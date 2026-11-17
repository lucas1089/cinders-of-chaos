#!/usr/bin/env python3
"""Tests of gen_spell_vfx.py (O596): the table rules, the pair refusal, the game size cut on synthetic sheets, the
generated server files. No pack art and no pair: python3 -I client/tools/sprites/gen_spell_vfx_test.py (numpy, Pillow)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_spell_vfx as G  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def test_table():
    rows = G.pieces()
    ok(G.table_errors(rows) == [], 'the table of the script holds its rules: %s' % G.table_errors(rows))
    eff = [r for r in rows if r['kind'] == 'effect']
    ok(eff[0]['id'] == 4743 and eff[-1]['id'] <= 5142, 'effects in the block 4743..5142')
    ok(all(r['id'] <= 253 for r in rows if r['kind'] == 'missile'), 'a projectile id is one byte')
    bad = [dict(r) for r in rows]
    bad[3]['id'] = 9
    ok(G.table_errors(bad), 'a hole in the ids is found')
    bad = [dict(r) for r in rows]
    bad[-1]['id'] = 254
    ok(G.table_errors(bad), 'projectile 254 is refused')
    bad = [dict(r) for r in rows]
    bad[0]['src'] = 'fire_pack.png'
    ok(G.table_errors(bad), 'src must be 12 hex')
    bad = [dict(r) for r in rows]
    bad[1]['src'] = bad[0]['src']
    ok(G.table_errors(bad), 'a sheet used twice is found')
    # the committed table is the script's, the total row records the count
    spec = G.read_spec()
    ok([r['name'] for r in spec] == [r['name'] for r in rows], 'spell_vfx.csv lists the pieces in order')
    ok(G.read_total() == [len(eff)], 'the total row records the exact count for the next step')
    ok(list(G.read_sums()) == [r['name'] for r in rows], 'one sum per piece, in order')
    ok(G.check() == 0, 'check passes on the repository')


def test_pair_refusal():
    ok(G.pair_ok(4742, 253), 'pair 72 counts')
    ok(not G.pair_ok(4782, 253), 'already imported')
    ok(not G.pair_ok(4742, 254), 'another missile count')
    ok(not G.pair_ok(4702, 253), 'an older pair')


def sheet(cols, rows, frames, blob):
    """a synthetic sheet: a soft round blob per cell, growing by frame, a hard core inside"""
    import numpy as np
    from PIL import Image
    a = np.zeros((rows * G.CELL, cols * G.CELL, 4), np.float32)
    ys, xs = np.indices((G.CELL, G.CELL))
    for i in range(frames):
        cx, cy, r = blob(i)
        d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
        al = np.clip(1.2 - d / r, 0, 1)
        cell = np.zeros((G.CELL, G.CELL, 4), np.float32)
        cell[..., 0] = 1.0
        cell[..., 1] = np.clip(1 - d / r, 0, 1)
        cell[..., 2] = 0.2
        cell[..., 3] = al
        c, rr = i % cols, i // cols
        a[rr * G.CELL:(rr + 1) * G.CELL, c * G.CELL:(c + 1) * G.CELL] = cell
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA')


def test_effect():
    import numpy as np
    r = dict(kind='effect', cols=6, rows=4, frames=24, ax=0.5, ay=0.5, size=96, at='tile')
    # frames 0..3 and 20..23 are empty: they are dropped
    sh = sheet(6, 4, 24, lambda i: (64, 64, 0.01 if i < 4 or i >= 20 else 20 + i))
    strip, more = G.build_effect(r, sh)
    ok(more['phases'] == G.MAX_PHASES and 60 <= more['ms'] <= 120, 'at most 12 phases, 60..120 ms: %s' % more)
    ok((more['w'], more['h'], more['dx'], more['dy']) == (3, 3, 1, 1), 'a 96 px piece on the tile middle is 3 x 3 at (1, 1): %s' % more)
    ok(strip.shape == (96, 96 * more['phases'], 4), 'strip shape')
    ok(set(np.unique(strip[..., 3]).tolist()) <= {0, G.GLOW, 255}, 'alpha is 0, one glow level or 255')
    ok((strip[..., 3] == G.GLOW).any() and (strip[..., 3] == 255).any(), 'a core and a glow')
    ok(not strip[strip[..., 3] == 0].any(), 'a transparent pixel carries no colour')
    cols = {tuple(c) for c in strip[strip[..., 3] > 0][:, :3].tolist()}
    ok(len(cols) <= G.COLOURS, 'at most %d colours' % G.COLOURS)
    for f in range(more['phases']):
        fr = strip[:, f * 96:(f + 1) * 96, 3]
        ok(fr.any(), 'no empty phase')
        ys, xs = np.where(fr == 255)
        ok(abs(xs.mean() - 47.5) < 2 and abs(ys.mean() - 47.5) < 2, 'the anchor sits on the middle of the target tile')
    again, _ = G.build_effect(r, sh)
    ok(G.digest(again) == G.digest(strip), 'the same sheet gives the same strip')
    # a feet anchored piece stands on the tile: the canvas grows up, not down
    r2 = dict(r, ay=0.9, at='feet', size=96)
    sh2 = sheet(6, 4, 24, lambda i: (64, 70, 40))
    _, m2 = G.build_effect(r2, sh2)
    ok(m2['h'] >= 3 and m2['dy'] <= 1 and m2['h'] - 1 - m2['dy'] >= 2, 'feet anchor: the art rises above the target tile: %s' % m2)
    # a small hit is small
    r3 = dict(r, size=64)
    sh3 = sheet(6, 4, 24, lambda i: (64, 64, 20))
    _, m3 = G.build_effect(r3, sh3)
    ok(m3['w'] <= 3 and m3['h'] <= 3, '64 px footprint')


def test_lift():
    import numpy as np
    f = np.zeros((1, 3, 4), np.float32)
    f[0, :, 3] = (0.15, 0.35, 0.6)
    f[..., 0] = 0.9
    out = G.lift(f)
    ok(out[0, 0, 3] > 0.15 and out[0, 1, 3] > 0.35 and out[0, 2, 3] > 0.6, 'the lift raises every alpha')
    cutd = G.cut(out, np.array([[0.9, 0.0, 0.0]], np.float32))
    ok(cutd[0, :, 3].tolist() == [G.GLOW, 255, 255], 'a faint glow survives as the glow level, a soft edge becomes solid: %s' % cutd[0, :, 3].tolist())
    ok(G.pick_phases([False, True, True, True, False]) == [1, 2, 3], 'phases from the first to the last shown frame')
    ok(len(G.pick_phases([True] * 32)) == G.MAX_PHASES, '32 frames give 12 phases')
    ok(G.fit_axis(-48, 48, 16) == (1, 1) and G.fit_axis(-16, 16, 16) == (0, 0), 'tiles round the target tile')


def test_missile():
    import numpy as np
    r = dict(kind='missile', cols=6, rows=4, frames=24, ax=0.7, ay=0.5)
    # the head at the anchor, a tail behind it (to the left: the sheet flies east)
    sh = sheet(6, 4, 24, lambda i: (0.7 * G.CELL - 6, 64, 14))
    strip, more = G.build_missile(r, sh)
    P, n = G.MISSILE_PX, G.MISSILE_PHASES
    ok(more == dict(w=3, h=3, phases=n, ms=G.MISSILE_MS, dx=1, dy=1), 'a projectile is 3 x 3 at (1, 1), 8 phases of 50 ms')
    ok(strip.shape == (3 * P, 3 * P * n, 4), 'strip shape: 3 x 3 patterns of 8 phases')
    ok(set(np.unique(strip[..., 3]).tolist()) <= {0, G.GLOW, 255}, 'alpha levels')

    def centre(x, y):
        fr = strip[y * P:(y + 1) * P, (x * n) * P:(x * n + 1) * P, 3]
        ys, xs = np.where(fr == 255)
        return xs.mean() - P / 2, ys.mean() - P / 2
    ex, ey = centre(2, 1)       # east: the body trails west of the head
    ok(ex < -0.5 and abs(ey) < 1.5, 'east: the tail is west of the middle (%.1f, %.1f)' % (ex, ey))
    wx, wy = centre(0, 1)
    ok(wx > 0.5 and abs(wy) < 1.5, 'west: the tail is east')
    nx, ny = centre(1, 0)
    ok(ny > 0.5 and abs(nx) < 1.5, 'north: the tail is south')
    sx, sy = centre(1, 2)
    ok(sy < -0.5 and abs(sx) < 1.5, 'south: the tail is north')
    ok(np.array_equal(strip[P:2 * P, n * P:2 * n * P], strip[2 * P:3 * P, n * P:2 * n * P]), 'the centre pattern repeats south')
    for y in range(3):
        for x in range(3):
            for f in range(n):
                ok(strip[y * P:(y + 1) * P, (x * n + f) * P:(x * n + f + 1) * P, 3].any(), 'no empty pattern')


def test_server_files():
    rows = G.read_spec()
    lua = G.lua_text(rows)
    ok(open(G.LUA).read() == lua, 'chaos_spell_vfx_ids.lua is up to date')
    ok('first = 4743, count = %d' % sum(1 for r in rows if r['kind'] == 'effect') in lua, 'the count is in the ids file')
    tags = G.tags_text(rows)
    ok(open(G.TAGS, newline='').read() == tags, 'the tags are up to date')
    ok(G.tags_text(rows) == tags, 'writing the tags twice changes nothing')
    for r in rows:
        if r['kind'] == 'effect':
            ok('%s,%s,%s\n' % (r['id'], r['name'], r['element']) in tags, 'tag row of ' + r['name'])
    for p in (G.SPEC, G.SUMS, G.LUA):
        text = open(p).read().lower()
        ok(not any(w in text for w in G.PACK_WORDS), 'no pack name in ' + os.path.basename(p))
        ok('.png' not in text, 'no picture file name in ' + os.path.basename(p))


def main():
    test_table()
    test_pair_refusal()
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        print('gen_spell_vfx_test: numpy / Pillow missing, the art tests are skipped')
    else:
        test_effect()
        test_lift()
        test_missile()
    test_server_files()
    print('gen_spell_vfx_test: %d checks passed' % N[0])


if __name__ == '__main__':
    main()
