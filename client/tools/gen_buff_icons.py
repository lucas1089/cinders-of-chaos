#!/usr/bin/env python3
"""Pixel-art icons of the buff bar (client module game_buffbar), 26x26: the bar's cell size, drawn 1:1.

Run: python3 client/tools/gen_buff_icons.py [OUTDIR] [--sheet SHEET.png]
     default OUTDIR: client/overlay/data/images/game/buffs  ->  <name>.png, one per name of ICONS
     --sheet writes a labelled contact sheet (3x) of every icon as well

One icon for every key of the registry (server/data/lib/chaos_buffs.lua) and every "buff:<name>" it names; the registry
gives every entry a "buff:<name>" icon, and the client falls back to the key's icon for an older "spell:" / "cond:" spec.
The names are checked against the registry when it is found (a name without a drawing, or a drawing nobody uses, stops
the run).

The look follows the spell icons (the element ability icon sets in tools/spell_icon_art/): hard pixels, no
anti-aliasing, one colour ramp of five shades per element, light from the top left (lit top-left edges, shaded
bottom-right edges), a dark plate behind the motif and a two pixel frame. The frame tells buff from debuff:
  * buff    warm ember gold: outer line #b8923a (the client's buff border), a lit gold inner line, ember studs in the
            corners and a hot spot at the top;
  * debuff  blood red and corrupted: outer line #c9301f (the client's debuff border), a dark blood inner line with
            bright veins, thorns growing into the plate from the corners and a red vignette on the plate.
The client draws its own 1 px border over the outer line, so the icon looks the same with or without it.

Sources: the class buffs that come from a Chaos spell show that spell's own pixel-art icon (its cell of
spell_icon_art/spell_icons_32.png, found through game_chaosspells/spelldata.lua: the inner art area-averaged to the
plate) in the buff frame, so the bar matches the action bar. Everything else is drawn here: a motif is drawn at 4x in
palette slots, reduced to 26 px by majority (crisp pixels), shaded by the ramp, outlined and given a one pixel glow.
Our own art; deterministic. Needs Pillow."""
import os, re, sys
from collections import Counter
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'buffs')
REGISTRY = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_buffs.lua')
SPELLDATA = os.path.join(ROOT, 'client', 'overlay', 'modules', 'game_chaosspells', 'spelldata.lua')
SPELL_ART = os.path.join(HERE, 'spell_icon_art', 'spell_icons_32.png')

N = 26          # icon size (BuffMath.ICON_SIZE)
K = 4           # the motifs are drawn at K x and reduced by majority
IN0, IN1 = 2, 24  # the plate: pixels IN0 .. IN1-1 inside the two pixel frame

# ---------------------------------------------------------------- palette: ramps dark -> highlight
R = {
    'ember': [(92, 30, 12), (176, 62, 18), (240, 118, 28), (255, 184, 60), (255, 238, 150)],
    'gold': [(96, 62, 16), (168, 116, 32), (222, 170, 60), (250, 214, 112), (255, 246, 200)],
    'blood': [(70, 6, 14), (138, 15, 30), (206, 22, 36), (250, 60, 62), (255, 150, 136)],
    'frost': [(20, 52, 110), (40, 110, 190), (96, 180, 240), (170, 226, 255), (240, 252, 255)],
    'water': [(12, 40, 96), (20, 90, 170), (40, 150, 230), (110, 210, 255), (220, 250, 255)],
    'poison': [(30, 64, 10), (70, 130, 20), (130, 200, 30), (196, 242, 70), (240, 255, 170)],
    'nature': [(14, 64, 40), (30, 120, 60), (70, 180, 70), (140, 230, 90), (220, 255, 180)],
    'arcane': [(50, 18, 90), (98, 40, 160), (150, 80, 230), (200, 140, 255), (245, 222, 255)],
    'energy': [(30, 30, 110), (60, 70, 200), (110, 140, 255), (180, 210, 255), (245, 250, 255)],
    'shadow': [(30, 20, 46), (64, 44, 92), (108, 84, 140), (160, 140, 196), (222, 212, 240)],
    'steel': [(40, 40, 48), (86, 86, 98), (140, 140, 152), (196, 196, 206), (250, 250, 255)],
    'bone': [(80, 66, 46), (140, 122, 92), (198, 182, 148), (232, 220, 190), (255, 250, 236)],
    'necro': [(20, 50, 40), (40, 100, 70), (90, 170, 100), (160, 230, 140), (230, 255, 210)],
    'holy': [(110, 80, 20), (190, 150, 50), (245, 210, 100), (255, 240, 170), (255, 255, 240)],
    'wood': [(60, 32, 14), (110, 62, 26), (160, 98, 44), (206, 146, 78), (240, 200, 140)],
    'coal': [(10, 8, 12), (26, 22, 30), (46, 40, 52), (72, 64, 80), (120, 110, 130)],
    'obsidian': [(16, 12, 20), (40, 34, 48), (70, 62, 82), (110, 100, 124), (170, 160, 186)],
    'wind': [(30, 70, 80), (60, 130, 140), (120, 200, 200), (190, 240, 236), (245, 255, 252)],
}
INK = (12, 6, 12)
WHITE = (255, 250, 240)

FRAME = {
    'buff': {'outer': (184, 146, 58), 'lit': (250, 214, 112), 'shade': (168, 116, 32), 'hot': (255, 246, 200),
             'stud': (255, 184, 60), 'plate': (16, 12, 14), 'tint': (60, 36, 12)},
    'debuff': {'outer': (201, 48, 31), 'lit': (138, 15, 30), 'shade': (82, 8, 16), 'hot': (250, 60, 62),
               'stud': (255, 96, 70), 'plate': (14, 6, 10), 'tint': (84, 8, 16)},
}


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


# ---------------------------------------------------------------- slots of the motif layer
# 1/2/3: ramp A shaded / highlight / dark, 4/5/6: ramp B, 11/12/13: ramp C, 7 white, 8 ink, 9: ramp A light (flat),
# 14: ramp A shaded on every other pixel (a see-through dither), 15: ramp B light (flat)
A, AH, AD, B, BH, BD, W, KK, AL, C, CH, CD, DITH, BL = 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15
GROUP = {1: 'A', 2: 'A', 3: 'A', 9: 'A', 14: 'A', 4: 'B', 5: 'B', 6: 'B', 15: 'B', 11: 'C', 12: 'C', 13: 'C'}


class Canvas:
    """A motif: vector shapes in icon pixels (drawn at K x into palette slots) and pixel stamps (1 x, on top)."""

    def __init__(self):
        self.big = Image.new('L', (N * K, N * K), 0)
        self.d = ImageDraw.Draw(self.big)
        self.stamps = []

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
        self.d.line(self._p(pts), fill=v, width=max(1, int(round(w * K))), joint='curve')

    def arc(self, x0, y0, x1, y1, a0, a1, v, w=1.0):
        self.d.arc((x0 * K, y0 * K, x1 * K - 1, y1 * K - 1), a0, a1, fill=v, width=max(1, int(round(w * K))))

    def px(self, rows, x, y, keys):
        """a pixel stamp: rows of characters, `keys` maps a character to a slot ('.' and ' ' are left alone)"""
        self.stamps.append((rows, x, y, keys))

    def grid(self):
        src = self.big.load()
        g = [[0] * N for _ in range(N)]
        for y in range(N):
            for x in range(N):
                c = Counter(src[x * K + i, y * K + j] for i in range(K) for j in range(K))
                v, n = max(((v, n) for v, n in c.items() if v), key=lambda t: (t[1], t[0]), default=(0, 0))
                if n * 2 >= K * K - 2:
                    g[y][x] = v
        for rows, x0, y0, keys in self.stamps:
            for j, row in enumerate(rows):
                for i, ch in enumerate(row):
                    if ch in keys and 0 <= x0 + i < N and 0 <= y0 + j < N:
                        g[y0 + j][x0 + i] = keys[ch]
        return g


# ---------------------------------------------------------------- plate, frame, shading
def plate(kind, ramp):
    f = FRAME[kind]
    im = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    p = im.load()
    base = mix(f['plate'], ramp[0], 0.22)
    mid = mix(f['plate'], ramp[0], 0.45)
    core = mix(f['plate'], ramp[0], 0.7)
    for y in range(IN0, IN1):
        for x in range(IN0, IN1):
            e = min(x - IN0, y - IN0, IN1 - 1 - x, IN1 - 1 - y)
            r = max(abs(x - 12.5), abs(y - 12.5)) + 0.35 * min(abs(x - 12.5), abs(y - 12.5))
            c = core if r < 6.5 else mid if r < 9.5 else base
            if e == 0:
                c = mix(c, (0, 0, 0), 0.45)   # the frame's shadow on the plate
            if kind == 'debuff' and r >= 9.5 and (x + y) % 2 == 0:
                c = mix(c, f['tint'], 0.55)   # the red vignette
            p[x, y] = c + (255,)
    return im


def frame(im, kind):
    f = FRAME[kind]
    p = im.load()
    for i in range(N):
        for (x, y) in ((i, 0), (i, N - 1), (0, i), (N - 1, i)):
            p[x, y] = f['outer'] + (255,)
    for i in range(1, N - 1):
        p[i, 1] = f['lit'] + (255,)
        p[1, i] = f['lit'] + (255,)
        p[i, N - 2] = f['shade'] + (255,)
        p[N - 2, i] = f['shade'] + (255,)
    for c in ((0, 0), (N - 1, 0), (0, N - 1), (N - 1, N - 1)):
        p[c] = (0, 0, 0, 0)
    if kind == 'buff':
        for x in range(10, 16):
            p[x, 1] = f['hot'] + (255,)
        p[9, 1] = p[16, 1] = mix(f['hot'], f['lit'], 0.5) + (255,)
        for (x, y) in ((1, 1), (N - 2, 1), (1, N - 2), (N - 2, N - 2)):
            p[x, y] = f['stud'] + (255,)
        p[2, 2] = mix(f['stud'], (0, 0, 0), 0.35) + (255,)
    else:
        for (x, y) in ((6, 1), (7, 1), (1, 17), (1, 18), (19, N - 2), (N - 2, 8), (N - 2, 9), (12, N - 2)):
            p[x, y] = f['hot'] + (255,)    # veins in the dark blood line
        thorn = f['outer']
        for (cx, cy, sx, sy) in ((2, 2, 1, 1), (N - 3, 2, -1, 1), (2, N - 3, 1, -1), (N - 3, N - 3, -1, -1)):
            for (dx, dy) in ((0, 0), (1, 0), (0, 1), (1, 1), (2, 0), (0, 2)):
                p[cx + sx * dx, cy + sy * dy] = (thorn if dx + dy < 2 else f['lit']) + (255,)
            p[cx + sx * 2, cy + sy * 2] = f['hot'] + (255,)
    return im


def paint(im, g, ramps, glow=True):
    """the motif grid onto the plate: ramp shading, ink outline, a one pixel glow"""
    p = im.load()
    rA, rB, rC = ramps[0], ramps[1] if len(ramps) > 1 else ramps[0], ramps[2] if len(ramps) > 2 else ramps[0]
    rampOf = {'A': rA, 'B': rB, 'C': rC}

    def at(x, y):
        return g[y][x] if 0 <= x < N and 0 <= y < N else 0

    def inside(x, y):
        return IN0 <= x < IN1 and IN0 <= y < IN1

    solid = [[at(x, y) != 0 and not (at(x, y) == DITH and (x + y) % 2) for x in range(N)] for y in range(N)]
    # glow (distance 2) then outline (distance 1), only on the plate
    for y in range(IN0, IN1):
        for x in range(IN0, IN1):
            if solid[y][x]:
                continue
            near1 = any(0 <= x + dx < N and 0 <= y + dy < N and solid[y + dy][x + dx]
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            near2 = any(0 <= x + dx < N and 0 <= y + dy < N and solid[y + dy][x + dx]
                        for dx in range(-2, 3) for dy in range(-2, 3) if abs(dx) + abs(dy) <= 3)
            if near1:
                p[x, y] = INK + (255,)
            elif glow and near2:
                p[x, y] = mix(p[x, y][:3], rA[1], 0.45) + (255,)
    for y in range(N):
        for x in range(N):
            v = g[y][x]
            if not v or not solid[y][x] or not inside(x, y):
                continue
            if v == W:
                c = WHITE
            elif v == KK:
                c = INK
            else:
                grp = GROUP[v]
                r = rampOf[grp]
                if v in (AH, BH, CH):
                    c = r[4]
                elif v in (AD, BD, CD):
                    c = r[1]
                elif v in (AL, BL):
                    c = r[3]
                else:
                    same = lambda xx, yy: GROUP.get(at(xx, yy)) == grp and solid[yy][xx] if 0 <= xx < N and 0 <= yy < N else False  # noqa: E731
                    if not same(x, y - 1) or not same(x - 1, y):
                        c = r[3]
                    elif not same(x, y + 1) or not same(x + 1, y):
                        c = r[1]
                    else:
                        c = r[2]
            p[x, y] = c + (255,)
    return im


# ---------------------------------------------------------------- motifs (icon pixels; the plate is 2..24)
def star(c, cx, cy, r1, r2, v, n=5, rot=-90):
    import math
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180.0 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    c.poly(pts, v)


def m_up_arrow(c, x=13, y=4, w=1.0, v=A):
    c.poly([(x, y), (x + 7 * w, y + 7), (x + 3 * w, y + 7), (x + 3 * w, y + 16), (x - 3 * w, y + 16), (x - 3 * w, y + 7),
            (x - 7 * w, y + 7)], v)


SKULL = ['....######....',
         '..##########..',
         '.###hh#######.',
         '.##hh########.',
         '##############',
         '##kkk####kkk##',
         '##kkkk##kkkk##',
         '##kkk####kkk##',
         '.######k#####.',
         '..####kkk####.',
         '...#########..',
         '...#k#k#k#k#..',
         '...#########..',
         '....#######...']


def skull(c, x=6, y=5, hi=AH, eye=KK):
    c.px(SKULL, x, y, {'#': A, 'h': hi, 'k': eye})


def m_world_xp(c):
    c.ell(4, 6, 22, 24, B)                                      # a globe
    c.arc(4, 6, 22, 24, 0, 360, BD, 1)
    c.line([(5, 15), (21, 15)], BD, 1); c.line([(13, 7), (13, 23)], BD, 1)
    c.arc(8, 6, 18, 24, 90, 270, BD, 1); c.arc(8, 6, 18, 24, 270, 90, BD, 1)
    m_up_arrow(c, 13, 3, 0.9, A)


def m_world_loot(c):
    c.rect(4, 13, 22, 22, B)                                    # the chest
    c.poly([(4, 13), (6, 8), (20, 8), (22, 13)], BD)              # the open lid
    c.rect(4, 15, 22, 17, A); c.rect(12, 14, 15, 19, A)           # gold bands, the lock
    for (x, y) in ((7, 9), (11, 7), (15, 8), (18, 10), (9, 11), (16, 11), (13, 10)):
        c.ell(x - 1.6, y - 1.6, x + 1.6, y + 1.6, A)             # coins heaped in it
    c.px(['.h.', 'hWh', '.h.'], 18, 3, {'h': AH, 'W': W})
    c.px(['h'], 6, 5, {'h': AH})


def m_world_skill(c):
    c.line([(5, 21), (19, 7)], A, 2.2); c.poly([(19, 7), (21, 4), (22, 5)], A)     # a sword
    c.line([(8, 14), (12, 18)], AD, 1.6)
    c.line([(21, 21), (8, 8)], B, 1.8)                                            # a staff
    c.ell(4.5, 4.5, 9.5, 9.5, BH)
    c.px(['.W.', 'W.W', '.W.'], 5, 5, {'W': W})


def m_world_hunt(c):
    skull(c, 6, 10)                                                               # a monster skull
    star(c, 7.5, 6, 3.6, 1.5, A)                                                  # a gold (rare) and a blue
    star(c, 18.5, 6, 3.6, 1.5, B)                                                 # (magic) star over it
    c.px(['W'], 7, 4, {'W': W})


def m_victory(c):
    for side in (-1, 1):                                          # a laurel wreath
        for i, (dx, dy) in enumerate(((7, 18), (8.5, 14.5), (8.6, 10.5), (7.5, 7))):
            x = 13 + side * dx
            c.ell(x - 1.8, dy - 1.2, x + 1.8, dy + 1.8, A)
        c.arc(13 - 9, 4, 13 + 9, 23, 100 if side < 0 else -10, 190 if side < 0 else 80, AD, 1)
    c.poly([(13, 4), (15, 8), (15, 18), (11, 18), (11, 8)], B)        # a sword through it
    c.rect(8, 18, 18, 20, C); c.rect(12, 20, 14, 23, C)


def m_golden_hour(c):
    c.rect(6, 3, 20, 5, B); c.rect(6, 21, 20, 23, B)               # an hourglass in a wooden frame
    c.poly([(8, 5), (18, 5), (14, 13), (18, 21), (8, 21), (12, 13)], AD)
    c.poly([(9.5, 7), (16.5, 7), (13, 12)], A)                      # gold sand above and below
    c.poly([(13, 15), (17, 21), (9, 21)], A)
    c.line([(13, 12), (13, 18)], AH, 0.6)
    c.px(['W'], 11, 8, {'W': W})


def m_chaos_storm(c):
    c.ell(3, 6, 12, 14, B); c.ell(8, 3, 19, 13, B); c.ell(14, 6, 23, 14, B); c.rect(5, 10, 21, 14, B)   # a cloud
    c.poly([(14, 12), (9, 18), (13, 18), (10, 24), (18, 16), (14, 16), (17, 12)], A)                   # a bolt
    c.px(['h', 'h'], 15, 13, {'h': AH})


def m_event(c):
    c.line([(6, 3), (6, 23)], C, 1.6)                               # a banner on a pole
    c.poly([(7, 4), (21, 4), (18, 9), (21, 14), (7, 14)], B)
    star(c, 13, 9, 4, 1.8, A)
    c.ell(4.8, 2, 7.6, 4.8, A)


def m_double_xp(c):
    c.px(['.#####.',
          '##hh###',
          '##...##',
          '.....##',
          '....##.',
          '...##..',
          '..##...',
          '.##....',
          '#######',
          '#######'], 4, 9, {'#': A, 'h': AH})
    c.px(['##...##',
          '.##.##.',
          '..###..',
          '.##.##.',
          '##...##'], 13, 14, {'#': B})
    c.poly([(18, 3), (22, 8), (20, 8), (20, 12), (16, 12), (16, 8), (14, 8)], C)


def m_trial_stacks(c):
    for i, y in enumerate((5, 11, 17)):                            # three rank chevrons
        c.poly([(4, y + 5), (13, y), (22, y + 5), (22, y + 8), (13, y + 3), (4, y + 8)], A if i else B)


def m_chi(c):
    c.ell(6, 6, 20, 20, A)                                          # an orb with a turning swirl
    c.arc(8, 8, 18, 18, 200, 470, AH, 1.4)
    c.ell(11.5, 11.5, 14.5, 14.5, W)
    for (x, y) in ((4, 5), (21, 6), (5, 21), (21, 20)):
        c.ell(x - 1.4, y - 1.4, x + 1.4, y + 1.4, B)


def m_rage(c):
    c.ell(6, 7, 20, 21, A)                                          # a horned helm
    c.rect(6, 14, 20, 21, A)
    c.poly([(7, 10), (3, 9), (2, 3), (5, 7), (8, 8)], B)              # horns
    c.poly([(19, 10), (23, 9), (24, 3), (21, 7), (18, 8)], B)
    c.rect(8, 14, 18, 16, KK)                                        # the visor and the burning eyes
    c.rect(12, 16, 14, 21, KK)
    c.px(['hh....hh'], 9, 14, {'h': CH})
    c.px(['c', 'c'], 13, 18, {'c': CD})


def shield(c, x0=6, y0=4, x1=20, y1=23, v=A):
    cx = (x0 + x1) / 2
    c.poly([(x0, y0), (x1, y0), (x1, y0 + (y1 - y0) * 0.5), (cx, y1), (x0, y0 + (y1 - y0) * 0.5)], v)


def m_reprisal(c):
    shield(c, 4, 4, 17, 22, A)
    c.line([(10.5, 6), (10.5, 19)], AD, 1); c.line([(5, 11), (16, 11)], AD, 1)
    c.arc(9, 4, 24, 20, 300, 80, B, 2)                                # an arrow bent back
    c.poly([(16, 20), (21, 16), (21, 22)], B)
    c.poly([(19, 5), (23, 4), (22, 8)], BH)


def m_templar_aura(c):
    c.arc(3, 3, 23, 23, 0, 360, B, 1.3)                               # the aura
    c.arc(6, 6, 20, 20, 0, 360, BD, 1)
    c.rect(11.5, 5, 14.5, 21, A); c.rect(7, 9, 19, 12, A)              # a cross
    c.px(['W'], 12, 6, {'W': W})


def m_stunned(c):
    c.ell(5, 14, 21, 21, B)                                         # a ring of stars over a head
    c.ell(7, 15.5, 19, 19.5, 0)
    star(c, 7, 9, 4.2, 1.8, A); star(c, 19, 9, 4.2, 1.8, A); star(c, 13, 5.5, 3.2, 1.4, AL)


def m_stun_immune(c):
    shield(c, 5, 3, 21, 23, B)
    star(c, 13, 11.5, 6, 2.6, A)
    c.px(['W'], 12, 8, {'W': W})


def m_focus(c):
    c.arc(3, 3, 23, 23, 0, 360, B, 1)                                 # a reticle
    for (x0, y0, x1, y1) in ((13, 2, 13, 7), (13, 19, 13, 24), (2, 13, 7, 13), (19, 13, 24, 13)):
        c.line([(x0, y0), (x1, y1)], B, 1)
    c.poly([(6, 13), (10, 9), (16, 9), (20, 13), (16, 17), (10, 17)], A)   # an eye in it
    c.ell(10.5, 10.5, 15.5, 15.5, KK)
    c.px(['W'], 11, 11, {'W': W})


def m_haste(c):
    c.poly([(9, 6), (15, 6), (15, 15), (21, 18), (21, 21), (7, 21), (7, 16)], B)        # a boot
    c.rect(8, 6, 16, 8, BD)
    for i, y in enumerate((5, 8.5, 12)):                                               # a wing on its heel
        c.poly([(9, y + 1.5), (2 + i, y - 1), (3 + i, y + 2), (9, y + 4)], A)
    c.line([(18, 6), (24, 6)], AL, 0.8); c.line([(19, 10), (24, 10)], AL, 0.8)


def m_regen(c):
    c.ell(4, 6, 14, 15, A); c.ell(12, 6, 22, 15, A)                     # a heart
    c.poly([(4.5, 12), (21.5, 12), (13, 22)], A)
    c.rect(11.5, 9, 14.5, 18, W); c.rect(9, 12, 17, 15, W)             # a cross of light
    c.px(['h'], 7, 8, {'h': AH})


def m_fed(c):
    c.ell(4, 4, 17, 16, A)                                             # a roast leg
    c.poly([(8, 13), (15, 6), (19, 15), (16, 18)], A)
    c.line([(15, 15), (21, 21)], B, 2.2)                                # its bone
    c.ell(18.5, 19.5, 22, 23, B); c.ell(20, 18, 23.5, 21.5, B)
    c.px(['hh', 'h.'], 7, 6, {'h': AH})


def m_manashield(c):
    c.ell(3, 3, 23, 23, B); c.ell(5, 5, 21, 21, 0)                     # a bubble
    shield(c, 8, 7, 18, 20, A)
    c.line([(13, 9), (13, 17)], AH, 0.8)
    c.px(['WW', 'W.'], 6, 6, {'W': W})


def m_invisible(c):
    c.ell(8, 3, 18, 13, A)                                              # a hooded figure fading out downwards
    c.poly([(8, 9), (18, 9), (19, 15), (7, 15)], A)
    c.poly([(7, 15), (19, 15), (22, 24), (4, 24)], DITH)
    c.rect(10, 7, 16, 12, KK)
    c.px(['W..W'], 11, 9, {'W': AH})


def m_light(c):
    c.rect(9, 4, 17, 6, B); c.rect(12, 2, 14, 4, B)                   # a lantern
    c.rect(8, 6, 18, 20, BD); c.rect(9.5, 7, 16.5, 19, 0)
    c.rect(7, 20, 19, 22, B)
    c.poly([(13, 8), (16, 14), (15, 18), (11, 18), (10, 14)], A)      # its flame
    c.poly([(13, 12), (14.6, 15.5), (13, 18), (11.4, 15.5)], AH)


def m_spellbuff(c):
    c.rect(11, 4, 15, 9, B)                                            # a potion
    c.ell(6, 8, 20, 23, B)
    c.ell(7.5, 12, 18.5, 21.5, A)
    c.rect(10, 3, 16, 5, C)
    c.px(['.W.', 'WWW', '.W.', '.W.'], 12, 13, {'W': W})


def m_poison(c):
    c.poly([(13, 2), (21, 14), (5, 14)], A); c.ell(5, 8, 21, 24, A)      # a venom drop with a skull face
    c.rect(8, 13, 12, 16, KK); c.rect(14, 13, 18, 16, KK); c.rect(12, 17, 14, 19, KK)
    c.px(['h', 'h'], 9, 10, {'h': AH})
    c.ell(19, 3, 23, 7, B); c.ell(3, 4, 6, 7, B)


def m_burning(c):
    c.poly([(13, 2), (18, 9), (20, 6), (22, 14), (20, 21), (13, 24), (6, 21), (4, 14), (6, 8), (9, 11)], A)   # a flame
    c.poly([(13, 9), (17, 15), (16, 21), (13, 23), (10, 21), (9, 16)], AL)
    c.poly([(13, 14), (15, 18), (13, 22), (11, 18)], AH)


def m_energy(c):
    c.poly([(15, 2), (6, 14), (12, 14), (9, 24), (20, 10), (14, 10), (18, 2)], A)   # a bolt
    c.px(['W', 'W'], 14, 4, {'W': W})
    c.px(['h'], 4, 6, {'h': AH}); c.px(['h'], 21, 19, {'h': AH})


def drop(c, x, y, s, v):
    c.poly([(x, y), (x + 3.6 * s, y + 6 * s), (x - 3.6 * s, y + 6 * s)], v)
    c.ell(x - 4 * s, y + 3.6 * s, x + 4 * s, y + 11.5 * s, v)


def m_bleeding(c):
    drop(c, 10, 3, 1.1, A); drop(c, 18, 10, 0.75, A); drop(c, 6, 16, 0.55, A)       # drops of blood
    c.px(['h', 'h'], 8, 10, {'h': AH})
    c.ell(3, 21, 23, 24, AD)


def m_drowning(c):
    for (x, y, r) in ((9, 9, 3.4), (16, 5, 2.2), (17, 12, 1.8), (11, 3, 1.2)):      # bubbles
        c.ell(x - r, y - r, x + r, y + r, A); c.ell(x - r + 1, y - r + 1, x + r - 1, y + r - 1, 0)
    for y in (16, 20):                                                                # waves
        c.line([(3, y + 2), (6, y), (9, y + 2), (12, y), (15, y + 2), (18, y), (21, y + 2), (24, y)], B, 1.6)


def m_freezing(c):
    import math
    for i in range(6):                                                                # a snowflake
        a = math.radians(i * 60 - 90)
        x1, y1 = 13 + 10 * math.cos(a), 13 + 10 * math.sin(a)
        c.line([(13, 13), (x1, y1)], A, 1.6)
        for side in (-1, 1):
            b = a + side * math.radians(45)
            mx, my = 13 + 6 * math.cos(a), 13 + 6 * math.sin(a)
            c.line([(mx, my), (mx + 3.2 * math.cos(b), my + 3.2 * math.sin(b))], A, 1)
    c.ell(10.5, 10.5, 15.5, 15.5, AH)


def m_dazzled(c):
    import math
    for i in range(8):                                                                # rays
        a = math.radians(i * 45 + 22.5)
        c.line([(13 + 7 * math.cos(a), 13 + 7 * math.sin(a)), (13 + 11 * math.cos(a), 13 + 11 * math.sin(a))], A, 1.4)
    c.poly([(4, 13), (9, 8), (17, 8), (22, 13), (17, 18), (9, 18)], B)                  # a blinded eye
    c.ell(9.5, 9.5, 16.5, 16.5, W)
    c.line([(6, 18), (20, 8)], KK, 1)


def m_cursed(c):
    skull(c, 6, 7)
    c.arc(2, 1, 14, 11, 180, 330, B, 1.2); c.arc(12, 0, 24, 12, 200, 360, B, 1.2)       # wisps
    c.px(['c'], 3, 6, {'c': BH}); c.px(['c'], 22, 6, {'c': BH})


def m_paralyze(c):
    c.ell(12, 12, 23, 23, A)                                                           # a ball and chain
    for (x, y) in ((5, 5), (8, 8), (11, 11)):
        c.ell(x - 1.8, y - 1.8, x + 1.8, y + 1.8, B); c.ell(x - 0.7, y - 0.7, x + 0.7, y + 0.7, 0)
    c.arc(2, 2, 9, 9, 0, 360, B, 1.4)
    c.px(['hh', 'h.'], 15, 14, {'h': AH})


def m_drunk(c):
    c.rect(5, 9, 17, 23, B)                                                            # a tankard
    c.rect(5, 12, 17, 13, BD); c.rect(5, 19, 17, 20, BD)
    c.arc(14, 11, 22, 21, 270, 90, B, 1.6)
    c.ell(4, 5, 10, 11, A); c.ell(8, 4, 14, 10, A); c.ell(12, 5, 18, 11, A)              # its foam
    c.ell(18, 2, 21, 5, A); c.ell(20, 6, 22, 8, A)


def m_pacified(c):
    c.poly([(12, 4), (14, 2), (16, 4), (16, 15), (12, 15)], A)                            # a sword ...
    c.rect(8, 15, 20, 17, B); c.rect(12.5, 17, 15.5, 22, B)
    c.arc(3, 3, 24, 24, 0, 360, C, 2)                                                      # ... that is forbidden
    c.line([(6.5, 20.5), (20.5, 6.5)], C, 2)


def m_muted(c):
    c.poly([(3, 8), (13, 10), (23, 8), (23, 20), (13, 22), (3, 20)], A)                     # an open spell book
    c.poly([(4.5, 7), (12.5, 9), (12.5, 19.5), (4.5, 18)], C)                               # its pages
    c.poly([(13.5, 9), (21.5, 7), (21.5, 18), (13.5, 19.5)], C)
    c.line([(3, 19), (23, 5)], B, 1.6)                                                     # chained shut
    c.rect(10, 12, 17, 19, B); c.arc(11, 8, 16.5, 15, 180, 360, B, 1.3)
    c.rect(12.5, 14.5, 14.5, 17, KK)


def m_infight(c):
    for flip in (False, True):                                                           # crossed swords
        sx = (lambda x: 26 - x) if flip else (lambda x: x)
        c.line([(sx(5), 4), (sx(18), 17)], A, 1.8)
        c.poly([(sx(4), 3), (sx(7), 4), (sx(5), 6)], A)
        c.line([(sx(15), 20), (sx(21), 14)], B, 1.4)
        c.line([(sx(19), 19), (sx(22), 22)], B, 1.6)
    c.px(['c', 'c'], 12, 13, {'c': CH})


def m_skull(c):
    skull(c, 6, 6)


def m_self_found(c):
    c.rect(4, 13, 22, 22, B)                                    # a closed chest, chained shut
    c.poly([(4, 13), (6, 9), (20, 9), (22, 13)], BD)
    c.rect(4, 15, 22, 16, A); c.rect(11, 13, 15, 20, A)           # gold bands, a padlock
    c.ell(11.5, 10, 14.5, 14, C); c.ell(12.4, 11, 13.6, 13, 0)   # the shackle
    c.px(['k', 'k'], 13, 16, {'k': KK})                           # the keyhole
    star(c, 13, 5, 3.6, 1.5, AH)                                  # one star above: found alone
    c.px(['W'], 13, 4, {'W': W})


def m_hardcore_ward(c):
    shield(c, 4, 3, 22, 24, B)                                    # a ward shield with a skull: one life, guarded
    shield(c, 6, 5, 20, 21, BD)
    c.px(['.#####.',
          '#######',
          '#kk#kk#',
          '#kk#kk#',
          '.##k##.',
          '..###..',
          '..#.#..'], 10, 8, {'#': A, 'k': KK})
    c.px(['h'], 11, 9, {'h': AH})


def m_skull_black(c):
    skull(c, 6, 6, eye=C)


# Ember Blessings (server blessings.lua): the blessing's motif and a small ember flame in the lower right (ramp C)
def ember_mark(c, x=19, y=16):
    c.poly([(x, y), (x + 3, y + 4), (x + 4, y + 2.5), (x + 4.5, y + 6), (x + 2.5, y + 8.5), (x - 0.5, y + 8.5),
            (x - 2.5, y + 6), (x - 2, y + 3)], C)
    c.poly([(x + 0.5, y + 4), (x + 2, y + 6.5), (x + 0.8, y + 8), (x - 0.8, y + 6.5)], CH)


def m_blessing_xp(c):
    c.poly([(3, 12), (8, 7), (18, 7), (23, 12), (18, 17), (8, 17)], B)       # an open eye of insight
    c.ell(9, 8, 17, 16, A); c.ell(11, 10, 15, 14, KK)
    c.px(['W'], 11, 10, {'W': W})
    m_up_arrow(c, 13, 1, 0.45, AL)
    ember_mark(c, 19, 15)


def m_blessing_gold(c):
    for i, (x, y) in enumerate(((5, 17), (5, 14), (5, 11), (12, 18), (12, 15))):   # stacks of coins
        c.ell(x, y, x + 8, y + 4, A); c.line([(x + 1, y + 2), (x + 7, y + 2)], AD, 0.6)
    c.ell(12, 4, 20, 12, A); c.ell(14, 6, 18, 10, AD)                              # one coin standing
    c.px(['W'], 14, 5, {'W': W})
    ember_mark(c, 20, 15)


def m_blessing_damage(c):
    c.line([(5, 21), (18, 8)], B, 2.4); c.poly([(18, 8), (22, 3), (23, 4), (19, 9)], B)   # a sword
    c.line([(6, 14), (12, 20)], BD, 1.6)
    c.line([(7, 19), (17, 9)], BH, 0.6)
    c.poly([(16, 12), (14, 5), (18, 8), (20, 3), (22, 10), (19, 14)], A)                  # flames along the blade
    ember_mark(c, 19, 15)


def m_blessing_ward(c):
    shield(c, 4, 3, 20, 23, B)                                                     # a shield with an ember on it
    shield(c, 6, 5, 18, 20, BD)
    c.poly([(12, 7), (15, 12), (14, 17), (12, 18), (10, 17), (9, 12)], A)
    c.poly([(12, 12), (13, 15), (12, 17), (11, 15)], AH)
    ember_mark(c, 20, 15)


def m_blessing_speed(c):
    for i, y in enumerate((5, 10, 15)):                                            # wind streaks and chevrons
        c.poly([(4 + i, y), (10 + i, y + 3), (4 + i, y + 6), (6 + i, y + 3)], A)
        c.poly([(11 + i, y), (17 + i, y + 3), (11 + i, y + 6), (13 + i, y + 3)], B)
    c.line([(3, 22), (13, 22)], AL, 0.8)
    ember_mark(c, 20, 15)


def m_blessing_regen(c):
    c.ell(3, 5, 12, 13, A); c.ell(10, 5, 19, 13, A)                                # a heart and a mana drop
    c.poly([(3.5, 10), (18.5, 10), (11, 19)], A)
    c.rect(9.5, 7, 12.5, 15, W); c.rect(7, 9.5, 15, 12.5, W)
    drop(c, 17, 11, 0.6, B)
    ember_mark(c, 20, 15)


def m_blessing_crit(c):
    c.arc(3, 3, 21, 21, 0, 360, B, 1.2)                                            # a reticle with a burst in it
    for (x0, y0, x1, y1) in ((12, 2, 12, 6), (12, 18, 12, 22), (2, 12, 6, 12), (18, 12, 22, 12)):
        c.line([(x0, y0), (x1, y1)], B, 1)
    star(c, 12, 12, 6, 2.4, A, n=8)
    c.px(['W'], 12, 12, {'W': W})
    ember_mark(c, 20, 15)


def m_blessing_loot(c):
    c.ell(4, 9, 19, 23, B)                                                         # a full sack, tied
    c.poly([(8, 5), (15, 5), (13, 10), (10, 10)], B)
    c.rect(8, 9, 15, 11, BD)
    c.ell(9, 3, 14, 6, A); c.ell(15, 2, 19, 6, A)                                  # coins spilling from it
    c.px(['h'], 7, 13, {'h': BH})
    ember_mark(c, 20, 15)


def m_blessing_rarity(c):
    c.poly([(7, 5), (17, 5), (21, 10), (12, 22), (3, 10)], A)                       # a cut gem
    c.poly([(7, 5), (17, 5), (15, 10), (9, 10)], AL)
    c.poly([(3, 10), (9, 10), (12, 22)], AD)
    c.line([(15, 10), (12, 22)], AD, 0.6)
    c.px(['W.', '.W'], 8, 6, {'W': W})
    ember_mark(c, 20, 15)


def m_blessing_orb(c):
    c.ell(4, 4, 19, 19, A)                                                         # a glowing orb on an anvil
    c.arc(6, 6, 17, 17, 200, 320, AH, 1.2)
    c.ell(9, 9, 14, 14, AL)
    c.rect(3, 19, 18, 21, B); c.rect(7, 21, 14, 24, BD)
    c.px(['W'], 8, 7, {'W': W})
    ember_mark(c, 20, 14)


# Professions (server professions.lua): a pick and a sickle crossed over a gold arrow (gathering -> experience)
def m_professions(c):
    c.line([(5, 21), (18, 6)], B, 1.7)                                             # the pick's handle
    c.arc(9, 2, 25, 14, 200, 335, A, 2.2)                                          # its head
    c.px(['h'], 17, 5, {'h': AH})
    c.arc(2, 4, 16, 18, 150, 320, A, 1.8)                                          # the sickle's blade
    c.line([(14, 14), (20, 21)], B, 1.7)                                           # its handle
    c.px(['W'], 5, 7, {'W': W})
    c.poly([(13, 15), (17.5, 19.5), (15, 19.5), (15, 23), (11, 23), (11, 19.5), (8.5, 19.5)], C)   # a small gold arrow
    c.px(['h'], 13, 16, {'h': CH})


# the vigils (server vigils.lua): a banner on a pole (ramp A the cloth, B the pole) with the vigil's emblem (ramp C)
def vigil_banner(c):
    c.line([(5.5, 4), (5.5, 24)], B, 1.6)                                          # the pole and its finial
    c.ell(3.5, 2, 7.5, 6, BH)
    c.poly([(7, 4), (22, 4), (22, 17), (14.5, 22), (7, 17)], A)                   # the cloth, a point at the bottom
    c.px(['hhhhhhhhhhhhh'], 8, 5, {'h': AH})


def m_vigil_wrath(c):
    vigil_banner(c)
    c.poly([(14.5, 6.5), (18.5, 12), (17.5, 17), (11.5, 17), (10.5, 12)], C)      # a flame
    c.poly([(14.5, 11), (16, 14), (14.5, 17), (13, 14)], CH)


def m_vigil_iron(c):
    vigil_banner(c)
    shield(c, 10, 7, 19, 19, C)                                                    # a shield
    c.line([(14.5, 8.5), (14.5, 17)], CD, 0.8)


def m_vigil_haste(c):
    vigil_banner(c)
    for x in (9, 14):                                                              # two chevrons, onwards
        c.poly([(x, 6.5), (x + 3.5, 6.5), (x + 7, 12), (x + 3.5, 17.5), (x, 17.5), (x + 3.5, 12)], C)


def m_vigil_clarity(c):
    vigil_banner(c)
    drop(c, 14.5, 6.5, 0.9, C)                                                     # a drop of mana
    c.px(['W'], 13, 12, {'W': W})


# Iron Tithe: the vigils paid in health: the banner with a heart
def m_vigil_tithe(c):
    vigil_banner(c)
    c.ell(9.5, 7.5, 15, 13, C); c.ell(14, 7.5, 19.5, 13, C)                       # a heart
    c.poly([(10, 11), (19, 11), (14.5, 18)], C)
    c.px(['h'], 11, 9, {'h': CH})


# Tautstring (the Ranger line's distance buff, data/spells/chaos/paladin/tautstring.lua): a bow drawn to the full, the
# arrow nocked on the string
def m_tautstring(c):
    c.arc(3, 3, 19, 23, 270, 90, B, 1.6)                                          # the bow's limbs
    c.line([(11, 4), (6, 13), (11, 22)], BL, 0.6)                                  # the string, pulled back
    c.line([(6, 13), (21, 13)], A, 1.0)                                            # the arrow
    c.poly([(23, 13), (19, 10), (19, 16)], AH)                                     # its head
    c.poly([(5, 10), (8, 13), (5, 16), (4, 13)], A)                                # the fletching
    c.px(['W'], 21, 12, {'W': W})


# Ironhold (the Warrior line's guard buff, data/spells/chaos/knight/ironhold.lua): a riveted tower shield, iron bands
def m_ironhold(c):
    shield(c, 5, 3, 21, 23, A)                                                     # the shield
    c.line([(5.5, 9), (20.5, 9)], AD, 1.0); c.line([(5.5, 15), (20.5, 15)], AD, 1.0)  # two iron bands
    c.line([(13, 4), (13, 21)], B, 1.0)                                            # the spine
    c.px(['h', '', '', '', '', '', 'h'], 8, 6, {'h': AH}); c.px(['h', '', '', '', '', '', 'h'], 17, 6, {'h': AH})


# time-friendly progression (server catchup.lua)
def m_rested(c):
    c.ell(3, 4, 19, 20, A)                                                         # a crescent moon: rest
    c.ell(8, 2, 22, 17, 0)
    c.px(['h'], 6, 9, {'h': AH})
    c.px(['BBBB', '..B.', '.B..', 'BBBB'], 16, 15, {'B': B})                       # a small z and a star
    star(c, 19, 6, 2.6, 1.0, BH)


def m_returning(c):
    c.poly([(5, 23), (5, 9), (12, 3), (19, 9), (19, 23)], B)                       # an open doorway
    c.poly([(8, 23), (8, 11), (12, 7), (16, 11), (16, 23)], KK)
    c.poly([(4, 13), (11, 8), (11, 11), (21, 11), (21, 15), (11, 15), (11, 18)], A)  # an arrow coming home
    c.px(['h'], 10, 10, {'h': AH})


def m_catchup(c):
    m_up_arrow(c, 8, 9, 0.6, B)                                                    # a small arrow catching up
    m_up_arrow(c, 16, 3, 0.75, A)                                                  # with the big one
    c.px(['W'], 16, 5, {'W': W})


def m_low_stamina(c):
    c.poly([(6, 4), (20, 4), (14, 13), (20, 22), (6, 22), (12, 13)], B)            # an hourglass running low
    c.poly([(9, 6), (17, 6), (13, 11)], KK)
    c.poly([(9, 20), (17, 20), (13, 16)], A)
    c.rect(5, 3, 21, 5, BD); c.rect(5, 21, 21, 23, BD)


MOTIFS = {  # name: (function, ramps A, B, C)
    'rested': (m_rested, 'holy', 'arcane'), 'returning': (m_returning, 'gold', 'wood'),
    'catchup': (m_catchup, 'gold', 'nature'), 'low_stamina': (m_low_stamina, 'blood', 'steel'),
    'world_xp': (m_world_xp, 'gold', 'water'), 'world_loot': (m_world_loot, 'gold', 'wood'),
    'world_skill': (m_world_skill, 'steel', 'arcane'),
    'world_hunt': (m_world_hunt, 'gold', 'water'), 'victory': (m_victory, 'nature', 'steel', 'gold'),
    'golden_hour': (m_golden_hour, 'gold', 'wood'), 'chaos_storm': (m_chaos_storm, 'arcane', 'shadow'),
    'calendar_event': (m_event, 'gold', 'blood', 'wood'), 'event': (m_event, 'gold', 'blood', 'wood'),
    'double_xp': (m_double_xp, 'gold', 'ember', 'holy'),
    'trial_stacks': (m_trial_stacks, 'blood', 'gold'), 'chi': (m_chi, 'ember', 'wind'),
    'rage': (m_rage, 'steel', 'bone', 'blood'), 'reprisal': (m_reprisal, 'steel', 'blood'),
    'templar_aura': (m_templar_aura, 'holy', 'gold'), 'stunned': (m_stunned, 'holy', 'steel'),
    'stun_immune': (m_stun_immune, 'gold', 'steel'), 'focus': (m_focus, 'arcane', 'ember'),
    'haste': (m_haste, 'wind', 'wood'), 'regen': (m_regen, 'nature'), 'fed': (m_fed, 'ember', 'bone'),
    'manashield': (m_manashield, 'water', 'arcane'), 'invisible': (m_invisible, 'shadow'),
    'light': (m_light, 'ember', 'gold'), 'spellbuff': (m_spellbuff, 'arcane', 'steel', 'wood'),
    'poison': (m_poison, 'poison', 'poison'), 'burning': (m_burning, 'ember'), 'energy': (m_energy, 'energy'),
    'bleeding': (m_bleeding, 'blood'), 'drowning': (m_drowning, 'water', 'water'), 'freezing': (m_freezing, 'frost'),
    'dazzled': (m_dazzled, 'holy', 'bone'), 'cursed': (m_cursed, 'necro', 'arcane'),
    'paralyze': (m_paralyze, 'steel', 'coal'), 'drunk': (m_drunk, 'bone', 'wood'),
    'pacified': (m_pacified, 'steel', 'gold', 'blood'), 'muted': (m_muted, 'arcane', 'steel', 'bone'),
    'infight': (m_infight, 'steel', 'wood', 'blood'),
    'self_found': (m_self_found, 'gold', 'wood', 'steel'), 'hardcore_ward': (m_hardcore_ward, 'bone', 'holy'),
    'skull_white': (m_skull, 'bone'), 'skull_red': (m_skull, 'blood'), 'skull_black': (m_skull_black, 'obsidian', 'obsidian', 'blood'),
    # Ember Blessings (blessings.lua): ramp C is always the ember of the corner flame
    'blessing_xp': (m_blessing_xp, 'arcane', 'bone', 'ember'), 'blessing_gold': (m_blessing_gold, 'gold', 'gold', 'ember'),
    'blessing_damage': (m_blessing_damage, 'ember', 'steel', 'ember'), 'blessing_ward': (m_blessing_ward, 'ember', 'steel', 'ember'),
    'blessing_speed': (m_blessing_speed, 'wind', 'water', 'ember'), 'blessing_regen': (m_blessing_regen, 'blood', 'water', 'ember'),
    'blessing_crit': (m_blessing_crit, 'holy', 'steel', 'ember'), 'blessing_loot': (m_blessing_loot, 'gold', 'wood', 'ember'),
    'blessing_rarity': (m_blessing_rarity, 'arcane', 'arcane', 'ember'), 'blessing_orb': (m_blessing_orb, 'energy', 'coal', 'ember'),
    'professions': (m_professions, 'steel', 'wood', 'gold'),
    'vigil_wrath': (m_vigil_wrath, 'blood', 'wood', 'ember'), 'vigil_iron': (m_vigil_iron, 'steel', 'wood', 'gold'),
    'vigil_haste': (m_vigil_haste, 'nature', 'wood', 'wind'), 'vigil_clarity': (m_vigil_clarity, 'arcane', 'wood', 'water'),
    'vigil_tithe': (m_vigil_tithe, 'obsidian', 'wood', 'blood'),
    'tautstring': (m_tautstring, 'nature', 'wood'),
    'ironhold': (m_ironhold, 'steel', 'wood'),
}

# the class buffs that come from a Chaos spell show that spell's icon (key -> the spell's words)
SPELL_ICONS = {
    'red_frenzy': 'vyr ira cruor', 'rally': 'tor vas vant', 'barkskin': 'tor ael skar',
    'divine_ward': 'tor sol ghar', 'soul_aegis': 'tor anh', 'phantom_veil': 'fen wrai', 'dash': 'ash flik',
    'iron_will': 'vok vas rhov', 'stealth': 'fen umh', 'poison_blades': 'vyr vex thyss', 'counter': 'tor ryx',
    'bushido': 'vyr mynd', 'bloodrage': 'vyr sang khar', 'bone_aura': 'tor vas oss', 'bone_shield': 'drai sang oss',
    'chi_ward': 'tor qhal', 'mantra': 'tor vas qhal', 'breath': 'saen qhal',
    'aegis_faith': 'tor gal sol aeg',
    'moonfang_pack': 'vael luth wyrd', 'mirror_image': 'drai spek',
}

DEBUFFS = {'poison', 'burning', 'energy', 'bleeding', 'drowning', 'freezing', 'dazzled', 'cursed', 'paralyze', 'drunk',
           'pacified', 'muted', 'infight', 'skull_white', 'skull_red', 'skull_black', 'stunned', 'low_stamina'}

ICONS = sorted(set(MOTIFS) | set(SPELL_ICONS))
assert not set(MOTIFS) & set(SPELL_ICONS), 'a name is both drawn and taken from a spell'


# ---------------------------------------------------------------- building
def spell_cells():
    """the spell's words -> its cell in the spell icon sheet (game_chaosspells/spelldata.lua)"""
    text = open(SPELLDATA, encoding='utf-8').read()
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'words = "([^"]+)".*?clientId = (\d+)', text)}


def from_spell(sheet, cell, kind):
    n = cell - 1
    icon = sheet.crop(((n % 20) * 32, (n // 20) * 32, (n % 20) * 32 + 32, (n // 20) * 32 + 32))
    inner = icon.crop((2, 2, 30, 30)).resize((IN1 - IN0, IN1 - IN0), Image.BOX)
    if inner.getextrema()[3][1] == 0:
        raise SystemExit('spell icon cell %d is empty' % cell)
    im = plate(kind, R['coal'])
    bg = Image.new('RGBA', inner.size, im.getpixel((12, 12)))
    im.paste(Image.alpha_composite(bg, inner).convert('RGBA'), (IN0, IN0))
    return frame(im, kind)


def draw(name):
    kind = 'debuff' if name in DEBUFFS else 'buff'
    fn, *ramps = MOTIFS[name]
    c = Canvas()
    fn(c)
    rr = [R[r] for r in ramps]
    im = paint(plate(kind, rr[0]), c.grid(), rr)
    return frame(im, kind)


def build_all():
    cells, sheet = None, None
    out = {}
    for name in ICONS:
        if name in SPELL_ICONS:
            if sheet is None:
                cells = spell_cells()
                sheet = Image.open(SPELL_ART).convert('RGBA')
            cell = cells.get(SPELL_ICONS[name])
            if not cell:
                raise SystemExit('%s: no spell "%s" in spelldata.lua' % (name, SPELL_ICONS[name]))
            out[name] = from_spell(sheet, cell, 'buff')
        else:
            out[name] = draw(name)
    return out


def registry_names():
    """keys and "buff:<name>" icons of the registry, or None when the registry is not found"""
    if not os.path.exists(REGISTRY):
        return None
    text = open(REGISTRY, encoding='utf-8').read()
    keys = set(re.findall(r'^(?:cond|source)\("(\w+)"', text, re.M))
    icons = set(re.findall(r'"buff:(\w+)"', text))
    debuffs = set(re.findall(r'^(?:cond|source)\("(\w+)",[^\n]*?"debuff"', text, re.M))
    return keys | icons, debuffs


def check():
    found = registry_names()
    if found is None:
        return
    names, debuffs = found
    # the Ember Descent's entries and icons (descent_*) are drawn by gen_descent_icons.py
    names = {n for n in names if not n.startswith('descent_')}
    debuffs = {n for n in debuffs if not n.startswith('descent_')}
    # the raid's (raid_*) by gen_raid_icons.py
    names = {n for n in names if not n.startswith('raid_')}
    debuffs = {n for n in debuffs if not n.startswith('raid_')}
    # the community goal stages (community_*) and the world modifiers (wmod_*) by gen_community_icons.py
    names = {n for n in names if not n.startswith(('community_', 'wmod_'))}
    mine = set(ICONS)
    if names != mine:
        raise SystemExit('ICONS does not match chaos_buffs.lua: missing %s, unused %s' %
                         (sorted(names - mine), sorted(mine - names)))
    if debuffs != DEBUFFS:
        raise SystemExit('DEBUFFS does not match the debuffs of chaos_buffs.lua: %s' % sorted(debuffs ^ DEBUFFS))


def contact_sheet(icons, path, scale=3):
    from PIL import ImageFont  # noqa: F401  (the default bitmap font)
    names = sorted(icons, key=lambda n: (n in DEBUFFS, n))
    cols, cw, ch = 8, N * scale + 52, N * scale + 22
    rows = (len(names) + cols - 1) // cols
    im = Image.new('RGB', (cols * cw + 16, rows * ch + 16), (22, 18, 20))
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        x, y = 8 + (i % cols) * cw + 26, 8 + (i // cols) * ch
        big = icons[n].resize((N * scale, N * scale), Image.NEAREST)
        im.paste(big, (x, y), big)
        label = n if len(n) <= 15 else n[:14] + '.'
        tw = d.textlength(label)
        d.text((x + (N * scale - tw) / 2, y + N * scale + 4), label,
               fill=(255, 140, 120) if n in DEBUFFS else (240, 222, 180))
    im.save(path)


def main():
    args = sys.argv[1:]
    sheet = None
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else DEFAULT_OUT
    check()
    icons = build_all()
    os.makedirs(out, exist_ok=True)
    for name, im in icons.items():
        im.save(os.path.join(out, name + '.png'), optimize=True)
    if sheet:
        contact_sheet(icons, sheet)
    print(len(icons), 'buff icons written to', out)


if __name__ == '__main__':
    main()
