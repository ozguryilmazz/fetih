extends Control

var _gold_label: Label
var _daily_btn: Button
var _quest_btn: Button
var _popup: Control


func _ready() -> void:
	var box := UIKit.screen(self, "")

	var preview := IconPreview.new()
	preview.custom_minimum_size = Vector2(0, 90)
	preview.color = GameConfig.color(SaveData.color_index)
	preview.icon = SaveData.icon_index
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(preview)

	var title := UIKit.label("FETİH", 72, UIKit.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var who := UIKit.label(SaveData.player_name, 32, UIKit.MUTED)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(who)

	_gold_label = UIKit.label("", 34, UIKit.ACCENT)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_gold_label)

	box.add_child(UIKit.spacer())
	var level := SaveData.unlocked_level
	var play_text := "Solo Oyna  (Bölüm %d%s)" % [level, (" · " + GameConfig.BOSS_INFO[GameConfig.boss_kind(level)]["name"]) if GameConfig.is_boss(level) else ""]
	box.add_child(UIKit.button(play_text, func():
		Session.mode = "solo"
		Session.level = SaveData.unlocked_level
		Session.go("game"), 110))
	var surv_text := "Hayatta Kalma"
	if SaveData.survival_best > 0.0:
		var t := int(SaveData.survival_best)
		@warning_ignore("integer_division")
		surv_text += "  (en iyi %d:%02d)" % [t / 60, t % 60]
	box.add_child(UIKit.button(surv_text, func():
		Session.mode = "survival"
		Session.go("game")))
	box.add_child(UIKit.button("Bölümler", func(): Session.go("level_select")))
	_daily_btn = UIKit.button("", _open_daily)
	box.add_child(_daily_btn)
	_quest_btn = UIKit.button("", func(): Session.go("quests"))
	box.add_child(_quest_btn)
	box.add_child(UIKit.button("Mağaza", func(): Session.go("shop")))
	box.add_child(UIKit.button("Çok Oyunculu", func(): Session.go("multiplayer")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	for pair in [["Ayarlar", "settings"], ["Hakkında", "about"]]:
		var scene: String = pair[1]
		var b := UIKit.button(pair[0], func(): Session.go(scene), 74)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	# 7 düğme sığsın diye ikincil düğmeler biraz daha alçak.
	box.add_theme_constant_override("separation", 14)
	for c in box.get_children():
		if c is Button and c.custom_minimum_size.y < 100:
			c.custom_minimum_size.y = 74
	_refresh()

	if SaveData.can_claim_daily():
		_open_daily.call_deferred()


func _refresh() -> void:
	_gold_label.text = UIKit.gold_text(SaveData.gold)
	var q_ready := SaveData.quests_ready_total()
	_quest_btn.text = "Görevler  (+%d hazır!)" % q_ready if q_ready > 0 else "Görevler"
	if q_ready > 0:
		_quest_btn.add_theme_stylebox_override("normal", UIKit.box(Color("#3fae6a").darkened(0.3)))
		_quest_btn.add_theme_stylebox_override("hover", UIKit.box(Color("#3fae6a").darkened(0.15)))
	var ready_now := SaveData.can_claim_daily()
	_daily_btn.text = "Günlük Ödül  (hazır!)" if ready_now else "Günlük Ödül"
	if ready_now:
		_daily_btn.add_theme_stylebox_override("normal", UIKit.box(UIKit.ACCENT.darkened(0.35)))
		_daily_btn.add_theme_stylebox_override("hover", UIKit.box(UIKit.ACCENT.darkened(0.25)))
	else:
		_daily_btn.remove_theme_stylebox_override("normal")
		_daily_btn.remove_theme_stylebox_override("hover")


# ---------------------------------------------------------------- günlük ödül

func _open_daily() -> void:
	if _popup:
		return
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
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)

	var t := UIKit.label("Günlük Ödül", 48, UIKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var sub := UIKit.label("Her gün gel, ödül büyüsün. Bir gün kaçırırsan seri başa döner.", 24, UIKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var can := SaveData.can_claim_daily()
	# Bugün alınabilecek gün; alındıysa bugün alınmış olan gün.
	var today_day := SaveData.next_daily_day() if can else SaveData.daily_streak
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for i in GameConfig.DAILY_REWARDS.size():
		var day := i + 1
		var done := day < today_day or (day == today_day and not can)
		var is_today := day == today_day and can
		var bg := Color("#3a4386")
		if is_today:
			bg = UIKit.ACCENT.darkened(0.3)
		elif done:
			bg = Color("#1f6f4a")
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", UIKit.box(bg, 16))
		cell.custom_minimum_size = Vector2(0, 120)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(v)
		var d := UIKit.label("%d. gün" % day, 22, UIKit.TEXT)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(d)
		var g := UIKit.label(("Alındı" if done else "%d" % GameConfig.DAILY_REWARDS[i]), 28, UIKit.TEXT if done else UIKit.ACCENT)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(g)

	if can:
		var reward: int = GameConfig.DAILY_REWARDS[today_day - 1]
		col.add_child(UIKit.button("Al  (+%d altın)" % reward, func():
			SaveData.claim_daily()
			_close_daily(), 100))
	else:
		var l := UIKit.label("Bugünkü ödülünü aldın. Yarın tekrar gel!", 26, UIKit.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	col.add_child(UIKit.button("Kapat", _close_daily, 84))


func _close_daily() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _popup:
			_close_daily()
		else:
			get_tree().quit()
