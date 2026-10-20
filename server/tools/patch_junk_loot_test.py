#!/usr/bin/env python3
"""Test of patch_junk_loot.py (run: python3 -I tools/patch_junk_loot_test.py)"""
import os, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_junk_loot as J

XML = '''<monster name="X">
	<loot>
		<item id="2148" chance="100000" countmax="5"/>
		<item id="25380" countmax="1" chance="10"/><!-- talent token -->
		<item id="36010" countmax="2" chance="18000" /><!-- goblin tooth -->
		<item id="27053" chance="10"/><!-- not checked: stays -->
		<item id="2464" chance="500"/>
	</loot>
</monster>
'''
LUA = '''monster.loot = {
	{id = 12409, chance = 6740},
	{id = 2464, chance = 5620},
	{id = 12436, chance = 1120}
}
'''
assert J.xml_fix(XML) == XML.replace('\t\t<item id="25380" countmax="1" chance="10"/><!-- talent token -->\n', '').replace(
    '\t\t<item id="36010" countmax="2" chance="18000" /><!-- goblin tooth -->\n', '')
assert J.xml_fix(J.xml_fix(XML)) == J.xml_fix(XML)
out = J.lua_fix(LUA)
assert out == 'monster.loot = {\n\t{id = 2464, chance = 5620}\n}\n', out
assert J.lua_fix(out) == out
assert 27053 not in J.JUNK and 29001 not in J.JUNK and len(J.JUNK) == 52 and not {6097, 6098, 6088, 6090} & set(J.JUNK)
d = tempfile.mkdtemp()
os.makedirs(os.path.join(d, 'monster', 'monsters', 'chaos'))
p = os.path.join(d, 'monster', 'monsters', 'chaos', 'x.xml')
open(p, 'w').write(XML)
assert J.main([d, '--check']) == 1
assert J.main([d]) == 0 and J.main([d, '--check']) == 0
print('patch_junk_loot_test: ok')
