#!/usr/bin/env bash
# Record the tester bots' party fighting a pinnacle boss, Malgrath the Drowned Crown by default (O689, .github/workflows/boss-video.yml,
# server/README.md "Malgrath fight video (O689)"), from the MAIN client.
#
# usage: tools/ci/boss_video.sh GAME_DIR ENV_FILE PARTY_ENV OUT_DIR
#   GAME_DIR   the assembled and built client (init.lua, data, modules, the executable as chaos-client), RSA key and server host already set
#   ENV_FILE   client-chaos.env of `tools/ci/unity_live_check.sh --serve-only` with UL_PINNACLE_PARTY=1: the account of the SPECTATOR (a staff character)
#   PARTY_ENV  party.env of the same run: the five testers' names, their state folder, the key file, the database login of the run (never given to the client)
#   OUT_DIR    gets malgrath_fight.mp4 (the file is named after the boss), fight-report.txt, client-log.txt and server-console-tail.txt (account, password, key and database login cut out)
# Needs Xvfb, ffmpeg, ffprobe, python3. Software OpenGL, no sound device, the updater off (CHAOS_UPDATE_OFF).
#
# Two programs play at once. The tester bots (server/tools/testers.py run --checks --closed --only pinnacle_party) gear up, form a party at the Keeper of the
# Pinnacle and fight the boss; that preparation takes an hour or more. The client (module test_bosstour, armed by CHAOS_BOSSTOUR=1, never for a player) logs the
# spectator in, goes invisible, waits, and when `/instances pinnacle` lists the fight it jumps to a party member and writes "bosstour: ready". The recording starts
# on that line (x11grab of the virtual screen, libx264 crf 23, yuv420p, +faststart, an even size) and stops when the client writes "bosstour: done ..." (the boss
# fell, the fight is gone, or BV_SECONDS ran out) and exits; the only picture that leaves this script is that MP4: no frame, no screenshot, no sprite file.
# Then the bots are stopped and the fight report is written from their activity log and the client log.
#
# The bots run with --video (O689, second run): no hunting, no free activities (a bot whose check is done waits in the temple), the gather tried again inside the
# preparation time, members that wait for the leader to the end. The second run ended with the party never at the Keeper: the activity log pads the kind to 8 characters
# (`CHECK    SKIP`), so the grep for the bots' verdict below never matched and the run waited the two hours out. OUT_DIR also gets server-console-tail.txt: the
# last 300 lines of the server console (tfs log of party.env TESTERS_TFS_LOG) with the secrets cut and every line with a sensitive word dropped.
#
#   BV_SECONDS      the longest the fight is filmed, from the ready line (default 480, 30 to 900)
#   BV_PREP_WAIT    seconds from the start of the bots to the fight opening (default 7200: gear, trials, ascensions on foot, the party)
#   BV_CHECK_GRACE  seconds the script waits for the ready line after the bots' check wrote its verdict (default 120): a check that ended with no fight fails the run
#   BV_WIDTH, BV_HEIGHT (even), BV_DISPLAY, BV_TESTERS (the testers.py to run; tools/ci/boss_video_test.py runs the script with a fake one and a fake client)
set -euo pipefail

GAME=${1:?game dir}
ENVF=${2:?client env file}
PARTYF=${3:?party env file}
OUT=${4:?out dir}
W=${BV_WIDTH:-1280}
H=${BV_HEIGHT:-720}
SECS=${BV_SECONDS:-480}
PREP=${BV_PREP_WAIT:-7200}
GRACE=${BV_CHECK_GRACE:-120}
DISPLAY_NUM=${BV_DISPLAY:-98}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TESTERS=${BV_TESTERS:-$REPO/server/tools/testers.py}
REPORTER="$REPO/tools/ci/boss_video_report.py"

[ -x "$GAME/chaos-client" ] || { echo "no executable $GAME/chaos-client" >&2; exit 2; }
[ -f "$ENVF" ] || { echo "no env file $ENVF" >&2; exit 2; }
[ -f "$PARTYF" ] || { echo "no party env file $PARTYF" >&2; exit 2; }
[ -f "$TESTERS" ] || { echo "no testers script $TESTERS" >&2; exit 2; }
if ! [[ "$SECS" =~ ^[0-9]+$ ]] || [ "$SECS" -lt 30 ] || [ "$SECS" -gt 900 ]; then
  echo "BV_SECONDS must be a number from 30 to 900" >&2
  exit 2
fi
if ! [[ "$PREP" =~ ^[0-9]+$ ]] || [ "$PREP" -lt 60 ] || [ "$PREP" -gt 14400 ]; then
  echo "BV_PREP_WAIT must be a number from 60 to 14400" >&2
  exit 2
fi
if [ $((W % 2)) != 0 ] || [ $((H % 2)) != 0 ]; then
  echo "the size must be even: ${W}x${H}" >&2
  exit 2
fi
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
GAME=$(cd "$GAME" && pwd)
WORK=$(mktemp -d)
CLOG="$WORK/client.log"
TOUT="$WORK/testers.out"
SECRETS="$WORK/secrets.txt"
PIDS=()
FFPID=""

# the values a log must not show: the spectator's account and password, the guard key, the database login of the run
envvalue() {
  # shellcheck disable=SC1090
  ( . "$1" && printf '%s' "${!2:-}" )
}
(
  umask 077
  {
    envvalue "$ENVF" CHAOS_LIVE_ACCOUNT
    echo
    envvalue "$ENVF" CHAOS_LIVE_PASSWORD
    echo
    envvalue "$ENVF" CHAOS_CLIENT_KEY
    echo
    envvalue "$PARTYF" CHAOS_DB_PASS
    echo
  } > "$SECRETS"
)

BOSS=$(envvalue "$PARTYF" PARTY_BOSS)
LEVEL=$(envvalue "$PARTYF" PARTY_LEVEL)
NAMES=$(envvalue "$PARTYF" PARTY_NAMES)
STATE=$(envvalue "$PARTYF" TESTERS_STATE)
TFS_LOG=$(envvalue "$PARTYF" TESTERS_TFS_LOG)
if [ -z "$BOSS" ] || [ -z "$NAMES" ] || [ -z "$STATE" ]; then
  echo "party.env names no boss, party or state folder" >&2
  exit 2
fi
VIDEO="$OUT/${BOSS}_fight.mp4"

# the newest activity log of the bots' run (the file testers.py writes under its state folder)
newest_activity() {
  find "$STATE/runs" -maxdepth 1 -name 'run-*.log' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-
}

cleanup() {
  local p
  if [ -n "$FFPID" ]; then kill -INT "$FFPID" 2>/dev/null || true; fi
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT

# the logs of this run, cut: written at every exit path, so a failed run still leaves something to read
write_logs() {
  local activity="" secs=${1:-}
  activity=$(newest_activity || true)
  local sj=()
  [ -f "$STATE/state.json" ] && sj=(--state-json "$STATE/state.json")
  python3 -I "$REPORTER" redact --in "$CLOG" --secrets-file "$SECRETS" ${sj[@]+"${sj[@]}"} --out "$OUT/client-log.txt" || true
  if [ -n "$TFS_LOG" ] && [ -f "$TFS_LOG" ]; then
    python3 -I "$REPORTER" console --in "$TFS_LOG" --lines 300 --secrets-file "$SECRETS" ${sj[@]+"${sj[@]}"} --out "$OUT/server-console-tail.txt" || true
  fi
  python3 -I "$REPORTER" report --boss "$BOSS" --level "$LEVEL" --party "$NAMES" --activity "${activity:-/nonexistent}" --client-log "$CLOG" \
    --secrets-file "$SECRETS" ${sj[@]+"${sj[@]}"} ${secs:+--seconds "$secs"} --out "$OUT/fight-report.txt" || true
}

fail() {
  echo "$1" >&2
  tail -n 40 "$TOUT" 2>/dev/null | python3 -I "$REPORTER" redact --in /dev/stdin --secrets-file "$SECRETS" --out /dev/stderr || true
  write_logs
  tail -n 25 "$OUT/client-log.txt" >&2 || true
  exit 1
}

export DISPLAY=":$DISPLAY_NUM"
Xvfb "$DISPLAY" -screen 0 "${W}x${H}x24" -nolisten tcp > "$WORK/xvfb.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 50); do
  [ -S "/tmp/.X11-unix/X$DISPLAY_NUM" ] && break
  sleep 0.2
done
[ -S "/tmp/.X11-unix/X$DISPLAY_NUM" ] || { cat "$WORK/xvfb.log"; echo "Xvfb did not start" >&2; exit 1; }

# the tester bots: the pinnacle fight of the complete party. Their environment has the database login, the client's does not (and the reverse)
MINUTES=$(( (PREP + SECS + 900) / 60 + 1 ))
[ "$MINUTES" -le 1440 ] || MINUTES=1440
(
  set -a
  # shellcheck disable=SC1090
  . "$PARTYF"
  set +a
  exec python3 -I "$TESTERS" run --key-file "$TESTERS_KEY_FILE" --server-dir "$TESTERS_SERVER_DIR" --state "$TESTERS_STATE" \
    --host "$TESTERS_HOST" --port "$TESTERS_PORT" --log "$TESTERS_TFS_LOG" --checks --closed --only pinnacle_party --video --prep-minutes "$((PREP / 60))" --minutes "$MINUTES"
) > "$TOUT" 2>&1 &
TESTERS_PID=$!
PIDS+=("$TESTERS_PID")

# the client: its environment holds the spectator's account and password and the names of the party, nothing else of this script does
(
  set -a
  # shellcheck disable=SC1090
  . "$ENVF"
  set +a
  export CHAOS_BOSSTOUR=1 CHAOS_BOSSTOUR_FOLLOW="$NAMES" CHAOS_BOSSTOUR_BOSS="${BOSS^}" CHAOS_BOSSTOUR_SECONDS="$SECS" CHAOS_BOSSTOUR_WAIT="$PREP"
  export CHAOS_UPDATE_OFF=1 LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null HOME="$WORK/home"
  mkdir -p "$HOME"
  cd "$GAME"
  exec ./chaos-client
) > "$CLOG" 2>&1 &
CLIENT=$!
PIDS+=("$CLIENT")

# wait for the ready line: the bots gear up, ascend, play their trials, form the party and open the fight
echo "waiting for the fight (the bots prepare; at most $PREP s)"
ready=0
since_check=""
for i in $(seq 1 $(((PREP + 300) / 2))); do
  if grep -q 'bosstour: ready' "$CLOG" 2>/dev/null; then ready=1; break; fi
  kill -0 "$CLIENT" 2>/dev/null || fail "the client stopped before the fight opened"
  kill -0 "$TESTERS_PID" 2>/dev/null || fail "the tester bots stopped before the fight opened"
  if grep -q 'bosstour: done' "$CLOG" 2>/dev/null; then fail "the tour stopped before the fight opened"; fi
  # the bots' check can end without a fight (the party could not form, a bot could not play): the verdict line is in their activity log
  act=$(newest_activity || true)
  if [ -n "$act" ] && grep -qP ' CHECK +[A-Z]+ +pinnacle_party: (?!played as a member)' "$act" 2>/dev/null; then
    since_check=${since_check:-$i}
    if [ $((i - since_check)) -gt $((GRACE / 2)) ]; then fail "the bots' check ended and no fight opened: $(grep -P ' CHECK +[A-Z]+ +pinnacle_party: (?!played as a member)' "$act" | head -n 1 | cut -c1-300)"; fi
  fi
  if [ $((i % 150)) = 0 ]; then echo "   still preparing: $((i * 2)) s"; fi
  sleep 2
done
[ "$ready" = 1 ] || fail "no ready line in $((PREP + 300)) s"
echo "ready: recording at most $SECS s at ${W}x${H}"

ffmpeg -nostdin -loglevel error -y -f x11grab -draw_mouse 0 -framerate 30 -video_size "${W}x${H}" -i "$DISPLAY.0" -t $((SECS + 40)) \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart "$VIDEO" &
FFPID=$!
REC_AT=$SECONDS

# the tour ends the fight: "bosstour: done ..." and the exit of the client
for _ in $(seq 1 $(((SECS + 120) * 2))); do
  grep -q 'bosstour: done' "$CLOG" 2>/dev/null && break
  kill -0 "$CLIENT" 2>/dev/null || break
  kill -0 "$FFPID" 2>/dev/null || break
  sleep 0.5
done
for _ in $(seq 1 60); do
  kill -0 "$CLIENT" 2>/dev/null || break
  sleep 1
done
if kill -0 "$CLIENT" 2>/dev/null; then
  echo "the client was still running after the tour: stopped"
  kill "$CLIENT" 2>/dev/null || true
fi
RECORDED=$((SECONDS - REC_AT))
if kill -0 "$FFPID" 2>/dev/null; then kill -INT "$FFPID" 2>/dev/null || true; fi
wait "$FFPID" 2>/dev/null || true
FFPID=""
echo "recorded about $RECORDED s"

# the bots' verdict comes after the fight (they leave the arena and walk off first): give it time, then stop them (they log out and write their report)
for _ in $(seq 1 120); do
  act=$(newest_activity || true)
  if [ -n "$act" ] && grep -qP ' CHECK +[A-Z]+ +pinnacle_party: (?!played as a member)' "$act" 2>/dev/null; then break; fi
  kill -0 "$TESTERS_PID" 2>/dev/null || break
  sleep 2
done
if kill -0 "$TESTERS_PID" 2>/dev/null; then kill -TERM "$TESTERS_PID" 2>/dev/null || true; fi
for _ in $(seq 1 60); do
  kill -0 "$TESTERS_PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$TESTERS_PID" 2>/dev/null; then kill -KILL "$TESTERS_PID" 2>/dev/null || true; fi

write_logs "$RECORDED"
cat "$OUT/fight-report.txt"
grep 'bosstour:' "$OUT/client-log.txt" | tail -n 25 || true

grep -q 'bosstour: done ok' "$OUT/client-log.txt" || { echo "the tour did not end ok" >&2; exit 1; }
grep -q 'bosstour: ready' "$OUT/client-log.txt" || { echo "no ready line in the client log" >&2; exit 1; }
[ -s "$VIDEO" ] || { echo "no video" >&2; exit 1; }
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")
echo "video: $(du -h "$VIDEO" | cut -f1), ${dur} s"
awk -v d="$dur" 'BEGIN { exit !(d >= 3) }' || { echo "the video is shorter than 3 s: $dur s" >&2; exit 1; }
