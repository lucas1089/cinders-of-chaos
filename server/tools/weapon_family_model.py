#!/usr/bin/env python3
"""Weapon families (O454): the damage neutrality of sword, axe and club, computed. Not measured.

usage: python3 -I server/tools/weapon_family_model.py [--check] [--table]

A sword, an axe and a club of one item level hit the same since the one melee skill. weapon_families_core.lua gives each a trait on
the basic melee attack (sword tempo, axe cleave, club impact) and a price, `single` in weapon_families_config.lua. The owner's rule:
the traits must not move the class damage the balance models rest on (server/data/spells/class_dps_measured.csv, class_dps_model.py).
This tool holds the numbers to it:

  1 target     each family's damage per second on one target against today (1.00): within 3% of today, and no family more than 5%
               above another. The sword is taken at full stacks with its edge (tempo is damage per second neutral, the swing is
               faster and each hit lighter by the same share), the axe and the club at their `single`.
  5 targets    the axe splits `pool` of a hit among the monsters next to the target, so one target and its neighbours (the test
               layout is the main dummy and four around it) take pool in all, whatever the number: its net gain over today is
               single x (1 + pool) - 1, at most 12%, for every number of neighbours. No other family splits anything.
  class        the share of a class's damage that is the basic attack (the auto attack share of the measured table moved by the
               swing rate gain of O429, as class_dps_model.py does) times those numbers: the axe on 5 targets must stay under +5% of
               the class's 5 target damage, and no family moves a class's 1 target damage by more than 3%.
  daze         a monster is held at most `stunMs / (stunMs + immuneMs)` of the time, a boss `bossSlowMs / (bossSlowMs + bossImmuneMs)`
               of it by a slow of `bossSlow`; at most 20% and 12%.
  who          the Warrior, Thief and Templar lines (nine classes). The Monk line, launchers, wands, fists are untouched.

--check   exit 1 when a number is outside its limit
--table   the table of server/README.md "Weapon families (O454)"

Limits are in this file (LIMITS), not in the config: the config is what the game does, this is what the owner allows.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import class_dps_model as M  # noqa: E402
import rotation_sim as R  # noqa: E402

CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'weapon_families_config.lua')
LIMITS = {
    'oneTargetBand': 0.03,     # each family within 3% of today on one target
    'familySpread': 1.05,      # no family more than 5% above another on one target
    'axeFiveTargets': 0.12,    # the axe gains at most 12% of the basic attack on 5 targets
    'classFiveTargets': 0.05,  # ... and under +5% of the class's 5 target damage
    'classOneTarget': 0.03,    # no family moves a class's 1 target damage by more than 3%
    'dazeUptime': 0.20,
    'bossUptime': 0.12,
    'bossSlowUptime': 0.05,    # the boss slow times its uptime: the speed a boss loses on average
}
LEVELS = M.LEVELS


def read(path=CONFIG):
    with open(path, encoding='utf-8') as f:
        return f.read()


def section(text, name):
    """the text of `name = { ... }` inside the families table (balanced braces)"""
    m = re.search(r'\b' + name + r' = \{', text[text.index('families = {'):])
    start = text.index('families = {') + m.end()
    depth, i = 1, start
    while depth:
        c = text[i]
        depth += (c == '{') - (c == '}')
        i += 1
    return text[start:i - 1]


def num(text, name):
    m = re.search(r'\b' + name + r' = ([0-9.]+)', text)
    if not m:
        raise ValueError('config: %s not found' % name)
    return float(m.group(1))


def config(text=None):
    text = text or read()
    sw, ax, cl = section(text, 'sword'), section(text, 'axe'), section(text, 'club')
    voc = {int(a) for a in re.findall(r'\[(\d+)\] = true', re.search(r'vocations = \{([^}]*)\}', text).group(1))}
    return {
        'vocations': voc,
        'single': {'sword': num(sw, 'single'), 'axe': num(ax, 'single'), 'club': num(cl, 'single')},
        'edge': num(sw, 'edge'), 'maxStacks': num(sw, 'maxStacks'), 'stackPct': num(sw, 'stackPct'),
        'pool': num(ax, 'pool'), 'maxTargets': int(num(ax, 'maxTargets')),
        'chance': num(cl, 'chance'), 'stunMs': num(cl, 'stunMs'), 'immuneMs': num(cl, 'immuneMs'),
        'bossChance': num(cl, 'bossChance'), 'bossSlow': num(cl, 'bossSlow'), 'bossSlowMs': num(cl, 'bossSlowMs'),
        'bossImmuneMs': num(cl, 'bossImmuneMs'),
    }


def one_target(c):
    """damage per second on one target against today, per family (sword at full stacks, with its edge)"""
    return {'sword': c['single']['sword'] * (1 + c['edge']), 'axe': c['single']['axe'], 'club': c['single']['club']}


def axe_gain(c, neighbours):
    """net gain of the axe over today on a target with `neighbours` monsters next to it, as a share of the basic attack"""
    n = min(neighbours, c['maxTargets'])
    return c['single']['axe'] * (1 + (c['pool'] if n > 0 else 0)) - 1


def auto_share(row, gain, five):
    """the share of the class's damage that is the basic attack, after the swing rate gain of O429 (class_dps_model.model)"""
    f = row['auto_share_5t' if five else 'auto_share_1t']
    return f * gain / (1 - f + f * gain)


def classes(c):
    return [cls for cls in M.KEY if R.VOC[cls] in c['vocations']]


def class_rows(c, rows=None, out=None):
    """{(class, level): {'share1', 'share5', 'sword1', 'axe1', 'club1', 'axe5', 'dps1', 'dps5'}}: the class change of each family"""
    rows = rows or M.load_rows()
    out = out or M.shipped()[0]
    one = one_target(c)
    gain4 = axe_gain(c, 4)
    res = {}
    for cls in classes(c):
        for lv in LEVELS:
            r, o = rows[(cls, lv)], out[(cls, lv)]
            s1, s5 = auto_share(r, o['gain'], False), auto_share(r, o['gain'], True)
            res[(cls, lv)] = {
                'share1': s1, 'share5': s5, 'dps1': o['1t'], 'dps5': o['5t'],
                'sword1': s1 * (one['sword'] - 1), 'axe1': s1 * (one['axe'] - 1), 'club1': s1 * (one['club'] - 1),
                'axe5': s5 * gain4,
            }
    return res


def problems(c=None, rows=None, out=None):
    c = c or config()
    bad = []
    one = one_target(c)
    for fam, v in one.items():
        if abs(v - 1) > LIMITS['oneTargetBand'] + 1e-9:
            bad.append('%s: %.3f of today on one target (band +-%.0f%%)' % (fam, v, LIMITS['oneTargetBand'] * 100))
    spread = max(one.values()) / min(one.values())
    if spread > LIMITS['familySpread'] + 1e-9:
        bad.append('families: %.3f between the highest and the lowest on one target (limit %.2f)' % (spread, LIMITS['familySpread']))
    for n in range(1, c['maxTargets'] + 1):
        g = axe_gain(c, n)
        if g > LIMITS['axeFiveTargets'] + 1e-9:
            bad.append('axe: +%.1f%% of the basic attack with %d neighbours (limit +%.0f%%)' % (g * 100, n, LIMITS['axeFiveTargets'] * 100))
    if c['single']['axe'] >= 1 or c['single']['club'] >= 1:
        bad.append('the axe and the club must pay: single below 1')
    if c['stunMs'] / (c['stunMs'] + c['immuneMs']) > LIMITS['dazeUptime'] + 1e-9:
        bad.append('club: a monster is held %.0f%% of the time (limit %.0f%%)' % (
            100 * c['stunMs'] / (c['stunMs'] + c['immuneMs']), LIMITS['dazeUptime'] * 100))
    boss = c['bossSlowMs'] / (c['bossSlowMs'] + c['bossImmuneMs'])
    if boss > LIMITS['bossUptime'] + 1e-9:
        bad.append('club: a boss is slowed %.0f%% of the time (limit %.0f%%)' % (boss * 100, LIMITS['bossUptime'] * 100))
    if c['bossSlow'] * boss > LIMITS['bossSlowUptime'] + 1e-9:
        bad.append('club: a boss loses %.1f%% of its speed on average (limit %.0f%%)' % (c['bossSlow'] * boss * 100, LIMITS['bossSlowUptime'] * 100))
    for (cls, lv), r in class_rows(c, rows, out).items():
        if r['axe5'] >= LIMITS['classFiveTargets']:
            bad.append('%s level %d: the axe gives +%.1f%% of the class damage on 5 targets (limit +%.0f%%)' % (
                cls, lv, r['axe5'] * 100, LIMITS['classFiveTargets'] * 100))
        for fam in ('sword', 'axe', 'club'):
            if abs(r[fam + '1']) > LIMITS['classOneTarget']:
                bad.append('%s level %d: the %s moves the class by %+.1f%% on 1 target (limit +-%.0f%%)' % (
                    cls, lv, fam, r[fam + '1'] * 100, LIMITS['classOneTarget'] * 100))
    return bad


def table(c=None):
    c = c or config()
    rows = class_rows(c)
    one = one_target(c)
    lines = [
        '| Class | Level | Basic attack share 1 / 5 targets | 1 target now | sword | axe | club | 5 targets now | axe, 5 targets |',
        '|---|---|---:|---:|---:|---:|---:|---:|---:|',
    ]
    for cls in classes(c):
        for lv in LEVELS:
            r = rows[(cls, lv)]
            lines.append('| %s | %d | %.0f%% / %.0f%% | %.0f | %.0f (%+.1f%%) | %.0f (%+.1f%%) | %.0f (%+.1f%%) | %.0f | %.0f (%+.1f%%) |' % (
                cls, lv, r['share1'] * 100, r['share5'] * 100, r['dps1'],
                r['dps1'] * (1 + r['sword1']), r['sword1'] * 100, r['dps1'] * (1 + r['axe1']), r['axe1'] * 100,
                r['dps1'] * (1 + r['club1']), r['club1'] * 100, r['dps5'],
                r['dps5'] * (1 + r['axe5'] + r['share5'] * 0), r['axe5'] * 100))
    head = ['One target, against today: sword %.3f (full stacks, edge included), axe %.3f, club %.3f; highest over lowest %.3f.' % (
        one['sword'], one['axe'], one['club'], max(one.values()) / min(one.values())),
        'Five targets (main target and four around it): axe %+.1f%% of the basic attack; a pack of any size: at most %+.1f%%.' % (
            axe_gain(c, 4) * 100, max(axe_gain(c, n) for n in range(1, c['maxTargets'] + 1)) * 100),
        'Daze: %.0f%% a hit, %.1f s without attacking, %.1f s of rest: held at most %.1f%% of the time; a boss: %.0f%% a hit, a %.0f%% slow for %.1f s, then %.1f s of rest.' % (
            c['chance'] * 100, c['stunMs'] / 1000, c['immuneMs'] / 1000, 100 * c['stunMs'] / (c['stunMs'] + c['immuneMs']),
            c['bossChance'] * 100, c['bossSlow'] * 100, c['bossSlowMs'] / 1000, c['bossImmuneMs'] / 1000), '']
    return '\n'.join(head + lines)


def main(argv):
    c = config()
    if '--table' in argv:
        print(table(c))
        return 0
    bad = problems(c)
    if '--check' in argv:
        for b in bad:
            print('FAIL ' + b)
        if not bad:
            print('weapon family check: ok (%d classes, levels %s; one target within %d%%, spread %.3f, axe on a pack +%.1f%%)' % (
                len(classes(c)), ','.join(map(str, LEVELS)), LIMITS['oneTargetBand'] * 100,
                max(one_target(c).values()) / min(one_target(c).values()), max(axe_gain(c, n) for n in range(1, c['maxTargets'] + 1)) * 100))
        return 1 if bad else 0
    print(table(c))
    if bad:
        print('\nOutside the limits: ' + '; '.join(bad))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
