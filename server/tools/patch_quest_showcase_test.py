#!/usr/bin/env python3
"""python3 -I server/tools/patch_quest_showcase_test.py : patch_quest_showcase.py on a synthetic map.

Two alcoves (sign behind the teleport on either side): an item on show is swapped in place, an added item goes on the
emptiest cell (middle first), a sign gets its new text and keeps its other attributes, a quest without an alcove is
skipped; a dry run writes nothing, --out leaves the map alone, the real run writes the .bak and keeps the tile count, a
second run changes nothing; an item to replace that is not on show is refused. The real quest_showcase.json names quest
rows of hall_hunts.csv only. No base server needed (numpy for otbm.py)."""
import json, os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_quest_showcase as Q  # noqa: E402
import install_content_areas as IC  # noqa: E402
import hall_order as H  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


FLOOR, COUNTER, PORTAL, SIGN = 100, 1643, 1387, Q.SIGN


def t(ground, *items):
    return dict(flags=0, ground=ground, items=[i if isinstance(i, tuple) else (i, {}) for i in items])


def text_raw(s):
    b = s.encode('latin-1')
    return bytes([6]) + struct.pack('<H', len(b)) + b


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


def parsed(mp, p):
    data = open(mp, 'rb').read()
    s, e = IC.tile_ranges(data, [p])[p]
    return H.parse_tile(data[s:e + 1], p)


CSV = [dict(name='Alpha Quest', kind='quest', dest_x=200, dest_y=200, dest_z=7),
       dict(name='Beta Quest', kind='quest', dest_x=300, dest_y=300, dest_z=8),
       dict(name='Gamma Quest', kind='quest', dest_x=400, dest_y=400, dest_z=9),
       dict(name='Some Hunt', kind='hunt', dest_x=500, dest_y=500, dest_z=7)]


def main():
    root = tempfile.mkdtemp(prefix='quest_showcase_test_')
    try:
        tiles = {(x, y, 7): t(FLOOR) for y in range(10, 22) for x in range(10, 20)}
        # Alpha: teleport at 12,13, sign behind at 12,11, cells row 12 (x 11..13)
        tiles[(12, 13, 7)] = t(FLOOR, (PORTAL, {'tele': (200, 200, 7)}))
        tiles[(12, 11, 7)] = t(FLOOR, COUNTER, (SIGN, {'raw': text_raw('Alpha Quest') + bytes([15, 1])}))
        tiles[(11, 12, 7)] = t(FLOOR, COUNTER, 2000, 2001)
        tiles[(12, 12, 7)] = t(FLOOR, COUNTER, 2002)
        tiles[(13, 12, 7)] = t(FLOOR, COUNTER, 2003)
        # Beta: teleport at 16,18, sign behind at 16,20, cells row 19
        tiles[(16, 18, 7)] = t(FLOOR, (PORTAL, {'tele': (300, 300, 8)}))
        tiles[(16, 20, 7)] = t(FLOOR, COUNTER, (SIGN, {'raw': text_raw('Beta Quest')}))
        tiles[(15, 19, 7)] = t(FLOOR, COUNTER, 3000)
        tiles[(16, 19, 7)] = t(FLOOR, COUNTER, 3001, 3002)
        tiles[(17, 19, 7)] = t(FLOOR, COUNTER, 3003)
        # a teleport to Alpha's quest elsewhere, without a sign: not an alcove
        tiles[(18, 15, 7)] = t(FLOOR, (PORTAL, {'tele': (200, 200, 7)}))
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'world'))
        mp = os.path.join(data, 'world', 'w.otbm')
        open(mp, 'wb').write(otbm_file(tiles))
        rp = os.path.join(root, 'rows.json')
        json.dump({'quests': [
            {'quest': 'Alpha Quest', 'replace': [[2001, 2101]], 'add': [2102], 'sign': 'Alpha Quest\nnew text'},
            {'quest': 'Beta Quest', 'add': [3100]},
            {'quest': 'Gamma Quest', 'add': [4100]}]}, open(rp, 'w'))
        before = open(mp, 'rb').read()
        log = []
        res = Q.run(data, dry=True, map_path=mp, rows_path=rp, csv_rows=CSV, log=log.append)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        check(res == dict(done=4, kept=0, skipped=1), 'dry counts: %s' % res)
        check(any('Gamma Quest: no alcove' in l for l in log), 'a quest without an alcove is skipped and listed')
        out = os.path.join(root, 'out.otbm')
        Q.run(data, map_path=mp, out=out, rows_path=rp, csv_rows=CSV, log=log.append)
        check(open(mp, 'rb').read() == before and os.path.exists(out), '--out leaves the map alone')
        Q.run(data, map_path=mp, rows_path=rp, csv_rows=CSV, log=log.append)
        ids = lambda p: [i for i, _a in parsed(mp, p)['items']]  # noqa: E731
        check(ids((11, 12, 7)) == [COUNTER, 2000, 2101], 'replaced in place: %s' % ids((11, 12, 7)))
        check(ids((12, 12, 7)) == [COUNTER, 2002, 2102], 'added on the emptiest cell, middle first: %s' % ids((12, 12, 7)))
        check(ids((15, 19, 7)) == [COUNTER, 3000, 3100], 'other side: added on the emptiest cell: %s' % ids((15, 19, 7)))
        sign = parsed(mp, (12, 11, 7))['items'][1][1]
        check(Q.sign_text(sign) == 'Alpha Quest\nnew text', 'sign text written: %r' % Q.sign_text(sign))
        check(bytes([15, 1]) in sign['raw'], 'the sign keeps its other attributes')
        check(Q.sign_text(parsed(mp, (16, 20, 7))['items'][1][1]) == 'Beta Quest', 'a sign without a new text is kept')
        check(len(otbm.load_otbm(mp).tiles['x']) == len(tiles), 'the tile count stays')
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        after = open(mp, 'rb').read()
        res = Q.run(data, map_path=mp, rows_path=rp, csv_rows=CSV, log=log.append)
        check(open(mp, 'rb').read() == after and res['done'] == 0 and res['kept'] == 4, 'a second run changes nothing: %s' % res)
        import map_guard_testkit as K
        K.fault_check(check, IC, lambda p: open(p, 'wb').write(otbm_file(tiles)),
                      lambda d, p: Q.run(d, map_path=p, rows_path=rp, csv_rows=CSV, log=lambda s: None), root, 'quest showcase')
        json.dump({'quests': [{'quest': 'Beta Quest', 'replace': [[9999, 9998]]}]}, open(rp, 'w'))
        try:
            Q.run(data, map_path=mp, rows_path=rp, csv_rows=CSV, log=log.append)
            check(False, 'an item to replace that is not on show is refused')
        except Q.ShowcaseError:
            pass
        json.dump({'quests': [{'quest': 'Some Hunt', 'add': [1]}]}, open(rp, 'w'))
        try:
            Q.read_rows(rp, CSV)
            check(False, 'a hunt row is refused')
        except Q.ShowcaseError:
            pass
    finally:
        shutil.rmtree(root, ignore_errors=True)
    rows = Q.read_rows()
    check(len(rows) >= 9 and all(r['replace'] or r['add'] or r['sign'] for r in rows), 'the real file: every quest changes something')
    check(all(i >= 100 for r in rows for i in r['add'] + [v for p in r['replace'] for v in p]), 'real item ids')
    if failed:
        print('%d failure(s)' % failed)
        return 1
    print('patch_quest_showcase_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
