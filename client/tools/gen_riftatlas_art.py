#!/usr/bin/env python3
"""Procedural art of the Rift Atlas window (client module game_riftatlas).
Run: python3 -I client/tools/gen_riftatlas_art.py client/overlay/data/images/riftatlas
Writes into that folder:
  icons_<set>.png   one row of 64x64 round node icons per colour set (core, abyss, hall, crypt, sanctum), in the
                    order of GLYPHS below; riftatlasview.lua RiftAtlasView.GLYPHS has the same order (cell x = index * 64)
  start.png         the start node, a 150x150 medallion
  background.png    the map backdrop (1024x1024): rings and the glow of the four theme branches
The node frames and the link lines are the passive tree's (/images/passivetree/...), so both maps look alike.
Same plate, glow and glyph style as the Chaos spell icons (gen_spell_icons.py). Needs Pillow."""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_spell_icons as base  # noqa: E402

CELL = 64
INK = (14, 8, 14, 255)


def hourglass(d, c):
    d.rectangle((26, 10, 102, 20), fill=c)
    d.rectangle((26, 108, 102, 118), fill=c)
    d.polygon([(34, 22), (94, 22), (68, 64), (94, 106), (34, 106), (60, 64)], fill=c)
    d.polygon([(46, 30), (82, 30), (64, 56)], fill=INK)
    d.polygon([(64, 74), (82, 100), (46, 100)], fill=(255, 255, 255, 110))


def key(d, c):
    d.ellipse((14, 14, 62, 62), fill=c)
    d.ellipse((28, 28, 48, 48), fill=INK)
    d.polygon([(52, 46), (60, 38), (118, 96), (110, 104)], fill=c)
    d.rectangle((86, 84, 96, 108), fill=c)
    d.rectangle((100, 96, 110, 116), fill=c)


def upkey(d, c):
    key(d, c)
    d.polygon([(96, 6), (122, 34), (106, 34), (106, 56), (86, 56), (86, 34), (70, 34)], fill=c)


def coins(d, c):
    for i, y in enumerate((96, 78, 60, 42)):
        x = 44 + (i % 2) * 6
        d.ellipse((x - 26, y - 10, x + 26, y + 10), fill=c)
        d.ellipse((x - 26, y - 14, x + 26, y + 6), fill=c)
        d.arc((x - 26, y - 14, x + 26, y + 6), 0, 180, fill=INK, width=3)
    d.ellipse((70, 70, 120, 120), fill=c)
    d.ellipse((82, 82, 108, 108), outline=INK, width=4)


def compass(d, c):
    # a chart's rose: the reward of reading the rift
    d.ellipse((10, 10, 118, 118), outline=c, width=6)
    for i in range(4):
        a = math.pi * i / 2
        tip = (64 + 56 * math.cos(a), 64 + 56 * math.sin(a))
        l = (64 + 14 * math.cos(a - math.pi / 2), 64 + 14 * math.sin(a - math.pi / 2))
        r = (64 + 14 * math.cos(a + math.pi / 2), 64 + 14 * math.sin(a + math.pi / 2))
        d.polygon([tip, l, (64, 64), r], fill=c)
    for i in range(4):
        a = math.pi * i / 2 + math.pi / 4
        tip = (64 + 36 * math.cos(a), 64 + 36 * math.sin(a))
        d.polygon([tip, (64 + 9 * math.cos(a - 1.2), 64 + 9 * math.sin(a - 1.2)),
                   (64 + 9 * math.cos(a + 1.2), 64 + 9 * math.sin(a + 1.2))], fill=c)
    d.ellipse((56, 56, 72, 72), fill=INK)


def star(d, c):
    pts = []
    for i in range(10):
        a = math.pi * i / 5 - math.pi / 2
        r = 58 if i % 2 == 0 else 24
        pts.append((64 + r * math.cos(a), 66 + r * math.sin(a)))
    d.polygon(pts, fill=c)


def orb(d, c):
    d.ellipse((16, 16, 112, 112), fill=c)
    d.ellipse((30, 30, 98, 98), fill=INK)
    base.swirl(d, c)
    d.ellipse((34, 28, 56, 46), fill=(255, 255, 255, 140))


def chest(d, c):
    d.rounded_rectangle((14, 52, 114, 112), 6, fill=c)
    d.pieslice((14, 18, 114, 86), 180, 360, fill=c)
    d.rectangle((14, 50, 114, 58), fill=INK)
    d.rectangle((56, 44, 72, 76), fill=INK)
    d.rectangle((60, 48, 68, 70), fill=c)


def coffer(d, c):
    chest(d, c)
    for x in (30, 98):
        d.rectangle((x - 4, 22, x + 4, 112), fill=INK)
    d.ellipse((52, 74, 76, 98), fill=INK)
    d.rectangle((60, 84, 68, 106), fill=INK)


def sack(d, c):
    # the goblin's loot sack
    d.ellipse((18, 40, 110, 122), fill=c)
    d.polygon([(44, 44), (84, 44), (96, 14), (32, 14)], fill=c)
    d.rectangle((40, 38, 88, 48), fill=INK)
    d.ellipse((50, 66, 78, 94), outline=INK, width=6)
    d.line([(64, 62), (64, 98)], fill=INK, width=5)


def heart(d, c):
    d.ellipse((14, 20, 68, 74), fill=c)
    d.ellipse((60, 20, 114, 74), fill=c)
    d.polygon([(18, 58), (110, 58), (64, 116)], fill=c)
    d.ellipse((30, 32, 50, 50), fill=(255, 255, 255, 110))


def crown(d, c):
    d.polygon([(10, 100), (16, 36), (40, 66), (64, 22), (88, 66), (112, 36), (118, 100)], fill=c)
    d.rectangle((12, 102, 116, 118), fill=c)
    for x in (16, 64, 112):
        d.ellipse((x - 8, 18 if x == 64 else 30, x + 8, 34 if x == 64 else 46), fill=c)
    d.ellipse((56, 80, 72, 96), fill=INK)


def ember(d, c):
    # a single ember: one life, burning hot
    d.polygon([(64, 6), (98, 56), (96, 92), (64, 118), (32, 92), (30, 56)], fill=c)
    d.polygon([(64, 46), (80, 78), (64, 104), (48, 78)], fill=INK)
    d.ellipse((56, 70, 72, 92), fill=c)


def tide(d, c):
    # many marks on the floor: the packs
    for x, y, r in [(32, 36, 15), (66, 28, 12), (96, 44, 15), (44, 76, 17), (84, 84, 17), (58, 112, 10), (106, 108, 9)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c)
        d.ellipse((x - r // 3, y - r // 3, x + r // 3, y + r // 3), fill=INK)


GLYPHS = [  # (name, drawing): riftatlasview.lua RiftAtlasView.GLYPHS lists the same names in this order
    ('density', tide), ('elite', star), ('time', hourglass), ('reward', compass), ('gold', coins), ('key', key),
    ('upgrade', upkey), ('fragment', base.crystal), ('orb', orb), ('rolls', chest), ('goblin', sack), ('coffer', coffer),
    ('life', heart), ('theme_abyss', base.eye), ('theme_hall', base.flame), ('theme_crypt', base.skull),
    ('theme_sanctum', base.leaf), ('ks_ember', ember), ('ks_crown', crown), ('ks_ascent', upkey),
    ('ks_hourglass', hourglass),
]

SETS = [  # (sheet, colour theme of gen_spell_icons.COL)
    ('core', 'light'), ('abyss', 'shadow'), ('hall', 'fire'), ('crypt', 'bone'), ('sanctum', 'nature'),
]


def render_round(theme, fn):
    """The plate of gen_spell_icons.render, cut to a circle (the passive tree frames are round)."""
    name = '_atlas_' + fn.__name__
    base.GLYPH[name] = fn
    img = base.render(theme, name)
    n = img.size[0]
    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).ellipse((4, 4, n - 5, n - 5), fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def start_image():
    n = 300
    icon = render_round('holy', compass).resize((n, n), Image.LANCZOS)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    out.alpha_composite(icon)
    d = ImageDraw.Draw(out)
    d.ellipse((6, 6, n - 7, n - 7), outline=(92, 66, 34, 255), width=14)
    d.ellipse((10, 10, n - 11, n - 11), outline=(196, 158, 88, 255), width=6)
    # four notches, one toward each branch
    for i, col in enumerate(((154, 106, 232), (232, 128, 58), (200, 184, 144), (127, 200, 106))):
        a = -math.pi / 2 + i * math.pi / 2
        x, y = n / 2 + (n / 2 - 12) * math.cos(a), n / 2 + (n / 2 - 12) * math.sin(a)
        d.ellipse((x - 14, y - 14, x + 14, y + 14), fill=col + (255,), outline=(60, 40, 20, 255), width=4)
    return out.resize((150, 150), Image.LANCZOS)


def background(size=1024, seed=7):
    rnd = random.Random(seed)
    img = Image.new('RGBA', (size, size), (10, 8, 12, 255))
    c = size / 2
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    # the four branches: north abyss, east hall, south crypt, west sanctum
    for (dx, dy), col in (((0, -1), (110, 60, 190)), ((1, 0), (190, 80, 30)), ((0, 1), (150, 130, 95)),
                          ((-1, 0), (70, 140, 60))):
        x, y = c + dx * size * 0.32, c + dy * size * 0.32
        r = size * 0.24
        g.ellipse((x - r, y - r, x + r, y + r), fill=col + (90,))
    g.ellipse((c - size * 0.16, c - size * 0.16, c + size * 0.16, c + size * 0.16), fill=(200, 160, 80, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(size / 14))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    # chart rings and spokes
    for r in (0.13, 0.27, 0.41, 0.48):
        rr = size * r
        d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=(120, 100, 70, 46), width=2)
    for i in range(16):
        a = math.pi * i / 8
        d.line([(c + size * 0.06 * math.cos(a), c + size * 0.06 * math.sin(a)),
                (c + size * 0.49 * math.cos(a), c + size * 0.49 * math.sin(a))], fill=(120, 100, 70, 22), width=1)
    # dust
    for _ in range(900):
        x, y = rnd.random() * size, rnd.random() * size
        v = rnd.randint(60, 170)
        a = rnd.randint(30, 120)
        rr = rnd.choice((0.6, 0.8, 1.0, 1.4))
        d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=(v, v - 10, v - 25, a))
    # dark rim so the edge of the map fades out
    rim = Image.new('L', (size, size), 0)
    ImageDraw.Draw(rim).ellipse((size * 0.02, size * 0.02, size * 0.98, size * 0.98), fill=255)
    rim = rim.filter(ImageFilter.GaussianBlur(size / 16))
    dark = Image.new('RGBA', (size, size), (6, 5, 8, 255))
    return Image.composite(img, dark, rim)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'client/overlay/data/images/riftatlas'
    os.makedirs(out, exist_ok=True)
    for name, theme in SETS:
        sheet = Image.new('RGBA', (CELL * len(GLYPHS), CELL), (0, 0, 0, 0))
        for i, (_, fn) in enumerate(GLYPHS):
            sheet.alpha_composite(render_round(theme, fn).resize((CELL, CELL), Image.LANCZOS), (i * CELL, 0))
        sheet.save(os.path.join(out, 'icons_%s.png' % name), optimize=True)
    start_image().save(os.path.join(out, 'start.png'), optimize=True)
    background().convert('RGB').save(os.path.join(out, 'background.png'), optimize=True)
    print(len(SETS), 'icon sheets of', len(GLYPHS), 'icons, start.png and background.png written to', out)


if __name__ == '__main__':
    main()
