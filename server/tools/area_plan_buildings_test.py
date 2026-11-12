#!/usr/bin/env python3
"""Tests of the planner's parametric buildings (O515; server/tools/area_plan_buildings.py, areaplan/prefabs/*.json,
areaplan/building_families.json, the `buildings` of a plan, area_plan_compile.py): the prefab files and their families,
the layout of every kind at every size on every door side (the door on the asked side, the way in from the door to every
feature, the layout turning with the door), the compiled village example, the QA (a decor slot on the door path, an
overlap, a roof that does not cover the footprint), the validator, and the checksums of the plans without buildings.
Needs LuaJIT (LUAJIT=... to point elsewhere). The sprite pair is not in CI: no picture is rendered here.

    python3 -I server/tools/area_plan_buildings_test.py
"""
import copy, hashlib, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import area_plan_core as C
import area_plan_compile as PC
import area_plan_decor as D
import area_plan_buildings as B
import map_tile_rules as MR

checks = fails = 0


def ok(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


EX = os.path.join(HERE, 'areaplan', 'examples')
VILLAGE = json.load(open(os.path.join(EX, 'village_square.json')))
cat = C.catalogue(False)
mats = C.materials(False)
kit = D.kits()
fams = B.families()
VEC = {'n': (0, -1), 'e': (1, 0), 's': (0, 1), 'w': (-1, 0)}

# ------------------------------------------------------------------------------------------------ the tables
ok(set(B.KINDS) == {'temple', 'depot', 'shop', 'house'}, 'four kinds')
ID_KEYS = {'width', 'height', 'dx', 'dy', 'length', 'min_iw', 'min_ih', 'door_width'}


def numbers_outside(v, key=None):
    """integers under keys that are not sizes or coordinates (an item id would show up here)"""
    if isinstance(v, dict):
        return [n for k, x in v.items() for n in numbers_outside(x, k)]
    if isinstance(v, list):
        return [n for x in v for n in numbers_outside(x, key)]
    if isinstance(v, int) and not isinstance(v, bool) and key not in ID_KEYS:
        return [(key, v)]
    return []


for kind in B.KINDS:
    pf = B.prefab(kind)
    ok(pf['kind'] == kind, kind + ': the prefab names its kind')
    ok(not B.prefab_problems(pf, mats, fams, kit['groups']), kind + ': the prefab is sound: %s' % B.prefab_problems(pf, mats, fams, kit['groups']))
    ok(not numbers_outside(pf), kind + ': no item id in the prefab: %s' % numbers_outside(pf)[:3])
    ok(pf['wall'] in mats['walls'] and pf['floor'] in mats['families'] and mats['families'][pf['floor']]['walk'],
       kind + ': its wall brush and floor family are in our tables')
    ok('stats' in pf, kind + ': says where its size comes from')
bad = dict(B.prefab('shop'), features=[dict(type='counter', dy=1, family='nope')])
ok(any('no family' in m for m in B.prefab_problems(bad, mats, fams, kit['groups'])), 'a prefab with an unknown family is a problem')
bad = dict(B.prefab('shop'), wall='nope')
ok(any('no wall family' in m for m in B.prefab_problems(bad, mats, fams, kit['groups'])), 'a prefab with an unknown wall brush is a problem')
for name, f in fams.items():
    for g in (f.get('group'), f.get('group_h'), f.get('group_v')):
        ok(g is None or g in kit['groups'], 'family %s: the kit group %s exists' % (name, g))
    stock = list(f.get('ids', [])) + list(f.get('dirs', {}).values()) + list(f.get('h', [])) + list(f.get('v', []))
    ok(all(isinstance(i, int) and i > 0 for i in stock), 'family %s: stock ids are positive integers' % name)
ok(set(mats['walls']['st_stone']) == {'horizontal', 'vertical', 'corner', 'pole'}, 'materials: the stone wall brush has its four pieces')
ok(mats['doors']['wood']['h']['closed'] != mats['doors']['wood']['v']['closed'], 'materials: a door for each wall direction')
ok(all(g in {x for fam in mats['families'].values() for x in fam['grounds']} for g in (406, 414)), 'materials: the temple and tile floors')


def blocks(family):
    f = fams[family]
    if f.get('hang'):
        return False
    return bool(kit['groups'][f['group']]['block']) if 'group' in f else bool(f.get('block'))


# ------------------------------------------------------------------------------------------------ the layout
def flood(lay):
    """tiles reached from the tiles just inside the door over the unblocked floor"""
    blocked = {it['tile'] for it in lay['items'] if it['role'] == 'floor' and blocks(it['family'])}
    free = lay['floor'] - blocked
    seen = set(t for t in lay['inside'] if t in free)
    stack = list(seen)
    while stack:
        x, y = stack.pop()
        for dx, dy in C.D8:
            n = (x + dx, y + dy)
            if n in free and n not in seen:
                seen.add(n)
                stack.append(n)
    return seen, free


sizes = n_layouts = 0
for kind in B.KINDS:
    pf = B.prefab(kind)
    (wlo, whi), (hlo, hhi) = B.size_range(pf)
    for w in range(wlo, whi + 1):
        for h in range(hlo, hhi + 1):
            for side in 'nesw':
                tag = '%s %dx%d door %s' % (kind, w, h, side)
                try:
                    lay = B.layout(pf, w, h, side)
                except B.BuildingError as e:
                    ok(False, tag + ': ' + str(e))
                    continue
                n_layouts += 1
                W, H = (w, h) if side in 'ns' else (h, w)
                if (lay['W'], lay['H']) != (W, H) or lay['conflicts'] or len(lay['door']) != pf['door_width']:
                    ok(False, tag + ': footprint %dx%d, conflicts %s, doors %d' % (lay['W'], lay['H'], lay['conflicts'], len(lay['door'])))
                    continue
                edge = {'n': lambda t: t[1] == 0, 's': lambda t: t[1] == H - 1, 'w': lambda t: t[0] == 0, 'e': lambda t: t[0] == W - 1}[side]
                fine = all(edge(t) for t in lay['door'])
                fine = fine and all((o[0] - t[0], o[1] - t[1]) == VEC[side] for o, t in zip(lay['outside'], lay['door']))
                fine = fine and all((t[0] - i[0], t[1] - i[1]) == VEC[side] for i, t in zip(lay['inside'], lay['door']))
                fine = fine and len(lay['walls']) == 2 * (W + H) - 4 and len(lay['floor']) == (W - 2) * (H - 2)
                fine = fine and all(t in lay['floor'] for t in lay['inside']) and not set(lay['door']) - set(lay['walls'])
                seen, free = flood(lay)
                want = set(lay['reach']) | ({lay['npc']} if lay['npc'] else set())
                path = want <= seen and seen == free
                if not (fine and path):
                    ok(False, tag + ': door side and footprint %s; way in reaches the features %s and every free tile %s' % (fine, want <= seen, seen == free))
                else:
                    sizes += 1
ok(sizes == n_layouts and n_layouts == 184, 'layout: %d layouts (4 kinds, every size, all 4 door sides) have the door on the asked side and a clear way from the door to every feature' % sizes)

# wall pieces follow the generator's rule: a pole in the north-west corner, a corner piece in the south-east one
lay = B.layout(B.prefab('house'), 7, 7, 's')
ok(lay['walls'][(0, 0)] == 'pole' and lay['walls'][(6, 6)] == 'corner' and lay['walls'][(6, 0)] == 'horizontal'
   and lay['walls'][(0, 6)] == 'vertical' and lay['walls'][(3, 0)] == 'horizontal' and lay['walls'][(0, 3)] == 'vertical',
   'walls: pole north-west, corner south-east, rows and columns between (A.wallPiece, as the generator)')
ok(all(lay['walls'][t] == MR.wall_piece(*((t[0] + dx, t[1] + dy) in lay['walls'] for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)))) for t in lay['walls']),
   'walls: every wall tile has the piece the shared rule wants')

# turning the door side turns the layout: the south layout carried round by quarter turns is the layout of the other sides
for kind in B.KINDS:
    pf = B.prefab(kind)
    w, h = pf['width'][0] + 1, pf['height'][0] + 1
    base = B.layout(pf, w, h, 's')
    floors = {(it['tile'], it['family']) for it in base['items'] if it['role'] == 'floor'}
    W, H = base['W'], base['H']
    turn = {'s': lambda t: t, 'w': lambda t: (H - 1 - t[1], t[0]), 'n': lambda t: (W - 1 - t[0], H - 1 - t[1]), 'e': lambda t: (t[1], W - 1 - t[0])}
    for side in 'nwe':
        other = B.layout(pf, w, h, side)
        got = {(it['tile'], it['family']) for it in other['items'] if it['role'] == 'floor'}
        ok({(turn[side](t), f) for t, f in floors} == got, '%s: the floor pieces of the south layout turned to door %s are those of the layout of door %s' % (kind, side, side))
        ok({turn[side](t) for t in base['door']} == set(other['door']) and {turn[side](t) for t in base['walls']} == set(other['walls']),
           '%s: the door and the walls turn with it' % kind)
        ok(base['npc'] is None or turn[side](base['npc']) == other['npc'], '%s: the NPC slot turns with it' % kind)
        ok({turn[side](t) for t in base['reach']} == set(other['reach']), '%s: the reach tiles turn with it' % kind)
# hung pieces only on north and west walls: the temple turned to the north has none on its torches' wall
t_n = B.layout(B.prefab('temple'), 10, 9, 'n')
t_s = B.layout(B.prefab('temple'), 10, 9, 's')
ok(any(it['role'] == 'hang' for it in t_s['items']) and len(t_n['dropped']) > len(t_s['dropped']), 'a hung piece on a south or east wall is dropped, one on a north or west wall is kept')
ok(all(it['wall_dir'] in ('n', 'w') for it in t_n['items'] + t_s['items'] if it['role'] == 'hang'), 'hung pieces face north or west walls only')
try:
    B.layout(B.prefab('house'), 4, 4, 's')
    ok(False, 'a 4 x 4 footprint is too small')
except B.BuildingError:
    ok(True, 'a 4 x 4 footprint is too small')
try:
    B.coord(9, 4)
    ok(False, 'a coordinate outside the interior is refused')
except B.BuildingError:
    ok(True, 'a coordinate outside the interior is refused')
ok(B.coord('c', 8) == 3 and B.coord(-1, 8) == 7 and B.coord(2, 8) == 2, 'coordinates: c, negative and plain')
extra = [dict(dx=0, dy=0, family='table', role='floor')]
ok(B.layout(B.prefab('house'), 7, 7, 's', extra)['conflicts'], 'an extra slot on a feature tile is a conflict')


# ------------------------------------------------------------------------------------------------ compiling
def build(buildings, **over):
    p = copy.deepcopy(VILLAGE)
    p['buildings'] = buildings
    p.update(over)
    return PC.compile_plan(p, pair24=False, cat=cat), p


def errs(res):
    """QA errors, the zones' outline rule left out (it measures the zones, not the buildings)"""
    return [m for m in PC.qa_errors(res) if not m.startswith('outline of floor')]


base_res = PC.compile_plan(VILLAGE, pair24=False, cat=cat)
ok(not PC.qa_errors(base_res), 'the village example compiles with zero QA errors: %s' % PC.qa_errors(base_res))
ok(len(base_res['buildings']) == 7 and [r['kind'] for r in base_res['buildings']] == ['temple', 'depot', 'shop', 'shop', 'house', 'house', 'house'],
   'the village example holds a temple, a depot, two shops and three houses')
ok(PC.compile_plan(VILLAGE, pair24=False, cat=cat)['otbm'] == base_res['otbm'], 'the village example: same plan, same bytes')
man = base_res['manifest']
ok(len(man['buildings']) == 7 and all(b['route_steps'] is not None for b in man['buildings']),
   'the manifest lists the buildings, each with its steps from the entry')
ox, oy, oz = base_res['origin']
ok(all(r['rect'][4] == oz for r in base_res['buildings']), 'the buildings stand on the area floor')
ok(not [m for l, m in base_res['qa'] if l == 'WARN'], 'the village example has no QA warning: %s' % [m for l, m in base_res['qa'] if l == 'WARN'])
st = base_res['stats']
ok(st['unknown_ids'] == 0 and st['unbordered'] == 0, 'the village example: no unknown id, every border closed')
_h, back, problems = PC.read_otbm_full(base_res['otbm'])
ok(not problems and len(back) == len(base_res['tiles']), 'the village OTBM reads back: %s' % problems[:2])
dist = C.tile_reach(base_res['walk'], base_res['arrival'], (), [e for l in base_res['links'] for e in l['edges']])
for r in base_res['buildings']:
    tag = r['id']
    walls = [t for t in r['foot'] if t not in set(r['interior'])]
    ok(all(a in dist for a in r['door']) and all(a in dist for a in r['outside']), tag + ': the door and the tile outside it are reached from the entry')
    ok(all(a in dist for a in r['reach']) and all(t in dist for t in r['interior'] if t in base_res['walk']), tag + ': every free interior tile and every counter or altar front is reached')
    ok(all(base_res['tiles'][(t[0], t[1], t[2] - 1)]['ground'] in set(kit['roof']['ground']) for t in r['foot']), tag + ': the roof covers the whole footprint one floor up')
    ok(all(any(i in r['door_ids'] for i, _a in base_res['tiles'][a]['items']) and len(base_res['tiles'][a]['items']) == 1 for a in r['door']),
       tag + ': the door tile holds the door and nothing else')
    ok(not [t for t in r['blocked'] if t in base_res['walk']] and not [t for t in r['walls'] if t in base_res['walk']], tag + ': walls and blocking pieces are off the walkable set')
    ok(len(walls) == 2 * (r['size'][0] + r['size'][1]) - 4, tag + ': a wall ring of one tile')
    ok(r['rect'][2] - r['rect'][0] + 1 == r['size'][0] and r['rect'][3] - r['rect'][1] + 1 == r['size'][1], tag + ': the size is the footprint on the map')
ok(any(r['pz'] for r in base_res['buildings']) and all(t in base_res['pz'] for r in base_res['buildings'] if r['pz'] for t in r['interior']),
   'protection zone: the temple, depot and shops are PZ inside')
npc_names = {n['name']: n for n in base_res['npcs']}
ok(set(npc_names) == {'Brother Halric', 'Clerk Mirwen', 'Tobin the Trader', 'Garreth Ironhand'}, 'the four keepers are placed: %s' % sorted(npc_names))
recs = {r['id']: r for r in base_res['buildings']}
ok(all((n['x'], n['y'], n['z']) in set(recs[n['building']]['interior']) for n in npc_names.values()), 'each NPC stands inside its own building')
ok(sum(1 for s in base_res['manifest']['stubs'] if s.startswith('data/npc/') and s.endswith('.xml')) == 4, 'a new NPC of a building gets the XML and script stubs')
ok('Brother Halric' in base_res['spawn_xml'], 'the NPCs are in the spawn file')

# every kind compiles, on every door side; the door is on the asked side and the layout turns with it
seen_sides = {}
for kind, dims in (('temple', [11, 10]), ('depot', [9, 8]), ('shop', [9, 8]), ('house', [7, 7])):
    for side in 'nesw':
        b = dict(id='b1', kind=kind, zone='plaza', door=side, size=dims)
        if kind != 'house':
            b['npc'] = dict(name='Keeper Tester', new=True, lines=['Hello, |PLAYERNAME|.'])
        res, _p = build([b])
        tag = '%s door %s' % (kind, side)
        ok(not errs(res), tag + ': compiles with no QA error: %s' % errs(res)[:2])
        rec = res['buildings'][0] if res['buildings'] else None
        if not rec:
            ok(False, tag + ': no building placed')
            continue
        x1, y1, x2, y2, z = rec['rect']
        d = rec['door'][0]
        on_edge = {'n': d[1] == y1, 's': d[1] == y2, 'w': d[0] == x1, 'e': d[0] == x2}[side]
        ok(rec['side'] == side and on_edge and rec['outside'][0][:2] == (d[0] + VEC[side][0], d[1] + VEC[side][1]), tag + ': the door is on the asked side')
        ok(rec['size'] == (dims if side in 'ns' else dims[::-1]), tag + ': the footprint turns with the door: %s' % rec['size'])
        want_door = mats['doors']['wood']['h' if side in 'ns' else 'v']['closed']
        ok(res['tiles'][d]['items'] == [(want_door, {})], tag + ': the door item is the %s pair of our door table' % ('h' if side in 'ns' else 'v'))
        seen_sides[(kind, side)] = rec
        feats = {f['family']: f['at'] for f in rec['features']}
        if kind == 'temple':
            a = feats['altar']
            back_edge = {'s': a[1] == y1 + 1, 'n': a[1] == y2 - 1, 'w': a[0] == x2 - 1, 'e': a[0] == x1 + 1}[side]
            ok(back_edge, tag + ': the altar stands at the back wall, opposite the door')
    ok(len({tuple(sorted((f['family'], f['at'][0] - seen_sides[(kind, s)]['rect'][0], f['at'][1] - seen_sides[(kind, s)]['rect'][1]) for f in seen_sides[(kind, s)]['features'])) for s in 'nesw' if (kind, s) in seen_sides}) == 4,
       '%s: the four door sides give four different layouts' % kind)

# the stock ids the check on the live data reads (area_planner.py check-kits)
rows = B.stock_ids(mats)
ok(len(rows) > 40 and {r[2] for r in rows} == {'item', 'wall', 'ground', 'door'} and all(isinstance(r[0], int) for r in rows),
   'check-kits: %d stock ids of the buildings (items, walls, grounds, doors)' % len(rows))
ok({mats['doors']['wood'][o][st] for o in 'hv' for st in ('closed', 'open')} <= {r[0] for r in rows if r[2] == 'door'}, 'check-kits: both door pairs are on the list')

# the door "route" faces the nearest route; a fixed door side is kept
res, _p = build([dict(id='h1', kind='house', zone='plaza', door='route')])
ok(not errs(res) and res['buildings'][0]['side'] in 'nesw', 'door "route": compiles and picks a side')
dd = res['buildings'][0]['outside'][0]
ok(res['manifest']['buildings'][0]['route_steps'] is not None, 'door "route": the outside tile is joined to the entry')

# ------------------------------------------------------------------------------------------------ the QA
good, _p = build([dict(id='temple', kind='temple', zone='plaza', door='s')])
rec = good['buildings'][0]
bx, by = rec['rect'][0] - ox, rec['rect'][1] - oy
c0 = (rec['size'][0] - 3) // 2
# a decor slot moved onto the door path: a pillar on the tile just inside the door
res, _p = build([dict(id='temple', kind='temple', zone='plaza', door='s', at=[bx, by],
                      slots=[dict(dx='c', dy=-1, family='pillar', role='floor')])])
ok(any('the way in from the door is blocked' in m or 'cannot be reached from the door' in m for m in errs(res)), 'QA: a pillar on the tile inside the door blocks the way in: %s' % errs(res)[:3])
# a slot on the tile in front of the altar, which a player must reach
res, _p = build([dict(id='temple', kind='temple', zone='plaza', door='s', at=[bx, by],
                      slots=[dict(dx='c', dy=1, family='crates', role='floor')])])
ok(any('in front of a counter or an altar cannot be reached' in m for m in errs(res)), 'QA: a crate in front of the altar is an error: %s' % errs(res)[:2])
# two slots on one tile are a conflict the building reports
res, _p = build([dict(id='temple', kind='temple', zone='plaza', door='s', at=[bx, by],
                      slots=[dict(dx=a, dy=1, family='crates', role='floor') for a in (2, 3)] + [dict(dx=2, dy=1, family='crates', role='floor')])])
ok(any('overlaps' in m for m in errs(res)), 'QA: two slots on one tile are reported: %s' % errs(res)[:2])
# a hung piece on the door tile
res, _p = build([dict(id='h1', kind='house', zone='plaza', door='n', size=[7, 7],
                      slots=[dict(dx='c', dy=0, family='torch', role='hang', wall='front')])])
ok(any('besides the door' in m for m in errs(res)), 'QA: a piece hung on the door tile is an error: %s' % errs(res)[:2])
# two buildings on the same spot overlap
res, _p = build([dict(id='temple', kind='temple', zone='plaza', door='s', at=[bx, by]),
                 dict(id='house_a', kind='house', zone='plaza', door='s', at=[bx + 2, by + 1])])
ok(any('house_a' in m and 'overlaps building temple' in m for m in errs(res)), 'QA: a building on top of another is refused: %s' % errs(res)[:2])
res, _p = build([dict(id='temple', kind='temple', zone='plaza', door='s', at=[bx, by]),
                 dict(id='house_a', kind='house', zone='plaza', door='s', at=[bx + rec['size'][0] + 1, by])])
ok(any('overlaps building temple' in m for m in errs(res)), 'QA: two footprints closer than the %d-tile gap overlap' % B.GAP)
# a building on rock, off its zone, and the area's arrival
res, _p = build([dict(id='h1', kind='house', zone='orchard', door='s', at=[1, 1])])
ok(any('building h1' in m for m in errs(res)), 'QA: a building outside its zone is refused: %s' % errs(res)[:2])
res, _p = build([dict(id='h1', kind='house', zone='plaza', door='s', at=[bx, by + 30])])
ok(any('building h1' in m for m in errs(res)), 'QA: a building off its zone and the rock is refused')
# the roof must cover the footprint (a roof tile taken away)
r0 = good['buildings'][0]
tiles = {k: dict(v) for k, v in good['tiles'].items()}
del tiles[(r0['foot'][0][0], r0['foot'][0][1], r0['foot'][0][2] - 1)]
msgs = []
B.qa_all(good['buildings'], tiles, good['walk'], C.tile_reach(good['walk'], good['arrival']), mats, msgs.append, msgs.append, set(kit['roof']['ground']))
ok(any('the roof misses 1 footprint tile' in m for m in msgs), 'QA: a roof that misses a footprint tile is an error: %s' % msgs[:2])
# a wall piece of the wrong kind
tiles = {k: dict(v, items=list(v['items'])) for k, v in good['tiles'].items()}
w0 = sorted(r0['walls'])[0]
other = [i for kind, ids in mats['walls'][r0['wall']].items() if kind != r0['walls'][w0] for i in ids][0]
tiles[w0]['items'] = [(other, {})]
msgs = []
B.qa_all(good['buildings'], tiles, good['walk'], C.tile_reach(good['walk'], good['arrival']), mats, msgs.append, msgs.append, set(kit['roof']['ground']))
ok(any('wall piece at' in m for m in msgs), 'QA: a wall piece of the wrong kind is an error (the generator\'s wall rule): %s' % msgs[:2])
# a door the entry cannot reach: the walk without the door's outside tile
walk2 = set(good['walk']) - set(r0['outside'])
msgs = []
B.qa_all(good['buildings'], good['tiles'], walk2, C.tile_reach(walk2, good['arrival']), mats, msgs.append, msgs.append, set(kit['roof']['ground']))
ok(any('cannot be reached from the entry' in m or 'is not walkable' in m for m in msgs), 'QA: a door that the entry cannot reach is an error')
# the tile rule shared with the whole-map audit: a blocking item on the door tile
msgs = []
t_door = r0['door'][0]
tiles2 = {k: dict(v, items=list(v['items'])) for k, v in good['tiles'].items()}
blocker = sorted(r0['block_ids'])[0]
tiles2[t_door]['items'].append((blocker, {}))
B.qa_all(good['buildings'], tiles2, good['walk'], C.tile_reach(good['walk'], good['arrival']), mats, msgs.append, msgs.append, set(kit['roof']['ground']))
ok(any('has the blocking item' in m for m in msgs), 'QA: a blocking item on the door tile is the shared audit rule (map_tile_rules.blocking_on_special): %s' % msgs[:2])
# overlap between two records
msgs = []
B.qa_all([r0, dict(r0, id='twin')], good['tiles'], good['walk'], C.tile_reach(good['walk'], good['arrival']), mats, msgs.append, msgs.append, set(kit['roof']['ground']))
ok(any('overlaps building temple' in m for m in msgs), 'QA: two records on the same tiles overlap')

# ------------------------------------------------------------------------------------------------ the validator
def verr(b, **over):
    p = copy.deepcopy(VILLAGE)
    p['buildings'] = [b]
    p.update(over)
    return [str(i) for i in C.validate(p, cat) if i.level == 'ERROR']


def vhas(b, text, **over):
    m = verr(b, **over)
    return any(text in x for x in m), m


ok(not verr(dict(id='h1', kind='house', zone='plaza')), 'validate: a plain house is fine')
r, m = vhas(dict(id='h1', kind='castle', zone='plaza'), 'is not allowed; use one of temple, depot, shop, house')
ok(r, 'validate: a kind without a prefab is refused by the schema: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='nowhere'), 'no zone "nowhere"')
ok(r, 'validate: the zone must exist: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', size=[20, 20]), 'is outside')
ok(r, 'validate: a size outside the prefab range: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', wall='nope'), 'no wall brush "nope"')
ok(r, 'validate: an unknown wall brush: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', floor='lava'), 'no walkable ground family "lava"')
ok(r, 'validate: a floor family that cannot be walked: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', item=1209), 'unknown key "item"')
ok(r, 'validate: an item id key is refused: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', npc=dict(name='Nobody Atall')), 'no NPC "Nobody Atall"')
ok(r, 'validate: an NPC of a building must exist or be new: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', npc=dict(name='Hobb', new=True)), 'has no NPC slot')
ok(r, 'validate: a house has no NPC slot: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', slots=[dict(dx=1, dy=1, family='zzz', role='floor')]), 'no building family "zzz"')
ok(r, 'validate: an unknown slot family: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', slots=[dict(dx=1, dy=1, family='torch', role='floor')]), 'its role must be hang')
ok(r, 'validate: a hung family needs the hang role: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', at=[2, 2], size=[7, 7]), 'leaves the usable area')
ok(r, 'validate: a position outside the usable area: %s' % m)
r, m = vhas(dict(id='h1', kind='house', zone='plaza', size=[9, 9]), 'does not fit zone', zones=[dict(id='plaza', floor=1, size=[8, 8], place='center', role='camp', pz=True)] + VILLAGE['zones'][1:])
ok(r, 'validate: a footprint bigger than its zone: %s' % m)
p = copy.deepcopy(VILLAGE)
p['buildings'] = [dict(id='h1', kind='house', zone='plaza'), dict(id='h1', kind='shop', zone='plaza')]
ok(any('is used twice' in str(i) for i in C.validate(p, cat)), 'validate: a building id twice')
for z in p['zones']:
    z['role'] = 'boss' if z['id'] == 'grove' else z.get('role', 'hunt')
p['buildings'] = [dict(id='h1', kind='house', zone='grove')]
ok(any('boss room' in str(i) for i in C.validate(p, cat)), 'validate: no building in the boss room')
p = copy.deepcopy(VILLAGE)
p['buildings'][0]['npc'] = dict(name='Brother Halric', new=True)
p['buildings'][3]['npc'] = dict(name='Brother Halric', new=True)
ok(not [i for i in C.validate(p, cat) if i.level == 'ERROR'], 'validate: the plan of the example is fine')
p = copy.deepcopy(VILLAGE)
p['buildings'][0]['pz'] = False
ok(any(i.level == 'WARN' and 'outside a protection zone' in str(i) for i in C.validate(p, cat)), 'validate: an NPC in a building that is no PZ is a warning')

# a plan without buildings validates and compiles as before
p = copy.deepcopy(VILLAGE)
del p['buildings']
res0 = PC.compile_plan(p, pair24=False, cat=cat)
ok('buildings' not in res0['manifest'] and res0['buildings'] == [], 'no buildings: no "buildings" key in the manifest')

# ------------------------------------------------------------------------------------------------ the old plans
OLD = {'asym/asym_forest_test.json': '9ae14f10cca25cfebc53', 'examples/crypt_boss.json': '0507e92d97cf5f4a33a5',
       'examples/lava_cave.json': '018a86a1faf68eb9dcc0', 'examples/swamp_hunt.json': '30a2ae2e60149dc05544',
       'examples/temple_throne.json': '413e2ddac10872ea0668'}
for rel, want in sorted(OLD.items()):
    plan = json.load(open(os.path.join(HERE, 'areaplan', rel)))
    res = PC.compile_plan(plan, pair24=False)
    h = hashlib.sha256()
    h.update(res['otbm'])
    h.update(res['frame_otbm'])
    h.update(res['spawn_xml'].encode())
    h.update(json.dumps(res['manifest'], sort_keys=True).encode())
    ok(h.hexdigest()[:20] == want, '%s: the same bytes as before the buildings existed (%s, was %s)' % (rel, h.hexdigest()[:20], want))
    ok('buildings' not in res['manifest'], rel + ': no buildings key')

print('area plan buildings: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
