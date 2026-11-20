#!/usr/bin/env python3
"""The Ember Descent model (O664): seconds to clear each room against seconds to die, per class and level band, solo and in a
O686 phase 3: `--upgrades` puts the spell upgrades on (spell_upgrade_model.py): every room monster and the boss x H at the party's level (descent.lua spawnOne), class damage x the typical gain, the heal spells x the heal gain. `--check --upgrades` must pass as `--check` does.
full party (computed, not measured; server/README.md "Ember Descent model (O664)").

usage: python3 -I server/tools/descent_model.py [--levels 100,500] [--party 1,4] [--legacy] [--detail] [--boons] [--curses] [--hunt]
                                                [--check]

O663 measured room 1 live: two waves of four monsters at 0.60-0.85 of the party level; a level 592 Warrior took 2,611 damage a
second (29% of its health a second, Mystic Baguemage hits of 1,300-2,000), healed 1,053 a second, and 7 of 10 bots fled at 20%.
The model answers "how does a room of the Descent compare with a hunt pack of the same level, and how do the rooms grow".

Without a flag: per level band, the hunt pack of the level (the yardstick) and for each party size and room (combat, elite, boss
by depth) the median class: seconds to clear, seconds to die, seconds to die with no healing at the start of a wave (burst), health
left after the room, next to the worst class and the hardest tenth of the monster picks. --legacy prints the state before O664
(descent_config.lua `pace.enabled = false`, `boss.damage = 1`: the monsters at the full health and damage of their pool entry) first. --detail adds
every class. --boons prints the boon model, --curses the room with the Swarm and Frailty curses taken, --hunt the hunt pack.
--check (CI): the limits of descent_balance_config.lua.

Inputs (everything in the repo; tools/descent_numbers.lua dumps the Lua side as JSON, luajit or $LUAJIT):
  descent_config.lua / descent_core.lua   rooms, waves, sizes, tiers, escalation of the level window, boss, boons, curses, the pace
                                          factors of a monster (the real functions: escalation, roomPlan, paceScale, pickTypes)
  bounty_pool.lua                         the monsters of a room (the pool entries inside the level window, as pickTypes draws)
  data/monster/monsters/chaos/**          the XML attacks of the level-scaled monsters (survival_model.py)
  data/spells/guardian_hits.csv           the biggest hits of the stock monsters (no XML in the repo): one hit of its mean attacks
                                          at `hitRate` a second, fitted on the level-scaled monsters that have both
  class_dps_model.py                      class damage on 1 and 5 targets (the one source of the balance models)
  survival_model.py                       health, armour, absorbs, dodge, toughness, healing of the class at the level
  pack_model.py                           the hunt pack size by level
  monster_tiers.lua                       health and damage of the ranks

The model, per class, level, party size n, depth d and room kind:
  monster    health = pool health x (1 + engineHealth x level for a level-scaled one) x pace health x depth health x rank x kind;
             damage per second = its XML attacks (level-scaled) or hitRate x (melee mean + spell mean) (stock), before the player's
             layers, x pace damage x depth damage x rank, the late-game physical boost on its melee and physical hits
  room       waves x size monsters (descent_core.lua roomPlan, the real plan; elite: one wave of rare and legendary, health x1.5;
             boss: one legendary of the window, health x (healthMult + perExtraPlayer x (n - 1)))
  clear      a wave of P monsters takes P x health / (n x boons x (d1 + (min(P, 5) - 1) x (d5 - d1) / 4)) seconds (the class's damage on
             1 and 5 targets; no pack cleave: pace.lua never marks the Descent); waveGap seconds of walking in before each wave
  damage     the wave's peak is P x the monster's damage, shared by n players; on average a wave deals (P + 1) / (2 P) of it (the monsters
             die one after the other); survival_model.survive() takes it through armour, block, absorb, dodge and toughness
  healing    survival_model's potions and self heal (the potion of the level), plus the Blood Drinker share of the damage dealt
  after      health lost over the room: each wave adds (damage - healing) x its seconds, each gap heals waveGap x healing
  boons      the picks of a run (descent_balance_config.lua boons.picksPerRoom, taken by Monte Carlo from the real boon table with the
             best of three offers): damage, damage taken, leech
Not in it: the monsters' armour and resistances, the party's heals, kiting and cover, the merchant's and the shrine's help, the Ward and
Thornmail and Pyre Burst boons, the curses unless asked, the Descent's own time limit.
"""
import csv, itertools, json, math, os, random, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import survival_model as S
import class_dps_model as CD
import spell_upgrade_model as SU  # the spell upgrades switch (O686 phase 3): monster health x H, class damage x the gain
import pack_model as PM

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')
HITS = os.path.join(SERVER, 'data', 'spells', 'guardian_hits.csv')
TIERS = os.path.join(CHAOS, 'monster_tiers.lua')


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


_numbers = {}


def numbers(levels, legacy=False):
    """the Lua side (tools/descent_numbers.lua) for these party levels"""
    key = (tuple(sorted(set(int(x) for x in levels))), bool(legacy))
    if key not in _numbers:
        args = [lua_bin(), 'tools/descent_numbers.lua'] + (['legacy'] if legacy else []) + [str(x) for x in key[0]]
        out = subprocess.run(args, cwd=SERVER, check=True, capture_output=True, text=True).stdout
        _numbers[key] = json.loads(out)
    return _numbers[key]


# ------------------------------------------------------------------------------------------------ small helpers
def read_hits(path=HITS):
    out = {}
    with open(path, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            out[r['name'].lower()] = {'melee': float(r['melee_mean']), 'elem': float(r['elem_mean']),
                                      'melee_max': float(r['melee_max']), 'elem_max': float(r['elem_max'])}
    return out


def rank_factors(path=TIERS):
    """{rank: (health, damage)} of monster_tiers.lua ChaosTiers"""
    text = S.read(path)
    out = {}
    for k in ('magic', 'rare', 'legendary'):
        m = re.search(r'\b%s = \{label = "[A-Za-z]+", hp = ([0-9.]+), speed = \d+, damage = ([0-9.]+)' % k, text)
        out[k] = (float(m.group(1)), float(m.group(2)))
    return out


def tier_mean(tiers_pct, ranks):
    """(health, damage) mean factor of a monster whose rank is rolled with the percents of descent_core.lua rollTier"""
    h = d = 1.0
    for k in ('magic', 'rare', 'legendary'):
        p = tiers_pct.get(k, 0) / 100.0
        h += p * (ranks[k][0] - 1)
        d += p * (ranks[k][1] - 1)
    return h, d


def elite_mean(cfg, depth, ranks):
    """an elite monster is rare, or legendary with min(100, legendaryBase + legendaryPerDepth x depth) percent"""
    el = cfg['elite']
    pl = min(100.0, el['legendaryBase'] + el['legendaryPerDepth'] * depth) / 100.0
    return ((1 - pl) * ranks['rare'][0] + pl * ranks['legendary'][0], (1 - pl) * ranks['rare'][1] + pl * ranks['legendary'][1])


def class_name(key):
    return S.name(key)


# ------------------------------------------------------------------------------------------------ monsters
class Monsters:
    """the pool entries as the model's monsters: base health and damage per second before any factor"""

    def __init__(self, num, bal, d):
        self.bal = bal
        self.xml = S.scaled_monsters()
        self.hits = read_hits()
        self.rows = num['pool']
        sbal = dict(d['balance'], tierMean=1.0)
        d2 = dict(d)
        d2['pace'] = {'enabled': False, 'damage': []}
        self.mons = []
        for r in self.rows:
            self.mons.append(self.one(r, d2, sbal))

    def one(self, r, d, sbal):
        name = r['name'].lower()
        xml = self.xml.get(name)
        hp = r['health']
        if xml and xml[1]:
            mlv, attacks = xml
            one = S.monster_dps(d, sbal, mlv, attacks)
            hits = sum(1000.0 / a['interval'] for a in attacks if a['kind'] == 'melee')
            hp *= 1 + self.bal['engineHealth'] * mlv
            src = 'xml'
        else:
            h = self.hits.get(name)
            rate = self.bal['hitRate']
            boost = 1 + S.boost_percent(d['boost']['points'], r['level']) / 100.0 if d['boost'].get('enabled', True) else 1.0
            if h:
                one = {'melee': h['melee'] * rate * boost, 'physical': 0.0, 'element': h['elem'] * rate}
                hits = rate if h['melee'] > 0 else 0.0
            else:
                one = {'melee': 0.0, 'physical': 0.0, 'element': 0.0}
                hits = 0.0
            if r['scaled']:
                hp *= 1 + self.bal['engineHealth'] * r['level']
            src = 'csv' if h else 'none'
        return {'name': r['name'], 'level': r['level'], 'health': hp, 'melee': one['melee'], 'physical': one['physical'],
                'element': one['element'], 'hits': hits, 'ph': r['ph'], 'pd': r['pd'], 'hh': r['hh'], 'hd': r['hd'], 'src': src,
                'spawns': r['spawns'], 'poolHealth': r['health']}


def candidates(mons, cfg, window):
    """the monster types a room can draw (descent_core.lua pickTypes): the pool inside the window, widened by escalation.widen up to
    five times while fewer than `types` are in it, then the nearest levels of the whole pool"""
    e = cfg['escalation']
    want = cfg['types']

    def inside(w):
        return [m for m in mons if w[0] <= m['level'] <= w[1] and m['poolHealth'] >= e['minPoolHealth'] and m['src'] != 'none']

    w = list(window)
    lst = inside(w)
    widen = 0
    while len(lst) < want and widen < 5:
        widen += 1
        w = [w[0] - e['widen'], w[1] + e['widen']]
        lst = inside(w)
    if len(lst) < want:
        rest = [m for m in mons if m['poolHealth'] >= e['minPoolHealth'] and m['src'] != 'none' and m not in lst]
        rest.sort(key=lambda m: (m['level'] < window[0] and window[0] - m['level'] or (m['level'] > window[1] and m['level'] - window[1] or 0), m['name']))
        lst = lst + rest[:want - len(lst)]
    return lst


def mean_monster(lst, key='ph'):
    n = float(len(lst))
    out = {}
    for k in ('health', 'melee', 'physical', 'element', 'hits'):
        out[k] = sum(m[k] for m in lst) / n
    # health and damage factors of the pace curves belong to each monster: fold them in per monster
    out['pace_health'] = sum(m['health'] * m['ph'] for m in lst) / n
    out['pace_damage'] = {k: sum(m[k] * m['pd'] for m in lst) / n for k in ('melee', 'physical', 'element')}
    out['pace_hits'] = sum(m['hits'] for m in lst) / n
    out['level'] = sum(m['level'] for m in lst) / n
    out['name'] = 'mean of %d' % len(lst)
    return out


def single(m):
    out = {k: m[k] for k in ('health', 'melee', 'physical', 'element', 'hits', 'level', 'name')}
    out['pace_health'] = m['health'] * m['ph']
    out['pace_damage'] = {k: m[k] * m['pd'] for k in ('melee', 'physical', 'element')}
    out['pace_hits'] = m['hits']
    return out


# ------------------------------------------------------------------------------------------------ boons
def boon_values(cfg, bal):
    """{key: (damage, taken, leech, weight, max, kind)}: the share of one stack the model counts"""
    out = {}
    for b in cfg['boons']:
        v = b['value'] / 100.0
        x = (b.get('extra') or 0) / 100.0
        off = tk = lk = 0.0
        if b['kind'] == 'damage':
            off = v
        elif b['kind'] == 'convert':
            off = v * x * bal['boons']['physicalShare']
        elif b['kind'] in ('echo', 'crit', 'execute'):
            off = v * x
        elif b['kind'] == 'reduce':
            tk = v
        elif b['kind'] == 'leech':
            lk = v
        out[b['key']] = (off, tk, lk, b['weight'], b['max'], b['kind'])
    return out


_boon_cache = {}


def boon_curve(cfg, bal):
    """[(damage factor, damage taken factor, leech share) after k picks], k = 0..12, the mean of `runs` seeded runs that take the best
    of three offers (by the damage, the reduction and the leech it adds), never a boon at its maximum, one brand at a time"""
    key = json.dumps([cfg['boons'], bal['boons']], sort_keys=True)
    if key in _boon_cache:
        return _boon_cache[key]
    vals = boon_values(cfg, bal)
    rng = random.Random(bal['boons']['seed'])
    runs = bal['boons']['runs']
    kmax = 12
    acc = [[0.0, 0.0, 0.0] for _ in range(kmax + 1)]
    for _ in range(runs):
        stacks = {}
        off, tk, lk = 1.0, 1.0, 0.0
        for k in range(1, kmax + 1):
            brand = any(vals[b][5] == 'convert' and stacks.get(b) for b in vals)
            pool = [b for b in vals if stacks.get(b, 0) < vals[b][4] and not (brand and vals[b][5] == 'convert')]
            offer = []
            for _i in range(3):
                if not pool:
                    break
                w = [vals[b][3] for b in pool]
                pick = rng.choices(pool, w)[0]
                offer.append(pick)
                pool.remove(pick)
            if offer:
                best = max(offer, key=lambda b: vals[b][0] + vals[b][1] + vals[b][2])
                stacks[best] = stacks.get(best, 0) + 1
                off *= 1 + vals[best][0]
                tk *= 1 - vals[best][1]
                lk += vals[best][2]
            acc[k][0] += off
            acc[k][1] += tk
            acc[k][2] += lk
        acc[0][0] += 1
        acc[0][1] += 1
    out = [(a[0] / runs, a[1] / runs, a[2] / runs) for a in acc]
    _boon_cache[key] = out
    return out


def picks_before(bal, depth):
    return min(12, int(bal['boons']['picksPerRoom'] * (depth - 1) + 1e-9))


# ------------------------------------------------------------------------------------------------ the player
class Players:
    def __init__(self, levels, num_levels):
        self.levels = levels
        self.d = S.dump(levels)
        self.sbal0 = dict(S.dump([1000])['balance'])
        self.gear, self.varm = S.gear_curves(), S.vocation_armour()
        self.builds = {}

    def sbal(self, level):
        """survival_model's balance at the level: the potion tier the level may drink, the self heal below 300 scaled by level"""
        b = dict(self.sbal0)
        tiers = [p['tier'] for p in self.d['potions']['everfull'] if p['line'] == 'health' and p['level'] <= level]
        b['potionTier'] = max(tiers) if tiers else 1
        if level < 300:
            b['selfHeal'] = {k: [v[0] * level / 300.0, v[1]] for k, v in b['selfHeal'].items()}
        return b

    def pack_of(self, mon_pack):
        return mon_pack

    def build_for(self, cls, level, pack):
        key = (cls, level)
        if key not in self.builds:
            bal = self.sbal(level)
            cands = [S.survive(self.d, bal, cls, level, b, pack, self.gear, self.varm) for b in self.d['builds'][cls][str(level)]]
            order = sorted(range(len(cands)), key=lambda i: cands[i]['burst'])
            self.builds[key] = self.d['builds'][cls][str(level)][order[len(order) // 2]]
        return self.builds[key]

    def survive(self, cls, level, pack, build_pack, reduction=0.0):
        bal = self.sbal(level)
        b = self.build_for(cls, level, build_pack)
        o = {'reduction': {cls: reduction}} if reduction else None
        return S.survive(self.d, bal, cls, level, b, pack, self.gear, self.varm, o)


# ------------------------------------------------------------------------------------------------ the hunt pack (the yardstick)
def hunt_pack(P, level, pool_mons, bal):
    """the pack of the hunt a player of this level is in (survival_model.py: hunting level = level - gap, the pool's monsters within
    band of it, by spawns; every pace damage factor on): {melee, physical, element, meleeHits} of a pack of pack_model's size"""
    hl = level - bal['gap']
    mons = [m for m in pool_mons if abs(m['level'] - hl) <= bal['band'] and m['src'] != 'none']
    size = next(p for lo, hi, p, w in PM.PACK if lo <= level < hi)
    total = float(sum(m['spawns'] for m in mons)) or 1.0
    out = {'melee': 0.0, 'physical': 0.0, 'element': 0.0, 'meleeHits': 0.0}
    for m in mons:
        wgt = m['spawns'] / total * size * 1.025
        for k in ('melee', 'physical', 'element'):
            out[k] += m[k] * m['hd'] * wgt
        out['meleeHits'] += m['hits'] * wgt / 1.025
    return out, size, len(mons)


# ------------------------------------------------------------------------------------------------ a room
def room(ctx, cls, level, n, depth, kind, mon, curses=None, reduction_extra=0.0):
    """one class in one room of one depth. mon: a monster dict of single() / mean_monster(). Returns the metrics"""
    num, cfg, bal, P = ctx['num'], ctx['cfg'], ctx['bal'], ctx['players']
    L = num['levels'][str(level)][str(depth)]
    esc = L['esc']
    curses = curses or {}
    swarm = 'swarm' if curses.get('swarm') else 'plain'
    plan = L['plan'][kind][str(n)][swarm]
    ranks = ctx['ranks']
    hm = 1.0
    if kind == 'elite':
        th, td = elite_mean(cfg, depth, ranks)
        hm = cfg['elite']['healthMult']
    elif kind == 'boss':
        th, td = ranks['legendary']
        hm = cfg['boss']['healthMult'] + cfg['boss']['perExtraPlayer'] * (n - 1)
        td *= cfg['boss'].get('damage', 1.0)
    else:
        th, td = tier_mean(esc['tiers'], ranks)
    h = mon['pace_health'] * esc['health'] * th * hm * SU.health(level)  # O686 phase 3: x H at the party's level (descent.lua spawnOne), 1 while off
    dmg = {k: mon['pace_damage'][k] * esc['damage'] * td for k in ('melee', 'physical', 'element')}
    hits = mon['pace_hits']
    waves, size = plan['waves'], plan['size']
    cls_name = class_name(cls)
    d1, d5 = CD.dps(cls_name, level)
    k = picks_before(bal, depth)
    off, taken, leech = ctx['boons'][k] if ctx.get('useBoons', True) else (1.0, 1.0, 0.0)
    s = (d5 - d1) / 4.0
    m = min(size, 5)
    one_wave = size * h / (n * off * (d1 + (m - 1) * s))
    gap = bal['waveGap']
    alive = (size + 1) / (2.0 * size)
    # the player: the wave's average and peak damage through the layers
    peak = {kk: dmg[kk] * size / n for kk in ('melee', 'physical', 'element')}
    peak['meleeHits'] = hits * size / n
    avgp = {kk: v * alive for kk, v in peak.items()}
    red = reduction_extra + (1 - taken)
    # damage taken factor of the boons (and Frailty) is applied as a toughness reduction: tough x (1 - red)
    frail = 1.2 if curses.get('frailty') else 1.0
    r_avg = P.survive(cls, level, avgp, ctx['build_pack'][level], red)
    r_peak = P.survive(cls, level, peak, ctx['build_pack'][level], red)
    dmg_avg = r_avg['damage'] * frail
    dmg_peak = r_peak['damage'] * frail
    heal = r_avg['heal'] * bal['healUse'] * (0.7 if curses.get('withering') else 1.0) + leech * off * (d1 + (m - 1) * s)
    pool = r_avg['pool']
    loss = worst = 0.0
    for _w in range(waves):
        loss = max(0.0, loss - heal * gap)
        loss = max(0.0, loss + (dmg_avg - heal) * one_wave)
        worst = max(worst, loss)
    clear = waves * (one_wave + gap)
    return {'class': cls, 'clear': clear, 'wave': one_wave, 'waves': waves, 'size': size, 'dmg': dmg_avg, 'peak': dmg_peak, 'heal': heal,
            'pool': pool, 'burst': pool / dmg_peak if dmg_peak > 0 else float('inf'),
            'die': pool / (dmg_avg - heal) if dmg_avg > heal else float('inf'),
            'left': max(0.0, 1.0 - worst / pool), 'lostShare': worst / pool, 'health': h, 'hits': dmg_peak,
            'pressure': dmg_avg / heal if heal > 0 else float('inf')}


def room_table(ctx, level, n, depth, kind, mon):
    return {cls: room(ctx, cls, level, n, depth, kind, mon) for cls in S.ORDER}


def median_row(rows, key='pressure'):
    """the class at the middle of the 21 by the key (damage against healing)"""
    ordered = sorted(rows.values(), key=lambda r: r[key])
    return ordered[len(ordered) // 2]


def room_mon(ctx, level, depth, kind, pick=None):
    """the monster of a room: the mean of the window's candidates (a boss: the upper half of the window by level, `bossFrom`)"""
    num, cfg = ctx['num'], ctx['cfg']
    esc = num['levels'][str(level)][str(depth)]['esc']
    lst = candidates(ctx['mons'].mons, cfg, esc['window'])
    if kind == 'boss':
        ordered = sorted(lst, key=lambda m: (m['level'], m['name']))
        return mean_monster(ordered[int(ctx['bal']['bossFrom'] * len(ordered)):] or ordered[-1:])
    return mean_monster(lst)


def spread_rows(ctx, level, n, depth, kind, cls):
    """one class against every candidate type alone: [lostShare ...] sorted, for the hardest tenth"""
    esc = ctx['num']['levels'][str(level)][str(depth)]['esc']
    lst = candidates(ctx['mons'].mons, ctx['cfg'], esc['window'])
    vals = sorted(((room(ctx, cls, level, n, depth, kind, single(m)), m) for m in lst), key=lambda t: t[0]['lostShare'])
    return vals


# ------------------------------------------------------------------------------------------------ the whole table
def context(levels, legacy=False):
    num = numbers(levels, legacy)
    cfg = num['cfg']
    bal = BAL()
    d = S.dump(levels)
    ctx = {'num': num, 'cfg': cfg, 'bal': bal, 'players': Players(levels, num['levels']), 'ranks': rank_factors(),
           'mons': Monsters(num, bal, d), 'boons': boon_curve(cfg, bal), 'd': d}
    # the build of each class at a level is picked against the hunt pack of the level (independent of the Descent's numbers)
    ctx['build_pack'] = {}
    ctx['hunt'] = {}
    for lv in levels:
        pack, size, nmon = hunt_pack(ctx['players'], lv, ctx['mons'].mons, bal)
        ctx['build_pack'][lv] = pack
        ctx['hunt'][lv] = {'pack': pack, 'size': size, 'monsters': nmon}
    return ctx


_bal = []


def BAL():
    """descent_balance_config.lua (the dump of tools/descent_numbers.lua prints it)"""
    if not _bal:
        _bal.append(numbers([])['balance'])
    return _bal[0]


def hunt_rows(ctx, level):
    """the median class in the hunt pack of the level: its burst, its damage, the healing against it"""
    P = ctx['players']
    pack = ctx['hunt'][level]['pack']
    rows = {}
    for cls in S.ORDER:
        r = P.survive(cls, level, pack, ctx['build_pack'][level])
        rows[cls] = r
    return rows


def compute(levels, parties, legacy=False):
    ctx = context(levels, legacy)
    bal = ctx['bal']
    res = {'ctx': ctx, 'levels': {}}
    for lv in levels:
        hr = hunt_rows(ctx, lv)
        med = statistics.median(r['burst'] for r in hr.values())
        entry = {'hunt': {'rows': hr, 'burstMedian': med, 'size': ctx['hunt'][lv]['size'], 'monsters': ctx['hunt'][lv]['monsters'],
                          'damageMedian': statistics.median(r['damage'] for r in hr.values()),
                          'healMedian': statistics.median(r['heal'] for r in hr.values())},
                 'rooms': {}}
        for n in parties:
            for depth in bal['depths']:
                kinds = ['combat'] + (['elite'] if depth >= ctx['cfg']['eliteFrom'] else []) + (['boss'] if depth in bal['bossDepths'] else [])
                for kind in kinds:
                    mon = room_mon(ctx, lv, depth, kind)
                    rows = room_table(ctx, lv, n, depth, kind, mon)
                    mid = median_row(rows)
                    worst = max(rows.values(), key=lambda r: (r['lostShare'], r['pressure']))
                    entry['rooms'][(n, depth, kind)] = {'rows': rows, 'median': mid, 'worst': worst, 'mon': mon}
        res['levels'][lv] = entry
    return res


def hard_pick(res, lv, n, depth, kind, q):
    """the median class (of the room) against the candidates alone: the row at quantile q of the monsters by health lost"""
    ctx = res['ctx']
    cell = res['levels'][lv]['rooms'][(n, depth, kind)]
    vals = spread_rows(ctx, lv, n, depth, kind, cell['median']['class'])
    return vals[min(len(vals) - 1, int(q * len(vals)))]


# ------------------------------------------------------------------------------------------------ the check
def check(res):
    ctx = res['ctx']
    bal = ctx['bal']
    lim = bal['limits']
    errors = []
    for lv, e in sorted(res['levels'].items()):
        hmed = e['hunt']['burstMedian']
        parties = sorted({k[0] for k in e['rooms']})
        for n in parties:
            tag = 'level %d, party %d' % (lv, n)
            r1 = e['rooms'][(n, 1, 'combat')]
            m, w = r1['median'], r1['worst']
            l1 = lim['room1']
            if m['left'] < l1['medianLeft']:
                errors.append('%s room 1: the median class keeps %.0f%% of its health, under %.0f%%' % (tag, 100 * m['left'], 100 * l1['medianLeft']))
            if w['left'] < l1['worstLeft']:
                errors.append('%s room 1: %s keeps %.0f%% of its health, under %.0f%%' % (tag, S.name(w['class']), 100 * w['left'], 100 * l1['worstLeft']))
            if not l1['clear'][0] <= m['clear'] <= l1['clear'][1]:
                errors.append('%s room 1: the median class clears in %.0f s, outside %s' % (tag, m['clear'], l1['clear']))
            if not l1['pressure'][0] <= m['pressure'] <= l1['pressure'][1]:
                errors.append('%s room 1: the median class takes %.2f x its healing, outside %s' % (tag, m['pressure'], l1['pressure']))
            if m['burst'] < l1['burstVsHunt'] * hmed:
                errors.append('%s room 1: the median class lives %.1f s with no healing, %.2f x the hunt pack of its level (%.1f s), under %.2f' % (
                    tag, m['burst'], m['burst'] / hmed, hmed, l1['burstVsHunt']))
            hp = hard_pick(res, lv, n, 1, 'combat', l1['hardQuantile'])
            if hp[0]['left'] < l1['hardLeft']:
                errors.append('%s room 1: against %s alone the median class keeps %.0f%%, under %.0f%%' % (
                    tag, hp[1]['name'], 100 * hp[0]['left'], 100 * l1['hardLeft']))
        # the climb is the solo player's (a party shares the damage and the damage is not split by the model's median class)
        n = parties[0]
        tag = 'level %d, party %d' % (lv, n)
        g = lim['growth']
        first = e['rooms'][(n, 1, 'combat')]['median']
        prev = None
        for depth in bal['depths']:
            c = e['rooms'].get((n, depth, 'combat'))
            if not c:
                continue
            p = c['median']['pressure']
            if prev is not None and p + g['slack'] < prev[1]:
                errors.append('%s: room %d presses the median class at %.2f x its healing, under room %d (%.2f)' % (tag, depth, p, prev[0], prev[1]))
            prev = (depth, p)
        late = e['rooms'][(n, g['lateRoom'], 'combat')]['median']
        if late['pressure'] < g['lateOverFirst'] * first['pressure']:
            errors.append('%s: room %d presses at %.2f, under %.1f x room 1 (%.2f)' % (tag, g['lateRoom'], late['pressure'], g['lateOverFirst'], first['pressure']))
        t5 = e['rooms'][(n, g['titleDepth'], 'combat')]['median']
        if t5['left'] < g['titleLeft']:
            errors.append('%s: the median class keeps %.0f%% of its health in room %d (the Ashwalker depth), under %.0f%%' % (
                tag, 100 * t5['left'], g['titleDepth'], 100 * g['titleLeft']))
        t9 = e['rooms'][(n, g['hardDepth'], 'combat')]['median']
        if t9['pressure'] < g['hardPressure']:
            errors.append('%s: room %d (the Emberdelver depth) presses the median class at %.2f x its healing, under %.2f' % (
                tag, g['hardDepth'], t9['pressure'], g['hardPressure']))
        for depth in bal['bossDepths']:
            b = e['rooms'][(n, depth, 'boss')]['median']
            bl = lim['boss']
            if not bl['clear'][0] <= b['clear'] <= bl['clear'][1]:
                errors.append('%s boss at depth %d: the median class kills it in %.0f s, outside %s' % (tag, depth, b['clear'], bl['clear']))
            if not bl['pressure'][0] <= b['pressure'] <= bl['pressure'][1]:
                errors.append('%s boss at depth %d: it presses the median class at %.2f x its healing, outside %s' % (tag, depth, b['pressure'], bl['pressure']))
        # a curse is a gamble, not a sentence
        c = lim['curse']
        mon = room_mon(ctx, lv, c['depth'], 'combat')
        rows = {cls: room(ctx, cls, lv, n, c['depth'], 'combat', mon, curses={'swarm': True, 'frailty': True}) for cls in S.ORDER}
        cm = median_row(rows)
        if cm['left'] < c['medianLeft']:
            errors.append('%s: with Swarm and Frailty at depth %d the median class keeps %.0f%%, under %.0f%%' % (
                tag, c['depth'], 100 * cm['left'], 100 * c['medianLeft']))
        # the party is no walkover and no wall next to the solo player
        if len(parties) > 1:
            a = e['rooms'][(parties[0], 1, 'combat')]['median']['clear']
            b = e['rooms'][(parties[-1], 1, 'combat')]['median']['clear']
            if not lim['party']['clearRatio'][0] <= b / a <= lim['party']['clearRatio'][1]:
                errors.append('level %d: room 1 takes a party of %d %.2f x the solo clear time, outside %s' % (
                    lv, parties[-1], b / a, lim['party']['clearRatio']))
    return errors


# ------------------------------------------------------------------------------------------------ reports
def fmt_s(x):
    return 'never' if x == float('inf') else '%.0f' % x


def report(res, detail=False):
    ctx = res['ctx']
    bal = ctx['bal']
    for lv, e in sorted(res['levels'].items()):
        h = e['hunt']
        print('\n== party level %d: the hunt pack of the level (hunting level %d, pack of %d, %d monsters): median class %.0f damage/s, %.0f heal/s,'
              ' %.1f s to die with no healing' % (lv, lv - bal['gap'], h['size'], h['monsters'], h['damageMedian'], h['healMedian'], h['burstMedian']))
        print('%-6s %-5s %-6s %5s %9s %7s %7s %7s %6s %7s %7s %7s %7s' % ('party', 'room', 'kind', 'waves', 'monsters', 'clear s', 'dmg/s', 'heal/s',
                                                                  'press', 'die s', 'burst', 'left', 'worst'))
        for (n, depth, kind), c in sorted(e['rooms'].items()):
            m, w = c['median'], c['worst']
            print('%-6d %-5d %-6s %5d %9d %7.0f %7.0f %7.0f %6.2f %7s %7.1f %6.0f%% %6.0f%%' % (
                n, depth, kind, m['waves'], m['size'], m['clear'], m['dmg'], m['heal'], m['pressure'], fmt_s(m['die']), m['burst'], 100 * m['left'], 100 * w['left']))
            if detail:
                for cls in S.ORDER:
                    r = c['rows'][cls]
                    print('         %-12s clear %5.0f  dmg/s %6.0f heal/s %6.0f  die %6s  burst %5.1f  left %4.0f%%' % (
                        S.name(cls), r['clear'], r['dmg'], r['heal'], fmt_s(r['die']), r['burst'], 100 * r['left']))


def hunt_report(res):
    for lv, e in sorted(res['levels'].items()):
        print('\n== the hunt pack of party level %d (pack of %d, %d monsters): every class' % (lv, e['hunt']['size'], e['hunt']['monsters']))
        print('%-12s %7s %7s %7s %6s %6s' % ('class', 'pool', 'dmg/s', 'heal/s', 'burst', 'sust'))
        for cls in S.ORDER:
            r = e['hunt']['rows'][cls]
            print('%-12s %7.0f %7.0f %7.0f %6.1f %6.2f' % (S.name(cls), r['pool'], r['damage'], r['heal'], r['burst'], r['sustain']))


def curses_report(res, curses):
    ctx = res['ctx']
    bal = ctx['bal']
    print('\n# with %s taken (the median class, solo, combat rooms)' % ' and '.join(sorted(curses)))
    print('%-6s %-5s %7s %7s %7s %6s %7s' % ('level', 'room', 'clear s', 'dmg/s', 'heal/s', 'press', 'left'))
    for lv in sorted(res['levels']):
        for depth in bal['depths']:
            if depth < ctx['cfg']['curseFrom'] and depth != 1:
                continue
            mon = room_mon(ctx, lv, depth, 'combat')
            rows = {cls: room(ctx, cls, lv, 1, depth, 'combat', mon, curses=curses) for cls in S.ORDER}
            m = median_row(rows)
            print('%-6d %-5d %7.0f %7.0f %7.0f %6.2f %6.0f%%' % (lv, depth, m['clear'], m['dmg'], m['heal'], m['pressure'], 100 * m['left']))


def main(argv):
    argv = SU.from_argv(argv)
    if SU.active():
        print(SU.banner())
    levels = [int(x) for x in argv[argv.index('--levels') + 1].split(',')] if '--levels' in argv else None
    parties = [int(x) for x in argv[argv.index('--party') + 1].split(',')] if '--party' in argv else None
    bal = BAL()
    levels = levels or bal['levels']
    parties = parties or bal['parties']
    if '--boons' in argv:
        cfg = numbers(levels)['cfg']
        for k, v in boon_values(cfg, bal).items():
            print('%-15s damage %+.3f taken %+.3f leech %.3f weight %d max %d (%s)' % ((k,) + v[:3] + v[3:]))
        for k, (o, t, lk) in enumerate(boon_curve(cfg, bal)):
            print('after %2d picks: damage x%.2f, taken x%.2f, leech %.1f%%' % (k, o, t, 100 * lk))
        return 0
    if '--legacy' in argv:
        print('# before O664 (pace.enabled = false)')
        report(compute(levels, parties, True), '--detail' in argv)
        print('\n# now')
    res = compute(levels, parties)
    report(res, '--detail' in argv)
    if '--hunt' in argv:
        hunt_report(res)
    if '--curses' in argv:
        curses_report(res, {'swarm': True, 'frailty': True, 'withering': True})
    if '--check' in argv:
        errors = check(res)
        for e in errors:
            print('FAIL ' + e)
        print('descent check: %s' % ('%d failure(s)' % len(errors) if errors else 'ok'))
        return 1 if errors else 0
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
