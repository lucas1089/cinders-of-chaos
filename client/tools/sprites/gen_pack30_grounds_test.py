#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_pack30_grounds_test.py : gen_pack30_grounds.py on synthetic generated images only (no
pack image is read), plus the committed tables (spec, sources, sums) against each other. Needs numpy and Pillow (fx venv)."""
import os
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack30_grounds as G  # noqa: E402
import pack30lib as P  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def raises(fn, what, text=None):
    try:
        fn()
    except P.PackError as e:
        check(text is None or text in str(e), '%s (message %r)' % (what, str(e)))
        return
    check(False, what + ' (no error)')


def solid(w, h, rgb, alpha=255):
    a = np.zeros((h, w, 4), np.uint8)
    a[:] = rgb + (alpha,)
    return a


def pack(slug, label='set30 mutter', cat='grounds', status='ready'):
    return P.Pack(slug, label, 'v1', status, cat, '', 'x', 'high', '', '', '1', '1', '')


class Fixture:
    """a temp drivepacks folder with synthetic files and the matching FileRow list"""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix='g30test_')
        self.rows = []

    def add(self, slug, path, arr):
        full = os.path.join(self.dir, slug, *path.split('/'))
        os.makedirs(os.path.dirname(full), exist_ok=True)
        Image.fromarray(arr, 'RGBA').save(full)
        self.rows.append(P.FileRow(slug, path, str(os.path.getsize(full)), P.file_md5(full), str(arr.shape[1]), str(arr.shape[0])))


def tile_bytes(i):
    return (i * 7 % 256, i * 13 % 256, i * 29 % 256)


# ------------------------------------------------------------------------------------------------ selection rules
rows = [P.FileRow('pk', p, '1', 'x', str(w), str(h)) for p, w, h in [
    ('floor/spr_mud_1.png', 32, 32),
    ('Ground/Dirt Path/spr_dirt_path_t_down_1.png', 32, 32),
    ('Ground/spr_flower_1.png', 32, 32),              # object word
    ('Ground/spr_tree_stump_1.png', 32, 32),
    ('Ground/spr_log_1.png', 32, 32),
    ('floor/spr_rock.png', 32, 32),
    ('floors/big.png', 96, 96),                       # too big for a tile
    ('floor/old_path_h.png', 64, 64),                 # four cells
    ('sand_floor_tile_2.png', 32, 32),                # a floor word, no folder
    ('Rocks/spr_rock_1.png', 64, 64),
    ('spr_lava_island_top_strip9.png', 288, 32),
    ('spr_lava_pool_strip9.png', 576, 64),
    ('mine_wall_light_strip9.png', 576, 64),          # an animated object, not a floor
    ('Sheet_1_Floors.png', 197, 131),
    ('notes.json', 0, 0)]]
rows += [P.FileRow('other', 'floor/x.png', '1', 'x', '32', '32'), P.FileRow('pend', 'floor/x.png', '1', 'x', '32', '32')]
G_SHEETS = dict(G.SHEETS)
G.SHEETS[('pk', 'Sheet_1_Floors.png')] = None
packs = [pack('pk'), pack('other', cat='decor'), pack('pend', status='pending')]
jobs = G.plan_jobs(rows, packs)
paths = [(j[1], j[2]) for j in jobs]
check(('floor/spr_mud_1.png', 'tile') in paths and ('Ground/Dirt Path/spr_dirt_path_t_down_1.png', 'tile') in paths,
      'select: floor folders')
check(('sand_floor_tile_2.png', 'tile') in paths, 'select: a floor word in the name')
check(not any('flower' in p or 'stump' in p or 'log_1' in p or 'rock' in p.lower() for p, m in paths), 'select: object words out')
check(('floors/big.png', 'tile') not in paths, 'select: 96 px file is not a tile')
check(('floor/old_path_h.png', 'tile') in paths, 'select: 64 px tile file')
check(('spr_lava_island_top_strip9.png', 'strip') in paths and ('spr_lava_pool_strip9.png', 'strip') in paths, 'select: animated floors')
check(('mine_wall_light_strip9.png', 'strip') not in paths, 'select: other strips out')
check(('Sheet_1_Floors.png', 'sheet') in paths, 'select: sheet from SHEETS')
check(not any(j[0] in ('other', 'pend') for j in jobs), 'select: only ready packs with the grounds category')
check(jobs == G.plan_jobs(list(reversed(rows)), packs), 'select: order does not depend on input order')

# ------------------------------------------------------------------------------------------------ cutting and classes
fx = Fixture()
fx.add('pk', 'floor/spr_mud_1.png', solid(32, 32, (255, 0, 0)))                 # opaque red -> ground, minimap 180
corner = solid(32, 32, (0, 255, 0))
corner[:8, :8] = 0                                                              # transparent corner -> border
fx.add('pk', 'floor/spr_edge.png', corner)
fx.add('pk', 'floor/spr_void.png', np.zeros((32, 32, 4), np.uint8))             # nothing -> dropped
fx.add('pk', 'floor/spr_mud_copy.png', solid(32, 32, (255, 0, 0)))              # exact duplicate -> kept once
faint = solid(32, 32, (9, 9, 9), 5)                                             # alpha under 12 is cleared -> empty
fx.add('pk', 'floor/spr_faint.png', faint)
two = np.zeros((32, 32, 4), np.uint8)
two[:, :16] = (255, 0, 0, 255)
two[:, 16:] = (0, 0, 255, 255)
fx.add('pk', 'floor/spr_two.png', two)                                          # mean (127.5 -> 128, 0, 128)
quad = np.concatenate([np.concatenate([solid(32, 32, tile_bytes(1)), solid(32, 32, tile_bytes(2))], 1),
                       np.concatenate([solid(32, 32, tile_bytes(3)), solid(32, 32, tile_bytes(4))], 1)], 0)
fx.add('pk', 'floor/old_path_h.png', quad)                                      # 64 x 64: four cells
frames = [solid(32, 32, (10 * i + 1, 50, 200)) for i in range(9)]
fx.add('pk', 'spr_lava_island_top_strip9.png', np.concatenate(frames, 1))       # 9 phases, opaque
pool = [np.concatenate([np.concatenate([solid(32, 32, (200, 20 * i + 1, 0)), solid(32, 32, (190, 20 * i + 2, 0))], 1),
                        np.concatenate([solid(32, 32, (180, 20 * i + 3, 0)), solid(32, 32, (170, 20 * i + 4, 0))], 1)], 0)
        for i in range(9)]
fx.add('pk', 'spr_lava_pool_strip9.png', np.concatenate(pool, 1))              # 64 px frames -> four animated cells
lake = [solid(32, 32, (0, 0, 200 - i)) for i in range(7)]
for f in lake:
    f[:, 28:] = 0
fx.add('pk', 'spr_lake_tile_strip7.png', np.concatenate(lake, 1))              # partly clear -> an animated overlay
# gap sheets: 197 x 131 (6 x 4 cells), cell k a flat colour, the gaps clear
sh = np.zeros((131, 197, 4), np.uint8)
for r in range(4):
    for c in range(6):
        sh[r * 33:r * 33 + 32, c * 33:c * 33 + 32] = tile_bytes(r * 6 + c + 100) + (255,)
sh[0:32, 5 * 33:5 * 33 + 32] = 0                                                # one empty cell
fx.add('pk', 'Sheet_1_Floors.png', sh)
packs1 = [pack('pk')]
tiles, rep = G.collect(fx.dir, fx.rows, packs1, {}, {})
by = {t.key: t for t in tiles}
check(by['pk__mud_1'].kind == 'ground' and by['pk__mud_1'].opaque, 'class: opaque tile is a ground')
check(by['pk__edge'].kind == 'border' and not by['pk__edge'].opaque, 'class: tile with a clear corner is a border')
check('pk__void' not in by and 'pk__faint' not in by and len(rep['dropped']) >= 3, 'class: empty tiles dropped and listed')
check('pk__mud_copy' not in by and ('pk__mud_copy', 'pk__mud_1') in rep['dups'], 'dedupe: exact copy kept once')
check('minimap:180' in by['pk__mud_1'].flags and by['pk__mud_1'].flags.startswith('ground:100 notmoveable '),
      'minimap: solid red is index 180 (6x6x6 cube)')
check(by['pk__two'].minimap == P.rgb_to_minimap_index((128, 0, 128)) and by['pk__two'].minimap == 36 * 3 + 3,
      'minimap: the mean colour of the tile picks the index')
check('fullground' in by['pk__mud_1'].flags and 'clip' in by['pk__edge'].flags and 'minimap' not in by['pk__edge'].flags,
      'flags: ground vs overlay')
# 64 px tile file: four cells, keys with the cell, pixels in place
quads = [by['pk__old_path_h__r%dc%d' % rc] for rc in ((0, 0), (0, 1), (1, 0), (1, 1))]
check([tuple(q.frames[0][5, 5, :3]) for q in quads] == [tile_bytes(i) for i in (1, 2, 3, 4)], 'tile file: cells in reading order')
# animated strip
top = by['pk__lava_island_top']
check(len(top.frames) == 9 and top.kind == 'ground' and 'animateAlways' in top.flags and top.flags.endswith('animateAlways'),
      'strip: 9 phases, animated ground')
check([int(f[0, 0, 0]) for f in top.frames] == [10 * i + 1 for i in range(9)], 'strip: frames in order')
pools = [by['pk__lava_pool__r%dc%d' % rc] for rc in ((0, 0), (0, 1), (1, 0), (1, 1))]
check(all(len(p.frames) == 9 and p.kind == 'water' for p in pools), 'strip: 64 px frames give four animated liquid cells')
check([int(p.frames[3][0, 0, 1]) for p in pools] == [61, 62, 63, 64], 'strip: each cell follows its quarter')
check(all('notwalkable' in p.flags and 'light:2:195' in p.flags for p in pools), 'lava: notwalkable and light')
lk = by['pk__lake_tile']
check(lk.kind == 'border' and len(lk.frames) == 7 and 'minimap' not in lk.flags, 'strip: a partly clear water strip is an animated overlay')
# gap grid
cells = [t for t in tiles if t.path == 'Sheet_1_Floors.png']
check(len(cells) == 23, 'sheet: 24 cells of a 197 x 131 gap grid, the empty one dropped (%d)' % len(cells))
check(all(t.cell is not None and t.key.startswith('pk__floors__r') for t in cells), 'sheet: keys carry the cell')
c = {t.cell: t for t in cells}
check(tuple(c[(2, 4)].frames[0][0, 0, :3]) == tile_bytes(2 * 6 + 4 + 100) and tuple(c[(3, 5)].frames[0][31, 31, :3]) == tile_bytes(3 * 6 + 5 + 100),
      'sheet: cells at pitch 33, 32 px each')
check((0, 5) not in c, 'sheet: the empty cell is not a tile')
sh131 = np.zeros((131, 131, 4), np.uint8)
for r in range(4):
    for cc in range(4):
        sh131[r * 33:r * 33 + 32, cc * 33:cc * 33 + 32] = tile_bytes(r * 4 + cc + 200) + (255,)
fx2 = Fixture()
fx2.add('pk', 'Sheet_2_Ground.png', sh131)
G.SHEETS[('pk', 'Sheet_2_Ground.png')] = None
t2, _ = G.collect(fx2.dir, fx2.rows, packs1, {}, {})
check(len(t2) == 16 and all(t.kind == 'ground' for t in t2), 'sheet: 131 px = 4 x 4 cells')
check(tuple(t2[5].frames[0][0, 0, :3]) == tile_bytes(5 + 200), 'sheet 131: row-major order')
# cap, sheet with no gap grid (1024-style cut at 32)
big = np.zeros((128, 128, 4), np.uint8)
for r in range(4):
    for cc in range(4):
        big[r * 32:(r + 1) * 32, cc * 32:(cc + 1) * 32] = tile_bytes(r * 4 + cc + 50) + (255,)
big[:, 31] = big[:, 32]                       # components cross the cell edge -> grid_detect(32) cannot decide... still 32
fx3 = Fixture()
fx3.add('pk', 'Big_Floors.png', big)
G.SHEETS[('pk', 'Big_Floors.png')] = 5
t3, rep3 = G.collect(fx3.dir, fx3.rows, packs1, {}, {})
check(len(t3) == 5 and len(rep3['capped']) == 11, 'sheet: the cap keeps the first 5 cells in reading order (%d, %d)' % (len(t3), len(rep3['capped'])))

# ------------------------------------------------------------------------------------------------ md5 and overrides
bad = [P.FileRow(r.slug, r.path, r.size, '0' * 32, r.w, r.h) for r in fx3.rows]
raises(lambda: G.collect(fx3.dir, bad, packs1, {}, {}), 'a file whose md5 differs from the list is refused', 'md5')
ov = {'pk__mud_1': {'rename': 'Red Test Floor'}, 'pk__edge': {'skip': 1}, 'pk__two': {'kind': 'border'},
      'pk__lava_pool__r0c0': {'light': (3, 150), 'blocking': 0}}
t4, _ = G.collect(fx.dir, fx.rows, packs1, {}, ov)
b4 = {t.key: t for t in t4}
check(b4['pk__mud_1'].name == 'Red Test Floor' and 'pk__edge' not in b4, 'overrides: rename, skip')
check(b4['pk__two'].kind == 'border' and 'minimap' not in b4['pk__two'].flags, 'overrides: kind border drops the minimap colour')
check('light:3:150' in b4['pk__lava_pool__r0c0'].flags and 'light:2:195' not in b4['pk__lava_pool__r0c0'].flags, 'overrides: light')
raises(lambda: G.collect(fx.dir, fx.rows, packs1, {}, {'pk__mud_1': {'kind': 'tree'}}), 'override kind must be known', 'kind')

# ------------------------------------------------------------------------------------------------ overflow
old = G.BLOCK
G.BLOCK = 6
try:
    raises(lambda: G.collect(fx.dir, fx.rows, packs1, {}, {}), 'more tiles than the block holds stops the build', 'move the overflow')
finally:
    G.BLOCK = old
check(G.FIRST_ID == 34859 and G.LAST_ID == 35158 and G.BLOCK == 300, 'block: client ids 34859..35158 (300)')

# ------------------------------------------------------------------------------------------------ tables, atlas layout
tables = G.tables(tiles)
spec = tables[G.SPEC]
rows_ = G.parse_csv(spec)
check(rows_[0] == G.FIELDS and len(rows_) == len(tiles) + 1, 'spec: header and one row per tile')
check(G.tables(G.collect(fx.dir, fx.rows, packs1, {}, {})[0]) == tables, 'deterministic: a rebuild gives identical tables')
sheets = G.atlases(tiles)
check(list(sheets) == ['pack30_grounds/grounds_1.png'], 'atlas: %d tiles fit one atlas' % len(tiles))
atl = sheets['pack30_grounds/grounds_1.png']
ok = True
for i, (t, r) in enumerate(zip(tiles, rows_[1:])):
    ph = int(r[10])
    ok &= (int(r[6]) == i * 32 and int(r[5]) == 0 and ph == len(t.frames))
    for f, fr in enumerate(t.frames):
        ok &= bool(np.array_equal(atl[i * 32:(i + 1) * 32, f * 32:(f + 1) * 32], fr))
check(ok, 'atlas: row y = 32 * place, phase f at x = 32 * f, pixels equal the tile')
check(atl.shape == (len(tiles) * 32, 9 * 32, 4), 'atlas: width is the widest tile')
check(all(r[11].count('animateAlways') == (r[10] != '1') and (r[10] != '1') == ('ms=' in r[14]) for r in rows_[1:]), 'spec: animated rows carry ms')
check(all(('ms=160' in r[14]) for r in rows_[1:] if r[0].startswith('pk__lava') or r[0].startswith('pk__lake')), 'spec: liquids share one ms')
check(all(r[14].startswith('family=pk|variant=') for r in rows_[1:]), 'spec: family first')
check([int(G.extra_of(r[14])['variant']) for r in rows_[1:]] == list(range(1, len(tiles) + 1)), 'spec: variant counts up in the family')
srcs = G.tables(tiles)[G.SOURCES_CSV]
sr = G.parse_csv(srcs)
check(sr[0] == G.SOURCE_FIELDS and all(x[2] == 'set30 mutter' for x in sr[1:]), 'sources: label per row')
check(any(x[3] == 'pk/Sheet_1_Floors.png[r2c4]' for x in sr[1:]) and any(x[3] == 'pk/floor/spr_mud_1.png' for x in sr[1:]),
      'sources: file and cell')
# the overflow arithmetic of atlas places across atlases
check(G.atlas_of(0) == ('pack30_grounds/grounds_1', 0) and G.atlas_of(100) == ('pack30_grounds/grounds_2', 0)
      and G.atlas_of(257) == ('pack30_grounds/grounds_3', 57 * 32), 'atlas_of: 100 tiles per atlas')

# ------------------------------------------------------------------------------------------------ check_tables
files = [P.FileRow(r.slug, r.path, r.size, r.md5, r.w, r.h) for r in fx.rows]
sums = P.sums_text(sorted(sheets.items()))
check(G.check_tables(spec, srcs, sums, packs1, files) == [], 'check_tables: a fresh build passes: %s' % G.check_tables(spec, srcs, sums, packs1, files))
with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, 'pack30_grounds'))
    Image.fromarray(atl, 'RGBA').save(os.path.join(d, 'pack30_grounds', 'grounds_1.png'))
    check(G.check_tables(spec, srcs, sums, packs1, files, atlas_dir=d) == [], 'check_tables: atlas on disk matches the sums')
    atl2 = atl.copy()
    atl2[0, 0] = (1, 2, 3, 255)
    Image.fromarray(atl2, 'RGBA').save(os.path.join(d, 'pack30_grounds', 'grounds_1.png'))
    check(any('differs' in b for b in G.check_tables(spec, srcs, sums, packs1, files, atlas_dir=d)), 'check_tables: changed atlas found')


def mut(old_s, new_s, text=spec):
    return text.replace(old_s, new_s, 1)


check(any('minimap' in b for b in G.check_tables(mut('minimap:180', 'minimap:216'), srcs, sums, packs1, files)), 'check_tables: minimap colour range')
check(any('duplicate' in b for b in G.check_tables(mut('pk__edge,', 'pk__mud_1,'), srcs, sums, packs1, files)), 'check_tables: duplicate key')
check(any('atlas place' in b for b in G.check_tables(mut(',0,32,1,1,1,1', ',0,64,1,1,1,1'), srcs, sums, packs1, files)), 'check_tables: atlas place')
check(any('animateAlways' in b for b in G.check_tables(mut('fullground animateAlways', 'fullground'), srcs, sums, packs1, files)), 'check_tables: animation flag')
check(any('files' in b for b in G.check_tables(spec, mut('pk/floor/spr_mud_1.png', 'pk/floor/nope.png', srcs), sums, packs1, files)), 'check_tables: source must be listed')
check(any('label' in b for b in G.check_tables(spec, mut('set30 mutter', 'set30 pocket', srcs), sums, packs1, files)), 'check_tables: label of the pack')
check(any('sums' in b for b in G.check_tables(spec, srcs, sums + 'ab  pack30_grounds/grounds_9.png\n', packs1, files)), 'check_tables: sums list')
many = spec + '\n'.join(','.join(['k%d__a' % i] + spec.splitlines()[1].split(',')[1:]) for i in range(300)) + '\n'
check(any('block holds' in b for b in G.check_tables(many, srcs, sums, packs1, files)), 'check_tables: more rows than the block')

# ------------------------------------------------------------------------------------------------ the committed tables
G.SHEETS.clear()
G.SHEETS.update(G_SHEETS)
if os.path.exists(G.SPEC):
    committed = G.check_tables(open(G.SPEC, newline='').read(), open(G.SOURCES_CSV, newline='').read(),
                               open(G.SUMS, newline='').read(), P.load_packs(), P.read_files(P.files_path('grounds')),
                               atlas_dir=P.ART)
    check(committed == [], 'committed tables: %s' % committed[:3])
    n = len(G.parse_csv(open(G.SPEC, newline='').read())) - 1
    check(0 < n <= G.BLOCK, 'committed tables: %d tiles in a block of %d' % (n, G.BLOCK))

print('gen_pack30_grounds_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
