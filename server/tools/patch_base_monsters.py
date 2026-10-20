#!/usr/bin/env python3
"""Load warnings of the base server's monsters, fixed in its files (idempotent). install_all.py step `basemonsters`.

usage: python3 -I patch_base_monsters.py DATA_DIR [--dry-run]

DATA_DIR is the base server's data folder. Every monster file under DATA_DIR/monster (XML and Lua) except our own
(monster/monsters/chaos, monster/lua/chaos: tools/fix_monster_xml.py and check_content.py keep those clean):
  * a speed spell below -1000 (speedchange, minspeedchange, maxspeedchange; Lua speedChange, minSpeedChange,
    maxSpeedChange) becomes -1000. The engine clamps it to that anyway, with a console warning at every start
    ("you cannot reduce a creatures speed below -1000"; start log 2026-10-16: 11 bosses)
  * a loot item named with its article ("the torso of a jester doll") becomes the item id of that name in
    DATA_DIR/items/items.xml (the engine looks loot names up without the article: "Unknown loot item", "Cant load
    loot"; undead_jester.xml). The old name stays as a comment after the tag
  * a monster no longer flees at low health (owner 2026-10-18): runonhealth="N" (XML) / runHealth = N (Lua) with N > 0
    becomes 0
  * fire immunity (XML <immunity fire="1"/> or firePercent 100+; Lua {type = "fire"} or a fire percent of 100+) becomes
    a fire resistance of FIRE_RESIST_PERCENT (30: the monster takes 70%) so that Pyre Oath never burns its owner for
    nothing (owner decision, C7; tools/monster_fire_resist.py holds the number)
  * a race the engine does not know (Lua monster.race = "magical", "dragon"; XML race="...") gets a known one:
    RACE_MAP, else blood ("Unknown race type")
Only those attributes change. A second run changes nothing. Prints one line per changed file and a summary.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
import monster_fire_resist as fire  # noqa: E402

KNOWN_RACES = ('venom', 'blood', 'undead', 'fire', 'energy')
RACE_MAP = {'magical': 'energy', 'magic': 'energy', 'dragon': 'blood', 'demon': 'fire', 'elemental': 'energy',
            'construct': 'energy', 'ghost': 'undead', 'spirit': 'undead', 'beast': 'blood', 'humanoid': 'blood',
            'poison': 'venom', 'slime': 'venom'}
MIN_SPEED = -1000
ARTICLES = ('the ', 'a ', 'an ')
OWN = ('chaos',)

XML_SPEED_RE = re.compile(r'(\s(?:speedchange|minspeedchange|maxspeedchange)\s*=\s*")(-?\d+)(")', re.I)
LUA_SPEED_RE = re.compile(r'(\b(?:speedChange|minSpeedChange|maxSpeedChange)\s*=\s*)(-\s*\d+)')
LOOT_RE = re.compile(r'<item\b[^>]*?\bname="([^"]*)"[^>]*?/?>')
XML_RUN_RE = re.compile(r'(\brunonhealth\s*=\s*")(\d+)(")', re.I)
LUA_RUN_RE = re.compile(r'(\brunHealth\s*=\s*)(\d+)')
XML_RACE_RE = re.compile(r'(<monster\b[^>]*?\srace=")([^"]*)(")')
LUA_RACE_RE = re.compile(r'(\.race\s*=\s*)(["\'])([^"\']*)\2')
ITEM_RE = re.compile(r'<item\b([^>]*)>')


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def attr(tag, name):
    m = re.search(r'\s%s="([^"]*)"' % name, tag)
    return m.group(1) if m else None


def item_names(items_xml):
    """{lower-case name: lowest id} of items.xml (single ids and fromid..toid ranges), as the engine's name lookup"""
    names = {}
    for m in ITEM_RE.finditer(items_xml):
        tag = m.group(1)
        name = attr(tag, 'name')
        if not name:
            continue
        first = attr(tag, 'id') or attr(tag, 'fromid')
        try:
            first = int(first)
        except (TypeError, ValueError):
            continue
        key = name.lower()
        if key not in names or first < names[key]:
            names[key] = first
    return names


def resolve(name, names):
    """item id for a loot name the engine does not know, or None"""
    low = name.lower()
    if low in names:
        return None  # the engine knows it
    for art in ARTICLES:
        if low.startswith(art) and low[len(art):] in names:
            return names[low[len(art):]]
    return None


def new_race(race):
    if race.lower() in KNOWN_RACES or race.isdigit():
        return None
    return RACE_MAP.get(race.lower(), 'blood')


def patch_xml(text, names):
    """(new text, [change, ...])"""
    changes = []

    def speed(m):
        v = int(m.group(2))
        if v >= MIN_SPEED:
            return m.group(0)
        changes.append('speed %d -> %d' % (v, MIN_SPEED))
        return m.group(1) + str(MIN_SPEED) + m.group(3)
    text = XML_SPEED_RE.sub(speed, text)

    def run(m):
        if int(m.group(2)) == 0:
            return m.group(0)
        changes.append('runonhealth %s -> 0' % m.group(2))
        return m.group(1) + '0' + m.group(3)
    text = XML_RUN_RE.sub(run, text)

    def loot(m):
        tag, name = m.group(0), m.group(1)
        if attr(tag, 'id') is not None:
            return tag
        sid = resolve(name, names)
        if sid is None:
            return tag
        changes.append('loot "%s" -> id %d' % (name, sid))
        new = tag.replace('name="%s"' % name, 'id="%d"' % sid, 1)
        return new + '<!-- %s -->' % name.replace('--', '- -')
    text = LOOT_RE.sub(loot, text)

    def race(m):
        r = new_race(m.group(2))
        if r is None:
            return m.group(0)
        changes.append('race %s -> %s' % (m.group(2), r))
        return m.group(1) + r + m.group(3)
    text = XML_RACE_RE.sub(race, text, count=1)
    text, immune = fire.xml(text)
    if immune:
        changes.append('fire immunity -> %d%% resistance' % fire.FIRE_RESIST_PERCENT)
    return text, changes


def patch_lua(text):
    changes = []

    def speed(m):
        v = int(m.group(2).replace(' ', ''))
        if v >= MIN_SPEED:
            return m.group(0)
        changes.append('speed %d -> %d' % (v, MIN_SPEED))
        return m.group(1) + str(MIN_SPEED)
    text = LUA_SPEED_RE.sub(speed, text)

    def run(m):
        if int(m.group(2)) == 0:
            return m.group(0)
        changes.append('runHealth %s -> 0' % m.group(2))
        return m.group(1) + '0'
    text = LUA_RUN_RE.sub(run, text)

    def race(m):
        r = new_race(m.group(3))
        if r is None:
            return m.group(0)
        changes.append('race %s -> %s' % (m.group(3), r))
        return m.group(1) + m.group(2) + r + m.group(2)
    text = LUA_RACE_RE.sub(race, text)
    text, immune = fire.lua(text)
    if immune:
        changes.append('fire immunity -> %d%% resistance' % fire.FIRE_RESIST_PERCENT)
    return text, changes


def monster_files(data):
    root = os.path.join(data, 'monster')
    for folder, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in OWN)
        for f in sorted(files):
            if f.endswith('.xml') or f.endswith('.lua'):
                yield os.path.join(folder, f)


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    data = args[0]
    items_path = os.path.join(data, 'items', 'items.xml')
    if not os.path.isdir(os.path.join(data, 'monster')) or not os.path.isfile(items_path):
        print('%s: no monster folder or items/items.xml' % data)
        return 1
    names = item_names(read(items_path))
    files = changed = 0
    for path in monster_files(data):
        if os.path.basename(path) == 'monsters.xml' and os.path.dirname(path) == os.path.join(data, 'monster'):
            continue  # the registry
        text = read(path)
        new, changes = patch_xml(text, names) if path.endswith('.xml') else patch_lua(text)
        files += 1
        if new == text:
            continue
        changed += 1
        if not dry:
            write(path, new)
        print('%s: %s' % (os.path.relpath(path, data).replace(os.sep, '/'), '; '.join(changes)))
    print('base monsters: %d file(s) checked, %d %s' % (files, changed,
                                                       'would change' if dry else 'changed') if changed else
          'base monsters: %d file(s) checked, nothing to change' % files)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
