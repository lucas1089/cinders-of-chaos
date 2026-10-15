#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_assets_art_test.py : the pure parts of gen_assets_art.py on synthetic strips
(alpha cleaning, strip cutting and crops, the look sheet layout, the things / picks / sources tables). No sources needed.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_assets_art as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# alpha under ALPHA_MIN is cleared with its colour
a = np.zeros((2, 2, 4), np.uint8)
a[0, 0] = (200, 10, 10, 5)
a[1, 1] = (10, 200, 10, 200)
c = G.clean(a)
check(not c[0, 0].any() and tuple(c[1, 1]) == (10, 200, 10, 200), 'clean: faint pixels cleared, others kept')

# strips cut into frames; an item crop that would lose art is refused
strip = np.zeros((96, 96 * 8, 4), np.uint8)
for i in range(8):
    strip[40:50, i * 96 + 40:i * 96 + 50] = (i, 1, 2, 255)
fr = G.strip_frames(strip, 96, 96)
check(len(fr) == 8 and fr[3][45, 45, 0] == 3, 'strip_frames: eight frames in order')
row = ('t', 's.png', 96, 96, (0, 0), 3, 'all', 140, 'test', 'decor', 'notmoveable', 'catacomb')
check(len(G.item_frames(strip, row)) == 8, 'item_frames: all frames of an animated row')
row1 = row[:6] + (7,) + row[7:]
one = G.item_frames(strip, row1)
check(len(one) == 1 and one[0][45, 45, 0] == 7, 'item_frames: one frame of a static row')
bad = row[:4] + ((0, 0), 1) + row[6:]
try:
    G.item_frames(strip, bad)
    check(False, 'item_frames: a crop that loses art is refused')
except AssertionError:
    pass

# look sheet: idle rows then walk rows, columns n e s w
cells = [[np.full((4, 4, 4), d * 10 + p, np.uint8) for p in range(2)] for d in range(4)]
sheet = G.look_sheet(cells, cells)
check(sheet.shape == (16, 16, 4), 'look_sheet: 2 + 2 rows of 4 directions')
check(sheet[0, 4, 0] == 10 and sheet[4, 8, 0] == 21 and sheet[12, 12, 0] == 31, 'look_sheet: cell order')

# the tables
rows = G.things_rows()
check(rows[0][0] == 'hollow_rider' and rows[0][1] == 'outfit' and rows[0][7] == 5, 'things: the rider first, 5x5')
check(len(rows) == 1 + len(G.ITEMS) and all(r[1] == 'item' for r in rows[1:]), 'things: then the items')
anim = [r for r in rows[1:] if r[10] == 8]
check(all('animateAlways' in r[11] and r[14].startswith('ms=') for r in anim), 'things: animated items loop')
check(G.picks_rows()[0][1] == G.FIRST_OUTFIT == 2234, 'picks: look 2234')
check(all(r[2] == G.PACK for r in G.sources_rows()), 'sources: every row names the credited pack')
shapes = G.expected_shapes()
check(shapes['hollow_rider'] == (160 * 8, 160 * 4) and shapes['crypt_portal'] == (96, 96 * 8), 'expected shapes')

print('gen_assets_art_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
