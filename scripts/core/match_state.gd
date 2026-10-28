class_name MatchState
extends RefCounted
## Bir maçın tüm durumu ve kuralları. Grafikten tamamen bağımsızdır.
##
## Multiplayer planı: host bu sınıfı çalıştırır. Oyuncuların hamleleri
## "komut" (Dictionary) olarak host'a gelir, host apply_command() ile uygular,
## düzenli aralıklarla snapshot() gönderir. Solo modda aynı sınıf yerelde çalışır.
##
## Asker kolları: gönderilen askerler tek bir top değil, sıra sıra yürüyen bir
## koldur. i. askerin kaynak üs merkezinden uzaklığı:
##     d - floor(i / lanes) * ROW_SPACING
## Askerler hedefe TEK TEK varır. Rakip kollar yolda karşılaşınca durur ve
## her adımda karşılıklı birer asker kaybeder (önce "kalkan" eksilir).

const NEUTRAL := -1
const ROW_SPACING := 9.0
const LANE_SPACING := 7.0
const MAX_LANES := 4
const SOLDIERS_PER_LANE := 12
## İki rakip askerin çarpışmış sayılacağı mesafe (piksel).
const CLASH_RANGE := 13.0

## {id, name, color, icon, bot, prod, speed, start_bonus, road}
var players: Array = []
## {id, pos: Vector2, owner, troops: float, type}
var bases: Array = []
## Yoldaki asker kolları:
## {id, owner, from, to, n, f, lanes, d, shield, dist, s0, s1, fighting}
##  n: koldaki asker numaralarının üst sınırı, f: önden eksilen (varan/ölen) asker sayısı
##  canlı asker = n - f; d: 0 numaralı askerin kaynaktan uzaklığı
##  s0/s1: yolun başladığı/bittiği uzaklık (üs kenarları)
##  shield: Yol Savaşı güçlendirmesinden gelen, çarpışmada önce eriyen bonus
var groups: Array = []
## Görsel efektler için olaylar. Ekran her karede okuyup temizler.
var events: Array = []
var time := 0.0
var _next_group_id := 0


static func make_player(id: int, pname: String, color_index: int, icon: int, is_bot: bool, upgrades: Dictionary) -> Dictionary:
	return {
		"id": id,
		"name": pname,
		"color": color_index,
		"icon": icon,
		"bot": is_bot,
		"prod": GameConfig.production_mult(upgrades.get("production", 0)),
		"speed": GameConfig.speed_mult(upgrades.get("speed", 0)),
		"start_bonus": GameConfig.start_bonus(upgrades.get("start", 0)),
		"road": GameConfig.road_bonus(upgrades.get("road", 0)),
	}


static func create(seed_val: int, player_list: Array, base_count: int, neutral_min: int, neutral_max: int) -> MatchState:
	var s := MatchState.new()
	s.players = player_list
	var starts: Array = []
	for p in player_list:
		starts.append(GameConfig.START_TROOPS + int(p["start_bonus"]))
	s.bases = MapGenerator.generate(seed_val, starts, base_count, GameConfig.MAP_RECT, neutral_min, neutral_max)
	return s


# ---------------------------------------------------------------- yardımcılar

func player_color(pid: int) -> Color:
	if pid == NEUTRAL:
		return GameConfig.color(-1)
	return GameConfig.color(players[pid]["color"])


func base_type(b: Dictionary) -> Dictionary:
	return GameConfig.BASE_TYPES[b["type"]]


func troop_speed(pid: int) -> float:
	return GameConfig.TROOP_SPEED * float(players[pid]["speed"])


static func group_count(g: Dictionary) -> int:
	return int(g["n"]) - int(g["f"])


func front_row(g: Dictionary) -> int:
	@warning_ignore("integer_division")
	return int(g["f"]) / int(g["lanes"])


func last_row(g: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (int(g["n"]) - 1) / int(g["lanes"])


func row_along(g: Dictionary, row: int) -> float:
	return g["d"] - row * ROW_SPACING


func front_along(g: Dictionary) -> float:
	return row_along(g, front_row(g))


func path_point(g: Dictionary, along: float) -> Vector2:
	var a: Vector2 = bases[g["from"]]["pos"]
	var b: Vector2 = bases[g["to"]]["pos"]
	return a.lerp(b, clampf(along / g["dist"], 0.0, 1.0))


## Kolun en öndeki askerinin konumu.
func group_position(g: Dictionary) -> Vector2:
	return path_point(g, front_along(g))


func _on_road(g: Dictionary, along: float) -> bool:
	return along >= g["s0"] and along <= g["s1"]


func alive_players() -> Array:
	var alive := {}
	for b in bases:
		if b["owner"] != NEUTRAL:
			alive[b["owner"]] = true
	for g in groups:
		alive[g["owner"]] = true
	return alive.keys()


## Saldırganın, `travel_time` saniye sonra varacağı hedefi alması için
## göndermesi gereken asker sayısı (tahmini).
func troops_needed(target: Dictionary, travel_time: float, attacker: int) -> float:
	var bt := base_type(target)
	var tr: float = target["troops"]
	if target["owner"] != NEUTRAL and tr < bt["capacity"]:
		tr = minf(bt["capacity"], tr + bt["growth"] * float(players[target["owner"]]["prod"]) * travel_time)
	for g in groups:
		if g["to"] != target["id"]:
			continue
		if g["owner"] == target["owner"]:
			tr += group_count(g)
		elif g["owner"] == attacker:
			tr -= group_count(g)
	return maxf(tr, 0.0) * float(bt["defense"])


# ---------------------------------------------------------------- simülasyon

func step(dt: float) -> void:
	time += dt
	for b in bases:
		if b["owner"] == NEUTRAL:
			continue
		var bt := base_type(b)
		var cap: float = bt["capacity"]
		if b["troops"] < cap:
			b["troops"] = minf(cap, b["troops"] + bt["growth"] * float(players[b["owner"]]["prod"]) * dt)
		elif b["troops"] > cap:
			b["troops"] = maxf(cap, b["troops"] - GameConfig.OVERFLOW_DECAY * dt)

	_resolve_clashes()

	for g in groups:
		if not g["fighting"]:
			g["d"] += troop_speed(g["owner"]) * dt
		# Hedefin kenarına ulaşan askerler tek tek üsse girer.
		while group_count(g) > 0 and front_along(g) >= g["s1"]:
			g["f"] += 1
			_arrive_one(g)

	groups = groups.filter(func(g): return group_count(g) > 0)


func apply_command(cmd: Dictionary) -> void:
	match cmd.get("type", ""):
		"send":
			_send(int(cmd["owner"]), cmd["sources"], cmd["targets"])


## Her kaynak üs askerlerini (SEND_FRACTION kadarını) hedeflere EŞİT böler.
## Örn: 100 asker, 2 hedef -> 50 + 50. Bölünmeyen artık ilk hedeflere 1'er eklenir.
func _send(owner: int, sources: Array, targets: Array) -> void:
	var tgts: Array = []
	for t in targets:
		var ti := int(t)
		if ti >= 0 and ti < bases.size() and not tgts.has(ti):
			tgts.append(ti)

	var used_sources: Array = []
	for s in sources:
		var si := int(s)
		if si < 0 or si >= bases.size() or used_sources.has(si):
			continue
		used_sources.append(si)
		var b: Dictionary = bases[si]
		if b["owner"] != owner:
			continue
		var my_targets := tgts.filter(func(x): return x != si)
		if my_targets.is_empty():
			continue
		var total := int(floor(b["troops"] * GameConfig.SEND_FRACTION))
		if total <= 0:
			continue
		var n := my_targets.size()
		@warning_ignore("integer_division")
		var share := total / n
		var rem := total % n
		b["troops"] -= total
		for i in n:
			var c := share + (1 if i < rem else 0)
			if c > 0:
				_spawn_group(owner, si, my_targets[i], c)


func _spawn_group(owner: int, from_id: int, to_id: int, count: int) -> void:
	var g := _make_group(_next_group_id, owner, from_id, to_id, count, 0,
		clampi(ceili(count / float(SOLDIERS_PER_LANE)), 1, MAX_LANES), -1.0, int(players[owner]["road"]))
	_next_group_id += 1
	groups.append(g)


## d < 0 verilirse kol kaynak üssün kenarından başlar.
func _make_group(id: int, owner: int, from_id: int, to_id: int, n: int, f: int, lanes: int, d: float, shield: int) -> Dictionary:
	var a: Dictionary = bases[from_id]
	var b: Dictionary = bases[to_id]
	var dist := maxf(a["pos"].distance_to(b["pos"]), 1.0)
	var s0: float = minf(base_type(a)["radius"], dist * 0.5)
	var s1: float = maxf(dist - base_type(b)["radius"], s0)
	return {
		"id": id, "owner": owner, "from": from_id, "to": to_id,
		"n": n, "f": f, "lanes": lanes, "d": s0 if d < 0.0 else d,
		"shield": shield, "dist": dist, "s0": s0, "s1": s1, "fighting": false,
	}


func _arrive_one(g: Dictionary) -> void:
	var b: Dictionary = bases[g["to"]]
	var pos := path_point(g, g["s1"])
	if b["owner"] == g["owner"]:
		b["troops"] += 1.0
		events.append({"type": "reinforce", "base": b["id"], "owner": g["owner"], "pos": pos})
		return
	var defense: float = base_type(b)["defense"]
	b["troops"] -= 1.0 / defense
	events.append({"type": "hit", "base": b["id"], "owner": g["owner"], "pos": pos})
	if b["troops"] < 0.0:
		var old: int = b["owner"]
		b["owner"] = g["owner"]
		b["troops"] = -b["troops"] * defense
		events.append({"type": "capture", "base": b["id"], "from": old, "to": g["owner"], "pos": b["pos"]})


# ---------------------------------------------------------------- yol çarpışmaları

## Her kolun en öndeki askeri, rakip kolların herhangi bir sırasına değiyor mu?
## Ortadan çarpışma (kesişen yollar) olursa vurulan kol o noktadan ikiye bölünür,
## böylece her çarpışma "ön asker - ön asker" olarak çözülür.
func _resolve_clashes() -> void:
	for g in groups:
		g["fighting"] = false
	if groups.size() < 2:
		return

	var pairs: Array = []
	var paired := {}
	var split_this_step := {}
	var count := groups.size()
	for i in count:
		var a: Dictionary = groups[i]
		var fa := front_along(a)
		if not _on_road(a, fa):
			continue
		var pa := path_point(a, fa)
		for j in count:
			var b: Dictionary = groups[j]
			if b["owner"] == a["owner"] or group_count(b) <= 0:
				continue
			var hit_row := -1
			for r in range(front_row(b), last_row(b) + 1):
				var al := row_along(b, r)
				if al < b["s0"]:
					break  # bundan sonraki sıralar henüz üssün içinde
				if al <= b["s1"] and pa.distance_to(path_point(b, al)) < CLASH_RANGE:
					hit_row = r
					break
			if hit_row < 0:
				continue
			var target := b
			if hit_row > front_row(b):
				if split_this_step.has(b["id"]):
					continue
				target = _split(b, hit_row)
				split_this_step[b["id"]] = true
			var key := "%d-%d" % [mini(a["id"], target["id"]), maxi(a["id"], target["id"])]
			if not paired.has(key):
				paired[key] = true
				pairs.append([a, target])
			break  # her kol adım başına tek çarpışma başlatır

	for p in pairs:
		var a: Dictionary = p[0]
		var b: Dictionary = p[1]
		if group_count(a) <= 0 or group_count(b) <= 0:
			continue
		_lose(a)
		_lose(b)
		a["fighting"] = true
		b["fighting"] = true
		events.append({"type": "clash", "a": a["owner"], "b": b["owner"],
			"pos": (group_position(a) + group_position(b)) * 0.5})


func _lose(g: Dictionary) -> void:
	if g["shield"] > 0:
		g["shield"] -= 1
	else:
		g["f"] += 1


## Kolu `row` sırasından ikiye böler; arka parçayı (yeni kol) döndürür.
func _split(g: Dictionary, row: int) -> Dictionary:
	var cut: int = row * int(g["lanes"])
	var rear := _make_group(_next_group_id, g["owner"], g["from"], g["to"],
		int(g["n"]) - cut, 0, g["lanes"], row_along(g, row), 0)
	_next_group_id += 1
	g["n"] = cut
	groups.append(rear)
	return rear


# ---------------------------------------------------------------- ağ için

## Maç başında bir kez gönderilir: oyuncular + harita.
func setup_dict() -> Dictionary:
	var bs: Array = []
	for b in bases:
		bs.append({"x": b["pos"].x, "y": b["pos"].y, "o": b["owner"], "n": b["troops"], "k": b["type"]})
	return {"players": players, "bases": bs}


static func from_setup(d: Dictionary) -> MatchState:
	var s := MatchState.new()
	s.players = d["players"]
	for i in d["bases"].size():
		var b: Dictionary = d["bases"][i]
		s.bases.append({"id": i, "pos": Vector2(b["x"], b["y"]), "owner": int(b["o"]), "troops": float(b["n"]), "type": b["k"]})
	return s


## Oyun sırasında host'un düzenli gönderdiği küçük durum paketi.
func snapshot() -> Dictionary:
	var bs: Array = []
	for b in bases:
		bs.append([b["owner"], snappedf(b["troops"], 0.1)])
	var gs: Array = []
	for g in groups:
		gs.append([g["id"], g["owner"], g["from"], g["to"], g["n"], g["f"], g["lanes"], snappedf(g["d"], 0.1), g["shield"]])
	return {"t": time, "b": bs, "g": gs}


func apply_snapshot(d: Dictionary) -> void:
	time = d["t"]
	for i in d["b"].size():
		bases[i]["owner"] = int(d["b"][i][0])
		bases[i]["troops"] = float(d["b"][i][1])
	groups.clear()
	for e in d["g"]:
		groups.append(_make_group(int(e[0]), int(e[1]), int(e[2]), int(e[3]),
			int(e[4]), int(e[5]), int(e[6]), float(e[7]), int(e[8])))
