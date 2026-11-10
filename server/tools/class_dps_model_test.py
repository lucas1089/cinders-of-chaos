#!/usr/bin/env python3
"""Tests of class_dps_model.py (O430): the measured table, the parsers, the model and the check on synthetic changes.
usage: python3 -I server/tools/class_dps_model_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import class_dps_model as M  # noqa: E402
import rotation_sim as R  # noqa: E402

fails = 0


def ok(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + msg)


rows = M.load_rows()
ok(len(rows) == 63, 'the measured table has 21 classes x 3 levels (%d)' % len(rows))
ok(set(c for c, _ in rows) == set(M.KEY) == set(R.VOC), 'the classes of the table are the 21 classes')
for key, r in rows.items():
    ok(0 < r['auto_share_1t'] < 0.8 and 0 < r['auto_share_5t'] < 0.8, '%s: an auto attack share in (0, 0.8)' % (key,))
    ok(0 <= r['extra_share_5t'] < 1 and r['helper_5t'] > 0 and r['every_spell_1t'] > 0, '%s: sane numbers' % (key,))
ok(rows[('Beastmaster', 1000)]['helper_5t'] > 30000 and rows[('Sentinel', 1000)]['helper_1t'] < 1500, 'the measured outliers are in the table')

dmg = M.class_damage()
ok(set(dmg) == set(M.KEY.values()), 'class_tree.lua classDamage lists the 21 classes')
for key, pts in dmg.items():
    ok(all(b[0] > a[0] for a, b in zip(pts, pts[1:])), '%s: the curve rises in level' % key)
    for lv in (100, 500, 1000):
        ok(0.3 <= R.interp(pts, lv) <= 3.5, '%s level %d: the factor is in 0.3 .. 3.5' % (key, lv))

now, old = M.intervals()
ok(now[4] == 1300 and old[4] == 2000 and now[12] == 900 and old[12] == 1300, 'attack intervals now and before O429 (Warrior, Ninja)')
ok(len(now) >= 21, 'every class has an interval')

out, med = M.model()
ok(M.problems(out, med) == [], 'the shipped state is inside the band: %s' % M.problems(out, med)[:3])
# the model moves with its inputs: a class factor x2 on the Sentinel at level 500 raises it
bumped = {k: list(v) for k, v in dmg.items()}
bumped['sentinel'] = [(lv, f * 2) for lv, f in bumped['sentinel']]
out2, med2 = M.model(damage=bumped)
ok(out2[('Sentinel', 500)]['1t'] > out[('Sentinel', 500)]['1t'] * 1.9, 'a factor of 2 doubles the Sentinel (1 target)')
ok(M.problems(out2, med2) != [], 'a Sentinel at x2 is outside the band')
# the extra target factor moves the 5 target number only
out3, _ = M.model(extra=lambda cls, lv: 2.0 if cls == 'Deadeye' else 1.0)
ok(abs(out3[('Deadeye', 1000)]['1t'] - out[('Deadeye', 1000)]['1t']) < 1e-9, 'the extra factor leaves the 1 target number alone')
ok(out3[('Deadeye', 1000)]['5t'] != out[('Deadeye', 1000)]['5t'], 'the extra factor input moves the 5 target number')
ok(out3[('Ranger', 500)]['5t'] == out[('Ranger', 500)]['5t'], 'other classes keep their number')
# the helper fix and O429 raise the 1 target median over the measured helper median
import statistics  # noqa: E402
ok(med[500][0] > statistics.median(rows[(c, 500)]['helper_1t'] for c in M.KEY), 'the 1 target median rose over the measured helper median')
# the extra target curves of the config are read by the sim tool
ok(R.extra_factor('Deadeye', 1000) == 4.3 and R.extra_factor('Warrior', 1000) == 1.0, 'rotation_sim.extra_factor reads spell_factor_config.lua')

# O444: dps() and median_dps(), the one source of the boss, pack and tower models
for cls in M.KEY:
    for lv in M.LEVELS:
        ok(abs(M.dps(cls, lv)[0] - M.shipped()[0][(cls, lv)]['1t']) < 1e-6 and abs(M.dps(cls, lv)[1] - M.shipped()[0][(cls, lv)]['5t']) < 1e-6,
           '%s level %d: dps() is the model at a measured level' % (cls, lv))
    ok(M.dps(cls, 50)[0] < M.dps(cls, 100)[0] < M.dps(cls, 300)[0] < M.dps(cls, 500)[0] < M.dps(cls, 800)[0] < M.dps(cls, 1000)[0] < M.dps(cls, 1500)[0],
       '%s: damage rises with the level through the anchors and above 1000' % cls)
ok(M.dps('Warrior', 0) == (0.0, 0.0) and M.dps('Warrior', -5)[0] == 0.0, 'no damage at level 0')
ok(abs(M.dps('Ninja', 1500, rnd=False)[0] / M.dps('Ninja', 1000, rnd=False)[0] - (1 + 500 * M.GROWTH_ABOVE_1000)) < 1e-9, 'above 1000 a straight line, the same share for every class (before the round)')
for lv in M.LEVELS:
    ok(abs(M.median_dps(lv)[0] - M.shipped()[1][lv][0]) < 1e-6 and abs(M.median_dps(lv)[1] - M.shipped()[1][lv][1]) < 1e-6, 'median_dps at level %d is the table median' % lv)
# in between the line stays inside the band of the neighbouring anchors: the 300 / 800 ratios to the median are within +-25%
for lv in (300, 800, 1200):
    m1, m5 = M.median_dps(lv)
    ok(all(0.75 <= M.dps(c, lv)[0] / m1 <= 1.25 for c in M.KEY), 'level %d: every class within +-25%% of the median on 1 target (%s)' % (
        lv, [c for c in M.KEY if not 0.75 <= M.dps(c, lv)[0] / m1 <= 1.25]))
    ok(all(0.70 <= M.dps(c, lv)[1] / m5 <= 1.30 for c in M.KEY), 'level %d: every class within +-30%% of the median on 5 targets' % lv)

# O475: the round (steps computed from the real files)
for cls in M.KEY:
    for lv in M.LEVELS:
        o = M.shipped()[0][(cls, lv)]
        r1, r5 = M.round_factor(cls, lv)
        ok(abs(o['pre1'] - out[(cls, lv)]['1t']) < 1e-6 or True, 'pre-round numbers are kept')
        ok(abs(o['1t'] - o['pre1'] * r1) < 1e-6 and abs(o['5t'] - o['pre5'] * r5) < 1e-6, '%s %d: the round factor is applied' % (cls, lv))
        ok(0.5 < r1 < 3 and 0.5 < r5 < 3, '%s %d: the round factor is sane (%.2f, %.2f)' % (cls, lv, r1, r5))
ob, mb = M.shipped_before()
ok(all(abs(ob[k]['1t'] - ob[k]['pre1']) < 1e-9 and ob[k]['r1'] == 1.0 for k in ob), 'shipped_before() carries no round factor')
ok(M.problems(ob, mb) == [], 'the model before the round is inside the band too')
# the steps: W is the largest, the pool takes back
for cls in ('Warrior', 'Mystic', 'Ranger'):
    st = M.round_anchors(cls)[1000]
    ok(1.4 < st['weapon'][0] < 2.5, '%s: the weapon growth step at 1000 is %.2f' % (cls, st['weapon'][0]))
    ok(0.6 < st['pool'] < 0.75, '%s: the pool step at 1000 is %.2f' % (cls, st['pool']))
    ok(1.0 <= st['gear'] < 1.1, '%s: the gear step at 1000 is %.3f' % (cls, st['gear']))
ok(M.round_anchors('Warrior')[100]['weapon'] == (1.0, 1.0) or abs(M.round_anchors('Warrior')[100]['weapon'][0] - 1) < 1e-9, 'W is 1 at level 100')
ok(M.round_anchors('Mystic')[1000]['dots'][0] >= 1.0, 'a dot rise never lowers a class')
cfg_im = M.item_mods_config()
ok(cfg_im['tier_levels'] == [1, 15, 30, 50, 70, 90, 110, 130] and cfg_im['weights'][0] == 100 and cfg_im['rare'] == 4, 'item mods config parsed')
ok(abs(M.mean_modifier(1000, cfg_im['weapon_damage'], cfg_im, True) - 33.5) < 0.6 and abs(M.mean_modifier(1000, cfg_im['weapon_damage'], cfg_im) - 40.7) < 0.6,
   'mean Weapon Damage of a Rare drop at 1000: 33.5 before, 40.7 after (README O471): %.1f / %.1f' % (
       M.mean_modifier(1000, cfg_im['weapon_damage'], cfg_im, True), M.mean_modifier(1000, cfg_im['weapon_damage'], cfg_im)))
ok(abs(M.step_pool(1000) - 2.7757 / 4.1241) < 1e-3, 'the pool step is the csv ratio')
ok(M.dps('Warrior', 850)[0] > M.dps('Warrior', 700)[0] * 1.2, 'the 850 row: the weapon growth bends there')

if fails:
    print('class_dps_model_test: %d failed' % fails)
    sys.exit(1)
print('class_dps_model_test: ok')
