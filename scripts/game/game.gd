extends Node2D
## Oyun ekranı: haritayı çizer, dokunmatik girişi komuta çevirir, simülasyonu ilerletir.
##
## Kontroller:
##  - Kendi üssünden sürüklemeye başla.
##  - Hedefe varmadan kendi başka üslerinin üzerinden geçersen onlar da KAYNAK olur.
##  - İlk hedefe değdikten sonra geçtiğin her üs HEDEF olur.
##  - Parmağını kaldırınca her kaynak askerini hedeflere EŞİT böler.
##  - Sadece kendi üslerinden geçip bırakırsan, son üs hedef sayılır (takviye).

const HIT_PAD := 24.0

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
var _hud_level: Label
var _end_layer: CanvasLayer


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_setup_solo()
	_build_hud()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _setup_solo() -> void:
	params = GameConfig.level_params(Session.level)
	var players: Array = [MatchState.make_player(
		0, SaveData.player_name, SaveData.color_index, SaveData.icon_index, false, SaveData.upgrades)]

	var used_colors: Array = [SaveData.color_index]
	var bot_upgrades := {"production": params["bot_upgrade"], "speed": params["bot_upgrade"], "start": params["bot_upgrade"]}
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
	position = ((vis - GameConfig.MAP_SIZE) / 2.0).floor()
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
		_check_end()
	queue_redraw()


func _issue(cmd: Dictionary) -> void:
	# Multiplayer'da burası komutu host'a gönderecek.
	state.apply_command(cmd)


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


func _finish_drag() -> void:
	_dragging = false
	if _targets.is_empty() and _sources.size() >= 2:
		_targets = [_sources.pop_back()]
	if not _targets.is_empty():
		_issue({"type": "send", "owner": my_id, "sources": _sources.duplicate(), "targets": _targets.duplicate()})
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
	draw_rect(Rect2(-position, vis), UIKit.BG)

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
		var pos := state.group_position(g)
		var r := 9.0 + sqrt(float(g["count"])) * 1.6
		draw_circle(pos, r, state.player_color(g["owner"]))
		_text_centered(str(g["count"]), pos, 20, Color.WHITE)

	for b in state.bases:
		_draw_base(b)


func _draw_base(b: Dictionary) -> void:
	var c: Vector2 = b["pos"]
	var r: float = state.base_type(b)["radius"]
	var owner: int = b["owner"]
	var col := state.player_color(owner)

	draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.3))
	draw_circle(c, r, col)
	draw_arc(c, r - 3.0, 0.0, TAU, 48, col.lightened(0.25), 4.0, true)
	if owner != GameConfig.NEUTRAL:
		IconDraw.draw_icon(self, state.players[owner]["icon"], c, r * 0.6, Color(1, 1, 1, 0.22))

	var id: int = b["id"]
	if _dragging and _sources.has(id):
		draw_arc(c, r + 8.0, 0.0, TAU, 48, Color.WHITE, 5.0, true)
	elif _dragging and _targets.has(id):
		draw_arc(c, r + 8.0, 0.0, TAU, 48, UIKit.ACCENT, 5.0, true)

	_text_centered(str(int(b["troops"])), c, 30, Color.WHITE)


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

	_hud_level = UIKit.label("Bölüm %d" % Session.level, 34)
	_hud_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_hud_level)
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
