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
