#!/usr/bin/env python3
"""python3 -I server/tools/check_dead_holes_test.py : check_dead_holes.py on a synthetic tiny map (no map data needed).

Down: a hole over nothing (void), over a wall (blocked), over a ground (alive); a hole over a stair of the floor below
lands off its foot (south stair: one tile north) and is judged there; the engine takes the first of the stair kinds.
Up: a ramp north needs its tile one north, one floor up; a ladder or rope spot any of the nine tiles above; a sewer
grate any of the nine below; floor 0 has nothing above, floor 15 nothing below. A tile nobody can stand on (a roof
piece: blocking, no ground) is no hole. items.xml: id and fromid / toid entries, the otb bits. Areas by plan box.
plain_ground and patch_rows pick the ground a dead stair turns into. The map reader runs on a tiny OTBM written here.
"""
import os, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import check_dead_holes as T  # noqa: E402
import install_content_areas as IC  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


GRASS, DIRT, WALL, HOLE, PIT, STAIRS, RAMP_N, LADDER, GRATE, ROOF, STAIR_S, STAIR_E, ROPE = (
    100, 101, 300, 383, 8250, 459, 1404, 1386, 430, 9092, 1402, 1398, 384)
NAMES = {GRASS: 'grass', DIRT: 'dirt', WALL: 'stone wall', HOLE: 'hole', PIT: 'pitfall', STAIRS: 'stairs',
         RAMP_N: 'ramp', LADDER: 'ladder', GRATE: 'sewer grate', ROOF: 'roof', STAIR_S: 'ramp', STAIR_E: 'ramp',
         ROPE: 'dirt floor'}
KINDS = T.Kinds({GRASS, DIRT, HOLE, STAIRS, ROPE}, {WALL, ROOF},
                {HOLE: {'down'}, PIT: {'down'}, STAIRS: {'down'}, RAMP_N: {'north'}, STAIR_S: {'south'},
                 STAIR_E: {'east'}, ROOF: {'east'}}, NAMES)


def world(**tiles):
    return T.World(tiles)


def res(w, p):
    return T.check_tile(KINDS, w, p)


def main():
    # down
    w = T.World({(5, 5, 7): [GRASS, PIT], (5, 5, 8): [DIRT],
                 (10, 5, 7): [GRASS, PIT],
                 (15, 5, 7): [GRASS, PIT], (15, 5, 8): [DIRT, WALL],
                 (20, 5, 7): [HOLE],  # a ground that is the hole
                 (25, 5, 7): [GRASS, PIT], (25, 5, 8): [DIRT, STAIR_S], (25, 4, 8): [DIRT],
                 (30, 5, 7): [GRASS, PIT], (30, 5, 8): [DIRT, STAIR_S],
                 (35, 5, 7): [GRASS, PIT], (35, 5, 8): [DIRT, RAMP_N],
                 (40, 5, 15): [GRASS, PIT], (45, 5, 7): [GRASS, PIT], (45, 5, 8): [GRASS]})
    r = res(w, (5, 5, 7))
    check(r and not r['dead'] and r['land'] == (5, 5, 8), 'hole over a ground leads somewhere: %s' % r)
    r = res(w, (10, 5, 7))
    check(r and r['dead'] and r['why'] == 'void', 'hole over no tile is dead (void): %s' % r)
    r = res(w, (15, 5, 7))
    check(r and r['dead'] and r['why'] == 'blocked', 'hole over a wall is dead (blocked): %s' % r)
    r = res(w, (20, 5, 7))
    check(r and r['dead'] and r['why'] == 'void', 'a ground hole over nothing is dead: %s' % r)
    r = res(w, (25, 5, 7))
    check(r and not r['dead'] and r['land'] == (25, 4, 8), 'over a south stair it lands one tile north: %s' % r)
    r = res(w, (30, 5, 7))
    check(r and r['dead'] and r['land'] == (30, 4, 8), 'the landing beside the stair is judged, not the stair: %s' % r)
    r = res(w, (35, 5, 7))
    check(r and not r['dead'] and r['land'] == (35, 5, 8), 'a north stair below does not move the landing: %s' % r)
    r = res(w, (40, 5, 15))
    check(r and r['dead'] and r['why'] == 'void', 'floor 15 has nothing below: %s' % r)
    check(res(w, (50, 5, 7)) is None and res(w, (45, 5, 8)) is None, 'no floor change, no result')
    # up
    w = T.World({(5, 5, 7): [GRASS, RAMP_N], (5, 4, 6): [DIRT],
                 (10, 5, 7): [GRASS, RAMP_N], (10, 4, 6): [DIRT, WALL],
                 (15, 5, 7): [GRASS, STAIR_E], (16, 5, 6): [GRASS],
                 (20, 5, 7): [GRASS, LADDER], (21, 6, 6): [GRASS],
                 (25, 5, 7): [GRASS, LADDER],
                 (30, 5, 7): [ROPE], (31, 4, 6): [DIRT],
                 (35, 5, 0): [GRASS, RAMP_N],
                 (40, 5, 7): [GRASS, GRATE], (41, 6, 8): [DIRT],
                 (45, 5, 7): [GRASS, GRATE], (45, 5, 8): [DIRT, WALL],
                 (50, 5, 7): [ROOF], (55, 5, 7): [GRASS, ROOF]})
    r = res(w, (5, 5, 7))
    check(r and not r['dead'] and r['dir'] == 'up' and r['land'] == (5, 4, 6), 'ramp north: %s' % r)
    r = res(w, (10, 5, 7))
    check(r and r['dead'] and r['why'] == 'blocked', 'ramp up to a wall is dead: %s' % r)
    r = res(w, (15, 5, 7))
    check(r and not r['dead'] and r['land'] == (16, 5, 6), 'ramp east goes one tile east: %s' % r)
    r = res(w, (20, 5, 7))
    check(r and not r['dead'] and r['land'] == (21, 6, 6), 'a ladder takes any of the nine tiles above: %s' % r)
    r = res(w, (25, 5, 7))
    check(r and r['dead'] and r['why'] == 'void', 'a ladder under nothing is dead: %s' % r)
    r = res(w, (30, 5, 7))
    check(r and not r['dead'], 'a rope spot under a ceiling hole: %s' % r)
    r = res(w, (35, 5, 0))
    check(r and r['dead'], 'floor 0 has nothing above: %s' % r)
    r = res(w, (40, 5, 7))
    check(r and not r['dead'] and r['land'] == (41, 6, 8), 'a sewer grate takes any of the nine tiles below: %s' % r)
    r = res(w, (45, 5, 7))
    check(r and r['dead'] and r['why'] == 'blocked', 'a grate over a wall is dead: %s' % r)
    check(res(w, (50, 5, 7)) is None, 'a roof piece on no ground is no hole')
    check(res(w, (55, 5, 7)) is None, 'a blocking roof piece is no hole')
    # report, labels, kinds
    rows = T.changes(KINDS, w, [(5, 5, 7), (10, 5, 7), (25, 5, 7), (99, 99, 7)])
    check([p for p, _i, _r in rows] == [(5, 5, 7), (10, 5, 7), (25, 5, 7)], 'changes: %s' % rows)
    lines = []
    areas = [('boneyard', 'Boneyard', 0, 0, 6, 12, 9, 7)]
    dead, by_area = T.report(rows, areas, False, lines.append)
    check(len(dead) == 2 and by_area == {'boneyard': 1, T.AREA_BASE: 1}, 'report by area: %s %s' % (len(dead), dict(by_area)))
    check(T.area_of(areas, (13, 5, 7)) == T.AREA_BASE and T.area_of(areas, (12, 9, 6)) == 'boneyard', 'area boxes')
    check(KINDS.label(PIT) == 'pitfall' and KINDS.label(ROPE) == 'rope' and KINDS.label(LADDER) == 'ladder', 'labels')
    kc = T.labelled(KINDS, dead)
    check(kc == {'ramp/up': 1, 'ladder/up': 1}, 'kinds counted: %s' % dict(kc))
    # the ground a dead stair turns into
    w = T.World({(5, 5, 7): [STAIRS], (4, 5, 7): [GRASS], (6, 5, 7): [DIRT], (5, 4, 7): [DIRT], (5, 6, 7): [DIRT, WALL],
                 (4, 4, 7): [HOLE]})
    check(T.plain_ground(KINDS, w, (5, 5, 7)) == DIRT, 'plain ground: the commonest walkable round it')
    check(T.plain_ground(KINDS, T.World({(5, 5, 7): [STAIRS]}), (5, 5, 7)) is None, 'no ground near: None')
    w.tiles[(5, 5, 7)] = [STAIRS]
    dead2 = [((5, 5, 7), [STAIRS], dict(dir='down', land=(5, 5, 8), why='void', dead=True), 'x'),
             ((4, 4, 7), [PIT], dict(dir='down', land=(4, 4, 8), why='void', dead=True), 'x')]
    w.tiles[(4, 4, 7)] = [DIRT, PIT]
    pr = T.patch_rows(KINDS, w, dead2)
    check(pr[0][3:6] == (STAIRS, 'ground', DIRT) and pr[1][3:6] == (PIT, 'remove', ''), 'patch rows: %s' % (pr,))
    # items.xml: id, fromid / toid, the engine's values only
    d = tempfile.mkdtemp(prefix='dead_holes_test_')
    try:
        xp = os.path.join(d, 'items.xml')
        open(xp, 'w').write('<items>\n<item id="383" name="hole"><attribute key="floorchange" value="down" /></item>\n'
                            '<item fromid="8279" toid="8281" name="trapdoor"><attribute key="floorchange" value="Down"/></item>\n'
                            '<item id="1" name="x" />\n<item id="2" name="y"><attribute key="weight" value="1"/></item>\n</items>\n')
        fc = T.read_xml_floorchange(xp)
        check(fc == {383: {'down'}, 8279: {'down'}, 8280: {'down'}, 8281: {'down'}}, 'items.xml floorchange: %s' % fc)
        # a tiny OTBM: positions_with_changes finds the tiles with floor change items, MapWorld reads them
        tiles = {(5, 5, 7): dict(flags=0, ground=GRASS, items=[(PIT, {})]), (6, 5, 7): dict(flags=0, ground=GRASS, items=[]),
                 (5, 5, 8): dict(flags=0, ground=DIRT, items=[]), (9, 9, 7): dict(flags=0, ground=None, items=[(HOLE, {})]),
                 (7, 5, 7): dict(flags=0, ground=GRASS, items=[(GRATE, {})])}
        esc = IC._esc
        root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
        md = b'\xFE' + esc(bytes([2]))
        towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
        mp = os.path.join(d, 'm.otbm')
        open(mp, 'wb').write(b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF')
        import otbm
        m = otbm.load_otbm(mp)
        pos = T.positions_with_changes(m, KINDS)
        check(pos == [(5, 5, 7), (7, 5, 7), (9, 9, 7)], 'positions with floor changes: %s' % pos)
        mw = T.MapWorld(m)
        rows = T.changes(KINDS, mw, pos)
        check([r['dead'] for _p, _i, r in rows] == [False, True, True], 'map rows: %s' % [(p, r['dead']) for p, _i, r in rows])
        check(mw.tile(5, 5, 7) == [GRASS, PIT] and mw.tile(1, 1, 1) is None and mw.tile(5, 5, -1) is None, 'MapWorld reads')
        csvp = os.path.join(d, 'out.csv')
        dead, _a = T.report(rows, [], False, lambda *_: None)
        T.write_csv(csvp, T.patch_rows(KINDS, mw, dead))
        lines = [l for l in open(csvp) if not l.startswith('#')]
        check(lines[0].startswith('x,y,z,item,action,ground,kind,why,area') and len(lines) == 3, 'csv: %s' % lines)
        check(T.main([mp]) == 2, 'no items.otb: usage error, not a crash')
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)
    print('check_dead_holes_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
