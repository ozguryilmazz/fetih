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
## Sürüklerken bir üs, parmak üstünde bu kadar (ms) kalırsa seçime eklenir.
## Hızlı geçilen aradaki üsler eklenmez. Parmağın kalktığı üs her zaman hedeftir.
const DWELL_MS := 180
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
## Çok oyunculu (Session.mode == "online")
var online := false
var _snap_timer := 0.0
var _pending_cmds: Array = []
var _eliminated := false
var _hover_base := -1
var _hover_ms := 0
## Maç başında hazır bekleyen görev ödülü (maç sonunda yeni ödül var mı diye).
var _quest_gold_start := 0

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

# Boss ve hava
var boss_dir: BossDirector
var _warns: Array = []      # {base, kind ("gaze"/"dragon"), until}
var _flames: Array = []     # {p, life, max, col, r} büyük alev/ışık patlaması
var _rain: Array = []       # yağmur çizgileri (ekran koordinatı)
var _bannered := {}         # olay türü -> bir kez gösterildi
# Maç özeti
var _history: Array = []    # [[zaman, [üs sayıları]]]
var _next_hist := 0.0
var _stats: Array = []      # oyuncu başına {biggest, captures, clash, kills}
# Çok oyunculu ifadeler ve rövanş
var _bubbles: Array = []    # {slot, e, life}
var _emote_row: Control
var _emote_btn: EmoteDraw.EmoteButton
var _emote_ready_ms := 0
var _restarting := false
var _rematch_btn: Button
var _rematch_label: Label
var _rematch_seen := {}     # bildirimi gösterilmiş rövanş isteyen slotlar


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_rng.randomize()
	_soldier_tex = _make_soldier_texture()
	if Session.mode == "online":
		_setup_online()
	elif Session.mode == "survival":
		_setup_survival()
	else:
		_setup_solo()
	_build_hud()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_quest_gold_start = SaveData.quests_ready_total()
	if online:
		_start_online_loading()
	else:
		_show_intro()


func _setup_online() -> void:
	online = true
	state = MatchState.from_setup(Net.setup)
	my_id = Net.my_slot
	bots = []
	params = {"boss": false, "par": 0}
	Net.match_ended.connect(_end_online)
	Net.emote_received.connect(_show_emote)
	Net.rematch_changed.connect(_on_rematch_changed)
	Net.match_started.connect(func(_d: Dictionary, _s: int):
		# Rövanş başladı: oyun ekranını yeni haritayla baştan aç.
		_restarting = true
		Session.go.call_deferred("game"))
	if Net.is_host:
		Net.command_received.connect(_on_net_command)
	else:
		Net.snapshot_received.connect(_on_net_snapshot)


func _on_net_command(_slot: int, cmd: Dictionary) -> void:
	_pending_cmds.append(cmd)


func _on_net_snapshot(snap: Dictionary) -> void:
	if not finished:
		state.apply_snapshot(snap)


## Maç başında iki tarafta da kısa yükleme ekranı; bitince oyun birlikte başlar.
func _start_online_loading() -> void:
	phase = "loading"
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var p := LoadingPanel.show_over(layer, "Savaş hazırlanıyor", 2.5)
	p.set_target(0.9)
	p.done.connect(func():
		layer.queue_free()
		_acc = 0.0
		phase = "play"
		_show_banner("Savaş başladı!"))
	get_tree().create_timer(1.2).timeout.connect(p.finish)


func _quest(id: String, n: float) -> void:
	# Çok oyunculu maçlar görevlere sayılmaz.
	if not online:
		SaveData.quest_add(id, n)


func _setup_solo() -> void:
	var setup := LevelSetup.create(Session.level, {
		"name": SaveData.player_name, "color": SaveData.color_index,
		"icon": SaveData.icon_index, "upgrades": SaveData.upgrades}, randi())
	state = setup["state"]
	bots = setup["bots"]
	params = setup["params"]
	boss_dir = setup["boss"]
	if params.get("weather", "") == "rain":
		for i in 90:
			_rain.append(Vector2(randf() * 760.0 - 20.0, randf() * 1320.0 - 20.0))


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
			if boss_dir:
				boss_dir.update(state, GameConfig.SIM_DT)
			for cmd in _pending_cmds:
				state.apply_command(cmd)
			_pending_cmds.clear()
			for bot in bots:
				for cmd in bot.update(state, GameConfig.SIM_DT):
					state.apply_command(cmd)
			state.step(GameConfig.SIM_DT)
			_record_history()
		if online and Net.is_host:
			_snap_timer -= delta
			if _snap_timer <= 0.0:
				_snap_timer = 1.0 / NetConfig.SNAPSHOT_HZ
				Net.send_snapshot(state.snapshot())
		_consume_events()
		_update_hud()
		_check_long_press()
		_check_dwell()
		_check_end()
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time / 0.4, 0.0, 1.0)
	if phase == "play" or phase == "end":
		_update_effects(delta)
		_update_emotes(delta)
	queue_redraw()


func _issue(cmd: Dictionary) -> void:
	# Çok oyunculuda istemci hamleyi host'a yollar; anında görünsün diye yerelde de uygular
	# (host'un sonraki durum paketi gerçeği getirir).
	if online and not Net.is_host:
		Net.send_command(cmd)
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
			"send":
				_stat(e["owner"], "biggest", e["n"], true)
			"capture":
				_stat(e["to"], "captures", 1)
				var col := state.player_color(e["to"])
				var r: float = GameConfig.BASE_TYPES["normal"]["radius"]
				_rings.append({"p": e["pos"], "life": 0.5, "max": 0.5, "col": col, "r0": r * 0.8, "r1": r * 2.4})
				_burst(e["pos"], col, 18, 220.0, 0.6, 4.5)
				_pop[e["base"]] = 0.35
				if e["to"] == my_id:
					_quest("captures", 1.0)
					_vibrate(35, 0.6)
					_shake(4.0, 0.15)
				elif e["from"] == my_id:
					bases_lost += 1
					_vibrate(90, 1.0)
					_shake(9.0, 0.25)
			"kill":
				_stat(e["killer"], "kills", e["n"])
				if e["killer"] == my_id:
					_quest("kills", e["n"])
			"clash_kill":
				_stat(e["killer"], "clash", e["n"])
				if e["killer"] == my_id:
					_quest("clash_kills", e["n"])
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
			"gaze_warn", "dragon_warn":
				var k: String = "gaze" if e["type"] == "gaze_warn" else "dragon"
				_warns.append({"base": e["base"], "kind": k, "until": state.time + BossDirector.WARN})
				_show_banner("Tepegöz sana bakıyor!" if k == "gaze" else "Ejderha geliyor!")
				_vibrate(40, 0.4)
			"gaze":
				_warns = _warns.filter(func(w): return w["kind"] != "gaze")
				_flames.append({"p": e["pos"], "life": 0.8, "max": 0.8, "col": Color("#ff5252"), "r": 120.0})
				_burst(e["pos"], Color("#ff8a80"), 24, 240.0, 0.7, 4.5)
				_shake(8.0, 0.3)
				_vibrate(120, 0.9)
			"dragon_fire":
				_warns = _warns.filter(func(w): return w["kind"] != "dragon")
				_flames.append({"p": e["pos"], "life": 1.2, "max": 1.2, "col": Color("#ff9f1c"), "r": 170.0})
				_burst(e["pos"], Color("#ff6d00"), 40, 300.0, 0.9, 6.0)
				_burst(e["pos"], Color("#ffd166"), 24, 200.0, 0.7, 4.0)
				_show_banner("Ejderha ateş püskürttü!")
				_shake(14.0, 0.5)
				_vibrate(220, 1.0)
			"poison_place":
				_rings.append({"p": e["pos"], "life": 0.6, "max": 0.6, "col": Color("#7dff8a"), "r0": 10.0, "r1": GameConfig.POISON_RADIUS})
				if not _bannered.has("poison"):
					_bannered["poison"] = true
					_show_banner("Şahmeran yola zehir bıraktı!")
			"poison_kill":
				if _rng.randf() < 0.5:
					_burst(e["pos"], Color("#7dff8a"), 2, 60.0, 0.4, 3.0)
			"darkness":
				_show_banner("Karakoncolos geceyi çağırdı!")
				_vibrate(50, 0.5)
			"rebirth":
				_flames.append({"p": e["pos"], "life": 1.4, "max": 1.4, "col": Color("#19c39a"), "r": 160.0})
				_rings.append({"p": e["pos"], "life": 1.0, "max": 1.0, "col": Color("#ffd166"), "r0": 40.0, "r1": 220.0})
				_burst(e["pos"], Color("#ff9f1c"), 36, 260.0, 1.0, 5.5)
				_burst(e["pos"], Color("#19c39a"), 24, 200.0, 1.0, 5.0)
				_pop[e["base"]] = 0.35
				_show_banner("Zümrüdüanka küllerinden doğdu!")
				_shake(10.0, 0.4)
				_vibrate(150, 0.9)
	state.events.clear()


func _stat(owner: int, key: String, n: float, is_max := false) -> void:
	if owner < 0:
		return
	while _stats.size() <= owner:
		_stats.append({"biggest": 0.0, "captures": 0.0, "clash": 0.0, "kills": 0.0})
	if is_max:
		_stats[owner][key] = maxf(_stats[owner][key], n)
	else:
		_stats[owner][key] += n


## Oyuncuların üs sayısını düzenli kaydeder (maç sonu grafiği).
func _record_history() -> void:
	if state.time < _next_hist:
		return
	_next_hist = state.time + (1.0 if state.time < 120.0 else 2.0)
	var counts: Array = []
	for p in state.players:
		counts.append(0)
	for b in state.bases:
		if b["owner"] >= 0 and b["owner"] < counts.size():
			counts[b["owner"]] += 1
	_history.append([state.time, counts])


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
	for f in _flames:
		f["life"] -= delta
	_flames = _flames.filter(func(f): return f["life"] > 0.0)
	_warns = _warns.filter(func(w): return w["until"] > state.time - 0.1)
	for i in _rain.size():
		var r: Vector2 = _rain[i] + Vector2(-140.0, 900.0) * delta
		if r.y > 1300.0:
			r = Vector2(randf() * 900.0, -30.0)
		_rain[i] = r
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
					_hover_base = -1
					_vibrate(12, 0.3)
		else:
			_press_base = -1
			if _dragging:
				# Parmağın kalktığı üs, beklenmemiş olsa da hedef olur.
				var rb := _base_at(p)
				if rb >= 0:
					_touch_base(rb)
				_finish_drag()
	elif event is InputEventScreenDrag and event.index == 0:
		_finger = make_input_local(event).position
		if _press_base >= 0 and _finger.distance_to(_press_pos) > LONG_PRESS_SLOP:
			_press_base = -1
		if _dragging:
			var b := _base_at(_finger)
			if b != _hover_base:
				_hover_base = b
				_hover_ms = Time.get_ticks_msec()


## Parmak bir üsün üstünde yeterince beklediyse o üsü seçime ekler.
func _check_dwell() -> void:
	if not _dragging or _hover_base < 0:
		return
	if Time.get_ticks_msec() - _hover_ms >= DWELL_MS:
		_touch_base(_hover_base)


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
	_hover_base = -1
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
	var full := Rect2(-position - Vector2(20, 20), vis + Vector2(40, 40))
	draw_texture_rect(Art.ground(), full, true)
	draw_texture_rect(Art.vignette(), full, false)
	var fog := _fog_level()
	if fog > 0.0:
		draw_rect(full, Color(0.02, 0.03, 0.08, fog))
		for b in state.bases:
			if b["owner"] == my_id:
				for k in 3:
					draw_circle(b["pos"], GameConfig.NIGHT_VISION * (0.55 + k * 0.22), Color(1.0, 0.93, 0.7, 0.035))
	_draw_hazards()

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
		_draw_column(g, fog > 0.0)

	for r in _rings:
		var k: float = 1.0 - r["life"] / r["max"]
		var col: Color = r["col"]
		col.a = 1.0 - k
		draw_arc(r["p"], lerpf(r["r0"], r["r1"], k), 0.0, TAU, 56, col, lerpf(10.0, 2.0, k), true)

	for b in state.bases:
		if fog > 0.0 and not _visible(b["pos"]):
			_draw_hidden_base(b)
		else:
			_draw_base(b)
	_draw_warns()
	_draw_bubbles()

	for f in _flames:
		var k: float = 1.0 - f["life"] / f["max"]
		var col: Color = f["col"]
		for j in 3:
			col.a = (1.0 - k) * (0.35 - j * 0.1)
			draw_circle(f["p"], f["r"] * (0.4 + k * 0.6) * (1.0 - j * 0.25), col)

	for p in _particles:
		var col: Color = p["col"]
		col.a = clampf(p["life"] / p["max"], 0.0, 1.0)
		draw_circle(p["p"], p["r"] * (0.5 + 0.5 * col.a), col)

	if not _rain.is_empty():
		var off := -position
		for r in _rain:
			draw_line(off + r, off + r + Vector2(-7, 44), Color(0.75, 0.85, 1.0, 0.32), 2.0)


## 0 = açık; gece ve Karakoncolos karanlığında haritanın kararma miktarı.
func _fog_level() -> float:
	if state.time < state.dark_until:
		return 0.72
	if params.get("weather", "") == "night":
		return 0.55
	return 0.0


## Gece/karanlıkta bir nokta, kendi üslerinden birinin görüş mesafesinde mi?
func _visible(p: Vector2) -> bool:
	for b in state.bases:
		if b["owner"] == my_id and p.distance_to(b["pos"]) <= GameConfig.NIGHT_VISION:
			return true
	return false


## Karanlıkta görünmeyen üs: sadece belli belirsiz bir gölge (sahibi ve askeri gizli).
func _draw_hidden_base(b: Dictionary) -> void:
	var r: float = state.base_type(b)["radius"]
	draw_circle(b["pos"], r, Color(0.5, 0.55, 0.7, 0.10))
	draw_arc(b["pos"], r, 0.0, TAU, 40, Color(0.7, 0.75, 0.9, 0.22), 2.0, true)
	_text_centered("?", b["pos"], 28, Color(1, 1, 1, 0.25))


## Şahmeran'ın zehir gölleri: zamanla küçülüp solar.
func _draw_hazards() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for h in state.hazards:
		var left: float = h["until"] - state.time
		var age: float = state.time - h["born"]
		var a := clampf(left / 2.0, 0.0, 1.0) * clampf(age / 0.4, 0.0, 1.0)
		var r: float = h["r"] * (0.75 + 0.25 * clampf(left / 2.0, 0.0, 1.0))
		var c: Vector2 = h["pos"]
		draw_circle(c, r, Color(0.2, 0.75, 0.25, 0.30 * a))
		draw_circle(c, r * 0.7, Color(0.35, 0.95, 0.35, 0.25 * a))
		draw_arc(c, r, 0.0, TAU, 40, Color(0.5, 1.0, 0.5, 0.55 * a), 3.0, true)
		for k in 5:
			var ph := fmod(t * 0.9 + k * 0.37 + h["born"], 1.0)
			var bp := c + Vector2(cos(k * 2.4 + h["born"]), sin(k * 1.7 + h["born"])) * r * 0.55
			draw_arc(bp, 3.0 + ph * 6.0, 0.0, TAU, 12, Color(0.75, 1.0, 0.7, (1.0 - ph) * 0.7 * a), 2.0, true)


## Tepegöz'ün gözü / Ejderha'nın gölgesi: vuruştan önceki uyarı.
func _draw_warns() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for w in _warns:
		var b: Dictionary = state.bases[w["base"]]
		var c: Vector2 = b["pos"]
		var r: float = state.base_type(b)["radius"]
		var k := clampf(1.0 - (w["until"] - state.time) / BossDirector.WARN, 0.0, 1.0)
		if w["kind"] == "gaze":
			var pulse := 0.5 + 0.5 * sin(t * 14.0)
			draw_arc(c, r + 14.0 + pulse * 6.0, 0.0, TAU, 56, Color(1.0, 0.25, 0.25, 0.5 + 0.4 * k), 5.0, true)
			var eye := c + Vector2(0, -r - 46.0)
			var pts := PackedVector2Array()
			for i in 24:
				var a := TAU * i / 24.0
				pts.append(eye + Vector2(cos(a) * 30.0, sin(a) * 18.0 * (0.4 + 0.6 * k)))
			draw_colored_polygon(pts, Color("#fff8ec"))
			draw_circle(eye, 11.0 * (0.4 + 0.6 * k), Color("#c0392b"))
			draw_circle(eye, 5.0 * (0.4 + 0.6 * k), Color("#1a0f0a"))
		else:
			# Ejderha gölgesi yaklaşır ve büyür
			var sc := lerpf(0.4, 1.3, k)
			var sp := c + Vector2(lerpf(-260.0, 0.0, k), lerpf(-160.0, 0.0, k))
			var shadow := Color(0, 0, 0, 0.25 + 0.25 * k)
			var wing := PackedVector2Array([sp + Vector2(-90, -10) * sc, sp + Vector2(-20, -24) * sc, sp + Vector2(0, -50) * sc,
				sp + Vector2(20, -24) * sc, sp + Vector2(90, -10) * sc, sp + Vector2(20, 6) * sc, sp + Vector2(0, 40) * sc, sp + Vector2(-20, 6) * sc])
			draw_colored_polygon(wing, shadow)
			draw_arc(c, r + 14.0, 0.0, TAU, 56, Color(1.0, 0.6, 0.1, 0.4 + 0.5 * k), 5.0, true)


## Asker kolunu sıra sıra çizer. Henüz üssün içinde olan askerler görünmez.
func _draw_column(g: Dictionary, fogged := false) -> void:
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
		if fogged and g["owner"] != my_id and not _visible(pos):
			continue
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

	# Yere düşen gölge
	draw_circle(c + Vector2(4, 12), r * 1.02, Color(0, 0, 0, 0.32))
	if state.is_full(b):
		_draw_full_glow(c, r, col, id)
	var kind: String = b["type"]
	if kind == "fortress" or kind == "keep" or kind == "citadel":
		_draw_fortress(c, r, col)
	# Derinlik: alt kalınlık + kubbe gölgelendirmesi + parlama + ince kenar
	draw_circle(c + Vector2(0, 6), r, col.darkened(0.45))
	var body := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
	draw_texture_rect(Art.ball(), body, false, col.lightened(0.12))
	draw_texture_rect(Art.gloss(), body, false)
	var rim := col.lightened(0.35)
	rim.a = 0.55
	draw_arc(c, r - 2.0, 0.0, TAU, 56, rim, 3.0, true)
	if kind == "barracks":
		_draw_barracks(c, r, col, b.get("level", 1))
	elif kind == "mine":
		_draw_mine(c, r, b.get("level", 1))
	elif kind == "fortress" and owner == 1 and params.get("boss_kind", "") != "":
		BossArt.draw(self, params["boss_kind"], c + Vector2(0, -2), r * 0.8, Time.get_ticks_msec() / 1000.0)
	elif owner != GameConfig.NEUTRAL:
		IconDraw.draw_icon(self, state.players[owner]["icon"], c, r * 0.6, Color(1, 1, 1, 0.22))
	if b.get("shielded", false):
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
		draw_arc(c, r + 16.0, 0.0, TAU, 64, Color(0.55, 0.8, 1.0, 0.35 + 0.3 * pulse), 6.0, true)
		draw_circle(c, r + 14.0, Color(0.55, 0.8, 1.0, 0.08))

	if _dragging and id == _hover_base and not _sources.has(id) and not _targets.has(id):
		# Bekleme göstergesi: halka dolunca üs seçime eklenir.
		var k := clampf(float(Time.get_ticks_msec() - _hover_ms) / DWELL_MS, 0.0, 1.0)
		draw_arc(c, r + 8.0, -PI / 2, -PI / 2 + TAU * k, 48, Color(1, 1, 1, 0.7), 4.0, true)
	if _dragging and _sources.has(id):
		draw_arc(c, r + 8.0, 0.0, TAU, 48, Color.WHITE, 5.0, true)
	elif _dragging and _targets.has(id):
		draw_arc(c, r + 8.0, 0.0, TAU, 48, UIKit.ACCENT, 5.0, true)

	if kind == "mine":
		# Maden: normal + 2 güçlü maden askeri (altın renkte).
		_text_centered(str(int(b["troops"] + b.get("elite", 0.0))), c, 30, Color("#ffe082"))
	else:
		var tc := c
		if kind == "fortress" and owner == 1 and params.get("boss_kind", "") != "":
			tc = c + Vector2(0, r + 26.0)  # sayı resmin altında
		_text_centered(str(int(b["troops"])), tc, 30, Color.WHITE)
	if b.get("rebirth", false):
		var fl := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
		draw_arc(c, r + 22.0, 0.0, TAU, 56, Color(0.1, 0.76, 0.6, 0.25 + 0.25 * fl), 4.0, true)


## Dolu üs (üretim durdu): çevresinde nabız gibi atan parlama.
func _draw_full_glow(c: Vector2, r: float, col: Color, id: int) -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0 + id)
	var glow := col.lightened(0.5)
	for k in 3:
		glow.a = (0.65 - k * 0.18) * (0.55 + 0.45 * pulse)
		draw_arc(c, r + 7.0 + k * 6.0 + pulse * 3.0, 0.0, TAU, 64, glow, 6.0, true)


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
		title += "  ·  " + GameConfig.BOSS_INFO[params["boss_kind"]]["name"]
	match params.get("weather", ""):
		"night":
			title += "  ·  Gece"
		"rain":
			title += "  ·  Yağmur"
	if survival:
		title = "Hayatta Kalma"
	if online:
		title = "Çok Oyunculu  ·  Oda %s" % Net.code
	var tl := UIKit.label(title, 32 if title.length() < 22 else 26)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.clip_text = true
	info.add_child(tl)
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
	if online:
		_build_emote_ui(root)
	_update_hud()


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner_time = 2.2


func _update_hud() -> void:
	if online:
		_time_label.text = _fmt_time(state.time)
		var names: Array = []
		for p in state.players:
			var count := state.bases.filter(func(b): return b["owner"] == p["id"]).size()
			names.append("%s %d" % [p["name"], count])
		_loss_label.text = "   ".join(names)
		return
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

func _show_intro(skip_legend := false) -> void:
	phase = "intro"
	if survival:
		_show_survival_intro()
		return
	if params["boss"] and not skip_legend:
		_show_legend()
		return
	var box := _open_overlay()
	_add_title(box, "Bölüm %d" % Session.level, 54, UIKit.TEXT)
	if params["boss"]:
		var info: Dictionary = GameConfig.BOSS_INFO[params["boss_kind"]]
		_add_title(box, "BOSS: %s" % info["name"], 34, Color("#ff8a80"))
		_add_title(box, info["power"], 22, UIKit.MUTED)
	match params.get("weather", ""):
		"night":
			_add_title(box, "Gece", 34, Color("#9fb4ff"))
			_add_title(box, "Karanlıkta sadece kendi üslerinin yakınını görebilirsin.", 22, UIKit.MUTED)
		"rain":
			_add_title(box, "Yağmur", 34, Color("#9fd3ff"))
			_add_title(box, "Çamurlu yollarda bütün askerler %%%d daha yavaş yürür." % int(round((1.0 - GameConfig.RAIN_SPEED) * 100)), 22, UIKit.MUTED)
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


## Boss bölümü girişi: yaratığın resmi ve efsanesi (yazı akarak gelir, "Geç" ile atlanır).
func _show_legend() -> void:
	var info: Dictionary = GameConfig.BOSS_INFO[params["boss_kind"]]
	var box := _open_overlay(0.82)
	var portrait := BossArt.Portrait.new()
	portrait.kind = params["boss_kind"]
	portrait.custom_minimum_size = Vector2(0, 320)
	box.add_child(portrait)
	_add_title(box, info["name"], 54, BossArt.color(params["boss_kind"]).lightened(0.3))
	var story := UIKit.label(info["legend"], 26, UIKit.TEXT)
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story.visible_ratio = 0.0
	box.add_child(story)
	var power := UIKit.label("Gücü: " + info["power"], 23, UIKit.ACCENT)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power.modulate.a = 0.0
	box.add_child(power)
	var btn := UIKit.button("Geç", func(): _show_intro(true), 96)
	box.add_child(btn)
	var tw := story.create_tween()  # pano kapanınca tween de durur
	tw.tween_property(story, "visible_ratio", 1.0, info["legend"].length() / 38.0)
	tw.tween_property(power, "modulate:a", 1.0, 0.5)
	tw.tween_callback(func(): btn.text = "Devam")


func _pause() -> void:
	if online:
		_online_menu()
		return
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
	if online:
		var alive := state.alive_players()
		if not alive.has(my_id) and not _eliminated:
			_eliminated = true
			_dragging = false
			_show_banner("Elendin! Maçı izliyorsun.")
		if Net.is_host and alive.size() <= 1:
			Net.finish(alive[0] if alive.size() == 1 else -1)
		return
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
	_add_goals(box, _goals(won))
	_add_summary(box)
	if won:
		var note := ""
		if stars <= prev:
			note = "  (tekrar)"
		elif prev > 0:
			note = "  (yeni rekor!)"
		_add_title(box, "+%d altın%s" % [gold, note], 36, UIKit.ACCENT)
		_add_quest_note(box)
		if Session.level < GameConfig.MAX_LEVEL:
			box.add_child(UIKit.button("Sonraki Bölüm", func():
				Session.level += 1
				Session.go("game"), 100))
		else:
			_add_title(box, "Tüm bölümleri bitirdin!", 30, UIKit.ACCENT)
	else:
		_add_quest_note(box)
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
	_add_summary(box, false)
	if record:
		_add_title(box, "Yeni rekor!", 34, UIKit.ACCENT)
	else:
		_add_title(box, "En iyi: %s" % _fmt_time(SaveData.survival_best), 26, UIKit.MUTED)
	_add_title(box, "+%d altın (mağaza)" % gold, 36, UIKit.ACCENT)
	_add_quest_note(box)
	box.add_child(UIKit.button("Tekrar Oyna", func(): Session.go("game"), 100))
	box.add_child(UIKit.button("Ana Menü", func(): Session.go("main_menu")))


## Maç özeti: üs sayısı grafiği + öne çıkanlar (en büyük saldırı, en çok fetih, yol savaşı).
func _add_summary(box: VBoxContainer, with_time := true) -> void:
	_record_history()
	var counts: Array = []
	for p in state.players:
		counts.append(state.bases.filter(func(b): return b["owner"] == p["id"]).size())
	_history.append([state.time, counts])
	var head := "Maç özeti"
	if with_time:
		head += "  ·  süre %s" % _fmt_time(state.time)
	box.add_child(UIKit.label(head, 24, UIKit.MUTED))
	var chart := MatchSummary.new()
	chart.history = _history
	for p in state.players:
		chart.colors.append(state.player_color(p["id"]))
	chart.custom_minimum_size = Vector2(0, 170)
	box.add_child(chart)
	var lines: Array = []
	for item in [["biggest", "En büyük saldırı", "asker"], ["captures", "En çok üs alan", "üs"], ["clash", "Yol savaşı ustası", "asker"]]:
		var best := -1
		var val := 0.0
		for i in _stats.size():
			if i < state.players.size() and _stats[i][item[0]] > val:
				val = _stats[i][item[0]]
				best = i
		if best >= 0:
			lines.append("%s: [color=#%s]%s[/color] (%d %s)" % [item[1], state.player_color(best).lightened(0.25).to_html(false), state.players[best]["name"], int(val), item[2]])
	if not lines.is_empty():
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.add_theme_font_size_override("normal_font_size", 22)
		rt.add_theme_color_override("default_color", UIKit.TEXT)
		rt.text = "\n".join(lines)
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rt)


## Maçta yeni görev ödülü hazır olduysa bitiş panelinde göster.
func _add_quest_note(box: VBoxContainer) -> void:
	var ready := SaveData.quests_ready_total()
	if ready > _quest_gold_start:
		_add_title(box, "Görev ödülü hazır: +%d altın (Görevler)" % ready, 26, Color("#8be28b"))


func _exit_tree() -> void:
	# Maç yarıda bırakılsa da görev ilerlemesi kaybolmasın.
	SaveData.save()
	if online and not _restarting:
		Net.leave()


# ---------------------------------------------------------------- çok oyunculu

const EMOTE_COOLDOWN_MS := 2000
const BUBBLE_TIME := 2.5


func _build_emote_ui(root: Control) -> void:
	_emote_btn = EmoteDraw.EmoteButton.new()
	_emote_btn.emote = 0
	_emote_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_emote_btn.offset_left = -116
	_emote_btn.offset_top = -116
	_emote_btn.offset_right = -24
	_emote_btn.offset_bottom = -24
	_emote_btn.pressed.connect(func(): _emote_row.visible = not _emote_row.visible)
	root.add_child(_emote_btn)
	_emote_row = HBoxContainer.new()
	_emote_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_emote_row.offset_left = 24
	_emote_row.offset_right = -24
	_emote_row.offset_top = -224
	_emote_row.offset_bottom = -132
	_emote_row.alignment = BoxContainer.ALIGNMENT_END
	_emote_row.add_theme_constant_override("separation", 10)
	_emote_row.visible = false
	root.add_child(_emote_row)
	for i in EmoteDraw.COUNT:
		var b := EmoteDraw.EmoteButton.new()
		b.emote = i
		b.custom_minimum_size = Vector2(98, 92)
		var idx := i
		b.pressed.connect(func(): _send_emote(idx))
		_emote_row.add_child(b)


func _send_emote(e: int) -> void:
	_emote_row.visible = false
	if Time.get_ticks_msec() < _emote_ready_ms or finished:
		return
	_emote_ready_ms = Time.get_ticks_msec() + EMOTE_COOLDOWN_MS
	Net.send_emote(e)
	_show_emote(my_id, e)


func _show_emote(slot: int, e: int) -> void:
	_bubbles = _bubbles.filter(func(b): return b["slot"] != slot)
	_bubbles.append({"slot": slot, "e": e, "life": BUBBLE_TIME})
	if slot != my_id:
		_vibrate(15, 0.3)


func _update_emotes(delta: float) -> void:
	for b in _bubbles:
		b["life"] -= delta
	_bubbles = _bubbles.filter(func(b): return b["life"] > 0.0)
	if _emote_btn:
		var d := Time.get_ticks_msec() < _emote_ready_ms
		if d != _emote_btn.dim:
			_emote_btn.dim = d
			_emote_btn.queue_redraw()


## İfade balonu: gönderenin en kalabalık üssünün üstünde (üssü yoksa ekranın üstünde).
func _draw_bubbles() -> void:
	for bb in _bubbles:
		var best := -1
		var most := -1.0
		for b in state.bases:
			if b["owner"] == bb["slot"] and b["troops"] > most:
				most = b["troops"]
				best = b["id"]
		var anchor := Vector2(GameConfig.MAP_SIZE.x / 2.0, 150.0)
		if best >= 0:
			anchor = state.bases[best]["pos"] + Vector2(0, -float(state.base_type(state.bases[best])["radius"]) - 52.0)
		var age: float = BUBBLE_TIME - bb["life"]
		var sc := minf(1.0, age / 0.15) * (1.0 + 0.15 * maxf(0.0, 1.0 - age / 0.3))
		var a := clampf(bb["life"] / 0.4, 0.0, 1.0)
		anchor.y = maxf(anchor.y, 60.0)
		var col := state.player_color(bb["slot"])
		var r := 40.0 * sc
		draw_colored_polygon(PackedVector2Array([anchor + Vector2(-12, r * 0.7), anchor + Vector2(12, r * 0.7), anchor + Vector2(0, r + 18.0)]), Color(1, 1, 1, 0.95 * a))
		draw_circle(anchor, r + 4.0, Color(col.r, col.g, col.b, a))
		draw_circle(anchor, r, Color(1, 1, 1, 0.95 * a))
		if a > 0.05:
			EmoteDraw.draw(self, bb["e"], anchor, r * 0.62)


func _on_rematch_changed(info: Dictionary) -> void:
	if not _rematch_label:
		return
	if info["gone"]:
		_rematch_label.text = "Rakip ayrıldı, rövanş yok."
		_rematch_label.add_theme_color_override("font_color", UIKit.MUTED)
		_rematch_btn.disabled = true
		return
	var votes: Array = info["votes"]
	# Rövanş isteyen diğer oyuncular: belirgin bildirim + titreşim (her oyuncu için bir kez).
	var askers: Array = []
	for v in votes:
		if v != my_id and v < state.players.size():
			askers.append(state.players[v]["name"])
			if not _rematch_seen.has(v):
				_rematch_seen[v] = true
				_vibrate(120, 0.9)
				_pulse(_rematch_btn)
	if votes.has(my_id):
		_rematch_btn.disabled = true
		_rematch_btn.text = "Rövanş istendi"
		var waiting := int(info["total"]) - votes.size()
		if waiting > 0:
			_rematch_label.text = "Rövanş isteğin gönderildi. Rakibin cevabı bekleniyor..."
			_rematch_label.add_theme_color_override("font_color", UIKit.MUTED)
	elif not askers.is_empty():
		_rematch_label.text = "%s rövanş istiyor!" % ", ".join(askers)
		_rematch_label.add_theme_font_size_override("font_size", 32)
		_rematch_label.add_theme_color_override("font_color", UIKit.ACCENT)
		_rematch_btn.text = "Rövanşı Kabul Et"
	if Net.is_host and votes.size() >= int(info["total"]):
		_rematch_label.text = "Yeni harita kuruluyor..."
		var players: Array = []
		for p in state.players:
			players.append(MatchState.make_player(p["id"], p["name"], p["color"], p["icon"], false, {}))
		Net.start_rematch(MatchState.create(randi(), players, 8 + 3 * players.size(), 6, 16))
	elif votes.size() >= int(info["total"]):
		_rematch_label.text = "Yeni harita kuruluyor..."


## Dikkat çeksin diye düğmeyi birkaç kez büyütüp küçültür.
func _pulse(c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	for i in 3:
		tw.tween_property(c, "scale", Vector2(1.08, 1.08), 0.15)
		tw.tween_property(c, "scale", Vector2.ONE, 0.15)


## Oyun durmaz (ortak maç); sadece çıkış seçeneği sunar.
func _online_menu() -> void:
	if finished or _overlay_layer:
		return
	_dragging = false
	var box := _open_overlay(0.45)
	_add_title(box, "Çok Oyunculu", 46, UIKit.TEXT)
	_add_title(box, "Oyun arkada devam ediyor.", 24, UIKit.MUTED)
	box.add_child(UIKit.button("Oyuna Dön", _close_overlay, 100))
	box.add_child(UIKit.button("Oyundan Çık", func():
		Net.leave()
		Session.go("multiplayer")))


func _end_online(info: Dictionary) -> void:
	if finished:
		return
	finished = true
	phase = "end"
	_dragging = false
	_close_overlay()
	if _emote_btn:
		_emote_btn.visible = false
		_emote_row.visible = false
	var reason: String = info.get("reason", "")
	var title := "Oyun Bitti"
	var sub := ""
	var gold := 0
	var col := UIKit.TEXT
	if reason == "win":
		var w := int(info.get("winner", -1))
		if w == my_id:
			title = "Kazandın!"
			col = UIKit.ACCENT
			gold = NetConfig.WIN_GOLD
		else:
			title = "Kaybettin"
			gold = NetConfig.LOSE_GOLD
			if w >= 0 and w < state.players.size():
				sub = "Kazanan: %s" % state.players[w]["name"]
	elif reason == "disconnect":
		title = "Bağlantı Koptu"
		sub = "%s oyundan düştü. Maç sona erdi." % info.get("name", "Bir oyuncu")
	else:
		title = "Oyun Sona Erdi"
		sub = "Bir oyuncu oyundan çıktı."
	if gold > 0:
		SaveData.gold += gold
		SaveData.save()
	_vibrate(160, 0.8)
	var box := _open_overlay()
	_add_title(box, title, 56, col)
	if sub != "":
		_add_title(box, sub, 28, UIKit.TEXT)
	if gold > 0:
		_add_title(box, "+%d altın" % gold, 36, UIKit.ACCENT)
	_add_summary(box)
	if reason == "win":
		_rematch_label = UIKit.label("Rövanş ister misin?", 24, UIKit.MUTED)
		_rematch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_rematch_label)
		_rematch_btn = UIKit.button("Rövanş", func(): Net.vote_rematch(), 100)
		box.add_child(_rematch_btn)
		_on_rematch_changed.call_deferred(Net.rematch_info())
	box.add_child(UIKit.button("Çok Oyunculu", func():
		Net.leave()
		Session.go("multiplayer"), 84 if reason == "win" else 100))
	box.add_child(UIKit.button("Ana Menü", func():
		Net.leave()
		Session.go("main_menu")))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if online and not finished:
				if _overlay_layer:
					_close_overlay()
				else:
					_online_menu()
				return
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
			if not online:
				_pause()
