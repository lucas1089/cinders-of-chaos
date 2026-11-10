#!/usr/bin/env python3
"""Tests of card_set_model.py (O453): the parsers, the value of a build on synthetic shares, the check on synthetic changes.
usage: python3 -I server/tools/card_set_model_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import card_set_model as M  # noqa: E402

fails = 0


def ok(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + msg)


cfg = M.load_config()
ok(len(cfg['families']) == 11, '11 convert lines (%d)' % len(cfg['families']))
# O473 (2026-11-10): the cap is 4 raw percent of the one additive damage pool (damage_pool_config.lua sources.cardSets), was 6
ok(cfg['need'] == 3 and cfg['cap'] == 4, 'a set is 3 cards, the damage part cap is 4 (a raw pool percent)')
ok(set(cfg['sets']) == {'fire', 'earth', 'death', 'holy', 'energy'}, 'five sets: %s' % sorted(cfg['sets']))
ok({r['kind'] for r in cfg['sets'].values()} == {'damage', 'poison', 'leech', 'heal', 'slow'}, 'five kinds, one each')
for el, row in cfg['sets'].items():
    if row['kind'] in ('damage', 'poison'):
        ok(0 < row['pct'] <= cfg['cap'], '%s: the damage part is in (0, cap]' % el)
for fam in cfg['families']:
    ok(len(fam['elements']) == 4 and fam['spell'] in cfg['lines'] and fam['spells'][0] == fam['spell'],
       '%s: four elements, a class list, its own name first' % fam['spell'])
ok(cfg['lines']['Reaping Gyre'] == ['Warrior', 'Juggernaut', 'Berserker'], 'the lines of Reaping Gyre')
ok(len(cfg['lines']['Frostfall Rune']) == 21, 'every class casts the Frostfall Rune')
ok(cfg['families'][1]['spells'] == ['Rime Bloom', 'Marrow Bolt', 'Soulrend Beam'], 'a line with two more spells')

data = M.spell_data()
ok(data['Doomtide'][0] == 'fire' and data['Reaping Gyre'][0] == 'physical' and 5 in data['Doomtide'][1], 'spell elements and vocations')
mult, n = M.resistances()
ok(n > 50 and set(mult) == set((M.PHYS,) + M.ELEMENTS), 'the resistance table covers every element (%d files)' % n)
ok(all(0.5 < v <= 1.2 for v in mult.values()), 'the multipliers are plausible')

# the value of a build on made-up shares: a physical spell with half of the damage moved to Fire loses what Fire resists more
M.SPELLS_NAT.clear()
M.SPELLS_NAT.update({'Reaping Gyre': 'physical', 'Earthbreaker': 'physical'})
shares = {'Reaping Gyre': (0.5, 0.4), 'Earthbreaker': (0.5, 0.6)}
fake = {e: 1.0 for e in (M.PHYS,) + M.ELEMENTS}
fake['fire'] = 0.9
zero = [0.0, 0.0]
v = M.value('Warrior', cfg, fake, shares, {}, zero)
ok(v == [0.0, 0.0], 'no card: no change')
v = M.value('Warrior', cfg, fake, shares, {'Reaping Gyre': 'fire'}, zero)
ok(abs(v[0] - 0.5 * (0.9 - 1)) < 1e-9 and abs(v[1] - 0.4 * (0.9 - 1)) < 1e-9, 'a line to Fire: the share x the change of the multiplier')
v = M.value('Warrior', cfg, fake, shares, {'Reaping Gyre': 'fire', 'Earthbreaker': 'fire'}, zero, 'fire')
ok(abs(v[0] - (-0.1 + 0.035 * 1.0)) < 1e-9, 'a Fire set: the whole damage is Fire, +3.5%% of it (O475: 4 before) on top of the loss: %s' % (v,))
v = M.value('Warrior', cfg, fake, shares, {'Reaping Gyre': 'fire', 'Earthbreaker': 'fire'}, zero, 'death')
ok(abs(v[0] - (-0.1)) < 1e-9, 'a Death set has no damage part: only the loss')
v = M.value('Warrior', cfg, fake, shares, {}, [0.1, 0.2])
ok(v == [0.1, 0.2], 'the extras (legendary, utility) are added')

# the shipped state passes; the check fires on synthetic changes
rows, mult, n = M.class_rows()
ok(len(rows) == 21, '21 classes')
ok(M.problems(rows, mult) == [], 'the shipped state passes: %s' % M.problems(rows, mult)[:3])
for r in rows:
    ok(r['mixed'] is not None and r['set'] is not None, '%s: both builds found' % r['class'])
    ok(r['legendary'][0] > 0.02 and r['legendary'][1] > 0.02, '%s: a legendary card is worth over 2%%' % r['class'])
    ok(abs(r['cap'][0] - 0.04 * r['dps'][0]) < 1e-6, '%s: the worst case is 4%% of the damage per second' % r['class'])
    for i in (0, 1):
        ok(abs((1 + r['set']['v'][i]) / (1 + r['mixed']['v'][i]) - 1) <= M.TOLERANCE, '%s: the set is within 10%% of the mixed build' % r['class'])
    ok(r['set']['cards'] >= 3 or r['set']['element'] is None, '%s: a set takes 3 cards or more' % r['class'])
ok(rows[0]['class'] == 'Warrior' and rows[0]['line'] == 'Warrior', 'the order of the classes')
# every class line has a class whose set is no better than the best mixed build
ok(len({r['line'] for r in rows if r['set']['v'][0] <= r['mixed']['v'][0] + 1e-9}) >= 3, 'three class lines have a set that costs something or nothing')

orig = M.load_config


def with_pct(fire, earth):
    def patched(path=M.CONFIG):
        c = orig(path)
        c['sets']['fire']['pct'] = fire
        c['sets']['earth']['pct'] = earth
        return c
    return patched


M.load_config = with_pct(12, 12)
rows2, mult2, _ = M.class_rows()
bad = M.problems(rows2, mult2)
ok(any('above the cap' in b for b in bad), 'a damage part of 12% is above the cap')
ok(any('strictly better' in b or 'lower it' in b for b in bad), 'a damage part of 12% puts a set ahead: lower it')
M.load_config = with_pct(2, 2)
rows3, mult3, _ = M.class_rows()
ok(M.problems(rows3, mult3) == [], 'a smaller damage part passes')
M.load_config = orig

print('card_set_model_test: %s' % ('ok' if not fails else '%d failures' % fails))
sys.exit(1 if fails else 0)
