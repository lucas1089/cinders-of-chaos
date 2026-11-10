#!/usr/bin/env bash
# Launch rehearsal on a shifted clock (O441, docs/LAUNCH.md "Launch rehearsal", server/README.md "Launch rehearsal (O441)").
# The launch date is the one value of server/data/scripts/chaos/launch_config.lua (O463). While it is "open" (no date, the owner's
# hold of 2026-11-10) there is nothing to rehearse: this script refuses before it starts anything, and says so. Set the date in
# launch_config.lua (docs/LAUNCH.md "Launch date: on hold"), install it, then run it. This runs the REAL server with the REAL committed configs under a shifted
# clock (libfaketime, TZ America/Sao_Paulo), a few minutes before each launch boundary, and reads what a player gets with a
# headless client (tools/ci/launch_rehearsal_probe.py). The dates, the plan and the decision of each check are in
# tools/ci/launch_rehearsal_core.py (unit test: launch_rehearsal_test.py, runs without a server).
#
# Checks (one OK / FAIL line each, observed values, no names, no passwords, no log lines):
#   start_line     the O439 start line shows the shifted local time and offset -180, no warning
#   founder        the Founder Pack is not in the store before the launch, is after, and goes four weeks later
#   season         Season 1 upcoming before 15:00, active after, one automatic start (log, broadcast)
#   season_once    a restart after the start: no second start, no reset of the season characters and their progress
#   pvp            PvP Season 1 not started before the epoch, running after, ends in the configured weeks
#   creator        the share of a donation by the instant it was credited: base, launch pct, launch pct, base
#   weekend        the Weekend Ritual is off before Fri 18:00, on after (announced once), on before Sun 23:59, off after
#   save           the 06:00 server save notice fires once at the crossing, then the engine stops once
#   launch_check   server/deploy/launch_check.py under the shifted clock: launch_date, the four date checks and the timezone are OK
#
# Where the server comes from (one of):
#   CI     UL_ASSETS=DIR (checkout of windows-assets) and LR_WORK=DIR: tools/ci/unity_live_check.sh --serve-only brings up a
#          real server and MariaDB in LR_WORK/base (as in unity-live-check.yml), this script stops that tfs, runs its own under
#          libfaketime, and calls unity_live_check.sh --stop at the end. Needs the same inputs as that script.
#   local  LR_SERVER=DIR (an installed server folder, install_all.py already run on this checkout), LR_DB_SOCK=FILE (a running
#          MariaDB with the database of config.lua, user root over the socket), LR_CRED_FILE=FILE (an env file with
#          CHAOS_LIVE_ACCOUNT, CHAOS_LIVE_PASSWORD, CHAOS_LIVE_CHARACTER; local test data only). Optional LR_DB_DUMP=FILE:
#          the database is dumped to it before and restored from it at the end (set it on a server you want back as it was).
# Other inputs: LR_WORK (work folder, never in the repository), LR_OUT (report folder, default LR_WORK/out), LR_ONLY=id,id (a
#   subset of the runs, for work on this script), LR_SAVE_TIME (default 06:00, the time the VPS setup gives the server save).
# libfaketime: apt-get install -y faketime (the package of Debian and Ubuntu). The rate is 1: the shifted clock runs at real speed
#   from the fake start, so every timer of the engine keeps its meaning; a boundary is crossed by waiting for it, not by speeding up.
# Database note: MariaDB stays on the real clock. The game compares a database NOW() or UNIX_TIMESTAMP() with os.time() nowhere in
#   the rehearsed systems (they store os.time() values); the seeds below are written as plain numbers, not with NOW().
# Output: the check lines, the report file (LR_OUT/launch-rehearsal-report.txt). Exit 1 on any FAIL. It stops tfs and, in CI mode,
#   the base server, always.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
CORE="$REPO/tools/ci/launch_rehearsal_core.py"
PROBE="$REPO/tools/ci/launch_rehearsal_probe.py"
die() { printf '::error::%s\n' "$*" >&2; exit 1; }
# the launch, from the checkout's launch_config.lua; "open" = no date = nothing to rehearse: refuse before anything starts
# (exit 3 of the core, its message is on stderr)
LAUNCH_AT=$(python3 -I "$CORE" launch --server "$REPO/server") || die "no launch date to rehearse (see above): set launch in server/data/scripts/chaos/launch_config.lua"
: "${LR_WORK:?LR_WORK: a work folder outside the repository}"
mkdir -p "$LR_WORK"
WORK=$(cd "$LR_WORK" && pwd)
OUT=${LR_OUT:-$WORK/out}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
OBS="$WORK/obs"
ZONE=America/Sao_Paulo
SAVE_TIME=${LR_SAVE_TIME:-06:00}

log() { printf '== %s\n' "$*"; }

TFS_PID=""
UL_BASE=""
SOCK=""
DBNAME=""
SERVER=""
PROBE_GROUP=""
SENT_ID=""
DUMP=${LR_DB_DUMP:-}
ASIDE="$WORK/aside"

dbq() { mariadb --no-defaults --socket="$SOCK" -uroot "$DBNAME" "$@"; }
dbn() { dbq -N -B -e "$1"; }
sqlq() { printf '%s' "${1//\'/\'\'}"; }

stop_tfs() {
  if [ -n "$TFS_PID" ] && kill -0 "$TFS_PID" 2>/dev/null; then
    kill -TERM "$TFS_PID" 2>/dev/null || true
    for _ in $(seq 1 60); do kill -0 "$TFS_PID" 2>/dev/null || break; sleep 1; done
    kill -KILL "$TFS_PID" 2>/dev/null || true
  fi
  TFS_PID=""
}

# shellcheck disable=SC2317,SC2329 # runs through the EXIT trap (older shellcheck reports SC2317)
cleanup() {
  local rc=$?
  trap - EXIT
  stop_tfs
  if [ -n "$SOCK" ] && [ -n "$DBNAME" ] && [ -S "$SOCK" ]; then
    # our own rows go whatever happens; a dump, when asked for, brings the whole database back
    dbq -e "DELETE FROM chaos_creator_uses WHERE order_id IN (SELECT id FROM chaos_coin_orders WHERE provider='rehearsal')" 2>/dev/null || true
    dbq -e "DELETE FROM chaos_coin_orders WHERE provider='rehearsal'; DELETE FROM chaos_creator_support WHERE code_id IN (SELECT id FROM chaos_creator_codes WHERE code='LRTEST'); DELETE FROM chaos_creator_codes WHERE code='LRTEST'" 2>/dev/null || true
    if [ -n "$SENT_ID" ]; then
      dbq -e "DELETE FROM chaos_season_progress WHERE player_id=$SENT_ID AND stat='lrsentinel'; DELETE FROM chaos_season_players WHERE player_id=$SENT_ID" 2>/dev/null || true
    fi
    if [ -n "$PROBE_GROUP" ] && [ -n "${CHAOS_LIVE_CHARACTER:-}" ]; then
      dbq -e "UPDATE players SET group_id=$PROBE_GROUP WHERE name='$(sqlq "$CHAOS_LIVE_CHARACTER")'" 2>/dev/null || true
    fi
    if [ -n "$DUMP" ] && [ -s "$DUMP" ]; then
      if dbq < "$DUMP" 2>/dev/null; then echo "   database restored from the dump"; else echo "   database restore FAILED"; fi
    fi
  fi
  if [ -d "$ASIDE" ] && [ -n "$SERVER" ]; then
    if [ -f "$ASIDE/globalevents.xml" ]; then cp -p "$ASIDE/globalevents.xml" "$SERVER/data/globalevents/globalevents.xml"; fi
    for f in "$ASIDE"/zz_*; do
      [ -e "$f" ] || continue
      mv -f "$f" "$SERVER/data/scripts/$(basename "$f")"
    done
  fi
  if [ -n "$UL_BASE" ]; then
    UL_WORK="$UL_BASE" bash "$REPO/tools/ci/unity_live_check.sh" --stop || true
  fi
  rm -f "${WORK:?}/etc-timezone" "${WORK:?}/localtime"
  exit "$rc"
}
trap cleanup EXIT

command -v faketime >/dev/null 2>&1 || die "faketime is not installed (apt-get install -y faketime)"
FT_LIB=""
for p in /usr/lib/x86_64-linux-gnu/faketime /usr/lib/faketime /usr/lib/aarch64-linux-gnu/faketime; do
  [ -e "$p/libfaketime.so.1" ] && FT_LIB="$p/libfaketime.so.1" && break
done
[ -n "$FT_LIB" ] || die "libfaketime.so.1 not found"

# ---------------------------------------------------------------------------------------------------- 1. the server
read_env() { tr -d '\r' < "$1" | sed -n "s/^\(export \)\{0,1\}$2=//p" | head -n 1 | sed "s/^['\"]//; s/['\"]\$//"; }

cfg_value() { tr -d '\r' < "$SERVER/config.lua" | sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\" ]*\).*/\1/p" | head -n 1; }

if [ -n "${LR_SERVER:-}" ]; then
  log "local server"
  SERVER=$(cd "$LR_SERVER" && pwd)
  SOCK=${LR_DB_SOCK:?LR_DB_SOCK: the MariaDB socket of the server}
  CRED=${LR_CRED_FILE:?LR_CRED_FILE: env file with the probe account}
  CHAOS_LIVE_ACCOUNT=$(read_env "$CRED" CHAOS_LIVE_ACCOUNT); [ -n "$CHAOS_LIVE_ACCOUNT" ] || CHAOS_LIVE_ACCOUNT=$(read_env "$CRED" ACCT)
  CHAOS_LIVE_PASSWORD=$(read_env "$CRED" CHAOS_LIVE_PASSWORD)
  CHAOS_LIVE_CHARACTER=$(read_env "$CRED" CHAOS_LIVE_CHARACTER); [ -n "$CHAOS_LIVE_CHARACTER" ] || CHAOS_LIVE_CHARACTER=$(read_env "$CRED" CHAR)
elif [ -n "${UL_ASSETS:-}" ]; then
  log "base server (unity_live_check.sh --serve-only)"
  UL_BASE="$WORK/base"
  UL_ASSETS="$UL_ASSETS" UL_WORK="$UL_BASE" UL_IDENTITIES=chaos bash "$REPO/tools/ci/unity_live_check.sh" --serve-only >/dev/null
  SERVER="$UL_BASE/server"
  SOCK=$(cat "$UL_BASE/run/mariadb.sockpath" 2>/dev/null || echo "$UL_BASE/run/mariadb.sock")
  CRED="$UL_BASE/client-chaos.env"
  CHAOS_LIVE_ACCOUNT=$(read_env "$CRED" CHAOS_LIVE_ACCOUNT)
  CHAOS_LIVE_PASSWORD=$(read_env "$CRED" CHAOS_LIVE_PASSWORD)
  CHAOS_LIVE_CHARACTER=$(read_env "$CRED" CHAOS_LIVE_CHARACTER)
  CHAOS_CLIENT_KEY=$(read_env "$CRED" CHAOS_CLIENT_KEY)
  export CHAOS_CLIENT_KEY
  # the tfs of the base server goes down: this script starts its own under the shifted clock
  if [ -s "$UL_BASE/run/tfs.pid" ]; then
    TFS_PID=$(cat "$UL_BASE/run/tfs.pid")
    stop_tfs
  fi
else
  die "give LR_SERVER (local) or UL_ASSETS (CI), see the header of this script"
fi
export CHAOS_LIVE_ACCOUNT CHAOS_LIVE_PASSWORD CHAOS_LIVE_CHARACTER
if [ -z "$CHAOS_LIVE_ACCOUNT" ] || [ -z "$CHAOS_LIVE_CHARACTER" ]; then die "no probe account in the env file"; fi
[ -x "$SERVER/tfs" ] || die "no tfs in the server folder"
[ -S "$SOCK" ] || die "no MariaDB socket"
DBNAME=$(cfg_value mysqlDatabase)
[ -n "$DBNAME" ] || die "no mysqlDatabase in config.lua"
LOGIN_PORT=$(cfg_value loginProtocolPort); LOGIN_PORT=${LOGIN_PORT:-7171}
GAME_PORT=$(cfg_value gameProtocolPort); GAME_PORT=${GAME_PORT:-7172}
if pgrep -x tfs >/dev/null 2>&1; then die "a tfs is already running on this machine"; fi
log "the plan, from the configs of the installed server"
[ "$(python3 -I "$CORE" launch --server "$SERVER")" = "$LAUNCH_AT" ] || die "the installed server has another launch date than the checkout (install_all.py again)"
PLAN=$(python3 -I "$CORE" plan --server "$SERVER" --save-time "$SAVE_TIME")
printf '%s\n' "$PLAN" | cut -f1,2 | sed 's/^/   /'

# ---------------------------------------------------------------------------------------------------- 2. prepare
if [ -n "$DUMP" ]; then
  mariadb-dump --no-defaults --socket="$SOCK" -uroot "$DBNAME" > "$DUMP" 2>/dev/null || die "the database dump failed"
  echo "   database dumped (restored at the end)"
fi
mkdir -p "$ASIDE" "$OBS"
rm -f "${OBS:?}"/*.json
# test-only files of the server folder (zz_*) go aside: the launch check would fail on them, and they are not the launch server
for f in "$SERVER"/data/scripts/zz_*; do
  [ -e "$f" ] || continue
  mv -f "$f" "$ASIDE/"
done
cp -p "$SERVER/data/globalevents/globalevents.xml" "$ASIDE/globalevents.xml"
# the daily save time, as the VPS setup gives it (server/tools/prod_config.py --save-time)
python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import prod_config; print("   " + prod_config.save_time(sys.argv[2], sys.argv[3], False))' \
  "$REPO/server/tools" "$SERVER" "$SAVE_TIME"
# the probe character is a staff character (group 4): "/weekend status" is a staff command
PROBE_GROUP=$(dbn "SELECT group_id FROM players WHERE name='$(sqlq "$CHAOS_LIVE_CHARACTER")'")
[ -n "$PROBE_GROUP" ] || die "the probe character is not in the database"
dbq -e "UPDATE players SET group_id=4 WHERE name='$(sqlq "$CHAOS_LIVE_CHARACTER")'"
# a character that is not the probe: the sentinel member of Season 1 (inserted after the start, looked for after a restart)
SENT_ID=$(dbn "SELECT id FROM players WHERE name<>'$(sqlq "$CHAOS_LIVE_CHARACTER")' ORDER BY id LIMIT 1")
SENT_ACC=$(dbn "SELECT account_id FROM players WHERE id=$SENT_ID")
[ -n "$SENT_ID" ] || die "no second character in the database"
dbq < "$REPO/server/sql/chaos_creator_codes.sql"
dbq < "$REPO/server/sql/chaos_season.sql"
# creator seeds: four credited donations of 1000 coins at the edges of the launch window (instants from the config, UTC-3)
CREATOR=$(python3 -I "$CORE" creator-instants --server "$SERVER")
CREATOR_ACC=$(dbn "SELECT id FROM accounts WHERE id NOT IN (SELECT account_id FROM chaos_creator_support) ORDER BY id LIMIT 1")
DONOR_ACC=$(dbn "SELECT id FROM accounts WHERE id<>$CREATOR_ACC AND id NOT IN (SELECT account_id FROM chaos_creator_support) ORDER BY id LIMIT 1")
if [ -z "$CREATOR_ACC" ] || [ -z "$DONOR_ACC" ]; then die "two accounts without a creator pick are needed"; fi
dbq -e "INSERT INTO chaos_creator_codes (code, account_id, pct, active, created_at) VALUES ('LRTEST', $CREATOR_ACC, 0, 1, 1)"
CODE_ID=$(dbn "SELECT id FROM chaos_creator_codes WHERE code='LRTEST'")
dbq -e "INSERT INTO chaos_creator_support (account_id, code_id, set_at, expires_at) VALUES ($DONOR_ACC, $CODE_ID, 1, 4000000000)"
while read -r name epoch; do
  dbq -e "INSERT INTO chaos_coin_orders (account_id, pack_key, provider, provider_ref, status, coins, created, credited) VALUES ($DONOR_ACC, 'rehearsal', 'rehearsal', 'lr-$name', 'credited', 1000, $epoch, $epoch)"
done <<< "$CREATOR"
echo "   seeds written (donations credited at the edges of the creator window)"

# ---------------------------------------------------------------------------------------------------- 3. the runs
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

start_tfs() { # id, fake start. Sets T0 (real unix time) and TFS_PID.
  T0=$(date +%s)
  # LD_PRELOAD and FAKETIME directly (the faketime wrapper script would keep a shell between us and tfs: no signal, no exit code)
  ( cd "$SERVER" && exec env TZ="$ZONE" LD_PRELOAD="$FT_LIB" FAKETIME="@$2" FAKETIME_DONT_FAKE_MONOTONIC=1 ./tfs ) > "$WORK/tfs-$1.log" 2>&1 < /dev/null &
  TFS_PID=$!
  local up=0
  for _ in $(seq 1 240); do
    if ! kill -0 "$TFS_PID" 2>/dev/null; then die "tfs stopped while starting (run $1)"; fi
    if grep -q 'Server Online' "$WORK/tfs-$1.log" 2>/dev/null && port_open "$GAME_PORT" && port_open "$LOGIN_PORT"; then up=1; break; fi
    sleep 1
  done
  [ "$up" = 1 ] || die "tfs is not online after 240 s (run $1)"
  ONLINE_AT=$(( $(date +%s) - T0 ))
  echo "   online $ONLINE_AT s after the start, fake clock at $2"
}

fact() { python3 -I "$CORE" setfact "$OBS/$1.json" "$2" "$3"; }

members_now() { dbn "SELECT COUNT(*) FROM chaos_season_players WHERE season=1 AND migrated_at=0"; }

season_db_facts() { # run id
  fact "$1" db_start_rows "$(dbn "SELECT COUNT(*) FROM chaos_season_log WHERE event='start' AND season=1")"
  fact "$1" db_end_rows "$(dbn "SELECT COUNT(*) FROM chaos_season_log WHERE event='end' AND season=1")"
  fact "$1" db_migrated_rows "$(dbn "SELECT COUNT(*) FROM chaos_season_players WHERE season=1 AND migrated_at>0")"
  fact "$1" sentinel_rows "$(dbn "SELECT COUNT(*) FROM chaos_season_players WHERE player_id=$SENT_ID AND season=1 AND migrated_at=0")"
  fact "$1" sentinel_value "$(dbn "SELECT COALESCE(MAX(value),-1) FROM chaos_season_progress WHERE player_id=$SENT_ID AND stat='lrsentinel'")"
  fact "$1" db_members "$(members_now)"
}

run_one() { # id, fake start, sample list, boundary seconds or -, exit wait
  local id=$1 start=$2 samples=$3 cross=$4 waitexit=$5
  log "run $id: fake start $start"
  printf '{"facts": {}, "samples": []}' > "$OBS/$id.json"
  # the runs are in time order; the probe character starts each one as if it had never been in the game (a last logout in the
  # future of the shifted clock would make its offline training negative: an artefact of rehearsing, not of the launch)
  dbq -e "UPDATE players SET lastlogin=0, lastlogout=0 WHERE name='$(sqlq "$CHAOS_LIVE_CHARACTER")'"
  start_tfs "$id" "$start"
  local stay=()
  [ "$waitexit" -gt 0 ] && stay=(--stay "$(( cross + waitexit ))")
  python3 -I "$PROBE" --server "$SERVER" --fake-start "$start" --t0 "$T0" --samples "$samples" --out "$OBS/$id.json" \
    --port "$LOGIN_PORT" --game-port "$GAME_PORT" "${stay[@]}" || echo "   the probe failed (see the facts)"
  if [ "$waitexit" -gt 0 ]; then
    # the server save stops the process by itself; wait for it past the notice period
    local until=$(( T0 + cross + waitexit ))
    while kill -0 "$TFS_PID" 2>/dev/null && [ "$(date +%s)" -lt "$until" ]; do sleep 1; done
    if kill -0 "$TFS_PID" 2>/dev/null; then
      fact "$id" exit_after null
    else
      fact "$id" exit_after "$(( $(date +%s) - T0 - cross ))"
      TFS_PID=""
    fi
  fi
  fact "$id" start_line "$(python3 -I "$CORE" startline "$WORK/tfs-$id.log")"
  local lf
  lf=$(python3 -I "$CORE" logfacts "$WORK/tfs-$id.log")
  for k in season_start_lines season_end_lines season_running_line season_members weekend_begin_lines lua_errors; do
    fact "$id" "$k" "$(printf '%s' "$lf" | python3 -I -c "import json,sys; print(json.dumps(json.load(sys.stdin)['$k']))")"
  done
  case "$id" in
    launch)
      fact "$id" members_before "$(members_now)"
      dbq -e "INSERT INTO chaos_season_players (player_id, account_id, season, joined_at) VALUES ($SENT_ID, $SENT_ACC, 1, 1)"
      dbq -e "INSERT INTO chaos_season_progress (season, player_id, stat, value, updated_at) VALUES (1, $SENT_ID, 'lrsentinel', 77, 1)"
      season_db_facts "$id"
      local shares="{}" n
      for n in before start last after; do
        shares=$(printf '%s' "$shares" | python3 -I -c "import json,sys; d=json.load(sys.stdin); d['$n']=$(dbn "SELECT COALESCE(MAX(u.share),-1) FROM chaos_creator_uses u JOIN chaos_coin_orders o ON o.id=u.order_id WHERE o.provider_ref='lr-$n'"); print(json.dumps(d))")
      done
      fact "$id" creator_shares "$shares"
      dbq -e "DELETE FROM chaos_creator_uses WHERE order_id IN (SELECT id FROM chaos_coin_orders WHERE provider='rehearsal')"
      dbq -e "DELETE FROM chaos_coin_orders WHERE provider='rehearsal'"
      ;;
    again)
      season_db_facts "$id"
      dbq -e "DELETE FROM chaos_season_progress WHERE player_id=$SENT_ID AND stat='lrsentinel'; DELETE FROM chaos_season_players WHERE player_id=$SENT_ID"
      SENT_ID=""
      ;;
  esac
  stop_tfs
}

ONLY=${LR_ONLY:-}
while IFS=$'\t' read -r id start samples cross waitexit; do
  [ -n "$id" ] || continue
  if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$id,"* ]]; then continue; fi
  run_one "$id" "$start" "$samples" "$cross" "$waitexit"
done <<< "$PLAN"

# ---------------------------------------------------------------------------------------------------- 4. launch check
log "launch check under the shifted clock"
echo "$ZONE" > "$WORK/etc-timezone"
ln -sf "/usr/share/zoneinfo/$ZONE" "$WORK/localtime"
FIRST_START=$(printf '%s\n' "$PLAN" | head -n 1 | cut -f2)
LC_JSON=$(TZ="$ZONE" CHAOS_TZ_ETC_TIMEZONE="$WORK/etc-timezone" CHAOS_TZ_LOCALTIME="$WORK/localtime" \
  faketime -f "@$FIRST_START" python3 -I "$REPO/server/deploy/launch_check.py" --server "$SERVER" --launch "$LAUNCH_AT" --json < /dev/null || true)
if [ -n "$LC_JSON" ]; then
  [ -s "$OBS/launch.json" ] || printf '{"facts": {}, "samples": []}' > "$OBS/launch.json"
  fact launch launch_check "$(printf '%s' "$LC_JSON" | python3 -I "$CORE" lcfacts)"
fi

# ---------------------------------------------------------------------------------------------------- 5. report
log "result"
rc=0
python3 -I "$CORE" decide --server "$SERVER" --obs "$OBS" --save-time "$SAVE_TIME" --report "$OUT/launch-rehearsal-report.txt" || rc=$?
echo "report: $OUT/launch-rehearsal-report.txt"
exit "$rc"
