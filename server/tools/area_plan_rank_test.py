#!/usr/bin/env python3
"""Tests of the area planner's candidate ranking and reach repair (O738, server/README.md "Area planner candidates and
reach repair (O738)"): seeds of the candidates, one candidate is the plain compile byte for byte, the ranking is
deterministic, the best is the highest score, a failing seed ranks last, the CLI writes the table; then the reach
repair through the planner: a path piece cut off from the zones (added to the layout by the test) is closed with rock
without `repair_reach` (no "reach" key in the manifest) and joined by a carved link with it (the stats name the pocket,
nothing is left out of reach, no new QA error). Needs LuaJIT (the generator). Run: python3 -I server/tools/area_plan_rank_test.py
"""
import copy
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import area_plan_compile as PC  # noqa: E402
import area_plan_core as C  # noqa: E402
import area_plan_rank as R  # noqa: E402
import area_planner  # noqa: E402

checks = fails = 0


def ok(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL ' + what)


EX = os.path.join(HERE, 'areaplan', 'examples')
SWAMP = json.load(open(os.path.join(EX, 'swamp_hunt.json')))
VILLAGE = json.load(open(os.path.join(EX, 'village_square.json')))
cat = C.catalogue(False)


def digest(res):
    h = hashlib.sha256()
    h.update(res['otbm'])
    h.update(res['frame_otbm'])
    h.update(res['spawn_xml'].encode())
    h.update(json.dumps(res['manifest'], sort_keys=True).encode())
    return h.hexdigest()


# ------------------------------------------------------------------------------------------------ seeds
ok(R.seed_of(24101, 1) == 24101, 'candidate 1 is the plan\'s own seed')
seeds = [R.seed_of(24101, k) for k in range(1, 9)]
ok(len(set(seeds)) == 8, 'eight different seeds %s' % seeds)
ok(all(1 <= s <= 2000000000 for s in seeds + [R.seed_of(1999999999, 5)]), 'seeds stay in the schema range')

# ------------------------------------------------------------------------------------------------ ranking
plain = PC.compile_plan(SWAMP, pair24=False, cat=cat)
rows1, res1 = R.rank(SWAMP, 1, pair24=False, cat=cat)
ok(len(rows1) == 1 and rows1[0]['seed'] == C.plan_seed(SWAMP), 'one candidate: the plan\'s seed')
ok(digest(res1) == digest(plain), 'one candidate: the same bytes as the plain compile')
rows, best = R.rank(SWAMP, 6, pair24=False, cat=cat)
rows_b, best_b = R.rank(SWAMP, 6, pair24=False, cat=cat)
ok(rows == rows_b and digest(best) == digest(best_b), 'six candidates: deterministic')
scores = [r['score'] for r in rows]
ok(all(s is not None for s in scores), 'six candidates: every seed compiles')
top = max(scores)
first = min(r['k'] for r in rows if r['score'] == top)
ok(best['manifest']['seed'] == rows[first - 1]['seed'], 'the kept compile is the best score (ties: lowest candidate)')
ok(all(set(r['parts']) == set(R.PARTS) for r in rows), 'every row has the five parts')
ok(all(abs(r['score'] - (100 - sum(r['parts'].values()))) < 0.02 for r in rows), 'score = 100 - the parts')
spread = max(scores) - min(scores)
print('  swamp_hunt, 6 seeds: scores %.2f-%.2f (spread %.2f), kept seed %d'
      % (min(scores), max(scores), spread, best['manifest']['seed']))
ok(spread > 0, 'the seeds differ in score')
txt = R.table(SWAMP['id'], rows)
lines = txt.splitlines()
ok(len(lines) == 6 + 3 and '*' in txt and 'reach' in lines[1], 'table: a header, six rows, the own seed marked')
ok(lines[2].split()[3] == '%.2f' % top, 'table: best first')


def boom(p):
    if p['seed'] == R.seed_of(C.plan_seed(SWAMP), 2):
        raise PC.CompileError('the plan has errors:\nsynthetic failure')
    return PC.compile_plan(p, pair24=False, cat=cat)


frows, fbest = R.rank(SWAMP, 3, compile_fn=boom, look=False)
ok(frows[1]['score'] is None and 'errors' in frows[1]['error'], 'a failing seed: no score, the error kept')
ok(R.table('x', frows).splitlines()[-2].split()[3] == '-', 'a failing seed ranks last')
ok(fbest is not None, 'a failing seed: the others still kept')
qa_res = dict(plain, qa=[('ERROR', 'x'), ('WARN', 'y'), ('WARN', 'outline of floor 1: z')])
ok(R.score_parts(SWAMP, qa_res, look=False)['qa'] == 33, 'qa part: 30 per error, 3 per warning, outline lines left out')

# ------------------------------------------------------------------------------------------------ the CLI
out = tempfile.mkdtemp(prefix='o738_')
try:
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = area_planner.main(['compile', os.path.join(EX, 'swamp_hunt.json'), out, '--pair24', 'off', '--candidates', '3'])
    text = buf.getvalue()
    cand = os.path.join(out, SWAMP['id'] + '-candidates.txt')
    ok(rc == 0 and os.path.exists(cand), 'CLI: compile --candidates writes %s' % os.path.basename(cand))
    ok('kept seed' in text and open(cand).read().count('\n') == 6, 'CLI: the table printed and written')
    man = json.load(open(os.path.join(out, SWAMP['id'] + '.json')))
    ok(('kept seed %d' % man['seed']) in text, 'CLI: the written area is the kept seed')
    buf = io.StringIO()
    with redirect_stdout(buf):
        area_planner.main(['compile', os.path.join(EX, 'swamp_hunt.json'), out + '/one', '--pair24', 'off'])
    ok(not os.path.exists(os.path.join(out, 'one', SWAMP['id'] + '-candidates.txt')), 'CLI: no table without --candidates')
finally:
    shutil.rmtree(out)

# ------------------------------------------------------------------------------------------------ reach repair
ok(not [i for i in C.validate(VILLAGE, cat) if i.level == 'ERROR'], 'village example with repair_reach validates')
vres = PC.compile_plan(VILLAGE, pair24=False, cat=cat)
ok(vres['manifest']['stats'].get('reach', {}).get('share') == 0.0, 'village example: the reach numbers in the manifest, nothing out of reach')
ok('reach' not in plain['manifest']['stats'], 'repair off: no reach key in the manifest (held bytes)')
ok(plain['reach']['left_share'] == 0 and plain['reach']['share'] == 0, 'swamp example: no pocket')
bad = copy.deepcopy(SWAMP)
bad['repair_reach'] = 'yes'
ok(any(i.level == 'ERROR' for i in C.validate(bad, cat)), 'repair_reach must be a boolean')

# a path piece the zones never touch: find a free strip on floor 1 (no walkable tile within 5) and add it to the layout
w0, h0 = SWAMP['size']
ox, oy, oz = plain['origin']
walk = {(x - ox + 1, y - oy + 1) for x, y, z in plain['walk'] if z == oz}
spot = None
for y in range(8, h0 - 8):
    for x in range(8, w0 - 18):
        if all((xx, yy) not in walk for xx in range(x - 6, x + 17) for yy in range(y - 6, y + 7)):
            spot = (x, y)
            break
    if spot:
        break
ok(spot is not None, 'a free strip for the cut-off path piece')
real_layout = C.layout


def with_stub(plan, cat_):
    lay = real_layout(plan, cat_)
    lay['paths'][1] = list(lay['paths'][1]) + [dict(width=3, style='road', points=[spot, (spot[0] + 10, spot[1])],
                                                     kind='stub', zones=('', ''))]
    return lay


C.layout = with_stub
try:
    off = PC.compile_plan(SWAMP, pair24=False, cat=cat)
    on_plan = dict(SWAMP, repair_reach=True)
    on = PC.compile_plan(on_plan, pair24=False, cat=cat)
    on2 = PC.compile_plan(on_plan, pair24=False, cat=cat)
finally:
    C.layout = real_layout
ro, rn = off['reach'], on['reach']
print('  swamp_hunt with a cut-off path piece: off %s; on %s' % (ro, rn))
ok(ro['pockets'] >= 1 and ro['left_share'] > 0, 'repair off: the pocket is found and closed')
ok('reach' not in off['manifest']['stats'], 'repair off: no reach key')
ok(rn['pockets'] == ro['pockets'] and rn['repaired'] == rn['pockets'], 'repair on: every pocket joined')
ok(rn['left_share'] == 0 and rn['share'] == 0, 'repair on: nothing out of reach')
ok(rn['carved'] > 0, 'repair on: cells carved')
ok(on['manifest']['stats']['reach'] == rn, 'repair on: the reach numbers in the manifest')
ok(len(on['walk']) > len(off['walk']), 'repair on: more walkable tiles (%d against %d)' % (len(on['walk']), len(off['walk'])))
ok(len(PC.qa_errors(on)) <= len(PC.qa_errors(off)), 'repair on: no new QA error %s' % PC.qa_errors(on)[:2])
ok(digest(on) == digest(on2), 'repair on: deterministic')
ok(R.score_parts(SWAMP, off, look=False)['reach'] > R.score_parts(on_plan, on, look=False)['reach'] == 0,
   'the reach part scores the cut-off pocket')

print('area plan rank: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
