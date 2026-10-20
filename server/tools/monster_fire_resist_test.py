#!/usr/bin/env python3
"""Test of monster_fire_resist.py (owner decision C7: no fire immunity, a resistance of FIRE_RESIST_PERCENT instead) and of
its use by patch_base_monsters.py. Run: python3 -I server/tools/monster_fire_resist_test.py"""
import os
import sys
import tempfile
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import monster_fire_resist as F  # noqa: E402

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)
        print('FAIL ' + what)


check(F.FIRE_RESIST_PERCENT == 30, 'the owner number: 30')

NO_ELEMENTS = '<monster name="a">\n\t<defenses armor="1" defense="1"/>\n\t<immunities>\n\t\t<immunity fire="1"/>\n\t\t<immunity paralyze="1"/>\n\t</immunities>\n\t<loot>\n\t</loot>\n</monster>\n'
t, imm = F.xml(NO_ELEMENTS)
check(imm and 'fire=' not in t and '<element firePercent="30"/>' in t, 'XML immunity -> element 30')
check('<immunity paralyze="1"/>' in t and t.index('<elements>') < t.index('<immunities>'), 'other immunities kept, elements first')
check(F.xml(t) == (t, False), 'XML second run changes nothing')

WITH = '<monster name="a">\n\t<elements>\n\t\t<element physicalPercent="10"/>\n\t\t<element firePercent="0"/>\n\t</elements>\n\t<immunities>\n\t\t<immunity fire="1"/>\n\t</immunities>\n</monster>\n'
t, imm = F.xml(WITH)
check(imm and t.count('firePercent') == 1 and 'firePercent="30"' in t and 'physicalPercent="10"' in t, 'existing row raised to 30')
check('<immunities>' not in t, 'an emptied immunities block goes')
HIGHER = WITH.replace('firePercent="0"', 'firePercent="60"')
check('firePercent="60"' in F.xml(HIGHER)[0], 'a higher resistance of its own stays')
ADD = '<monster name="a">\n\t<elements>\n\t\t<element icePercent="10"/>\n\t</elements>\n\t<immunities>\n\t\t<immunity fire="1" />\n\t</immunities>\n</monster>\n'
check('<element firePercent="30"/>' in F.xml(ADD)[0] and 'icePercent="10"' in F.xml(ADD)[0], 'row added to a block')
PCT = '<monster name="a">\n\t<elements>\n\t\t<element firePercent="100"/>\n\t</elements>\n</monster>\n'
check(F.xml(PCT) == (PCT.replace('100', '30'), True), 'firePercent 100 -> 30')
MULTI = '<monster name="a">\n\t<immunities>\n\t\t<immunity fire="1" ice="1"/>\n\t</immunities>\n</monster>\n'
t, _ = F.xml(MULTI)
check('ice="1"' in t and 'fire=' not in t, 'a tag with two attributes loses only fire')
CLEAN = '<monster name="a">\n\t<elements>\n\t\t<element firePercent="20"/>\n\t</elements>\n</monster>\n'
check(F.xml(CLEAN) == (CLEAN, False), 'a monster without immunity is untouched')

LUA = 'monster.elements = {\n\t{type = COMBAT_ENERGYDAMAGE, percent = 100},\n\t{type = COMBAT_FIREDAMAGE, percent = 100},\n}\n\nmonster.immunities = {\n\t{type = "paralyze", condition = false}\n}\n'
t, imm = F.lua(LUA)
check(imm and 'COMBAT_FIREDAMAGE, percent = 30' in t and 'COMBAT_ENERGYDAMAGE, percent = 100' in t, 'Lua percent 100 -> 30, energy kept')
check(F.lua(t) == (t, False), 'Lua second run changes nothing')
LUA2 = 'monster.immunities = {\n\t{type = "fire", combat = true, condition = true},\n\t{type = "paralyze", condition = false}\n}\nmType:register(monster)\n'
t, imm = F.lua(LUA2)
check(imm and 'type = "fire"' not in t and 'monster.elements = {\n\t{type = COMBAT_FIREDAMAGE, percent = 30},\n}' in t, 'Lua immunity -> new elements block')
check('"paralyze"' in t, 'Lua other immunities kept')
check(F.lua('monster.race = "blood"\n') == ('monster.race = "blood"\n', False), 'Lua without immunity untouched')

# patch_base_monsters.py: base XML and Lua monsters, our chaos folder left to tune_monsters.py
with tempfile.TemporaryDirectory() as tmp:
    data = os.path.join(tmp, 'data')
    for rel, text in (('items/items.xml', '<items></items>'), ('monster/monsters/dragon.xml', NO_ELEMENTS),
                      ('monster/lua/bosses/x.lua', LUA2), ('monster/monsters/chaos/own.xml', NO_ELEMENTS)):
        p = os.path.join(data, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'w', newline='').write(text)
    tool = os.path.join(HERE, 'patch_base_monsters.py')
    r = subprocess.run([sys.executable, '-I', tool, data], capture_output=True, text=True)
    check(r.returncode == 0 and '2 changed' in r.stdout, 'base patch changes 2 files: ' + r.stdout + r.stderr)
    check('firePercent="30"' in open(os.path.join(data, 'monster/monsters/dragon.xml')).read(), 'base XML fixed')
    check('type = "fire"' not in open(os.path.join(data, 'monster/lua/bosses/x.lua')).read(), 'base Lua fixed')
    check(open(os.path.join(data, 'monster/monsters/chaos/own.xml')).read() == NO_ELEMENTS, 'chaos folder untouched')
    r = subprocess.run([sys.executable, '-I', tool, data], capture_output=True, text=True)
    check('nothing to change' in r.stdout, 'second run changes nothing: ' + r.stdout)

if fails:
    print('monster_fire_resist_test: %d check(s) failed' % len(fails))
    sys.exit(1)
print('monster_fire_resist_test: ok')
