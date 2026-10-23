#!/usr/bin/env python3
"""Tests of gen_creature_palette.py on synthetic sprites (drawn here; no pair, no pack art).

    python3 -I client/tools/sprites/gen_creature_palette_test.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import gen_creature_palette as G

FAILS = []


def ok(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def creature(seed=1, size=64):
    """a noisy blob: dark outline, a shaded body of many close colours, two glowing eyes, soft glow pixels"""
    rng = np.random.default_rng(seed)
    a = np.zeros((size, size, 4), np.uint8)
    yy, xx = np.mgrid[:size, :size]
    inside = (yy - 40) ** 2 + (xx - 36) ** 2 < 18 ** 2
    p = np.pad(inside, 1)
    rim = inside & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
    shade = 70 + (60 - yy) * 1.2 + rng.normal(0, 9, inside.shape)          # lit from the top, noisy
    body = np.stack([shade * 0.9, shade * 0.55, shade * 0.4], -1)
    a[inside, :3] = np.clip(body[inside], 0, 255).astype(np.uint8)
    a[inside, 3] = 255
    a[rim, :3] = [6, 2, 3]
    a[rim & (xx > 36), :3] = [4, 2, 2]
    for x in (30, 40):                                                     # two eyes, 2 x 1 px each
        a[34, x:x + 2, :3] = [250, 230, 40]
    halo = ~inside & ((yy - 40) ** 2 + (xx - 36) ** 2 < 21 ** 2) & (yy < 30)
    a[halo, :3] = [200, 90, 30]; a[halo, 3] = 90                           # a soft glow over the head
    return a


def frames_of(n=4):
    return {(0, ph, 0, 0, d, 0): creature(seed=10 * ph + d) for ph in range(n) for d in range(2)}


def colours(fr):
    return {int(c) for f in fr.values() for c in G.pack(f[f[..., 3] > 0][:, :3])}


# ------------------------------------------------------------------------------------------------------- the pass
fr = frames_of()
roles = {k: (0, None) for k in fr}
out, st = G.pass_look(fr, roles, 32)
out2, _ = G.pass_look(frames_of(), roles, 32)
ok(all(np.array_equal(out[k], out2[k]) for k in out), 'deterministic: the same frames give the same pass')
before, after = colours(fr), colours(out)
ok(len(before) > 100, 'the synthetic creature is noisy (%d colours)' % len(before))
ok(len(after) <= 32, 'one palette of at most 32 colours for all frames (%d)' % len(after))
ok(after <= before, 'every palette colour is a real colour of the look')
ok(all(np.array_equal(out[k][..., 3], fr[k][..., 3]) for k in fr), 'alpha unchanged (soft glow included)')
ok(all(((out[k][..., 3] == 0) <= (out[k][..., :3] == 0).all(-1)).all() for k in out), 'transparent pixels stay 0')
eye = G.pack(np.array([250, 230, 40]))
ok(all(int(G.pack(out[k][34, 30, :3])) == eye and int(G.pack(out[k][34, 41, :3])) == eye for k in out),
   'the glowing eyes keep their exact colour (accent entry)')
lb0 = G.luma(np.concatenate([f[f[..., 3] > 0][:, :3] for f in fr.values()])) < G.DARK
lb1 = G.luma(np.concatenate([f[f[..., 3] > 0][:, :3] for f in out.values()])) < G.DARK
ok((lb0 == lb1).all(), 'near-black stays near-black and nothing else becomes it (outline kept)')
for k in fr:
    vis = fr[k][..., 3] > 0
    rim = G.rim_of(vis)
    ok(((G.luma(out[k][..., :3]) < G.DARK) == (G.luma(fr[k][..., :3]) < G.DARK))[rim].all(), 'rim darkness %s' % (k,))
ok(st['lone1'] / st['body1'] < st['lone0'] / st['body0'], 'speckle lower (%.2f -> %.2f)'
   % (st['lone0'] / st['body0'], st['lone1'] / st['body1']))
ok(G.judge(st) == '', 'the synthetic creature passes the judge: %r' % G.judge(st))

# a look of 32 colours or fewer keeps its palette
small = {k: f.copy() for k, f in frames_of(2).items()}
for f in small.values():
    v = f[..., 3] > 0
    f[v, :3] = (f[v, :3] // 64) * 64 + 10
o, s = G.pass_look(small, {k: (0, None) for k in small}, 32)
ok(colours(o) <= colours(small) and s['info'].get('identity'), 'a small palette is kept (despeckle only)')

# ---------------------------------------------------------------------------------------------------- despeckle
img = np.zeros((7, 7, 4), np.uint8)
img[..., 3] = 255
img[..., :3] = [100, 60, 40]
img[3, 3, :3] = [110, 70, 50]           # a lone pixel close in luma: cleaned
img[1, 5, :3] = [240, 240, 240]         # a lone pixel far in luma: kept
img[5, 1, :3] = [112, 72, 52]           # a lone accent pixel: kept
d = G.despeckle(img, keep_codes={int(G.pack(np.array([112, 72, 52])))})
ok(tuple(d[3, 3, :3]) == (100, 60, 40), 'a lone pixel takes the common neighbour colour')
ok(tuple(d[1, 5, :3]) == (240, 240, 240), 'a lone pixel far in luma is kept')
ok(tuple(d[5, 1, :3]) == (112, 72, 52), 'an accent pixel is never despeckled')
ok(tuple(d[0, 0, :3]) == (100, 60, 40) and np.array_equal(d[..., 3], img[..., 3]), 'alpha and the rest unchanged')
dk = img.copy(); dk[..., :3] = [20, 20, 20]; dk[3, 3, :3] = [40, 40, 40]
ok(tuple(G.despeckle(dk)[3, 3, :3]) == (40, 40, 40), 'despeckle never crosses the near-black line')
rimimg = img.copy(); rimimg[0, 3, :3] = [104, 64, 44]
ok(tuple(G.despeckle(rimimg)[0, 3, :3]) == (104, 64, 44), 'a rim pixel is not despeckled')

# ---------------------------------------------------------------------------------------------------- colour mask
mfr = {}
for k, f in frames_of(2).items():
    mfr[k] = f
    m = np.zeros_like(f)
    m[40:50, 30:44, :3] = [255, 0, 0]; m[40:50, 30:44, 3] = 255          # body: red template
    m[50:54, 30:44, :3] = [0, 0, 255]; m[50:54, 30:44, 3] = 255          # feet: blue
    mfr[k[:5] + (1,)] = m
ok(G.is_mask_layer([v for k, v in mfr.items() if k[5] == 1]), 'a pure template layer is a mask')
ok(not G.is_mask_layer([v for k, v in mfr.items() if k[5] == 0]), 'an art layer is not a mask')


class Grp:
    layers = 2


roles = G.layer_roles(mfr, [Grp()], aura=False)
mo, _ = G.pass_look(mfr, roles, 32)
ok(all(np.array_equal(mo[k], mfr[k]) for k in mfr if k[5] == 1), 'the mask layer is kept exactly')
ok(all(np.array_equal(mo[k][40:54, 30:44], mfr[k][40:54, 30:44]) for k in mfr if k[5] == 0),
   'base pixels under the mask stay as they were (in-game colouring)')
ok(any(not np.array_equal(mo[k], mfr[k]) for k in mfr if k[5] == 0), 'the rest of the base layer is passed')
ok(all(r == (k[5], None) for k, r in G.layer_roles(mfr, [Grp()], aura=True).items()), 'an aura has no mask layer')

# -------------------------------------------------------------------------------------------------------- judge
base = {'body0': 100, 'lone0': 50, 'body1': 100, 'lone1': 10, 'vivid0': 100, 'vivid_far': 0, 'vivid_de': 2.0,
        'spots0': 100, 'spots_moved': 0}
ok(G.judge(base) == '', 'judge: a clean pass')
ok(G.judge(dict(base, spots_moved=11)).startswith('small accents lost'), 'judge: lost spot pixels keep the look')
ok(G.judge(dict(base, vivid_far=11)).startswith('accents lost'), 'judge: moved vivid pixels keep the look')
ok(G.judge(dict(base, vivid_de=10.5)).startswith('accents moved'), 'judge: a large mean move keeps the look')
ok(G.judge(dict(base, lone1=60)) == 'speckle not lower', 'judge: no gain, no change')

# ------------------------------------------------------------------------------------------------ kmeans, spots
x = np.array([[0, 0, 0], [1, 0, 0], [50, 0, 0], [51, 0, 0]], float)
lbl = G.kmeans(x, np.ones(4), 2)
ok(lbl[0] == lbl[1] and lbl[2] == lbl[3] and lbl[0] != lbl[2], 'k-means splits two clear clusters')
ok(G.medoid(x[:3], np.array([1.0, 1.0, 5.0])) == 2, 'the medoid follows the weights')
ok(G.split_budget([90, 10], [50, 50], 10) == [9, 1], 'budget split by pixels: %r' % G.split_budget([90, 10], [50, 50], 10))
ok(G.split_budget([90, 10], [3, 50], 10) == [3, 7], 'budget split capped by the colours of a group')
v = np.zeros((12, 12), bool); v[2, 2] = True; v[6:12, 6:12] = True
sp = G.spots(v)
ok(sp[2, 2] and not sp[8, 8], 'a lone vivid pixel is a spot, a big vivid area is not')

# ------------------------------------------------------------------------------------------- the committed report
ok(G.check_report_rows(G.read_report()) == [], 'the committed report lists the targets: %r' % G.check_report_rows(G.read_report()))
bad = G.read_report()
bad[0] = dict(bad[0], status='changed', sha256='')
ok(G.check_report_rows(bad) != [], 'a changed row without its hash is refused')

print('%d failures' % len(FAILS) if FAILS else 'gen_creature_palette_test: all passed')
sys.exit(1 if FAILS else 0)
