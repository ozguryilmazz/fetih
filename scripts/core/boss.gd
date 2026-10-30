class_name BossDirector
extends RefCounted
## Boss bölümlerindeki özel yetenekler. Her simülasyon adımında update() çağrılır.
## Görseller için MatchState.events'e olay ekler. Oyuncu = 0, boss = 1.
##   tepegoz:      gaze_warn {base} -> 2 sn sonra gaze {base}
##   sahmeran:     poison_place {pos}
##   karakoncolos: darkness  (state.dark_until)
##   zumruduanka:  (kale "rebirth" bayrağı; MatchState çözer)
##   ejderha:      dragon_warn {base} -> 2 sn sonra dragon_fire {base}

const PLAYER := 0
const BOSS := 1
const WARN := 2.0

var kind := ""
var _timer := 0.0
var _warned := -1
var _dragon_times: Array = []
var _rng := RandomNumberGenerator.new()


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


func setup(state: MatchState) -> void:
	if kind == "zumruduanka":
		for b in state.bases:
			if b["owner"] == BOSS and b["type"] == "fortress":
				b["rebirth"] = true


func update(state: MatchState, dt: float) -> void:
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
