#!/usr/bin/env python3
"""Install the planned content hunts into a base server's world map, with their way in from the teleport room.

usage: python3 -I server/tools/install_content_areas.py DATA_DIR [--dry-run] [--only ID,...] [--no-room]
                                                        [--plans DIR] [--config FILE] [--map FILE]

DATA_DIR is the server's data folder. Read at run time, never hard-coded: every plan of server/tools/areaplan/plans/
(size, origin, arrival) and server/data/scripts/chaos/hunt_teleports_config.lua (the room, the order of the plans and
their display monsters; read through tools/hunt_teleports_dump.lua with luajit, or $LUA).

Steps (server/README.md "Hunt teleports"; docs/MAP_GUIDE.md "Content plans"):
  compile  every plan with `area_planner.py compile` into a temporary folder (at its own origin)
  room     the teleport room of the config (Cinderhold, floor 6) grows on both sides: the alcove module columns are
           copied past the old end and the end (with its temple teleport and destination) moves out by the module
           width per module. Only the old end's tiles are replaced; every other new tile must land where the map has
           no tile, else nothing is written. The copies carry no teleport (hunt_teleports.lua puts ours on at startup)
  areas    each plan's tiles pasted at its origin; refused when one lands on a tile the map has
  spawns   each plan's spawn blocks (marked chaoscontent="ID") and two display monsters per teleport in the closed
           cells beside its counter, like the room's own (marked chaoshunt="ID"; blocks of a slot no longer used go)
  chests   the plan's chest script into data/scripts/chaos_areaplan (`area_planner.py install`)
  places   data/lib/chaos_hunt_places.lua: per placed plan its teleport, sign, arrival, exit, level band and display
           monster (read by data/scripts/chaos/hunt_teleports.lua)
Slots go to the config's `plans` in order, then to the plans the config does not list (by band floor, display monster
their most frequent one; the log names them). More plans than slots: refused (raise `modules`).
Idempotent: a placed plan (every tile there, the same items) and a grown room are recognised and left alone; a plan
that changed since it was placed (other tiles) is refused with the reason (restore the map from <map>.otbm.bak, which
is written before the first change when missing, and run the whole install again). The map is written through
<map>.otbm.tmp and checked (tile count) before it replaces the old one.
--dry-run computes and checks everything and writes nothing. --only places only these plans (the room and the places
file still cover every placed plan). --no-room leaves the room alone (no slots: no teleports, no display spawns).
Exit 0 on success, 1 on a refusal.
Python 3 standard library and numpy (tools/map/otbm.py reads the world).
"""
import json, os, re, shutil, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

PLANS_DIR = os.path.join(HERE, 'areaplan', 'plans')
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'hunt_teleports_config.lua')
PLACES_REL = os.path.join('lib', 'chaos_hunt_places.lua')

ATTR_TILE_FLAGS, ATTR_ITEM, ATTR_ACTION, ATTR_TELE = 3, 9, 4, 8
T_AREA, T_TILE, T_HOUSETILE = 4, 5, 14


class InstallError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ inputs
def load_config(path=CONFIG):
    lua = os.environ.get('LUA') or shutil.which('luajit') or shutil.which('lua5.3') or 'luajit'
    proc = subprocess.run([lua, os.path.join(HERE, 'hunt_teleports_dump.lua'), path], cwd=SERVER,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise InstallError('cannot read %s: %s' % (path, proc.stderr.decode('utf-8', 'replace').strip()))
    return json.loads(proc.stdout.decode('utf-8'))


def plan_files(plans_dir=PLANS_DIR):
    out = {}
    for name in sorted(os.listdir(plans_dir)):
        if name.endswith('.json'):
            plan = json.load(open(os.path.join(plans_dir, name), encoding='utf-8'))
            out[plan['id']] = (os.path.join(plans_dir, name), plan)
    return out


def compile_plan(path, out_dir):
    proc = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'area_planner.py'), 'compile', path, out_dir],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    if proc.returncode != 0:
        raise InstallError('compile %s failed:\n%s' % (os.path.basename(path), proc.stdout.strip()[-2000:]))


def read_area(out_dir, pid):
    import area_plan_compile as PC
    man = json.load(open(os.path.join(out_dir, pid + '.json'), encoding='utf-8'))
    _h, tiles, problems = PC.read_otbm_full(open(os.path.join(out_dir, pid + '.otbm'), 'rb').read())
    if problems:
        raise InstallError('%s: the compiled area is not a planner OTBM: %s' % (pid, problems[0]))
    return tiles, man


# ------------------------------------------------------------------------------------------------ world helpers
class World:
    """the few reads we need from tools/map/otbm.py's Map (or a stand-in in the tests)"""

    def __init__(self, m, teleports=None):
        self.m = m
        self.tele = teleports or {}  # (x, y, z) -> destination of the tile's teleport item

    def has(self, p):
        return self.m.find(*p) >= 0

    def stack(self, p):
        i = self.m.find(*p)
        return None if i < 0 else [int(a) for a in self.m.stack(i)]

    def flags(self, p):
        i = self.m.find(*p)
        return 0 if i < 0 else int(self.m.tiles['flags'][i])

    def house(self, p):
        i = self.m.find(*p)
        return 0 if i < 0 else int(self.m.tiles['house'][i])

    def count(self):
        return len(self.m.tiles['x'])


def load_world(path, portal):
    import otbm
    m = otbm.load_otbm(path)
    tele = {}
    for ti, _iid, d in otbm.teleports(m, [portal]):
        tele[(int(m.tiles['x'][ti]), int(m.tiles['y'][ti]), int(m.tiles['z'][ti]))] = tuple(d)
    return World(m, tele)


def stack_of(tile):
    """a tile of ours ({'ground', 'items'}) as the id list otbm.py gives for a map tile"""
    return ([tile['ground']] if tile.get('ground') else []) + [iid for iid, _a in tile['items']]


# ------------------------------------------------------------------------------------------------ the room
def room_layout(world, room, portal):
    """the grown room: {'tiles': {pos: tile}, 'module': set(pos), 'caps': set(pos) (new place of the ends),
    'old': set(pos) (tiles of the old ends, replaced), 'slots': [...]}"""
    z = room['z']
    r0, r1 = room['rows']
    tiles, module, caps, old, cols = {}, set(), set(), set(), []
    for side in ('east', 'west'):
        s = room.get(side)
        if not s or not s.get('modules'):
            continue
        a, b = s['module']
        c0, c1 = s['cap']
        per = b - a + 1
        n = s['modules'] * per
        if side == 'east':
            new = list(range(c0, c0 + n))
            src = lambda x: a + (x - c0) % per
            shift = n
        else:
            new = list(range(c1, c1 - n, -1))  # from the stairs outward
            src = lambda x: b - (c1 - x) % per
            shift = -n
        for x in new:
            sx = src(x)
            for y in range(r0, r1 + 1):
                st = world.stack((sx, y, z))
                if st is None:
                    continue
                if world.house((sx, y, z)):
                    raise InstallError('room: the module tile %d,%d,%d belongs to a house' % (sx, y, z))
                items = [(i, {}) for i in st if i != portal]
                tiles[(x, y, z)] = dict(ground=None, items=items, flags=world.flags((sx, y, z)))
                module.add((x, y, z))
            cols.append((side, x, sx))
        for x in range(c0, c1 + 1):
            for y in range(r0, r1 + 1):
                p = (x, y, z)
                st = world.stack(p)
                if st is None:
                    continue
                old.add(p)
                items = []
                for i in st:
                    attrs = {}
                    if i == portal and p in world.tele:
                        attrs['tele'] = world.tele[p]
                    items.append((i, attrs))
                q = (x + shift, y, z)
                tiles[q] = dict(ground=None, items=items, flags=world.flags(p))
                caps.add(q)
    # the slots: new columns whose source column has a teleport on the north teleport row
    tn, ts = room['teleportRows']
    slots = []
    for side, x, sx in cols:
        st = world.stack((sx, tn, z))
        if not st or portal not in st:
            continue
        for row, cell, sign in ((tn, room['cellRows'][0], room['signRows'][0]), (ts, room['cellRows'][1], room['signRows'][1])):
            cells = []
            for cx in (x - 1, x + 1):
                t = tiles.get((cx, cell, z))
                if t and not t['flags'] & 1 and len(t['items']) == 1:
                    cells.append((cx, cell, z))
            slots.append(dict(teleport=(x, row, z), sign=(x, sign, z), cells=cells, side=side))
    return dict(tiles=tiles, module=module, caps=caps, old=old, slots=slots)


def room_state(world, lay):
    """'done' (grown already), 'todo' (can grow), or raises with the reason"""
    if not lay['tiles']:
        return 'done'
    same = [p for p in lay['module'] if world.stack(p) == stack_of(lay['tiles'][p])]
    if len(same) == len(lay['module']):
        return 'done'  # the copies stand where the old ends were: grown (the ends were moved then)
    taken = [p for p in lay['tiles'] if world.has(p) and p not in lay['old']]
    if taken:
        raise InstallError('room: %d target tile(s) are taken (first %d,%d,%d) and the room is not the one this '
                           'config grows from; nothing written' % ((len(taken),) + taken[0]))
    if not lay['old']:
        raise InstallError('room: no end (cap) tiles where the config says')
    for p in lay['old']:
        if world.house(p):
            raise InstallError('room: the end tile %d,%d,%d belongs to a house' % p)
    return 'todo'


def top_monster(plan):
    """the plan's most frequent monster (by spawn count; ties by name)"""
    count = {}
    for s in plan.get('spawns', []):
        count[s['monster']] = count.get(s['monster'], 0) + s.get('count', 1)
    return sorted(count.items(), key=lambda kv: (-kv[1], kv[0]))[0][0] if count else None


def plan_order(cfg, plans):
    """the config's plans that have a plan file, then the other plans by band floor, each {id, monster, ...}"""
    listed = [dict(p) for p in cfg.get('plans', []) if p['id'] in plans]
    have = {p['id'] for p in listed}
    rest = sorted((pid for pid in plans if pid not in have), key=lambda pid: (plans[pid][1]['level'][0], pid))
    return listed + [dict(id=pid, monster=top_monster(plans[pid][1]), auto=True) for pid in rest]


def assign_slots(order, slots, placed):
    """{plan id: slot} for the placed plans, in `order` (pinned `slot` first)"""
    out, used = {}, set()
    plans = [p for p in order if p['id'] in placed]
    for p in plans:
        if p.get('slot'):
            k = p['slot'] - 1
            if not 0 <= k < len(slots) or k in used:
                raise InstallError('plan %s: slot %s is not free or does not exist (%d slots)' % (p['id'], p['slot'], len(slots)))
            out[p['id']] = slots[k]
            used.add(k)
    free = [k for k in range(len(slots)) if k not in used]
    for p in plans:
        if p['id'] in out:
            continue
        if not free:
            raise InstallError('the room has %d slots, too few for the %d plans: raise `modules` in the config'
                               % (len(slots), len(plans)))
        k = free.pop(0)
        out[p['id']] = slots[k]
        used.add(k)
    return out


# ------------------------------------------------------------------------------------------------ the areas
def area_state(world, pid, tiles):
    have = [p for p in tiles if world.has(p)]
    if not have:
        return 'todo'
    if len(have) == len(tiles):
        diff = [p for p in tiles if world.stack(p) != stack_of(tiles[p])]
        if not diff:
            return 'done'
        raise InstallError('%s: placed before, but %d tile(s) differ from the plan now (first %d,%d,%d): the plan changed; '
                           'restore the map from <map>.otbm.bak and install again' % ((pid, len(diff)) + diff[0]))
    raise InstallError('%s: %d of its %d tiles land on tiles the map has (first %d,%d,%d); move its origin'
                       % ((pid, len(have), len(tiles)) + have[0]))


# ------------------------------------------------------------------------------------------------ OTBM writing
def _esc(b):
    out = bytearray()
    for c in b:
        if c in (0xFD, 0xFE, 0xFF):
            out.append(0xFD)
        out.append(c)
    return bytes(out)


def tile_nodes(tiles):
    """the escaped bytes of tile area nodes holding these tiles (ground inline when given, items as nodes)"""
    out = bytearray()
    keys = sorted(tiles, key=lambda t: (t[2], t[1] & 0xFF00, t[0] & 0xFF00, t[1], t[0]))
    cur = None
    for k in keys:
        t = tiles[k]
        akey = (k[0] & 0xFF00, k[1] & 0xFF00, k[2])
        if akey != cur:
            if cur is not None:
                out += b'\xFF'
            cur = akey
            out += b'\xFE' + _esc(bytes([T_AREA]) + struct.pack('<HHB', *akey))
        p = bytes([T_TILE, k[0] & 0xFF, k[1] & 0xFF])
        if t.get('flags'):
            p += bytes([ATTR_TILE_FLAGS]) + struct.pack('<I', t['flags'])
        if t.get('ground'):
            p += bytes([ATTR_ITEM]) + struct.pack('<H', t['ground'])
        out += b'\xFE' + _esc(p)
        for iid, attrs in t['items']:
            q = bytes([6]) + struct.pack('<H', iid)
            if attrs.get('aid'):
                q += bytes([ATTR_ACTION]) + struct.pack('<H', attrs['aid'])
            if attrs.get('uid'):
                q += bytes([5]) + struct.pack('<H', attrs['uid'])
            if attrs.get('tele'):
                q += bytes([ATTR_TELE]) + struct.pack('<HHB', *attrs['tele'])
            out += b'\xFE' + _esc(q) + b'\xFF'
        out += b'\xFF'
    if cur is not None:
        out += b'\xFF'
    return bytes(out)


def _unesc_head(data, i, n):
    """the first n unescaped payload bytes from offset i"""
    out = bytearray()
    while len(out) < n and i < len(data):
        c = data[i]
        if c == 0xFD:
            out.append(data[i + 1])
            i += 2
        elif c in (0xFE, 0xFF):
            break
        else:
            out.append(c)
            i += 1
    return bytes(out)


def tile_ranges(data, positions):
    """{pos: (start, end)} raw offsets (FE .. FF inclusive) of the tile nodes at these positions"""
    import numpy as np
    import area_plan_place as PL
    want = set(positions)
    if not want:
        return {}
    bases = {(x & 0xFF00, y & 0xFF00, z) for x, y, z in want}
    a = np.frombuffer(data, np.uint8)
    mk, is_start, depth = PL._markers(a)
    areas = np.flatnonzero(is_start & (depth == 3))
    out = {}
    for k in areas:
        off = int(mk[k])
        if a[off + 1] != T_AREA:
            continue
        head = _unesc_head(data, off + 2, 5)
        if len(head) < 5 or struct.unpack('<HHB', head) not in bases:
            continue
        bx, by, bz = struct.unpack('<HHB', head)
        j = k + 1
        while j < len(mk) and depth[j] >= 3:
            if is_start[j] and depth[j] == 4:
                s = int(mk[j])
                kind = a[s + 1]
                h = _unesc_head(data, s + 2, 2)
                pos = (bx + h[0], by + h[1], bz)
                e = j + 1
                while not (not is_start[e] and depth[e] == 3):
                    e += 1
                if pos in want:
                    if kind == T_HOUSETILE:
                        raise InstallError('the tile %d,%d,%d is a house tile; not replaced' % pos)
                    out[pos] = (s, int(mk[e]))
                j = e + 1
            else:
                j += 1
    missing = want - set(out)
    if missing:
        raise InstallError('%d tile(s) to replace were not found in the map file (first %s)' % (len(missing), sorted(missing)[0]))
    return out


def write_map(world_path, out_path, remove, new_tiles):
    """the world with the tiles at `remove` cut out and `new_tiles` added (before the towns node)"""
    import area_plan_place as PL
    data = open(world_path, 'rb').read()
    if data[:2] == b'\x1f\x8b':
        raise InstallError('the world map is compressed; unpack it first')
    cuts = sorted(tile_ranges(data, remove).values())
    k = PL.insertion_point(data)
    for s, e in cuts:
        if s <= k <= e:
            raise InstallError('internal: the insertion point is inside a removed tile')
    with open(out_path, 'wb') as f:
        pos = 0
        pieces = cuts + [(k, k - 1)]
        pieces.sort()
        for s, e in pieces:
            f.write(data[pos:s])
            if e < s:  # the insertion point
                f.write(tile_nodes(new_tiles))
                pos = s
            else:
                pos = e + 1
        f.write(data[pos:])
    return len(cuts)


# ------------------------------------------------------------------------------------------------ spawns
SPAWN_RE = re.compile(r'\t<spawn\b[^>]*>.*?</spawn>\n', re.S)


def spawn_center(block):
    m = re.search(r'centerx="(\d+)" centery="(\d+)" centerz="(\d+)"', block)
    return tuple(int(v) for v in m.groups()) if m else None


def update_spawns(text, plan_blocks, displays, spawntime):
    """the spawn file with the plans' blocks (once each) and exactly the wanted display blocks; returns (text, notes)"""
    notes = []
    blocks = SPAWN_RE.findall(text)
    want = {}
    for pid, (monster, cells) in displays.items():
        for c in cells:
            want[c] = (pid, monster)
    # display blocks no longer wanted (slot moved, plan dropped) go
    for b in blocks:
        m = re.search(r'chaoshunt="([^"]+)"', b)
        if m and want.get(spawn_center(b), (None,))[0] != m.group(1):
            text = text.replace(b, '', 1)
            notes.append('display spawn of %s at %s removed' % (m.group(1), spawn_center(b)))
    centers = {}
    for b in SPAWN_RE.findall(text):
        c = spawn_center(b)
        if c:
            centers.setdefault(c, []).append(b)
    add = []
    for c in sorted(want):
        pid, monster = want[c]
        have = [b for b in centers.get(c, []) if 'chaoshunt="%s"' % pid in b]
        if have:
            if 'name="%s"' % monster in have[0]:
                continue
            text = text.replace(have[0], '', 1)
        elif centers.get(c):
            notes.append('display cell %s already has a spawn (not ours); skipped' % (c,))
            continue
        add.append('\t<spawn centerx="%d" centery="%d" centerz="%d" radius="1" chaoshunt="%s">\n'
                   '\t\t<monster name="%s" x="0" y="0" z="%d" spawntime="%d" />\n\t</spawn>\n'
                   % (c[0], c[1], c[2], pid, monster, c[2], spawntime))
    if add:
        notes.append('%d display spawn(s) added' % len(add))
    for pid, xml in plan_blocks:
        if 'chaoscontent="%s"' % pid in text:
            continue
        for b in SPAWN_RE.findall(xml):
            add.append(re.sub(r'^(\t<spawn\b[^>]*?)>', r'\1 chaoscontent="%s">' % pid, b, count=1))
        notes.append('%s: %d spawn block(s) added' % (pid, len(SPAWN_RE.findall(xml))))
    if add:
        cut = text.rfind('</spawns>')
        if cut < 0:
            raise InstallError('the spawn file has no </spawns>')
        text = text[:cut] + ''.join(add) + text[cut:]
    return text, notes


# ------------------------------------------------------------------------------------------------ places file
def places_lua(back, entries):
    def q(s):
        return 'nil' if s is None else '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')

    def pos(p):
        if isinstance(p, dict):
            p = (p['x'], p['y'], p['z'])
        return '{x = %d, y = %d, z = %d}' % tuple(p) if p else 'nil'
    lines = ['-- Written by server/tools/install_content_areas.py; do not edit (run the install again).',
             '-- The placed content hunts and their teleports (data/scripts/chaos/hunt_teleports.lua).',
             'return {', '\tback = %s,' % pos(back), '\tplaces = {']
    for e in entries:
        lines.append('\t\t{id = "%s", name = %s, level = {%d, %d}, teleport = %s, sign = %s, arrival = %s, exit = %s, '
                     'monster = %s},' % (e['id'], q(e['name']), e['level'][0], e['level'][1], pos(e['teleport']),
                                         pos(e['sign']), pos(e['arrival']), pos(e['exit']), q(e.get('monster'))))
    lines += ['\t}', '}', '']
    return '\n'.join(lines)


# ------------------------------------------------------------------------------------------------ run
def spawn_path(map_path):
    p = map_path[:-5] + '-spawn.xml'
    return p if os.path.isfile(p) else None


def run(data_dir, dry=False, only=None, room_on=True, plans_dir=PLANS_DIR, config=CONFIG, map_path=None,
        compiled=None, world=None, log=print):
    """compiled: {id: out_dir} already compiled (tests); world: a World (tests). Returns a summary dict."""
    import area_plan_place as PL
    cfg = load_config(config) if isinstance(config, str) else config
    portal = cfg['items']['portal']
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise InstallError('no world map in %s/world' % data_dir)
    plans = plan_files(plans_dir)
    unknown = [p['id'] for p in cfg.get('plans', []) if p['id'] not in plans]
    for pid in unknown:
        log('config plan %s has no plan file; skipped' % pid)
    order = plan_order(cfg, plans)
    for p in order:
        if p.get('auto'):
            log('%s: not in the hunt teleports config: teleport after the listed plans, display monster %s (check its '
                'look in the client; list the plan in the config to choose)' % (p['id'], p['monster']))
    if only:
        bad = [o for o in only if o not in plans]
        if bad:
            raise InstallError('unknown plan(s) for --only: %s' % ', '.join(bad))
    tmp = tempfile.mkdtemp(prefix='chaos_content_')
    try:
        areas = {}
        for pid, (path, plan) in plans.items():
            out = (compiled or {}).get(pid)
            if not out:
                out = os.path.join(tmp, pid)
                compile_plan(path, out)
            tiles, man = read_area(out, pid)
            areas[pid] = dict(out=out, tiles=tiles, man=man, plan=plan)
        if world is None:
            log('reading %s ...' % map_path)
            world = load_world(map_path, portal)
        # the room
        lay = room_layout(world, cfg['room'], portal) if room_on else dict(tiles={}, module=set(), caps=set(), old=set(), slots=[])
        rstate = room_state(world, lay)
        log('room: %s (%d new tiles, %d replaced, %d teleport slots)' % (
            'grown already' if rstate == 'done' else 'grows', len(set(lay['tiles']) - lay['old']) if rstate == 'todo' else 0,
            len(lay['old'] & set(lay['tiles'])) if rstate == 'todo' else 0, len(lay['slots'])))
        # the areas
        state = {}
        for pid, a in areas.items():
            st = area_state(world, pid, a['tiles'])
            clash = set(a['tiles']) & set(lay['tiles'])
            if clash:
                raise InstallError('%s overlaps the room (%d tiles)' % (pid, len(clash)))
            if st == 'todo' and only and pid not in only:
                st = 'skipped'
            state[pid] = st
            log('%s: %s (%d tiles at %s)' % (pid, {'done': 'placed already', 'todo': 'to place', 'skipped': 'not placed (--only)'}[st],
                                             len(a['tiles']), tuple(a['man']['origin'])))
        placed = {pid for pid, st in state.items() if st in ('done', 'todo')}
        slots = assign_slots(order, lay['slots'], placed) if lay['slots'] else {}
        if lay['slots']:
            log('room: %d of %d teleport slots used' % (len(slots), len(lay['slots'])))
        # the aid block must be free on the map
        if rstate == 'todo' or any(st == 'todo' for st in state.values()):
            import gen_poi
            used = gen_poi.find_action_items(open(map_path, 'rb').read(), [cfg['aid']])
            if used:
                raise InstallError('action id %d is on the map already (%s); pick another in the config' % (cfg['aid'], used[0][1]))
        # the map
        new_tiles = {}
        if rstate == 'todo':
            new_tiles.update(lay['tiles'])
        for pid, st in state.items():
            if st == 'todo':
                new_tiles.update(areas[pid]['tiles'])
        remove = sorted(lay['old']) if rstate == 'todo' else []
        summary = dict(room=rstate, areas=state, slots={k: v['teleport'] for k, v in slots.items()}, new_tiles=len(new_tiles),
                       removed=len(remove))
        if new_tiles and not dry:
            bak = map_path + '.bak'
            if not os.path.exists(bak):
                shutil.copyfile(map_path, bak)
                log('backup %s' % bak)
            tmp_map = map_path + '.tmp'
            write_map(map_path, tmp_map, remove, new_tiles)
            import otbm
            check = otbm.load_otbm(tmp_map)
            expect = world.count() - len(remove) + len(new_tiles)
            if len(check.tiles['x']) != expect:
                os.remove(tmp_map)
                raise InstallError('the new map holds %d tiles, %d expected; nothing replaced' % (len(check.tiles['x']), expect))
            os.replace(tmp_map, map_path)
            log('map: %d tile(s) added, %d replaced' % (len(new_tiles), len(remove)))
        elif new_tiles:
            log('map: would add %d tile(s), replace %d' % (len(new_tiles), len(remove)))
        # spawns
        sp = spawn_path(map_path)
        if sp:
            text = open(sp, encoding='latin-1').read()
            plan_blocks = [(pid, open(os.path.join(areas[pid]['out'], pid + '-spawn.xml'), encoding='latin-1').read())
                           for pid in sorted(placed)]
            mons = {p['id']: p['monster'] for p in order}
            displays = {pid: (mons[pid], s['cells']) for pid, s in slots.items() if mons.get(pid)}
            new, notes = update_spawns(text, plan_blocks, displays, cfg.get('displaySpawntime', 120))
            for n in notes:
                log('spawns: ' + n)
            if new != text:
                if not dry:
                    open(sp, 'w', encoding='latin-1').write(new)
                log('spawns: %s %s' % ('would write' if dry else 'written', sp))
        else:
            log('spawns: no spawn file next to the map; skipped')
        # chest scripts
        server_dir = os.path.dirname(os.path.abspath(data_dir))
        for pid in sorted(placed):
            PL.install(areas[pid]['out'], server_dir, dry_run=dry, log=lambda s: log('chests: ' + s))
        # places file
        entries = []
        for p in order:
            pid = p['id']
            if pid not in slots:
                continue
            a = areas[pid]
            ex = a['man'].get('exit') or {}
            entries.append(dict(id=pid, name=a['man'].get('name') or a['plan'].get('name') or pid, level=a['plan']['level'],
                                teleport=slots[pid]['teleport'], sign=slots[pid]['sign'], arrival=a['man']['arrival'],
                                exit=ex.get('at'), monster=p.get('monster')))
        text = places_lua(cfg['room']['back'], entries)
        dst = os.path.join(data_dir, PLACES_REL)
        old = open(dst, encoding='utf-8').read() if os.path.isfile(dst) else None
        if old != text:
            if not dry:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                open(dst, 'w', encoding='utf-8').write(text)
            log('places: %s %s (%d teleport(s))' % ('would write' if dry else 'written', dst, len(entries)))
        for e in entries:
            log('teleport %s at %s -> %s (level %d+)' % (e['id'], e['teleport'], tuple(e['arrival']), e['level'][0]))
        summary['places'] = entries
        return summary
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    args, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--dry-run', '--no-room'):
            args[a] = True
        elif a in ('--only', '--plans', '--config', '--map'):
            if i + 1 >= len(argv):
                sys.exit('%s needs a value' % a)
            args[a] = argv[i + 1]
            i += 1
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            sys.exit('unknown option %s' % a)
        else:
            pos.append(a)
        i += 1
    if len(pos) != 1:
        print(__doc__)
        return 2
    only = [s.strip() for s in args['--only'].split(',') if s.strip()] if args.get('--only') else None
    try:
        run(pos[0], dry=bool(args.get('--dry-run')), only=only, room_on=not args.get('--no-room'),
            plans_dir=args.get('--plans', PLANS_DIR), config=args.get('--config', CONFIG), map_path=args.get('--map'))
    except InstallError as e:
        print('refused: %s' % e)
        return 1
    print('done%s' % (' (dry run: nothing written)' if args.get('--dry-run') else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
