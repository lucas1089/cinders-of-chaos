"""Tests for companion_model.py (O306): the Python formulas against the server's Lua functions, the shipped config inside
its limits, and the before / after of the fix.

Run: python3 -I server/tools/companion_model_test.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import companion_model as M
import pack_model as P
import rotation_sim as R

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


levels = (1, 50, 100, 399, 400, 1000)
data = M.dump(levels)
c, bal = M.conf()
ok(len(data['rows']) == len(levels), 'dumper: one row per level')
for r in data['rows']:
    lv, sk = r['level'], r['skill']
    ok(r['health'] == M.health(c, lv), 'health formula = classes.lua at %d' % lv)
    ok(r['cap'] == M.cap(c, lv), 'cap = classes.lua at %d' % lv)
    avg = M.bite(c, lv, sk)
    ok(abs((r['autoMin'] + r['autoMax']) / 2 - avg) <= 1.0, 'auto bite = classes.lua at %d' % lv)
    ok(r['shown'] == lv, 'shown level is the owner level at %d' % lv)
    ok(r['autoMax'] > r['mulMax'] or lv < 5, 'the own bite is above the spells bite at %d' % lv)
    ok(r['taken'] == round(1000 * c['taken']), 'taken share at %d' % lv)
    ok(r['takenAlpha'] < r['taken'], 'Pack Alpha cuts more at %d' % lv)
ok(M.cap(c, 399) == 1 and M.cap(c, 400) == 2, 'two companions from level 400')

# the shipped config passes its own limits, at the report levels too
ok(M.check() == [], 'check: the shipped config is inside its limits')

# the fix matters (tester report: dead in under 5 s at level 400, 4% of the damage)
for lv in (100, 400, 1000):
    old, new = M.alive_seconds(lv, True), M.alive_seconds(lv)
    ok(old < 8, 'legacy: the companion lived %.1f s at %d' % (old, lv))
    ok(new >= bal['limits']['aliveSecondsMin'] and new > 2 * old, 'fix: lives %.1f s at %d' % (new, lv))
    t = M.totals(lv)
    ok(t['share_before'] < 0.09, 'legacy: the bites were %.0f%% at %d' % (100 * t['share_before'], lv))
    ok(0.20 <= t['share'] <= 0.30, 'fix: the bites are %.0f%% at %d' % (100 * t['share'], lv))
ok(M.hits_survived(400, True) < 8 <= M.hits_survived(400), 'hits survived at 400')

# more attackers, less time; a damage cut of Pack Alpha is outside the model (it only helps)
ok(M.alive_seconds(400, attackers=4) < M.alive_seconds(400) / 1.9, 'four attackers halve the time')

# the pack model: the Beastmaster's total is the measured one with the bites replaced; other classes untouched; tune off untouched
raw = P._damage('Beastmaster', 400, True, False)
ok(P.damage('Beastmaster', 400, True, False) == raw, 'tune off: the measured numbers')
ok(P.damage('Warrior', 400) == P._damage('Warrior', 400), 'other classes: untouched')
d1, d5 = P.damage('Beastmaster', 400)
t = M.totals(400)
ok(abs(d1 - t['after']) < 1e-6, 'pack model: Beastmaster 1 target = the model\'s after')
ok(abs(t['drift5']) < 0.02, 'level 400: a pack of 5 is where it was')

# a retuned config fails the check: bites back to the old ones
saved = dict(c)
c['autoLevel'], c['autoSkill'] = 0.12, 0.6
try:
    ok(M.check() != [], 'check: the old bites fail the share limit')
finally:
    c.update(saved)

if fails:
    print('companion_model_test: %d failed' % fails)
    sys.exit(1)
print('companion_model_test: ok')
