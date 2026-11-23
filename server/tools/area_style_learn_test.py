#!/usr/bin/env python3
"""Tests of the area planner style profiles (O743, server/README.md "Style profile (O743)"): area_style_learn.py on a
synthetic painted area (OTBM by map_guard_testkit): the shares per class, the statistics, unknown ids reported and
dropped, a box under 200 walkable tiles refused, the same bytes twice, no position or layout in the profile; the
compile of a plan with a style learned from that reference: the generator takes the profile's floor and patches (and
drops a family or patch it cannot use), the decoration kit and density follow the profile, and the copy guard: no 8 x 8
window of the output (items by tile, windows with 4+ items) equals one of the reference; the shipped profile
gravewatch_crypt is what the learner gives on the compiled crypt example, and the example hollowgate_vault compiles
with it with no QA error or warning; the validator; a plan without `style` untouched. Needs luajit or lua5.3.

usage: python3 -I server/tools/area_style_learn_test.py
"""
import copy
import io
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import area_plan_compile as PC  # noqa: E402
import area_plan_core as C  # noqa: E402
import area_plan_decor as D  # noqa: E402
import area_plan_style as ST  # noqa: E402
import area_style_learn as L  # noqa: E402
import map_guard_testkit as K  # noqa: E402

checks = fails = 0


def ok(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL ' + what)


EX = os.path.join(HERE, 'areaplan', 'examples')
cat = C.catalogue(False)
mats = C.materials(False)
SC = ST.catalogue(True)
fam = mats['families']
groups = ST.D.kits()['groups']
UNKNOWN = next(i for i in range(39000, 40000) if i not in SC['legal'])


# ------------------------------------------------------------------------------------------------ a painted reference
def reference(w=44, h=34, seed=743, origin=(1000, 1000, 7)):
    """a glade: st_grass with st_dirt patches, a mountain rim, grass tufts, flowers, pebbles and bushes in little
    groups, two unknown items -> {(x, y, z): [ids]} (ground first)"""
    rng = random.Random(seed)
    ox, oy, oz = origin
    out = {}
    patches = [(rng.randrange(6, w - 6), rng.randrange(6, h - 6)) for _ in range(5)]
    for y in range(h):
        for x in range(w):
            p = (ox + x, oy + y, oz)
            if x < 2 or y < 2 or x >= w - 2 or y >= h - 2:
                out[p] = [919]
                continue
            dirt = any((x - a) ** 2 + (y - b) ** 2 <= 5 for a, b in patches)
            out[p] = [103 if dirt else rng.choice(fam['st_grass']['grounds'])]
    inner = [p for p, st in out.items() if st[0] != 919]
    rng.shuffle(inner)
    for p in inner[:40]:          # group anchors with 1-5 neighbours
        for k in range(rng.randint(1, 6)):
            q = (p[0] + rng.randint(-1, 1), p[1] + rng.randint(-1, 1), p[2])
            if q in out and out[q][0] != 919 and len(out[q]) == 1:
                g = rng.choice(['grass_tufts', 'grass_tufts', 'flowers', 'pebbles', 'bushes'])
                out[q].append(rng.choice(groups[g]['ids']))
    for p in inner[40:42]:
        if len(out[p]) == 1:
            out[p].append(UNKNOWN)
    return out


def otbm_of(stacks):
    return K.build({p: [K.item(i) for i in st] for p, st in stacks.items()})


tmp = tempfile.mkdtemp(prefix='o743_')
try:
    ref = reference()
    path = os.path.join(tmp, 'glade.otbm')
    open(path, 'wb').write(otbm_of(ref))
    box = '1000,1000,1043,1033,7'
    buf = io.StringIO()
    code = L.main([path, '--box', box, '--name', 'test_glade', '--json', os.path.join(tmp, 'a.json')], out=buf)
    ok(code == 0, 'learn: exit 0 (%s)' % buf.getvalue()[-300:])
    prof = json.load(open(os.path.join(tmp, 'a.json')))
    walk_want = sum(1 for st in ref.values() if st[0] != 919 and not any(groups['bushes']['block'] and i in groups['bushes']['ids'] for i in st[1:]))
    ok(prof['source']['walkable'] == walk_want, 'learn: %d walkable tiles (want %d: no rim, no bush)' % (prof['source']['walkable'], walk_want))
    gf = prof['grounds']['families']
    ok(set(gf) == {'st_grass', 'st_dirt'} and gf['st_grass'] > gf['st_dirt'] > 0.02, 'learn: ground families %s' % gf)
    ok(prof['grounds']['unwalked'] == {'mountain': 1.0}, 'learn: the rim is ground nobody walks on: %s' % prof['grounds']['unwalked'])
    dg = prof['decor']['groups']
    ok(set(dg) == {'grass_tufts', 'flowers', 'pebbles', 'bushes'}, 'learn: decoration groups %s' % sorted(dg))
    ok(abs(sum(dg.values()) - 1) < 0.01 and abs(sum(gf.values()) - 1) < 0.01, 'learn: shares sum to 1')
    ok(prof['dropped_items'] == 2 and str(UNKNOWN) not in json.dumps(prof['decor']['ids']),
       'learn: the unknown id %d is dropped (%d items)' % (UNKNOWN, prof['dropped_items']))
    ok(('dropped 2 item(s) of 1 unknown id(s): %d x2' % UNKNOWN) in buf.getvalue(), 'learn: the unknown id is reported')
    n_deco = sum(1 for st in ref.values() for i in st[1:] if i != UNKNOWN)
    ok(abs(prof['density']['decor_per100'] - round(100.0 * n_deco / walk_want, 3)) < 0.01,
       'learn: %.2f decoration items per 100 walkable tiles' % prof['density']['decor_per100'])
    ok(0 < prof['density']['vegetation_per100'] < prof['density']['decor_per100'] and prof['density']['block_per100'] > 0,
       'learn: vegetation and blocking subsets %s' % prof['density'])
    ok(prof['clusters']['per100'] > 0 and abs(sum(prof['clusters']['sizes'].values()) - 1) < 0.01, 'learn: cluster sizes')
    ok(prof['walls']['brushes'] == {} and prof['wall_runs']['mean'] == 0, 'learn: no wall in a glade')
    ok(0 < prof['open_share'] < 1 and abs(sum(prof['corridor_width'].values()) - 1) < 0.01, 'learn: open share, corridor widths')
    ok(ST.problems(prof) == [], 'learn: the profile is a usable profile: %s' % ST.problems(prof))
    text = json.dumps(prof)
    ok('1000,' not in text.replace(box, '') and all(k not in prof for k in ST.FORBIDDEN),
       'copy guard: the profile holds no position and no layout (only the box it was learned from)')
    bad = copy.deepcopy(prof)
    bad['decor']['tiles'] = [[1000, 1000, 7, 4526]]
    ok(ST.problems(bad), 'copy guard: a profile with a tile list is refused')
    L.main([path, '--box', box, '--name', 'test_glade', '--json', os.path.join(tmp, 'b.json')], out=io.StringIO())
    ok(open(os.path.join(tmp, 'a.json')).read() == open(os.path.join(tmp, 'b.json')).read(), 'learn: the same bytes twice')
    # a box under 200 walkable tiles: refused
    buf = io.StringIO()
    code = L.main([path, '--box', '1000,1000,1015,1015,7', '--name', 'small', '--json', os.path.join(tmp, 'c.json')], out=buf)
    ok(code == 2 and 'refused' in buf.getvalue() and not os.path.exists(os.path.join(tmp, 'c.json')),
       'learn: a box of 144 walkable tiles is refused: %s' % buf.getvalue().strip())
    buf = io.StringIO()
    ok(L.main([path, '--box', box, '--name', 'Bad-Key'], out=buf) == 2, 'learn: a key that is not lower-case is refused')
    # --write goes to the styles folder (here a temporary one)
    sdir = os.path.join(tmp, 'styles')
    L.main([path, '--box', box, '--name', 'test_glade', '--write', '--style-dir', sdir], out=io.StringIO())
    ok(os.path.isfile(os.path.join(sdir, 'test_glade.json')), 'learn: --write writes styles/<key>.json')

    # ------------------------------------------------------------------------------------------------ the compile
    ST.STYLE_DIR = sdir
    river = json.load(open(os.path.join(EX, 'river_hunt.json')))
    plain_r = PC.compile_plan(river, pair24=False, cat=cat)
    styled = copy.deepcopy(river)
    styled['style'] = 'test_glade'
    ok(not C.errors(C.validate(styled, cat, False)), 'validator: a plan with a known style validates')
    r = PC.compile_plan(styled, pair24=False, cat=cat)
    st = r['stats']['style']
    ok(st['generator'].get('floor') == 'st_grass' and [p['family'] for p in st['generator'].get('patches', [])] == ['st_dirt'],
       'compile: the generator takes the profile floor and patches: %s' % st['generator'])
    ok(abs(st['density_factor'] - prof['density']['decor_per100'] / ST.REF_PER100) < 0.01 or st['density_factor'] in ST.DENSITY_RANGE,
       'compile: the density factor %.3f from the profile' % st['density_factor'])
    placed = [g for _t, _i, g, _c in r['dresser'].placed]
    mine = sum(1 for g in placed if g in dg)
    ok(placed and mine / float(len(placed)) >= 0.75, 'compile: %d of %d decoration pieces are of the profile groups' % (mine, len(placed)))
    ok(not PC.qa_errors(r), 'compile: no QA error with the style: %s' % PC.qa_errors(r))
    out = {k: [t['ground']] + [i for i, _a in t['items']] for k, t in r['tiles'].items()}
    ok(ST.window_matches(ref, out) == [], 'copy guard: no 8 x 8 window of the output equals one of the reference')
    ok(len(ST.window_matches(ref, ref)) > 0, 'copy guard: the reference against itself matches (the guard sees a copy)')
    ok(plain_r['manifest']['stats'].get('style') is None and PC.style_of(river, cat, False, False) == (None, None),
       'off by default: no style entry, no job.style without the field')
    r2 = PC.compile_plan(styled, pair24=False, cat=cat)
    ok(r2['otbm'] == r['otbm'], 'compile: the same bytes twice with a style')
    # density follows the profile
    dense = copy.deepcopy(prof)
    dense['density']['decor_per100'] = prof['density']['decor_per100'] * 2
    sparse = copy.deepcopy(prof)
    sparse['density']['decor_per100'] = prof['density']['decor_per100'] / 3
    for k, p in (('test_dense', dense), ('test_sparse', sparse)):
        p['key'] = k
        json.dump(p, open(os.path.join(sdir, k + '.json'), 'w'))
    n = {}
    for k in ('test_dense', 'test_sparse'):
        pl = copy.deepcopy(river)
        pl['style'] = k
        n[k] = len(PC.compile_plan(pl, pair24=False, cat=cat)['dresser'].placed)
    ok(n['test_dense'] > n['test_sparse'], 'compile: a denser profile places more (%d against %d)' % (n['test_dense'], n['test_sparse']))
    # O745: lights follow the profile's light density against the kind's reference
    crypt_plan = json.load(open(os.path.join(EX, 'crypt_boss.json')))
    lit = json.load(open(os.path.join(C.PLANDIR, 'styles', 'gravewatch_crypt.json')))
    dim = copy.deepcopy(lit)
    lit['density']['light_per100'] = ST.REF_LIGHT_PER100['dungeon'] * 3
    dim['density']['light_per100'] = ST.REF_LIGHT_PER100['dungeon'] / 3
    nl, lf = {}, {}
    for k, p in (('test_lit', lit), ('test_dim', dim)):
        p['key'] = k
        json.dump(p, open(os.path.join(sdir, k + '.json'), 'w'))
        pl = copy.deepcopy(crypt_plan)
        pl['style'] = k
        rr = PC.compile_plan(pl, pair24=False, cat=cat)
        nl[k] = sum(1 for _t, _i, g, _c in rr['dresser'].placed if rr['dresser'].groups[g]['light'])
        lf[k] = rr['stats']['style']['light_factor']
    ok(lf == {'test_lit': ST.LIGHT_RANGE[1], 'test_dim': ST.LIGHT_RANGE[0]}
       and nl['test_lit'] > nl['test_dim'], 'O745 compile: a brighter profile lights more (%s, factors %s)' % (nl, lf))
    # O745: the debris share in the categories that keep the biome's rows
    deb = copy.deepcopy(prof)
    deb['key'] = 'test_debris'
    deb['decor']['groups'] = {}
    deb['density']['debris_per100'] = deb['density']['decor_per100'] * 0.4
    json.dump(deb, open(os.path.join(sdir, 'test_debris.json'), 'w'))
    pl = copy.deepcopy(river)
    pl['style'] = 'test_debris'
    rd = PC.compile_plan(pl, pair24=False, cat=cat)
    sd = rd['stats']['style']
    base_kit = D.kit_for(river['biome'])[1]
    dgs = ST.debris_groups(D.kits()['groups'])
    doubled = all(w == max(1, int(round(bw * 2.0))) for c in sd['debris_categories']
                  for (g, w), (_g, bw) in zip(rd['dresser'].kit[c], base_kit[c]) if g in dgs)
    ok(sd['debris_factor'] == ST.DEBRIS_RANGE[1] and sd['debris_categories'] and doubled,
       'O745 compile: a debris share of 0.4 (the waste kind holds %.2f) doubles the debris weight in %s'
       % (ST.REF_DEBRIS_PER100['waste'] / ST.REF_DECOR_PER100['waste'], sd['debris_categories']))
    # O745: a path with no width takes the profile's most common corridor width
    wide = copy.deepcopy(prof)
    wide['key'] = 'test_wide'
    wide['corridor_width'] = {'1': 0.1, '3': 0.2, '5': 0.3, '7+': 0.4}
    json.dump(wide, open(os.path.join(sdir, 'test_wide.json'), 'w'))
    seen = []
    real_layout = C.layout
    C.layout = lambda pl_, cat_: (seen.append([q.get('width') for q in pl_.get('paths', [])]), real_layout(pl_, cat_))[1]
    try:
        pl = copy.deepcopy(river)
        pl['style'] = 'test_wide'
        pl['paths'][0]['width'] = 2
        for q in pl['paths'][1:]:
            q.pop('width', None)
        rw = PC.compile_plan(pl, pair24=False, cat=cat)
    finally:
        C.layout = real_layout
    ok(seen and seen[-1] == [2] + [5] * (len(pl['paths']) - 1) and rw['stats']['style']['path_width'] == 5
       and 'width' not in pl['paths'][1], 'O745 compile: paths with no width take 5 tiles, a named width stays: %s' % seen[-1:])
    # the generator drops what it cannot use
    lay = C.layout(river, cat)
    _a, meta = PC.run_build(river, cat, lay, False, False, dict(floor='no_such_family', patches=[
        dict(family='no_such_family', share=0.1, radius=[2, 4]), dict(family='st_dirt', share=0.1, radius=[2, 4])]))
    _a0, meta0 = PC.run_build(river, cat, lay, False, False)
    ok('no_such_family' not in meta['families'] and 'st_dirt' in meta['families'] and 'st_grass' in meta['families'],
       'generator: an unknown family is left out, a usable patch is kept: %s' % sorted(meta['families']))
    _a2, meta2 = PC.run_build(river, cat, lay, False, False, dict(wall='ruin'))
    ok(meta2.get('walls') == meta0.get('walls'), 'generator: a wall brush only in a dungeon')
    # the validator
    p = copy.deepcopy(river)
    p['style'] = 'no_such_style'
    ok(any('plan.style' in str(i) for i in C.errors(C.validate(p, cat, False))), 'validator: an unknown style is an ERROR')
    p['style'] = 'Bad Key'
    ok(any('plan.style' in str(i) for i in C.errors(C.validate(p, cat, False))), 'validator: a bad key breaks the schema')
finally:
    shutil.rmtree(tmp, ignore_errors=True)
    ST.STYLE_DIR = os.path.join(C.PLANDIR, 'styles')

# ------------------------------------------------------------------------------------------------ the shipped profile
crypt = json.load(open(os.path.join(EX, 'crypt_boss.json')))
rc = PC.compile_plan(crypt, pair24=False, cat=cat)
ox, oy, oz = rc['origin']
x2, y2 = ox + crypt['size'][0] - 1, oy + crypt['size'][1] - 1
cstacks = {k: [t['ground']] + [i for i, _a in t['items']] for k, t in rc['tiles'].items()
           if k[2] == oz and ox <= k[0] <= x2 and oy <= k[1] <= y2}
want, _rep = L.learn(cstacks, SC, 'gravewatch_crypt', dict(name='gravewatch_crypt.otbm', box='%d,%d,%d,%d,%d' % (ox, oy, x2, y2, oz)))
have = ST.load('gravewatch_crypt')
ok(have == json.loads(json.dumps(want)), 'shipped: styles/gravewatch_crypt.json is what the learner gives on the compiled crypt example '
   '(area_style_learn.py gravewatch_crypt.otbm --box %d,%d,%d,%d,%d --name gravewatch_crypt --write)' % (ox, oy, x2, y2, oz))
ok(ST.keys() == ['gravewatch_crypt'], 'shipped: one profile: %s' % ST.keys())
vault = json.load(open(os.path.join(EX, 'hollowgate_vault.json')))
ok(vault.get('style') == 'gravewatch_crypt' and vault['biome'] == 'vault', 'example: hollowgate_vault is a vault with the style')
rv = PC.compile_plan(vault, pair24=False, cat=cat)
ok(not [q for q in rv['qa'] if q[0] in ('ERROR', 'WARN')], 'example: no QA error or warning: %s' % [q for q in rv['qa'] if q[0] != 'INFO'][:3])
sv = rv['stats']['style']
ok(abs(sv['light_factor'] - 6.15 / ST.REF_LIGHT_PER100['dungeon']) < 0.001 and sv['path_width'] == 3 and sv['debris_categories'] == []
   and abs(sv['debris_factor'] - (21.524 / 46.658) / (ST.REF_DEBRIS_PER100['dungeon'] / ST.REF_DECOR_PER100['dungeon'])) < 0.001,
   'O745 example: light factor %.3f, debris factor %.3f (every category from the profile), paths of 3' % (sv['light_factor'], sv['debris_factor']))
ok(sv['generator'].get('wall') == 'ruin' and sv['generator'].get('floor') == 'slate', 'example: ruin walls and slate floors from the profile: %s' % sv['generator'])
vstacks = {k: [t['ground']] + [i for i, _a in t['items']] for k, t in rv['tiles'].items()}
ok(ST.window_matches(cstacks, vstacks) == [], 'example: copy guard against the reference floor')
plain_v = copy.deepcopy(vault)
del plain_v['style']
pv = PC.compile_plan(plain_v, pair24=False, cat=cat)
fams_v = {f for t in rv['tiles'].values() for f in [SC['ground'].get(t['ground'])] if f}
fams_p = {f for t in pv['tiles'].values() for f in [SC['ground'].get(t['ground'])] if f}
ok(fams_v != fams_p, 'example: the style changes the grounds (%s against the vault default %s)' % (sorted(fams_v), sorted(fams_p)))

# O745: the path width rule
ok(ST.path_width({'corridor_width': {'2': 0.3, '4': 0.3}}) == 2 and ST.path_width({'corridor_width': {'5': 0.3, '3': 0.3}}) == 3,
   'path width: a tie goes to the width nearest 3, then the narrower')
ok(ST.path_width({'corridor_width': {'1': 0.5, '7+': 0.5}}) == 3 and ST.path_width({}) == 3, 'path width: 3 with no corridor of 2-6')
ok(ST.path_width({'corridor_width': {'3': 0.2, '6': 0.25}}) == 6, 'path width: the most common of 2-6')

# ------------------------------------------------------------------------------------------------ Lua: both interpreters
outs = []
for lua in ('luajit', 'lua5.3'):
    if shutil.which(lua):
        res = subprocess.run([lua, 'tools/areaplan_build.lua', 'styleids'], cwd=C.SERVER, capture_output=True, text=True)
        ok(res.returncode == 0, '%s: styleids runs: %s' % (lua, res.stderr[-200:]))
        outs.append(res.stdout)
ok(len(set(outs)) == 1, 'styleids: the same ids under luajit and lua5.3')

print('area style learn: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
