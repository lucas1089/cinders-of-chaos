#!/usr/bin/env python3
"""Art of the card item tooltip (game_itemtooltip, O422): the round icon frame, the glow and the diamond ornament.

usage: python3 -I client/tools/gen_tooltip_art.py [OUTDIR]
       python3 -I client/tools/gen_tooltip_art.py --check   (draws into a temporary folder, fails when a shipped file differs)
       default OUTDIR: client/overlay/modules/game_itemtooltip/images

Files (all white or near white, the client tints them with image-color in the item's rarity colour):
  ring.png     52x52  a 2 px ring, soft edge
  disc.png     52x52  the dark disc behind the item icon (drawn as it is, no tint)
  glow.png     64x40  a radial glow, alpha only, stretched over the top of the card
  diamond.png  11x11  the small diamond of the dividers
Our own art, deterministic, Pillow only.
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, '..', 'overlay', 'modules', 'game_itemtooltip', 'images'))
SS = 8  # supersampling


def _down(im, size):
    return im.resize(size, Image.LANCZOS)


def ring():
    n = 52
    im = Image.new('RGBA', (n * SS, n * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((1 * SS, 1 * SS, (n - 1) * SS - 1, (n - 1) * SS - 1), outline=(255, 255, 255, 255), width=2 * SS)
    return _down(im, (n, n))


def disc():
    n = 52
    im = Image.new('RGBA', (n * SS, n * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((1 * SS, 1 * SS, (n - 1) * SS - 1, (n - 1) * SS - 1), fill=(24, 18, 14, 255))
    return _down(im, (n, n))


def glow():
    w, h = 64, 40
    im = Image.new('RGBA', (w, h), (255, 255, 255, 0))
    px = im.load()
    for y in range(h):
        for x in range(w):
            dx, dy = (x + 0.5 - w / 2) / (w / 2), (y + 0.5) / h  # centre on the top edge
            r = (dx * dx + dy * dy) ** 0.5
            a = max(0.0, 1.0 - r)
            px[x, y] = (255, 255, 255, int(round(120 * a * a)))
    return im


def diamond():
    n = 11
    im = Image.new('RGBA', (n * SS, n * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = n * SS / 2
    d.polygon([(c, 1 * SS), (n * SS - SS, c), (c, n * SS - SS), (SS, c)], fill=(255, 255, 255, 255))
    return _down(im, (n, n))


FILES = [('ring.png', ring), ('disc.png', disc), ('glow.png', glow), ('diamond.png', diamond)]


def main(argv):
    args = argv[1:]
    if '--check' in args:
        return check()
    out = args[0] if args else DEFAULT_OUT
    os.makedirs(out, exist_ok=True)
    for name, fn in FILES:
        fn().save(os.path.join(out, name))
        print('wrote', os.path.join(out, name))
    return 0


def check():
    import tempfile
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, fn in FILES:
            fn().save(os.path.join(tmp, name))
            shipped = os.path.join(DEFAULT_OUT, name)
            if not os.path.exists(shipped):
                bad.append(name + ': missing')
                continue
            a, b = Image.open(os.path.join(tmp, name)).convert('RGBA'), Image.open(shipped).convert('RGBA')
            if a.size != b.size or a.tobytes() != b.tobytes():
                bad.append(name + ': differs')
    for line in bad:
        print('gen_tooltip_art --check:', line)
    if bad:
        print('run: python3 -I client/tools/gen_tooltip_art.py')
        return 1
    print('tooltip art: up to date')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
