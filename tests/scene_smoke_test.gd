extends SceneTree
## Ekranları sırayla açar, oyun ekranında gerçek bir sürükle-bırak hareketi yapar.
## godot --headless --path . -s tests/scene_smoke_test.gd

const SCENES := ["main_menu", "level_select", "shop", "settings", "multiplayer", "quests", "about"]


func _initialize() -> void:
	# Bir betik derlenemezse test takılmasın, hata versin.
	create_timer(60.0).timeout.connect(func():
		print("  HATA zaman aşımı (bir ekran açılamadı)")
		print("SONUC: HATA")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	var failed := false
	for name in SCENES:
		var node: Node = load("res://scenes/%s.tscn" % name).instantiate()
		root.add_child(node)
		for i in 5:
			await process_frame
		print("  ok   %s açıldı (%d alt öğe)" % [name, node.get_child_count()])
		node.queue_free()
		await process_frame

	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for i in 10:
		await process_frame
	var intro_ok: bool = game.phase == "intro" and game._overlay != null
	print(("  ok   " if intro_ok else "  HATA ") + "oyun hedef kartıyla başladı")
	failed = failed or not intro_ok
	game._close_overlay()
	game.phase = "play"
	await process_frame
	var st: MatchState = game.state
	var mine: Dictionary = st.bases.filter(func(b): return b["owner"] == 0)[0]
	var target: Dictionary = st.bases.filter(func(b): return b["owner"] != 0)[0]
	var before: float = mine["troops"]

	# Ekran koordinatına çevirip dokunmatik olay gönder.
	var xf := game.get_global_transform_with_canvas()
	var p0: Vector2 = xf * mine["pos"]
	var p1: Vector2 = xf * target["pos"]
	_touch(p0, true)
	await process_frame
	for i in range(1, 11):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = p0.lerp(p1, i / 10.0)
		root.push_input(d, true)
		await process_frame
	_touch(p1, false)
	for i in 3:
		await process_frame

	var sent: bool = st.groups.any(func(g): return g["owner"] == 0 and g["to"] == target["id"])
	print(("  ok   " if sent else "  HATA ") + "sürükle-bırak asker gönderdi (üs: %d -> %d)" % [before, int(mine["troops"])])
	failed = failed or not sent

	game._pause()
	var t0: float = st.time
	for i in 20:
		await process_frame
	var paused_ok: bool = game.phase == "pause" and is_equal_approx(st.time, t0)
	print(("  ok   " if paused_ok else "  HATA ") + "duraklatınca oyun durdu")
	failed = failed or not paused_ok
	game._resume()
	for i in 20:
		await process_frame
	var resumed_ok: bool = game.phase == "play" and st.time > t0
	print(("  ok   " if resumed_ok else "  HATA ") + "devam edince oyun sürdü")
	failed = failed or not resumed_ok
	game.queue_free()
	await process_frame
	failed = (await _survival_check()) or failed
	failed = (await _level_map_check()) or failed
	print("SONUC: ", "HATA" if failed else "TAMAM")
	quit(1 if failed else 0)


## Hayatta kalma: oyun açılır, kendi üssüne basılı tutunca yükseltme menüsü açılır, kışla kurulur.
func _survival_check() -> bool:
	root.get_node("Session").mode = "survival"
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for i in 5:
		await process_frame
	var ok: bool = game.survival != null and game.state.economy
	print(("  ok   " if ok else "  HATA ") + "hayatta kalma modu açıldı")
	game._close_overlay()
	game.phase = "play"
	await process_frame
	var st: MatchState = game.state
	st.players[0]["gold"] = 500.0
	var b: Dictionary = st.bases.filter(func(x): return x["owner"] == 0 and x["type"] == "normal")[0]
	var p: Vector2 = game.get_global_transform_with_canvas() * b["pos"]
	_touch(p, true)
	var t0 := Time.get_ticks_msec()
	while game._menu_base < 0 and Time.get_ticks_msec() - t0 < 1500:
		await process_frame
	var menu_ok: bool = game._menu_base == b["id"]
	if not menu_ok:
		print("    dokunulan üs: %d, beklenen: %d, basılı: %d, faz: %s" % [game._base_at(game.make_input_local(_ev(p)).position), b["id"], game._press_base, game.phase])
	print(("  ok   " if menu_ok else "  HATA ") + "basılı tutunca yükseltme menüsü açıldı")
	_touch(p, false)
	game._issue({"type": "build", "owner": 0, "base": b["id"], "kind": "barracks"})
	game._close_build_menu()
	var built: bool = b["type"] == "barracks"
	print(("  ok   " if built else "  HATA ") + "kışla kuruldu")
	root.get_node("Session").mode = "solo"
	return not (ok and menu_ok and built)


func _touch(p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = p
	e.pressed = pressed
	root.push_input(e, true)


func _ev(p: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.position = p
	return e


## Bölüm haritası: açık bölüme dokununca bölüm seçilir, kilitliye dokununca seçilmez.
func _level_map_check() -> bool:
	var sd: Node = root.get_node("SaveData")
	var ses: Node = root.get_node("Session")
	var keep_level: int = sd.unlocked_level
	sd.unlocked_level = 3
	var scr: Node = load("res://scenes/level_select.tscn").instantiate()
	root.add_child(scr)
	for i in 6:
		await process_frame
	var map: Control = scr.find_children("*", "Control", true, false).filter(func(c): return c.has_method("node_pos"))[0]
	var chosen: Array = []
	for c in map.level_chosen.get_connections():
		map.level_chosen.disconnect(c["callable"])
	map.level_chosen.connect(func(n): chosen.append(n))
	for lv in [2, 9]:
		var p: Vector2 = map.get_global_transform_with_canvas() * map.node_pos(lv)
		_mouse(p, true)
		await process_frame
		_mouse(p, false)
		await process_frame
	var ok: bool = chosen == [2]
	print(("  ok   " if ok else "  HATA ") + "bölüm haritası: açık bölüm seçildi, kilitli seçilmedi (seçilen: %s)" % [chosen])
	sd.unlocked_level = keep_level
	scr.queue_free()
	await process_frame
	return not ok


func _mouse(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = p
	e.global_position = p
	e.pressed = pressed
	root.push_input(e, true)
