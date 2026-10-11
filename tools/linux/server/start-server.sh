#!/usr/bin/env bash
# Cinders of Chaos, Linux server package: starts the database (the package's own MariaDB on 127.0.0.1:3307) and the
# game server, and keeps the game server running (it is started again after the daily server save and after a crash).
#
#   ./start-server.sh        in this terminal; Ctrl+C stops the game server (it saves) and the database
#   ./start-server.sh -d     in the background, output in logs/server.log; ./stop-server.sh stops it
#
# The first start creates the database in database/ (about a minute): the game database "chaos", a database user
# "chaos" with a random password (written to chaos.env, which config.lua reads) and a staff account with a random
# password (first-start-account.txt). CHAOS_TEST_ACCOUNTS=1 ./start-server.sh at the first start also loads the test
# accounts of the Windows package (chaos/chaos, test/test: known passwords, local play only).
set -euo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MDB="$ROOT/mariadb"
DATA="$ROOT/database"
RUN="$ROOT/run"
LOGS="$ROOT/logs"
SOCK="$RUN/mariadb.sock"
# a Unix socket path may have at most 107 bytes: deep folders put it in /tmp instead (named after this folder)
[ "$(printf %s "$SOCK" | wc -c)" -le 100 ] || SOCK="/tmp/chaos-mariadb-$(id -u)-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1).sock"
ENVF="$ROOT/chaos.env"
ME=$(id -un)

if [ "${1:-}" = "-d" ] || [ "${1:-}" = "--background" ]; then
  mkdir -p "$LOGS"
  setsid nohup "$ROOT/start-server.sh" >> "$LOGS/server.log" 2>&1 < /dev/null &
  echo "Started in the background (pid $!). Log: logs/server.log   Stop: ./stop-server.sh"
  echo "Wait for \"Server Online\" in the log before you log in:  tail -f logs/server.log"
  exit 0
fi

mkdir -p "$RUN" "$LOGS"
chmod 700 "$RUN"
if [ -f "$RUN/start.pid" ] && kill -0 "$(cat "$RUN/start.pid")" 2>/dev/null; then
  echo "Already running (pid $(cat "$RUN/start.pid")). Stop it with ./stop-server.sh first."
  exit 1
fi
echo $$ > "$RUN/start.pid"
echo "$SOCK" > "$RUN/socket.txt"
rm -f "$RUN/stop"

for f in "$MDB/bin/mariadbd" "$ROOT/server/tfs"; do
  [ -x "$f" ] || { echo "Missing: $f (extract the whole archive, keep the folder layout)"; exit 1; }
done

sql() {  # the database's admin account is this system user, over the socket only (unix_socket authentication)
  "$MDB/bin/mariadb" --no-defaults --socket="$SOCK" -u "$ME" "$@"
}

db_up() {
  "$MDB/bin/mariadb-admin" --no-defaults --socket="$SOCK" -u "$ME" ping >/dev/null 2>&1
}

# ---- database
started_db=0
if [ ! -d "$DATA/mysql" ]; then
  echo "First start: creating the database folder (database/)..."
  "$MDB/scripts/mariadb-install-db" --no-defaults --basedir="$MDB" --datadir="$DATA" \
    --auth-root-authentication-method=socket --auth-root-socket-user="$ME" --skip-test-db \
    >> "$LOGS/database-setup.log" 2>&1 || { echo "mariadb-install-db failed: see logs/database-setup.log"; exit 1; }
fi
if ! db_up; then
  echo "Starting the database (127.0.0.1:3307)..."
  as_root=()
  [ "$(id -u)" -eq 0 ] && as_root=(--user=root)
  "$MDB/bin/mariadbd" --no-defaults "${as_root[@]}" --basedir="$MDB" --datadir="$DATA" \
    --plugin-dir="$MDB/lib/plugin" --lc-messages-dir="$MDB/share" --socket="$SOCK" --pid-file="$RUN/mariadb.pid" \
    --port=3307 --bind-address=127.0.0.1 --skip-name-resolve --log-error="$LOGS/mariadb.err" \
    --innodb-buffer-pool-size=256M --max-allowed-packet=64M &
  started_db=1
  for _ in $(seq 1 60); do
    db_up && break
    sleep 1
  done
  db_up || { echo "The database did not start within 60 seconds: see logs/mariadb.err"; exit 1; }
fi

stop_db() {
  if [ $started_db -eq 1 ] && db_up; then
    echo "Stopping the database..."
    "$MDB/bin/mariadb-admin" --no-defaults --socket="$SOCK" -u "$ME" shutdown || true
  fi
}

# ---- first start: game database, database user, staff account
if [ ! -f "$DATA/chaos-setup-done.txt" ]; then
  echo "Loading the game database from server/sql-setup ..."
  pass=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  sql -e "CREATE DATABASE IF NOT EXISTS chaos CHARACTER SET utf8mb4;
          CREATE USER IF NOT EXISTS 'chaos'@'127.0.0.1' IDENTIFIED BY '$pass';
          CREATE USER IF NOT EXISTS 'chaos'@'localhost' IDENTIFIED BY '$pass';
          ALTER USER 'chaos'@'127.0.0.1' IDENTIFIED BY '$pass';
          ALTER USER 'chaos'@'localhost' IDENTIFIED BY '$pass';
          GRANT ALL PRIVILEGES ON chaos.* TO 'chaos'@'127.0.0.1';
          GRANT ALL PRIVILEGES ON chaos.* TO 'chaos'@'localhost';"
  umask 077
  {
    echo "# Cinders of Chaos, Linux server package. Read by start-server.sh; config.lua reads the CHAOS_* variables."
    echo "# Written at the first start. Keep it private (mode 600)."
    echo "CHAOS_DB_HOST=127.0.0.1"
    echo "CHAOS_DB_PORT=3307"
    echo "CHAOS_DB_USER=chaos"
    echo "CHAOS_DB_PASS=$pass"
    echo "CHAOS_DB_NAME=chaos"
    echo "# client guard: the 64 hex digits the official client was built with (GitHub secret CHAOS_CLIENT_KEY)."
    echo "# Empty: the guard is off and any 10.98 client can log in. Set: only that client can (README.txt)."
    echo "CHAOS_CLIENT_KEY="
  } > "$ENVF"
  umask 022
  for f in "$ROOT"/server/sql-setup/*.sql; do
    case "$f" in
      *test_accounts.sql) [ "${CHAOS_TEST_ACCOUNTS:-0}" = 1 ] || continue ;;
    esac
    echo "  $(basename "$f")"
    sql --force chaos < "$f" >> "$LOGS/database-setup.log" 2>&1 || true
  done
  staff=$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')
  sql chaos -e "INSERT IGNORE INTO accounts (name, password, type, creation) VALUES ('admin', SHA1('$staff'), 5, UNIX_TIMESTAMP());
                INSERT IGNORE INTO players (name, group_id, account_id, vocation, level, lastlogin)
                  SELECT 'Chaos Staff', 6, id, 4, 1, UNIX_TIMESTAMP() FROM accounts WHERE name = 'admin';"
  umask 077
  printf 'Staff account (god): account admin / password %s, character "Chaos Staff".\nChange the password after the first login. More accounts: ./add-account.sh\n' "$staff" \
    > "$ROOT/first-start-account.txt"
  umask 022
  echo "done" > "$DATA/chaos-setup-done.txt"
  echo "Database ready."
  cat "$ROOT/first-start-account.txt"
fi

[ -f "$ENVF" ] || { echo "chaos.env is missing (it is written at the first start; database/ was made without it)"; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENVF"
set +a

# ---- game server, started again after a clean stop (the daily server save shuts it down) and after a crash
child=0
on_stop() {
  touch "$RUN/stop"
  if [ $child -ne 0 ] && kill -0 $child 2>/dev/null; then
    echo "Stopping the game server (it saves first)..."
    kill -TERM $child 2>/dev/null || true
  fi
}
trap on_stop INT TERM

crashes=0
while [ ! -f "$RUN/stop" ]; do
  echo "Starting the game server ($(date '+%F %T')). Ctrl+C or ./stop-server.sh stops it."
  (cd "$ROOT/server" && exec ./tfs) &
  child=$!
  echo $child > "$RUN/server.pid"
  code=0
  # wait returns early when a trapped signal arrives; then wait again for the save and the exit
  while kill -0 $child 2>/dev/null; do
    wait $child && code=0 || code=$?
  done
  rm -f "$RUN/server.pid"
  [ -f "$RUN/stop" ] && break
  if [ $code -eq 0 ]; then
    crashes=0
    echo "The game server stopped cleanly (server save or /shutdown). Starting it again in 5 seconds."
  else
    crashes=$((crashes + 1))
    mkdir -p "$ROOT/crashes"
    echo "$(date '+%F %T') exit code $code" >> "$ROOT/crashes/crashes.log"
    echo "The game server crashed (exit code $code). Restart $crashes of 5; see crashes/crashes.log."
    if [ $crashes -ge 5 ]; then
      echo "It crashed 5 times in a row. Not restarting again: read the output above."
      break
    fi
  fi
  sleep 5
done

stop_db
rm -f "$RUN/start.pid" "$RUN/stop"
echo "Stopped."
