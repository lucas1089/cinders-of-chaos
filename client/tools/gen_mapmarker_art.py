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
  npcmark_new.png         16x24  (O415) a gold exclamation mark with a dark outline: drawn over the head of an NPC that has
  npcmark_ready.png              a quest this character can start now; a gold question mark: a step to turn in or
  npcmark_locked.png             report to this NPC; a grey exclamation mark: a quest that waits for a level
  huntport.png            14x14  (O568) a stone gate with an ember opening: a hunt teleport of the hall
  huntport_last.png       18x18  the same in gold on a glowing plate: the one you last used, your way back
  huntexit.png            14x14  a frost door with an arrow out: the way out of a hunt you have entered
  huntexit_here.png       18x18  the same glowing: the way out of the hunt you stand in (the client pulses the two big ones)
  poi_<kind>.png          14x14  a dark round plate, gold rim, the kind's motif: temple, depot, bank, npc, shop,
                                 travel, bless, craft, guild, portal, boss, dungeon, hunt, quest (a quest giver or
                                 chest: a gold exclamation mark), questgoal (your next quest step: an ember target)
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
    def __init__(self, size, height=None, unit=None):
        # unit: the design's own size in drawing units (a 14 unit design on a bigger canvas is drawn bigger)
        self.size = size
        self.height = height or size
        self.k = K * size / (unit or size)
        self.img = Image.new('RGBA', (size * K, self.height * K), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def p(self, v):
        return v * self.k

    def ellipse(self, x0, y0, x1, y1, fill):
        self.d.ellipse((self.p(x0), self.p(y0), self.p(x1), self.p(y1)), fill=fill)

    def rect(self, x0, y0, x1, y1, fill):
        self.d.rectangle((self.p(x0), self.p(y0), self.p(x1), self.p(y1)), fill=fill)

    def poly(self, pts, fill):
        self.d.polygon([(self.p(x), self.p(y)) for x, y in pts], fill=fill)

    def line(self, pts, fill, w):
        self.d.line([(self.p(x), self.p(y)) for x, y in pts], fill=fill, width=max(1, round(self.p(w))), joint='curve')

    def done(self):
        return self.img.resize((self.size, self.height), Image.LANCZOS)


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


def m_quest(cv):
    cv.poly([(5.6, 2.6), (8.4, 2.6), (7.7, 8.4), (6.3, 8.4)], c('gold', 3))
    cv.poly([(5.6, 2.6), (8.4, 2.6), (8.2, 4.0), (5.8, 4.0)], c('gold', 4))
    cv.ellipse(5.9, 9.3, 8.1, 11.5, c('gold', 4))


def m_questgoal(cv):
    cv.ellipse(2.8, 2.8, 11.2, 11.2, c('ember', 2))
    cv.ellipse(4.2, 4.2, 9.8, 9.8, PLATE[0])
    cv.ellipse(5.4, 5.4, 8.6, 8.6, c('ember', 4))
    cv.ellipse(6.3, 6.3, 7.7, 7.7, c('gold', 4))


POI = {'temple': m_temple, 'depot': m_depot, 'bank': m_bank, 'npc': m_npc, 'shop': m_shop, 'travel': m_travel,
       'bless': m_bless, 'craft': m_craft, 'guild': m_guild, 'portal': m_portal, 'boss': m_boss, 'dungeon': m_dungeon,
       'hunt': m_hunt, 'quest': m_quest, 'questgoal': m_questgoal}


def poi_icon(motif):
    cv = Canvas(14)
    plate(cv)
    motif(cv)
    return cv.done()


# ------------------------------------------------------------------------------------------------ hunt teleports (O568)
# Drawn in the 14 unit plate design; the highlighted ones on an 18 px canvas (the same design, drawn bigger) with a glow
# ring round the plate. The colours are the markers' meaning: ember gate (into a hunt), gold (the one to go back to),
# frost door (out of a hunt), a brighter frost when it is the hunt you are in.
def glow(cv, ramp):
    for i, (grow_by, alpha) in enumerate(((0.0, 70), (-0.8, 110))):
        g = c(ramp, 3)[:3] + (alpha,)
        cv.ellipse(-0.6 - grow_by, -0.6 - grow_by, 14.6 + grow_by, 14.6 + grow_by, g)


def m_gate(ramp, frame='stone', lo=3, hi=4):
    def draw(cv):
        cv.rect(3.0, 3.4, 4.8, 11.6, c(frame, lo))                   # the two posts
        cv.rect(9.2, 3.4, 11.0, 11.6, c(frame, lo))
        cv.poly([(3.0, 3.4), (7.0, 1.8), (11.0, 3.4), (11.0, 5.0), (3.0, 5.0)], c(frame, hi))   # the lintel
        cv.rect(4.8, 5.0, 9.2, 11.6, INK)                            # the opening
        cv.ellipse(5.4, 6.2, 8.6, 11.6, c(ramp, 2))                  # the glow inside
        cv.ellipse(6.1, 7.4, 7.9, 11.0, c(ramp, 4))
    return draw


def m_door(ramp, frame='stone', lo=3):
    def draw(cv):
        cv.rect(3.2, 2.4, 9.0, 11.8, c(frame, lo))                   # the frame
        cv.rect(4.2, 3.4, 8.0, 11.8, c(ramp, 1))                     # the door
        cv.rect(4.2, 3.4, 5.0, 11.8, c(ramp, 3))                     # lit from the left
        cv.ellipse(6.8, 7.2, 7.6, 8.0, c('gold', 4))                 # the handle
        cv.poly([(9.4, 6.2), (12.2, 7.6), (9.4, 9.0)], c(ramp, 4))   # the arrow out
        cv.rect(8.2, 7.1, 10.2, 8.1, c(ramp, 4))
    return draw


class Shifted:
    """draws the 14 unit design moved by dx units on a bigger canvas"""
    def __init__(self, base, dx):
        self.base, self.dx = base, dx

    def ellipse(self, x0, y0, x1, y1, fill):
        d = self.dx
        self.base.ellipse(x0 + d, y0 + d, x1 + d, y1 + d, fill)

    def rect(self, x0, y0, x1, y1, fill):
        d = self.dx
        self.base.rect(x0 + d, y0 + d, x1 + d, y1 + d, fill)

    def poly(self, pts, fill):
        self.base.poly([(x + self.dx, y + self.dx) for x, y in pts], fill)

    def line(self, pts, fill, w):
        self.base.line([(x + self.dx, y + self.dx) for x, y in pts], fill, w)


PAD = 2.2   # units of glow round the plate on an 18 px marker


def hunt_icon(motif, size, rim=None, halo=None):
    if size == 14:
        cv = Canvas(14)
        plate(cv)
        motif(cv)
        return cv.done()
    cv = Canvas(size, unit=14 + 2 * PAD)
    out = Shifted(cv, PAD)
    glow(out, halo)
    plate(out)
    out.ellipse(0.9, 0.9, 13.1, 13.1, rim)           # a thicker, brighter rim
    out.ellipse(1.9, 1.9, 12.1, 12.1, PLATE[0])
    out.ellipse(2.3, 2.1, 10.6, 9.6, PLATE[1])
    motif(out)
    return cv.done()


HUNT_ART = {
    'huntport': lambda: hunt_icon(m_gate('ember'), 14),
    'huntport_last': lambda: hunt_icon(m_gate('ember', 'gold', 2, 3), 18, rim=c('gold', 4), halo='gold'),
    'huntexit': lambda: hunt_icon(m_door('frost'), 14),
    'huntexit_here': lambda: hunt_icon(m_door('frost', 'frost', 3), 18, rim=c('frost', 3), halo='frost'),
}


# ------------------------------------------------------------------------------------------------ marks over NPC heads (O415)
# 16x24, a dark outline all round so they read on grass, stone and water. Gold ramp for the quests of the character,
# the stone ramp (grey) for a quest that waits for a level.
def bang(ramp):
    cv = Canvas(16, 24)
    stem = [(5.2, 2.2), (10.8, 2.2), (9.6, 15.0), (6.4, 15.0)]
    cv.poly(grow(stem, 1.4), INK)
    cv.ellipse(4.3, 16.3, 11.7, 23.7, INK)
    cv.poly(stem, c(ramp, 2))
    cv.poly([(5.2, 2.2), (8.0, 2.2), (7.4, 15.0), (6.4, 15.0)], c(ramp, 3))     # lit from the top left
    cv.poly([(9.4, 2.2), (10.8, 2.2), (9.6, 15.0), (8.8, 15.0)], c(ramp, 1))    # shaded right edge
    cv.ellipse(5.6, 17.4, 10.4, 22.2, c(ramp, 2))
    cv.ellipse(6.0, 17.6, 8.8, 20.4, c(ramp, 3))
    return cv.done()


def question(ramp):
    cv = Canvas(16, 24)
    cx, cy, r = 8.0, 7.4, 4.1
    pts = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in range(180, 411, 10)]
    pts += [(8.1, 13.2), (8.0, 15.0)]

    def stroke(width, fill, dx=0.0, dy=0.0):
        cv.line([(x + dx, y + dy) for x, y in pts], fill, width)
        for x, y in pts:
            cv.ellipse(x + dx - width / 2, y + dy - width / 2, x + dx + width / 2, y + dy + width / 2, fill)
    stroke(5.0, INK)
    cv.ellipse(4.3, 16.3, 11.7, 23.7, INK)
    stroke(2.8, c(ramp, 2))
    stroke(1.0, c(ramp, 3), -0.5, -0.4)                                          # lit from the top left
    cv.ellipse(5.6, 17.4, 10.4, 22.2, c(ramp, 2))
    cv.ellipse(6.0, 17.6, 8.8, 20.4, c(ramp, 3))
    return cv.done()


MARKS = {'npcmark_new': lambda: bang('gold'), 'npcmark_ready': lambda: question('gold'),
         'npcmark_locked': lambda: bang('stone')}


def all_art():
    out = {'party_pin': party_pin(), 'floor_up': floor_arrow(True), 'floor_down': floor_arrow(False)}
    for name, make in MARKS.items():
        out[name] = make()
    for name, angle in DIRS.items():
        out['party_arrow_' + name] = party_arrow(angle)
    for kind, motif in POI.items():
        out['poi_' + kind] = poi_icon(motif)
    for name, make in HUNT_ART.items():
        out[name] = make()
    return out


def sheet(art, path):
    names = sorted(art)
    cell, cellh = 64, 100
    img = Image.new('RGBA', (cell * 6, cellh * ((len(names) + 5) // 6)), (60, 70, 50, 255))
    for i, n in enumerate(names):
        a = art[n]
        if n.startswith('party_'):
            tint = Image.new('RGBA', a.size, (255, 157, 46, 255))
            a = Image.composite(Image.blend(a, tint, 0.0), a, a)
            r, g, b, al = a.split()
            a = Image.merge('RGBA', (r.point(lambda v: v * 255 // 255), g.point(lambda v: v * 157 // 255),
                                     b.point(lambda v: v * 46 // 255), al))
        big = a.resize((a.width * 4, a.height * 4), Image.NEAREST)
        img.alpha_composite(big, ((i % 6) * cell + 4, (i // 6) * cellh + 4))
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
