class_name EventStream
extends RefCounted
## Firebase Realtime Database canlı dinleme (Server-Sent Events).
## Bir yoldaki her değişiklik "put" / "patch" olayı olarak gelir:
##   {"path": "/alt/yol", "data": ...}
## Bağlantı koparsa kendiliğinden yeniden bağlanır (yeniden bağlanınca sunucu
## önce o yolun tamamını "put /" olarak tekrar gönderir).

signal event(kind: String, path: String, data: Variant)

var _host := ""
var _port := 0
var _tls := false
var _path := ""
var _client := HTTPClient.new()
var _buffer := ""
var _requested := false
var _retry_at := 0
var _closed := false
## Son olay veya keep-alive'ın geldiği an (ms). Bağlantı sağlığı için.
var last_activity := 0


func _init(base_url: String, path_with_query: String) -> void:
	var u := base_url
	_tls = u.begins_with("https://")
	u = u.trim_prefix("https://").trim_prefix("http://")
	var slash := u.find("/")
	if slash >= 0:
		u = u.substr(0, slash)
	var colon := u.find(":")
	if colon >= 0:
		_host = u.substr(0, colon)
		_port = int(u.substr(colon + 1))
	else:
		_host = u
		_port = 443 if _tls else 80
	_path = path_with_query
	last_activity = Time.get_ticks_msec()


## Token yenilenince adres değişir; yeniden bağlanır.
func set_path(path_with_query: String) -> void:
	_path = path_with_query
	_restart()


func close() -> void:
	_closed = true
	_client.close()


func _restart() -> void:
	_client.close()
	_requested = false
	_buffer = ""


func poll() -> void:
	if _closed:
		return
	_client.poll()
	var st := _client.get_status()
	match st:
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, \
				HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			if Time.get_ticks_msec() < _retry_at:
				return
			_retry_at = Time.get_ticks_msec() + 1000
			_requested = false
			_buffer = ""
			_client.close()
			var opts: TLSOptions = TLSOptions.client() if _tls else null
			_client.connect_to_host(_host, _port, opts)
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				_requested = true
				_client.request(HTTPClient.METHOD_GET, _path, ["Accept: text/event-stream"])
			elif _client.has_response():
				# Akış bitti (sunucu kapattı veya hata kodu döndü): yeniden bağlan.
				_restart()
				_retry_at = Time.get_ticks_msec() + 1000
		HTTPClient.STATUS_BODY:
			var chunk := _client.read_response_body_chunk()
			if chunk.size() > 0:
				last_activity = Time.get_ticks_msec()
				_buffer += chunk.get_string_from_utf8()
				_parse()


func _parse() -> void:
	_buffer = _buffer.replace("\r\n", "\n")
	while true:
		var end := _buffer.find("\n\n")
		if end < 0:
			return
		var block := _buffer.substr(0, end)
		_buffer = _buffer.substr(end + 2)
		var kind := ""
		var data := ""
		for line in block.split("\n"):
			if line.begins_with("event:"):
				kind = line.substr(6).strip_edges()
			elif line.begins_with("data:"):
				data += line.substr(5).strip_edges()
		if kind == "put" or kind == "patch":
			var parsed: Variant = JSON.parse_string(data)
			if parsed is Dictionary:
				event.emit(kind, String(parsed.get("path", "/")), parsed.get("data"))
		elif kind == "cancel" or kind == "auth_revoked":
			event.emit(kind, "/", data)
