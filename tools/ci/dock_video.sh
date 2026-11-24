#!/usr/bin/env bash
# Record the side dock (O732, client/MANIFEST.md "Side dock (O732)") from the MAIN client on a running server.
#
# usage: tools/ci/dock_video.sh GAME_DIR ENV_FILE OUT_DIR
#   GAME_DIR  the assembled and built client (init.lua, data, modules, the executable as chaos-client), server host already set
#   ENV_FILE  exports CHAOS_LIVE_ACCOUNT, CHAOS_LIVE_PASSWORD and CHAOS_LIVE_CHARACTER (a test account of a local or CI server)
#   OUT_DIR   gets dock.mp4, client-log.txt (account and password cut out) and stills/NAME.png cut from the video at the
#             tour's `still` lines
# Needs Xvfb, ffmpeg, xdotool. Software OpenGL, no sound device, the updater off (CHAOS_UPDATE_OFF).
#
# The client module test_docktour (armed by CHAOS_DOCKTOUR=1, never for a player) logs in, enters, writes "docktour: ready"
# and plays its steps. A line "docktour: key KEY" makes this script press KEY on the virtual screen with xdotool, so the
# dock's own key binding is what opens and closes it (the module calls the dock itself when the key did not work, and says
# so in the log). The recording runs from the ready line until the tour's exit (at most DV_SECONDS, default 120).
set -euo pipefail

GAME=${1:?game dir}
ENVF=${2:?env file}
OUT=${3:?out dir}
W=${DV_WIDTH:-1280}
H=${DV_HEIGHT:-720}
SECS=${DV_SECONDS:-120}
DISPLAY_NUM=${DV_DISPLAY:-98}
READY_WAIT=${DV_READY_WAIT:-480}

[ -x "$GAME/chaos-client" ] || { echo "no executable $GAME/chaos-client" >&2; exit 2; }
[ -f "$ENVF" ] || { echo "no env file $ENVF" >&2; exit 2; }
mkdir -p "$OUT/stills"
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

(
  set -a
  # shellcheck disable=SC1090
  . "$ENVF"
  set +a
  export CHAOS_DOCKTOUR=1 CHAOS_UPDATE_OFF=1 LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null HOME="$WORK/home"
  mkdir -p "$HOME"
  cd "$GAME"
  exec ./chaos-client
) > "$LOG" 2>&1 &
CLIENT=$!
PIDS+=("$CLIENT")

envvalue() {
  # shellcheck disable=SC1090
  ( . "$ENVF" && printf '%s' "${!1:-}" )
}
redact() {
  local args=() s
  for s in "$(envvalue CHAOS_LIVE_ACCOUNT)" "$(envvalue CHAOS_LIVE_PASSWORD)"; do
    if [[ "$s" =~ ^[A-Za-z0-9]{6,}$ ]]; then args+=(-e "s/$s/<removed>/g"); fi
  done
  if [ "${#args[@]}" -gt 0 ]; then sed "${args[@]}" "$1"; else cat "$1"; fi
}
fail() {
  echo "$1" >&2
  redact "$LOG" | grep -a 'docktour\|ERROR\|rror' | tail -n 40 >&2 || true
  redact "$LOG" > "$OUT/client-log.txt" || true
  exit 1
}

ready=0
for _ in $(seq 1 $((READY_WAIT * 2))); do
  if grep -aq 'docktour: ready' "$LOG" 2>/dev/null; then ready=1; break; fi
  kill -0 "$CLIENT" 2>/dev/null || fail "the client stopped before the ready line"
  if grep -aq 'docktour: done' "$LOG" 2>/dev/null; then fail "the tour stopped before the ready line"; fi
  sleep 0.5
done
[ "$ready" = 1 ] || fail "no ready line in $READY_WAIT s"
echo "ready: recording at ${W}x${H}"

ffmpeg -nostdin -loglevel error -y -f x11grab -draw_mouse 0 -framerate 30 -video_size "${W}x${H}" -i "$DISPLAY.0" -t "$SECS" \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -movflags +faststart "$WORK/raw.mp4" &
FF=$!
PIDS+=("$FF")

# the key lines: each one pressed once, in order
done_keys=0
while kill -0 "$CLIENT" 2>/dev/null; do
  mapfile -t keys < <(grep -a 'docktour: key [A-Za-z+]*$\|docktour: key [A-Za-z+]* @' "$LOG" | sed -E 's/.*docktour: key ([A-Za-z+]+).*/\1/')
  while [ "$done_keys" -lt "${#keys[@]}" ]; do
    k=${keys[$done_keys]}
    xk=$(printf '%s' "$k" | tr '[:upper:]' '[:lower:]')
    xdotool key --clearmodifiers "$xk" || true
    echo "pressed $k"
    done_keys=$((done_keys + 1))
  done
  sleep 0.2
done
sleep 1
kill -INT "$FF" 2>/dev/null || true
wait "$FF" 2>/dev/null || true
cp "$WORK/raw.mp4" "$OUT/dock.mp4"

redact "$LOG" > "$OUT/client-log.txt"
grep -a 'docktour:' "$OUT/client-log.txt" || true

# stills: the tour's `still NAME` lines carry their time from the ready line (@ms); the grab began about then
grep -a 'docktour: still ' "$OUT/client-log.txt" | sed -E 's/.*still ([a-z_]+):.* @([0-9]+)$/\1 \2/' | while read -r name ms; do
  ffmpeg -nostdin -loglevel error -y -ss "$(awk -v m="$ms" 'BEGIN { printf "%.2f", m / 1000 }')" -i "$OUT/dock.mp4" -frames:v 1 \
    "$OUT/stills/$name.png" || true
done
grep -aq 'docktour: done ok' "$OUT/client-log.txt" || { echo "the tour did not end ok" >&2; exit 1; }
echo "video: $(du -h "$OUT/dock.mp4" | cut -f1)"
