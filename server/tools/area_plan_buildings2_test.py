#!/usr/bin/env python3
"""Tests of buildings phase 2 of the area planner (O740; server/tools/area_plan_buildings.py, area_plan_compile.py,
areaplan/prefabs/camp.json, server/README.md "Buildings phase 2 (O740)"): floors above a building joined by stairs with
the roof on the top floor, the plan's ruin share, the open camp, the cellar the area generator builds under a building.
The pure parts (plan_levels, ruin_plan, open_layout) on every size and door side; the example
examples/ruined_hamlet.json compiled with no QA error or warning, every floor above, cellar and camp tile reached over
the stairs, holes and ladders, only legal ids, the map tile audit (audit_map_plans.py) clean and the house audit rules
(audit_houses.py: floors, door, size, roof share) held on its whole houses; the QA cases (a missing stair, a cellar with
no way down, a roof off the map); the validator; all off by default: the held examples compile to the same bytes.
Needs LuaJIT (the generator) and numpy (the map tile audit).

    python3 -I server/tools/area_plan_buildings2_test.py
"""
import copy, hashlib, json, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import area_plan_core as C
import area_plan_compile as PC
import area_plan_decor as D
import area_plan_buildings as B
import audit_houses as AH
import map_tile_rules as MR

checks = fails = 0


def ok(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


EX = os.path.join(HERE, 'areaplan', 'examples')
HAMLET = json.load(open(os.path.join(EX, 'ruined_hamlet.json')))
cat = C.catalogue(False)
mats = C.materials(False)
kit = D.kits()
fams = B.families()
blocks = lambda f: B.family_blocks(f, fams, kit)
STAIRS_UP, STAIRS_GROUND = kit['brushes']['stairs_up'], kit['brushes']['stairs_down_ground']

# ------------------------------------------------------------------------------------------------ the tables
ok(B.KINDS == ('temple', 'depot', 'shop', 'house') and B.ALL_KINDS == B.KINDS + ('camp',), 'four walled kinds and the camp')
camp = B.prefab('camp')
ok(camp.get('open') and not B.prefab_problems(camp, mats, fams, kit['groups']),
   'camp: the prefab is sound: %s' % B.prefab_problems(camp, mats, fams, kit['groups']))
for name in ('campfire', 'bedroll', 'barrels', 'debris'):
    ok(name in fams, 'family %s' % name)
ok(fams['campfire']['ids'] == [48561] and not blocks('campfire'), 'campfire: the flame campfire of decor_flames.csv, walkable')
flames = open(os.path.join(os.path.dirname(HERE), 'data', 'items', 'decor_flames.csv')).read()
ok(',48561,campfire,' in flames, 'the campfire id is the server id of data/items/decor_flames.csv')
ok(not blocks('bedroll') and not blocks('debris'), 'bedroll stand-in and ruin debris are walkable')
for kind in ('house', 'shop'):
    up = B.prefab(kind).get('upper', {}).get('pieces', [])
    ok(up and all(p in fams and not fams[p].get('hang') for p in up), '%s: the upper pieces are floor families' % kind)
bad = dict(camp, wall='st_stone', roof=True)
ok(len(B.prefab_problems(bad, mats, fams, kit['groups'])) == 2, 'an open prefab with a wall and a roof is refused')
bad = dict(B.prefab('house'), upper={'pieces': ['torch', 'nope']})
ok(len(B.prefab_problems(bad, mats, fams, kit['groups'])) == 2, 'upper pieces: a hung family and an unknown one are refused')


# ------------------------------------------------------------------------------------------------ plan_levels
def reached(free, start):
    return B._all_reached(set(free), start)


n_lv, no_room = 0, []
for kind in B.KINDS:
    pf = B.prefab(kind)
    (wlo, whi), (hlo, hhi) = B.size_range(pf)
    for w in range(wlo, whi + 1):
        for h in range(hlo, hhi + 1):
            for side in 'nesw':
                lay = B.layout(pf, w, h, side)
                for n_up, cel in ((1, False), (2, False), (0, True), (2, True)):
                    n_lv += 1
                    try:
                        lv = B.plan_levels(lay, n_up, cel, blocks, pf.get('upper', {}).get('pieces', ()))
                    except B.BuildingError:
                        no_room.append((kind, w, h, side, n_up, cel))
                        continue
                    L = lv['levels']
                    good = len(L) == n_up + 1
                    inter = set(lay['floor'])
                    claimed = {it['tile'] for it in lay['items'] if it['role'] == 'floor'}
                    blocked0 = {it['tile'] for it in lay['items'] if it['role'] == 'floor' and blocks(it['family'])}
                    bars0 = {t for t in (L[0]['stairs'], lv['hole']) if t}
                    good &= not bars0 & (claimed | set(lay['reach']) | set(lay['inside']))
                    good &= reached(inter - blocked0 - bars0, lay['inside'][0])
                    for k in range(1, n_up + 1):
                        d = L[k]['down']
                        good &= d == L[k - 1]['stairs'] and (d[0], d[1] + 1) in inter and (d[0], d[1] - 1) in inter
                        good &= (d[0], d[1] + 1) not in claimed | bars0 if k == 1 else (d[0], d[1] + 1) != L[k - 1]['down']
                        bars = {d} | ({L[k]['stairs']} if L[k]['stairs'] else set())
                        blk = {i['tile'] for i in L[k]['items'] if blocks(i['family'])}
                        good &= L[k]['start'] == (d[0], d[1] - 1) and reached(inter - bars - blk, L[k]['start'])
                    if cel:
                        hz, up = lv['hole'], lv['hole_up']
                        good &= up == (hz[0], hz[1] + 1) and up in inter and up not in claimed | bars0
                    ok(good, '%s %dx%d door %s: %d floor(s) above, cellar %s: stairs and hole on free tiles, every tile reached'
                       % (kind, w, h, side, n_up, cel))
ok(n_lv == 4 * 184, 'plan_levels on every layout of the four kinds (%d)' % n_lv)
# a shop 7 deep with the door south: shelves, counter and the tiles in front of it leave no room for the stairs and the
# hole together; the planner then turns the door to another side (or names the building in an error)
ok(sorted(no_room) == [('shop', w, 7, 's', 2, True) for w in (8, 9, 10)], 'no room only in the 7-deep shop with stairs and a hole: %s' % no_room)
# a 6 x 5 building has a 4 x 3 interior: the stairs fit; a table across the middle of a 4 x 2 interior blocks them
tiny = dict(B.prefab('house'), features=[], slots=[])
lay = B.layout(tiny, 6, 4, 's')
try:
    B.plan_levels(lay, 1, False, blocks)
    ok(False, 'a 4 x 2 interior has no room for stairs with a landing on both floors')
except B.BuildingError as e:
    ok('stairs' in str(e), 'a 4 x 2 interior: no room for the stairs (%s)' % e)

# ------------------------------------------------------------------------------------------------ ruin_plan, open_layout
lay = B.layout(B.prefab('house'), 9, 9, 's')
ok(B.ruin_plan(lay, 0, random.Random(1)) == (set(), set()), 'ruin 0: nothing breaks')
gaps, patches = B.ruin_plan(lay, 100, random.Random(1))
door = set(lay['door'])
near = {(t[0] + dx, t[1] + dy) for t in door for dx, dy in ((1, 0), (-1, 0), (2, 0), (-2, 0), (0, 1), (0, -1), (0, 2), (0, -2))}
ok(not gaps & (door | near) and gaps == {t for t in lay['walls'] if t not in door | near},
   'ruin 100: every wall breaks but the door and the two wall tiles on each side of it (%d gaps)' % len(gaps))
free = [t for t in lay['floor'] if t not in {i['tile'] for i in lay['items'] if i['role'] == 'floor'} | set(lay['reach']) | set(lay['inside'])]
ok(len(patches) == round(len(free) / 2.0) and patches <= set(free), 'ruin 100: half the free floor loses its floor, no piece tile')
g40, p40 = B.ruin_plan(lay, 40, random.Random(1), hung=[(0, 3)])
ok(len(g40) == round(0.4 * len([t for t in lay['walls'] if t not in door | near and max(abs(t[0]), abs(t[1] - 3)) > 1]))
   and not any(max(abs(t[0]), abs(t[1] - 3)) <= 1 for t in g40), 'ruin 40: 40 %% of the eligible walls; a hung piece keeps its run')
ok(B.ruin_plan(lay, 40, random.Random(7)) == B.ruin_plan(lay, 40, random.Random(7)), 'ruin: the same seed, the same ruin')
ol = B.open_layout(camp, 5, 5)
ok(ol['open'] and not ol['walls'] and not ol['door'] and len(ol['floor']) == 25 and not ol['conflicts'],
   'camp 5 x 5: no wall, no door, the whole patch')
ok({i['family'] for i in ol['items']} == {'campfire', 'bedroll', 'crates', 'barrels'} and
   [i['tile'] for i in ol['items'] if i['family'] == 'campfire'] == [(2, 2)], 'camp: the fire in the middle, beds and crates round it')
for w in range(5, 8):
    for h in range(5, 8):
        ol = B.open_layout(camp, w, h)
        tiles_ = {i['tile'] for i in ol['items']}
        blk = {i['tile'] for i in ol['items'] if blocks(i['family'])}
        ok(len(tiles_) == len(ol['items']) and reached(ol['floor'] - blk, (0, 0)), 'camp %d x %d: no overlap, every free tile joined' % (w, h))
ol = B.open_layout(camp, 5, 5, [dict(dx=0, dy=0, family='torch', role='hang', wall='back')])
ok(ol['dropped'], 'camp: a hung slot is dropped (no wall)')

# ------------------------------------------------------------------------------------------------ the example
issues = C.validate(HAMLET, cat)
ok(not issues, 'ruined_hamlet: validates with no error and no warning: %s' % [str(i) for i in issues])
res = PC.compile_plan(HAMLET, pair24=False, cat=cat)
ok(not [q for q in res['qa'] if q[0] != 'INFO'], 'ruined_hamlet: no QA error or warning: %s' % res['qa'][:3])
res2 = PC.compile_plan(HAMLET, pair24=False, cat=cat)
ok(res2['otbm'] == res['otbm'] and res2['frame_otbm'] == res['frame_otbm'], 'ruined_hamlet: the same plan gives the same bytes')
tiles, walk = res['tiles'], res['walk']
oz = res['origin'][2]
recs = {r['id']: r for r in res['buildings']}
ok(sorted(recs) == sorted(b['id'] for b in HAMLET['buildings']), 'every building placed')
edges = [e for l in res['links'] for e in l['edges']] + [(t['at'], t['to']) for t in res['teleports']]
bedges = []
for r in recs.values():
    for lv in r.get('levels', ()):
        below = (lv['down'][0], lv['down'][1], lv['z'] + 1)
        bedges += [(below, (lv['down'][0], lv['down'][1] - 1, lv['z'])), (lv['down'], (below[0], below[1] + 1, below[2]))]
    if r.get('cellar'):
        c = r['cellar']
        bedges += [(c['hole'], c['ladder']), (c['ladder'], c['up'])]
dist = C.tile_reach(walk, res['arrival'], (), edges + bedges)
ok(not [t for t in walk if t not in dist], 'every walkable tile of every floor is reached (%d of %d)' % (len(dist), len(walk)))
dist0 = C.tile_reach(walk, res['arrival'], (), edges)
upper = {t for t in walk if t[2] < oz}
cellar_t = {t for t in walk if t[2] > oz}
ok(upper and cellar_t and not (upper | cellar_t) & set(dist0),
   'the floors above (%d tiles) and the cellars (%d) are reached only over their stairs, holes and ladders' % (len(upper), len(cellar_t)))

inn, watch = recs['old_inn'], recs['watch_house']
for r, n in ((inn, 2), (watch, 1)):
    ok(len(r['levels']) == n and [lv['z'] for lv in r['levels']] == [oz - k for k in range(1, n + 1)], '%s: %d floor(s) above' % (r['id'], n))
    for lv in r['levels']:
        below = (lv['down'][0], lv['down'][1], lv['z'] + 1)
        ok(STAIRS_UP in [i for i, _a in tiles[below]['items']] and tiles[lv['down']]['ground'] == STAIRS_GROUND,
           '%s floor z %d: stone stairs below, the stairs ground above' % (r['id'], lv['z']))
        lw = set(lv['walls'])
        ok(len(lw) == len(r['walls']) + len(r['door']), '%s floor z %d: the full wall ring, the door is wall there' % (r['id'], lv['z']))
        ok(all(MR.wall_piece(*[(a[0] + dx, a[1] + dy, a[2]) in lw for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0))]) == k
               for a, k in lv['walls'].items()), '%s floor z %d: every wall piece is the one its neighbours want' % (r['id'], lv['z']))
    top = oz - n - 1
    roof = set(kit['roof']['ground'])
    ok(all(tiles.get((t[0], t[1], top), {}).get('ground') in roof for t in r['foot']), '%s: the roof lies on z %d over the whole footprint' % (r['id'], top))
    ok(not any(tiles.get((t[0], t[1], oz - 1), {}).get('ground') in roof for t in r['foot']), '%s: no roof on the first floor above' % r['id'])
ok(any(lv['items'] for lv in inn['levels']), 'old_inn: pieces stand on the floors above')

for bid, biome in (('old_inn', 'crypt'), ('burnt_house', 'vault')):
    c = recs[bid]['cellar']
    ok(c['biome'] == biome and c['ladder'] == (c['hole'][0], c['hole'][1], oz + 1) and c['up'] == (c['hole'][0], c['hole'][1] + 1, oz),
       '%s: a %s cellar one floor down, the ladder under the hole, up lands south of the hole' % (bid, biome))
    ok(8972 in [i for i, _a in tiles[c['hole']]['items']] and 1386 in [i for i, _a in tiles[c['ladder']]['items']],
       '%s: the large hole and the ladder of areagen_config.lua' % bid)
    ok(len(c['walk']) >= 40 and all(t in dist for t in c['walk']), '%s: %d cellar tiles, all reached' % (bid, len(c['walk'])))
    ok(c['hole'] in recs[bid]['interior'], '%s: the hole is inside the building' % bid)

for bid, share in (('burnt_house', 40), ('fallen_shop', 60), ('empty_house', 40)):
    r = recs[bid]
    ru = r['ruin']
    ok(ru['share'] == share and ru['gaps'] and all(g in walk for g in ru['gaps']), '%s: ruin %d %%, %d walkable gaps' % (bid, share, len(ru['gaps'])))
    ws = set(r['walls']) | set(r['door'])
    ok(all(MR.wall_piece(*[(a[0] + dx, a[1] + dy, a[2]) in ws for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0))]) == k
           for a, k in r['walls'].items()), '%s: the walls left get the piece their new neighbours want' % bid)
    ok(all(t in dist for t in r['outside'] + r['door'] + r['inside'] + r['reach']), '%s: the door path stays open' % bid)
    deb = set(kit['groups'][fams['debris']['group']]['ids'])
    ok(any(i in deb for t in r['interior'] + ru['gaps'] for i, _a in tiles[t]['items']), '%s: loose debris lies about' % bid)
    ok(not r['roof'], '%s: a ruin is open to the sky' % bid)
ok('ruin' not in inn and 'ruin' not in watch, 'a building with floors above stays whole')

cp = recs['hunters_camp']
ok(cp['open'] and not cp['walls'] and not cp['door'] and not cp['roof'], 'camp: no wall, no door, no roof')
ids = [i for t in cp['foot'] for i, _a in tiles[t]['items']]
ok(48561 in ids and any(i in kit['groups']['dry_grass']['ids'] for i in ids), 'camp: the campfire and the straw beds')
ok(all(t in dist for t in cp['interior'] if t in walk), 'camp: every free tile reached')
ok(not {tiles[t]['ground'] for t in cp['foot']} & {g for d in mats['families'].values() if d['indoor'] for g in d['grounds']},
   'camp: the patch keeps its outdoor ground')

ok(res['stats']['unknown_ids'] == 0, 'only legal ids: none outside the catalogue')
fr = res['manifest']['frame']
ok(set(fr.get('cellars', [])) == {101}, 'the cellars are framed with their own biome ground (earth 101)')
ok(not C.view_frame({t for t in walk if t[2] >= oz}, set(tiles) | set(res['frame'])), 'no void in view of the ground floor or a cellar')
man = {b['id']: b for b in res['manifest']['buildings']}
ok(len(man['old_inn']['floors_above']) == 2 and man['old_inn']['cellar']['biome'] == 'crypt' and man['fallen_shop']['ruin']['share'] == 60
   and man['hunters_camp']['open'], 'the manifest lists the floors above, the cellars, the ruins and the camp')

# the house audit rules (audit_houses.py, O513) on the whole houses: floors, a door on the edge with a walkable tile
# outside, the size, the roof share; a ruin is no house anyone owns, so the roof rule does not apply to it
for r in recs.values():
    if r['kind'] != 'house' or r.get('ruin'):
        continue
    n_floor = 1 + len(r.get('levels', ()))
    size = len(r['foot']) + sum(len(lv['interior']) + len(lv['walls']) for lv in r.get('levels', ()))
    top = oz - n_floor
    roofed = sum(1 for t in r['foot'] if (t[0], t[1], top) in tiles) / float(len(r['foot']))
    ok(n_floor <= AH.MAX_FLOORS, '%s: %d floors (house audit MULTI_FLOOR, at most %d)' % (r['id'], n_floor, AH.MAX_FLOORS))
    ok(r['door'] and all(o in walk for o in r['outside']), '%s: a door on the edge with a walkable tile outside' % r['id'])
    ok(AH.HOUSE_MIN_TILES <= size <= AH.HOUSE_MAX_TILES, '%s: %d tiles (house audit SIZE)' % (r['id'], size))
    ok(roofed >= AH.ROOF_MIN_SHARE, '%s: roof share %.2f (house audit ROOF_SHARE)' % (r['id'], roofed))

# the map tile audit (O511) over the compiled example with its frame
import audit_map_plans as AMP
import audit_map_tiles as AMT
got = AMP.audit_plan(os.path.join(EX, 'ruined_hamlet.json'), log=lambda *_a: None)
found = {c: got[1].count(c) for c in AMT.CODES if got[1].count(c)} if got else None
ok(found == {}, 'the map tile audit (ground, borders, wall pieces, doors, floor changes, roofs) finds nothing: %s' % found)

# ------------------------------------------------------------------------------------------------ the QA
# a stair taken away: the floor above is out of reach
tiles_ = copy.deepcopy(tiles)
lv = inn['levels'][0]
below = (lv['down'][0], lv['down'][1], oz)
tiles_[below]['items'] = [it for it in tiles_[below]['items'] if it[0] != STAIRS_UP]
d_ = C.tile_reach(walk, res['arrival'], (), edges + [e for e in bedges if e[0] != below])
msgs = []
B.qa_all([inn], tiles_, walk, d_, mats, msgs.append, msgs.append, set(kit['roof']['ground']))
ok(any('floor 1 cannot be reached' in m for m in msgs) and any('out of reach' in m for m in msgs),
   'QA: no stairs, the floor above is out of reach: %s' % msgs[:2])
# no way down to the cellar
c = recs['burnt_house']['cellar']
d_ = C.tile_reach(walk, res['arrival'], (), edges + [e for e in bedges if e[0] != c['hole']])
msgs = []
B.qa_all([recs['burnt_house']], tiles, walk, d_, mats, msgs.append, msgs.append, set(kit['roof']['ground']))
ok(any('the ladder' in m for m in msgs) and any('cellar has' in m for m in msgs), 'QA: no hole, the cellar is out of reach: %s' % msgs[:2])
# a roof above the top of the map
p = copy.deepcopy(HAMLET)
p['origin'] = dict(x=14600, y=14600, z=2)
r_ = PC.compile_plan(p, pair24=False, cat=cat)
ok(any('no floor above' in q[1] for q in r_['qa'] if q[0] == 'ERROR'), 'QA: two floors above and a roof from z 2 leave the map')
# the cellar overlaps a floor of the area
p = copy.deepcopy(HAMLET)
p['floors'] = 2
p['zones'].append(dict(id='deep', floor=2, size=[20, 16], place='center'))
p['connections'] = [dict(type='stairs', **{'from': 'thicket', 'to': 'deep'})]
iss = [str(i) for i in C.errors(C.validate(p, cat))]
ok(any('cellar' in m and 'floor 2' in m for m in iss), 'validator: a cellar on a floor of the plan: %s' % iss[:2])

# ------------------------------------------------------------------------------------------------ the validator
def msgs_of(plan):
    return [str(i) for i in C.validate(plan, cat)]


p = copy.deepcopy(HAMLET)
p['buildings'][5].update(wall='st_stone', roof=True)
m = msgs_of(p)
ok(any('open' in x and '"wall"' in x for x in m) and any('"roof"' in x for x in m), 'validator: a camp with a wall and a roof: %s' % m[:2])
p = copy.deepcopy(HAMLET)
p['buildings'][0]['floors_above'] = 3
ok(any('floors_above' in x and 'maximum' in x for x in msgs_of(p)), 'validator: at most 2 floors above')
p = copy.deepcopy(HAMLET)
p['buildings'][1]['floors_above'] = 2
ok(any(x.startswith('WARN') and 'MULTI_FLOOR' in x for x in msgs_of(p)), 'validator: a house on 3 floors is the house audit\'s MULTI_FLOOR')
p = copy.deepcopy(HAMLET)
del p['buildings'][1]['ruin']
ok(any(x.startswith('WARN') and 'stays whole' in x for x in msgs_of(p)), 'validator: a ruin share on a building with floors above')
p = copy.deepcopy(HAMLET)
p['buildings'][2]['cellar'] = {'biome': 'lava'}
ok(any('cellar' in x for x in msgs_of(p)), 'validator: a cellar biome that is not underground')
p = copy.deepcopy(HAMLET)
p['ruin'] = 101
ok(any('plan.ruin' in x for x in msgs_of(p)), 'validator: the ruin share is 0-100')

# ------------------------------------------------------------------------------------------------ off by default
HELD = {'examples/village_square.json': '3002fd05a3a7abffb52a', 'examples/river_hunt.json': 'a5b999d110fa28ce74f1',
        'examples/crypt_boss.json': '0507e92d97cf5f4a33a5'}
for rel, want in sorted(HELD.items()):
    plan = json.load(open(os.path.join(HERE, 'areaplan', rel)))
    r = PC.compile_plan(plan, pair24=False, cat=cat)
    h = hashlib.sha256()
    h.update(r['otbm'])
    h.update(r['frame_otbm'])
    h.update(r['spawn_xml'].encode())
    h.update(json.dumps(r['manifest'], sort_keys=True).encode())
    ok(h.hexdigest()[:20] == want, '%s: the same bytes as before phase 2 (%s, was %s)' % (rel, h.hexdigest()[:20], want))

print('area plan buildings phase 2: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
