#!/usr/bin/env python3
"""Find floor changes that lead nowhere (server/README.md "Dead holes (O262)").

usage: python3 -I server/tools/check_dead_holes.py MAP.otbm [--items items.otb] [--xml items.xml] [--plans DIR ...]
                                                   [--csv FILE] [--all] [--quiet]

Owner, 2026-10-26: "esse buraco nao leva a lugar nenhum" (a dirt hole on a grass patch beside grey stone ruins that
drops into nothing). The checker reads the map (tools/map/otbm.py, numpy; about a minute for the base map) and every
tile that carries a floor change item, and works out where the engine puts a creature that steps on it:
  down      items.xml floorchange "down" (holes, pitfalls, trapdoors, stairs down): the same x,y one floor below
            (z + 1), then moved by the floor change of THAT tile as the engine does (the first of south-alt -2 y, east-alt -2 x,
            south -1 y, east -1 x, west +1 x; a north stair below does not move it)
  up        floorchange north / south / east / west (ramps, stairs up, roofs): z - 1 and one tile in that direction
            (the alt kinds two tiles)
  ladder    items named ladder or rope (use actions that go up): z - 1, the tile or any of its 8 neighbours
  grate     sewer grates (a use action that goes down): z + 1, the tile or any of its 8 neighbours
The floor change flags come from items.xml (`floorchange` of an id or a fromid / toid range) and the bits 8-12 of
items.otb (down, north, east, south, west); the use-action kinds from the item names. A tile counts its items together.
A landing is dead when
  void     the destination has no tile, or a tile with no ground
  blocked  it has a ground but an item that blocks walking (flag block solid)
Only a tile a creature can stand on counts: it has a ground and no blocking item (roof pieces, rails, bridges' ropes
on bare tiles are no holes). A change is dead when its only destination (down, up) or every candidate (ladder, grate) is dead. Prints one line per
dead change: x y z, kind, the item, why, where it would land, the area it lies in (the plans of server/tools/areaplan/
plans, chronicle, rooms, events and inbox: origin, size, floors; else `base map`), then totals by kind and by area.
--all also lists the live ones. --csv FILE writes the dead ones as the patch list of patch_dead_holes.py
(x,y,z,item,action,ground,kind,why,area; `remove` takes the item off, `ground` swaps a ground that is itself the floor
change for the plain ground round it). Exit 0 when none is dead, 1 otherwise (2 on a usage error).
Not in CI: it needs the map (a unit test on a synthetic map runs there: tools/check_dead_holes_test.py).
"""
import csv, glob, json, os, re, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

GROUP_GROUND = 1
FLAG_BLOCK = 1                      # block solid (items.otb; block path only steers path finding: stairs, holes and fields have it)
OTB_FC = {8: 'down', 9: 'north', 10: 'east', 11: 'south', 12: 'west'}
STEP = {'north': (0, -1), 'south': (0, 1), 'east': (1, 0), 'west': (-1, 0),
        'northalt': (0, -2), 'southalt': (0, 2), 'eastalt': (2, 0), 'westalt': (-2, 0)}
# a tile below a hole that is a stair moves the landing off its foot (the other way round than going up)
LAND = {k: (-v[0], -v[1]) for k, v in STEP.items()}
UP_NAME = re.compile(r'^(ladder|rope-ladder|rope spot)$', re.I)
DOWN_NAME = re.compile(r'^(jammed )?sewer grate$', re.I)
ROPE_SPOTS = (384, 418, 8278, 8592)   # the grounds a rope climbs from (their name is just the floor's)
PLAN_DIRS = ('plans', 'chronicle', 'rooms', 'annexes', 'events', 'inbox')
AREA_BASE = 'base map'


def read_xml_floorchange(xml_path):
    """{item id: set of floor change values} from items.xml (id and fromid / toid entries)"""
    out = {}
    if not xml_path or not os.path.isfile(xml_path):
        return out
    text = open(xml_path, encoding='latin-1').read()
    for m in re.finditer(r'<item\b([^>]*?)(/?)>', text):
        if m.group(2):
            continue
        end = text.find('</item>', m.end())
        body = text[m.end():end if end >= 0 else m.end()]
        vals = re.findall(r'key="floorchange"\s+value="(\w+)"', body)
        if not vals:
            continue
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        if 'id' in a:
            ids = [int(a['id'])]
        elif 'fromid' in a and 'toid' in a:
            ids = range(int(a['fromid']), int(a['toid']) + 1)
        else:
            continue
        for i in ids:
            out.setdefault(i, set()).update(v.lower() for v in vals)
    return out


class Kinds:
    """what the check needs to know of an item id: ground, blocking, its floor change values, its name"""

    def __init__(self, ground, block, fc, names):
        self.ground, self.block, self.fc, self.names = set(ground), set(block), fc, names

    @classmethod
    def from_files(cls, otb, xml=None):
        import numpy as np
        from itemdb import ItemDB
        db = ItemDB(otb, xml)
        fc = read_xml_floorchange(xml)
        for sid in np.flatnonzero((db.flags >> 8) & 31):
            for bit, name in OTB_FC.items():
                if int(db.flags[sid]) & (1 << bit):
                    fc.setdefault(int(sid), set()).add(name)
        names = {i: db.name[i] for i in range(len(db.name)) if db.name[i]}
        return cls((int(i) for i in np.flatnonzero(db.group == GROUP_GROUND)),
                   (int(i) for i in np.flatnonzero(db.flags & FLAG_BLOCK)), fc, names)

    def label(self, iid):
        """a short kind for an item: hole, pitfall, trapdoor, stairs, ramp, ladder, rope, grate, roof, other"""
        n = self.names.get(iid, '').lower()
        if iid in ROPE_SPOTS:
            return 'rope'
        for w in ('pitfall', 'trapdoor', 'hole', 'stair', 'ramp', 'ladder', 'rope', 'grate', 'roof'):
            if w in n:
                return 'stairs' if w == 'stair' else w
        return 'other'

    def action(self, iid):
        """'up' / 'down' for an item that changes the floor by a use action (no floorchange value), else None"""
        if iid in self.fc:
            return None
        n = self.names.get(iid, '')
        if iid in ROPE_SPOTS:
            return 'up'
        if UP_NAME.search(n):
            return 'up'
        if DOWN_NAME.search(n):
            return 'down'
        return None


class World:
    """the tiles the check looks at: tile(x, y, z) -> list of item ids (ground first) or None"""

    def __init__(self, tiles):
        self.tiles = tiles

    def tile(self, x, y, z):
        return self.tiles.get((x, y, z))


class MapWorld:
    def __init__(self, m):
        self.m = m

    def tile(self, x, y, z):
        if not (0 <= z <= 15 and x >= 0 and y >= 0):
            return None
        i = self.m.find(x, y, z)
        return None if i < 0 else [int(s) for s in self.m.stack(i)]


def tile_fc(kinds, ids):
    """(floor change values of the tile, first use action direction or None)"""
    vals, act = set(), None
    for s in ids:
        vals |= kinds.fc.get(s, set())
        if act is None:
            act = kinds.action(s)
    return vals, act


def landing_state(kinds, world, p):
    """None when a creature can stand on p, else 'void' (no tile or no ground) or 'blocked'"""
    ids = world.tile(*p)
    if not ids:
        return 'void'
    if ids[0] not in kinds.ground:
        return 'void'
    if any(s in kinds.block for s in ids):
        return 'blocked'
    return None


def around9(p):
    return [(p[0] + dx, p[1] + dy, p[2]) for dy in (0, -1, 1) for dx in (0, -1, 1)]


def destination(kinds, world, p, vals, act):
    """(direction, [candidate landing positions]) of a floor change at p; direction 'down' / 'up'"""
    x, y, z = p
    if 'down' in vals:
        d = (x, y, z + 1)
        below = world.tile(*d)
        if below:
            bv = set()
            for s in below:
                bv |= kinds.fc.get(s, set())
            for k in ('southalt', 'eastalt', 'south', 'east', 'west'):   # the engine takes the first that is there
                if k in bv:
                    d = (d[0] + LAND[k][0], d[1] + LAND[k][1], d[2])
                    break
        return 'down', [d]
    steps = [k for k in STEP if k in vals]
    if steps:
        d = (x, y, z - 1)
        for k in steps:
            d = (d[0] + STEP[k][0], d[1] + STEP[k][1], d[2])
        return 'up', [d]
    if act == 'up':
        return 'up', around9((x, y, z - 1))
    if act == 'down':
        return 'down', around9((x, y, z + 1))
    return None, []


def check_tile(kinds, world, p):
    """None when the tile has no floor change; else dict(dir, land (first candidate), why, dead). `why` is the state of
    the best candidate: None when one is walkable"""
    ids = world.tile(*p)
    if not ids:
        return None
    vals, act = tile_fc(kinds, ids)
    if not vals and not act:
        return None
    # a tile nobody can stand on (no ground, or a blocking item, floor change or not: roof pieces, rails) leads
    # nowhere because nobody gets there; it is not a hole
    if ids[0] not in kinds.ground or any(s in kinds.block for s in ids):
        return None
    direction, cands = destination(kinds, world, p, vals, act)
    if direction is None:
        return None
    if not (0 <= cands[0][2] <= 15):
        return dict(dir=direction, land=cands[0], why='void', dead=True)
    states = [landing_state(kinds, world, c) for c in cands]
    if any(s is None for s in states):
        return dict(dir=direction, land=cands[states.index(None)], why=None, dead=False)
    why = 'void' if all(s == 'void' for s in states) else 'blocked'
    return dict(dir=direction, land=cands[0], why=why, dead=True)


def changes(kinds, world, positions):
    """[(pos, items, result)] for every position with a floor change, sorted"""
    out = []
    for p in sorted(positions):
        r = check_tile(kinds, world, p)
        if r is None:
            continue
        ids = world.tile(*p)
        fcs = [s for s in ids if kinds.fc.get(s) or kinds.action(s)]
        out.append((p, fcs, r))
    return out


# ------------------------------------------------------------------------------------------------ areas
def read_areas(plan_dirs):
    """[(id, name, x0, y0, z0, x1, y1, z1)] of the plans' boxes (origin, size, floors; floor 1 is the top, the next
    floors one level deeper)"""
    out = []
    for d in plan_dirs:
        files = glob.glob(os.path.join(d, '*.json')) + glob.glob(os.path.join(d, '*', 'plan.json'))
        for f in sorted(files):
            try:
                plan = json.load(open(f, encoding='utf-8'))
                o, size = plan.get('origin'), plan['size']
                if not o:
                    continue
                out.append((plan['id'], plan.get('name', ''), o['x'], o['y'], o['z'], o['x'] + size[0] - 1,
                            o['y'] + size[1] - 1, o['z'] + int(plan.get('floors', 1)) - 1))
            except (OSError, ValueError, KeyError, TypeError):
                continue
    return out


def area_of(areas, p):
    for a in areas:
        if a[2] <= p[0] <= a[5] and a[3] <= p[1] <= a[6] and a[4] <= p[2] <= a[7]:
            return a[0]
    return AREA_BASE


def default_plan_dirs():
    base = os.path.join(HERE, 'areaplan')
    return [os.path.join(base, d) for d in PLAN_DIRS]


# ------------------------------------------------------------------------------------------------ run
def positions_with_changes(m, kinds):
    """tile positions of the map that hold a floor change item (vectorised over the item array)"""
    import numpy as np
    ids = set(kinds.fc) | set(ROPE_SPOTS) | {i for i in kinds.names if kinds.action(i)}
    mask = np.isin(m.items, np.fromiter(ids, np.uint32))
    idx = np.flatnonzero(mask)
    if not len(idx):
        return []
    owner = np.repeat(np.arange(len(m)), m.tiles['cnt'].astype(np.int64))   # the items array is in tile order
    t = np.unique(owner[idx])
    return sorted(zip(m.tiles['x'][t].tolist(), m.tiles['y'][t].tolist(), m.tiles['z'][t].tolist()))


def report(rows, areas, show_all=False, out=print):
    """prints the dead changes (and the live ones with show_all); returns (dead rows, Counter by kind, Counter by area)"""
    dead, by_kind, by_area = [], Counter(), Counter()
    for p, ids, r in rows:
        if not r['dead'] and not show_all:
            continue
        area = area_of(areas, p)
        out('%d %d %d  %s  item %s  %s  %s  lands %s  %s' % (
            p[0], p[1], p[2], r['dir'], ','.join(str(i) for i in ids), 'DEAD' if r['dead'] else 'ok',
            r['why'] or '', '%d,%d,%d' % r['land'], area))
        if r['dead']:
            dead.append((p, ids, r, area))
            by_area[area] += 1
    return dead, by_area


def labelled(kinds, dead):
    by_kind = Counter()
    for p, ids, r, area in dead:
        by_kind['%s/%s' % (kinds.label(ids[0]), r['dir'])] += 1
    return by_kind


def plain_ground(kinds, world, p, reach=3):
    """the ground a dead floor change that IS a ground (stairs, an open pitfall, a hole) turns into: the commonest
    plain walkable ground of the tiles round it on the same floor (nearest ring that has one; the smaller id on a
    tie), or None"""
    for r in range(1, reach + 1):
        count = Counter()
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                q = (p[0] + dx, p[1] + dy, p[2])
                ids = world.tile(*q)
                if ids and landing_state(kinds, world, q) is None and not (kinds.fc.get(ids[0]) or kinds.action(ids[0])):
                    count[ids[0]] += 1
        if count:
            return sorted(count.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
    return None


def patch_rows(kinds, world, dead):
    """[(x, y, z, item, action, ground, kind, why, area)]: one row per floor change item of a dead tile. `remove` takes
    the item off; `ground` swaps the tile's ground (the item IS the ground) for `ground`, the plain one round it;
    `none` when no plain ground is near (the patch leaves it)"""
    rows = []
    for p, ids, r, area in dead:
        for iid in sorted(set(ids)):
            world_ids = world.tile(*p)
            if world_ids[0] == iid:
                g = plain_ground(kinds, world, p)
                action, ground = ('ground', g) if g else ('none', '')
            else:
                action, ground = 'remove', ''
            rows.append((p[0], p[1], p[2], iid, action, ground, '%s/%s' % (kinds.label(iid), r['dir']), r['why'], area))
    return rows


def write_csv(path, rows):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write('# dead floor changes of the installed map (check_dead_holes.py --csv), the patch list of patch_dead_holes.py:\n')
        f.write('# remove = the item goes; ground = the tile\'s ground (the item itself) becomes `ground`; positions only\n')
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['x', 'y', 'z', 'item', 'action', 'ground', 'kind', 'why', 'area'])
        for r in rows:
            w.writerow(r)


def sibling(map_path, name):
    for d in (os.path.dirname(os.path.abspath(map_path)), os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(map_path))), 'items')):
        f = os.path.join(d, name)
        if os.path.isfile(f):
            return f
    return None


def main(argv):
    opts, args, plans = {}, [], []
    flags = set()
    k = 0
    while k < len(argv):
        a = argv[k]
        if a in ('--items', '--xml', '--csv'):
            if k + 1 >= len(argv):
                print('%s needs a value' % a)
                return 2
            opts[a] = argv[k + 1]
            k += 2
        elif a == '--plans':
            if k + 1 >= len(argv):
                print('--plans needs a value')
                return 2
            plans.append(argv[k + 1])
            k += 2
        elif a in ('--all', '--quiet'):
            flags.add(a)
            k += 1
        elif a.startswith('--'):
            print(__doc__)
            return 2
        else:
            args.append(a)
            k += 1
    if len(args) != 1:
        print(__doc__)
        return 2
    map_path = args[0]
    otb = opts.get('--items') or sibling(map_path, 'items.otb')
    xml = opts.get('--xml') or sibling(map_path, 'items.xml')
    if not otb or not os.path.isfile(otb):
        print('no items.otb next to the map; pass --items')
        return 2
    import otbm
    kinds = Kinds.from_files(otb, xml)
    m = otbm.load_otbm(map_path)
    world = MapWorld(m)
    rows = changes(kinds, world, positions_with_changes(m, kinds))
    areas = read_areas(plans or default_plan_dirs())
    out = (lambda *_: None) if '--quiet' in flags else print
    dead, by_area = report(rows, areas, '--all' in flags, out)
    by_kind = labelled(kinds, dead)
    print('%d floor change tile(s), %d dead' % (len(rows), len(dead)))
    for key, n in sorted(by_kind.items()):
        print('  kind %-16s %d' % (key, n))
    for key, n in sorted(by_area.items()):
        print('  area %-24s %d' % (key, n))
    if '--csv' in opts:
        write_csv(opts['--csv'], patch_rows(kinds, world, dead))
    return 1 if dead else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
