#!/usr/bin/env python3
"""Test of monster_physical_resist.py (no hunt monster immune to physical: a resistance of PHYSICAL_RESIST_PERCENT
instead, the bleed immunity kept, untouchable and fully immune monsters left alone) and of its use by
patch_base_monsters.py. Run: python3 -I server/tools/monster_physical_resist_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import monster_physical_resist as P  # noqa: E402

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)
        print('FAIL ' + what)


check(P.PHYSICAL_RESIST_PERCENT == 30, 'the number: 30 (as fire, C7)')

# the base Phantasm, shortened: elements of its own, physical among other immunities
GHOST = ('<monster name="Phantasm">\n\t<flags>\n\t\t<flag attackable="1" />\n\t</flags>\n\t<elements>\n'
         '\t\t<element earthPercent="20" />\n\t</elements>\n\t<immunities>\n\t\t<immunity paralyze="1" />\n'
         '\t\t<immunity death="1" />\n\t\t<immunity physical="1" />\n\t</immunities>\n</monster>\n')
t, imm = P.xml(GHOST)
check(imm and 'physical="1"' not in t, 'XML immunity goes')
check('<element physicalPercent="30"/>' in t and 'earthPercent="20"' in t, 'row added to its elements')
check('<immunity bleed="1" />' in t, 'bleed immunity kept in its place')
check('<immunity death="1" />' in t and '<immunity paralyze="1" />' in t, 'other immunities kept')
check(P.xml(t) == (t, False), 'XML second run changes nothing')

NO_ELEMENTS = '<monster name="a">\n\t<immunities>\n\t\t<immunity physical="1"/>\n\t</immunities>\n\t<loot>\n\t</loot>\n</monster>\n'
t, imm = P.xml(NO_ELEMENTS)
check(imm and t.index('<elements>') < t.index('<immunities>') and 'physicalPercent="30"' in t, 'new elements block first')

OWN = GHOST.replace('<element earthPercent="20" />', '<element physicalPercent="60"/>')
t, imm = P.xml(OWN)
check(imm and 'physicalPercent="60"' in t and t.count('physicalPercent') == 1, 'a higher resistance of its own stays')
LOW = GHOST.replace('<element earthPercent="20" />', '<element physicalPercent="-10"/>')
check('physicalPercent="30"' in P.xml(LOW)[0], 'a lower row is raised to 30')
PCT = '<monster name="a">\n\t<elements>\n\t\t<element physicalPercent="100"/>\n\t</elements>\n</monster>\n'
check(P.xml(PCT) == (PCT.replace('100', '30'), True), 'physicalPercent 100 -> 30')
NAMED = '<monster name="a">\n\t<immunities>\n\t\t<immunity name="physical"/>\n\t</immunities>\n</monster>\n'
t, imm = P.xml(NAMED)
check(imm and '<immunity name="bleed"/>' in t and 'physicalPercent="30"' in t, 'name="physical" form')
CLEAN = '<monster name="a">\n\t<elements>\n\t\t<element physicalPercent="20"/>\n\t</elements>\n</monster>\n'
check(P.xml(CLEAN) == (CLEAN, False), 'a monster without immunity is untouched')

# left alone: not attackable (a thrower trap), immune to every damage type but fire (an event creature)
TRAP = GHOST.replace('attackable="1"', 'attackable="0"')
check(P.xml(TRAP) == (TRAP, False), 'not attackable: untouched')
ALL = ('<monster name="a">\n\t<elements>\n\t\t<element firePercent="30"/>\n\t</elements>\n\t<immunities>\n'
       + ''.join('\t\t<immunity %s="1"/>\n' % k for k in ('physical', 'energy', 'earth', 'ice', 'holy', 'death'))
       + '\t</immunities>\n</monster>\n')
check(P.xml(ALL) == (ALL, False), 'immune to everything but fire: untouched')
check(P.xml(ALL.replace('earth=', 'poison='))[1] is False, 'poison counts as earth')
check(P.xml(ALL.replace('\t\t<immunity holy="1"/>\n', ''))[1] is True, 'one element open: converted')

LUA = ('monster.flags = {\n\tattackable = true,\n}\n\nmonster.elements = {\n\t{type = COMBAT_PHYSICALDAMAGE, percent = 100},\n'
       '\t{type = COMBAT_ICEDAMAGE, percent = 70},\n}\n\nmonster.immunities = {\n\t{type = "paralyze", condition = true}\n}\n')
t, imm = P.lua(LUA)
check(imm and 'COMBAT_PHYSICALDAMAGE, percent = 30' in t and 'COMBAT_ICEDAMAGE, percent = 70' in t, 'Lua percent 100 -> 30')
check(P.lua(t) == (t, False), 'Lua second run changes nothing')
LUA2 = ('monster.immunities = {\n\t{type = "physical", combat = true, condition = true},\n'
        '\t{type = "paralyze", condition = true}\n}\nmType:register(monster)\n')
t, imm = P.lua(LUA2)
check(imm and '{type = "physical", combat = false, condition = true}' in t, 'Lua combat immunity off, bleed kept')
check('monster.elements = {\n\t{type = COMBAT_PHYSICALDAMAGE, percent = 30},\n}' in t, 'Lua new elements block')
check(P.lua(t) == (t, False), 'Lua second run changes nothing (2)')
LUA3 = 'monster.immunities = {\n\t{type = "physical", condition = false},\n}\n'
check(P.lua(LUA3) == (LUA3, False), 'Lua condition-only row is no immunity')
check(P.lua(LUA2.replace('monster.immunities', 'monster.flags = {attackable = false}\nmonster.immunities'))[1] is False,
      'Lua not attackable: untouched')

# patch_base_monsters.py: base XML and Lua monsters changed, our chaos folder left alone
with tempfile.TemporaryDirectory() as tmp:
    data = os.path.join(tmp, 'data')
    for rel, text in (('items/items.xml', '<items></items>'), ('monster/monsters/phantasm.xml', GHOST),
                      ('monster/lua/x/spectre.lua', LUA), ('monster/monsters/flamethrower.xml', TRAP),
                      ('monster/monsters/chaos/own.xml', GHOST)):
        p = os.path.join(data, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'w', newline='').write(text)
    tool = os.path.join(HERE, 'patch_base_monsters.py')
    r = subprocess.run([sys.executable, '-I', tool, data], capture_output=True, text=True)
    check(r.returncode == 0 and '2 changed' in r.stdout and 'physical immunity -> 30% resistance' in r.stdout,
          'base patch changes 2 files: ' + r.stdout + r.stderr)
    check('physicalPercent="30"' in open(os.path.join(data, 'monster/monsters/phantasm.xml')).read(), 'base XML fixed')
    check('percent = 30' in open(os.path.join(data, 'monster/lua/x/spectre.lua')).read(), 'base Lua fixed')
    check(open(os.path.join(data, 'monster/monsters/flamethrower.xml')).read() == TRAP, 'trap untouched')
    check(open(os.path.join(data, 'monster/monsters/chaos/own.xml')).read() == GHOST, 'chaos folder untouched')
    r = subprocess.run([sys.executable, '-I', tool, data], capture_output=True, text=True)
    check('nothing to change' in r.stdout, 'second run changes nothing: ' + r.stdout)

if fails:
    print('monster_physical_resist_test: %d check(s) failed' % len(fails))
    sys.exit(1)
print('monster_physical_resist_test: ok')
