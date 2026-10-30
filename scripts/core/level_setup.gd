class_name LevelSetup
extends RefCounted
## Bir solo bölümünü kurar: oyuncular, harita, bot'lar, boss.
## Hem oyun ekranı hem zorluk simülasyonu bunu kullanır, böylece
## test edilen zorluk ile oynanan zorluk birebir aynıdır.

## player: {name, color, icon, upgrades}. Dönen: {state, bots, params, boss}
## params["boss_kind"]: tepegoz/sahmeran/... ; params["weather"]: "", "night", "rain"
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
			bname = GameConfig.BOSS_INFO[GameConfig.boss_kind(level)]["name"]
		var bp := MatchState.make_player(i + 1, bname, ci, rng.randi() % GameConfig.ICON_NAMES.size(), true, bot_upgrades)
		bp["prod"] *= params["bot_prod_bonus"]
		players.append(bp)

	var state := MatchState.create(rng.randi(), players, params["bases"], params["neutral_min"], params["neutral_max"])

	var boss: BossDirector = null
	params["boss_kind"] = GameConfig.boss_kind(level)
	if params["boss"]:
		_make_boss_territory(state, 1)
		boss = BossDirector.new(params["boss_kind"], hash(seed_val) ^ 0x5eed)  # bot tohumlarını kaydırmasın
		boss.setup(state)

	# Her 5. bölüm: her oynayışta rastgele gece veya yağmur.
	params["weather"] = ""
	if GameConfig.is_weather_level(level):
		var wr := RandomNumberGenerator.new()
		wr.seed = hash(seed_val) ^ 0x7a1
		params["weather"] = "night" if wr.randf() < 0.5 else "rain"
		if params["weather"] == "rain":
			state.speed_mult = GameConfig.RAIN_SPEED
			params["par"] = int(ceil(params["par"] * 1.3 / 10.0) * 10)
		else:
			params["par"] = int(ceil(params["par"] * 1.15 / 10.0) * 10)

	var bots: Array = []
	for i in range(1, players.size()):
		bots.append(BotAI.new(i, params["skill"], rng.randi()))
	return {"state": state, "bots": bots, "params": params, "boss": boss}


## Boss'un başlangıç üssü kaleye dönüşür (büyük, hızlı üretir, dayanıklı).
static func _make_boss_territory(state: MatchState, boss_id: int) -> void:
	var hq: Dictionary = state.bases.filter(func(b): return b["owner"] == boss_id)[0]
	hq["type"] = "fortress"
	hq["troops"] = 30.0
