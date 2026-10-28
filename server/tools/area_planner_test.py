#!/usr/bin/env python3
"""Tests of the area planner (server/tools/area_planner.py, area_plan_*.py) without the live data or a sprite pair (CI):
the schema and game-rule validator, the reachability maths, the layout, the compiler (the three example plans compile
and pass QA, the same seed gives the same bytes, the OTBM reads back), the pair 24 switch, the knowledge base and the AI
adapter's fix loop on a fake endpoint. Needs LuaJIT (LUAJIT=... to point elsewhere).

    python3 -I server/tools/area_planner_test.py
"""
import copy, json, os, re, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import area_plan_core as C
import area_plan_compile as PC
import area_plan_kb as KB
import area_plan_ai as AI

checks = fails = 0


def ok(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


EX = os.path.join(HERE, 'areaplan', 'examples')
examples = {f[:-5]: json.load(open(os.path.join(EX, f))) for f in sorted(os.listdir(EX)) if f.endswith('.json')}
ok(sorted(examples) == ['crypt_boss', 'lava_cave', 'swamp_hunt', 'temple_throne'], 'four example plans: %s' % sorted(examples))
NUMERIC = {'size', 'floors', 'level', 'seed', 'count', 'respawn', 'pack', 'width', 'at', 'x', 'y', 'z', 'gold',
           'experience', 'chest_action', 'floor'}


def numbers_outside(v, key=None):
    """numbers under keys that are not plain quantities (an item id would show up here)"""
    if isinstance(v, dict):
        return [n for k, x in v.items() for n in numbers_outside(x, k)]
    if isinstance(v, list):
        return [n for x in v for n in numbers_outside(x, key)]
    if isinstance(v, int) and not isinstance(v, bool) and key not in NUMERIC:
        return [(key, v)]
    return []
cat = C.catalogue(False)
ok({'swamp', 'crypt', 'lava', 'forest', 'ice', 'cave'} <= set(cat['biomes']), 'the biomes of the catalogue')


def msgs(plan, level='ERROR'):
    return [str(i) for i in C.validate(plan, cat) if i.level == level]


def has(plan, text, level='ERROR'):
    m = msgs(plan, level)
    return any(text in x for x in m), m


# ------------------------------------------------------------------------------------------------ the examples
for name, plan in examples.items():
    ok(not msgs(plan), name + ': validates: %s' % msgs(plan))
    ok(not numbers_outside(plan), name + ': no item id in the plan: %s' % numbers_outside(plan)[:3])

base = examples['crypt_boss']

# ------------------------------------------------------------------------------------------------ schema
p = copy.deepcopy(base)
del p['zones']
r, m = has(p, 'missing "zones"')
ok(r, 'schema: a missing key is named: %s' % m)
p = copy.deepcopy(base)
p['zones'][0]['item'] = 1740
r, m = has(p, 'unknown key "item"')
ok(r, 'schema: an item id key is refused: %s' % m)
p = copy.deepcopy(base)
p['size'] = [300, 20]
r, m = has(p, 'above the maximum 200')
ok(r and any('below the minimum 24' in x for x in m), 'schema: the size limits: %s' % m)
p = copy.deepcopy(base)
p['decoration'] = 'lots'
r, m = has(p, 'use one of sparse, normal, dense')
ok(r, 'schema: an enum lists its values: %s' % m)
p = copy.deepcopy(base)
p['schema'] = 'chaos-area-plan/2'
ok(has(p, 'must be "chaos-area-plan/1"')[0], 'schema: the version')

# ------------------------------------------------------------------------------------------------ game rules
p = copy.deepcopy(base)
p['paths'] = [x for x in p['paths'] if x['to'] != 'reliquary']
r, m = has(p, 'zone reliquary cannot be reached from the entry vestibule')
ok(r and any('"from": "' in x for x in m), 'reach: an unreached zone, with a path to add: %s' % m)
p = copy.deepcopy(base)
p['connections'] = [c for c in p['connections'] if c['type'] != 'stairs']
r, m = has(p, 'cannot be reached')
ok(r, 'reach: floor 2 without its stairs: %s' % m)
p = copy.deepcopy(base)
p['connections'][0] = {'type': 'hole', 'from': 'landing', 'to': 'stairwell'}
ok(has(p, 'a hole leads down')[0], 'a hole from below is refused')
p = copy.deepcopy(base)
p['connections'][0]['type'] = 'hole'
r = C.plan_reach(p)
ok('landing' in r and r['landing'] == 4, 'reach: a hole leads down (hops %s)' % r.get('landing'))
p2 = copy.deepcopy(p)
p2['entry']['zone'] = 'vestibule'
p2['paths'].append({'from': 'landing', 'to': 'catacomb'})
ok('stairwell' in C.plan_reach(p2), 'reach: floor 1 itself still reached')
p = copy.deepcopy(base)
p['connections'].append({'type': 'teleport', 'from': 'hall', 'to': 'nowhere'})
r, m = has(p, 'no zone "nowhere"')
ok(r, 'a teleport target must exist: %s' % m)
p = copy.deepcopy(base)
p['connections'].append({'type': 'teleport', 'from': 'hall', 'to': 'throne'})
r, m = has(p, 'the boss room throne has 2 entrances')
ok(r, 'boss room: a second way in: %s' % m)
p = copy.deepcopy(base)
p['connections'].append({'type': 'teleport', 'from': 'throne', 'to': 'hall', 'two_way': False})
ok(not msgs(p), 'boss room: a one-way teleport out is no entrance: %s' % msgs(p))
p = copy.deepcopy(base)
p['spawns'].append({'zone': 'vestibule', 'monster': 'Bone Knight', 'count': 2})
ok(has(p, 'spawn in vestibule, a protection zone')[0], 'no spawn in a protection zone')
p = copy.deepcopy(base)
p['spawns'][0]['monster'] = 'Bone Knigth'
r, m = has(p, 'no monster "Bone Knigth"')
ok(r and any('Bone Knight' in x for x in m), 'an unknown monster with the close name: %s' % m)
p = copy.deepcopy(base)
p['spawns'][0]['monster'] = 'Rat'
r, m = has(p, 'Rat is level 4; the band 150-280 takes monsters of level 120-299')
ok(r and any('pick from:' in x for x in m), 'tier: a monster too weak for the band, with picks: %s' % m)
p = copy.deepcopy(base)
p['level'] = [40, 400]
ok(has(p, 'spans 4 level tiers')[0], 'tier: a band over four tiers')
# the open top tier (800+): the bounty window ends at 1500, a band above it takes monsters up to its top + 100
ok(C.tier_window(900, 1100)[2] == 1500, 'tier: the top tier keeps the bounty window up to 1500')
ok(C.tier_window(1300, 1450)[2] == 1550, 'tier: a 1300-1450 band takes monsters up to 1550')
ok(C.tier_window(1750, 2000)[1:] == (640, 2100), 'tier: a 1750-2000 band takes monsters up to 2100')
ok(C.tier_window(150, 280)[2] == 299, 'tier: a closed tier keeps its window')
p = copy.deepcopy(base)
p['zones'][5]['floor'] = 1
p['paths'].append({'from': 'landing', 'to': 'hall'})
ok(has(p, 'path landing-catacomb joins floor 1 and floor 2')[0], 'a path cannot change floors')
p = copy.deepcopy(base)
p['floors'] = 1
ok(has(p, 'floor 2 but the area has 1 floor')[0], 'a zone below the last floor')
p = copy.deepcopy(base)
p['entry']['zone'] = 'landing'
ok(has(p, 'players arrive on floor 1')[0], 'the entry is on floor 1')
p = copy.deepcopy(base)
p['zones'][1]['size'] = [40, 40]
p['size'] = [40, 40]
ok(has(p, 'too big for a 40x40 area')[0], 'a zone bigger than the area')
p = copy.deepcopy(base)
p['zones'][0]['at'] = [10, 10]
p['zones'][1]['at'] = [12, 12]
ok(has(p, 'overlap')[0], 'fixed zones may not overlap')
p = copy.deepcopy(base)
p['npcs'] = [{'zone': 'hall', 'name': 'Nobody Here'}]
ok(has(p, 'no NPC "Nobody Here"')[0] and has(p, 'outside a protection zone', 'WARN')[0], 'NPC name and PZ')
p = copy.deepcopy(examples['swamp_hunt'])
p['biome'] = 'tundra'
ok(has(p, 'unknown biome "tundra"')[0], 'an unknown biome')

# ------------------------------------------------------------------------------------------------ maths
walk = {(x, y, 7) for x in range(0, 5) for y in range(0, 3)} | {(x, y, 8) for x in range(0, 3) for y in range(0, 3)} \
    | {(20, 20, 7), (21, 20, 7)}
d = C.tile_reach(walk, (0, 0, 7))
ok(d.get((4, 2, 7)) == 4 and (0, 0, 8) not in d, 'tile reach: 8-neighbour steps on one floor')
d = C.tile_reach(walk, (0, 0, 7), links=[((2, 1, 7), (2, 1, 8), (2, 2, 7))])
ok(d.get((2, 1, 8)) == 3 and d.get((0, 0, 8)) == 5, 'tile reach: down a hole (%s)' % d.get((2, 1, 8)))
d = C.tile_reach(walk, (0, 0, 8), links=[((2, 1, 7), (2, 1, 8), (2, 2, 7))])
ok(d.get((2, 2, 7)) == 3, 'tile reach: up a ladder to the tile south of the hole')
d = C.tile_reach(walk, (0, 0, 8), links=[((2, 1, 7), (2, 1, 8), None)])
ok((2, 2, 7) not in d, 'tile reach: a hole without a ladder is one way')
d = C.tile_reach(walk, (0, 0, 7), teleports=[((4, 2, 7), (20, 20, 7))])
ok(d.get((21, 20, 7)) == 6, 'tile reach: a teleport (%s)' % d.get((21, 20, 7)))
room = {(x, y, 7) for x in range(10, 16) for y in range(10, 16)}
door1 = {(x, 13, 7) for x in range(4, 10)}
door2 = {(13, y, 7) for y in range(16, 20)}
ok(C.openings(room | door1, (10, 10, 15, 15), 7) == 1, 'openings: one corridor')
ok(C.openings(room | door1 | door2, (10, 10, 15, 15), 7) == 2, 'openings: two corridors')
wide = {(x, y, 7) for x in range(4, 10) for y in range(12, 15)}
ok(C.openings(room | wide, (10, 10, 15, 15), 7) == 1, 'openings: a 3-wide corridor is one way in')
ok(C.route_cells([(0, 0), (4, 0), (4, 3)], 1) == {(x, 0) for x in range(5)} | {(4, y) for y in range(4)}, 'route cells, width 1')
ok(len(C.route_cells([(0, 5), (9, 5)], 3)) == 31, 'route cells, width 3 (the turn adds one)')
mean, mx, n = C.screen_density({(x, y) for x in range(30) for y in range(11)}, {(1, 1): 3, (16, 2): 1}, 0, 0, 30, 11)
ok((mean, mx, n) == (2.0, 3, 2), 'monsters per screen: %s' % ((mean, mx, n),))

# ------------------------------------------------------------------------------------------------ layout
lay = C.layout(base, cat)
ok(lay == C.layout(base, cat), 'layout: deterministic')
rects = lay['rects']
same_floor = [(a, b) for a in rects for b in rects if a < b and base['zones'][[z['id'] for z in base['zones']].index(a)]['floor'] ==
              base['zones'][[z['id'] for z in base['zones']].index(b)]['floor']]
ok(all(not C.rect_overlap(rects[a], rects[b], C.GAP) for a, b in same_floor), 'layout: zones keep their gap')
ok(all(r[0] >= C.MARGIN_LO and r[1] >= C.MARGIN_LO and r[2] <= base['size'][0] - C.MARGIN_HI and r[3] <= base['size'][1] - C.MARGIN_HI
       for r in rects.values()), 'layout: zones inside the rim')
ok(len(lay['links']) == 1 and lay['links'][0]['floor'] == 1, 'layout: one link point for the stairs')
st = rects['stairwell']
l = lay['links'][0]
ok(st[0] < l['x'] < st[2] and st[1] < l['y'] < st[3] - 1, 'layout: the hole inside the stairwell')

# ------------------------------------------------------------------------------------------------ view frame
# a 3x1 walkable strip with no tile around it: everything within 9 x 7 of it, and nothing else
vf = C.view_frame({(10, 10, 7), (11, 10, 7), (12, 10, 7)}, {(10, 10, 7), (11, 10, 7), (12, 10, 7), (0, 10, 7)})
ok(len(vf) == 21 * 15 - 3 and (1, 3, 7) in vf and (21, 17, 7) in vf and (0, 10, 7) not in vf and (22, 10, 7) not in vf
   and (10, 18, 7) not in vf and not any(p[2] != 7 for p in vf), 'view frame: the 9 x 7 view of every walkable tile')
ok(C.view_frame({(5, 5, 7)}, {(x, y, 7) for x in range(-5, 16) for y in range(-5, 16)}) == set(),
   'view frame: nothing where the tiles cover the view')
ok(C.view_frame(set(), set()) == set(), 'view frame: no walkable tile, no frame')
ok(C.VIEW[0] >= (C.SCREEN[0] + 1) // 2 + 1 and C.VIEW[1] >= (C.SCREEN[1] + 1) // 2 + 1, 'view frame: past the screen')


def frame_ok(name, res):
    """the frame fills the whole view of every walkable tile, never on a tile of the area, unwalkable, one ground"""
    fr, man = res['frame'], res['manifest']['frame']
    allt = set(res['tiles']) | set(fr)
    ok(not C.view_frame(res['walk'], allt), name + ': no void in view of a walkable tile')
    ok(not set(fr) & set(res['tiles']) and not set(fr) & res['walk'], name + ': the frame is off the area and its floor')
    if man.get('thicket'):
        # a thicket biome: the whole plan rectangle, one blocking tree or bush on every tile
        ok(man['tiles'] == len(fr) and all(len(t['items']) == 1 and not t['flags'] for t in fr.values()),
           name + ': the frame is a thicket')
    else:
        ok(man['tiles'] == len(fr) and {t['ground'] for t in fr.values()} <= {man['ground']}
           and all(not t['items'] and not t['flags'] for t in fr.values()), name + ': the frame is bare %s' % man['family'])
    _h, back, problems = PC.read_otbm_full(res['frame_otbm'])
    ok(not problems and set(back) == set(fr), name + ': the frame OTBM reads back')


results = {}
for name, plan in examples.items():
    res = PC.compile_plan(plan, pair24=False, cat=cat)
    results[name] = res
    ok(not PC.qa_errors(res), name + ': QA passes: %s' % PC.qa_errors(res))
    res2 = PC.compile_plan(plan, pair24=False, cat=cat)
    ok(res2['otbm'] == res['otbm'] and res2['spawn_xml'] == res['spawn_xml'], name + ': the same plan gives the same bytes')
    header, tiles, problems = PC.read_otbm_full(res['otbm'])
    ok(not problems and len(tiles) == len(res['tiles']), name + ': the OTBM reads back: %s' % problems[:3])
    same = all(tiles[k]['ground'] == t['ground'] and tiles[k]['items'] == [(i, a) for i, a in t['items']]
               and tiles[k]['flags'] == t['flags'] for k, t in res['tiles'].items())
    ok(same, name + ': every tile reads back with its flags, items and attributes')
    s = res['stats']
    ok(s['unknown_ids'] == 0 and s['unbordered'] == 0, name + ': no unknown id, every border closed')
    frame_ok(name, res)
    ok(1.5 <= s['per100'] <= 5.0, name + ': %.2f monsters per 100 walkable tiles' % s['per100'])
    ok(set(s['zone_steps']) == {z['id'] for z in plan['zones']}, name + ': every zone reached on the tiles')
    ok(all((sp['x'], sp['y'], sp['z']) not in res['pz'] for sp in res['spawns']), name + ': no spawn in a PZ tile')
    want = sum(x['count'] for x in plan.get('spawns', []))
    ok(sum(sp['count'] for sp in res['spawns']) == want, name + ': every monster placed (%d)' % want)
    ok(len(res['chests']) == len(plan.get('chests', [])), name + ': the chests')
    ok(res['spawn_xml'].count('<monster ') >= len(res['spawns']), name + ': the spawn file')
    pz_zones = [z['id'] for z in plan['zones'] if z.get('pz')]
    for zid in pz_zones:
        x1, y1, x2, y2, z = res['zrect'][zid]
        ok(all(res['tiles'][(x, y, z)]['flags'] & PC.FLAG_PZ for x in range(x1, x2 + 1) for y in range(y1, y2 + 1)
               if (x, y, z) in res['tiles']), name + ': zone %s is a protection zone on the tiles' % zid)
crypt = results['crypt_boss']
ok(crypt['stats']['entry_to_boss'] and crypt['boss']['monster'] == 'Morgashal', 'crypt: the boss is reached (%s steps)'
   % crypt['stats']['entry_to_boss'])
lk = crypt['links'][0]
ok(len(crypt['links']) == 1 and lk['brush'] == 'stairs', 'crypt: the stairs use the stair brush (%s)' % lk['brush'])
kit = __import__('area_plan_decor').kits()
# the owner's decoration of pair 26: on (pair 26 published), the waste biome gets its own kit merged over
# decor_kits.json; the file itself (what the kits are with the switch off) keeps the lava kit for it
_D = __import__('area_plan_decor')
_base = json.load(open(_D.KITS_PATH, encoding='utf-8'))
_m = _D.merge_owner(_base, json.load(open(_D.OWNER_PATH, encoding='utf-8')))
# the catacomb kit of pair 27 (on since pair 27 went live) is merged after the owner's
_m = _D.merge_owner(_m, json.load(open(_D.ASSETS_PATH, encoding='utf-8'))) if _D.assets_on() else _m
# the harvest kit of pair 33 (on since pair 33 went live) is merged last
_m = _D.merge_owner(_m, json.load(open(_D.HARVEST_PATH, encoding='utf-8'))) if _D.harvest_on() else _m
ok(_D.owner_on() and kit == _m and kit['biome_kit']['waste'] == 'waste' and 'waste' in kit['kits'],
   'owner decoration: switch on, the kits are decor_kits.json merged with the owner\'s (and the catacomb and harvest kits\')')
ok('waste' not in _base['kits'] and _base['biome_kit']['waste'] == 'lava', 'owner decoration: off, the waste biome uses the lava kit')
ok(_m['biome_kit']['waste'] == 'waste' and ['cacti_potted', 3] in _m['kits']['waste']['centre']
   and _m['kits']['waste']['floor'][:len(_base['kits']['lava']['floor'])] == _base['kits']['lava']['floor']
   and _base['biome_kit']['waste'] == 'lava', 'owner decoration merged: waste = the lava kit plus the plants, input kept')
ok(all(36940 <= i <= 36985 for g in ('cacti_potted', 'desert_plants', 'waypoint_seal') for i in _m['groups'][g]['ids'])
   and len(_m['groups']['cacti_potted']['ids']) + len(_m['groups']['desert_plants']['ids']) == 45,
   'owner decoration: 45 plants and the seal, server ids 36940..36985')
ok(crypt['tiles'][lk['hole']]['ground'] == kit['brushes']['stairs_down_ground'], 'crypt: the stairs ground above')
ok(kit['brushes']['stairs_up'] in [i for i, _a in crypt['tiles'][lk['stair']]['items']], 'crypt: the stone stairs below')
ok(lk['landing'] == (lk['stair'][0], lk['stair'][1] + 1, lk['stair'][2]) and lk['up'] == (lk['hole'][0], lk['hole'][1] - 1, lk['hole'][2]),
   'crypt: down lands south of the stairs, up north of the stairs ground')
ok(lk['landing'] in crypt['walk'] and lk['up'] in crypt['walk'], 'crypt: both stair landings are walkable')
ok(any(a.get('tele') for t in crypt['tiles'].values() for _i, a in t['items']), 'crypt: the teleport carries its destination')
ok('Wandering Merchant' in results['swamp_hunt']['spawn_xml'], 'swamp: the NPC in the spawn file')
exit_items = [a for t in crypt['tiles'].values() for i, a in t['items'] if a.get('aid') == 47951]
ok(len(exit_items) == 1, 'crypt: one exit portal with the area exit action id')
# another seed, another layout
p = copy.deepcopy(examples['lava_cave'])
p['seed'] = 999
ok(PC.compile_plan(p, pair24=False, cat=cat)['otbm'] != results['lava_cave']['otbm'], 'another seed gives other tiles')
# ragged zones and wild paths: other tiles, still a valid area, and the ragged sides take walkable tiles off
p = copy.deepcopy(examples['swamp_hunt'])
for z in p['zones']:
    if z.get('role') != 'boss':
        z['ragged'] = True
for q in p['paths']:
    if 'boss' not in [z.get('role') for z in p['zones'] if z['id'] in (q['from'], q['to'])]:
        q['style'] = 'wild'
ok(not msgs(p), 'ragged zones and wild paths validate: %s' % msgs(p))
rg = PC.compile_plan(p, pair24=False, cat=cat)
ok(rg['otbm'] != results['swamp_hunt']['otbm'], 'ragged zones and wild paths give other tiles')
ok(not PC.qa_errors(rg), 'the ragged plan passes QA: %s' % PC.qa_errors(rg))
# spawns along a path: outside every zone, on the path's tiles; a spawn names a zone or a path, not both
p = copy.deepcopy(examples['swamp_hunt'])
q0 = p['paths'][0]
p['spawns'].append({'path': [q0['to'], q0['from']], 'monster': p['spawns'][0]['monster'], 'count': 4, 'pack': 2})
ok(not msgs(p), 'a path spawn validates: %s' % msgs(p))
ps = PC.compile_plan(p, pair24=False, cat=cat)
on_path = [s_ for s_ in ps['spawns'] if s_['zone'].startswith('path ')]
ok(sum(s_['count'] for s_ in on_path) == 4 and all((s_['x'], s_['y'], s_['z']) in ps['walk'] for s_ in on_path),
   'a path spawn places its monsters on walkable path tiles')
bad = copy.deepcopy(p)
bad['spawns'][-1]['zone'] = q0['from']
ok(has(bad, 'a zone or a path'), 'a spawn with a zone and a path is refused')
bad = copy.deepcopy(p)
bad['spawns'][-1]['path'] = [q0['from'], q0['from']]
ok(has(bad, 'no path joins'), 'a spawn on a path that does not exist is refused')
# spread spawns: one point per monster, evenly apart (no two closer than the default random placement allows)
p = copy.deepcopy(examples['swamp_hunt'])
for s_ in p['spawns']:
    s_['spread'], s_['pack'] = True, 1
ok(not msgs(p), 'spread spawns validate: %s' % msgs(p))
sp = PC.compile_plan(p, pair24=False, cat=cat)
pts = [(s_['x'], s_['y'], s_['z']) for s_ in sp['spawns']]
ok(sum(s_['count'] for s_ in sp['spawns']) == sum(s_['count'] for s_ in p['spawns']), 'spread spawns place every monster')
ok(len(set(pts)) == len(pts) and all(t in sp['walk'] for t in pts), 'spread spawns: one walkable point each')
ok(not PC.qa_errors(sp), 'the spread plan passes QA: %s' % PC.qa_errors(sp))
# a one-way hole: no ladder below it
p = copy.deepcopy(base)
p['connections'][0]['type'] = 'hole'
p['paths'].append({'from': 'landing', 'to': 'antechamber'})
p['connections'].append({'type': 'teleport', 'from': 'landing', 'to': 'stairwell', 'two_way': False})
p['zones'][-1]['role'] = 'hunt'
p.pop('boss')
res = PC.compile_plan(p, pair24=False, cat=cat)
lk = res['links'][0]
ok(lk['ladder'] is None and 1386 not in [i for i, _a in res['tiles'][lk['landing']]['items']], 'a hole has no ladder below')
ok(not PC.qa_errors(res), 'the one-way hole plan passes QA: %s' % PC.qa_errors(res))
# a plan that cannot be laid out says why
p = copy.deepcopy(examples['swamp_hunt'])
p['size'] = [30, 30]
try:
    PC.compile_plan(p, pair24=False, cat=cat)
    ok(False, 'a crowded plan fails')
except PC.CompileError as e:
    ok('does not fit' in str(e) or 'too big' in str(e), 'a crowded plan fails with a reason: %s' % e)
# the pair 24 switch: its swamp, water and acid grounds only when on
on = PC.compile_plan(examples['swamp_hunt'], pair24=True)
ids_on = {i for t in on['tiles'].values() for i in [t['ground']] + [x for x, _a in t['items']]}
ids_off = {i for t in results['swamp_hunt']['tiles'].values() for i in [t['ground']] + [x for x, _a in t['items']]}
ok(any(36852 <= i <= 36903 for i in ids_on) and not any(36852 <= i <= 36903 for i in ids_off),
   'pair 24 grounds only with the switch on')
ok(not PC.qa_errors(on), 'pair 24 on: QA passes: %s' % PC.qa_errors(on))
# every biome compiles a plan
for b in sorted(cat['biomes']):
    p = copy.deepcopy(examples['swamp_hunt'])
    p['biome'] = b
    res = PC.compile_plan(p, pair24=False, cat=cat)
    ok(not PC.qa_errors(res), 'biome %s compiles and passes QA: %s' % (b, PC.qa_errors(res)[:2]))
    frame_ok('biome ' + b, res)

# ------------------------------------------------------------------------------------------------ knowledge base
with tempfile.TemporaryDirectory() as tmp:
    ok(KB.kb_path({'AREAPLAN_KB': os.path.join(tmp, 'x.db')}) == os.path.join(tmp, 'x.db'), 'kb: path from the environment')
    ok(KB.kb_path({'XDG_DATA_HOME': tmp}).startswith(tmp), 'kb: path under the data dir')
    db = KB.connect(os.path.join(tmp, 'kb.sqlite3'))
    s0 = KB.suggest(db, 'swamp', 50, 140)
    ok(s0['approved'] == 0 and s0['monsters_in_band'], 'kb: suggest on an empty base gives the band\'s monsters')
    for name, res in results.items():
        KB.approve(db, examples[name], res['stats'], now=1)
    KB.approve(db, examples['swamp_hunt'], results['swamp_hunt']['stats'], now=2)
    ok(len(KB.rows(db)) == len(results), 'kb: one row per plan')
    s1 = KB.suggest(db, 'swamp', 60, 120)
    ok(s1['approved'] == 1 and s1['typical']['width'] == 72 and 'Bog Raider' in s1['monsters_used'], 'kb: suggest: %s' % s1.get('typical'))
    p = copy.deepcopy(examples['swamp_hunt'])
    p['id'] = 'another_fen'
    sim = KB.similar(db, p)
    ok(sim and sim[0][1]['id'] == 'mirewater_fen', 'kb: the closest plan is the same biome and band')
    db.close()

# ------------------------------------------------------------------------------------------------ AI adapter
try:
    AI.settings({})
    ok(False, 'ai: no key, no run')
except AI.NotConfigured as e:
    ok('ANTHROPIC_API_KEY' in str(e), 'ai: no key, no run')
try:
    AI.settings({'ANTHROPIC_API_KEY': 'k'})
    ok(False, 'ai: the model must be named')
except AI.NotConfigured as e:
    ok('AREAPLAN_LLM_MODEL' in str(e), 'ai: the model must be named')
ok(AI.settings({'ANTHROPIC_API_KEY': 'k', 'AREAPLAN_LLM_MODEL': 'm'})[2] == 'm', 'ai: the model from the environment')
ok(AI.settings({'AREAPLAN_LLM': 'openai', 'AREAPLAN_LLM_ENDPOINT': 'http://localhost:11434/v1/chat/completions',
                'AREAPLAN_LLM_MODEL': 'm'})[3] is None, 'ai: a local endpoint needs no key')
try:
    AI.settings({'AREAPLAN_LLM': 'openai', 'AREAPLAN_LLM_ENDPOINT': 'https://example.org/v1', 'AREAPLAN_LLM_MODEL': 'm'})
    ok(False, 'ai: a remote endpoint needs a key')
except AI.NotConfigured:
    ok(True, 'ai: a remote endpoint needs a key')
good = examples['lava_cave']
bad = copy.deepcopy(good)
bad['spawns'][0]['monster'] = 'Rat'
answers = ['Here it is:\n```json\n' + json.dumps(bad) + '\n```', json.dumps(good)]
seen = []


def fake(system, messages):
    seen.append((system, [m['content'] for m in messages]))
    t = answers.pop(0)
    return t, {'role': 'assistant', 'content': t}
plan, issues, rounds = AI.plan_from_prompt('a lava cave for 300-480', fake, cat, (300, 480), log=lambda *a: None)
ok(plan == good and rounds == 1, 'ai: one fix round from the validator errors (rounds %d)' % rounds)
ok('Rat is level 4' in seen[1][1][-1], 'ai: the fix round sends the errors')
ok('"chaos-area-plan/1"' in seen[0][0] and 'lava (cave' in seen[0][0] and 'Cinderclaw' in seen[0][0], 'ai: schema, biomes, monsters in the prompt')
answers[:] = ['not json'] * 5
plan, issues, rounds = AI.plan_from_prompt('x', fake, cat, None, log=lambda *a: None)
ok(rounds == AI.MAX_FIX_ROUNDS and plan is None, 'ai: at most %d fix rounds' % AI.MAX_FIX_ROUNDS)

# ------------------------------------------------------------------------------------------------ decoration
import area_plan_decor as D
import area_plan_place as PL
import subprocess
ok(set(kit['biome_kit']) >= set(cat['biomes']), 'decor: every biome has a kit: %s' % (set(cat['biomes']) - set(kit['biome_kit'])))
for kname, k in kit['kits'].items():
    for c, rows in k.items():
        if c in ('hall', 'rates'):
            continue
        for g, _w in rows:
            ok(g in kit['groups'], 'decor: kit %s %s names group %s' % (kname, c, g))
            if c in ('floor', 'around', 'path_edge', 'wall_h', 'wall_v', 'light_small', 'light_wall_h', 'light_wall_v'):
                ok(not kit['groups'][g]['block'], 'decor: %s %s %s does not block' % (kname, c, g))
ok(all(g['light'] for c in ('light_floor', 'light_wall_h', 'light_wall_v') for k in kit['kits'].values()
       for g in [kit['groups'][r[0]] for r in k.get(c, [])]), 'decor: the light categories give light')
for name, res in results.items():
    st = res['stats']['decoration']
    ok(st['added'] > 100, name + ': the dressing adds %d pieces' % st['added'])
    ok(st['spam_share'] < 0.01, name + ': under 1%% of tiles with 3+ decoration items (%.3f)' % st['spam_share'])
    ok(not any(t in res['dresser'].protected for t, _i, _g, _c in res['dresser'].placed),
       name + ': nothing on a spawn, teleport, link, chest, NPC or the boss')
    ok(not any('decoration' in m for m in PC.qa_errors(res)), name + ': decoration cuts no path')
    # nothing else next to a quest chest: no decoration piece of the dresser and no kit item on the eight tiles around it
    kit_ids = D.all_ids()
    ring = {(c['at'][0] + dx, c['at'][1] + dy, c['at'][2]) for c in res['chests'] for dx, dy in C.D8}
    ok(not any(t in ring for t, _i, _g, _c in res['dresser'].placed), name + ': the dresser put nothing next to a chest')
    ok(not any(i in kit_ids for t in ring if t in res['tiles'] for i, _a in res['tiles'][t]['items']),
       name + ': no decoration item next to a chest')
    raw = PC.compile_plan(examples[name], pair24=False, cat=cat, dress=False)
    ok(set(res['zone_steps'] if 'zone_steps' in res else res['stats']['zone_steps']) == set(raw['stats']['zone_steps']),
       name + ': the same zones reached with and without decoration')
temple = results['temple_throne']
cats = temple['stats']['decoration']['by_category']
ok(cats.get('hall pillars', 0) >= 8 and cats.get('throne') == 1 and cats.get('braziers') == 2,
   'temple: pillar rows, the throne and its braziers: %s' % cats)
ok(cats.get('wall lights', 0) > 0 and cats.get('wall decor', 0) > 0, 'temple: torches and tapestries on the walls')
pil = [(t, i) for t, i, g, c in temple['dresser'].placed if c == 'hall pillars']
ok(len({i for _t, i in pil}) == 1, 'temple: one pillar look per area')
hung = [i for _t, i, g, c in temple['dresser'].placed if c == 'wall decor' and g.startswith('tapestry')]
ok(len({kit['groups']['tapestry_h']['ids'].index(i) if i in kit['groups']['tapestry_h']['ids'] else
        kit['groups']['tapestry_v']['ids'].index(i) for i in hung}) <= 1, 'temple: one tapestry colour')
counts = {}
for level in ('sparse', 'normal', 'dense'):
    p = copy.deepcopy(examples['lava_cave'])
    p['decoration'] = level
    counts[level] = PC.compile_plan(p, pair24=False, cat=cat)['stats']['decoration']['added']
ok(counts['sparse'] < counts['normal'] < counts['dense'], 'decor: sparse < normal < dense: %s' % counts)
lights = {}
for level in ('dark', 'bright'):
    p = copy.deepcopy(examples['crypt_boss'])
    p['light'] = level
    lights[level] = PC.compile_plan(p, pair24=False, cat=cat)['stats']['decoration']['lights_added']
ok(lights['dark'] < lights['bright'], 'decor: the light setting scales the lights: %s' % lights)
# a blocking piece never cuts a route: the dresser's own check on a narrow corridor
walk = {(x, 5, 7) for x in range(10)} | {(x, y, 7) for x in range(3) for y in range(3, 8)}
ok(not D._simple(walk, (5, 5, 7)) and D._simple(walk, (0, 3, 7)), 'decor: a corridor tile is not simple, a corner is')
lane = D.lanes(walk, (9, 5, 7), [(0, 3, 7)])
ok((5, 5, 7) in lane and (0, 3, 7) in lane, 'decor: the lane runs from the arrival to the target')

# ------------------------------------------------------------------------------------------------ biomes without the pack
for b in ('forest', 'ice'):
    p = copy.deepcopy(examples['swamp_hunt'])
    p['biome'] = b
    res = PC.compile_plan(p, pair24=False, cat=cat)
    ids = {i for t in res['tiles'].values() for i in [t['ground']] + [x for x, _a in t['items']]}
    ok(not any(36000 <= i < 37000 for i in ids), '%s: no pack item without the packitems step' % b)
    ok(not C.validate(p, cat) or not any('pack items' in str(i) for i in C.validate(p, cat)), '%s: no pack warning' % b)
p = copy.deepcopy(examples['swamp_hunt'])
p['biome'] = 'ice'
ice = PC.compile_plan(p, pair24=False, cat=cat)
grounds = {t['ground'] for t in ice['tiles'].values()}
ok(len(grounds & set(range(6580, 6627)) | (grounds & {670})) >= 10, 'ice: 10+ snow ground ids (%d)' % len(grounds))
ok(ice['stats']['unbordered'] == 0, 'ice: every snow and ice edge bordered')
p['biome'] = 'forest_pack'
ok(any('pack items' in str(i) for i in C.validate(p, cat)), 'forest_pack: warns that it needs the pack items')

# ------------------------------------------------------------------------------------------------ roofs
p = copy.deepcopy(examples['crypt_boss'])
p['origin'] = {'x': 14800, 'y': 14800, 'z': 6}
roofed = PC.compile_plan(p, pair24=False, cat=cat)
ok(roofed['stats']['roof_tiles'] > 0 and not PC.qa_errors(roofed), 'roof: a crypt at z 6 gets a roof (%d)' % roofed['stats']['roof_tiles'])
ok(all(roofed['tiles'][(x, y, 5)]['ground'] == kit['roof']['ground'][0] for (x, y, z) in roofed['tiles'] if z == 6
       and (x, y, 5) in roofed['tiles']), 'roof: over floor 1 on z 5')
ok(crypt['stats']['roof_tiles'] == 0, 'roof: none underground')

# ------------------------------------------------------------------------------------------------ chests and NPC stubs
ok(all(C.CHEST_ACTION_BLOCK[0] <= c['aid'] <= C.CHEST_ACTION_BLOCK[1] for r in results.values() for c in r['chests']),
   'chests: the action id in the block')
ok(all(C.CHEST_STORAGE_BLOCK[0] <= c['storage'] <= C.CHEST_STORAGE_BLOCK[1] for r in results.values() for c in r['chests']),
   'chests: the storage in the block')
ok(cat['items']['chest'] == 32311, 'chests: the reward chest of rift_config.lua (32311, the one-tile look, README "Reward chests")')
ok(all(dict(temple['tiles'][c['at']]['items']).get(cat['items']['chest'], {}).get('aid') == c['aid'] for c in temple['chests']),
   'chests: the chest item carries the action id')
p = copy.deepcopy(examples['temple_throne'])
p['chests'][0]['reward']['items'][0]['name'] = 'Orb of Upheavel'
r, m = has(p, 'no item "Orb of Upheavel"')
ok(r and any('Orb of Upheaval' in x for x in m), 'chests: an unknown reward item, with the close name: %s' % m)
p = copy.deepcopy(examples['temple_throne'])
p['npcs'][0]['name'] = 'Wandering Merchant'
ok(has(p, 'exists already')[0], 'npcs: a new NPC may not reuse a name')
script = temple['stubs']['data/scripts/chaos_areaplan/sunfallen_temple_chests.lua']
ok('npc/Brother Aldwen.xml' in ' '.join(temple['stubs']) and 'data/npc/scripts/brother_aldwen.lua' in temple['stubs'],
   'npcs: the new NPC stubs')
with tempfile.TemporaryDirectory() as tmp:
    sp = os.path.join(tmp, 'chests.lua')
    open(sp, 'w').write(script)
    c = temple['chests'][0]
    harness = os.path.join(tmp, 'run.lua')
    open(harness, 'w').write("""
MESSAGE_INFO_DESCR = 1
local reg
function Action() local a = {} function a:aid(n) self.id = n end function a:register() reg = self end return a end
function ItemType(id) return {getWeight = function(self, n) return n end} end
dofile("%s")
local store, got, gold, last = {}, {}, 0, ""
local player = {getStorageValue = function(s, k) return store[k] or -1 end, setStorageValue = function(s, k, v) store[k] = v end,
  getFreeCapacity = function() return 1000 end, addItem = function(s, id, n) got[#got + 1] = id .. "x" .. n end,
  addMoney = function(s, g) gold = gold + g end, addExperience = function() end, sendTextMessage = function(s, t, m) last = m end}
local item = {getPosition = function() return {x = %d, y = %d, z = %d} end}
reg.onUse(player, item)
local first = table.concat(got, ",") .. " " .. gold .. " " .. last
reg.onUse(player, item)
print(reg.id, first, #got, gold, last)
""" % (sp, c['at'][0], c['at'][1], c['at'][2]))
    for lua in ('luajit', 'lua5.3'):
        try:
            out = subprocess.run([lua, harness], capture_output=True, text=True).stdout.strip()
        except FileNotFoundError:
            continue
        ok(out.split('\t') == [str(c['aid']), '29856x2,32251x1 250000 You take the relic offerings.', '2', '250000',
                                'The chest is empty.'], 'chests: the script gives the reward once (%s): %s' % (lua, out))
    # ------------------------------------------------------------------------------------------------ place, install
    a_dir, w_dir = os.path.join(tmp, 'a'), os.path.join(tmp, 'w')
    PC.write_outputs(temple, a_dir)
    PC.write_outputs(results['swamp_hunt'], w_dir)
    world = os.path.join(w_dir, 'mirewater_fen.otbm')
    before = open(world, 'rb').read()
    copy_ = os.path.join(tmp, 'copy.otbm')
    out = PL.place(os.path.join(a_dir, 'sunfallen_temple.otbm'), world, copy_, (14900, 14700, 9),
                   os.path.join(w_dir, 'mirewater_fen-spawn.xml'), os.path.join(tmp, 'copy-spawn.xml'), log=lambda *a: None)
    ok(open(world, 'rb').read() == before, 'place: the world file is untouched')
    _h, back, probs = PC.read_otbm_full(open(copy_, 'rb').read())
    ok(not probs and len(back) == len(results['swamp_hunt']['tiles']) + len(temple['tiles']) + out['frame'],
       'place: the copy holds both and the frame')
    d = out['shift']
    tfr = {(x + d[0], y + d[1], z + d[2]) for x, y, z in temple['frame']}
    ok(0 < out['frame'] <= len(tfr) and all(back[p]['ground'] == temple['manifest']['frame']['ground'] for p in tfr
                                            if p not in results['swamp_hunt']['tiles']),
       'place: the frame where the world has no tile (%d of %d)' % (out['frame'], len(tfr)))
    ok(all(back[p]['ground'] == results['swamp_hunt']['tiles'][p]['ground'] for p in tfr & set(results['swamp_hunt']['tiles'])),
       'place: the frame never replaces a world tile')
    d = out['shift']
    moved_exit = (temple['exit']['at'][0] + d[0], temple['exit']['at'][1] + d[1], temple['exit']['at'][2] + d[2])
    ok(any(a.get('aid') == temple['exit']['aid'] for _i, a in back[moved_exit]['items']), 'place: tiles and items shifted')
    tele = [a['tele'] for t in back.values() for _i, a in t['items'] if a.get('tele')]
    ok(all(x in back for x in tele), 'place: teleport destinations follow the area')
    sp_text = open(os.path.join(tmp, 'copy-spawn.xml')).read()
    ok(sp_text.count('<spawn ') == results['swamp_hunt']['spawn_xml'].count('<spawn ') + temple['spawn_xml'].count('<spawn '),
       'place: the spawn copy holds both spawn files')
    ok('local ORIGIN = {x = 14900, y = 14700, z = 9}' in open(out['chest_script']).read(), 'place: the chest script follows')
    try:
        PL.place(os.path.join(a_dir, 'sunfallen_temple.otbm'), world, os.path.join(tmp, 'c2.otbm'),
                 tuple(results['swamp_hunt']['manifest']['origin']), log=lambda *a: None)
        ok(False, 'place: an overlap is refused')
    except PL.PlaceError as e:
        ok('land on tiles the world map has' in str(e), 'place: an overlap is refused')
    try:
        PL.place(os.path.join(a_dir, 'sunfallen_temple.otbm'), world, world, (14900, 14700, 9), log=lambda *a: None)
        ok(False, 'place: never the world file')
    except PL.PlaceError:
        ok(True, 'place: never the world file')
    srv = os.path.join(tmp, 'srv')
    os.makedirs(os.path.join(srv, 'data'))
    done = PL.install(a_dir, srv, log=lambda *a: None)
    ok(len(done) == 3 and all(a == 'write' for a, _p in done), 'install: three files written')
    done = PL.install(a_dir, srv, log=lambda *a: None)
    ok(all(a == 'same' for a, _p in done), 'install: idempotent')
    other = os.path.join(srv, 'data', 'scripts', 'chaos_areaplan', 'other_chests.lua')
    open(other, 'w').write('action:aid(%d)\n' % temple['chests'][0]['aid'])
    try:
        PL.install(a_dir, srv, log=lambda *a: None)
        ok(False, 'install: an action id clash stops it')
    except PL.PlaceError as e:
        ok('action id' in str(e), 'install: an action id clash stops it')
    os.remove(other)
    # a batch of new areas: a clash between two of them is found before anything is installed (a dry run too)
    PL.check_batch([a_dir], srv)
    ok(True, 'check_batch: one area and its own installed script pass')
    twin = os.path.join(tmp, 'twin')
    tdir = os.path.join(twin, 'data', 'scripts', 'chaos_areaplan')
    os.makedirs(tdir)
    own = open(os.path.join(a_dir, 'data', 'scripts', 'chaos_areaplan', 'sunfallen_temple_chests.lua')).read()
    open(os.path.join(tdir, 'twin_chests.lua'), 'w').write(own.replace('action:aid(', 'action:aid(1'))
    srv2 = os.path.join(tmp, 'srv2')
    os.makedirs(os.path.join(srv2, 'data'))
    try:
        PL.check_batch([a_dir, twin], srv2)
        ok(False, 'check_batch: a storage shared by two new areas stops it')
    except PL.PlaceError as e:
        ok('shares storage' in str(e), 'check_batch: a storage shared by two new areas stops it')
    ok(not os.path.exists(os.path.join(srv2, 'data', 'scripts')), 'check_batch: nothing written')

# the areas install_content_areas.py places together (plans, chronicle, rooms): one chest action id per area, one
# storage per chest quest, and every area 10+ tiles from every other in x or y, whatever the floor (docs/MAP_GUIDE.md
# "Content plans"; the hall fill of 2026-10-22 brought 41 plans and two storage clashes the install found late)
placed = []
for sub in ('plans', 'chronicle', 'rooms'):
    d = os.path.join(HERE, 'areaplan', sub)
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if f.endswith('.json'):
            placed.append(json.load(open(os.path.join(d, f), encoding='utf-8')))
aids, sts, clash = {}, {}, []
for p in placed:
    if p.get('chests'):
        a = C.chest_action(p)
        if a in aids:
            clash.append('action %d: %s, %s' % (a, aids[a], p['id']))
        aids[a] = p['id']
    for c in p.get('chests') or []:
        s = C.chest_storage(c['quest'])
        if s in sts:
            clash.append('storage %d: %s, %s' % (s, sts[s], c['quest']))
        sts[s] = c['quest']
ok(not clash, 'placed areas: no shared chest action id or storage %s' % clash[:3])
near = []
for i, p in enumerate(placed):
    ox, oy, w, h = p['origin']['x'], p['origin']['y'], p['size'][0], p['size'][1]
    for q in placed[i + 1:]:
        qx, qy, qw, qh = q['origin']['x'], q['origin']['y'], q['size'][0], q['size'][1]
        gx = max(qx - (ox + w), ox - (qx + qw))
        gy = max(qy - (oy + h), oy - (qy + qh))
        if gx < 10 and gy < 10:
            near.append('%s/%s' % (p['id'], q['id']))
ok(len(placed) >= 58 and not near, 'placed areas: %d, each 10+ tiles from the others %s' % (len(placed), near[:3]))

# ground, border and shore pieces never stand alone as decoration (owner report 2026-10-28: the lava kit laid "small lava
# cracks" 5840-5843, the old lava edge pieces, on bare floor: brown strips with a crack line and an ochre bar)
import csv as _csv, re as _re
SERVER = os.path.dirname(HERE)
PLACE_KINDS = {'ground', 'border', 'shore', 'lake', 'water', 'dock'}
EDGE_STOCK = {5840: 'small lava cracks (lava edge strip)', 5841: 'small lava cracks (lava edge strip)',
              5842: 'small lava cracks (lava edge bar)', 5843: 'small lava cracks (lava edge strip)'}
placing = dict(EDGE_STOCK)
for f in sorted(os.listdir(os.path.join(SERVER, 'data', 'items'))):
    if not f.endswith('.csv'):
        continue
    with open(os.path.join(SERVER, 'data', 'items', f), encoding='utf-8') as fh:
        for row in _csv.DictReader(l for l in fh if not l.startswith('#')):
            sid = row.get('server_id') or ''
            if not sid.isdigit():
                continue
            if row.get('kind') == 'border' and _re.search(r'family=(decals|cata_ground)\b', row.get('extra') or ''):
                continue  # floor decals drawn as top order 1 items (bones, puddles): meant to lie alone
            if row.get('kind') in PLACE_KINDS or (row.get('role') or '').startswith('blend'):
                placing[int(sid)] = '%s %s' % (f, row.get('key') or row.get('name'))
cfg = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'areagen_config.lua'), encoding='utf-8').read()
pieces_txt = cfg[cfg.index('pieces = {'):cfg.index('walls = {')]
for n in _re.findall(r'\b(\d{3,5})\b', pieces_txt):
    placing.setdefault(int(n), 'areagen_config border piece')
fam_txt = cfg[cfg.index('families = {'):cfg.index('borders = {')]
for n in _re.findall(r'\{(\d{3,5}), \d+\}', fam_txt):
    placing.setdefault(int(n), 'areagen_config ground')
ok(len(placing) > 500, 'edge check: %d ground / border ids known' % len(placing))
kit_bad = []
for f in ('decor_kits', 'decor_owner_art', 'decor_assets_art', 'decor_pack33_kit'):
    kd = json.load(open(os.path.join(HERE, 'areaplan', f + '.json'), encoding='utf-8'))
    for gname, g in kd['groups'].items():
        for i in g['ids']:
            if i in placing:
                kit_bad.append('%s %s %d (%s)' % (f, gname, i, placing[i]))
ok(not kit_bad, 'decor kits hold no ground, border or edge piece as a standalone item: %s' % kit_bad[:6])
sc_bad = []
th = cfg[cfg.index('themes = {'):]
for n in _re.findall(r'\{(\d{3,5}), \d+\}', th):
    if int(n) in placing:
        sc_bad.append('%s %s' % (n, placing[int(n)]))
ok(not sc_bad, 'areagen themes scatter no ground or border piece as decor: %s' % sc_bad[:6])

# one ground family per corridor floor (owner report 2026-10-28, Hollow Crypt: the crypt family laid 13189 "dark sandy floor"
# and 12237, a round-pebble patch tile of the stain family 12234-12237, by weight, tile by tile)
STAIN_PATCH = {12234, 12235, 12236, 12237}
crypt_fam = re.search(r'crypt = \{z = 1500, grounds = \{(.*?)\}\},\n', cfg).group(1)
ok(set(re.findall(r'\{(\d+), \d+\}', crypt_fam)) == {'13189'}, 'areagen crypt family: 13189 only (%s)' % crypt_fam)
crypt_bad = []
for pid in ('hollow_crypt', 'bonechoir_catacomb', 'bonewright_galleries', 'graveknell_catacombs', 'lanternless_catacombs'):
    pl = json.load(open(os.path.join(HERE, 'areaplan', 'plans', pid + '.json'), encoding='utf-8'))
    _h, tl, _pr = PC.read_otbm_full(PC.compile_plan(pl, pair24=False)['otbm'])
    seen = {}
    for t_ in tl.values():
        g = t_['ground'] if isinstance(t_, dict) else t_[0]
        seen[g] = seen.get(g, 0) + 1
    if STAIN_PATCH & set(seen) or not seen.get(13189):
        crypt_bad.append('%s %s' % (pid, sorted(STAIN_PATCH & set(seen))))
ok(not crypt_bad, 'catacomb hunts: crypt corridors are 13189 only, no stain patch tile: %s' % crypt_bad)

print('area planner: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
