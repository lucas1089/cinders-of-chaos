#!/usr/bin/env bash
# Cinders of Chaos, Linux server package: stops the game server (it saves the players first; up to 3 minutes on a busy
# server) and then the database. Works for ./start-server.sh in a terminal and in the background (-d).
# The game server is asked first with a file, server/stop.request (it checks every few seconds, tells the players,
# saves and exits cleanly; server/README.md "Stop request file"); if it has not taken the file after REQUEST_WAIT
# seconds it gets SIGTERM, which saves too.
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
RUN="$ROOT/run"
MDB="$ROOT/mariadb"
SOCK="$RUN/mariadb.sock"
# a Unix socket path may have at most 107 bytes: deep folders put it in /tmp instead (named after this folder)
[ "$(printf %s "$SOCK" | wc -c)" -le 100 ] || SOCK="/tmp/chaos-mariadb-$(id -u)-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1).sock"
ME=$(id -un)

alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
db_up() { "$MDB/bin/mariadb-admin" --no-defaults --socket="$SOCK" -u "$ME" ping >/dev/null 2>&1; }

REQUEST_WAIT=20

# waits up to $2 s (200 by default) for a process to end; the database is only stopped once the game server has saved
# and exited
wait_gone() {
  for _ in $(seq 1 "${2:-200}"); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 1
  done
  return 1
}

db_was_up=0
db_up && db_was_up=1

# asks the running game server (pid $1) to save and stop through server/stop.request (a fixed file in this package's
# own server folder; its content is not read). Returns 0 once the server has taken the request (it removes the file,
# then saves, which may take minutes) or has exited; 1 when the file stayed for REQUEST_WAIT seconds (no answer: the
# caller sends SIGTERM)
request_stop() {
  local req="$ROOT/server/stop.request"
  : > "$req" 2>/dev/null || return 1
  for _ in $(seq 1 "$REQUEST_WAIT"); do
    { [ ! -e "$req" ] || ! kill -0 "$1" 2>/dev/null; } && return 0
    sleep 1
  done
  rm -f "$req"
  echo "No answer to server/stop.request after $REQUEST_WAIT seconds; sending SIGTERM instead."
  return 1
}

if alive "$RUN/start.pid"; then
  pid=$(cat "$RUN/start.pid")
  echo "Stopping the game server (it saves first)..."
  touch "$RUN/stop"
  # start-server.sh sees run/stop when the game server exits and does not start it again
  if ! { alive "$RUN/server.pid" && request_stop "$(cat "$RUN/server.pid")"; }; then
    kill -TERM "$pid" 2>/dev/null
  fi
  # start-server.sh stops the game server, waits for its save and exit, then stops the database it started itself
  if ! wait_gone "$pid"; then
    echo "start-server.sh (pid $pid) is still running after 200 seconds; the game server may still be saving."
    echo "The database is left running. Run ./stop-server.sh again once it has finished."
    exit 1
  fi
elif alive "$RUN/server.pid"; then
  # the game server without its start-server.sh (killed): wait for its save before the database goes
  pid=$(cat "$RUN/server.pid")
  echo "Stopping the game server (it saves first)..."
  request_stop "$pid" || kill -TERM "$pid" 2>/dev/null
  if ! wait_gone "$pid"; then
    echo "The game server (pid $pid) is still running after 200 seconds; it may still be saving."
    echo "The database is left running. Run ./stop-server.sh again once it has finished."
    exit 1
  fi
  rm -f "$RUN/server.pid"
else
  echo "The game server was not running."
fi

# the login-screen services (start-server.sh stops them itself; this is for a start-server.sh that was killed)
if alive "$RUN/clientservices.pid"; then
  kill "$(cat "$RUN/clientservices.pid")" 2>/dev/null && echo "Login-screen services stopped."
fi
rm -f "$RUN/clientservices.pid"
if alive "$RUN/helpai.pid"; then
  kill "$(cat "$RUN/helpai.pid")" 2>/dev/null && echo "Help channel assistant stopped."
fi
rm -f "$RUN/helpai.pid"

if db_up; then
  "$MDB/bin/mariadb-admin" --no-defaults --socket="$SOCK" -u "$ME" shutdown && echo "Database stopped."
elif [ $db_was_up -eq 1 ]; then
  echo "Database stopped (by start-server.sh, after the game server)."
else
  echo "The database is not running."
fi
rm -f "$RUN/stop"
