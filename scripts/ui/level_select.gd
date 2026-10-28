extends Control
## 50 bölüm, 10'arlı zorluk bantları halinde. Her 10. bölüm boss.

const COLUMNS := 5
const BOSS_COLOR := Color("#8e2f3c")


func _ready() -> void:
	var box := UIKit.screen(self, "Bölümler")
	var total := UIKit.label("Toplam yıldız: %d / %d" % [SaveData.total_stars(), GameConfig.MAX_LEVEL * 3], 28, UIKit.ACCENT)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(total)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	var focus: Control = null
	for band in GameConfig.BAND_NAMES.size():
		var first := band * 10 + 1
		list.add_child(UIKit.label("%d–%d  ·  %s" % [first, first + 9, GameConfig.BAND_NAMES[band]], 26, UIKit.MUTED))
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		list.add_child(grid)
		for n in range(first, first + 10):
			var cell := _level_cell(n)
			grid.add_child(cell)
			if n == SaveData.unlocked_level:
				focus = cell

	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu"), 84))
	if focus:
		_scroll_to(scroll, focus)


func _scroll_to(scroll: ScrollContainer, target: Control) -> void:
	# Yerleşim bitsin diye iki kare bekle.
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(maxf(0.0, target.get_global_rect().position.y - scroll.get_global_rect().position.y - 200.0) + scroll.scroll_vertical)


func _level_cell(n: int) -> Control:
	var level := n
	var boss := GameConfig.is_boss(n)
	var b := UIKit.button(str(n), func():
		Session.mode = "solo"
		Session.level = level
		Session.go("game"), 118)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = n > SaveData.unlocked_level
	b.add_theme_font_size_override("font_size", 32)
	if boss:
		b.add_theme_stylebox_override("normal", UIKit.box(BOSS_COLOR))
		b.add_theme_stylebox_override("hover", UIKit.box(BOSS_COLOR.lightened(0.15)))
		b.add_theme_stylebox_override("pressed", UIKit.box(BOSS_COLOR.darkened(0.2)))
		b.add_theme_stylebox_override("disabled", UIKit.box(BOSS_COLOR.darkened(0.55)))
		var tag := UIKit.label("BOSS", 18, Color(1, 0.85, 0.85, 0.9))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.set_anchors_preset(Control.PRESET_TOP_WIDE)
		tag.offset_top = 4
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tag)
	if n <= SaveData.unlocked_level:
		var sr := StarRow.new()
		sr.count = SaveData.best_stars(n)
		sr.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		sr.offset_top = -30
		sr.offset_bottom = -8
		sr.offset_left = 14
		sr.offset_right = -14
		b.add_child(sr)
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")
