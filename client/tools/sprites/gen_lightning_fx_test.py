#!/usr/bin/env python3
"""Tests of gen_lightning_fx.py (O614): the table rules, the pair refusal and the padding, the drawing held to its bar
(the same bytes twice, 6 to 10 frames, alpha 0 / one glow level / 255, the palette, the strike is one piece from the sky
to the target tile, branches inside the canvas and ending in the air), the tints, the import spec (the build appends
only), the generated server files. No pair:
python3 -I client/tools/sprites/gen_lightning_fx_test.py (numpy, Pillow)."""
import csv
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_lightning_fx as G  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def test_table():
    rows = G.pieces()
    ok(G.table_errors(rows) == [], 'the table of the script holds its rules: %s' % G.table_errors(rows))
    ok(rows[0]['id'] == 5331 and rows[-1]['id'] <= G.LAST, 'effects in the block 5331..%d' % G.LAST)
    ok(G.FIRST == 5331, 'the ids of the steps before (4743..5330) are not touched')
    ok(all(6 <= r['phases'] <= 10 for r in rows), '6 to 10 frames')
    ok({r['size'] for r in rows} == {'std', 'heavy'} and {r['tint'] for r in rows} == {'energy'},
       'the pair has plain and heavy bolts, energy only')
    ok(len({r['seed'] for r in rows}) == len(rows), 'every variant has its own seed')
    bad = [dict(r) for r in rows]
    bad[1]['id'] = 9
    ok(G.table_errors(bad), 'a hole in the ids is found')
    bad = [dict(r) for r in rows]
    bad[0]['name'] = 'bolt'
    ok(G.table_errors(bad), 'a name is lf_*')
    bad = [dict(r) for r in rows]
    bad[1]['seed'] = bad[0]['seed']
    ok(G.table_errors(bad), 'the same bolt twice is found')
    bad = [dict(r) for r in rows]
    bad[0]['tag'] = 'fire'
    ok(G.table_errors(bad), 'the tag follows the tint')
    bad = [dict(r) for r in rows]
    bad[0]['durs'] = '50;50'
    ok(G.table_errors(bad), 'one duration per frame')
    bad = [dict(r) for r in rows]
    bad[0]['dx'] = 4
    ok(G.table_errors(bad), 'a send offset outside the canvas is found')
    spec = G.read_spec()
    ok([[str(r[k]) for k in G.FIELDS] for r in rows] == [[r[k] for k in G.FIELDS] for r in spec], 'lightning_fx.csv is the table')
    ok(G.read_total() == [len(rows)], 'the total row records the exact count')
    ok(list(G.read_sums()) == [r['name'] for r in rows], 'one sum per effect, in order')
    ok(G.check(quiet=True) == 0, 'check passes on the repository')


def test_pair_refusal():
    ok(G.pair_ok(5330, 253) and G.pads(5330) == 0, 'every effect step of pair 73 done: nothing to pad')
    ok(G.pair_ok(4742, 253) and G.pads(4742) == 588, 'pair 72: 588 blank effects, 4743..5330')
    ok(not G.pair_ok(5331, 253), 'already imported')
    ok(not G.pair_ok(5330, 254), 'another missile count')
    ok(not G.pair_ok(4702, 253), 'an older pair')


def test_drawing():
    import numpy as np
    pairs = G.build_rows()
    again = G.build_rows()
    sums = G.read_sums()
    digests = set()
    for (r, s), (_r2, s2) in zip(pairs, again):
        ok(s.tobytes() == s2.tobytes(), '%s: the same bytes twice' % r['name'])
        ok(G.digest(s) == sums[r['name']], '%s: the committed sum' % r['name'])
        digests.add(G.digest(s))
        ok(G.art_errors(s, r) == [], '%s holds the bar: %s' % (r['name'], G.art_errors(s, r)))
        z = G.SIZES[r['size']]
        W, H, n = z['w'] * 32, z['h'] * 32, len(z['script'])
        ok(s.shape == (H, W * n, 4) and s.dtype == np.uint8, '%s: %d frames of the canvas' % (r['name'], n))
        ok(set(np.unique(s[..., 3]).tolist()) == {0, G.GLOW, 255}, '%s: alpha is 0, the glow level and 255' % r['name'])
        cols = {tuple(c) for c in s[s[..., 3] > 0][:, :3].tolist()}
        ok(cols == set(G.PALETTES[r['tint']]) and len(cols) == 4, '%s: the four colours of its palette' % r['name'])
        glow = {tuple(c) for c in s[s[..., 3] == G.GLOW][:, :3].tolist()}
        ok(glow == {G.PALETTES[r['tint']][3]}, '%s: the glow level has the glow colour only' % r['name'])
        tx, ty = G.target(r['size'])
        k = next(i for i, e in enumerate(z['script']) if e[0] == 'strike')
        fr = [s[:, f * W:(f + 1) * W] for f in range(n)]
        px = [int((f[..., 3] > 0).sum()) for f in fr]
        ok(px.index(max(px)) == k, '%s: the strike is the fullest frame' % r['name'])
        ok(px[0] < px[1] < px[k] and px[-1] < px[-2] < px[k], '%s: leader grows, afterglow fades: %s' % (r['name'], px))
        ok((fr[k][ty, tx] == G.PALETTES[r['tint']][0] + (255,)).all(), '%s: the core hits the target point' % r['name'])
        ok(fr[k][0, :, 3].any() and not fr[0][ty - 16:, :, 3].any(), '%s: it comes in at the top; the leader is still in the air' % r['name'])
        lit = np.nonzero(fr[k][..., 3].any(axis=0))[0]
        ok(int(lit.min()) < tx - 32, '%s: it falls from up-left of the target' % r['name'])
        top = np.nonzero(fr[k][0, :, 3])[0]
        ok(top.mean() < tx - 0.3 * ty, '%s: the oblique lean' % r['name'])
        # the shape: channel and branches inside the canvas, a branch ends above the ground burst
        sh = G.shape(r['seed'], r['size'])
        ok(len(sh['branches']) >= 2, '%s: branches' % r['name'])
        for b in sh['branches'] + [sh['main']] + sh['shaken']:
            ok(all(2 <= x < W - 2 and 0 <= y < H for x, y in b), '%s: a stroke stays inside the canvas' % r['name'])
        for b in sh['branches']:
            ok(max(y for _x, y in b) < ty - 13, '%s: a branch ends in the air' % r['name'])
        ok(sh['main'][-1] == (tx, ty) and all(p[-1] == (tx, ty) for p in sh['shaken']), '%s: every channel ends on the target point' % r['name'])
        tile = fr[k][ty - G.STAND[1]:ty - G.STAND[1] + 32, tx - G.STAND[0]:tx - G.STAND[0] + 32, 3]
        ok(int((tile == 255).sum()) > 60, '%s: the ground burst is on the target tile' % r['name'])
    ok(len(digests) == len(pairs), 'no two variants are the same picture')
    # the target tile is where the send offset says
    for size, z in G.SIZES.items():
        tx, ty = G.target(size)
        ok((tx // 32, ty // 32) == (z['w'] - 1 - z['dx'], z['h'] - 1 - z['dy']), '%s: the target point is in the target tile' % size)
        ok(sum(e[0] == 'strike' for e in z['script']) == 1 and z['script'][0][0] == 'lead' and z['script'][-1][0] == 'embers',
           '%s: leader, one strike, afterglow' % size)
    ok(G.target('heavy')[1] > G.target('std')[1] + 24, 'the heavy bolt falls from higher')
    # a bolt that misses the tile, a stray alpha and a foreign colour are found
    r, s = pairs[0]
    W = G.SIZES[r['size']]['w'] * 32
    bad = s.copy()
    tx, ty = G.target(r['size'])
    bad[ty - 40:ty - 30, 2 * W:3 * W] = 0
    ok(G.art_errors(bad, r), 'a strike cut off above the tile is found')
    bad = s.copy()
    bad[5, 5] = (255, 255, 255, 90)
    ok(G.art_errors(bad, r), 'a second glow level is found')
    bad = s.copy()
    bad[5, 5] = (255, 0, 0, 255)
    ok(G.art_errors(bad, r), 'a colour outside the palette is found')
    bad = s.copy()
    bad[5, 5] = (255, 255, 255, 0)
    ok(G.art_errors(bad, r), 'a colour under a transparent pixel is found')
    bad = s.copy()
    bad[-1, 5] = G.PALETTES['energy'][0] + (255,)
    ok(G.art_errors(bad, r), 'art on the bottom edge is found')


def test_tints():
    import numpy as np
    names = [v[0] for v in G.all_variants()]
    ok(len(set(names)) == len(names) and len(names) == len(G.VARIANTS) + 4, 'the sheets: the pair, then holy and dark')
    base = G.strip_of(G.frames(11, 'energy', 'std'))
    for tint in ('holy', 'dark'):
        s = G.strip_of(G.frames(11, tint, 'std'))
        ok((s[..., 3] == base[..., 3]).all(), '%s: the same shape as energy' % tint)
        cols = {tuple(c) for c in s[s[..., 3] > 0][:, :3].tolist()}
        ok(cols == set(G.PALETTES[tint]), '%s: its own palette' % tint)
        row = dict(name=tint, size='std', tint=tint)
        ok(G.art_errors(s, row) == [], '%s holds the bar' % tint)
    ok(len({p for pal in G.PALETTES.values() for p in pal}) == 12, 'no colour shared between tints')
    ok(not np.array_equal(G.strip_of(G.frames(11, 'energy', 'std')), G.strip_of(G.frames(12, 'energy', 'std'))), 'another seed, another bolt')


def test_import_spec():
    import numpy as np
    from PIL import Image
    pairs = G.build_rows()
    with tempfile.TemporaryDirectory() as tmp:
        spec = os.path.join(tmp, 'import.csv')
        G.import_spec(spec, tmp, 5329, pairs)
        rows = list(csv.DictReader(open(spec, newline='')))
        ok([x['name'] for x in rows] == ['lf_pad_5329', 'lf_pad_5330'] + [r['name'] for r, _ in pairs],
           'blank effects up to 5330, then the bolts in id order')
        ok(all((x['w'], x['h'], x['phases'], x['blank']) == ('1', '1', '1', '1') for x in rows[:2]), 'a blank effect is one empty 1 x 1 phase')
        ok(all(x['kind'] == 'effect' and not x['replace'] and not x['lua'] for x in rows), 'the build appends only: effects, nothing replaced')
        ok(all(x['alpha'] == 'soft' for x in rows), 'the glow level is kept')
        ok(not np.asarray(Image.open(rows[0]['file'])).any(), 'the blank picture is empty')
        for x, (r, s) in zip(rows[2:], pairs):
            ok(G.digest(np.asarray(Image.open(x['file']))) == G.digest(s), '%s: the strip is written as drawn' % r['name'])
            ok(x['durs'] == r['durs'] and (int(x['dx']), int(x['dy'])) == (r['dx'], r['dy']), '%s: durations and send offset' % r['name'])
        G.import_spec(spec, tmp, 5331, pairs)
        rows = list(csv.DictReader(open(spec, newline='')))
        ok([x['name'] for x in rows] == [r['name'] for r, _ in pairs], 'on a pair with 5330 effects nothing is padded')


def test_server_files():
    rows = G.read_spec()
    lua = G.lua_text(rows)
    ok(open(G.LUA).read() == lua, 'chaos_lightning_fx_ids.lua is up to date')
    ok('first = 5331, count = %d' % len(rows) in lua, 'the count is in the ids file')
    for r in rows:
        ms = sum(int(v) for v in r['durs'].split(';'))
        ok('%s = {id = %s, dx = %s, dy = %s, ms = %d,' % (r['name'], r['id'], r['dx'], r['dy'], ms) in lua, 'ids row of ' + r['name'])
    tags = G.tags_text(rows)
    ok(open(G.TAGS, newline='').read() == tags, 'the tags are up to date')
    ok(G.tags_text(rows) == tags, 'writing the tags twice changes nothing')
    for r in rows:
        ok('%s,%s,energy\n' % (r['id'], r['name']) in tags, 'tag row of ' + r['name'])
    for p in (G.SPEC, G.SUMS, G.LUA):
        ok('.png' not in open(p).read().lower(), 'no picture file name in ' + os.path.basename(p))
    lib = open(os.path.join(G.ROOT, 'server', 'data', 'lib', 'chaos_lightning_fx.lua')).read()
    for r in rows:
        ok('"%s"' % r['name'] in lib, '%s has a sender in chaos_lightning_fx.lua' % r['name'])
    here = set(os.listdir(G.ART))
    ok(not any(f.startswith('lightning_fx') and f.endswith('.png') for f in here), 'no art file in the repository')


def main():
    test_pair_refusal()
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        print('gen_lightning_fx_test: numpy / Pillow missing, the art tests are skipped')
    else:
        test_table()
        test_drawing()
        test_tints()
        test_import_spec()
    test_server_files()
    print('gen_lightning_fx_test: %d checks passed' % N[0])


if __name__ == '__main__':
    main()
