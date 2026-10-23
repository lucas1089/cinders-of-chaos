#!/usr/bin/env python3
"""The teleport hall of Cinderhold in level order (server/README.md "Hall order").

usage: python3 -I server/tools/hall_order.py derive DATA_DIR [--map FILE] [--force]
       python3 -I server/tools/hall_order.py show [--csv FILE]
       python3 -I server/tools/hall_order.py band DATA_DIR X,Y,Z

The hall (hunt_teleports_config.lua `room` and `hall`) has the base server's own hunt teleports on three floors (z 7,
6, 5) and the planned content hunts' teleports in the grown wings of floor 6. The owner wants the whole hall ordered by
level: the lowest bands on the entry floor (z 7) along the corridor, each floor up the next bands.

Floors by level (owner, 2026-10-18): the ground floor z 7 holds the hunts of levels 1-500, z 6 of 501-1000, z 5 the
rest (config `hall.levels`); inside a floor they ascend by level along the corridor. A floor with too few slots is
grown (install_content_areas.py). The base server's quest teleports (kind `quest`, the entry floor's own alcoves) take
no level slot: they move, with the rewards shown beside them, to the quest hall east of the corridor's aisle
(hall_quests.py), and their old alcoves become hunt slots.

derive  reads the base server's hunt teleports of the hall from the map (a teleport on a teleport row of the room, or
        on the corridor's end row when it does not lead to the temple) and gives each a level and a band from the
        monsters spawned around its destination (hunt_band; each monster's hunting level as tools/gen_bounty_pool.py
        estimates it: the middle of <level min max>, else 1.6 x sqrt(experience) raised by health). The level is the
        weighted median (the order and the floors' ranges), the band the weighted 20th to 80th percentile (signs).
        The room's monster (`display`: in the two cells beside the teleport and on its sign and label) is the first
        top monster that does not turn invisible. Nothing spawns near: kind `not a hunt` (left in place, unordered). Writes tools/hall_hunts.csv (review it; it
        is the install's input; --force keeps each row's kind and note, the hand decisions). It must
        read the hall as the base server has it: refused when the CSV exists (--force) or the places file says the
        hall order is installed.
show    prints the CSV in hall order with the floor of each hunt.
band    prints the level, band and top monsters around a destination, for a hunt added to the CSV by hand (empty z, x, y).

install_content_areas.py does the rest (step `contentareas`): with the CSV present it owns every hunt slot of the
hall (the base teleports' tiles, their display cells and signs, and the wings' slots), assigns the base and content
hunts to them by band (hall_order.assign) and writes the teleport tiles, the display spawns, the hunts' ways back
(front_of: in front of the teleport each hunt has now) and the places file.
--remove-hall puts the base hunts back where the base server had them (the CSV keeps every original position,
destination and display monster).
Python 3 standard library; numpy through tools/map/otbm.py.
"""
import csv, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

CSV_PATH = os.path.join(HERE, 'hall_hunts.csv')
FIELDS = ['id', 'z', 'x', 'y', 'dest_x', 'dest_y', 'dest_z', 'kind', 'name', 'level', 'lo', 'hi', 'display', 'spawntime',
          'monsters', 'note']
KIND_HUNT, KIND_NOT, KIND_QUEST = 'hunt', 'not a hunt', 'quest'
KINDS = (KIND_HUNT, KIND_NOT, KIND_QUEST)
# hand decisions kept by a new derive (--force): the kind, a note and, for a hunt, its band
KEEP = ('kind', 'note')


class HallError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ the data file
def read_csv(path=CSV_PATH):
    if not os.path.isfile(path):
        return None
    rows = []
    with open(path, encoding='utf-8', newline='') as f:
        for r in csv.DictReader(l for l in f if not l.startswith('#')):
            for k in ('dest_x', 'dest_y', 'dest_z', 'lo', 'hi', 'spawntime'):
                r[k] = int(r[k])
            # a hunt added to the hall (not a base teleport) has no place of its own: z, x, y empty
            for k in ('z', 'x', 'y'):
                r[k] = int(r[k]) if r.get(k) not in (None, '') else None
            r['level'] = int(r['level']) if r.get('level') not in (None, '') else (r['lo'] + r['hi']) // 2
            r['kind'] = r.get('kind') or KIND_HUNT
            if r['kind'] not in KINDS:
                raise HallError('%s: kind %r (hunt, quest or not a hunt)' % (r['id'], r['kind']))
            if r['x'] is None and r['kind'] != KIND_HUNT:
                raise HallError('%s: only a hunt can be without a place' % r['id'])
            r['note'] = r.get('note') or ''
            rows.append(r)
    ids = [r['id'] for r in rows]
    if len(ids) != len(set(ids)):
        raise HallError('%s: an id is there twice' % path)
    return rows


def write_csv(rows, path=CSV_PATH):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write('# Generated by server/tools/hall_order.py derive from the base map and spawn file; reviewed by hand.\n')
        f.write('# The base server\'s hunt teleports of the Cinderhold hall: where each stood (z x y), where it leads, its\n')
        f.write('# level band (lo hi, from the monsters around the destination), its display monster and the top monsters.\n')
        w = csv.DictWriter(f, FIELDS, lineterminator='\n')
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, '') for k in FIELDS})


def base_id(z, x, y):
    return 'base_%d_%d_%d' % (z, x, y)


# ------------------------------------------------------------------------------------------------ the hall
def is_hunt_teleport(pos, dest, room, hall):
    """a hunt teleport of the hall: on a teleport row, or on the corridor's end row not leading to the temple"""
    x, y, z = pos
    if z not in hall['floors'] or not hall['x'][0] <= x <= hall['x'][1]:
        return False
    if y in room['teleportRows']:
        return True
    return y == hall['endRow'] and tuple(dest) != tuple(hall['temple'])


def hall_teleports(tele, room, hall):
    """[(pos, dest)] of the hall's hunt teleports in a {pos: dest} map"""
    return sorted(((p, d) for p, d in tele.items() if is_hunt_teleport(p, d, room, hall)), key=lambda t: (t[0][2], t[0][0], t[0][1]))


def floor_rank(hall, z):
    return hall['floors'].index(z)


def slot_key(hall, pos):
    """the hall's order of slots: the floors in `hall.floors` order (the entry floor first), then along the corridor
    from west to east, the north teleport of a column before the south one"""
    return (floor_rank(hall, pos[2]), pos[0], pos[1])


def level_of(h):
    """a hunt's level: its `level` (the weighted median of its monsters' levels), else the middle of its band"""
    return h['level'] if h.get('level') is not None else (h['lo'] + h['hi']) // 2


def band_key(h):
    return (level_of(h), h['lo'], h['hi'], h['id'])


def order_hunts(hunts):
    """hunts [{id, lo, hi, level}] ascending by level (the median), then band floor, ceiling, id"""
    return sorted(hunts, key=band_key)


def floor_for(hall, level):
    """the floor a hunt of `level` belongs on by the owner's rule (hall.levels: [{z, max}, ..., {z}] in floor order, a
    hunt of level <= max goes on that floor, the last floor takes the rest); None without the rule"""
    rule = hall.get('levels')
    if not rule:
        return None
    for f in rule:
        if f.get('max') is None or level <= f['max']:
            return f['z']
    return rule[-1]['z']


def assign(hunts, slots, hall):
    """{hunt id: slot}: the hunts by band, the slots in hall order (slot_key), one to one; refused when short.
    With hall.levels each hunt takes a slot of the floor its level belongs on (floor_for), the hunts of one floor in
    band order along that floor's slots; a floor with fewer slots than hunts is refused (grow it); without the rule
    the hunts fill all slots from the entry floor up."""
    ordered = sorted(slots, key=lambda s: slot_key(hall, s['teleport']))
    hs = order_hunts(hunts)
    if not hall.get('levels'):
        if len(hs) > len(ordered):
            raise HallError('the hall has %d hunt slots for %d hunts: grow the room (`modules`)' % (len(ordered), len(hs)))
        return {h['id']: s for h, s in zip(hs, ordered)}
    out = {}
    for z in hall['floors']:
        mine = [h for h in hs if floor_for(hall, level_of(h)) == z]
        free = [s for s in ordered if s['teleport'][2] == z]
        if len(mine) > len(free):
            raise HallError('floor %d has %d hunt slots for %d hunts (levels %s): grow it (`room.wings`)'
                            % (z, len(free), len(mine), floor_range_text(hall, z)))
        out.update({h['id']: s for h, s in zip(mine, free)})
    return out


def floor_range(hall, z):
    """(lo, hi) of the levels a floor holds by the rule; hi 0 = no limit (the top floor); None without the rule"""
    rule = hall.get('levels')
    if not rule:
        return None
    lo = 1
    for f in rule:
        if f['z'] == z:
            return (lo, f.get('max') or 0)
        lo = f.get('max') or lo
    return None


def floor_range_text(hall, z):
    r = floor_range(hall, z)
    return 'any' if not r else ('%d+' % r[0] if not r[1] else '%d-%d' % r)


def original(hunts_base, slots):
    """{base hunt id: slot}: every base hunt at the slot it had (the base server's order); a hunt added to the hall
    (no place of its own) is not there"""
    by = {tuple(s['teleport']): s for s in slots}
    out = {}
    for r in hunts_base:
        if r['x'] is None:
            continue
        s = by.get((r['x'], r['y'], r['z']))
        if not s:
            raise HallError('%s: its slot %d,%d,%d is not a slot of the hall' % (r['id'], r['x'], r['y'], r['z']))
        out[r['id']] = s
    return out


def floor_bands(assignment, hunts, hall):
    """[{z, level = [lo, hi]}] per floor of the hall in hall.floors order. With hall.levels the owner's ranges (hi 0:
    and up); else the lowest to the highest hunt level on it (a floor without hunts is left out), so floors never
    overlap"""
    if hall.get('levels'):
        return [dict(z=z, level=list(floor_range(hall, z))) for z in hall['floors']]
    by = {h['id']: h for h in hunts}
    out = []
    for z in hall['floors']:
        on = [by[i] for i, s in assignment.items() if s['teleport'][2] == z and i in by]
        if on:
            out.append(dict(z=z, level=[min(level_of(h) for h in on), max(level_of(h) for h in on)]))
    return out


def check_ascending(assignment, hunts, hall):
    """problems (strings) when the hall's slots do not ascend by band, or a hunt stands on the wrong floor"""
    by = {h['id']: h for h in hunts}
    seq = sorted(assignment.items(), key=lambda kv: slot_key(hall, kv[1]['teleport']))
    out = []
    for (a, _sa), (b, _sb) in zip(seq, seq[1:]):
        if band_key(by[a]) > band_key(by[b]):
            out.append('%s (%d) before %s (%d)' % (a, level_of(by[a]), b, level_of(by[b])))
    for i, s in assignment.items():
        want = floor_for(hall, level_of(by[i]))
        if want is not None and s['teleport'][2] != want:
            out.append('%s (%d) on floor %d, its floor is %d' % (i, level_of(by[i]), s['teleport'][2], want))
    return out


# ------------------------------------------------------------------------------------------------ the bands
def band(levels, lo_q=0.2, hi_q=0.8):
    """(lo, hi, median) of weighted levels [(level, weight)]: the lo_q and hi_q weighted percentiles (lo down and hi
    up to 5) and the weighted median (the hunt's level: its place in the order and in the floor's range)"""
    pts = sorted((l, w) for l, w in levels if w > 0)
    if not pts:
        return None
    total = float(sum(w for _l, w in pts))

    def q(f):
        acc = 0.0
        for l, w in pts:
            acc += w
            if acc >= f * total - 1e-9:
                return l
        return pts[-1][0]
    lo, hi, med = q(lo_q), q(hi_q), q(0.5)
    lo = max(1, int(lo) // 5 * 5)
    hi = max(lo + 5, -(-int(hi) // 5) * 5)
    return lo, hi, max(1, int(med))


SPAWN_RE = re.compile(r'<spawn\b([^>]*)>(.*?)</spawn>', re.S)


def spawn_points(text):
    """[(x, y, z, monster name)] of every monster of a spawn file"""
    out = []
    num = lambda tag, k: int(re.search(r'\b%s="(-?\d+)"' % k, tag).group(1))
    for m in SPAWN_RE.finditer(text):
        head = m.group(1)
        try:
            cx, cy, cz = num(head, 'centerx'), num(head, 'centery'), num(head, 'centerz')
        except AttributeError:
            continue
        for t in re.finditer(r'<monster\b[^>]*>', m.group(2)):
            tag = t.group(0)
            nm = re.search(r'\bname="([^"]+)"', tag)
            if not nm:
                continue
            dx = re.search(r'\bx="(-?\d+)"', tag)
            dy = re.search(r'\by="(-?\d+)"', tag)
            dz = re.search(r'\bz="(-?\d+)"', tag)
            out.append((cx + (int(dx.group(1)) if dx else 0), cy + (int(dy.group(1)) if dy else 0),
                        int(dz.group(1)) if dz else cz, nm.group(1)))
    return out


def spawn_blocks_at(text):
    """{(x, y, z): (monster, spawntime)} of single-monster spawn blocks by their centre (the display cells)"""
    out = {}
    for m in SPAWN_RE.finditer(text):
        head, body = m.group(1), m.group(2)
        c = re.search(r'centerx="(\d+)" centery="(\d+)" centerz="(\d+)"', head)
        mons = re.findall(r'<monster\b[^>]*>', body)
        if not c or len(mons) != 1:
            continue
        nm = re.search(r'\bname="([^"]+)"', mons[0])
        st = re.search(r'\bspawntime="(\d+)"', mons[0])
        out[tuple(int(v) for v in c.groups())] = (nm.group(1) if nm else '', int(st.group(1)) if st else 60)
    return out


DOWN = (-1, 0, 1, 2, 3)
PASSES = ((40, (0,)), (70, (-1, 0, 1)), (40, DOWN), (70, DOWN), (100, DOWN), (120, DOWN))


def hunt_band(points, levels, dest, passes=PASSES, min_count=8):
    """(lo, hi, median, top monsters) of the monsters spawned around `dest`: the same floor within 40 tiles; with
    fewer than min_count, 70 tiles and the floors next to it; then 40, 70, 100 and 120 tiles down to three floors
    below (a cave whose hunt is down its stairs: the nearest group wins). None when nothing spawns even there."""
    dx, dy, dz = dest
    known = {}
    for r, dzs in passes:
        near = {}
        for x, y, z, name in points:
            if z - dz in dzs and abs(x - dx) <= r and abs(y - dy) <= r:
                near[name] = near.get(name, 0) + 1
        known = {n: c for n, c in near.items() if levels.get(n.lower())}
        if sum(known.values()) >= min_count:
            break
    if not known:
        return None
    lo, hi, med = band([(levels[n.lower()], c) for n, c in known.items()])
    top = [n for n, _c in sorted(known.items(), key=lambda kv: (-kv[1], kv[0]))[:3]]
    return lo, hi, med, top


def derive(data_dir, cfg, map_path=None, log=print, keep=None):
    """the base hunts of the hall (rows of hall_hunts.csv); keep: the rows of a former CSV whose hand decisions (kind,
    note) carry over"""
    import install_content_areas as T
    import gen_bounty_pool as B
    import patch_base_towns
    room, hall = cfg['room'], cfg['hall']
    map_path = map_path or patch_base_towns.map_path(data_dir)
    places = os.path.join(data_dir, T.PLACES_REL)
    if os.path.isfile(places) and 'hall = true' in open(places, encoding='utf-8').read():
        raise HallError('the places file says the hall order is installed: run install_content_areas.py --remove-hall '
                        'first, so the hall is the base server\'s again')
    log('reading %s ...' % map_path)
    world = T.load_world(map_path, cfg['items']['portal'], cfg['items'].get('questPortals') or ())
    sp_text = open(T.spawn_path(map_path), encoding='latin-1').read()
    points = spawn_points(sp_text)
    cells = spawn_blocks_at(sp_text)
    levels = {k: B.estimate_level(m) for k, m in B.load_monsters(data_dir).items()}
    files = monster_files(data_dir)
    rows = []
    kept = {r['id']: r for r in (keep or [])}
    for pos, dest in hall_teleports(world.tele, room, hall):
        x, y, z = pos
        old = kept.get(base_id(z, x, y)) or {}
        got = hunt_band(points, levels, dest)
        kind = old.get('kind') or KIND_HUNT
        if not got:
            log('%d,%d,%d -> %s: no monster spawns near the destination: not a hunt (kept in place)' % (pos + (dest,)))
            got = (1, 5, 1, [])
            kind = KIND_NOT
        lo, hi, med, top = got
        # the room's monster is the hunt's own top monster (the first that stays visible), not whatever the base
        # server's cells beside that teleport held (beta 2026-10-20: "Novice of the Cult" showed two Wyrms); only
        # the spawn time of the base display is kept
        disp = visible_monster(top, files) if top else ''
        st = cfg.get('displaySpawntime', 120)
        for c in display_cells(world, room, pos):
            if c in cells and cells[c][0]:
                st = cells[c][1]
                break
        name = top[0] if top else 'Hunt'
        rows.append(dict(id=base_id(z, x, y), z=z, x=x, y=y, dest_x=dest[0], dest_y=dest[1], dest_z=dest[2],
                         kind=kind, name=name, level=med, lo=lo, hi=hi, display=disp, spawntime=st,
                         monsters='|'.join(top), note=old.get('note', '')))
    # the hunts added to the hall by hand (no place of their own) carry over
    rows += [r for r in (keep or []) if r['x'] is None]
    return rows


# ------------------------------------------------------------------------------------------------ slots
def front_of(room, pos):
    """the corridor tile in front of a hall teleport: below a north-row teleport, above a south-row one, and for a
    teleport on the corridor's end row the tile towards the stairs (room.back.x). The way back from a hunt leads there."""
    x, y, z = pos
    tn, ts = room['teleportRows']
    if y == tn:
        return (x, y + 1, z)
    if y == ts:
        return (x, y - 1, z)
    return (x + 1 if x < room['back']['x'] else x - 1, y, z)


def room_monster(row):
    """the monster of a hunt's room: shown in the two cells beside its teleport and named on its sign and label (the
    CSV's `display`; empty: the top monster `name`). One name for both, so the room shows what it says."""
    return row.get('display') or row.get('name') or ''


def monster_files(data_dir):
    """{lower name: file} of the server's monsters (data/monster/monsters.xml and the Lua monster files); {} without"""
    import glob
    base = os.path.join(data_dir, 'monster')
    out = {}
    reg = os.path.join(base, 'monsters.xml')
    if os.path.isfile(reg):
        for m in re.finditer(r'<monster\s+name="([^"]+)"\s+file="([^"]+)"', open(reg, encoding='latin-1').read()):
            out[m.group(1).lower()] = os.path.join(base, m.group(2))
    for p in sorted(glob.glob(os.path.join(base, '**', '*.lua'), recursive=True)):
        if '#' in os.path.basename(p):
            continue
        for m in re.finditer(r'createMonsterType\(\s*"([^"]+)"', open(p, encoding='latin-1').read()):
            out[m.group(1).lower()] = p
    return out


def is_invisible(path):
    """the monster turns invisible (an `invisible` defense in its XML or Lua file): a display of it shows nothing"""
    try:
        text = open(path, encoding='latin-1').read()
    except OSError:
        return False
    return bool(re.search(r'<defense\b[^>]*name="invisible"|name\s*=\s*"invisible"', text))


def visible_monster(names, files):
    """the first of `names` the server has and that does not turn invisible; the first name when none is known"""
    for n in names:
        f = files.get(n.lower())
        if f and not is_invisible(f):
            return n
    return names[0] if names else ''


def display_cells(world, room, pos, known=(), end_row=None):
    """the closed one-tile cells beside a teleport (non-PZ tiles with only ground on the cell row of its side, or a
    tile in `known`: where a spawn of the map already stands a monster). A teleport with no such cell beside it (two
    teleports sharing one counter, beta 2026-10-22: the base Dragons stayed in the cell behind it) takes the cell right
    behind it. A teleport on the corridor's end row (`end_row`) takes the two cells on its outer side, above and below
    (the base server's own display spots there; only `known` ones)."""
    x, y, z = pos
    known = set(known)

    def ok(c):
        if c in known:
            return True
        st = world.stack(c)
        return st is not None and len(st) == 1 and not world.flags(c) & 1

    rows = room['teleportRows']
    if y in rows:
        row = room['cellRows'][rows.index(y)]
        out = [(cx, row, z) for cx in (x - 1, x + 1) if ok((cx, row, z))]
        if not out and ok((x, row, z)):
            out = [(x, row, z)]
        return out
    if end_row is not None and y == end_row:
        side = 1 if x > room.get('back', {}).get('x', x) else -1
        return [c for c in ((x + side, y - 1, z), (x + side, y + 1, z)) if c in known]
    return []


def spare_cell(world, room, pos, known=(), counter=None):
    """the cell right behind a teleport, kept for the case that the cells beside it go to its neighbour (two
    teleports on one shared cell, beta 2026-10-23: the second hunt of z 6 31657 / 31659 had no showcase at all): a
    bare non-PZ tile, or one that holds only the ground and the `counter` item (the install takes the counter off:
    hall_edit). None when there is none."""
    x, y, z = pos
    rows = room['teleportRows']
    if y not in rows:
        return None
    c = (x, room['cellRows'][rows.index(y)], z)
    if c in set(known):
        return c
    st = world.stack(c)
    if st is None or world.flags(c) & 1:
        return None
    if len(st) == 1 or (counter is not None and len(st) == 2 and st[1] == counter):
        return c
    return None


def sign_of(world, room, pos, sign_id):
    x, y, z = pos
    rows = room['teleportRows']
    if y not in rows:
        return None
    row = room['signRows'][rows.index(y)]
    for dx in (0, 1, -1):
        st = world.stack((x + dx, row, z))
        if st and sign_id in st:
            return (x + dx, row, z)
    return None


def hunts_of(rows):
    """the rows that are hunts (a `not a hunt` row keeps its teleport where it is and is not ordered; a `quest` row
    moves to the quest hall)"""
    return [r for r in rows if r['kind'] == KIND_HUNT]


def quests_of(rows):
    return [r for r in rows if r['kind'] == KIND_QUEST]


def cells_of(room, pos):
    """the two cells beside a teleport whatever stands in them now (a quest alcove's cells hold the rewards on show
    until the install clears them)"""
    x, y, z = pos
    rows = room['teleportRows']
    if y not in rows:
        return []
    row = room['cellRows'][rows.index(y)]
    return [(x - 1, row, z), (x + 1, row, z)]


def hall_slots(world, room, sign_id, base_rows, wing_slots, quest_rows=(), known=(), end_row=None, counter=None):
    """every hunt slot of the hall: the base hunts' places (from the CSV, whatever stands there now), the places of
    the quest teleports (their alcoves become hunt slots once the quests have moved) and the grown wings' slots. A
    display cell goes to the first slot (hall order) that claims it; a slot left with none takes its spare cell
    (spare_cell). A hunt without a place is not a slot. known, end_row: display_cells'; counter: spare_cell's."""
    slots = []
    quest_at = {(r['x'], r['y'], r['z']) for r in quest_rows}
    for r in list(hunts_of(base_rows)) + list(quest_rows):
        if r['x'] is None:
            continue
        p = (r['x'], r['y'], r['z'])
        if not world.has(p):
            raise HallError('%s: %d,%d,%d is not a tile of the map (hall_hunts.csv is for another map?)' % ((r['id'],) + p))
        cells = cells_of(room, p) if p in quest_at else display_cells(world, room, p, known, end_row)
        spare = None if p in quest_at else spare_cell(world, room, p, known, counter)
        slots.append(dict(teleport=p, sign=sign_of(world, room, p, sign_id), cells=cells, base=r['id'], spare=spare))
    have = {s['teleport'] for s in slots}
    for s in wing_slots:
        if tuple(s['teleport']) not in have:
            slots.append(dict(teleport=tuple(s['teleport']), sign=s.get('sign'), cells=list(s.get('cells') or []), base=None))
    return slots


def share_cells(slots, hall):
    taken = set()
    order = sorted(slots, key=lambda s: slot_key(hall, s['teleport']))
    for s in order:
        s['cells'] = [c for c in s['cells'] if c not in taken]
        taken.update(s['cells'])
    for s in order:
        sp = s.get('spare')
        if not s['cells'] and sp and sp not in taken:
            s['cells'] = [sp]
            taken.add(sp)
    return slots


# ------------------------------------------------------------------------------------------------ teleport tiles
def _node(data, i):
    """the OTBM node at data[i] (0xFE): (payload bytes unescaped, [child nodes], index after its 0xFF)"""
    if data[i] != 0xFE:
        raise HallError('internal: no node at %d' % i)
    i += 1
    pay = bytearray()
    kids = []
    while True:
        c = data[i]
        if c == 0xFD:
            pay.append(data[i + 1])
            i += 2
        elif c == 0xFE:
            kid, i = _node(data, i)
            kids.append(kid)
        elif c == 0xFF:
            return (bytes(pay), kids), i + 1
        else:
            pay.append(c)
            i += 1


# item attributes kept as they are when a tile is rewritten (OTBM: 1/2/6/7/19 strings, the rest fixed sizes)
ITEM_STRING_ATTRS = (1, 2, 6, 7, 19)
ITEM_FIXED_ATTRS = {10: 2, 12: 1, 13: 1, 14: 1, 15: 1, 16: 4, 17: 1, 18: 4, 20: 4, 21: 4, 22: 2}


def parse_tile(raw, pos):
    """a map tile node (escaped bytes, 0xFE .. 0xFF) as {'flags', 'ground', 'items': [(id, attrs)]}; refused when
    it is a house tile or holds anything we cannot write back unchanged (containers, texts, other attributes)"""
    import struct
    (pay, kids), _ = _node(raw, 0)
    if pay[0] != 5:
        raise HallError('%d,%d,%d is not a plain tile (a house tile?); not rewritten' % pos)
    k, flags, ground = 3, 0, None
    while k < len(pay):
        a = pay[k]
        if a == 3:
            flags = struct.unpack_from('<I', pay, k + 1)[0]
            k += 5
        elif a == 9:
            ground = struct.unpack_from('<H', pay, k + 1)[0]
            k += 3
        else:
            raise HallError('%d,%d,%d: tile attribute %d; not rewritten' % (pos + (a,)))
    items = []
    for kpay, kkids in kids:
        if kpay[0] != 6 or kkids:
            raise HallError('%d,%d,%d: an item with contents; not rewritten' % pos)
        iid = struct.unpack_from('<H', kpay, 1)[0]
        attrs, j, raw = {}, 3, bytearray()
        while j < len(kpay):
            a = kpay[j]
            if a == 4:
                attrs['aid'] = struct.unpack_from('<H', kpay, j + 1)[0]
                j += 3
            elif a == 5:
                attrs['uid'] = struct.unpack_from('<H', kpay, j + 1)[0]
                j += 3
            elif a == 8:
                attrs['tele'] = struct.unpack_from('<HHB', kpay, j + 1)
                j += 6
            elif a in ITEM_STRING_ATTRS:  # a sign's text, a description: kept byte for byte
                n = 3 + struct.unpack_from('<H', kpay, j + 1)[0]
                raw += kpay[j:j + n]
                j += n
            elif a in ITEM_FIXED_ATTRS:  # a count, charges, a date: kept byte for byte
                n = 1 + ITEM_FIXED_ATTRS[a]
                raw += kpay[j:j + n]
                j += n
            else:
                raise HallError('%d,%d,%d: item %d has attribute %d; not rewritten' % (pos + (iid, a)))
        if raw:
            attrs['raw'] = bytes(raw)
        items.append((iid, attrs))
    return dict(flags=flags, ground=ground, items=items)


def with_portal(tile, portal, dest, grounds=None):
    """the tile with no teleport item (dest None) or with one leading to dest, first after the ground. A tile whose
    ground is its first item node (the grown wings' copies) keeps it first: the teleport goes after it (before, it went
    in front of the ground). grounds: the ground item ids (items.otb), else the first item node is taken for one."""
    items = [(i, a) for i, a in tile['items'] if i != portal]
    if dest is not None:
        at = 0
        if not tile['ground'] and items and (grounds is None or items[0][0] in grounds):
            at = 1
        items.insert(at, (portal, {'tele': tuple(dest)}))
    return dict(flags=tile['flags'], ground=tile['ground'], items=items)


def portal_state(world, pos, portal):
    """None (no teleport item) or the destination of the tile's teleport ((0, 0, 0) without one)"""
    st = world.stack(pos)
    if not st or portal not in st:
        return None
    return tuple(world.tele.get(pos) or (0, 0, 0))


# ------------------------------------------------------------------------------------------------ the CLI
def main(argv):
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    import install_content_areas as T
    if cmd == 'show':
        path = rest[rest.index('--csv') + 1] if '--csv' in rest else CSV_PATH
        rows = read_csv(path) or []
        cfg = T.load_config()
        for r in order_hunts(rows):
            print('%-22s %-15s  %4d (%4d-%-4d) %-10s %s %s' % (r['id'], ('z%d %5d %5d' % (r['z'], r['x'], r['y']))
                  if r['x'] is not None else 'added', r['level'], r['lo'], r['hi'], r['kind'], r['monsters'], r['note']))
        return 0
    if cmd == 'band':
        # band DATA_DIR X,Y,Z: the level band and top monsters around a destination (for a hunt added by hand)
        import gen_bounty_pool as B
        import patch_base_towns
        if len(rest) != 2:
            print(__doc__)
            return 2
        dest = tuple(int(v) for v in rest[1].split(','))
        text = open(T.spawn_path(patch_base_towns.map_path(rest[0])), encoding='latin-1').read()
        levels = {k: B.estimate_level(m) for k, m in B.load_monsters(rest[0]).items()}
        got = hunt_band(spawn_points(text), levels, dest)
        if not got:
            sys.exit('no monster spawns near %s' % (dest,))
        print('level %d (%d-%d) %s' % (got[2], got[0], got[1], '|'.join(got[3])))
        return 0
    if cmd == 'derive':
        pos = [a for a in rest if not a.startswith('--')]
        if len(pos) != 1:
            print(__doc__)
            return 2
        mp = rest[rest.index('--map') + 1] if '--map' in rest else None
        if mp in pos:
            pos.remove(mp)
        if os.path.exists(CSV_PATH) and '--force' not in rest:
            sys.exit('%s exists (review it, or --force to derive it again)' % CSV_PATH)
        try:
            rows = derive(pos[0], T.load_config(), map_path=mp, keep=read_csv() if os.path.exists(CSV_PATH) else None)
        except HallError as e:
            sys.exit('refused: %s' % e)
        write_csv(rows)
        print('%d base hunt teleport(s) -> %s' % (len(rows), CSV_PATH))
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
