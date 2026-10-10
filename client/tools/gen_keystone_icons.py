#!/usr/bin/env python3
"""Procedural icons for the passive tree keystones (game_passivetree: nodes 621 and 624, and the keystones of the
class sections, 625-664) and the start images of the class sections.
Run: python3 -I client/tools/gen_keystone_icons.py client/overlay/data/images/passivetree/keystones.png
Writes one row of 64x64 cells, in the order of ICONS below; treedata/icons.lua points at each cell
(x = index * 64). Next to the sheet: classstart_<line>.png (START below, 150x150), the start node of a class
section. Same plate, glow and glyph style as the Chaos spell icons (gen_spell_icons.py). Needs Pillow."""
import math, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_spell_icons as base  # noqa: E402

CELL = 64
INK = (14, 8, 14, 255)


def cleave(d, c):
    # a wide crescent swing with the blade at its end
    d.arc((8, 14, 120, 126), 190, 350, fill=c, width=16)
    d.arc((24, 30, 104, 110), 200, 340, fill=c, width=6)
    d.polygon([(104, 40), (124, 22), (118, 58)], fill=c)


def bulwark(d, c):
    d.polygon([(30, 16), (98, 16), (98, 58), (64, 108), (30, 58)], fill=c)
    d.polygon([(64, 26), (88, 26), (88, 56), (64, 92)], fill=(255, 255, 255, 70))
    for y in (30, 64, 98):  # reflected strikes
        d.polygon([(4, y), (20, y - 8), (20, y + 8)], fill=c)
        d.polygon([(124, y), (108, y - 8), (108, y + 8)], fill=c)


def ricochet(d, c):
    pts = [(10, 104), (58, 30), (88, 92), (120, 22)]
    d.line(pts, fill=c, width=8)
    for x, y in pts[1:3]:
        d.ellipse((x - 10, y - 10, x + 10, y + 10), fill=c)
    d.polygon([(120, 8), (124, 40), (100, 26)], fill=c)


def deadeye(d, c):
    d.ellipse((16, 16, 112, 112), outline=c, width=9)
    d.ellipse((40, 40, 88, 88), outline=c, width=6)
    for a, b in (((64, 4), (64, 40)), ((64, 88), (64, 124)), ((4, 64), (40, 64)), ((88, 64), (124, 64))):
        d.line([a, b], fill=c, width=7)
    d.ellipse((56, 56, 72, 72), fill=c)


def echo(d, c):
    for r, w in ((56, 6), (40, 8), (24, 10)):
        d.ellipse((64 - r, 64 - r, 64 + r, 64 + r), outline=c, width=w)
    d.ellipse((56, 56, 72, 72), fill=c)


def overload(d, c):
    d.ellipse((10, 10, 118, 118), outline=c, width=8)
    d.pieslice((22, 22, 106, 106), 90, 270, fill=c)
    d.polygon([(78, 26), (60, 66), (74, 66), (62, 104), (92, 56), (78, 56), (90, 26)], fill=c)


def overgrowth(d, c):
    d.polygon([(16, 112), (24, 52), (58, 22), (96, 20), (92, 60), (58, 96)], fill=c)
    d.line([(20, 110), (82, 34)], fill=(20, 60, 20), width=5)
    d.rectangle((92, 70, 104, 122), fill=c)
    d.rectangle((72, 90, 124, 102), fill=c)


def thorns(d, c):
    base.thorns(d, c)
    d.ellipse((52, 52, 76, 76), fill=INK)


def phantasm(d, c):
    # a marked enemy: eye inside a rune ring
    d.ellipse((6, 6, 122, 122), outline=c, width=7)
    for i in range(6):
        a = math.pi * i / 3
        x, y = 64 + 58 * math.cos(a), 64 + 58 * math.sin(a)
        d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=c)
    base.eye(d, c)


def inspire(d, c):
    # three allies under a rising star
    for x in (28, 64, 100):
        d.ellipse((x - 12, 70, x + 12, 94), fill=c)
        d.pieslice((x - 20, 92, x + 20, 132), 180, 360, fill=c)
    pts = []
    for i in range(10):
        a = math.pi * i / 5 - math.pi / 2
        r = 30 if i % 2 == 0 else 12
        pts.append((64 + r * math.cos(a), 34 + r * math.sin(a)))
    d.polygon(pts, fill=c)


def wrath(d, c):
    base.burst(d, c, n=8, r1=58, r2=26)


def resolve(d, c):
    base.shield(d, c)


GLYPHS = {f.__name__: f for f in (cleave, bulwark, ricochet, deadeye, echo, overload, overgrowth, thorns, phantasm,
                                  inspire, wrath, resolve)}
base.GLYPH.update(GLYPHS)

ICONS = [  # (icon key in treedata/icons.lua, theme, glyph)
    ('ksWrath', 'ember', 'wrath'), ('ksResolve', 'steel', 'resolve'),
    ('ksCleavingArc', 'steel', 'cleave'), ('ksBulwark', 'ember', 'bulwark'),
    ('ksRicochet', 'holy', 'ricochet'), ('ksDeadeye', 'light', 'deadeye'),
    ('ksArcaneEcho', 'arcane', 'echo'), ('ksOverload', 'fire', 'overload'),
    ('ksOvergrowth', 'nature', 'overgrowth'), ('ksThorns', 'poison', 'thorns'),
    ('ksSharedPhantasm', 'shadow', 'phantasm'), ('ksInspiringIllusion', 'holy', 'inspire'),
    # per-ascended variants (621 / 624) of the Juggernaut, Berserker, Deadeye and Beastmaster
    ('ksImmovable', 'steel', 'slam'), ('ksUndyingRage', 'blood', 'greataxe'),
    ('ksHuntersFocus', 'ember', 'eye'), ('ksPackAlpha', 'nature', 'paw'),
    # the class sections: Ninja, Samurai, Lich, Bone Lord, Shadowfist, Iron Sage, Inquisitor, Sentinel
    ('ksLivingShadow', 'shadow', 'hood'), ('ksWayOfTheBlade', 'ember', 'katana'),
    ('ksHoardedSouls', 'necrotic', 'ghost'), ('ksBoneColossus', 'bone', 'golem'),
    ('ksHundredHands', 'shadow', 'fist'), ('ksFlowingMercy', 'light', 'flame'),
    ('ksDivineVerdict', 'holy', 'eye'), ('ksBastion', 'light', 'shield'),
]

START = [  # (line, theme, glyph): the start node of each class section
    ('thief', 'shadow', 'daggers'), ('necromancer', 'necrotic', 'skull'), ('monk', 'ember', 'fist'),
    ('templar', 'holy', 'cross'),
]
START_SIZE = 150


def start_image(theme, glyph):
    # a round medallion: the icon cut to a circle inside a bronze ring (the root's start node is round too)
    from PIL import ImageDraw
    n = START_SIZE * 2
    icon = base.render(theme, glyph).resize((n, n), Image.LANCZOS)
    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).ellipse((14, 14, n - 15, n - 15), fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask)
    d = ImageDraw.Draw(out)
    d.ellipse((6, 6, n - 7, n - 7), outline=(92, 66, 34, 255), width=14)
    d.ellipse((10, 10, n - 11, n - 11), outline=(196, 158, 88, 255), width=6)
    return out.resize((START_SIZE, START_SIZE), Image.LANCZOS)


def main():
    out = sys.argv[1]
    sheet = Image.new('RGBA', (CELL * len(ICONS), CELL), (0, 0, 0, 0))
    for i, (_, theme, glyph) in enumerate(ICONS):
        sheet.alpha_composite(base.render(theme, glyph).resize((CELL, CELL), Image.LANCZOS), (i * CELL, 0))
    sheet.save(out)
    print(len(ICONS), 'keystone icons written to', out)
    folder = os.path.dirname(os.path.abspath(out))
    for line, theme, glyph in START:
        path = os.path.join(folder, 'classstart_%s.png' % line)
        start_image(theme, glyph).save(path)
    print(len(START), 'class start images written next to it')


if __name__ == '__main__':
    main()
