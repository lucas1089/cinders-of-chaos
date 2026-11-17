#!/usr/bin/env python3
"""Test of gen_creature_outfits.py (O608, after O605): python3 -I client/tools/sprites/gen_creature_outfits_test.py

The committed table, sums, picks rows and monster map against the rules, every rule with a failing case, and `discover` / `measure` /
`build` / `live` on synthetic packs drawn here (frame folders of the four directions on a 256 px canvas: a creature with a walk
folder, one with a move folder and a run folder that is not read, one with no walk at all whose box is longer than 128 px, one
with a direction of few frames) and a small synthetic input pair: the frame pick (evenly spaced, the loop closed), the hard alpha cut,
the size (4x4 up to 128 px, else 5x5, pixel for pixel; sampled down only past 160 px), the placement (lowest pixel on the last row,
the box in the middle of the canvas), the displacement that puts the middle over the creature's tile, the outfit shape (idle group,
walk group, phases, durations from 12 pictures a second), the idle rule, the outfits appended after the input's, every slot reading
back as drawn, wrong input pairs and an existing output folder refused. No pack files and no real pair needed. Needs numpy and
Pillow (the fx venv of CI). Nothing drawn here is art of any pack."""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_creature_outfits as G  # noqa: E402
import gen_wst_outfits as W  # noqa: E402
import gen_wst_outfits_test as WT  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from import_outfits import parse_body  # noqa: E402


def creature(root, name, anims, box=(70, 70, 120, 120), soft=False):
    """a folder NAME with animation folders {folder name: {direction: frames}} of 256 px frames: a random figure in `box` (x, y, w, h)
    that moves a little from frame to frame"""
    rng = np.random.default_rng(sum(map(ord, name)) + 11)
    x, y, w, h = box
    for anim, dirs in anims.items():
        for k, (d, n) in enumerate(dirs.items()):
            p = os.path.join(root, name, 'Animations', anim, d)
            os.makedirs(p)
            for i in range(n):
                a = np.zeros((256, 256, 4), np.uint8)
                # 2 px blocks of random colour, cold and warm ones; the figure bobs one block every second frame
                col = rng.integers(0, 256, (h // 2, w // 2, 3)).astype(np.uint8)
                col = np.repeat(np.repeat(col, 2, 0), 2, 1)
                top = y + 2 * (i % 2)
                a[top:top + h, x + 2 * k:x + 2 * k + w, :3] = col
                a[top:top + h, x + 2 * k:x + 2 * k + w, 3] = 255
                if soft:
                    a[top, x + 2 * k:x + 2 * k + w, 3] = 100      # a soft top row: cut away
                Image.fromarray(a, 'RGBA').save(os.path.join(p, 'frame_%03d.png' % i))
    return os.path.join(root, name)


def four(n):
    return {'south': n, 'east': n, 'north': n, 'west': n}


def row(src, new, **kw):
    r = {'src': src, 'new': str(new), 'kind': 'ooze', 'size': '4x4', 'scale': '128/128', 'disp': '-48:0', 'idle': '4', 'idle_ms': '250',
         'walk': '8', 'walk_ms': '125', 'walk_src': 'walk', 'colours': '60'}
    r.update({k: str(v) for k, v in kw.items()})
    return r


def main():
    # ---- the committed table, sums, picks rows and map
    t = G.rows()
    assert G.problems() == [], G.problems()
    assert len(t) == 3 and [int(r['new']) for r in t] == list(range(3527, 3530)) and G.FIRST_NEW == 3527 == G.OUTFITS_72 + 1 and G.PAIR == 73
    assert [(r['src'], r['kind']) for r in t] == list(G.ROWS) and not {'humanoid', 'angel/spirit'} & set(G.KIND_NAMES)
    assert [r['size'] for r in t] == ['4x4', '5x5', '5x5'] and all(r['idle'] == '4' and r['walk'] == '8' for r in t)
    # every one pixel for pixel, at the size it was drawn, and standing on its tile
    assert all(r['scale'] == '%d/%d' % (32 * int(r['size'][0]), 32 * int(r['size'][0])) and r['disp'] == G.disp_text(int(r['size'][0])) for r in t)
    assert [r['walk_src'] for r in t].count('idle') == 1
    assert set(G.read_sums()) == {r['new'] for r in t} and all(len(v) == 64 for v in G.read_sums().values())
    assert len(set(G.read_sums().values())) == 3, 'two outfits with one digest'
    picks = G.picks_rows()
    assert len(picks) == 3 and G.map_problems() == [] and G.write_map(check=True) == []
    assert G.map_text(G.map_rows()) == open(G.MAP, encoding='utf-8', newline='').read()
    # bosses only (owner, O608): no monster of the bounty pool hunt list wears one, each boss has a file of ours and its own look
    hunt = set(W.pool_looks())
    own = G.own_looks()
    assert not [m for m, _n, _d in picks if m in hunt], 'a hunt monster on a boss look'
    assert all(m in own for m, _n, _d in picks) and len({n for _m, n, _d in picks}) == 3
    # no pack name in the tool, the table, the rows of picks.csv or the map (docs/CREDITS.md names them)
    words = ('jelly', 'eldritch', 'organism', 'glacial', 'chieftain', 'magister', 'academy', 'silverstorm', 'defender', 'sanctuary',
             'axemaiden', 'automata')
    for path in (G.TABLE, G.SUMS, G.MAP, os.path.join(HERE, 'gen_creature_outfits.py')):
        low = open(path, encoding='utf-8').read().lower()
        assert not [w for w in words if w in low], (path, [w for w in words if w in low])
    low = ''.join(line for line in open(G.PICKS, encoding='utf-8') if ',creature,' in line).lower()
    assert not [w for w in words if w in low], [w for w in words if w in low]

    # ---- every rule has a case
    A, B = 'a' * 12, 'b' * 12
    good = [row(A, 3527), row(B, 3528)]
    sums = {'3527': 'x', '3528': 'y'}
    assert G.problems(good, sums, want=None) == []
    for bad, text in (
            ([row(A, 3527), row(B, 3530)], 'must be 3528'),
            ([row('xyz', 3527), row(B, 3528)], 'not 12 hex'),
            ([row(A, 3527), row(A, 3528)], 'on two rows'),
            ([row(A, 3527, kind='fish'), row(B, 3528)], 'kind fish'),
            ([row(A, 3527, size='3x3'), row(B, 3528)], 'a boss look is'),
            ([row(A, 3527, size='2x2'), row(B, 3528)], 'a boss look is'),
            ([row(A, 3527, size='6x6'), row(B, 3528)], 'a boss look is'),
            ([row(A, 3527, size='4x5'), row(B, 3528)], 'a boss look is'),
            ([row(A, 3527, scale='1/2'), row(B, 3528)], 'pixel for pixel'),
            ([row(A, 3527, scale='128/100'), row(B, 3528)], 'pixel for pixel'),
            ([row(A, 3527, scale='128/134'), row(B, 3528)], 'pixel for pixel'),      # a 4x4 is never sampled down: it would be a 5x5
            ([row(A, 3527, size='5x5', scale='160/300', disp='-64:0'), row(B, 3528)], 'pixel for pixel'),
            ([row(A, 3527, disp='0:0'), row(B, 3528)], 'stands on its tile'),
            ([row(A, 3527, size='5x5', scale='160/160'), row(B, 3528)], 'stands on its tile'),
            ([row(A, 3527, idle=1), row(B, 3528)], 'idle phases'),
            ([row(A, 3527, walk=2), row(B, 3528)], 'walk phases'),
            ([row(A, 3527, walk_src='run'), row(B, 3528)], 'walk_src'),
            ([row(A, 3527, idle_ms=5), row(B, 3528)], '40 to 1000'),
            ([row(A, 3527, colours=0), row(B, 3528)], 'no colours')):
        p = G.problems(bad, sums, want=None)
        assert any(text in x for x in p), (text, p)
    assert G.problems([row(A, 3527, size='5x5', scale='160/160', disp='-64:0'), row(B, 3528, size='5x5', scale='160/200', disp='-64:0')],
                      sums, want=None) == []
    assert any('name other outfits' in x for x in G.problems(good, {'3527': 'x'}, want=None))
    assert any('not ROWS' in x for x in G.problems(good, sums))
    old = {'M1': 10, 'M2': 11, 'M3': 12}
    assert G.map_problems(good, [('M1', 3527, 1), ('M2', 3528, 2)], old) == []
    for bad, text in (([('M1', 3527, 1), ('M2', 3529, 3)], 'not a row'), ([('M1', 3527, 2), ('M2', 3528, 2)], 'not a row'),
                      ([('M1', 3527, 1), ('M2', 3527, 1), ('M3', 3527, 1), ('M1', 3528, 2)], 'more than 2'),
                      ([('M1', 3527, 1), ('M1', 3528, 2)], 'on two rows'), ([('M1', 3527, 1), ('M9', 3528, 2)], 'no monster file'),
                      ([('M1', 3527, 1)], 'worn by no monster')):
        p = G.map_problems(good, bad, old)
        assert any(text in x for x in p), (text, p)
    assert G.map_text([('M1', 10, 3527)]) == 'monster,look,new_look\nM1,10,3527\n'
    assert G.old_looks({'M1': 5}, {'M1': 9, 'M2': 7}) == {'M1': 5, 'M2': 7}, 'our file wins over the pool'

    # ---- the pixel rules
    assert G.pick(12, 4) == [0, 3, 6, 9] and G.pick(8, 8) == list(range(8)) and G.pick(4, 4) == [0, 1, 2, 3]
    for n in range(8, 25):
        p = G.pick(n, 8)
        gaps = [(p[(i + 1) % 8] - p[i]) % n for i in range(8)]
        assert p[0] == 0 and p == sorted(p) and len(set(p)) == 8 and max(gaps) - min(gaps) <= 1 and sum(gaps) == n, (n, p)
    a = np.zeros((2, 2, 4), np.uint8)
    a[0, 0] = (9, 9, 9, 127)
    a[0, 1] = (9, 9, 9, 128)
    c = G.cut(a)
    assert tuple(c[0, 0]) == (0, 0, 0, 0) and tuple(c[0, 1]) == (9, 9, 9, 255)
    src = np.arange(256 * 256, dtype=np.uint32).reshape(256, 256, 1).view(np.uint8).reshape(256, 256, 4)
    s = G.sample(src, (10, 20, 137, 147), 128, 128)      # pixel for pixel: the box itself
    assert s.shape == (128, 128, 4) and (s == src[20:148, 10:138]).all()
    s = G.sample(src, (10, 20, 137, 119), 128, 128)
    assert s.shape == (100, 128, 4) and (s == src[20:120, 10:138]).all()
    s = G.sample(src, (30, 40, 173, 172), 160, 160)
    assert s.shape == (133, 144, 4) and (s == src[40:173, 30:174]).all()
    s = G.sample(src, (0, 0, 199, 99), 200, 160)         # a figure of 200 px: 5 source pixels give 4
    assert s.shape == (80, 160, 4) and (s[0, 0] == src[0, 0]).all() and (s[79, 159] == src[99, 199]).all()
    # the size: the smallest canvas of whole tiles that holds the figure, 4x4 to 5x5; the displacement puts its middle over the tile
    assert [G.tiles_for(n) for n in (60, 120, 128, 129, 144, 160, 161, 250)] == [4, 4, 4, 5, 5, 5, 5, 5]
    assert G.disp_of(4) == (-48, 0) and G.disp_of(5) == (-64, 0) and G.disp_text(4) == '-48:0'
    for n in (4, 5):   # the middle column of the canvas, moved by the displacement, is the middle column of the last tile
        assert (32 * n - 1) / 2.0 - G.disp_of(n)[0] == 32 * n - 16.5
    assert G.flags_of(row(A, 1)) == (bytes([25, 0xD0, 0xFF, 0, 0]), {'displacement': (65488, 0)})
    assert G.flags_of(row(A, 1, size='5x5'))[1] == {'displacement': (65472, 0)}
    assert G.tiles_of_size('4x4') == 4 and G.tiles_of_size('5x5') == 5 and G.tiles_of_size('3x3') is None and G.tiles_of_size('4x5') is None

    with tempfile.TemporaryDirectory() as tmp:
        src_dir = os.path.join(tmp, 'packs')
        creature(src_dir, 'one', {'Idle': four(12), 'Walk': four(8)})
        creature(src_dir, 'two', {'Hover_Idle': {'south': 10, 'east': 16, 'north': 3, 'west': 9}, 'Run': four(8), 'Slow_Move': four(15)},
                 box=(60, 60, 100, 120), soft=True)
        creature(src_dir, 'deep/three', {'Idle': four(12), 'Attack': four(5)}, box=(50, 80, 150, 90))
        os.makedirs(os.path.join(src_dir, 'four', 'Animations', 'Idle', 'south'))   # three directions missing: no creature
        found = G.discover(src_dir)
        assert len(found) == 3
        by = {}
        for name in ('one', 'two', 'deep/three'):
            anim = 'Hover_Idle' if name == 'two' else 'Idle'
            by[name] = W._sha12(os.path.join(src_dir, name, 'Animations', anim, 'south', 'frame_000.png'))
        ids = {c.id: c for c in found}
        assert set(ids) == set(by.values())
        one, two, three = (ids[by[k]] for k in ('one', 'two', 'deep/three'))
        assert (one.walk_src, two.walk_src, three.walk_src) == ('walk', 'walk', 'idle')
        assert all('Slow_Move' in p for p in two.files[('walk', 0)]) and len(two.files[('walk', 2)]) == 15, 'the run folder is not the walk'
        assert three.files[('walk', 1)] == three.files[('idle', 1)]

        m1 = G.measure(one)
        assert (m1['tiles'], m1['scale'], m1['idle'], m1['walk'], m1['idle_ms'], m1['walk_ms']) == (4, '128/128', 4, 8, 250, 83), m1['scale']
        m2 = G.measure(two)
        assert (m2['idle'], m2['walk']) == (3, 8), 'a direction with 3 idle frames gives 3 phases'
        assert m2['idle_ms'] == round(1000 * (10 + 16 + 3 + 9) / 4 / 12 / 3) and m2['walk_ms'] == round(1000 * 15 / 12 / 8)
        assert m2['box'][1] == 61, 'the soft top row is cut away'
        m3 = G.measure(three)
        # 150 px wide, 3 steps of 2 px across the directions: 156 px, so 5x5 and still pixel for pixel
        assert (m3['tiles'], m3['scale']) == (5, '160/160') and m3['walk'] == 8 and m3['idle'] == 4, m3['scale']
        creature(src_dir, 'wide', {'Idle': four(4)}, box=(20, 80, 200, 90))
        mw = G.measure([c for c in G.discover(src_dir) if c.id not in ids][0])
        assert (mw['tiles'], mw['scale']) == (5, '160/206'), mw['scale']      # longer than 160 px: sampled down to 160
        import shutil
        shutil.rmtree(os.path.join(src_dir, 'wide'))
        for m in (m1, m2, m3):
            low = right = 0
            c = 32 * m['tiles']
            left = c
            for (g, d), lst in m['placed'].items():
                assert len(lst) == m[g]
                for fr in lst:
                    assert fr.shape == (c, c, 4) and set(np.unique(fr[..., 3])) <= {0, 255}
                    ys, xs = np.nonzero(fr[..., 3])
                    low, right, left = max(low, int(ys.max())), max(right, int(xs.max())), min(left, int(xs.min()))
            # the lowest pixel on the last row, the box in the middle of the canvas (half a pixel at most off it)
            assert low == c - 1 and right <= c - 1 and abs((left + right) / 2.0 - (c - 1) / 2.0) <= 0.5, (low, left, right)
        assert G.idle_problems([(row(one.id, 3), m1)]) == []
        flat = dict(m1, placed={k: [v[0]] * len(v) for k, v in m1['placed'].items()})
        assert len(G.idle_problems([(row(one.id, 3), flat)])) == 4, 'an idle group of one picture is refused'
        # the frames are the picked source frames, sampled: phase 1 of the idle group facing south is source frame 3
        a3 = G.cut(W._read_png(one.files[('idle', 2)][3]))
        want3 = G.place({('x', 0): [G.sample(a3, m1['box'], 128, 128)], ('y', 0): [G.sample(G.cut(W._read_png(p)), m1['box'], 128, 128)
                                                                                   for lst in one.files.values() for p in lst]}, 128)[('x', 0)][0]
        assert (m1['placed'][('idle', 2)][1] == want3).all()
        gs = G.groups_of(m1)
        assert [(g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.phases) for g, _t in gs] == [(0, 4, 4, 128, 1, 4, 4), (1, 4, 4, 128, 1, 4, 8)]
        assert [(g.w, g.h, g.exact) for g, _t in G.groups_of(m3)] == [(5, 5, 160)] * 2
        assert gs[0][0].anim == (0, 0, 0, (250, 250) * 4) and gs[1][0].anim == (0, 0, 0, (83, 83) * 8)
        assert [len(tl) for _g, tl in gs] == [4 * 4 * 16, 8 * 4 * 16]

        # ---- the pair: build, read back, live
        odat, ospr = WT.input_pair(tmp)
        want = ((one.id, 'ooze'), (two.id, 'aberration'), (three.id, 'elemental'))
        out = os.path.join(tmp, 'out')
        lines = []
        new = G.build(odat, ospr, out, src_dir, want=want, first=3, log=lines.append)
        assert new == [3, 4, 5] and any('append-only guard passed' in x for x in lines), lines
        ms = G.measured(src_dir, want, 3)
        table, sums = [r for r, _m in ms], G.pack_sums(ms)
        assert [r['new'] for r in table] == ['3', '4', '5'] and table[2]['walk_src'] == 'idle'
        assert [(r['size'], r['scale'], r['disp']) for r in table] == [('4x4', '128/128', '-48:0')] * 2 + [('5x5', '160/160', '-64:0')]
        assert G.problems(table, sums, first=3, want=want) == []
        assert G.table_text(table).splitlines()[0] == ','.join(G.HEADER) and len(G.table_text(table).splitlines()) == 4
        paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
        d, sp = Dat(paths[0]), Spr(paths[1])
        assert len(d.outfits) == 5
        g0, g1 = parse_body(d, d.outfit(4))
        assert (g0.gtype, g0.phases, g1.gtype, g1.phases) == (0, 3, 1, 8) and (g0.w, g0.h, g1.w, g1.h) == (4, 4, 4, 4)
        # the displacement is the outfit's only flag, as the dat reader gives it (u16: -48 and -64)
        assert dict(d.outfit(4).flags) == {'displacement': (65488, 0)} and dict(d.outfit(5).flags) == {'displacement': (65472, 0)}
        assert [(g.w, g.h) for g in parse_body(d, d.outfit(5))] == [(5, 5), (5, 5)]
        quiet = dict(log=lambda *_: None)
        assert G.live(*paths, table=table, sums=sums, **quiet) == []
        assert G.live(*paths, table=table, sums={**sums, '4': '0' * 64}, **quiet)
        assert G.live(odat, ospr, table=table, sums=sums, **quiet), 'a pair without the outfits'
        assert G.live(*paths, table=[dict(table[0], idle='2')] + table[1:], sums=sums, **quiet), 'another phase count'
        assert G.live(*paths, table=[dict(table[0], size='5x5')] + table[1:], sums=sums, **quiet), 'another size and displacement'
        for args, kw, text in (((odat, ospr, out, src_dir), dict(want=want, first=3), 'exists'),
                               ((odat, ospr, os.path.join(tmp, 'o2'), src_dir), dict(want=want, first=9), 'wrong input pair'),
                               ((odat, ospr, os.path.join(tmp, 'o3'), src_dir), dict(want=(('f' * 12, 'ooze'),), first=3), 'no creature')):
            try:
                G.build(*args, log=lambda *_: None, **kw)
            except SystemExit as e:
                assert text in str(e), (text, str(e))
            else:
                raise AssertionError('build did not refuse: ' + text)
        # a second build of the same packs gives the same bytes
        out2 = os.path.join(tmp, 'again')
        G.build(odat, ospr, out2, src_dir, want=want, first=3, log=lambda *_: None)
        assert open(paths[0], 'rb').read() == open(os.path.join(out2, 'Tibia.dat'), 'rb').read()
        assert open(paths[1], 'rb').read() == open(os.path.join(out2, 'Tibia.spr'), 'rb').read()
    assert G.main(['build', 'a', 'b', 'c']) == 1   # --src is needed
    assert G.main(['check']) == 0
    print('gen_creature_outfits_test: ok')


if __name__ == '__main__':
    main()
