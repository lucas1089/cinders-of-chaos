#!/usr/bin/env python3
"""Rotations of at most 5 spells (server/tools/rotation_sim.py; server/data/spells/README.md "Rotations").

usage: python3 -I server/tools/rotation_sim_test.py

- every class and ascension at the level bands 100 / 300 / 600 / 1000: a best set of at most 5 attack spells whose
  longest time between two casts is at most 2.0 s (owner, 2026-10-14);
- the simulator: a lone 2 s filler casts every 2 s, a 4 s spell alone leaves 4 s, a 4 s group cooldown or a shared
  secondary group leaves a window, a cast time inside the group cooldown does not;
- the data: rotation_model.csv has a row for every attack spell, stock_spells.csv carries every row of
  spell_timings.csv (patch_spell_timings.py) and patch_spell_timings.py does what the csv says (synthetic spells.xml);
- Radiant Smite's class scale is read from templar_aura_core.lua;
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
    for a in ('cooldown', 'groupcooldown', 'secondarygroupcooldown'):
        if s and (row.get(a) or '').strip():
            check(s[a] == int(row[a]), 'stock_spells.csv %s %s = spell_timings.csv' % (row['name'], a))
check(R.smite_scale() == {23: 0.56, 24: 0.69, 25: 0.56}, 'Radiant Smite scales from templar_aura_core.lua')
smite = [s for s in spells if s['words'] == 'kah sol dyr'][0]
check(smite['cooldown'] == 2000, 'Radiant Smite cooldown 2 s')

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

# every class and ascension at every band: at most 5 spells, never 2 s without one
for cls, _, _ in R.CLASSES:
    for lv in R.BANDS:
        best = R.analyse(spells, model, cls, lv)['best']
        check(best is not None, '%s %d has attack spells' % (cls, lv))
        if best:
            check(len(best['spells']) <= R.MAX_SPELLS, '%s %d: at most 5 spells' % (cls, lv))
            check(best['gap'] <= R.GAP_LIMIT + 1e-9, '%s %d: gap %.2f s <= 2.0 s (%s)' % (
                cls, lv, best['gap'], R.fmt_set(best)))

# the client data is up to date
text = R.client_data(spells, model)
check(open(R.CLIENT_DATA, encoding='utf-8').read() == text,
      'autorotation_data.lua up to date (python3 -I server/tools/rotation_sim.py --write)')

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('rotation_sim_test: OK (%d classes x %d bands)' % (len(R.CLASSES), len(R.BANDS)))
