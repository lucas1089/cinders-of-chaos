#!/usr/bin/env python3
"""Test of gen_pixellab_monsters.py (O640): python3 -I client/tools/sprites/gen_pixellab_monsters_test.py

The committed table, sums, sheets, picks rows and monster map against the rules, every rule with a failing case, and `load_source` /
`fit` / `make` / `art` / `build` / `live` on synthetic PixelLab downloads drawn here (folders KEY/idle|walk/south|east|north|west/NN.png of
random blocks: a small walker, a wide one, a tall one, a floater, a figure that hangs low, one that is too big) and a small synthetic
input pair: the hard alpha cut, the size (the smallest canvas of whole tiles, never sampled down), the one shift for every picture and the
displacement that puts the standing point on the tile (the O585 point, higher for a bigger outfit, a floater on its row), the idle
durations, the outfit shape (idle group, walk group, one layer, the displacement as the only flag), every slot reading back as drawn,
wrong input pairs (a pair that ends one outfit early is told to build Malgrath first) and an existing output folder refused, `live`
holding the pair to the sheets, the sums, the durations and the standing point. No PixelLab file and no real pair needed. Needs numpy and
Pillow (the fx venv of CI). Nothing drawn here is art of anyone."""
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_pixellab_monsters as P  # noqa: E402
import oblique_lean as L  # noqa: E402
import gen_wst_outfits as W  # noqa: E402
import gen_wst_outfits_test as WT  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from import_outfits import parse_body  # noqa: E402


def figure(root, key, cell, box, idle=4, walk=8, bob=1, seed=1, soft=False, tag='aa', lean=0.0):
    """root/key/{idle,walk}/{south,east,north,west}/NN.png: cell x cell pictures, a block of random colour in `box` (x, y, w, h) that moves
    a little from picture to picture and differs from direction to direction, leaning `lean` px a row (the game's angle, O728); ids.json
    names a character id"""
    rng = np.random.default_rng(seed + sum(map(ord, key)))
    x, y, w, h = box
    for kind, n in (('idle', idle), ('walk', walk)):
        for k, d in enumerate(P.DIRS if False else ('south', 'east', 'north', 'west')):
            p = os.path.join(root, key, kind, d)
            os.makedirs(p)
            for i in range(n):
                a = np.zeros((cell, cell, 4), np.uint8)
                col = rng.integers(40, 256, (h // 2, w // 2, 3)).astype(np.uint8)
                col = np.repeat(np.repeat(col, 2, 0), 2, 1)
                top = y + bob * (i % 2) + (i % 3 == 0)
                a[top:top + h, x + k:x + k + w, :3] = col
                a[top:top + h, x + k:x + k + w, 3] = 255
                # legs: two narrow columns down from the body, so the feet measure has something to stand on
                a[top + h:top + h + 4, x + k + 2:x + k + 5, :3] = 90
                a[top + h:top + h + 4, x + k + 2:x + k + 5, 3] = 255
                a[top + h:top + h + 4, x + k + w - 5:x + k + w - 2, :3] = 90
                a[top + h:top + h + 4, x + k + w - 5:x + k + w - 2, 3] = 255
                if soft:
                    a[top, x + k:x + k + w, 3] = 100        # a soft top row: cut away
                if lean:
                    a = L.shear(a, lean, y + h + 4 + bob + 1)
                Image.fromarray(a, 'RGBA').save(os.path.join(p, '%02d.png' % i))
    open(os.path.join(root, key, 'ids.json'), 'w').write('{"id": "%s000000-0000-4000-8000-000000000000"}' % tag)
    return os.path.join(root, key)


def spec(key, name, tier=1, role='roamer', fl=0):
    return (key, name, tier, role, fl)


def row(key='a', new=3, **kw):
    r = {'key': key, 'name': 'A', 'tier': '1', 'role': 'roamer', 'float': '0', 'new': str(new), 'tiles': '2x2', 'lean': '0.00', 'disp': '-16:0',
         'idle': '4',
         'idle_ms': '300', 'walk': '8', 'walk_ms': '100', 'pixels': '1000', 'src': 'a' * 12, 'pl': 'b' * 8}
    r.update({k: str(v) for k, v in kw.items()})
    return r


def main():
    # ---- the committed table, sums, sheets, picks rows and map
    t = P.rows()
    assert P.problems() == [], P.problems()
    assert len(t) == 24 and [int(r['new']) for r in t] == list(range(3531, 3555)) and P.FIRST_NEW == 3531 == P.OUTFITS_BEFORE + 1 and P.PAIR == 74
    assert [r['key'] for r in t] == list(P.KEYS) and len(set(P.KEYS)) == 24
    assert [int(r['tier']) for r in t].count(1) == 7 and [int(r['tier']) for r in t].count(2) == 6
    assert [int(r['tier']) for r in t].count(3) == 6 and [int(r['tier']) for r in t].count(4) == 5
    assert [r['key'] for r in t if r['float'] == '1'] == ['wisp', 'maw', 'bat', 'broodsac', 'veilwitch']
    assert {r['tiles'] for r in t} == {'2x2', '3x3'}, 'nothing is sampled down: a figure over 64 px is a 3x3 outfit'
    # the built size: the hound and the bat grow to 3x3 for their shear (O728); the sheets stay as drawn; every redraw is 3x3
    assert [r['key'] for r in t if r['tiles'] == '2x2'] == ['wisp', 'crawler', 'maw', 'broodsac']
    assert P.REDRAW_PENDING == () and all(r['tiles'] == '3x3' for r in t if r['key'] not in P.SHEAR), 'every oblique redraw is in (O728)'
    assert {r['key'] for r in t if r['lean'] != '0.00'} == set(P.SHEAR), 'every key of SHEAR is sheared (none leaned already)'
    assert all(P.read_sheet(r)[1][('idle', 0)][0].shape[0] == 64 for r in t if r['key'] in ('hound', 'bat'))
    assert all(r['walk'] == '8' and r['walk_ms'] == '100' for r in t) and [r['idle'] for r in t].count('15') == 1
    assert all(int(r['idle_ms']) == P.idle_ms_for(int(r['idle'])) for r in t) and P.idle_ms_for(4) == 300 and P.idle_ms_for(8) == 200 and P.idle_ms_for(15) == 100
    assert set(P.read_sums()) == {r['new'] for r in t} and all(len(v) == 64 for v in P.read_sums().values())
    assert len(set(P.read_sums().values())) == 24, 'two outfits with one digest'
    assert P.check_sheets() == [], P.check_sheets()
    assert P.check() == [], P.check()
    assert len(P.picks_rows()) == 24 and P.map_problems() == [] and P.write_map(check=True) == []
    assert P.map_text(P.map_rows()) == open(P.MAP, encoding='utf-8', newline='').read()
    picks = P.picks_rows()
    assert [n for _m, n, _d in picks] == list(range(3531, 3555)) and [d for _m, _n, d in picks] == list(range(1, 25))
    # a hunt monster of the pool on every look, one each, in the level band of the tier (the five boss-like looks: level 500 and more)
    lv = P.pool_levels()
    assert all(m in lv for m, _n, _d in picks) and len({m for m, _n, _d in picks}) == 24
    assert all(lv[m] >= 500 for (m, n, _d) in picks if int(t[n - 3531]['tier']) == 4)
    # the standing point: the O585 point on every sheet, as the numbers of the notes say
    for r in t:
        _a, cells = P.read_sheet(r)
        r, cells, _p = P.built(r, cells)
        m = P.measure_cells(r, cells)
        assert abs(m['stand'][0] - P.TX) <= 1 and abs(m['stand'][1] - m['want_y']) <= 1, (r['key'], m)
        assert m['dirs'] == 4 and m['idle_distinct'] >= 2 and m['walk_distinct'] >= 4
    # no name of any other game, server or client in the tool, the table, the picks rows and the map
    for path in (P.TABLE, P.SUMS, P.MAP, os.path.join(HERE, 'gen_pixellab_monsters.py')):
        assert os.path.exists(path)

    # ---- every rule has a case
    good = [row('a', 3), row('b', 4, tiles='3x3', disp='-32:0', float=1, idle=8, idle_ms=200)]
    sums = {'3': 'x', '4': 'y'}
    assert P.problems(good, sums, first=3, spec=None) == []
    for bad, text in (
            ([row('a', 3), row('b', 6)], 'must be 4'),
            ([row('a', 3), row('a', 4)], 'on two rows'),
            ([row('a', 3, tiles='1x2'), row('b', 4)], 'not NxN'),
            ([row('a', 3, tiles='5x5'), row('b', 4)], 'not NxN'),
            ([row('a', 3, disp='16:0'), row('b', 4)], 'displacement'),
            ([row('a', 3, disp='0-16'), row('b', 4)], 'displacement'),
            ([row('a', 3, idle=2, idle_ms=300), row('b', 4)], 'idle phases'),
            ([row('a', 3, idle_ms=200), row('b', 4)], 'idle phases'),
            ([row('a', 3, walk=6), row('b', 4)], 'the walk is 8 phases'),
            ([row('a', 3, walk_ms=83), row('b', 4)], 'the walk is 8 phases'),
            ([row('a', 3, src='xyz'), row('b', 4)], 'not 12 hex'),
            ([row('a', 3, pl='xyz'), row('b', 4)], 'not 8 hex'),
            ([row('a', 3, pixels='many'), row('b', 4)], 'opaque pixels'),
            ([row('a', 3, tier=5), row('b', 4)], 'tier 5'),
            ([row('a', 3, role='boss'), row('b', 4)], 'role boss'),
            ([row('a', 3, float=2), row('b', 4)], 'float 2'),
            ([row('a', 3, name=' '), row('b', 4)], 'no name'),
            ([row('a', 3, lean='0.25'), row('b', 4)], 'lean 0.25'),
            ([row('hound', 3, lean='0.10'), row('b', 4)], 'lean 0.10'),
            ([row('a', 3, lean=''), row('b', 4)], 'lean ')):
        p = P.problems(bad, sums, first=3, spec=None)
        assert any(text in x for x in p), (text, p)
    assert any('name other outfits' in x for x in P.problems(good, {'3': 'x'}, first=3, spec=None))
    assert any('not SPEC' in x for x in P.problems(good, sums, first=3))
    old = {'M1': 10, 'M2': 11, 'M3': 12}
    levels = {'M1': 5, 'M2': 40, 'M3': 600}
    tb = [row('a', 3, tier=1), row('b', 4, tier=2)]
    assert P.map_problems(tb, [('M1', 3, 1), ('M2', 4, 2)], old, levels, first=3) == []
    for bad, text in (([('M1', 3, 1), ('M2', 5, 3)], 'not a row'), ([('M1', 3, 2), ('M2', 4, 2)], 'not a row'),
                      ([('M1', 3, 1), ('M2', 3, 1), ('M3', 4, 2)], 'no two hunt monsters share'),
                      ([('M1', 3, 1), ('M1', 4, 2)], 'on two rows'), ([('M1', 3, 1), ('M9', 4, 2)], 'no monster file'),
                      ([('M1', 3, 1)], 'worn by no monster'), ([('M1', 3, 1), ('M3', 4, 2)], 'band of tier 2'),
                      ([('M2', 3, 1), ('M1', 4, 2)], 'band of tier')):
        p = P.map_problems(tb, bad, old, levels, first=3)
        assert any(text in x for x in p), (text, p)
    assert any('not a hunt monster' in x for x in P.map_problems(tb, [('M1', 3, 1), ('M2', 4, 2)], {**old}, {'M1': 5}, first=3))
    assert P.map_text([('M1', 10, 3531)]) == 'monster,look,new_look\nM1,10,3531\n'
    assert P.old_looks({'M1': 5}, {'M1': 9, 'M2': 7}) == {'M1': 5, 'M2': 7}, 'our file wins over the pool'
    assert P.tiles_of_text('2x2') == 2 and P.tiles_of_text('3x3') == 3 and P.tiles_of_text('2x3') is None and P.tiles_of_text('9x9') is None
    assert P.disp_of_text('-16:0') == (-16, 0) and P.disp_of_text('-32:-13') == (-32, -13) and P.disp_of_text('x') is None
    assert P.flags_of(row(disp='-16:0')) == (bytes([25, 0xF0, 0xFF, 0, 0]), {'displacement': (65520, 0)})
    assert P.flags_of(row(disp='-32:-13'))[1] == {'displacement': (65504, 65523)}
    assert P.tile_origin(2, (-16, 0)) == (16, 32) and P.tile_origin(3, (-32, -13)) == (32, 51), 'the creature\'s tile on the canvas'
    assert P.pair_ok(2, 3) is None and 'Malgrath' in P.pair_ok(1, 3) and 'needs 2' in P.pair_ok(7, 3)

    # ---- the pictures
    a = np.zeros((2, 2, 4), np.uint8)
    a[0, 0] = (9, 9, 9, 127)
    a[0, 1] = (9, 9, 9, 128)
    c = P.cut(a)
    assert tuple(c[0, 0]) == (0, 0, 0, 0) and tuple(c[0, 1]) == (9, 9, 9, 255), 'alpha cut at 128'
    assert list(__import__('itertools').islice(P.near(-16), 5)) == [-16, -15, -17, -14, -18]

    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, 'dl')
        figure(src, 'small', 48, (10, 4, 20, 24), tag='01')                 # 20 x 28 px: a 1x1 outfit
        figure(src, 'mid', 64, (8, 8, 36, 40), tag='07')                    # 36 x 44 px: 2x2
        figure(src, 't3_wide', 80, (4, 20, 70, 40), idle=8, tag='02')       # 70 wide: 3x3
        figure(src, 't4_tall', 96, (30, 4, 24, 80), idle=4, tag='03')       # 24 x 88 px: 3x3
        figure(src, 'floaty', 64, (10, 10, 30, 30), idle=8, tag='04')
        figure(src, 'huge', 160, (2, 2, 140, 100), tag='05')                # longer than 128 px: no canvas
        figure(src, 'softy', 48, (10, 4, 20, 24), soft=True, tag='06')

        # load_source: pictures in order, alpha cut, one size; the four directions with as many pictures
        fr, size = P.load_source(os.path.join(src, 'small'))
        assert size == (48, 48) and len(fr[('idle', 2)]) == 4 and len(fr[('walk', 1)]) == 8
        assert all(set(np.unique(a[..., 3])) <= {0, 255} for lst in fr.values() for a in lst)
        assert P.source_dir('wide', [src]).endswith('t3_wide') and P.source_dir('tall', [src]).endswith('t4_tall')
        try:
            P.source_dir('nothing', [src])
        except SystemExit as e:
            assert 'no download of nothing' in str(e)
        else:
            raise AssertionError('a missing download was taken')
        assert P.pl_id(os.path.join(src, 'small')) == '01000000'
        bad = os.path.join(tmp, 'bad')
        figure(bad, 'k', 48, (10, 4, 20, 24))
        shutil.rmtree(os.path.join(bad, 'k', 'idle', 'east'))
        try:
            P.load_source(os.path.join(bad, 'k'))
        except SystemExit as e:
            assert 'no pictures' in str(e)
        else:
            raise AssertionError('a missing direction was taken')
        os.remove(os.path.join(bad, 'k', 'walk', 'north', '03.png'))
        shutil.rmtree(os.path.join(bad, 'k', 'idle'))
        shutil.copytree(os.path.join(src, 'small', 'idle'), os.path.join(bad, 'k', 'idle'))
        try:
            P.load_source(os.path.join(bad, 'k'))
        except SystemExit as e:
            assert 'different numbers' in str(e)
        else:
            raise AssertionError('uneven directions were taken')

        # fit: the smallest canvas, one shift, the standing point on the tile
        for key, fl, tiles in (('small', 0, 1), ('mid', 0, 2), ('wide', 0, 3), ('tall', 0, 3), ('floaty', 1, 2)):
            frames, _s = P.load_source(P.source_dir(key, [src]))
            n, disp, shift = P.fit(frames, bool(fl))
            assert n == tiles, (key, n)
            placed = P.place_checked(frames, n, shift)
            c = 32 * n
            ox, oy = P.tile_origin(n, disp)
            assert all(a.shape == (c, c, 4) for lst in placed.values() for a in lst)
            assert sum(P.opaque(a) for lst in placed.values() for a in lst) == sum(P.opaque(a) for lst in frames.values() for a in lst), 'no pixel lost'
            for k2, lst in frames.items():      # every picture moved by the same shift, colour for colour
                for s, d in zip(lst, placed[k2]):
                    ys, xs = np.nonzero(s[..., 3])
                    assert (d[ys + shift[1], xs + shift[0]] == s[ys, xs]).all()
            sx, sy = P.stand_placed(placed, n, disp, bool(fl))
            assert abs(sx - P.TX) <= 1 and abs(sy - P.expected_y(placed, n, disp, bool(fl))) <= 1, (key, sx, sy)
            assert disp[0] <= 0 and (key != 'mid' or disp[0] <= -(16 * n - 16) + 8)
            if fl:
                assert abs(sy - P.FLOAT_LOW) <= 1 and P.hang_of(placed, n, disp) <= 0, 'a floater has its lowest pixel on its row'
            else:
                assert P.hang_of(placed, n, disp) <= P.HANG
        # a figure that does not fit 4 x 4 tiles (128 px) is refused, never sampled down
        try:
            P.fit(P.load_source(P.source_dir('huge', [src]))[0], False)
        except ValueError as e:
            assert 'does not fit' in str(e)
        else:
            raise AssertionError('a figure longer than the biggest canvas was taken')
        # a figure whose legs hang low stands higher by the rest, one on the point by the rule otherwise
        low = {(k, d): [a.copy() for a in v] for (k, d), v in P.load_source(P.source_dir('mid', [src]))[0].items()}
        for v in low.values():
            for a in v:
                a[56:64, 24:30, :3] = 50
                a[56:64, 24:30, 3] = 255        # a tail that reaches far below the feet
        n, disp, shift = P.fit(low, False)
        placed = P.place_checked(low, n, shift)
        assert P.hang_of(placed, n, disp) == P.HANG and P.stand_placed(placed, n, disp, False)[1] < P.TY[n], 'the figure stands higher'

        # make / art: the table row, the sheet, the sums, written to a folder of ours
        P.SPEC, P.SHEETS, P.TABLE, P.SUMS = ((spec('small', 'Small One'), spec('mid', 'Mid One', 2), spec('wide', 'Wide One', 3, 'chaser'),
                                                spec('tall', 'Tall One', 4, 'hunter'), spec('floaty', 'Floaty One', 2, 'sniper', 1)),
                                               os.path.join(tmp, 'sheets'), os.path.join(tmp, 'm.csv'), os.path.join(tmp, 'm.sums'))
        P.KEYS = tuple(s[0] for s in P.SPEC)
        # the synthetic blocks stand straight: the lean rule is tested on its own below (LOW_BODY with no floor lets them through)
        P.SHEAR, P.REDRAW_PENDING, P.LOW_BODY = (), (), {k: -99.0 for k in P.KEYS}
        assert P.art([src], True) == []
        t2 = P.rows()
        assert [r['key'] for r in t2] == list(P.KEYS) and [r['new'] for r in t2] == ['3531', '3532', '3533', '3534', '3535']
        assert [(r['tiles'], r['idle'], r['idle_ms'], r['walk'], r['walk_ms']) for r in t2] == [
            ('1x1', '4', '300', '8', '100'), ('2x2', '4', '300', '8', '100'), ('3x3', '8', '200', '8', '100'), ('3x3', '4', '300', '8', '100'),
            ('2x2', '8', '200', '8', '100')]
        assert [r['pl'] for r in t2] == ['01000000', '07000000', '02000000', '03000000', '04000000']
        assert P.problems(t2, P.read_sums(), spec=P.SPEC) == [], P.problems(t2, P.read_sums(), spec=P.SPEC)
        assert P.check_sheets(t2, P.read_sums()) == [], P.check_sheets(t2, P.read_sums())
        assert P.table_text(t2) == open(P.TABLE, encoding='utf-8', newline='').read()
        # the sheet's cells are the pictures of the placed outfit: column per direction in the engine order, rows idle then walk
        r0 = t2[0]
        _a, cells = P.read_sheet(r0)
        frames, _s = P.load_source(P.source_dir('small', [src]))
        n0, d0, sh0 = P.fit(frames, False)
        assert (r0['disp'], r0['tiles']) == ('%d:%d' % d0, '%dx%d' % (n0, n0))
        pl0 = P.place_checked(frames, n0, sh0)
        assert all((cells[(g, d)][i] == pl0[(g, ('north', 'east', 'south', 'west').index(['north', 'east', 'south', 'west'][d]))][i]).all()
                   for (g, d) in cells for i in range(len(cells[(g, d)])))
        # a changed sheet, a soft pixel, a copied direction, a wrong standing point, a wrong count are caught
        bad_root = os.path.join(tmp, 'badsheets')
        shutil.copytree(P.SHEETS, bad_root)
        a0 = np.array(Image.open(os.path.join(bad_root, 'small.png')).convert('RGBA'))
        a0[40, 40, 3] = 100
        Image.fromarray(a0).save(os.path.join(bad_root, 'small.png'))
        p = P.check_sheets(t2, P.read_sums(), root=bad_root)
        assert any('soft alpha' in x for x in p) and any('not the one of the table' in x for x in p), p
        a1 = np.array(Image.open(os.path.join(P.SHEETS, 'wide.png')).convert('RGBA'))
        c1 = 96
        a1[:, 2 * c1:3 * c1] = a1[:, 0:c1]       # the south column is the north one
        Image.fromarray(a1).save(os.path.join(bad_root, 'wide.png'))
        assert any('different standing pictures' in x for x in P.check_sheets(t2, P.read_sums(), root=bad_root)), 'a copied direction'
        a2 = np.array(Image.open(os.path.join(P.SHEETS, 'tall.png')).convert('RGBA'))
        a2 = np.roll(a2, 6, axis=0)
        Image.fromarray(a2).save(os.path.join(bad_root, 'tall.png'))
        assert any('stands on tile point' in x for x in P.check_sheets(t2, P.read_sums(), root=bad_root)), 'a moved figure'
        assert any('opaque pixels on the sheet' in x for x in P.check_sheets([dict(t2[4], pixels='5')] + [], P.read_sums(), root=P.SHEETS)), 'a wrong count'
        shutil.rmtree(bad_root)
        # a figure with soft alpha is cut: the soft row is gone, the count is the cut one
        figure(src, 'softy', 48, (10, 4, 20, 24), soft=True, tag='06') if not os.path.isdir(os.path.join(src, 'softy')) else None
        frames_s, _s = P.load_source(os.path.join(src, 'softy'))
        assert all(set(np.unique(a[..., 3])) <= {0, 255} for lst in frames_s.values() for a in lst)

        # ---- the pair: build, read back, live
        odat, ospr = WT.input_pair(tmp)
        out = os.path.join(tmp, 'out')
        lines = []
        new = P.build(odat, ospr, out, table=t2, first=3, log=lines.append)
        # 3 + the table: the pair has 2 outfits, the first new outfit is 3
        assert new == [3, 4, 5, 6, 7] and any('append-only guard passed' in x for x in lines), lines
        t3 = [dict(r, new=str(3 + i)) for i, r in enumerate(t2)]
        sums = {}
        for r in t3:
            _a, cells = P.read_sheet(r)
            sums[r['new']] = P.digest_of(r, cells)
        assert P.problems(t3, sums, first=3, spec=P.SPEC) == []
        paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
        d, sp = Dat(paths[0]), Spr(paths[1])
        assert len(d.outfits) == 7
        g0, g1 = parse_body(d, d.outfit(5))
        assert (g0.gtype, g0.phases, g1.gtype, g1.phases) == (0, 8, 1, 8) and (g0.w, g0.h, g0.layers, g1.w, g1.h) == (3, 3, 1, 3, 3)
        assert g0.anim == (0, 0, 0, (200, 200) * 8) and g1.anim == (0, 0, 0, (100, 100) * 8)
        for r in t3:
            assert dict(d.outfit(int(r['new'])).flags) == P.flags_of(r)[1], 'the displacement is the only flag'
        quiet = dict(log=lambda *_: None)
        assert P.live(*paths, table=t3, sums=sums, first=3, **quiet) == []
        assert P.live(*paths, table=t3, sums={**sums, '4': '0' * 64}, first=3, **quiet)
        assert P.live(odat, ospr, table=t3, sums=sums, first=3, **quiet), 'a pair without the outfits'
        assert P.live(*paths, table=[dict(t3[0], idle='8')] + t3[1:], sums=sums, first=3, **quiet), 'another phase count'
        assert P.live(*paths, table=[dict(t3[0], tiles='3x3')] + t3[1:], sums=sums, first=3, **quiet), 'another size'
        assert P.live(*paths, table=[dict(t3[0], disp='-32:-32')] + t3[1:], sums=sums, first=3, **quiet), 'another displacement'
        for bad, text in ((dict(t3[1], idle_ms='200'), 'do not last 200 ms'), (dict(t3[1], pixels=str(int(t3[1]['pixels']) + 1)), 'opaque pixels')):
            p = P.live(*paths, table=[t3[0], bad] + t3[2:], sums=sums, first=3, **quiet)
            assert any(text in x for x in p), (text, p)
        # a pair built from other sheets: a picture differs from the sheet
        other = os.path.join(tmp, 'other_sheets')
        shutil.copytree(P.SHEETS, other)
        a3 = np.array(Image.open(os.path.join(other, 'floaty.png')).convert('RGBA'))
        ys, xs = np.nonzero(a3[..., 3])
        a3[ys[0], xs[0], :3] ^= 1
        Image.fromarray(a3).save(os.path.join(other, 'floaty.png'))
        assert any('not the one of the sheet' in x for x in P.live(*paths, table=t3, sums=sums, first=3, root=other, **quiet))
        # wrong input pairs and an existing output folder are refused, one that ends an outfit early is told about Malgrath
        for args, kw, text in (((odat, ospr, out), dict(table=t3, first=3), 'exists'),
                               ((odat, ospr, os.path.join(tmp, 'o2')), dict(table=t3, first=9), 'needs 8'),
                               ((odat, ospr, os.path.join(tmp, 'o3')), dict(table=t3, first=4), 'Malgrath'),
                               ((odat, ospr, os.path.join(tmp, 'o4')), dict(table=t3[:1] + [dict(t3[1], key='nope')], first=3), 'sheet')):
            try:
                P.build(*args, log=lambda *_: None, **kw)
            except (SystemExit, FileNotFoundError) as e:
                assert text in str(e) or text == 'sheet', (text, str(e))
            else:
                raise AssertionError('build did not refuse: ' + text)
        # a second build gives the same bytes
        out2 = os.path.join(tmp, 'again')
        P.build(odat, ospr, out2, table=t3, first=3, log=lambda *_: None)
        assert open(paths[0], 'rb').read() == open(os.path.join(out2, 'Tibia.dat'), 'rb').read()
        assert open(paths[1], 'rb').read() == open(os.path.join(out2, 'Tibia.spr'), 'rb').read()

        # ---- O728: the shear of a SHEAR key when built, the lean rule, the guard, the in-place rewrite of a pair, the old form in live
        P.LOW_BODY = {k: -99.0 for k in P.KEYS if k != 'tall'}
        rt = t3[3]                                          # the tall one: 24 x 88 px, upright
        _a, cells = P.read_sheet(rt)
        assert any('the game\'s angle' in x for x in P.lean_rule(rt, cells)), 'an upright look fails the lean rule'
        P.REDRAW_PENDING = ('tall',)
        assert P.lean_rule(rt, cells) == [], 'a pending key waits'
        P.REDRAW_PENDING, P.SHEAR = (), ('tall',)
        r2, c2, p = P.built(rt, cells)
        ln = L.leans(c2)
        assert p == [] and r2['lean'] == '0.25' and L.LEAN[0] <= ln[2] <= L.LEAN[1], (p, r2['lean'], ln)
        assert sum(P.opaque(a) for v in c2.values() for a in v) == int(rt['pixels']), 'the shear keeps every pixel'
        assert P.problems([dict(r2, new='3')], {'3': 'x'}, first=3, spec=None) == []
        lean_cells = {k: [L.shear(a, 0.3) for a in v] for k, v in cells.items()}
        assert P.leaned(rt, lean_cells)[0]['lean'] == '0.00', 'the guard: a sheet that leans already is left as drawn'
        P.REDRAW_PENDING = ('tall',)
        assert any('REDRAW_PENDING' in x for x in P.lean_rule(r2, c2)), 'a pending key that leans now is named'
        P.REDRAW_PENDING = ()
        # the pair built before (upright) is the old form; the table now builds the tall one sheared
        old_csv, old_sums = os.path.join(tmp, 'old.csv'), os.path.join(tmp, 'old.sums')
        open(old_csv, 'w', encoding='utf-8', newline='').write(P.table_text([dict(r, lean='0.00') for r in t3]))
        open(old_sums, 'w', encoding='utf-8').write(P.sums_text(sums))
        P.OLD_TABLE, P.OLD_SUMS = old_csv, old_sums
        t4 = [P.built(r, P.read_sheet(r)[1])[0] for r in t3]
        sums4 = {r['new']: P.digest_of(r, P.built(r, P.read_sheet(r)[1])[1]) for r in t3}
        assert sums4['6'] != sums['6'] and all(sums4[k] == sums[k] for k in sums if k != '6')
        assert P.live(*paths, table=t4, sums=sums4, first=3, accept_old=True, **quiet) == [], 'the old form is let through'
        assert P.live(*paths, table=t4, sums=sums4, first=3, accept_old=False, **quiet), 'and held once the pair is meant to carry the lean'
        rel = os.path.join(tmp, 'relook')
        assert P.relook(*paths, rel, table=t4, sums=sums4, **quiet) == [6]
        rpaths = (os.path.join(rel, 'Tibia.dat'), os.path.join(rel, 'Tibia.spr'))
        assert P.live(*rpaths, table=t4, sums=sums4, first=3, accept_old=False, **quiet) == []
        rd, od = Dat(rpaths[0]), Dat(paths[0])
        assert all(rd.data[od.outfits[i].raw[0]:od.outfits[i].raw[1]] == od.data[od.outfits[i].raw[0]:od.outfits[i].raw[1]]
                   for i in range(5)), 'only outfit 6 changed'
        assert P.relook(*rpaths, os.path.join(tmp, 'relook2'), table=t4, sums=sums4, **quiet) == [] and \
            not os.path.exists(os.path.join(tmp, 'relook2')), 'a second run writes nothing'
        open(old_sums, 'w', encoding='utf-8').write(P.sums_text({**sums, '4': '0' * 64}))
        try:
            P.relook(*paths, os.path.join(tmp, 'relook3'), table=t4, sums={**sums4, '4': '0' * 64}, **quiet)
        except SystemExit as e:
            assert 'neither' in str(e), e
        else:
            raise AssertionError('relook took an outfit of another pair')

        # ---- O728: an oblique PixelLab download (rotations, a v3 walk of 9 frames with the standing frame_000, metadata.json)
        drop = os.path.join(tmp, 'drop', 'tall', 'Idle')
        rng = np.random.default_rng(7)
        for k, d in enumerate(('south', 'east', 'north', 'west')):
            os.makedirs(os.path.join(drop, 'rotations'), exist_ok=True)
            os.makedirs(os.path.join(drop, 'animations', 'walkv3-%d' % k, d))
            for i in range(-1, 9):
                a = np.zeros((80, 80, 4), np.uint8)
                a[20:60, 30 + k:44 + k, :3] = rng.integers(40, 250, (40, 14, 3)) if i < 0 else 100 + 10 * k
                a[20:60, 30 + k:44 + k, 3] = 255
                a[60:66, 32 + k + (i % 4):35 + k + (i % 4), :3] = 70
                a[60:66, 32 + k + (i % 4):35 + k + (i % 4), 3] = 255
                a[60:66, 40 + k - (i % 4):43 + k - (i % 4), :3] = 70
                a[60:66, 40 + k - (i % 4):43 + k - (i % 4), 3] = 255
                a = L.shear(a, 0.45, 65)
                if i < 0:
                    Image.fromarray(a, 'RGBA').save(os.path.join(drop, 'rotations', d + '.png'))
                else:
                    a = np.roll(a, 2, axis=1)                   # drawn 2 px off: the import puts it back on the feet
                    Image.fromarray(a, 'RGBA').save(os.path.join(drop, 'animations', 'walkv3-%d' % k, d, 'frame_%03d.png' % i))
        open(os.path.join(tmp, 'drop', 'tall', 'metadata.json'), 'w').write(
            '{"states": [{"character": {"id": "abcdef12-0000-4000-8000-000000000000"}}]}')
        dr = L.read_drop(os.path.join(tmp, 'drop', 'tall'))
        assert [len(dr['walk'][d]) for d in L.DROP_DIRS] == [8] * 4 and [len(dr['idle'][d]) for d in L.DROP_DIRS] == [4] * 4
        assert len({a.tobytes() for a in dr['idle']['south']}) >= 2, 'the breath moves'
        assert all(abs(L.feet_point(a)[0] - L.feet_point(dr['stand'][d])[0]) <= 1.5 for d in L.DROP_DIRS for a in dr['walk'][d]), \
            'the walk is back on the standing feet'
        r5, pl5, _f = P.make_drop(P.SPEC[3], 3534, os.path.join(tmp, 'drop', 'tall'))
        assert (r5['tiles'], r5['idle'], r5['idle_ms'], r5['walk'], r5['lean'], r5['pl']) == ('3x3', '4', '300', '8', '0.00', 'abcdef12'), r5
        P.SHEAR = ()
        assert P.sheet_problems(r5, pl5) == [] and P.lean_rule(r5, pl5) == [], (P.sheet_problems(r5, pl5), L.lean_text(pl5))
    assert P.main(['build', 'a', 'b']) == 2 and P.main(['art']) == 2 and P.main(['nothing']) == 2
    print('gen_pixellab_monsters_test: ok')


if __name__ == '__main__':
    main()
