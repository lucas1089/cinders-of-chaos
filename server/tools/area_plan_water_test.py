#!/usr/bin/env python3
"""Tests of the planner's rivers, lakes, bridges and fords (O739, server/README.md "Rivers, lakes, bridges and fords
(O739)"): the plan rules of `water`, the generator's def (lakes off the zone centre), the river example compiled with
no QA error or warning, every walkable tile reached, one INFO chokepoint line per crossing, no spawn, chest, NPC or
decoration on water or a crossing, shore pieces only on water next to land, deep water never walkable, the same bytes
twice, and a plan without `water` untouched (no water numbers, no water ids). Needs luajit or lua5.3 (the generator).

usage: python3 -I server/tools/area_plan_water_test.py
"""
import copy
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import area_plan_compile as PC  # noqa: E402
import area_plan_core as C  # noqa: E402
import area_plan_rank as R  # noqa: E402

checks = fails = 0


def ok(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


EX = os.path.join(HERE, 'areaplan', 'examples')
river = json.load(open(os.path.join(EX, 'river_hunt.json'), encoding='utf-8'))
swamp = json.load(open(os.path.join(EX, 'swamp_hunt.json'), encoding='utf-8'))
cat = C.catalogue(False)


def errors(plan):
    return [str(i) for i in C.validate(plan, cat) if i.level == 'ERROR']


# ------------------------------------------------------------------------------------------------ plan rules
ok(not errors(river), 'the river example validates: %s' % errors(river))
p = copy.deepcopy(river)
p['water']['lakes'][0]['zone'] = 'meer'
ok(any('no zone "meer"' in m for m in errors(p)), 'a lake in an unknown zone is an error')
p = copy.deepcopy(river)
p['water']['rivers'][0]['floor'] = 2
ok(any('floor 2' in m for m in errors(p)), 'a river on a floor the plan has not is an error')
p = copy.deepcopy(river)
p['water']['rivers'][0]['width'] = [5, 3]
ok(any('lowest width' in m for m in errors(p)), 'a width range high to low is an error')
p = copy.deepcopy(river)
p['water']['rivers'][0]['course'] = 'east-north'
ok(errors(p), 'an unknown course is a schema error')
p = copy.deepcopy(river)
p['water']['tides'] = 2
ok(errors(p), 'an unknown water field is a schema error')

# ------------------------------------------------------------------------------------------------ the generator's def
lay = C.layout(river, cat)
job = PC.job_def(river, cat, lay)
w = job['water']
ok(w['rivers'] == [dict(course='north-south', floor=1, width=[3, 5], at=50)], 'the river def: %s' % w['rivers'])
ok(w['fords'] == 1 and len(w['lakes']) == 1, 'one lake, one ford wanted')
x1, y1, x2, y2 = lay['rects']['mere'][:4]
lk = w['lakes'][0]
ok(x1 <= lk['x'] <= x2 and y1 <= lk['y'] <= y2, 'the lake lies in its zone')
ok((lk['x'], lk['y']) != ((x1 + x2) // 2, (y1 + y2) // 2), 'the lake is off the zone centre (the centre stays dry)')
q = copy.deepcopy(river)
q['water']['lakes'][0]['place'] = 'center'
ok((PC.water_def(q, lay)['lakes'][0]['x'], PC.water_def(q, lay)['lakes'][0]['y']) == ((x1 + x2) // 2, (y1 + y2) // 2),
   'place center puts it on the centre')
ok('water' not in PC.job_def(swamp, cat, C.layout(swamp, cat)), 'a plan without water: no water in the job')

# ------------------------------------------------------------------------------------------------ the compiled example
res = PC.compile_plan(river, pair24=False, cat=cat)
bad = [(l, m) for l, m in res['qa'] if l in ('ERROR', 'WARN')]
ok(not bad, 'the river example has no QA error or warning: %s' % bad[:3])
st = res['stats']
ws = st.get('water') or {}
ok(ws.get('rivers') == 1 and ws.get('lakes') == 1, 'one river, one lake: %s' % ws)
ok(ws.get('bridges', 0) >= 1 and ws.get('fords', 0) >= 1, 'at least one bridge and one ford: %s' % ws)
ok(ws.get('deep', 0) > 50, 'deep water tiles: %s' % ws.get('deep'))
ok(st['reach']['share'] == 0 and st['reach']['left_share'] == 0, 'nothing out of reach: %s' % st['reach'])
ok(st['unbordered'] == 0 and st['unknown_ids'] == 0, 'every border closed, no unknown id')
ok(set(st['zone_steps']) == {z['id'] for z in river['zones']}, 'every zone reached across the water')
info = [m for l, m in res['qa'] if l == 'INFO' and m.startswith('chokepoint: ')]
ok(len(info) == ws.get('crossings') and len(info) >= 2, 'one chokepoint line per crossing: %s' % info)
ok(R.score_parts(river, res, look=False)['qa'] == 0, 'the INFO lines cost the rank nothing')

tiles, walk = res['tiles'], res['walk']
# the water grounds of the compile: the families named in the generator's own config
lua = 'luajit' if subprocess.call(['which', 'luajit'], stdout=subprocess.DEVNULL) == 0 else 'lua5.3'
SERVER = os.path.dirname(HERE)
out = subprocess.run([lua, '-e', 'local c = dofile("data/scripts/chaos/areagen_config.lua") local W = c.water '
                      'for k, n in pairs(W.fams) do print("F " .. k .. " " .. W.families[n].grounds[1][1]) end '
                      'for k, id in pairs(W.shore) do print("S " .. k .. " " .. id) end'],
                     cwd=SERVER, capture_output=True, text=True, check=True).stdout.split('\n')
kind_of, shore = {}, set()
for line in out:
    f = line.split()
    if len(f) == 3 and f[0] == 'F':
        kind_of[int(f[2])] = f[1]
    elif len(f) == 3 and f[0] == 'S':
        shore.add(int(f[2]))
ok(len(kind_of) == 3 and len(shore) == 19, 'the config: 3 water grounds, 19 shore pieces')
crossing = {k for k, t in tiles.items() if kind_of.get(t['ground']) in ('ford', 'bridge')}
deep = {k for k, t in tiles.items() if kind_of.get(t['ground']) == 'deep'}
ok(crossing and crossing <= walk, 'every bridge and ford tile is walkable (%d)' % len(crossing))
ok(not (deep & walk), 'no deep water tile is walkable')


def near(t, d=1):
    return {(t[0] + dx, t[1] + dy, t[2]) for dx in range(-d, d + 1) for dy in range(-d, d + 1)}


spots = [(s['x'], s['y'], s['z']) for s in res['spawns']] + [tuple(c['at']) for c in res['chests']]
spots += [(n['x'], n['y'], n['z']) for n in res['npcs']]
ok(not [s for s in spots if s in deep or near(s) & crossing], 'no spawn, chest or NPC on water or beside a crossing')
deco = [t for t, _i, _g, _c in res['dresser'].placed]
ok(not [t for t in deco if t in crossing or t in deep], 'no decoration on water or a crossing')
wrong, missing = [], []
for k, t in tiles.items():
    ids = {i for i, _a in t['items']}
    water = kind_of.get(t['ground']) in ('deep', 'ford')
    land_side = any((n in tiles and n not in deep and kind_of.get(tiles[n]['ground']) not in ('deep', 'ford', 'bridge'))
                    for n in ((k[0], k[1] - 1, k[2]), (k[0] + 1, k[1], k[2]), (k[0], k[1] + 1, k[2]), (k[0] - 1, k[1], k[2])))
    if ids & shore and not water:
        wrong.append(k)
    if water and land_side and not ids & shore:
        missing.append(k)
ok(not wrong, 'shore pieces lie only on water: %s' % wrong[:3])
ok(not missing, 'every water tile beside land has its shore piece: %s' % missing[:3])
res2 = PC.compile_plan(river, pair24=False, cat=cat)
ok(res2['otbm'] == res['otbm'] and res2['spawn_xml'] == res['spawn_xml'], 'the same plan gives the same bytes')

# ------------------------------------------------------------------------------------------------ off: a plan without water
dry = PC.compile_plan(swamp, pair24=False, cat=cat)
ok('water' not in dry['stats'], 'a plan without water: no water numbers in the manifest')
ok(not any(kind_of.get(t['ground']) or {i for i, _a in t['items']} & shore for t in dry['tiles'].values()),
   'a plan without water: no water ground and no shore piece')
ok(not [m for l, m in dry['qa'] if l == 'INFO'], 'a plan without water: no chokepoint line')

print('  river example: %s; %d spawns, %d decoration pieces' % (ws, len(res['spawns']), len(deco)))
print('area plan water: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
