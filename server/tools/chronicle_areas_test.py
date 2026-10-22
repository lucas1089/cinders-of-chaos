#!/usr/bin/env python3
"""The planned areas of the Ashen Chronicle and the Capital Memorial (server/README.md "The Ashen Chronicle", "The Capital
Memorial"): every plan in server/tools/areaplan/chronicle/ validates and compiles with the area planner without a QA
error; the chapter areas' arrival offsets are the ones chronicle_config.lua uses; the Memorial's slots
(memorial_config.lua) are free floor in the right hall of the compiled plaza, and with every statue and stone placed no
walkable tile is cut off from the arrival.

    python3 -I server/tools/chronicle_areas_test.py                  # the checks (CI)
    python3 -I server/tools/chronicle_areas_test.py --preview OUT    # also OUT/<id>.png: a schematic preview per plan
                                                                      # (floor, walls, decoration, zones, the Memorial's
                                                                      # slots, the arrival and the exit; needs Pillow)
Needs LuaJIT (LUAJIT=... to point elsewhere), like the area planner.
"""
import glob, json, os, subprocess, sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import area_plan_core as C
import area_plan_compile as AC

PLANS = os.path.join(HERE, 'areaplan', 'chronicle')
LUAJIT = os.environ.get('LUAJIT', 'luajit')
ZONE_OF_KIND = {'first': 'hall_of_firsts', 'record': 'hall_of_records', 'fallen': 'garden_of_the_fallen', 'stone': 'plaza'}

failures = []


def check(cond, what):
    if not cond:
        failures.append(what)
        print('FAIL ' + what)


def lua(code):
    out = subprocess.run([LUAJIT, '-e', code], cwd=SERVER, capture_output=True, text=True, check=True).stdout
    return [line.split() for line in out.splitlines() if line.strip()]


def memorial_slots():
    rows = lua('local c = dofile("data/scripts/chaos/memorial_config.lua") '
               'for _, k in ipairs({"first", "record", "fallen"}) do for i, o in ipairs(c.slots[k]) do '
               'print(k, i, o[1], o[2]) end end print("stone", 1, c.slots.stone[1], c.slots.stone[2]) '
               'print("plan", c.plaza.plan, 0, 0) '
               'local function p3(k, t) if t then print(k, t.x or t[1], t.y or t[2], t.z or t[3]) end end '
               'p3("at", c.plaza.at) p3("arrival", c.plaza.arrival) p3("portal", c.plaza.portal) '
               'print("towns", #(c.portalTowns or {}), 0, 0)')
    slots, plan, place = [], None, {}
    for row in rows:
        if row[0] == 'plan':
            plan = row[1]
        elif row[0] == 'towns':
            place['towns'] = int(row[1])
        elif row[0] in ('at', 'arrival', 'portal'):
            place[row[0]] = tuple(int(v) for v in row[1:4])
        else:
            k, i, x, y = row
            slots.append((k, int(i), int(x), int(y)))
    return slots, plan, place


def chronicle_areas():
    rows = lua('local c = dofile("data/scripts/chaos/chronicle_config.lua") for _, a in ipairs(c.areas) do '
               'local at, g = a.at or {x = -1, y = -1, z = -1}, a.gate or {x = -1, y = -1, z = -1} '
               'print(a.key, a.plan, a.arrival[1], a.arrival[2], a.arrival[3], a.minLevel, at.x, at.y, at.z, g.x, g.y, g.z) end')
    out = []
    for r in rows:
        at, gate = tuple(int(v) for v in r[6:9]), tuple(int(v) for v in r[9:12])
        out.append(dict(key=r[0], plan=r[1], arrival=(int(r[2]), int(r[3]), int(r[4])), minLevel=int(r[5]),
                        at=None if at[0] < 0 else at, gate=None if gate[0] < 0 else gate))
    return out


def neighbours(k):
    """the 8 tiles around (players walk diagonally too)"""
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


def preview(result, plan, out_dir, marks):
    from PIL import Image, ImageDraw
    ox, oy, oz = result['origin']
    w, h = plan['size']
    scale = 12
    floors = plan['floors']
    img = Image.new('RGB', (w * scale, (h * scale + 18) * floors), (12, 10, 14))
    d = ImageDraw.Draw(img)
    walk, tiles = result['walk'], result['tiles']
    for f in range(floors):
        z = oz + f
        top = f * (h * scale + 18) + 18
        d.text((4, top - 16), '%s, floor %d (z %d)' % (plan['name'], f + 1, z), fill=(232, 184, 74))
        for y in range(h):
            for x in range(w):
                k = (ox + x, oy + y, z)
                t = tiles.get(k)
                if not t or t['ground'] is None:
                    continue
                col = (70, 64, 58) if k in walk else (28, 24, 26)
                if k in result['pz']:
                    col = (64, 72, 90) if k in walk else col
                if k in walk and t['items']:
                    col = (110, 96, 70)
                d.rectangle([x * scale, top + y * scale, x * scale + scale - 1, top + y * scale + scale - 1], fill=col)
        for zid, r in result['zrect'].items():
            if r[4] != z:
                continue
            d.rectangle([(r[0] - ox) * scale, top + (r[1] - oy) * scale, (r[2] - ox + 1) * scale - 1,
                         top + (r[3] - oy + 1) * scale - 1], outline=(200, 160, 80))
            d.text(((r[0] - ox) * scale + 2, top + (r[1] - oy) * scale + 1), zid, fill=(246, 207, 114))
        for (x, y, mz), col in marks:
            if mz == z:
                d.ellipse([(x - ox) * scale + 2, top + (y - oy) * scale + 2, (x - ox) * scale + scale - 3,
                           top + (y - oy) * scale + scale - 3], fill=col)
    path = os.path.join(out_dir, plan['id'] + '.png')
    img.save(path)
    return path


def main(args):
    out_dir = None
    if '--preview' in args:
        out_dir = args[args.index('--preview') + 1]
        os.makedirs(out_dir, exist_ok=True)
    cat = C.catalogue(C.pair24_switch(), False)
    plans = sorted(glob.glob(os.path.join(PLANS, '*.json')))
    check(len(plans) >= 3, 'the plaza and the chapter areas are there')
    slots, plaza_plan, plaza_place = memorial_slots()
    areas = {a['plan']: a for a in chronicle_areas()}
    compiled = {}
    for path in plans:
        plan = json.load(open(path, encoding='utf-8'))
        issues = C.validate(plan, cat)
        errs = C.errors(issues)
        check(not errs, '%s validates: %s' % (os.path.basename(path), '; '.join(str(e) for e in errs)))
        if errs:
            continue
        r = AC.compile_plan(plan, cat=cat)
        check(not AC.qa_errors(r), '%s compiles without a QA error: %s' % (plan['id'], AC.qa_errors(r)))
        compiled[plan['id']] = (plan, r)
        check(plan['id'] == os.path.splitext(os.path.basename(path))[0], plan['id'] + ': the file is named by the id')
    # the chapter areas: chronicle_config.lua knows each one with its arrival offset
    for pid, a in areas.items():
        check(pid in compiled, 'chronicle_config.lua area %s has its plan %s.json' % (a['key'], pid))
        if pid not in compiled:
            continue
        plan, r = compiled[pid]
        ox, oy, oz = r['origin']
        ax, ay, az = r['arrival']
        check(a['arrival'] == (ax - ox, ay - oy, az - oz), '%s: arrival offset %s (the plan gives %s)'
              % (a['key'], a['arrival'], (ax - ox, ay - oy, az - oz)))
        check(a['minLevel'] <= plan['level'][0], '%s: minLevel %d at most the plan\'s band %d' % (a['key'], a['minLevel'], plan['level'][0]))
        check(r['exit'] and r['exit'].get('aid') == 47951, '%s: an exit portal back to the temple' % a['key'])
        # install step contentareas places the plan at its own origin: `at` must be that origin; the gate is a world tile
        check(a['at'] == (ox, oy, oz), '%s: at %s is the plan\'s origin %s' % (a['key'], a['at'], (ox, oy, oz)))
        # the gate: one fixed world tile (`gate`, a staff override) or, unset, the Chronicle Gates of gateTowns that
        # cityportals.lua places in the portal gallery at the temple (tests/cityportals_test.lua checks those tiles)
        check(a['gate'] is None or not (14336 <= a['gate'][0] <= 15359 and 14336 <= a['gate'][1] <= 15359),
              '%s: a gate tile in the world (not inside the content block): %s' % (a['key'], a['gate']))
    for pid in compiled:
        if pid.startswith('chronicle_'):
            check(pid in areas, '%s.json is an area of chronicle_config.lua' % pid)
    # the Memorial's plaza and its slots
    check(plaza_plan in compiled, 'the plaza plan %s compiles' % plaza_plan)
    if plaza_plan in compiled:
        plan, r = compiled[plaza_plan]
        ox, oy, oz = r['origin']
        walk, tiles = r['walk'], r['tiles']
        check(not plan.get('spawns') and not plan.get('boss'), 'no monster in the plaza')
        check(plaza_place.get('at') == (ox, oy, oz), 'plaza.at %s is the plan\'s origin %s' % (plaza_place.get('at'), (ox, oy, oz)))
        ax, ay, az = r['arrival']
        check(plaza_place.get('arrival') == (ax - ox, ay - oy, az - oz), 'plaza.arrival %s (the plan gives %s)'
              % (plaza_place.get('arrival'), (ax - ox, ay - oy, az - oz)))
        check(plaza_place.get('portal') is not None or plaza_place.get('towns', 0) > 0,
              'plaza.portal or portalTowns: the way in (cityportals.lua places the Memorial Portal)')
        check(all(z['pz'] for z in r['manifest']['zones'].values()), 'every zone of the plaza is protected')
        start = tuple(r['arrival'])
        every = reachable(walk, start, set())
        check(len(every) == len(walk), 'every walkable tile of the plaza is reached from the arrival')
        protect = {start, tuple(r['exit']['at'])}
        blocked, seen = set(), set()
        for kind, i, dx, dy in slots:
            k = (ox + dx, oy + dy, oz)
            check(k not in seen, '%s slot %d (%d, %d) used once' % (kind, i, dx, dy))
            seen.add(k)
            zr = r['zrect'][ZONE_OF_KIND[kind]]
            check(zr[0] <= k[0] <= zr[2] and zr[1] <= k[1] <= zr[3], '%s slot %d (%d, %d) in %s' % (kind, i, dx, dy, ZONE_OF_KIND[kind]))
            check(k in walk, '%s slot %d (%d, %d) is walkable floor' % (kind, i, dx, dy))
            check(k in tiles and not tiles[k]['items'], '%s slot %d (%d, %d) holds no decoration' % (kind, i, dx, dy))
            check(k not in protect, '%s slot %d (%d, %d) is not the arrival or the exit' % (kind, i, dx, dy))
            if kind != 'stone':
                blocked.add(k)  # statues and grave stones block
        left = reachable(walk, start, blocked)
        check(len(left) == len(walk) - len(blocked), 'with every statue placed no tile is cut off (%d of %d reached)'
              % (len(left), len(walk) - len(blocked)))
    if out_dir:
        colors = {'first': (255, 154, 60), 'record': (127, 168, 255), 'fallen': (200, 200, 200), 'stone': (111, 216, 111)}
        for pid, (plan, r) in sorted(compiled.items()):
            ox, oy, oz = r['origin']
            marks = [(tuple(r['arrival']), (232, 64, 64)), (tuple(r['exit']['at']), (192, 112, 255))]
            for t in r.get('teleports') or []:
                marks.append((tuple(t['at']), (192, 112, 255)))
            if pid == plaza_plan:
                for kind, i, dx, dy in slots:
                    marks.append(((ox + dx, oy + dy, oz), colors[kind]))
            print('preview', preview(r, plan, out_dir, marks))
            with open(os.path.join(out_dir, pid + '.json'), 'w') as f:
                json.dump(r['manifest'], f, indent=1, sort_keys=True)
    print('chronicle_areas_test: %d plan(s), %d failure(s)' % (len(compiled), len(failures)))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
