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
	## Boss'un ana üssü: büyük, hızlı üretir, dayanıklı.
	"fortress": {"name": "Kale", "growth": 1.4, "capacity": 120, "defense": 1.4, "radius": 54.0},
	## Hayatta kalma modu: oyuncunun kalesi. Düşerse oyun biter; askerinin en fazla
	## yarısını gönderebilir (gerisi garnizon).
	"keep": {"name": "Kale", "growth": 1.4, "capacity": 150, "defense": 2.0, "radius": 54.0},
	## Hayatta kalma modu: rakibin ana kalesi. Asker göndermez (dalgaları o çıkarır),
	## garnizonu büyür, savunması çok yüksektir. Alınırsa zafer.
	"citadel": {"name": "Düşman Kalesi", "growth": 4.0, "capacity": 400, "defense": 2.5, "radius": 60.0},
	## Hayatta kalma modu: kışla (üretimi seviyeye göre, bkz. barracks_growth).
	"barracks": {"name": "Kışla", "growth": 1.5, "capacity": 80, "defense": 1.0, "radius": 44.0},
	## Hayatta kalma modu: altın madeni. growth/capacity = madenin kendi (2 güçlü) askerleri.
	"mine": {"name": "Altın Madeni", "growth": 0.5, "capacity": 30, "defense": 1.0, "radius": 42.0},
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
	"road": {"name": "Yol Savaşı", "desc": "Yolda çarpışınca her kolun +1 asker avantajlı (15'e 15 → 1 askerin sağ kalır)", "max": 10, "base_cost": 120},
}
const UPGRADE_ORDER := ["production", "speed", "start", "road"]


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


## Yol çarpışmasında kol başına kaç askerlik avantaj (kademe başına +1).
static func road_bonus(level: int) -> int:
	return level


# ---------------------------------------------------------------- solo bölümler

const MAX_LEVEL := 50
## Yıldız sayısına göre altın (0, 1, 2, 3 yıldız).
const STAR_GOLD := [0, 50, 75, 100]
## Daha önce aynı/daha iyi yıldızla geçilmiş bölüm tekrar oynanırsa verilen oran.
const REPLAY_GOLD_FACTOR := 0.2
const BOSS_GOLD_FACTOR := 2
## 3. yıldız: en fazla bu kadar üs kaybederek kazan.
const STAR_LOSS_LIMIT := 2
## Günlük ödül serisi (7. günden sonra başa döner; bir gün kaçırılırsa seri sıfırlanır).
const DAILY_REWARDS := [50, 75, 100, 125, 150, 200, 300]
const BAND_NAMES := ["Kolay-Orta", "Orta", "Orta-Zor", "Zor", "Çok Zor"]
## Zorluk eğrisi: [bölüm, bot becerisi 0..1]. Aradaki bölümler doğrusal geçer.
const SKILL_CURVE := [[1, 0.0], [10, 0.25], [20, 0.45], [30, 0.62], [40, 0.78], [50, 0.95]]


static func is_boss(n: int) -> bool:
	return n % 10 == 0


static func band_name(n: int) -> String:
	@warning_ignore("integer_division")
	return BAND_NAMES[clampi((n - 1) / 10, 0, BAND_NAMES.size() - 1)]


static func skill_for_level(n: int) -> float:
	n = clampi(n, 1, MAX_LEVEL)
	for i in range(1, SKILL_CURVE.size()):
		var a: Array = SKILL_CURVE[i - 1]
		var b: Array = SKILL_CURVE[i]
		if n <= b[0]:
			return lerpf(a[1], b[1], float(n - a[0]) / float(b[0] - a[0]))
	return 1.0


static func level_params(n: int) -> Dictionary:
	var s := skill_for_level(n)
	var boss := is_boss(n)
	var up := clampi(int(floor((s - 0.25) * 9.0)), 0, 7)
	var p := {
		"skill": s,
		"boss": boss,
		"bots": 1 if (n <= 5 or boss) else 2,
		"bases": clampi(7 + int(n / 4.0), 7, 16),
		"bot_upgrade": up,
		"bot_prod_bonus": 1.0 + 0.15 * clampf((s - 0.6) / 0.4, 0.0, 1.0),
		"neutral_min": 5 + int(n / 5.0),
		"neutral_max": 15 + int(n / 3.0),
	}
	if boss:
		p["skill"] = minf(1.0, s + 0.05)
		p["bot_upgrade"] = up + 1
		p["bot_prod_bonus"] += 0.1
		p["bases"] = mini(p["bases"] + 1, 17)
	p["par"] = par_time(p)
	return p


## 2. yıldız için hedef süre (saniye). Zorluk simülasyonuyla ayarlandı.
static func par_time(p: Dictionary) -> int:
	var t: float = 55.0 + 6.0 * p["bases"] + 15.0 * (p["bots"] - 1)
	if p["boss"]:
		t += 30.0
	return int(ceil(t / 10.0) * 10.0)


static func level_gold(n: int, stars: int, previous_best: int) -> int:
	var g: float = STAR_GOLD[stars]
	if is_boss(n):
		g *= BOSS_GOLD_FACTOR
	if stars <= previous_best:
		g *= REPLAY_GOLD_FACTOR
	return int(g)


## Kazanılan bölümün yıldız sayısı: 1 (kazandın) + hedef süre + az kayıp.
static func stars_for(params: Dictionary, time_sec: float, bases_lost: int) -> int:
	var st := 1
	if time_sec <= params["par"]:
		st += 1
	if bases_lost <= STAR_LOSS_LIMIT:
		st += 1
	return st



# ---------------------------------------------------------------- hayatta kalma modu

const SURVIVAL_BASES := 22
const SURVIVAL_ENEMY_SKILL := 0.85
const SURVIVAL_NEUTRAL_MIN := 15
const SURVIVAL_NEUTRAL_MAX := 35
const CITADEL_START := 300.0
## Düşman kalesi bu dalgaya kadar kalkanlı (alınamaz).
const CITADEL_SHIELD_WAVES := 10
## Maç altını: herkese saniyede bu kadar, her maden ayrıca MINE_GOLD ekler.
const SURVIVAL_GOLD_RATE := 1.0
## Altın madeni seviyeleri: [fiyat, ek altın/sn, maden askeri tavanı]
const MINE_LEVELS := [
	[120, 0.5, 30],
	[200, 1.0, 40],
	[350, 1.5, 50],
]
## Aynı türden her yeni bina bu oranda pahalanır (2. kışla %50 daha pahalı...).
const EXTRA_BUILDING_COST := 0.5
## Kaleden tek seferde gönderilebilecek oran (yarısı garnizon olarak kalır).
const FORTRESS_SEND_FRACTION := 0.5
## Kalede her zaman en az bu kadar asker kalır.
const KEEP_MIN_GARRISON := 20
## Maden askeri bu kadar güçlü (normal asker 1).
const ELITE_POWER := 2.0
## Kışla seviyeleri: [fiyat, kendi üretimi, diğer üslere üretim bonusu, hız bonusu]
const BARRACKS_LEVELS := [
	[100, 1.5, 0.10, 0.0],
	[150, 2.0, 0.20, 0.0],
	[250, 2.5, 0.30, 0.0],
	[400, 3.0, 0.40, 0.10],
	[600, 3.5, 0.50, 0.20],
]
## Birden fazla kışlanın bonusları toplanır ama bu tavanları aşamaz.
const MAX_PROD_BONUS := 1.0
const MAX_SPEED_BONUS := 0.3
## Dalgalar: ilk dalga WAVE_FIRST sn'de, sonra her WAVE_INTERVAL sn'de bir.
const WAVE_FIRST := 60.0
const WAVE_INTERVAL := 60.0
const WAVE_BASE := 12
const WAVE_GROWTH := 9
## Dalgalar ilerledikçe hızlanarak büyür: + WAVE_ACCEL * (n-1)^2
const WAVE_ACCEL := 0.5
## Rakibin üretimi dakikada bu oranda artar.
const ENEMY_RAMP_PER_MIN := 0.10
## Mağaza altını ödülü: dayanılan her dakika için + zafer bonusu.
const SURVIVAL_GOLD_PER_MIN := 10
const SURVIVAL_WIN_BONUS := 200


static func barracks_cost(level: int) -> int:
	return BARRACKS_LEVELS[level - 1][0]


static func mine_gold(level: int) -> float:
	return MINE_LEVELS[level - 1][1]


static func mine_capacity(level: int) -> float:
	return MINE_LEVELS[level - 1][2]


## Kışla kapasitesi seviyeyle artar (70, 80 ... 110).
static func barracks_capacity(level: int) -> float:
	return 60.0 + 10.0 * level


static func barracks_growth(level: int) -> float:
	return BARRACKS_LEVELS[level - 1][1]


static func survival_reward(time_sec: float, won: bool) -> int:
	return int(time_sec / 60.0 * SURVIVAL_GOLD_PER_MIN) + (SURVIVAL_WIN_BONUS if won else 0)
