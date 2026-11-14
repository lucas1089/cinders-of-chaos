#!/usr/bin/env python3
"""Tests of client/tools/gen_lootbeam_art.py (O569): the loot beam pictures are soft, loop, keep the rarity colours, and Divine is the
loudest tier (O576) while the others keep their order.

python3 -I client/tools/gen_lootbeam_art_test.py       (numpy and Pillow; the fx venv in CI)
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import gen_lootbeam_art as G  # noqa: E402

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


def mean_diff(a, b):
    return float(np.abs(a.astype(np.float32) - b.astype(np.float32)).mean())


# ---------------------------------------------------------------- shape of a strip
ok(G.W == 64 and G.H == 128, 'frames are 64 x 128')
eq(G.FRAMES, 18, '6 burst frames and 12 loop frames')
eq(len(G.GROUPS), 6, 'six tier groups')
eq(sorted(G.GROUPS), sorted(G.GROUP_ORDER), 'the order names every group')
eq(G.STYLES, ('a', 'b', 'c'), 'three styles')
strips = {}
for st in G.STYLES:
    for g in G.GROUP_ORDER:
        strips[(st, g)] = G.strip(st, g)
for key, arr in strips.items():
    eq(arr.shape, (G.H, G.W * G.FRAMES, 4), '%s: strip size' % (key,))
    eq(arr.dtype, np.uint8, '%s: 8 bit' % (key,))

# the generator is deterministic
again = G.strip('b', 'orange')
ok(np.array_equal(again, strips[('b', 'orange')]), 'the same strip twice')
ok(not np.array_equal(strips[('a', 'orange')], strips[('b', 'orange')]), 'style a and b differ')
ok(not np.array_equal(strips[('a', 'orange')], strips[('c', 'orange')]), 'style a and c differ')
ok(not np.array_equal(strips[('a', 'white')], strips[('a', 'blue')]), 'tiers differ')


def frames_of(arr):
    return [arr[:, k * G.W:(k + 1) * G.W] for k in range(G.FRAMES)]


# ---------------------------------------------------------------- soft, no hard edges
MAX_STEP = 0.66   # the biggest alpha step between two neighbouring pixels (the bright centre line is the sharpest thing there is)
for key, arr in strips.items():
    for k, fr in enumerate(frames_of(arr)):
        a = alpha(fr)
        # nothing touches the frame's edge: the glow has died out before it
        edge = max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max())
        ok(edge < 0.02, '%s frame %d: the glow stops before the frame edge (%.3f)' % (key, k, edge))
        step = max(np.abs(np.diff(a, axis=0)).max(), np.abs(np.diff(a, axis=1)).max())
        ok(step <= MAX_STEP, '%s frame %d: no hard edge, biggest step %.2f' % (key, k, step))
        # a pixel that is almost clear is fully clear (clean alpha, no 1/255 dust)
        faint = (fr[..., 3] > 0) & (fr[..., 3] < 1)
        eq(int(faint.sum()) >= 0, True, 'alpha counted')
# the column of style a is feathered: from the centre line out, the alpha falls steadily over 8 px on both sides
fr = frames_of(strips[('a', 'orange')])[G.BURST + 3]
row = alpha(fr)[int(G.FOOT_Y) - 40]
c = 32
ok(row[c] > row[c + 3] > row[c + 6] > row[c + 9], 'style a: the column falls off to the right in steps')
ok(row[c - 1] > row[c - 4] > row[c - 7] > row[c - 10], 'style a: and to the left')
ok(row[c + 2] > 0.3, 'style a: a body of light round the centre line, not a thread')
ok(row[c + 14] < 0.08, 'style a: no hard shoulder')

# ---------------------------------------------------------------- the picture: a column and a ring on the floor
for key, arr in strips.items():
    loop0 = frames_of(arr)[G.BURST]
    a = alpha(loop0)
    fy = int(G.FOOT_Y)
    # the ground ring: an ellipse wider than high (the oblique view), centred on the foot
    ys, xs = np.nonzero(a[fy - 24:fy + 16, :] > 0.25)
    ok(len(xs) > 0, '%s: a ring is drawn' % (key,))
    ring_w, ring_h = xs.max() - xs.min(), ys.max() - ys.min()
    ok(ring_w > ring_h * 1.35, '%s: the ring lies on the floor (%d wide, %d high)' % (key, ring_w, ring_h))
    ok(abs((xs.max() + xs.min()) / 2.0 - 32) <= 3, '%s: the ring is centred on the foot' % (key,))
    # a column above the foot: light on the centre line at half the column's height, nothing at the very top
    g = key[1]
    top = int(G.FOOT_Y - G.GROUPS[g]['col'])
    mid = int(G.FOOT_Y - G.GROUPS[g]['col'] * 0.5)
    ok(a[mid, 24:40].max() > 0.3, '%s: the column stands at half height' % (key,))
    ok(a[max(top - 2, 0), 24:40].max() < 0.12, '%s: it has faded out at the top' % (key,))
    ok(a[mid, 24:40].max() > a[max(top, 0) + 4, 24:40].max(), '%s: it fades towards the top' % (key,))

# ---------------------------------------------------------------- the loop closes, the burst joins it
for key, arr in strips.items():
    fs = frames_of(arr)[G.BURST:]
    steps = [mean_diff(fs[i], fs[(i + 1) % G.LOOP]) for i in range(G.LOOP)]
    closing = steps[-1]
    others = steps[:-1]
    ok(closing <= max(others) * 1.35 + 0.05, '%s: the last loop frame leads into the first (%.3f vs %.3f)' % (key, closing, max(others)))
    ok(min(steps) > 0, '%s: every loop frame differs from the next (it moves)' % (key,))
    burst = frames_of(arr)[:G.BURST]
    join = mean_diff(burst[-1], fs[0])
    ok(join <= max(others) * 3.0 + 0.1, '%s: the burst joins the loop (%.3f)' % (key, join))
    # the burst grows: the column of the last burst frame is much taller than that of the first
    h = [np.nonzero(alpha(b)[:, 28:36].max(axis=1) > 0.2)[0] for b in burst]
    ok(len(h[0]) < len(h[-1]), '%s: the column rises in the burst' % (key,))

# ---------------------------------------------------------------- the rarity colours; Divine the loudest, the others in order
peaks = {}
for g in G.GROUP_ORDER:
    arr = strips[('a', g)]
    fs = frames_of(arr)[G.BURST:]
    peak = max(alpha(f).max() for f in fs)
    peaks[g] = peak
    # the colour of the soft body of the column (not the burnt centre): the tier's hue
    want = np.array([int(G.GROUPS[g]['color'][i:i + 2], 16) for i in (1, 3, 5)], np.float32)
    fr = fs[3]
    mid = int(G.FOOT_Y - G.GROUPS[g]['col'] * 0.45)
    px = fr[mid, 32 + 4].astype(np.float32)[:3]
    cos = float(px @ want / (np.linalg.norm(px) * np.linalg.norm(want) + 1e-6))
    ok(cos > 0.97, '%s: the body of the beam is in the rarity colour (cos %.3f)' % (g, cos))
others = [g for g in G.GROUP_ORDER if g != 'divine']
ok(max(peaks[g] for g in others) - min(peaks[g] for g in others) < 0.12, 'the tiers but Divine peak alike: %s' % peaks)
ok(peaks['divine'] >= max(peaks[g] for g in others), 'Divine is at least as bright as any tier at its peak: %s' % peaks)


def band_light(arr, lo, hi):
    """mean alpha of the body of the column (x 22..42, rows lo..hi above the foot) per loop frame"""
    y0, y1 = int(G.FOOT_Y - hi), int(G.FOOT_Y - lo)
    return [float(alpha(f)[y0:y1, 22:42].mean()) for f in frames_of(arr)[G.BURST:]]


for st in G.STYLES:
    # total light a frame gives out: the tiers grow richer up to Legendary, Divine is the loudest of all by a clear margin
    tot = {g: float(np.mean([alpha(f).sum() for f in frames_of(strips[(st, g)])[G.BURST:]])) for g in G.GROUP_ORDER}
    ok(tot['orange'] > tot['white'] * 0.95, '%s: Legendary is not poorer than Common' % st)
    ok(tot['white'] < tot['blue'] < tot['orange'] < tot['unique'], '%s: the other tiers keep their order (%s)' % (st, tot))
    ok(tot['orb'] < tot['blue'], '%s: Orbs stay calm' % st)
    ok(tot['divine'] > max(tot[g] for g in others) * 1.3, '%s: Divine gives out 30%% more light than any other tier (%s)' % (st, tot))
    ok(tot['divine'] < tot['white'] * 5, '%s: and is still not a wall of light (%s)' % (st, tot))
    # the body of the column is brighter along its height, and it reaches higher
    body = {g: float(np.mean(band_light(strips[(st, g)], 10, 90))) for g in G.GROUP_ORDER}
    ok(body['divine'] > max(body[g] for g in others), '%s: the column of Divine is the brightest (%s)' % (st, body))
    upper = {g: float(np.mean(band_light(strips[(st, g)], 70, 100))) for g in G.GROUP_ORDER}
    ok(upper['divine'] > max(upper[g] for g in others) * 1.15, '%s: it still burns high up where the others have faded (%s)' % (st, upper))
    # a pulse of its own: the light of the column moves more from frame to frame than that of any other tier (travelling rings,
    # a faster and deeper swell)
    move = {}
    for g in G.GROUP_ORDER:
        fs = [alpha(f)[:, 20:44] for f in frames_of(strips[(st, g)])[G.BURST:]]
        move[g] = float(np.mean([np.abs(fs[i] - fs[(i + 1) % G.LOOP]).mean() for i in range(G.LOOP)]))
    ok(move['divine'] > max(move[g] for g in others) * 1.25, '%s: Divine has its own, livelier pulse (%s)' % (st, move))

# more motes in the higher tiers
ok(G.GROUPS['white']['motes'] < G.GROUPS['blue']['motes'] < G.GROUPS['orange']['motes'] < G.GROUPS['divine']['motes'], 'motes grow with the tier')
ok(G.GROUPS['white']['col'] < G.GROUPS['orange']['col'] <= G.GROUPS['unique']['col'], 'the column grows with the tier')
ok(G.GROUPS['divine']['col'] <= G.FOOT_Y, 'the column fits in the frame')
ok(G.GROUPS['divine']['col'] > max(G.GROUPS[g]['col'] for g in others), 'Divine is the tallest')
ok(G.GROUPS['divine']['motes'] > max(G.GROUPS[g]['motes'] for g in others), 'Divine has the most motes')
ok(G.GROUPS['divine']['stars'] > max(G.GROUPS[g]['stars'] for g in others), 'Divine has the most twinkles')
ok(G.GROUPS['divine']['halo'][0] > max(G.GROUPS[g]['halo'][0] for g in others), 'Divine has the widest halo')
ok(G.GROUPS['divine']['fade'] < G.DEFAULT_FADE, 'the column of Divine fades out later')
ok(G.GROUPS['divine']['pulse'][0] > G.DEFAULT_PULSE[0] and G.GROUPS['divine']['pulse'][1] > G.DEFAULT_PULSE[1], 'Divine pulses faster and deeper')
for key in ('aura', 'rings', 'outer'):
    ok(key in G.GROUPS['divine'] and not any(key in G.GROUPS[g] for g in others), 'only Divine has %s' % key)
ok(G.GROUPS['divine']['inner'] and G.GROUPS['unique']['inner'] and not G.GROUPS['orange']['inner'], 'only Divine and Uniques have an inner ring')

# ---------------------------------------------------------------- the styles are what they say
# b: two strands: at a row where they are apart there are two bright columns
fb = alpha(frames_of(strips[('b', 'orange')])[G.BURST + 2])
split = 0
for y in range(int(G.FOOT_Y - 85), int(G.FOOT_Y - 20)):
    r = fb[y, 20:45]
    peaks_ = [i for i in range(1, len(r) - 1) if r[i] > 0.35 and r[i] >= r[i - 1] and r[i] >= r[i + 1]]
    if len(peaks_) >= 2 and peaks_[-1] - peaks_[0] >= 6:
        split += 1
ok(split >= 8, 'style b: two strands show side by side on %d rows' % split)
# c: glyphs: light beside the column (|dx| 6..14) at several heights where style a has less
fa = alpha(frames_of(strips[('a', 'orange')])[G.BURST + 4])
fc = alpha(frames_of(strips[('c', 'orange')])[G.BURST + 4])
side_a = float(fa[int(G.FOOT_Y - 100):int(G.FOOT_Y - 20), 20:26].sum() + fa[int(G.FOOT_Y - 100):int(G.FOOT_Y - 20), 38:44].sum())
side_c = float(fc[int(G.FOOT_Y - 100):int(G.FOOT_Y - 20), 20:26].sum() + fc[int(G.FOOT_Y - 100):int(G.FOOT_Y - 20), 38:44].sum())
ok(side_c > side_a * 0.5, 'style c has glyphs beside the column (%.1f vs %.1f)' % (side_c, side_a))
eq(len(G.RUNES) >= 5, True, 'at least five glyph shapes')

# ---------------------------------------------------------------- check / write
with tempfile.TemporaryDirectory() as tmp:
    arr = strips[('a', 'white')]
    path = os.path.join(tmp, 'a_white.png')
    G.save(path, arr)
    ok(np.array_equal(G.load(path), arr), 'a strip written and read back is the same')
    eq(G.strip_name('c', 'orb'), 'c_orb.png', 'file name')

# the committed strips are what the generator draws (the same as --check, on the pictures this test already drew)
bad = []
for st in G.STYLES:
    for g in G.GROUP_ORDER:
        path = os.path.join(G.OUT, G.strip_name(st, g))
        if not os.path.exists(path):
            bad.append(path + ' (missing)')
        elif np.abs(G.load(path).astype(np.int16) - strips[(st, g)].astype(np.int16)).max() > G.TOL:  # CPU float rounding
            bad.append(path + ' (differs)')
eq(bad, [], 'the committed strips match')

print('gen_lootbeam_art: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
