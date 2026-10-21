#!/usr/bin/env python3
"""Tests of check_text_fit.py: glyph widths from a synthetic sheet, the measure, the parsers, and the real check.

Usage: python3 client/tools/check_text_fit_test.py   (Pillow)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_text_fit as T  # noqa: E402
from PIL import Image  # noqa: E402

n = 0


def eq(a, b, msg):
    global n
    n += 1
    if a != b:
        raise AssertionError('%s: %r ~= %r' % (msg, a, b))


# a 2-column sheet of 4x3 cells from glyph 32: '!' ink in column 0, '"' ink up to column 2, '#' empty
sheet = Image.new('RGBA', (8, 6), (0, 0, 0, 0))
sheet.putpixel((4, 1), (255, 255, 255, 255))       # '!' (33): cell 1, column 0
sheet.putpixel((2, 4), (255, 255, 255, 1))         # '"' (34): cell 2, column 2 (alpha 1 counts, the advance mark)
w = T.glyph_widths(sheet, (4, 3), 32)
eq(w[33], 1, 'one column of ink')
eq(w[34], 3, 'advance mark at column 2')
eq(w[35], 0, 'empty cell')
m = T.measurer(w, -1, 4)
eq(m(''), 0, 'empty text')
eq(m('!'), 1, 'one glyph, no spacing')
eq(m('! "'), 1 + 4 + 3 - 2, 'spacing between glyphs only')

eq(T.pt_br_table('  ["Misc."] = "Diversos",\n  ["A \\"b\\""] = "C",'), {'Misc.': 'Diversos', 'A "b"': 'C'}, 'pt-BR pairs')
eq(T.option_labels("+local OPTION_LABELS = {\n+  controls = 'Controls', hud = 'HUD',\n+}\n"),
   {'controls': 'Controls', 'hud': 'HUD'}, 'OPTION_LABELS')

# the real fonts: the old main font would not fit "Action Bar Hotkeys", the sub-entry font fits all
eq(T.load_font('verdana-11px-rounded')('Action Bar Hotkeys') > 107, True, 'rounded 11 px is too wide')
problems, widest, room = T.check()
eq(problems, [], 'every options menu sub-entry fits')
eq(widest[0] <= room, True, 'widest fits')

print('check_text_fit_test: %d ok' % n)
