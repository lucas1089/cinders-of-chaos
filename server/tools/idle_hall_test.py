#!/usr/bin/env python3
"""The Idle Hall's plan (server/README.md "Idle Hall"): server/tools/areaplan/rooms/idle_hall.json validates and compiles
with the area planner without a QA error; it has no monster, every zone is a protection zone, the exit portal leads
back (action id 47951: areagen.lua sends the character to its town temple); idlehall_config.lua's `hall.at` is the plan's
origin and `hall.arrival` its arrival; every dummy, bench and the sign slot is free floor (no decoration, not the
arrival or the exit) in its room (dummies: training, benches: rest, sign: hall) with room to stand beside it; with every
fixture placed no walkable tile is cut off from the arrival; the origin keeps 10+ tiles from every other plan and
generated area; install_content_areas.py places the rooms folder (FIXED_DIRS).

    python3 -I server/tools/idle_hall_test.py
Needs LuaJIT (LUAJIT=... to point elsewhere), like the area planner.
"""
import glob, json, os, re, subprocess, sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import area_plan_core as C
import area_plan_compile as AC
import install_content_areas as I

PLAN = os.path.join(HERE, 'areaplan', 'rooms', 'idle_hall.json')
LUAJIT = os.environ.get('LUAJIT', 'luajit')
ROOM_OF = {'dummies': 'training', 'benches': 'rest', 'sign': 'hall'}

failures = []


def check(cond, what):
    if not cond:
        failures.append(what)
        print('FAIL ' + what)


def config():
    code = ('local c = dofile("data/scripts/chaos/idlehall_config.lua") '
            'print("at", c.hall.at.x, c.hall.at.y, c.hall.at.z) '
            'print("arrival", c.hall.arrival[1], c.hall.arrival[2], c.hall.arrival[3] or 0) '
            'print("exit", c.hall.exit[1], c.hall.exit[2], c.hall.exit[3] or 0) '
            'print("plan", c.hall.plan) '
            'for _, k in ipairs({"dummies", "benches"}) do for i, o in ipairs(c.slots[k]) do print(k, o[1], o[2]) end end '
            'print("sign", c.slots.sign[1], c.slots.sign[2])')
    out = subprocess.run([LUAJIT, '-e', code], cwd=SERVER, capture_output=True, text=True, check=True).stdout
    cfg = {'slots': []}
    for row in (l.split() for l in out.splitlines() if l.strip()):
        if row[0] in ('at', 'arrival', 'exit'):
            cfg[row[0]] = tuple(int(v) for v in row[1:4])
        elif row[0] == 'plan':
            cfg['plan'] = row[1]
        else:
            cfg['slots'].append((row[0], int(row[1]), int(row[2])))
    return cfg


def neighbours(k):
    x, y, z = k
    return tuple((x + dx, y + dy, z) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)


def reachable(walk, start, blocked):
    seen, q = {start}, deque([start])
    while q:
        k = q.popleft()
        for n in neighbours(k):
            if n in walk and n not in blocked and n not in seen:
                seen.add(n)
                q.append(n)
    return seen


def other_areas():
    """(id, x0, y0, x1, y1) of every other plan and generated area of the 14336-15359 block"""
    out = []
    for path in glob.glob(os.path.join(HERE, 'areaplan', '*', '*.json')):
        p = json.load(open(path, encoding='utf-8'))
        o = p.get('origin')
        if o and p.get('id') != 'idle_hall':
            out.append((p['id'], o['x'], o['y'], o['x'] + p['size'][0] - 1, o['y'] + p['size'][1] - 1))
    src = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'areagen_config.lua'), encoding='utf-8').read()
    for m in re.finditer(r'origin = \{x = (\d+), y = (\d+), z = \d+\}, size = \{(\d+), (\d+)\}', src):
        x, y, w, h = (int(v) for v in m.groups())
        out.append(('areagen %d,%d' % (x, y), x, y, x + w - 1, y + h - 1))
    return out


def main():
    plan = json.load(open(PLAN, encoding='utf-8'))
    cat = C.catalogue(C.pair24_switch(), False)
    errs = C.errors(C.validate(plan, cat))
    check(not errs, 'idle_hall.json validates: %s' % '; '.join(str(e) for e in errs))
    if errs:
        return 1
    check(plan['id'] == 'idle_hall', 'the file is named by the id')
    r = AC.compile_plan(plan, cat=cat)
    check(not AC.qa_errors(r), 'compiles without a QA error: %s' % AC.qa_errors(r))
    check(not plan.get('spawns') and not plan.get('boss') and not plan.get('chests'), 'no monster, boss or chest')
    check(all(z['pz'] for z in r['manifest']['zones'].values()), 'every zone is a protection zone')
    check(r['exit'] and r['exit'].get('aid') == 47951 and not r['exit'].get('to'), 'the exit portal leads to the temple')

    cfg = config()
    ox, oy, oz = r['origin']
    check(cfg['plan'] == plan['id'], 'hall.plan is %s' % plan['id'])
    check(cfg['at'] == (ox, oy, oz), 'hall.at %s is the plan\'s origin %s' % (cfg['at'], (ox, oy, oz)))
    ax, ay, az = r['arrival']
    check(cfg['arrival'] == (ax - ox, ay - oy, az - oz), 'hall.arrival %s (the plan gives %s)'
          % (cfg['arrival'], (ax - ox, ay - oy, az - oz)))
    ex, ey, ez = r['exit']['at']
    check(cfg.get('exit') == (ex - ox, ey - oy, ez - oz), 'hall.exit %s (the plan gives %s): idlehall.lua re-tags that portal'
          % (cfg.get('exit'), (ex - ox, ey - oy, ez - oz)))

    walk, tiles = r['walk'], r['tiles']
    start, exit_at = tuple(r['arrival']), tuple(r['exit']['at'])
    check(len(reachable(walk, start, set())) == len(walk), 'every walkable tile is reached from the arrival')
    blocked, seen = set(), set()
    for kind, dx, dy in cfg['slots']:
        k = (ox + dx, oy + dy, oz)
        what = '%s slot (%d, %d)' % (kind, dx, dy)
        check(k not in seen, what + ' used once')
        seen.add(k)
        zr = r['zrect'][ROOM_OF[kind]]
        check(zr[0] <= k[0] <= zr[2] and zr[1] <= k[1] <= zr[3], '%s in the %s room' % (what, ROOM_OF[kind]))
        check(k in walk, what + ' is walkable floor')
        check(k in tiles and not tiles[k]['items'], what + ' holds no decoration')
        check(k not in (start, exit_at), what + ' is not the arrival or the exit')
        free = [n for n in neighbours(k) if n in walk and not tiles[n]['items']]
        check(len(free) >= 3, what + ' has room to stand beside it')
        blocked.add(k)  # dummies and the sign block; benches are counted as blocking too
    left = reachable(walk, start, blocked)
    check(len(left) == len(walk) - len(blocked), 'with every fixture placed no tile is cut off (%d of %d reached)'
          % (len(left), len(walk) - len(blocked)))

    w, h = plan['size']
    for name, x0, y0, x1, y1 in other_areas():
        apart = ox > x1 + 10 or ox + w - 1 < x0 - 10 or oy > y1 + 10 or oy + h - 1 < y0 - 10
        check(apart, 'the hall keeps 10 tiles from %s' % name)
    check(14336 <= ox and ox + w - 1 <= 15359 and 14336 <= oy and oy + h - 1 <= 15359, 'inside the content block')

    rooms = os.path.join(HERE, 'areaplan', 'rooms')
    check(any(os.path.abspath(d) == rooms for d in I.FIXED_DIRS), 'install_content_areas.py places the rooms folder')
    fixed = I.fixed_plans((rooms,), {}, log=lambda s: None)
    check('idle_hall' in fixed, 'the installer reads the Idle Hall as a fixed area')

    print('idle_hall_test: %d failure(s)' % len(failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
