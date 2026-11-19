#!/usr/bin/env python3
"""Tests of client/tools/gen_lootburst_art.py (O677): the loot burst pictures are the sizes the module assumes, soft (no hard edge), tintable
(the light parts are white), deterministic, and they play out (the first frame is the strongest, the last nearly gone).

python3 -I client/tools/gen_lootburst_art_test.py       (numpy and Pillow; the fx venv in CI)
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import gen_lootburst_art as G  # noqa: E402

fails = 0
checks = 0


def eq(a, b, what):
    global fails, checks
    checks += 1
    if a != b:
        print('FAIL %s: %r != %r' % (what, a, b))
        fails += 1


def ok(cond, what):
    eq(bool(cond), True, what)


def alpha(arr):
    return arr[..., 3].astype(np.float32) / 255.0


def frames_of(name, arr):
    w, h, n = G.SHEETS[name]
    return [arr[:, k * w:(k + 1) * w] for k in range(n)]


sheets = {name: G.sheet(name) for name in G.SHEETS}
eq(sorted(G.SHEETS), ['dust', 'flash', 'glow', 'ring', 'shadow'], 'five pictures')
for name, (w, h, n) in G.SHEETS.items():
    arr = sheets[name]
    eq(arr.shape, (h, w * n, 4), '%s: strip size' % name)
    eq(arr.dtype, np.uint8, '%s: 8 bit' % name)
    ok(alpha(arr).max() > 0.3, '%s: something is drawn' % name)
    ok(np.array_equal(G.sheet(name), arr), '%s: the same picture twice' % name)
    for k, fr in enumerate(frames_of(name, arr)):
        a = alpha(fr)
        edge = max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max())
        ok(edge < 0.06, '%s frame %d: the glow stops before the frame edge (%.3f)' % (name, k, edge))
        step = max(np.abs(np.diff(a, axis=0)).max(), np.abs(np.diff(a, axis=1)).max())
        ok(step <= 0.7, '%s frame %d: no hard edge, biggest step %.2f' % (name, k, step))

# the light parts are white (the module tints them with the group colour); the dust is warm grey; the shadow is black
for name in ('flash', 'ring', 'glow'):
    arr = sheets[name]
    solid = arr[arr[..., 3] > 40][:, :3]
    ok(len(solid) > 0 and (solid == 255).all(), '%s: white, so the tint shows true' % name)
dust = sheets['dust']
px = dust[dust[..., 3] > 40][:, :3].astype(np.float32).mean(axis=0)
ok(px[0] > px[2] and 150 < px.mean() < 230, 'dust: warm, light')
sh = sheets['shadow']
ok((sh[..., :3] == 0).all(), 'shadow: black')
ok(0.45 < alpha(sh).max() < 0.7, 'shadow: soft, never solid (%.2f)' % alpha(sh).max())

# the strips play out: strong at the start, nearly gone at the end
for name in ('flash', 'ring', 'dust'):
    fs = frames_of(name, sheets[name])
    tot = [float(alpha(f).sum()) for f in fs]
    ok(tot[-1] < tot[0] * 0.8 or tot[-1] < tot[len(tot) // 2], '%s: it fades out (%s)' % (name, ['%.0f' % t for t in tot]))
    ok(max(alpha(fs[-1]).max(), 0) < max(alpha(f).max() for f in fs), '%s: the last frame is not the strongest' % name)
fl = frames_of('flash', sheets['flash'])
ws = [np.nonzero(alpha(f) > 0.1)[1] for f in fl[:5]]
ok(all(len(x) for x in ws), 'flash: drawn in the first frames')
widths = [x.max() - x.min() for x in ws]
ok(widths[0] < widths[-1], 'flash: it spreads out (%s)' % widths)
# the ring lies on the floor: wider than high, centred
for k, fr in enumerate(frames_of('ring', sheets['ring'])[:4]):
    ys, xs = np.nonzero(alpha(fr) > 0.25)
    ok(len(xs) > 0, 'ring frame %d: drawn' % k)
    ok((xs.max() - xs.min()) > (ys.max() - ys.min()) * 1.35, 'ring frame %d: wider than high (the oblique view)' % k)
    ok(abs((xs.max() + xs.min()) / 2.0 - 32) <= 2, 'ring frame %d: centred' % k)

with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, 'ring.png')
    G.save(path, sheets['ring'])
    ok(np.array_equal(G.load(path), sheets['ring']), 'a picture written and read back is the same')
    eq(G.sheet_name('dust'), 'dust.png', 'file name')

# the committed pictures are what the generator draws (the same as --check)
bad = []
for name in G.SHEETS:
    path = os.path.join(G.OUT, G.sheet_name(name))
    if not os.path.exists(path):
        bad.append(path + ' (missing)')
    elif np.abs(G.load(path).astype(np.int16) - sheets[name].astype(np.int16)).max() > G.TOL:
        bad.append(path + ' (differs)')
eq(bad, [], 'the committed pictures match')

print('gen_lootburst_art: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
