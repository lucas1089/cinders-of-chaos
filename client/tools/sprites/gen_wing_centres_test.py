#!/usr/bin/env python3
"""Tests of gen_wing_centres.py on small synthetic figures (no pair needed; numpy).

python3 -I client/tools/sprites/gen_wing_centres_test.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_wing_centres as gw  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def near(a, b, tol=0.3):
    return a is not None and abs(a - b) <= tol


# ---- the torso: rows 30% to 70% of the opaque box, alpha-weighted
body = np.zeros((64, 64), np.uint8)
body[10:20, 30:34] = 255            # a head at x 30..33 (rows 10-19)
body[20:50, 20:30] = 255            # the trunk at x 20..29
body[50:60, 24:28] = 255            # legs
# box rows 10..59 (50 rows): band rows 25..44 -> only the trunk, x mean 24.5
check(near(gw.torso_x(body), 24.5), 'torso is the trunk, not the head or the legs: %s' % gw.torso_x(body))
staff = body.copy()
staff[25:45, 2:4] = 255             # a staff in the torso rows pulls the centre left
check(gw.torso_x(staff) < 22.0, 'a weapon in the torso rows stays in: %s' % gw.torso_x(staff))
check(gw.torso_x(np.zeros((64, 64), np.uint8)) is None, 'nothing visible')
shifted = np.roll(body, 7, axis=1)
check(near(gw.torso_x(shifted) - gw.torso_x(body), 7.0, 0.01), 'moves with the figure')
half = body.copy()
half[20:50, 20:30] = 128            # alpha weights
check(near(gw.torso_x(half), 24.5), 'uniform alpha: same centre')

# ---- wings frames (RGBA)


def frame(parts, shadow=None, size=(64, 128)):
    f = np.zeros(size + (4,), np.uint8)
    for (y0, y1, x0, x1) in parts:
        f[y0:y1, x0:x1] = (200, 220, 255, 255)
    if shadow:
        y0, y1, x0, x1 = shadow
        f[y0:y1, x0:x1] = (10, 10, 20, 90)
    return f


# two equal wings at x 20..39 and 80..99: centre 59.5
two = frame([(10, 40, 20, 40), (10, 40, 80, 100)])
check(near(gw.wings_x([two]), 59.5), 'two wings, midpoint: %s' % gw.wings_x([two]))
# a large soft shadow on the right does not move it
sh = frame([(10, 40, 20, 40), (10, 40, 80, 100)], shadow=(30, 64, 70, 128))
check(gw.shadow_mask(sh).sum() > 1000, 'shadow found')
check(near(gw.wings_x([sh]), 59.5), 'the baked shadow is left out: %s' % gw.wings_x([sh]))
# the same pixels counted as art (a bright, opaque-enough ring is wing art, not shadow)
glow = sh.copy()
glow[30:64, 70:128] = (250, 250, 250, 150)
check(not gw.shadow_mask(glow)[40, 100], 'a bright partial pixel is not shadow')
# one mass (a fan): the plain mean
fan = frame([(10, 40, 30, 90)])
check(near(gw.wings_x([fan]), 59.5), 'one mass: its mean')
# a thin streak far left of a main wing pair: not a second mass (under 25% of the art)
streak = frame([(10, 40, 60, 100), (5, 35, 2, 4)])
mean_all = gw.wings_x([streak])
# before the rule the streak made the midpoint of streak and main wing (about 31); now it is the mean (about 78)
check(70 < mean_all < 82, 'streak case near the main wing: %s' % mean_all)
# two unequal but both over 25%: the midpoint of the masses, not the mean
uneven = frame([(10, 40, 20, 40), (10, 60, 80, 100)])
check(near(gw.wings_x([uneven]), 59.5), 'two masses of different size: midpoint %s' % gw.wings_x([uneven]))
# phases: the union splits at the widest gap over all phases
a, b = frame([(10, 40, 20, 40), (10, 40, 80, 100)]), frame([(10, 40, 24, 44), (10, 40, 76, 96)])
check(near(gw.wings_x([a, b]), 59.5), 'flapping wings, symmetric: %s' % gw.wings_x([a, b]))
check(gw.wings_x([np.zeros((64, 128, 4), np.uint8)]) is None, 'empty wings')
check(gw.wings_x([]) is None, 'no frames')

# ---- placement and rounding
class T:   # a stand-in for a dat thing: 2x2 look with displacement 8,8
    w = h = 2
    flags = {'displacement': (8, 8)}


check(gw.to_place(40.0, T) == 40.0 - 8 - 32, 'to_place takes the displacement and the tile frame out')
T.flags = {'displacement': (65532, 4)}
check(gw.to_place(40.0, T) == 40.0 + 4 - 32, 'a negative displacement')
check(gw.rnd(2.5) == 3 and gw.rnd(-2.5) == -2 and gw.rnd(-2.6) == -3 and gw.rnd(0.4) == 0, 'rounding')

# ---- the id lists
check(gw.ids('1-3,7') == [1, 2, 3, 7], 'ids')
w = gw.wing_ids()
check(len(w) == len(set(w)) and 937 in w and 2231 in w and 2414 in w and 2385 in w, 'wing ids: %d' % len(w))
check(len(w) == 29 + len(gw.pack33_wings()), 'base 29 plus the pack wings: %d' % len(w))

# ---- heads (O561, base patch 0200)
fig = np.zeros((64, 64), np.uint8)
fig[10:22, 26:34] = 255             # a head, x 26..33 (centre 29.5), rows 10..21
fig[22:50, 22:36] = 255             # the body below
hx, hy = gw.head_xy(fig)
check(near(hx, 29.5 - 0.0, 2.6) and near(hy, 15.0, 0.01), 'head: the top band of the solid body: %s %s' % (hx, hy))
staff = fig.copy()
staff[0:40, 8:10] = 255             # a thin staff held up beside the head: opened away, the head stays
hx2, hy2 = gw.head_xy(staff)
check(near(hx2, hx, 0.01) and near(hy2, hy, 0.01), 'a staff above the head does not move it: %s %s' % (hx2, hy2))
check(gw.head_xy(np.zeros((64, 64), np.uint8)) is None, 'head: nothing visible')
moved = np.roll(np.roll(fig, 5, axis=1), 3, axis=0)
mx, my = gw.head_xy(moved)
check(near(mx - hx, 5.0, 0.01) and near(my - hy, 3.0, 0.01), 'head moves with the figure: %s %s' % (mx - hx, my - hy))
check(gw.HEAD_PIECES == (2477, 2568) and gw.HEAD_REF == 128, 'head piece range and reference look')

if fails:
    print('%d failure(s)' % fails)
    sys.exit(1)
print('gen_wing_centres_test: all checks passed')
