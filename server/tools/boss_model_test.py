"""Tests for boss_model.py: the shape of the model and the config.

Run: python3 -I server/tools/boss_model_test.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import boss_model as B
import pack_model as PM

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


cfg = B.config()
ok(set(cfg['limits']) == set(PM.C4), 'limits: one row per class')
ok(set(cfg['proposed']) == set(PM.C4), 'proposed: one row per class')
ok(all(lo < hi for lo, hi in list(cfg['limits'].values()) + list(cfg['proposed'].values())), 'rows: low below high')
ok(cfg['levels'] == list(B.DEFAULT_LEVELS), 'levels: 300, 800, 1000, 1200')

t = B.table([300, 1000])
ok(abs(t['Deadeye'][0][1] - 1.0) < 1e-9 and abs(t['Deadeye'][1][1] - 1.0) < 1e-9, 'ratio: Deadeye is 1')
ok(t['Deadeye'][0][0] == 1312 and t['Deadeye'][1][0] == 4571, 'dps: the C4 1-target numbers at 300 and 1000')
ok(t['Thief'][0][0] == 870 and t['Ninja'][1][0] == 3565 + 35, 'dps: kit change added')
ok(B.boss_dps('Elementalist', 800) == PM.damage('Elementalist', 800)[0], 'dps: no cleave, the 1-target number')
ok(B.boss_dps('Warrior', 1200) > B.boss_dps('Warrior', 1000), 'dps: grows above 1000')

bad = B.outside({'A': [(1, 0.5), (2, 0.9)]}, {'A': (0.6, 1.0)})
ok(len(bad) == 1 and bad[0][1] == 0, 'outside: finds the ratio below its row')
ok(B.check() == 0, 'check: the current state passes')
broken = open(B.CONFIG, encoding='utf-8').read().replace('["Deadeye"] = {0.97, 1.03}', '["Deadeye"] = {0.5, 0.6}', 1)
ok(B.check(broken) == 1, 'check: a row the class is outside of fails')

p = B.pack_ratios([300, 1000])
ok(len(p) == 21 and all(len(v) == 2 for v in p.values()), 'pack ratios: 21 classes, 2 levels')

print('boss_model_test: %s' % ('FAIL' if fails else 'ok'))
sys.exit(1 if fails else 0)
