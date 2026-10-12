#!/usr/bin/env python3
"""Marker icons of the map overlay (client module game_mapoverlay). Run: python3 -I gen_mapoverlay_icons.py OUTDIR
(the repo copy lives in client/overlay/data/images/chaos/mapoverlay/). Simple shapes drawn at 4x and scaled down to
16x16, a dark rim so they read over both the game view and the map colours."""
import math, os, sys
from PIL import Image, ImageDraw

S = 16
K = 4                       # supersampling
N = S * K
RIM = (10, 8, 10, 235)


def canvas():
    img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def p(v):
    return v * K


def done(img):
    return img.resize((S, S), Image.LANCZOS)


def circle(d, cx, cy, r, fill, rim=RIM, w=1.2):
    d.ellipse((p(cx - r - w), p(cy - r - w), p(cx + r + w), p(cy + r + w)), fill=rim)
    d.ellipse((p(cx - r), p(cy - r), p(cx + r), p(cy + r)), fill=fill)


def poly(d, pts, fill, rim=RIM, w=1.2):
    cx = sum(x for x, _ in pts) / len(pts)
    cy = sum(y for _, y in pts) / len(pts)
    big = []
    for x, y in pts:
        dx, dy = x - cx, y - cy
        ln = math.hypot(dx, dy) or 1
        big.append((p(x + dx / ln * w), p(y + dy / ln * w)))
    d.polygon(big, fill=rim)
    d.polygon([(p(x), p(y)) for x, y in pts], fill=fill)


def star(cx, cy, r1, r2, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def icon_party():
    img, d = canvas()
    circle(d, 8, 8, 4.6, (90, 220, 110, 255))
    circle(d, 8, 8, 1.8, (220, 255, 220, 255), rim=(0, 0, 0, 0), w=0)
    return done(img)


def icon_temple():
    img, d = canvas()
    circle(d, 8, 8, 6, (40, 90, 170, 255))
    d.rectangle((p(7), p(3.5), p(9), p(12.5)), fill=(245, 245, 255, 255))
    d.rectangle((p(4.5), p(6), p(11.5), p(8)), fill=(245, 245, 255, 255))
    return done(img)


def icon_depot():
    img, d = canvas()
    poly(d, [(2.5, 4), (13.5, 4), (13.5, 13), (2.5, 13)], (150, 100, 50, 255))
    d.rectangle((p(2.5), p(7.5), p(13.5), p(8.5)), fill=(70, 45, 20, 255))
    d.rectangle((p(7), p(6.5), p(9), p(10)), fill=(240, 200, 90, 255))
    return done(img)


def icon_npc():
    img, d = canvas()
    circle(d, 8, 8, 5, (240, 220, 120, 255))
    d.ellipse((p(6.2), p(4.4), p(9.8), p(8)), fill=(70, 55, 30, 255))
    d.pieslice((p(4.6), p(8.4), p(11.4), p(14.6)), 180, 360, fill=(70, 55, 30, 255))
    return done(img)


def icon_entry():
    img, d = canvas()
    circle(d, 8, 8, 6, (120, 70, 210, 255))
    circle(d, 8, 8, 3.6, (40, 20, 70, 255), rim=(0, 0, 0, 0), w=0)
    circle(d, 8, 8, 1.6, (210, 180, 255, 255), rim=(0, 0, 0, 0), w=0)
    return done(img)


def icon_guardian():
    img, d = canvas()
    # horned skull-ish: a red shield with two horns
    poly(d, [(2, 2.5), (5.5, 5.5), (10.5, 5.5), (14, 2.5), (13, 9), (8, 14), (3, 9)], (210, 40, 30, 255))
    d.ellipse((p(5), p(7), p(7.4), p(9.4)), fill=(25, 0, 0, 255))
    d.ellipse((p(8.6), p(7), p(11), p(9.4)), fill=(25, 0, 0, 255))
    return done(img)


def icon_boss():
    img, d = canvas()
    poly(d, [(8, 1.5), (14.5, 8), (8, 14.5), (1.5, 8)], (230, 90, 30, 255))
    d.ellipse((p(5.6), p(5.6), p(10.4), p(10.4)), fill=(60, 10, 0, 255))
    return done(img)


def icon_worldboss():
    img, d = canvas()
    poly(d, star(8, 8.4, 7, 3.1), (235, 40, 40, 255))
    circle(d, 8, 8.4, 1.6, (255, 220, 120, 255), rim=(0, 0, 0, 0), w=0)
    return done(img)


def icon_chest():
    img, d = canvas()
    poly(d, [(2, 6), (14, 6), (14, 13.5), (2, 13.5)], (220, 170, 50, 255))
    poly(d, [(2.5, 3), (13.5, 3), (14, 6), (2, 6)], (250, 210, 90, 255), w=0.8)
    d.rectangle((p(7), p(7), p(9), p(10)), fill=(90, 50, 10, 255))
    return done(img)


def icon_coffer():
    img, d = canvas()
    poly(d, [(2, 5), (14, 5), (14, 13.5), (2, 13.5)], (120, 120, 140, 255))
    d.rectangle((p(2), p(8.2), p(14), p(9.4)), fill=(50, 50, 60, 255))
    circle(d, 8, 8.8, 1.8, (200, 60, 220, 255), rim=(30, 0, 40, 255), w=0.6)
    return done(img)


def icon_goblin():
    img, d = canvas()
    circle(d, 8, 8, 5.6, (250, 200, 40, 255))
    circle(d, 8, 8, 3.8, (200, 140, 20, 255), rim=(0, 0, 0, 0), w=0)
    d.rectangle((p(7.2), p(4.6), p(8.8), p(11.4)), fill=(255, 240, 170, 255))
    return done(img)


def icon_invasion():
    img, d = canvas()
    d.ellipse((p(1.5), p(1.5), p(14.5), p(14.5)), outline=RIM, width=round(p(3.4)))
    d.ellipse((p(2), p(2), p(14), p(14)), outline=(255, 70, 40, 255), width=round(p(2)))
    for x0, y0, x1, y1 in ((7.2, 0.5, 8.8, 5), (7.2, 11, 8.8, 15.5), (0.5, 7.2, 5, 8.8), (11, 7.2, 15.5, 8.8)):
        d.rectangle((p(x0), p(y0), p(x1), p(y1)), fill=(255, 70, 40, 255))
    circle(d, 8, 8, 1.4, (255, 200, 120, 255), w=0.6)
    return done(img)


def icon_self():
    img, d = canvas()
    poly(d, [(8, 1.5), (13, 8), (8, 14.5), (3, 8)], (255, 255, 255, 255))
    d.polygon([(p(8), p(5)), (p(10.4), p(8)), (p(8), p(11)), (p(5.6), p(8))], fill=(70, 200, 255, 255))
    return done(img)


ICONS = {
    'party': icon_party, 'temple': icon_temple, 'depot': icon_depot, 'npc': icon_npc, 'entry': icon_entry,
    'guardian': icon_guardian, 'boss': icon_boss, 'worldboss': icon_worldboss, 'chest': icon_chest,
    'coffer': icon_coffer, 'goblin': icon_goblin, 'invasion': icon_invasion, 'self': icon_self,
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    for name, fn in ICONS.items():
        fn().save(os.path.join(out, name + '.png'))
    print('wrote', len(ICONS), 'icons to', out)


if __name__ == '__main__':
    main()
