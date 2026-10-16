#!/usr/bin/env bash
# Cinders of Chaos, Linux server package: stops the game server (it saves the players first; up to 3 minutes on a busy
# server) and then the database. Works for ./start-server.sh in a terminal and in the background (-d).
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

# waits up to 200 s for a process to end; the database is only stopped once the game server has saved and exited
wait_gone() {
  for _ in $(seq 1 200); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 1
  done
  return 1
}

db_was_up=0
db_up && db_was_up=1

if alive "$RUN/start.pid"; then
  pid=$(cat "$RUN/start.pid")
  echo "Stopping the game server (it saves first)..."
  touch "$RUN/stop"
  kill -TERM "$pid" 2>/dev/null
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
  kill -TERM "$pid" 2>/dev/null
  if ! wait_gone "$pid"; then
    echo "The game server (pid $pid) is still running after 200 seconds; it may still be saving."
    echo "The database is left running. Run ./stop-server.sh again once it has finished."
    exit 1
  fi
  rm -f "$RUN/server.pid"
else
  echo "The game server was not running."
fi

if db_up; then
  "$MDB/bin/mariadb-admin" --no-defaults --socket="$SOCK" -u "$ME" shutdown && echo "Database stopped."
elif [ $db_was_up -eq 1 ]; then
  echo "Database stopped (by start-server.sh, after the game server)."
else
  echo "The database is not running."
fi
rm -f "$RUN/stop"
