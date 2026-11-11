#!/usr/bin/env python3
"""Tests of gen_foot_marks.py on a synthetic creature thing (no pair needed; numpy).

python3 -I client/tools/sprites/gen_foot_marks_test.py
"""
import os
import sys
from types import SimpleNamespace

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_foot_marks as gfm  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


class FakeSpr:
    def __init__(self, tiles):
        self.tiles = tiles

    def sprite(self, sid):
        return self.tiles.get(sid)


def tile(rows):
    a = np.zeros((32, 32, 4), np.uint8)
    for y0, y1, x0, x1 in rows:
        a[y0:y1, x0:x1, 3] = 255
        a[y0:y1, x0:x1, :3] = 120
    return a


def thing(px, per_dir, w=1, h=1, disp=None):
    """a 1x1 thing: sprite id d + 1 holds direction d's picture (a body 12 wide, two legs below)"""
    flags = {'displacement': disp} if disp else {}
    return SimpleNamespace(w=w, h=h, px=px, py=1, pz=1, layers=1, phases=1, flags=flags,
                           sprites=list(range(1, px + 1)))


# a body in rows 8-23 of columns 10-22 and two legs in rows 24-30 under columns 10-14 and 18-22; direction 1 is the
# same figure moved 6 px right
base = [(8, 24, 10, 22), (24, 31, 10, 14), (24, 31, 18, 22)]
shifted = [(y0, y1, x0 + 6, x1 + 6) for y0, y1, x0, x1 in base]
spr = FakeSpr({1: tile(base), 2: tile(shifted), 3: tile(base), 4: tile(base)})
t = thing(4, None)
row = gfm.thing_feet(t, spr)
check(row is not None and len(row) == 8, 'eight numbers: %s' % (row,))
nx, ny, ex, ey, sx, sy, wx, wy = row
check((nx, ny) == (sx, sy) == (wx, wy), 'the same picture gives the same feet in every direction')
check(ex - sx == 6 and ey == sy, 'a figure 6 px further right has feet 6 px further right: %s' % (row,))
check(14 <= sx <= 18 and 26 <= sy <= 30, 'the feet are between the legs, low: %s' % ((sx, sy),))

# the displacement moves the feet into the coordinates the client draws in (up and left of the tile)
t2 = thing(4, None, disp=(8, 8))
row2 = gfm.thing_feet(t2, spr)
check(row2[4] == sx - 8 and row2[5] == sy - 8, 'displacement applied: %s vs %s' % (row2, row))

# a single-direction look repeats its one frame
t1 = thing(1, None)
r1 = gfm.thing_feet(t1, FakeSpr({1: tile(base)}))
check(r1 == [sx, sy] * 4, 'one direction repeated: %s' % (r1,))

# nothing visible: no row
check(gfm.thing_feet(thing(1, None), FakeSpr({})) is None, 'an empty look has no feet')

# the Lua text: sorted rows, six to a line, the md5 in the header, parses as the module expects
text = gfm.lua_text([(5, [1, 2, 3, 4, 5, 6, 7, 8]), (9, [-1, 2, 3, 4, 5, 6, 7, 8])], 'abc')
check('dat = "abc"' in text and '[5]={1,2,3,4,5,6,7,8}' in text and '[9]={-1,2,3,4,5,6,7,8}' in text, 'rows: %s' % text)
check(text.rstrip().endswith('return CosmeticFootMarks'), 'returns the table')
check(gfm.lua_text([(5, [1] * 8)], 'abc') == gfm.lua_text([(5, [1] * 8)], 'abc'), 'deterministic')

print('gen_foot_marks_test: %s' % ('OK' if not fails else '%d failed' % fails))
sys.exit(1 if fails else 0)
