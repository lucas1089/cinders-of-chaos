#!/usr/bin/env python3
"""Imported hunt areas: free community maps cut into hunts of our world (docs/MAP_GUIDE.md "Imported hunts").

An imported area is a plan of server/tools/areaplan/plans/ with schema "chaos-area-import/1" instead of the generator's
plan: its tiles are not generated, they are a cut of a community map, kept in git as a small chunk
(server/tools/areaplan/imports/<id>.otbm.xz, the planner's own OTBM format) with the spawns decided at extraction.
install_content_areas.py places it like every other plan (origin, teleport slot by level band, spawns, places file).

usage: python3 -I server/tools/area_import.py extract SPEC.json SOURCE.otbm ASSETS_DIR [--out-plans DIR] [--out-chunks DIR] [--dry-run]
       python3 -I server/tools/area_import.py compile PLAN.json OUT_DIR       (what the installer and CI run)
       python3 -I server/tools/area_import.py validate PLAN.json
       python3 -I server/tools/area_import.py preview PLAN.json ASSETS_DIR OUT.png [--scale N]

extract  developer step, needs the source map (never in git), numpy, scipy and the items of the installed server in
         ASSETS_DIR (items.otb, items.xml, Tibia.dat, optional Tibia.spr for preview). The spec
         (server/tools/areaplan/imports/<id>.spec) holds: id, name, biome, level, source rectangle on one floor
         (the walkable cave plus a 10 tile frame of the map's own rock or sea), the arrival tile, the origin on our map and
         the monster mix. It writes the plan and the chunk. Deterministic: the same inputs, the same bytes.
         What the cut does to the tiles:
           - only ground, border, wall and decoration items of known ids stay (groups none and ground). Unknown ids,
             containers, doors, keys, signs, fields, fluids, teleports and every action or unique id go;
           - floor changes (stairs, holes, ladders) go: a stair that was the ground becomes the commonest walkable ground
             around it, so the cut area has no way down that leads nowhere;
           - protection zone, house and other tile flags go; the tile keeps its place with an offset (dx, dy) and floor z.
         Spawns: farthest-point spawn points over the walkable tiles joined to the arrival, outside 10 tiles of it,
         packs of 3 (one point = one pack), density `per100` monsters per 100 walkable tiles (docs/MAP_GUIDE.md
         "Hunting areas"), the mix shared out to the points by region (a monster holds a region, as in the planned hunts).
compile  writes OUT_DIR/<id>.otbm, <id>.json (the manifest install_content_areas.py reads) and <id>-spawn.xml.
Python 3 standard library for compile and validate.
"""
import json, lzma, os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

SCHEMA = 'chaos-area-import/1'
CHUNKS = os.path.join(HERE, 'areaplan', 'imports')
PLANS = os.path.join(HERE, 'areaplan', 'plans')
FRAME = 10          # tiles of the source map kept around the walkable area (the client sees 9 x 7 tiles beyond a player)
KEEP_GROUPS = (0, 1)
SPAWN_GAP = 5       # spawn points at least this far apart (Chebyshev), as gen_spawn_density.py
SAFE = 10           # no spawn this close to the arrival
PORTAL_ID = 1387    # the magic forcefield, hunt_teleports_config.lua items.portal
EXIT_AID = 47951    # areagen_config.lua aid.exit
FLOORNAME =re.compile(r'\b(hole|ramp|stairs?|staircase|ladder|trapdoor|pitfall|grate|rope spot)\b', re.I)


class ImportError_(Exception):
    pass


def is_import(plan):
    return isinstance(plan, dict) and plan.get('schema') == SCHEMA


def chunk_path(plan, plan_path):
    return os.path.join(os.path.dirname(os.path.abspath(plan_path)), '..', 'imports', plan['chunk'])


# ------------------------------------------------------------------------------------------------ validate / compile
def validate(plan, plan_path=None):
    """list of error strings"""
    errs = []
    for k in ('id', 'name', 'biome', 'size', 'floors', 'level', 'origin', 'arrival', 'chunk', 'spawns', 'source'):
        if k not in plan:
            errs.append('missing %s' % k)
    if errs:
        return errs
    o, sz = plan['origin'], plan['size']
    lv = plan['level']
    if not (isinstance(lv, list) and len(lv) == 2 and 1 <= lv[0] <= lv[1] <= 2500):
        errs.append('level must be [lo, hi] inside 1-2500')
    ar = plan['arrival']
    if not (o['x'] <= ar[0] < o['x'] + sz[0] and o['y'] <= ar[1] < o['y'] + sz[1] and ar[2] == o['z']):
        errs.append('the arrival is outside the box')
    for s in plan['spawns']:
        for p in s.get('points', []):
            if not (o['x'] <= p[0] < o['x'] + sz[0] and o['y'] <= p[1] < o['y'] + sz[1]):
                errs.append('%s: a spawn point is outside the box' % s.get('monster'))
                break
        if s.get('count') != len(s.get('points', [])) * s.get('pack', 1) and s.get('count') != sum(1 + len(p[2]) for p in s.get('points', [])):
            errs.append('%s: count is not the monsters of its points' % s.get('monster'))
    if plan_path:
        cp = chunk_path(plan, plan_path)
        if not os.path.isfile(cp):
            errs.append('chunk %s is missing' % plan['chunk'])
    return errs


def read_chunk(path):
    with lzma.open(path, 'rb') as f:
        return f.read()


def spawn_xml(plan):
    lines = ['<?xml version="1.0"?>', '<spawns>']
    z = plan['origin']['z']
    for s in plan['spawns']:
        for p in s['points']:
            lines.append('\t<spawn centerx="%d" centery="%d" centerz="%d" radius="1">' % (p[0], p[1], z))
            for dx, dy in [(0, 0)] + [tuple(d) for d in p[2]]:
                lines.append('\t\t<monster name="%s" x="%d" y="%d" z="%d" spawntime="%d" />' % (s['monster'], dx, dy, z, s['respawn']))
            lines.append('\t</spawn>')
    lines.append('</spawns>')
    return '\n'.join(lines) + '\n'


def compile_plan(plan_path, out_dir):
    plan = json.load(open(plan_path, encoding='utf-8'))
    errs = validate(plan, plan_path)
    if errs:
        raise ImportError_('%s: %s' % (plan.get('id'), '; '.join(errs)))
    os.makedirs(out_dir, exist_ok=True)
    pid = plan['id']
    data = read_chunk(chunk_path(plan, plan_path))
    with open(os.path.join(out_dir, pid + '.otbm'), 'wb') as f:
        f.write(data)
    with open(os.path.join(out_dir, pid + '-spawn.xml'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(spawn_xml(plan))
    o = plan['origin']
    man = dict(id=pid, name=plan['name'], biome=plan['biome'], schema=SCHEMA, floors=1, size=plan['size'],
               origin=[o['x'], o['y'], o['z']], arrival=plan['arrival'], boss=None, chests=[], stubs=[],
               teleports=[], npcs=[], links=[], exit=dict(plan['exit'], to=None), dark=False, spawns=sum(len(s['points']) for s in plan['spawns']),
               frame=None, qa=[], plan_issues=[])
    with open(os.path.join(out_dir, pid + '.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(man, f, indent=1, sort_keys=True)
        f.write('\n')
    return man


# ------------------------------------------------------------------------------------------------ extract
def _tables(assets):
    root = os.path.join(HERE, '..', '..', 'tools', 'map')
    sys.path.insert(0, root)
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites'))
    import itemdb, analyze
    dat = os.path.join(assets, 'Tibia.dat')
    db = itemdb.ItemDB(os.path.join(assets, 'items.otb'), os.path.join(assets, 'items.xml'), dat if os.path.isfile(dat) else None)
    return db, analyze.ItemTables(db), analyze, itemdb


def convert(m, spec, db, it, analyze, itemdb):
    """{(x, y, z): {'ground', 'items': [(id, {})], 'flags': 0}} of the cut, on our map, and the walkable set"""
    x0, y0, x1, y1 = spec['rect']
    z = spec['z']
    ox, oy, oz = spec['origin']['x'], spec['origin']['y'], spec['origin']['z']
    C = itemdb.C
    src = {}
    for i in m.rect(x0, y0, x1, y1, z):
        x, y = int(m.tiles['x'][i]), int(m.tiles['y'][i])
        src[(x, y)] = [int(v) for v in m.stack(i)]
    blocked_ground = {}

    def way(sid):
        return db.cls[sid] == C['floorchg'] or FLOORNAME.search(db.name[sid] or '') is not None

    def keep(sid):
        return bool(db.known[sid]) and int(db.group[sid]) in KEEP_GROUPS and not way(sid) and db.cls[sid] != C['door']

    def is_walk_ground(g):
        return not it.block[g] and int(it.gcat[g]) not in (analyze.G['water'], analyze.G['lava'])

    tiles = {}
    for (x, y), st in src.items():
        g = next((s for s in st if db.known[s] and db.cls[s] == C['ground'] and not way(s)), None)
        rest = [s for s in st if s != g and keep(s) and db.cls[s] != C['ground']]
        tiles[(x, y)] = [g, rest]
    # a ground lost with a floor change (a stair is the ground): the commonest walkable ground around it
    for (x, y), (g, rest) in sorted(tiles.items()):
        if g is None and src[(x, y)]:
            around = {}
            for wide in (1, 2):
                for dx in range(-wide, wide + 1):
                    for dy in range(-wide, wide + 1):
                        t = tiles.get((x + dx, y + dy))
                        if t and t[0] is not None and is_walk_ground(t[0]):
                            around[t[0]] = around.get(t[0], 0) + 1
                if around:
                    break
            if around:
                tiles[(x, y)][0] = sorted(around.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
    out = {}
    for (x, y), (g, rest) in tiles.items():
        if g is None:
            continue
        out[(x - x0 + ox, y - y0 + oy, oz)] = dict(ground=g, items=[(s, {}) for s in rest], flags=0)
    walk = set()
    for p, t in out.items():
        if not is_walk_ground(t['ground']):
            continue
        if any(it.block[s] or it.is_wall[s] for s, _a in t['items']):
            continue
        walk.add(p)
    return out, walk


def joined(walk, start):
    seen, todo = {start}, [start]
    while todo:
        x, y, z = todo.pop()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy, z)
                if q in walk and q not in seen:
                    seen.add(q)
                    todo.append(q)
    return seen


def central_tile(walk, free=None):
    """the tile nearest the middle of the largest walkable set whose 3 x 3 square is walkable too (and, with `free`, a
    tile with nothing on it)"""
    left, best = set(walk), set()
    while left:
        comp = joined(left, min(left))
        left -= comp
        if len(comp) > len(best):
            best = comp
    cx = sum(p[0] for p in best) / float(len(best))
    cy = sum(p[1] for p in best) / float(len(best))
    ok = [p for p in best if (free is None or p in free) and all((p[0] + dx, p[1] + dy, p[2]) in best for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
    return min(ok or sorted(best), key=lambda p: ((p[0] - cx) ** 2 + (p[1] - cy) ** 2, p))


def spawn_points(region, arrival, per100, pack=3):
    """farthest-point spawn points: [(x, y, [(dx, dy), ...])] covering per100 monsters per 100 walkable tiles"""
    import numpy as np
    pts = sorted(p for p in region if max(abs(p[0] - arrival[0]), abs(p[1] - arrival[1])) > SAFE)
    want = int(round(len(region) * per100 / 100.0 / pack))
    arr = np.array([(p[0], p[1]) for p in pts], np.int64)
    dist = np.full(len(pts), 10 ** 9, np.int64)
    chosen = []
    # a point with at least two free neighbours for the pack, the far side of the area first by x then y on ties
    nb = set(region)
    ok = [k for k, p in enumerate(pts) if sum((p[0] + dx, p[1] + dy, p[2]) in nb for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1))) >= 2]
    if not ok:
        return []
    first = ok[0]
    cur = first
    while len(chosen) < want:
        chosen.append(cur)
        d = np.maximum(np.abs(arr[:, 0] - arr[cur, 0]), np.abs(arr[:, 1] - arr[cur, 1]))
        dist = np.minimum(dist, d)
        cand = [k for k in ok if dist[k] >= SPAWN_GAP]
        if not cand:
            break
        cur = max(cand, key=lambda k: (int(dist[k]), -pts[k][0], -pts[k][1]))
    out = []
    for k in chosen:
        p = pts[k]
        offs = []
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            if len(offs) >= pack - 1:
                break
            if (p[0] + dx, p[1] + dy, p[2]) in nb:
                offs.append((dx, dy))
        out.append((p[0], p[1], offs))
    return out


def share_out(points, mix):
    """regions: farthest-point centres, one per mix entry (heaviest first); each point goes to the nearest centre.
    A monster of the mix holds one region of the hunt. Returns {monster index: [points]}"""
    import numpy as np
    k = len(mix)
    xy = np.array([(p[0], p[1]) for p in points], np.int64)
    centres = [0]
    while len(centres) < min(k, len(points)):
        d = np.min([np.maximum(np.abs(xy[:, 0] - xy[c, 0]), np.abs(xy[:, 1] - xy[c, 1])) for c in centres], axis=0)
        centres.append(int(np.argmax(d)))
    out = {i: [] for i in range(k)}
    order = sorted(range(len(centres)), key=lambda i: (-xy[centres[i], 0] - xy[centres[i], 1], i))
    # the heaviest monster of the mix takes the centre that holds the most points
    held = {c: 0 for c in range(len(centres))}
    near = []
    for p in range(len(points)):
        c = min(range(len(centres)), key=lambda c: (max(abs(xy[p, 0] - xy[centres[c], 0]), abs(xy[p, 1] - xy[centres[c], 1])), c))
        near.append(c)
        held[c] += 1
    ranked = sorted(held, key=lambda c: (-held[c], c))
    heavy = sorted(range(k), key=lambda i: (-mix[i].get('weight', 1), i))
    owner = {c: heavy[r] for r, c in enumerate(ranked)}
    for p, c in zip(points, near):
        out[owner[c]].append(p)
    return out


def encode_chunk(spec, tiles):
    import area_plan_compile as PC
    o = spec['origin']
    data = PC.otbm_bytes(spec['name'], spec['id'], 'imported cut at %d,%d,%d' % (o['x'], o['y'], o['z']), tiles,
                         spec['id'] + '-spawn.xml', spec['id'] + '-house.xml')
    return data


def extract(spec_path, source, assets, out_plans=PLANS, out_chunks=CHUNKS, dry=False, log=print):
    spec = json.load(open(spec_path, encoding='utf-8'))
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools', 'map'))
    import otbm
    db, it, analyze, itemdb = _tables(assets)
    m = otbm.load_map(source)
    tiles, walk = convert(m, spec, db, it, analyze, itemdb)
    o = spec['origin']
    x0, y0, x1, y1 = spec['rect']
    if spec.get('arrival'):
        sx, sy = spec['arrival']
        arrival = (sx - x0 + o['x'], sy - y0 + o['y'], o['z'])
    else:
        arrival = central_tile(walk, {p for p in walk if not tiles[p]['items']})
    if arrival not in walk:
        raise ImportError_('%s: the arrival %s is not a walkable tile' % (spec['id'], arrival))
    region = joined(walk, arrival)
    # only the walkable set joined to the arrival and a frame of FRAME tiles around it stay: pockets the player cannot
    # reach and the rest of the cut go (the player sees at most 9 x 7 tiles beyond the area)
    near = set()
    for (x, y, z) in region:
        for dx in range(-FRAME, FRAME + 1):
            for dy in range(-FRAME, FRAME + 1):
                near.add((x + dx, y + dy, z))
    tiles = {p: t for p, t in tiles.items() if p in near}
    walk = {p for p in walk if p in tiles}
    # the way back: a forcefield with the exit action id on a free walkable tile 2 tiles from the arrival (areagen_config.lua
    # aid.exit; the installed hunt teleports lead it to the hall, as the planned hunts' camp portal) and a protection
    # zone of 7 x 7 tiles around the arrival, the camp
    ring = sorted(p for p in region if max(abs(p[0] - arrival[0]), abs(p[1] - arrival[1])) == 2 and not tiles[p]['items'])
    if not ring:
        raise ImportError_('%s: no free tile for the exit portal near the arrival' % spec['id'])
    exit_at = ring[len(ring) // 2]
    tiles[exit_at]['items'].append((PORTAL_ID, {'aid': EXIT_AID}))
    for p in region:
        if max(abs(p[0] - arrival[0]), abs(p[1] - arrival[1])) <= 3:
            tiles[p]['flags'] = 1
    xs = [p[0] for p in tiles]
    ys = [p[1] for p in tiles]
    pts = spawn_points(region, arrival, spec.get('per100', 4.4), spec.get('pack', 3))
    parts = share_out(pts, spec['mix'])
    spawns = []
    for i, mx in enumerate(spec['mix']):
        ps = parts[i]
        if not ps:
            continue
        spawns.append(dict(monster=mx['monster'], count=sum(1 + len(p[2]) for p in ps), pack=spec.get('pack', 3),
                           respawn=mx['respawn'], zone='imported', points=[[p[0], p[1], [list(d) for d in p[2]]] for p in ps]))
    size = [max(xs) - min(xs) + 1, max(ys) - min(ys) + 1]
    o = dict(o, x=min(xs), y=min(ys))
    plan = dict(schema=SCHEMA, id=spec['id'], name=spec['name'], biome=spec['biome'], size=size, floors=1, level=spec['level'],
                origin=o, arrival=list(arrival), entry={'zone': 'imported'}, exit={'aid': EXIT_AID, 'at': list(exit_at)}, zones=[], chunk=spec['id'] + '.otbm.xz',
                source=dict(spec['source'], z=spec['z'], rect=spec['rect']), spawns=spawns, notes=spec.get('notes', ''),
                stats=dict(tiles=len(tiles), walkable=len(region), monsters=sum(s['count'] for s in spawns),
                           spawn_points=len(pts), per100=round(100.0 * sum(s['count'] for s in spawns) / max(1, len(region)), 2)))
    log('%s: %d tiles, %d walkable joined to the arrival (%d walkable in the cut), %d spawn points, %d monsters, %.2f per 100'
        % (spec['id'], len(tiles), len(region), len(walk), len(pts), plan['stats']['monsters'], plan['stats']['per100']))
    if dry:
        return plan
    data = encode_chunk(spec, tiles)
    os.makedirs(out_chunks, exist_ok=True)
    with lzma.open(os.path.join(out_chunks, plan['chunk']), 'wb', preset=6) as f:
        f.write(data)
    with open(os.path.join(out_plans, spec['id'] + '.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(plan, f, indent=1, sort_keys=False)
        f.write('\n')
    return plan


def preview(plan_path, assets, out_png, scale=12):
    """the area as the client draws it with the spawn points marked (needs the sprite pair in ASSETS_DIR)"""
    import tempfile
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools', 'map'))
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites'))
    import otbm, render
    from datspr import Spr
    from PIL import ImageDraw
    plan = json.load(open(plan_path, encoding='utf-8'))
    db, it, analyze, itemdb = _tables(assets)
    tmp = tempfile.mkdtemp()
    compile_plan(plan_path, tmp)
    m = otbm.load_map(os.path.join(tmp, plan['id'] + '.otbm'))
    spr = Spr(os.path.join(assets, 'Tibia.spr'))
    o, sz = plan['origin'], plan['size']
    img, miss = render.render(m, db, spr, o['x'], o['y'], o['x'] + sz[0] - 1, o['y'] + sz[1] - 1, o['z'])
    d = ImageDraw.Draw(img)
    for s in plan['spawns']:
        for p in s['points']:
            cx, cy = (p[0] - o['x']) * 32 + 16, (p[1] - o['y']) * 32 + 16
            d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], outline=(255, 40, 40), width=3)
    a = plan['arrival']
    cx, cy = (a[0] - o['x']) * 32 + 16, (a[1] - o['y']) * 32 + 16
    d.rectangle([cx - 14, cy - 14, cx + 14, cy + 14], outline=(40, 255, 40), width=4)
    w = sz[0] * scale
    img = img.resize((w, int(img.height * w / img.width)))
    img.save(out_png)
    return out_png, miss


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, args = argv[0], argv[1:]
    try:
        if cmd == 'compile':
            man = compile_plan(args[0], args[1])
            print(os.path.join(args[1], man['id'] + '.otbm'))
            return 0
        if cmd == 'validate':
            plan = json.load(open(args[0], encoding='utf-8'))
            errs = validate(plan, args[0])
            for e in errs:
                print(e)
            print('%d error(s), 0 warning(s)' % len(errs))
            return 1 if errs else 0
        if cmd == 'extract':
            dry = '--dry-run' in args
            args = [a for a in args if a != '--dry-run']
            extract(args[0], args[1], args[2], dry=dry)
            return 0
        if cmd == 'preview':
            scale = int(args[args.index('--scale') + 1]) if '--scale' in args else 12
            print(*preview(args[0], args[1], args[2], scale))
            return 0
    except (ImportError_, OSError, ValueError) as e:
        print(e)
        return 1
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
