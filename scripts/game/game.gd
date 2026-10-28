extends Node2D
## Oyun ekranı: haritayı çizer, dokunmatik girişi komuta çevirir, simülasyonu ilerletir,
## simülasyondan gelen olaylara göre efekt ve titreşim üretir.
##
## Kontroller:
##  - Kendi üssünden sürüklemeye başla.
##  - Hedefe varmadan kendi başka üslerinin üzerinden geçersen onlar da KAYNAK olur.
##  - İlk hedefe değdikten sonra geçtiğin her üs HEDEF olur.
##  - Parmağını kaldırınca her kaynak askerini hedeflere EŞİT böler.
##  - Sadece kendi üslerinden geçip bırakırsan, son üs hedef sayılır (takviye).

const HIT_PAD := 24.0
const SOLDIER_R := 5.2
const MAX_PARTICLES := 400

var state: MatchState
var my_id := 0
var bots: Array = []
var params: Dictionary
var finished := false

var _acc := 0.0
var _dragging := false
var _sources: Array = []
var _targets: Array = []
var _finger := Vector2.ZERO
var _font: Font
var _end_layer: CanvasLayer
var _rng := RandomNumberGenerator.new()

# Efektler (sadece görsel; simülasyonu etkilemez).
var _layout_pos := Vector2.ZERO
var _particles: Array = []  # {p, v, life, max, col, r}
var _rings: Array = []      # {p, life, max, col, r0, r1}
var _pop := {}              # üs id -> kalan süre (ele geçirilince büyüyüp küçülme)
var _jolt := {}             # üs id -> kalan süre (darbe alınca titreme)
var _shake_time := 0.0
var _shake_power := 0.0
var _soldier_tex: Texture2D


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_rng.randomize()
	_soldier_tex = _make_soldier_texture()
	_setup_solo()
	_build_hud()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _setup_solo() -> void:
	params = GameConfig.level_params(Session.level)
	var players: Array = [MatchState.make_player(
		0, SaveData.player_name, SaveData.color_index, SaveData.icon_index, false, SaveData.upgrades)]

	var used_colors: Array = [SaveData.color_index]
	var lvl: int = params["bot_upgrade"]
	var bot_upgrades := {"production": lvl, "speed": lvl, "start": lvl, "road": lvl}
	for i in params["bots"]:
		var ci := 0
		while used_colors.has(ci):
			ci += 1
		used_colors.append(ci)
		players.append(MatchState.make_player(i + 1, "Bot %d" % (i + 1), ci, randi() % GameConfig.ICON_NAMES.size(), true, bot_upgrades))

	state = MatchState.create(randi(), players, params["bases"], params["neutral_min"], params["neutral_max"])
	for i in range(1, players.size()):
		bots.append(BotAI.new(i, params["difficulty"], randi()))


## Mantıksal 720x1280 haritayı, farklı ekran oranlarında ortala.
func _layout() -> void:
	var vis := get_viewport_rect().size
	_layout_pos = ((vis - GameConfig.MAP_SIZE) / 2.0).floor()
	position = _layout_pos
	queue_redraw()


func _process(delta: float) -> void:
	if not finished:
		_acc += minf(delta, 0.25)
		while _acc >= GameConfig.SIM_DT:
			_acc -= GameConfig.SIM_DT
			for bot in bots:
				for cmd in bot.update(state, GameConfig.SIM_DT):
					state.apply_command(cmd)
			state.step(GameConfig.SIM_DT)
		_consume_events()
		_check_end()
	_update_effects(delta)
	queue_redraw()


func _issue(cmd: Dictionary) -> void:
	# Multiplayer'da burası komutu host'a gönderecek.
	state.apply_command(cmd)


# ---------------------------------------------------------------- efektler

func _consume_events() -> void:
	for e in state.events:
		match e["type"]:
			"hit":
				var col := state.player_color(e["owner"])
				if _rng.randf() < 0.6:
					_burst(e["pos"], col, 3, 70.0, 0.35, 3.0)
				_jolt[e["base"]] = 0.12
			"reinforce":
				if _rng.randf() < 0.25:
					_burst(e["pos"], state.player_color(e["owner"]).lightened(0.4), 1, 30.0, 0.25, 2.0)
			"clash":
				_burst(e["pos"], Color(1.0, 0.95, 0.7), 2, 160.0, 0.22, 3.6)
				_burst(e["pos"], state.player_color(e["a"]).lightened(0.2), 1, 120.0, 0.45, 3.8)
				_burst(e["pos"], state.player_color(e["b"]).lightened(0.2), 1, 120.0, 0.45, 3.8)
				if _rng.randf() < 0.3:
					_rings.append({"p": e["pos"], "life": 0.18, "max": 0.18, "col": Color(1, 1, 0.9), "r0": 3.0, "r1": 18.0})
			"capture":
				var col := state.player_color(e["to"])
				var r: float = GameConfig.BASE_TYPES["normal"]["radius"]
				_rings.append({"p": e["pos"], "life": 0.5, "max": 0.5, "col": col, "r0": r * 0.8, "r1": r * 2.4})
				_burst(e["pos"], col, 18, 220.0, 0.6, 4.5)
				_pop[e["base"]] = 0.35
				if e["to"] == my_id:
					_vibrate(35, 0.6)
					_shake(4.0, 0.15)
				elif e["from"] == my_id:
					_vibrate(90, 1.0)
					_shake(9.0, 0.25)
	state.events.clear()


func _burst(p: Vector2, col: Color, n: int, speed: float, life: float, size: float) -> void:
	for i in n:
		if _particles.size() >= MAX_PARTICLES:
			_particles.pop_front()
		var a := _rng.randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * _rng.randf_range(0.4, 1.0)
		var l := life * _rng.randf_range(0.7, 1.2)
		_particles.append({"p": p, "v": v, "life": l, "max": l, "col": col, "r": size * _rng.randf_range(0.7, 1.2)})


func _shake(power: float, time: float) -> void:
	_shake_power = maxf(_shake_power, power)
	_shake_time = maxf(_shake_time, time)


func _vibrate(ms: int, amplitude: float) -> void:
	if SaveData.vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amplitude)


func _update_effects(delta: float) -> void:
	for p in _particles:
		p["p"] += p["v"] * delta
		p["v"] *= 1.0 - minf(1.0, 4.0 * delta)
		p["life"] -= delta
	_particles = _particles.filter(func(p): return p["life"] > 0.0)
	for r in _rings:
		r["life"] -= delta
	_rings = _rings.filter(func(r): return r["life"] > 0.0)
	for dict in [_pop, _jolt]:
		for k in dict.keys():
			dict[k] -= delta
			if dict[k] <= 0.0:
				dict.erase(k)
	if _shake_time > 0.0:
		_shake_time -= delta
		position = _layout_pos + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake_power
		if _shake_time <= 0.0:
			_shake_power = 0.0
			position = _layout_pos


# ---------------------------------------------------------------- giriş

func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventScreenTouch and event.index == 0:
		var p: Vector2 = make_input_local(event).position
		if event.pressed:
			var b := _base_at(p)
			if b >= 0 and state.bases[b]["owner"] == my_id:
				_dragging = true
				_sources = [b]
				_targets = []
				_finger = p
				_vibrate(12, 0.3)
		elif _dragging:
			_finish_drag()
	elif event is InputEventScreenDrag and event.index == 0 and _dragging:
		_finger = make_input_local(event).position
		var b := _base_at(_finger)
		if b >= 0:
			_touch_base(b)


func _touch_base(b: int) -> void:
	if _sources.has(b) or _targets.has(b):
		return
	if _targets.is_empty() and state.bases[b]["owner"] == my_id:
		_sources.append(b)
	else:
		_targets.append(b)
	_vibrate(8, 0.25)


func _finish_drag() -> void:
	_dragging = false
	if _targets.is_empty() and _sources.size() >= 2:
		_targets = [_sources.pop_back()]
	if not _targets.is_empty():
		_issue({"type": "send", "owner": my_id, "sources": _sources.duplicate(), "targets": _targets.duplicate()})
		_vibrate(20, 0.5)
	_sources = []
	_targets = []


func _base_at(p: Vector2) -> int:
	for b in state.bases:
		var r: float = state.base_type(b)["radius"] + HIT_PAD
		if p.distance_to(b["pos"]) <= r:
			return b["id"]
	return -1


# ---------------------------------------------------------------- çizim

func _draw() -> void:
	var vis := get_viewport_rect().size
	draw_rect(Rect2(-position - Vector2(20, 20), vis + Vector2(40, 40)), UIKit.BG)

	if _dragging:
		for s in _sources:
			if state.bases[s]["owner"] != my_id:
				continue
			var a: Vector2 = state.bases[s]["pos"]
			if _targets.is_empty():
				_dashed(a, _finger, Color(1, 1, 1, 0.75))
			else:
				for t in _targets:
					_dashed(a, state.bases[t]["pos"], Color(1, 1, 1, 0.75))
		if not _targets.is_empty():
			_dashed(state.bases[_targets.back()]["pos"], _finger, Color(1, 1, 1, 0.35))

	for g in state.groups:
		_draw_column(g)

	for r in _rings:
		var k: float = 1.0 - r["life"] / r["max"]
		var col: Color = r["col"]
		col.a = 1.0 - k
		draw_arc(r["p"], lerpf(r["r0"], r["r1"], k), 0.0, TAU, 56, col, lerpf(10.0, 2.0, k), true)

	for b in state.bases:
		_draw_base(b)

	for p in _particles:
		var col: Color = p["col"]
		col.a = clampf(p["life"] / p["max"], 0.0, 1.0)
		draw_circle(p["p"], p["r"] * (0.5 + 0.5 * col.a), col)


## Asker kolunu sıra sıra çizer. Henüz üssün içinde olan askerler görünmez.
func _draw_column(g: Dictionary) -> void:
	var a: Vector2 = state.bases[g["from"]]["pos"]
	var b: Vector2 = state.bases[g["to"]]["pos"]
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var lanes: int = g["lanes"]
	var col := state.player_color(g["owner"])
	var tex_size := Vector2(SOLDIER_R, SOLDIER_R) * 2.0
	# Yürürken hafif sallanma (her kol farklı fazda).
	var bob: float = 0.0 if g["fighting"] else Time.get_ticks_msec() / 90.0 + g["id"] * 1.7
	for i in range(g["f"], g["n"]):
		@warning_ignore("integer_division")
		var row: int = i / lanes
		var along: float = g["d"] - row * MatchState.ROW_SPACING
		if along < g["s0"] - 2.0:
			break
		var lane_off := (i % lanes - (lanes - 1) * 0.5) * MatchState.LANE_SPACING
		lane_off += sin(bob + row * 1.3) * 0.9
		var pos := a + dir * along + perp * lane_off
		draw_texture_rect(_soldier_tex, Rect2(pos - tex_size / 2.0, tex_size), false, col)


func _draw_base(b: Dictionary) -> void:
	var id: int = b["id"]
	var c: Vector2 = b["pos"]
	var r: float = state.base_type(b)["radius"]
	var owner: int = b["owner"]
	var col := state.player_color(owner)

	if _pop.has(id):
		var k: float = _pop[id] / 0.35
		r *= 1.0 + 0.22 * sin(k * PI)
	if _jolt.has(id):
		c += Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5))

	draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.3))
	draw_circle(c, r, col)
	draw_arc(c, r - 3.0, 0.0, TAU, 48, col.lightened(0.25), 4.0, true)
	if owner != GameConfig.NEUTRAL:
		IconDraw.draw_icon(self, state.players[owner]["icon"], c, r * 0.6, Color(1, 1, 1, 0.22))

	if _dragging and _sources.has(id):
		draw_arc(c, r + 8.0, 0.0, TAU, 48, Color.WHITE, 5.0, true)
	elif _dragging and _targets.has(id):
		draw_arc(c, r + 8.0, 0.0, TAU, 48, UIKit.ACCENT, 5.0, true)

	_text_centered(str(int(b["troops"])), c, 30, Color.WHITE)


## Kenarı koyu, ortası açık küçük asker dokusu (beyaz; çizerken renklendirilir).
func _make_soldier_texture() -> Texture2D:
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) / 2.0 - Vector2(0.5, 0.5)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s / 2.0)
			var alpha := clampf((1.0 - d) * 6.0, 0.0, 1.0)
			var shade := 0.62 if d > 0.72 else 1.0
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return ImageTexture.create_from_image(img)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	draw_dashed_line(a, b, col, 5.0, 14.0, true)


func _text_centered(text: String, c: Vector2, fs: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := c.y + (_font.get_ascent(fs) - _font.get_descent(fs)) / 2.0
	draw_string_outline(_font, Vector2(c.x - w / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.45))
	draw_string(_font, Vector2(c.x - w / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# ---------------------------------------------------------------- HUD ve bitiş

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.make_theme()
	layer.add_child(root)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_top = 40
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	var lvl := UIKit.label("Bölüm %d" % Session.level, 34)
	lvl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(lvl)
	bar.add_child(UIKit.button("Çık", func(): Session.go("main_menu"), 70))


func _check_end() -> void:
	var alive := state.alive_players()
	if not alive.has(my_id):
		_end(false)
	elif alive.size() == 1:
		_end(true)


func _end(won: bool) -> void:
	finished = true
	_dragging = false
	_vibrate(160 if won else 250, 0.8)
	var gold := 0
	if won:
		gold = params["gold"]
		SaveData.gold += gold
		if Session.level >= SaveData.unlocked_level:
			SaveData.unlocked_level = Session.level + 1
		SaveData.save()
	_show_end_panel(won, gold)


func _show_end_panel(won: bool, gold: int) -> void:
	_end_layer = CanvasLayer.new()
	_end_layer.layer = 10
	add_child(_end_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.make_theme()
	_end_layer.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	var title := UIKit.label("Kazandın!" if won else "Kaybettin", 56, UIKit.ACCENT if won else UIKit.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	if won:
		var g := UIKit.label("+%d altın" % gold, 36, UIKit.ACCENT)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(g)
		box.add_child(UIKit.button("Sonraki Bölüm", func():
			Session.level += 1
			Session.go("game")))
	else:
		box.add_child(UIKit.button("Tekrar Dene", func(): Session.go("game")))
	box.add_child(UIKit.button("Ana Menü", func(): Session.go("main_menu")))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")
