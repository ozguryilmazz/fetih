extends Control
## Hakkında ekranı. Sürüm numarası her GitHub derlemesinde otomatik güncellenir.


func _ready() -> void:
	var box := UIKit.screen(self, "Hakkında")

	var logo := IconPreview.new()
	logo.custom_minimum_size = Vector2(0, 130)
	logo.color = GameConfig.color(SaveData.color_index)
	logo.icon = SaveData.icon_index
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(logo)

	var name_l := UIKit.label("FETİH", 64)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_l)

	var panel := PanelContainer.new()
	box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	_section(v, "Tasarımcı", ["Özgür Yılmaz Kılınç"])
	_section(v, "Hedef Kullanıcılar", ["Toprak Özgür Kılınç", "Ateş Ares Bayırlı"])
	_section(v, "Sürüm", [version_text()])

	box.add_child(UIKit.spacer())
	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu"), 84))


static func version_text() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.1.0"))


func _section(parent: VBoxContainer, title: String, lines: Array) -> void:
	parent.add_child(UIKit.label(title, 24, UIKit.MUTED))
	for line in lines:
		parent.add_child(UIKit.label(line, 32, UIKit.TEXT))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")
