#!/usr/bin/env bash
# Cinders of Chaos, Linux server package: adds a player account, with a level 1 character, to the package's database.
# The database must be running (./start-server.sh).
#
#   ./add-account.sh ACCOUNT PASSWORD CHARACTER [warrior|ranger|mystic|thief] [male|female]
#
# ACCOUNT: 3-32 letters or digits. PASSWORD: 6-64 characters, no spaces, quotes or backslashes. CHARACTER: 3-29
# letters and spaces ("Ember Knight"). The class defaults to warrior, the sex to male.
#
# The character is made like the website and the client make one: level 8 with that level's experience and its class's
# health, mana, capacity and soul (server/data/scripts/chaos/start_stats.lua), its class look with both addons and
# the class's start colours (class_looks_core.lua), the main city as its town (newplayer_config.lua homeTown), position 0,0,0 (the temple).
# The game gives it the full starter kit in its first login.
set -euo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
if [ $# -lt 3 ] || [ $# -gt 5 ]; then sed -n '4,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; fi
account=$1 password=$2 character=$3 class=${4:-warrior} sexname=${5:-male}
[[ $account =~ ^[A-Za-z0-9]{3,32}$ ]] || { echo "ACCOUNT: 3-32 letters or digits"; exit 2; }
[[ $password =~ ^[^[:space:]\'\"\\]{6,64}$ ]] || { echo "PASSWORD: 6-64 characters, no spaces, quotes or backslashes"; exit 2; }
[[ $character =~ ^[A-Za-z][A-Za-z\ ]{1,27}[A-Za-z]$ ]] || { echo "CHARACTER: 3-29 letters and spaces"; exit 2; }
case "$class" in
  warrior) voc=4 ;; ranger) voc=3 ;; mystic) voc=1 ;; thief) voc=11 ;;
  *) echo "class: warrior, ranger, mystic or thief"; exit 2 ;;
esac
case "$sexname" in
  male) sex=1 ;; female) sex=0 ;;
  *) echo "sex: male or female"; exit 2 ;;
esac

# --- the values of the server's own files (one source of truth with the website and the game server)
CHAOS="$ROOT/server/data/scripts/chaos"
[ -d "${CHAOS_SCRIPTS:-}" ] && CHAOS=$CHAOS_SCRIPTS   # tests point it at the repository
stats_line=$(grep -E "^[[:space:]]*\[$voc\] = \{health = [0-9]+, mana = [0-9]+, cap = [0-9]+, soul = [0-9]+, gainhp = [0-9]+, gainmana = [0-9]+, gaincap = [0-9]+\}" \
  "$CHAOS/start_stats.lua" 2>/dev/null | head -n 1) || true
[ -n "$stats_line" ] || { echo "No level 1 stats for class $voc in $CHAOS/start_stats.lua"; exit 1; }
field() { printf '%s\n' "$stats_line" | sed -E "s/.*[{ ]$1 = ([0-9]+).*/\1/"; }
setting() { sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p" "$CHAOS/start_stats.lua" | head -n 1; }
level=$(setting startLevel) experience=$(setting startExperience)
[[ ${level:-} =~ ^[1-9][0-9]*$ ]] || level=1
[[ ${experience:-} =~ ^[0-9]+$ ]] || experience=0
up=$((level - 1))
# the class's stats at the start level: its level 1 row plus a level's gains per level above 1
health=$(( $(field health) + up * $(field gainhp) ))
mana=$(( $(field mana) + up * $(field gainmana) ))
cap=$(( $(field cap) + up * $(field gaincap) ))
soul=$(field soul)
# the class look: L.looks, replaced by L.pair19Looks / L.pair20Looks when their switch is on (as the website reads it)
look=$(awk -v v="$voc" -v sex="$sex" '
  /^L\.PAIR19_LOOKS[ \t]*=[ \t]*true/ { on19 = 1 }
  /^L\.PAIR20_LOOKS[ \t]*=[ \t]*true/ { on20 = 1 }
  /^L\.looks[ \t]*=[ \t]*\{/ { t = "base"; next }
  /^L\.pair19Looks[ \t]*=[ \t]*\{/ { t = "p19"; next }
  /^L\.pair20Looks[ \t]*=[ \t]*\{/ { t = "p20"; next }
  /^\}/ { t = "" }
  t != "" && $0 ~ ("^[ \t]*\\[" v "\\][ \t]*=[ \t]*\\{") {
    m = $0; sub(/.*[^e]male = /, "", m); f = $0; sub(/.*female = /, "", f); M[t] = m + 0; F[t] = f + 0
  }
  END {
    k = "base"
    if (on19 && ("p19" in M)) k = "p19"; else if (on20 && ("p20" in M)) k = "p20"
    if (k in M) print (sex == 0 ? F[k] : M[k])
  }' "$CHAOS/class_looks_core.lua" 2>/dev/null) || true
[[ ${look:-} =~ ^[0-9]+$ ]] || { echo "No class look for class $voc in $CHAOS/class_looks_core.lua"; exit 1; }
# the class's start colours (L.startColors: head, body, legs, feet), as the website and the first login put them on
colors=$(awk -v v="$voc" '
  /^L\.startColors[ \t]*=[ \t]*\{/ { t = 1; next }
  /^\}/ { t = 0 }
  t && $0 ~ ("^[ \t]*\\[" v "\\][ \t]*=[ \t]*\\{") {
    h = $0; sub(/.*head = /, "", h); b = $0; sub(/.*body = /, "", b); l = $0; sub(/.*legs = /, "", l)
    f = $0; sub(/.*feet = /, "", f); print h + 0, b + 0, l + 0, f + 0
  }' "$CHAOS/class_looks_core.lua" 2>/dev/null) || true
read -r lookhead lookbody looklegs lookfeet <<< "${colors:-78 68 58 76}"
town=$(sed -nE 's/^[[:space:]]*homeTown[[:space:]]*=[[:space:]]*\{[[:space:]]*id[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' \
  "$CHAOS/newplayer_config.lua" 2>/dev/null | head -n 1)
[[ ${town:-} =~ ^[1-9][0-9]*$ ]] || town=2
if [ "${ADD_ACCOUNT_PRINT_ONLY:-0}" = 1 ]; then   # tests: the values, no database
  echo "vocation=$voc sex=$sex level=$level experience=$experience health=$health mana=$mana cap=$cap soul=$soul looktype=$look colors=$lookhead/$lookbody/$looklegs/$lookfeet town=$town"; exit 0
fi

SOCK="$ROOT/run/mariadb.sock"
# a Unix socket path may have at most 107 bytes: deep folders put it in /tmp instead (named after this folder)
[ "$(printf %s "$SOCK" | wc -c)" -le 100 ] || SOCK="/tmp/chaos-mariadb-$(id -u)-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1).sock"
db() { "$ROOT/mariadb/bin/mariadb" --no-defaults --socket="$SOCK" -u "$(id -un)" chaos "$@"; }
db -e "SELECT 1" >/dev/null 2>&1 || { echo "The database is not running: start it with ./start-server.sh"; exit 1; }
if [ "$(db -N -e "SELECT COUNT(*) FROM accounts WHERE name = '$account'")" != 0 ]; then
  echo "Account $account exists already."; exit 1
fi
if [ "$(db -N -e "SELECT COUNT(*) FROM players WHERE name = '$character'")" != 0 ]; then
  echo "A character named $character exists already."; exit 1
fi
db -e "INSERT INTO accounts (name, password, type, creation) VALUES ('$account', SHA1('$password'), 1, UNIX_TIMESTAMP());
       INSERT INTO players (name, group_id, account_id, vocation, level, experience, health, healthmax, mana, manamax, cap, soul,
                            sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, town_id, posx, posy, posz, lastlogin)
         SELECT '$character', 1, id, $voc, $level, $experience, $health, $health, $mana, $mana, $cap, $soul, $sex,
                $look, $lookhead, $lookbody, $looklegs, $lookfeet, 3, $town, 0, 0, 0, 0 FROM accounts WHERE name = '$account';"
echo "Account $account added with the $class \"$character\" (level $level: $health health, $mana mana, $cap cap)."
