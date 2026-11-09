#!/usr/bin/env python3
"""Class DPS balance (O430): every class within +-25% of the level median on 1 target and on 5 targets (+-30% at level 100).

usage: python3 -I server/tools/class_dps_model.py [--check] [--before] [--csv]

Owner, 2026-11-06: "balance the classes that are far from the median DPS". The anchor is a measured DPS test of all 21 classes at
levels 100, 500 and 1000 (server/data/spells/class_dps_measured.csv: one character per class and level, the same gear rule, the
passive tree build of the class, the helper's Auto setup rotation, 60 s on training dummies, 1 target and 5 targets; the
"every spell" column is the same rotation with every rule cast on one target, which is what the helper does since O430).
The test ran BEFORE O429 (faster auto attacks) and before the numbers of this change.

The model (computed, not measured): the table's numbers moved by the changes made since the test:
  1 target   = every-spell 1 target x (1 - f1 + f1 x r) x m
  5 targets  = helper 5 targets      x (1 - f5 + f5 x r) x m x (1 + w5 x (x - 1))
  r  the auto attack gain of O429, old base attack interval / new (chaos_vocations*.xml; attack_rate_config.lua trainOld)
  f1, f5  the auto attack's share of the measured damage (rotation_sim.py spell damage of the cast rotation next to
          weapon_sim.py's auto attack of the class's weapon kind, snapshot in the csv; 1 target and 5 targets)
  m  the class damage factor now / then (class_tree.lua classDamage, the csv holds "then")
  w5 the share of the measured 5 target damage that is a spell hit on a target other than the first of its cast (snapshot
     in the csv), x the extra target factor (spell_factor_config.lua `extra`, rotation_sim.py extra_factor)
No other changes are modelled (a retuned gear set, a tree change); the weights are the model's guess and the measurement spread
was +-5% to +-15%, so the check keeps a class inside the band, not on a number.
--check   exit 1 when a class is outside its band at one of the levels or the table has a hole
--before  print the measured table before the change (helper mode, the state the owner saw)

O444 (2026-11-09): this file is the ONE source of class damage for the balance models. boss_model.py, pack_model.py and
tower_model.py read `dps(class, level)` and `median_dps(level)` below, not a table of their own (they carried the C4
measurement of 2026-10-11, which is older than O430 and put the Sentinel at 1.80 of the Deadeye on a boss while this model
has it at -14% of the median on 1 target). `dps` is the model at the three measured levels and, between and outside them,
a straight line in the logarithm of level and damage (below 100 and between the anchors), then 0.093% a level above 1000
(the old rule: 2.41 a level over the C4 median 2598 at level 1000; the 500 to 1000 slope of this table is 0.096%). Computed,
not measured, as everything here.
"""
import csv
import math
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import rotation_sim as R  # noqa: E402

CSV = os.path.join(REPO, 'server', 'data', 'spells', 'class_dps_measured.csv')
CLASS_TREE = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'class_tree.lua')
ATTACK_RATE = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'attack_rate_config.lua')
VOCATION_XMLS = [os.path.join(REPO, 'server', 'data', 'XML', n) for n in
                 ('chaos_vocations.xml', 'chaos_vocations_monk.xml', 'chaos_vocations_necro.xml', 'chaos_vocations_templar.xml')]
LEVELS = (100, 500, 1000)
BAND = {100: 0.30, 500: 0.25, 1000: 0.25}
# the class key of class_tree.lua classDamage
KEY = {'Warrior': 'warrior', 'Juggernaut': 'juggernaut', 'Berserker': 'berserker', 'Ranger': 'ranger', 'Deadeye': 'deadeye',
       'Beastmaster': 'beastmaster', 'Mystic': 'mystic', 'Elementalist': 'elementalist', 'Illusionist': 'illusionist',
       'Thief': 'thief', 'Ninja': 'ninja', 'Samurai': 'samurai', 'Necromancer': 'necromancer', 'Lich': 'lich',
       'Bone Lord': 'bonelord', 'Monk': 'monk', 'Shadowfist': 'shadowfist', 'Iron Sage': 'ironsage', 'Templar': 'templar',
       'Inquisitor': 'inquisitor', 'Sentinel': 'sentinel'}


def load_rows(path=CSV):
    out = {}
    with open(path, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            out[(r['class'], int(r['level']))] = {k: float(v) for k, v in r.items() if k not in ('class', 'level')}
    return out


def class_damage(path=CLASS_TREE):
    """{class key: [(level, factor), ...]} of class_tree.lua classDamage"""
    text = open(path, encoding='utf-8').read()
    block = text.split('M.classDamage = {', 1)[1].split('\n}', 1)[0]
    out = {}
    for m in re.finditer(r'^\t(\w+) = (\{\{[^\n]*\}\}),', block, re.M):
        out[m.group(1)] = [(int(a), float(b)) for a, b in re.findall(r'\{(\d+),\s*([0-9.]+)\}', m.group(2))]
    return out


def intervals():
    """({vocation id: base attack interval ms now}, {vocation id: ms before O429}) from the vocation XMLs and attack_rate_config.lua"""
    now = {}
    for p in VOCATION_XMLS:
        for m in re.finditer(r'<vocation id="(\d+)"[^>]*?attackspeed="(\d+)"', open(p, encoding='utf-8').read()):
            now[int(m.group(1))] = int(m.group(2))
    text = open(ATTACK_RATE, encoding='utf-8').read()
    default = int(re.search(r'trainDefault = (\d+)', text).group(1))
    old = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\] = (\d+)', re.search(r'trainOld = \{([^}]*)\}', text).group(1))}
    return now, {v: old.get(v, default) for v in now}


def model(rows=None, damage=None, interval=None, extra=None):
    """{(class, level): {'1t': dps, '5t': dps, ...}} and {level: (median 1t, median 5t)}"""
    rows = rows or load_rows()
    damage = damage or class_damage()
    now, old = interval or intervals()
    extra = extra or R.extra_factor
    out, med = {}, {}
    for lv in LEVELS:
        for cls in KEY:
            r = rows[(cls, lv)]
            voc = R.VOC[cls]
            gain = old[voc] / float(now[voc])
            m = R.interp(damage[KEY[cls]], lv) / r['class_damage_before']
            x = extra(cls, lv)
            one = r['every_spell_1t'] * (1 - r['auto_share_1t'] + r['auto_share_1t'] * gain) * m
            five = r['helper_5t'] * (1 - r['auto_share_5t'] + r['auto_share_5t'] * gain) * m * (1 + r['extra_share_5t'] * (x - 1))
            out[(cls, lv)] = {'1t': one, '5t': five, 'm': m, 'x': x, 'gain': gain}
        med[lv] = (statistics.median(out[(c, lv)]['1t'] for c in KEY), statistics.median(out[(c, lv)]['5t'] for c in KEY))
    return out, med


def problems(out=None, med=None):
    if out is None:
        out, med = model()
    bad = []
    for lv in LEVELS:
        for cls in KEY:
            for i, name in ((0, '1t'), (1, '5t')):
                d = out[(cls, lv)][name] / med[lv][i] - 1
                if abs(d) > BAND[lv]:
                    bad.append('%s level %d, %s: %+.0f%% of the median (band +-%.0f%%)' % (cls, lv, name, d * 100, BAND[lv] * 100))
    return bad


# ---- O444: the class damage every balance model reads --------------------------------------------------------------------
GROWTH_ABOVE_1000 = 0.00093   # damage growth per level above 1000, a share of the level 1000 damage (all classes the same)
_CACHE = {}


def shipped():
    """(model, medians) of the committed state, computed once"""
    if 'model' not in _CACHE:
        _CACHE['model'] = model()
    return _CACHE['model']


def _anchor_value(points, level):
    """points = [(anchor level, damage), ...] ascending: a straight line in log(level), log(damage) between two anchors, the
    slope of the first two below the first anchor, the growth above 1000 a straight line (GROWTH_ABOVE_1000 a level)"""
    if level <= 0:
        return 0.0
    if level >= points[-1][0]:
        return points[-1][1] * (1 + GROWTH_ABOVE_1000 * (level - points[-1][0]))
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if level <= x1:
            e = (math.log(y1) - math.log(y0)) / (math.log(x1) - math.log(x0))
            return y0 * (level / float(x0)) ** e
    raise AssertionError('level above the last anchor is handled first')


def dps(cls, level, out=None):
    """(1 target, 5 targets) damage per second of a class at any level: the model's numbers at 100, 500 and 1000, in between
    and outside as described in the header. No pack cleave and no boss uptime: those are the models' own"""
    out = out or shipped()[0]
    return tuple(_anchor_value([(lv, out[(cls, lv)][k]) for lv in LEVELS], level) for k in ('1t', '5t'))


def median_dps(level, out=None):
    """(median 1 target, median 5 targets) of the 21 classes at any level (the median of dps(), so the same line the
    classes follow; at 100, 500 and 1000 it is the table's median)"""
    return tuple(statistics.median(dps(c, level, out)[i] for c in KEY) for i in (0, 1))


def table(out, med):
    lines = ['| Level | Class | 1 target | vs median | 5 targets | vs median | m | extra |', '|---|---|---:|---:|---:|---:|---:|---:|']
    for lv in LEVELS:
        for cls in KEY:
            o = out[(cls, lv)]
            lines.append('| %d | %s | %.0f | %+.0f%% | %.0f | %+.0f%% | %.2f | %.2f |' % (
                lv, cls, o['1t'], (o['1t'] / med[lv][0] - 1) * 100, o['5t'], (o['5t'] / med[lv][1] - 1) * 100, o['m'], o['x']))
        lines.append('| %d | median | %.0f | | %.0f | | | |' % (lv, med[lv][0], med[lv][1]))
    return '\n'.join(lines)


def before_table(rows=None):
    rows = rows or load_rows()
    lines = ['| Level | Class | 1 target (helper) | vs median | 5 targets | vs median |', '|---|---|---:|---:|---:|---:|']
    for lv in LEVELS:
        m1 = statistics.median(rows[(c, lv)]['helper_1t'] for c in KEY)
        m5 = statistics.median(rows[(c, lv)]['helper_5t'] for c in KEY)
        for cls in KEY:
            r = rows[(cls, lv)]
            lines.append('| %d | %s | %.0f | %+.0f%% | %.0f | %+.0f%% |' % (
                lv, cls, r['helper_1t'], (r['helper_1t'] / m1 - 1) * 100, r['helper_5t'], (r['helper_5t'] / m5 - 1) * 100))
    return '\n'.join(lines)


def main(argv):
    if '--before' in argv:
        print(before_table())
        return 0
    out, med = model()
    bad = problems(out, med)
    if '--check' in argv:
        for b in bad:
            print('FAIL ' + b)
        if not bad:
            print('class dps check: ok (21 classes, levels %s, within +-25%% of the median on 1 and 5 targets, +-30%% at 100)' %
                  ','.join(map(str, LEVELS)))
        return 1 if bad else 0
    print(table(out, med))
    if bad:
        print('\nOutside the band: ' + '; '.join(bad))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
