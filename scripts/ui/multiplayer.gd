extends Control
## Çok oyunculu oda ekranı (arayüz iskeleti).
## Firebase bağlantısı bir sonraki adımda eklenecek: "Oda Kur" kodu
## veritabanında rezerve edecek, "Katıl" o odaya oyuncu olarak yazacak.

var _status: Label
var _code_label: Label
var _code_edit: LineEdit


func _ready() -> void:
	var box := UIKit.screen(self, "Çok Oyunculu")

	box.add_child(UIKit.label("Oda kur, 4 haneli kodu arkadaşına ver. En fazla 3 oyuncu.", 26, UIKit.MUTED))
	box.add_child(UIKit.button("Oda Kur", _create_room, 110))

	_code_label = UIKit.label("", 96, UIKit.ACCENT)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_code_label)

	box.add_child(UIKit.label("Arkadaşının odasına katıl:", 26, UIKit.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "0000"
	_code_edit.max_length = 4
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_code_edit.add_theme_font_size_override("font_size", 48)
	_code_edit.custom_minimum_size = Vector2(0, 100)
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_changed.connect(_on_code_changed)
	row.add_child(_code_edit)
	var join := UIKit.button("Katıl", _join_room, 100)
	join.custom_minimum_size.x = 200
	row.add_child(join)

	_status = UIKit.label("", 26, UIKit.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	box.add_child(UIKit.spacer())
	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu")))


func _on_code_changed(t: String) -> void:
	var digits := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != t:
		_code_edit.text = digits
		_code_edit.caret_column = digits.length()


func _create_room() -> void:
	_code_label.text = "%04d" % randi_range(0, 9999)
	_status.text = "Online bağlantı henüz eklenmedi (sıradaki adım: Firebase)."


func _join_room() -> void:
	if _code_edit.text.length() != 4:
		_status.text = "Kod 4 haneli olmalı."
		return
	_status.text = "Online bağlantı henüz eklenmedi (sıradaki adım: Firebase)."


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")
