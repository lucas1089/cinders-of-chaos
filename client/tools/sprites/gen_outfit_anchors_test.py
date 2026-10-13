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

# a cape that is a real part of the body (wide) does count: the centre moves towards it
heavy = figure()
heavy[24:50, 38:46] = 255
check(goa.measure(heavy)[0] > cx, 'a wide cape is body mass')

# an oblique figure leaning up and left: the centre is its mass, left of its feet
lean = np.zeros((64, 64), np.uint8)
for k in range(30):
    lean[20 + k, 14 + k // 2:26 + k // 2] = 255
lean[50:60, 29:33] = 255
lean[50:60, 37:41] = 255
l = goa.measure(lean)
check(l[0] < 35, 'a leaning body is centred on its mass, not its feet: %s' % (l,))

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

if fails:
    sys.exit('gen_outfit_anchors_test: %d failed' % fails)
print('gen_outfit_anchors_test: OK')
