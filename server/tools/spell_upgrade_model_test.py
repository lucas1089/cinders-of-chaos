#!/usr/bin/env python3
"""Tests of spell_upgrade_model.py (O686 phase 3): the rank curve against the design's table, the power and the health curve, the
switch (off = today, on = the gain and H), the PvP half rule, the parts, the check on the committed files and on broken ones, and that
every balance model answers the --upgrades flag."""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spell_upgrade_model as SU  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
failures = 0


def check(cond, msg):
    global failures
    if not cond:
        failures += 1
        print('FAIL ' + msg)


def near(a, b, tol, msg):
    check(abs(a - b) <= tol, '%s: %s vs %s (tolerance %s)' % (msg, a, b, tol))


# ---- the rank curve: the design's cost table (docs/SPELL_UPGRADES.md 1.4) and the hours of 5.3
design_costs = [0.06, 0.16, 0.29, 0.44, 0.62, 0.81, 1.02, 1.25, 1.49, 1.75, 2.01, 2.29, 2.59, 2.89, 3.21, 3.53, 3.87, 4.22, 4.57, 4.94]
costs = SU.rank_costs()
check(len(costs) == 20, '20 ranks')
for r, (a, b) in enumerate(zip(costs, design_costs), 1):
    near(a, b, 0.011, 'cost of rank %d' % r)
near(sum(costs), 42.0, 1e-9, 'ranks 1 to 20 cost 42 SP')
near(SU.rank_of_sp(0.0), 0.0, 1e-12, 'no SP, rank 0')
near(SU.rank_of_sp(costs[0]), 1.0, 1e-9, 'the cost of rank 1 is rank 1')
near(SU.rank_of_sp(costs[0] + costs[1] / 2), 1.5, 1e-9, 'half of rank 2')
near(SU.rank_of_sp(1000), 20.0, 1e-12, 'capped at 20')
# the design's table of 5.3: hunting hours in, rank of the main spell
for lv, hours, rank in ((100, 1.1, 1.8), (200, 3.8, 3.2), (300, 9, 4.8), (500, 24.7, 7.4), (1000, 117, 14.3), (1600, 239, 19.2), (2000, 307, 20)):
    near(SU.hours_in(lv), hours, max(0.5, hours * 0.01), 'hunting hours at level %d' % lv)
    near(SU.main_rank(lv), rank, 0.45, 'main rank at level %d' % lv)
last = -1
for lv in range(8, 2600, 25):
    check(SU.main_rank(lv) >= last - 1e-9, 'the main rank never falls at level %d' % lv)
    last = SU.main_rank(lv)
first20 = next(L for L in range(8, 2600) if SU.main_rank(L) >= 19.999)
check(1500 <= first20 <= 2000, 'rank 20 at level %d, inside the owner\'s window 1500 to 2000' % first20)

# ---- the power P: the design's first table (combos 5%) is reproduced within 2% (the old script was never committed)
b = SU.balance_config()
saved = b['combos']['total']
b['combos']['total'] = 0.05
for lv, p in ((100, 1.019), (200, 1.035), (300, 1.071), (400, 1.095), (500, 1.119), (600, 1.147), (700, 1.189), (800, 1.211), (1000, 1.252),
              (1300, 1.284), (1600, 1.330), (2000, 1.365), (2500, 1.469)):
    near(SU.power(lv), p, 0.02, 'P at level %d with the combos of the first design' % lv)
b['combos']['total'] = saved
near(SU.power(2500) / SU.power(2500, {'rank': True, 'forms': True, 'combos': True, 'awakening': False}), 1.06, 0.001, 'awakening at 2500 is 6%')
near(SU.parts_at(2500)['rank'], 1.246, 0.005, 'rank part at the cap is +24.6%')
near(SU.parts_at(2500)['forms'], 1.06, 1e-9, 'Forms part at the cap is +6%')
for lv in (100, 500, 1000, 2500):
    check(SU.power(lv, {'rank': True, 'forms': False, 'combos': False, 'awakening': False}) <= SU.power(lv), 'parts only add at level %d' % lv)
    check(SU.derived_health(lv, {'rank': True, 'forms': True, 'combos': False, 'awakening': False}) <= SU.derived_health(lv), 'fewer parts, not more H')
last = 0
for lv in range(100, 2600, 50):
    check(SU.power(lv) >= last - 1e-6, 'P does not fall at level %d' % lv)
    last = SU.power(lv)

# ---- the health curve H
for lv, h in ((100, 1.02), (200, 1.03), (300, 1.06), (500, 1.10), (1000, 1.20), (2000, 1.29), (2500, 1.38)):
    near(SU.committed_health()[[int(x) for x, _ in SU.committed_health()].index(lv)][1], h, 0.03, 'H at %d against the first design' % lv)
near(SU.health_committed(50), 1.0, 1e-12, 'below level 100 x1')
near(SU.health_committed(150), 1.025, 1e-9, 'between points')
near(SU.health_committed(9999), SU.health_committed(2500), 1e-12, 'flat above the last point')
check(SU.problems() == [], 'the committed files pass --check: %s' % SU.problems())

# ---- the switch
SU.set_mode(False)
check(not SU.active(), 'off')
check(SU.gain('Warrior', 1000) == 1.0 and SU.health(1000) == 1.0 and SU.heal_gain(1000) == 1.0 and SU.pvp_gain(1000) == 1.0, 'off: everything is 1')
check(SU.median_gain(1000) == 1.0 and SU.slack(1000) == 0.0 and SU.widen('pvpBurst', 'burstMax') == 0.0, 'off: no gain, no slack, no widening')
SU.set_mode(True)
check(SU.active(), 'on')
check(SU.gain('Warrior', 1000) > 1.1, 'on: a Warrior at level 1000 has a gain')
check(SU.gain('Lich', 1000) > SU.gain('Shadowfist', 1000), 'on: the class with more spell share gains more')
check(SU.gain('Warrior', 1000, 5) > SU.gain('Warrior', 1000, 1), 'on: five targets are more spell')
near(SU.health(1000), 1.21, 1e-9, 'on: H at 1000')
check(SU.health(50) == 1.0, 'on: below 100 x1')
check(SU.heal_gain(1000) > 1.1, 'on: a heal gain')
check(SU.heal_gain(1000) < SU.gain('Warrior', 1000, 5) + 0.05, 'on: heals gain less than damage')
check(SU.widen('pvpBurst', 'burstMax') > 0, 'on: the named widening')
check(SU.widen('nothing', 'burstMax') == 0.0, 'on: an unknown row widens nothing')
# the half rule
full = SU.gain('Warrior', 1000)
with SU.pvp():
    half = SU.gain('Warrior', 1000)
    half_heal = SU.heal_gain(1000)
    check(SU.pvp_on(), 'pvp context on')
    near(SU.gain('Warrior', 2500), 1 + SU.spell_share('Warrior', 2500, 1) * (SU.rank_power(SU.avg_rank(2500), pvp=True) * SU.forms_power(SU.avg_rank(2500), pvp=True) - 1),
         1e-12, 'pvp: rank and Forms only, no awakening, no combos at 2500')
check(not SU.pvp_on(), 'pvp context restored')
check(1.0 < half < full, 'pvp gain is between 1 and the full gain')
near((half - 1) / (full - 1), 0.5, 0.2, 'pvp gain is about half of the full one at 1000 (no combos)')
check(1.0 < half_heal < SU.heal_gain(1000), 'pvp heal gain is between 1 and the full one')
check(SU.pvp_gain(1000) < SU.median_gain(1000), 'pvp factor below the typical gain')
# forced() and from_argv
with SU.forced(False):
    check(not SU.active() and SU.health(1000) == 1.0, 'forced(False) is today inside an upgrades run')
check(SU.active(), 'forced() restores')
SU.set_mode(None)
rest = SU.from_argv(['--check', '--upgrades', '--levels', '1'])
check(rest == ['--check', '--levels', '1'] and SU.active(), '--upgrades is taken out of the arguments and sets the mode')
rest = SU.from_argv(['--today'])
check(rest == [] and not SU.active(), '--today sets it off')
SU.set_mode(None)
check('ON' in SU.banner() or 'off' in SU.banner(), 'the banner')

# ---- kill times of the typical character, the design's promise (3%)
lim = SU.balance_config()['limits']
for lv in SU.CHECK_LEVELS:
    check(abs(SU.kill_time_ratio(lv, 0) - 1) <= lim['killTime'], 'kill time at level %d within %.0f%%' % (lv, lim['killTime'] * 100))
    check(abs(SU.kill_time_ratio(lv, 1) - 1) <= lim['killTimeOneTarget'], 'boss kill time at level %d' % lv)
    check(abs(SU.kill_time_ratio(lv, 5) - 1) <= lim['killTimeFiveTargets'], 'pack kill time at level %d' % lv)

# ---- the character with no upgrades (design 5.6)
near(SU.no_upgrades_xp(1000), 17, 1.2, 'no upgrades: experience an hour at level 1000')
near(SU.no_upgrades_xp(2500), 27, 1.2, 'no upgrades: experience an hour at the cap')
check(SU.no_upgrades_hours(500) < SU.no_upgrades_hours(1000) < SU.no_upgrades_hours(2000), 'no upgrades: the hours climb')

# ---- a broken curve is refused
real = SU.committed_health
SU.committed_health = lambda: [(100, 1.02), (1000, 1.35), (2500, 1.38)]
bad = SU.problems()
check(any('level 1000' in x for x in bad), 'a health curve off the derivation is refused')
SU.committed_health = lambda: [(100, 1.02), (500, 1.10), (1000, 1.05), (2500, 1.38)]
check(any('falls' in x for x in SU.problems()), 'a falling health curve is refused')
SU.committed_health = real
real_typ = SU.committed_typical
SU.committed_typical = lambda: [(lv, 1.5) for lv in SU.CHECK_LEVELS]
check(any('typical gain' in x for x in SU.problems()), 'a typical gain table off the derivation is refused')
SU.committed_typical = real_typ
b['classShare'] = 0.5
check(any('class share' in x or 'health at level' in x for x in SU.problems()), 'a class share far from the measured one is refused')
b['classShare'] = 0.80
check(SU.problems() == [], 'restored')

# ---- the derivation prints what the config holds
out = SU.derive()
check(all(('{%d, %.2f}' % (int(lv), v)) in out for lv, v in SU.committed_health()), '--derive prints the committed health curve')
check(SU.derive({'rank': True, 'forms': True, 'combos': False, 'awakening': False}) != out, 'a release with fewer parts gets another curve')

# ---- every balance model answers --upgrades
MODELS = ('class_dps_model', 'pack_model', 'boss_model', 'boss_length_model', 'tower_model', 'guardian_model', 'survival_model', 'pvp_model',
          'descent_model', 'waystone_endgame_model', 'pinnacle_model', 'greater_rift_model', 'minion_model', 'companion_model',
          'card_set_model', 'spell_mastery_model', 'weapon_family_model', 'mainquest_boss_model')
for m in MODELS:
    text = open(os.path.join(HERE, m + '.py'), encoding='utf-8').read()
    check('SU.from_argv(argv)' in text, '%s.py reads the --upgrades flag (SU.from_argv)' % m)
    check('--upgrades' in text, '%s.py documents --upgrades' % m)
for m in ('rift_layout_model.lua', 'progression_model.lua'):
    text = open(os.path.join(HERE, m), encoding='utf-8').read()
    check('--upgrades' in text, '%s reads the --upgrades flag' % m)
check('--no-upgrades' in open(os.path.join(HERE, 'progression_model.lua'), encoding='utf-8').read(), 'progression_model.lua has --no-upgrades')

# ---- a model run in a process of its own, both modes (the caches of the models are per process)
for flags in ([], ['--upgrades']):
    r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'boss_model.py'), '--check'] + flags, capture_output=True, text=True, timeout=600)
    check(r.returncode == 0 and 'boss check: ok' in r.stdout, 'boss_model.py --check %s: %s' % (' '.join(flags), (r.stdout + r.stderr)[-300:]))
    check(('spell upgrades: ON' in r.stdout) == bool(flags), 'the banner follows the flag')

print('spell_upgrade_model_test: %s' % ('FAILED %d' % failures if failures else 'ok'))
sys.exit(1 if failures else 0)
