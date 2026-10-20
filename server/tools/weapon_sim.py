#!/usr/bin/env python3
"""Weapon damage per second across weapon styles (owner debug item 47: "Fórmula de dano das armas muito inconsistente").

usage: python3 -I server/tools/weapon_sim.py [--report] [--write | --check] [--audit DATA_DIR]

The model (computed, not measured; the engine's formula, Weapons::getMaxWeaponDamage):
  max hit  = round(level / 5 (integer) + ((skill / 4 + 1) * (attack / 3) * 1.03) / attack factor)
  hit      = a bell curve over min..max hit (min 0 for melee, a fifth of the level for a launcher), x the style factor
             of weapon_styles.lua
  per sec  = mean hit x hit chance / attack interval
The attack factor is 1 in the offensive stance, the skill is the same for every style (one melee skill, see server/README.md
"One melee skill"), the interval is the weapon's own (one-handed 2000 ms, two-handed and launchers 3000 ms, scaled alike by
every vocation). The tier of a level comes from the equipment sets (install_gear_sets.py CURVES: one-handed melee attack,
launcher attack and hit chance by level; the stock gear of the same level is what those curves were anchored to). Every
melee type of one tier (sword, axe, club) has the same attack there, so the differences are the styles:
  melee1    one-handed weapon (+ shield)        the reference, 1.00
  melee2    two-handed sword, axe or club       attack + 3, 3000 ms, no shield           target 1.07 (two_handed.py: "about +7%")
  bow       launcher, splash 50% on the others  attack of the launcher, 3000 ms, hit chance   (aligned: 1.00, the splash is its extra)
  crossbow  launcher, no splash                 attack + 3, 3000 ms, hit chance          (aligned: 1.07)
The flat x1.6 of the two-handed weapons and launchers (before) put the two-handed weapons 12-28% and the launchers up to
111% ahead of one hand + shield. The style factor of the melee styles is now a function of the level
(weapon_balance_config.lua, written by this tool with --write, read by weapon_styles.lua through weapon_balance_core.lua)
solved so a two-handed weapon lands on its target whatever the attack of the tier is. The launchers keep the flat x1.6
while RANGED_ALIGN is False: the Ranger line's class order was measured with them (server/data/spells/README.md "Class
order fixes"), and aligning them takes a third off the Ranger line's auto attacks (see the README); set it to True to
bring them on target (the class compensation is then the owner's call).

--report   the table of dps against one-handed at levels 8 .. 300, before and after, and the fist of the Monk
--check    exit 1 when weapon_balance_config.lua is out of date or the melee styles (and the launchers, when aligned)
           are not within TOLERANCE (10%) of each other at any level 8 .. 300 (within 12% at half and at one and a half
           times the usual skill)
--write    write server/data/scripts/chaos/weapon_balance_config.lua
--audit DATA_DIR   read the base items.xml and weapons.xml of an installed server: the attack of the one-handed and
           two-handed swords, axes and clubs and of the launchers, per level band, against the tier curve; run it on the
           server after install_all.py and put a type that is off into TYPE_FACTOR (the base items are never hand edited)
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_gear_sets as G  # noqa: E402  (CURVES, curve)

REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'weapon_balance_config.lua')

LEVELS = (8, 15, 30, 50, 75, 100, 150, 200, 300)                              # the report
FACTOR_LEVELS = (1, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 75, 100, 125, 150, 200, 250, 300, 400, 700, 1000, 1500, 2000)   # the anchors of the config
TOLERANCE = 0.10                    # styles of one tier within 10% of each other (at the modelled skill)
SKILL_TOLERANCE = 0.12              # ... and within 12% when the skill is half or one and a half times the model's
FLAT_BEFORE = 1.6                   # weapon_styles.lua twoHandedDamage until 2026-10-17
TARGET = {'melee1': 1.00, 'melee2': 1.07, 'bow': 1.00, 'crossbow': 1.07}
RANGED_ALIGN = False                # True: the launchers get factors on target too (an owner decision, see the README)
STYLES = ('melee1', 'melee2', 'bow', 'crossbow')
MELEE_STYLES = ('melee1', 'melee2')
INTERVAL = {'melee1': 2000.0, 'melee2': 3000.0, 'bow': 3000.0, 'crossbow': 3000.0}
# a multiplier per weapon type, for a type whose base items turn out off the tier (--audit); 1.0 = as they are
TYPE_FACTOR = {'sword': 1.0, 'axe': 1.0, 'club': 1.0}
SKILL_START, SKILL_PER_LEVEL = 10.0, 0.4    # the skill a character has at a level: an assumption, tested at x0.5 and x1.5


def skill_at(level, k=1.0):
    return max(10.0, (SKILL_START + SKILL_PER_LEVEL * (level - 8)) * k)


def max_hit(level, skill, attack, factor=1.0):
    """Weapons::getMaxWeaponDamage (level / 5 is an integer division)"""
    return int(level // 5 + ((skill / 4.0 + 1) * (attack / 3.0) * 1.03) / factor + 0.5)


def attack_of(style, level):
    if style == 'melee1':
        return G.curve('attack', level)
    if style == 'melee2':
        return G.curve('attack', level) + 3
    if style == 'bow':
        return G.curve('bow', level)
    return G.curve('bow', level) + 3


def hit_chance(style, level):
    return G.curve('hit', level) / 100.0 if style in ('bow', 'crossbow') else 1.0


def mean_hit(style, level, k=1.0):
    """normal_random(min, max) is centred: min is 0 for a melee weapon and a fifth of the level (rounded up) against a
    monster for a launcher (WeaponDistance::getWeaponDamage; ChaosArchery.averageHit)"""
    top = max_hit(level, skill_at(level, k), attack_of(style, level))
    low = min(top, -(-level // 5)) if style in ('bow', 'crossbow') else 0
    return (low + top) / 2.0


def raw_dps(style, level, k=1.0):
    """per second before the style factor"""
    return mean_hit(style, level, k) * hit_chance(style, level) / INTERVAL[style] * 1000.0


def interp(levels, values, level):
    """the same linear interpolation weapon_balance_core.lua does: flat outside the anchors"""
    if level <= levels[0]:
        return values[0]
    for i in range(1, len(levels)):
        if level <= levels[i]:
            x0, x1 = levels[i - 1], levels[i]
            return values[i - 1] + (values[i] - values[i - 1]) * (level - x0) / float(x1 - x0)
    return values[-1]


def solve_factors(align_ranged=None):
    """style -> factor at each FACTOR_LEVELS so the style's dps = TARGET x the one-handed dps (skill model k = 1); the
    launchers keep FLAT_BEFORE unless they are aligned (RANGED_ALIGN)"""
    align = RANGED_ALIGN if align_ranged is None else align_ranged
    out = {}
    for style in STYLES[1:]:
        if style != 'melee2' and not align:
            out[style] = [FLAT_BEFORE] * len(FACTOR_LEVELS)
        else:
            out[style] = [round(TARGET[style] * raw_dps('melee1', lv) / raw_dps(style, lv), 3) for lv in FACTOR_LEVELS]
    return out


def style_factor(factors, style, level):
    if style == 'melee1':
        return 1.0
    return interp(FACTOR_LEVELS, factors[style], level)


def flat_factors():
    return {s: [FLAT_BEFORE] * len(FACTOR_LEVELS) for s in STYLES[1:]}


def dps(style, level, factors, k=1.0):
    return raw_dps(style, level, k) * style_factor(factors, style, level)


def spread(level, factors, k=1.0, styles=None):
    """(ratios to one-handed per style, widest ratio between two of the styles in `styles`: the melee styles, or all of
    them when the launchers are aligned)"""
    styles = styles or (STYLES if RANGED_ALIGN else MELEE_STYLES)
    base = dps('melee1', level, factors, k)
    ratios = {s: dps(s, level, factors, k) / base for s in STYLES}
    inside = [ratios[s] for s in styles]
    return ratios, max(inside) / min(inside)


def fist_ratio(level):
    """a Monk's bare fists against one hand (monk_chi_core.lua cfg.unarmed: attack 40 + 0.025 per level, at most 60; the
    class factor meleeDamage 1.1-1.2 left out, the Thief line has its own just the same)"""
    fist = min(60.0, 40.0 + 0.025 * level)
    s = skill_at(level)
    return max_hit(level, s, fist) / float(max_hit(level, s, attack_of('melee1', level)))


# ------------------------------------------------------------------------------------------------ the config file
def lua_list(values):
    return '{' + ', '.join(('%g' % v) for v in values) + '}'


def config_text(factors):
    return (
        '-- Weapon style factors by character level (generated by server/tools/weapon_sim.py --write, do not edit by hand;\n'
        '-- server/data/spells/README.md "Weapon damage per second"). weapon_styles.lua multiplies the hit of a two-handed\n'
        '-- weapon, a bow or a crossbow by the factor of the wielder\'s level (weapon_balance_core.lua interpolates between\n'
        '-- the levels). The factors make a style of one tier deal the damage per second of its target against one hand\n'
        '-- and a shield (two-handed melee and crossbow 1.04, bow 1.00 and its splash), whatever the attack and the\n'
        '-- interval of the style are at that level. typeFactor scales a weapon type whose base items are off the tier\n'
        '-- (weapon_sim.py --audit on an installed server). Lua 5.1 / LuaJIT and 5.3.\n'
        'return {\n'
        '\tlevels = %s,\n'
        '\ttwoHanded = %s,\n'
        '\tbow = %s,\n'
        '\tcrossbow = %s,\n'
        '\ttypeFactor = {sword = %g, axe = %g, club = %g}\n'
        '}\n') % (lua_list(FACTOR_LEVELS), lua_list(factors['melee2']), lua_list(factors['bow']),
                  lua_list(factors['crossbow']), TYPE_FACTOR['sword'], TYPE_FACTOR['axe'], TYPE_FACTOR['club'])


# ------------------------------------------------------------------------------------------------ report and check
def report():
    after = solve_factors()
    aligned = solve_factors(True)
    before = flat_factors()
    out = ['Weapon damage per second against one hand + shield (1.00), same tier, same skill, offensive stance',
           'level  | two-handed bef  aft | bow bef  aft  aligned | crossbow bef  aft  aligned | melee gap bef  aft | fist (Monk)']
    for lv in LEVELS:
        rb, _ = spread(lv, before)
        ra, _ = spread(lv, after)
        rl, _ = spread(lv, aligned)
        gb = spread(lv, before, 1.0, MELEE_STYLES)[1]
        ga = spread(lv, after, 1.0, MELEE_STYLES)[1]
        out.append('%-6d | %12.2f %4.2f | %7.2f %4.2f %7.2f | %12.2f %4.2f %7.2f | %9.0f%% %3.0f%% | %.2f' % (
            lv, rb['melee2'], ra['melee2'], rb['bow'], ra['bow'], rl['bow'], rb['crossbow'], ra['crossbow'],
            rl['crossbow'], (gb - 1) * 100, (ga - 1) * 100, fist_ratio(lv)))
    out.append('')
    out.append('style factor (weapon_balance_config.lua)    ' + ' '.join('%5d' % lv for lv in LEVELS))
    for style in STYLES[1:]:
        out.append('  %-8s before %.2f                       ' % (style, FLAT_BEFORE) + ' '.join(
            '%5.2f' % style_factor(after, style, lv) for lv in LEVELS))
    out.append('  aligned launchers (RANGED_ALIGN = True): bow ' + ' '.join(
        '%5.2f' % style_factor(aligned, 'bow', lv) for lv in LEVELS) + '  crossbow ' + ' '.join(
        '%5.2f' % style_factor(aligned, 'crossbow', lv) for lv in LEVELS))
    return '\n'.join(out)


def problems(factors=None):
    """every level 8 .. 300 and 400 .. 2000 (the anchors) at skill x0.5, x1, x1.5: the widest gap between two styles"""
    factors = factors or solve_factors()
    bad = []
    for k in (0.5, 1.0, 1.5):
        for lv in list(range(8, 301)) + [400, 700, 1000, 1500, 2000]:
            ratios, wide = spread(lv, factors, k)
            if wide > 1 + (TOLERANCE if k == 1.0 else SKILL_TOLERANCE) + 1e-9:
                bad.append('level %d skill x%.1f: widest gap %.1f%% (%s)' % (
                    lv, k, (wide - 1) * 100, ', '.join('%s %.2f' % kv for kv in sorted(ratios.items()))))
    return bad


# ------------------------------------------------------------------------------------------------ audit of a server
def audit(data_dir):
    """rows (kind, band, count, median attack) from the installed items.xml and weapons.xml, and the tier's attack"""
    def read(*parts):
        with open(os.path.join(data_dir, *parts), encoding='utf-8', errors='surrogateescape') as f:
            return f.read()
    items = read('items', 'items.xml')
    levels = {}
    for m in re.finditer(r'<(?:melee|distance|wand)\b([^>]*)', read('weapons', 'weapons.xml')):
        head = m.group(1)
        lv = re.search(r'\blevel="(\d+)"', head)
        one = re.search(r'\bid="(\d+)"', head)
        if lv and one:
            levels[int(one.group(1))] = int(lv.group(1))
    rows = {}
    for m in re.finditer(r'<item\s([^>]*?)>(.*?)</item>', items, re.S):
        head, body = m.group(1), m.group(2)
        wid = re.search(r'\bid="(\d+)"', head)
        wt = re.search(r'key="weaponType"\s+value="([^"]+)"', body)
        atk = re.search(r'key="attack"\s+value="(\d+)"', body)
        if not (wid and wt and atk) or wt.group(1) not in ('sword', 'axe', 'club', 'distance'):
            continue
        two = re.search(r'key="slotType"\s+value="two-handed"', body) is not None
        kind = wt.group(1) if wt.group(1) != 'distance' else ('launcher' if two else 'throwing')
        if kind != 'launcher' and wt.group(1) != 'distance':
            kind += '2' if two else '1'
        if kind == 'throwing':
            continue
        lv = levels.get(int(wid.group(1)))
        if lv is None:
            continue
        band = next(b for b in (20, 50, 100, 200, 400, 1000, 10 ** 9) if lv <= b)
        rows.setdefault((kind, band), []).append(int(atk.group(1)))
    out = []
    for (kind, band), vals in sorted(rows.items()):
        vals.sort()
        median = vals[len(vals) // 2]
        top = band if band < 10 ** 9 else 2000
        tier = attack_of('melee1' if kind.endswith('1') else 'melee2' if kind.endswith('2') else 'bow', top)
        out.append((kind, band, len(vals), median, tier))
    return out


def audit_report(data_dir):
    lines = ['kind        up to level  items  median attack  tier attack at the top of the band']
    for kind, band, n, median, tier in audit(data_dir):
        lines.append('%-11s %11s %6d %15d %10.0f' % (kind, band if band < 10 ** 9 else 'above', n, median, tier))
    return '\n'.join(lines)


def main(argv):
    if '--audit' in argv:
        i = argv.index('--audit')
        if i + 1 >= len(argv):
            print(__doc__)
            return 1
        print(audit_report(argv[i + 1]))
        return 0
    factors = solve_factors()
    text = config_text(factors)
    if '--write' in argv:
        with open(CONFIG, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        print('wrote ' + os.path.relpath(CONFIG, REPO))
        return 0
    if '--check' in argv:
        bad = problems(factors)
        current = open(CONFIG, encoding='utf-8').read() if os.path.isfile(CONFIG) else ''
        if current != text:
            bad.append('weapon_balance_config.lua is out of date (python3 -I server/tools/weapon_sim.py --write)')
        for b in bad[:20]:
            print('FAIL ' + b)
        if not bad:
            print('weapon_sim: OK (one-handed and two-handed melee within %d%% of each other at levels 8-300)' % int(TOLERANCE * 100))
        return 1 if bad else 0
    print(report())
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
