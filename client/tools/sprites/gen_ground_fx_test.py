#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_ground_fx_test.py: the ground effect rules (gen_ground_fx.py) on synthetic
rows, and the committed ground_fx.csv / groundfx_data.lua against the real catalogues."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_ground_fx as G

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def row(cat, size='1x1', style='', note='', id=1):
    return dict(id=id, size=size, offset='0,0', note=note, style=style, use='area', cat=cat)


E, B, V, S = 'effects_catalog.csv', 'big_fx_catalog.csv', 'vfx_catalog.csv', 'status_fx_catalog.csv'
# rule 1: procedural floor styles, not the engine's hits
ok(G.tags('fx:fire_nova', row(E, style='nova', note='expanding flame ring'), None) == [1], 'nova')
ok(G.tags('fx:arcane_aura', row(E, style='aura', note='violet glowing ring'), None) == [1], 'aura ring')
ok(G.tags('fx:CONST_ME_GREEN_RINGS', row(E, style='rings', note='engine earth hit'), None) == [], 'engine hit spared')
ok(G.tags('fx:spark', row(E, style='sparks'), None) == [], 'sparks are not floor')
# rule 2: every large effect
ok(2 in G.tags('big_pillar_holy_5', row(B, size='5x5'), None), 'big')
# rule 3: the name, only for effects over one tile
ok(G.tags('holy_seal', row(V, size='3x3'), None) == [3], 'seal by name')
ok(G.tags('fx:blood_rune', row(E, size='2x2', style='circle'), None) == [1, 3], 'rune: rules 1 and 3')
ok(G.tags('string_trap', row(V, size='3x3'), None) == [], 'ring only as a word')
ok(G.tags('nova_x', row(V, size='1x1'), None) == [], '1x1 not by name')
# rule 4: long cover of the body; status words spared
ok(G.tags('frozen', row(V, size='3x3'), {'ms': 1992, 'peak': 0.96}) == [4], 'long cover')
ok(G.tags('hit', row(V, size='3x3'), {'ms': 499, 'peak': 0.9}) == [], 'short cover')
ok(G.tags('word_x', row(S, size='3x3'), {'ms': 900, 'peak': 0.7}) == [], 'status word spared')

# check(): a tagged effect must be ground; rule 3 may be overruled with a reason; unknown names fail
cat = [('fx:ring', row(E, style='nova', id=10)), ('head_ring', row(V, size='3x3', id=11)),
       ('frozen', row(V, size='3x3', id=12)), ('hit', row(V, size='3x3', id=13))]
cover = {12: {'ms': 1000, 'peak': 0.9}}
spec = [dict(name='fx:ring', layer='ground', reason='r'), dict(name='head_ring', layer='above', reason='over the head'),
        dict(name='frozen', layer='ground', reason='r')]
ok(G.check(cat, spec, cover) == [], 'clean spec: %s' % G.check(cat, spec, cover))
bad = [dict(name='fx:ring', layer='above', reason='r')] + spec[1:]
ok(any('fx:ring' in e and 'must be listed as ground' in e for e in G.check(cat, bad, cover)), 'rule 1 enforced')
ok(any('frozen' in e for e in G.check(cat, spec[:2], cover)), 'rule 4 enforced (missing row)')
ok(any('head_ring' in e for e in G.check(cat, spec[:1] + spec[2:], cover)), 'rule 3 needs a row')
ok(any('nope' in e for e in G.check(cat, spec + [dict(name='nope', layer='ground', reason='r')], cover)), 'unknown')
ok(any('twice' in e for e in G.check(cat, spec + [spec[0]], cover)), 'twice')
ok(any('no reason' in e for e in G.check(cat, spec + [dict(name='hit', layer='above', reason='')], cover)), 'reason')
lua = G.lua_text(cat, spec)
ok('[10] = "fx:ring"' in lua and '[12] = "frozen"' in lua and '"head_ring"' not in lua, 'lua lists the ground ids')

# the committed files: the rules hold on the real catalogues and the data file is current
real = G.check(G.catalogue(), G.read_spec(), G.read_cover())
ok(real == [], 'ground_fx.csv: %s' % real[:5])
ok(G.read_cover() != {}, 'ground_fx_cover.csv present')
ok(G.main(['build', '--check']) == 0, 'groundfx_data.lua up to date')
# every directional name of the csv expands to effects that exist
names = {n for n, _ in G.catalogue()}
ok(all(r['name'] in names for r in G.read_spec()), 'every csv name exists')

print('gen_ground_fx_test: %s' % ('ok' if not fails else '%d failed' % fails))
sys.exit(1 if fails else 0)
