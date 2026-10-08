#!/usr/bin/env python3
"""Install the crafting orbs into a base server (items.xml names, the unique guard of the stock reroll script).

usage: python3 -I install_crafting.py DATA_DIR [--dry-run]

1. data/items/items.xml: the Orbs of Alchemy, Annulment and Scouring are the stackable rune stones 24691, 24697 and
   24688 (no items.xml entry, nothing uses them). They get a name, plural, description and weight here. The Orb of
   Transmutation (29851) and the Exalted Orb (29855) are existing currency items (character upgrades); their
   description gets a sentence about crafting.
2. data/scripts/customs/rarity/reroll_rarity_stats.lua: the stock Chaos and Divine Orb action made a plain copy of a
   unique item (a unique has no "rarity", so the reroll gave it none and dropped its name and stats). isRerollable now
   refuses items with the "chaos_unique" attribute, as every crafting orb does (data/lib/chaos_crafting.lua).

Idempotent: an item that already has an entry is left alone, descriptions are only extended once, and the guard
carries a marker comment.
"""
import os, re, sys

NEW_ITEMS = [
    (24691, 'an', 'Orb of Alchemy', 'Orbs of Alchemy',
     'Use it with a normal item: it becomes Rare, Epic or Legendary with random modifiers. Or use it at the crafting bench (!craft).'),
    (24697, 'an', 'Orb of Annulment', 'Orbs of Annulment',
     'Use it with an item with a rarity: one random modifier is removed. Or use it at the crafting bench (!craft).'),
    (24688, 'an', 'Orb of Scouring', 'Orbs of Scouring',
     'Use it with an item with a rarity: the rarity and every modifier are removed. Or use it at the crafting bench (!craft).'),
]
EXTEND = {
    29851: 'Crafting: turns a normal item into a Common or Uncommon one (use it to open the crafting bench).',
    29855: 'Crafting: adds one random modifier to an item with a rarity (use it to open the crafting bench).',
}
WEIGHT = 50

GUARD_MARKER = '-- Chaos: uniques are never rerolled (install_crafting.py)'
GUARD = ('  ' + GUARD_MARKER + '\n'
         '  if item:getCustomAttribute("chaos_unique") then return false end\n')


def patch_items(text):
    notes = []
    end = text.rfind('</items>')
    if end < 0:
        return text, ['items.xml: no </items>']
    add = []
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', text)]
    for iid, article, name, plural, desc in NEW_ITEMS:
        if re.search(r'<item\s+id="%d"' % iid, text) or any(a <= iid <= b for a, b in ranges):
            notes.append('items.xml: %d already has an entry' % iid)
            continue
        add.append('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                   '\t\t<attribute key="description" value="%s" />\n'
                   '\t\t<attribute key="weight" value="%d" />\n'
                   '\t</item>\n' % (iid, article, name, plural, desc, WEIGHT))
        notes.append('items.xml: added %d %s' % (iid, name))
    if add:
        text = text[:end] + ''.join(add) + text[end:]
    for iid, sentence in EXTEND.items():
        m = re.search(r'(<item\s+id="%d"[^>]*>)(.*?)(</item>)' % iid, text, re.S)
        if not m:
            notes.append('items.xml: %d not found' % iid)
            continue
        body = m.group(2)
        if sentence in body:
            notes.append('items.xml: %d description already extended' % iid)
            continue
        d = re.search(r'(<attribute\s+key="description"\s+value=")([^"]*)(")', body)
        if d:
            new_body = body[:d.start()] + d.group(1) + d.group(2).rstrip() + ' ' + sentence + d.group(3) + body[d.end():]
        else:
            new_body = '\n\t\t<attribute key="description" value="%s" />' % sentence + body
        text = text[:m.start(2)] + new_body + text[m.end(2):]
        notes.append('items.xml: %d description extended' % iid)
    return text, notes


def patch_reroll(text):
    if GUARD_MARKER in text:
        return text, 'already'
    m = re.search(r'local function isRerollable\(item\)\n(.*?\n)', text)
    if not m:
        return text, 'isRerollable not found'
    # after the first guard line of the function (the "not an item" test)
    at = m.end()
    return text[:at] + GUARD + text[at:], 'patched'


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if len(args) != 1:
        print(__doc__)
        return 1
    data = args[0]
    status = 0
    path = os.path.join(data, 'items', 'items.xml')
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    new, notes = patch_items(text)
    for n in notes:
        print(n)
    if new != text and not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    path = os.path.join(data, 'scripts', 'customs', 'rarity', 'reroll_rarity_stats.lua')
    if os.path.exists(path):
        text = open(path, encoding='utf-8', errors='surrogateescape').read()
        new, st = patch_reroll(text)
        print('reroll_rarity_stats.lua:', st)
        if st not in ('patched', 'already'):
            status = 1
        if new != text and not dry:
            open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    else:
        print('reroll_rarity_stats.lua: not found (nothing to guard)')
    if dry:
        print('dry run: nothing written')
    return status


if __name__ == '__main__':
    sys.exit(main())
