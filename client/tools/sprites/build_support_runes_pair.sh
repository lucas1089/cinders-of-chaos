#!/bin/sh
# Appends the 100 support rune looks (art_import/support_runes.csv, client items from FIRST) to ANY input pair and checks it.
# usage: build_support_runes_pair.sh IN_DIR OUT_DIR [LAST_ITEM_OF_IN]   (IN_DIR has Tibia.dat + Tibia.spr; default last item 38657, pair 45)
# The first new client id is LAST_ITEM_OF_IN + 1 and must equal clientFirstId in server/data/lib/chaos_supports_config.lua
# (38658 on top of pair 45). Run from the repo root. Afterwards (they rewrite two committed lua files with the dat md5):
#   python3 -I client/tools/sprites/gen_outfit_anchors.py OUT_DIR/Tibia.dat OUT_DIR/Tibia.spr
#   python3 -I client/tools/sprites/gen_info_lift.py OUT_DIR/Tibia.dat OUT_DIR/Tibia.spr
set -e
IN=$1; OUT=$2; LAST=${3:-38657}
[ -n "$IN" ] && [ -n "$OUT" ] || { sed -n 2,7p "$0"; exit 1; }
T=client/tools/sprites
python3 -I $T/gen_support_runes_art.py build --check
python3 -I $T/import_art_things.py --ours-dat "$IN/Tibia.dat" --ours-spr "$IN/Tibia.spr" --out-dir "$OUT" \
    --things $T/art_import/support_runes.csv --first-item $((LAST + 1)) --expect-items "$LAST"
python3 -I $T/check_pair.py "$OUT/Tibia.dat" "$OUT/Tibia.spr" --old "$IN/Tibia.dat" "$IN/Tibia.spr" --new-only
md5sum "$OUT/Tibia.dat" "$OUT/Tibia.spr"
