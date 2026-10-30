class_name EmoteDraw
extends RefCounted
## Çok oyunculu ifadeler (emoji yazı tipi olmadığı için kodla çizilir).
## 0 gülme, 1 kızgın, 2 şaşkın, 3 ağlama, 4 kalp, 5 beyaz bayrak

const COUNT := 6
const NAMES := ["Gülme", "Kızgın", "Şaşkın", "Ağlama", "Kalp", "Teslim"]
const FACE := Color("#ffcf3f")
const DARK := Color("#4a2c0a")


static func draw(ci: CanvasItem, e: int, c: Vector2, s: float) -> void:
	match e:
		4:
			_heart(ci, c, s)
			return
		5:
			_flag(ci, c, s)
			return
	var face := FACE if e != 1 else Color("#ff7043")
	ci.draw_circle(c + Vector2(0, s * 0.06), s, face.darkened(0.25))
	ci.draw_circle(c, s, face)
	ci.draw_circle(c + Vector2(-s * 0.3, -s * 0.35), s * 0.25, Color(1, 1, 1, 0.25))
	var w := maxf(2.0, s * 0.12)
	match e:
		0:  # gülme: kapalı kavisli gözler, kocaman ağız
			ci.draw_arc(c + Vector2(-s * 0.35, -s * 0.15), s * 0.18, PI, TAU, 10, DARK, w, true)
			ci.draw_arc(c + Vector2(s * 0.35, -s * 0.15), s * 0.18, PI, TAU, 10, DARK, w, true)
			var m := PackedVector2Array()
			for i in 13:
				var a := PI * i / 12.0
				m.append(c + Vector2(cos(a) * s * 0.55, s * 0.1 + sin(a) * s * 0.5))
			ci.draw_colored_polygon(m, DARK)
			ci.draw_circle(c + Vector2(0, s * 0.45), s * 0.18, Color("#e85d5d"))
		1:  # kızgın: çatık kaş, düz ağız
			ci.draw_line(c + Vector2(-s * 0.6, -s * 0.45), c + Vector2(-s * 0.15, -s * 0.22), DARK, w * 1.3, true)
			ci.draw_line(c + Vector2(s * 0.6, -s * 0.45), c + Vector2(s * 0.15, -s * 0.22), DARK, w * 1.3, true)
			ci.draw_circle(c + Vector2(-s * 0.33, -s * 0.05), s * 0.11, DARK)
			ci.draw_circle(c + Vector2(s * 0.33, -s * 0.05), s * 0.11, DARK)
			ci.draw_arc(c + Vector2(0, s * 0.62), s * 0.32, PI * 1.2, PI * 1.8, 10, DARK, w, true)
		2:  # şaşkın: yuvarlak gözler, O ağız
			ci.draw_circle(c + Vector2(-s * 0.33, -s * 0.18), s * 0.2, Color.WHITE)
			ci.draw_circle(c + Vector2(s * 0.33, -s * 0.18), s * 0.2, Color.WHITE)
			ci.draw_circle(c + Vector2(-s * 0.33, -s * 0.18), s * 0.1, DARK)
			ci.draw_circle(c + Vector2(s * 0.33, -s * 0.18), s * 0.1, DARK)
			ci.draw_circle(c + Vector2(0, s * 0.42), s * 0.2, DARK)
		3:  # ağlama: gözyaşı, ters ağız
			ci.draw_arc(c + Vector2(-s * 0.35, -s * 0.2), s * 0.16, 0.0, PI, 10, DARK, w, true)
			ci.draw_arc(c + Vector2(s * 0.35, -s * 0.2), s * 0.16, 0.0, PI, 10, DARK, w, true)
			ci.draw_arc(c + Vector2(0, s * 0.62), s * 0.3, PI * 1.15, PI * 1.85, 10, DARK, w, true)
			for side in [-1, 1]:
				var t := c + Vector2(side * s * 0.45, s * 0.05)
				ci.draw_colored_polygon(PackedVector2Array([t + Vector2(0, -s * 0.12), t + Vector2(s * 0.1, s * 0.08), t + Vector2(-s * 0.1, s * 0.08)]), Color("#5ec8ff"))
				ci.draw_circle(t + Vector2(0, s * 0.1), s * 0.1, Color("#5ec8ff"))


static func _heart(ci: CanvasItem, c: Vector2, s: float) -> void:
	var col := Color("#ff4d6d")
	ci.draw_circle(c + Vector2(-s * 0.42, -s * 0.2), s * 0.48, col)
	ci.draw_circle(c + Vector2(s * 0.42, -s * 0.2), s * 0.48, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.88, -s * 0.05), c + Vector2(s * 0.88, -s * 0.05), c + Vector2(0, s * 0.9)]), col)
	ci.draw_circle(c + Vector2(-s * 0.5, -s * 0.38), s * 0.15, Color(1, 1, 1, 0.45))


static func _flag(ci: CanvasItem, c: Vector2, s: float) -> void:
	ci.draw_line(c + Vector2(-s * 0.55, -s * 0.9), c + Vector2(-s * 0.55, s * 0.95), Color("#8d6e63"), maxf(3.0, s * 0.14), true)
	var pts := PackedVector2Array()
	for i in 9:
		var x := -s * 0.5 + s * 1.3 * i / 8.0
		pts.append(c + Vector2(x, -s * 0.85 + sin(i * 0.9) * s * 0.08))
	for i in range(8, -1, -1):
		var x := -s * 0.5 + s * 1.3 * i / 8.0
		pts.append(c + Vector2(x, s * 0.05 + sin(i * 0.9) * s * 0.08))
	ci.draw_colored_polygon(pts, Color("#f5f5f5"))
	ci.draw_polyline(pts, Color(0, 0, 0, 0.25), 2.0, true)


## Dokunulabilir ifade düğmesi.
class EmoteButton extends Control:
	signal pressed
	var emote := 0
	var dim := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color(0.13, 0.16, 0.27, 0.92))
		draw_arc(c, r - 1.5, 0.0, TAU, 40, Color(1, 1, 1, 0.18), 3.0, true)
		EmoteDraw.draw(self, emote, c, r * 0.55)
		if dim:
			draw_circle(c, r, Color(0, 0, 0, 0.45))
