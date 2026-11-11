#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_gem_art_test.py : the pure parts of gen_gem_art.py (cell cut, source checks, twinkle
spots, the nine phases per quality) on synthetic cells, then the committed source sheet and atlas. No pair needed."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_gem_art as G  # noqa: E402
from PIL import Image  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def raises(fn, *a):
    try:
        fn(*a)
    except (AssertionError, SystemExit):
        return True
    return False


def gem(seed=1):
    """a synthetic 32 x 32 cell: an opaque blob of dull colours with two brighter pixels and one tied pair"""
    rng = np.random.RandomState(seed)
    c = np.zeros((32, 32, 4), np.uint8)
    c[6:27, 6:27, :3] = rng.randint(20, 120, (21, 21, 3))
    c[6:27, 6:27, 3] = 255
    c[10, 10, :3] = (250, 250, 240)      # the brightest
    c[22, 22, :3] = (230, 230, 230)      # next, far from the first
    c[10, 12, :3] = (250, 250, 240)      # ties with the first
    c[12, 11, :3] = (240, 240, 240)      # close to the first: never the second spot
    return c


def sheet_of(cells):
    s = np.zeros((32 * len(G.KEYS), 32 * G.TIERS, 4), np.uint8)
    for r in range(len(G.KEYS)):
        for k in range(G.TIERS):
            s[r * 32:(r + 1) * 32, k * 32:(k + 1) * 32] = cells(r, k)
    return s


# ---- cell cut
marked = sheet_of(lambda r, k: np.full((32, 32, 4), (r * 10 + k, 0, 0, 255), np.uint8))
check(all(G.cell(marked, r, k)[0, 0, 0] == r * 10 + k and G.cell(marked, r, k).shape == (32, 32, 4)
          for r in range(len(G.KEYS)) for k in range(G.TIERS)), 'cell(sheet, row, tier) cuts the 32 px cell')

# ---- source checks
good = sheet_of(lambda r, k: gem(r * 5 + k))
G.check_source(good)
check(raises(G.check_source, good[:-32]), 'refuses a sheet of the wrong size')
semi = good.copy()
semi[5, 5, 3] = 128
check(raises(G.check_source, semi), 'refuses semi-transparent alpha')
dirty = good.copy()
dirty[0, 0, :3] = 9
check(raises(G.check_source, dirty), 'refuses colour under alpha 0')
empty = good.copy()
empty[64:96, 32:64] = 0
check(raises(G.check_source, empty), 'refuses an empty cell')

# ---- spots: deterministic, brightest first, 9 px apart, off the border
c = gem()
cand = G.spot_candidates(c, [])
check(cand == [(10, 10), (10, 12)], 'candidates are the tied brightest pixels in reading order: %s' % cand)
check(G.spots(c, 2) == G.spots(c.copy(), 2), 'spots choice is deterministic')
sp = G.spots(c, 2)
check(sp[0] == (10, 10), 'without a pick the first tied pixel in reading order')
check(sp[1] == (22, 22), 'the second spot is the brightest pixel 9 px away, not the near one: %s' % sp)
check(G.spots(c, 2, ((10, 12),))[0] == (10, 12), 'a pick among the ties is taken')
check(G.spots(c, 2, ((10, 12),))[1] == (22, 22), 'the second spot follows the first pick')
check(raises(G.spots, c, 1, ((22, 22),)), 'a pick that is not a brightest pixel is refused')
check(all(abs(a[0] - b[0]) + abs(a[1] - b[1]) >= G.SPOT_APART for i, a in enumerate(sp) for b in sp[:i]), 'spots are apart')
edge = np.zeros((32, 32, 4), np.uint8)
edge[0:G.SPOT_EDGE, :] = (255, 255, 255, 255)
edge[:, 30:] = (255, 255, 255, 255)
edge[15, 15] = (100, 100, 100, 255)
check(G.spots(edge, 1) == [(15, 15)], 'pixels on the border are no spot')
check(G.spots(np.zeros((32, 32, 4), np.uint8), 2) == [], 'an empty cell has no spot')

# ---- phases
base = gem()
for tier in (1, 2, 3):
    fr = G.phases(base, tier)
    check(len(fr) == G.PHASES and all(np.array_equal(f, base) for f in fr), 'quality %d stands still: nine equal frames' % tier)


def diff_px(f):
    return {(int(y), int(x)) for y, x in zip(*np.nonzero((f != base).any(axis=2)))}


def near(pt, px, reach):
    return all(abs(y - pt[0]) + abs(x - pt[1]) <= reach for y, x in px)


fl = G.phases(base, 4, ((10, 10),))
check(len(fl) == G.PHASES, 'Flawless has nine phases')
check(all(np.array_equal(fl[p], base) for p in (0, 6, 7, 8)), 'Flawless is plain in phases 0, 6, 7, 8')
for p, grow in zip(range(1, 6), G.GROW):
    px = diff_px(fl[p])
    check(all(tuple(fl[p][y, x]) == (255, 255, 255, 255) for y, x in px), 'Flawless phase %d changes only to white' % p)
    check(near((10, 10), px, 2), 'Flawless phase %d changes only pixels near the spot' % p)
    check(grow == 0 or px, 'Flawless phase %d shows a twinkle' % p)
check(len({tuple(sorted(diff_px(fl[p]))) for p in range(1, 6)}) == 3 and diff_px(fl[1]) == diff_px(fl[5])
      and diff_px(fl[2]) == diff_px(fl[4]), 'Flawless twinkle grows and shrinks: 0 1 2 1 0')
check(len(diff_px(fl[3])) > len(diff_px(fl[2])) > len(diff_px(fl[1])), 'Flawless peak in phase 3')

pf = G.phases(base, 5, ((10, 10), (22, 22)))
check(np.array_equal(pf[0], base), 'Perfect is plain in phase 0')
first = {p for p in range(1, 6)}
second = {p for p in range(5, 9)}
for p in range(G.PHASES):
    px = diff_px(pf[p])
    a_px = {q for q in px if abs(q[0] - 10) + abs(q[1] - 10) <= 2}
    b_px = {q for q in px if abs(q[0] - 22) + abs(q[1] - 22) <= 2}
    check(a_px | b_px == px, 'Perfect phase %d changes only pixels near one of two spots' % p)
    check(all(tuple(pf[p][y, x]) == (255, 255, 255, 255) for y, x in px), 'Perfect phase %d changes only to white' % p)
    check(bool(a_px) == (p in first), 'Perfect first twinkle in phases 1 to 5 (phase %d)' % p)
    check(bool(b_px) == (p in second), 'Perfect second twinkle in phases 5 to 8 (phase %d)' % p)
check(any(diff_px(pf[5]) & {(y, x) for y in range(8, 13) for x in range(8, 13)})
      and any(diff_px(pf[5]) & {(y, x) for y in range(20, 25) for x in range(20, 25)}), 'Perfect phase 5 shows both twinkles')
check(max(len(diff_px(pf[p]) & {(y, x) for y in range(20, 25) for x in range(20, 25)}) for p in range(G.PHASES))
      < max(len(diff_px(pf[p]) & {(y, x) for y in range(8, 13) for x in range(8, 13)}) for p in range(G.PHASES)),
      'the second twinkle is smaller than the first')
check(all(set(np.unique(f[..., 3]).tolist()) <= {0, 255} for f in fl + pf), 'alpha stays 0 / 255')
check(all(f.shape == (32, 32, 4) and f.dtype == np.uint8 for f in fl + pf), 'frames are 32 x 32 RGBA')

# ---- the committed source, atlas and things file
src = np.asarray(Image.open(G.SOURCE).convert('RGBA'))
G.check_source(src)
atlas = G.build_atlas(src)
check(atlas.shape == (1120, 288, 4), 'atlas is 288 x 1120')
check(np.array_equal(np.asarray(Image.open(G.ATLAS).convert('RGBA')), atlas), 'committed gems.png is the build of gems_src.png')
rows = G.things_rows()
check(len(rows) == 35 and [r['x'] for r in rows] == [0] * 35 and [r['y'] for r in rows] == [32 * i for i in range(35)],
      'things rows: one atlas row each')
check(all(r['phases'] == 9 and r['extra'] == 'ms=110' and r['mode'] == 'replace' for r in rows), '9 phases, 110 ms, mode replace')
check([r['server_id'] for r in rows] == list(range(32001, 32036)), 'server ids 32001 to 32035')
check(all(not np.array_equal(atlas[i * 32:(i + 1) * 32, :32], atlas[i * 32:(i + 1) * 32, 32:64]) for i in range(35) if i % 5 in (3, 4)),
      'every Flawless and Perfect gem animates')
check(all(np.array_equal(atlas[i * 32:(i + 1) * 32, :32], atlas[i * 32:(i + 1) * 32, 32:64]) for i in range(35) if i % 5 < 3),
      'every Chipped, Flawed and Polished gem stands still')
check(sorted(G.PICKS) == sorted((k, t) for k in G.KEYS for t in (4, 5)), 'a pick table entry for each twinkling cell')

print('gem art test: %s' % ('OK' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
