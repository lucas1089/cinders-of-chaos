#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_pack30_anim_test.py : gen_pack30_anim.py on synthetic generated images only (no pack
image is read), plus the committed tables (spec, sources, sums) against each other. Needs numpy and Pillow (fx venv)."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack30_anim as A  # noqa: E402
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


def pack(slug, label='set30 mutter', cat='anim', status='ready'):
    return P.Pack(slug, label, 'v1', status, cat, '', 'x', 'high', '', '', '1', '1', '')


def strip(n, fw, fh, fill=None, empty=()):
    """n frames of fw x fh; frame i is opaque with value 10 + i (so frames differ), or empty / only `fill` box"""
    a = np.zeros((fh, fw * n, 4), np.uint8)
    for i in range(n):
        if i in empty:
            continue
        x0, y0, x1, y1 = fill or (0, 0, fw, fh)
        a[y0:y1, i * fw + x0:i * fw + x1] = (10 + i, 20, 30, 255)
    return a


class Fix:
    def __init__(self):
        self.rows, self.arr = [], {}

    def add(self, slug, path, a):
        self.rows.append(P.FileRow(slug, path, '1', 'x', str(a.shape[1]), str(a.shape[0])))
        self.arr[(slug, path)] = a

    def load(self, row):
        return self.arr[(row.slug, row.path)]


packs = [pack('pk'), pack('other', cat='decor'), pack('pend', status='pending'), pack('pc', label='set30 pocket')]

# ------------------------------------------------------------------------------------------------ names and selection
fx = Fix()
fx.add('pk', 'spr_Void_Portal_strip7.png', strip(7, 64, 64))
fx.add('pk', 'Camp_Fire_strip9.png', strip(9, 64, 64))
fx.add('pk', 'sub/Small_Torch_strip9.png', strip(9, 32, 32))
fx.add('pk', 'spr_lava_pool_strip9.png', strip(9, 64, 64))            # an animated floor: grounds owns it
fx.add('pk', 'spr_lake_TILE_strip7.png', strip(7, 32, 32))
fx.add('pk', 'spr_Giant_Squid_attack_strip17.png', strip(17, 128, 128))   # not used
fx.add('pk', 'spr_Giant_Squid_idle_strip17.png', strip(17, 128, 128))
fx.add('pk', 'static_thing.png', strip(1, 64, 64))
fx.add('pk', 'notes.json', np.zeros((1, 1, 4), np.uint8))
fx.add('other', 'x_strip9.png', strip(9, 32, 32))
fx.add('pend', 'y_strip9.png', strip(9, 32, 32))
objs, rep = A.plan(fx.rows, packs)
keys = [o.key for o in objs]
check(keys == ['pk__camp_fire', 'pk__giant_squid_idle', 'pk__void_portal', 'pk__small_torch'], 'plan: keys %s' % keys)
check(rep['unused'] == ['pk/spr_Giant_Squid_attack_strip17.png'], 'plan: attack strip unused')
check(len(rep['floors']) == 2 and rep['static'] == 1, 'plan: floors %s, static %d' % (rep['floors'], rep['static']))
by = {o.key: o for o in objs}
check(by['pk__void_portal'].n == 7 and (by['pk__void_portal'].gw, by['pk__void_portal'].gh) == (2, 2), 'plan: portal 7 phases 2x2')
check(not by['pk__giant_squid_idle'].group and (by['pk__giant_squid_idle'].gw, by['pk__giant_squid_idle'].gh) == (4, 4),
      'plan: 4x4 stays one item')
check(A.stem_of('x/Spr_Void_Portal_strip7.png') == 'void_portal' and A.stem_of('sp_sewer_barrel_strip13.png') == 'sewer_barrel',
      'stem: prefix and strip dropped')
raises(lambda: A.plan([P.FileRow('pk', 'a_strip4.png', '1', 'x', '130', '32')], packs), 'plan: width not whole frames', 'whole frames')
raises(lambda: A.plan([P.FileRow('pk', 'a_strip1.png', '1', 'x', '32', '32')], packs), 'plan: one frame is no animation')
# same stem in two folders: the folder joins the key
dup = [P.FileRow('pk', 'a/tree_strip2.png', '1', 'x', '64', '32'), P.FileRow('pk', 'b/tree_strip2.png', '1', 'x', '64', '32')]
check([o.key for o in A.plan(dup, packs)[0]] == ['pk__tree', 'pk__b_tree'], 'plan: duplicate stem gets the folder')

# ------------------------------------------------------------------------------------------------ strip to phases
items, objs, rep = A.collect(fx.rows, packs, fx.load, {})
it = {i.key: i for i in items}
tp = it['pk__void_portal']
check((tp.piece.tw, tp.piece.th, len(tp.frames)) == (2, 2, 7), 'strip: portal is 2x2 with 7 phases')
check([int(f[63, 63, 0]) for f in tp.frames] == [10 + i for i in range(7)], 'strip: frames keep their order')
atl = A.layout(items)
a = atl['pack30_anim/pk.png']
check(a.shape[1] == max(i.piece.tw * 32 * i.obj.n for i in items), 'layout: atlas width = the widest strip')
check(a.shape[0] == sum(i.piece.th * 32 for i in items), 'layout: rows stacked')
check(all(np.array_equal(a[i.y:i.y + i.piece.th * 32, f * i.piece.tw * 32:(f + 1) * i.piece.tw * 32], i.frames[f])
          for i in items for f in range(i.obj.n)), 'layout: every phase at x = phase * width')
check([i.y for i in items] == sorted(i.y for i in items) and items[0].y == 0, 'layout: y grows in id order')

# ------------------------------------------------------------------------------------------------ padding
fx2 = Fix()
fx2.add('pk', 'zombie_fire_strip9.png', strip(9, 92, 92, fill=(0, 0, 92, 92)))
fx2.add('pk', 'magic_tower_1_strip7.png', strip(7, 68, 128, fill=(60, 120, 68, 128)))
fx2.add('pk', 'cell_wall_candle_strip9.png', strip(9, 48, 48))
i2 = {i.key: i for i in A.collect(fx2.rows, packs, fx2.load, {})[0]}
z = i2['pk__zombie_fire']
check((z.piece.tw, z.piece.th) == (3, 3) and z.frames[0].shape == (96, 96, 4), 'pad: 92 px frame becomes 96 (3x3)')
check(z.frames[0][3, 3, 3] == 0 and z.frames[0][4, 4, 3] == 255 and z.frames[0][95, 95, 3] == 255, 'pad: top-left padding, art bottom-right')
t = i2['pk__magic_tower_1']
check((t.piece.tw, t.piece.th) == (3, 4) and t.frames[0][127, 95, 3] == 255 and t.frames[0][127, 27, 3] == 0,
      'pad: 68 x 128 frame becomes 96 x 128 aligned bottom-right')
check((i2['pk__cell_wall_candle'].piece.tw, i2['pk__cell_wall_candle'].piece.th) == (2, 2), 'pad: 48 px becomes 64')

# ------------------------------------------------------------------------------------------------ split with equal timing
fx3 = Fix()
fx3.add('pk', 'big_portal_strip16.png', strip(16, 192, 192, fill=(0, 0, 192, 192)))
fx3.add('pk', 'spr_volcano_strip9.png', strip(9, 256, 256, fill=(140, 0, 256, 256)))   # west pieces empty
fx3.add('pk', 'spr_volcano_2_strip7.png', strip(7, 256, 256, fill=(0, 0, 256, 256)))
i3, o3, r3 = A.collect(fx3.rows, packs, fx3.load, {})
g = [i for i in i3 if i.obj.key == 'pk__big_portal']
check([i.key for i in g] == ['pk__big_portal_r0c0', 'pk__big_portal_r0c1', 'pk__big_portal_r1c0', 'pk__big_portal_r1c1'],
      'split: 6x6 -> four pieces, row-major keys')
check([(i.piece.tw, i.piece.th) for i in g] == [(2, 2), (4, 2), (2, 4), (4, 4)], 'split: remainder in the north-west')
check(all(len(i.frames) == 16 for i in g), 'split: 16 phases in every piece')
check(len({A.extra_text(i).split('|')[1] for i in g}) == 1, 'split: one ms for the whole group')
v = [i for i in i3 if i.obj.key == 'pk__volcano']
check([i.key for i in v] == ['pk__volcano_r0c1', 'pk__volcano_r1c1'], 'split: a piece empty in every phase is dropped')
check(r3['dropped'] == ['pk__volcano_r0c0', 'pk__volcano_r1c0'], 'split: the dropped piece is reported')
check(all(len(i.frames) == 9 and (i.piece.tw, i.piece.th) == (4, 4) for i in v), 'split: 256 px -> 4x4 pieces of 9 phases')
check('group=pk__volcano|gw=8|gh=8|piece=1,1' in A.extra_text(v[-1]), 'split: group extra')
# pieces cover the picture exactly: reassemble phase 0 of the portal
full = strip(16, 192, 192, fill=(0, 0, 192, 192))[:, :192]
canvas = np.zeros((192, 192, 4), np.uint8)
for i in g:
    canvas[i.piece.ty * 32:(i.piece.ty + i.piece.th) * 32, i.piece.tx * 32:(i.piece.tx + i.piece.tw) * 32] = i.frames[0]
check(np.array_equal(canvas, P.pad_to_tile(full)), 'split: the pieces reassemble to the picture')
# a frame partly empty keeps its phase count (an empty phase is not a dropped phase)
fx3b = Fix()
fx3b.add('pk', 'flicker_strip5.png', strip(5, 64, 64, empty=(1, 3)))
ib = A.collect(fx3b.rows, packs, fx3b.load, {})[0]
check(len(ib) == 1 and len(ib[0].frames) == 5, 'phases: empty phases stay')
emp = Fix()
emp.add('pk', 'e_strip3.png', strip(3, 32, 32, empty=(0, 1, 2)))
raises(lambda: A.collect(emp.rows, packs, emp.load, {}), 'empty picture stops the build', 'visible pixel')

# ------------------------------------------------------------------------------------------------ light table, kinds, ms
L = {i.key: i for i in items}
check('light:3:207' in L['pk__camp_fire'].flags, 'light: fire 3 / 207')
check('light:2:208' in L['pk__small_torch'].flags, 'light: torch 2, default colour')
check('light:3:164' in L['pk__void_portal'].flags, 'light: void portal 3 / 164 (colour by element word)')
check('light' not in L['pk__giant_squid_idle'].flags, 'light: squid has none')
check(A.COLOUR_WORDS['ice'] == 143 and A.COLOUR_WORDS['holy'] == 215 and A.COLOUR_WORDS['nature'] == 130
      and A.COLOUR_WORDS['lightning'] == 191 and A.COLOUR_WORDS['void'] == 164 and A.COLOUR_WORDS['fire'] == 207
      and A.DEFAULT_LIGHT_COLOUR == 208, 'light: colour table of the plan')
fl = Fix()
for nm in ('ice_portal', 'holy_portal', 'nature_portal', 'lighting_portal', 'dark_portal', 'lava_portal'):
    fl.add('pk', 'spr_%s_strip7.png' % nm, strip(7, 64, 64))
li = {i.obj.stem: i for i in A.collect(fl.rows, packs, fl.load, {})[0]}
check('light:3:143' in li['ice_portal'].flags and 'light:3:215' in li['holy_portal'].flags and 'light:3:130' in li['nature_portal'].flags
      and 'light:3:191' in li['lighting_portal'].flags and 'light:3:164' in li['dark_portal'].flags
      and 'light:3:207' in li['lava_portal'].flags, 'light: portal colours by element word')
lights = [i for i in i3 if 'light' in i.flags]
check([i.key for i in lights if i.obj.key == 'pk__big_portal'] == ['pk__big_portal_r1c1'], 'light: a split group lights its last piece only')
check('light:4:208' in lights[0].flags, 'light: a big portal (4 tiles or more) one level up')
check(all('light:5:207' in i.flags for i in i3 if i.obj.stem.startswith('volcano') and i.key.endswith('r1c1')), 'light: volcano 5 / fire')
check(L['pk__camp_fire'].obj.ms == 100 and L['pk__void_portal'].obj.ms == 120 and L['pk__giant_squid_idle'].obj.ms == 140,
      'ms: fires 100, portals 120, others 140')
check(A.ms_of('torch') == 100 and A.ms_of('magic_tree_1') == 140, 'ms: table')
check(L['pk__camp_fire'].kind == 'decor' and L['pk__giant_squid_idle'].kind == 'stump' and
      'bottom notwalkable notmoveable' in L['pk__giant_squid_idle'].flags, 'kind: fire decor, squid stump')
wl = Fix()
for nm in ('mine_wall_light', 'sewer_vent', 'sewer_fan', 'magic_tree_3', 'mushroom_1', 'sewer_barrel', 'long_grass_1', 'trap_plant_2'):
    wl.add('pk', 'x/%s_strip4.png' % nm, strip(4, 32, 32))
kw = {i.obj.stem: i.kind for i in A.collect(wl.rows, packs, wl.load, {})[0]}
check(kw == {'mine_wall_light': 'wall', 'sewer_vent': 'wall', 'sewer_fan': 'wall', 'magic_tree_3': 'stump', 'mushroom_1': 'stump',
             'sewer_barrel': 'stump', 'long_grass_1': 'decor', 'trap_plant_2': 'decor'}, 'kind: rules %s' % kw)
check(all('animateAlways' in i.flags for i in i3 + items), 'flags: animateAlways everywhere')
sev = [i for i in i3 if i.obj.key == 'pk__volcano_2']
check([i.kind for i in sev] == ['decor', 'decor', 'decor', 'stump'], 'kind: only the south-east piece of a stump group blocks')

# ------------------------------------------------------------------------------------------------ overrides
ov = {'pk__camp_fire': {'rename': 'Hearth', 'light': (4, 150), 'blocking': 1},
      'pk__small_torch': {'light': (0, 0)}, 'pk__void_portal': {'skip': 1}, 'pk__giant_squid_idle': {'kind': 'decor'},
      'pk__volcano_2_r0c0': {'skip': 1}}
io_, oo, ro = A.collect(fx.rows + fx3.rows, packs, lambda r: {**fx.arr, **fx3.arr}[(r.slug, r.path)], ov)
ik = {i.key: i for i in io_}
check('pk__void_portal' not in ik, 'override: skip')
check(ik['pk__camp_fire'].name == 'Hearth' and 'light:4:150' in ik['pk__camp_fire'].flags and ik['pk__camp_fire'].kind == 'stump',
      'override: rename, light, blocking')
check('light' not in ik['pk__small_torch'].flags, 'override: light level 0 = none')
check(ik['pk__giant_squid_idle'].kind == 'decor' and ik['pk__giant_squid_idle'].flags == 'notmoveable animateAlways', 'override: kind')
check('pk__volcano_2_r0c0' not in ik and 'pk__volcano_2_r0c1' in ik, 'override: skip of one piece')
raises(lambda: A.collect(fx.rows, packs, fx.load, {'pk__camp_fire': {'kind': 'tree'}}), 'override: unknown kind', 'kind override')
c = A.collect(fx.rows, packs, fx.load, {'pk__camp_fire': {'flags': 'notmoveable light:1:1'}})[0]
check([i.flags for i in c if i.key == 'pk__camp_fire'] == ['notmoveable light:1:1 animateAlways'], 'override: flags verbatim + animateAlways')

# ------------------------------------------------------------------------------------------------ overflow
many = Fix()
for n in range(A.BLOCK + 1):
    many.add('pk', 'o%03d_strip2.png' % n, strip(2, 32, 32))
raises(lambda: A.collect(many.rows, packs, many.load, {}), 'block overflow is a clear error', 'block holds 300')
ok300 = Fix()
for n in range(A.BLOCK):
    ok300.add('pk', 'o%03d_strip2.png' % n, strip(2, 32, 32))
check(len(A.collect(ok300.rows, packs, ok300.load, {})[0]) == A.BLOCK, 'overflow: exactly the block is fine')
check(A.FIRST_ID == 36459 and A.LAST_ID == 36758, 'block ids 36459..36758')

# ------------------------------------------------------------------------------------------------ tables
def tabs(fxx, ovv=None, pk=None):
    ii, oo_, _r = A.collect(fxx.rows, pk or packs, fxx.load, ovv or {})
    sheets = A.layout(ii)
    t = A.tables(ii)
    return t[A.SPEC], t[A.SOURCES_CSV], P.sums_text(sorted(sheets.items())), ii, sheets


spec, srcs, sums, ii, sheets = tabs(fx3)
good = A.check_tables(spec, srcs, sums, packs, fx3.rows, {})
check(good == [], 'check_tables: synthetic tables are clean: %s' % good[:3])
check(tabs(fx3)[:3] == (spec, srcs, sums), 'deterministic: same input, same tables')


def mut(a_, b_, text=spec, n=1):
    assert a_ in text, a_
    return text.replace(a_, b_, n)


def bad_with(spec_text=spec, srcs_text=srcs, sums_text=sums, rows=fx3.rows, ovv=None):
    return A.check_tables(spec_text, srcs_text, sums_text, packs, rows, ovv or {})


check(any('ms' in b and 'step' in b for b in bad_with(mut('ms=120', 'ms=100', n=1))), 'check_tables: pieces out of step')
check(any('phases' in b for b in bad_with(mut(',16,', ',9,', n=1))), 'check_tables: phase count')
check(any('size' in b for b in bad_with(mut(',2,2,1,16,', ',3,3,1,16,'))), 'check_tables: piece size')
check(any('duplicate' in b for b in bad_with(spec + spec.splitlines()[1] + '\n')), 'check_tables: duplicate key')
check(any('atlas row' in b for b in bad_with(mut(',0,64,', ',0,96,'))) or any('atlas row' in b for b in bad_with(mut(',0,128,', ',0,96,'))),
      'check_tables: atlas row')
check(any('flags' in b for b in bad_with(mut(' animateAlways', '', n=1))), 'check_tables: animateAlways missing')
check(any('light on more' in b for b in bad_with(mut('notmoveable animateAlways', 'notmoveable light:3:208 animateAlways', n=1))),
      'check_tables: light only on the last piece')
check(any('group extra' in b for b in bad_with(mut('gw=6', 'gw=5'))), 'check_tables: group extra')
check(any('plan order' in b for b in bad_with('\n'.join([spec.splitlines()[0], spec.splitlines()[2], spec.splitlines()[1]] + spec.splitlines()[3:]) + '\n')),
      'check_tables: plan order')
check(any('no item for' in b for b in bad_with('\n'.join(spec.splitlines()[:1] + [l for l in spec.splitlines()[1:] if 'big_portal' not in l]) + '\n')),
      'check_tables: object without an item')
check(any('not an object' in b for b in bad_with(mut('pk__big_portal_r0c0', 'pk__other_r0c0'))), 'check_tables: unknown key')
check(any('files' in b for b in bad_with(srcs_text=mut('pk/big_portal_strip16.png', 'pk/nope_strip16.png', srcs))), 'check_tables: source must be listed')
check(any('label' in b for b in bad_with(srcs_text=mut('set30 mutter', 'set30 pocket', srcs))), 'check_tables: label of the pack')
check(any('sums' in b for b in bad_with(sums_text=sums + 'ab  pack30_anim/zz.png\n')), 'check_tables: sums list')
check(any('kind' in b and 'disagree' in b for b in bad_with(mut(',stump,', ',decor,'))), 'check_tables: kind and flags')
big = spec + ''.join(spec.splitlines()[1] + '\n' for _ in range(300))
check(any('block holds' in b for b in bad_with(big)), 'check_tables: more rows than the block')
# atlas on disk is compared with the sums
import tempfile  # noqa: E402
from PIL import Image  # noqa: E402
d = tempfile.mkdtemp(prefix='a30test_')
os.makedirs(os.path.join(d, 'pack30_anim'))
for rel, arr in sheets.items():
    Image.fromarray(arr, 'RGBA').save(os.path.join(d, rel))
check(A.check_tables(spec, srcs, sums, packs, fx3.rows, {}, atlas_dir=d) == [], 'check_tables: atlas on disk matches')
bad_arr = sheets['pack30_anim/pk.png'].copy()
bad_arr[0, 0] = (1, 2, 3, 255)
Image.fromarray(bad_arr, 'RGBA').save(os.path.join(d, 'pack30_anim/pk.png'))
check(any('differs' in b for b in A.check_tables(spec, srcs, sums, packs, fx3.rows, {}, atlas_dir=d)), 'check_tables: changed atlas found')

# ------------------------------------------------------------------------------------------------ the committed tables
if os.path.exists(A.SPEC):
    committed = A.check_tables(open(A.SPEC, newline='').read(), open(A.SOURCES_CSV, newline='').read(),
                               open(A.SUMS, newline='').read(), P.load_packs(), P.read_files(P.files_path('anim')),
                               P.load_overrides(), atlas_dir=P.ART)
    check(committed == [], 'committed tables: %s' % committed[:3])
    n = len(A.parse_csv(open(A.SPEC, newline='').read())) - 1
    check(0 < n <= A.BLOCK, 'committed tables: %d items in a block of %d' % (n, A.BLOCK))

print('gen_pack30_anim_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
