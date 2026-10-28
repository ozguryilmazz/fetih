class_name GameConfig
extends RefCounted
## Oyun genelindeki sabitler ve denge (balance) ayarları.
## Sayılarla oynamak istediğinde ilk bakılacak yer burası.

## Haritanın mantıksal boyutu. Tüm cihazlarda aynıdır; multiplayer'da
## herkes aynı koordinatları görür, ekran farkı sadece ortalanarak çözülür.
const MAP_SIZE := Vector2(720, 1280)
## Üslerin yerleşebileceği alan (üstte HUD için boşluk bırakılır).
const MAP_RECT := Rect2(70, 200, 580, 1000)

## Simülasyon sabit adımla ilerler (saniyede 30 adım).
## Multiplayer'da host ile istemcilerin aynı sonucu üretmesi için önemli.
const SIM_DT := 1.0 / 30.0

const NEUTRAL := -1
const MAX_PLAYERS := 3

## Bir üsten gönderim yapıldığında askerlerin ne kadarı yola çıkar (1.0 = tamamı).
## Birden fazla hedef seçildiyse bu miktar hedeflere eşit bölünür.
const SEND_FRACTION := 1.0
## Askerlerin yürüme hızı (piksel/saniye).
const TROOP_SPEED := 120.0
## Oyuncuların başlangıç üssündeki asker sayısı.
const START_TROOPS := 20
## Kapasitenin üstüne çıkan üs saniyede bu kadar asker kaybeder.
const OVERFLOW_DECAY := 2.0

## Üs tipleri. Yeni tip eklemek için buraya bir satır eklemek yeter.
## growth: saniyede üretilen asker, capacity: üretimin durduğu sınır,
## defense: saldıranın askerleri bu sayıya bölünerek düşülür (1.5 = %50 daha dayanıklı).
const BASE_TYPES := {
	"normal": {"name": "Normal", "growth": 1.0, "capacity": 60, "defense": 1.0, "radius": 42.0},
}

const PALETTE_HEX := [
	"#e74c3c", "#3498db", "#2ecc71", "#f1c40f",
	"#9b59b6", "#e67e22", "#1abc9c", "#ff6b9d",
]
const NEUTRAL_HEX := "#6c7293"

## Geçici ikonlar (şekiller). Gerçek ikon seti belirlenince değişecek.
const ICON_NAMES := ["Daire", "Yıldız", "Üçgen", "Kare", "Elmas", "Altıgen"]

## Altınla alınan güçlendirmeler. Solo ve multiplayer'da geçerlidir.
const UPGRADES := {
	"production": {"name": "Üretim Hızı", "desc": "Üslerin %6 daha hızlı asker üretir", "max": 10, "base_cost": 100},
	"speed": {"name": "Asker Hızı", "desc": "Askerlerin %5 daha hızlı yürür", "max": 10, "base_cost": 100},
	"start": {"name": "Başlangıç Gücü", "desc": "Başlangıç üssüne +3 asker", "max": 10, "base_cost": 80},
}
const UPGRADE_ORDER := ["production", "speed", "start"]


static func color(index: int) -> Color:
	if index < 0:
		return Color(NEUTRAL_HEX)
	return Color(PALETTE_HEX[index % PALETTE_HEX.size()])


static func upgrade_cost(key: String, level: int) -> int:
	return int(UPGRADES[key]["base_cost"]) * (level + 1)


static func production_mult(level: int) -> float:
	return 1.0 + 0.06 * level


static func speed_mult(level: int) -> float:
	return 1.0 + 0.05 * level


static func start_bonus(level: int) -> int:
	return 3 * level


## Solo bölümlerin zorluk eğrisi.
static func level_params(n: int) -> Dictionary:
	return {
		"bots": 1 if n < 4 else 2,
		"bases": clampi(7 + int(n / 2.0), 7, 16),
		"difficulty": clampf(0.1 + n * 0.05, 0.1, 1.0),
		"bot_upgrade": mini(int(n / 3.0), 10),
		"neutral_min": 5 + int(n / 3.0),
		"neutral_max": 15 + n,
		"gold": 40 + n * 10,
	}
