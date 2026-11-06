#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_temple_art_test.py : the pure parts of gen_temple_art.py (the 2 x 2 average, the bottom
right canvas, the snap, the outline, the droplet filter), the committed source sheet and outputs against a rebuild, the things
rows against import_art_things.py (flag names, otb table, manifest), and the ids (client 44511.., server = client + 4000, clear of
the relic sets). No pair and no owner sheet needed."""
import csv
import io
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_temple_art as G  # noqa: E402
import import_art_things as I  # noqa: E402
import style_check as sc  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# --- down2: exact 2 x 2 box average, integers
a = np.zeros((2, 2, 4), np.uint8)
a[..., :3] = (100, 50, 10)
a[..., 3] = 255
check((G.down2(a) == np.array([[[100, 50, 10, 255]]], np.uint8)).all(), 'down2: four equal pixels stay as they are')
a[0, 0] = (0, 0, 0, 255)
check(tuple(G.down2(a)[0, 0]) == (75, 38, 8, 255), 'down2: the mean of four opaque pixels (rounded half up)')
b = np.zeros((2, 2, 4), np.uint8)
b[0, 0] = (200, 0, 0, 255)
b[0, 1] = (200, 0, 0, 255)
b[1, 0] = (200, 0, 0, 255)
check(tuple(G.down2(b)[0, 0]) == (200, 0, 0, 255), 'down2: three of four opaque is opaque and keeps its colour (alpha-weighted)')
b[1, 0] = 0
check(G.down2(b)[0, 0, 3] == 0 and tuple(G.down2(b)[0, 0, :3]) == (0, 0, 0), 'down2: two of four is transparent, colour cleared')
c = np.zeros((2, 2, 4), np.uint8)
c[0, 0] = (255, 0, 0, 255)
c[0, 1] = (0, 255, 0, 255)
c[1, 0] = (0, 0, 255, 255)
c[1, 1] = (255, 255, 255, 255)
check(tuple(G.down2(c)[0, 0]) == (128, 128, 128, 255), 'down2: a colour mix is averaged per channel')
soft = np.zeros((2, 2, 4), np.uint8)
soft[:, :] = (80, 80, 80, 200)
check(G.down2(soft)[0, 0, 3] == 255, 'down2: a soft edge at alpha 200 is opaque (alpha forced to 0 / 255)')

# --- canvas64: the bounding box on whole 64 px cells, bottom right
p = np.zeros((300, 200, 4), np.uint8)
p[20:120, 30:130] = (9, 9, 9, 255)       # 100 x 100 art
p[10:12, 5:7] = (1, 1, 1, 60)            # soft specks outside: dropped
cv = G.canvas64(p)
check(cv.shape == (128, 128, 4), 'canvas64: 100 x 100 art on 128 x 128')
check(cv[-1, -1, 3] == 255 and cv[0, 0, 3] == 0 and (cv[28:, 28:, 3] == 255).all(), 'canvas64: anchored bottom right')

# --- snap: only palette colours come out
pal = np.array([(0, 0, 0), (255, 255, 255), (200, 150, 100), (100, 60, 30)], np.uint8)
rng = np.random.RandomState(1)
px = rng.randint(0, 256, (200, 3))
out = pal[G.snap_index(px, pal)]
check(all(tuple(r) in {tuple(x) for x in pal} for r in out), 'snap_index: every output is a palette colour')
check(tuple(pal[G.snap_index(np.array([[199, 151, 99]]), pal)[0]]) == (200, 150, 100), 'snap_index: a near colour finds its palette colour')

# --- outline: the silhouette rim in the outline colour, the inside untouched, the canvas edge counts as outside
o = np.zeros((8, 8, 4), np.uint8)
o[2:7, 2:7] = (200, 200, 200, 255)
edge = np.array((5, 1, 1), np.uint8)
r = G.outline(o, edge)
check(tuple(r[2, 2, :3]) == (5, 1, 1) and tuple(r[4, 4, :3]) == (200, 200, 200) and tuple(r[6, 6, :3]) == (5, 1, 1),
      'outline: rim pixels dark, the inside kept')
check((r[..., 3] == o[..., 3]).all(), 'outline: alpha unchanged (no growth)')
full = np.full((4, 4, 4), 255, np.uint8)
check((G.outline(full, edge)[0, 0, :3] == edge).all(), 'outline: art at the canvas edge gets the rim too')

# --- drop_small
m = np.zeros((10, 10), bool)
m[1:3, 1:3] = True          # 4 pixels
m[6, 6] = True              # 1 pixel
kept = G.drop_small(m, 3)
check(kept[1, 1] and not kept[6, 6], 'drop_small: a droplet goes, a part of 4 stays')

# --- the table
check(len(set(G.KEYS)) == len(G.KEYS), 'piece keys are unique')
check(len(G.KEYS) == 39, '39 pieces')
for k, cls, name, how, args in G.PIECES:
    check(cls in G.CLASSES, '%s: class %s known' % (k, cls))
    check(how in ('comp', 'tile', 'block', 'mosaic', 'blood'), '%s: how %s known' % (k, how))
    check(name.startswith('temple '), '%s: the item name starts with "temple " (no clash with a stock loot name)' % k)
rects = [(k, ) + tuple(args) for k, _c, _n, how, args in G.PIECES if how == 'comp']
for i, (k, x, y, w, h) in enumerate(rects):
    for k2, x2, y2, w2, h2 in rects[i + 1:]:
        m_ = G.MARGIN
        apart = x + w + m_ <= x2 - m_ or x2 + w2 + m_ <= x - m_ or y + h + m_ <= y2 - m_ or y2 + h2 + m_ <= y - m_
        check(apart, '%s and %s: source boxes (with their soft edge) do not overlap' % (k, k2))

# --- the committed source sheet and the pieces
pieces = G.load_pieces()
check(set(pieces) == set(G.KEYS), 'temple_src.csv names every piece')
for k in G.KEYS:
    a_ = pieces[k]
    how = G.SPEC[k][3]
    if how in ('tile', 'block', 'mosaic'):
        check(a_.shape[0] % 64 == 0 and a_.shape[1] % 64 == 0 and (a_[..., 3] == 255).all(), '%s: whole opaque 64 px tiles' % k)
    check((a_[a_[..., 3] == 0][:, :3] == 0).all(), '%s: no colour under alpha 0' % k)
sheet = G.read_rgba(G.SRC_SHEET)
check(sheet.shape[1] <= G.SHEET_W, 'the source sheet is at most %d px wide' % G.SHEET_W)
for i, a_ in enumerate(G.KEYS):
    for b_ in G.KEYS[i + 1:]:
        same = pieces[a_].shape == pieces[b_].shape and np.array_equal(pieces[a_], pieces[b_])
        check(not same, '%s and %s are different pieces' % (a_, b_))

# --- the build
arts, data, pal_t, theme = G.build_all(pieces)
check(G.problems_of(arts) == [], 'problems_of: whole cells, alpha 0 / 255, no ghost colour, no two pieces equal: %s' % G.problems_of(arts))
theme_pal = {tuple(int(v) for v in x) for x in pal_t}
edge = tuple(sc.unhex(theme['outline'][0]))
for k in G.KEYS:
    a_ = arts[k]
    cols = {tuple(int(v) for v in x) for x in np.unique(a_[a_[..., 3] > 0][:, :3], axis=0)}
    check(cols <= theme_pal, '%s: every colour is a %s palette colour' % (k, G.THEME))
    bad, _w, ncol = G.style_report(k, a_, data, pal_t, theme)
    check(not bad, '%s: style_check passes (%s)' % (k, bad))
    if G.SPEC[k][1] not in G.FLOOR:
        solid = a_[..., 3] == 255
        rim = solid & ~sc.erode(solid)
        check(all(tuple(int(v) for v in x) == edge for x in a_[rim][:, :3]), '%s: the whole silhouette is outlined' % k)
    if G.SPEC[k][1] == 'ground':
        check(a_.shape == (32, 32, 4) and (a_[..., 3] == 255).all(), '%s: a ground tile is one opaque 32 px tile' % k)
check(G.SPEC['mosaic'][4] == () and arts['mosaic'].shape == (96, 96, 4), 'the mosaic is 3 x 3 tiles')
check(arts['carpet'].shape == (128, 96, 4), 'the carpet is 3 wide, 4 tall')

# --- outputs against the committed files
atlas, pos = G.atlas_of(arts)
things = G.things_text(arts, pos)
check(os.path.exists(G.ATLAS) and np.array_equal(G.read_rgba(G.ATLAS), atlas), 'temple.png is up to date (gen_temple_art.py build)')
for path, text in ((G.THINGS, things), (G.MANIFEST, G.manifest_text(things)), (G.SOURCES, G.sources_text()),
                   (G.SUMS, G.sums_text(pieces, arts, atlas))):
    check(os.path.exists(path) and open(path, encoding='utf-8').read() == text, '%s is up to date' % os.path.basename(path))

# --- the things file against the importer
rows = list(csv.DictReader(io.StringIO(things)))
check([r['key'] for r in rows] == G.KEYS, 'things rows in table order')
check(list(rows[0].keys()) == G.HEADER, 'things header')
flag_names = set(I.NEW_BYTE)
for r in rows:
    toks = [t.split(':')[0] for t in r['flags'].split()]
    check(all(t in flag_names for t in toks), '%s: every dat flag name is known to the importer' % r['key'])
    check(r['kind'] in I.OTB and r['cat'] == 'item' and r['mode'] == 'new', '%s: kind %s in the importer table' % (r['key'], r['kind']))
    w, h = int(r['w']), int(r['h'])
    x, y = int(r['x']), int(r['y'])
    check(x % 32 == 0 and y % 32 == 0 and x + w * 32 <= atlas.shape[1] and y + h * 32 <= atlas.shape[0],
          '%s: its atlas box is on the 32 px grid and inside the atlas' % r['key'])
    cell = atlas[y:y + h * 32, x:x + w * 32]
    check(np.array_equal(cell, arts[r['key']]), '%s: the atlas box holds the piece' % r['key'])
    if r['kind'] == 'ground':
        check('ground:100' in r['flags'] and 'fullground' in r['flags'] and 'minimap:' in r['flags'], '%s: ground flags' % r['key'])
    if r['kind'] == 'stump':
        check('notwalkable' in r['flags'] and 'bottom' in r['flags'], '%s: a stump blocks the tile' % r['key'])
check('light:6:206' in [r for r in rows if r['key'] == 'torch'][0]['flags'], 'the torch carries light')
man = list(csv.DictReader(io.StringIO(G.manifest_text(things))))
check([int(r['client_id']) for r in man] == list(range(44511, 44511 + len(G.KEYS))), 'client ids 44511.. in table order')
check(all(int(r['server_id']) == int(r['client_id']) + 4000 for r in man), 'server id = client id + 4000')
check(min(int(r['server_id']) for r in man) > 48510, 'server ids start after the relic sets (48446-48510)')
for r in man:
    g, fl, top = I.OTB[r['kind']]
    check(int(r['otb_group']) == g and int(r['otb_flags']) & ~I.ANIM == fl | (I.SOLID if r['kind'] == 'stump' else 0), '%s: otb group and flags of the importer table' % r['key'])
    check(not int(r['otb_flags']) & (I.PICKUP | I.MOVE | I.STACK), '%s: not pickupable, moveable or stackable' % r['key'])

print('gen_temple_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
