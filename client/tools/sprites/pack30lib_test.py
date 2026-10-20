#!/usr/bin/env python3
"""python3 -I client/tools/sprites/pack30lib_test.py : pack30lib.py on synthetic generated images only (no pack image is
read), plus the committed audit tables (pack30_packs.csv, pack30_overrides.csv, pack30_<cat>.files) against each other
and against the names rule. Needs numpy and Pillow (the fx venv)."""
import hashlib
import os
import re
import sys
import tempfile
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'tools', 'ci'))
import pack30lib as P  # noqa: E402
from PIL import Image  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def raises(fn, what, exc=P.PackError):
    try:
        fn()
    except exc:
        return
    check(False, what)


def img(w, h, rects=(), colour=(200, 100, 50, 255)):
    a = np.zeros((h, w, 4), np.uint8)
    for x0, y0, x1, y1 in rects:
        a[y0:y1, x0:x1] = colour
    return a


# ------------------------------------------------------------------------------------------------ pixels
a = np.zeros((2, 2, 4), np.uint8)
a[0, 0] = (200, 10, 10, 5)
a[1, 1] = (10, 200, 10, 200)
c = P.clean_alpha(a)
check(not c[0, 0].any() and tuple(c[1, 1]) == (10, 200, 10, 200) and a[0, 0, 0] == 200, 'clean_alpha: faint cleared, input kept')

s = img(96, 32)
for i in range(3):
    s[:, i * 32] = (i + 1, 0, 0, 255)
fr = P.strip_frames(s, 32)
check(len(fr) == 3 and fr[2][0, 0, 0] == 3 and fr[0].shape == (32, 32, 4), 'strip_frames: 3 frames in order')
raises(lambda: P.strip_frames(img(100, 32), 32), 'strip_frames: not whole frames')
raises(lambda: P.strip_frames(img(96, 33), 32, 32), 'strip_frames: wrong height')

m = img(4, 2, [(0, 0, 1, 1)])
check(P.mirror(m)[0, 3, 3] == 255 and P.mirror(m)[0, 0, 3] == 0 and P.mirror(P.mirror(m)).tolist() == m.tolist(), 'mirror')

check(P.alpha_bbox(img(8, 8)) is None, 'alpha_bbox: empty')
check(P.alpha_bbox(img(8, 8, [(2, 3, 5, 7)])) == (2, 3, 5, 7), 'alpha_bbox: exclusive end')
fa, fb = img(16, 16, [(2, 3, 5, 7)]), img(16, 16, [(10, 1, 12, 4)])
check(P.union_bbox([fa, img(16, 16), fb]) == (2, 1, 12, 7), 'union_bbox over frames')
check(P.union_bbox([img(4, 4)]) is None, 'union_bbox: nothing')

check(P.fit_tiles(30, 20) == 1 and P.fit_tiles(31, 10) == 1 and P.fit_tiles(32, 10) == 2, 'fit_tiles: margin counts')
check(P.fit_tiles(10, 70) == 3 and P.fit_tiles(60, 60, hi=3) == 2, 'fit_tiles: edge from the larger side')
raises(lambda: P.fit_tiles(100, 10), 'fit_tiles: over 3 tiles stops')
raises(lambda: P.fit_tiles(130, 10, hi=9), 'fit_tiles: never above MAX_TILES')

fr = img(64, 64, [(10, 20, 30, 50)])
box = P.alpha_bbox(fr)
out = P.place_bottom_right(fr, box, 2, 2)
check(out.shape == (64, 64, 4) and P.alpha_bbox(out) == (64 - 1 - 20, 64 - 1 - 30, 63, 63), 'place_bottom_right: 1 px from right and bottom')
out2 = P.place_bottom_right(fr, box, 2, 2, dx=-3, dy=-2)
check(P.alpha_bbox(out2) == (40, 31, 60, 61), 'place_bottom_right: owner shift')
check((out[P.alpha_bbox(out)[1]:P.alpha_bbox(out)[3], P.alpha_bbox(out)[0]:P.alpha_bbox(out)[2]] == fr[20:50, 10:30]).all(),
      'place_bottom_right: pixels moved, not scaled')
wide = img(64, 64, [(0, 0, 40, 10)])
raises(lambda: P.place_bottom_right(wide, P.alpha_bbox(wide), 1, 1), 'place_bottom_right: a box that does not fit stops')
raises(lambda: P.place_bottom_right(fr, box, 2, 2, dx=5), 'place_bottom_right: a shift off the canvas stops')

p = P.pad_to_tile(img(46, 32, [(0, 0, 46, 32)]))
check(p.shape == (32, 64, 4) and not p[:, :18].any() and p[:, 18:].all(), 'pad_to_tile: 46 -> 64, bottom-right aligned')
p = P.pad_to_tile(img(62, 92, [(0, 0, 62, 92)]))
check(p.shape == (96, 64, 4) and p[4:, 2:].all() and not p[:4].any(), 'pad_to_tile: 62x92 -> 64x96')
check(P.pad_to_tile(img(64, 32)).shape == (32, 64, 4), 'pad_to_tile: multiples unchanged')

# scale2x: a flat block stays flat, a lone diagonal pixel pair keeps its colours, size doubles
f = img(4, 4, [(0, 0, 4, 4)])
u = P.scale2x(f)
check(u.shape == (8, 8, 4) and (u == f[0, 0]).all(), 'scale2x: flat input stays flat')
d = np.zeros((3, 3, 4), np.uint8)
d[0, 0] = d[1, 1] = d[2, 2] = (255, 0, 0, 255)
u = P.scale2x(d)
check(u.shape == (6, 6, 4) and set(map(tuple, u.reshape(-1, 4))) <= {(0, 0, 0, 0), (255, 0, 0, 255)}, 'scale2x: no new colours')

# colour mask: markers snap, near colours snap, far colours and faint alpha are cleared; at most four colours remain
mk = np.zeros((1, 6, 4), np.uint8)
mk[0, 0] = (250, 250, 10, 255)    # yellow-ish
mk[0, 1] = (230, 20, 30, 200)     # red-ish
mk[0, 2] = (0, 255, 0, 255)       # green
mk[0, 3] = (20, 10, 235, 255)     # blue-ish
mk[0, 4] = (128, 128, 128, 255)   # far from every marker
mk[0, 5] = (255, 0, 0, 100)       # faint
sm = P.snap_mask(mk)
check(tuple(sm[0, 0]) == (255, 255, 0, 255) and tuple(sm[0, 1]) == (255, 0, 0, 255) and tuple(sm[0, 2]) == (0, 255, 0, 255)
      and tuple(sm[0, 3]) == (0, 0, 255, 255), 'snap_mask: markers')
check(not sm[0, 4].any() and not sm[0, 5].any(), 'snap_mask: far colour and faint alpha cleared')
check(len(set(map(tuple, sm.reshape(-1, 4)))) <= 5, 'snap_mask: four colours and clear')
check(not P.snap_mask(np.array([[[255, 255, 41, 255]]], np.uint8)).any(), 'snap_mask: 41 off is out')

check(P.mean_rgb(img(2, 2, [(0, 0, 2, 1)], (10, 20, 30, 255))) == (10, 20, 30) and P.mean_rgb(img(2, 2)) == (0, 0, 0), 'mean_rgb')

# ------------------------------------------------------------------------------------------------ geometry
mask = np.zeros((10, 12), bool)
mask[1:3, 1:4] = True
mask[3, 4] = True            # diagonal touch joins the first blob
mask[6:8, 8:10] = True
mask[9, 0] = True
cs = P.components(mask)
check(cs == [(1, 1, 5, 4, 7), (8, 6, 10, 8, 4), (0, 9, 1, 10, 1)], 'components: 8-connected, reading order, areas: %r' % cs)
u = np.zeros((6, 7), bool)
u[0:5, 0] = u[0:5, 4] = u[4, 0:5] = True       # a U joins at the bottom
check(len(P.components(u)) == 1 and P.components(u)[0][4] == 13, 'components: a U is one piece')
check(P.components(np.zeros((4, 4), bool)) == [], 'components: empty')
big = np.zeros((1024, 1024), bool)
rng = np.random.RandomState(1)
for _ in range(400):
    x, y = rng.randint(0, 1000), rng.randint(0, 1000)
    big[y:y + rng.randint(2, 24), x:x + rng.randint(2, 24)] = True
t0 = time.time()
n = len(P.components(big))
check(n > 0 and time.time() - t0 < 10, 'components: a 1024 sheet is fast (%d comps, %.1fs)' % (n, time.time() - t0))

sheet = img(128, 64)
sheet[3:25, 3:20] = (9, 9, 9, 255)          # cell 0,0
sheet[40:60, 36:60] = (9, 9, 9, 255)        # cell 1,1 .. 1,1 (x 36-60, y 40-60)
sheet[5:20, 28:70] = (9, 9, 9, 255)         # crosses the edges of cells 0, 1, 2 (x 28..70)
sheet[50, 120] = (9, 9, 9, 255)             # a speck, area 1
boxes, dropped = P.segment_sheet(sheet)
check(boxes == [(0, 0, 96, 32), (32, 32, 64, 64)], 'segment_sheet: crossing piece stays whole and merges its neighbour: %r' % (boxes,))
check(dropped == [(120, 50, 121, 51, 1)], 'segment_sheet: the speck is dropped and listed')
boxes, _ = P.segment_sheet(img(128, 64, [(70, 40, 90, 60), (3, 3, 10, 10)]))
check(boxes == [(0, 0, 32, 32), (64, 32, 96, 64)], 'segment_sheet: separate sprites, boxes on the 32 grid')
b2, _ = P.segment_sheet(img(100, 40, [(90, 30, 100, 40)]))
check(b2 == [(64, 0, 100, 40)], 'segment_sheet: the grown box stops at the sheet edge')

g = P.grid_detect(img(131, 131))
check(g == {'cell': 32, 'gap': 1, 'nx': 4, 'ny': 4, 'pitch': 33, 'how': 'gap33'}, 'grid_detect: 131 px sheet, 4x4 with gaps')
g = P.grid_detect(img(197, 131))
check(g and (g['nx'], g['ny'], g['gap']) == (6, 4, 1), 'grid_detect: 197x131 is 6x4 with gaps')
g = P.grid_detect(img(256, 256, [(3, 3, 20, 20), (40, 70, 60, 90)]))
check(g and g['cell'] == 32 and g['nx'] == 8 and g['how'] == 'cells32', 'grid_detect: 32 cells when nothing crosses')
g = P.grid_detect(img(64, 64, [(20, 4, 30, 12), (5, 36, 12, 44)]))      # the first sprite crosses the 32 edge? no: 20..30 < 32
check(g and g['cell'] == 32, 'grid_detect: sprites inside 32 cells')
g = P.grid_detect(img(64, 64, [(24, 4, 40, 12), (5, 36, 12, 44)]))      # crosses x=32, and also x=16 -> neither fits
check(g is None, 'grid_detect: crossing both grids returns None')
g = P.grid_detect(img(64, 64, [(2, 2, 14, 14), (18, 2, 30, 14), (2, 18, 14, 30)]))
check(g and g['cell'] == 32, 'grid_detect: 32 preferred when it also fits')
g = P.grid_detect(img(64, 64, [(10, 10, 22, 22), (40, 40, 50, 50)]))      # the first sprite sits on the 32 edge? 10..22 fits 16? crosses x=16
check(g is not None and g['cell'] == 32, 'grid_detect: inside 32')
g = P.grid_detect(img(64, 64, [(28, 4, 36, 12), (5, 36, 12, 44)]), cells=(16,))
check(g is None, 'grid_detect: restricted cells')
g = P.grid_detect(img(64, 64, [(16, 4, 28, 12), (40, 20, 60, 28)]))
check(g is None or g['cell'] in (32, 16), 'grid_detect: no crash on mixed sheets')
g = P.grid_detect(img(48, 48, [(2, 2, 12, 12), (18, 18, 30, 30)]))
check(g and g['cell'] == 16 and g['nx'] == 3, 'grid_detect: 48 px sheet only fits 16')

for gw, gh, want in [(1, 1, [(0, 0, 0, 0, 1, 1)]), (4, 4, [(0, 0, 0, 0, 4, 4)]),
                     (6, 4, [(0, 0, 0, 0, 2, 4), (0, 1, 2, 0, 4, 4)]),
                     (5, 3, [(0, 0, 0, 0, 1, 3), (0, 1, 1, 0, 4, 3)])]:
    got = [tuple(x) for x in P.plan_split(gw, gh)]
    check(got == want, 'plan_split %dx%d: %r' % (gw, gh, got))
ps = P.plan_split(16, 16)
check(len(ps) == 16 and all(q.tw == 4 and q.th == 4 for q in ps), 'plan_split: the 512 px keep is 16 pieces of 4x4')
ps = P.plan_split(6, 6)
check([(q.tw, q.th) for q in ps] == [(2, 2), (4, 2), (2, 4), (4, 4)], 'plan_split 6x6: remainder north-west')
for gw, gh, mt in [(7, 5, 4), (9, 9, 3), (6, 8, 4), (3, 3, 4), (13, 2, 4)]:
    ps = P.plan_split(gw, gh, mt)
    cover = np.zeros((gh, gw), int)
    for q in ps:
        check(q.tw <= mt and q.th <= mt, 'plan_split %dx%d: piece within the limit' % (gw, gh))
        cover[q.ty:q.ty + q.th, q.tx:q.tx + q.tw] += 1
    check((cover == 1).all(), 'plan_split %dx%d (max %d): exact cover' % (gw, gh, mt))
    check(any(q.tw == mt and q.th == mt for q in ps) or gw < mt or gh < mt, 'plan_split %dx%d: south-east piece is full' % (gw, gh))
pic = np.arange(6 * 32 * 6 * 32 * 4, dtype=np.uint32).astype(np.uint8).reshape(6 * 32, 6 * 32, 4)
parts = P.plan_split(6, 6)
re_ = np.zeros_like(pic)
for q in parts:
    cut = P.cut_piece(pic, q)
    check(cut.shape == (q.th * 32, q.tw * 32, 4), 'cut_piece: shape')
    re_[q.ty * 32:(q.ty + q.th) * 32, q.tx * 32:(q.tx + q.tw) * 32] = cut
check((re_ == pic).all(), 'cut_piece: pieces rebuild the picture')
check(P.piece_key('keep', parts[3]) == 'keep_r1c1', 'piece_key')
check(P.group_extra('keep', 6, 6, parts[1]) == 'group=keep|gw=6|gh=6|piece=0,1', 'group_extra')
raises(lambda: P.plan_split(0, 3), 'plan_split: empty group')
check(P.tiles_of_px(1) == 1 and P.tiles_of_px(32) == 1 and P.tiles_of_px(33) == 2 and P.tiles_of_px(92) == 3, 'tiles_of_px')

# ------------------------------------------------------------------------------------------------ palettes
check(all(P.rgb_to_outfit_index(P.outfit_rgb(i)) == i for i in range(133)), 'outfit palette: every colour maps to itself')
check(len(set(P.OUTFIT_TABLE)) == 133, 'outfit palette: 133 distinct colours')
try:
    import compose_outfit as CO
    check(all(P.outfit_rgb(i) == CO.outfit_colour(i) for i in range(133)), 'outfit palette: same table as compose_outfit')
except ImportError:
    print('skip: compose_outfit not importable')
check(P.rgb_to_outfit_index((255, 255, 255)) == 0 and P.rgb_to_outfit_index((0, 0, 0)) == 114, 'outfit palette: white 0, black 114')
check(all(P.rgb_to_minimap_index(P.minimap_rgb(i)) == i for i in range(1, 216)), 'minimap cube: 215 colours map to themselves')
check(P.rgb_to_minimap_index((0, 0, 0)) == 1 and P.rgb_to_minimap_index((255, 255, 255)) == 215, 'minimap cube: 0 is transparent, never returned')
check(P.rgb_to_minimap_index((250, 20, 3)) == 5 * 36 + 0 * 6 + 0 and P.minimap_rgb(186) == (255, 51, 0), 'minimap cube: red, index 186')

# ------------------------------------------------------------------------------------------------ tables
a = img(3, 2, [(0, 0, 2, 2)])
check(P.digest(a) == P.digest(a.copy()) and P.digest(a) != P.digest(a.T.copy()) and len(P.digest(a)) == 64, 'digest: pixels and shape')
check(P.csv_text(['a', 'b'], [[1, 'x,y']]) == 'a,b\n1,"x,y"\n', 'csv_text')
check(P.sums_text([('d/a.png', a)]) == '%s  d/a.png\n' % P.digest(a), 'sums_text')
check(P.slugify('Frozen Ruins – 32x32!') == 'frozen_ruins_32x32' and P.humanize('sootfang_wolf') == 'Sootfang Wolf', 'slugify, humanize')
check(P.key_of('Frozen Ruins', 'Sheet 2', (1, 3)) == 'frozen_ruins__sheet_2__1_3' and P.key_of('p', 's') == 'p__s', 'key_of')
check(P.fps_to_ms(8) == 125 and P.fps_to_ms(3) == 333 and P.fps_to_ms(None) == 110 and P.fps_to_ms(0) == 110, 'fps_to_ms')

# ------------------------------------------------------------------------------------------------ overrides
with tempfile.TemporaryDirectory() as td:
    ov = os.path.join(td, 'ov.csv')

    def write(text):
        open(ov, 'w', newline='').write(text)

    write('key,action,value\n')
    check(P.load_overrides(ov) == {}, 'overrides: header only')
    check(P.load_overrides(os.path.join(td, 'missing.csv')) == {}, 'overrides: no file')
    write('key,action,value\na__b__c,dx,-3\na__b__c,tiles,2\na__b__c,ns,w\nq,tiles,3x2\nq,light,3:207\nq,skip,1\nq,rename,Old Tome\n')
    o = P.load_overrides(ov)
    check(o['a__b__c'] == {'dx': -3, 'tiles': (2, 2), 'ns': 'w'} and o['q']['tiles'] == (3, 2) and o['q']['light'] == (3, 207)
          and o['q']['skip'] == 1 and o['q']['rename'] == 'Old Tome', 'overrides: parsed values')
    check(P.ov_get(o, 'q', 'skip') == 1 and P.ov_get(o, 'q', 'dx', 7) == 7 and P.ov_get(o, 'zz', 'dx') is None, 'ov_get')
    for bad in ('k,nope,1\n', 'k,ns,n\n', 'k,tiles,5\n', 'k,skip,2\n', 'k,light,3:300\n', 'k,dx,x\n', 'k,dx,1\nk,dx,2\n', 'k,flip\n'):
        write('key,action,value\n' + bad)
        raises(lambda: P.load_overrides(ov), 'overrides: refuse %r' % bad.strip())
    write('k,action,value\n')
    raises(lambda: P.load_overrides(ov), 'overrides: header')

# ------------------------------------------------------------------------------------------------ files, roots, md5
with tempfile.TemporaryDirectory() as td:
    pk = os.path.join(td, 'real folder', 'inner')
    os.makedirs(os.path.join(pk, 'sub'))
    os.makedirs(os.path.join(pk, 'preview'))
    os.makedirs(os.path.join(pk, 'cr', 'sheets'))
    for rel, im in (('one.png', img(64, 32)), ('sub/two.png', img(32, 96)), ('preview/skip.png', img(8, 8)),
                    ('cr/sheets/cr_sheet.png', img(512, 64)), ('cr/sheets/x.txt', None)):
        if im is None:
            open(os.path.join(pk, rel), 'w').write('t')
        else:
            Image.fromarray(im).save(os.path.join(pk, rel))
    open(os.path.join(pk, 'cr', 'animations.json'), 'w').write('{}')
    open(os.path.join(pk, 'readme.gif'), 'wb').write(b'GIF89a')
    open(os.path.join(pk, 'a.7z'), 'wb').write(b'7z')
    rows = P.scan_pack('demo', pk)
    check([r.path for r in rows] == ['cr/animations.json', 'cr/sheets/cr_sheet.png', 'one.png', 'sub/two.png'],
          'scan_pack: png and json only, no previews: %r' % [r.path for r in rows])
    check([(r.w, r.h) for r in rows if r.path == 'sub/two.png'] == [('32', '96')] and rows[0].w == '', 'scan_pack: PIL sizes')
    lk = P.scan_pack('demo', pk, looks=True)
    check([r.path for r in lk] == ['cr/animations.json', 'cr/sheets/cr_sheet.png'], 'scan_pack looks: sheets and animations.json only')
    check(rows[2].md5 == hashlib.md5(open(os.path.join(pk, 'one.png'), 'rb').read()).hexdigest() == P.file_md5(os.path.join(pk, 'one.png')),
          'file_md5')
    txt = P.files_text(rows[::-1])
    path = os.path.join(td, 'x.files')
    open(path, 'w', newline='').write(txt)
    check(P.read_files(path) == rows and P.files_text(P.read_files(path)) == txt, 'files_text / read_files round trip, sorted')
    priv = {'demo': {'slug': 'demo', 'folder': 'real folder', 'root': 'inner'}}
    check(P.pack_root(td, 'demo', priv) == pk, 'pack_root: the private map')
    check(P.verify_files(td, rows, priv) == [], 'verify_files: clean')
    open(os.path.join(pk, 'one.png'), 'ab').write(b'x')
    check(any('size' in b for b in P.verify_files(td, rows, priv)), 'verify_files: a changed size')
    os.truncate(os.path.join(pk, 'one.png'), int(rows[2].size))
    Image.fromarray(img(64, 32, [(0, 0, 1, 1)])).save(os.path.join(pk, 'one.png'))
    bad = P.verify_files(td, rows, priv)
    check(any('one.png' in b for b in bad), 'verify_files: changed content is caught')
    os.remove(os.path.join(pk, 'sub', 'two.png'))
    check(any('missing' in b for b in P.verify_files(td, rows, priv, md5=False)), 'verify_files: missing')
    raises(lambda: P.source_path(td, 'demo', '../x', priv), 'source_path: no ..')
    raises(lambda: P.source_path(td, 'demo', '/etc/passwd', priv), 'source_path: no absolute path')
    raises(lambda: P.pack_root(td, 'nope', {}), 'pack_root: unknown slug')
    os.makedirs(os.path.join(td, 'plain'))
    check(P.pack_root(td, 'plain', {}) == os.path.join(td, 'plain'), 'pack_root: a folder named like the slug')
    good = os.path.join(pk, 'good.png')
    Image.fromarray(img(4, 4, [(0, 0, 2, 2)])).save(good)
    arr = P.load_verified(good, P.file_md5(good))
    check(arr.shape == (4, 4, 4) and arr[0, 0, 3] == 255, 'load_verified: RGBA array')
    raises(lambda: P.load_verified(good, '0' * 32), 'load_verified: wrong md5 refused before decoding')

# ------------------------------------------------------------------------------------------------ the committed tables
packs = P.load_packs()
check(P.check_packs(packs) == [], 'pack30_packs.csv: %r' % P.check_packs(packs))
by = P.pack_by_slug(packs)
check(len(by) == len(packs), 'pack30_packs.csv: unique slugs')
st = {s: [p for p in packs if p.status == s] for s in P.STATUSES}
check(len(st['excluded']) == 1 and st['excluded'][0].label == '' and st['excluded'][0].licence_class == 'none-found',
      'pack30_packs.csv: one excluded pack')
check(all(by[p.dup_of].status == 'ready' and p.category == by[p.dup_of].category for p in st['dup']), 'dup rows point at ready packs')
check(sorted(p.slug for p in st['ready'] if p.label == 'set30 monsters') == ['mon_a', 'mon_b', 'mon_c'] and
      all(p.category == 'looks' for p in st['ready'] if p.label == 'set30 monsters'), 'the three monster packs are looks')
check(len([p for p in st['ready'] if p.label == 'set30 potions']) == 1, 'one potions pack')
check(all(p.licence_class == 'unread' and p.file_count == '0' for p in st['pending']) and len(st['pending']) >= 15, 'pending packs listed')
check(P.check() == [], 'pack30lib check: %r' % P.check())
for cat in P.CATEGORIES:
    rows = P.read_files(P.files_path(cat))
    check(rows and all(by[r.slug].status == 'ready' for r in rows), 'pack30_%s.files: ready packs only' % cat)
    check(len({(r.slug, r.path) for r in rows}) == len(rows), 'pack30_%s.files: unique paths' % cat)
    check(all(re.fullmatch(r'[0-9a-f]{32}', r.md5) and r.size.isdigit() for r in rows), 'pack30_%s.files: md5 and size' % cat)
    check(all(r.path.lower().endswith(('.png', '.json')) and '..' not in r.path for r in rows), 'pack30_%s.files: png / json paths' % cat)
check(sum(1 for r in P.read_files(P.files_path('looks')) if r.path.endswith('animations.json')) == 75, 'looks: 75 creatures')
check(P.load_overrides() == {}, 'pack30_overrides.csv: header only')
for cat in P.CATEGORIES:
    gi = os.path.join(P.ART, 'pack30_%s' % cat, '.gitignore')
    check(os.path.isfile(gi) and open(gi).read().splitlines()[-2:] == ['*', '!.gitignore'], 'pack30_%s/.gitignore' % cat)

# ------------------------------------------------------------------------------------------------ names rule
import check_names as CN  # noqa: E402

HASHES = {'4863cb09cbec3d4c', '56de29ba8c431f96', '9a7be5bb26fa4e65', '1097a5e313cae18c', '296538767d1b2a34',
          'ec306d4a7b51ab70', '47e0139db7ccacfa'}   # vendor, author and pack-title words (sha256 prefixes)
WORD = re.compile(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+')


def hit(line):
    if CN.name_hit(line):
        return True
    w = [x.lower() for x in WORD.findall(line)]
    cand = w + [a + b for a, b in zip(w, w[1:])]
    return any(hashlib.sha256(x.encode()).hexdigest()[:16] in HASHES for x in cand)


names = [P.PACKS_CSV, P.OVERRIDES_CSV, __file__, P.__file__] + [P.files_path(c) for c in P.CATEGORIES] + \
        [os.path.join(P.ART, 'pack30_%s' % c, '.gitignore') for c in P.CATEGORIES]
for f in names:
    for i, line in enumerate(open(f, encoding='utf-8').read().split('\n'), 1):
        if hit(line):
            check(False, 'names: %s:%d: %s' % (os.path.relpath(f, HERE), i, line[:80]))
    check(not hit(os.path.basename(f)), 'names: file name %s' % os.path.basename(f))
check(not P.PRIVATE_CSV.endswith('pack30_packs.csv') and os.path.basename(P.PRIVATE_CSV) == 'pack30_packs.private.csv', 'private sidecar name')

# the OTB kinds the pack importers use exist in import_art_things.py
import import_art_things as IAT  # noqa: E402

for kind in ('wall', 'flask', 'prop', 'ground', 'water', 'border', 'stump', 'decor', 'weapon', 'corpse'):
    check(kind in IAT.OTB, 'import_art_things.OTB has %s' % kind)
check(IAT.OTB['wall'] == (0, IAT.HANG, 0) and IAT.HANG == 1 << 16, 'OTB wall: hangable')
check(IAT.OTB['flask'][1] & IAT.STACK and IAT.OTB['flask'][1] & IAT.PICKUP and IAT.OTB['flask'][1] & IAT.MOVE, 'OTB flask: stackable pickup')
check(IAT.OTB['prop'] == (0, 0, 0), 'OTB prop: plain fixed object')
check(all(len(v) == 3 for v in IAT.OTB.values()), 'OTB: (group, flags, top order) everywhere')

print('pack30lib_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
