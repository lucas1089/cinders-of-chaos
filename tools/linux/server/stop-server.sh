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

if alive "$RUN/start.pid"; then
  pid=$(cat "$RUN/start.pid")
  echo "Stopping the game server (it saves first)..."
  touch "$RUN/stop"
  kill -TERM "$pid" 2>/dev/null
  for _ in $(seq 1 200); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "start-server.sh (pid $pid) is still running after 200 seconds; the game server may still be saving."
    exit 1
  fi
elif alive "$RUN/server.pid"; then
  echo "Stopping the game server (it saves first)..."
  kill -TERM "$(cat "$RUN/server.pid")"
else
  echo "The game server was not running."
fi

if "$MDB/bin/mariadb-admin" --no-defaults --socket="$SOCK" -u "$ME" ping >/dev/null 2>&1; then
  "$MDB/bin/mariadb-admin" --no-defaults --socket="$SOCK" -u "$ME" shutdown && echo "Database stopped."
else
  echo "The database is not running."
fi
rm -f "$RUN/stop"
