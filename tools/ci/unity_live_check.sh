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
#   UL_GROUPS       default temple,shop,shared,death,market (the rift groups run last: its slots build a minute after the start)
#   UL_RESUME=1     keep the finished stages of an earlier run in UL_WORK (local work on this script)
#
# Secrets: none. The guard key of the Chaos identity is made here (openssl rand), given to tfs and Core.LiveCheck through
# the environment and thrown away with the work folder; a repository secret is not used (the server and the client are both
# ours, so the guard is checked in enforce mode with a key nobody else has). The RSA modulus comes from the base key.pem.
# Staff commands: the death, sharedkill and rift scenarios use stock staff commands (/goto, /m, /rift, /i) of staff accounts
# made in the database of this run. The riftboss scenario is not run: its /rkill and /rnear exist only as a local-only
# revscript (unity/README.md phase 23) and are not server data.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
: "${UL_ASSETS:?UL_ASSETS: checkout of windows-assets}" "${UL_WORK:?UL_WORK: work folder}" "${UL_OUT:?UL_OUT: output folder}"
ASSETS=$(cd "$UL_ASSETS" && pwd)
mkdir -p "$UL_WORK" "$UL_OUT"
WORK=$(cd "$UL_WORK" && pwd)
OUT=$(cd "$UL_OUT" && pwd)
LOGIN_PORT=${UL_LOGIN_PORT:-17171}
GAME_PORT=${UL_GAME_PORT:-17172}
DB_PORT=${UL_DB_PORT:-13306}
IDENTITIES=${UL_IDENTITIES:-extended,chaos}
GROUPS_TO_RUN=${UL_GROUPS:-temple,shop,shared,death,market}
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
cleanup() {
  set +e
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
  mariadbd --no-defaults "${as_root[@]}" --datadir="$WORK/db" --socket="$SOCK" --pid-file="$RUN/mariadb.pid" \
    --port="$DB_PORT" --bind-address=127.0.0.1 --skip-name-resolve --log-error="$WORK/mariadb.err" \
    --innodb-buffer-pool-size=256M --max-allowed-packet=64M > /dev/null 2>&1 &
  DB_PID=$!
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
  log "config.lua (ports $LOGIN_PORT/$GAME_PORT, database, client guard in enforce mode)"
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
for key, value in (('clientGuardMode', '"enforce"'), ('clientGuardKey', '""'), ('clientGuardAllowDevKey', 'false')):
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
  ( cd "$SERVER" && CHAOS_CLIENT_KEY="$GUARD_KEY" exec ./tfs ) > "$WORK/tfs.log" 2>&1 &
  TFS_PID=$!
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
                DELETE FROM players WHERE name LIKE 'Live %'; DELETE FROM accounts WHERE name LIKE 'lcp%' OR name LIKE 'lcq%';"
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
command -v dotnet > /dev/null || die "dotnet not found"

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

log "Core.LiveCheck build"
dotnet build -c Release -o "$WORK/livecheck" "$REPO/unity/Core.LiveCheck" > "$WORK/dotnet-build.log" 2>&1 || { tail -n 30 "$WORK/dotnet-build.log"; die "Core.LiveCheck does not build"; }
mark "dotnet build"

start_tfs; mark "tfs start"

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
