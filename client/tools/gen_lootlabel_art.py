#!/usr/bin/env python3
"""Loot label plates (O562): one 9-slice plate per loot label cosmetic of the server (cosmetics_config.lua, kind
"lootbeam", the `accent` colour), drawn by game_groundlabels on the ground and by game_lookpreview on the Customise
window's tiles and stage. Our own procedural art, no outside pixels.

usage: python3 -I client/tools/gen_lootlabel_art.py [--check]

Writes client/overlay/modules/game_groundlabels/images/label_<key>.png (32 x 20, image-border 7: a vertical gradient fill
of the accent, a metal frame in a hue of the set, and a corner ornament that differs by set: diamonds, brackets, studs,
cut corners, spikes, scallops) and client/overlay/modules/game_groundlabels/labelplates.lua (the accent colour of each
set -> its plate), so the 17 sets read apart at a glance. The label's text keeps the item's rarity colour. --check
rebuilds in memory and fails when a committed file differs.
"""
import colorsys
import io
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CONFIG = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'cosmetics_config.lua')
OUT = os.path.join(ROOT, 'client', 'overlay', 'modules', 'game_groundlabels')
W, H, BORDER = 32, 20, 7
ORNAMENTS = ['diamond', 'bracket', 'stud', 'cut', 'spike', 'scallop']


def sets():
    """-> [(key, accent '#rrggbbaa', name)] in the file's order"""
    text = open(CONFIG, encoding='utf-8').read()
    out = []
    for m in re.finditer(r'\{id = \d+, key = "(loot_\w+)", kind = "lootbeam".*?accent = "(#[0-9a-fA-F]{8})".*?name = "([^"]+)"', text, re.S):
        out.append((m.group(1), m.group(2).lower(), m.group(3)))
    return out


def rgb(hexs):
    return tuple(int(hexs[i:i + 2], 16) for i in (1, 3, 5))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def metal(c):
    """the frame colour: the accent's hue, pale and saturated enough to read on the dark fill"""
    h, s, v = colorsys.rgb_to_hsv(*(x / 255.0 for x in c))
    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, 0.35 + s * 0.6), 0.88)
    return (int(r * 255), int(g * 255), int(b * 255))


def plate(accent, style):
    base = rgb(accent)
    top, bot = shade(base, 1.9), shade(base, 0.55)
    frame = metal(base)
    dim = shade(frame, 0.55)
    px = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    p = px.load()
    for y in range(H):
        k = y / float(H - 1)
        col = tuple(int(top[i] * (1 - k) + bot[i] * k) for i in range(3))
        for x in range(W):
            p[x, y] = col + (240,)
    # outer frame line and an inner dim line
    for x in range(W):
        for y, c in ((0, frame), (H - 1, frame), (1, dim), (H - 2, dim)):
            p[x, y] = c + (255,)
    for y in range(H):
        for x, c in ((0, frame), (W - 1, frame), (1, dim), (W - 2, dim)):
            p[x, y] = c + (255,)

    def corners(fn):
        for cx, cy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            for dx in range(BORDER):
                for dy in range(BORDER):
                    fn(dx, dy, lambda x, y, c, cx=cx, cy=cy: p.__setitem__(
                        ((W - 1 - x) if cx else x, (H - 1 - y) if cy else y), c))

    def put_all(pts, col):
        def fn(dx, dy, put):
            if (dx, dy) in pts:
                put(dx, dy, col + (255,))
        corners(fn)

    if style == 'diamond':
        put_all({(2, 2), (3, 2), (2, 3), (1, 3), (3, 3), (2, 4), (3, 4), (4, 3)}, frame)
        put_all({(3, 3)}, shade(frame, 1.25))
    elif style == 'bracket':
        put_all({(2, 2), (3, 2), (4, 2), (5, 2), (2, 3), (2, 4), (2, 5)}, frame)
        put_all({(3, 3)}, dim)
    elif style == 'stud':
        put_all({(3, 3), (4, 3), (3, 4), (4, 4)}, frame)
        put_all({(3, 3)}, shade(frame, 1.3))
        put_all({(5, 3), (3, 5)}, dim)
    elif style == 'cut':
        pts = {(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (0, 2)}
        for cx, cy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            for dx, dy in pts:
                p[((W - 1 - dx) if cx else dx, (H - 1 - dy) if cy else dy)] = (0, 0, 0, 0)

        def fn(dx, dy, put):
            if (dx, dy) in {(3, 0), (2, 1), (1, 2), (0, 3)}:
                put(dx, dy, frame + (255,))
            if (dx, dy) == (3, 3):
                put(dx, dy, shade(frame, 1.2) + (255,))
        corners(fn)
    elif style == 'spike':
        put_all({(2, 2), (3, 3), (4, 4), (5, 5), (2, 3), (3, 2), (3, 4), (4, 3)}, frame)
        put_all({(6, 6), (1, 1)}, dim)
    else:  # scallop
        put_all({(2, 3), (3, 2), (4, 2), (5, 3), (2, 4), (2, 5), (3, 5), (4, 4)}, frame)
        put_all({(3, 3), (4, 3), (3, 4)}, dim)
    # a notch of light in the middle of the top and bottom frame lines (the plate's own mark)
    for x in range(W // 2 - 2, W // 2 + 2):
        p[x, 0] = shade(frame, 1.25) + (255,)
        p[x, H - 1] = shade(frame, 0.8) + (255,)
    return px


def build():
    files, rows = {}, []
    for i, (key, accent, name) in enumerate(sets()):
        im = plate(accent, ORNAMENTS[i % len(ORNAMENTS)])
        b = io.BytesIO()
        im.save(b, format='PNG', optimize=False)
        files['label_%s.png' % key[5:]] = b.getvalue()
        rows.append((accent, key[5:], name))
    lua = ['-- Generated by client/tools/gen_lootlabel_art.py from server/data/scripts/chaos/cosmetics_config.lua (loot label',
           '-- accents). Do not edit. The accent colour of each loot label set -> its 9-slice plate (images/label_<plate>.png,',
           '-- %d x %d, image-border %d); read by groundlabelslogic.lua GL.plateFor.' % (W, H, BORDER),
           'GroundLabelPlates = {', '  size = { %d, %d }, border = %d,' % (W, H, BORDER), '  plates = {']
    for accent, plate_name, name in rows:
        lua.append('    ["%s"] = "%s", -- %s' % (accent, plate_name, name))
    lua += ['  },', '}', '']
    files['../labelplates.lua'] = '\n'.join(lua).encode()
    return files


def main():
    check = '--check' in sys.argv
    files = build()
    bad = 0
    img_dir = os.path.join(OUT, 'images')
    os.makedirs(img_dir, exist_ok=True)
    for name, data in files.items():
        path = os.path.normpath(os.path.join(img_dir, name))
        old = open(path, 'rb').read() if os.path.exists(path) else None
        if old != data:
            if check:
                print('stale: %s' % os.path.relpath(path, ROOT))
                bad += 1
            else:
                open(path, 'wb').write(data)
    if check:
        print('gen_lootlabel_art: %d file(s), %d stale' % (len(files), bad))
        return 1 if bad else 0
    print('gen_lootlabel_art: wrote %d file(s)' % len(files))
    return 0


if __name__ == '__main__':
    sys.exit(main())
