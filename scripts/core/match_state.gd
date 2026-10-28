class_name MatchState
extends RefCounted
## Bir maçın tüm durumu ve kuralları. Grafikten tamamen bağımsızdır.
##
## Multiplayer planı: host bu sınıfı çalıştırır. Oyuncuların hamleleri
## "komut" (Dictionary) olarak host'a gelir, host apply_command() ile uygular,
## düzenli aralıklarla snapshot() gönderir. Solo modda aynı sınıf yerelde çalışır.

const NEUTRAL := -1

## {id, name, color, icon, bot, prod, speed, start_bonus}
var players: Array = []
## {id, pos: Vector2, owner, troops: float, type}
var bases: Array = []
## Yoldaki asker grupları: {id, owner, from, to, count, t (0..1), dist}
var groups: Array = []
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


func group_position(g: Dictionary) -> Vector2:
	var a: Vector2 = bases[g["from"]]["pos"]
	var b: Vector2 = bases[g["to"]]["pos"]
	return a.lerp(b, clampf(g["t"], 0.0, 1.0))


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
			tr += g["count"]
		elif g["owner"] == attacker:
			tr -= g["count"]
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

	var arrived: Array = []
	for g in groups:
		g["t"] += troop_speed(g["owner"]) * dt / g["dist"]
		if g["t"] >= 1.0:
			arrived.append(g)
	for g in arrived:
		groups.erase(g)
		_arrive(g)


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
	var dist: float = bases[from_id]["pos"].distance_to(bases[to_id]["pos"])
	groups.append({
		"id": _next_group_id,
		"owner": owner,
		"from": from_id,
		"to": to_id,
		"count": count,
		"t": 0.0,
		"dist": maxf(dist, 1.0),
	})
	_next_group_id += 1


func _arrive(g: Dictionary) -> void:
	var b: Dictionary = bases[g["to"]]
	if b["owner"] == g["owner"]:
		b["troops"] += g["count"]
		return
	var defense: float = base_type(b)["defense"]
	b["troops"] -= g["count"] / defense
	if b["troops"] < 0.0:
		b["owner"] = g["owner"]
		b["troops"] = -b["troops"] * defense


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
		gs.append([g["id"], g["owner"], g["from"], g["to"], g["count"], snappedf(g["t"], 0.001)])
	return {"t": time, "b": bs, "g": gs}


func apply_snapshot(d: Dictionary) -> void:
	time = d["t"]
	for i in d["b"].size():
		bases[i]["owner"] = int(d["b"][i][0])
		bases[i]["troops"] = float(d["b"][i][1])
	groups.clear()
	for e in d["g"]:
		var from_id := int(e[2])
		var to_id := int(e[3])
		groups.append({
			"id": int(e[0]), "owner": int(e[1]), "from": from_id, "to": to_id,
			"count": int(e[4]), "t": float(e[5]),
			"dist": maxf(bases[from_id]["pos"].distance_to(bases[to_id]["pos"]), 1.0),
		})
