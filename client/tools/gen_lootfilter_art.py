#!/usr/bin/env python3
"""Art of game_lootfilter (white, tinted per rarity in the client with image-color):
  lf_glow.png   34x34 soft glow hugging the slot edge, transparent centre (highlighted items)
  lf_frame.png  34x34 crisp 1 px border with brighter corner ticks (items with a rarity that do not glow)
  lf_taken.png  34x34 check mark with a dark outline (loot channel: the item left the corpse; drawn untinted)
python3 -I client/tools/gen_lootfilter_art.py   (writes into client/overlay/modules/game_lootfilter/images/)"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_lootfilter', 'images')
S = 34


def edge_dist(x, y):
    return min(x, y, S - 1 - x, S - 1 - y)


def glow():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    px = im.load()
    for y in range(S):
        for x in range(S):
            d = edge_dist(x, y)
            if d <= 1:
                a = 255
            elif d <= 7:
                a = int(220 * (1 - (d - 1) / 6.0) ** 1.6)
            else:
                a = 0
            if a:
                px[x, y] = (255, 255, 255, a)
    return im


def frame():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    px = im.load()
    for y in range(S):
        for x in range(S):
            d = edge_dist(x, y)
            corner = (x < 7 or x > S - 8) and (y < 7 or y > S - 8)
            if d == 0:
                px[x, y] = (255, 255, 255, 255 if corner else 170)
            elif d == 1 and corner:
                px[x, y] = (255, 255, 255, 200)
    return im


def taken():
    big = Image.new('RGBA', (S * 4, S * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    pts = [(9 * 4, 18 * 4), (14 * 4, 24 * 4), (25 * 4, 10 * 4)]
    d.line(pts, fill=(10, 8, 6, 235), width=34, joint='curve')
    d.line(pts, fill=(150, 230, 120, 255), width=16, joint='curve')
    return big.resize((S, S), Image.LANCZOS)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    glow().save(os.path.join(OUT, 'lf_glow.png'))
    frame().save(os.path.join(OUT, 'lf_frame.png'))
    taken().save(os.path.join(OUT, 'lf_taken.png'))
    print('wrote', OUT)
