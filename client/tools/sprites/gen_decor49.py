#!/usr/bin/env python3
"""Pair 49: decoration for the two Map Studio biomes CELESTIAL (marble, gold, crystal, starlight, clouds) and CURSED (dead
trees, graves, bones, altars, pumpkins, taint). Client ids 39111.., server ids + 4000 (server/tools/install_decor49_items.py).

    python3 -I gen_decor49.py build --src DIR            # -> art_import/decor49.png (git-ignored) + decor49.csv (things file of
                                                         #    import_art_things.py) + decor49.sums + decor49_sources.csv
                                                         #    + decor49_selection.csv + server/data/items/decor49_items.csv
    python3 -I gen_decor49.py build --src DIR --check    # rebuild in memory, compare with every committed file
    python3 -I gen_decor49.py build --check              # CI, no sources: the tables agree with each other, the sums match the
                                                         #    atlas on disk (if there is one)

Three kinds of art, all kept out of git (only this tool, the tables and the sums are committed):
  * own art    drawn by the functions below (clouds, glowing rune circles, starlight, marble pillars, taint pools, pumpkins).
  * prepared single objects of the decoration sources C, D and E (docs/CREDITS.md). --src DIR holds them:
        c/<name>.png    source C, props already cut to one object per file (transparent background, 32 px grid art)
        d/<id>.png      source D, 32x32 item art
        e/trees.png     source E, the dead tree sheet (4x4 cells, art at 4x: read at 1/4)
    Objects are recoloured where the spec says (marble / gold: a luminance ramp, flames and gems keep their colour), padded to
    whole tiles (centred, bottom aligned) and never scaled. decor49_sources.csv names each object by a neutral source letter, the
    file and the sha256 of its pixels.
Blocking: trees, statues, pillars, graves, altars, tables, crystals; small clutter, birds and ground details do not. Light items
carry light:level:colour (OT palette index), animated ones 4 phases.
"""
import colorsys
import csv
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
FIRST_CLIENT = 39111
SERVER_OFFSET = 4000
ATLAS = 'decor49'
OUT_ITEMS = os.path.join(REPO, 'server', 'data', 'items', 'decor49_items.csv')
OUT_SEL = os.path.join(HERE, 'decor49_selection.csv')
LICENCE = ('purchased or owner-supplied; use in games incl. commercial, modified or recoloured; no resale or sharing of the raw '
           'files; never AI training data or a style reference; studio: docs/CREDITS.md')


def ot(r, g, b):
    """OT palette index (6x6x6 colour cube) of levels 0..5"""
    return r * 36 + g * 6 + b


C_GOLD, C_WHITE, C_ICE, C_VIOLET, C_ORANGE, C_GREEN, C_PALE = ot(5, 4, 1), 215, ot(2, 4, 5), ot(4, 1, 5), ot(5, 4, 2), ot(1, 5, 1), ot(4, 5, 5)
MM = {'marble': 215, 'gold': ot(5, 4, 0), 'crystal': ot(3, 5, 5), 'stone': ot(3, 3, 3), 'wood': ot(2, 1, 0), 'violet': ot(2, 0, 3),
      'bone': ot(4, 4, 3), 'tree': ot(2, 2, 1), 'cloth': ot(3, 0, 0)}


# ------------------------------------------------------------------------------------------------------------------ own art
def px(w, h):
    return np.zeros((h, w, 4), np.uint8)


def put(a, x, y, c):
    if 0 <= y < a.shape[0] and 0 <= x < a.shape[1]:
        a[y, x] = (c[0], c[1], c[2], 255)


def disc_mask(w, h, discs):
    yy, xx = np.mgrid[0:h, 0:w]
    m = np.zeros((h, w), bool)
    for cx, cy, rx, ry in discs:
        m |= ((xx + .5 - cx) / rx) ** 2 + ((yy + .5 - cy) / ry) ** 2 <= 1
    return m


def shade_mask(m, ramp, outline):
    """top-lit shading of a mask: ramp light->dark by distance from the top edge and the right edge, one px outline"""
    h, w = m.shape
    a = px(w, h)
    pad = np.pad(m, 1)
    edge = m & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    ys = np.where(m.any(axis=1))[0]
    y0, y1 = ys.min(), ys.max()
    for y in range(h):
        for x in range(w):
            if not m[y, x]:
                continue
            if edge[y, x]:
                a[y, x] = (*outline, 255)
                continue
            t = (y - y0) / max(1, y1 - y0)
            k = min(len(ramp) - 1, int(t * len(ramp)))
            a[y, x] = (*ramp[k], 255)
    return a


def cloud(seed, w, h, bumps):
    m = np.zeros((h, w), bool)
    rng = np.random.RandomState(seed)
    base = disc_mask(w, h, [(w / 2, h * .62, w * .46, h * .3)])
    m |= base
    for i in range(bumps):
        cx = w * (.2 + .6 * (i + rng.rand() * .6) / bumps)
        cy = h * (.38 + .2 * rng.rand())
        r = h * (.22 + .12 * rng.rand())
        m |= disc_mask(w, h, [(cx, cy, r * 1.15, r)])
    ramp = [(252, 252, 255), (240, 244, 255), (222, 230, 250), (196, 208, 238), (170, 184, 222)]
    return shade_mask(m, ramp, (112, 126, 176))


def rune_circle(phase, base, nphase=4, star=False):
    """32x32 ground glyph: squashed ring with 8 glyph ticks and a centre mark, pulsing over the phases"""
    a = px(32, 32)
    b = [.62, .8, 1.0, .8][phase % 4]
    col = tuple(min(255, int(c * b + (255 - c) * .0)) for c in base)
    dark = tuple(int(c * .45) for c in col)
    cx, cy, rx, ry = 15.5, 17.0, 14, 9
    for k in range(240):
        t = k / 240 * 2 * np.pi
        x, y = int(round(cx + rx * np.cos(t))), int(round(cy + ry * np.sin(t)))
        put(a, x, y, col)
        put(a, int(round(cx + (rx - 3) * np.cos(t))), int(round(cy + (ry - 2) * np.sin(t))), dark)
    for k in range(8):
        t = k / 8 * 2 * np.pi + np.pi / 8
        for r in (.55, .62, .69, .76):
            put(a, int(round(cx + rx * r * np.cos(t))), int(round(cy + ry * r * np.sin(t))), col)
    pts = []
    for k in range(5 if star else 4):
        t = (k * (2 if star else 1) / (5 if star else 4)) * 2 * np.pi - np.pi / 2
        pts.append((cx + (rx - 5) * .75 * np.cos(t), cy + (ry - 3) * .75 * np.sin(t)))
    d = Image.fromarray(a)
    dr = ImageDraw.Draw(d)
    for i in range(len(pts)):
        dr.line([pts[i], pts[(i + 1) % len(pts)]], fill=(*col, 255), width=1)
    a = np.array(d)
    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        put(a, 15 + dx, 17 + dy, tuple(min(255, c + 60) for c in col))
    return a


def sparkle(phase):
    a = px(32, 32)
    r = [1, 3, 5, 3][phase % 4]
    cx, cy = 15, 15
    for i in range(-r, r + 1):
        c = (255, 246, 200) if abs(i) < 2 else (230, 208, 130)
        put(a, cx + i, cy, c)
        put(a, cx, cy + i, c)
    for i in range(1, max(1, r // 2) + 1):
        put(a, cx + i, cy + i, (255, 236, 170)); put(a, cx - i, cy - i, (255, 236, 170))
        put(a, cx + i, cy - i, (255, 236, 170)); put(a, cx - i, cy + i, (255, 236, 170))
    put(a, cx, cy, (255, 255, 255))
    for (x, y) in ((6, 22), (25, 9), (9, 7), (22, 24)):
        if (x + y + phase) % 4 < 2:
            put(a, x, y, (255, 240, 190))
    return a


MARBLE = [(250, 248, 244), (238, 236, 238), (222, 222, 232), (200, 202, 218), (170, 174, 198)]
MOUT = (92, 92, 122)


def pillar(broken):
    a = px(32, 64)
    top = 22 if broken else 4
    # plinth, shaft, capital
    def rect(x0, y0, x1, y1, ramp=MARBLE):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                edge = x in (x0, x1) or y in (y0, y1)
                if edge:
                    put(a, x, y, MOUT)
                else:
                    t = (x - x0) / max(1, x1 - x0)
                    put(a, x, y, ramp[0] if t < .3 else ramp[1] if t < .55 else ramp[2] if t < .8 else ramp[3])
    rect(6, 55, 25, 62)
    rect(8, 51, 23, 55)
    rect(10, top + (0 if broken else 7), 21, 51)
    for x in (13, 16, 19):
        for y in range(top + (1 if broken else 8), 51):
            if a[y, x, 3]:
                put(a, x, y, MARBLE[3])
    if broken:
        for x in range(10, 22):
            put(a, x, top + [0, 1, 0, 2, 3, 2, 1, 0, 2, 1, 0, 1][x - 10], MOUT)
        for (x, y) in ((4, 60), (27, 59), (3, 62), (28, 62), (26, 61)):
            put(a, x, y, MARBLE[1]); put(a, x + 1, y, MARBLE[2]); put(a, x, y + 1, MOUT)
    else:
        rect(7, 2, 24, 6)
        rect(9, 6, 22, 8)
        for x in range(8, 24):
            put(a, x, 4, (232, 190, 70))
    return a


def taint_pool(phase, green):
    a = px(32, 32)
    m = disc_mask(32, 32, [(15.5, 18, 13, 8), (10, 16, 7, 5), (22, 20, 7, 5)])
    dark, mid, light = ((30, 70, 25), (60, 150, 40), (150, 230, 90)) if green else ((52, 18, 70), (110, 40, 150), (200, 130, 240))
    pad = np.pad(m, 1)
    edge = m & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    for y in range(32):
        for x in range(32):
            if m[y, x]:
                put(a, x, y, dark if edge[y, x] else mid if (x * 3 + y * 7) % 11 else dark)
    bub = [(9, 17), (15, 20), (21, 18), (18, 15), (12, 21)]
    for i, (x, y) in enumerate(bub):
        if (i + phase) % 4 < 2:
            put(a, x, y, light); put(a, x + 1, y, mid)
    return a


def pumpkin(lit, n):
    a = px(32, 32)
    spots = [(15.5, 21.5, 9, 7)] if n == 1 else [(10, 22, 7, 5.5), (22, 20, 8, 6.5)]
    for cx, cy, rx, ry in spots:
        m = disc_mask(32, 32, [(cx, cy, rx, ry)])
        pad = np.pad(m, 1)
        edge = m & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
        for y in range(32):
            for x in range(32):
                if not m[y, x]:
                    continue
                if edge[y, x]:
                    put(a, x, y, (92, 36, 8))
                else:
                    rib = int(abs(x - cx) * 2.2 / rx) % 2 == 0
                    top = y < cy - ry * .3
                    put(a, x, y, (255, 160, 40) if top and rib else (240, 124, 20) if rib else (206, 94, 12))
        put(a, int(cx), int(cy - ry), (70, 90, 30)); put(a, int(cx), int(cy - ry) - 1, (70, 90, 30)); put(a, int(cx) + 1, int(cy - ry) - 1, (110, 130, 40))
    if lit and n == 1:
        glow = (255, 232, 90)
        for (x, y) in ((11, 20), (12, 20), (12, 19), (19, 20), (20, 20), (19, 19)):
            put(a, x, y, glow)
        for x in range(11, 21):
            put(a, x, 25 if x % 2 else 24, glow)
        put(a, 15, 22, glow); put(a, 16, 22, glow)
    return a


def own_art(name):
    k, _, v = name.partition(':')
    if k == 'cloud':
        s, w, h, b = (int(x) for x in v.split(','))
        return cloud(s, w, h, b)
    if k == 'rune':
        col, ph, star = v.split(',')
        base = {'gold': (255, 214, 96), 'ice': (150, 226, 255), 'violet': (196, 92, 255)}[col]
        return rune_circle(int(ph), base, star=bool(int(star)))
    if k == 'sparkle':
        return sparkle(int(v))
    if k == 'pillar':
        return pillar(v == 'broken')
    if k == 'taint':
        col, ph = v.split(',')
        return taint_pool(int(ph), col == 'green')
    if k == 'pumpkin':
        lit, n = v.split(',')
        return pumpkin(lit == '1', int(n))
    raise KeyError(name)


# --------------------------------------------------------------------------------------------------------------- recolour
RAMPS = {
    'marble': ([(70, 66, 96), (150, 152, 178), (214, 216, 232), (250, 248, 246)], (96, 92, 124)),
    'gold': ([(86, 54, 8), (176, 122, 24), (244, 200, 72), (255, 244, 190)], (86, 54, 8)),
    'dove': ([(120, 130, 170), (196, 206, 232), (240, 244, 255), (255, 255, 255)], (96, 106, 150)),
}


def recolour(a, ramp_name):
    ramp, outline = RAMPS[ramp_name]
    a = a.copy()
    rgb = a[..., :3].astype(float) / 255
    lum = rgb @ np.array([.299, .587, .114])
    on = a[..., 3] > 0
    lo, hi = np.percentile(lum[on], 3), np.percentile(lum[on], 97)
    t = np.clip((lum - lo) / max(hi - lo, 1e-6), 0, 1)
    h, w = lum.shape
    for y in range(h):
        for x in range(w):
            if not on[y, x]:
                continue
            r, g, b = rgb[y, x]
            hh, ss, vv = colorsys.rgb_to_hsv(r, g, b)
            if ss > .62 and vv > .65 and (hh < .17 or hh > .95):   # flames and warm gems keep their colour
                continue
            if t[y, x] < .1:
                a[y, x, :3] = outline
                continue
            pos = t[y, x] * (len(ramp) - 1)
            i = min(int(pos), len(ramp) - 2)
            f = pos - i
            a[y, x, :3] = [int(round(ramp[i][c] * (1 - f) + ramp[i + 1][c] * f)) for c in range(3)]
    return a


# ----------------------------------------------------------------------------------------------------------------- the list
# (biome, name, source, recolour, kind, blocks, light (level, colour) or None, minimap key or None)
# source: 'c:<file>' source C object, 'd:<id>' source D item, 'e:<cell>' source E tree, 'own:<spec>' own art; several phases
# of an animated own item: 'own:rune:gold,%d,0' with the %d replaced by the phase.
S = []


def add(biome, name, src, recolour=None, kind='static', blocks=False, light=None, mm=None, phases=1, ms=0):
    S.append(dict(biome=biome, name=name, src=src, recolour=recolour, kind=kind, blocks=blocks, light=light, mm=mm,
                  phases=phases, ms=ms))


# --- celestial
for i, (sid, nm, lt) in enumerate((
        (41665, 'Starlight crystal cluster', (4, C_PALE)), (41666, 'White crystal cluster', None), (41668, 'Frosted crystal cluster', None),
        (41674, 'Sapphire crystal cluster', (4, C_ICE)), (41677, 'Amethyst crystal cluster', (3, C_VIOLET)),
        (41725, 'Glacial crystal cluster', None), (41727, 'Pale crystal cluster', None), (41733, 'Azure crystal cluster', (3, C_ICE)),
        (41738, 'Moonstone crystal cluster', None))):
    add('celestial', nm, 'd:%d' % sid, None, 'light' if lt else 'static', True, lt, 'crystal')
add('celestial', 'Golden brazier', 'd:40935', 'gold', 'light', True, (5, C_GOLD), 'gold')
add('celestial', 'Marble angel statue', 'c:sp_10', 'marble', 'static', True, None, 'marble')
add('celestial', 'Marble stele', 'c:sp_11', 'marble', 'static', True, None, 'marble')
add('celestial', 'Marble cross stele', 'c:sp_12', 'marble', 'static', True, None, 'marble')
add('celestial', 'Broken marble stele', 'c:sp_14', 'marble', 'static', True, None, 'marble')
add('celestial', 'Marble fountain', 'c:sp_01', 'marble', 'static', True, None, 'marble')
add('celestial', 'Marble shrine', 'c:sp_02', 'marble', 'static', True, None, 'marble')
add('celestial', 'Marble lectern', 'c:se_11', 'marble', 'static', True, None, 'marble')
add('celestial', 'Marble sarcophagus', 'c:sp_05', 'marble', 'static', True, None, 'marble')
add('celestial', 'Narrow marble sarcophagus', 'c:sp_06', 'marble', 'static', True, None, 'marble')
add('celestial', 'Golden candelabra', 'c:sp_16', 'gold', 'light', False, (4, C_GOLD), None)
add('celestial', 'Golden lamp post', 'c:sp_17', 'gold', 'light', True, (6, C_GOLD), 'gold')
add('celestial', 'Golden basin', 'c:sp_20', 'gold', 'light', True, (4, C_PALE), 'gold')
add('celestial', 'Golden candle', 'c:sp_19', 'gold', 'light', False, (3, C_GOLD), None)
add('celestial', 'Doves', 'c:sp_07', 'dove', 'static', False, None, None)
add('celestial', 'Flock of doves', 'c:sp_00', 'dove', 'static', False, None, None)
add('celestial', 'Marble signpost', 'c:sp_22', 'marble', 'static', False, None, None)
add('celestial', 'Marble pillar', 'own:pillar:whole', None, 'static', True, None, 'marble')
add('celestial', 'Broken marble pillar', 'own:pillar:broken', None, 'static', True, None, 'marble')
add('celestial', 'Small cloud', 'own:cloud:1,32,22,2', None, 'static', False, None, None)
add('celestial', 'Cloud puff', 'own:cloud:2,32,26,3', None, 'static', False, None, None)
add('celestial', 'Drifting cloud', 'own:cloud:3,30,18,2', None, 'static', False, None, None)
add('celestial', 'Cloud bank', 'own:cloud:4,64,30,5', None, 'static', False, None, None)
add('celestial', 'Golden rune circle', 'own:rune:gold,%d,0', None, 'animated', False, (4, C_GOLD), None, 4, 220)
add('celestial', 'Star rune circle', 'own:rune:gold,%d,1', None, 'animated', False, (4, C_GOLD), None, 4, 220)
add('celestial', 'Azure rune circle', 'own:rune:ice,%d,0', None, 'animated', False, (4, C_ICE), None, 4, 220)
add('celestial', 'Starlight sparkle', 'own:sparkle:%d', None, 'animated', False, (2, C_WHITE), None, 4, 260)
# --- cursed
for i, nm in ((0, 'Gnarled dead tree'), (1, 'Twisted dead tree'), (2, 'Split dead tree'), (3, 'Hollow dead tree'), (4, 'Broad dead tree'),
              (5, 'Dead tree stump'), (6, 'Pale dead tree'), (8, 'Rotten dead tree'), (9, 'Fallen dead tree'), (10, 'Hollow fallen log'),
              (11, 'Thin dead tree'), (14, 'Tall dead tree')):
    add('cursed', nm, 'e:%d' % i, None, 'static', True, None, 'tree')
for f, nm, bl, lt, mm in (
        ('sp_00', 'Bats', False, None, None), ('sp_01', 'Cursed well', True, None, 'stone'), ('sp_02', 'Cursed crypt', True, None, 'stone'),
        ('sp_04', 'Scarecrow', True, None, 'wood'), ('sp_05', 'Open coffin', True, None, 'wood'), ('sp_06', 'Coffin', True, None, 'wood'),
        ('sp_07', 'Crows', False, None, None), ('sp_09', 'Pumpkin scarecrow', True, None, 'wood'),
        ('sp_10', 'Angel tombstone', True, None, 'stone'), ('sp_11', 'Round tombstone', True, None, 'stone'),
        ('sp_12', 'Cross tombstone', True, None, 'stone'), ('sp_14', 'Cracked tombstone', True, None, 'stone'),
        ('sp_15', 'Witch broom', False, None, None), ('sp_16', 'Cursed candles', False, (4, C_ORANGE), None),
        ('sp_17', 'Haunted lantern post', True, (5, C_ORANGE), 'wood'), ('sp_18', 'Witch hat', False, None, None),
        ('sp_19', 'Candle skull', False, (3, C_ORANGE), None), ('sp_20', 'Witch cauldron', True, (4, C_GREEN), 'stone'),
        ('sp_21', 'Open grave', True, None, 'stone'), ('sp_22', 'Cursed signpost', False, None, None),
        ('sp_24', 'Rotten wheelbarrow', False, None, None), ('se_00', 'Watching cauldron', True, (3, C_GREEN), 'stone'),
        ('se_02', 'Butcher table', True, None, 'wood'), ('se_10', 'Sacrificial slab', True, None, 'cloth'),
        ('se_11', 'Cursed lectern', True, None, 'wood'), ('se_12', 'Brewing table', True, None, 'wood'),
        ('se_16', 'Blood altar', True, None, 'cloth'), ('se_09', 'Skull pile', False, None, None)):
    add('cursed', nm, 'c:' + f, None, 'light' if lt else 'static', bl, lt, mm)
for i, nm in ((12, 'Skeleton remains'), (19, 'Fossil beast'), (20, 'Bone-picked carcass'), (25, 'Horned carcass')):
    add('cursed', nm, 'd:%d' % (40900 + i), None, 'static', False, None, None)
add('cursed', 'Horned bone mound', 'd:40929', None, 'static', True, None, 'bone')
add('cursed', 'Jack-o-lantern', 'own:pumpkin:1,1', None, 'light', False, (4, C_ORANGE), None)
add('cursed', 'Pumpkin patch', 'own:pumpkin:0,2', None, 'static', False, None, None)
add('cursed', 'Pumpkin', 'own:pumpkin:0,1', None, 'static', False, None, None)
add('cursed', 'Purple taint pool', 'own:taint:purple,%d', None, 'animated', False, (3, C_VIOLET), None, 4, 300)
add('cursed', 'Green taint pool', 'own:taint:green,%d', None, 'animated', False, (3, C_GREEN), None, 4, 300)
add('cursed', 'Cursed rune circle', 'own:rune:violet,%d,1', None, 'animated', False, (4, C_VIOLET), None, 4, 220)

SOURCE_OF = {'c': ('C', 'prop sheets cut to single objects'), 'd': ('D', '32 px item art'), 'e': ('E', 'dead tree sheet'),
             'own': ('own', 'drawn by gen_decor49.py')}
TREE_NATIVE = 64   # one cell of the sheet, native pixels (the file is 4x)


# ------------------------------------------------------------------------------------------------------------ source reading
def load_rgba(path):
    return np.array(Image.open(path).convert('RGBA'))


def trim(a):
    ys, xs = np.where(a[..., 3] > 0)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def source_art(spec, src_dir, phase=0):
    k, _, v = spec['src'].partition(':')
    if k == 'own':
        return own_art(v % phase if '%d' in v else v), None
    if k == 'c':
        p = os.path.join(src_dir, 'c', v + '.png')
        a = trim(load_rgba(p))
    elif k == 'd':
        p = os.path.join(src_dir, 'd', v + '.png')
        a = trim(load_rgba(p))
    elif k == 'e':
        p = os.path.join(src_dir, 'e', 'trees.png')
        sheet = load_rgba(p)[::4, ::4]
        n = int(v)
        r, c = divmod(n, 4)
        a = trim(sheet[r * TREE_NATIVE:(r + 1) * TREE_NATIVE, c * TREE_NATIVE:(c + 1) * TREE_NATIVE])
    else:
        raise KeyError(k)
    a = a.copy()
    a[a[..., 3] < 128] = 0
    a[a[..., 3] >= 128, 3] = 255
    if spec['recolour']:
        a = recolour(a, spec['recolour'])
    return a, p


def to_canvas(a, own=False):
    h, w = a.shape[:2]
    tw, th = max(1, -(-w // 32)), max(1, -(-h // 32))
    cv = np.zeros((th * 32, tw * 32, 4), np.uint8)
    if own and (h, w) == (th * 32, tw * 32):
        return cv + a, tw, th
    x0 = (tw * 32 - w) // 2
    cv[th * 32 - h:, x0:x0 + w] = a
    return cv, tw, th


def build(src_dir):
    """-> (atlas image, things rows, manifest rows, source rows, selection rows)"""
    items = []
    for n, spec in enumerate(S):
        cid = FIRST_CLIENT + n
        frames, files = [], None
        for ph in range(spec['phases']):
            a, files = source_art(spec, src_dir, ph)
            frames.append(to_canvas(a, own=spec['src'].startswith('own:')))
        tw, th = frames[0][1:]
        assert all(f[1:] == (tw, th) for f in frames), spec['name']
        items.append((cid, spec, frames, tw, th, files))
    W = max(tw * 32 * spec['phases'] for _, spec, _, tw, th, _ in items)
    H = sum(th * 32 for _, _, _, _, th, _ in items)
    atlas = np.zeros((H, W, 4), np.uint8)
    y = 0
    things, mani, srcs, sel = [], [], [], []
    for cid, spec, frames, tw, th, files in items:
        for ph, (cv, _, _) in enumerate(frames):
            atlas[y:y + th * 32, ph * tw * 32:(ph + 1) * tw * 32] = cv
        key = 'decor49_%s_%d' % (spec['biome'], cid)
        toks, dat = [], []
        if spec['blocks']:
            toks += ['bottom', 'notwalkable', 'notmoveable']
        else:
            toks += ['notmoveable']
        if spec['light']:
            toks.append('light:%d:%d' % spec['light'])
        mmc = MM[spec['mm']] if spec['mm'] else None
        if mmc is not None:
            toks.append('minimap:%d' % mmc)
        things.append([key, 'item', 'stump' if spec['blocks'] else 'decor', spec['name'], ATLAS, 0, y, tw, th, 1, spec['phases'],
                       ' '.join(toks), 'new', '', ('ms=%d' % spec['ms']) if spec['phases'] > 1 else ''])
        otb = 8197 if spec['blocks'] else 0
        top = 2 if spec['blocks'] else 0
        if spec['phases'] > 1:
            otb |= 1 << 24
        names = [t.split(':')[0] for t in toks]
        dat_flags = ' '.join(names)
        lvl, colr = spec['light'] or (0, 0)
        mani.append([cid, cid + SERVER_OFFSET, key, spec['name'], 'object', '', '%dx%d' % (tw, th), '1x1', spec['phases'],
                     spec['ms'] if spec['phases'] > 1 else 0, 0, 0, otb, top, lvl, colr, mmc if mmc is not None else '', dat_flags])
        s, what = SOURCE_OF[spec['src'].partition(':')[0]]
        sha = hashlib.sha256(np.ascontiguousarray(frames[0][0]).tobytes()).hexdigest()[:16]
        if s != 'own':   # own art needs no source line (drawn by this file)
            srcs.append([key, 'item', 'decoration source ' + s, '%s (%s) art %s' % (spec['src'].partition(':')[2], what, sha),
                         LICENCE])
        sel.append([spec['biome'], spec['src'].partition(':')[0].upper() if s != 'own' else 'own', spec['name'],
                    '%dx%d' % (tw, th), spec['kind'], int(spec['blocks'])])
        y += th * 32
    return atlas, things, mani, srcs, sel


HEAD_THINGS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id', 'extra']
HEAD_MANI = ['client_id', 'server_id', 'key', 'name', 'kind', 'piece', 'size', 'patterns', 'phases', 'frame_ms', 'speed', 'otb_group',
             'otb_flags', 'top_order', 'light_level', 'light_color', 'minimap', 'dat_flags']
HEAD_SRC = ['name', 'kind', 'pack', 'source', 'licence']
HEAD_SEL = ['biome', 'source', 'name', 'size', 'kind', 'blocks']


def csv_text(head, rows):
    b = io.StringIO()
    w = csv.writer(b, lineterminator='\n')
    w.writerow(head)
    w.writerows(rows)
    return b.getvalue()


def png_bytes(a):
    b = io.BytesIO()
    Image.fromarray(a).save(b, 'PNG', optimize=False)
    return b.getvalue()


def targets(atlas, things, mani, srcs, sel):
    png = png_bytes(atlas)
    return {
        os.path.join(ART, ATLAS + '.png'): png,
        os.path.join(ART, ATLAS + '.csv'): csv_text(HEAD_THINGS, things).encode(),
        os.path.join(ART, ATLAS + '.sums'): ('%s  %s.png\n' % (hashlib.sha256(png).hexdigest(), ATLAS)).encode(),
        os.path.join(ART, ATLAS + '_sources.csv'): csv_text(HEAD_SRC, srcs).encode(),
        OUT_SEL: csv_text(HEAD_SEL, sel).encode(),
        OUT_ITEMS: csv_text(HEAD_MANI, mani).encode(),
    }


def check_tables():
    """no sources needed: the committed tables agree with each other and with the list above"""
    errs = []
    things = list(csv.DictReader(open(os.path.join(ART, ATLAS + '.csv'), newline='')))
    mani = list(csv.DictReader(open(OUT_ITEMS, newline='')))
    srcs = list(csv.DictReader(open(os.path.join(ART, ATLAS + '_sources.csv'), newline='')))
    sel = list(csv.DictReader(open(OUT_SEL, newline='')))
    if not (len(things) == len(mani) == len(sel) == len(S) and len(srcs) == sum(1 for x in S if not x['src'].startswith('own:'))):
        errs.append('row counts differ: things %d manifest %d sources %d selection %d list %d' % (
            len(things), len(mani), len(srcs), len(sel), len(S)))
        return errs
    srcs_by = {r['name']: r for r in srcs}
    for n, (t, m, e, spec) in enumerate(zip(things, mani, sel, S)):
        cid = FIRST_CLIENT + n
        if int(m['client_id']) != cid or int(m['server_id']) != cid + SERVER_OFFSET:
            errs.append('%s: ids' % t['key'])
        if not (t['key'] == m['key'] == 'decor49_%s_%d' % (spec['biome'], cid)) or \
                (t['key'] in srcs_by) == spec['src'].startswith('own:'):
            errs.append('%s: keys differ' % t['key'])
        if t['name'] != m['name'] or t['name'] != spec['name'] or e['name'] != spec['name']:
            errs.append('%s: names differ' % t['key'])
        if ('notwalkable' in m['dat_flags'].split()) != spec['blocks'] or (int(m['otb_flags']) & 1 != 0) != spec['blocks']:
            errs.append('%s: blocking flags' % t['key'])
        if bool(spec['light']) != (int(m['light_level']) > 0) or ('light' in m['dat_flags'].split()) != bool(spec['light']):
            errs.append('%s: light flags' % t['key'])
        if spec['light'] and not 1 <= int(m['light_level']) <= 9:
            errs.append('%s: light level' % t['key'])
        if int(m['phases']) != spec['phases'] or (spec['phases'] > 1) != bool(int(m['otb_flags']) & (1 << 24)):
            errs.append('%s: phases' % t['key'])
        if (int(t['w']), int(t['h'])) != tuple(int(v) for v in m['size'].split('x')):
            errs.append('%s: size' % t['key'])
    sums = os.path.join(ART, ATLAS + '.sums')
    png = os.path.join(ART, ATLAS + '.png')
    if os.path.exists(png):
        want = open(sums).read().split()[0]
        if hashlib.sha256(open(png, 'rb').read()).hexdigest() != want:
            errs.append('atlas does not match the sums')
        atlas = np.array(Image.open(png).convert('RGBA'))
        for t in things:
            w, h, ph = int(t['w']) * 32, int(t['h']) * 32, int(t['phases'])
            cell = atlas[int(t['y']):int(t['y']) + h, :w * ph]
            if not (cell[..., 3] > 0).any():
                errs.append('%s: empty art' % t['key'])
    return errs


def main(argv):
    if not argv or argv[0] != 'build':
        print(__doc__)
        return 1
    check = '--check' in argv
    src = argv[argv.index('--src') + 1] if '--src' in argv else None
    if not src:
        errs = check_tables()
        for e in errs:
            print('FAIL', e)
        print('decor49: %d items, tables %s' % (len(S), 'agree' if not errs else 'DISAGREE'))
        return 1 if errs else 0
    out = targets(*build(src))
    bad = 0
    for path, data in out.items():
        if check:
            if not os.path.exists(path) or open(path, 'rb').read() != data:
                print('differs:', os.path.relpath(path, REPO))
                bad += 1
        else:
            with open(path, 'wb') as fh:
                fh.write(data)
            print('wrote', os.path.relpath(path, REPO))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
