#!/usr/bin/env python3
"""Append the Chaos spell icons to one of the client's spell icon sheets.
usage: python3 -I append_spell_icons.py SHEET.png ICON_DIR FIRST_ID CELL_W CELL_H OUT.png
Cells are numbered like the client does (Spells.getImageClipNormal): id 1 is the top-left cell, 20 columns.
The sheet grows downwards when the ids do not fit. Icons are ICON_DIR/01.png, 02.png, ..."""
import os, sys
from PIL import Image

COLS = 20

def main():
    sheet_path, icon_dir, first, cw, ch, out = sys.argv[1:7]
    first, cw, ch = int(first), int(cw), int(ch)
    sheet = Image.open(sheet_path)
    icons = sorted(f for f in os.listdir(icon_dir) if f.endswith('.png'))
    last_id = first + len(icons) - 1
    rows_needed = (last_id - 1) // COLS + 1
    if rows_needed * ch > sheet.height:
        grown = Image.new(sheet.mode, (sheet.width, rows_needed * ch), (0, 0, 0, 0) if sheet.mode == 'RGBA' else (0, 0, 0))
        grown.paste(sheet, (0, 0))
        sheet = grown
    for i, name in enumerate(icons):
        cid = first + i
        col, row = (cid - 1) % COLS, (cid - 1) // COLS
        icon = Image.open(os.path.join(icon_dir, name)).convert('RGBA')
        if icon.size != (cw, ch):
            icon = icon.resize((cw, ch), Image.LANCZOS)
        if sheet.mode == 'RGBA':
            sheet.paste(icon, (col * cw, row * ch))
        else:
            base = Image.new('RGBA', icon.size, (0, 0, 0, 255)); base.alpha_composite(icon)
            sheet.paste(base.convert(sheet.mode), (col * cw, row * ch))
    sheet.save(out)
    print(f'{len(icons)} icons at ids {first}..{last_id}, sheet {sheet.size}')

if __name__ == '__main__':
    main()
