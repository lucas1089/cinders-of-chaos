#!/usr/bin/env python3
"""Test of patch_spell_cap.py (the 15-spell cap, owner 2026-10-20) and of the cap itself.
  * patch(): classes a spell lost leave its <vocation> lines, a spell no class keeps becomes a marked comment (or the
    monster-only form when a monster names it, monster_spells.py), the
    Chaos block and comments stay, a second run changes nothing, --dry-run writes nothing;
  * the repo data: every class and ascension has at most 15 spells of its own, counted from
    data/spells/chaos/spells_chaos.xml, data/spells/stock_spells.csv (stock attack and healing spells as installed)
    and CAP (the stock support spells the classes keep), without UNIVERSAL and OUTSIDE_CAP; the counts are pinned (docs/CLASSES.md
    "Spell cap": update both when a kit changes).
Run: python3 -I server/tools/patch_spell_cap_test.py"""
import csv
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_spell_cap as C  # noqa: E402

SPELLS = os.path.join(HERE, '..', 'data', 'spells')
fails = []


def check(c, what):
    if not c:
        fails.append(what)
        print('FAIL ' + what)


def spell(name, script, sid, vocs):
    body = ''.join('\t\t<vocation name="%s" />\n' % v for v in vocs)
    return '\t<instant group="attack" spellid="%d" name="%s" words="x %d" level="10" script="%s">\n%s\t</instant>\n' % (
        sid, name, sid, script, body)


# ------------------------------------------------------------------ patch() on a small spells.xml
XML = '<spells>\n'
XML += spell('Lance', 'attack/grand_death_beam.lua', 260, ['Mystic', 'Elementalist'])          # retired
XML += spell('Minor', 'healing/light_healing.lua', 1, ['Warrior', 'Mystic', 'Necromancer'])    # Warrior leaves
XML += spell('Spark', "attack/apprentice's_strike.lua", 169, ['Mystic', 'Elementalist'])       # not in CAP
XML += '\t<!-- an earlier comment <instant script="attack/fire_wave.lua"> -->\n'
XML += '\t<!-- BEGIN chaos spells (x) -->\n' + spell('Chaos Lance', 'attack/grand_death_beam.lua', 250, ['Mystic'])
XML += '\t<!-- END chaos spells -->\n</spells>\n'
new, removed, retired, kept = C.patch(XML)
check(retired == 1 and kept == 0 and new.count(C.MARK) == 1, 'Lance retired once: %d' % retired)
check('<!-- ' + C.MARK + '<instant group="attack" spellid="260" name="Lance"' in new, 'the retired tag kept in the comment')
check(removed == 1, 'one class entry removed: %d' % removed)
minor = re.search(r'<instant[^>]*name="Minor".*?</instant>', new, re.S).group(0)
check('"Warrior"' not in minor and '"Mystic"' in minor and '"Necromancer"' in minor, 'Minor: the Warrior left')
check(spell('Spark', "attack/apprentice's_strike.lua", 169, ['Mystic', 'Elementalist']) in new, 'a spell not in CAP stays')
check(new[new.index('BEGIN chaos'):].count(C.MARK) == 0 and 'name="Chaos Lance"' in new, 'the Chaos block is untouched')
check(C.patch(new) == (new, 0, 0, 0), 'a second run changes nothing')
# a monster names Lance: monster-only form instead of the comment, also from the comment of an earlier run
# (monster_spells_test.py tests the form and the repair in depth)
kept_new, _, r2, k2 = C.patch(XML, {'lance'})
check(r2 == 0 and k2 == 1 and 'name="Lance" words="###chaos grand_death_beam"' in kept_new and C.MARK not in kept_new,
      'a spell a monster names is kept for monsters')
check(C.patch(new, {'lance'})[0] == kept_new, 'the comment of an earlier run comes back in the monster-only form')
with tempfile.TemporaryDirectory() as tmp:
    p = os.path.join(tmp, 'spells')
    os.makedirs(p)
    open(os.path.join(p, 'spells.xml'), 'w', newline='').write(XML)
    tool = os.path.join(HERE, 'patch_spell_cap.py')
    r = subprocess.run([sys.executable, '-I', tool, tmp, '--dry-run'], capture_output=True, text=True)
    check(r.returncode == 0 and open(os.path.join(p, 'spells.xml')).read() == XML, 'dry run writes nothing')
    r = subprocess.run([sys.executable, '-I', tool, tmp], capture_output=True, text=True)
    check('1 spells retired' in r.stdout and open(os.path.join(p, 'spells.xml')).read() == new, 'run: ' + r.stdout)
    r = subprocess.run([sys.executable, '-I', tool, tmp], capture_output=True, text=True)
    check('nothing to change' in r.stdout, 'second run: ' + r.stdout)

# ------------------------------------------------------------------ the cap on the repo data
ORDER = ['Warrior', 'Juggernaut', 'Berserker', 'Ranger', 'Deadeye', 'Beastmaster', 'Mystic', 'Elementalist',
         'Illusionist', 'Thief', 'Ninja', 'Samurai', 'Monk', 'Shadowfist', 'Iron Sage', 'Necromancer', 'Lich',
         'Bone Lord', 'Templar', 'Inquisitor', 'Sentinel']
# spells of its own per class after the cap (docs/CLASSES.md "Spell cap")
PINNED = {'Warrior': 15, 'Juggernaut': 15, 'Berserker': 15, 'Ranger': 15, 'Deadeye': 15, 'Beastmaster': 14,
          'Mystic': 15, 'Elementalist': 14, 'Illusionist': 15, 'Thief': 10, 'Ninja': 13, 'Samurai': 13, 'Monk': 7,
          'Shadowfist': 10, 'Iron Sage': 11, 'Necromancer': 11, 'Lich': 13, 'Bone Lord': 13, 'Templar': 4,
          'Inquisitor': 6, 'Sentinel': 7}
kit = {v: set() for v in ORDER}
xml = re.sub(r'<!--.*?-->', '', open(os.path.join(SPELLS, 'chaos', 'spells_chaos.xml'), encoding='utf-8').read(), flags=re.S)
for m in re.finditer(r'<instant ([^>]*)>(.*?)</instant>', xml, re.S):
    name = re.search(r'name="([^"]+)"', m.group(1)).group(1)
    for v in re.findall(r'<vocation name="([^"]+)"', m.group(2)):
        kit[v].add(name)
stock = list(csv.DictReader(open(os.path.join(SPELLS, 'stock_spells.csv'), encoding='utf-8')))
for r in stock:
    for v in r['vocations'].split(';'):
        kit[v].add(r['name'])
stock_names = {r['name'] for r in stock}
for script, (sid, name, keep) in C.CAP.items():
    for v in keep:
        kit[v].add(name)
    if not keep:
        check(name not in stock_names, name + ': retired, not in stock_spells.csv')
for v in ORDER:
    own = kit[v] - set(C.UNIVERSAL) - set(C.OUTSIDE_CAP)
    check(len(own) <= C.MAX_SPELLS, '%s: %d spells (at most %d)' % (v, len(own), C.MAX_SPELLS))
    check(len(own) == PINNED[v], '%s: %d spells, pinned %d' % (v, len(own), PINNED[v]))
# the Chaos spells of UNIVERSAL are every class's (the stock ones are not in the repo data: the light, rope, find
# person, levitate and haste spells of the base server, and Radiant Lantern, a light spell of the casters)
for name in C.UNIVERSAL:
    if any(name in kit[v] for v in ORDER):
        check(all(name in kit[v] for v in ORDER), name + ': every class has it')
check(len(C.RETIRED_IDS) == 68, 'retired: %d' % len(C.RETIRED_IDS))
# Ward of the Mind, the classic mana shield (owner 2026-10-21): the Mystic and Ranger lines only, outside the 15;
# add_vocations.py gives those six the spell, the Necromancer line never gets it
import add_vocations as AV  # noqa: E402
SHIELD = ['Mystic', 'Elementalist', 'Illusionist', 'Ranger', 'Deadeye', 'Beastmaster']
check(sorted(C.CAP['support/magic_shield.lua'][2]) == sorted(SHIELD), 'Ward of the Mind: the Mystic and Ranger lines')
check(sorted(v for v in ORDER if 'Ward of the Mind' in kit[v]) == sorted(SHIELD), 'Ward of the Mind: no other class')
lines = [ls for script, _, ls in AV.LINE_STOCK_SPELLS if script == 'support/magic_shield.lua']
check(len(lines) == 1 and sorted(v for line in lines[0] for v in line) == sorted(SHIELD), 'add_vocations gives it the six')
check(any('magic_shield' in k for k in AV.NECRO_SPELL_SKIP), 'the Necromancer line never gets it')


def install(xml):
    # the order of install_all.py: add_vocations.py (Necromancer line, then the stock spell lines), then the cap
    xml = AV.patch_spells_necro(xml)[0]
    xml = AV.patch_spells_lines(xml)[0]
    return C.patch(xml)[0]


def shield_classes(xml):
    tag = re.search(r'<instant[^>]*script="support/magic_shield.lua".*?</instant>', xml, re.S).group(0)
    return re.findall(r'<vocation name="([^"]+)"', tag)


# a fresh install (the converted stock list of the casters) and one the old cap cut to the Elementalist
for start in (['Mystic', 'Elementalist', 'Illusionist'], ['Elementalist']):
    xml = '<spells>\n' + spell('Magic Shield', 'support/magic_shield.lua', 44, start) + '</spells>\n'
    xml = xml.replace('group="attack"', 'group="support"')
    once = install(xml)
    check(sorted(shield_classes(once)) == sorted(SHIELD), 'install from %s: %s' % (start, shield_classes(once)))
    check(len(shield_classes(once)) == len(set(shield_classes(once))), 'no class twice: %s' % shield_classes(once))
    check(install(once) == once, 'install from %s: a second run changes nothing' % start)

if fails:
    print('%d failure(s)' % len(fails))
    sys.exit(1)
print('patch_spell_cap_test: OK (%d stock spells capped, %d retired)' % (len(C.CAP), len(C.RETIRED_IDS)))
