#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_pack30_decor_test.py : gen_pack30_decor.py on synthetic generated images only (no
pack image is read), plus the committed tables (specs, sources, sums) against each other. Needs numpy and Pillow (fx venv)."""
import os
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack30_decor as D  # noqa: E402
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


def solid(w, h, rgb=(200, 100, 50), alpha=255):
    a = np.zeros((h, w, 4), np.uint8)
    a[:] = rgb + (alpha,)
    return a


def noise(w, h, seed):
    r = np.random.RandomState(seed)
    a = r.randint(0, 256, (h, w, 4)).astype(np.uint8)
    a[..., 3] = 255
    return a


def pack(slug, label='set30 mutter', cat='decor', also='', fit='high'):
    return P.Pack(slug, label, 'v1', 'ready', cat, also, 'x', fit, '', '', '1', '1', '')


class Fixture:
    """a temp drivepacks folder with synthetic files and the matching FileRow list"""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix='d30test_')
        self.rows = []

    def add(self, slug, path, arr):
        full = os.path.join(self.dir, slug, *path.split('/'))
        os.makedirs(os.path.dirname(full), exist_ok=True)
        Image.fromarray(arr, 'RGBA').save(full)
        self.rows.append(P.FileRow(slug, path, str(os.path.getsize(full)), P.file_md5(full), str(arr.shape[1]), str(arr.shape[0])))

    def run(self, packs, ov=None):
        return D.collect(self.dir, self.rows, packs, {}, ov or {})


def by_key(objs):
    return {o.key: o for o in objs}


# ------------------------------------------------------------------------------------------------ pad, trim, scale2x
def test_objects():
    fx = Fixture()
    fx.add('tp', 'Props/statue_a.png', noise(48, 48, 1))                  # 48 px: padded to 64, bottom-right aligned
    fx.add('tp', 'vase.png', noise(62, 62, 2))                            # 62 px: 64
    fx.add('tp', 'dock_wood.png', noise(34, 34, 3))                       # 34 px: 64
    low = np.zeros((64, 64, 4), np.uint8)
    low[32:, 32:] = noise(32, 32, 4)                                      # art only in the south-east tile: trimmed to 1x1
    fx.add('tp', 'small_barrel.png', low)
    rock = noise(16, 16, 5)
    fx.add('tp', 'pebble.png', rock)                                      # 16 px: Scale2x
    fx.add('tp', 'empty.png', np.zeros((32, 32, 4), np.uint8))            # no art: dropped
    soft = solid(32, 32, alpha=8)                                         # alpha under 12 is cleared, so empty too
    fx.add('tp', 'faint.png', soft)
    objs, rep = fx.run([pack('tp')])
    o = by_key(objs)
    st = o['tp__statue_a']
    check((st.tw, st.th) == (2, 2) and st.canvas.shape == (64, 64, 4), 'statue 48 px pads to 2x2')
    check(np.array_equal(st.canvas[16:, 16:], noise(48, 48, 1)) and not st.canvas[:16].any() and not st.canvas[:, :16].any(),
          'statue is bottom-right aligned, nothing scaled')
    check((o['tp__vase'].tw, o['tp__vase'].th) == (2, 2), 'vase 62 px is 2x2')
    check(np.array_equal(o['tp__vase'].canvas[2:, 2:], noise(62, 62, 2)), 'vase bottom-right aligned')
    check((o['tp__dock_wood'].tw, o['tp__dock_wood'].th) == (2, 2), '34 px is 2x2')
    b = o['tp__small_barrel']
    check((b.tw, b.th) == (1, 1) and np.array_equal(b.canvas, noise(32, 32, 4)), 'whole empty tile rows and columns are trimmed')
    p = o['tp__pebble']
    check(p.scaled and p.canvas.shape == (32, 32, 4) and np.array_equal(p.canvas, P.scale2x(rock)), '16 px art is Scale2x')
    check('tp__empty' not in o and 'tp__faint' not in o and len(rep['empty']) == 2, 'empty art dropped and listed')
    one, two, three = D.make_items(objs, {})
    ex = {it.key: it.extra for it in one + two}
    check('scale2x=1' in ex['tp__pebble'] and 'scale2x' not in ex['tp__vase'], 'scale2x recorded in the extra')
    check(all(it.canvas.shape[0] == it.h * 32 and it.canvas.shape[1] == it.w * 32 for it in one + two), 'canvas sizes')
    # override: scale2x 0 keeps 16 px art unscaled (padded to 32)
    objs2, _ = fx.run([pack('tp')], {'tp__pebble': {'scale2x': 0}})
    q = by_key(objs2)['tp__pebble']
    check(not q.scaled and np.array_equal(q.canvas[16:, 16:], rock), 'scale2x=0 override pads instead')


# ------------------------------------------------------------------------------------------------ sheets
def test_sheets():
    fx = Fixture()
    g = np.zeros((128, 128, 4), np.uint8)
    for (r, c) in ((0, 0), (0, 1), (2, 3)):
        g[r * 32:(r + 1) * 32, c * 32:(c + 1) * 32] = noise(32, 32, 10 + r * 4 + c)
    fx.add('tw', 'Wall_Portraits_Sheet.png', g)
    s = np.zeros((256, 256, 4), np.uint8)
    s[5:25, 5:25] = noise(20, 20, 20)                  # a blob inside the first cell
    s[70:90, 28:44] = noise(16, 20, 21)                # crosses the cell edge at x=32: stays whole
    s[200:202, 200:202] = noise(2, 2, 22)              # a speck of 4 px: dropped
    fx.add('tp', 'Sheet_3_Props.png', s)
    D.SHEETS[('tw', 'Wall_Portraits_Sheet.png')] = ('grid', None)
    D.SHEETS[('tp', 'Sheet_3_Props.png')] = ('segment', None)
    D.PACK_KIND['tw'] = 'wall'
    try:
        objs, rep = fx.run([pack('tw'), pack('tp')])
        o = by_key(objs)
        check(sorted(o) == ['tp__props__r0c0', 'tp__props__r2c0', 'tw__wall_portraits_sheet__r0c0',
                            'tw__wall_portraits_sheet__r0c1', 'tw__wall_portraits_sheet__r2c3'], 'sheet keys: %s' % sorted(o))
        check((o['tp__props__r2c0'].tw, o['tp__props__r2c0'].th) == (2, 1), 'a component across a cell edge stays whole (2x1)')
        check(o['tp__props__r2c0'].box == (0, 64, 64, 96), 'its box is grown to the grid: %s' % (o['tp__props__r2c0'].box,))
        check(np.array_equal(o['tp__props__r0c0'].canvas[5:25, 5:25], noise(20, 20, 20)), 'segment pixels')
        check(all(o[k].kind == 'wall' for k in o if k.startswith('tw__')), 'a wall decoration pack is all wall')
        one, two, three = D.make_items(objs, {})
        fl = {it.key: it.flags for it in one + two}
        check(fl['tw__wall_portraits_sheet__r0c0'] == 'hangable notmoveable', 'wall flags: %r' % fl['tw__wall_portraits_sheet__r0c0'])
        check(len(rep['empty']) == 13, 'grid: the 13 empty cells are dropped and listed: %d' % len(rep['empty']))
        src = {it.key: D.source_of(it) for it in one + two}
        check(src['tp__props__r2c0'] == 'tp/Sheet_3_Props.png[0,64,64,96]', 'source with the cell box: %s' % src['tp__props__r2c0'])
        # a sheet that is not a whole number of cells stops
        fx2 = Fixture()
        fx2.add('tw', 'Wall_Portraits_Sheet.png', np.zeros((100, 100, 4), np.uint8))
        raises(lambda: fx2.run([pack('tw')]), 'sheet size', 'whole number of 32 px cells')
    finally:
        del D.SHEETS[('tw', 'Wall_Portraits_Sheet.png')], D.SHEETS[('tp', 'Sheet_3_Props.png')], D.PACK_KIND['tw']


# ------------------------------------------------------------------------------------------------ selection and kinds
def test_selection_and_kinds():
    fx = Fixture()
    for i, name in enumerate(('red_banner', 'oak_tree', 'big_rug', 'banner_stand', 'bed_roll', 'royal_bed', 'old_chest',
                              'wall_pillow', 'hanging_chains', 'gold_pile', 'camp_storage', 'window_light', 'spr_shawdow',
                              'dark_cottage', 'tiny_house_sign')):
        fx.add('tp', name + '.png', noise(32, 32, 30 + i))
    fx.add('tp', 'camp_fire_strip9.png', noise(288, 32, 50))                # animated: left to another task
    fx.add('tp', 'Greenhouse.png', noise(128, 128, 51))                      # building word at 128 px
    fx.add('tp', 'huge.png', noise(256, 256, 52))                            # over 192 px
    fx.add('tp', 'floors/stone_floor_tile_1.png', noise(32, 32, 53))         # a floor: grounds claims it
    packs = [pack('tp', also='grounds')]
    objs, rep = fx.run(packs)
    o = by_key(objs)
    kind = {k.split('__', 1)[1]: v.kind for k, v in o.items()}
    check(kind['red_banner'] == 'wall' and kind['wall_pillow'] == 'wall' and kind['hanging_chains'] == 'wall', 'wall words')
    check(kind['oak_tree'] == 'stump' and kind['royal_bed'] == 'stump' and kind['old_chest'] == 'stump', 'blocking words')
    check(kind['big_rug'] == 'decor' and kind['bed_roll'] == 'decor' and kind['gold_pile'] == 'decor', 'decor by default')
    check(kind['banner_stand'] == 'stump', 'a banner stand is not wall mounted')
    check(kind['camp_storage'] == 'decor', 'storage is not a store (building word)')
    check('tp__window_light' not in o and 'tp__shawdow' not in o, 'light overlays and shadows left out')
    check('tp__dark_cottage' in o, 'a 32 px cottage word is a small prop, not a building')
    why = {r[1]: r[2] for r in rep['skipped']}
    check(why.get('camp_fire_strip9.png') == 'animated strip', 'strips left to the animation task')
    check(why.get('Greenhouse.png') == 'building' and why.get('huge.png', '').startswith('over 192 px'), 'buildings left out')
    check(why.get('floors/stone_floor_tile_1.png') == 'floor (grounds)', 'a floor claimed by the grounds plan is not decoration')
    # a pack whose category is bldg: 96 px and more is a building
    fx3 = Fixture()
    fx3.add('tb', 'barrel_stack.png', noise(96, 96, 60))
    fx3.add('tb', 'crate.png', noise(64, 64, 61))
    objs3, rep3 = fx3.run([pack('tb', cat='bldg', also='decor')])
    check(sorted(by_key(objs3)) == ['tb__crate'] and rep3['skipped'][0][2] == 'building', 'building pack: 96 px is left out')
    # family cap: numbered variants
    fx4 = Fixture()
    for n in range(1, 13):
        fx4.add('tp', 'Trees/spr_tree_%d.png' % n, noise(32, 32, 100 + n))
    objs4, rep4 = fx4.run([pack('tp')])
    got = sorted(int(k.rsplit('_', 1)[1]) for k in by_key(objs4) if not by_key(objs4)[k].late)
    check(got == list(range(1, 9)), 'first 8 variants in natural order: %s' % got)
    late = sorted(int(o.key.rsplit('_', 1)[1]) for o in objs4 if o.late)
    check(late == [9, 10, 11, 12] and objs4[-1].late and not objs4[0].late, 'the rest goes to decor-3, after the others: %s' % late)
    a, b, c = D.make_items(objs4, {})
    check((len(a), len(b), len(c)) == (8, 0, 4), 'blocks of the family: %s' % [len(a), len(b), len(c)])
    # an exact duplicate of a late object keeps the decor-1/2 object
    fx4.add('tp', 'Trees/spr_tree_20.png', noise(32, 32, 101))
    o4b, r4b = fx4.run([pack('tp')])
    check(('tp__tree_20', 'tp__tree_1') in r4b['dups'], 'a late duplicate is the one dropped: %s' % r4b['dups'])
    # low-fit packs come last in plan order
    fx5 = Fixture()
    fx5.add('aa', 'one.png', noise(32, 32, 120))
    fx5.add('zz', 'two.png', noise(32, 32, 121))
    objs5, _ = fx5.run([pack('aa', fit='low'), pack('zz', fit='high')])
    check([o.key for o in objs5] == ['zz__two', 'aa__one'], 'low-fit last: %s' % [o.key for o in objs5])
    check([o.hide for o in objs5] == [1, 0], 'hideout 1 for a small decor of a good pack, 0 for a low-fit pack')


# ------------------------------------------------------------------------------------------------ overrides
def test_overrides():
    fx = Fixture()
    fx.add('tp', 'a_chest.png', noise(64, 64, 200))
    fx.add('tp', 'b_vase.png', noise(32, 32, 201))
    fx.add('tp', 'c_lamp.png', noise(32, 32, 202))
    fx.add('tp', 'd_table.png', noise(32, 32, 203))
    fx.add('tp', 'e_post.png', noise(32, 32, 204))
    ov = {'tp__b_vase': {'skip': 1}, 'tp__a_chest': {'rename': 'Locked Chest', 'hideout': 0},
          'tp__c_lamp': {'blocking': 1, 'light': (2, 207)}, 'tp__d_table': {'blocking': 0},
          'tp__e_post': {'kind': 'wall', 'tiles': (1, 2)}}
    objs, rep = fx.run([pack('tp')], ov)
    o = by_key(objs)
    check('tp__b_vase' not in o and rep['ovskip'] == ['tp__b_vase'], 'skip')
    check(o['tp__a_chest'].name == 'Locked Chest' and o['tp__a_chest'].hide == 0, 'rename and hideout')
    check(o['tp__c_lamp'].kind == 'stump' and o['tp__d_table'].kind == 'decor', 'blocking 1 / 0')
    check((o['tp__e_post'].tw, o['tp__e_post'].th) == (1, 2) and o['tp__e_post'].kind == 'wall', 'kind and tiles')
    check(np.array_equal(o['tp__e_post'].canvas[32:], noise(32, 32, 204)) and not o['tp__e_post'].canvas[:32].any(),
          'tiles: art bottom-right aligned in the forced canvas')
    one, two, three = D.make_items(objs, ov)
    fl = {it.key: it.flags for it in one + two}
    check(fl['tp__c_lamp'] == 'bottom notwalkable notmoveable light:2:207', 'light override: %r' % fl['tp__c_lamp'])
    ov2 = {'tp__a_chest': {'flags': 'notmoveable clip'}}
    objs2, _ = fx.run([pack('tp')], ov2)
    check({it.key: it.flags for it in sum(D.make_items(objs2, ov2), [])}['tp__a_chest'] == 'notmoveable clip', 'flags override')
    raises(lambda: fx.run([pack('tp')], {'tp__a_chest': {'tiles': (1, 1)}}), 'art that needs cropping stops', 'does not fit')
    raises(lambda: fx.run([pack('tp')], {'tp__a_chest': {'kind': 'tree'}}), 'bad kind', 'not one of')


# ------------------------------------------------------------------------------------------------ blocks, pieces, layout
def test_blocks_and_pieces():
    fx = Fixture()
    fx.add('tp', 'a_pebble.png', noise(32, 32, 300))
    fx.add('tp', 'b_post.png', noise(32, 64, 301))
    fx.add('tp', 'c_beam.png', noise(64, 32, 302))
    fx.add('tp', 'd_rock.png', noise(64, 64, 303))
    fx.add('tp', 'e_tree.png', noise(160, 160, 304))                  # 5x5 tiles: four pieces
    fx.add('tp', 'f_dup.png', noise(32, 32, 300))                      # same pixels as a_pebble
    objs, rep = fx.run([pack('tp')])
    check(rep['dups'] == [('tp__f_dup', 'tp__a_pebble')], 'exact duplicates kept once: %s' % rep['dups'])
    one, two, three = D.make_items(objs, {})
    check([i.key for i in one] == ['tp__a_pebble', 'tp__b_post', 'tp__c_beam'], 'block 1 holds the 1x1, 1x2 and 2x1: %s' % [i.key for i in one])
    check([i.key for i in two][:1] == ['tp__d_rock'], 'block 2 starts with the 2x2')
    pcs = [i for i in two if i.piece is not None]
    check([i.key for i in pcs] == ['tp__e_tree_r0c0', 'tp__e_tree_r0c1', 'tp__e_tree_r1c0', 'tp__e_tree_r1c1'], 'piece keys')
    check([(i.w, i.h) for i in pcs] == [(1, 1), (4, 1), (1, 4), (4, 4)], 'plan_split(5, 5) sizes: %s' % [(i.w, i.h) for i in pcs])
    check(pcs[3].extra.endswith('group=tp__e_tree|gw=5|gh=5|piece=1,1') and 'family=tp' in pcs[3].extra, 'group extra: %s' % pcs[3].extra)
    tree = by_key(objs)['tp__e_tree']
    check(tree.kind == 'stump' and [i.kind for i in pcs] == ['decor', 'decor', 'decor', 'stump'],
          'only the south-east piece of a blocking group blocks: %s' % [i.kind for i in pcs])
    check(pcs[0].flags == 'notmoveable' and pcs[3].flags == 'bottom notwalkable notmoveable', 'piece flags')
    whole = np.zeros((160, 160, 4), np.uint8)
    for pc, it in zip(P.plan_split(5, 5), pcs):
        whole[pc.ty * 32:(pc.ty + pc.th) * 32, pc.tx * 32:(pc.tx + pc.tw) * 32] = it.canvas
    check(np.array_equal(whole, tree.canvas), 'the pieces put together are the picture')
    check(all(i.w <= 4 and i.h <= 4 for i in one + two), 'no item over 4x4')
    # art over 6 tiles is left out and listed
    fx2 = Fixture()
    fx2.add('tp', 'sheetish.png', noise(200, 200, 310))
    s2 = np.zeros((256, 256, 4), np.uint8)
    s2[0:224, 0:100] = noise(100, 224, 311)
    fx2.add('tp', 'Sheet_9.png', s2)
    D.SHEETS[('tp', 'Sheet_9.png')] = ('segment', None)
    try:
        o2, r2 = fx2.run([pack('tp')])
        check(o2 == [] and len(r2['big']) == 1 and r2['skipped'][0][2].startswith('over 192 px'), 'over 6 tiles is skipped')
    finally:
        del D.SHEETS[('tp', 'Sheet_9.png')]
    # a block that is too small stops the build with a clear error
    old = D.BLOCK_1
    D.BLOCK_1 = 2
    try:
        raises(lambda: D.make_items(objs, {}), 'decor-1 overflow', 'block overflow: decor-1 needs 3 ids, the block holds 2')
    finally:
        D.BLOCK_1 = old
    old = D.BLOCK_2
    D.BLOCK_2 = 3
    try:
        raises(lambda: D.make_items(objs, {}), 'decor-2 overflow', 'block overflow: decor-2 needs 5 ids, the block holds 3')
    finally:
        D.BLOCK_2 = old
    # caps keep the objects with the most opaque pixels, in plan order
    fx3 = Fixture()
    fx3.add('tp', 'a_one.png', noise(32, 32, 320))
    half = noise(32, 32, 321)
    half[:, :16] = 0
    fx3.add('tp', 'b_two.png', half)
    fx3.add('tp', 'c_three.png', noise(32, 32, 322))
    D.PACK_CAPS['tp'] = (2, None)
    try:
        o3, r3 = fx3.run([pack('tp')])
    finally:
        del D.PACK_CAPS['tp']
    check([o.key for o in o3 if not o.late] == ['tp__a_one', 'tp__c_three'] and r3['capped'] == ['tp__b_two'] and
          o3[-1].key == 'tp__b_two' and o3[-1].late, 'pack cap moves the rest to decor-3: %s' % [o.key for o in o3])
    x, y, z = D.make_items(o3, {})
    check([i.key for i in x] == ['tp__a_one', 'tp__c_three'] and [i.key for i in z] == ['tp__b_two'], 'cap: blocks')
    # a late big group: all pieces in decor-3
    fx5 = Fixture()
    fx5.add('tp', 'a_rock.png', noise(128, 128, 330))
    tree = np.zeros((160, 160, 4), np.uint8)             # sparse corners: the fewest opaque pixels, still 5x5 tiles
    tree[0, 0] = tree[0, 159] = tree[159, 0] = tree[159, 159] = (9, 9, 9, 255)
    fx5.add('tp', 'b_tree.png', tree)
    D.PACK_CAPS['tp'] = (None, 1)
    try:
        o5, r5 = fx5.run([pack('tp')])
    finally:
        del D.PACK_CAPS['tp']
    x, y, z = D.make_items(o5, {})
    check([i.key for i in y] == ['tp__a_rock'] and len(z) == 4 and all(i.piece is not None for i in z), 'late group pieces: %s' % [i.key for i in z])
    old = D.BLOCK_3
    D.BLOCK_3 = 3
    try:
        raises(lambda: D.make_items(o5, {}), 'decor-3 overflow', 'block overflow: decor-3 needs 4 ids, the block holds 3')
    finally:
        D.BLOCK_3 = old
    # atlas layout: a new atlas when the next object would pass ATLAS_H
    old = D.ATLAS_H
    D.ATLAS_H = 96
    try:
        lay = D.layout([(1, 1), (1, 2), (1, 1), (4, 1)], 1)
    finally:
        D.ATLAS_H = old
    check(lay == [('pack30_decor/decor1_1', 0), ('pack30_decor/decor1_1', 32), ('pack30_decor/decor1_2', 0),
                  ('pack30_decor/decor1_2', 32)], 'layout: %s' % lay)


# ------------------------------------------------------------------------------------------------ tables
def synthetic_tables():
    """(call with D.SHEETS holding the tq sheet)"""
    fx = Fixture()
    packs = [pack('tp'), pack('tq', label='set30 pocket', fit='low')]
    fx.add('tp', 'a_pebble.png', noise(16, 16, 400))
    fx.add('tp', 'b_chest.png', noise(64, 64, 401))
    fx.add('tp', 'c_tree.png', noise(160, 160, 402))
    fx.add('tq', 'sub/d_post.png', noise(32, 64, 403))
    fx.add('tq', 'e_banner.png', noise(48, 48, 404))
    s = np.zeros((128, 128, 4), np.uint8)
    s[0:32, 0:32] = noise(32, 32, 405)
    s[64:96, 32:64] = noise(32, 32, 406)
    fx.add('tq', 'Sheet_1.png', s)
    for n in range(1, 11):                      # variants 9 and 10 go to decor-3
        fx.add('tp', 'g_%d.png' % n, noise(32, 32, 410 + n))
    objs, rep = fx.run(packs)
    one, two, three = D.make_items(objs, {})
    files = D.tables(one, two, three)
    sheets = dict(D.atlases(one, 1))
    sheets.update(D.atlases(two, 2))
    sheets.update(D.atlases(three, 3))
    sums = P.sums_text(sorted(sheets.items()))
    return fx, packs, one, two, three, files, sheets, sums


def test_tables():
    D.SHEETS[('tq', 'Sheet_1.png')] = ('grid', None)
    try:
        fx, packs, one, two, three, files, sheets, sums = synthetic_tables()
        args = (files[D.SPEC_1], files[D.SPEC_2], files[D.SPEC_3], files[D.SOURCES_CSV], sums, packs, fx.rows)
        check(D.check_tables(*args) == [], 'check_tables on a good build: %s' % D.check_tables(*args))
        # atlas pixels: every item sits where the spec says
        rows = {r[0]: r for t in (files[D.SPEC_1], files[D.SPEC_2], files[D.SPEC_3]) for r in D.parse_csv(t)[1:]}
        for it in one + two + three:
            r = rows[it.key]
            a = sheets[r[4] + '.png']
            y = int(r[6])
            check(np.array_equal(a[y:y + it.h * 32, :it.w * 32], it.canvas), 'atlas pixels of %s' % it.key)
        # deterministic: a second build is byte-identical
        _, _, one2, two2, three2, files2, sheets2, sums2 = synthetic_tables()
        check(files2 == files and sums2 == sums, 'same inputs give the same tables')
        # tampering is found
        bad = D.check_tables(files[D.SPEC_1].replace('tp__a_pebble', 'tp__Pebble'), *args[1:])
        check(bad, 'a bad key is found')
        bad = D.check_tables(files[D.SPEC_2], files[D.SPEC_1], *args[2:])
        check(any('wrong block' in b for b in bad), 'swapped blocks are found')
        bad = D.check_tables(args[0], files[D.SPEC_2].replace('piece=1,1', 'piece=1,0'), *args[2:])
        check(any('group' in b for b in bad), 'a wrong piece is found')
        check(D.check_tables(*args[:4], sums.splitlines()[0] + '\n', packs, fx.rows), 'a missing sum is found')
        bad = D.check_tables(*args[:3], files[D.SOURCES_CSV].replace('tq/e_banner.png', 'tq/nope.png'), *args[4:])
        check(any('not in pack30_decor.files' in b for b in bad), 'a source that is not listed is found')
        bad = D.check_tables(*args[:3], files[D.SOURCES_CSV].replace('set30 pocket', 'set30 mutter'), *args[4:])
        check(any('label' in b for b in bad), 'a wrong label is found')
        bad = D.check_tables(args[0].replace('notmoveable', 'walk', 1), *args[1:])
        check(any('flags' in b for b in bad), 'a wrong flag is found')
        # atlases on disk are compared with the sums
        d = tempfile.mkdtemp(prefix='d30atlas_')
        os.makedirs(os.path.join(d, 'pack30_decor'))
        for rel, a in sheets.items():
            Image.fromarray(a, 'RGBA').save(os.path.join(d, rel))
        check(D.check_tables(*args, atlas_dir=d) == [], 'atlases on disk match the sums')
        first = sorted(sheets)[0]
        a = sheets[first].copy()
        a[0, 0] ^= 255
        Image.fromarray(a, 'RGBA').save(os.path.join(d, first))
        check(any('differs' in b for b in D.check_tables(*args, atlas_dir=d)), 'a changed atlas is found')
        # block overflow in the tables
        old = D.BLOCK_1
        D.BLOCK_1 = 1
        try:
            check(any('block overflow' in b for b in D.check_tables(*args)), 'too many rows for the block')
        finally:
            D.BLOCK_1 = old
        # sources: licence text and pieces
        src = D.parse_csv(files[D.SOURCES_CSV])
        check(src[0] == D.SOURCE_FIELDS and len(src) == 1 + len(one) + len(two) + len(three), 'sources: one row per item')
        check(any(' piece r1c1' in r[3] for r in src), 'sources: piece suffix')
        check(('w' + 'st') not in files[D.SPEC_1].lower() and ('w' + 'st') not in files[D.SOURCES_CSV].lower(), 'no vendor tag')
    finally:
        del D.SHEETS[('tq', 'Sheet_1.png')]


def test_committed():
    paths = (D.SPEC_1, D.SPEC_2, D.SPEC_3, D.SOURCES_CSV, D.SUMS)
    if not all(os.path.exists(p) for p in paths):
        check(False, 'committed tables missing')
        return
    texts = [open(p, newline='', encoding='utf-8').read() for p in paths]
    bad = D.check_tables(*texts, P.load_packs(), P.read_files(P.files_path(D.CAT)), P.load_overrides(), atlas_dir=D.ART)
    check(bad == [], 'committed tables: %s' % bad[:5])
    n1, n2, n3 = (len(D.parse_csv(t)) - 1 for t in texts[:3])
    check(0 < n1 <= D.BLOCK_1 and 0 < n2 <= D.BLOCK_2 and 0 < n3 <= D.BLOCK_3, 'committed counts fit the blocks (%d, %d, %d)' % (n1, n2, n3))
    check(D.FIRST_3 == 37713 and D.FIRST_3 > 37112 and D.LAST_3 + 3000 <= 65535, 'decor-3 starts at 37713, clear of the donor ids 37000..37112')
    check(D.FIRST_1 + D.BLOCK_1 == D.FIRST_2 and D.LAST_ID == 36058, 'block ids: decor-1 35159, decor-2 35559..36058')
    check(os.path.exists(os.path.join(D.OUT_DIR, '.gitignore')), 'the cut sheets folder is ignored by git')


for t in (test_objects, test_sheets, test_selection_and_kinds, test_overrides, test_blocks_and_pieces, test_tables, test_committed):
    t()
print('gen_pack30_decor tests:', 'OK' if not failed else '%d FAILED' % failed)
sys.exit(1 if failed else 0)
