#!/usr/bin/env python3
"""Tests of gen_pack30_bldg.py on synthetic pictures only (no pack file is read).

    /tmp/fxenv/bin/python -I gen_pack30_bldg_test.py
"""
import os
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack30_bldg as G  # noqa: E402
import pack30lib as P  # noqa: E402

OK = []


def check(cond, what):
    if not cond:
        print('FAIL', what)
        sys.exit(1)
    OK.append(what)


def raises(fn, what):
    try:
        fn()
    except P.PackError:
        OK.append(what)
        return
    print('FAIL', what, '(no PackError)')
    sys.exit(1)


def pic(w, h, box=None, val=7):
    """a w x h picture with an opaque box (x0, y0, x1, y1); the colour encodes val, a marker pixel sits at the box corner"""
    a = np.zeros((h, w, 4), np.uint8)
    x0, y0, x1, y1 = box or (0, 0, w, h)
    a[y0:y1, x0:x1] = (val, 60, 200, 255)
    a[y0, x0] = (val, 1, 1, 255)
    return a


def row(slug, path, w, h):
    return P.FileRow(slug, path, 1, 'x' * 32, w, h)


def pack(slug, category='bldg', fit='high', also=''):
    return P.Pack(slug, 'set30 mutter', 'v1', 'ready', category, also, 'x', fit, '', 'x', 1, 1, '')


# ------------------------------------------------------------------------------------------------ plan_split / pieces
def test_split():
    def shape(gw, gh):
        return [(p.row, p.col, p.tw, p.th) for p in P.plan_split(gw, gh)]
    check(shape(4, 4) == [(0, 0, 4, 4)], '128 px: one piece of 4x4')
    check(shape(6, 6) == [(0, 0, 2, 2), (0, 1, 4, 2), (1, 0, 2, 4), (1, 1, 4, 4)], '192 px: 2x2 pieces, remainder north-west')
    check(len(shape(8, 8)) == 4 and all(s[2:] == (4, 4) for s in shape(8, 8)), '256 px: four 4x4 pieces')
    check(len(shape(16, 16)) == 16 and all(s[2:] == (4, 4) for s in shape(16, 16)), '512 px: sixteen pieces of 4x4')
    pcs = P.plan_split(6, 6)
    check(P.piece_key('k', pcs[3]) == 'k_r1c1', 'piece key')
    check(P.group_extra('k', 6, 6, pcs[3]) == 'group=k|gw=6|gh=6|piece=1,1', 'group extra')
    # a 256 px picture with art only in the lower left: the empty pieces take no id
    a = np.zeros((256, 256, 4), np.uint8)
    a[200:256, 0:100] = (9, 9, 9, 255)
    g = G.Group(G.Src(pack('p'), row('p', 'X.png', 256, 256)), 'p__x', 'X', G.trim_tiles(a))
    check((g.gw, g.gh) == (4, 2) and [(pc.row, pc.col) for pc in g.pieces] == [(0, 0)], 'trimmed group, one piece: %s' % g.pieces)
    check(g.arr.shape == (64, 128, 4) and g.arr[:, :, 3].any(), 'trimmed to the art tiles')


# ------------------------------------------------------------------------------------------------ selection
def test_select():
    pk = [pack('big', fit='medium'), pack('hi'), pack('lo', fit='low'), pack('deco', category='decor', also='bldg'),
          pack('stalls', category='decor', also='bldg'), pack('village', fit='high')]
    G.RULES.update({'deco': {'inc': r'tent|cottage'}, 'village': {'min_px': 64, 'inc': r'house'}})
    try:
        rows = [row('big', 'Gothic_Abbey.png', 256, 256), row('big', 'Small_Prop.png', 64, 64),
                row('big', 'Mill_strip9.png', 2304, 256), row('big', 'floor/Stone.png', 128, 128),
                row('big', 'Snow Ground Tiles.png', 131, 131), row('big', 'Thin.png', 256, 64),
                row('big', 'notes.json', 0, 0), row('big', 'Wall_128.png', 128, 128),
                row('hi', 'Zeta.png', 128, 128), row('hi', 'Alpha.png', 128, 128),
                row('lo', 'Low.png', 128, 128),
                row('deco', 'Tent_1.png', 128, 128), row('deco', 'Barrel.png', 128, 128), row('deco', 'Tent_s.png', 64, 64),
                row('stalls', 'Stall_1.png', 128, 128),
                row('village', 'spr_house_2.png', 64, 64), row('village', 'spr_boat.png', 64, 64),
                row('village', 'spr_Little_House.png', 32, 32)]
        srcs = G.select(rows, pk)
        got = [s.source for s in srcs]
        check(got == ['deco/Tent_1.png', 'hi/Alpha.png', 'hi/Zeta.png', 'village/spr_house_2.png', 'big/Gothic_Abbey.png',
                      'big/Wall_128.png', 'lo/Low.png'], 'selection and priority order (fit, slug, path): %s' % got)
        check([s.key for s in srcs][:4] == ['deco__tent_1', 'hi__alpha', 'hi__zeta', 'village__spr_house_2'], 'group keys')
        check(G.select(rows, pk, {'hi__alpha': {'skip': 1}})[1].source == 'hi/Zeta.png', 'skip override drops a file')
        raises(lambda: G.select(rows + [row('hi', 'sub/Alpha.png', 128, 128)], pk), 'two files with one key stop')
        check(G.clean_name('spr_castle_tower') == 'Castle Tower' and G.clean_name('Dwarven_house_1') == 'Dwarven House 1',
              'names from the file stem')
    finally:
        del G.RULES['deco'], G.RULES['village']


# ------------------------------------------------------------------------------------------------ pictures
def test_pixels():
    # not a multiple of 32: padded top and left, bottom-right aligned, never scaled
    a = pic(92, 70)
    p = G.prepare(a)
    check(p.shape == (96, 96, 4) and np.array_equal(p[26:, 4:], a) and not p[:26].any() and not p[:, :4].any(),
          'odd size padded bottom-right aligned')
    # soft alpha is cleared
    s = pic(64, 64, (0, 0, 64, 64))
    s[3, 3, 3] = 5
    check(G.prepare(s)[3, 3, 3] == 0, 'alpha under 12 cleared')
    # the art keeps its place on the tile grid when empty outer tiles are trimmed
    big = pic(256, 256, (70, 100, 150, 230))
    t = G.trim_tiles(big)
    check(t.shape == (160, 96, 4), 'trim to whole tiles: %s' % (t.shape,))
    check(np.array_equal(t, big[96:256, 64:160]), 'trim keeps pixels in place')
    check(G.trim_tiles(np.zeros((64, 64, 4), np.uint8)) is None, 'empty picture')
    # scale2x for 16 px art
    sm = pic(16, 16)
    check(G.prepare(sm, True).shape == (32, 32, 4), 'scale2x override')


def fixture():
    pk = [pack('hi'), pack('mid', fit='medium'), pack('lo', fit='low')]
    files = {}
    rows = []

    def add(slug, path, a):
        files[(slug, path)] = a
        rows.append(row(slug, path, a.shape[1], a.shape[0]))

    add('hi', 'A_128.png', pic(128, 128, (4, 6, 120, 128), 1))               # 4x4, 1 piece
    add('hi', 'B_256.png', pic(256, 256, (10, 10, 250, 250), 2))             # 8x8, 4 pieces
    add('hi', 'C_192.png', pic(192, 192, (0, 0, 192, 192), 3))               # 6x6, 4 pieces
    add('mid', 'D_512.png', pic(512, 512, (0, 0, 512, 512), 4))              # 16x16, 16 pieces
    add('mid', 'E_lowpart.png', pic(256, 256, (0, 160, 90, 256), 5))         # 3x3 -> trimmed 3x3: one piece
    add('mid', 'F_dup.png', pic(128, 128, (4, 6, 120, 128), 1))              # exact copy of A_128 (other slug/key)
    add('lo', 'G_128.png', pic(128, 128, (0, 0, 128, 128), 6))
    add('lo', 'H_empty.png', np.zeros((128, 128, 4), np.uint8))
    return pk, rows, files


def load_of(files):
    return lambda r: files[(r.slug, r.path)]


# ------------------------------------------------------------------------------------------------ groups, blocking, tables
def test_render():
    pk, rows, files = fixture()
    srcs = G.select(rows, pk)
    kept, dropped = G.render(srcs, load_of(files), {})
    keys = [g.key for g in kept]
    check(keys == ['hi__a_128', 'hi__b_256', 'hi__c_192', 'lo__g_128', 'mid__d_512', 'mid__e_lowpart'] or
          keys == ['hi__a_128', 'hi__b_256', 'hi__c_192', 'mid__d_512', 'mid__e_lowpart', 'lo__g_128'],
          'groups follow the priority order: %s' % keys)
    check(keys == ['hi__a_128', 'hi__b_256', 'hi__c_192', 'mid__d_512', 'mid__e_lowpart', 'lo__g_128'], 'fit order: low last')
    reasons = {n: why for n, _s, why in dropped}
    check(reasons == {'mid__f_dup': 'duplicate of hi__a_128', 'lo__h_empty': 'empty'}, 'dropped: %s' % reasons)
    by = {g.key: g for g in kept}
    check([len(by[k].pieces) for k in keys] == [1, 4, 4, 16, 1, 1], 'pieces: 128=1, 256=4, 192=4, 512=16')
    check((by['hi__a_128'].gw, by['hi__a_128'].gh) == (4, 4), 'A is 4x4')
    rows_ = G.things_rows(kept, {})
    check(len(rows_) == 27 and rows_[0]['key'] == 'hi__a_128_r0c0', 'item rows in id order')
    r0 = rows_[0]
    check((r0['kind'], r0['flags'], r0['w'], r0['h'], r0['x'], r0['y']) ==
          ('stump', 'bottom notwalkable notmoveable', 4, 4, 0, 0) and r0['name'] == 'A 128', 'single piece blocks: %s' % r0)
    check(r0['extra'] == 'family=hi|group=hi__a_128|gw=4|gh=4|piece=0,0', 'extra of a single piece')
    b = [r for r in rows_ if r['key'].startswith('hi__b_256_')]
    kinds = {r['key'][-4:]: r['kind'] for r in b}
    check(kinds == {'r0c0': 'decor', 'r0c1': 'decor', 'r1c0': 'stump', 'r1c1': 'stump'}, 'bottom row blocks, upper does not: %s' % kinds)
    up = next(r for r in b if r['key'].endswith('r0c1'))
    check(up['flags'] == 'notmoveable' and up['name'] == 'B 256 R0C1' and (up['x'], up['y'], up['w'], up['h']) == (128, 0, 4, 4),
          'upper piece: %s' % up)
    c = {r['key'][-4:]: r for r in rows_ if r['key'].startswith('hi__c_192_')}
    check((c['r0c0']['w'], c['r0c0']['h'], c['r1c1']['x'], c['r1c1']['y']) == (2, 2, 64, 64), '192 px pieces 2x2 + 4x4')
    check(all(r['extra'].startswith('family=') and ('gw=6|gh=6' in r['extra']) for r in c.values()), 'group extra on every piece')
    # the piece atlas cell is the piece of the group picture
    import import_art_things as I
    with tempfile.TemporaryDirectory() as td:
        os.makedirs(os.path.join(td, G.ATLAS_DIR))
        from PIL import Image
        for g in kept:
            Image.fromarray(g.arr, 'RGBA').save(os.path.join(td, g.atlas + '.png'))
        open(os.path.join(td, 'things.csv'), 'w', newline='').write(G.things_text(rows_))
        I.ATLAS_DIR[0] = td
        I._atlas.clear()
        its = I.read_things(os.path.join(td, 'things.csv'))
        check(len(its) == 27, 'importer parses the rows')
        for r in its:
            frames, px, py, nph = I.item_frames(r)
            check(len(frames) == 1 and (px, py, nph) == (1, 1, 1), 'one frame %s' % r['key'])
            g = by[r['ex']['group']]
            pc = next(x for x in g.pieces if P.piece_key(g.key, x) == r['key'])
            check(np.array_equal(frames[(0, 0, 0)], P.cut_piece(g.arr, pc)), 'importer cell = piece %s' % r['key'])
    # sums: sorted, one per group, deterministic
    t = G.sums_of(kept)
    check([ln.split('  ')[1] for ln in t.splitlines()] == sorted('pack30_bldg/%s.png' % k for k in keys), 'sums sorted')
    check(t == G.sums_of(list(reversed(kept))), 'sums independent of order')
    # sources
    src = G.sources_text(kept)
    check(src.splitlines()[0] == 'name,kind,pack,source,licence' and 'hi__b_256_r1c0,item,set30 mutter,hi/B_256.png,' in src
          and src.count('\n') == 28, 'sources csv: one row per item')
    # overrides: rename, blocking on a group and on a piece, kind, flags, light
    ov = {'hi__b_256': {'rename': 'Gate Hall', 'blocking': 0}, 'hi__b_256_r1c1': {'blocking': 1},
          'hi__c_192': {'kind': 'prop', 'light': (3, 207)}, 'hi__a_128': {'blocking': 0},
          'mid__d_512_r3c3': {'flags': 'notwalkable'}}
    k2, _d = G.render(srcs, load_of(files), ov)
    r2 = {r['key']: r for r in G.things_rows(k2, ov)}
    check(r2['hi__b_256_r1c0']['kind'] == 'decor' and r2['hi__b_256_r1c1']['kind'] == 'stump', 'blocking override: piece beats group')
    check(r2['hi__b_256_r0c0']['name'] == 'Gate Hall R0C0', 'rename')
    check(r2['hi__a_128_r0c0']['kind'] == 'decor' and r2['hi__a_128_r0c0']['flags'] == 'notmoveable', 'blocking 0 on a single piece')
    check(r2['hi__c_192_r1c1']['kind'] == 'prop' and r2['hi__c_192_r1c1']['flags'].endswith('light:3:207'), 'kind and light')
    check(r2['mid__d_512_r3c3']['flags'] == 'notwalkable', 'flags override on a piece')
    k3, d3 = G.render(G.select(rows, pk, {'hi__b_256': {'skip': 1}}), load_of(files), {})
    check('hi__b_256' not in [g.key for g in k3], 'skip override removes a building')
    # a vanishing piece takes no id: art only in the north-west corner of a 256 picture
    corner = {('hi', 'Z.png'): pic(256, 256, (0, 0, 40, 40), 8)}
    kz, _ = G.render(G.select([row('hi', 'Z.png', 256, 256)], pk), load_of(corner), {})
    check(len(kz[0].pieces) == 1 and (kz[0].gw, kz[0].gh) == (2, 2), 'only pieces with art get an id')


def test_overflow():
    pk = [pack('hi'), pack('mid', fit='medium'), pack('lo', fit='low')]
    files, rows = {}, []
    # hi: 60 x 4 pieces (240 ids), mid: 30 x 4 (120), lo: 20 x 4 (80) + 4 x 4 more = 16 over... total 456 + 16
    for slug, n in (('hi', 60), ('mid', 30), ('lo', 24)):
        for i in range(n):
            a = pic(256, 256, (0, 0, 256, 256), 10 + i)
            a[100, 100] = (i, 77, ('hi', 'mid', 'lo').index(slug), 255)             # make every picture distinct
            files[(slug, '%s_%02d.png' % (slug, i))] = a
            rows.append(row(slug, '%s_%02d.png' % (slug, i), 256, 256))
    srcs = G.select(rows, pk)
    try:
        G.render(srcs, load_of(files), {})
        check(False, 'overflow must stop')
    except P.PackError as e:
        msg = str(e)
        check('456 ids needed' in msg and 'holds 400' in msg and '14 building(s), 56 id(s) over' in msg
              and 'lo__lo_10 (4)' in msg and 'hi__' not in msg.split('Dropped first')[1], 'overflow error lists the tail: %s' % msg[:200])
    kept, dropped = G.render(srcs, load_of(files), {}, drop_overflow=True)
    check(len(kept) == 100 and sum(len(g.pieces) for g in kept) == 400, '100 buildings fill the block exactly')
    over = [n for n, _s, why in dropped if why == 'overflow']
    check(over == ['lo__lo_%02d' % i for i in range(10, 24)], 'the lowest-priority buildings are dropped first')
    check(all(g.key.startswith(('hi__', 'mid__')) or int(g.key[-2:]) < 10 for g in kept), 'kept are the high ones')
    # ids of a kept building do not depend on lower ones
    kept2, _ = G.render(G.select(rows[:-5], pk), load_of(files), {}, drop_overflow=True)
    check([g.key for g in kept2][:90] == [g.key for g in kept][:90], 'prefix is stable')
    # exactly 400 is fine
    k3, _ = G.render(G.select([r for r in rows if not (r.path.startswith('lo_') and int(r.path[3:5]) >= 10)], pk), load_of(files), {})
    check(sum(len(g.pieces) for g in k3) == 400, 'exactly 400 ids build')
    rows_ = G.things_rows(kept, {})
    check(len(rows_) == 400, '400 item rows')
    # the overflow set is the tail of the plan, built for the overflow range
    tail, none = G.render(srcs, load_of(files), {}, overflow=True)
    check(none == [] and [g.key for g in tail] == over, 'overflow set = the groups dropped from the main block, in order')
    check((G.OVER_FIRST, G.OVER_LAST, G.OVER_BLOCK) == (37113, 62535, 25423), 'overflow range 37113..62535')
    check(G.OVER_FIRST > 37112 and G.OVER_LAST + 3000 == 65535, 'overflow range avoids the donor hole and fits u16 server ids')
    try:
        G.use_variant(True)
        check((G.FIRST_ID, G.THINGS.endswith('pack30_bldg2.csv'), G.ATLAS_DIR) == (37113, True, 'pack30_bldg2'), 'variant paths')
        check(tail[0].atlas == 'pack30_bldg2/lo__lo_10' and 'DROPPED' not in G.texts_of(tail, [], {}), 'overflow atlas dir')
        check(len(G.texts_of(tail, [], {})) == 3, 'no dropped table for the overflow set')
    finally:
        G.use_variant(False)
    check((G.FIRST_ID, G.ATLAS_DIR) == (36059, 'pack30_bldg'), 'back to the main variant')
    huge = [G.Group(srcs[0], 'x%d' % i, 'X', np.ones((256, 256, 4), np.uint8)) for i in range(7000)]
    raises(lambda: G.allocate(huge, False, G.OVER_BLOCK, G.OVER_FIRST), 'more than the overflow range holds stops')


def test_sheet():
    a = np.zeros((256, 256, 4), np.uint8)
    a[10:100, 10:90] = (1, 2, 3, 255)               # building 1: 3x3 tiles after growing
    a[120:250, 130:250] = (4, 5, 6, 255)            # building 2: 4x4
    a[5:15, 200:210] = (7, 8, 9, 255)               # a prop: one tile -> small
    pk = [pack('rv', category='grounds', also='bldg')]
    G.RULES['rv'] = {'inc': 'buildings'}
    try:
        rows = [row('rv', 'sheet_2_buildings.png', 256, 256), row('rv', 'sheet_5_nature.png', 256, 256)]
        srcs = G.select(rows, pk)
        check([s.source for s in srcs] == ['rv/sheet_2_buildings.png'] and srcs[0].sheet, 'only the building sheet is taken')
        kept, dropped = G.render(srcs, load_of({('rv', 'sheet_2_buildings.png'): a}), {})
        check([g.key for g in kept] == ['rv__sheet_2_buildings__s1', 'rv__sheet_2_buildings__s3'], 'segments are groups (reading order, numbers kept)')
        check([(g.gw, g.gh) for g in kept] == [(3, 4), (4, 5)] and kept[0].name == 'Sheet 2 Buildings 1', 'segment sizes')
        check(dropped == [('rv__sheet_2_buildings__s2', 'rv/sheet_2_buildings.png[s2]', 'small')], 'a tiny segment is dropped: %s' % dropped)
        k2, d2 = G.render(srcs, load_of({('rv', 'sheet_2_buildings.png'): a}), {'rv__sheet_2_buildings__s3': {'skip': 1}})
        check(len(k2) == 1 and ('rv__sheet_2_buildings__s3', 'rv/sheet_2_buildings.png[s3]', 'skip') in d2, 'segment skip')
        big = np.zeros((1024, 1024, 4), np.uint8)
        big[0:700, 0:700] = 255
        k3, d3 = G.render(srcs, load_of({('rv', 'sheet_2_buildings.png'): big}), {})
        check(not k3 and d3[0][2] == 'large', 'a segment over 16 tiles is left out')
    finally:
        del G.RULES['rv']
    raises(lambda: G.groups_of(G.Src(pack('p'), row('p', 'X.png', 1024, 1024)), pic(1024, 1024), {}), 'a single picture over 16 tiles stops')


# ------------------------------------------------------------------------------------------------ build --check against disk
def test_check():
    pk, rows, files = fixture()
    ov = {}
    srcs = G.select(rows, pk, ov)
    kept, dropped = G.render(srcs, load_of(files), ov)
    texts = G.texts_of(kept, dropped, ov)
    saved = (G.THINGS, G.SUMS, G.SOURCES, G.DROPPED, G.ART)
    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, 'pack30_bldg')
        G.THINGS, G.SUMS, G.SOURCES, G.DROPPED = [os.path.join(td, os.path.basename(p)) for p in
                                                  (G.THINGS, G.SUMS, G.SOURCES, G.DROPPED)]
        G.ART = td
        try:
            texts = G.texts_of(kept, dropped, ov)
            check(G.check_structure(srcs, pk, ov, out)[0].endswith('missing (run build --src)'), 'missing tables reported')
            G.write_outputs(kept, texts, out)
            check(open(os.path.join(out, '.gitignore')).read() == G.GITIGNORE_TEXT, 'group folder ignores itself')
            check(sorted(f for f in os.listdir(out) if f.endswith('.png')) == sorted(g.key + '.png' for g in kept), 'group files')
            check(G.check_structure(srcs, pk, ov, out) == [], 'structure check passes: %s' % G.check_structure(srcs, pk, ov, out))
            check(G.disk_problems(kept, out) == [], 'disk matches')
            # a changed atlas is found
            from PIL import Image
            p = os.path.join(out, 'hi__a_128.png')
            im = np.asarray(Image.open(p).convert('RGBA')).copy()
            im[5, 5] = (1, 2, 3, 255)
            Image.fromarray(im, 'RGBA').save(p)
            check(G.disk_problems(kept, out) and G.check_structure(srcs, pk, ov, out), 'changed atlas found by both checks')
            G.write_outputs(kept, texts, out)
            # a hand-edited things row is found
            good = open(G.THINGS).read()
            open(G.THINGS, 'w').write(good.replace('bottom notwalkable notmoveable', 'notmoveable', 1))
            check(G.check_structure(srcs, pk, ov, out), 'wrong blocking flags found')
            open(G.THINGS, 'w').write(good.replace(',4,4,1,1,', ',4,3,1,1,', 1))
            check(G.check_structure(srcs, pk, ov, out), 'wrong piece size found')
            open(G.THINGS, 'w').write(good)
            # an override that changes the plan makes the committed tables stale
            ov2 = {'hi__b_256': {'blocking': 0}}
            check(G.check_structure(srcs, pk, ov2, out), 'override not reflected in the tables found')
            check(G.check_structure(G.select(rows, pk, {'hi__a_128': {'skip': 1}}), pk, ov, out),
                  'a file skipped by an override but still built is found')
            # a file that appears in the list but is neither built nor dropped
            more = rows + [row('hi', 'Z_new.png', 128, 128)]
            check(G.check_structure(G.select(more, pk, ov), pk, ov, out), 'unaccounted building file found')
            open(G.SUMS, 'w').write(open(G.SUMS).read().replace('pack30_bldg/hi__a_128.png', 'pack30_bldg/hi__zz.png'))
            check(G.check_structure(srcs, pk, ov, out), 'sums path mismatch found')
        finally:
            G.THINGS, G.SUMS, G.SOURCES, G.DROPPED, G.ART = saved
    # the block is 400 ids from 36059
    check((G.FIRST_ID, G.BLOCK, G.LAST_ID) == (36059, 400, 36458), 'block 36059-36458')
    check(list(G.texts_of(kept, dropped, ov).values()) == list(texts.values()), 'tables are deterministic')


def test_real_tables():
    """the committed tables agree with the file list and with each other (what CI runs)"""
    if not os.path.isfile(G.THINGS):
        return
    packs, ov, srcs = G.load_plan()
    bad = G.check_structure(srcs, packs, ov)
    check(not bad, 'committed pack30_bldg tables: %s' % bad[:3])


def main():
    for t in (test_split, test_select, test_pixels, test_render, test_overflow, test_sheet, test_check, test_real_tables):
        t()
    print('gen_pack30_bldg_test: %d checks passed' % len(OK))


if __name__ == '__main__':
    main()
