#!/usr/bin/env python3
"""Procedural art for game_monsterbar: one frame per tier. Run: python3 -I gen_monsterbar_art.py OUTDIR
Canvas 420x64, bar window x 24..396, y 34..52 (transparent so the progress bar shows through)."""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter

W, H = 420, 64
BAR = (24, 34, 396, 52)
TIERS = {
    # name: (rim light, rim dark, glow color, ornament)
    'normal':    ((150, 140, 145), (45, 40, 44), (0, 0, 0), None),
    'magic':     ((120, 170, 255), (30, 50, 110), (60, 120, 255), 'gem'),
    'rare':      ((255, 215, 110), (110, 75, 20), (255, 190, 50), 'wing'),
    'legendary': ((255, 150, 60), (120, 30, 10), (255, 90, 20), 'flame'),
    'boss':      ((230, 60, 40), (80, 8, 8), (220, 30, 20), 'skull'),
}

def glow(img, color, radius, strength):
    a = img.getchannel('A').filter(ImageFilter.GaussianBlur(radius))
    layer = Image.new('RGBA', img.size, color + (0,))
    layer.putalpha(a.point(lambda v: min(255, int(v * strength))))
    return Image.alpha_composite(layer, img)

def frame(tier):
    light, dark, gc, orn = TIERS[tier]
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = BAR
    # dark plate behind bar (kept: the progress bar draws over it)
    d.rectangle((x0 - 8, y0 - 6, x1 + 8, y1 + 6), fill=(12, 9, 12, 235))
    d.rectangle((x0 - 1, y0 - 1, x1 + 1, y1 + 1), fill=(0, 0, 0, 0))
    # bevelled iron rim
    for i, (c) in enumerate([dark, light, dark]):
        d.rectangle((x0 - 8 + i, y0 - 6 + i, x1 + 8 - i, y1 + 6 - i), outline=c + (255,))
    d.rectangle((x0 - 2, y0 - 2, x1 + 2, y1 + 2), outline=dark + (255,))
    d.rectangle((x0 - 1, y0 - 1, x1 + 1, y1 + 1), outline=light + (200,))
    # name plate
    d.polygon([(x0 + 40, 4), (x1 - 40, 4), (x1 - 20, 28), (x0 + 20, 28)], fill=(14, 10, 14, 215), outline=light + (255,))
    # rivets
    for x in range(x0 + 14, x1 - 8, 52):
        for y in (y0 - 4, y1 + 4):
            d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=light + (255,))
    cx = W // 2
    if orn == 'gem':
        for dx in (-1, 1):
            gx = cx + dx * 186
            d.polygon([(gx, 30), (gx + 7, 43), (gx, 56), (gx - 7, 43)], fill=gc + (255,), outline=light + (255,))
    elif orn == 'wing':
        for dx in (-1, 1):
            for k in range(5):
                bx = cx + dx * (150 + k * 9)
                d.polygon([(bx, 30 - k * 2), (bx + dx * 7, 26 - k * 2), (bx + dx * 4, 34)], fill=light + (255,), outline=dark + (255,))
        d.ellipse((cx - 7, 24, cx + 7, 38), fill=dark + (255,), outline=light + (255,))
    elif orn == 'flame':
        # symmetric flames along the top rim, kept inside the canvas and clear of the name text
        heights = [10, 14, 9, 13, 8, 12]
        for dx in (-1, 1):
            for k, h in enumerate(heights):
                bx = cx + dx * (150 + k * 9)
                d.polygon([(bx - 4, 30), (bx, 30 - h), (bx + 4, 30)], fill=(255, 140 + k * 10, 40, 255), outline=dark + (255,))
            # small ember gem at each end of the bar
            gx = cx + dx * 196
            d.polygon([(gx, 33), (gx + 5, 43), (gx, 53), (gx - 5, 43)], fill=gc + (255,), outline=light + (255,))
    elif orn == 'skull':
        # horns
        for dx in (-1, 1):
            pts = [(cx + dx * 26, 24), (cx + dx * 60, 18), (cx + dx * 92, 6), (cx + dx * 84, 24), (cx + dx * 56, 30)]
            d.polygon(pts, fill=(200, 190, 175, 255), outline=dark + (255,))
            for k in range(6):
                sx = x0 - 6 if dx < 0 else x1 + 6
                d.polygon([(sx, y0 + k * 3 - 4), (sx + dx * -10, y0 + 2 + k * 3 - 4), (sx, y0 + 4 + k * 3 - 4)], fill=light + (255,))
        # skull
        d.ellipse((cx - 17, 2, cx + 17, 34), fill=(222, 214, 198, 255), outline=dark + (255,))
        d.rectangle((cx - 9, 28, cx + 9, 38), fill=(222, 214, 198, 255), outline=dark + (255,))
        d.ellipse((cx - 12, 12, cx - 3, 23), fill=(20, 4, 4, 255))
        d.ellipse((cx + 3, 12, cx + 12, 23), fill=(20, 4, 4, 255))
        d.ellipse((cx - 10, 15, cx - 5, 20), fill=gc + (255,))
        d.ellipse((cx + 5, 15, cx + 10, 20), fill=gc + (255,))
        d.polygon([(cx, 24), (cx - 3, 29), (cx + 3, 29)], fill=(20, 4, 4, 255))
        for k in range(-3, 4):
            d.line((cx + k * 3, 32, cx + k * 3, 37), fill=dark + (255,))
        # blood drips under the bar
        random.seed(3)
        for _ in range(14):
            bx = random.randint(x0 + 6, x1 - 6)
            hh = random.randint(3, 10)
            d.rectangle((bx, y1 + 6, bx + 1, y1 + 6 + hh), fill=(150, 10, 10, 255))
            d.ellipse((bx - 1, y1 + 5 + hh, bx + 2, y1 + 8 + hh), fill=(150, 10, 10, 255))
    if gc != (0, 0, 0):
        img = glow(img, gc, 6, 1.6 if tier in ('legendary', 'boss') else 1.0)
    # clear the bar window again (glow may have bled into it)
    px = img.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px[x, y] = (0, 0, 0, 0)
    return img

def fill(tier):
    """16x18 horizontal-gradient swatch, handy for previews / future image-source use."""
    light, dark, gc, _ = TIERS[tier]
    img = Image.new('RGBA', (4, 18))
    px = img.load()
    base = {'normal': (170, 160, 160), 'magic': (60, 120, 230), 'rare': (235, 190, 50),
            'legendary': (240, 110, 30), 'boss': (190, 20, 16)}[tier]
    for y in range(18):
        k = 1.25 - abs(y - 5) / 12.0
        for x in range(4):
            px[x, y] = tuple(max(0, min(255, int(c * k))) for c in base) + (255,)
    return img

def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for t in TIERS:
        frame(t).save(os.path.join(out, f'frame_{t}.png'))
        fill(t).save(os.path.join(out, f'fill_{t}.png'))
    print('written', len(TIERS) * 2, 'images to', out)

if __name__ == '__main__':
    main()
