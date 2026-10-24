#!/usr/bin/env bash
# Assemble the Cinders of Chaos client: the base client source (you supply it) + patches + overlay.
# Usage: tools/assemble_client.sh <base-client-dir> <output-dir> [<things-dir>]
# The base client tree is ~300 MB, so it is not committed here.
# <things-dir>: a folder with the 10.98 Tibia.dat and Tibia.spr. The dat is copied and the spr is split into sprite
# shards (tools/sprites/spr_shards.py, base patch 0048: Tibia.sprshards + Tibia.NNN.spr, checked against the spr);
# CHAOS_SPR_SHARDS=0 copies the single Tibia.spr instead (a client or map editor that needs it). Without
# <things-dir> the pair is not included: copy it into <out>/data/things/1098/ yourself.
set -euo pipefail
SRC=${1:?base client dir (the folder with init.lua, modules/, mods/)}; OUT=${2:?output dir}; THINGS=${3:-}
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$SRC/init.lua" ] && [ -d "$SRC/modules" ] || { echo "not an the base client tree: $SRC"; exit 1; }
mkdir -p "$OUT"; cp -a "$SRC"/. "$OUT"/
for p in "$HERE"/base-patches/*.patch; do patch -p1 -d "$OUT" < "$p"; done
# the base client's own stash targets its 8.60 protocol; ours speaks extended opcode 110 to the base server
rm -rf "$OUT/mods/game_stash" "$OUT/modules/game_stash"
# the base client's battle pass is for its own server; ours is the Chaos season pass (extended opcode 227)
rm -rf "$OUT/modules/game_battlepass" "$OUT/mods/game_battlepass"
# the base Task Hunt window (bounty tasks, preferred list, talisman, weekly tasks, task shop) reads packets of newer
# protocols the 10.98 server never sends, so it stayed empty; ours: Hunt > Kill Tasks (game_bestiary) and the Bounty
# Board (game_bounty). Every caller of the module checks that it exists.
rm -rf "$OUT/modules/game_task_hunt"
# no scripting bot: the vBot module (scripts, cavebot) and the helper's cavebot and script workspace go
# (patch 0015 removes them from the helper window, its module list and game_interface's load-later list)
rm -rf "$OUT/modules/game_bot"
rm -f "$OUT/mods/game_helper/cavebot_panel.lua" "$OUT/mods/game_helper/scripting.lua" \
  "$OUT/mods/game_helper/scripting_actions.lua" "$OUT/mods/game_helper/scripting_compat.lua"
# the base helper retires whole: the overlay's modules/game_helper is the helper (client/MANIFEST.md "Helper"). The base
# patches above still apply to mods/game_helper first (earlier patches are never edited), then the folder goes.
# game_interface loads "game_helper" by name from its load-later list and finds the overlay module.
rm -rf "$OUT/mods/game_helper"
# An install updated over a package that still had the base helper keeps it inside its chaos.pack (the updater adds and
# replaces files, it never hides one). A retired stub at the base helper's own .otmod path replaces it there: another
# name, no scripts, so the engine never merges it into our game_helper (tools/ci/check_assembled.py RETIRED_STUB).
mkdir -p "$OUT/mods/game_helper"
printf 'Module\n  name: game_helper_base_retired\n  description: the base helper, retired (Cinders of Chaos uses modules/game_helper)\n  autoload: false\n' > "$OUT/mods/game_helper/helper.otmod"
# the base native splash picture (used only with init.lua ENABLE_NATIVE_SPLASH on; without it no splash is drawn) and
# the browser build's emblem show the base client's name in the picture (client/BASE.md "Names check")
rm -f "$OUT/data/images/splash.png" "$OUT"/data/images/*-client-emblem.png
cp -a "$HERE"/overlay/modules/. "$OUT/modules/"
cp -a "$HERE"/overlay/data/. "$OUT/data/"
# one game_helper, ours, and no two modules of one name (tools/ci/check_assembled.py): a base helper left next to ours
# is merged into it by the engine and wins, and the helper loses its Auto setup and Support tab
if command -v python3 >/dev/null 2>&1; then python3 -I "$HERE/../tools/ci/check_assembled.py" "$OUT"; fi
# our executable icon (src/otcicon.rc names otcicon.ico; the window icon data/images/clienticon.png came with the overlay data);
# made by tools/gen_client_icon.py from docs/brand/cinders_logo_icon.png
if [ -d "$HERE/overlay/src" ]; then mkdir -p "$OUT/src" && cp -a "$HERE"/overlay/src/. "$OUT/src/"; fi
# (the overlay's data/images/game/spells/spell-icons-*.png are complete generated sheets, Chaos spells at cells
#  201..277 included, and replace the base ones; regenerate them with tools/gen_all_spell_icons.py)
# the Chaos bitmap fonts (client_chaos_theme ChaosTheme.fonts), made from the OFL fonts in client/fonts-src/ by
# tools/make_ofl_fonts.sh, came with the overlay into data/fonts/chaos/ (client/MANIFEST.md "OFL fonts"). The client
# copies every font into one 2048x2048 atlas texture (framework/graphics/atlas.cpp; out of space is fatal at start);
# the room comes from four unused stock fonts the overlay's data/fonts/*.otfont replace by a copy of a loaded one.
# A local override: bitmap fonts in client/local-fonts/ (git-ignored) replace the shipped ones of the same name.
if ls "$HERE"/local-fonts/*.otfont >/dev/null 2>&1; then
  cp "$HERE"/local-fonts/*.otfont "$HERE"/local-fonts/*.png "$OUT/data/fonts/chaos/"
fi
# The font atlas check (tools/make_fonts.py, no Pillow needed): a set that does not fit stops the assembly here,
# since the client would stop at start with "[Atlas] Out of space for new fonts".
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
  python3 -I "$HERE/tools/make_fonts.py" --atlas-check "$OUT/data/fonts" | tail -1
  # slim client: the files nothing uses go (tools/slim_prune.txt, a reason per group; client/BASE.md "Slim client"),
  # then every static file reference of the tree must still resolve (tools/slim_client.py check)
  python3 -I "$HERE/tools/slim_client.py" prune "$OUT"
  python3 -I "$HERE/tools/slim_client.py" check "$OUT"
else
  echo "python3 not found: font atlas check and slim prune skipped (the client ships ~170 MB of unused files)"
fi
mkdir -p "$OUT/data/things/1098"
if [ -n "$THINGS" ]; then
  [ -f "$THINGS/Tibia.dat" ] && [ -f "$THINGS/Tibia.spr" ] || { echo "no Tibia.dat / Tibia.spr in $THINGS"; exit 1; }
  cp "$THINGS/Tibia.dat" "$OUT/data/things/1098/"
  if [ "${CHAOS_SPR_SHARDS:-1}" = "0" ]; then
    rm -f "$OUT"/data/things/1098/Tibia.sprshards "$OUT"/data/things/1098/Tibia.[0-9][0-9][0-9].spr
    cp "$THINGS/Tibia.spr" "$OUT/data/things/1098/"
  else
    # one shard per 16384 sprites: a sprite change (new sprites are appended) updates only the shards that hold
    # it; the shards are byte-checked against the spr before the single file is left out
    rm -f "$OUT/data/things/1098/Tibia.spr"
    python3 -I "$HERE/tools/sprites/spr_shards.py" split "$THINGS/Tibia.spr" "$OUT/data/things/1098"
    python3 -I "$HERE/tools/sprites/spr_shards.py" verify "$THINGS/Tibia.spr" "$OUT/data/things/1098"
  fi
  echo "Done. The pair is in $OUT/data/things/1098/; build with CMake."
else
  echo "Done. Put Tibia.spr and Tibia.dat (10.98) in $OUT/data/things/1098/ (or pass a things dir), then build with CMake."
fi
