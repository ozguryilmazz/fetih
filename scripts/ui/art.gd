class_name Art
extends RefCounted
## Kodla üretilen dokular (resim dosyası yok, APK büyümez). Bir kez üretilip saklanır.

static var _ground: Texture2D
static var _vignette: Texture2D
static var _ball: Texture2D
static var _gloss: Texture2D


## Hafif dokulu zemin: dikişsiz gürültü + seyrek nokta ızgarası. Döşenerek (tile) çizilir.
static func ground() -> Texture2D:
	if _ground:
		return _ground
	var size := 256
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	noise.seed = 7
	var src: Image = noise.get_seamless_image(size, size)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var base := UIKit.BG
	for y in size:
		for x in size:
			var v: float = src.get_pixel(x, y).r  # 0..1
			var c := base.lightened((v - 0.5) * 0.08) if v >= 0.5 else base.darkened((0.5 - v) * 0.12)
			img.set_pixel(x, y, c)
	# Seyrek, çok hafif nokta ızgarası (her 32 px).
	var dot := base.lightened(0.10)
	for gy in range(0, size, 32):
		for gx in range(0, size, 32):
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if absi(ox) + absi(oy) <= 1:
						img.set_pixel((gx + ox + size) % size, (gy + oy + size) % size, dot)
	_ground = ImageTexture.create_from_image(img)
	return _ground


## Kenarları hafifçe karartan yarı saydam katman (ekrana gerilerek çizilir).
static func vignette() -> Texture2D:
	if _vignette:
		return _vignette
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0, 0, 0, 0.55))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.2, 0.5)
	t.width = 256
	t.height = 256
	_vignette = t
	return _vignette


## Üs gövdesi: hafif kubbe gölgelendirmesi (gri tonlu, çizerken renklendirilir).
static func ball() -> Texture2D:
	if _ball:
		return _ball
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var light := Vector3(-0.45, -0.55, 0.7).normalized()
	var r := s / 2.0
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5 - r, y + 0.5 - r) / r
			var d := p.length()
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Basık kubbe: kenarlara doğru eğilen yüzey.
			var z := sqrt(maxf(0.0, 1.0 - d * d * 0.85))
			var n := Vector3(p.x * 0.6, p.y * 0.6, z).normalized()
			var shade := 0.72 + 0.28 * maxf(0.0, n.dot(light))
			shade *= 1.0 - 0.22 * smoothstep(0.82, 1.0, d)
			var alpha := clampf((1.0 - d) * r * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	_ball = ImageTexture.create_from_image(img)
	return _ball


## Sol üstte yumuşak parlama (beyaz, yarı saydam).
static func gloss() -> Texture2D:
	if _gloss:
		return _gloss
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var r := s / 2.0
	var center := Vector2(-0.32, -0.38)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5 - r, y + 0.5 - r) / r
			if p.length() > 0.96:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
				continue
			var q := (p - center) / Vector2(0.48, 0.32)
			var a := clampf(1.0 - q.length(), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * 0.45))
	_gloss = ImageTexture.create_from_image(img)
	return _gloss
