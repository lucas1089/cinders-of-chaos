#!/usr/bin/env python3
"""Art of the battleground and PvP seasons (client module game_battleground): the six season tier emblems, the three
brazier states of the Ember Wells HUD and the honor icon.

Run: python3 client/tools/gen_battleground_art.py [OUTDIR] [--sheet SHEET.png]
     default OUTDIR: client/overlay/data/images/chaos/battleground  ->  tier_<key>.png (36x36, keys from
     server/data/scripts/chaos/battleground_config.lua season.tiers), well_0.png / well_1.png / well_2.png (20x20:
     neutral, Emberguard, Ashbound), honor.png (16x16)
     --sheet writes a labelled contact sheet (4x)

Art, donor art first: every emblem holds a cell of the element ability icon sets (spell_icon_art/spell_icons_32.png;
tags in spell_icon_art/icon_tags.csv) whose set and tags fit the tier (WANT), never a cell the buff bar, the Ember
Descent or the raid icons already show; the crest around it (a heater shield in the tier's colour ramp of
gen_buff_icons.py with one gem per tier along its top) and the brazier icons are drawn here. The honor icon takes a
Steel cell in a gold ring. Deterministic. Needs Pillow."""
import os, re, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_buff_icons as B  # noqa: E402
import gen_descent_icons as D  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'chaos', 'battleground')
CONFIG = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'battleground_config.lua')

# tier key -> (colour ramp of gen_buff_icons.R, icon sets best first, tags best first)
WANT = {
    'ashen': ('steel', ['Steel'], ['strike', 'melee']),
    'smoulder': ('wood', ['Fire'], ['dot', 'area']),
    'kindled': ('gold', ['Fire'], ['strike', 'wand']),
    'blazing': ('ember', ['Fire'], ['burst', 'area']),
    'infernal': ('blood', ['Blood', 'Fire'], ['burst', 'avatar', 'challenge']),
    'sovereign': ('holy', ['Arcane', 'Fire'], ['avatar', 'buff']),
}
HONOR = ('gold', ['Steel'], ['challenge', 'buff', 'melee'])
E = 36  # emblem size
SS = 4  # supersampling of the drawn shapes


def taken_cells():
    """cells the buff bar, the Descent and the raid icons already show"""
    taken = set(D.buffbar_cells())
    taken |= {c for c in D.choose().values() if c}
    try:
        import gen_raid_icons as RA  # noqa: E402
        taken |= {c for c in RA.choose().values() if c}
    except (ImportError, OSError, SystemExit):
        pass
    return taken


def choose():
    """name -> sheet cell, deterministic: the names in config order take the first free fit"""
    cells, tags = D.sheet_cells()
    taken = taken_cells()
    out = {}
    for name, (_ramp, sets, want) in list(WANT.items()) + [('honor', HONOR)]:
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
        if not pick:
            raise SystemExit('no free icon cell for %s' % name)
        taken.add(pick)
        out[name] = pick
    return out


def cell_image(sheet, cell, size):
    n = cell - 1
    icon = sheet.crop(((n % 20) * 32, (n // 20) * 32, (n % 20) * 32 + 32, (n // 20) * 32 + 32))
    inner = icon.crop((2, 2, 30, 30))
    if inner.getextrema()[3][1] == 0:
        raise SystemExit('spell icon cell %d is empty' % cell)
    return inner.resize((size, size), Image.LANCZOS)


def shield_points(s, inset=0.0):
    """a heater shield in an E x E box (scaled by s), inset in pixels"""
    i = inset
    return [((3 + i) * s, (4 + i) * s), ((E - 3 - i) * s, (4 + i) * s), ((E - 3 - i) * s, (17) * s),
            ((E / 2) * s, (E - 1.5 - i * 1.4) * s), ((3 + i) * s, 17 * s)]


def emblem(sheet, cell, ramp_name, gems):
    r = B.R[ramp_name]
    big = Image.new('RGBA', (E * SS, E * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.polygon(shield_points(SS), fill=B.INK + (255,))
    d.polygon(shield_points(SS, 1.0), fill=r[1] + (255,))
    d.polygon(shield_points(SS, 2.0), fill=r[3] + (255,))
    d.polygon(shield_points(SS, 3.0), fill=B.mix((16, 12, 14), r[0], 0.55) + (255,))
    im = big.resize((E, E), Image.LANCZOS)
    # the donor picture inside, masked to the shield's field
    art = cell_image(sheet, cell, 20)
    mask_big = Image.new('L', (E * SS, E * SS), 0)
    ImageDraw.Draw(mask_big).polygon(shield_points(SS, 3.4), fill=255)
    mask = mask_big.resize((E, E), Image.LANCZOS).crop((8, 8, 28, 28))
    tint = Image.new('RGBA', art.size, r[2] + (255,))
    art = Image.blend(art, Image.composite(tint, art, art.split()[3]), 0.18)
    layer = Image.new('RGBA', (E, E), (0, 0, 0, 0))
    a = art.copy()
    a.putalpha(Image.composite(art.split()[3], Image.new('L', art.size, 0), mask))
    layer.paste(a, (8, 8), a)
    im = Image.alpha_composite(im, layer)
    # one gem per tier along the top edge
    g = ImageDraw.Draw(im)
    w = 4
    total = gems * w + (gems - 1) * 1
    x0 = (E - total) // 2
    for i in range(gems):
        x = x0 + i * (w + 1)
        g.rectangle((x, 1, x + w - 1, 4), fill=B.INK + (255,))
        g.rectangle((x + 1, 2, x + w - 2, 3), fill=r[4] + (255,))
    return im


def well(team):
    """a brazier basin: neutral (grey coals), team 1 (ember flame), team 2 (frost flame)"""
    n = 20
    big = Image.new('RGBA', (n * SS, n * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    flame = {0: B.R['steel'], 1: B.R['ember'], 2: B.R['frost']}[team]
    basin = B.R['obsidian']
    s = SS
    # flame (three tongues) behind the rim
    if team:
        d.polygon([(10 * s, 1 * s), (14 * s, 7 * s), (13 * s, 11 * s), (7 * s, 11 * s), (6 * s, 7 * s)], fill=flame[2] + (255,))
        d.polygon([(5 * s, 4 * s), (8 * s, 9 * s), (5 * s, 11 * s), (3 * s, 8 * s)], fill=flame[1] + (255,))
        d.polygon([(15 * s, 4 * s), (17 * s, 8 * s), (15 * s, 11 * s), (12 * s, 9 * s)], fill=flame[1] + (255,))
        d.polygon([(10 * s, 5 * s), (12 * s, 9 * s), (10 * s, 11 * s), (8 * s, 9 * s)], fill=flame[4] + (255,))
    else:
        for (x, y) in ((6, 9), (10, 8), (13, 9)):
            d.ellipse(((x - 2) * s, (y - 1) * s, (x + 2) * s, (y + 2) * s), fill=flame[1] + (255,))
    # bowl, rim and foot
    d.polygon([(2 * s, 11 * s), (18 * s, 11 * s), (15 * s, 16 * s), (5 * s, 16 * s)], fill=B.INK + (255,))
    d.polygon([(3 * s, 11.5 * s), (17 * s, 11.5 * s), (14.5 * s, 15.3 * s), (5.5 * s, 15.3 * s)], fill=basin[2] + (255,))
    d.rectangle((2 * s, 10 * s, 18 * s, 12 * s - 1), fill=basin[3] + (255,))
    d.rectangle((8 * s, 16 * s, 12 * s, 18 * s), fill=B.INK + (255,))
    d.rectangle((6 * s, 18 * s, 14 * s, 19 * s), fill=basin[1] + (255,))
    return big.resize((n, n), Image.LANCZOS)


def honor_icon(sheet, cell):
    n = 16
    big = Image.new('RGBA', (n * SS, n * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    g = B.R['gold']
    d.ellipse((0, 0, n * SS - 1, n * SS - 1), fill=B.INK + (255,))
    d.ellipse((SS, SS, (n - 1) * SS - 1, (n - 1) * SS - 1), fill=g[3] + (255,))
    d.ellipse((2 * SS, 2 * SS, (n - 2) * SS - 1, (n - 2) * SS - 1), fill=(24, 18, 14, 255))
    im = big.resize((n, n), Image.LANCZOS)
    art = cell_image(sheet, cell, 10)
    im.paste(art, (3, 3), art)
    return im


def config_tiers():
    """the tier keys of battleground_config.lua, in order (None when it is not found)"""
    if not os.path.exists(CONFIG):
        return None
    text = open(CONFIG, encoding='utf-8').read()
    block = re.search(r'\btiers = \{(.*?)\n\t\t\},', text, re.S).group(1)
    return re.findall(r'key = "(\w+)"', block)


def build_all():
    keys = config_tiers()
    if keys is not None and keys != list(WANT):
        raise SystemExit('WANT does not match battleground_config.lua season.tiers: %s' % keys)
    sheet = Image.open(B.SPELL_ART).convert('RGBA')
    picks = choose()
    out = {}
    for i, (name, (ramp, _sets, _want)) in enumerate(WANT.items()):
        out['tier_' + name] = emblem(sheet, picks[name], ramp, i + 1)
    for team in (0, 1, 2):
        out['well_%d' % team] = well(team)
    out['honor'] = honor_icon(sheet, picks['honor'])
    return out, picks


def contact_sheet(icons, path, scale=4):
    names = list(icons)
    cw, ch = E * scale + 30, E * scale + 24
    im = Image.new('RGB', (len(names) * cw + 16, ch + 16), (22, 18, 20))
    d = ImageDraw.Draw(im)
    for i, nme in enumerate(names):
        ic = icons[nme]
        big = ic.resize((ic.width * scale, ic.height * scale), Image.NEAREST)
        x, y = 8 + i * cw + (cw - big.width) // 2, 8 + (E * scale - big.height) // 2
        im.paste(big, (x, y), big)
        tw = d.textlength(nme)
        d.text((8 + i * cw + (cw - tw) / 2, 8 + E * scale + 6), nme, fill=(240, 222, 180))
    im.save(path)


def main():
    args = sys.argv[1:]
    sheet = None
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else DEFAULT_OUT
    icons, picks = build_all()
    os.makedirs(out, exist_ok=True)
    for name, im in icons.items():
        im.save(os.path.join(out, name + '.png'), optimize=True)
    if sheet:
        contact_sheet(icons, sheet)
    print(len(icons), 'battleground images written to', out, '(cells: %s)' %
          ', '.join('%s %d' % (k, v) for k, v in picks.items()))


if __name__ == '__main__':
    main()
