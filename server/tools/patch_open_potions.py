#!/usr/bin/env python3
"""Every class drinks every health, mana and spirit potion (idempotent). install_all.py step `openpotions`.

usage: python3 -I patch_open_potions.py DATA_DIR [--dry-run]

Owner decision 2026-10-24 ("Let every class use any type of potion", server/README.md "Open potions", ROADMAP O175).
DATA_DIR is the base server's data folder.
  actions/scripts/other/potions.lua: every potion entry that heals (health or mana, the spirit potions too) loses its
    `vocations = {...}` list, so the stock check `potion.vocations and not table.contains(...)` never refuses a class. The
    level stays: it is a balance gate (a level 1 character does not drink a supreme potion), and the refusal text becomes
    "Only characters of level N or above may drink this fluid.". The buff potions (berserk, mastermind, bullseye: a
    `condition`, no heal) keep their lists: they are not health, mana or spirit potions.
  items/items.xml: the Look text "This potion can only be consumed by knights of level 80 or higher." of those potions
    becomes "This potion can be consumed by characters of level 80 or higher."
add_vocations.py runs before this step and only appends to a list that exists, so a re-run of it brings nothing back.
Line ends (CRLF) are kept. A second run changes nothing.
"""
import os
import re
import sys

POTIONS = os.path.join('actions', 'scripts', 'other', 'potions.lua')
ITEMS = os.path.join('items', 'items.xml')

ENTRY = re.compile(r'(\n[ \t]*\[\d+\]\s*=\s*\{)')
VOC_LINE = re.compile(r'\n[ \t]*vocations\s*=\s*\{[\d,\s]*\},?[ \t]*(?=\n)')
VOC_DEF = re.compile(r'vocations\s*=\s*\{')
HEALS = re.compile(r'\b(health|mana)\s*=\s*\{')
REFUSAL = re.compile(r'(description\s*=\s*")Only .*?( of level \d+ or above)? may drink this (fluid|potion)\.(")')
LOOK = re.compile(r'(value=")This potion can only be consumed by [^"]*?( of level \d+ or higher)?\.(")')


def patch_potions(text):
    """(new text, number of potion entries opened)"""
    parts = ENTRY.split(text)
    count = 0
    for i in range(2, len(parts), 2):
        chunk = parts[i]
        # the entry ends where the next `[id] = {` starts (the split); a heal and a vocation list in the same entry
        if not HEALS.search(chunk) or not VOC_LINE.search(chunk):
            continue
        new = VOC_LINE.sub('', chunk, count=1)

        def refusal(m):
            level = m.group(2) or ''
            return '%s%s%s may drink this %s.%s' % (m.group(1), 'Only characters' if level else 'Anyone', level,
                                                    m.group(3), m.group(4))
        new = REFUSAL.sub(refusal, new, count=1)
        if new != chunk:
            parts[i] = new
            count += 1
    return ''.join(parts), count


def opened_ids(text):
    """the item ids of potions.lua that heal and carry no vocation list"""
    parts = ENTRY.split(text)
    ids = set()
    for i in range(1, len(parts) - 1, 2):
        if HEALS.search(parts[i + 1]) and not VOC_DEF.search(parts[i + 1]):
            ids.add(re.search(r'\[(\d+)\]', parts[i]).group(1))
    return ids


def patch_items(items_text, ids):
    """(new items.xml text, number of items changed): the Look text of the opened potions"""
    count = [0]

    def block(m):
        item_id = re.search(r'id="(\d+)"', m.group(0))
        if not item_id or item_id.group(1) not in ids:
            return m.group(0)

        def look(t):
            level = t.group(2) or ''
            return '%sThis potion can be consumed by characters%s.%s' % (t.group(1), level, t.group(3))
        out = LOOK.sub(look, m.group(0), count=1)
        if out != m.group(0):
            count[0] += 1
        return out
    out = re.sub(r'<item\s[^>]*\bid="\d+"[^>]*[^/>]>(?:(?!<item\s).)*?</item>', block, items_text, flags=re.S)
    return out, count[0]


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    data = args[0]
    pot = os.path.join(data, POTIONS)
    items = os.path.join(data, ITEMS)
    if not os.path.isfile(pot):
        print('%s: not found (skipped)' % POTIONS.replace(os.sep, '/'))
        return 0
    raw = read(pot)
    crlf = '\r\n' in raw
    new, n = patch_potions(raw.replace('\r\n', '\n'))
    ids = opened_ids(new)
    if n:
        write_text = new.replace('\n', '\r\n') if crlf else new
        if not dry:
            write(pot, write_text)
    print('%s: %d potions open to every class' % (POTIONS.replace(os.sep, '/'), n))
    ni = 0
    if os.path.isfile(items):
        iraw = read(items)
        icrlf = '\r\n' in iraw
        inew, ni = patch_items(iraw.replace('\r\n', '\n'), ids)
        if ni and not dry:
            write(items, inew.replace('\n', '\r\n') if icrlf else inew)
    print('items.xml: %d potion descriptions say so' % ni)
    if not n and not ni:
        print('open potions: nothing to change')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
