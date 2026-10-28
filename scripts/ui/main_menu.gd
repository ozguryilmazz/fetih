extends Control


func _ready() -> void:
	var box := UIKit.screen(self, "")

	var preview := IconPreview.new()
	preview.custom_minimum_size = Vector2(0, 150)
	preview.color = GameConfig.color(SaveData.color_index)
	preview.icon = SaveData.icon_index
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(preview)

	var title := UIKit.label("FETİH", 92, UIKit.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var who := UIKit.label(SaveData.player_name, 32, UIKit.MUTED)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(who)

	var gold := UIKit.label(UIKit.gold_text(SaveData.gold), 34, UIKit.ACCENT)
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(gold)

	box.add_child(UIKit.spacer())
	box.add_child(UIKit.button("Solo Oyna  (Bölüm %d)" % SaveData.unlocked_level, func():
		Session.mode = "solo"
		Session.level = SaveData.unlocked_level
		Session.go("game"), 110))
	box.add_child(UIKit.button("Bölümler", func(): Session.go("level_select")))
	box.add_child(UIKit.button("Çok Oyunculu", func(): Session.go("multiplayer")))
	box.add_child(UIKit.button("Mağaza", func(): Session.go("shop")))
	box.add_child(UIKit.button("Ayarlar", func(): Session.go("settings")))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
