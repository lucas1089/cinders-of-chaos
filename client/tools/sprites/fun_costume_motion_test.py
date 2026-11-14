#!/usr/bin/env python3
"""Tests of fun_costume_motion.py and gen_dusk_moth.py (O578): hops and breaths on a synthetic picture, the palette lock, `prepare` on a
fake PixelLab download, and the moth's own rules (28 phases, no frame skips, the loop closes, the same frames every run). Needs numpy
and Pillow (the fx venv of CI).

    python3 -I client/tools/sprites/fun_costume_motion_test.py
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import fun_costume_motion as M  # noqa: E402
import gen_dusk_moth as MOTH  # noqa: E402


def blob(cv=48, top=10, left=14, h=30, w=20):
    a = np.zeros((cv, cv, 4), np.uint8)
    a[top:top + h, left:left + w] = (200, 60, 60, 255)
    a[top, left:left + w] = (20, 16, 26, 255)
    a[top + h - 1, left:left + w] = (20, 16, 26, 255)
    a[top + 4:top + 7, left + 4:left + 8] = (250, 250, 250, 255)
    return a


def main():
    a = blob()
    x0, y0, x1, y1 = M.bbox(a)
    # morph: same size is the same picture; the bottom stays, the outline rows stay
    assert np.array_equal(M.morph(a), a)
    b = M.morph(a, 1.1, 0.8)
    bx0, by0, bx1, by1 = M.bbox(b)
    assert by1 == y1 and (by1 - by0 + 1) == round(30 * 0.8) and (bx1 - bx0 + 1) == round(20 * 1.1)
    assert tuple(b[by0, bx0 + 3, :3]) == (20, 16, 26) and tuple(b[by1, bx0 + 3, :3]) == (20, 16, 26), 'first and last rows kept'
    c = M.morph(a, 1.0, 1.0, lift=5)
    assert M.bbox(c)[3] == y1 - 5
    d = M.morph(a, 1.0, 1.0, lean=2.0)
    assert M.bbox(d)[0] != M.bbox(a)[0] or M.bbox(d)[2] != M.bbox(a)[2], 'the top leans'
    assert (d[y1, :, 3] > 0).sum() == (a[y1, :, 3] > 0).sum() and np.array_equal(d[y1], a[y1]), 'the base does not move'
    # hop: n phases, two hops, different neighbours, bottoms on or above the ground, the first and the last phase lead into each other
    hop = M.hop_cycle(a, 12)
    assert len(hop) == 12 and all(h.shape == a.shape for h in hop)
    assert all(not np.array_equal(hop[i], hop[(i + 1) % 12]) for i in range(12))
    assert all(M.bbox(h)[3] <= y1 for h in hop) and max(y1 - M.bbox(h)[3] for h in hop) >= 3
    side = [M.bbox(h)[0] + M.bbox(h)[2] for h in hop]
    assert min(side) < max(side), 'a waddle: the figure leans one way, then the other'
    assert len(M.hop_cycle(a, 12, scale=0.5)) == 12
    br = M.breath_cycle(a, 4)
    assert len(br) == 4 and not np.array_equal(br[0], br[2]) and np.array_equal(br[0], a)
    # palette lock: a noisy frame is pulled to the colours of the references and gets hard alpha
    noisy = a.copy()
    noisy[15, 20, :3] = (203, 58, 61)
    noisy[16, 20] = (10, 10, 10, 100)
    locked = M.lock_palette([noisy], [a], 1)[0]
    assert tuple(locked[15, 20, :3]) == (200, 60, 60) and locked[16, 20, 3] == 0 and set(np.unique(locked[..., 3])) <= {0, 255}
    # prepare on a fake download
    with tempfile.TemporaryDirectory() as tmp:
        st = os.path.join(tmp, 'dl', 'Idle')
        for d in M.DIRS:
            os.makedirs(os.path.join(st, 'rotations'), exist_ok=True)
            Image.fromarray(blob(left=14 + M.DIRS.index(d))).save(os.path.join(st, 'rotations', d + '.png'))
            os.makedirs(os.path.join(st, 'animations', 'w8', d))
            for i in range(8):
                Image.fromarray(blob(top=10 + i % 2)).save(os.path.join(st, 'animations', 'w8', d, 'frame_%03d.png' % i))
        out = os.path.join(tmp, 'out')
        assert M.prepare(os.path.join(tmp, 'dl'), out, 'hop', phases=12) == 12
        assert len(os.listdir(os.path.join(out, 'walk', 'east'))) == 12 and len(os.listdir(os.path.join(out, 'idle', 'south'))) == 4
        out2 = os.path.join(tmp, 'out2')
        assert M.prepare(os.path.join(tmp, 'dl'), out2, 'walk', anim='w8') == 8
        assert os.path.exists(os.path.join(out2, 'rot', 'west.png'))
        # match: a direction 6 rows taller than the south one is cut to the same height
        Image.fromarray(blob(h=36, top=6)).save(os.path.join(st, 'rotations', 'east.png'))
        out3 = os.path.join(tmp, 'out3')
        M.prepare(os.path.join(tmp, 'dl'), out3, 'hop', match=3)
        e = np.array(Image.open(os.path.join(out3, 'rot', 'east.png')))
        assert M.bbox(e)[3] - M.bbox(e)[1] + 1 == 30

    # the moth
    fr = MOTH.all_frames()
    assert set(fr) == set(MOTH.DIRS) and all(len(v) == MOTH.PHASES >= 24 for v in fr.values())
    assert all(a.shape == (32, 32, 4) for v in fr.values() for a in v)
    assert MOTH.problems(fr) == [], MOTH.problems(fr)
    again = MOTH.all_frames()
    assert all(np.array_equal(x, y) for d in MOTH.DIRS for x, y in zip(fr[d], again[d])), 'the same pictures every run'
    # the angle: wings up at phase 0, down at the middle, a soft turn at both ends (the step shrinks to nothing near the top and the bottom)
    ang = [MOTH.angle_at(i) for i in range(MOTH.PHASES)]
    assert ang[0] > 50 and ang[MOTH.PHASES // 2] < -20
    steps = [abs(ang[(i + 1) % MOTH.PHASES] - ang[i]) for i in range(MOTH.PHASES)]
    assert steps[0] < 0.2 * max(steps) and steps[MOTH.PHASES // 2 - 1] < 0.3 * max(steps) and steps[MOTH.PHASES // 2] < 0.3 * max(steps), steps
    assert max(steps) < 12, 'no phase turns the wing by more than 12 degrees'
    lift = [MOTH.lift_at(i) for i in range(MOTH.PHASES)]
    assert abs(lift[MOTH.PHASES // 4] - max(lift)) < 0.3 and abs(lift[3 * MOTH.PHASES // 4] - min(lift)) < 0.3, 'the bob follows the stroke'
    # outline: every rim pixel is the near-black colour
    a = fr['south'][5]
    op = a[..., 3] > 0
    assert (a[op][:, :3] == np.array(MOTH.OUTLINE)).all(axis=1).sum() > 20
    print('fun_costume_motion_test: OK')


if __name__ == '__main__':
    main()
