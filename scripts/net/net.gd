extends Node
## Çok oyunculu oda yönetimi (autoload: Net).
##
## Veritabanı düzeni:  rooms/<4 haneli kod>/
##   meta:    {host, created, status: "lobby" | "playing"}
##   players: {<uid>: {name, color, icon, t}}
##   hb:      {<uid>: sunucu saati}            kalp atışı (2 sn'de bir)
##   setup:   "<json>"   maç başında harita + oyuncular + uid->slot (host yazar)
##   snap:    "<json>"   saniyede 5 kez maç durumu (host yazar)
##   cmds:    {<push id>: {uid, c: "<json komut>"}}   oyuncu hamleleri
##   end:     {reason: "win" | "disconnect" | "left", winner?, by?}
##   emo:     {<uid>: {e: ifade no, n: sayaç}}   maç içi ifade (emoji)
##   rematch: {<uid>: true}   maç sonu rövanş oyu; herkes isteyince host yeni maç kurar
##
## Host maçı hesaplar; diğerleri komut gönderir ve host'un durumunu çizer.
## Herhangi bir oyuncunun bağlantısı koparsa maç herkes için biter.

signal status(text: String)
signal failed(message: String)
signal room_ready(code: String)
signal lobby_changed(players: Array)
signal match_started(setup: Dictionary, my_slot: int)
signal snapshot_received(snap: Dictionary)
signal command_received(slot: int, cmd: Dictionary)
signal match_ended(info: Dictionary)
signal emote_received(slot: int, emote: int)
## Rövanş durumu: votes = oy veren slotlar, total = maçtaki oyuncu, gone = biri ayrıldı
signal rematch_changed(info: Dictionary)

var fb: Firebase
var code := ""
var is_host := false
var my_slot := -1
var in_room := false
var in_match := false
var setup: Dictionary = {}

var _room := {}            # odanın yerel kopyası
var _streams: Array = []
var _slots := {}           # uid -> slot
var _seen_cmds := {}
var _last_seen := {}       # uid -> ticks (son kalp atışı)
var _hb_timer := 0.0
var _lobby_since := 0
var _ended := false
var _last_snap := ""
var _waiting_ready: Array = []
var _emo_seen := {}        # uid -> son görülen sayaç
var _emo_n := 0
var _round := 0
var _gone := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if fb == null:
		return
	fb.poll()
	if not in_room:
		return
	_hb_timer -= delta
	if _hb_timer <= 0.0:
		_hb_timer = NetConfig.HEARTBEAT_SEC
		fb.put("rooms/%s/hb/%s" % [code, fb.uid], Firebase.SERVER_TIME, Callable(), "hb")
	if is_host and not in_match and Time.get_ticks_msec() - _lobby_since > NetConfig.room_ttl_ms():
		_fail("Oda süresi doldu (%d dakika)." % int(NetConfig.room_ttl_ms() / 60000))
		leave()
		return
	if in_match and not _ended:
		var now := Time.get_ticks_msec()
		for uid in _slots.keys():
			if uid == fb.uid:
				continue
			if now - int(_last_seen.get(uid, now)) > NetConfig.DISCONNECT_SEC * 1000:
				var who: String = _room.get("players", {}).get(uid, {}).get("name", "Bir oyuncu")
				_end_match({"reason": "disconnect", "by": uid, "name": who})
				return


func available() -> bool:
	return NetConfig.configured()


func _ensure_ready(then: Callable) -> void:
	if fb == null:
		fb = Firebase.new()
		fb.ready_changed.connect(_on_ready_changed)
	if fb.is_ready():
		then.call()
		return
	_waiting_ready.append(then)
	status.emit("Sunucuya bağlanılıyor...")
	fb.sign_in()


func _on_ready_changed(ok: bool, message: String) -> void:
	var waiting := _waiting_ready
	_waiting_ready = []
	if not ok:
		_fail(message)
		return
	for w in waiting:
		w.call()


func _fail(message: String) -> void:
	status.emit("")
	failed.emit(message)


static func me() -> Dictionary:
	return {"name": SaveData.player_name, "color": SaveData.color_index, "icon": SaveData.icon_index,
		"t": Firebase.SERVER_TIME}


# ---------------------------------------------------------------- oda kur

func create_room() -> void:
	_reset()
	_ensure_ready(func(): _try_code(0))


func _try_code(attempt: int) -> void:
	if attempt >= 15:
		_fail("Boş oda kodu bulunamadı, tekrar dene.")
		return
	var c := "%04d" % randi_range(0, 9999)
	status.emit("Oda kuruluyor...")
	fb.get_value("rooms/" + c, func(code_: int, data: Variant, etag: String):
		if code_ != 200:
			_fail("Sunucu hatası (%d)" % code_)
			return
		if not _is_free(data):
			_try_code(attempt + 1)
			return
		var room := {
			"meta": {"host": fb.uid, "created": Firebase.SERVER_TIME, "status": "lobby"},
			"players": {fb.uid: me()},
		}
		fb.put("rooms/" + c, room, func(put_code: int):
			if put_code == 200:
				is_host = true
				_enter(c)
			elif put_code == 412 or put_code == 401:
				_try_code(attempt + 1)  # bu arada başkası aldı
			else:
				_fail("Oda kurulamadı (%d)" % put_code), "", etag), true)


## Kod boş mu? (hiç yok, bitmiş veya süresi geçmiş lobi)
func _is_free(data: Variant) -> bool:
	if not (data is Dictionary):
		return true
	if data.has("end"):
		return true
	var meta: Dictionary = data.get("meta", {})
	if meta.is_empty():
		return true
	if meta.get("status") == "lobby" and fb.server_time() - int(meta.get("created", 0)) > NetConfig.room_ttl_ms():
		return true
	return false


# ---------------------------------------------------------------- katıl

func join_room(c: String) -> void:
	_reset()
	if not c.is_valid_int() or c.length() != 4:
		_fail("Kod 4 haneli olmalı.")
		return
	_ensure_ready(func():
		status.emit("Odaya bağlanılıyor...")
		fb.get_value("rooms/" + c, func(code_: int, data: Variant, _etag: String):
			if code_ != 200:
				_fail("Sunucu hatası (%d)" % code_)
				return
			if not (data is Dictionary) or not data.has("meta"):
				_fail("Bu kodla bir oda bulunamadı.")
				return
			var meta: Dictionary = data["meta"]
			if data.has("end"):
				_fail("Bu odadaki oyun bitmiş.")
				return
			if meta.get("status") != "lobby":
				_fail("Bu odada oyun başlamış.")
				return
			if fb.server_time() - int(meta.get("created", 0)) > NetConfig.room_ttl_ms():
				_fail("Bu kodun süresi dolmuş.")
				return
			var players: Dictionary = data.get("players", {})
			if players.size() >= NetConfig.MAX_PLAYERS and not players.has(fb.uid):
				_fail("Oda dolu (en fazla %d oyuncu)." % NetConfig.MAX_PLAYERS)
				return
			fb.put("rooms/%s/players/%s" % [c, fb.uid], me(), func(put_code: int):
				if put_code == 200:
					is_host = false
					_enter(c)
				else:
					_fail("Odaya katılınamadı (%d)" % put_code))))


# ---------------------------------------------------------------- odada

func _enter(c: String) -> void:
	code = c
	in_room = true
	_lobby_since = Time.get_ticks_msec()
	_hb_timer = 0.0
	status.emit("")
	# Host kendi yazdığı durum paketini geri indirmesin diye sadece gereken yolları dinler.
	var paths := ["players", "hb", "cmds", "end", "emo", "rematch"] if is_host else [""]
	for p in paths:
		var full := "rooms/%s/%s" % [code, p] if p != "" else "rooms/" + code
		var s := fb.listen(full)
		s.event.connect(_on_event.bind(p))
		_streams.append(s)
	room_ready.emit(code)


func _on_event(kind: String, path: String, data: Variant, prefix: String) -> void:
	if kind != "put" and kind != "patch":
		return
	var parts: Array = []
	if prefix != "":
		parts.append(prefix)
	for p in path.split("/", false):
		parts.append(p)
	if kind == "put":
		_room = _set_at(_room, parts, data)
	else:
		for k in (data as Dictionary).keys():
			var sub := parts.duplicate()
			for p in String(k).split("/", false):
				sub.append(p)
			_room = _set_at(_room, sub, data[k])
	var top: String = parts[0] if parts.size() > 0 else ""
	_changed(top)


static func _set_at(tree: Variant, parts: Array, value: Variant) -> Dictionary:
	var t: Dictionary = tree if tree is Dictionary else {}
	if parts.is_empty():
		return value if value is Dictionary else {}
	var k: String = parts[0]
	if parts.size() == 1:
		if value == null:
			t.erase(k)
		else:
			t[k] = value
		return t
	var child := _set_at(t.get(k), parts.slice(1), value)
	if child.is_empty():
		t.erase(k)
	else:
		t[k] = child
	return t


func _changed(top: String) -> void:
	var all := top == ""
	if all or top == "hb":
		var now := Time.get_ticks_msec()
		var hb: Dictionary = _room.get("hb", {})
		for uid in hb.keys():
			if _last_seen.get("v_" + uid) != hb[uid]:
				_last_seen["v_" + uid] = hb[uid]
				_last_seen[uid] = now
	if all or top == "players":
		lobby_changed.emit(lobby_players())
		if in_match and _ended:
			var present: Dictionary = _room.get("players", {})
			for uid in _slots.keys():
				if not present.has(uid):
					_gone = true
			rematch_changed.emit(rematch_info())
		if in_match:
			var ps: Dictionary = _room.get("players", {})
			for uid in _slots.keys():
				if not ps.has(uid) and not _ended:
					_end_match({"reason": "left", "by": uid})
					return
	if (all or top == "emo") and in_match and not _ended:
		var emo: Dictionary = _room.get("emo", {})
		for uid in emo.keys():
			var e: Variant = emo[uid]
			if uid == fb.uid or not (e is Dictionary) or not _slots.has(uid):
				continue
			var n := int(e.get("n", 0))
			if _emo_seen.get(uid, -1) != n:
				_emo_seen[uid] = n
				emote_received.emit(_slots[uid], int(e.get("e", 0)))
	if (all or top == "rematch") and _ended:
		rematch_changed.emit(rematch_info())
	if all or top == "end":
		var e: Variant = _room.get("end")
		if e is Dictionary and not _ended:
			_end_match(e, false)
			return
	if not is_host:
		if all or top == "meta":
			if not _room.has("meta") and in_room and _ended and not _gone:
				_gone = true  # host ayrıldı, oda silindi
				rematch_changed.emit(rematch_info())
			if not _room.has("meta") and in_room and not _ended:
				if in_match:
					_end_match({"reason": "left", "by": "host"}, false)
				else:
					_fail("Oda sahibi odayı kapattı.")
					leave()
				return
		if (all or top == "meta" or top == "setup") and not in_match:
			if _room.get("meta", {}).get("status") == "playing" and _room.get("setup") is String:
				_start_from_setup(JSON.parse_string(_room["setup"]))
		elif (all or top == "setup") and in_match and _ended and _room.get("setup") is String:
			# Rövanş: host yeni turun haritasını yazdı.
			var d: Variant = JSON.parse_string(_room["setup"])
			if d is Dictionary and int(d.get("round", 0)) > _round:
				_room.erase("end")
				_room.erase("snap")
				_ended = false
				_last_snap = ""
				_start_from_setup(d)
		if (all or top == "snap") and in_match and _room.get("snap") is String:
			var s: String = _room["snap"]
			if s != _last_snap:
				_last_snap = s
				var d: Variant = JSON.parse_string(s)
				if d is Dictionary:
					snapshot_received.emit(d)
	else:
		if (all or top == "cmds") and in_match:
			var cmds: Dictionary = _room.get("cmds", {})
			var keys := cmds.keys()
			keys.sort()
			for k in keys:
				if _seen_cmds.has(k):
					continue
				_seen_cmds[k] = true
				var e: Dictionary = cmds[k]
				var slot: int = _slots.get(e.get("uid", ""), -1)
				var cmd: Variant = JSON.parse_string(String(e.get("c", "")))
				if slot >= 0 and cmd is Dictionary:
					cmd["owner"] = slot  # oyuncu sadece kendi adına hamle yapabilir
					command_received.emit(slot, cmd)


## Lobideki oyuncular, katılma sırasına göre (host önce).
func lobby_players() -> Array:
	var out: Array = []
	var ps: Dictionary = _room.get("players", {})
	var host: String = _room.get("meta", {}).get("host", fb.uid if is_host else "")
	for uid in ps.keys():
		var p: Dictionary = ps[uid].duplicate()
		p["uid"] = uid
		p["host"] = uid == host
		out.append(p)
	out.sort_custom(func(a, b):
		if a["host"] != b["host"]:
			return a["host"]
		return float(a.get("t", 0)) < float(b.get("t", 0)))
	return out.slice(0, NetConfig.MAX_PLAYERS)


# ---------------------------------------------------------------- maç

## Host: lobideki oyuncularla maçı başlatır. build: func(players: Array) -> MatchState
func start_match(state: MatchState, uids: Array) -> void:
	_slots = {}
	for i in uids.size():
		_slots[uids[i]] = i
	var d := state.setup_dict()
	d["slots"] = _slots
	setup = d
	var now := Time.get_ticks_msec()
	for uid in uids:
		_last_seen[uid] = now
	fb.put("rooms/%s/setup" % code, JSON.stringify(d))
	fb.patch("rooms/%s/meta" % code, {"status": "playing"})
	my_slot = 0
	in_match = true
	match_started.emit(d, 0)


func _start_from_setup(d: Variant) -> void:
	if not (d is Dictionary):
		return
	var slots: Dictionary = d.get("slots", {})
	if not slots.has(fb.uid):
		_fail("Oda dolu, maça alınamadın.")
		leave()
		return
	setup = d
	_round = int(d.get("round", 0))
	_slots = {}
	for uid in slots.keys():
		_slots[uid] = int(slots[uid])
	my_slot = _slots[fb.uid]
	var now := Time.get_ticks_msec()
	for uid in _slots.keys():
		_last_seen[uid] = now
	in_match = true
	match_started.emit(d, my_slot)


func send_command(cmd: Dictionary) -> void:
	if is_host or not in_match or _ended:
		return
	fb.push("rooms/%s/cmds" % code, {"uid": fb.uid, "c": JSON.stringify(cmd)})


func send_snapshot(snap: Dictionary) -> void:
	if not is_host or not in_match or _ended:
		return
	fb.put("rooms/%s/snap" % code, JSON.stringify(snap), Callable(), "snap")


## Maç içi ifade gönder (0..5).
func send_emote(e: int) -> void:
	if not in_match or _ended:
		return
	_emo_n += 1
	fb.put("rooms/%s/emo/%s" % [code, fb.uid], {"e": e, "n": _emo_n})


## Maç sonu rövanş oyu.
func vote_rematch() -> void:
	if not in_match or not _ended or _gone:
		return
	fb.put("rooms/%s/rematch/%s" % [code, fb.uid], true)
	var r: Variant = _room.get("rematch", {})
	if not (r is Dictionary):
		r = {}
	r[fb.uid] = true
	_room["rematch"] = r
	rematch_changed.emit(rematch_info())


func rematch_info() -> Dictionary:
	var votes: Array = []
	var r: Variant = _room.get("rematch", {})
	if r is Dictionary:
		for uid in r.keys():
			if _slots.has(uid):
				votes.append(_slots[uid])
	return {"votes": votes, "total": _slots.size(), "gone": _gone}


## Host: herkes rövanş istedi; aynı oyuncularla yeni harita kurar.
func start_rematch(state: MatchState) -> void:
	if not is_host or not _ended or _gone:
		return
	_round += 1
	var d := state.setup_dict()
	d["slots"] = _slots
	d["round"] = _round
	setup = d
	fb.patch("rooms/" + code, {"end": null, "rematch": null, "snap": null, "cmds": null, "emo": null,
		"setup": JSON.stringify(d), "meta/status": "playing"})
	_room.erase("end")
	_room.erase("rematch")
	_room.erase("cmds")
	_room.erase("emo")
	_seen_cmds = {}
	_ended = false
	var now := Time.get_ticks_msec()
	for uid in _slots.keys():
		_last_seen[uid] = now
	match_started.emit(d, 0)


## Host: maç bitti, kazananı bildir.
func finish(winner_slot: int) -> void:
	if _ended:
		return
	_end_match({"reason": "win", "winner": winner_slot})


func _end_match(info: Dictionary, write := true) -> void:
	if _ended:
		return
	_ended = true
	if write and in_room:
		info["by"] = info.get("by", fb.uid)
		fb.put("rooms/%s/end" % code, info)
	match_ended.emit(info)


## Odadan/maçtan çık. Maç sürüyorsa herkes için biter.
func leave() -> void:
	if fb == null:
		return
	if in_room:
		if in_match and not _ended:
			_end_match({"reason": "left", "by": fb.uid})
		if is_host and (not in_match or _ended):
			fb.remove("rooms/" + code)  # oda temizlenir
		elif not in_match or _ended:
			fb.remove("rooms/%s/players/%s" % [code, fb.uid])
	fb.stop_listening()
	_streams.clear()
	in_room = false
	in_match = false


func slot_name(slot: int) -> String:
	for uid in _slots.keys():
		if _slots[uid] == slot:
			return _room.get("players", {}).get(uid, {}).get("name", "Oyuncu")
	return "Oyuncu"


func _reset() -> void:
	if in_room:
		leave()
	code = ""
	is_host = false
	my_slot = -1
	in_match = false
	setup = {}
	_room = {}
	_slots = {}
	_seen_cmds = {}
	_last_seen = {}
	_ended = false
	_last_snap = ""
	_emo_seen = {}
	_emo_n = 0
	_round = 0
	_gone = false
