#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_pack30_items_test.py : gen_pack30_items.py on synthetic generated images only (no
pack image is read), plus the committed tables (spec, sources, sums) against each other. Needs numpy and Pillow (fx venv)."""
import os
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack30_items as G  # noqa: E402
import import_art_things as IAT  # noqa: E402
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


def col(i):
    return (i * 7 % 256, i * 13 % 256, i * 29 % 256)


def pack(slug, label='set30 mutter', cat='items', status='ready', also=''):
    return P.Pack(slug, label, 'v1', status, cat, also, 'x', 'high', '', '', '1', '1', '')


class Fixture:
    """a temp drivepacks folder with synthetic files and the matching FileRow list"""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix='i30test_')
        self.rows = []

    def add(self, slug, path, arr):
        full = os.path.join(self.dir, slug, *path.split('/'))
        os.makedirs(os.path.dirname(full), exist_ok=True)
        Image.fromarray(arr, 'RGBA').save(full)
        self.rows.append(P.FileRow(slug, path, str(os.path.getsize(full)), P.file_md5(full), str(arr.shape[1]), str(arr.shape[0])))


def sheet(cell, n, art, seed, skip=()):
    """n x n cells of `cell` px, each holding an art x art flat square (colour from the seed and place) at its top-left + 1"""
    a = np.zeros((cell * n, cell * n, 4), np.uint8)
    for r in range(n):
        for c in range(n):
            if (r, c) in skip:
                continue
            a[r * cell + 1:r * cell + 1 + art, c * cell + 1:c * cell + 1 + art] = col(seed + r * n + c) + (255,)
    return a


# ------------------------------------------------------------------------------------------------ selection
check(G.weapon_kind('swords_blades') == 'sword' and G.weapon_kind('axes_maces_hammers') == 'weapon' and
      G.weapon_kind('ranged_weapons') == 'weapon' and G.weapon_kind('shields_and_magic_weapons') == 'weapon' and
      G.weapon_kind('maces_hammers') == 'club' and G.weapon_kind('stuff') == 'weapon', 'weapon_kind: one class word or weapon')
check(G.stem_of('weapons', 'Sheet_1_Swords_Blades.png') == 'swords_blades' and G.stem_of('mini_books', 'Red Book Open.png') == 'red_book_open',
      'stem_of: no sheet number, no extension')
rows = [P.FileRow(s, p, '1', 'x', '32', '32') for s, p in [
    ('weapons', 'Sheet_1_Swords.png'), ('weapons', 'notes.json'),
    ('potions', 'pocoes/veneno/great/tira.png'), ('potions', 'pocoes/lava/health/tira.png'), ('potions', 'pocoes/lava/great/tira.png'),
    ('potions', 'pocoes/lava/health/parada.png'), ('potions', 'efeitos/bomba_veneno_v1/tira.png'),
    ('potions', 'projeteis/pocao_lava_v2/folha_3x3.png'), ('mini_books', 'Book_A.png'), ('other', 'x.png')]]
packs = [pack('weapons'), pack('potions', 'set30 potions', 'fx', also='items'), pack('mini_books', status='pending'),
         pack('other', cat='decor')]
jobs = G.plan_jobs(rows, packs)
check([(j[1], j[2]) for j in jobs] == [('pocoes/lava/health/tira.png', 'flask'), ('pocoes/lava/great/tira.png', 'flask'),
                                       ('pocoes/veneno/great/tira.png', 'flask'), ('Sheet_1_Swords.png', 'sheet')]
      or [j[2] for j in jobs] == ['sheet', 'flask', 'flask', 'flask'], 'select: sheets and the six tira strips only: %s' % jobs)
check([j[1] for j in jobs if j[2] == 'flask'] == ['pocoes/lava/health/tira.png', 'pocoes/lava/great/tira.png',
                                                   'pocoes/veneno/great/tira.png'], 'select: flasks lava before venom, small to large')
check(not any(j[0] in ('other', 'mini_books') for j in jobs), 'select: pending / other-category packs skipped')
packs_b = [pack('weapons'), pack('mini_books')]
check(('Book_A.png', 'book') in [(j[1], j[2]) for j in G.plan_jobs(rows, packs_b)], 'select: a ready book pack is cut')
raises(lambda: G.plan_jobs(rows, [pack('mystery')]), 'a ready items pack without a rule stops the build', 'rule')
check(jobs == G.plan_jobs(list(reversed(rows)), packs), 'select: order does not depend on input order')

# ------------------------------------------------------------------------------------------------ grid decision
a64 = sheet(64, 2, 60, 10)                    # art of 60 px: only 64 (and 128) cells hold it
cut, grid, valid = G.cut_sheet(P.clean_alpha(a64), 'weapons', 's.png', 'weapons__s', {})
check(grid == '64' and valid == [64, 128] and len(cut) == 4 and all((i.tw, i.th) == (2, 2) for i in cut),
      '64 px cells: 2x2 items, no scaling (%s %s)' % (grid, valid))
check([i.cell for i in cut] == ['r0c0', 'r0c1', 'r1c0', 'r1c1'] and tuple(cut[3].frames[0][1, 1, :3]) == col(13),
      '64 px cells: reading order, pixels in place')
a32 = sheet(32, 4, 28, 20)
cut, grid, valid = G.cut_sheet(P.clean_alpha(a32), 'weapons', 's.png', 'weapons__s', {})
check(grid == '32' and len(cut) == 16 and all((i.tw, i.th) == (1, 1) for i in cut) and valid[0] == 32, '32 px cells: 1x1 items')
a16 = sheet(16, 8, 12, 30)                    # 12 px art in 16 px cells (also fits 32)
cut, grid, valid = G.cut_sheet(P.clean_alpha(a16), 'weapons', 's.png', 'weapons__s', {})
check(grid == '16' and len(cut) == 64 and cut[0].frames[0].shape == (32, 32, 4) and valid[:2] == [16, 32],
      '16 px cells: Scale2x to 32, smallest valid cell wins')
check(cut[0].frames[0][3, 3, 3] == 255 and cut[0].frames[0][0, 0, 3] == 0 and tuple(cut[5].frames[0][4, 4, :3]) == col(35),
      '16 px cells: 12 px art becomes 24 px, in the right cell')
c2, g2, _ = G.cut_sheet(P.clean_alpha(a16), 'weapons', 's.png', 'weapons__s', {'weapons__s': {'tiles': (1, 1)}})
check(g2 == '32' and len(c2) == 16, 'override tiles,1 forces 32 px cells')
c3, g3, _ = G.cut_sheet(P.clean_alpha(a32), 'weapons', 's.png', 'weapons__s', {'weapons__s': {'scale2x': 1}})
check(g3 == '16' and len(c3) == 64, 'override scale2x,1 forces 16 px cells')
c4, g4, _ = G.cut_sheet(P.clean_alpha(a32), 'weapons', 's.png', 'weapons__s', {'weapons__s': {'tiles': (2, 2)}})
check(g4 == '64' and len(c4) == 4 and c4[0].tw == 2, 'override tiles,2 forces 64 px cells')
raises(lambda: G.cut_sheet(P.clean_alpha(sheet(32, 3, 28, 1)), 'weapons', 's.png', 'weapons__s', {'weapons__s': {'tiles': (2, 2)}}),
       'a forced grid that does not divide the sheet is refused', 'not a grid')
# no grid: art crossing every cell edge in a 100 x 100 sheet -> segments of whole 32 px cells
seg = np.zeros((100, 100, 4), np.uint8)
seg[3:30, 3:30] = (9, 9, 9, 255)
seg[40:90, 40:70] = (8, 8, 8, 255)
cut, grid, valid = G.cut_sheet(P.clean_alpha(seg), 'weapons', 's.png', 'weapons__s', {})
check(grid == 'seg' and valid == [] and [i.cell for i in cut] == ['y0x0', 'y32x32'] and (cut[1].tw, cut[1].th) == (2, 2),
      'no grid: segment boxes grown to the 32 px grid (%s)' % [(i.cell, i.tw, i.th) for i in cut])
huge = np.zeros((300, 300, 4), np.uint8)
huge[2:200, 2:30] = (1, 1, 1, 255)
raises(lambda: G.cut_sheet(huge, 'weapons', 's.png', 'weapons__s', {}), 'art above 4 tiles stops the build', 'larger than')

# ------------------------------------------------------------------------------------------------ collect: weapons, flasks, books
fx = Fixture()
w1 = sheet(64, 2, 60, 100, skip=((1, 1),))                     # one empty cell
fx.add('weapons', 'Sheet_1_Swords_Blades.png', w1)
w2 = sheet(64, 2, 60, 100)                                     # same colours as w1: three exact duplicates
fx.add('weapons', 'Sheet_2_Axes_Maces_Hammers.png', w2)
for el in ('lava', 'veneno'):
    for k, sz in enumerate(('health', 'strong', 'great')):
        fr = np.concatenate([solid(32, 32, col(50 + 10 * k + f + (3 if el == 'veneno' else 0))) for f in range(8)], 1)
        fx.add('potions', 'pocoes/%s/%s/tira.png' % (el, sz), fr)
        fx.add('potions', 'pocoes/%s/%s/parada.png' % (el, sz), solid(32, 32, (1, 2, 3)))
fx.add('potions', 'efeitos/bomba_veneno_v1/tira.png', np.zeros((32, 384, 4), np.uint8))
packs1 = [pack('weapons'), pack('potions', 'set30 potions', 'fx', also='items')]
items, rep = G.collect(fx.dir, fx.rows, packs1, {}, {})
keys = [i.key for i in items]
check(len(items) == 4 + 6 and keys[0] == 'weapons__swords_blades__r0c0' and keys[2] == 'weapons__swords_blades__r1c0' and keys[3] == 'weapons__axes_maces_hammers__r1c1',
      'collect: 3 sheet-1 cells (one empty dropped), sheet 2 only its new cell, 6 flasks (%d)' % len(items))
check(len(rep['dups']) == 3 and len(rep['dropped']) == 1 and rep['dups'][0][1] == 'weapons__swords_blades__r0c0',
      'collect: duplicates and the empty cell are listed')
check(all(i.block == 'a' for i in items[:4]) and all(i.block == 'c' for i in items[4:]), 'collect: blocks')
check([i.key for i in items[4:]] == ['potions__lava_flask_small', 'potions__lava_flask_medium', 'potions__lava_flask_large',
                                     'potions__venom_flask_small', 'potions__venom_flask_medium', 'potions__venom_flask_large'],
      'flasks: keys, lava before venom, small to large')
fl = items[4]
check(fl.kind == 'flask' and fl.name == 'lava flask (small)' and len(fl.frames) == 8 and fl.flags == 'pickupable stackable animateAlways'
      and fl.extra['ms'] == '125', 'flask: 8 phases, name, flags, 125 ms')
check([int(f[0, 0, 0]) for f in fl.frames] == [col(50 + f)[0] for f in range(8)], 'flask: frames in order')
check(items[0].kind == 'sword' and items[0].flags == 'pickupable' and items[0].name == 'swords blades r0c0', 'weapon: kind, flags, name')
# overrides
ov = {'weapons__swords_blades__r0c0': {'rename': 'Test Blade', 'kind': 'axe', 'light': (2, 100)},
      'weapons__swords_blades__r0c1': {'skip': 1}, 'potions__venom_flask_large': {'flags': 'pickupable animateAlways'},
      'weapons__axes_maces_hammers': {'skip': 1}}
i4, _ = G.collect(fx.dir, fx.rows, packs1, {}, ov)
b4 = {i.key: i for i in i4}
check(b4['weapons__swords_blades__r0c0'].name == 'Test Blade' and b4['weapons__swords_blades__r0c0'].kind == 'axe'
      and 'light:2:100' in b4['weapons__swords_blades__r0c0'].flags, 'overrides: rename, kind, light')
check('weapons__swords_blades__r0c1' not in b4 and b4['potions__venom_flask_large'].flags == 'pickupable animateAlways', 'overrides: skip, flags')
check(len(i4) == 8, 'overrides: skipping a sheet by its key')
raises(lambda: G.collect(fx.dir, fx.rows, packs1, {}, {'weapons__swords_blades__r0c0': {'kind': 'tree'}}),
       'an unknown kind override is refused', 'kind')
bad = [P.FileRow(r.slug, r.path, r.size, '0' * 32, r.w, r.h) for r in fx.rows]
raises(lambda: G.collect(fx.dir, bad, packs1, {}, {}), 'a file whose md5 differs from the list is refused', 'md5')
fx_bad = Fixture()
fx_bad.add('potions', 'pocoes/lava/health/tira.png', np.zeros((16, 256, 4), np.uint8) + 255)
raises(lambda: G.collect(fx_bad.dir, fx_bad.rows, [pack('potions', 'set30 potions', 'fx', also='items')], {}, {}),
       'a flask strip of 16 px frames stops', 'square frames')
# books (second batch)
fb = Fixture()
fb.add('mini_books', 'Red_Book_Open.png', np.concatenate([solid(32, 32, col(f + 1)) for f in range(7)], 1))
fb.add('mini_books', 'Red_Book_Closed.png', np.concatenate([solid(16, 16, col(f + 9)) for f in range(7)], 1))
ib, _ = G.collect(fb.dir, fb.rows, [pack('mini_books')], {}, {})
check([i.key for i in ib] == ['mini_books__red_book_closed', 'mini_books__red_book_open'] and all(i.block == 'b' for i in ib), 'books: keys, block B')
check(all(i.kind == 'spellbook' and len(i.frames) == 7 and 'animateAlways' in i.flags and i.extra['ms'] == '120' for i in ib)
      and ib[0].frames[0].shape == (32, 32, 4), 'books: 7 phases, animated, 16 px frames upscaled')

# ------------------------------------------------------------------------------------------------ blocks, overflow, pads
old = dict(G.BLOCKS)
G.BLOCKS['a'] = (34443, 2)
try:
    raises(lambda: G.collect(fx.dir, fx.rows, packs1, {}, {}), 'more items than block A holds stops the build', 'move the overflow')
finally:
    G.BLOCKS.update(old)
check(G.BLOCKS == {'a': (34443, 256), 'b': (34699, 20), 'c': (34719, 20), 'd': (34739, 20)} and G.LAST_ID == 34758 and G.ALL_IDS == 316,
      'blocks: client ids 34443..34758 (316)')
slots = G.layout(items)
ids = [c for c, _ in slots]
check(ids == list(range(34443, 34443 + len(slots))), 'layout: contiguous ids')
check([c for c, i in slots if i is not None and i.block == 'c'][0] == 34719, 'layout: the first flask is id 34719')
check(sum(1 for c, i in slots if i is None) == (256 - 4) + 20 and slots[-1][1] is not None and slots[-1][0] == 34724,
      'layout: A and B padded to their size, nothing after the last flask')
only_a = [i for i in items if i.block == 'a']
check(all(i is not None for _, i in G.layout(only_a)) and len(G.layout(only_a)) == 4, 'layout: no pad rows without a later block')

# ------------------------------------------------------------------------------------------------ tables, atlases
tab = G.tables(items)
spec = tab[G.SPEC]
rows_ = G.parse_csv(spec)
check(rows_[0] == G.FIELDS and len(rows_) == 1 + 4 + 252 + 20 + 6, 'spec: header and one row per id (%d)' % len(rows_))
check(G.tables(G.collect(fx.dir, fx.rows, packs1, {}, {})[0]) == tab, 'deterministic: a rebuild gives identical tables')
r0 = rows_[1]
check(r0[7:10] == ['2', '2', '1'] and r0[11] == 'pickupable' and r0[12] == 'new' and r0[13] == '', 'spec: 2x2 weapon row')
pads = [r for r in rows_[1:] if r[0].startswith('pad_')]
check(len(pads) == 272 and pads[0][0] == 'pad_34447' and pads[0][6] == str(4 * 64) and pads[0][2] == 'decor' and pads[0][11] == ''
      and pads[0][14] == 'blank=1', 'spec: pad rows point at the clear cell below the weapons')
check([r[6] for r in rows_[1:5]] == ['0', '64', '128', '192'], 'spec: weapon rows are 64 px apart')
sheets = G.atlases(items)
check(sorted(sheets) == ['pack30_items/items_a.png', 'pack30_items/items_c.png'], 'atlas: A (weapons + pad cell) and C (flasks)')
aa, ac = sheets['pack30_items/items_a.png'], sheets['pack30_items/items_c.png']
check(aa.shape == (4 * 64 + 32, 64, 4) and ac.shape == (6 * 32, 8 * 32, 4), 'atlas: shapes')
check(np.array_equal(aa[64:128], np.asarray(items[1].frames[0])) and not aa[256:].any(), 'atlas: 64 px rows, clear pad cell last')
check(all(np.array_equal(ac[k * 32:(k + 1) * 32, f * 32:(f + 1) * 32], items[4 + k].frames[f]) for k in range(6) for f in range(8)),
      'atlas: flask rows, phase f at x = 32 * f')
check(G.atlases(only_a).keys() == {'pack30_items/items_a.png'} and G.atlases(only_a)['pack30_items/items_a.png'].shape == (256, 64, 4),
      'atlas: no pad cell without pad rows')
srcs = tab[G.SOURCES_CSV]
sr = G.parse_csv(srcs)
check(sr[0] == G.SOURCE_FIELDS and len(sr) == 1 + 10 and sr[1][2] == 'set30 mutter' and sr[-1][2] == 'set30 potions', 'sources: label per row, no pad rows')
check(sr[1][3] == 'weapons/Sheet_1_Swords_Blades.png[r0c0]' and sr[5][3] == 'potions/pocoes/lava/health/tira.png', 'sources: file and cell')

# ------------------------------------------------------------------------------------------------ check_tables
files = [P.FileRow(r.slug, r.path, r.size, r.md5, r.w, r.h) for r in fx.rows]
sums = P.sums_text(sorted(sheets.items()))
res = G.check_tables(spec, srcs, sums, packs1, files)
check(res == [], 'check_tables: a fresh build passes: %s' % res[:3])
with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, 'pack30_items'))
    for rel, arr in sheets.items():
        Image.fromarray(arr, 'RGBA').save(os.path.join(d, rel))
    check(G.check_tables(spec, srcs, sums, packs1, files, atlas_dir=d) == [], 'check_tables: atlases on disk match the sums')
    aa2 = aa.copy()
    aa2[0, 0] = (1, 2, 3, 255)
    Image.fromarray(aa2, 'RGBA').save(os.path.join(d, 'pack30_items', 'items_a.png'))
    check(any('differs' in b for b in G.check_tables(spec, srcs, sums, packs1, files, atlas_dir=d)), 'check_tables: changed atlas found')


def mut(old_s, new_s, text=spec):
    assert old_s in text, old_s
    return text.replace(old_s, new_s, 1)


def probs(sp=spec, so=srcs, su=sums):
    return G.check_tables(sp, so, su, packs1, files)


check(any('duplicate' in b for b in probs(mut('potions__lava_flask_medium,', 'potions__lava_flask_small,'))), 'check_tables: duplicate key')
check(any('flags' in b for b in probs(mut('pickupable stackable animateAlways', 'pickupable sticky'))), 'check_tables: unknown flag')
check(any('animateAlways' in b for b in probs(mut('pickupable stackable animateAlways', 'pickupable stackable'))), 'check_tables: animation flag')
check(any('kind' in b for b in probs(mut('item,flask,lava flask (small)', 'item,tree,lava flask (small)'))), 'check_tables: kind')
check(any('atlas row' in b for b in probs(mut(',0,64,2,2', ',0,96,2,2'))), 'check_tables: atlas row follows the heights')
check(any('family' in b for b in probs(mut('family=potions|variant=1', 'family=weapons|variant=1'))), 'check_tables: family belongs to its block')
check(any('pad row' in b for b in probs(mut('pad_34447,item,decor', 'pad_34447,item,prop'))), 'check_tables: pad row shape')
check(any('size' in b for b in probs(mut(',0,0,2,2,1,1', ',0,0,5,2,1,1'))), 'check_tables: size within 4 tiles')
check(any('sources' in b and 'files' in b for b in probs(so=mut('Sheet_1_Swords_Blades.png[r0c0]', 'Nope.png[r0c0]', srcs))), 'check_tables: source must be listed')
check(any('outside' in b for b in probs(so=mut('[r0c0]', '[r9c9]', srcs))), 'check_tables: cell inside the file')
check(any('label' in b for b in probs(so=mut('set30 potions', 'set30 mutter', srcs))), 'check_tables: label of the pack')
check(any('sums' in b for b in probs(su=sums + 'ab  pack30_items/items_b.png\n')), 'check_tables: sums list')
lines = spec.splitlines()
check(any('last row' in b or 'pad' in b for b in probs('\n'.join(lines[:-6] + [lines[4]]) + '\n')), 'check_tables: no trailing pad row')
many = spec + '\n'.join(','.join(['k%d__a' % i] + lines[1].split(',')[1:]) for i in range(40)) + '\n'
check(any('hold' in b for b in G.check_tables(many, srcs, sums, packs1, files)), 'check_tables: more rows than the blocks hold')

# ------------------------------------------------------------------------------------------------ import_art_things kinds
check(all(k in IAT.OTB for k in G.KINDS), 'every kind has an OTB entry in import_art_things: %s' % [k for k in G.KINDS if k not in IAT.OTB])
check(IAT.OTB['flask'][1] & IAT.PICKUP and IAT.OTB['flask'][1] & IAT.STACK, 'flask kind is a stackable pickup')

# ------------------------------------------------------------------------------------------------ the committed tables
if os.path.exists(G.SPEC):
    committed = G.check_tables(open(G.SPEC, newline='').read(), open(G.SOURCES_CSV, newline='').read(),
                               open(G.SUMS, newline='').read(), P.load_packs(), P.read_files(P.files_path('items')),
                               atlas_dir=P.ART)
    check(committed == [], 'committed tables: %s' % committed[:3])
    n = len(G.parse_csv(open(G.SPEC, newline='').read())) - 1
    check(0 < n <= G.ALL_IDS, 'committed tables: %d rows in %d ids' % (n, G.ALL_IDS))

print('gen_pack30_items_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
