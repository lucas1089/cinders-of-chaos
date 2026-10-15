#!/bin/bash
# capture_login.sh CLIENT_DIR OUT.mp4 [pt-BR|en] [seconds]
# Records the live login scene of an assembled client (no server needed) on a private Xvfb display at 1920x1080, 30 fps.
# CLIENT_DIR: output of client/tools/assemble_client.sh with a sprite pair in data/things/1098. Needs Xvfb, ffmpeg, xdotool.
set -e
G=$(cd "$1" && pwd); OUT=$(realpath -m "$2"); LANG_=${3:-pt-BR}; SECS=${4:-14}
BIN=${CLIENT_BIN:-$(find "$G" -maxdepth 1 -type f -perm -u+x ! -name '*.sh' | head -1)}
D=${DISPLAY_NUM:-:823}; H=$(mktemp -d)
Xvfb $D -screen 0 1920x1080x24 >/dev/null 2>&1 & XP=$!
sleep 1
mkdir -p "$H/.local/share/otclientv8"
if [ "$LANG_" = en ]; then L="chaos-language: en\nlocale: en"; else L="chaos-language: pt-BR\nlocale: pt"; fi
printf "$L\nwindow-size: 1920 1080\nwindow-maximized: false\n" > "$H/.local/share/otclientv8/config.otml"
(cd "$G" && DISPLAY=$D HOME=$H ALSOFT_DRIVERS=null LIBGL_ALWAYS_SOFTWARE=1 "$BIN" >/dev/null 2>&1) & CP=$!; disown
sleep 25
DISPLAY=$D xdotool mousemove 1919 1079 || true
ffmpeg -v error -y -f x11grab -framerate 30 -video_size 1920x1080 -i $D -t "$SECS" \
  -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p "$OUT"
kill -9 $CP 2>/dev/null || true; pkill -9 -P $CP 2>/dev/null || true; kill $XP 2>/dev/null || true; rm -rf "$H"
echo "$OUT"
