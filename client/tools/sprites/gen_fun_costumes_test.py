#!/usr/bin/env python3
"""Tests of gen_fun_costumes.py (O566): the committed table, sums and sheets against the rules (the sheets are the art we made
with PixelLab, committed; CI needs no pair), the placement of downloads on synthetic pictures, the drawn Rune Seal ring, and `build` /
`live` on a small synthetic input pair. Needs numpy and Pillow (the fx venv of CI).

    python3 -I client/tools/sprites/gen_fun_costumes_test.py
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_fun_costumes as G  # noqa: E402
import check_pair_test as T  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from import_outfits import parse_body  # noqa: E402


def png(path, a):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(a.astype(np.uint8), 'RGBA').save(path)


def figure(cv, top, left, h, w, k):
    a = np.zeros((cv, cv, 4), np.uint8)
    a[top:top + h, left:left + w] = (40 + k * 7 % 200, 90, 150 + k % 90, 255)
    a[top:top + 1, left:left + w, 3] = 255
    return a


def downloads(root, key, cv=56, walk=6, top=8, left=20, h=40, w=16, soft=False):
    """a fake PixelLab folder: rot/DIRECTION.png and walk/DIRECTION/frame_NNN.png"""
    for di, d in enumerate(G.DIR_NAMES):
        a = figure(cv, top, left, h, w, di)
        if soft:
            a[top, left:left + w, 3] = 90
        png(os.path.join(root, key, 'rot', d + '.png'), a)
        for ph in range(walk):
            png(os.path.join(root, key, 'walk', d, 'frame_%03d.png' % ph), figure(cv, top + ph % 2, left + (ph % 3), h - 1, w, di + ph))


def rec(i, n=1, a=255):
    return T.record({(i * 7 + k) % 1000: ((i * 5 + k * 13) % 256, (i * 11) % 256, (k * 29 + i) % 256, a) for k in range(n)})


def input_pair(tmp):
    """a pair of 3 outfits: 1 and 2 any, 3 a one tile moth-like look with animateAlways (the flags a `moth` row copies from look FLAG_LOOKS)"""
    recs = [rec(i, 1 + i % 3) for i in range(1, 9)]
    o = T.entry(b'', [T.group([1, 2, 3, 4], px=4, gtype=0)], outfit=True)
    o3 = T.entry(bytes([28]), [T.group([1, 2, 3, 4], px=4, gtype=0)], outfit=True)   # animateAlways
    dat = T.dat_bytes([], [o, o, o3], [T.entry(b'', [T.group([1, 2], phases=2)])], [])
    d = os.path.join(tmp, 'in')
    os.makedirs(d)
    paths = []
    for name, blob in (('ours.dat', dat), ('ours.spr', T.spr_bytes(recs))):
        p = os.path.join(d, name)
        open(p, 'wb').write(blob)
        paths.append(p)
    return paths


def main():
    # ------------------------------------------------------------ the committed table, sums and sheets
    t = G.rows()
    assert G.problems() == [], G.problems()
    assert G.FIRST_NEW == 3511 == G.OUTFITS_71 + 1 and len(t) == 14
    assert [int(r['new']) for r in t] == list(range(3511, 3525))
    kinds = [r['kind'] for r in t]
    assert kinds == ['costume'] * 12 + ['pet', 'aura'], kinds
    assert all(int(r['walk']) >= G.MIN_WALK and int(r['idle']) >= 2 and int(r['dirs']) == 4 and r['flags'] == '' and r['src'] for r in t[:12])
    assert int(t[12]['walk']) >= G.MIN_PET_PHASES and t[12]['flags'] == 'moth' and int(t[12]['tiles']) == 1
    assert int(t[13]['walk']) >= G.MIN_AURA_PHASES and int(t[13]['tiles']) == 3 and int(t[13]['dirs']) == 1 and t[13]['src'] == 'script'
    assert set(G.read_sums()) == {r['new'] for r in t} and all(len(v) == 64 for v in G.read_sums().values())
    assert G.art_check() == [], G.art_check()
    assert G.sums_text() == open(G.SUMS, encoding='utf-8').read(), 'sums are not what the sheets give'
    # each rule has a case
    s = G.read_sums()
    base = [dict(r) for r in t]

    def bad(mutate, text):
        rows_ = [dict(r) for r in base]
        mutate(rows_)
        p = G.problems(rows_, s)
        assert any(text in x for x in p), (text, p)
    bad(lambda r: r[1].update(new='3599'), 'must be 3512')
    bad(lambda r: r[1].update(key=r[0]['key']), 'two rows')
    bad(lambda r: r[0].update(kind='hat'), 'is not one of')
    bad(lambda r: r[0].update(tiles='1'), 'tiles, the row says 1')
    bad(lambda r: r[0].update(walk='3'), 'costume has 4 directions')
    bad(lambda r: r[12].update(walk='4'), 'pet has 4 directions')
    bad(lambda r: r[13].update(walk='6'), 'aura has one drawn direction')
    bad(lambda r: r[0].update(flags='wings'), 'flags wings')
    bad(lambda r: r[0].update(ms='10'), 'too fast')
    bad(lambda r: r[0].update(name=' '), 'no name')
    assert any('no row' in x for x in G.problems(base, {k: v for k, v in s.items() if k != '3511'}))
    assert any('not in the table' in x for x in G.problems(base, {**s, '4000': 'x' * 64}))

    # ------------------------------------------------------------ the ring: round, animated, a loop, hard alpha
    ring = G.ring_frames()
    assert len(ring) == G.RING_PHASES == 24
    assert len({a.tobytes() for a in ring.values()}) == 24, 'every phase differs'
    r0, r24 = G.draw_ring(0), G.draw_ring(G.RING_PHASES)
    assert np.array_equal(r0, r24), 'the last phase leads back into the first'
    assert np.array_equal(G.draw_ring(5), G.draw_ring(5)), 'drawn the same every time'
    for a in ring.values():
        assert set(np.unique(a[..., 3])) <= {0, 255}
    x0, y0, x1, y1 = G.union_box(list(ring.values()))
    assert 0.9 <= (x1 - x0 + 1) / float(y1 - y0 + 1) <= 1.1 and (x1 - x0 + 1) >= 60, (x0, y0, x1, y1)

    with tempfile.TemporaryDirectory() as tmp:
        # ------------------------------------------------------------ placing downloads
        src = os.path.join(tmp, 'src')
        downloads(src, 'box')
        fr, n = G.place_costume(src, 'box')
        assert n == 6 and len(fr) == 4 * (2 + 6) and all(a.shape == (64, 64, 4) for a in fr.values())
        x0, y0, x1, y1 = G.union_box(list(fr.values()))
        assert y1 == G.FOOT_ROW, 'feet on row 63'
        assert abs((x0 + x1) / 2.0 - G.MID_COL) <= 1.0, (x0, x1)
        assert not np.array_equal(fr[('idle', 2, 0)], fr[('idle', 2, 1)]), 'the idle pair differs'
        assert np.array_equal(fr[('idle', 2, 1)][:-1], fr[('idle', 2, 0)][1:]), 'the second idle picture is the first one pixel up'
        # no west pictures: the east ones mirrored
        downloads(src, 'nowest')
        import shutil
        shutil.rmtree(os.path.join(src, 'nowest', 'walk', 'west'))
        os.remove(os.path.join(src, 'nowest', 'rot', 'west.png'))
        nf, nn = G.place_costume(src, 'nowest')
        assert nn == 6 and len(nf) == 4 * 8
        base = os.path.join(src, 'nowest')
        assert np.array_equal(G.load_rot(base, 'west'), G.load_rot(base, 'east')[:, ::-1])
        assert [a.tobytes() for a in G.load_walk(base, 'west')] == [a[:, ::-1].tobytes() for a in G.load_walk(base, 'east')]
        assert len(G.source_files(src, 'nowest')) == 3 + 3 * 6, 'only the files that are there are summed'
        downloads(src, 'soft', soft=True)
        a = G.binary_alpha(G.load_png(os.path.join(src, 'soft', 'rot', 'north.png')))
        assert set(np.unique(a[..., 3])) <= {0, 255}, 'hard alpha'
        for key, kw, text in (('short', dict(walk=3), 'walk phases per direction'), ('huge', dict(cv=90, top=0, left=0, h=80, w=80), 'does not fit')):
            downloads(src, key, **kw)
            try:
                G.place_costume(src, key)
            except ValueError as e:
                assert text in str(e), (text, e)
            else:
                raise AssertionError('place_costume did not refuse ' + key)
        downloads(src, 'moth', cv=34, walk=13, top=8, left=8, h=16, w=18)
        pf, pn = G.place_pet(src, 'moth')
        assert pn == 13 and all(a.shape == (32, 32, 4) for a in pf.values()) and len(pf) == 4 * 13
        downloads(src, 'bigmoth', cv=48, walk=13, top=2, left=2, h=40, w=40)
        try:
            G.place_pet(src, 'bigmoth')
        except ValueError as e:
            assert 'does not fit 32 px' in str(e)
        else:
            raise AssertionError('place_pet did not refuse a big moth')
        assert len(G.src_sum(src, 'box')) == 12 and G.src_sum(src, 'box') != G.src_sum(src, 'short')

        # ------------------------------------------------------------ build and live on a synthetic pair
        odat, ospr = input_pair(tmp)
        od, osp = Dat(odat), Spr(ospr)
        sheets = os.path.join(tmp, 'sheets')
        os.makedirs(sheets)
        saved = (G.SHEETS, G.OUTFITS_71, G.FLAG_LOOKS)
        G.SHEETS = sheets
        G.FLAG_LOOKS = {'moth': 3}
        try:
            costume = {'new': '4', 'key': 'box', 'name': 'Box', 'kind': 'costume', 'tiles': '2', 'dirs': '4', 'idle': '2', 'walk': '6',
                       'flags': '', 'ms': '110', 'src': 'x'}
            pet = {'new': '5', 'key': 'moth', 'name': 'Moth', 'kind': 'pet', 'tiles': '1', 'dirs': '4', 'idle': '0', 'walk': '13',
                   'flags': 'moth', 'ms': '90', 'src': 'x'}
            aura = {'new': '6', 'key': 'ring', 'name': 'Ring', 'kind': 'aura', 'tiles': '3', 'dirs': '1', 'idle': '0', 'walk': '24',
                    'flags': '', 'ms': '100', 'src': 'script'}
            G.write_sheet(costume, fr)
            G.write_sheet(pet, pf)
            G.write_sheet(aura, ring)
            back = G.read_sheet(costume)
            assert set(back) == set(fr) and all(np.array_equal(back[k], G.clean(fr[k])) for k in fr), 'sheet round trip'
            table = [costume, pet, aura]
            out = os.path.join(tmp, 'out')
            lines = []
            ids = G.build(odat, ospr, out, table=table, first=4, log=lines.append)
            assert ids == [4, 5, 6], ids
            nd, nsp = Dat(os.path.join(out, 'Tibia.dat')), Spr(os.path.join(out, 'Tibia.spr'))
            assert len(od.outfits) == 3 and len(nd.outfits) == 6 and nd.counts[2:] == od.counts[2:], nd.counts
            assert nd.data[8:od.outfits[-1].raw[1]] == od.data[8:od.outfits[-1].raw[1]], 'old outfits changed'
            assert nsp.count > osp.count
            for i in range(1, osp.count + 1):
                x, y = osp.sprite(i), nsp.sprite(i)
                assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), i
            g1 = parse_body(nd, nd.outfit(4))
            assert [(g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.phases) for g in g1] == [(0, 2, 2, 64, 1, 4, 2), (1, 2, 2, 64, 1, 4, 6)]
            assert g1[0].anim == (0, 0, 0, tuple([G.IDLE_MS] * 4)) and g1[1].anim == (0, 0, 0, tuple([110] * 12)), (g1[0].anim, g1[1].anim)
            assert nd.outfit(5).flags == {'animateAlways': True} and not nd.outfit(4).flags, nd.outfit(5).flags
            g2 = parse_body(nd, nd.outfit(5))
            assert [(g.gtype, g.w, g.h, g.exact, g.phases) for g in g2] == [(1, 1, 1, 32, 13)]
            g3 = parse_body(nd, nd.outfit(6))
            assert [(g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.phases) for g in g3] == [(0, 3, 3, 96, 1, 4, 24)] and not nd.outfit(6).flags
            assert len(g3[0].sprites) == 24 * 4 * 9
            # the same ring picture in all four directions shares its sprite records
            assert len(set(g3[0].sprites)) < len(g3[0].sprites) / 3
            assert any('verified' in x for x in lines) and any('append-only guard passed' in x for x in lines), lines
            good = {r['new']: G.digest(nd, nsp, int(r['new'])) for r in table}
            paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
            assert G.live(*paths, table=table, sums=good, first=4, log=lambda *_: None) == []
            assert G.live(*paths, table=table, sums={**good, '4': '0' * 64}, first=4, log=lambda *_: None)
            assert G.live(odat, ospr, table=table, sums=good, first=4, log=lambda *_: None)
            assert all(good[r['new']] == G.spec_digest(G.row_specs(r)) for r in table), 'the digest of the sheet is the digest of the pair'
            # refusals: the output exists, the input has other outfits than the first id says, the input md5 is wrong
            for args, kw, text in (((odat, ospr, out), dict(table=table, first=4), 'exists'),
                                   ((odat, ospr, os.path.join(tmp, 'o2')), dict(table=table, first=9), 'wrong input pair'),
                                   ((odat, ospr, os.path.join(tmp, 'o3')), dict(table=table, first=4, expect_md5='0' * 32), 'wrong input pair')):
                try:
                    G.build(*args, log=lambda *_: None, **kw)
                except SystemExit as e:
                    assert text in str(e), (text, e)
                else:
                    raise AssertionError('build did not refuse: ' + text)
            assert not os.path.exists(os.path.join(tmp, 'o2')) and not os.path.exists(os.path.join(tmp, 'o3.tmp'))
        finally:
            G.SHEETS, G.OUTFITS_71, G.FLAG_LOOKS = saved
    assert G.main(['build', 'a', 'b']) == 1   # wrong arguments print the help
    assert G.main(['check']) == 0
    print('gen_fun_costumes_test: OK')


if __name__ == '__main__':
    main()
