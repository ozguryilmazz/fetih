extends SceneTree
## Ekransız test: godot --headless --path . -s tests/sim_test.gd
## 1) Eşit bölüştürme kuralını doğrular. 2) Bot'ları birbirine karşı oynatır.

var _failed := false


func _initialize() -> void:
	_test_equal_split()
	_test_bot_matches()
	print("SONUC: ", "HATA" if _failed else "TAMAM")
	quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  HATA ") + msg)
	if not cond:
		_failed = true


func _player(id: int) -> Dictionary:
	return MatchState.make_player(id, "P%d" % id, id, 0, true, {})


func _test_equal_split() -> void:
	print("Eşit bölüştürme testi")
	var s := MatchState.new()
	s.players = [_player(0), _player(1)]
	s.bases = [
		{"id": 0, "pos": Vector2(100, 100), "owner": 0, "troops": 100.0, "type": "normal"},
		{"id": 1, "pos": Vector2(400, 100), "owner": 1, "troops": 10.0, "type": "normal"},
		{"id": 2, "pos": Vector2(100, 600), "owner": 1, "troops": 10.0, "type": "normal"},
		{"id": 3, "pos": Vector2(400, 600), "owner": -1, "troops": 5.0, "type": "normal"},
		{"id": 4, "pos": Vector2(250, 300), "owner": 0, "troops": 7.0, "type": "normal"},
	]
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [1, 2]})
	var counts: Array = s.groups.map(func(g): return g["count"])
	_check(counts == [50, 50], "100 asker 2 hedefe -> 50+50 (bulunan: %s)" % [counts])
	_check(is_zero_approx(s.bases[0]["troops"]), "kaynak üs boşaldı")

	s.groups.clear()
	s.apply_command({"type": "send", "owner": 0, "sources": [4], "targets": [1, 2, 3]})
	counts = s.groups.map(func(g): return g["count"])
	_check(counts == [3, 2, 2], "7 asker 3 hedefe -> 3+2+2 (bulunan: %s)" % [counts])

	s.groups.clear()
	s.bases[0]["troops"] = 30.0
	s.bases[4]["troops"] = 20.0
	s.apply_command({"type": "send", "owner": 0, "sources": [0, 4], "targets": [3]})
	counts = s.groups.map(func(g): return g["count"])
	_check(counts == [30, 20], "2 kaynak 1 hedefe -> 30 ve 20 (bulunan: %s)" % [counts])

	s.groups.clear()
	s.bases[1]["troops"] = 50.0
	s.apply_command({"type": "send", "owner": 0, "sources": [1], "targets": [3]})
	_check(s.groups.is_empty(), "rakibin üssünden gönderim reddedildi")

	# Ele geçirme: 10 savunan, 25 saldıran. Yol 300 px / 120 hız = 2.5 sn;
	# bu sürede savunan 2.5 asker daha üretir -> 25 - 12.5 = 12.5 ile el değiştirir.
	s.groups.clear()
	s.bases[1]["troops"] = 10.0
	s.bases[0]["troops"] = 25.0
	s.apply_command({"type": "send", "owner": 0, "sources": [0], "targets": [1]})
	for i in 200:
		s.step(GameConfig.SIM_DT)
		if s.groups.is_empty():
			break
	_check(s.bases[1]["owner"] == 0, "üs ele geçirildi")
	_check(absf(s.bases[1]["troops"] - 12.5) < 0.6, "kalan asker ~12.5 (bulunan: %.1f)" % s.bases[1]["troops"])

	# Ağ paketi gidip gelince durum aynı kalmalı.
	var copy := MatchState.from_setup(s.setup_dict())
	copy.apply_snapshot(s.snapshot())
	_check(copy.bases.size() == s.bases.size() and copy.bases[1]["owner"] == 0, "setup/snapshot gidiş-dönüş")


func _test_bot_matches() -> void:
	print("Bot'a karşı bot maçları")
	var wins := {}
	var max_time := 0.0
	for m in 20:
		var players: Array = []
		var n := 2 + m % 2
		for i in n:
			players.append(_player(i))
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
			var alive := s.alive_players()
			if alive.size() <= 1:
				winner = alive[0] if alive.size() == 1 else -1
				break
		max_time = maxf(max_time, s.time)
		wins[winner] = wins.get(winner, 0) + 1
	print("  kazananlar (oyuncu id: maç sayısı; -9 = 15 dk'da bitmedi): ", wins)
	print("  en uzun maç: %.0f sn" % max_time)
	_check(not wins.has(-9) or wins[-9] <= 3, "maçların çoğu 15 dakikada sonuçlanıyor")
