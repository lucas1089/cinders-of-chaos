#!/usr/bin/env python3
"""The white up / down arrows of the Move up / Move down buttons (overlay data/styles/10-buttons.otui, MoveUpButton):
plain triangles the style tints (icon-color), 9 x 6 with a soft edge. The stock arrows were green and red.

usage: python3 -I client/tools/gen_rule_arrows.py [--check]
"""
import io, os, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'data', 'images', 'chaos')
W, H, SS = 9, 6, 8  # size and supersampling


def arrow(up):
    big = Image.new('L', (W * SS, H * SS), 0)
    d = ImageDraw.Draw(big)
    top, bottom = SS * 0.5, H * SS - SS * 0.5
    pts = [(W * SS / 2, top), (W * SS - SS * 0.5, bottom), (SS * 0.5, bottom)] if up else \
          [(W * SS / 2, bottom), (W * SS - SS * 0.5, top), (SS * 0.5, top)]
    d.polygon(pts, fill=255)
    alpha = big.resize((W, H), Image.LANCZOS)
    im = Image.new('RGBA', (W, H), (255, 255, 255, 0))
    im.putalpha(alpha)
    return im


def png(im):
    b = io.BytesIO()
    im.save(b, 'PNG', optimize=True)
    return b.getvalue()


def main(argv):
    check = '--check' in argv
    bad = 0
    for name, up in (('rule_arrow_up', True), ('rule_arrow_down', False)):
        path = os.path.join(OUT, name + '.png')
        data = png(arrow(up))
        if check:
            if not os.path.exists(path) or open(path, 'rb').read() != data:
                print('out of date: ' + path)
                bad += 1
        else:
            open(path, 'wb').write(data)
            print('wrote ' + path)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
