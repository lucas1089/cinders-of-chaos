#!/usr/bin/env python3
"""Tests of boss_length_model.py (O475): the derivation and the check on synthetic changes.
usage: python3 -I server/tools/boss_length_model_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import boss_length_model as B  # noqa: E402

fails = 0


def ok(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + msg)


ok(abs(B.kept('boss') - 0.60) < 1e-9 and abs(B.kept('normal') - 0.80) < 1e-9, 'a boss lets 0.60 through, a normal monster 0.80')
rows = B.dps_table()
ok([lv for lv, _ in rows] == list(B.DPS_LEVELS) and 850 in B.DPS_LEVELS, 'the table has the 850 row')
ok(all(b[1] > a[1] for a, b in zip(rows, rows[1:])), 'the damage rises with the level')
ok(abs(B.table_dps(rows, 850) - rows[B.DPS_LEVELS.index(850)][1]) < 1e-6, 'table_dps is the row at a row')
ok(abs(B.table_dps(rows, 50) - rows[0][1] / 2) < 1e-6, 'below the first row: scaled by the level')
ok(B.table_dps(rows, 5000) == rows[-1][1], 'above the last row: flat')
hm = B.health_mult(rows, 825, 900, 14800)
ok(abs(hm * 14800 * (1 + 0.0074 * 900) / B.table_dps(rows, 825) - B.BOSS_SECONDS) < 1e-6, 'healthMult gives the boss 150 s')
(d1, e1), (d5, e5) = B.rift_fit()
ok(1.0 < e1 < 1.6 and 1.0 < e5 < 1.6 and d1 > 1000 and d5 > d1, 'the rift fit is a power law above the old numbers (%.0f %.2f %.0f %.2f)' % (d1, e1, d5, e5))
health, factor = B.omen_factor()
ok(abs(health - (B.one_target(1000) * 0.75 - 380) * 318) < 1e-6 and factor > 1, 'the Omen guardian has 318 s at level 1000')
ok(B.problems() == [], 'the committed numbers are the derivation: %s' % B.problems()[:3])
# a number off by more than the tolerance is found
real = B.committed_mults
B.committed_mults = lambda: dict(real(), vault=real()['vault'] * 1.1)
ok(any('vault healthMult' in b for b in B.problems()), 'a healthMult 10% off is reported')
B.committed_mults = real
if fails:
    print('boss_length_model_test: %d failed' % fails)
    sys.exit(1)
print('boss_length_model_test: ok')
