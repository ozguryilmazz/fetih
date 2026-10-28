class_name BotAI
extends RefCounted
## Basit yapay zeka. Belirli aralıklarla haritaya bakar, alabileceği en ucuz
## hedefi bulur ve en yakın üslerinden yeterince askeri oraya yollar.
## difficulty 0..1: düşünme sıklığını, risk payını ve hata oranını belirler.

var pid: int
var think_interval: float
var safety_margin: float
var mistake_chance: float
var _timer: float
var _rng := RandomNumberGenerator.new()


func _init(player_id: int, difficulty: float, seed_val: int) -> void:
	pid = player_id
	think_interval = lerpf(2.8, 0.9, difficulty)
	safety_margin = lerpf(1.5, 1.1, difficulty)
	mistake_chance = lerpf(0.35, 0.03, difficulty)
	_rng.seed = seed_val
	_timer = _rng.randf_range(1.0, think_interval + 1.0)


## Her simülasyon adımında çağrılır; uygulanacak komutları döndürür.
func update(state: MatchState, dt: float) -> Array:
	_timer -= dt
	if _timer > 0.0:
		return []
	_timer = think_interval * _rng.randf_range(0.8, 1.2)
	if _rng.randf() < mistake_chance:
		return []
	var cmd := _decide(state)
	return [] if cmd.is_empty() else [cmd]


func _decide(state: MatchState) -> Dictionary:
	var mine: Array = state.bases.filter(func(b): return b["owner"] == pid)
	if mine.is_empty():
		return {}
	var speed := state.troop_speed(pid)
	var best := {}
	var best_score := INF

	for t in state.bases:
		if t["owner"] == pid:
			continue
		var tpos: Vector2 = t["pos"]
		var by_dist := mine.duplicate()
		by_dist.sort_custom(func(a, b): return a["pos"].distance_to(tpos) < b["pos"].distance_to(tpos))

		var srcs: Array = []
		var sum := 0.0
		var far := 0.0
		var need := INF
		for s in by_dist:
			var avail := floorf(s["troops"])
			if avail < 4.0:
				continue
			srcs.append(s["id"])
			sum += avail
			far = maxf(far, s["pos"].distance_to(tpos))
			need = state.troops_needed(t, far / speed, pid) * safety_margin + 2.0
			if sum >= need:
				break
		if srcs.is_empty() or sum < need:
			continue

		# Ucuz ve yakın hedefleri tercih et; rakip üssü almak tarafsızdan biraz daha değerli.
		var score := need + far * 0.06
		if t["owner"] != GameConfig.NEUTRAL:
			score -= 6.0
		if score < best_score:
			best_score = score
			best = {"type": "send", "owner": pid, "sources": srcs, "targets": [t["id"]]}
	return best
