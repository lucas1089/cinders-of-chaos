#!/usr/bin/env python3
"""The median class hit by level (O462): the curve of data/scripts/chaos/monster_defence_config.lua `hitCurve`.

usage: python3 -I server/tools/defence_curve.py [--check] [--lua]

The armour of a monster (monster_defence_core.lua) is sized so that the median class hit at the monster's level loses 25%
(normal), 40% (rare and legendary) or 50% (bosses) of itself. This tool derives that hit from the class damage model
(class_dps_model.py: the measured csv moved by the changes since, computed not measured), the way the README
"Monster defence (O462)" says:

  For each of the 21 classes at the measured levels 100, 500 and 1000 (one target):
    dps            the model's damage per second on one target
    auto share     a = the auto attack's share of it (class_dps_measured.csv auto_share_1t)
    weapon hit     dps x a x I, one swing every I seconds (the vocation's attack speed, chaos_vocations*.xml)
    spell hit      dps x (1 - a) x 2.0, one cast on every attack group cooldown (rotation_sim.py GCD, 2 s: the helper's
                   rotation casts on every cooldown by design)
    class hit      the damage weighted mean: a x weapon hit + (1 - a) x spell hit (the size of hit a point of damage
                   belongs to)
  The median class hit is the median over the 21 classes. Its ratio to the median dps is kept between the anchors (a
  straight line in the logarithm of the level, flat outside) and multiplied with class_dps_model.median_dps(level) at the
  anchor levels of the config, so the curve follows the model's own growth (a straight line in log level and log damage
  between 100, 500, 1000, 0.093% a level above 1000).

--check  exit 1 when the config's hitCurve is not what this derivation gives (a change of the class damage model moves it)
--lua    print the curve as the Lua rows of the config
"""
import math
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import class_dps_model as M  # noqa: E402
import rotation_sim as R  # noqa: E402

CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'monster_defence_config.lua')
LEVELS = (1, 10, 30, 60, 100, 200, 300, 500, 750, 1000, 1500, 2000, 2500)
GCD = R.GCD


def class_hits(level, out=None, rows=None, now=None):
    """{class: (weapon hit, spell hit, class hit)} at one of the measured levels"""
    out = out or M.shipped()[0]
    rows = rows or M.load_rows()
    now = now or M.intervals()[0]
    res = {}
    for cls in M.KEY:
        d1 = out[(cls, level)]['1t']
        a = rows[(cls, level)]['auto_share_1t']
        interval = now[R.VOC[cls]] / 1000.0
        weapon = d1 * a * interval
        spell = d1 * (1 - a) * GCD
        res[cls] = (weapon, spell, a * weapon + (1 - a) * spell)
    return res


def ratios():
    """{measured level: median class hit / median dps (1 target)}"""
    out, med = M.shipped()
    return {lv: statistics.median(v[2] for v in class_hits(lv, out).values()) / med[lv][0] for lv in M.LEVELS}


def ratio_at(level, r=None):
    r = r or ratios()
    lv = sorted(r)
    if level <= lv[0]:
        return r[lv[0]]
    if level >= lv[-1]:
        return r[lv[-1]]
    for a, b in zip(lv, lv[1:]):
        if level <= b:
            t = (math.log(level) - math.log(a)) / (math.log(b) - math.log(a))
            return r[a] + (r[b] - r[a]) * t
    return r[lv[-1]]


def curve(levels=LEVELS):
    r = ratios()
    return [(lv, int(round(M.median_dps(lv)[0] * ratio_at(lv, r)))) for lv in levels]


def config_curve(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    block = text.split('hitCurve = {', 1)[1].split('\n\t}', 1)[0]
    return [(int(a), int(b)) for a, b in re.findall(r'\{level = (\d+), hit = (\d+)\}', block)]


def main(argv):
    got = curve()
    if '--lua' in argv:
        print(',\n'.join('\t\t{level = %d, hit = %d}' % row for row in got))
        return 0
    if '--check' in argv:
        have = config_curve()
        if have != got:
            print('FAIL monster_defence_config.lua hitCurve is not the derivation of the class damage model:')
            print('  config    ', have)
            print('  derivation', got)
            return 1
        print('defence curve check: ok (%d anchors, median class hit %d at 100, %d at 500, %d at 1000)' % (
            len(got), dict(got)[100], dict(got)[500], dict(got)[1000]))
        return 0
    r = ratios()
    out, med = M.shipped()
    print('level  median dps  median weapon hit  median spell hit  median class hit  hit / dps')
    for lv in M.LEVELS:
        h = class_hits(lv, out)
        print('%5d  %10.0f  %17.0f  %16.0f  %16.0f  %9.3f' % (
            lv, med[lv][0], statistics.median(v[0] for v in h.values()), statistics.median(v[1] for v in h.values()),
            statistics.median(v[2] for v in h.values()), r[lv]))
    print('\nanchors of the config (level, median class hit):')
    for lv, hit in got:
        print('%5d  %8d' % (lv, hit))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
