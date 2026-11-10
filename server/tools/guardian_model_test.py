#!/usr/bin/env python3
"""Test of the single hit and the level warning of guardian_model.py (O476): the odds of a guardian, the window, one
application of every factor of the hit chain, the worst modifiers, the rule against the stored levels of rift_config.lua
(it must fail when they drift), and the shape of the levels.
usage: python3 -I server/tools/guardian_model_test.py"""
import copy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import guardian_model as G  # noqa: E402
import survival_model as S  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def near(a, b, tol=1e-6):
    return abs(a - b) <= tol * max(1.0, abs(b))


nums = G.numbers(False)
bal = nums['bal']
d = G.preload([100, 500, 1000])

# the odds: the strongest of three random picks
rows = [{'name': 'n%02d' % i, 'level': 100 + i, 'mlevel': 0, 'melee_max': 10.0 * (i + 1), 'melee_mean': 5.0, 'elem_max': 0.0,
         'elem_mean': 0.0} for i in range(10)]
odds = G.guardian_odds(rows, 3)
check(near(sum(p for _, p in odds), 1.0), 'the odds sum to one')
check(odds[0][1] == 0 and odds[1][1] == 0, 'the two weakest are never the strongest of three')
check(all(odds[i][1] <= odds[i + 1][1] for i in range(9)), 'a stronger type is more likely the strongest')
check(near(odds[9][1], math.comb(9, 2) / math.comb(10, 3)), 'the last: C(9, 2) / C(10, 3)')

# the window of a tier and its widening (rift_core.lua R.pickTypes)
lo, hi = nums['tiers'][0]['pick']
few = [{'name': 'a', 'level': lo, 'mlevel': 0}, {'name': 'b', 'level': hi + nums['hit']['widenStep'] - 1, 'mlevel': 0},
       {'name': 'c', 'level': hi + nums['hit']['widenStep'] + 5, 'mlevel': 0}]
got = [r['name'] for r in G.candidates(few, nums, 1)]
check(got == ['a', 'b', 'c'] or got == ['a', 'b'], 'a window with fewer than three types is widened: %s' % got)
check([r['name'] for r in G.candidates(few[:1] + [dict(few[0], name='z', level=lo + 1)] + [dict(few[0], name='y', level=lo + 2)],
                                       nums, 1)] == ['a', 'z', 'y'], 'sorted by level')

# one application of every factor: the XML roll x engine level bonus (passes) x late boost (melee) x legendary x guardian
# curve x tier damage x party
tier = 3
t = nums['tiers'][tier - 1]
row = {'name': 'x', 'level': 300, 'mlevel': 300, 'melee_max': 1000.0, 'melee_mean': 500.0, 'elem_max': 1000.0, 'elem_mean': 500.0}
common = G.rank_damage() * t['guardian'] * t['tierDamage']
eng = (1 + bal['hit']['engineBonus'] * 300) ** bal['hit']['enginePasses']
boost = 1 + S.boost_percent(d['boost']['points'], 300) / 100.0
check(near(G.chain(row, 'elem', tier, nums, bal, d), 1000 * eng * common), 'elemental: engine bonus, rank, curve, no late boost')
check(near(G.chain(row, 'melee', tier, nums, bal, d), 1000 * eng * boost * common), 'melee: and the late-game boost')
check(near(G.chain(dict(row, mlevel=0), 'elem', tier, nums, bal, d), 1000 * common), 'no <level>: no engine bonus')
check(near(G.chain(row, 'elem', tier, nums, bal, d, party=5), 1000 * eng * common * 1.4), 'a party of five: x1.4')
check(near(G.rank_damage(), 1.70), 'the legendary rank is the one monster_tiers.lua has: %s' % G.rank_damage())

# the worst modifiers
mon, key, combo = G.worst_mods(nums, 1, 'elem')
check(near(mon, 1.4 * 1.5 * 1.5), 'the monster side without a physical weapon hit: Brutal, Berserker, a critical hit')
check(near(G.worst_mods(nums, 1, 'melee')[0], 1.4 * 1.5 * 1.5 * 1.5), 'a physical weapon hit adds the element')
check(set(combo) == {'brutality', 'keen'}, 'tier 1 keys can roll Brutality and Keen Fangs only: %s' % (combo,))
check(near(key, 1.4 * 1.5), 'at their top: x1.4 and a x1.5 critical hit (%s)' % key)
mon4, key4, combo4 = G.worst_mods(nums, 4, 'elem')
check('dread' in combo4 and key4 > key, 'from tier 4 Dread Guardian is the biggest: %s' % (combo4,))
check(len(combo4) <= nums['hit']['maxMods'], 'no more modifiers than a key holds')
check(len(set(m for m in combo4 if m in ('searing', 'flaying'))) <= 1 and
      len(set(m for m in combo4 if m.endswith('brand'))) <= 1, 'one of a group')

# the stored levels and the rule: the check passes on the repo and fails when they drift
check(G.check_warn(nums) == [], 'the stored warn block is the rule: %s' % G.check_warn(nums))
w = G.warn_levels()
levels = w['levels']
check(len(levels) == nums['hit']['maxTier'], 'a level for every tier')
check(levels == list(nums['warn']['levels']), 'the same levels the config stores')
check(w['partySize'] == nums['warn']['partySize'] and 2 <= w['partySize'] <= nums['hit']['maxPlayers'], 'the party size')
for tr in range(nums['hit']['maxTier']):
    lo, hi = nums['tiers'][tr]['pick']
    check(levels[tr] >= nums['tiers'][tr]['minLevel'], 'tier %d: not under the entry level' % (tr + 1))
    check(levels[tr] <= max(hi, levels[tr - 1] if tr else 0), 'tier %d: not above the window top (or the tier below)' % (tr + 1))
    check(tr == 0 or levels[tr] >= levels[tr - 1], 'tier %d: never below the tier under it' % (tr + 1))
check(all(x['why'] in ('rule', 'window top', 'tier below') for x in w['detail']), 'every level says where it comes from')

drift = copy.deepcopy(nums)
drift['warn']['levels'][2] += 5
errors = G.check_warn(drift)
check(len(errors) == 1 and 'warn.levels' in errors[0], 'a drifted level is reported: %s' % errors)
drift = copy.deepcopy(nums)
drift['warn']['partySize'] += 1
check(any('partySize' in e for e in G.check_warn(drift)), 'a drifted party size is reported')
check(G.check_warn(dict(nums, warn=None)) == ['rift_config.lua has no `warn` block'], 'a missing block is reported')

# the rule answers to its inputs: a stricter share moves the levels up
saved = bal['hit']['oneHit']
bal['hit']['oneHit'] = 0.3
try:
    strict = G.warn_levels()['levels']
finally:
    bal['hit']['oneHit'] = saved
check(strict != levels and all(a >= b for a, b in zip(strict, levels)), 'a smaller share of the pool asks for more level')

# ---------------------------------------------------------------- O478: the hit cap in the model
# the share of a roll's average a ceiling leaves: E[min(X, cap)] / E[X], X spread evenly
check(near(G.uniform_retention(0, 100, 100), 1.0), 'a cap at the top of the range leaves everything')
check(near(G.uniform_retention(0, 100, 500), 1.0), 'a cap over the range leaves everything')
check(near(G.uniform_retention(0, 300, 100), 2 * 100 / 300 - (100 / 300) ** 2), 'from 0 to 3 x the cap: 2 c / h - (c / h)^2 = 0.556')
check(near(G.uniform_retention(100, 100, 50), 0.5), 'a fixed roll over the cap: cap / roll')
check(near(G.uniform_retention(200, 400, 100), 100 / 300.0), 'a range wholly over the cap: cap / mean')
check(near(G.uniform_retention(0, 100, 0), 0.0), 'a cap of 0 leaves nothing')
prev = 1.0
for cap in (90, 70, 50, 30, 10):
    cur = G.uniform_retention(20, 100, cap)
    check(cur <= prev, 'a lower cap never leaves more (%d)' % cap)
    prev = cur

# the cap block of the numbers dump and its check
check(nums['cap'] == {'enabled': True, 'share': 0.6}, 'the dump has rift_config.lua guardian.hitCap: %s' % nums.get('cap'))
check(G.check_cap(nums) == [], 'the stored cap passes: %s' % G.check_cap(nums))
for label, patch, word in (('no block', None, 'no guardian.hitCap'), ('off', {'enabled': False, 'share': 0.6}, 'enabled is false'),
                           ('not a boolean', {'enabled': 1, 'share': 0.6}, 'not a boolean'),
                           ('share over one', {'enabled': True, 'share': 1.5}, 'not a share'),
                           ('share 0', {'enabled': True, 'share': 0}, 'not a share'),
                           ('share drift', {'enabled': True, 'share': 0.5}, 'hit.oneHit'),
                           ('an unread key', {'enabled': True, 'share': 0.6, 'floor': 1}, 'keys the model does not read')):
    drift = copy.deepcopy(nums)
    if patch is None:
        drift.pop('cap')
    else:
        drift['cap'] = patch
    errors = G.check_cap(drift)
    check(len(errors) >= 1 and any(word in e for e in errors), 'cap drift (%s) is reported: %s' % (label, errors))

# the retention of the typical guardian: 1 with the cap off, under 1 where its hits reach the cap, 1 where they never do
hrows = G.hit_rows()
bal0 = nums['bal']
d1 = G.preload([100, 500, 1000])
t1 = nums['tiers'][0]
mons, pool = S.scaled_monsters(), G.pool_rows()
nb = G.M.dump([50])['balance']
d0 = S.dump([1007])
base1, hits1, marks1 = G.tier_inputs(1, bal0, d0, nb, mons, pool, nums)
th1 = G.tier_hits(1, nums, bal0, d1, hrows)
rows1 = G.class_rows(t1['minLevel'], bal0['split'], hits1, marks1)
ret1 = G.retention(rows1, th1['typical'], nums)
check(0.3 < ret1 < 0.9, 'tier 1 typical guardian at the entry level loses part of its damage to the cap: %.2f' % ret1)
off = dict(nums, _nocap=True)
check(G.retention(rows1, th1['typical'], off) == 1.0, '--nocap: retention 1')
off2 = dict(nums, cap={'enabled': False, 'share': 0.6})
check(G.retention(rows1, th1['typical'], off2) == 1.0, 'a switched-off cap: retention 1')
looser = dict(nums, cap={'enabled': True, 'share': 1.2})
check(G.retention(rows1, th1['typical'], looser) > ret1, 'a looser cap leaves more')
tighter = dict(nums, cap={'enabled': True, 'share': 0.3})
check(G.retention(rows1, th1['typical'], tighter) < ret1, 'a tighter cap leaves less')

# the model's columns: the cap lowers the pressure and raises the seconds to die, never the other way; the model of before is whole
for tr in (1, 5, 10):
    capped = G.run_tier(tr, False, bal0, d0, nb, mons, pool, nums, None, hrows)
    check(capped['med']['pressure'] <= capped['med0']['pressure'] + 1e-9, 'tier %d: the cap does not raise the pressure' % tr)
    check(capped['med']['burst'] >= capped['med0']['burst'] - 1e-9, 'tier %d: the cap does not shorten the seconds to die' % tr)
    check(0 < capped['ret'] <= 1.0, 'tier %d: retention in (0, 1]: %s' % (tr, capped['ret']))
    before = G.run_tier(tr, False, bal0, d0, nb, mons, pool, dict(nums, _nocap=True), None, hrows)
    check(before['ret'] == 1.0 and near(before['med']['pressure'], before['med0']['pressure']), 'tier %d: --nocap is the model of before' % tr)
    check(near(before['med0']['pressure'], capped['med0']['pressure']), 'tier %d: the uncapped numbers are the same with or without' % tr)
rt10 = G.run_tier(10, False, bal0, d0, nb, mons, pool, nums, None, hrows)
check(rt10['ret'] > 0.97, 'tier 10: its guardian is far under the cap, nothing changes: %.3f' % rt10['ret'])
rt1 = G.run_tier(1, False, bal0, d0, nb, mons, pool, nums, None, hrows)
check(rt1['med']['pressure'] < bal0['limits']['pressure']['min'], 'tier 1 with the cap is under the pressure band (the named exception)')

# the named exception: --check passes on the repo, and fails when the exception is stale or missing
res = G.compute(False, [1])
check(G.check(res) == [], 'tier 1 passes with the exception: %s' % G.check(res))
stale = copy.deepcopy(res)
stale['rows'][0]['med']['pressure'] = bal0['limits']['pressure']['min'] + 0.05
check(any('stale' in e for e in G.check(stale)), 'a stale exception is reported')
gone = copy.deepcopy(res)
gone['bal']['limits']['pressureCapped'] = []
check(any('outside' in e for e in G.check(gone)), 'without the exception tier 1 fails the band')
low = copy.deepcopy(res)
low['rows'][0]['med']['pressure'] = low['bal']['limits']['pressureCapped'][0]['min'] - 0.05
check(any('outside' in e for e in G.check(low)), 'under the exception floor still fails')

# --hits: the hit before and after the cap
rows = G.capped_table([1, 3, 8])
for r in rows:
    for tag in ('biggest', 'quantile'):
        name, before_share, after_share = r[tag]
        check(near(after_share, min(before_share, r['share'])), 'tier %d %s: after = min(before, cap share)' % (r['tier'], tag))
        check(after_share <= r['share'] + 1e-9, 'tier %d %s: never over the cap share' % (r['tier'], tag))
check(rows[1]['biggest'][1] > 1.0 and rows[1]['biggest'][2] <= 0.6 + 1e-9, 'tier 3: the outlier pool monsters were over the pool, now at the cap')
check(rows[2]['biggest'][2] == rows[2]['biggest'][1], 'tier 8: a hit under the cap is not cut')
check(all(r['die'] >= r['die0'] - 1e-9 and r['press'] <= r['press0'] + 1e-9 for r in rows), 'the table columns move the right way')

# the warn rule reads the uncapped hit: the stored levels do not move with the cap
check(G.check_warn(nums) == [], 'the warn levels still hold with the cap in the config')

if fails:
    print('guardian_model_test: %d failed' % fails)
    sys.exit(1)
print('guardian_model_test: ok')
