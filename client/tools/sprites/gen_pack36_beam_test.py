#!/usr/bin/env python3
"""Tests for the loot beams of gen_pack36_fx.py at full size (O522, pair 65), on synthetic strips (no purchased art):
the ring centre, the 3 x 5 group with its 1 x 1 send offset, no scaling, the ring landing where the halved beam's ring
was (within 1 px), the dissolve and the empty last phase, a frame that does not fit, and the committed beam spec.
Needs numpy and Pillow like the build (CI uses the fx venv). python3 -I gen_pack36_beam_test.py"""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_pack36_fx as P  # noqa: E402

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        print('FAIL', what)
        fails += 1


def synthetic(cx=32, cy=116, rx=18, ry=5, seed=1):
    """24 frames of 64 x 128: a 10 px wide pillar, a ground ring (ellipse outline filled) at (cx, cy), sparks that move"""
    rng = np.random.RandomState(seed)
    frames = []
    yy, xx = np.mgrid[0:128, 0:64]
    for i in range(24):
        f = np.zeros((128, 64, 4), np.uint8)
        ring = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1.0
        pillar = (abs(xx - cx) <= 5) & (yy > 12) & (yy < cy)
        f[ring | pillar] = (90, 200, 255, 255)
        sx, sy = int(rng.randint(8, 56)), int(rng.randint(20, 90))      # a spark that is somewhere else in every frame
        f[sy:sy + 2, sx:sx + 2] = (255, 255, 255, 255)
        frames.append(f)
    return frames


def halved_strip(frames):
    """the rule before O522 (load() 'beam' + effect_strip): halved to 32 x 64, the bottom tile on the item's tile"""
    half = [P.halve(f) for f in frames]
    h = half[0].shape[0]
    return P.effect_strip('old', half, (0, h - 32), (0, 0), True)


def cut(strip, w, h, n):
    W = w * 32
    return [strip[:, i * W:(i + 1) * W] for i in range(n)]


src = synthetic()
cx, cy = P.ring_centre(src)
ok(abs(cx - 32) <= 0.5 and abs(cy - 116) <= 1.5, f'ring centre of the synthetic art {cx}, {cy}')
ok(P.ring_centre([f.copy() for f in src], 16) == (cx, cy), 'the window of an eighth is 16 rows of 128')

strip, w, h, n, dx, dy = P.beam_strip('synthetic', src)
ok((w, h, n, dx, dy) == (3, 5, 25, 1, 1), f'group {w}x{h}, {n} phases, offset {dx},{dy}')
ok(strip.shape == (160, 96 * 25, 4), f'strip shape {strip.shape}')
fr = cut(strip, w, h, n)
ok(not fr[24][:, :, 3].any(), 'the 25th phase is empty')
# no scaling: the first 21 frames carry every pixel of the source, unchanged (compare the art boxes)
for i in (0, 10, 20):
    a, b = src[i], fr[i]
    ys, xs = np.nonzero(a[:, :, 3])
    ys2, xs2 = np.nonzero(b[:, :, 3])
    ok(len(ys) == len(ys2), f'frame {i} pixel count')
    sy, sx = ys2.min() - ys.min(), xs2.min() - xs.min()
    ok(np.array_equal(b[sy:sy + 128, sx:sx + 64], a), f'frame {i} is the source frame, unscaled, shifted whole')
# the dissolve of the last three frames: fewer and fewer pixels
cnt = [int((f[:, :, 3] > 0).sum()) for f in fr[:24]]
ok(cnt[20] == int((src[20][:, :, 3] > 0).sum()), 'frame 20 is whole')
ok(cnt[21] > cnt[22] > cnt[23] > 0 and cnt[21] < cnt[20], f'frames 21 to 23 dissolve {cnt[21:24]}')
# the ring lands at BEAM_RING of the item tile (column 1, row 3 of the group)
col, row = P.BEAM_W - 1 - P.BEAM_DX, P.BEAM_H - 1 - P.BEAM_DY
ok((col, row) == (1, 3), 'the item tile is column 1, row 3')
rx_, ry_ = P.ring_centre(fr[:24], 16)
tile = (rx_ - col * 32, ry_ - row * 32)
ok(abs(tile[0] - P.BEAM_RING[0]) <= 0.5 and abs(tile[1] - P.BEAM_RING[1]) <= 0.5, f'ring centre on the item tile {tile}')
# and where the halved beam's ring was: within 1 px (the proof of the pair 65 build, on the real pair: client/MANIFEST.md)
old, ow, oh, on, odx, ody = halved_strip(src)
ok((ow, oh, odx, ody) == (1, 2, 0, 0), 'the old beam is 1 x 2')
ofr = cut(old, ow, oh, on)
ox, oy = P.ring_centre(ofr[:24], 8)
oldtile = (ox - 0 * 32, oy - 1 * 32)                    # item tile = column 0, row 1 of the 1 x 2 group
ok(abs(oldtile[0] - tile[0]) <= 1 and abs(oldtile[1] - tile[1]) <= 1, f'ring: old {oldtile}, new {tile}')

# a ring whose art would leave the group (shifted by the rule past its left edge) is refused, not clipped
wide = synthetic(cx=2, rx=2)
try:
    P.beam_strip('wide', wide)
    ok(False, 'art that does not fit the group is refused')
except AssertionError:
    ok(True, 'art that does not fit the group is refused')

# every ring position of the real strips has art right of the item tile and below it: the group has the room
wide_art = synthetic(cx=50, rx=14, ry=7, cy=121)
s2, *_ = P.beam_strip('wide2', wide_art)
ok(s2.shape == (160, 96 * 25, 4), 'a wide ring (3 px past the tile right, 4 below) fits the group')

# the committed spec: the 12 beams are 3 x 5, 25 phases of 70 ms, offset 1, 1, and in the replace table 4090..4101
spec = list(csv.DictReader(open(P.SPEC['beam'], newline='')))
ok(len(spec) == 12, f'{len(spec)} beams in pack36_beam.csv')
ok(all((r['w'], r['h'], r['phases'], r['ms'], r['dx'], r['dy']) == ('3', '5', '25', '70', '1', '1') for r in spec), 'beam spec rows')
p65 = os.path.join(P.ART, 'pack36_beam_p65.csv')
rep = list(csv.DictReader(open(p65, newline='')))
ok([r['name'] for r in rep] == [r['name'] for r in spec], 'the pair 65 spec lists the same beams')
ok([int(r['replace']) for r in rep] == list(range(4090, 4102)), 'in place at effects 4090 to 4101')
ok(all((r['w'], r['h'], r['phases'], r['ms'], r['dx'], r['dy'], r['file']) == (s['w'], s['h'], s['phases'], s['ms'], s['dx'], s['dy'], s['file'])
       for r, s in zip(rep, spec)), 'the pair 65 spec agrees with the beam spec')
# the beam ids of the server file are the ones replaced
ids = {}
lua = os.path.join(HERE, '..', '..', '..', 'server', 'data', 'lib', 'chaos_pack36_fx_ids.lua')
for line in open(lua, encoding='utf-8'):
    if line.startswith('ChaosVfx.beam_'):
        name = line[len('ChaosVfx.'):].split(' ')[0]
        ids[name] = (int(line.split('{id = ')[1].split(',')[0]), line.split('dx = ')[1].split(',')[0], line.split('dy = ')[1].split(',')[0])
ok(all(ids.get(r['name']) == (int(r['replace']), r['dx'], r['dy']) for r in rep), 'server ids file: beam ids and send offsets')

if fails:
    print(f'{fails} failed')
    sys.exit(1)
print('gen_pack36 beams: ok')
