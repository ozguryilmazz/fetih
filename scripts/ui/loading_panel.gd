class_name LoadingPanel
extends Control
## Ekranı kaplayan yükleme paneli: ilerleme çubuğu + altında dönen esprili yazılar.
## Çubuk gerçek adımlara bağlanır: set_target(0..1) ile bir sonraki adımın sınırı verilir,
## çubuk o sınıra yavaşça yaklaşır (aşmaz). finish() çubuğu doldurur ve `done` sinyali verir.

signal done

const MESSAGES := [
	"Evrene bağlandı",
	"Dünyalar oluşturuluyor",
	"Askerler eğitiliyor",
	"Kakalaklar yerleştiriliyor",
	"Kaleler boyanıyor",
	"Bayraklar dikiliyor",
	"Yollar çiziliyor",
	"Haritacılar uyandırılıyor",
	"Komutanlara çay demleniyor",
	"Kılıçlar bileniyor",
	"Casuslar sınırdan geri çağrılıyor",
	"Atlar eyerleniyor",
	"Tarafsız köylüler ikna ediliyor",
	"Sinyal güçlendiriliyor",
]
## Her yazı ekranda bu kadar kalır (çocuklar da rahat okuyabilsin). Yükleme bundan
## kısa sürerse sadece rastgele seçilen bir-iki yazı görünür; yükleme uzatılmaz.
const MESSAGE_SEC := 2.2

var _bar_fill: ColorRect
var _bar_bg: Panel
var _title: Label
var _msg: Label
var _value := 0.0
var _target := 0.15
var _finishing := false
var _msg_timer := 0.0
var _order: Array = []
var _min_until := 0


## title: üstteki büyük yazı; min_sec: panelin en az görünme süresi (yazılar okunabilsin).
static func show_over(parent: Node, title: String, min_sec := 1.6) -> LoadingPanel:
	var p := LoadingPanel.new()
	p._min_until = Time.get_ticks_msec() + int(min_sec * 1000)
	parent.add_child(p)
	p._title.text = title
	return p


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # alttaki düğmelere basılmasın
	theme = UIKit.make_theme()

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.09, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 22)
	center.add_child(box)

	_title = UIKit.label("", 40, UIKit.TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_bar_bg = Panel.new()
	_bar_bg.custom_minimum_size = Vector2(0, 34)
	_bar_bg.add_theme_stylebox_override("panel", UIKit.box(Color("#0f1329"), 17))
	box.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UIKit.ACCENT
	_bar_fill.position = Vector2(5, 5)
	_bar_bg.add_child(_bar_fill)

	_msg = UIKit.label("", 26, UIKit.MUTED)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_msg)

	_order = range(MESSAGES.size())
	_order.shuffle()


## Çubuğun şu anki adımda ulaşabileceği en üst değer (0..1).
func set_target(v: float) -> void:
	_target = maxf(_target, clampf(v, 0.0, 0.98))


## Çubuğu doldurur; en az görünme süresi dolunca `done` verir ve kendini kaldırır.
func finish() -> void:
	_finishing = true
	_target = 1.0


func cancel() -> void:
	queue_free()


func _process(delta: float) -> void:
	# Hedefe yumuşak yaklaşma; bitirirken daha hızlı.
	var speed := 2.5 if _finishing else 0.9
	_value = move_toward(_value, _target, delta * speed * maxf(0.08, _target - _value + 0.08))
	if not _finishing and _value > _target - 0.02:
		# Adım uzarsa takılmış görünmesin: sınıra çok yavaş sürünür.
		_target = minf(_target + delta * 0.01, 0.97)
	var w := maxf(0.0, (_bar_bg.size.x - 10.0) * _value)
	_bar_fill.size = Vector2(w, _bar_bg.size.y - 10.0)

	_msg_timer -= delta
	if _msg_timer <= 0.0 and not _order.is_empty():
		_msg_timer = MESSAGE_SEC
		_msg.text = String(MESSAGES[_order.pop_front()]) + "..."
		# Yumuşakça belirsin
		_msg.modulate.a = 0.0
		_msg.create_tween().tween_property(_msg, "modulate:a", 1.0, 0.25)
		if _order.is_empty():
			_order = range(MESSAGES.size())
			_order.shuffle()

	if _finishing and _value >= 0.999 and Time.get_ticks_msec() >= _min_until:
		_finishing = false
		done.emit()
		queue_free()
