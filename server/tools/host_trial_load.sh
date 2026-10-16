#!/usr/bin/env bash
# Host trial, part 2: the game server load test on the rented VPS itself (docs/HOST_TRIAL.md, server/README.md
# "Load test on the full map"). Bots and server run on the same box and talk over 127.0.0.1 only.
#
#   sudo bash server/tools/host_trial_load.sh --pkg DIR [--counts 300,400] [--duration 600] [--ramp 0.5]
#                                             [--classes] [--out DIR] [--keep] [--cleanup-only]
#
#   --pkg DIR      the extracted Linux server package (CindersOfChaos-Server-Linux.tar.gz of a winpkg-<n> release),
#                  started once with ./start-server.sh so that chaos.env and the database exist
#   --counts       bot counts, one run each (default 300,400)
#   --duration     seconds at full load per run, after the ramp (default 600)
#   --classes      bots with area classes and their spell rotations (server/README.md "Load test with area
#                  classes"); default: level 100 bots that walk, talk and fight (setup --spread, run --hunt)
#   --keep         leave the bots, the test scripts and the test config in place (default: clean up at the end)
#   --cleanup-only only the clean up of an earlier run
#
# For each count: a mark line in logs/server.log, server/tools/loadtest.py run (with the probe's game loop lag, the
# engine's CPU per thread and RSS), host_trial.py sample (whole machine CPU without the bots, steal, MemAvailable,
# swap) and host_trial.py load-report (verdict). Output in --out: loadtest_<n>.txt, samples_<n>.jsonl,
# host_trial_load_<n>.txt / .json, and host_trial_load_report.txt with all counts.
# Test changes, all undone by the clean up: the TEST ONLY scripts server/tools/loadtest_probe.lua and loadtest_hunt.lua
# as data/scripts/zz_loadtest_*.lua; config.lua with slowTaskLogMs = 100 and maxPlayers = the largest count + 10
# (a copy is kept as config.lua.host-trial.bak); the loadbot accounts in the package database. Never run it against
# a server with real players.
set -euo pipefail

HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PKG=""
COUNTS="300,400"
DURATION=600
RAMP=0.5
CLASSES=0
OUT="$PWD/host_trial_load"
KEEP=0
ONLY_CLEAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pkg) PKG=$(readlink -f "$2"); shift ;;
    --counts) COUNTS=$2; shift ;;
    --duration) DURATION=$2; shift ;;
    --ramp) RAMP=$2; shift ;;
    --classes) CLASSES=1 ;;
    --out) OUT=$(readlink -f "$2"); shift ;;
    --keep) KEEP=1 ;;
    --cleanup-only) ONLY_CLEAN=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$PKG" ] || { echo "--pkg DIR is required (the extracted Linux server package)" >&2; exit 2; }
SRV="$PKG/server"
LOG="$PKG/logs/server.log"
CFG="$SRV/config.lua"
for f in "$SRV/tfs" "$PKG/start-server.sh" "$PKG/stop-server.sh" "$CFG"; do
  [ -e "$f" ] || { echo "not a Linux server package folder: $f is missing" >&2; exit 2; }
done
[ -f "$PKG/chaos.env" ] || { echo "start the package once first (./start-server.sh), so that chaos.env exists" >&2; exit 2; }
[[ $COUNTS =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "--counts must be numbers separated by commas" >&2; exit 2; }
MAX=$(tr ',' '\n' <<<"$COUNTS" | sort -n | tail -1)

set -a
# shellcheck disable=SC1091
. "$PKG/chaos.env"
set +a
# loadtest.py calls "mysql"; the package brings the MariaDB client under its own name
SHIM=""
if ! command -v mysql >/dev/null; then
  SHIM=$(mktemp -d)
  ln -s "$PKG/mariadb/bin/mariadb" "$SHIM/mysql"
  PATH="$SHIM:$PATH"
fi

LT=(python3 -I "$HERE/loadtest.py")
# shellcheck disable=SC2054  # the commas belong to the option values
CLASS_ARGS=(--classes "Elementalist:5,Berserker:4,Mystic:3,Beastmaster:3,Inquisitor:2,Bone Lord:2,Lich:1,Illusionist:1,Warrior:1,Deadeye:1,Thief:1,Monk:1,Samurai:1"
            --levels "100,300,600,1000" --server-data "$SRV")

running() { [ -f "$PKG/run/start.pid" ] && kill -0 "$(cat "$PKG/run/start.pid")" 2>/dev/null; }

restart_server() {
  if running; then
    echo "Stopping the game server (it saves) ..."
    (cd "$PKG" && ./stop-server.sh) || true
    for _ in $(seq 1 120); do running || break; sleep 1; done
  fi
  local offset
  offset=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
  (cd "$PKG" && ./start-server.sh -d)
  echo "Waiting for \"Server Online\" (the map takes a few minutes) ..."
  for _ in $(seq 1 900); do
    if tail -c +"$((offset + 1))" "$LOG" 2>/dev/null | grep -q "Server Online"; then
      echo "Server online."
      return 0
    fi
    sleep 1
  done
  echo "The server did not come online within 15 minutes: see $LOG" >&2
  return 1
}

set_config() {
  [ -f "$CFG.host-trial.bak" ] || cp -p "$CFG" "$CFG.host-trial.bak"
  python3 -I - "$CFG" "$((MAX + 10))" <<'PY'
import re, sys
path, maxp = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8', errors='surrogateescape').read()
for key, val in (('slowTaskLogMs', '100'), ('maxPlayers', maxp)):
    line = '%s = %s  -- host trial (server/tools/host_trial_load.sh); the clean up restores config.lua' % (key, val)
    text, n = re.subn(r'^[ \t]*%s[ \t]*=.*$' % key, lambda m: line, text, count=1, flags=re.M)
    if n == 0:
        text = text.rstrip('\n') + '\n' + line + '\n'
open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(text)
PY
}

cleanup() {
  echo "Clean up: bots, test scripts, config.lua ..."
  "${LT[@]}" cleanup || echo "loadtest.py cleanup failed: run it again with --cleanup-only" >&2
  rm -f "$SRV/data/scripts/zz_loadtest_probe.lua" "$SRV/data/scripts/zz_loadtest_hunt.lua"
  if [ -f "$CFG.host-trial.bak" ]; then
    mv -f "$CFG.host-trial.bak" "$CFG"
  fi
  restart_server || true
  [ -z "$SHIM" ] || rm -rf "$SHIM"
}

if [ $ONLY_CLEAN -eq 1 ]; then
  running || restart_server
  cleanup
  exit 0
fi

mkdir -p "$OUT"
cp "$HERE/loadtest_probe.lua" "$SRV/data/scripts/zz_loadtest_probe.lua"
cp "$HERE/loadtest_hunt.lua" "$SRV/data/scripts/zz_loadtest_hunt.lua"
set_config
[ $KEEP -eq 1 ] || trap cleanup EXIT
restart_server

echo "Creating $MAX bot characters ..."
"${LT[@]}" cleanup >/dev/null 2>&1 || true
if [ $CLASSES -eq 1 ]; then
  "${LT[@]}" setup --count "$MAX" "${CLASS_ARGS[@]}" --power 1.6
else
  "${LT[@]}" setup --count "$MAX" --spread "$SRV/data/chaos_poi.lua"
fi

KEY=()
[ -f "$SRV/key.pem" ] && KEY=(--key "$SRV/key.pem")
: > "$OUT/host_trial_load_report.txt"
worst=0
for n in ${COUNTS//,/ }; do
  pid=$(cat "$PKG/run/server.pid")
  mark=$(date +%s)
  echo "[host-trial-mark $mark] load test with $n bots" >> "$LOG"
  echo "== $n bots: ramp $RAMP s apart, then $DURATION s at full load"
  run=(run --count "$n" --host 127.0.0.1 --port 7171 --duration "$DURATION" --ramp "$RAMP" --hunt
       --server-pid "$pid" --server-log "$LOG" "${KEY[@]}")
  [ $CLASSES -eq 0 ] || run+=("${CLASS_ARGS[@]}" --pull "8,6")
  "${LT[@]}" "${run[@]}" > "$OUT/loadtest_$n.txt" 2>&1 &
  ltpid=$!
  rm -f "$OUT/samples_$n.jsonl"
  python3 -I "$HERE/host_trial.py" sample "$OUT/samples_$n.jsonl" --step-s 5 --exclude-pid "$ltpid" &
  smppid=$!
  wait "$ltpid" || echo "loadtest.py ended with an error: see $OUT/loadtest_$n.txt"
  kill -TERM "$smppid" 2>/dev/null || true
  wait "$smppid" 2>/dev/null || true
  tail -n 25 "$OUT/loadtest_$n.txt"
  code=0
  python3 -I "$HERE/host_trial.py" load-report --count "$n" --loadtest-out "$OUT/loadtest_$n.txt" \
    --samples "$OUT/samples_$n.jsonl" --server-log "$LOG" --since "$mark" --out "$OUT" || code=$?
  [ $code -le 3 ] || { echo "load-report failed (exit $code)" >&2; exit $code; }
  [ $code -le $worst ] || worst=$code
  cat "$OUT/host_trial_load_$n.txt" >> "$OUT/host_trial_load_report.txt"
  echo "Cooling down for 60 s (the bots' logout saves) ..."
  sleep 60
done
echo "Load test done. Send $OUT/host_trial_load_report.txt (no IPs or passwords in it)."
exit $worst
