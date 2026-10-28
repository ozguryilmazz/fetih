extends Control
## Altınla güçlendirme satın alma ekranı.

var _gold_label: Label
var _rows: VBoxContainer


func _ready() -> void:
	var box := UIKit.screen(self, "Mağaza")
	_gold_label = UIKit.label("", 36, UIKit.ACCENT)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_gold_label)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 18)
	box.add_child(_rows)

	box.add_child(UIKit.spacer())
	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu")))
	_refresh()


func _refresh() -> void:
	_gold_label.text = UIKit.gold_text(SaveData.gold)
	for c in _rows.get_children():
		c.queue_free()

	for key in GameConfig.UPGRADE_ORDER:
		var up: Dictionary = GameConfig.UPGRADES[key]
		var level: int = SaveData.upgrades[key]
		var maxed := level >= int(up["max"])
		var cost := GameConfig.upgrade_cost(key, level)

		var panel := PanelContainer.new()
		_rows.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		panel.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UIKit.label("%s  (%d/%d)" % [up["name"], level, up["max"]], 32))
		info.add_child(UIKit.label(up["desc"], 24, UIKit.MUTED))

		var k: String = key
		var btn := UIKit.button("MAKS" if maxed else "%d altın" % cost, func():
			if SaveData.try_buy_upgrade(k):
				_refresh(), 90)
		btn.custom_minimum_size.x = 190
		btn.disabled = maxed or SaveData.gold < cost
		row.add_child(btn)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")
