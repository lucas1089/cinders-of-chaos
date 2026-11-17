#!/usr/bin/env python3
"""Tests of gen_decor_flames.py (O623): the table rules, the fit on a synthetic raw sheet (the same bytes twice, 12 frames, the
loop closes, alpha 0 / 144 / 255, the theme palette, sizes, pieces under 3 pixels gone, the cold recolour), the committed strips
held to the same bar, the committed files up to date, the importer's manifest, and `build` / `live` on a small synthetic pair
(torch in place, four items appended). No pair, no node: python3 -I client/tools/sprites/gen_decor_flames_test.py (numpy, Pillow)."""
import csv
import io
import os
import shutil
import struct
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_decor_flames as G  # noqa: E402
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def test_table():
    rows = G.pieces()
    ok(G.table_errors(rows) == [], 'the table holds its rules: %s' % G.table_errors(rows))
    ok([r['client_id'] for r in rows] == [44544, 44560, 44561, 44562, 44563], 'ids: the torch, then 44560 up')
    ok(G.FIRST == 44560 and G.EXPECT_ITEMS == 44559, 'new items follow the 44,559 items of pair 73')
    ok(all(r['server_id'] == r['client_id'] + 4000 for r in rows), 'server id = client id + 4000')
    ok({r['key']: r['w'] for r in rows} == {'torch': 2, 'brazier': 2, 'campfire': 2, 'candle': 1, 'spirit': 1}, 'sizes')
    ok(all(r['frames'] <= 12 and 83 <= r['ms'] <= 120 for r in rows), 'at most 12 frames, 83 to 120 ms')
    ok(G.PAIR == 74, 'joins pair 74')
    for mut, what in ((lambda r: r[1].update(client_id=9), 'a hole in the ids'),
                      (lambda r: r[2].update(name='campfire'), 'a new name without "flame "'),
                      (lambda r: r[3].update(ms=300), 'a slow frame'),
                      (lambda r: r[0].update(mode='new'), 'the torch is not replaced'),
                      (lambda r: r[1].update(frames=20), 'too many frames'),
                      (lambda r: r[1].update(theme='x'), 'unknown theme')):
        bad = [dict(r) for r in rows]
        mut(bad)
        ok(G.table_errors(bad), what + ' is found')
    spec = list(csv.DictReader(open(G.SPEC, encoding='utf-8')))
    ok([[str(r[k]) for k in G.FIELDS] for r in rows] == [[r[k] for k in G.FIELDS] for r in spec], 'decor_flames.csv is the table')


def raw_frames(n=24, size=(40, 56), seed=1):
    """a synthetic periodic render: a body that stands, a flame that sways with the phase, a spark, a smoke haze"""
    rng = np.random.RandomState(seed)
    out = []
    for i in range(n):
        f = np.zeros((size[1], size[0], 4), np.uint8)
        ph = i / n * 2 * np.pi
        f[40:54, 14:26] = (90, 60, 40, 255)                         # the body
        sway = int(round(3 * np.sin(ph)))
        top = 24 + int(round(4 * np.cos(ph * 2)))
        f[top:40, 17 + sway:23 + sway] = (255, 160, 30, 255)         # the flame
        f[28:36, 19 + sway:21 + sway] = (255, 240, 160, 255)
        f[12:22, 16:24] = (150, 150, 150, 90 + int(40 * np.cos(ph)))  # smoke: soft alpha
        f[41:44, 14 + (i // 2) % 12] = (255, 230, 120, 255)           # a marching ember on the body
        f[5, 5 + (i % 3)] = (255, 220, 100, 255)                    # a spark: one pixel
        f[8, 30] = (0, 0, 0, 10)                                    # almost invisible
        out.append(f)
    return out, {'frameSize': [size[0], size[1]], 'pivot': [20, 54], 'frames': n}


def test_fit():
    frames, info = raw_frames()
    a, s = G.fit_one(frames, info, 1, 'fire', False)
    b, _s = G.fit_one(frames, info, 1, 'fire', False)
    ok(a.tobytes() == b.tobytes(), 'the same bytes twice')
    ok(a.shape == (32, 32 * 12, 4), 'a 1 x 1 strip of 12 frames is 384 x 32: %s' % (a.shape,))
    ok(0 < s < 1, 'a body taller than the canvas is scaled down, never up')
    ok(set(np.unique(a[..., 3]).tolist()) <= {0, 144, 255} and 144 in a[..., 3], 'alpha 0 / 144 / 255, the glow level is used')
    ok(not a[a[..., 3] == 0][:, :3].any(), 'a transparent pixel carries no colour')
    pal = {tuple(c) for c in G.theme_palette('fire').tolist()}
    cols = {tuple(c) for c in a[a[..., 3] > 0][:, :3].tolist()}
    ok(cols <= pal and len(cols) <= G.KEEP, 'colours are of the theme palette, at most KEEP')
    cells = G.cells_of(a, 1)
    ok(len({c.tobytes() for c in cells}) == 12, 'twelve different frames')
    steps = [G.step_size(cells[i], cells[(i + 1) % 12]) for i in range(12)]
    ok(steps[-1] <= 1.5 * max(steps[:-1]), 'the loop closes: last step %.1f, others up to %.1f' % (steps[-1], max(steps[:-1])))
    row = dict(G.pieces()[3])
    ok(G.strip_problems(a, row) == [], 'a fitted strip holds the bar: %s' % G.strip_problems(a, row))
    # a 2 x 2 canvas: the body stands on the bottom row, the pivot on the middle column
    c, _s = G.fit_one(frames, info, 2, 'fire', False)
    ok(c.shape == (64, 64 * 12, 4), '2 x 2 strip size')
    ys, xs = np.nonzero(G.cells_of(c, 2)[0][..., 3] == 255)
    ok(ys.max() == 63, 'the body stands on the bottom row')
    ok(abs((xs.min() + xs.max()) / 2 - 32) <= 3, 'the pivot is on the middle column')
    # pieces under 3 pixels (sparks) are gone
    one = np.zeros((8, 8, 4), np.uint8)
    one[1, 1] = (255, 0, 0, 255)
    one[4:6, 4:7] = (255, 0, 0, 255)
    d = G.drop_pieces(one)
    ok(d[1, 1, 3] == 0 and (d[4:6, 4:7, 3] == 255).all(), 'a lone pixel goes, a piece stays')
    # the cold recolour turns teal to blue and lightens
    cold = G.cold_colour(np.array([[44, 196, 180], [10, 40, 60]], np.uint8))
    ok(cold[0][2] > cold[0][1] and cold[0].sum() > 44 + 196 + 180 - 40, 'teal becomes a lighter blue')
    cs, _s = G.fit_one(frames, info, 1, 'cold', True)
    cp_ = {tuple(c) for c in G.theme_palette('cold').tolist()}
    ok({tuple(c) for c in cs[cs[..., 3] > 0][:, :3].tolist()} <= cp_, 'the cold flame uses the rimewraith palette')
    # the bar finds faults
    bad = a.copy()
    bad[5, 5] = (1, 2, 3, 200)
    ok(G.strip_problems(bad, row), 'a strange alpha is found')
    bad = a.copy()
    bad[a[..., 3] == 255] = (1, 2, 3, 255)
    ok(any('palette' in p for p in G.strip_problems(bad, row)), 'a colour outside the palette is found')
    bad = np.concatenate([cells[0]] * 12, axis=1)
    ok(G.strip_problems(bad, row), 'twelve equal frames are found')
    ok(G.strip_problems(a[:, :-32], row), 'a missing frame is found')
    ramp = [np.roll(cells[0], k, axis=1) for k in range(12)]    # a drift that never comes back: the loop does not close
    ok(any('loop' in p for p in G.strip_problems(np.concatenate(ramp, axis=1), row)), 'a loop that does not close is found')


def test_committed():
    ok(G.check(quiet=True) == 0, 'check passes on the repository')
    for r in G.pieces():
        a = G.read_strip(r['key'])
        ok(G.strip_problems(a, r) == [], '%s holds the bar' % r['key'])
        ok(G.style_problems(a, r) == [], '%s passes style_check (own light, soft alpha)' % r['key'])
    cold = G.read_strip('spirit')
    px = cold[cold[..., 3] > 0][:, :3].astype(int)
    ok((px[:, 2] >= px[:, 0]).mean() > 0.9, 'the spirit flame is cold: blue over red in 9 of 10 pixels')
    warm = G.read_strip('brazier')
    px = warm[warm[..., 3] > 0][:, :3].astype(int)
    ok((px[:, 0] >= px[:, 2]).mean() > 0.9, 'the brazier is warm')
    sums = open(G.SUMS, encoding='utf-8').read()
    ok(G.PIXELFX_COMMIT in sums and G.SOURCE_SHA256 in sums, 'the sums name the pinned commit and the source digest')
    ok(len(G.SOURCE_SHA256) == 64, 'the source digest is pinned')


def synthetic():
    recs = [t.record({0: t.RED, 1: t.RED, 40: (10, 20, 30, 255)}), t.record({5: (200, 100, 50, 128)}),
            t.record({0: t.YELLOW, 1: t.RED}), t.record({100 + k: (10 * k, 2, 3, 255) for k in range(20)}),
            t.record({200: (9, 9, 9, 255)}), t.record({300: (7, 7, 7, 255)})]
    items = [t.entry(bytes([17]), [t.group([1])]),                                              # 100 a still
             t.entry(bytes([22]) + struct.pack('<HH', 6, 206), [t.group([2, 3, 4, 5], w=2, h=2)])]   # 101 the torch, 2 x 2, one frame
    base = t.good_parts()
    return recs, items, base[2], base[3], base[4]


def test_pair():
    c = t.Case()
    try:
        recs, items, outfits, effects, missiles = synthetic()
        dat, spr = c.pair(recs, items, outfits, effects, missiles)
        out = os.path.join(c.dir, 'out')
        G.build(dat, spr, out, torch=101, first=G.FIRST, expect=101)
        od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
        ok(G.live(od, os_, torch=101) == [], 'live: the pair holds the five flames pixel for pixel: %s' % G.live(od, os_, torch=101))
        old = cp.parse_dat(open(dat, 'rb').read())[2]
        new = cp.parse_dat(open(od, 'rb').read())[2]
        ok(len(new['item']) == G.FIRST + 3 - 99, 'items run to 44563')
        n101 = [x for x in new['item'] if x.id == 101][0]
        o101 = [x for x in old['item'] if x.id == 101][0]
        g = n101.groups[0]
        ok(n101.flags == o101.flags, 'the torch keeps its flag bytes (light 6 / 206)')
        ok((g.w, g.h, g.phases) == (2, 2, 12) and len(g.sprites) == 48, 'the torch is 2x2 of 12 phases')
        ok(len(new['outfit']) == len(old['outfit']) and len(new['effect']) == len(old['effect']), 'outfits and effects untouched')
        r = cp.check(od, os_, auras={2}, old=(dat, spr), allow_changed=cp.parse_allow('item:101'))
        ok(r.ok, 'the append-only guard passes with the torch allowed to change: ' + r.text())
        bad = cp.check(od, os_, auras={2}, old=(dat, spr))
        ok(not bad.ok, 'without the allowance the guard sees the torch change')
        # the live check finds a stale pair
        ok(G.live(dat, spr, torch=101), 'live: the input pair is not the output')
        # deterministic
        out2 = os.path.join(c.dir, 'out2')
        G.build(dat, spr, out2, torch=101, first=G.FIRST, expect=101)
        ok(open(os.path.join(out2, 'Tibia.spr'), 'rb').read() == open(os_, 'rb').read(), 'same inputs, same spr')
        ok(open(os.path.join(out2, 'Tibia.dat'), 'rb').read() == open(od, 'rb').read(), 'same inputs, same dat')
        # the importer's manifest is the committed one
        mp = os.path.join(c.dir, 'manifest.csv')
        import import_art_things as iat
        work = tempfile.mkdtemp(dir=c.dir)
        os.makedirs(os.path.join(work, 'decor_flames'))
        for r_ in G.pieces():
            shutil.copyfile(os.path.join(G.STRIPS, r_['key'] + '.png'), os.path.join(work, 'decor_flames', r_['key'] + '.png'))
        open(os.path.join(work, 'things.csv'), 'w', newline='').write(G.things_text(G.pieces()))
        argv, sys.argv = sys.argv, ['i', '--ours-dat', dat, '--ours-spr', spr, '--out-dir', os.path.join(work, 'o'), '--things',
                                    os.path.join(work, 'things.csv'), '--first-item', str(G.FIRST), '--expect-items', '101',
                                    '--server-offset', '4000', '--manifest-out', mp]
        try:
            iat.main()
        finally:
            sys.argv = argv
        ok(open(mp, encoding='utf-8').read() == open(G.MANIFEST, encoding='utf-8').read() == G.manifest_text(G.pieces()),
           "the importer's manifest is server/data/items/decor_flames.csv")
        rows = list(csv.DictReader(open(G.MANIFEST, encoding='utf-8')))
        ok([r_['client_id'] for r_ in rows] == ['44560', '44561', '44562', '44563'], 'the manifest holds the four new items')
        ok(all(int(r_['otb_flags']) & (1 << 24) for r_ in rows), 'animated items carry the ANIM flag')
        ok([(r_['key'], int(r_['light_level']), int(r_['light_color'])) for r_ in rows][-1] == ('spirit', 5, 101), 'the cold flame has a cold light')
        ok(not any(int(r_['otb_flags']) & (32 | 64) for r_ in rows), 'none is pickupable or moveable')
        # a refusal: the wrong pair
        try:
            G.build(dat, spr, os.path.join(c.dir, 'o3'), torch=101, first=G.FIRST, expect=44559)
            ok(False, 'the wrong item count is refused')
        except SystemExit:
            ok(True, 'the wrong item count is refused')
    finally:
        shutil.rmtree(c.dir, ignore_errors=True)


def test_preview_needs_nothing_secret():
    src = open(os.path.join(HERE, 'gen_decor_flames.py'), encoding='utf-8').read()
    ok('--permission' in src and '--allow-fs-read' in src, 'render runs node with the permission model')
    drv = open(G.DRIVER, encoding='utf-8').read()
    ok('child_process' not in drv and 'fetch(' not in drv and 'http' not in drv.replace('https://github.com/patch-gg/pixelfx', ''),
       'our driver spawns nothing and uses no network')
    ok('gallery' not in ' '.join(G.SOURCE_FILES), 'the gallery (its fonts are not MIT) is not copied')


for f in (test_table, test_fit, test_committed, test_pair, test_preview_needs_nothing_secret):
    f()
print('gen_decor_flames_test: OK (%d checks)' % N[0])
