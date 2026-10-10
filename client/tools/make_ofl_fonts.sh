#!/bin/bash
# Regenerates the shipped bitmap fonts (client/overlay/data/fonts/chaos/) from the OFL fonts in client/fonts-src/
# with tools/make_fonts.py:  bash client/tools/make_ofl_fonts.sh
# tools/assemble_client.sh checks that they fit the client's font atlas (make_fonts.py --atlas-check) after it has
# removed the unused stock fonts that make the room. The names are by role, not by family: the OFL does not let a
# converted font carry a Reserved Font Name, and the client code asks for roles (client_chaos_theme
# ChaosTheme.fonts). See client/MANIFEST.md "OFL fonts".
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/fonts-src"
OUT="$HERE/overlay/data/fonts/chaos"
MK=(python3 -I "$HERE/tools/make_fonts.py")
CINZEL="$SRC/Cinzel/Cinzel-VariableFont_wght.ttf"
rm -f "$OUT"/chaos-*.otfont "$OUT"/chaos-*.png
mkdir -p "$OUT"
# title: window titles (Cinzel Bold, its lower case is small capitals)
"${MK[@]}" "$CINZEL" --weight 700 --name chaos-title --sizes 15 --shadow 1,1 --out "$OUT"
# splash: the login "PRESS ANY KEY TO START" (upper case: glyphs space..Z only, which keeps the sheet in a 256 slot)
"${MK[@]}" "$CINZEL" --weight 700 --name chaos-splash --sizes 20 --last 90 --outline 1 --shadow 1,1 --out "$OUT"
# subtitle and heading: the Codex page title / crafting item name, the Codex section headings (Alegreya SC Bold;
# its own space is 0.17 em, 2 px at these sizes)
ASC="$SRC/AlegreyaSC/AlegreyaSC-Bold.ttf"
"${MK[@]}" "$ASC" --name chaos-subtitle --sizes 16 --shadow 1,1 --space-width 4 --out "$OUT"
"${MK[@]}" "$ASC" --name chaos-heading --sizes 14 --shadow 1,1 --space-width 4 --out "$OUT"
# dialogue: what NPCs say (IM Fell English Roman; plain, the bubble's plate is dark)
"${MK[@]}" "$SRC/IMFellEnglish/IMFeENrm28P.ttf" --name chaos-dialogue --sizes 15 --space-width 4 --out "$OUT"
# body: a trial body font, off by default (Alegreya Sans Medium)
"${MK[@]}" "$SRC/AlegreyaSans/AlegreyaSans-Medium.ttf" --name chaos-body --sizes 12,13 --space-width 3 --out "$OUT"
# the OFL wants its text (with the copyright line) in every copy that ships the fonts
for f in Cinzel AlegreyaSC IMFellEnglish AlegreyaSans; do cp "$SRC/$f/OFL.txt" "$OUT/OFL-$f.txt"; done
