#!/usr/bin/env python3
"""Tests of boss_length_model.py (O475): the derivation and the check on synthetic changes.
usage: python3 -I server/tools/boss_length_model_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spell_upgrade_model as _SU  # noqa: E402
_SU.set_mode(False)  # O709: the spell upgrades ship on and a model's default is the upgrades mode; this test holds the switch-off numbers (the model's --check runs both modes in CI)
import boss_length_model as B  # noqa: E402

fails = 0


def ok(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + msg)


ok(abs(B.kept('boss') - 0.60) < 1e-9 and abs(B.kept('normal') - 0.80) < 1e-9, 'a boss lets 0.60 through, a normal monster 0.80')
rows = B.dps_table()
ok([lv for lv, _ in rows] == list(B.DPS_LEVELS) and 850 in B.DPS_LEVELS, 'the table has the 850 row')
ok(all(b[1] > a[1] for a, b in zip(rows, rows[1:])), 'the damage rises with the level')
ok(abs(B.table_dps(rows, 850) - rows[B.DPS_LEVELS.index(850)][1]) < 1e-6, 'table_dps is the row at a row')
ok(abs(B.table_dps(rows, 50) - rows[0][1] / 2) < 1e-6, 'below the first row: scaled by the level')
ok(B.table_dps(rows, 5000) == rows[-1][1], 'above the last row: flat')
hm = B.health_mult(rows, 825, 900, 14800)
ok(abs(hm * 14800 * (1 + 0.0074 * 900) / B.table_dps(rows, 825) - B.BOSS_SECONDS) < 1e-6, 'healthMult gives the boss 150 s')
(d1, e1), (d5, e5) = B.rift_fit()
ok(1.0 < e1 < 1.6 and 1.0 < e5 < 1.6 and d1 > 1000 and d5 > d1, 'the rift fit is a power law above the old numbers (%.0f %.2f %.0f %.2f)' % (d1, e1, d5, e5))
health, factor = B.omen_factor()
ok(abs(health - (B.one_target(1000) * 0.75 - 380) * 318) < 1e-6 and factor > 1, 'the Omen guardian has 318 s at level 1000')
ok(B.problems() == [], 'the committed numbers are the derivation: %s' % B.problems()[:3])
# the arena boss (O637): Malgrath's health is 360 s for five typical characters of level 800, and its ref is the same numbers
ok([a[0] for a in B.ARENA_BOSSES] == ['malgrath_the_drowned_crown.xml'] and B.ARENA_BOSSES[0][2:] == (800, 5, 360, 0.85, 400), 'the arena bosses table')
ah = B.arena_health(800, 5, 360, 0.85, 400)
ok(abs(ah - 360 * (5 * B.one_target(800) * 0.85 - 400)) < 1e-6 and 5.2e6 < ah < 5.3e6, 'the arena health is 360 s of five characters (%.0f)' % ah)
ok(B.committed_health(B.CHAOS_MONSTERS)['malgrath_the_drowned_crown.xml'] == 5240000, 'the XML health is the derivation rounded to 10,000')
ok(B.committed_arena('malgrath, the drowned crown') == (5240000, 400, 17600, 0.85, 5) and B.committed_arena('nobody') is None, 'the ref of the profile')
ok(abs(B.xml_heal('<defense name="healing" interval="2000" chance="8" min="8000" max="12000">') - 400) < 1e-9 and B.xml_heal('') == 0.0, 'the heal a second of a healing defense')
real_arena = B.ARENA_BOSSES
B.ARENA_BOSSES = (('malgrath_the_drowned_crown.xml', 'malgrath, the drowned crown', 800, 5, 400, 0.85, 400),)
ok(any('arena boss malgrath_the_drowned_crown.xml health' in b for b in B.problems()), 'a boss at 400 s instead of 360 is reported')
B.ARENA_BOSSES = real_arena
# the pocket bosses (O704): 300 s alone and 200 s for five of the median class at level 300, the boss heals a tenth of its damage, adds and totems at
# the pocket's size, the world curve of the files in pocketboss_config.lua, and the kill time of every size from the real core
ok(B.POCKET_SECONDS == (300, 200) and B.POCKET_PLAYERS == 5 and B.POCKET_HEAL_SHARE == 0.10, 'the pocket plan: 300 s alone, 200 s for five, heal 10%')
pn = B.pocket_numbers()
ok(pn['worldLevel'] == 300 and len(pn['bosses']) == 5 and pn['limit'] == 900, 'five world pocket bosses at level 300, limit 900 s')
solo, extra = B.pocket_plan(300, 100)
ok(abs(solo - 300 * (B.one_target(300) * 0.85 - 100)) < 1e-6 and 223000 < solo < 224200 and abs(extra - 0.673) < 0.002, 'the pocket health 223,5xx and the curve 0.673 (%.0f %.4f)' % (solo, extra))
ok(B.pocket_problems() == [], 'the committed pocket numbers are the plan: %s' % B.pocket_problems()[:3])
for pb in pn['bosses']:
    ok(pb['xmlHeal'] > B.one_target(300), '%s: the monster file heals %.0f a second, above the median class (%.0f): the reason for the scale' % (pb['name'], pb['xmlHeal'], B.one_target(300)))
    ok(pb['before']['1']['seconds'] is None and pb['after']['1']['seconds'] is not None, '%s: alone it could not be killed before (the heal), 300 s after' % pb['name'])
    ok(abs(pb['after']['1']['seconds'] / 300 - 1) < 0.03 and abs(pb['after']['5']['seconds'] / 200 - 1) < 0.03, '%s: %.0f s alone, %.0f s with five' % (pb['name'], pb['after']['1']['seconds'], pb['after']['5']['seconds']))
    ok(pb['before']['5']['seconds'] > 540, '%s: five took %.0f s before, over 60%% of the 900 s limit' % (pb['name'], pb['before']['5']['seconds']))
import copy  # noqa: E402
real_pocket = list(B._pocket)


def mutated(fn):
    d = copy.deepcopy(real_pocket[0])
    fn(d)
    B._pocket[:] = [d]
    out = B.pocket_problems()
    B._pocket[:] = real_pocket
    return out


ok(any('pocket health alone' in x for x in mutated(lambda d: d['pocket'].update(health=d['pocket']['health'] * 1.1))), 'a pocket health 10% off is reported')
ok(any('pocket health for five' in x for x in mutated(lambda d: d['pocket'].update(perExtra=0.4))), 'a party curve of 0.4 is reported')
ok(any('heals' in x for x in mutated(lambda d: d['bosses'][3]['profile']['pocket'].update(healScale=1.0))), 'a boss that keeps the file heal (Nyxareth, 1,250 a second) is reported')
ok(any('health curve' in x for x in mutated(lambda d: d['bosses'][0].update(settings=d['bosses'][0]['defaults']))), 'the world curve of 3% on a boss file is reported')
ok(any('the median class kills it' in x for x in mutated(lambda d: d['bosses'][1]['after']['1'].update(seconds=420))), 'a kill time of 420 s against 300 is reported')
ok(any('the median class kills it' in x for x in mutated(lambda d: d['bosses'][1]['after']['5'].update(seconds=300))), 'a party of five at 300 s against 200 is reported')
ok(any('floor' in x for x in mutated(lambda d: d['bosses'][2]['after']['3'].update(hpMult=0.6))), 'a factor on the floor is reported')
ok(any('weakest class' in x for x in mutated(lambda d: d['bosses'][0]['weak'].update({'1': 600}))), 'a weakest class over the limit is reported')
ok(any('adds' in x for x in mutated(lambda d: d['bosses'][0]['profile']['adds'][0].update(health=400000))), 'adds of the event\'s size in a pocket are reported')
ok(any('totem' in x for x in mutated(lambda d: [m.update(totemHealth=120000) for m in d['bosses'][3]['profile']['timed'] if 'totemHealth' in m])), 'a totem of the event\'s size is reported')
ok(any('no pocket profile' in x for x in mutated(lambda d: d['bosses'][4].update(profile=None))), 'a world boss with no pocket profile is reported')
ok(any('level' in x for x in mutated(lambda d: d.update(worldLevel=500))), 'a pocket level that is not the world pocket\'s is reported')
# a number off by more than the tolerance is found
real = B.committed_mults
B.committed_mults = lambda: dict(real(), vault=real()['vault'] * 1.1)
ok(any('vault healthMult' in b for b in B.problems()), 'a healthMult 10% off is reported')
B.committed_mults = real
# O703: the mechanics' health factor of the fight's own size (the real core through tools/party_factor_numbers.lua)
import copy  # noqa: E402

nums = B.party_numbers()
ok(B.party_problems(nums) == [] and B.callsite_problems() == [], 'the party factor and the call sites hold: %s' % (B.party_problems(nums) + B.callsite_problems())[:3])
fights = {f['key']: f for f in nums['fights']}
ok(len(fights) == 9 and [f['kind'] for f in nums['fights']].count('dungeon') == 5, 'five dungeon bosses, Gorvath and three Omen guardians')
five = [f['rows']['5'] for f in nums['fights'] if f['kind'] == 'dungeon']
ok(all(abs(r['final'] - 102) < 1.5 for r in five), 'a group of five kills each dungeon boss in 102 s: %s' % [round(r['final'], 1) for r in five])
ok(all(abs(f['rows']['1']['final'] - 150) < 1.5 for f in nums['fights'] if f['kind'] == 'dungeon'), 'alone 150 s')
ok(sum(1 for r in five if r['oldFinal'] < r['final'] - 3) == 4, 'the solo factor left 4 of the 5 dungeon bosses 8-14% too fast with five')
g = fights['gorvath the banner-eater']['rows']
ok(abs(g['1']['final'] - 495) < 2 and abs(g['5']['final'] - 421) < 2 and g['1']['oldFinal'] > 570, 'Gorvath 495 s alone (was %.0f), 421 s with five' % g['1']['oldFinal'])
ok(nums['guild']['enrageAt'] - g['1']['final'] >= B.PARTY_ENRAGE_GAP, 'Gorvath alone is clear of the enrage')
for k in ('sangrith the bloodmoon herald', 'thalcyra the stormbound seer'):
    ok(all(abs(r['hpMult'] - r['soloMult']) < 1e-9 for r in fights[k]['rows'].values()), '%s does not move' % k)
m = fights['morvane the hollow crown']['rows']
ok(abs(m['1']['final'] - m['1']['oldFinal']) < 1e-9 and m['5']['final'] > m['5']['oldFinal'] + 5, 'Morvane: alone as before, five %.0f s (was %.0f)' % (m['5']['final'], m['5']['oldFinal']))
# the old way (the factor of the profile's own party at every size) is reported: dungeon bosses, Gorvath and Morvane
old = copy.deepcopy(nums)
for f in old['fights']:
    for r in f['rows'].values():
        r['hpMult'], r['final'] = r['soloMult'], r['oldFinal']
bad = B.party_problems(old)
ok(any('vault keeper ossrim' in b for b in bad) and any('Gorvath' in b for b in bad) and any('Morvane' in b for b in bad), 'the solo factor on a party is reported')
ok(not any('sangrith' in b or 'thalcyra' in b for b in bad), 'and Sangrith and Thalcyra still pass')
# an Omen guardian that moved is reported
moved = copy.deepcopy(nums)
moved['fights'][6]['rows']['5']['hpMult'] += 0.01
ok(any('must not' in b for b in B.party_problems(moved)), 'a Sangrith that moves is reported')
if fails:
    print('boss_length_model_test: %d failed' % fails)
    sys.exit(1)
print('boss_length_model_test: ok')
