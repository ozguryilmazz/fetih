extends Control
## Bölüm seçimi: yukarıdan aşağı kıvrılan bir yol üzerinde 50 bölüm noktası.
## Her 10 bölüm bir zorluk bandı (ayrı zemin tonu ve başlık), her 10. bölüm boss.

func _ready() -> void:
	var box := UIKit.screen(self, "Bölümler")
	var total := UIKit.label("Toplam yıldız: %d / %d" % [SaveData.total_stars(), GameConfig.MAX_LEVEL * 3], 28, UIKit.ACCENT)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(total)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var map := LevelMap.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.level_chosen.connect(func(n: int):
		Session.mode = "solo"
		Session.level = n
		Session.go("game"))
	scroll.add_child(map)

	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu"), 84))
	_scroll_to_current(scroll, map)


func _scroll_to_current(scroll: ScrollContainer, map: LevelMap) -> void:
	# Yerleşim bitsin diye iki kare bekle.
	await get_tree().process_frame
	await get_tree().process_frame
	var y := map.node_pos(SaveData.unlocked_level).y
	scroll.scroll_vertical = int(maxf(0.0, y - scroll.size.y * 0.5))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")


## Haritayı çizen ve dokunmaları bölüme çeviren kontrol.
class LevelMap extends Control:
	signal level_chosen(n: int)

	const STEP := 132.0
	const BAND_GAP := 110.0
	const TOP := 60.0
	const R := 40.0
	const R_BOSS := 52.0
	const BAND_TINTS := [Color("#1d3b5c"), Color("#2a4a2f"), Color("#5a4a22"), Color("#5a2e2e"), Color("#3e2a5a")]
	const DONE_COL := Color("#3a7bd5")
	const LOCK_COL := Color("#3b4170")
	const BOSS_COL := Color("#c0392b")

	var _press := Vector2.ZERO
	var _font: Font

	func _ready() -> void:
		_font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = node_pos(GameConfig.MAX_LEVEL).y + 120.0
		resized.connect(queue_redraw)

	## Bölüm n'nin haritadaki merkezi.
	func node_pos(n: int) -> Vector2:
		var i := n - 1
		@warning_ignore("integer_division")
		var band := i / 10
		var y := TOP + i * STEP + band * BAND_GAP + BAND_GAP * 0.6
		var w := maxf(size.x, 300.0)
		var x := w * 0.5 + sin(i * 0.85) * w * 0.30
		return Vector2(x, y)

	func _band_rect(band: int) -> Rect2:
		var top := node_pos(band * 10 + 1).y - BAND_GAP * 0.85
		var bottom := node_pos(band * 10 + 10).y + STEP * 0.5
		return Rect2(0, top, size.x, bottom - top)

	func _process(_delta: float) -> void:
		queue_redraw()  # açık bölümün nabız efekti için

	func _draw() -> void:
		var unlocked := SaveData.unlocked_level
		# Bant zeminleri ve başlıklar
		for band in GameConfig.BAND_NAMES.size():
			var rect := _band_rect(band)
			var tint: Color = BAND_TINTS[band]
			tint.a = 0.28
			draw_rect(rect.grow_individual(-4, 0, -4, 0), tint)
			var first := band * 10 + 1
			var title := "%d–%d  ·  %s" % [first, first + 9, GameConfig.BAND_NAMES[band]]
			draw_string(_font, Vector2(20, rect.position.y + 40), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UIKit.MUTED)

		# Yol
		for n in range(1, GameConfig.MAX_LEVEL):
			var a := node_pos(n)
			var b := node_pos(n + 1)
			var pts := PackedVector2Array()
			for k in 13:
				var t := k / 12.0
				var p := a.lerp(b, t)
				p.x += sin(t * PI) * (b.x - a.x) * 0.0
				pts.append(p)
			if n + 1 <= unlocked:
				draw_polyline(pts, Color(1, 1, 1, 0.08), 22.0, true)
				draw_polyline(pts, UIKit.ACCENT.darkened(0.25), 8.0, true)
			else:
				draw_dashed_line(a, b, Color(1, 1, 1, 0.18), 6.0, 16.0, true)

		# Noktalar
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
		for n in range(1, GameConfig.MAX_LEVEL + 1):
			_draw_node(n, unlocked, pulse)

	func _draw_node(n: int, unlocked: int, pulse: float) -> void:
		var c := node_pos(n)
		var boss := GameConfig.is_boss(n)
		var r := R_BOSS if boss else R
		var locked := n > unlocked
		var stars := SaveData.best_stars(n)
		var col := LOCK_COL
		if not locked:
			col = BOSS_COL if boss else (DONE_COL if stars > 0 else UIKit.ACCENT.darkened(0.15))

		if n == unlocked:
			var glow := UIKit.ACCENT
			glow.a = 0.35 + 0.35 * pulse
			draw_arc(c, r + 10.0 + pulse * 4.0, 0.0, TAU, 56, glow, 6.0, true)
		draw_circle(c + Vector2(3, 9), r, Color(0, 0, 0, 0.3))
		draw_circle(c + Vector2(0, 5), r, col.darkened(0.45))
		var body := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_texture_rect(Art.ball(), body, false, col.lightened(0.12))
		draw_texture_rect(Art.gloss(), body, false)

		if boss:
			var top := c + Vector2(0, -r - 10.0)
			var crown := PackedVector2Array([
				top + Vector2(-18, 10), top + Vector2(-18, -6), top + Vector2(-9, 2), top + Vector2(0, -10),
				top + Vector2(9, 2), top + Vector2(18, -6), top + Vector2(18, 10)])
			draw_colored_polygon(crown, UIKit.ACCENT if not locked else Color(1, 1, 1, 0.25))

		if locked:
			_draw_lock(c, Color(1, 1, 1, 0.45))
		else:
			_text_centered(str(n), c, 32 if boss else 30, Color.WHITE)
			# Yıldızlar
			for i in 3:
				var sp := c + Vector2((i - 1) * 22.0, r + 18.0)
				var sc := UIKit.ACCENT if i < stars else Color(1, 1, 1, 0.2)
				draw_colored_polygon(IconDraw.star_points(sp, 10.0), sc)

	func _draw_lock(c: Vector2, col: Color) -> void:
		draw_arc(c + Vector2(0, -6), 9.0, PI, TAU, 16, col, 4.0, true)
		draw_rect(Rect2(c + Vector2(-13, -6), Vector2(26, 20)), col)

	func _text_centered(text: String, c: Vector2, fs: int, col: Color) -> void:
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := c.y + (_font.get_ascent(fs) - _font.get_descent(fs)) / 2.0
		draw_string_outline(_font, Vector2(c.x - w / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.4))
		draw_string(_font, Vector2(c.x - w / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	## Dokunma: parmak az kayarak kalkarsa (kaydırma değil) dokunulan bölümü aç.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press = event.position
			elif event.position.distance_to(_press) < 20.0:
				var n := _level_at(event.position)
				if n > 0 and n <= SaveData.unlocked_level:
					level_chosen.emit(n)

	func _level_at(p: Vector2) -> int:
		for n in range(1, GameConfig.MAX_LEVEL + 1):
			var r := (R_BOSS if GameConfig.is_boss(n) else R) + 14.0
			if p.distance_to(node_pos(n)) <= r:
				return n
		return 0
