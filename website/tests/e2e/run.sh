#!/usr/bin/env bash
# Browser smoke test of the website (website/README.md "Smoke test"). The pre-deploy check of docs/LAUNCH.md "Website".
#
#   website/tests/e2e/run.sh                  # a throwaway local site: MariaDB + install_site.sh + php -S, then removed
#   E2E_BASE_URL=https://staging.example.org/ website/tests/e2e/run.sh   # an installed site (staging), nothing set up
#
# The local site: a MariaDB data folder in a temporary folder, the game schema (CHAOS_E2E_SCHEMA = the base server's
# schema.sql, else the upstream TFS 1.4.2 schema.sql at a pinned tag, checked by SHA-256), server/sql/*.sql, one town,
# then website/install_site.sh with mock donation providers and PHP's built-in server with setup/router.php. All of it
# is deleted at the end (E2E_KEEP=1 keeps it and prints where).
#
# Needs: bash, php 8.1+ with mysqli, mariadb-server (mariadbd, mariadb-install-db), git, curl, python3, Node 18+ and
# the npm package playwright (Apache 2.0) with its Chromium, installed OUTSIDE this repository, for example:
#   npm install -g playwright@1.56.1 && npx playwright@1.56.1 install chromium
# (where PLAYWRIGHT_BROWSERS_PATH already holds Chromium, skip the second command). No package.json, no lockfile.
#
# Settings: E2E_SHOTS (screenshot folder, default $TMPDIR/chaos-e2e-shots, kept), E2E_HTTP_PORT (8099), E2E_DB_PORT (33099),
# E2E_WORK (work folder, default a new temporary folder), E2E_KEEP=1.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
TEST="$HERE/smoke.test.js"

# playwright from the global npm folder when NODE_PATH does not have it
if ! node -e 'require("playwright")' >/dev/null 2>&1; then
  export NODE_PATH="${NODE_PATH:+$NODE_PATH:}$(npm root -g 2>/dev/null || true)"
  node -e 'require("playwright")' >/dev/null 2>&1 || {
    echo "The npm package playwright is missing: npm install -g playwright@1.56.1 (outside the repository)." >&2; exit 2; }
fi

if [ -n "${E2E_BASE_URL:-}" ]; then
  echo "Smoke test of $E2E_BASE_URL"
  exec node --test --test-concurrency=1 "$TEST"
fi

# ---------------------------------------------------------------- a throwaway local site
SCHEMA_URL="https://raw.githubusercontent.com/otland/forgottenserver/v1.4.2/schema.sql"
SCHEMA_SHA256="828d49fed7ee71d5f91bed25ddf32ef0c3cf50289e4f274f4e368e3e9300e936"
HTTP_PORT="${E2E_HTTP_PORT:-8099}"
DB_PORT="${E2E_DB_PORT:-33099}"
WORK="${E2E_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/chaos-e2e.XXXXXX")}"
WORK="$(realpath -m "$WORK")"
case "$WORK/" in "$REPO/"*) echo "E2E_WORK must be outside the repository." >&2; exit 1 ;; esac
mkdir -p "$WORK/logs"
export E2E_SHOTS="${E2E_SHOTS:-${TMPDIR:-/tmp}/chaos-e2e-shots}"
DBSOCK="$WORK/db.sock"
PIDS=()

cleanup() {
  local rc=$?
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  [ -f "$WORK/db.pid" ] && kill "$(cat "$WORK/db.pid")" 2>/dev/null || true
  sleep 1
  if [ "${E2E_KEEP:-0}" = 1 ] || [ $rc -ne 0 ]; then
    echo "Work folder kept: $WORK (logs in $WORK/logs; delete it when done)"
  else
    rm -rf "$WORK"
  fi
  exit $rc
}
trap cleanup EXIT

command -v mariadbd >/dev/null || { echo "Needs mariadbd (mariadb-server)." >&2; exit 2; }
echo "Database (port $DB_PORT) ..."
mariadb-install-db --no-defaults --datadir="$WORK/db" --user="$(id -un)" --auth-root-authentication-method=normal \
  > "$WORK/logs/db_install.log" 2>&1
mariadbd --no-defaults --datadir="$WORK/db" --port="$DB_PORT" --bind-address=127.0.0.1 --socket="$DBSOCK" \
  --pid-file="$WORK/db.pid" --user="$(id -un)" --innodb-buffer-pool-size=64M --innodb-log-file-size=16M --skip-log-bin \
  > "$WORK/logs/db.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 60); do mariadb -S "$DBSOCK" -uroot -e 'SELECT 1' >/dev/null 2>&1 && break; sleep 1; done
SQL() { mariadb -S "$DBSOCK" -uroot "$@"; }
SQL -e "CREATE DATABASE chaos; CREATE USER 'chaos'@'127.0.0.1' IDENTIFIED BY 'e2e'; GRANT ALL ON chaos.* TO 'chaos'@'127.0.0.1';"

SCHEMA="${CHAOS_E2E_SCHEMA:-}"
if [ -z "$SCHEMA" ]; then
  SCHEMA="$WORK/schema.sql"
  curl -fsSL -o "$SCHEMA" "$SCHEMA_URL"
  got="$(sha256sum "$SCHEMA" | cut -d' ' -f1)"
  [ "$got" = "$SCHEMA_SHA256" ] || { echo "schema.sql checksum mismatch: $got" >&2; exit 1; }
fi
SQL chaos < "$SCHEMA"
for f in "$REPO"/server/sql/*.sql; do SQL chaos < "$f"; done
SQL chaos -e "INSERT IGNORE INTO towns (id, name, posx, posy, posz) VALUES (1, 'Smoke Town', 100, 100, 7)"

cat > "$WORK/site.env" <<EOF
CHAOS_SITE_DIR=$WORK/site
CHAOS_SITE_URL=http://127.0.0.1:$HTTP_PORT
CHAOS_DB_USER=chaos
CHAOS_DB_PASSWORD=e2e
CHAOS_DB_NAME=chaos
CHAOS_DB_HOST=127.0.0.1
CHAOS_DB_PORT=$DB_PORT
CHAOS_START_TOWNS=1
CHAOS_GAME_HOST=127.0.0.1
CHAOS_GAME_PORT=7171
CHAOS_PAY_ENV=$WORK/payments.env
CHAOS_PAY_PIX_PROVIDER=mock
CHAOS_PAY_PAYPAL_PROVIDER=mock
CHAOS_PAY_SITE_URL=http://127.0.0.1:$HTTP_PORT
CHAOS_PAY_MOCK_APPROVE_AFTER=600
CHAOS_PAY_MOCK_SECRET=e2e-mock-secret
CHAOS_PAY_MOCK_STATE=$WORK/pay_mock.json
CHAOS_PAY_PAYER_SALT=e2e-payer-salt
EOF
: > "$WORK/payments.env"
echo "Website (install_site.sh) ..."
"$REPO/website/install_site.sh" "$WORK/site.env" > "$WORK/logs/install_site.log" 2>&1 \
  || { tail -20 "$WORK/logs/install_site.log" >&2; exit 1; }

echo "PHP server (port $HTTP_PORT) ..."
( set -a; . "$WORK/site.env"; set +a
  cd "$WORK/site"   # ZnoteX writes engine/cache/ relative to the working folder
  exec php -S "127.0.0.1:$HTTP_PORT" -t "$WORK/site" "$REPO/website/setup/router.php" ) > "$WORK/logs/php.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 30); do curl -fs -o /dev/null "http://127.0.0.1:$HTTP_PORT/" && break; sleep 0.5; done

export E2E_BASE_URL="http://127.0.0.1:$HTTP_PORT/" E2E_PAY_MOCK=1
node --test --test-concurrency=1 "$TEST"
echo "Screenshots: $E2E_SHOTS"
