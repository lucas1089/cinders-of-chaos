#!/usr/bin/env python3
"""Take the three deck items out of the base data (O570, server/README.md "Deck of Cards (O570)").

usage: python3 -I patch_remove_decks.py DATA_DIR [--dry-run]

Owner, 2026-11-14: "tire os decks e faça o novo deck of cards ...". The Deck of Cards (cards.lua) replaced the Bronze, Silver and
Golden Deck items (27632-27634). Every card a character owns goes into the Deck by itself, and a deck item that is still carried or
lies in a depot is emptied and removed at login (cards.lua migration), so nothing is deleted from the database here. This tool
only stops new decks from reaching players, in the installed base data (idempotent, each change once):
  1. monster/**: a loot entry of a deck is cut out (Lua `{id = N, chance = C}` lines, XML `<item id="N" .../>` lines, and the
     same by name: "bronze deck", "silver deck", "golden deck").
  2. npc/**: a deck is taken out of a trade list: the XML `shop_buyable` / `shop_sellable` entries `name,id,price;` and the Lua
     `shopModule:addBuyableItem` / `addSellableItem` lines.
  3. scripts/**, lib/**: a line that is only a table entry of a deck (a task or quest reward, a store list: `{itemid = N, ...},`)
     is cut out.
Whatever else still names a deck id is listed (a warning for the owner of the step, never a failure: a script that reads the ids
for another reason is left alone). A file is changed only when a pattern is there as the stock text has it. Line endings (LF or
CRLF) are kept. The items stay in items.xml and items.otb (the ids stay known to server and client; the descriptions are set by
patch_badges.py). Never edit the base data by hand: this is the way.
"""
import os
import re
import sys

DECK_IDS = (27632, 27633, 27634)
DECK_NAMES = ('bronze deck', 'silver deck', 'golden deck')


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


IDS = '|'.join(str(i) for i in DECK_IDS)
NAMES = '|'.join(DECK_NAMES)

# 1. loot lines
LOOT_LUA = re.compile(r'^[ \t]*\{[ \t]*(?:id|name)[ \t]*=[ \t]*(?:(?:%s)|"(?:%s)")[ \t]*,[^{}\r\n]*\}[ \t]*,?[ \t]*(?:--[^\r\n]*)?\r?\n'
                      % (IDS, NAMES), re.M | re.I)
LOOT_XML = re.compile(r'^[ \t]*<item[ \t]+(?:id="(?:%s)"|name="(?:%s)")[^>\r\n]*/>[ \t]*(?:<!--[^\r\n]*-->)?[ \t]*\r?\n'
                      % (IDS, NAMES), re.M | re.I)

# 2. trade lists
SHOP_PARAM = re.compile(r'(<parameter[ \t]+key="shop_(?:buyable|sellable)"[ \t]+value=")([^"]*)(")')
SHOP_LUA = re.compile(r'^[ \t]*shopModule:add(?:Buyable|Sellable)Item[^\r\n]*\b(?:%s)\b[^\r\n]*\r?\n' % IDS, re.M)
SHOP_LUA_NAME = re.compile(r'^[ \t]*shopModule:add(?:Buyable|Sellable)Item[^\r\n]*"(?:%s)"[^\r\n]*\r?\n' % NAMES, re.M | re.I)

# 3. whole-line table entries of the scripts
ENTRY = re.compile(r'^[ \t]*\{[^{}\r\n]*\b(?:itemid|itemId|id|item)[ \t]*=[ \t]*(?:%s)\b[^{}\r\n]*\}[ \t]*,?[ \t]*(?:--[^\r\n]*)?\r?\n' % IDS, re.M)

MENTION = re.compile(r'(?<![\w.])(?:%s)(?![\w.])' % IDS)


def clean_loot(text, path):
    rx = LOOT_XML if path.endswith('.xml') else LOOT_LUA
    return rx.subn('', text)


def clean_shop_param(text):
    """-> (new text, entries removed)"""
    removed = [0]

    def one(m):
        keep = []
        for entry in m.group(2).split(';'):
            parts = [x.strip() for x in entry.split(',')]
            if len(parts) >= 2 and (parts[1] in [str(i) for i in DECK_IDS] or parts[0].lower() in DECK_NAMES):
                removed[0] += 1
                continue
            keep.append(entry)
        return m.group(1) + ';'.join(keep) + m.group(3)

    return SHOP_PARAM.sub(one, text), removed[0]


def clean_npc(text, path):
    if path.endswith('.xml'):
        return clean_shop_param(text)
    new, n1 = SHOP_LUA.subn('', text)
    new, n2 = SHOP_LUA_NAME.subn('', new)
    return new, n1 + n2


def clean_entries(text):
    return ENTRY.subn('', text)


def walk_files(root, exts):
    for base, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            if name.endswith(exts):
                yield os.path.join(base, name)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    suffix = ' (dry run, not written)' if dry else ''
    out = []

    def rel(p):
        return 'data/' + os.path.relpath(p, data).replace(os.sep, '/')

    def sweep(sub, exts, fn, what):
        total = files_n = 0
        d = os.path.join(data, sub)
        if os.path.isdir(d):
            for path in walk_files(d, exts):
                text = read(path)
                new, n = fn(text, path)
                if n:
                    total += n
                    files_n += 1
                    if not dry:
                        write(path, new)
        out.append('data/%s: %s' % (sub, ('%d %s removed in %d file(s)%s' % (total, what, files_n, suffix)) if total
                                    else 'already done (no deck in any %s)' % what.split(' ')[0]))

    sweep('monster', ('.lua', '.xml'), clean_loot, 'loot line(s)')
    sweep('npc', ('.lua', '.xml'), clean_npc, 'trade entr(ies)')
    sweep('scripts', ('.lua',), lambda t, p: clean_entries(t), 'reward / list line(s)')
    sweep('lib', ('.lua',), lambda t, p: clean_entries(t), 'reward / list line(s)')

    left = []
    if not dry:
        for sub in ('scripts', 'npc', 'lib', 'events', 'monster'):
            d = os.path.join(data, sub)
            if not os.path.isdir(d):
                continue
            for p in walk_files(d, ('.lua', '.xml')):
                for line in read(p).splitlines():
                    if MENTION.search(line):
                        left.append(rel(p))
                        break
    if left:
        out.append('WARNING: a deck id is still named in: %s (read by hand: the card and badge scripts and the Chaos item lists '
                   'keep it on purpose)' % ', '.join(sorted(set(left))[:8]))
    print('\n'.join(out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
