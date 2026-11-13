#!/usr/bin/env python3
"""Tests of gen_minimap_swatches.py on a synthetic pair (fake dat and spr objects, numpy and Pillow, no pair needed).

python3 -I client/tools/gen_minimap_swatches_test.py
"""
import io
import os
import sys
from types import SimpleNamespace

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_minimap_swatches as g  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


class FakeSpr:
    def __init__(self, tiles):
        self.tiles = tiles

    def sprite(self, sid):
        return self.tiles.get(sid)


def flat(r, gr, b, a=255):
    arr = np.zeros((32, 32, 4), np.uint8)
    arr[...] = (r, gr, b, a)
    return arr


def thing(w, h, sprites, flags=None, layers=1):
    return SimpleNamespace(w=w, h=h, px=1, py=1, pz=1, layers=layers, sprites=tuple(sprites), flags=flags or {})


# item 100 grass (opaque green), 101 water ground (minimap 51), 102 lava ground (192), 103 a tree (solid, tall, half clear),
# 104 a wall piece (solid, not tall), 105 a 2x2 roof (sprites 10 11 12 13: cell (0,0) = 10 is the bottom right), 106 ground border,
# 107 empty item (no sprite), 108 a half transparent red flower
spr = FakeSpr({
    1: flat(40, 160, 40), 2: flat(30, 80, 200), 3: flat(230, 90, 20),
    4: np.concatenate([flat(10, 70, 10)[:, :16], np.zeros((32, 16, 4), np.uint8)], axis=1),   # left half dark green, right half clear
    5: flat(200, 180, 150),
    10: flat(250, 0, 0), 11: flat(0, 250, 0), 12: flat(0, 0, 250), 13: flat(250, 250, 0),
    6: flat(100, 100, 100),
    8: flat(255, 0, 0, 128),
})
items = [
    thing(1, 1, [1], {'ground': 0}),
    thing(1, 1, [2], {'ground': 0, 'minimap': 51}),
    thing(1, 1, [3], {'ground': 0, 'minimap': 192}),
    thing(1, 1, [4], {'notwalkable': True, 'blockmissile': True}),
    thing(1, 1, [5], {'notwalkable': True}),
    thing(2, 2, [10, 11, 12, 13], {'notwalkable': True, 'blockmissile': True}),
    thing(1, 1, [6], {'clip': 0, 'notwalkable': True}),
    thing(1, 1, [0], {}),
    thing(1, 1, [8], {}),
]
dat = SimpleNamespace(items=items)
CID = {name: 100 + i for i, name in enumerate(['grass', 'water', 'lava', 'tree', 'wall', 'roof', 'border', 'empty', 'flower'])}

# ---- flags
check(g.item_flags(items[0]) == 0, 'grass has no flags')
check(g.item_flags(items[1]) == g.F_WATER, 'water ground')
check(g.item_flags(items[2]) == g.F_LAVA, 'lava ground')
check(g.item_flags(items[3]) == g.F_SOLID | g.F_TALL, 'tree: solid and tall')
check(g.item_flags(items[4]) == g.F_SOLID, 'wall piece: solid, not tall')
check(g.item_flags(items[6]) == 0, 'a ground border that blocks is still no solid')
check(g.item_flags(thing(1, 1, [1], {'ground': 0, 'notwalkable': True, 'blockmissile': True})) == 0, 'ground never solid')

# ---- swatches
sw = g.render_swatch(items[0], spr)
check(sw.shape == (8, 8, 4) and (sw[..., :3] == (40, 160, 40)).all() and (sw[..., 3] == 255).all(), 'flat sprite -> flat swatch')
tree = g.render_swatch(items[3], spr)
check(tree[0, 0, 3] == 255 and tree[0, 7, 3] == 0, 'half clear sprite: left opaque, right clear')
check(tuple(tree[0, 0, :3]) == (10, 70, 10), 'colour of an opaque pixel is exact')
check(tuple(tree[0, 7]) == (0, 0, 0, 0), 'a clear pixel is zero')
flower = g.render_swatch(items[8], spr)
check(flower[0, 0, 3] in (127, 128) and flower[0, 0, 0] >= 254 and flower[0, 0, 1] == 0, 'alpha weighted: colour is not dimmed by alpha')
check(g.render_swatch(items[7], spr) is None, 'an item without a pixel has no swatch')
# colour averaged over the 4x4 block, alpha weighted: left half 255, right half 0 inside one 8 px column straddles nothing, so edge blocks are pure
half = np.zeros((32, 32, 4), np.uint8)
half[:, :2] = (200, 0, 0, 255)           # 2 of 4 columns of the first 4x4 block: alpha 0.5, colour stays 200
spr.tiles[20] = half
t2 = g.render_swatch(thing(1, 1, [20]), spr)
check(t2[0, 0, 3] in (127, 128) and t2[0, 0, 0] == 200, 'a half covered block keeps its colour and halves its alpha')
check(t2[0, 1, 3] == 0, 'a block with no covered pixel is clear')
# 2x2: sprite index 0 is the bottom right cell
roof = g.render_swatch(items[5], spr)
check(roof.shape == (16, 16, 4), '2x2 swatch is 16 x 16')
check(roof[12, 12, 0] > 200 and roof[12, 12, 1] < 40, 'cell 0 (red) is bottom right')
check(roof[12, 4, 1] > 200 and roof[12, 4, 0] < 40, 'cell 1 (green) is bottom left')
check(roof[4, 12, 2] > 200, 'cell 2 (blue) is top right')
check(roof[4, 4, 0] > 200 and roof[4, 4, 1] > 200, 'cell 3 (yellow) is top left')

# ---- pack, build, index
ids = sorted(CID.values())
png, text = g.build(dat, spr, ids)
atlas, recs = g.parse_index(text)
check(len(recs) == 8, 'eight swatches (the empty item has none), got %d' % len(recs))
check(atlas['w'] == g.ATLAS_W and atlas['cell'] == 8, 'atlas header')
ids = [i for i in ids if i != CID['empty']]      # ids.txt lists the types of the map: an empty one never gets a swatch there either
check(not g.check_files(png, text, ids), 'the built files pass the check: %s' % g.check_files(png, text, ids))
png2, text2 = g.build(dat, spr, ids)
check(png == png2 and text == text2, 'the build is deterministic')
by = {r[0]: r for r in recs}
check(by[CID['roof']][3:5] == (2, 2), 'roof is 2x2 in the index')
check(by[CID['tree']][5] == g.F_SOLID | g.F_TALL, 'tree flags in the index')
check(CID['empty'] not in by, 'the empty item is not listed')
im = np.asarray(Image.open(io.BytesIO(png)).convert('RGBA'))
x, y = by[CID['grass']][1], by[CID['grass']][2]
check((im[y:y + 8, x:x + 8, :3] == (40, 160, 40)).all(), 'grass pixels are where the index says')
x, y = by[CID['roof']][1], by[CID['roof']][2]
check(tuple(im[y + 12, x + 12, :3]) == tuple(roof[12, 12, :3]), 'roof pixels are where the index says')
# no overlap (the check does it too): count painted cells
grid = np.zeros(im.shape[:2], int)
for cid, x, y, w, h, fl in recs:
    grid[y:y + h * 8, x:x + w * 8] += 1
check(grid.max() == 1, 'no two swatches overlap')

# ---- the check finds faults
bad_png = bytearray(png)
bad_png[-20] ^= 0xFF
check(any('sha256' in e or 'png' in e for e in g.check_files(bytes(bad_png), text, ids)), 'a changed png is found')
check(any('not in ids.txt' in e for e in g.check_files(png, text, ids[:3])), 'an item outside ids.txt is found')
dup = text + text.splitlines()[2] + '\n'
check(any('twice' in e for e in g.check_files(png, dup, ids)), 'a repeated item is found')
lines = text.splitlines()
lines[2] = '100 2041 0 11 0'
check(any('outside' in e for e in g.check_files(png, '\n'.join(lines) + '\n', ids)), 'a swatch outside the atlas is found')
lines = text.splitlines()
q = lines[2].split()
lines[2] = '%s %s %s %s 2' % tuple(q[:4])
check(any('flags' in e for e in g.check_files(png, '\n'.join(lines) + '\n', ids)), 'a tall item that is not solid is found')
lines = text.splitlines()
lines[3] = ' '.join([lines[3].split()[0]] + lines[2].split()[1:3] + lines[3].split()[3:])
check(any('overlaps' in e for e in g.check_files(png, '\n'.join(lines) + '\n', ids)), 'an overlap is found')
for bad_text in ('chaos-minimap-hd 2\n', 'chaos-minimap-hd 1\natlas a.png 1\n', text + 'x y z\n', text.replace(' 11 ', ' 1 ', 1)):
    try:
        g.parse_index(bad_text)
        check(False, 'a bad index is refused: %r' % bad_text[:30])
    except g.SwatchError:
        pass
big = b'\0' * (g.MAX_PNG_BYTES + 1)
check(any('budget' in e for e in g.check_files(png + big, text, ids)), 'the size budget is checked')

# ---- ids file
check(g.format_ids([5, 6, 7, 9, 12, 13]).splitlines()[1:] == ['5-7', '9', '12-13'], 'ids are written as ranges')
tmp = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'minimap_ids_test_%d.txt' % os.getpid())
open(tmp, 'w').write(g.format_ids([100, 101, 102, 200, 300, 301]))
check(g.read_ids(tmp) == [100, 101, 102, 200, 300, 301], 'ids read back')
open(tmp, 'w').write('5\n3\n')
try:
    g.read_ids(tmp)
    check(False, 'unsorted ids are refused')
except g.SwatchError:
    pass
os.remove(tmp)
committed = g.read_ids()
check(len(committed) > 1000 and committed[0] >= 100, 'the committed ids.txt has the map\'s item types')

if fails:
    print(fails, 'failure(s)')
    sys.exit(1)
print('gen_minimap_swatches_test: all passed')
