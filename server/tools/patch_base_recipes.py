#!/usr/bin/env python3
"""The base crafting books give the late-game boss materials a use (idempotent). install_all.py step `baserecipes`.

usage: python3 -I patch_base_recipes.py DATA_DIR [--dry-run] [--check]

server/README.md "Base crafting recipes". Owner (2026-10-22, on the Seraphic Charged Stone): "Coloque pra que servem".
The base books (data/scripts/customs/crafting/<book>.lua, `Crafting.<book> = {...}`) have the three class sets of
level 35 (Myst Regalia, Seraphic, Dawnforged), but every Seraphic and Dawnforged recipe asks for the Myst Charged Stone
and the Myst Emblem, so the Seraphic and Dawnforged stones and emblems that bosses drop had no use at all. This tool:

1. armorsmith, weaponsmith, jewelsmith: a Seraphic product (SERAPHIC) takes the Seraphic Charged Stone (29922) and the
   Seraphic Emblem (29925) instead of the Myst ones (29921, 29924); a Dawnforged product (DAWNFORGED) the Dawnforged
   ones (29923, 29926). Counts, gold, level and the order of the recipes stay. Belts and gloves are left alone
   (patch_badges.py retires them).
2. jewelsmith: the recipes named "Myst Regalia Amulet" / "Myst Regalia Ring" made item 29865 / 29866 (the Myst
   spellbook and wand, which the weaponsmith also makes); they make the amulet (29867) and the ring (29868) now.
3. generalcrafting: ADDED, appended in a block after the book (marker CRAFT_MARK), so the stock recipes keep their
   places: the boss trophies of the late hunts and the Runic Stone Shard make the charged stones and the emblems.
   Every recipe's materials sell for at most what its product sells for (data/lib/chaos_item_prices_data.lua), and
   with the gold the inputs are worth more than the product: no gold loop, and the item price table's craft floor
   leaves the product's price as it was (patch_base_recipes_test.py checks both against the price table).
4. data/items/items.xml: DESCRIPTIONS, a short "what it is for" text on each of these materials (added when the item
   has no description, appended when it has another one).

A book or item that is not there is skipped and listed. A second run changes nothing; --check changes nothing and exits
1 when something is still to do. item_prices_base.py `recipes` reads the books through `patch_book`, so the committed
snapshot data/items/base_recipes.csv (gen_item_prices.py survey) has the recipes as installed.
"""
import os
import re
import sys

sys.dont_write_bytecode = True

BOOKS = os.path.join('scripts', 'customs', 'crafting')
ITEMS = os.path.join('items', 'items.xml')
CRAFT_MARK = '-- Chaos: boss material recipes (patch_base_recipes.py) v1'

MYST_STONE, SERAPHIC_STONE, DAWN_STONE = 29921, 29922, 29923
MYST_EMBLEM, SERAPHIC_EMBLEM, DAWN_EMBLEM = 29924, 29925, 29926
NYXDRATH_HEART = 29920
RUNIC_SHARD = 29900
GARGANTUAN_EYE, BRAINFORGED, RUNIC_CLAW, VERDANT_SCALE, VORSK_SCALE, FROSTBONE_SHARD = range(29908, 29914)

# the set pieces of each line (helmet .. ring; not the retired belts and gloves 29914-29919)
SERAPHIC = tuple(range(29869, 29878))
DAWNFORGED = tuple(range(29878, 29891))
SWAPS = [(SERAPHIC, {MYST_STONE: SERAPHIC_STONE, MYST_EMBLEM: SERAPHIC_EMBLEM}),
         (DAWNFORGED, {MYST_STONE: DAWN_STONE, MYST_EMBLEM: DAWN_EMBLEM})]
SWAP_BOOKS = ('armorsmith', 'weaponsmith', 'jewelsmith')
# (book, recipe name, wrong product id, right product id)
ID_FIXES = [('jewelsmith', 'Myst Regalia Amulet', 29865, 29867), ('jewelsmith', 'Myst Regalia Ring', 29866, 29868)]

# generalcrafting: (product id, name, crafting level, gold, [(material id, count)])
ADDED = [
    (MYST_STONE, 'Myst Charged Stone', 25, 25000, [(GARGANTUAN_EYE, 1), (RUNIC_CLAW, 1)]),
    (SERAPHIC_STONE, 'Seraphic Charged Stone', 25, 25000, [(VERDANT_SCALE, 1), (VORSK_SCALE, 1)]),
    (DAWN_STONE, 'Dawnforged Charged Stone', 25, 25000, [(FROSTBONE_SHARD, 1), (RUNIC_SHARD, 1)]),
    (MYST_EMBLEM, 'Myst Emblem', 30, 25000, [(MYST_STONE, 1), (RUNIC_SHARD, 1)]),
    (SERAPHIC_EMBLEM, 'Seraphic Emblem', 30, 25000, [(SERAPHIC_STONE, 1), (RUNIC_SHARD, 1)]),
    (DAWN_EMBLEM, 'Dawnforged Emblem', 30, 25000, [(DAWN_STONE, 1), (RUNIC_SHARD, 1)]),
    (MYST_EMBLEM, 'Myst Emblem', 30, 25000, [(BRAINFORGED, 1), (RUNIC_SHARD, 1)]),
]
ADDED_BOOK = 'generalcrafting'

DESCRIPTIONS = {
    NYXDRATH_HEART: 'Crafting material for the Myst Regalia, Seraphic and Dawnforged sets.',
    MYST_STONE: 'Crafting material for the Myst Regalia set and the Myst Emblem.',
    SERAPHIC_STONE: 'Crafting material for the Seraphic set and the Seraphic Emblem.',
    DAWN_STONE: 'Crafting material for the Dawnforged set and the Dawnforged Emblem.',
    MYST_EMBLEM: 'Crafting material for the Myst Regalia set.',
    SERAPHIC_EMBLEM: 'Crafting material for the Seraphic set.',
    DAWN_EMBLEM: 'Crafting material for the Dawnforged set.',
    RUNIC_SHARD: 'Crafting material for the Dawnforged Charged Stone and the set emblems (crafting table).',
    GARGANTUAN_EYE: 'Crafting material for the Myst Charged Stone (crafting table).',
    RUNIC_CLAW: 'Crafting material for the Myst Charged Stone (crafting table).',
    BRAINFORGED: 'Crafting material for the Myst Emblem (crafting table).',
    VERDANT_SCALE: 'Crafting material for the Seraphic Charged Stone (crafting table).',
    VORSK_SCALE: 'Crafting material for the Seraphic Charged Stone (crafting table).',
    FROSTBONE_SHARD: 'Crafting material for the Dawnforged Charged Stone (crafting table).',
}

# one recipe of a book: `{ id = N, name = "...", ... materials = { {id = M, count = K}, ... } }` (as
# item_prices_base.py reads them)
RECIPE = re.compile(r'\{\s*id\s*=\s*(\d+)\s*,(.*?)materials\s*=\s*\{(.*?)\}\s*,?\s*\}', re.S)
MATERIAL_ID = re.compile(r'(\{\s*id\s*=\s*)(\d+)(\s*,\s*count\s*=)')
NAME = re.compile(r'\bname\s*=\s*"([^"]*)"')
BOOK_HEAD = re.compile(r'^Crafting\.(\w+)\s*=\s*\{', re.M)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def swap_for(pid):
    for ids, swap in SWAPS:
        if pid in ids:
            return swap
    return None


def added_block(nl):
    lines = ['', CRAFT_MARK + ': the boss trophies and the Runic Stone Shard make the charged stones and the',
             '-- emblems of the three level 35 sets (server/README.md "Base crafting recipes"). Appended, so the stock',
             '-- recipes keep their places.', 'do', '    local list = Crafting and Crafting.%s' % ADDED_BOOK,
             '    if type(list) == "table" then', '        for _, craft in ipairs({']
    for pid, name, level, cost, mats in ADDED:
        lines += ['        {', '            id = %d,' % pid, '            name = "%s",' % name,
                  '            level = %d,' % level, '            cost = %d,' % cost, '            count = 1,',
                  '            storage = 0,', '            storageText = "",', '            materials = {']
        lines += ['                {id = %d, count = %d},' % m for m in mats]
        lines += ['            }', '        },']
    lines += ['        }) do', '            list[#list + 1] = craft', '        end', '    end', 'end', '']
    return nl.join(lines)


def patch_book(book, text):
    """(new text, notes) of one crafting book; the same text again when there is nothing to do"""
    notes = []
    if not BOOK_HEAD.search(text):
        return text, ['%s: no `Crafting.<book> = {`, skipped' % book]
    if book in SWAP_BOOKS or any(b == book for b, _n, _o, _w in ID_FIXES):
        out, pos, swapped, fixed = [], 0, 0, 0
        for m in RECIPE.finditer(text):
            pid = int(m.group(1))
            name = NAME.search(m.group(2))
            name = name.group(1) if name else ''
            new_id = pid
            for b, n, wrong, right in ID_FIXES:
                if b == book and n == name and pid == wrong:
                    new_id = right
            swap = swap_for(new_id) if book in SWAP_BOOKS else None
            mats = m.group(3)
            if swap:
                mats = MATERIAL_ID.sub(lambda x: x.group(1) + str(swap.get(int(x.group(2)), int(x.group(2)))) + x.group(3),
                                       mats)
            if new_id == pid and mats == m.group(3):
                continue
            swapped += mats != m.group(3)
            fixed += new_id != pid
            out.append(text[pos:m.start(1)] + str(new_id) + text[m.end(1):m.start(3)] + mats)
            pos = m.end(3)
        out.append(text[pos:])
        text = ''.join(out)
        if swapped:
            notes.append('%s: %d Seraphic / Dawnforged recipe(s) take their own charged stone and emblem' % (book, swapped))
        if fixed:
            notes.append('%s: %d Myst amulet / ring recipe(s) make the amulet / ring' % (book, fixed))
    if book == ADDED_BOOK and CRAFT_MARK not in text:
        nl = '\r\n' if '\r\n' in text else '\n'
        text = (text if text.endswith(nl) or not text else text + nl) + added_block(nl)
        notes.append('%s: %d boss material recipe(s) added' % (book, len(ADDED)))
    return text, notes


def patch_items(xml):
    """(new items.xml, notes): the materials' "what it is for" descriptions"""
    notes = []
    for iid, sentence in sorted(DESCRIPTIONS.items()):
        m = re.search(r'(<item\s+id="%d"[^>]*[^/]>)(.*?)(</item>)' % iid, xml, re.S)
        if not m:
            notes.append('items.xml: %d not found' % iid)
            continue
        body = m.group(2)
        if sentence in body:
            continue
        d = re.search(r'(<attribute\s+key="description"\s+value=")([^"]*)(")', body)
        if d:
            old = d.group(2).rstrip()
            body = body[:d.start()] + d.group(1) + (old + ' ' if old else '') + sentence + d.group(3) + body[d.end():]
        else:
            indent = re.search(r'\n([ \t]*)<attribute', body)
            nl = '\r\n' if '\r\n' in body else '\n'
            body = '%s%s<attribute key="description" value="%s" />' % (
                nl, indent.group(1) if indent else '\t\t', sentence) + body
        xml = xml[:m.start(2)] + body + xml[m.end(2):]
        notes.append('items.xml: %d described' % iid)
    return xml, notes


def run(data, dry=False):
    """-> (report lines, files that change)"""
    report, changed = [], 0
    books = sorted(set(SWAP_BOOKS) | {b for b, _n, _o, _w in ID_FIXES} | {ADDED_BOOK})
    jobs = [(os.path.join(data, BOOKS, b + '.lua'), lambda t, b=b: patch_book(b, t)) for b in books]
    jobs.append((os.path.join(data, ITEMS), patch_items))
    for path, fn in jobs:
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        if not os.path.isfile(path):
            report.append('%s: not found, skipped' % rel)
            continue
        text = read(path)
        new, notes = fn(text)
        report += notes
        if new != text:
            changed += 1
            if not dry:
                write(path, new)
        else:
            report.append('%s: nothing to do' % rel)
    return report, changed


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    check = '--check' in argv
    report, changed = run(args[0], dry=check or '--dry-run' in argv)
    for line in report:
        print(line)
    if check and changed:
        print('%d file(s) still to patch' % changed)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
