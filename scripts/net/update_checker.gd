class_name UpdateChecker
extends Node
## GitHub'daki "son-surum" yayınından version.json okuyarak yeni sürüm var mı bakar.
## version.json'u GitHub Actions her derlemede üretir:
##   {"code": 19, "name": "0.1.19", "apk": "<indirme linki>", "notes": ["...", "..."]}
## Kullanım: var u := UpdateChecker.new(); add_child(u); u.finished.connect(...); u.check()

signal finished(result: Dictionary)  # {ok, newer, current, latest, apk, notes, error}

const VERSION_URL := "https://github.com/ozguryilmazz/fetih/releases/download/son-surum/version.json"

var _http: HTTPRequest


static func version_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-url="):
			return a.substr(13)
	return VERSION_URL


static func current_name() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.1.0"))


## "0.1.18" -> 18 (derleme numarası). Bilinmiyorsa 0.
static func code_of(version_name: String) -> int:
	var parts := version_name.split(".")
	return int(parts[-1]) if parts.size() > 0 and parts[-1].is_valid_int() else 0


static func evaluate(data: Variant, current: String) -> Dictionary:
	var r := {"ok": false, "newer": false, "current": current, "latest": "", "apk": "", "notes": [], "error": ""}
	if not (data is Dictionary) or not data.has("code") or not data.has("apk"):
		r["error"] = "Sürüm bilgisi okunamadı."
		return r
	r["ok"] = true
	r["latest"] = String(data.get("name", "0.1.%d" % int(data["code"])))
	r["apk"] = String(data["apk"])
	r["notes"] = data.get("notes", []) if data.get("notes") is Array else []
	r["newer"] = int(data["code"]) > code_of(current)
	return r


func check() -> void:
	if _http:
		return
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.max_redirects = 8  # GitHub indirme linki başka sunucuya yönlendirir
	add_child(_http)
	_http.request_completed.connect(_on_done)
	var url := version_url() + "?t=%d" % Time.get_unix_time_from_system()  # önbelleği atla
	if _http.request(url) != OK:
		_finish({"ok": false, "error": "İstek gönderilemedi."})


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish({"ok": false, "error": "İnternete bağlanılamadı."})
		return
	if code != 200:
		_finish({"ok": false, "error": "Sunucu yanıtı: %d" % code})
		return
	_finish(evaluate(JSON.parse_string(body.get_string_from_utf8()), current_name()))


func _finish(r: Dictionary) -> void:
	if _http:
		_http.queue_free()
		_http = null
	if not r.has("current"):
		r["current"] = current_name()
	finished.emit(r)
