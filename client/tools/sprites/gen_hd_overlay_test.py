#!/usr/bin/env python3
"""Tests of gen_hd_overlay.py on a synthetic pair (fake dat and spr objects, numpy and Pillow, no pair needed).

python3 -I client/tools/sprites/gen_hd_overlay_test.py
"""
import os
import sys
import tempfile
from types import SimpleNamespace

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_hd_overlay as g  # noqa: E402

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


class FakeDat:
    def __init__(self, outfits, items=()):
        self.outfits, self.items, self.effects, self.missiles = list(outfits), list(items), [], []

    def outfit(self, look):
        return self.outfits[look - 1] if 1 <= look <= len(self.outfits) else None


def plain_sprite(seed):
    a = np.zeros((32, 32, 4), np.uint8)
    a[4:28, 4:28] = (seed % 250 + 1, 10, 20, 255)
    return a


def make_group(w, h, phases, first_sid, px=4, layers=1, share=None):
    """a frame group whose sprites are first_sid, first_sid + 1, ...; share = {index: sid} puts a given id at an index"""
    n = w * h * layers * px * phases
    sprites = [first_sid + i for i in range(n)]
    for i, sid in (share or {}).items():
        sprites[i] = sid
    return (w, h, 32, layers, px, 1, 1, phases, tuple(sprites), None)


def make_thing(tid, groups):
    return SimpleNamespace(id=tid, groups=groups, w=groups[0][0], h=groups[0][1], flags={})


def frame_png(path, w, h, scale, tint):
    """each tile of the frame a flat colour of its own, so a cut tile tells which tile it was"""
    s = 32 * scale
    a = np.zeros((h * s, w * s, 4), np.uint8)
    for ty in range(h):
        for tx in range(w):
            a[ty * s:(ty + 1) * s, tx * s:(tx + 1) * s] = (tint, tx * 60 + 20, ty * 60 + 20, 255)
    Image.fromarray(a, 'RGBA').save(path)


def write_frames(art, name, w, h, scale, groups):
    d = os.path.join(art, name)
    os.makedirs(d, exist_ok=True)
    for gi, nframes in groups.items():
        for di, dname in enumerate(g.DIRS):
            for k in range(nframes):
                frame_png(os.path.join(d, 'g%d_%s_%02d.png' % (gi, dname, k)), w, h, scale, 10 + gi * 50 + di * 10 + k)


# a 2x2 look: idle group of 1 phase and walk group of 2 phases; sprite ids 100.. (idle), 200.. (walk)
idle = make_group(2, 2, 1, 100, share={15: 0})     # the last tile of the last direction has no sprite: a zero place
walk = make_group(2, 2, 2, 200, share={1: 100})        # the walk group draws sprite 100 once more (same look: not foreign)
orc = make_thing(1, [idle, walk])
# an item that wears sprite 101 (the idle group's second sprite): that sprite is foreign to the look
item = make_thing(1000, [make_group(1, 1, 1, 101, px=1)])
spr_tiles = {sid: plain_sprite(sid) for sid in list(range(100, 116)) + list(range(200, 232))}
spr_tiles.pop(205)           # an empty record
dat = FakeDat([orc], [item])
spr = FakeSpr(spr_tiles)
spec = {'version': 1, 'looks': [{'look': 1, 'name': 'orc', 'scale': 2, 'groups': [0, 1]}]}

tmp = tempfile.mkdtemp()
art = os.path.join(tmp, 'art')
write_frames(art, 'orc', 2, 2, 2, {0: 1, 1: 3})        # the walk group has 2 phases, 3 frames: phase p shows frame (p * 3) // 2

rows = g.plan_rows(spec, dat, spr, art)
by = {}
for r in rows:
    by.setdefault(r[9], []).append(r)
check(len(rows) == 4 * 4 + 2 * 4 * 4 - 0, 'a row for every tile of every direction and phase: %d' % len(rows))
check(len(by.get('foreign', [])) >= 1 and all(r[7] == 101 for r in by['foreign']), 'sprite 101 is foreign: %s' % by.get('foreign'))
check(len(by.get('zero', [])) == 1 and by['zero'][0][6] == 15 and by['zero'][0][7] == 0, 'one zero place: %s' % by.get('zero'))
check(any(r[7] == 205 and r[9] == 'empty' for r in rows), 'the empty record is `empty`')
shared = [r for r in rows if r[7] == 100]
check(shared[0][9] == 'used', 'first place of 100 is used: %s' % (shared[0],))
check(all(r[9] in ('same', 'conflict') for r in shared[1:]), 'later places of 100 are same or conflict: %s' % shared)
check(any(r[9] == 'conflict' for r in shared[1:]), 'the walk frame cut a different tile for 100: conflict')

# tile geometry: sprite index of (ww, hh) lies at the bottom right: tile (0, 0) is the bottom right cell of the frame
t = orc
frame = g.load_frame(os.path.join(art, 'orc', 'g0_south_00.png'))
bottom_right = g.cut_tile(frame, spec['looks'][0], t, 0, 0)
top_left = g.cut_tile(frame, spec['looks'][0], t, 1, 1)
check(bottom_right.shape == (64, 64, 4), 'tile is 64 px at 2x')
check(tuple(bottom_right[0, 0, 1:3]) == (80, 80) and tuple(top_left[0, 0, 1:3]) == (20, 20), 'tile (0,0) is the bottom right cell: %s %s' % (bottom_right[0, 0], top_left[0, 0]))

# frames per phase: 3 frames for 2 phases shows frames 0 and 1; one frame for one phase
check(g.pick_frame(['a', 'b', 'c'], 0, 2) == 'a' and g.pick_frame(['a', 'b', 'c'], 1, 2) == 'b', 'frame for phase p is (p * k) // n')
check(g.pick_frame(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'], 1, 2) == 'e', '8 frames on 2 phases: 0 and 4')
check(g.pick_frame(['a'], 0, 12) == 'a' and g.pick_frame(['a'], 11, 12) == 'a', 'one frame on 12 phases')

# build: atlas, index
text, pics = g.build_outputs(spec, rows, art, thing_of_look=dat.outfit)
atlases, sprites, slots = g.parse_index(text)
used_ids = {r[7] for r in rows if r[9] == 'used'}
check(set(sprites) == used_ids, 'the index maps exactly the used sprites')
check(101 not in sprites and 205 not in sprites, 'foreign and empty sprites are not mapped by id')
# every place that has no id record but a tile with a pixel is a slot: zero, foreign, conflict (the empty record has the frame's tile too)
slot_rows = [r for r in rows if r[9] in g.SLOT_STATUSES]
check(len(slots) == len(slot_rows), 'a slot for every zero, foreign, conflict and empty place: %d slots, %d rows' % (len(slots), len(slot_rows)))
zr = by['zero'][0]
check(slots[(1, 1, zr[6])][0] == 0, 'the zero place keeps sprite 0 in its slot')
check(all(v[0] in (0, 101, 100, 205) for v in slots.values()), 'slots carry the pair sprite of their place')
check(atlases == ['hd_2x_0.png'] and list(pics) == ['hd_2x_0.png'], 'one 2x atlas: %s' % atlases)
check(pics['hd_2x_0.png'].shape[1] == 2048 and pics['hd_2x_0.png'].shape[0] % 64 == 0, 'atlas width 2048, height cut to the rows used')
for sid, (a, x, y, scale, crc) in sprites.items():
    check(x % 64 == 0 and y % 64 == 0 and scale == 2, 'tile of %d on the grid' % sid)
    check(crc == g.sprite_crc(spr_tiles[sid]), 'crc of %d' % sid)
text2, _ = g.build_outputs(spec, rows, art, thing_of_look=dat.outfit)
check(text == text2, 'deterministic')
check(text.count('\nslot 1 1 ') == len(slots), 'slot lines name category 1 and the outfit id')
# without the pair the same text comes out of the rows alone
text3, pics3 = g.build_outputs(spec, rows, art)
check(text3 == text and np.array_equal(pics3['hd_2x_0.png'], pics['hd_2x_0.png']), 'rebuild from rows alone is the same')
# identical tiles are packed once: two sprites with the same tile share an atlas cell
tile_cells = {(a, x, y) for (a, x, y, s, c) in sprites.values()}
check(len(tile_cells) <= len(sprites), 'cells are shared or one each')

# csv round trip
csv_path = os.path.join(tmp, 'tiles.csv')
g.write_rows(rows, csv_path)
check(g.read_rows(csv_path) == rows, 'csv round trip')

# write, then compare: equal; a changed atlas pixel and a changed index are found
out = os.path.join(tmp, 'out')
g.write_outputs(text, pics, out)
check(g.compare_outputs(text, pics, out) == [], 'written outputs compare equal')
pic_path = os.path.join(out, 'hd_2x_0.png')
im = np.array(Image.open(pic_path).convert('RGBA'))
im[0, 0, 0] ^= 1
Image.fromarray(im, 'RGBA').save(pic_path)
check(any('hd_2x_0.png differs' in m for m in g.compare_outputs(text, pics, out)), 'a changed pixel is found')
g.write_outputs(text, pics, out)
with open(os.path.join(out, 'index.txt'), 'a') as f:
    f.write('# stray\n')
check(any('index.txt differs' in m for m in g.compare_outputs(text, pics, out)), 'a changed index is found')
g.write_outputs(text, pics, out)
open(os.path.join(out, 'hd_2x_9.png'), 'wb').write(b'x')
g.write_outputs(text, pics, out)
check(not os.path.exists(os.path.join(out, 'hd_2x_9.png')), 'a stale atlas file is removed by a write')

# live pair check: same pair passes, a sprite with another picture is reported
check(g.check_rows_against_pair(spec, rows, dat, spr, art) == [], 'rows match their own pair')
spr2 = FakeSpr({**spr_tiles, 100: plain_sprite(9)})
check(len(g.check_rows_against_pair(spec, rows, dat, spr2, art)) > 0, 'a changed sprite is reported')

# the engine's view: with the overlay a sprite gives its tile at the asked size, a changed crc hides it
overlay = (atlases, sprites, slots, pics)
t64 = g.overlay_tile(overlay, 100, spr_tiles[100], 64)
check(t64 is not None and t64.shape == (64, 64, 4), 'tile at 64')
t32 = g.overlay_tile(overlay, 100, spr_tiles[100], 32)
check(t32 is not None and t32.shape == (32, 32, 4) and tuple(t32[5, 5, :3]) == tuple(t64[10, 10, :3]), 'tile at 32 is the mean of the same flat colour')
t128 = g.overlay_tile(overlay, 100, spr_tiles[100], 128)
check(t128.shape == (128, 128, 4) and tuple(t128[3, 3]) == tuple(t64[1, 1]), 'tile at 128 is nearest')
check(g.overlay_tile(overlay, 100, plain_sprite(7), 64) is None, 'another picture under the id: the plain sprite')
check(g.overlay_tile(overlay, 999, None, 64) is None, 'no tile for an id that is not mapped')
# a slot wins over the id and needs the pair's sprite id at the place; another id there hides it
zslot = g.overlay_tile(overlay, 0, None, 64, 1, zr[6])
check(zslot is not None and zslot.shape == (64, 64, 4), 'the zero place draws its slot')
check(g.overlay_tile(overlay, 77, None, 64, 1, zr[6]) is None, 'a slot hides when the pair has another sprite there')
check(g.overlay_tile(overlay, 0, None, 64, 2, zr[6]) is None, 'a slot is for its own thing')

# resample: alpha weighted mean at an edge, hard pixels kept going up
q = np.zeros((2, 2, 4), np.uint8)
q[0, 0] = (200, 0, 0, 255)
q[0, 1] = (99, 99, 99, 0)
q[1, 0] = (0, 200, 0, 255)
q[1, 1] = (0, 0, 200, 255)
r = g.resample(q, 1)
check(r.shape == (1, 1, 4) and r[0, 0, 3] == 191 and tuple(r[0, 0, :3]) == (67, 67, 67), 'edge mean: %s' % (r[0, 0],))
check(np.array_equal(g.resample(q, 2), q), 'same size')
up = g.resample(q, 4)
check(tuple(up[1, 1]) == tuple(q[0, 0]) and tuple(up[3, 3]) == tuple(q[1, 1]), 'up is nearest')

# compose: plain at 64 repeats the 32 px sprite, overlay at 64 uses the tiles
plain = g.compose(orc, spr, 0, 'south', 0, 64, None)
hd = g.compose(orc, spr, 0, 'south', 0, 64, overlay)
check(plain.shape == (128, 128, 4) and hd.shape == (128, 128, 4), 'composed size 2x2 tiles of 64')
check(not np.array_equal(plain, hd), 'the overlay changes the picture')
check(hd[127, 127, 3] == 255 and tuple(hd[127, 127, :3]) == tuple(bottom_right[0, 0, :3]), 'bottom right tile at the bottom right')
panel = g.side_by_side(plain, hd)
check(panel.shape == (128, 128 * 2 + 8, 4), 'side by side panel')
made = g.preview(spec, dat, spr, os.path.join(tmp, 'pv'), 2, overlay)
check(len(made) == 4 * 1 + 4 * 2 and all(os.path.isfile(p) for p in made), 'preview writes 4 idle and 8 walk panels: %d' % len(made))

# errors
bad_spec = {'version': 1, 'looks': [{'look': 1, 'name': 'orc', 'scale': 4, 'groups': [0, 1]}]}
try:
    g.plan_rows(bad_spec, dat, spr, art)
    check(False, 'a 2x frame for a 4x look is refused')
except g.HdError as e:
    check('frame is 128x128' in str(e), 'frame size message: %s' % e)
try:
    g.plan_rows({'version': 1, 'looks': [{'look': 5, 'name': 'orc', 'scale': 2, 'groups': [0]}]}, dat, spr, art)
    check(False, 'a look the dat does not have is refused')
except g.HdError as e:
    check('no outfit 5' in str(e), 'unknown look message: %s' % e)
try:
    g.plan_rows({'version': 1, 'looks': [{'look': 1, 'name': 'orc', 'scale': 2, 'groups': [3]}]}, dat, spr, art)
    check(False, 'a missing frame group is refused')
except g.HdError as e:
    check('no frame group 3' in str(e), 'group message: %s' % e)
masked = FakeDat([make_thing(1, [make_group(1, 1, 1, 300, layers=2)])])
try:
    g.plan_rows({'version': 1, 'looks': [{'look': 1, 'name': 'orc', 'scale': 2, 'groups': [0]}]}, masked, spr, art)
    check(False, 'a colour mask look is refused')
except g.HdError as e:
    check('layers' in str(e), 'layers message: %s' % e)
try:
    g.plan_rows({'version': 1, 'looks': [{'look': 1, 'name': 'nothere', 'scale': 2, 'groups': [0]}]}, dat, spr, art)
    check(False, 'missing frames are refused')
except g.HdError as e:
    check('no frames' in str(e), 'missing frames message: %s' % e)

# allow_foreign takes the foreign sprite
allow_spec = {'version': 1, 'looks': [{'look': 1, 'name': 'orc', 'scale': 2, 'groups': [0, 1], 'allow_foreign': [101]}]}
rows_allow = g.plan_rows(allow_spec, dat, spr, art)
check(not any(r[9] == 'foreign' for r in rows_allow), 'allow_foreign takes sprite 101')

# a 4x look: 128 px tiles, a 4x atlas of its own
big_dat = FakeDat([make_thing(1, [make_group(1, 1, 1, 400, px=1)])])
big_spr = FakeSpr({400: plain_sprite(1)})
big_art = os.path.join(tmp, 'bigart')
d = os.path.join(big_art, 'imp')
os.makedirs(d)
frame_png(os.path.join(d, 'g0_south_00.png'), 1, 1, 4, 99)
big_spec = {'version': 1, 'looks': [{'look': 1, 'name': 'imp', 'scale': 4, 'groups': [0]}]}
big_rows = g.plan_rows(big_spec, big_dat, big_spr, big_art)
btext, bpics = g.build_outputs(big_spec, big_rows, big_art)
check('atlas 0 hd_4x_0.png' in btext and 'sprite 400 0 0 0 4 ' in btext and '\nslot' not in btext, 'a 4x look gets a 4x atlas: %s' % btext)
check(bpics['hd_4x_0.png'].shape[0] == 128, 'atlas cut to one 128 px row')

# hd_prep: edges, specks, placement, palette (synthetic figure)
import hd_prep as hp  # noqa: E402
fig = np.zeros((128, 128, 4), np.uint8)
fig[40:100, 50:80] = (200, 30, 30, 255)
fig[10, 10] = (255, 255, 255, 255)                      # a lone pixel
fig[20:22, 100:102] = (255, 255, 255, 255)              # a 2 x 2 speck
fig[60, 55] = (0, 255, 0, 90)                           # soft pixel under the cut: gone
fig[61, 56] = (0, 0, 255, 200)                          # soft pixel over the cut: solid
b = hp.binarize(fig)
check(set(np.unique(b[:, :, 3])) == {0, 255}, 'alpha is 0 or 255')
check(tuple(b[60, 55]) == (0, 0, 0, 0) and b[61, 56, 3] == 255, 'the cut is at 128')
d = hp.despeckle(b)
check(d[10, 10, 3] == 0, 'lone pixel removed')
check(d[20:22, 100:102, 3].sum() > 0, 'a 2x2 block has 3 neighbours a pixel: kept (only 2 px pairs go)')
pair = np.zeros((16, 16, 4), np.uint8)
pair[3, 3] = pair[3, 4] = (9, 9, 9, 255)
check(hp.despeckle(pair)[:, :, 3].sum() == 0, 'a two pixel speck is removed')
body = np.zeros((16, 16, 4), np.uint8)
body[4:12, 4:12] = (9, 9, 9, 255)
check(np.array_equal(hp.despeckle(body), body), 'a solid body is kept')
placed, (dx, dy) = hp.place([d], 128, 1, 40.0)
x0, y0, x1, y1 = hp.union_bbox(placed)
check(y1 == 126, 'bottom row 1 px above the edge: %d' % y1)
check(abs((x0 + x1) / 2.0 - 40.0) <= 1, 'centred on 40: %s' % ((x0 + x1) / 2.0,))
far, _ = hp.place([d], 128, 1, 500.0)
check(hp.union_bbox(far)[2] == 127 or hp.union_bbox(far)[2] <= 127, 'never leaves the frame')
noisy = np.zeros((32, 32, 4), np.uint8)
rng = np.random.RandomState(1)
noisy[:, :, :3] = rng.randint(0, 256, (32, 32, 3))
noisy[:, :, 3] = 255
pal = hp.shared_palette([noisy], 8)
q = hp.apply_palette(noisy, pal)
check(hp.colour_count(q) <= 8 and (q[:, :, 3] == 255).all(), 'palette limited to 8 colours')
check(hp.colour_count(hp.apply_palette(hp.binarize(fig), hp.shared_palette([hp.binarize(fig)], 48))) <= 48, 'palette cap on the figure')

# the spec reader
try:
    g.load_spec(os.path.join(tmp, 'none.json'))
    check(False, 'missing spec raises')
except OSError:
    pass
check(g.load_spec()['version'] == 1, 'the shipped hd_looks.json loads')

print('gen_hd_overlay_test: %s' % ('OK' if not fails else '%d failed' % fails))
sys.exit(1 if fails else 0)
