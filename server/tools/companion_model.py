#!/usr/bin/env python3
"""The Beastmaster companion model (O306; computed, not measured in game; server/README.md "Beastmaster companion (O306)").

usage: python3 -I server/tools/companion_model.py [--levels 50,100,400,1000] [--legacy] [--check]

Tester report 2026-10-29 (a level 400 Beastmaster): the companion was 4% of the damage and died in 3 hits of the monsters
of the owner's hunting level, in under 5 s. What the model answers, per level:
  * how long a companion lives when `attackers` monsters of the owner's hunting level go for it (health against their
    damage, with the companion's cut `taken`), and how many hits that is;
  * what its own bites are worth: bite = (level x autoLevel + distance skill x autoSkill) every biteMs, in contact with the
    target `contact` of the time, alive the share of a hunt's pack cycle it lives; as a share of the Beastmaster's damage;
  * the class total with the bites: the Beastmaster's measured total (pack_model.py C4, level 300 and 1000) held the old
    bites; the bites' gain is added and the class damage factor (class_tree.lua classDamage) takes it back, so the class
    stays in its pack and boss bands (pack_model.py calls apply() for the Beastmaster). The factor alone could not hold
    both bands (the bites add the same to 1 target and to a pack, the class is a pack class): the pack cleave's high end
    (pace_config.lua, the companion's hits cleave too) went from 1 to 2 with it.

Inputs (everything in the repo, so CI runs it without the base tree):
  chaos_constants.lua, classes.lua   the companion's numbers and formulas, run by tools/companion_numbers.lua (luajit or
                                     lua5.3; env LUAJIT) so the model uses the server's own functions
  companion_balance_config.lua       the model's inputs, the numbers before O306 and the limits of --check
  necro_balance_config.lua           what a monster deals to a summon (monsterDps by hunting level)
  rotation_sim.py                    the owner's distance skill by level
  pack_model.py                      the class total, the pack, its health and the walking time
"""
import json, math, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rotation_sim as R
import pack_model as P

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CLASS = 'Beastmaster'
HIT_S = 2.0  # seconds between the hits of a monster (the stock attack interval)


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


_dump = {}


def dump(levels):
    """the numbers of the real config and classes.lua for these levels (tools/companion_numbers.lua)"""
    key = tuple(levels)
    if key not in _dump:
        args = [lua_bin(), 'tools/companion_numbers.lua'] + ['%d:%.4f' % (lv, R.stats(CLASS, lv)['SK']) for lv in levels]
        out = subprocess.run(args, cwd=SERVER, check=True, capture_output=True, text=True).stdout
        _dump[key] = json.loads(out)
    return _dump[key]


def conf():
    """(companion config, balance config) of the real files"""
    d = dump((100,))
    return d['config'], d['balance']


def power(points, x):
    """a power law between the points (below the first by the exponent of the first two, above the last by the last)"""
    pts = [tuple(p) for p in points]
    if x <= pts[0][0]:
        (x0, y0), (x1, y1) = pts[0], pts[1]
    elif x >= pts[-1][0]:
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
    else:
        (x0, y0), (x1, y1) = next((a, b) for a, b in zip(pts, pts[1:]) if x <= b[0])
    return y0 * (x / x0) ** (math.log(y1 / y0) / math.log(x1 / x0))


def monster_dps(level):
    return power(dump((100,))['necro']['monsterDps'], max(level, 1))


# ------------------------------------------------------------------------------------------------ the formulas
# (the same as classes.lua; the test compares them with the Lua rows)
def health(c, level, legacy=False, bal=None):
    if legacy:
        return bal['legacy']['healthBase'] + bal['legacy']['healthPerLevel'] * level
    return math.floor(c['health']['base'] + c['health']['perLevel'] * level)


def bite(c, level, skill, legacy=False, bal=None):
    """the average bite"""
    if legacy:
        a, b = bal['legacy']['autoLevel'], bal['legacy']['autoSkill']
    else:
        a, b = c['autoLevel'], c['autoSkill']
    return level * a + skill * b


def cap(c, level):
    n = 0
    for step in c['caps']:
        if level >= step['level']:
            n = step['count']
    return n


def taken(c, bal, legacy):
    return bal['legacy']['taken'] if legacy else c['taken']


def alive_seconds(level, legacy=False, attackers=None):
    """seconds one companion lives under `attackers` monsters of the hunting level (burst included)"""
    c, bal = conf()
    n = attackers or bal['attackers']
    incoming = n * monster_dps(level) * bal['burst'] * taken(c, bal, legacy)
    return health(c, level, legacy, bal) / incoming


def hits_survived(level, legacy=False):
    """hits of one monster (every HIT_S, burst included) one companion takes"""
    c, bal = conf()
    hit = monster_dps(level) * bal['burst'] * HIT_S * taken(c, bal, legacy)
    return health(c, level, legacy, bal) / hit


def pack_of(level, d1, d5):
    """(pack size, clear time) of a class with these damages: pack_model.py's rule"""
    cfg, mons = _pack()
    scaled = level >= 1000
    hp = P.lin(P.SCALED_HEALTH, level) if scaled else P.median_health(mons, level)
    m = P.lin(cfg['scaled'] if scaled else cfg['base'], level)
    p0 = next(p for lo, hi, p, w in P.PACK if lo <= level < hi)
    share = max(0.0, (d5 - d1) / d5) if d5 else 0.0
    n = min(P.PCAP, p0 - 2 + 4 * min(1.0, share / 0.6))
    s = max(0.0, (d5 - d1) / 4)
    return n, n * hp * m / (d1 + (n - 1) * s)


_p = {}


def _pack():
    if not _p:
        _p['v'] = (P.pace(), P.monsters())
    return _p['v']


def uptime(level, legacy=False):
    """the share of a pack fight one companion is alive: its health against the damage the monsters going for it deal in
    the clear time (a dead one is called again between packs)"""
    c, bal = conf()
    d1, d5 = P.damage(CLASS, level, tune=False)
    n, clear = pack_of(level, d1, d5)
    count = max(1, cap(c, level))
    incoming = bal['huntAttackers'] / count * monster_dps(level) * bal['burst'] * taken(c, bal, legacy) * bal['alive'] * clear
    return min(1.0, health(c, level, legacy, bal) / incoming)


def companion_dps(level, legacy=False):
    """raw damage per second of the companions' own bites in a hunt (no class factor)"""
    c, bal = conf()
    skill = R.stats(CLASS, level)['SK']
    return cap(c, level) * bite(c, level, skill, legacy, bal) / (c['biteMs'] / 1000.0) * bal['contact'] * uptime(level, legacy)


def class_factor(level, points):
    return P.lin([tuple(p) for p in points], level)


def cleave(level, legacy=False):
    """the pack cleave multiplier of the Beastmaster on a pack of 5 (pace_config.lua cleave; "the companion's hits too")"""
    e = _pack()[0]['cleave'].get(P.VOC[CLASS])
    if not e:
        return 1.0
    high = conf()[1]['legacy']['cleaveHigh'] if legacy else e[2]
    return 1 + P.lin([(P.CLEAVE_FROM, e[0]), (P.CLEAVE_TO, high)], level) / 100.0 * min(e[1], 4)


def totals(level):
    """the Beastmaster at a level: before = the measured total (C4 + kit, which held the old bites) x the old class factor;
    after = with today's bites and class factor. d1 on 1 target, d5 on a pack of 5 with the cleave. Class factors are relative to the pack model's base"""
    c, bal = conf()
    raw1, raw5 = P.damage(CLASS, level, tune=False)
    old, new = companion_dps(level, True), companion_dps(level)
    base = P.DAMAGE_BASE[CLASS]
    g_old = class_factor(level, bal['legacy']['classDamage']) / class_factor(level, base)
    g_new = class_factor(level, dump((100,))['classDamage']['beastmaster']) / class_factor(level, base)
    cl = cleave(level)
    before1, before5 = raw1 * g_old, raw5 * g_old * cleave(level, True)
    after1, after5 = (raw1 - old + new) * g_new, (raw5 + new - old) * g_new * cl
    return {'raw1': raw1, 'raw5': raw5, 'old': old, 'new': new, 'before': before1, 'after': after1,
            'share_before': old / raw1, 'share': new / (raw1 - old + new), 'drift1': after1 / before1 - 1,
            'drift5': after5 / before5 - 1, 'g_old': g_old, 'g_new': g_new, 'cleave': cl}


def apply(level, tuned, raw):
    """pack_model.damage() for the Beastmaster: `tuned` is the C4 (+ kit) damage with the class factor of today, `raw`
    without it; the bites of O306 replace the bites the measurement held (they cleave like the rest, pack_model.py
    multiplies the 5 target damage by the cleave). Returns (1 target, 5 targets)"""
    g = tuned[0] / raw[0] if raw[0] else 1.0
    delta = companion_dps(level) - companion_dps(level, True)
    return (raw[0] + delta) * g, (raw[1] + delta) * g


# ------------------------------------------------------------------------------------------------ reports
def report(levels, legacy=False):
    c, bal = conf()
    print('| Level | Health | Taken | Monster dps (burst) | Alive under %d | Hits taken | Bite | Companions | Uptime in a pack | Bites dps | Share of damage | Class total vs before (1 target / pack of 5) |' % bal['attackers'])
    print('|---|---|---|---|---|---|---|---|---|---|---|---|')
    for lv in levels:
        sk = R.stats(CLASS, lv)['SK']
        t = totals(lv)
        lg = legacy
        drift = 'before' if lg else '%+.1f%% / %+.1f%%' % (100 * t['drift1'], 100 * t['drift5'])
        print('| %d | %d | %.2f | %d | %.1f s | %.1f | %d | %d | %.0f%% | %.0f | %.0f%% | %s |' % (
            lv, health(c, lv, lg, bal), taken(c, bal, lg), monster_dps(lv) * bal['burst'], alive_seconds(lv, lg),
            hits_survived(lv, lg), bite(c, lv, sk, lg, bal), cap(c, lv), 100 * uptime(lv, lg),
            t['old'] if lg else t['new'], 100 * (t['share_before'] if lg else t['share']), drift))


def check(levels=None):
    c, bal = conf()
    lim = bal['limits']
    bad = []
    for lv in levels or bal['checkLevels']:
        t = totals(lv)
        s = alive_seconds(lv)
        if s < lim['aliveSecondsMin']:
            bad.append('level %d: a companion lives %.1f s under %d monsters (at least %d s)' % (lv, s, bal['attackers'], lim['aliveSecondsMin']))
        h = hits_survived(lv)
        if h < lim['hitsMin']:
            bad.append('level %d: a companion takes %.1f hits (at least %d)' % (lv, h, lim['hitsMin']))
        u = uptime(lv)
        if u < lim['uptimeMin']:
            bad.append('level %d: a companion is alive %.0f%% of a pack fight (at least %.0f%%)' % (lv, 100 * u, 100 * lim['uptimeMin']))
        lo, hi = lim['share']
        if not lo <= t['share'] <= hi:
            bad.append('level %d: the bites are %.0f%% of the Beastmaster\'s damage (%.0f-%.0f%%)' % (lv, 100 * t['share'], 100 * lo, 100 * hi))
        if abs(t['drift5']) > lim['drift5'] or not lim['drift1'][0] <= t['drift1'] <= lim['drift1'][1]:
            bad.append('level %d: the class total moved %+.1f%% on 1 target and %+.1f%% on a pack of 5 against before (%+.0f..%+.0f%% and at most %.0f%%): retune classDamage.beastmaster in class_tree.lua' % (
                lv, 100 * t['drift1'], 100 * t['drift5'], 100 * lim['drift1'][0], 100 * lim['drift1'][1], 100 * lim['drift5']))
    return bad


def main(argv):
    c, bal = conf()
    levels = tuple(int(x) for x in argv[argv.index('--levels') + 1].split(',')) if '--levels' in argv else tuple(bal['levels'])
    if '--check' in argv:
        bad = check()
        for b in bad:
            print('FAIL ' + b)
        print('companion model: %s' % ('FAIL' if bad else 'ok'))
        return 1 if bad else 0
    report(levels, '--legacy' in argv)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
