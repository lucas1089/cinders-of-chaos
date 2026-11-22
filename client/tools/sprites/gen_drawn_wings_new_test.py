#!/usr/bin/env python3
"""Tests of gen_drawn_wings_new.py (O581 phase 2): the six code-drawn wings as new wings looks of pair 78. The table rules and the generated files
(table, sums, wing_anchors.lua, the server's ids file), the pictures of a look, and `build-new` / `live-new` on a synthetic pair: the six
outfits appended, the shape of the O583 wings, every old outfit byte for byte, a pair that is not pair 77 refused, a second run refused.

python3 -I client/tools/sprites/gen_drawn_wings_new_test.py
"""
import copy
import hashlib
import os
import shutil
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_drawn_wings as gd  # noqa: E402
import gen_drawn_wings_families as fm  # noqa: E402
import gen_drawn_wings_new as nw  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


# ---- the table and the files it makes
rows = nw.load()
check(len(rows) == 6 and [r['key'] for r in rows] == list(gd.KEYS), 'six rows, the designs of O581 in order')
check([r['name'] for r in rows] == ['Ember Pinions', 'Ossuary Wings', 'Void Orbit', 'Bladefan', 'Rimeshard', 'Grave Lanterns'], 'the six names')
check([int(r['look']) for r in rows] == list(range(3555, 3561)) and nw.FIRST_NEW == nw.INPUT_OUTFITS + 1 == 3555,
      'looks 3555-3560, after the last outfit of pair 77')
check([int(r['wings']) for r in rows] == list(range(122, 128)), 'wings.xml ids 122-127')
check(nw.problems(rows) == [], 'the table rules: %s' % nw.problems(rows))
old = fm.load()
check(not ({int(r['look']) for r in rows} & {sp.look for sp in old}) and not ({int(r['wings']) for r in rows} & {sp.wings for sp in old}),
      'no id of the 121 old wings is taken')
check(nw.table_text() == open(nw.CSV, encoding='utf-8').read(), 'new_looks.csv is current')
check(nw.table_text() == nw.table_text(), 'the table text is the same twice')
# the rules see a fault
bad = copy.deepcopy(rows)
bad[2]['look'] = '3999'
check(any('looks must be' in b for b in nw.problems(bad)), 'a look out of order is seen')
bad = copy.deepcopy(rows)
bad[0]['wings'] = '121'
check(any('wings ids' in b for b in nw.problems(bad)) and any('taken' in b for b in nw.problems(bad)), 'a wings id of an old wing is seen')
bad = copy.deepcopy(rows)
bad[1]['name'] = old[0].name
check(any('old wings' in b for b in nw.problems(bad)), 'the name of an old wing is seen')
bad = copy.deepcopy(rows)
bad[3]['element'] = 'plasma'
check(any('element' in b for b in nw.problems(bad)), 'an unknown element is seen')
check(any('six designs' in b for b in nw.problems(rows[:5])), 'a missing design is seen')

# the pictures: 128 a look, y 0 the whole wing, y 1 the front; the digests are those of new_looks.sums, all different, none an old wing's
pats = nw.patterns('void_orbit')
check(len(pats) == 2 * 4 * gd.FRAMES, 'two y patterns, four directions, 16 frames')
back, front = gd.render_frame('void_orbit', 'east', 7)
check(np.array_equal(pats[(0, 1, 7)], fm.whole(back, front)) and np.array_equal(pats[(1, 1, 7)], front), 'y0 the whole wing, y1 the front')
sums = nw.digests(rows)
check(sums == nw.read_sums(), 'new_looks.sums is current')
check(len(set(sums.values())) == 6, 'six different pictures')
check(not (set(sums.values()) & set(fm.read_sums().values())), 'none the pictures of an old wing')
check(nw.sums_text(sums) == open(nw.SUMS, encoding='utf-8').read(), 'the sums file is its text')
check(open(fm.ANCHORS, encoding='utf-8').read() == fm.anchors_text(), 'wing_anchors.lua is current')
check(fm.new_looks() == list(range(3555, 3561)) and all(str(v) in open(fm.ANCHORS).read() for v in range(3555, 3561)), 'the six looks are anchored')
check(nw.anchor_looks() == fm.new_looks(), 'the same looks from both readers')
check(open(nw.IDS_LUA, encoding='utf-8').read() == nw.ids_text(), 'the server ids file is current')
check('id = 122, look = 3555, name = "Ember Pinions", element = "fire"' in nw.ids_text() and nw.ids_text().count('{key = "wings_') == 6,
      'the ids file rows')
check(nw.main(['new-table', '--check']) == 0, 'new-table --check passes: the table is idempotent')
check(gd.main(['new-table', '--check']) == 0, 'gen_drawn_wings.py hands the command over')

# ---- the pair step on a synthetic pair
import check_pair_test as t  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from gen_effects import encode_sprite  # noqa: E402
from import_outfits import parse_body  # noqa: E402

ids, recs = {}, []


def cut(img, w, h):
    out = []
    for hh in range(h):
        for ww in range(w):
            tile = np.ascontiguousarray(img[(h - 1 - hh) * 32:(h - hh) * 32, (w - 1 - ww) * 32:(w - ww) * 32])
            rec = encode_sprite(tile)
            if rec is None:
                out.append(0)
                continue
            rec = bytes(rec)
            if rec not in ids:
                recs.append(rec)
                ids[rec] = len(recs)
            out.append(ids[rec])
    return out


body = np.zeros((32, 32, 4), np.uint8)
body[4:30, 10:22] = (90, 60, 40, 255)
b = cut(body, 1, 1)
wing = np.zeros((64, 64, 4), np.uint8)
wing[8:30, 6:20] = (200, 160, 90, 255)
w2 = []
for p in range(2):
    for d in range(4):
        w2 += cut(wing, 2, 2)
disp, always = bytes([25]) + struct.pack('<hh', 8, 8), bytes([28])
outfits = [t.entry(disp, [t.group(b * 4, px=4, gtype=0)], outfit=True),
           t.entry(always, [t.group(w2, w=2, h=2, px=4, phases=2, gtype=0)], outfit=True),
           t.entry(disp, [t.group(b * 4, px=4, gtype=0)], outfit=True),
           t.entry(disp, [t.group(b * 4, px=4, gtype=0)], outfit=True)]
items = [t.entry(bytes([17]), [t.group(b)])]
effects = [t.entry(b'', [t.group(b)])]
missiles = [t.entry(b'', [t.group(b * 9, px=3, py=3)])]
case = t.Case()
dat_p, spr_p = case.pair(recs, items, outfits, effects, missiles)
with open(dat_p, 'rb') as fh:
    md5 = hashlib.md5(fh.read()).hexdigest()
FIRST = len(outfits) + 1
trows = copy.deepcopy(rows)
for i, r in enumerate(trows):
    r['look'] = str(FIRST + i)
tsums = {FIRST + i: fm.digest(nw.patterns(r['key'])) for i, r in enumerate(trows)}
quiet = lambda *a: None  # noqa: E731
out_dir = os.path.join(case.dir, 'out')

check(nw.pair_ok(dat_p, len(outfits), md5, FIRST) is None, 'a pair with the right md5 and outfit count is taken')
check('md5' in (nw.pair_ok(dat_p, len(outfits), '0' * 32, FIRST) or ''), 'another dat md5 is refused')
check('outfits' in (nw.pair_ok(dat_p, len(outfits) + 6, md5, FIRST) or ''), 'a pair that has the looks already is refused')
check(nw.INPUT_DAT_MD5 == '80cdf40aa03fc6097752f2d0822ffae7', 'the md5 of pair 77')

# refusals leave nothing behind
for call, what in ((lambda: nw.build_new(dat_p, spr_p, out_dir, trows, FIRST, '1' * 32, log=quiet), 'another pair (md5)'),
                   (lambda: nw.build_new(dat_p, spr_p, out_dir, trows, FIRST + 1, md5, log=quiet), 'a pair with another outfit count'),
                   (lambda: nw.build_new(dat_p, spr_p, out_dir, rows, FIRST, md5, log=quiet), 'looks that are not the next free ids'),
                   (lambda: nw.build_new(dat_p, spr_p, case.dir, trows, FIRST, md5, log=quiet), 'an existing folder')):
    try:
        call()
        check(False, 'build-new refuses ' + what)
    except SystemExit:
        pass
check(not os.path.exists(out_dir) and not os.path.exists(out_dir + '.tmp'), 'a refused run leaves no folder')
check(len(nw.live(dat_p, spr_p, trows, tsums, log=quiet)) == 6, 'the old pair does not hold the looks')

done = nw.build_new(dat_p, spr_p, out_dir, trows, FIRST, md5, log=quiet)
check(done == list(range(FIRST, FIRST + 6)), 'the new looks: %s' % done)
ndat_p, nspr_p = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
check(nw.live(ndat_p, nspr_p, trows, tsums, log=quiet) == [], 'the built pair holds the six wings')
od, nd, ospr, nspr = Dat(dat_p), Dat(ndat_p), Spr(spr_p), Spr(nspr_p)
check(nd.counts == (od.counts[0], od.counts[1] + 6, od.counts[2], od.counts[3]), 'six outfits added: %s -> %s' % (od.counts, nd.counts))
check(nspr.count > ospr.count, 'sprites appended')
for sid in range(1, ospr.count + 1):
    x, y = ospr.sprite(sid), nspr.sprite(sid)
    check((x is None) == (y is None) and (x is None or np.array_equal(x, y)), 'old sprite %d unchanged' % sid)
for i in range(1, len(outfits) + 1):
    ta, tb = od.outfit(i), nd.outfit(i)
    check(od.data[ta.raw[0]:ta.raw[1]] == nd.data[tb.raw[0]:tb.raw[1]], 'outfit %d byte for byte' % i)
check(od.data[od.effects[0].raw[0]:] == nd.data[nd.effects[0].raw[0]:], 'effects and missiles byte for byte')
for i, r in enumerate(trows):
    look = FIRST + i
    tt = nd.outfit(look)
    check(set(tt.flags) == {'animateAlways'}, 'look %d: animateAlways, no displacement: %s' % (look, dict(tt.flags)))
    gs = list(parse_body(nd, tt))
    check(len(gs) == 1 and (gs[0].w, gs[0].h, gs[0].layers, gs[0].px, gs[0].py, gs[0].pz, gs[0].phases, gs[0].gtype) ==
          (3, 3, 1, 4, 2, 1, gd.FRAMES, 0), 'look %d: 3 x 3, one layer, 4 directions, 2 y patterns, 16 phases' % look)
    check(tuple(gs[0].anim[3]) == (fm.FRAME_MS, fm.FRAME_MS) * gd.FRAMES, 'look %d: 83 ms a phase' % look)
    got = fm.pair_patterns(nd, nspr, look)
    want = nw.patterns(r['key'])
    check(not isinstance(got, str) and all(np.array_equal(want[key], got[key]) for key in want), 'look %d: the pictures read back' % look)
# the live check sees a wrong picture and a missing look
check(len(nw.live(ndat_p, nspr_p, trows, {**tsums, FIRST: '0' * 64}, log=quiet)) == 1, 'live-new sees a wrong picture')
extra = copy.deepcopy(trows) + [dict(trows[0], look=str(FIRST + 6))]
check(len(nw.live(ndat_p, nspr_p, extra, {**tsums, FIRST + 6: 'x'}, log=quiet)) == 1, 'live-new sees a missing look')
# a built pair is not taken again, the same input gives the same bytes
try:
    nw.build_new(ndat_p, nspr_p, out_dir + '2', trows, FIRST, md5, log=quiet)
    check(False, 'a second run on the built pair is refused')
except SystemExit:
    pass
again = os.path.join(case.dir, 'again')
nw.build_new(dat_p, spr_p, again, trows, FIRST, md5, log=quiet)
for name in ('Tibia.dat', 'Tibia.spr'):
    with open(os.path.join(out_dir, name), 'rb') as fa, open(os.path.join(again, name), 'rb') as fb:
        check(fa.read() == fb.read(), 'the same pair twice: ' + name)
shutil.rmtree(case.dir)

if fails:
    print('%d failures' % fails)
    sys.exit(1)
print('gen_drawn_wings_new_test: all checks passed')
