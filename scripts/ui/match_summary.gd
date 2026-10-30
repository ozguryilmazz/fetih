class_name MatchSummary
extends Control
## Maç sonu özeti: oyuncuların üs sayısının zamana göre çizgi grafiği.
## history: [[zaman, [oyuncu0 üs, oyuncu1 üs, ...]], ...]

var history: Array = []
var colors: Array = []
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var pad_l := 40.0
	var pad_b := 30.0
	var area := Rect2(pad_l, 8.0, size.x - pad_l - 8.0, size.y - pad_b - 8.0)
	draw_rect(area, Color(1, 1, 1, 0.04))
	if history.size() < 2:
		return
	var t_max: float = maxf(1.0, history[-1][0])
	var c_max := 1
	for h in history:
		for v in h[1]:
			c_max = maxi(c_max, int(v))
	# Yatay kılavuz çizgileri
	var step := maxi(1, int(ceil(c_max / 4.0)))
	var v := 0
	while v <= c_max:
		var y := area.end.y - area.size.y * v / float(c_max)
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.08), 1.0)
		_text(str(v), Vector2(area.position.x - 8, y), 18, HORIZONTAL_ALIGNMENT_RIGHT)
		v += step
	_text("0:00", Vector2(area.position.x, area.end.y + 16), 18, HORIZONTAL_ALIGNMENT_LEFT)
	_text(_fmt(t_max), Vector2(area.end.x, area.end.y + 16), 18, HORIZONTAL_ALIGNMENT_RIGHT)
	var players: int = history[0][1].size()
	for p in players:
		var pts := PackedVector2Array()
		for h in history:
			var cnt := int(h[1][p]) if p < h[1].size() else 0
			pts.append(Vector2(area.position.x + area.size.x * h[0] / t_max,
				area.end.y - area.size.y * cnt / float(c_max)))
		var col: Color = colors[p] if p < colors.size() else Color.WHITE
		var shadow := Color(0, 0, 0, 0.35)
		draw_polyline(pts, shadow, 6.0, true)
		draw_polyline(pts, col.lightened(0.15), 4.0, true)
		draw_circle(pts[-1], 6.0, col.lightened(0.15))


func _text(t: String, at: Vector2, fs: int, align: int) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	draw_string(_font, Vector2(x, at.y + fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.5))


static func _fmt(sec: float) -> String:
	var t := int(sec)
	@warning_ignore("integer_division")
	return "%d:%02d" % [t / 60, t % 60]
