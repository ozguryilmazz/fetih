class_name BossDirector
extends RefCounted
## Boss bölümlerindeki özel yetenekler. Her simülasyon adımında update() çağrılır.
## Görseller için MatchState.events'e olay ekler. Oyuncu = 0, boss = 1.
##   tepegoz:      gaze_warn {base} -> 2 sn sonra gaze {base}
##   sahmeran:     poison_place {pos}
##   karakoncolos: darkness  (state.dark_until)
##   zumruduanka:  (kale "rebirth" bayrağı; MatchState çözer)
##   ejderha:      dragon_warn {base} -> 2 sn sonra dragon_fire {base}
##   albasti:      curse_warn {base} -> curse {base} (6 sn üretim/gönderim yok) -> curse_end
##   yelbegen:     roar_warn -> roar {targets}: kaleden üç ayrı ordu
##   erlik:        erlik_warn {base} -> erlik_take {base} veya erlik_drain {base}

const PLAYER := 0
const BOSS := 1
const WARN := 2.0

var kind := ""
var _timer := 0.0
var _warned := -1
var _dragon_times: Array = []
var _rng := RandomNumberGenerator.new()
var _cursed: Array = []   # [[üs id, bitiş zamanı]]
var _roar_warned := false


func _init(kind_: String, seed_val: int) -> void:
	kind = kind_
	_rng.seed = seed_val
	match kind:
		"tepegoz":
			_timer = 22.0
		"sahmeran":
			_timer = 8.0
		"karakoncolos":
			_timer = 10.0
		"ejderha":
			_dragon_times = [_rng.randf_range(35.0, 60.0), _rng.randf_range(90.0, 130.0)]
		"albasti":
			_timer = 15.0
		"yelbegen":
			_timer = 25.0
		"erlik":
			_timer = 18.0


func setup(state: MatchState) -> void:
	if kind == "zumruduanka":
		for b in state.bases:
			if b["owner"] == BOSS and b["type"] == "fortress":
				b["rebirth"] = true


func update(state: MatchState, dt: float) -> void:
	_expire_curses(state)
	if not state.alive_players().has(BOSS):
		return
	match kind:
		"tepegoz":
			_tepegoz(state, dt)
		"sahmeran":
			_sahmeran(state, dt)
		"karakoncolos":
			_karakoncolos(state, dt)
		"ejderha":
			_ejderha(state)
		"albasti":
			_albasti(state, dt)
		"yelbegen":
			_yelbegen(state, dt)
		"erlik":
			_erlik(state, dt)


static func _biggest(state: MatchState, owner: int) -> int:
	var best := -1
	var most := -1.0
	for b in state.bases:
		if b["owner"] == owner and b["troops"] > most:
			most = b["troops"]
			best = b["id"]
	return best


func _tepegoz(state: MatchState, dt: float) -> void:
	_timer -= dt
	if _timer <= WARN and _warned < 0:
		_warned = _biggest(state, PLAYER)
		if _warned >= 0:
			state.events.append({"type": "gaze_warn", "base": _warned, "pos": state.bases[_warned]["pos"]})
	if _timer <= 0.0:
		_timer = GameConfig.TEPEGOZ_INTERVAL
		var t := _warned
		_warned = -1
		if t < 0 or state.bases[t]["owner"] != PLAYER:
			t = _biggest(state, PLAYER)
		if t >= 0:
			state.bases[t]["troops"] *= GameConfig.TEPEGOZ_FACTOR
			state.events.append({"type": "gaze", "base": t, "pos": state.bases[t]["pos"]})


func _sahmeran(state: MatchState, dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = GameConfig.POISON_INTERVAL
	# Oyuncunun bir üssü ile ona en yakın başkasının üssü arasındaki yolun ortasına.
	var options: Array = []
	for a in state.bases:
		if a["owner"] != PLAYER:
			continue
		var near := {}
		var nd := INF
		for b in state.bases:
			if b["owner"] == PLAYER:
				continue
			var d: float = a["pos"].distance_to(b["pos"])
			if d < nd:
				nd = d
				near = b
		if not near.is_empty():
			options.append(a["pos"].lerp(near["pos"], _rng.randf_range(0.35, 0.65)))
	if options.is_empty():
		return
	var pos: Vector2 = options[_rng.randi() % options.size()]
	state.hazards.append({"kind": "poison", "pos": pos, "r": GameConfig.POISON_RADIUS,
		"until": state.time + GameConfig.POISON_DURATION, "owner": BOSS, "born": state.time})
	state.events.append({"type": "poison_place", "pos": pos})


func _karakoncolos(state: MatchState, dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = GameConfig.DARK_INTERVAL
	state.dark_until = state.time + GameConfig.DARK_DURATION
	state.events.append({"type": "darkness"})


func _ejderha(state: MatchState) -> void:
	if _dragon_times.is_empty():
		return
	var t: float = _dragon_times[0]
	if state.time >= t - WARN and _warned < 0:
		_warned = _biggest(state, PLAYER)
		if _warned >= 0:
			state.events.append({"type": "dragon_warn", "base": _warned, "pos": state.bases[_warned]["pos"]})
	if state.time >= t:
		_dragon_times.pop_front()
		var target := _warned
		_warned = -1
		if target < 0 or state.bases[target]["owner"] != PLAYER:
			target = _biggest(state, PLAYER)
		if target >= 0:
			state.bases[target]["troops"] *= GameConfig.DRAGON_FACTOR
			state.events.append({"type": "dragon_fire", "base": target, "pos": state.bases[target]["pos"]})


## Bir oyuncunun en az askerli üssü; yoksa -1.
static func _weakest(state: MatchState, owner: int) -> int:
	var best := -1
	var least := INF
	for b in state.bases:
		if b["owner"] == owner and b["troops"] < least:
			least = b["troops"]
			best = b["id"]
	return best


## Uyarı + vuruş kalıbı: süre dolmadan WARN sn önce hedef seçilip uyarı olayı yollanır.
## Vuruş anında hedef seçilmiş (hâlâ oyuncunun) üs ya da yeniden seçilen üs döner; yoksa -1.
func _warn_then_hit(state: MatchState, dt: float, interval: float, warn_type: String, pick: Callable) -> int:
	_timer -= dt
	if _timer <= WARN and _warned < 0:
		_warned = pick.call()
		if _warned >= 0:
			state.events.append({"type": warn_type, "base": _warned, "pos": state.bases[_warned]["pos"]})
	if _timer > 0.0:
		return -1
	_timer = interval
	var t := _warned
	_warned = -1
	if t < 0 or state.bases[t]["owner"] != PLAYER:
		t = pick.call()
	return t


func _albasti(state: MatchState, dt: float) -> void:
	var t := _warn_then_hit(state, dt, GameConfig.CURSE_INTERVAL, "curse_warn", func(): return _biggest(state, PLAYER))
	if t < 0:
		return
	state.bases[t]["cursed"] = true
	_cursed.append([t, state.time + GameConfig.CURSE_DURATION])
	state.events.append({"type": "curse", "base": t, "pos": state.bases[t]["pos"]})


func _expire_curses(state: MatchState) -> void:
	if _cursed.is_empty():
		return
	var keep: Array = []
	for c in _cursed:
		if state.time >= c[1]:
			state.bases[c[0]].erase("cursed")
			state.events.append({"type": "curse_end", "base": c[0], "pos": state.bases[c[0]]["pos"]})
		else:
			keep.append(c)
	_cursed = keep


func _yelbegen(state: MatchState, dt: float) -> void:
	_timer -= dt
	if _timer <= WARN and not _roar_warned:
		_roar_warned = true
		state.events.append({"type": "roar_warn"})
	if _timer > 0.0:
		return
	_timer = GameConfig.ROAR_INTERVAL
	_roar_warned = false
	var home := -1
	for b in state.bases:
		if b["owner"] == BOSS and b["type"] == "fortress":
			home = b["id"]
	if home < 0:
		home = _biggest(state, BOSS)  # kalesi düştüyse en kalabalık üssünden
	if home < 0:
		return
	var hp: Vector2 = state.bases[home]["pos"]
	var targets: Array = state.bases.filter(func(b): return b["owner"] == PLAYER)
	targets.sort_custom(func(a, b): return a["pos"].distance_to(hp) < b["pos"].distance_to(hp))
	var n := int(minf(20.0, 6.0 + state.time / 15.0))
	var ids: Array = []
	for b in targets.slice(0, 3):
		state.spawn_wave(BOSS, home, b["id"], n)
		ids.append(b["id"])
	if not ids.is_empty():
		state.events.append({"type": "roar", "targets": ids, "pos": hp})


func _erlik(state: MatchState, dt: float) -> void:
	var t := _warn_then_hit(state, dt, GameConfig.ERLIK_INTERVAL, "erlik_warn", func(): return _weakest(state, PLAYER))
	if t < 0:
		return
	var b: Dictionary = state.bases[t]
	if b["troops"] < GameConfig.ERLIK_TAKE_BELOW:
		b["owner"] = BOSS
		b["troops"] = 10.0
		b.erase("cursed")
		state.events.append({"type": "erlik_take", "base": t, "pos": b["pos"]})
		state.events.append({"type": "capture", "base": t, "from": PLAYER, "to": BOSS, "pos": b["pos"]})
	else:
		b["troops"] = maxf(0.0, b["troops"] - GameConfig.ERLIK_DRAIN)
		state.events.append({"type": "erlik_drain", "base": t, "pos": b["pos"]})
