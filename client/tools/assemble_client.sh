#!/usr/bin/env bash
# Assemble the Chaos client: upstream OTC-Fonticak (MIT) + patches + overlay.
# Usage: tools/assemble_client.sh <output-dir> [upstream-git-ref]
# Does NOT include Tibia.spr/.dat: copy your 10.98 pair into <out>/data/things/1098/ yourself.
set -euo pipefail
OUT=${1:?output dir}; REF=${2:-main}
HERE=$(cd "$(dirname "$0")/.." && pwd)
git clone https://github.com/soyfabi/OTC-Fonticak.git "$OUT"
git -C "$OUT" checkout "$REF"
for p in "$HERE"/base-patches/*.patch; do patch -p1 -d "$OUT" < "$p"; done
# our stash (extended-opcode, 10.98) replaces Fonticak's native one (needs 11.x packets)
rm -rf "$OUT/modules/game_stash"
cp -r "$HERE"/overlay/modules/. "$OUT/modules/"
mkdir -p "$OUT/data/images"; cp -r "$HERE"/overlay/data/images/. "$OUT/data/images/"
mkdir -p "$OUT/data/things/1098"
echo "Done. Put Tibia.spr and Tibia.dat (10.98) in $OUT/data/things/1098/, then build with CMake."
