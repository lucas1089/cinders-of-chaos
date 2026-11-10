#!/usr/bin/env python3
"""The guardian and rift pack model (O427; computed, not measured in game; server/README.md "Rifts", Guardian damage).

usage: python3 -I server/tools/guardian_model.py [--legacy] [--tiers 1,5,10,15] [--check] [--hits] [--warn] [--passes N]

Owner report 2026-11-06: "the rift bosses hit too little, you can solo them with the Necromancer", then "make the Omen
bosses hit harder", "the rift monsters are weak too, put more monsters". The model answers, per rift tier and for the Omen
guardian: how hard the guardian and a lured pack hit the median class of the tier's level (seconds to die with no healing,
damage against healing), what the guardian's hits do to a Necromancer's trio (seconds the front minion lives, the share of
the damage the owner takes while the minions stand) and how many monsters a run plans and keeps alive.

Without a flag: the tables for the config as it is. --legacy: the numbers before O427 (guardian_balance_config.lua `legacy`
patched over the config). --check (CI): the limits of guardian_balance_config.lua at the tiers of `tiers` and the Omen.

Inputs (everything in the repo): tools/guardian_numbers.lua (rift_config.lua, rift_core.lua, guardian_core.lua,
boss_mechanics_config.lua, necro_config.lua through the real functions), survival_model.py (the median class of a level:
health, armour, absorbs, healing), minion_model.py (the trio's health), necro_balance_config.lua (stock monster damage,
the focus), data/monster/monsters/chaos (the XML hits of the window's monsters and of the three Omen guardians).

The model, per tier t and the geared median class at the tier's level:
  base      the guardian's hits per second before the player: the median of the tier window's monsters with XML (tiers from
            xmlFromTier on: every monster of the pool within the window, unpaced: rift monsters are not paced), else the
            stock line x stockFit at windowAt of the window. x legendary x the tier's damage x guardian.damage (x party).
  marks     the marked attacks: the mean share of max health per second of the guardian's telegraph list (the kit included)
            x marksTaken (a player moves out of most of them).
  player    survival_model.survive(): the split melee / physical / element through armour, absorbs, dodge, toughness; the
            marks on top; burst = pool / damage (seconds to die with no healing), pressure = damage / healing.
  pack      `pack` monsters of the window (median) x packDamage(t) x packTierMean, the same layers: burst and sustain
            (healing / damage) as the hunt model.
  trio      the Necromancer's warrior, archer and mage (minion_model.py health at the level): the guardian's hits, `focus`
            of them on the minions by the aggro weights, x minion.factor: the front minion lives health / that; the owner's
            share of the damage while the minions stand = (1 - focus) + focus x splash. Before: factor 0.25, splash 0.
"""
import csv, itertools, json, math, os, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import survival_model as S
import minion_model as M

SERVER = os.path.normpath(os.path.join(HERE, '..'))
BAL = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'guardian_balance_config.lua')


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


def lua_json(args, script):
    out = subprocess.run([lua_bin(), script] + args, cwd=SERVER, check=True, capture_output=True, text=True).stdout
    return json.loads(out)


_numbers = {}


def numbers(legacy):
    if legacy not in _numbers:
        _numbers[legacy] = lua_json(['legacy'] if legacy else [], os.path.join(SERVER, 'tools', 'guardian_numbers.lua'))
    return _numbers[legacy]


def pool_rows():
    txt = S.read(S.POOL).split('\tbosses = ')[0]
    return [(m.group(1), int(m.group(2))) for m in re.finditer(r'\{name = "([^"]+)", level = (\d+), exp', txt)]


def window_dps(d, bal, pick, tier, nbal, mons, pool):
    """the base damage per second of one monster of the tier's window before the layers (median of the XML ones from
    xmlFromTier on, else the stock line x stockFit at windowAt)"""
    lo, hi = pick
    if tier >= bal['xmlFromTier']:
        d2 = dict(d)
        d2['pace'] = {'enabled': False, 'damage': []}
        vals = []
        for name, level in pool:
            if lo <= level <= hi and name.lower() in mons and mons[name.lower()][1]:
                ml, att = mons[name.lower()]
                vals.append(sum(S.monster_dps(d2, dict(d['balance'], tierMean=1.0), ml, att).values()))
        if vals:
            return statistics.median(vals)
    level = lo + (hi - lo) * bal['windowAt']
    return M.power(nbal_stock(), level) * bal['stockFit']


_nstock = []


def nbal_stock():
    if not _nstock:
        _nstock.append(M.dump([50])['balance']['monsterDps'])
    return _nstock[0]


def omen_dps(d, nbal, mons_omen):
    d2 = dict(d)
    d2['pace'] = {'enabled': False, 'damage': []}
    vals = [sum(S.monster_dps(d2, dict(d['balance'], tierMean=1.0), 0, att).values()) for att in mons_omen]
    return statistics.mean(vals)


def omen_monsters():
    out = []
    folder = os.path.join(S.MONSTERS, 'omens')
    for f in sorted(os.listdir(folder)):
        if f.endswith('.xml'):
            out.append(S.parse_monster(S.read(os.path.join(folder, f)))[1])
    return out


def median_class(pl, pack_split, dps, marks_share):
    """per class at level pl under `dps` of hits and `marks_share` x marksTaken of max health per second: the median of
    the classes' burst and pressure; returns {pool, health, heal, damage, burst, pressure, sustain}"""
    d = S.dump([pl])
    bal = d['balance']
    gear, varm = S.gear_curves(), S.vocation_armour()
    pack = {'melee': dps * pack_split['melee'], 'physical': dps * pack_split['physical'],
            'element': dps * pack_split['element'], 'meleeHits': 0.5}
    rows = []
    for cls in S.ORDER:
        cands = [S.survive(d, bal, cls, pl, b, pack, gear, varm) for b in d['builds'][cls][str(pl)]]
        cands.sort(key=lambda r: r['burst'])
        r = cands[len(cands) // 2]
        r = dict(r)
        r['damage'] += marks_share * r['health']
        r['burst'] = r['pool'] / r['damage'] if r['damage'] > 0 else float('inf')
        r['sustain'] = r['heal'] / r['damage'] if r['damage'] > 0 else float('inf')
        r['pressure'] = r['damage'] / r['heal'] if r['heal'] > 0 else float('inf')
        rows.append(r)
    med = {k: statistics.median(r[k] for r in rows) for k in ('pool', 'health', 'heal', 'damage', 'burst', 'sustain', 'pressure')}
    med['rows'] = rows
    return med


def trio(level, dps, focus, factor, splash, nbal, reraise):
    """the front minion's seconds under the guardian's hits and the owner's share of the damage while the minions stand"""
    data = M.dump([level])
    rows = M.rows_of(data, 'necromancer', level)
    total = rows['warrior']['total']
    kinds = M.compose(data['balance'], 'necromancer', level, data['balance']['defaultBuild'], total)
    aggro = data['balance']['aggro']
    weights = {k: aggro[k] for k in kinds}
    wsum = sum(weights.values())
    life = {}
    for k in kinds:
        incoming = dps * focus * factor * weights[k] / wsum
        life[k] = rows[k]['health'] / incoming if incoming > 0 else float('inf')
    front = life.get('warrior', max(life.values()))
    return {'front': front, 'all': max(life.values()), 'health': sum(rows[k]['health'] for k in kinds),
            'owner': (1 - focus) + focus * splash, 'uptime': front / (front + reraise)}


def tier_inputs(tier, bal, d, nbal, mons, pool, nums):
    """(base, hits, marks) of a tier: the guardian's hits per second before the player's layers and the marked share"""
    t = nums['tiers'][tier - 1]
    base = window_dps(d, bal, t['pick'], tier, nbal, mons, pool)
    hits = base * bal['legendaryDamage'] * t['tierDamage'] * t['guardian']
    return base, hits, t['marksKit'] * bal['marksTaken']


def run_tier(tier, legacy, bal, d, nbal, mons, pool, nums, ntables):
    t = nums['tiers'][tier - 1]
    pl = t['minLevel']
    base, hits, marks = tier_inputs(tier, bal, d, nbal, mons, pool, nums)
    med = median_class(pl, bal['split'], hits, marks)
    pack_dps = base * bal['pack'] * t['packDamage'] * t['tierDamage'] * bal['packTierMean']
    pack = median_class(pl, bal['split'], pack_dps, 0)
    party = median_class(pl, bal['split'], hits * (1 + nums['party']['damagePerExtraPlayer'] * 4), marks)
    tr = trio(pl, hits, nbal['focus'], t['minion']['factor'], t['minion']['splash'], nbal, bal['reraise'])
    return {'tier': tier, 'level': pl, 'base': base, 'hits': hits, 'marks': marks, 'med': med, 'pack': pack, 'party': party,
            'trio': tr, 'count': t['count'], 'live': t['live'], 'packDamage': t['packDamage'], 'mult': t['guardian'],
            'tierDamage': t['tierDamage']}


def run_omen(legacy, bal, nbal, nums):
    o = nums['omen']
    pl = o['minLevel']
    d = S.dump([pl])
    base = omen_dps(d, nbal, omen_monsters())
    hits = base * o['guardian']
    marks = o['marksKit'] * bal['marksTaken']
    med = median_class(pl, bal['split'], hits, marks)
    party = median_class(pl, bal['split'], hits * 1.4, marks)
    tr = trio(pl, hits, nbal['focus'], o['minion']['factor'], o['minion']['splash'], nbal, bal['reraise'])
    return {'tier': 'omen', 'level': pl, 'base': base, 'hits': hits, 'marks': marks, 'med': med, 'party': party, 'trio': tr,
            'mult': o['guardian']}


def compute(legacy=False, tiers=None):
    nums = numbers(legacy)
    bal = nums['bal']
    d = S.dump([1007])
    nbal = M.dump([50])['balance']
    mons, pool = S.scaled_monsters(), pool_rows()
    tiers = tiers or bal['tiers']
    rows = [run_tier(t, legacy, bal, d, nbal, mons, pool, nums, None) for t in tiers]
    return {'bal': bal, 'rows': rows, 'omen': run_omen(legacy, bal, nbal, nums), 'nums': nums}


# ------------------------------------------------------------------------------------------------ O476: single hit, warning
HITS = os.path.join(SERVER, 'data', 'spells', 'guardian_hits.csv')
MON_TIERS = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'monster_tiers.lua')


def hit_rows():
    """[{name, level, mlevel, melee_max, ...}] of data/spells/guardian_hits.csv (tools/survey_guardian_hits.py)"""
    rows = []
    with open(HITS, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            row = {'name': r['name'], 'level': int(r['level']), 'mlevel': int(r['mlevel'])}
            for k in ('melee_max', 'melee_mean', 'elem_max', 'elem_mean'):
                row[k] = float(r[k])
            rows.append(row)
    return rows


def rank_damage(rank='legendary'):
    """the damage factor of a monster rank (monster_tiers.lua ChaosTiers; the model's legendaryDamage is the older 2.0)"""
    m = re.search(r'\b%s = \{label = "[A-Za-z]+", hp = [0-9.]+, speed = \d+, damage = ([0-9.]+)' % rank, S.read(MON_TIERS))
    return float(m.group(1))


def candidates(rows, nums, tier):
    """the rows the rift draws a guardian from (rift_core.lua R.pickTypes): the pool entries of the tier's window, widened
    by widenStep up to five times while fewer than `types` are in it; sorted by (level, name), the order that makes the
    strongest of three the guardian"""
    h = nums['hit']
    lo, hi = nums['tiers'][tier - 1]['pick']
    out = [r for r in rows if lo <= r['level'] <= hi]
    widen = 0
    while len(out) < h['types'] and widen < 5:
        widen += 1
        lo, hi = lo - h['widenStep'], hi + h['widenStep']
        out = [r for r in rows if lo <= r['level'] <= hi]
    return sorted(out, key=lambda r: (r['level'], r['name']))


def guardian_odds(cands, types=3):
    """[(row, probability)]: the guardian is the last of `types` distinct random picks of the sorted list, so the one at
    index i is it with chance C(i, types - 1) / C(n, types)"""
    n = len(cands)
    if n < types:
        return [(c, 1.0 / n) for c in cands]
    total = math.comb(n, types)
    return [(c, math.comb(i, types - 1) / total) for i, c in enumerate(cands)]


def chain(row, kind, tier, nums, bal, d, party=1):
    """one roll of the guardian's biggest attack of `kind` ('melee' or 'elem') as the player gets it before its own
    layers, no modifier on the monster or the key: the XML roll, x the engine's level bonus (enginePasses times), x the
    late-game boost (melee and physical only), x the legendary rank, x guardian.damage, x the tier's own damage (above 10),
    x the party's. The single application, as the code intends it."""
    h = bal['hit']
    t = nums['tiers'][tier - 1]
    v = row[kind + '_max']
    if row['mlevel'] > 0:
        v *= (1 + h['engineBonus'] * row['mlevel']) ** h['enginePasses']
    if kind == 'melee':
        v *= 1 + S.boost_percent(d['boost']['points'], row['level']) / 100.0
    v *= rank_damage() * t['guardian'] * t['tierDamage'] * (1 + nums['party']['damagePerExtraPlayer'] * (party - 1))
    return v


def worst_mods(nums, tier, kind):
    """(monster factor, key factor, key modifiers): the biggest one-hit multiplier the monster's four legendary modifiers
    (Brutal x1.4, Berserker x1.5 under half health, Ruthless a x1.5 critical hit, Emberforged / Frostforged / Stormforged
    +50% of a physical weapon hit as an element) and a key of the tier (up to maxMods modifiers, each with its top value in
    the tier's window, one per group, Brutality, Dread Guardian, Keen Fangs, a brand, a hex) can add"""
    mon = 1.4 * 1.5 * 1.5 * (1.5 if kind == 'melee' else 1.0)
    h = nums['hit']
    window = next(w for w in h['modWindow'] if tier <= w[0])
    top = window[2]
    opts = {}
    for m in h['mods']:
        if m['key'] not in nums['warn']['hot']:
            continue
        if tier < (m.get('minTier') or 1):
            continue
        v = m['tiers'][top - 1] / 100.0
        if m['key'] == 'keen':
            mult = h['critMult']
        elif m['key'] == 'flaying' and kind != 'melee':
            mult = 1.0
        elif m['key'] == 'searing' and kind == 'melee':
            mult = 1.0
        else:
            mult = 1 + v
        opts[m['key']] = (m.get('group') or m['key'], mult)
    names = sorted(opts)
    best = (1.0, ())
    for n in range(1, h['maxMods'] + 1):
        for combo in itertools.combinations(names, n):
            groups = [opts[k][0] for k in combo]
            if len(set(groups)) < len(groups):
                continue
            f = 1.0
            for k in combo:
                f *= opts[k][1]
            if f > best[0]:
                best = (f, combo)
    return mon, best[0], best[1]


def preload(levels):
    """one Lua dump for all the levels (survival_model.dump keys by the level list)"""
    d = S.dump(levels)
    for lv in levels:
        S._dump[(int(lv),)] = d
    return d


_class_rows = {}


def class_rows(level, split, hits, marks):
    """the class rows at a level under a tier's hits (the build of each class is the median one under them), cached"""
    key = (level, round(hits, 3), round(marks, 6))
    if key not in _class_rows:
        _class_rows[key] = median_class(level, split, hits, marks)['rows']
    return _class_rows[key]


def layered(rows, hit, kind):
    """the median over the classes of (the hit after the class's armour and absorbs, no dodge or block) / its pool"""
    vals = []
    for r in rows:
        if kind == 'melee':
            k = (1 - r['armourRed']) * (1 - r['absorbPhys'])
        else:
            k = 1 - r['absorbElem']
        vals.append(hit * k * r['toughness'] / r['pool'])
    return statistics.median(vals)


def item_share(rows, it, nums, tier, worst):
    """a guardian item's biggest roll (the bigger of its two kinds after the layers; worst: with the worst modifiers) over
    the median class's pool"""
    best = 0.0
    for kind in ('melee', 'elem'):
        v = it[kind]
        if v <= 0:
            continue
        if worst:
            mon, key, _ = worst_mods(nums, tier, kind)
            v *= mon * key
        best = max(best, layered(rows, v, kind))
    return best


def tier_hits(tier, nums, bal, d, hrows, party=1):
    """per tier: the candidates with their raw rolls and odds, the biggest, the typical (median by odds) and the quantile one"""
    cands = candidates(hrows, nums, tier)
    odds = guardian_odds(cands, nums['hit']['types'])
    items = []
    for c, p in odds:
        m = chain(c, 'melee', tier, nums, bal, d, party) if c['melee_max'] > 0 else 0.0
        e = chain(c, 'elem', tier, nums, bal, d, party) if c['elem_max'] > 0 else 0.0
        items.append({'row': c, 'p': p, 'melee': m, 'elem': e, 'top': max(m, e)})
    items.sort(key=lambda x: x['top'])
    acc, q, med = 0.0, None, None
    for it in items:
        acc += it['p']
        if med is None and acc >= 0.5:
            med = it
        if q is None and acc >= bal['hit']['quantile'] - 1e-9:
            q = it
    return {'items': items, 'biggest': items[-1], 'typical': med, 'quantile': q, 'count': len(items)}


def share_at(level, item, split, hits, marks, nums, tier):
    """the item's bigger kind, layered, over the median class's pool at `level`; and the median class (its pressure)"""
    med = median_class(level, split, hits, marks)
    return item_share(med['rows'], item, nums, tier, False), med


def warn_levels():
    """{'levels': [level of tiers 1..maxTier], 'partySize': n, 'detail': [...]} by the rule of rift_config.lua `warn`:
    the recommended solo level of a tier is the lowest level, from the tier's entry level up in steps of hit.step, at which
    (1) the guardian that `quantile` of the draws do not exceed rolls its biggest hit, after the median class's armour and
    absorbs, at most `oneHit` of that class's pool, and (2) the guardian's pressure on the median class (its damage against
    its healing, the model's `press`) is at most the pressure at the middle of the tier's monster window; the top of the
    window when no level up to it does; never below the level of the tier under it. partySize: the smallest party at which a player at the tier's entry level takes,
    per head, no more pressure than a solo player in the middle of the window (the guardian's hits shared by n, x (1 + the
    party's damage step x (n - 1)) each), at most the party limit"""
    nums = numbers(False)
    bal = nums['bal']
    h = bal['hit']
    d0 = S.dump([1007])
    nbal = M.dump([50])['balance']
    mons, pool = S.scaled_monsters(), pool_rows()
    hrows = hit_rows()
    d = preload(sorted(set(range(100, 1131, h['step']))))
    out, detail, worst_share = [], [], 0.0
    for tier in range(1, nums['hit']['maxTier'] + 1):
        t = nums['tiers'][tier - 1]
        base, hits, marks = tier_inputs(tier, bal, d0, nbal, mons, pool, nums)
        th = tier_hits(tier, nums, bal, d, hrows)
        lo, hi = t['pick']
        mid = int(round((lo + hi) / 2.0 / h['step']) * h['step'])
        p_mid = median_class(mid, bal['split'], hits, marks)['pressure']
        pick, one = None, 0.0
        for lv in range(t['minLevel'], hi + 1, h['step']):
            one, med = share_at(lv, th['quantile'], bal['split'], hits, marks, nums, tier)
            if one <= h['oneHit'] and med['pressure'] <= p_mid + 1e-9:
                pick = lv
                break
        why = 'rule'
        if pick is None:
            pick, why = hi, 'window top'
        if out and pick < out[-1]:
            pick, why = out[-1], 'tier below'
        p_min = median_class(t['minLevel'], bal['split'], hits, marks)['pressure']
        worst_share = max(worst_share, p_min / p_mid if p_mid > 0 else 0.0)
        out.append(pick)
        detail.append({'tier': tier, 'level': pick, 'why': why, 'mid': mid, 'pMid': p_mid, 'pMin': p_min, 'share': one,
                       'quantile': th['quantile']['row']['name'], 'qHit': th['quantile']['top'], 'count': th['count']})
    size = None
    step = nums['party']['damagePerExtraPlayer']
    for n in range(2, nums['hit']['maxPlayers'] + 1):
        if (1 + step * (n - 1)) / n * worst_share <= 1.0:
            size = n
            break
    return {'levels': out, 'partySize': size or nums['hit']['maxPlayers'], 'detail': detail, 'worstShare': worst_share}


def hit_table(tiers=None):
    """Part A: per tier the biggest, the typical and the quantile guardian roll, and each over the median class's pool at
    the tier's entry level, the middle of its window and its top; solo and a party of 5; no modifier and the worst ones"""
    nums = numbers(False)
    bal = nums['bal']
    h = bal['hit']
    d0 = S.dump([1007])
    nbal = M.dump([50])['balance']
    mons, pool = S.scaled_monsters(), pool_rows()
    hrows = hit_rows()
    d = preload(sorted(set(range(100, 1131, h['step']))))
    out = []
    for tier in tiers or range(1, nums['hit']['maxTier'] + 1):
        t = nums['tiers'][tier - 1]
        base, hits, marks = tier_inputs(tier, bal, d0, nbal, mons, pool, nums)
        lo, hi = t['pick']
        levels = [t['minLevel'], int(round((lo + hi) / 2.0 / h['step']) * h['step']), hi]
        row = {'tier': tier, 'levels': levels}
        for party in (1, 5):
            th = tier_hits(tier, nums, bal, d, hrows, party)
            for tag in ('biggest', 'typical', 'quantile'):
                it = th[tag]
                rows_mid = class_rows(levels[1], bal['split'], hits, marks)
                kinds = [k for k in ('melee', 'elem') if it[k] > 0]
                kind = max(kinds, key=lambda k: layered(rows_mid, it[k], k))
                mon, key, combo = worst_mods(nums, tier, kind)
                cell = {'name': it['row']['name'], 'kind': kind, 'raw': it[kind], 'worst': it[kind] * mon * key,
                        'combo': combo, 'share': [], 'worstShare': [], 'pool': [], 'okLevel': None}
                for lv in levels:
                    rows_c = class_rows(lv, bal['split'], hits, marks)
                    cell['pool'].append(statistics.median(r['pool'] for r in rows_c))
                    cell['share'].append(item_share(rows_c, it, nums, tier, False))
                    cell['worstShare'].append(item_share(rows_c, it, nums, tier, True))
                for lv in range(t['minLevel'], 1131, h['step']):
                    if item_share(class_rows(lv, bal['split'], hits, marks), it, nums, tier, False) <= h['oneHit']:
                        cell['okLevel'] = lv
                        break
                row[(tag, party)] = cell
            row[('count', party)] = th['count']
        out.append(row)
    return out


def print_hits(rows):
    print("Part A, raw roll of the guardian's biggest attack before the player (solo; a party of 5 is x1.4; worst = the worst")
    print('modifiers of the monster and of a key of the tier), the biggest / typical (median draw) / 90th percentile guardian:')
    print('%-4s %4s  %-9s %8s %8s  %-9s %8s %8s  %-9s %8s %8s' % ('tier', 'n', 'biggest', 'raw', 'worst', 'typical', 'raw',
                                                                  'worst', 'q90', 'raw', 'worst'))
    for r in rows:
        c = [r[(k, 1)] for k in ('biggest', 'typical', 'quantile')]
        print('%-4d %4d  %-9.9s %8.0f %8.0f  %-9.9s %8.0f %8.0f  %-9.9s %8.0f %8.0f' % (
            r['tier'], r[('count', 1)], c[0]['name'], c[0]['raw'], c[0]['worst'], c[1]['name'], c[1]['raw'], c[1]['worst'],
            c[2]['name'], c[2]['raw'], c[2]['worst']))
    print("\nHit after the median class's armour and absorbs over its pool (health + mana for a mana shield class), at the")
    print("tier's entry level / middle of the window / top; solo, then a party of 5 (the hits x1.4); unmodified | worst modifiers:")
    for tag in ('biggest', 'typical', 'quantile'):
        print('-- %s guardian' % tag)
        print('%-4s %-17s %-23s %-23s %-23s %-23s' % ('tier', 'levels', 'solo', 'solo worst', 'party5', 'party5 worst'))
        for r in rows:
            def f(party, key):
                return '/'.join('%.2f' % x for x in r[(tag, party)][key])
            print('%-4d %-17s %-23s %-23s %-23s %-23s' % (r['tier'], '/'.join(str(x) for x in r['levels']),
                  f(1, 'share'), f(1, 'worstShare'), f(5, 'share'), f(5, 'worstShare')))
    print('\nlowest level (steps of 5, from the entry level, to 1130) at which that hit, solo and unmodified, is at most 60%')
    print('of the median class pool; - = none up to 1130 (solo | party of 5):')
    print('%-4s %-18s %-18s %-18s' % ('tier', 'biggest', 'typical', 'q90'))
    for r in rows:
        def ok(tag):
            return '%s | %s' % tuple(str(r[(tag, p)]['okLevel'] or '-') for p in (1, 5))
        print('%-4d %-18s %-18s %-18s' % (r['tier'], ok('biggest'), ok('typical'), ok('quantile')))
    print('\npool of the median class at those levels: ' + '; '.join(
        't%d %s' % (r['tier'], '/'.join('%.0f' % x for x in r[('typical', 1)]['pool'])) for r in rows))


def check_warn(nums):
    """errors: the stored `warn` block of rift_config.lua against the rule"""
    errors = []
    stored = nums.get('warn')
    if not stored:
        return ['rift_config.lua has no `warn` block']
    got = warn_levels()
    want = got['levels']
    if list(stored.get('levels') or []) != want:
        errors.append('warn.levels is %s, the rule gives %s (python3 -I server/tools/guardian_model.py --warn)' % (
            stored.get('levels'), want))
    if stored.get('partySize') != got['partySize']:
        errors.append('warn.partySize is %s, the rule gives %s' % (stored.get('partySize'), got['partySize']))
    return errors




def check(res):
    lim = res['bal']['limits']
    errors = []
    for r in res['rows']:
        m, tag = r['med'], 'tier %s' % r['tier']
        if not lim['burst']['min'] <= m['burst'] <= lim['burst']['max']:
            errors.append('%s: the median class dies in %.1f s with no healing under the guardian, outside %s-%s' % (
                tag, m['burst'], lim['burst']['min'], lim['burst']['max']))
        if not lim['pressure']['min'] <= m['pressure'] <= lim['pressure']['max']:
            errors.append('%s: the guardian deals %.2f x the median healing, outside %s-%s' % (
                tag, m['pressure'], lim['pressure']['min'], lim['pressure']['max']))
        if r['party']['pressure'] > lim['partyPressure']:
            errors.append('%s: a party of 5 takes %.2f x the healing of one player from the guardian, over %s' % (
                tag, r['party']['pressure'], lim['partyPressure']))
        p = r['pack']
        if not lim['packSustain']['min'] <= p['sustain'] <= lim['packSustain']['max']:
            errors.append('%s: the median class heals %.2f x a pack, outside %s-%s' % (
                tag, p['sustain'], lim['packSustain']['min'], lim['packSustain']['max']))
        t = r['trio']
        if not lim['minionMin'] <= t['front'] <= lim['minionMax']:
            errors.append('%s: the Necromancer front minion lives %.1f s under the guardian, outside %s-%s' % (
                tag, t['front'], lim['minionMin'], lim['minionMax']))
        if t['owner'] < lim['ownerShare']:
            errors.append('%s: the owner takes %.2f of the guardian damage while the minions stand, under %s' % (
                tag, t['owner'], lim['ownerShare']))
        if r['live'] > lim['liveMax']:
            errors.append('%s: %d monsters alive at once, over %d' % (tag, r['live'], lim['liveMax']))
    o = res['omen']
    if not lim['omenBurst']['min'] <= o['med']['burst'] <= lim['omenBurst']['max']:
        errors.append('omen: the median class dies in %.1f s with no healing, outside %s-%s' % (
            o['med']['burst'], lim['omenBurst']['min'], lim['omenBurst']['max']))
    if not lim['omenPressure']['min'] <= o['med']['pressure'] <= lim['omenPressure']['max']:
        errors.append('omen: the guardian deals %.2f x the median healing, outside %s-%s' % (
            o['med']['pressure'], lim['omenPressure']['min'], lim['omenPressure']['max']))
    if o['party']['pressure'] > lim['partyPressure'] + 0.2:
        errors.append('omen: a party of 5 takes %.2f x the healing of one player, over %s' % (
            o['party']['pressure'], lim['partyPressure'] + 0.2))
    if not lim['minionMin'] <= o['trio']['front'] <= lim['minionMax']:
        errors.append('omen: the Necromancer front minion lives %.1f s, outside %s-%s' % (
            o['trio']['front'], lim['minionMin'], lim['minionMax']))
    rows = res['rows']
    if len(rows) > 1 and rows[-1]['count'] < lim['denseMin'] * rows[0]['count']:
        errors.append('the last tier plans %d monsters, under %.1f x tier 1 (%d)' % (rows[-1]['count'], lim['denseMin'],
                                                                                    rows[0]['count']))
    return errors


def report(res):
    print('%-7s %6s %7s %7s %6s %6s %7s %6s %7s %6s %6s %6s %6s' % (
        'tier', 'level', 'g.dps', 'pool', 'heal', 'die s', 'press', 'party s', 'pack s', 'pk sus', 'front', 'owner', 'upt'))
    for r in res['rows'] + [res['omen']]:
        m = r['med']
        p = r.get('pack')
        t = r['trio']
        print('%-7s %6d %7.0f %7.0f %6.0f %6.1f %7.2f %6.1f %7s %6s %6.1f %6.2f %6.2f' % (
            r['tier'], r['level'], r['hits'], m['pool'], m['heal'], m['burst'], m['pressure'], r['party']['burst'],
            '%.1f' % p['burst'] if p else '-', '%.2f' % p['sustain'] if p else '-', t['front'], t['owner'], t['uptime']))
    print('\nmonsters planned / alive at once (solo, typical layout) and pack damage:')
    for r in res['rows']:
        print('  tier %2s: %4d / %3d, pack x%.2f, guardian x%.2f (+ legendary x%s), tier damage x%.2f' % (
            r['tier'], r['count'], r['live'], r['packDamage'], r['mult'], res['bal']['legendaryDamage'], r['tierDamage']))


def main(argv):
    tiers = None
    if '--tiers' in argv:
        tiers = [int(x) for x in argv[argv.index('--tiers') + 1].split(',')]
    legacy = '--legacy' in argv
    if '--passes' in argv:  # the engine's level bonus counted this many times (1 = as the models and the fixed engine, 2 = the live engine of before)
        numbers(False)['bal']['hit']['enginePasses'] = int(argv[argv.index('--passes') + 1])
    if '--hits' in argv:
        print_hits(hit_table(tiers))
        return 0
    if '--warn' in argv:
        w = warn_levels()
        print('recommended solo level by tier (rule: guardian_model.py warn_levels): %s' % w['levels'])
        print('partySize %d (worst pressure at the entry level over the middle of the window: %.2f)' % (
            w['partySize'], w['worstShare']))
        print('%-4s %6s %6s %-10s %-22s %7s %6s %6s %6s' % ('tier', 'level', 'mid', 'from', 'q90 guardian', 'q90 hit', 'share',
                                                          'p mid', 'p min'))
        for r in w['detail']:
            print('%-4d %6d %6d %-10s %-22.22s %7.0f %6.2f %6.2f %6.2f' % (
                r['tier'], r['level'], r['mid'], r['why'], r['quantile'], r['qHit'], r['share'], r['pMid'], r['pMin']))
        return 0
    res = compute(legacy, tiers)
    print('# %s' % ('before O427' if legacy else 'now'))
    report(res)
    if '--check' in argv:
        errors = check(res)
        if not legacy and tiers is None:
            errors += check_warn(numbers(False))
        for e in errors:
            print('FAIL ' + e)
        print('guardian check: %s' % ('%d failure(s)' % len(errors) if errors else 'ok'))
        return 1 if errors else 0
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
