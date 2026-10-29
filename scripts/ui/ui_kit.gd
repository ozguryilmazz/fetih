class_name UIKit
extends RefCounted
## Tüm ekranlarda ortak kullanılan renkler, tema ve küçük arayüz parçaları.

const BG := Color("#151a33")
const PANEL := Color("#232a52")
const ACCENT := Color("#f5a623")
const TEXT := Color("#ecf0f1")
const MUTED := Color("#8e96c4")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	t.set_stylebox("normal", "Button", box(Color("#3a4386")))
	t.set_stylebox("hover", "Button", box(Color("#4a55a8")))
	t.set_stylebox("pressed", "Button", box(Color("#2b3266")))
	t.set_stylebox("disabled", "Button", box(Color("#262b4d")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_stylebox("normal", "LineEdit", box(Color("#0f1329"), 14))
	t.set_stylebox("focus", "LineEdit", box(Color("#0f1329"), 14, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 26))
	return t


static func box(c: Color, radius := 18, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	if border.a > 0.0:
		sb.set_border_width_all(4)
		sb.border_color = border
	return sb


## Ekranın arka planını, kenar boşluklarını ve başlığı kurar; içerik kutusunu döndürür.
static func screen(root: Control, title: String) -> VBoxContainer:
	root.theme = make_theme()
	var bg := TextureRect.new()
	bg.texture = Art.ground()
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var vig := TextureRect.new()
	vig.texture = Art.vignette()
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 90)
	margin.add_theme_constant_override("margin_bottom", 60)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	margin.add_child(vbox)
	if title != "":
		var l := label(title, 54)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(l)
	return vbox


static func label(text: String, size := 30, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, on_press: Callable, height := 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.pressed.connect(on_press)
	return b


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func gold_text(amount: int) -> String:
	return "Altın: %d" % amount
