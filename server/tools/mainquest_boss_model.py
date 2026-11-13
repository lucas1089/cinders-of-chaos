#!/usr/bin/env python3
"""Vael Ashmourn, the solo boss of the main quest (O551; computed, not measured): can all 21 classes solo it at level 500?

usage: python3 -I server/tools/mainquest_boss_model.py [--check]

The boss is the spell trial "mq" of the Vocation Trials (trials_config.lua spellTiers). Its health is hp of the Merciless tier x hpShare at
the tier's minimum level (x (level / minLevel) ^ hpExponent above it). The damage a class deals to a boss is class_dps_model.py's one
target number times what a boss lets through (boss_length_model.kept('boss')), the same rule that gives the dungeon bosses their 150 s.
--check holds:
  typical     the median class kills it in 150 s +-10% (the dungeon boss length) at level 500
  weakest     the weakest of the 21 classes (and the median at 700, the top of the tier's window) needs at most 70% of the time limit
  spread      the weakest class deals at least 60% of the median (so the plan does not rest on the spread the class model holds, +-25%)
  hit         a hit of the boss is at most the Cruel Trial's share of the maximum health before the resistance (0.09), lives 3, the time
              limit between 300 and 420 s (the three spell trials: 300 / 360 / 420)
The boss's four phases, the resistance of their element and the door are tested in tests/mainquest_boss_test.lua (lua, mocked engine).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import boss_length_model as BL  # noqa: E402
import class_dps_model as CD  # noqa: E402

CHAOS = os.path.join(HERE, '..', 'data', 'scripts', 'chaos')
LEVEL = 500
TYPICAL_SECONDS, TYPICAL_TOL = BL.BOSS_SECONDS, 0.10
MAX_TIME_SHARE = 0.70
MIN_SPREAD = 0.60
MAX_HIT = 0.09


def read(name):
    with open(os.path.join(CHAOS, name), encoding='utf-8') as f:
        return f.read()


def tier():
    text = read('trials_config.lua')
    merc = re.search(r'key = "merciless", name = "Merciless", minLevel = \d+, maxLevel = \d+, hp = (\d+)', text)
    exp = float(re.search(r'hpExponent = ([0-9.]+)', text).group(1))
    row = re.search(r'\{key = "mq", name = "[^"]+", minLevel = (\d+), maxLevel = (\d+), hpShare = ([0-9.]+), hit = ([0-9.]+), addHit = ([0-9.]+),\s*'
                    r'time = (\d+), lives = (\d+)', text)
    if not merc or not row:
        raise SystemExit('trials_config.lua: the mq spell tier or the Merciless hp was not found')
    return {'merc_hp': int(merc.group(1)), 'exp': exp, 'min': int(row.group(1)), 'max': int(row.group(2)), 'share': float(row.group(3)),
            'hit': float(row.group(4)), 'time': int(row.group(6)), 'lives': int(row.group(7))}


def health(t, level):
    lvl = max(t['min'], min(t['max'], level))
    return t['merc_hp'] * t['share'] * (lvl / float(t['min'])) ** t['exp']


def seconds(t, level, dps1):
    return health(t, level) / (dps1 * BL.kept('boss'))


def table():
    t = tier()
    out = ['| Class | 1 target at %d | seconds to kill | share of the time limit |' % LEVEL, '|---|---:|---:|---:|']
    rows = []
    for name in CD.KEY:
        d = CD.dps(name, LEVEL)[0]
        rows.append((seconds(t, LEVEL, d), name, d))
    for s, name, d in sorted(rows):
        out.append('| %s | %.0f | %.0f | %.0f%% |' % (name, d, s, s / t['time'] * 100))
    med = CD.median_dps(LEVEL)[0]
    out.append('| median | %.0f | %.0f | %.0f%% |' % (med, seconds(t, LEVEL, med), seconds(t, LEVEL, med) / t['time'] * 100))
    return out, rows, t


def problems():
    out, rows, t = table()
    bad = []
    med = CD.median_dps(LEVEL)[0]
    typical = seconds(t, LEVEL, med)
    if abs(typical - TYPICAL_SECONDS) > TYPICAL_SECONDS * TYPICAL_TOL:
        bad.append('the median class needs %.0f s at level %d (plan %d s +-%d%%): hpShare is %.2f' % (typical, LEVEL, TYPICAL_SECONDS,
                                                                                                   TYPICAL_TOL * 100, t['share']))
    worst_s, worst_name, worst_d = max(rows)
    if worst_s > t['time'] * MAX_TIME_SHARE:
        bad.append('%s needs %.0f s of the %d s limit (more than %d%%)' % (worst_name, worst_s, t['time'], MAX_TIME_SHARE * 100))
    if min(d for _, _, d in rows) < med * MIN_SPREAD:
        bad.append('a class deals less than %d%% of the median' % (MIN_SPREAD * 100))
    top = seconds(t, t['max'], CD.median_dps(t['max'])[0])
    if top > t['time'] * MAX_TIME_SHARE:
        bad.append('the median class needs %.0f s at level %d, the top of the window' % (top, t['max']))
    if t['hit'] > MAX_HIT + 1e-9:
        bad.append('a hit of %.3f of the maximum health is above the Cruel Trial\'s %.2f' % (t['hit'], MAX_HIT))
    if t['lives'] != 3 or not 300 <= t['time'] <= 420:
        bad.append('3 lives and 300-420 s are the spell trials\' rule (got %d lives, %d s)' % (t['lives'], t['time']))
    if t['min'] != 500:
        bad.append('the tier starts at level 500, the second resistance mark')
    return bad


def main(argv):
    out, _, t = table()
    if '--check' not in argv:
        print('health at level %d: %.0f (hpShare %.2f)' % (LEVEL, health(t, LEVEL), t['share']))
        print('\n'.join(out))
    bad = problems()
    for b in bad:
        sys.stderr.write('mainquest_boss_model: %s\n' % b)
    if bad:
        return 1
    if '--check' in argv:
        print('mainquest_boss_model: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
