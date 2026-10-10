#!/usr/bin/env python3
"""Pixel-art icons of the DPS meter (client module game_dpsmeter), 26x26 in the buff bar's frame style.

Run: python3 client/tools/gen_dpsmeter_icons.py [OUTDIR] [--sheet SHEET.png]
     default OUTDIR: client/overlay/data/images/game/dpsmeter  ->  <name>.png, one per name of MOTIFS, and grip.png
     (the panel's 10x10 resize grip)

The meter shows a spell's own icon (the spell icon sheet, through the spell's words) and a rune's item; damage over
time and regeneration use the buff bar's icons (images/game/buffs). Everything else a row can be is drawn here: the
weapon attacks (sword, axe, club, fist, distance, wand), procs (spell supports, keystones, thorns, legendary powers,
item elements), summons, potions, the "other" row, and the attackers of the Taken tab (monster, player, environment).
The drawing helpers (plate, frame, shading, the 4x motif canvas) are the buff icon generator's (gen_buff_icons.py),
so both sets look alike: warm gold frame, one colour ramp per motif, light from the top left. The DpsMath.ICONS list
(game_dpsmeter/dpsmath.lua) must name the same icons: the run stops when they differ.
Our own art; deterministic. Needs Pillow."""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'dpsmeter')
DPSMATH = os.path.join(ROOT, 'client', 'overlay', 'modules', 'game_dpsmeter', 'dpsmath.lua')

_spec = importlib.util.spec_from_file_location('gen_buff_icons', os.path.join(HERE, 'gen_buff_icons.py'))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)

A, AH, AD, BB, BH, BD, W, KK, AL, C, CH, CD = B.A, B.AH, B.AD, B.B, B.BH, B.BD, B.W, B.KK, B.AL, B.C, B.CH, B.CD


# ---------------------------------------------------------------- motifs (icon pixels; the plate is 2..24)
def blade(c, x0, y0, x1, y1, v=A, w=2.2):
    c.line([(x0, y0), (x1, y1)], v, w)


def m_sword(c):
    blade(c, 6, 20, 20, 5, A, 2.4)                               # a blade, point top right
    c.poly([(19, 4), (22, 4), (21, 7)], AH)
    c.line([(4, 15), (11, 22)], BB, 1.8)                         # the guard
    c.line([(3, 23), (7, 19)], C, 2.0)                           # grip and pommel
    c.ell(2, 22, 5, 25, BH)
    c.line([(9, 17), (18, 7)], AH, 0.8)


def m_axe(c):
    c.line([(6, 23), (17, 6)], C, 2.0)                           # the haft
    c.poly([(13, 4), (22, 6), (23, 14), (19, 15), (16, 10)], A)  # the head
    c.poly([(19, 7), (22, 8), (22, 12)], AH)
    c.ell(15, 7, 18, 10, KK)


def m_club(c):
    c.line([(5, 22), (14, 11)], C, 2.4)                          # handle
    c.ell(11, 3, 23, 15, A)                                      # the head with studs
    c.ell(13, 5, 18, 9, AL)
    for (x, y) in ((12, 9), (17, 4), (21, 9), (17, 13)):
        c.px(['s'], x, y, {'s': BH})


def m_fist(c):
    c.rect(7, 9, 20, 19, A)                                      # a clenched fist
    for x in (7, 10.5, 14, 17.5):
        c.ell(x - 0.5, 6, x + 3.5, 11, A)
    c.ell(4, 11, 9, 17, A)                                       # the thumb
    c.rect(8, 19, 19, 23, BB)                                    # wraps
    c.line([(8, 21), (19, 21)], BD, 0.8)
    for x in (9.5, 13, 16.5):
        c.line([(x, 7.5), (x, 10)], AD, 0.7)


def m_distance(c):
    c.arc(3, 3, 23, 23, 300, 420, BB, 1.8)                       # a bow and an arrow
    c.line([(7, 4), (7, 22)], BD, 0.8)
    c.line([(5, 13), (22, 13)], A, 1.4)
    c.poly([(22, 10), (25, 13), (22, 16)], AH)
    c.poly([(4, 10), (7, 13), (4, 16), (5, 13)], C)


def m_wand(c):
    c.line([(5, 22), (16, 11)], BB, 2.0)                         # a wand with a glowing tip
    B.star(c, 18, 8, 6.5, 2.6, A, n=4, rot=-45)
    c.ell(16, 6, 20, 10, AH)
    c.px(['W'], 18, 8, {'W': W})
    c.px(['h'], 6, 6, {'h': AH}); c.px(['h'], 22, 18, {'h': AH})


def m_dot(c):
    for (x, y, r) in ((8, 16, 4), (16, 9, 3.2), (18, 19, 2.4)):  # drops ticking down
        c.poly([(x, y - r * 2), (x + r, y), (x - r, y)], A)
        c.ell(x - r, y - r * 0.6, x + r, y + r * 1.2, A)
    c.px(['h'], 7, 13, {'h': AH})


def m_other(c):
    c.ell(5, 5, 21, 21, A)                                       # a rune disc with a question mark
    c.ell(7, 7, 19, 19, AD)
    c.px(['.###.',
          '#...#',
          '....#',
          '...#.',
          '..#..',
          '.....',
          '..#..'], 11, 9, {'#': AH})


def m_supports(c):
    c.poly([(13, 3), (22, 13), (13, 23), (4, 13)], A)            # a socketed support rune
    c.poly([(13, 7), (18, 13), (13, 19), (8, 13)], BB)
    c.ell(10.5, 10.5, 15.5, 15.5, BH)
    c.px(['W'], 12, 11, {'W': W})


def m_keystone(c):
    c.ell(4, 4, 22, 22, BB)                                      # a passive tree keystone: a ring with a star
    c.ell(6, 6, 20, 20, BD)
    B.star(c, 13, 13, 7, 3, A)
    c.px(['h'], 12, 8, {'h': AH})


def m_thorns(c):
    B.shield(c, 6, 5, 20, 23, BB)                                # a shield with thorns
    for (x0, y0, x1, y1) in ((6, 9, 2, 6), (20, 9, 24, 6), (6, 16, 2, 18), (20, 16, 24, 18), (13, 5, 13, 1)):
        c.line([(x0, y0), (x1, y1)], A, 1.4)
    c.line([(9, 9), (17, 17)], AH, 1.1); c.line([(17, 9), (9, 17)], AH, 1.1)


def m_power(c):
    c.poly([(13, 2), (16, 10), (24, 10), (17.5, 15), (20, 23), (13, 18), (6, 23), (8.5, 15), (2, 10), (10, 10)], A)
    c.poly([(13, 7), (15, 12), (13, 16), (11, 12)], AH)          # a legendary burst


def m_elements(c):
    c.poly([(8, 3), (12, 9), (10, 13), (4, 11)], A)              # three element shards: fire, ice, storm
    c.poly([(18, 4), (22, 10), (18, 14), (14, 10)], BB)
    c.poly([(13, 13), (17, 13), (14, 18), (17, 18), (11, 24), (12, 19), (9, 19)], C)


def m_summon(c):
    c.ell(7, 11, 19, 22, A)                                      # a paw
    for (x, y) in ((4, 7), (9, 3), (15, 3), (20, 7)):
        c.ell(x - 0.5, y, x + 3.5, y + 4.5, A)
    c.px(['h', 'h'], 10, 13, {'h': AH})


def m_potion(c):
    c.rect(11, 3, 15, 8, BB)                                     # a red potion
    c.ell(5, 7, 21, 23, BB)
    c.ell(6.5, 12, 19.5, 22, A)
    c.rect(10, 2, 16, 4, C)
    c.px(['W', 'W'], 9, 13, {'W': W})


def m_monster(c):
    B.skull(c, 6, 7)                                             # a horned skull: a monster
    c.poly([(6, 9), (2, 3), (8, 7)], BB); c.poly([(20, 9), (24, 3), (18, 7)], BB)


def m_player(c):
    c.ell(9, 3, 17, 11, A)                                       # a figure
    c.poly([(5, 24), (6, 15), (9, 12), (17, 12), (20, 15), (21, 24)], BB)
    c.px(['k', 'k'], 11, 6, {'k': KK}); c.px(['k'], 14, 6, {'k': KK})


def m_env(c):
    c.poly([(2, 22), (9, 10), (13, 16), (17, 8), (24, 22)], A)   # mountains and a falling rock
    c.poly([(17, 8), (19, 12), (15, 12)], AH)
    c.ell(4, 3, 9, 8, BB)


MOTIFS = {  # name: (function, ramps A, B, C)
    'sword': (m_sword, 'steel', 'gold', 'wood'), 'axe': (m_axe, 'steel', 'steel', 'wood'),
    'club': (m_club, 'wood', 'steel'), 'fist': (m_fist, 'bone', 'blood'),
    'distance': (m_distance, 'steel', 'wood', 'blood'), 'wand': (m_wand, 'arcane', 'wood'),
    'dot': (m_dot, 'poison'), 'other': (m_other, 'obsidian'), 'supports': (m_supports, 'arcane', 'gold'),
    'keystone': (m_keystone, 'ember', 'gold'), 'thorns': (m_thorns, 'nature', 'steel'),
    'power': (m_power, 'holy'), 'elements': (m_elements, 'ember', 'frost', 'energy'),
    'summon': (m_summon, 'bone'), 'potion': (m_potion, 'blood', 'blood', 'wood'),
    'monster': (m_monster, 'bone', 'blood'), 'player': (m_player, 'bone', 'water'),
    'env': (m_env, 'coal', 'ember'),
}


def draw(name):
    fn, *ramps = MOTIFS[name]
    c = B.Canvas()
    fn(c)
    rr = [B.R[r] for r in ramps]
    im = B.paint(B.plate('buff', rr[0]), c.grid(), rr)
    return B.frame(im, 'buff')


def grip():
    """the 10x10 resize grip of the meter panel: three diagonal rows of iron studs, lit top left"""
    from PIL import Image
    im = Image.new('RGBA', (10, 10), (0, 0, 0, 0))
    p = im.load()
    for (x, y) in ((8, 2), (5, 5), (8, 5), (2, 8), (5, 8), (8, 8)):
        p[x, y] = (125, 113, 118, 255)
        p[x - 1, y - 1] = (214, 201, 174, 255)
        p[x, y - 1] = p[x - 1, y] = (90, 80, 86, 255)
    return im


def check():
    """the client's DpsMath.ICONS must list exactly these names"""
    if not os.path.exists(DPSMATH):
        return
    text = open(DPSMATH, encoding='utf-8').read()
    m = re.search(r'DpsMath\.ICONS\s*=\s*\{([^}]*)\}', text)
    names = set(re.findall(r"'(\w+)'", m.group(1))) if m else set()
    if names != set(MOTIFS):
        raise SystemExit('DpsMath.ICONS does not match: missing %s, extra %s' %
                         (sorted(set(MOTIFS) - names), sorted(names - set(MOTIFS))))


def main():
    args = sys.argv[1:]
    sheet = None
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else DEFAULT_OUT
    check()
    icons = {name: draw(name) for name in sorted(MOTIFS)}
    os.makedirs(out, exist_ok=True)
    for name, im in icons.items():
        im.save(os.path.join(out, name + '.png'), optimize=True)
    grip().save(os.path.join(out, 'grip.png'), optimize=True)
    if sheet:
        B.DEBUFFS = set()
        B.contact_sheet(icons, sheet)
    print(len(icons), 'DPS meter icons written to', out)


if __name__ == '__main__':
    main()
