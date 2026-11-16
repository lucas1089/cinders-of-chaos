#!/usr/bin/env python3
"""Tests of gen_drawn_wings.py (O581): the drawing rules hold on every frame of every design (numpy, Pillow; no pair).

python3 -I client/tools/sprites/gen_drawn_wings_test.py
"""
import os
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_drawn_wings as gd  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


S, F = gd.SIZE, gd.FRAMES

# ---- the kit
sq = gd.poly_mask([(10, 10), (20, 10), (20, 16), (10, 16)])
check(sq.sum() == 60 and sq[10, 10] and sq[15, 19] and not sq[16, 10] and not sq[10, 20], 'poly_mask fills pixel centres')
check(gd.disc_mask(30.5, 30.5, 0.6).sum() == 1, 'a disc under one pixel wide is one pixel')
idx = gd.edge_shade(sq, 3, 2, 1)
check(idx[10, 12] == 3 and idx[12, 10] == 3 and idx[15, 15] == 1 and idx[13, 19] == 1 and idx[12, 14] == 2,
      'edge_shade: lit top and left, dark bottom and right')
c = gd.Canvas((1, 2, 3))
c.piece(sq, idx, ((0, 0, 0), (50, 50, 50), (100, 100, 100), (200, 200, 200)))
c.spark(40, 40, (250, 250, 0), 1)
c.spark(12, 9, (250, 250, 0), 1)             # on the outline ring: not painted
c.spark(60, 60, (9, 9, 9), 0)
img = c.finish()
check(tuple(img[9, 12]) == (1, 2, 3, 255), 'the ring is the outline colour and a spark does not repaint it')
check(tuple(img[40, 40]) == (250, 250, 0, 255) and img[40, 41, 3] == gd.GLOW_ALPHA and img[39, 40, 3] == gd.GLOW_ALPHA,
      'a spark is a core with glow arms')
check(img[60, 60, 3] == gd.GLOW_ALPHA and img[41, 41, 3] == 0, 'a glow dot; no glow on the diagonal')
back = np.zeros((S, S, 4), np.uint8)
front = np.zeros((S, S, 4), np.uint8)
back[5, 5] = (10, 10, 10, 255)
front[5, 5] = (99, 99, 99, gd.GLOW_ALPHA)
front[6, 6] = (99, 99, 99, gd.GLOW_ALPHA)
front[7, 7] = (7, 7, 7, 255)
m = gd.merge(back, front)
check(tuple(m[5, 5]) == (10, 10, 10, 255) and m[6, 6, 3] == gd.GLOW_ALPHA and tuple(m[7, 7]) == (7, 7, 7, 255),
      'merge: front over back, a glow pixel never repaints an opaque one')
check(len(gd.KEYS) == 6 and len(set(gd.KEYS)) == 6, 'six designs')
check(gd.anchor_row() == {d: gd.ANCHOR[0] - 64 for d in gd.DIRS}, 'the wings centre row is the anchor')
p0 = gd.project((0, 0, 0), 'south')
check(abs(p0[0] - gd.ANCHOR[0]) < 1e-9 and abs(p0[1] - gd.ANCHOR[1]) < 1e-9, 'the model origin is the anchor')
check(gd.project((0, 0, -5), 'south')[2] < 0 < gd.project((0, 0, -5), 'north')[2], 'the back is behind when facing south')
check(gd.project((0, 0, -5), 'east')[0] < gd.ANCHOR[0] < gd.project((0, 0, -5), 'west')[0], 'the back is left when facing east')


def touches_open(alpha):
    """opaque pixels with a transparent 4-neighbour"""
    op = alpha == 255
    clear = alpha == 0
    near = np.zeros_like(op)
    near[1:, :] |= clear[:-1, :]
    near[:-1, :] |= clear[1:, :]
    near[:, 1:] |= clear[:, :-1]
    near[:, :-1] |= clear[:, 1:]
    return op & near


def frame_rules(img, outline, what):
    a = img[..., 3]
    check(set(np.unique(a).tolist()) <= {0, 255, gd.GLOW_ALPHA}, what + ': alpha is 0, 255 or the glow level')
    edge = touches_open(a)
    bad = edge & ~(img[..., :3] == np.asarray(outline, np.uint8)).all(axis=2)
    check(not bad.any(), what + ': %d edge pixels are not the outline colour' % int(bad.sum()))
    check(not (a[0, :].any() or a[-1, :].any() or a[:, 0].any() or a[:, -1].any()), what + ': art touches the cell border')
    check(not img[a == 0][:, :3].any(), what + ': a transparent pixel carries colour')


# ---- every design, every frame
for key, title, outline, fn, pivot in gd.DESIGNS:
    frames = gd.render(key)
    again = gd.render(key)
    glow = 0
    used = {'back': 0, 'front': 0}
    merged = {}
    for d in gd.DIRS:
        check(len(frames[d]) == F, '%s %s: 16 frames' % (key, d))
        merged[d] = []
        for f in range(F):
            back, front = frames[d][f]
            check(back.shape == (S, S, 4) and front.shape == (S, S, 4) and back.dtype == np.uint8, '%s: frame size' % key)
            check(np.array_equal(back, again[d][f][0]) and np.array_equal(front, again[d][f][1]),
                  '%s %s %d: the same pixels twice' % (key, d, f))
            both = gd.merge(back, front)
            for name, img in (('back', back), ('front', front), ('merged', both)):
                frame_rules(img, outline, '%s %s %d %s' % (key, d, f, name))
            used['back'] += int((back[..., 3] == 255).sum())
            used['front'] += int((front[..., 3] == 255).sum())
            glow += int((both[..., 3] == gd.GLOW_ALPHA).sum())
            check((both[..., 3] == 255).sum() >= 120, '%s %s %d: the art is there' % (key, d, f))
            merged[d].append(both)
        # the loop closes: every step moves, and the step from frame 15 to frame 0 is no bigger than the others
        steps = [int((merged[d][i] != merged[d][(i + 1) % F]).any(axis=2).sum()) for i in range(F)]
        check(min(steps) > 0, '%s %s: a frame equals the next (%s)' % (key, d, steps))
        check(steps[F - 1] <= 1.5 * max(steps[:F - 1]), '%s %s: a jump from frame 15 to frame 0 (%s)' % (key, d, steps))
        check(not np.array_equal(merged[d][0], merged[d][F // 2]), '%s %s: half a cycle later it looks the same' % (key, d))
    check(used['back'] > 0 and used['front'] > 0, '%s: both layers are used (%s)' % (key, used))
    check(glow > 0, '%s: sparks' % key)
    for i, a in enumerate(gd.DIRS):
        for b in gd.DIRS[i + 1:]:
            check(not np.array_equal(merged[a][0], merged[b][0]), '%s: %s and %s look the same' % (key, a, b))
    check(not np.array_equal(merged['east'][0], merged['west'][0][:, ::-1]), '%s: west is not east mirrored' % key)
    # the art stands round the anchor: its mass is within a tile of it
    ys, xs = np.nonzero(np.max([m[..., 3] for d in gd.DIRS for m in merged[d]], axis=0))
    check(abs(xs.mean() - gd.ANCHOR[0]) < 16 and abs(ys.mean() - gd.ANCHOR[1]) < 24,
          '%s: the art is far from the anchor (%.1f, %.1f)' % (key, xs.mean(), ys.mean()))

# ---- the files: sizes, the same bytes twice
with tempfile.TemporaryDirectory() as tmp:
    a_dir, b_dir = os.path.join(tmp, 'a'), os.path.join(tmp, 'b')
    one = gd.build(a_dir, ('void_orbit', 'grave_lanterns'))
    two = gd.build(b_dir, ('void_orbit', 'grave_lanterns'))
    check(sorted(os.path.basename(p) for p in one) == sorted('%s_%s.png' % (k, n) for k in ('void_orbit', 'grave_lanterns')
                                                             for n in ('sheet', 'back', 'front')), 'three files a design')
    for pa, pb in zip(one, two):
        check(open(pa, 'rb').read() == open(pb, 'rb').read(), 'the same bytes twice: ' + os.path.basename(pa))
        im = Image.open(pa)
        check(im.size == (S * F, S * len(gd.DIRS)) and im.mode == 'RGBA', 'sheet size and mode: ' + os.path.basename(pa))
    sheet = np.asarray(Image.open(os.path.join(a_dir, 'void_orbit_sheet.png')))
    back, front = gd.render_frame('void_orbit', 'south', 3)
    r = gd.DIRS.index('south')
    check(np.array_equal(sheet[r * S:(r + 1) * S, 3 * S:4 * S], gd.merge(back, front)), 'rows north east south west, 16 columns')
    check(gd.main(['build', os.path.join(tmp, 'c'), '--only', 'bladefan']) == 0 and
          sorted(os.listdir(os.path.join(tmp, 'c'))) == ['bladefan_back.png', 'bladefan_front.png', 'bladefan_sheet.png'],
          'build --only')

# ---- the preview body without a pair
for d in gd.DIRS:
    body = gd.silhouette(d)
    ys, xs = np.nonzero(body[..., 3])
    check(len(xs) > 150 and abs(xs.mean() - gd.ANCHOR[0]) < 6 and abs(ys.mean() - gd.ANCHOR[1]) < 6, 'silhouette on the anchor ' + d)
frames = {d: [gd.render_frame('void_orbit', d, 0)] for d in gd.DIRS}
strip = gd.strip(frames, {d: gd.silhouette(d) for d in gd.DIRS}, 0)
check(strip.shape == (S, S * 4, 3), 'preview strip: four directions side by side')

if fails:
    print('%d FAILED' % fails)
    sys.exit(1)
print('gen_drawn_wings_test: OK')
