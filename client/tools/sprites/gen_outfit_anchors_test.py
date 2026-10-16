#!/usr/bin/env python3
"""Tests of gen_outfit_anchors.py's measure() on small synthetic figures (no pair needed; numpy).

python3 -I client/tools/sprites/gen_outfit_anchors_test.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_outfit_anchors as goa  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def figure():
    """a 64x64 canvas: a body 12 wide from row 20 to 49, two legs (4 wide, a 4 px gap) from row 50 to 59"""
    a = np.zeros((64, 64), np.uint8)
    a[20:50, 26:38] = 255
    a[50:60, 26:30] = 255
    a[50:60, 34:38] = 255
    return a


# a standing figure: centred on its body, standing on its legs
plain = goa.measure(figure())
cx, ground, top, left, right, flt, reach = plain
check(cx == 32, 'centre of a symmetric body: %s' % cx)
check(52 <= ground <= 58, 'the ground row in the legs, near the soles: %s' % ground)
check((top, left, right, flt) == (20, 26, 38, 0), 'bounds and not floating: %s' % (plain,))
check(reach == 6, 'reach: half the body: %s' % reach)

# a cape tip: one pixel wide, hanging between the legs 4 rows below the feet: neither the centre nor the ground move
cape = figure()
cape[50:64, 31] = 255
c = goa.measure(cape)
check(c[0] == cx and c[1] == ground, 'a cape tip moves neither the centre nor the ground: %s' % (c,))
check(c[2] == 20 and c[4] == 38, 'the bounds still hold the whole picture')

# a long thin staff held out to the left: the centre stays on the body, the bounds hold the staff
staff = figure()
staff[30:32, 2:26] = 255
s = goa.measure(staff)
check(s[0] == cx and s[3] == 2 and s[6] <= 7, 'a thin staff moves neither the centre nor the reach: %s' % (s,))

# a staff three pixels thick (a torch, a leafy staff) is still what the body holds, not the body
thick = figure()
thick[8:48, 14:17] = 255
t3 = goa.measure(thick)
check(t3[0] == cx and t3[1] == ground and t3[3] == 14, 'a thick staff moves neither the centre nor the ground: %s' % (t3,))

# a leafy staff: a thin shaft with a big clump of leaves at its end; the clump is not the body
leafy = figure()
leafy[10:40, 15] = 255
leafy[4:12, 8:20] = 255
check(goa.measure(leafy)[0] == cx, 'the leaves at the end of a staff do not move the centre: %s' % (goa.measure(leafy),))

# the other horizontal anchors: the box of the whole figure (the staff included) and halfway to it
check(goa.measure(staff, centre='bbox')[0] == (2 + 38) // 2, 'bbox centre: the whole figure')
check(goa.measure(staff, centre='blend')[0] == int((cx + 20) / 2 + 0.5), 'blend: halfway')
check(goa.measure(staff, centre='body')[1:] == goa.measure(staff, centre='bbox')[1:], 'only the centre changes')

# a cape that is a real part of the body (wide) does count: the centre moves towards it
heavy = figure()
heavy[24:50, 38:46] = 255
check(goa.measure(heavy, centre='body')[0] > cx, 'a wide cape is body mass')

# an oblique figure leaning up and left (every look of the pair leans so): the body anchor is its mass, left of its
# feet; the feet anchor (the default) is the feet's own centre, so the feet stand on the dais centre
lean = np.zeros((64, 64), np.uint8)
for k in range(30):
    lean[20 + k, 14 + k // 2:26 + k // 2] = 255
lean[50:60, 29:33] = 255
lean[50:60, 37:41] = 255
l = goa.measure(lean, centre='body')
check(l[0] < 33, 'a leaning body: the body anchor is its mass, left of its feet: %s' % (l,))
lf = goa.measure(lean)
check(goa.CENTRE == 'feet', 'the feet are the default anchor')
check(34 <= lf[0] <= 36, 'a leaning body: the feet anchor is between the two feet (29-41): %s' % (lf,))
check(lf[0] - l[0] >= 4, 'the feet anchor is right of the mass on a leaning look: %s %s' % (lf, l))
check(54 <= lf[1] <= 58, 'the feet anchor row is in the feet, not where their band starts: %s' % (lf,))
check(lf[2:] == l[2:], 'bounds, flag and reach do not depend on the anchor')
# the feet anchor ignores what hangs under or beside the feet: a cape tip, a staff
check(goa.measure(cape)[:2] == plain[:2], 'feet: a cape tip moves nothing')
check(goa.measure(thick)[:2] == plain[:2], 'feet: a thick staff moves nothing')
grounded = figure()
grounded[30:60, 8:11] = 255         # a staff standing on the ground beside the body, three pixels thick
check(goa.measure(grounded)[:2] == plain[:2], 'feet: the foot of a staff beside the body is not a foot: %s' % (goa.measure(grounded),))

# a floating look (a robe, no feet): its ground is its lowest solid row and it says it floats
robe = np.zeros((64, 64), np.uint8)
robe[20:56, 24:40] = 255
robe[56:62, 30:31] = 255           # a thin wisp under it
f = goa.measure(robe, floating=True)
check(f[5] == 1 and goa.measure(robe)[5] == 0, 'floating: flagged')
check(f[:5] == goa.measure(robe)[:5] and f[1] < 56, 'floating: the same ground in its mass (the wisp ignored): %s' % (f,))

# canvas to tile pixels; nothing visible
check(goa.measure(figure(), -40, -40)[:2] == (cx - 40, ground - 40), 'offsets applied')
check(goa.measure(np.zeros((32, 32), np.uint8)) is None, 'nothing visible')
check({2184, 2183} <= goa.FLOATING, 'the robed Necromancer ascension looks are listed as floating')

# the dat's displacement is two u16: -6,-12 is stored as 65530,65524 and must shift the anchors like -6,-12
class Thing:
    w = h = 1

    def __init__(self, disp):
        self.flags = {'displacement': disp}


real_south = goa.south_alpha
goa.south_alpha = lambda t, spr: figure()[:32, 16:48]
neg = goa.anchor_of(Thing((65530, 65524)), None, 1)
check(neg == goa.measure(figure()[:32, 16:48], 6, 12, False), 'a negative displacement is signed: %s' % (neg,))
check(goa.anchor_of(Thing((8, 8)), None, 1) == goa.measure(figure()[:32, 16:48], -8, -8, False),
      'a positive displacement is unchanged')
goa.south_alpha = real_south

if fails:
    sys.exit('gen_outfit_anchors_test: %d failed' % fails)
print('gen_outfit_anchors_test: OK')
