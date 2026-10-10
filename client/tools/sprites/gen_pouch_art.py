#!/usr/bin/env python3
"""Draw the three store pouch looks (Orbs Pouch, Rift Key Pouch, Loot Pouch) in code and write them as the 32 px atlas
art_import/pouches.png (3 x 1 tiles, in that order) that import_art_things.py appends with art_import/pouches.csv.

python3 -I gen_pouch_art.py [--out art_import/pouches.png] [--preview PREVIEW.png]

Our own art (no sprite of any client is read): each pouch is drawn at 128 px from shape fields (darklib.py), given
volume and rim light from the upper left (darklib.rim_light), a dark outline, then downsampled 4:1 (premultiplied box
average, light sharpening, hard alpha) to 32 px. Three silhouettes and colours that cannot be mixed up in a backpack:
  Orbs Pouch      a round violet velvet pouch, gold drawstring, a glowing cyan orb on its front
  Rift Key Pouch  a dark iron strongbox with riveted bands, a gold key on its front and a key ring on top
  Loot Pouch      a tall brown leather sack with a gold trim band, gold coins spilling at its foot
Deterministic: the same script gives a byte-identical PNG. --preview writes the three at 32 px and enlarged 4x
(nearest) on light and dark backgrounds.
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from darklib import grid, hexcol, ramp, sstep, poly_mask, seg_dist, rim_light, finish, over, rgba, dilate, blur

HERE = os.path.dirname(os.path.abspath(__file__))
S = 128           # drawing size
F = 4             # 128 -> 32
OUTLINE = hexcol('#140c08')


def canvas():
    return np.zeros((S, S, 4), np.float32)


def solid(mask, col):
    return rgba(np.broadcast_to(col, mask.shape + (3,)).copy(), mask.astype(np.float32))


def paint(img, mask, rgb):
    """rgb (H, W, 3) or a colour, over img where mask (bool or 0..1)"""
    m = mask.astype(np.float32)
    if np.ndim(rgb) == 1:
        rgb = np.broadcast_to(rgb, img.shape[:2] + (3,))
    return over(img, rgba(np.array(rgb, np.float32), m))


def outlined(img, steps=4):
    """a dark outline of `steps` px (1 px at 32) around the silhouette, under the art"""
    sil = img[..., 3] > 0.5
    ring = dilate(sil, steps)
    base = solid(ring, OUTLINE)
    return over(base, img)


def ellipse(Y, X, cx, cy, rx, ry):
    return ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2


# ----------------------------------------------------------------------------------------------- Orbs Pouch
def orbs_pouch():
    Y, X = grid(S, S)
    img = canvas()
    # body: a round sack, wider at the bottom, the neck gathered
    body = ellipse(Y, X, 64, 82, 44, 38) <= 1
    neck = poly_mask(X, Y, [(46, 48), (82, 48), (76, 60), (52, 60)])
    frill = poly_mask(X, Y, [(40, 26), (54, 36), (64, 24), (74, 36), (88, 26), (84, 46), (44, 46)])
    t = np.clip((Y - 20) / 100, 0, 1)
    velvet = ramp(t + 0.08 * np.sin(X / 6.0) * sstep(40, 110, Y), ['#b98cf2', '#7d43c9', '#4c2186', '#2a0f52'])
    # folds: soft vertical creases converging to the neck
    fold = 0.5 + 0.5 * np.sin((X - 64) / (8 + (Y - 40).clip(0) * 0.12))
    velvet = velvet * (0.82 + 0.18 * fold[..., None])
    img = paint(img, body | neck, velvet)
    img = paint(img, frill, ramp(np.clip((Y - 22) / 26, 0, 1), ['#c9a2f7', '#8a52d4']))
    # gold drawstring round the neck, a bow hanging on the right
    cord = (np.abs(ellipse(Y, X, 64, 51, 21, 6) - 1) < 0.22) & (Y > 46)
    d1, _ = seg_dist(X, Y, 80, 52, 92, 66)
    d2, _ = seg_dist(X, Y, 80, 52, 86, 70)
    cord |= (d1 < 2.6) | (d2 < 2.6)
    tassel = (ellipse(Y, X, 92, 69, 4, 5) <= 1) | (ellipse(Y, X, 86, 73, 4, 5) <= 1)
    gold = ramp(np.clip((Y - 44) / 30, 0, 1), ['#fff1a8', '#f2c230', '#a8740e'])
    img = paint(img, cord | tassel, gold)
    img = rim_light(img, width=10, hl=1.0, sh=0.55, form=0.8, gloss=0.25)
    # the orb emblem: a gold bezel, a cyan sphere with a white core and a glint, glow on the velvet
    r2 = ellipse(Y, X, 62, 86, 1, 1)
    glow = np.exp(-r2 / (2 * 22.0 ** 2)) * (body | neck)
    img[..., :3] = np.clip(img[..., :3] + glow[..., None] * hexcol('#5fe8ff') * 0.55, 0, 1)
    bezel = r2 <= 20.5 ** 2
    img = paint(img, bezel, ramp(np.clip((Y - 66) / 40, 0, 1), ['#fff3b0', '#e2a91f', '#7a520a']))
    sph = r2 <= 16 ** 2
    rr = np.sqrt(ellipse(Y, X, 57, 80, 1, 1)) / 26
    img = paint(img, sph, ramp(rr, ['#ffffff', '#b6fbff', '#38d6f2', '#126e9e', '#0b3a66']))
    glint = ellipse(Y, X, 56, 79, 4.5, 3.5) <= 1
    img = paint(img, glint, hexcol('#ffffff'))
    # two small sparkles
    for cx, cy, r in ((90, 40, 7), (34, 62, 5)):
        dx, dy = np.abs(X - cx), np.abs(Y - cy)
        star = ((dx < 1.6) & (dy < r)) | ((dy < 1.6) & (dx < r))
        img = paint(img, star, hexcol('#e9fcff'))
    return outlined(img)


# ----------------------------------------------------------------------------------------------- Rift Key Pouch
def key_pouch():
    Y, X = grid(S, S)
    img = canvas()
    # key ring on top (behind the lid): a thick iron ring with a small gold key hanging from it
    rd = np.sqrt(ellipse(Y, X, 64, 30, 1, 1))
    ring = np.abs(rd - 15) < 3.6
    img = paint(img, ring & (Y < 46), ramp(np.clip((Y - 14) / 30, 0, 1), ['#d5dbe3', '#7d8794', '#3a414b']))
    # strongbox: a front face and a lid with a little perspective
    front = poly_mask(X, Y, [(16, 58), (112, 58), (110, 118), (18, 118)])
    lid = poly_mask(X, Y, [(22, 40), (106, 40), (114, 60), (14, 60)])
    t = np.clip((Y - 40) / 80, 0, 1)
    plank = 0.5 + 0.5 * np.sin(Y / 3.0) * 0.15
    iron = ramp(t, ['#6c7682', '#444c57', '#2a3038', '#191d23'])
    iron = iron * (0.9 + plank[..., None] * 0.2)
    img = paint(img, front, iron)
    img = paint(img, lid, ramp(np.clip((Y - 40) / 20, 0, 1), ['#8a95a3', '#56606c']))
    # iron bands (lighter), corner plates and rivets
    band = (front | lid) & ((np.abs(X - 30) < 5) | (np.abs(X - 98) < 5))
    band |= front & (np.abs(Y - 62) < 3.5)
    img = paint(img, band, ramp(np.clip((Y - 40) / 80, 0, 1), ['#b4bcc6', '#6f7884', '#3c434c']))
    for cx in (30, 98):
        for cy in (50, 74, 96, 110):
            img = paint(img, ellipse(Y, X, cx, cy, 2.8, 2.8) <= 1, hexcol('#e3e8ee'))
    img = rim_light(img, width=10, hl=0.9, sh=0.5, form=0.6, gloss=0.2)
    # the gold key emblem across the front: bow (ring), shaft, two teeth
    gold = ramp(np.clip((Y - 70) / 40, 0, 1), ['#fff4b8', '#f3c537', '#9c6a0c'])
    bow = np.abs(np.sqrt(ellipse(Y, X, 44, 90, 1, 1)) - 9.5) < 4.2
    sd, _ = seg_dist(X, Y, 53, 90, 90, 90)
    shaft = sd < 3.6
    teeth = poly_mask(X, Y, [(80, 90), (85, 90), (85, 103), (80, 103)]) | \
        poly_mask(X, Y, [(88, 90), (93, 90), (93, 99), (88, 99)])
    key = bow | shaft | teeth
    img = paint(img, dilate(key, 3) & ~key, hexcol('#2a1a05'))
    img = paint(img, key, gold)
    img = paint(img, ellipse(Y, X, 41, 86, 2.5, 2) <= 1, hexcol('#ffffff'))
    # a violet rift glint in the keyhole of the lid
    hole = (ellipse(Y, X, 64, 51, 3.5, 3.5) <= 1) | poly_mask(X, Y, [(62, 52), (66, 52), (67, 58), (61, 58)])
    img = paint(img, hole, hexcol('#c06bff'))
    return outlined(img)


# ----------------------------------------------------------------------------------------------- Loot Pouch
def loot_pouch():
    Y, X = grid(S, S)
    img = canvas()
    # a tall sack: round belly, tied neck, the open top flaring out
    belly = ellipse(Y, X, 58, 86, 38, 34) <= 1
    neck = poly_mask(X, Y, [(44, 36), (72, 36), (68, 56), (48, 56)])
    top = poly_mask(X, Y, [(34, 14), (50, 22), (60, 12), (70, 22), (84, 14), (76, 38), (40, 38)])
    t = np.clip((Y - 10) / 110, 0, 1)
    grain = 0.5 + 0.5 * np.sin(X / 2.3 + np.sin(Y / 5.0) * 2.0)
    leather = ramp(t, ['#d9a066', '#a8662e', '#6e3c17', '#3d1f0a']) * (0.9 + 0.1 * grain[..., None])
    img = paint(img, belly | neck, leather)
    img = paint(img, top, ramp(np.clip((Y - 12) / 26, 0, 1), ['#e3b07a', '#9c5c28']))
    # stitched seam down the middle
    seam = (np.abs(X - 58 - (Y - 86) * 0.05) < 1.3) & belly & ((Y.astype(int) // 5) % 2 == 0)
    img = paint(img, seam, hexcol('#3a1d08'))
    # gold trim band round the neck and a gold clasp
    trim = neck & (np.abs(Y - 44) < 4.5)
    img = paint(img, trim, ramp(np.clip((Y - 39) / 10, 0, 1), ['#fff0a0', '#e8b52a', '#8f600a']))
    img = paint(img, ellipse(Y, X, 58, 44, 5, 5) <= 1, hexcol('#c0392b'))
    img = rim_light(img, width=10, hl=1.0, sh=0.55, form=0.8, gloss=0.2)
    # coins spilling at the foot (front right), a coin stack and loose coins
    for cx, cy, rx, ry in ((96, 110, 12, 6), (96, 103, 12, 6), (96, 96, 12, 6), (76, 116, 11, 6), (110, 118, 9, 5),
                           (84, 104, 9, 9)):
        e = ellipse(Y, X, cx, cy, rx, ry)
        img = paint(img, e <= 1.18, hexcol('#5a3a04'))
        img = paint(img, e <= 1, ramp(np.clip((Y - cy + ry) / (2 * ry), 0, 1), ['#fff6b8', '#ffd23a', '#b07a08']))
        img = paint(img, ellipse(Y, X, cx - rx * 0.3, cy - ry * 0.3, rx * 0.3, ry * 0.25) <= 1, hexcol('#fffbe0'))
    # a sparkle on the gold
    dx, dy = np.abs(X - 108), np.abs(Y - 88)
    img = paint(img, ((dx < 1.6) & (dy < 7)) | ((dy < 1.6) & (dx < 7)), hexcol('#ffffff'))
    return outlined(img)


LOOKS = (('orbs', orbs_pouch), ('keys', key_pouch), ('loot', loot_pouch))


def build():
    tiles = []
    for _, fn in LOOKS:
        tiles.append(finish(fn(), F, False, 0.35))
    return np.concatenate(tiles, axis=1)


def preview(atlas, path):
    n = atlas.shape[1] // 32
    pad, z = 8, 4
    W = n * (32 * z + pad) + pad
    H = 2 * (32 + 32 * z + 3 * pad)
    im = Image.new('RGBA', (W, H), (0, 0, 0, 255))
    for row, bg in enumerate(((214, 200, 170, 255), (40, 36, 34, 255))):
        y0 = row * (H // 2)
        im.paste(Image.new('RGBA', (W, H // 2), bg), (0, y0))
        for k in range(n):
            tile = Image.fromarray(atlas[:, k * 32:(k + 1) * 32])
            x = pad + k * (32 * z + pad)
            im.alpha_composite(tile, (x + 48, y0 + pad))
            im.alpha_composite(tile.resize((32 * z, 32 * z), Image.NEAREST), (x, y0 + 32 + 2 * pad))
    im.convert('RGB').save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default=os.path.join(HERE, 'art_import', 'pouches.png'))
    ap.add_argument('--preview', default=None)
    a = ap.parse_args()
    atlas = build()
    Image.fromarray(atlas, 'RGBA').save(a.out, optimize=False)
    print('atlas', a.out, atlas.shape[1], 'x', atlas.shape[0])
    if a.preview:
        preview(atlas, a.preview)
        print('preview', a.preview)


if __name__ == '__main__':
    main()
