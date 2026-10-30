extends Control
## Çok oyunculu: oda kur (4 haneli kod) veya koda katıl, lobide bekle, başlat.

var _menu: VBoxContainer
var _lobby: VBoxContainer
var _status: Label
var _code_edit: LineEdit
var _code_label: Label
var _timer_label: Label
var _players_box: VBoxContainer
var _start_btn: Button
var _wait_label: Label
var _lobby_started := 0
var _loading: LoadingPanel
var _pending_code := ""


func _ready() -> void:
	var box := UIKit.screen(self, "Çok Oyunculu")

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 22)
	_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_menu)
	_lobby = VBoxContainer.new()
	_lobby.add_theme_constant_override("separation", 18)
	_lobby.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby.visible = false
	box.add_child(_lobby)

	_status = UIKit.label("", 26, UIKit.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	box.add_child(UIKit.button("Geri", _back, 84))

	_build_menu()
	_build_lobby()

	# Adlandırılmış metotlara bağlanır: ekran kapanınca Godot bağlantıları kendisi koparır.
	Net.status.connect(_on_status)
	Net.failed.connect(_on_failed)
	Net.room_ready.connect(_on_room_ready)
	Net.lobby_changed.connect(_on_lobby)
	Net.match_started.connect(_on_match_started)

	if not Net.available():
		_status.text = "Çok oyunculu henüz ayarlanmadı (Firebase bilgileri eksik)."
		_status.add_theme_color_override("font_color", Color("#e57373"))
		for c in _menu.get_children():
			if c is Button:
				c.disabled = true


func _build_menu() -> void:
	_menu.add_child(UIKit.label("Oda kur, çıkan 4 haneli kodu arkadaşına ver. En fazla 3 oyuncu. Kod 5 dakika geçerli.", 26, UIKit.MUTED))
	_menu.add_child(UIKit.button("Oda Kur", func():
		_status.add_theme_color_override("font_color", UIKit.MUTED)
		_begin_loading("Oda kuruluyor")
		Net.create_room(), 110))

	_menu.add_child(UIKit.label("Arkadaşının odasına katıl:", 26, UIKit.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_menu.add_child(row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "0000"
	_code_edit.max_length = 4
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_code_edit.add_theme_font_size_override("font_size", 48)
	_code_edit.custom_minimum_size = Vector2(0, 100)
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_changed.connect(_on_code_changed)
	_code_edit.text_submitted.connect(func(_t): _join())
	row.add_child(_code_edit)
	var join := UIKit.button("Katıl", _join, 100)
	join.custom_minimum_size.x = 200
	row.add_child(join)
	_menu.add_child(UIKit.label("Çok oyunculu maçlarda mağaza güçlendirmeleri geçerli değildir. Bir oyuncunun bağlantısı koparsa maç herkes için biter.", 22, UIKit.MUTED))


func _build_lobby() -> void:
	_lobby.add_child(UIKit.label("Oda kodu", 28, UIKit.MUTED))
	_code_label = UIKit.label("", 120, UIKit.ACCENT)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby.add_child(_code_label)
	_timer_label = UIKit.label("", 24, UIKit.MUTED)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby.add_child(_timer_label)

	var panel := PanelContainer.new()
	_lobby.add_child(panel)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 12)
	panel.add_child(_players_box)

	_wait_label = UIKit.label("", 26, UIKit.MUTED)
	_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby.add_child(_wait_label)
	_start_btn = UIKit.button("Başlat", _start, 110)
	_lobby.add_child(_start_btn)


func _process(_delta: float) -> void:
	if _lobby.visible and Net.is_host:
		var left := int((NetConfig.room_ttl_ms() - (Time.get_ticks_msec() - _lobby_started)) / 1000.0)
		@warning_ignore("integer_division")
		_timer_label.text = "Kodun geçerliliği: %d:%02d" % [maxi(left, 0) / 60, maxi(left, 0) % 60]


func _on_status(t: String) -> void:
	_status.text = "" if _loading else t
	# Gerçek adımlar çubuğun ilerleyebileceği sınırı belirler.
	if _loading:
		if t.begins_with("Sunucuya"):
			_loading.set_target(0.35)
		elif t != "":
			_loading.set_target(0.75)


func _begin_loading(title: String) -> void:
	if _loading:
		_loading.cancel()
	_loading = LoadingPanel.show_over(self, title)
	_loading.set_target(0.2)


func _on_match_started(_setup: Dictionary, _slot: int) -> void:
	Session.mode = "online"
	Session.go.call_deferred("game")


func _on_code_changed(t: String) -> void:
	var digits := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != t:
		_code_edit.text = digits
		_code_edit.caret_column = digits.length()


func _join() -> void:
	_status.add_theme_color_override("font_color", UIKit.MUTED)
	if _code_edit.text.length() == 4:
		_begin_loading("Odaya bağlanılıyor")
	Net.join_room(_code_edit.text)


func _on_failed(msg: String) -> void:
	if _loading:
		_loading.cancel()
		_loading = null
	_status.text = msg
	_status.add_theme_color_override("font_color", Color("#e57373"))
	_menu.visible = true
	_lobby.visible = false


func _on_room_ready(code: String) -> void:
	# Yükleme çubuğu dolup kapandıktan sonra lobi açılır.
	if _loading:
		_pending_code = code
		_loading.done.connect(_on_loading_done, CONNECT_ONE_SHOT)
		_loading.finish()
		return
	_show_lobby(code)


func _on_loading_done() -> void:
	_loading = null
	_show_lobby(_pending_code)


func _show_lobby(code: String) -> void:
	_menu.visible = false
	_lobby.visible = true
	_lobby_started = Time.get_ticks_msec()
	_code_label.text = code
	_timer_label.text = "" if Net.is_host else "Oda sahibinin başlatması bekleniyor..."
	_start_btn.visible = Net.is_host
	_on_lobby(Net.lobby_players())


func _on_lobby(players: Array) -> void:
	for c in _players_box.get_children():
		c.queue_free()
	for p in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var dot := IconPreview.new()
		dot.custom_minimum_size = Vector2(56, 56)
		dot.color = GameConfig.color(int(p.get("color", 0)))
		dot.icon = int(p.get("icon", 0))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
		var name_l := UIKit.label(String(p.get("name", "Oyuncu")) + ("  (oda sahibi)" if p.get("host", false) else ""), 30)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_l)
		_players_box.add_child(row)
	for i in range(players.size(), NetConfig.MAX_PLAYERS):
		_players_box.add_child(UIKit.label("  Boş yer...", 26, Color(1, 1, 1, 0.3)))
	var enough := players.size() >= 2
	_start_btn.disabled = not enough
	if Net.is_host:
		_wait_label.text = "Arkadaşının katılması bekleniyor..." if not enough else "Hazır! Başlatabilirsin."


## Host: lobideki oyuncularla haritayı kurar ve maçı başlatır.
func _start() -> void:
	var lp: Array = Net.lobby_players()
	if lp.size() < 2:
		return
	var used: Array = []
	var players: Array = []
	for i in lp.size():
		var col := int(lp[i].get("color", 0))
		if used.has(col):
			col = 0
			while used.has(col):
				col += 1
		used.append(col)
		players.append(MatchState.make_player(i, String(lp[i].get("name", "Oyuncu")), col, int(lp[i].get("icon", 0)), false, {}))
	var bases := 8 + 3 * lp.size()
	var st := MatchState.create(randi(), players, bases, 6, 16)
	Net.start_match(st, lp.map(func(p): return p["uid"]))


func _back() -> void:
	if Net.in_room:
		Net.leave()
		_menu.visible = true
		_lobby.visible = false
		_status.text = ""
	else:
		Session.go("main_menu")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
