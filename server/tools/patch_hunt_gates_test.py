#!/usr/bin/env python3
"""python3 -I server/tools/patch_hunt_gates_test.py : patch_hunt_gates.py on a synthetic map.

A teleport item goes (the ground stays), a stair that is a ground becomes the plain ground of the CSV, a ground given as the
tile's first item node too, a ramp too; a tile with a container and a row whose item is not there are left alone; a `none` row
too, and a tile that is not in the list stays. A dry run writes nothing, the real run writes the .bak and the tile count stays,
a second run changes nothing, --out leaves the map alone. The real hunt_gates.csv is well formed (known actions, ground only on
`ground` rows, no duplicate row, sorted). No base server needed (numpy for otbm.py)."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_hunt_gates as T  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


GRASS, DIRT, TELE, STAIRS, RAMP_N, BAG = 100, 101, 1387, 459, 1404, 1987
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
    tiles[(12, 12, Z)] = t(GRASS, TELE)                       # a stock portal: the item goes
    tiles[(14, 12, Z)] = t(STAIRS)                            # stairs that are a ground: become dirt
    tiles[(16, 12, Z)] = t(None, STAIRS, TELE)                # ground as an item node: the stair becomes dirt, the portal goes
    tiles[(18, 12, Z)] = t(GRASS, RAMP_N)                     # a ramp: goes
    tiles[(22, 12, Z)] = t(GRASS, TELE, (BAG, {'kids': [2148]}))   # holds a container: left alone
    tiles[(24, 12, Z)] = t(GRASS)                             # the CSV row's item is not there
    tiles[(26, 12, Z)] = t(GRASS, TELE)                       # a `none` row
    tiles[(28, 12, Z)] = t(GRASS, TELE)                       # not in the CSV: stays
    return tiles


ROWS = """# synthetic
x,y,z,item,action,ground,kind,lands,far_level,hunt
12,12,7,1387,remove,,teleport,"500,500,7",300,Test Hunt
14,12,7,459,ground,101,stairs/down,"14,12,8",300,Test Hunt
16,12,7,459,ground,101,stairs/down,"16,12,8",300,Test Hunt
16,12,7,1387,remove,,teleport,"500,500,7",300,Test Hunt
18,12,7,1404,remove,,ramp/up,"18,11,6",300,Test Hunt
22,12,7,1387,remove,,teleport,"500,500,7",300,Test Hunt
24,12,7,1387,remove,,teleport,"500,500,7",300,Test Hunt
26,12,7,1387,none,,teleport,"500,500,7",300,Test Hunt
"""


def setup(root):
    data = os.path.join(root, 'data')
    os.makedirs(os.path.join(data, 'world'))
    mp = os.path.join(data, 'world', 'w.otbm')
    open(mp, 'wb').write(otbm_file(base_tiles()))
    lp = os.path.join(root, 'gates.csv')
    open(lp, 'w').write(ROWS)
    return data, mp, lp


def stacks(mp):
    m = otbm.load_otbm(mp)
    return {(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i])): [int(a) for a in m.stack(i)]
            for i in range(len(m.tiles['x']))}


def main():
    root = tempfile.mkdtemp(prefix='hunt_gates_patch_test_')
    try:
        data, mp, lp = setup(root)
        before = open(mp, 'rb').read()
        log = []
        T.run(data, dry=True, map_path=mp, list_path=lp, log=log.append)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        out = os.path.join(root, 'out.otbm')
        T.run(data, map_path=mp, out=out, list_path=lp, log=log.append)
        check(open(mp, 'rb').read() == before and os.path.exists(out), '--out leaves the map alone')
        log = []
        done = T.run(data, map_path=mp, list_path=lp, log=log.append)
        check(done == {'remove': 3, 'ground': 2}, 'counts: %s' % done)
        s = stacks(mp)
        check(s[(12, 12, Z)] == [GRASS], 'portal gone, ground stays: %s' % s[(12, 12, Z)])
        check(s[(14, 12, Z)] == [DIRT], 'stair ground became the plain ground: %s' % s[(14, 12, Z)])
        check(s[(16, 12, Z)] == [DIRT], 'ground as an item node, portal gone: %s' % s[(16, 12, Z)])
        check(s[(18, 12, Z)] == [GRASS], 'ramp gone: %s' % s[(18, 12, Z)])
        check(s[(22, 12, Z)][:2] == [GRASS, TELE], 'a tile with a container is left alone: %s' % s[(22, 12, Z)])
        check(s[(24, 12, Z)] == [GRASS] and s[(26, 12, Z)] == [GRASS, TELE] and s[(28, 12, Z)] == [GRASS, TELE],
              'not-there, none and unlisted rows change nothing')
        check(any('container' in l or 'contents' in l for l in log), 'the container tile is listed: %s' % log)
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        check(len(s) == len(base_tiles()), 'tile count unchanged')
        after = open(mp, 'rb').read()
        done = T.run(data, map_path=mp, list_path=lp, log=log.append)
        check(done == {} and open(mp, 'rb').read() == after, 'second run changes nothing: %s' % done)
        # the real list
        rows = T.read_rows()
        keys = [(r['pos'], r['item']) for r in rows]
        check(len(set(keys)) == len(keys), 'hunt_gates.csv: %d rows, no duplicate' % len(rows))
        check(keys == sorted(keys), 'hunt_gates.csv is sorted by position')
        check(all(r['action'] != 'ground' or r['ground'] for r in rows), 'every ground row has its ground')
        try:
            open(os.path.join(root, 'bad.csv'), 'w').write('x,y,z,item,action,ground\n1,1,1,1,ground,\n')
            T.read_rows(os.path.join(root, 'bad.csv'))
            check(False, 'a ground row without ground is refused')
        except T.GateError:
            pass
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('patch_hunt_gates_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
