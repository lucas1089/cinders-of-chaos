#!/usr/bin/env python3
"""The area planner's compiler, QA and renderer (server/tools/area_planner.py; docs/MAP_GUIDE.md "Area planner").

compile_plan(plan) runs:
  1. area_plan_core.layout: zone rectangles, link points, landing spots, path routes (from the plan's seed);
  2. the area generator through tools/areaplan_build.lua: our grounds, auto-borders, walls, decoration, lights, holes
     and ladders, from our own tables only;
  3. the placements on the generated tiles: teleports, the exit portal, quest chests, NPCs, the boss, spawn points
     (spread inside their zones), protection-zone flags;
  4. QA on the written OTBM bytes: structure, tile flags, every id known to our catalogue, every border closed,
     reachability from the entry over holes, ladders and teleports, the boss room's single entrance, the stats.
The result holds the OTBM bytes, the spawn file, a manifest (zones, chests with their quest keys, portals, stats, QA)
and the tile model for render_floors(). The same plan and seed give the same bytes.
"""
import json, os, random, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import area_plan_core as C
import area_plan_decor as D
import areagen_export as AX

FLAG_PZ = 1
KNOWN_FLAGS = 1 | 4 | 8 | 16      # pz, no pvp, no logout, pvp zone (the planner writes pz only)
ATTR_TILE_FLAGS, ATTR_ITEM, ATTR_ACTION, ATTR_UNIQUE, ATTR_TELE = 3, 9, 4, 5, 8


class CompileError(Exception):
    pass


# ================================================================================================= Lua bridge
def lua_value(v, ind=''):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(v, (list, tuple)):
        return '{' + ', '.join(lua_value(x, ind) for x in v) + '}'
    if isinstance(v, dict):
        parts = []
        for k in sorted(v, key=str):
            key = ('[%d]' % k) if isinstance(k, int) else k
            parts.append('%s = %s' % (key, lua_value(v[k], ind)))
        return '{' + ', '.join(parts) + '}'
    if v is None:
        return 'nil'
    raise TypeError(type(v))


def origin_of(plan, biome):
    o = plan.get('origin')
    if o:
        return o['x'], o['y'], o['z']
    return C.DEFAULT_ORIGIN[0], C.DEFAULT_ORIGIN[1], biome['z']


def job_def(plan, cat, lay):
    biome = C.biome_of(plan, cat)
    ox, oy, oz = origin_of(plan, biome)
    W, H = plan['size']
    per_floor = {}
    for f in range(1, plan['floors'] + 1):
        zones = []
        for z in plan['zones']:
            if z['floor'] == f:
                r = lay['rects'][z['id']]
                zones.append(dict(x1=r[0], y1=r[1], x2=r[2], y2=r[3], shape=C.zone_shape(z, biome),
                                  kind='boss' if z.get('role') == 'boss' else 'hunt', ragged=bool(z.get('ragged'))))
        paths = [dict(width=p['width'], style=p['style'], points=[list(q) for q in p['points']]) for p in lay['paths'][f]]
        per_floor[f] = dict(zones=zones, paths=paths, spots=[list(s) for s in lay['spots'][f]],
                            anchor=list(lay['anchors'][f]))
    ax, ay = lay['arrival']
    return dict(id=plan['id'], name=plan['name'], origin=dict(x=ox, y=oy, z=oz), size=[W, H], floors=plan['floors'],
                seed=lay['seed'], arrival=[ax, ay], noExit=True,
                links=[dict(floor=l['floor'], x=l['x'], y=l['y']) for l in lay['links']],
                layout=dict(plan=per_floor),
                spawns=dict(density=0, minDistance=4, safeRadius=4, level=[1, 1], monsters=[]))


def run_build(plan, cat, lay, pair24, dark):
    job = dict(def_=job_def(plan, cat, lay), biome=plan['biome'], decoration=plan.get('decoration', 'normal'))
    if plan.get('light'):
        job['light'] = plan['light']
    text = 'return ' + lua_value(job).replace('def_ =', '["def"] =') + '\n'
    fd, path = tempfile.mkstemp(prefix='areaplan_', suffix='.lua')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        args = [C.lua_bin(), 'tools/areaplan_build.lua', 'build', path] + (['pair24'] if pair24 else []) + (['dark'] if dark else [])
        res = subprocess.run(args, cwd=C.SERVER, capture_output=True, text=True)
    finally:
        os.unlink(path)
    if res.returncode != 0:
        raise CompileError('the area generator failed: ' + res.stderr.strip()[-600:])
    meta = None
    lines = []
    for line in res.stdout.splitlines():
        if line.startswith('J '):
            meta = json.loads(line[2:])
        else:
            lines.append(line)
    area = AX.parse_dump('\n'.join(lines))[0]
    return area, meta


# ================================================================================================= OTBM
def otbm_bytes(name, area_id, origin_desc, tiles, spawn_name, house_name):
    """tiles: {(x, y, z): {'ground', 'items': [(id, attrs)], 'flags'}}; attrs = {'aid', 'uid', 'tele': (x, y, z)}"""
    root = AX.Node(0, struct.pack('<IHHII', 2, AX.MAP_W, AX.MAP_H, AX.ITEMS_MAJOR, AX.ITEMS_MINOR))
    md = root.add(AX.Node(2, AX._str_attr(1, 'Cinders of Chaos planned area: %s (%s)' % (name, origin_desc))
                          + AX._str_attr(11, spawn_name) + AX._str_attr(13, house_name)))
    keys = sorted(tiles, key=lambda t: (t[2], t[1] & 0xFF00, t[0] & 0xFF00, t[1], t[0]))
    cur_key, cur = None, None
    for k in keys:
        t = tiles[k]
        akey = (k[0] & 0xFF00, k[1] & 0xFF00, k[2])
        if akey != cur_key:
            cur_key = akey
            cur = md.add(AX.Node(4, struct.pack('<HHB', akey[0], akey[1], akey[2])))
        payload = bytes([k[0] & 0xFF, k[1] & 0xFF])
        if t['flags']:
            payload += bytes([ATTR_TILE_FLAGS]) + struct.pack('<I', t['flags'])
        payload += bytes([ATTR_ITEM]) + struct.pack('<H', t['ground'])
        node = cur.add(AX.Node(5, payload))
        for iid, attrs in t['items']:
            p = struct.pack('<H', iid)
            if attrs.get('aid'):
                p += bytes([ATTR_ACTION]) + struct.pack('<H', attrs['aid'])
            if attrs.get('uid'):
                p += bytes([ATTR_UNIQUE]) + struct.pack('<H', attrs['uid'])
            if attrs.get('tele'):
                x, y, z = attrs['tele']
                p += bytes([ATTR_TELE]) + struct.pack('<HHB', x, y, z)
            node.add(AX.Node(6, p))
    md.add(AX.Node(12))
    md.add(AX.Node(15))
    out = bytearray(b'\x00\x00\x00\x00')
    root.write(out)
    return bytes(out)


def read_otbm_full(data):
    """a strict reader for the planner's files: (header, tiles {(x, y, z): {'ground', 'items': [(id, attrs)], 'flags'}},
    problems). Checks the node nesting (root > map data > tile areas > tiles > items) and every attribute."""
    problems = []
    if data[:4] != b'\x00\x00\x00\x00':
        problems.append('the file does not start with the OTBM identifier')
    i, n = 4, len(data)
    stack, tiles, header, base, cur = [], {}, None, None, None
    allowed_parent = {0: None, 2: 0, 4: 2, 5: 4, 6: 5, 12: 2, 15: 2}
    while i < n:
        c = data[i]
        if c == 0xFE:
            kind = data[i + 1]
            i += 2
            buf = bytearray()
            while i < n and data[i] not in (0xFE, 0xFF):
                if data[i] == 0xFD:
                    i += 1
                buf.append(data[i])
                i += 1
            parent = stack[-1] if stack else None
            if kind not in allowed_parent:
                problems.append('unknown node type %d' % kind)
            elif allowed_parent[kind] != parent:
                problems.append('node %d inside node %s' % (kind, parent))
            stack.append(kind)
            try:
                if kind == 0:
                    header = struct.unpack_from('<IHHII', buf, 0)
                elif kind == 4:
                    base = struct.unpack_from('<HHB', buf, 0)
                elif kind == 5:
                    x, y = base[0] + buf[0], base[1] + buf[1]
                    cur = (x, y, base[2])
                    t = dict(ground=None, items=[], flags=0)
                    k = 2
                    while k < len(buf):
                        a = buf[k]
                        if a == ATTR_TILE_FLAGS:
                            t['flags'] = struct.unpack_from('<I', buf, k + 1)[0]
                            k += 5
                        elif a == ATTR_ITEM:
                            t['ground'] = struct.unpack_from('<H', buf, k + 1)[0]
                            k += 3
                        else:
                            problems.append('tile %s: unknown attribute %d' % (cur, a))
                            break
                    if cur in tiles:
                        problems.append('tile %s written twice' % (cur,))
                    tiles[cur] = t
                elif kind == 6:
                    iid = struct.unpack_from('<H', buf, 0)[0]
                    attrs, k = {}, 2
                    while k < len(buf):
                        a = buf[k]
                        if a == ATTR_ACTION:
                            attrs['aid'] = struct.unpack_from('<H', buf, k + 1)[0]
                            k += 3
                        elif a == ATTR_UNIQUE:
                            attrs['uid'] = struct.unpack_from('<H', buf, k + 1)[0]
                            k += 3
                        elif a == ATTR_TELE:
                            attrs['tele'] = struct.unpack_from('<HHB', buf, k + 1)
                            k += 6
                        else:
                            problems.append('item %d at %s: unknown attribute %d' % (iid, cur, a))
                            break
                    tiles[cur]['items'].append((iid, attrs))
            except (struct.error, IndexError, TypeError):
                problems.append('node %d is cut short' % kind)
        elif c == 0xFF:
            if not stack:
                problems.append('a node end without a start')
            else:
                stack.pop()
            i += 1
        else:
            problems.append('stray byte at %d' % i)
            break
    if stack:
        problems.append('%d node(s) not closed' % len(stack))
    return header, tiles, problems


def spawn_xml(spawns, boss, npc_list, walk):
    lines = ['<?xml version="1.0"?>', '<spawns>']
    pts = list(spawns) + ([boss] if boss else [])
    for s in pts:
        used = []
        for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            if len(used) >= s['count']:
                break
            if (s['x'] + dx, s['y'] + dy, s['z']) in walk:
                used.append((dx, dy))
        lines.append('\t<spawn centerx="%d" centery="%d" centerz="%d" radius="1">' % (s['x'], s['y'], s['z']))
        for dx, dy in used:
            lines.append('\t\t<monster name="%s" x="%d" y="%d" z="%d" spawntime="%d" />'
                         % (s['monster'], dx, dy, s['z'], s['spawntime']))
        lines.append('\t</spawn>')
    for n in npc_list:
        lines.append('\t<spawn centerx="%d" centery="%d" centerz="%d" radius="1">' % (n['x'], n['y'], n['z']))
        lines.append('\t\t<npc name="%s" x="0" y="0" z="%d" spawntime="60" />' % (n['name'], n['z']))
        lines.append('\t</spawn>')
    lines.append('</spawns>')
    return '\n'.join(lines) + '\n'


# ================================================================================================= compile
def _simple(walk, t):
    """removing tile t keeps its walkable neighbours joined (one group around it)"""
    ring = [(t[0] + dx, t[1] + dy, t[2]) in walk for dx, dy in C.D8]
    groups, seen = 0, set()
    for k in range(8):
        if ring[k] and k not in seen:
            groups += 1
            stack = [k]
            seen.add(k)
            while stack:
                a = stack.pop()
                for b in range(8):
                    if ring[b] and b not in seen and abs(C.D8[a][0] - C.D8[b][0]) <= 1 and abs(C.D8[a][1] - C.D8[b][1]) <= 1:
                        seen.add(b)
                        stack.append(b)
    return groups <= 1


def compile_plan(plan, pair24=None, dark=False, cat=None, dress=True):
    """the compiled area: dict(otbm, spawn_xml, manifest, tiles, walk, ...); raises CompileError with the plan's
    errors when it does not validate"""
    if pair24 is None:
        pair24 = C.pair24_switch()
    cat = cat or C.catalogue(pair24, dark)
    issues = C.validate(plan, cat)
    if C.errors(issues):
        raise CompileError('the plan has errors:\n' + '\n'.join(str(i) for i in C.errors(issues)))
    try:
        lay = C.layout(plan, cat)
    except C.LayoutError as e:
        raise CompileError(str(e))
    area, meta = run_build(plan, cat, lay, pair24, dark)
    biome = C.biome_of(plan, cat)
    ox, oy, oz = origin_of(plan, biome)
    seed = lay['seed']
    rng = random.Random(seed * 131 + 17)
    zones = {z['id']: z for z in plan['zones']}

    def absp(x, y, floor):
        return (ox + x - 1, oy + y - 1, oz + floor - 1)

    zrect = {}
    for zid, r in lay['rects'].items():
        a, b = absp(r[0], r[1], zones[zid]['floor']), absp(r[2], r[3], zones[zid]['floor'])
        zrect[zid] = (a[0], a[1], b[0], b[1], a[2])
    tiles = {}
    walk = set()
    for t in area['tiles']:
        k = (t['x'], t['y'], t['z'])
        tiles[k] = dict(ground=t['ground'], items=[(i, {}) for i in t['items']], flags=0)
        if t['walk']:
            walk.add(k)
    qa = []
    E = lambda m: qa.append(('ERROR', m))
    Wn = lambda m: qa.append(('WARN', m))
    # the generator's own checks (its reachability ignores teleports, the planner checks that below)
    for p in area['problems']:
        if 'cannot be reached' in p or 'links,' in p:
            continue
        E('area generator: ' + p)
    # links: the generator keeps a link only when its three tiles are walkable. stairs: our stair brush (a stairs
    # ground above, stone stairs below) when its tiles allow, else the hole and ladder; hole: the ladder goes
    kit = D.kits()
    brush = kit['brushes']
    link_out = []
    got = {(l['hole'][0], l['hole'][1], l['hole'][2]): l for l in area['links']}
    for l in lay['links']:
        hole = absp(l['x'], l['y'], l['floor'])
        g = got.get(hole)
        c = plan['connections'][l['conn']]
        if not g:
            E('connection %d (%s %s-%s): the generator could not place it at %d,%d,%d'
              % (l['conn'], c['type'], c['from'], c['to'], hole[0], hole[1], hole[2]))
            continue
        ladder, up = tuple(g['ladder']), tuple(g['up'])
        north = (hole[0], hole[1] - 1, hole[2])
        south_below = (ladder[0], ladder[1] + 1, ladder[2])
        if c['type'] == 'stairs' and north in walk and south_below in walk:
            # going down lands south of the stone stairs; the stairs lead up to the tile north of the stairs ground
            tiles[hole]['ground'] = brush['stairs_down_ground']
            tiles[hole]['items'] = [it for it in tiles[hole]['items'] if it[0] != meta['hole']]
            tiles[ladder]['items'] = [it for it in tiles[ladder]['items'] if it[0] != meta['ladder']] + \
                [(brush['stairs_up'], {})]
            link_out.append(dict(conn=l['conn'], type='stairs', brush='stairs', hole=hole, ladder=None, landing=south_below,
                                 up=north, stair=ladder, edges=[(hole, south_below), (ladder, north)]))
        elif c['type'] == 'hole':
            tiles[ladder]['items'] = [it for it in tiles[ladder]['items'] if it[0] != meta['ladder']]
            link_out.append(dict(conn=l['conn'], type='hole', brush='hole', hole=hole, ladder=None, landing=ladder, up=up,
                                 edges=[(hole, ladder)]))
        else:
            if c['type'] == 'stairs':
                Wn('connection %d: no room for the stair brush at %d,%d,%d; a hole and a ladder instead' % ((l['conn'],) + hole))
            link_out.append(dict(conn=l['conn'], type=c['type'], brush='hole and ladder', hole=hole, ladder=ladder,
                                 landing=ladder, up=up, edges=[(hole, ladder), (ladder, up)]))
    arrival = tuple(area['arrival'])
    special = {arrival}
    for l in link_out:
        special.update(t for t in (l['hole'], l['landing'], l['up'], l.get('stair')) if t)
    near_special = lambda t, d=1: any(max(abs(t[0] - s[0]), abs(t[1] - s[1])) <= d and t[2] == s[2] for s in special)

    def zone_cells(zid, avoid=1):
        x1, y1, x2, y2, z = zrect[zid]
        out = [(x, y, z) for y in range(y1, y2 + 1) for x in range(x1, x2 + 1)
               if (x, y, z) in walk and not near_special((x, y, z), avoid)]
        return out

    def path_cells(ends):
        """walkable tiles along the plan path joining the two zones, outside every zone"""
        out = set()
        for f, paths in lay['paths'].items():
            for q in paths:
                if q.get('kind') == 'path' and set(q['zones']) == set(ends):
                    for x, y in C.route_cells(q['points'], q['width'] + {'tunnel': 2, 'wild': 4}.get(q['style'], 0)):
                        a = absp(x, y, f)
                        if a in walk and not near_special(a, 2) and not any(
                                r[4] == a[2] and r[0] <= a[0] <= r[2] and r[1] <= a[1] <= r[3] for r in zrect.values()):
                            out.add(a)
        return sorted(out)

    def zcenter(zid):
        x1, y1, x2, y2, z = zrect[zid]
        return ((x1 + x2) // 2, (y1 + y2) // 2, z)

    def by_center(zid, cells, min_d=0):
        c = zcenter(zid)
        return sorted(cells, key=lambda t: (max(abs(t[0] - c[0]), abs(t[1] - c[1])) < min_d,
                                            (t[0] - c[0]) ** 2 + (t[1] - c[1]) ** 2, t[1], t[0]))

    def pick(zid, what, min_d=2, avoid=1):
        cells = by_center(zid, zone_cells(zid, avoid), min_d)
        if not cells:
            E('%s in zone %s: no free walkable tile' % (what, zid))
            return None
        special.add(cells[0])
        return cells[0]

    def free_neighbour(t):
        for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)):
            n = (t[0] + dx, t[1] + dy, t[2])
            if n in walk and n not in special:
                return n
        return None

    portal = meta['portal']
    teleports = []      # (from tile, to tile)
    tele_out = []
    for i, c in enumerate(plan.get('connections', [])):
        if c['type'] != 'teleport':
            continue
        pa = pick(c['from'], 'teleport %d' % i)
        if not pa:
            continue
        if c.get('two_way', True):
            pb = pick(c['to'], 'return teleport %d' % i)
            if not pb:
                continue
            da, db = free_neighbour(pb), free_neighbour(pa)
            if not da or not db:
                E('teleport %d: no free tile next to a portal' % i)
                continue
            tiles[pa]['items'].append((portal, {'tele': da}))
            tiles[pb]['items'].append((portal, {'tele': db}))
            teleports += [(pa, da), (pb, db)]
            special.update((da, db))
            tele_out.append(dict(conn=i, at=pa, to=da, back_at=pb, back_to=db))
        else:
            cells = by_center(c['to'], zone_cells(c['to']), 1)
            if not cells:
                E('teleport %d: no free tile in %s' % (i, c['to']))
                continue
            da = cells[0]
            special.add(da)
            tiles[pa]['items'].append((portal, {'tele': da}))
            teleports.append((pa, da))
            tele_out.append(dict(conn=i, at=pa, to=da))
    exit_out = None
    if 'exit' in plan:
        ex = plan['exit']
        t = pick(ex['zone'], 'the exit portal', min_d=1)
        if t:
            attrs = {'aid': meta['exitAction']}
            if ex.get('to'):
                attrs['tele'] = (ex['to']['x'], ex['to']['y'], ex['to']['z'])
            tiles[t]['items'].append((portal, attrs))
            exit_out = dict(at=t, to=attrs.get('tele'), aid=attrs['aid'])
    chest_out = []
    chest_aid = C.chest_action(plan)
    for i, ch in enumerate(plan.get('chests', [])):
        cells = [t for t in zone_cells(ch['zone'], 2) if _simple(walk, t)]
        # against a wall or rock edge first, then away from the zone's centre
        wall = lambda t: sum(1 for dx, dy in C.D8 if (t[0] + dx, t[1] + dy, t[2]) not in walk)
        c0 = zcenter(ch['zone'])
        cells.sort(key=lambda t: (-min(wall(t), 3), -((t[0] - c0[0]) ** 2 + (t[1] - c0[1]) ** 2), t[1], t[0]))
        if not cells:
            E('chest %d (%s) in zone %s: no free tile against a wall' % (i, ch['quest'], ch['zone']))
            continue
        t = cells[0]
        tiles[t]['items'].append((meta['chest'], {'aid': chest_aid}))
        walk.discard(t)
        special.add(t)
        chest_out.append(dict(quest=ch['quest'], zone=ch['zone'], at=t, aid=chest_aid, storage=C.chest_storage(ch['quest']),
                              reward=C.resolve_reward(ch.get('reward'))))
    npc_out = []
    for n in plan.get('npcs', []):
        t = pick(n['zone'], 'NPC %s' % n['name'], min_d=1)
        if t:
            npc_out.append(dict(name=C.npcs().get(n['name'].lower(), n['name']), x=t[0], y=t[1], z=t[2], zone=n['zone'],
                                new=bool(n.get('new')), lines=n.get('lines', [])))
    boss_out = None
    if 'boss' in plan:
        b = plan['boss']
        t = pick(b['zone'], 'the boss', min_d=0)
        if t:
            boss_out = dict(x=t[0], y=t[1], z=t[2], monster=C.monsters()[b['monster'].lower()]['name'], count=1,
                            spawntime=b.get('respawn', 3600), title=b.get('title'), zone=b['zone'])
    # protection zones
    pz = set()
    for zid, z in zones.items():
        if z.get('pz'):
            x1, y1, x2, y2, zz = zrect[zid]
            for y in range(y1, y2 + 1):
                for x in range(x1, x2 + 1):
                    if (x, y, zz) in tiles:
                        tiles[(x, y, zz)]['flags'] |= FLAG_PZ
                        pz.add((x, y, zz))
    # spawn points: spread inside their zone, packs on one point
    spawn_out = []
    taken = []
    for i, s in enumerate(plan.get('spawns', [])):
        pack = s.get('pack', 1)
        npts = (s['count'] + pack - 1) // pack
        if 'path' in s:
            zid = 'path %s-%s' % tuple(s['path'])
            cells = path_cells(s['path'])
        else:
            zid = s['zone']
            cells = zone_cells(zid, 2)
        cells = [t for t in cells if t not in pz and
                 not (t[2] == arrival[2] and max(abs(t[0] - arrival[0]), abs(t[1] - arrival[1])) < 4)]
        cells.sort(key=lambda t: (t[1], t[0]))
        rng.shuffle(cells)
        name = C.monsters()[s['monster'].lower()]['name']
        left = s['count']
        if s.get('spread') and cells:
            # even coverage: points about sqrt(tiles / points) apart, the spacing shrinking only when they do not fit
            want = max(2.0, (len(cells) / max(1, npts)) ** 0.5)
            while left > 0 and want >= 2:
                for t in cells:
                    if left <= 0:
                        break
                    if any(t[2] == q[2] and (t[0] - q[0]) ** 2 + (t[1] - q[1]) ** 2 < want * want for q in taken):
                        continue
                    cnt = min(pack, left)
                    taken.append(t)
                    spawn_out.append(dict(x=t[0], y=t[1], z=t[2], monster=name, count=cnt, spawntime=s.get('respawn', 90),
                                          zone=zid, entry=i))
                    left -= cnt
                want -= 0.5
        for mind in (4, 3, 2):
            for t in cells:
                if left <= 0:
                    break
                if any(t[2] == q[2] and (t[0] - q[0]) ** 2 + (t[1] - q[1]) ** 2 < mind * mind for q in taken):
                    continue
                cnt = min(pack, left)
                taken.append(t)
                spawn_out.append(dict(x=t[0], y=t[1], z=t[2], monster=name, count=cnt, spawntime=s.get('respawn', 90),
                                      zone=zid, entry=i))
                left -= cnt
            if left <= 0:
                break
        if left > 0:
            E('spawn %d (%d %s) in zone %s: only room for %d point(s) of %d; make the zone bigger or lower the count'
              % (i, s['count'], name, zid, npts - (left + pack - 1) // pack, npts))
    # ---------------------------------------------------------------------------------------- decoration
    edges = [e for l in link_out for e in l['edges']] + list(teleports)
    sets = meta['sets'] if isinstance(meta['sets'], dict) else {}
    meta['sets'] = sets
    plain = set(meta['allowed']) & set(i for s_ in sets.values() for i in s_)
    wall_kind, wall_ids = {}, set()
    for kind_, ids_ in (meta.get('walls') or {}).items():
        wall_ids.update(ids_)
    for k, t in tiles.items():
        for i, _a in t['items']:
            for kind_, ids_ in (meta.get('walls') or {}).items():
                if i in ids_:
                    wall_kind[k] = kind_
    plain |= wall_ids | {meta['hole'], meta['ladder'], meta['portal'], meta['chest'], brush['stairs_up']}
    protected = set(special) | {(s_['x'], s_['y'], s_['z']) for s_ in spawn_out}
    if boss_out:
        protected.add((boss_out['x'], boss_out['y'], boss_out['z']))
    for a, b in teleports:
        protected.update((a, b))
    # routes kept free of blocking pieces: from the arrival to every zone, spawn and special tile
    targets = set(special) | {b for _a, b in teleports}
    for zid in zones:
        cells = by_center(zid, [t for t in walk if t[2] == zrect[zid][4] and zrect[zid][0] <= t[0] <= zrect[zid][2]
                                and zrect[zid][1] <= t[1] <= zrect[zid][3]])
        if cells:
            targets.add(cells[0])
    keep = D.lanes(walk, arrival, sorted(targets), (), edges)
    for t in list(protected):
        for dx, dy in C.D8:
            keep.add((t[0] + dx, t[1] + dy, t[2]))
    corridor = set()
    for f, paths in lay['paths'].items():
        for q in paths:
            for x, y in C.route_cells(q['points'], q['width'] + {'tunnel': 2, 'wild': 4}.get(q['style'], 0)):
                a = absp(x, y, f)
                if not any(r[4] == a[2] and r[0] <= a[0] <= r[2] and r[1] <= a[1] <= r[3] for r in zrect.values()):
                    corridor.add(a)
    zone_list = [dict(id=zid, rect=zrect[zid], shape=C.zone_shape(z, biome), role=z.get('role', 'hunt'))
                 for zid, z in sorted(zones.items())]
    reach_before = set(C.tile_reach(walk, arrival, (), edges))
    dresser = D.Dresser(tiles, walk, zone_list, meta['kind'], plan['biome'], protected, keep, corridor, plain, wall_kind,
                        random.Random(seed * 977 + 5), plan.get('decoration', 'normal'),
                        plan.get('light') or biome.get('light', 'normal'),
                        boss=(boss_out['x'], boss_out['y'], boss_out['z']) if boss_out else None)
    if dress:
        dresser.run(wall_ids)
        if chest_out:   # nothing else next to a quest chest (owner request 2026-10-27; area_plan_decor.Dresser.clear_around)
            dresser.clear_around([c['at'] for c in chest_out], plain | wall_ids | {meta['chest']})
    reach_after = set(C.tile_reach(walk, arrival, (), edges))
    cut = reach_before - reach_after - dresser.blocked
    if cut:
        E('decoration cuts %d walkable tile(s) off the routes (first %s)' % (len(cut), sorted(cut)[0]))
    for t in protected:
        if t in reach_before and t not in reach_after:
            E('decoration blocks the way to %s' % (t,))
    for t, _i, _g, _c in dresser.placed:
        if t in protected:
            E('decoration on a protected tile %s' % (t,))
    # roofs: a dungeon floor at ground level or above gets a flat roof on the floor over it (the client hides it
    # while a player is inside); floors under another floor of the plan are covered already
    roofs = 0
    if meta['kind'] == 'dungeon':
        for f in range(1, plan['floors'] + 1):
            z = oz + f - 1
            if z > 7 or z == 0:
                continue
            for (x, y, zz) in [k for k in tiles if k[2] == z]:
                above = (x, y, z - 1)
                if above not in tiles:
                    tiles[above] = dict(ground=kit['roof']['ground'][0], items=[], flags=0)
                    roofs += 1
        if roofs:
            Wn('a flat roof of %d tiles covers the floors above ground' % roofs)
    # the view frame: the generator builds only a thin rock rim around the floor (walls in a dungeon), so a player near
    # it would see the black void past it. Every tile within C.VIEW of a walkable tile that has none gets a bare ground
    # (meta['frame']: the theme's rock, the rim's own ground, so no border is wanted; earth behind a dungeon's walls).
    # It is a file of its own (<id>-frame.otbm): the installer lays it only where the map has no tile and no other area
    # or room goes
    fr = meta.get('frame')
    frame = {}
    if not fr:
        E('the generator names no ground for the view frame')
    else:
        if fr['walk']:
            E('the view frame family %s is walkable; it needs a blocking ground' % fr['family'])
        frame = {p: dict(ground=fr['ground'], items=[], flags=0) for p in C.view_frame(walk, tiles)}
    # a thicket biome (meta['thicket']): the rock around the floor and its edge pieces become grass under a tree or a
    # bush on every tile, and the frame grows to the whole rectangle of the plan on each floor, all of it thicket
    th = meta.get('thicket')
    if th and fr:
        rock = fr['family']
        rgrounds = set(meta['families'].get(rock, {}).get('grounds', []))
        rpieces = set()
        for b in meta['borders']:
            if b['over'] == rock:
                rpieces |= set(meta['sets'].get(b['set'], []))
        trng = random.Random(seed * 7 + 3)

        def thick():
            return dict(ground=trng.choice(th['grounds']), items=[(trng.choice(th['items']), {})], flags=0)
        for k in sorted(tiles):
            t = tiles[k]
            if k in walk:
                continue
            if t['ground'] in rgrounds:
                tiles[k] = thick()
            elif any(i in rpieces for i, _a in t['items']):
                t['items'] = [it for it in t['items'] if it[0] not in rpieces] + [(trng.choice(th['items']), {})]
        for f in range(1, plan['floors'] + 1):
            for x in range(plan['size'][0]):
                for y in range(plan['size'][1]):
                    p = absp(x + 1, y + 1, f)
                    if p not in tiles:
                        frame[p] = None
        frame = {p: thick() for p in sorted(frame)}
    # ---------------------------------------------------------------------------------------- OTBM and QA
    spawn_name, house_name = plan['id'] + '-spawn.xml', plan['id'] + '-house.xml'
    data = otbm_bytes(plan['name'], plan['id'], 'seed %d' % seed, tiles, spawn_name, house_name)
    header, back, problems = read_otbm_full(data)
    for p in problems:
        E('OTBM: ' + p)
    frame_data = otbm_bytes(plan['name'], plan['id'], 'view frame, seed %d' % seed, frame, spawn_name, house_name)
    _fh, frame_back, problems = read_otbm_full(frame_data)
    for p in problems:
        E('OTBM (view frame): ' + p)
    if len(frame_back) != len(frame) or set(frame_back) & set(back):
        E('OTBM: the view frame holds %d tiles, %d expected (or overlaps the area)' % (len(frame_back), len(frame)))
    # the checks below run over the area with its frame, as the map holds them
    back_area, back = back, dict(back)
    back.update(frame_back)
    if header != (2, AX.MAP_W, AX.MAP_H, AX.ITEMS_MAJOR, AX.ITEMS_MINOR):
        E('OTBM: header %s' % (header,))
    if len(back_area) != len(tiles):
        E('OTBM: %d tiles written, %d read back' % (len(tiles), len(back_area)))
    allowed = set(meta['allowed']) | {meta['chest'], meta['portal'], meta['hole'], meta['ladder']} | D.all_ids()
    if th:
        allowed |= set(th['grounds']) | set(th['items'])
    if fr:
        allowed.add(fr['ground'])
    unknown = {}
    for k, t in back.items():
        if t['ground'] is None:
            E('OTBM: tile %s has no ground' % (k,))
        for iid in [t['ground']] + [i for i, _a in t['items']]:
            if iid not in allowed:
                unknown[iid] = unknown.get(iid, 0) + 1
        if t['flags'] & ~KNOWN_FLAGS:
            E('OTBM: tile %s has unknown flags %d' % (k, t['flags']))
        for iid, attrs in t['items']:
            if 'tele' in attrs and iid != meta['portal']:
                E('OTBM: a teleport destination on item %d at %s' % (iid, k))
            dest = attrs.get('tele')
            if dest and dest in tiles and dest not in walk:
                E('OTBM: the teleport at %s lands on a tile that is not walkable %s' % (k, dest))
    for iid, n in sorted(unknown.items()):
        E('unknown id %d on %d tile(s): not in our catalogue for this biome' % (iid, n))
    # borders closed: every transition to a higher family with a border set carries one of its pieces; every
    # walkable tile has all 8 neighbours built (no open edge into nothing)
    fam_of = {}
    for f, d in meta['families'].items():
        for g in d['grounds']:
            if g is not None:
                fam_of.setdefault(g, f)
    rules = {}
    for r in meta['borders']:
        rules[(r['over'], r['under'])] = set(meta['sets'][r['set']])
    open_edges, unbordered, transitions = 0, 0, 0
    for k, t in back.items():
        f = fam_of.get(t['ground'])
        if f is None:
            continue
        zf = meta['families'][f]['z']
        ids = {i for i, _a in t['items']}
        wanted = {}
        for dx, dy in C.D8:
            nk = (k[0] + dx, k[1] + dy, k[2])
            nt = back.get(nk)
            if nt is None:
                if k in walk:
                    open_edges += 1
                continue
            if nk in frame_back and ids & wall_ids:
                continue    # a dungeon wall closes the edge to the frame behind it
            g = fam_of.get(nt['ground'])
            if g and g != f and meta['families'][g]['z'] > zf:
                s = rules.get((g, f)) or rules.get((g, '*'))
                if s:
                    wanted[g] = s
        for g, s in wanted.items():
            transitions += 1
            if not ids & s:
                unbordered += 1
    if open_edges:
        E('%d walkable tile edge(s) open into unbuilt tiles' % open_edges)
    void = C.view_frame(walk, back)
    if void:
        E('%d tile(s) in view of a walkable tile have no ground (first %s): the client shows black void there'
          % (len(void), sorted(void)[0]))
    if unbordered:
        E('%d of %d ground transitions have no border piece' % (unbordered, transitions))
    # reachability, entry to every zone and the boss
    dist = C.tile_reach(walk, arrival, (), edges)
    unreached = [t for t in walk if t not in dist and t[2] in {oz + f for f in range(plan['floors'])}]
    zone_steps = {}
    for zid in zones:
        x1, y1, x2, y2, z = zrect[zid]
        ds = [d for (x, y, zz), d in dist.items() if zz == z and x1 <= x <= x2 and y1 <= y <= y2]
        if not ds:
            E('zone %s: no walkable tile of it can be reached from the entry' % zid)
        else:
            zone_steps[zid] = min(ds)
    if unreached:
        Wn('%d walkable tile(s) cannot be reached from the entry (pockets cut off by decoration or pools)' % len(unreached))
    boss_steps = dist.get((boss_out['x'], boss_out['y'], boss_out['z'])) if boss_out else None
    if boss_out and boss_steps is None:
        E('the boss cannot be reached from the entry')
    for zid, z in zones.items():
        if z.get('role') == 'boss':
            x1, y1, x2, y2, zz = zrect[zid]
            n = C.openings(walk, (x1, y1, x2, y2), zz)
            tele_in = sum(1 for a, b in teleports if b[2] == zz and x1 <= b[0] <= x2 and y1 <= b[1] <= y2
                          and not (a[2] == zz and x1 <= a[0] <= x2 and y1 <= a[1] <= y2))
            link_in = sum(1 for l in link_out if l['landing'][2] == zz and x1 <= l['landing'][0] <= x2 and y1 <= l['landing'][1] <= y2)
            if n + tele_in + link_in != 1:
                E('the boss room %s has %d way(s) in on the tiles (%d opening(s), %d teleport(s), %d hole(s)); it needs one'
                  % (zid, n + tele_in + link_in, n, tele_in, link_in))
    for p in lay['paths'].values():
        for q in p:
            if q.get('crosses_boss'):
                E('path %s-%s runs through the boss room; move the zones apart' % q['zones'])
    for s in spawn_out + ([boss_out] if boss_out else []):
        t = (s['x'], s['y'], s['z'])
        if t not in walk:
            E('spawn at %s is not walkable' % (t,))
        if t in pz:
            E('spawn at %s is in a protection zone' % (t,))
    # ---------------------------------------------------------------------------------------- stats
    floors = []
    total_mon = sum(s['count'] for s in spawn_out)
    for f in range(1, plan['floors'] + 1):
        z = oz + f - 1
        wxy = {(x, y) for (x, y, zz) in walk if zz == z}
        hunt = {(x, y) for (x, y, zz) in walk if zz == z and (x, y, zz) not in pz}
        mxy = {}
        for s in spawn_out:
            if s['z'] == z:
                mxy[(s['x'], s['y'])] = mxy.get((s['x'], s['y']), 0) + s['count']
        mons = sum(mxy.values())
        mean, mx, nscr = C.screen_density(wxy, mxy, ox, oy, plan['size'][0], plan['size'][1])
        floors.append(dict(floor=f, z=z, walkable=len(wxy), hunt=len(hunt), monsters=mons,
                           per100=round(100.0 * mons / max(1, len(hunt)), 2), per_screen=round(mean, 2),
                           per_screen_max=mx, screens=nscr))
        if mons and not 1.0 <= 100.0 * mons / max(1, len(hunt)) <= 6.0:
            Wn('floor %d: %.2f monsters per 100 walkable tiles (the guide asks 1.5-5)' % (f, 100.0 * mons / max(1, len(hunt))))
    stats = dict(tiles=len(tiles), walkable=len(walk), monsters=total_mon, spawn_points=len(spawn_out),
                 per100=round(100.0 * total_mon / max(1, len(walk - pz)), 2), floors=floors,
                 entry_to_boss=boss_steps, zone_steps=zone_steps,
                 farthest_zone=max(zone_steps.values()) if zone_steps else None,
                 transitions=transitions, unbordered=unbordered, unknown_ids=len(unknown),
                 decoration=deco_stats(tiles, walk, plain, dresser, oz, plan['floors']), roof_tiles=roofs,
                 checksum=area.get('checksum'), frame_tiles=len(frame))
    if stats['decoration']['spam_share'] > 0.01:
        Wn('%.1f%% of the walkable tiles carry 3 or more decoration items (the guide keeps it under 1%%)'
           % (100 * stats['decoration']['spam_share']))
    manifest = dict(schema=plan.get('schema'), id=plan['id'], name=plan['name'], biome=plan['biome'], theme=meta['theme'],
                    kind=meta['kind'], seed=seed, origin=[ox, oy, oz], size=plan['size'], floors=plan['floors'],
                    pair24=bool(pair24), dark=bool(dark),
                    zones={zid: dict(rect=list(r[:4]), z=r[4], role=zones[zid].get('role', 'hunt'), pz=bool(zones[zid].get('pz')))
                           for zid, r in sorted(zrect.items())},
                    frame=dict(tiles=len(frame), family=fr and fr['family'], ground=fr and fr['ground'], view=list(C.VIEW), file=plan['id'] + '-frame.otbm',
                               thicket=bool(th and fr)),
                    arrival=list(arrival), exit=exit_out, links=link_out, teleports=tele_out, chests=chest_out,
                    npcs=npc_out, boss=boss_out, spawns=len(spawn_out), entry_from_world=plan['entry'].get('from_world'),
                    stats=stats, qa=[dict(level=l, message=m) for l, m in qa],
                    plan_issues=[i.as_dict() for i in issues])
    stubs = {}
    if chest_out:
        stubs['data/scripts/chaos_areaplan/%s_chests.lua' % plan['id']] = chest_script(plan, chest_out, (ox, oy, oz))
    for n in npc_out:
        if n['new']:
            stubs.update(npc_stub(n))
    manifest['stubs'] = sorted(stubs)
    return dict(otbm=data, frame_otbm=frame_data, frame=frame, spawn_xml=spawn_xml(spawn_out, boss_out, npc_out, walk), manifest=manifest, tiles=tiles,
                stubs=stubs, dresser=dresser,
                walk=walk, pz=pz, spawns=spawn_out, boss=boss_out, chests=chest_out, npcs=npc_out, links=link_out,
                teleports=tele_out, exit=exit_out, arrival=arrival, zrect=zrect, origin=(ox, oy, oz), qa=qa,
                stats=stats, plan_issues=issues)


def qa_errors(result):
    return [m for l, m in result['qa'] if l == 'ERROR']


def write_outputs(result, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    pid = result['manifest']['id']
    paths = []
    for name, data, mode in ((pid + '.otbm', result['otbm'], 'wb'), (pid + '-frame.otbm', result['frame_otbm'], 'wb'),
                             (pid + '-spawn.xml', result['spawn_xml'], 'w'),
                             (pid + '.json', json.dumps(result['manifest'], indent=1, sort_keys=True) + '\n', 'w')):
        p = os.path.join(out_dir, name)
        with open(p, mode) as f:
            f.write(data)
        paths.append(p)
    for rel, text in sorted(result.get('stubs', {}).items()):
        p = os.path.join(out_dir, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as f:
            f.write(text)
        paths.append(p)
    return paths


# ================================================================================================= render
class _Map:
    def __init__(self, tiles):
        self.index, self.stacks = {}, []
        for k in sorted(tiles):
            t = tiles[k]
            self.index[k] = len(self.stacks)
            self.stacks.append([t['ground']] + [i for i, _a in t['items']])

    def find(self, x, y, z):
        return self.index.get((x, y, z), -1)

    def stack(self, i):
        return self.stacks[i]


def render_floors(result, out_dir, items_otb, items_xml, dat, spr_path, scale=0.5):
    """OUT/<id>_z<z>.png per floor (client sprites, tools/map/render.py) and OUT/<id>_map.png (minimap colours, all
    floors, with the arrival green, spawns red, boss magenta, chests yellow, teleports and exit blue, holes and ladders
    cyan, protection zones tinted)"""
    sys.path.insert(0, os.path.join(C.ROOT, 'tools', 'map'))
    from PIL import Image, ImageDraw
    from itemdb import ItemDB
    from datspr import Spr
    import render as rd
    os.makedirs(out_dir, exist_ok=True)
    db = ItemDB(items_otb, items_xml, dat)
    spr = Spr(spr_path)
    # the area with its view frame, as the map holds them once installed
    m = _Map({**(result.get('frame') or {}), **result['tiles']})
    pid = result['manifest']['id']
    ox, oy, oz = result['origin']
    w, h = result['manifest']['size']
    floors = result['manifest']['floors']
    out = []
    for f in range(floors):
        z = oz + f
        img, miss = rd.render(m, db, spr, ox, oy, ox + w - 1, oy + h - 1, z)
        if scale != 1:
            img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
        p = os.path.join(out_dir, '%s_z%d.png' % (pid, z))
        img.convert('RGB').save(p, optimize=True)
        out.append((p, miss))
    px = 4
    mm = Image.new('RGB', (w * px * floors + 8 * (floors - 1), h * px), (0, 0, 0))
    d = ImageDraw.Draw(mm)

    def cell(x, y, z):
        return (z - oz) * (w * px + 8) + (x - ox) * px, (y - oy) * px
    for (x, y, z), t in result['tiles'].items():
        col = (0, 0, 0)
        for iid in [t['ground']] + [i for i, _a in t['items']]:
            c = int(db.minimap[iid]) if iid < len(db.minimap) else 0
            if c:
                col = ((c // 36) % 6 * 51, (c // 6) % 6 * 51, c % 6 * 51)
        if (x, y, z) not in result['walk'] and col == (0, 0, 0):
            col = (40, 40, 40)
        if t['flags'] & FLAG_PZ:
            col = (col[0] // 2 + 60, col[1] // 2 + 100, col[2] // 2 + 60)
        x0, y0 = cell(x, y, z)
        d.rectangle([x0, y0, x0 + px - 1, y0 + px - 1], fill=col)

    def mark(t, col, r=2):
        if t:
            x0, y0 = cell(*t)
            d.ellipse([x0 + px // 2 - r, y0 + px // 2 - r, x0 + px // 2 + r, y0 + px // 2 + r], fill=col)
    for s in result['spawns']:
        mark((s['x'], s['y'], s['z']), (230, 30, 30), 2 + s['count'])
    for c in result['chests']:
        mark(c['at'], (250, 220, 40), 4)
    for l in result['links']:
        mark(l['hole'], (40, 230, 255), 4)
        mark(l['landing'], (40, 230, 255), 4)
    for t in result['teleports']:
        mark(t['at'], (60, 110, 255), 4)
        mark(t.get('back_at'), (60, 110, 255), 4)
    if result['exit']:
        mark(result['exit']['at'], (255, 255, 255), 4)
    if result['boss']:
        b = result['boss']
        mark((b['x'], b['y'], b['z']), (230, 40, 230), 7)
    mark(result['arrival'], (40, 230, 40), 5)
    p = os.path.join(out_dir, '%s_map.png' % pid)
    mm.save(p, optimize=True)
    out.append((p, 0))
    return out


# ================================================================================================= stats, stubs
def deco_stats(tiles, walk, plain, dresser, oz, floors):
    """decoration per open tile (walkable or holding a blocking decoration piece) on the plan's floors, the share of
    tiles with 3+ decoration items, and what the dressing pass added per category"""
    zs = {oz + f for f in range(floors)}
    open_ = {t for t in walk if t[2] in zs} | {t for t in dresser.blocked if t[2] in zs}
    n_deco, spam = 0, 0
    for t in open_:
        k = sum(1 for i, _a in tiles[t]['items'] if i not in plain)
        n_deco += k
        if k >= 3:
            spam += 1
    lights = sum(1 for _t, _i, g, _c in dresser.placed if dresser.groups[g]['light'])
    return dict(per_open=round(n_deco / max(1, len(open_)), 3), spam_share=round(spam / max(1, len(open_)), 4),
                added=len(dresser.placed), lights_added=lights,
                lights_per100=round(100.0 * lights / max(1, len(open_)), 2),
                by_category=dict(sorted(dresser.counts.items())), kit=dresser.kit_name)


def _lua_str(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'


def chest_script(plan, chests, origin):
    """the quest chest script of one area (revscript Action on the area's chest action id): each chest gives its
    reward once per character, keyed by the chest's tile; drop it into data/scripts/ (area_planner.py install)"""
    aid = chests[0]['aid']
    rows = []
    for c in chests:
        x, y, z = c['at']
        r = c['reward'] or dict(gold=0, experience=0, message='', items=[])
        items = ', '.join('{id = %d, count = %d}' % (i, n) for i, n, _name in r['items'])
        names = ', '.join('%d %s' % (n, name) for _i, n, name in r['items'])
        x, y, z = x - origin[0], y - origin[1], z - origin[2]
        rows.append('\t["%d:%d:%d"] = {quest = %s, storage = %d, gold = %d, experience = %d, message = %s,\n'
                    '\t\titems = {%s}}, -- %s' % (x, y, z, _lua_str(c['quest']), c['storage'], r['gold'], r['experience'],
                                                   _lua_str(r['message']), items, names or 'no items'))
    return '''-- Quest chests of the planned area "%(name)s" (%(id)s). GENERATED by server/tools/area_planner.py compile from the
-- plan's chests; install with `area_planner.py install` (server/README.md "Area planner"). Action id %(aid)d (block
-- 47960-47999), one player storage per chest (block 7101200-7101299). Each chest gives its reward once per character.
-- The chests are keyed by their offset from ORIGIN, the area's top-left tile of floor 1; `area_planner.py place` writes
-- the ORIGIN of the place it pastes the area to.
local ORIGIN = {x = %(ox)d, y = %(oy)d, z = %(oz)d}
local CHESTS = {
%(rows)s
}

local action = Action()

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local pos = item:getPosition()
	local chest = CHESTS[(pos.x - ORIGIN.x) .. ":" .. (pos.y - ORIGIN.y) .. ":" .. (pos.z - ORIGIN.z)]
	if not chest then
		return false
	end
	if player:getStorageValue(chest.storage) > 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "The chest is empty.")
		return true
	end
	local weight = 0
	for _, it in ipairs(chest.items) do
		weight = weight + ItemType(it.id):getWeight(it.count)
	end
	if weight > player:getFreeCapacity() then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "The reward is too heavy for you.")
		return true
	end
	for _, it in ipairs(chest.items) do
		player:addItem(it.id, it.count)
	end
	if chest.gold > 0 then
		player:addMoney(chest.gold)
	end
	if chest.experience > 0 then
		player:addExperience(chest.experience, true)
	end
	player:setStorageValue(chest.storage, 1)
	player:sendTextMessage(MESSAGE_INFO_DESCR, chest.message ~= "" and chest.message or "You found a reward.")
	return true
end

action:aid(%(aid)d)
action:register()
''' % dict(name=plan['name'], id=plan['id'], aid=aid, rows='\n'.join(rows), ox=origin[0], oy=origin[1], oz=origin[2])


def npc_file(name):
    return ''.join(c if c.isalnum() else '_' for c in name.lower()).strip('_')


def npc_stub(n):
    """a new NPC: data/npc/<Name>.xml and data/npc/scripts/<name>.lua (greeting and simple answers)"""
    lines = list(n.get('lines') or [])
    greet = lines[0] if lines else 'Greetings, |PLAYERNAME|.'
    fname = npc_file(n['name'])
    xml = '''<?xml version="1.0" encoding="UTF-8"?>
<!-- %(name)s: an NPC of a planned area. GENERATED by server/tools/area_planner.py compile; edit the look and the
     answers, then install with `area_planner.py install` (server/README.md "Area planner"). -->
<npc name="%(name)s" script="%(file)s.lua" walkinterval="0" floorchange="0">
	<health now="100" max="100" />
	<look type="128" head="78" body="69" legs="58" feet="76" addons="0" />
	<parameters>
		<parameter key="message_greet" value="%(greet)s" />
		<parameter key="message_farewell" value="Farewell, |PLAYERNAME|." />
		<parameter key="message_walkaway" value="Farewell." />
	</parameters>
</npc>
''' % dict(name=n['name'], file=fname, greet=greet.replace('"', "'").replace('&', 'and'))
    answers = '\n'.join('keywordHandler:addKeyword({%s}, StdModule.say, {npcHandler = npcHandler, text = %s})'
                        % (_lua_str(l.split(':', 1)[0].strip().lower()), _lua_str(l.split(':', 1)[1].strip()))
                        for l in lines[1:] if ':' in l)
    lua = '''-- %(name)s: an NPC of a planned area. GENERATED by server/tools/area_planner.py compile. Lines of the plan written
-- "keyword: answer" become answers; the first line is the greeting (the XML).
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

%(answers)s
npcHandler:addModule(FocusModule:new())
''' % dict(name=n['name'], answers=answers)
    return {'data/npc/%s.xml' % n['name']: xml, 'data/npc/scripts/%s.lua' % fname: lua}
