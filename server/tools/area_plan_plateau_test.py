#!/usr/bin/env python3
"""Tests of the plateaus and cliffs of the area planner (O744, area_plan_plateau.py, server/README.md "Plateaus and cliffs
(O744)"): the shapes and ramp spots, the cliff and lip sets with the notches, the border pieces, the validator, off by
default (byte for byte), the example examples/highland_hunt.json (three plateaus, two of height 2: ramps, cliff ring,
reach over every floor, map tile audit, look audit), plateaus off water and buildings, the QA cases (a stair taken away,
a ramp into a wall, a lip opened, a top tile cut off) and determinism. Needs luajit (the generator) and numpy (the map
tile audit; skipped without it).

usage: python3 -I server/tools/area_plan_plateau_test.py
"""
import copy
import hashlib
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import area_plan_compile as PC  # noqa: E402
import area_plan_core as C  # noqa: E402
import area_plan_decor as D  # noqa: E402
import area_plan_plateau as PL  # noqa: E402

fails = 0
checks = 0


def ok(cond, what):
    global fails, checks
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


EX = os.path.join(HERE, 'areaplan', 'examples')


def load(name):
    with open(os.path.join(EX, name + '.json'), encoding='utf-8') as f:
        return json.load(f)


def digest(r):
    return hashlib.sha256(r['otbm'] + r['frame_otbm'] + r['spawn_xml'].encode()).hexdigest()


def errors(r):
    return [m for l, m in r['qa'] if l == 'ERROR']


def warns(r):
    return [m for l, m in r['qa'] if l == 'WARN']


cat = C.catalogue(False)
kit = D.kits()
STAIRS_UP, STAIRS_GROUND = kit['brushes']['stairs_up'], kit['brushes']['stairs_down_ground']
mats = C.materials(False)
ok(STAIRS_UP == 3687 and STAIRS_GROUND == 411, 'the stair brush of O740: stone stairs 3687, stairs ground 411')
ok(mats['over_any'].get('mountain') == 'gravel' and set(mats['pieces']['gravel']) == {
    'n', 'e', 's', 'w', 'cnw', 'cne', 'csw', 'cse', 'dnw', 'dne', 'dsw', 'dse'}, 'materials: the mountain edge set by name')
ok(mats['families']['mountain']['grounds'] == [919] and not mats['families']['mountain']['walk'], 'materials: the mountain 919')

# ------------------------------------------------------------------------------------------------ pure parts
ok(PL.spec({}) is None and PL.spec({'plateaus': {'count': 0}}) is None, 'spec: none without plateaus or with count 0')
sp = PL.spec({'plateaus': {'count': 2, 'height': 2}})
ok(sp['height'] == (2, 2) and sp['ramps'] == (1, 2) and sp['size'] == (12, 16), 'spec: defaults %s' % sp)
for seed in range(40):
    w, h = 8 + seed % 13, 8 + (seed * 7) % 13
    G = PL.shape(random.Random(seed), w, h)
    rows = {}
    for x, y in G:
        rows.setdefault(y, []).append(x)
    ok(all(max(xs) - min(xs) + 1 == len(xs) for xs in rows.values()), 'shape %d: every row is one run' % seed)
    ok(sorted(rows) == list(range(h)), 'shape %d: every row holds tiles' % seed)
    ok(len(G) < w * h, 'shape %d: never the full rectangle' % seed)
    ok(PL.shape(random.Random(seed), w, h) == G, 'shape %d: same seed, same shape' % seed)
    spike = [(x, y) for x, y in G if sum((x + dx, y + dy) in G for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))) <= 1]
    ok(not spike, 'shape %d: no one tile spike %s' % (seed, spike[:2]))
box = {(x, y) for x in range(10) for y in range(8)}
ok(PL.rim(box) == {t for t in box if t[0] in (0, 9) or t[1] in (0, 7)}, 'rim of a box')
ok(PL.erode(box, 2) == {(x, y) for x in range(2, 8) for y in range(2, 6)}, 'erode of a box')
ok(len(PL.ring({(0, 0)}, 1)) == 8 and len(PL.ring({(0, 0)}, 2)) == 24, 'ring of a tile')
spots = PL.ramp_spots(box)
ok(spots and all(y == 7 for _x, y in spots) and {x for x, _y in spots} == set(range(2, 8)), 'ramp spots on the south edge %s' % spots)
lv = PL.levels_of(box, [(4, 7)])
ok((3, 7) not in lv[0]['solid'] and (4, 7) not in lv[0]['solid'] and (5, 7) not in lv[0]['solid'] and (2, 7) in lv[0]['solid'],
   'levels: the notch of a ramp is cut out of the cliff')
ok(lv[1]['solid'] == PL.rim(box) - {(3, 7), (4, 7), (5, 7)} and lv[1]['stairs_top'] == {(4, 7)}, 'levels: the lip less the notch')
G2 = PL.erode({(x, y) for x in range(20) for y in range(18)}, PL.LEDGE)
lv2 = PL.levels_of({(x, y) for x in range(20) for y in range(18)}, [(9, 17)], G2, [(9, 12)])
ok(2 in lv2 and lv2[1]['stairs_low'] == {(9, 12)} and lv2[2]['stairs_top'] == {(9, 12)}, 'levels: the second tier and its ramp')
ok((9, 12) not in lv2[1]['solid'] and (8, 12) not in lv2[1]['solid'] and (7, 12) in lv2[1]['solid'],
   'levels: the upper tier stands on the lower top, notched for its ramp')
bd = dict(cfam='mountain', fz={'mountain': 9900, 'st_grass': 3600, 'st_dirt': 3450},
          rules={('mountain', '*'): 'gravel', ('st_grass', '*'): 'st_grass'}, pieces=mats['pieces'])
fam = {(0, -1): 'mountain', (-1, 0): 'mountain', (1, 0): 'st_grass'}
ids, cliff = PL.pieces_for((0, 0), lambda c: fam.get(c, 'st_dirt'), bd)
gv = mats['pieces']['gravel']
ok(cliff == [gv['dnw']] and ids[-1] == gv['dnw'] and ids[0] == mats['pieces']['st_grass']['e'],
   'pieces: grass edge first, then the mountain corner %s' % ids)
ok(PL.pieces_for((0, 0), lambda c: 'st_dirt', bd) == ([], []), 'pieces: none on open ground')

# ------------------------------------------------------------------------------------------------ the validator


def vmsgs(plan):
    return [str(i) for i in C.validate(plan, cat) if i.level == 'ERROR']


hh = load('highland_hunt')
ok(not vmsgs(hh), 'highland_hunt validates: %s' % vmsgs(hh))
p = copy.deepcopy(hh)
p['plateaus']['count'] = 5
ok(any('count' in m for m in vmsgs(p)), 'validator: at most 4 plateaus')
p = copy.deepcopy(hh)
p['plateaus']['size'] = [12, 16]
ok(any('17 tiles a side' in m for m in vmsgs(p)), 'validator: height 2 needs 17 tiles a side')
p['plateaus']['height'] = 1
ok(not vmsgs(p), 'validator: height 1 takes 12-16 %s' % vmsgs(p))
p = copy.deepcopy(hh)
p['plateaus']['size'] = [16, 12]
ok(any('lowest size' in m for m in vmsgs(p)), 'validator: the lowest size first')
p = copy.deepcopy(hh)
p['plateaus']['zones'] = ['ridge', 'nowhere']
ok(any('nowhere' in m for m in vmsgs(p)), 'validator: an unknown zone')
p = copy.deepcopy(hh)
p['plateaus']['heights'] = 1
ok(vmsgs(p), 'validator: unknown keys refused by the schema')
crypt = load('crypt_boss')
p = copy.deepcopy(crypt)
p['plateaus'] = {'count': 1, 'size': [10, 12], 'height': 1}
ok(any('dungeon' in m for m in vmsgs(p)), 'validator: no plateau in a dungeon biome')
cave = load('lava_cave')
p = copy.deepcopy(cave)
p['plateaus'] = {'count': 1, 'size': [17, 18], 'height': 2}
ok(not any('plateau' in m for m in vmsgs(p)), 'validator: height 2 in a cave at z %d %s' % (cat['biomes']['lava']['z'], vmsgs(p)))
p['origin'] = {'x': 14800, 'y': 14800, 'z': 9}
ok(any('above the ground floor' in m for m in vmsgs(p)), 'validator: a cave plateau stays under the ground floor (z 9, height 2)')
p['plateaus']['height'] = 1
ok(not any('plateau' in m for m in vmsgs(p)), 'validator: height 1 in a cave at z 9 %s' % vmsgs(p))
swamp = load('swamp_hunt')
if swamp['floors'] > 1:
    p = copy.deepcopy(swamp)
    z2 = next(z['id'] for z in p['zones'] if z['floor'] == 2)
    p['plateaus'] = {'count': 1, 'size': [10, 12], 'height': 1, 'zones': [z2]}
    ok(any('floor 1 only' in m for m in vmsgs(p)), 'validator: plateaus over floor 1 only')

# ------------------------------------------------------------------------------------------------ off by default
HELD = {'river_hunt': '3c8b41129c07fc74fe8dad82817ded54dab3f5a9bbd3dcced4c7fa8f3e48b824',
        'village_square': '9e5b3054d00efcd17cb0de2e7caa55b2290f31ff8ee8eac5eb93e586a26caca0',
        'swamp_hunt': '4518a68fbb1abd230b7eb99342378f19dc70653fa961c0e70a52831bedf41302'}
for name, want in HELD.items():
    plan = load(name)
    r = PC.compile_plan(plan)
    ok(digest(r) == want, '%s compiles to its held bytes' % name)
    ok('plateaus' not in r['manifest']['stats'] and not r['plateaus'], '%s: no plateau in the manifest' % name)
    if name == 'river_hunt':
        plan['plateaus'] = {'count': 0}
        r0 = PC.compile_plan(plan)
        ok(r0['otbm'] == r['otbm'] and r0['spawn_xml'] == r['spawn_xml'], 'count 0: the same bytes')

# ------------------------------------------------------------------------------------------------ the example
r = PC.compile_plan(hh)
ok(not errors(r) and not warns(r), 'highland_hunt: no QA error or warning: %s %s' % (errors(r)[:3], warns(r)[:3]))
recs = r['plateaus']
ok(len(recs) == 3 and sum(1 for x in recs if x['height'] == 2) >= 1, 'highland_hunt: 3 plateaus, one of height 2 or more')
ok([x['zone'] for x in recs] == ['ridge', 'crags', 'tor'], 'highland_hunt: the zones in turn')
ox, oy, oz = r['origin']
tiles, walk = r['tiles'], r['walk']
gv_ids = set(mats['pieces']['gravel'].values())
edges = [e for l in r['links'] for e in l['edges']] + [(t['at'], t['to']) for t in r['teleports']] + r['plateau_edges']
dist = C.tile_reach(walk, r['arrival'], (), edges)
out = [t for t in walk if t not in dist]
ok(not out, 'highland_hunt: every walkable tile on every floor is reached (%d of %d; first %s)'
   % (len(walk) - len(out), len(walk), sorted(out)[:1]))
zs = sorted({t[2] for t in walk})
ok(zs == [oz - 2, oz - 1, oz], 'highland_hunt: walkable tiles on three floors %s' % zs)
for rec in recs:
    z = rec['z']
    lab = 'plateau %s' % rec['id']
    for t in rec['base']['solid']:
        if tiles[t]['ground'] != 919 or t in walk:
            ok(False, '%s: cliff face %s' % (lab, t))
            break
    else:
        ok(True, '%s: the cliff face is mountain ground' % lab)
    feet = rec['base']['feet']
    ok(feet and all(any(i in gv_ids for i, _a in tiles[t]['items']) for t in feet if t not in walk),
       '%s: the cliff foot carries the gravel edge' % lab)
    ok(all(t not in walk for t in feet if any(i in gv_ids for i, _a in tiles[t]['items'])),
       '%s: a cliff foot tile is not walkable' % lab)
    ok(len(rec['ramps']) >= rec['height'], '%s: a ramp per tier at least (%d)' % (lab, len(rec['ramps'])))
    for lv in rec['levels']:
        built = set(lv['built'])
        open_ = [t for t in built if t in walk and tiles[t]['ground'] != STAIRS_GROUND
                 and any((t[0] + dx, t[1] + dy, t[2]) not in tiles for dx, dy in PL.D8)]
        ok(not open_, '%s z %d: the cliff ring is closed except at the ramps %s' % (lab, lv['z'], open_[:1]))
        ok(len(lv['walk']) >= PL.MIN_TOP, '%s z %d: %d walkable tiles on top' % (lab, lv['z'], len(lv['walk'])))
        ok(all(t in dist for t in lv['walk']), '%s z %d: every top tile reached' % (lab, lv['z']))
        ok(all((t[0], t[1], z) in tiles for t in built), '%s z %d: built over the floor below' % (lab, lv['z']))
    for rp in rec['ramps']:
        ok([i for i, _a in tiles[rp['low']]['items']] == [STAIRS_UP], '%s: stone stairs alone at %s' % (lab, rp['low']))
        ok(tiles[rp['top']]['ground'] == STAIRS_GROUND and not tiles[rp['top']]['items'], '%s: bare stairs ground at %s' % (lab, rp['top']))
        ok(rp['top'][:2] == rp['low'][:2] and rp['top'][2] == rp['low'][2] - 1, '%s: the stairs ground over the stairs' % lab)
        ok(rp['up'] in walk and rp['down'] in walk and rp['landing'] in walk, '%s: the ramp at %s leads walkable tiles' % (lab, rp['low']))
        ok((rp['low'], rp['up']) in r['plateau_edges'] and (rp['top'], rp['down']) in r['plateau_edges'],
           '%s: both floor changes of the ramp' % lab)
        ok(dist.get(rp['up'], 10 ** 6) > dist.get(rp['low'], -1), '%s: the top is reached over the ramp' % lab)
taken = {(s['x'], s['y'], s['z']) for s in r['spawns']}
ramp_tiles = {rp[k] for rec in recs for rp in rec['ramps'] for k in ('low', 'top', 'up', 'down', 'landing')}
ok(not taken & ramp_tiles and not {c['at'] for c in r['chests']} & ramp_tiles, 'highland_hunt: no spawn or chest on a ramp')
ok(sum(1 for s in r['spawns'] if s['z'] < oz) >= 1, 'highland_hunt: spawns stand on top of a plateau')
ok(all(rp['landing'] not in r['dresser'].blocked for rec in recs for rp in rec['ramps']), 'highland_hunt: no decoration on a landing')
man = r['manifest']['stats']['plateaus']
ok(len(man) == 3 and all(m['entry_to_top'] for m in man), 'highland_hunt: the manifest lists the plateaus %s' %
   [(m['id'], m['height'], m['entry_to_top']) for m in man])
print('  highland_hunt: %d walkable tiles on %d floors, %d monsters; %s' % (len(walk), len(zs), r['stats']['monsters'],
      '; '.join('%s %s h%d %s ramps %d' % (m['id'], m['zone'], m['height'], '/'.join(str(t['walkable']) for t in m['top']),
                                           len(m['ramps'])) for m in man)))
ok(digest(PC.compile_plan(load('highland_hunt'))) == digest(r), 'highland_hunt: the same bytes twice')
info = [m for l, m in r['qa'] if l == 'INFO' and m.startswith('ramp:')]
ok(len(info) == sum(len(x['ramps']) for x in recs), 'highland_hunt: one INFO line per ramp')
try:
    import numpy  # noqa: F401
    import audit_map_plans as AMP
    got = AMP.audit_plan(os.path.join(EX, 'highland_hunt.json'), log=lambda *_a: None)
    found = got[1]
    import audit_map_tiles as AMT
    bad = {c: found.count(c) for c in AMT.CODES if found.count(c)}
    ok(not bad, 'highland_hunt: the map tile audit is clean %s' % bad)
except ImportError:
    print('  (numpy missing: the map tile audit of the example is skipped)')
import audit_plan_look as APL  # noqa: E402
ok(not APL.audit_plan(os.path.join(EX, 'highland_hunt.json'))[1], 'highland_hunt: the look audit is clean')

# ------------------------------------------------------------------------------------------------ off water and buildings
p = copy.deepcopy(hh)
p['water'] = {'lakes': [{'zone': 'tor', 'radius': [3, 4]}]}
rw = PC.compile_plan(p)
wet = {k for k, t in rw['tiles'].items() if t['ground'] in (36456, 36457)}
near = [t for rec in rw['plateaus'] for t in rec['clear']
        if any((t[0] + dx, t[1] + dy, t[2]) in wet for dx in range(-1, 2) for dy in range(-1, 2))]
ok(wet and not near, 'with a lake: no plateau or cliff foot next to the water (%d water tiles)' % len(wet))
ok(not [m for m in errors(rw) if 'next to water' in m], 'with a lake: no plateau next to the water %s' % errors(rw)[:2])
p = copy.deepcopy(hh)
p['buildings'] = [{'id': 'lodge', 'kind': 'house', 'zone': 'ridge'}]
rb = PC.compile_plan(p)
foot = {t for b in rb['buildings'] for t in b['foot']}
ok(rb['buildings'] and rb['plateaus'] and not foot & {t for rec in rb['plateaus'] for t in rec['clear']},
   'with a house: the plateaus keep off the building')

# ------------------------------------------------------------------------------------------------ QA cases


def qa_of(tiles_, walk_, dist_=None):
    got = []
    PL.qa(recs, tiles_, walk_, dist_ if dist_ is not None else C.tile_reach(walk_, r['arrival'], (), edges), {},
          lambda m: got.append(m), lambda m: got.append('WARN ' + m), lambda m: None, STAIRS_UP, STAIRS_GROUND, 919)
    return got


ok(not qa_of(tiles, walk), 'QA: the example is clean')
rp = recs[0]['ramps'][0]
t2 = copy.deepcopy(tiles)
t2[rp['low']]['items'] = []
ok(any('not the stone stairs alone' in m for m in qa_of(t2, walk)), 'QA: a ramp without its stairs')
w2 = set(walk) - {rp['up']}
ok(any('runs into a wall' in m for m in qa_of(tiles, w2)), 'QA: a ramp into a wall')
lip = next(t for t in recs[0]['levels'][0]['solid'] if (t[0], t[1] - 1, t[2]) in tiles and t[1] > recs[0]['rect'][1])
w3 = set(walk) | {lip}
ok(any('cliff ring of z' in m for m in qa_of(tiles, w3)), 'QA: a lip tile opened %s' % (lip,))
far = max(recs[0]['levels'][0]['walk'], key=lambda t: dist[t])
d4 = dict(dist)
d4.pop(far)
ok(any('cannot be reached' in m for m in qa_of(tiles, walk, d4)), 'QA: a top tile cut off')
t5 = copy.deepcopy(tiles)
t5[recs[0]['base']['solid'][0]]['ground'] = 103
ok(any('cliff face' in m for m in qa_of(t5, walk)), 'QA: a cliff face that is not the cliff ground')

print('area plan plateaus: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
