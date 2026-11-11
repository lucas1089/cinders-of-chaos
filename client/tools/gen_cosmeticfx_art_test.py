#!/usr/bin/env python3
"""Tests of the foot marks of gen_cosmeticfx_art.py (O499): size, centring, both feet, determinism, the check.

python3 -I client/tools/gen_cosmeticfx_art_test.py   (Pillow, numpy)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_cosmeticfx_art as g  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


made = g.images()
for key in g.PRINTS:
    for side in 'lr':
        im = made[('marks', '%s_%s.png' % (key, side))]
        check(im.size == (g.MARK, g.MARK), '%s_%s size %s' % (key, side, im.size))
        a = np.asarray(im)[..., 3].astype(float)
        check(a.sum() > 2000, '%s_%s has paint' % (key, side))
        ys, xs = np.mgrid[0:g.MARK, 0:g.MARK]
        cx, cy = (xs * a).sum() / a.sum(), (ys * a).sum() / a.sum()
        # the mark's centre of mass is near the canvas centre: the module centres the picture on the foot
        check(abs(cx - g.MARK / 2) < 6 and abs(cy - g.MARK / 2) < 8, '%s_%s centred: %.1f %.1f' % (key, side, cx, cy))
        # nothing is cut at the edge (a hard edge of paint would show as a line on the floor)
        edge = max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max())
        check(edge < 40, '%s_%s clear at its edge: %d' % (key, side, edge))
    left, right = made[('marks', key + '_l.png')], made[('marks', key + '_r.png')]
    check(left.tobytes() != right.tobytes(), '%s: the two feet differ' % key)
# the pair pictures are untouched by the marks: 14 styles of 64 x 64
check(all(made[('prints', k + '.png')].size == (g.P, g.P) for k in g.PRINTS), 'prints stay 64 x 64')
# deterministic
again = g.images()
check(all(again[k].tobytes() == made[k].tobytes() for k in made), 'the same pictures twice')
# the committed files are what the generator draws (the same as --check)
check(g.check(made) == [], 'committed pictures: %s' % g.check(made))
print('gen_cosmeticfx_art_test: %s' % ('OK' if not fails else '%d failed' % fails))
sys.exit(1 if fails else 0)
