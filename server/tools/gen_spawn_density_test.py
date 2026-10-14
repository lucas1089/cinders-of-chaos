#!/usr/bin/env python3
"""Tests of tools/gen_spawn_density.py on synthetic grids and a synthetic map (no base data needed).

    python3 -I server/tools/gen_spawn_density_test.py
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools', 'map'))
try:
    import numpy as np
except ImportError:
    print('gen_spawn_density_test: numpy missing, skipped')
    sys.exit(0)
import gen_spawn_density as G  # noqa: E402

fails = checks = 0


def ok(cond, what):
    global fails, checks
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


def room(w, h, walls=True):
    """a w x h grid of CAND | WALK tiles inside a wall ring"""
    g = [[G.WALK | G.CAND] * w for _ in range(h)]
    if walls:
        for x in range(w):
            g[0][x] = g[h - 1][x] = 0
        for y in range(h):
            g[y][0] = g[y][w - 1] = 0
    return g


# dilate
m = np.zeros((7, 7), bool)
m[3, 3] = True
d = G.dilate(m, 2)
ok(d.sum() == 25 and d[1, 1] and d[5, 5] and not d[0, 3], 'dilate: a 5 x 5 square around one tile')

# pocket: a closed room is a pocket, the same room with an exit tile or a door to a big area is not
g = room(12, 12)
ok(G.pocket(g, [(5, 5)]), 'a closed room of 100 tiles is a pocket')
g[3][3] |= G.EXIT
ok(not G.pocket(g, [(5, 5)]), 'a room with stairs is not')
g = room(40, 40)
ok(not G.pocket(g, [(5, 5)]), 'a room over 400 tiles is not')
g = [[G.WALK] * 5 for _ in range(5)]
ok(not G.pocket(g, [(2, 2)]), 'leaving the grid counts as open')

# region: within REACH, connected, without town, exit, pz, house tiles
g = room(40, 30)
for y in range(1, 29):
    g[y][20] = 0                       # a wall splits the room
town = [[False] * 40 for _ in range(30)]
r = G.region_of(g, [(15, 15)], town)
ok(all(x < 20 for x, _ in r), 'region: not through a wall')
ok(all(abs(x - 15) <= G.REACH and abs(y - 15) <= G.REACH for x, y in r), 'region: within REACH')
ok(len(r) == 11 * 13, 'region: 11 x 13 tiles (x 9-19, y 9-21): %d' % len(r))
g[15][17] |= G.PZ
town[10][15] = True
r2 = G.region_of(g, [(15, 15)], town)
ok((17, 15) not in r2 and (15, 10) not in r2 and len(r2) == len(r) - 2, 'region: no PZ, no town tile')

# place: spacing, the farthest tile first, deterministic, capped by spacing
reg = set((x, y) for x in range(20) for y in range(20))
pts = G.place(reg, reg, [(0, 0)], 3)
ok(pts[0] == (0, 19) and pts[1] == (19, 0), 'place: the farthest tile first, ties by x then y: %s' % (pts,))
ok(pts == G.place(reg, reg, [(0, 0)], 3), 'place: deterministic')
many = G.place(reg, reg, [(0, 0)], 1000)
close = sum(1 for i, a in enumerate(many) for b in many[i + 1:] if max(abs(a[0] - b[0]), abs(a[1] - b[1])) < G.SPACING)
ok(close == 0 and all(max(a) >= G.SPACING for a in many), 'place: every point SPACING from the others and the entry')
ok(len(many) < 1000 and len(many) >= 20, 'place: stops when no tile is SPACING away (%d)' % len(many))
ok(G.place(reg, set(), [(0, 0)], 5) == [], 'place: no candidate, nothing')

# nearest and wanted
ok(G.nearest((5, 5), [(9, 5), (5, 8), (1, 1)]) == (5, 8), 'nearest: Chebyshev first')
ok(G.nearest((5, 5), [(7, 7), (7, 5)]) == (7, 5), 'nearest: then the straight one')
ok(G.wanted(20, 1000, 3.25, 3.4, 2.0, 400) == 14, 'wanted: 2.0 -> 3.4 per 100')
ok(G.wanted(40, 1000, 3.25, 3.4, 2.0, 400) == 0, 'wanted: 4.0 is full')
ok(G.wanted(5, 1000, 3.25, 3.4, 2.0, 400) == 10, 'wanted: at most cap x the entries')
ok(G.wanted(300, 30000, 3.25, 3.4, 2.0, 400) == 400, 'wanted: at most max-add')

# plan on a synthetic map: a 60 x 40 cave with 12 entries, a town strip of houses on the east, a closed quest room
import otbm  # noqa: E402
xs, ys, zs, hs, fl = [], [], [], [], []
for y in range(100, 140):
    for x in range(100, 200):
        if x in (100, 199) or y in (100, 139):
            continue                   # no tile: void
        xs.append(x); ys.append(y); zs.append(7); hs.append(1 if x >= 185 else 0); fl.append(0)
for y in range(300, 312):              # the quest room: 10 x 10 walkable, walls around
    for x in range(300, 312):
        if 300 < x < 311 and 300 < y < 311:
            xs.append(x); ys.append(y); zs.append(7); hs.append(0); fl.append(0)
n = len(xs)
tiles = dict(x=np.array(xs, np.uint16), y=np.array(ys, np.uint16), z=np.array(zs, np.uint8),
             flags=np.array(fl, np.uint32), house=np.array(hs, np.uint32), off=np.arange(n, dtype=np.uint32),
             cnt=np.ones(n, np.uint16))
mp = otbm.Map(tiles, np.ones(n, np.uint16), [], {})
code = np.where(tiles['house'] > 0, G.WALK | G.HOUSE, G.WALK | G.CAND).astype(np.uint8)
cave = [('Test Low', 110 + 6 * (i % 4), 110 + 6 * (i // 4), 7, 30, 60, True) for i in range(12)]
quest = [('Test Low', 302 + (i % 4) * 2, 302 + (i // 4) * 3, 7, 30, 60, True) for i in range(10)]
hunts = [(30, sorted(cave)), (30, sorted(quest))]
areas, skipped = G.plan(mp, code, hunts, [(140, 120, 7)], [(e[1], e[2], e[3]) for e in cave + quest],
                        3.25, 3.4, 2.0, 400)
ok(skipped.get('closed pocket') == 1 and len(areas) == 1, 'plan: the quest room is skipped: %s' % dict(skipped))
a = areas[0]
ok(a['before'] < 3.25 and 3.0 <= a['after'] <= 3.6, 'plan: filled to about 3.4 (%s -> %s)' % (a['before'], a['after']))
ok(all(x < 185 - G.HOUSE_MARGIN for x, _y, _i in a['add']), 'plan: nothing in the town margin')
ok(all(max(abs(x - 140), abs(y - 120)) > G.NPC_MARGIN for x, y, _i in a['add']), 'plan: nothing next to the NPC')
allp = [(e[1], e[2]) for e in cave] + [(x, y) for x, y, _i in a['add']]
close = sum(1 for i, p in enumerate(allp) for q in allp[i + 1:] if max(abs(p[0] - q[0]), abs(p[1] - q[1])) < G.SPACING)
ok(close == 0, 'plan: spacing to every entry')
ok(all(list(a['likes'][i]) in [[e[1], e[2]] for e in cave] for _x, _y, i in a['add']), 'plan: copies entries of the hunt')
again, _s = G.plan(mp, code, hunts, [(140, 120, 7)], [(e[1], e[2], e[3]) for e in cave + quest], 3.25, 3.4, 2.0, 400)
ok(G.render(again, _s, dict(min=3.25, target=3.4, cap=2.0, max_add=400)) ==
   G.render(areas, skipped, dict(min=3.25, target=3.4, cap=2.0, max_add=400)), 'plan: the same JSON twice')

if fails:
    print('gen_spawn_density: %d of %d checks failed' % (fails, checks))
    sys.exit(1)
print('gen_spawn_density: all %d checks passed' % checks)
