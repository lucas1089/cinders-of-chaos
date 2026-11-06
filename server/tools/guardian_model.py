#!/usr/bin/env python3
"""The guardian and rift pack model (O427; computed, not measured in game; server/README.md "Rifts", Guardian damage).

usage: python3 -I server/tools/guardian_model.py [--legacy] [--tiers 1,5,10,15] [--check]

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
import json, os, re, statistics, subprocess, sys

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


def run_tier(tier, legacy, bal, d, nbal, mons, pool, nums, ntables):
    t = nums['tiers'][tier - 1]
    pl = t['minLevel']
    base = window_dps(d, bal, t['pick'], tier, nbal, mons, pool)
    hits = base * bal['legendaryDamage'] * t['tierDamage'] * t['guardian']
    marks = t['marksKit'] * bal['marksTaken']
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
    res = compute(legacy, tiers)
    print('# %s' % ('before O427' if legacy else 'now'))
    report(res)
    if '--check' in argv:
        errors = check(res)
        for e in errors:
            print('FAIL ' + e)
        print('guardian check: %s' % ('%d failure(s)' % len(errors) if errors else 'ok'))
        return 1 if errors else 0
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
