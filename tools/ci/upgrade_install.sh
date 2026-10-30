#!/usr/bin/env bash
# An update of an installed server, the way the VPS runs one (chaos_kit_update.sh step 5): install_all.py of an older
# commit on the base server, then install_all.py of this checkout over it. Every install step is idempotent on its own
# work, but a fresh install (the package build) never sees the work of an older version. On 2026-10-30 two steps failed
# only on the live server (packitems: a node the item wire table changed; contentareas: a wing grown before).
#
# usage: tools/ci/upgrade_install.sh FROM_REF BASE_SERVER_DIR [MAP_MASTER_DIR]
#
# BASE_SERVER_DIR is changed in place. MAP_MASTER_DIR (windows-assets' world/) replaces the base map first, as on the
# VPS. No database: both installs run with --no-sql. When the update needs the map from its backup (a placed area
# changed shape; install_all.py says to touch <map>.otbm.restore), the update runs again with the marker and passes
# with a warning: the owner creates the marker on the VPS before that update (server/README.md "Map master").
# Exit 0 passed, 1 the update failed, 2 the older install itself failed (not this change).
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
FROM=$1
SERVER=$(cd "$2" && pwd)
MASTER=${3:-}
WORK=$(mktemp -d)
cleanup() {
  git -C "$REPO" worktree remove --force "$WORK/old" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

git -C "$REPO" worktree add --detach "$WORK/old" "$FROM" >/dev/null 2>&1 || { echo "no commit $FROM in $REPO" >&2; exit 2; }
echo "== from $(git -C "$WORK/old" rev-parse --short HEAD) to $(git -C "$REPO" rev-parse --short HEAD)"

if [ -n "$MASTER" ] && [ -f "$MASTER/MAP_MASTER.json" ]; then
  echo "== map master"
  python3 -I "$REPO/server/tools/map_master.py" install "$MASTER" "$SERVER" --backup-dir "$WORK/mapbak" | sed 's/^/  /'
  [ "${PIPESTATUS[0]}" = 0 ] || { echo "the map master did not install" >&2; exit 2; }
fi

echo "== install of $FROM"
if ! python3 -I "$WORK/old/server/tools/install_all.py" "$SERVER" --no-sql --quiet > "$WORK/old.log" 2>&1; then
  tail -n 40 "$WORK/old.log"
  echo "::error::the install of $FROM itself failed on this base: not a fault of the update"
  exit 2
fi
tail -n 3 "$WORK/old.log"

echo "== update to this checkout"
if python3 -I "$REPO/server/tools/install_all.py" "$SERVER" --no-sql --quiet > "$WORK/new.log" 2>&1; then
  tail -n 3 "$WORK/new.log"
  echo "update from $FROM: passed"
  exit 0
fi
tail -n 40 "$WORK/new.log"
if ! grep -q 'otbm.restore' "$WORK/new.log"; then
  echo "::error::the update from $FROM fails on an installed server (above); the VPS would roll it back"
  exit 1
fi

echo "== update again with the restore marker (the install asked for the map from its backup)"
map=$(find "$SERVER/data/world" -maxdepth 1 -name '*.otbm' | head -n 1)
[ -n "$map" ] || { echo "no map in $SERVER/data/world" >&2; exit 1; }
touch "$map.restore"
if python3 -I "$REPO/server/tools/install_all.py" "$SERVER" --no-sql --quiet > "$WORK/new2.log" 2>&1; then
  tail -n 3 "$WORK/new2.log"
  echo "::warning::the update from $FROM needs the restore marker on the VPS first: touch $(basename "$map").restore in data/world (server/README.md \"Map master\")"
  exit 0
fi
tail -n 40 "$WORK/new2.log"
echo "::error::the update from $FROM fails even with the map from its backup (above)"
exit 1
