#!/usr/bin/env bash
# Apply server/src-patches/*.patch, in number order, to a base server folder (or to a folder holding only its src/;
# every patch touches src/ files only). Used by tools/windows/prepare_server.sh (the server folder of the packages) and
# by the engine job of .github/workflows/windows-package.yml (which builds from the patched src/ without waiting for
# the server job). A patch that is already applied is skipped, so running it twice is harmless.
#
# usage: tools/windows/apply_engine_patches.sh BASE_SERVER_DIR
set -euo pipefail

SERVER=$(cd "$1" && pwd)
REPO=$(cd "$(dirname "$0")/../.." && pwd)

[ -d "$SERVER/src" ] || { echo "no src/ in: $SERVER" >&2; exit 1; }

for p in "$REPO"/server/src-patches/*.patch; do
  if patch -d "$SERVER" -p1 -R --dry-run -s -f < "$p" > /dev/null 2>&1; then
    echo "  $(basename "$p") (already applied)"
  else
    patch -d "$SERVER" -p1 -s -f --no-backup-if-mismatch < "$p"
    echo "  $(basename "$p")"
  fi
done
