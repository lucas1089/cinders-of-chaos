#!/usr/bin/env python3
"""Tests of gen_gap_fx.py (O606): the table rules, the pair refusal and the padding, the cut and the placement on
synthetic sheets, the generated server files. No purchased art and no pair:
python3 -I client/tools/sprites/gen_gap_fx_test.py (numpy, Pillow)."""
import csv
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_gap_fx as G  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def test_table():
    rows = G.pieces()
    ok(G.table_errors(rows) == [], 'the table of the script holds its rules: %s' % G.table_errors(rows))
    ok(rows[0]['id'] == 5190 and rows[-1]['id'] <= G.LAST, 'effects in the block 5190..%d' % G.LAST)
    ok(G.FIRST > 5189, 'the ids of the steps before (4743..5189) are not touched')
    bad = [dict(r) for r in rows]
    bad[1]['id'] = 9
    ok(G.table_errors(bad), 'a hole in the ids is found')
    bad = [dict(r) for r in rows]
    bad[0]['src'] = 'sheet.png'
    ok(G.table_errors(bad), 'src must be 12 hex')
    bad = [dict(r) for r in rows]
    bad[0]['name'] = 'talent'
    ok(G.table_errors(bad), 'a name is gx_*')
    bad = [dict(r) for r in rows]
    bad[0]['f1'] = bad[0]['frames']
    ok(G.table_errors(bad), 'a frame past the sheet is found')
    bad = [dict(r) for r in rows]
    bad[0]['fw'] = 100
    ok(G.table_errors(bad), 'a frame is whole tiles')
    bad = [dict(r) for r in rows]
    bad[1]['src'], bad[1]['frames'], bad[1]['f0'], bad[1]['f1'] = bad[0]['src'], bad[0]['frames'], bad[0]['f0'], bad[0]['f1']
    ok(G.table_errors(bad), 'a frame used twice is found')
    # the strike circle is one sheet cut in two halves that share no frame
    zone = next(r for r in rows if r['name'] == 'gx_tele_zone')
    fill = next(r for r in rows if r['name'] == 'gx_tele_fill')
    ok(zone['src'] == fill['src'] and zone['f1'] + 1 == fill['f0'] and fill['f1'] < fill['frames'],
       'the telegraph pulse and its fill are two parts of one sheet')
    # the committed table is the script's, the total row records the count
    spec = G.read_spec()
    ok([r['name'] for r in spec] == [r['name'] for r in rows], 'gap_fx.csv lists the picks in order')
    ok(G.read_total() == [len(rows)], 'the total row records the exact count')
    ok(list(G.read_sums()) == [r['name'] for r in rows], 'one sum per effect, in order')
    ok(G.check() == 0, 'check passes on the repository')
    ok(all(1 <= int(r['phases']) <= G.MAX_PHASES and int(r['ms']) == 83 for r in spec), 'at most 24 phases of 83 ms')


def test_pair_refusal():
    ok(G.pair_ok(4742, 253) and G.pads(4742) == 447, 'pair 72: 447 blank effects, 4743..5189')
    ok(G.pair_ok(4744, 253) and G.pads(4744) == 445, 'pair 72 with the spell effects: 445')
    ok(G.pair_ok(5189, 253) and G.pads(5189) == 0, 'every earlier step done: nothing to pad')
    ok(not G.pair_ok(5190, 253), 'already imported')
    ok(not G.pair_ok(4742, 254), 'another missile count')
    ok(not G.pair_ok(4702, 253), 'an older pair')


def sheet(fw, fh, frames, blob):
    """a synthetic sheet, one row of frames: a soft round blob per frame with a hard core. blob(i) -> (cx, cy, radius)"""
    import numpy as np
    from PIL import Image
    a = np.zeros((fh, fw * frames, 4), np.float32)
    ys, xs = np.indices((fh, fw))
    for i in range(frames):
        cx, cy, r = blob(i)
        d = np.sqrt((xs + 0.5 - cx) ** 2 + (ys + 0.5 - cy) ** 2)
        cell = np.zeros((fh, fw, 4), np.float32)
        cell[..., 0] = 1.0
        cell[..., 1] = 0.5
        cell[..., 3] = np.clip(1.25 - d / r, 0, 1) if r > 0 else 0
        a[:, i * fw:(i + 1) * fw] = cell
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA')


def row(**kw):
    r = dict(kind='effect', name='gx_test', fw=96, fh=96, frames=12, ax=1, ay=1, f0=0, f1=11, at='stand')
    r.update(kw)
    return r


def centre(strip, w, h, dx, dy, f=0):
    """the solid centroid of phase f, in px from the target tile's top left"""
    import numpy as np
    fr = strip[:, f * w * 32:(f + 1) * w * 32, 3]
    ys, xs = np.where(fr == 255)
    return xs.mean() + 0.5 - (w - 1 - dx) * 32, ys.mean() + 0.5 - (h - 1 - dy) * 32


def test_effect():
    import numpy as np
    # the set's unit point: a ring centred on 24, 24 of the anchor tile (56, 56 of a 3 x 3 frame anchored at 1, 1)
    sh = sheet(96, 96, 12, lambda i: (56.5, 56.5, 0 if i in (0, 11) else 18 + i))
    strip, m = G.build_effect(row(), sh)
    ok(m['phases'] == 10 and m['ms'] == 83, 'the empty first and last frames are dropped: %s' % m)
    ok((m['sx'], m['sy']) == (-8, -4), 'stand: 8 px left, 4 px up: %s' % m)
    ok(strip.shape == (m['h'] * 32, m['w'] * 32 * m['phases'], 4), 'strip shape')
    ok(set(np.unique(strip[..., 3]).tolist()) == {0, G.GLOW, 255}, 'alpha is 0, one glow level and 255')
    ok(not strip[strip[..., 3] == 0].any(), 'a transparent pixel carries no colour')
    cols = {tuple(c) for c in strip[strip[..., 3] > 0][:, :3].tolist()}
    ok(cols == {(255, 128, 0)}, 'the colours are the sheet\'s: %s' % cols)
    for f in range(m['phases']):
        x, y = centre(strip, m['w'], m['h'], m['dx'], m['dy'], f)
        ok(abs(x - 16.5) <= 0.51 and abs(y - 20.0) <= 0.51, 'stand: the ring is on our standing point (%.1f, %.1f)' % (x, y))
    again, _ = G.build_effect(row(), sh)
    ok(G.digest(again) == G.digest(strip), 'the same sheet gives the same strip')
    # tile: a floor mark, centred on the tile's middle
    strip, m = G.build_effect(row(at='tile'), sh)
    x, y = centre(strip, m['w'], m['h'], m['dx'], m['dy'])
    ok((m['sx'], m['sy']) == (-8, -8) and abs(x - 16) <= 0.51 and abs(y - 16) <= 0.51, 'tile: the ring centre is 16, 16: %s' % m)
    ok(m['w'] == 3 and m['h'] == 3 and (m['dx'], m['dy']) == (1, 1), 'a 56 px ring on the tile middle is 3 x 3 at (1, 1): %s' % m)
    # gate: the width is centred, the height is the sheet's
    sh2 = sheet(128, 128, 6, lambda i: (66, 40, 30))
    strip, m = G.build_effect(row(fw=128, fh=128, frames=6, ax=2, ay=2, f1=5, at='gate'), sh2)
    x, y = centre(strip, m['w'], m['h'], m['dx'], m['dy'])
    ok((m['sx'], m['sy']) == (14, 0) and abs(x - 16) <= 0.51 and abs(y - (40 - 64)) <= 0.51, 'gate: x centred, y kept: %s' % m)
    ok(m['dy'] == 0 and m['h'] >= 2, 'a thing that rises over the tile: the canvas grows up, not down: %s' % m)
    # a sheet whose art is off the set's unit point is centred by its own pixels
    sh3 = sheet(128, 128, 4, lambda i: (76.5, 76.5, 20))
    _, m = G.build_effect(row(fw=128, fh=128, frames=4, ax=2, ay=2, f1=3), sh3)
    ok((m['sx'], m['sy']) == (4, 8), 'stand follows the centroid: %s' % m)
    # a part of a sheet: only its frames
    _, m = G.build_effect(row(f0=4, f1=7), sh)
    ok(m['phases'] == 4, 'frames 4..7 are 4 phases')
    # an empty frame inside is refused, never skipped silently
    sh4 = sheet(96, 96, 12, lambda i: (56.5, 56.5, 0 if i == 5 else 20))
    try:
        G.build_effect(row(), sh4)
        ok(False, 'an empty frame inside must stop the build')
    except AssertionError:
        ok(True, 'an empty frame inside stops the build')


def test_cut():
    import numpy as np
    f = np.zeros((1, 4, 4), np.uint8)
    f[0, :, 3] = (20, 40, 90, 200)             # 0.08, 0.16, 0.35, 0.78
    f[..., 0] = 200
    out = G.game_cut(f)
    ok(out[0, :, 3].tolist() == [0, G.GLOW, 255, 255],
       'the lift: a faint glow goes, a glow stays as the glow level, a soft edge is solid: %s' % out[0, :, 3].tolist())
    ok(out[0, 0].tolist() == [0, 0, 0, 0] and out[0, 3, 0] == 200, 'colours kept, nothing under a cut pixel')
    import gen_spell_vfx as V
    ok((G.CUT, G.HALO, G.GLOW, G.LIFT) == (V.CUT, V.HALO, V.GLOW, V.LIFT) == (0.5, 0.2, 144, 1.8), 'the cut of O596')


def test_import_spec():
    import numpy as np
    sh = sheet(96, 96, 12, lambda i: (56.5, 56.5, 20))
    strip, m = G.build_effect(row(), sh)
    r = dict(row(), note='n', **m)
    with tempfile.TemporaryDirectory() as tmp:
        spec = os.path.join(tmp, 'import.csv')
        G.import_spec(spec, tmp, 5187, [(r, strip)])
        rows = list(csv.DictReader(open(spec, newline='')))
        ok([x['name'] for x in rows] == ['gx_pad_5187', 'gx_pad_5188', 'gx_pad_5189', 'gx_test'], 'blank effects up to 5189, then the art')
        ok(all((x['w'], x['h'], x['phases']) == ('1', '1', '1') for x in rows[:3]), 'a blank effect is one empty 1 x 1 phase')
        ok(all(x['alpha'] == 'soft' and not x['replace'] for x in rows), 'appended, the glow level kept')
        from PIL import Image
        ok(not np.asarray(Image.open(rows[0]['file'])).any(), 'the blank picture is empty')
        ok(G.digest(np.asarray(Image.open(rows[3]['file']))) == G.digest(strip), 'the strip is written as built')


def test_server_files():
    rows = G.read_spec()
    lua = G.lua_text(rows)
    ok(open(G.LUA).read() == lua, 'chaos_gapfx_ids.lua is up to date')
    ok('first = 5190, count = %d' % len(rows) in lua, 'the count is in the ids file')
    tags = G.tags_text(rows)
    ok(open(G.TAGS, newline='').read() == tags, 'the tags are up to date')
    ok(G.tags_text(rows) == tags, 'writing the tags twice changes nothing')
    tagged = [r for r in rows if r['tag']]
    ok(sorted(r['name'] for r in tagged) == sorted(G.TAGGED), 'the snare effects are tagged')
    for r in tagged:
        ok('%s,%s,%s\n' % (r['id'], r['name'], r['tag']) in tags, 'tag row of ' + r['name'])
    for p in (G.SPEC, G.SUMS, G.LUA, os.path.join(HERE, 'gen_gap_fx.py')):
        text = open(p).read().lower()
        ok(not any(w in text for w in G.PACK_WORDS), 'no pack name in ' + os.path.basename(p))
    for p in (G.SPEC, G.SUMS, G.LUA):
        ok('.png' not in open(p).read().lower(), 'no picture file name in ' + os.path.basename(p))


def main():
    test_table()
    test_pair_refusal()
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        print('gen_gap_fx_test: numpy / Pillow missing, the art tests are skipped')
    else:
        test_effect()
        test_cut()
        test_import_spec()
    test_server_files()
    print('gen_gap_fx_test: %d checks passed' % N[0])


if __name__ == '__main__':
    main()
