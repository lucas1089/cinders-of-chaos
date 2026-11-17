#!/usr/bin/env python3
"""Test of gen_creature_outfits.py (O608, after O605): python3 -I client/tools/sprites/gen_creature_outfits_test.py

The committed table, sums, picks rows and monster map against the rules, every rule with a failing case, and `discover` / `measure` /
`build` / `live` on synthetic packs drawn here (frame folders of the four directions on a 256 px canvas: a creature with a walk
folder, one with a move folder and a run folder that is not read, one with no walk at all whose box is longer than 128 px, one
with a direction of few frames) and a small synthetic input pair: the frame pick (evenly spaced, the loop closed), the hard alpha cut,
the size (4x4 up to 128 px, 5x5 up to 160 px, up to 8x8, always pixel for pixel: nothing is sampled down), the placement (lowest
pixel on the last row, the box in the middle of the canvas), the displacement that puts the middle over the creature's tile, the
outfit shape (idle group, walk group, as many phases as the longest direction has frames, 83 ms a phase: 12 pictures a second), the
idle rule, the outfits appended after the input's, every slot reading back as drawn, wrong input pairs and an existing output
folder refused. O616 (owner 2026-11-17, "so no pixel is lost"): every built frame has the opaque pixels of its source frame, on the
canvas and in the sprite tiles, colour for colour; every source frame of every direction is shown, in order; a frame with soft
alpha is refused; the four directions are the pack's own folders; the foot point stands on the boss's tile; each with a failing
case, and `live` holds the pair to the durations, the pixel count, the pictures per direction and the foot point. No pack files and no real pair needed. Needs numpy and
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
    r = {'src': src, 'new': str(new), 'kind': 'ooze', 'size': '4x4', 'scale': '128/128', 'disp': '-48:0', 'idle': '4', 'idle_ms': '83',
         'walk': '8', 'walk_ms': '83', 'walk_src': 'walk', 'colours': '60', 'idle_frames': '4/3/4/2', 'walk_frames': '8/8/5/8',
         'pixels': '1000'}
    r.update({k: str(v) for k, v in kw.items()})
    return r


def main():
    # ---- the committed table, sums, picks rows and map
    t = G.rows()
    assert G.problems() == [], G.problems()
    assert len(t) == 3 and [int(r['new']) for r in t] == list(range(3527, 3530)) and G.FIRST_NEW == 3527 == G.OUTFITS_72 + 1 and G.PAIR == 73
    assert [(r['src'], r['kind']) for r in t] == list(G.ROWS) and not {'humanoid', 'angel/spirit'} & set(G.KIND_NAMES)
    assert [r['size'] for r in t] == ['4x4', '5x5', '5x5']
    # no frame dropped (O616): a group has as many phases as its longest direction has frames, 83 ms each (12 a second)
    assert [(r['idle'], r['walk']) for r in t] == [('16', '21'), ('19', '15'), ('12', '12')]
    assert [(r['idle_frames'], r['walk_frames']) for r in t] == [('16/16/12/16', '11/16/21/16'), ('19/19/17/14', '15/15/14/15'),
                                                                 ('12/12/12/12', '12/12/12/12')]
    assert all(int(r[g]) == max(G.frames_of(r[g + '_frames'])) and r[g + '_ms'] == '83' for r in t for g in ('idle', 'walk')) and G.FRAME_MS == 83
    assert [r['pixels'] for r in t] == ['1009990', '1021347', '580686']
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
            ([row(A, 3527, size='9x9'), row(B, 3528)], 'a boss look is'),
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
            ([row(A, 3527, idle_ms=250), row(B, 3528)], 'a phase lasts 83 ms'),
            ([row(A, 3527, walk_ms=84), row(B, 3528)], 'a phase lasts 83 ms'),
            ([row(A, 3527, size='5x5', scale='160/200', disp='-64:0'), row(B, 3528)], 'pixel for pixel'),
            ([row(A, 3527, idle_frames='4/3/4'), row(B, 3528)], 'four frame counts'),
            ([row(A, 3527, idle_frames='4/3/6/2'), row(B, 3528)], 'a frame is dropped'),
            ([row(A, 3527, walk=9), row(B, 3528)], 'a frame is dropped or shown twice'),
            ([row(A, 3527, walk_src='idle'), row(B, 3528)], 'walk_frames is not idle_frames'),
            ([row(A, 3527, pixels='many'), row(B, 3528)], 'opaque pixels'),
            ([row(A, 3527, colours=0), row(B, 3528)], 'no colours')):
        p = G.problems(bad, sums, want=None)
        assert any(text in x for x in p), (text, p)
    assert G.problems([row(A, 3527, size='5x5', scale='160/160', disp='-64:0'), row(B, 3528, size='7x7', scale='224/224', disp='-96:0')],
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
    assert [G.tiles_for(n) for n in (60, 120, 128, 129, 144, 160, 161, 250, 256)] == [4, 4, 4, 5, 5, 5, 6, 8, 8]
    assert G.tile_box(4) == (48, 96, 79, 127) and G.tile_box(5) == (64, 128, 95, 159), 'the boss tile on the canvas'
    assert G.frames_of('16/16/12/16') == [16, 16, 12, 16] and G.frames_of('1/2/3') is None and G.frames_of('0/1/1/1') is None
    for n in range(2, 25):       # with as many phases as the longest direction has frames, a shorter one still shows every frame
        for ph in range(n, 25):
            p = G.pick(n, ph)
            assert sorted(set(p)) == list(range(n)) and p == sorted(p) and max(p.count(i) for i in range(n)) - min(p.count(i) for i in range(n)) <= 1
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
                 box=(60, 60, 100, 120))
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
        assert (m1['tiles'], m1['scale'], m1['idle'], m1['walk'], m1['idle_ms'], m1['walk_ms']) == (4, '128/128', 12, 8, 83, 83), m1['scale']
        m2 = G.measure(two)
        assert (m2['idle'], m2['walk']) == (16, 15), 'as many phases as the longest direction has frames'
        assert m2['idle_ms'] == 83 == m2['walk_ms'] and m2['counts'][('idle', 0)] == 3 and G.frames_text(m2, 'idle') == '3/16/10/9'
        # the direction of 3 frames shows each of them, in order, over the 16 phases; the longest one frame for frame
        assert m2['use'][('idle', 0)] == [0] * 6 + [1] * 5 + [2] * 5 and m2['use'][('idle', 1)] == list(range(16))
        m3 = G.measure(three)
        # 150 px wide, 3 steps of 2 px across the directions: 156 px, so 5x5 and still pixel for pixel
        assert (m3['tiles'], m3['scale']) == (5, '160/160') and m3['walk'] == 12 and m3['idle'] == 12, m3['scale']
        assert m3['use'][('walk', 2)] == list(range(12)) and G.frames_text(m3, 'walk') == G.frames_text(m3, 'idle') == '12/12/12/12'
        import shutil
        creature(src_dir, 'wide', {'Idle': four(4)}, box=(20, 80, 200, 90))
        mw = G.measure([c for c in G.discover(src_dir) if c.id not in ids][0])
        assert (mw['tiles'], mw['scale']) == (7, '224/224'), mw['scale']      # longer than 160 px: a bigger canvas, never sampled down
        assert G.pixel_problems(mw) == []
        shutil.rmtree(os.path.join(src_dir, 'wide'))
        creature(src_dir, 'softy', {'Idle': four(4)}, soft=True)              # a soft pixel would be lost or changed by the cut: refused
        try:
            G.measure([c for c in G.discover(src_dir) if c.id not in ids][0])
        except ValueError as e:
            assert 'soft alpha' in str(e), str(e)
        else:
            raise AssertionError('a frame with soft alpha was taken')
        shutil.rmtree(os.path.join(src_dir, 'softy'))
        # ---- no pixel lost (O616): every phase has the opaque pixels of its source frame, on the canvas and in the tiles
        for c, m in ((one, m1), (two, m2), (three, m3)):
            assert G.pixel_problems(m) == [] and G.foot_problems(m) == [], (G.pixel_problems(m), G.foot_problems(m))
            total = 0
            for (g, d), use in m['use'].items():
                assert sorted(set(use)) == list(range(len(c.files[(g, d)]))), 'every source frame is shown'
                for ph, i in enumerate(use):
                    n_src = int((W._read_png(c.files[(g, d)][i])[..., 3] > 0).sum())
                    assert n_src == G.opaque(m['placed'][(g, d)][ph]) > 0
                    total += n_src
            assert total == m['pixels']
            # the four directions are the pack's own folders: nothing is mirrored
            assert len({tuple(c.files[('idle', d)]) for d in range(4)}) == 4 and len({m['placed'][('idle', d)][0].tobytes() for d in range(4)}) == 4

        def tampered(m, key, ph, fn, use=None):
            placed = dict(m['placed'])
            lst = list(placed[key])
            lst[ph] = fn(lst[ph].copy())
            placed[key] = lst
            return dict(m, placed=placed)

        def lose(a):
            ys, xs = np.nonzero(a[..., 3])
            a[ys[0], xs[0]] = 0
            return a

        def recolour(a):
            ys, xs = np.nonzero(a[..., 3])
            a[ys[0], xs[0], :3] ^= 1
            return a

        assert any('opaque pixels in the source' in x for x in G.pixel_problems(tampered(m1, ('idle', 2), 5, lose))), 'a lost pixel'
        assert any('pixel for pixel' in x for x in G.pixel_problems(tampered(m1, ('walk', 1), 0, recolour))), 'a changed colour'
        assert any('moved by' in x for x in G.pixel_problems(tampered(m1, ('walk', 3), 2, lambda a: np.roll(a, -1, 1)))), 'a frame moved alone'
        assert any('dropped or out of order' in x for x in G.pixel_problems(dict(m1, use={**m1['use'], ('idle', 0): [0] * 12}))), 'a dropped frame'
        assert any('sampled' in x for x in G.pixel_problems(dict(m1, scale='128/134')))
        # the foot point: a figure pushed off the boss's tile, sideways or up, is refused
        def only(a, rows, cols):
            b = np.zeros_like(a)
            b[rows, cols] = a[rows, cols]
            return b

        off = dict(m1, placed={k: [only(a, slice(None), slice(0, 40)) for a in v] for k, v in m1['placed'].items()})
        assert all('foot column' in x for x in G.foot_problems(off)) and len(G.foot_problems(off)) == 8, G.foot_problems(off)
        up = dict(m1, placed={k: [only(a, slice(0, 88), slice(None)) for a in v] for k, v in m1['placed'].items()})
        assert all('lowest pixel' in x for x in G.foot_problems(up)) and len(G.foot_problems(up)) == 8, G.foot_problems(up)
        assert 'tile cols 48-79 rows 96-127' in G.foot_line(m1)
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
        # the frames are the source frames: phase 3 of the idle group facing south is source frame 3
        a3 = G.cut(W._read_png(one.files[('idle', 2)][3]))
        want3 = G.place({('x', 0): [G.sample(a3, m1['box'], 128, 128)], ('y', 0): [G.sample(G.cut(W._read_png(p)), m1['box'], 128, 128)
                                                                                   for lst in one.files.values() for p in lst]}, 128)[('x', 0)][0]
        assert (m1['placed'][('idle', 2)][3] == want3).all()
        gs = G.groups_of(m1)
        assert [(g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.phases) for g, _t in gs] == [(0, 4, 4, 128, 1, 4, 12), (1, 4, 4, 128, 1, 4, 8)]
        assert [(g.w, g.h, g.exact) for g, _t in G.groups_of(m3)] == [(5, 5, 160)] * 2
        assert gs[0][0].anim == (0, 0, 0, (83, 83) * 12) and gs[1][0].anim == (0, 0, 0, (83, 83) * 8)
        assert [len(tl) for _g, tl in gs] == [12 * 4 * 16, 8 * 4 * 16]

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
        assert (g0.gtype, g0.phases, g1.gtype, g1.phases) == (0, 16, 1, 15) and (g0.w, g0.h, g1.w, g1.h) == (4, 4, 4, 4)
        # the displacement is the outfit's only flag, as the dat reader gives it (u16: -48 and -64)
        assert dict(d.outfit(4).flags) == {'displacement': (65488, 0)} and dict(d.outfit(5).flags) == {'displacement': (65472, 0)}
        assert [(g.w, g.h) for g in parse_body(d, d.outfit(5))] == [(5, 5), (5, 5)]
        quiet = dict(log=lambda *_: None)
        assert G.live(*paths, table=table, sums=sums, **quiet) == []
        assert G.live(*paths, table=table, sums={**sums, '4': '0' * 64}, **quiet)
        assert G.live(odat, ospr, table=table, sums=sums, **quiet), 'a pair without the outfits'
        assert G.live(*paths, table=[dict(table[0], idle='2')] + table[1:], sums=sums, **quiet), 'another phase count'
        assert G.live(*paths, table=[dict(table[0], size='5x5')] + table[1:], sums=sums, **quiet), 'another size and displacement'
        # O616: the pair is held to the durations, the pixel count and the pictures a direction shows
        for bad, text in ((dict(table[1], idle_ms='84'), 'do not last 84 ms'), (dict(table[1], pixels=str(int(table[1]['pixels']) + 1)), 'opaque pixels'),
                          (dict(table[1], idle_frames='4/16/10/9'), 'different pictures')):
            p = G.live(*paths, table=[table[0], bad, table[2]], sums=sums, **quiet)
            assert len(p) == 1 and text in p[0], (text, p)
        assert [int(r['pixels']) for r in table] == [m['pixels'] for _r, m in ms]
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
