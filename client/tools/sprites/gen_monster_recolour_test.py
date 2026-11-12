#!/usr/bin/env python3
"""Test of gen_monster_recolour.py (O529, O531): python3 -I client/tools/sprites/gen_monster_recolour_test.py

The pixel transform, the committed table and its two id files, and `build` / `live` on a small synthetic pair 68 (three outfits, one
with a second frame group, the copies are appended after them, every old byte stays, the copy of a sprite is the recoloured
source, a sprite shared by two outfits is recoloured once per row, wrong input pairs and an existing output folder are refused).
Needs numpy and Pillow (the fx venv of CI)."""
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_monster_recolour as G  # noqa: E402
import check_pair_test as T  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from import_outfits import parse_body  # noqa: E402


def px(r, g, b, a=255):
    return np.array([[[r, g, b, a]]], dtype=np.uint8)


def row(m, sh=10, look='1', mode='hue', hue='0'):
    return {'look': look, 'hue_shift': str(sh), 'monster': m, 'mode': mode, 'theme': 'x', 'source_hue': hue, 'source_sat': '1'}


def pixels(rgba):
    """{index: (r, g, b, a)} of the opaque pixels of a 32 x 32 RGBA array, for the synthetic spr writer"""
    flat = rgba.reshape(1024, 4)
    return {i: tuple(int(v) for v in flat[i]) for i in range(1024) if flat[i][3]}


def synthetic(tmp):
    """a pair of 3 outfits and 1 effect: outfit 1 (1x1, 4 directions, idle + 2 phase walk), outfit 2 (shares one sprite with 1,
    carries a displacement flag), outfit 3 (a blank slot and a mask-less art). 10 sprites."""
    recs = [T.record({0: (255, 0, 0, 255), 1: (200, 100, 0, 255), 50: (0, 0, 255, 128)}),    # 1
            T.record({5: (0, 255, 0, 255), 6: (120, 120, 120, 255)}),                          # 2
            T.record({9: (255, 255, 0, 255)}),                                                  # 3
            T.record({20: (10, 200, 200, 255)}),                                                # 4
            None,                                                                               # 5 empty slot
            T.record({300: (90, 30, 160, 255)}),                                                # 6
            T.record({400: (255, 0, 255, 255), 401: (255, 0, 255, 255)}),                       # 7
            T.record({70: (30, 30, 30, 255)}),                                                  # 8
            T.record({80: (255, 128, 0, 255)}),                                                 # 9
            T.record({90: (0, 128, 255, 255)})]                                                 # 10
    o1 = T.entry(b'', [T.group([1, 2, 3, 4], px=4, gtype=0),
                       T.group([1, 2, 3, 4, 6, 7, 6, 7], px=4, phases=2, gtype=1, anim=(1, 0, 0, [100, 140, 100, 140]))], outfit=True)
    o2 = T.entry(bytes([25]) + struct.pack('<hh', 8, 8), [T.group([1, 8, 9, 10], px=4, gtype=1)], outfit=True)
    o3 = T.entry(b'', [T.group([5, 6, 7, 5], px=4, gtype=1)], outfit=True)
    eff = T.entry(b'', [T.group([8, 9], phases=2)])
    dat = T.dat_bytes([], [o1, o2, o3], [eff], [])
    d = os.path.join(tmp, 'in')
    os.makedirs(d)
    open(os.path.join(d, 'Tibia.dat'), 'wb').write(dat)
    open(os.path.join(d, 'Tibia.spr'), 'wb').write(T.spr_bytes(recs))
    return os.path.join(d, 'Tibia.dat'), os.path.join(d, 'Tibia.spr')


def main():
    # red +120 = green, +240 = blue; alpha stays; a grey pixel has no hue and stays in mode hue
    assert tuple(G.recolour(px(255, 0, 0), 120)[0, 0]) == (0, 255, 0, 255)
    assert tuple(G.recolour(px(255, 0, 0), 240)[0, 0]) == (0, 0, 255, 255)
    assert tuple(G.recolour(px(120, 120, 120, 200), 90)[0, 0]) == (120, 120, 120, 200)
    o = G.recolour(px(200, 100, 0), 180)[0, 0]   # value and saturation stay
    assert max(o[:3]) == 200 and min(o[:3]) == 0, o
    t = G.recolour(px(100, 100, 100), 120, 'tint')[0, 0]   # grey takes the target hue at the tint saturation, value kept
    assert t[1] == 100 and t[0] == t[2] and abs(int(t[0]) - round(100 * (1 - G.TINT_SAT))) <= 1, t
    assert G.TINT_SAT >= 0.6 and G.FAR == 120
    # the committed table
    assert G.problems() == [], G.problems()
    assert G.problems([row('A', 400)], {})
    assert any('less than' in p for p in G.problems([row('A', 10), row('B', 20)], {'A': 1, 'B': 1}))
    assert G.problems([row('A', 120), row('B', 240)], {'A': 1, 'B': 1}) == []   # source 0, copies 120 and 240: 3 colours, 120 apart
    assert any('less than 120' in p for p in G.problems([row('A', 100), row('B', 240)], {'A': 1, 'B': 1}))   # 100 is 100 from the source
    assert G.problems([row('A', 180)], {'A': 1}) == [] and any('less than' in p for p in G.problems([row('A', 100)], {'A': 1}))
    assert any('needs mode tint' in p for p in G.problems([dict(row('A', 180), source_sat='0.2')], {'A': 1}))   # a low saturation source tints
    assert G.problems([dict(row('A', 180, mode='tint'), source_sat='0.2')], {'A': 1}) == []
    five = [row('R%d' % i, 60 * (i + 1), look='5') for i in range(5)]   # 6 colours: 60 apart is the best there is
    assert G.problems(five, {r['monster']: 5 for r in five}) == [], G.problems(five, {r['monster']: 5 for r in five})
    # every committed look: the rule, and a removed row leaves the rest buildable (ids follow the remaining rows)
    committed = G.rows()
    sub = committed[3:20] + committed[30:]
    assert [r[2] for r in G.id_rows(sub)] == list(range(3371, 3371 + len(sub)))
    assert any('two rows' in p for p in G.problems([row('A', 100), row('A', 200)], {'A': 1}))
    assert any('monster file says 2' in p for p in G.problems([row('A', 100)], {'A': 2}))   # the table's look is the file's
    # the ids: the row at line n is outfit 3371 + n, both files are in sync with the table
    ids = G.id_rows()
    assert [r[2] for r in ids] == list(range(3371, 3371 + len(G.rows()))) and len(ids) == len(G.rows()), ids[:2]
    assert G.FIRST_NEW == G.OUTFITS_68 + 1 == 3371
    assert G.write_ids(check=True) == [], G.write_ids(check=True)
    a, b = G.id_texts([row('A', 10), row('B', 20, look='7')], first=100)
    assert a == 'monster,look,new_look,hue_shift,mode\nA,1,100,10,hue\nB,7,101,20,hue\n' and b == 'monster,look,new_look\nA,1,100\nB,7,101\n', (a, b)

    # build and live on a synthetic pair
    with tempfile.TemporaryDirectory() as tmp:
        dat, spr = synthetic(tmp)
        table = [row('Alpha', 120, look='1'), row('Beta', 200, look='1'), row('Gamma', 90, look='2', mode='tint'),
                 row('Delta', 300, look='3')]
        out = os.path.join(tmp, 'out')
        lines = []
        ids = G.build(dat, spr, out, table=table, first=4, log=lines.append)
        assert ids == [4, 5, 6, 7], ids
        od, ospr = Dat(dat), Spr(spr)
        nd, nspr = Dat(os.path.join(out, 'Tibia.dat')), Spr(os.path.join(out, 'Tibia.spr'))
        assert len(od.outfits) == 3 and len(nd.outfits) == 7 and nd.counts[2:] == od.counts[2:], nd.counts
        assert nd.data[8:od.outfits[-1].raw[1]] == od.data[8:od.outfits[-1].raw[1]], 'old outfits changed'
        assert ospr.count == 10 and nspr.count > 10
        for i in range(1, 11):   # every old sprite stays at its id
            x, y = ospr.sprite(i), nspr.sprite(i)
            assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), i
        # copy 4 = outfit 1 with hue +120: same groups and animator, each sprite recoloured
        for new, src, sh, mode in ((4, 1, 120, 'hue'), (5, 1, 200, 'hue'), (6, 2, 90, 'tint'), (7, 3, 300, 'hue')):
            a, b = parse_body(od, od.outfit(src)), parse_body(nd, nd.outfit(new))
            assert len(a) == len(b)
            assert nd.data[nd.outfit(new).raw[0]:nd.outfit(new).attr_end] == od.data[od.outfit(src).raw[0]:od.outfit(src).attr_end], 'flags'
            for g, h in zip(a, b):
                assert (g.gtype, g.w, g.h, g.layers, g.px, g.py, g.phases, g.anim) == (h.gtype, h.w, h.h, h.layers, h.px, h.py, h.phases, h.anim)
                for s0, s1 in zip(g.sprites, h.sprites):
                    x, y = ospr.sprite(s0), nspr.sprite(s1)
                    if x is None or not x[:, :, 3].any():
                        assert y is None, (new, s0, s1)
                    else:
                        assert np.array_equal(G.recolour(x, sh, mode), y), (new, s0, s1)
        # the shared sprite 1 is two different copies (Alpha +120, Beta +200), one record each
        assert parse_body(nd, nd.outfit(4))[0].sprites[0] != parse_body(nd, nd.outfit(5))[0].sprites[0]
        assert any('verified' in l for l in lines) and any('append-only guard passed' in l for l in lines), lines
        assert G.live(*(os.path.join(out, n) for n in ('Tibia.dat', 'Tibia.spr')), table=table, first=4, log=lambda *_: None) == []
        # live finds a wrong table (another shift) and a pair without the copies
        bad = G.live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'), table=[dict(table[0], hue_shift='121')] + table[1:],
                     first=4, log=lambda *_: None)
        assert bad and 'not the recoloured' in bad[0], bad
        assert G.live(dat, spr, table=table, first=4, log=lambda *_: None)
        # refusals: the output exists, the input has other outfits than the first id says, the input md5 is not pair 68's
        for args, kw, text in (((dat, spr, out), dict(table=table, first=4), 'exists'),
                               ((dat, spr, os.path.join(tmp, 'o2')), dict(table=table, first=9), 'wrong input pair'),
                               ((dat, spr, os.path.join(tmp, 'o3')), dict(table=table, first=4, expect_md5='0' * 32), 'wrong input pair')):
            try:
                G.build(*args, log=lambda *_: None, **kw)
            except SystemExit as e:
                assert text in str(e), (text, e)
            else:
                raise AssertionError('build did not refuse: ' + text)
        assert not os.path.exists(os.path.join(tmp, 'o2')) and not os.path.exists(os.path.join(tmp, 'o3.tmp'))
    assert G.main(['build']) == 1   # the arguments are DAT SPR OUT_DIR
    print('gen_monster_recolour_test: OK')


if __name__ == '__main__':
    main()
