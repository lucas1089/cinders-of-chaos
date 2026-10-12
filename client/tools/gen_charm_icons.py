#!/usr/bin/env python3
"""Icons of the charms (client module game_charms): one 32x32 icon per charm modifier of the pool and per unique charm,
the generic charm icon and the locked-cell padlock.

Run: python3 client/tools/gen_charm_icons.py [OUTDIR] [--sheet SHEET.png]
     default OUTDIR: client/overlay/data/images/game/charms  ->  <key>.png (dmg_undead.png, res_fire.png, goldfind.png,
     gravewarden.png, ...), charm.png, locked.png
     --sheet writes a labelled contact sheet (3x)

Art, donor art first: an icon is a cell of the element ability icon sets (spell_icon_art/spell_icons_32.png, the sets
build_spell_icon_art.py copies in; tags in spell_icon_art/icon_tags.csv) whose set and tags fit the modifier (WANT
below), set into a round charm setting: a dark plate, the art inside a circle and a bronze rim. No two charm icons share
a cell. A key whose wanted sets carry none of its tags is drawn (a plain glyph on the same setting); the padlock is
always drawn. The keys come from server/data/scripts/chaos/charms_config.lua (a pool key or unique without an entry
here stops the run). Our own art; deterministic. Needs Pillow."""
import csv, math, os, re, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ART = os.path.join(HERE, 'spell_icon_art')
SHEET = os.path.join(ART, 'spell_icons_32.png')
CONFIG = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'charms_config.lua')
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'charms')
N = 32

# name -> (icon sets best first, tags best first)
WANT = {
    'dmg_dragons': (['Fire'], ['claw', 'wave', 'burst']),
    'dmg_demons': (['Blood', 'Fire'], ['challenge', 'avatar', 'burst']),
    'dmg_undead': (['Arcane', 'Blood'], ['holyground', 'virtue', 'light']),
    'dmg_humans': (['Steel'], ['melee', 'strike', 'spear']),
    'dmg_humanoids': (['Steel', 'Nature'], ['fist', 'melee', 'claw']),
    'dmg_beasts': (['Nature'], ['claw', 'summon']),
    'dmg_elementals': (['Water', 'Arcane'], ['burstring', 'wave', 'beam']),
    'dmg_vermin': (['Nature', 'Blood'], ['dot', 'area']),
    'res_fire': (['Fire'], ['shield', 'burstring', 'wave']),
    'res_ice': (['Water'], ['shield']),
    'res_energy': (['Arcane', 'Water'], ['shield', 'beam', 'flash']),
    'res_earth': (['Nature'], ['shield']),
    'res_death': (['Blood', 'Arcane'], ['shield', 'cure', 'invis', 'burstring']),
    'res_holy': (['Steel', 'Fire'], ['virtue', 'shield', 'light']),
    'lifeonkill': (['Blood', 'Nature'], ['regen', 'heal']),
    'goldfind': (['Steel', 'Fire'], ['find', 'food', 'rune']),
    'orbfind': (['Arcane', 'Water'], ['find', 'reveal', 'rune']),
    'oocspeed': (['Nature', 'Water', 'Steel'], ['haste', 'levitate']),
    'reputation': (['Steel', 'Fire'], ['party', 'buff', 'virtue']),
    'rifttime': (['Arcane'], ['illusion', 'meditate', 'invis']),
    'gravewarden': (['Blood', 'Arcane'], ['avatar', 'holyground', 'summon']),
    'compass': (['Water', 'Nature'], ['levitate', 'haste', 'rope']),
    'hoard': (['Fire', 'Steel'], ['find', 'flash', 'light']),
    'tally': (['Blood'], ['heal', 'regen', 'claw']),
    'charm': (['Arcane', 'Fire'], ['buff', 'flash', 'light']),
}
DRAWN = ('locked',)

PLATE = (24, 18, 22, 255)
RIM_DARK = (92, 58, 26, 255)
RIM_LIGHT = (214, 160, 78, 255)
GLINT = (255, 226, 160, 255)


def sheet_cells():
    """(set, index) -> the cell of the spell icon sheet, and the tags of every (set, index)"""
    cells = {}
    for name in ('chaos_spell_icons.csv', 'stock_spell_icons.csv'):
        with open(os.path.join(ART, name), encoding='utf-8') as f:
            for r in csv.DictReader(f):
                cells.setdefault((r['set'], int(r['index'])), int(r['cell']))
    tags = {}
    with open(os.path.join(ART, 'icon_tags.csv'), encoding='utf-8') as f:
        for r in csv.DictReader(f):
            tags[(r['set'], int(r['index']))] = r['tags'].split()
    return cells, tags


def choose():
    """name -> sheet cell (or None: drawn); the names in sorted order take the first free fit"""
    cells, tags = sheet_cells()
    taken, out = set(), {}
    for name in sorted(WANT):
        sets, want = WANT[name]
        pick = None
        for tag in want:
            for s in sets:
                for key in sorted(k for k in cells if k[0] == s):
                    cell = cells[key]
                    if cell in taken or tag not in tags.get(key, []):
                        continue
                    pick = cell
                    break
                if pick:
                    break
            if pick:
                break
        if pick:
            taken.add(pick)
        out[name] = pick
    return out


def setting(art=None):
    """the round charm setting: plate, the art inside a circle, a two-tone rim and a glint"""
    size = N * 4
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((2, 2, size - 3, size - 3), fill=RIM_DARK)
    d.ellipse((8, 8, size - 9, size - 9), fill=RIM_LIGHT)
    d.ellipse((14, 14, size - 15, size - 15), fill=PLATE)
    if art is not None:
        inner = art.resize((size - 32, size - 32), Image.NEAREST)
        mask = Image.new('L', inner.size, 0)
        ImageDraw.Draw(mask).ellipse((0, 0, inner.size[0] - 1, inner.size[1] - 1), fill=255)
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        layer.paste(inner, (16, 16), mask)
        im = Image.alpha_composite(im, layer)
        d = ImageDraw.Draw(im)
    d.arc((10, 10, size - 11, size - 11), 200, 250, fill=GLINT, width=4)
    return im.resize((N, N), Image.LANCZOS)


def draw_locked():
    size = N * 4
    art = Image.new('RGBA', (size, size), PLATE)
    d = ImageDraw.Draw(art)
    d.rounded_rectangle((34, 58, 94, 104), radius=8, fill=(150, 140, 128, 255), outline=(60, 54, 50, 255), width=4)
    d.arc((44, 24, 84, 76), 180, 360, fill=(170, 160, 146, 255), width=10)
    d.line((44, 50, 44, 60), fill=(170, 160, 146, 255), width=10)
    d.line((84, 50, 84, 60), fill=(170, 160, 146, 255), width=10)
    d.ellipse((58, 70, 70, 82), fill=(40, 34, 32, 255))
    d.rectangle((62, 78, 66, 94), fill=(40, 34, 32, 255))
    return setting(art.resize((N, N), Image.LANCZOS))


def draw_glyph(name):
    """a plain glyph when no donor cell fits: a rune-like star"""
    size = N * 4
    art = Image.new('RGBA', (size, size), PLATE)
    d = ImageDraw.Draw(art)
    pts = []
    for i in range(10):
        r = 46 if i % 2 == 0 else 20
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((64 + r * math.cos(a), 64 + r * math.sin(a)))
    d.polygon(pts, fill=(226, 170, 84, 255))
    return setting(art.resize((N, N), Image.LANCZOS))


def build_all():
    sheet = Image.open(SHEET).convert('RGBA')
    picks = choose()
    icons, source = {}, {}
    for name in sorted(WANT):
        cell = picks[name]
        if cell:
            n = cell - 1
            art = sheet.crop(((n % 20) * 32, (n // 20) * 32, (n % 20) * 32 + 32, (n // 20) * 32 + 32))
            if art.getextrema()[3][1] == 0:
                raise SystemExit('spell icon cell %d is empty' % cell)
            icons[name] = setting(art)
            source[name] = 'cell %d' % cell
        else:
            icons[name] = draw_glyph(name)
            source[name] = 'drawn'
    icons['locked'] = draw_locked()
    source['locked'] = 'drawn'
    return icons, source


def check():
    """every pool key and unique of charms_config.lua has an entry here, and nothing else"""
    if not os.path.exists(CONFIG):
        return
    text = open(CONFIG, encoding='utf-8').read()
    keys = set('dmg_' + k for k in re.findall(r'family\("(\w+)"', text))
    keys |= set('res_' + k for k in re.findall(r'element\("(\w+)"', text))
    pool = re.search(r'\nC\.pool = \{(.*?)\n\}', text, re.S).group(1)
    keys |= set(re.findall(r'\{key = "(\w+)"', pool))
    uniques = re.search(r'\nC\.uniques = \{(.*?)\n\}', text, re.S).group(1)
    keys |= set(re.findall(r'\n\t(\w+) = \{mods', uniques))
    keys.add('charm')
    if keys != set(WANT):
        raise SystemExit('WANT does not match charms_config.lua: missing %s, unused %s' %
                         (sorted(keys - set(WANT)), sorted(set(WANT) - keys)))


def contact_sheet(icons, source, path, scale=3):
    names = sorted(icons)
    cols, cw, ch = 6, N * scale + 40, N * scale + 34
    rows = (len(names) + cols - 1) // cols
    im = Image.new('RGB', (cols * cw + 16, rows * ch + 16), (22, 18, 20))
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        x, y = 8 + (i % cols) * cw + 20, 8 + (i // cols) * ch
        big = icons[n].resize((N * scale, N * scale), Image.NEAREST)
        im.paste(big, (x, y), big)
        for j, t in enumerate((n[:16], source[n])):
            tw = d.textlength(t)
            d.text((x + (N * scale - tw) / 2, y + N * scale + 3 + j * 11), t, fill=(240, 222, 180))
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
    icons, source = build_all()
    os.makedirs(out, exist_ok=True)
    for name, im in icons.items():
        im.save(os.path.join(out, name + '.png'), optimize=True)
    if sheet:
        contact_sheet(icons, source, sheet)
    drawn = sorted(n for n in source if source[n] == 'drawn')
    print(len(icons), 'charm icons written to', out, '(%d from the icon sets, drawn: %s)' %
          (len(icons) - len(drawn), ', '.join(drawn) or 'none'))


if __name__ == '__main__':
    main()
