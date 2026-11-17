#!/usr/bin/env python3
"""Tests of gen_area_fx.py (O607): the table rules, the pair refusal and the blank padding up to 5299, a refill cut into
the canvas of its pair 36 spec on synthetic frames, the beam reach, the generated server files, the pair 51 lists.
No pack art and no pair: python3 -I client/tools/sprites/gen_area_fx_test.py (numpy, Pillow)."""
import os
import struct
import sys
from types import SimpleNamespace as NS

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_area_fx as G  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def test_table():
    rows = G.pieces()
    ok(G.table_errors(rows) == [], 'the table of the script holds its rules: %s' % G.table_errors(rows))
    ok(len(rows) == 42, '42 effects')
    new = [r for r in rows if r['kind'] == 'new']
    ok([r['id'] for r in new] == [5300, 5301, 5302], 'the new effects are 5300..5302')
    ok(all(r['id'] < 4743 for r in rows if r['kind'] == 'refill'), 'a refill is an id of pair 36')
    ok(sum(r['role'] == 'beam' for r in rows) == 32, 'four beams of eight headings')
    ok([r['dir'] for r in rows if r['name'].startswith('mega_soul_chain_')] == G.DIRS, 'the headings in the order of pair 36')
    for change, why in ((lambda b: b[1].update(id=5305), 'a hole in the new block'),
                        (lambda b: b[0].update(src='fire_pack.png'), 'src must be 12 hex'),
                        (lambda b: b[3].update(id=5303), 'a refill above pair 36'),
                        (lambda b: b[4].update(name=b[3]['name']), 'a name twice'),
                        (lambda b: b[3].update(dir='n'), 'a heading on an area burst'),
                        (lambda b: b[0].update(element='shadow'), 'an unknown element'),
                        (lambda b: b[0].update(set='zz'), 'an unknown set')):
        bad = [dict(r) for r in rows]
        change(bad)
        ok(G.table_errors(bad), why + ' is found')
    spec = G.read_spec()
    ok([r['name'] for r in spec] == [r['name'] for r in rows], 'area_fx.csv lists the rows in order')
    ok(list(G.read_sums()) == [r['name'] for r in rows], 'one sum per effect, in order')
    ok(len(set(G.read_sums().values())) == len(rows), 'no two strips are the same picture')
    ok(G.check() == 0, 'check passes on the repository')


def test_refills_are_pair36():
    old, names = G.pack36_rows(), G.pack36_ids()
    for r in G.read_spec():
        if r['kind'] == 'refill':
            o = old[r['name']]
            ok(all(r[k] == o[k] for k in ('w', 'h', 'phases', 'ms', 'dx', 'dy')), r['name'] + ': the pair 36 canvas')
            ok(names[r['name']] == (int(r['id']), int(r['dx']), int(r['dy'])), r['name'] + ': the pair 36 id and offset')
        else:
            ok(r['name'] not in names and r['name'] not in old, r['name'] + ': a new name')


def test_padding():
    ok(G.pad_plan(4742) == (4743, 557), 'pair 72: 4743..5299 are padded')
    ok(G.pad_plan(4745) == (4746, 554), 'after the O596 step: from its last effect')
    ok(G.pad_plan(5250) == (5251, 49), 'after a step that ends at 5250: only the rest')
    ok(G.pad_plan(5299) == (5300, 0), 'a pair that ends at 5299: nothing to pad')
    ok(G.pad_plan(5300) is None and G.pad_plan(5302) is None, 'already imported: refused')
    ok(G.pad_plan(4741) is None, 'an older pair: refused')
    ok(len(G.BLANK) == 12 and G.BLANK[0] == 0xFF and G.BLANK[-4:] == b'\0\0\0\0', 'a blank effect: one 1x1 frame, sprite 0')
    # a fake dat: header, two "effects", two "missiles"
    saved = (G.MIN_EFFECTS, G.FIRST)
    G.MIN_EFFECTS, G.FIRST = 2, 6
    try:
        head = b'SIGN' + struct.pack('<HHHH', 100, 1, 2, 2)
        e1, e2, m1, m2 = b'\xffEFFECT-ONE', b'\xffE2', b'\xffMISSILE-1', b'\xffM2'
        data = head + b'ITEMS+OUTFITS' + e1 + e2 + m1 + m2
        at = len(head) + len(b'ITEMS+OUTFITS')
        dat = NS(data=data,
                 effects=[NS(raw=(at, at + len(e1))), NS(raw=(at + len(e1), at + len(e1) + len(e2)))],
                 missiles=[NS(raw=(at + len(e1) + len(e2), at + len(e1) + len(e2) + len(m1))), NS(raw=(0, 0))])
        out = G.padded_dat(dat)
        ok(struct.unpack_from('<HHHH', out, 4) == (100, 1, 5, 2), 'the effect count grows to FIRST - 1, the others stay')
        ok(out[12:] == b'ITEMS+OUTFITS' + e1 + e2 + G.BLANK * 3 + m1 + m2, 'the blanks sit after the last effect, the rest is byte for byte')
    finally:
        G.MIN_EFFECTS, G.FIRST = saved


def fake_pack():
    """the functions of gen_pack36_fx.py that the cut uses, on plain arrays: no dither, the frame placed by its anchor"""
    import numpy as np

    def trim(frames):
        return [f for f in frames if f[..., 3].any()]

    def dissolve(f, keep):
        g = f.copy()
        ys, xs = np.nonzero(g[..., 3])
        drop = (xs * 7 + ys * 13) % 100 >= keep * 100
        g[ys[drop], xs[drop]] = 0
        return g

    def place(f, anchor, point, left, top, w, h, name):
        ys, xs = np.nonzero(f[..., 3])
        x0, y0 = anchor[0] - left * 32, anchor[1] - top * 32
        if xs.min() < x0 or ys.min() < y0 or xs.max() >= x0 + w * 32 or ys.max() >= y0 + h * 32:
            raise SystemExit('%s: art outside the canvas' % name)
        return f[y0:y0 + h * 32, x0:x0 + w * 32]

    return NS(trim=trim, FADE=3, G=NS(dissolve=dissolve, place=place))


def test_fixed_canvas():
    import numpy as np
    P = fake_pack()
    anchor = (96, 96)                       # the anchor tile's corner inside a 256 px frame

    def frame(x0, y0, x1, y1):
        f = np.zeros((256, 256, 4), np.uint8)
        f[y0:y1, x0:x1] = (200, 40, 40, 255)
        return f
    frames = [frame(100, 100, 120, 120), frame(70, 80, 150, 150), frame(40, 70, 180, 120), np.zeros((256, 256, 4), np.uint8)]
    # a 5 x 3 canvas, the anchor tile 2 from the right and 1 from the bottom
    strip = G.fixed_strip(P, 't', frames, anchor, anchor, False, 5, 3, 2, 1, 6)
    ok(strip.shape == (96, 5 * 32 * 6, 4), 'the strip is phases x the canvas of the spec')
    ok(strip[:, 3 * 160:].max() == 0, 'the phases after the art are empty')
    ok(strip[:, :160, 3].sum() == 20 * 20 * 255, 'the first frame is whole')
    ys, xs = np.nonzero(strip[:, :160, 3])
    ok((xs.min(), ys.min()) == (100 - 96 + 2 * 32, 100 - 96 + 32), 'the anchor tile sits dx from the right, dy from the bottom')
    again = G.fixed_strip(P, 't', frames, anchor, anchor, False, 5, 3, 2, 1, 6)
    ok(G.digest(strip) == G.digest(again), 'the same bytes twice')
    for bad, why in (((5, 3, 2, 1, 3), 'more frames than the phases of pair 36'),
                     ((3, 3, 1, 1, 6), 'art wider than the canvas')):
        try:
            G.fixed_strip(P, 't', frames, anchor, anchor, False, *bad)
            ok(False, why + ' is refused')
        except SystemExit:
            ok(True, why)
    # a loop: its last three frames dissolve
    loop = [frame(70, 80, 150, 150)] * 8
    s = G.fixed_strip(P, 't', loop, anchor, anchor, True, 5, 3, 2, 1, 9)
    mass = [int((s[:, i * 160:(i + 1) * 160, 3] > 0).sum()) for i in range(9)]
    ok(mass[4] == mass[0] and mass[5] > mass[6] > mass[7] > 0 and mass[8] == 0, 'a loop fades out over its last frames: %s' % mass)


def test_reach():
    def r(d, w, h, dx, dy):
        return G.reach(dict(dir=d, w=w, h=h, dx=dx, dy=dy))
    ok(r('e', 4, 1, 3, 0) == 3 and r('w', 4, 1, 0, 0) == 3, 'a 4 x 1 canvas reaches 3 tiles from the caster')
    ok(r('n', 1, 4, 0, 0) == 3 and r('s', 2, 4, 0, 3) == 3, 'north and south')
    ok(r('se', 3, 3, 2, 2) == 2 and r('nw', 3, 3, 0, 0) == 2, 'a diagonal: the shorter side')
    ok(r('ne', 4, 3, 3, 0) == 2, 'a diagonal in a canvas that is not square')
    ok(r('e', 1, 1, 0, 0) == 1, 'never 0')
    rows = G.read_spec()
    for x in rows:
        if x['role'] == 'beam':
            ok(2 <= G.reach(x) <= 4, x['name'] + ': a beam of 2 to 4 tiles')


def test_server_files():
    rows = G.read_spec()
    lua = G.lua_text(rows)
    ok(lua.count('{id = ') == len(rows), 'one Lua row per effect')
    ok('ab_fire_rain = {id = 5300, dx = 3, dy = 2' in lua and 'first = 5300, count = 3' in lua, 'the new block in the ids file')
    ok('mega_soul_chain = {n = 3, ne = 2, e = 3, se = 2, s = 3, sw = 2, w = 3, nw = 2}' in lua, 'the beam reaches')
    ok(lua.startswith('-- GENERATED') and 'ChaosVfx.' not in lua, 'a plain table: no other generator reads it as ChaosVfx rows')
    tags = G.tags_text(rows)
    ok(G.tags_text(rows) == tags and open(G.TAGS, encoding='utf-8', newline='').read() == tags, 'the tags are written and stable')
    lines = tags.splitlines()[1:]
    ok([int(l.split(',')[0]) for l in lines] == sorted(int(l.split(',')[0]) for l in lines), 'the tags stay in id order')
    for r in rows:
        ok('%s,%s,%s' % (r['id'], r['name'], r['element']) in lines, r['name'] + ': tagged')
    cat = G.catalog_text(rows).splitlines()
    ok(len(cat) == 6 and cat[1].startswith('effect,5300,ab_fire_rain,7x6,"3,2"'), 'the five area bursts are a ground catalogue')
    ok(G.ids(True) == 0, 'the generated files are committed up to date')
    for p in (G.SPEC, G.SUMS, G.LUA, G.CATALOG, os.path.abspath(G.__file__), os.path.abspath(__file__)):
        text = open(p, encoding='utf-8').read().lower()
        ok(not any(w in text for w in G.PACK_WORDS), os.path.basename(p) + ' names no pack')


def test_pair51():
    rows = G.read_spec()
    ok(G.pair51_errors(rows) == [], 'the refilled ids left the removed list of pair 51 and are on its keep list')
    fake = [dict(rows[0], kind='refill', id='560', name='x')]
    ok(G.pair51_errors(fake), 'a refill that is not on the keep list under its name is found')
    import prune_pair
    keep = prune_pair.keep_list()
    ok(all(('effect', int(r['id'])) in keep for r in rows if r['kind'] == 'refill'), 'prune_pair.py keeps them')


def main():
    for t in (test_table, test_refills_are_pair36, test_padding, test_fixed_canvas, test_reach, test_server_files, test_pair51):
        t()
    print('gen_area_fx_test: %d checks passed' % N[0])


if __name__ == '__main__':
    main()
