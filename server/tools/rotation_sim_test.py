#!/usr/bin/env python3
"""Rotations of at most 5 spells (server/tools/rotation_sim.py; server/data/spells/README.md "Rotations").

usage: python3 -I server/tools/rotation_sim_test.py

- every class and ascension at the level bands 15 / 30 / 60 / 100 / 300 / 600 / 1000 and at every level where its
  preset changes: a best set of at most 5 attack spells (the 2.0 s rule was removed, owner 2026-10-17: the order is area
  spells first, then single target, longest cooldown first);
- the snares (utility) are in no set and no preset;
- the simulator: a lone 2 s filler casts every 2 s, a 4 s spell alone leaves 4 s, a 4 s group cooldown or a shared
  secondary group leaves a window, a cast time inside the group cooldown does not;
- the data: rotation_model.csv has a row for every attack spell, stock_spells.csv carries every row of
  spell_timings.csv (patch_spell_timings.py) and patch_spell_timings.py does what the csv says (synthetic spells.xml);
- Radiant Smite's class scale is read from templar_aura_core.lua, Shuriken Toss's from shuriken_toss.lua;
- the mana runway: every class has an attack spell at level 8 and its best set runs 15 s on a full mana pool (vocation
  regeneration only) at every band and preset level up to 1000 (rotation_sim.py --mana; fixed spell costs, 2026-10-21),
  and no spell's fixed cost is above a class's pool at the spell's level (cost_fits); the mana flow curve is read;
- the client's autorotation_data.lua is up to date (--check).
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rotation_sim as R
import patch_spell_timings as P

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


def spell(words, cd, gcd=2000, sec='', seccd=0, cast=0, dmg='100', t5=1, flags=''):
    return ({'id': 1, 'name': words, 'words': words, 'group': 'attack', 'level': 1, 'mana': 0, 'cooldown': cd,
             'groupcooldown': gcd, 'secondarygroup': sec, 'secondarygroupcooldown': seccd, 'params': False,
             'vocations': ['Mystic'], 'chaos': True, 'cast': cast},
            {'dmg': dmg, 't5': t5, 'flags': set(f for f in flags.split(';') if f)})


def gap_of(*defs):
    spells = [d[0] for d in defs]
    model = {d[0]['words']: d[1] for d in defs}
    return R.simulate(R.prepare(spells, model, 'Mystic', 300))[1]


# the simulator
check(gap_of(spell('a', 2000)) == 2.0, 'a 2 s filler: 2 s')
check(gap_of(spell('a', 4000)) == 4.0, 'a 4 s spell alone: 4 s')
check(gap_of(spell('a', 4000), spell('b', 2000)) == 2.0, 'the filler covers the 4 s spell')
check(gap_of(spell('a', 30000, gcd=4000, dmg='999'), spell('b', 2000)) == 4.0, 'a 4 s group lock: 4 s')
check(gap_of(spell('a', 12000, gcd=12000, dmg='999'), spell('b', 2000)) == 12.0, 'the old Sunder Guard: 12 s')
check(gap_of(spell('a', 8000, sec='special', seccd=8000), spell('b', 8000, sec='special', seccd=8000)) == 8.0,
      'one secondary group: 8 s')
check(gap_of(spell('a', 20000, cast=1500, dmg='999'), spell('b', 2000)) == 2.0, 'a 1.5 s cast fits in 2 s')
check(gap_of(spell('a', 20000, cast=2500, dmg='999'), spell('b', 2000)) == 2.5, 'a 2.5 s cast holds the next')

# the data
spells, model = R.load_all()
check(all(s['words'] in model for s in spells if s['group'] == 'attack'), 'a model row for every attack spell')
stock = {s['name']: s for s in spells if not s['chaos']}
for row in P.load():
    s = stock.get(row['name'])
    check(s is not None, 'stock_spells.csv has %s' % row['name'])
    for a in ('cooldown', 'groupcooldown', 'secondarygroupcooldown', 'level', 'mana'):
        if s and (row.get(a) or '').strip():
            check(s[a] == int(row[a]), 'stock_spells.csv %s %s = spell_timings.csv' % (row['name'], a))
check(R.smite_scale() == {23: 0.56, 24: 0.69, 25: 0.56}, 'Radiant Smite scales from templar_aura_core.lua')
smite = [s for s in spells if s['words'] == 'kah sol dyr'][0]
check(smite['cooldown'] == 2000, 'Radiant Smite cooldown 2 s')
check(R.toss_scales() == ({11: 1.33, 12: 1.62, 13: 1.5}, {12: (180, 1.33), 13: (120, 1.33)}, 1.33),
      'Shuriken Toss scales from shuriken_toss.lua')
check(R.toss_for('Ninja', 179) == 1.33 and R.toss_for('Ninja', 180) == 1.62 and R.toss_for('Samurai', 120) == 1.5,
      'Shuriken Toss early scales')
toss = [s for s in spells if s['words'] == 'kah shur'][0]
check(toss['cooldown'] == 2000, 'Shuriken Toss cooldown 2 s')
utility = {w for w, m in model.items() if 'utility' in m['flags']}
check(utility == {'drai snar', 'kah snar'}, 'the snares are utility spells')

# patch_spell_timings.py on a synthetic spells.xml: the attributes change once, the Chaos block never
xml = ('<spells>\n<instant group="attack" name="Sunder Guard" words="kah gro" cooldown="12000" groupcooldown="12000" '
       'script="attack/expose_weakness.lua"></instant>\n'
       '<!-- BEGIN chaos spells -->\n<instant group="attack" name="X" groupcooldown="12000" '
       'script="attack/expose_weakness.lua"></instant>\n<!-- END chaos spells -->\n</spells>\n')
rows = [{'script': 'attack/expose_weakness.lua', 'name': 'Sunder Guard', 'cooldown': '', 'groupcooldown': '2000',
         'secondarygroup': '', 'secondarygroupcooldown': ''}]
new, changes, missing = P.patch_text(xml, rows)
check('groupcooldown="2000"' in new.split('BEGIN')[0], 'patched outside the Chaos block')
check('name="X" groupcooldown="12000"' in new, 'the Chaos block untouched')
check(len(changes) == 1 and not missing, 'one change')
check(P.patch_text(new, rows)[1] == [], 'idempotent')
check(P.patch_text(xml.replace('expose_weakness', 'other'), rows)[2] == ['attack/expose_weakness.lua'],
      'a missing script is reported')

# the mana runway (owner debug items 44 and 45): every class has an attack spell at the start level 8, and every class's best
# set runs MANA_RUNWAY seconds from a full pool at every band and preset level up to MANA_MAX_LEVEL
for cls, _, _ in R.CLASSES:
    first = min(s['level'] for s in spells if s['group'] == 'attack' and cls in s['vocations'] and
                not model[s['words']]['flags'] & set(R.NO_PRESET))
    check(first <= 8, '%s has an attack spell at level 8 (first at %d)' % (cls, first))
    for lv in R.mana_levels(spells, model, cls):
        r = R.mana_runway(spells, model, cls, lv)
        check(r is not None, '%s %d: a mana runway' % (cls, lv))
        if r:
            check(r[0] >= R.MANA_RUNWAY, '%s %d: the best set runs %.1f s on a full pool, under %.0f s (%s)' % (
                cls, lv, r[0], R.MANA_RUNWAY, ' > '.join('%s %d' % c for c in r[4])))
# synthetic pool: 100 mana, 10 regeneration a second is not asserted here; the pool and regeneration come from the data
check(R.mana_pool('Warrior', 8) == 70 and R.mana_pool('Mystic', 8) == 300, 'mana pool at level 8 = start_stats.lua')
check(abs(R.mana_stats()['Warrior'][2] - 5 / 6.0) < 1e-9 and R.mana_stats()['Elementalist'][2] == 5.0,
      'regeneration = gainmanaamount / gainmanaticks')
check(R.MANA_MAX_LEVEL >= 1000 and 1000 in R.mana_levels(spells, model, 'Warrior'), 'the runway is checked up to 1000')
check(not R.cost_fits(), 'every fixed cost fits its classes\' pools: %s' % R.cost_fits()[:3])
check(R.cost_fits([{'name': 'X', 'vocations': ['Warrior'], 'level': 8, 'mana': 71}]) == [('X', 'Warrior', 8, 71, 70)],
      'cost_fits: a cost above the pool is caught')
check(R.flow_regen(99) == 0 and R.flow_regen(100) == 4 and R.flow_regen(1000) == 60 and R.flow_regen(200) == 14,
      'the level regeneration of mana_flow_config.lua')
check(R.shadow_mend_cfg()['mana'] > 0 and R.shadow_mend_rate(300, 30)[2] == R.shadow_mend_rate(1000, 40)[2],
      'Shadow Mend costs the same fixed mana at every level')

# every class and ascension at every band and every preset level: at most 5 spells, never a snare
for cls, _, _ in R.CLASSES:
    for lv in sorted(set(R.BANDS) | set(R.breakpoints(spells, model, cls))):
        best = R.analyse(spells, model, cls, lv)['best']
        check(best is not None or lv < 100, '%s %d has attack spells' % (cls, lv))
        if best:
            check(len(best['spells']) <= R.MAX_SPELLS, '%s %d: at most 5 spells' % (cls, lv))
            check(not {s.words for s in best['spells']} & utility, '%s %d: no snare in the set' % (cls, lv))

# the cooldown ladder (owner 2026-10-20; O176, owner 2026-10-24: the strongest rungs one second apart instead of two): every
# attack spell's cooldown is the cooldown of its rung (2, 4, 6, 7 ... 13 s), the group cooldown 2 s, and every class's
# first (level 8) spell is 2 s; a class's cooldowns rise with the rung and none is under the 2 s attack group cooldown
check(R.LADDER_COOLDOWNS == (2000, 4000, 6000, 7000, 8000, 9000, 10000, 11000, 12000, 13000), 'the ladder: 2, 4, 6, 7 ... 13 s')
check(all(a < b for a, b in zip(R.LADDER_COOLDOWNS, R.LADDER_COOLDOWNS[1:])) and R.LADDER_COOLDOWNS[0] >= int(R.GCD * 1000),
      'the ladder rises and starts at the attack group cooldown')
final, per_class, _ = R.ladder(spells, model)
ULT = {s['name'] for s in spells if s.get('ultimate')}
check(len(ULT) == 7, 'seven ultimates (one per class line)')
for s in spells:
    if s['group'] == 'attack' and s['name'] in ULT:
        # an ultimate has no rung: a fixed cooldown of 35 to 50 s, at level 1200, taught by its quest
        check(s['name'] not in final, '%s: no ladder rung' % s['name'])
        check(R.ULT_COOLDOWN[0] <= s['cooldown'] <= R.ULT_COOLDOWN[1], '%s: cooldown 35 to 50 s' % s['name'])
        check(s['level'] == R.ULT_LEVEL and s['quest'], '%s: level 1200 and a quest spell' % s['name'])
        check(s['groupcooldown'] == 2000, '%s: group cooldown 2 s' % s['name'])
    elif s['group'] == 'attack':
        check(s['cooldown'] == final[s['name']], '%s: cooldown %d, the ladder %d' % (s['name'], s['cooldown'],
                                                                                    final[s['name']]))
        check(s['groupcooldown'] == 2000, '%s: group cooldown 2 s' % s['name'])
for cls, rows in per_class.items():
    check(final[rows[0][0]] == 2000, '%s: the first spell %s is 2 s' % (cls, rows[0][0]))
    # the line spell quest attacks come last whatever they deal, all at QUEST_COOLDOWN
    ranked = [r for r in rows if final[r[0]] != R.QUEST_COOLDOWN or r[0] not in {s['name'] for s in spells if s.get('quest')}]
    check(all(ranked[i][2] <= ranked[i + 1][2] for i in range(1, len(ranked) - 1)), '%s: weakest to strongest' % cls)
    check(all(final[r[0]] == R.QUEST_COOLDOWN for r in rows if r[0] in {s['name'] for s in spells if s.get('quest')} - ULT),
          '%s: its quest spell is at %d ms' % (cls, R.QUEST_COOLDOWN))

# the ultimates (owner 2026-10-28: exempt from the 5-spell cap): in no set, no preset, on top of the best set of a character with
# the quests; the baseline (quest 0, what every balance model measures) has no quest spell at all
QUEST = {s['name'] for s in spells if s.get('quest')}
check(len(QUEST) == 14, 'fourteen quest spells (7 attacks, 7 ultimates)')
for cls, _, _ in R.CLASSES:
    pool = R.prepare(R.class_spells(spells, cls, 1200), model, cls, 1200)
    check(not any(p.name in ULT for p in pool), '%s: the ultimate is not in the pool of the sets' % cls)
    ults = R.prepare(R.class_spells(spells, cls, 1200), model, cls, 1200, True)
    check(len(ults) == 1 and ults[0].name in ULT, '%s: exactly one ultimate' % cls)
    base = R.analyse(spells, model, cls, 1200)['best']
    check(not any(p.name in QUEST for p in base['spells']) and base['ult1'] == 0 and base['dps1'] == base['base1'],
          '%s: the baseline set has no quest spell' % cls)
    full = R.analyse(spells, model, cls, 1200, 3)['best']
    check(len(full['spells']) <= R.MAX_SPELLS and not any(p.name in ULT for p in full['spells']), '%s: 5 spells and no ultimate among them' % cls)
    check(full['ult1'] > 0 and full['dps1'] == full['base1'] + full['ult1'], '%s: the ultimate adds to the damage per second' % cls)
    low = R.analyse(spells, model, cls, 1199, 3)['best']
    check(low['ult1'] == 0 and low['dps1'] == low['base1'], '%s: no ultimate at level 1199' % cls)
    one = R.analyse(spells, model, cls, 1200, 1)['best']
    check(one['ult1'] == 0 and R.score(one['dps1'], one['dps5']) >= R.score(base['dps1'], base['dps5']) - 1e-9,
          '%s: the level 500 attack never lowers the set' % cls)
    check(R.score(full['dps1'], full['dps5']) >= R.score(one['dps1'], one['dps5']) - 1e-9, '%s: the ultimate never lowers it either' % cls)
    q1, q3 = R.quest_gain(spells, model, cls, 1200)
    check(R.Q3_GAIN[0] <= q3 <= R.Q3_GAIN[1], '%s: the ultimate adds %.1f%% at level 1200' % (cls, 100 * q3))
check(R.quest_bad(spells, model) == [], 'the quest gains are in bounds: %s' % R.quest_bad(spells, model)[:3])
sc = R.quest_scales()
check(set(sc) == QUEST, 'quest_spell_scale_config.lua lists exactly the 14 quest spells')
def _vals(f):
    return [v for _, v in f] if isinstance(f, list) else [f]
check(all(0.1 <= v <= 2.0 for row in sc.values() for f in row.values() for v in _vals(f)) and all(len(row) == 3 for row in sc.values()),
      'every quest spell has a factor (0.1 to 2) for its three classes (a number or a curve)')
check(isinstance(sc['Soulflay Wave']['Bone Lord'], list) and isinstance(sc['Moonshard Rain']['Beastmaster'], list),
      'the Bone Lord and the Beastmaster have a factor curve (class identity pass 2026-10-28)')
curve = sc['Soulflay Wave']['Necromancer']
check(R.quest_factor('Soulflay Wave', 'Necromancer', curve[0][0] - 100) == curve[0][1] and
      R.quest_factor('Soulflay Wave', 'Necromancer', curve[-1][0] + 500) == curve[-1][1] and
      abs(R.quest_factor('Soulflay Wave', 'Necromancer', (curve[0][0] + curve[1][0]) / 2) - (curve[0][1] + curve[1][1]) / 2) < 1e-9,
      'a factor curve is flat outside its points and linear between them')
check(R.quest_factor('Soulflay Wave', 'Lich', 900) == sc['Soulflay Wave']['Lich'] and R.quest_factor('Keepfall', 'Mystic', 900) == 1.0,
      'a number is the factor at every level, a class that lacks the spell has 1')
for cls, _, _ in R.CLASSES:
    q1, q3 = R.quest_gain(spells, model, cls, 1200)
    check(R.Q_BOTH[0] <= q1 + q3 <= R.Q_BOTH[1] and R.Q1_EDGE[0] <= q1 <= R.Q1_EDGE[1],
          '%s: both quests add %.1f%% at level 1200, the attack %.1f%%' % (cls, 100 * (q1 + q3), 100 * q1))
# the net gain: the cast takes one attack group cooldown from the set
u = R.with_ultimates({'dps1': 100.0, 'dps5': 100.0}, [type('U', (), {'dmg': 1000.0, 'dmg5': 1000.0, 'cd': 40.0, 'chi': False})()])
check(abs(u['ult1'] - (1000 - 2 * 100) / 40.0) < 1e-9, 'the ultimate adds (hit - 2 s of the set) / cooldown')
check(R.with_ultimates(None, []) is None, 'no set, no ultimate')

# the class spell factor (spell_factor_config.lua): read from the server's table, applied to every spell of the class
check(R.spell_factors() == {1: 0.99, 3: 0.93, 4: 0.99, 5: 0.64, 7: 1.01, 8: 1.05, 10: 0.74, 11: 0.94, 12: 1.14, 13: 1.15, 14: 1.06, 15: 1.07, 17: 0.9,
                            18: 0.79, 19: 1.0, 20: 0.67, 21: 0.88, 22: 0.66, 23: 0.61, 24: 0.76, 25: 0.62},
      'the class spell factors (the end of each curve) of spell_factor_config.lua')
check(R.spell_factor('Mystic') == 0.99 and R.spell_factor('Templar') == 0.61, 'every class has a factor since O176 (the Mystic and the Elementalist got a curve)')
check(R.spell_factor('Thief', 300) == 0.99 and R.spell_factor('Ninja', 300) == 0.88 and R.spell_factor('Samurai', 1000) == 1.15,
      'the Thief line has a curve since C2 (2026-10-24)')
check(R.spell_factor('Templar', 300) == 0.57 and R.spell_factor('Templar', 5000) == 0.61, 'the level curve (O136)')
check(abs(R.spell_factor('Templar', 35) - 0.8055555555555556) < 1e-9 and R.spell_factor('Templar', 1) == 0.6, 'the curve is linear between points')
smite = [s for s in spells if s['name'] == 'Radiant Smite']
t = R.prepare(smite, model, 'Templar', 300)[0].dmg
w = R.evaluate(model[smite[0]['words']]['dmg'], R.stats('Templar', 300))
check(abs(t - 0.57 * w) < 1e-6, 'Templar 300: Radiant Smite x0.57 in the simulation (%.1f, %.1f)' % (t, w))

# the client data is up to date
text = R.client_data(spells, model)
check(open(R.CLIENT_DATA, encoding='utf-8').read() == text,
      'autorotation_data.lua up to date (python3 -I server/tools/rotation_sim.py --write)')

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('rotation_sim_test: OK (%d classes x %d bands)' % (len(R.CLASSES), len(R.BANDS)))
