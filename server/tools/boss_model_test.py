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
ok(set(cfg['packLimits']) == set(PM.C4), 'packLimits: one row per class')
ok(all(lo < hi for lo, hi in list(cfg['limits'].values()) + list(cfg['packLimits'].values())), 'rows: low below high')
ok(cfg['lead'] == 0.08 and set(cfg['bossWindows']) == {800} and set(cfg['packWindows']) == {800, 1200}, 'lead and windows read')
ok(cfg['levels'] == list(B.DEFAULT_LEVELS), 'levels: 300, 800, 1000, 1200')

t = B.table([300, 1000])
ok(abs(t['Deadeye'][0][1] - 1.0) < 1e-9 and abs(t['Deadeye'][1][1] - 1.0) < 1e-9, 'ratio: Deadeye is 1')
ok(t['Deadeye'][0][0] == 1312 and t['Deadeye'][1][0] == 4571, 'dps: the C4 1-target numbers at 300 and 1000')
ok(PM.damage('Thief', 300, tune=False)[0] == 870 and PM.damage('Ninja', 1000, tune=False)[0] == 3565 + 35, 'dps: kit change added')
ok(abs(t['Thief'][0][0] - 870 * PM.tuning('Thief', 300)[0]) < 1e-6, 'dps: the class identity pass multiplied in (class damage factor now / then)')
ok(PM.tuning('Deadeye', 300) == (1.0, 1.0) and PM.tuning('Deadeye', 1200) == (1.0, 1.0), 'tuning: the Deadeye, the reference, is unchanged')
ok(B.boss_dps('Elementalist', 800) == PM.damage('Elementalist', 800)[0], 'dps: no cleave, the 1-target number')
ok(B.boss_dps('Warrior', 1200) > B.boss_dps('Warrior', 1000), 'dps: grows above 1000')

bad = B.outside({'A': [(1, 0.5), (2, 0.9)]}, {'A': (0.6, 1.0)})
ok(len(bad) == 1 and bad[0][1] == 0, 'outside: finds the ratio below its row')
ok(B.check() == 0, 'check: the current state passes')
broken = open(B.CONFIG, encoding='utf-8').read().replace('["Deadeye"] = {0.98, 1.02}', '["Deadeye"] = {0.5, 0.6}', 1)
ok(B.check(broken) == 1, 'check: a row the class is outside of fails')
lead = open(B.CONFIG, encoding='utf-8').read().replace('lead = 0.08', 'lead = 0.30', 1)
ok(B.check(lead) == 1, 'check: a leader less than the lead ahead fails')
win = PM.window(None, 800, (0.6, 0.7), {800: (0.03, 0.0)})
ok(abs(win[0] - 0.57) < 1e-9 and win[1] == 0.7, 'window: widens the row at its level')
ok(B.outside({'A': [(1, 0.58)]}, {'A': (0.6, 0.7)}, [800], {800: (0.03, 0.0)}) == [], 'outside: the window at 800 lets 0.58 pass')
ok(len(B.outside({'A': [(1, 0.58)]}, {'A': (0.6, 0.7)}, [300], {800: (0.03, 0.0)})) == 1, 'outside: no window at 300')

p = B.pack_ratios([300, 1000])
ok(len(p) == 21 and all(len(v) == 2 for v in p.values()), 'pack ratios: 21 classes, 2 levels')

# pack_model's side: the bands and the area lead
ok(PM.check_identity() == 0, 'pack bands: the current state passes')
pbroken = PM.identity_config(open(PM.BALANCE, encoding='utf-8').read().replace('["Thief"] = {0.80, 0.86}', '["Thief"] = {0.5, 0.6}', 1))
ok(PM.check_identity(pbroken) == 1, 'pack bands: a class outside its row fails')
plead = PM.identity_config(open(PM.BALANCE, encoding='utf-8').read().replace('lead = 0.08', 'lead = 0.30', 1))
ok(PM.check_identity(plead) == 1, 'area lead: an Elementalist less than the lead ahead fails')
ok(abs(sum(1 for c in PM.C4 if PM.VOC[c] in PM.BASE_CLEAVE) - 20) == 0, 'reference: a cleave row for every class but the Elementalist')

print('boss_model_test: %s' % ('FAIL' if fails else 'ok'))
sys.exit(1 if fails else 0)
