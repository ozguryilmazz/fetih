extends SceneTree
## Uçtan uca çok oyunculu test (sahte sunucu ile, CI'da çalışmaz). Gerçek ekranlar kullanılır:
## host Çok Oyunculu ekranında oda kurar, client kodu yazıp katılır, host başlatır,
## iki tarafı da bot oynar (dokunma yerine game._issue ile). Roller: host, client, client_kill.

var role := ""
var dir := ""
var got := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		if a.begins_with("--dir="):
			dir = a.substr(6)
	_run.call_deferred()


func _log(s: String) -> void:
	print("[%s %.1f] %s" % [role, Time.get_ticks_msec() / 1000.0, s])


func _check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  HATA ") + "[%s] %s" % [role, msg])
	if not ok:
		got["fail"] = true


func _wait(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > sec * 1000:
			return false
		await process_frame
	return true


func _scene_name() -> String:
	return current_scene.name if current_scene else ""


func _run() -> void:
	var net: Node = root.get_node("Net")
	net.match_ended.connect(func(i): got["end"] = i)
	change_scene_to_file("res://scenes/multiplayer.tscn")
	await _wait(func(): return _scene_name() == "Multiplayer", 5)
	var mp: Node = current_scene
	if role.begins_with("host"):
		mp._status.text = ""
		net.create_room()
		_check(await _wait(func(): return net.code != "" and mp._lobby.visible, 15), "lobi açıldı, kod: %s" % net.code)
		FileAccess.open(dir + "/code", FileAccess.WRITE).store_string(net.code)
		_check(await _wait(func(): return not mp._start_btn.disabled, 30), "arkadaş katıldı, Başlat açıldı")
		mp._start()
	else:
		await _wait(func(): return FileAccess.file_exists(dir + "/code"), 20)
		mp._code_edit.text = FileAccess.get_file_as_string(dir + "/code")
		mp._join()
		_check(await _wait(func(): return mp._lobby.visible, 15), "lobiye girdi")
	_check(await _wait(func(): return _scene_name() == "Game", 30), "oyun ekranı açıldı")
	await process_frame
	var game: Node2D = current_scene
	_check(game.online and game.my_id == (0 if role.begins_with("host") else 1), "çevrimiçi mod, slot %d" % game.my_id)
	Engine.time_scale = 1.0 if role.ends_with("_kill") or FileAccess.file_exists(dir + "/slow") else 3.0
	var bot := BotAI.new(game.my_id, 0.8, 99 if role == "host" else 7)
	var sent := 0
	var t0 := Time.get_ticks_msec()
	var snaps := [0]
	if role != "host":
		net.snapshot_received.connect(func(_s): snaps[0] += 1)
	var host_cmds := [0]
	if role == "host":
		net.command_received.connect(func(_s, _c): host_cmds[0] += 1)
	while not game.finished:
		await process_frame
		for c in bot.update(game.state, 1.0 / 60.0 * Engine.time_scale):
			game._issue(c)
			sent += 1
		if role.ends_with("_kill") and Time.get_ticks_msec() - t0 > 2500:
			FileAccess.open(dir + "/expect_disconnect", FileAccess.WRITE).store_string("1")
		if role.ends_with("_kill") and Time.get_ticks_msec() - t0 > 3000:
			_log("süreç öldürülüyor (bağlantı kopması)")
			OS.kill(OS.get_process_id())
		if Time.get_ticks_msec() - t0 > 150000:
			break
	Engine.time_scale = 1.0
	var e: Dictionary = got.get("end", {})
	_log("bitiş: %s, gönderilen hamle %d, gelen durum paketi %d, host'a gelen komut %d" % [e, sent, snaps[0], host_cmds[0]])
	FileAccess.open(dir + "/end_" + role, FileAccess.WRITE).store_string(JSON.stringify(e))
	if FileAccess.file_exists(dir + "/expect_disconnect"):
		_check(e.get("reason") == "disconnect", "client kopunca maç 'bağlantı koptu' ile bitti")
	elif role == "host":
		_check(host_cmds[0] > 0, "client hamleleri host'a ulaştı (%d)" % host_cmds[0])
	else:
		_check(snaps[0] > 10, "durum paketleri geldi (%d)" % snaps[0])
	_check(game.finished and not e.is_empty(), "maç bitti (%s)" % e.get("reason", "-"))
	await create_timer(1.0).timeout
	print("SONUC: ", "HATA" if got.get("fail", false) else "TAMAM")
	quit(1 if got.get("fail", false) else 0)
