#!/usr/bin/env python3
"""Snapshot of the biggest single hits of the rift guardian candidates (O476; server/README.md "Rifts", Level warning).

usage: python3 -I server/tools/survey_guardian_hits.py INSTALLED_DATA        write server/data/spells/guardian_hits.csv
       python3 -I server/tools/survey_guardian_hits.py INSTALLED_DATA --check  exit 1 when the committed file differs

INSTALLED_DATA is the data/ folder of a base server after `install_all.py` (monster/monsters.xml, monster/monsters/**,
monster/lua/**). The stock monster files are not in git, so the model (tools/guardian_model.py) reads this table, as
tools/survey_base_weapons.py does for the weapons. One row per entry of the bounty pool (data/scripts/chaos/bounty_pool.lua
`hunt`, at least `minPoolHealth` health: the rift candidates):
  name, level (the pool's hunting level, what the rift windows cut), mlevel (the level of the type's <level> range, its
  middle, 0 for a type without one: the engine's monsterBonusDamage reads it), melee_max / melee_mean (the biggest single
  melee or physical attack: its largest roll and the middle of its range), elem_max / elem_mean (the same for every other
  direct damage attack).
Counted: attacks with a damage range (min / max in the XML, minDamage / maxDamage in a Lua type); a melee attack with only
skill and attack is turned into its maximum (the engine's formula). Not counted: conditions (poison, fire, bleed ticks),
mana drain, and the attacks that name a spell with no numbers (curses, skill reducers). The largest roll of a monster spell
is a bell around the middle, so the max is rare; the mean is the typical roll.
"""
import csv
import io
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
OUT = os.path.join(SERVER, 'data', 'spells', 'guardian_hits.csv')
POOL = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'bounty_pool.lua')
RIFT = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'rift_config.lua')
COLS = ['name', 'level', 'mlevel', 'melee_max', 'melee_mean', 'elem_max', 'elem_mean']
SKIP_NAMES = ('condition', 'curse', 'skill reducer', 'drunk', 'speed', 'outfit', 'invisible', 'field', 'dread', 'manadrain',
              'cancel', 'paralyze')


def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def attr(tag, key):
    m = re.search(r'\b' + key + r'="([^"]*)"', tag)
    return m.group(1) if m else None


def melee_max(skill, attack):
    """Weapons::getMaxMeleeDamage (the base engine): a melee attack given by skill and attack value"""
    return int(math.ceil(skill * (attack * 0.05) + attack * 0.5))


def classify(name):
    """'melee', 'elem' or None (a condition, a mana drain or a spell without numbers)"""
    n = name.lower()
    if n.startswith('melee'):
        return 'melee'
    if n in ('physical', 'bleed'):
        return 'melee'
    if n.endswith('condition') or any(s in n for s in SKIP_NAMES):
        return None
    return 'elem'


def best(attacks):
    """{kind: (largest roll, its mean)} from [(kind, lo, hi)]"""
    out = {}
    for kind, lo, hi in attacks:
        top = max(abs(lo), abs(hi))
        mean = (abs(lo) + abs(hi)) / 2.0
        if top > 0 and (kind not in out or top > out[kind][0]):
            out[kind] = (top, mean)
    return out


def xml_attacks(text):
    block = re.search(r'<attacks>(.*?)</attacks>', text, re.S)
    out = []
    for tag in re.findall(r'<attack\s[^>]*?/?>', block.group(1) if block else ''):
        kind = classify(attr(tag, 'name') or '')
        if not kind:
            continue
        lo, hi = attr(tag, 'min'), attr(tag, 'max')
        if lo is None and hi is None and kind == 'melee' and attr(tag, 'skill') and attr(tag, 'attack'):
            hi = str(-melee_max(int(attr(tag, 'skill')), int(attr(tag, 'attack'))))
            lo = '0'
        if lo is None or hi is None:
            continue
        out.append((kind, int(lo), int(hi)))
    return out


def xml_level(text):
    m = re.search(r'<level\s+min="(\d+)"\s+max="(\d+)"', text)
    return (int(m.group(1)) + int(m.group(2))) // 2 if m and int(m.group(1)) and int(m.group(2)) else 0


def lua_attacks(text):
    block = re.search(r'monster\.attacks = \{(.*?)\n\}', text, re.S)
    out = []
    for line in (block.group(1) if block else '').split('\n'):
        m = re.search(r'name ?= ?"([^"]*)"', line)
        if not m:
            continue
        name = m.group(1)
        t = re.search(r'type = (COMBAT_\w+)', line)
        if name.lower() == 'melee':
            kind = 'melee'
        elif name.lower() == 'combat':
            kind = 'melee' if t and t.group(1) == 'COMBAT_PHYSICALDAMAGE' else 'elem'
        else:
            kind = classify(name)
        lo = re.search(r'minDamage ?= ?(-?\d+)', line)
        hi = re.search(r'maxDamage ?= ?(-?\d+)', line)
        if kind and lo and hi:
            out.append((kind, int(lo.group(1)), int(hi.group(1))))
    return out


def lua_level(text):
    lo, hi = re.search(r'minLevel ?= ?(\d+)', text), re.search(r'maxLevel ?= ?(\d+)', text)
    return (int(lo.group(1)) + int(hi.group(1))) // 2 if lo and hi and int(lo.group(1)) and int(hi.group(1)) else 0


def indexes(data):
    """({lower name: xml path}, {lower name: lua path}) of the installed monster folder"""
    base = os.path.join(data, 'monster')
    xml = {}
    for m in re.finditer(r'<monster\s+name="([^"]+)"\s+file="([^"]+)"', read(os.path.join(base, 'monsters.xml'))):
        xml[m.group(1).lower()] = os.path.join(base, m.group(2))
    lua = {}
    for root, _, files in os.walk(os.path.join(base, 'lua')):
        for f in sorted(files):
            if f.endswith('.lua'):
                m = re.search(r'createMonsterType\("([^"]+)"\)', read(os.path.join(root, f)))
                if m:
                    lua[m.group(1).lower()] = os.path.join(root, f)
    return xml, lua


def pool_rows(text=None):
    txt = (text if text is not None else read(POOL)).split('\tbosses = ')[0]
    return [(m.group(1), int(m.group(2)), int(m.group(3))) for m in
            re.finditer(r'\{name = "([^"]+)", level = (\d+), exp = \d+, health = (\d+)', txt)]


def min_health():
    m = re.search(r'minPoolHealth = (\d+)', read(RIFT))
    return int(m.group(1)) if m else 100


def rows_of(data, pool=None, floor_health=None):
    xml, lua = indexes(data)
    floor_health = floor_health if floor_health is not None else min_health()
    out = []
    for name, level, health in (pool if pool is not None else pool_rows()):
        if health < floor_health:
            continue
        k = name.lower()
        if k in xml and read(xml[k]):
            t = read(xml[k])
            atk, ml = xml_attacks(t), xml_level(t)
        elif k in lua and read(lua[k]):
            t = read(lua[k])
            atk, ml = lua_attacks(t), lua_level(t)
        else:
            continue
        b = best(atk)
        if not b:
            continue
        mm, em = b.get('melee', (0, 0)), b.get('elem', (0, 0))
        out.append([name, level, ml, mm[0], round(mm[1], 1), em[0], round(em[1], 1)])
    return out


def to_csv(rows):
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(COLS)
    for r in sorted(rows, key=lambda r: (r[1], r[0])):
        w.writerow(r)
    return buf.getvalue()


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    text = to_csv(rows_of(args[0]))
    if '--check' in argv:
        same = read(OUT) == text
        print('guardian_hits.csv: %s' % ('up to date' if same else 'differs from the installed server'))
        return 0 if same else 1
    with open(OUT, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    print('wrote %s (%d rows)' % (OUT, text.count('\n') - 1))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
