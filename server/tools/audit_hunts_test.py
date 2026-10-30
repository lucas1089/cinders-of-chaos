"""Unit test of audit_hunts.py on synthetic data (run: python3 -I server/tools/audit_hunts_test.py)."""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audit_hunts as H

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


# ---- walking speed and sweep
check(H.tiles_per_second(1) < H.tiles_per_second(300) <= H.tiles_per_second(2000), 'faster feet at higher levels: %r %r' %
      (H.tiles_per_second(1), H.tiles_per_second(300)))
check(abs(H.sweep_seconds(2000, 100) - 2000 / 8.0 / H.tiles_per_second(100)) < 1e-9, 'sweep = tiles / width / speed')

# ---- spawn file and places file readers
spawn_text = '''<spawns>
	<spawn centerx="100" centery="200" centerz="7" radius="2" chaoscontent="demo">
		<monster name="Rat" x="1" y="-1" z="7" spawntime="60" />
		<monster name="Cat" x="0" y="0" z="7" spawntime="60" />
	</spawn>
	<spawn centerx="110" centery="200" centerz="7" radius="1" chaoshunt="demo">
		<monster name="Rat" x="0" y="0" z="7" spawntime="60" />
	</spawn>
	<spawn centerx="5" centery="5" centerz="8" radius="1">
		<npc name="Bob" x="0" y="0" z="8" spawntime="60" />
	</spawn>
</spawns>'''
ents = H.parse_spawn_entries(spawn_text)
check(len(ents) == 3 and ents[0]['x'] == 101 and ents[0]['y'] == 199 and ents[0]['content'] == 'demo' and ents[2]['hunt'] == 'demo',
      'spawn entries: %r' % ents)
places_text = '''-- x
return {
	back = {x = 1, y = 2, z = 6},
	places = {
		{id = "demo", name = "Demo \\"Hall\\"", level = {10, 20}, teleport = {x = 1, y = 2, z = 6}, sign = {x = 1, y = 3, z = 6}, arrival = {x = 100, y = 200, z = 7}, exit = {x = 3, y = 4, z = 7}, monster = "Rat", front = {x = 5, y = 5, z = 6}},
	},
	hall = true,
	base = {
		{id = "base_1", name = "Troll", level = {5, 15}, teleport = {x = 9, y = 9, z = 7}, sign = {x = 9, y = 10, z = 7}, dest = {x = 50, y = 60, z = 8}},
	},
	floors = {
	},
}
'''
pl = H.parse_places(places_text)
check(len(pl['places']) == 1 and pl['places'][0]['arrival'] == (100, 200, 7) and pl['places'][0]['level'] == (10, 20) and
      pl['places'][0]['monster'] == 'Rat' and pl['places'][0]['name'] == 'Demo \\"Hall\\"', 'places: %r' % pl['places'])
check(len(pl['base']) == 1 and pl['base'][0]['dest'] == (50, 60, 8) and pl['base'][0]['teleport'] == (9, 9, 7), 'base places: %r' % pl['base'])

# ---- metrics: a 60 x 22 field (8 screens of 15 x 11), 40 monsters in the left half
field = {(100 + x, 200 + y, 7) for x in range(60) for y in range(22)}
left = [(100 + (i * 3) % 30, 200 + (i * 5) % 22, 7) for i in range(40)]
m = H.metrics(left, field, 100)
check(m['monsters'] == 40 and m['walkable'] == 1320, 'counts: %r' % m)
check(abs(m['per100'] - 100 * 40 / 1320.0) < 1e-9 and abs(m['tpm'] - 33.0) < 1e-9, 'density: %r' % m)
check(m['screens'] == 8 and 0.3 < m['dead_share'] < 0.5, 'the right half has no monster in view of a player: %r' % m)
check(m['screen_max'] >= m['screen_mean'] > 0, 'screen mean and peak')
check('dead' in H.density_flags(m, dead=True) and 'dead' not in H.density_flags(m), 'dead only judged where asked')
check(H.metrics(left, {(100 + x, 200 + y, 7) for x in range(30) for y in range(22)}, 100)['dead_share'] < 0.1, 'monsters all over: no dead ground')
check('sparse' in H.density_flags(H.metrics(left[:10], field, 100)), 'sparse under %.1f per 100' % H.SPARSE)
dense = H.metrics([(100 + i % 20, 200 + i // 20, 7) for i in range(200)], {(100 + x, 200 + y, 7) for x in range(30) for y in range(11)}, 100)
check('packed' in H.density_flags(dense), 'packed: %.1f per 100' % dense['per100'])
stack = H.metrics([(159, 221, 7)] * 4 + left, field, 100)
check(stack['stacked'] == 1 and stack['stack_max'] >= 4 and 'stacked' in H.density_flags(stack), 'four on one tile are stacked: %r' % stack['stacked'])
three = H.metrics([(159, 221, 7)] * 3 + left, field, 100)
check(three['stacked'] == 0, 'a pack of three is no stack')
check(H.size_flags(H.metrics(left[:30], {(1 + x, 1 + y, 7) for x in range(10) for y in range(10)}, 100)) == ['small'], 'a closet is small')
big = H.metrics(left, {(x, y, 7) for x in range(300) for y in range(100)}, 1)
check('big' in H.size_flags(big), 'a field of 30000 tiles at level 1 sweeps over %d s: big (%d)' % (H.MAX_SWEEP, big['sweep']))
roomy = H.metrics(left, {(100 + x, 200 + y, 7) for x in range(80) for y in range(40)}, 100)
check(H.size_flags(roomy) == [], '3200 tiles with 40 monsters is fine: %r %r' % (H.size_flags(roomy), roomy['sweep']))
check(H.size_flags(m) == ['small'], 'the 1320 tile field sweeps in %d s: small' % m['sweep'])
check('small' in H.size_flags(H.metrics(left[:5], field, 100)), 'few monsters are small')

# ---- band fit
check(H.band_fit([10, 12, 15, 90], 10, 20)[:2] == (0.75, 0.0) or H.band_fit([10, 12, 15, 90], 10, 20)[0] == 0.75, 'band share')
check(H.band_fit([], 1, 2) == (0.0, 0.0, 0), 'no monsters')

# ---- region and reach
ok = {(x, y, 7) for x in range(0, 40) for y in range(0, 40)}
walk = lambda p: p in ok
spot = lambda p: not (p[0] == 5 and p[1] == 5)
reg = H.region_tiles([(10, 10, 7)], walk, spot)
check(len(reg) == 13 * 13 - 1 and (5, 5, 7) not in H.region_tiles([(5, 5, 7)], walk, spot), 'region: %d' % len(reg))
check(len(H.region_tiles([(10, 10, 7)], walk, spot, allowed={(10, 10, 7)})) == 1, 'region limited to the allowed tiles')
two = ok | {(x, y, 8) for x in range(0, 10) for y in range(0, 10)}
hole = {(20, 20, 7): [dict(land=(5, 5, 8))]}
w2 = lambda p: p in two and p != (20, 20, 7)
r1 = H.reach_all(w2, hole, (1, 1, 7), (0, 0, 39, 39, 7, 8))
r2 = H.reach_all(w2, {}, (1, 1, 7), (0, 0, 39, 39, 7, 8))
check((5, 5, 8) in r1 and (5, 5, 8) not in r2, 'a hole leads to the floor below, without it the floor is cut off')
check(H.reach_all(w2, {}, (500, 500, 7), (0, 0, 39, 39, 7, 8)) == set(), 'a start that does not walk reaches nothing')

# ---- a planned hunt
plan = dict(id='demo', name='Demo', level=[10, 20], origin=dict(x=100, y=200, z=7), size=[60, 22], floors=1,
            spawns=[dict(monster='Rat', count=4), dict(monster='Cat', count=4)])
levels = {'rat': 12, 'cat': 15, 'dragon': 300, 'bear': 14}
level_of = lambda n: levels.get(n.lower(), 0)
fieldw = lambda p: p in field
nospot = lambda p: True
place = dict(id='demo', level=(10, 20), arrival=(105, 205, 7), monster='Rat')


def mk(name, i, content='demo'):
    return dict(x=100 + (i * 3) % 58, y=200 + (i * 5) % 22, z=7, name=name, content=content, hunt='')


good = [mk('Rat' if i % 2 else 'Cat', i) for i in range(60)] + [dict(x=102, y=203, z=7, name='Rat', content='', hunt='demo')]
row = H.audit_planned(plan, place, good, level_of, fieldw, nospot, {})
check(row['flags'] == [] or row['flags'] == ['dead'], 'a clean planned hunt: %r %s' % (row['flags'], row['detail']))
check(row['m']['monsters'] == 61 or row['m']['monsters'] == 60, 'monsters counted: %r' % row['m']['monsters'])
miss = H.audit_planned(plan, place, [e for e in good if e['name'] != 'Cat'], level_of, fieldw, nospot, {})
check('missing' in miss['flags'] and 'Cat' in miss['detail'], 'a monster of the plan without a spawn: %r' % miss['flags'])
alien = good + [dict(x=110 + i, y=210, z=7, name='Bear', content='', hunt='') for i in range(10)]
fr = H.audit_planned(plan, place, alien, level_of, fieldw, nospot, {})
check('foreign' in fr['flags'] and 'Bear' in fr['detail'], 'foreign monsters in the box: %r' % fr['flags'])
dis = H.audit_planned(plan, dict(place, monster='Dragon'), good, level_of, fieldw, nospot, {})
check('display' in dis['flags'], 'a sign that shows a monster that is not there')
arr = H.audit_planned(plan, dict(place, arrival=(5, 5, 7)), good, level_of, fieldw, nospot, {})
check('arrival' in arr['flags'], 'an arrival outside the box')
blocked = H.audit_planned(plan, place, good, level_of, lambda p: p in field and p[0] != 130, nospot, {})
check('cut' in blocked['flags'], 'a wall across the box cuts the far half off: %r' % blocked['flags'])
levels['rat'], levels['cat'] = 300, 300
bnd = H.audit_planned(plan, place, good, level_of, fieldw, nospot, {})
check('band' in bnd['flags'], 'monsters of level 300 in a 10-20 hunt: %r' % bnd['flags'])
levels['rat'], levels['cat'] = 12, 15
lvl = H.audit_planned(plan, dict(place, level=(10, 25)), good, level_of, fieldw, nospot, {})
check('band' in lvl['flags'] and '(10, 25)' in lvl['detail'], 'the places file band differs from the plan')
few = H.audit_planned(plan, place, good[:6], level_of, fieldw, nospot, {})
check('sparse' in few['flags'] and 'small' in few['flags'], 'six monsters on 1320 tiles: %r' % few['flags'])

# ---- a box area (waystone map, late game)
wbox = (100, 200, 159, 221, 7, 7)
area = H.audit_box_area('Map', 'waystone', wbox, (10, 20), {'Rat', 'Cat'}, [dict(e, content='') for e in good], level_of, fieldw, nospot)
check(area['kind'] == 'waystone' and 'foreign' not in area['flags'], 'a box area: %r' % area['flags'])
area2 = H.audit_box_area('Map', 'waystone', wbox, (10, 20), {'Rat', 'Dragon', 'Bear'}, [dict(e, content='') for e in good], level_of, fieldw, nospot)
check('missing' in area2['flags'] and 'foreign' in area2['flags'], 'declared monsters missing, the others foreign: %r' % area2['flags'])

# ---- references
plans = {'demo': dict(id='demo', name='Demo Hall', level=[10, 20])}
rows = H.audit_refs(plans, {'demo': (10, 25), 'gone': (1, 2)}, 'Where to hunt. Demo Hall (10-30), Other (5-9).', pl)
check(len(rows) == 3 and all(r['flags'] == ['ref'] for r in rows), 'three reference problems: %r' % [r['detail'] for r in rows])
check(H.audit_refs(plans, {'demo': (10, 20)}, 'Demo Hall (10-20)', pl) == [], 'matching references are quiet')

# ---- base hunts through audit_hunt_bands
try:
    import numpy as np
    import audit_hunt_transitions as AT
    import audit_hunt_bands as B
    lv = {'rat': 10, 'wolf': 12}
    pts = [(100 + (i * 7) % 30, 100 + (i * 3) % 30, 7, 'rat' if i % 2 else 'wolf') for i in range(60)]
    sp = AT.Spawns(pts, lv, {k: 1.0 for k in lv})
    gnd = {(x, y, 7) for x in range(60, 160) for y in range(60, 160)}
    hunt = dict(id='base_1', name='Rat', level=10, lo=5, hi=15, dest=(115, 115, 7), monsters=['Rat', 'Wolf'], x=None, y=None, z=None)
    brows = B.audit([hunt], sp, lambda p: p in gnd, lambda p: True, [], None, lambda *_: None, False)
    out = H.audit_base(brows, sp, lambda p: p in gnd, lambda p: True, [dict(id='base_1', teleport=(9, 9, 7), dest=(115, 115, 7))],
                       {(9, 9, 7): [dict(land=(1, 1, 7))]})
    check(len(out) == 1 and out[0]['kind'] == 'base' and out[0]['m']['monsters'] > 0, 'base hunt row: %r' % out)
    check('teleport' in out[0]['flags'], 'the map teleport leads elsewhere than the hunt: %r' % out[0]['flags'])
    out2 = H.audit_base(brows, sp, lambda p: p in gnd, lambda p: True, [dict(id='base_1', teleport=(9, 9, 7), dest=(115, 115, 7))],
                        {(9, 9, 7): [dict(land=(115, 115, 7))]})
    check('teleport' not in out2[0]['flags'], 'the teleport matches')
    # the annex of a base hunt (hunt_annexes.json): its ground and spawns join the hunt; problems are flagged
    aplan = dict(id='annex_1', origin=dict(x=500, y=500, z=9), size=[30, 20], floors=1)
    agnd = {(x, y, 9) for x in range(502, 526) for y in range(502, 516)}
    aent = [dict(x=505 + 4 * i, y=505, z=9, name='Rat', content='annex_1', hunt='') for i in range(6)]
    arow = dict(id='annex_1', hunt='base_1', portal=(112, 115, 7), dest=(503, 503, 9), back=(115, 115, 7))
    stack_ok = lambda p: [100, 1387] if p == (112, 115, 7) else [100]
    ents_, tiles_, bad_ = H.audit_annex(arow, aplan, aent, lambda p: p in agnd or p in gnd, lambda p: True, stack_ok)
    check(len(ents_) == 6 and len(tiles_) == len(agnd) and not bad_, 'annex: spawns and ground counted, nothing wrong: %r' % (bad_,))
    ents_, tiles_, bad_ = H.audit_annex(arow, aplan, [], lambda p: p in gnd, lambda p: True, lambda p: [100])
    check(any('not on the map' in b for b in bad_) and any('arrival' in b for b in bad_) and any('no portal' in b for b in bad_),
          'annex: missing area, arrival and portal reported: %r' % (bad_,))
    check(H.audit_annex(arow, None, [], lambda p: True, lambda p: True, stack_ok)[2] == ['no annex plan annex_1'], 'annex: no plan')
    plain = out2[0]['m']
    aent_xyz = [(e['x'], e['y'], e['z']) for e in aent]
    with_annex = H.audit_base(brows, sp, lambda p: p in gnd, lambda p: True, [], {}, None, None,
                              lambda hid: (aent_xyz, set(agnd), []) if hid == 'base_1' else None)
    check(with_annex[0]['m']['monsters'] == plain['monsters'] + 6 and with_annex[0]['m']['walkable'] == plain['walkable'] + len(agnd),
          'annex: the hunt\'s numbers include the annex: %r vs %r' % (with_annex[0]['m']['monsters'], plain['monsters']))
    broken = H.audit_base(brows, sp, lambda p: p in gnd, lambda p: True, [], {}, None, None, lambda hid: ([], set(), ['no portal at x']))
    check('annex' in broken[0]['flags'], 'annex: a broken annex is flagged: %r' % broken[0]['flags'])
except ImportError:
    print('numpy missing: the base hunt test is skipped')

# ---- hunt cluster, suggestion, rename
try:
    import numpy as np
    import audit_hunt_transitions as AT
    import hall_order as HO
    lv2 = {'wolf': 12, 'rat': 5, 'dragon': 300}
    pts = [(100 + (i * 7) % 30, 100 + (i * 3) % 20, 7, 'wolf' if i % 3 else 'rat') for i in range(60)]     # a pack field
    pts += [(300 + i * 2, 300, 7, 'wolf') for i in range(5)]                                               # a thin line far off
    pts += [(105 + i, 160, 7, 'dragon') for i in range(14)]                                               # dragons 40 tiles south
    sp2 = AT.Spawns(pts, lv2, {k: 1.0 for k in lv2})
    cl = H.hunt_cluster(sp2, [0])
    check(len(cl) == 60 and all(pts[i][0] < 200 and pts[i][3] != 'dragon' for i in cl), 'the cluster is the pack field: %d' % len(cl))
    check(len(H.hunt_cluster(sp2, [60])) == 5, 'the thin line is its own hunt')
    check(len(H.hunt_cluster(sp2, [0], cap=10)) >= 10, 'a cap stops the growth')
    land = {(x, y, 7) for x in range(0, 400) for y in range(0, 400)}
    wk = lambda p: p in land
    bad_hunt = dict(id='h', name='Wolf', level=200, lo=150, hi=250, dest=(300, 300, 7))
    sg = H.suggest_base(sp2, bad_hunt, ['Wolf', ''], wk, lambda p: True, {}, [(300, 300, 7)])
    check(len(sg) == 1 and 95 <= sg[0]['arrival'][0] <= 135 and 95 <= sg[0]['arrival'][1] <= 125, 'a better area for the wolf sign: %r' % [c['arrival'] for c in sg])
    check(sg and sg[0]['band'][0] <= 12 <= sg[0]['band'][1] and sg[0]['band'][1] <= 3 * max(1, sg[0]['band'][0]) + 3, 'its band is the wolf level: %r' % (sg and sg[0]['band'],))
    check(not H.suggest_base(sp2, bad_hunt, ['Dragon', ''], wk, lambda p: True, {}, []), 'dragons in a line of 14 are a small hunt: no suggestion')
    tmpd = tempfile.mkdtemp()
    cp2 = os.path.join(tmpd, 'h.csv')
    rows0 = [dict(id='base_1', z=7, x=1, y=2, dest_x=3, dest_y=4, dest_z=5, kind='hunt', name='Elephant', level=8, lo=5, hi=10,
                  display='Elephant', spawntime=60, monsters='Elephant|Wasp|Bug', note='old')]
    HO.write_csv(rows0, cp2)
    n = H.apply_renames([(dict(id='base_1'), 'Wasp')], cp2, lambda *_: None)
    back = HO.read_csv(cp2)[0]
    check(n == 1 and back['name'] == 'Wasp' and back['display'] == 'Wasp' and back['monsters'] == 'Wasp|Bug' and back['note'].startswith('renamed O337 from Elephant'),
          'rename: %r' % back)
    check(H.apply_renames([(dict(id='base_1'), 'Wasp')], cp2, lambda *_: None) == 0, 'a second rename changes nothing')
except ImportError:
    print('numpy missing: the suggestion test is skipped')

# ---- generated tables
old_t = '\t["rat"] = {spawns = 3, areas = {{1, 2, 7, 3}}},\n\t["wolf"] = {spawns = 2, areas = {{1, 2, 7, 2}}},\n'
new_t = '\t["rat"] = {spawns = 3, areas = {{1, 2, 7, 3}}},\n\t["wolf"] = {spawns = 9, areas = {{1, 2, 7, 9}}},\n\t["bear"] = {spawns = 4, areas = {{1, 2, 7, 4}}},\n'
check(H.pool_entries(old_t) == {'rat': 3, 'wolf': 2}, 'bestiary rows')
check(H.pool_entries('\t\t{name = "Dragon Lord", level = 73, exp = 2, health = 3, spawns = 55, look = 1},') == {'dragon lord': 55}, 'pool rows')
check(H.audit_generated('x', old_t, old_t) is None, 'equal tables are quiet')
g = H.audit_generated('x', old_t, new_t)
check(g and g['flags'] == ['stale'] and '1 monsters of the map are not in the file (bear)' in g['detail'] and '1 counts differ' in g['detail'], 'stale table: %r' % (g and g['detail'],))

# ---- known list, check, outputs
tmp = tempfile.mkdtemp()
kp = os.path.join(tmp, 'known.csv')
open(kp, 'w').write('# comment\nid,flag,reason\ndemo,dead,map edit\ngone,small,old\n')
known = H.read_known(kp)
rws = [dict(kind='planned', id='demo', name='Demo', level=15, lo=10, hi=20, flags=['dead', 'sparse'], detail='x|y', in_share=1.0,
            far_share=0.0, median=12, m=m, own=3, floors=1)]
new, stale = H.check_rows(rws, known)
check(new == [('demo', 'sparse')] and stale == [('gone', 'small')], 'check: new %r stale %r' % (new, stale))
md = H.render_md(rws, known)
check('dead*' in md and 'sparse' in md and 'x/y' in md and '|' in md, 'markdown: starred known defect, pipes cleaned')
cp = os.path.join(tmp, 'a.csv')
H.write_csv(cp, rws)
check(open(cp).read().startswith('kind,id,name'), 'csv header')
check(H.render_md(rws, known) == md, 'the markdown is deterministic')

print('audit_hunts_test: %s' % ('ok' if not fails else '%d failure(s)' % fails))
sys.exit(1 if fails else 0)
