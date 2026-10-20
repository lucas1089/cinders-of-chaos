#!/usr/bin/env python3
"""Tests of patch_debuff_durations.py: python3 -I server/tools/patch_debuff_durations_test.py"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_debuff_durations as P

SAMPLE = '''<monster name="x">
	<attacks>
		<attack name="melee" interval="2000" min="0" max="-50" />
		<attack name="speed" interval="1000" chance="12" radius="6" target="0" speedchange="-850" duration="60000">
			<attribute key="areaEffect" value="redshimmer" />
		</attack>
		<attack name="drunk" interval="2000" chance="10" range="7" duration="5000" />
		<attack name="outfit" interval="2000" chance="1" range="7" monster="rabbit" duration="60000" />
		<attack name="fire" interval="2000" chance="10" min="-10" max="-20" duration="30000" />
	</attacks>
	<defenses>
		<defense name="speed" interval="2000" chance="15" speedchange="300" duration="60000" />
	</defenses>
</monster>
'''

fails = 0


def check(cond, label):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + label)


new, n = P.patch_text(SAMPLE)
check(n == 2, 'two debuffs over 10 s are cut (got %d)' % n)
check('speedchange="-850" duration="10000"' in new, 'the slow lasts 10 s')
check('monster="rabbit" duration="10000"' in new, 'the outfit change lasts 10 s')
check('range="7" duration="5000"' in new, 'a shorter debuff keeps its duration')
check('max="-20" duration="30000"' in new, 'a damage attack is not a debuff')
check('speedchange="300" duration="60000"' in new, "a monster's own haste (defense) is untouched")
again, n2 = P.patch_text(new)
check(n2 == 0 and again == new, 'idempotent')

if fails:
    sys.exit('%d check(s) failed' % fails)
print('patch_debuff_durations_test: ok')
