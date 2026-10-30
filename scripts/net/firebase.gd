class_name Firebase
extends RefCounted
## Firebase Realtime Database REST istemcisi + anonim giriş.
## Kimlik (uid) cihazda saklanır, her açılışta token yenilenir.

signal ready_changed(ok: bool, message: String)

var uid := ""
var _id_token := ""
var _refresh_token := ""
var _token_expires := 0  # ms (ticks)
var _db: HttpChannel
var _auth: HttpChannel
var _streams: Array = []  # [{stream, path}]
var _signing_in := false
## Son yanıtın sunucu saati (ms, Date başlığından). Oda süresi için.
var server_now_ms := 0
var _server_now_at := 0


func _init() -> void:
	_db = HttpChannel.new(NetConfig.db_url())
	_auth = HttpChannel.new(NetConfig.auth_url())


func poll() -> void:
	_db.poll()
	_auth.poll()
	_poll_refresh()
	for s in _streams:
		s["stream"].poll()
	if _id_token != "" and Time.get_ticks_msec() > _token_expires and not _signing_in:
		_refresh()


func is_ready() -> bool:
	return _id_token != ""


## Sunucu saatinin şu anki tahmini (ms).
func server_time() -> int:
	if server_now_ms == 0:
		return 0
	return server_now_ms + (Time.get_ticks_msec() - _server_now_at)


# ---------------------------------------------------------------- giriş

func _auth_file() -> String:
	return "user://fb_auth_%s.cfg" % NetConfig.profile()


func sign_in() -> void:
	if _signing_in or is_ready():
		return
	_signing_in = true
	var cf := ConfigFile.new()
	if cf.load(_auth_file()) == OK:
		_refresh_token = cf.get_value("auth", "refresh", "")
		uid = cf.get_value("auth", "uid", "")
	if _refresh_token != "":
		_refresh()
		return
	var url := "/v1/accounts:signUp?key=%s" % NetConfig.api_key()
	_auth.request(HTTPClient.METHOD_POST, url, JSON.stringify({"returnSecureToken": true}), [], "", func(r):
		_signing_in = false
		var d: Variant = JSON.parse_string(r["text"]) if r["text"] != "" else null
		if r["code"] != 200 or not (d is Dictionary):
			ready_changed.emit(false, "Sunucuya bağlanılamadı (giriş %d)" % r["code"])
			return
		uid = d["localId"]
		_set_token(d["idToken"], d["refreshToken"], int(d.get("expiresIn", "3600"))))


func _refresh() -> void:
	_signing_in = true
	var ch := HttpChannel.new(NetConfig.token_url())
	_auth_refresh_channel = ch
	# Google'ın belgelediği biçim: form verisi.
	var body := "grant_type=refresh_token&refresh_token=" + _refresh_token.uri_encode()
	ch.request(HTTPClient.METHOD_POST, "/v1/token?key=%s" % NetConfig.api_key(), body,
			["Content-Type: application/x-www-form-urlencoded"], "", func(r):
		_signing_in = false
		var d: Variant = JSON.parse_string(r["text"]) if r["text"] != "" else null
		if r["code"] != 200 or not (d is Dictionary):
			# Kayıtlı kimlik geçersiz: yeni anonim hesap aç.
			_refresh_token = ""
			_id_token = ""
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_auth_file()))
			sign_in()
			return
		uid = d["user_id"]
		_set_token(d["id_token"], d["refresh_token"], int(d.get("expires_in", "3600"))))


var _auth_refresh_channel: HttpChannel


func _poll_refresh() -> void:
	if _auth_refresh_channel:
		_auth_refresh_channel.poll()


func _set_token(id_token: String, refresh: String, expires_sec: int) -> void:
	var first := _id_token == ""
	_id_token = id_token
	_refresh_token = refresh
	_token_expires = Time.get_ticks_msec() + (expires_sec - 300) * 1000
	var cf := ConfigFile.new()
	cf.set_value("auth", "refresh", refresh)
	cf.set_value("auth", "uid", uid)
	cf.save(_auth_file())
	for s in _streams:
		s["stream"].set_path(_url(s["path"]))
	if first:
		ready_changed.emit(true, "")


# ---------------------------------------------------------------- veritabanı

func _url(path: String) -> String:
	var u := "/%s.json" % path.trim_prefix("/")
	if _id_token != "":
		u += "?auth=" + _id_token
	return u


func _note_time(r: Dictionary) -> void:
	var h: Dictionary = r.get("resp_headers", {})
	for k in h.keys():
		if String(k).to_lower() == "date":
			var unix := _parse_http_date(String(h[k]))
			if unix > 0:
				server_now_ms = unix * 1000
				_server_now_at = Time.get_ticks_msec()


static func _parse_http_date(s: String) -> int:
	# "Fri, 30 Oct 2026 08:15:01 GMT"
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var p := s.split(" ", false)
	if p.size() < 5:
		return 0
	var m := months.find(p[2]) + 1
	if m <= 0:
		return 0
	var iso := "%s-%02d-%02dT%s" % [p[3], m, int(p[1]), p[4]]
	return Time.get_unix_time_from_datetime_string(iso)


## Callback: func(code: int, data: Variant, etag: String)
func get_value(path: String, cb: Callable, want_etag := false) -> void:
	var hdrs := PackedStringArray()
	if want_etag:
		hdrs.append("X-Firebase-ETag: true")
	_db.request(HTTPClient.METHOD_GET, _url(path), "", hdrs, "", func(r):
		_note_time(r)
		var etag := ""
		for k in r["resp_headers"].keys():
			if String(k).to_lower() == "etag":
				etag = String(r["resp_headers"][k])
		cb.call(r["code"], JSON.parse_string(r["text"]) if r["text"] != "" else null, etag))


func put(path: String, value: Variant, cb := Callable(), key := "", if_match := "") -> void:
	var hdrs := PackedStringArray()
	if if_match != "":
		hdrs.append("if-match: " + if_match)
	_db.request(HTTPClient.METHOD_PUT, _url(path), JSON.stringify(value), hdrs, key, func(r):
		_note_time(r)
		if cb.is_valid():
			cb.call(r["code"]))


func patch(path: String, value: Dictionary, cb := Callable()) -> void:
	_db.request(HTTPClient.METHOD_PATCH, _url(path), JSON.stringify(value), [], "", func(r):
		if cb.is_valid():
			cb.call(r["code"]))


## Listeye benzersiz anahtarla ekler.
func push(path: String, value: Variant, cb := Callable()) -> void:
	_db.request(HTTPClient.METHOD_POST, _url(path), JSON.stringify(value), [], "", func(r):
		if cb.is_valid():
			cb.call(r["code"]))


func remove(path: String, cb := Callable()) -> void:
	_db.request(HTTPClient.METHOD_DELETE, _url(path), "", [], "", func(r):
		if cb.is_valid():
			cb.call(r["code"]))


## Bir yolu canlı dinler. Dönen EventStream'in `event` sinyaline bağlanılır.
func listen(path: String) -> EventStream:
	var s := EventStream.new(NetConfig.db_url(), _url(path))
	_streams.append({"stream": s, "path": path})
	return s


func stop_listening() -> void:
	for s in _streams:
		s["stream"].close()
	_streams.clear()


func pending_writes() -> bool:
	return _db.busy()


const SERVER_TIME := {".sv": "timestamp"}
