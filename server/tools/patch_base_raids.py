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
new one is; when the new one is missing too, the spawn line is taken out and kept as an XML comment. The name an older run of
worldtexts wrote in place of an old name (Ocyakao -> Frostmaw, Chayenne -> Wren: base_world_names.csv, looked up by sha256) is fixed
the same way. A raid file or a name that is not there is skipped. Idempotent: a second run finds nothing to change. --dry-run writes nothing.
install_all.py step `baseraids` (after `monsternames` and `spawns`).
"""
import csv
import glob
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# the rename lists keyed by sha256 of the old name (lower case): row name = what the world / NPC rename tools wrote
RENAME_CSVS = [os.path.join(os.path.dirname(HERE), 'data', 'npc', n) for n in ('base_world_names.csv', 'base_npc_names.csv')]

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


def renamed_names(old, csvs=None):
    """the names an older run of the worldtexts / npcnames tools wrote in place of the old name (raid spawn names were
    renamed by it before O294, so a server that ran it holds "Frostmaw" where the base file had "Ocyakao"); [] when no row"""
    key = hashlib.sha256(re.sub(r'\s+', ' ', old.strip().lower()).encode('utf-8')).hexdigest()
    out = []
    for path in (RENAME_CSVS if csvs is None else csvs):
        if not os.path.isfile(path):
            continue
        with open(path, encoding='utf-8', newline='') as f:
            for row in csv.DictReader(f):
                if (row.get('sha256') or '').strip().lower() == key and (row.get('name') or '').strip():
                    out.append(row['name'].strip())
    return out


def with_aliases(fixes, csvs=None):
    """fixes + each old name's rename-list replacement mapped to the same new monster"""
    out = dict(fixes)
    for old, new in fixes.items():
        for alias in renamed_names(old, csvs):
            out.setdefault(alias, new)
    return out


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


def unknown_spawns(data, known):
    """[(raid file, name)] of every spawn name of data/raids/**/*.xml that no known monster has (outside XML comments)"""
    out = []
    for path in sorted(glob.glob(os.path.join(data, 'raids', '**', '*.xml'), recursive=True)):
        with open(path, encoding='utf-8', errors='replace') as f:
            text = re.sub(r'<!--.*?-->', '', f.read(), flags=re.S)
        for m in SPAWN.finditer(text):
            if m.group('name').lower() not in known:
                out.append((os.path.relpath(path, data).replace(os.sep, '/'), m.group('name')))
    return out


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
        new, done = patch(text, with_aliases(fixes), known)
        if not done:
            print('%s: nothing to change' % rel)
            continue
        for old, repl in done:
            print('%s: %s -> %s%s' % (rel, old, repl or 'taken out', ' (dry run)' if dry else ''))
        if not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
    if not dry:
        for rel, name in unknown_spawns(data, known_monsters(data)):
            print('WARNING %s: spawn "%s" is no monster type (the engine logs "Cant create monster")' % (rel, name))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
