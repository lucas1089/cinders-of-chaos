#!/usr/bin/env bash
# Check that mapeditor/patches/*.patch apply in order on a clean copy of the upstream tree at the pinned commit.
#
# usage: mapeditor/tools/check_patches.sh UPSTREAM_CLONE [WORK_DIR]
#
# UPSTREAM_CLONE is a git clone of the upstream editor; it is never changed. The pinned commit (mapeditor/UPSTREAM)
# is exported into WORK_DIR (default: a temporary folder, removed at the end) and every patch is checked, then
# applied, in name order, the way the build workflow does it.
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
CLONE=$(cd "$1" && pwd)
PIN=$(tr -d ' \r\n' < "$HERE/UPSTREAM")
WORK=${2:-}
CLEANUP=
if [ -z "$WORK" ]; then
  WORK=$(mktemp -d)
  CLEANUP=$WORK
fi
trap '[ -z "$CLEANUP" ] || rm -rf "$CLEANUP"' EXIT

mkdir -p "$WORK/src"
git -C "$CLONE" archive --format=tar "$PIN" | tar -xf - -C "$WORK/src"
git -C "$WORK/src" init -q
for patch in "$HERE"/patches/*.patch; do
  git -C "$WORK/src" apply --check --whitespace=nowarn "$patch"
  git -C "$WORK/src" apply --whitespace=nowarn "$patch"
  echo "ok $(basename "$patch")"
done
echo "all patches apply on $PIN"
