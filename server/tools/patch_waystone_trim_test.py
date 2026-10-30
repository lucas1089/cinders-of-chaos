#!/usr/bin/env python3
"""python3 -I server/tools/patch_waystone_trim_test.py : patch_waystone_trim.py on a synthetic map.

The wall piece goes on top of the neck tile's items; a tile that has it already, one with no ground and one with a container are
left alone; a dry run writes nothing, the real run writes the .bak and the tile count stays, a second run changes nothing, --out
leaves the map alone. The real waystone_trim.json is well formed (rows of four integers, maps 9 or 12 only). No base server needed (numpy for otbm.py)."""
import json, os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_waystone_trim as T  # noqa: E402
import patch_map_fixes as PM  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


SAND, WALL, BAG = 100, 3454, 1987
KINDS = PM.Kinds({SAND}, {WALL})


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


def main():
    root = tempfile.mkdtemp(prefix='waystone_trim_test_')
    try:
        tiles = {(x, y, 7): t(SAND) for y in range(10, 14) for x in range(10, 20)}
        tiles[(12, 11, 7)] = t(SAND, 2100)            # decoration under the wall piece
        tiles[(13, 11, 7)] = t(SAND, WALL)            # the piece is there already
        tiles[(14, 11, 7)] = t(None)                  # no ground
        tiles[(15, 11, 7)] = t(SAND, (BAG, {'kids': [2148]}))   # a container
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'world'))
        mp = os.path.join(data, 'world', 'w.otbm')
        open(mp, 'wb').write(otbm_file(tiles))
        rp = os.path.join(root, 'trim.json')
        json.dump({'maps': [{'map': 9, 'items': [[11, 11, 7, WALL], [12, 11, 7, WALL], [13, 11, 7, WALL], [14, 11, 7, WALL], [15, 11, 7, WALL]]}]}, open(rp, 'w'))
        before = open(mp, 'rb').read()
        log = []
        T.run(data, dry=True, map_path=mp, rows_path=rp, kinds=KINDS, log=log.append)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        out = os.path.join(root, 'out.otbm')
        T.run(data, map_path=mp, out=out, rows_path=rp, kinds=KINDS, log=log.append)
        check(open(mp, 'rb').read() == before and os.path.exists(out), '--out leaves the map alone')
        res = T.run(data, map_path=mp, rows_path=rp, kinds=KINDS, log=log.append)
        check(res == dict(done=2, kept=1, left=2), 'counts: %s' % res)
        s = stacks(mp)
        check(s[(11, 11, 7)] == [SAND, WALL], 'a bare tile gets the piece: %s' % s[(11, 11, 7)])
        check(s[(12, 11, 7)] == [SAND, 2100, WALL], 'the piece goes on top of the decoration: %s' % s[(12, 11, 7)])
        check(s[(13, 11, 7)] == [SAND, WALL], 'a tile with the piece is not stacked')
        check(s[(15, 11, 7)][:2] == [SAND, BAG], 'a container tile is left alone')
        check(len(s) == len(tiles), 'the tile count stays')
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        after = open(mp, 'rb').read()
        res = T.run(data, map_path=mp, rows_path=rp, kinds=KINDS, log=log.append)
        check(open(mp, 'rb').read() == after and res['done'] == 0, 'a second run changes nothing: %s' % res)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    rows = T.read_rows()
    check(all(r['map'] in (9, 12) for r in rows), 'the real file names waystone maps 9 and 12 only')
    check(all(len(it) == 4 for r in rows for it in r['items']), 'rows of four integers')
    check(all(it[3] >= 100 for r in rows for it in r['items']), 'real item ids')
    if failed:
        print('%d failure(s)' % failed)
        return 1
    print('patch_waystone_trim_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
