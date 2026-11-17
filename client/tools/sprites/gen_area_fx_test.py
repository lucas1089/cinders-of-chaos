#!/usr/bin/env python3
"""Tests of gen_area_fx.py (O607): the table rules, the pair refusal and the blank padding up to 5299, a refill cut into
the canvas of its pair 36 spec on synthetic frames, the beam reach, the generated server files, the pair 51 lists.
O609, the long beams: the table of lengths, a synthetic beam (a start flare, a body with light that flows, a tip) made
longer on a straight and a diagonal heading: one start, one tip, the body and its flow run on pixel for pixel; a body that
sways is bent so its middle line does not step; the view cut; the rows' rules.
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
    ok(len(rows) == 70, '70 effects')
    new = [r for r in rows if r['kind'] == 'new']
    ok([r['id'] for r in new] == [5300, 5301, 5302], 'the new effects are 5300..5302')
    ok(G.last_new() == 5302, 'the O607 step ends at 5302')
    ok(all(r['id'] < 4743 for r in rows if r['kind'] == 'refill'), 'a refill is an id of pair 36')
    ok(sum(r['role'] == 'beam' and r['kind'] == 'refill' for r in rows) == 32, 'four beams of eight headings')
    long = [r for r in rows if r['kind'] == 'long']
    ok([r['id'] for r in long] == list(range(5303, 5331)), 'the long beams are 5303..5330, after the O607 block')
    ok(rows[-28:] == long, 'the long beams are the last rows')
    for base, ln in G.LONG:
        for d in G.DIRS:
            name = G.long_name(base, ln, d)
            ok(any(r['name'] == name for r in rows), name + ': the beam of that length and heading is a row')
            natural = ln == G.NATURAL and d in G.STRAIGHT
            ok((name == base + '_' + d) == natural, name + ': the pack\'s own beam only on a straight line of 3 tiles')
    ok(sum(r['len'] == 3 for r in long) == 4, 'a line of 3 tiles needs a beam of its own on the diagonals only')
    ok(all(r['role'] == 'beam' and r['dir'] and r['name'] == G.long_name(r['name'][:r['name'].rindex('_l')], r['len'], r['dir'])
           for r in long), 'a long beam is named for its beam, length and heading')
    ok([r['dir'] for r in rows if r['kind'] == 'refill' and r['name'].startswith('mega_soul_chain_')] == G.DIRS, 'the headings in the order of pair 36')
    for change, why in ((lambda b: b[1].update(id=5305), 'a hole in the new block'),
                        (lambda b: b[0].update(src='fire_pack.png'), 'src must be 12 hex'),
                        (lambda b: b[3].update(id=5303), 'a refill above pair 36'),
                        (lambda b: b[4].update(name=b[3]['name']), 'a name twice'),
                        (lambda b: b[3].update(dir='n'), 'a heading on an area burst'),
                        (lambda b: b[0].update(element='shadow'), 'an unknown element'),
                        (lambda b: b[-1].update(len=''), 'a long beam with no length'),
                        (lambda b: b[0].update(len=4), 'a length on a burst'),
                        (lambda b: b[-1].update(id=5400), 'a hole before a long beam'),
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
        if x['role'] == 'beam' and x['kind'] == 'refill':
            ok(2 <= G.reach(x) <= 4, x['name'] + ': a beam of 2 to 4 tiles')


def test_server_files():
    rows = G.read_spec()
    lua = G.lua_text(rows)
    ok(lua.count('{id = ') == len(rows), 'one Lua row per effect')
    ok('ab_fire_rain = {id = 5300, dx = 3, dy = 2' in lua and 'first = 5300, count = 31, natural = 3' in lua, 'the new block in the ids file')
    ok('[6] = {n = "mega_soul_chain_l6_n", ne = "mega_soul_chain_l6_ne", e = "mega_soul_chain_l6_e"' in lua, 'the lengths: a long beam per heading')
    ok('[3] = {n = "mega_sunbeam_lance_n", ne = "mega_sunbeam_lance_l3_ne", e = "mega_sunbeam_lance_e"' in lua,
       'the lengths: 3 tiles is the pack\'s own beam on a straight heading')
    ok('mega_soul_chain_l6_e = {id = 5305,' in lua and 'refill = false, len = 6, reach = 6}' in lua, 'a long beam row has its length and reach')
    ok(lua.count('len = ') == 28 and 'mega_glacier_breath = {' not in lua.split('lengths = {')[1], 'only the beams the spells draw are long')
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


def synth(d, total, sway=0, count=12):
    """a beam towards d in beam coordinates: a grey start flare 10 px long and 11 wide, a body 7 px wide whose light runs
    out 8 px a frame in pulses 32 px apart, a red tip of 12 px, `total` px in all; sway: the body swings that many px"""
    import math
    import numpy as np
    sx, sy = G.STEP[d]
    n2 = sx * sx + sy * sy
    v0, c0 = -4 * n2, -G.PADC - 8 * n2
    S = np.zeros((count, (total + 4) * n2, 2 * (G.PADC + 8 * n2) + 1, 4), np.uint8)
    for f in range(count):
        for vi in range(S.shape[1]):
            u = (vi + v0) / n2
            if u < 0 or u >= total:
                continue
            body = 10 <= u < total - 12
            half = 5 if u < 10 else (3 if body else 4)
            mid = int(round(sway * math.sin(2 * math.pi * (u / 48.0 - f / 12.0)))) if body else 0
            col = (200, 200, 200) if u < 10 else ((200, 40, 40) if not body else ((255, 220, 100) if (u - 8 * f) % 32 < 8 else (180, 140, 60)))
            for k in range(-half, half + 1):
                c = (mid + k) * n2
                if (vi + v0 + c) % n2 == 0:
                    S[f, vi, c - c0] = col + (255,)
    return S, v0, c0, n2


def count(S, col):
    return int((S[..., :3] == col).all(-1).sum())


def test_long_beam():
    import numpy as np
    for d in ('e', 'n', 'sw', 'ne'):
        S, v0, c0, n2 = synth(d, 110)
        frames, anchor = G.from_strip(S, v0, c0, d)
        back = G.to_strip(frames, anchor, d)
        again, anchor_b = G.from_strip(*back[:3], d)
        ok(back[3] == n2 and anchor_b == anchor and all(np.array_equal(x, y) for x, y in zip(frames, again)),
           d + ': pictures and beam coordinates turn into each other')
        ok(G.extent(frames, anchor, d)[0] == 0 and abs(G.extent(frames, anchor, d)[1] - 109.25) < 0.5, d + ': the art runs from the caster\'s tile to 110 px: %s' % (
            G.extent(frames, anchor, d),))
        speed = G.flow(S, v0, n2, 10, 98)
        ok(speed is not None and abs(speed - 8) < 0.5, d + ': the light flows out 8 px a frame: %s' % speed)
        errors = G.seam_errors(S, v0, n2, 10, 98, False, speed)
        ok(errors and all(o == G.flow_step(q, speed, 12) for q, o in errors), d + ': only the frame step that lets the flow run on')
        ok(errors[(32, 8)][0] == 0 and errors[(64, 4)][0] == 0, d + ': a period of whole pulses has a seam that matches')
        ok(min(e for (q, o), (e, c, bend) in errors.items() if q % 8) > 0, d + ': a period the flow does not fit shows at the seam')
        pick = G.choose_seam(errors, 64, 0)
        ok(pick[1:5] == (64, 1, 4, 0) and pick[5] == 0, d + ': 64 px more is one period with a seam that matches: %s' % (pick,))
        pick = G.choose_seam(errors, 160, 0)
        ok(pick[1] * pick[2] == 160 and pick[2] > 1 and pick[4] == 0, d + ': 160 px more is whole periods: %s' % (pick,))
        near = G.choose_seam(errors, 61, 2)
        ok(G.choose_seam(errors, 61, 0) is None and near and 0 < abs(near[1] * near[2] - 61) <= 2, d + ': only a diagonal may miss its length, by 2 px at most')
        for extra in (64, 160):
            c, q, n, o, e, bend = G.choose_seam(errors, extra, 0)
            T = G.stretch(S, v0, n2, c, q, n, o, False)
            want = synth(d, 110 + extra)[0]
            ok(T.shape == want.shape and np.array_equal(T, want), d + ' +%d px: the same pixels as a beam drawn that long, every frame' % extra)
            ok(count(T, (200, 200, 200)) == count(S, (200, 200, 200)), d + ': one start flare')
            ok(count(T, (200, 40, 40)) == count(S, (200, 40, 40)), d + ': one tip')
            jumps, wide = G.seam_check(S, T, v0, n2, c, q, n, 10, 98)
            ok(max(jumps) == 0 and wide[0] <= wide[1], d + ': no step and no flare inside the new body')
            long, anchor2 = G.from_strip(T, v0, c0, d)
            ok(G.extent(long, anchor2, d)[1] == G.extent(frames, anchor, d)[1] + extra, d + ': the tip lies %d px further out' % extra)
    ok(G.flow_step(32, 8.0, 12) == 8 and G.flow_step(32, -8.0, 12) == 4, 'a copy 32 px out plays 4 frames behind a flow that runs out, ahead of one that runs in')
    ok(G.flow_step(20, 8.0, 12) is None and G.flow_step(23, 5.66, 12) == 8, 'a period must be whole frames of flow (0.35 let by)')
    ok(G.flow(synth('e', 110)[0][:1].repeat(12, 0), -4, 1, 10, 98) is None, 'a beam that stands still has no flow')
    # a body that sways: bent at the seams
    S, v0, c0, n2 = synth('e', 110, sway=4)
    errors = G.seam_errors(S, v0, n2, 10, 98, True, G.flow(S, v0, n2, 10, 98))
    c, q, n, o, e, bend = G.choose_seam(errors, 96, 0)
    plain, bent = G.stretch(S, v0, n2, c, q, n, o, False), G.stretch(S, v0, n2, c, q, n, o, True)
    jp, jb = max(G.seam_check(S, plain, v0, n2, c, q, n, 10, 98)[0]), max(G.seam_check(S, bent, v0, n2, c, q, n, 10, 98)[0])
    ok(jp >= 3 and jb <= G.JUMP_MAX, 'a swaying body steps %.1f px at a plain seam, %.1f px when bent' % (jp, jb))
    ok(count(bent, (200, 40, 40)) == count(S, (200, 40, 40)) and count(bent, (200, 200, 200)) == count(S, (200, 200, 200)),
       'the bend keeps the one start and the one tip whole')
    ok(int((bent[..., 3] > 0).sum()) == int((plain[..., 3] > 0).sum()), 'the bend moves pixels, it makes none')
    again = G.stretch(S, v0, n2, c, q, n, o, True)
    ok(np.array_equal(bent, again), 'the same bytes twice')


def test_long_rows():
    import numpy as np
    # the view cut: art past 8 tiles east or 7 south of the caster's tile goes
    f = np.zeros((400, 400, 4), np.uint8)
    f[40:48, 40:360] = (9, 9, 9, 255)                       # the caster's tile at 32, 32: a bar 8 px .. 328 px east of it
    cut, lost = G.view_cut([f], (32, 32))
    ok(cut[0][:, :32 + 9 * 32, 3].sum() == f[:, :32 + 9 * 32, 3].sum() and cut[0][:, 32 + 9 * 32:].max() == 0, 'east of the ninth column the art is cut')
    ok(abs(lost - 40 / 320.0) < 1e-9, 'the share that went')
    g = np.zeros((400, 400, 4), np.uint8)
    g[40:360, 40:48] = (9, 9, 9, 255)
    ok(G.view_cut([g], (32, 32))[0][0][32 + 8 * 32:].max() == 0 and G.view_cut([g], (32, 32))[0][0][:32 + 8 * 32, :, 3].any(), 'south of the eighth row too')
    ok(G.view_cut([f[:, :200]], (32, 32))[1] == 0, 'a beam inside the view loses nothing')
    # the rules of a long row
    good = dict(name='x_l8_s', kind='long', dir='s', len='8', dx='0', dy='7', reach='7', cut='c36 q32 n5 o8 e0.132 b0.0 view-11%')
    ok(G.long_row_errors(good) == [], 'a beam cut at the view may stop one tile short: %s' % G.long_row_errors(good))
    for change, why in ((dict(reach='6'), 'two tiles short'), (dict(dy='8'), 'a far tile the caster does not see'),
                        (dict(dir='e', dx='9', dy='0', reach='8', cut='c36 q32 n5 o8 e0.132 b0.0'), 'nine tiles east'),
                        (dict(cut='c36 q32 n5 o8 e0.132 b0.0'), 'short with no view cut'),
                        (dict(cut='c36 q32 n5 o8 e0.900 b0.0 view-11%'), 'a seam over the limit'),
                        (dict(cut='c36 q32 n0 o8 e0.100 b0.0 view-11%'), 'no period'), (dict(cut=''), 'no cut'), (dict(reach=''), 'no reach')):
        ok(G.long_row_errors(dict(good, **change)), why + ' is found')
    ok(G.long_row_errors(dict(good, dir='n', dy='0', reach='8', cut='c59 q32 n5 o8 e0.140 b0.0')) == [], 'a whole beam')
    for r in G.read_spec():
        if r['kind'] == 'long':
            ok(G.long_row_errors(r) == [], r['name'] + ': %s' % G.long_row_errors(r))
            ok(int(r['w']) <= G.LONG_TILES and int(r['h']) <= G.LONG_TILES and r['phases'] == '13' and r['ms'] == '83', r['name'] + ': canvas and frames')
        else:
            ok(not r['len'] and not r['reach'] and not r['cut'], r['name'] + ': only a long beam has a length, a reach and a cut')
    short = [r['name'] for r in G.read_spec() if r['kind'] == 'long' and r['reach'] != r['len']]
    ok(short == ['mega_sunbeam_lance_l8_se', 'mega_sunbeam_lance_l8_s', 'mega_sunbeam_lance_l8_sw'],
       'only the 8 tile beam towards the south is cut at the view: %s' % short)


def test_pair51():
    rows = G.read_spec()
    ok(G.pair51_errors(rows) == [], 'the refilled ids left the removed list of pair 51 and are on its keep list')
    fake = [dict(rows[0], kind='refill', id='560', name='x')]
    ok(G.pair51_errors(fake), 'a refill that is not on the keep list under its name is found')
    import prune_pair
    keep = prune_pair.keep_list()
    ok(all(('effect', int(r['id'])) in keep for r in rows if r['kind'] == 'refill'), 'prune_pair.py keeps them')


def main():
    for t in (test_table, test_refills_are_pair36, test_padding, test_fixed_canvas, test_reach, test_long_beam, test_long_rows,
              test_server_files, test_pair51):
        t()
    print('gen_area_fx_test: %d checks passed' % N[0])


if __name__ == '__main__':
    main()
