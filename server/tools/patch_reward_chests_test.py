#!/usr/bin/env python3
"""python3 -I server/tools/patch_reward_chests_test.py : patch_reward_chests.py on a synthetic tiny map: the old quest
chests (1740 with an action id of the quest chest block) become the reward chest, a plain 1740 without that action id
and other items stay, a dry run writes nothing, a second run changes nothing, the map otherwise keeps its bytes, an id
whose bytes need escaping works, a missing reward chest in items.otb is refused. Also: the reward chest id of
rift_config.lua is the one the Lua test expects. No base server needed."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_reward_chests as T  # noqa: E402
import install_content_areas as IC  # noqa: E402
import gen_poi as G  # noqa: E402

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


GROUND, OLD, NEW = 100, 1740, 21584
AID = 47960
tiles = {
    (10, 10, 7): dict(ground=GROUND, items=[(OLD, {'aid': AID})], flags=0),           # a quest chest
    (12, 10, 7): dict(ground=GROUND, items=[(OLD, {'aid': 47999})], flags=0),         # another area's
    (14, 10, 7): dict(ground=GROUND, items=[(OLD, {})], flags=0),                     # a plain chest: stays
    (16, 10, 7): dict(ground=GROUND, items=[(OLD, {'aid': 1234})], flags=0),          # a base quest chest: stays
    (18, 10, 7): dict(ground=GROUND, items=[(1387, {'aid': AID})], flags=0),          # not a chest: stays
    (300, 300, 6): dict(ground=GROUND, items=[(OLD, {'aid': AID, 'uid': 9})], flags=1),  # another area node
}
AIDS = set(range(47960, 48000))

tmp = tempfile.mkdtemp(prefix='chaos_chests_')
try:
    data_dir = os.path.join(tmp, 'data')
    os.makedirs(os.path.join(data_dir, 'world'))
    mp = os.path.join(data_dir, 'world', 'map.otbm')
    orig = otbm_file(tiles)
    open(mp, 'wb').write(orig)
    logs = []

    # what is found
    found = T.find_chests(orig, T.OLD_IDS, AIDS)
    check(sorted(c[3] for c in found) == [(10, 10, 7), (12, 10, 7), (300, 300, 6)], 'the three quest chests found: %s'
          % [c[3] for c in found])

    # dry run: nothing written
    s = T.run(data_dir, dry=True, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == 3, 'dry run counts 3')
    check(open(mp, 'rb').read() == orig, 'dry run writes nothing')
    check(not os.path.exists(mp + '.bak'), 'dry run: no backup')

    # --out: the patched copy elsewhere, the map untouched
    out = os.path.join(tmp, 'copy.otbm')
    T.run(data_dir, dry=True, out=out, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(open(mp, 'rb').read() == orig and os.path.isfile(out), '--out writes the copy only')

    # the run
    s = T.run(data_dir, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == 3, 'three replaced')
    new = open(mp, 'rb').read()
    check(open(mp + '.bak', 'rb').read() == orig, 'backup of the old map')
    check(new == open(out, 'rb').read(), 'the same bytes as the --out copy')
    check(len(new) == len(orig), 'same length (an id without escaped bytes)')
    got = {p: i for i, p in G.find_items(new, [OLD, NEW, 1387])}
    check(got.get((10, 10, 7)) == NEW and got.get((12, 10, 7)) == NEW and got.get((300, 300, 6)) == NEW,
          'quest chests are the reward chest now')
    check(got.get((14, 10, 7)) == OLD, 'the plain chest stays')
    check(got.get((16, 10, 7)) == OLD, 'a chest with another action id stays')
    check(got.get((18, 10, 7)) == 1387, 'other items stay')
    check(sorted(G.find_action_items(new, [AID])) == sorted(G.find_action_items(orig, [AID])),
          'the action ids stay on their tiles')
    # the result equals a map built with the new chest
    want = dict(tiles)
    for p in ((10, 10, 7), (12, 10, 7), (300, 300, 6)):
        t = dict(tiles[p])
        t['items'] = [(NEW, a) for _i, a in t['items']]
        want[p] = t
    check(new == otbm_file(want), 'byte for byte the map a plan with the new chest gives')

    # second run: nothing
    s = T.run(data_dir, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == 0 and open(mp, 'rb').read() == new, 'second run changes nothing')

    # an id whose bytes need escaping (0xFE in the low byte)
    open(mp, 'wb').write(orig)
    T.run(data_dir, new_id=0x01FE, aids=AIDS, log=logs.append, check_otb=False)
    got = {p: i for i, p in G.find_items(open(mp, 'rb').read(), [OLD, 0x01FE])}
    check(got.get((10, 10, 7)) == 0x01FE and got.get((14, 10, 7)) == OLD, 'escaped id written and read back')

    # the reward chest must be in items.otb
    open(mp, 'wb').write(orig)
    try:
        T.run(data_dir, new_id=NEW, aids=AIDS, log=logs.append)
        check(False, 'no items.otb: refused')
    except T.ChestError:
        check(open(mp, 'rb').read() == orig, 'refused: nothing written')

    # an old id as the new one: refused
    try:
        T.run(data_dir, new_id=OLD, aids=AIDS, log=logs.append, check_otb=False)
        check(False, 'the old id as the new one: refused')
    except T.ChestError:
        pass
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# the repo's numbers
check(T.reward_chest_id() == 21584, 'rift_config.lua chest: 21584')
aids = T.chest_aids()
check(47960 in aids and 47999 in aids and 47402 not in aids, 'quest chest block, not the rift chest action id')

if failed:
    print('patch_reward_chests_test: %d check(s) failed' % failed)
    sys.exit(1)
print('patch_reward_chests_test: all checks passed')
