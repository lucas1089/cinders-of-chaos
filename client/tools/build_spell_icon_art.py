#!/usr/bin/env python3
"""Build the spell icon art sheet from the six element ability icon sets (32x32 pixel-art icons with a frame).

usage: python3 -I client/tools/build_spell_icon_art.py --src DIR --spells-lua <client>/modules/gamelib/spells.lua
                                                         [--out spell_icon_art/spell_icons_32.png]
DIR holds the sets' "Full PNGs" folders anywhere below it (files "<Set> Icon (<n>).png", Set = Steel, Nature, Arcane,
Blood, Water, Fire); nothing in it is executed. Output: a 20-column sheet of 32x32 cells laid out like the client's
spell icon sheets (cell n at col (n-1)%20, row (n-1)//20), icons copied pixel for pixel; empty cells stay transparent.
  * Chaos spells (cells 201..): spell_icon_art/chaos_spell_icons.csv picks one icon per spell by element and role.
  * every other cell the client's SpellIcons table names (stock spells and runes, renamed by rename_spells.py): the
    cell is classified like gen_all_spell_icons.py does (element and kind from the words) and gets an icon of the set
    for that element whose tags (spell_icon_art/icon_tags.csv) name that kind; icons not used yet are preferred, so an
    icon repeats only when a set runs out. The choice is written to spell_icon_art/stock_spell_icons.csv.
  * unnamed cells get nothing (gen_all_spell_icons.py draws its neutral filler there).
gen_all_spell_icons.py reads the sheet (and derives the 22x24 / 20x20 sizes); a cell without art keeps the generated
drawing, and --no-art there draws every cell again. Deterministic. Needs Pillow.
"""
import argparse, csv, os, re, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'spell_icon_art')
NAME = re.compile(r'^(Steel|Nature|Arcane|Blood|Water|Fire) Icon \((\d+)\)\.png$')
# element (gen_all_spell_icons.classify) -> icon sets, best first
SETS = {'fire': ['Fire'], 'ice': ['Water'], 'energy': ['Arcane', 'Water'], 'earth': ['Nature'], 'poison': ['Nature'],
        'death': ['Blood', 'Arcane'], 'holy': ['Fire', 'Steel'], 'light': ['Fire', 'Water'], 'physical': ['Steel'],
        'blood': ['Blood'], 'heal': ['Nature', 'Water'], 'arcane': ['Arcane'], 'shadow': ['Arcane', 'Blood'],
        'monk': ['Fire', 'Steel'], 'spirit': ['Fire'], 'harmony': ['Water', 'Nature'], 'nature': ['Nature'],
        'food': ['Nature'], 'neutral': ['Steel']}
# kind -> tags that fit it, best first
KINDS = {'strike': ['strike', 'wand'], 'wave': ['wave', 'area'], 'beam': ['beam', 'strike'], 'area': ['area', 'burst'],
         'burst': ['burst', 'area'], 'burstring': ['burstring', 'burst', 'area'], 'heal': ['heal', 'regen', 'cure'],
         'regen': ['regen', 'heal'], 'cure': ['cure', 'heal'], 'buff': ['buff', 'avatar'], 'avatar': ['avatar', 'buff'],
         'shield': ['shield'], 'haste': ['haste'], 'summon': ['summon'], 'rune': ['rune'], 'ammo': ['ammo', 'spear'],
         'spear': ['spear', 'ammo'], 'melee': ['melee', 'claw'], 'claw': ['claw', 'melee'], 'fist': ['fist', 'melee'],
         'dot': ['dot', 'area'], 'challenge': ['challenge'], 'party': ['party', 'buff'], 'invis': ['invis', 'illusion'],
         'illusion': ['illusion', 'invis'], 'find': ['find', 'reveal'], 'reveal': ['reveal', 'find'],
         'light': ['light', 'flash'], 'flash': ['flash', 'light'], 'holyground': ['holyground', 'virtue'],
         'virtue': ['virtue', 'holyground'], 'meditate': ['meditate'], 'levitate': ['levitate', 'haste'],
         'rope': ['rope'], 'food': ['food'], 'wand': ['wand', 'strike']}


def find_icons(src):
    found = {}
    for root, _dirs, files in os.walk(src):
        for f in files:
            m = NAME.match(f)
            if m:
                found[(m.group(1), int(m.group(2)))] = os.path.join(root, f)
    return found


def stock_map(spells_lua, taken, tags):
    """cell -> (set, index, label, kind, element) for the cells the client's SpellIcons names (not the Chaos cells)."""
    sys.path.insert(0, HERE)
    import gen_all_spell_icons as g
    cells = g.parse_spells_lua(spells_lua)
    used = {k: 0 for k in tags}
    for k in taken:
        used[k] = used.get(k, 0) + 1
    out = {}
    for n in sorted(cells):
        if n >= g.CHAOS_FIRST:
            continue
        c = cells[n]
        spec = g.classify(c['words'], c['type'], c['key'])
        kind, el = spec['kind'], spec.get('el') or 'neutral'
        sets = SETS.get(el, ['Steel'])
        want = KINDS.get(kind, [kind])
        best = None
        for si, st in enumerate(sets):
            for ti, tg in enumerate(want):
                for (s2, i2), tl in tags.items():
                    if s2 != st or tg not in tl:
                        continue
                    score = (used[(s2, i2)], si, ti, tl.index(tg), i2)
                    if best is None or score < best[0]:
                        best = (score, (s2, i2))
        if best is None or best[0][0] > 0:      # nothing fitting left unused: any unused icon of the first set
            free = [k for k in sorted(tags, key=lambda k: k[1]) if k[0] == sets[0] and used[k] == 0]
            if free:
                best = ((0,), free[0])
        if best is None:
            continue
        key = best[1]
        used[key] += 1
        out[n] = (key[0], key[1], c['name'], kind, el)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--src', required=True)
    ap.add_argument('--spells-lua', required=True)
    ap.add_argument('--out', default=os.path.join(ART, 'spell_icons_32.png'))
    a = ap.parse_args()
    found = find_icons(a.src)
    tags = {}
    for r in csv.DictReader(open(os.path.join(ART, 'icon_tags.csv'), newline='', encoding='utf-8')):
        tags[(r['set'], int(r['index']))] = r['tags'].split()
    rows = list(csv.DictReader(open(os.path.join(ART, 'chaos_spell_icons.csv'), newline='', encoding='utf-8')))
    chaos = {int(r['cell']): (r['set'], int(r['index'])) for r in rows}
    assert len(set(chaos.values())) == len(chaos), 'an icon is used twice for the Chaos spells'
    stock = stock_map(a.spells_lua, list(chaos.values()), tags)
    with open(os.path.join(ART, 'stock_spell_icons.csv'), 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh); w.writerow(['cell', 'spell', 'kind', 'element', 'set', 'index'])
        for n, (st, i, label, kind, el) in sorted(stock.items()):
            w.writerow([n, label, kind, el, st, i])
    picks = dict(chaos); picks.update({n: (v[0], v[1]) for n, v in stock.items()})
    last = max(picks)
    cols = 20
    sheet = Image.new('RGBA', (cols * 32, ((last - 1) // cols + 1) * 32), (0, 0, 0, 0))
    for n, key in sorted(picks.items()):
        if key not in found:
            sys.exit(f'missing icon {key[0]} {key[1]} under {a.src}')
        im = Image.open(found[key]).convert('RGBA')
        assert im.size == (32, 32), (key, im.size)
        sheet.paste(im, (((n - 1) % cols) * 32, ((n - 1) // cols) * 32))
    sheet.save(a.out, optimize=True)
    distinct = len(set(picks.values()))
    print(f'{len(chaos)} Chaos cells + {len(stock)} stock cells, {distinct} distinct icons of {len(found)} -> {a.out}')


if __name__ == '__main__':
    main()
