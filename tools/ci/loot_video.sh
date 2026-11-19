#!/usr/bin/env bash
# Record the loot explosion (O669) from the MAIN client (O676, .github/workflows/loot-video.yml, server/README.md "Loot explosion (O669)").
#
# usage: tools/ci/loot_video.sh GAME_DIR ENV_FILE OUT_DIR
#   GAME_DIR  the assembled and built client (init.lua, data, modules, the executable as chaos-client), RSA key and server host already set
#   ENV_FILE  client-chaos.env of `tools/ci/unity_live_check.sh --serve-only` (UL_LOOT_TESTER=1): the account and the "Tester Xxx" character
#   OUT_DIR   gets loot_explosion.mp4 and client-log.txt (the client log with the account, the password and the guard key cut out)
# Needs Xvfb, ffmpeg, ffprobe. Software OpenGL, no sound device, the updater off (CHAOS_UPDATE_OFF).
#
# The client module test_loottour (armed by CHAOS_LOOTTOUR=1, never for a player) logs in, enters, writes "loottour: ready", says
# `!tester explode run` twice, presses Loot all, writes "loottour: done ok" and exits. The recording starts on the ready line and runs
# LV_SECONDS (default 20) seconds: x11grab of the virtual screen, libx264 crf 18, yuv420p, +faststart, an even size. The only picture
# that leaves this script is that MP4: no frame, no screenshot and no sprite file is written.
set -euo pipefail

GAME=${1:?game dir}
ENVF=${2:?env file}
OUT=${3:?out dir}
W=${LV_WIDTH:-1280}
H=${LV_HEIGHT:-720}
SECS=${LV_SECONDS:-20}
DISPLAY_NUM=${LV_DISPLAY:-99}
READY_WAIT=${LV_READY_WAIT:-480}   # seconds from the start of the client to the ready line (login, character list, entering)

[ -x "$GAME/chaos-client" ] || { echo "no executable $GAME/chaos-client" >&2; exit 2; }
[ -f "$ENVF" ] || { echo "no env file $ENVF" >&2; exit 2; }
if [ $((W % 2)) != 0 ] || [ $((H % 2)) != 0 ]; then
  echo "the size must be even: ${W}x${H}" >&2
  exit 2
fi
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
GAME=$(cd "$GAME" && pwd)
WORK=$(mktemp -d)
LOG="$WORK/client.log"
PIDS=()

cleanup() {
  local p
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT

export DISPLAY=":$DISPLAY_NUM"
Xvfb "$DISPLAY" -screen 0 "${W}x${H}x24" -nolisten tcp > "$WORK/xvfb.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 50); do
  [ -S "/tmp/.X11-unix/X$DISPLAY_NUM" ] && break
  sleep 0.2
done
[ -S "/tmp/.X11-unix/X$DISPLAY_NUM" ] || { cat "$WORK/xvfb.log"; echo "Xvfb did not start" >&2; exit 1; }

# the client: its environment holds the account and the password, nothing else of this script does
(
  set -a
  # shellcheck disable=SC1090
  . "$ENVF"
  set +a
  export CHAOS_LOOTTOUR=1 CHAOS_UPDATE_OFF=1 LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null HOME="$WORK/home"
  mkdir -p "$HOME"
  cd "$GAME"
  exec ./chaos-client
) > "$LOG" 2>&1 &
CLIENT=$!
PIDS+=("$CLIENT")

# redact: the log of the client without the account, the password and the guard key (all letters and digits)
envvalue() {
  # shellcheck disable=SC1090
  ( . "$ENVF" && printf '%s' "${!1:-}" )
}
redact() {
  local acct pass key
  acct=$(envvalue CHAOS_LIVE_ACCOUNT)
  pass=$(envvalue CHAOS_LIVE_PASSWORD)
  key=$(envvalue CHAOS_CLIENT_KEY)
  local args=() s
  for s in "$acct" "$pass" "$key"; do
    if [[ "$s" =~ ^[A-Za-z0-9]{6,}$ ]]; then args+=(-e "s/$s/<removed>/g"); fi
  done
  if [ "${#args[@]}" -gt 0 ]; then sed "${args[@]}" "$1"; else cat "$1"; fi
}

fail() {
  echo "$1" >&2
  redact "$LOG" | tail -n 60 >&2 || true
  redact "$LOG" > "$OUT/client-log.txt" || true
  exit 1
}

# wait for the ready line
ready=0
for _ in $(seq 1 $((READY_WAIT * 2))); do
  if grep -q 'loottour: ready' "$LOG" 2>/dev/null; then ready=1; break; fi
  kill -0 "$CLIENT" 2>/dev/null || fail "the client stopped before the ready line"
  if grep -q 'loottour: fail\|loottour: done' "$LOG" 2>/dev/null; then fail "the tour stopped before the ready line"; fi
  sleep 0.5
done
[ "$ready" = 1 ] || fail "no ready line in $READY_WAIT s"
echo "ready: recording $SECS s at ${W}x${H}"

ffmpeg -nostdin -loglevel error -y -f x11grab -draw_mouse 0 -framerate 30 -video_size "${W}x${H}" -i "$DISPLAY.0" -t "$SECS" \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -movflags +faststart "$OUT/loot_explosion.mp4"

# the tour ends with the exit of the client
for _ in $(seq 1 60); do
  kill -0 "$CLIENT" 2>/dev/null || break
  sleep 1
done
if kill -0 "$CLIENT" 2>/dev/null; then
  echo "the client was still running after the recording: stopped"
  kill "$CLIENT" 2>/dev/null || true
fi

redact "$LOG" > "$OUT/client-log.txt"
grep 'loottour:' "$OUT/client-log.txt" || true

grep -q 'loottour: done ok' "$OUT/client-log.txt" || { echo "the tour did not end ok" >&2; exit 1; }
for what in 'loottour: say !tester explode run' 'loottour: loot all sent'; do
  grep -q "$what" "$OUT/client-log.txt" || { echo "missing in the client log: $what" >&2; exit 1; }
done
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/loot_explosion.mp4")
echo "video: $(du -h "$OUT/loot_explosion.mp4" | cut -f1), ${dur} s"
awk -v d="$dur" -v s="$SECS" 'BEGIN { exit !(d >= s - 2) }' || { echo "the video is shorter than expected: $dur s" >&2; exit 1; }
