class_name IconPreview
extends Control
## Renkli daire + ikon çizen, tıklanabilir küçük kontrol (ayarlar ekranı için).

signal pressed

var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()
var icon := 0:
	set(v):
		icon = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 8.0
	if selected:
		draw_arc(c, r + 5.0, 0.0, TAU, 48, UIKit.ACCENT, 5.0, true)
	draw_circle(c, r, color)
	if icon >= 0:
		IconDraw.draw_icon(self, icon, c, r * 0.55, Color(1, 1, 1, 0.92))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		pressed.emit()
		accept_event()
