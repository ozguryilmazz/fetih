extends SceneTree
## Hayatta kalma dengesi (CI'da çalışmaz):
##   godot --headless --path . -s tests/survival_report.gd -- [oyuncu_becerisi] [maç_sayısı] [güçlendirme]
## Oyuncu bot'u da kışla/maden kurar. Ne kadar dayandığı ve kaç dalga gördüğü yazdırılır.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var skill := float(args[0]) if args.size() > 0 else 0.85
	var matches := int(args[1]) if args.size() > 1 else 10
	var up := int(args[2]) if args.size() > 2 else 2
	var ups := {"production": up, "speed": up, "start": up, "road": up}
	var times: Array = []
	var wins := 0
	var builds := 0
	for m in matches:
		var r := play(skill, ups, 1000 + m)
		times.append(r["time"])
		builds += r["builds"]
		if r["result"] == "win":
			wins += 1
		print("  maç %2d: %-5s %5.0f sn, dalga %d, oyuncu inşaatı %d, rakip inşaatı %d" % [
			m + 1, r["result"], r["time"], r["wave"], r["builds"], r["enemy_builds"]])
	times.sort()
	print("beceri %.2f, güçlendirme %d: ortanca %.1f dk, en kısa %.1f, en uzun %.1f, zafer %d/%d" % [
		skill, up, times[times.size() / 2] / 60.0, times[0] / 60.0, times[-1] / 60.0, wins, matches])
	quit()


static func play(skill: float, ups: Dictionary, seed_val: int) -> Dictionary:
	var setup := Survival.create({"name": "P", "color": 1, "icon": 0, "upgrades": ups}, seed_val)
	var s: MatchState = setup["state"]
	var sv: Survival = setup["survival"]
	var bots: Array = setup["bots"]
	bots.append(BotAI.new(0, skill, seed_val + 7))
	var build_timer := 0.0
	var siege_timer := 10.0
	var builds := 0
	var enemy_builds := 0
	while s.time < 3600.0:
		sv.update(s, GameConfig.SIM_DT)
		build_timer -= GameConfig.SIM_DT
		if build_timer <= 0.0:
			build_timer = 2.0
			var c := Survival.auto_build(s, 0)
			if not c.is_empty():
				s.apply_command(c)
		for b in bots:
			for c in b.update(s, GameConfig.SIM_DT):
				s.apply_command(c)
		siege_timer -= GameConfig.SIM_DT
		if siege_timer <= 0.0:
			siege_timer = 10.0
			var cmd := siege(s)
			if not cmd.is_empty():
				s.apply_command(cmd)
		s.step(GameConfig.SIM_DT)
		for e in s.events:
			if e["type"] == "build":
				if e["owner"] == 0:
					builds += 1
				else:
					enemy_builds += 1
		s.events.clear()
		var res := Survival.result(s)
		if res != "":
			return {"result": res, "time": s.time, "wave": sv.wave, "builds": builds, "enemy_builds": enemy_builds}
	return {"result": "süre", "time": s.time, "wave": sv.wave, "builds": builds, "enemy_builds": enemy_builds}


## İnsan oyuncu taklidi: gönderilebilir ordusu düşman kalesinin 1,1 katını geçince saldırır.
static func siege(s: MatchState) -> Dictionary:
	var cit := Survival.fortress_of(s, 1)
	if cit.is_empty():
		return {}
	var srcs: Array = []
	var sum := 0.0
	for b in s.bases:
		if b["owner"] == 0 and MatchState.can_send_from(b) and b["type"] != "keep":
			srcs.append(b["id"])
			sum += floorf(b["troops"])
	if sum > s.base_strength(cit) * 1.1:
		return {"type": "send", "owner": 0, "sources": srcs, "targets": [cit["id"]]}
	return {}
