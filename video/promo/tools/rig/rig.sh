#!/bin/bash
# rig.sh: the trailer's live capture rig (video/promo/README.md "Live rig"). TEST ONLY, scratch folders only.
#
#   RIG=/scratch/rig rig.sh <command> ...
#   $RIG/srv   base server, installed with server/tools/install_all.py, engine built with every src-patch (build/tfs)
#   $RIG/game  assembled client (client/tools/assemble_client.sh) with pair 26 in data/things/1098, built
#   $RIG/db    MariaDB data folder (port 3369); $RIG/clips the raw recordings
#
# commands
#   setup-db                 create the data folder and database, load the base schema, the rig account (chars.sql)
#   hooks                    copy the test hooks: rig_server.lua into the server, zz_devexec into the client
#   db | server | server stop
#   client NAME [pt-BR|en]   Xvfb :831 at 1920x1080 + the client, log in account "trailer" as NAME; "client stop"
#   char NAME [kit] [level]  log NAME in; with a kit (/testkit kinds: mage, berserker, templar, necromancer, ...)
#                            give gear and raise the level first, then log in again (item bonuses apply at login)
#   sx 'server lua' [wait]   run Lua in the server (output: the result line)
#   cx 'client lua' [wait]   run Lua in the client (output: DEVEXEC lines of the client log)
#   rec NAME SECONDS         record the display to $RIG/clips/NAME.mp4 (x11grab, 30 fps)
#   take NAME SECS 'server lua' 'client lua' [pause]   set up with sx, start the client script, record
set -u
RIG=${RIG:?set RIG to the rig folder}
HERE=$(cd "$(dirname "$0")" && pwd)
D=:831
SOCK=$RIG/db.sock
cmd=${1:-}; shift || true

case "$cmd" in
setup-db)
  mkdir -p "$RIG/db" "$RIG/sxq"
  [ -d "$RIG/db/mysql" ] || mariadb-install-db --no-defaults --datadir="$RIG/db" --user=root > "$RIG/db_install.log" 2>&1
  "$0" db
  mariadb -S "$SOCK" -u root -e "CREATE DATABASE IF NOT EXISTS chaosrig; CREATE USER IF NOT EXISTS 'rig'@'127.0.0.1' IDENTIFIED BY 'rigtest'; GRANT ALL ON chaosrig.* TO 'rig'@'127.0.0.1';"
  if [ "$(mariadb -S "$SOCK" -u root -N -e 'select count(*) from information_schema.tables where table_schema="chaosrig"')" = 0 ]; then
    for f in "$RIG"/srv/SQL_Server/schema.sql "$RIG"/srv/SQL_Server/schema_*.sql "$RIG"/srv/SQL_Server/sql_*.sql; do
      mariadb -S "$SOCK" -u root chaosrig < "$f" || echo "SQL FAIL $f"
    done
  fi
  sed -i 's/^loginProtocolPort = .*/loginProtocolPort = 7891/; s/^gameProtocolPort = .*/gameProtocolPort = 7892/;
          s/^statusProtocolPort = .*/statusProtocolPort = 7891/; s/^mysqlUser = .*/mysqlUser = "rig"/;
          s/^mysqlPass = .*/mysqlPass = "rigtest"/; s/^mysqlDatabase = .*/mysqlDatabase = "chaosrig"/;
          s/^mysqlPort = .*/mysqlPort = 3369/' "$RIG/srv/config.lua"
  echo "now: python3 -I server/tools/install_all.py $RIG/srv  (its sql step fills chaosrig), then:"
  echo "  mariadb -S $SOCK -u root chaosrig < $HERE/chars.sql"
  ;;
hooks)
  cp "$HERE/rig_server.lua" "$RIG/srv/data/scripts/zz_rig_test.lua"
  mkdir -p "$RIG/game/modules/zz_devexec"
  cp "$HERE"/zz_devexec/* "$RIG/game/modules/zz_devexec/"
  ;;
db)
  [ -S "$SOCK" ] && exit 0
  (setsid mariadbd --no-defaults --datadir="$RIG/db" --port=3369 --bind-address=127.0.0.1 --socket="$SOCK" \
    --pid-file="$RIG/db.pid" --user=root --innodb-buffer-pool-size=128M --skip-log-bin > "$RIG/db.log" 2>&1 &)
  for _ in $(seq 30); do [ -S "$SOCK" ] && break; sleep 1; done
  ;;
server)
  for p in $(pgrep -x tfs); do [ "$(readlink /proc/$p/cwd)" = "$RIG/srv" ] && kill $p; done
  for _ in $(seq 60); do pgrep -x tfs >/dev/null || break; sleep 1; done
  [ "${1:-}" = stop ] && exit 0
  mkdir -p "$RIG/sxq"
  (cd "$RIG/srv" && CHAOS_RIG_QUEUE="$RIG/sxq" setsid ./build/tfs > "$RIG/tfs.log" 2>&1 < /dev/null &)
  for _ in $(seq 200); do grep -aq "Server Online" "$RIG/tfs.log" && break; sleep 2; done
  grep -a "Server Online" "$RIG/tfs.log"
  ;;
client)
  [ -f "$RIG/client.pid" ] && kill -9 "$(cat "$RIG/client.pid")" 2>/dev/null
  [ -f "$RIG/xvfb.pid" ] && kill "$(cat "$RIG/xvfb.pid")" 2>/dev/null
  rm -f "$RIG/client.pid" "$RIG/xvfb.pid"; sleep 1
  [ "${1:-}" = stop ] && exit 0
  NAME=$1; LNG=${2:-pt-BR}
  setsid Xvfb $D -screen 0 1920x1080x24 >/dev/null 2>&1 & echo $! > "$RIG/xvfb.pid"; sleep 1
  mkdir -p "$RIG/game/devexec"; : > "$RIG/game/devexec/cmd.lua"
  H=$RIG/home; rm -rf "$H"; mkdir -p "$H/.local/share/otclientv8"
  if [ "$LNG" = en ]; then L="chaos-language: en\nlocale: en"; else L="chaos-language: pt-BR\nlocale: pt"; fi
  printf "$L\nwindow-size: 1920 1080\nwindow-maximized: false\nshowFps: false\nshowPing: false\n" \
    > "$H/.local/share/otclientv8/config.otml"
  BIN=${CLIENT_BIN:-$(find "$RIG/game" -maxdepth 1 -type f -perm -u+x ! -name '*.sh' | head -1)}
  (cd "$RIG/game" && DISPLAY=$D HOME=$H ALSOFT_DRIVERS=null LIBGL_ALWAYS_SOFTWARE=1 setsid "$BIN" > "$RIG/client.log" 2>&1 &
   echo $! > "$RIG/client.pid")
  for _ in $(seq 60); do grep -aq "All local" "$RIG/client.log" 2>/dev/null && break; sleep 1; done; sleep 10
  "$0" cx "local eg = rootWidget:recursiveGetChildById('enterGame'); eg:getChildById('accountNameTextEdit'):setText('trailer'); eg:getChildById('accountPasswordTextEdit'):setText('test'); EnterGame.doLogin() return 'login sent'" 10
  [ "$NAME" = - ] && exit 0  # stay on the character list (charselect captures)
  "$0" cx "local w = rootWidget:recursiveGetChildById('characters') for _, c in ipairs(w and w:getChildren() or {}) do if c.characterName == '$NAME' then w:focusChild(c) end end CharacterList.doLogin() return 'picked'" 15
  DISPLAY=$D xdotool mousemove 1919 1079
  ;;
char)
  "$0" client "$1" "${LNG:-pt-BR}" >/dev/null
  if [ -n "${2:-}" ]; then
    "$0" cx "g_game.talk('!skiptutorial') return 1" 3 >/dev/null
    "$0" sx "local p = Player('$1') ChaosTestKit.give(p, '$2') local l = ${3:-1000} - 1 local need = math.floor((50*l*l*l - 150*l*l + 400*l) / 3) if need > p:getExperience() then p:addExperience(need - p:getExperience(), false) end return p:getLevel()" 3
    "$0" client "$1" "${LNG:-pt-BR}" >/dev/null
  fi
  sleep 1; "$0" cx "$(cat "$HERE/client_prep.lua")" 2
  ;;
sx)
  X=$RIG/sxq; touch "$X/out.log"; n=$(wc -l < "$X/out.log")
  printf -- '-- %s\nif configManager.getNumber(configKeys.GAME_PORT) ~= 7892 then error("not the rig") end\n%s\n' \
    "$RANDOM$RANDOM" "$1" > "$X/cmd.lua"
  sleep "${2:-1}"; tail -n +$((n + 1)) "$X/out.log"
  ;;
cx)
  n=$(wc -l < "$RIG/client.log")
  printf -- '-- %s\n%s\n' "$RANDOM$RANDOM" "$1" > "$RIG/game/devexec/cmd.lua"
  sleep "${2:-2}"; tail -n +$((n + 1)) "$RIG/client.log" | grep -a "DEVEXEC" | head -5
  ;;
rec)
  mkdir -p "$RIG/clips"
  ffmpeg -v error -y -f x11grab -framerate 30 -video_size 1920x1080 -i $D -t "$2" \
    -c:v libx264 -preset ultrafast -crf 14 -pix_fmt yuv420p "$RIG/clips/$1.mp4"
  ;;
take)
  "$0" sx "$3" 1 | tail -1; sleep "${5:-1.5}"
  "$0" cx "$4" 0.1 >/dev/null &
  "$0" rec "$1" "$2"; wait
  ;;
*)
  sed -n '2,25p' "$0"; exit 2
  ;;
esac
