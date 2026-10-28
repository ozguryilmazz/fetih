extends Control

const COLUMNS := 4


func _ready() -> void:
	var box := UIKit.screen(self, "Bölümler")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)

	# Açık bölümler + önündeki birkaç kilitli bölüm, 4'ün katına tamamlanmış.
	var shown := int(ceil((SaveData.unlocked_level + 8) / float(COLUMNS))) * COLUMNS
	for n in range(1, shown + 1):
		var level := n
		var b := UIKit.button(str(n), func():
			Session.mode = "solo"
			Session.level = level
			Session.go("game"), 120)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = n > SaveData.unlocked_level
		grid.add_child(b)

	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu")))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")
