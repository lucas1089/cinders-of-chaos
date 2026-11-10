#!/usr/bin/env python3
"""The resistance data of the monsters, in files (idempotent). install_all.py step `monsterresists` (O462).

usage: python3 -I patch_monster_resists.py DATA_DIR [--check] [--dry-run] [--quiet]

DATA_DIR is the server's data folder. Every monster file under DATA_DIR/monster (XML and Lua) is read, except the pets
(monsters/chaos/pets: allies, never a target) and the monsters the physical rule leaves alone (not attackable, or immune
to every damage type: event and quest creatures that are invulnerable by design; tools/monster_physical_resist.py).
The rule (O462: a normal monster never passes 40, a boss never passes 75):

  * a NORMAL monster: every positive element percent is at most 40; an immunity to a damage type (XML <immunity fire="1"/>
    or name="fire", Lua {type = "fire", combat = true}, or a percent of 100 and more) becomes 40
  * a BOSS (the monster flag isboss, Lua isBoss = true): the same with 75
  * the scaled high-level set that has a flat 30 on all seven types (physical, fire, ice, energy, earth, death, holy):
    three of them keep 30, chosen by a stable hash of the monster's name (SHA-256 of "name:type", lower case: the same on
    every run and machine), the other four become 0
  * weaknesses (negative percents) stay. Life drain and mana drain are no element for this rule.
Bleeding stays immune where physical was (as monster_physical_resist.py). Runtime: monster_defence.lua caps the
resistance at defence_config.lua resistCap (75) whatever the file says, and adds the rank bonus of the elite ranks.

--check    changes nothing, prints each file that would change, exit 1 when any would (CI, tools/ci/check_content.py)
--dry-run  changes nothing, prints what a run would change (exit 0)
Our own monsters in the repository go through the same functions in tools/tune_monsters.py (the owner of those files);
this tool is the install step for the base server's monsters and a second guard for ours. Test: patch_monster_resists_test.py.
"""
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
import monster_physical_resist as phys  # noqa: E402

CAP_NORMAL = 40
CAP_BOSS = 75
FLAT_VALUE = 30
FLAT_KEEP = 3
SEVEN = ('physical', 'fire', 'ice', 'energy', 'earth', 'death', 'holy')
PETS = 'pets'

# XML element attribute -> damage type; lifedrain and manadrain are left out on purpose
XML_ATTR = {'physicalPercent': 'physical', 'firePercent': 'fire', 'icePercent': 'ice', 'energyPercent': 'energy',
            'earthPercent': 'earth', 'poisonPercent': 'earth', 'deathPercent': 'death', 'holyPercent': 'holy',
            'drownPercent': 'drown', 'waterPercent': 'water', 'arcanePercent': 'arcane'}
# damage immunity name (XML attribute / Lua type) -> element attribute written for it
IMMUNITY = {'physical': 'physicalPercent', 'energy': 'energyPercent', 'earth': 'earthPercent', 'poison': 'earthPercent',
            'fire': 'firePercent', 'drown': 'drownPercent', 'ice': 'icePercent', 'holy': 'holyPercent',
            'death': 'deathPercent'}
LUA_TYPE = {'PHYSICAL': 'physical', 'ENERGY': 'energy', 'EARTH': 'earth', 'FIRE': 'fire', 'ICE': 'ice', 'HOLY': 'holy',
            'DEATH': 'death', 'DROWN': 'drown', 'WATER': 'water', 'ARCANE': 'arcane'}
LUA_CONST = {v: 'COMBAT_%sDAMAGE' % k for k, v in LUA_TYPE.items()}

TRUE = r'(?:1|true|yes)'
_XML_NAME = re.compile(r'<monster\b[^>]*?\sname\s*=\s*"([^"]*)"')
_XML_BOSS = re.compile(r'<flag\s+isboss\s*=\s*"' + TRUE + '"', re.I)
_XML_ROW = re.compile(r'(<element\s+)(\w+Percent)(\s*=\s*")(-?\d+)(")')
_XML_IMM = re.compile(r'([ \t]*)(<immunity\b[^>]*?/?>)([ \t]*(?:\r?\n)?)')
_LUA_NAME = re.compile(r'(?:createMonsterType|MonsterType)\(\s*"([^"]*)"\s*\)')
_LUA_BOSS = re.compile(r'\bisBoss\s*=\s*true\b')
_LUA_ROW = re.compile(r'(\{\s*type\s*=\s*)(COMBAT_(?:PHYSICAL|ENERGY|EARTH|FIRE|ICE|HOLY|DEATH|DROWN|WATER|ARCANE)DAMAGE)'
                      r'(\s*,\s*percent\s*=\s*)(-?\d+)')
_LUA_ENTRY = re.compile(r'\{[^{}]*\}')


class Counts(dict):
    """what a run changed, by rule"""
    KEYS = ('capped', 'immunity', 'flat30')

    def __init__(self):
        super().__init__((k, 0) for k in self.KEYS)

    def add(self, other):
        for k in self.KEYS:
            self[k] += other[k]


def cap_for(boss):
    return CAP_BOSS if boss else CAP_NORMAL


def keep_types(name):
    """the three of the seven types a flat-30 monster keeps: the first three by SHA-256 of "name:type" (name in lower case)"""
    return sorted(SEVEN, key=lambda t: hashlib.sha256(('%s:%s' % (name.lower(), t)).encode('utf-8')).hexdigest())[:FLAT_KEEP]


def _strip_xml_comments(text):
    return re.sub(r'<!--.*?-->', '', text, flags=re.S)


def xml_is_boss(text):
    return bool(_XML_BOSS.search(_strip_xml_comments(text)))


def xml(text, name=None):
    """(new text, Counts, notes) for one monster XML. notes: one short string per change"""
    counts, notes = Counts(), []
    if phys.xml_left_alone(text):
        return text, counts, notes
    m = _XML_NAME.search(text)
    name = name or (m.group(1) if m else '')
    boss = xml_is_boss(text)
    cap = cap_for(boss)
    new = text
    # the flat 30 on the seven types
    rows = {}
    for r in _XML_ROW.finditer(_strip_xml_comments(new)):
        if r.group(2) in XML_ATTR:
            rows[XML_ATTR[r.group(2)]] = int(r.group(4))
    if all(rows.get(t) == FLAT_VALUE for t in SEVEN):
        keep = keep_types(name)

        def flat(r):
            t = XML_ATTR.get(r.group(2))
            if t in SEVEN and t not in keep and int(r.group(4)) == FLAT_VALUE:
                return r.group(1) + r.group(2) + r.group(3) + '0' + r.group(5)
            return r.group(0)
        new = _XML_ROW.sub(flat, new)
        counts['flat30'] += 1
        notes.append('flat 30 on seven types: keeps %s' % ', '.join(keep))
    # damage immunities -> the cap
    immune = []

    def imm(r):
        lead, tag, tail = r.group(1), r.group(2), r.group(3)
        out = tag
        for key in IMMUNITY:
            a = re.compile(r'\s%s\s*=\s*"%s"' % (key, TRUE), re.I)
            nm = re.compile(r'(\sname\s*=\s*")%s(")' % key, re.I)
            if key == 'physical':
                if a.search(out) or nm.search(out):
                    immune.append(key)
                    out = a.sub(lambda x: re.sub(r'physical', 'bleed', x.group(0), flags=re.I), out)
                    out = nm.sub(lambda x: x.group(1) + 'bleed' + x.group(2), out)
                continue
            if a.search(out):
                immune.append(key)
                out = a.sub('', out)
            elif nm.search(out):
                immune.append(key)
                out = re.sub(r'\sname\s*=\s*"%s"' % key, '', out, flags=re.I)
        if out == tag:
            return r.group(0)
        if not re.search(r'\s\w+\s*=', out):
            return ''  # a tag with nothing left goes with its line
        return lead + out + tail
    new = _XML_IMM.sub(imm, new)
    if immune:
        new = re.sub(r'[ \t]*<immunities>\s*</immunities>[ \t]*(?:\r?\n)?', '', new)
    # percents over the cap, and the immunities as rows of the cap
    immune_types = {XML_ATTR[IMMUNITY[k]] for k in immune}
    done = set()

    def over(r):
        t = XML_ATTR.get(r.group(2))
        if t is None:
            return r.group(0)
        v = int(r.group(4))
        if t in immune_types:
            done.add(t)
            if v != cap:
                notes.append('%s %d -> %d (immunity)' % (t, v, cap))
        elif v >= 100:
            counts['immunity'] += 1
            notes.append('%s %d -> %d (immunity)' % (t, v, cap))
        elif v > cap:
            counts['capped'] += 1
            notes.append('%s %d -> %d' % (t, v, cap))
        else:
            return r.group(0)
        return r.group(1) + r.group(2) + r.group(3) + str(cap) + r.group(5)
    new = _XML_ROW.sub(over, new)
    for key in dict.fromkeys(immune):
        attr = IMMUNITY[key]
        counts['immunity'] += 1
        if XML_ATTR[attr] in done:
            continue
        notes.append('%s immunity -> %d' % (XML_ATTR[attr], cap))
        new = _xml_add_row(new, attr, cap)
    return (new, counts, notes) if new != text else (text, Counts(), [])


def _xml_add_row(text, attr, value):
    row = '<element %s="%d"/>' % (attr, value)
    el = re.search(r'([ \t]*)<elements>[ \t]*\r?\n', text)
    if el:
        return text[:el.end()] + '%s\t%s\n' % (el.group(1), row) + text[el.end():]
    block = '\t<elements>\n\t\t%s\n\t</elements>\n' % row
    for b in ('immunities', 'summons', 'voices', 'loot'):
        n = re.search(r'[ \t]*<%s\b' % b, text)
        if n:
            return text[:n.start()] + block + text[n.start():]
    n = text.rindex('</monster>')
    return text[:n] + block + text[n:]


def lua_is_boss(text):
    return bool(_LUA_BOSS.search(re.sub(r'--[^\n]*', '', text)))


def lua(text, name=None):
    """(new text, Counts, notes) for one Lua monster file"""
    counts, notes = Counts(), []
    if phys.lua_left_alone(text):
        return text, counts, notes
    m = _LUA_NAME.search(text)
    name = name or (m.group(1) if m else '')
    boss = lua_is_boss(text)
    cap = cap_for(boss)
    new = text
    rows = {}
    for r in _LUA_ROW.finditer(re.sub(r'--[^\n]*', '', new)):
        rows[LUA_TYPE[r.group(2)[len('COMBAT_'):-len('DAMAGE')]]] = int(r.group(4))
    if all(rows.get(t) == FLAT_VALUE for t in SEVEN):
        keep = keep_types(name)

        def flat(r):
            t = LUA_TYPE[r.group(2)[len('COMBAT_'):-len('DAMAGE')]]
            if t in SEVEN and t not in keep and int(r.group(4)) == FLAT_VALUE:
                return r.group(1) + r.group(2) + r.group(3) + '0'
            return r.group(0)
        new = _LUA_ROW.sub(flat, new)
        counts['flat30'] += 1
        notes.append('flat 30 on seven types: keeps %s' % ', '.join(keep))
    # damage immunities (combat = true) -> combat = false, and the cap as a row
    immune = []

    def entry(r):
        e = r.group(0)
        t = re.search(r'\btype\s*=\s*"(\w+)"', e)
        if t and t.group(1) in IMMUNITY and re.search(r'\bcombat\s*=\s*true\b', e):
            immune.append(t.group(1))
            return re.sub(r'\bcombat\s*=\s*true\b', 'combat = false', e)
        return e
    block = re.search(r'monster\.immunities\s*=\s*\{', new)
    if block:
        end = _matching_brace(new, block.end() - 1)
        new = new[:block.start()] + _LUA_ENTRY.sub(entry, new[block.start():end + 1]) + new[end + 1:]
    done = set()
    immune_types = {XML_ATTR[IMMUNITY[i]] for i in immune}

    def over(r):
        t = LUA_TYPE[r.group(2)[len('COMBAT_'):-len('DAMAGE')]]
        v = int(r.group(4))
        if t in immune_types:
            done.add(t)
            if v != cap:
                notes.append('%s %d -> %d (immunity)' % (t, v, cap))
        elif v >= 100:
            counts['immunity'] += 1
            notes.append('%s %d -> %d (immunity)' % (t, v, cap))
        elif v > cap:
            counts['capped'] += 1
            notes.append('%s %d -> %d' % (t, v, cap))
        else:
            return r.group(0)
        return r.group(1) + r.group(2) + r.group(3) + str(cap)
    new = _LUA_ROW.sub(over, new)
    for key in dict.fromkeys(immune):
        t = XML_ATTR[IMMUNITY[key]]
        counts['immunity'] += 1
        if t in done:
            continue
        notes.append('%s immunity -> %d' % (t, cap))
        new = _lua_add_row(new, LUA_CONST[t], cap)
    return (new, counts, notes) if new != text else (text, Counts(), [])


def _matching_brace(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return i
    return len(text) - 1


def _lua_add_row(text, const, value):
    row = '\t{type = %s, percent = %d},\n' % (const, value)
    el = re.search(r'monster\.elements\s*=\s*\{[ \t]*\r?\n', text)
    if el:
        return text[:el.end()] + row + text[el.end():]
    n = re.search(r'monster\.immunities\s*=|mType:register', text)
    pos = n.start() if n else len(text)
    return text[:pos] + 'monster.elements = {\n' + row + '}\n\n' + text[pos:]


def files(data):
    """(path, fix function) of every monster file under DATA_DIR/monster, pets left out"""
    out = []
    root = os.path.join(data, 'monster')
    for folder, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d != PETS)
        for n in sorted(names):
            p = os.path.join(folder, n)
            if n.endswith('.xml') and n != 'monsters.xml':
                out.append((p, xml))
            elif n.endswith('.lua'):
                out.append((p, lua))
    return out


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    check, dry, quiet = '--check' in argv, '--dry-run' in argv, '--quiet' in argv
    if len(args) != 1 or not os.path.isdir(os.path.join(args[0], 'monster')):
        print(__doc__)
        return 2
    total, changed = Counts(), 0
    for path, fix in files(args[0]):
        text = read(path)
        if 'Percent' not in text and 'mmunit' not in text and 'percent' not in text:
            continue
        new, counts, notes = fix(text)
        if new == text:
            continue
        changed += 1
        total.add(counts)
        rel = os.path.relpath(path, args[0]).replace(os.sep, '/')
        if check:
            print('not up to date (monster resistances):', rel)
        elif not quiet:
            print(('would change ' if dry else 'changed ') + rel + ': ' + '; '.join(notes))
        if not (check or dry):
            write(path, new)
    print('monster resistances: %d file(s) %s; capped %d, immunities %d, flat 30 sets %d' % (
        changed, 'to change' if (check or dry) else 'changed', total['capped'], total['immunity'], total['flat30']))
    return 1 if (check and changed) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
