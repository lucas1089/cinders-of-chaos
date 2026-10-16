#!/usr/bin/env bash
# Host trial: one run on a fresh VPS (Ubuntu or Debian, as root) that says KEEP, BORDERLINE, UPGRADE or REFUND.
# docs/HOST_TRIAL.md is the checklist (Portuguese). The work is done by host_trial.py next to this file.
#
#   sudo bash server/tools/host_trial.sh [--install-tools] [--quick] [--plan magic-sword|golden-boots] [--out DIR]
#                                        [any option of: python3 server/tools/host_trial.py run --help]
#   sudo bash server/tools/host_trial.sh load ...    the game server load test (host_trial_load.sh)
#
#   --install-tools   apt-get install -y fio luajit first (the only change to the system; optional: without fio a
#                     Python fsync loop measures the disk, without LuaJIT the Python and Lua loops measure the core)
#   --quick           a 3 minute rehearsal (window 2 min, 3 single-core runs); the real verdict needs the full run
#
# What it does: reads /proc and /sys; runs a niced CPU loop on every vCPU for the steal window (default 30 min) with a
# single-core benchmark pinned (taskset) to the last vCPU now and then; writes and deletes test files in a temp dir
# under --tmp (default /var/tmp, the root disk); pings a few public hosts in Brazil. Nothing else leaves the machine.
# Output: host_trial_report.txt and host_trial_report.json in --out (default: the current folder).
# Exit code: 0 KEEP, 1 BORDERLINE, 2 UPGRADE, 3 REFUND, other values: an error.
set -euo pipefail

HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

if [ "${1:-}" = "load" ]; then
  shift
  exec bash "$HERE/host_trial_load.sh" "$@"
fi

install=0
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --install-tools) install=1 ;;
    --quick) args+=(--window-min 2 --step-s 5 --bench-runs 3 --fio-runtime 15 --seq-mb 512 --ping-count 5) ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) args+=("$1") ;;
  esac
  shift
done

if [ "$(id -u)" -ne 0 ]; then
  echo "Run it as root (sudo). It needs root only for --install-tools and to read every /proc counter." >&2
  exit 10
fi
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) echo "Note: tested on Ubuntu and Debian; this is ${PRETTY_NAME:-unknown}." ;;
  esac
fi
command -v python3 >/dev/null || { echo "python3 is missing: apt-get install -y python3" >&2; exit 11; }

if [ $install -eq 1 ]; then
  echo "Installing fio and luajit (apt-get) ..."
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fio luajit
fi
command -v fio >/dev/null || echo "Note: fio is not installed; the disk is measured with a Python fsync loop (--install-tools adds fio)."
command -v taskset >/dev/null || echo "Note: taskset is missing (util-linux); the benchmark is pinned through Python instead."

echo "Host trial: started $(date '+%F %T'). Keep the session open (or run it inside screen / tmux)."
code=0
python3 -I "$HERE/host_trial.py" run "${args[@]}" || code=$?
case $code in
  0) echo "Verdict: KEEP" ;;
  1) echo "Verdict: BORDERLINE (run it again at another hour; docs/HOST_TRIAL.md decision table)" ;;
  2) echo "Verdict: UPGRADE (CPU and disk are fine; RAM or vCPU count is the limit)" ;;
  3) echo "Verdict: REFUND (bad CPU or disk; cancel before day 7)" ;;
  *) echo "The trial failed (exit $code)"; exit $code ;;
esac
exit $code
