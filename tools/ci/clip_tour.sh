#!/usr/bin/env bash
# Record the mechanics clips of the website (O687, website/README.md "Mechanics clips") from the MAIN client.
#
# usage: tools/ci/clip_tour.sh GAME_DIR ENV_FILE OUT_DIR
#   GAME_DIR  the assembled and built client (init.lua, data, modules, the executable as chaos-client), RSA key and server host already set
#   ENV_FILE  client-chaos.env of `tools/ci/unity_live_check.sh --serve-only` (UL_LOOT_TESTER=1): the account and the "Tester Xxx" character;
#             the same server also needs the test helper (tester_helper.lua) that run copies in
#   OUT_DIR   gets one <shot id>.mp4 per shot (the raw loop, 1920x1080), shots.txt and client-log.txt (the client log with the account, the
#             password and the guard key cut out)
# Environment: CLIP_SHOTS   comma list of shot ids (default all ten; ids: client/overlay/modules/test_cliptour/cliptourlogic.lua SHOTS)
#              CLIP_DRY=1   run the tour and log every answer, record nothing (the first run: it shows which staging line a shot needs fixed)
#              CLIP_WIDTH / CLIP_HEIGHT (1920x1080: the name blur boxes of gen_site_media.py are cut for it), CLIP_DISPLAY (99),
#              CLIP_READY_WAIT (480 s from the start of the client to the ready line), CLIP_TOUR_WAIT (900 s for the whole tour)
# Needs Xvfb, ffmpeg, ffprobe (not for CLIP_DRY=1: only Xvfb). Software OpenGL, no sound device, the updater off (CHAOS_UPDATE_OFF).
#
# The client module test_cliptour (armed by CHAOS_CLIPTOUR=1, never for a player) logs in, enters, writes "cliptour: ready" and plays the
# shots. On each line "cliptour: begin ID SECONDS" this script starts an x11grab of that many seconds into OUT_DIR/ID.mp4 (libx264 crf 18,
# yuv420p, no sound); the module waits LEAD_MS before the action, so the grab has started. The module ends with "cliptour: done ok" and exits.
# The only pictures that leave this script are those MP4 files: no frame, no screenshot and no sprite file is written.
# Next: copy OUT_DIR to SRC/rec/loops/ and run `python3 -I website/tools/gen_site_media.py --build-clips SRC` (encodes the site's clip-<id>.mp4
# and posters, blurs the test character's name, writes the manifest); commit those files.
set -euo pipefail

GAME=${1:?game dir}
ENVF=${2:?env file}
OUT=${3:?out dir}
W=${CLIP_WIDTH:-1920}
H=${CLIP_HEIGHT:-1080}
DISPLAY_NUM=${CLIP_DISPLAY:-99}
READY_WAIT=${CLIP_READY_WAIT:-480}
TOUR_WAIT=${CLIP_TOUR_WAIT:-900}
DRY=${CLIP_DRY:-0}

[ -x "$GAME/chaos-client" ] || { echo "no executable $GAME/chaos-client" >&2; exit 2; }
[ -f "$ENVF" ] || { echo "no env file $ENVF" >&2; exit 2; }
if [ $((W % 2)) != 0 ] || [ $((H % 2)) != 0 ]; then
  echo "the size must be even: ${W}x${H}" >&2
  exit 2
fi
if [ "$DRY" != 1 ]; then
  command -v ffmpeg >/dev/null || { echo "ffmpeg is not installed" >&2; exit 2; }
fi
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
GAME=$(cd "$GAME" && pwd)
WORK=$(mktemp -d)
LOG="$WORK/client.log"
PIDS=()
GRABS=()

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
  export CHAOS_CLIPTOUR=1 CHAOS_UPDATE_OFF=1 LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null HOME="$WORK/home"
  if [ -n "${CLIP_SHOTS:-}" ]; then export CHAOS_CLIPTOUR_SHOTS="$CLIP_SHOTS"; fi
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
  if grep -q 'cliptour: ready' "$LOG" 2>/dev/null; then ready=1; break; fi
  kill -0 "$CLIENT" 2>/dev/null || fail "the client stopped before the ready line"
  if grep -q 'cliptour: fail\|cliptour: done' "$LOG" 2>/dev/null; then fail "the tour stopped before the ready line"; fi
  sleep 0.5
done
[ "$ready" = 1 ] || fail "no ready line in $READY_WAIT s"
grep 'cliptour: tour' "$LOG" || true
echo "ready: ${W}x${H}, dry run: $DRY"

# follow the log: a begin line starts a grab of that shot, the done line ends the tour
seen=0
: > "$OUT/shots.txt"
for _ in $(seq 1 $((TOUR_WAIT * 5))); do
  total=$(wc -l < "$LOG")
  if [ "$total" -gt "$seen" ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ cliptour:\ begin\ ([a-z0-9-]+)\ ([0-9]+) ]]; then
        id=${BASH_REMATCH[1]}
        secs=${BASH_REMATCH[2]}
        echo "begin $id ($secs s)"
        if [ "$DRY" != 1 ]; then
          ffmpeg -nostdin -loglevel error -y -f x11grab -draw_mouse 0 -framerate 30 -video_size "${W}x${H}" -i "$DISPLAY.0" -t "$secs" \
            -an -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -movflags +faststart "$OUT/$id.mp4" &
          GRABS+=($!)
        fi
        echo "$id $secs" >> "$OUT/shots.txt"
      fi
    done < <(sed -n "$((seen + 1)),${total}p" "$LOG")
    seen=$total
  fi
  if grep -q 'cliptour: done' "$LOG" 2>/dev/null; then break; fi
  kill -0 "$CLIENT" 2>/dev/null || break
  sleep 0.2
done

# the grabs end by themselves (-t); the client ends with the tour
for p in "${GRABS[@]}"; do wait "$p" 2>/dev/null || true; done
for _ in $(seq 1 60); do
  kill -0 "$CLIENT" 2>/dev/null || break
  sleep 1
done
if kill -0 "$CLIENT" 2>/dev/null; then
  echo "the client was still running after the tour: stopped"
  kill "$CLIENT" 2>/dev/null || true
fi

redact "$LOG" > "$OUT/client-log.txt"
grep 'cliptour:' "$OUT/client-log.txt" || true

grep -q 'cliptour: done ok' "$OUT/client-log.txt" || { echo "the tour did not end ok" >&2; exit 1; }
# every shot that was said to begin has its file (not a dry run) and its length
bad=0
while read -r id secs; do
  [ -n "$id" ] || continue
  if [ "$DRY" = 1 ]; then continue; fi
  if [ ! -s "$OUT/$id.mp4" ]; then echo "missing: $id.mp4" >&2; bad=1; continue; fi
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$id.mp4")
  echo "$id: $(du -h "$OUT/$id.mp4" | cut -f1), ${dur} s"
  awk -v d="$dur" -v s="$secs" 'BEGIN { exit !(d >= s - 1) }' || { echo "$id is shorter than expected: $dur s" >&2; bad=1; }
done < "$OUT/shots.txt"
[ "$bad" = 0 ] || exit 1
echo "done: $(wc -l < "$OUT/shots.txt") shots in $OUT"
