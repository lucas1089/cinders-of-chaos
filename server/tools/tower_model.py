#!/usr/bin/env python3
"""The Infinity Tower model: seconds to clear every floor for the classes, against a base hunt pack of the same level
(computed, not measured; server/README.md "Infinity Tower balance and floor rewards", O144).

usage: python3 -I server/tools/tower_model.py [--levels 100,300,500,800,1000] [--floors 1,5,10,...] [--before]
                                              [--derive] [--check] [--damage]

--check (CI): bounds the floors of infinitytower_balance_config.lua (limits there): the floor a player of the meant level
meets dies in clearMin..clearMax seconds and in huntMin..huntMax times a base hunt pack of that level; a boss in
bossMin..bossMax seconds and never healing more than a share of the median class's damage; the floor after a milestone
floor is easier (breather) and no floor jumps more than stepMax over the one before; the damage of a floor's monsters is
what a hunt monster of the floor's shown level deals (pace damage curve x hit(L) / hit(band level), O328); the items and the
gold an hour of the tower stay at a hunt of the same level (lootShare, killGold, O328); a median-class player of level `reachLevel` gets `reachMin`..`reachMax` floors deep,
a weak class at least `weakReach`; a player of 60% of the floor's level still clears it in underMax seconds; nobody is
stopped by a healing boss. Prints the tables.
--derive prints the `health`, `bossHealth`, `damage`, `lootShare` and `killGold` lines for the config from `clear`, `level`,
`count`, the tiers, `hit` and the hunt model.
--damage prints the damage of the floors against the line of O285 (the stock hit of the species x the factor).
--before prints the same table for the planner of 2026-10-22 (stock pool health, tier chances rising with every
floor, up to 16 monsters, bosses on floors 10-120 in the old order): what the beta players met.

Inputs (everything in the repo): tools/pack_model.py (the damage of every class in packs, the pack cleave, the base hunt
pack of a level), data/scripts/chaos/monster_tiers.lua (tier health, modifier counts and the modifiers' health effect),
data/scripts/chaos/infinitytower_balance_config.lua, data/scripts/chaos/bounty_pool.lua (stock health of the old pools),
data/scripts/chaos/pace_config.lua (the damage curve, lootLevel.goldPerHour), infinitytower_run.lua (nextFloorDelay).

The model, per floor and group: the monsters of the floor appear together around the group, so the floor dies like a pack,
P x health / (damage of one target + (P - 1) x the gain of one more target), as pack_model.py does, with at most
pack_model.PCAP targets counted; a group adds the damage of its players. health = the floor's normal health x the
expected tier factor (tier chances x tier health x the modifiers' average health effect: Juggernaut x1.6, Stoneskin
x1/0.7). A boss floor: its helpers, then the boss alone, boss health / (damage of one target x uptime - its heal).
"""
import functools
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # python -I leaves the script's folder out of sys.path
import pack_model as PM  # noqa: E402

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')
BALANCE = os.path.join(CHAOS, 'infinitytower_balance_config.lua')
TIERS = os.path.join(CHAOS, 'monster_tiers.lua')
POOL = os.path.join(CHAOS, 'bounty_pool.lua')
PACE = os.path.join(CHAOS, 'pace_config.lua')
RUN = os.path.join(CHAOS, 'infinitytower_run.lua')

CAP = PM.PCAP

# the planner of 2026-10-22 (infinitytower_run.lua before O144): what the beta players met
LEGACY_BOSSES = [  # floor 10, 20, ... : health, heal per second (server/README.md "Solo kill times")
    ('the grey widow', 3200, 42), ('the ashen count', 50000, 0), ('zeburoth', 110000, 1750), ('pestrogh', 80000, 300),
    ('morgashal', 22500, 316), ('moloveth', 60000, 64), ('vharagoth', 55000, 64), ('ssylvath the corruptor', 28000, 250),
    ('ashvoran', 270000, 1750), ('massacre', 32000, 0), ("jungle's revenge", 1800, 204), ('vhalkareth', 50000, 60)]
LEGACY_POOLS = [
    ['troll', 'orc warrior', 'skeleton', 'ghoul', 'dwarf soldier'],
    ['minotaur', 'cyclops', 'giant spider', 'gargoyle', 'stone golem'],
    ['dragon', 'warlock', 'banshee', 'serpent spawn', 'crystal spider'],
    ['demon skeleton', 'vampire', 'werewolf', 'lost soul', 'hydra'],
    ['behemoth', 'dragon lord', 'dark torturer', 'fury', 'phantasm'],
    ['hellhound', 'juggernaut', 'plaguesmith', 'undead dragon', 'grim reaper'],
    ['demon', 'destroyer', 'hellfire fighter', 'massive fire elemental', 'blightwalker']]
STOCK_HEALTH = {'demon': 8200}  # the pool's "Demon" is a renamed spawn of 50 health; the stock demon has 8,200


def lin(points, x):
    return PM.lin(points, x)


# ------------------------------------------------------------------------------------------------ the config
def read(path):
    return open(path, encoding='utf-8').read()


def curve(text, key):
    m = re.search(r'(?m)^\t' + key + r' = \{((?:\s*\{[-0-9.]+, [-0-9.]+\},?)+)\s*\}', text)
    return [(float(a), float(b)) for a, b in re.findall(r'\{([-0-9.]+), ([-0-9.]+)\}', m.group(1))]


def scalar(text, key):
    return float(re.search(r'(?m)^\t' + key + r' = ([-0-9.]+)', text).group(1))


def balance(text=None):
    t = text if text is not None else read(BALANCE)
    pools = re.search(r'(?m)^\tpools = \{(.*?)\n\t\}', t, re.S).group(1)
    pools = [re.findall(r'"([^"]+)"', p) for p in re.findall(r'\{([^{}]*)\}', pools)]
    bosses = [(n, int(h)) for n, h in re.findall(r'\{name = "([^"]+)", heal = (\d+)\}', t)]
    bh = re.search(r'(?m)^\tbossHealth = \{(.*?)\}', t, re.S).group(1)
    limits = dict((k, float(v)) for k, v in re.findall(r'\t\t(\w+) = ([-0-9.]+)', re.search(r'limits = \{(.*?)\n\t\}', t, re.S).group(1)))
    saw = [float(x) for x in re.search(r'(?m)^\tsawtooth = \{([0-9., ]+)\}', t).group(1).split(',')]
    cfg = {
        'pools': pools, 'bosses': bosses, 'bossHealth': dict((int(k), float(v)) for k, v in re.findall(r'\[(\d+)\] = ([0-9.]+)', bh)),
        'count': curve(t, 'count'), 'magic': curve(t, 'magic'), 'rare': curve(t, 'rare'), 'legendary': curve(t, 'legendary'),
        'level': curve(t, 'level'), 'clear': curve(t, 'clear'), 'health': curve(t, 'health'), 'damage': curve(t, 'damage'),
        'hit': curve(t, 'hit'), 'lootShare': curve(t, 'lootShare'), 'killGold': curve(t, 'killGold'),
        'bossSeconds': curve(t, 'bossSeconds'), 'sawtooth': saw, 'limits': limits,
        'beyond': dict((k, float(v)) for k, v in re.findall(r'\t\t(\w+) = ([-0-9.]+)', re.search(r'(?m)^\tbeyond = \{(.*?)\n\t\}', t, re.S).group(1))),
        'tierHealth': dict((k, float(v)) for k, v in re.findall(r'(magic|rare|legendary) = ([0-9.]+)',
                                                                re.search(r'(?m)^\ttierHealth = \{(.*?)\}', t).group(1)))}
    for k in ('bossEvery', 'milestoneEvery', 'bandFloors', 'bossHelperDivisor', 'perPlayer', 'maxFloor', 'packUptime', 'bossUptime', 'engageSeconds', 'lootScaledFrom', 'goldShare', 'climb'):
        cfg[k] = scalar(t, k)
    return cfg


# ------------------------------------------------------------------------------------------------ monster tiers
def tier_info(cfg=None):
    """({tier: health x}, {tier: average modifier count}, average health effect of one modifier) from monster_tiers.lua;
    with a config the tower's own tier health (`tierHealth`) replaces the stock x2 / x3.5 / x6"""
    t = read(TIERS)
    hp = dict((k, float(v)) for k, v in re.findall(r'\n\t(magic|rare|legendary) = \{label = "\w+", hp = ([0-9.]+)', t))
    cnt = dict((k, (int(a) + int(b)) / 2.0) for k, a, b in
               re.findall(r'(magic|rare|legendary) = \{(\d), (\d)\}', t.split('modCount =', 1)[1].split('\n', 1)[0]))
    block = t.split('ChaosMods = {', 1)[1].split('\nChaosModList', 1)[0]
    effects = []
    for body in re.split(r'\n\t(?=[a-z]+ = \{name = ")', block)[1:]:
        h = re.search(r'\bhp = ([0-9.]+)', body)
        k = re.search(r'\btaken = ([0-9.]+)', body)
        effects.append((float(h.group(1)) if h else 1.0) / (float(k.group(1)) if k else 1.0))
    return (cfg['tierHealth'] if cfg else hp), cnt, sum(effects) / len(effects)


def tier_factor(mix, info):
    """expected health factor of a monster with the tier chances mix = (magic, rare, legendary) as fractions"""
    hp, cnt, mod = info
    normal = 1.0 - sum(mix)
    return normal + sum(p * hp[n] * mod ** cnt[n] for p, n in zip(mix, ('magic', 'rare', 'legendary')))


# ------------------------------------------------------------------------------------------------ schemes
def growth(cfg, rate, accel, f):
    """exp(rate x d + accel x d^2 / 2), d = f - maxFloor; 1 up to maxFloor (B.growth of infinitytower_balance_core.lua)"""
    d = f - cfg['maxFloor']
    return 1.0 if d <= 0 else math.exp(min(60.0, rate * d + accel * d * d / 2))


def dmg_cap_floor(cfg):
    """the first floor whose damage factor reaches damageMax (the climb and the growth together: no closed form)"""
    f, top = int(cfg['maxFloor']), cfg['beyond']['damageMax']
    while dmg_at(cfg, f) < top and f < 10 ** 7:
        f += 1
    return f


def growth_floor(cfg, rate, accel, factor):
    """the first whole floor where the growth is at least `factor` (B.growthFloor)"""
    want, lo, hi = math.log(factor), 0.0, 1e9
    while hi - lo > 1e-6:
        mid = (lo + hi) / 2
        lo, hi = (lo, mid) if rate * mid + accel * mid * mid / 2 >= want else (mid, hi)
    return int(cfg['maxFloor'] + math.ceil(hi))


def trend_hp(cfg, f):
    """the health of a normal monster of floor f before the sawtooth and the cap: the curve, then the growth"""
    b = cfg['beyond']
    return lin(cfg['health'], f) * growth(cfg, b['healthRate'], b['healthAccel'], f)


def hp_at(cfg, f):
    """B.health: the trend x the sawtooth, capped (int32 health with room for the legendary tier)"""
    v = trend_hp(cfg, f) * cfg['sawtooth'][(int(f) - 1) % len(cfg['sawtooth'])]
    return math.floor(min(cfg['beyond']['healthMax'], v)) if f > cfg['maxFloor'] else v


def boss_hp_at(cfg, f):
    """B.bossHealth: the table up to maxFloor (the boss floor at or below f), then the last x the growth, capped"""
    b = cfg['beyond']
    keys = sorted(cfg['bossHealth'])
    best = max([k for k in keys if k <= f] or [keys[0]])
    v = cfg['bossHealth'][best]
    if f > keys[-1]:
        v *= growth(cfg, b['bossHealthRate'], b['bossHealthAccel'], f)
    return math.floor(min(b['bossHealthMax'], v))


def climb_at(cfg, f):
    """B.climb: 1 + climb x (floor - 1) on every floor, never held"""
    return 1 + cfg.get('climb', 0) * (f - 1)


def dmg_at(cfg, f):
    """B.damage: the curve x the climb, then x the growth, capped"""
    b = cfg['beyond']
    v = lin(cfg['damage'], f) * climb_at(cfg, f)
    return min(b['damageMax'], v * growth(cfg, b['damageRate'], b['damageAccel'], f)) if f > cfg['maxFloor'] else v


def boss_dmg_at(cfg, f):
    """B.bossDamage: 1 up to maxFloor, then the growth, capped"""
    b = cfg['beyond']
    return min(b['damageMax'], growth(cfg, b['damageRate'], b['damageAccel'], f))


def level_at(cfg, f):
    """B.level (not rounded): the curve, then levelPerFloor a floor, capped"""
    b = cfg['beyond']
    v = lin(cfg['level'], f)
    return min(b['levelMax'], v + b['levelPerFloor'] * (f - cfg['maxFloor'])) if f > cfg['maxFloor'] else v


def new_scheme(cfg):
    n = len(cfg['sawtooth'])

    def count(f, players=1):
        return int(math.floor(lin(cfg['count'], f) + 0.5)) + (players - 1) * int(cfg['perPlayer'])

    def mix(f):
        return tuple(lin(cfg[k], f) / 100.0 for k in ('magic', 'rare', 'legendary'))

    def hp(f):
        return hp_at(cfg, f)

    def boss(f):
        b = cfg['bosses'][(int(f // cfg['bossEvery']) - 1) % len(cfg['bosses'])]
        return boss_hp_at(cfg, int(f)), b[1]

    return {'name': 'now', 'count': count, 'mix': mix, 'hp': hp, 'boss': boss, 'every': int(cfg['bossEvery']),
            'divisor': int(cfg['bossHelperDivisor']), 'dmg': lambda f: dmg_at(cfg, f)}


def legacy_scheme():
    pool = dict((n.lower(), h) for n, h in re.findall(r'\{name = "([^"]+)", level = \d+, exp = \d+, health = (\d+), spawns',
                                                      read(POOL).split('\tbosses = ')[0]))

    def stock(name):
        return STOCK_HEALTH.get(name, float(pool[name]))

    def count(f, players=1):
        return min(4 + f // 3, 16) + (players - 1) * 2

    def mix(f):
        return (min(5 + f, 60) / 100.0, min(f // 2, 30) / 100.0, min(f // 10, 10) / 100.0)

    def hp(f):
        names = LEGACY_POOLS[min(len(LEGACY_POOLS), f // 8 + 1) - 1]
        return sum(stock(n) for n in names) / len(names)

    def boss(f):
        b = LEGACY_BOSSES[(f // 10 - 1) % len(LEGACY_BOSSES)]
        return float(b[1]), b[2]

    return {'name': 'before', 'count': count, 'mix': mix, 'hp': hp, 'boss': boss, 'every': 10, 'divisor': 3,
            'dmg': lambda f: 1.0}


# ------------------------------------------------------------------------------------------------ the damage
_PACE = PM.pace()


def class_dps(cls, L, P, kit=True):
    """(damage per second on a pack of P monsters, one-target damage) of a class at level L, as pack_model.py"""
    d1, d5 = PM.damage(cls, L, kit)
    if PM.VOC[cls] in _PACE['cleave']:
        e = _PACE['cleave'][PM.VOC[cls]]
        pc = lin([(PM.CLEAVE_FROM, e[0]), (PM.CLEAVE_TO, e[2])], L)
        d5 *= 1 + pc / 100.0 * min(e[1], 4)
    s = max(0.0, (d5 - d1) / 4)
    return d1 + (min(P, CAP) - 1) * s, d1


def ranked(L, P):
    """the classes from the weakest to the strongest on a pack of P at level L"""
    return sorted(PM.C4, key=lambda c: class_dps(c, L, P)[0])


def median_class(L, P):
    r = ranked(L, P)
    return r[len(r) // 2]


def player_dps(cls, L, P):
    """(dps on a pack of P, one-target damage) of a class; cls None = the median class: the mean of the middle five of the
    21 classes by their damage on the pack (one class would jump with every level)"""
    if cls:
        return class_dps(cls, L, P)
    mid = ranked(L, P)[8:13]
    v = [class_dps(c, L, P) for c in mid]
    return sum(a for a, _ in v) / len(v), sum(b for _, b in v) / len(v)


# ------------------------------------------------------------------------------------------------ the floors
def is_boss(sc, f):
    return f % sc['every'] == 0


def floor_time(sc, cfg, f, group, info):
    """seconds to clear floor f for group = [(class or None for the median class, level), ...]: (total, pack, boss)"""
    players = len(group)
    n = sc['count'](f, players)
    boss = is_boss(sc, f)
    helpers = n // sc['divisor'] if boss else n
    names = [c for c, _ in group]
    pack = boss_t = 0.0
    if helpers > 0:
        e = tier_factor(sc['mix'](f), info)
        dps = sum(player_dps(c, L, helpers)[0] for c, (_, L) in zip(names, group)) * cfg['packUptime']
        pack = helpers * sc['hp'](f) * e / dps
    if boss:
        bh, heal = sc['boss'](f)
        d1 = sum(player_dps(c, L, 1)[1] for c, (_, L) in zip(names, group)) * cfg['bossUptime']
        boss_t = bh / (d1 - heal) if d1 > heal else float('inf')
    return pack + boss_t + cfg['engageSeconds'], pack, boss_t


def hunt_clear(L, cfg_pace=None, mons=None):
    """seconds a base hunt pack (the late level-scaled set from level 670) of the median class dies in at level L"""
    return PM.pack_clear(L, L >= 670, cfg_pace or _PACE, mons if mons is not None else _MONS)[0]


_MONS = PM.monsters()


def reach(sc, cfg, L, info, cls=None):
    """the deepest floor a player of level L (class cls, else the median class) gets to while every floor up to it takes at
    most reachRatio times the base hunt pack of level L (a boss: reachBoss seconds, helpers excluded)"""
    lim = cfg['limits']
    hunt = hunt_clear(L)
    for f in range(1, int(cfg['maxFloor']) + 1):
        t, pack, boss = floor_time(sc, cfg, f, [(cls, L)], info)
        if is_boss(sc, f):
            if boss > lim['reachBoss']:
                return f - 1
        elif pack > lim['reachRatio'] * hunt:
            return f - 1
    return int(cfg['maxFloor'])


def legendary_alone(sc, cfg, f, L, info, cls=None):
    """seconds one legendary monster of floor f (the tier's health, the average modifiers) lives for one player of level L"""
    hp, cnt, mod = info
    return sc['hp'](f) * hp['legendary'] * mod ** cnt['legendary'] / player_dps(cls, L, 1)[1]


# ------------------------------------------------------------------------------------------------ derive
# the `damage` line of O144 / O285 (the pace curve at the band's hunting level only): --damage prints it against the new one
LEGACY_DAMAGE = [(1, 1.0), (12, 1.0), (20, 0.86), (28, 0.83), (36, 0.79), (44, 0.76), (52, 0.8), (120, 0.86)]
SMOOTH_WINDOW = 5  # --derive: lootShare and killGold are the least of the floors within this many floors (the sawtooth)

MIN_STEP = 1.005  # --derive: the least rise of a point over the one before
DERIVE_FLOORS = (1, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 50, 60, 70, 80, 90, 100, 110, 120)


def sig(x, n=3):
    if x == 0:
        return 0
    return round(x, -int(math.floor(math.log10(abs(x)))) + (n - 1))


def derive(cfg, info):
    sc = new_scheme(cfg)
    raw = []
    for f in range(1, int(cfg['maxFloor']) + 1):
        L = lin(cfg['level'], f)
        P = sc['count'](f)
        e = tier_factor(sc['mix'](f), info)
        dps = player_dps(None, L, P)[0] * cfg['packUptime']
        raw.append(lin(cfg['clear'], f) * dps / (P * e))
    # a floor's health is smooth: the mean of the floors around it, never lower than the one before
    smooth, best = [], 0.0
    for i in range(len(raw)):
        w = raw[max(0, i - 3):i + 4]
        best = max(best, sum(w) / len(w))
        smooth.append(best)
    pts = []
    for f in DERIVE_FLOORS:
        v = sig(smooth[f - 1])
        if pts and v < pts[-1][1] * MIN_STEP:  # strictly rising: every floor is stronger than the one before (O172)
            v = sig(pts[-1][1] * MIN_STEP)
        pts.append((f, v))
    health = '\thealth = {%s},' % ', '.join('{%d, %s}' % (f, ('%d' % v)) for f, v in pts)
    out = []
    boss_prev = 0
    for k in range(1, int(cfg['maxFloor'] // cfg['bossEvery']) + 1):
        f = k * int(cfg['bossEvery'])
        L = lin(cfg['level'], f)
        d1 = player_dps(None, L, 1)[1] * cfg['bossUptime']
        heal = cfg['bosses'][(k - 1) % len(cfg['bosses'])][1]
        v = sig(lin(cfg['bossSeconds'], f) * (d1 - heal))
        if boss_prev and v < boss_prev * MIN_STEP:  # a later boss floor never has less health than an earlier one (O172)
            v = sig(boss_prev * MIN_STEP)
        boss_prev = v
        out.append('[%d] = %d' % (f, v))
    dmg = [(f, sig(dmg_target(cfg, f))) for f in damage_floors(cfg)]
    share, gold = loot_curves(cfg, info)
    return (health, '\tbossHealth = {%s},' % ', '.join(out),
            '\tdamage = {%s},' % ', '.join('{%d, %g}' % d for d in dmg),
            '\tlootShare = {%s},' % ', '.join('{%d, %g}' % d for d in share),
            '\tkillGold = {%s},' % ', '.join('{%d, %g}' % d for d in gold))


# ------------------------------------------------------------------------------------------------ O328: damage and loot
def band_floors(cfg):
    """[(first floor, last floor)] of every pool band; the last one runs to maxFloor"""
    n, w = len(cfg['pools']), int(cfg['bandFloors'])
    return [(max(1, b * w), (b + 1) * w - 1 if b < n - 1 else int(cfg['maxFloor'])) for b in range(n)]


def damage_floors(cfg):
    """the floors of the `damage` curve: both edges of every band (the species change there) and every fourth floor"""
    fl = set(range(1, int(cfg['maxFloor']) + 1, 4)) | {int(cfg['maxFloor'])}
    for a, z in band_floors(cfg):
        fl |= {a, z}
    return sorted(fl)


def band_level(cfg, f):
    """the hunting level of the species of floor f's band (the median of the bounty pool levels)"""
    return _pool_level(tuple(cfg['pools'][min(len(cfg['pools']), int(f // cfg['bandFloors']) + 1) - 1]))


def dmg_target(cfg, f):
    """the damage factor a monster shown at the level of floor f needs to hit like a hunt monster of that level (O328): the pace
    damage curve at the shown level L x hit(L) / hit(the band's hunting level), the stock hit of its species"""
    L = lin(cfg['level'], f)
    return lin(_PACE_DAMAGE(), L) * lin(cfg['hit'], L) / lin(cfg['hit'], band_level(cfg, f))


def damage_table(cfg, floors=(1, 8, 20, 30, 40, 48, 60, 80, 120), extra_levels=(100, 500, 1200, 2000)):
    """damage before (O285) and after (O328) at some floors, and at the floors that show the levels of extra_levels. The hit is
    the maximum of an attack of the band's species at its hunting level times the factor (hit(band level) x factor)"""
    rows = ['| Floor | Shown level | Band level | Factor before | Factor after | Hit before | Hit after |', '|---|---|---|---|---|---|---|']
    fl = list(floors)
    for L in extra_levels:
        f = next((x for x in range(1, int(cfg['maxFloor']) + 1) if lin(cfg['level'], x) >= L), int(cfg['maxFloor']))
        if f not in fl:
            fl.append(f)
    for f in sorted(fl):
        l = band_level(cfg, f)
        h = lin(cfg['hit'], l)
        old, new = lin(LEGACY_DAMAGE, f), dmg_at(cfg, f)
        rows.append('| %d | %d | %d | %.2f | %.2f | %d | %d |' % (f, round(lin(cfg['level'], f)), l, old, new, h * old, h * new))
    return '\n'.join(rows)


def loot_level(cfg, f):
    """B.lootLevel: the shown level, never above the level of maxFloor"""
    return min(lin(cfg['level'], f), lin(cfg['level'], cfg['maxFloor']))


@functools.lru_cache(maxsize=None)
def _gold_per_hour():
    m = re.search(r'goldPerHour = \{(.*?)\}', read(PACE), re.S)
    return sorted((float(a), float(b)) for a, b in re.findall(r'\[(\d+)\] = (\d+)', m.group(1)))


def gold_per_hour(L):
    """the gold an hour a hunt at level L is held to (pace_config.lua lootLevel.goldPerHour, flat above its last band)"""
    return lin(_gold_per_hour(), L)


@functools.lru_cache(maxsize=None)
def _gap_seconds():
    """the pause between two floors (infinitytower_run.lua nextFloorDelay)"""
    return float(re.search(r'nextFloorDelay = (\d+)', read(RUN)).group(1))


def tower_kills(cfg, info, f):
    """kills an hour of the median class at the level of floor f, run after run floor after floor (a boss floor counts its
    helpers and the boss): 3600 x monsters / (seconds of the floor + the pause before the next)"""
    sc = new_scheme(cfg)
    L = lin(cfg['level'], f)
    total = floor_time(sc, cfg, f, [(None, L)], info)[0]
    n = sc['count'](f)
    n = n // sc['divisor'] + 1 if is_boss(sc, f) else n
    return 3600.0 * n / (total + _gap_seconds())


def hunt_kills(L):
    """kills an hour of the median class in a base hunt pack at level L (the late sets from 670)"""
    return PM.pack_clear(L, L >= 670, _PACE, _MONS)[2]


def _smooth_min(cfg, raw):
    """raw = {floor: value} for the normal floors: the least value within SMOOTH_WINDOW floors, for every floor 1..maxFloor"""
    out = {}
    for f in range(1, int(cfg['maxFloor']) + 1):
        near = [raw[g] for g in range(f - SMOOTH_WINDOW, f + SMOOTH_WINDOW + 1) if g in raw]
        out[f] = min(near)
    return out


def loot_curves(cfg, info):
    """(lootShare points, killGold points) at DERIVE_FLOORS. lootShare: the share of the hunt's loot per kill that keeps the items
    an hour of the tower at those of a hunt of the floor's level (at most 1). killGold: goldShare x the hunt's gold an hour over
    the tower's kills an hour (2 significant digits, rounded down)"""
    share, gold = {}, {}
    for f in range(1, int(cfg['maxFloor']) + 1):
        if f % int(cfg['bossEvery']) == 0:
            continue
        k = tower_kills(cfg, info, f)
        Ll = loot_level(cfg, f)
        share[f] = min(1.0, hunt_kills(Ll) / k)
        gold[f] = cfg['goldShare'] * gold_per_hour(Ll) / k
    sm, gm = _smooth_min(cfg, share), _smooth_min(cfg, gold)
    return ([(f, math.floor(sm[f] * 100) / 100.0) for f in DERIVE_FLOORS],
            [(f, math.floor(gm[f] / 10 ** max(0, int(math.floor(math.log10(gm[f]))) - 1)) * 10 ** max(0, int(math.floor(math.log10(gm[f]))) - 1))
             for f in DERIVE_FLOORS])


# ------------------------------------------------------------------------------------------------ the tables
def table(sc, cfg, info, levels, floors):
    rows = ['| Floor | Count | Hunt pack | ' + ' | '.join('L%d' % L for L in levels) + ' |',
            '|---|---|---|' + '---|' * len(levels)]
    for f in floors:
        hunts = ['%.1f' % hunt_clear(L) for L in (lin(cfg['level'], f),)]
        cells = []
        for L in levels:
            t, pack, boss = floor_time(sc, cfg, f, [(None, L)], info)
            cells.append('%s' % ('never' if math.isinf(t) else '%.0f s' % t) if not is_boss(sc, f) else
                         ('never' if math.isinf(t) else '%.0f s (boss %.0f)' % (t, boss)))
        rows.append('| %d%s | %d | %s s at L%d | %s |' % (f, ' B' if is_boss(sc, f) else '', sc['count'](f), hunts[0],
                                                          lin(cfg['level'], f), ' | '.join(cells)))
    return '\n'.join(rows)


def check(cfg, info, out=print):
    sc = new_scheme(cfg)
    lim = cfg['limits']
    bad = []
    rows = ['| Floor | Level | Count | Floor (median class) | Hunt pack | Ratio | Boss | Damage x |', '|---|---|---|---|---|---|---|---|']
    prev = None
    for f in range(1, int(cfg['maxFloor']) + 1):
        L = lin(cfg['level'], f)
        t, pack, boss = floor_time(sc, cfg, f, [(None, L)], info)
        hunt = hunt_clear(L)
        ratio = pack / hunt if not is_boss(sc, f) else None
        if not is_boss(sc, f):
            if not (lim['clearMin'] <= pack <= lim['clearMax']):
                bad.append('floor %d: %.1f s outside %g-%g' % (f, pack, lim['clearMin'], lim['clearMax']))
            if not (lim['huntMin'] <= ratio <= lim['huntMax']):
                bad.append('floor %d: %.2f x the hunt pack outside %g-%g' % (f, ratio, lim['huntMin'], lim['huntMax']))
            if prev is not None and f % int(cfg['milestoneEvery']) != 1 and pack > prev * lim['stepMax']:
                bad.append('floor %d: %.1f s is more than %g x the floor before (%.1f s)' % (f, pack, lim['stepMax'], prev))
            if f % int(cfg['milestoneEvery']) == 1 and prev is not None and pack > prev * lim['breather']:
                bad.append('floor %d: %.1f s is not a breather after %.1f s' % (f, pack, prev))
            prev = pack
        else:
            if not (lim['bossMin'] <= boss <= lim['bossMax']):
                bad.append('floor %d: boss %.0f s outside %g-%g' % (f, boss, lim['bossMin'], lim['bossMax']))
            bh, heal = sc['boss'](f)
            d1 = player_dps(None, L, 1)[1] * cfg['bossUptime']
            if heal > lim['bossHeal'] * d1:
                bad.append('floor %d: boss heals %d a second, %.0f%% of %.0f' % (f, heal, 100.0 * heal / d1, d1))
            wb = floor_time(sc, cfg, f, [(min(PM.C4, key=lambda c: class_dps(c, L, 1)[1]), L)], info)[2]
            if wb > lim['weakBoss']:
                bad.append('floor %d: the weakest class needs %.0f s for the boss (limit %g)' % (f, wb, lim['weakBoss']))
        rows.append('| %d | %d | %d | %s | %.1f s | %s | %s | %.2f |' % (
            f, L, sc['count'](f), '%.1f s' % pack, hunt, '%.2f' % ratio if ratio else '-',
            '%.0f s' % boss if boss else '-', sc['dmg'](f)))
        slow = floor_time(sc, cfg, f, [(None, L * lim['underLevel'])], info)
        if (not is_boss(sc, f) and slow[1] > lim['underMax']) or math.isinf(slow[0]):
            bad.append('floor %d: %.0f s at %d%% of the floor level (limit %g)' % (f, slow[0], 100 * lim['underLevel'], lim['underMax']))
    bad += endless(cfg, info)
    reachL = int(lim['reachLevel'])
    r = reach(sc, cfg, reachL, info)
    weak = reach(sc, cfg, reachL, info, cls=ranked(reachL, 7)[0])
    if not (lim['reachMin'] <= r <= lim['reachMax']):
        bad.append('median class at level %d gets to floor %d, wanted %g-%g' % (reachL, r, lim['reachMin'], lim['reachMax']))
    if weak < lim['weakReach']:
        bad.append('the weakest class at level %d gets to floor %d, wanted at least %g' % (reachL, weak, lim['weakReach']))
    levels = (100, 300, 500, 800, 1000, 1500, 2000)
    reaches = [(L, reach(sc, cfg, L, info)) for L in levels]
    if any(b2 <= a2 for (_, a2), (_, b2) in zip(reaches, reaches[1:])):
        bad.append('a higher level does not get deeper: %s' % reaches)
    for f in range(1, 31):
        if is_boss(sc, f):
            continue
        t2 = floor_time(sc, cfg, f, [(None, 500), (None, 800)], info)[1]
        if t2 > lim['pairMax']:
            bad.append('floor %d: a pair of levels 500 and 800 needs %.0f s (limit %g)' % (f, t2, lim['pairMax']))
    for f in range(1, int(cfg['maxFloor']) + 1):
        L = lin(cfg['level'], f)
        s = legendary_alone(sc, cfg, f, L, info)
        if s > lim['singleMax']:
            bad.append('floor %d: a legendary monster lives %.0f s for the median class at level %d (limit %g)' % (f, s, L, lim['singleMax']))
    # O328: the damage of every floor against what a hunt monster of the shown level deals (pace curve x hit(L) / hit(band))
    for f in range(1, int(cfg['maxFloor']) + 1):
        want = dmg_target(cfg, f)
        got = lin(cfg['damage'], f)  # the hunt match; the climb comes on top (dmg_at)
        if abs(got - want) > lim['damageTol'] * want:
            bad.append('damage at floor %d is %.2f, the pace curve x hit at level %d over the band level %d is %.2f' % (
                f, got, int(round(lin(cfg['level'], f))), band_level(cfg, f), want))
    # O328: the items and the gold an hour of the tower against a hunt of the floor's level
    for f in range(1, int(cfg['maxFloor']) + 1):
        if f % int(cfg['bossEvery']) == 0:
            continue
        k, Ll = tower_kills(cfg, info, f), loot_level(cfg, f)
        items = lin(cfg['lootShare'], f) * k / hunt_kills(Ll)
        if items > lim['lootRatio']:
            bad.append('floor %d: the tower gives %.2f x the items an hour of a hunt at level %d (limit %g)' % (f, items, int(Ll), lim['lootRatio']))
        gold = lin(cfg['killGold'], f) * k / (cfg['goldShare'] * gold_per_hour(Ll))
        if gold > lim['goldRatio']:
            bad.append('floor %d: the tower gives %.2f x its share of the gold an hour at level %d (limit %g)' % (f, gold, int(Ll), lim['goldRatio']))
    if '--quiet' not in sys.argv:
        out('\n'.join(rows))
        out('')
        endless(cfg, info, out=out)
        out('')
        out('reach (every floor within %g x the hunt pack of the player\'s level), median class: %s; weakest class at %d: floor %d' % (
            lim['reachRatio'], ', '.join('L%d floor %d' % x for x in reaches), reachL, weak))
    for b in bad:
        out('FAIL ' + b)
    out('tower check: %s' % ('FAIL (%d)' % len(bad) if bad else 'ok'))
    return 1 if bad else 0


def endless(cfg, info, floors=None, out=None):
    """the checks of O172 (the tower never stops getting stronger), floors 1..N (limits.endless, 1000):
    - the health trend (before the sawtooth), the level and the damage factor (from the first floor of the last pool band: the
      species change before it and the factor restarts, O328) rise strictly, boss floor to boss floor the boss health and (above maxFloor) the
      boss damage too;
    - the health of a floor is above the floor a climb (milestoneEvery) before it and only the breather is easier than
      the floor before it (the sawtooth stays); above maxFloor no climb starts more than stepMax over the one before;
    - no value is above its cap or not finite; the caps start past limits.capMin; the health cap leaves room for the
      legendary tier and every cap is under the engine's int32;
    - the clear time of the median class at the floor's own level climbs steadily above maxFloor (a soft wall, no cliff).
    Returns the failures; out(line) gets the table of selected floors"""
    lim, b = cfg['limits'], cfg['beyond']
    top = int(floors or lim['endless'])
    m, bad = int(cfg['milestoneEvery']), []
    start, be = int(cfg['maxFloor']), int(cfg['bossEvery'])
    low = band_floors(cfg)[-1][0]  # the last band's first floor: the species change before it, the damage factor restarts
    caps = {'health': b['healthMax'], 'boss health': b['bossHealthMax'], 'damage': b['damageMax'], 'level': b['levelMax']}
    for f in range(1, top + 1):
        if f > 1:
            if trend_hp(cfg, f) <= trend_hp(cfg, f - 1) and hp_at(cfg, f) < b['healthMax']:
                bad.append('floor %d: the health trend does not rise (%.0f)' % (f, trend_hp(cfg, f)))
            if int(round(level_at(cfg, f))) <= int(round(level_at(cfg, f - 1))):
                bad.append('floor %d: the level does not rise' % f)
            if f > low and dmg_at(cfg, f) <= dmg_at(cfg, f - 1) and dmg_at(cfg, f) < b['damageMax']:
                bad.append('floor %d: the damage factor does not rise (%.3f)' % (f, dmg_at(cfg, f)))
        if f > m and hp_at(cfg, f) <= hp_at(cfg, f - m) and hp_at(cfg, f) < b['healthMax']:
            bad.append('floor %d: no more health than floor %d' % (f, f - m))
        if f > m and f % m != 1 and hp_at(cfg, f) < hp_at(cfg, f - 1):
            bad.append('floor %d: less health than floor %d (only the breather may be easier)' % (f, f - 1))
        if f > start and f % m == 1 and hp_at(cfg, f) > hp_at(cfg, f - 1) * lim['stepMax']:
            bad.append('floor %d: a cliff, %.2f x the floor before' % (f, hp_at(cfg, f) / hp_at(cfg, f - 1)))
        if f % be == 0 and f > be:
            if boss_hp_at(cfg, f) <= boss_hp_at(cfg, f - be) and boss_hp_at(cfg, f) < b['bossHealthMax']:
                bad.append('boss floor %d: no more health than floor %d' % (f, f - be))
            if f > start and boss_dmg_at(cfg, f) <= boss_dmg_at(cfg, f - be) and boss_dmg_at(cfg, f) < b['damageMax']:
                bad.append('boss floor %d: the boss damage does not rise' % f)
        for name, v in (('health', hp_at(cfg, f)), ('boss health', boss_hp_at(cfg, f)), ('damage', dmg_at(cfg, f)),
                        ('level', level_at(cfg, f))):
            if not (v == v and abs(v) != float('inf')) or v > caps[name] or v < 0:
                bad.append('floor %d: %s %r is not finite or above its cap' % (f, name, v))
    if b['healthMax'] * max(cfg['tierHealth'].values()) > b['engineMaxHealth'] or b['engineMaxHealth'] > 2 ** 31 - 1:
        bad.append('the health cap x the legendary tier is above the engine limit')
    if b['bossHealthMax'] > b['engineMaxHealth'] or b['levelMax'] > 2 ** 31 - 1:
        bad.append('a boss health or level cap is above the engine limit')
    starts = {'health': growth_floor(cfg, b['healthRate'], b['healthAccel'],
                                     b['healthMax'] / (lin(cfg['health'], start) * max(cfg['sawtooth']))),
              'boss health': growth_floor(cfg, b['bossHealthRate'], b['bossHealthAccel'],
                                          b['bossHealthMax'] / cfg['bossHealth'][max(cfg['bossHealth'])]),
              'damage': dmg_cap_floor(cfg)}
    for name, f in starts.items():
        if f <= lim['capMin']:
            bad.append('the %s cap starts at floor %d, wanted past %g' % (name, f, lim['capMin']))
    # the soft wall: seconds the median class needs for a milestone floor at the floor's own level
    prev, times = None, {}
    for f in range(start, top + 1, m):
        L = level_at(cfg, f)
        n = int(cfg['count'][-1][1])
        mix = tuple(lin(cfg[k], f) / 100.0 for k in ('magic', 'rare', 'legendary'))
        t = trend_hp(cfg, f) * cfg['sawtooth'][-1] * tier_factor(mix, info) * n / (player_dps(None, L, n)[0] * cfg['packUptime'])
        if f > start and hp_at(cfg, f) < b['healthMax']:
            if t <= prev:
                bad.append('floor %d: the clear time at its own level does not climb (%.1f s after %.1f s)' % (f, t, prev))
            if t > prev * lim['stepMax']:
                bad.append('floor %d: the clear time jumps %.2f x over the milestone before' % (f, t / prev))
        prev = t
        times[f] = t
    if out:
        rows = ['| Floor | Level | Monster health | Boss health | Damage x | Boss damage x | Clear at own level |',
                '|---|---|---|---|---|---|---|']
        for f in (1, 10, 50, 120, 130, 200, 300, 500, 750, 1000):
            if f > top:
                continue
            rows.append('| %d | %d | %d | %d | %.2f | %.2f | %s |' % (
                f, int(round(level_at(cfg, f))), hp_at(cfg, f), boss_hp_at(cfg, f // be * be or be), dmg_at(cfg, f),
                boss_dmg_at(cfg, f), '%.1f s' % times[f] if f in times else '-'))
        out('\n'.join(rows))
        out('caps: normal monster health %d from floor %d, boss health %d from floor %d, damage factor %g from floor %d (floors 1-%d checked)' % (
            b['healthMax'], starts['health'], b['bossHealthMax'], starts['boss health'], b['damageMax'], starts['damage'], top))
    return bad


@functools.lru_cache(maxsize=None)
def _pace_damage():
    m = re.search(r'\n\tdamage = \{((?:\{[0-9.]+, [0-9.]+\},?\s*)+)\}', read(PACE))
    return tuple((float(a), float(b)) for a, b in re.findall(r'\{([0-9.]+), ([0-9.]+)\}', m.group(1)))


def _PACE_DAMAGE():
    return list(_pace_damage())


@functools.lru_cache(maxsize=None)
def _pool_level(names):
    """the median hunting level (the bounty pool's estimate, baseLevelMult 1 since O285) of a band's species"""
    names = tuple(names)
    pool = dict((n.lower(), int(l)) for n, l in re.findall(r'\{name = "([^"]+)", level = (\d+),',
                                                          read(POOL).split('\tbosses = ')[0]))
    lv = sorted(pool[n] for n in names if n in pool and n != 'demon')
    return lv[len(lv) // 2]


def main(argv):
    cfg = balance()
    info = tier_info(cfg if '--before' not in argv else None)
    if '--derive' in argv:
        for line in derive(cfg, info):
            print(line)
        return 0
    if '--damage' in argv:
        print(damage_table(cfg))
        return 0
    if '--check' in argv:
        return check(cfg, info)
    levels = [int(x) for x in argv[argv.index('--levels') + 1].split(',')] if '--levels' in argv else [100, 300, 500, 800, 1000]
    floors = [int(x) for x in argv[argv.index('--floors') + 1].split(',')] if '--floors' in argv else \
        [1, 5, 10, 15, 20, 25, 30, 35, 40, 50, 60, 80, 100, 120]
    sc = legacy_scheme() if '--before' in argv else new_scheme(cfg)
    print(table(sc, cfg, info, levels, floors))
    print('')
    print('reach (floors within %g x the hunt pack of the player level), median class: ' % cfg['limits']['reachRatio'] + ', '.join(
        'L%d floor %d' % (L, reach(sc, cfg, L, info)) for L in (100, 300, 500, 800, 1000, 1500, 2000)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
