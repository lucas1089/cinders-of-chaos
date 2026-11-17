#!/usr/bin/env python3
"""The boss lairs of bosslair_config.lua against their plans (O616, server/README.md "Talath's lair (O616)").

    python3 -I server/tools/boss_lair_test.py

For every lair: its plan (server/tools/areaplan/rooms/<plan>.json) validates and compiles with the area planner without a
QA error and is a fixed area of install_content_areas.py; the config's `at` is the plan's origin, `arrival` the compiled
arrival, `boss` the compiled boss spawn point (the lair's monster, the config's respawn, inside the boss room, with room
to fight around it), `back` the plan's exit destination and `portal` the plan's recorded way in. The portal and the way
back are bare walkable tiles of the compiled hunt plan, outside a protection zone, the portal with free ground all
round and three tiles or more from a spawn point. The lair shares the hunt's level band, keeps 40 tiles from every
other planned area and lies in the annex row. Talath's lair: an ice area off an ice hunt whose band holds the level its
mechanics are fair for (boss_mechanics_config.lua).
Needs LuaJIT (LUAJIT=... to point elsewhere), like the area planner.
"""
import glob, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import area_plan_core as C  # noqa: E402
import area_plan_compile as AC  # noqa: E402
import install_content_areas as I  # noqa: E402

ROOMS = os.path.join(HERE, 'areaplan', 'rooms')
PLANS = os.path.join(HERE, 'areaplan', 'plans')
LUAJIT = os.environ.get('LUAJIT', 'luajit')
APART = 40          # tiles between a lair and any other planned area
ROOM = 250          # walkable tiles of a boss room, at least
NEAR = 100          # walkable tiles within 7 tiles of the boss (Winter Ring reaches 7), at least

failures = []


def check(cond, what):
    if not cond:
        failures.append(what)
        print('FAIL ' + what)


def lairs():
    code = ('local c = dofile("data/scripts/chaos/bosslair_config.lua") for _, l in ipairs(c.lairs) do '
            'print(l.key, l.monster, l.plan, l.hunt, l.pair or 0, l.respawn, l.minLevel or 0, l.at.x, l.at.y, l.at.z, l.arrival[1], l.arrival[2], '
            'l.arrival[3], l.boss[1], l.boss[2], l.boss[3], l.portal.x, l.portal.y, l.portal.z, l.back.x, l.back.y, l.back.z) end')
    out = subprocess.run([LUAJIT, '-e', code], cwd=SERVER, capture_output=True, text=True, check=True).stdout
    rows = []
    for line in out.splitlines():
        f = line.split('\t')
        n = [int(v) for v in f[4:]]
        rows.append(dict(key=f[0], monster=f[1], plan=f[2], hunt=f[3], pair=n[0], respawn=n[1], min_level=n[2], at=tuple(n[3:6]),
                         arrival=tuple(n[6:9]), boss=tuple(n[9:12]), portal=tuple(n[12:15]), back=tuple(n[15:18])))
    return rows


def other_areas(skip):
    out = []
    for path in glob.glob(os.path.join(HERE, 'areaplan', '*', '*.json')):
        p = json.load(open(path, encoding='utf-8'))
        o = p.get('origin') if isinstance(p, dict) else None
        if o and 'size' in p and p.get('id') != skip:
            out.append((p['id'], o['x'], o['y'], o['x'] + p['size'][0] - 1, o['y'] + p['size'][1] - 1))
    return out


def fair_level(key):
    """refLevel of the boss's mechanics (boss_mechanics_config.lua), or None"""
    text = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'boss_mechanics_config.lua'), encoding='utf-8').read()
    m = re.search(r'\["%s"\] = \{\s*[^\n]*?element = "(\w+)"[^\n]*?fair = \{refLevel = (\d+)\}' % re.escape(key), text)
    return (m.group(1), int(m.group(2))) if m else (None, None)


def main():
    rows = lairs()
    check(len(rows) >= 1, 'bosslair_config.lua has a lair')
    cat = C.catalogue(C.pair24_switch(), False)
    fixed = I.fixed_plans((ROOMS,), {}, log=lambda s: None)
    check(any(os.path.abspath(d) == ROOMS for d in I.FIXED_DIRS), 'install_content_areas.py places the rooms folder')
    for r in rows:
        k = r['key']
        plan = json.load(open(os.path.join(ROOMS, r['plan'] + '.json'), encoding='utf-8'))
        errs = C.errors(C.validate(plan, cat))
        check(not errs, '%s: the plan validates: %s' % (k, '; '.join(str(e) for e in errs)))
        check(plan['id'] == r['plan'] and r['plan'] in fixed, '%s: the installer reads the plan as a fixed area' % k)
        res = AC.compile_plan(plan)
        check(not AC.qa_errors(res), '%s: the plan compiles without a QA error: %s' % (k, AC.qa_errors(res)[:3]))
        man = res['manifest']
        o = plan['origin']
        origin = (o['x'], o['y'], o['z'])
        check(r['at'] == origin, '%s: `at` %s is the plan\'s origin %s' % (k, r['at'], origin))

        def absolute(off):
            return (origin[0] + off[0], origin[1] + off[1], origin[2] + off[2])

        check(absolute(r['arrival']) == tuple(man['arrival']), '%s: `arrival` %s is the compiled arrival %s (offset %s)' % (
            k, r['arrival'], man['arrival'], tuple(a - b for a, b in zip(man['arrival'], origin))))
        b = res['boss']
        check(b is not None and b['monster'] == r['monster'], '%s: the plan\'s boss is %s' % (k, r['monster']))
        if b:
            bp = (b['x'], b['y'], b['z'])
            check(absolute(r['boss']) == bp, '%s: `boss` %s is the compiled spawn point %s (offset %s)' % (
                k, r['boss'], bp, tuple(a - c for a, c in zip(bp, origin))))
            check(b['spawntime'] == r['respawn'] == plan['boss'].get('respawn'), '%s: the respawn is the config\'s (%s)' % (k, b['spawntime']))
            check(3600 <= b['spawntime'] <= 86400, '%s: a lair boss comes back hours after its death' % k)
            zone = man['zones'][b['zone']]
            x0, y0, x1, y1 = zone['rect']
            check(zone['role'] == 'boss' and not zone['pz'] and x0 <= bp[0] <= x1 and y0 <= bp[1] <= y1, '%s: the boss stands in the boss room' % k)
            room = [p for p in res['walk'] if p[2] == bp[2] and x0 <= p[0] <= x1 and y0 <= p[1] <= y1]
            near = [p for p in room if max(abs(p[0] - bp[0]), abs(p[1] - bp[1])) <= 7]
            check(len(room) >= ROOM and len(near) >= NEAR, '%s: the boss room has room to fight (%d walkable tiles, %d within 7 of the boss)'
                  % (k, len(room), len(near)))
            check('<monster name="%s"' % r['monster'] in res['spawn_xml'] and 'spawntime="%d"' % r['respawn'] in res['spawn_xml'],
                  '%s: the spawn file has the boss with its respawn' % k)
            check(man['stats'].get('entry_to_boss'), '%s: the boss is reached from the arrival' % k)
        check(not res['spawns'], '%s: the lair has no other monster' % k)
        az = [z for z in man['zones'].values() if z['rect'][0] <= man['arrival'][0] <= z['rect'][2] and z['rect'][1] <= man['arrival'][1] <= z['rect'][3]]
        check(az and az[0]['pz'], '%s: players arrive in a protection zone' % k)
        ex = man.get('exit') or {}
        check(tuple(ex.get('to') or ()) == r['back'], '%s: the exit portal leads to `back` %s (%s)' % (k, r['back'], ex.get('to')))
        fw = (plan.get('entry') or {}).get('from_world') or {}
        check((fw.get('x'), fw.get('y'), fw.get('z')) == r['portal'], '%s: the plan records the way in %s' % (k, r['portal']))
        ox, oy = origin[0], origin[1]
        w, h = plan['size']
        for name, ax0, ay0, ax1, ay1 in other_areas(plan['id']):
            apart = ox > ax1 + APART or ox + w - 1 < ax0 - APART or oy > ay1 + APART or oy + h - 1 < ay0 - APART
            check(apart, '%s: the lair keeps %d tiles from %s' % (k, APART, name))
        check(14336 <= ox and ox + w - 1 <= 17663 and 15400 <= oy and oy + h - 1 <= 16383, '%s: inside the annex row' % k)

        # the hunt: the portal and the way back
        hunt = json.load(open(os.path.join(PLANS, r['hunt'] + '.json'), encoding='utf-8'))
        hres = AC.compile_plan(hunt)
        walk, tiles = hres['walk'], hres['tiles']

        def bare(p):
            t = tiles.get(p)
            return p in walk and t is not None and not t['items'] and not t['flags']

        px, py, pz = r['portal']
        check(bare(r['portal']) and bare(r['back']), '%s: the portal and the way back are bare walkable tiles of %s' % (k, r['hunt']))
        check(all(bare((px + dx, py + dy, pz)) for dx in (-1, 0, 1) for dy in (-1, 0, 1)), '%s: free ground all round the portal' % k)
        check(r['back'] != r['portal'] and max(abs(r['back'][0] - px), abs(r['back'][1] - py)) <= 3, '%s: the way back lands beside the portal' % k)
        check(all(max(abs(s['x'] - px), abs(s['y'] - py)) >= 3 for s in hres['spawns'] if s['z'] == pz), '%s: no spawn point within 2 tiles of the portal' % k)
        hz = [n for n, z in hres['manifest']['zones'].items() if z['rect'][0] <= px <= z['rect'][2] and z['rect'][1] <= py <= z['rect'][3]]
        check(hz and not hres['manifest']['zones'][hz[0]]['pz'], '%s: the portal stands in a hunting zone (%s)' % (k, hz))
        check(plan['level'] == hunt['level'], '%s: the lair has the hunt\'s level band' % k)
        check(r['min_level'] <= hunt['level'][0], '%s: who hunts there may enter (level %d, the hunt starts at %d)' % (k, r['min_level'], hunt['level'][0]))
        if k == 'talath':
            element, ref = fair_level('talath')
            check(element == 'ice' and plan['biome'] == 'ice' and hunt['biome'] == 'ice', 'talath: an ice lair off an ice hunt for the ice boss')
            check(ref is not None and hunt['level'][0] <= ref <= hunt['level'][1], 'talath: the hunt\'s band %s holds the level its mechanics are fair for (%s)'
                  % (hunt['level'], ref))
            check(hz == ['glacial_col'], 'talath: the portal stands in the Glacial Col')
            check(r['pair'] == 73, 'talath: open from client pair 73')
    print('boss_lair_test: %d failure(s)' % len(failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
