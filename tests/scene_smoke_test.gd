extends SceneTree
## Ekranları sırayla açar, oyun ekranında gerçek bir sürükle-bırak hareketi yapar.
## godot --headless --path . -s tests/scene_smoke_test.gd

const SCENES := ["main_menu", "level_select", "shop", "settings", "multiplayer"]


func _initialize() -> void:
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
	print("SONUC: ", "HATA" if failed else "TAMAM")
	quit(1 if failed else 0)


func _touch(p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = p
	e.pressed = pressed
	root.push_input(e, true)
