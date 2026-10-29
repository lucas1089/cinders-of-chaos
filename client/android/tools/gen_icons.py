#!/usr/bin/env python3
"""Launcher icons of the Android client (O313): docs/brand/cinders_logo_icon.png scaled to the five densities.

  python3 -I client/android/tools/gen_icons.py [--check]

Writes app/src/main/res/mipmap-<density>/ic_launcher.png (48 dp at mdpi .. xxxhdpi). --check fails when a file is
missing or differs from what the script would write. Needs Pillow."""
import io
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
SRC = os.path.join(ROOT, 'docs', 'brand', 'cinders_logo_icon.png')
RES = os.path.join(HERE, '..', 'app', 'src', 'main', 'res')
SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}


def render(px):
    im = Image.open(SRC).convert('RGBA').resize((px, px), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def main():
    check = '--check' in sys.argv[1:]
    bad = 0
    for dens, px in SIZES.items():
        path = os.path.join(RES, 'mipmap-' + dens, 'ic_launcher.png')
        data = render(px)
        if check:
            if not os.path.exists(path) or Image.open(path).size != (px, px):
                print('stale or missing: ' + path)
                bad += 1
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(data)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
