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
## Basılı tutma ile yükseltme menüsü açılması için süre (ms) ve izin verilen kayma (px).
const LONG_PRESS_MS := 450
const LONG_PRESS_SLOP := 18.0
const SOLDIER_R := 5.2
const MAX_PARTICLES := 400

var state: MatchState
var my_id := 0
var bots: Array = []
var params: Dictionary
var finished := false
## "intro" (hedef kartı), "play", "pause", "end"
var phase := "intro"
var bases_lost := 0
## Hayatta kalma modu (Session.mode == "survival")
var survival: Survival
var _banner: Label
var _banner_time := 0.0
var _press_base := -1
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _menu_base := -1

var _acc := 0.0
var _dragging := false
var _sources: Array = []
var _targets: Array = []
var _finger := Vector2.ZERO
var _font: Font
var _overlay_layer: CanvasLayer
var _overlay: Control
var _time_label: Label
var _loss_label: Label
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
	if Session.mode == "survival":
		_setup_survival()
	else:
		_setup_solo()
	_build_hud()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_show_intro()


func _setup_solo() -> void:
	var setup := LevelSetup.create(Session.level, {
		"name": SaveData.player_name, "color": SaveData.color_index,
		"icon": SaveData.icon_index, "upgrades": SaveData.upgrades}, randi())
	state = setup["state"]
	bots = setup["bots"]
	params = setup["params"]


func _setup_survival() -> void:
	var setup := Survival.create({
		"name": SaveData.player_name, "color": SaveData.color_index,
		"icon": SaveData.icon_index, "upgrades": SaveData.upgrades}, randi())
	state = setup["state"]
	bots = setup["bots"]
	survival = setup["survival"]
	params = {"boss": false, "par": 0}


## Mantıksal 720x1280 haritayı, farklı ekran oranlarında ortala.
func _layout() -> void:
	var vis := get_viewport_rect().size
	_layout_pos = ((vis - GameConfig.MAP_SIZE) / 2.0).floor()
	position = _layout_pos
	queue_redraw()


func _process(delta: float) -> void:
	if phase == "play":
		_acc += minf(delta, 0.25)
		while _acc >= GameConfig.SIM_DT:
			_acc -= GameConfig.SIM_DT
			if survival:
				survival.update(state, GameConfig.SIM_DT)
			for bot in bots:
				for cmd in bot.update(state, GameConfig.SIM_DT):
					state.apply_command(cmd)
			state.step(GameConfig.SIM_DT)
		_consume_events()
		_update_hud()
		_check_long_press()
		_check_end()
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time / 0.4, 0.0, 1.0)
	if phase == "play" or phase == "end":
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
					bases_lost += 1
					_vibrate(90, 1.0)
					_shake(9.0, 0.25)
			"build":
				var col := state.player_color(e["owner"])
				var bp: Vector2 = state.bases[e["base"]]["pos"]
				_rings.append({"p": bp, "life": 0.6, "max": 0.6, "col": UIKit.ACCENT, "r0": 30.0, "r1": 90.0})
				_burst(bp, UIKit.ACCENT, 14, 160.0, 0.6, 4.0)
				_pop[e["base"]] = 0.35
				if e["owner"] == my_id:
					_vibrate(30, 0.5)
			"shield":
				if _rng.randf() < 0.5:
					_burst(e["pos"], Color("#8ecbff"), 2, 90.0, 0.3, 3.0)
			"shield_down":
				_rings.append({"p": e["pos"], "life": 0.9, "max": 0.9, "col": Color("#8ecbff"), "r0": 60.0, "r1": 200.0})
				_burst(e["pos"], Color("#8ecbff"), 30, 260.0, 0.8, 5.0)
				_show_banner("Düşman kalesinin kalkanı düştü!")
				_vibrate(120, 0.8)
			"wave":
				_show_banner("%d. dalga geliyor!" % e["n"])
				_rings.append({"p": e["pos"], "life": 0.7, "max": 0.7, "col": state.player_color(e["owner"]), "r0": 60.0, "r1": 160.0})
				_shake(5.0, 0.2)
				_vibrate(60, 0.7)
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
	if phase != "play":
		return
	if event is InputEventScreenTouch and event.index == 0:
		var p: Vector2 = make_input_local(event).position
		if event.pressed:
			var b := _base_at(p)
			_finger = p
			if b >= 0 and state.bases[b]["owner"] == my_id:
				if survival:
					_press_base = b
					_press_pos = p
					_press_ms = Time.get_ticks_msec()
				if MatchState.can_send_from(state.bases[b]):
					_dragging = true
					_sources = [b]
					_targets = []
					_vibrate(12, 0.3)
		else:
			_press_base = -1
			if _dragging:
				_finish_drag()
	elif event is InputEventScreenDrag and event.index == 0:
		_finger = make_input_local(event).position
		if _press_base >= 0 and _finger.distance_to(_press_pos) > LONG_PRESS_SLOP:
			_press_base = -1
		if _dragging:
			var b := _base_at(_finger)
			if b >= 0:
				_touch_base(b)


## Hayatta kalma: kendi üssüne kıpırdamadan basılı tutunca yükseltme menüsü açılır.
func _check_long_press() -> void:
	if _press_base < 0 or Time.get_ticks_msec() - _press_ms < LONG_PRESS_MS:
		return
	var b := _press_base
	_press_base = -1
	if state.bases[b]["owner"] != my_id:
		return
	_dragging = false
	_sources = []
	_targets = []
	_vibrate(25, 0.5)
	_open_build_menu(b)


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


## Dokunulan noktaya en yakın üs (dokunma payıyla birlikte); yoksa -1.
func _base_at(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for b in state.bases:
		var d: float = p.distance_to(b["pos"])
		if d <= float(state.base_type(b)["radius"]) + HIT_PAD and d < best_d:
			best_d = d
			best = b["id"]
	return best


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
	var kind: String = b["type"]
	if kind == "fortress" or kind == "keep" or kind == "citadel":
		_draw_fortress(c, r, col)
	draw_circle(c, r, col)
	draw_arc(c, r - 3.0, 0.0, TAU, 48, col.lightened(0.25), 4.0, true)
	if kind == "barracks":
		_draw_barracks(c, r, col, b.get("level", 1))
	elif kind == "mine":
		_draw_mine(c, r, b.get("level", 1))
	elif owner != GameConfig.NEUTRAL:
		IconDraw.draw_icon(self, state.players[owner]["icon"], c, r * 0.6, Color(1, 1, 1, 0.22))
	if b.get("shielded", false):
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
		draw_arc(c, r + 16.0, 0.0, TAU, 64, Color(0.55, 0.8, 1.0, 0.35 + 0.3 * pulse), 6.0, true)
		draw_circle(c, r + 14.0, Color(0.55, 0.8, 1.0, 0.08))

	if _dragging and _sources.has(id):
		draw_arc(c, r + 8.0, 0.0, TAU, 48, Color.WHITE, 5.0, true)
	elif _dragging and _targets.has(id):
		draw_arc(c, r + 8.0, 0.0, TAU, 48, UIKit.ACCENT, 5.0, true)

	if kind == "mine":
		# Maden: normal + 2 güçlü maden askeri (altın renkte).
		_text_centered(str(int(b["troops"] + b.get("elite", 0.0))), c, 30, Color("#ffe082"))
	else:
		_text_centered(str(int(b["troops"])), c, 30, Color.WHITE)


## Kışla: içinde koyu kalkan şekli, altında seviye yıldızları.
func _draw_barracks(c: Vector2, r: float, col: Color, level: int) -> void:
	var w := r * 0.95
	var shield := PackedVector2Array([
		c + Vector2(-w * 0.5, -w * 0.45), c + Vector2(w * 0.5, -w * 0.45),
		c + Vector2(w * 0.5, w * 0.05), c + Vector2(0, w * 0.55), c + Vector2(-w * 0.5, w * 0.05)])
	draw_colored_polygon(shield, col.darkened(0.35))
	_draw_level_stars(c + Vector2(0, r + 12.0), level, 5)


## Altın madeni: altın para, altında seviye yıldızları.
func _draw_mine(c: Vector2, r: float, level: int) -> void:
	draw_circle(c, r * 0.62, Color("#c9971c"))
	draw_arc(c, r * 0.62, 0.0, TAU, 40, Color("#ffe082"), 4.0, true)
	_draw_level_stars(c + Vector2(0, r + 12.0), level, 3)


func _draw_level_stars(c: Vector2, level: int, max_level: int) -> void:
	var gap := 15.0
	var x0 := c.x - gap * (max_level - 1) / 2.0
	for i in max_level:
		var col := UIKit.ACCENT if i < level else Color(1, 1, 1, 0.2)
		draw_colored_polygon(IconDraw.star_points(Vector2(x0 + i * gap, c.y), 7.0), col)


## Kale (boss üssü): dişli dış halka ve üstünde taç.
func _draw_fortress(c: Vector2, r: float, col: Color) -> void:
	var teeth := 12
	for i in teeth:
		var a := TAU * i / teeth
		var p := c + Vector2(cos(a), sin(a)) * (r + 5.0)
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), col.darkened(0.25))
	draw_circle(c, r + 4.0, col.darkened(0.25))
	var top := c + Vector2(0, -r - 14.0)
	var crown := PackedVector2Array([
		top + Vector2(-18, 10), top + Vector2(-18, -6), top + Vector2(-9, 2), top + Vector2(0, -10),
		top + Vector2(9, 2), top + Vector2(18, -6), top + Vector2(18, 10)])
	draw_colored_polygon(crown, UIKit.ACCENT)


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


# ---------------------------------------------------------------- HUD

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
	bar.offset_top = 36
	bar.add_theme_constant_override("separation", 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	var pause := UIKit.button("II", func(): _pause(), 76)
	pause.custom_minimum_size.x = 76
	pause.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.add_child(pause)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 0)
	bar.add_child(info)
	var title := "Bölüm %d" % Session.level
	if params["boss"]:
		title += "  ·  BOSS"
	if survival:
		title = "Hayatta Kalma"
	info.add_child(UIKit.label(title, 32))
	_loss_label = UIKit.label("", 22, UIKit.MUTED)
	info.add_child(_loss_label)

	_time_label = UIKit.label("", 34)
	_time_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_time_label)

	_banner = UIKit.label("", 40, UIKit.ACCENT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 170
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_update_hud()


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner_time = 2.2


func _update_hud() -> void:
	if survival:
		var p: Dictionary = state.players[my_id]
		var rate := GameConfig.SURVIVAL_GOLD_RATE
		for b in state.bases:
			if b["owner"] == my_id and b["type"] == "mine":
				rate += GameConfig.mine_gold(b.get("level", 1))
		_time_label.text = _fmt_time(state.time)
		_loss_label.text = "Altın %d  (+%s/sn)   ·   %d. dalga %s" % [
			int(p["gold"]), str(snappedf(rate, 0.1)), survival.wave + 1, _fmt_time(survival.seconds_to_next_wave(state))]
		_loss_label.add_theme_color_override("font_color", UIKit.ACCENT)
		return
	var over: bool = state.time > params["par"]
	_time_label.text = "%s / %s" % [_fmt_time(state.time), _fmt_time(params["par"])]
	_time_label.add_theme_color_override("font_color", Color("#e57373") if over else UIKit.TEXT)
	var limit := GameConfig.STAR_LOSS_LIMIT
	_loss_label.text = "Kaybedilen üs: %d / %d" % [bases_lost, limit]
	_loss_label.add_theme_color_override("font_color", Color("#e57373") if bases_lost > limit else UIKit.MUTED)


static func _fmt_time(sec: float) -> String:
	var t := int(sec)
	@warning_ignore("integer_division")
	return "%d:%02d" % [t / 60, t % 60]


## Hedef listesi: [metin, tutuldu mu (null = henüz belli değil)]
func _goals(won: Variant) -> Array:
	var time_ok: Variant = null
	var loss_ok: Variant = null
	if won == true:
		time_ok = state.time <= params["par"]
		loss_ok = bases_lost <= GameConfig.STAR_LOSS_LIMIT
	elif won == false:
		time_ok = false
		loss_ok = false
	else:
		time_ok = false if state.time > params["par"] else null
		loss_ok = false if bases_lost > GameConfig.STAR_LOSS_LIMIT else null
	return [
		["Bölümü kazan", won],
		["%s içinde kazan" % _fmt_time(params["par"]), time_ok],
		["En fazla %d üs kaybet" % GameConfig.STAR_LOSS_LIMIT, loss_ok],
	]


# ---------------------------------------------------------------- açılır panolar

## Yarı saydam arka plan + ortada panel; panelin içeriğini döndürür.
func _open_overlay(dim_alpha := 0.6) -> VBoxContainer:
	_close_overlay()
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10
	add_child(_overlay_layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.theme = UIKit.make_theme()
	_overlay_layer.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, dim_alpha)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	return box


func _close_overlay() -> void:
	if _overlay_layer:
		_overlay_layer.queue_free()
		_overlay_layer = null
		_overlay = null


func _add_title(box: VBoxContainer, text: String, size: int, col: Color) -> void:
	var l := UIKit.label(text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)


func _add_goals(box: VBoxContainer, goals: Array) -> void:
	for g in goals:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		var star := StarRow.new()
		star.total = 1
		star.count = 1 if g[1] == true else 0
		if g[1] == null:
			star.empty_color = Color(1, 1, 1, 0.45)
		elif g[1] == false:
			star.empty_color = Color(0.9, 0.35, 0.35, 0.6)
		star.custom_minimum_size = Vector2(38, 38)
		row.add_child(star)
		var col := UIKit.TEXT
		if g[1] == false:
			col = UIKit.MUTED
		var l := UIKit.label(g[0], 28, col)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)


# ---------------------------------------------------------------- yükseltme menüsü

func _open_build_menu(base_id: int) -> void:
	_menu_base = base_id
	var b: Dictionary = state.bases[base_id]
	var box := _open_overlay(0.35)
	var gold: float = state.players[my_id]["gold"]
	var kind: String = b["type"]
	var lv: int = b.get("level", 1)
	var names := {"normal": "Üs", "barracks": "Kışla", "mine": "Altın Madeni", "keep": "Kale", "fortress": "Kale"}
	_add_title(box, names.get(kind, "Üs"), 44, UIKit.TEXT)
	if kind == "barracks" or kind == "mine":
		var sr := StarRow.new()
		sr.total = 5 if kind == "barracks" else 3
		sr.count = lv
		sr.custom_minimum_size = Vector2(0, 36)
		box.add_child(sr)
	_add_title(box, "Altının: %d" % int(gold), 28, UIKit.ACCENT)

	match kind:
		"normal":
			_build_option(box, base_id, "barracks", "Kışla kur",
				"Kendisi %sx asker üretir, diğer tüm üslerine +%%%d üretim" % [
					str(GameConfig.barracks_growth(1)), int(GameConfig.BARRACKS_LEVELS[0][2] * 100)])
			_build_option(box, base_id, "mine", "Altın Madeni kur",
				"+%s altın/sn. 2 güçlü savunma askeri üretir, bu askerler saldıramaz" % str(GameConfig.mine_gold(1)))
		"barracks":
			if lv < GameConfig.BARRACKS_LEVELS.size():
				var nx: Array = GameConfig.BARRACKS_LEVELS[lv]
				var desc := "Kendisi %sx üretim, diğer üslerine +%%%d üretim" % [str(nx[1]), int(nx[2] * 100)]
				if nx[3] > 0.0:
					desc += ", +%%%d asker hızı" % int(nx[3] * 100)
				_build_option(box, base_id, "upgrade", "%d. seviyeye yükselt" % (lv + 1), desc)
			else:
				_add_title(box, "En yüksek seviyede", 28, UIKit.MUTED)
		"mine":
			if lv < GameConfig.MINE_LEVELS.size():
				_build_option(box, base_id, "upgrade", "%d. seviyeye yükselt" % (lv + 1),
					"+%s altın/sn, en fazla %d maden askeri" % [str(GameConfig.mine_gold(lv + 1)), int(GameConfig.mine_capacity(lv + 1))])
			else:
				_add_title(box, "En yüksek seviyede", 28, UIKit.MUTED)
		_:
			_add_title(box, "Kale geliştirilemez. Düşerse oyun biter!", 26, UIKit.MUTED)
	box.add_child(UIKit.button("Kapat", _close_build_menu, 80))


func _build_option(box: VBoxContainer, base_id: int, kind: String, title: String, desc: String) -> void:
	var cost := state.build_cost(my_id, base_id, kind)
	if cost < 0:
		return
	var gold: float = state.players[my_id]["gold"]
	var btn := UIKit.button("%s  —  %d altın" % [title, cost], func():
		_issue({"type": "build", "owner": my_id, "base": base_id, "kind": kind})
		_close_build_menu(), 92)
	btn.disabled = gold < cost
	box.add_child(btn)
	box.add_child(UIKit.label(desc, 22, UIKit.MUTED))


func _close_build_menu() -> void:
	_menu_base = -1
	_close_overlay()


# ---------------------------------------------------------------- giriş / duraklat panoları

func _show_intro() -> void:
	phase = "intro"
	if survival:
		_show_survival_intro()
		return
	var box := _open_overlay()
	_add_title(box, "Bölüm %d" % Session.level, 54, UIKit.TEXT)
	if params["boss"]:
		_add_title(box, "BOSS: %s" % state.players[1]["name"], 34, Color("#ff8a80"))
	_add_title(box, GameConfig.band_name(Session.level), 26, UIKit.MUTED)
	var best := SaveData.best_stars(Session.level)
	if best > 0:
		var sr := StarRow.new()
		sr.count = best
		sr.custom_minimum_size = Vector2(0, 44)
		box.add_child(sr)
	box.add_child(UIKit.label("Hedefler", 28, UIKit.MUTED))
	_add_goals(box, _goals(null))
	box.add_child(UIKit.button("Başla", func():
		_close_overlay()
		phase = "play", 100))
	box.add_child(UIKit.button("Geri", func(): Session.go("level_select"), 80))


func _pause() -> void:
	if phase != "play":
		return
	phase = "pause"
	_dragging = false
	_menu_base = -1
	var box := _open_overlay()
	_add_title(box, "Duraklatıldı", 50, UIKit.TEXT)
	if survival:
		_add_title(box, "Hayatta Kalma  ·  %s  ·  %d. dalga" % [_fmt_time(state.time), survival.wave], 28, UIKit.MUTED)
	else:
		_add_title(box, "Bölüm %d  ·  %s" % [Session.level, _fmt_time(state.time)], 28, UIKit.MUTED)
		_add_goals(box, _goals(null))
	box.add_child(UIKit.button("Devam Et", _resume, 100))
	box.add_child(UIKit.button("Yeniden Başla", func(): Session.go("game")))
	if not survival:
		box.add_child(UIKit.button("Bölümler", func(): Session.go("level_select")))
	box.add_child(UIKit.button("Ana Menü", func(): Session.go("main_menu")))


func _resume() -> void:
	_close_overlay()
	_acc = 0.0
	phase = "play"


# ---------------------------------------------------------------- bitiş

func _check_end() -> void:
	if survival:
		var res := Survival.result(state)
		if res != "":
			_end_survival(res == "win")
		return
	var alive := state.alive_players()
	if not alive.has(my_id):
		_end(false)
	elif alive.size() == 1:
		_end(true)


func _end(won: bool) -> void:
	finished = true
	phase = "end"
	_dragging = false
	_vibrate(160 if won else 250, 0.8)
	var stars := 0
	var gold := 0
	var prev := SaveData.best_stars(Session.level)
	if won:
		stars = GameConfig.stars_for(params, state.time, bases_lost)
		gold = SaveData.record_win(Session.level, stars)
	_show_end_panel.call_deferred(won, stars, gold, prev)


func _show_end_panel(won: bool, stars: int, gold: int, prev: int) -> void:
	var box := _open_overlay()
	_add_title(box, "Kazandın!" if won else "Kaybettin", 58, UIKit.ACCENT if won else UIKit.TEXT)
	var sr := StarRow.new()
	sr.count = stars
	sr.custom_minimum_size = Vector2(0, 84)
	box.add_child(sr)
	_add_title(box, "Süre %s" % _fmt_time(state.time), 26, UIKit.MUTED)
	_add_goals(box, _goals(won))
	if won:
		var note := ""
		if stars <= prev:
			note = "  (tekrar)"
		elif prev > 0:
			note = "  (yeni rekor!)"
		_add_title(box, "+%d altın%s" % [gold, note], 36, UIKit.ACCENT)
		if Session.level < GameConfig.MAX_LEVEL:
			box.add_child(UIKit.button("Sonraki Bölüm", func():
				Session.level += 1
				Session.go("game"), 100))
		else:
			_add_title(box, "Tüm bölümleri bitirdin!", 30, UIKit.ACCENT)
	box.add_child(UIKit.button("Tekrar Oyna", func(): Session.go("game")))
	box.add_child(UIKit.button("Ana Menü", func(): Session.go("main_menu")))


# ---------------------------------------------------------------- hayatta kalma panoları

func _show_survival_intro() -> void:
	var box := _open_overlay()
	_add_title(box, "Hayatta Kalma", 54, UIKit.TEXT)
	var lines := [
		"Saniyede 1 maç altını kazanırsın (mağaza altınından ayrı).",
		"Kendi üssüne basılı tut: Kışla veya Altın Madeni kur, yükselt.",
		"Rakip kalesi sürekli akın yapar; ayrıca her dakika büyüyen bir saldırı dalgası gelir.",
		"Kalenden en fazla askerin yarısı çıkar, en az %d asker içeride kalır." % GameConfig.KEEP_MIN_GARRISON,
		"Kalen düşerse oyun biter. %d. dalgadan sonra rakip kalesinin kalkanı düşer: onu alırsan kazanırsın!" % GameConfig.CITADEL_SHIELD_WAVES,
	]
	for t in lines:
		box.add_child(UIKit.label("• " + t, 24, UIKit.TEXT))
	if SaveData.survival_best > 0.0:
		_add_title(box, "En iyi: %s  ·  %d. dalga" % [_fmt_time(SaveData.survival_best), SaveData.survival_best_wave], 28, UIKit.ACCENT)
	box.add_child(UIKit.button("Başla", func():
		_close_overlay()
		phase = "play", 100))
	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu"), 80))


func _end_survival(won: bool) -> void:
	finished = true
	phase = "end"
	_dragging = false
	_press_base = -1
	_menu_base = -1
	_vibrate(160 if won else 250, 0.8)
	var prev_best := SaveData.survival_best
	var gold := SaveData.record_survival(state.time, survival.wave, won)
	_show_survival_end.call_deferred(won, gold, state.time > prev_best)


func _show_survival_end(won: bool, gold: int, record: bool) -> void:
	var box := _open_overlay()
	_add_title(box, "Zafer!" if won else "Kalen Düştü", 58, UIKit.ACCENT if won else UIKit.TEXT)
	if won:
		_add_title(box, "Rakip kalesini ele geçirdin.", 28, UIKit.TEXT)
	_add_title(box, "Dayandığın süre: %s" % _fmt_time(state.time), 34, UIKit.TEXT)
	_add_title(box, "Atlatılan dalga: %d" % survival.wave, 28, UIKit.MUTED)
	if record:
		_add_title(box, "Yeni rekor!", 34, UIKit.ACCENT)
	else:
		_add_title(box, "En iyi: %s" % _fmt_time(SaveData.survival_best), 26, UIKit.MUTED)
	_add_title(box, "+%d altın (mağaza)" % gold, 36, UIKit.ACCENT)
	box.add_child(UIKit.button("Tekrar Oyna", func(): Session.go("game"), 100))
	box.add_child(UIKit.button("Ana Menü", func(): Session.go("main_menu")))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _menu_base >= 0:
				_close_build_menu()
				return
			match phase:
				"play":
					_pause()
				"pause":
					_resume()
				"intro":
					Session.go("main_menu" if survival else "level_select")
				_:
					Session.go("main_menu")
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_pause()
