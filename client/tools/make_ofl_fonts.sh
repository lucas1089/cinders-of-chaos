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
# Every font holds the glyphs 32..255 (cp1252: accents, € – — “ ” …), the client draws a string byte by byte.
# splash: the login "PRESS ANY KEY TO START" (upper case; with the whole range for the pt-BR "APERTE QUALQUER TECLA
# PARA COMEÇAR": a 512 slot of the font atlas, the room of the dropped outline 12 px below)
"${MK[@]}" "$CINZEL" --weight 700 --name chaos-splash --sizes 20 --outline 1 --shadow 1,1 --out "$OUT"
# subtitle and heading: the Codex page title / crafting item name, the Codex section headings (Alegreya SC Bold;
# its own space is 0.17 em, 2 px at these sizes; the heading --tight: its sheet then fits a 256 slot)
ASC="$SRC/AlegreyaSC/AlegreyaSC-Bold.ttf"
"${MK[@]}" "$ASC" --name chaos-subtitle --sizes 16 --shadow 1,1 --space-width 4 --out "$OUT"
"${MK[@]}" "$ASC" --name chaos-heading --sizes 14 --tight --shadow 1,1 --space-width 4 --out "$OUT"
# dialogue: what NPCs say (IM Fell English Roman; plain, the bubble's plate is dark)
"${MK[@]}" "$SRC/IMFellEnglish/IMFeENrm28P.ttf" --name chaos-dialogue --sizes 15 --space-width 4 --out "$OUT"
# body: a trial body font, off by default (Alegreya Sans Medium)
"${MK[@]}" "$SRC/AlegreyaSans/AlegreyaSans-Medium.ttf" --name chaos-body --sizes 12,13 --space-width 3 --out "$OUT"
# outline: small text drawn straight over the game picture (the login scene's name plates): Alegreya Sans Medium 11
# with an antialiased round 1 px border (--border), so it reads on light and dark ground alike. The per mille sign and
# the em dash are squeezed (--max-cell-width) so it keeps a 256 slot of the font atlas. (A 12 px size had no user;
# its slot went to the full-range splash.)
ASM="$SRC/AlegreyaSans/AlegreyaSans-Medium.ttf"
"${MK[@]}" "$ASM" --name chaos-outline --sizes 11 --border 1.0 --space-width 3 --max-cell-width 14 --out "$OUT"
# display: big captions over the game picture (the login scene's place name, the character list's hero name): Cinzel
# Bold 16 with the border and a shadow; glyphs space..~ only (ASCII: place and character names are never accented),
# which keeps the sheet in a 256 slot (the whole range needs a 512 the font atlas does not have)
"${MK[@]}" "$CINZEL" --weight 700 --name chaos-display --sizes 16 --last 126 --border 1.0 --shadow 1,1 \
  --space-width 5 --out "$OUT"
# chaos-outline-12px is gone (its atlas room went to the splash): an install updated over an older one keeps the old
# chaos-outline-12px.png, and that sheet loaded as well would fill the font atlas (fatal at start). This stub carries
# the name of a font loaded before it, so the client skips it (FontManager::importFont), like the replaced stock fonts.
cat > "$OUT/chaos-outline-12px.otfont" <<'OTF'
// Cinders of Chaos: chaos-outline-12px was dropped (client/MANIFEST.md "OFL fonts"). This stub replaces the old file
// of an updated install with the name of a font loaded before it, so the client skips it and its old sheet takes no
// font atlas slot.
Font
  name: Icon-VBold-11px
  texture: /data/fonts/Icon-VBold-11px
  height: 15
  glyph-size: 22 15
  space-width: 4
OTF
rm -f "$OUT/chaos-outline-12px.png"
# the OFL wants its text (with the copyright line) in every copy that ships the fonts
for f in Cinzel AlegreyaSC IMFellEnglish AlegreyaSans; do cp "$SRC/$f/OFL.txt" "$OUT/OFL-$f.txt"; done
