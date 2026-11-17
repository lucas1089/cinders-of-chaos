#!/usr/bin/env python3
"""Test of gen_source_wings.py (O627): python3 -I client/tools/sprites/gen_source_wings_test.py

The committed table, sums, server lib and anchors file against the rules, every rule with a failing case, and the measures, `fit`,
`measured`, `build`, `live` and the preview on a synthetic source pair and a small synthetic input pair drawn here: the O495 centre
(two masses or the mean), the stray specks, the canvas (3x3, up to 5x5, never sampled), one whole pixel shift a direction, the
layers (south and east whole in y 0, north and west whole in y 1 and their opaque pixels in y 0), the outfit shape (one group of type 1,
NxN, one layer, 4 directions, 2 y patterns, the source's phases and milliseconds, animateAlways only), every slot reading back as drawn,
the anchors, wrong input pairs and an existing output folder refused, and `live` holding the pair to the digest, the layers, the
centres and the pixel count. No source file and no real pair needed. Needs numpy and Pillow (the fx venv of CI). Nothing drawn here
is art of any pair."""
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_source_wings as G  # noqa: E402
import gen_wst_outfits as W  # noqa: E402
import check_pair_test as T  # noqa: E402
import gen_wst_outfits_test as WT  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from gen_effects import encode_sprite, tiles_of  # noqa: E402
from import_outfits import NEW_BYTE, parse_body  # noqa: E402


def row(src, new, **kw):
    r = {'src': str(src), 'srchash': 'a' * 12, 'new': str(new), 'key': 'bloodmoon', 'name': 'Bloodmoon Wings', 'kind': 'aura', 'size': '3x3',
         'frames': '6', 'ms': '100', 'anchor': '-16:2', 'shift': '-12:3:-16:-11', 'centres': '-3:-3:-5:-2', 'strays': '0', 'pixels': '5000',
         'dirs': '4', 'solid': '88', 'dip': '96', 'aspect': '133', 'floor': '0', 'src_light': 'none', 'note': ''}
    r.update({k: str(v) for k, v in kw.items()})
    return r


def blank(n):
    return np.zeros((32 * n, 32 * n, 4), np.uint8)


def rect(img, x0, y0, x1, y1, colour, alpha=255):
    img[y0:y1, x0:x1, :3] = colour
    img[y0:y1, x0:x1, 3] = alpha


def fake_wing(wid, size, frames, ms=100, disp=(0, 0), light=None):
    """a Wing of a source canvas of `size` tiles: frames(d, p) -> RGBA array; 4 phases"""
    w = G.Wing()
    w.id, w.w, w.h, w.layers, w.px, w.py, w.pz, w.phases = wid, size, size, 1, 4, 1, 1, 4
    w.durs = tuple([ms] * 8)
    w.disp, w.light = disp, light
    w.frames = {d: [G.clean(frames(d, p)) for p in range(4)] for d in range(4)}
    return w


def lobes(size, left=(20, 40), right=(60, 80), top=30, bottom=60, moves=True):
    """two opaque lobes (a wing pair with a gap) and a glow skirt: the art of wing A; the y wiggles by phase"""
    def make(d, p):
        a = blank(size)
        dy = p if moves else 0
        rect(a, left[0] + d, top + dy, left[1] + d, bottom + dy, (200, 30 + 20 * d, 40), 255)
        rect(a, right[0] + d, top + dy, right[1] + d, bottom + dy, (30, 200, 60 + 20 * d), 255)
        rect(a, left[0] + d, bottom + dy, left[1] + d, bottom + dy + 2, (255, 255, 255), 120)   # a glow skirt under the left lobe
        return a
    return make


def src_pair(tmp, wings):
    """a synthetic source pair: {outfit id: (size, frames(d, p) -> RGBA, ms, flags)}; filler outfits below the highest id.
    Returns the folder (the pair sits one folder down, as the real one does)."""
    recs, idx = [], {}

    def sid(tile):
        rec = encode_sprite(np.ascontiguousarray(tile))
        if rec is None:
            return 0
        if rec not in idx:
            recs.append(bytes(rec))
            idx[rec] = len(recs)
        return idx[rec]
    outfits = []
    filler = T.entry(b'', [T.group([0], gtype=0)], outfit=True)
    for i in range(1, max(wings) + 1):
        if i not in wings:
            outfits.append(filler)
            continue
        size, frames, ms, flags = wings[i]
        phases = 4
        sp = [0] * (size * size * 4 * phases)
        for p in range(phases):
            for d in range(4):
                tiles = tiles_of(G.clean(frames(d, p)), size, size)
                for hh in range(size):
                    for ww in range(size):
                        sp[((((p * 1 + 0) * 1 + 0) * 4 + d) * size + hh) * size + ww] = sid(tiles[(ww, hh)])
        outfits.append(T.entry(flags, [T.group(sp, w=size, h=size, px=4, phases=phases, gtype=0, anim=(0, 0, 0, [ms] * 8))], outfit=True))
    dat = T.dat_bytes([], outfits, [T.entry(b'', [T.group([0])])], [])
    d = os.path.join(tmp, 'src', 'pt1')
    os.makedirs(d)
    open(os.path.join(d, 'Tibia.dat'), 'wb').write(dat)
    open(os.path.join(d, 'Tibia.spr'), 'wb').write(T.spr_bytes(recs))
    return os.path.join(tmp, 'src')


def main():
    # ---- the committed table, sums, server lib and anchors
    t = G.rows()
    assert G.problems() == [], G.problems()
    assert G.lib_problems() == [], G.lib_problems()
    assert G.anchors_problems() == [], G.anchors_problems()
    assert len(t) == 15 and [int(r['new']) for r in t] == list(range(3530, 3545)) and G.FIRST_NEW == 3530 == G.OUTFITS_73 + 1 and G.PAIR == 74
    assert [int(r['src']) for r in t] == [906, 903, 940, 912, 902, 943, 908, 942, 913, 941, 904, 1240, 915, 1221, 1220]
    assert [r['src'] for r in t] == [str(a) for a, _b, _c, _d in G.ROWS]
    assert set(G.read_sums()) == {r['new'] for r in t} and all(len(v) == 64 for v in G.read_sums().values())
    assert len(set(G.read_sums().values())) == 15, 'two outfits with one digest'
    assert len({r['srchash'] for r in t}) == 15 and len({r['name'] for r in t}) == 15 and len({r['key'] for r in t}) == 15
    kinds = [r['kind'] for r in t]
    assert (kinds.count('wings'), kinds.count('borderline'), kinds.count('aura')) == (2, 3, 10), kinds
    assert [r['src'] for r in t if r['kind'] == 'wings'] == ['1240', '915'] and [r['src'] for r in t if r['dirs'] == '2'] == ['1220']
    assert [r['size'] for r in t].count('4x4') == 2 and {r['size'] for r in t} == {'3x3', '4x4'}
    assert all(r['strays'] in ('0', '4') for r in t) and sum(int(r['strays']) for r in t) == 20
    assert [r['src'] for r in t if r['src_light'] != 'none'] == ['906', '912', '908', '913', '904']
    assert [r['src'] for r in t if r['note']] == ['1240']
    # every view of the committed rows stands on the anchor column to the tenth of a pixel (the whole pixel shift)
    assert all(max(abs(v) for v in G.ints_of(r['centres'], 4)) <= 6 for r in t)
    pictures = [f for f in os.listdir(G.ART) if f.startswith('source_wings') and f.endswith(('.png', '.gif', '.mp4', '.bmp'))]
    assert pictures == [], 'a picture of the source in art_import: %s' % pictures

    # ---- every rule has a case
    good = [row(906, 3530), row(903, 3531, key='cinderveil', name='Cinderveil Wings')]
    sums = {'3530': 'x', '3531': 'y'}
    assert G.problems(good, sums, want=None) == []
    for bad, text in (
            ([row(906, 3530), row(903, 3533, key='cinderveil', name='Cinderveil Wings')], 'must be 3531'),
            ([row('x', 3530), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'not an outfit id'),
            ([row(906, 3530, srchash='xyz'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'not 12 hex'),
            ([row(906, 3530), row(906, 3531, key='cinderveil', name='Cinderveil Wings')], 'on two rows'),
            ([row(906, 3530), row(903, 3531)], 'used twice'),
            ([row(906, 3530, key='Blood Moon'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'lower case letters'),
            ([row(906, 3530, name='Bloodmoon'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'ending in Wings'),
            ([row(906, 3530, kind='fish'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'kind fish'),
            ([row(906, 3530, size='2x2'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'not 3x3, 4x4 or 5x5'),
            ([row(906, 3530, size='3x4'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'not 3x3, 4x4 or 5x5'),
            ([row(906, 3530, anchor='-32:2'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'has -16:2'),
            ([row(906, 3530, size='4x4', anchor='-16:2'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'has -32:2'),
            ([row(906, 3530, frames=0), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'frames'),
            ([row(906, 3530, ms=5), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'lasts'),
            ([row(906, 3530, shift='3'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'four whole numbers of px'),
            ([row(906, 3530, centres='1:2:3'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'four whole numbers'),
            ([row(906, 3530, centres='0:0:30:0'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'off the anchor column'),
            ([row(906, 3530, strays='some'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'strays'),
            ([row(906, 3530, dirs=5), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'dirs'),
            ([row(906, 3530, pixels=0), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'no pixels'),
            ([row(906, 3530, kind='wings'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'not what the shape numbers say'),
            ([row(906, 3530, src_light='big'), row(903, 3531, key='cinderveil', name='Cinderveil Wings')], 'src_light')):
        p = G.problems(bad, sums, want=None)
        assert any(text in x for x in p), (text, p)
    assert any('name other outfits' in x for x in G.problems(good, {'3530': 'x'}, want=None))
    assert any('not ROWS' in x for x in G.problems(good, sums))
    assert G.problems([row(906, 5, kind='wings', solid=40, dip=60), row(903, 6, key='cinderveil', name='Cinderveil Wings')], {'5': 'x', '6': 'y'},
                      first=5, want=None) == []
    # the shape kinds
    assert [G.kind_of(*a) for a in ((4, 88, 96, 0), (4, 90, 98, 0), (2, 50, 50, 0), (4, 75, 97, 24), (4, 76, 91, 0), (4, 74, 87, 0), (4, 66, 66, 7),
                                    (4, 43, 62, 0), (4, 70, 85, 15), (4, 69, 85, 0))] == \
        ['aura', 'aura', 'aura', 'aura', 'borderline', 'borderline', 'wings', 'wings', 'borderline', 'wings']
    # the anchors and the prices
    assert G.anchor_of(3) == (-16, 2) and G.anchor_of(4) == (-32, 2) and G.anchor_of(5) == (-48, 2) and G.anchor_text(4) == '-32:2'
    assert G.price_of(3) == 250 and G.price_of(4) == 300 and G.price_of(5) == 300
    assert G.tiles_of_size('3x3') == 3 and G.tiles_of_size('5x5') == 5 and G.tiles_of_size('2x2') is None and G.tiles_of_size('3x4') is None
    # the server lib rule: a changed name or price is a problem, so is the wrong gate
    lib = G.lib_rows()
    assert len(lib) == 15 and lib[0] == ('voidbloom', 122, 3530, 'Voidbloom Wings', 'dark', 250) and lib[12][5] == 300
    assert G.lib_problems(t, lib[:-1]) and G.lib_problems(t, lib[:3] + [('x',) + lib[3][1:]] + lib[4:])
    # the anchors file: a changed row is a problem
    assert G.anchors_text(t) == open(G.ANCHORS, encoding='utf-8', newline='').read()
    assert G.anchors_text(t[:1]) != G.anchors_text(t) and '{3542, -32, 2}' in G.anchors_text(t)

    # ---- the measures
    col = np.zeros((96, 96, 4), np.uint8)
    for x, a in ((10, 255), (11, 255), (60, 255)):
        col[:, x, 3] = a
    frames = [col]
    c, m = G.centre_x(frames)
    assert m == 'two' and abs(c - ((10.5 + 60) / 2.0)) < 1e-9, (c, m)        # two masses with a gap: the midpoint of their means
    lone = np.zeros((96, 96, 4), np.uint8)
    lone[:, 10, 3] = 255
    lone[:, 40, 3] = 4                                                     # the right mass is under 25%: the mean of everything
    c, m = G.centre_x([lone])
    assert m == 'mean' and 10 < c < 11, (c, m)
    one = np.zeros((96, 96, 4), np.uint8)
    one[:, 20:41, 3] = 255
    c, m = G.centre_x([one])
    assert m == 'mean' and c == 30.0
    soft = np.zeros((96, 96, 4), np.uint8)
    soft[:, 20:30, 3] = 255
    soft[:, 30:40, 3] = 100                                                 # alpha weighted
    assert G.centre_x([soft])[0] > 24.5 and G.centre_x([soft])[1] == 'mean'
    # stray specks: a box with 4 pixels or fewer, none solid; a solid pixel, a bigger crumb and one near the wing stay
    a = np.zeros((96, 96, 4), np.uint8)
    rect(a, 40, 40, 70, 60, (9, 9, 9))
    a[2:4, 2:4] = (7, 7, 7, 90)                                             # 4 glow pixels far away: a stray
    a[90, 90] = (7, 7, 7, 255)                                              # a solid pixel far away: kept
    a[80:83, 5:8] = (7, 7, 7, 90)                                           # 9 glow pixels: kept
    a[38, 40] = (7, 7, 7, 90)                                               # a glow pixel next to the wing: kept
    s = G.strays_of(a)
    assert s.sum() == 4 and s[2:4, 2:4].all() and not s[90, 90] and not s[80:83, 5:8].any() and not s[38, 40]
    assert not G.strays_of(np.zeros((96, 96, 4), np.uint8)).any()
    # box_sum
    m = np.zeros((9, 9), bool)
    m[4, 4] = True
    bs = G.box_sum(m, 2)
    assert bs[4, 4] == 1 and bs[2, 2] == 1 and bs[1, 1] == 0 and bs[6, 6] == 1 and bs[7, 7] == 0 and bs.sum() == 25
    # the hull and the shape numbers: a filled oval-ish block is solid, two lobes are not
    block = np.zeros((96, 96, 4), np.uint8)
    rect(block, 20, 30, 80, 70, (1, 2, 3))
    solid, dip, aspect, near = G.shape_numbers(block, (48, 64))
    assert solid >= 95 and dip >= 95 and aspect == 150 and near == 0, (solid, dip, aspect, near)
    pair = np.zeros((96, 96, 4), np.uint8)
    rect(pair, 10, 30, 30, 70, (1, 2, 3))
    rect(pair, 66, 30, 86, 70, (1, 2, 3))
    solid, dip, aspect, near = G.shape_numbers(pair, (48, 100))
    assert solid < 60 and dip < 20 and near > 30, (solid, dip, aspect, near)
    # layers: south and east before the body, north and west after it, with their opaque pixels also in y 0
    img = np.zeros((96, 96, 4), np.uint8)
    rect(img, 10, 10, 20, 20, (5, 6, 7), 255)
    rect(img, 30, 10, 40, 20, (5, 6, 7), 100)
    for d in (G.SOUTH, G.EAST):
        y0, y1 = G.layers_of(d, img)
        assert np.array_equal(y0, img) and not y1.any()
    for d in (G.NORTH, G.WEST):
        y0, y1 = G.layers_of(d, img)
        assert np.array_equal(y1, img) and (y0[..., 3] == 255).sum() == 100 and (y0[..., 3] == 100).sum() == 0 and np.array_equal(y0[10:20, 10:20], img[10:20, 10:20])

    # ---- fit
    wing_a = fake_wing(7, 3, lobes(3))                                      # lobes at 20..40 and 60..80: centre 50 + the direction
    f = G.fit(wing_a)
    assert f['tiles'] == 3 and f['strays'] == 0 and len(f['shifts']) == 4
    for d in range(4):
        assert abs(f['centres'][d]) <= 0.51, (d, f['centres'])
        assert f['methods'][d] == 'two'
    # the lobes move 1 px a direction, so do the shifts the other way (a half pixel rounds to even: one pixel of play)
    assert all(abs((f['shifts'][d] - f['shifts'][0]) + d) <= 1 for d in range(4)) and f['shifts'][3] < f['shifts'][0], f['shifts']
    # the art is only moved: the same pixels, no colour touched, no vertical shift
    for d in range(4):
        for p in range(4):
            src = wing_a.frames[d][p]
            ys, xs = np.nonzero(src[..., 3])
            dst = f['placed'][d][p]
            assert np.array_equal(dst[ys, xs + f['shifts'][d]], src[ys, xs]) and (dst[..., 3] > 0).sum() == len(ys)
    # a 2x2 source goes on 3x3; the dat displacement is taken out (a displacement of 8 px up moves the art 8 px up)
    wing_b = fake_wing(8, 2, lambda d, p: (lambda a: (rect(a, 20, 20, 44, 44, (9, 9, 9)), a)[1])(blank(2)), disp=(0, 8))
    wb = G.fit(wing_b)
    assert wb['tiles'] == 3
    ys, xs = np.nonzero(wb['placed'][2][0][..., 3])
    assert ys.min() == 20 + 32 - 8 and ys.max() == 43 + 32 - 8, (ys.min(), ys.max())
    # a wider art goes on 4x4, an art that no canvas holds stops
    wide = fake_wing(9, 4, lobes(4, left=(10, 40), right=(90, 120), top=60, bottom=100))
    wf = G.fit(wide)
    assert wf['tiles'] == 4 and max(abs(c) for c in wf['centres']) <= 0.51
    heavy = fake_wing(10, 5, lambda d, p: (lambda a: (rect(a, 0, 100, 10, 120, (3, 3, 3)), rect(a, 11, 100, 155, 101, (3, 3, 3), 40), a)[2])(blank(5)))
    try:
        G.fit(heavy)
        raise AssertionError('an art no canvas holds was fitted')
    except ValueError as e:
        assert 'does not fit' in str(e)
    empty = fake_wing(11, 3, lambda d, p: blank(3) if d == 1 else lobes(3)(d, p))
    try:
        G.fit(empty)
        raise AssertionError('an empty view was fitted')
    except ValueError as e:
        assert 'empty' in str(e)
    # the stray of the source is dropped and counted
    def with_stray(d, p):
        a = lobes(3)(d, p)
        if d == 3 and p == 1:
            a[2:4, 2:4] = (7, 7, 7, 90)
        return a
    ws = G.fit(fake_wing(12, 3, with_stray))
    assert ws['strays'] == 4 and ws['tiles'] == 3

    # ---- measure, groups, the dat flags
    r, f = G.measure(wing_a)
    assert r['size'] == '3x3' and r['frames'] == '4' and r['ms'] == '100' and r['anchor'] == '-16:2' and r['dirs'] == '4' and r['src_light'] == 'none'
    assert r['shift'] == ':'.join(str(v) for v in f['shifts']) and r['kind'] in G.KINDS and int(r['pixels']) == G.count_pixels(f['placed'])
    assert G.measure(fake_wing(13, 3, lobes(3), light=(10, 191)))[0]['src_light'] == '10:191'
    uneven = fake_wing(14, 3, lobes(3))
    uneven.durs = (100, 100, 100, 100, 200, 200, 200, 200)
    try:
        G.measure(uneven)
        raise AssertionError('uneven phases measured')
    except ValueError as e:
        assert 'same time' in str(e)
    assert G.src_hash(wing_a) == G.src_hash(fake_wing(7, 3, lobes(3))) and G.src_hash(wing_a) != G.src_hash(fake_wing(7, 3, lobes(3, moves=False)))
    specs = G.groups_of(f, 100, 4)
    g, tiles = specs[0]
    assert (g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases) == (1, 3, 3, 96, 1, 4, 2, 1, 4) and g.anim == (0, 0, 0, (100,) * 8)
    assert len(tiles) == 3 * 3 * 4 * 2 * 4 == len(g.sprites)
    assert G.flags_of() == (bytes([NEW_BYTE['animateAlways']]), {'animateAlways': True})

    # ---- the pair: a synthetic source and a small input pair
    flag_always = bytes([NEW_BYTE['animateAlways']])
    flag_light = bytes([NEW_BYTE['light']]) + struct.pack('<HH', 10, 191)
    with tempfile.TemporaryDirectory() as tmp:
        wings = {2: (3, lobes(3), 100, flag_always + flag_light), 3: (2, wing_b.frames and (lambda d, p: wing_b.frames[d][p]), 250, flag_always),
                 4: (4, lobes(4, left=(10, 40), right=(90, 120), top=60, bottom=100), 80, flag_always)}
        src = src_pair(tmp, wings)
        want = ((2, 'aaaa', 'Aaaa Wings', 'dark'), (3, 'bbbb', 'Bbbb Wings', 'fire'), (4, 'cccc', 'Cccc Wings', 'light'))
        assert G.find_pair(src)[0].endswith('Tibia.dat')
        ws_ = G.load_source(src, [2, 3, 4])
        assert ws_[2].light == (10, 191) and ws_[3].w == 2 and ws_[4].w == 4 and ws_[2].durs == (100,) * 8 and ws_[3].durs == (250,) * 8
        assert np.array_equal(ws_[2].frames[1][2], G.clean(lobes(3)(1, 2)))
        try:
            G.load_source(src, [9])
            raise AssertionError('a missing outfit was loaded')
        except SystemExit as e:
            assert 'no outfit 9' in str(e)
        try:
            G.find_pair(os.path.join(tmp, 'nothing'))
            raise AssertionError('a missing pair was found')
        except SystemExit:
            pass
        ms = G.measured(src, want, first=3)
        assert [r['new'] for r, _f, _w in ms] == ['3', '4', '5'] and [r['size'] for r, _f, _w in ms] == ['3x3', '3x3', '4x4']
        assert [r['src_light'] for r, _f, _w in ms] == ['10:191', 'none', 'none'] and [r['ms'] for r, _f, _w in ms] == ['100', '250', '80']
        table = [r for r, _f, _w in ms]
        sums = G.pack_sums(ms)
        assert G.problems(table, sums, first=3, want=None) == [], G.problems(table, sums, first=3, want=None)
        assert G.table_text(table).splitlines()[0] == ','.join(G.HEADER) and G.table_text(table).count('\n') == 4
        again = G.pack_sums(G.measured(src, want, first=3))
        assert again == sums, 'the same bytes twice'
        odat, ospr = WT.input_pair(tmp)
        out = os.path.join(tmp, 'out')
        ids = G.build(odat, ospr, out, src, want=want, first=3, log=lambda *_a: None)
        assert ids == [3, 4, 5]
        d, sp = Dat(os.path.join(out, 'Tibia.dat')), Spr(os.path.join(out, 'Tibia.spr'))
        assert len(d.outfits) == 5
        for (r, f, _w), nid in zip(ms, ids):
            th = d.outfit(nid)
            assert dict(th.flags) == {'animateAlways': True}, th.flags                        # the source light is not carried
            gs = parse_body(d, th)
            n = int(r['size'][0])
            assert len(gs) == 1 and (gs[0].gtype, gs[0].w, gs[0].h, gs[0].layers, gs[0].px, gs[0].py, gs[0].pz) == (1, n, n, 1, 4, 2, 1)
            assert gs[0].phases == 4 and tuple(gs[0].anim[3]) == (int(r['ms']),) * 8
        assert G.live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'), table, sums, log=lambda *_a: None) == []
        # live holds the pair to the sums, the table and the rule
        lv = lambda tb, sm: G.live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'), tb, sm, log=lambda *_a: None)   # noqa: E731
        bad = dict(sums)
        bad['4'] = 'f' * 64
        assert any('source_wings.sums' in x for x in lv(table, bad))
        assert any('pixels in its sprites' in x for x in lv([table[0], dict(table[1], pixels='5'), table[2]], sums))
        assert any('not 4 phases of 99 ms' in x or 'phases of' in x for x in lv([table[0], dict(table[1], ms='99'), table[2]], sums))
        assert any('not one group' in x for x in lv([table[0], dict(table[1], size='4x4', anchor='-32:2'), table[2]], sums))
        assert any('not one group' in x for x in lv([table[0], table[1], dict(table[2], size='3x3', anchor='-16:2')], sums))
        assert any('the pair has' in x for x in G.live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'), table + [dict(table[0], new='9')], sums,
                                                       log=lambda *_a: None))
        # a pair with the pictures of another wing: the digest, the layers or the centre says so
        swapped = os.path.join(tmp, 'swapped')
        wings2 = dict(wings)
        wings2[2] = (3, lobes(3, left=(10, 25), right=(70, 85)), 100, flag_always)
        os.makedirs(os.path.join(tmp, 'x2'))
        G.build(odat, ospr, swapped, src_pair(os.path.join(tmp, 'x2'), wings2), want=want, first=3, log=lambda *_a: None)
        assert any('source_wings.sums' in x for x in G.live(os.path.join(swapped, 'Tibia.dat'), os.path.join(swapped, 'Tibia.spr'), table, sums,
                                                              log=lambda *_a: None))
        # refusals: an existing output folder, an input with the wrong number of outfits, a wrong first id
        for args, text in (((odat, ospr, out, src), 'exists'), ((odat, ospr, os.path.join(tmp, 'o2'), src), 'wrong input pair')):
            try:
                kw = dict(want=want, first=3 if text == 'exists' else 9, log=lambda *_a: None)
                G.build(*args, **kw)
                raise AssertionError('not refused: ' + text)
            except SystemExit as e:
                assert text in str(e), (text, str(e))
        try:
            G.build(odat, ospr, os.path.join(tmp, 'o3'), src, want=((9, 'zzzz', 'Zzzz Wings', 'dark'),), first=3, log=lambda *_a: None)
            raise AssertionError('a missing source outfit was built')
        except SystemExit as e:
            assert 'no outfit 9' in str(e)
        assert not os.path.exists(os.path.join(tmp, 'o2')) and not os.path.exists(os.path.join(tmp, 'o3'))

        # ---- the preview: an MP4 of even size
        if os.system('ffmpeg -version > /dev/null 2>&1') == 0:
            mp4 = os.path.join(tmp, 'p.mp4')
            G.preview(mp4, src, seconds=1, fps=4, want=want, log=lambda *_a: None)
            assert os.path.getsize(mp4) > 1000
            probe = os.popen('ffprobe -v error -select_streams v:0 -show_entries stream=width,height,pix_fmt,codec_name -of csv=p=0 "%s"' % mp4).read().strip()
            w, h = G.CELL * G.SCALE * 4, G.CELL * G.SCALE * 2 + 40
            assert w % 2 == 0 and h % 2 == 0
            if probe:
                assert probe == 'h264,%d,%d,yuv420p' % (w, h), probe
        # the stand-in body and the compositor
        fig = G.figure(G.SOUTH)
        assert fig.shape == (96, 96, 4) and fig[64, 48, 3] == 255 and fig[10, 10, 3] == 0
        cell = G.view_cell(dict(tiles=3, placed={d: [np.zeros((96, 96, 4), np.uint8)] for d in range(4)}, phase=lambda s: 0), G.NORTH, True, 5)
        assert cell.shape == (G.CELL, G.CELL, 3)
    print('gen_source_wings_test: OK')


if __name__ == '__main__':
    main()
