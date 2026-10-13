#!/usr/bin/env python3
"""Art of the character select (modules/client_chaos_charselect; client/MANIFEST.md "Character select").

Run:  python3 -I client/tools/gen_charselect_art.py [platforms DIR]
Output: client/overlay/data/images/chaos/charselect/
  class_<line>.png   40x40 class badges, the same badges as the website's class cards (website/tools/gen_site_art.py
                     `badge`, built on this folder's gen_theme_art.py glyphs), one per class line
  class_none.png     the empty badge plate (a class id the client does not know)
  platform.png       256x96 the dark stone dais the big character stands on (three designs below; `platforms DIR`
                     writes all three for a comparison, outside the repository)
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


# ---------------------------------------------------------------- the platform the big character stands on
# 256x96, the ellipse of a round platform seen from above at the client's angle; its centre is where the feet go.
# Low contrast and cool grey, so it never tints or outshines the character (owner, 2026-10-13: the orange ember glow
# made the characters look strange). Three designs were drawn and compared under the live select
# (scratchpad sheet, client/MANIFEST.md "Character select"); `platform` is the one shipped, the others are written
# only by `python3 -I client/tools/gen_charselect_art.py platforms DIR` for a comparison.
PW, PH = 256, 96


def _ellipse(cx, cy, rx, ry):
    yy, xx = np.mgrid[0:PH, 0:PW].astype(np.float32)
    return np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)


def _rgba(rgb, alpha):
    img = np.zeros((PH, PW, 4), np.float32)
    img[..., :3] = rgb
    img[..., 3] = np.clip(alpha, 0, 1) * 255
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGBA')


def _shadow(alpha=0.55):
    """the soft contact shadow under the feet"""
    d = _ellipse(PW / 2, PH / 2 + 4, PW * 0.36, PH * 0.30)
    return np.clip(1 - d, 0, 1) ** 1.3 * alpha


def platform_dais():
    """a low dark carved stone dais: top face, a lit far rim, a darker front side, a shadow"""
    top = _ellipse(PW / 2, PH * 0.44, PW * 0.42, PH * 0.34)
    side = _ellipse(PW / 2, PH * 0.44 + 9, PW * 0.42, PH * 0.34)
    yy, xx = np.mgrid[0:PH, 0:PW].astype(np.float32)
    noise = gta.fbm(PH, PW, 18, 4, 31) - 0.5
    face = np.array(gta.hexc('#2b2a2f'), np.float32)
    rgb = np.zeros((PH, PW, 3), np.float32) + face
    rgb += noise[..., None] * 22
    # carved concentric groove and a lighter rim towards the back (the light from above)
    groove = np.exp(-((top - 0.70) / 0.035) ** 2)
    rgb -= groove[..., None] * 18
    rim = np.exp(-((top - 0.97) / 0.03) ** 2) * np.clip((PH * 0.44 - yy) / (PH * 0.34), 0, 1)
    rgb += rim[..., None] * np.array(gta.hexc('#6d7079'), np.float32) * 0.55
    # the front side: the band between the top face and the lowered copy, darker
    side_band = (side <= 1.0) & (top > 1.0)
    rgb[side_band] = np.array(gta.hexc('#17161a'), np.float32) + noise[side_band][:, None] * 12
    alpha = np.where((top <= 1.0) | side_band, 0.92, 0.0)
    # contact shadow on the face where the feet stand, and a soft drop shadow outside
    contact = np.clip(1 - _ellipse(PW / 2, PH * 0.47, PW * 0.17, PH * 0.12), 0, 1) ** 1.2
    rgb *= (1 - contact * 0.45)[..., None]
    drop = np.clip(1 - _ellipse(PW / 2, PH * 0.52, PW * 0.49, PH * 0.47), 0, 1) ** 1.5 * 0.5
    a = np.maximum(alpha, drop)
    rgb = np.where(alpha[..., None] > 0, rgb, 0)
    return _rgba(rgb, a)


def platform_runes():
    """an engraved rune circle on the ground: two thin cool grey rings, rune ticks between them, a soft shadow"""
    d = _ellipse(PW / 2, PH / 2, PW * 0.44, PH * 0.38)
    yy, xx = np.mgrid[0:PH, 0:PW].astype(np.float32)
    ang = np.arctan2((yy - PH / 2) / (PH * 0.38), (xx - PW / 2) / (PW * 0.44))
    ring = np.exp(-((d - 0.97) / 0.022) ** 2) + np.exp(-((d - 0.78) / 0.018) ** 2) * 0.8
    k = 24
    tick = (np.abs(((ang / (2 * np.pi)) * k) % 1 - 0.5) < 0.08) & (d > 0.81) & (d < 0.94)
    mark = np.clip(ring + tick * 0.7, 0, 1)
    shadow = _shadow(0.5)
    a = np.maximum(shadow, mark * 0.42)
    grey = np.array(gta.hexc('#8d919b'), np.float32)
    rgb = np.where(mark[..., None] > 0.05, grey, 0)
    return _rgba(rgb, a)


def platform_shadow():
    """only a soft neutral shadow with a faint cool rim"""
    d = _ellipse(PW / 2, PH / 2, PW * 0.40, PH * 0.34)
    rim = np.exp(-((d - 0.95) / 0.05) ** 2) * 0.18
    a = np.maximum(_shadow(0.6), rim)
    rgb = np.where(rim[..., None] > 0.02, np.array(gta.hexc('#7c808a'), np.float32), 0)
    return _rgba(rgb, a)


PLATFORMS = {'dais': platform_dais, 'runes': platform_runes, 'shadow': platform_shadow}
PLATFORM = 'dais'   # the one shipped as platform.png


def gen_platform():
    save(PLATFORMS[PLATFORM](), 'platform.png')


def gen_shade():
    w, h = 64, 256
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32) / (h - 1)
    a = 0.62 + 0.18 * np.sin(yy * np.pi)
    img = np.zeros((h, w, 4), np.float32)
    img[..., :3] = np.array(gta.hexc('#0d0b0e'), np.float32)
    img[..., 3] = a * 255
    save(Image.fromarray(img.astype(np.uint8), 'RGBA'), 'shade.png')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'platforms':
        os.makedirs(sys.argv[2], exist_ok=True)
        for key, fn in PLATFORMS.items():
            fn().save(os.path.join(sys.argv[2], 'platform_%s.png' % key))
            print('wrote', os.path.join(sys.argv[2], 'platform_%s.png' % key))
        sys.exit(0)
    gen_icons()
    gen_platform()
    gen_shade()
