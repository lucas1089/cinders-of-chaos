"""Tests for boss_model.py: the shape of the model and the config.

O444 (2026-11-09): the class damage of the boss, pack and tower models is class_dps_model.py's. These tests also pin that
(`PM.damage` is `CD.dps`, the C4 frame is still there for minion_model.py and companion_model.py) and the bands of
boss_balance_config.lua (against the level median, no leader rule).

Run: python3 -I server/tools/boss_model_test.py
"""
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import boss_model as B
import class_dps_model as CD
import pack_model as PM

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


text = open(B.CONFIG, encoding='utf-8').read()
cfg = B.config()
ok(set(cfg['limits']) == set(PM.C4), 'limits: one row per class (the band or its own row)')
ok(set(cfg['packLimits']) == set(PM.C4), 'packLimits: one row per class (the band or its own row)')
ok(all(lo < hi for lo, hi in list(cfg['limits'].values()) + list(cfg['packLimits'].values())), 'rows: low below high')
ok('lead' not in cfg and 'lead =' not in text, 'O444: no leader rule (O430 retired it, the Deadeye and the Elementalist lead nothing)')
ok(cfg['bossWindows'] == {} and cfg['packWindows'] == {}, 'no window: every class is inside the band at every level')
ok(cfg['levels'] == list(B.DEFAULT_LEVELS) == [300, 500, 800, 1000, 1200], 'levels: 300, 500, 800, 1000, 1200')
ok(cfg['limits']['Sentinel'] == (0.75, 1.25) and cfg['packLimits']['Deadeye'] == (0.75, 1.25),
   'the band is the +-25% of class_dps_model.py against the level median')

# ---- one source: the three models read class_dps_model.py
for cls in PM.C4:
    for lv in (100, 500, 1000):
        ok(PM.damage(cls, lv) == CD.dps(cls, lv), 'PM.damage is CD.dps: %s at %d' % (cls, lv))
        ok(abs(PM.damage(cls, lv)[0] - CD.shipped()[0][(cls, lv)]['1t']) < 1e-6, 'CD.dps at a measured level is the model: %s %d' % (cls, lv))
ok(PM.damage('Sentinel', 1000, tune=False)[0] != PM.damage('Sentinel', 1000)[0], 'the C4 frame is still there as tune=False')
ok(PM.damage('Sentinel', 1000, frame='c4')[0] > 1.2 * CD.dps('Sentinel', 1000, rnd=False)[0], 'the C4 frame had the Sentinel 28% above class_dps_model.py before the round (1.80 of the Deadeye)')

t = B.table([300, 1000])
for i, lv in enumerate((300, 1000)):
    ok(abs(statistics.median(t[c][i][1] for c in PM.C4) - 1.0) < 1e-9, 'ratio: the median class of level %d is 1' % lv)
ok(t['Sentinel'][1][1] < 0.90 and 0.95 < t['Deadeye'][1][1] < 1.10, 'O444: the Sentinel is below the median on a boss at 1000 (was 1.80 of the Deadeye); O475: the Deadeye is at the median (1.21 before the round)')
ok(abs(t['Sentinel'][1][1] - CD.dps('Sentinel', 1000)[0] / CD.median_dps(1000)[0]) < 1e-9, 'boss ratio is the class_dps_model 1 target ratio')
ok(PM.damage('Deadeye', 300, tune=False)[0] == 1312 and PM.damage('Deadeye', 1000, tune=False)[0] == 4571, 'c4 frame: the 1-target numbers at 300 and 1000 (untuned)')
ok(PM.damage('Thief', 300, tune=False)[0] == 870 and PM.damage('Ninja', 1000, tune=False)[0] == 3565 + 35, 'c4 frame: kit change added')
ok(PM.tuning('Juggernaut', 300) == (1.0, 1.0), 'c4 frame: a class with the same factor now as then is unchanged')
ok(B.boss_dps('Elementalist', 800) == PM.damage('Elementalist', 800)[0], 'dps: no cleave, the 1-target number')
ok(B.boss_dps('Warrior', 1200) > B.boss_dps('Warrior', 1000), 'dps: grows above 1000')
ok(all(B.boss_dps(c, 300) < B.boss_dps(c, 500) < B.boss_dps(c, 800) < B.boss_dps(c, 1000) for c in PM.C4), 'dps: rises with the level')

# ---- class_dps_model.dps between and outside the anchors
for cls in ('Warrior', 'Sentinel', 'Beastmaster'):
    ok(CD.dps(cls, 60)[0] < CD.dps(cls, 100)[0] and CD.dps(cls, 0)[0] == 0, '%s: below 100 the line goes down to zero' % cls)
    a, b = CD.dps(cls, 100)[0], CD.dps(cls, 500)[0]
    ok(a < CD.dps(cls, 300)[0] < b, '%s: 300 lies between the measured 100 and 500' % cls)
    ok(abs(CD.dps(cls, 2000, rnd=False)[0] / CD.dps(cls, 1000, rnd=False)[0] - (1 + 1000 * CD.GROWTH_ABOVE_1000)) < 1e-9, '%s: above 1000 a straight line of %.3f%% a level before the round' % (cls, CD.GROWTH_ABOVE_1000 * 100))
m1, m5 = CD.median_dps(500)
ok(abs(m1 - CD.shipped()[1][500][0]) < 1e-6 and abs(m5 - CD.shipped()[1][500][1]) < 1e-6, 'median_dps at a measured level is the table median')

bad = B.outside({'A': [(1, 0.5), (2, 0.9)]}, {'A': (0.6, 1.0)})
ok(len(bad) == 1 and bad[0][1] == 0, 'outside: finds the ratio below its row')
ok(B.check() == 0, 'check: the current state passes')
broken = text.replace('limits = {\n\t},', 'limits = {\n\t\t["Deadeye"] = {0.5, 0.6},\n\t},', 1)
ok(broken != text and B.check(broken) == 1, 'check: a row the class is outside of fails')
own = B.config(broken)
ok(own['limits']['Deadeye'] == (0.5, 0.6) and own['limits']['Sentinel'] == (0.75, 1.25), 'config: a row of its own replaces the band for that class only')
narrow = text.replace('bossBand = {0.75, 1.25}', 'bossBand = {0.95, 1.05}', 1)
ok(B.check(narrow) == 1, 'check: a band narrower than the spread of the classes fails')
win = PM.window(None, 800, (0.6, 0.7), {800: (0.03, 0.0)})
ok(abs(win[0] - 0.57) < 1e-9 and win[1] == 0.7, 'window: widens the row at its level')
ok(B.outside({'A': [(1, 0.58)]}, {'A': (0.6, 0.7)}, [800], {800: (0.03, 0.0)}) == [], 'outside: the window at 800 lets 0.58 pass')
ok(len(B.outside({'A': [(1, 0.58)]}, {'A': (0.6, 0.7)}, [300], {800: (0.03, 0.0)})) == 1, 'outside: no window at 300')

p = B.pack_ratios([300, 1000])
ok(len(p) == 21 and all(len(v) == 2 for v in p.values()), 'pack ratios: 21 classes, 2 levels')
ok(abs(statistics.median(v[1] for v in p.values()) - 1.0) < 1e-9, 'pack ratios: against the median class of the level')

# pack_model's side: the bands against the level median
ok(PM.check_identity() == 0, 'pack bands: the current state passes')
pbroken = PM.identity_config(text.replace('packLimits = {\n\t},', 'packLimits = {\n\t\t["Thief"] = {0.01, 0.02},\n\t},', 1))
ok(PM.check_identity(pbroken) == 1, 'pack bands: a class outside its row fails')
ok(abs(sum(1 for c in PM.C4 if PM.VOC[c] in PM.BASE_CLEAVE) - 20) == 0, 'c4 frame, reference: a cleave row for every class but the Elementalist')
ok(PM.pack_clear(1000, True, PM.pace(), PM.monsters())[0] < PM.pack_clear(1000, True, PM.pace(), PM.monsters(), 'c4')[0],
   'the median class of today clears a late pack faster than the median class of the C4 table')

print('boss_model_test: %s' % ('FAIL' if fails else 'ok'))
sys.exit(1 if fails else 0)
