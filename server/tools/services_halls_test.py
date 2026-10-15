#!/usr/bin/env python3
"""The Halls of Services (server/README.md "Halls of Services"): server/tools/areaplan/rooms/services_*.json validate and
compile with the area planner without a QA error; no monster, every zone a protection zone, the exit portal of areagen
(action id 47951, npc_booths.lua re-tags it); npc_booths_config.lua's hall `at`, `size`, `arrival` and `exit` match the
compiled plans; every booth NPC tile, counter, partition, coal basin and system portal is free floor (no decoration,
not the arrival or the exit) in its room; with all of them placed no other floor tile is cut off from the arrival;
each booth's front tile (the row in front of its counter) is reached, and from it its own NPC is the nearest; the
Descent and raid portal positions (descent_config.lua, raid_config.lua) are the halls' portal tiles; every NPC named in
a booth has an XML that never walks (walkinterval 0); the halls keep 10+ tiles from every other plan and generated area
and lie in the content block; install_content_areas.py places the rooms folder.

    python3 -I server/tools/services_halls_test.py
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

ROOMS = os.path.join(HERE, 'areaplan', 'rooms')
LUAJIT = os.environ.get('LUAJIT', 'luajit')

failures = []


def check(cond, what):
    if not cond:
        failures.append(what)
        print('FAIL ' + what)


DUMP = r'''
local K = dofile("data/scripts/chaos/npc_booths_core.lua")
local c = K.cfg()
print("enabled", c.enabled and 1 or 0)
for _, h in ipairs(c.halls) do
  print("hall", h.plan, h.town, h.at.x, h.at.y, h.at.z, h.size[1], h.size[2], h.arrival[1], h.arrival[2], h.arrival[3] or 0,
    h.exit[1], h.exit[2], h.exit[3] or 0)
  for _, f in ipairs(K.fixtures(c, h)) do print("fix", h.plan, f.x, f.y, f.z, f.id, f.kind) end
  for _, row in ipairs(c.rows) do
    for _, b in ipairs(row.booths) do
      local n = K.npcName(b, h.town)
      if n then
        local p = K.offset(h, b.x, row.npcRow)
        local front = K.offset(h, b.x, row.counterRow + (row.counterRow - row.npcRow))
        print("booth", h.plan, p.x, p.y, p.z, front.x, front.y, row.room, (n:gsub(" ", "_")))
      end
    end
  end
  for key in pairs(c.portals) do local p = K.portal(c, h, key) print("portal", h.plan, key, p.x, p.y, p.z, h.town) end
end
for _, f in ipairs({"descent", "raid"}) do
  local d = dofile("data/scripts/chaos/" .. f .. "_config.lua")
  for _, p in ipairs(d.portal.positions or {}) do print("pos", f, p.town, p.x, p.y, p.z) end
end
'''


def config():
    out = subprocess.run([LUAJIT, '-e', DUMP], cwd=SERVER, capture_output=True, text=True, check=True).stdout
    cfg = {'halls': {}, 'fix': [], 'booth': [], 'portal': [], 'pos': []}
    for row in (l.split() for l in out.splitlines() if l.strip()):
        if row[0] == 'enabled':
            cfg['enabled'] = row[1] == '1'
        elif row[0] == 'hall':
            v = [int(x) for x in row[2:]]
            cfg['halls'][row[1]] = dict(town=v[0], at=tuple(v[1:4]), size=tuple(v[4:6]), arrival=tuple(v[6:9]),
                                        exit=tuple(v[9:12]))
        elif row[0] == 'fix':
            cfg['fix'].append((row[1], (int(row[2]), int(row[3]), int(row[4])), int(row[5]), row[6]))
        elif row[0] == 'booth':
            cfg['booth'].append((row[1], (int(row[2]), int(row[3]), int(row[4])), (int(row[5]), int(row[6]), int(row[4])),
                                 row[7], row[8].replace('_', ' ')))
        elif row[0] == 'portal':
            cfg['portal'].append((row[1], row[2], (int(row[3]), int(row[4]), int(row[5])), int(row[6])))
        elif row[0] == 'pos':
            cfg['pos'].append((row[1], int(row[2]), (int(row[3]), int(row[4]), int(row[5]))))
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


def cheb(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def other_areas(ids):
    out = []
    for path in glob.glob(os.path.join(HERE, 'areaplan', '*', '*.json')):
        p = json.load(open(path, encoding='utf-8'))
        o = p.get('origin')
        if o and p.get('id') not in ids:
            out.append((p['id'], o['x'], o['y'], o['x'] + p['size'][0] - 1, o['y'] + p['size'][1] - 1))
    src = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'areagen_config.lua'), encoding='utf-8').read()
    for m in re.finditer(r'origin = \{x = (\d+), y = (\d+), z = \d+\}, size = \{(\d+), (\d+)\}', src):
        x, y, w, h = (int(v) for v in m.groups())
        out.append(('areagen %d,%d' % (x, y), x, y, x + w - 1, y + h - 1))
    return out


def npc_walks(name):
    path = os.path.join(SERVER, 'data', 'npc', name + '.xml')
    if not os.path.isfile(path):
        return None
    m = re.search(r'<npc\b[^>]*\bwalkinterval="(\d+)"', open(path, encoding='utf-8').read())
    return int(m.group(1)) if m else None


def main():
    cfg = config()
    check(cfg['enabled'], 'the halls are on')
    cat = C.catalogue(C.pair24_switch(), False)
    check(set(cfg['halls']) == {'services_cinderhold', 'services_mirewake'}, 'one hall each for Cinderhold and Mirewake')
    check({h['town'] for h in cfg['halls'].values()} == {1, 2}, 'the halls belong to towns 2 (main city) and 1')
    for pid, hall in sorted(cfg['halls'].items()):
        plan = json.load(open(os.path.join(ROOMS, pid + '.json'), encoding='utf-8'))
        errs = C.errors(C.validate(plan, cat))
        check(not errs, '%s validates: %s' % (pid, '; '.join(str(e) for e in errs)))
        if errs:
            continue
        check(plan['id'] == pid and plan['biome'] == 'townhall', '%s: named by its id, biome townhall' % pid)
        r = AC.compile_plan(plan, cat=cat)
        check(not AC.qa_errors(r), '%s compiles without a QA error: %s' % (pid, AC.qa_errors(r)))
        check(not plan.get('spawns') and not plan.get('boss') and not plan.get('chests'), pid + ': no monster or chest')
        check(all(z['pz'] for z in r['manifest']['zones'].values()), pid + ': every zone is a protection zone')
        check(r['exit'] and r['exit'].get('aid') == 47951 and not r['exit'].get('to'), pid + ': the exit portal')
        ox, oy, oz = r['origin']
        check(hall['at'] == (ox, oy, oz), '%s: at %s is the origin %s' % (pid, hall['at'], (ox, oy, oz)))
        check(hall['size'] == tuple(plan['size']), '%s: size %s' % (pid, hall['size']))
        ax, ay, az = r['arrival']
        check(hall['arrival'] == (ax - ox, ay - oy, az - oz), '%s: arrival %s' % (pid, hall['arrival']))
        ex, ey, ez = r['exit']['at']
        check(hall['exit'] == (ex - ox, ey - oy, ez - oz), '%s: exit %s' % (pid, hall['exit']))

        walk, tiles, zr = r['walk'], r['tiles'], r['zrect']
        start, exit_at = tuple(r['arrival']), tuple(r['exit']['at'])
        check(len(reachable(walk, start, set())) == len(walk), pid + ': every floor tile is reached from the arrival')

        def free_floor(k, room, what):
            check(k in walk, '%s: %s %s is walkable floor' % (pid, what, k))
            check(k in tiles and not tiles[k]['items'], '%s: %s %s holds no decoration' % (pid, what, k))
            check(k not in (start, exit_at), '%s: %s %s is not the arrival or the exit' % (pid, what, k))
            if room:
                z = zr[room]
                check(z[0] <= k[0] <= z[2] and z[1] <= k[1] <= z[3], '%s: %s %s in the %s room' % (pid, what, k, room))

        blocked, used = set(), set()
        fixes = [f for f in cfg['fix'] if f[0] == pid]
        booths = [b for b in cfg['booth'] if b[0] == pid]
        portals = [p for p in cfg['portal'] if p[0] == pid]
        check(len(booths) >= 9, '%s: the booths are set (%d)' % (pid, len(booths)))
        for _, k, iid, kind in fixes:
            check(k not in used, '%s: fixture tile %s used once' % (pid, k))
            used.add(k)
            free_floor(k, None, kind)
            blocked.add(k)
        for _, k, front, room, name in booths:
            check(k not in used, '%s: booth %s used once' % (pid, k))
            used.add(k)
            free_floor(k, room, 'booth of ' + name)
            blocked.add(k)
            w = npc_walks(name)
            check(w == 0, '%s: data/npc/%s.xml exists and never walks (walkinterval %s)' % (pid, name, w))
        for _, key, k, town in portals:
            check(k not in used, '%s: %s portal %s used once' % (pid, key, k))
            used.add(k)
            free_floor(k, 'portals', key + ' portal')
            blocked.add(k)
        left = reachable(walk, start, blocked)
        check(len(left) == len(walk) - len(blocked), '%s: with every fixture, NPC and portal placed no tile is cut off '
              '(%d of %d reached)' % (pid, len(left), len(walk) - len(blocked)))
        # the booths are closed: no NPC tile touches a floor tile a player can reach
        for _, k, front, room, name in booths:
            check(not any(n in left for n in neighbours(k)), '%s: %s stands in a closed booth' % (pid, name))
            check(front in left, '%s: the front of %s\'s booth %s is reached' % (pid, name, front))
            d_own = cheb(front, k)
            others = [cheb(front, b[1]) for b in booths if b[1] != k]
            check(d_own <= 2 and all(d > d_own for d in others),
                  '%s: in front of %s its own booth is the nearest NPC (%d, others %s)' % (pid, name, d_own, sorted(others)[:2]))
        for _, key, k, town in portals:
            check(any(n in left for n in neighbours(k)), '%s: the %s portal is reached' % (pid, key))
            want = [p for p in cfg['pos'] if p[0] == key and p[1] == town]
            check(len(want) == 1 and want[0][2] == k, '%s: %s_config.lua portal.positions for town %d is %s' % (pid, key, town, k))

        w, h = plan['size']
        for name, x0, y0, x1, y1 in other_areas({pid}):
            apart = ox > x1 + 10 or ox + w - 1 < x0 - 10 or oy > y1 + 10 or oy + h - 1 < y0 - 10
            check(apart, '%s keeps 10 tiles from %s' % (pid, name))
        check(14336 <= ox and ox + w - 1 <= 15359 and 14336 <= oy and oy + h - 1 <= 15359, pid + ': inside the content block')

    check(any(os.path.abspath(d) == ROOMS for d in I.FIXED_DIRS), 'install_content_areas.py places the rooms folder')
    fixed = I.fixed_plans((ROOMS,), {}, log=lambda s: None)
    check(all(pid in fixed for pid in cfg['halls']), 'the installer reads the halls as fixed areas')

    print('services_halls_test: %d failure(s)' % len(failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
