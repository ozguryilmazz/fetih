extends Control
## Oyuncu adı, renk ve ikon seçimi. Değişiklikler anında kaydedilir.

var _preview: IconPreview
var _color_buttons: Array = []
var _icon_buttons: Array = []


func _ready() -> void:
	var box := UIKit.screen(self, "Ayarlar")

	_preview = IconPreview.new()
	_preview.custom_minimum_size = Vector2(0, 120)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_preview)

	box.add_child(UIKit.label("Oyuncu adı", 28, UIKit.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = SaveData.player_name
	name_edit.max_length = 14
	name_edit.custom_minimum_size = Vector2(0, 84)
	name_edit.text_changed.connect(func(t: String):
		var clean := t.strip_edges()
		SaveData.player_name = clean if clean != "" else "Oyuncu"
		SaveData.save())
	box.add_child(name_edit)

	box.add_child(UIKit.label("Renk", 28, UIKit.MUTED))
	var colors := GridContainer.new()
	colors.columns = 4
	colors.add_theme_constant_override("h_separation", 12)
	colors.add_theme_constant_override("v_separation", 12)
	box.add_child(colors)
	for i in GameConfig.PALETTE_HEX.size():
		var idx := i
		var c := IconPreview.new()
		c.custom_minimum_size = Vector2(0, 92)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.color = GameConfig.color(i)
		c.icon = -1
		c.pressed.connect(func():
			SaveData.color_index = idx
			SaveData.save()
			_refresh())
		colors.add_child(c)
		_color_buttons.append(c)

	box.add_child(UIKit.label("İkon", 28, UIKit.MUTED))
	var icons := GridContainer.new()
	icons.columns = 3
	icons.add_theme_constant_override("h_separation", 12)
	icons.add_theme_constant_override("v_separation", 12)
	box.add_child(icons)
	for i in GameConfig.ICON_NAMES.size():
		var idx := i
		var c := IconPreview.new()
		c.custom_minimum_size = Vector2(0, 100)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.icon = i
		c.pressed.connect(func():
			SaveData.icon_index = idx
			SaveData.save()
			_refresh())
		icons.add_child(c)
		_icon_buttons.append(c)

	box.add_child(UIKit.spacer())
	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu")))
	_refresh()


func _refresh() -> void:
	var col := GameConfig.color(SaveData.color_index)
	_preview.color = col
	_preview.icon = SaveData.icon_index
	for i in _color_buttons.size():
		_color_buttons[i].selected = i == SaveData.color_index
	for i in _icon_buttons.size():
		_icon_buttons[i].color = col.darkened(0.25)
		_icon_buttons[i].selected = i == SaveData.icon_index


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")
