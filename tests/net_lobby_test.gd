extends SceneTree
## Ağ testi (sahte sunucu ile, CI'da çalışmaz):
##   host:   godot --headless -s tests/net_lobby_test.gd -- --fb=http://127.0.0.1:9050 --profile=a --role=host --dir=/tmp/x
##   client: godot --headless -s tests/net_lobby_test.gd -- --fb=http://127.0.0.1:9050 --profile=b --role=client --dir=/tmp/x
## Host oda kurar ve kodu dosyaya yazar; client önce yanlış kodu dener, sonra katılır.
## Host maçı başlatır; client komut yollar, host durum paketi yollar.

var role := ""
var dir := ""
var net: Node
var log_lines: Array = []
var got := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		if a.begins_with("--dir="):
			dir = a.substr(6)
	net = root.get_node("Net")
	net.failed.connect(func(m): _log("failed: " + m); got["failed"] = m)
	net.room_ready.connect(func(c): _log("room " + c); got["room"] = c)
	net.lobby_changed.connect(func(p): got["lobby"] = p.size())
	net.match_started.connect(func(_s, slot): _log("started slot %d" % slot); got["started"] = slot)
	net.snapshot_received.connect(func(s): got["snaps"] = got.get("snaps", 0) + 1; got["last_t"] = s["t"])
	net.command_received.connect(func(slot, c): _log("cmd from %d: %s" % [slot, c]); got["cmd"] = c)
	net.match_ended.connect(func(i): _log("ended " + str(i)); got["ended"] = i)
	_run.call_deferred()


func _log(s: String) -> void:
	print("[%s %.1f] %s" % [role, Time.get_ticks_msec() / 1000.0, s])


func _wait(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > sec * 1000:
			return false
		await process_frame
	return true


func _check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  HATA ") + "[%s] %s" % [role, msg])
	if not ok:
		got["fail"] = true


func _run() -> void:
	if role == "host":
		await _host()
	elif role == "expire_host":
		net.create_room()
		await _wait(func(): return got.has("room"), 10)
		FileAccess.open(dir + "/code_expire", FileAccess.WRITE).store_string(got["room"])
		_check(await _wait(func(): return got.has("failed"), 15), "host lobisi süre dolunca kapandı (%s)" % got.get("failed", ""))
	elif role == "expire_client":
		await _wait(func(): return FileAccess.file_exists(dir + "/code_expire"), 20)
		var c := FileAccess.get_file_as_string(dir + "/code_expire")
		await create_timer(4.0).timeout
		net.join_room(c)
		await _wait(func(): return got.has("failed") or got.has("room"), 15)
		_check(got.get("failed", "").contains("süresi") or got.get("failed", "").contains("bulunamadı"), "süresi dolan koda katılınamadı (%s)" % got.get("failed", "-"))
	else:
		await _client()
	print("SONUC: ", "HATA" if got.get("fail", false) else "TAMAM")
	quit(1 if got.get("fail", false) else 0)


func _host() -> void:
	net.create_room()
	_check(await _wait(func(): return got.has("room"), 15), "oda kuruldu")
	FileAccess.open(dir + "/code", FileAccess.WRITE).store_string(got.get("room", ""))
	_check(await _wait(func(): return got.get("lobby", 0) >= 2, 30), "ikinci oyuncu lobide göründü")
	var lp: Array = net.lobby_players()
	_check(lp.size() == 2 and lp[0]["host"], "lobi sırası: önce host")
	var players: Array = []
	for i in lp.size():
		players.append(MatchState.make_player(i, lp[i]["name"], i, 0, false, {}))
	var st := MatchState.create(5, players, 9, 5, 15)
	net.start_match(st, lp.map(func(p): return p["uid"]))
	_check(await _wait(func(): return got.has("cmd"), 20), "client komutu host'a ulaştı")
	_check(int(got.get("cmd", {}).get("owner", -1)) == 1, "komutun sahibi client'ın slotu (1) olarak zorlandı")
	for i in 15:
		st.time = i * 0.2
		net.send_snapshot(st.snapshot())
		await create_timer(0.2).timeout
	_check(await _wait(func(): return got.has("ended"), 30), "client kopunca host maçı bitirdi")
	_check(got.get("ended", {}).get("reason") == "disconnect", "bitiş nedeni: bağlantı koptu")


func _client() -> void:
	await _wait(func(): return FileAccess.file_exists(dir + "/code"), 20)
	var c := FileAccess.get_file_as_string(dir + "/code")
	var wrong := "%04d" % ((int(c) + 1) % 10000)
	net.join_room(wrong)
	await _wait(func(): return got.has("failed"), 10)
	_check(got.get("failed", "").contains("bulunamadı"), "yanlış kod reddedildi (%s)" % got.get("failed", ""))
	got.erase("failed")
	net.join_room(c)
	_check(await _wait(func(): return got.has("room"), 15), "odaya katıldı")
	_check(await _wait(func(): return got.has("started"), 30), "maç başladı")
	_check(got.get("started", -1) == 1, "slot 1 atandı")
	var setup: Dictionary = net.setup
	var st := MatchState.from_setup(setup)
	_check(st.bases.size() == 9 and st.players.size() == 2, "harita ve oyuncular alındı")
	net.send_command({"type": "send", "owner": 0, "sources": [1, 2], "targets": [3]})
	_check(await _wait(func(): return got.get("snaps", 0) >= 5, 20), "durum paketleri geliyor (%d)" % got.get("snaps", 0))
	st.apply_snapshot(JSON.parse_string(JSON.stringify(st.snapshot())))
	# Kopma: heartbeat'i kesip çık (süreç öldürülmüş gibi).
	print("SONUC: ", "HATA" if got.get("fail", false) else "TAMAM")
	OS.kill(OS.get_process_id())
