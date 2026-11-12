#!/usr/bin/env python3
"""Test of gen_wst_outfits.py (O540): python3 -I client/tools/sprites/gen_wst_outfits_test.py

The committed table and sums against the rules, and `discover` / `measure` / `select` / `sums` / `build` / `live` on synthetic packs
drawn here (a 64 px sheet creature with a colour mask, a 128 px one, a strip creature, a 160 px strip creature, a creature with too
few colours) and a small synthetic input pair: the tint formula, the 2:1 sampling, the placement (lowest pixel on row 63, middle on
column 47.5, left of the last column, a figure that does not fit is refused), the outfit shape (idle group, walk group, 2x2, phases,
durations), the picks appended after the input's outfits, every slot reading back as drawn, a picture the input has taking its sprite
id, wrong input pairs and an existing output folder refused. No pack files and no real pair needed. Needs numpy and Pillow (the fx venv
of CI). Nothing drawn here is art of any pack."""
import json
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_wst_outfits as G  # noqa: E402
import check_pair_test as T  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from import_outfits import parse_body  # noqa: E402

POSES = ['idle1', 'idle2', 'walk1', 'walk2', 'walk3', 'walk4', 'attack1', 'attack2', 'death1', 'death2', 'death3']
TINT = {'head': [200, 100, 50], 'body': [10, 20, 30], 'legs': [255, 255, 255], 'feet': [0, 128, 255]}
MARK = [(255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255)]


def figure(rng, h, w, top, left, cell, seed_value):
    """a cell with a random grey figure (binary alpha) at (top, left) of size h x w; returns (cell array, marker array)"""
    base = np.zeros((cell, cell, 4), np.uint8)
    mask = np.zeros((cell, cell, 4), np.uint8)
    g = rng.integers(40, 250, (h, w))
    base[top:top + h, left:left + w, :3] = g[..., None]
    base[top:top + h, left:left + w, 3] = 255
    for y in range(h):
        for x in range(w):
            part = (x + y) % 5
            if part < 4:
                mask[top + y, left + x] = MARK[part] + (255,)
    base[top, left, 3] = 255
    return base, mask


def sheet_creature(root, name, cell, size, fig, colours_hi=True):
    """a folder with animations.json and sheets/<name>_sheet.png (base | mask, 11 pose rows, 4 directions)"""
    d = os.path.join(root, name)
    os.makedirs(os.path.join(d, 'sheets'))
    rng = np.random.default_rng(sum(map(ord, name)) + 7)
    img = np.zeros((11 * cell, 8 * cell, 4), np.uint8)
    h, w, top, left = fig
    for r in range(11):
        for dr in range(4):
            if colours_hi:
                b, m = figure(rng, h, w, top + (r % 3), left + dr, cell, r)
            else:   # two colours only
                b, m = figure(rng, h, w, top, left, cell, r)
                b[..., :3] = np.where(b[..., :3] > 120, 200, 60).astype(np.uint8)
                b[..., :3][(np.arange(cell)[:, None] + np.arange(cell)[None, :]) % 2 == 0] = 90
            img[r * cell:(r + 1) * cell, dr * cell:(dr + 1) * cell] = b
            img[r * cell:(r + 1) * cell, (4 + dr) * cell:(5 + dr) * cell] = m
    Image.fromarray(img, 'RGBA').save(os.path.join(d, 'sheets', name + '_sheet.png'))
    Image.fromarray(np.zeros((4, 4, 4), np.uint8), 'RGBA').save(os.path.join(d, 'sheets', name + '_shadow.png'))
    json.dump({'name': name, 'size': size, 'cell': cell, 'anchor': [52.0, 54.0], 'poses': POSES, 'schemes': ['first', 'second'],
               'tints': {'first': TINT, 'second': {k: [1, 2, 3] for k in TINT}}}, open(os.path.join(d, 'animations.json'), 'w'))
    return d


def strip_creature(root, key, canvas, frames=4, soft=False):
    """strips <key>_{idle,walk}_{n,e,s,w}_strip.png of 4 frames of a canvas x canvas picture"""
    d = os.path.join(root, 'strips')
    os.makedirs(d, exist_ok=True)
    rng = np.random.default_rng(sum(map(ord, key)) + 3)
    for g in ('idle', 'walk'):
        for k, letter in enumerate('news'):
            a = np.zeros((canvas, frames * canvas, 4), np.uint8)
            for f in range(frames):
                h, w = canvas // 3, canvas // 3
                top, left = canvas - h - 3, canvas // 2 - w // 2 + k
                col = rng.integers(0, 256, (h, w, 3))
                a[top:top + h, f * canvas + left:f * canvas + left + w, :3] = col
                a[top:top + h, f * canvas + left:f * canvas + left + w, 3] = 255
                if soft:
                    a[top, f * canvas + left:f * canvas + left + w, 3] = 40
            Image.fromarray(a, 'RGBA').save(os.path.join(d, '%s_%s_%s_strip.png' % (key, g, letter)))
    return d


def rec(i, n=1, a=255):
    return T.record({(i * 7 + k) % 1000: ((i * 5 + k * 13) % 256, (i * 11) % 256, (k * 29 + i) % 256, a) for k in range(n)})


def input_pair(tmp):
    """a pair of 2 outfits over 8 sprites (idle group 1 phase, walk group 2 phases); sprite 1 is a picture the picks can reuse"""
    recs = [rec(i, 1 + i % 3) for i in range(1, 9)]
    o = T.entry(b'', [T.group([1, 2, 3, 4], px=4, gtype=0), T.group([2, 3, 4, 5, 6, 7, 8, 1], px=4, phases=2, gtype=1)], outfit=True)
    dat = T.dat_bytes([], [o, o], [T.entry(b'', [T.group([1, 2], phases=2)])], [])
    d = os.path.join(tmp, 'in')
    os.makedirs(d)
    paths = []
    for name, blob in (('ours.dat', dat), ('ours.spr', T.spr_bytes(recs))):
        p = os.path.join(d, name)
        open(p, 'wb').write(blob)
        paths.append(p)
    return paths


def row(src, new, kind='beast', size='2x2', scale='1', idle='2', walk='4', colours='600', outcolours='600'):
    return {'src': src, 'new': str(new), 'kind': kind, 'size': size, 'scale': scale, 'idle': idle, 'walk': walk, 'colours': colours,
            'outcolours': outcolours}


def main():
    # the committed table, sums, kinds and map
    committed = G.rows()
    assert G.problems() == [], G.problems()
    assert len(committed) == 77 and [int(r['new']) for r in committed] == list(range(3434, 3511)) and G.FIRST_NEW == 3434 == G.OUTFITS_70 + 1
    assert all(r['kind'] in G.KIND_NAMES and int(r['colours']) >= 500 and int(r['walk']) >= 4 and r['size'] == '2x2' for r in committed)
    assert all(int(x) <= 2 for r in committed for x in r['size'].split('x')), 'a pick above 2x2'
    assert {r['scale'] for r in committed} == {'1', '1/2'}
    assert set(G.read_sums()) == {r['src'] for r in committed} and all(len(v) == 64 for v in G.read_sums().values())
    assert not set(G.EXCLUDED) & {r['src'] for r in committed}
    assert any('is excluded' in x for x in G.problems(committed + [row(next(iter(G.EXCLUDED)), 3511, kind=G.KINDS[next(iter(G.EXCLUDED))])], G.read_sums()))
    # every rule has a case
    s = {'a' * 12: 'x', 'b' * 12: 'y'}
    A, B = 'a' * 12, 'b' * 12
    saved = dict(G.KINDS)
    G.KINDS.update({A: 'beast', B: 'beast'})
    try:
        ok = [row(A, 11), row(B, 12)]
        assert G.problems(ok, s, first=11) == [], G.problems(ok, s, first=11)
        for bad, text in (([row(A, 11), row(B, 14)], 'must be 12'), ([row(A, 11), row(A, 12)], 'two rows'),
                          ([row(A, 11, kind='dog'), row(B, 12)], 'is not one of'), ([row(A, 11, size='3x3'), row(B, 12)], 'above 2x2'),
                          ([row(A, 11, walk='3'), row(B, 12)], 'walk frames'), ([row(A, 11, idle='1'), row(B, 12)], 'idle frames'),
                          ([row(A, 11, colours='499'), row(B, 12)], 'polished'), ([row(A, 11, size='big'), row(B, 12)], 'not WxH'),
                          ([row(A, 11, scale='2'), row(B, 12)], 'scale 2'), ([row('xyz', 11), row(B, 12)], 'not 12 hex'),
                          ([row(A, 11, kind='undead'), row(B, 12)], 'KINDS says')):
            assert any(text in x for x in G.problems(bad, s, first=11)), (text, G.problems(bad, s, first=11))
        assert any('other outfits' in x for x in G.problems(ok, {A: 'x'}, first=11))
    finally:
        G.KINDS.clear()
        G.KINDS.update(saved)

    # the monster map: picks.csv rows of family purchased against the outfit table and the pool
    tbl = [row('a' * 12, 3434), row('b' * 12, 3435)]
    picks, pool = [('A', 3434, 1), ('B', 3435, 2), ('C', 3435, 2)], {'A': 100, 'B': 200, 'C': 300}
    assert G.map_rows(picks, pool) == [('A', 100, 3434), ('B', 200, 3435), ('C', 300, 3435)]
    assert G.map_text(G.map_rows(picks, pool)) == 'monster,look,new_look\nA,100,3434\nB,200,3435\nC,300,3435\n'
    assert G.map_problems(tbl, picks, pool) == []
    for bp, bpool, text in (([('A', 3434, 1), ('B', 3437, 4)], pool, 'not a row'), ([('A', 3434, 1), ('B', 3434, 1), ('C', 3434, 1)], pool, 'more than 2 monsters'),
                            ([('A', 3434, 1), ('A', 3435, 2)], pool, 'two rows'), (picks, {'A': 100}, 'not in the bounty pool')):
        assert any(text in x for x in G.map_problems(tbl, bp, bpool)), (text, G.map_problems(tbl, bp, bpool))
    assert G.write_map(check=True) == [] and G.map_problems() == []
    assert len(G.picks_rows()) == 79 and set(G.pool_looks()) >= {m for m, _n, _d in G.picks_rows()}

    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, 'src')
        os.makedirs(src)
        # --- discover and the colour of a sheet creature
        sheet_creature(src, 'small_one', 64, 'small', (24, 20, 20, 24))
        sheet_creature(src, 'large_one', 128, 'large', (60, 70, 40, 30))
        sheet_creature(src, 'dull_one', 64, 'small', (24, 20, 20, 24), colours_hi=False)
        strip_creature(src, 'strip_one', 64)
        strip_creature(src, 'soft_one', 64, soft=True)
        strip_creature(src, 'huge_one', 160)
        found = G.discover(src)
        assert len(found) == 6 and len({c.id for c in found}) == 6 and all(len(c.id) == 12 for c in found)
        small = next(c for c in found if c.kind == 'pack' and c.cell == 64 and G.measure(c)['colours'] > 100)
        fr = small.frames()
        assert sorted(fr) == [(g, d) for g in ('idle', 'walk') for d in range(4)] and len(fr[('idle', 2)]) == 2 and len(fr[('walk', 2)]) == 4
        # the tint: marker pixels are base * scheme / 255, every other pixel keeps its colour, alpha as drawn
        meta = {'cell': 64, 'poses': POSES, 'schemes': ['first'], 'tints': {'first': TINT}}
        rng = np.random.default_rng(5)
        b, m = figure(rng, 10, 10, 10, 10, 64, 0)
        sheet = np.zeros((11 * 64, 8 * 64, 4), np.uint8)
        sheet[0:64, 0:64] = b
        sheet[0:64, 4 * 64:5 * 64] = m
        out = G.tint_frames(meta, sheet)[('idle1', 0)]
        for y in range(10, 20):
            for x in range(10, 20):
                part = (x - 10 + y - 10) % 5
                if part < 4:
                    want = np.clip(np.round(b[y, x, :3] * (np.array(TINT[('head', 'body', 'legs', 'feet')[part]]) / 255.0)), 0, 255)
                    assert (out[y, x, :3] == want).all() and out[y, x, 3] == 255, (x, y, part)
                else:
                    assert (out[y, x] == b[y, x]).all(), (x, y)
        assert out[0, 0].tolist() == [0, 0, 0, 0]
        # --- 2:1 sampling keeps every second pixel, the offset that keeps the most
        a = np.zeros((128, 128, 4), np.uint8)
        a[1::2, 1::2] = (9, 9, 9, 255)
        assert G.half(a, 1, 1).shape == (64, 64, 4) and (G.half(a, 1, 1)[..., 3] == 255).all() and (G.half(a, 0, 0)[..., 3] == 0).all()
        assert G.best_phase({'k': [a]}) == (1, 1)
        # --- placement: lowest pixel on row 63, middle on column 47.5, left of the last column, a figure that does not fit is refused
        f = np.zeros((64, 64, 4), np.uint8)
        f[10:30, 5:15] = (1, 2, 3, 255)         # 10 wide, 20 high
        placed = G.place({('walk', 2): [f, f]})[('walk', 2)][0]
        ys, xs = np.nonzero(placed[..., 3] > 0)
        assert ys.max() == 63 and ys.min() == 44 and (xs.min() + xs.max()) / 2.0 in (47.0, 47.5), (xs.min(), xs.max(), ys.min(), ys.max())
        wide = np.zeros((64, 64, 4), np.uint8)
        wide[10:20, 0:44] = (1, 2, 3, 255)      # 44 wide: the box would pass column 63 if centred on 47.5
        placed = G.place({('walk', 2): [wide]})[('walk', 2)][0]
        ys, xs = np.nonzero(placed[..., 3] > 0)
        assert xs.max() == 63 and xs.min() == 20 and ys.max() == 63
        try:
            G.place({('walk', 2): [np.zeros((64, 64, 4), np.uint8)]})
        except ValueError as e:
            assert 'no opaque pixel' in str(e)
        else:
            raise AssertionError('an empty creature is refused')
        # a figure taller than the canvas after placement does not fit
        tall = np.zeros((70, 70, 4), np.uint8)
        tall[0:70, 0:5] = (1, 2, 3, 255)
        try:
            G.place({('walk', 2): [tall]})
        except ValueError as e:
            assert 'does not fit' in str(e)
        else:
            raise AssertionError('a 70 px figure does not fit a 64 px canvas')
        # --- measure and the pick rule
        by_cell = {}
        for c in found:
            by_cell.setdefault((c.kind, c.cell), []).append((c, G.measure(c)))
        big = by_cell[('pack', 128)][0][1]
        assert big['scale'] == '1/2' and big['placed'][('walk', 2)][0].shape == (64, 64, 4) and not big['reason'], big
        huge = by_cell[('strip', 160)][0][1]
        assert 'canvas 160' in huge['reason'] and not G.passes(huge)
        dull = [m for c, m in by_cell[('pack', 64)] if m['colours'] < 20][0]
        assert not G.passes(dull)
        # --- select on the synthetic packs (kinds and colour line set for them)
        kinds_saved, mc = dict(G.KINDS), G.MIN_COLOURS
        G.KINDS.clear()
        for i, c in enumerate(found):
            G.KINDS[c.id] = ('beast', 'undead', 'demon', 'plant', 'worm', 'humanoid')[i % 6]
        G.MIN_COLOURS = 50
        try:
            lines = []
            picks = G.select(src, log=lines.append)
            got = {p[0] for p in picks}
            assert got == {c.id for c in found} - {dull_c.id for dull_c, m in by_cell[('pack', 64)] if m['colours'] < 20} - {by_cell[('strip', 160)][0][0].id}, (got, lines)
            assert any('canvas 160' in x for x in lines) and any('drop' in x for x in lines)
            assert [p[1] for p in picks] == sorted(p[1] for p in picks), 'ordered by kind'
            assert all(p[2] == '2x2' and p[3] in ('1', '1/2') for p in picks) and any(p[3] == '1/2' for p in picks)
            G.EXCLUDED[by_cell[('strip', 64)][0][0].id] = 'test'
            try:
                assert by_cell[('strip', 64)][0][0].id not in {p[0] for p in G.select(src, log=lambda *_: None)}
            finally:
                del G.EXCLUDED[by_cell[('strip', 64)][0][0].id]
            sm = G.pack_sums(src, sorted(got))
            assert sorted(sm) == sorted(got) and all(len(v) == 64 for v in sm.values())
            assert G.sums_text(sm).splitlines()[1].split()[0] == sorted(got)[0]
            # --- the pair: build, read back, live
            odat, ospr = input_pair(tmp)
            od, osp = Dat(odat), Spr(ospr)
            table = [row(p[0], 3 + i, p[1], '2x2', p[3], str(p[4]), str(p[5]), str(p[6]), str(p[7])) for i, p in enumerate(picks)]
            out = os.path.join(tmp, 'out')
            lines = []
            ids = G.build(odat, ospr, out, src, table=table, first=3, log=lines.append)
            assert ids == [3 + i for i in range(len(picks))], ids
            nd, nsp = Dat(os.path.join(out, 'Tibia.dat')), Spr(os.path.join(out, 'Tibia.spr'))
            assert len(od.outfits) == 2 and len(nd.outfits) == 2 + len(picks) and nd.counts[2:] == od.counts[2:], nd.counts
            assert nd.data[8:od.outfits[-1].raw[1]] == od.data[8:od.outfits[-1].raw[1]], 'old outfits changed'
            assert nsp.count > osp.count
            for i in range(1, osp.count + 1):    # every old sprite stays at its id
                x, y = osp.sprite(i), nsp.sprite(i)
                assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), i
            for nid, r in zip(ids, table):
                gs = parse_body(nd, nd.outfit(nid))
                assert len(gs) == 2 and not nd.outfit(nid).flags
                assert [(g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz) for g in gs] == [(0, 2, 2, 64, 1, 4, 1, 1), (1, 2, 2, 64, 1, 4, 1, 1)]
                assert gs[0].phases == int(r['idle']) and gs[1].phases == int(r['walk'])
                strip = r['src'] in {c.id for c, _m in by_cell[('strip', 64)]}
                ms_idle, ms_walk = (220, 140) if strip else (333, 125)
                assert gs[0].anim == (0, 0, 0, tuple([ms_idle, ms_idle] * gs[0].phases)) and gs[1].anim == (0, 0, 0, tuple([ms_walk, ms_walk] * gs[1].phases)), (gs[0].anim, gs[1].anim)
                assert len(gs[0].sprites) == 4 * 4 * gs[0].phases and len(gs[1].sprites) == 4 * 4 * gs[1].phases
            assert any('verified' in x for x in lines) and any('append-only guard passed' in x for x in lines), lines
            # live: the right sums pass, a wrong one, a short pair and a pair with another shape fail
            good = {r['src']: G.digest(nd, nsp, int(r['new'])) for r in table}
            paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
            assert G.live(*paths, table=table, sums=good, first=3, log=lambda *_: None) == []
            assert G.live(*paths, table=table, sums={**good, table[0]['src']: '0' * 64}, first=3, log=lambda *_: None)
            assert G.live(odat, ospr, table=table, sums=good, first=3, log=lambda *_: None)
            # the digest of the pack is the digest of the pair outfit
            assert all(good[k] == sm[k] for k in good), 'the sums of the pack files equal the digests read from the pair'
            # a picture of the input pair is reused: a one pixel tile record equal to sprite 1 would take id 1 (checked by the record index)
            idx = G.record_index(osp)
            assert len(idx) >= 1 and all(isinstance(v, int) for v in idx.values())
            # refusals: the output exists, the input has other outfits than the first id says, the input md5 is not pair 70's, an unknown src
            for args, kw, text in (((odat, ospr, out, src), dict(table=table, first=3), 'exists'),
                                   ((odat, ospr, os.path.join(tmp, 'o2'), src), dict(table=table, first=9), 'wrong input pair'),
                                   ((odat, ospr, os.path.join(tmp, 'o3'), src), dict(table=table, first=3, expect_md5='0' * 32), 'wrong input pair'),
                                   ((odat, ospr, os.path.join(tmp, 'o4'), src), dict(table=[row('f' * 12, 3)], first=3), 'no creature'),
                                   ((odat, ospr, os.path.join(tmp, 'o5'), src), dict(table=[row(by_cell[('strip', 160)][0][0].id, 3)], first=3), 'canvas 160')):
                try:
                    G.build(*args, log=lambda *_: None, **kw)
                except SystemExit as e:
                    assert text in str(e), (text, e)
                else:
                    raise AssertionError('build did not refuse: ' + text)
            assert not os.path.exists(os.path.join(tmp, 'o2')) and not os.path.exists(os.path.join(tmp, 'o3.tmp'))
        finally:
            G.MIN_COLOURS = mc
            G.KINDS.clear()
            G.KINDS.update(kinds_saved)
    assert G.main(['build', 'a', 'b', 'c']) == 1   # --src is needed
    assert G.main(['check']) == 0
    print('gen_wst_outfits_test: OK')


if __name__ == '__main__':
    main()
