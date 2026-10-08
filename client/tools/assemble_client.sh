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
# no scripting bot: the vBot module (scripts, cavebot) and the helper's cavebot and script workspace go
# (patch 0015 removes them from the helper window, its module list and game_interface's load-later list)
rm -rf "$OUT/modules/game_bot"
rm -f "$OUT/mods/game_helper/cavebot_panel.lua" "$OUT/mods/game_helper/scripting.lua" \
  "$OUT/mods/game_helper/scripting_actions.lua" "$OUT/mods/game_helper/scripting_compat.lua"
cp -a "$HERE"/overlay/modules/. "$OUT/modules/"
cp -a "$HERE"/overlay/data/. "$OUT/data/"
# (the overlay's data/images/game/spells/spell-icons-*.png are complete generated sheets, Chaos spells at cells
#  201..277 included, and replace the base ones; regenerate them with tools/gen_all_spell_icons.py)
mkdir -p "$OUT/data/things/1098"
echo "Done. Put Tibia.spr and Tibia.dat (10.98) in $OUT/data/things/1098/, then build with CMake."
