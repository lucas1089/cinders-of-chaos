#!/bin/sh
# Starts the Cinders of Chaos client (Linux). Settings and logs go to ~/.local/share/ (the client's own folder there).
cd "$(dirname "$(readlink -f "$0")")" || exit 1
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "No graphical session (DISPLAY is not set). Start it from your desktop, or see README.txt for a headless run."
  exit 1
fi
# without any sound device OpenAL's device probe can stop the client at start: use its silent backend then
if [ -z "${ALSOFT_DRIVERS:-}" ] && [ ! -e /dev/snd ] && [ ! -S "${XDG_RUNTIME_DIR:-/nonexistent}/pulse/native" ]; then
  export ALSOFT_DRIVERS=null
fi
exec ./chaos-client "$@"
