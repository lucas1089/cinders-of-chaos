#!/usr/bin/env python3
"""Test of gen_donor_outfits.py (O538): python3 -I client/tools/sprites/gen_donor_outfits_test.py

The committed table and sums against the rules, and `select` / `sums` / `build` / `live` on small synthetic pairs: a donor with
three outfits (an idle group and a walk group of 3 phases each, one with a flag, one with a blank slot), an input pair that holds
one of them already and one of their pictures; the picks are appended after the input's outfits, every donor slot reads back
pixel identical, a picture the input has takes its sprite id, wrong input pairs and an existing output folder are refused.
No donor files needed. Needs numpy and Pillow (the fx venv of CI)."""
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_donor_outfits as G  # noqa: E402
import check_pair_test as T  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from import_outfits import parse_body  # noqa: E402


def rec(i, n=1, a=255):
    """a record of n opaque pixels of colours that depend on i (every i another picture)"""
    return T.record({(i * 7 + k) % 1000: ((i * 5 + k * 13) % 256, (i * 11) % 256, (k * 29 + i) % 256, a) for k in range(n)})


def outfit(first, flags=b'', blank=False):
    """idle group (4 directions, 1 phase) and walk group (4 directions, 3 phases) starting at sprite id first"""
    idle = [first + k for k in range(4)]
    walk = [0 if (blank and k == 5) else first + 4 + k for k in range(12)]
    return T.entry(flags, [T.group(idle, px=4, gtype=0), T.group(walk, px=4, phases=3, gtype=1)], outfit=True)


def pairs(tmp):
    """(ours dat, ours spr, donor dat, donor spr): the donor has outfits 1-3 over sprites 1-48; ours holds donor outfit 3 as its outfit 2"""
    drecs = [rec(i, 1 + i % 3) for i in range(1, 49)]
    ddat = T.dat_bytes([], [outfit(1), outfit(17, bytes([25]) + struct.pack('<hh', 8, 8), blank=True), outfit(33)],
                       [T.entry(b'', [T.group([1, 2], phases=2)])], [])
    # ours: sprite 1 is a picture of donor outfit 1 (the reuse), outfit 2 is donor outfit 3 byte for byte
    orecs = [drecs[0], rec(200)] + [rec(300 + i) for i in range(4)] + [None] * 2 + list(drecs[32:48]) + [rec(400)]
    # ours outfit 1: sprites 1..16 as their own (1 is the shared picture); outfit 2: the 16 pictures of donor outfit 3
    o1 = T.entry(b'', [T.group([1, 2, 3, 4], px=4, gtype=0),
                       T.group([2, 3, 4, 5, 6, 3, 4, 5, 6, 3, 4, 5], px=4, phases=3, gtype=1)], outfit=True)
    base = 9
    o2 = T.entry(b'', [T.group([base + k for k in range(4)], px=4, gtype=0), T.group([base + 4 + k for k in range(12)], px=4, phases=3, gtype=1)],
                 outfit=True)
    odat = T.dat_bytes([], [o1, o2], [T.entry(b'', [T.group([1, 2], phases=2)])], [])
    d = os.path.join(tmp, 'in')
    os.makedirs(d)
    paths = []
    for name, blob in (('ours.dat', odat), ('ours.spr', T.spr_bytes(orecs)), ('donor.dat', ddat), ('donor.spr', T.spr_bytes(drecs))):
        p = os.path.join(d, name)
        open(p, 'wb').write(blob)
        paths.append(p)
    return paths


def row(donor, new, kind='beast', size='1x1', walk='3', colours='600'):
    return {'donor': str(donor), 'new': str(new), 'kind': kind, 'size': size, 'walk': walk, 'colours': colours}


def main():
    # the committed table and sums
    committed = G.rows()
    assert G.problems() == [], G.problems()
    assert [int(r['new']) for r in committed] == list(range(3406, 3406 + len(committed))) and G.FIRST_NEW == 3406 == G.OUTFITS_69 + 1
    assert all(r['kind'] in G.KIND_NAMES and int(r['colours']) >= 500 and int(r['walk']) >= 3 for r in committed)
    assert all(int(x) <= 2 for r in committed for x in r['size'].split('x')), 'a pick above 2x2'
    # the owner's exclusion (2026-11-12, "Remove 3411 to 3415"): five donors, no row, and a table that has one fails
    assert sorted(G.OWNER_EXCLUDED) == [2227, 2228, 2229, 2230, 2231] and len(committed) == 28
    assert not {int(r['donor']) for r in committed} & set(G.OWNER_EXCLUDED)
    assert any('struck by the owner' in x for x in G.problems(committed + [row(2227, 3434, kind='beast')], G.read_sums()))
    sums = G.read_sums()
    assert set(sums) == {int(r['donor']) for r in committed} and all(len(v) == 64 for v in sums.values())
    # every rule has a case
    s = {1: 'x', 2: 'y'}
    ok = [row(1, 11), row(2, 12)]
    saved = dict(G.KINDS)
    G.KINDS.update({1: 'beast', 2: 'beast'})
    try:
        assert G.problems(ok, s, first=11) == [], G.problems(ok, s, first=11)
    finally:
        G.KINDS.clear()
        G.KINDS.update(saved)
    for bad, text in (([row(1, 11), row(2, 14)], 'must be 12'), ([row(1, 11), row(1, 12)], 'two rows'),
                      ([row(1, 11, kind='dog'), row(2, 12)], 'is not one of'), ([row(1, 11, size='3x3'), row(2, 12)], 'above 2x2'),
                      ([row(1, 11, walk='2'), row(2, 12)], 'walk frames'), ([row(1, 11, colours='499'), row(2, 12)], 'polished'),
                      ([row(1, 11, size='big'), row(2, 12)], 'not WxH')):
        saved = dict(G.KINDS)
        G.KINDS.update({1: bad[0]['kind'], 2: 'beast'})
        try:
            p = G.problems(bad, s, first=11)
        finally:
            G.KINDS.clear()
            G.KINDS.update(saved)
        assert any(text in x for x in p), (text, p)
    G.KINDS.update({1: 'beast', 2: 'beast'})
    try:
        assert any('other outfits' in x for x in G.problems(ok, {1: 'x'}, first=11))
        assert any('KINDS says' in x for x in G.problems([row(1, 11, kind='undead'), row(2, 12)], s, first=11))
    finally:
        del G.KINDS[1], G.KINDS[2]

    # the monster map: picks.csv rows of family donor against the outfit table and the pool
    tbl = [row(1, 11), row(2, 12)]
    picks, pool = [('A', 11, 1), ('B', 12, 2)], {'A': 100, 'B': 200}
    assert G.map_rows(picks, pool) == [('A', 100, 11), ('B', 200, 12)]
    assert G.map_text(G.map_rows(picks, pool)) == 'monster,look,new_look\nA,100,11\nB,200,12\n'
    assert G.map_problems(tbl, picks, pool) == []
    for bp, bpool, text in (([('A', 11, 1), ('B', 12, 3)], pool, 'not a row'), ([('A', 11, 1), ('B', 11, 1)], pool, 'two monsters'),
                            ([('A', 11, 1), ('A', 12, 2)], pool, 'two rows'), (picks, {'A': 100}, 'not in the bounty pool'),
                            ([('A', 11, 1)], pool, 'no monster')):
        assert any(text in x for x in G.map_problems(tbl, bp, bpool)), (text, G.map_problems(tbl, bp, bpool))
    assert G.write_map(check=True) == [] and G.map_problems() == []
    assert len(G.picks_rows()) == len(committed) and set(G.pool_looks()) >= {m for m, _n, _d in G.picks_rows()}
    assert [r[2] for r in G.map_rows()] == [int(r['new']) for r in sorted(committed, key=lambda r: [p[1] for p in G.picks_rows()].index(int(r['new'])))]

    with tempfile.TemporaryDirectory() as tmp:
        odat, ospr, ddat, dspr = pairs(tmp)
        d, sp = Dat(ddat), Spr(dspr)
        od, osp = Dat(odat), Spr(ospr)
        # measure, the pick rule, a pick equal to an outfit of the input pair, an equal pair of picks
        m = G.measure(d, sp, 1)
        assert (m['w'], m['h'], m['layers'], m['dirs'], m['walk']) == (1, 1, 1, 4, 3) and m['colours'] >= 3, m
        assert G.digest(d, sp, 3) == G.digest(od, osp, 2) and G.digest(d, sp, 1) != G.digest(d, sp, 2)
        saved_k, saved_c = dict(G.KINDS), G.MIN_COLOURS
        G.KINDS.clear()
        G.KINDS.update({1: 'beast', 2: 'demon', 3: 'undead'})
        G.MIN_COLOURS = 3
        try:
            lines = []
            picks = G.select(ddat, dspr, (odat, ospr), log=lines.append)
            assert [p[0] for p in picks] == [1, 2], picks     # 3 is outfit 2 of the input pair
            assert any('identical to outfit 2' in x for x in lines), lines
            assert sorted(p[0] for p in G.select(ddat, dspr)) == [1, 2, 3]   # without the pair nothing is dropped
            G.MIN_COLOURS = 10 ** 6
            assert G.select(ddat, dspr, log=lambda *_: None) == []
            G.MIN_COLOURS = 3
            G.MAX_TILES = 0
            assert G.select(ddat, dspr, log=lambda *_: None) == []
        finally:
            G.MAX_TILES = 2
            G.KINDS.clear()
            G.KINDS.update(saved_k)
            G.MIN_COLOURS = saved_c
        # sums of a few donor outfits
        sm = G.donor_sums(ddat, dspr, [1, 2])
        assert sorted(sm) == [1, 2] and G.sums_text(sm).splitlines()[1].split()[0] == '1'

        table = [row(2, 3, 'undead'), row(1, 4, 'beast')]
        out = os.path.join(tmp, 'out')
        lines = []
        ids = G.build(odat, ospr, out, ddat, dspr, table=table, first=3, log=lines.append)
        assert ids == [3, 4], ids
        nd, nsp = Dat(os.path.join(out, 'Tibia.dat')), Spr(os.path.join(out, 'Tibia.spr'))
        assert len(od.outfits) == 2 and len(nd.outfits) == 4 and nd.counts[2:] == od.counts[2:], nd.counts
        assert nd.data[8:od.outfits[-1].raw[1]] == od.data[8:od.outfits[-1].raw[1]], 'old outfits changed'
        assert osp.count == 25 and nsp.count > 25
        for i in range(1, 26):   # every old sprite stays at its id
            x, y = osp.sprite(i), nsp.sprite(i)
            assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), i
        # new outfit 3 is donor outfit 2 (flag and a blank slot kept), 4 is donor outfit 1; picture 1 is the input's sprite 1
        assert nd.data[nd.outfit(3).raw[0]:nd.outfit(3).attr_end] == d.data[d.outfit(2).raw[0]:d.outfit(2).attr_end]
        for new, src in ((3, 2), (4, 1)):
            a, b = parse_body(d, d.outfit(src)), parse_body(nd, nd.outfit(new))
            assert len(a) == len(b) == 2
            for g, h in zip(a, b):
                assert (g.gtype, g.w, g.h, g.layers, g.px, g.py, g.phases, g.anim) == (h.gtype, h.w, h.h, h.layers, h.px, h.py, h.phases, h.anim)
                for s0, s1 in zip(g.sprites, h.sprites):
                    x, y = sp.sprite(s0), nsp.sprite(s1)
                    if x is None or not x[:, :, 3].any():
                        assert y is None, (new, s0, s1)
                    else:
                        assert np.array_equal(x, y), (new, s0, s1)
        assert parse_body(nd, nd.outfit(4))[0].sprites[0] == 1, 'a picture the input has keeps its sprite id'
        assert parse_body(nd, nd.outfit(3))[1].sprites[5] == 0, 'the blank slot stays blank'
        assert G.digest(nd, nsp, 3) == G.digest(d, sp, 2) and G.digest(nd, nsp, 4) == G.digest(d, sp, 1)
        assert any('verified' in x for x in lines) and any('append-only guard passed' in x for x in lines), lines
        # live: right sums pass, a wrong one and a short pair fail
        good = {2: G.digest(d, sp, 2), 1: G.digest(d, sp, 1)}
        paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
        assert G.live(*paths, table=table, sums=good, first=3, log=lambda *_: None) == []
        assert G.live(*paths, table=table, sums={**good, 1: '0' * 64}, first=3, log=lambda *_: None)
        assert G.live(odat, ospr, table=table, sums=good, first=3, log=lambda *_: None)
        # refusals: the output exists, the input has other outfits than the first id says, the input md5 is not pair 69's
        for args, kw, text in (((odat, ospr, out, ddat, dspr), dict(table=table, first=3), 'exists'),
                               ((odat, ospr, os.path.join(tmp, 'o2'), ddat, dspr), dict(table=table, first=9), 'wrong input pair'),
                               ((odat, ospr, os.path.join(tmp, 'o3'), ddat, dspr), dict(table=table, first=3, expect_md5='0' * 32), 'wrong input pair'),
                               ((odat, ospr, os.path.join(tmp, 'o4'), ddat, dspr), dict(table=[row(77, 3)], first=3), 'no outfit 77')):
            try:
                G.build(*args, log=lambda *_: None, **kw)
            except SystemExit as e:
                assert text in str(e), (text, e)
            else:
                raise AssertionError('build did not refuse: ' + text)
        assert not os.path.exists(os.path.join(tmp, 'o2')) and not os.path.exists(os.path.join(tmp, 'o3.tmp'))
    assert G.main(['build', 'a', 'b', 'c']) == 1   # --donor is needed
    assert G.main(['check']) == 0
    print('gen_donor_outfits_test: OK')


if __name__ == '__main__':
    main()
