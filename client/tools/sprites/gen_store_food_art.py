#!/usr/bin/env python3
"""Draw the Everfull Ration look (the store's infinite food) in code and write it as the 32 px tile
art_import/store_food.png that import_art_things.py appends with art_import/store_food.csv (client id 33904, after
the pair 24 items).

python3 -I gen_store_food_art.py [--out art_import/store_food.png] [--preview PREVIEW.png]

Our own art (no sprite of any client is read), drawn the way gen_pouch_art.py draws the store pouches (its helpers):
a glazed earthen bowl with a gold rim, a roast haunch on it with its bone, and a ring of warm gold sparks around the
food (it never runs out). Drawn at 128 px, rim light from the upper left, a dark outline, downsampled 4:1 to 32 px.
Deterministic: the same script gives a byte-identical PNG.
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from darklib import grid, hexcol, ramp, poly_mask, seg_dist, rim_light, finish
from gen_pouch_art import S, F, canvas, paint, outlined, ellipse

HERE = os.path.dirname(os.path.abspath(__file__))


def ration():
    Y, X = grid(S, S)
    img = canvas()
    # the bowl: the lower half of a wide ellipse, a lip on top
    body = (ellipse(Y, X, 64, 78, 46, 30) <= 1) & (Y >= 78)
    foot = (ellipse(Y, X, 64, 108, 20, 6) <= 1)
    glaze = ramp(np.clip((Y - 78) / 34, 0, 1), ['#b5532a', '#7c2e14', '#3f160a'])
    img = paint(img, body | foot, glaze)
    lip = (ellipse(Y, X, 64, 78, 47, 9) <= 1)
    img = paint(img, lip, ramp(np.clip((Y - 70) / 16, 0, 1), ['#fff1a8', '#e8b52a', '#8f600a']))
    inner = (ellipse(Y, X, 64, 78, 41, 6) <= 1)
    img = paint(img, inner, hexcol('#2a120a'))
    # the roast haunch on the bowl: a round body, the bone to the upper right
    meat = (ellipse(Y, X, 56, 62, 30, 20) <= 1) | (ellipse(Y, X, 74, 54, 18, 14) <= 1)
    roast = ramp(np.clip((Y - 40) / 40 + 0.15 * np.sin(X / 7.0), 0, 1), ['#f0a35a', '#b8601f', '#7a3410', '#4a1d08'])
    img = paint(img, meat & (Y < 80), roast)
    sd, _ = seg_dist(X, Y, 84, 48, 102, 30)
    bone = sd < 5.5
    knob = (ellipse(Y, X, 103, 27, 6, 6) <= 1) | (ellipse(Y, X, 108, 32, 5.5, 5.5) <= 1)
    img = paint(img, bone | knob, ramp(np.clip((Y - 20) / 34, 0, 1), ['#fffaf0', '#e6dcc6', '#b8ab90']))
    img = rim_light(img, width=10, hl=1.0, sh=0.55, form=0.8, gloss=0.3)
    # crackling on the roast and a glint
    for cx, cy in ((44, 58), (58, 52), (66, 66), (50, 70)):
        img = paint(img, ellipse(Y, X, cx, cy, 4.5, 1.6) <= 1, hexcol('#5a2409'))
    img = paint(img, ellipse(Y, X, 48, 50, 5, 2.5) <= 1, hexcol('#ffd9a0'))
    # the never-empty sparks: four gold stars around the food
    for cx, cy, r in ((22, 40, 7), (106, 64, 6), (30, 92, 5), (92, 96, 5)):
        star = poly_mask(X, Y, [(cx, cy - r), (cx + r * 0.3, cy - r * 0.3), (cx + r, cy), (cx + r * 0.3, cy + r * 0.3),
                                (cx, cy + r), (cx - r * 0.3, cy + r * 0.3), (cx - r, cy), (cx - r * 0.3, cy - r * 0.3)])
        img = paint(img, star, hexcol('#ffe27a'))
    return outlined(img)


def build():
    return finish(ration(), F, False, 0.35)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default=os.path.join(HERE, 'art_import', 'store_food.png'))
    ap.add_argument('--preview', default=None)
    a = ap.parse_args()
    tile = build()
    Image.fromarray(tile, 'RGBA').save(a.out, optimize=False)
    print('tile', a.out, tile.shape[1], 'x', tile.shape[0])
    if a.preview:
        big = Image.fromarray(tile, 'RGBA').resize((128, 128), Image.NEAREST)
        sheet = Image.new('RGBA', (32 + 128 + 16, 160), (40, 34, 30, 255))
        sheet.paste(Image.fromarray(tile, 'RGBA'), (4, 4), Image.fromarray(tile, 'RGBA'))
        sheet.paste(big, (44, 16), big)
        sheet.save(a.preview)
        print('preview', a.preview)


if __name__ == '__main__':
    main()
