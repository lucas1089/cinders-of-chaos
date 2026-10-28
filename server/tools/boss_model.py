#!/usr/bin/env python3
"""The boss model: damage per second of every class on one boss, against the Deadeye's (computed, not measured;
server/data/spells/README.md "Boss damage per class"). The mirror of pack_model.py.

usage: python3 -I server/tools/boss_model.py [--levels 300,800,1000,1200] [--proposed] [--check]

Inputs: pack_model.py's own (nothing new). Its `damage()` gives a class's 1-target damage per second at a level: the C4
measurement (level 300 and 1000, linear in between and below, +2.41 per level above 1000) plus the kit change since
(KIT, rotation_sim.py based). That number is the class on one target with its tree, gear, spell factor and, for the
Necromancer line, its minions. A boss takes only it: the pack cleave never hits a boss (it needs 2 or more targets),
and the pack tools hit a lone target like the filler spell, which the 1-target number already holds. Boss uptime
(downtime, phases, mechanics) is in no existing model, so every class gets full uptime; the ratio is damage while
attacking.

Output: damage per second and the ratio to the Deadeye per level, next to each class's pack ratio (against the median
class, pack_model.py) so the trade between packs and bosses shows per class.

--check (CI): each class's boss ratio at every level of boss_balance_config.lua `levels` stays inside its `limits` row
(the current state with a margin). --proposed also prints which classes are outside the `proposed` rows (the plan of the
owner, 2026-10-28; not enforced).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack_model as PM  # noqa: E402

CONFIG = os.path.normpath(os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'boss_balance_config.lua'))
REF = 'Deadeye'
DEFAULT_LEVELS = (300, 800, 1000, 1200)


def config(text=None):
    """{'levels': [...], 'limits': {class: (lo, hi)}, 'proposed': {class: (lo, hi)}} read from the Lua table"""
    text = text if text is not None else open(CONFIG, encoding='utf-8').read()
    lv = re.search(r'levels = \{([0-9, ]+)\}', text)
    out = {'levels': [int(x) for x in lv.group(1).split(',') if x.strip()]}
    for key in ('limits', 'proposed'):
        block = re.search(key + r' = \{(.*?)\n\t\}', text, re.S).group(1)
        out[key] = {c: (float(a), float(b)) for c, a, b in
                    re.findall(r'\["([^"]+)"\] = \{([0-9.]+), ([0-9.]+)\}', block)}
    return out


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
    """{class: [pack ratio against the median class per level]} from pack_model.spread (levels from 1000 on: late set)"""
    spec = tuple((L, L >= 1000) for L in levels)
    t = PM.spread(spec, cfg=cfg, mons=mons)
    return {c: [r for r, _, _ in v] for c, v in t.items()}


def outside(ratios, rows):
    """[(class, level index, ratio, (lo, hi))] where a ratio is outside its row"""
    bad = []
    for c, per in ratios.items():
        if c not in rows:
            continue
        lo, hi = rows[c]
        for i, (_, r) in enumerate(per):
            if r < lo - 1e-9 or r > hi + 1e-9:
                bad.append((c, i, r, rows[c]))
    return bad


def check(cfg_text=None):
    cfg = config(cfg_text)
    t = table(cfg['levels'])
    bad = outside(t, cfg['limits'])
    missing = [c for c in PM.C4 if c not in cfg['limits']]
    for c, i, r, (lo, hi) in bad:
        print('FAIL %s at %d: boss ratio %.2f outside %.2f-%.2f' % (c, cfg['levels'][i], r, lo, hi))
    for c in missing:
        print('FAIL %s has no limits row' % c)
    print('boss check: %s (%d classes, levels %s)' % ('FAIL' if bad or missing else 'ok', len(PM.C4),
                                                      ','.join(str(L) for L in cfg['levels'])))
    return 1 if bad or missing else 0


def report(levels, show_proposed):
    t = table(levels)
    p = pack_ratios(levels)
    print('| Class | ' + ' | '.join('%d boss dps / ratio / pack' % L for L in levels) + ' |')
    print('|---|' + '---|' * len(levels))
    for c in PM.C4:
        print('| %s | %s |' % (c, ' | '.join('%d / %.2f / %.2f' % (t[c][i][0], t[c][i][1], p[c][i])
                                             for i in range(len(levels)))))
    if show_proposed:
        prop = config()['proposed']
        bad = outside(t, prop)
        by = {}
        for c, i, r, rng in bad:
            by.setdefault(c, []).append('%d: %.2f' % (levels[i], r))
        print('\nproposed targets (not enforced), classes outside their row:')
        for c in PM.C4:
            if c in by:
                print('- %s %.2f-%.2f: %s' % (c, prop[c][0], prop[c][1], ', '.join(by[c])))
    return 0


def main(argv):
    if '--check' in argv:
        return check()
    levels = DEFAULT_LEVELS
    if '--levels' in argv:
        levels = tuple(int(x) for x in argv[argv.index('--levels') + 1].split(','))
    return report(levels, '--proposed' in argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
