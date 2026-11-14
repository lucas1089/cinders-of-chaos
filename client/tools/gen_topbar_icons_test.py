#!/usr/bin/env python3
"""Tests of client/tools/gen_topbar_icons.py: every glyph of the tree is drawn, fits its cell, differs from the others,
the atlases and the index agree, and drawing twice gives the same pixels. Needs Pillow and numpy."""
import importlib.util
import os
import re
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GEN = load(os.path.join(HERE, 'gen_topbar_icons.py'), 'gen_topbar_icons')
CHK = load(os.path.join(os.path.dirname(HERE), '..', 'tools', 'ci', 'check_topbar_tree.py'), 'check_topbar_tree')
n = 0


def check(cond, msg):
    global n
    n += 1
    if not cond:
        print('FAIL: ' + msg)
        sys.exit(1)


names = list(GEN.G.NAMES)
check(len(set(names)) == len(names), 'no glyph name twice')

# every glyph the tree and the cards use is drawn (the CI check says it too, here the atlas side)
tree = CHK.parse_tree(CHK.read(os.path.join(CHK.TOPBAR, 'topbar_tree.lua')))
cards = CHK.parse_cards(CHK.read(os.path.join(CHK.TOPBAR, 'topbar_cards.lua')))
used = set(h['glyph'] for h in tree['hubs']) | set(g for g, _ in cards['cards'].values()) | set(cards['icon_glyph'].values()) | {cards['fallback']} | {'pin'}   # pin: the mark of a pinned card (topbar_hub.lua)
check(used <= set(names), 'undrawn glyphs: %s' % sorted(used - set(names)))
check(set(names) <= used, 'a drawn glyph nobody uses: %s' % sorted(set(names) - used))

with tempfile.TemporaryDirectory() as tmp:
    first = GEN.render(tmp)
    check(first == ['glyphs_bar.png', 'glyphs_card.png', 'glyphs_mark.png'], 'three atlases')
    with tempfile.TemporaryDirectory() as tmp2:
        GEN.render(tmp2)
        for f in first:
            check(GEN.same_pixels(os.path.join(tmp, f), os.path.join(tmp2, f)), 'deterministic: ' + f)
    for kind, (cell, size) in GEN.SIZES.items():
        img = Image.open(os.path.join(tmp, 'glyphs_%s.png' % kind)).convert('RGBA')
        rows = -(-len(names) // GEN.COLS)
        check(img.size == (GEN.COLS * cell, rows * cell), '%s atlas size %s' % (kind, img.size))
        pos = GEN.slots(cell)
        seen = {}
        for name in names:
            x, y = pos[name]
            tile = np.asarray(img.crop((x, y, x + cell, y + cell)), np.uint8)
            alpha = tile[..., 3]
            body = (alpha > 128)
            check(body.sum() > size * size * 0.06, '%s/%s is drawn (%d px)' % (kind, name, body.sum()))
            ys, xs = np.nonzero(body)
            m = (cell - size) // 2
            check(xs.min() >= m - 1 and ys.min() >= m - 1 and xs.max() <= cell - m and ys.max() <= cell - m,
                  '%s/%s stays inside its %d px glyph box (margin %d)' % (kind, name, size, m))
            check(alpha[0, :].max() < 8 and alpha[-1, :].max() < 8 and alpha[:, 0].max() < 8 and alpha[:, -1].max() < 8,
                  '%s/%s: the shadow stays inside the cell' % (kind, name))
            key = bytes(tile.tobytes())
            check(key not in seen, '%s/%s looks like %s' % (kind, name, seen.get(key)))
            seen[key] = name
            # white glyph with a light ramp: the top is brighter than the bottom, the shadow is black
            solid = tile[body]
            check(np.median(solid[:, 0]) >= 170, '%s/%s: the glyph is light, ready to tint' % (kind, name))
            shadow = tile[(alpha > 0) & ~body]
            if len(shadow):
                check((shadow[:, 0] <= 40).mean() >= 0.3, '%s/%s: a part of the baked shadow is black' % (kind, name))

# the index agrees with the atlas layout
text = GEN.index_text()
for kind, (cell, size) in GEN.SIZES.items():
    block = re.search(r"%s = \{ file = 'images/glyphs_%s', cell = (\d+), glyph = (\d+), slots = \{(.*?)\} \}," % (kind, kind), text, re.S)
    check(block and int(block.group(1)) == cell and int(block.group(2)) == size, '%s index header' % kind)
    cells = dict((a, (int(b), int(c))) for a, b, c in re.findall(r'(\w+) = \{ (\d+), (\d+) \}', block.group(3)))
    check(cells == GEN.slots(cell), '%s index cells' % kind)
check(text.count('\n') > 5 and text.endswith('return ChaosTopBarGlyphs\n'), 'index text shape')

# the shipped files are the generator's output
check(GEN.check() == 0, 'the shipped atlases and index are up to date')
print('gen_topbar_icons_test: %d checks ok' % n)
