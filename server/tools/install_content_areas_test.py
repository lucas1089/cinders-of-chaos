#!/usr/bin/env python3
"""python3 -I server/tools/install_content_areas_test.py : install_content_areas.py on a synthetic tiny world (a room
of one alcove module and an end with its temple teleport, a tiny compiled area): the dry run writes nothing; the
install grows the room by copying the module (no teleport in the copies), moves the end with its teleport
destination, places the area, adds its spawns and two display monsters per slot, writes the places file; a second run
changes nothing; a taken target tile, an area on map tiles and a changed plan are refused; a fixed area (the
chronicle folder) is placed at its origin with its spawns but gets no teleport and no places line; a fixed plan without
an origin is left out; two areas on one tile are refused. No base server needed."""
import hashlib, json, os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import install_content_areas as T  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


G, WALL, COUNTER, SIGN, PORTAL, STONE = 100, 200, 1642, 5360, 1387, 1421
Z = 6
ROWS = (9, 17)


def esc(b):
    return T._esc(b)


def otbm_file(tiles):
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + T.tile_nodes(tiles) + towns + b'\xFF\xFF'


def tile(*ids, flags=1, tele=None):
    items = []
    for i in ids:
        items.append((i, {'tele': tele} if (i == PORTAL and tele) else {}))
    return dict(ground=None, items=items, flags=flags)


def room_tiles():
    """module columns 10..13 (gap, wall, teleport, wall; copied from column 14 on: teleports at 16 and 20), the end columns 14..15 with a temple teleport at 14,13"""
    t = {}
    for y in range(ROWS[0], ROWS[1] + 1):
        corridor = 12 <= y <= 14
        t[(10, y, Z)] = tile(G) if corridor else tile(G, WALL)
        for x in (11, 13):
            if y in (10, 16):
                t[(x, y, Z)] = tile(G, flags=0)  # the closed cells
            else:
                t[(x, y, Z)] = tile(G) if corridor else tile(G, WALL)
        col = {9: (G, COUNTER, SIGN), 10: (G, COUNTER), 11: (G, PORTAL, STONE), 15: (G, PORTAL, STONE), 16: (G, COUNTER),
               17: (G, COUNTER, SIGN)}.get(y, (G,))
        t[(12, y, Z)] = tile(*col)
    for y in range(11, 16):
        t[(14, y, Z)] = tile(G, PORTAL, tele=(500, 500, 7)) if y == 13 else tile(G, WALL)
    for y in range(12, 15):
        t[(15, y, Z)] = tile(G, WALL)
    return t


CFG = {
    'aid': 47930, 'items': {'portal': PORTAL, 'sign': SIGN}, 'displaySpawntime': 90,
    'room': {'z': Z, 'rows': list(ROWS), 'teleportRows': [11, 15], 'cellRows': [10, 16], 'signRows': [9, 17],
             'east': {'module': [10, 13], 'cap': [14, 15], 'modules': 2}, 'back': {'x': 11, 'y': 13, 'z': Z}},
    'plans': [{'id': 'tiny_hunt', 'monster': 'Bog Rat'}, {'id': 'other_hunt', 'monster': 'Bat'}],
}


def make_area(out, pid, origin, n=3, ground=G):
    os.makedirs(out, exist_ok=True)
    ox, oy, oz = origin
    tiles = {(ox + i, oy, oz): dict(ground=ground, items=[], flags=0) for i in range(n)}
    tiles[(ox + 1, oy, oz)]['items'] = [(PORTAL, {'aid': 47951})]
    open(os.path.join(out, pid + '.otbm'), 'wb').write(otbm_file(tiles))
    json.dump({'id': pid, 'name': pid.replace('_', ' ').title(), 'origin': list(origin), 'arrival': [ox, oy, oz],
               'exit': {'at': [ox + 1, oy, oz], 'aid': 47951, 'to': None}},
              open(os.path.join(out, pid + '.json'), 'w'))
    open(os.path.join(out, pid + '-spawn.xml'), 'w').write(
        '<?xml version="1.0"?>\n<spawns>\n\t<spawn centerx="%d" centery="%d" centerz="%d" radius="1">\n'
        '\t\t<monster name="Bog Rat" x="0" y="0" z="%d" spawntime="60" />\n\t</spawn>\n</spawns>\n' % (ox + 2, oy, oz, oz))


def setup(root, extra=None, drop=()):
    srv = os.path.join(root, 'srv')
    os.makedirs(os.path.join(srv, 'data', 'world'))
    os.makedirs(os.path.join(srv, 'data', 'scripts'))
    open(os.path.join(srv, 'config.lua'), 'w').write('mapName = "w"\n')
    world = room_tiles()
    world.update(extra or {})
    for p in drop:
        world.pop(p, None)
    open(os.path.join(srv, 'data', 'world', 'w.otbm'), 'wb').write(otbm_file(world))
    open(os.path.join(srv, 'data', 'world', 'w-spawn.xml'), 'w').write(
        '<?xml version="1.0"?>\n<spawns>\n\t<spawn centerx="11" centery="10" centerz="6" radius="1">\n'
        '\t\t<monster name="Hydra" x="0" y="0" z="6" spawntime="120" />\n\t</spawn>\n</spawns>\n')
    plans = os.path.join(root, 'plans')
    os.makedirs(plans)
    comp = {}
    for pid, origin in (('tiny_hunt', (1000, 1000, 7)), ('other_hunt', (1100, 1000, 8))):
        json.dump({'id': pid, 'name': pid, 'level': [300, 400] if pid == 'tiny_hunt' else [500, 600],
                   'origin': dict(zip('xyz', origin))}, open(os.path.join(plans, pid + '.json'), 'w'))
        comp[pid] = os.path.join(root, 'out', pid)
        make_area(comp[pid], pid, origin)
    return srv, plans, comp


def digest(srv):
    h = hashlib.sha1()
    for rel in ('data/world/w.otbm', 'data/world/w-spawn.xml', 'data/lib/chaos_hunt_places.lua'):
        p = os.path.join(srv, rel)
        h.update(open(p, 'rb').read() if os.path.exists(p) else b'-')
    return h.hexdigest()


def run(srv, plans, comp, **kw):
    log = []
    kw.setdefault('fixed_dirs', ())
    res = T.run(os.path.join(srv, 'data'), plans_dir=plans, config=CFG, compiled=comp, log=log.append, **kw)
    return res, log


BLOCK = {WALL, COUNTER}


def map_state(srv):
    """(stacks, teleport destinations, flags) of the synthetic world as written"""
    m = otbm.load_otbm(os.path.join(srv, 'data', 'world', 'w.otbm'))
    stacks, flags = {}, {}
    for i in range(len(m.tiles['x'])):
        p = (int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i]))
        stacks[p] = [int(a) for a in m.stack(i)]
        flags[p] = int(m.tiles['flags'][i])
    tele = {(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i])): tuple(d) for i, _iid, d in otbm.teleports(m, [PORTAL])}
    return stacks, tele, flags


def reachable(stacks, start, z):
    """tiles of floor z a player reaches from start (a tile with a wall or a counter blocks)"""
    seen, todo = {start}, [start]
    while todo:
        x, y, _z = todo.pop()
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + d[0], y + d[1], z)
            if q in seen or q not in stacks or BLOCK & set(stacks[q]):
                continue
            seen.add(q)
            todo.append(q)
    return seen


def hall_order_checks(root):
    import hall_order as H
    # the band of the monsters around a destination: weighted 15th-85th percentile, to 5s
    # the band of the monsters around a destination: weighted 20th-80th percentile to 5s, and the median (its level)
    check(H.band([(42, 10), (73, 10), (124, 1)]) == (40, 75, 73), 'band %s' % (H.band([(42, 10), (73, 10), (124, 1)]),))
    check(H.band([(10, 8), (400, 1)])[2] == 10, 'one strong monster does not move the level')
    check(H.band([]) is None and H.band([(3, 1)]) == (1, 6, 3), 'band edge cases')
    pts = [(105, 100, 7, 'Rat')] * 6 + [(110, 100, 7, 'Dragon')] * 4 + [(300, 300, 7, 'Demon')] * 9
    got = H.hunt_band(pts, {'rat': 5, 'dragon': 42, 'demon': 124}, (100, 100, 7))
    check(got and got[3] == ['Rat', 'Dragon'] and got[0] == 5, 'monsters near the destination only: %s' % (got,))
    down = [(130, 100, 10, 'Demon')] * 9
    got = H.hunt_band(down, {'demon': 124}, (100, 100, 7))
    check(got and got[3] == ['Demon'] and got[2] == 124, 'a cave whose hunt is three floors down: %s' % (got,))
    check(H.hunt_band([], {}, (100, 100, 7)) is None, 'nothing spawns: no band')
    # a teleport tile read from the map and written back unchanged but for the teleport
    t = dict(flags=1, ground=G, items=[(PORTAL, {'tele': (700, 700, 7)}), (STONE, {})])
    raw = T.tile_nodes({(12, 11, Z): t})
    s = raw.index(b'\xFE', 1)  # the tile node inside its area node
    tile_raw = raw[s:-1]
    back = H.parse_tile(tile_raw, (12, 11, Z))
    check(back == t, 'tile parsed back: %s' % back)
    check(H.with_portal(back, PORTAL, None)['items'] == [(STONE, {})], 'teleport taken off')
    check(H.with_portal(back, PORTAL, (1, 2, 3))['items'][0] == (PORTAL, {'tele': (1, 2, 3)}), 'teleport put on')
    cfg = json.loads(json.dumps(CFG))
    cfg['hall'] = {'enabled': True, 'floors': [Z], 'x': [0, 40], 'endRow': 13, 'temple': [500, 500, 7], 'labels': [],
                   'closed': {'wall': WALL, 'decor': [STONE]}}
    # two base hunts on the module's teleports (12,11) and (12,15): one low, one high; the content hunts in between
    extra = {(12, 11, Z): tile(G, PORTAL, STONE, tele=(700, 700, 7)), (12, 15, Z): tile(G, PORTAL, STONE, tele=(710, 700, 7)),
             (30, 11, Z): tile(G, PORTAL, tele=(800, 800, 7)),
             # the hunts' own ways back, beside their arrival: in front of the teleport where the base server had it
             (701, 700, 7): tile(G, PORTAL, tele=(12, 12, Z)), (711, 701, 7): tile(G, PORTAL, tele=(12, 14, Z))}
    srv, plans, comp = setup(os.path.join(root, 'hallorder'), extra)
    csvp = os.path.join(root, 'hallorder', 'hall_hunts.csv')
    rows = [dict(id='base_6_12_11', z=Z, x=12, y=11, dest_x=700, dest_y=700, dest_z=7, name='Rat', lo=10, hi=40,
                 display='Hydra', spawntime=120, monsters='Rat'),
            dict(id='base_6_12_15', z=Z, x=12, y=15, dest_x=710, dest_y=700, dest_z=7, name='Dragon', lo=600, hi=700,
                 display='', spawntime=120, monsters='Dragon'),
            dict(id='base_6_30_11', z=Z, x=30, y=11, dest_x=800, dest_y=800, dest_z=7, kind='not a hunt', name='Hunt',
                 lo=1, hi=5, display='', spawntime=120, monsters='', note='a city')]
    H.write_csv(rows, csvp)
    check(H.read_csv(csvp)[0]['lo'] == 10, 'the CSV reads back')

    def go(**kw):
        return T.run(os.path.join(srv, 'data'), plans_dir=plans, config=cfg, compiled=comp, log=lambda s: None,
                     fixed_dirs=(), hall_csv=csvp, **kw)
    res = go()
    hall = res['hall']['assign']
    check(set(hall) == {'base_6_12_11', 'base_6_12_15', 'tiny_hunt', 'other_hunt'}, 'every hunt once, the city out: %s' % hall)
    seq = sorted(hall, key=lambda k: (hall[k][0], hall[k][1]))
    check(seq == ['base_6_12_11', 'tiny_hunt', 'other_hunt', 'base_6_12_15'], 'ascending along the corridor: %s' % seq)
    stacks, tele, flags = map_state(srv)
    check(tele.get((12, 11, Z)) == (700, 700, 7), 'the low base hunt keeps its teleport')
    check(tele.get((30, 11, Z)) == (800, 800, 7), 'a teleport that is not a hunt stays where it is')
    check(PORTAL not in stacks[(12, 15, Z)] and stacks[(12, 15, Z)] == [G, STONE], 'its old place is free for a content hunt: %s' % stacks[(12, 15, Z)])
    check(tele.get(hall['base_6_12_15']) == (710, 700, 7), 'the high base hunt moved with its destination: %s' % tele)
    moved = hall['base_6_12_15']
    check(tele.get((711, 701, 7)) == H.front_of(cfg['room'], moved) != (12, 14, Z) and tele.get((701, 700, 7)) == (12, 12, Z),
          'the moved hunt\'s way back leads in front of its new teleport, the other one\'s stays: %s' % tele)
    check(all(flags[p] == 1 for p in stacks if p[2] == Z and 12 <= p[1] <= 14), 'the corridor stays PZ')
    check(flags[(11, 10, Z)] == 0 and flags[(15, 10, Z)] == 0, 'the cells stay non-PZ')
    seen = reachable(stacks, (11, 13, Z), Z)
    check(all(tuple(p) in seen for p in hall.values()), 'every teleport reachable from the corridor')
    sp = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
    check('chaoshunt="base_6_12_11">\n\t\t<monster name="Hydra"' in sp and sp.count('name="Hydra"') == 2,
          'the base display monster follows its hunt (the old unmarked block taken over)')
    pl = open(os.path.join(srv, 'data', 'lib', 'chaos_hunt_places.lua')).read()
    check('hall = true' in pl and '{id = "base_6_12_15", name = "Dragon", level = {600, 700}' in pl and 'floors = {' in pl,
          'places file: the base hunts and the floors')
    free = [(x, y, Z) for x in (12, 16, 20) for y in (11, 15) if (x, y, Z) not in hall.values()]
    check(len(free) == 2 and all(stacks[p] == [G, WALL] for p in free),
          'the rooms no hunt takes are closed: a wall on the teleport tile, the ring off: %s' % [(p, stacks[p]) for p in free])
    check(all(WALL not in stacks[tuple(p)] for p in hall.values()), 'the rooms in use stay open')
    once = digest(srv)
    go()
    check(digest(srv) == once, 'hall order: a second run changes nothing')
    # --remove-hall: the base hunts back where they were, the content hunts in the wing
    res = go(hall_on=False)
    stacks, tele, flags = map_state(srv)
    check(tele.get((12, 11, Z)) == (700, 700, 7) and tele.get((12, 15, Z)) == (710, 700, 7), 'remove: base teleports back')
    check(tele.get((711, 701, 7)) == (12, 14, Z), 'remove: the way back leads to the old place again')
    check(PORTAL not in stacks[(16, 15, Z)], 'remove: the wing slot free again')
    check(all(WALL not in stacks[p] and STONE in stacks[p] for p in free), 'remove: the closed rooms open again: %s' % [stacks[p] for p in free])
    check(res['slots'] == {'tiny_hunt': (16, 11, Z), 'other_hunt': (16, 15, Z)}, 'remove: content hunts in the wing %s' % res['slots'])
    pl = open(os.path.join(srv, 'data', 'lib', 'chaos_hunt_places.lua')).read()
    check('hall = false' in pl, 'remove: places file says so')
    again = digest(srv)
    go(hall_on=False)
    check(digest(srv) == again, 'remove: a second run changes nothing')
    go()
    stacks, tele, _f = map_state(srv)
    check(tele.get(hall['base_6_12_15']) == (710, 700, 7) and PORTAL not in stacks[(12, 15, Z)], 'order again after a remove')
    # the order changes on a later install (beta report 2026-10-22: a hunt's level changed; seven ways back led in
    # front of another hunt's teleport): each way back follows its own hunt, by the arrival beside it
    rows[0] = dict(rows[0], lo=900, hi=950)
    H.write_csv(rows, csvp)
    res = go()
    hall = res['hall']['assign']
    seq = sorted(hall, key=lambda k: (hall[k][0], hall[k][1]))
    check(seq[-1] == 'base_6_12_11', 'reorder: the Rat hunt last now: %s' % seq)
    stacks, tele, _f = map_state(srv)
    check(tele.get((701, 700, 7)) == H.front_of(cfg['room'], hall['base_6_12_11'])
          and tele.get((711, 701, 7)) == H.front_of(cfg['room'], hall['base_6_12_15']),
          'reorder: each way back leads in front of its own hunt\'s teleport: %s' % tele)
    once = digest(srv)
    go()
    check(digest(srv) == once, 'reorder: a second run changes nothing')
    rows[0] = dict(rows[0], lo=10, hi=40)
    H.write_csv(rows, csvp)
    # too few slots: refused
    rows.append(dict(rows[0], id='base_6_99_11', x=99))
    H.write_csv(rows, csvp)
    try:
        go(dry=True)
        check(False, 'a base hunt off the hall refused')
    except (T.InstallError, H.HallError) as e:
        check('not a tile of the map' in str(e), 'refused: %s' % e)


QP1, QP2, REWARD, CHEST, BOOTH = 5023, 11796, 2160, 29327, 1500


def text_attr(text):
    b = text.encode('latin-1')
    return bytes([6]) + struct.pack('<H', len(b)) + b


def tile_at(srv, pos):
    """a tile of the written map, parsed with every attribute (hall_order.parse_tile)"""
    import hall_order as H
    path = os.path.join(srv, 'data', 'world', 'w.otbm')
    data = open(path, 'rb').read()
    s, e = T.tile_ranges(data, [pos])[pos]
    return H.parse_tile(data[s:e + 1], pos)


def lay0_rect(cfg, qrows):
    import hall_quests as HQ
    return HQ.layout_grid(dict(cfg['hall']['quests']), cfg['room'], qrows)['rect']


def tele_of(srv, pos):
    return map_state(srv)[1].get(pos)


def wing_ground_checks(root):
    """a wing of the ground floor copied from floor 6, whose outer wall stands on no ground and whose module lacks a
    tile where the old end stood: every tile of the wing gets a ground (no black, unmapped square), a base hunt's
    teleport goes after the ground, its way back follows it to the new floor; a second run changes nothing"""
    import hall_order as H
    cfg = json.loads(json.dumps(CFG))
    cfg['room']['wings'] = [{'z': 7, 'from': Z, 'sweep': True, 'east': {'modules': 1}}]
    cfg['hall'] = {'enabled': True, 'floors': [7, Z], 'levels': [{'z': 7, 'max': 450}, {'z': Z}], 'x': [0, 40],
                   'endRow': 13, 'temple': [500, 500, 7], 'labels': []}
    extra = {(10, 9, Z): dict(ground=None, items=[(WALL, {})], flags=1),  # floor 6's outer wall on no ground
             (12, 11, Z): tile(G, PORTAL, STONE, tele=(700, 700, 7)),
             (701, 700, 7): tile(G, PORTAL, tele=(12, 12, Z))}
    for y in range(ROWS[0] - 1, ROWS[1] + 2):  # the ground floor: its end (two columns) and the lawn east of it
        for x in range(14, 22):
            corridor = 12 <= y <= 14
            if x in (14, 15) and ROWS[0] <= y <= ROWS[1]:
                extra[(x, y, 7)] = tile(G) if corridor else tile(G, WALL)
            else:
                extra[(x, y, 7)] = tile(G, flags=0)
    srv, plans, comp = setup(os.path.join(root, 'wing'), extra, drop=[(11, 17, Z)])  # no module tile there
    csvp = os.path.join(root, 'wing', 'hall_hunts.csv')
    H.write_csv([dict(id='base_6_12_11', z=Z, x=12, y=11, dest_x=700, dest_y=700, dest_z=7, name='Rat', lo=10, hi=40,
                      level=20, display='Rat', spawntime=120, monsters='Rat')], csvp)

    def go():
        return T.run(os.path.join(srv, 'data'), plans_dir=plans, config=cfg, compiled=comp, log=lambda s: None,
                     fixed_dirs=(), hall_csv=csvp, kinds=({G}, set()))
    res = go()
    stacks, tele, _f = map_state(srv)
    box = [(x, y, 7) for x in range(14, 20) for y in range(ROWS[0], ROWS[1] + 1)]
    bad = [p for p in box if p not in stacks or not stacks[p] or stacks[p][0] != G]
    check(not bad, 'every tile of the ground floor\'s wing has a ground: %s' % [(p, stacks.get(p)) for p in bad])
    check(stacks.get((14, 9, 7)) == [G, WALL], 'the outer wall copied from floor 6 stands on ground: %s' % stacks.get((14, 9, 7)))
    check(stacks.get((15, 17, 7)) == [G], 'the old end tile without a copy over it is ground, not a hole: %s' % stacks.get((15, 17, 7)))
    at = res['hall']['assign']['base_6_12_11']
    check(at[2] == 7 and stacks[at][:2] == [G, PORTAL], 'the base hunt on the ground floor, its teleport after the ground: %s %s' % (at, stacks.get(at)))
    check(tele.get((701, 700, 7)) == H.front_of(cfg['room'], at), 'its way back leads to the new floor: %s' % (tele.get((701, 700, 7)),))
    once = digest(srv)
    go()
    check(digest(srv) == once, 'wing ground: a second run changes nothing')


def floor_rule_checks():
    """the owner's floors by level: z 7 for levels 1-500, z 6 for 501-1000, z 5 for the rest (hall.levels)"""
    import hall_order as H
    hall = {'floors': [7, 6, 5], 'levels': [{'z': 7, 'max': 500}, {'z': 6, 'max': 1000}, {'z': 5}]}
    got = [H.floor_for(hall, lv) for lv in (1, 60, 500, 501, 1000, 1001, 5000)]
    check(got == [7, 7, 7, 6, 6, 5, 5], 'floor of a level: %s' % got)
    check([H.floor_range_text(hall, z) for z in (7, 6, 5)] == ['1-500', '500-1000', '1000+'], 'floor ranges')
    check(H.floor_bands({}, [], hall) == [dict(z=7, level=[1, 500]), dict(z=6, level=[500, 1000]), dict(z=5, level=[1000, 0])],
          'floor bands with the rule: %s' % H.floor_bands({}, [], hall))
    hunts = [dict(id='low', lo=5, hi=10, level=8), dict(id='mid', lo=600, hi=700, level=650),
             dict(id='top', lo=1500, hi=1600, level=1550), dict(id='low2', lo=20, hi=30, level=25)]
    slots = [dict(teleport=(x, 11, z)) for z in (7, 6, 5) for x in (10, 14)]
    got = H.assign(hunts, slots, hall)
    check({k: v['teleport'] for k, v in got.items()} == {'low': (10, 11, 7), 'low2': (14, 11, 7), 'mid': (10, 11, 6),
                                                         'top': (10, 11, 5)}, 'hunts on the floor of their level, ascending: %s' % got)
    check(H.check_ascending(got, hunts, hall) == [], 'no ordering problem: %s' % H.check_ascending(got, hunts, hall))
    try:
        H.assign(hunts + [dict(id='low3', lo=1, hi=5, level=3)], [s for s in slots if s['teleport'][2] != 7] + slots[:1], hall)
        check(False, 'a floor with too few slots refused')
    except H.HallError as e:
        check('floor 7' in str(e) and 'grow' in str(e), 'refused, names the floor: %s' % e)


def quest_hall_checks(root):
    """the base quests leave the level-ordered floor: each alcove (teleport with destination and unique id, the sign with
    its text, the rewards on show with their attributes) moves tile for tile to the quest hall, the way back from the
    quest leads in front of the new alcove, the reward chests are gone; a second run changes nothing; --remove-hall
    puts the quests back"""
    import hall_order as H
    import hall_quests as Q
    QZ = 7  # the quests stand on the entry floor, the room's module on Z
    cfg = json.loads(json.dumps(CFG))
    cfg['items'] = {'portal': PORTAL, 'sign': SIGN, 'questPortals': [QP1, QP2]}
    cfg['hall'] = {'enabled': True, 'floors': [QZ, Z], 'levels': [{'z': QZ, 'max': 500}, {'z': Z}], 'x': [0, 60], 'endRow': 13, 'temple': [500, 500, 7], 'labels': [],
                   'quests': {'z': QZ, 'origin': {'x': 30, 'y': 20}, 'connector': {'x': 26}, 'step': 4,
                              'model': {'x': 12, 'z': Z},
                              'chests': [{'x': 36, 'y': 25, 'item': CHEST, 'uid': 34801, 'rows': [23, 25]}]}}
    q1, q2 = (700, 700, 7), (710, 700, 7)

    def t(*items, flags=0):
        return dict(ground=None, items=[(G, {})] + list(items), flags=flags)
    extra = {
        (12, 11, QZ): t((QP1, {'tele': q1, 'uid': 44001}), (STONE, {}), flags=1),
        (12, 15, QZ): t((QP2, {'tele': q2}), (STONE, {}), flags=1),
        (11, 10, QZ): t((REWARD, {'uid': 44002, 'raw': bytes([15, 3])})),
        (13, 10, QZ): t((REWARD + 1, {})),
        (11, 16, QZ): t((REWARD + 2, {'raw': bytes([15, 7])})),
        (13, 16, QZ): t((REWARD + 3, {})),
        (12, 9, QZ): t((COUNTER, {}), (SIGN, {'raw': text_attr('Quest A')})),
        # the counter between the two cells holds rewards too (the base hall: the beta showed them left behind)
        (12, 10, QZ): t((COUNTER, {}), (REWARD + 4, {}), flags=1),
        (12, 16, QZ): t((COUNTER, {}), (REWARD + 5, {}), flags=1),
        # the alcove's east divider: a wall (the quest hall's far end is closed with it)
        (14, 11, QZ): t((WALL, {}), flags=1),
        (12, 17, QZ): t((COUNTER, {}), (SIGN, {'raw': text_attr('Quest B')})),
        # the quest sites' way back, and a teleport nearby that is not one
        (701, 700, 7): t((PORTAL, {'tele': (12, 12, QZ)})),
        (711, 700, 7): t((PORTAL, {'tele': (12, 14, QZ)})),
        (702, 700, 7): t((PORTAL, {'tele': (5, 5, QZ)})),
        # the reward chest and its booth
        (36, 23, QZ): t((BOOTH, {})), (36, 24, QZ): t((BOOTH, {})), (36, 25, QZ): t((CHEST, {'uid': 34801})),
    }
    for x in range(10, 15):  # every tile of the old alcoves exists on the map
        for y in range(9, 18):
            extra.setdefault((x, y, QZ), t())
    for y in (12, 13, 14):  # the hall's corridor on the quest floor
        extra[(12, y, QZ)] = t(flags=1)
    for x in range(24, 41):  # the plaza's ground where the quest hall goes
        for y in range(19, 30):
            extra.setdefault((x, y, QZ), t())
    srv, plans, comp = setup(os.path.join(root, 'quests'), extra)
    csvp = os.path.join(root, 'quests', 'hall_hunts.csv')
    base = dict(spawntime=120, display='', monsters='', lo=0, hi=0, level=0)
    rows = [dict(base, id='base_7_12_11', z=QZ, x=12, y=11, dest_x=700, dest_y=700, dest_z=7, kind='quest', name='Quest A'),
            dict(base, id='base_7_12_15', z=QZ, x=12, y=15, dest_x=710, dest_y=700, dest_z=7, kind='quest', name='Quest B'),
            dict(base, id='base_6_12_11', z=Z, x=12, y=11, dest_x=900, dest_y=900, dest_z=7, name='Dragon', lo=600, hi=700, level=650, monsters='Dragon'),
            dict(base, id='base_6_12_15', z=Z, x=12, y=15, dest_x=910, dest_y=900, dest_z=7, name='Demon', lo=900, hi=1100, level=1000, monsters='Demon'),
            dict(base, id='low_cave', z='', x='', y='', dest_x=800, dest_y=800, dest_z=7, kind='hunt', name='Rat', lo=5, hi=10,
                 level=8, display='Hydra', monsters='Rat')]
    H.write_csv(rows, csvp)
    before = {p: tile_at(srv, p) for p in extra}

    def go(**kw):
        return T.run(os.path.join(srv, 'data'), plans_dir=plans, config=cfg, compiled=comp, log=lambda s: None,
                     fixed_dirs=(), hall_csv=csvp, **kw)
    res = go()
    qrows = H.quests_of(H.read_csv(csvp))
    lay = Q.layout(cfg['hall']['quests'], cfg['room'], qrows)
    al = {a['id']: a for a in lay['alcoves']}
    check(al['base_7_12_11']['new'] == (30, 22, QZ) and al['base_7_12_15']['new'] == (30, 26, QZ), 'quest hall: the north alcove above the corridor, the south one below: %s' % [a['new'] for a in lay['alcoves']])
    for a in lay['alcoves']:
        for old, new in a['tiles'].items():
            if old not in before:  # the map has no tile there: the quest hall has plain floor
                continue
            check(tile_at(srv, new) == before[old], 'alcove tile %s -> %s moved with every attribute: %s vs %s' % (old, new, tile_at(srv, new), before[old]))
    tele_tile = tile_at(srv, (30, 22, QZ))
    check(tele_tile['items'][1] == (QP1, {'tele': q1, 'uid': 44001}), 'the quest teleport keeps its destination and unique id')
    check(tile_at(srv, (29, 21, QZ))['items'][1] == (REWARD, {'uid': 44002, 'raw': bytes([15, 3])}), 'the reward on show keeps its unique id and count')
    check(tile_at(srv, (30, 20, QZ))['items'][-1][1].get('raw') == text_attr('Quest A'), 'the sign keeps its text')
    check(tile_at(srv, (30, 26, QZ))['items'][1] == (QP2, {'tele': q2}), 'the south quest teleport moved')
    # the old alcoves: no quest teleport, bare cells, blank signs
    hunt_at = res['hall']['assign']['low_cave']
    for old in (al['base_7_12_11']['old'], al['base_7_12_15']['old']):
        items = [i for i, _a in tile_at(srv, old)['items']]
        check(QP1 not in items and QP2 not in items, 'old quest teleport gone at %s' % (old,))
    check(tile_at(srv, hunt_at)['items'][:2] == [(G, {}), (PORTAL, {'tele': (800, 800, 7)})],
          'the new low-level hunt takes the first free slot %s, its teleport after the ground' % (hunt_at,))
    for c in ((11, 10, QZ), (13, 10, QZ), (11, 16, QZ), (13, 16, QZ)):
        check([i for i, _a in tile_at(srv, c)['items']] == [G] and tile_at(srv, c)['flags'] == 0,
              'old cell %s bare and without protection zone like the model alcove\'s (a display monster can stand there)' % (c,))
    for c in ((12, 10, QZ), (12, 16, QZ)):
        check([i for i, _a in tile_at(srv, c)['items']] == [G, COUNTER], 'old counter %s without its rewards: %s' % (c, tile_at(srv, c)))
    check([i for i, _a in tile_at(srv, (30, 21, QZ))['items']] == [G, COUNTER, REWARD + 4], 'the counter\'s rewards moved with it')
    # the corridor's far end is closed with the hall's wall
    ends = lay['endwall']
    check(ends == [(33, 23, QZ), (33, 24, QZ), (33, 25, QZ)] and all(WALL in [i for i, _a in tile_at(srv, p)['items']] for p in ends),
          'the quest corridor\'s far end closed by a wall: %s' % [tile_at(srv, p) for p in ends])
    sp = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
    check('centerx="11" centery="10" centerz="7" radius="1" chaoshunt="low_cave">\n\t\t<monster name="Hydra"' in sp,
          'the display monster of the hunt in the old alcove stands in its cell')
    for sg in ((12, 9, QZ), (12, 17, QZ)):
        check(all(a.get('raw', b'') == b'' for i, a in tile_at(srv, sg)['items'] if i == SIGN), 'old sign %s blank' % (sg,))
    # the way back from the quest sites
    tele = map_state(srv)[1]
    check(tele.get((701, 700, 7)) == (30, 23, QZ) and tele.get((711, 700, 7)) == (30, 25, QZ), 'way back leads in front of the new alcoves: %s' % tele)
    check(tele.get((702, 700, 7)) == (5, 5, QZ), 'a teleport that does not lead to the hall is left alone')
    # the chest and its booth are gone
    check(all([i for i, _a in tile_at(srv, (36, y, QZ))['items']] == [G] for y in (23, 24, 25)), 'chest and booth removed')
    # reachable, and the corridor keeps its protection zone
    stacks, tele, flags = map_state(srv)
    seen = reachable(stacks, (26, 24, QZ), QZ)
    check((30, 23, QZ) in seen and (30, 25, QZ) in seen, 'both new fronts reachable from the connector')
    check(all(flags[(x, y, QZ)] == 1 for x in range(26, 33) for y in (23, 24, 25)), 'quest corridor and connector are protection zone')
    pl = open(os.path.join(srv, 'data', 'lib', 'chaos_hunt_places.lua')).read()
    check('quests = {label = {x = 31, y = 24, z = 7}, entrance = {x = 26, y = 24, z = 7}, count = 2}' in pl,
          'places file: the quest labels')
    once = digest(srv)
    state_once = map_state(srv)
    snap_spawn = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
    go()
    check(digest(srv) == once, 'quest hall: a second run changes nothing')
    # --remove-hall: the quests where they were, with everything
    go(hall_on=False)
    for a in lay['alcoves']:
        for old in a['tiles']:
            if old not in before:
                continue
            check(tile_at(srv, old) == before[old], 'remove: alcove tile %s restored: %s vs %s' % (old, tile_at(srv, old), before[old]))
    tele = map_state(srv)[1]
    check(tele.get((701, 700, 7)) == (12, 12, QZ) and tele.get((711, 700, 7)) == (12, 14, QZ), 'remove: way back leads to the old fronts')
    check([i for i, _a in tile_at(srv, (30, 22, QZ))['items']] == [G], 'remove: the quest hall is floor again')
    again = digest(srv)
    go(hall_on=False)
    check(digest(srv) == again, 'remove: a second run changes nothing')
    go()
    check(map_state(srv) == state_once, 'order again after a remove: the same tiles, teleports and flags')
    sp = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
    check(sp.count('chaoshunt=') == snap_spawn.count('chaoshunt='), 'order again after a remove: the same display monsters')
    # a unique id or an action id where the quest hall would go is refused
    srv2, plans2, comp2 = setup(os.path.join(root, 'quests2'), {**extra, (31, 24, QZ): t((BOOTH, {'aid': 9999}))})
    try:
        T.run(os.path.join(srv2, 'data'), plans_dir=plans2, config=cfg, compiled=comp2, log=lambda s: None, fixed_dirs=(),
              hall_csv=csvp)
        check(False, 'an action id under the quest hall refused')
    except T.InstallError as e:
        check('action id' in str(e), 'refused: %s' % e)
    # a wing that sweeps open ground: only decoration may go (no action id, unique id, teleport, sign)
    m2 = os.path.join(srv2, 'data', 'world', 'w.otbm')
    T.check_swept(m2, {(36, 23, QZ), (30, 22, QZ)}, PORTAL, cfg['items'], lambda s: None)
    for pos in ((31, 24, QZ), (12, 9, QZ), (12, 11, QZ)):
        try:
            T.check_swept(m2, {pos}, PORTAL, cfg['items'], lambda s: None)
            check(False, 'a swept tile with an action id, sign or teleport refused: %s' % (pos,))
        except T.InstallError as e:
            check('nothing written' in str(e), 'swept %s refused: %s' % (pos, e))
    # the quests move on from the quest hall over the pond to two rows round a corridor of the plaza (owner,
    # 2026-10-20: "you can overwrite this green region"); the earlier hall is taken back to the map's backup; a
    # teleport of the plaza on the corridor stays where it is
    plaza = {}
    for x in range(44, 57):
        for y in range(39, 51):
            plaza[(x, y, QZ)] = t(flags=1)
    plaza[(48, 44, QZ)] = t((PORTAL, {'tele': (321, 321, 7)}), flags=1)
    import hall_quests as HQ
    srv5, plans5, comp5 = setup(os.path.join(root, 'quests5'), {**extra, **plaza})
    T.run(os.path.join(srv5, 'data'), plans_dir=plans5, config=cfg, compiled=comp5, log=lambda s: None, fixed_dirs=(),
          hall_csv=csvp)
    first = map_state(srv5)
    cfg5 = json.loads(json.dumps(cfg))
    q5 = cfg5['hall']['quests']
    q5['previous'] = {'origin': q5.pop('origin'), 'connector': q5.pop('connector'), 'step': q5.pop('step'), 'fill': 28915}
    q5.update({'north': {'y': 40, 'x': [50]}, 'south': {'y': 46, 'x': [50]}, 'corridor': {'x': [47, 53], 'y': [43, 45]}})
    logs = []
    T.run(os.path.join(srv5, 'data'), plans_dir=plans5, config=cfg5, compiled=comp5, log=logs.append, fixed_dirs=(),
          hall_csv=csvp)
    stacks, tele, flags = map_state(srv5)
    check(tile_at(srv5, (50, 42, QZ))['items'][1] == (QP1, {'tele': q1, 'uid': 44001})
          and tile_at(srv5, (50, 46, QZ))['items'][1] == (QP2, {'tele': q2}), 'quests moved on to the plaza rows')
    check(not any(i in (QP1, QP2) for p in lay0_rect(cfg, qrows) for i, _a in (tile_at(srv5, p)['items'] if p in stacks else [])),
          'no quest teleport left in the earlier quest hall')
    check(tile_at(srv5, (49, 41, QZ))['items'][1] == (REWARD, {'uid': 44002, 'raw': bytes([15, 3])}), 'with their rewards')
    check(tele.get((701, 700, 7)) == (50, 43, QZ) and tele.get((711, 700, 7)) == (50, 45, QZ), 'ways back to the new fronts: %s' % tele)
    check(tele.get((48, 44, QZ)) == (321, 321, 7), 'the plaza\'s own teleport on the corridor stays')
    lay0 = HQ.layout_grid(dict(cfg['hall']['quests']), cfg['room'], qrows)
    check(all(stacks.get(p) == [G] for p in lay0['rect'] if p in plaza or (24 <= p[0] <= 40 and 19 <= p[1] <= 29)),
          'the earlier quest hall back as the backup has it: %s' % [(p, stacks.get(p)) for p in lay0['rect'][:3]])
    check(all(flags[(x, y, QZ)] == 1 for x in range(47, 54) for y in (43, 44, 45)), 'the plaza corridor is protection zone')
    once = digest(srv5)
    T.run(os.path.join(srv5, 'data'), plans_dir=plans5, config=cfg5, compiled=comp5, log=lambda s: None, fixed_dirs=(),
          hall_csv=csvp)
    check(digest(srv5) == once, 'moved on: a second run changes nothing')
    check(first != stacks, 'moved on: the map changed')
    # an earlier install lost a quest (a hunt's teleport took its alcove, the sign blank, the rewards still there): the
    # alcove moves to the quest hall all the same, its teleport made again from the CSV and the sign named
    lost = dict(extra)
    lost[(12, 11, QZ)] = t((PORTAL, {'tele': (999, 999, 7)}), (STONE, {}), flags=1)
    lost[(12, 9, QZ)] = t((COUNTER, {}), (SIGN, {}))
    srv4, plans4, comp4 = setup(os.path.join(root, 'quests4'), lost)
    T.run(os.path.join(srv4, 'data'), plans_dir=plans4, config=cfg, compiled=comp4, log=lambda s: None, fixed_dirs=(),
          hall_csv=csvp)
    got = tile_at(srv4, (30, 22, QZ))['items']
    check(got[:2] == [(G, {}), (PORTAL, {'tele': q1})] and all(a.get('tele') in (None, q1) for _i, a in got),
          'a lost quest\'s teleport made again in the quest hall: %s' % got)
    sg = [a for i, a in tile_at(srv4, (30, 20, QZ))['items'] if i == SIGN]
    check(sg and sg[0].get('raw') == text_attr('Quest A'), 'its sign named again: %s' % sg)
    check([i for i, _a in tile_at(srv4, (29, 21, QZ))['items']] == [G, REWARD], 'its rewards on show in the quest hall')
    check(PORTAL not in [i for i, _a in tile_at(srv4, (12, 11, QZ))['items']] or
          tele_of(srv4, (12, 11, QZ)) != (999, 999, 7), 'the stray hunt teleport is gone from the old alcove')
    once = digest(srv4)
    T.run(os.path.join(srv4, 'data'), plans_dir=plans4, config=cfg, compiled=comp4, log=lambda s: None, fixed_dirs=(),
          hall_csv=csvp)
    check(digest(srv4) == once, 'lost quest: a second run changes nothing')
    # a chest with another unique id is not removed (not ours)
    srv3, plans3, comp3 = setup(os.path.join(root, 'quests3'), {**extra, (36, 25, QZ): t((CHEST, {'uid': 1}))})
    try:
        T.run(os.path.join(srv3, 'data'), plans_dir=plans3, config=cfg, compiled=comp3, log=lambda s: None, fixed_dirs=(),
              hall_csv=csvp)
        check(False, 'a chest with another unique id refused')
    except T.InstallError as e:
        check('unique id' in str(e), 'refused: %s' % e)


def csv_name_checks():
    """the monsters of tools/hall_hunts.csv (name, display, monsters) are named as the installed server names them:
    install step monsternames renames the base monsters before contentareas runs, so an old name has no monster and
    its room no display (owner 2026-10-21: four low-level rooms stood empty: their CSV rows had the old names)"""
    import csv as _csv
    import hashlib
    import hall_order as H
    names = os.path.join(HERE, '..', 'data', 'monster', 'base_monster_names.csv')
    old = {r['sha256'] for r in _csv.DictReader(open(names, encoding='utf-8')) if r['kind'] == 'monster'}
    for r in H.read_csv():
        for n in [r['name'], r.get('display') or ''] + (r.get('monsters') or '').split('|'):
            if n:
                check(hashlib.sha256(n.lower().encode('utf-8')).hexdigest() not in old,
                      '%s: %r is an old monster name (use its Chaos name)' % (r['id'], n))


def main():
    root = tempfile.mkdtemp(prefix='content_areas_test_')
    try:
        srv, plans, comp = setup(os.path.join(root, 'a'))
        before = digest(srv)
        res, _log = run(srv, plans, comp, dry=True)
        check(digest(srv) == before, 'dry run writes nothing')
        check(res['room'] == 'todo' and res['areas'] == {'tiny_hunt': 'todo', 'other_hunt': 'todo'}, 'dry run: all to do')
        res, log = run(srv, plans, comp)
        check(res['slots'] == {'tiny_hunt': (16, 11, Z), 'other_hunt': (16, 15, Z)}, 'slots: first copied alcove, north then south %s' % res['slots'])
        m = otbm.load_otbm(os.path.join(srv, 'data', 'world', 'w.otbm'))

        def stack(p):
            i = m.find(*p)
            return None if i < 0 else [int(a) for a in m.stack(i)]
        check(stack((16, 11, Z)) == [G, STONE], 'copied teleport tile without the teleport: %s' % stack((16, 11, Z)))
        check(stack((16, 9, Z)) == [G, COUNTER, SIGN], 'the sign counter copied')
        check(stack((20, 11, Z)) == [G, STONE], 'second module copied')
        check(stack((15, 10, Z)) == [G], 'the cell copied')
        check(m.tiles['flags'][m.find(15, 10, Z)] == 0 and m.tiles['flags'][m.find(14, 12, Z)] == 1, 'tile flags copied')
        check(stack((22, 13, Z)) == [G, PORTAL], 'the end moved by 8 with its teleport')
        tele = {(int(m.tiles['x'][i]), int(m.tiles['y'][i])): d for i, _iid, d in otbm.teleports(m, [PORTAL])}
        check(tele.get((22, 13)) == (500, 500, 7), 'the end teleport keeps its destination: %s' % tele)
        check(stack((14, 13, Z)) == [G], 'the old end tile replaced by the corridor copy')
        check(stack((1000, 1000, 7)) == [G] and stack((1101, 1000, 8)) == [G, PORTAL], 'areas placed')
        check(len(m.tiles['x']) == len(room_tiles()) - 8 + 9 * 8 + 8 + 6, 'tile count %d' % len(m.tiles['x']))
        sp = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
        check(sp.count('chaoshunt="tiny_hunt"') == 2 and sp.count('chaoshunt="other_hunt"') == 2, 'two display monsters each')
        check('centerx="15" centery="10" centerz="6" radius="1" chaoshunt="tiny_hunt"' in sp
              and 'centerx="17" centery="10"' in sp and 'name="Bog Rat" x="0" y="0" z="6" spawntime="90"' in sp,
              'display cells beside the teleport')
        check(sp.count('chaoscontent="tiny_hunt"') == 1 and 'name="Hydra"' in sp, 'area spawns added, old kept')
        pl = open(os.path.join(srv, 'data', 'lib', 'chaos_hunt_places.lua')).read()
        check('{id = "tiny_hunt", name = "Tiny Hunt", level = {300, 400}, teleport = {x = 16, y = 11, z = 6}, '
              'sign = {x = 16, y = 9, z = 6}, arrival = {x = 1000, y = 1000, z = 7}, exit = {x = 1001, y = 1000, z = 7}, '
              'monster = "Bog Rat", front = {x = 16, y = 12, z = 6}}' in pl,
              'places entry:\n' + pl)
        check('back = {x = 11, y = 13, z = 6}' in pl, 'back tile')
        once = digest(srv)
        res, _log = run(srv, plans, comp)
        check(digest(srv) == once, 'a second run changes nothing')
        check(res['room'] == 'done' and set(res['areas'].values()) == {'done'}, 'second run: all done')
        make_area(comp['tiny_hunt'], 'tiny_hunt', (1000, 1000, 7), ground=101)
        # the same map as a map master (tools/map_master.py's marker): the area differs from its plan as if the owner
        # had edited it by hand; it is kept, nothing written
        mark = os.path.join(srv, 'data', 'world', 'w.otbm.master.json')
        open(mark, 'w').write('{"version": 1}\n')
        try:
            run(srv, plans, comp)
            check(False, 'map master: an area most of whose tiles differ is still refused')
        except T.InstallError as e:
            check('changed' in str(e), 'map master, all tiles changed: %s' % e)
        one = {(1000 + i, 1000, 7): dict(ground=G, items=[], flags=0) for i in range(3)}
        one[(1001, 1000, 7)]['items'] = [(PORTAL, {'aid': 47951})]
        one[(1000, 1000, 7)]['ground'] = 101
        open(os.path.join(comp['tiny_hunt'], 'tiny_hunt.otbm'), 'wb').write(otbm_file(one))
        open(mark, 'w').write('{"version": 1}\n')
        res, log = run(srv, plans, comp)
        check(res['areas'].get('tiny_hunt') == 'done' and digest(srv) == once, 'map master: an edited area is kept')
        check(any('tiny_hunt: placed before' not in l and 'tiny_hunt: placed already' in l and 'edited by hand' in l
                  for l in log), 'map master: logged')
        os.remove(mark)
        # no map master: a placed area whose plan changed (a new spawn list moves the decoration) is written again,
        # its spawn blocks too; the tile count stays, the other area and the old spawns are kept
        with open(os.path.join(comp['tiny_hunt'], 'tiny_hunt-spawn.xml'), 'w') as f:
            f.write('<?xml version="1.0"?>\n<spawns>\n'
                    '\t<spawn centerx="1002" centery="1000" centerz="7" radius="1">\n'
                    '\t\t<monster name="Bog Rat" x="0" y="0" z="7" spawntime="60" />\n\t</spawn>\n'
                    '\t<spawn centerx="1000" centery="1000" centerz="7" radius="1">\n'
                    '\t\t<monster name="Mire Leech" x="0" y="0" z="7" spawntime="60" />\n\t</spawn>\n</spawns>\n')
        res, _log = run(srv, plans, comp, dry=True)
        check(res['areas'].get('tiny_hunt') == 'update' and digest(srv) == once, 'changed plan, dry run: nothing written')
        res, log = run(srv, plans, comp)
        check(res['areas'] == {'tiny_hunt': 'update', 'other_hunt': 'done'}, 'changed plan: written again %s' % res['areas'])
        check(any('tiny_hunt: placed before, the plan changed' in l for l in log), 'changed plan: logged')
        m = otbm.load_otbm(os.path.join(srv, 'data', 'world', 'w.otbm'))
        i = m.find(1000, 1000, 7)
        check([int(a) for a in m.stack(i)] == [101], 'changed plan: the new tile')
        check([int(a) for a in m.stack(m.find(1001, 1000, 7))] == [G, PORTAL], 'changed plan: the exit kept')
        check(len(m.tiles['x']) == len(room_tiles()) - 8 + 9 * 8 + 8 + 6, 'changed plan: the tile count stays')
        sp = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
        check(sp.count('chaoscontent="tiny_hunt"') == 2 and 'name="Mire Leech"' in sp and 'name="Hydra"' in sp
              and sp.count('chaoscontent="other_hunt"') == 1, 'changed plan: its spawn blocks replaced:\n' + sp)
        twice = digest(srv)
        res, _log = run(srv, plans, comp)
        check(res['areas'].get('tiny_hunt') == 'done' and digest(srv) == twice, 'changed plan: a second run changes nothing')
        # a reorder (tiny_hunt's band now above other_hunt's) moves the display monsters; the config order is not used
        cfg2 = dict(CFG, plans=[CFG['plans'][1], CFG['plans'][0]])
        tj = os.path.join(plans, 'tiny_hunt.json')
        tplan = json.load(open(tj))
        tplan['level'] = [700, 800]
        json.dump(tplan, open(tj, 'w'))
        make_area(comp['tiny_hunt'], 'tiny_hunt', (1000, 1000, 7))
        T.run(os.path.join(srv, 'data'), plans_dir=plans, config=cfg2, compiled=comp, log=lambda s: None, fixed_dirs=())
        sp = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
        check('centerx="15" centery="10" centerz="6" radius="1" chaoshunt="other_hunt"' in sp
              and sp.count('chaoshunt=') == 4, 'reorder: display spawns follow the slots')

        # a target tile of the room taken
        srv, plans, comp = setup(os.path.join(root, 'b'), {(20, 12, Z): tile(G)})
        before = digest(srv)
        try:
            run(srv, plans, comp)
            check(False, 'taken room tile refused')
        except T.InstallError as e:
            check('taken' in str(e), 'taken: %s' % e)
        check(digest(srv) == before, 'nothing written')
        # an area on map tiles
        srv, plans, comp = setup(os.path.join(root, 'c'), {(1001, 1000, 7): tile(G)})
        try:
            run(srv, plans, comp)
            check(False, 'area on map tiles refused')
        except T.InstallError as e:
            check('land on tiles' in str(e), 'area clash: %s' % e)
        # a plan missing from the config: a teleport in its band's place (the highest here), its most frequent monster on display
        srv, plans, comp = setup(os.path.join(root, 'e'))
        json.dump({'id': 'late_hunt', 'name': 'late_hunt', 'level': [900, 1000], 'origin': {'x': 1200, 'y': 1000, 'z': 9},
                   'spawns': [{'monster': 'Bat', 'count': 2}, {'monster': 'Wyrm', 'count': 5}, {'monster': 'Bat', 'count': 2}]},
                  open(os.path.join(plans, 'late_hunt.json'), 'w'))
        comp['late_hunt'] = os.path.join(root, 'e', 'out', 'late_hunt')
        make_area(comp['late_hunt'], 'late_hunt', (1200, 1000, 9))
        res, log = run(srv, plans, comp)
        check(res['slots'].get('late_hunt') == (20, 11, Z), 'unlisted plan in the third slot: %s' % res['slots'])
        sp = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
        check('chaoshunt="late_hunt">\n\t\t<monster name="Wyrm"' in sp, 'its most frequent monster on display')
        check(any('late_hunt: not in the hunt teleports config' in l for l in log), 'logged')
        # more plans than slots
        cfg_small = json.loads(json.dumps(CFG))
        cfg_small['room']['east']['modules'] = 1
        srv, plans, comp2 = setup(os.path.join(root, 'f'))
        json.dump({'id': 'late_hunt', 'name': 'late_hunt', 'level': [900, 1000], 'origin': {'x': 1200, 'y': 1000, 'z': 9}},
                  open(os.path.join(plans, 'late_hunt.json'), 'w'))
        comp2['late_hunt'] = comp['late_hunt']
        try:
            T.run(os.path.join(srv, 'data'), plans_dir=plans, config=cfg_small, compiled=comp2, log=lambda s: None,
                  fixed_dirs=())
            check(False, 'too few slots refused')
        except T.InstallError as e:
            check('too few' in str(e), 'too few slots: %s' % e)
        # --only places one plan; the other gets no teleport
        srv, plans, comp = setup(os.path.join(root, 'd'))
        res, _log = run(srv, plans, comp, only=['other_hunt'])
        check(res['areas'] == {'tiny_hunt': 'skipped', 'other_hunt': 'todo'} and list(res['slots']) == ['other_hunt'],
              '--only: %s' % res)
        # fixed areas (the chronicle folder): placed at their origin with spawns, no teleport, no places line
        srv, plans, comp = setup(os.path.join(root, 'g'))
        fixed = os.path.join(root, 'g', 'fixed')
        os.makedirs(fixed)
        json.dump({'id': 'story_area', 'name': 'Story Area', 'level': [400, 500], 'origin': {'x': 1300, 'y': 1000, 'z': 7}},
                  open(os.path.join(fixed, 'story_area.json'), 'w'))
        json.dump({'id': 'no_origin', 'name': 'No Origin', 'level': [1, 50]}, open(os.path.join(fixed, 'no_origin.json'), 'w'))
        comp['story_area'] = os.path.join(root, 'g', 'out', 'story_area')
        make_area(comp['story_area'], 'story_area', (1300, 1000, 7))
        res, log = run(srv, plans, comp, fixed_dirs=(fixed,))
        check(res['areas'].get('story_area') == 'todo' and 'no_origin' not in res['areas'], 'fixed area placed: %s' % res['areas'])
        check('story_area' not in res['slots'] and len(res['slots']) == 2, 'no teleport for a fixed area: %s' % res['slots'])
        check(any('no_origin: no origin' in l for l in log), 'a fixed plan without an origin is logged')
        m = otbm.load_otbm(os.path.join(srv, 'data', 'world', 'w.otbm'))
        check(m.find(1300, 1000, 7) >= 0, 'the fixed area is on the map')
        sp = open(os.path.join(srv, 'data', 'world', 'w-spawn.xml')).read()
        check(sp.count('chaoscontent="story_area"') == 1 and 'chaoshunt="story_area"' not in sp, 'its spawns, no display')
        pl = open(os.path.join(srv, 'data', 'lib', 'chaos_hunt_places.lua')).read()
        check('story_area' not in pl, 'not in the places file')
        once = digest(srv)
        res, _log = run(srv, plans, comp, fixed_dirs=(fixed,))
        check(digest(srv) == once and res['areas']['story_area'] == 'done', 'fixed area: a second run changes nothing')
        # two areas on one tile
        srv, plans, comp = setup(os.path.join(root, 'h'))
        fixed = os.path.join(root, 'h', 'fixed')
        os.makedirs(fixed)
        json.dump({'id': 'story_area', 'name': 'Story Area', 'level': [400, 500], 'origin': {'x': 1001, 'y': 1000, 'z': 7}},
                  open(os.path.join(fixed, 'story_area.json'), 'w'))
        comp['story_area'] = os.path.join(root, 'h', 'out', 'story_area')
        make_area(comp['story_area'], 'story_area', (1001, 1000, 7))
        before = digest(srv)
        try:
            run(srv, plans, comp, fixed_dirs=(fixed,))
            check(False, 'overlapping areas refused')
        except T.InstallError as e:
            check('overlap' in str(e), 'overlap: %s' % e)
        check(digest(srv) == before, 'overlap: nothing written')

        # the hall order: the base hunts (a hall_hunts.csv) and the content hunts in one band order over every slot
        hall_order_checks(root)
        floor_rule_checks()
        quest_hall_checks(root)
        wing_ground_checks(root)

        # the real hunts: ascending by band, every plan exactly once, and ascending along the corridor's slots
        real = T.plan_files(T.PLANS_DIR)
        order = T.plan_order(T.load_config(), real)
        ids = [p['id'] for p in order]
        check(sorted(ids) == sorted(real) and len(ids) == len(set(ids)), 'every hunt exactly once: %s' % ids)
        bands = [T.band_of(real, pid) for pid in ids]
        check(bands == sorted(bands), 'hunts ascending by band: %s' % list(zip(ids, bands)))
        # slots in corridor order (a west wing and an east wing, as the room has): west to east, north before south
        fake = [dict(teleport=(x, row, 6)) for x in (31686, 31614, 31670, 31610) for row in (32258, 32254)]
        fake.sort(key=lambda s: (s['teleport'][0], s['teleport'][1]))
        got = T.assign_slots(order[:len(fake)], fake, set(ids))
        seq = [got[pid]['teleport'] for pid in ids[:len(fake)]]
        check(seq == sorted(seq), 'lower bands west, higher east, north before south: %s' % seq)
        # a base display block whose monster stands off its centre (centre in the corridor, the monster one tile north
        # in the cell): taken over all the same, so no second monster on the cell ("Couldn't spawn" at startup)
        off = ('<?xml version="1.0"?>\n<spawns>\n\t<spawn centerx="11" centery="11" centerz="6" radius="1">\n'
               '\t\t<monster name="Warlock" x="0" y="-1" z="6" spawntime="120" />\n\t</spawn>\n</spawns>\n')
        new, notes = T.update_spawns(off, [], {'h': ('Hydra', [(11, 10, 6)])}, 120, takeover={(11, 10, 6)})
        check('Warlock' not in new and new.count('chaoshunt="h"') == 1, 'off-centre base display taken over: %s' % notes)
        new, notes = T.update_spawns(off, [], {'h': ('Hydra', [(11, 10, 6)])}, 120, takeover=())
        check('Warlock' in new and 'chaoshunt' not in new and any('already has a spawn' in n for n in notes),
              'an off-centre monster on a display cell is seen (no second monster on it): %s' % notes)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    csv_name_checks()
    print('install_content_areas_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
