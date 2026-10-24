"""Tests for minion_model.py (O160): the pure helpers and the shape of the model.

Run: python3 -I server/tools/minion_model_test.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import minion_model as M

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


levels = (8, 50, 200, 500, 1000)
data = M.dump(levels)
ok(len(data['rows']) == 3 * 6 * len(levels), 'dumper: one row per class, kind and level')
ok(data['config']['minions']['incoming']['pace'] is True, 'config: incoming pace on')
ok(data['config']['minions']['regen']['idle'] > data['config']['minions']['regen']['combat'], 'config: idle regen above combat')

# the current config passes its own limits
ok(M.check(levels) == [], 'check: the shipped config is inside its limits')

# the fix matters: without it the minions are dead a good part of the fight at 1000
old = M.model_class('necromancer', 1000, levels=(8, 50, 200, 500, 1000), legacy=True)
new = M.model_class('necromancer', 1000, levels=(8, 50, 200, 500, 1000))
ok(old['fight']['alive'] < 0.85, 'legacy: the trio is dead often at 1000')
ok(new['fight']['alive'] >= 0.9, 'fix: the trio lives at 1000')
ok(new['ratio1'] > old['ratio1'], 'fix: more damage than before at 1000')
ok(new['ratio1'] < 1.2, 'fix: not far ahead of the median class')

if fails:
    print('minion_model_test: %d failed' % fails)
    sys.exit(1)
print('minion_model_test: ok')
