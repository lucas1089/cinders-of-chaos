#!/usr/bin/env python3
"""The PvP model (O444): how fast every class kills the median class and dies to it, and who wins a duel of two classes at the same
level (COMPUTED, not measured: no PvP DPS test was ever run on a server; server/README.md "PvP model (O444)").

usage: python3 -I server/tools/pvp_model.py [--levels 100,500,1000] [--matrix LEVEL [--heal]] [--detail] [--check | --scale | --round-before]

Output, per class and level (100, 500, 1000):
  burst     the damage the class deals in the first 3 seconds of a fight (its best Auto setup rotation from a cold start, rotation_sim.py
            simulate with a 3 s horizon over the same set at 120 s, times the class's damage per second) as a share of the median
            class's health pool, after the PvP rules and the median class's layers
  kill      seconds to kill the median class with no healing and with its healing (potions and self heal, PvP healing reduction);
            "never" when the healing is at least the damage
  die       seconds to die to the median class, no healing and with the class's own healing
  duels     wins / losses / draws against the 20 other classes (one duel per pair at the same level, both sides with their healing)
  first     "yes" when the class kills the median class before the median class kills it (with healing), "no", or "draw"

Inputs, all read from the repo (nothing copied):
  class damage    class_dps_model.py `dps()` (1 target: a duel is one target; no pack cleave, which is a pace layer and PvP is never
                  touched by pace_config.lua), the measured table of 2026-11-06 moved by every change since (O444: the one source)
  burst           rotation_sim.py: the class's best set at the level, damage landing in the first 3 s over the damage of 120 s
  toughness       survival_model.py `survive()` with the class's role build of median burst: health pool (a mana shield line adds its
                  mana), armour, physical and elemental absorb, dodge, class toughness, the Ninja guard, healing per second (potions
                  plus self heal). The hunt pack is swapped for a 50 / 50 physical and elemental one: only the layers are used
  PvP rules       the engine halves damage between players (ENGINE_PVP_DAMAGE below; data/spells/README.md "PvP (tested with two
                  characters on the test server)"; no config holds it); healing_rules_core.lua pvp.healingTaken (0.70) on every heal a
                  player in PvP combat gets; the battleground's level normalisation (battleground_config.lua normalise) is x1 between
                  two players of one level (within 4% at the edge of a bracket, where its clamps differ), so a duel at one level has
                  none; the arena's fightSeconds (arena_config.lua) ends a fight
                  nobody wins and the higher health share takes it
  limits          pvp_balance_config.lua

The model, for an attacker A and a defender D at one level:
  incoming damage of D   = A's damage per second x ENGINE_PVP_DAMAGE x D's layers (the attack is `physicalShare` physical, the rest
                           elemental; physical: armour, physical absorb, dodge; elemental: elemental absorb; both: toughness and guard)
  time to kill D         = D's pool / (incoming damage - D's healing x healingTaken), "never" when that is not above 0
  a duel                 the side that kills first wins; kill times within `drawBand` of each other are a draw; when nobody dies inside
                           fightSeconds the health share left decides (a difference under `drawBand` is a draw); two classes that heal
                           more than they take are a draw
Not in it: movement, line of sight, stuns, snares and crowd control (Monk stun, Beastmaster's wolves as separate targets: the wolves'
damage is in the class damage but they would also take hits), potions run out or are on a cooldown (one Everfull potion a second is
survival_balance_config.lua), mana, gear and build choices other than the Auto builds, gems and uniques, the level normalisation
between two levels, parties (2v2, 3v3, battleground) and healers healing a partner. It is a screen for a one shot, an unkillable class
and a class that wins nearly every duel, not a forecast of a ladder.

--check (CI): at every level of pvp_balance_config.lua `levels`: no class's burst is above burstMax, none kills the median class in
under killMin seconds with no healing, none needs more than killMax seconds with its healing (never counts), no class wins or loses
more than duelShareMax of its 20 duels; a class with a row in `exceptions` has its own limit for the named metric.
"""
import math
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)  # python -I leaves the script's folder out of sys.path
import class_dps_model as CD  # noqa: E402
import rotation_sim as R  # noqa: E402
import survival_model as S  # noqa: E402

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')
CONFIG = os.path.join(CHAOS, 'pvp_balance_config.lua')
ARENA = os.path.join(CHAOS, 'arena_config.lua')
BATTLEGROUND = os.path.join(CHAOS, 'battleground_config.lua')
HEALING = os.path.join(CHAOS, 'healing_rules_core.lua')
PACE = os.path.join(CHAOS, 'pace_config.lua')

# the base engine halves damage between players, spells and weapons alike (README "PvP (tested with two characters on the test
# server)", 2026-10: Hail of Dawn 1830 against a level 300 knight with no armour). No config file holds it
ENGINE_PVP_DAMAGE = 0.5
INF = float('inf')
NAMES = list(CD.KEY)  # the 21 classes in class_dps_model order
KEY = CD.KEY


# ------------------------------------------------------------------------------------------------ the config files
def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def config(text=None):
    """pvp_balance_config.lua: {'levels': [...], scalars..., 'exceptions': {class: {metric: value}}}"""
    text = text if text is not None else read(CONFIG)
    out = {'levels': [int(x) for x in re.search(r'levels = \{([0-9, ]+)\}', text).group(1).split(',') if x.strip()]}
    body = text.split('exceptions = {', 1)
    head = body[0]
    for k, v in re.findall(r'(?m)^\t(\w+) = ([-0-9.]+)', head):
        out[k] = float(v)
    # O473: the PvP damage scale, {level, factor} rows (pvp_scale_core.lua applies it in the game, once, for every path)
    ds = re.search(r'damageScale = \{(\{.*?\})\},?\s*\n', head)
    out['damageScale'] = [(int(a), float(b)) for a, b in re.findall(r'\{(\d+), ([0-9.]+)\}', ds.group(1))] if ds else []
    out['exceptions'] = {}
    if len(body) > 1:
        for cls, row in re.findall(r'\["([^"]+)"\] = \{([^}]*)\}', body[1]):
            out['exceptions'][cls] = {k: float(v) for k, v in re.findall(r'(\w+) = ([-0-9.]+)', row)}
    return out


def rules(arena=None, bg=None, healing=None, pace=None):
    """the PvP rules of the configs: {'fightSeconds', 'levelRatio', 'normalise': (exponent, min, max), 'healingTaken', 'windowMs',
    'paceSkipsPvp'}"""
    arena = arena if arena is not None else read(ARENA)
    bg = bg if bg is not None else read(BATTLEGROUND)
    healing = healing if healing is not None else read(HEALING)
    pace = pace if pace is not None else read(PACE)
    nm = re.search(r'normalise = \{exponent = ([0-9.]+), minFactor = ([0-9.]+), maxFactor = ([0-9.]+)\}', bg)
    ht = re.search(r'pvp = \{healingTaken = ([0-9.]+), windowMs = (\d+)\}', healing)
    return {'fightSeconds': float(re.search(r'fightSeconds = (\d+)', arena).group(1)),
            'levelRatio': float(re.search(r'level = \{ratio = ([0-9.]+)', arena).group(1)),
            'normalise': tuple(float(x) for x in nm.groups()),
            'healingTaken': float(ht.group(1)), 'windowMs': int(ht.group(2)),
            'paceSkipsPvp': 'PvP is never touched' in pace}


def normalise(src, tgt, ref, rule):
    """battleground_config.lua normalise: damage or healing between players x (ref / source level)^e x (target level / ref)^e, each
    factor clamped to [minFactor, maxFactor]; 1 between two players of the same level"""
    e, lo, hi = rule
    clamp = lambda x: max(lo, min(hi, x))  # noqa: E731
    return clamp((ref / float(src)) ** e) * clamp((tgt / float(ref)) ** e)


# ------------------------------------------------------------------------------------------------ the inputs
_CACHE = {}


def burst_factors(levels):
    """{(class, level): (damage per second in the first 3 s) / (damage per second over 120 s)} of the class's best set"""
    key = ('burst', tuple(levels))
    if key not in _CACHE:
        spells, model = R.load_all()
        out = {}
        for lv in levels:
            for cls in NAMES:
                rot = R.analyse(spells, model, cls, lv)['best']['spells']
                full = R.simulate(rot)[2]
                first = R.simulate(rot, horizon=3.0)[2]
                out[(cls, lv)] = first / full if full > 0 else 1.0
        _CACHE[key] = out
    return _CACHE[key]


def layers(levels):
    """{(class, level): layers} from survival_model.survive: pool, health, armour reduction, absorbs, dodge, toughness, guard,
    healing per second. The role build of median burst against a 50 / 50 physical and elemental pack (survival_model.table's rule)"""
    key = ('layers', tuple(levels))
    if key not in _CACHE:
        bal = dict(S.dump([1000])['balance'])
        gear, varm = S.gear_curves(), S.vocation_armour()
        pack = {'melee': 0.0, 'physical': 500.0, 'element': 500.0, 'meleeHits': 0.0}
        out = {}
        for lv in levels:
            d = S.dump([lv])
            for cls in NAMES:
                ck = KEY[cls]
                cands = [S.survive(d, bal, ck, lv, b, pack, gear, varm) for b in d['builds'][ck][str(lv)]]
                cands.sort(key=lambda r: r['burst'])
                r = cands[len(cands) // 2]
                out[(cls, lv)] = {k: r[k] for k in ('pool', 'health', 'armourRed', 'absorbPhys', 'absorbElem', 'dodge', 'toughness',
                                                    'guard', 'heal', 'build')}
        _CACHE[key] = out
    return _CACHE[key]


def inputs(levels, rnd=True):
    """everything the model reads, once: {'dps': {(class, level): damage per second, 1 target}, 'burst': ..., 'layers': ...}.
    rnd (O475): the class damage after the balance round (class_dps_model.dps); rnd=False is the damage before it"""
    return {'dps': {(c, lv): CD.dps(c, lv, rnd=rnd)[0] for c in NAMES for lv in levels}, 'burst': burst_factors(levels),
            'layers': layers(levels)}


# ------------------------------------------------------------------------------------------------ the formulas
def mitigation(lay, physical_share):
    """the share of an attack that gets through a defender's layers: toughness x (1 - guard) x (physical share x armour x physical
    absorb x dodge + the rest x elemental absorb)"""
    phys = (1 - lay['armourRed']) * (1 - lay['absorbPhys']) * (1 - lay['dodge'])
    elem = 1 - lay['absorbElem']
    return lay['toughness'] * (1 - lay['guard']) * (physical_share * phys + (1 - physical_share) * elem)


def incoming(dps, lay, physical_share, pvp=ENGINE_PVP_DAMAGE):
    """damage per second a defender takes from an attacker dealing `dps` against nobody (PvP rules in)"""
    return dps * pvp * mitigation(lay, physical_share)


def kill_time(pool, damage, heal):
    """seconds to kill a defender of this pool: INF when its healing is at least the damage taken"""
    net = damage - heal
    return pool / net if net > 1e-9 else INF


def share_left(pool, damage, heal, seconds):
    """health share of a defender left after `seconds` of the damage and the healing (1 when the healing wins)"""
    return max(0.0, 1.0 - max(0.0, damage - heal) * seconds / pool)


def duel(pool_a, in_a, heal_a, pool_b, in_b, heal_b, fight, band):
    """one duel of A and B: in_x is the damage per second X takes, heal_x its healing per second. 'win' / 'loss' / 'draw' for A"""
    ta, tb = kill_time(pool_b, in_b, heal_b), kill_time(pool_a, in_a, heal_a)  # A kills B in ta, B kills A in tb
    if ta == INF and tb == INF:
        return 'draw'
    if min(ta, tb) <= fight:
        if ta < tb * (1 - band):
            return 'win'
        if tb < ta * (1 - band):
            return 'loss'
        return 'draw'
    sa, sb = share_left(pool_a, in_a, heal_a, fight), share_left(pool_b, in_b, heal_b, fight)
    return 'win' if sa - sb > band else 'loss' if sb - sa > band else 'draw'


def median_layers(lays):
    """the median defender of a level: the median of every layer over the classes"""
    return {k: statistics.median(l[k] for l in lays) for k in ('pool', 'health', 'armourRed', 'absorbPhys', 'absorbElem', 'dodge',
                                                                  'toughness', 'guard', 'heal')}


def solve(data, cfg, rule, levels=None, scaled=True):
    """{level: {'rows': {class: row}, 'matrix': {(a, b): verdict for a, damage race}, 'matrixHeal': {...with healing}, 'median': {...}}}.
    The damage race has no healing: it is the question "who is ahead after the burst", the one the limits are about. With healing
    the potions (one Everfull potion a second, survival_balance_config.lua) out-heal what a class deals to a player, so every
    duel is a draw (see the module docstring and server/README.md "PvP model (O444)")"""
    levels = levels or cfg['levels']
    share, band, fight = cfg['physicalShare'], cfg['drawBand'], rule['fightSeconds']
    taken = rule['healingTaken']
    out = {}
    for lv in levels:
        lays = {c: data['layers'][(c, lv)] for c in NAMES}
        # O475: a player's damage to another player is x the PvP scale of the attacker's level (pvp_scale_core.lua); a duel is two
        # players of one level. scaled=False leaves it out (the state before the round, --round-before)
        scale = damage_scale(lv, cfg) if scaled else 1.0
        dps = {c: data['dps'][(c, lv)] * scale for c in NAMES}
        med = median_layers(lays.values())
        med_dps = statistics.median(dps.values())
        med_pool = med['pool']
        med_heal = med['heal'] * taken
        rows = {}
        for c in NAMES:
            lay = lays[c]
            heal = lay['heal'] * taken
            din = incoming(dps[c], med, share)  # the median class takes this from c
            burst_dmg = cfg['burstSeconds'] * dps[c] * data['burst'][(c, lv)] * ENGINE_PVP_DAMAGE * mitigation(med, share)
            dback = incoming(med_dps, lay, share)  # c takes this from the median class
            rows[c] = {'dps': dps[c], 'burstFactor': data['burst'][(c, lv)], 'burst': burst_dmg / med_pool,
                       'kill0': kill_time(med_pool, din, 0.0), 'kill1': kill_time(med_pool, din, med_heal),
                       'die0': kill_time(lay['pool'], dback, 0.0), 'die1': kill_time(lay['pool'], dback, heal),
                       'sustain': heal / dback if dback > 0 else INF, 'pool': lay['pool'], 'heal': heal, 'in': din,
                       'first': duel(lay['pool'], dback, 0.0, med_pool, din, 0.0, fight, band),
                       'firstHeal': duel(lay['pool'], dback, heal, med_pool, din, med_heal, fight, band)}
        matrix, matrix_heal = {}, {}
        for a in NAMES:
            for b in NAMES:
                if a == b:
                    continue
                in_b = incoming(dps[a], lays[b], share)
                in_a = incoming(dps[b], lays[a], share)
                ha, hb = lays[a]['heal'] * taken, lays[b]['heal'] * taken
                matrix[(a, b)] = duel(lays[a]['pool'], in_a, 0.0, lays[b]['pool'], in_b, 0.0, fight, band)
                matrix_heal[(a, b)] = duel(lays[a]['pool'], in_a, ha, lays[b]['pool'], in_b, hb, fight, band)
        for a in NAMES:
            v = [matrix[(a, b)] for b in NAMES if b != a]
            vh = [matrix_heal[(a, b)] for b in NAMES if b != a]
            rows[a].update(wins=v.count('win'), losses=v.count('loss'), draws=v.count('draw'),
                           winsHeal=vh.count('win'), lossesHeal=vh.count('loss'), drawsHeal=vh.count('draw'))
        out[lv] = {'rows': rows, 'matrix': matrix, 'matrixHeal': matrix_heal,
                   'median': {'pool': med_pool, 'dps': med_dps, 'heal': med_heal, 'layers': med}}
    return out


# ------------------------------------------------------------------------------------------------ the limits
GENERAL = {'burst': 'burstMax', 'killMin': 'killMin', 'killMax': 'killMax', 'dieMin': 'dieMin', 'sustain': 'sustainMax',
           'wins': 'duelShareMax', 'losses': 'duelShareMax'}


def limit(cfg, cls, metric, level=None):
    """the limit of a metric for a class: its row in `exceptions` ("Class@100" for one level, "Class" for all), else the general
    one (the duel share is of the 20 duels)"""
    for key in ('%s@%s' % (cls, level), cls):
        own = cfg['exceptions'].get(key, {})
        if metric in own:
            return own[metric]
    v = cfg[GENERAL[metric]]
    return v * 20 if metric in ('wins', 'losses') else v


def value(row, metric):
    return {'burst': row['burst'], 'killMin': row['kill0'], 'killMax': row['kill0'], 'dieMin': row['die0'], 'sustain': row['sustain'],
            'wins': row['wins'], 'losses': row['losses']}[metric]


def passes(metric, v, lim):
    """a metric against its limit: killMin and dieMin at least, the others at most"""
    return v >= lim if metric in ('killMin', 'dieMin') else v <= lim


def problems(res, cfg):
    """the failures of the limits: ['class level metric: value against limit']"""
    bad = []
    for lv, t in sorted(res.items()):
        for c in NAMES:
            for m in GENERAL:
                v, lim = value(t['rows'][c], m), limit(cfg, c, m, lv)
                if not passes(m, v, lim):
                    bad.append('%s level %d, %s: %s against the limit %s' % (c, lv, m, fmt(v), fmt(lim)))
    return bad + scale_problems(cfg)


def damage_scale(level, cfg):
    """the PvP damage scale of an attacker's level (pvp_scale_core.lua: geometric between two rows, flat outside). Applied to the
    damage of this model since O475 (solve(scaled=True)): the class damage is the typical damage after the round, the scale
    brings the seconds to kill back to the model before the round (fit_scale() below, server/README.md "Final re-fit (O475)")."""
    rows = cfg.get('damageScale') or []
    if not rows:
        return 1.0
    if level <= rows[0][0]:
        return rows[0][1]
    if level >= rows[-1][0]:
        return rows[-1][1]
    for (l0, f0), (l1, f1) in zip(rows, rows[1:]):
        if level <= l1:
            return math.exp(math.log(f0) + (math.log(f1) - math.log(f0)) * (level - l0) / float(l1 - l0))
    return rows[-1][1]


def fit_scale(level):
    """the scale that holds the seconds to kill of the median class where they were before the round: the median class damage
    before / after at the level (one target; the layers of the defender are the same before and after, so the seconds to kill
    move with the damage alone)"""
    return CD.median_dps(level, rnd=False)[0] / CD.median_dps(level)[0]


def scale_problems(cfg):
    """the shape of the scale table: ascending levels, factors in (0, 2]"""
    rows = cfg.get('damageScale') or []
    bad = []
    if not rows:
        bad.append('damageScale: no table in pvp_balance_config.lua')
    for (l0, _), (l1, _) in zip(rows, rows[1:]):
        if l1 <= l0:
            bad.append('damageScale: levels do not ascend at %d' % l1)
    for lv, f in rows:
        if not 0 < f <= 2.0:
            bad.append('damageScale: the factor at level %d is %s, not in (0, 2]' % (lv, f))
        # O475: the table is the fit that holds the duels where they were before the round (fit_scale), within 1.5%
        if abs(f / fit_scale(lv) - 1) > 0.015:
            bad.append('damageScale: the factor at level %d is %s, the fit is %.3f (python3 -I server/tools/pvp_model.py --scale)' % (
                lv, f, fit_scale(lv)))
    return bad


def own_row(cfg, cls, metric, level):
    """True when the limit of this class, level and metric comes from a row of `exceptions`"""
    return any(metric in cfg['exceptions'].get(k, {}) for k in ('%s@%s' % (cls, level), cls))


def near(res, cfg, margin=0.10):
    """[(class, level, metric, value, limit)] of the checks that pass within `margin` (relative) of their limit"""
    out = []
    for lv, t in sorted(res.items()):
        for c in NAMES:
            for m in GENERAL:
                v, lim = value(t['rows'][c], m), limit(cfg, c, m, lv)
                if not passes(m, v, lim) or v == INF or lim == 0:
                    continue
                if (m in ('killMin', 'dieMin') and v <= lim * (1 + margin)) or (m not in ('killMin', 'dieMin') and v >= lim * (1 - margin)):
                    out.append((c, lv, m, v, lim))
    return out


def fmt(v):
    return 'never' if v == INF else '%.2f' % v if v < 10 else '%.1f' % v if v < 1000 else '%.0f' % v


# ------------------------------------------------------------------------------------------------ the report
def report(res, detail=False):
    for lv, t in sorted(res.items()):
        m = t['median']
        print('\n== level %d: the median class has a pool of %.0f, deals %.0f a second and heals %.0f a second in PvP' % (
            lv, m['pool'], m['dps'], m['heal']))
        head = '%-12s %6s %6s %8s %9s %8s %9s %7s %9s  %s' % ('class', 'dps', 'burst', 'kill s', 'kill+heal', 'die s', 'die+heal',
                                                            'sustain', 'duels W/L/D', 'first')
        if detail:
            head += '  %6s %6s %6s' % ('pool', 'heal', 'b.fact')
        print(head)
        for c in NAMES:
            r = t['rows'][c]
            line = '%-12s %6.0f %6.2f %8s %9s %8s %9s %7.2f %5d/%d/%-2d  %s' % (
                c, r['dps'], r['burst'], fmt(r['kill0']), fmt(r['kill1']), fmt(r['die0']), fmt(r['die1']), r['sustain'],
                r['wins'], r['losses'], r['draws'], r['first'])
            if detail:
                line += '  %6.0f %6.0f %6.2f' % (r['pool'], r['heal'], r['burstFactor'])
            print(line)
        print('duels with healing: %d wins, %d losses, %d draws of %d (every duel a draw means the healing out-heals the damage)' % (
            sum(r['winsHeal'] for r in t['rows'].values()), sum(r['lossesHeal'] for r in t['rows'].values()),
            sum(r['drawsHeal'] for r in t['rows'].values()), len(NAMES) * (len(NAMES) - 1)))


def matrix_report(t, heal=False):
    short = {c: c[:3] for c in NAMES}
    mx = t['matrixHeal' if heal else 'matrix']
    print('row against column: W win, L loss, . draw (%s)' % ('with healing' if heal else 'damage race, no healing'))
    print('     ' + ' '.join(short[c] for c in NAMES))
    for a in NAMES:
        print('%-4s ' % short[a] + ' '.join('  -' if a == b else '  ' + {'win': 'W', 'loss': 'L', 'draw': '.'}[mx[(a, b)]]
                                           for b in NAMES))


def summary(res):
    """{level: (decisive duels, draws, pairs)} over the 210 pairs of the damage race"""
    out = {}
    for lv, t in res.items():
        v = [t['matrix'][(a, b)] for i, a in enumerate(NAMES) for b in NAMES[i + 1:]]
        out[lv] = (len(v) - v.count('draw'), v.count('draw'), len(v))
    return out


def main(argv):
    cfg = config()
    levels = [int(x) for x in argv[argv.index('--levels') + 1].split(',')] if '--levels' in argv else cfg['levels']
    rule = rules()
    if '--scale' in argv:
        print('level  median dps before  after  scale (fit)  seconds to kill the median class: before / after with the scale')
        for lv in (100, 200, 300, 500, 700, 850, 1000, 1500, 2000):
            b, a = CD.median_dps(lv, rnd=False)[0], CD.median_dps(lv)[0]
            f = fit_scale(lv)
            print('%5d  %17.0f %6.0f  %.3f  (table %.3f)' % (lv, b, a, f, damage_scale(lv, cfg)))
        return 0
    if '--round-before' in argv:
        report(solve(inputs(levels, rnd=False), cfg, rule, levels, scaled=False), '--detail' in argv)
        return 0
    data = inputs(levels)
    res = solve(data, cfg, rule, levels)
    if '--matrix' in argv:
        lv = int(argv[argv.index('--matrix') + 1])
        matrix_report(res[lv], '--heal' in argv)
        return 0
    if '--check' not in argv:
        report(res, '--detail' in argv)
        return 0
    bad = problems(res, cfg)
    for b in bad:
        print('FAIL ' + b)
    nr = near(res, cfg)
    for c, lv, m, v, lim in nr:
        print('near %s level %d, %s: %s against the limit %s%s' % (c, lv, m, fmt(v), fmt(lim),
                                                                  ' (its own row: an exception)' if own_row(cfg, c, m, lv) else ''))
    print('pvp check: %s (21 classes, levels %s; computed, not measured)' % (
        'FAIL (%d)' % len(bad) if bad else 'ok', ','.join(str(x) for x in levels)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
