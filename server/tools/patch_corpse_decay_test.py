#!/usr/bin/env python3
"""Tests of patch_corpse_decay.py: python3 -I server/tools/patch_corpse_decay_test.py"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_corpse_decay as P

SAMPLE = '''<items>
	<item id="10" article="a" name="dead ogre">
		<attribute key="containerSize" value="10" />
		<attribute key="decayTo" value="11" />
		<attribute key="duration" value="900" />
		<attribute key="corpseType" value="blood" />
	</item>
	<item id="11" article="a" name="dead ogre">
		<attribute key="containerSize" value="10" />
		<attribute key="decayTo" value="12" />
		<attribute key="duration" value="900" />
		<attribute key="corpseType" value="blood" />
	</item>
	<item id="12" article="a" name="dead ogre">
		<attribute key="decayTo" value="0" />
		<attribute key="duration" value="30" />
		<attribute key="corpseType" value="blood" />
	</item>
	<item id="20" article="a" name="dead rat">
		<attribute key="decayTo" value="21" />
		<attribute key="duration" value="120" />
		<attribute key="corpseType" value="blood" />
	</item>
	<item id="21" article="a" name="dead rat">
		<attribute key="decayTo" value="0" />
		<attribute key="duration" value="60" />
		<attribute key="corpseType" value="blood" />
	</item>
	<item id="30" name="torch">
		<attribute key="decayTo" value="31" />
		<attribute key="duration" value="3600" />
	</item>
</items>
'''

fails = 0


def check(cond, label):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + label)


new, n, ranges = P.patch_text(SAMPLE)
items, _ = P.parse(new)
ogre = sum(items[i]['duration'] for i in (10, 11, 12))
check(ogre <= P.MAX_S, 'the ogre chain lasts at most 5 min (got %d s)' % ogre)
check(items[10]['duration'] > items[12]['duration'], 'stages keep their proportions')
check(items[20]['duration'] == 120 and items[21]['duration'] == 60, 'a chain within 5 min is untouched')
check('value="3600"' in new, 'a non-corpse item (torch) is untouched')
check(n == 3, 'three stages changed (got %d)' % n)
again, n2, _ = P.patch_text(new)
check(n2 == 0 and again == new, 'idempotent')

if fails:
    sys.exit('%d check(s) failed' % fails)
print('patch_corpse_decay_test: ok')
