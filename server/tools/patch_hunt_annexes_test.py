#!/usr/bin/env python3
"""python3 -I server/tools/patch_hunt_annexes_test.py : patch_hunt_annexes.py on a synthetic map.

The portal (item 1387 with the annex's arrival as destination and a description) is put on the hunt's tile and the tile keeps its
ground and items; a row whose annex is not on the map is skipped; a tile that is no ground, one with another teleport and one
with a container are left alone; a dry run writes nothing, the real run writes the .bak and the tile count stays, a second run
changes nothing, --out leaves the map alone. The real hunt_annexes.json is well formed (every id has a plan in
areaplan/annexes/, no portal twice, portal and back differ). No base server needed (numpy for otbm.py)."""
import json, os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_hunt_annexes as T  # noqa: E402
import patch_map_fixes as PM  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


GRASS, SAND, BAG, TELE = 100, 101, 1987, 1387
KINDS = PM.Kinds({GRASS, SAND}, {300})


def t(ground, *items, flags=0):
    return dict(flags=flags, ground=ground, items=[i if isinstance(i, tuple) else (i, {}) for i in items])


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


def tiles_of(mp):
    m = otbm.load_otbm(mp)
    return {(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i])): [int(a) for a in m.stack(i)]
            for i in range(len(m.tiles['x']))}


def main():
    root = tempfile.mkdtemp(prefix='hunt_annexes_patch_test_')
    try:
        tiles = {}
        for y in range(10, 20):
            for x in range(10, 30):
                tiles[(x, y, 7)] = t(GRASS)
        tiles[(12, 12, 7)] = t(GRASS, 2100)                       # portal goes on a tile with decoration
        tiles[(14, 12, 7)] = t(None)                              # no ground
        tiles[(16, 12, 7)] = t(GRASS, (TELE, dict(tele=(5, 5, 7))))   # another teleport
        tiles[(18, 12, 7)] = t(GRASS, (BAG, {'kids': [2148]}))    # a container
        tiles[(20, 12, 7)] = t(GRASS)                             # annex not placed
        tiles[(500, 500, 9)] = t(SAND)                            # the annex's arrival (annex a is placed)
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'world'))
        mp = os.path.join(data, 'world', 'w.otbm')
        open(mp, 'wb').write(otbm_file(tiles))
        rows = {'annexes': [
            dict(id='a', name='Alpha', hunt='h1', portal=[12, 12, 7], dest=[500, 500, 9], back=[13, 12, 7]),
            dict(id='b', name='Beta', hunt='h2', portal=[14, 12, 7], dest=[500, 500, 9], back=[13, 12, 7]),
            dict(id='c', name='Gamma', hunt='h3', portal=[16, 12, 7], dest=[500, 500, 9], back=[13, 12, 7]),
            dict(id='d', name='Delta', hunt='h4', portal=[18, 12, 7], dest=[500, 500, 9], back=[13, 12, 7]),
            dict(id='e', name='Eps', hunt='h5', portal=[20, 12, 7], dest=[600, 600, 9], back=[13, 12, 7]),
        ]}
        rp = os.path.join(root, 'rows.json')
        json.dump(rows, open(rp, 'w'))
        before = open(mp, 'rb').read()
        log = []
        T.run(data, dry=True, map_path=mp, rows_path=rp, kinds=KINDS, log=log.append)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        out = os.path.join(root, 'out.otbm')
        T.run(data, map_path=mp, out=out, rows_path=rp, kinds=KINDS, log=log.append)
        check(open(mp, 'rb').read() == before and os.path.exists(out), '--out leaves the map alone')
        log = []
        res = T.run(data, map_path=mp, rows_path=rp, kinds=KINDS, log=log.append)
        check(res == dict(done=1, kept=0, skipped=1, left=3), 'counts: %s' % res)
        s = tiles_of(mp)
        check(s[(12, 12, 7)] == [GRASS, 2100, TELE], 'the portal is on top of the tile\'s items: %s' % s[(12, 12, 7)])
        check(s[(14, 12, 7)] == [] or GRASS not in s[(14, 12, 7)], 'a tile without ground gets nothing')
        check(s[(16, 12, 7)] == [GRASS, TELE], 'another teleport stays: %s' % s[(16, 12, 7)])
        check(s[(18, 12, 7)][:2] == [GRASS, BAG], 'a container tile is left alone')
        check(s[(20, 12, 7)] == [GRASS], 'an annex that is not placed gets no portal')
        check(len(s) == len(tiles), 'the tile count stays')
        data_bytes = open(mp, 'rb').read()
        check(b'A portal to the deeper part of this hunt (Alpha).' in data_bytes, 'the description is on the item')
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        after = open(mp, 'rb').read()
        log = []
        res = T.run(data, map_path=mp, rows_path=rp, kinds=KINDS, log=log.append)
        check(open(mp, 'rb').read() == after and res['done'] == 0 and res['kept'] == 1, 'a second run changes nothing: %s' % res)
        check(any('left alone' in l or 'another teleport' in l for l in log), 'the tiles left alone are listed: %s' % log)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    # the real file
    real = T.read_rows()
    ids = [r['id'] for r in real]
    check(len(ids) == 5 and len(set(ids)) == 5, 'five annexes')
    for r in real:
        check(os.path.isfile(os.path.join(HERE, 'areaplan', 'annexes', r['id'] + '.json')), '%s has a plan' % r['id'])
        check(r['portal'] != r['back'], '%s: the portal is not the way back' % r['id'])
    check(len({r['portal'] for r in real}) == len(real), 'no portal tile twice')
    if failed:
        print('%d failure(s)' % failed)
        return 1
    print('patch_hunt_annexes_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
