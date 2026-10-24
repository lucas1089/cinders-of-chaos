#!/usr/bin/env python3
"""Test of patch_open_potions.py on small synthetic potions.lua and items.xml (no game data; CI runs it).

    python3 -I server/tools/patch_open_potions_test.py
"""
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_open_potions as P  # noqa: E402

fails = 0


def ok(c, m):
    global fails
    if not c:
        fails += 1
        print('FAIL', m)


LUA = '''local potions = {
	[7439] = { -- berserk potion
		condition = berserk,
		vocations = {4, 8, 14},
		description = "Only Warriors may drink this potion."
	},
	[7591] = { -- great health potion
		health = {425, 575},
		vocations = {4, 8, 14, 23},
		level = 80,
		description = "Only Warriors and Templars of level 80 or above may drink this fluid."
	},
	[7618] = { -- health potion
		health = {125, 175},
		flask = 7636
	},
	[8472] = { -- great spirit potion
		health = {250, 350},
		mana = {100, 200},
		vocations = {3, 7, 15},
		level = 80,
		description = "Only Rangers of level 80 or above may drink this fluid."
	}
}

function onUse(player, item)
	if potion.level and player:getLevel() < potion.level or potion.vocations and not table.contains(potion.vocations, 1) then
		return true
	end
end
'''
ITEMS = '''<items>
	<item fromid="7592" toid="7599" name="linen" />
	<item id="7591" article="a" name="great health potion">
		<attribute key="description" value="This potion can only be consumed by knights of level 80 or higher." />
	</item>
	<item id="7439" name="berserk potion">
		<attribute key="description" value="This potion can only be consumed by knights." />
	</item>
</items>
'''

new, n = P.patch_potions(LUA)
ok(n == 2, 'two healing potions opened, got %d' % n)
ok('vocations = {4, 8, 14}' in new, 'the berserk potion keeps its list')
ok('vocations = {4, 8, 14, 23}' not in new and 'vocations = {3, 7, 15}' not in new, 'healing lists gone')
ok('Only characters of level 80 or above may drink this fluid.' in new, 'level text names no class')
ok('potion.vocations and not' in new, 'onUse untouched')
ok(P.patch_potions(new) == (new, 0), 'idempotent')
ok(P.opened_ids(new) == {'7591', '7618', '8472'}, 'opened ids: %s' % sorted(P.opened_ids(new)))
items, ni = P.patch_items(ITEMS, P.opened_ids(new))
ok(ni == 1, 'one look text')
ok('This potion can be consumed by characters of level 80 or higher.' in items, 'look text')
ok('knights.' in items, 'the berserk look text stays')
ok(P.patch_items(items, P.opened_ids(new)) == (items, 0), 'items idempotent')

d = tempfile.mkdtemp()
try:
    pot = os.path.join(d, P.POTIONS)
    itm = os.path.join(d, P.ITEMS)
    os.makedirs(os.path.dirname(pot))
    os.makedirs(os.path.dirname(itm))
    with open(pot, 'w', newline='') as f:
        f.write(LUA.replace('\n', '\r\n'))
    with open(itm, 'w', newline='') as f:
        f.write(ITEMS)
    ok(P.main([d, '--dry-run']) == 0 and open(pot, newline='').read() == LUA.replace('\n', '\r\n'), 'dry run writes nothing')
    ok(P.main([d]) == 0, 'main')
    text = open(pot, newline='').read()
    ok('\r\n' in text and '\n' not in text.replace('\r\n', ''), 'CRLF kept')
    ok('vocations = {3, 7, 15}' not in text, 'file opened')
    again = open(pot, newline='').read(), open(itm, newline='').read()
    ok(P.main([d]) == 0 and (open(pot, newline='').read(), open(itm, newline='').read()) == again, 'second run changes nothing')
finally:
    shutil.rmtree(d)

if fails:
    sys.exit(1)
print('patch_open_potions_test: ok')
