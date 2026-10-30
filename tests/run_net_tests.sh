#!/bin/bash
# Çok oyunculu testler: sahte Firebase sunucusu + iki ayrı Godot kopyası.
# Kullanım: tests/run_net_tests.sh <godot çalıştırılabilir dosyası>
set -u
G="$1"
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
PORT=9057
python3 tools/fake_firebase/server.py $PORT database.rules.json > "$TMP/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
sleep 1
FAIL=0

pair() {  # pair <betik> <rolA> <rolB> [ek arg]
	rm -rf "$TMP/run" && mkdir -p "$TMP/run"
	local ARGS="--fb=http://127.0.0.1:$PORT --dir=$TMP/run ${4:-}"
	timeout 150 "$G" --headless --path . -s "$1" -- $ARGS --profile=a --role=$2 > "$TMP/a.log" 2>&1 &
	local A=$!
	timeout 150 "$G" --headless --path . -s "$1" -- $ARGS --profile=b --role=$3 > "$TMP/b.log" 2>&1
	wait $A
	grep -hE "^\s+(ok|HATA)" "$TMP/a.log" "$TMP/b.log"
	for f in a b; do
		local r="$2"; [ $f = b ] && r="$3"
		case "$r" in *_kill) continue;; esac
		grep -q "SONUC: TAMAM" "$TMP/$f.log" || { echo "HATA: $1 ($r) başarısız"; tail -20 "$TMP/$f.log"; FAIL=1; }
	done
}

echo "== Lobi, komut, durum paketi, kopma"
pair tests/net_lobby_test.gd host client
echo "== Oda süresi"
pair tests/net_lobby_test.gd expire_host expire_client "--ttl=3000"
echo "== Uçtan uca maç"
pair tests/net_match_test.gd host client
echo "== İfade + rövanş"
pair tests/net_match_test.gd host_re client_re
echo "== Maç ortasında client kopması"
pair tests/net_match_test.gd host client_kill
echo "== Maç ortasında host kopması"
pair tests/net_match_test.gd host_kill client
grep '"denied"' "$TMP/server.log" | tail -1
[ $FAIL = 0 ] && echo "SONUC: TAMAM" || echo "SONUC: HATA"
exit $FAIL
