#!/usr/bin/env python3
"""Tests of weapon_family_model.py (O454): the config parser against the Lua file, the formulas on synthetic configs, the limits, the
classes it covers, and the shipped state.

usage: python3 -I server/tools/weapon_family_model_test.py   (luajit or lua5.3 for the parser check)
"""
import copy
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import weapon_family_model as W  # noqa: E402

fails = 0


def ok(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + msg)


def near(a, b, tol, msg):
    ok(abs(a - b) <= tol, '%s: %r ~ %r' % (msg, a, b))


c = W.config()

# ---- the parser reads what the game reads
for lua in ('luajit', 'lua5.3'):
    if shutil.which(lua):
        code = ('local c = dofile("%s"); local f = c.families; io.write(string.format("%%.6f %%.6f %%.6f %%.6f %%.6f %%.6f %%d %%.6f %%.6f", '
                'f.sword.single, f.axe.single, f.club.single, f.sword.tempo.edge, f.axe.cleave.pool, f.club.daze.chance, '
                'f.axe.cleave.maxTargets, f.club.daze.bossSlow, f.club.daze.bossChance))' % W.CONFIG)
        r = subprocess.run([lua, '-e', code], capture_output=True, text=True)
        got = r.stdout.split()
        want = [c['single']['sword'], c['single']['axe'], c['single']['club'], c['edge'], c['pool'], c['chance'], c['maxTargets'],
                c['bossSlow'], c['bossChance']]
        ok(r.returncode == 0 and len(got) == 9 and all(abs(float(a) - float(b)) < 1e-6 for a, b in zip(got, want)),
           '%s reads the same numbers as the parser: %r %r' % (lua, got, want))
ok(c['vocations'] == {4, 8, 14, 11, 12, 13, 23, 24, 25}, 'the vocations of the Warrior, Thief and Templar lines')
ok(not ({17, 18, 19} & c['vocations']), 'the Monk line is not in it')
ok(W.classes(c) == ['Warrior', 'Juggernaut', 'Berserker', 'Thief', 'Ninja', 'Samurai', 'Templar', 'Inquisitor', 'Sentinel'],
   'the nine classes: %r' % W.classes(c))

# ---- formulas
one = W.one_target(c)
near(one['sword'], c['single']['sword'] * (1 + c['edge']), 1e-12, 'the sword at full stacks has its edge')
near(one['axe'], c['single']['axe'], 1e-12, 'the axe pays')
near(W.axe_gain(c, 4), c['single']['axe'] * (1 + c['pool']) - 1, 1e-12, 'the axe on 4 neighbours')
near(W.axe_gain(c, 1), W.axe_gain(c, 8), 1e-12, 'the pool: the same with one neighbour as with eight')
ok(W.axe_gain(c, 0) < 0, 'alone the axe only pays')
near(W.axe_gain(c, 30), W.axe_gain(c, c['maxTargets']), 1e-12, 'more neighbours than the maximum: the maximum')
near(W.auto_share({'auto_share_1t': 0.5, 'auto_share_5t': 0.2}, 1.0, False), 0.5, 1e-12, 'no swing rate gain: the measured share')
near(W.auto_share({'auto_share_1t': 0.5, 'auto_share_5t': 0.2}, 2.0, False), 0.5 * 2 / (0.5 + 1.0), 1e-12, 'a gain of 2 on half of it')
ok(W.auto_share({'auto_share_1t': 0.5, 'auto_share_5t': 0.2}, 1.4, True) > 0.2, 'the gain raises the share')

# ---- the shipped state
ok(W.problems(c) == [], 'the shipped numbers pass: %r' % W.problems(c))
rows = W.class_rows(c)
ok(len(rows) == 27, '9 classes x 3 levels')
worst = max(r['axe5'] for r in rows.values())
ok(0.02 < worst < W.LIMITS['classFiveTargets'], 'the axe gives the best class a few percent on 5 targets, under the limit (%.3f)' % worst)
ok(all(abs(r[f + '1']) <= W.LIMITS['classOneTarget'] for r in rows.values() for f in ('sword', 'axe', 'club')),
   'no family moves a class by more than 3% on 1 target')
ok(all(r['sword1'] > 0 and r['axe1'] < 0 and r['club1'] < 0 for r in rows.values()), 'the sword gains, the axe and the club pay')
tab = W.table(c)
ok(tab.count('\n| ') >= 27, 'the table has the 27 rows')

# ---- the limits catch a bad config
def with_change(**kw):
    d = copy.deepcopy(c)
    for k, v in kw.items():
        if k == 'single':
            d['single'].update(v)
        else:
            d[k] = v
    return W.problems(d)


ok(with_change() == [], 'a copy of the shipped config passes')
ok(any('axe' in p and 'neighbours' in p for p in with_change(pool=0.30)), 'a pool of 30% fails (the axe gains over 12%)')
ok(any('5 targets' in p and 'class damage' in p for p in with_change(pool=0.30)), 'and the class gain on 5 targets')
ok(any('axe' in p and 'one target' in p for p in with_change(single={'axe': 0.90})), 'an axe at 0.90 fails on one target')
ok(any('highest' in p for p in with_change(single={'axe': 0.96, 'club': 0.96}, edge=0.03)), 'a spread over 5% fails')
ok(any('sword' in p and 'one target' in p for p in with_change(edge=0.06)), 'a sword edge of 6% fails')
ok(any('must pay' in p for p in with_change(single={'axe': 1.0})), 'an axe that does not pay fails')
ok(any('club' in p and 'held' in p for p in with_change(stunMs=2000)), 'a long stun fails the uptime')
ok(any('boss' in p for p in with_change(bossImmuneMs=1000)), 'a boss slowed most of the time fails')
ok(any('boss loses' in p for p in with_change(bossSlow=0.9, bossImmuneMs=4000)), 'a boss slow that costs it speed fails')

print('weapon_family_model_test: %d failures' % fails)
sys.exit(1 if fails else 0)
