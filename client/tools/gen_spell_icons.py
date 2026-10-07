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

GLYPH = {k: v for k, v in globals().items() if callable(v) and k in (
    'burst', 'bolt', 'drop', 'crystal', 'meteor', 'dots', 'shield', 'thorns', 'paw', 'leaf', 'swirl', 'cross', 'arrows',
    'ring', 'sword', 'slam', 'wave', 'arrowup', 'hammer', 'twin', 'dash', 'eye', 'ghost', 'rift', 'missile')}

ICONS = [  # (spell name, theme, glyph)
    ('Frost Nova', 'frost', 'burst'), ('Hexfire Bolt', 'fire', 'missile'), ('Chain Lightning', 'light', 'bolt'),
    ('Blood Pact', 'blood', 'drop'), ('Meteor Strike', 'fire', 'meteor'), ('Glacial Tomb', 'frost', 'crystal'),
    ('Cataclysm', 'fire', 'burst'), ('Venom Swarm', 'poison', 'dots'), ('Cleansing Spring', 'water', 'drop'),
    ('Barkskin', 'nature', 'shield'), ('Thorn Cage', 'nature', 'thorns'), ('Spirit Wolves', 'shadow', 'paw'),
    ('Rejuvenating Grove', 'nature', 'leaf'), ('Ancient Tempest', 'light', 'swirl'), ('Holy Smite', 'holy', 'cross'),
    ('Piercing Volley', 'steel', 'arrows'), ('Consecration', 'holy', 'ring'), ('Divine Ward', 'holy', 'shield'),
    ('Judgement', 'holy', 'sword'), ('Sanctified Barrage', 'holy', 'arrows'), ('Whirlwind', 'steel', 'swirl'),
    ('Ground Slam', 'ember', 'slam'), ('Crimson Fury', 'blood', 'burst'), ('Warcry', 'ember', 'wave'),
    ('Leaping Strike', 'steel', 'arrowup'), ("Titan's Wrath", 'ember', 'hammer'), ('Mirror Image', 'arcane', 'twin'),
    ('Shadow Step', 'shadow', 'dash'), ('Mind Fracture', 'arcane', 'eye'), ('Phantom Veil', 'shadow', 'ghost'),
    ('Umbral Eruption', 'shadow', 'burst'), ('Reality Rift', 'arcane', 'rift'), ('Blink Dash', 'arcane', 'dash'),
    ('Rallying Cry', 'holy', 'wave'), ('Soul Aegis', 'arcane', 'shield'), ('Sense Prey', 'poison', 'eye')]

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
