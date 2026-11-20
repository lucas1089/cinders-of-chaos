#!/usr/bin/env bash
# Record the spell showcase: new spell effects, Forms and combos, from the MAIN client (O692, .github/workflows/spells-video.yml,
# server/README.md "Spell showcase video (O692)").
#
# usage: tools/ci/spells_video.sh GAME_DIR OUT_DIR ENV_FILE [ENV_FILE ...]
#   GAME_DIR   the assembled and built client (init.lua, data, modules, the executable as chaos-client), RSA key and server host already set
#   OUT_DIR    gets one CLASS.mp4 per class (elementalist.mp4, deadeye.mp4, illusionist.mp4), spells-report.txt and client-log-CLASS.txt (account,
#              password and guard key cut out)
#   ENV_FILE   spell-CLASS.env of `tools/ci/unity_live_check.sh --serve-only` with UL_SPELL_SHOWCASE=1: the account of a staff character of one
#              showcase class (CHAOS_LIVE_*, CHAOS_SPELLTOUR_CLASS, CHAOS_CLIENT_KEY), one per client run
# Needs Xvfb, ffmpeg, ffprobe, python3. Software OpenGL, no sound device, the updater off (CHAOS_UPDATE_OFF).
#
# One client run per class, one after the other on the same server (the pack helper of the server keeps monsters round whichever character is
# online). The client (module test_spelltour, armed by CHAOS_SPELLTOUR=1, never for a player) logs the staff character in, sets the spell ranks with
# `/spellrank ID 20`, writes "spelltour: ready", then plays its script: every shown spell with no Form, Form I A / B and Form II A / B, then the
# combos, a caption (pt-BR) over each cast, and writes "spelltour: done ..." and exits. The recording starts on the ready line (x11grab of the virtual
# screen, libx264 crf 20, yuv420p, +faststart, an even size) and stops with the done line. The only pictures that leave this script are those MP4s:
# no frame, no screenshot, no sprite file.
#
#   SV_SECONDS      the longest the film of one class is, from the ready line (default 900, 30 to 1800)
#   SV_READY_WAIT   seconds from the start of the client to the ready line (default 600: the login, the entry, the staff commands)
#   SV_WIDTH, SV_HEIGHT (even), SV_DISPLAY; SV_NO_VIDEO=1 for a dry run that films nothing
set -euo pipefail

GAME=${1:?game dir}
OUT=${2:?out dir}
shift 2
[ "$#" -ge 1 ] || { echo "no env file: usage spells_video.sh GAME_DIR OUT_DIR ENV_FILE..." >&2; exit 2; }
W=${SV_WIDTH:-1280}
H=${SV_HEIGHT:-720}
SECS=${SV_SECONDS:-900}
READY_WAIT=${SV_READY_WAIT:-600}
DISPLAY_NUM=${SV_DISPLAY:-97}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
REPORTER="$REPO/tools/ci/boss_video_report.py"

[ -x "$GAME/chaos-client" ] || { echo "no executable $GAME/chaos-client" >&2; exit 2; }
for f in "$@"; do
  [ -f "$f" ] || { echo "no env file $f" >&2; exit 2; }
done
if ! [[ "$SECS" =~ ^[0-9]+$ ]] || [ "$SECS" -lt 30 ] || [ "$SECS" -gt 1800 ]; then
  echo "SV_SECONDS must be a number from 30 to 1800" >&2
  exit 2
fi
if ! [[ "$READY_WAIT" =~ ^[0-9]+$ ]] || [ "$READY_WAIT" -lt 30 ] || [ "$READY_WAIT" -gt 3600 ]; then
  echo "SV_READY_WAIT must be a number from 30 to 3600" >&2
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
SECRETS="$WORK/secrets.txt"
PIDS=()
FFPID=""

# the values a log must not show: the accounts and passwords of the characters, the guard key
envvalue() {
  # shellcheck disable=SC1090
  ( . "$1" && printf '%s' "${!2:-}" )
}
(
  umask 077
  : > "$SECRETS"
  for f in "$@"; do
    for name in CHAOS_LIVE_ACCOUNT CHAOS_LIVE_PASSWORD CHAOS_CLIENT_KEY; do
      envvalue "$f" "$name" >> "$SECRETS"
      echo >> "$SECRETS"
    done
  done
)

cleanup() {
  local p
  if [ -n "$FFPID" ]; then kill -INT "$FFPID" 2>/dev/null || true; fi
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

REPORT="$OUT/spells-report.txt"
{
  echo "Spell showcase (O692): what each video shows"
  echo "  seconds limit per class: $SECS, screen ${W}x${H}"
} > "$REPORT"

# redact LOG -> OUT/client-log-CLASS.txt
cut_log() {
  python3 -I "$REPORTER" redact --in "$1" --secrets-file "$SECRETS" --out "$OUT/client-log-$2.txt" || true
}

fail() {
  echo "$1" >&2
  echo "FAILED: $1" >> "$REPORT"
  exit 1
}

total=0
for ENVF in "$@"; do
  CLASS=$(envvalue "$ENVF" CHAOS_SPELLTOUR_CLASS)
  [[ "$CLASS" =~ ^[a-z]+$ ]] || fail "$ENVF names no showcase class"
  CLOG="$WORK/client-$CLASS.log"
  VIDEO="$OUT/$CLASS.mp4"
  echo "== $CLASS"
  (
    set -a
    # shellcheck disable=SC1090
    . "$ENVF"
    set +a
    export CHAOS_SPELLTOUR=1 CHAOS_SPELLTOUR_SECONDS="$SECS"
    export CHAOS_UPDATE_OFF=1 LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null HOME="$WORK/home-$CLASS"
    mkdir -p "$HOME"
    cd "$GAME"
    exec ./chaos-client
  ) > "$CLOG" 2>&1 &
  CLIENT=$!
  PIDS+=("$CLIENT")

  # the login, the entry and the staff commands that set the ranks: the ready line
  ready=0
  for i in $(seq 1 $((READY_WAIT / 2))); do
    if grep -q 'spelltour: ready' "$CLOG" 2>/dev/null; then ready=1; break; fi
    if grep -q 'spelltour: done' "$CLOG" 2>/dev/null; then break; fi
    kill -0 "$CLIENT" 2>/dev/null || break
    if [ $((i % 60)) = 0 ]; then echo "   still waiting for the ready line: $((i * 2)) s"; fi
    sleep 2
  done
  if [ "$ready" != 1 ]; then
    cut_log "$CLOG" "$CLASS"
    tail -n 25 "$OUT/client-log-$CLASS.txt" >&2 || true
    fail "$CLASS: no ready line in $READY_WAIT s"
  fi
  echo "   ready: recording at most $SECS s at ${W}x${H}"

  REC_AT=$SECONDS
  if [ "${SV_NO_VIDEO:-0}" != 1 ]; then
    ffmpeg -nostdin -loglevel error -y -f x11grab -draw_mouse 0 -framerate 30 -video_size "${W}x${H}" -i "$DISPLAY.0" -t $((SECS + 60)) \
      -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -movflags +faststart "$VIDEO" &
    FFPID=$!
  fi

  # the tour ends the film: "spelltour: done ..." and the exit of the client
  for _ in $(seq 1 $(((SECS + 120) * 2))); do
    grep -q 'spelltour: done' "$CLOG" 2>/dev/null && break
    kill -0 "$CLIENT" 2>/dev/null || break
    if [ -n "$FFPID" ]; then kill -0 "$FFPID" 2>/dev/null || break; fi
    sleep 0.5
  done
  for _ in $(seq 1 60); do
    kill -0 "$CLIENT" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$CLIENT" 2>/dev/null; then
    echo "   the client was still running after the tour: stopped"
    kill "$CLIENT" 2>/dev/null || true
  fi
  RECORDED=$((SECONDS - REC_AT))
  if [ -n "$FFPID" ]; then
    if kill -0 "$FFPID" 2>/dev/null; then kill -INT "$FFPID" 2>/dev/null || true; fi
    wait "$FFPID" 2>/dev/null || true
    FFPID=""
  fi
  echo "   recorded about $RECORDED s"
  total=$((total + RECORDED))

  cut_log "$CLOG" "$CLASS"
  grep -q 'spelltour: done ok' "$OUT/client-log-$CLASS.txt" || { tail -n 25 "$OUT/client-log-$CLASS.txt" >&2 || true; fail "$CLASS: the tour did not end ok"; }
  if [ "${SV_NO_VIDEO:-0}" != 1 ]; then
    [ -s "$VIDEO" ] || fail "$CLASS: no video"
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")
    awk -v d="$dur" 'BEGIN { exit !(d >= 3) }' || fail "$CLASS: the video is shorter than 3 s: $dur s"
    echo "   video: $(du -h "$VIDEO" | cut -f1), ${dur} s"
  else
    dur=0
  fi

  # the report part of the class: what the video shows, from the client log
  {
    echo
    echo "$CLASS: ${dur%.*} s of video, recorded about $RECORDED s"
    grep -m1 'spelltour: class ' "$OUT/client-log-$CLASS.txt" | sed 's/^.*spelltour: /  /' || true
    echo "  casts: $(grep -c 'spelltour: cast ' "$OUT/client-log-$CLASS.txt" || true), picks: $(grep -c 'spelltour: pick ' "$OUT/client-log-$CLASS.txt" || true)"
    grep 'spelltour: caption ' "$OUT/client-log-$CLASS.txt" | sed 's/^.*spelltour: caption /    /' || true
    grep 'spelltour: no monster' "$OUT/client-log-$CLASS.txt" | sed 's/^.*spelltour: /  warning: /' | sort | uniq -c || true
  } >> "$REPORT"
done

echo "  total recorded about $total s" >> "$REPORT"
cat "$REPORT"
