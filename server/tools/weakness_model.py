#!/usr/bin/env python3
"""The weakness model: what each class pays for its strength (computed, not measured in game; server/data/spells/README.md
"Class weaknesses (measured)"). Step 3 of the class identity plan (docs/CLASSES.md "Class identity (2026-10-28)"); steps 1
and 2 are pack_model.py and boss_model.py, which measure the strengths.

usage: python3 -I server/tools/weakness_model.py [--levels 300,800,1000,1200] [--findings] [--check]

Per class and level it reports three things, from the models and data that already exist (no new balance number):

  * Mana pressure. The best rotation of rotation_sim.py (the helper's auto rotation, class spell factor and fixed spell costs
    included) spends so much mana a minute; the vocation regenerates so much (chaos_vocations*.xml) plus the level mana flow
    (mana_flow_config.lua). The runway is how long the best set runs from a full pool: the pool (start_stats.lua, the mana gain
    of the vocation) over the net drain. `runway (own)` is the number of `rotation_sim.py --mana` (vocation regeneration only);
    `runway` has the level flow on top. No potion is assumed: the existing runway check assumes none either (rotation_sim.py
    mana_stats). `drain` is the pools the rotation burns in a minute (mana spent a minute over the pool).
  * Ramp-up. Seconds until the class reaches RAMP_SHARE (80%) of its steady damage from a cold start (a fresh pull, no buff,
    no minion out, no chi). The damage dealt since the start over the damage a steady class would have dealt by then must stay
    at 80% or more from that second on. The rotation is rotation_sim.simulate (its chi: +1 a 2 s auto attack hit, a finisher
    waits for 4 chi); the Necromancer line adds its minions: raised one by one by the support group (2 s) and each spell's own
    cooldown (Raise Bone Warrior / Mage 4 s, Raise Dead 2 s with no corpse to raise from, one minion a cast, Bone Golem 30 s), each
    hitting `minionTravel` seconds plus its class's first strike delay (necro_config.lua minions.firstStrikeMs) after it arrives, weighted by minion_model.py (the tree factor, the alive share, the wand).
    Damage buffs are cast before the pull in every balance model and the auto attack is not in rotation_sim, so both stay out.
  * Exposure. The share of the class's damage on one target that is dealt from a reach of 1 (melee exposure), of 2 and of 3 or
    more (ranged): the best rotation's spell hits, plus the weapon (`autoShare` of weakness_config.lua of the damage, the share
    the Templar's auto attack holds in server/data/spells/README.md "Templar line": 30-44%; a wand holds the 15% of the Mystic's
    spells the minion model uses; reach 1 for the sword, the fist and the dagger, 3 or more for a bow, a crossbow, a wand). The reach of a spell is its `range` in spells_chaos.xml; a spell without one (cast on the caster's
    tile) has the radius of its area (AREA_CIRCLE / AREA_SQUARE in its script, else the attack kit's radius, else the `reach`
    table of weakness_config.lua: the stock spells, whose files are not in the repo, and two area strikes that build their area
    by hand). Effective health per level is the vocation's health gain over the damage taken factor of the toughness model
    (`toughness` of weakness_config.lua: Juggernaut, Sentinel, Samurai as server/data/spells/README.md "Templar line" and
    "Classes with the passive trees" state them; every other class 1.0); `ehp` is the base health at the level over the factor.
    No gear, tree, evasion or shield: the base the classes start from.

--findings prints the intended weaknesses (docs/CLASSES.md "Class weaknesses (measured)") that do not hold today, each with a
lever. --check (CI) pins the identity facts that hold today (weakness_config.lua `pins`); it never pins a number of the tables,
only an order (who is lowest, who is slowest, who is most ranged), so tuning that keeps the identity passes.
"""
import functools
import itertools
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rotation_sim as R  # noqa: E402
import pack_model as PM  # noqa: E402
import minion_model as MM  # noqa: E402

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'weakness_config.lua')
KIT_CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'attack_kit_config.lua')
NECRO_CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'necro_config.lua')
DEFAULT_LEVELS = (300, 800, 1000, 1200)
CLASSES = [c for c, _, _ in R.CLASSES]
LINE = {c: l for c, l, _ in R.CLASSES}
LINES = ['Warrior', 'Ranger', 'Mystic', 'Thief', 'Necromancer', 'Monk', 'Templar']
MINION_KEY = {'Necromancer': 'necromancer', 'Lich': 'lich', 'Bone Lord': 'bonelord'}
LIMITS = ('atleast', 'atmost')   # pin kinds with a value instead of a rank
GRID = 0.25            # seconds between two points of the ramp curve
RAMP_FROM = 2.0        # the curve starts after one attack group cooldown: one cast does not decide a ramp
RAMP_TO = 60.0         # a class that is still under the share here has no ramp the model can name (reported as this)
STEADY_FROM = 30.0     # the steady spans start from here (a cooldown cycle is over by then)
SUPPORT_GCD = 2.0      # the support group cooldown of the summon spells (spells_chaos.xml)


# ------------------------------------------------------------------------------------------------ config
def config(text=None):
    """weakness_config.lua: {'levels', 'rampShare', 'minionTravel', 'raisePerCast', 'autoShare': {kind: share}, 'toughness':
    {class: factor}, 'reach': {spell: reach}, 'pins': [(rank, measure, scope, n, [names])]}"""
    text = text if text is not None else open(CONFIG, encoding='utf-8').read()
    out = {'levels': [int(x) for x in re.search(r'levels = \{([0-9, ]+)\}', text).group(1).split(',') if x.strip()],
           'rampShare': float(re.search(r'rampShare = ([0-9.]+)', text).group(1)),
           'minionTravel': float(re.search(r'minionTravel = ([0-9.]+)', text).group(1)),
           'raisePerCast': int(re.search(r'raisePerCast = (\d+)', text).group(1))}
    for key in ('toughness', 'reach'):
        block = re.search(r'\b' + key + r' = \{(.*?)\n\t\}', text, re.S).group(1)
        out[key] = {n: float(v) for n, v in re.findall(r'\["([^"]+)"\] = ([0-9.]+)', block)}
    block = re.search(r'\bautoShare = \{(.*?)\}', text, re.S).group(1)
    out['autoShare'] = {k: float(v) for k, v in re.findall(r'(\w+) = ([0-9.]+)', block)}
    pins = re.search(r'\bpins = \{(.*?)\n\t\}', text, re.S).group(1)
    out['pins'] = []
    for s in re.findall(r'"([^"]+)"', pins):
        rank, measure, scope, n, names = s.split(' ', 4)
        out['pins'].append((rank, measure, scope, float(n) if rank in LIMITS else int(n), [x.strip() for x in names.split(',')]))
    return out


@functools.lru_cache(maxsize=None)
def first_strike():
    """{class key: seconds a freshly raised minion waits before its first hit} of necro_config.lua minions.firstStrikeMs"""
    text = open(NECRO_CONFIG, encoding='utf-8').read()
    block = re.search(r'firstStrikeMs = \{([^}]*)\}', text).group(1)
    return {k: int(v) / 1000.0 for k, v in re.findall(r'(\w+) = (\d+)', block)}


@functools.lru_cache(maxsize=None)
def ctx():
    spells, model = R.load_all()
    return spells, model


# ------------------------------------------------------------------------------------------------ reach
@functools.lru_cache(maxsize=None)
def spell_attrs():
    """{words: (range or 0, script)} of spells_chaos.xml"""
    xml = re.sub(r'<!--.*?-->', '', open(R.CHAOS_XML, encoding='utf-8').read(), flags=re.S)
    return {a.get('words'): (int(a.get('range') or 0), a.get('script', '')) for a, _ in R.instants(xml)}


@functools.lru_cache(maxsize=None)
def kit_radius(name):
    """the attack kit's radius (or range) of a spell, 0 when it is not a kit spell"""
    text = open(KIT_CONFIG, encoding='utf-8').read()
    m = re.search(r'name = "' + re.escape(name) + r'",(.*?)(?=\n\t\t\w+ = \{|\n\t\},)', text, re.S)
    if not m:
        return 0
    r = re.search(r'\bradius = (\d+)', m.group(1)) or re.search(r'\brange = (\d+)', m.group(1))
    return int(r.group(1)) if r else 0


def script_radius(script):
    """the radius of the area a spell script builds (AREA_CIRCLE3X3 is radius 3, AREA_SQUARE1X1 radius 1), 0 when none"""
    path = os.path.join(R.SPELLS, script)
    if not script or not os.path.isfile(path):
        return 0
    m = re.search(r'AREA_(?:CIRCLE|SQUARE)(\d+)X', open(path, encoding='utf-8').read())
    return int(m.group(1)) if m else 0


def reach(name, words, conf):
    """the reach of a spell in squares, or None when nothing says (the report lists those)"""
    rng, script = spell_attrs().get(words, (0, ''))
    return rng or script_radius(script) or kit_radius(name) or conf['reach'].get(name) or None


# ------------------------------------------------------------------------------------------------ the rotation
def best(cls, level):
    spells, model = ctx()
    return R.analyse(spells, model, cls, level)['best']


def trace(cls, level):
    """the landing times and hits on one target of the class's best set from a cold start: [(time, hit)]"""
    b = best(cls, level)
    if not b:
        return []
    hits = []
    R.simulate(b['spells'], R.HORIZON, hits)
    return sorted((t, h) for t, h, _, _ in hits)


def minion_arrivals(kinds, rates, conf):
    """[(arrival second, damage rate)] of every minion of a build, raised from a cold start with no corpse around (`raisePerCast`
    minions of a kind a Raise Dead cast): the support group allows a cast every SUPPORT_GCD, each spell has its own cooldown, and
    the player picks the order of casts that costs the least damage (the sum of rate x arrival second, tried over every order)"""
    cd = {'warrior': 4.0, 'mage': 4.0, 'golem': 30.0, 'skeleton': 2.0, 'shade': 2.0}
    per = {'skeleton': conf['raisePerCast'], 'shade': 1}
    by = {}
    for k, r in zip(kinds, rates):
        by.setdefault(k, []).append(r)
    casts = []                                    # one entry per cast: (kind, the rates of the minions it raises)
    for k, rs in by.items():
        rs = sorted(rs, reverse=True)
        n = int(per.get(k, 1))
        casts += [(k, tuple(rs[i:i + n])) for i in range(0, len(rs), n)]

    def run(order):
        free, t, out = {}, 0.0, []
        for k, rs in order:
            t = max(t, free.get(k, 0.0))
            out += [(t, r) for r in rs]
            free[k] = t + cd[k]
            t += SUPPORT_GCD
        return out

    return min((run(o) for o in set(itertools.permutations(casts))), key=lambda o: sum(a * r for a, r in o))


def cum(times, x):
    """the damage of the hits landed by x seconds (times: sorted [(time, hit)], with a running total as third field)"""
    lo, hi = 0, len(times)
    while lo < hi:
        mid = (lo + hi) // 2
        if times[mid][0] <= x:
            lo = mid + 1
        else:
            hi = mid
    return times[lo - 1][2] if lo else 0.0


def ramp_of(cls, level, conf):
    """{'ramp': seconds to rampShare of the steady damage, 'out': seconds until every minion is out and hitting (0 with none),
    'share': the share of the steady damage the minions hold}. The steady damage of a span of t
    seconds is the mean damage of every span of t seconds that starts in the steady part of the horizon (STEADY_FROM on), so the
    cooldown cycle of the rotation does not read as a ramp: a class ramps up when the span from the pull is under the mean span"""
    hits = trace(cls, level)
    wand, minion = 0.0, []
    if cls in MINION_KEY:
        m = MM.model_class(MINION_KEY[cls], level, levels=DEFAULT_LEVELS)
        wand = m['wand']
        rates = [m['tree'] * m['rows'][k]['dps1'] * m['fight']['alive'] for k in m['kinds']]
        delay = conf['minionTravel'] + first_strike().get(MINION_KEY[cls], 0.0)
        minion = [(a + delay, r) for a, r in minion_arrivals(m['kinds'], rates, conf)]
    run, tot = [], 0.0
    for tt, h in hits:
        tot += h
        run.append((tt, h, tot))
    mrate = sum(r for _, r in minion)
    last_below, t = None, RAMP_FROM
    while t <= RAMP_TO:
        starts = [STEADY_FROM + 0.5 * k for k in range(int((R.HORIZON - STEADY_FROM - t) / 0.5) + 1)]
        steady = sum(cum(run, s + t) - cum(run, s) for s in starts) / len(starts) + (wand + mrate) * t
        dealt = cum(run, t) + wand * t + sum(r * max(0.0, t - a) for a, r in minion)
        if steady > 0 and dealt < conf['rampShare'] * steady:
            last_below = t
        t += GRID
    ramp = 0.0 if last_below is None else min(RAMP_TO, last_below + GRID)
    total = (sum(h for _, h in hits) / R.HORIZON + wand + mrate) or 1.0
    return {'ramp': ramp, 'out': max([a for a, _ in minion] or [0.0]), 'share': mrate / total,
            'strike': first_strike().get(MINION_KEY.get(cls), 0.0) + (conf['minionTravel'] if cls in MINION_KEY else 0.0)}


# ------------------------------------------------------------------------------------------------ the three measures
def mana_row(cls, level):
    """{'spent': mana a minute, 'regen': a minute (vocation + level flow), 'own': vocation regeneration a minute, 'pool',
    'drain': pools burnt a minute, 'runway_own': seconds (the number of rotation_sim.py --mana), 'runway': with the level
    flow on top}; inf runway when the regeneration pays for the rotation"""
    spells, model = ctx()
    r = R.mana_runway(spells, model, cls, level)
    if not r:
        return None
    run_own, pool, regen, spent, _ = r
    flow = R.flow_regen(level)
    net = spent - regen - flow
    return {'spent': spent * 60, 'regen': (regen + flow) * 60, 'own': regen * 60, 'pool': pool, 'drain': spent * 60 / pool,
            'runway_own': run_own, 'runway': pool / net if net > 0 else float('inf')}


def band(r):
    return 'near' if r <= 1 else ('mid' if r == 2 else 'far')


def exposure_row(cls, level, conf):
    """{'near': share at reach 1, 'mid': at 2, 'far': at 3+ (spells and weapon), 'spells': the same for the spells alone,
    'unknown': spell names without a reach}"""
    b = best(cls, level)
    if not b:
        return None
    hits = []
    R.simulate(b['spells'], R.HORIZON, hits)
    by = {s.words: s.name for s in b['spells']}
    tot = {'near': 0.0, 'mid': 0.0, 'far': 0.0}
    unknown = set()
    for _, h, _, w in hits:
        r = reach(by[w], w, conf)
        if r is None:
            unknown.add(by[w])
            r = 1
        tot[band(r)] += h
    s = sum(tot.values()) or 1.0
    spells = {k: v / s for k, v in tot.items()}
    kind = R.CLASS_KIND[cls]
    auto = conf['autoShare'][kind]
    weapon = 'near' if kind in ('melee', 'fist') else 'far'
    both = {k: (1 - auto) * v + (auto if k == weapon else 0.0) for k, v in spells.items()}
    return dict(both, spells=spells, unknown=sorted(unknown))


@functools.lru_cache(maxsize=None)
def vocation_health():
    """{class: (level 1 health, health per level)} of start_stats.lua"""
    text = open(R.START_STATS, encoding='utf-8').read()
    by_id = {int(v): (int(h), int(g)) for v, h, g in re.findall(r'\[(\d+)\] = \{health = (\d+), mana = \d+, .*?gainhp = (\d+)', text)}
    return {c: by_id[R.VOC[c]] for c in CLASSES}


def health_row(cls, level, conf):
    """{'taken': damage taken factor, 'per_level': effective health per level, 'ehp': effective health at the level}"""
    first, gain = vocation_health()[cls]
    taken = conf['toughness'].get(cls, 1.0)
    return {'taken': taken, 'per_level': gain / taken, 'ehp': (first + (level - 1) * gain) / taken}


@functools.lru_cache(maxsize=None)
def rows(levels, conf_text=None):
    conf = config(conf_text)
    out = {}
    for c in CLASSES:
        out[c] = []
        for L in levels:
            rp = ramp_of(c, L, conf)
            out[c].append({'mana': mana_row(c, L), 'ramp': rp['ramp'], 'out': rp['out'], 'strike': rp['strike'], 'minion_share': rp['share'],
                           'exp': exposure_row(c, L, conf), 'hp': health_row(c, L, conf)})
    return out


# ------------------------------------------------------------------------------------------------ facts and checks
MEASURES = {
    'health': lambda r: r['hp']['per_level'],
    'ramp': lambda r: r['ramp'],
    'strike': lambda r: r['strike'],
    'far': lambda r: r['exp']['far'],
    'farspells': lambda r: r['exp']['spells']['far'],
    'near': lambda r: r['exp']['near'],
    'runway': lambda r: r['mana']['runway_own'],
    'drain': lambda r: r['mana']['drain'],
}


def mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs)


def score(t, scope, name, i, measure):
    """the measure of a class, or of a line (the mean of its classes), at level index i"""
    f = MEASURES[measure]
    if scope == 'class':
        return f(t[name][i])
    return mean(f(t[c][i]) for c in CLASSES if LINE[c] == name)


def ranked(t, scope, i, measure, rank):
    """the names of the classes (or lines) from the `rank` end ('lowest' or 'highest') of a measure at level index i"""
    names = CLASSES if scope == 'class' else LINES
    return sorted(names, key=lambda n: (score(t, scope, n, i, measure) * (1 if rank == 'lowest' else -1), n))


def check_facts(t, levels, pins):
    """[failure text] of the pins against the tables. A pin is "rank measure scope N names": every name is among the N
    lowest (or highest) classes (or lines) of the measure at every level; or "atleast|atmost measure scope VALUE names": every
    name's measure is at least (at most) the value at every level"""
    bad = []
    for rank, measure, scope, n, names in pins:
        if rank in LIMITS:
            for i, L in enumerate(levels):
                for name in names:
                    v = score(t, scope, name, i, measure)
                    if (rank == 'atleast' and v < n) or (rank == 'atmost' and v > n):
                        bad.append('%d: %s %s %s is %.3f, %s %s' % (L, name, scope, measure, v, 'under' if rank == 'atleast' else 'over', n))
            continue
        for i, L in enumerate(levels):
            top = ranked(t, scope, i, measure, rank)[:n]
            for name in names:
                if name not in top:
                    bad.append('%d: %s is not among the %d %s %s in %s (it is number %d)' % (
                        L, name, n, rank, 'classes' if scope == 'class' else 'lines', measure,
                        ranked(t, scope, i, measure, rank).index(name) + 1))
    return bad


def intended(t, levels, conf):
    """[(statement, holds, detail)] the intended weaknesses (docs/CLASSES.md "Class weaknesses (measured)") against the numbers,
    judged on the lines (the mean of a line's three classes) at every level"""
    n = range(len(levels))
    lv = ','.join(map(str, levels))

    def per(measure, names, scope='line', fmt='%.0f'):
        return '; '.join('%s %s' % (x, '/'.join(fmt % score(t, scope, x, i, measure) for i in n)) for x in names)

    out = []
    low = [ranked(t, 'line', i, 'runway', 'lowest') for i in n]
    out.append(('Mystic line: the most mana pressure', all(r[0] == 'Mystic' and 'Warrior' not in r[:3] and 'Templar' not in r[:3]
                                                              for r in low),
                'line mean runway in seconds (vocation regeneration, as rotation_sim.py --mana) at %s, shortest first at %d: %s; Mystic line %s' % (
                    lv, levels[0], ', '.join('%s %.0f' % (x, score(t, 'line', x, 0, 'runway')) for x in low[0][:3]),
                    '/'.join('%.0f' % score(t, 'line', 'Mystic', i, 'runway') for i in n))))
    hp = all(ranked(t, 'line', i, 'health', 'lowest')[0] == 'Mystic' and
             ranked(t, 'class', i, 'health', 'lowest')[:3] == sorted(['Mystic', 'Elementalist', 'Illusionist'], key=lambda c: (score(t, 'class', c, i, 'health'), c))
             for i in n)
    out.append(('Mystic line: the least effective health', hp,
                'health per level: Mystic %.1f, Elementalist %.1f, Illusionist %.1f; the next classes Lich %.1f, Necromancer %.1f; line means %s' % (
                    score(t, 'class', 'Mystic', 0, 'health'), score(t, 'class', 'Elementalist', 0, 'health'),
                    score(t, 'class', 'Illusionist', 0, 'health'), score(t, 'class', 'Lich', 0, 'health'),
                    score(t, 'class', 'Necromancer', 0, 'health'),
                    ', '.join('%s %.1f' % (x, score(t, 'line', x, 0, 'health')) for x in ranked(t, 'line', 0, 'health', 'lowest')[:3]))))
    ok = all('Ranger' in ranked(t, 'line', i, 'health', 'lowest')[:3] and 'Ranger' in ranked(t, 'line', i, 'far', 'highest')[:3] for i in n)
    out.append(('Ranger line: low effective health but ranged', ok,
                'health per level %.1f (lines, lowest first: %s); far share %s%% (lines, most ranged first: %s)' % (
                    score(t, 'line', 'Ranger', 0, 'health'), ', '.join(ranked(t, 'line', 0, 'health', 'lowest')[:4]),
                    '/'.join('%.0f' % (100 * score(t, 'line', 'Ranger', i, 'far')) for i in n),
                    ', '.join(ranked(t, 'line', 0, 'far', 'highest')[:4]))))
    ok = all(score(t, 'line', x, i, 'farspells') <= 0.45 and score(t, 'line', x, i, 'far') < 0.5 and all(score(t, 'line', x, i, 'far') < score(t, 'line', y, i, 'far')
                                                          for y in ('Ranger', 'Mystic', 'Necromancer'))
             for x in ('Warrior', 'Templar') for i in n)
    out.append(('Warrior and Templar lines: melee with little range', ok,
                'far share (3+, weapon included) %s%%; spells alone %s%%' % (
                    '; '.join('%s %s' % (x, '/'.join('%.0f' % (100 * score(t, 'line', x, i, 'far')) for i in n)) for x in ('Warrior', 'Templar')),
                    '; '.join('%s %s' % (x, '/'.join('%.0f' % (100 * mean(t[c][i]['exp']['spells']['far'] for c in CLASSES if LINE[c] == x))
                                                      for i in n)) for x in ('Warrior', 'Templar')))))
    slow = [ranked(t, 'line', i, 'ramp', 'highest') for i in n]
    ok = all(set(s[:2]) == {'Monk', 'Necromancer'} for s in slow) and all(
        t['Necromancer'][i]['ramp'] >= 3.0 and t['Lich'][i]['strike'] >= 4.0 for i in n)

    def cls_ramp(c):
        return '%s %s' % (c, '/'.join('%.1f' % t[c][i]['ramp'] for i in n))

    out.append(('Monk and Necromancer lines: the slowest ramp-up', ok,
                'line mean ramp in seconds, slowest first at %d: %s; by class (seconds at %s): %s; the Necromancer line\'s minions are '
                'out at %.1f s (Necromancer), %.1f s (Lich), %.1f s (Bone Lord) at %d' % (
                    levels[0], ', '.join('%s %.1f' % (x, score(t, 'line', x, 0, 'ramp')) for x in slow[0][:3]), lv,
                    ', '.join(cls_ramp(c) for c in ('Monk', 'Shadowfist', 'Iron Sage', 'Necromancer', 'Lich', 'Bone Lord')),
                    t['Necromancer'][0]['out'], t['Lich'][0]['out'], t['Bone Lord'][0]['out'], levels[0])))
    return out


def mana_factor(t, levels):
    """the factor on the mana the Mystic line spends (its costs) that makes the line's mean runway 10% under the shortest other
    line's, per level: found by bisection on the runway formula pool / (spent - regeneration)"""
    out = []
    for i, L in enumerate(levels):
        goal = 0.9 * min(score(t, 'line', x, i, 'runway') for x in LINES if x != 'Mystic')
        cls = [c for c in CLASSES if LINE[c] == 'Mystic']

        def mean_run(f):
            return mean(t[c][i]['mana']['pool'] / max(1e-9, (t[c][i]['mana']['spent'] * f - t[c][i]['mana']['own']) / 60) for c in cls)

        lo, hi = 1.0, 20.0
        for _ in range(40):
            mid = (lo + hi) / 2
            if mean_run(mid) > goal:
                lo = mid
            else:
                hi = mid
        out.append(hi if mean_run(1.0) > goal else 1.0)
    return out


def levers(t, levels):
    """the suggested lever of each intended weakness that does not hold (never applied by this tool)"""
    f = mana_factor(t, levels)
    return {
        'Mystic line: the most mana pressure':
            'the Mystic line best sets would have to spend %.1f-%.1f times the mana a minute to be the shortest runway of the lines: raise the '
            'fixed cost of the Mystic area spells (spells_chaos.xml, rotation_model.csv; Falling Pyre, Doomtide, Glacial Doom) or '
            'cut the Mystic line mana gain (start_stats.lua gainmana 30); rotation_sim.py --mana keeps its 15 s floor' % (min(f), max(f)),
        'Mystic line: the least effective health':
            'the Illusionist (gainhp 7) and the Mystic line differ little from the Lich (7): lower the Illusionist to 5-6 in '
            'start_stats.lua and chaos_vocations.xml if the line must be lowest class by class',
        'Ranger line: low effective health but ranged':
            'health per level 10-11 against the Thief and Monk lines 12: lower the Ranger line gainhp by 1-2 (start_stats.lua, '
            'chaos_vocations.xml); a damage taken factor in the toughness model would not change the table',
        'Warrior and Templar lines: melee with little range':
            'the spells of both lines reach 3 or more (Rift Cleaver 4, Bastion Cry 3, Crusader\'s Sweep 3, Sanctum Verdict 3, Lance of '
            'Vigil 5, the 3x3 and wider areas around the caster): cut the range of those kit spells to 1-2 in spells_chaos.xml and '
            'attack_kit_config.lua together (the helper rotation data follows with rotation_sim.py --write)',
        'Monk and Necromancer lines: the slowest ramp-up':
            'the Necromancer\'s own ramp is covered by its spell opening; a longer Raise cooldown or a first hit delay on the minions '
            'would show it (necro_config.lua), and the Monk\'s chi build is 4 s: a finisher at 5 chi would lengthen it',
    }


def check(conf_text=None):
    conf = config(conf_text)
    levels = tuple(conf['levels'])
    t = rows(levels, conf_text)
    bad = check_facts(t, levels, conf['pins'])
    for c in CLASSES:
        for i, L in enumerate(levels):
            if t[c][i]['exp']['unknown']:
                print('WARN %s at %d: no reach for %s (add it to `reach` of weakness_config.lua)' % (
                    c, L, ', '.join(t[c][i]['exp']['unknown'])))
    for b in bad:
        print('FAIL ' + b)
    print('weakness check: %s (%d classes, levels %s, %d pins)' % (
        'FAIL' if bad else 'ok', len(CLASSES), ','.join(str(L) for L in levels), len(conf['pins'])))
    return 1 if bad else 0


# ------------------------------------------------------------------------------------------------ report
def fmt_run(x):
    return 'inf' if x == float('inf') else '%d' % round(x)


def report(levels):
    t = rows(tuple(levels))
    print('| Class | Level | Mana a min | Regen a min | Pools a min | Runway own / flow (s) | Ramp (s) | Minions out (s) | Near / mid / far | Health per level | Health at level |')
    print('|---|---|---|---|---|---|---|---|---|---|---|')
    for c in CLASSES:
        for i, L in enumerate(levels):
            r = t[c][i]
            m, e, h = r['mana'], r['exp'], r['hp']
            print('| %s | %d | %d | %d | %.2f | %s / %s | %.1f | %s | %.0f%% / %.0f%% / %.0f%% | %.1f | %d |' % (
                c, L, m['spent'], m['regen'], m['drain'], fmt_run(m['runway_own']), fmt_run(m['runway']), r['ramp'],
                '%.1f' % r['out'] if c in MINION_KEY else '-', 100 * e['near'], 100 * e['mid'], 100 * e['far'],
                h['per_level'], h['ehp']))
    print()
    print('| Line | ' + ' | '.join('%d runway s / ramp s / far / health per level' % L for L in levels) + ' |')
    print('|---|' + '---|' * len(levels))
    for l in LINES:
        print('| %s | %s |' % (l, ' | '.join('%s / %.1f / %.0f%% / %.1f' % (
            fmt_run(score(t, 'line', l, i, 'runway')), score(t, 'line', l, i, 'ramp'), 100 * score(t, 'line', l, i, 'far'),
            score(t, 'line', l, i, 'health')) for i in range(len(levels)))))
    return t


def main(argv):
    if '--check' in argv:
        return check()
    levels = DEFAULT_LEVELS
    if '--levels' in argv:
        levels = tuple(int(x) for x in argv[argv.index('--levels') + 1].split(','))
    t = report(levels)
    if '--findings' in argv:
        print()
        lv = levers(t, levels)
        for what, holds, detail in intended(t, levels, config()):
            print('%s: %s. %s' % ('HOLDS' if holds else 'FINDING', what, detail))
            if not holds:
                print('  lever: ' + lv[what])
        print('NOT CHECKED: Thief line (burst classes): low sustained mana efficiency is fine, no pin')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
