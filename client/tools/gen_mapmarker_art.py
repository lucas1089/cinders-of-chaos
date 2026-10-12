#!/usr/bin/env python3
"""Art of the map markers (client module game_mapmarkers): party member pins and edge arrows, the floor arrows and one
icon per kind of point of interest. Run: python3 client/tools/gen_mapmarker_art.py [OUTDIR] [--sheet SHEET.png]
(default OUTDIR: client/overlay/data/images/chaos/mapmarkers; --sheet also writes a contact sheet at 4x, not shipped).

House look (gen_buff_icons.py, gen_toast_art.py): blackened iron plates lit from the top left, a thin gold rim
(#b8923a, the client's buff border), motifs in the five-shade ramps of gen_buff_icons.py (ember, gold, frost, blood,
nature, arcane, stone). Shapes are drawn at 4x and reduced (smooth edges that read on the minimap's colours), with a dark
outline so they stay visible over water, grass and the black of unexplored map.
  party_pin.png           12x12  a round pin, white to light grey with a dark rim: the client tints it with the
                                 member's party colour (image-color), so one file serves every colour
  party_arrow_<dir>.png   12x12  the same for a member outside the shown map: a pointed arrow toward n, ne, e, se, s,
                                 sw, w, nw (tinted the same way)
  floor_up.png / floor_down.png 8x8  gold triangles: the member is on a higher / lower floor
  poi_<kind>.png          14x14  a dark round plate, gold rim, the kind's motif: temple, depot, bank, npc, shop,
                                 travel, bless, craft, guild, portal, boss, dungeon, hunt
Our own art; deterministic. Needs Pillow."""
import math
import os
import sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'chaos', 'mapmarkers')

K = 4
INK = (12, 6, 12, 255)
RIM = (184, 146, 58, 255)          # #b8923a
PLATE = [(26, 20, 24, 255), (44, 36, 40, 255)]  # dark, lit
# ramps dark -> highlight (gen_buff_icons.py)
R = {
    'ember': [(92, 30, 12), (176, 62, 18), (240, 118, 28), (255, 184, 60), (255, 238, 150)],
    'gold': [(96, 62, 16), (168, 116, 32), (222, 170, 60), (250, 214, 112), (255, 246, 200)],
    'blood': [(70, 6, 14), (138, 15, 30), (206, 22, 36), (250, 60, 62), (255, 150, 136)],
    'frost': [(20, 52, 110), (40, 110, 190), (96, 180, 240), (170, 226, 255), (240, 252, 255)],
    'nature': [(14, 64, 40), (30, 120, 60), (70, 180, 70), (140, 230, 90), (220, 255, 180)],
    'arcane': [(44, 18, 80), (86, 40, 150), (140, 80, 220), (196, 150, 255), (240, 220, 255)],
    'stone': [(50, 46, 44), (90, 84, 80), (140, 132, 124), (196, 188, 178), (240, 236, 228)],
}


def c(ramp, i):
    return R[ramp][i] + (255,)


class Canvas:
    def __init__(self, size):
        self.size = size
        self.img = Image.new('RGBA', (size * K, size * K), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def p(self, v):
        return v * K

    def ellipse(self, x0, y0, x1, y1, fill):
        self.d.ellipse((self.p(x0), self.p(y0), self.p(x1), self.p(y1)), fill=fill)

    def rect(self, x0, y0, x1, y1, fill):
        self.d.rectangle((self.p(x0), self.p(y0), self.p(x1), self.p(y1)), fill=fill)

    def poly(self, pts, fill):
        self.d.polygon([(self.p(x), self.p(y)) for x, y in pts], fill=fill)

    def line(self, pts, fill, w):
        self.d.line([(self.p(x), self.p(y)) for x, y in pts], fill=fill, width=max(1, round(self.p(w))), joint='curve')

    def done(self):
        return self.img.resize((self.size, self.size), Image.LANCZOS)


def grow(pts, w):
    cx = sum(x for x, _ in pts) / len(pts)
    cy = sum(y for _, y in pts) / len(pts)
    out = []
    for x, y in pts:
        dx, dy = x - cx, y - cy
        ln = math.hypot(dx, dy) or 1
        out.append((x + dx / ln * w, y + dy / ln * w))
    return out


# ------------------------------------------------------------------------------------------------ party
def party_pin():
    cv = Canvas(12)
    cv.ellipse(0.4, 0.4, 11.6, 11.6, INK)
    cv.ellipse(1.5, 1.5, 10.5, 10.5, (200, 200, 200, 255))
    cv.ellipse(2.2, 2.0, 9.4, 9.2, (255, 255, 255, 255))      # lit from the top left
    cv.ellipse(4.3, 4.3, 7.7, 7.7, (90, 90, 90, 255))           # the centre dot reads as "a person here"
    return cv.done()


DIRS = {'n': -90, 'ne': -45, 'e': 0, 'se': 45, 's': 90, 'sw': 135, 'w': 180, 'nw': -135}


def party_arrow(angle):
    cv = Canvas(12)
    a = math.radians(angle)

    def rot(x, y):
        return (6 + x * math.cos(a) - y * math.sin(a), 6 + x * math.sin(a) + y * math.cos(a))
    shape = [rot(5.2, 0), rot(-3.6, -4.4), rot(-1.6, 0), rot(-3.6, 4.4)]
    cv.poly(grow(shape, 1.1), INK)
    cv.poly(shape, (235, 235, 235, 255))
    cv.poly([rot(5.2, 0), rot(-3.6, -4.4), rot(-1.6, 0)], (255, 255, 255, 255))
    return cv.done()


def floor_arrow(up):
    cv = Canvas(8)
    pts = [(4, 0.9), (7.4, 6.4), (0.6, 6.4)]
    if not up:
        pts = [(x, 7.3 - y) for x, y in pts]
    cv.poly(grow(pts, 0.9), INK)
    cv.poly(pts, c('gold', 3))
    return cv.done()


# ------------------------------------------------------------------------------------------------ points of interest
def plate(cv):
    cv.ellipse(0.2, 0.2, 13.8, 13.8, INK)
    cv.ellipse(0.9, 0.9, 13.1, 13.1, RIM)
    cv.ellipse(1.8, 1.8, 12.2, 12.2, PLATE[0])
    cv.ellipse(2.2, 2.0, 10.6, 9.6, PLATE[1])


def m_temple(cv):
    cv.rect(6.2, 3.0, 7.8, 11.0, c('gold', 4))
    cv.rect(4.0, 5.2, 10.0, 6.8, c('gold', 4))
    cv.rect(7.0, 3.6, 7.8, 10.4, c('gold', 2))


def m_depot(cv):
    cv.rect(3.4, 4.6, 10.6, 10.8, c('ember', 1))
    cv.rect(3.4, 4.6, 10.6, 5.6, c('ember', 3))
    cv.rect(3.4, 7.2, 10.6, 7.9, INK)
    cv.rect(6.3, 6.6, 7.7, 8.8, c('gold', 4))


def m_bank(cv):
    cv.ellipse(3.4, 3.4, 10.6, 10.6, c('gold', 2))
    cv.ellipse(4.2, 3.8, 9.8, 9.4, c('gold', 3))
    cv.rect(6.4, 4.6, 7.6, 9.4, c('gold', 0))
    cv.rect(5.0, 5.6, 9.0, 6.4, c('gold', 0))
    cv.rect(5.0, 7.6, 9.0, 8.4, c('gold', 0))


def m_npc(cv):
    cv.ellipse(5.0, 2.8, 9.0, 6.8, c('ember', 4))
    cv.d.pieslice((cv.p(3.2), cv.p(7.0), cv.p(10.8), cv.p(14.4)), 180, 360, fill=c('ember', 2))
    cv.ellipse(5.6, 3.3, 7.4, 5.0, (255, 255, 255, 200))


def m_shop(cv):
    cv.poly([(3.2, 5.6), (10.8, 5.6), (10.0, 11.0), (4.0, 11.0)], c('nature', 2))
    cv.poly([(3.2, 5.6), (10.8, 5.6), (10.6, 6.8), (3.4, 6.8)], c('nature', 4))
    cv.line([(5.2, 5.8), (5.6, 3.2), (8.4, 3.2), (8.8, 5.8)], c('stone', 3), 0.9)


def m_travel(cv):
    cv.poly([(2.8, 8.0), (11.2, 8.0), (9.6, 10.8), (4.4, 10.8)], c('ember', 1))
    cv.poly([(7.0, 2.6), (7.0, 7.4), (10.4, 7.4)], c('frost', 4))
    cv.poly([(6.4, 3.6), (6.4, 7.4), (3.8, 7.4)], c('frost', 3))
    cv.rect(6.5, 2.6, 7.1, 8.0, c('stone', 1))


def m_bless(cv):
    cv.poly([(7, 2.4), (8.4, 6.0), (11.6, 7.0), (8.4, 8.0), (7, 11.6), (5.6, 8.0), (2.4, 7.0), (5.6, 6.0)], c('gold', 4))
    cv.ellipse(5.9, 5.9, 8.1, 8.1, c('ember', 3))


def m_craft(cv):
    cv.poly([(3.0, 4.6), (8.6, 4.6), (8.6, 6.8), (3.0, 6.8)], c('stone', 3))      # the hammer's head
    cv.rect(5.1, 6.8, 6.5, 11.4, c('ember', 1))                                   # the handle
    cv.poly([(8.2, 8.6), (11.4, 8.6), (10.6, 10.8), (9.0, 10.8)], c('stone', 2))  # an anvil foot
    cv.ellipse(9.2, 3.0, 11.6, 5.4, c('ember', 3))                                # a spark


def m_guild(cv):
    cv.rect(4.0, 2.8, 4.8, 11.6, c('stone', 3))
    cv.poly([(4.8, 3.0), (11.0, 3.0), (9.4, 5.4), (11.0, 7.8), (4.8, 7.8)], c('blood', 2))
    cv.poly([(4.8, 3.0), (11.0, 3.0), (10.2, 4.2), (4.8, 4.2)], c('blood', 3))


def m_portal(cv):
    cv.ellipse(3.0, 2.6, 11.0, 11.4, c('arcane', 2))
    cv.ellipse(4.4, 4.0, 9.6, 10.0, c('arcane', 0))
    cv.ellipse(5.6, 5.4, 8.4, 8.6, c('arcane', 4))


def m_boss(cv):
    cv.poly([(2.6, 3.0), (5.0, 5.4), (9.0, 5.4), (11.4, 3.0), (10.8, 8.6), (7.0, 11.8), (3.2, 8.6)], c('blood', 2))
    cv.ellipse(4.6, 6.4, 6.6, 8.4, INK)
    cv.ellipse(7.4, 6.4, 9.4, 8.4, INK)
    cv.ellipse(5.1, 6.9, 6.1, 7.9, c('ember', 3))
    cv.ellipse(7.9, 6.9, 8.9, 7.9, c('ember', 3))


def m_dungeon(cv):
    cv.poly([(3.2, 11.4), (3.2, 6.2), (7.0, 2.8), (10.8, 6.2), (10.8, 11.4)], c('stone', 2))
    cv.poly([(5.2, 11.4), (5.2, 7.6), (7.0, 5.8), (8.8, 7.6), (8.8, 11.4)], INK)
    cv.rect(5.4, 10.0, 8.6, 11.4, c('ember', 2))


def m_hunt(cv):
    cv.line([(3.6, 10.4), (10.4, 3.6)], c('stone', 3), 1.1)
    cv.poly([(10.8, 3.2), (7.6, 3.8), (10.2, 6.4)], c('stone', 4))
    cv.line([(3.0, 9.0), (5.0, 11.0)], c('blood', 3), 1.0)
    cv.line([(4.2, 8.0), (6.0, 9.8)], c('blood', 3), 1.0)


POI = {'temple': m_temple, 'depot': m_depot, 'bank': m_bank, 'npc': m_npc, 'shop': m_shop, 'travel': m_travel,
       'bless': m_bless, 'craft': m_craft, 'guild': m_guild, 'portal': m_portal, 'boss': m_boss, 'dungeon': m_dungeon,
       'hunt': m_hunt}


def poi_icon(motif):
    cv = Canvas(14)
    plate(cv)
    motif(cv)
    return cv.done()


def all_art():
    out = {'party_pin': party_pin(), 'floor_up': floor_arrow(True), 'floor_down': floor_arrow(False)}
    for name, angle in DIRS.items():
        out['party_arrow_' + name] = party_arrow(angle)
    for kind, motif in POI.items():
        out['poi_' + kind] = poi_icon(motif)
    return out


def sheet(art, path):
    names = sorted(art)
    cell = 64
    img = Image.new('RGBA', (cell * 6, cell * ((len(names) + 5) // 6)), (60, 70, 50, 255))
    for i, n in enumerate(names):
        a = art[n]
        if n.startswith('party_'):
            tint = Image.new('RGBA', a.size, (255, 157, 46, 255))
            a = Image.composite(Image.blend(a, tint, 0.0), a, a)
            r, g, b, al = a.split()
            a = Image.merge('RGBA', (r.point(lambda v: v * 255 // 255), g.point(lambda v: v * 157 // 255),
                                     b.point(lambda v: v * 46 // 255), al))
        big = a.resize((a.width * 4, a.height * 4), Image.NEAREST)
        img.alpha_composite(big, ((i % 6) * cell + 4, (i // 6) * cell + 4))
    img.save(path)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    out = DEFAULT_OUT
    sheet_path = None
    if '--sheet' in argv:
        i = argv.index('--sheet')
        sheet_path = argv[i + 1]
        args = [a for a in args if a != sheet_path]
    if args:
        out = args[0]
    os.makedirs(out, exist_ok=True)
    art = all_art()
    for name, img in sorted(art.items()):
        img.save(os.path.join(out, name + '.png'), optimize=True)
    if sheet_path:
        sheet(art, sheet_path)
    print('wrote %d images to %s' % (len(art), out))


if __name__ == '__main__':
    main(sys.argv[1:])
