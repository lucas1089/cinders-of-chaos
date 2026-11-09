#!/usr/bin/env bash
# Unity Core live check against a real server (O433, unity/README.md "Live check in CI"; .github/workflows/unity-live-check.yml).
# Both clients, the Extended and the Chaos identity of unity/Core.LiveCheck, play on one server that this script builds:
#   1. the base server of windows-assets, the map master when the branch has one, install_all.py of this checkout
#   2. a private MariaDB (own data folder, own socket, TCP on 127.0.0.1), the base schema, the chaos_* tables (install_all.py)
#   3. the engine: the tfs binary and its libraries from the newest winpkg release with CindersOfChaos-Server-Linux.tar.gz
#   4. fresh accounts and characters per run, random passwords made here, never printed, never written to a report
#   5. tfs on its own ports, Core.LiveCheck per run (a start place and a staff set-up per group of scenarios), reports,
#      a summary (GITHUB_STEP_SUMMARY when set), exit 1 when a run or a scenario failed (a skip does not fail)
#
# usage: UL_ASSETS=DIR UL_WORK=DIR UL_OUT=DIR tools/ci/unity_live_check.sh
#   UL_ASSETS       checkout of windows-assets (server/base-server.tar.xz, SHA256SUMS.parts, world/ when present)
#   UL_WORK         empty work folder (server, database, logs); several GB, never inside the repository
#   UL_OUT          folder for the reports and the summary (the artifact of the workflow); nothing secret goes in
#   UL_ENGINE_TAR   a CindersOfChaos-Server-Linux.tar.gz already downloaded (else: gh release download, GH_TOKEN, read only)
#   UL_ENGINE_REPO  repository of the releases (default GITHUB_REPOSITORY, else the origin of this checkout)
#   UL_LOGIN_PORT, UL_GAME_PORT, UL_DB_PORT   default 17171, 17172, 13306
#   UL_IDENTITIES   default extended,chaos
#   UL_GROUPS       default newplayer,temple,shop,shared,death,market,tester (the rift groups run last: its slots build a minute after the start)
#   UL_RESUME=1     keep the finished stages of an earlier run in UL_WORK (local work on this script)
#
# Modes (O433, the player on the same server: .github/workflows/unity-prototype.yml, unity/README.md "Player on a live server (CI)"):
#   (none)          the run above: Core.LiveCheck plays, reports, summary, the server goes down at the end
#   --serve-only    brings the server up (steps 1-3 and 5, no Core.LiveCheck), makes one fresh account and character per identity of
#                   UL_IDENTITIES, plus one more character per identity that never logged in (new_newbie, level 1), writes
#                   WORK/client-IDENTITY.env (mode 600, `export NAME=value` lines: CHAOS_LIVE_HOST, _PORT, _ACCOUNT, _PASSWORD,
#                   _CHARACTER, _IDENTITY, CHAOS_LIVE_NEW_ACCOUNT, _NEW_PASSWORD, _NEW_CHARACTER (the player smoke's new player first
#                   minute), CHAOS_CLIENT_KEY, CHAOS_RSA_PUBLIC; the player and Core.LiveCheck read those) and leaves tfs and MariaDB running detached (pid files in WORK/run). No secret is printed: only the paths of
#                   the files. UL_OUT is not needed. A second call on the same UL_WORK is not supported (use a new folder).
#   --stop          stops what --serve-only started (tfs, then MariaDB) and deletes the env files and the database password. Needs UL_WORK only.
#
# Secrets: none. The guard key of the Chaos identity is made here (openssl rand), given to tfs and Core.LiveCheck through
# the environment and thrown away with the work folder; a repository secret is not used (the server and the client are both
# ours, so the guard is checked in enforce mode with a key nobody else has). The RSA modulus comes from the base key.pem.
# The newplayer group needs no staff at all: a level 1 character that never logged in, the scenarios newplayer, questlog, firstunlock and firstkill (phases 27 and 28).
# firstunlock hunts the Rats to level 9, where every class opens Ghost Rope (about 35 s on fresh spawns, at most 170 s, a skip when the level is not reached). firstquest
# (25 rats, the teleport room, three scroll uses) and riftkilled (the local helper /rgive) are not run here.
# The tester group (phase 30) runs the tester bot checks of server/tools/tester_checks.py through the Unity core: the TEST ONLY helper of the tester bots
# (server/tools/tester_helper.lua, `!tester ...`) is copied into data/scripts of this run's server (install_tester_helper, before tfs starts) and acts for characters named
# "Tester Xxx" with the storage 7102900 = 1 only; the two characters of the run (a Beastmaster for Extended, a Necromancer for Chaos, and a Warrior partner) are made here with
# that name and storage, level 1500, the hunt spot in the rat cave. The helper is not part of the install and goes down with the work folder.
# Staff commands: the death, sharedkill and rift scenarios use stock staff commands (/goto, /m, /rift, /i) of staff accounts
# made in the database of this run. The riftboss scenario is not run: its /rkill and /rnear exist only as a local-only
# revscript (unity/README.md phase 23) and are not server data.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
MODE=run
case "${1:-}" in
  "") ;;
  --serve-only) MODE=serve ;;
  --stop) MODE=stop ;;
  *) echo "usage: [UL_* variables] $0 [--serve-only | --stop]" >&2; exit 2 ;;
esac

# --stop: what --serve-only left running goes down, the env files and the database password go. Nothing else is read.
if [ "$MODE" = stop ]; then
  : "${UL_WORK:?UL_WORK: the work folder of --serve-only}"
  [ -d "$UL_WORK/run" ] || { echo "no $UL_WORK/run: nothing to stop"; exit 0; }
  W=$(cd "$UL_WORK" && pwd)
  if [ -s "$W/run/tfs.pid" ]; then
    p=$(cat "$W/run/tfs.pid")
    if kill -0 "$p" 2>/dev/null; then
      kill -TERM "$p" 2>/dev/null || true
      for _ in $(seq 1 20); do kill -0 "$p" 2>/dev/null || break; sleep 1; done
      kill -KILL "$p" 2>/dev/null || true
    fi
    echo "tfs stopped"
  fi
  if [ -s "$W/run/mariadb.pid" ]; then
    p=$(cat "$W/run/mariadb.pid")
    sock=$(cat "$W/run/mariadb.sockpath" 2>/dev/null || echo "$W/run/mariadb.sock")
    if kill -0 "$p" 2>/dev/null; then
      mariadb-admin --no-defaults --socket="$sock" -uroot shutdown 2>/dev/null || true
      for _ in $(seq 1 20); do kill -0 "$p" 2>/dev/null || break; sleep 1; done
      kill -KILL "$p" 2>/dev/null || true
    fi
    echo "database stopped"
  fi
  rm -f "$W"/client-*.env "$W/.db-user"
  echo "env files and database password removed"
  exit 0
fi

if [ "$MODE" = serve ]; then
  : "${UL_ASSETS:?UL_ASSETS: checkout of windows-assets}" "${UL_WORK:?UL_WORK: work folder}"
  UL_OUT=${UL_OUT:-$UL_WORK/out}
else
  : "${UL_ASSETS:?UL_ASSETS: checkout of windows-assets}" "${UL_WORK:?UL_WORK: work folder}" "${UL_OUT:?UL_OUT: output folder}"
fi
ASSETS=$(cd "$UL_ASSETS" && pwd)
mkdir -p "$UL_WORK" "$UL_OUT"
WORK=$(cd "$UL_WORK" && pwd)
OUT=$(cd "$UL_OUT" && pwd)
LOGIN_PORT=${UL_LOGIN_PORT:-17171}
GAME_PORT=${UL_GAME_PORT:-17172}
DB_PORT=${UL_DB_PORT:-13306}
IDENTITIES=${UL_IDENTITIES:-extended,chaos}
GROUPS_TO_RUN=${UL_GROUPS:-newplayer,temple,shop,shared,death,market,tester}
SERVER="$WORK/server"
RUN="$WORK/run"
SOCK="$RUN/mariadb.sock"
# a Unix socket path may have at most 107 bytes: a deep UL_WORK puts it in a private temporary folder instead
if [ "$(printf %s "$SOCK" | wc -c)" -gt 100 ]; then SOCK="$(mktemp -d)/m.sock"; fi
SUMMARY_MD="$OUT/summary.md"
TIMES="$WORK/times.txt"

# Where the scenarios start. The map is the base map of windows-assets, so these are stable (unity/README.md phases 21-23).
TEMPLE_AT="32929,32073,7"         # beside the temple stair of the base town
NPC_NAME="Tesenna"; NPC_AT="32918,32075,7"
STAIRS_AT="32931,32077,7"
SELL_NPC="Solan";   SELL_AT="${UL_SELL_AT:-}"   # filled from the installed server's spawn list when empty
MARKET_AT="31672,32233,7"         # the hub market of Cinderhold, in front of Archivist Maelis (npc_booths_config.lua 31672,32236,7)
MARKET_NPC_AT="31672,32236,7"

mkdir -p "$RUN" && chmod 700 "$RUN"
: > "$TIMES"
log() { printf '== %s\n' "$*"; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }
t0=$SECONDS
mark() { printf '%s\t%s\n' "$1" "$((SECONDS - t0))" >> "$TIMES"; printf '   [%s: %ss]\n' "$1" "$((SECONDS - t0))"; t0=$SECONDS; }
stage_done() { [ "${UL_RESUME:-0}" = 1 ] && [ -f "$WORK/.done-$1" ]; }
stage_mark() { : > "$WORK/.done-$1"; }

TFS_PID=""
DB_PID=""
KEEP=0       # --serve-only, once the server is up: the processes stay, --stop ends them
DETACH=()    # --serve-only: tfs and MariaDB in their own session, so the end of this script and of the workflow step does not take them down
[ "$MODE" = serve ] && DETACH=(setsid)
cleanup() {
  set +e
  [ "$KEEP" = 1 ] && return
  if [ -n "$TFS_PID" ] && kill -0 "$TFS_PID" 2>/dev/null; then kill -TERM "$TFS_PID" 2>/dev/null; for _ in $(seq 1 20); do kill -0 "$TFS_PID" 2>/dev/null || break; sleep 1; done; kill -KILL "$TFS_PID" 2>/dev/null; fi
  if [ -n "$DB_PID" ] && kill -0 "$DB_PID" 2>/dev/null; then mariadb-admin --no-defaults --socket="$SOCK" -uroot shutdown 2>/dev/null; for _ in $(seq 1 20); do kill -0 "$DB_PID" 2>/dev/null || break; sleep 1; done; kill -KILL "$DB_PID" 2>/dev/null; fi
}
trap cleanup EXIT

rand_hex() { openssl rand -hex "$1"; }
dbq() { mariadb --no-defaults --socket="$SOCK" -uroot "$@"; }

# ---------------------------------------------------------------------------------------------------- 1. base server
prepare_base() {
  log "base server"
  (cd "$ASSETS" && sha256sum --ignore-missing -c SHA256SUMS.parts | grep -c ': OK$' | sed 's/^/   checked: /')
  rm -rf "$WORK/base" "$SERVER"
  mkdir -p "$WORK/base"
  tar -xJf "$ASSETS/server/base-server.tar.xz" -C "$WORK/base"
  [ "$(find "$WORK/base" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 1 ] || die "the base server archive does not hold exactly one folder"
  mv "$WORK"/base/*/ "$SERVER"
  rm -rf "$WORK/base"
  if [ -f "$ASSETS/world/MAP_MASTER.json" ]; then
    log "map master"
    python3 -I "$REPO/server/tools/map_master.py" install "$ASSETS/world" "$SERVER" --backup-dir "$WORK/mapbak" | sed 's/^/   /'
    [ "${PIPESTATUS[0]}" = 0 ] || die "the map master did not install"
  else
    echo "   no map master on this branch: the base map"
  fi
}

# ---------------------------------------------------------------------------------------------------- 2. database
start_db() {
  log "database (private MariaDB on 127.0.0.1:$DB_PORT)"
  local as_root=()
  [ "$(id -u)" -eq 0 ] && as_root=(--user=root)
  if [ ! -d "$WORK/db/mysql" ]; then
    mariadb-install-db --no-defaults "${as_root[@]}" --datadir="$WORK/db" --auth-root-authentication-method=normal --skip-test-db \
      > "$WORK/db-install.log" 2>&1 || { tail -n 20 "$WORK/db-install.log"; die "mariadb-install-db failed"; }
  fi
  ${DETACH[@]+"${DETACH[@]}"} mariadbd --no-defaults "${as_root[@]}" --datadir="$WORK/db" --socket="$SOCK" --pid-file="$RUN/mariadb.pid" \
    --port="$DB_PORT" --bind-address=127.0.0.1 --skip-name-resolve --log-error="$WORK/mariadb.err" \
    --innodb-buffer-pool-size=256M --max-allowed-packet=64M > /dev/null 2>&1 &
  DB_PID=$!
  printf '%s\n' "$SOCK" > "$RUN/mariadb.sockpath"   # --stop needs the socket (a deep UL_WORK moves it to a temporary folder)
  for _ in $(seq 1 60); do
    mariadb-admin --no-defaults --socket="$SOCK" -uroot ping > /dev/null 2>&1 && break
    kill -0 "$DB_PID" 2>/dev/null || { tail -n 20 "$WORK/mariadb.err"; die "mariadbd stopped"; }
    sleep 1
  done
  mariadb-admin --no-defaults --socket="$SOCK" -uroot ping > /dev/null 2>&1 || { tail -n 20 "$WORK/mariadb.err"; die "mariadbd did not start in 60 s"; }
  if [ ! -f "$WORK/.db-user" ]; then
    DBPASS=$(rand_hex 16)
    dbq -e "CREATE DATABASE chaos CHARACTER SET utf8mb4;
            CREATE USER 'chaos'@'127.0.0.1' IDENTIFIED BY '$DBPASS';
            GRANT ALL PRIVILEGES ON chaos.* TO 'chaos'@'127.0.0.1';"
    (umask 077; printf '%s\n' "$DBPASS" > "$WORK/.db-user")
  fi
  DBPASS=$(cat "$WORK/.db-user")
}

load_base_schema() {
  log "base schema"
  local f
  dbq chaos < "$SERVER/SQL_Server/schema.sql"
  for f in "$SERVER"/SQL_Server/schema_*.sql "$SERVER"/SQL_Server/sql_*.sql; do   # never the SQL_ONLY_for_existing_server file
    echo "   $(basename "$f")"
    dbq chaos < "$f"
  done
}

# ---------------------------------------------------------------------------------------------------- 3. config, install
write_config() {
  log "config.lua (ports $LOGIN_PORT/$GAME_PORT, database, client guard in enforce mode, no shutdown at the daily save)"
  python3 -I - "$SERVER/config.lua" "$LOGIN_PORT" "$GAME_PORT" "$DB_PORT" "$DBPASS" <<'PY'
import re, sys
path, login, game, dbport, dbpass = sys.argv[1:6]
text = open(path, encoding='latin-1').read()
want = {'ip': '"127.0.0.1"', 'loginProtocolPort': login, 'gameProtocolPort': game, 'statusProtocolPort': login,
        'mysqlHost': '"127.0.0.1"', 'mysqlUser': '"chaos"', 'mysqlPass': '"%s"' % dbpass, 'mysqlDatabase': '"chaos"',
        'mysqlPort': dbport, 'mysqlSock': '""'}
for key, value in want.items():
    text, n = re.subn(r'^(%s\s*=\s*)[^\r\n]*' % key, lambda m: m.group(1) + value, text, count=1, flags=re.M)
    if n != 1:
        sys.exit('config.lua: no %s line' % key)
# the guard: key from the environment of tfs (CHAOS_CLIENT_KEY), none in this file
# the daily server save (globalevents "Server Save", 08:00 server time) shuts the server down by default: a run that crosses it lost
# the server mid-scenario (PR 325, 2026-11-09: every run after 08:05 UTC could not log in). Save, but stay up and open.
for key, value in (('clientGuardMode', '"enforce"'), ('clientGuardKey', '""'), ('clientGuardAllowDevKey', 'false'),
                   ('serverSaveShutdown', 'false'), ('serverSaveClose', 'false')):
    text, n = re.subn(r'^(%s\s*=\s*)[^\r\n]*' % key, lambda m: m.group(1) + value, text, count=1, flags=re.M)
    if n == 0:
        text = text.rstrip('\n') + '\n%s = %s\n' % (key, value)
open(path, 'w', encoding='latin-1', newline='').write(text)
PY
}

install_chaos() {
  log "install_all.py of this checkout (steps, then the chaos_* tables on the database)"
  CHAOS_DB_PASS="$DBPASS" python3 -I "$REPO/server/tools/install_all.py" "$SERVER" --quiet > "$WORK/install.log" 2>&1 \
    || { tail -n 60 "$WORK/install.log"; die "install_all.py failed (log above)"; }
  tail -n 4 "$WORK/install.log" | sed 's/^/   /'
  [ -n "$(dbq chaos -N -e "SHOW TABLES LIKE 'chaos_%'")" ] || die "no chaos_* table after the install"
  echo "   chaos tables: $(dbq chaos -N -e "SHOW TABLES LIKE 'chaos_%'" | wc -l)"
}

# install_tester_helper: the TEST ONLY helper of the tester bots into data/scripts, as chaos-ctl.sh testers start does, only when the group `tester` runs. It acts for a character
# named "Tester Xxx" with the storage 7102900 = 1 and for no other (tester_helper_core.lua H.eligible), and it is never part of install_all.py.
install_tester_helper() {
  case ",$GROUPS_TO_RUN," in *,tester,*) ;; *) return 0 ;; esac
  [ -f "$REPO/server/tools/tester_helper.lua" ] && [ -f "$REPO/server/tools/tester_helper_core.lua" ] || die "server/tools/tester_helper.lua is missing"
  cp "$REPO/server/tools/tester_helper.lua" "$SERVER/data/scripts/zz_tester_helper.lua"
  cp "$REPO/server/tools/tester_helper_core.lua" "$SERVER/data/scripts/zz_tester_helper_core.lua"
  echo "   tester helper installed (TEST ONLY: data/scripts/zz_tester_helper*.lua)"
}

# ---------------------------------------------------------------------------------------------------- 4. engine
ENGINE_FROM=""
fetch_engine() {
  log "engine (tfs of the newest winpkg release with a Linux server)"
  local repo=${UL_ENGINE_REPO:-${GITHUB_REPOSITORY:-}} tag="" id="" tar=${UL_ENGINE_TAR:-}
  if [ -z "$tar" ]; then
    if [ -z "$repo" ]; then
      repo=$(git -C "$REPO" remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
    fi
    # REST only (gh release list is GraphQL): the releases come newest first
    while read -r t i; do
      tag=$t; id=$i; break
    done < <(gh api "repos/$repo/releases?per_page=30" --jq '.[] | select(.tag_name | startswith("winpkg-")) | .tag_name as $t | .assets[] | select(.name == "CindersOfChaos-Server-Linux.tar.gz") | "\($t) \(.id)"')
    [ -n "$tag" ] || die "no winpkg release with CindersOfChaos-Server-Linux.tar.gz in $repo"
    mkdir -p "$WORK/engine-dl"
    tar="$WORK/engine-dl/CindersOfChaos-Server-Linux.tar.gz"
    if ! gh release download "$tag" -R "$repo" -p CindersOfChaos-Server-Linux.tar.gz -D "$WORK/engine-dl" --clobber > /dev/null 2>&1; then
      echo "   gh release download failed, trying the REST asset download"
      gh api -H "Accept: application/octet-stream" "repos/$repo/releases/assets/$id" > "$tar"
    fi
    ENGINE_FROM="release $tag"
  else
    ENGINE_FROM="given file $(basename "$tar")"
  fi
  [ -s "$tar" ] || die "the engine archive is empty"
  # only the binary and its libraries (RUNPATH $ORIGIN/lib); the server folder of the archive is not used
  tar -xzf "$tar" -C "$SERVER" --strip-components=2 --wildcards '*/server/tfs' '*/server/lib/*'
  tar -xzf "$tar" -O --wildcards '*/BUILD_INFO.txt' 2>/dev/null | sed 's/^/   build info: /' | head -n 8 || true
  chmod 0755 "$SERVER/tfs"
  if ldd "$SERVER/tfs" 2>&1 | grep -q 'not found'; then ldd "$SERVER/tfs" | grep 'not found'; die "the engine lacks a library on this system"; fi
  echo "$ENGINE_FROM" > "$WORK/engine.txt"
  echo "   $ENGINE_FROM, tfs $(du -h "$SERVER/tfs" | cut -f1), lib $(ls "$SERVER/lib" | wc -l) files"
}

# ---------------------------------------------------------------------------------------------------- 5. server up
GUARD_KEY=""
start_tfs() {
  log "tfs"
  GUARD_KEY=$(rand_hex 32)
  if [ "$MODE" = serve ]; then
    CHAOS_CLIENT_KEY="$GUARD_KEY" setsid bash -c 'cd "$1" && exec ./tfs' _ "$SERVER" > "$WORK/tfs.log" 2>&1 < /dev/null &
  else
    ( cd "$SERVER" && CHAOS_CLIENT_KEY="$GUARD_KEY" exec ./tfs ) > "$WORK/tfs.log" 2>&1 &
  fi
  TFS_PID=$!
  printf '%s\n' "$TFS_PID" > "$RUN/tfs.pid"
  local up=0
  for _ in $(seq 1 360); do
    if ! kill -0 "$TFS_PID" 2>/dev/null; then tail -n 40 "$WORK/tfs.log"; die "tfs stopped while starting"; fi
    # online in the log and both ports taking connections (the log line can come before the listeners)
    if grep -q 'Server Online' "$WORK/tfs.log" 2>/dev/null && (exec 3<>"/dev/tcp/127.0.0.1/$GAME_PORT") 2>/dev/null \
       && (exec 3<>"/dev/tcp/127.0.0.1/$LOGIN_PORT") 2>/dev/null; then up=1; break; fi
    sleep 1
  done
  [ "$up" = 1 ] || { tail -n 40 "$WORK/tfs.log"; die "tfs is not online after 360 s"; }
  sleep 3
  grep -i -E 'ClientGuard|guard' "$WORK/tfs.log" | head -n 3 | sed 's/^/   /' || true
  echo "   online (login $LOGIN_PORT, game $GAME_PORT)"
  ss -ltn 2>/dev/null | grep -E ":($LOGIN_PORT|$GAME_PORT)\\b" | sed 's/^/   listening: /' || echo "   no listener on the two ports"
}

# ---------------------------------------------------------------------------------------------------- 6. accounts, runs
RUN_NO=0
PRIM_NAMES=(Aldric Brenna Corwin Dagna Edrik Fenna Garrick Hilda Ivor Joran Kestra Lorcan)
PART_NAMES=(Maeve Nolan Orla Perrin Quilla Rurik Sabine Tamsin Ulric Vesna Wynn Yara)
RESULTS="$WORK/results.tsv"   # run, identity, exit, report
ALL_SECRETS=()
: > "$RESULTS"

# find_npc NAME: x,y,z of an NPC in the spawn files of the installed map (spawn centre plus the entry's x and y offset), or nothing
find_npc() {
  python3 -I - "$SERVER/data/world" "$1" <<'PY'
import os, sys
import xml.etree.ElementTree as ET
world, name = sys.argv[1:3]
for fn in sorted(os.listdir(world)):
    if not fn.endswith('-spawn.xml'):
        continue
    for sp in ET.parse(os.path.join(world, fn)).getroot().iter('spawn'):
        for n in sp.iter('npc'):
            if n.get('name') == name:
                # the engine ignores the entry's z: an NPC stands on the spawn's floor
                print('%d,%d,%d' % (int(sp.get('centerx')) + int(n.get('x', 0)), int(sp.get('centery')) + int(n.get('y', 0)),
                                    int(sp.get('centerz'))))
                sys.exit(0)
PY
}

# beside POS X,Y,Z: one tile to the east
beside() { local x y z; IFS=, read -r x y z <<< "$1"; echo "$((x + 1)),$y,$z"; }

# new_chars GROUP: two fresh accounts and characters; sets PA PN PP (primary account, character, password) and QA QN QP (partner)
# new_newbie IDENTITY: one fresh account and character made the way the website makes one (level 1, 150 health, 0 mana, 400 capacity, position 0,0,0,
# lastlogin 0, no staff right, no tester row): the first login gives the start level, the kit, the welcome and the temple of Cinderhold. Sets PA PN PP; the
# partner of live_run is not used. The Extended identity gets a Warrior (vocation 4), the Chaos one a Mystic (vocation 1): a melee and a caster first spell.
new_newbie() {
  local id=$1 voc=4 look=128
  [ "$id" = chaos ] && voc=1
  RUN_NO=$((RUN_NO + 1))
  PA="lcn$RUN_NO$(rand_hex 3)"; QA=""; QN=""; QP=""
  local k=$((RUN_NO - 1)) tail_letter=(A B C D E F G H I J K L)
  PN="Live ${PRIM_NAMES[$((k % 12))]} ${tail_letter[$((k / 12))]}"
  PP=$(rand_hex 12)
  ALL_SECRETS+=("$PP")
  dbq chaos <<SQL
INSERT INTO accounts (name, password, type, creation) VALUES ('$PA', SHA1('$PP'), 1, UNIX_TIMESTAMP());
INSERT INTO players (name, group_id, account_id, vocation, level, experience, health, healthmax, mana, manamax, cap, soul,
                     sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, town_id, posx, posy, posz, lastlogin)
  SELECT '$PN', 1, id, $voc, 1, 0, 150, 150, 0, 0, 400, 100, 1, $look, 78, 68, 58, 76, 3, 2, 0, 0, 0, 0 FROM accounts WHERE name = '$PA';
SQL
}

# new_testers IDENTITY: the tester characters of the group `tester` (phase 30): a primary and a partner, each named "Tester Xxx" (the helper's name rule: Tester, a space, a capital and
# two lower case letters) with the storage 7102900 = 1 (the helper's marker; +2, +3, +4 are the hunt spot, the rat cave under Cinderhold, a safe place for level 1500), level 1500,
# 12000 health, 10500 mana, plain players (no staff right). The primary is a Beastmaster (Extended) or a Necromancer (Chaos), the two classes with summons; the partner a Warrior.
# Sets PA PN PP QA QN QP like new_chars.
TESTER_P=(Aka Bel Cor Dun Eld Fan Gor Hal Ivo Jun Kel Lor)
TESTER_Q=(Mar Nor Ola Per Qui Rur Sab Tam Ulr Ves Wyn Yar)
new_testers() {
  local id=$1 voc=15
  [ "$id" = chaos ] && voc=20
  RUN_NO=$((RUN_NO + 1))
  local k=$((RUN_NO - 1))
  PA="lct$RUN_NO$(rand_hex 3)"; QA="lcu$RUN_NO$(rand_hex 3)"
  PN="Tester ${TESTER_P[$((k % 12))]}"; QN="Tester ${TESTER_Q[$((k % 12))]}"
  PP=$(rand_hex 12); QP=$(rand_hex 12)
  ALL_SECRETS+=("$PP" "$QP")
  local px py pz
  IFS=, read -r px py pz <<< "$TEMPLE_AT"
  local exp
  exp=$(python3 -I -c 'L = 1500; print(50 * (L ** 3 - 6 * L ** 2 + 17 * L - 12) // 3)')
  dbq chaos <<SQL
INSERT INTO accounts (name, password, type, creation) VALUES ('$PA', SHA1('$PP'), 1, UNIX_TIMESTAMP()), ('$QA', SHA1('$QP'), 1, UNIX_TIMESTAMP());
INSERT INTO players (name, group_id, account_id, vocation, level, experience, health, healthmax, mana, manamax, maglevel, skill_fist, skill_club, skill_sword, skill_axe, skill_dist, skill_shielding,
                     cap, soul, sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, town_id, posx, posy, posz, lastlogin)
  SELECT '$PN', 1, id, $voc, 1500, $exp, 12000, 12000, 10500, 10500, 60, 130, 130, 130, 130, 130, 130, 40000, 100, 1, 128, 78, 68, 58, 76, 3, 2, $px, $py, $pz, 0 FROM accounts WHERE name = '$PA';
INSERT INTO players (name, group_id, account_id, vocation, level, experience, health, healthmax, mana, manamax, maglevel, skill_fist, skill_club, skill_sword, skill_axe, skill_dist, skill_shielding,
                     cap, soul, sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, town_id, posx, posy, posz, lastlogin)
  SELECT '$QN', 1, id, 4, 1500, $exp, 12000, 12000, 10500, 10500, 60, 130, 130, 130, 130, 130, 130, 40000, 100, 1, 128, 78, 68, 58, 76, 3, 2, $px, $py, $pz, 0 FROM accounts WHERE name = '$QA';
INSERT INTO player_storage (player_id, \`key\`, value) SELECT id, 7100252, 101 FROM players WHERE name IN ('$PN', '$QN');
INSERT INTO player_storage (player_id, \`key\`, value) SELECT id, 7102900, 1 FROM players WHERE name IN ('$PN', '$QN');
INSERT INTO player_storage (player_id, \`key\`, value) SELECT id, 7102902, 32369 FROM players WHERE name IN ('$PN', '$QN');
INSERT INTO player_storage (player_id, \`key\`, value) SELECT id, 7102903, 32214 FROM players WHERE name IN ('$PN', '$QN');
INSERT INTO player_storage (player_id, \`key\`, value) SELECT id, 7102904, 8 FROM players WHERE name IN ('$PN', '$QN');
SQL
}

# staff: primary, partner, both or none: the group's set-up. Level 1200 (experience of level 1200) so that every hunt, rift and
# shared experience rule applies; vocation 4 (Warrior); first login (lastlogin 0): the starter kit with gold, the tutorial skipped.
new_chars() {
  local primary_staff=$1 partner_staff=$2 pos=$3 ppos=$4
  RUN_NO=$((RUN_NO + 1))
  PA="lcp$RUN_NO$(rand_hex 3)"; QA="lcq$RUN_NO$(rand_hex 3)"
  # letters only in a name: a word of the list and, after twelve runs, a letter
  local k=$((RUN_NO - 1)) tail_letter=(A B C D E F G H I J K L)
  PN="Live ${PRIM_NAMES[$((k % 12))]} ${tail_letter[$((k / 12))]}"; QN="Live ${PART_NAMES[$((k % 12))]} ${tail_letter[$((k / 12))]}"
  PP=$(rand_hex 12); QP=$(rand_hex 12)
  ALL_SECRETS+=("$PP" "$QP")
  local px py pz qx qy qz pg=1 pt=1 qg=1 qt=1
  IFS=, read -r px py pz <<< "$pos"
  IFS=, read -r qx qy qz <<< "$ppos"
  [ "$primary_staff" = 1 ] && { pg=6; pt=6; }
  [ "$partner_staff" = 1 ] && { qg=6; qt=6; }
  # the password goes in on stdin, as a stock SHA-1 (re-hashed by the server at the first login); nothing is echoed
  dbq chaos <<SQL
INSERT INTO accounts (name, password, type, creation) VALUES ('$PA', SHA1('$PP'), $pt, UNIX_TIMESTAMP()), ('$QA', SHA1('$QP'), $qt, UNIX_TIMESTAMP());
INSERT INTO players (name, group_id, account_id, vocation, level, experience, health, healthmax, mana, manamax, cap, soul,
                     sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, town_id, posx, posy, posz, lastlogin)
  SELECT '$PN', $pg, id, 4, 1200, 28667831032, 10000, 10000, 3000, 3000, 60000, 100, 1, 128, 78, 68, 58, 76, 3, 2, $px, $py, $pz, 0 FROM accounts WHERE name = '$PA';
INSERT INTO players (name, group_id, account_id, vocation, level, experience, health, healthmax, mana, manamax, cap, soul,
                     sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, town_id, posx, posy, posz, lastlogin)
  SELECT '$QN', $qg, id, 4, 1200, 28667831032, 10000, 10000, 3000, 3000, 60000, 100, 1, 128, 78, 68, 58, 76, 3, 2, $qx, $qy, $qz, 0 FROM accounts WHERE name = '$QA';
INSERT INTO player_storage (player_id, \`key\`, value) SELECT id, 7100252, 101 FROM players WHERE name IN ('$PN', '$QN');
SQL
}

# live_run GROUP IDENTITY SCENARIOS [extra Core.LiveCheck arguments]  (characters made by new_chars first)
live_run() {
  local group=$1 identity=$2 scenarios=$3; shift 3
  local name="$group-$identity" rc=0
  echo "-- run $name: $scenarios"
  CHAOS_LIVE_PASSWORD="$PP" CHAOS_LIVE_ACCOUNT2="$QA" CHAOS_LIVE_PASSWORD2="$QP" CHAOS_LIVE_CHARACTER2="$QN" \
  CHAOS_CLIENT_KEY="$GUARD_KEY" CHAOS_RSA_PUBLIC="$RSA_PUBLIC" \
    timeout 1500 dotnet "$WORK/livecheck/Core.LiveCheck.dll" 127.0.0.1 "$LOGIN_PORT" "$PA" "$PN" --identity "$identity" \
      --otb "$SERVER/data/items/items.otb" --report "$OUT/$name.json" --scenario "$scenarios" --seconds 5 "$@" \
      > "$WORK/run-$name.out" 2>&1 || rc=$?
  tail -n 3 "$WORK/run-$name.out" | sed 's/^/   /'
  echo "   exit $rc"
  LAST_RC=$rc
  printf '%s\t%s\t%s\t%s\n' "$group" "$identity" "$rc" "$name.json" >> "$RESULTS"
}

# run_group_once GROUP IDENTITY: fresh characters, one Core.LiveCheck run. A failed first try is kept as "GROUP try1" and the
# group runs once more with new characters (the server is live: a refused step after a respawn is a flake, a real fault repeats).
run_group_once() {
  local g=$1 id=$2 label=$1
  case "$g" in
    temple)  # stock item tooltip, a stair and the floor change, NPC trade, a party of two (both plain players)
      new_chars 0 0 "$TEMPLE_AT" "$(beside "$TEMPLE_AT")"
      live_run "$label" "$id" tooltip,stairs,floorchange,npc,party --npc "$NPC_NAME" --npc-at "$NPC_AT" --stairs-at "$STAIRS_AT" ;;
    newplayer)  # a fresh character's first login (every packet and opcode of its first 45 s, the kit, the welcome, the outfit window), the base quest log (0xF0, 0xF1),
                # the first spell unlock by name (level 9) and its first kill with the first attack spell, the loot bag read and taken: no staff right, no local script.
                # The stairs and the cave are the base map of windows-assets.
      new_newbie "$id"
      live_run "$label" "$id" newplayer,questlog,purse,firstunlock,firstkill ;;
    tester)  # the tester bot checks of tools/tester_checks.py through the Unity core (phase 30): the TEST ONLY helper (install_tester_helper) answers for the two "Tester Xxx" characters.
             # The scenarios that need the second connection (the party ones) run last: its connection stays up and the multi-client rule would block the trial and dungeon legs before them.
             # The run order is the order of LiveRun.OptInScenarios, not of this list (Core.Tests checks that the party ones end it).
      new_testers "$id"
      live_run "$label" "$id" testsummons,testpets,testrift,testwaystone,testloot,testchests,testspellquest,testunique,testdual,testauto,testparty,testpartyxp --no-ext ;;
    shop)    # selling to an NPC that buys (the post office NPC does not)
      new_chars 0 0 "$SELL_AT" "$(beside "$SELL_AT")"
      live_run "$label" "$id" sell --npc "$SELL_NPC" --npc-at "$SELL_AT" ;;
    shared)  # shared experience: the partner (staff) summons, then gives its rights up through the admin panel
      new_chars 0 1 "$TEMPLE_AT" "$(beside "$TEMPLE_AT")"
      live_run "$label" "$id" sharedkill --stairs-at "$STAIRS_AT" ;;
    death)   # the partner (staff) kills the primary with a summoned monster
      new_chars 0 1 "$TEMPLE_AT" "$(beside "$TEMPLE_AT")"
      live_run "$label" "$id" death --stairs-at "$STAIRS_AT" ;;
    market)  # the modal window of Archivist Maelis, then a rift opened with a staff key (the primary is staff)
      new_chars 1 0 "$MARKET_AT" "$(beside "$MARKET_AT")"
      live_run "$label" "$id" modal,rift --modal-at "$MARKET_NPC_AT" ;;
    *) die "unknown group $g" ;;
  esac
}

run_groups() {
  local g id
  # a resumed work folder keeps the rows of an earlier run
  dbq chaos -e "DELETE FROM player_storage WHERE player_id IN (SELECT id FROM players WHERE name LIKE 'Live %');
                DELETE FROM players WHERE name LIKE 'Live %'; DELETE FROM accounts WHERE name LIKE 'lcp%' OR name LIKE 'lcq%' OR name LIKE 'lcn%';
                DELETE FROM player_storage WHERE player_id IN (SELECT id FROM players WHERE name LIKE 'Tester %');
                DELETE FROM players WHERE name LIKE 'Tester %'; DELETE FROM accounts WHERE name LIKE 'lct%' OR name LIKE 'lcu%';"
  for g in ${GROUPS_TO_RUN//,/ }; do
    for id in ${IDENTITIES//,/ }; do
      t0=$SECONDS
      LAST_RC=0
      run_group_once "$g" "$id"
      if [ "$LAST_RC" != 0 ]; then
        echo "   first try failed (exit $LAST_RC): once more with new characters"
        for f in json txt; do [ -f "$OUT/$g-$id.$f" ] && mv "$OUT/$g-$id.$f" "$OUT/$g-try1-$id.$f"; done
        sed -i '$d' "$RESULTS"
        printf '%s\t%s\t%s\t%s\n' "$g try1" "$id" "$LAST_RC" "$g-try1-$id.json" >> "$RESULTS"
        run_group_once "$g" "$id"
      fi
      mark "run $g $id"
    done
  done
}

# ---------------------------------------------------------------------------------------------------- 6b. --serve-only: accounts and env files
# serve_clients: one fresh account and character per identity (the first of each pair new_chars makes; the partner is not used) and one more that never logged in
# (new_newbie, level 1: the player smoke logs it in first, CHAOS_LIVE_NEW_*), each in a
# client-IDENTITY.env of mode 600 that a client sources (set -a). Values are written with printf %q; nothing goes to the terminal but the paths.
serve_clients() {
  log "accounts and env files (one per identity: $IDENTITIES)"
  dbq chaos -e "DELETE FROM player_storage WHERE player_id IN (SELECT id FROM players WHERE name LIKE 'Live %');
                DELETE FROM players WHERE name LIKE 'Live %'; DELETE FROM accounts WHERE name LIKE 'lcp%' OR name LIKE 'lcq%' OR name LIKE 'lcn%';"
  local id file
  for id in ${IDENTITIES//,/ }; do
    case "$id" in extended|chaos) ;; *) die "unknown identity $id" ;; esac
    new_chars 0 0 "$TEMPLE_AT" "$(beside "$TEMPLE_AT")"
    local main_a=$PA main_n=$PN main_p=$PP
    new_newbie "$id"   # one more, never logged in (the new player first minute of the player smoke, O433); it sets PA PN PP, the normal ones are kept above
    file="$WORK/client-$id.env"
    (
      umask 077
      {
        printf 'export CHAOS_LIVE_HOST=%q\n' 127.0.0.1
        printf 'export CHAOS_LIVE_PORT=%q\n' "$LOGIN_PORT"
        printf 'export CHAOS_LIVE_ACCOUNT=%q\n' "$main_a"
        printf 'export CHAOS_LIVE_PASSWORD=%q\n' "$main_p"
        printf 'export CHAOS_LIVE_CHARACTER=%q\n' "$main_n"
        printf 'export CHAOS_LIVE_NEW_ACCOUNT=%q\n' "$PA"
        printf 'export CHAOS_LIVE_NEW_PASSWORD=%q\n' "$PP"
        printf 'export CHAOS_LIVE_NEW_CHARACTER=%q\n' "$PN"
        printf 'export CHAOS_LIVE_IDENTITY=%q\n' "$id"
        printf 'export CHAOS_CLIENT_KEY=%q\n' "$GUARD_KEY"
        printf 'export CHAOS_RSA_PUBLIC=%q\n' "$RSA_PUBLIC"
      } > "$file"
    )
    chmod 600 "$file"
    echo "   $id: $file"
  done
}

# ---------------------------------------------------------------------------------------------------- 7. summary
write_summary() {
  python3 -I - "$RESULTS" "$OUT" "$TIMES" "$SUMMARY_MD" "$(cat "$WORK/engine.txt" 2>/dev/null || echo '?')" "${GITHUB_SHA:-$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo ?)}" <<'PY'
import json, os, sys
results, out, times, md_path, engine, commit = sys.argv[1:7]
rows = [l.rstrip('\n').split('\t') for l in open(results) if l.strip()]
lines = ['## Unity live check (O433)', '', 'Commit `%s`, engine from %s, guard in enforce mode with a key made for this run.' % (commit[:12], engine), '']
scen = {}     # (scenario) -> {identity: (status, reason)}
runs = []
retries = []
failed = False
for group, identity, rc, report in rows:
    path = os.path.join(out, report)
    data = None
    if os.path.isfile(path):
        try:
            data = json.load(open(path))
        except ValueError:
            data = None
    retried = group.endswith(' try1')   # a failed first try that was run again: shown, not counted
    ok = rc == '0'
    if not ok and not retried:
        failed = True
    if data is None:
        runs.append((group, identity, rc, 'no report', '', '', ''))
        continue
    login = data.get('login', {}).get('ok')
    enter = data.get('enter', {}).get('ok')
    walk = data.get('walk', {})
    parse = data.get('parse', {})
    runs.append((group, identity, rc, 'ok' if login else 'FAIL', 'ok' if enter else 'FAIL',
                 '%s of %s' % (walk.get('confirmed', 0) + walk.get('skipped', 0), walk.get('directions', 0)),
                 str(parse.get('errors', '?'))))
    for s in ([] if retried else data.get('scenarios', []) or []):
        scen.setdefault(s['name'], {})[identity] = (s['status'], s.get('reason', ''))
        if s['status'] == 'fail':
            failed = True
    if retried:
        fl = [x for x in data.get('scenarios', []) or [] if x['status'] == 'fail']
        retries.extend((group, identity, x['name'], x.get('reason', '')) for x in fl)
ids = sorted({r[1] for r in rows})
lines += ['| run | identity | exit | login | entry | walk | parse errors |', '|---|---|---|---|---|---|---|']
for r in runs:
    lines.append('| %s | %s | %s | %s | %s | %s | %s |' % r)
lines += ['', '| scenario | ' + ' | '.join(ids) + ' |', '|---|' + '---|' * len(ids)]
for name in sorted(scen):
    lines.append('| %s | %s |' % (name, ' | '.join(scen[name].get(i, ('not run', ''))[0] for i in ids)))
skips = [(n, i, v[1]) for n in sorted(scen) for i, v in sorted(scen[n].items()) if v[0] == 'skip']
fails = [(n, i, v[1]) for n in sorted(scen) for i, v in sorted(scen[n].items()) if v[0] == 'fail']
if retries:
    lines += ['', '### First tries that failed and passed or failed again on the second try'] + ['- %s (%s) %s: %s' % r for r in retries]
if fails:
    lines += ['', '### Failed'] + ['- **%s** (%s): %s' % f for f in fails]
if skips:
    lines += ['', '### Skipped'] + ['- %s (%s): %s' % s for s in skips]
lines += ['', '### Time per step', '', '| step | seconds |', '|---|---|']
for l in open(times):
    k, v = l.rstrip('\n').split('\t')
    lines.append('| %s | %s |' % (k, v))
text = '\n'.join(lines) + '\n'
open(md_path, 'w').write(text)
print(text)
sys.exit(1 if failed else 0)
PY
}

# ---------------------------------------------------------------------------------------------------- main
command -v mariadbd > /dev/null || die "mariadbd not found (apt-get install mariadb-server)"
[ "$MODE" = serve ] || command -v dotnet > /dev/null || die "dotnet not found"   # --serve-only builds no client

fresh=1
if stage_done install && [ -x "$SERVER/tfs" ]; then fresh=0; log "server folder and schema kept from an earlier run (UL_RESUME)"; fi
if [ "$fresh" = 1 ]; then prepare_base; mark "base server"; fi
start_db; mark "database up"
if [ "$fresh" = 1 ]; then
  load_base_schema; mark "base schema"
  write_config; install_chaos; mark "install_all"
  fetch_engine; mark "engine"
  stage_mark install
fi
write_config > /dev/null   # idempotent
RSA_PUBLIC=$(python3 -I "$REPO/server/tools/rsa_key.py" public --key "$SERVER/key.pem" 2>/dev/null | grep -E '^[0-9]+$' | tail -n 1 || true)
[ -n "$RSA_PUBLIC" ] || die "no RSA modulus from $SERVER/key.pem"

if [ "$MODE" != serve ]; then
  log "Core.LiveCheck build"
  dotnet build -c Release -o "$WORK/livecheck" "$REPO/unity/Core.LiveCheck" > "$WORK/dotnet-build.log" 2>&1 || { tail -n 30 "$WORK/dotnet-build.log"; die "Core.LiveCheck does not build"; }
  mark "dotnet build"
fi

install_tester_helper
start_tfs; mark "tfs start"

if [ "$MODE" = serve ]; then
  serve_clients
  KEEP=1
  log "serving: tfs pid $(cat "$RUN/tfs.pid"), login $LOGIN_PORT, game $GAME_PORT; stop it with: UL_WORK=$WORK bash tools/ci/unity_live_check.sh --stop"
  exit 0
fi

if [ -z "$SELL_AT" ]; then
  SELL_AT=$(find_npc "$SELL_NPC")
  [ -n "$SELL_AT" ] || die "no place for the NPC $SELL_NPC in the installed spawn files (UL_SELL_AT=X,Y,Z)"
  echo "   $SELL_NPC stands at $SELL_AT"
fi

rc=0
run_groups || rc=$?
log "summary"
write_summary || rc=1

# what goes into the artifact: the reports and the summary (written above), a tail of the server log. No key.pem, no
# config.lua, no database files. Passwords and the guard key are cut from every text file as a last guard.
tail -n 400 "$WORK/tfs.log" > "$OUT/tfs-log-tail.txt" || true
if [ -f "$SERVER/data/logs/clientguard.log" ]; then tail -n 200 "$SERVER/data/logs/clientguard.log" > "$OUT/clientguard-log-tail.txt" || true; fi
for secret in "$GUARD_KEY" "$DBPASS" "${ALL_SECRETS[@]}"; do
  [ -n "$secret" ] || continue
  grep -l -F -r -- "$secret" "$OUT" 2>/dev/null | while read -r f; do sed -i "s/$secret/<removed>/g" "$f"; done || true
done
exit "$rc"
