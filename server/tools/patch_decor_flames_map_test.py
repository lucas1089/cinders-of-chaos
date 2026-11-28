#!/usr/bin/env python3
"""python3 -I server/tools/patch_decor_flames_map_test.py : patch_decor_flames_map.py on a synthetic map (O788).

A brazier added on open floor, a still coal basin swapped for a brazier in its place in the stack, a candle on an altar, a
candelabrum swapped for a candle, a cold spirit flame on floor; a dry run and --out leave the map alone; the real run writes
the .bak, keeps the tile count and touches only the listed tiles; a second run changes nothing. Each refusal leaves the map
as it was and names the spot: a wrong top item, a missing old item, an old item with an action id, a door, a spawn centre,
a house tile, a 2x2 flame reaching over a wall, a brazier that cuts a one tile way, no tile. Bad csv rows are refused. The
client pair guard skips below pair 74. The map write guard refuses a writer that also cuts a far tile. The real
decor_flames_map.csv is well formed. No base server needed (numpy for otbm.py)."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_decor_flames_map as F  # noqa: E402
import install_content_areas as IC  # noqa: E402
import map_guard_testkit as K  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


SAND, WALL, BASIN, CANDELABRUM, ALTAR, DOOR, TABLE = 100, 1050, 1481, 2057, 2606, 1209, 1619
KINDS = F.Kinds({SAND}, {WALL, BASIN, ALTAR}, {DOOR})
HEAD = 'x,y,z,item,action,old,on,why\n'


def tiles():
    """{pos: [item nodes]} of a 21 x 13 field of sand on floor 7 with a few things on it"""
    t = {(x, y, 7): [K.item(SAND)] for y in range(10, 23) for x in range(10, 31)}
    t[(12, 12, 7)] = [K.item(SAND), K.item(BASIN)]                     # a still coal basin, free floor west and north
    t[(25, 12, 7)] = [K.item(SAND), K.item(ALTAR)]
    t[(26, 12, 7)] = [K.item(SAND), K.item(TABLE), K.item(CANDELABRUM)]
    t[(28, 12, 7)] = [K.item(SAND), K.item(BASIN, bytes([4]) + struct.pack('<H', 4100))]   # a basin with an action id
    t[(14, 14, 7)] = [K.item(SAND), K.item(DOOR)]
    t[(18, 14, 7)] = [K.item(SAND), K.item(WALL)]                      # north-west of (19, 15)
    t[(24, 15, 7)] = K.tile_node((24, 15, 7), [K.item(SAND)], house=7)
    for x in range(10, 31):                                           # a one tile way along y 21 between walls
        t[(x, 20, 7)] = [K.item(SAND), K.item(WALL)]
        t[(x, 22, 7)] = [K.item(SAND), K.item(WALL)]
    return t


def make_map(path):
    open(path, 'wb').write(K.build(tiles()))


def spawn_xml(path):
    open(path, 'w').write('<?xml version="1.0"?>\n<spawns>\n<spawn centerx="16" centery="17" centerz="7" radius="2">\n'
                          '<monster name="Rat" x="1" y="0" z="7" spawntime="60" />\n</spawn>\n</spawns>\n')


def stacks(mp):
    m = otbm.load_otbm(mp)
    return {(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i])): [int(a) for a in m.stack(i)]
            for i in range(len(m.tiles['x']))}


def rows_file(root, name, lines):
    p = os.path.join(root, name)
    open(p, 'w').write(HEAD + ''.join(l + '\n' for l in lines))
    return p


GOOD = ['20,16,7,48560,add,,100,a brazier on open floor',
        '12,12,7,48560,swap,1481,,a still coal basin made a brazier',
        '25,12,7,48562,add,,2606,a candle on the altar',
        '26,12,7,48562,swap,2057,,the candelabrum made a candle',
        '22,18,7,48563,add,,100,a cold spirit flame on floor',
        '27,17,7,48561,add,,100,a campfire on open floor']

BAD = [('23,13,7,48560,add,,2606,wrong top', 'its top item is 100, not 2606'),
       ('21,13,7,48562,swap,2057,,missing old', 'the tile holds 0 of 2057'),
       ('28,12,7,48562,swap,1481,,a basin with an action id', 'carries attributes'),
       ('14,14,7,48562,add,,1209,on a door', 'a door, teleport or floor change'),
       ('16,17,7,48562,add,,100,on the spawn centre', 'spawn centre'),
       ('17,17,7,48562,add,,100,on a monster place', 'spawn centre'),
       ('24,15,7,48562,add,,100,on a house tile', 'a house tile'),
       ('19,15,7,48560,add,,100,reaches over the wall', 'reaches over 18,14,7: a blocking item'),
       ('15,21,7,48563,add,,100,in the one tile way', 'the way past it is cut'),
       ('5,5,7,48562,add,,100,no tile', 'no tile')]


def run(data, mp, rp, **kw):
    log = []
    res = F.run(data, map_path=mp, rows_path=rp, kinds=KINDS, log=log.append, pair_check=False, **kw)
    return res, log


def main():
    root = tempfile.mkdtemp(prefix='decor_flames_map_test_')
    try:
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'world'))
        mp = os.path.join(data, 'world', 'w.otbm')
        make_map(mp)
        spawn_xml(os.path.join(data, 'world', 'w-spawn.xml'))
        check(F.spawn_spots(data, mp) == {(16, 17, 7), (17, 17, 7)}, 'spawn centre and creature place read')
        rp = rows_file(root, 'good.csv', GOOD)
        before = open(mp, 'rb').read()
        run(data, mp, rp, dry=True)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        out = os.path.join(root, 'out.otbm')
        run(data, mp, rp, out=out)
        check(open(mp, 'rb').read() == before and os.path.exists(out), '--out leaves the map alone')
        old = stacks(mp)
        res, log = run(data, mp, rp)
        check(res == dict(done=6, kept=0), 'counts: %s' % res)
        s = stacks(mp)
        check(s[(20, 16, 7)] == [SAND, F.BRAZIER], 'a brazier on open floor: %s' % s[(20, 16, 7)])
        check(s[(12, 12, 7)] == [SAND, F.BRAZIER], 'the basin is the brazier now: %s' % s[(12, 12, 7)])
        check(s[(25, 12, 7)] == [SAND, ALTAR, F.CANDLE], 'a candle on the altar: %s' % s[(25, 12, 7)])
        check(s[(26, 12, 7)] == [SAND, TABLE, F.CANDLE], 'the candelabrum is a candle in its place: %s' % s[(26, 12, 7)])
        check(s[(22, 18, 7)] == [SAND, F.SPIRIT], 'a cold spirit flame: %s' % s[(22, 18, 7)])
        check(s[(27, 17, 7)] == [SAND, F.CAMPFIRE], 'a campfire: %s' % s[(27, 17, 7)])
        moved = {p for p in s if s[p] != old.get(p)}
        check(moved == {(20, 16, 7), (12, 12, 7), (25, 12, 7), (26, 12, 7), (22, 18, 7), (27, 17, 7)},
              'only the listed tiles changed: %s' % sorted(moved))
        check(len(s) == len(old), 'the tile count stays')
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        check(any('map write guard' in l for l in log), 'the write went through the map write guard')
        after = open(mp, 'rb').read()
        res, _log = run(data, mp, rp)
        check(open(mp, 'rb').read() == after and res == dict(done=0, kept=6), 'a second run changes nothing: %s' % res)
        # every refusal: nothing written, the spot named
        for i, (line, why) in enumerate(BAD):
            bp = rows_file(root, 'bad%d.csv' % i, GOOD[:1] + [line])
            fresh = os.path.join(root, 'fresh%d' % i)
            os.makedirs(os.path.join(fresh, 'world'))
            fm = os.path.join(fresh, 'world', 'w.otbm')
            make_map(fm)
            spawn_xml(os.path.join(fresh, 'world', 'w-spawn.xml'))
            fb = open(fm, 'rb').read()
            try:
                run(fresh, fm, bp)
                check(False, 'refused: %s' % line)
            except F.FlameError as e:
                pos = ','.join(line.split(',')[:3])
                check(why in str(e) and pos in str(e), 'refusal names %s and "%s": %s' % (pos, why, e))
            check(open(fm, 'rb').read() == fb and not os.path.exists(fm + '.tmp'), 'refused, the map stays: %s' % line)
        # bad rows of the csv
        for i, line in enumerate(['20,16,7,2057,add,,100,not a flame', '20,16,7,48560,swap,,,swap without old',
                                  '20,16,7,48560,add,1481,,add without on', '20,16,7,48560,add,,100,']):
            try:
                F.read_rows(rows_file(root, 'row%d.csv' % i, [line]))
                check(False, 'bad row refused: %s' % line)
            except F.FlameError:
                pass
        try:
            F.read_rows(rows_file(root, 'twice.csv', GOOD[:1] + GOOD[:1]))
            check(False, 'a tile named twice is refused')
        except F.FlameError:
            pass
        # the client pair guard
        cfg = os.path.join(root, 'config.lua')
        pdata = os.path.join(root, 'pairdata')
        os.makedirs(os.path.join(pdata, 'world'))
        pm = os.path.join(pdata, 'world', 'w.otbm')
        make_map(pm)
        pb = open(pm, 'rb').read()
        for pair, want in ((73, True), (None, True), (74, False)):
            pr = os.path.join(root, 'p%s' % pair)
            os.makedirs(os.path.join(pr, 'data', 'world'))
            shutil.copyfile(pm, os.path.join(pr, 'data', 'world', 'w.otbm'))
            if pair is not None:
                open(os.path.join(pr, 'config.lua'), 'w').write('chaosClientPair = %d\n' % pair)
            log = []
            res = F.run(os.path.join(pr, 'data'), rows_path=rp, kinds=KINDS, log=log.append)
            skipped = bool(res.get('skipped'))
            check(skipped == want and (not want or any(l.startswith('WARNING: decorflamesmap skipped') for l in log)),
                  'pair %s: skipped %s: %s' % (pair, skipped, log[:1]))
            same = open(os.path.join(pr, 'data', 'world', 'w.otbm'), 'rb').read() == pb
            check(same == want, 'pair %s: the map %s' % (pair, 'stays' if want else 'is written'))
        check(not os.path.exists(cfg), 'no stray config')
        K.fault_check(check, IC, make_map,
                      lambda d, p: F.run(d, map_path=p, rows_path=rp, kinds=KINDS, log=lambda s: None, pair_check=False),
                      root, 'decor flames map')
    finally:
        shutil.rmtree(root, ignore_errors=True)
    rows = F.read_rows()
    check(20 <= len(rows) <= 40, 'the real list has 20-40 spots: %d' % len(rows))
    check({r['item'] for r in rows} == set(F.FLAMES), 'every flame is placed somewhere')
    check(all(r['why'] for r in rows), 'every spot says why')
    if failed:
        print('%d failure(s)' % failed)
        return 1
    print('patch_decor_flames_map_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
