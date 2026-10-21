#!/usr/bin/env python3
"""python3 -I server/tools/patch_map_fixes_test.py : patch_map_fixes.py on a synthetic map.

Teleports: a destination is set (and kept on a second run), a junk teleport goes, one with an action id stays, a
boat loses its destination, a row for a tile without the item is skipped, a destination on a blocking tile refuses
the run. Hub: every missing tile of the box becomes water, a wall standing on nothing gets its neighbours' ground,
the shore tile beside the new water gets the border pieces of its sides (one side, two sides and the corner, a corner
only) in place of the old ones. Temples: the arcade's rows rewritten (marble, protection zone, stands bare, partitions,
the coal basin on the outer end, counters in turn, the carpet's corners and edges), a lamp added; an arcade tile with
an action id refuses the run. A dry run writes nothing, a second run changes nothing, the real configs and CSV hold
together (every destination row differs from its tile, the arcade mirrored, stands = the config's NPCs). No base
server needed (numpy for tools/map/otbm.py)."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_map_fixes as T  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


GRASS, WATER, MARBLE, WALL, PORTAL, BOAT, ROCK = 100, 200, 406, 300, 1387, 3593, 310
B = dict(n=29166, e=29167, w=29168, s=29177, dnw=29169, dne=29170, dsw=29171, dse=29172, cnw=29173, cne=29174,
         csw=29175, cse=29176)
KINDS = T.Kinds({GRASS, WATER, MARBLE}, {WALL, ROCK} | set(B.values()) | {1642, 1643, 1644, 1484, 1479})
Z = 7


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


def t(ground, *items, flags=0):
    return dict(flags=flags, ground=ground, items=[i if isinstance(i, tuple) else (i, {}) for i in items])


def base_tiles():
    tiles = {}
    # a land strip x 10-29, y 10-19 (teleports, temple)
    for y in range(10, 20):
        for x in range(10, 30):
            tiles[(x, y, Z)] = t(GRASS)
    tiles[(12, 12, Z)] = t(GRASS, (PORTAL, {'tele': (900, 900, 9)}))     # destination: no tile -> fixed
    tiles[(13, 12, Z)] = t(GRASS, PORTAL)                                 # no destination: junk -> removed
    tiles[(14, 12, Z)] = t(GRASS, (PORTAL, {'aid': 30025}))               # scripted: stays
    tiles[(15, 12, Z)] = t(GRASS, (BOAT, {'tele': (8000, 8000, 0)}))      # boat: destination off
    tiles[(16, 12, Z)] = t(GRASS, ROCK)                                   # a blocking tile
    tiles[(18, 12, Z)] = t(GRASS, (PORTAL, {'tele': (5000, 5000, 7)}))    # a destination that is no tile: junk
    tiles[(19, 12, Z)] = t(GRASS, (PORTAL, {'tele': (26, 18, 7)}))        # leads somewhere real: stays
    # the hub box x 40-47, y 40-46: water x 40-41, land x 42-44 (a shore column at 44), void x 45-47
    for y in range(40, 47):
        for x in range(40, 45):
            tiles[(x, y, Z)] = t(WATER if x < 42 else GRASS)
    tiles[(43, 43, Z)] = t(None, WALL)                                    # a wall on nothing
    tiles[(44, 41, Z)] = t(GRASS, B['n'])                                 # an old border piece (replaced)
    del tiles[(44, 40, Z)]                                                # void north of it: corner pieces
    return tiles


ROWS = """x,y,z,item,action,to_x,to_y,to_z,note
12,12,7,1387,dest,26,18,7,"fix"
13,12,7,1387,remove,,,,"junk"
14,12,7,1387,remove,,,,"scripted: stays"
15,12,7,3593,nodest,,,,"boat"
17,12,7,1387,remove,,,,"not there"
18,12,7,1387,remove,,,,"leads to no tile"
19,12,7,1387,remove,,,,"leads somewhere: stays"
"""

HUB = """return {hall = {fill = {z = 7, x = {40, 47}, y = {40, 46}, water = {%d},
	shore = {%d}, borders = {n = 29166, e = 29167, w = 29168, s = 29177, dnw = 29169, dne = 29170, dsw = 29171,
	dse = 29172, cnw = 29173, cne = 29174, csw = 29175, cse = 29176}}}}
""" % (WATER, GRASS)

TEMPLE = """return {enabled = true,
	items = {floor = 406, counter = {1642, 1643}, partition = 1644, light = 1484, plant = 8011, lamp = 1479,
		carpet = {nw = 4394, n = 4395, ne = 4396, w = 4397, c = 4398, e = 4399, sw = 4400, s = 4401, se = 4402}},
	towns = {{town = 2, name = "Town", temple = {x = 25, y = 11, z = 7}, z = 7, npcRow = 14, counterRow = 15,
		aisle = {16, 17}, wings = {{from = 18, to = 23, outer = 18}},
		stands = {{name = "A", x = 23}, {name = "B", x = 21}}, free = {19}, lamps = {{x = 22, y = 18}}}}}
"""


def setup(root, rows=ROWS, temple=TEMPLE, tiles=None):
    data = os.path.join(root, 'data')
    os.makedirs(os.path.join(data, 'world'))
    mp = os.path.join(data, 'world', 'w.otbm')
    open(mp, 'wb').write(otbm_file(tiles or base_tiles()))
    paths = {}
    for name, text in (('fixes.csv', rows), ('hub.lua', HUB), ('temple.lua', temple)):
        p = os.path.join(root, name)
        open(p, 'w').write(text)
        paths[name] = p
    return data, mp, paths


def run(data, mp, paths, **kw):
    log = []
    res = T.run(data, map_path=mp, fixes_path=paths['fixes.csv'], hunt_config=paths['hub.lua'],
                temple_config=paths['temple.lua'], kinds=KINDS, log=log.append, **kw)
    return res, log


def tiles_of(mp):
    m = otbm.load_otbm(mp)
    out = {}
    for i in range(len(m.tiles['x'])):
        out[(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i]))] = (
            [int(a) for a in m.stack(i)], int(m.tiles['flags'][i]))
    tele = {(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i])): tuple(d)
            for i, _iid, d in otbm.teleports(m, [PORTAL, BOAT])}
    return out, tele


def main():
    root = tempfile.mkdtemp(prefix='map_fixes_test_')
    try:
        data, mp, paths = setup(os.path.join(root, 'a'))
        before = open(mp, 'rb').read()
        res, log = run(data, mp, paths, dry=True)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        check(res['teleports'] == 4 and res['added'] == 22, 'dry run counts: %s' % res)
        res, log = run(data, mp, paths)
        check(os.path.exists(mp + '.bak'), 'backup written')
        tl, tele = tiles_of(mp)
        # teleports
        check(tele.get((12, 12, Z)) == (26, 18, Z), 'destination fixed: %s' % tele)
        check(tl[(13, 12, Z)][0] == [GRASS], 'junk teleport removed')
        check(PORTAL in tl[(14, 12, Z)][0], 'a teleport with an action id stays')
        check(tl[(18, 12, Z)][0] == [GRASS], 'a teleport whose destination is no tile is removed')
        check(PORTAL in tl[(19, 12, Z)][0] and tele.get((19, 12, Z)) == (26, 18, Z), 'one that leads to a tile stays')
        check(tl[(15, 12, Z)][0] == [GRASS, BOAT] and (15, 12, Z) not in tele, 'the boat keeps its place, no destination')
        # hub
        for y in range(40, 47):
            for x in range(45, 48):
                check(tl.get((x, y, Z), ([None],))[0] == [WATER], 'water at %d,%d' % (x, y))
        check(tl[(44, 40, Z)][0] == [WATER], 'the void north of the shore filled')
        check(tl[(43, 43, Z)][0] == [GRASS, WALL], 'the wall stands on its neighbours\' ground: %s' % tl[(43, 43, Z)][0])
        check(tl[(44, 42, Z)][0] == [GRASS, B['e']], 'a shore tile with water east: %s' % tl[(44, 42, Z)][0])
        check(tl[(44, 41, Z)][0] == [GRASS, B['dne']], 'water north and east: the d piece, the old piece gone: %s'
              % tl[(44, 41, Z)][0])
        check(tl[(43, 41, Z)][0] == [GRASS, B['cne']], 'water only at the north-east corner: %s' % tl[(43, 41, Z)][0])
        check(tl[(42, 43, Z)][0] == [GRASS], 'a tile away from the new water is left alone')
        check(tl[(41, 43, Z)][0] == [WATER], 'old water untouched')
        # temple arcade
        check(tl[(23, 14, Z)] == ([MARBLE], 1) and tl[(21, 14, Z)] == ([MARBLE], 1), 'stands bare, marble, PZ')
        check(tl[(22, 14, Z)][0] == [MARBLE, 1644] and tl[(20, 14, Z)][0] == [MARBLE, 1644], 'partitions between')
        check(tl[(19, 14, Z)][0] == [MARBLE, 8011], 'plants on the free booth')
        check(tl[(18, 14, Z)][0] == [MARBLE, 1484], 'the coal basin on the outer end')
        check([tl[(x, 15, Z)][0][1] for x in range(18, 24)] == [1642, 1643] * 3, 'the counters in turn')
        check(tl[(18, 16, Z)][0] == [MARBLE, 4394] and tl[(23, 16, Z)][0] == [MARBLE, 4396]
              and tl[(20, 16, Z)][0] == [MARBLE, 4395], 'carpet north row: corners and edge')
        check(tl[(18, 17, Z)][0] == [MARBLE, 4400] and tl[(23, 17, Z)][0] == [MARBLE, 4402]
              and tl[(21, 17, Z)][0] == [MARBLE, 4401], 'carpet south row')
        check(all(tl[(x, y, Z)][1] & 1 for x in range(18, 24) for y in range(14, 18)), 'the arcade is protection zone')
        check(tl[(22, 18, Z)][0] == [GRASS, 1479], 'the lamp added')
        check(tl[(24, 14, Z)][0] == [GRASS], 'outside the wing untouched')
        # second run
        after = open(mp, 'rb').read()
        res, log = run(data, mp, paths)
        check(open(mp, 'rb').read() == after and res['changed'] == 0 and res['added'] == 0,
              'a second run changes nothing: %s' % res)

        # refusals
        bad = ROWS.replace('12,12,7,1387,dest,26,18,7', '12,12,7,1387,dest,16,12,7')
        data, mp, paths = setup(os.path.join(root, 'b'), rows=bad)
        before = open(mp, 'rb').read()
        try:
            run(data, mp, paths)
            check(False, 'a destination on a blocking tile is refused')
        except T.FixError as e:
            check('not a free tile' in str(e), 'refusal names the destination: %s' % e)
        check(open(mp, 'rb').read() == before, 'a refusal writes nothing')
        tiles = base_tiles()
        tiles[(20, 16, Z)] = t(GRASS, (1945, {'aid': 1000}))
        data, mp, paths = setup(os.path.join(root, 'c'), tiles=tiles)
        try:
            run(data, mp, paths, only=('temples',))
            check(False, 'an arcade tile with an action id is refused')
        except T.FixError as e:
            check('action id' in str(e), 'refusal: %s' % e)

        # the earlier quest hall's tiles belong to install_content_areas.py: plain fill water, no border on them
        data, mp, paths = setup(os.path.join(root, 'd'))
        real = T.previous_hall
        T.previous_hall = lambda cfg: ({(46, 40, Z), (44, 42, Z)}, 999)
        try:
            run(data, mp, paths, only=('hub',))
        finally:
            T.previous_hall = real
        tl, _tele = tiles_of(mp)
        check(tl[(46, 40, Z)][0] == [999], 'a missing tile of the earlier hall gets its plain fill water')
        check(tl[(44, 42, Z)][0] == [GRASS], 'a tile of the earlier hall gets no border')
        check(tl[(44, 43, Z)][0] == [GRASS, B['e']], 'its neighbours do')

        # the pieces of a shore tile
        check(T.border_pieces(['n', 'w', 'nw'], B) == [B['dnw']], 'two sides and a corner')
        check(T.border_pieces(['se'], B) == [B['cse']], 'a corner only')
        check(T.border_pieces(['n', 'ne', 'nw'], B) == [B['n']], 'one side covers its corners')
        check(T.border_pieces(['s', 'nw'], B) == [B['s'], B['cnw']], 'a side and the far corner')

        # the real inputs hold together
        rows = T.read_fixes()
        keep = [r for r in rows if r['action'] != 'remove']  # two junk items on one tile: two remove rows
        check(len(rows) > 0 and len({r['pos'] + (r['item'],) for r in keep}) == len(keep),
              'teleport_fixes.csv: one destination row per item')
        for r in rows:
            if r['action'] == 'dest':
                check(r['to'] != r['pos'], 'a destination is not the teleport\'s own tile: %s' % (r,))
        tcfg = IC.load_config(T.TEMPLE_CONFIG)
        for town in tcfg['towns']:
            want, lamps = T.arcade_tiles(town, tcfg['items'])
            mid = town['temple']['x']
            for (x, y, z), tile in want.items():
                m = want.get((2 * mid - x, y, z))
                check(m is not None, 'the arcade is mirrored round the temple: %d,%d' % (x, y))
                if m and y == town['npcRow']:
                    check(bool(m['items']) == bool(tile['items']), 'a stand mirrors a stand: %d' % x)
            for s in town['stands']:
                check(want[(s['x'], town['npcRow'], town['z'])]['items'] == [], '%s stands on a bare tile' % s['name'])
        hub = IC.load_config(T.HUNT_CONFIG)['hall']['fill']
        check(set(hub['borders']) == set(B), 'the hub fill names every border piece')
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('patch_map_fixes_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
