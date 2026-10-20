#!/usr/bin/env python3
"""Install the planned content hunts into a base server's world map, with their way in from the teleport room.

usage: python3 -I server/tools/install_content_areas.py DATA_DIR [--dry-run] [--only ID,...] [--no-room]
                                                        [--plans DIR] [--config FILE] [--map FILE] [--no-fixed]
                                                        [--remove-hall]

DATA_DIR is the server's data folder. Read at run time, never hard-coded: every plan of server/tools/areaplan/plans/
(size, origin, arrival) and server/data/scripts/chaos/hunt_teleports_config.lua (the room, the order of the plans and
their display monsters; read through tools/hunt_teleports_dump.lua with luajit, or $LUA).
Fixed areas: every plan of server/tools/areaplan/chronicle/ (the Ashen Chronicle's chapter areas and the Capital
Memorial's plaza) and of server/tools/areaplan/rooms/ (the Idle Hall) is placed the same way at its own `origin`, with
its spawns and chest script, but gets no teleport and no line in the places file: its way in is a runtime portal of its
own (chronicle_config.lua `areas` gate, memorial_config.lua `plaza.portal`; tools/chronicle_areas_test.py checks that
their `at` is the plan's origin) or, for the Idle Hall, idlehall.lua's move (tools/idle_hall_test.py).
--no-fixed leaves them out.

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
Slots go to the plans by level band ascending (floor, ceiling, id), along the corridor from west to east (north
teleport before south in each column); the config's `plans` gives each its display monster (a plan it does not list
gets its most frequent one; the log names it). More plans than slots: refused (raise `modules`).
Hall order (tools/hall_order.py, server/README.md "Hall order"): with tools/hall_hunts.csv present and the config's
`hall.enabled`, every hunt slot of the hall (the base teleports' places on floors 7, 6 and 5 and the wings' slots)
gets a hunt by band, the base server's and the planned ones together: the entry floor first, along the corridor from
west to east, then each floor up. The base teleport tiles are rewritten (a base hunt's teleport with its destination,
or none where a planned hunt's teleport goes at startup), the display spawns follow their hunts (the base server's
unmarked display blocks of the hall's cells are taken over) and the places file lists the base hunts and the floors'
bands. --remove-hall puts every base hunt back where the CSV says it stood (the planned hunts in the wings again).
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
FIXED_DIRS = (os.path.join(HERE, 'areaplan', 'chronicle'), os.path.join(HERE, 'areaplan', 'rooms'))
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


def load_world(path, portal, extra=()):
    """the map and its teleports: {pos: destination} of the `portal` item and of the `extra` teleport items (the base
    quests' own teleport items: the hall order moves them too)"""
    import otbm
    m = otbm.load_otbm(path)
    tele = {}
    for ti, _iid, d in otbm.teleports(m, [portal] + list(extra)):
        tele[(int(m.tiles['x'][ti]), int(m.tiles['y'][ti]), int(m.tiles['z'][ti]))] = tuple(d)
    return World(m, tele)


def stack_of(tile):
    """a tile of ours ({'ground', 'items'}) as the id list otbm.py gives for a map tile"""
    return ([tile['ground']] if tile.get('ground') else []) + [iid for iid, _a in tile['items']]


# ------------------------------------------------------------------------------------------------ the room
def room_layout(world, room, portal, portal_at=None, wing=None):
    """the grown room: {'tiles': {pos: tile}, 'module': set(pos), 'caps': set(pos) (new place of the ends),
    'old': set(pos) (tiles of the old ends, replaced), 'swept': set(pos) (open ground of a wing's floor that the new
    tiles replace), 'slots': [...]}. portal_at: the places that hold a teleport in the base room (the hall order moves
    them; hall_hunts.csv keeps where they were), else the map says it.
    wing: grow another floor the same way ({z, from, east: {modules}, west: {modules}, sweep}): the alcoves are
    copied from floor `from` (the room's own, bare of rewards and signs), the ends are that floor's own; with `sweep`
    the new tiles may replace open ground (no house, nothing but decoration) where the floor has the town's lawn"""
    z = wing['z'] if wing else room['z']
    src_z = (wing.get('from') or z) if wing else z
    r0, r1 = room['rows']
    tiles, module, caps, old, swept, cols = {}, set(), set(), set(), set(), []
    for side in ('east', 'west'):
        s = room.get(side)
        n_mod = (wing.get(side) or {}).get('modules', 0) if wing else (s or {}).get('modules', 0)
        if not s or not n_mod:
            continue
        a, b = s['module']
        c0, c1 = s['cap']
        per = b - a + 1
        n = n_mod * per
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
                st = world.stack((sx, y, src_z))
                if st is None:
                    continue
                if world.house((sx, y, src_z)):
                    raise InstallError('room: the module tile %d,%d,%d belongs to a house' % (sx, y, src_z))
                items = [(i, {}) for i in st if i != portal]
                tiles[(x, y, z)] = dict(ground=None, items=items, flags=world.flags((sx, y, src_z)))
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
    if wing and wing.get('sweep'):
        swept = {p for p in tiles if world.has(p) and p not in old}
    # the slots: new columns whose source column has a teleport on the north teleport row
    tn, ts = room['teleportRows']
    slots = []
    for side, x, sx in cols:
        st = world.stack((sx, tn, src_z))
        has = (sx, tn, src_z) in portal_at if portal_at is not None else bool(st and portal in st)
        if not has:
            continue
        for row, cell, sign in ((tn, room['cellRows'][0], room['signRows'][0]), (ts, room['cellRows'][1], room['signRows'][1])):
            cells = []
            for cx in (x - 1, x + 1):
                t = tiles.get((cx, cell, z))
                if t and not t['flags'] & 1 and len(t['items']) == 1:
                    cells.append((cx, cell, z))
            slots.append(dict(teleport=(x, row, z), sign=(x, sign, z), cells=cells, side=side))
    # along the corridor: west to east, the north teleport of a column before the south one (the bands ascend that way)
    slots.sort(key=lambda s: (s['teleport'][0], s['teleport'][1]))
    return dict(tiles=tiles, module=module, caps=caps, old=old, swept=swept, slots=slots)


def check_swept(map_path, swept, portal, items, log):
    """A wing may take the place of open ground (room_layout `sweep`): refused when one of those tiles holds anything
    but decoration - an action id, a unique id, a teleport, a sign, a container or an attribute we cannot write back."""
    import hall_order as H
    data = open(map_path, 'rb').read()
    ranges = tile_ranges(data, sorted(swept))
    sign, quest = items.get('sign'), set(items.get('questPortals') or ())
    for p in sorted(swept):
        s, e = ranges[p]
        try:
            t = H.parse_tile(data[s:e + 1], p)
        except H.HallError as ex:
            raise InstallError('room: a wing would replace a tile we cannot read back: %s' % ex)
        for iid, a in t['items']:
            if a.get('aid') or a.get('uid') or a.get('tele') or iid in (portal, sign) or iid in quest:
                raise InstallError('room: a wing would replace an action id, unique id, teleport or sign at %d,%d,%d '
                                   '(item %d); nothing written' % (p + (iid,)))
    log('room: %d tile(s) of open ground replaced by the wings hold only decoration' % len(swept))


def room_state(world, lay, portal=None):
    """'done' (grown already), 'todo' (can grow), or raises with the reason. A teleport on a copied tile (the hall
    order puts base hunts in the wings) does not count."""
    if not lay['tiles']:
        return 'done'

    def bare(st):
        return None if st is None else [i for i in st if i != portal]
    same = [p for p in lay['module'] if bare(world.stack(p)) == bare(stack_of(lay['tiles'][p]))]
    if len(same) == len(lay['module']):
        return 'done'  # the copies stand where the old ends were: grown (the ends were moved then)
    taken = [p for p in lay['tiles'] if world.has(p) and p not in lay['old'] and p not in lay.get('swept', ())]
    if taken:
        raise InstallError('room: %d target tile(s) are taken (first %d,%d,%d) and the room is not the one this '
                           'config grows from; nothing written' % ((len(taken),) + taken[0]))
    if not lay['old']:
        raise InstallError('room: no end (cap) tiles where the config says')
    for p in set(lay['old']) | set(lay.get('swept', ())):
        if world.house(p):
            raise InstallError('room: the tile %d,%d,%d belongs to a house; not replaced' % p)
    return 'todo'


def top_monster(plan):
    """the plan's most frequent monster (by spawn count; ties by name)"""
    count = {}
    for s in plan.get('spawns', []):
        count[s['monster']] = count.get(s['monster'], 0) + s.get('count', 1)
    return sorted(count.items(), key=lambda kv: (-kv[1], kv[0]))[0][0] if count else None


def band_of(plans, pid):
    """the plan's level band (lo, hi); a plan without one sorts last"""
    lv = plans[pid][1].get('level') or [10 ** 9, 10 ** 9]
    return (int(lv[0]), int(lv[1]))


def plan_order(cfg, plans):
    """every plan that has a plan file, by level band ascending (floor, then ceiling, then id), each {id, monster, ...}:
    the config's entry gives the display monster, minLevel and a pinned `slot`; a plan the config does not list gets
    its most frequent monster (auto). The config's order does not count: a new hunt lands in its place by its band."""
    listed = {p['id']: dict(p) for p in cfg.get('plans', []) if p['id'] in plans}
    out = []
    for pid in sorted(plans, key=lambda pid: band_of(plans, pid) + (pid,)):
        out.append(listed.get(pid) or dict(id=pid, monster=top_monster(plans[pid][1]), auto=True))
    return out


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
            if attrs.get('raw'):  # other attributes kept as read (a sign's text, a count)
                q += attrs['raw']
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


def spawn_cells(block):
    """the tiles the creatures of a spawn block stand on (centre + each x / y offset, its own z)"""
    c = spawn_center(block)
    if not c:
        return []
    return [(c[0] + int(x), c[1] + int(y), int(z)) for x, y, z in
            re.findall(r'<(?:monster|npc)\b[^>]*?\bx="(-?\d+)" y="(-?\d+)" z="(\d+)"', block)]


def update_spawns(text, plan_blocks, displays, spawntime, takeover=()):
    """the spawn file with the plans' blocks (once each) and exactly the wanted display blocks; returns (text, notes).
    displays: {id: (monster, cells[, spawntime])}; takeover: display cells of the hall order whose unmarked blocks (the
    base server's own display monsters) are replaced too"""
    notes = []
    blocks = SPAWN_RE.findall(text)
    want, times = {}, {}
    for pid, d in displays.items():
        monster, cells = d[0], d[1]
        for c in cells:
            want[c] = (pid, monster)
            times[c] = d[2] if len(d) > 2 and d[2] else spawntime
    takeover = set(takeover)
    for b in blocks:
        # a base display block may stand its monster off its centre (centre in the corridor, monster in the cell)
        cells = spawn_cells(b)
        on_cell = spawn_center(b) in takeover or (cells and all(c in takeover for c in cells))
        if 'chaoshunt=' not in b and 'chaoscontent=' not in b and on_cell:
            text = text.replace(b, '', 1)
            notes.append('base display spawn at %s taken over by the hall order' % (spawn_center(b),))
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
        for cell in spawn_cells(b):
            if cell != c and b not in centers.get(cell, []):
                centers.setdefault(cell, []).append(b)
    add = []
    for c in sorted(want):
        pid, monster = want[c]
        have = [b for b in centers.get(c, []) if 'chaoshunt="%s"' % pid in b]
        if have:
            if 'name="%s"' % monster in have[0] and 'spawntime="%d"' % times[c] in have[0]:
                continue
            text = text.replace(have[0], '', 1)
        elif centers.get(c):
            notes.append('display cell %s already has a spawn (not ours); skipped' % (c,))
            continue
        add.append('\t<spawn centerx="%d" centery="%d" centerz="%d" radius="1" chaoshunt="%s">\n'
                   '\t\t<monster name="%s" x="0" y="0" z="%d" spawntime="%d" />\n\t</spawn>\n'
                   % (c[0], c[1], c[2], pid, monster, c[2], times[c]))
    if add:
        notes.append('%d display spawn(s) added' % len(add))
    for pid, xml in plan_blocks:
        if 'chaoscontent="%s"' % pid in text:
            continue
        blocks_of = SPAWN_RE.findall(xml)
        if not blocks_of:
            continue  # an area without monsters (the Memorial's plaza)
        for b in blocks_of:
            add.append(re.sub(r'^(\t<spawn\b[^>]*?)>', r'\1 chaoscontent="%s">' % pid, b, count=1))
        notes.append('%s: %d spawn block(s) added' % (pid, len(blocks_of)))
    if add:
        cut = text.rfind('</spawns>')
        if cut < 0:
            raise InstallError('the spawn file has no </spawns>')
        text = text[:cut] + ''.join(add) + text[cut:]
    return text, notes


# ------------------------------------------------------------------------------------------------ places file
def places_lua(back, entries, base=None, floors=None, hall=False, quests=None):
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
    lines.append('\t},')
    if base is not None:
        # the base server's hunt teleports of the hall (hall_hunts.csv): the map's teleport leads there; the script
        # writes the sign and floats the label
        lines.append('\thall = %s,' % ('true' if hall else 'false'))
        lines.append('\tbase = {')
        for e in base:
            lines.append('\t\t{id = "%s", name = %s, level = {%d, %d}, teleport = %s, sign = %s, dest = %s},'
                         % (e['id'], q(e['name']), e['level'][0], e['level'][1], pos(e['teleport']), pos(e['sign']),
                            pos(e['dest'])))
        lines.append('\t},')
        lines.append('\tfloors = {')
        for f in floors or []:  # level {lo, 0}: no upper limit (the top floor)
            lines.append('\t\t{z = %d, level = {%d, %d}},' % (f['z'], f['level'][0], f['level'][1]))
        lines.append('\t},')
        if quests:
            # the quest hall (hall_quests.py): where its "Quests" label floats and how many alcoves it has
            lines.append('\tquests = {label = %s, count = %d},' % (pos(quests['label']), quests['count']))
    lines += ['}', '']
    return '\n'.join(lines)


# ------------------------------------------------------------------------------------------------ run
def spawn_path(map_path):
    p = map_path[:-5] + '-spawn.xml'
    return p if os.path.isfile(p) else None


def fixed_plans(dirs, hunts, log=print):
    """the plans of the fixed-area folders: {id: (path, plan)}; a plan without an origin is left out (logged)"""
    out = {}
    for d in dirs or ():
        if not os.path.isdir(d):
            continue
        for pid, (path, plan) in plan_files(d).items():
            if pid in hunts or pid in out:
                raise InstallError('plan id %s is in two plan folders' % pid)
            if not isinstance(plan.get('origin'), dict):
                log('%s: no origin in %s; not placed' % (pid, os.path.basename(path)))
                continue
            out[pid] = (path, plan)
    return out


def hall_layout(world, cfg, rows, lay_slots, order, plans, placed, hall_on, log):
    """the hall order (hall_order.py): every hunt slot of the hall (the base teleports' places, the quest alcoves'
    places and the wings'), the base hunts of `rows` (hall_hunts.csv) and the placed content hunts, assigned by
    floor and band (hall_on) or as the base server had them (the content hunts in the wings as before; the quests
    stay in their alcoves). Returns {'assign': {id: slot}, 'portal': {pos: dest or None}, 'displays': {id: (monster,
    cells, spawntime)}, 'takeover': cells, 'base': [...], 'floors': [...], 'slots': [...], 'quests': rows}"""
    import hall_order as H
    room, hall = cfg['room'], cfg['hall']
    quests = H.quests_of(rows) if hall_on else []  # a quest alcove is a hunt slot once its quest has moved
    rows = H.hunts_of(rows)  # a `not a hunt` row keeps its teleport where it stands, untouched
    slots = H.share_cells(H.hall_slots(world, room, cfg['items']['sign'], rows, lay_slots, quests), hall)
    mons = {p['id']: p for p in order}
    ours = [dict(id=pid, lo=int(plans[pid][1]['level'][0]), hi=int(plans[pid][1]['level'][1]), level=None) for pid in placed]
    hunts = [dict(id=r['id'], lo=r['lo'], hi=r['hi'], level=r['level']) for r in rows] + ours
    if hall_on:
        assign = H.assign(hunts, slots, hall)
    else:
        assign = H.original(rows, slots)
        wing = [s for s in slots if s['base'] is None]
        wing.sort(key=lambda s: (s['teleport'][0], s['teleport'][1]))
        assign.update(assign_slots(order, wing, set(placed)))
    by_row = {r['id']: r for r in rows}
    portal = {}
    for s in slots:
        portal[s['teleport']] = None
    for hid, s in assign.items():
        r = by_row.get(hid)
        if r:
            portal[s['teleport']] = (r['dest_x'], r['dest_y'], r['dest_z'])
    displays = {}
    for hid, s in assign.items():
        if hid in by_row:
            if by_row[hid]['display']:
                displays[hid] = (by_row[hid]['display'], s['cells'], by_row[hid]['spawntime'])
        else:
            p = mons.get(hid) or {}
            if p.get('monster') and p.get('display', True):
                displays[hid] = (p['monster'], s['cells'], cfg.get('displaySpawntime', 120))
    takeover = {c for s in slots for c in s['cells']}
    base = []
    for hid, s in sorted(assign.items(), key=lambda kv: H.slot_key(hall, kv[1]['teleport'])):
        r = by_row.get(hid)
        if r:
            base.append(dict(id=hid, name=r['name'], level=(r['lo'], r['hi']), teleport=s['teleport'], sign=s['sign'],
                             dest=(r['dest_x'], r['dest_y'], r['dest_z'])))
    floors = H.floor_bands(assign, hunts, hall)
    if hall_on:
        bad = H.check_ascending(assign, hunts, hall)
        if bad:
            raise InstallError('hall order: not ascending: %s' % bad[0])
        for f in floors:
            on = sum(1 for s in assign.values() if s['teleport'][2] == f['z'])
            log('hall: floor %d (levels %s): %d hunts on %d slots' % (
                f['z'], H.floor_range_text(hall, f['z']), on, sum(1 for s in slots if s['teleport'][2] == f['z'])))
    log('hall: %d hunts on %d slots (%s)' % (len(assign), len(slots), 'by floor and level' if hall_on else 'as the base server had them'))
    return dict(assign=assign, portal=portal, displays=displays, takeover=takeover, base=base, floors=floors, slots=slots,
                quests=quests)


def hall_edit(world, map_path, cfg, rows, hl, hall_on, new_tiles, log):
    """The hall order's changes to existing tiles, through one reading of them (hall_quests.TileEditor): the quest
    alcoves moved to the quest hall (or back) with their way back from the quest sites, the reward chests of the plaza
    taken away, the hunt teleports of every slot (the slot's hunt, or none), the signs of unused slots blank.
    Returns ({pos: tile} to write - the map's own tiles that differ now, and the quest layout or None)."""
    import hall_order as H
    import hall_quests as Q
    room, portal, sign = cfg['room'], cfg['items']['portal'], cfg['items']['sign']
    qcfg = cfg['hall'].get('quests')
    qrows = H.quests_of(rows)
    qlay = Q.layout(qcfg, room, qrows) if (qcfg and qrows) else None
    ed = Q.TileEditor(world, map_path, new_tiles)
    ed.need(*hl['portal'])
    used = {s['teleport'] for s in hl['assign'].values()}
    for s in hl['slots']:
        if s['sign']:
            ed.need(tuple(s['sign']))
    found, chests, template_at = [], [], None
    if qlay:
        ed.need(*Q.need_positions(qlay))
        found = Q.find_returns(world.tele, qlay, qcfg.get('returnRadius', 4))
        ed.need(*[p for _a, p in found])
        for c in qcfg.get('chests') or []:
            c = dict(c, z=qcfg['z'])
            chests.append(c)
            ed.need(*[(c['x'], y, c['z']) for y in range(c['rows'][0], c['rows'][1] + 1)])
        tn, ts = room['teleportRows']
        template_at = [(qrows[0]['x'], y, qrows[0]['z']) for y in (tn + 1, (tn + ts) // 2, ts - 1)]  # the corridor's 3 rows
        ed.need(*template_at)
    try:
        ed.load()
        if qlay:
            template = [ed.get(p) for p in template_at]
            if None in template:
                raise Q.QuestError('no corridor tile at %s' % (template_at,))
            if hall_on:
                w, notes = Q.plan_chests(ed, chests)
                for p, t in w.items():
                    ed.set(p, t)
                for n in notes:
                    log('quests: ' + n)
            w, notes = Q.plan_move(ed, qlay, room, portal, sign, template, forward=hall_on)
            for p, t in w.items():
                ed.set(p, t)
            for n in notes:
                log('quests: ' + n)
            for p, t in Q.plan_returns(ed, found, hall_on).items():
                ed.set(p, t)
            if found:
                log('quests: %d way(s) back from the quest sites point to the %s' % (
                    len(found), 'quest hall' if hall_on else 'old alcoves'))
        for p, dest in hl['portal'].items():
            t = ed.get(p)
            if t is None:
                raise Q.QuestError('no tile at %d,%d,%d for a hunt teleport' % p)
            ed.set(p, H.with_portal(t, portal, dest))
        if hall_on:
            for s in hl['slots']:
                if s['teleport'] not in used and s['sign']:
                    t = ed.get(tuple(s['sign']))
                    if t is not None:
                        ed.set(tuple(s['sign']), Q.blank_sign(t, sign))
    except (Q.QuestError, H.HallError) as e:
        raise InstallError(str(e))
    return ed.changed(), qlay


def run(data_dir, dry=False, only=None, room_on=True, plans_dir=PLANS_DIR, config=CONFIG, map_path=None,
        compiled=None, world=None, log=print, fixed_dirs=FIXED_DIRS, hall_csv=None, hall_on=None):
    """compiled: {id: out_dir} already compiled (tests); world: a World (tests); fixed_dirs: the folders of the fixed
    areas (placed at their origin, no teleport); hall_csv: the base hunts of the hall (default tools/hall_hunts.csv;
    without it the hall is left as it is); hall_on: False puts the base hunts back where they were (--remove-hall),
    default the config's hall.enabled. Returns a summary dict."""
    import area_plan_place as PL
    import hall_order
    cfg = load_config(config) if isinstance(config, str) else config
    portal = cfg['items']['portal']
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise InstallError('no world map in %s/world' % data_dir)
    plans = plan_files(plans_dir)
    fixed = fixed_plans(fixed_dirs, plans, log)
    unknown = [p['id'] for p in cfg.get('plans', []) if p['id'] not in plans]
    for pid in unknown:
        log('config plan %s has no plan file; skipped' % pid)
    order = plan_order(cfg, plans)
    for p in order:
        if p.get('auto'):
            log('%s: not in the hunt teleports config: teleport in the place of its band, display monster %s (check its '
                'look in the client; list the plan in the config to choose)' % (p['id'], p['monster']))
    if only:
        bad = [o for o in only if o not in plans and o not in fixed]
        if bad:
            raise InstallError('unknown plan(s) for --only: %s' % ', '.join(bad))
    tmp = tempfile.mkdtemp(prefix='chaos_content_')
    try:
        areas = {}
        for pid, (path, plan) in list(plans.items()) + list(fixed.items()):
            out = (compiled or {}).get(pid)
            if not out:
                out = os.path.join(tmp, pid)
                compile_plan(path, out)
            tiles, man = read_area(out, pid)
            areas[pid] = dict(out=out, tiles=tiles, man=man, plan=plan)
        if world is None:
            log('reading %s ...' % map_path)
            world = load_world(map_path, portal, cfg['items'].get('questPortals') or ())
        # the hall order's data (tools/hall_hunts.csv): the base hunts and where they stood
        rows = None
        if room_on and cfg.get('hall'):
            rows = hall_order.read_csv(hall_csv or hall_order.CSV_PATH)
        if hall_on is None:
            hall_on = bool(cfg.get('hall', {}).get('enabled'))
        base_at = {(r['x'], r['y'], r['z']) for r in rows if r['x'] is not None} if rows else None
        # the room: floor 6 and, with the hall order, the other floors' wings (hall_order.assign names a floor's missing slots)
        lays, rstates = [], []
        if room_on:
            lays.append(room_layout(world, cfg['room'], portal, base_at))
            for w in (cfg['room'].get('wings') or []) if rows else []:
                lays.append(room_layout(world, cfg['room'], portal, base_at, wing=w))
        for l in lays:
            rstates.append(room_state(world, l, portal))
        todo_lays = [l for l, st in zip(lays, rstates) if st == 'todo']
        rstate = 'todo' if todo_lays else 'done'
        lay = dict(tiles={}, module=set(), caps=set(), old=set(), swept=set(), slots=[])
        for l in lays:
            for k in ('tiles',):
                lay[k].update(l[k])
            for k in ('module', 'caps', 'old', 'swept'):
                lay[k] |= l[k]
            lay['slots'] += l['slots']
        lay['slots'].sort(key=lambda s: (s['teleport'][0], s['teleport'][1], s['teleport'][2]))
        grow_tiles = {}
        for l in todo_lays:
            grow_tiles.update(l['tiles'])
        grow_cut = set()
        for l in todo_lays:
            grow_cut |= l['old'] | l['swept']
        swept_all = set().union(*[l['swept'] for l in todo_lays]) if todo_lays else set()
        if swept_all:
            check_swept(map_path, swept_all, portal, cfg['items'], log)
        log('room: %s (%d new tiles, %d replaced, %d teleport slots)' % (
            'grown already' if rstate == 'done' else 'grows', len(set(grow_tiles) - grow_cut) if rstate == 'todo' else 0,
            len(grow_cut & set(grow_tiles)) if rstate == 'todo' else 0, len(lay['slots'])))
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
            log('%s: %s (%d tiles at %s)%s' % (pid, {'done': 'placed already', 'todo': 'to place', 'skipped': 'not placed (--only)'}[st],
                                               len(a['tiles']), tuple(a['man']['origin']),
                                               ', fixed area: no teleport' if pid in fixed else ''))
        # tiles of two areas on one spot: refused
        owner = {}
        for pid, a in areas.items():
            for p in a['tiles']:
                if p in owner:
                    raise InstallError('%s and %s overlap at %d,%d,%d' % ((owner[p], pid) + p))
                owner[p] = pid
        placed_all = {pid for pid, st in state.items() if st in ('done', 'todo')}
        placed = placed_all - set(fixed)
        hl = None
        if rows:
            try:
                hl = hall_layout(world, cfg, rows, lay['slots'], order, plans, placed, hall_on, log)
            except hall_order.HallError as e:
                raise InstallError('hall order: %s' % e)
            slots = {pid: s for pid, s in hl['assign'].items() if pid in placed}
        else:
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
            new_tiles.update(grow_tiles)
        for pid, st in state.items():
            if st == 'todo':
                new_tiles.update(areas[pid]['tiles'])
        remove = sorted(grow_cut) if rstate == 'todo' else []
        qlay = None
        if hl:
            changed, qlay = hall_edit(world, map_path, cfg, rows, hl, hall_on, new_tiles, log)
            if changed:
                log('hall: %d existing tile(s) to rewrite' % len(changed))
            new_tiles.update(changed)
            remove = sorted(set(remove) | {p for p in changed if world.has(p)})
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
                           for pid in sorted(placed_all)]
            if hl:
                displays, takeover = hl['displays'], hl['takeover']
            else:
                mons = {p['id']: p['monster'] for p in order if p.get('display', True)}
                displays, takeover = {pid: (mons[pid], s['cells']) for pid, s in slots.items() if mons.get(pid)}, ()
            new, notes = update_spawns(text, plan_blocks, displays, cfg.get('displaySpawntime', 120), takeover)
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
        for pid in sorted(placed_all):
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
        if hl:
            quests = dict(label=qlay['label'], count=len(qlay['alcoves'])) if (qlay and hall_on) else None
            text = places_lua(cfg['room']['back'], entries, hl['base'], hl['floors'] if hall_on else [], hall_on, quests)
            summary['hall'] = dict(on=hall_on, assign={k: v['teleport'] for k, v in hl['assign'].items()},
                                   floors=hl['floors'], displays={k: v[0] for k, v in hl['displays'].items()})
        else:
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
        if a in ('--dry-run', '--no-room', '--no-fixed', '--remove-hall'):
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
            plans_dir=args.get('--plans', PLANS_DIR), config=args.get('--config', CONFIG), map_path=args.get('--map'),
            fixed_dirs=() if args.get('--no-fixed') else FIXED_DIRS, hall_on=False if args.get('--remove-hall') else None)
    except InstallError as e:
        print('refused: %s' % e)
        return 1
    print('done%s' % (' (dry run: nothing written)' if args.get('--dry-run') else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
