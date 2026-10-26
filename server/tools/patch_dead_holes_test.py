#!/usr/bin/env python3
"""python3 -I server/tools/patch_dead_holes_test.py : patch_dead_holes.py on a synthetic map.

A dead pitfall item goes (the ground stays), a dead stair that is a ground becomes the plain ground of the CSV, a ground
given as the tile's first item node too, a ramp too; a hole with a tile below is kept even though its row is there (a
lower floor mapped since); a tile with a container and a row whose item is not there are left alone; a `none` row too.
A dry run writes nothing, the real run writes the .bak and the tile count stays, a second run changes nothing, --out
leaves the map alone, and the checker finds nothing dead after the run. The real dead_holes.csv is well formed
(known actions, ground only on `ground` rows, no duplicate row, sorted). No base server needed (numpy for otbm.py)."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_dead_holes as T  # noqa: E402
import check_dead_holes as CD  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


GRASS, DIRT, WALL, PIT, STAIRS, RAMP_N, BAG = 100, 101, 300, 8250, 459, 1404, 1987
KINDS = CD.Kinds({GRASS, DIRT, STAIRS}, {WALL}, {PIT: {'down'}, STAIRS: {'down'}, RAMP_N: {'north'}},
                 {GRASS: 'grass', DIRT: 'dirt', PIT: 'pitfall', STAIRS: 'stairs', RAMP_N: 'ramp', WALL: 'wall'})
Z = 7


def t(ground, *items, flags=0):
    return dict(flags=flags, ground=ground, items=[i if isinstance(i, tuple) else (i, {}) for i in items])


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


def base_tiles():
    tiles = {}
    for y in range(10, 20):
        for x in range(10, 30):
            tiles[(x, y, Z)] = t(GRASS)
    tiles[(12, 12, Z)] = t(GRASS, PIT)                        # dead pitfall: item goes
    tiles[(14, 12, Z)] = t(STAIRS)                            # dead stair ground: becomes grass
    tiles[(16, 12, Z)] = t(None, STAIRS, PIT)                 # ground as an item node: the stair becomes grass, the pitfall goes
    tiles[(18, 12, Z)] = t(GRASS, RAMP_N)                     # dead ramp: goes
    tiles[(20, 12, Z)] = t(GRASS, PIT)                        # has a tile below now: kept
    tiles[(20, 12, Z + 1)] = t(DIRT)
    tiles[(22, 12, Z)] = t(GRASS, PIT, (BAG, {'kids': [2148]}))   # holds a container: left alone
    tiles[(24, 12, Z)] = t(GRASS)                             # the CSV row's item is not there
    tiles[(26, 12, Z)] = t(GRASS, PIT)                        # a `none` row
    tiles[(28, 12, Z)] = t(GRASS, PIT)                        # dead, not in the CSV: stays
    return tiles


ROWS = """# synthetic
x,y,z,item,action,ground,kind,why,area
12,12,7,8250,remove,,pitfall/down,void,base map
14,12,7,459,ground,101,stairs/down,void,base map
16,12,7,459,ground,101,stairs/down,void,base map
16,12,7,8250,remove,,pitfall/down,void,base map
18,12,7,1404,remove,,ramp/up,void,base map
20,12,7,8250,remove,,pitfall/down,void,base map
22,12,7,8250,remove,,pitfall/down,void,base map
24,12,7,8250,remove,,pitfall/down,void,base map
26,12,7,8250,none,,pitfall/down,void,base map
"""


def setup(root):
    data = os.path.join(root, 'data')
    os.makedirs(os.path.join(data, 'world'))
    mp = os.path.join(data, 'world', 'w.otbm')
    open(mp, 'wb').write(otbm_file(base_tiles()))
    lp = os.path.join(root, 'dead.csv')
    open(lp, 'w').write(ROWS)
    return data, mp, lp


def stacks(mp):
    m = otbm.load_otbm(mp)
    return {(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i])): [int(a) for a in m.stack(i)]
            for i in range(len(m.tiles['x']))}


def main():
    root = tempfile.mkdtemp(prefix='dead_holes_patch_test_')
    try:
        data, mp, lp = setup(root)
        before = open(mp, 'rb').read()
        log = []
        T.run(data, dry=True, map_path=mp, list_path=lp, kinds=KINDS, log=log.append)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        out = os.path.join(root, 'out.otbm')
        T.run(data, map_path=mp, out=out, list_path=lp, kinds=KINDS, log=log.append)
        check(open(mp, 'rb').read() == before and os.path.exists(out), '--out leaves the map alone')
        log = []
        done = T.run(data, map_path=mp, list_path=lp, kinds=KINDS, log=log.append)
        check(done == {'remove': 3, 'ground': 2}, 'counts: %s' % done)
        s = stacks(mp)
        check(s[(12, 12, Z)] == [GRASS], 'pitfall item gone, ground stays: %s' % s[(12, 12, Z)])
        check(s[(14, 12, Z)] == [DIRT], 'stair ground became the plain ground: %s' % s[(14, 12, Z)])
        check(s[(16, 12, Z)] == [DIRT], 'ground as an item node, pitfall gone: %s' % s[(16, 12, Z)])
        check(s[(18, 12, Z)] == [GRASS], 'ramp gone: %s' % s[(18, 12, Z)])
        check(s[(20, 12, Z)] == [GRASS, PIT], 'a hole with a tile below is kept: %s' % s[(20, 12, Z)])
        check(s[(22, 12, Z)][:2] == [GRASS, PIT], 'a tile with a container is left alone: %s' % s[(22, 12, Z)])
        check(s[(24, 12, Z)] == [GRASS] and s[(26, 12, Z)] == [GRASS, PIT] and s[(28, 12, Z)] == [GRASS, PIT],
              'not-there, none and unlisted rows change nothing')
        check(any('container' in l or 'contents' in l for l in log), 'the container tile is listed: %s' % log)
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        check(len(s) == len(base_tiles()), 'tile count unchanged')
        # a second run: nothing
        after = open(mp, 'rb').read()
        log = []
        done = T.run(data, map_path=mp, list_path=lp, kinds=KINDS, log=log.append)
        check(done == {} and open(mp, 'rb').read() == after, 'second run changes nothing: %s' % done)
        # the checker: what is dead now is only what the CSV left
        m = otbm.load_otbm(mp)
        rows = CD.changes(KINDS, CD.MapWorld(m), CD.positions_with_changes(m, KINDS))
        left = sorted(p for p, _i, r in rows if r['dead'])
        check(left == [(22, 12, Z), (26, 12, Z), (28, 12, Z)], 'dead after the run: %s' % left)
        # the real list
        rows = T.read_rows()
        keys = [(r['pos'], r['item']) for r in rows]
        check(len(rows) > 100 and len(set(keys)) == len(keys), 'dead_holes.csv: %d rows, no duplicate' % len(rows))
        check(keys == sorted(keys), 'dead_holes.csv is sorted by position')
        check(all(r['action'] != 'ground' or r['ground'] for r in rows), 'every ground row has its ground')
        try:
            open(os.path.join(root, 'bad.csv'), 'w').write('x,y,z,item,action,ground\n1,1,1,1,ground,\n')
            T.read_rows(os.path.join(root, 'bad.csv'))
            check(False, 'a ground row without ground is refused')
        except T.HoleError:
            pass
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('patch_dead_holes_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
