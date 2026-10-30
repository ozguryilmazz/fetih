extends Control
## Oyuncu adı, renk ve ikon seçimi. Değişiklikler anında kaydedilir.

var _preview: IconPreview
var _color_buttons: Array = []
var _icon_buttons: Array = []


func _ready() -> void:
	var box := UIKit.screen(self, "Ayarlar")

	_preview = IconPreview.new()
	_preview.custom_minimum_size = Vector2(0, 100)
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
		c.custom_minimum_size = Vector2(0, 84)
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
		c.custom_minimum_size = Vector2(0, 88)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.icon = i
		c.pressed.connect(func():
			SaveData.icon_index = idx
			SaveData.save()
			_refresh())
		icons.add_child(c)
		_icon_buttons.append(c)

	var vib := UIKit.button("", func(): pass, 80)
	vib.text = _vib_text()
	vib.pressed.connect(func():
		SaveData.vibration = not SaveData.vibration
		SaveData.save()
		vib.text = _vib_text()
		if SaveData.vibration and OS.has_feature("mobile"):
			Input.vibrate_handheld(40, 0.6))
	vib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	row.add_child(vib)
	var upd := UIKit.button("Güncelleme", _check_update, 80)
	upd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(upd)

	box.add_child(UIKit.spacer())
	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu"), 84))
	_refresh()


func _vib_text() -> String:
	return "Titreşim: Açık" if SaveData.vibration else "Titreşim: Kapalı"


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
		if _popup:
			_close_popup()
		else:
			Session.go("main_menu")


# ---------------------------------------------------------------- güncelleme

var _popup: Control
var _popup_box: VBoxContainer


func _check_update() -> void:
	_open_popup()
	_popup_box.add_child(_center_label("Güncellemeler kontrol ediliyor...", 30, UIKit.TEXT))
	_popup_box.add_child(_center_label("Bu sürüm: %s" % UpdateChecker.current_name(), 24, UIKit.MUTED))
	var u := UpdateChecker.new()
	add_child(u)
	u.finished.connect(func(r: Dictionary):
		u.queue_free()
		_show_update_result(r))
	u.check()


func _show_update_result(r: Dictionary) -> void:
	if not _popup:
		return
	for c in _popup_box.get_children():
		c.queue_free()
	if not r.get("ok", false):
		_popup_box.add_child(_center_label("Kontrol edilemedi", 38, UIKit.TEXT))
		_popup_box.add_child(_center_label(String(r.get("error", "")), 26, Color("#e57373")))
		_popup_box.add_child(UIKit.button("Tekrar Dene", _check_update, 84))
	elif r["newer"]:
		_popup_box.add_child(_center_label("Yeni sürüm var!", 40, UIKit.ACCENT))
		_popup_box.add_child(_center_label("%s  →  %s" % [r["current"], r["latest"]], 30, UIKit.TEXT))
		var notes: Array = r.get("notes", [])
		if not notes.is_empty():
			_popup_box.add_child(UIKit.label("Bu sürümde:", 24, UIKit.MUTED))
			for n in notes.slice(0, 6):
				_popup_box.add_child(UIKit.label("• " + String(n), 22, UIKit.TEXT))
		_popup_box.add_child(UIKit.label("İndirme bitince bildirime dokun ve \"Güncelle\"yi seç. İlerlemen silinmez.", 22, UIKit.MUTED))
		var apk: String = r["apk"]
		_popup_box.add_child(UIKit.button("İndir ve Kur", func(): OS.shell_open(apk), 96))
	else:
		_popup_box.add_child(_center_label("Oyun güncel", 40, Color("#8be28b")))
		_popup_box.add_child(_center_label("Sürüm %s" % r["current"], 28, UIKit.TEXT))
	_popup_box.add_child(UIKit.button("Kapat", _close_popup, 80))


func _center_label(t: String, size: int, col: Color) -> Label:
	var l := UIKit.label(t, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _open_popup() -> void:
	_close_popup()
	_popup = Control.new()
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_popup)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	_popup_box = VBoxContainer.new()
	_popup_box.add_theme_constant_override("separation", 16)
	panel.add_child(_popup_box)


func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null
