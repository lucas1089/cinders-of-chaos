#!/usr/bin/env python3
"""Footprint and outline pictures of game_cosmeticfx (drawn by every client for the players who wear them; server
cosmetics_config.lua kinds footprint / outline, `prints` and `glows` name the art keys):
  images/prints/<art>.png  64x64: the prints one step leaves, pointing north (the module rotates them to the step's
                           direction and fades them out)
  images/glows/<art>.png   128x128: a soft glow drawn behind the character (a creature bottom widget, centred on the
                           creature), the colour or a vertical gradient; pulsing outlines breathe in Lua
All drawn here from shapes and noise with a fixed seed (no reference art, nothing copied). preview_cosmeticfx.png (not
shipped, --preview PATH) shows them on a dark ground.
python3 -I client/tools/gen_cosmeticfx_art.py [--preview PATH]   (writes into client/overlay/modules/game_cosmeticfx/images/)"""
import math
import os
import random
import sys
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_cosmeticfx', 'images')
P = 64   # print canvas
G = 128  # glow canvas

# art key -> (style, main colour, edge / second colour)
PRINTS = {
    'ember': ('sole', (255, 196, 84), (226, 84, 18)),
    'frost': ('sole', (230, 248, 255), (110, 180, 250)),
    'blood': ('drops', (176, 16, 20), (96, 6, 8)),
    'ash': ('smudge', (178, 172, 166), (92, 88, 84)),
    'petal': ('petals', (255, 170, 204), (226, 96, 150)),
    'venom': ('drops', (126, 230, 80), (40, 120, 24)),
    'shadow': ('wisps', (170, 120, 240), (70, 30, 120)),
    'gilded': ('sole', (255, 226, 120), (196, 140, 30)),
    'spark': ('sparks', (236, 250, 255), (90, 170, 255)),
    'hunter': ('paws', (176, 120, 72), (96, 60, 32)),
    'chronicle': ('runes', (120, 228, 216), (40, 140, 132)),
    'rime': ('crystals', (240, 252, 255), (150, 210, 255)),
    'omen': ('motes', (196, 132, 255), (90, 40, 150)),
    # the collection score's footstep trail (server collection_config.lua, O318); appended last so the seeds above stay
    'laurel': ('petals', (214, 236, 128), (84, 150, 52)),
}
# art key -> (bottom colour, top colour, peak alpha 0..255, ring: None or ring colour)
GLOWS = {
    'gold': ((255, 200, 60), (255, 220, 110), 150, None),
    'crimson': ((210, 30, 30), (240, 70, 60), 150, None),
    'void': ((120, 50, 200), (170, 90, 240), 155, None),
    'frost': ((100, 180, 255), (170, 225, 255), 145, None),
    'verdant': ((70, 200, 80), (140, 240, 130), 145, None),
    'ember': ((220, 40, 10), (255, 214, 70), 160, None),
    'storm': ((20, 60, 200), (235, 250, 255), 160, None),
    'radiant': ((255, 230, 140), (255, 250, 210), 160, None),
    'abyssal': ((80, 30, 150), (140, 80, 220), 165, None),
    'absolute': ((255, 236, 180), (255, 255, 250), 170, (255, 214, 90)),
    'chronicle': ((60, 180, 170), (130, 235, 225), 150, None),
    'corona': ((20, 0, 30), (40, 10, 60), 175, (160, 80, 255)),
    'cinder': ((200, 30, 0), (255, 180, 40), 170, (255, 110, 20)),
}


def rgba(c, a):
    return (int(c[0]), int(c[1]), int(c[2]), int(max(0, min(255, a))))


def soft(im, r):
    return im.filter(ImageFilter.GaussianBlur(r))


# ---------------------------------------------------------------- prints
def sole(d, cx, cy, main, edge, flip):
    # a boot print: a rounded fore-sole and a heel, slightly turned outwards
    turn = -0.18 if flip else 0.18
    def pt(x, y):
        return (cx + x * math.cos(turn) - y * math.sin(turn), cy + x * math.sin(turn) + y * math.cos(turn))
    fore = [pt(5 * math.cos(t), -6 + 8 * math.sin(t)) for t in [i * math.pi / 12 for i in range(24)]]
    heel = [pt(3.6 * math.cos(t), 7 + 4 * math.sin(t)) for t in [i * math.pi / 12 for i in range(24)]]
    for poly in (fore, heel):
        d.polygon(poly, fill=rgba(edge, 235))
    for poly in (fore, heel):
        inner = [(cx + (x - cx) * 0.6, cy + (y - cy) * 0.6 + (-2 if poly is fore else 4) * 0.4) for x, y in poly]
        d.polygon(inner, fill=rgba(main, 245))


def draw_print(style, main, edge, seed):
    rnd = random.Random(seed)
    im = Image.new('RGBA', (P, P), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if style == 'sole':
        sole(d, 24, 38, main, edge, True)
        sole(d, 40, 22, main, edge, False)
    elif style == 'drops':
        for (x, y, r) in ((22, 40, 4.5), (38, 24, 4.0), (33, 44, 2.4), (28, 18, 2.0), (44, 36, 1.6)):
            d.ellipse((x - r, y - r, x + r, y + r), fill=rgba(edge, 240))
            d.ellipse((x - r * 0.65, y - r * 0.75, x + r * 0.55, y + r * 0.45), fill=rgba(main, 250))
            d.point((x - r * 0.3, y - r * 0.4), fill=rgba((255, 255, 255), 160))
    elif style == 'smudge':
        for (x, y) in ((24, 38), (40, 22)):
            for _ in range(26):
                a, rr = rnd.uniform(0, 2 * math.pi), rnd.uniform(0, 7)
                px, py = x + math.cos(a) * rr * 0.7, y + math.sin(a) * rr
                s = rnd.uniform(1.2, 2.6)
                d.ellipse((px - s, py - s, px + s, py + s), fill=rgba(edge if rnd.random() < 0.5 else main, 200))
    elif style == 'petals':
        for i, (x, y) in enumerate(((22, 40), (36, 30), (42, 18), (28, 22), (46, 40))):
            a = rnd.uniform(0, math.pi)
            pts = []
            for t in [k * math.pi / 10 for k in range(20)]:
                r = 5.5 * abs(math.sin(t)) ** 0.8
                pts.append((x + math.cos(t + a) * r, y + math.sin(t + a) * r * 0.55))
            d.polygon(pts, fill=rgba(main, 235))
            d.line([pts[0], pts[10]], fill=rgba(edge, 220))
    elif style == 'wisps':
        for (x, y, s) in ((24, 40, 1.0), (40, 22, 0.9), (34, 34, 0.6)):
            pts = [(x + math.cos(t) * 7 * s * (1 - t / 9), y - t * 1.6 * s + math.sin(t * 1.4) * 3 * s)
                   for t in [k * 0.3 for k in range(28)]]
            d.line(pts, fill=rgba(edge, 220), width=4)
            d.line(pts, fill=rgba(main, 240), width=2)
    elif style == 'sparks':
        for (x, y) in ((24, 40), (40, 22), (33, 31)):
            for k in range(4):
                a = k * math.pi / 4 + rnd.uniform(-0.2, 0.2)
                r = rnd.uniform(5, 8)
                d.line([(x - math.cos(a) * r, y - math.sin(a) * r), (x + math.cos(a) * r, y + math.sin(a) * r)],
                       fill=rgba(edge, 230), width=1)
            d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=rgba(main, 255))
    elif style == 'paws':
        for (x, y) in ((24, 40), (40, 22)):
            d.ellipse((x - 4.5, y - 1, x + 4.5, y + 6), fill=rgba(edge, 240))
            d.ellipse((x - 3.2, y, x + 3.2, y + 5), fill=rgba(main, 245))
            for (dx, dy) in ((-5, -4), (-2, -7), (2, -7), (5, -4)):
                d.ellipse((x + dx - 1.8, y + dy - 2.2, x + dx + 1.8, y + dy + 2.2), fill=rgba(main, 240))
                d.point((x + dx, y + dy - 4), fill=rgba(edge, 230))  # a claw
    elif style == 'runes':
        for (x, y) in ((24, 40), (40, 22)):
            d.ellipse((x - 7, y - 7, x + 7, y + 7), outline=rgba(edge, 200), width=1)
            d.line([(x, y - 5), (x, y + 5)], fill=rgba(main, 245), width=2)
            d.line([(x, y - 2), (x + 4, y - 5)], fill=rgba(main, 245), width=2)
            d.line([(x, y + 1), (x - 4, y + 4)], fill=rgba(main, 245), width=2)
    elif style == 'crystals':
        for (x, y, r) in ((24, 40, 7), (40, 22, 6.5), (36, 38, 3.5)):
            for k in range(3):
                a = k * math.pi / 3
                d.line([(x - math.cos(a) * r, y - math.sin(a) * r), (x + math.cos(a) * r, y + math.sin(a) * r)],
                       fill=rgba(edge, 235), width=2)
            for k in range(6):
                a = k * math.pi / 3
                d.line([(x, y), (x + math.cos(a) * r * 0.6, y + math.sin(a) * r * 0.6)], fill=rgba(main, 250))
    elif style == 'motes':
        for _ in range(18):
            x, y = rnd.uniform(18, 46), rnd.uniform(14, 48)
            s = rnd.uniform(1.0, 2.6)
            d.ellipse((x - s, y - s, x + s, y + s), fill=rgba(main if rnd.random() < 0.6 else edge, 220))
    glow = soft(im, 2.2)
    out = Image.new('RGBA', (P, P), (0, 0, 0, 0))
    # a faint halo of the art's own colour under the crisp shapes
    halo = Image.new('RGBA', (P, P), rgba(edge if style != 'sparks' else main, 0))
    halo.putalpha(glow.getchannel('A').point(lambda v: int(v * 0.55)))
    out.alpha_composite(halo)
    out.alpha_composite(im)
    if style == 'sole' and main == PRINTS['gilded'][1]:
        sd = ImageDraw.Draw(out)
        for (x, y) in ((30, 34), (46, 16), (18, 46)):
            sd.line([(x - 3, y), (x + 3, y)], fill=(255, 255, 230, 240))
            sd.line([(x, y - 3), (x, y + 3)], fill=(255, 255, 230, 240))
    return out


# ---------------------------------------------------------------- glows
def draw_glow(bottom, top, peak, ring):
    im = Image.new('RGBA', (G, G), (0, 0, 0, 0))
    px = im.load()
    cx, cy, rx, ry = G / 2 - 6, G / 2 - 10, 36.0, 50.0  # the body sits a little up and left of the creature's centre
    for y in range(G):
        t = min(1.0, max(0.0, (y - (cy - ry)) / (2 * ry)))  # 0 at the top, 1 at the bottom
        col = [top[i] + (bottom[i] - top[i]) * t for i in range(3)]
        for x in range(G):
            dx, dy = (x - cx) / rx, (y - cy) / ry
            r = math.sqrt(dx * dx + dy * dy)
            if r >= 1.0:
                continue
            # a full core (hidden behind the body) that fades out smoothly past the silhouette
            a = 1.0 if r < 0.42 else 0.5 + 0.5 * math.cos(math.pi * (r - 0.42) / 0.58)
            if ring:
                # a brighter rim near the edge (corona, cinder, absolute)
                rim = math.exp(-((r - 0.74) / 0.11) ** 2)
                c = [col[i] * (1 - rim) + ring[i] * rim for i in range(3)]
                a = max(a * 0.8, rim * 0.95)
            else:
                c = col
            px[x, y] = rgba(c, peak * a)
    return soft(im, 1.5)


def main():
    os.makedirs(os.path.join(OUT, 'prints'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'glows'), exist_ok=True)
    prints, glows = {}, {}
    for i, (key, (style, main_c, edge)) in enumerate(PRINTS.items()):
        # the shapes sit in the middle of the canvas: scaled up so a print fills most of its tile
        prints[key] = draw_print(style, main_c, edge, 1000 + i).crop((10, 10, 54, 54)).resize((P, P), Image.LANCZOS)
        prints[key].save(os.path.join(OUT, 'prints', key + '.png'))
    for key, spec in GLOWS.items():
        glows[key] = draw_glow(*spec)
        glows[key].save(os.path.join(OUT, 'glows', key + '.png'))
    if '--preview' in sys.argv:
        cols = max(len(prints), len(glows))
        prev = Image.new('RGBA', (cols * 136, 2 * 140), (38, 34, 30, 255))
        for i, im in enumerate(prints.values()):
            prev.alpha_composite(im.resize((128, 128), Image.NEAREST), (i * 136 + 4, 6))
        for i, im in enumerate(glows.values()):
            prev.alpha_composite(im, (i * 136 + 4, 146))
        prev.save(sys.argv[sys.argv.index('--preview') + 1])
    print('wrote', OUT)


if __name__ == '__main__':
    main()
