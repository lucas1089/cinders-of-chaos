#!/usr/bin/env python3
"""python3 -I server/tools/patch_crypt_floors_test.py : patch_crypt_floors.py on a synthetic map.

Ground 12237 inside a catacomb plan's rectangle (every floor of it) becomes 13189, the items on the tile stay; 12237 outside
the rectangle (other maps) and other grounds inside stay; a floor the plan does not have stays. A dry run writes nothing,
the real run writes the .bak, the tile count stays, a second run changes nothing and --out leaves the map alone. The real
catacomb plans are found. No base server needed."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_crypt_floors as T  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


SAND, DISC, SLATE, BONE = 13189, 12237, 10766, 2230
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


RECTS = [('crypt_hunt', 100, 100, 119, 109, Z, Z + 1)]


def base_tiles():
    tiles = {}
    for z in (Z, Z + 1, Z + 2):
        for y in range(98, 112):
            for x in range(98, 122):
                tiles[(x, y, z)] = t(SAND)
    tiles[(102, 102, Z)] = t(DISC, BONE)          # swapped, the bone stays
    tiles[(104, 102, Z)] = t(DISC)                # swapped
    tiles[(106, 102, Z + 1)] = t(DISC)            # second floor: swapped
    tiles[(108, 102, Z)] = t(SLATE, BONE)         # another ground: stays
    tiles[(99, 99, Z)] = t(DISC)                  # outside the rectangle: stays
    tiles[(104, 102, Z + 2)] = t(DISC)            # a floor the plan does not have: stays
    return tiles


def main():
    root = tempfile.mkdtemp(prefix='crypt_floors_test_')
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
        check(n == 3, 'changed %s tiles, expected 3' % n)
        check(s[(102, 102, Z)] == [SAND, BONE], 'disc swapped, bone stays: %s' % s[(102, 102, Z)])
        check(s[(104, 102, Z)] == [SAND], 'disc swapped: %s' % s[(104, 102, Z)])
        check(s[(106, 102, Z + 1)] == [SAND], 'second floor swapped: %s' % s[(106, 102, Z + 1)])
        check(s[(108, 102, Z)] == [SLATE, BONE], 'another ground stays')
        check(s[(99, 99, Z)] == [DISC] and s[(104, 102, Z + 2)] == [DISC], 'outside the plan stays')
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        check(len(s) == len(base_tiles()), 'tile count unchanged')
        after = open(mp, 'rb').read()
        n = T.run(data, map_path=mp, rects=RECTS, log=log.append)
        check(n == 0 and open(mp, 'rb').read() == after, 'second run changes nothing: %s' % n)
        ids = {r[0] for r in T.crypt_rects()}
        check({'hollow_crypt', 'bonechoir_catacomb', 'bonewright_galleries', 'graveknell_catacombs',
               'lanternless_catacombs'} <= ids, 'the real catacomb plans are found: %s' % sorted(ids))
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('patch_crypt_floors_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
