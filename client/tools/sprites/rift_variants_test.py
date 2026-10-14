#!/usr/bin/env python3
"""Unit tests of rift_variants.py (the post-processing of the rift monster variants). python3 -I rift_variants_test.py"""
import csv, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import rift_variants as RV

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def blob(W=64, box=(20, 30, 50, 60), rgb=(120, 60, 40)):
    a = np.zeros((W, W, 4), np.uint8)
    x0, y0, x1, y1 = box
    a[y0:y1, x0:x1, :3] = rgb
    a[y0:y1, x0:x1, 3] = 255
    return a


# alpha: 0 / 255 only, specks dropped, transparent pixels carry no colour
a = blob()
a[5, 5] = (255, 0, 0, 200)          # a lone speck
a[30:32, 18:20] = (10, 10, 10, 100)  # soft fringe below 128
c = RV.cut_alpha(a, 4)
ok(set(np.unique(c[..., 3]).tolist()) == {0, 255}, 'alpha 0 / 255')
ok(c[5, 5, 3] == 0, 'a one-pixel speck is dropped')
ok(c[30, 18, 3] == 0 and not c[30, 18, :3].any(), 'alpha under 128 cut and its colour cleared')
ok(c[40, 30, 3] == 255, 'the body stays')

# shift
s = RV.shift(blob(), 2, -1)
ok(s[29, 22, 3] == 255 and s[29, 21, 3] == 0 and s[58, 22, 3] == 255 and s[59, 22, 3] == 0, 'shift moves right 2, up 1')

# alignment: registered frames stay put; a real misregistration is undone; a soft halo of the base is ignored
base = blob()
ok(RV.best_shift([(blob(), base)] * 3) == (0, 0), 'registered: no shift')
moved = RV.shift(blob(), -2, -3)
ok(RV.best_shift([(moved, base)] * 3) == (2, 3), 'misregistered by (-2, -3): shifted back')
halo = base.copy()
halo[26:30, 16:54, 3] = 60   # a glow above the body (semi-transparent)
halo[26:30, 16:54, :3] = 200
ok(RV.best_shift([(blob(), halo)] * 3) == (0, 0), 'a soft halo does not pull the variant')
ok(RV.feet(blob()) == 59 and RV.feet(halo, 250) == 59, 'feet: the lowest opaque row')

# grade
g = RV.grade(blob(rgb=(200, 100, 50)), 0.5, 1.0)
ok(tuple(g[40, 30, :3]) == (100, 50, 25), 'grade halves the value')
ok(RV.grade(blob(), 1.0, 1.0) is not None, 'grade 1 / 1 is a no-op')

# palette: n colours, an accent of few pixels kept, sorted dark to light; snap uses only palette colours
rng = np.random.RandomState(3)
f = blob(rgb=(90, 90, 90))
f[30:60, 20:50, :3] = rng.randint(40, 140, (30, 30, 1)).repeat(3, -1)   # 101 greys
f[40, 30, :3] = (40, 230, 240)                                           # two cyan eye pixels
f[40, 32, :3] = (40, 230, 240)
plain = RV.palette_of([f], 8, 0)
acc = RV.palette_of([f], 8, 2)
near = lambda pal, c: int(((pal.astype(int) - np.array(c)) ** 2).sum(1).min())
ok(len(plain) <= 8 and len(acc) <= 8, 'at most n colours')
ok(near(plain, (40, 230, 240)) > 3000, 'a plain median cut loses the two eye pixels')
ok(near(acc, (40, 230, 240)) < 100, 'the accent colour keeps them')
lum = (acc.astype(int) * [299, 587, 114]).sum(1)
ok(list(lum) == sorted(lum), 'palette sorted dark to light')
sn = RV.snap(f, acc)
cols = {tuple(x) for x in sn[sn[..., 3] > 0][:, :3].tolist()}
ok(cols <= {tuple(x) for x in acc.tolist()}, 'snap: palette colours only')
ok(not sn[sn[..., 3] == 0][:, :3].any(), 'snap leaves transparent pixels alone')

# outline: bright edge pixels darkened, inside untouched, then snapped to the palette
bright = blob(rgb=(220, 220, 220))
pal = np.array([[20, 20, 20], [100, 100, 100], [220, 220, 220]], np.uint8)
o = RV.outline(bright, pal, 80)
ok(tuple(o[30, 20, :3]) == (100, 100, 100), 'a bright edge pixel is darkened (220 x 0.45 = 99 -> 100)')
ok(tuple(o[40, 30, :3]) == (220, 220, 220), 'inside pixels keep their colour')
ok(RV.outline(bright, pal, None) is bright, 'outline off')

# the things row of a layout (import_art_things.py's outfit layout)
lay = {'flags': {'animateAlways': True}, 'groups': [
    {'type': 0, 'w': 2, 'h': 2, 'exact': 64, 'phases': 1, 'anim': None},
    {'type': 1, 'w': 2, 'h': 2, 'exact': 64, 'phases': 2, 'anim': [0, 0, -1, [300, 310, 300, 310]]}]}
r = RV.things_row({'key': 'k', 'name': 'N'}, lay)
ok(r['phases'] == '1+2' and r['w'] == 2 and r['patterns'] == 4 and r['flags'] == 'animateAlways', 'row: layout')
ok(r['extra'] == 'layers=1|gtypes=0+1|exact=64+64|durs1=300:310/300:310|anim1=0:0:-1', 'row: ' + r['extra'])
fr = {(g, d, p): np.full((64, 64, 4), 10 * g + d + 100 * p, np.uint8) for g, n in ((0, 1), (1, 2)) for d in range(4)
      for p in range(n)}
sh = RV.sheet(lay, fr)
ok(sh.shape == (3 * 64, 4 * 64, 4), 'sheet: a row per group phase, a column per direction')
ok(sh[64 * 2 + 5, 64 * 3 + 5, 0] == 10 + 3 + 100, 'sheet: walk phase 1, west, in row 3, column 4')

# the committed spec, sheets and rows agree (no pair or raw results needed)
ok(RV.cmd_check(type('A', (), {'spec': RV.SPEC})()) == 0, 'rift_variants.py check passes')
spec = RV.load_spec()
with open(RV.OUT_CSV, newline='') as fh:
    rows = list(csv.DictReader(fh))
ok([x['key'] for x in rows] == [v['key'] for v in sorted(spec['variants'], key=lambda v: v['look'])],
   'things rows in look order')
ok(all(v['look'] >= spec['first_outfit'] for v in spec['variants']), 'looks from first_outfit on')

print('rift_variants tests:', 'ok' if not fails else f'{fails} failed')
sys.exit(1 if fails else 0)
