#!/usr/bin/env python3
"""The flat armour and defence of the monster files, capped by a level rule (idempotent). install_all.py step `monsterflat` (O505).

usage: python3 -I patch_monster_flat_defence.py DATA_DIR [--check] [--dry-run] [--quiet]

DATA_DIR is the server's data folder. Every monster file under DATA_DIR/monster (XML and Lua) is read, except the pets
(monsters/chaos/pets: allies, never a target) and the test dummies (monsters/zo). Owner, 2026-11-11 (O501 report, translated): "You can
fix these 3 things of the auto attack." The first of them: the XML `armor` and `defense` of the base monsters cut a hit in the engine
before any Lua runs (Creature::blockHit, engine creature.cpp): `defense` takes uniform(defense / 2, defense) off a hit (a melee hit; a
launcher never meets it) once a second, `armor` takes uniform(armor / 2, armor - 1 - armor % 2) off every weapon hit (armor 1 to 3
takes 1), and a hit that falls to 0 never reaches a Lua event. A stock hunt monster of level 20 has 15 and 15: half of a level 20
Warrior's attacks were blocked outright and the rest arrived at half of their roll (README "Monster defence (O462)", "Weapon hits
(O501)", "Flat armour, weapon spells and the Monk's fist (O505)").

The rule: the flat armour and defence stay as a small, level-true bite and not a wall. For a monster of level L the two together take
at most `flatShare` percent (normal 10, boss 20) of the median engine ROLL of an auto attack at that level (the 12 armoured classes that
are not the fist line, before any armour: monster_defence_config.lua `flatRollCurve`, derived by tools/defence_curve.py). The cap is one
integer c for both numbers: the largest c where armour_bite(c) + defence_bite(c), the mean the engine takes off, is at most the share of
the roll. A value above its cap is lowered to the cap; a value at or below it is never touched (a later, lower cap still applies; a run
on a file that is done changes nothing). A boss is the XML flag isboss, a Lua boss flag, or a monster of the `bosses` list of
bounty_pool.lua; it keeps twice the share, because the layer sizes its armour for a boss at twice the normal share too.

The level of a monster is the one the damage layer uses (monster_defence.lua levelOf: the hunting level): the middle of the <level>
range of a level-scaled file (engine patch 0082) when it is its real level, else the level of bounty_pool.lua (DATA_DIR/scripts/chaos),
else the estimate from its experience and health of ChaosItemMods.estimateMonsterLevel.

--check    changes nothing, prints each file that would change, exit 1 when any would (CI, tools/ci/check_content.py)
--dry-run  changes nothing, prints what a run would change (exit 0)
Our own monsters in the repository go through the same functions in tools/tune_monsters.py; this tool is the install step for the
base server's monsters and a second guard for ours. Test: patch_monster_flat_defence_test.py. The numbers: monster_defence_config.lua
`flatShare` and `flatRollCurve` (derived and held by tools/defence_curve.py --check, rule G5).
"""
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
CONFIG = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'monster_defence_config.lua')
POOL = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'bounty_pool.lua')
SKIP_DIRS = ('pets', 'zo')

_XML_NAME = re.compile(r'<monster\b[^>]*?\sname\s*=\s*"([^"]*)"')
_XML_BOSS = re.compile(r'<flag\s+isboss\s*=\s*"(?:1|true|yes)"', re.I)
_XML_LEVEL = re.compile(r'<level\s+min\s*=\s*"(\d+)"\s+max\s*=\s*"(\d+)"')
_XML_EXP = re.compile(r'<monster\b[^>]*?\sexperience\s*=\s*"(\d+)"')
_XML_HP = re.compile(r'<health\s+now\s*=\s*"\d+"\s+max\s*=\s*"(\d+)"')
_XML_DEF = re.compile(r'<defenses\b[^>]*>')
_LUA_NAME = re.compile(r'(?:createMonsterType|MonsterType)\(\s*"([^"]*)"\s*\)')
_LUA_BOSS = re.compile(r'\b(?:isBoss|rewardBoss)\s*=\s*true\b')
_LUA_LEVEL = re.compile(r'minLevel\s*=\s*(\d+)\s*,\s*maxLevel\s*=\s*(\d+)')
_LUA_EXP = re.compile(r'monster\.experience\s*=\s*(\d+)')
_LUA_HP = re.compile(r'monster\.maxHealth\s*=\s*(\d+)|monster\.health\s*=\s*(\d+)')
_LUA_DEF = re.compile(r'(monster\.defenses\s*=\s*\{)([^{}]*)(\})')


# ---- what the engine takes off (Creature::blockHit, creature.cpp) -------------------------------------------------------------
def armour_bite(a):
    """the mean the engine takes off a weapon hit for XML armor a: uniform_random(a / 2, a - (a % 2 + 1)) for a over 3, 1 for 1 to 3"""
    if a <= 0:
        return 0.0
    if a <= 3:
        return 1.0
    return (a // 2 + a - (a % 2 + 1)) / 2.0


def defence_bite(d):
    """the mean the engine takes off a melee hit for XML defense d: uniform_random(d / 2, d), once a second (a hit every second or slower
    meets it every time)"""
    return (d // 2 + d) / 2.0 if d > 0 else 0.0


def hit_at(rows, level):
    """a straight line in log level and log value between two rows (level, value), the slope of the last two rows beyond the ends (the
    rule of monster_defence_core.lua curveAt)"""
    level = max(1, level)
    a, b = rows[0], rows[1]
    for i in range(1, len(rows)):
        a, b = rows[i - 1], rows[i]
        if level <= b[0]:
            break
    e = (math.log(b[1]) - math.log(a[1])) / (math.log(b[0]) - math.log(a[0]))
    return a[1] * (level / float(a[0])) ** e


def read_config(path=CONFIG):
    """{'share': {'normal': 10.0, 'boss': 20.0}, 'roll': [(level, roll)]} from monster_defence_config.lua"""
    with open(path, encoding='utf-8') as f:
        text = f.read()
    m = re.search(r'flatShare\s*=\s*\{([^}]*)\}', text)
    share = {k: float(v) for k, v in re.findall(r'(\w+)\s*=\s*([0-9.]+)', m.group(1))}
    block = text.split('flatRollCurve = {', 1)[1].split('\n\t}', 1)[0]
    roll = [(int(a), int(b)) for a, b in re.findall(r'\{level = (\d+), hit = (\d+)\}', block)]
    return {'share': share, 'roll': roll}


_CAPS = {}


def cap_for(level, boss, cfg):
    """the cap c of a monster of this level (hunting level) for armor and defense: the largest integer where the mean bite of both together
    is at most flatShare percent of the median roll of the level"""
    key = (id(cfg), int(level), bool(boss))
    if key in _CAPS:
        return _CAPS[key]
    budget = cfg['share']['boss' if boss else 'normal'] / 100.0 * hit_at(cfg['roll'], level)
    c = 0
    while armour_bite(c + 1) + defence_bite(c + 1) <= budget:
        c += 1
        if c > 100000:
            break
    _CAPS[key] = c
    return c


# ---- the level of a monster ------------------------------------------------------------------------------------------------
def estimate_level(experience, health):
    """ChaosItemMods.estimateMonsterLevel: the hunting level from experience and health (tools/gen_bounty_pool.py estimate_level)"""
    by_exp = 1.6 * math.sqrt(max(experience or 0, 1))
    by_hp = (health or 0) / 60.0
    return max(1, int(math.floor(max(by_exp, min(by_hp, by_exp * 1.5)) + 0.5)))


class Pool(object):
    """bounty_pool.lua: name (lower case) -> (level, exp, health, is boss)"""

    def __init__(self, path=None):
        self.rows = {}
        if path and os.path.isfile(path):
            with open(path, encoding='utf-8', errors='replace') as f:
                text = f.read()
            hunt, _, bosses = text.partition('\tbosses = ')
            for part, boss in ((hunt, False), (bosses, True)):
                for m in re.finditer(r'\{name = "([^"]+)", level = (\d+), exp = (\d+), health = (\d+)', part):
                    self.rows[m.group(1).lower()] = (int(m.group(2)), int(m.group(3)), int(m.group(4)), boss)

    def level_of(self, facts):
        """(level, boss) of a monster: facts {name, boss, own (level range middle or 0), exp, hp}"""
        row = self.rows.get(facts['name'].lower())
        boss = facts['boss'] or bool(row and row[3])
        own = facts['own']
        if row:
            # a level range of 1 to 10 next to the stats of a level 150 monster (loot.lua L.ownLevel): the pool level that equals the
            # estimate of the type's experience and health is the level of a type that is NOT level-scaled
            if own <= 0 or estimate_level(row[1], row[2]) == row[0]:
                return row[0], boss
            return own, boss
        if own > 0:
            return own, boss
        return estimate_level(facts['exp'], facts['hp']), boss


def facts_xml(text):
    clean = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    m = _XML_NAME.search(clean)
    lv = _XML_LEVEL.search(clean)
    ex, hp = _XML_EXP.search(clean), _XML_HP.search(clean)
    own = (int(lv.group(1)) + int(lv.group(2))) // 2 if lv and int(lv.group(2)) > 0 else 0
    return {'name': m.group(1) if m else '', 'boss': bool(_XML_BOSS.search(clean)), 'own': own,
            'exp': int(ex.group(1)) if ex else 0, 'hp': int(hp.group(1)) if hp else 0}


def facts_lua(text):
    clean = re.sub(r'--[^\n]*', '', text)
    m = _LUA_NAME.search(clean)
    lv = _LUA_LEVEL.search(clean)
    ex, hp = _LUA_EXP.search(clean), _LUA_HP.search(clean)
    own = (int(lv.group(1)) + int(lv.group(2))) // 2 if lv and int(lv.group(2)) > 0 else 0
    return {'name': m.group(1) if m else '', 'boss': bool(_LUA_BOSS.search(clean)), 'own': own,
            'exp': int(ex.group(1)) if ex else 0, 'hp': int(hp.group(1) or hp.group(2)) if hp else 0}


# ---- the files ---------------------------------------------------------------------------------------------------------------
class Counts(dict):
    KEYS = ('files', 'armor', 'defense', 'left')

    def __init__(self):
        super().__init__((k, 0) for k in self.KEYS)

    def add(self, other):
        for k in self.KEYS:
            self[k] += other[k]


def _lower(value, cap):
    return cap if value > cap else value


def xml(text, pool, cfg, facts=None):
    """(new text, Counts, notes) for one monster XML: armor and defense of <defenses> lowered to the cap of the monster's level"""
    counts, notes = Counts(), []
    d = _XML_DEF.search(text)
    if not d:
        return text, counts, notes
    facts = facts or facts_xml(text)
    level, boss = pool.level_of(facts)
    cap = cap_for(level, boss, cfg)
    tag = d.group(0)
    new_tag = tag
    for attr in ('armor', 'defense'):
        m = re.search(r'(\s%s\s*=\s*")(\d+)(")' % attr, new_tag)
        if m and int(m.group(2)) > cap:
            notes.append('%s %s -> %d' % (attr, m.group(2), cap))
            counts[attr] += 1
            new_tag = new_tag[:m.start(2)] + str(cap) + new_tag[m.end(2):]
    if new_tag == tag:
        counts['left'] = 1
        return text, counts, notes
    counts['files'] = 1
    return text[:d.start()] + new_tag + text[d.end():], counts, notes


def lua(text, pool, cfg, facts=None):
    """(new text, Counts, notes) for one Lua monster file: armor and defense of monster.defenses"""
    counts, notes = Counts(), []
    d = _LUA_DEF.search(text)
    if not d:
        return text, counts, notes
    facts = facts or facts_lua(text)
    level, boss = pool.level_of(facts)
    cap = cap_for(level, boss, cfg)
    body = d.group(2)
    new_body = body
    for attr in ('armor', 'defense'):
        m = re.search(r'(\b%s\s*=\s*)(\d+)' % attr, new_body)
        if m and int(m.group(2)) > cap:
            notes.append('%s %s -> %d' % (attr, m.group(2), cap))
            counts[attr] += 1
            new_body = new_body[:m.start(2)] + str(cap) + new_body[m.end(2):]
    if new_body == body:
        counts['left'] = 1
        return text, counts, notes
    counts['files'] = 1
    return text[:d.start(2)] + new_body + text[d.end(2):], counts, notes


def files(data):
    """(path, fix function) of every monster file under DATA_DIR/monster, pets and test dummies left out"""
    out = []
    root = os.path.join(data, 'monster')
    for folder, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for n in sorted(names):
            p = os.path.join(folder, n)
            if n.endswith('.xml') and n != 'monsters.xml':
                out.append((p, xml))
            elif n.endswith('.lua') and not n.startswith('#'):
                out.append((p, lua))
    return out


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def load(data):
    """(Pool, config) of a server data folder: its installed bounty pool and config when there are (the install step `files` copies
    them), else the repository's"""
    chaos = os.path.join(data, 'scripts', 'chaos')
    pool = os.path.join(chaos, 'bounty_pool.lua')
    cfg = os.path.join(chaos, 'monster_defence_config.lua')
    return Pool(pool if os.path.isfile(pool) else POOL), read_config(cfg if os.path.isfile(cfg) else CONFIG)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    check, dry, quiet = '--check' in argv, '--dry-run' in argv, '--quiet' in argv
    if len(args) != 1 or not os.path.isdir(os.path.join(args[0], 'monster')):
        print(__doc__)
        return 2
    pool, cfg = load(args[0])
    total, changed = Counts(), 0
    for path, fix in files(args[0]):
        text = read(path)
        if 'armor' not in text:
            continue
        new, counts, notes = fix(text, pool, cfg)
        total.add(counts)
        if new == text:
            continue
        changed += 1
        rel = os.path.relpath(path, args[0]).replace(os.sep, '/')
        if check:
            print('not up to date (monster flat defence):', rel)
        elif not quiet:
            print(('would change ' if dry else 'changed ') + rel + ': ' + '; '.join(notes))
        if not (check or dry):
            write(path, new)
    print('monster flat defence: %d file(s) %s; armor lowered %d, defense lowered %d, left alone %d' % (
        changed, 'to change' if (check or dry) else 'changed', total['armor'], total['defense'], total['left']))
    return 1 if (check and changed) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
