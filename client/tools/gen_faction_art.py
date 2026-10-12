#!/usr/bin/env python3
"""Pixel-art emblems of the four factions (client module game_factions; server factions_config.lua).

Run: python3 client/tools/gen_faction_art.py [OUTDIR] [--sheet SHEET.png]
     default OUTDIR: client/overlay/data/images/factions  ->  <key>.png (64x64) and <key>_small.png (32x32) per faction
     --sheet writes a 4x contact sheet of every emblem as well

Our own art, drawn here and deterministic (no stock or donor pictures were found that fit; nothing is traced). The look
follows the buff icons (tools/gen_buff_icons.py): hard pixels, no anti-aliasing, one colour ramp of five shades per
material, light from the top left (lit top-left edges, shaded bottom-right edges), an ink outline and the house frame:
a heater shield with a warm ember-gold rim (#b8923a outer line, lit gold inner line, ember studs) on a dark plate tinted
with the faction's colour, and a blood-red inner line where the plate meets the rim. The motif is drawn at 4x in palette
slots, reduced to the target size by majority (crisp pixels), then shaded by the ramp and outlined.
  vigil    the Ashen Vigil: a skull under a pyre flame
  compact  the Cinderforge Compact: an anvil, a hammer and sparks
  choir    the Veiled Choir: an eye under a hood, three tears
  circle   the Thornbound Circle: a ring of thorns round a leaf
Needs Pillow."""
import os, sys
from collections import Counter
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'factions')

N = 64
K = 4

RAMP = {
    'ember': [(92, 30, 12), (176, 62, 18), (240, 118, 28), (255, 184, 60), (255, 238, 150)],
    'gold': [(96, 62, 16), (168, 116, 32), (222, 170, 60), (250, 214, 112), (255, 246, 200)],
    'blood': [(70, 6, 14), (138, 15, 30), (206, 22, 36), (250, 60, 62), (255, 150, 136)],
    'bone': [(80, 66, 46), (140, 122, 92), (198, 182, 148), (232, 220, 190), (255, 250, 236)],
    'steel': [(40, 40, 48), (86, 86, 98), (140, 140, 152), (196, 196, 206), (250, 250, 255)],
    'arcane': [(50, 18, 90), (98, 40, 160), (150, 80, 230), (200, 140, 255), (245, 222, 255)],
    'shadow': [(30, 20, 46), (64, 44, 92), (108, 84, 140), (160, 140, 196), (222, 212, 240)],
    'nature': [(14, 64, 40), (30, 120, 60), (70, 180, 70), (140, 230, 90), (220, 255, 180)],
    'wood': [(60, 32, 14), (110, 62, 26), (160, 98, 44), (206, 146, 78), (240, 200, 140)],
}
INK = (12, 6, 12)
FRAME_OUT = (184, 146, 58)
FRAME_LIT = (250, 214, 112)
FRAME_SHADE = (120, 80, 22)
STUD = (255, 184, 60)
BLOOD_LINE = (138, 15, 30)

# faction key -> plate tint and the ramps of the motif slots (1 = ramp A, 2 = ramp B, 3 = ramp C, 4 = white / flat light)
FACTIONS = {
    'vigil': {'plate': (40, 24, 16), 'A': 'bone', 'B': 'ember', 'C': 'gold'},
    'compact': {'plate': (44, 18, 12), 'A': 'steel', 'B': 'ember', 'C': 'wood'},
    'choir': {'plate': (28, 16, 44), 'A': 'shadow', 'B': 'arcane', 'C': 'blood'},
    'circle': {'plate': (14, 34, 20), 'A': 'wood', 'B': 'nature', 'C': 'blood'},
}

SHIELD = [(8, 6), (56, 6), (56, 30), (52, 42), (44, 51), (32, 58), (20, 51), (12, 42), (8, 30)]


class Canvas:
    def __init__(self):
        self.img = Image.new('L', (N * K, N * K), 0)
        self.d = ImageDraw.Draw(self.img)

    @staticmethod
    def _p(pts):
        return [(x * K, y * K) for x, y in pts]

    def poly(self, pts, v):
        self.d.polygon(self._p(pts), fill=v)

    def ell(self, x0, y0, x1, y1, v):
        self.d.ellipse((x0 * K, y0 * K, x1 * K - 1, y1 * K - 1), fill=v)

    def rect(self, x0, y0, x1, y1, v):
        self.d.rectangle((x0 * K, y0 * K, x1 * K - 1, y1 * K - 1), fill=v)

    def line(self, pts, v, w=1.0):
        self.d.line(self._p(pts), fill=v, width=max(1, int(round(w * K))))

    def arc(self, box, a0, a1, v, w=1.0):
        x0, y0, x1, y1 = box
        self.d.arc((x0 * K, y0 * K, x1 * K - 1, y1 * K - 1), a0, a1, fill=v, width=max(1, int(round(w * K))))

    def grid(self, size):
        """majority of each KxK (scaled) cell; a cell needs a quarter of its pixels to count as a slot"""
        src = self.img.resize((size * K, size * K), Image.NEAREST).load() if size != N else self.img.load()
        g = [[0] * size for _ in range(size)]
        for y in range(size):
            for x in range(size):
                c = Counter(src[x * K + i, y * K + j] for i in range(K) for j in range(K))
                v, n = c.most_common(1)[0]
                if v == 0 and n < K * K:
                    rest = [(vv, nn) for vv, nn in c.most_common() if vv != 0]
                    if rest and rest[0][1] * 4 >= K * K * 1.5:
                        v = rest[0][0]
                g[y][x] = v
        return g


# ---------------------------------------------------------------- motifs (slots: 1 A, 2 B, 3 C, 4 light, 5 ink detail)
def motif_vigil(c):
    # pyre flame
    c.poly([(32, 9), (38, 16), (41, 22), (38, 27), (35, 24), (34, 29), (30, 29), (28, 24), (25, 27), (22, 22), (26, 15)], 2)
    c.poly([(32, 15), (35, 20), (34, 25), (32, 23), (30, 25), (29, 20)], 4)
    # skull
    c.ell(21, 25, 43, 45, 1)
    c.rect(25, 40, 39, 49, 1)
    c.ell(24, 32, 31, 39, 5)
    c.ell(33, 32, 40, 39, 5)
    c.poly([(32, 39), (34, 43), (30, 43)], 5)
    for x in (27, 30, 33, 36):
        c.rect(x, 46, x + 1, 49, 5)
    # crossed brands behind
    c.line([(14, 48), (22, 42)], 3, 2.5)
    c.line([(50, 48), (42, 42)], 3, 2.5)


def motif_compact(c):
    # anvil
    c.poly([(14, 31), (46, 31), (50, 27), (52, 31), (48, 36), (40, 37), (38, 43), (44, 47), (20, 47), (26, 43), (24, 37), (16, 36)], 1)
    c.rect(20, 47, 44, 50, 1)
    # hammer
    c.line([(30, 27), (44, 13)], 3, 2.5)
    c.poly([(37, 9), (46, 18), (50, 14), (41, 5)], 1)
    # sparks
    for x, y in ((20, 20), (17, 25), (24, 15), (27, 22), (14, 18)):
        c.rect(x, y, x + 2, y + 2, 2)
    c.rect(21, 24, 23, 26, 4)


def motif_choir(c):
    # hood
    c.poly([(32, 8), (46, 20), (50, 40), (42, 50), (22, 50), (14, 40), (18, 20)], 1)
    c.poly([(32, 15), (41, 24), (43, 38), (32, 44), (21, 38), (23, 24)], 5)
    # the eye
    c.poly([(21, 30), (27, 25), (37, 25), (43, 30), (37, 35), (27, 35)], 2)
    c.ell(28, 26, 36, 34, 4)
    c.ell(30, 28, 34, 32, 5)
    # tears
    for x in (26, 32, 38):
        c.poly([(x, 38), (x + 2, 43), (x, 45), (x - 2, 43)], 3)


def motif_circle(c):
    # ring of thorns
    c.arc((13, 11, 51, 49), 0, 360, 1, 3.2)
    import math
    for i in range(10):
        a = math.radians(i * 36 + 10)
        cx, cy = 32 + 19 * math.cos(a), 30 + 19 * math.sin(a)
        ox, oy = math.cos(a + 0.9), math.sin(a + 0.9)
        c.poly([(cx - ox * 2, cy - oy * 2), (cx + ox * 2, cy + oy * 2),
                (cx + math.cos(a) * 6, cy + math.sin(a) * 6)], 1)
    # leaf
    c.poly([(32, 15), (40, 23), (42, 31), (38, 40), (32, 45), (26, 40), (22, 31), (24, 23)], 2)
    c.line([(32, 18), (32, 44)], 5, 1.2)
    c.line([(32, 26), (37, 22)], 5, 1)
    c.line([(32, 33), (27, 29)], 5, 1)
    # a drop of blood on a thorn
    c.ell(46, 41, 50, 46, 3)


MOTIFS = {'vigil': motif_vigil, 'compact': motif_compact, 'choir': motif_choir, 'circle': motif_circle}


def inside_shield(size):
    c = Canvas()
    c.poly(SHIELD, 1)
    return c.grid(size)


def shade(g, x, y, size, ramp):
    """ramp index by light from the top left: lit where the up-left neighbour is not this slot, dark down-right"""
    v = g[y][x]
    up = g[y - 1][x] if y > 0 else 0
    left = g[y][x - 1] if x > 0 else 0
    down = g[y + 1][x] if y < size - 1 else 0
    right = g[y][x + 1] if x < size - 1 else 0
    if up != v or left != v:
        return ramp[3] if (up != v and left != v) else ramp[3 if up != v else 2]
    if down != v or right != v:
        return ramp[1]
    # a soft vertical light inside larger shapes
    return ramp[2] if y < size * 0.55 else ramp[1]


def render(key, size):
    spec = FACTIONS[key]
    shield = inside_shield(size)
    c = Canvas()
    MOTIFS[key](c)
    g = c.grid(size)
    s = size / 64.0
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    px = out.load()
    plate = spec['plate']
    # plate with a soft top-left light
    for y in range(size):
        for x in range(size):
            if shield[y][x]:
                t = (x + y) / (2.0 * size)
                px[x, y] = tuple(int(plate[i] * (1.35 - 0.7 * t)) for i in range(3)) + (255,)
    # motif
    ramps = {1: RAMP[spec['A']], 2: RAMP[spec['B']], 3: RAMP[spec['C']], 4: RAMP[spec['B']]}
    for y in range(size):
        for x in range(size):
            v = g[y][x]
            if not v or not shield[y][x]:
                continue
            if v == 5:
                px[x, y] = INK + (255,)
            elif v == 4:
                px[x, y] = ramps[4][4] + (255,)
            else:
                px[x, y] = shade(g, x, y, size, ramps[v]) + (255,)
    # ink outline round the motif (on the plate only)
    for y in range(size):
        for x in range(size):
            if shield[y][x] and not g[y][x]:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < size and 0 <= yy < size and g[yy][xx] and g[yy][xx] != 5:
                        px[x, y] = INK + (255,)
                        break
    # the frame: outer gold line, lit / shaded bevel, blood inner line
    def edge(x, y):
        return shield[y][x] and any(not (0 <= x + dx < size and 0 <= y + dy < size and shield[y + dy][x + dx])
                                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    ring1 = [(x, y) for y in range(size) for x in range(size) if edge(x, y)]
    inner = [[shield[y][x] and (x, y) not in set(ring1) for x in range(size)] for y in range(size)]
    ring1s = set(ring1)
    for x, y in ring1:
        px[x, y] = FRAME_OUT + (255,)
    width = max(1, int(round(2 * s)))
    cur = inner
    for k in range(width + 1):
        ring = []
        for y in range(size):
            for x in range(size):
                if cur[y][x] and any(not (0 <= x + dx < size and 0 <= y + dy < size and cur[y + dy][x + dx])
                                     for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    ring.append((x, y))
        for x, y in ring:
            if k < width:
                lit = (x + y) < size * 0.95
                px[x, y] = (FRAME_LIT if lit else FRAME_SHADE) + (255,)
            else:
                px[x, y] = BLOOD_LINE + (255,)
        rs = set(ring)
        cur = [[cur[y][x] and (x, y) not in rs for x in range(size)] for y in range(size)]
    del ring1s
    # ember studs in the upper corners and the point
    for sx, sy in ((11, 9), (52, 9), (32, 54)):
        x, y = int(round(sx * s)), int(round(sy * s))
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)) if size >= 48 else ((0, 0),):
            if 0 <= x + dx < size and 0 <= y + dy < size:
                px[x + dx, y + dy] = (STUD if (dx, dy) != (1, 1) else RAMP['ember'][1]) + (255,)
    return out


def main():
    args = [a for a in sys.argv[1:]]
    sheet = None
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else DEFAULT_OUT
    os.makedirs(out, exist_ok=True)
    big = []
    for key in FACTIONS:
        img = render(key, 64)
        img.save(os.path.join(out, key + '.png'))
        render(key, 32).save(os.path.join(out, key + '_small.png'))
        big.append(img)
        print('wrote', os.path.join(out, key + '.png'))
    if sheet:
        w = Image.new('RGBA', (len(big) * 64 * 4 + (len(big) + 1) * 8, 64 * 4 + 16), (16, 12, 14, 255))
        for i, img in enumerate(big):
            w.paste(img.resize((256, 256), Image.NEAREST), (8 + i * 264, 8), img.resize((256, 256), Image.NEAREST))
        w.save(sheet)
        print('wrote', sheet)
    return 0


if __name__ == '__main__':
    sys.exit(main())
