#!/usr/bin/env python3
"""Test of survey_guardian_hits.py on a made-up data folder: XML and Lua types, the melee formula, what is not a hit, levels,
the pool filter, the committed file in step with the model's reader.
usage: python3 -I server/tools/survey_guardian_hits_test.py"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import survey_guardian_hits as S  # noqa: E402

MONSTERS_XML = """<monsters>
<monster name="Ash Brute" file="monsters/ash_brute.xml" />
<monster name="Pale Wisp" file="monsters/chaos/pale_wisp.xml" />
<monster name="No File" file="monsters/gone.xml" />
</monsters>"""
ASH_BRUTE = """<monster name="Ash Brute" experience="100" speed="200">
<attacks>
<attack name="melee" interval="2000" min="0" max="-300" />
<attack name="melee" interval="2000" skill="80" attack="60" />
<attack name="fire" interval="2000" chance="10" range="7" min="-100" max="-500" />
<attack name="firecondition" interval="1000" chance="12" radius="6" target="0" min="-50" max="-9000" />
<attack name="manadrain" interval="2000" chance="10" range="7" min="-30" max="-4000" />
<attack name="speed" interval="2000" chance="15" speedchange="-700" duration="10000" />
<attack name="djinn electrify" interval="2000" range="5" chance="15" />
</attacks>
</monster>"""
PALE_WISP = """<monster name="Pale Wisp" experience="100" speed="200">
<level min="200" max="300" />
<attacks>
<attack name="energy" interval="2000" chance="10" min="-40" max="-250" />
<attack name="physical" interval="2000" chance="10" range="7" min="0" max="-80" />
</attacks>
</monster>"""
LUA_TYPE = """local mType = Game.createMonsterType("Lua Beast")
local monster = {}
monster.maxHealth = 900
monster.minLevel = 100
monster.maxLevel = 140
monster.attacks = {
	{name ="melee", interval = 1500, chance = 100, minDamage = 0, maxDamage = -90},
	{name ="combat", interval = 2000, chance = 15, type = COMBAT_PHYSICALDAMAGE, minDamage = -50, maxDamage = -400, range = 7},
	{name ="combat", interval = 2000, chance = 15, type = COMBAT_ICEDAMAGE, minDamage = -75, maxDamage = -215, range = 7},
	{name ="condition", type = CONDITION_POISON, interval = 2000, chance = 15, minDamage = -200, maxDamage = -9999},
	{name ="wave t", interval = 2000, chance = 10, minDamage = -250, maxDamage = -380, target = false},
	{name ="speed", chance = 15, interval = 2000, speed = -700},
}
monster.defenses = {}
"""
POOL = """return {
	hunt = {
		{name = "Ash Brute", level = 120, exp = 100, health = 500, spawns = 10, look = 1},
		{name = "Pale Wisp", level = 250, exp = 100, health = 800, spawns = 10, look = 1},
		{name = "Lua Beast", level = 120, exp = 100, health = 900, spawns = 10, look = 1},
		{name = "Tiny", level = 130, exp = 1, health = 50, spawns = 10, look = 1},
		{name = "No File", level = 140, exp = 1, health = 500, spawns = 10, look = 1},
		{name = "Unknown", level = 150, exp = 1, health = 500, spawns = 10, look = 1},
	},
	bosses = {
		{name = "Boss", level = 500, exp = 1, health = 5000, spawns = 1, look = 1},
	}
}"""

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


with tempfile.TemporaryDirectory() as tmp:
    base = os.path.join(tmp, 'monster')
    write(os.path.join(base, 'monsters.xml'), MONSTERS_XML)
    write(os.path.join(base, 'monsters', 'ash_brute.xml'), ASH_BRUTE)
    write(os.path.join(base, 'monsters', 'chaos', 'pale_wisp.xml'), PALE_WISP)
    write(os.path.join(base, 'lua', 'beasts', 'lua_beast.lua'), LUA_TYPE)
    rows = {r[0]: r for r in S.rows_of(tmp, S.pool_rows(POOL), 100)}
    check(set(rows) == {'Ash Brute', 'Pale Wisp', 'Lua Beast'}, 'the rows: %s' % sorted(rows))
    ash = rows['Ash Brute']
    check(ash[1:3] == [120, 0], 'a type with no <level> has mlevel 0: %s' % ash)
    # melee: the explicit 300 against skill 80 / attack 60 = ceil(80 * 3 + 30) = 270
    check(ash[3] == 300 and ash[4] == 150.0, 'the biggest melee roll and its middle: %s' % ash)
    check(S.melee_max(80, 60) == 270, 'the melee formula')
    check(ash[5] == 500 and ash[6] == 300.0, 'the fire spell, not the 9000 condition or the 4000 mana drain: %s' % ash)
    wisp = rows['Pale Wisp']
    check(wisp[2] == 250, 'mlevel is the middle of <level>: %s' % wisp)
    check(wisp[3] == 80 and wisp[5] == 250, 'a physical spell counts as melee kind, energy as element: %s' % wisp)
    lua = rows['Lua Beast']
    check(lua[2] == 120, 'a Lua type reads minLevel / maxLevel: %s' % lua)
    check(lua[3] == 400 and lua[5] == 380, 'physical combat is melee kind, a named wave an element, the condition not: %s' % lua)
    text = S.to_csv(list(rows.values()))
    check(text.splitlines()[0] == ','.join(S.COLS), 'the header')
    check(text.splitlines()[1].startswith('Ash Brute,120,'), 'sorted by level then name: %s' % text.splitlines()[1])
    check(S.to_csv(S.rows_of(tmp, S.pool_rows(POOL), 100)) == text, 'the same text again')

# the committed table reads back through the model's reader and has what the model needs
sys.path.insert(0, HERE)
import guardian_model as G  # noqa: E402
rows = G.hit_rows()
check(len(rows) > 300, 'the committed table has the pool: %d rows' % len(rows))
check(all(r['level'] >= 1 and r['mlevel'] >= 0 for r in rows), 'levels')
check(any(r['melee_max'] > 0 for r in rows) and any(r['elem_max'] > 0 for r in rows), 'both kinds are there')

if fails:
    print('survey_guardian_hits_test: %d failed' % fails)
    sys.exit(1)
print('survey_guardian_hits_test: ok')
