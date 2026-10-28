"""Tests for weakness_model.py: the shape of the model, the config and the pins.

Run: python3 -I server/tools/weakness_model_test.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import weakness_model as W
import rotation_sim as R

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


text = open(W.CONFIG, encoding='utf-8').read()
cfg = W.config()
ok(cfg['levels'] == [300, 800, 1000, 1200], 'config: levels 300, 800, 1000, 1200')
ok(cfg['rampShare'] == 0.8 and cfg['minionTravel'] > 0 and cfg['raisePerCast'] == 1, 'config: ramp inputs read')
ok(set(cfg['autoShare']) == {'melee', 'fist', 'distance', 'caster'}, 'config: an auto share for every kind of stats')
ok(set(cfg['toughness']) == {'Juggernaut', 'Sentinel', 'Samurai'} and all(0 < v < 1 for v in cfg['toughness'].values()),
   'config: the toughness model has the three classes the docs give')
ok(len(cfg['pins']) >= 6 and all(p[0] in ('lowest', 'highest') and p[1] in W.MEASURES and p[2] in ('class', 'line')
                                  for p in cfg['pins']), 'config: pins parse into rank, measure, scope')
ok(all(n in W.CLASSES for p in cfg['pins'] if p[2] == 'class' for n in p[4]) and
   all(n in W.LINES for p in cfg['pins'] if p[2] == 'line' for n in p[4]), 'config: every pinned name is a class or a line')

# reach: the xml range, the script's area, the kit radius, the config table
ok(W.reach('Rift Cleaver', 'kah rhim brak', cfg) == 4, 'reach: the xml range')
titan = next(w for w, (rg, sc) in W.spell_attrs().items() if sc.endswith('knight/titans_wrath.lua'))
ok(W.reach('Colossus Fall', titan, cfg) == 3, 'reach: AREA_CIRCLE3X3 is radius 3')
ok(W.kit_radius('Censer Swing') == 1 and W.kit_radius('No Such Spell') == 0, 'reach: the attack kit radius')
ok(W.reach('Blade Flurry', 'none', cfg) == 1 and W.reach('Nothing', 'none', cfg) is None, 'reach: the config table, else unknown')

# the minion schedule
conf = dict(cfg)
trio = W.minion_arrivals(['warrior', 'warrior', 'mage'], [82.0, 82.0, 110.0], conf)
ok(sorted(a for a, _ in trio) == [0.0, 2.0, 4.0], 'minions: the trio is out in 4 s (cooldown 4 s, support group 2 s)')
one = W.minion_arrivals(['shade'], [200.0], conf)
ok(one == [(0.0, 200.0)], 'minions: one shade is out at once')
army = W.minion_arrivals(['skeleton'] * 6 + ['golem'], [47.0] * 6 + [120.0], conf)
ok(len(army) == 7 and max(a for a, _ in army) == 12.0 and min(a for a, _ in army) == 0.0, 'minions: six skeletons and the golem, 2 s apart')
ok(min(a for a, r in army if r == 120.0) == 0.0, 'minions: the golem, the strongest, comes first')
conf3 = dict(cfg, raisePerCast=3)
ok(max(a for a, _ in W.minion_arrivals(['skeleton'] * 6, [47.0] * 6, conf3)) == 2.0, 'minions: three a cast from corpses halves the time')

# the sums
run = [(1.0, 10.0, 10.0), (3.0, 5.0, 15.0)]
ok(W.cum(run, 0.5) == 0 and W.cum(run, 1.0) == 10.0 and W.cum(run, 2.9) == 10.0 and W.cum(run, 9) == 15.0, 'cum: the running total')

# the rows
t = W.rows(tuple(cfg['levels']))
ok(set(t) == set(W.CLASSES) and all(len(v) == 4 for v in t.values()), 'rows: 21 classes, 4 levels')
ok(all(abs(r['exp']['near'] + r['exp']['mid'] + r['exp']['far'] - 1.0) < 1e-9 for v in t.values() for r in v), 'exposure: the shares add to 1')
ok(all(abs(sum(r['exp']['spells'][k] for k in ('near', 'mid', 'far')) - 1.0) < 1e-9 for v in t.values() for r in v), 'exposure: spells alone add to 1')
ok(all(not r['exp']['unknown'] for v in t.values() for r in v), 'exposure: every spell of every best set has a reach')
ok(all(r['ramp'] >= 0 for v in t.values() for r in v), 'ramp: not negative')
ok(all(r['out'] == 0 for c, v in t.items() if c not in W.MINION_KEY for r in v), 'ramp: only the Necromancer line has minions to raise')
ok(all(r['out'] > 0 for c in W.MINION_KEY for r in t[c]), 'ramp: the Necromancer line raises minions')
ok(t['Mystic'][0]['exp']['far'] > 0.99 and t['Monk'][0]['exp']['near'] > 0.5, 'exposure: a Mystic is all range, a Monk mostly reach 1')
ok(t['Warrior'][0]['exp']['near'] >= cfg['autoShare']['melee'] - 1e-9, 'exposure: a sword reaches 1, so the melee weapon share is near')

# health
ok(abs(W.health_row('Juggernaut', 300, cfg)['per_level'] - 15 / 0.765) < 1e-9, 'health: the Juggernaut 19.6 a level')
ok(abs(W.health_row('Sentinel', 300, cfg)['per_level'] - 14 / 0.81) < 1e-9, 'health: the Sentinel 17.3 a level')
ok(W.health_row('Mystic', 300, cfg)['per_level'] == 5 and W.health_row('Mystic', 300, cfg)['ehp'] == 150 + 299 * 5, 'health: base health + gain')

# mana: the number of rotation_sim.py --mana, the flow on top
spells, model = W.ctx()
r = R.mana_runway(spells, model, 'Templar', 300)
m = t['Templar'][0]['mana']
ok(abs(m['runway_own'] - r[0]) < 1e-9 and m['runway'] > m['runway_own'], 'mana: runway (own) is rotation_sim.mana_runway, the level flow lengthens it')
ok(abs(m['spent'] - r[3] * 60) < 1e-9 and abs(m['drain'] - r[3] * 60 / r[1]) < 1e-9, 'mana: spent a minute and pools a minute')

# lines and ranks
ok(W.ranked(t, 'line', 0, 'health', 'lowest')[0] == 'Mystic', 'rank: the Mystic line has the lowest mean health per level')
ok(W.ranked(t, 'class', 0, 'ramp', 'highest')[0] in ('Bone Lord', 'Shadowfist'), 'rank: the slowest classes')
ok(abs(W.score(t, 'line', 'Mystic', 0, 'health') - (5 + 5 + 7) / 3.0) < 1e-9, 'score: a line is the mean of its classes')

# the intended weaknesses and their levers: five statements, a lever for each
found = W.intended(t, cfg['levels'], cfg)
lev = W.levers(t, cfg['levels'])
ok(len(found) == 5 and all(isinstance(h, bool) for _, h, _ in found) and all(s in lev for s, _, _ in found), 'findings: five statements, each with a lever')
ok(all(1.0 <= f for f in W.mana_factor(t, cfg['levels'])), 'lever: the mana factor is at least 1')

# the check
ok(W.check() == 0, 'check: the current state passes')
ok(W.check(text.replace('"lowest health line 1 Mystic"', '"lowest health line 1 Warrior"')) == 1, 'check: a wrong health pin fails')
ok(W.check(text.replace('"highest ramp line 2 Monk,Necromancer"', '"highest ramp line 2 Mystic,Thief"')) == 1, 'check: a wrong ramp pin fails')
ok(W.check(text.replace('"highest health class 3 Juggernaut,Sentinel,Samurai"', '"highest health class 3 Mystic"')) == 1, 'check: a wrong class pin fails')
ok(W.check_facts(t, cfg['levels'], [('lowest', 'health', 'line', 1, ['Mystic'])]) == [], 'facts: a held pin has no failure')
ok(len(W.check_facts(t, [300], [('highest', 'health', 'class', 1, ['Mystic'])])) == 1, 'facts: a missed pin names the class')

print('weakness_model_test: %s' % ('FAIL' if fails else 'ok'))
sys.exit(1 if fails else 0)
