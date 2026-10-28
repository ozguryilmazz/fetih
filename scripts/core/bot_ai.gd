class_name BotAI
extends RefCounted
## Yapay zeka. Belirli aralıklarla haritaya bakar ve sırasıyla:
##  1. SAVUNMA: düşecek bir üssü varsa, yetişebilecek üslerden takviye yollar.
##  2. SALDIRI: alabileceği en kârlı hedefe yeterli askeri yollar. Kendi üslerini
##     güçlü düşmanların yanında boş bırakmaktan kaçınır, yoldaki askerleri hesaba katar.
##  3. TOPLAMA: arkada dolup taşan üslerin askerini cephedeki üsse taşır.
##
## skill 0..1: düşünme hızı, hata oranı, savunma isteği, risk hesabı ve
## karar gürültüsünü belirler. 0.1 = acemi, 1.0 = çok güçlü.

var pid: int
var skill: float
var think_interval: float
var safety_margin: float
var mistake_chance: float
var defend_chance: float
var noise: float
var risk_weight: float
var enemy_bonus: float
var consolidate: bool
var _timer: float
var _rng := RandomNumberGenerator.new()


func _init(player_id: int, skill_val: float, seed_val: int) -> void:
	pid = player_id
	skill = clampf(skill_val, 0.0, 1.0)
	think_interval = lerpf(2.6, 0.55, skill)
	safety_margin = lerpf(1.5, 1.08, skill)
	mistake_chance = lerpf(0.35, 0.0, skill)
	defend_chance = clampf((skill - 0.15) / 0.6, 0.0, 1.0)
	noise = lerpf(0.5, 0.05, skill)
	risk_weight = lerpf(0.0, 1.0, skill)
	enemy_bonus = lerpf(3.0, 12.0, skill)
	consolidate = skill >= 0.45
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
	var mine: Array = state.bases.filter(func(b): return b["owner"] == pid)
	if mine.is_empty():
		return []

	var threats := _threats(state, mine)
	if not threats.is_empty() and _rng.randf() < defend_chance:
		var d := _defend(state, mine, threats)
		if not d.is_empty():
			return [d]
	var a := _attack(state, mine, threats)
	if not a.is_empty():
		return [a]
	if consolidate:
		var c := _consolidate(state, mine, threats)
		if not c.is_empty():
			return [c]
	return []


# ---------------------------------------------------------------- savunma

## Düşmesi beklenen üslerim: {base id: {need, eta}}
func _threats(state: MatchState, mine: Array) -> Dictionary:
	var out := {}
	for b in mine:
		var enemy := 0.0
		var friendly := 0.0
		var eta := INF
		for g in state.groups:
			if g["to"] != b["id"]:
				continue
			var c := MatchState.group_count(g)
			if g["owner"] == pid:
				friendly += c
			else:
				enemy += c
				eta = minf(eta, maxf(0.0, g["s1"] - state.front_along(g)) / state.troop_speed(g["owner"]))
		if enemy <= 0.0:
			continue
		var bt := state.base_type(b)
		var grown := minf(bt["capacity"], b["troops"] + b.get("elite", 0.0) * GameConfig.ELITE_POWER + state.base_growth(b) * eta)
		var projected := grown + friendly - enemy / float(bt["defense"])
		if projected < 1.0:
			out[b["id"]] = {"need": (1.0 - projected) * float(bt["defense"]), "eta": eta}
	return out


func _defend(state: MatchState, mine: Array, threats: Dictionary) -> Dictionary:
	var speed := state.troop_speed(pid)
	var ids := threats.keys()
	ids.sort_custom(func(a, b): return threats[a]["eta"] < threats[b]["eta"])
	for tid in ids:
		var target: Dictionary = state.bases[tid]
		var need: float = threats[tid]["need"] * safety_margin + 2.0
		var eta: float = threats[tid]["eta"]
		var helpers := mine.filter(func(h): return h["id"] != tid and not threats.has(h["id"]) and h["troops"] >= 3.0 and MatchState.can_send_from(h))
		helpers.sort_custom(func(a, b): return a["pos"].distance_to(target["pos"]) < b["pos"].distance_to(target["pos"]))
		var srcs: Array = []
		var sum := 0.0
		for h in helpers:
			if h["pos"].distance_to(target["pos"]) / speed > eta + 1.5:
				break
			srcs.append(h["id"])
			sum += MatchState.sendable(h)
			if sum >= need:
				return {"type": "send", "owner": pid, "sources": srcs, "targets": [tid]}
	return {}


# ---------------------------------------------------------------- saldırı

## Her olası hedef için net değer hesaplanır:
##   kazanç  = üssün değeri (+ rakipten alınıyorsa ek değer)
##   maliyet = harcanacak asker + yol süresi
##   risk    = boşalan kaynak üslerin ve alınan üssün hemen geri kaybedilme ihtimali
## Usta bot sadece değeri yeterince yüksek hamleleri yapar (sabır); acemi bot
## gördüğü her fırsata atlar, riski hesaba katmaz.
func _attack(state: MatchState, mine: Array, threats: Dictionary) -> Dictionary:
	var speed := state.troop_speed(pid)
	var best := {}
	var best_score := lerpf(-60.0, 4.0, skill)

	for t in state.bases:
		if t["owner"] == pid:
			continue
		var tpos: Vector2 = t["pos"]
		var by_dist := mine.duplicate()
		by_dist.sort_custom(func(a, b): return a["pos"].distance_to(tpos) < b["pos"].distance_to(tpos))
		var t_threat := _threat_near(state, tpos, -1)
		var hold := t_threat * skill * 0.7

		var srcs: Array = []
		var sum := 0.0
		var far := 0.0
		var raw := 0.0
		var need := INF
		for s in by_dist:
			var avail := float(MatchState.sendable(s))
			if avail < 4.0 or not MatchState.can_send_from(s):
				continue
			if skill > 0.5 and threats.has(s["id"]):
				continue
			srcs.append(s["id"])
			sum += avail
			far = maxf(far, s["pos"].distance_to(tpos))
			raw = state.troops_needed(t, far / speed, pid)
			need = raw * safety_margin + 2.0 + hold
			if sum >= need:
				break
		if srcs.is_empty() or raw <= 0.5:
			continue
		var min_need := raw * safety_margin + 2.0
		if sum < min_need:
			continue

		var value := 30.0 + (float(state.base_type(t)["capacity"]) - 60.0) * 0.3
		if t["owner"] != GameConfig.NEUTRAL:
			value += enemy_bonus
		var score := value - raw - far * 0.03
		# Alınan üs elde tutulabilecek mi?
		var leftover := sum - raw
		if t_threat > leftover:
			score -= value * 0.6 * skill
		# Boşalan kaynak üsler hemen kaybedilir mi?
		for sid in srcs:
			var st := _threat_near(state, state.bases[sid]["pos"], sid)
			if st > 3.0:
				score -= minf(st / 15.0, 1.0) * 25.0 * risk_weight
		score += _rng.randf_range(-noise, noise) * 20.0
		if score > best_score:
			best_score = score
			best = {"type": "send", "owner": pid, "sources": srcs, "targets": [t["id"]]}
	return best


## Bir noktaya yakın rakip üslerin (mesafeyle azalan) en büyük asker gücü.
func _threat_near(state: MatchState, p: Vector2, except_id: int) -> float:
	var m := 0.0
	for b in state.bases:
		if b["owner"] == pid or b["owner"] == GameConfig.NEUTRAL or b["id"] == except_id:
			continue
		var d: float = p.distance_to(b["pos"])
		if d < 450.0:
			m = maxf(m, b["troops"] * (1.0 - d / 600.0))
	return m


# ---------------------------------------------------------------- toplama

## Arkada dolmuş (üretimi boşa giden) üsten, düşmana en yakın üsse asker taşır.
func _consolidate(state: MatchState, mine: Array, threats: Dictionary) -> Dictionary:
	if mine.size() < 2:
		return {}
	var enemies: Array = state.bases.filter(func(b): return b["owner"] != pid and b["owner"] != GameConfig.NEUTRAL)
	if enemies.is_empty():
		return {}
	var front := {}
	var front_d := INF
	var dists := {}
	for b in mine:
		var d := INF
		for e in enemies:
			d = minf(d, b["pos"].distance_to(e["pos"]))
		dists[b["id"]] = d
		if d < front_d:
			front_d = d
			front = b
	var donor := {}
	var donor_d := front_d + 150.0
	for b in mine:
		if b["id"] == front["id"] or threats.has(b["id"]) or not MatchState.can_send_from(b):
			continue
		if b["troops"] < float(state.base_type(b)["capacity"]) * 0.8:
			continue
		if dists[b["id"]] > donor_d:
			donor_d = dists[b["id"]]
			donor = b
	if donor.is_empty():
		return {}
	return {"type": "send", "owner": pid, "sources": [donor["id"]], "targets": [front["id"]]}
