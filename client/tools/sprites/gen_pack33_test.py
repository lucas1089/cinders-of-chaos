#!/usr/bin/env python3
"""Tests of gen_pack33.py on synthetic packs (no pack file is read): the trim and placement geometry, the
displacement rule, the element table, the kit kind rules, a two-layer aura and a wings thing cut from a synthetic
sheet, a kit item strip, a kit look and its corpse, the md5 guard, and the committed tables (build --check without
sources).

    python3 -I client/tools/sprites/gen_pack33_test.py
"""
import json
import os
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_pack33 as G  # noqa: E402

FAILS = []


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def save(path, a):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(a.astype(np.uint8), 'RGBA').save(path)


def test_geometry():
    # 64 x 64 frame, anchor (1, 1): art inside the anchor tile and the tile up-left
    tw, th, R, B, r, b = G.trim_plan((10, 4, 60, 62), 1, 1)
    check((tw, th, R, B, r, b) == (2, 2, 64, 64, 0, 0), 'trim 64 anchor 1,1: %r' % ((tw, th, R, B, r, b),))
    # anchor (0, 0) and art reaching 20 px right and 10 px below the anchor tile
    tw, th, R, B, r, b = G.trim_plan((0, 0, 52, 42), 0, 0)
    check((r, b, R, B) == (20, 10, 52, 42) and (tw, th) == (2, 2), 'trim right/below: %r' % ((tw, th, R, B, r, b),))
    # a box far up-left of the anchor grows the canvas, never shrinks below the anchor tile
    tw, th, R, B, r, b = G.trim_plan((0, 0, 10, 10), 2, 2)
    check((tw, th, R, B) == (3, 3, 96, 96), 'trim keeps the anchor tile: %r' % ((tw, th, R, B),))
    cell = np.zeros((64, 64, 4), np.uint8)
    cell[50, 51] = (1, 2, 3, 255)
    out = G.place(cell, 2, 2, 52, 52)
    check(out.shape == (64, 64, 4) and tuple(out[50 + 12, 51 + 12]) == (1, 2, 3, 255), 'place moves to bottom-right')
    out = G.place(cell, 1, 1, 64, 64)
    check(out[..., 3].sum() == 255 and tuple(out[50 - 32, 51 - 32]) == (1, 2, 3, 255), 'place crops left / top')
    check(G.displacement('wings', 4, 4, 32, 32) == (G.BODY_REF - 32, G.BODY_REF - 32), 'wings displacement')
    check(G.displacement('aura', 2, 2, 0, 0) == (G.BODY_REF + 16, G.BODY_REF + 16), 'aura centring 2x2')
    check(G.displacement('aura', 1, 3, 0, 4) == (G.BODY_REF, G.BODY_REF - 4 + 32), 'aura centring per axis')


def test_tables():
    readme = '## Fire (2)\n\n| piece | file | x |\n|---|---|---|\n| A | `a_one` | 1 |\n| B | `b_two` | 1 |\n' \
             '## Dark (1)\n| C | `c_three` | 1 |\n'
    check(G.elements(readme) == {'a_one': 'fire', 'b_two': 'fire', 'c_three': 'dark'}, 'elements')
    k = G.kit_item_kind({'id': 'x', 'category': 'tiles', 'kind': 'ground'})
    check(k[0] == 'ground' and 'fullground' in k[1], 'kit ground')
    check(G.kit_item_kind({'id': 'barn_planks_h', 'category': 'walls', 'kind': 'h'}) == ('stump', G.BLOCK), 'wall')
    check(G.kit_item_kind({'id': 'barn_planks_door_open_h', 'category': 'walls', 'kind': 'door_open'})[0] == 'decor',
          'open door walkable')
    check(G.kit_item_kind({'id': 'portal_open', 'category': 'mechanics', 'kind': 'prop'})[0] == 'decor', 'portal')
    try:
        G.kit_item_kind({'id': 'x', 'category': 'sky', 'kind': 'cloud'})
        check(False, 'unknown kit kind refused')
    except G.BuildError:
        pass


def vfx_pack(root, slug, kind):
    fw = fh = 64
    n = 3
    sheet = np.zeros((8 * fh, n * fw, 4), np.uint8)
    front = np.zeros_like(sheet)
    for row in range(8):
        for f in range(n):
            sheet[row * fh + 20:row * fh + 30, f * fw + 22:f * fw + 34] = (200, 10 * row, f, 255)
            front[row * fh + 40, f * fw + 40] = (9, 9, row, 255)
    rel = 'oblique/32px/%s/thing_one' % slug
    files = {'all': rel + '.png', 'back': rel + '_back.png', 'front': rel + '_front.png'}
    save(os.path.join(root, slug, files['all']), np.maximum(sheet, front))
    save(os.path.join(root, slug, files['back']), sheet)
    save(os.path.join(root, slug, files['front']), front)
    meta = {'effects': [{'id': 'thing_one', 'frames': n, 'fps': 12, 'directions': list(G.ROW_OF),
                         'variants': {'oblique/32': {'frame_w': fw, 'frame_h': fh, 'anchor_tile': [1, 1], 'rows': 8,
                                                     'columns': n, 'files': files}}}]}
    open(os.path.join(root, slug, 'metadata.json'), 'w').write(json.dumps(meta))
    open(os.path.join(root, slug, 'README.md'), 'w').write('## Fire (1)\n| T | `thing_one` | 3 |\n')


def test_vfx_build():
    with tempfile.TemporaryDirectory() as root:
        vfx_pack(root, 'heads', 'aura')
        vfx_pack(root, 'wings', 'wings')
        rows, sheets, sources, S = G.build_pack('heads', root, scanning=True)
        check(len(rows) == 1 and rows[0][1:3] == ['outfit', 'aura'], 'heads row kind')
        r = rows[0]
        check((r[7], r[8], r[10]) == (2, 2, 3), 'heads 2x2, 3 phases: %r' % (r[7:11],))
        check('displacement:%d:%d' % (G.BODY_REF + 16, G.BODY_REF + 16) in r[11], 'heads displacement %s' % r[11])
        check('layers=2' in r[14] and 'element=fire' in r[14], 'heads extra %s' % r[14])
        sh = sheets[0][1]
        check(sh.shape == (3 * 64, 8 * 64, 4), 'aura sheet: 3 phases x (2 layers x 4 directions)')
        # direction S (dat 2) is pack row 2: green channel 20 in layer 0, frame 1 blue 1
        cell = sh[64:128, 2 * 64:3 * 64]
        check(tuple(cell[25, 25]) == (200, 20, 1, 255), 'south cell from pack row 2: %r' % (tuple(cell[25, 25]),))
        cell = sh[0:64, (4 + 0) * 64:(4 + 1) * 64]                 # layer 1, north = pack row 6
        check(tuple(cell[40, 40]) == (9, 9, 6, 255), 'front layer north from row 6')
        check(sorted(S.used) == ['README.md', 'metadata.json', 'oblique/32px/heads/thing_one_back.png',
                                 'oblique/32px/heads/thing_one_front.png'], 'heads files used %r' % sorted(S.used))
        rows, sheets, sources, S = G.build_pack('wings', root, scanning=True)
        r = rows[0]
        check(r[2] == 'wings' and 'layers=1' in r[14] and 'displacement:%d:%d' % (G.BODY_REF, G.BODY_REF) in r[11],
              'wings row %r' % r[11])
        check(sources[0][2] == 'set33 wings' and sources[0][4] == G.LICENCE, 'wings source row')
        # the md5 guard: a file that differs from the list is refused before decoding
        S2 = G.Source(root, 'wings', scanning=True)
        S2.png('oblique/32px/wings/thing_one.png')
        listed = dict(S2.used)
        S3 = G.Source.__new__(G.Source)
        S3.src, S3.slug, S3.scanning, S3.used = root, 'wings', False, {}
        S3.listed = {k: v._replace(md5='0' * 32) for k, v in listed.items()}
        try:
            S3.png('oblique/32px/wings/thing_one.png')
            check(False, 'md5 guard refuses a changed file')
        except Exception as e:
            check('md5' in str(e), 'md5 guard message: %s' % e)
        try:
            S3.png('../escape.png')
            check(False, 'unsafe path refused')
        except G.BuildError:
            pass


def test_kit_build():
    with tempfile.TemporaryDirectory() as root:
        base = os.path.join(root, 'kit')
        sprites = []
        g = np.zeros((32, 32, 4), np.uint8)
        g[...] = (90, 60, 30, 255)
        save(os.path.join(base, 'tiles/soil_1.png'), g)
        sprites.append({'id': 'soil_1', 'category': 'tiles', 'kind': 'ground', 'set': 's', 'w': 32, 'h': 32,
                        'file': 'tiles/soil_1.png', 'group': 'tiles'})
        strip = np.zeros((64, 64 * 4, 4), np.uint8)
        strip[60:64, :, :] = 255
        save(os.path.join(base, 'props/lamp_strip.png'), strip)
        save(os.path.join(base, 'props/lamp.png'), strip[:, :64])
        sprites.append({'id': 'lamp', 'category': 'props', 'kind': 'light', 'set': 'p', 'w': 64, 'h': 64,
                        'file': 'props/lamp.png', 'strip': 'props/lamp_strip.png', 'frames': 4, 'frame_w': 64,
                        'frame_h': 64, 'frame_ms': 100, 'footprint': [1, 1], 'group': 'props'})
        sprites.append({'id': 'lamp_f0', 'category': 'props', 'kind': 'light_floor', 'part_of': 'lamp', 'w': 64,
                        'h': 64, 'file': 'props/lamp.png', 'group': 'props'})
        for anim in ('idle', 'walk', 'death'):
            for d in G.KIT_DIRS:
                rel = 'monsters/king_%s_%s_strip.png' % (anim, d)
                a = np.zeros((64, 4 * 64, 4), np.uint8)
                a[40:60, :, :] = (10, 20, 30 + G.KIT_DIRS.index(d), 255)
                save(os.path.join(base, rel), a)
                sprites.append({'id': 'king_%s_%s' % (anim, d), 'category': 'figures', 'kind': 'figure',
                                'set': 'king', 'anim': anim, 'dir': d, 'file': rel, 'strip': rel, 'frames': 4,
                                'frame_ms': 150, 'w': 64, 'h': 64, 'group': 'boss'})
        open(os.path.join(base, 'catalog.json'), 'w').write(json.dumps({'sprites': sprites}))
        rows, sheets, sources, S = G.build_pack('kit', root, scanning=True)
        keys = [r[0] for r in rows]
        check(keys == ['kit__king', 'kit__soil_1', 'kit__lamp', 'kit__corpse_king'], 'kit rows %r' % keys)
        look, soil, lamp, corpse = rows
        check(look[10] == '4+4' and 'durs0=150/150/150/150' in look[14], 'kit look groups %r' % look[10])
        check('minimap:' in soil[11] and soil[2] == 'ground', 'kit ground minimap')
        check(lamp[10] == 4 and 'animateAlways' in lamp[11] and G.LIGHT in lamp[11] and 'ms=100' in lamp[14],
              'kit lamp strip %r' % lamp[11])
        check(corpse[2] == 'corpse' and corpse[10] == 1, 'kit corpse')
        check([s[0] for s in sources] == keys, 'kit sources in row order')
        lk = dict(sheets)['pack33_kit/look_king.png']
        check(lk.shape == (8 * 64, 4 * 64, 4) and lk[50, 64 * 2 + 5, 2] == 32, 'kit look sheet, south column')


def test_committed():
    if os.path.isfile(os.path.join(G.ART, 'pack33_wings.csv')):
        check(G.check_tables() == [], 'committed tables agree: %r' % G.check_tables()[:3])


if __name__ == '__main__':
    test_geometry()
    test_tables()
    test_vfx_build()
    test_kit_build()
    test_committed()
    if FAILS:
        print('gen_pack33_test: %d failures' % len(FAILS))
        sys.exit(1)
    print('gen_pack33_test: OK')
