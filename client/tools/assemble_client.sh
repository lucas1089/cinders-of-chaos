#!/usr/bin/env bash
# Assemble the Chaos client: the base client source (you supply it) + patches + overlay.
# Usage: tools/assemble_client.sh <base-client-dir> <output-dir>
# The base client tree is ~300 MB, so it is not committed here.
# Does NOT include Tibia.spr/.dat: copy your 10.98 pair into <out>/data/things/1098/ yourself.
set -euo pipefail
SRC=${1:?base client dir (the folder with init.lua, modules/, mods/)}; OUT=${2:?output dir}
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$SRC/init.lua" ] && [ -d "$SRC/modules" ] || { echo "not an the base client tree: $SRC"; exit 1; }
mkdir -p "$OUT"; cp -a "$SRC"/. "$OUT"/
for p in "$HERE"/base-patches/*.patch; do patch -p1 -d "$OUT" < "$p"; done
# the base client's own stash targets its 8.60 protocol; ours speaks extended opcode 110 to the base server
rm -rf "$OUT/mods/game_stash" "$OUT/modules/game_stash"
# the base client's battle pass is for its own server; ours matches the base server (raw opcode 39)
rm -rf "$OUT/modules/game_battlepass" "$OUT/mods/game_battlepass"
cp -a "$HERE"/overlay/modules/. "$OUT/modules/"
mkdir -p "$OUT/data/images"; cp -a "$HERE"/overlay/data/images/. "$OUT/data/images/"
# the Chaos spell icons go into the client's spell icon sheets (cells 201..236; needs python3 with Pillow)
ICONS=$(mktemp -d)
python3 -I "$HERE/tools/gen_spell_icons.py" "$ICONS"
for spec in "32x32:32:32:32" "22x24:22x24:22:24" "20x20:20:20:20"; do
  IFS=: read sheet dir w h <<< "$spec"
  f="$OUT/data/images/game/spells/spell-icons-$sheet.png"
  if [ -f "$f" ]; then python3 -I "$HERE/tools/append_spell_icons.py" "$f" "$ICONS/$dir" 201 "$w" "$h" "$f"; else echo "warning: $f not found, icons for $sheet not added"; fi
done
mkdir -p "$OUT/data/things/1098"
echo "Done. Put Tibia.spr and Tibia.dat (10.98) in $OUT/data/things/1098/, then build with CMake."
