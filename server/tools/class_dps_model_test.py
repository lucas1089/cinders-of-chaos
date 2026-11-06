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
ok(R.extra_factor('Deadeye', 1000) == 2.5 and R.extra_factor('Warrior', 1000) == 1.0, 'rotation_sim.extra_factor reads spell_factor_config.lua')

if fails:
    print('class_dps_model_test: %d failed' % fails)
    sys.exit(1)
print('class_dps_model_test: ok')
