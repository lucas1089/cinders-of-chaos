#!/usr/bin/env python3
"""The Greater Rift model (O668; computed, not measured in game; server/README.md "Greater Rift (O668)").

usage: python3 -I server/tools/greater_rift_model.py [--check] [--detail] [--level N] [--tiers 16,20,30] [--upgrades]
--upgrades  O686 phase 3: every monster x H (a Greater tier at H(2000) flat, the plain tier 15 at H of its level), class damage x the gain; the reached tier stays within 1

Owner 2026-11-19: the rift past tier 15, endless: a Greater Rift Key opens tier 16 and up, every tier raises the monsters by a
rule (rift_config.lua `greater`), a clock decides how far a key climbs (1-3 tiers inside it) or falls (1 tier). The model
answers: the tier the median class reaches at levels 1500 / 2000 / 2500 (solo and a party of 5), the seconds a tier takes, how
many runs the climb is, and how the guardian's damage stands against the median class's healing at the tier it reaches.

Without a flag: the tables. --check (CI): the limits of greater_balance_config.lua. --detail: every tier of one level (--level,
default 1500), --tiers: only those shown tiers in the detail table.

Inputs (everything in the repo): tools/greater_numbers.lua (rift_config.lua `greater`, rift_core.lua R.clearParts / R.greater*,
the clear of a tier 15 rift for a typical player: packs, guardian, walking), class_dps_model.py (the median class's damage at any
level: 1 target for the guardian, 5 targets for the packs), guardian_model.py + survival_model.py (the tier 15 guardian's damage
and the median class's pool and healing at any level), greater_balance_config.lua (the limits and their reasons).

The model, for a player level P, party size n (1 or 5), Greater tier g (shown tier 15 + g):
  seconds   packs / (area damage of P against the typical player x n-party factor) + guardian / (single damage ... ) + walking
            (the tier 15 parts of R.clearParts), the first two x (1 + rule.health)^g, the walk x the speed of the typical player /
            the speed of P. The clock is the layout band's limit x clock.mult.
  reach     the highest g whose seconds fit the clock (balance clockUse).
  climb     a key starts at g = 0 and goes up by the clock step it fits (rift_core.lua R.greaterUp: 3 / 2 / 1) until it reaches the
            reach: the runs it takes.
  guardian  the tier 15 guardian's hits per second (guardian_model.py, the entry level) x (1 + rule.damage)^g x the engine's level
            bonus of the shown level (config.lua monsterBonusDamage 0.0015 a level, patch 0090) against the median class of P:
            pressure = damage / healing, burst = pool / damage (seconds to die with no healing).
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spell_upgrade_model as SU  # noqa: E402  the spell upgrades switch (O686 phase 3): monster health x H, class damage x the gain

SERVER = os.path.normpath(os.path.join(HERE, '..'))
SCAN_MAX = 149  # the numbers script prints rule rows for g 1..SCAN_MAX


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


def numbers(levels=None):
    """greater_numbers.lua: the config, the tier 15 clear parts, the rule rows, the walking speed at `levels`"""
    args = [lua_bin(), os.path.join(SERVER, 'tools', 'greater_numbers.lua')]
    if levels:
        args.append(','.join(str(int(x)) for x in levels))
    out = subprocess.run(args, cwd=SERVER, check=True, capture_output=True, text=True).stdout
    return json.loads(out)


# ----------------------------------------------------------------------------------------------- pure maths (tested)
def hp_of(N, g):
    """the health of tier g against the tier 15 numbers of the typical player. O686 phase 3: x H of the spell ranks (rift.lua healthLevelOf): a
    Greater tier (g >= 1) at greater.healthLevel (2000, flat: a tier serves levels 1500 to 2500), the plain tier 15 at its own level; 1 while off"""
    h = SU.health(N['greater'].get('healthLevel', 2000)) if g > 0 else SU.health(N['tier15']['minLevel'])
    return h if g <= 0 else N['info'][str(g)]['health'] * h


def seconds(N, bal, power, tps, g, n=1):
    """clear seconds of Greater tier g for a median character of power = {'area': x, 'single': y} (its damage against the typical
    player's at the entry level) and walking speed ratio tps (the typical player's / its own), n = 1 or 5 players"""
    parts = N['tier15']['solo' if n == 1 else 'party5']
    k = 1.0 if n == 1 else bal['partyDps']
    hp = hp_of(N, g)
    return parts['packs'] * hp / (power['area'] * k) + parts['guardian'] * hp / (power['single'] * k) + parts['walk'] * tps


def reach(N, bal, power, tps, n=1, top=SCAN_MAX):
    """the highest g (0 = a plain tier 15 key) whose seconds fit the clock; -1 when even tier 15 does not"""
    limit = N['tier15']['clock'] * bal['clockUse']
    best = -1
    for g in range(0, top + 1):
        if seconds(N, bal, power, tps, g, n) <= limit:
            best = g
        else:
            break
    return best


def up_steps(N, secs, limit):
    """rift_core.lua R.greaterUp: tiers a sealed run climbs by the clock fraction it used (0 = not inside the clock)"""
    for st in N['greater']['clock']['steps']:
        if secs <= st['fraction'] * limit:
            return st['up']
    return 0


def climb_runs(N, bal, power, tps, n=1):
    """runs from the first key (g = 0) to a key at the reach, +1 / +2 / +3 by the clock; 0 when nothing is reached"""
    limit = N['tier15']['clock']
    target = reach(N, bal, power, tps, n)
    if target < 1:
        return 0
    g, runs = 0, 0
    while g < target and runs < 1000:
        runs += 1
        g += max(1, up_steps(N, seconds(N, bal, power, tps, g, n), limit))
    return runs


def damage_factor(N, g):
    """the guardian's hits at Greater tier g against tier 15: the rule's factor x the engine's level bonus of the shown level"""
    if g <= 0:
        return 1.0
    eb = N['engineBonus']
    i = N['info'][str(g)]
    return i['damage'] * (1 + eb * i['level']) / (1 + eb * N['tier15']['minLevel'])


# ----------------------------------------------------------------------------------------------- the repo's models
_cache = {}


def classes():
    if 'c' not in _cache:
        import class_dps_model as C
        _cache['c'] = C
    return _cache['c']


def guardian15():
    """(hits per second before the layers, marked share, the split) of the tier 15 guardian, guardian_model.py"""
    if 'g' not in _cache:
        import guardian_model as G
        r = G.compute(tiers=[15])
        row = r['rows'][0]
        _cache['g'] = (G, row['hits'] * row['ret'], row['marks'], r['bal']['split'])
    return _cache['g']


def power_of(level, ref):
    A, S = classes().median_dps(level)  # (1 target, 5 targets)
    return {'single': A / ref[0], 'area': S / ref[1]}


def guardian_row(level, g, party=1):
    G, hits, marks, split = guardian15()
    step = 0.10  # rift_config.lua party.damagePerExtraPlayer
    mult = damage_factor(NUMBERS, g) * (1 + step * 4 if party > 1 else 1)
    m = G.median_class(level, split, hits * mult, marks)
    return {'pressure': m['pressure'], 'burst': m['burst'], 'heal': m['heal'], 'pool': m['pool']}


NUMBERS = None


def compute(levels=None):
    global NUMBERS
    bal = BAL_CACHE or balance()
    levels = levels or bal['levels']
    N = numbers(sorted(set(levels + [N15_LEVEL])))
    NUMBERS = N
    with SU.forced(False):  # the tier 15 clear of greater_numbers.lua is the typical player's of today at the entry level
        ref = classes().median_dps(N['tier15']['minLevel'])
    out = {'N': N, 'bal': bal, 'rows': [], 'ref': ref}
    t0 = N['tps'][str(N15_LEVEL)]
    for lv in levels:
        power = power_of(lv, ref)
        tps = t0 / N['tps'][str(lv)]
        r = {'level': lv, 'power': power, 'tps': tps}
        r['reach'] = reach(N, bal, power, tps, 1)
        r['reachParty'] = reach(N, bal, power, tps, 5)
        r['runs'] = climb_runs(N, bal, power, tps, 1)
        r['runsParty'] = climb_runs(N, bal, power, tps, 5)
        r['secsReach'] = seconds(N, bal, power, tps, max(0, r['reach']), 1)
        r['secs15'] = seconds(N, bal, power, tps, 0, 1)
        r['secs16'] = seconds(N, bal, power, tps, 1, 1)
        r['guardian'] = guardian_row(lv, max(0, r['reach']))
        r['guardianParty'] = guardian_row(lv, max(0, r['reachParty']), 5)
        r['guardianSoloAtParty'] = guardian_row(lv, max(0, r['reachParty']))
        out['rows'].append(r)
    return out


N15_LEVEL = 1025
BAL_CACHE = None


def balance():
    global BAL_CACHE
    script = os.path.join(SERVER, 'tools', 'greater_balance.lua')
    out = subprocess.run([lua_bin(), script], cwd=SERVER, check=True, capture_output=True, text=True).stdout
    BAL_CACHE = json.loads(out)
    return BAL_CACHE


def curve(res, level, top):
    """per tier 1..top at one level: seconds, share of the clock, the step ratio, pressure, burst"""
    N, bal = res['N'], res['bal']
    ref = res['ref']
    power = power_of(level, ref)
    tps = N['tps'][str(N15_LEVEL)] / N['tps'][str(level)]
    rows, prev, prevp = [], None, None
    for g in range(1, top + 1):
        s = seconds(N, bal, power, tps, g, 1)
        gr = guardian_row(level, g)
        rows.append({'g': g, 'shown': N['maxTier'] + g, 'secs': s, 'share': s / N['tier15']['clock'],
                     'step': s / prev if prev else None, 'pressure': gr['pressure'], 'burst': gr['burst'],
                     'pstep': gr['pressure'] / prevp if prevp else None})
        prev, prevp = s, gr['pressure']
    return rows


# ----------------------------------------------------------------------------------------------- check and report
def check(res):
    lim = res['bal']['limits']
    N = res['N']
    errors = []
    by = {r['level']: r for r in res['rows']}
    for lv, (lo, hi) in sorted((int(k), v) for k, v in lim['reach'].items()):
        r = by.get(lv)
        if r is None:
            errors.append('level %d is not in the balance levels' % lv)
            continue
        shown = N['maxTier'] + r['reach']
        if not lo <= shown <= hi:
            errors.append('level %d: the median class reaches tier %d solo, outside %d-%d' % (lv, shown, lo, hi))
        if abs(r['reachParty'] - r['reach']) > lim['partyDelta']:
            errors.append('level %d: a party of 5 reaches tier %d, %d tiers from the solo tier %d (limit %d)' % (
                lv, N['maxTier'] + r['reachParty'], abs(r['reachParty'] - r['reach']), shown, lim['partyDelta']))
        runs = r['runs']
        if not lim['runs']['min'] <= runs <= lim['runs']['max']:
            errors.append('level %d: the climb takes %d runs, outside %d-%d' % (lv, runs, lim['runs']['min'], lim['runs']['max']))
        g = r['guardian']
        if not lim['pressure']['min'] <= g['pressure'] <= lim['pressure']['max']:
            errors.append('level %d: the guardian of tier %d deals %.2f x the median healing, outside %s-%s' % (
                lv, shown, g['pressure'], lim['pressure']['min'], lim['pressure']['max']))
        if not lim['burst']['min'] <= g['burst'] <= lim['burst']['max']:
            errors.append('level %d: the median class dies in %.1f s with no healing under the tier %d guardian, outside %s-%s' % (
                lv, g['burst'], shown, lim['burst']['min'], lim['burst']['max']))
        gp, gs = r['guardianParty'], r['guardianSoloAtParty']
        if gs['pressure'] > 0 and gp['pressure'] / gs['pressure'] > lim['partyPressure']:
            errors.append('level %d: a party of 5 takes %.2f x the solo pressure of the same tier, over %s' % (
                lv, gp['pressure'] / gs['pressure'], lim['partyPressure']))
    lo15, hi15 = by[max(by)]['reach'], None
    if 1500 in by and 2500 in by and by[2500]['reach'] - by[1500]['reach'] < lim['levelSpread']:
        errors.append('level 2500 reaches only %d tiers above level 1500, under %d' % (by[2500]['reach'] - by[1500]['reach'],
                                                                                    lim['levelSpread']))
    entry = by.get(res['bal']['levels'][0])
    if entry:
        share = entry['secs16'] / N['tier15']['clock']
        if not lim['entry']['min'] <= share <= lim['entry']['max']:
            errors.append('tier 16 at level %d takes %.0f%% of the clock, outside %.0f%%-%.0f%%' % (
                entry['level'], share * 100, lim['entry']['min'] * 100, lim['entry']['max'] * 100))
    # the curve: no wall, no free tier (level 1500, up to the reach of level 2500 and the scan)
    top = min(SCAN_MAX, (by[max(by)]['reach'] if by else 0) + res['bal']['scan'])
    for row in curve(res, 1500, top):
        if row['step'] is not None and not lim['stepRatio']['min'] <= row['step'] <= lim['stepRatio']['max']:
            errors.append('tier %d takes %.3f x the seconds of tier %d at level 1500, outside %s-%s (a wall or a free tier)' % (
                row['shown'], row['step'], row['shown'] - 1, lim['stepRatio']['min'], lim['stepRatio']['max']))
        if row['pstep'] is not None and row['pstep'] > lim['pressureStep']:
            errors.append('tier %d: the guardian pressure grows %.3f x from tier %d, over %s' % (row['shown'], row['pstep'],
                                                                                              row['shown'] - 1, lim['pressureStep']))
    # the rewards: a personal best never pays more gold than a share of the tier 15 chest at the top of the windows
    cfg = N['greater']
    topTier = max(int(hi) for _, (lo, hi) in lim['reach'].items())
    gold = cfg['rewards']['best']['gold']
    pb = gold['base'] + gold['perTier'] * (topTier - cfg['firstTier'])
    chest = N["tier15"]["chestGold"]  # the tier 15 chest of one finisher (R.reward, no bonus)
    if pb > lim['pbGoldShare'] * chest:
        errors.append('a personal best at tier %d pays %d gold, over %.0f%% of the tier 15 chest (%d)' % (
            topTier, pb, lim['pbGoldShare'] * 100, chest))
    return errors


def report(res, detail=None, tiers=None):
    N = res['N']
    print('tier 15 clear, typical player at level %d: packs %.0f s + guardian %.0f s + walk %.0f s = %.0f s of %d s clock' % (
        N['tier15']['minLevel'], N['tier15']['solo']['packs'], N['tier15']['solo']['guardian'], N['tier15']['solo']['walk'],
        N['tier15']['solo']['packs'] + N['tier15']['solo']['guardian'] + N['tier15']['solo']['walk'], N['tier15']['clock']))
    r = N['greater']['rule']
    print('rule per tier: health x%.2f, damage x%.2f, level +%d, chest +%d%%' % (1 + r['health'], 1 + r['damage'], r['levelStep'],
                                                                              r['reward'] * 100))
    print('%-6s %-7s %-7s %-6s %-7s %-8s %-8s %-9s %-8s %-8s' % ('level', 'solo', 'party5', 'runs', 's@reach', 's tier15', 's tier16',
                                                              'pressure', 'burst s', 'party x'))
    for x in res['rows']:
        gp, gs = x['guardianParty'], x['guardianSoloAtParty']
        print('%-6d %-7d %-7d %-6d %-7.0f %-8.0f %-8.0f %-9.2f %-8.1f %-8.2f' % (
            x['level'], N['maxTier'] + x['reach'], N['maxTier'] + x['reachParty'], x['runs'], x['secsReach'], x['secs15'],
            x['secs16'], x['guardian']['pressure'], x['guardian']['burst'], gp['pressure'] / gs['pressure'] if gs['pressure'] else 0))
    if detail:
        print()
        print('level %d, tier by tier (solo):' % detail)
        print('%-5s %-7s %-7s %-6s %-9s %-8s' % ('tier', 'secs', '% clock', 'step', 'pressure', 'burst s'))
        top = N['greater'].get('maxShownTier', 999) - N['maxTier']
        rows = curve(res, detail, min(SCAN_MAX, 60))
        for row in rows:
            if tiers and row['shown'] not in tiers:
                continue
            print('%-5d %-7.0f %-7.0f %-6s %-9.2f %-8.1f' % (row['shown'], row['secs'], row['share'] * 100,
                                                          '%.3f' % row['step'] if row['step'] else '-', row['pressure'], row['burst']))


def main(argv):
    argv = SU.from_argv(argv)
    if SU.active():
        print(SU.banner())
    detail = None
    tiers = None
    if '--detail' in argv:
        detail = 1500
    if '--level' in argv:
        detail = int(argv[argv.index('--level') + 1])
    if '--tiers' in argv:
        tiers = [int(x) for x in argv[argv.index('--tiers') + 1].split(',')]
    balance()
    res = compute()
    report(res, detail, tiers)
    if '--check' in argv:
        errors = check(res)
        for e in errors:
            print('FAIL ' + e)
        print('greater rift check: %s' % ('%d failure(s)' % len(errors) if errors else 'ok'))
        return 1 if errors else 0
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
