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
		next_wave += GameConfig.WAVE_INTERVAL
		_launch_wave(state)
		if wave == GameConfig.CITADEL_SHIELD_WAVES:
			var cit := fortress_of(state, ENEMY)
			if not cit.is_empty():
				cit["shielded"] = false
				state.events.append({"type": "shield_down", "base": cit["id"], "pos": cit["pos"]})

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
	if target.is_empty():
		var sp: Vector2 = src["pos"]
		targets.sort_custom(func(a, b): return a["pos"].distance_to(sp) < b["pos"].distance_to(sp))
		target = targets[0]
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
