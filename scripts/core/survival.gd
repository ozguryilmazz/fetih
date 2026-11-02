class_name Survival
extends RefCounted
## Hayatta kalma modu: kurulum, rakibin zamanla güçlenmesi, dalgalar ve
## otomatik inşaat (rakip için; zorluk simülasyonunda oyuncu bot'u için de).
##
## Oyuncu = 0, rakip = 1. İkisi de kaleyle başlar.
## Yenilgi: oyuncunun kalesi düşer. Zafer: rakibin kalesi alınır.

const PLAYER := 0
const ENEMY := 1

var wave := 0
var next_wave := GameConfig.WAVE_FIRST
var _enemy_base_prod := 1.0
var _build_timer := 0.0
var _raid_timer := 15.0
var _rng := RandomNumberGenerator.new()
var rage := false
var _timers := {}          # yetenek -> sonraki kullanıma kalan sn
var _intro_done := {}      # yetenek -> ilk tanıtım gösterildi
var _patrol_rest := 3.0
var _meteor_at := -1.0
var _meteor_pos := Vector2.ZERO
var _betray_target := -1
var _betray_at := -1.0


## player: {name, color, icon, upgrades}. Dönen: {state, bots, survival}
static func create(player: Dictionary, seed_val: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var enemy_color := 0 if player["color"] != 0 else 1
	var players: Array = [
		MatchState.make_player(PLAYER, player["name"], player["color"], player["icon"], false, player["upgrades"]),
		MatchState.make_player(ENEMY, "Rakip", enemy_color, rng.randi() % GameConfig.ICON_NAMES.size(), true, {}),
	]
	var state := MatchState.create(rng.randi(), players, GameConfig.SURVIVAL_BASES, GameConfig.SURVIVAL_NEUTRAL_MIN, GameConfig.SURVIVAL_NEUTRAL_MAX)
	state.economy = true
	for b in state.bases:
		if b["owner"] == PLAYER:
			b["type"] = "keep"
			b["troops"] = GameConfig.KEEP_START
		elif b["owner"] == ENEMY:
			b["type"] = "citadel"
			b["troops"] = GameConfig.CITADEL_START
			b["shielded"] = true
	# İki taraf da kalesinin yanındaki 2 üsle başlar.
	for pid in [PLAYER, ENEMY]:
		var home: Dictionary = state.bases.filter(func(b): return b["owner"] == pid)[0]
		var hpos: Vector2 = home["pos"]
		var near: Array = state.bases.filter(func(b): return b["owner"] == GameConfig.NEUTRAL)
		near.sort_custom(func(a, b): return a["pos"].distance_to(hpos) < b["pos"].distance_to(hpos))
		for i in mini(2, near.size()):
			near[i]["owner"] = pid
			near[i]["troops"] = 20.0
	var sv := Survival.new()
	sv._rng.seed = rng.randi()
	sv._enemy_base_prod = players[ENEMY]["prod"]
	var bots: Array = [BotAI.new(ENEMY, GameConfig.SURVIVAL_ENEMY_SKILL, rng.randi())]
	return {"state": state, "bots": bots, "survival": sv}


## Oyuncunun kalesi ("keep") veya rakibin kalesi ("citadel"); düşmüşse boş.
static func fortress_of(state: MatchState, pid: int) -> Dictionary:
	var kind := "keep" if pid == PLAYER else "citadel"
	for b in state.bases:
		if b["type"] == kind and b["owner"] == pid:
			return b
	return {}


## "win", "lose" veya "" (sürüyor).
static func result(state: MatchState) -> String:
	if fortress_of(state, PLAYER).is_empty():
		return "lose"
	if fortress_of(state, ENEMY).is_empty():
		return "win"
	return ""


func seconds_to_next_wave(state: MatchState) -> float:
	return maxf(0.0, next_wave - state.time)


func wave_size(n: int) -> int:
	return int(GameConfig.WAVE_BASE + GameConfig.WAVE_GROWTH * (n - 1) + GameConfig.WAVE_ACCEL * (n - 1) * (n - 1))


## Her simülasyon adımında çağrılır: rakibi güçlendirir, dalga yollar, rakip için inşaat yapar.
func update(state: MatchState, dt: float) -> void:
	var minutes := state.time / 60.0
	state.players[ENEMY]["prod"] = _enemy_base_prod * (1.0 + GameConfig.ENEMY_RAMP_PER_MIN * minutes)

	if state.time >= next_wave:
		wave += 1
		next_wave += GameConfig.RAGE_WAVE_INTERVAL if rage else GameConfig.WAVE_INTERVAL
		_launch_wave(state)
		if wave == GameConfig.CITADEL_SHIELD_WAVES:
			var cit := fortress_of(state, ENEMY)
			if not cit.is_empty() and cit.get("shielded", false):
				cit["shielded"] = false
				state.events.append({"type": "shield_down", "base": cit["id"], "pos": cit["pos"]})

	_update_rage(state)
	_update_abilities(state, dt)

	_raid_timer -= dt
	if _raid_timer <= 0.0:
		_raid_timer = GameConfig.CITADEL_RAID_INTERVAL
		_raid(state)

	_build_timer -= dt
	if _build_timer <= 0.0:
		_build_timer = 2.0
		var cmd := auto_build(state, ENEMY)
		if not cmd.is_empty():
			state.apply_command(cmd)


## Düşman kalesi garnizonun üstünde yeterli asker biriktirince, yakındaki en
## zayıf oyuncu üssüne akın yapar (yapay zekâdan bağımsız, sürekli baskı).
func _raid(state: MatchState) -> void:
	var cit := fortress_of(state, ENEMY)
	if cit.is_empty() or MatchState.sendable(cit) < GameConfig.CITADEL_RAID_MIN:
		return
	var cp: Vector2 = cit["pos"]
	var targets: Array = state.bases.filter(func(b): return b["owner"] != ENEMY)
	if targets.is_empty():
		return
	targets.sort_custom(func(a, b):
		return state.base_strength(a) + a["pos"].distance_to(cp) * 0.08 < state.base_strength(b) + b["pos"].distance_to(cp) * 0.08)
	state.apply_command({"type": "send", "owner": ENEMY, "sources": [cit["id"]], "targets": [targets[0]["id"]]})


func _launch_wave(state: MatchState) -> void:
	var src := fortress_of(state, ENEMY)
	if src.is_empty():
		return
	var targets: Array = state.bases.filter(func(b): return b["owner"] == PLAYER)
	if targets.is_empty():
		return
	var target: Dictionary
	if wave % 3 == 0:
		# Her 3. dalga doğrudan kaleye gider.
		target = fortress_of(state, PLAYER)
	var sp: Vector2 = src["pos"]
	targets.sort_custom(func(a, b): return a["pos"].distance_to(sp) < b["pos"].distance_to(sp))
	if target.is_empty():
		target = targets[0]
	if unlocked("double") and targets.size() >= 2:
		# Çifte baskın: iki ayrı yönden, her biri dalganın %60'ı.
		_intro(state, "double")
		var other: Dictionary = targets[targets.size() / 2] if targets[targets.size() / 2]["id"] != target["id"] else targets[-1]
		state.spawn_wave(ENEMY, src["id"], target["id"], int(wave_size(wave) * 0.6))
		state.spawn_wave(ENEMY, src["id"], other["id"], int(wave_size(wave) * 0.6))
	else:
		state.spawn_wave(ENEMY, src["id"], target["id"], wave_size(wave))
	state.events.append({"type": "wave", "n": wave, "owner": ENEMY, "pos": src["pos"]})


## Basit inşaat kararı: önce maden (dakikaya göre artan sayıda), sonra kışla,
## sonra yükseltmeler (en düşük seviyeli bina önce). Cepheden uzak üsler seçilir.
static func auto_build(state: MatchState, pid: int) -> Dictionary:
	var gold: float = state.players[pid]["gold"]
	var mine: Array = state.bases.filter(func(b): return b["owner"] == pid)
	var enemies: Array = state.bases.filter(func(b): return b["owner"] != pid and b["owner"] != GameConfig.NEUTRAL)
	if enemies.is_empty():
		return {}
	var safety := func(b: Dictionary) -> float:
		var d := INF
		for e in enemies:
			d = minf(d, b["pos"].distance_to(e["pos"]))
		return d
	var normals := mine.filter(func(b): return b["type"] == "normal")
	normals.sort_custom(func(a, b): return safety.call(a) > safety.call(b))
	var mines := mine.filter(func(b): return b["type"] == "mine")
	var barracks := mine.filter(func(b): return b["type"] == "barracks")
	var want_mines := 1 + int(state.time / 300.0)
	var want_barracks := 1 + int(state.time / 420.0)

	var options: Array = []
	if not normals.is_empty() and mines.size() < want_mines:
		options.append({"base": normals[0]["id"], "kind": "mine"})
	if not normals.is_empty() and barracks.size() < want_barracks:
		options.append({"base": normals[mini(1, normals.size() - 1)]["id"], "kind": "barracks"})
	var upgradable := mines + barracks
	upgradable.sort_custom(func(a, b): return a.get("level", 1) < b.get("level", 1))
	for b in upgradable:
		options.append({"base": b["id"], "kind": "upgrade"})
	# İlk uygun seçenek; parası yetmiyorsa biriktirir (daha ucuz bir şeye harcamaz).
	if options.is_empty():
		return {}
	var o: Dictionary = options[0]
	var cost := state.build_cost(pid, o["base"], o["kind"])
	if cost > 0 and gold >= cost:
		return {"type": "build", "owner": pid, "base": o["base"], "kind": o["kind"]}
	return {}



# ---------------------------------------------------------------- yetenekler

func unlocked(key: String) -> bool:
	return wave >= int(GameConfig.ABILITIES[key][0])


## Bir yetenek ilk kez kullanılınca oyuna adı ve açıklaması gösterilsin.
func _intro(state: MatchState, key: String) -> void:
	if _intro_done.has(key):
		return
	_intro_done[key] = true
	var a: Array = GameConfig.ABILITIES[key]
	state.events.append({"type": "ability_intro", "key": key, "title": a[2], "desc": a[3]})


## Öfke modu: rakibin kalesinden başka üssü kalmayınca dalgalar sıklaşır, yetenekler hızlanır.
func _update_rage(state: MatchState) -> void:
	if rage:
		return
	var cit := fortress_of(state, ENEMY)
	if cit.is_empty():
		return
	for b in state.bases:
		if b["owner"] == ENEMY and b["id"] != cit["id"]:
			return
	rage = true
	next_wave = minf(next_wave, state.time + GameConfig.RAGE_WAVE_INTERVAL)
	state.events.append({"type": "rage", "pos": cit["pos"]})


func _update_abilities(state: MatchState, dt: float) -> void:
	var cit := fortress_of(state, ENEMY)
	if cit.is_empty():
		return
	var speed := 1.0
	if state.time / 60.0 >= GameConfig.ABILITY_LATE_MIN:
		speed /= GameConfig.ABILITY_LATE_FACTOR
	if rage:
		speed *= 2.0
	for key in ["night", "venom", "siege", "plunder", "storm", "meteor", "betrayal"]:
		if not unlocked(key):
			continue
		if not _timers.has(key):
			# İlk kullanım açıldıktan kısa süre sonra; yetenekler aynı anda gelmesin diye kaydırılır.
			_timers[key] = 4.0 + _timers.size() * 3.0
		_timers[key] -= dt * speed
		if _timers[key] <= 0.0 and _use(state, key, cit):
			_timers[key] = float(GameConfig.ABILITIES[key][1])
		elif _timers[key] <= 0.0:
			_timers[key] = 5.0  # şartlar uygun değil; az sonra tekrar dene
	if unlocked("patrol"):
		_update_patrol(state, dt * speed, cit)
	_update_meteor(state)
	_update_betrayal(state)


## Yeteneği kullanır; uygun hedef yoksa false.
func _use(state: MatchState, key: String, cit: Dictionary) -> bool:
	var mine: Array = state.bases.filter(func(b): return b["owner"] == PLAYER)
	if mine.is_empty():
		return false
	match key:
		"night":
			state.dark_until = state.time + GameConfig.NIGHT_DURATION
			state.events.append({"type": "darkness", "by": "survival"})
		"venom":
			var t: Dictionary = mine[_rng.randi() % mine.size()]
			state.spawn_venom(ENEMY, cit["id"], t["id"])
			state.events.append({"type": "venom_sent", "base": t["id"], "pos": t["pos"]})
		"siege":
			var cand := mine.filter(func(b): return not b.get("besieged", false) and b["troops"] >= 10.0)
			if cand.is_empty():
				return false
			cand.sort_custom(func(a, b): return a["troops"] > b["troops"])
			var n := GameConfig.SIEGE_START + int(state.time / 60.0) * 2
			state.spawn_siege(ENEMY, cit["id"], cand[0]["id"], n)
			state.events.append({"type": "siege_sent", "base": cand[0]["id"], "pos": cand[0]["pos"]})
		"plunder":
			var mines := mine.filter(func(b): return b["type"] == "mine")
			if mines.is_empty():
				return false
			var m: Dictionary = mines[_rng.randi() % mines.size()]
			state.spawn_wave(ENEMY, cit["id"], m["id"], int(state.base_strength(m) * 1.2) + 12)
			state.events.append({"type": "plunder_sent", "base": m["id"], "pos": m["pos"]})
		"storm":
			state.players[PLAYER]["slow_until"] = state.time + GameConfig.STORM_DURATION
			state.events.append({"type": "storm", "until": state.time + GameConfig.STORM_DURATION})
		"meteor":
			if _meteor_at >= 0.0:
				return false
			_meteor_pos = _meteor_target(state, mine)
			_meteor_at = state.time + GameConfig.METEOR_WARN
			state.events.append({"type": "meteor_warn", "pos": _meteor_pos, "r": GameConfig.METEOR_RADIUS, "until": _meteor_at})
		"betrayal":
			if _betray_target >= 0:
				return false
			var small := mine.filter(func(b): return b["type"] != "keep" and b["troops"] < GameConfig.BETRAYAL_BELOW)
			if small.is_empty():
				return false
			small.sort_custom(func(a, b): return a["troops"] < b["troops"])
			_betray_target = small[0]["id"]
			_betray_at = state.time + 2.0
			state.events.append({"type": "betray_warn", "base": _betray_target, "pos": small[0]["pos"]})
	_intro(state, key)
	return true


## Ateş yağmuru hedefi: oyuncunun en kalabalık kolunun önü; kol yoksa en kalabalık üssü.
func _meteor_target(state: MatchState, mine: Array) -> Vector2:
	var best := {}
	for g in state.groups:
		if g["owner"] == PLAYER and (best.is_empty() or MatchState.group_count(g) > MatchState.group_count(best)):
			best = g
	if not best.is_empty() and MatchState.group_count(best) >= 8:
		# Kol yürümeye devam edeceği için biraz ilerisine nişan alır.
		var ahead := minf(state.front_along(best) + state.troop_speed(PLAYER) * 1.0, best["s1"])
		return state.path_point(best, ahead)
	mine.sort_custom(func(a, b): return a["troops"] > b["troops"])
	return mine[0]["pos"]


func _update_meteor(state: MatchState) -> void:
	if _meteor_at >= 0.0 and state.time >= _meteor_at:
		_meteor_at = -1.0
		state.meteor_strike(ENEMY, _meteor_pos, GameConfig.METEOR_RADIUS)


func _update_betrayal(state: MatchState) -> void:
	if _betray_target < 0 or state.time < _betray_at:
		return
	var b: Dictionary = state.bases[_betray_target]
	_betray_target = -1
	if b["owner"] != PLAYER or b["troops"] >= GameConfig.BETRAYAL_BELOW * 1.5:
		return  # bu arada takviye geldi: ihanet bastırıldı
	b["owner"] = ENEMY
	b.erase("besieged")
	b.erase("venom_until")
	state.events.append({"type": "betrayal", "base": b["id"], "pos": b["pos"]})
	state.events.append({"type": "capture", "base": b["id"], "from": PLAYER, "to": ENEMY, "pos": b["pos"]})


## Devriye: kale yakınında bekler, sonra oyuncunun yollarında dolaşıp geri döner.
func _update_patrol(state: MatchState, dt: float, cit: Dictionary) -> void:
	for g in state.groups:
		if g.get("patrol", false) and g["owner"] == ENEMY:
			return  # devriye hâlâ dışarıda
	_patrol_rest -= dt
	if _patrol_rest > 0.0:
		return
	_patrol_rest = GameConfig.PATROL_REST
	var mine: Array = state.bases.filter(func(b): return b["owner"] == PLAYER)
	if mine.is_empty():
		return
	# Ara noktalar: oyuncu üsleri arasındaki ve oyuncu üsleriyle kale arasındaki yolların ortaları.
	var pts: Array = []
	var cp: Vector2 = cit["pos"]
	var speed := state.troop_speed(ENEMY)
	var budget := speed * GameConfig.PATROL_TIME
	var cur := cp
	for i in 6:
		var a: Dictionary = mine[_rng.randi() % mine.size()]
		var other: Vector2 = cp
		if mine.size() > 1 and _rng.randf() < 0.6:
			other = mine[_rng.randi() % mine.size()]["pos"]
		var wp: Vector2 = a["pos"].lerp(other, _rng.randf_range(0.35, 0.65))
		var back := wp.distance_to(cp)
		if cur.distance_to(wp) + back > budget:
			break
		budget -= cur.distance_to(wp)
		pts.append(wp)
		cur = wp
	if pts.is_empty():
		pts.append(cp.lerp(mine[0]["pos"], 0.5))
	var n := GameConfig.PATROL_START + int(state.time / 60.0) * GameConfig.PATROL_PER_MIN
	state.spawn_patrol(ENEMY, cit["id"], pts, n)
	state.events.append({"type": "patrol", "pos": cp})
	_intro(state, "patrol")
