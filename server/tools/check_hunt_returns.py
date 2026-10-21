#!/usr/bin/env python3
"""Check that every hunt of the teleport hall has a way back (server/README.md "Hall order", "Ways back").

usage: python3 -I server/tools/check_hunt_returns.py DATA_DIR [--map FILE] [--csv FILE] [--config FILE]

Owner, 2026-10-20: "many teleports to hunts have no teleport back". A hunt of the hall (tools/hall_hunts.csv, kind
`hunt`) has its way back when
  - the map has a teleport within `returns.radius` tiles of its arrival, on its floor, that leads into the hall (the
    base server's own ways back stand one to three tiles from the arrival; install_content_areas.py makes them lead in
    front of the hunt's teleport), or
  - hunt_teleports_config.lua `returns` lists it and the tile startup will use is free: its `at`, else the nearest tile
    ChaosHuntTeleportsCore.pickReturnTile would take (the same rule here: reached on foot from the arrival, a ground
    and nothing blocking, no stairs or hole, no protection zone, no house, no teleport, nothing lying on it, not
    splitting the way between its neighbours).
The planned hunts have their camp portal: with data/lib/chaos_hunt_places.lua each placed plan must have its `exit`.
Prints one line per hunt and exits 1 when a hunt has no way back (2 on a usage error).
Run it on the server's data folder after install_content_areas.py (the map is read with tools/map/otbm.py, numpy;
about a minute for the base map; items.otb and items.xml give the item flags).
"""
import csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

CSV_PATH = os.path.join(HERE, 'hall_hunts.csv')
FLAG_BLOCK_SOLID, FLAG_BLOCK_PATH, FLAG_FLOOR_DOWN = 1, 4, 1 << 8
GROUP_GROUND, GROUP_TELEPORT = 1, 7
TF_PZ = 1


def read_hunts(path=CSV_PATH):
    """[{id, name, arrival, placed}] of the CSV's hunts (placed: the base server had a teleport for it in the hall)"""
    rows = csv.DictReader(line for line in open(path, encoding='utf-8') if not line.startswith('#'))
    out = []
    for r in rows:
        if r['kind'] != 'hunt':
            continue
        out.append(dict(id=r['id'], name=r['name'], placed=bool(r['x']),
                        arrival=(int(r['dest_x']), int(r['dest_y']), int(r['dest_z']))))
    return out


def in_hall(cfg, p):
    hall, room = cfg['hall'], cfg['room']
    return (p[2] in hall['floors'] and hall['x'][0] <= p[0] <= hall['x'][1]
            and room['rows'][0] <= p[1] <= room['rows'][1])


def map_way_back(cfg, tele, arrival, radius, want=None):
    """the map teleport within radius of the arrival (same floor) that leads into the hall (to `want` when given: the
    tile in front of the hunt's teleport), nearest first; or None"""
    best = None
    for p, d in tele.items():
        if p[2] != arrival[2] or not in_hall(cfg, d) or (want is not None and tuple(d) != tuple(want)):
            continue
        dist = max(abs(p[0] - arrival[0]), abs(p[1] - arrival[1]))
        if dist <= radius and (best is None or (dist, p) < best[0]):
            best = ((dist, p), p)
    return best[1] if best else None


def front_of(room, pos):
    """the tile in front of a hall teleport (hall_order.front_of)"""
    import hall_order
    return hall_order.front_of(room, pos)


def around(p):
    return [(p[0] + dx, p[1] + dy, p[2]) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dy]


def cuts_way(p, info):
    """as ChaosHuntTeleportsCore.cutsWay: the walkable neighbours must reach each other side by side"""
    walk = [q for q in around(p) if (info(q) or {}).get('walk')]
    if not walk:
        return True
    seen, stack = {walk[0]}, [walk[0]]
    while stack:
        a = stack.pop()
        for b in walk:
            if b not in seen and abs(a[0] - b[0]) + abs(a[1] - b[1]) == 1:
                seen.add(b)
                stack.append(b)
    return len(seen) < len(walk)


def pick_return_tile(arrival, radius, info, prefer=None):
    """as ChaosHuntTeleportsCore.pickReturnTile: `prefer` when it fits, else the nearest on foot (north to south,
    west to east); None when no tile fits. info(pos) -> {'walk', 'spot'} or None."""
    steps, order, queue = {arrival: 0}, [], [arrival]
    for p in queue:
        for q in around(p):
            if q in steps or max(abs(q[0] - arrival[0]), abs(q[1] - arrival[1])) > radius:
                continue
            if (info(q) or {}).get('walk'):
                steps[q] = steps[p] + 1
                queue.append(q)
                order.append(q)

    def fits(q):
        return steps.get(q, 0) > 0 and (info(q) or {}).get('spot') and not cuts_way(q, info)
    if prefer is not None and tuple(prefer)[2] == arrival[2] and fits(tuple(prefer)):
        return tuple(prefer)
    for q in sorted(order, key=lambda q: (steps[q], q[1], q[0])):
        if fits(q):
            return q
    return None


def check(cfg, hunts, tele, info, places=None):
    """(lines, missing ids): every hunt's way back; places: the places file's text (the planned hunts' exits)"""
    ret = cfg.get('returns') or {}
    radius = int(ret.get('radius') or 4)
    listed = {r['id']: r for r in ret.get('list') or []}
    lines, missing = [], []
    # with the places file: where each hunt's teleport stands now, so the way back must lead in front of it
    want = {}
    for m in re.finditer(r'\{id = "([^"]+)",[^\n]*?teleport = \{x = (\d+), y = (\d+), z = (\d+)\}', places or ''):
        want[m.group(1)] = front_of(cfg['room'], (int(m.group(2)), int(m.group(3)), int(m.group(4))))
    for h in hunts:
        r = listed.get(h['id'])
        if r:
            at = r.get('at')
            at = (at['x'], at['y'], at['z']) if at else None
            p = pick_return_tile(h['arrival'], radius, info, at)
            if p is None:
                missing.append(h['id'])
                lines.append('%s: NO way back (listed, but no free tile within %d of %s)' % (h['id'], radius, h['arrival']))
            else:
                lines.append('%s: way back at startup %s%s' % (h['id'], p, '' if p == at else ' (not its `at` %s)' % (at,)))
            continue
        p = map_way_back(cfg, tele, h['arrival'], radius, want.get(h['id']))
        if p:
            lines.append('%s: way back on the map %s -> %s' % (h['id'], p, tele[p]))
        elif want.get(h['id']) and map_way_back(cfg, tele, h['arrival'], radius):
            missing.append(h['id'])
            lines.append('%s: the way back near %s leads in front of another teleport, not %s (run install_content_areas.py)'
                         % (h['id'], h['arrival'], want[h['id']]))
        else:
            missing.append(h['id'])
            lines.append('%s: NO way back near %s (list it in hunt_teleports_config.lua returns)' % (h['id'], h['arrival']))
    if places is not None:
        for m in re.finditer(r'\{id = "([^"]+)",[^\n]*?exit = (nil|\{[^}]*\})', places):
            if m.group(2) == 'nil':
                missing.append(m.group(1))
                lines.append('%s: NO camp portal (exit) in the places file' % m.group(1))
            else:
                lines.append('%s: camp portal %s' % (m.group(1), m.group(2)))
    return lines, missing


def map_info(data_dir, map_path, extra=()):
    """(teleports {pos: dest}, info(pos)) from the map and items.otb / items.xml; extra: more teleport item ids (the
    hall's own portal item, which items.otb does not always mark as a teleport)"""
    import numpy as np
    import otbm
    from itemdb import ItemDB, C
    xml = os.path.join(data_dir, 'items', 'items.xml')
    db = ItemDB(os.path.join(data_dir, 'items', 'items.otb'), xml if os.path.isfile(xml) else None)
    if not hasattr(db, 'cls'):
        db.classify()
    m = otbm.load_otbm(map_path)
    ids = {int(i) for i in np.flatnonzero(db.group == GROUP_TELEPORT)} | {int(i) for i in extra}
    if os.path.isfile(xml):
        text = open(xml, encoding='latin-1').read()
        for mm in re.finditer(r'<item\b([^>]*?)>(.*?)</item>', text, re.S):
            if re.search(r'key="type"\s+value="teleport"', mm.group(2)):
                a = dict(re.findall(r'(\w+)="([^"]*)"', mm.group(1)))
                if 'id' in a:
                    ids.add(int(a['id']))
    tele = {}
    for ti, _iid, d in otbm.teleports(m, ids):
        tele[(int(m.tiles['x'][ti]), int(m.tiles['y'][ti]), int(m.tiles['z'][ti]))] = tuple(d)

    def info(p):
        i = m.find(*p)
        if i < 0:
            return None
        st = [int(a) for a in m.stack(i)]
        if not st or int(db.group[st[0]]) != GROUP_GROUND:
            return None
        block = any(int(db.flags[s]) & (FLAG_BLOCK_SOLID | FLAG_BLOCK_PATH) for s in st)
        stairs = any(int(db.cls[s]) == C['floorchg'] or int(db.flags[s]) & FLAG_FLOOR_DOWN for s in st)
        walk = not block and not stairs
        lying = [s for s in st[1:] if int(db.order[s]) == 0]  # down items: not borders, walls or tops
        spot = (walk and not int(m.tiles['flags'][i]) & TF_PZ and not int(m.tiles['house'][i]) and p not in tele
                and not any(int(db.group[s]) == GROUP_TELEPORT or s in ids for s in st) and not lying)
        return dict(walk=walk, spot=spot)
    return tele, info


def main(argv):
    opts, args = {}, []
    k = 0
    while k < len(argv):
        a = argv[k]
        if a in ('--map', '--csv', '--config'):
            if k + 1 >= len(argv):
                print('%s needs a value' % a)
                return 2
            opts[a] = argv[k + 1]
            k += 2
            continue
        args.append(a)
        k += 1
    if len(args) != 1:
        print(__doc__)
        return 2
    data_dir = args[0]
    import install_content_areas as I
    cfg = I.load_config(opts.get('--config', I.CONFIG))
    map_path = opts.get('--map')
    if not map_path:
        world = os.path.join(data_dir, 'world')
        maps = sorted(n for n in os.listdir(world) if n.endswith('.otbm'))
        if len(maps) != 1:
            print('pass --map FILE: %s holds %d .otbm files' % (world, len(maps)))
            return 2
        map_path = os.path.join(world, maps[0])
    hunts = read_hunts(opts.get('--csv', CSV_PATH))
    items = cfg.get('items') or {}
    tele, info = map_info(data_dir, map_path, [items.get('portal', 1387)] + list(items.get('questPortals') or []))
    pf = os.path.join(data_dir, I.PLACES_REL)
    places = open(pf, encoding='utf-8').read() if os.path.isfile(pf) else None
    lines, missing = check(cfg, hunts, tele, info, places)
    for line in lines:
        print(line)
    if places is None:
        print('no %s: the planned hunts\' camp portals are not checked (install_content_areas.py)' % pf)
    print('%d hunt(s) checked, %d without a way back' % (len(hunts), len(missing)))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
