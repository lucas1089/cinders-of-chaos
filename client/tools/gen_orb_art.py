#!/usr/bin/env python3
"""Art of the liquid orbs (client/MANIFEST.md "game_shaderfx"): the round mask the orb shader fills. Drawn here from
plain geometry (no source images). The ring drawn over the mask comes from import_hud_kit.py (the purchased painted
pack, docs/CREDITS.md); this tool only checks that every orb size has its ring at 2x.

One mask and one ring per orb size (shaderfxlogic.lua ORB_SIZES: 76, 150, 190 px; the liquid 50 of 76 of that, the
opening of the ring), each at twice the size it is drawn. At 2x a drawn pixel is the plain average of 2x2 texels (the
widget draws with image-smooth), and a UI scaled 2x draws it 1:1.

  orb_mask_<L>.png  2L x 2L  white disc, a soft edge of one drawn pixel (the shader cuts the orb by its alpha)
  orb_ring_<S>.png  2S x 2S  made by import_hud_kit.py (S the orb size, L its liquid: round(S * 50 / 76))

Usage: python3 client/tools/gen_orb_art.py [--check]   (Pillow; writes into overlay/modules/game_shaderfx/images/)
  --check: the committed masks have the pixels the generator draws and every ring exists at 2S x 2S (exit 1 when
  not, or when a stray orb image is left); nothing is written.
"""
import math
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.join(os.path.dirname(HERE), 'overlay', 'modules', 'game_shaderfx')
OUT = os.path.join(MODULE, 'images')
LOGIC = os.path.join(MODULE, 'shaderfxlogic.lua')
SCALE = 2  # texels per drawn pixel


def orb_sizes(text):
    """the orb sizes of shaderfxlogic.lua's ORB_SIZES"""
    m = re.search(r'L\.ORB_SIZES = \{(.*?)\n\}', text, re.S)
    return [int(v) for v in re.findall(r'size = (\d+)', m.group(1))] if m else []


def liquid_size(size):
    """as shaderfxlogic.lua L.orbSize: math.floor(size * 50 / 76 + 0.5)"""
    return int(math.floor(size * 50 / 76 + 0.5))


def coverage(dist, radius, ramp=1.0):
    """alpha of a pixel whose centre is `dist` from the centre, for an edge at `radius` (a ramp `ramp` texels wide)"""
    return max(0.0, min(1.0, (radius - dist) / ramp + 0.5))


def mask(size):
    """the liquid's mask, `size` texels (a drawn liquid of size / SCALE)"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    c = (size - 1) / 2.0
    r = size / 2.0 - 0.5 * SCALE
    px = img.load()
    for y in range(size):
        for x in range(size):
            a = coverage(math.hypot(x - c, y - c), r, SCALE)
            if a > 0:
                px[x, y] = (255, 255, 255, int(round(a * 255)))
    return img


def art():
    """file name -> image, for every orb size"""
    sizes = orb_sizes(open(LOGIC, encoding='utf-8').read())
    if not sizes:
        raise SystemExit('gen_orb_art: no ORB_SIZES in ' + LOGIC)
    out = {}
    for s in sizes:
        out['orb_mask_%d.png' % liquid_size(s)] = mask(liquid_size(s) * SCALE)
    return out


def check(images):
    bad = []
    rings = set()
    for s in orb_sizes(open(LOGIC, encoding='utf-8').read()):
        name = 'orb_ring_%d.png' % s
        rings.add(name)
        path = os.path.join(OUT, name)
        if not os.path.exists(path):
            bad.append(name + ': missing (python3 -I client/tools/import_hud_kit.py <pack-dir>)')
        elif Image.open(path).size != (s * SCALE, s * SCALE):
            bad.append(name + ': not %d x %d' % (s * SCALE, s * SCALE))
    for name, img in sorted(images.items()):
        path = os.path.join(OUT, name)
        if not os.path.exists(path):
            bad.append(name + ': missing')
            continue
        have = Image.open(path).convert('RGBA')
        if have.size != img.size or have.tobytes() != img.tobytes():
            bad.append(name + ': differs from the generator')
    for name in sorted(os.listdir(OUT)):
        if name.startswith('orb_') and name.endswith('.png') and name not in images and name not in rings:
            bad.append(name + ': not made by the generator (left over)')
    return bad


def main(argv):
    images = art()
    if '--check' in argv:
        bad = check(images)
        for b in bad:
            print('gen_orb_art --check:', b)
        if bad:
            print('run: python3 client/tools/gen_orb_art.py')
            return 1
        print('gen_orb_art --check: %d images up to date' % len(images))
        return 0
    os.makedirs(OUT, exist_ok=True)
    for name, img in sorted(images.items()):
        img.save(os.path.join(OUT, name))
    print('wrote', len(images), 'images to', OUT)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
