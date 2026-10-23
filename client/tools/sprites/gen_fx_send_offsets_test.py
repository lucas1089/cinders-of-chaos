#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_fx_send_offsets_test.py: the send offsets of the in-place pair 36 effects
(gen_fx_send_offsets.py) on synthetic pivots, and the committed pivots / table over every in-place effect: each one
has its pivot, none is pulled past its art, and the offset leaves the pivot within half a tile of its place on both axes
(owner 2026-10-23: the teleport 11 and the holy 201 / 262 sat a tile off after the first table)."""
import csv
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_fx_send_offsets as G  # noqa: E402

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


# the rounding: the whole tiles nearest to bringing the pivot back
ok(G.axis(0) == 0, 'no pull, no offset')
ok(G.axis(-7) == 0, 'the teleport ring (7 px) stays')
ok(G.axis(-15) == 0, '15 px stays')
ok(G.axis(-16) == 1, 'half a tile rounds to the tile')
ok(G.axis(-32) == 1 and G.axis(-47) == 1, 'a tile')
ok(G.axis(-48) == 2 and G.axis(-63) == 2, 'two tiles')
for pull in range(-160, 1):
    ok(abs(G.residual(pull, G.axis(pull))) <= G.MAX_RESIDUAL, f'residual of {pull}')


def tree(replace_rows, pivot_rows):
    d = tempfile.mkdtemp(prefix='fxoff_test_')
    with open(os.path.join(d, 'pack36_replace.csv'), 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note'])
        for r in replace_rows:
            w.writerow(r)
    with open(os.path.join(d, 'pack36_replace_pivots.csv'), 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['replace', 'name', 'pull_x', 'pull_y'])
        for r in pivot_rows:
            w.writerow(r)
    return d


def rep(i, w, h, dx=0, dy=0, kind='effect'):
    return [i, kind, f'rep_e{i}', f'pack36_fx/rep_e{i}.png', w, h, 10, 83, dx, dy, f'note {i}']


rows = [rep(1, 2, 2), rep(2, 3, 3), rep(3, 4, 4), rep(4, 3, 2), rep(5, 2, 2, 1, 1), rep(6, 2, 2, kind='missile')]
piv = [[1, 'rep_e1', -3, -3], [2, 'rep_e2', -34, -34], [3, 'rep_e3', -47, -63], [4, 'rep_e4', -4, -20],
       [5, 'rep_e5', -50, -50]]
d = tree(rows, piv)
got = {i: (dx, dy) for i, dx, dy, _ in G.offsets(d)}
ok(got == {2: (1, 1), 3: (1, 2), 4: (0, 1)}, f'synthetic offsets {got}')
ok(G.check_table(d) == [], f'synthetic table is fine: {G.check_table(d)}')
ok(1 not in got and 5 not in got and 6 not in got, 'small pull, own offset (ChaosVfx) and missiles are not listed')
bad = tree(rows, [[1, 'rep_e1', 5, -3]] + piv[1:])
ok(any('0 or negative' in e for e in G.check_table(bad)), 'a positive pull is refused')
bad = tree(rows, [[1, 'rep_e1', -90, -3]] + piv[1:])
ok(any('larger than the art' in e for e in G.check_table(bad)), 'a pull larger than the art is refused')
missing = tree(rows, piv[1:])
try:
    G.offsets(missing)
    ok(False, 'a missing pivot row is refused')
except SystemExit as e:
    ok('no row in pack36_replace_pivots.csv' in str(e), 'a missing pivot row says so')

# the committed data: every in-place effect has its pivot, in order, and its pivot ends within half a tile
rep_rows = [r for r in G.read(os.path.join(G.ART, 'pack36_replace.csv')) if r['kind'] == 'effect']
pv_rows = G.read(os.path.join(G.ART, 'pack36_replace_pivots.csv'))
ok([r['name'] for r in rep_rows] == [r['name'] for r in pv_rows], 'pivots list the in-place effects in order')
ok(G.check_table() == [], f'committed table: {G.check_table()}')
table = {i: (dx, dy) for i, dx, dy, _ in G.offsets()}
# the engine's own table (server/data/lib/chaos_fx_send_offsets.lua) is this one
lua = open(G.OUT, encoding='utf-8').read()
lua_rows = {int(a): (int(b), int(c)) for a, b, c in re.findall(r'^\t\[(\d+)\] = \{(-?\d+), (-?\d+)\}', lua, re.M)}
ok(lua_rows == table, 'the committed Lua table is the generated one')
ok(all(dx >= 0 and dy >= 0 and dx <= 3 and dy <= 3 for dx, dy in table.values()), 'offsets are 0..3 tiles')
# the owner's reports: the blue teleport 11 and the yellow holy 201 / 262 are sent at their own tile
for i in (3, 7, 11, 167, 201, 226, 262, 309, 416):
    ok(i not in table, f'effect {i} is sent at its own tile')
# the whole spread, for every in-place effect (not just the reported ones)
worst = 0
for r in pv_rows:
    px, py = int(r['pull_x']), int(r['pull_y'])
    d = table.get(int(r['replace']), (0, 0))
    worst = max(worst, abs(G.residual(px, d[0])), abs(G.residual(py, d[1])))
ok(worst <= G.MAX_RESIDUAL, f'worst residual {worst} px')

# gen_pack36_fx.pull on synthetic art (needs numpy and Pillow, like the build; skipped without)
try:
    import numpy as np
    import gen_pack36_fx as P
except ImportError:
    P = None
if P:
    def frame(x0, y0, x1, y1):
        f = np.zeros((96, 96, 4), np.uint8)
        f[y0:y1, x0:x1, 3] = 255
        return f

    anchor, point = (48, 48), (16, 16)
    # art 3 tiles wide centred on the pivot reaches 48 px right of it: past the tile's edge by 32 px
    ok(P.pull([frame(0, 0, 96, 96)], anchor, point, 0, 0) == (-32, -32), 'a centred 3x3 is pulled a tile')
    # art reaching 7 px past the tile edge (the teleport ring): pulled 7 px, which the offset leaves alone
    ok(P.pull([frame(20, 20, 71, 71)], anchor, point, 0, 0) == (-7, -7), 'a ring 7 px past the edge')
    ok(P.pull([frame(40, 40, 56, 56)], anchor, point, 0, 0) == (0, 0), 'art inside the tile is not pulled')
    # the pivot lands at point + pull inside the sent tile, as anchored() places it
    fr = [frame(0, 0, 96, 96)]
    placed, w, h, cut = P.anchored(fr, anchor, point, 0, 0, 4, 'synthetic')
    sx, sy = P.pull(fr, anchor, point, 0, 0)
    ys, xs = np.nonzero(placed[0][:, :, 3] > 0)
    ok(int(xs.max()) == w * 32 - 1 and int(ys.max()) == h * 32 - 1, 'the pulled art ends at the sent tile corner')
    ok((w, h) == (3, 3) and (sx, sy) == (-32, -32), 'the canvas is 3x3')

if fails:
    print(f'{fails} failed')
    sys.exit(1)
print('gen_fx_send_offsets_test: OK')
