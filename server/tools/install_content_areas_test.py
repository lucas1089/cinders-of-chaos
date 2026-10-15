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
        # a reorder moves the display monsters
        cfg2 = dict(CFG, plans=[CFG['plans'][1], CFG['plans'][0]])
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
        # a plan missing from the config: a teleport after the listed ones, its most frequent monster on display
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
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('install_content_areas_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
