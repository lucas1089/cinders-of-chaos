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
  regeneration only) at every band and preset level up to 300 (rotation_sim.py --mana);
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

# every class and ascension at every band and every preset level: at most 5 spells, never a snare
for cls, _, _ in R.CLASSES:
    for lv in sorted(set(R.BANDS) | set(R.breakpoints(spells, model, cls))):
        best = R.analyse(spells, model, cls, lv)['best']
        check(best is not None or lv < 100, '%s %d has attack spells' % (cls, lv))
        if best:
            check(len(best['spells']) <= R.MAX_SPELLS, '%s %d: at most 5 spells' % (cls, lv))
            check(not {s.words for s in best['spells']} & utility, '%s %d: no snare in the set' % (cls, lv))

# the cooldown ladder (owner 2026-10-20): every attack spell's cooldown is its rung x 2 s, the group cooldown 2 s, and
# every class's first (level 8) spell is 2 s
final, per_class, _ = R.ladder(spells, model)
for s in spells:
    if s['group'] == 'attack':
        check(s['cooldown'] == final[s['name']], '%s: cooldown %d, the ladder %d' % (s['name'], s['cooldown'],
                                                                                    final[s['name']]))
        check(s['groupcooldown'] == 2000, '%s: group cooldown 2 s' % s['name'])
for cls, rows in per_class.items():
    check(final[rows[0][0]] == 2000, '%s: the first spell %s is 2 s' % (cls, rows[0][0]))
    check(all(rows[i][2] <= rows[i + 1][2] for i in range(1, len(rows) - 1)), '%s: weakest to strongest' % cls)

# the client data is up to date
text = R.client_data(spells, model)
check(open(R.CLIENT_DATA, encoding='utf-8').read() == text,
      'autorotation_data.lua up to date (python3 -I server/tools/rotation_sim.py --write)')

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('rotation_sim_test: OK (%d classes x %d bands)' % (len(R.CLASSES), len(R.BANDS)))
