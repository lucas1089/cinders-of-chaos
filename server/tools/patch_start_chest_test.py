#!/usr/bin/env python3
"""python3 -I server/tools/patch_start_chest_test.py : patch_start_chest.py on a synthetic tiny map: the chest with action id
33735 goes (as the stock chest 21584, as the reward chest look, with contents inside), every other item and tile stays,
a dry run writes nothing, --out writes a copy, a second run changes nothing, a backup is made, the use script is renamed
(not removed), other files with the text are only listed, a compressed map is refused. No base server needed."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_start_chest as T  # noqa: E402
import install_content_areas as IC  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


G, AID = 100, 33735
tiles = {
    (10, 10, 7): dict(ground=G, items=[(21584, {'aid': AID})], flags=0),                      # the stock chest
    (12, 10, 7): dict(ground=G, items=[(32310, {'aid': AID}), (1387, {})], flags=0),          # the reward look, a brazier next to it
    (14, 10, 7): dict(ground=G, items=[(21584, {'aid': AID, 'kids': [2160, 2400]})], flags=0),  # with contents
    (16, 10, 7): dict(ground=G, items=[(21584, {'aid': 33733})], flags=0),                    # the Soul War chest: stays
    (18, 10, 7): dict(ground=G, items=[(21584, {})], flags=0),                                # a bare chest: stays
    (20, 10, 7): dict(ground=G, items=[(1740, {'aid': 2000, 'uid': 3058, 'kids': [2160]})], flags=0),  # a quest chest: stays
    (22, 10, 7): dict(ground=G, items=[(1387, {'aid': 1234})], flags=0),                      # another action id: stays
    (300, 300, 6): dict(ground=G, items=[(21584, {'aid': AID})], flags=1),                    # another area node
}
GONE = [(10, 10, 7), (12, 10, 7), (14, 10, 7), (300, 300, 6)]

tmp = tempfile.mkdtemp(prefix='chaos_startchest_')
try:
    data_dir = os.path.join(tmp, 'data')
    os.makedirs(os.path.join(data_dir, 'world'))
    os.makedirs(os.path.join(data_dir, 'scripts', 'customs', 'actions'))
    os.makedirs(os.path.join(data_dir, 'scripts', 'customs', 'other'))
    mp = os.path.join(data_dir, 'world', 'map.otbm')
    orig = otbm_file(tiles)
    open(mp, 'wb').write(orig)
    script = os.path.join(data_dir, T.SCRIPT)
    open(script, 'w').write('local a = Action()\n-- Collect First Items!\n')
    other = os.path.join(data_dir, 'scripts', 'customs', 'other', 'text.lua')
    open(other, 'w').write('x = "collect first items"\n')
    logs = []

    found = T.find_chests(orig)
    check(sorted(c[2] for c in found) == sorted(GONE), 'found: %s' % [c[2] for c in found])

    # dry run: nothing written
    s = T.run(data_dir, dry=True, map_path=mp, log=logs.append)
    check(open(mp, 'rb').read() == orig and os.path.isfile(script), 'dry run writes nothing')
    check(sorted(s['chests']) == sorted(GONE) and s['script'], 'dry run counts %s' % s)

    # --out: a copy, the map stays
    out = os.path.join(tmp, 'copy.otbm')
    T.run(data_dir, dry=True, map_path=mp, out=out, log=logs.append)
    check(os.path.isfile(out) and open(mp, 'rb').read() == orig, '--out writes the copy only')
    check(not T.find_chests(open(out, 'rb').read()), '--out copy has no chest')

    # real run
    s = T.run(data_dir, log=logs.append)
    new = open(mp, 'rb').read()
    check(not T.find_chests(new), 'no starter chest left')
    check(os.path.isfile(mp + '.bak') and open(mp + '.bak', 'rb').read() == orig, 'backup written')
    expect = dict(tiles)
    for p in GONE:
        t = dict(tiles[p])
        t['items'] = [it for it in t['items'] if it[1].get('aid') != AID]
        expect[p] = t
    check(new == otbm_file(expect), 'only the chests are gone, every other byte stays')
    check(not os.path.exists(script) and os.path.isfile(script + T.OFF), 'use script renamed, not deleted')
    check(s['text_files'] == ['scripts/customs/other/text.lua'], 'other file with the text listed: %s' % s['text_files'])
    check(os.path.isfile(other), 'other file untouched')

    # second run: nothing changes
    before = open(mp, 'rb').read()
    s = T.run(data_dir, log=logs.append)
    check(open(mp, 'rb').read() == before and not s['chests'] and not s['script'], 'second run changes nothing')

    # compressed map refused
    open(mp, 'wb').write(b'\x1f\x8b' + b'0' * 10)
    try:
        T.run(data_dir, log=logs.append)
        check(False, 'compressed map refused')
    except T.ChestError:
        pass
finally:
    shutil.rmtree(tmp, ignore_errors=True)

if failed:
    print('patch_start_chest_test: %d check(s) failed' % failed)
    sys.exit(1)
print('patch_start_chest_test: all checks passed')
