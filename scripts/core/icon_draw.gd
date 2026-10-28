class_name IconDraw
extends RefCounted
## Geçici oyuncu ikonları (basit şekiller). Gerçek ikonlar gelince
## burası doku (texture) çizen bir fonksiyonla değiştirilecek.


static func draw_icon(ci: CanvasItem, index: int, c: Vector2, r: float, col: Color) -> void:
	match index % GameConfig.ICON_NAMES.size():
		0:
			ci.draw_circle(c, r * 0.8, col)
		1:
			ci.draw_colored_polygon(_star(c, r, r * 0.45, 5), col)
		2:
			ci.draw_colored_polygon(_regular(c, r, 3, -PI / 2), col)
		3:
			ci.draw_colored_polygon(_regular(c, r, 4, PI / 4), col)
		4:
			ci.draw_colored_polygon(_regular(c, r, 4, 0.0), col)
		5:
			ci.draw_colored_polygon(_regular(c, r, 6, 0.0), col)


static func _regular(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := rot + TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _star(c: Vector2, r_out: float, r_in: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := -PI / 2 + PI * i / n
		var r := r_out if i % 2 == 0 else r_in
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	return _star(c, r, r * 0.45, 5)
