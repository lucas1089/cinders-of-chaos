#!/usr/bin/env python3
"""Install the crafting orbs into a base server (items.xml names, the use-with flag of two orbs, the stock reroll script).

usage: python3 -I install_crafting.py DATA_DIR [--dry-run]

1. data/items/items.xml: the Orbs of Alchemy, Annulment and Scouring are the stackable rune stones 24691, 24697 and
   24688 (no items.xml entry, nothing uses them). They get a name, plural, description and weight here. The Orb of
   Transmutation (29851) and the Exalted Orb (29855) are existing currency items (character upgrades); their
   description gets a sentence about crafting. Descriptions written by an older version of this script are updated.
2. data/items/items.otb: the Orb of Transmutation and the Exalted Orb get the "useable" flag (FLAG_USEABLE), which the
   engine needs for "use with" (Game::playerUseItemEx). The other five orbs have it already. The client side is the
   multi-use flag of the same items in Tibia.dat: client/tools/sprites/set_multiuse.py. A copy of the original file is
   kept as items.otb.bak the first time.
3. data/scripts/customs/rarity/reroll_rarity_stats.lua: the stock Chaos and Divine Orb action made a plain copy of a
   unique item (a unique has no "rarity", so the reroll gave it none and dropped its name and stats). isRerollable now
   refuses items with the "chaos_unique" attribute, as every crafting orb does (data/lib/chaos_crafting.lua). Its two
   actions are no longer registered when data/scripts/chaos/crafting.lua registered the Chaos and Divine Orbs itself
   (same rules, logging and Rift Keys for all seven orbs).

Idempotent: an item that already has an entry is left alone, descriptions are only extended once, the otb flag is
only set when missing, and the guards carry marker comments.
"""
import os, re, sys

NEW_ITEMS = [
    (24691, 'an', 'Orb of Alchemy', 'Orbs of Alchemy',
     'Use it with a normal item: it becomes Rare, Epic or Legendary with random modifiers. On a Rift Key without modifiers: 2-3 modifiers.'),
    (24697, 'an', 'Orb of Annulment', 'Orbs of Annulment',
     'Use it with an item with a rarity or a Rift Key: one random modifier is removed.'),
    (24688, 'an', 'Orb of Scouring', 'Orbs of Scouring',
     'Use it with an item with a rarity: the rarity and every modifier are removed. On a Rift Key: every modifier is removed.'),
]
EXTEND = {
    29851: 'Crafting: use it with a normal item to make it Common or Uncommon, or with a Rift Key without modifiers to give it one.',
    29855: 'Crafting: use it with an item with a rarity or a Rift Key to add one random modifier.',
}
# texts of older versions of this script, replaced by the ones above
OLD_TEXTS = [
    ('Use it with a normal item: it becomes Rare, Epic or Legendary with random modifiers. Or use it at the crafting bench (!craft).',
     NEW_ITEMS[0][4]),
    ('Use it with an item with a rarity: one random modifier is removed. Or use it at the crafting bench (!craft).',
     NEW_ITEMS[1][4]),
    ('Use it with an item with a rarity: the rarity and every modifier are removed. Or use it at the crafting bench (!craft).',
     NEW_ITEMS[2][4]),
    (' Crafting: turns a normal item into a Common or Uncommon one (use it to open the crafting bench).', ''),
    (' Crafting: adds one random modifier to an item with a rarity (use it to open the crafting bench).', ''),
]
WEIGHT = 50

USEABLE_IDS = (29851, 29855)  # Orb of Transmutation, Exalted Orb: items.otb FLAG_USEABLE
FLAG_USEABLE = 1 << 4
OTB_ESC, OTB_START, OTB_END = 0xFD, 0xFE, 0xFF

REGISTER_MARKER = '-- Chaos: crafting.lua registers this orb (install_crafting.py)'


GUARD_MARKER = '-- Chaos: uniques are never rerolled (install_crafting.py)'
GUARD = ('  ' + GUARD_MARKER + '\n'
         '  if item:getCustomAttribute("chaos_unique") then return false end\n')


def patch_items(text):
    notes = []
    for old, new in OLD_TEXTS:
        if old in text:
            text = text.replace(old, new)
            notes.append('items.xml: updated an older crafting text')
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


def _escape(data):
    out = bytearray()
    for b in data:
        if b in (OTB_ESC, OTB_START, OTB_END):
            out.append(OTB_ESC)
        out.append(b)
    return bytes(out)


def patch_otb(data, ids=USEABLE_IDS):
    """Set FLAG_USEABLE on the item nodes of these server ids. Returns (new bytes, notes).
    An item node is START, group (u8), flags (u32), then attributes; the first one is the server id
    (attr 0x10, u16 length 2, u16 id). Bytes inside a node are escaped with 0xFD."""
    notes = []
    data = bytearray(data)
    for sid in ids:
        pattern = _escape(bytes([0x10, 0x02, 0x00]) + sid.to_bytes(2, 'little'))
        found = False
        at = data.find(pattern)
        while at >= 0:
            # walk back over group + flags (5 logical bytes, maybe escaped) to the node start
            raw, i, logical = [], at - 1, []
            while i >= 0 and len(logical) < 5:
                b = data[i]
                if i > 0 and data[i - 1] == OTB_ESC and b in (OTB_ESC, OTB_START, OTB_END):
                    logical.insert(0, (i - 1, b)); i -= 2
                else:
                    if b in (OTB_START, OTB_END, OTB_ESC):
                        break
                    logical.insert(0, (i, b)); i -= 1
            if len(logical) == 5 and i >= 0 and data[i] == OTB_START and (i == 0 or data[i - 1] != OTB_ESC):
                found = True
                flags = int.from_bytes(bytes(b for _, b in logical[1:]), 'little')
                if flags & FLAG_USEABLE:
                    notes.append('items.otb: %d already useable' % sid)
                else:
                    flags |= FLAG_USEABLE
                    start, end = logical[1][0], at  # the raw span of the flags
                    data[start:end] = _escape(flags.to_bytes(4, 'little'))
                    notes.append('items.otb: %d made useable (use with)' % sid)
                break
            at = data.find(pattern, at + 1)
        if not found:
            notes.append('items.otb: %d not found' % sid)
    return bytes(data), notes


def patch_reroll(text):
    notes = []
    if GUARD_MARKER in text:
        notes.append('unique guard already')
    else:
        m = re.search(r'local function isRerollable\(item\)\n(.*?\n)', text)
        if not m:
            return text, 'isRerollable not found'
        # after the first guard line of the function (the "not an item" test)
        at = m.end()
        text = text[:at] + GUARD + text[at:]
        notes.append('unique guard patched')
    if REGISTER_MARKER in text:
        notes.append('registration already')
    else:
        n = 0
        for var in ('chaos', 'sanctum'):
            line = '%s:register()' % var
            if re.search(r'^%s\s*$' % re.escape(line), text, re.M):
                text = re.sub(r'^%s\s*$' % re.escape(line),
                              'if not (ChaosCrafting and ChaosCrafting.ownsStockOrbs) then %s end %s' % (line, REGISTER_MARKER),
                              text, count=1, flags=re.M)
                n += 1
        notes.append('registration patched (%d)' % n if n else 'registration lines not found')
    return text, ', '.join(notes)


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
    path = os.path.join(data, 'items', 'items.otb')
    if os.path.exists(path):
        raw = open(path, 'rb').read()
        new, notes = patch_otb(raw)
        for n in notes:
            print(n)
            if n.endswith('not found'):
                status = 1
        if new != raw and not dry:
            if not os.path.exists(path + '.bak'):
                open(path + '.bak', 'wb').write(raw)
            open(path, 'wb').write(new)
    else:
        print('items.otb: not found')
        status = 1
    path = os.path.join(data, 'scripts', 'customs', 'rarity', 'reroll_rarity_stats.lua')
    if os.path.exists(path):
        text = open(path, encoding='utf-8', errors='surrogateescape').read()
        new, st = patch_reroll(text)
        print('reroll_rarity_stats.lua:', st)
        if 'not found' in st:
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
