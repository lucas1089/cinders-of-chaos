#!/usr/bin/env python3
"""Base raids that name a monster the server does not have (server/README.md "Base raid fixes").

usage: python3 -I patch_base_raids.py DATA_DIR [--dry-run]

DATA_DIR is the server's data folder. The engine runs a raid event that names an unknown monster as
"[Error] Raids: Cant create monster NAME" and the raid loses that spawn. The Thais orc raid (raids/thais/orcs.xml) has
three single spawns for monsters called "Orc Helmet", "Orc Shield" and "Orc Armor". A scan of all 90 raid files found
five more names no monster has: "Orc Sambackpack" (an area spawn line), "White Pale", "Chayenne", "Ocyakao" and "Hirintror".
They get Orc Warlord, Spectre, Dragon Lord, Yeti and Frost Dragon. The raids use no items. None of them is registered in
monsters.xml or made by a Lua monster, in the base or after our installs. Each such spawn now names "Orc Leader", the
orc chief the base does have (one at each of the three spots, as the raid meant). The change is made only when the
old name is not a known monster (registered in monsters.xml, or Game.createMonsterType("...") in a Lua monster) and the
new one is; when the new one is missing too, the spawn line is taken out and kept as an XML comment. A raid file or a
name that is not there is skipped. Idempotent: a second run finds nothing to change. --dry-run writes nothing.
install_all.py step `baseraids` (after `monsternames` and `spawns`).
"""
import glob
import os
import re
import sys

# raid file (relative to DATA_DIR) -> {old name: new name}
# The new names are base monsters that monsternames does not rename and that match the old one in theme and strength.
FIXES = {
    'raids/thais/orcs.xml': {'Orc Helmet': 'Orc Leader', 'Orc Shield': 'Orc Leader', 'Orc Armor': 'Orc Leader'},
    'raids/venore/orc_backpack.xml': {'Orc Sambackpack': 'Orc Warlord'},
    'raids/darashia/white_pale.xml': {'White Pale': 'Spectre'},
    'raids/chayenne/chayenne.xml': {'Chayenne': 'Dragon Lord'},
    'raids/svargrond/ocyakao.xml': {'Ocyakao': 'Yeti'},
    'raids/svargrond/hirintror.xml': {'Hirintror': 'Frost Dragon'},
}
# single spawns and the monster lines of area spawns
SPAWN = re.compile(r'(?P<head><(?:singlespawn|monster)\b[^>]*?\bname=")(?P<name>[^"]*)(?P<tail>"[^>]*?/>)')


def known_monsters(data):
    """lower case names of the monsters monsters.xml registers and the Lua monsters make"""
    names = set()
    path = os.path.join(data, 'monster', 'monsters.xml')
    if os.path.isfile(path):
        with open(path, encoding='utf-8', errors='replace') as f:
            names |= {n.lower() for n in re.findall(r'<monster\s+name="([^"]+)"', f.read())}
    for lua in glob.glob(os.path.join(data, 'monster', '**', '*.lua'), recursive=True):
        with open(lua, encoding='utf-8', errors='replace') as f:
            names |= {n.lower() for n in re.findall(r'createMonsterType\(\s*["\']([^"\']+)["\']', f.read())}
    return names


def patch(text, fixes, known):
    """(new text, [(old name, new name or None)])"""
    done = []

    def sub(m):
        old = m.group('name')
        new = fixes.get(old)
        if new is None or old.lower() in known:
            return m.group(0)
        if new.lower() in known:
            done.append((old, new))
            return m.group('head') + new + m.group('tail')
        done.append((old, None))
        return '<!-- ' + m.group(0).replace('--', '- -') + ' -->'

    return SPAWN.sub(sub, text), done


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    args = [a for a in args if a != '--dry-run']
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__)
        return 1
    data = args[0]
    known = known_monsters(data)
    for rel, fixes in FIXES.items():
        path = os.path.join(data, *rel.split('/'))
        if not os.path.isfile(path):
            print('%s: no such raid file, skipped' % rel)
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, done = patch(text, fixes, known)
        if not done:
            print('%s: nothing to change' % rel)
            continue
        for old, repl in done:
            print('%s: %s -> %s%s' % (rel, old, repl or 'taken out', ' (dry run)' if dry else ''))
        if not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
