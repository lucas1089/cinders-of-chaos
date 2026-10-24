#!/usr/bin/env bash
# Turn the base server download into the server folder of the Windows package (run on Linux; used by
# .github/workflows/windows-package.yml, and by hand for a local check).
#
# usage: tools/windows/prepare_server.sh BASE_SERVER_DIR [MAP_MASTER_DIR]
#
# BASE_SERVER_DIR (the extracted base server download: config.lua, data/, src/, SQL_Server/) is changed in place:
#  - server/src-patches/*.patch applied to src/ (the engine is built from it afterwards, on Windows)
#  - config.lua: the package's own MariaDB (127.0.0.1:3307, user root without password, database chaos)
#  - MAP_MASTER_DIR (windows-assets' world/: the owner's edited map, server/README.md "Map master"), when given and
#    it holds MAP_MASTER.json: the map master replaces the base map (server/tools/map_master.py install; the base map
#    is not kept in the folder), so the install steps below run on top of it and find their own work in place
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
bash "$WIN/apply_engine_patches.sh" "$SERVER"

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

echo "== map master"
MASTER=${2:-}
if [ -n "$MASTER" ] && [ -f "$MASTER/MAP_MASTER.json" ]; then
  MAPBAK=$(mktemp -d)
  python3 -I "$REPO/server/tools/map_master.py" install "$MASTER" "$SERVER" --backup-dir "$MAPBAK" | sed 's/^/  /'
  [ "${PIPESTATUS[0]}" = 0 ] || { echo "the map master did not install" >&2; rm -rf "$MAPBAK"; exit 1; }
  rm -rf "$MAPBAK"
else
  echo "  none (${MASTER:-no folder given}): the base map"
fi

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
