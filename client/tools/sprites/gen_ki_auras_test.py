#!/usr/bin/env python3
"""Tests of gen_ki_auras.py (O577): the committed table, sums and sheets against the rules (the sheets are drawn by script and
committed; CI needs no pair), the drawing (loop, layers, palette, hard alpha), each figure rule, and `build` / `live` on a small
synthetic input pair. Needs numpy and Pillow (the fx venv of CI).

    python3 -I client/tools/sprites/gen_ki_auras_test.py
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_ki_auras as K  # noqa: E402
import gen_fun_costumes as F  # noqa: E402
import gen_fun_costumes_test as FT  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from import_outfits import parse_body  # noqa: E402


def colours(a):
    return {tuple(int(v) for v in px[:3]) for px in a.reshape(-1, 4) if px[3]}


def main():
    # ------------------------------------------------------------ the committed table, sums and sheets
    t = K.rows()
    assert K.problems() == [], K.problems()
    assert K.FIRST_NEW == 3525 == F.FIRST_NEW + 14 and len(t) == 2
    assert [int(r['new']) for r in t] == [3525, 3526] and [r['key'] for r in t] == ['ki_gold', 'ki_blaze']
    assert [r['name'] for r in t] == ['Golden Ki', 'Crimson Blaze']
    assert all(r['kind'] == 'aura' and int(r['tiles']) == 3 and int(r['layers']) == 2 and int(r['phases']) == 24 and r['flags'] == '' for r in t)
    assert len(F.rows()) == 14 and int(F.rows()[-1]['new']) == 3524, 'the ids follow the last outfit of gen_fun_costumes.py'
    assert set(K.read_sums()) == {'3525', '3526'} and all(len(v) == 64 for v in K.read_sums().values())
    assert K.art_check() == [], K.art_check()
    assert K.sums_text() == open(K.SUMS, encoding='utf-8').read(), 'sums are not what the sheets give'
    # each rule has a case
    s = K.read_sums()
    base = [dict(r) for r in t]

    def bad(mutate, text):
        rows_ = [dict(r) for r in base]
        mutate(rows_)
        p = K.problems(rows_, s)
        assert any(text in x for x in p), (text, p)
    bad(lambda r: r[1].update(new='3599'), 'must be 3526')
    bad(lambda r: r[1].update(key=r[0]['key']), 'two rows')
    bad(lambda r: r[0].update(key='ki_green'), 'no style')
    bad(lambda r: r[0].update(tiles='2'), 'an aura here is 3x3')
    bad(lambda r: r[0].update(layers='1'), 'an aura here is 3x3')
    bad(lambda r: r[0].update(phases='12'), 'an aura here is 3x3')
    bad(lambda r: r[0].update(flags='moth'), 'no flags')
    bad(lambda r: r[0].update(ms='10'), 'outside 40..200')
    bad(lambda r: r[0].update(name=' '), 'no name')
    assert any('no row' in x for x in K.problems(base, {k: v for k, v in s.items() if k != '3525'}))
    assert any('not in the table' in x for x in K.problems(base, {**s, '4000': 'x' * 64}))

    # ------------------------------------------------------------ the drawing
    for key, st in K.STYLES.items():
        fr = K.frames_of_key(key)
        assert len(fr) == 48 and all(a.shape == (96, 96, 4) and a.dtype == np.uint8 for a in fr.values())
        for a in fr.values():
            assert set(np.unique(a[..., 3])) <= {0, 255}, 'hard alpha'
        allowed = set(st['pal']) | set(st['ring'])
        used = set()
        for a in fr.values():
            used |= colours(a)
        assert used <= allowed, (key, sorted(used - allowed))
        assert len(used) >= 8, 'the flames use the colour bands'
        again = K.draw(key, 7)
        assert np.array_equal(again[0], fr[(0, 7)]) and np.array_equal(again[1], fr[(1, 7)]), 'drawn the same every time'
        # the loop closes: phase 24 is phase 0 (up to a few pixels at a threshold)
        for layer in (0, 1):
            wrap = K.draw(key, K.PHASES)[layer]
            assert int((wrap != fr[(layer, 0)]).any(axis=2).sum()) <= K.ART_TOL, (key, layer)
        # the ground ring is in layer 0 (under the body), its front rim at the bottom, the front flames are layer 1
        assert fr[(0, 0)][int(K.CENTRE[1] + K.RING_R), int(K.CENTRE[0])][3] == 255, 'the ring is on layer 0'
        front = fr[(1, 0)][..., 3] > 0
        assert front[int(K.CENTRE[1]):].sum() > front[:int(K.CENTRE[1])].sum(), 'layer 1 is mostly the front half (below the feet point)'
        assert (fr[(0, 0)][..., 3] > 0)[:int(K.CENTRE[1] - 8)].sum() > 150, 'layer 0 holds the back flames above the head'
        assert (fr[(1, 0)][..., 3] > 0).sum() > 300 and (fr[(0, 0)][..., 3] > 0).sum() > 1500
        assert K.figure_problems({'key': key}, fr) == [], K.figure_problems({'key': key}, fr)
    gold, blaze = K.frames_of_key('ki_gold'), K.frames_of_key('ki_blaze')
    assert not np.array_equal(gold[(0, 3)][..., 3] > 0, blaze[(0, 3)][..., 3] > 0), 'the two silhouettes differ'
    # the tongues: tall at the sides, short at the front and the back
    tg = K.make_tongues(K.STYLES['ki_gold'])
    assert len(tg) == K.STYLES['ki_gold']['n'] + K.STYLES['ki_gold']['n2']
    side = [x['h0'] for x in tg if abs(x['bx'] - K.CENTRE[0]) > 20 and x['by'] > 30]
    mid = [x['h0'] for x in tg if abs(x['bx'] - K.CENTRE[0]) < 8]
    assert sum(side) / len(side) > sum(mid) / len(mid), 'tall at the sides'
    assert all(x['by'] - x['h0'] >= 2 for x in tg), 'every tongue fits under the top of the cell'

    # ------------------------------------------------------------ each figure rule has a case
    r0 = t[0]
    fr = {k: a.copy() for k, a in K.frames_of_key('ki_gold').items()}

    def broken(mutate, text):
        f2 = {k: a.copy() for k, a in fr.items()}
        mutate(f2)
        p = K.figure_problems(r0, f2)
        assert any(text in x for x in p), (text, p)
    broken(lambda f: f[(0, 5)].__setitem__((10, 10, 3), 90), 'soft alpha')
    broken(lambda f: [f.__setitem__((1, p), np.zeros((96, 96, 4), np.uint8)) for p in range(24)], 'layer 1 is empty')
    broken(lambda f: f[(0, 2)].__setitem__((0, 40, 3), 255), 'touches the edge')
    broken(lambda f: [f.__setitem__((l, p), np.roll(f[(l, p)], 12, axis=1)) for l in (0, 1) for p in range(24)], 'centre x')
    broken(lambda f: [f.__setitem__((l, p), np.roll(f[(l, p)], 5, axis=0)) for l in (0, 1) for p in range(24)], 'the ring ends on row')
    broken(lambda f: [f.__setitem__((l, p), f[(l, 0)]) for l in (0, 1) for p in range(24)], 'would not animate')
    broken(lambda f: [f.__setitem__((l, 23), K.draw('ki_blaze', 9)[l]) for l in (0, 1)], 'the loop jumps')

    with tempfile.TemporaryDirectory() as tmp:
        # ------------------------------------------------------------ the sheets: write, read, compare with a redraw
        sheets = os.path.join(tmp, 'sheets')
        os.makedirs(sheets)
        odat, ospr = FT.input_pair(tmp)
        od, osp = Dat(odat), Spr(ospr)
        saved = (K.SHEETS, F.row_specs)
        K.SHEETS = sheets
        try:
            table = [dict(r0, new='4'), dict(t[1], new='5')]
            for r in table:
                K.write_sheet(r['key'], K.frames_of_key(r['key']))
            back = K.read_sheet(table[0])
            assert set(back) == set(fr) and all(np.array_equal(back[k], K.clean(fr[k])) for k in fr), 'sheet round trip'
            assert K.art_check() == [], K.art_check()
            f2 = K.read_sheet(table[1])
            K.write_sheet('ki_blaze', {k: (np.roll(a, 3, axis=1) if k == (0, 4) else a) for k, a in f2.items()})
            assert any('differs from draw()' in x for x in K.art_check()), 'a sheet that is not the drawing is found'
            K.write_sheet('ki_blaze', f2)

            # -------------------------------------------------------- build and live on a synthetic pair
            out = os.path.join(tmp, 'out')
            lines = []
            ids = K.build(odat, ospr, out, table=table, first=4, log=lines.append)
            assert ids == [4, 5], ids
            assert F.row_specs is saved[1], 'the build puts gen_fun_costumes.row_specs back'
            nd, nsp = Dat(os.path.join(out, 'Tibia.dat')), Spr(os.path.join(out, 'Tibia.spr'))
            assert len(od.outfits) == 3 and len(nd.outfits) == 5 and nd.counts[2:] == od.counts[2:], nd.counts
            assert nd.data[8:od.outfits[-1].raw[1]] == od.data[8:od.outfits[-1].raw[1]], 'old outfits changed'
            for i in range(1, osp.count + 1):
                x, y = osp.sprite(i), nsp.sprite(i)
                assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), i
            for nid in (4, 5):
                g = parse_body(nd, nd.outfit(nid))
                assert [(a.gtype, a.w, a.h, a.exact, a.layers, a.px, a.py, a.pz, a.phases) for a in g] == [(0, 3, 3, 96, 2, 4, 1, 1, 24)], g
                assert g[0].anim == (0, 0, 0, tuple([80] * 48)), g[0].anim
                assert len(g[0].sprites) == 24 * 4 * 2 * 9 and not nd.outfit(nid).flags
                # the four directions share their sprite records
                assert len(set(g[0].sprites)) < len(g[0].sprites) / 3
                # slot order: phase, direction, layer, row, column: layer 1 of phase 3 is the front half
                from import_outfits import frame
                fr_back = K.read_sheet(table[nid - 4])
                for ph in (0, 3, 17):
                    for layer in (0, 1):
                        for d in (0, 2):
                            assert np.array_equal(K.clean(frame(g[0], nsp, d, 0, 0, ph, layer)), K.clean(fr_back[(layer, ph)])), (nid, ph, layer, d)
            assert any('verified' in x for x in lines) and any('append-only guard passed' in x for x in lines), lines
            good = {r['new']: F.digest(nd, nsp, int(r['new'])) for r in table}
            paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
            assert K.live(*paths, table=table, sums=good, first=4, log=lambda *_: None) == []
            assert K.live(*paths, table=table, sums={**good, '4': '0' * 64}, first=4, log=lambda *_: None)
            assert K.live(odat, ospr, table=table, sums=good, first=4, log=lambda *_: None)
            assert all(good[r['new']] == F.spec_digest(K.row_specs(r)) for r in table), 'the digest of the sheet is the digest of the pair'
            # refusals: the output exists, the input has other outfits than the first id says
            for args, kw, text in (((odat, ospr, out), dict(table=table, first=4), 'exists'),
                                   ((odat, ospr, os.path.join(tmp, 'o2')), dict(table=table, first=9), 'wrong input pair')):
                try:
                    K.build(*args, log=lambda *_: None, **kw)
                except SystemExit as e:
                    assert text in str(e), (text, e)
                else:
                    raise AssertionError('build did not refuse: ' + text)
            assert F.row_specs is saved[1], 'a refused build puts it back too'
            # build71 refuses an existing output or half-way folder before it reads the input
            os.makedirs(os.path.join(tmp, 'p72.half'))
            try:
                K.build71(odat, ospr, os.path.join(tmp, 'p72'), log=lambda *_: None)
            except SystemExit as e:
                assert 'exists' in str(e)
            else:
                raise AssertionError('build71 did not refuse')
        finally:
            K.SHEETS = saved[0]
            F.row_specs = saved[1]
    assert K.main(['build', 'a', 'b']) == 1   # wrong arguments print the help
    assert K.main(['check']) == 0
    print('gen_ki_auras_test: OK')


if __name__ == '__main__':
    main()
