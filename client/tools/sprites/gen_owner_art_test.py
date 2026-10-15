#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_owner_art_test.py : gen_owner_art.py on synthetic sheets (cells and frame
order of both monster layouts, the west wings mirrored about the wearer's axis and kept inside the cell, plant blobs
cut in sheet order and stood on the item's tile, alpha cleaning, the sheet rules) and the spec (ids after pair 25,
one row per look and item, the picks)."""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_owner_art as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def mark(c, v):
    """a c x c cell with one opaque pixel whose red channel is v"""
    a = np.zeros((c, c, 4), np.uint8)
    a[c - 2, c - 2] = (v, 0, 0, 255)
    return a


# sheet8: 8 x 5 cells of 64 px; walk rows by direction, idle row 4
s = np.zeros((320, 512, 4), np.uint8)
for r in range(5):
    for k in range(8):
        s[r * 64:(r + 1) * 64, k * 64:(k + 1) * 64] = mark(64, r * 10 + k + 1)
idle, walk = G.monster_frames(s, 'sheet8', 64, 8)
check([int(f[62, 62, 0]) for f in idle] == [41, 42, 43, 44], 'sheet8: idle = row 4, one column per direction')
check(len(walk) == 8 and [int(f[62, 62, 0]) for f in walk[3]] == [4, 14, 24, 34], 'sheet8: walk phase p of direction d = row d, column p')
# grid: one column per direction, one row per phase; idle = phase 0
g = np.zeros((3 * 128, 4 * 128, 4), np.uint8)
for r in range(3):
    for k in range(4):
        g[r * 128:(r + 1) * 128, k * 128:(k + 1) * 128] = mark(128, r * 10 + k + 1)
idle, walk = G.monster_frames(g, 'grid', 128, 3)
check([int(f[126, 126, 0]) for f in idle] == [1, 2, 3, 4] and [int(f[126, 126, 0]) for f in walk[2]] == [21, 22, 23, 24],
      'grid: columns are directions, rows phases, idle = phase 0')
sheet = G.look_sheet(idle, walk)
check(sheet.shape == (4 * 128, 4 * 128, 4) and int(sheet[128 + 126, 126, 0]) == 1, 'look sheet: idle row then the walk rows')

# mirror about an axis, moved back inside
c = np.zeros((96, 96, 4), np.uint8)
c[40, 20:30] = (9, 9, 9, 255)
m = G.mirror_about(c, 50)
xs = np.nonzero(m[40, :, 3])[0]
check(list(xs) == list(range(71, 81)), 'mirror: x -> 100 - x (%s)' % list(xs[:3]))
c2 = np.zeros((96, 96, 4), np.uint8)
c2[10, 2:12] = (9, 9, 9, 255)
xs = np.nonzero(G.mirror_about(c2, 50)[10, :, 3])[0]
check(xs.max() == 95 and len(xs) == 10, 'mirror: a tip past the edge is moved back inside, nothing cut')

# wings: west column from the east one
w = np.zeros((96 * 2, 96 * 4, 4), np.uint8)
for p in range(2):
    for d, x in enumerate((50, 30, 50, 30)):
        w[p * 96 + 40, d * 96 + x - 2:d * 96 + x + 3] = (d + 1, 0, 0, 255)
fr = G.wings_frames(w, 2, True)
west = fr[1][3]
check(int(west[40, 70, 0]) == 2 and not west[40, 30, 3], 'wings: west = east mirrored about the north / south centre')
check(int(G.wings_frames(w, 2, False)[0][3][40, 30, 0]) == 4, 'wings: the west column kept when not asked')

# plants: blobs in sheet order, each stood on the item tile
pl = np.zeros((128, 192, 4), np.uint8)
pl[10:40, 100:110] = (0, 200, 0, 255)      # row band 0, right
pl[20:50, 10:30] = (0, 200, 0, 255)        # row band 0, left
pl[50, 40] = (0, 200, 0, 255)              # a speck 1 px away from nothing: its own blob
pl[80:120, 60:90] = (0, 200, 0, 255)       # row band 1
bl = G.blobs(pl)
check(len(bl) == 4 and [b[1] for b in bl] == [10, 40, 100, 60], 'blobs: sorted by 64 px band of the lowest row, then x (%s)'
      % [b[1] for b in bl])
cv = G.plant_canvas(pl, bl[3])
ys, xs = np.nonzero(cv[..., 3])
check(ys.max() == G.CACTUS_FOOT_Y and round(xs[ys == ys.max()].mean()) == G.CACTUS_FOOT_X, 'plant: foot on the tile, x 48, y 61')
check(cv[..., 3].sum() == pl[80:120, 60:90, 3].sum(), 'plant: every art pixel kept')

# alpha cleaning and the sheet rules
a = np.zeros((4, 4, 4), np.uint8)
a[0, 0] = (5, 5, 5, 11)
a[1, 1] = (5, 5, 5, 12)
cl = G.clean(a)
check(not cl[0, 0].any() and cl[1, 1, 3] == 12, 'clean: alpha under 12 cleared, the rest kept')
check(any('missing' in b for b in G.check_rules({})), 'rules: a missing sheet is reported')

# the spec
check(len(G.LOOKS) == 12 and len(G.WINGS) == 9 and len(G.CACTI) == 45, 'spec: 12 monsters, 9 wings, 45 plants')
picks = G.picks_rows()
check([r[1] for r in picks] == list(range(2213, 2234)), 'picks: looks 2213..2233 after pair 25')
check({r[5] for r in picks} == {'hunt', 'dungeonboss', 'storewings', 'exclusive'}, 'picks: families')
check(sum(1 for r in picks if r[5] == 'dungeonboss') == 4, 'picks: the four deep dungeon bosses')
check(all(src in G.SOURCES for _k, src, *_r in G.LOOKS + [(w[0], w[1]) for w in G.WINGS]), 'spec: every source listed')
sheets = G.read_sheets()
if len(sheets) == len(G.expected_shapes()):
    rows = G.things_rows(sheets)
    check(len(rows) == 21 + 46 and [r[1] for r in rows[:21]] == ['outfit'] * 21, 'things: 21 outfits then 46 items')
    check(rows[-1][0] == 'waypoint_seal' and rows[-1][7] == 3 and rows[-1][10] == 60, 'things: the 3x3 seal, 60 phases')
    check(G.check_rules(sheets) == [], 'committed sheets follow the rules')
else:
    check(False, 'committed sheets: run gen_owner_art.py build --src DIR')

print('gen_owner_art_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
