"""Unit test of audit_hunt_transitions.py on synthetic data (run: python3 -I server/tools/audit_hunt_transitions_test.py)."""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit_hunt_transitions as A

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


# ---- verdict: ratios, steps, the soft rules, no destination
src = dict(level=20, exp=100.0, density=3.0)
check(A.verdict(src, None) == 'ok', 'no monsters at the destination')
check(A.verdict(src, dict(level=25, exp=100.0, density=3.0)) == 'ok', 'a similar level')
check(A.verdict(src, dict(level=45, exp=100.0, density=3.0)) == 'danger', '2 x and 25 more is danger')
check(A.verdict(src, dict(level=40, exp=100.0, density=3.0)) == 'ok', '2 x but 20 more is not enough')
check(A.verdict(src, dict(level=60, exp=100.0, density=3.0)) == 'extreme', '3 x and 40 more is extreme')
check(A.verdict(src, dict(level=40, exp=100.0, density=3.0)) == 'ok', '2 x but 20 more with equal density is ok')
check(A.verdict(src, dict(level=40, exp=350.0, density=3.0)) == 'danger', '2 x less 15... 1.5 x with 3.5 x experience is danger')
check(A.verdict(src, dict(level=40, exp=100.0, density=10.0)) == 'danger', '2 x less 5 is soft: 3.3 x density is danger')
check(A.verdict(src, dict(level=25, exp=900.0, density=30.0)) == 'ok', 'experience and density alone never count')
check(A.verdict(dict(level=0, exp=0.0, density=0.0), dict(level=60, exp=1.0, density=1.0)) == 'extreme', 'level 0 counts as 8')
check(A.verdict(dict(level=2, exp=0.0, density=0.0), dict(level=20, exp=1.0, density=1.0)) == 'ok', 'a rat level source counts as 8')
check(A.verdict(src, dict(level=45, exp=1.0, density=1.0), dict(A.THRESHOLDS, level_min_step=30)) == 'ok', 'thresholds are an argument')

# ---- level label and clusters
check(A.level_label(87) == 85 and A.level_label(3) == 5, 'level label rounds down to 5, at least 5')
g = A.cluster([(100, 100, 8), (105, 100, 8), (200, 200, 8), (100, 100, 9), (110, 110, 8)])
check(g[(100, 100, 8)] == g[(105, 100, 8)] == g[(110, 110, 8)], 'close landings are one group (a chain)')
check(g[(200, 200, 8)] != g[(100, 100, 8)] and g[(100, 100, 9)] != g[(100, 100, 8)], 'far or another floor is another group')
check(sorted(set(g.values())) == [1, 2, 3], 'group numbers from 1')

# ---- spawns: bands, near, density
try:
    import numpy as np  # noqa: F401
except ImportError:
    print('numpy missing: the spawn tests are skipped')
    sys.exit(1 if fails else 0)

levels = {'rat': 5, 'wolf': 10, 'demon': 120, 'hydra': 140, 'ghost': 0}
exps = {'rat': 10, 'wolf': 30, 'demon': 2000, 'hydra': 3000, 'ghost': 0}
pts = []
for i in range(10):                       # a rat and wolf field on floor 7 round (100, 100)
    pts.append((95 + i, 100, 7, 'rat' if i % 2 else 'wolf'))
for i in range(12):                       # a demon cave on floor 8 under it, twice as dense
    pts.append((98 + i % 4, 98 + i // 4, 8, 'demon' if i % 3 else 'hydra'))
pts.append((100, 101, 7, 'ghost'))        # unknown level: ignored for the band
pts.append((500, 500, 7, 'rat'))          # far away
sp = A.Spawns(pts, levels, exps)
check(len(sp.x) == len(pts), 'all spawns read')
near = sp.near((100, 100, 7), passes=A.LOCAL_PASSES, min_count=A.MIN_LOCAL)
check(len(near) == 10, 'near: the 10 known monsters of the floor within 25, not the ghost, not the far one: %d' % len(near))
band = sp.band(near)
check(band[0] <= 5 and band[1] >= 10 and 5 <= band[2] <= 10, 'band of the field %r' % (band,))
check(abs(band[4] - 20.0) < 1e-6, 'average experience')
check(sp.band(np.zeros(0, np.int64)) is None, 'no monsters: no band')
low = A.describe(sp, lambda x0, y0, x1, y1, z: 625, (100, 100, 7))
high = A.describe(sp, lambda x0, y0, x1, y1, z: 625, (100, 99, 8))
check(low and high and low['level'] < 15 and high['level'] >= 100, 'describe: field %r cave %r' % (low and low['level'], high and high['level']))
check(abs(high['density'] - 100.0 * 12 / 625) < 1e-6, 'density per 100 walkable tiles')
check(A.describe(sp, lambda *a: 625, (400, 400, 7)) is None, 'describe: nothing near is None')
check(A.describe(sp, lambda *a: 0, (100, 99, 8))['density'] == 0.0, 'no walkable tiles: density 0')

# ---- audit on a fake map: four transitions
class Ground:
    def __init__(self, *a, **k):
        pass

    def count(self, x0, y0, x1, y1, z):
        return 625


trans = [
    dict(pos=(100, 100, 7), kind='hole/down', item=1, land=(100, 99, 8)),      # field -> cave: danger or extreme
    dict(pos=(102, 100, 7), kind='teleport', item=2, land=(100, 101, 8)),      # the same cave: same group
    dict(pos=(300, 300, 7), kind='hole/down', item=3, land=(100, 99, 8)),      # no monsters round the entry: not audited
    dict(pos=(100, 99, 8), kind='ladder/up', item=4, land=(100, 100, 7)),      # cave -> field: ok
    dict(pos=(130, 100, 7), kind='hole/down', item=5, land=(100, 99, 8)),      # 30 tiles from the field: not at its edge
]
A_Ground, A_find = A.Ground, A.find_transitions
A.Ground, A.find_transitions = Ground, lambda m, k, d, x=None: trans
hunts = [dict(id='h1', name='Rat Field', level=8, lo=5, hi=10, dest=(100, 100, 7))]
rows = A.audit(None, None, None, hunts, sp)
A.Ground, A.find_transitions = A_Ground, A_find
check(len(rows) == 3, 'three transitions are at a monster area: %d' % len(rows))
by = {r['item']: r for r in rows}
check(by[1]['verdict'] == 'extreme' and by[2]['verdict'] == 'extreme', 'hole and teleport into the cave are extreme: %r' % [r['verdict'] for r in rows])
check(by[4]['verdict'] == 'ok', 'the way back is ok')
check(by[1]['hunt']['name'] == 'Rat Field' and by[1]['src']['level'] == 8, 'the hall hunt names the area and gives its level')
check(by[4]['hunt']['name'].startswith('area '), 'an entry outside every hall hunt is named by its position')
check(by[1]['place'] is None, 'no hall hunt at the landing')

# ---- outputs
text, lv = A.render_places(rows)
check(text.count('{id =') == 2 and 'kind = "floor"' in text and 'kind = "teleport"' in text, 'places for the two dangerous entries')
check(len(set(lv)) == 1 and list(lv.values())[0] >= 70, 'one group, level label %r' % (lv,))
check('signs' not in text, 'no sign positions')
md = A.render_md(rows, hunts)
check('# Hunt transitions (O323)' in md and md.count('| extreme |') == 2 and '| Rat Field (8) |' in md, 'markdown table')
check('—' not in md and '–' not in md, 'no dashes in the prose')
d = tempfile.mkdtemp()
cfg = os.path.join(d, 'c.lua')
open(cfg, 'w').write('local C = {}\nC.enabled = true\n-- BEGIN places (x)\nC.places = {\n}\n-- END places\nreturn C\n')
check(A.write_config(cfg, rows) is True, 'config written')
body = open(cfg).read()
check('C.enabled = true' in body and 'verdict = "extreme"' in body and body.rstrip().endswith('return C'), 'config keeps its numbers')
check(A.write_config(cfg, rows) is False, 'second write changes nothing')
open(cfg, 'w').write('return {}\n')
try:
    A.write_config(cfg, rows)
    check(False, 'no markers must be refused')
except A.AuditError:
    pass
csvp = os.path.join(d, 'a.csv')
A.write_csv(csvp, rows)
check(len(open(csvp).read().splitlines()) == 4, 'csv: header and 3 rows')

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('audit_hunt_transitions_test: ok')
