#!/usr/bin/env python3
"""The boss model: damage per second of every class on one boss, against the Deadeye's (computed, not measured;
server/data/spells/README.md "Boss damage per class"). The mirror of pack_model.py.

usage: python3 -I server/tools/boss_model.py [--levels 300,800,1000,1200] [--check]

Inputs: pack_model.py's own (nothing new). Its `damage()` gives a class's 1-target damage per second at a level: the C4
measurement (level 300 and 1000, linear in between and below, +2.41 per level above 1000) plus the kit change since
(KIT, rotation_sim.py based) times the class identity pass (the class damage factor of class_tree.lua classDamage now over
then, pack_model.tuning). That number is the class on one target with its tree, gear, spell factor and, for the Necromancer
line, its minions. A boss takes only it: the pack cleave never hits a boss (it needs 2 or more targets), and the pack tools hit
a lone target like the filler spell, which the 1-target number already holds. Boss uptime (downtime, phases, mechanics) is in
no existing model, so every class gets full uptime; the ratio is damage while attacking.

Output: damage per second and the ratio to the Deadeye per level, next to each class's pack ratio (against the reference,
pack_model.py) so the trade between packs and bosses shows per class.

--check (CI): each class's boss ratio at every level of boss_balance_config.lua `levels` stays inside its `limits` row (widened
by `bossWindows` at the levels that are not measured), and the Deadeye is at least `lead` ahead of every other class (the pack
bands and the Elementalist's area lead are pack_model.py --check).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack_model as PM  # noqa: E402

CONFIG = PM.BALANCE
REF = 'Deadeye'
DEFAULT_LEVELS = (300, 800, 1000, 1200)


def config(text=None):
    """the bands of boss_balance_config.lua (pack_model.identity_config)"""
    return PM.identity_config(text)


def boss_dps(cls, L):
    """damage per second on one boss at level L: the 1-target number of pack_model, no cleave, full uptime"""
    return PM.damage(cls, L)[0]


def table(levels):
    """{class: [(dps, ratio to the Deadeye) per level]}"""
    out = {c: [] for c in PM.C4}
    for L in levels:
        ref = boss_dps(REF, L)
        for c in PM.C4:
            d = boss_dps(c, L)
            out[c].append((d, d / ref))
    return out


def pack_ratios(levels, cfg=None, mons=None):
    """{class: [pack ratio against the reference per level]} from pack_model.spread (levels from 1000 on: late set)"""
    spec = tuple((L, L >= 1000) for L in levels)
    t = PM.spread(spec, cfg=cfg, mons=mons, against='reference')
    return {c: [r for r, _, _ in v] for c, v in t.items()}


def outside(ratios, rows, levels=None, windows=None):
    """[(class, level index, ratio, (lo, hi))] where a ratio is outside its row (widened by the level's window)"""
    bad = []
    for c, per in ratios.items():
        if c not in rows:
            continue
        for i, (_, r) in enumerate(per):
            lo, hi = rows[c]
            if levels and windows:
                lo, hi = PM.window(None, levels[i], rows[c], windows)
            if r < lo - 1e-9 or r > hi + 1e-9:
                bad.append((c, i, r, (lo, hi)))
    return bad


def check(cfg_text=None):
    cfg = config(cfg_text)
    t = table(cfg['levels'])
    bad = outside(t, cfg['limits'], cfg['levels'], cfg['bossWindows'])
    missing = [c for c in PM.C4 if c not in cfg['limits']]
    for c, i, r, (lo, hi) in bad:
        print('FAIL %s at %d: boss ratio %.2f outside %.2f-%.2f' % (c, cfg['levels'][i], r, lo, hi))
    for c in missing:
        print('FAIL %s has no limits row' % c)
    lead = 0
    for i, L in enumerate(cfg['levels']):
        for c in PM.C4:
            if c != REF and t[c][i][1] * (1 + cfg['lead']) > 1 + 1e-9:
                print('FAIL %s at %d: boss ratio %.2f is within %d%% of the %s' % (c, L, t[c][i][1], round(100 * cfg['lead']), REF))
                lead += 1
    print('boss check: %s (%d classes, levels %s, %s %d%% ahead)' % (
        'FAIL' if bad or missing or lead else 'ok', len(PM.C4), ','.join(str(L) for L in cfg['levels']), REF, round(100 * cfg['lead'])))
    return 1 if bad or missing or lead else 0


def report(levels):
    t = table(levels)
    p = pack_ratios(levels)
    print('| Class | ' + ' | '.join('%d boss dps / ratio / pack' % L for L in levels) + ' |')
    print('|---|' + '---|' * len(levels))
    for c in PM.C4:
        print('| %s | %s |' % (c, ' | '.join('%d / %.2f / %.2f' % (t[c][i][0], t[c][i][1], p[c][i])
                                             for i in range(len(levels)))))
    return 0


def main(argv):
    if '--check' in argv:
        return check()
    levels = DEFAULT_LEVELS
    if '--levels' in argv:
        levels = tuple(int(x) for x in argv[argv.index('--levels') + 1].split(','))
    return report(levels)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
