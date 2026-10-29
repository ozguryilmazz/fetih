extends SceneTree
## Ekransız test: godot --headless --path . -s tests/sim_test.gd
## Kuralları (eşit bölüştürme, ele geçirme, yol çarpışması, Yol Savaşı) doğrular
## ve bot'ları birbirine karşı oynatır.

var _failed := false


func _initialize() -> void:
	_test_equal_split()
	_test_capture_and_network()
	_test_head_on_clash()
	_test_crossing_clash()
	_test_levels_and_rewards()
	_test_survival_rules()
	_test_quest_counting()
	_test_bot_matches()
	print("SONUC: ", "HATA" if _failed else "TAMAM")
	quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  HATA ") + msg)
	if not cond:
		_failed = true


func _player(id: int, road := 0) -> Dictionary:
	return MatchState.make_player(id, "P%d" % id, id, 0, true, {"road": road})


func _base(id: int, pos: Vector2, owner: int, troops: float) -> Dictionary:
	return {"id": id, "pos": pos, "owner": owner, "troops": troops, "type": "normal"}


func _counts(s: MatchState) -> Array:
	return s.groups.map(func(g): return MatchState.group_count(g))


## Üretimi kapatır: sonuçlar tam sayı ve kesin olsun diye.
func _no_production(s: MatchState) -> void:
	for p in s.players:
		p["prod"] = 0.0


func _run(s: MatchState, seconds: float) -> void:
	var t := 0.0
	while t < seconds and not s.groups.is_empty():
		s.step(GameConfig.SIM_DT)
		t += GameConfig.SIM_DT


func _test_equal_split() -> void:
	print("Eşit bölüştürme")
	var s := MatchState.new()
	s.players = [_player(0), _player(1)]
	s.bases = [
		_base(0, Vector2(100, 100), 0, 100.0),
		_base(1, Vector2(400, 100), 1, 10.0),
		_base(2, Vector2(100, 600), 1, 10.0),
		_base(3, Vector2(400, 600), -1, 5.0),
		_base(4, Vector2(250, 300), 0, 7.0),
	]
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [1, 2]})
	_check(_counts(s) == [50, 50], "100 asker 2 hedefe -> 50+50 (bulunan: %s)" % [_counts(s)])
	_check(is_zero_approx(s.bases[0]["troops"]), "kaynak üs boşaldı")

	s.groups.clear()
	s.apply_command({"type": "send", "owner": 0, "sources": [4], "targets": [1, 2, 3]})
	_check(_counts(s) == [3, 2, 2], "7 asker 3 hedefe -> 3+2+2 (bulunan: %s)" % [_counts(s)])

	s.groups.clear()
	s.bases[0]["troops"] = 30.0
	s.bases[4]["troops"] = 20.0
	s.apply_command({"type": "send", "owner": 0, "sources": [0, 4], "targets": [3]})
	_check(_counts(s) == [30, 20], "2 kaynak 1 hedefe -> 30 ve 20 (bulunan: %s)" % [_counts(s)])

	s.groups.clear()
	s.bases[1]["troops"] = 50.0
	s.apply_command({"type": "send", "owner": 0, "sources": [1], "targets": [3]})
	_check(s.groups.is_empty(), "rakibin üssünden gönderim reddedildi")


func _test_capture_and_network() -> void:
	print("Ele geçirme ve ağ paketi")
	var s := MatchState.new()
	s.players = [_player(0), _player(1)]
	s.bases = [_base(0, Vector2(100, 300), 0, 25.0), _base(1, Vector2(500, 300), 1, 10.0)]
	_no_production(s)
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [1]})
	for i in 30:
		s.step(GameConfig.SIM_DT)
	var copy := MatchState.from_setup(s.setup_dict())
	copy.apply_snapshot(s.snapshot())
	_check(copy.groups.size() == 1 and MatchState.group_count(copy.groups[0]) == 25
		and is_equal_approx(copy.groups[0]["d"], s.groups[0]["d"]), "yoldaki kol paketle aynen kopyalandı")

	var captured := false
	_run(s, 20.0)
	for e in s.events:
		captured = captured or e["type"] == "capture"
	_check(s.bases[1]["owner"] == 0, "üs ele geçirildi")
	_check(is_equal_approx(s.bases[1]["troops"], 15.0), "25 - 10 = 15 asker kaldı (bulunan: %.1f)" % s.bases[1]["troops"])
	_check(captured, "ele geçirme olayı üretildi (efekt için)")


## Kafa kafaya çarpışma: X ve Y üsleri birbirine 15'er asker yollar.
## Yol Savaşı seviyesi L olan taraftan L asker sağ kalıp karşı üsse ulaşır.
func _head_on(road_level: int) -> MatchState:
	var s := MatchState.new()
	s.players = [_player(0, road_level), _player(1, 0)]
	s.bases = [_base(0, Vector2(100, 400), 0, 15.0), _base(1, Vector2(600, 400), 1, 15.0)]
	_no_production(s)
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [1]})
	s.apply_command({"type": "send", "owner": 1, "sources": [1], "targets": [0]})
	_run(s, 20.0)
	return s


func _test_head_on_clash() -> void:
	print("Yol çarpışması (kafa kafaya)")
	var s := _head_on(0)
	var clashes := s.events.filter(func(e): return e["type"] == "clash").size()
	_check(s.groups.is_empty() and s.bases[0]["owner"] == 0 and s.bases[1]["owner"] == 1
		and is_zero_approx(s.bases[0]["troops"]) and is_zero_approx(s.bases[1]["troops"]),
		"15'e 15 -> ikisi de yolda yok oldu, kimse üsse ulaşmadı")
	_check(clashes == 15, "15 çarpışma adımı (bulunan: %d)" % clashes)

	for lvl in [1, 3]:
		s = _head_on(lvl)
		_check(s.bases[1]["owner"] == 0 and is_equal_approx(s.bases[1]["troops"], lvl),
			"Yol Savaşı %d: %d asker sağ kalıp rakip üssü aldı (üs: sahip %d, %.0f asker)" % [lvl, lvl, s.bases[1]["owner"], s.bases[1]["troops"]])
		_check(is_zero_approx(s.bases[0]["troops"]) and s.bases[0]["owner"] == 0, "Yol Savaşı %d: rakipten kimse geçemedi" % lvl)


## Kesişen yollar: A soldan sağa, B yukarıdan aşağı. B'nin önü A'nın ortasına çarpar,
## A ikiye bölünür. Her iki taraf eşit kayıp verir.
func _test_crossing_clash() -> void:
	print("Yol çarpışması (kesişen yollar)")
	var s := MatchState.new()
	s.players = [_player(0), _player(1)]
	s.bases = [
		_base(0, Vector2(100, 600), 0, 30.0), _base(1, Vector2(600, 600), 0, 0.0),
		_base(2, Vector2(350, 300), 1, 30.0), _base(3, Vector2(350, 900), 1, 0.0),
	]
	_no_production(s)
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [1]})
	s.apply_command({"type": "send", "owner": 1, "sources": [2], "targets": [3]})
	var max_groups := 0
	var t := 0.0
	while t < 20.0 and not s.groups.is_empty():
		s.step(GameConfig.SIM_DT)
		max_groups = maxi(max_groups, s.groups.size())
		t += GameConfig.SIM_DT
	var a_left: float = s.bases[1]["troops"]
	var b_left: float = s.bases[3]["troops"]
	_check(max_groups >= 3, "ortadan vurulan kol ikiye bölündü (en çok %d kol)" % max_groups)
	_check(a_left < 30.0 and is_equal_approx(a_left, b_left),
		"iki taraf eşit kayıp verdi (ulaşan: %.0f ve %.0f)" % [a_left, b_left])


func _test_levels_and_rewards() -> void:
	print("Bölümler, yıldızlar, ödüller")
	var bosses: Array = range(1, 51).filter(func(n): return GameConfig.is_boss(n))
	_check(bosses == [10, 20, 30, 40, 50], "boss bölümleri: %s" % [bosses])
	var skills: Array = range(1, 51).map(func(n): return GameConfig.skill_for_level(n))
	var rising := true
	for i in range(1, skills.size()):
		rising = rising and skills[i] >= skills[i - 1]
	_check(rising, "bot becerisi bölümle birlikte artıyor (%.2f → %.2f)" % [skills[0], skills[49]])
	var bands: Array = [1, 11, 21, 31, 41].map(func(n): return GameConfig.band_name(n))
	_check(bands == ["Kolay-Orta", "Orta", "Orta-Zor", "Zor", "Çok Zor"], "zorluk bantları: %s" % [bands])

	var p := GameConfig.level_params(5)
	_check(GameConfig.stars_for(p, p["par"] - 1, 0) == 3, "hedef sürede + az kayıp = 3 yıldız")
	_check(GameConfig.stars_for(p, p["par"] + 1, 0) == 2, "süre aşıldı = 2 yıldız")
	_check(GameConfig.stars_for(p, p["par"] + 1, GameConfig.STAR_LOSS_LIMIT + 1) == 1, "ikisi de tutmadı = 1 yıldız")
	var golds: Array = [1, 2, 3].map(func(st): return GameConfig.level_gold(5, st, 0))
	_check(golds == [50, 75, 100], "altın: 1★ 50, 2★ 75, 3★ 100 (bulunan: %s)" % [golds])
	_check(GameConfig.level_gold(10, 3, 0) == 200, "boss bölümü çift altın")
	_check(GameConfig.level_gold(5, 2, 3) == 15, "geliştirme olmayan tekrar oyunu %20 altın")

	var setup := LevelSetup.create(20, {"name": "P", "color": 1, "icon": 0, "upgrades": {}}, 42)
	var st: MatchState = setup["state"]
	var forts := st.bases.filter(func(b): return b["type"] == "fortress" and b["owner"] == 1)
	_check(st.players.size() == 2 and forts.size() == 1, "boss bölümünde boss tek rakip ve kalesi var")


func _survival_state() -> MatchState:
	var s := MatchState.new()
	s.economy = true
	s.players = [_player(0), _player(1)]
	s.bases = [
		_base(0, Vector2(100, 300), 0, 40.0), _base(1, Vector2(500, 300), 1, 10.0),
		_base(2, Vector2(100, 700), 0, 10.0), _base(3, Vector2(500, 700), 0, 10.0),
		_base(4, Vector2(300, 1000), 0, 10.0),
	]
	return s


func _test_survival_rules() -> void:
	print("Hayatta kalma kuralları")
	var s := _survival_state()
	_no_production(s)
	for i in 300:
		s.step(GameConfig.SIM_DT)
	_check(absf(s.players[0]["gold"] - 10.0) < 0.1, "10 saniyede 10 maç altını (bulunan: %.1f)" % s.players[0]["gold"])

	s.players[0]["gold"] = 1000.0
	_check(s.build_cost(0, 2, "barracks") == 100, "1. kışla 100 altın")
	_check(s.build(0, 2, "barracks"), "kışla kuruldu")
	_check(s.build_cost(0, 3, "barracks") == 150, "2. kışla %50 pahalı: 150")
	_check(s.build_cost(0, 2, "upgrade") == 150 and s.build(0, 2, "upgrade") and s.bases[2]["level"] == 2, "kışla 2. seviye: 150 altın")
	_check(s.build_cost(0, 1, "barracks") == -1, "rakibin üssüne inşaat yapılamaz")
	s.players[0]["gold"] = 10.0
	_check(not s.build(0, 3, "mine"), "parası yetmeyince inşaat olmaz")

	# Kışla bonusu: seviye 5 -> +%50 üretim, +%20 hız; iki tane olsa bile tavan +%100 / +%30
	s.bases[2]["level"] = 5
	s.bases[3]["type"] = "barracks"
	s.bases[3]["level"] = 5
	s.step(GameConfig.SIM_DT)
	_check(is_equal_approx(s.players[0]["pb"], 1.0) and is_equal_approx(s.players[0]["sb"], 0.3),
		"iki 5 yıldızlı kışla: bonus tavanı +%%100 üretim, +%%30 hız (bulunan: %.2f, %.2f)" % [s.players[0]["pb"], s.players[0]["sb"]])
	s.bases[3]["type"] = "normal"
	s.bases[3].erase("level")
	s.step(GameConfig.SIM_DT)
	_check(is_equal_approx(s.players[0]["pb"], 0.5) and is_equal_approx(s.players[0]["sb"], 0.2), "tek 5 yıldızlı kışla: +%50 üretim, +%20 hız")

	# Maden: 2 güçlü asker, gönderilemez, ele geçirilince normal üsse döner.
	s = _survival_state()
	_no_production(s)
	s.players[0]["gold"] = 200.0
	_check(s.build(0, 4, "mine"), "maden kuruldu")
	s.bases[4]["elite"] = 10.0
	s.bases[4]["troops"] = 0.0
	s.apply_command({"type": "send", "owner": 0, "sources": [4], "targets": [1]})
	_check(s.groups.is_empty(), "madenden asker gönderilemez")
	s.bases[1]["troops"] = 19.0
	s.apply_command({"type": "send", "owner": 1, "sources": [1], "targets": [4]})
	_run(s, 20.0)
	_check(s.bases[4]["owner"] == 0 and absf(s.bases[4]["elite"] - 0.5) < 0.01, "19 asker, 10 maden askerini (20 güç) yenemedi")
	s.bases[1]["owner"] = 1
	s.bases[1]["troops"] = 5.0
	s.apply_command({"type": "send", "owner": 1, "sources": [1], "targets": [4]})
	_run(s, 20.0)
	_check(s.bases[4]["owner"] == 1 and s.bases[4]["type"] == "normal" and not s.bases[4].has("elite"),
		"ele geçirilen maden normal üsse döndü")

	# Kale: en fazla yarısı gider, en az 20 kalır. Kalkanlı kale hasar almaz.
	s = _survival_state()
	s.bases[0]["type"] = "keep"
	s.bases[0]["troops"] = 100.0
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [2]})
	_check(_counts(s) == [50], "100 askerli kaleden en fazla yarısı (50) gider (bulunan: %s)" % [_counts(s)])
	s.groups.clear()
	s.bases[0]["troops"] = 60.0
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [2]})
	_check(_counts(s) == [20], "60 askerli kaleden 20 gider, 40 garnizon kalır (bulunan: %s)" % [_counts(s)])
	s.groups.clear()
	s.bases[1]["type"] = "citadel"
	s.bases[1]["troops"] = 250.0
	s.apply_command({"type": "send", "owner": 1, "sources": [1], "targets": [2]})
	_check(_counts(s) == [60], "düşman kalesi de saldırır: 250'den 60 gider, 190 garnizon (bulunan: %s)" % [_counts(s)])
	s = _survival_state()
	_no_production(s)
	s.bases[1]["type"] = "citadel"
	s.bases[1]["shielded"] = true
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [1]})
	_run(s, 20.0)
	_check(s.bases[1]["owner"] == 1 and is_equal_approx(s.bases[1]["troops"], 10.0), "kalkanlı düşman kalesi hasar almadı")

	# Dalgalar ve sonuç
	var setup := Survival.create({"name": "P", "color": 1, "icon": 0, "upgrades": {}}, 5)
	var st: MatchState = setup["state"]
	var sv: Survival = setup["survival"]
	_check(st.bases.size() == GameConfig.SURVIVAL_BASES and not Survival.fortress_of(st, 0).is_empty()
		and Survival.fortress_of(st, 1).get("shielded", false), "harita %d üs, iki kale, düşman kalesi kalkanlı" % st.bases.size())
	var waves := 0
	while st.time < 61.0:
		sv.update(st, GameConfig.SIM_DT)
		st.step(GameConfig.SIM_DT)
		for e in st.events:
			if e["type"] == "wave":
				waves += 1
		st.events.clear()
	_check(waves == 1 and sv.wave == 1, "60. saniyede 1. dalga geldi")
	_check(sv.wave_size(1) == GameConfig.WAVE_BASE and sv.wave_size(10) > sv.wave_size(5) * 2, "dalgalar hızlanarak büyüyor (%d, %d, %d)" % [sv.wave_size(1), sv.wave_size(5), sv.wave_size(10)])
	Survival.fortress_of(st, 0)["owner"] = 1
	_check(Survival.result(st) == "lose", "kale düşünce oyun biter")


func _sum_events(s: MatchState, kind: String, killer: int) -> float:
	var t := 0.0
	for e in s.events:
		if e["type"] == kind and e["killer"] == killer:
			t += e["n"]
	return t


func _test_quest_counting() -> void:
	print("Görevler: sayma ve ödüller")
	# Üs saldırısı: 25 asker, 10 savunana. 10 savunan + 10 saldıran ölür, 15 saldıran üssü alır.
	var s := MatchState.new()
	s.players = [_player(0), _player(1)]
	s.bases = [_base(0, Vector2(100, 300), 0, 25.0), _base(1, Vector2(500, 300), 1, 10.0)]
	_no_production(s)
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [1]})
	_run(s, 20.0)
	_check(is_equal_approx(_sum_events(s, "kill", 0), 10.0) and is_equal_approx(_sum_events(s, "kill", 1), 10.0),
		"üs saldırısı: oyuncu 10 öldürdü, savunma 10 öldürdü (bulunan: %.1f, %.1f)" % [_sum_events(s, "kill", 0), _sum_events(s, "kill", 1)])
	_check(_sum_events(s, "clash_kill", 0) == 0.0, "üs saldırısı yol çarpışması sayılmadı")

	# Yol çarpışması ayrı sayılır: 15'e 15, Yol Savaşı 1 -> oyuncu 15 öldürür, rakip 14.
	s = _head_on(1)
	_check(is_equal_approx(_sum_events(s, "clash_kill", 0), 15.0) and is_equal_approx(_sum_events(s, "clash_kill", 1), 14.0),
		"yol çarpışması: 15 ve 14 öldürme (bulunan: %.0f, %.0f)" % [_sum_events(s, "clash_kill", 0), _sum_events(s, "clash_kill", 1)])
	_check(is_equal_approx(_sum_events(s, "kill", 0), 0.0), "kalan 1 asker boş üsse girdi, o öldürme sayılmadı")

	# Kayıt: kademeli ödül, alma, gece yarısı sıfırlama, sadece yeni bölümler.
	var sd: Node = root.get_node("SaveData")
	var backup := {"gold": sd.gold, "stars": sd.stars.duplicate(), "level": sd.unlocked_level}
	sd.quest_day = ""
	sd.quest_add("kills", 120.0)
	_check(sd.quest_value("kills") == 120 and sd.quest_ready_gold("kills") == 40, "120 öldürme: 50 ve 100 kademeleri hazır (10 + 30)")
	var g0: int = sd.gold
	_check(sd.claim_quest("kills") == 40 and sd.gold == g0 + 40 and sd.quest_claimed_count("kills") == 2, "ödül alındı, 2 kademe işaretlendi")
	_check(sd.quest_ready_gold("kills") == 0, "aynı kademe iki kez alınamaz")
	sd.quest_add("kills", 100.0)
	_check(sd.quest_ready_gold("kills") == 50, "220'de 200 kademesi hazır (50)")
	sd.stars.erase(GameConfig.MAX_LEVEL)
	sd.record_win(GameConfig.MAX_LEVEL, 1)
	sd.record_win(GameConfig.MAX_LEVEL, 1)
	_check(sd.quest_value("new_levels") == 1, "aynı bölümü tekrar bitirmek yeni bölüm sayılmadı")
	sd.quest_day = "2000-01-01"
	_check(sd.quest_value("kills") == 0 and sd.quest_claimed_count("kills") == 0, "gün değişince görevler sıfırlandı")
	var all_tiers := 0
	for q in GameConfig.QUESTS:
		all_tiers += q["tiers"].size()
	_check(GameConfig.QUESTS.size() == 4 and all_tiers == 37, "4 görev, 37 kademe")
	sd.gold = backup["gold"]
	sd.stars = backup["stars"]
	sd.unlocked_level = backup["level"]
	sd.quest_day = ""
	sd.save()


func _test_bot_matches() -> void:
	print("Bot'a karşı bot maçları")
	var wins := {}
	var max_time := 0.0
	var max_groups := 0
	var t0 := Time.get_ticks_msec()
	for m in 20:
		var players: Array = []
		var n := 2 + m % 2
		for i in n:
			players.append(_player(i, m % 4))
		var s := MatchState.create(1000 + m, players, 10 + m % 5, 5, 20)
		var bots: Array = []
		for i in n:
			bots.append(BotAI.new(i, 0.3 + 0.35 * i, 77 + m * 10 + i))
		var winner := -9
		while s.time < 900.0:
			for b in bots:
				for c in b.update(s, GameConfig.SIM_DT):
					s.apply_command(c)
			s.step(GameConfig.SIM_DT)
			s.events.clear()
			max_groups = maxi(max_groups, s.groups.size())
			var alive := s.alive_players()
			if alive.size() <= 1:
				winner = alive[0] if alive.size() == 1 else -1
				break
		max_time = maxf(max_time, s.time)
		wins[winner] = wins.get(winner, 0) + 1
	print("  kazananlar (oyuncu id: maç sayısı; -9 = 15 dk'da bitmedi): ", wins)
	print("  en uzun maç: %.0f sn, aynı anda en çok %d kol, toplam süre %d ms" % [max_time, max_groups, Time.get_ticks_msec() - t0])
	_check(not wins.has(-9) or wins[-9] <= 3, "maçların çoğu 15 dakikada sonuçlanıyor")
