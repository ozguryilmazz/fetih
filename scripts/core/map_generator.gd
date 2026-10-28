class_name MapGenerator
extends RefCounted
## Rastgele harita üretici. Aynı seed her cihazda aynı haritayı üretir.


## starts: her oyuncunun başlangıç asker sayısı (dizi sırası = oyuncu id).
static func generate(seed_val: int, starts: Array, base_count: int, rect: Rect2, neutral_min: int, neutral_max: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var radius: float = GameConfig.BASE_TYPES["normal"]["radius"]
	var count := maxi(base_count, starts.size() + 1)

	# Üsleri birbirine fazla yaklaşmayacak şekilde rastgele yerleştir.
	var min_dist := sqrt(rect.get_area() / count) * 0.85
	var points: Array = []
	var tries := 0
	while points.size() < count:
		tries += 1
		if tries > 4000:
			min_dist *= 0.9
			tries = 0
		var p := Vector2(
			rng.randf_range(rect.position.x + radius, rect.end.x - radius),
			rng.randf_range(rect.position.y + radius, rect.end.y - radius))
		var ok := true
		for q in points:
			if p.distance_to(q) < maxf(min_dist, radius * 2.6):
				ok = false
				break
		if ok:
			points.append(p)

	# Başlangıç üslerini birbirinden olabildiğince uzak seç.
	var start_idx: Array = [rng.randi_range(0, points.size() - 1)]
	while start_idx.size() < starts.size():
		var best := -1
		var best_d := -1.0
		for i in points.size():
			if start_idx.has(i):
				continue
			var d := INF
			for j in start_idx:
				d = minf(d, points[i].distance_to(points[j]))
			if d > best_d:
				best_d = d
				best = i
		start_idx.append(best)

	var bases: Array = []
	for i in points.size():
		var owner := start_idx.find(i)  # -1 ise tarafsız
		var troops := float(starts[owner]) if owner >= 0 else float(rng.randi_range(neutral_min, neutral_max))
		bases.append({"id": i, "pos": points[i], "owner": owner, "troops": troops, "type": "normal"})
	return bases
