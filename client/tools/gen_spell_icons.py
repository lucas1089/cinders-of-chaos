#!/usr/bin/env python3
"""Procedural 32x32 spell icons for the Chaos spells (and 22x24 / 20x20 versions).
Run: python3 -I gen_spell_icons.py OUTDIR   -> OUTDIR/32/<n>.png, OUTDIR/22x24/<n>.png, OUTDIR/20/<n>.png
The order and names come from ICONS below (same order as server/data/spells/chaos/spells_chaos.xml)."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 128  # work size, scaled down to 32
COL = {
    'fire': (255, 130, 40), 'frost': (130, 205, 255), 'light': (255, 230, 90), 'blood': (215, 30, 40),
    'poison': (120, 205, 70), 'nature': (95, 175, 80), 'holy': (255, 238, 160), 'shadow': (160, 100, 230),
    'arcane': (125, 150, 255), 'steel': (205, 210, 222), 'ember': (240, 100, 50), 'water': (90, 190, 200),
    'bone': (226, 214, 182), 'necrotic': (120, 222, 140),
}

def burst(d, c, n=10, r1=54, r2=24):
    pts = []
    for i in range(n * 2):
        a = math.pi * i / n - math.pi / 2
        r = r1 if i % 2 == 0 else r2
        pts.append((64 + r * math.cos(a), 64 + r * math.sin(a)))
    d.polygon(pts, fill=c)

def bolt(d, c):
    d.polygon([(76, 8), (34, 70), (60, 70), (46, 120), (96, 52), (68, 52)], fill=c)

def drop(d, c):
    d.polygon([(64, 10), (30, 70)] + [(64 + 36 * math.cos(math.radians(a)), 80 + 36 * math.sin(math.radians(a))) for a in range(160, 20, -10)] + [(98, 70)], fill=c)

def crystal(d, c):
    d.polygon([(64, 8), (92, 44), (80, 120), (48, 120), (36, 44)], fill=c)
    d.line([(64, 8), (64, 120)], fill=(255, 255, 255), width=4)

def meteor(d, c):
    d.polygon([(10, 10), (70, 52), (52, 70)], fill=c)
    d.ellipse((46, 46, 112, 112), fill=c)

def dots(d, c):
    for x, y, r in [(40, 40, 14), (84, 34, 11), (64, 70, 16), (36, 92, 10), (92, 90, 13), (66, 112, 8)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c)

def shield(d, c):
    d.polygon([(22, 18), (106, 18), (106, 62), (64, 118), (22, 62)], fill=c)
    d.polygon([(64, 30), (94, 30), (94, 60), (64, 100)], fill=(255, 255, 255, 70))

def thorns(d, c):
    for i in range(8):
        a = math.pi * i / 4
        d.polygon([(64 + 22 * math.cos(a - .2), 64 + 22 * math.sin(a - .2)), (64 + 58 * math.cos(a), 64 + 58 * math.sin(a)),
                   (64 + 22 * math.cos(a + .2), 64 + 22 * math.sin(a + .2))], fill=c)
    d.ellipse((42, 42, 86, 86), fill=c)

def paw(d, c):
    d.ellipse((38, 64, 90, 112), fill=c)
    for x, y in [(26, 52), (50, 28), (78, 28), (102, 52)]:
        d.ellipse((x - 12, y - 14, x + 12, y + 14), fill=c)

def leaf(d, c):
    d.polygon([(20, 108), (30, 40), (70, 12), (112, 20), (104, 70), (70, 104)], fill=c)
    d.line([(24, 108), (96, 32)], fill=(20, 60, 20), width=5)

def swirl(d, c):
    for k, w in enumerate((14, 11, 8)):
        pts = []
        for i in range(40):
            a = 0.2 * i + k * 2.1
            r = 8 + i * 1.3
            pts.append((64 + r * math.cos(a), 64 + r * math.sin(a)))
        d.line(pts, fill=c, width=w)

def cross(d, c):
    d.rectangle((52, 10, 76, 118), fill=c)
    d.rectangle((24, 40, 104, 62), fill=c)

def arrows(d, c):
    for off in (-26, 0, 26):
        d.line([(20, 64 + off), (92, 64 + off)], fill=c, width=8)
        d.polygon([(88, 50 + off), (112, 64 + off), (88, 78 + off)], fill=c)

def ring(d, c):
    d.ellipse((14, 14, 114, 114), outline=c, width=12)
    d.rectangle((58, 34, 70, 94), fill=c)
    d.rectangle((38, 52, 90, 62), fill=c)

def sword(d, c):
    d.polygon([(64, 6), (78, 22), (78, 84), (50, 84), (50, 22)], fill=c)
    d.rectangle((26, 84, 102, 96), fill=c)
    d.rectangle((58, 96, 70, 122), fill=c)

def slam(d, c):
    d.polygon([(8, 96), (120, 96), (120, 120), (8, 120)], fill=c)
    for x in (24, 52, 80, 104):
        d.polygon([(x, 96), (x + 14, 30), (x + 28, 96)], fill=c)

def wave(d, c):
    for i, y in enumerate((30, 64, 98)):
        pts = [(10 + x, y + 10 * math.sin(x / 10 + i)) for x in range(0, 108, 4)]
        d.line(pts, fill=c, width=11)

def arrowup(d, c):
    d.polygon([(64, 8), (110, 60), (80, 60), (80, 118), (48, 118), (48, 60), (18, 60)], fill=c)

def hammer(d, c):
    d.rectangle((52, 40, 76, 122), fill=c)
    d.rectangle((20, 8, 108, 48), fill=c)

def twin(d, c):
    d.ellipse((10, 24, 80, 94), outline=c, width=12)
    d.ellipse((48, 34, 118, 104), fill=c)

def dash(d, c):
    for i, y in enumerate((34, 64, 94)):
        d.polygon([(20 + 10 * i, y - 8), (96, y - 8), (112, y), (96, y + 8), (20 + 10 * i, y + 8)], fill=c)

def eye(d, c):
    d.polygon([(6, 64), (34, 36), (64, 26), (94, 36), (122, 64), (94, 92), (64, 102), (34, 92)], fill=c)
    d.ellipse((44, 44, 84, 84), fill=(20, 10, 30))
    d.ellipse((56, 56, 72, 72), fill=c)

def ghost(d, c):
    d.pieslice((24, 12, 104, 92), 180, 360, fill=c)
    d.rectangle((24, 52, 104, 104), fill=c)
    for x in (24, 54, 84):
        d.polygon([(x, 100), (x + 15, 124), (x + 30, 100)], fill=c)
    d.ellipse((40, 46, 56, 64), fill=(20, 10, 30)); d.ellipse((72, 46, 88, 64), fill=(20, 10, 30))

def rift(d, c):
    d.polygon([(70, 6), (44, 50), (66, 54), (36, 122), (92, 60), (68, 56), (96, 14)], fill=c)

def missile(d, c):
    d.polygon([(14, 112), (70, 70), (56, 56)], fill=c)
    d.ellipse((52, 20, 108, 76), fill=c)

def shuriken(d, c):
    for i in range(4):
        a = math.pi / 2 * i + math.pi / 8
        d.polygon([(64 + 16 * math.cos(a - .9), 64 + 16 * math.sin(a - .9)), (64 + 58 * math.cos(a), 64 + 58 * math.sin(a)),
                   (64 + 16 * math.cos(a + .9), 64 + 16 * math.sin(a + .9))], fill=c)
    d.ellipse((50, 50, 78, 78), fill=c)
    d.ellipse((58, 58, 70, 70), fill=(20, 10, 30))

def daggers(d, c):
    for flip in (False, True):
        pts = [(20, 112), (30, 102), (96, 22), (106, 14), (100, 32), (40, 108), (30, 118)]
        if flip:
            pts = [(128 - x, y) for x, y in pts]
        d.polygon(pts, fill=c)
    d.rectangle((18, 96, 46, 104), fill=c); d.rectangle((82, 96, 110, 104), fill=c)

def smoke(d, c):
    for x, y, r in [(44, 78, 30), (84, 74, 28), (64, 50, 30), (36, 52, 18), (94, 46, 18), (64, 96, 22)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c)

def katana(d, c):
    d.line([(22, 108), (40, 90)], fill=c, width=12)
    d.polygon([(40, 96), (34, 86), (100, 18), (114, 10), (108, 26)], fill=c)
    d.ellipse((30, 82, 52, 104), outline=c, width=6)

def hood(d, c):
    d.pieslice((18, 14, 110, 120), 180, 360, fill=c)
    d.polygon([(18, 66), (110, 66), (98, 120), (30, 120)], fill=c)
    d.ellipse((40, 52, 88, 100), fill=(20, 10, 30))
    d.ellipse((50, 70, 60, 78), fill=c); d.ellipse((68, 70, 78, 78), fill=c)

def greataxe(d, c):
    d.line([(30, 120), (86, 22)], fill=c, width=10)
    d.pieslice((52, 2, 124, 74), 200, 20, fill=c)
    d.polygon([(60, 30), (40, 8), (34, 38)], fill=c)

def fang(d, c):
    d.pieslice((10, 6, 118, 96), 0, 180, fill=c)
    for x in (30, 82):
        d.polygon([(x, 50), (x + 16, 50), (x + 8, 120)], fill=c)
    d.ellipse((36, 30, 52, 46), fill=(20, 10, 30)); d.ellipse((76, 30, 92, 46), fill=(20, 10, 30))

# the Necromancer line
def skull(d, c):
    d.ellipse((24, 14, 104, 88), fill=c)
    d.rounded_rectangle((40, 70, 88, 108), 8, fill=c)
    d.ellipse((38, 40, 60, 64), fill=(20, 10, 30)); d.ellipse((68, 40, 90, 64), fill=(20, 10, 30))
    d.polygon([(64, 66), (58, 80), (70, 80)], fill=(20, 10, 30))
    for x in (48, 60, 72):
        d.line([(x, 92), (x, 108)], fill=(20, 10, 30), width=4)

def bonespear(d, c):
    d.line([(22, 106), (98, 30)], fill=c, width=10)
    d.polygon([(90, 22), (118, 10), (106, 38)], fill=c)
    for x, y in ((22, 106), (30, 98)):
        d.ellipse((x - 10, y - 10, x + 10, y + 10), fill=c)

def golem(d, c):
    d.ellipse((46, 8, 82, 40), fill=c)
    d.rounded_rectangle((30, 40, 98, 92), 10, fill=c)
    for y in (52, 64, 76):
        d.line([(40, y), (88, y)], fill=(20, 10, 30), width=4)
    d.rounded_rectangle((10, 44, 30, 96), 8, fill=c); d.rounded_rectangle((98, 44, 118, 96), 8, fill=c)
    d.rectangle((38, 92, 56, 120), fill=c); d.rectangle((72, 92, 90, 120), fill=c)
    d.ellipse((54, 18, 62, 26), fill=(20, 10, 30)); d.ellipse((66, 18, 74, 26), fill=(20, 10, 30))

def banner(d, c):
    d.line([(34, 10), (34, 120)], fill=c, width=8)
    d.polygon([(38, 14), (110, 14), (96, 44), (110, 74), (38, 74)], fill=c)
    d.ellipse((56, 26, 82, 52), fill=(20, 10, 30)); d.rectangle((62, 50, 76, 60), fill=(20, 10, 30))

def ribs(d, c):
    d.line([(64, 10), (64, 118)], fill=c, width=8)
    for i, y in enumerate((28, 48, 68, 88)):
        w = 46 - i * 6
        d.arc((64 - w, y - 14, 64 + w, y + 30), 190, 350, fill=c, width=7)

# the Monk line
def fist(d, c):
    # a clenched fist seen from the front: four knuckles over a palm block and a thumb
    d.rounded_rectangle((30, 46, 98, 110), 14, fill=c)
    for i in range(4):
        x = 30 + i * 17
        d.ellipse((x, 26, x + 19, 56), fill=c)
    d.polygon([(26, 70), (60, 64), (64, 80), (30, 92)], fill=c)
    for i in range(1, 4):
        x = 30 + i * 17
        d.line([(x, 34), (x, 52)], fill=(20, 10, 30), width=3)


def palm(d, c):
    # an open palm pushing out a shock ring
    d.ellipse((6, 6, 122, 122), outline=c, width=6)
    d.rounded_rectangle((42, 52, 88, 112), 10, fill=c)
    for i, h in enumerate((30, 22, 24, 34)):
        x = 42 + i * 12
        d.rounded_rectangle((x, h, x + 10, 60), 5, fill=c)
    d.polygon([(42, 76), (22, 60), (28, 54), (46, 66)], fill=c)


def kick(d, c):
    # a spinning heel: a leg arc with motion lines
    d.arc((14, 14, 114, 114), 200, 520, fill=c, width=12)
    d.polygon([(84, 18), (112, 22), (104, 46), (88, 40)], fill=c)
    for r in (30, 42):
        d.arc((64 - r, 64 - r, 64 + r, 64 + r), 30, 150, fill=c, width=4)


def flame(d, c):
    # a breath of chi: a rising flame over a bowl
    d.polygon([(64, 8), (88, 48), (84, 78), (64, 92), (44, 78), (40, 48)], fill=c)
    d.polygon([(64, 40), (74, 62), (64, 80), (54, 62)], fill=(255, 255, 255, 120))
    d.pieslice((28, 76, 100, 124), 0, 180, fill=c)


def nodes(d, c):
    # pressure points: a hand's outline of five struck nodes joined by lines
    pts = [(64, 16), (100, 46), (86, 100), (42, 100), (28, 46)]
    d.line(pts + [pts[0]], fill=c, width=5)
    for x, y in pts:
        d.ellipse((x - 11, y - 11, x + 11, y + 11), fill=c)
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(20, 10, 30))
    d.ellipse((52, 54, 76, 78), fill=c)


def mountain(d, c):
    # the mantra of stone: a mountain with a halo
    d.ellipse((30, 6, 98, 50), outline=c, width=6)
    d.polygon([(6, 118), (52, 40), (70, 66), (84, 52), (122, 118)], fill=c)
    d.polygon([(52, 40), (62, 58), (44, 58)], fill=(255, 255, 255, 140))


def gate(d, c):
    # Town Portal: an arched gate with a swirl inside
    d.rounded_rectangle((26, 14, 102, 120), 36, outline=c, width=9)
    for i in range(3):
        r = 30 - i * 9
        d.arc((64 - r, 70 - r, 64 + r, 70 + r), 40 + i * 70, 300 + i * 70, fill=c, width=5)
    d.rectangle((14, 112, 114, 122), fill=c)

def flurry(d, c):
    # Blade Flurry: three curved blades spinning round a hub, with the arc of the spin
    for r, w in ((54, 5), (40, 3)):
        d.arc((64 - r, 64 - r, 64 + r, 64 + r), 210, 320, fill=c, width=w)
        d.arc((64 - r, 64 - r, 64 + r, 64 + r), 30, 140, fill=c, width=w)
    for i in range(3):
        a = 2 * math.pi * i / 3 - math.pi / 2
        pts = [(64 + 10 * math.cos(a - .9), 64 + 10 * math.sin(a - .9)), (64 + 30 * math.cos(a - .38), 64 + 30 * math.sin(a - .38)),
               (64 + 58 * math.cos(a), 64 + 58 * math.sin(a)), (64 + 40 * math.cos(a + .42), 64 + 40 * math.sin(a + .42)),
               (64 + 22 * math.cos(a + .55), 64 + 22 * math.sin(a + .55)), (64 + 10 * math.cos(a + .9), 64 + 10 * math.sin(a + .9))]
        d.polygon(pts, fill=c)
    d.ellipse((52, 52, 76, 76), fill=c)
    d.ellipse((59, 59, 69, 69), fill=(20, 10, 30))

def sweep(d, c):
    # Iaido Sweep: a wide crescent cut drawn from the scabbard, the blade at its end
    d.pieslice((6, 22, 122, 138), 200, 340, fill=c)
    d.pieslice((22, 40, 106, 124), 196, 344, fill=(18, 13, 18, 255))
    d.line([(16, 116), (34, 100)], fill=c, width=10)
    d.polygon([(30, 106), (26, 96), (96, 40), (112, 34), (104, 50)], fill=c)
    d.line([(26, 92), (40, 108)], fill=c, width=6)

def palmwave(d, c):
    # Palm Shockwave: an open palm and the rings of its shockwave
    for r, w in ((56, 5), (44, 4), (32, 3)):
        d.arc((64 - r, 70 - r, 64 + r, 70 + r), 200, 340, fill=c, width=w)
    d.rounded_rectangle((44, 52, 84, 112), 10, fill=c)
    for i, x in enumerate((44, 54, 64, 74)):
        d.rounded_rectangle((x, 26 + abs(i - 1.5) * 6, x + 9, 60), 4, fill=c)
    d.polygon([(84, 80), (104, 62), (110, 70), (88, 94)], fill=c)

def ricochet(d, c):
    # Shadow Ricochet: a dark fist mark and its zig-zag jumps
    pts = [(14, 104), (44, 44), (66, 92), (88, 30), (112, 70)]
    d.line(pts, fill=c, width=7, joint='curve')
    for x, y in pts:
        d.ellipse((x - 9, y - 9, x + 9, y + 9), fill=c)
    d.ellipse((6, 96, 22, 112), fill=(20, 10, 30))

def chain(d, c):
    # Iron Chain: three linked iron rings across the icon
    for i, (x, y) in enumerate(((30, 92), (64, 64), (98, 36))):
        if i % 2 == 0:
            d.ellipse((x - 22, y - 14, x + 22, y + 14), outline=c, width=9)
        else:
            d.ellipse((x - 14, y - 22, x + 14, y + 22), outline=c, width=9)

def shrapnel(d, c):
    # Bone Shrapnel: a burst of bone shards from a cracked core
    for i in range(8):
        a = math.pi * i / 4 + .2
        x0, y0 = 64 + 18 * math.cos(a), 64 + 18 * math.sin(a)
        x1, y1 = 64 + 58 * math.cos(a), 64 + 58 * math.sin(a)
        d.polygon([(x0 - 6 * math.sin(a), y0 + 6 * math.cos(a)), (x1, y1), (x0 + 6 * math.sin(a), y0 - 6 * math.cos(a))], fill=c)
    d.ellipse((46, 46, 82, 82), fill=c)
    d.line([(52, 56), (64, 66), (74, 58)], fill=(30, 20, 20), width=4)

def shieldwave(d, c):
    # Shield Wave: a shield driven forward with arcs of force in front of it
    d.polygon([(14, 34), (54, 34), (54, 70), (34, 100), (14, 70)], fill=c)
    for r, w in ((30, 6), (44, 5), (58, 4)):
        d.arc((60 - r, 66 - r, 60 + r, 66 + r), -50, 50, fill=c, width=w)

def knives(d, c):
    # Fan of Knives: five knives spread in a fan
    for i in range(5):
        a = math.radians(-140 + i * 25)
        x1, y1 = 64 + 58 * math.cos(a), 112 + 58 * math.sin(a) * 1.5
        bx, by = 64 + 18 * math.cos(a), 112 + 18 * math.sin(a) * 1.5
        n = (-(y1 - by), x1 - bx)
        ln = math.hypot(*n) or 1
        nx, ny = n[0] / ln * 6, n[1] / ln * 6
        d.polygon([(bx + nx, by + ny), (x1, y1), (bx - nx, by - ny)], fill=c)
    d.ellipse((54, 102, 74, 122), fill=c)

GLYPH = {k: v for k, v in globals().items() if callable(v) and k in (
    'burst', 'bolt', 'drop', 'crystal', 'meteor', 'dots', 'shield', 'thorns', 'paw', 'leaf', 'swirl', 'cross', 'arrows',
    'ring', 'sword', 'slam', 'wave', 'arrowup', 'hammer', 'twin', 'dash', 'eye', 'ghost', 'rift', 'missile',
    'shuriken', 'daggers', 'smoke', 'katana', 'hood', 'greataxe', 'fang', 'skull', 'bonespear', 'golem', 'banner', 'ribs',
    'fist', 'palm', 'kick', 'flame', 'nodes', 'mountain', 'gate', 'flurry', 'sweep', 'palmwave',
    'ricochet', 'chain', 'shrapnel', 'shieldwave', 'knives')}

ICONS = [  # (spell name, theme, glyph)
    ('Rime Bloom', 'frost', 'burst'), ('Witchfire Bolt', 'fire', 'missile'), ('Forked Storm', 'light', 'bolt'),
    ('Crimson Covenant', 'blood', 'drop'), ('Falling Pyre', 'fire', 'meteor'), ('Frozen Crypt', 'frost', 'crystal'),
    ('Doomtide', 'fire', 'burst'), ('Blightswarm', 'poison', 'dots'), ('Purifying Wellspring', 'water', 'drop'),
    ('Ironbark Hide', 'nature', 'shield'), ('Briar Prison', 'nature', 'thorns'), ('Moonfang Pack', 'shadow', 'paw'),
    ('Verdant Sanctuary', 'nature', 'leaf'), ('Primordial Squall', 'light', 'swirl'), ('Dawnpiercer', 'holy', 'cross'),
    ('Skewering Line', 'steel', 'arrows'), ('Blessed Earth', 'holy', 'ring'), ('Lightward', 'holy', 'shield'),
    ('Final Verdict', 'holy', 'sword'), ('Hail of Dawn', 'holy', 'arrows'), ('Reaping Gyre', 'steel', 'swirl'),
    ('Earthbreaker', 'ember', 'slam'), ('Red Frenzy', 'blood', 'burst'), ('Iron Bellow', 'ember', 'wave'),
    ('Vaulting Cleave', 'steel', 'arrowup'), ("Colossus Fall", 'ember', 'hammer'), ('Hall of Mirrors', 'arcane', 'twin'),
    ('Umbral Stride', 'shadow', 'dash'), ('Shattered Psyche', 'arcane', 'eye'), ('Wraithshroud', 'shadow', 'ghost'),
    ('Nightburst', 'shadow', 'burst'), ('Tear in the Weave', 'arcane', 'rift'), ('Flickerdash', 'arcane', 'dash'),
    ('Banner Call', 'holy', 'wave'), ('Soulward', 'arcane', 'shield'), ("Hunter's Instinct", 'poison', 'eye'),
    # the Thief line (cells 237..245)
    ('Shuriken Toss', 'steel', 'shuriken'), ('Shadow Veil', 'shadow', 'hood'), ('Poison Blades', 'poison', 'daggers'),
    ('Shadow Step', 'shadow', 'dash'), ('Smoke Bomb', 'shadow', 'smoke'), ('Shuriken Barrage', 'steel', 'shuriken'),
    ('Counter Stance', 'ember', 'shield'), ('Iaijutsu', 'blood', 'katana'), ('Bushido Focus', 'light', 'katana'),
    # Berserker and Beastmaster (cells 246..249)
    ('Skyfall Cleave', 'ember', 'greataxe'), ('Bloodrage', 'blood', 'greataxe'), ('Wild Bond', 'nature', 'fang'),
    ('Feral Command', 'blood', 'fang'),
    # the Necromancer line (cells 250..258)
    ('Raise Dead', 'necrotic', 'skull'), ('Bone Spear', 'bone', 'bonespear'), ('Withering Curse', 'shadow', 'skull'),
    ('Soul Rot', 'necrotic', 'dots'), ('Life Siphon', 'blood', 'drop'), ('Corpse Explosion', 'necrotic', 'burst'),
    ('Bone Golem', 'bone', 'golem'), ('Banner of Bones', 'bone', 'banner'), ('Bone Offering', 'blood', 'ribs'),
    # the Monk line (cells 259..268)
    ('Ashen Fist', 'ember', 'fist'), ('Sundering Palm', 'steel', 'palm'), ('Whirling Heel', 'ember', 'kick'),
    ('Kindled Breath', 'light', 'flame'), ('Mistborne Step', 'water', 'dash'),
    ('Pressure Points', 'shadow', 'nodes'), ('Shadowfist Flurry', 'shadow', 'fist'),
    ('Chi Ward', 'holy', 'shield'), ('Iron Palm', 'steel', 'fist'), ('Mantra of Stone', 'light', 'mountain'),
    # the Templar line (cells 269..277)
    ('Radiant Smite', 'light', 'hammer'), ('Consecration', 'light', 'ring'), ('Vow of Mending', 'holy', 'drop'),
    ('Judgement', 'holy', 'eye'), ('Purging Nova', 'holy', 'burst'), ('Zealotry', 'ember', 'sword'),
    ('Rebuke', 'light', 'wave'), ('Aegis of Faith', 'light', 'shield'), ('Lay on Hands', 'light', 'cross'),
    # the Illusionist healer pass (cells 278..279)
    ('Mirror Mend', 'water', 'twin'), ('Lucid Reverie', 'arcane', 'ring'),
    # Town Portal, every class (cell 280)
    ('Town Portal', 'arcane', 'gate'),
    # the Thief line's self heal (cell 281)
    ('Shadow Mend', 'shadow', 'drop'),
    # build archetypes, second round (2026-10-12): the snares and the vigils
    ('Snare Trap', 'steel', 'fang'), ('Seeker Mine', 'ember', 'meteor'), ('Detonate Mines', 'fire', 'burst'),
    ('Vigil of Wrath', 'blood', 'banner'), ('Vigil of Iron', 'steel', 'shield'), ('Vigil of Haste', 'nature', 'dash'),
    ('Vigil of Clarity', 'water', 'ring'),
    # pack farming (2026-10-15): the Thief line's area strikes (cells 289..290)
    ('Blade Flurry', 'steel', 'flurry'), ('Iaido Sweep', 'blood', 'sweep'),
    # the pack tools of the second pass (cells 291..297)
    ('Palm Shockwave', 'ember', 'palmwave'), ('Shadow Ricochet', 'shadow', 'ricochet'), ('Iron Chain', 'steel', 'chain'),
    ('Bone Shrapnel', 'bone', 'shrapnel'), ('Sanctified Ground', 'holy', 'ring'), ('Shield Wave', 'light', 'shieldwave'),
    ('Fan of Knives', 'steel', 'knives'),
    # the Necromancer line's summon spells (2026-10-18, cells 298..300: the last three of the 300-cell sheets)
    ('Raise Bone Warrior', 'bone', 'sword'), ('Raise Bone Archer', 'bone', 'arrows'), ('Raise Bone Mage', 'necrotic', 'eye'),
    # the late spells of the ascended classes (C6, 2026-10-20): cells 301..307, past the old 300-cell sheets (the sheets get a 16th row)
    ('Bastion Cry', 'steel', 'banner'), ('Anvil Fall', 'steel', 'hammer'), ('Twin Verdict', 'holy', 'twin'),
    ('Rampage Leap', 'blood', 'slam'), ('Glacial Doom', 'frost', 'swirl'), ('Pack Frenzy', 'nature', 'paw'),
    ('Shuriken Tempest', 'steel', 'shuriken'),
    # the Ranger line's fight buff in place of the stock Hawkeye (2026-10-20, cell 308)
    ('Tautstring', 'nature', 'arrowup')]

def render(theme, glyph):
    c = COL[theme]
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # dark plate with a themed inner glow and an iron rim
    d.rounded_rectangle((2, 2, S - 3, S - 3), 14, fill=(18, 13, 18, 255), outline=(120, 108, 112, 255), width=4)
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((14, 14, S - 14, S - 14), fill=c + (150,))
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    img = Image.alpha_composite(img, glow)
    g = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    GLYPH[glyph](gd, c + (255,))
    shadow = g.filter(ImageFilter.GaussianBlur(3))
    dark = Image.new('RGBA', (S, S), (0, 0, 0, 0)); dark.putalpha(shadow.getchannel('A').point(lambda v: int(v * .7)))
    img = Image.alpha_composite(img, dark)
    # shrink the glyph a little so it sits inside the rim
    g = g.resize((92, 92), Image.LANCZOS)
    hi = Image.new('RGBA', g.size, (255, 255, 255, 0)); hi.putalpha(g.getchannel('A').point(lambda v: int(v * .25)))
    g = Image.alpha_composite(g, hi)
    img.alpha_composite(g, (18, 18))
    return img

def main():
    out = sys.argv[1]
    for sub in ('32', '22x24', '20'):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    for i, (name, theme, glyph) in enumerate(ICONS, 1):
        big = render(theme, glyph)
        big.resize((32, 32), Image.LANCZOS).save(os.path.join(out, '32', f'{i:02d}.png'))
        big.resize((22, 24), Image.LANCZOS).save(os.path.join(out, '22x24', f'{i:02d}.png'))
        big.resize((20, 20), Image.LANCZOS).save(os.path.join(out, '20', f'{i:02d}.png'))
    print(len(ICONS), 'icons written to', out)

if __name__ == '__main__':
    main()
