#!/usr/bin/env python3
"""Tests of area_import.py and of the imported hunts of server/tools/areaplan/plans/ (docs/MAP_GUIDE.md "Imported hunts").

Run: python3 -I server/tools/area_import_test.py. Needs numpy for the synthetic spawn checks.
Checks, on the committed plans and chunks (no source map needed):
  - every imported plan validates, compiles twice to the same bytes, the OTBM is the planner's own format
  - the arrival is a free ground tile, the exit forcefield (action id 47951) is within 3 tiles, no other action id,
    teleport or unique id, only ids of the base items range (up to 29926: the source maps' own custom ids never ship)
  - the spawn file holds exactly the monsters of the plan, on walkable-looking ground tiles (a tile of the chunk
    with a ground), outside 10 tiles of the arrival, every monster of a known monster file, its level band inside 1-2500
  - the boxes keep 10 tiles from every other plan, on every floor, and the level bands look like the monsters
    (the monster files' own names)
  - spawn_points / share_out / central_tile on a synthetic area
"""
import glob, json, os, re, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import area_import as A
import area_plan_compile as PC

FAILED = []


def check(cond, msg):
    if not cond:
        FAILED.append(msg)
        print('FAIL: ' + msg)


def plans():
    out = {}
    for p in sorted(glob.glob(os.path.join(HERE, 'areaplan', 'plans', '*.json'))):
        d = json.load(open(p, encoding='utf-8'))
        if A.is_import(d):
            out[d['id']] = (p, d)
    return out


def monster_names():
    names = set()
    for p in glob.glob(os.path.join(SERVER, 'data', 'monster', '**', '*.xml'), recursive=True):
        m = re.search(r'<monster[^>]*\bname="([^"]+)"', open(p, encoding='latin-1').read(800))
        if m:
            names.add(m.group(1).lower())
    pool = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'bounty_pool.lua'), encoding='utf-8').read()
    names |= {m.lower() for m in re.findall(r'\{name = "([^"]+)", level = ', pool)}
    return names


def boxes():
    out = []
    for d in ('plans', 'chronicle', 'rooms', 'annexes', 'events'):
        for p in glob.glob(os.path.join(HERE, 'areaplan', d, '*.json')):
            plan = json.load(open(p, encoding='utf-8'))
            o = plan.get('origin')
            if not o or 'size' not in plan:
                continue
            out.append((plan['id'], o['x'], o['y'], o['x'] + plan['size'][0] - 1, o['y'] + plan['size'][1] - 1))
    return out


def main():
    imp = plans()
    check(len(imp) >= 4, 'at least four imported plans (%d)' % len(imp))
    known = monster_names()
    others = boxes()
    for pid, (path, plan) in imp.items():
        check(A.validate(plan, path) == [], '%s: validates' % pid)
        a, b = tempfile.mkdtemp(), tempfile.mkdtemp()
        A.compile_plan(path, a)
        A.compile_plan(path, b)
        for name in sorted(os.listdir(a)):
            check(open(os.path.join(a, name), 'rb').read() == open(os.path.join(b, name), 'rb').read(), '%s: %s compiles to the same bytes' % (pid, name))
        _h, tiles, problems = PC.read_otbm_full(open(os.path.join(a, pid + '.otbm'), 'rb').read())
        check(not problems, '%s: planner OTBM (%s)' % (pid, problems[:1]))
        ar = tuple(plan['arrival'])
        check(ar in tiles and tiles[ar]['items'] == [], '%s: the arrival is a free tile' % pid)
        exits = [(p, i, at) for p, t in tiles.items() for i, at in t['items'] if at.get('aid')]
        check(len(exits) == 1 and exits[0][2]['aid'] == A.EXIT_AID and exits[0][1] == A.PORTAL_ID, '%s: one exit forcefield, no other action id' % pid)
        if exits:
            check(max(abs(exits[0][0][0] - ar[0]), abs(exits[0][0][1] - ar[1])) <= 3 and list(exits[0][0]) == plan['exit']['at'],
                  '%s: the exit is beside the arrival and named in the plan' % pid)
        ids = [t['ground'] for t in tiles.values()] + [i for t in tiles.values() for i, _a in t['items']]
        check(max(ids) <= 29926, '%s: only ids of the base items range (max %d)' % (pid, max(ids)))
        check(all(not a.get('tele') and not a.get('uid') for t in tiles.values() for _i, a in t['items']), '%s: no teleport, no unique id' % pid)
        check(len(tiles) > 5000, '%s: %d tiles' % (pid, len(tiles)))
        xml = open(os.path.join(a, pid + '-spawn.xml'), encoding='utf-8').read()
        mons = re.findall(r'<monster name="([^"]+)" x="(-?\d+)" y="(-?\d+)" z="(\d+)" spawntime="(\d+)"', xml)
        check(len(mons) == sum(s['count'] for s in plan['spawns']), '%s: the spawn file holds every monster of the plan' % pid)
        for s in plan['spawns']:
            check(s['monster'].lower() in known, '%s: %s is a monster of the server' % (pid, s['monster']))
            for p in s['points']:
                at = (p[0], p[1], plan['origin']['z'])
                check(at in tiles and max(abs(p[0] - ar[0]), abs(p[1] - ar[1])) > A.SAFE, '%s: spawn point %s on a tile, outside the camp' % (pid, at))
                for dx, dy in p[2]:
                    check((p[0] + dx, p[1] + dy, at[2]) in tiles, '%s: pack monster on a tile' % pid)
        check(plan['stats']['monsters'] / float(plan['stats']['walkable']) * 100 < 8, '%s: under 8 monsters per 100 walkable tiles' % pid)
        o, sz = plan['origin'], plan['size']
        xs = [p[0] for p in tiles]
        ys = [p[1] for p in tiles]
        check(min(xs) == o['x'] and min(ys) == o['y'] and max(xs) - min(xs) + 1 == sz[0] and max(ys) - min(ys) + 1 == sz[1],
              '%s: origin and size are the box of the tiles' % pid)
        for oid, x0, y0, x1, y1 in others:
            if oid == pid:
                continue
            gap = (o['x'] - 10 > x1 or o['x'] + sz[0] - 1 + 10 < x0 or o['y'] - 10 > y1 or o['y'] + sz[1] - 1 + 10 < y0)
            check(gap, '%s: 10 tiles from %s' % (pid, oid))
    # synthetic: a 40 x 40 walkable square
    sq = {(x, y, 7) for x in range(40) for y in range(40)}
    c = A.central_tile(sq)
    check(abs(c[0] - 20) <= 1 and abs(c[1] - 20) <= 1, 'central_tile: the middle of a square (%s)' % (c,))
    pts = A.spawn_points(sq, c, 4.5)
    check(len(pts) == int(round(1600 * 4.5 / 100.0 / 3)), 'spawn_points: the density asked (%d points)' % len(pts))
    check(all(max(abs(p[0] - c[0]), abs(p[1] - c[1])) > A.SAFE for p in pts), 'spawn_points: outside the camp')
    check(all(max(abs(p[0] - q[0]), abs(p[1] - q[1])) >= A.SPAWN_GAP for i, p in enumerate(pts) for q in pts[:i]), 'spawn_points: the gap between points')
    check(A.spawn_points(sq, c, 4.5) == pts, 'spawn_points: deterministic')
    parts = A.share_out(pts, [{'monster': 'a', 'weight': 3}, {'monster': 'b', 'weight': 1}])
    check(sum(len(v) for v in parts.values()) == len(pts) and all(parts[i] for i in parts), 'share_out: every point goes to a monster, each monster has a region')
    print('area_import_test: %s' % ('ok' if not FAILED else '%d failed' % len(FAILED)))
    return 1 if FAILED else 0


if __name__ == '__main__':
    sys.exit(main())
