#!/usr/bin/env bash
# Put the Linux server package together (CindersOfChaos-Server-Linux.tar.gz of .github/workflows/windows-package.yml).
#
# usage: tools/linux/package_server.sh SERVER_DIR ENGINE MARIADB_DIR HOST OUT
#
#   SERVER_DIR   the prepared server folder (tools/windows/prepare_server.sh: engine patches, install_all.py, sql-setup/)
#   ENGINE       the engine built from it on Linux
#   MARIADB_DIR  a portable MariaDB (tools/linux/fetch_mariadb.sh); copied
#   HOST         the address players connect to (config.lua ip); 127.0.0.1 for play on this machine only
#   OUT          the package folder to create
#
# OUT gets: server/ (the folder without the engine sources, the engine as server/tfs, its libraries in server/lib/),
# mariadb/, start-server.sh, stop-server.sh, add-account.sh, README.txt and deploy/ (the systemd units of
# server/deploy/ for a production install, docs/LAUNCH.md). config.lua gets the production settings of
# server/tools/prod_config.py with two changes for a package: the database settings come from chaos.env (written by
# start-server.sh at the first start) and the client guard is on only when CHAOS_CLIENT_KEY is set there.
set -euo pipefail

[ $# -eq 5 ] || { echo "usage: $0 SERVER_DIR ENGINE MARIADB_DIR HOST OUT" >&2; exit 2; }
SERVER=$(readlink -f "$1")
ENGINE=$(readlink -f "$2")
MARIADB=$(readlink -f "$3")
HOST=$4
OUT=$5
REPO=$(cd "$(dirname "$0")/../.." && pwd)
[ -f "$SERVER/config.lua" ] && [ -d "$SERVER/sql-setup" ] || { echo "not a prepared server folder: $SERVER" >&2; exit 1; }
[ ! -e "$OUT" ] || { echo "$OUT exists" >&2; exit 1; }
[[ $HOST =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || { echo "HOST must be a DNS name or an IPv4 address" >&2; exit 1; }

echo "== server folder"
mkdir -p "$OUT/server"
tar -C "$SERVER" --exclude=./src --exclude=./cmake --exclude=./CMakeLists.txt --exclude=./build \
  --exclude=./vcpkg.json --exclude=./triplets -cf - . | tar -C "$OUT/server" -xf -
cp "$ENGINE" "$OUT/server/tfs"
chmod 0755 "$OUT/server/tfs"

echo "== engine libraries"
bash "$REPO/tools/linux/bundle_libs.sh" "$OUT/server/tfs" "$OUT/server/lib"

echo "== config.lua"
python3 -I "$REPO/server/tools/prod_config.py" "$OUT/server" --public-host "$HOST"
python3 -I - "$OUT/server/config.lua" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding='utf-8', errors='surrogateescape').read()
line = ('clientGuardMode = (os.getenv("CHAOS_CLIENT_KEY") or "") ~= "" and "enforce" or "off"'
        '  -- Linux server package: on when chaos.env sets CHAOS_CLIENT_KEY (README.txt)')
text, n = re.subn(r'^[ \t]*clientGuardMode[ \t]*=.*$', lambda m: line, text, count=1, flags=re.M)
if n != 1:
    sys.exit('config.lua: no clientGuardMode line')
for key in ('mysqlHost', 'mysqlPort', 'mysqlUser', 'mysqlPass', 'mysqlDatabase'):
    if not re.search(r'^%s = .*os\.getenv\("CHAOS_DB_' % key, text, re.M):
        sys.exit('config.lua: %s does not read CHAOS_DB_* (prod_config.py)' % key)
open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(text)
print('  clientGuardMode: enforce when CHAOS_CLIENT_KEY is set, else off')
PY

echo "== MariaDB"
cp -a "$MARIADB" "$OUT/mariadb"

echo "== scripts, README, systemd units"
for f in start-server.sh stop-server.sh add-account.sh; do
  install -m 0755 "$REPO/tools/linux/server/$f" "$OUT/$f"
done
install -m 0644 "$REPO/tools/linux/server/README.txt" "$OUT/README.txt"
# the login-screen services (boosted creature / boss, event schedule): start-server.sh runs it on 127.0.0.1:8090
mkdir -p "$OUT/server/tools"
install -m 0644 "$REPO/server/tools/clientservices.py" "$OUT/server/tools/clientservices.py"
# security: our own RSA login key and the VPS hardening (docs/SECURITY_CHECKLIST.md)
install -m 0644 "$REPO/server/tools/rsa_key.py" "$OUT/server/tools/rsa_key.py"
install -m 0755 "$REPO/tools/linux/harden_vps.sh" "$OUT/harden_vps.sh"
mkdir -p "$OUT/deploy"
cp "$REPO"/server/deploy/*.service "$REPO"/server/deploy/*.timer "$REPO"/server/deploy/chaos.env.example \
  "$REPO"/server/deploy/chaos.logrotate "$OUT/deploy/"
du -sh "$OUT"/*
du -sh "$OUT"
