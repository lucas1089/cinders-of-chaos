#!/usr/bin/env bash
# Turn the base server download into the server folder of the Windows package (run on Linux; used by
# .github/workflows/windows-package.yml, and by hand for a local check).
#
# usage: tools/windows/prepare_server.sh BASE_SERVER_DIR
#
# BASE_SERVER_DIR (the extracted base server download: config.lua, data/, src/, SQL_Server/) is changed in place:
#  - server/src-patches/*.patch applied to src/ (the engine is built from it afterwards, on Windows)
#  - config.lua: the package's own MariaDB (127.0.0.1:3307, user root without password, database chaos)
#  - every Chaos install step (server/tools/install_all.py); the SQL it would run is captured, not run
#  - sql-setup/: the SQL a fresh database needs, in order (base schema, Chaos tables, test accounts);
#    start-server.bat loads it at the first start
#  - the base download's Windows binary and DLLs removed (they lack the engine patches; the build replaces them)
set -euo pipefail

SERVER=$(cd "$1" && pwd)
REPO=$(cd "$(dirname "$0")/../.." && pwd)
WIN="$REPO/tools/windows"

[ -f "$SERVER/config.lua" ] && [ -d "$SERVER/src" ] || { echo "not a base server folder: $SERVER" >&2; exit 1; }

echo "== engine patches"
for p in "$REPO"/server/src-patches/*.patch; do
  if patch -d "$SERVER" -p1 -R --dry-run -s -f < "$p" > /dev/null 2>&1; then
    echo "  $(basename "$p") (already applied)"
  else
    patch -d "$SERVER" -p1 -s -f --no-backup-if-mismatch < "$p"
    echo "  $(basename "$p")"
  fi
done

echo "== config.lua"
python3 -I - "$SERVER/config.lua" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding='latin-1').read()
want = {'mysqlHost': '"127.0.0.1"', 'mysqlUser': '"root"', 'mysqlPass': '""', 'mysqlDatabase': '"chaos"',
        'mysqlPort': '3307', 'mysqlSock': '""', 'ip': '"127.0.0.1"'}
for key, value in want.items():
    text, n = re.subn(r'^(%s\s*=\s*)[^\r\n]*' % key, lambda m: m.group(1) + value, text, count=1, flags=re.M)
    if n != 1:
        sys.exit('config.lua: no %s line' % key)
    print('  %s = %s' % (key, value))
open(path, 'w', encoding='latin-1', newline='').write(text)
PY

echo "== Chaos content (install_all.py)"
CAPTURE=$(mktemp -d)
CAPTURE_DIR="$CAPTURE" python3 -I "$REPO/server/tools/install_all.py" "$SERVER" --mysql "$WIN/capture_sql.sh" --quiet

echo "== sql-setup"
rm -rf "$SERVER/sql-setup"
mkdir "$SERVER/sql-setup"
n=0
add() {
  cp "$1" "$SERVER/sql-setup/$(printf '%02d' "$n")-$2"
  echo "  $(printf '%02d' "$n")-$2"
  n=$((n + 1))
}
# the base schema first (docs/LAUNCH.md "Database"); never the SQL_ONLY_for_existing_server file
add "$SERVER/SQL_Server/schema.sql" schema.sql
for f in "$SERVER"/SQL_Server/schema_*.sql "$SERVER"/SQL_Server/sql_*.sql; do
  add "$f" "$(basename "$f")"
done
for f in "$CAPTURE"/chaos-*.sql; do
  add "$f" "$(basename "$f")"
done
add "$WIN/test_accounts.sql" test_accounts.sql
rm -rf "$CAPTURE"

echo "== old Windows binary"
rm -fv "$SERVER"/*.exe "$SERVER"/*.dll | sed 's/^/  /'
rm -rf "$SERVER/build" "$SERVER/vc17"
echo "done: $SERVER"
