#!/usr/bin/env python3
"""Art of the character select (modules/client_chaos_charselect; client/MANIFEST.md "Character select").

Run:  python3 -I client/tools/gen_charselect_art.py
Output: client/overlay/data/images/chaos/charselect/
  class_<line>.png   40x40 class badges, the same badges as the website's class cards (website/tools/gen_site_art.py
                     `badge`, built on this folder's gen_theme_art.py glyphs), one per class line
  class_none.png     the empty badge plate (a class id the client does not know)
  pedestal.png       256x96 ember glow the big character stands on
  shade.png          64x256 dark vertical fade behind the character cards (stretched to the column)
Needs Pillow + numpy. Deterministic.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(REPO, 'client', 'overlay', 'data', 'images', 'chaos', 'charselect')
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'website', 'tools'))
import gen_theme_art as gta  # noqa: E402
import gen_site_art as site  # noqa: E402  (the class badges of the website's class cards)

ICON = 40


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    print('wrote', os.path.relpath(os.path.join(OUT, name), REPO), img.size)


def gen_icons():
    for name, _ in site.CLASSES:
        save(site.badge(name, ICON), 'class_%s.png' % name)
    plate = gta.badge_plate(False).crop((10, 10, gta.N - 10, gta.N - 10))
    save(plate.resize((ICON, ICON), Image.LANCZOS), 'class_none.png')


def gen_pedestal():
    w, h = 256, 96
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    glow = np.clip(1 - d, 0, 1) ** 1.6
    ring = np.exp(-((d - 0.72) / 0.07) ** 2) * 0.55
    a = np.clip(glow * 0.75 + ring, 0, 1)
    img = np.zeros((h, w, 4), np.float32)
    ember = np.array(gta.hexc('#e8742a'), np.float32)
    gold = np.array(gta.hexc('#f6cf72'), np.float32)
    mix = np.clip(glow, 0, 1)[..., None]
    img[..., :3] = ember * (1 - mix) + gold * mix
    img[..., 3] = a * 200
    save(Image.fromarray(img.astype(np.uint8), 'RGBA'), 'pedestal.png')


def gen_shade():
    w, h = 64, 256
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32) / (h - 1)
    a = 0.62 + 0.18 * np.sin(yy * np.pi)
    img = np.zeros((h, w, 4), np.float32)
    img[..., :3] = np.array(gta.hexc('#0d0b0e'), np.float32)
    img[..., 3] = a * 255
    save(Image.fromarray(img.astype(np.uint8), 'RGBA'), 'shade.png')


if __name__ == '__main__':
    gen_icons()
    gen_pedestal()
    gen_shade()
