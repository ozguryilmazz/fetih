class_name NetConfig
extends RefCounted
## Firebase bağlantı ayarları. Firebase konsolundan alınan iki değer buraya yazılır:
##  - DB_URL:  Realtime Database sayfasının üstündeki adres (sonunda / olmadan)
##  - API_KEY: Proje ayarları -> Genel -> Web API anahtarı
## Bu ikisi gizli değildir; asıl koruma database.rules.json kurallarıdır.

const DB_URL := "https://zozo-c097b-default-rtdb.europe-west1.firebasedatabase.app"
const API_KEY := "AIzaSyA-Ya4fp5q2P5vGqPQyJW1yC21iWkUTYts"

const AUTH_URL := "https://identitytoolkit.googleapis.com"
const TOKEN_URL := "https://securetoken.googleapis.com"

## Oda kodu geçerlilik süresi ve kopma algılama.
const ROOM_TTL_MS := 5 * 60 * 1000
const HEARTBEAT_SEC := 2.0
const DISCONNECT_SEC := 9.0
const SNAPSHOT_HZ := 5.0
const MAX_PLAYERS := 3

## Ödül (mağaza altını).
const WIN_GOLD := 100
const LOSE_GOLD := 30


## Test için komut satırından sahte sunucu: godot ... -- --fb=http://127.0.0.1:9000
static func override_base() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fb="):
			return a.substr(5)
	return ""


## Test için oda süresi: -- --ttl=3000
static func room_ttl_ms() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ttl="):
			return int(a.substr(6))
	return ROOM_TTL_MS


static func profile() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			return a.substr(10)
	return "default"


static func db_url() -> String:
	var o := override_base()
	return o if o != "" else DB_URL


static func auth_url() -> String:
	var o := override_base()
	return o if o != "" else AUTH_URL


static func token_url() -> String:
	var o := override_base()
	return o if o != "" else TOKEN_URL


static func api_key() -> String:
	return "test" if override_base() != "" else API_KEY


static func configured() -> bool:
	return db_url() != "" and api_key() != ""
