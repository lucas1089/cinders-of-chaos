#!/usr/bin/env python3
"""Icons of the Ember Descent's boons and curses (client module game_descent and the buff bar), 26x26 in the buff-icon
style of gen_buff_icons.py: the same plate, frame (gold buff frame for a boon, blood debuff frame for a curse) and
pixel rules.

Run: python3 client/tools/gen_descent_icons.py [OUTDIR] [--sheet SHEET.png]
     default OUTDIR: client/overlay/data/images/game/buffs  ->  descent_b_<boon>.png, descent_c_<curse>.png and the two
     generic icons descent_boon.png / descent_curse.png (the buff registry's entries, server/data/lib/chaos_buffs.lua)
     --sheet writes a labelled contact sheet (3x)

Art, donor art first: every icon takes a cell of the element ability icon sets (spell_icon_art/spell_icons_32.png, the
sets build_spell_icon_art.py copies in; tags in spell_icon_art/icon_tags.csv) whose set and tags fit the boon (WANT
below), the inner art area-averaged onto the buff plate exactly like gen_buff_icons.from_spell does for the class
buffs. No two Descent icons share a source icon, and icons the buff bar already shows for a class spell are skipped.
When no cell of the wanted sets carries one of the wanted tags, the icon is drawn with gen_buff_icons' motif kit
instead (MOTIF below). The keys come from server/data/scripts/chaos/descent_config.lua (checked when it is found: a
boon or curse without an entry here stops the run). Deterministic. Needs Pillow."""
import csv, os, re, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_buff_icons as B  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = B.DEFAULT_OUT
ART = os.path.join(HERE, 'spell_icon_art')
CONFIG = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'descent_config.lua')

# name -> (kind, icon sets best first, tags best first)
WANT = {
    'descent_boon': ('buff', ['Fire'], ['avatar', 'buff']),
    'descent_curse': ('debuff', ['Blood'], ['dot', 'challenge']),
    'descent_b_ember_edge': ('buff', ['Fire'], ['melee', 'strike']),
    'descent_b_searing_brand': ('buff', ['Fire'], ['buff', 'avatar', 'wand']),
    'descent_b_rime_brand': ('buff', ['Water'], ['buff', 'avatar', 'wand', 'strike']),
    'descent_b_grave_brand': ('buff', ['Blood', 'Arcane'], ['buff', 'avatar', 'wand']),
    'descent_b_blood_drinker': ('buff', ['Blood'], ['regen', 'heal', 'claw']),
    'descent_b_pyre_burst': ('buff', ['Fire'], ['burst', 'burstring', 'area']),
    'descent_b_soul_harvest': ('buff', ['Nature', 'Blood'], ['regen', 'heal']),
    'descent_b_echo_strike': ('buff', ['Arcane'], ['beam', 'strike']),
    'descent_b_ember_ward': ('buff', ['Fire', 'Steel'], ['shield']),
    'descent_b_quickstep': ('buff', ['Nature', 'Water', 'Steel'], ['haste', 'levitate']),
    'descent_b_keen_eye': ('buff', ['Steel', 'Arcane'], ['find', 'reveal', 'flash']),
    'descent_b_executioner': ('buff', ['Steel'], ['melee', 'claw']),
    'descent_b_stoneskin': ('buff', ['Steel', 'Nature'], ['shield']),
    'descent_b_thornmail': ('buff', ['Nature'], ['shield', 'claw', 'dot']),
    'descent_b_phoenix_ember': ('buff', ['Fire'], ['heal', 'regen', 'virtue']),
    'descent_b_ember_tithe': ('buff', ['Fire', 'Steel'], ['light', 'flash', 'food']),
    'descent_c_frailty': ('debuff', ['Blood'], ['dot', 'challenge']),
    'descent_c_withering': ('debuff', ['Nature', 'Blood'], ['dot', 'cure']),
    'descent_c_swarm': ('debuff', ['Blood', 'Arcane', 'Nature'], ['summon']),
    'descent_c_frenzy': ('debuff', ['Arcane', 'Blood'], ['haste', 'challenge']),
    'descent_c_ashen_purse': ('debuff', ['Steel', 'Fire'], ['rune', 'ammo', 'area']),
}


# ---------------------------------------------------------------- fallback motifs (gen_buff_icons' kit)
def m_ember(c):
    c.poly([(13, 3), (19, 12), (18, 19), (13, 23), (8, 19), (7, 12)], B.A)
    c.poly([(13, 9), (16, 15), (13, 20), (10, 15)], B.AH)


def m_coin(c):
    c.ell(6, 6, 20, 20, B.A)
    c.ell(9, 9, 17, 17, B.AD)
    c.line([(13, 10), (13, 16)], B.AH, 1.5)


MOTIF = {'descent_boon': (m_ember, 'ember', 'gold'), 'descent_curse': (m_ember, 'blood', 'coal')}


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


def buffbar_cells():
    """the sheet cells the buff bar already shows for class buffs (gen_buff_icons.SPELL_ICONS)"""
    try:
        words = B.spell_cells()
    except OSError:
        return set()
    return {words[w] for w in B.SPELL_ICONS.values() if w in words}


def choose():
    """name -> sheet cell (or None: drawn), deterministic: the names in sorted order take the first free fit"""
    cells, tags = sheet_cells()
    taken = buffbar_cells()
    out = {}
    for name in sorted(WANT):
        _kind, sets, want = WANT[name]
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


def draw_motif(name, kind):
    fn, *ramps = MOTIF.get(name, (m_coin, 'gold', 'ember') if kind == 'buff' else (m_coin, 'blood', 'coal'))
    c = B.Canvas()
    fn(c)
    rr = [B.R[r] for r in ramps]
    return B.frame(B.paint(B.plate(kind, rr[0]), c.grid(), rr), kind)


def build_all():
    sheet = Image.open(B.SPELL_ART).convert('RGBA')
    picks = choose()
    icons, source = {}, {}
    for name in sorted(WANT):
        kind = WANT[name][0]
        cell = picks[name]
        if cell:
            icons[name] = B.from_spell(sheet, cell, kind)
            source[name] = 'cell %d' % cell
        else:
            icons[name] = draw_motif(name, kind)
            source[name] = 'drawn'
    return icons, source


def config_names():
    """descent_b_<boon> / descent_c_<curse> for every key of descent_config.lua (None when it is not found)"""
    if not os.path.exists(CONFIG):
        return None
    text = open(CONFIG, encoding='utf-8').read()
    boons = re.search(r'\bboons = \{(.*?)\n\t\},', text, re.S).group(1)
    curses = re.search(r'\bcurses = \{(.*?)\n\t\},', text, re.S).group(1)
    names = {'descent_b_' + k for k in re.findall(r'key = "(\w+)"', boons)}
    names |= {'descent_c_' + k for k in re.findall(r'key = "(\w+)"', curses)}
    return names | {'descent_boon', 'descent_curse'}


def check():
    names = config_names()
    if names is not None and names != set(WANT):
        raise SystemExit('WANT does not match descent_config.lua: missing %s, unused %s' %
                         (sorted(names - set(WANT)), sorted(set(WANT) - names)))


def contact_sheet(icons, source, path, scale=3):
    names = sorted(icons, key=lambda n: (WANT[n][0] == 'debuff', n))
    cols, cw, ch = 6, B.N * scale + 70, B.N * scale + 34
    rows = (len(names) + cols - 1) // cols
    im = Image.new('RGB', (cols * cw + 16, rows * ch + 16), (22, 18, 20))
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        x, y = 8 + (i % cols) * cw + 35, 8 + (i // cols) * ch
        big = icons[n].resize((B.N * scale, B.N * scale), Image.NEAREST)
        im.paste(big, (x, y), big)
        label = n.replace('descent_', '').replace('b_', '').replace('c_', '')
        for j, t in enumerate((label[:16], source[n])):
            tw = d.textlength(t)
            d.text((x + (B.N * scale - tw) / 2, y + B.N * scale + 3 + j * 11), t,
                   fill=(255, 140, 120) if WANT[n][0] == 'debuff' else (240, 222, 180))
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
    print(len(icons), 'descent icons written to', out, '(%d from the icon sets, drawn: %s)' %
          (len(icons) - len(drawn), ', '.join(drawn) or 'none'))


if __name__ == '__main__':
    main()
