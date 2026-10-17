#!/usr/bin/env python3
"""Test of add_vocations.patch_item_potion_texts on a small synthetic items.xml and potions.lua (no game data; CI runs it).

    python3 -I server/tools/add_vocations_potion_text_test.py

The Look text of a potion in items.xml ("can only be consumed by knights ...") must name the same classes as the refusal
text of potions.lua; a self-closing <item ... /> in front of a potion must not hide it; a second run changes nothing.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import add_vocations as A  # noqa: E402

ITEMS = '''<items>
	<item fromid="7592" toid="7599" name="linen" />
	<item id="7591" article="a" name="great health potion">
		<attribute key="weight" value="310" />
		<attribute key="description" value="This potion can only be consumed by knights of level 80 or higher." />
	</item>
	<item id="26028" name="sword" />
	<item id="26029" article="an" name="ultimate mana potion">
		<attribute key="description" value="This potion can only be consumed by sorcerers and druids of level 130 or higher." />
	</item>
	<item id="1234" name="other">
		<attribute key="description" value="A plain description." />
	</item>
</items>
'''
POTIONS = '''local potions = {
	[7591] = { -- great health potion
		health = {250, 350},
		vocations = {4, 8, 14, 23, 24, 25},
		level = 80,
		description = "Only Warriors and Templars of level 80 or above may drink this fluid."
	},
	[26029] = { -- ultimate mana potion
		mana = {425, 575},
		vocations = {1, 2, 3, 4},
		level = 130,
		description = "Only characters of level 130 or above may drink this fluid."
	},
}
'''

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


new, n = A.patch_item_potion_texts(ITEMS, POTIONS)
check(n == 2, 'two potions changed (got %d)' % n)
check('by Warriors and Templars of level 80 or higher.' in new, 'the great health potion names the classes')
check('by characters of level 130 or higher.' in new, 'the ultimate mana potion (after a self-closing item) too')
check('knights' not in new and 'sorcerers' not in new, 'no stock class left')
check('A plain description.' in new, 'an item that is no potion is untouched')
again, n2 = A.patch_item_potion_texts(new, POTIONS)
check(n2 == 0 and again == new, 'a second run changes nothing')

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('add_vocations_potion_text_test: OK')
