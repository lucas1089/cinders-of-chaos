#!/usr/bin/env python3
"""Tests of waystone_endgame_model.py (O666): the helpers, the closed-form derivation, the committed deep factors and band boss files, and
that --check fails when a committed number moves. Run: python3 -I server/tools/waystone_endgame_model_test.py (needs luajit)."""
import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import waystone_endgame_model as M  # noqa: E402

fails = 0


def check(cond, label):
    global fails
    if not cond:
        fails += 1
        print('FAIL', label)


# helpers
check(M.lin([(0, 0), (10, 100)], 5) == 50, 'lin: between')
check(M.lin([(0, 0), (10, 100)], 20) == 100, 'lin: flat above')
check(M.lin([(5, 7), (10, 100)], 1) == 7, 'lin: flat below')
check(abs(M.exp_for_level(2) - 100.0) < 1e-9, 'experience of level 2 is 100')
check(M.exp_for_level(3508) > 7e11, 'experience of the top level')
check(M.scale({'healthPerLevel': 0.0074, 'damagePerLevel': 0.0015}, 540, 540)['health'] == 1.0, 'scale: same level')

num = M.numbers()
check(len(num['tiers']['tiers']) == 25, '25 tiers read')
check(M.deep_factor(num, 15, 'health') == 1.0, 'no deep factor at XV')
check(M.deep_factor(num, 16, 'health') == num['tiers']['deep']['health']['base'], 'deep health at XVI is the base')

# the derivation lands on its targets
lim = num['bal']['limits']
hf, df, xf = M.derive_deep(num, 20)
row = M.run_row(num, 20, (hf, df, xf))
check(abs(row['clear'] - lim['deepClearSeconds']) < 2, 'derived health: the clear time target (%.1f)' % row['clear'])
check(abs(row['sustain'] - lim['deepSustain']) < 0.02, 'derived damage: the sustain target (%.3f)' % row['sustain'])
check(abs(row['ratio'] - lim['deepExpRatio']) < 0.01, 'derived experience: the hunt ratio (%.3f)' % row['ratio'])

# the committed numbers pass
rows = [M.run_row(num, t) for t in range(1, 26)]
bands = [M.band_row(num, b) for b in num['endgame']['bandBosses']]
errs = M.check(num, rows, bands)
check(errs == [], 'the committed numbers pass --check: %s' % errs[:3])

# a number that moves fails
bad = copy.deepcopy(num)
bad['tiers']['deep']['health']['base'] = 1.0
check(any('deep health' in e for e in M.check(bad, [M.run_row(bad, t) for t in range(1, 26)], bands)), 'a deep health factor of 1 fails')
bad = copy.deepcopy(num)
bad['endgame']['corrupt']['breakChance'] = 60
check(any('break chance' in e for e in M.check(bad, rows, bands)), 'a break chance of 60 fails')
bad = copy.deepcopy(num)
bad['bal']['limits']['clearSeconds'] = [900, 1000]
check(any('plain run takes' in e for e in M.check(bad, rows, bands)), 'a clear time limit above the runs fails')

# the band boss files agree with what the tool would write
for b in num['endgame']['bandBosses']:
    hp, melee = M.fit_boss(num, b)
    xml = M.read_boss(b['file'])
    check(xml is not None and abs(xml['health'] - hp) <= 1000, '%s: the committed health is the fitted one' % b['monster'])
    text = M.boss_xml(num, b, hp, melee)
    check('name="%s"' % b['monster'] in text and 'isboss="1"' in text, '%s: the template' % b['monster'])

print('waystone_endgame_model_test: %s' % ('FAIL (%d)' % fails if fails else 'OK'))
sys.exit(1 if fails else 0)
