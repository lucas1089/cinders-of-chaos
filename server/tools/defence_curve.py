#!/usr/bin/env python3
"""The median hits by level (O462, O501): the curves of data/scripts/chaos/monster_defence_config.lua `hitCurve` and `weaponHitCurve`.

usage: python3 -I server/tools/defence_curve.py [--check] [--lua] [--autos [--level N]]

The armour of a monster (monster_defence_core.lua) is sized so that the median hit at the monster's level loses 25%
(normal), 40% (rare and legendary) or 50% (bosses) of itself. Two medians, because two kinds of hit meet the armour:

CLASS HIT (`hitCurve`, a spell; O462). From the class damage model (class_dps_model.py: the measured csv moved by the changes
since, computed not measured), the way the README "Monster defence (O462)" says:
  For each of the 21 classes at the measured levels 100, 500 and 1000 (one target):
    dps            the model's damage per second on one target
    auto share     a = the auto attack's share of it (class_dps_measured.csv auto_share_1t)
    weapon hit     dps x a x I, one swing every I seconds (the vocation's attack speed, chaos_vocations*.xml)
    spell hit      dps x (1 - a) x 2.0, one cast on every attack group cooldown (rotation_sim.py GCD, 2 s: the helper's
                   rotation casts on every cooldown by design)
    class hit      the damage weighted mean: a x weapon hit + (1 - a) x spell hit
  The median class hit is the median over the 21 classes. Its ratio to the median dps is kept between the anchors (a
  straight line in the logarithm of the level, flat outside) and multiplied with class_dps_model.median_dps(level) at the
  anchor levels of the config.

WEAPON HIT (`weaponHitCurve`, a melee or ranged weapon hit; O501, owner 2026-11-11: "the auto attack is hitting practically
nothing on the monsters"). The class hit is the wrong yardstick for an auto attack: it is the hit of a typical character AFTER the
player's own multipliers (class damage, damage pool, weapon style, weapon power, the Monk's unarmed scaling ...), which are later
events of the monster than the armour layer; the layer sees the weapon hit as the engine rolled it. This tool derives the weapon
curve in the units that ARRIVE (measured on a local server, README "Monster defence (O462)" "Measured, O501"):
    engine roll   Weapons::getMaxWeaponDamage = level / 5 + (skill / 4 + 1) x (attack / 3) x 1.03; a bell between 0 (a fifth of the
                  level for a launcher) and the maximum, its quantiles ROLL (mean 1), the attack of the equipment tier of the
                  level (install_gear_sets.py curves, grown by weapon_growth.py), of which the physical part is PHYS_SHARE for a
                  set melee weapon (the rest is an element part, never armoured), all of it for a bow, FIST_ATTACK for the Monk
                  line (the engine's bare fist; the Monk's scaling is a later event), the typical skill of the level
                  (weapon_skill_config.lua) but never below SKILL_FLOOR (measured)
    flat armour   the monster's own XML armour and defence take off a hit before any Lua event (Creature::blockHit): FLAT, the
                  medians of the hunt monsters by level (measured on the installed pool and the repository's chaos monsters)
    arriving hit  roll - defence - armour, a hit that falls to 0 never reaches the layer
  weaponHitCurve = the median over the 15 classes with an armoured weapon hit (the 6 casters hit with a wand: ORIGIN_WAND, which
  the armour never touches) of the mean arriving hit, at the same levels as hitCurve.
  weaponShareCap = the most a weapon hit may lose to armour per rank: the ceilings G2 below.

--check
  1  the config's two curves are what this derivation gives (a change of the class damage model, of a tier curve or of a constant
     moves them)
  2  G1 the armour removes about the armourTarget of the auto attack damage (expected over the roll, of arriving hits) of the
     median class: within G1_TOL points at every level of LEVELS_CHECK, normal, elite and boss
  3  G2 no class loses more than the ceiling (normal 40, elite 55, boss 65) of an auto attack, at every level of LEVELS_CHECK
  4  the caps of the config are the ceilings, and a big hit still loses less than a small one
--autos  the table: class, level, mean arriving weapon hit, share removed on a normal / elite / boss monster, before (class curve,
         no cap) and after (weapon curve, capped)
--lua    print the two curves as the Lua rows of the config
"""
import functools
import math
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import class_dps_model as M  # noqa: E402
import rotation_sim as R  # noqa: E402
import weapon_sim as WS  # noqa: E402

CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'monster_defence_config.lua')
DEFENCE = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'defence_config.lua')
LEVELS = (1, 10, 30, 60, 100, 200, 300, 500, 750, 1000, 1500, 2000, 2500)
GCD = R.GCD

# ---- the auto attack as it arrives at the layer (O501) -------------------------------------------------------------------
# the physical share of the attack of a set melee weapon: install_gear_sets.py gives a set weapon its attack as a physical part and an
# element part, 65 : 35 (wyrmscale blade 22 + 12, bloodmoon blade 44 + 23, rimewraith blade 51 + 27, wintermourn blade 96 + 51;
# data/items/items.xml of an installed server). A bow has no element part.
PHYS_SHARE = 0.65
# the engine's bare fist attack: the Monk line's fist hit arrives as that, monk_combat.lua (ChaosMonkCombat, registered on a monster
# at the first hit, so after the layer) scales it to the level-based fist attack later. Measured: a Monk's fist hits max 63 at level
# 100, skill 70 = the formula with attack 6.8.
FIST_ATTACK = 7.0
# the weapon skill the engine rolls with is never below this: a level 8 and a level 20 character with weapon skill 10 and 20 hit as
# a skill of about 36 (measured 2026-11-11: maximum hits 36 and 38 for a blade of attack 10 against 13 and 25 by the formula; the
# fit over the sword, bow and fist of both levels). Not found in the Lua; the engine patches are not in the repository.
SKILL_FLOOR = 36.0
# the quantiles (20 midpoints, 2.5% to 97.5%) of the arriving physical hit over its mean, pooled over the Warrior (one and two
# hands), Ranger and Monk characters at levels 20 to 1000 (3,000 hits, measured 2026-11-11, SP/o501 hits_*_n_on.txt): a bell
# between 0 and twice the mean. The Thief's blade adds crits and is left out.
ROLL = (0.165, 0.348, 0.482, 0.571, 0.646, 0.733, 0.803, 0.859, 0.925, 0.988, 1.023, 1.07, 1.126, 1.2, 1.265, 1.338, 1.427, 1.522,
        1.659, 1.85)
# the armour (= the defence, the files hold the same number) of a hunt monster by level: the median of the bounty pool's monsters
# within 10% of the level on the installed server (5 at 8, 10 at 13, 15 at 20, 30 at 60 and 100, 65 at 300, 70 at 500) and of the
# repository's level-scaled monsters (75 at 500, 85 at 1000, 90 at 2000), measured 2026-11-11 with SP/o501 realmon.py, chaosmon.py
FLAT = ((1, 2.0), (8, 5.0), (13, 10.0), (20, 15.0), (60, 30.0), (100, 30.0), (300, 65.0), (500, 75.0), (1000, 85.0), (2000, 90.0))
# G1: points the expected share of the median class may be off its armourTarget; G2: the most any class loses, by rank
G1_TOL = 5.0
CEILING = {'normal': 40.0, 'elite': 55.0, 'boss': 65.0}
LEVELS_CHECK = tuple(sorted(set(list(range(8, 100, 4)) + list(range(100, 500, 20)) + list(range(500, 2501, 50)) + [8, 13, 20, 60, 100, 300, 500, 1000, 2000, 2500])))
FACTOR = 0.07   # defence_config.lua armourHitFactor, read below


def armour_factor(path=DEFENCE):
    return float(re.search(r'armourHitFactor\s*=\s*([0-9.]+)', open(path, encoding='utf-8').read()).group(1))


def class_hits(level, out=None, rows=None, now=None):
    """{class: (weapon hit, spell hit, class hit)} at one of the measured levels"""
    out = out or M.shipped()[0]
    rows = rows or M.load_rows()
    now = now or M.intervals()[0]
    res = {}
    for cls in M.KEY:
        d1 = out[(cls, level)]['1t']
        a = rows[(cls, level)]['auto_share_1t']
        interval = now[R.VOC[cls]] / 1000.0
        weapon = d1 * a * interval
        spell = d1 * (1 - a) * GCD
        res[cls] = (weapon, spell, a * weapon + (1 - a) * spell)
    return res


def ratios():
    """{measured level: median class hit / median dps (1 target)}"""
    out, med = M.shipped()
    return {lv: statistics.median(v[2] for v in class_hits(lv, out).values()) / med[lv][0] for lv in M.LEVELS}


def ratio_at(level, r=None):
    r = r or ratios()
    lv = sorted(r)
    if level <= lv[0]:
        return r[lv[0]]
    if level >= lv[-1]:
        return r[lv[-1]]
    for a, b in zip(lv, lv[1:]):
        if level <= b:
            t = (math.log(level) - math.log(a)) / (math.log(b) - math.log(a))
            return r[a] + (r[b] - r[a]) * t
    return r[lv[-1]]


def curve(levels=LEVELS):
    r = ratios()
    return [(lv, int(round(M.median_dps(lv)[0] * ratio_at(lv, r)))) for lv in levels]


# ---- the weapon hit ------------------------------------------------------------------------------------------------------
ARMOURED = [c for c in M.KEY if R.CLASS_KIND[c] != 'caster']      # the 15 classes whose auto attack is a melee or ranged hit


def flat_at(level):
    """the armour and the defence of a typical hunt monster of the level (straight between the rows, flat outside)"""
    return WS.interp([p[0] for p in FLAT], [p[1] for p in FLAT], level)


def skill_of(level):
    return max(SKILL_FLOOR, WS.anchor_interp(WS.skill_config()['skill'], level))


def engine_mean(kind, level, skill, attack):
    """the mean of the engine's roll of the physical part of an auto attack: Weapons::getMaxWeaponDamage = level / 5 + (skill / 4 + 1) x
    (attack / 3) x 1.03 (rounded), a bell between 0 (a fifth of the level, rounded up, for a launcher) and that maximum"""
    top = int(level // 5 + (skill / 4.0 + 1) * (attack / 3.0) * 1.03 + 0.5)
    low = min(top, -(-level // 5)) if kind == 'distance' else 0
    return (low + top) / 2.0


@functools.lru_cache(maxsize=None)
def roll_mean(cls, level):
    """the mean of the engine's roll of the physical part of an auto attack of the class at the level, before the monster's flat
    armour: the tier weapon of the level (weapon_sim.py), the typical skill"""
    kind = R.CLASS_KIND[cls]
    if kind == 'fist':
        atk = FIST_ATTACK
    elif kind == 'distance':
        atk = WS.attack_of('bow', level)
    else:
        atk = (WS.attack_of('melee2', level) if cls == 'Berserker' else WS.attack_of('melee1', level)) * PHYS_SHARE
    return engine_mean(kind, level, skill_of(level), atk)


def after_flat(hit, armour, defence):
    """[(size, weight)] of the hit as it arrives after the engine took the monster's defence (uniform defence / 2 .. defence, once a
    second: every hit of a weapon of the 1 s interval and up) and its armour (uniform armour / 2 .. armour - 1 - armour % 2, 1 below
    4): five points of each spread; a hit that falls to 0 is dropped (Creature::blockHit)"""
    out = []
    dl, dh = defence / 2.0, float(defence)
    al = armour // 2
    ah = armour - (armour % 2 + 1)
    if armour <= 3:
        al = ah = 1 if armour > 0 else 0
    for i in range(5):
        d = dl + (dh - dl) * (i + 0.5) / 5
        h1 = hit - d
        if h1 <= 0:
            continue
        for j in range(5):
            a = al + (ah - al) * (j + 0.5) / 5
            h2 = h1 - a
            if h2 > 0:
                out.append((h2, 1.0 / 25))
    return out


@functools.lru_cache(maxsize=None)
def arriving(cls, level):
    """[(size, weight)] the arriving physical hits of the class's auto attack at the level (the whole roll, flat armour taken off)"""
    m = roll_mean(cls, level)
    f = flat_at(level)
    hits = []
    for r in ROLL:
        for h, w in after_flat(m * r, f, f):
            hits.append((h, w / len(ROLL)))
    return hits


@functools.lru_cache(maxsize=None)
def arriving_mean(cls, level):
    h = arriving(cls, level)
    tot = sum(w for _, w in h)
    return sum(v * w for v, w in h) / tot if tot else 0.0


def weapon_curve(levels=LEVELS):
    return [(lv, max(1, int(round(statistics.median(arriving_mean(c, lv) for c in ARMOURED))))) for lv in levels]


def hit_at(rows, level):
    """the config's rule: a straight line in log level and log hit between two rows, the slope of the last two rows beyond"""
    a, b = rows[0], rows[1]
    for i in range(1, len(rows)):
        a, b = rows[i - 1], rows[i]
        if level <= b[0]:
            break
    e = (math.log(b[1]) - math.log(a[1])) / (math.log(b[0]) - math.log(a[0]))
    return a[1] * (max(1, level) / float(a[0])) ** e


def armour_value(rows, target, level, factor=None):
    f = target / 100.0
    return f / (1 - f) * (factor or FACTOR) * hit_at(rows, level)


def share_of(A, h, cap=None, factor=None):
    s = A / (A + (factor or FACTOR) * h)
    return min(s, cap / 100.0) if cap is not None else s


def expected_share(hits, A, cap=None):
    """the share of the damage of a list of arriving hits [(size, weight)] that armour A removes (damage weighted), caps in percent"""
    tot = sum(v * w for v, w in hits)
    return 100.0 * sum(v * w * share_of(A, v, cap) for v, w in hits) / tot if tot else 0.0


@functools.lru_cache(maxsize=None)
def median_class(level):
    """the armoured class whose mean arriving hit is the median one (the 15th of 15 sorted: the 8th)"""
    ranked = sorted(ARMOURED, key=lambda c: arriving_mean(c, level))
    return ranked[len(ranked) // 2]


def config_curve(path=CONFIG, name='hitCurve'):
    text = open(path, encoding='utf-8').read()
    block = text.split(name + ' = {', 1)[1].split('\n\t}', 1)[0]
    return [(int(a), int(b)) for a, b in re.findall(r'\{level = (\d+), hit = (\d+)\}', block)]


def config_caps(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    m = re.search(r'weaponShareCap\s*=\s*\{([^}]*)\}', text)
    return {k: float(v) for k, v in re.findall(r'(\w+)\s*=\s*([0-9.]+)', m.group(1))} if m else {}


def config_targets(path=CONFIG, name='armourTarget'):
    text = open(path, encoding='utf-8').read()
    m = re.search(name + r'\s*=\s*\{([^}]*)\}', text)
    return {k: float(v) for k, v in re.findall(r'(\w+)\s*=\s*([0-9.]+)', m.group(1))}


def problems(weapon=None, caps=None, targets=None, levels=LEVELS_CHECK, wtargets=None):
    """the G1 / G2 findings of a weapon curve (rows), caps and weapon targets: [text]; targets are the armourTarget goals of G1"""
    weapon = weapon or config_curve(name='weaponHitCurve')
    caps = caps or config_caps()
    targets = targets or config_targets()
    wtargets = wtargets or config_targets(name='weaponTarget')
    out = []
    for rank, ceiling in CEILING.items():
        if caps.get(rank) is None or caps[rank] > ceiling + 1e-9:
            out.append('G2 the %s cap %s is above its ceiling %s' % (rank, caps.get(rank), ceiling))
    for lv in levels:
        for rank in ('normal', 'elite', 'boss'):
            A = armour_value(weapon, wtargets[rank], lv)
            cap = caps.get(rank)
            mid = median_class(lv)
            e = expected_share(arriving(mid, lv), A, cap)
            if abs(e - targets[rank]) > G1_TOL:
                out.append('G1 level %d %s: the median class (%s) loses %.1f%%, target %.0f%% +-%.0f' % (lv, rank, mid, e, targets[rank], G1_TOL))
            for c in ARMOURED:
                e = expected_share(arriving(c, lv), A, cap)
                if e > CEILING[rank] + 1e-9:
                    out.append('G2 level %d %s: %s loses %.1f%%, ceiling %.0f%%' % (lv, rank, c, e, CEILING[rank]))
    return out


def autos(level):
    """rows [class, mean arriving hit, [after share normal, elite, boss], [before]]: before = the class curve, no cap (O462), after = the weapon
    curve with the caps (O501)"""
    targets = config_targets()
    wtargets = config_targets(name='weaponTarget')
    caps = config_caps()
    weapon = config_curve(name='weaponHitCurve')
    cls_rows = config_curve()
    rows = []
    for c in ARMOURED:
        h = arriving(c, level)
        after = [expected_share(h, armour_value(weapon, wtargets[r], level), caps.get(r)) for r in ('normal', 'elite', 'boss')]
        before = [expected_share(h, armour_value(cls_rows, targets[r], level)) for r in ('normal', 'elite', 'boss')]
        rows.append((c, arriving_mean(c, level), after, before))
    return rows


def main(argv):
    global FACTOR
    FACTOR = armour_factor()
    got = curve()
    wgot = weapon_curve()
    if '--lua' in argv:
        print('hitCurve:')
        print(',\n'.join('\t\t{level = %d, hit = %d}' % row for row in got))
        print('weaponHitCurve:')
        print(',\n'.join('\t\t{level = %d, hit = %d}' % row for row in wgot))
        return 0
    if '--check' in argv:
        bad = 0
        have = config_curve()
        if have != got:
            print('FAIL monster_defence_config.lua hitCurve is not the derivation of the class damage model:')
            print('  config    ', have)
            print('  derivation', got)
            bad = 1
        whave = config_curve(name='weaponHitCurve')
        if whave != wgot:
            print('FAIL monster_defence_config.lua weaponHitCurve is not the derivation of the arriving auto attack:')
            print('  config    ', whave)
            print('  derivation', wgot)
            bad = 1
        for p in problems():
            print('FAIL ' + p)
            bad = 1
        if bad:
            return 1
        print('defence curve check: ok (%d anchors, median class hit %d at 100, %d at 500, %d at 1000; median weapon hit %d / %d / %d; G1 within %.0f points and G2 at %d levels)' % (
            len(got), dict(got)[100], dict(got)[500], dict(got)[1000], dict(wgot)[100], dict(wgot)[500], dict(wgot)[1000], G1_TOL, len(LEVELS_CHECK)))
        return 0
    if '--autos' in argv:
        levels = [int(argv[argv.index('--level') + 1])] if '--level' in argv else (100, 500, 1000)
        for lv in levels:
            print('level %d: flat armour and defence of a hunt monster %.0f, skill %.0f' % (lv, flat_at(lv), skill_of(lv)))
            print('%-12s %9s | share removed after: %-6s %-6s %-6s | before: %-6s %-6s %-6s' % ('class', 'mean hit', 'normal', 'elite', 'boss', 'normal', 'elite', 'boss'))
            for c, m, a, b in autos(lv):
                print('%-12s %9.1f |                    %5.1f%% %5.1f%% %5.1f%% |         %5.1f%% %5.1f%% %5.1f%%' % ((c, m) + tuple(a) + tuple(b)))
        return 0
    r = ratios()
    out, med = M.shipped()
    print('level  median dps  median weapon hit  median spell hit  median class hit  hit / dps')
    for lv in M.LEVELS:
        h = class_hits(lv, out)
        print('%5d  %10.0f  %17.0f  %16.0f  %16.0f  %9.3f' % (
            lv, med[lv][0], statistics.median(v[0] for v in h.values()), statistics.median(v[1] for v in h.values()),
            statistics.median(v[2] for v in h.values()), r[lv]))
    print('\nanchors of the config (level, median class hit, median arriving weapon hit):')
    for (lv, hit), (_, wh) in zip(got, wgot):
        print('%5d  %8d  %8d' % (lv, hit, wh))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
