class_name HttpChannel
extends RefCounted
## Tek bir sunucuya açık tutulan (keep-alive) HTTP bağlantısı ve istek kuyruğu.
## Saniyede birkaç yazma yapıldığı için her istekte yeni TLS bağlantısı açmak yerine
## bağlantı yeniden kullanılır. Aynı `key` ile kuyruğa giren eski istek, yenisiyle
## değiştirilir (ör. yalnızca en son durum paketi gönderilir).
##
## Kullanım: her karede poll() çağrılır. request() bir Dictionary döndürür;
## istek bitince içine "done"=true, "code", "body", "headers" yazılır ve
## varsa callback(result) çağrılır.

var _host := ""
var _port := 0
var _tls := false
var _client := HTTPClient.new()
var _queue: Array = []
var _current: Dictionary = {}
var _body := PackedByteArray()
var _connecting := false
var _fail_count := 0


func _init(base_url: String) -> void:
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


func request(method: int, path: String, body := "", headers: PackedStringArray = [], key := "", callback := Callable()) -> Dictionary:
	var r := {"method": method, "path": path, "body": body, "headers": headers,
		"key": key, "callback": callback, "done": false, "code": 0, "text": "", "resp_headers": {}}
	if key != "":
		for i in _queue.size():
			if _queue[i]["key"] == key:
				_queue[i]["done"] = true  # eskisi gönderilmeden atlanır
				_queue[i] = r
				return r
	_queue.append(r)
	return r


func busy() -> bool:
	return not _current.is_empty() or not _queue.is_empty()


func close() -> void:
	_client.close()
	_queue.clear()
	_current = {}


func poll() -> void:
	_client.poll()
	var st := _client.get_status()

	if _current.is_empty():
		if _queue.is_empty():
			return
		if st == HTTPClient.STATUS_DISCONNECTED or st == HTTPClient.STATUS_CONNECTION_ERROR \
				or st == HTTPClient.STATUS_CANT_CONNECT or st == HTTPClient.STATUS_CANT_RESOLVE \
				or st == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			if not _connecting or st != HTTPClient.STATUS_DISCONNECTED:
				_client.close()
				var opts: TLSOptions = TLSOptions.client() if _tls else null
				_client.connect_to_host(_host, _port, opts)
				_connecting = true
			return
		if st != HTTPClient.STATUS_CONNECTED:
			return  # bağlanıyor / çözümleniyor
		_connecting = false
		_current = _queue.pop_front()
		var hdrs := PackedStringArray(_current["headers"])
		var has_ct := false
		for h in hdrs:
			if h.to_lower().begins_with("content-type"):
				has_ct = true
		if not has_ct:
			hdrs.append("Content-Type: application/json")
		var err := _client.request(_current["method"], _current["path"], hdrs, _current["body"])
		if err != OK:
			_finish(0, "")
		_body = PackedByteArray()
		return

	match st:
		HTTPClient.STATUS_REQUESTING:
			return
		HTTPClient.STATUS_BODY:
			var chunk := _client.read_response_body_chunk()
			if chunk.size() > 0:
				_body.append_array(chunk)
			return
		HTTPClient.STATUS_CONNECTED:
			if _client.has_response():
				_current["resp_headers"] = _client.get_response_headers_as_dictionary()
				_finish(_client.get_response_code(), _body.get_string_from_utf8())
			else:
				_finish(0, "")
		_:
			# Bağlantı koptu: isteği bir kez yeniden dene.
			_client.close()
			_connecting = false
			_fail_count += 1
			if _fail_count <= 3:
				_queue.push_front(_current)
				_current = {}
			else:
				_fail_count = 0
				_finish(0, "")


func _finish(code: int, text: String) -> void:
	if code > 0:
		_fail_count = 0
	var r := _current
	_current = {}
	r["done"] = true
	r["code"] = code
	r["text"] = text
	if r["callback"].is_valid():
		r["callback"].call(r)
