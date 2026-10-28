#!/usr/bin/env python3
"""Weapon damage per second across styles (server/tools/weapon_sim.py; server/data/spells/README.md "Weapon damage per
second"; owner debug item 47).

usage: python3 -I server/tools/weapon_sim_test.py

- the formula is the engine's (Weapons::getMaxWeaponDamage) and the model's tier comes from the equipment sets;
- the generated weapon_balance_config.lua is up to date, and a two-handed weapon of one tier deals 1.07 x one hand within
  10% at every level 8 .. 300 (12% at half and one and a half times the skill); sword, axe and club have one tier attack;
- the old flat x1.6 was 12-28% off (the test of the problem), the launchers keep it while RANGED_ALIGN is False and
  come on target when aligned (the solver);
- --audit reads an items.xml and a weapons.xml (synthetic here) and reports the median attack per kind and level band.
"""
import os, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import weapon_sim as W

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


# the engine formula: level 100, skill 100, attack 60, offensive stance: 20 + 26 x 20 x 1.03
check(W.max_hit(100, 100, 60) == round(20 + 26 * 20 * 1.03), 'max hit')
check(W.max_hit(100, 100, 60, 2.0) == round(20 + 26 * 20 * 1.03 / 2), 'max hit, defensive stance')
check(W.max_hit(8, 10, 16) == round(1 + 3.5 * (16 / 3.0) * 1.03), 'max hit at level 8: level / 5 is an integer division')
check(W.mean_hit('bow', 100) > W.max_hit(100, W.skill_at(100), W.attack_of('bow', 100)) / 2.0,
      'a launcher has a minimum of a fifth of the level: its mean is above half the maximum')
check(W.mean_hit('melee1', 100) == W.max_hit(100, W.skill_at(100), W.attack_of('melee1', 100)) / 2.0, 'a melee hit is 0 .. max')

# the problem: the flat 1.6
flat = W.flat_factors()
gaps = [W.spread(lv, flat, 1.0, W.MELEE_STYLES)[1] for lv in W.LEVELS]
check(max(gaps) > 1.20 and min(gaps) > 1.10, 'the flat x1.6 puts two hands 12-28%% ahead (%s)' % ['%.2f' % g for g in gaps])

# the fix
factors = W.solve_factors(False)
check(len(factors['melee2']) == len(W.FACTOR_LEVELS), 'a factor per anchor level')
for lv in range(8, 301):
    ratios, wide = W.spread(lv, factors, 1.0, W.MELEE_STYLES)
    check(abs(ratios['melee2'] - W.TARGET['melee2']) < 0.03, 'level %d: two hands at %.3f, target %.2f' % (lv, ratios['melee2'], W.TARGET['melee2']))
    check(wide <= 1.10, 'level %d: melee styles within 10%% (%.3f)' % (lv, wide))
check(not W.problems(factors), 'problems(): ' + '; '.join(W.problems(factors)[:3]))
check(factors['bow'] == [W.FLAT_BEFORE] * len(W.FACTOR_LEVELS) and factors['crossbow'] == factors['bow'],
      'the launchers keep the flat factor while not aligned')
check(W.RANGED_ALIGN is False, 'RANGED_ALIGN is the owner\'s decision: False as shipped')
aligned = W.solve_factors(True)
for lv in range(8, 301):
    ratios, _ = W.spread(lv, aligned, 1.0, W.STYLES)
    check(abs(ratios['bow'] - 1.0) < 0.05 and abs(ratios['crossbow'] - 1.07) < 0.05,
          'aligned launchers at level %d: bow %.2f crossbow %.2f' % (lv, ratios['bow'], ratios['crossbow']))
check(all(0.5 < v < 2 for style in ('bow', 'crossbow') for v in aligned[style]), 'aligned factors are sane')
for style in ('bow', 'crossbow'):
    check(abs(W.style_factor(factors, style, 100) - 1.6) < 1e-9, style + ': 1.6 kept')
check(W.style_factor(factors, 'melee1', 100) == 1.0, 'one hand is the reference')
check(W.interp((10, 20), (1.0, 3.0), 15) == 2.0 and W.interp((10, 20), (1.0, 3.0), 5) == 1.0
      and W.interp((10, 20), (1.0, 3.0), 50) == 3.0, 'interpolation: linear, flat outside')

# sword, axe and club: one tier attack (the equipment sets have no per-type curve)
check(set(W.G.CURVES) >= {'attack', 'bow', 'hit'}, 'the sets\' curves')
check(W.TYPE_FACTOR == {'sword': 1.0, 'axe': 1.0, 'club': 1.0}, 'no type factor as shipped')

# the config file
text = W.config_text(factors)
check(os.path.isfile(W.CONFIG) and open(W.CONFIG, encoding='utf-8').read() == text,
      'weapon_balance_config.lua is up to date (python3 -I server/tools/weapon_sim.py --write)')
check('typeFactor = {sword = 1, axe = 1, club = 1}' in text, 'typeFactor in the config')

# the auto attack power (weapon_power_config.lua, owner 2026-10-23): up to date, never a cut, lifts the launcher and the
# wand to their share of the reference class's rotation at high levels, leaves the melee weapon alone
power = W.power_factors()
check(os.path.isfile(W.POWER_CONFIG) and open(W.POWER_CONFIG, encoding='utf-8').read() == W.power_text(power),
      'weapon_power_config.lua is up to date (python3 -I server/tools/weapon_sim.py --power --write)')
for kind, row in power.items():
    check(len(row) == len(W.POWER_LEVELS), kind + ': a factor per level')
    check(all(1.0 <= v <= W.POWER_MAX for v in row), kind + ': never a cut, never over the cap: %s' % row)
    check(row == sorted(row), kind + ': never drops with the level')
    share = W.POWER_KINDS[kind][0]
    for lv in (300, 500, 1000, 2000):
        ref = W.reference_dps(W.POWER_KINDS[kind][1], lv)
        got = W.own_dps(kind, lv) * W.interp(W.POWER_LEVELS, row, lv)
        check(got >= min(share, W.own_dps(kind, lv) / ref) * ref * 0.97,
              '%s at level %d: %.0f per second against %.0f%% of %.0f' % (kind, lv, got, share * 100, ref))
check(W.interp(W.POWER_LEVELS, power['distance'], 2000) > W.interp(W.POWER_LEVELS, power['distance'], 1000) > 1.15,
      'the launcher is lifted more and more with the level')
check(W.interp(W.POWER_LEVELS, power['wand'], 300) > 1.5, 'the wand is lifted')
check(all(v <= 1.03 for v in power['melee']), 'melee is at or near its share at every level: at most a 3%% lift: %s' % power['melee'])
check(W.own_dps('distance', 2000) / W.reference_dps('Ranger', 2000) < 0.25,
      'the problem: a launcher is under 25% of a Ranger\'s rotation at level 2000 without the factor')

# --audit on a synthetic server
items = '''<items>
	<item id="1" name="sabre"><attribute key="weaponType" value="sword" /><attribute key="attack" value="30" /></item>
	<item id="2" name="blade"><attribute key="weaponType" value="sword" /><attribute key="attack" value="34" /></item>
	<item id="3" name="great axe"><attribute key="weaponType" value="axe" /><attribute key="attack" value="49" /><attribute key="slotType" value="two-handed" /></item>
	<item id="4" name="war bow"><attribute key="weaponType" value="distance" /><attribute key="attack" value="70" /><attribute key="slotType" value="two-handed" /></item>
	<item id="5" name="star"><attribute key="weaponType" value="distance" /><attribute key="attack" value="40" /></item>
	<item id="6" name="shield"><attribute key="weaponType" value="shield" /><attribute key="defense" value="30" /></item>
</items>
'''
weapons = '''<weapons>
	<melee id="1" level="40"><vocation name="Warrior" /></melee>
	<melee id="2" level="45"><vocation name="Warrior" /></melee>
	<melee id="3" level="90"><vocation name="Warrior" /></melee>
	<distance id="4" level="95"><vocation name="Ranger" /></distance>
	<distance id="5" level="10"><vocation name="Thief" /></distance>
</weapons>
'''
with tempfile.TemporaryDirectory() as tmp:
    os.makedirs(os.path.join(tmp, 'items'))
    os.makedirs(os.path.join(tmp, 'weapons'))
    open(os.path.join(tmp, 'items', 'items.xml'), 'w').write(items)
    open(os.path.join(tmp, 'weapons', 'weapons.xml'), 'w').write(weapons)
    rows = W.audit(tmp)
    got = {(kind, band): (n, median) for kind, band, n, median, _ in rows}
    check(got.get(('sword1', 50)) == (2, 34), 'two one-handed swords up to level 50: median %s' % (got,))
    check(got.get(('axe2', 100)) == (1, 49), 'a two-handed axe')
    check(got.get(('launcher', 100)) == (1, 70), 'a launcher')
    check(not any(k == 'throwing' for k, _ in got), 'throwing weapons are left out')
    check('sword1' in W.audit_report(tmp), 'the report names the kinds')

# --skills (weapon_skill_config.lua, weapon_skill_core.lua): the typical skills are the C4 stats of rotation_sim.py, a
# typical stat deals what it dealt before (no balance jump), and every weapon type hits harder with more skill
import rotation_sim as R  # noqa: E402
cfg = W.skill_config()
check(cfg['skill'] == [(float(a), float(b)) for a, b in R.ANCHORS['skill']], 'typical skill = rotation_sim skill anchors')
check([p for p in cfg['magic'] if p[0] >= 100] == [(float(a), float(b)) for a, b in R.ANCHORS['ml_caster'] if a >= 100],
      'typical magic level = rotation_sim caster anchors from level 100')
check(abs(W.wand_factor(cfg, 8, 0) - 1) < 1e-9, 'a new character (level 8, magic level 0) hits with its wand as before')
check(W.wand_factor(cfg, 1000, 0) == cfg['min'] and W.wand_factor(cfg, 8, 999) == cfg['max'], 'the wand factor is clamped')
for name, _, lv, stat, before, after, lo, hi, blo, bhi in W.skills_rows(cfg):
    check(abs(after - before) < 1e-6, '%s level %d: the typical stat deals what it did (%.1f -> %.1f)' % (name, lv, before, after))
    check(lo < after * 0.92 and hi > after * 1.08, '%s level %d: 0.8x / 1.2x the stat is clearly less / more (%.0f %.0f %.0f)'
          % (name, lv, lo, after, hi))
    if name != 'wand / rod':
        check((blo, bhi) == (lo, hi), '%s: the engine scales it by the skill already (unchanged)' % name)
    else:
        check(blo == bhi == before, 'wand before: flat whatever the magic level')
check('wand / rod' in W.skills_report(), 'the skills report lists the wands')

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('weapon_sim_test: OK')
