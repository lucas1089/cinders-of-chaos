#!/usr/bin/env python3
"""Tests of spell_mastery_model.py (O451): the config and support parsers, the free effect rule (the same numbers as
ChaosSupports.freeEffect), the effects on a synthetic spell, hex uptime, and the cap on the real data: every choice at most
+15% of the class damage on its own, on 1 and on 5 targets, and every class of the line can cast the spell.
usage: python3 -I server/tools/spell_mastery_model_test.py"""
import os
import sys
from types import SimpleNamespace

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rotation_sim as R  # noqa: E402
import spell_mastery_model as M  # noqa: E402

fails = 0


def ok(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + msg)


def near(a, b, msg, tol=1e-9):
    ok(abs(a - b) <= tol, '%s: %r ~ %r' % (msg, a, b))


cfg = M.load_config()
sup = M.load_supports()
ok(cfg['tier'] == 1 and cfg['strength'] == 75, 'tier 1, strength 75')
ok([c['id'] for c in cfg['choices']] == list(range(1, 21)), '20 choices with ids 1..20')
for c in cfg['choices']:
    ok(c['support'] in sup and c['support'] in cfg['reduce'], '%s: a support the config reduces' % c['name'])
    ok(1 <= c['effect'] <= 7, '%s: the effect position' % c['name'])
ok(len(sup) == 20, '20 supports parsed (%d)' % len(sup))
ok(sup['fork']['values2'][0] == 35 and sup['quickening']['values'][0] == 6 and sup['hex']['values'][0] == 3, 'Common numbers')
ok(sup['dawnbrand']['group'] == 'brand' and sup['dawnbrand']['element'] == 'holy', 'a brand: group and element')

# the free effect: the rune's numbers at tier 1, the reduced fields at 75% rounded down (data/lib/chaos_supports.lua freeEffect)
want = {'fork': (1, 26), 'breadth': (1, 26), 'shatter': (15, None), 'quickening': (4, None), 'hex': (2, None), 'echo': (11, 50),
        'dawnbrand': (15, None), 'gravebrand': (15, None), 'stormbrand': (15, None)}
for key, (v, v2) in want.items():
    e = M.free_effect(cfg, sup, key)
    ok(e['value'] == v and e['value2'] == v2, '%s: free effect %r' % (key, e))
    rune = sup[key]
    ok(e['value'] <= rune['values'][0], '%s: value never above the Common rune' % key)
    ok(e['value2'] is None or e['value2'] <= rune['values2'][0], '%s: value2 never above the Common rune' % key)
ok({c['support'] for c in cfg['choices']} == set(want), 'the choices use exactly the supports of the table')

# one cast of a synthetic spell
def spell(dmg, t, cd=10.0, gcd=2.0):
    return SimpleNamespace(dmg=float(dmg), dmg5=float(dmg) * t, cd=cd, gcd=gcd, cast=0.0, id=1, words='x')


one = spell(1000, 1)
near(M.spell_change('fork', {'value': 1, 'value2': 26}, one)[1], 0.26, 'fork on a single spell, 5 targets')
near(M.spell_change('fork', {'value': 1, 'value2': 26}, one)[0], 0.0, 'fork on one target: nothing')
near(M.spell_change('shatter', {'value': 15, 'value2': None}, one)[1], 0.60, 'shatter: 4 neighbours x 15%')
three = spell(1000, 3)
near(M.spell_change('breadth', {'value': 1, 'value2': 26}, three)[1], 2 * 0.26 / 3, 'breadth: 2 missed enemies')
near(M.spell_change('breadth', {'value': 1, 'value2': 26}, spell(1000, 5))[1], 0.0, 'breadth: nothing missed when the pack is hit')
near(M.spell_change('dawnbrand', {'value': 15, 'value2': None}, three)[0], 0.15, 'brand: +15%')
near(M.spell_change('echo', {'value': 11, 'value2': 50}, three)[0], 0.055, 'echo: 11% x 50%')
m = M.modified('quickening', {'value': 4, 'value2': None}, one)
near(m.cd, 9.6, 'quickening 4% of 10 s')
near(M.modified('quickening', {'value': 90, 'value2': None}, one).cd, 1.0, 'never below 1 s')
near(M.spell_rate_change('quickening', {'value': 4, 'value2': None}, one)[0], 10 / 9.6 - 1, 'a spell cast on its cooldown')
near(one.cd, 10.0, 'the original spell is not changed')
# hex: uptime 4 s over the seconds between two casts; 5 targets: the share of the pack the spell hits
rot = [SimpleNamespace(id=1, words='x', dmg=1.0, dmg5=1.0), SimpleNamespace(id=2, words='y', dmg=1.0, dmg5=5.0)]
casts = [(i * 10.0, 'x') for i in range(12)]  # every 10 s over 120 s
h = M.hex_gain(rot, 1, {'value': 2}, casts)
near(h[0], 0.02 * 0.4, 'hex 2% for 4 s of every 10 s'); near(h[1], 0.02 * 0.4 / 5, 'hex on one of 5 targets')
h = M.hex_gain(rot, 2, {'value': 2}, [(i * 2.0, 'y') for i in range(60)])
near(h[0], 0.02, 'a spell cast every 2 s keeps the hex up'); near(h[1], 0.02, 'a spell that hits the pack hexes it all')
ok(M.hex_gain(rot, 1, {'value': 2}, [])[0] == 0.0, 'a spell never cast hexes nothing')

# every class of the line has the spell in its kit (the choice is the same for the three classes of the line)
spells, model = R.load_all()
for c in cfg['choices']:
    for cls in M.line_classes(c['line']):
        have = [s for s in spells if s['id'] == c['spell'] and s['group'] == 'attack' and cls in s['vocations']]
        ok(have, '%s: %s casts spell %d' % (c['name'], cls, c['spell']))
        ok(have and have[0]['level'] <= 1000, '%s: %s has it by level 1000' % (c['name'], cls))
        ok(have and not model[have[0]['words']]['flags'] & {'skip', 'utility', 'ultimate'},
           '%s: the spell is a rotation spell, no utility or ultimate' % c['name'])

# the cap, on the real data: at most +15% of the class damage on its own, on 1 and on 5 targets; no negative gain
bad = M.problems()
ok(not bad, 'the cap: ' + '; '.join(bad))
for c in cfg['choices']:
    nums, own = M.choice_numbers(c)
    ok(nums, '%s: at least one class and level counts' % c['name'])
    s = M.summary(c, nums, own)
    ok(0 <= s['class_one'] <= M.CAP and 0 <= s['class_five'] <= M.CAP, '%s: class gain %.3f / %.3f' % (c['name'], s['class_one'], s['class_five']))
    ok(s['spell_one'] >= 0 and s['spell_five'] >= 0, '%s: the spell does not lose' % c['name'])
    ok(s['class_one'] + s['class_five'] > 0, '%s: the choice does something on 1 or 5 targets' % c['name'])
    # the owner's cap of +40% in a specialty holds with room: even the largest choice is under the cap of this model
    ok(max(s['class_one'], s['class_five']) <= 0.15, '%s: at most +15%%' % c['name'])

if fails:
    print('%d failures' % fails)
    sys.exit(1)
print('spell_mastery_model_test: ok')
