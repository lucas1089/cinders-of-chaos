#!/usr/bin/env python3
"""The pack model: experience per hour of every class in packs, against the median class at the same level (computed,
not measured; server/README.md "Pack combat (pace)", data/spells/README.md "Pack farming for every class").

usage: python3 -I server/tools/pack_model.py [--levels 300,800,1000] [--no-cleave] [--no-kit] [--rounded] [--top] [--median] [--check]

Without a flag the table is against the reference: the median class before the class identity pass (2026-10-28; BASE_CLEAVE,
the C4 and KIT numbers without TUNE), the yardstick of the pack bands; --median against the median class of today.

--check (CI, class identity pass): every class's kills per hour in packs against the reference stays inside its `packLimits` row of
boss_balance_config.lua at every level of `levels` (the windows at 800 and 1200 widen it), and no class has more than 1 / (1 +
lead) of the Elementalist's damage on a pack of 5 (with the cleave). Also (CI, O138): the pack of the median class in the level-scaled late sets (hunting level 670 and up) dies in at most
LATE_MAX (3.0) times the time of a base hunt's pack at the same level (at most level 1000); prints the table. O285: the
hunting level of a base monster is its pool level, so no base monster is above 657; above it the base pack is the top
monsters' with their health grown with the level (median_health).

Prints experience per hour against the median class; --top prints each class's kills per hour (experience per kill is
the same for every class, so this is its experience per hour up to one factor) and its share of the top class's.

Inputs (everything in the repo):
  C4             the damage of every class measured in game (data/spells/README.md "Classes with the passive trees":
                 1 target / 5 targets per second at level 300 and 1000, linear in between)
  KIT            what the class kits gained after the C4 measurement, added to it (computed: rotation_sim.py's change
                 of the class's spell damage x the class's measured spell-to-total factor; data/spells/README.md
                 "Pack farming for every class" has the method); --no-kit leaves it out
  pace_config    the health curves (base hunts and the level-scaled late sets), the multikill steps and the pack
                 cleave by vocation (`cleave.byVocation`); --no-cleave leaves the cleave out
  bounty_pool    the hunting monsters and their spawns (the median health at a level, x1.11 for the tiers); the
                 level-scaled late sets use the health of server/README.md "Pack combat (pace)"

The model, per class and level: a lure gathers a pack of P = band pack - 2 + 4 x min(1, area share / 0.6), at most 8
(area share = (5 targets - 1 target) / 5 targets, after the cleave); the pack dies in
clear = P x health / (1 target + (P - 1) x (5 targets - 1 target) / 4); W seconds of walking and luring per pack;
kills/h = 3600 P / (clear + W), x (1 + the multikill bonus of a chain of P). The cleave adds percent x min(targets, 4)
(the percent at the level: `percent` up to 300, linear to `high` at 1000) of every hit on the pack (area hits cleave too): 5 targets x (1 + percent x min(targets, 4)). P is not rounded and the
multikill bonus is linear between its steps (pulls vary); --rounded rounds P and takes the bonus of its step (the first
model, 2026-10-14). Experience per kill is the same for every class, so experience per hour against the median class
is kills/h against the median class's.
"""
import os, re, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.normpath(os.path.join(HERE, '..'))
PACE = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'pace_config.lua')
POOL = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'bounty_pool.lua')
CHAOS_MONSTERS = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos')

# class: (300 1 target, 300 5 targets, 1000 1 target, 1000 5 targets), measured (C4, 2026-10-11)
C4 = {
    'Warrior': (886, 2127, 2351, 6280), 'Juggernaut': (781, 1623, 2569, 4424), 'Berserker': (974, 2932, 2634, 8218),
    'Ranger': (1075, 1409, 3673, 5305), 'Deadeye': (1312, 1446, 4571, 5385), 'Beastmaster': (832, 1919, 3267, 9255),
    'Mystic': (803, 2692, 2439, 8354), 'Elementalist': (913, 3442, 2954, 11004), 'Illusionist': (765, 1747, 2014, 5239),
    'Thief': (870, 870, 2391, 2297), 'Ninja': (1121, 1424, 3565, 5101), 'Samurai': (751, 770, 2025, 2018),
    'Necromancer': (1009, 1069, 2598, 2622), 'Lich': (1164, 2057, 4037, 7696), 'Bone Lord': (1158, 2326, 4104, 7883),
    'Monk': (955, 1122, 2326, 2794), 'Shadowfist': (1181, 1262, 3683, 3948), 'Iron Sage': (796, 829, 1992, 2399),
    'Templar': (904, 1422, 2103, 3375), 'Inquisitor': (1086, 2056, 3556, 6192), 'Sentinel': (743, 1285, 1948, 3429)}
# kit changes since C4 (2026-10-15: Blade Flurry, Iaido Sweep and the pack tools of _packtools.lua), same order as C4:
# rotation_sim.py's change of the class's best rotation x the class's spell-to-total factor (data/spells/README.md
# "Pack farming for every class"); computed, not measured
KIT = {'Thief': (0, 1028, 0, 3977), 'Ninja': (7, 503, 35, 2520), 'Samurai': (-1, 774, -23, 3017),
       'Monk': (0, 1034, 0, 3183), 'Shadowfist': (0, 505, 0, 1834), 'Iron Sage': (25, 983, 72, 3161),
       'Necromancer': (0, 1425, 0, 3111), 'Templar': (0, 982, 0, 2070), 'Sentinel': (0, 822, 0, 1929)}
VOC = {'Mystic': 1, 'Ranger': 3, 'Warrior': 4, 'Elementalist': 5, 'Deadeye': 7, 'Juggernaut': 8, 'Illusionist': 10,
       'Thief': 11, 'Ninja': 12, 'Samurai': 13, 'Berserker': 14, 'Beastmaster': 15, 'Monk': 17, 'Shadowfist': 18,
       'Iron Sage': 19, 'Necromancer': 20, 'Lich': 21, 'Bone Lord': 22, 'Templar': 23, 'Inquisitor': 24,
       'Sentinel': 25}
# player band: (low, high, pack, walk and lure s per pack)
PACK = [(1, 50, 5, 7), (50, 150, 6, 8), (150, 300, 6, 9), (300, 600, 6, 10), (600, 1000, 7, 12), (1000, 10 ** 9, 7, 13)]
PCAP = 8
TIER_HEALTH = 1.11
# the level-scaled late sets: health at their level (server/README.md "Pack combat (pace)")
SCALED_HEALTH = [(670, 88600), (800, 130000), (980, 200000), (1300, 324000), (2000, 593000)]
ABOVE_1000 = 2.41  # damage per level above 1000 (README "Solo kill times")

# ---- the class identity pass (2026-10-28): what changed after C4 + KIT, read from the configs ---------------------------
# class: (class key, line key) of chaos_constants.lua Chaos.classes (class_tree.lua damageFactor looks the class up first,
# then its line)
KEYS = {'Warrior': ('warrior', 'warrior'), 'Juggernaut': ('juggernaut', 'warrior'), 'Berserker': ('berserker', 'warrior'),
        'Ranger': ('ranger', 'ranger'), 'Deadeye': ('deadeye', 'ranger'), 'Beastmaster': ('beastmaster', 'ranger'),
        'Mystic': ('mystic', 'mystic'), 'Elementalist': ('elementalist', 'mystic'), 'Illusionist': ('illusionist', 'mystic'),
        'Thief': ('thief', 'thief'), 'Ninja': ('ninja', 'thief'), 'Samurai': ('samurai', 'thief'),
        'Necromancer': ('necromancer', 'necromancer'), 'Lich': ('lich', 'necromancer'),
        'Bone Lord': ('bonelord', 'necromancer'), 'Monk': ('monk', 'monk'), 'Shadowfist': ('shadowfist', 'monk'),
        'Iron Sage': ('ironsage', 'monk'), 'Templar': ('templar', 'templar'), 'Inquisitor': ('inquisitor', 'templar'),
        'Sentinel': ('sentinel', 'templar')}
CLASS_TREE = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'class_tree.lua')
PACKTOOLS = os.path.join(SERVER, 'data', 'spells', 'chaos', '_packtools.lua')
BLADES = os.path.join(SERVER, 'data', 'spells', 'chaos', '_blades.lua')
# the class damage factor (class_tree.lua classDamage: all damage of the class, points {level, factor}) of every class before
# the identity pass, i.e. the state of pack_model's C4 + KIT numbers; the model multiplies them by now / then at the level
DAMAGE_BASE = {'Warrior': [(300, 1.0), (1000, 1.0)], 'Juggernaut': [(300, 1.0), (1000, 1.0)],
               'Berserker': [(300, 0.78), (1000, 1.0)], 'Ranger': [(300, 1.0), (1000, 0.95)],
               'Deadeye': [(300, 1.0), (1000, 0.95)], 'Beastmaster': [(300, 1.0), (1000, 0.95)],
               'Mystic': [(300, 1.0), (1000, 1.0)], 'Elementalist': [(300, 1.0), (1000, 1.0)],
               'Illusionist': [(300, 1.0), (1000, 1.0)], 'Thief': [(300, 0.48), (1000, 0.53)],
               'Ninja': [(300, 0.45), (1000, 0.57)], 'Samurai': [(300, 0.30), (1000, 0.37)],
               'Necromancer': [(300, 0.93), (1000, 0.64)], 'Lich': [(300, 0.50), (1000, 0.57)],
               'Bone Lord': [(300, 0.63), (1000, 0.61)], 'Monk': [(300, 0.63), (1000, 0.75)],
               'Shadowfist': [(300, 0.49), (1000, 0.69)], 'Iron Sage': [(300, 0.61), (1000, 0.75)],
               'Templar': [(300, 0.78), (1000, 0.60)], 'Inquisitor': [(300, 0.65), (1000, 0.58)],
               'Sentinel': [(300, 0.73), (1000, 0.60)]}
# the pack tools' `pack` multiples before the pass (_packtools.lua, _blades.lua sweep); a class's tools scale the area gain
# its KIT row holds, each by its weight (the share of that gain the tool holds: rotation_sim.py, the best set's 5-target damage
# with the tool's t5 at 1 against full: Samurai Iaido Sweep 0.74-0.77, Thief Fan of Knives 0.62-0.78, the rest is Blade Flurry
# and the other area spells); tool scale = 1 - weight x (1 - now / then), the mean over the class's tools
TOOLS = {'Thief': ('fan',), 'Samurai': ('sweep',), 'Monk': ('shockwave',), 'Shadowfist': ('shockwave', 'ricochet'),
         'Iron Sage': ('shockwave', 'chain'), 'Necromancer': ('shrapnel',), 'Templar': ('sanctified',),
         'Sentinel': ('shieldWave',)}
TOOL_WEIGHT = {'fan': 0.7, 'sweep': 0.75}  # a tool not listed: 1
TOOL_LEVEL = {'fan': 80, 'sweep': 200}  # the level a tool is learned at (spells_chaos.xml); its scale counts from there
TOOLS_BASE = {'fan': 1.0, 'sweep': 1.5, 'shockwave': 2.0, 'ricochet': 2.5, 'chain': 2.0, 'shrapnel': 2.5,
              'sanctified': 2.5, 'shieldWave': 2.0}


def class_damage(text=None):
    """{class key: [(level, factor), ...]} of class_tree.lua classDamage"""
    text = text if text is not None else open(CLASS_TREE, encoding='utf-8').read()
    block = text.split('M.classDamage = {', 1)[1].split('\n}', 1)[0]
    return {k: [(int(a), float(b)) for a, b in re.findall(r'\{(\d+), ([0-9.]+)\}', v)]
            for k, v in re.findall(r'(\w+) = \{(\{[^=]*?\})\}', block)}


def tool_packs():
    """{tool: pack multiple now} from _packtools.lua and _blades.lua"""
    out = {}
    for path, keys in ((PACKTOOLS, [k for k in TOOLS_BASE if k != 'sweep']), (BLADES, ['sweep'])):
        text = open(path, encoding='utf-8').read()
        for k in keys:
            m = re.search(r'\n\t(?:--[^\n]*\n\t)*' + k + r' = \{(.*?)\n\t\},', text, re.S)
            out[k] = float(re.search(r'\bpack = ([0-9.]+)', m.group(1)).group(1))
    return out


_TUNING = {}


def tuning(cls, L):
    """(damage factor change at level L, area-tool change) of a class since C4 + KIT: classDamage now over then (class_tree.lua
    damageFactor: linear between its points, flat outside), and its pack tools' scale (TOOL_WEIGHT; 1 for a class with none). Both are multiplied into the class's numbers (damage())."""
    if not _TUNING:
        now, packs = class_damage(), tool_packs()
        for c, (ck, lk) in KEYS.items():
            f = now.get(ck) or now.get(lk) or [(300, 1.0), (1000, 1.0)]
            _TUNING[c] = (f, DAMAGE_BASE[c], {k: 1 - TOOL_WEIGHT.get(k, 1.0) * (1 - packs[k] / TOOLS_BASE[k])
                                              for k in TOOLS.get(c, ())})
    f, b, tools = _TUNING[cls]
    here = [t for k, t in tools.items() if L >= TOOL_LEVEL.get(k, 0)]
    return lin(f, L) / lin(b, L), (sum(here) / len(tools) + (len(tools) - len(here)) / len(tools) if tools else 1.0)

LATE_MAX = 3.0  # --check: late pack clear time / base pack clear time, at most (O138: 2.0-2.5 today, was 4-11)
LATE_LEVELS = (670, 800, 1000, 1300, 1600, 2000)
# the pack cleave of pace_config.lua before the identity pass {vocation id: (percent, targets, high)} (the reference)
BASE_CLEAVE = {4: (6, 4, 11), 8: (15, 4, 26), 14: (0, 4, 3), 3: (23, 4, 20), 7: (28, 4, 21), 15: (9, 4, 0), 1: (0, 4, 2),
               10: (12, 4, 17), 11: (10, 4, 11), 12: (12, 4, 6), 13: (17, 4, 19), 20: (2, 4, 14), 21: (10, 4, 7),
               22: (6, 4, 6), 17: (6, 4, 12), 18: (16, 4, 16), 19: (11, 4, 15), 23: (3, 4, 16), 24: (8, 4, 13),
               25: (6, 4, 16)}
CLEAVE_FROM, CLEAVE_TO = 300, 1000  # a cleave's `percent` up to level 300, linear to its `high` at 1000 (pace_config)


def lin(points, x):
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / float(x1 - x0)
    return points[-1][1]


# ------------------------------------------------------------------------------------------------ pace_config.lua
def pace(text=None):
    text = text if text is not None else open(PACE, encoding='utf-8').read()

    def curve(block, key):
        b = text.split(block + ' = {', 1)[1]
        m = re.search(key + r' = \{((?:\{[0-9.]+, [0-9.]+\},?\s*)+)\}', b)
        return [(float(a), float(c)) for a, c in re.findall(r'\{([0-9.]+), ([0-9.]+)\}', m.group(1))]
    cleave = {}
    block = re.search(r'cleave = \{.*?byVocation = \{(.*?)\n\t\t\}', text, re.S)
    if block and not re.search(r'cleave = \{\s*enabled = false', text):
        for v, pc, hi, n in re.findall(r'\[(\d+)\] = \{percent = (\d+),(?: high = (\d+),)? targets = (\d+)\}',
                                       block.group(1)):
            cleave[int(v)] = (int(pc), int(n), int(hi) if hi else int(pc))
    steps = [(int(k), int(p)) for k, p in re.findall(r'\{kills = (\d+), percent = (\d+)\}', text)]
    return {'base': curve('base', 'health'), 'scaled': curve('scaled', 'health'), 'cleave': cleave, 'steps': steps}


# ------------------------------------------------------------------------------------------------ the monsters
def monsters():
    """the hunting monsters of the bounty pool: (hunting level, health, spawns) of the base ones"""
    txt = open(POOL, encoding='utf-8').read().split('\tbosses = ')[0]
    scaled = set()
    for f in os.listdir(CHAOS_MONSTERS):
        if f.endswith('.xml'):
            t = open(os.path.join(CHAOS_MONSTERS, f), encoding='utf-8', errors='replace').read()
            n = re.search(r'<monster\s[^>]*name="([^"]+)"', t)
            if n and re.search(r'<level\s+min="\d+"', t):
                scaled.add(n.group(1).lower())
    out = []
    for m in re.finditer(r'\{name = "([^"]+)", level = (\d+), exp = (\d+), health = (\d+), spawns = (\d+)', txt):
        name, lv, exp, hp, sp = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))
        by_exp = 1.6 * max(exp, 1) ** 0.5
        est = max(1, int(round(max(by_exp, min(hp / 60.0, by_exp * 1.5)))))
        if name.lower() in scaled or est != lv or hp <= 0 or exp <= 0:
            continue  # a level-scaled monster: the late sets below
        out.append((lv, hp, sp))  # hunting level = the pool's fair-hunt estimate (pace_config baseLevelMult 1 since O285)
    return out


def median_health(mons, L):
    # no base monster is hunted above the pool's highest level (O285: hunting level = pool level, 657). The base hunt that
    # the late sets are compared with above it is the top one's monsters with their health grown with the level (the
    # pool's health is about 65 a level there)
    top = max(hl for hl, h, sp in mons)
    Lh = min(L, top)
    hs = sorted(h for hl, h, sp in mons if Lh * 0.75 <= hl < Lh * 1.33 for _ in range(sp))
    return hs[len(hs) // 2] * TIER_HEALTH * max(1.0, L / float(top))


# ------------------------------------------------------------------------------------------------ the model
def damage(cls, L, kit=True, tune=True):
    """(1-target, 5-target) damage per second at level L; tune=False leaves the identity pass out (minion_model.py
    applies the class damage factor itself)"""
    a1, a5, b1, b5 = C4[cls]
    g, t = tuning(cls, L) if tune else (1.0, 1.0)
    if kit and cls in KIT:
        k = KIT[cls]
        a1, a5, b1, b5 = a1 + k[0], a5 + k[1] * t, b1 + k[2], b5 + k[3] * t
    if tune:
        a1, a5, b1, b5 = a1 * g, a5 * g, b1 * g, b5 * g
    if L <= 300:
        return a1 * L / 300.0, a5 * L / 300.0
    if L <= 1000:
        t = (L - 300) / 700.0
        return a1 + (b1 - a1) * t, a5 + (b5 - a5) * t
    return b1 + ABOVE_1000 * (L - 1000), b5 + ABOVE_1000 * (L - 1000) * b5 / b1


def multikill(P, steps, rounded):
    if rounded:
        return max([p for k, p in steps if P >= k] + [0])
    pts = [(steps[0][0] - 1, 0)] + list(steps)
    return lin(pts, P) if P >= pts[0][0] else 0


def kills_per_hour(cls, L, scaled, cfg, health, cleave=True, kit=True, rounded=False, tune=True):
    d1, d5 = damage(cls, L, kit, tune)
    if cleave and VOC[cls] in cfg['cleave']:
        e = cfg['cleave'][VOC[cls]]
        pc, n, hi = e[0], e[1], e[2] if len(e) > 2 else e[0]
        pc = lin([(CLEAVE_FROM, pc), (CLEAVE_TO, hi)], L)  # pace_core.lua P.cleavePercent
        d5 *= 1 + pc / 100.0 * min(n, 4)
    m = lin(cfg['scaled'] if scaled else cfg['base'], L)
    p0, walk = next((p, w) for lo, hi, p, w in PACK if lo <= L < hi)
    share = max(0.0, (d5 - d1) / d5)
    P = min(PCAP, p0 - 2 + 4 * min(1.0, share / 0.6))
    if rounded:
        P = round(P)
    s = max(0.0, (d5 - d1) / 4)
    clear = P * health * m / (d1 + (P - 1) * s)
    return 3600 * P / (clear + walk) * (1 + multikill(P, cfg['steps'], rounded) / 100.0), P


def reference(L, scaled, cfg, health, rounded=False):
    """kills per hour of the median class before the identity pass (C4 + KIT numbers, the cleave of BASE_CLEAVE): the fixed
    yardstick of the pack bands, so a band does not move when the classes around the median do"""
    base = dict(cfg, cleave=BASE_CLEAVE)
    return statistics.median(kills_per_hour(c, L, scaled, base, health, True, True, rounded, False)[0] for c in C4)


def spread(levels=((300, False), (800, False), (1000, True)), cleave=True, kit=True, rounded=False, cfg=None,
           mons=None, against='median'):
    """{class: [(ratio to the median class (or the top class: against='top'; or the median class before the identity
    pass: against='reference'), pack, kills per hour), ...] per level}"""
    cfg = cfg or pace()
    mons = mons if mons is not None else monsters()
    out = {c: [] for c in C4}
    for L, scaled in levels:
        health = lin(SCALED_HEALTH, L) if scaled else median_health(mons, L)
        k = {c: kills_per_hour(c, L, scaled, cfg, health, cleave, kit, rounded) for c in C4}
        if against == 'reference':
            ref = reference(L, scaled, cfg, health, rounded)
        else:
            ref = max(v[0] for v in k.values()) if against == 'top' else statistics.median(v[0] for v in k.values())
        for c in C4:
            out[c].append((k[c][0] / ref, k[c][1], k[c][0]))
    return out


def pack_clear(L, scaled, cfg, mons):
    """(seconds the pack of the median class (by kills per hour) takes, pack size P, kills per hour) at level L. The median
    class is that of the state before the class identity pass (C4 + KIT numbers, BASE_CLEAVE): the pace curves, the late sets and
    the tower are calibrated against it, and a pass that moves classes around the median does not move the yardstick"""
    health = lin(SCALED_HEALTH, L) if scaled else median_health(mons, L)
    base = dict(cfg, cleave=BASE_CLEAVE)
    rows = sorted((kills_per_hour(c, L, scaled, base, health, True, True, False, False) + (c,) for c in C4))
    k, P, c = rows[len(rows) // 2]
    d1, d5 = damage(c, L, True, False)
    if VOC[c] in base['cleave']:
        e = base['cleave'][VOC[c]]
        d5 *= 1 + lin([(CLEAVE_FROM, e[0]), (CLEAVE_TO, e[2])], L) / 100.0 * min(e[1], 4)
    m = lin(base['scaled'] if scaled else base['base'], L)
    return P * health * m / (d1 + (P - 1) * max(0.0, (d5 - d1) / 4)), P, k


BALANCE = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'boss_balance_config.lua')


def identity_config(text=None):
    """the class identity bands of boss_balance_config.lua: {'levels': [...], 'limits': {class: (lo, hi)} (boss),
    'packLimits': {...}, 'bossWindows': {level: (below, above)}, 'packWindows': {...}, 'lead': float}"""
    text = text if text is not None else open(BALANCE, encoding='utf-8').read()
    out = {'levels': [int(x) for x in re.search(r'levels = \{([0-9, ]+)\}', text).group(1).split(',') if x.strip()],
           'lead': float(re.search(r'\blead = ([0-9.]+)', text).group(1))}
    for key in ('limits', 'packLimits'):
        block = re.search(r'\b' + key + r' = \{(.*?)\n\t\}', text, re.S).group(1)
        out[key] = {c: (float(a), float(b)) for c, a, b in re.findall(r'\["([^"]+)"\] = \{([0-9.]+), ([0-9.]+)\}', block)}
    for key in ('bossWindows', 'packWindows'):
        block = re.search(key + r' = \{(.*?)\},?\n', text).group(1)
        out[key] = {int(L): (float(a), float(b)) for L, a, b in re.findall(r'\[(\d+)\] = \{([0-9.]+), ([0-9.]+)\}', block)}
    return out


def window(ratio_row, level, rows, windows):
    """the row of a class at a level, widened by the level's window"""
    lo, hi = rows
    below, above = windows.get(level, (0.0, 0.0))
    return lo - below, hi + above


def area_power(cls, L, cfg=None):
    """damage per second on a pack of 5 with the pack cleave (the share at L, up to 4 targets): the area leader's measure"""
    cfg = cfg or pace()
    d5 = damage(cls, L)[1]
    e = cfg['cleave'].get(VOC[cls])
    if e:
        d5 *= 1 + lin([(CLEAVE_FROM, e[0]), (CLEAVE_TO, e[2])], L) / 100.0 * min(e[1], 4)
    return d5


def check_identity(conf=None, cfg=None, mons=None):
    """the pack bands and the area lead (0 ok, 1 fail); prints what is outside"""
    conf = conf or identity_config()
    cfg, mons = cfg or pace(), mons if mons is not None else monsters()
    levels = conf['levels']
    t = spread(tuple((L, L >= 1000) for L in levels), cfg=cfg, mons=mons, against='reference')
    bad = 0
    for c in C4:
        if c not in conf['packLimits']:
            print('FAIL %s has no packLimits row' % c)
            bad += 1
            continue
        for L, (r, _, _) in zip(levels, t[c]):
            lo, hi = window(None, L, conf['packLimits'][c], conf['packWindows'])
            if not lo - 1e-9 <= r <= hi + 1e-9:
                print('FAIL %s at %d: pack ratio %.2f outside %.2f-%.2f' % (c, L, r, lo, hi))
                bad += 1
    for L in levels:
        top = area_power('Elementalist', L, cfg)
        for c in C4:
            if c != 'Elementalist' and area_power(c, L, cfg) * (1 + conf['lead']) > top + 1e-9:
                print('FAIL %s at %d: area damage on a pack %.0f is within %d%% of the Elementalist\'s %.0f' % (
                    c, L, area_power(c, L, cfg), round(100 * conf['lead']), top))
                bad += 1
    print('pack band check: %s (%d classes, levels %s, Elementalist %d%% ahead on a pack)' % (
        'FAIL' if bad else 'ok', len(C4), ','.join(str(L) for L in levels), round(100 * conf['lead'])))
    return 1 if bad else 0


def check():
    cfg, mons = pace(), monsters()
    bands = check_identity(None, cfg, mons)
    bad = 0
    print('| Level | Base pack | Late pack | Late / base | P | Kills/h base | Kills/h late |')
    print('|---|---|---|---|---|---|---|')
    for L in LATE_LEVELS:
        b, bp, bk = pack_clear(min(L, 1000), False, cfg, mons)
        s, sp, sk = pack_clear(L, True, cfg, mons)
        flag = '' if s <= LATE_MAX * b else ' FAIL'
        bad += bool(flag)
        print('| %d | %.1f s | %.1f s | %.2f%s | %.1f | %d | %d |' % (L, b, s, s / b, flag, sp, bk, sk))
    print('late pack check: %s (limit %.1fx a base hunt pack)' % ('FAIL' if bad else 'ok', LATE_MAX))
    return 1 if bad or bands else 0


def main(argv):
    if '--check' in argv:
        return check()
    levels = ((300, False), (800, False), (1000, True))
    if '--levels' in argv:
        ls = [int(x) for x in argv[argv.index('--levels') + 1].split(',')]
        levels = tuple((L, L >= 1000) for L in ls)
    top = '--top' in argv
    t = spread(levels, cleave='--no-cleave' not in argv, kit='--no-kit' not in argv, rounded='--rounded' in argv,
               against='top' if top else ('median' if '--median' in argv else 'reference'))
    print('| Class | ' + ' | '.join('%d%s' % (L, ' (late set)' if s else '') for L, s in levels) + ' |')
    print('|---|' + '---|' * len(levels))
    for c, v in t.items():
        if top:
            print('| %s | %s |' % (c, ' | '.join('%s kills/h (%.2f)' % (format(round(k), ','), r) for r, _, k in v)))
        else:
            print('| %s | %s |' % (c, ' | '.join('%.2f' % r for r, _, _ in v)))
    allr = [r for v in t.values() for r, _, _ in v]
    print('range %.2f-%.2f' % (min(allr), max(allr)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
