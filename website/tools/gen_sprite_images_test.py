#!/usr/bin/env python3
"""Tests of gen_sprite_images.py: the outfit colour maths on hand-made template masks, the placement of a rider and a
mount, the stack and fluid patterns, the ownership rules, and a build on a tiny synthetic pair (no real pair needed).

    python3 -I website/tools/gen_sprite_images_test.py
"""
import json
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_sprite_images as g  # noqa: E402
import check_pair_test as cpt  # noqa: E402  (synthetic dat / spr writers)

FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def rgba(*px):
    return np.array(px, np.uint8)


def test_colour_table():
    import compose_outfit
    for c in range(133):
        expect(g.outfit_colour(c) == compose_outfit.outfit_colour(c), f'colour {c} matches the composer')
    expect(g.outfit_colour(0) == (255, 255, 255), 'colour 0 is white')
    expect(g.outfit_colour(1) == (255, 212, 191), 'colour 1 is ffd4bf')
    expect(g.outfit_colour(19) == (218, 218, 218), 'colour 19 is a grey')
    expect(g.outfit_colour(114) == (36, 36, 36), 'colour 114 is the darkest grey')
    expect(g.outfit_colour(133) == g.outfit_colour(0) and g.outfit_colour(-1) == g.outfit_colour(0), 'out of range is 0')


def test_tint_hand_made():
    # a 1 x 6 strip of art and its template: head, body, legs, feet, a shaded yellow (not a template colour), no mask
    art = rgba([[200, 100, 50, 255], [200, 100, 50, 255], [200, 100, 50, 255], [200, 100, 50, 255],
                [200, 100, 50, 255], [200, 100, 50, 255]])
    mask = rgba([[255, 255, 0, 255], [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
                 [254, 254, 0, 255], [0, 0, 0, 0]])
    cols = (0, 1, 94, 114)
    out = g.tint(art.copy(), mask, cols)
    for i, c in enumerate(cols):
        want = tuple((v * k + 127) // 255 for v, k in zip((200, 100, 50), g.outfit_colour(c)))
        expect(tuple(out[0, i, :3]) == want, f'part {i} multiplied by colour {c}: {tuple(out[0, i, :3])} {want}')
        expect(out[0, i, 3] == 255, f'part {i} keeps its alpha')
    expect(tuple(out[0, 4]) == (200, 100, 50, 255), 'an inexact template colour is left alone')
    expect(tuple(out[0, 5]) == (200, 100, 50, 255), 'no template pixel: art unchanged')
    # colour 0 (white) changes nothing; a transparent template pixel of the right colour is ignored
    out = g.tint(art.copy(), mask, (0, 0, 0, 0))
    expect((out == art).all(), 'white leaves the art as it is')
    m2 = mask.copy(); m2[0, 0, 3] = 0
    out = g.tint(art.copy(), m2, (114, 114, 114, 114))
    expect(tuple(out[0, 0]) == (200, 100, 50, 255), 'a transparent template pixel does not count')
    # hand-made numbers: 200 * 255 = 51000 -> 200; 100 * 212 = 21200 -> (21200 + 127) // 255 = 83
    out = g.tint(rgba([[100, 100, 100, 255]]), rgba([[255, 255, 0, 255]]), (1, 0, 0, 0))
    expect(tuple(out[0, 0, :3]) == (100, 83, 75), f'100 x ffd4bf = 100, 83, 75: {tuple(out[0, 0, :3])}')


def sheet_of(cells, cw=32, ch=32, layers=2):
    """cells: list of (art, mask) arrays (ch x cw x 4) in column order -> the layer sheet"""
    s = np.zeros((ch * layers, cw * len(cells), 4), np.uint8)
    for i, (a, m) in enumerate(cells):
        s[0:ch, i * cw:(i + 1) * cw] = a
        if layers > 1:
            s[ch:2 * ch, i * cw:(i + 1) * cw] = m
    return s


def cell(colour=None, mcolour=None, xy=(0, 0)):
    a = np.zeros((32, 32, 4), np.uint8); m = np.zeros((32, 32, 4), np.uint8)
    if colour:
        a[xy[1], xy[0]] = colour
    if mcolour:
        m[xy[1], xy[0]] = mcolour
    return a, m


def test_compose_addons():
    # 1x1 look, 3 addon patterns, no mount: base pixel (0,0) body, addon 1 pixel (1,0) head, addon 2 pixel (2,0)
    meta = [1, 1, 0, 0, 3, 1, 2, 0, 0, 0, 0]
    s = sheet_of([cell((100, 100, 100, 255), (255, 0, 0, 255), (0, 0)),
                  cell((100, 100, 100, 255), (255, 255, 0, 255), (1, 0)),
                  cell((50, 60, 70, 255), None, (2, 0))])
    out = g.compose(meta, s, (0, 1, 0, 0), addons=0)
    expect(out.shape == (32, 32, 4), 'a 1x1 look is 32 x 32')
    expect(tuple(out[0, 0, :3]) == (100, 83, 75), 'body coloured')
    expect(out[0, 1, 3] == 0 and out[0, 2, 3] == 0, 'no addons drawn without addons')
    out = g.compose(meta, s, (1, 0, 0, 0), addons=1)
    expect(tuple(out[0, 1, :3]) == (100, 83, 75) and out[0, 2, 3] == 0, 'addon 1 drawn and coloured, not addon 2')
    out = g.compose(meta, s, (0, 0, 0, 0), addons=2)
    expect(out[0, 1, 3] == 0 and tuple(out[0, 2]) == (50, 60, 70, 255), 'addon 2 only')
    out = g.compose(meta, s, (0, 0, 0, 0), addons=3)
    expect(out[0, 1, 3] == 255 and out[0, 2, 3] == 255, 'both addons')
    # a look without a template is drawn as it is
    meta1 = [1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 0]
    out = g.compose(meta1, s[0:32, 0:32], (114, 114, 114, 114))
    expect(tuple(out[0, 0, :3]) == (100, 100, 100), 'one layer: no colouring')


def test_place():
    player = [2, 2, 8, 8, 3, 2, 2, 0, 0, 0, 0]
    expect(g.place(player) == ((-40, -40), None, 0), 'a 2x2 look with displacement 8,8')
    stock_mount = [2, 2, 8, 8, 1, 1, 1, 0, 0, 0, 0]
    r, m, z = g.place(player, stock_mount)
    expect(z == 1 and r == (-40, -40) and m == (-48, -48), f'stock path: mount drawn 8 px further up left: {r} {m}')
    big = [3, 4, -32, -32, 1, 1, 1, 1, 1, 14, -2]   # a centred donor mount with a rider seat (base patch 0034)
    r, m, z = g.place(player, big)
    expect(m == (-32, -64), f'negative mount: drawn by its own displacement: {m}')
    expect(r == (14 - 40, -2 - 40), f'rider moved by the seat: {r}')
    no_mount_pattern = [2, 2, 8, 8, 3, 1, 2, 0, 0, 0, 0]
    expect(g.place(no_mount_pattern, big) == ((-40, -40), None, 0), 'a look without a mounted pattern rides nothing')
    # the canvas holds both frames
    s = np.zeros((128, 64 * 6, 4), np.uint8); s[0, 64 * 3] = (1, 2, 3, 255)   # mounted pattern z 1, addon 0
    ms = np.zeros((128, 96, 4), np.uint8); ms[127, 95] = (9, 9, 9, 255)
    out = g.compose(player, s, mount=big, mount_sheet=ms)
    expect(out.shape == (128, 96, 4), f'canvas covers rider and mount: {out.shape}')
    expect(tuple(out[127, 95]) == (9, 9, 9, 255), 'mount drawn at its place')
    expect(tuple(out[-42 + 64, -26 + 32]) == (1, 2, 3, 255), 'rider drawn from its mounted pattern at the seat')


def test_patterns():
    expect([g.stack_pattern(n, 4, 2) for n in (0, 1, 2, 4, 5, 9, 10, 24, 25, 49, 50, 100)] ==
           [(0, 0), (0, 0), (1, 0), (3, 0), (0, 1), (0, 1), (1, 1), (1, 1), (2, 1), (2, 1), (3, 1), (3, 1)],
           'stack patterns')
    expect(g.stack_pattern(7, 1, 1) == (0, 0), 'not a 4 x 2 stack: pattern 0')
    expect([g.fluid_pattern(k, 4, 2) for k in (0, 1, 3, 4, 7, 8)] == [(0, 0), (1, 0), (3, 0), (0, 1), (3, 1), (0, 0)],
           'fluid patterns')


def test_owners(tmp):
    rows = g.read_owners()
    expect(g.tier_of(rows, 'outfit', 128) == 'stock', 'a stock look')
    expect(g.tier_of(rows, 'outfit', 2073) == 'donor', 'a class look is donor art')
    expect(g.tier_of(rows, 'outfit', 2043) == 'stock', 'an exception after a range wins')
    expect(g.tier_of(rows, 'outfit', 2010) == 'own', 'the art set looks are ours')
    expect(g.tier_of(rows, 'item', 2000) == 'stock' and g.tier_of(rows, 'item', 33659) == 'own', 'items')
    expect(g.tier_of(rows, 'item', 99999) == 'stock', 'an unlisted id is not ours')
    expect(g.parse_publish('') == ('own', 'donor') and g.parse_publish('all') == ('own', 'donor', 'stock')
           and g.parse_publish('own') == ('own',), 'publish settings')
    try:
        g.parse_publish('own,other'); expect(False, 'a bad tier is refused')
    except SystemExit:
        pass


def test_build(tmp):
    W, Y, R, B = (200, 100, 50, 255), (255, 255, 0, 255), (255, 0, 0, 255), (0, 0, 255, 255)
    recs = [cpt.record({0: W, 1: W}),            # 1 art
            cpt.record({0: Y, 1: R}),            # 2 template
            cpt.record({5: (10, 20, 30, 255)}),  # 3 a stock item
            cpt.record({k: (k, 0, 0, 255) for k in range(8)})]   # 4 a stack piece
    items = [cpt.entry(bytes([17]), [cpt.group([1])]),                                     # 100 ours
             cpt.entry(bytes([17]), [cpt.group([3])]),                                     # 101 stock
             cpt.entry(bytes([5, 17]), [cpt.group([4, 1, 1, 1, 1, 1, 1, 4], px=4, py=2)])]  # 102 stackable, ours
    outfits = [cpt.entry(b'', [cpt.group([1, 2] * 4, layers=2, px=4, gtype=0)], outfit=True),   # 1 ours
               cpt.entry(b'', [cpt.group([3] * 4, px=4, gtype=0)], outfit=True)]               # 2 stock
    d = os.path.join(tmp, 'pair'); os.makedirs(d)
    dat, spr = os.path.join(d, 'Tibia.dat'), os.path.join(d, 'Tibia.spr')
    open(dat, 'wb').write(cpt.dat_bytes(items, outfits, [], []))
    open(spr, 'wb').write(cpt.spr_bytes(recs))
    owners = os.path.join(tmp, 'owners.csv')
    open(owners, 'w').write('kind,first,last,tier,source\nitem,100,100,own,t\nitem,102,102,donor,t\n'
                            'outfit,1,1,own,t\n')
    out = os.path.join(tmp, 'out')
    idx = g.build(dat, spr, out, publish=('own', 'donor'), owners=owners, log=lambda s: None,
                  ids={2000: 100, 2001: 101, 2002: 102, 2003: 100, 2004: 999})
    expect(set(idx['items']) == {'2000', '2002', '2003'} and idx['items']['2002'] == 'c', f'items {idx["items"]}')
    expect(list(idx['outfits']) == ['1'], f'only our look: {list(idx["outfits"])}')
    ph = open(os.path.join(out, 'placeholder-item.png'), 'rb').read()
    for sid in (2001, 2004):
        expect(open(os.path.join(out, 'items', f'{sid}.png'), 'rb').read() == ph, f'{sid}: the placeholder')
    a = np.asarray(Image.open(os.path.join(out, 'items', '2000.png')).convert('RGBA'))
    expect(tuple(a[0, 0]) == W and a[0, 2, 3] == 0, 'our item drawn from its sprite')
    expect(os.path.isfile(os.path.join(out, 'items', '2003.png')), 'a second server id of the same client id')
    c50 = np.asarray(Image.open(os.path.join(out, 'items', '2002-c50.png')).convert('RGBA'))
    expect(tuple(c50[0, 3]) == (3, 0, 0, 255), 'the 50-piece stack is pattern (3, 1)')
    expect(not os.path.exists(os.path.join(out, 'outfits', '2.png')), 'no sheet of a stock look')
    sheet = np.asarray(Image.open(os.path.join(out, 'outfits', '1.png')).convert('RGBA'))
    expect(sheet.shape == (64, 32, 4), f'sheet: art and template rows, one column: {sheet.shape}')
    raw = g.read_raw(os.path.join(out, 'outfits', '1.raw'))
    expect(raw.shape == sheet.shape and (raw == sheet).all(), 'the raw sheet for PHP holds the same pixels')
    dflt = g.compose(idx['outfits']['1'], raw)
    head = tuple((v * k + 127) // 255 for v, k in zip(W[:3], g.outfit_colour(78)))
    body = tuple((v * k + 127) // 255 for v, k in zip(W[:3], g.outfit_colour(69)))
    expect(tuple(dflt[0, 0, :3]) == head and tuple(dflt[0, 1, :3]) == body, 'default look: head 78, body 69')
    j = json.load(open(os.path.join(out, 'index.json')))
    expect(j['publish'] == ['own', 'donor'] and len(j['stamp']) == 16, 'index settings')
    idx2 = g.build(dat, spr, os.path.join(tmp, 'out2'), publish=('own',), owners=owners, log=lambda s: None,
                   ids={2002: 102})
    expect(idx2['items'] == {}, 'donor items left out with publish own')
    expect(idx['stamp'] != idx2['stamp'], 'the stamp follows the settings')
    del B


def main():
    tmp = tempfile.mkdtemp(prefix='gen_sprite_images_test_')
    test_colour_table()
    test_tint_hand_made()
    test_compose_addons()
    test_place()
    test_patterns()
    test_owners(tmp)
    test_build(tmp)
    print('gen_sprite_images:', 'OK' if not FAILS else f'{len(FAILS)} failure(s)')
    sys.exit(1 if FAILS else 0)


if __name__ == '__main__':
    main()
