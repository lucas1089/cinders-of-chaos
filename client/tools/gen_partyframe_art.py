#!/usr/bin/env python3
"""Small status marks for the party frames (client module game_partyframes), 14x14 each.

Run: python3 client/tools/gen_partyframe_art.py [OUTDIR]
     default OUTDIR: client/overlay/data/images/game/partyframes  ->  crown, up, down, fight, dead, offline (.png)

crown = the party leader, up / down = a member on a floor above / below, fight = in a fight, dead = health at 0,
offline = connection lost. Our own procedural art, drawn at 8x and scaled down. Needs Pillow."""
import os, sys
from PIL import Image, ImageDraw

S = 112  # 8 x 14
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'partyframes')
GOLD, GOLD_D, INK = (246, 207, 114, 255), (150, 98, 24, 255), (20, 14, 16, 255)


def canvas():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def crown():
    img, d = canvas()
    pts = [(14, 90), (14, 36), (38, 62), (56, 22), (74, 62), (98, 36), (98, 90)]
    d.polygon(pts, fill=GOLD, outline=INK)
    d.rectangle((14, 82, 98, 96), fill=GOLD_D, outline=INK)
    for x in (14, 56, 98):
        d.ellipse((x - 8, 14 if x == 56 else 28, x + 8, 30 if x == 56 else 44), fill=(224, 58, 30, 255), outline=INK)
    return img


def arrow(up):
    img, d = canvas()
    if up:
        pts = [(56, 12), (100, 62), (72, 62), (72, 100), (40, 100), (40, 62), (12, 62)]
    else:
        pts = [(56, 100), (100, 50), (72, 50), (72, 12), (40, 12), (40, 50), (12, 50)]
    d.polygon(pts, fill=(158, 205, 255, 255), outline=INK)
    return img


def fight():
    img, d = canvas()
    for sign in (1, -1):
        d.line((20 if sign > 0 else 92, 16, 92 if sign > 0 else 20, 88), fill=(214, 220, 232, 255), width=12)
        d.line((20 if sign > 0 else 92, 16, 92 if sign > 0 else 20, 88), fill=INK, width=2)
    d.rectangle((12, 80, 100, 94), fill=GOLD_D, outline=INK)
    return img


def dead():
    img, d = canvas()
    d.ellipse((18, 10, 94, 78), fill=(226, 214, 182, 255), outline=INK, width=3)
    d.rectangle((38, 66, 74, 100), fill=(226, 214, 182, 255), outline=INK, width=3)
    d.ellipse((30, 34, 52, 58), fill=INK)
    d.ellipse((60, 34, 82, 58), fill=INK)
    return img


def offline():
    img, d = canvas()
    d.rectangle((10, 40, 54, 72), fill=(140, 128, 112, 255), outline=INK, width=3)
    d.rectangle((62, 40, 102, 72), fill=(140, 128, 112, 255), outline=INK, width=3)
    d.line((54, 56, 62, 56), fill=(224, 58, 30, 255), width=6)
    d.line((20, 94, 92, 18), fill=(224, 58, 30, 255), width=10)
    return img


ART = {'crown': crown, 'up': lambda: arrow(True), 'down': lambda: arrow(False), 'fight': fight, 'dead': dead, 'offline': offline}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    os.makedirs(out, exist_ok=True)
    for name, fn in ART.items():
        fn().resize((14, 14), Image.LANCZOS).save(os.path.join(out, name + '.png'), optimize=True)
    print(len(ART), 'party frame marks written to', out)


if __name__ == '__main__':
    main()
