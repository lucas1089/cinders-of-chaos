#!/usr/bin/env python3
"""Take the sell-only junk items out of the Chaos monsters' loot (idempotent).

usage: python3 -I patch_junk_loot.py [DATA_DIR] [--check] [--list]

DATA_DIR is a data folder (default: server/data of this repo). The tool edits data/monster/monsters/chaos/**/*.xml and
data/monster/lua/chaos/*.lua: only the loot line of a listed id inside <loot> / monster.loot goes, nothing else is
rewritten. The items stay in items.xml, the NPC lists, the stash and the price table (item_price_rules.csv keeps the
price of the ids that only a monster put in the table), so copies the players hold still sell.

JUNK is the owner-approved list of 2026-10-20 (58 items, README "Junk loot"), less six ids that were never checked
against the base server (27053 cracked alabaster vase, 29001 colourful snail shell) or that may be map quest items
(6097 hook, 6098 eye patch, 6088 and 6090 music sheets): they stay in their loot (owner decision 2026-10-20).
--check changes nothing and exits 1 when a file still lists a junk id.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True

JUNK = {
    25380: 'titanium token', 2153: 'violet gem', 2155: 'green gem', 2156: 'red gem', 2158: 'blue gem',
    2154: 'yellow gem', 2145: 'small diamond', 2157: 'gold nugget', 5879: 'spider silk', 5913: 'brown piece of cloth',
    6500: 'demonic essence', 8303: 'energy soil', 9006: 'toy spider', 10567: 'polar bear paw', 10603: 'swamp grass',
    11231: 'nettle blossom', 12401: 'bamboo stick', 12409: 'broken helmet', 12436: 'skull belt', 18425: 'blazing bone',
    20102: 'swampling moss', 21399: 'golden raid token', 23563: 'mono detector', 23569: 'metal toe',
    25379: 'platinum token', 28036: 'heart of the mountains',
}
# creature products of the pack: 36010 .. 36035 except 36036 ff (food, kept)
for _i, _n in enumerate(('goblin tooth', 'goblin skull', 'piece of scrap metal', 'pouch of black powder', 'frayed rope',
                         'carved bone', 'tribal feather', 'boar hide', 'bear pelt', 'wolf pelt', 'elk antler',
                         'piece of heartwood', 'spore sack', 'lump of moss gel', 'hornet stinger', 'pouch of pixie dust',
                         'tuft of spider silk', 'stag beetle horn', 'owl feather', 'dryad leaf', 'withered leaf',
                         'handful of treant seeds', 'moss clump', 'drop of inky ichor', 'drop of toad venom',
                         'cloud of royal spores')):
    JUNK[36010 + _i] = _n
NOT_CHECKED = {27053: 'cracked alabaster vase', 29001: 'colourful snail shell', 6097: 'hook', 6098: 'eye patch',
               6088: 'music sheet', 6090: 'music sheet'}  # left out on purpose
assert len(JUNK) == 52 and not set(JUNK) & set(NOT_CHECKED)

IDS = '|'.join(str(i) for i in sorted(JUNK))
XML_LINE = re.compile(r'^[ \t]*<item\s+id="(?:%s)"[^>\n]*/>[ \t]*(?:<!--.*?-->)?[ \t]*\r?\n' % IDS, re.M)
LUA_LINE = re.compile(r'^[ \t]*\{[ \t]*id[ \t]*=[ \t]*(?:%s)[ \t]*,[^\n]*?\}[ \t]*,?[ \t]*(?:--[^\n]*)?\r?\n' % IDS, re.M)


def xml_fix(text):
    def block(m):
        return XML_LINE.sub('', m.group(0))
    return re.sub(r'<loot>.*?</loot>', block, text, flags=re.S)


def lua_fix(text):
    m = re.search(r'monster\.loot\s*=\s*\{\n(.*?)\n\}', text, re.S)
    if not m:
        return text
    body = m.group(1) + '\n'
    body = LUA_LINE.sub('', body)
    lines = body.rstrip('\n').split('\n') if body.strip() else []
    if lines:  # the last entry carries no comma
        lines[-1] = re.sub(r',([ \t]*(?:--[^\n]*)?)$', r'\1', lines[-1]) if re.search(r'\{.*\}[ \t]*,', lines[-1]) else lines[-1]
    return text[:m.start(1)] + '\n'.join(lines) + text[m.end(1):]


def targets(data):
    root = os.path.join(data, 'monster', 'monsters', 'chaos')
    for d, _s, files in sorted(os.walk(root)):
        for f in sorted(files):
            if f.endswith('.xml'):
                yield os.path.join(d, f), xml_fix
    root = os.path.join(data, 'monster', 'lua', 'chaos')
    if os.path.isdir(root):
        for f in sorted(os.listdir(root)):
            if f.endswith('.lua'):
                yield os.path.join(root, f), lua_fix


def main(argv):
    check = '--check' in argv
    args = [a for a in argv if not a.startswith('--')]
    data = args[0] if args else os.path.join(os.path.dirname(HERE), 'data')
    if '--list' in argv:
        for i in sorted(JUNK):
            print(i, JUNK[i])
        return 0
    bad = 0
    for p, fix in targets(data):
        t = open(p, encoding='utf-8', errors='surrogateescape', newline='').read()
        new = fix(t)
        if fix(new) != new:
            raise SystemExit('%s: not idempotent' % p)
        if new != t:
            bad += 1
            if check:
                print('junk loot left:', os.path.relpath(p, data))
            else:
                open(p, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
                print('junk loot removed:', os.path.relpath(p, data))
    print('junk loot:', ('up to date' if not bad else '%d file(s) to patch' % bad) if check else '%d file(s) changed' % bad)
    return 1 if (check and bad) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
