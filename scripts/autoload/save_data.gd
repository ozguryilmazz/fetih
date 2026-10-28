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
