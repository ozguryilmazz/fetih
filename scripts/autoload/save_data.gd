extends Node
## Cihazda saklanan oyuncu bilgileri. Hesap sistemi yok; her şey bu dosyada.

const PATH := "user://save.cfg"

## Multiplayer'da oyuncuyu ayırt etmek için cihaza özel rastgele kimlik.
var player_id := ""
var player_name := "Oyuncu"
var color_index := 1
var icon_index := 0
var gold := 0
## Açılmış en yüksek bölüm.
var unlocked_level := 1
var upgrades := {"production": 0, "speed": 0, "start": 0, "road": 0}
var vibration := true
## Bölüm -> en iyi yıldız sayısı (1..3).
var stars := {}
## Günlük ödül: son alındığı gün (YYYY-MM-DD) ve serideki gün (1..7).
var daily_last := ""
var daily_streak := 0


func _ready() -> void:
	load_data()


func load_data() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		player_id = cf.get_value("player", "id", "")
		player_name = cf.get_value("player", "name", player_name)
		color_index = cf.get_value("player", "color", color_index)
		icon_index = cf.get_value("player", "icon", icon_index)
		vibration = cf.get_value("settings", "vibration", true)
		gold = cf.get_value("progress", "gold", 0)
		unlocked_level = cf.get_value("progress", "level", 1)
		for key in upgrades.keys():
			upgrades[key] = cf.get_value("upgrades", key, 0)
		if cf.has_section("stars"):
			for key in cf.get_section_keys("stars"):
				stars[int(key)] = int(cf.get_value("stars", key, 0))
		daily_last = cf.get_value("daily", "last", "")
		daily_streak = cf.get_value("daily", "streak", 0)
		unlocked_level = mini(unlocked_level, GameConfig.MAX_LEVEL)
	if player_id == "":
		player_id = _new_id()
		save()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "id", player_id)
	cf.set_value("player", "name", player_name)
	cf.set_value("player", "color", color_index)
	cf.set_value("player", "icon", icon_index)
	cf.set_value("settings", "vibration", vibration)
	cf.set_value("progress", "gold", gold)
	cf.set_value("progress", "level", unlocked_level)
	for key in upgrades.keys():
		cf.set_value("upgrades", key, upgrades[key])
	for level in stars.keys():
		cf.set_value("stars", str(level), stars[level])
	cf.set_value("daily", "last", daily_last)
	cf.set_value("daily", "streak", daily_streak)
	cf.save(PATH)


func try_buy_upgrade(key: String) -> bool:
	var level: int = upgrades[key]
	if level >= int(GameConfig.UPGRADES[key]["max"]):
		return false
	var cost := GameConfig.upgrade_cost(key, level)
	if gold < cost:
		return false
	gold -= cost
	upgrades[key] = level + 1
	save()
	return true


func _new_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in 16:
		s += "%x" % rng.randi_range(0, 15)
	return s


# ---------------------------------------------------------------- bölüm sonucu

func best_stars(level: int) -> int:
	return stars.get(level, 0)


func total_stars() -> int:
	var t := 0
	for v in stars.values():
		t += v
	return t


## Kazanılan bölümü kaydeder, verilen altını döndürür.
func record_win(level: int, earned_stars: int) -> int:
	var prev := best_stars(level)
	var g := GameConfig.level_gold(level, earned_stars, prev)
	gold += g
	if earned_stars > prev:
		stars[level] = earned_stars
	if level >= unlocked_level:
		unlocked_level = mini(level + 1, GameConfig.MAX_LEVEL)
	save()
	return g


# ---------------------------------------------------------------- günlük ödül

static func today() -> String:
	return Time.get_date_string_from_system()


static func _day_before(date: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	return Time.get_date_string_from_unix_time(unix - 86400)


func can_claim_daily() -> bool:
	return daily_last != today()


## Bugün alınacak ödülün serideki günü (1..7).
func next_daily_day() -> int:
	if daily_last == _day_before(today()) and daily_streak > 0:
		return daily_streak % GameConfig.DAILY_REWARDS.size() + 1
	return 1


## Ödülü verir, verilen altını döndürür (alınamıyorsa 0).
func claim_daily() -> int:
	if not can_claim_daily():
		return 0
	var day := next_daily_day()
	var g: int = GameConfig.DAILY_REWARDS[day - 1]
	gold += g
	daily_streak = day
	daily_last = today()
	save()
	return g
