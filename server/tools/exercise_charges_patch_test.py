#!/usr/bin/env python3
"""Test of patch_base_events.patch_exercise_charges on the stock exercise_weapons.lua line (no game data; CI runs it).

    python3 -I server/tools/exercise_charges_patch_test.py

The charge count of an exercise weapon is sent to the client again (transform to the same id with the new count); the
last charge keeps setAttribute; a second run changes nothing; an unknown file is refused.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_base_events as P  # noqa: E402

STOCK = '''                            local charges_n = exercise:getAttribute(ITEM_ATTRIBUTE_CHARGES)
                            if charges_n >= 1 then
                                exercise:setAttribute(ITEM_ATTRIBUTE_CHARGES, (charges_n - 1))
                                local voc = player:getVocation():getId()
'''
fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


new, status = P.patch_exercise_charges(STOCK)
check(status == 'patched', 'patched (got %s)' % status)
check('exercise:transform(exercise:getId(), charges_n - 1)' in new, 'the transform sends the new charges')
check('exercise:setAttribute(ITEM_ATTRIBUTE_CHARGES, 0)' in new, 'the last charge keeps setAttribute')
check('local voc = player:getVocation():getId()' in new, 'the rest of the script is kept')
again, status2 = P.patch_exercise_charges(new)
check(status2 == 'already' and again == new, 'a second run changes nothing')
other, status3 = P.patch_exercise_charges('local x = 1\n')
check(status3.startswith('unexpected'), 'an unknown file is refused')

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('exercise_charges_patch_test: OK')
