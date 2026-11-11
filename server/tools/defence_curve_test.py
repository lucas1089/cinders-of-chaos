#!/usr/bin/env python3
"""Test of defence_curve.py (O462, O501): the class curve and the weapon curve of monster_defence_config.lua, the engine formula of an
auto attack against what a local server rolled (measured 2026-11-11), the monster's flat armour, the roll, and the rules G1 and G2
(the armour removes the armourTarget of the auto attack damage of the median class, no class loses more than the ceiling): the
rules must hold for the config and fail when a cap or the curve drifts.
usage: python3 -I server/tools/defence_curve_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import defence_curve as D  # noqa: E402

D.FACTOR = D.armour_factor()
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def near(a, b, tol):
    return abs(a - b) <= tol


# the two curves are the derivations (what --check holds CI to)
check(D.config_curve() == D.curve(), 'hitCurve is the derivation of the class damage model')
check(D.config_curve(name='weaponHitCurve') == D.weapon_curve(), 'weaponHitCurve is the derivation of the arriving auto attack')
check([r[0] for r in D.weapon_curve()] == [r[0] for r in D.curve()], 'the two curves have the same levels')
check(all(w > 0 for _, w in D.weapon_curve()), 'every weapon curve row is positive')
check(all(w < c for (_, w), (_, c) in zip(D.weapon_curve()[4:], D.curve()[4:])), 'from level 100 the median weapon hit is under the median class hit')
check(D.armour_factor() == 0.07, 'the armour factor is the shared 0.07')

# the engine formula: Weapons::getMaxWeaponDamage = level / 5 + (skill / 4 + 1) x (attack / 3) x 1.03, a bell from 0
check(D.engine_mean('melee', 100, 70, 22) == 80.0, 'engine: level 100, skill 70, attack 22 rolls to a maximum of 160, mean 80')
check(D.engine_mean('distance', 100, 70, 36) == 134.5, 'engine: a bow rolls from a fifth of the level: (20 + 249) / 2')
check(D.engine_mean('melee', 8, 10, 7) < D.engine_mean('melee', 8, 36, 7), 'engine: a higher skill hits harder')

# the measured arriving hits (SP/o501, 2026-11-11, a local server, the dummy of the level with no armour): kind, level, physical attack of the
# weapon, weapon skill of the character, mean of the arriving physical hit over 100 to 200 hits. The formula with the skill floor
# reproduces them: the model is in the units that arrive (G4)
MEASURED = [
    ('melee', 8, 10, 10, 16.5), ('melee', 20, 10, 20, 18.7), ('melee', 60, 22, 45, 54.5), ('melee', 100, 22, 70, 78.2),
    ('melee', 300, 44, 100, 219.9), ('melee', 500, 51, 120, 319.1), ('melee', 1000, 96, 135, 705.6),
    ('distance', 8, 31, 10, 57.4), ('distance', 20, 31, 20, 64.4), ('distance', 60, 36, 45, 97.5), ('distance', 100, 36, 70, 139.7),
    ('distance', 300, 94, 100, 473.4), ('distance', 500, 109, 120, 629.7), ('distance', 1000, 191, 135, 1349.3),
    ('fist', 8, 7, 10, 11.9), ('fist', 20, 7, 20, 14.0), ('fist', 60, 7, 45, 21.1), ('fist', 100, 7, 70, 31.5),
    ('fist', 300, 7, 100, 62.8), ('fist', 500, 7, 120, 85.9), ('fist', 1000, 7, 135, 145.0),
]
for kind, level, atk, skill, measured in MEASURED:
    got = D.engine_mean(kind, level, max(D.SKILL_FLOOR, skill), atk)
    check(near(got / measured, 1.0, 0.15), 'engine formula vs measured %s level %d: %.1f vs %.1f' % (kind, level, got, measured))
    if skill < D.SKILL_FLOOR:
        check(D.engine_mean(kind, level, skill, atk) < 0.7 * measured, 'the skill floor is needed at skill %d (level %d %s)' % (skill, level, kind))

# the roll: 20 midpoints of a bell between 0 and twice the mean, mean 1
check(len(D.ROLL) == 20 and list(D.ROLL) == sorted(D.ROLL), 'the roll is 20 sorted quantiles')
check(near(sum(D.ROLL) / 20.0, 1.0, 0.005), 'the roll has mean 1')
check(D.ROLL[0] < 0.25 and D.ROLL[-1] < 2.0 and D.ROLL[-1] > 1.7, 'the roll runs from near 0 to under twice the mean')

# the monster's own armour and defence (the engine takes them off before any Lua event)
check(D.xml_flat_at(8) == 5 and D.xml_flat_at(20) == 15 and D.xml_flat_at(500) == 75 and D.xml_flat_at(5000) == 90, 'stock flat armour of the level: anchors and flat outside')
check(D.xml_flat_at(60) < D.xml_flat_at(100) + 1 and D.xml_flat_at(100) < D.xml_flat_at(300), 'stock flat armour never falls with the level')
# O505: after the rule a typical monster keeps the smaller of the stock number and the cap of its level, so under the stock number
check(all(D.flat_at(lv) <= D.xml_flat_at(lv) for lv in (1, 8, 20, 60, 100, 300, 500, 1000, 2000, 5000)), 'the rule never raises the flat armour')
check(D.flat_at(20) == 2 and D.flat_at(100) == 8 and D.flat_at(500) == 23, 'flat armour after the rule: 2 / 8 / 23 at level 20 / 100 / 500')
check(D.flat_at(1) == 1, 'flat armour of level 1 is the cap 1')
hits = D.after_flat(100.0, 0, 0)
check(near(sum(w for _, w in hits), 1.0, 1e-9) and all(near(v, 100.0, 1e-9) for v, _ in hits), 'no armour and no defence: the hit arrives whole')
check(D.after_flat(10.0, 5, 20) == [], 'a hit under the defence never arrives')
arr = D.after_flat(60.0, 10, 10)
check(arr and all(v < 60.0 for v, _ in arr) and sum(w for _, w in arr) <= 1.0, 'a hit that arrives is smaller than the roll')
check(near(sum(v * w for v, w in arr) / sum(w for _, w in arr), 60 - 7.5 - 6.5, 1.0), 'armour 10 and defence 10 take about 14 off a hit of 60')

# the armoured classes: the 15 whose auto attack is a melee or ranged weapon hit
check(len(D.ARMOURED) == 15, 'fifteen classes have an armoured auto attack (the six casters hit with a wand: no armour)')
check(all(c not in D.ARMOURED for c in ('Mystic', 'Elementalist', 'Illusionist', 'Necromancer', 'Lich', 'Bone Lord')), 'no caster is armoured')
for lv in (8, 100, 1000):
    # the stock engine's bare fist (attack 7, what the engine rolls without patch 0091) is the smallest hit, as before O505
    check(D.roll_mean('Monk', lv, True) < D.roll_mean('Warrior', lv) < D.roll_mean('Ranger', lv), 'level %d: stock fist < one-handed < bow roll' % lv)
    # O505: the arriving fist hit is the Monk's own size (its fist attack x meleeDamage, the units the layer measures in on both engines):
    # above a Warrior's, and under a bow's from level 100 (at level 8 the Monk's 40-attack fist beats a level 8 bow too: 81.6 against 53.5)
    check(D.arriving_mean('Warrior', lv) < D.arriving_mean('Monk', lv), 'level %d: one-handed < Monk arriving hit (O505)' % lv)
    if lv >= 100:
        check(D.arriving_mean('Monk', lv) < D.arriving_mean('Ranger', lv), 'level %d: Monk < bow arriving hit (O505)' % lv)

# the share of a hit: A / (A + 0.07 H), a cap, a big hit loses less
check(near(D.share_of(10.0, 100.0), 10.0 / 17.0, 1e-9), 'share_of is A / (A + 0.07 H)')
check(D.share_of(10.0, 1.0, cap=40) == 0.4, 'the cap holds a small hit')
check(D.share_of(1.0, 1000.0, cap=40) < 0.4, 'a big hit loses under the cap')
check(D.share_of(10.0, 10.0) > D.share_of(10.0, 100.0) > D.share_of(10.0, 1000.0), 'a big hit loses less than a small one')
hs = [(10.0, 0.5), (30.0, 0.5)]
check(near(D.expected_share(hs, 5.0), 100 * (10 * 0.5 * (5 / (5 + 0.7)) + 30 * 0.5 * (5 / (5 + 2.1))) / 20.0, 1e-9), 'expected_share is damage weighted')
check(D.expected_share(hs, 5.0, cap=10) <= 10.0 + 1e-9, 'expected_share respects the cap')

# the rules hold for the config ...
check(D.problems() == [], 'G1 and G2 hold for the config: ' + '; '.join(D.problems()[:3]))
check(D.config_caps() == D.CEILING, 'the caps of the config are the ceilings of G2')
check(D.config_caps()['normal'] == 40.0 and D.config_caps()['elite'] == 55.0 and D.config_caps()['boss'] == 65.0, 'the caps are 40 / 55 / 65')
targets = D.config_targets()
check(targets == {'normal': 25.0, 'elite': 40.0, 'boss': 50.0}, 'the goals are the armourTarget 25 / 40 / 50')
# ... and fail when a cap or the curve drifts
loose = {'normal': 60.0, 'elite': 55.0, 'boss': 65.0}
check(any(p.startswith('G2') for p in D.problems(caps=loose)), 'G2 fails when the normal cap is 60')
none = D.problems(caps={'elite': 55.0, 'boss': 65.0})
check(any('cap None' in p for p in none), 'G2 fails when a cap is missing')
tripled = [(lv, h * 3) for lv, h in D.config_curve(name='weaponHitCurve')]
check(any(p.startswith('G1') for p in D.problems(weapon=tripled)), 'G1 fails when the weapon curve is three times too big')
small = [(lv, max(1, h // 4)) for lv, h in D.config_curve(name='weaponHitCurve')]
check(any(p.startswith('G1') or p.startswith('G2') for p in D.problems(weapon=small)), 'G1 or G2 fails when the weapon curve is four times too small')
check(D.problems(wtargets={'normal': 40.0, 'elite': 60.0, 'boss': 70.0}) != [], 'G1 notices weapon targets that are far too high (O505: with the small flat armour the plain goals 25 / 40 / 50 are inside G1 too)')

# the table of the class curve (the state of before O501) against the same arriving hits: the melee classes lose over half at 100
rows = D.autos(100)
by = {r[0]: r for r in rows}
check(len(rows) == 15, 'the table has the 15 armoured classes')
check(by['Warrior'][3][0] > 55.0, 'before: a Warrior at level 100 lost over 55%% of the auto attack on a normal monster (%.1f)' % by['Warrior'][3][0])
# the `before` column is the class curve with no cap (O462) applied to the hits of the model's CURRENT state: the Monk's own size hits (O505), so a
# Monk loses 42.9% there, under a Warrior's 55.7%. What a Monk lost with the stock engine's attack 7 and the stock flat armour (the 90.9% of the
# O501 report, 91.0 here) is pinned from the stock hit
check(near(by['Monk'][3][0], 42.9, 1.5) and by['Monk'][3][0] < by['Warrior'][3][0], 'before column: a Monk at level 100 loses 42.9%% on its own size hit, under the Warrior (%.1f)' % by['Monk'][3][0])
_m7 = D.roll_mean('Monk', 100, True)
_f = D.xml_flat_at(100)
_hits = [(h, w / len(D.ROLL)) for r in D.ROLL for h, w in D.after_flat(_m7 * r, _f, _f)]
_old = D.expected_share(_hits, D.armour_value(D.config_curve(), D.config_targets()['normal'], 100))
check(near(_old, 90.9, 1.0), 'before O501 and O505: a Monk (attack 7, stock flat armour 30) at level 100 lost 90.9%% on a normal monster (%.1f)' % _old)
check(all(r[2][0] <= 40.0 + 1e-9 and r[2][1] <= 55.0 + 1e-9 and r[2][2] <= 65.0 + 1e-9 for r in rows), 'after: no class passes its ceiling at level 100')
check(near(by['Warrior'][2][0], 25.0, 3.0) and near(by['Warrior'][2][1], 40.0, 3.0) and near(by['Warrior'][2][2], 50.0, 3.0), 'after: the Warrior (the median) loses 25 / 40 / 50 within 3 points')
check(by['Ranger'][2][0] < by['Warrior'][2][0], 'after: the bow, a bigger hit, loses less than the sword')
# O501 held the Monk at the cap (40.0): its arriving hit was attack 7. O505: its hit is its own size, so it loses less than the median class
check(near(by['Monk'][2][0], 16.9, 1.0) and by['Monk'][2][0] < by['Warrior'][2][0] < 40.0, 'after: a Monk at level 100 loses 16.9%% (O505), under the Warrior and far under the cap (%.1f)' % by['Monk'][2][0])
check(D.fist_reach('Monk', 100, True, flat=D.xml_flat_at(100))[2] < 8.0, 'a stock engine with the stock flat armour: under 8%% of a level 100 Monk reaches the monster (the 6%% of O501)')

# ---- O505, G5: the flat armour and defence of the monster files --------------------------------------------------------------
# the engine's mean bite (Creature::blockHit): armor 1..3 takes 1, above that uniform(a / 2, a - 1 - a % 2); defense uniform(d / 2, d)
check(D.F.armour_bite(0) == 0 and D.F.armour_bite(1) == 1 and D.F.armour_bite(3) == 1, 'armour bite: 0, then 1 for armor 1 to 3')
check(D.F.armour_bite(4) == (2 + 3) / 2.0 and D.F.armour_bite(10) == (5 + 9) / 2.0, 'armour bite: armor 4 is uniform 2..3, armor 10 uniform 5..9')
check(D.F.defence_bite(0) == 0 and D.F.defence_bite(10) == 7.5 and D.F.defence_bite(1) == 0.5, 'defence bite: uniform(d / 2, d)')
check(D.problems() == [] and D.flat_problems() == [], 'G5 holds for the config: ' + '; '.join(D.flat_problems()[:3]))
rows = D.config_curve(name='flatRollCurve')
check(rows == D.flat_roll_curve(), 'flatRollCurve is the derivation of the median engine roll')
check(len(rows) == 13 and [r[0] for r in rows] == [r[0] for r in D.curve()], 'flatRollCurve has the levels of the other curves')
check(D.config_flat_share() == {'normal': 10.0, 'boss': 20.0} == D.FLAT_SHARE, 'flatShare is 10 / 20 percent in the config and in the tool')
# the cap: more with the level, a boss twice the bite, never a bite over the share + the tolerance
last = 0
for lv in D.LEVELS_CHECK:
    c, cb = D.flat_cap(lv), D.flat_cap(lv, True)
    check(c >= last and cb >= c, 'level %d: the cap does not fall with the level and a boss keeps at least as much' % lv)
    last = c
check(D.flat_cap(20) == 2 and D.flat_cap(100) == 8 and D.flat_cap(500) == 23 and D.flat_cap(1000) == 46, 'the cap is 2 / 8 / 23 / 46 at level 20 / 100 / 500 / 1000')
check(D.flat_cap(100, True) == 16 and D.flat_cap(500, True) == 45, 'a boss keeps about twice: 16 at level 100, 45 at 500')
# G5 fails when the share, the roll rows or the blocked limit drift
check(any(p.startswith('G5') for p in D.flat_problems(rows=[(lv, h * 4) for lv, h in rows], share={'normal': 10.0, 'boss': 20.0}, levels=(100, 500))),
      'G5 fails when the roll rows are four times too big (the cap follows the rows, the real roll does not)')
check(not any('blocked' in p for p in D.flat_problems(rows=[(lv, max(1, h // 8)) for lv, h in rows], levels=(100, 500, 1000))),
      'smaller rows only lower the cap: no more blocked attacks')
check(any('blocked outright' in p for p in D.flat_problems(blocked_max=-1.0, levels=(8,))), 'G5 fails when a class loses attacks to the flat armour above the limit')
check(D.flat_problems(share={'normal': 10.0}) == ['G5 flatShare needs a normal and a boss share'], 'G5 needs both shares')
# before the rule: the stock flat armour blocked a good part of the attacks at the low levels (the typical character; measured on real monsters:
# 77 of 154 attacks at level 8 and 95 of 191 at level 20, 60 and 100, skill 10 / 20 / 45 / 70)
before = max(D.blocked_share(c, 20, D.xml_flat_at(20)) for c in D.NONFIST)
after = max(D.blocked_share(c, 20, float(D.flat_cap(20))) for c in D.NONFIST)
check(before > 20.0, 'before: over 20%% of a level 20 class\'s attacks blocked outright by the stock flat armour (%.1f)' % before)
check(after <= D.BLOCKED_MAX, 'after: at most %.0f%% of a level 20 class\'s attacks blocked (%.1f)' % (D.BLOCKED_MAX, after))
# a launcher meets no defence: the same armour blocks a bow less than a sword of the same roll
check(len(D.arriving('Ranger', 100, 30.0)) >= len(D.arriving('Warrior', 100, 30.0)), 'a bow meets the armour only: it arrives at least as often as a melee hit')

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('defence curve tests: ok')
