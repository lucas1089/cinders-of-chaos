#!/usr/bin/env python3
"""The pack model: experience per hour of every class in packs, against the median class at the same level (computed,
not measured; server/README.md "Pack combat (pace)", data/spells/README.md "Pack farming for every class").

usage: python3 -I server/tools/pack_model.py [--levels 300,800,1000] [--no-cleave] [--no-kit] [--rounded] [--top]

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
        out.append((2 * lv, hp, sp))  # hunting level = 2 x the pool's fair-hunt estimate
    return out


def median_health(mons, L):
    hs = sorted(h for hl, h, sp in mons if L * 0.75 <= hl < L * 1.33 for _ in range(sp))
    return hs[len(hs) // 2] * TIER_HEALTH


# ------------------------------------------------------------------------------------------------ the model
def damage(cls, L, kit=True):
    a1, a5, b1, b5 = C4[cls]
    if kit and cls in KIT:
        k = KIT[cls]
        a1, a5, b1, b5 = a1 + k[0], a5 + k[1], b1 + k[2], b5 + k[3]
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


def kills_per_hour(cls, L, scaled, cfg, health, cleave=True, kit=True, rounded=False):
    d1, d5 = damage(cls, L, kit)
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


def spread(levels=((300, False), (800, False), (1000, True)), cleave=True, kit=True, rounded=False, cfg=None,
           mons=None, against='median'):
    """{class: [(ratio to the median class (or the top class: against='top'), pack, kills per hour), ...] per level}"""
    cfg = cfg or pace()
    mons = mons if mons is not None else monsters()
    out = {c: [] for c in C4}
    for L, scaled in levels:
        health = lin(SCALED_HEALTH, L) if scaled else median_health(mons, L)
        k = {c: kills_per_hour(c, L, scaled, cfg, health, cleave, kit, rounded) for c in C4}
        ref = max(v[0] for v in k.values()) if against == 'top' else statistics.median(v[0] for v in k.values())
        for c in C4:
            out[c].append((k[c][0] / ref, k[c][1], k[c][0]))
    return out


def main(argv):
    levels = ((300, False), (800, False), (1000, True))
    if '--levels' in argv:
        ls = [int(x) for x in argv[argv.index('--levels') + 1].split(',')]
        levels = tuple((L, L >= 1000) for L in ls)
    top = '--top' in argv
    t = spread(levels, cleave='--no-cleave' not in argv, kit='--no-kit' not in argv, rounded='--rounded' in argv,
               against='top' if top else 'median')
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
