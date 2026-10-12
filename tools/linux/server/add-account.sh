#!/usr/bin/env bash
# Cinders of Chaos, Linux server package: adds a player account, with a level 1 character, to the package's database.
# The database must be running (./start-server.sh).
#
#   ./add-account.sh ACCOUNT PASSWORD CHARACTER [warrior|ranger|mystic|thief]
#
# ACCOUNT: 3-32 letters or digits. PASSWORD: 6-64 characters, no spaces, quotes or backslashes. CHARACTER: 3-29
# letters and spaces ("Ember Knight"). The class defaults to warrior. The tutorial runs at the first login.
set -euo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
[ $# -ge 3 ] && [ $# -le 4 ] || { sed -n '4,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
account=$1 password=$2 character=$3 class=${4:-warrior}
[[ $account =~ ^[A-Za-z0-9]{3,32}$ ]] || { echo "ACCOUNT: 3-32 letters or digits"; exit 2; }
[[ $password =~ ^[^[:space:]\'\"\\]{6,64}$ ]] || { echo "PASSWORD: 6-64 characters, no spaces, quotes or backslashes"; exit 2; }
[[ $character =~ ^[A-Za-z][A-Za-z\ ]{1,27}[A-Za-z]$ ]] || { echo "CHARACTER: 3-29 letters and spaces"; exit 2; }
case "$class" in
  warrior) voc=4 ;; ranger) voc=3 ;; mystic) voc=1 ;; thief) voc=11 ;;
  *) echo "class: warrior, ranger, mystic or thief"; exit 2 ;;
esac

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
       INSERT INTO players (name, group_id, account_id, vocation, level, lastlogin)
         SELECT '$character', 1, id, $voc, 1, 0 FROM accounts WHERE name = '$account';"
echo "Account $account added with the $class \"$character\"."
