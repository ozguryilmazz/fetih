class_name LevelSetup
extends RefCounted
## Bir solo bölümünü kurar: oyuncular, harita, bot'lar, boss.
## Hem oyun ekranı hem zorluk simülasyonu bunu kullanır, böylece
## test edilen zorluk ile oynanan zorluk birebir aynıdır.

const BOSS_NAMES := ["Demir Pençe", "Kızıl Hükümdar", "Gölge Komutan", "Taş Dev", "Fırtına Kralı"]


## player: {name, color, icon, upgrades}. Dönen: {state, bots, params}
static func create(level: int, player: Dictionary, seed_val: int) -> Dictionary:
	var params := GameConfig.level_params(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var players: Array = [MatchState.make_player(
		0, player["name"], player["color"], player["icon"], false, player["upgrades"])]

	var used_colors: Array = [player["color"]]
	var lvl: int = params["bot_upgrade"]
	var bot_upgrades := {"production": lvl, "speed": lvl, "start": lvl, "road": lvl}
	for i in params["bots"]:
		var ci := 0
		while used_colors.has(ci):
			ci += 1
		used_colors.append(ci)
		var bname := "Bot %d" % (i + 1)
		if params["boss"]:
			@warning_ignore("integer_division")
			bname = BOSS_NAMES[(level / 10 - 1) % BOSS_NAMES.size()]
		var bp := MatchState.make_player(i + 1, bname, ci, rng.randi() % GameConfig.ICON_NAMES.size(), true, bot_upgrades)
		bp["prod"] *= params["bot_prod_bonus"]
		players.append(bp)

	var state := MatchState.create(rng.randi(), players, params["bases"], params["neutral_min"], params["neutral_max"])

	if params["boss"]:
		_make_boss_territory(state, 1)

	var bots: Array = []
	for i in range(1, players.size()):
		bots.append(BotAI.new(i, params["skill"], rng.randi()))
	return {"state": state, "bots": bots, "params": params}


## Boss'un başlangıç üssü kaleye dönüşür (büyük, hızlı üretir, dayanıklı).
static func _make_boss_territory(state: MatchState, boss_id: int) -> void:
	var hq: Dictionary = state.bases.filter(func(b): return b["owner"] == boss_id)[0]
	hq["type"] = "fortress"
	hq["troops"] = 30.0
