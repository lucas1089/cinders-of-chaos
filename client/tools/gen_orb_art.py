#!/usr/bin/env python3
"""Art of the liquid orbs (client/MANIFEST.md "game_shaderfx"): the round mask the orb shader fills and the bronze
ring drawn over it. Drawn here from plain geometry (no source images).

  orb_mask.png  64x64  white disc, 1 px soft edge (the shader cuts the orb by its alpha)
  orb_ring.png  76x76  dark bronze ring around the 64 px orb, lit from the upper left, four small rivets

Usage: python3 client/tools/gen_orb_art.py   (Pillow; writes into overlay/modules/game_shaderfx/images/)
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'overlay', 'modules', 'game_shaderfx', 'images')


def coverage(dist, radius):
    """alpha of a pixel whose centre is `dist` from the centre, for an edge at `radius` (1 px ramp)"""
    return max(0.0, min(1.0, radius - dist + 0.5))


def mask(size=64):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    c = (size - 1) / 2.0
    r = size / 2.0 - 0.5
    px = img.load()
    for y in range(size):
        for x in range(size):
            a = coverage(math.hypot(x - c, y - c), r)
            if a > 0:
                px[x, y] = (255, 255, 255, int(round(a * 255)))
    return img


def ring(size=76, inner=31.5, outer=37.5):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    c = (size - 1) / 2.0
    px = img.load()
    rivets = [(c + math.cos(a) * (inner + outer) / 2, c + math.sin(a) * (inner + outer) / 2)
              for a in (math.pi * 0.25, math.pi * 0.75, math.pi * 1.25, math.pi * 1.75)]
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c)
            a = coverage(d, outer) * (1.0 - coverage(d, inner - 1.0))
            if a <= 0:
                continue
            # light from the upper left on a rounded band: the band's profile and the angle to the light
            t = (d - inner) / (outer - inner)
            bulge = math.sin(max(0.0, min(1.0, t)) * math.pi)
            ang = math.atan2(y - c, x - c)
            light = 0.5 + 0.5 * math.cos(ang - math.radians(-135))
            k = 0.35 + 0.45 * bulge * (0.4 + 0.6 * light)
            col = [int(min(255, v * k)) for v in (176, 120, 62)]
            for rx, ry in rivets:
                rd = math.hypot(x - rx, y - ry)
                if rd < 1.8:
                    col = [int(min(255, v * (0.9 + 0.5 * light))) for v in (214, 170, 100)]
            # a thin dark line at the inner edge so the liquid reads as behind glass
            if d < inner + 0.8:
                col = [int(v * 0.45) for v in col]
            px[x, y] = (col[0], col[1], col[2], int(round(a * 255)))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    mask().save(os.path.join(OUT, 'orb_mask.png'))
    ring().save(os.path.join(OUT, 'orb_ring.png'))
    print('wrote', OUT)


if __name__ == '__main__':
    main()
