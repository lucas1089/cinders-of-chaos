#!/usr/bin/env python3
"""Tests of gen_cliff_art.py (O746): the table rules, the drawing (the same bytes twice, alpha 0 / 255, the theme palettes, every piece
holds style_check, the faces tile side by side and the corners continue them, the lip pieces join), the committed table and sums
current, the face rule of the planner on small footprints, and `build` / `live` on a small synthetic pair (42 items appended, a pair
of another md5 or item count refused). No real pair: python3 -I client/tools/sprites/gen_cliff_art_test.py (numpy, Pillow)."""
import csv
import hashlib
import os
import shutil
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_cliff_art as G  # noqa: E402
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402

sys.path.insert(0, os.path.join(G.ROOT, 'server', 'tools'))
import area_plan_plateau as PL  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def test_table():
    rows = G.pieces()
    ok(G.table_errors(rows) == [], 'the table holds its rules: %s' % G.table_errors(rows))
    ok(len(rows) == 42 and [r['client_id'] for r in rows] == list(range(44564, 44606)), '42 pieces at 44564..44605')
    ok(G.FIRST == G.EXPECT_ITEMS + 1 == 44564 and G.PAIR == 83, 'appended after the 44,563 items of pair 82, joins pair 83')
    ok(G.PAIR82_DAT_MD5 == 'ee8c32fc87be4372f4668b635148b9bf', 'build takes the pair 82 dat only')
    ok(all(r['server_id'] == r['client_id'] + 4000 for r in rows), 'server id = client id + 4000')
    ok(G.LIP == ('n', 'e', 's', 'w', 'cnw', 'cne', 'csw', 'cse', 'dnw', 'dne', 'dse', 'dsw'), "the lip in the planner's piece order")
    import gen_editor_brushes as GE
    ok(tuple(G.LIP) == GE.SLOTS, 'the same order as the editor brushes (gen_editor_brushes.SLOTS)')
    ok(set(G.LIP) >= set(PL.MR.border_pieces(1, 0, 0, 1, 0, 0, 0, 0) + PL.MR.border_pieces(0, 0, 0, 0, 1, 1, 1, 1)),
       'every name map_tile_rules.border_pieces gives is a lip piece')
    for mut, what in ((lambda r: r[1].update(client_id=9), 'a hole in the ids'),
                      (lambda r: r[2].update(name='stone'), 'a name without "cliff "'),
                      (lambda r: r[3].update(server_id=1), 'a server id off the rule'),
                      (lambda r: r[4].update(kind='decor'), 'a piece that is no border'),
                      (lambda r: r[5].update(theme='x'), 'a palette of another theme'),
                      (lambda r: r[6].update(key=r[0]['key']), 'a key twice')):
        bad = [dict(r) for r in rows]
        mut(bad)
        ok(G.table_errors(bad), what + ' is found')
    spec = list(csv.DictReader(open(G.SPEC, encoding='utf-8')))
    ok([[str(r[k]) for k in G.FIELDS] for r in rows] == [[r[k] for k in G.FIELDS] for r in spec], 'cliff_art.csv is the table')


def test_draw():
    a, b = G.draw_all(), G.draw_all()
    ok(all(np.array_equal(a[k], b[k]) for k in a), 'the same bytes twice')
    ok(G.sums_text(a) == open(G.SUMS, encoding='utf-8').read(), 'cliff_art.sums is current')
    ok(len({G.digest(v) for v in a.values()}) == 42, 'no two pieces alike')
    for r in G.pieces():
        p = a[r['key']]
        ok(G.piece_problems(r['key'], p, r['piece']) == [], '%s holds the rules: %s' % (r['key'], G.piece_problems(r['key'], p, r['piece'])))
        ok(G.style_problems(r['key'], p, r['piece'], r['palette']) == [], '%s passes style_check: %s'
           % (r['key'], G.style_problems(r['key'], p, r['piece'], r['palette'])))
        cols = {tuple(c) for c in p[p[..., 3] > 0][:, :3].tolist()}
        allowed = {G.unhex(h) for h in G.PALETTES[r['palette']]['colours'] + G.PALETTES[r['palette']]['outline']}
        ok(cols <= allowed, '%s: only the colours of its palette' % r['key'])
        ok(len(cols) >= 11, '%s: 11 colours or more (%d)' % (r['key'], len(cols)))
    ok(G.seam_problems(a) == [], 'the pieces join: %s' % G.seam_problems(a))
    # the south face runs on: a, b, a side by side is one band (the edge columns of both variants agree)
    s = np.concatenate([a['stone_face_s_a'], a['stone_face_s_b'], a['stone_face_s_a']], axis=1)
    jumps = [int(np.abs(s[:, x].astype(int) - s[:, x + 1].astype(int))[..., :3].mean()) for x in range(95)]
    ok(max(jumps[31], jumps[63]) <= 3 * max(1, int(np.median(jumps))) + 20, 'no seam where two south faces meet %s' % jumps[30:34])
    # stone is grey, earth is brown
    st = a['stone_face_s_a'][..., :3].astype(int)
    ea = a['earth_face_s_a'][..., :3].astype(int)
    ok(np.abs(st[..., 0] - st[..., 2]).mean() < 12, 'stone is grey')
    ok((ea[..., 0] - ea[..., 2]).mean() > 20, 'earth is brown (red over blue)')
    # light: the south face is lighter at its top than at its foot, the east face darker than the south face
    def L(p):
        q = p.astype(int)
        return (299 * q[..., 0] + 587 * q[..., 1] + 114 * q[..., 2]) // 1000
    ok(L(a['stone_face_s_a'])[:8].mean() > L(a['stone_face_s_a'])[-8:].mean() + 15, 'the south face is lit at the top')
    ok(L(a['stone_face_e_a']).mean() < L(a['stone_face_s_a']).mean(), 'the east face is darker than the south face')
    ok(G.check(quiet=True) == 0, 'check passes on the repository')


def test_no_art_read():
    src = open(os.path.join(HERE, 'gen_cliff_art.py'), encoding='utf-8').read()
    body = src[src.index('def south_face'):src.index('# ---------------------------------------------------------------------------------------------------'
                                                     '---------- files')]
    ok('open(' not in body and 'Image.open' not in body, 'the drawing reads no file')
    ok('http' not in src and 'requests' not in src, 'no service')


def test_face_rule():
    box = {(x, y) for x in range(5) for y in range(4)}
    faces, ends = PL.cliff_face_pieces(box)
    ok(set(faces) == {(x, 3) for x in range(5)} | {(4, y) for y in range(4)}, 'the south row and the east column show rock')
    ok(faces[(4, 3)] == 'outer_se' and ends == {(-1, 3): ['outer_sw'], (4, -1): ['outer_ne']}, 'the corner and the two ends')
    step = box | {(5, 0), (5, 1)}                       # the east edge steps back at the bottom: an inner corner
    faces, _ends = PL.cliff_face_pieces(step)
    ok(faces[(4, 1)].startswith('inner_se_'), 'a step of the east edge makes an inner corner %s' % faces)
    ok({p for p in faces.values()} <= set(G.FACE), 'the planner only asks for pieces of the set')


def synthetic():
    recs = [t.record({0: t.RED, 1: t.RED, 40: (10, 20, 30, 255)}), t.record({5: (200, 100, 50, 128)}),
            t.record({0: t.YELLOW, 1: t.RED}), t.record({100 + k: (10 * k, 2, 3, 255) for k in range(20)}),
            t.record({200: (9, 9, 9, 255)}), t.record({300: (7, 7, 7, 255)})]
    items = [t.entry(bytes([17]), [t.group([1])]), t.entry(bytes([17]), [t.group([4])])]       # 100, 101
    base = t.good_parts()
    return recs, items, base[2], base[3], base[4]


def test_pair():
    c = t.Case()
    try:
        recs, items, outfits, effects, missiles = synthetic()
        dat, spr = c.pair(recs, items, outfits, effects, missiles)
        md5 = hashlib.md5(open(dat, 'rb').read()).hexdigest()
        out = os.path.join(c.dir, 'out')
        ok(G.build(dat, spr, out, want_md5=md5, first=102, expect=101) == 0, 'build on the synthetic pair')
        od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
        ok(G.live(od, os_, first=102) == [], 'live: the pair holds the 42 pieces pixel for pixel')
        old = cp.parse_dat(open(dat, 'rb').read())[2]
        new = cp.parse_dat(open(od, 'rb').read())[2]
        ok(len(new['item']) == len(old['item']) + 42, '42 items appended')
        ok(len(new['outfit']) == len(old['outfit']) and len(new['effect']) == len(old['effect'])
           and len(new['missile']) == len(old['missile']), 'outfits, effects and missiles untouched')
        r = cp.check(od, os_, auras={2}, old=(dat, spr))
        ok(r.ok, 'the append-only guard passes: ' + r.text())
        ok(G.live(dat, spr, first=102), 'live: the input pair is not the output')
        out2 = os.path.join(c.dir, 'out2')
        G.build(dat, spr, out2, want_md5=md5, first=102, expect=101)
        ok(open(os.path.join(out2, 'Tibia.dat'), 'rb').read() == open(od, 'rb').read() and
           open(os.path.join(out2, 'Tibia.spr'), 'rb').read() == open(os_, 'rb').read(), 'same inputs, same pair')
        for kw, what in ((dict(), 'a dat that is not pair 82'), (dict(want_md5=md5, expect=44563), 'a wrong item count')):
            try:
                G.build(dat, spr, os.path.join(c.dir, 'o3'), **dict(dict(first=102, expect=101), **kw))
                ok(False, what + ' is refused')
            except SystemExit:
                ok(True, what + ' is refused')
    finally:
        shutil.rmtree(c.dir, ignore_errors=True)


for f in (test_table, test_draw, test_no_art_read, test_face_rule, test_pair):
    f()
print('gen_cliff_art_test: OK (%d checks)' % N[0])
