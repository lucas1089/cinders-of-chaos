#!/usr/bin/env python3
"""Tests of the area planner (server/tools/area_planner.py, area_plan_*.py) without the live data or a sprite pair (CI):
the schema and game-rule validator, the reachability maths, the layout, the compiler (the three example plans compile
and pass QA, the same seed gives the same bytes, the OTBM reads back), the pair 24 switch, the knowledge base and the AI
adapter's fix loop on a fake endpoint. Needs LuaJIT (LUAJIT=... to point elsewhere).

    python3 -I server/tools/area_planner_test.py
"""
import copy, json, os, sys, tempfile

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
ok(sorted(examples) == ['crypt_boss', 'lava_cave', 'swamp_hunt'], 'three example plans: %s' % sorted(examples))
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
    text = json.dumps(plan)
    ok('"item' not in text and '"id": 1' not in text, name + ': no item id in the plan')

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
r, m = has(p, 'above the maximum 160')
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

# ------------------------------------------------------------------------------------------------ compile
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
ok(len(crypt['links']) == 1 and crypt['links'][0]['ladder'], 'crypt: the stairs have a hole and a ladder')
ok(any(a.get('tele') for t in crypt['tiles'].values() for _i, a in t['items']), 'crypt: the teleport carries its destination')
ok('Wandering Merchant' in results['swamp_hunt']['spawn_xml'], 'swamp: the NPC in the spawn file')
exit_items = [a for t in crypt['tiles'].values() for i, a in t['items'] if a.get('aid') == 47951]
ok(len(exit_items) == 1, 'crypt: one exit portal with the area exit action id')
# another seed, another layout
p = copy.deepcopy(examples['lava_cave'])
p['seed'] = 999
ok(PC.compile_plan(p, pair24=False, cat=cat)['otbm'] != results['lava_cave']['otbm'], 'another seed gives other tiles')
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
    ok(len(KB.rows(db)) == 3, 'kb: one row per plan')
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

print('area planner: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
