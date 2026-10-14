#!/usr/bin/env python3
"""Art of the character select (modules/client_chaos_charselect; client/MANIFEST.md "Character select").

Run:  python3 -I client/tools/gen_charselect_art.py [platforms DIR]
Output: client/overlay/data/images/chaos/charselect/
  class_<line>.png   40x40 class badges, the same badges as the website's class cards (website/tools/gen_site_art.py
                     `badge`, built on this folder's gen_theme_art.py glyphs), one per class line
  class_none.png     the empty badge plate (a class id the client does not know)
  platform.png       41x41 sprite pixels, the stone dais the big character stands on, in the sprites' own
                     projection, centred on its feet point; platform_l.png 49x49 and platform_xl.png 57x57 the same
                     dais for wider bodies (three designs below; `platforms DIR` writes all three for a comparison,
                     outside the repository)
  hover_shadow.png   22x8 sprite pixels, the shadow under a flying character
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
# Drawn in sprite pixels and in the sprites' own projection (owner, 2026-10-13: on the first dais, a flat ellipse
# seen from a low camera, the characters stood at the wrong angle). The game looks straight down on the ground and
# draws height up and to the left: a stock block's top face is a plain square, its walls go down and right at 45
# degrees, the light comes from the upper left (lit top and left edges, darker lower and right ones) and a dithered
# shadow lines its lower right base. So the platform's top face is a true circle or octagon seen from above, its
# thickness is the same face copied one pixel down and right per pixel of height, and its shadow is a checker of
# dark pixels along that lower right base. Our own art, no stock pixels.
# The client draws it at T / 32 (2x, 3x, 4x) without smoothing, so its pixels match the character's.
# Three sizes, so a wide body gets a wider dais (SIZES; CharSelectCore.PLATFORMS in charselect_core.lua names the
# same, `check_core` keeps the two the same). Three designs were compared under the live select (client/MANIFEST.md
# "Character select"); `PLATFORM` is the one shipped, `python3 -I client/tools/gen_charselect_art.py platforms DIR`
# writes all three outside the repository.
SIZES = [(19, 'platform'), (23, 'platform_l'), (27, 'platform_xl')]   # lower step radius, image
PS = PF = PR = 0     # set by _size: canvas, the centre of the top face (PF, PF), the lower step's radius


def _size(r):
    global PS, PF, PR
    PR, PF, PS = r, r + 1, 2 * r + 3
STONE = {'face': (60, 61, 68), 'lit': (90, 91, 100), 'lip': (74, 75, 83), 'wall_r': (44, 45, 51),
         'wall_d': (34, 35, 40), 'base': (25, 25, 29), 'groove': (40, 41, 47)}


def _grid():
    yy, xx = np.mgrid[0:PS, 0:PS].astype(np.float32)
    return xx + 0.5, yy + 0.5


def _circle(cx, cy, r):
    xx, yy = _grid()
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r


def _octagon(cx, cy, r):
    xx, yy = _grid()
    dx, dy = np.abs(xx - cx), np.abs(yy - cy)
    return (dx <= r) & (dy <= r) & (dx + dy <= r * 1.414)


def _shift(m, k):
    """m moved k pixels down and right"""
    out = np.zeros_like(m)
    if k == 0:
        return m.copy()
    out[k:, k:] = m[:-k, :-k]
    return out


def _noise(seed):
    """per-pixel stone mottling: fine grain plus a softer patch noise, -1..1"""
    rs = np.random.RandomState(seed)
    fine = rs.uniform(-1, 1, (PS, PS))
    coarse = rs.uniform(-1, 1, (PS // 4 + 2, PS // 4 + 2))
    coarse = np.kron(coarse, np.ones((4, 4)))[:PS, :PS]
    k = np.array([1, 2, 1], np.float32) / 4
    for ax in (0, 1):
        coarse = np.apply_along_axis(lambda v: np.convolve(v, k, 'same'), ax, coarse)
    return (fine * 0.45 + coarse * 0.8).astype(np.float32)


class Slab:
    def __init__(self, seed):
        self.rgb = np.zeros((PS, PS, 3), np.float32)
        self.alpha = np.zeros((PS, PS), np.float32)
        self.solid = np.zeros((PS, PS), bool)
        self.noise = _noise(seed)

    def paint(self, mask, rgb, grain=6.0):
        self.rgb[mask] = np.array(rgb, np.float32) + self.noise[mask][:, None] * grain
        self.alpha[mask] = 1.0
        self.solid |= mask

    def block(self, top, height, centre):
        """a slab whose top face is `top`, `height` pixels thick: walls down and right, lit from the upper left;
        returns the top face"""
        body = top.copy()
        for k in range(1, height + 1):
            body |= _shift(top, k)
        wall = body & ~top
        if wall.any():
            xx, yy = _grid()
            cx, cy = centre
            # the wall facing right is lit a little more than the one facing down (the light: upper left, above)
            ang = np.arctan2(yy - cy - height / 2, xx - cx - height / 2)
            facing_right = np.cos(ang) > np.sin(ang)
            self.paint(wall & facing_right, STONE['wall_r'], 5)
            self.paint(wall & ~facing_right, STONE['wall_d'], 5)
            base = body & ~np.roll(np.roll(body, -1, 0), -1, 1)   # no body pixel down and right of it
            self.paint(base & wall, STONE['base'], 3)
        self.paint(top, STONE['face'])
        # edges of the top face: lit along the top and left, a lighter lip where it meets the walls
        up = np.roll(top, 1, 0)
        left = np.roll(top, 1, 1)
        down = np.roll(top, -1, 0)
        right = np.roll(top, -1, 1)
        self.paint(top & (~up | ~left), STONE['lit'], 4)
        self.paint(top & (~down | ~right) & up & left, STONE['lip'], 4)
        return top

    def groove(self, mask):
        """a carved line: dark, its lower right edge catching the light (the light falls in from the upper left)"""
        face = self.solid.copy()
        self.paint(mask & face, STONE['groove'], 3)
        light = _shift(mask, 1) & ~mask & face
        self.paint(light, STONE['lip'], 3)

    def shadow(self, footprint, reach=2):
        """the game's dithered shadow along the lower right base, and a few checker pixels under the feet"""
        shade = np.zeros_like(footprint)
        for k in range(1, reach + 1):
            shade |= _shift(footprint, k)
        shade &= ~self.solid
        xx, yy = _grid()
        checker = ((xx - 0.5 + yy - 0.5) % 2) == 0
        self.alpha[shade] = np.where(checker[shade], 0.62, 0.30)
        self.rgb[shade] = 0
        xx, yy = _grid()
        feet = (((xx - PF - 1) / 7.5) ** 2 + ((yy - PF - 0.5) / 3.2) ** 2 <= 1) & self.solid & checker
        self.rgb[feet] *= 0.8

    def ground_shadow(self, footprint):
        """a faint ground shadow one pixel all around the footprint, darker (dithered) along its lower right base, and
        a few checker pixels under the feet"""
        ring = footprint.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ring |= np.roll(np.roll(footprint, dy, 0), dx, 1)
        ring &= ~self.solid
        xx, yy = _grid()
        checker = ((xx - 0.5 + yy - 0.5) % 2) == 0
        base = _shift(footprint, 1) & ring
        self.alpha[ring] = 0.18
        self.alpha[base] = np.where(checker[base], 0.55, 0.30)
        self.rgb[ring] = 0
        feet = (((xx - PF) / 7.5) ** 2 + ((yy - PF) / 3.2) ** 2 <= 1) & self.solid & checker
        self.rgb[feet] *= 0.8

    def image(self):
        img = np.zeros((PS, PS, 4), np.float32)
        img[..., :3] = self.rgb
        img[..., 3] = self.alpha * 255
        return Image.fromarray(np.clip(img + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def _ring(cx, cy, r, w=1.0):
    xx, yy = _grid()
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    return np.abs(d - r) <= w / 2


def platform_slab():
    """a round stone slab three pixels thick with one carved ring"""
    s = Slab(7)
    top = _circle(PF, PF, PR)
    s.block(top, 3, (PF, PF))
    s.groove(_ring(PF, PF, PR - 5))
    s.shadow(_shift(top, 3))
    return s.image()


GLYPHS = [  # 3x4 rune marks, our own
    ['x.x', '.x.', 'x.x', '.x.'], ['xx.', 'x..', 'xx.', 'x..'], ['.x.', 'xxx', '.x.', '.x.'],
    ['x..', 'xx.', 'x.x', 'x..'], ['xxx', '..x', '.x.', 'x..'], ['x.x', 'xxx', 'x.x', '...']]


def platform_runes():
    """a flat round rune slab one pixel thick: two carved rings and a ring of carved runes between them"""
    s = Slab(11)
    top = _circle(PF, PF, PR)
    s.block(top, 1, (PF, PF))
    marks = _ring(PF, PF, PR - 3) | _ring(PF, PF, PR - 10)
    n = 10
    for i in range(n):
        a = 2 * np.pi * i / n - np.pi / 2
        gx = int(round(PF + np.cos(a) * (PR - 6.5) - 1.5))
        gy = int(round(PF + np.sin(a) * (PR - 6.5) - 2))
        for yy, row in enumerate(GLYPHS[i % len(GLYPHS)]):
            for xx, ch in enumerate(row):
                if ch == 'x':
                    marks[gy + yy, gx + xx] = True
    s.groove(marks)
    s.shadow(_shift(top, 1))
    return s.image()


def platform_octagon():
    """a two-step octagonal dais, both steps centred on the feet point (an equal rim on every side, seen from above),
    each one pixel thick (the height cue down and right, the light from the upper left), a faint ground shadow one
    pixel all around it and darker along its lower right base. Its whole silhouette is centred on the feet point within
    half a pixel (the wall adds one pixel down and right): `silhouette_centre`, checked by `check_core`. The first
    version had its top step 2 pixels up and left of its lower step and 2-pixel walls and a 2-pixel shadow down and
    right: the dais read 3.5 pixels down and right of the feet (owner, 2026-10-13: "still misaligned")."""
    s = Slab(5)
    low = _octagon(PF, PF, PR)
    s.block(low, 1, (PF, PF))
    s.groove(_octagon(PF, PF, PR - 2) & ~_octagon(PF, PF, PR - 3))
    top = _octagon(PF, PF, PR - 6)
    s.block(top, 1, (PF, PF))
    s.ground_shadow(low | _shift(low, 1))
    return s.image()


def silhouette_centre(img):
    """the centre of the box around every visible pixel (shadow included), in pixel coordinates (a pixel i spans
    i..i+1), x and y"""
    a = np.asarray(img)[..., 3] > 0
    ys, xs = np.nonzero(a)
    return (xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2


PLATFORMS = {'slab': platform_slab, 'runes': platform_runes, 'octagon': platform_octagon}
PLATFORM = 'octagon'   # the one shipped as platform.png


def check_core():
    """CharSelectCore.PLATFORMS must name these sizes and centres"""
    core = open(os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_charselect',
                             'charselect_core.lua')).read()
    for r, name in SIZES:
        _size(r)
        want = "{ r = %d, size = %d, feet = %d, image = '%s' }" % (r, PS, PF, name)
        if want not in core:
            sys.exit('charselect_core.lua must list: ' + want)
        # the feet point (the top face's centre) on the centre of the whole silhouette, shadow included
        img = PLATFORMS[PLATFORM]()
        cx, cy = silhouette_centre(img)
        box = Image.fromarray((np.asarray(img)[..., 3] > 0).astype(np.uint8)).getbbox()
        if box != (0, 0, PS, PS):
            # charselect_core_test.lua checks the feet against the image size: the silhouette must fill the canvas
            sys.exit('%s: the silhouette %s does not fill the canvas %dx%d' % (name, box, PS, PS))
        if abs(cx - PF) > 0.5 or abs(cy - PF) > 0.5:
            sys.exit('%s: the feet point (%d, %d) is not the silhouette centre (%.1f, %.1f)' % (name, PF, PF, cx, cy))
    if 'C.SHADOW = { w = %d, h = %d }' % SHADOW not in core:
        sys.exit('charselect_core.lua must say: C.SHADOW = { w = %d, h = %d }' % SHADOW)


def gen_platform():
    check_core()
    for r, name in SIZES:
        _size(r)
        save(PLATFORMS[PLATFORM](), name + '.png')


# the shadow of a flying character on the top face: a dark ellipse in sprite pixels, its rim dithered as the game's
# shadows are (CharSelectCore.SHADOW)
SHADOW = (22, 8)


def hover_shadow():
    w, h = SHADOW
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xx, yy = xx + 0.5 - w / 2, yy + 0.5 - h / 2
    outer = (xx / (w / 2)) ** 2 + (yy / (h / 2)) ** 2 <= 1
    inner = (xx / (w / 2 - 3)) ** 2 + (yy / (h / 2 - 1.4)) ** 2 <= 1
    checker = ((np.floor(xx + w / 2) + np.floor(yy + h / 2)) % 2) == 0
    a = np.where(inner, 0.5, np.where(outer & checker, 0.4, np.where(outer, 0.16, 0.0)))
    img = np.zeros((h, w, 4), np.float32)
    img[..., :3] = 8
    img[..., 3] = a * 255
    return Image.fromarray(np.clip(img + 0.5, 0, 255).astype(np.uint8), 'RGBA')


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
        _size(SIZES[0][0])
        for key, fn in PLATFORMS.items():
            fn().save(os.path.join(sys.argv[2], 'platform_%s.png' % key))
            print('wrote', os.path.join(sys.argv[2], 'platform_%s.png' % key))
        sys.exit(0)
    gen_icons()
    gen_platform()
    save(hover_shadow(), 'hover_shadow.png')
    gen_shade()
