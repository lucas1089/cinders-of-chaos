#!/usr/bin/env python3
"""Test of patch_base_monsters.py on a made-up data folder: speed spells below -1000 clamped (XML and Lua), a loot name
with its article becomes the item id, unknown races mapped, our own chaos folders and good files untouched, a second
run changes nothing, --dry-run writes nothing, bad args.
Run: python3 -I server/tools/patch_base_monsters_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_base_monsters.py')
sys.path.insert(0, HERE)
import patch_base_monsters as P  # noqa: E402

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)
        print('FAIL ' + what)


ITEMS = '''<?xml version="1.0" encoding="UTF-8"?>
<items>
	<item id="100" article="a" name="test doll" />
	<item id="101" article="the" name="head of a test doll" />
	<item fromid="102" toid="104" article="the" name="torso of a test doll" />
	<item id="110" article="a" name="the plain key" />
</items>
'''
SLOW = '''<?xml version="1.0" encoding="UTF-8"?>
<monster name="Test Slow" race="blood" experience="10" speed="200">
	<attacks>
		<attack name="speed" interval="1000" chance="12" radius="6" target="0" speedchange="-1900" duration="60000"/>
		<attack name="speed" interval="1000" chance="12" minspeedchange="-1200" maxspeedchange="-800" duration="6000"/>
		<attack name="speed" interval="1000" chance="12" speedchange="-1000" duration="6000"/>
	</attacks>
</monster>
'''
LOOT = '''<?xml version="1.0" encoding="UTF-8"?>
<monster name="Test Loot" race="magical" experience="10" speed="200">
	<loot>
		<item id="100" chance="1000" />
		<item name="the torso of a test doll" chance="800" />
		<item name="the head of a test doll" chance="400" />
		<item name="test doll" chance="400" />
		<item name="the plain key" chance="400" />
		<item name="no such thing" chance="400" />
	</loot>
</monster>
'''
LUA = '''local mType = Game.createMonsterType("Test Lua")
local monster = {}
monster.race = "dragon"
monster.attacks = {
	{name = "speed", interval = 2000, chance = 15, speedChange = -1500, radius = 4, target = false, duration = 5000},
	{name = "speed", interval = 2000, chance = 15, speedChange = -600, duration = 5000},
}
mType:register(monster)
'''
GOOD_LUA = 'local monster = {}\nmonster.race = "undead"\n'


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', newline='') as f:
        f.write(text)


def read(path):
    with open(path, newline='') as f:
        return f.read()


def run(*args):
    p = subprocess.run([sys.executable, '-I', TOOL] + list(args), capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


with tempfile.TemporaryDirectory() as tmp:
    data = os.path.join(tmp, 'data')
    write(os.path.join(data, 'items', 'items.xml'), ITEMS)
    m = os.path.join(data, 'monster')
    write(os.path.join(m, 'monsters.xml'), '<monsters>\n\t<monster name="Test Slow" file="monsters/slow.xml" />\n</monsters>\n')
    write(os.path.join(m, 'monsters', 'slow.xml'), SLOW)
    write(os.path.join(m, 'monsters', 'loot.xml'), LOOT)
    write(os.path.join(m, 'lua', 'bosses', 'test.lua'), LUA)
    write(os.path.join(m, 'lua', 'good.lua'), GOOD_LUA)
    own_xml = os.path.join(m, 'monsters', 'chaos', 'own.xml')
    own_lua = os.path.join(m, 'lua', 'chaos', 'own.lua')
    write(own_xml, SLOW)
    write(own_lua, LUA)

    rc, out = run(data, '--dry-run')
    check(rc == 0, 'dry run ok: ' + out)
    check('3 would change' in out, 'dry run counts 3 files: ' + out)
    check(read(os.path.join(m, 'monsters', 'slow.xml')) == SLOW, 'dry run writes nothing')

    rc, out = run(data)
    check(rc == 0, 'run ok: ' + out)
    check('3 changed' in out, 'three files changed: ' + out)
    slow = read(os.path.join(m, 'monsters', 'slow.xml'))
    check('speedchange="-1000" duration="60000"' in slow, '-1900 -> -1000')
    check('minspeedchange="-1000" maxspeedchange="-800"' in slow, 'minspeedchange -1200 -> -1000, max kept')
    check(slow.count('-1000') == 3, 'the -1000 spell untouched')
    check(SLOW.replace('-1900', '-1000').replace('-1200', '-1000') == slow, 'nothing else changed')
    loot = read(os.path.join(m, 'monsters', 'loot.xml'))
    check('<item id="102" chance="800" /><!-- the torso of a test doll -->' in loot, 'torso by id (first of a range)')
    check('<item id="101" chance="400" /><!-- the head of a test doll -->' in loot, 'head by id')
    check('<item name="test doll" chance="400" />' in loot, 'a known name stays')
    check('<item name="the plain key" chance="400" />' in loot, 'a known name with "the" in it stays')
    check('<item name="no such thing" chance="400" />' in loot, 'an unknown name without an article: left alone')
    check('race="energy"' in loot, 'XML race magical -> energy')
    lua = read(os.path.join(m, 'lua', 'bosses', 'test.lua'))
    check('monster.race = "blood"' in lua, 'Lua race dragon -> blood')
    check('speedChange = -1000, radius' in lua and 'speedChange = -600' in lua, 'Lua speed clamped, -600 kept')
    check(read(os.path.join(m, 'lua', 'good.lua')) == GOOD_LUA, 'a known race untouched')
    check(read(own_xml) == SLOW and read(own_lua) == LUA, 'our own chaos folders untouched')

    rc, out = run(data)
    check(rc == 0 and 'nothing to change' in out, 'second run changes nothing: ' + out)

    rc, out = run()
    check(rc == 1, 'no args: usage')
    rc, out = run(os.path.join(tmp, 'nothing'))
    check(rc == 1, 'not a data folder')

check(P.new_race('VENOM') is None and P.new_race('3') is None, 'known races and race numbers stay')
check(P.new_race('wyrm') == 'blood', 'an unmapped race -> blood')
check(P.resolve('An Apple', {'apple': 5}) == 5 and P.resolve('apple', {'apple': 5}) is None, 'resolve')

if fails:
    print('patch_base_monsters_test: %d check(s) failed' % len(fails))
    sys.exit(1)
# no fleeing at low health
t, ch = P.patch_xml('<monster name="x"><flags><flag runonhealth="15" /></flags></monster>', {})
check('runonhealth="0"' in t and any('runonhealth' in c for c in ch), 'XML runonhealth becomes 0')
t2, ch2 = P.patch_xml(t, {})
check(t2 == t and not ch2, 'XML runonhealth: second run changes nothing')
t, ch = P.patch_lua('monster.flags = { runHealth = 10, hostile = true }')
check('runHealth = 0' in t, 'Lua runHealth becomes 0')
t2, ch2 = P.patch_lua(t)
check(t2 == t and not ch2, 'Lua runHealth: second run changes nothing')

print('patch_base_monsters_test: all checks passed')
