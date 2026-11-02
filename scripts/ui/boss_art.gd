class_name BossArt
extends RefCounted
## Boss yaratıklarının kodla çizilen resimleri (resim dosyası yok).
## draw(ci, tür, merkez, boyut, zaman): boyut ≈ yarıçap. Hem kale üstünde (küçük)
## hem efsane kartında (büyük) kullanılır.

const COLORS := {
	"tepegoz": Color("#b07a4f"),
	"sahmeran": Color("#3fae6a"),
	"karakoncolos": Color("#3a3150"),
	"zumruduanka": Color("#19c39a"),
	"ejderha": Color("#d8402f"),
	"albasti": Color("#d1355a"),
	"yelbegen": Color("#7a9a3c"),
	"erlik": Color("#4b4fb0"),
}


static func color(kind: String) -> Color:
	return COLORS.get(kind, Color.WHITE)


static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, t: float) -> void:
	match kind:
		"tepegoz":
			_tepegoz(ci, c, s, t)
		"sahmeran":
			_sahmeran(ci, c, s, t)
		"karakoncolos":
			_karakoncolos(ci, c, s, t)
		"zumruduanka":
			_zumruduanka(ci, c, s, t)
		"ejderha":
			_ejderha(ci, c, s, t)
		"albasti":
			_albasti(ci, c, s, t)
		"yelbegen":
			_yelbegen(ci, c, s, t)
		"erlik":
			_erlik(ci, c, s, t)


static func _poly(ci: CanvasItem, c: Vector2, s: float, pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + Vector2(p[0], p[1]) * s)
	ci.draw_colored_polygon(out, col)


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	ci.draw_colored_polygon(pts, col)


## Tek gözlü dev: iri baş, tek kocaman göz, tek kaş, dişli ağız, boynuzlar.
static func _tepegoz(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var skin := Color("#c48a5a")
	_poly(ci, c, s, [[-0.62, -0.55], [-0.95, -1.0], [-0.42, -0.72]], Color("#efe3c4"))
	_poly(ci, c, s, [[0.62, -0.55], [0.95, -1.0], [0.42, -0.72]], Color("#efe3c4"))
	_ellipse(ci, c + Vector2(0, 0.08) * s, 0.8 * s, 0.86 * s, skin.darkened(0.25))
	_ellipse(ci, c, 0.76 * s, 0.82 * s, skin)
	_ellipse(ci, c + Vector2(-0.22, -0.3) * s, 0.3 * s, 0.22 * s, Color(1, 1, 1, 0.12))
	# Tek göz (kırpar gibi göz bebeği oynar)
	var eye := c + Vector2(0, -0.18) * s
	_ellipse(ci, eye, 0.42 * s, 0.34 * s, Color("#fff8ec"))
	var look := Vector2(sin(t * 1.3) * 0.12, cos(t * 0.9) * 0.05) * s
	ci.draw_circle(eye + look, 0.2 * s, Color("#c0392b"))
	ci.draw_circle(eye + look, 0.1 * s, Color("#1a0f0a"))
	ci.draw_circle(eye + look + Vector2(-0.05, -0.06) * s, 0.04 * s, Color(1, 1, 1, 0.9))
	ci.draw_arc(eye, 0.42 * s, PI * 1.08, PI * 1.92, 20, skin.darkened(0.5), 0.07 * s, true)
	# Tek kaş
	_poly(ci, c, s, [[-0.5, -0.62], [0.5, -0.62], [0.42, -0.5], [-0.42, -0.5]], Color("#3b2416"))
	# Ağız ve dişler
	_ellipse(ci, c + Vector2(0, 0.45) * s, 0.36 * s, 0.14 * s, Color("#4a1712"))
	for i in 4:
		var x := -0.24 + i * 0.16
		_poly(ci, c, s, [[x - 0.05, 0.36], [x + 0.05, 0.36], [x, 0.46]], Color("#fff8ec"))


## Şahmeran: kıvrılmış yılan gövdesi, üstünde taçlı kadın başı.
static func _sahmeran(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var green := Color("#3fae6a")
	var dark := green.darkened(0.4)
	# Kıvrımlar: alttan yukarı küçülen halkalar
	for k in 3:
		var y := 0.62 - k * 0.3
		var w := 0.85 - k * 0.2
		_ellipse(ci, c + Vector2(0, y + 0.05) * s, w * s, 0.2 * s, dark)
		_ellipse(ci, c + Vector2(0, y) * s, w * s, 0.18 * s, green)
		for j in 5:
			var x := (-0.6 + j * 0.3) * (w / 0.85)
			ci.draw_circle(c + Vector2(x, y) * s, 0.045 * s, Color("#f2d04b"))
	# Kuyruk ucu sallanır
	var tip := c + Vector2(0.95, 0.5 + sin(t * 3.0) * 0.08) * s
	ci.draw_line(c + Vector2(0.78, 0.62) * s, tip, green, 0.09 * s, true)
	# Kadın başı ve saçı
	var head := c + Vector2(0, -0.42) * s
	_ellipse(ci, head + Vector2(0, 0.06) * s, 0.34 * s, 0.38 * s, Color("#1d3b2a"))
	_ellipse(ci, head, 0.25 * s, 0.3 * s, Color("#f1c9a5"))
	ci.draw_circle(head + Vector2(-0.09, -0.02) * s, 0.04 * s, Color("#173d2a"))
	ci.draw_circle(head + Vector2(0.09, -0.02) * s, 0.04 * s, Color("#173d2a"))
	ci.draw_arc(head + Vector2(0, 0.1) * s, 0.08 * s, 0.3, PI - 0.3, 10, Color("#8a3b3b"), 0.03 * s, true)
	# Taç
	_poly(ci, head, s, [[-0.22, -0.24], [-0.22, -0.4], [-0.11, -0.3], [0, -0.46], [0.11, -0.3], [0.22, -0.4], [0.22, -0.24]], Color("#f2c94c"))
	ci.draw_circle(head + Vector2(0, -0.33) * s, 0.04 * s, Color("#2ecc71"))


## Karakoncolos: kapkara, tüylü top; parlayan sarı gözler, uzun pençeler.
static func _karakoncolos(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var fur := Color("#2b2338")
	var pts := PackedVector2Array()
	var n := 30
	for i in n:
		var a := TAU * i / n
		var rr := (0.82 if i % 2 == 0 else 0.62) + sin(t * 2.0 + i) * 0.03
		pts.append(c + Vector2(cos(a), sin(a) * 0.95) * rr * s)
	ci.draw_colored_polygon(pts, fur)
	_ellipse(ci, c, 0.6 * s, 0.58 * s, fur.lightened(0.08))
	# Pençeler
	for side in [-1, 1]:
		for k in 3:
			var base := c + Vector2(side * (0.55 + k * 0.08), 0.45 + k * 0.08) * s
			_poly(ci, base, s, [[-0.03, 0], [0.03, 0], [side * 0.12, 0.28]], Color("#d9d2c0"))
	# Gözler (ara sıra kırpar)
	var blink := 0.15 if fmod(t, 3.2) < 0.12 else 1.0
	for side in [-1, 1]:
		var e := c + Vector2(side * 0.24, -0.12) * s
		ci.draw_circle(e, 0.2 * s, Color(1.0, 0.85, 0.2, 0.18))
		_ellipse(ci, e, 0.13 * s, 0.1 * s * blink, Color("#ffd23f"))
		_ellipse(ci, e, 0.03 * s, 0.08 * s * blink, Color("#1a0d00"))
	# Sivri dişli sırıtış
	var grin := PackedVector2Array()
	for i in 9:
		var x := -0.3 + i * 0.075
		grin.append(c + Vector2(x, 0.2 + (0.0 if i % 2 == 0 else 0.1) + 0.12 * (1.0 - pow(x / 0.3, 2))) * s)
	ci.draw_polyline(grin, Color("#e8e1d0"), 0.04 * s, true)


## Zümrüdüanka: açık kanatlı zümrüt kuş, uzun alev tüyleri.
static func _zumruduanka(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var em := Color("#19c39a")
	var flap := sin(t * 2.4) * 0.08
	# Kuyruk alevleri
	for k in 3:
		var x := (k - 1) * 0.18
		_poly(ci, c, s, [[x - 0.08, 0.3], [x + 0.08, 0.3], [x * 1.8, 1.0 + 0.06 * sin(t * 4.0 + k)]],
			Color("#ff9f1c") if k == 1 else Color("#ffd166"))
	# Kanatlar
	for side in [-1, 1]:
		var sd := float(side)
		_poly(ci, c, s, [[0.1 * sd, -0.1], [0.98 * sd, -0.62 - flap], [0.86 * sd, -0.3 - flap],
			[0.98 * sd, -0.18 - flap], [0.78 * sd, 0.02], [0.84 * sd, 0.12], [0.2 * sd, 0.22]], em.darkened(0.2))
		_poly(ci, c, s, [[0.14 * sd, -0.06], [0.8 * sd, -0.5 - flap], [0.6 * sd, 0.05], [0.2 * sd, 0.16]], em)
	# Gövde ve baş
	_ellipse(ci, c + Vector2(0, 0.06) * s, 0.24 * s, 0.38 * s, em.lightened(0.15))
	var head := c + Vector2(0, -0.42) * s
	ci.draw_circle(head, 0.17 * s, em.lightened(0.25))
	_poly(ci, head, s, [[-0.05, 0.02], [0.05, 0.02], [0, 0.16]], Color("#f2c94c"))
	ci.draw_circle(head + Vector2(-0.07, -0.03) * s, 0.035 * s, Color("#102a22"))
	ci.draw_circle(head + Vector2(0.07, -0.03) * s, 0.035 * s, Color("#102a22"))
	# Tepelik
	for k in 3:
		var a := -PI / 2 + (k - 1) * 0.4
		ci.draw_line(head + Vector2(cos(a), sin(a)) * 0.14 * s, head + Vector2(cos(a), sin(a)) * 0.34 * s, Color("#ffd166"), 0.05 * s, true)


## Ejderha: boynuzlu kırmızı baş, yarık göz, burun deliklerinden duman, arkada kanat.
static func _ejderha(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var red := Color("#d8402f")
	# Arka kanatlar
	for side in [-1, 1]:
		var sd := float(side)
		_poly(ci, c, s, [[0.3 * sd, -0.2], [1.0 * sd, -0.9], [0.95 * sd, -0.4], [0.75 * sd, -0.5], [0.7 * sd, -0.1], [0.5 * sd, -0.2], [0.45 * sd, 0.1]], red.darkened(0.45))
	# Boynuzlar
	for side in [-1, 1]:
		var sd := float(side)
		_poly(ci, c, s, [[0.22 * sd, -0.5], [0.36 * sd, -0.52], [0.5 * sd, -1.0]], Color("#f0e2c0"))
	# Kafa ve burun
	_ellipse(ci, c + Vector2(0, -0.12) * s, 0.5 * s, 0.46 * s, red)
	_poly(ci, c, s, [[-0.36, 0.05], [0.36, 0.05], [0.26, 0.62], [-0.26, 0.62]], red.lightened(0.06))
	_ellipse(ci, c + Vector2(0, 0.6) * s, 0.26 * s, 0.1 * s, red.lightened(0.06))
	ci.draw_line(c + Vector2(-0.24, 0.5) * s, c + Vector2(0.24, 0.5) * s, Color("#4a0f0a"), 0.03 * s, true)
	for k in 4:
		_poly(ci, c, s, [[-0.17 + k * 0.11, 0.33], [-0.11 + k * 0.11, 0.33], [-0.14 + k * 0.11, 0.38]], red.darkened(0.3))
	# Burun delikleri ve duman
	for side in [-1, 1]:
		var n := c + Vector2(side * 0.1, 0.22) * s
		ci.draw_circle(n, 0.04 * s, Color("#4a0f0a"))
		var k := fmod(t * 0.8 + (0.5 if side > 0 else 0.0), 1.0)
		ci.draw_circle(n + Vector2(side * 0.1, -0.2 - k * 0.4) * s, (0.05 + k * 0.08) * s, Color(0.8, 0.8, 0.8, 0.45 * (1.0 - k)))
	# Gözler
	for side in [-1, 1]:
		var e := c + Vector2(side * 0.22, -0.12) * s
		_ellipse(ci, e, 0.13 * s, 0.09 * s, Color("#ffd23f"), side * -0.3)
		_ellipse(ci, e, 0.025 * s, 0.08 * s, Color("#1a0500"))
	# Kaş sırtı
	_poly(ci, c, s, [[-0.42, -0.3], [-0.08, -0.2], [-0.1, -0.28]], red.darkened(0.4))
	_poly(ci, c, s, [[0.42, -0.3], [0.08, -0.2], [0.1, -0.28]], red.darkened(0.4))
	# Dişler
	for side in [-1, 1]:
		_poly(ci, c, s, [[side * 0.14, 0.5], [side * 0.21, 0.5], [side * 0.17, 0.62]], Color("#fff8ec"))


## Albastı: dalgalanan kızıl saçlar, kemik beyazı yüz, parlayan beyaz gözler.
static func _albasti(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var hair := Color("#c62848")
	# Saç: yüzün arkasında dalgalanan uzun tutamlar
	for k in 9:
		var a := lerpf(-2.6, -0.54, k / 8.0)
		var sway := sin(t * 2.0 + k) * 0.08
		var root := c + Vector2(cos(a), sin(a)) * 0.4 * s
		var tip := c + Vector2(cos(a) * 0.9 + sway, 0.95 + absf(cos(a)) * 0.1) * s
		_poly(ci, Vector2.ZERO, 1.0, [[root.x - 0.1 * s, root.y], [root.x + 0.1 * s, root.y], [tip.x, tip.y]], hair.darkened(0.15 * (k % 2)))
	_ellipse(ci, c + Vector2(0, -0.05) * s, 0.62 * s, 0.6 * s, hair)
	# Yüz
	_ellipse(ci, c + Vector2(0, 0.08) * s, 0.36 * s, 0.46 * s, Color("#e9e4dc"))
	_ellipse(ci, c + Vector2(0, 0.35) * s, 0.2 * s, 0.14 * s, Color("#d9d2c6"))
	# Perçem
	_poly(ci, c, s, [[-0.38, -0.24], [0.38, -0.24], [0.3, -0.5], [-0.3, -0.5]], hair)
	_poly(ci, c, s, [[-0.36, -0.26], [-0.1, -0.26], [-0.26, -0.06]], hair.darkened(0.1))
	_poly(ci, c, s, [[0.36, -0.26], [0.1, -0.26], [0.26, -0.06]], hair.darkened(0.1))
	# Parlayan gözler
	var glow := 0.6 + 0.4 * sin(t * 3.0)
	for side in [-1, 1]:
		var e := c + Vector2(side * 0.14, 0.07) * s
		ci.draw_circle(e, 0.09 * s, Color(1, 1, 1, 0.25 * glow))
		_ellipse(ci, e, 0.07 * s, 0.045 * s, Color("#ffffff"))
	# Uzun ince burun ve sinsi gülüş
	ci.draw_line(c + Vector2(0, 0.06) * s, c + Vector2(0.02, 0.22) * s, Color("#b8afa3"), 0.03 * s, true)
	ci.draw_arc(c + Vector2(0.02, 0.28) * s, 0.12 * s, 0.4, PI - 0.9, 10, Color("#7a1f2e"), 0.035 * s, true)


## Yelbegen: kalın gövdeden çıkan yedi uzun boyunlu baş.
static func _yelbegen(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var skin := Color("#7a9a3c")
	_ellipse(ci, c + Vector2(0, 0.62) * s, 0.62 * s, 0.32 * s, skin.darkened(0.3))
	_ellipse(ci, c + Vector2(0, 0.56) * s, 0.58 * s, 0.3 * s, skin)
	for k in 7:
		var a := lerpf(-PI * 0.92, -PI * 0.08, k / 6.0)
		var len := 0.8 if k == 3 else (0.66 if k % 2 == 0 else 0.74)
		var sway := sin(t * 2.2 + k * 0.9) * 0.05
		var base := c + Vector2(cos(a) * 0.25, 0.5 + sin(a) * 0.1) * s
		var head := c + Vector2(cos(a) * len + sway, 0.5 + sin(a) * len) * s
		ci.draw_line(base, head, skin.darkened(0.15), 0.12 * s, true)
		var hr := (0.19 if k == 3 else 0.15) * s
		ci.draw_circle(head, hr, skin.lightened(0.08))
		ci.draw_circle(head + Vector2(0.04 * s, -0.03 * s), hr * 0.32, Color("#ffd23f"))
		ci.draw_circle(head + Vector2(0.05 * s, -0.03 * s), hr * 0.14, Color("#1a1205"))
		_poly(ci, head, s, [[-0.04, 0.06], [0.06, 0.06], [0.01, 0.1]], Color("#f0e2c0"))


## Erlik Han: dikenli kara taç, boynuzlar, uzun sakal, kızıl gözler.
static func _erlik(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var dark := Color("#2b2d5c")
	# Boynuzlar
	for side in [-1, 1]:
		var sd := float(side)
		_poly(ci, c, s, [[0.2 * sd, -0.4], [0.44 * sd, -0.22], [0.86 * sd, -0.95]], Color("#cfc6b0"))
	# Sakal
	_poly(ci, c, s, [[-0.42, 0.1], [0.42, 0.1], [0.3, 0.7], [0.0, 0.98], [-0.3, 0.7]], Color("#46407a"))
	# Yüz
	_ellipse(ci, c + Vector2(0, -0.02) * s, 0.42 * s, 0.46 * s, Color("#5d62c4"))
	_ellipse(ci, c + Vector2(-0.14, -0.18) * s, 0.14 * s, 0.1 * s, Color(1, 1, 1, 0.1))
	# Taç
	_poly(ci, c, s, [[-0.42, -0.3], [-0.42, -0.62], [-0.28, -0.44], [-0.14, -0.72], [0, -0.48], [0.14, -0.72], [0.28, -0.44], [0.42, -0.62], [0.42, -0.3]], dark)
	for x in [-0.28, 0.0, 0.28]:
		ci.draw_circle(c + Vector2(x, -0.38) * s, 0.045 * s, Color("#e53935"))
	# Kızıl gözler
	var glow := 0.7 + 0.3 * sin(t * 4.0)
	for side in [-1, 1]:
		var e := c + Vector2(side * 0.16, -0.06) * s
		ci.draw_circle(e, 0.11 * s, Color(1, 0.1, 0.1, 0.25 * glow))
		_poly(ci, e, s, [[-0.09, -0.02 * side], [0.09, 0.02 * side], [0.0, 0.05]], Color("#ff3b30"))
	# Kaşlar
	_poly(ci, c, s, [[-0.32, -0.2], [-0.06, -0.12], [-0.08, -0.2]], dark)
	_poly(ci, c, s, [[0.32, -0.2], [0.06, -0.12], [0.08, -0.2]], dark)
	# Bıyık
	ci.draw_arc(c + Vector2(-0.12, 0.2) * s, 0.12 * s, PI * 1.1, PI * 1.9, 10, Color("#1b1b2f"), 0.05 * s, true)
	ci.draw_arc(c + Vector2(0.12, 0.2) * s, 0.12 * s, PI * 1.1, PI * 1.9, 10, Color("#1b1b2f"), 0.05 * s, true)


## Efsane kartında kullanılan büyük portre.
class Portrait extends Control:
	var kind := ""

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.42
		var col := BossArt.color(kind)
		for k in 4:
			var g := col
			g.a = 0.10 - k * 0.02
			draw_circle(c, r * (1.15 + k * 0.12), g)
		draw_circle(c, r * 1.08, Color(0, 0, 0, 0.35))
		BossArt.draw(self, kind, c, r * 0.95, Time.get_ticks_msec() / 1000.0)
