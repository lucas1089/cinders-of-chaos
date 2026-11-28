#!/usr/bin/env python3
"""Tests of gen_wst_wear.py (O747): the purchased wings, heads and capes of pair 83, without the packs or the real pair.

    python3 -I client/tools/sprites/gen_wst_wear_test.py      (needs numpy and Pillow: CI uses the fx venv)

Checks: the committed table, sums and generated files (`check`), the table rules on broken copies; the cut of a layer (the
pack's ground shadow out of the back, the alpha a hard cut at 0.5, the back with the solid front on it); then a synthetic
pack (metadata and sheets of one replaced wing, one new wing, one head and one cape, written here) and a synthetic pair:
`table_rows` (designs order, the twin's price and element, new looks dense), the src digest guard, `build` (the replaced
wing keeps its look and loses its displacement, the new looks are appended, every old outfit, item, effect and sprite byte
for byte, the same bytes twice), the refusals (another item count, a built pair, an existing folder, looks not dense), and
`live` (pending below pair 83, a wrong picture and a missing look found); the north move of the pack wings (O779):
`turn_of`, the rules of pack_wear_shift.csv on broken copies, the rows in wear_pieces.lua, `live` with a wrong move; the
east and west moves (O784): `side_of`, three rows per wing, dx 0 on the sides, `live` with a wrong west move.
"""
import copy
import hashlib
import json
import os
import shutil
import struct
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_wst_wear as ww  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


quiet = lambda *a: None  # noqa: E731

# ---- the committed files
check(ww.check(log=quiet) == 0, 'gen_wst_wear.py check passes on the committed table, sums and generated files')
rows = ww.load()
check(ww.problems(rows) == [], 'the committed table has no problem')
check(sum(1 for r in rows if r['design']) == 73, '73 wings replaced in place')
news = [r for r in rows if not r['design']]
check(int(news[0]['look']) == ww.FIRST_NEW == 3589 and news[0]['cat'] == 'wings' and news[0]['wings'] == '128',
      'the new wing is look 3589, wings.xml id 128')
check(int(news[-1]['look']) == 3733, 'the last piece is look 3733')
check(all(r['cost'] in ('150', '200', '250', '300') for r in rows), 'prices 150-300')


def broken(change):
    c = copy.deepcopy(rows)
    change(c)
    return ' '.join(ww.problems(c))


check('twice' in broken(lambda c: c[100].__setitem__('look', c[101]['look'])), 'a look twice is found')
check('anchor tile' in broken(lambda c: c[80].__setitem__('ax', '9')), 'an anchor outside the frame is found')
check('lift' in broken(lambda c: c[0].__setitem__('lift', '1 1')), 'a bad lift is found')
check('element' in broken(lambda c: c[90].__setitem__('element', 'plasma')), 'an unknown element is found')
check('designs.csv' in broken(lambda c: c[0].__setitem__('wings', '999')), 'a replaced wing that is not its designs row is found')
check('wings id' in broken(lambda c: c[100].__setitem__('lift', '0 0')), 'a lift on a head is found')
check('dense' in broken(lambda c: c[-1].__setitem__('look', '9999')), 'looks that are not dense are found')
check('curation keeps' in broken(lambda c: c.pop()), 'a missing piece is found')
for r in rows:
    if r['cat'] != 'wings':
        check(r['wings'] == '' and r['lift'] == '', '%s %s: no wings id or lift' % (r['cat'], r['key']))

# ---- the cut of one layer
fr = np.zeros((4, 4, 4), np.uint8)
fr[0, 0] = (10, 10, 10, 100)     # the pack's soft ground shadow (dark, half see-through): out
fr[0, 1] = (200, 100, 50, 100)   # a half see-through coloured pixel: below 0.5, out
fr[0, 2] = (200, 100, 50, 200)   # above 0.5: solid
fr[0, 3] = (5, 5, 5, 255)        # a dark solid outline: stays
back = ww.clean(fr, True)
check(back[0, 0, 3] == 0 and back[0, 1, 3] == 0, 'the shadow and a faint pixel go')
check(back[0, 2, 3] == 255 and back[0, 3, 3] == 255, 'the solid pixels stay, alpha 255')
check(set(np.unique(back[..., 3])) <= {0, 255}, 'hard alpha')
front = ww.clean(fr, False)
check(front[0, 0, 3] == 0, 'the front: the faint dark pixel goes by the alpha cut')
fb = np.zeros((2, 2, 4), np.uint8)
fb[0, 0] = (1, 2, 3, 255)
ff = np.zeros((2, 2, 4), np.uint8)
ff[0, 0] = (9, 9, 9, 255)
ff[1, 1] = (7, 7, 7, 255)
w = ww.whole(fb, ff)
check(tuple(w[0, 0]) == (9, 9, 9, 255) and tuple(w[1, 1]) == (7, 7, 7, 255), 'y pattern 0: the front on the back')

# ---- a synthetic pack
tmp = tempfile.mkdtemp(prefix='wstwear')
src = os.path.join(tmp, 'src')
PIECES = {
    'wings': [('ember_test_wings', 'Ember Test Wings', 96, 96, 1, 1, 8), ('plasma_fly_wings', 'Plasma Fly Wings', 96, 64, 1, 1, 8)],
    'heads': [('antelope_horns', 'Antelope Horns', 64, 64, 1, 1, 8)],
    'capes': [('academic_gown_cape', 'Academic Gown Cape', 64, 96, 1, 1, 10)],
}


def sheet(fw, fh, frames, seed, layer):
    rng = np.random.RandomState(seed + (7 if layer == 'front' else 0))
    img = np.zeros((8 * fh, frames * fw, 4), np.uint8)
    for r in range(8):
        for f in range(frames):
            y0, x0 = r * fh + 8 + f % 3, f * fw + 6 + r
            img[y0:y0 + 12, x0:x0 + 10, :3] = rng.randint(40, 250, 3)
            img[y0:y0 + 12, x0:x0 + 10, 3] = 255
            if layer == 'back':
                img[r * fh + fh - 4, f * fw + 2:f * fw + 20] = (20, 15, 10, 90)   # a ground shadow
    return img


for ci, (cat, pieces) in enumerate(PIECES.items()):
    effects = []
    for pi, (key, name, fw, fh, ax, ay, frames) in enumerate(pieces):
        files = {}
        for layer in ('back', 'front'):
            rel = 'oblique/32px/%s/%s_%s.png' % (cat, key, layer)
            p = os.path.join(src, cat, 'efeitos', rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            Image.fromarray(sheet(fw, fh, frames, ci * 10 + pi, layer)).save(p)
            files[layer] = rel
        e = {'id': key, 'name': name, 'frames': frames,
             'variants': {'oblique/32': {'frame_w': fw, 'frame_h': fh, 'anchor_tile': [ax, ay], 'files': files}}}
        if cat == 'wings':
            e['lift_px'] = [[0, -(f % 3)] for f in range(frames)]
        effects.append(e)
    os.makedirs(os.path.join(src, cat, 'fontes'), exist_ok=True)
    with open(os.path.join(src, cat, 'fontes', 'metadata.json'), 'w') as f:
        json.dump({'effects': effects}, f)
curation = {cat: {'keep': [p[0] for p in pieces]} for cat, pieces in PIECES.items()}
tdesigns = [{'key': 'drawn_ember', 'name': 'Ember Test Wings', 'look': '2', 'wings': '30'}]
twins = {('head', 'antelope_horns'): (34, 2478, 'Antelope Horns', 'earth', 175)}

trows = ww.table_rows(src, curation, tdesigns, twins)
check([r['key'] for r in trows] == ['ember_test_wings', 'plasma_fly_wings', 'antelope_horns', 'academic_gown_cape'],
      'table order: the replaced wing, the new wing, heads, capes: %s' % [r['key'] for r in trows])
check(trows[0]['look'] == '2' and trows[0]['design'] == 'drawn_ember' and trows[0]['wings'] == '30', 'the replaced wing keeps look and id')
check([r['look'] for r in trows[1:]] == [str(ww.FIRST_NEW + i) for i in range(3)], 'the new looks are dense from 3589')
check(trows[1]['wings'] == '128' and trows[1]['element'] == 'energy' and trows[1]['cost'] == '300', 'the new wing: id 128, energy, 300')
check(trows[2]['aura'] == '34' and trows[2]['cost'] == '175' and trows[2]['element'] == 'earth', 'the head takes its twin aura, price and element')
check(trows[3]['aura'] == '' and trows[3]['cost'] == '200', 'a cape without a twin: 200')
check(trows[0]['lift'].split()[:4] == ['0', '0', '0', '-1'], 'the lift of a wing per frame')
check(ww.lift_of(trows[0])[2] == (0, -2), 'lift_of reads it back')
pats = ww.pictures(src, trows[2])
check(len(pats) == 2 * 4 * 8 and pats[(0, 0, 0)].shape == (64, 64, 4), 'pictures: 2 y patterns x 4 directions x 8 frames of 64 x 64')
check(all(set(np.unique(p[..., 3])) <= {0, 255} for p in pats.values()), 'every picture is hard alpha')
check(all(not (p[..., 3] == 255)[60].any() for k, p in pats.items() if k[0] == 0), 'the ground shadow row is gone')
bad = dict(trows[2], src_back='0' * 12)
try:
    ww.pictures(src, bad)
    check(False, 'a sheet that is not the one of the table is refused')
except SystemExit:
    pass
tsums = {int(r['look']): ww.digest(ww.pictures(src, r)) for r in trows}
check(len(set(tsums.values())) == 4, 'four different pieces')

# ---- a synthetic pair
import check_pair_test as t  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from gen_effects import encode_sprite  # noqa: E402
from import_outfits import parse_body  # noqa: E402

ids, recs = {}, []


def cut(img, w, h):
    out = []
    for hh in range(h):
        for ww_ in range(w):
            tile = np.ascontiguousarray(img[(h - 1 - hh) * 32:(h - hh) * 32, (w - 1 - ww_) * 32:(w - ww_) * 32])
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
disp = bytes([25]) + struct.pack('<hh', 8, 8)
always_disp = bytes([25]) + struct.pack('<hh', 4, 4) + bytes([28])
outfits = [t.entry(disp, [t.group(b * 4, px=4, gtype=0)], outfit=True),
           t.entry(always_disp, [t.group(w2, w=2, h=2, px=4, phases=2, gtype=0)], outfit=True),
           t.entry(disp, [t.group(b * 4, px=4, gtype=0)], outfit=True)]
items = [t.entry(bytes([17]), [t.group(b)])]
effects = [t.entry(b'', [t.group(b)])]
missiles = [t.entry(b'', [t.group(b * 9, px=3, py=3)])]
case = t.Case()
dat_p, spr_p = case.pair(recs, items, outfits, effects, missiles)
FIRST, LAST_ITEM = len(outfits) + 1, 99 + len(items)
prow = copy.deepcopy(trows)
for i, r in enumerate(prow[1:]):
    r['look'] = str(FIRST + i)
psums = {int(r['look']): tsums[int(trows[i]['look'])] for i, r in enumerate(prow)}
out_dir = os.path.join(case.dir, 'out')


def build(out, rws=prow, first=FIRST, last=LAST_ITEM, dat=dat_p, spr=spr_p):
    return ww.build(dat, spr, out, src, rws, first=first, last_item=last, cliff=False, sums=psums, log=quiet)


check(len(ww.live(dat_p, spr_p, prow, psums, assets=83, log=quiet)) == 4, 'the old pair holds none of the pieces')
check(ww.live(dat_p, spr_p, prow, psums, assets=82, log=quiet) == [], 'pending while windows-assets is older than pair 83')
for call, what in ((lambda: build(out_dir, last=LAST_ITEM + 1), 'another item count (no cliff pieces)'),
                   (lambda: build(out_dir, first=FIRST + 1), 'another outfit count'),
                   (lambda: build(out_dir, rws=trows), 'new looks that are not the next free ids'),
                   (lambda: build(case.dir), 'an existing folder')):
    try:
        call()
        check(False, 'build refuses ' + what)
    except SystemExit:
        pass
check(not os.path.exists(out_dir) and not os.path.exists(out_dir + '.tmp'), 'a refused run leaves no folder')
bsums = dict(psums)
bsums[FIRST] = '0' * 64
try:
    ww.build(dat_p, spr_p, out_dir, src, prow, first=FIRST, last_item=LAST_ITEM, cliff=False, sums=bsums, log=quiet)
    check(False, 'pictures that are not those of the sums are refused')
except SystemExit:
    pass

md5 = build(out_dir)
ndat_p, nspr_p = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
with open(ndat_p, 'rb') as f:
    check(hashlib.md5(f.read()).hexdigest() == md5, 'build returns the dat md5')
check(ww.live(ndat_p, nspr_p, prow, psums, assets=83, log=quiet) == [], 'the built pair holds every piece')
od, nd, ospr, nspr = Dat(dat_p), Dat(ndat_p), Spr(spr_p), Spr(nspr_p)
check(nd.counts == (od.counts[0], od.counts[1] + 3, od.counts[2], od.counts[3]), 'three looks appended: %s' % (nd.counts,))
for sid in range(1, ospr.count + 1):
    x, y = ospr.sprite(sid), nspr.sprite(sid)
    check((x is None) == (y is None) and (x is None or np.array_equal(x, y)), 'old sprite %d unchanged' % sid)
for i in (1, 3):
    ta, tb = od.outfit(i), nd.outfit(i)
    check(od.data[ta.raw[0]:ta.raw[1]] == nd.data[tb.raw[0]:tb.raw[1]], 'outfit %d byte for byte' % i)
check(od.data[od.effects[0].raw[0]:] == nd.data[nd.effects[0].raw[0]:], 'effects and missiles byte for byte')
tw = nd.outfit(2)
check('displacement' not in tw.flags and 'animateAlways' in tw.flags, 'the replaced wing: no displacement, still animated')
gs = list(parse_body(nd, tw))
check(len(gs) == 1 and (gs[0].w, gs[0].h, gs[0].py, gs[0].phases) == (3, 3, 2, 8), 'the replaced wing: 3 x 3, back and front, 8 frames')
check(tuple(gs[0].anim[3]) == (ww.FRAME_MS, ww.FRAME_MS) * 8, '83 ms a frame')
cape = nd.outfit(FIRST + 2)
check(set(cape.flags) == {'animateAlways'}, 'a new look: animateAlways only')
gc = list(parse_body(nd, cape))[0]
check((gc.w, gc.h, gc.layers, gc.px, gc.py, gc.phases) == (2, 3, 1, 4, 2, 10), 'the cape: 2 x 3 tiles, 4 directions, 10 frames')
got = ww.pair_pictures(nd, nspr, prow[3])
check(not isinstance(got, str) and ww.digest(got) == psums[FIRST + 2], 'the cape pictures read back')
check(len(ww.live(ndat_p, nspr_p, prow, {**psums, FIRST: '1' * 64}, assets=83, log=quiet)) == 1, 'live sees a wrong picture')
extra = copy.deepcopy(prow) + [dict(prow[3], look=str(FIRST + 3))]
check(len(ww.live(ndat_p, nspr_p, extra, {**psums, FIRST + 3: 'x'}, assets=83, log=quiet)) == 1, 'live sees a missing look')
try:
    ww.build(ndat_p, nspr_p, out_dir + '2', src, prow, first=FIRST, last_item=LAST_ITEM, cliff=False, sums=psums, log=quiet)
    check(False, 'a built pair is not taken again')
except SystemExit:
    pass
again = os.path.join(case.dir, 'again')
build(again)
for name in ('Tibia.dat', 'Tibia.spr'):
    with open(os.path.join(out_dir, name), 'rb') as fa, open(os.path.join(again, name), 'rb') as fb:
        check(fa.read() == fb.read(), 'the same pair twice: ' + name)

# ---- the generated texts from the synthetic table
ct = ww.client_text(prow)
check('{%d,1,1}' % FIRST in ct.replace(' ', '') and 'lifts' in ct, 'wear_pieces.lua: the anchor rows and the lifts')
st = ww.server_text(prow)
check('key = "wings_plasma_fly", id = 128' in st and 'aura = 34' in st, 'chaos_wst_wear_ids.lua: the new wing and the twin aura')

# ---- the north move of the pack wings (O779, base patch 0217)
check(ww.rnd(2.5) == 3 and ww.rnd(-2.5) == -3 and ww.rnd(-0.4) == 0 and ww.rnd(9.2) == 9, 'rnd: half away from zero')


def pic(x, y, w=4, h=4):
    img = np.zeros((96, 96, 4), np.uint8)
    img[y:y + h, x:x + w, 3] = 255
    return img


south, north = pic(40, 30), pic(38, 40)
pats = {(0, 2, 0): south, (0, 2, 1): south, (0, 0, 0): north, (0, 0, 1): north}
check(ww.turn_of(pats, 2) == (2, -10, 10.0), 'turn_of: the north picture 2 px left and 10 px low moves 2 right and 10 up: %s'
      % (ww.turn_of(pats, 2),))
empty = {k: np.zeros((96, 96, 4), np.uint8) for k in pats}
check(ww.turn_of(empty, 2) == (0, 0, 0.0), 'turn_of: an empty view does not move')
east, west = pic(40, 37), pic(40, 33)
pats.update({(0, 1, 0): east, (0, 1, 1): east, (0, 3, 0): west, (0, 3, 1): west})
check(ww.side_of(pats, 2, 1) == (0, -7, 7.0), 'side_of: the east picture 7 px low moves 7 up: %s' % (ww.side_of(pats, 2, 1),))
check(ww.side_of(pats, 2, 3) == (0, -3, 3.0), 'side_of: the west picture 3 px low moves 3 up')
pats[(0, 1, 0)] = pats[(0, 1, 1)] = pic(33, 37)
check(ww.side_of(pats, 2, 1) == (0, -7, 7.0), 'side_of: only the height moves, the wing keeps its place across')
empty = {k: np.zeros((96, 96, 4), np.uint8) for k in pats}
check(ww.side_of(empty, 2, 1) == (0, 0, 0.0) and ww.side_of(empty, 2, 3) == (0, 0, 0.0), 'side_of: an empty view does not move')
check(ww.shift_problems() == [], 'the committed pack_wear_shift.csv keeps its rules')
srows = ww.load_shifts()
wl = [r for r in rows if r['cat'] == 'wings']
check(len(srows) == 3 * len(wl) == 222, 'a north, an east and a west move per pack wing: %d' % len(srows))
check([r['dir'] for r in srows[:3]] == ['north', 'east', 'west'], 'the rows of a wing: north, east, west')
north_rows = [r for r in srows if r['dir'] == 'north']
side_rows = [r for r in srows if r['dir'] != 'north']
pearl = [r for r in north_rows if r['key'] == 'pearl_scallop_wings']
check(len(pearl) == 1 and (pearl[0]['dx'], pearl[0]['dy']) == ('2', '-9'), 'Pearl Scallop Wings: 2 right, 9 up')
check(all(-13 <= int(r['dy']) <= -8 for r in north_rows), 'every pack wing hung 8-13 px low facing north (pair 90)')
check(all(r['dx'] == '0' and -10 <= int(r['dy']) <= 0 for r in side_rows), 'facing east and west: up 0-10 px, never across')
check(all(-10 <= int(r['dy']) <= -5 for r in side_rows if r['dir'] == 'east'), 'facing east every pack wing hung 5-10 px low (pair 90)')
check(all(abs(int(r['dy']) + float(r['hang'])) <= 0.5 for r in srows), 'after the move every view is within half a px of south')


def bad_shift(change):
    c = copy.deepcopy(srows)
    change(c)
    return ' '.join(ww.shift_problems(c, rows))


check('order' in bad_shift(lambda c: c.reverse()), 'a row out of order is found')
check('order' in bad_shift(lambda c: c.pop()), 'a missing wing is found')
check('order' in bad_shift(lambda c: c[0].__setitem__('dir', 'east')), 'a direction out of its place is found')
check('order' in bad_shift(lambda c: c.__delitem__(1)), 'a missing east row is found')
check('dx 0' in bad_shift(lambda c: c[1].update(dx='2')), 'a side move across is found')
check('not down' in bad_shift(lambda c: c[2].update(dy='2', hang='-2.0')), 'a side move down is found')
check(ww.shift_problems([r for r in srows if r['dir'] == 'north'], rows) != [], 'the north-only table of O779 is stale now')
check('whole px' in bad_shift(lambda c: c[0].__setitem__('dx', '1.5')), 'a part px is found')
check('over 24' in bad_shift(lambda c: c[0].update(dx='25')), 'a move over 24 px is found')
check('rounded' in bad_shift(lambda c: c[0].update(dy=str(int(c[0]['dy']) + 2))), 'dy off the hang is found')
check('not down' in bad_shift(lambda c: c[0].update(dy='3', hang='-3.0')), 'a move down is found')
check('columns' in ' '.join(ww.shift_problems([], rows)), 'an empty table is found')
lt = ww.client_text(rows, [{'look': '2442', 'key': 'pearl_scallop_wings', 'dir': 'north', 'dx': '2', 'dy': '-9', 'hang': '9.2'}])
check('shifts = {' in lt and '{2442,0,2,-9}' in lt, 'wear_pieces.lua: the shift rows as look, direction 0, dx, dy')
lt = ww.client_text(rows, [{'look': '2442', 'key': 'pearl_scallop_wings', 'dir': 'north', 'dx': '2', 'dy': '-9', 'hang': '9.2'},
                           {'look': '2442', 'key': 'pearl_scallop_wings', 'dir': 'east', 'dx': '0', 'dy': '-6', 'hang': '6.1'},
                           {'look': '2442', 'key': 'pearl_scallop_wings', 'dir': 'west', 'dx': '0', 'dy': '0', 'hang': '0.3'}])
check('{2442,1,0,-6}' in lt and '{2442,3,' not in lt, 'wear_pieces.lua: an east row as direction 1; a row of no move left out')

# live holds the moves to a pair: the synthetic wings measured, then one row wrong
sp = ww.shift_rows(nd, nspr, prow, log=quiet)
check(sp is not None and len(sp) == 3 * sum(1 for r in prow if r['cat'] == 'wings'), 'shift_rows: three rows per wing of the pair')
check(sp is not None and [r['dir'] for r in sp[:3]] == ['north', 'east', 'west'], 'shift_rows: north, east, west')
check(ww.live(ndat_p, nspr_p, prow, psums, assets=83, log=quiet, shifts=sp) == [], 'live: the moves of the pair pass')
wrong = copy.deepcopy(sp)
wrong[0]['dy'] = str(int(wrong[0]['dy']) - 3)
check(any('pack_wear_shift' in b for b in ww.live(ndat_p, nspr_p, prow, psums, assets=83, log=quiet, shifts=wrong)),
      'live: a wrong north move is found')
wrong = copy.deepcopy(sp)
wrong[2]['dy'] = str(int(wrong[2]['dy']) - 2)
check(any('west' in b for b in ww.live(ndat_p, nspr_p, prow, psums, assets=83, log=quiet, shifts=wrong)),
      'live: a wrong west move is found and named')

# ---- the head pieces and capes moved onto the body (O785, base patch 0219)
torso_img = np.zeros((64, 64), np.uint8)
torso_img[20:60, 30:40] = 255          # a body 40 rows high: torso band rows 32-48, columns 30-39
tx, ty = ww.torso_xy(torso_img)
check(abs(tx - 34.5) < 0.6 and abs(ty - 40.0) < 0.6, 'torso_xy: the median column and the middle of the torso band: %s %s' % (tx, ty))
check(ww.torso_xy(np.zeros((32, 32), np.uint8)) is None, 'torso_xy: nothing visible')
ref = {'heads': [(10.0, 4.0), (11.0, 4.0), (10.0, 4.0), (9.0, 5.0)], 'capes': [(10.0, 12.0)] * 4}
hp = {(0, 2, 0): pic(40, 30), (0, 2, 1): pic(40, 30), (0, 0, 0): pic(38, 33), (0, 0, 1): pic(38, 33),
      (0, 1, 0): pic(44, 28), (0, 1, 1): pic(44, 28), (0, 3, 0): pic(40, 30), (0, 3, 1): pic(40, 30)}
check(ww.layer_of(hp, 2, ref['heads'], 'heads', 0) == (2, -3, -2.0, 3.0), 'layer_of: a head 2 px left and 3 low facing north moves back: %s'
      % (ww.layer_of(hp, 2, ref['heads'], 'heads', 0),))
check(ww.layer_of(hp, 2, ref['heads'], 'heads', 1) == (-3, 2, 3.0, -2.0), 'layer_of: the body\'s own move facing east is taken out: %s'
      % (ww.layer_of(hp, 2, ref['heads'], 'heads', 1),))
check(ww.layer_of(hp, 2, ref['heads'], 'heads', 3) == (-1, 1, 1.0, -1.0), 'layer_of: a head on the same picture as south follows the head facing west')
check(ww.layer_of(hp, 2, ref['capes'], 'capes', 0) == (2, -3, -2.0, 3.0), 'layer_of: a cape facing north moves both ways')
check(ww.layer_of(hp, 2, ref['capes'], 'capes', 1) == (0, 2, 4.0, -2.0), 'layer_of: a cape facing east moves in height only: %s'
      % (ww.layer_of(hp, 2, ref['capes'], 'capes', 1),))
empty = {k: np.zeros((96, 96, 4), np.uint8) for k in hp}
check(ww.layer_of(empty, 2, ref['heads'], 'heads', 0) == (0, 0, 0.0, 0.0), 'layer_of: an empty view does not move')
check(ww.layer_problems() == [], 'the committed pack_wear_layer_shift.csv keeps its rules')
lrows = ww.load_layer_shifts()
lp = [r for r in rows if r['cat'] in ('heads', 'capes')]
check(len(lrows) == 3 * len(lp) == 432, 'a north, an east and a west row per head piece and cape: %d' % len(lrows))
horns = [r for r in lrows if r['key'] == 'antelope_horns' and r['dir'] == 'north']
check(len(horns) == 1 and (horns[0]['dx'], horns[0]['dy'], horns[0]['off_y']) == ('1', '-3', '2.8'),
      'Antelope Horns 3590 facing north: 2.8 px low, moved 1 right and 3 up')
check(all(r['dx'] == '0' for r in lrows if r['cat'] == 'capes' and r['dir'] != 'north'), 'capes facing east or west: never across')
check(all(abs(int(r['dy']) + float(r['off_y'])) <= 0.55 for r in lrows), 'after the move every view is within half a px in height')
summary = ww.layer_summary(lrows)
check(len(summary) == 6 and all('0.5 max' in s or '0.4 max' in s or '0.3 max' in s for s in summary), 'layer_summary: six lines, at most 0.5 px after')


def bad_layer(change):
    c = copy.deepcopy(lrows)
    change(c)
    return ' '.join(ww.layer_problems(c, rows))


check('order' in bad_layer(lambda c: c.reverse()), 'a head / cape row out of order is found')
check('order' in bad_layer(lambda c: c.pop()), 'a missing cape row is found')
check('order' in bad_layer(lambda c: c[0].__setitem__('cat', 'capes')), 'a wrong kind is found')
check('height only' in bad_layer(lambda c: next(r for r in c if r['cat'] == 'capes' and r['dir'] == 'east').update(dx='1')),
      'a cape moved across facing east is found')
check('dx' in bad_layer(lambda c: c[0].update(dx=str(int(c[0]['dx']) + 2))), 'a head dx off its offset is found')
check('dy' in bad_layer(lambda c: c[0].update(dy=str(int(c[0]['dy']) + 2))), 'a dy off its offset is found')
check('whole px' in bad_layer(lambda c: c[0].update(dy='1.5')), 'a part px is found')
check('over 24' in bad_layer(lambda c: c[0].update(dy='25', off_y='-25.0')), 'a move over 24 px is found')
check('columns' in ' '.join(ww.layer_problems([], rows)), 'an empty head / cape table is found')
lt = ww.client_text(rows, [], [{'look': '3590', 'key': 'antelope_horns', 'cat': 'heads', 'dir': 'north', 'dx': '1', 'dy': '-3',
                                'off_x': '-1.3', 'off_y': '2.8'},
                               {'look': '3590', 'key': 'antelope_horns', 'cat': 'heads', 'dir': 'west', 'dx': '0', 'dy': '0',
                                'off_x': '0.4', 'off_y': '0.2'}])
check('wearShifts = {' in lt and '{3590,0,1,-3}' in lt and '{3590,3,' not in lt,
      'wear_pieces.lua: wearShifts as look, direction, dx, dy; a row of no move left out')

# measured on the synthetic pair against its two bodies (outfits 1 and 3), then held by live
bref = ww.body_ref(nd, nspr, [1, 3])
check(bref is not None and len(bref['heads']) == 4 and len(bref['capes']) == 4, 'body_ref: a head and a torso per direction')
check(ww.body_ref(nd, nspr, [FIRST + 50]) is None, 'body_ref: no body in the pair')
lp_rows = ww.layer_rows(nd, nspr, prow, bodies=[1, 3], log=quiet)
check(lp_rows is not None and len(lp_rows) == 3 * sum(1 for r in prow if r['cat'] in ('heads', 'capes')),
      'layer_rows: three rows per head piece and cape of the pair')
check(ww.layer_rows(nd, nspr, prow, bodies=[FIRST + 50], log=quiet) is None, 'layer_rows: none without a body')
check(ww.layer_problems(lp_rows, prow) == [], 'layer_rows: the rows keep the rules')
check(ww.live(ndat_p, nspr_p, prow, psums, assets=83, log=quiet, layer=lp_rows, bodies=[1, 3]) == [], 'live: the head / cape moves pass')
wrong = copy.deepcopy(lp_rows)
wrong[-1]['dy'] = str(int(wrong[-1]['dy']) - 2)
check(any('pack_wear_layer_shift' in b and 'west' in b
          for b in ww.live(ndat_p, nspr_p, prow, psums, assets=83, log=quiet, layer=wrong, bodies=[1, 3])),
      'live: a wrong cape move is found and named')

shutil.rmtree(case.dir, ignore_errors=True)
shutil.rmtree(tmp, ignore_errors=True)
if fails:
    print('%d failures' % fails)
    sys.exit(1)
print('gen_wst_wear_test: all checks passed')
