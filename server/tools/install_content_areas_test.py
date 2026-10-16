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


def setup(root, extra=None):
    srv = os.path.join(root, 'srv')
    os.makedirs(os.path.join(srv, 'data', 'world'))
    os.makedirs(os.path.join(srv, 'data', 'scripts'))
    open(os.path.join(srv, 'config.lua'), 'w').write('mapName = "w"\n')
    world = room_tiles()
    world.update(extra or {})
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
    cfg['hall'] = {'enabled': True, 'floors': [Z], 'x': [0, 40], 'endRow': 13, 'temple': [500, 500, 7], 'labels': []}
    # two base hunts on the module's teleports (12,11) and (12,15): one low, one high; the content hunts in between
    extra = {(12, 11, Z): tile(G, PORTAL, STONE, tele=(700, 700, 7)), (12, 15, Z): tile(G, PORTAL, STONE, tele=(710, 700, 7)),
             (30, 11, Z): tile(G, PORTAL, tele=(800, 800, 7))}
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
    once = digest(srv)
    go()
    check(digest(srv) == once, 'hall order: a second run changes nothing')
    # --remove-hall: the base hunts back where they were, the content hunts in the wing
    res = go(hall_on=False)
    stacks, tele, flags = map_state(srv)
    check(tele.get((12, 11, Z)) == (700, 700, 7) and tele.get((12, 15, Z)) == (710, 700, 7), 'remove: base teleports back')
    check(PORTAL not in stacks[(16, 15, Z)], 'remove: the wing slot free again')
    check(res['slots'] == {'tiny_hunt': (16, 11, Z), 'other_hunt': (16, 15, Z)}, 'remove: content hunts in the wing %s' % res['slots'])
    pl = open(os.path.join(srv, 'data', 'lib', 'chaos_hunt_places.lua')).read()
    check('hall = false' in pl, 'remove: places file says so')
    again = digest(srv)
    go(hall_on=False)
    check(digest(srv) == again, 'remove: a second run changes nothing')
    go()
    stacks, tele, _f = map_state(srv)
    check(tele.get(hall['base_6_12_15']) == (710, 700, 7) and PORTAL not in stacks[(12, 15, Z)], 'order again after a remove')
    # too few slots: refused
    rows.append(dict(rows[0], id='base_6_99_11', x=99))
    H.write_csv(rows, csvp)
    try:
        go(dry=True)
        check(False, 'a base hunt off the hall refused')
    except (T.InstallError, H.HallError) as e:
        check('not a tile of the map' in str(e), 'refused: %s' % e)


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
              'monster = "Bog Rat"}' in pl,
              'places entry:\n' + pl)
        check('back = {x = 11, y = 13, z = 6}' in pl, 'back tile')
        once = digest(srv)
        res, _log = run(srv, plans, comp)
        check(digest(srv) == once, 'a second run changes nothing')
        check(res['room'] == 'done' and set(res['areas'].values()) == {'done'}, 'second run: all done')
        # a changed plan (other tiles) is refused
        make_area(comp['tiny_hunt'], 'tiny_hunt', (1000, 1000, 7), ground=101)
        try:
            run(srv, plans, comp)
            check(False, 'changed plan refused')
        except T.InstallError as e:
            check('changed' in str(e), 'changed plan: %s' % e)
        check(digest(srv) == once, 'refusal writes nothing')
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
    print('install_content_areas_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
