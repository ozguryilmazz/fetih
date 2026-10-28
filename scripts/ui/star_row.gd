class_name StarRow
extends Control
## Yan yana 3 yıldız çizer; `count` kadarı dolu (altın rengi).

var count := 0:
	set(v):
		count = v
		queue_redraw()
var total := 3
var empty_color := Color(1, 1, 1, 0.16)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x / total
	var r := minf(w * 0.86, size.y) / 2.0
	for i in total:
		var c := Vector2(w * (i + 0.5), size.y / 2.0)
		draw_colored_polygon(IconDraw.star_points(c, r), UIKit.ACCENT if i < count else empty_color)
