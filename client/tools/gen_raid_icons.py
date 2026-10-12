#!/usr/bin/env python3
"""Icons of the Ashen Sepulchre's boss debuffs (the buff bar, server/data/lib/chaos_buffs.lua source "raid"; the raid
HUD of client module game_raid), 26x26 in the buff-icon style of gen_buff_icons.py: the same plate, blood debuff frame
and pixel rules.

Run: python3 client/tools/gen_raid_icons.py [OUTDIR] [--sheet SHEET.png]
     default OUTDIR: client/overlay/data/images/game/buffs  ->  raid_debuff.png (the registry entry), raid_sunder.png
     (Sundered, the tank swap stacks), raid_hexed.png (Hexed, the effigy stacks), raid_hex.png (Withering Hex, to cleanse)
     --sheet writes a labelled contact sheet (3x)

Art, donor art first, exactly like gen_descent_icons.py: a cell of the element ability icon sets whose set and tags fit
(WANT), never a cell the buff bar or the Descent icons already use; the motif kit of gen_buff_icons.py when nothing fits.
The names come from raid.lua (checked when it is found). Deterministic. Needs Pillow."""
import os, re, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_buff_icons as B  # noqa: E402
import gen_descent_icons as D  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = B.DEFAULT_OUT
SCRIPT = os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'raid.lua')

# name -> (kind, icon sets best first, tags best first)
WANT = {
    'raid_debuff': ('debuff', ['Blood', 'Arcane'], ['challenge', 'dot']),
    'raid_sunder': ('debuff', ['Steel', 'Blood'], ['melee', 'claw', 'strike']),
    'raid_hexed': ('debuff', ['Arcane', 'Blood'], ['dot', 'summon']),
    'raid_hex': ('debuff', ['Arcane', 'Nature'], ['cure', 'dot', 'challenge']),
}


def choose():
    """name -> sheet cell (or None: drawn); the buff bar's and the Descent's cells are taken first"""
    cells, tags = D.sheet_cells()
    taken = D.buffbar_cells()
    taken |= {c for c in D.choose().values() if c}
    out = {}
    for name in sorted(WANT):
        _kind, sets, want = WANT[name]
        pick = None
        for tag in want:
            for s in sets:
                for k in sorted(k for k in cells if k[0] == s):
                    cell = cells[k]
                    if cell in taken or tag not in tags.get(k, []):
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
            icons[name] = D.draw_motif(name, kind)
            source[name] = 'drawn'
    return icons, source


def check():
    """every "buff:raid_*" icon raid.lua and the registry name has an entry here"""
    names = set()
    for path in (SCRIPT, os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_buffs.lua')):
        if os.path.exists(path):
            names |= set(re.findall(r'"buff:(raid_\w+)"', open(path, encoding='utf-8').read()))
    if names and names != set(WANT):
        raise SystemExit('WANT does not match raid.lua / chaos_buffs.lua: missing %s, unused %s' %
                         (sorted(names - set(WANT)), sorted(set(WANT) - names)))


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
        saved = D.WANT
        D.WANT = WANT
        try:
            D.contact_sheet(icons, source, sheet)
        finally:
            D.WANT = saved
    drawn = sorted(n for n in source if source[n] == 'drawn')
    print(len(icons), 'raid icons written to', out, '(%d from the icon sets, drawn: %s)' %
          (len(icons) - len(drawn), ', '.join(drawn) or 'none'))


if __name__ == '__main__':
    main()
