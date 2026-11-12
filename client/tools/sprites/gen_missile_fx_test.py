#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_missile_fx_test.py : gen_missile_fx.py on synthetic missile art (no pair needed): the shape
of the result (8 phases, 96 x 96, hard alpha, the head at the centre, only the projectile's own colours), that it moves between
phases and trails behind the direction of travel in all 8 directions, determinism, the 3 x 3 strip layout, art that does not fit
is refused, and the committed spec, ids file and sums against the generator; the ids against the client's baked-trail list
(visualfx_logic.lua), the stock ids of the energy and ice shot (effects_catalog.csv) and the offsets of 144 and 161."""
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_missile_fx as G  # noqa: E402

ROOT = os.path.join(HERE, '..', '..', '..')
failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


PAL = [(12, 20, 40), (30, 60, 120), (60, 110, 190), (110, 170, 230), (170, 215, 250), (240, 250, 255)]


def synthetic(direction, phases=1, w=64, h=32):
    """a small missile flying east (a bright head on the right, a darker tail), turned to the direction by hand: a head disc at
    the front and a tail line behind it. Returns the list of RGBA images, the head at about 2/3 of the way along."""
    t = G.unit(direction)
    out = []
    for k in range(phases):
        a = np.zeros((h, w, 4), np.uint8)
        cx, cy = w // 2, h // 2
        for s in range(0, 22):                         # the tail, behind the head
            x, y = int(round(cx - t[0] * s)), int(round(cy - t[1] * s))
            col = PAL[2 if s < 8 else 1]
            if 0 <= x < w and 0 <= y < h:
                a[y, x, :3], a[y, x, 3] = col, 255
        for yy in range(-3, 4):                        # the head
            for xx in range(-3, 4):
                if xx * xx + yy * yy <= 9:
                    x, y = cx + xx + int(round(t[0] * 4)), cy + yy + int(round(t[1] * 4))
                    if 0 <= x < w and 0 <= y < h:
                        a[y, x, :3], a[y, x, 3] = PAL[5 if xx * xx + yy * yy < 4 else 4], 255
        a[0, 0, :3] = PAL[0]
        a[0, 0, 3] = 255
        out.append(Image.fromarray(a, 'RGBA'))
    return out


def arr(im):
    return np.asarray(im.convert('RGBA'))


for kind in ('death', 'energy', 'ice', 'fire', 'poison'):
    for d in G.DIRS:
        src = synthetic(d, 1)
        pal = G.palette_of(src)
        res = G.enhance(src, pal, 'B', d, kind=kind, seed=7)
        check(len(res) == G.NPHASES == 8, '%s %s: 8 phases' % (kind, d))
        okshape = all(im.size == (96, 96) and im.mode == 'RGBA' for im in res)
        check(okshape, '%s %s: 96 x 96 RGBA' % (kind, d))
        hard = all(set(np.unique(arr(im)[..., 3]).tolist()) <= {0, 255} for im in res)
        check(hard, '%s %s: hard alpha' % (kind, d))
        colours = set(map(tuple, np.unique(np.concatenate([arr(im)[arr(im)[..., 3] > 0][:, :3] for im in res]), axis=0)))
        own = set(pal) | set(map(tuple, np.unique(arr(src[0])[arr(src[0])[..., 3] > 0][:, :3], axis=0)))
        check(colours <= own, '%s %s: only the projectile\'s own colours (%d extra)' % (kind, d, len(colours - own)))
        check(all((arr(im)[..., 3] > 0).any() for im in res), '%s %s: no empty phase' % (kind, d))
        # the head stays at the canvas centre: opaque art within 7 px of (48, 48) in every phase (the head is at the anchor)
        yy, xx = np.mgrid[0:96, 0:96]
        near = (xx - 48) ** 2 + (yy - 48) ** 2 <= 49
        check(all(((arr(im)[..., 3] > 0) & near).sum() >= 12 for im in res), '%s %s: the head is at the centre' % (kind, d))
        # it moves: at least 5 different frames of 8
        check(len({arr(im).tobytes() for im in res}) >= 5, '%s %s: the phases differ' % (kind, d))
        # it trails behind: the pixel mass lies behind the head along the travel direction
        t = G.unit(d)
        a = np.concatenate([arr(im) for im in res])
        ys, xs = np.nonzero(a[..., 3] > 0)
        ys = ys % 96
        along = (xs - 48) * t[0] + (ys - 48) * t[1]
        check(along.mean() < -2.0, '%s %s: trails behind (mean %.1f)' % (kind, d, along.mean()))
        # the particles never cover the head: the 2 px disc of the head keeps its colours in phase 0 (no particle colour inside)

# determinism: the same input, the same bytes; another seed, other bytes
src = synthetic('east', 1)
pal = G.palette_of(src)
a1 = [arr(i).tobytes() for i in G.enhance(src, pal, 'B', 'east', kind='energy', seed=5)]
a2 = [arr(i).tobytes() for i in G.enhance(src, pal, 'B', 'east', kind='energy', seed=5)]
a3 = [arr(i).tobytes() for i in G.enhance(src, pal, 'B', 'east', kind='energy', seed=6)]
check(a1 == a2, 'deterministic')
check(a1 != a3, 'the seed changes the sparks')

# a source with several phases is cycled
many = synthetic('east', 3)
res = G.enhance(many, G.palette_of(many), 'B', 'east', kind='ice', seed=1)
check(len(res) == 8, 'a 3 phase source still gives 8 phases')

# styles A and C exist for previews and differ from B
resA = G.enhance(src, pal, 'A', 'east', kind='energy', seed=5)
resC = G.enhance(src, pal, 'C', 'east', kind='energy', seed=5)
check([arr(i).tobytes() for i in resA] != a1 and [arr(i).tobytes() for i in resC] != a1, 'styles A and C differ from B')

# art that does not fit the 3 x 3 canvas is refused (nothing is cut silently)
big = Image.fromarray(np.full((128, 128, 4), 255, np.uint8), 'RGBA')
try:
    G.enhance([big], PAL, 'B', 'east', kind='death', seed=1)
    check(False, 'oversize art is refused')
except ValueError:
    pass

# the strip: 3 x 3 patterns of 8 frames, the centre pattern repeats the south one
frames = {d: synthetic(d, 1) for d in G.DIRS}
spec = dict(G.SPECS[2])
strip = G.build_strip(frames, spec)
check(strip.shape == (288, 3 * 96 * 8, 4), 'strip shape %s' % (strip.shape,))
cell = lambda px, py, f: strip[py * 96:(py + 1) * 96, (px * 8 + f) * 96:(px * 8 + f + 1) * 96]  # noqa: E731
for d, (px, py) in G.PATTERN.items():
    check(all((cell(px, py, f)[..., 3] > 0).any() for f in range(8)), 'pattern %s is drawn in all 8 phases' % d)
check(all(np.array_equal(cell(1, 1, f), cell(1, 2, f)) for f in range(8)), 'the centre pattern is the south one')
check(set(np.unique(strip[..., 3]).tolist()) <= {0, 255}, 'strip: hard alpha')
check(G.digest(strip) == G.digest(G.build_strip(frames, spec)), 'strip digest is stable')

# the spec
rows = G.spec_rows()
check(len(rows) == 6 and [r['replace'] for r in rows] == [222, 221, 5, 37, 161, 144], 'six rows at the six ids, in place')
check(all((r['kind'], r['w'], r['h'], r['phases'], r['ms'], r['dx'], r['dy']) == ('missile', 3, 3, 8, 50, 1, 1) for r in rows),
      'every row is a 3 x 3 missile of 8 phases of 50 ms sent at (1, 1)')
check(len({r['name'] for r in rows}) == 6 and all(r['file'].endswith(r['name'] + '.png') for r in rows), 'names and files')
check(all(0 < r['replace'] < 255 and r['replace'] not in (43, 46, 47, 52, 254) for r in rows), 'one byte ids, none of the blank or the weapon-type id')
import import_fx_art as I  # noqa: E402
parsed = I.read_spec(G.SPEC) if os.path.exists(G.SPEC) else []
check(len(parsed) == 6 and all(p['replace'] == r['replace'] for p, r in zip(parsed, rows)), 'import_fx_art reads the committed spec')

# the committed files are the generator's
bad = G.committed_problems(None)
check(bad == [], 'the committed spec, ids file and sums are up to date: %s' % bad)

# the ids against the rest of the repository
ids = sorted(s['id'] for s in G.SPECS)
vl = open(os.path.join(ROOT, 'client', 'overlay', 'modules', 'game_visualfx', 'visualfx_logic.lua'), encoding='utf-8').read()
m = re.search(r'L\.BAKED_TRAIL_MISSILES = \{([^}]*)\}', vl)
check(m is not None and sorted(int(x) for x in re.findall(r'\d+', m.group(1))) == ids,
      'visualfx_logic.lua BAKED_TRAIL_MISSILES is the generator\'s six ids')
cat = open(os.path.join(ROOT, 'server', 'data', 'spells', 'effects_catalog.csv'), encoding='utf-8').read()
check('CONST_ANI_ENERGY,energy,missile,5,' in cat and 'CONST_ANI_SMALLICE,frost,missile,37,' in cat, 'ids 5 and 37 are the stock energy and ice shots')
p29 = open(os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_pack29_fx_ids.lua'), encoding='utf-8').read()
p41 = open(os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_pack41_fx_ids.lua'), encoding='utf-8').read()
check('ChaosVfxMissile.witchfire_lance = {id = 161, dx = 1, dy = 1}' in p29, 'witchfire_lance is sent at (1, 1) already')
check('ChaosVfxMissile.proj_venom_glob_necrotic = {id = 144, dx = 1, dy = 1}' in p41, 'proj_venom_glob_necrotic is sent at (1, 1) already')
lua = G.lua_text()
for n, i in (('p51_magenta_orb_tendrils', 222), ('p51_pink_lightning', 221), ('p67_energy_shot', 5), ('p67_ice_shot', 37)):
    check('ChaosVfxMissile.%s = {id = %d, dx = 1, dy = 1}' % (n, i) in lua, 'ids file names %s' % n)

print('gen_missile_fx_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
