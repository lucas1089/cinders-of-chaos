#!/usr/bin/env python3
"""Tests of tools/greater_rift_model.py (O668): the maths on a synthetic rule, the check on broken inputs, and the real repo's
numbers (the tier the median class reaches, the shape of the curve). Run: python3 -I server/tools/greater_rift_model_test.py"""
import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spell_upgrade_model as _SU  # noqa: E402
_SU.set_mode(False)  # O709: the spell upgrades ship on and a model's default is the upgrades mode; this test holds the switch-off numbers (the model's --check runs both modes in CI)
import greater_rift_model as M

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def near(a, b, tol, what):
    ok(abs(a - b) <= tol, '%s: %r vs %r' % (what, a, b))


# ------------------------------------------------------------------ a synthetic rule: health x2 a tier, clock 1000
def synth(health=2.0):
    info = {str(g): {'health': health ** g, 'damage': 1.1 ** g, 'level': 1000 + 25 * g, 'reward': 1.0, 'shown': 15 + g}
            for g in range(1, 150)}
    return {'maxTier': 15, 'engineBonus': 0.0015,
            'tier15': {'minLevel': 1000, 'clock': 1000, 'limit': 1000, 'chestGold': 1000000,
                       'solo': {'packs': 80.0, 'guardian': 20.0, 'walk': 0.0},
                       'party5': {'packs': 400.0, 'guardian': 100.0, 'walk': 0.0}},
            'greater': {'clock': {'steps': [{'fraction': 0.5, 'up': 3}, {'fraction': 0.75, 'up': 2}, {'fraction': 1.0, 'up': 1}]},
                        'firstTier': 16, 'rule': {}, 'rewards': {'best': {'gold': {'base': 100, 'perTier': 10}}}},
            'info': info, 'tps': {'1000': 10.0}}


BAL = {'partyDps': 5.0, 'clockUse': 1.0, 'scan': 5, 'levels': [1000], 'limits': {}}
N = synth()
P1 = {'area': 1.0, 'single': 1.0}

# seconds: base 100 s solo, doubles a tier; a party of 5 with 5 times the damage takes the same
near(M.seconds(N, BAL, P1, 1.0, 0), 100.0, 1e-9, 'tier 15 seconds')
near(M.seconds(N, BAL, P1, 1.0, 3), 800.0, 1e-9, 'three tiers up: x8')
near(M.seconds(N, BAL, P1, 1.0, 3, 5), 800.0, 1e-9, 'a party of 5 with 5x damage')
near(M.seconds(N, BAL, {'area': 2.0, 'single': 2.0}, 1.0, 3), 400.0, 1e-9, 'twice the damage halves the seconds')
n2 = copy.deepcopy(N)
n2['tier15']['solo']['walk'] = 50.0
near(M.seconds(n2, BAL, P1, 0.5, 0), 125.0, 1e-9, 'the walk x the speed ratio')

# reach: 100 * 2^g <= 1000 -> g 3 (800 s), not 4 (1600)
ok(M.reach(N, BAL, P1, 1.0) == 3, 'reach 3, got %r' % M.reach(N, BAL, P1, 1.0))
ok(M.reach(N, BAL, {'area': 4.0, 'single': 4.0}, 1.0) == 5, 'four times the damage: two tiers more')
ok(M.reach(N, BAL, {'area': 0.05, 'single': 0.05}, 1.0) == -1, 'tier 15 itself out of the clock: -1')
bal2 = dict(BAL, clockUse=0.5)
ok(M.reach(N, bal2, P1, 1.0) == 2, 'clockUse 0.5')

# the clock steps of R.greaterUp: <= 50% -> 3, <= 75% -> 2, <= 100% -> 1, over -> 0
ok(M.up_steps(N, 500, 1000) == 3, 'up 3 at exactly half')
ok(M.up_steps(N, 501, 1000) == 2, 'up 2 just over half')
ok(M.up_steps(N, 750, 1000) == 2, 'up 2 at three quarters')
ok(M.up_steps(N, 751, 1000) == 1, 'up 1 over three quarters')
ok(M.up_steps(N, 1000, 1000) == 1, 'up 1 at the clock')
ok(M.up_steps(N, 1001, 1000) == 0, 'no step past the clock')

# the climb: g 0 (100 s: +3) -> 3 (800 s: reach 3 already) = 1 run
ok(M.climb_runs(N, BAL, P1, 1.0) == 1, 'climb of one run, got %r' % M.climb_runs(N, BAL, P1, 1.0))
slow = synth(1.2)
r = M.reach(slow, BAL, P1, 1.0)
ok(r == 12, 'slow rule reach 12, got %r' % r)
ok(M.climb_runs(slow, BAL, P1, 1.0) >= 4, 'a slow rule needs several runs')
ok(M.climb_runs(N, BAL, {'area': 0.05, 'single': 0.05}, 1.0) == 0, 'nothing reached: 0 runs')

# the damage factor: the rule x the engine's level bonus of the shown level against the entry level
near(M.damage_factor(N, 0), 1.0, 1e-12, 'damage factor of tier 15')
near(M.damage_factor(N, 4), 1.1 ** 4 * (1 + 0.0015 * 1100) / (1 + 0.0015 * 1000), 1e-9, 'damage factor of g 4')


# ------------------------------------------------------------------ the real numbers
M.balance()
real = M.compute()
errors = M.check(real)
ok(errors == [], 'the repo passes its own limits: %s' % errors)
by = {r['level']: r for r in real['rows']}
for lv in (1500, 2000, 2500):
    ok(by[lv]['reach'] >= 1, 'level %d reaches a Greater tier' % lv)
ok(by[1500]['reach'] < by[2000]['reach'] < by[2500]['reach'], 'a higher level reaches a higher tier')
ok(by[1025]['reach'] < by[1500]['reach'], 'the entry level reaches less than 1500')
# every tier costs more seconds than the one below it, with no step over the limit (no wall, no free tier)
rows = M.curve(real, 2000, 60)
ok(all(rows[i]['secs'] > rows[i - 1]['secs'] for i in range(1, len(rows))), 'seconds rise with every tier (level 2000)')
ok(all(rows[i]['pressure'] > rows[i - 1]['pressure'] for i in range(1, len(rows))), 'the guardian pressure rises with every tier')
# the rule file: the health step is what the curve is made of
step = real['N']['greater']['rule']['health']
ok(abs(real['N']['info']['10']['health'] - (1 + step) ** 10) < 1e-6, 'the rule rows are (1 + health)^g')
# a broken limit fails: a window the median class cannot be in
broken = copy.deepcopy(real)
broken['bal']['limits']['reach']['2000'] = [90, 95]
ok(any('level 2000' in e for e in M.check(broken)), 'a reach window that is missed is reported')
broken = copy.deepcopy(real)
broken['bal']['limits']['pressure'] = {'min': 5, 'max': 6}
ok(any('median healing' in e for e in M.check(broken)), 'a pressure window that is missed is reported')
broken = copy.deepcopy(real)
broken['bal']['limits']['stepRatio'] = {'min': 1.2, 'max': 1.3}
ok(any('wall or a free tier' in e for e in M.check(broken)), 'a step ratio that is missed is reported')
broken = copy.deepcopy(real)
broken['bal']['limits']['pbGoldShare'] = 0.01
ok(any('personal best' in e for e in M.check(broken)), 'a personal best that pays too much gold is reported')

print('greater_rift_model_test: %s' % ('%d failure(s)' % fails if fails else 'ok'))
sys.exit(1 if fails else 0)
