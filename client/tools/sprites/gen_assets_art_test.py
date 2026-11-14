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

# ---- the rider stands on its tile (O576)
C = 160


def figure(x0, x1, y0, y1):
    f = np.zeros((C, C, 4), np.uint8)
    f[y0:y1, x0:x1] = (200, 50, 50, 255)
    return f


# the kit's shape: figures hang in the middle of the cell, a different size per direction (north 112 wide, east 90, south 77, west 128)
boxes = [(10, 122, 20, 147), (38, 128, 46, 123), (46, 123, 38, 128), (10, 138, 11, 123)]
idle = [[figure(*b), figure(b[0] + 1, b[1], b[2], b[3] - 2)] for b in boxes]
walk = [[figure(b[0], b[1] - 1, b[2] + 1, b[3]), figure(*b)] for b in boxes]
i2, w2, moves = G.stand(idle, walk)
for d in range(4):
    box = G.box_of(i2[d] + w2[d])
    check(box[3] == C, 'stand: the lowest pixel of direction %d is on the last row (%d)' % (d, box[3]))
    check(abs((box[0] + box[1]) / 2.0 - 96) <= 0.5, 'stand: direction %d is centred on column 96 (%s)' % (d, box))
    check(box[0] >= 0 and box[1] <= C and box[2] >= 0, 'stand: direction %d stays in the cell' % d)
    # one shift for all frames of a direction: the frames keep their places against each other
    for f0, f1 in zip(idle[d] + walk[d], i2[d] + w2[d]):
        dx, dy = moves[d]
        check(np.array_equal(f0[:C - dy, :C - dx] if dx >= 0 and dy >= 0 else f0, f1[dy:, dx:] if dx >= 0 and dy >= 0 else f0),
              'stand: frame of direction %d only moved by (%d, %d)' % (d, dx, dy))
box_w = G.box_of(i2[3] + w2[3])
check(box_w[1] == C, 'stand: the widest direction ends at the cell edge (%s)' % (box_w,))
check(sum(int((f[..., 3] > 0).sum()) for f in sum(idle, []) + sum(walk, [])) ==
      sum(int((f[..., 3] > 0).sum()) for f in sum(i2, []) + sum(w2, [])), 'stand: no pixel lost')
# a creature narrower than a tile: the middle of its tile (cell - 16); a wider one is moved left until it ends at the cell edge
narrow = [[figure(60, 84, 40, 120)] for _ in range(4)]
n2, _w2, mv = G.stand(narrow, narrow)
check(abs(sum(G.box_of(n2[0])[:2]) / 2.0 - (C - 16)) <= 0.5, 'stand: a narrow figure stands on the middle of its tile')
# the shift never loses art: a frame that would fall off is refused
try:
    G.shifted(figure(100, 160, 100, 160), 5, 0)
    check(False, 'shifted: art falling off the right is refused')
except AssertionError:
    pass
check(np.array_equal(G.shifted(G.shifted(figure(10, 20, 10, 20), 7, 9), -7, -9), figure(10, 20, 10, 20)), 'shifted: back and forth')

print('gen_assets_art_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
