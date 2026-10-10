#!/usr/bin/env python3
"""Icons of the community goal stages and the weekly world modifiers (the buff bar and client module game_community),
26x26 in the buff-icon style of gen_buff_icons.py: the same plate, gold buff frame and pixel rules.

Run: python3 client/tools/gen_community_icons.py [OUTDIR] [--sheet SHEET.png]
     default OUTDIR: client/overlay/data/images/game/buffs  ->  community_<stage>.png, wmod_<modifier>.png and the two
     generic icons community_goal.png / wmod_week.png (the buff registry's entries, server/data/lib/chaos_buffs.lua)
     --sheet writes a labelled contact sheet (3x)

Art, donor art first: an icon takes a cell of the element ability icon sets (spell_icon_art/spell_icons_32.png; tags in
spell_icon_art/icon_tags.csv) whose set and tags fit (WANT below), the inner art area-averaged onto the buff plate exactly
like gen_buff_icons.from_spell. Cells the buff bar, the Ember Descent (gen_descent_icons.py) and the raid
(gen_raid_icons.py, when present) already show are skipped, and no two icons here share one. An icon whose wanted sets
carry none of its tags, or that asks for no cell, is drawn with gen_buff_icons' motif kit (MOTIF below). The keys come
from server/data/scripts/chaos/community_config.lua (checked when it is found). Our own art; deterministic. Needs Pillow."""
import os, re, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_buff_icons as B  # noqa: E402
import gen_descent_icons as D  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = B.DEFAULT_OUT
CONFIG = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'community_config.lua')

# name -> (icon sets best first, tags best first); an empty tag list = always drawn (MOTIF)
WANT = {
    'community_goal': ([], []),
    'community_kindled': ([], []),
    'community_bounty': ([], []),
    'community_beacon': (['Arcane', 'Fire'], ['reveal', 'find', 'light']),
    'community_ablaze': ([], []),
    'wmod_week': ([], []),
    'wmod_ember_tides': (['Fire'], ['wave', 'burstring']),
    'wmod_bloodmoon': (['Blood'], ['challenge', 'avatar']),
    'wmod_restless_dead': (['Blood', 'Arcane'], ['summon']),
    'wmod_gilded_week': ([], []),
    'wmod_forgefire': ([], []),
    'wmod_dragonfall': (['Fire'], ['beam', 'wave']),
    'wmod_ambush_season': (['Steel', 'Nature'], ['claw', 'melee']),
    'wmod_banner_week': (['Steel'], ['party', 'virtue']),
    'wmod_tower_echoes': (['Arcane', 'Water'], ['levitate', 'meditate']),
}


# ---------------------------------------------------------------- motifs (gen_buff_icons' kit)
def brazier(c, flame=B.A):
    c.poly([(5, 15), (21, 15), (18, 20), (8, 20)], B.B)              # the bowl on three legs
    c.rect(5, 14, 21, 16, B.BH)
    c.line([(9, 20), (7, 24)], B.BD, 1.4); c.line([(17, 20), (19, 24)], B.BD, 1.4); c.line([(13, 20), (13, 24)], B.BD, 1.4)
    c.poly([(13, 2), (18, 9), (17, 14), (9, 14), (8, 9)], flame)     # the flame
    c.poly([(13, 7), (15, 11), (13, 14), (11, 11)], B.AH)


def m_goal(c):
    brazier(c)


def m_kindled(c):
    brazier(c)
    B.m_up_arrow(c, 21, 2, 0.45, B.C)


def m_bounty(c):
    brazier(c)
    for (x, y) in ((6, 22), (20, 22), (13, 23)):
        c.ell(x - 1.8, y - 1.8, x + 1.8, y + 1.8, B.C)                # coins spilled at its feet


def m_ablaze(c):
    c.poly([(13, 1), (21, 9), (20, 15), (6, 15), (5, 9)], B.A)       # a roaring flame over the bowl
    c.poly([(7, 4), (10, 9), (6, 11)], B.A); c.poly([(19, 4), (16, 9), (20, 11)], B.A)
    c.poly([(5, 16), (21, 16), (18, 21), (8, 21)], B.B)
    c.rect(5, 15, 21, 17, B.BH)
    c.line([(9, 21), (7, 24)], B.BD, 1.4); c.line([(17, 21), (19, 24)], B.BD, 1.4)
    c.poly([(13, 5), (16, 10), (13, 15), (10, 10)], B.AH)
    c.px(['W'], 13, 9, {'W': B.W})


def m_beacon(c):
    brazier(c)
    c.ell(18, 2, 24, 8, B.C); c.ell(19.5, 3.5, 22.5, 6.5, 0)          # a rift ring above it


def m_week(c):
    c.ell(4, 4, 22, 22, B.B)                                          # a world with a turning arrow
    c.arc(4, 4, 22, 22, 0, 360, B.BD, 1)
    c.line([(5, 13), (21, 13)], B.BD, 1); c.arc(8, 4, 18, 22, 90, 270, B.BD, 1); c.arc(8, 4, 18, 22, 270, 90, B.BD, 1)
    c.arc(2, 2, 24, 24, 200, 330, B.A, 1.6)
    c.poly([(20, 3), (24, 7), (19, 8)], B.A)


def m_gilded(c):
    c.ell(4, 9, 22, 24, B.B)                                          # a heavy sack of gold
    c.poly([(9, 10), (17, 10), (15, 6), (11, 6)], B.BD)
    c.line([(10, 9), (16, 9)], B.C, 1.2)
    for (x, y) in ((8, 6), (18, 5), (13, 3)):
        c.ell(x - 1.8, y - 1.8, x + 1.8, y + 1.8, B.A)
    c.ell(10, 14, 16, 20, B.A); c.px(['h'], 12, 15, {'h': B.AH})


def m_forgefire(c):
    c.poly([(3, 15), (23, 15), (21, 18), (17, 18), (17, 22), (9, 22), (9, 18), (5, 18)], B.B)   # an anvil
    c.rect(3, 14, 23, 16, B.BH)
    c.poly([(13, 2), (18, 9), (16, 13), (10, 13), (8, 9)], B.A)       # a flame on it
    c.poly([(13, 6), (15, 10), (13, 13), (11, 10)], B.AH)
    c.ell(18.5, 8.5, 22.5, 12.5, B.C)                                 # an orb in the heat


MOTIF = {
    'community_goal': (m_goal, 'ember', 'steel', 'gold'), 'community_kindled': (m_kindled, 'ember', 'steel', 'gold'),
    'community_bounty': (m_bounty, 'ember', 'steel', 'gold'), 'community_beacon': (m_beacon, 'ember', 'steel', 'arcane'),
    'community_ablaze': (m_ablaze, 'ember', 'obsidian', 'gold'), 'wmod_week': (m_week, 'ember', 'water'),
    'wmod_gilded_week': (m_gilded, 'gold', 'wood', 'bone'), 'wmod_forgefire': (m_forgefire, 'ember', 'steel', 'arcane'),
}
FALLBACK = (m_week, 'ember', 'water')


def taken_cells():
    """the cells the buff bar, the Descent and the raid already show"""
    taken = D.buffbar_cells()
    taken |= {c for c in D.choose().values() if c}
    try:
        import gen_raid_icons as RAID  # noqa: E402  (another system's icons; optional)
        taken |= {c for c in RAID.choose().values() if c}
    except (ImportError, OSError, SystemExit, AttributeError):
        pass
    return taken


def choose():
    """name -> sheet cell (or None: drawn), deterministic: the names in sorted order take the first free fit"""
    cells, tags = D.sheet_cells()
    taken = taken_cells()
    out = {}
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


def draw_motif(name):
    fn, *ramps = MOTIF.get(name, FALLBACK)
    c = B.Canvas()
    fn(c)
    rr = [B.R[r] for r in ramps]
    return B.frame(B.paint(B.plate('buff', rr[0]), c.grid(), rr), 'buff')


def build_all():
    sheet = Image.open(B.SPELL_ART).convert('RGBA')
    picks = choose()
    icons, source = {}, {}
    for name in sorted(WANT):
        cell = picks[name]
        if cell:
            icons[name] = B.from_spell(sheet, cell, 'buff')
            source[name] = 'cell %d' % cell
        else:
            icons[name] = draw_motif(name)
            source[name] = 'drawn'
    return icons, source


def config_names():
    """community_<stage> / wmod_<modifier> for every key of community_config.lua (None when it is not found)"""
    if not os.path.exists(CONFIG):
        return None
    text = open(CONFIG, encoding='utf-8').read()
    stages = re.search(r'\bstages = \{(.*?)\n\t\t\},', text, re.S).group(1)
    pool = re.search(r'\bpool = \{(.*?)\n\t\t\},', text, re.S).group(1)
    names = {'community_' + k for k in re.findall(r'key = "(\w+)"', stages)}
    names |= {'wmod_' + k for k in re.findall(r'key = "(\w+)"', pool)}
    return names | {'community_goal', 'wmod_week'}


def check():
    names = config_names()
    if names is not None and names != set(WANT):
        raise SystemExit('WANT does not match community_config.lua: missing %s, unused %s' %
                         (sorted(names - set(WANT)), sorted(set(WANT) - names)))


def contact_sheet(icons, source, path, scale=3):
    names = sorted(icons)
    cols, cw, ch = 6, B.N * scale + 74, B.N * scale + 34
    rows = (len(names) + cols - 1) // cols
    im = Image.new('RGB', (cols * cw + 16, rows * ch + 16), (22, 18, 20))
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        x, y = 8 + (i % cols) * cw + 37, 8 + (i // cols) * ch
        big = icons[n].resize((B.N * scale, B.N * scale), Image.NEAREST)
        im.paste(big, (x, y), big)
        label = n.replace('community_', '').replace('wmod_', '')
        for j, t in enumerate((label[:17], source[n])):
            tw = d.textlength(t)
            d.text((x + (B.N * scale - tw) / 2, y + B.N * scale + 3 + j * 11), t, fill=(240, 222, 180))
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
    print(len(icons), 'community icons written to', out, '(%d from the icon sets, drawn: %s)' %
          (len(icons) - len(drawn), ', '.join(drawn) or 'none'))


if __name__ == '__main__':
    main()
