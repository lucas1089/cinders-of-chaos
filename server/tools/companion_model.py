#!/usr/bin/env python3
"""The Beastmaster wolves model (O306, O332; computed, not measured in game; server/README.md "Beastmaster companion (O306)"
and "Wolves as the main damage (O332)").

usage: python3 -I server/tools/companion_model.py [--levels 50,100,400,750] [--legacy] [--compare] [--check]

Tester report 2026-10-29 (a level 400 Beastmaster): the companion was 4% of the damage and died in 3 hits of the monsters
of the owner's hunting level, in under 5 s (O306). Tester report 2026-10-29 (a level 750 Beastmaster with every minion damage
passive, both wolves and three support runes on his wolf skill): the wolves' main skill was 10-12% of his damage, a Ranger's
main arrow line 60-70% (O332). What the model answers, per level and build:
  * how long a companion lives when `attackers` monsters of the owner's hunting level go for it (health against their
    damage, with the companion's cut `taken`), and how many hits that is;
  * what the wolves are worth: the companion's own bite (bite = level x autoLevel + distance skill x autoSkill every biteMs,
    in contact with the target `contact` of the time, alive the share of a hunt's pack cycle it lives) and the four wolf spells
    (Feral Command, Pack Frenzy, Pack Howl, Rending Pounce, in the best 5 spells of rotation_sim.py) as a share of the
    Beastmaster's damage, for three builds: plain (no wolf factor), tree (Pack Alpha, the state of the measured totals) and
    full (Pack Alpha and the Trials' minion damage, ChaosClasses.wolfFactor);
  * the class total: the Beastmaster's measured total (pack_model.py C4, level 300 and 1000) held the old bites and the old
    kit. Its spell part is scaled by the rotation of today over the rotation of that kit (the method of pack_model.py KIT:
    `before.sim` of the config holds the old best 5), the bites are added as they are (they are dealt without an event,
    so no class factor, no tree increments), and the class damage factor (class_tree.lua classDamage) puts the class
    back into its pack and boss bands (pack_model.py calls apply() for the Beastmaster).

Inputs (everything in the repo, so CI runs it without the base tree):
  chaos_constants.lua, classes.lua   the companion's numbers and formulas, run by tools/companion_numbers.lua (luajit or
                                     lua5.3; env LUAJIT) so the model uses the server's own functions
  companion_balance_config.lua       the model's inputs, the numbers before O306 and O332 and the limits of --check
  necro_balance_config.lua           what a monster deals to a summon (monsterDps by hunting level)
  trials_nodes.lua                   the Beastmaster's Trials minion damage
  rotation_sim.py                    the owner's distance skill by level, the best 5 spells (WOLF = the wolf factor)
  pack_model.py                      the class total, the pack, its health and the walking time
"""
import json, math, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rotation_sim as R
import pack_model as P

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CLASS = 'Beastmaster'
HIT_S = 2.0  # seconds between the hits of a monster (the stock attack interval)
TRIALS = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'trials_nodes.lua')
WOLF_SPELLS = ('Feral Command', 'Pack Frenzy', 'Pack Howl', 'Rending Pounce')
BUILDS = ('plain', 'tree', 'full')


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


def companion_dps(level, legacy=False, factor=1.0, head=False):
    """raw damage per second of the companions' own bites in a hunt (dealt without an event: no class factor), x the wolf factor;
    head: the bite of the state before O332 (config before.autoLevel / autoSkill)"""
    c, bal = conf()
    skill = R.stats(CLASS, level)['SK']
    if head:
        b = level * bal['before']['autoLevel'] + skill * bal['before']['autoSkill']
    else:
        b = bite(c, level, skill, legacy, bal)
    return cap(c, level) * b / (c['biteMs'] / 1000.0) * bal['contact'] * uptime(level, legacy) * factor


def class_factor(level, points):
    return P.lin([tuple(p) for p in points], level)


def cleave(level, legacy=False, head=False):
    """the pack cleave multiplier of the Beastmaster on a pack of 5 (pace_config.lua cleave; "the companion's hits too");
    legacy: before O306, head: before O332"""
    e = _pack()[0]['cleave'].get(P.VOC[CLASS])
    if not e:
        return 1.0
    high = conf()[1]['legacy']['cleaveHigh'] if legacy else (conf()[1]['before']['cleaveHigh'] if head else e[2])
    return 1 + P.lin([(P.CLEAVE_FROM, e[0]), (P.CLEAVE_TO, high)], level) / 100.0 * min(e[1], 4)


# ------------------------------------------------------------------------------------------------ the builds (O332)
def trials_minion():
    """the Beastmaster's Vocation Trials minion damage in percent: dealMinion of its nodes, one of each pair (trials_nodes.lua)"""
    text = open(TRIALS, encoding='utf-8').read()
    block = text.split('[15] = {', 1)[1].split('\n\t},', 1)[0]
    pairs = [[int(x) for x in re.findall(r'dealMinion = (\d+)', pair)] or [0] for pair in re.split(r'\n\t\t\{n\(', block)[1:]]
    return sum(max(p) for p in pairs)


def wolf_factor(build):
    """the wolf factor (ChaosClasses.wolfFactor) of a build: plain 1, tree = Pack Alpha, full = Pack Alpha x the Trials"""
    pa = 1 + dump((100,))['packAlpha']['bonus']
    return {'plain': 1.0, 'tree': pa, 'full': pa * (1 + trials_minion() / 100.0)}[build]


_spells = []


def _spells_model():
    if not _spells:
        _spells.append(R.load_all())
    return _spells[0]


_best = {}


def best(level, build):
    """(1 target, 5 targets, wolf spells' 1 target, wolf spells' 5 targets, names of the set, the biggest spell's 1 target): the
    Auto setup rotation of the Beastmaster at a level (rotation_sim.py's best 5 of a character with no wolf factor at the
    helper's last breakpoint, what its presets hold) cast by a build: the wolf spells deal x the build's wolf factor, the rest as it is. Damage per
    second in rotation_sim.py units"""
    key = (level, build)
    if key not in _best:
        spells, model = _spells_model()
        R.set_wolf(1.0)
        # the helper's preset of the level: the best 5 of the last level (a new spell, or a stat band) at or below it
        # (the same call as rotation_sim.client_data, which writes game_helperrotation/autorotation_data.lua)
        point = max(b for b in R.breakpoints(spells, model, CLASS) if b <= level)
        words = [s.words for s in R.best_set(R.prepare(R.class_spells(spells, CLASS, point), model, CLASS, point))['spells']]
        R.set_wolf(wolf_factor(build))
        try:
            have = [s for s in R.class_spells(spells, CLASS, level) if R.quest_spell_ok(s, 0)]
            pool = {p.words: p for p in R.prepare(have, model, CLASS, level)}
            rot = R.order([pool[w] for w in words if w in pool])
            hits = []
            _, _, d1, d5 = R.simulate(rot, hits=hits)
        finally:
            R.set_wolf(1.0)
        names = {s['words']: s['name'] for s in spells}
        w1 = sum(h1 for t, h1, h5, w in hits if names[w] in WOLF_SPELLS) / R.HORIZON
        w5 = sum(h5 for t, h1, h5, w in hits if names[w] in WOLF_SPELLS) / R.HORIZON
        top = max([sum(h1 for t, h1, h5, w in hits if w == x) for x in {h[3] for h in hits}] or [0]) / R.HORIZON
        _best[key] = (d1, d5, w1, w5, [s.name for s in rot], top)
    return _best[key]


def before_sim(level):
    """(1 target, 5 targets) of the best 5 of the kit before O332 (config before.sim)"""
    rows = _before()['sim']
    return (P.lin([(r[0], r[1]) for r in rows], level), P.lin([(r[0], r[2]) for r in rows], level))


def _before():
    return conf()[1]['before']


def totals(level, build='tree'):
    """the Beastmaster at a level and build. d1 on 1 target, d5 on a pack of 5 (before the cleave). Class factors are relative
    to the pack model's base: the measured total was taken with it. 'spell1' / 'spell5' is the part of the measured total that
    is the best 5 spells (and the auto attack, which grows with them): it moves with the rotation of today over the old one"""
    c, bal = conf()
    raw1, raw5 = P.damage(CLASS, level, tune=False)
    old = companion_dps(level, True)
    k1, k5 = before_sim(level)
    s2t1, s2t5 = (raw1 - old) / k1, (raw5 - old) / k5
    base = P.DAMAGE_BASE[CLASS]
    g_new = class_factor(level, dump((100,))['classDamage']['beastmaster']) / class_factor(level, base)
    g_head = class_factor(level, _before()['classDamage']) / class_factor(level, base)
    g_old = class_factor(level, bal['legacy']['classDamage']) / class_factor(level, base)
    d1, d5, w1, w5, names, top = best(level, build)
    bites = companion_dps(level, factor=wolf_factor(build))
    spell1, spell5 = s2t1 * d1 * g_new, s2t5 * d5 * g_new
    wolf1, wolf5 = s2t1 * w1 * g_new, s2t5 * w5 * g_new
    head_bites = companion_dps(level, head=True)
    head1 = (raw1 - old + head_bites) * g_head
    head5 = (raw5 - old + head_bites) * g_head
    before1 = raw1 * g_old
    return {'raw1': raw1, 'raw5': raw5, 'old': old, 'bites': bites, 'spell1': spell1, 'spell5': spell5,
            'wolf1': wolf1, 'wolf5': wolf5, 'top1': s2t1 * top * g_new, 'set': names,
            'total1': spell1 + bites, 'total5': spell5 + bites, 'total5c': (spell5 + bites) * cleave(level), 'head5c': head5 * cleave(level, head=True),
            'share': (wolf1 + bites) / (spell1 + bites),
            'share5': (wolf5 + bites) / (spell5 + bites), 'spellshare': wolf1 / (spell1 + bites),
            'bitesshare': bites / (spell1 + bites), 'topshare': s2t1 * top * g_new / (spell1 + bites),
            'head1': head1, 'head5': head5, 'before1': before1, 's2t1': s2t1, 's2t5': s2t5, 'g_new': g_new,
            'g_head': g_head, 'g_old': g_old, 'cleave': cleave(level)}


def apply(level, tuned, raw):
    """pack_model.damage() for the Beastmaster: the measured total is replaced by the model's tree build (Pack Alpha, the
    state the class totals and bands are about). `raw` is the C4 (+ kit) damage without the class factor (kept for the
    signature); the class factor, the new kit and the wolves are in totals(). Returns (1 target, 5 targets)"""
    t = totals(level, 'tree')
    return t['total1'], t['total5']


# ------------------------------------------------------------------------------------------------ reports
def report(levels, legacy=False):
    c, bal = conf()
    print('| Level | Health | Taken | Monster dps (burst) | Alive under %d | Hits taken | Bite | Companions | Uptime in a pack | Bites dps (plain) | Share of damage: wolves plain / tree / full | Class total tree vs before O332 (1 target / pack of 5) |' % bal['attackers'])
    print('|---|---|---|---|---|---|---|---|---|---|---|---|')
    for lv in levels:
        sk = R.stats(CLASS, lv)['SK']
        lg = legacy
        if lg:
            t0 = None
            share, drift = '%.0f%%' % (100 * companion_dps(lv, True) / P.damage(CLASS, lv, tune=False)[0]), 'before'
            bites = companion_dps(lv, True)
        else:
            ts = {b: totals(lv, b) for b in BUILDS}
            t = ts['tree']
            share = ' / '.join('%.0f%%' % (100 * ts[b]['share']) for b in BUILDS)
            drift = '%+.1f%% / %+.1f%%' % (100 * (t['total1'] / t['head1'] - 1), 100 * (t['total5c'] / t['head5c'] - 1))
            bites = ts['plain']['bites']
        print('| %d | %d | %.2f | %d | %.1f s | %.1f | %d | %d | %.0f%% | %.0f | %s | %s |' % (
            lv, health(c, lv, lg, bal), taken(c, bal, lg), monster_dps(lv) * bal['burst'], alive_seconds(lv, lg),
            hits_survived(lv, lg), bite(c, lv, sk, lg, bal), cap(c, lv), 100 * uptime(lv, lg), bites, share, drift))


def compare(levels):
    """the wolves of the full build against the Necromancer line's minions (minion_model.py) and a Ranger's main skill:
    the share of the damage each one's biggest source is (rotation_sim.py, per class: the best set's spell with most damage)"""
    spells, model = _spells_model()
    names = {s['words']: s['name'] for s in spells}
    print('| Level | Beastmaster wolves, full | its main wolf spell | Beastmaster, plain | Ranger main skill | Deadeye main skill | Necromancer minions (minion_model.py) |')
    print('|---|---|---|---|---|---|---|')
    import minion_model as M
    for lv in levels:
        full, plain = totals(lv, 'full'), totals(lv, 'plain')
        mains = []
        for cls in ('Ranger', 'Deadeye'):
            a = R.analyse(spells, model, cls, lv)
            hits = []
            R.simulate(a['best']['spells'], hits=hits)
            per = {}
            for t, h1, h5, w in hits:
                per[w] = per.get(w, 0) + h1
            mains.append('%s %.0f%%' % (names[max(per, key=per.get)], 100 * max(per.values()) / sum(per.values())))
        m = M.model_class('necromancer', lv, levels=tuple(levels))
        nec = '%.0f%% (alive %.0f%%)' % (100 * m['share1_full'], 100 * m['share1'])
        print('| %d | %.0f%% | %.0f%% | %.0f%% | %s | %s | %s |' % (lv, 100 * full['share'], 100 * full['topshare'],
                                                                   100 * plain['share'], mains[0], mains[1], nec))


def check(levels=None):
    c, bal = conf()
    lim = bal['limits']
    bad = []
    for lv in levels or bal['checkLevels']:
        s = alive_seconds(lv)
        if s < lim['aliveSecondsMin']:
            bad.append('level %d: a companion lives %.1f s under %d monsters (at least %d s)' % (lv, s, bal['attackers'], lim['aliveSecondsMin']))
        h = hits_survived(lv)
        if h < lim['hitsMin']:
            bad.append('level %d: a companion takes %.1f hits (at least %d)' % (lv, h, lim['hitsMin']))
        u = uptime(lv)
        if u < lim['uptimeMin']:
            bad.append('level %d: a companion is alive %.0f%% of a pack fight (at least %.0f%%)' % (lv, 100 * u, 100 * lim['uptimeMin']))
        ts = {b: totals(lv, b) for b in BUILDS}
        early = lv < lim['earlyBelow']
        for b, key in (('plain', 'shareEarlyPlain' if early else 'sharePlain'), ('tree', 'shareEarlyTree' if early else 'shareTree'),
                       ('full', 'shareFull')):
            if b == 'full' and lv < bal['fullFrom']:
                continue
            lo, hi = lim[key]
            if not lo <= ts[b]['share'] <= hi:
                bad.append('level %d: the wolves are %.0f%% of the %s Beastmaster\'s damage (%.0f-%.0f%%)' % (lv, 100 * ts[b]['share'], b, 100 * lo, 100 * hi))
        t = ts['tree']
        lo, hi = lim['plainOverTree']
        r = ts['plain']['total1'] / t['total1']
        if not lo <= r <= hi:
            bad.append('level %d: the plain build deals %.0f%% of the tree build (%.0f-%.0f%%): a bow Beastmaster must stay viable' % (lv, 100 * r, 100 * lo, 100 * hi))
        if lv >= bal['fullFrom']:
            lo, hi = lim['fullOverTree']
            r = ts['full']['total1'] / t['total1']
            if not lo <= r <= hi:
                bad.append('level %d: the full build deals %.0f%% of the tree build (%.0f-%.0f%%)' % (lv, 100 * r, 100 * lo, 100 * hi))
        d1, d5 = t['total1'] / t['head1'] - 1, t['total5c'] / t['head5c'] - 1
        if abs(d5) > lim['drift5'] or not lim['drift1'][0] <= d1 <= lim['drift1'][1]:
            bad.append('level %d: the class total moved %+.1f%% on 1 target and %+.1f%% on a pack of 5 against before O332 (%+.0f..%+.0f%% and at most %.0f%%): retune classDamage.beastmaster in class_tree.lua' % (
                lv, 100 * d1, 100 * d5, 100 * lim['drift1'][0], 100 * lim['drift1'][1], 100 * lim['drift5']))
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
    if '--compare' in argv:
        compare(levels)
        return 0
    report(levels, '--legacy' in argv)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
