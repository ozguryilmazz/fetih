extends Control
## Günlük görevler ekranı. Her gün gece yarısı sıfırlanır.

const DONE := Color("#3fae6a")

var _gold_label: Label
var _reset_label: Label
var _list: VBoxContainer
var _timer := 0.0


func _ready() -> void:
	var box := UIKit.screen(self, "Günlük Görevler")
	_gold_label = UIKit.label("", 30, UIKit.ACCENT)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_gold_label)
	_reset_label = UIKit.label("", 24, UIKit.MUTED)
	_reset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_reset_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 16)
	scroll.add_child(_list)

	box.add_child(UIKit.button("Geri", func(): Session.go("main_menu"), 84))
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_update_reset_label()


func _update_reset_label() -> void:
	var now := Time.get_datetime_dict_from_system()
	var left: int = 86400 - (int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"]))
	@warning_ignore("integer_division")
	_reset_label.text = "Görevler %d sa %02d dk sonra yenilenir" % [left / 3600, (left % 3600) / 60]
	# Gece yarısını geçtiysek ekranı yenile.
	if SaveData.quest_day != SaveData.today():
		_refresh()


func _refresh() -> void:
	_gold_label.text = UIKit.gold_text(SaveData.gold)
	_update_reset_label()
	for c in _list.get_children():
		c.queue_free()
	for q in GameConfig.QUESTS:
		_list.add_child(_quest_card(q))


func _quest_card(q: Dictionary) -> Control:
	var id: String = q["id"]
	var tiers: Array = q["tiers"]
	var value := SaveData.quest_value(id)
	var claimed := SaveData.quest_claimed_count(id)
	var ready := SaveData.quest_ready_gold(id)
	var all_done := claimed >= tiers.size()

	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	v.add_child(UIKit.label(q["name"], 30))
	v.add_child(UIKit.label(q["desc"], 20, UIKit.MUTED))

	# Çubuk: henüz ulaşılmamış ilk kademeye doğru ilerleme.
	var next_i := tiers.size() - 1
	for i in tiers.size():
		if value < tiers[i][0]:
			next_i = i
			break
	var target: int = tiers[next_i][0]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var bar := ProgressBar.new()
	bar.max_value = target
	bar.value = mini(value, target)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 26)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UIKit.box(Color("#0f1329"), 10))
	bar.add_theme_stylebox_override("fill", UIKit.box(DONE if value >= target else UIKit.ACCENT, 10))
	row.add_child(bar)
	var count := UIKit.label("%d / %d" % [value, target], 24)
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(count)

	# Kademe noktaları: alınan yeşil, hazır altın, kalan sönük.
	var dots := _TierDots.new()
	dots.total = tiers.size()
	dots.claimed = claimed
	var reached := 0
	for t in tiers:
		if value >= t[0]:
			reached += 1
	dots.reached = reached
	dots.custom_minimum_size = Vector2(0, 18)
	v.add_child(dots)

	if all_done:
		v.add_child(UIKit.label("Bugünkü tüm kademeler tamamlandı!", 24, DONE))
	elif ready > 0:
		var btn := UIKit.button("Al  (+%d altın)" % ready, func():
			SaveData.claim_quest(id)
			_refresh(), 84)
		btn.add_theme_stylebox_override("normal", UIKit.box(DONE.darkened(0.2)))
		btn.add_theme_stylebox_override("hover", UIKit.box(DONE))
		v.add_child(btn)
	else:
		v.add_child(UIKit.label("Sıradaki ödül: %d altın" % tiers[next_i][1], 24, UIKit.ACCENT))
	return panel


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Session.go("main_menu")


## Kademe göstergesi.
class _TierDots extends Control:
	var total := 1
	var claimed := 0
	var reached := 0

	func _draw() -> void:
		var gap := size.x / total
		var r := minf(gap * 0.3, size.y * 0.45)
		for i in total:
			var c := Vector2(gap * (i + 0.5), size.y / 2.0)
			var col := Color(1, 1, 1, 0.15)
			if i < claimed:
				col = DONE
			elif i < reached:
				col = UIKit.ACCENT
			draw_circle(c, r, col)
