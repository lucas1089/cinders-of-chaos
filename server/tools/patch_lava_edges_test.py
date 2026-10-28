#!/usr/bin/env python3
"""python3 -I server/tools/patch_lava_edges_test.py : patch_lava_edges.py on a synthetic map.

The edge items 5840-5843 go off the tiles inside a lava plan's rectangle (every floor of it), the ground and the other
items stay; the same items outside the rectangle (the base map's own lava caves) stay; a tile with a container is left
alone. A dry run writes nothing, the real run writes the .bak, the tile count stays, a second run changes nothing and
--out leaves the map alone. The real lava plans are found (every plan of the lava and waste biomes). No base server needed."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_lava_edges as T  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


ROCK, ROCK2, ROCK3, BONE, BAG = 9068, 9069, 17625, 2230, 1987
Z = 10


def t(ground, *items):
    return dict(flags=0, ground=ground, items=[i if isinstance(i, tuple) else (i, {}) for i in items])


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


def stacks(mp):
    m = otbm.load_otbm(mp)
    return {(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i])): [int(a) for a in m.stack(i)]
            for i in range(len(m.tiles['x']))}


RECTS = [('lava_hunt', 100, 100, 119, 109, Z, Z + 1)]


def base_tiles():
    tiles = {}
    for z in (Z, Z + 1, Z + 2):
        for y in range(98, 112):
            for x in range(98, 122):
                tiles[(x, y, z)] = t(ROCK)
    tiles[(102, 102, Z)] = t(ROCK, 5840, BONE)          # strip: goes, the bone stays
    tiles[(104, 102, Z)] = t(ROCK, 5842)                # bar: goes
    tiles[(106, 102, Z + 1)] = t(ROCK, 5841, 5843)      # second floor: both go
    tiles[(108, 102, Z)] = t(ROCK, 5843, (BAG, {'kids': [2148]}))  # container: left alone
    tiles[(110, 102, Z)] = t(ROCK, BONE)                # nothing to do
    tiles[(99, 99, Z)] = t(ROCK, 5840)                  # outside the rectangle: stays
    tiles[(104, 102, Z + 2)] = t(ROCK, 5842)            # a floor the plan does not have: stays
    return tiles


def main():
    root = tempfile.mkdtemp(prefix='lava_edges_test_')
    try:
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'world'))
        mp = os.path.join(data, 'world', 'w.otbm')
        open(mp, 'wb').write(otbm_file(base_tiles()))
        before = open(mp, 'rb').read()
        log = []
        T.run(data, dry=True, map_path=mp, rects=RECTS, log=log.append)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        out = os.path.join(root, 'out.otbm')
        T.run(data, map_path=mp, out=out, rects=RECTS, log=log.append)
        check(open(mp, 'rb').read() == before and os.path.exists(out), '--out leaves the map alone')
        n = T.run(data, map_path=mp, rects=RECTS, log=log.append)
        s = stacks(mp)
        check(n == 4, 'removed %s, expected 4' % n)
        check(s[(102, 102, Z)] == [ROCK, BONE], 'strip gone, bone stays: %s' % s[(102, 102, Z)])
        check(s[(104, 102, Z)] == [ROCK], 'bar gone: %s' % s[(104, 102, Z)])
        check(s[(106, 102, Z + 1)] == [ROCK], 'both strips of the second floor gone: %s' % s[(106, 102, Z + 1)])
        check(5843 in s[(108, 102, Z)], 'a tile with a container is left alone: %s' % s[(108, 102, Z)])
        check(s[(110, 102, Z)] == [ROCK, BONE], 'a clean tile is untouched')
        check(s[(99, 99, Z)] == [ROCK, 5840] and s[(104, 102, Z + 2)] == [ROCK, 5842], 'outside the plan stays')
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        check(len(s) == len(base_tiles()), 'tile count unchanged')
        after = open(mp, 'rb').read()
        n = T.run(data, map_path=mp, rects=RECTS, log=log.append)
        check(n == 0 and open(mp, 'rb').read() == after, 'second run changes nothing: %s' % n)
        rects = T.lava_rects()
        ids = {r[0] for r in rects}
        check('ironhorn_slagworks' in ids and len(ids) >= 10, 'the real lava plans are found: %d' % len(ids))
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('patch_lava_edges_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
