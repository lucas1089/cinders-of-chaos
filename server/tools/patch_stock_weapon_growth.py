#!/usr/bin/env python3
"""The stock weapons grow with the level (O472, owner 2026-11-10: "You can do everything"; server/README.md "Weapon growth (O472)").

usage: python3 -I patch_stock_weapon_growth.py DATA_DIR [--dry-run]

The weapon values of the equipment sets, the weapons above level 800, the relic sets, the fist weapons and the uniques grow with the
level (tools/weapon_growth.py: a(level) = 1 + (W - 1) / 0.85, install_gear_sets.py WEAPON_CURVES). The stock weapons of the base server
are not written by those tools; left alone they would fall to a third of the tier at level 1000 and no class would find a usable weapon
among them (tools/gear_coverage.lua --fairness). So this step gives them the same growth:

  items.xml     a sword, axe, club, bow or crossbow (a launcher's attack already holds its ammunition, patch_base_archery.py) with a
                weapons.xml level above 100 and no charges: attack and every element damage attribute = the number before the step
                times a(level), rounded half up
  weapons.xml   a wand or rod with a level above 100: min and max the same way

The numbers BEFORE the step are kept in one marker comment at the end of each file (id, attack, element damage; id, min, max). Every run
works from them, not from the numbers it finds: the step is idempotent, a server installed before O472 moves to the new numbers on the
first run, and a change of the table moves it again. tools/survey_base_weapons.py reads the comment back, so data/items/base_weapons.csv
stays the stock snapshot (the audits, tools/weapon_coverage.lua stockGrowth, apply the same rule to it). Run after the archery step.
Items with charges (training and one-shot weapons), thrown weapons (retired, chaos_throwables.lua), the weapons of the Chaos tools
(server id 36654 and up) and weapons of level 100 or less are left alone.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import weapon_growth as WG  # noqa: E402
import survey_base_weapons as SV  # noqa: E402

KINDS = ('sword', 'axe', 'club', 'bow', 'crossbow')
FROM_LEVEL = 100          # a weapon of a level above this grows
ITEMS_BEGIN, WANDS_BEGIN, END = WG.ITEMS_BEGIN, WG.WANDS_BEGIN, WG.END
read_items_block, read_wands_block = WG.read_items_block, WG.read_wands_block


def grows(kind, level, charges):
    return kind in KINDS and charges == 0 and level > FROM_LEVEL


def wand_grows(level):
    return level > FROM_LEVEL


def write_block(text, begin, lines, root):
    """the text with the marker comment holding `lines` (none: without one), before the closing root tag"""
    span = WG.block_span(text, begin)
    if span:
        text = text[:span[0]] + text[span[1]:]
    if not lines:
        return text
    block = begin + ''.join('\t\t%s\n' % l for l in lines) + END
    at = text.rfind(root)
    if at < 0:
        raise SystemExit('no %s' % root)
    return text[:at] + block + text[at:]


# ------------------------------------------------------------------------------------------------ items.xml
# the same shape as survey_base_weapons.py ITEM: an item with a body ends at </item>; a self-closing item (`<item id=".." name=".." />`) has none
# and must not swallow the next item
ITEM_RE = re.compile(r'(<item\s+([^>]*?)(/?)>)(.*?)(</item>|(?=<item\s))', re.S)
ELEMENT_KEYS = SV.ELEMENTS


def item_before(body):
    """(attack, {element key: value}) of an item body as it stands"""
    attack, elem = 0, {}
    for k, v in SV.KEYVAL.findall(body):
        low = k.lower()
        if low == 'attack':
            attack = int(v or 0)
        elif low in ELEMENT_KEYS:
            elem[k] = int(v or 0)
    return attack, elem


def set_attr(body, key, value):
    rx = re.compile(r'(<attribute\s+key\s*=\s*")(%s)("\s+value\s*=\s*")(\d+)(")' % re.escape(key), re.I)
    return rx.sub(lambda m: m.group(1) + m.group(2) + m.group(3) + str(value) + m.group(5), body, count=1)


def patch_items(text, rows):
    """(new text, note, number of items grown): `rows` are survey rows (the numbers before the step, levels, kinds)"""
    kept = read_items_block(text)
    todo = {r['id']: r for r in rows if grows(r['kind'], r['level'], r['charges']) and (r['attack'] > 0 or r['element'] > 0)}
    changed, block = 0, {}

    def fix(m):
        nonlocal changed
        idm = re.search(r'\bid\s*=\s*"(\d+)"', m.group(2))
        if m.group(3) == '/' or not idm:
            return m.group(0)
        wid = int(idm.group(1))
        r = todo.get(wid)
        if not r:
            return m.group(0)
        body = m.group(4)
        # the numbers before the step: the marker's when there is one, else what the item holds now
        attack, elem = kept[wid] if wid in kept else item_before(body)
        block[wid] = (attack, elem)
        a = WG.weapon_a(r['level'])
        new = body
        if attack > 0:
            new = set_attr(new, 'attack', int(attack * a + 0.5))
        for k, v in elem.items():
            if v > 0:
                new = set_attr(new, k, int(v * a + 0.5))
        if new != body:
            changed += 1
        return m.group(1) + new + m.group(5)

    out = ITEM_RE.sub(fix, text)
    lines = []
    for wid in sorted(block):
        attack, elem = block[wid]
        lines.append(' '.join(['%d' % wid, '%d' % attack] + ['%s=%d' % (k, v) for k, v in sorted(elem.items())]))
    out = write_block(out, ITEMS_BEGIN, lines, '</items>')
    note = 'items.xml: %d stock weapon(s) grown (%d in the marker)' % (changed, len(block)) if changed else \
        'items.xml: the stock weapons are grown (%d in the marker)' % len(block)
    return out, note, changed


# ------------------------------------------------------------------------------------------------ weapons.xml
WAND_RE = re.compile(r'<wand\b[^>]*>')


def patch_wands(text, rows):
    kept = read_wands_block(text)
    todo = {r['id']: r for r in rows if r['kind'] == 'wand' and wand_grows(r['level']) and r['wmax'] > 0}
    changed, block = 0, {}

    def fix(m):
        nonlocal changed
        tag = m.group(0)
        idm = re.search(r'\bid\s*=\s*"(\d+)"', tag)
        wid = int(idm.group(1)) if idm else -1
        r = todo.get(wid)
        if not r:
            return tag
        mn = re.search(r'\bmin\s*=\s*"(\d+)"', tag)
        mx = re.search(r'\bmax\s*=\s*"(\d+)"', tag)
        if not mn or not mx:
            return tag
        lo, hi = kept[wid] if wid in kept else (int(mn.group(1)), int(mx.group(1)))
        block[wid] = (lo, hi)
        a = WG.weapon_a(r['level'])
        new = re.sub(r'\bmin\s*=\s*"\d+"', 'min="%d"' % int(lo * a + 0.5), tag, count=1)
        new = re.sub(r'\bmax\s*=\s*"\d+"', 'max="%d"' % int(hi * a + 0.5), new, count=1)
        if new != tag:
            changed += 1
        return new

    out = WAND_RE.sub(fix, text)
    out = write_block(out, WANDS_BEGIN, ['%d %d %d' % (wid, lo, hi) for wid, (lo, hi) in sorted(block.items())], '</weapons>')
    note = 'weapons.xml: %d stock wand(s) and rod(s) grown (%d in the marker)' % (changed, len(block)) if changed else \
        'weapons.xml: the stock wands and rods are grown (%d in the marker)' % len(block)
    return out, note, changed


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    data = args[0]
    ix = os.path.join(data, 'items', 'items.xml')
    wx = os.path.join(data, 'weapons', 'weapons.xml')
    for p in (ix, wx):
        if not os.path.exists(p):
            print('not found:', p)
            return 1
    _text, rows = SV.survey(data)    # the numbers before the step (the survey reads the marker comments back)
    texts = {ix: open(ix, encoding='utf-8', errors='surrogateescape').read(), wx: open(wx, encoding='utf-8', errors='surrogateescape').read()}
    new_i, note_i, _ = patch_items(texts[ix], rows)
    new_w, note_w, _ = patch_wands(texts[wx], rows)
    print(note_i)
    print(note_w)
    if '--dry-run' in argv:
        print('dry run: nothing written')
        return 0
    for path, new in ((ix, new_i), (wx, new_w)):
        if new != texts[path]:
            open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
