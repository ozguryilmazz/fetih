extends SceneTree
## Zorluk raporu (CI'da çalışmaz, ayar yaparken elle çalıştırılır):
##   godot --headless --path . -s tests/difficulty_report.gd -- [oyuncu_becerisi] [maç_sayısı]
## Sabit beceride bir "oyuncu bot'u", o bölüme gelmiş bir oyuncunun tahmini
## güçlendirmeleriyle her bölümü oynar. Kazanma oranı ve süreler yazdırılır.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var player_skill := float(args[0]) if args.size() > 0 else 0.7
	var matches := int(args[1]) if args.size() > 1 else 8
	print("oyuncu becerisi %.2f, bölüm başına %d maç" % [player_skill, matches])
	print("bölüm  bant        bot   güçl  kazanma  ort.süre  hedef  hedefte%  kayıpsız%  ort.kayıp")
	var t0 := Time.get_ticks_msec()
	var only_boss := args.size() > 2 and args[2] == "boss"
	for level in range(1, GameConfig.MAX_LEVEL + 1):
		if only_boss and not GameConfig.is_boss(level):
			continue
		var wins := 0
		var times: Array = []
		var on_par := 0
		var no_loss := 0
		var lost_sum := 0
		var params := GameConfig.level_params(level)
		var ups := expected_upgrades(level)
		for m in matches:
			var r := play(level, player_skill, ups, 7919 * level + m)
			if r["won"]:
				wins += 1
				times.append(r["time"])
				if r["time"] <= params["par"]:
					on_par += 1
				if r["lost"] == 0:
					no_loss += 1
				lost_sum += r["lost"]
		var avg := 0.0
		for t in times:
			avg += t
		avg = avg / maxf(times.size(), 1)
		print("%5d  %-10s  %.2f  %4d  %6d%%  %8.0f  %5d  %7d%%  %8d%%  %8.1f" % [
			level, GameConfig.band_name(level), params["skill"], ups["production"],
			100 * wins / matches, avg, params["par"],
			100 * on_par / maxi(wins, 1), 100 * no_loss / maxi(wins, 1), lost_sum / maxf(wins, 1)])
	print("süre: %d sn" % ((Time.get_ticks_msec() - t0) / 1000))
	quit()


## Bölüm n'ye gelen oyuncunun tahmini güçlendirmeleri: bölüm başına ~80 altın
## + günlük ödül, en ucuz güçlendirmeden alınarak harcanmış.
static func expected_upgrades(level: int) -> Dictionary:
	var gold := (level - 1) * 80 + (level - 1) * 50
	var ups := {"production": 0, "speed": 0, "start": 0, "road": 0}
	while true:
		var best := ""
		var best_cost := 1 << 30
		for k in GameConfig.UPGRADE_ORDER:
			var c := GameConfig.upgrade_cost(k, ups[k])
			if ups[k] < GameConfig.UPGRADES[k]["max"] and c < best_cost:
				best = k
				best_cost = c
		if best == "" or best_cost > gold:
			break
		gold -= best_cost
		ups[best] += 1
	return ups


static func play(level: int, player_skill: float, ups: Dictionary, seed_val: int) -> Dictionary:
	var setup := LevelSetup.create(level, {"name": "P", "color": 1, "icon": 0, "upgrades": ups}, seed_val)
	var s: MatchState = setup["state"]
	var bots: Array = setup["bots"]
	bots.append(BotAI.new(0, player_skill, seed_val + 1))
	var lost := 0
	var boss: BossDirector = setup["boss"]
	while s.time < 600.0:
		if boss:
			boss.update(s, GameConfig.SIM_DT)
		for b in bots:
			for c in b.update(s, GameConfig.SIM_DT):
				s.apply_command(c)
		s.step(GameConfig.SIM_DT)
		for e in s.events:
			if e["type"] == "capture" and e["from"] == 0:
				lost += 1
		s.events.clear()
		var alive := s.alive_players()
		if not alive.has(0):
			return {"won": false, "time": s.time, "lost": lost}
		if alive.size() == 1:
			return {"won": true, "time": s.time, "lost": lost}
	return {"won": false, "time": s.time, "lost": lost}
