#!/usr/bin/env python3
"""Art of the liquid orbs (client/MANIFEST.md "game_shaderfx"): the round mask the orb shader fills and the bronze
ring drawn over it. Drawn here from plain geometry (no source images).

One mask and one ring per orb size (shaderfxlogic.lua ORB_SIZES: 76, 150, 190 px; the liquid 64 of 76 of that),
each at twice the size it is drawn. The first art was one 64 px mask and one 76 px ring for every size, so the
medium and large orbs (150 and 190 px, medium the default) drew them stretched about 2x and 2.5x: a blurred, stepped
ring and square rivets (owner screenshot 2026-10-21). At 2x a drawn pixel is the plain average of 2x2 texels (the
widget draws with image-smooth), and a UI scaled 2x draws it 1:1.

  orb_mask_<L>.png  2L x 2L  white disc, a soft edge of one drawn pixel (the shader cuts the orb by its alpha)
  orb_ring_<S>.png  2S x 2S  dark bronze ring around the liquid, lit from the upper left, four small rivets
  (S the orb size, L its liquid: round(S * 64 / 76))

Usage: python3 client/tools/gen_orb_art.py [--check]   (Pillow; writes into overlay/modules/game_shaderfx/images/)
  --check: the committed images have the pixels the generator draws (exit 1 when not, or when a stray orb image is
  left); nothing is written.
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

# the ring of the first 76 px orb, in drawn pixels of that size; every size scales it
BASE_SIZE = 76
BASE_INNER = 31.5
BASE_OUTER = 37.5
BASE_RIVET = 1.8
BASE_LINE = 0.8


def orb_sizes(text):
    """the orb sizes of shaderfxlogic.lua's ORB_SIZES"""
    m = re.search(r'L\.ORB_SIZES = \{(.*?)\n\}', text, re.S)
    return [int(v) for v in re.findall(r'size = (\d+)', m.group(1))] if m else []


def liquid_size(size):
    """as shaderfxlogic.lua L.orbSize: math.floor(size * 64 / 76 + 0.5)"""
    return int(math.floor(size * 64 / 76 + 0.5))


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


def ring(size):
    """the ring, `size` texels (a drawn orb of size / SCALE)"""
    k = size / float(BASE_SIZE)
    inner, outer = BASE_INNER * k, BASE_OUTER * k
    rivet, line = BASE_RIVET * k, BASE_LINE * k
    ramp = SCALE  # one drawn pixel
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    c = (size - 1) / 2.0
    px = img.load()
    rivets = [(c + math.cos(a) * (inner + outer) / 2, c + math.sin(a) * (inner + outer) / 2)
              for a in (math.pi * 0.25, math.pi * 0.75, math.pi * 1.25, math.pi * 1.75)]
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c)
            a = coverage(d, outer, ramp) * (1.0 - coverage(d, inner - k, ramp))
            if a <= 0:
                continue
            # light from the upper left on a rounded band: the band's profile and the angle to the light
            t = (d - inner) / (outer - inner)
            bulge = math.sin(max(0.0, min(1.0, t)) * math.pi)
            ang = math.atan2(y - c, x - c)
            light = 0.5 + 0.5 * math.cos(ang - math.radians(-135))
            kk = 0.35 + 0.45 * bulge * (0.4 + 0.6 * light)
            col = [min(255.0, v * kk) for v in (176, 120, 62)]
            # rivets: round, with a soft edge (they were hard 3x3 blocks, stretched to squares)
            for rx, ry in rivets:
                rc = coverage(math.hypot(x - rx, y - ry), rivet, ramp)
                if rc > 0:
                    head = [min(255.0, v * (0.9 + 0.5 * light)) for v in (214, 170, 100)]
                    col = [b + (h - b) * rc for b, h in zip(col, head)]
            # a thin dark line at the inner edge so the liquid reads as behind glass
            dark = coverage(d, inner + line, ramp)
            col = [v * (1.0 - 0.55 * dark) for v in col]
            px[x, y] = (int(col[0]), int(col[1]), int(col[2]), int(round(a * 255)))
    return img


def art():
    """file name -> image, for every orb size"""
    sizes = orb_sizes(open(LOGIC, encoding='utf-8').read())
    if not sizes:
        raise SystemExit('gen_orb_art: no ORB_SIZES in ' + LOGIC)
    out = {}
    for s in sizes:
        out['orb_ring_%d.png' % s] = ring(s * SCALE)
        out['orb_mask_%d.png' % liquid_size(s)] = mask(liquid_size(s) * SCALE)
    return out


def check(images):
    bad = []
    for name, img in sorted(images.items()):
        path = os.path.join(OUT, name)
        if not os.path.exists(path):
            bad.append(name + ': missing')
            continue
        have = Image.open(path).convert('RGBA')
        if have.size != img.size or have.tobytes() != img.tobytes():
            bad.append(name + ': differs from the generator')
    for name in sorted(os.listdir(OUT)):
        if name.startswith('orb_') and name.endswith('.png') and name not in images:
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
