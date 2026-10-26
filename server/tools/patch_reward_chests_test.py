#!/usr/bin/env python3
"""python3 -I server/tools/patch_reward_chests_test.py : patch_reward_chests.py on a synthetic tiny map: the old quest
chests of the planned areas (1740 or the stock 21584 with an action id of the quest chest block) and the base server's
quest chests (by the rules of the module docstring: system.lua action ids with contents, system2.lua unique ids, quest
script unique ids, the stock reward chest with an action id) become the reward chest; a plain 1740, empty system.lua
chests, boxes, coffins, chests with an unowned unique id and other items stay; uid / aid / contents stay; a dry run
writes nothing, a second run changes nothing, the map otherwise keeps its bytes, an id whose bytes need escaping works,
a missing reward chest in items.otb is refused. Also: the reward chest id of rift_config.lua is the one the Lua test
expects. No base server needed."""
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


GROUND, OLD, NEW = 100, 1740, 32310
STOCK = 21584
AID = 47960
tiles = {
    (10, 10, 7): dict(ground=GROUND, items=[(OLD, {'aid': AID})], flags=0),           # a quest chest
    (12, 10, 7): dict(ground=GROUND, items=[(OLD, {'aid': 47999})], flags=0),         # another area's
    (14, 10, 7): dict(ground=GROUND, items=[(OLD, {})], flags=0),                     # a plain chest: stays
    (16, 10, 7): dict(ground=GROUND, items=[(OLD, {'aid': 1234})], flags=0),          # a chest with an unknown action id: stays
    (18, 10, 7): dict(ground=GROUND, items=[(1387, {'aid': AID})], flags=0),          # not a chest: stays
    (300, 300, 6): dict(ground=GROUND, items=[(OLD, {'aid': AID, 'uid': 9})], flags=1),  # another area node
    (20, 10, 7): dict(ground=GROUND, items=[(STOCK, {'aid': 47961})], flags=0),       # a planned area's chest of the stock look
}
# the base server's quest chests (kids = the contents) and what must stay
BASE = {
    (30, 10, 7): dict(ground=GROUND, items=[(1740, {'aid': 2000, 'uid': 3058, 'kids': [2160, 2400]})], flags=0),   # system.lua
    (32, 10, 7): dict(ground=GROUND, items=[(12664, {'aid': 2215, 'uid': 4015, 'kids': [2400]})], flags=0),        # annihilator
    (34, 10, 7): dict(ground=GROUND, items=[(1749, {'aid': 28300, 'uid': 4042, 'kids': [2400]})], flags=0),        # arena reward
    (36, 10, 7): dict(ground=GROUND, items=[(1740, {'aid': 2001, 'uid': 3009})], flags=0),                          # system2.lua
    (38, 10, 7): dict(ground=GROUND, items=[(1740, {'uid': 1304})], flags=0),                                       # inquisition
    (40, 10, 7): dict(ground=GROUND, items=[(1748, {'uid': 3089})], flags=0),                                       # yalahar
    (42, 10, 7): dict(ground=GROUND, items=[(18473, {'uid': 3149})], flags=0),                                      # bigfoot
    (44, 10, 7): dict(ground=GROUND, items=[(STOCK, {'aid': 33735})], flags=0),                                     # starter chest
}
KEEP = {
    (50, 10, 7): dict(ground=GROUND, items=[(1740, {'aid': 2000, 'uid': 3058})], flags=0),                # system.lua, empty: stays
    (52, 10, 7): dict(ground=GROUND, items=[(1738, {'aid': 2000, 'uid': 3058, 'kids': [2160]})], flags=0),  # a box: stays
    (54, 10, 7): dict(ground=GROUND, items=[(1410, {'aid': 2000, 'uid': 3059, 'kids': [2160]})], flags=0),  # a coffin: stays
    (56, 10, 7): dict(ground=GROUND, items=[(1740, {'uid': 61907})], flags=0),                            # a unique id nothing owns
    (58, 10, 7): dict(ground=GROUND, items=[(1740, {'aid': 2001, 'uid': 65207})], flags=0),               # system2.lua, not its table
    (60, 10, 7): dict(ground=GROUND, items=[(1740, {'uid': 3164 + 1})], flags=0),                         # just past a script's unique id
    (62, 10, 7): dict(ground=GROUND, items=[(STOCK, {})], flags=0),                                        # a bare stock chest
    (64, 10, 7): dict(ground=GROUND, items=[(29327, {'uid': 34801})], flags=0),                           # the plaza's royal chest
    (66, 10, 7): dict(ground=GROUND, items=[(1740, {'aid': 55555, 'uid': 4, 'kids': [2160]})], flags=0),  # an unknown action id
}
tiles.update(BASE)
tiles.update(KEEP)
AIDS = set(range(47960, 48000))
PLANNED = [(10, 10, 7), (12, 10, 7), (300, 300, 6), (20, 10, 7)]
SWAP = sorted(PLANNED + list(BASE))

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
    check(sorted(c[3] for c in found) == sorted(PLANNED), 'the four planned quest chests found: %s' % [c[3] for c in found])
    base = T.find_base_quest_chests(orig, AIDS)
    check(sorted(c[3] for c in base) == sorted(BASE), 'the eight base quest chests found: %s' % sorted(c[3] for c in base))
    check({c[3]: c[4] for c in base} == {(30, 10, 7): 'system', (32, 10, 7): 'system', (34, 10, 7): 'system',
                                         (36, 10, 7): 'system2', (38, 10, 7): 'script', (40, 10, 7): 'script',
                                         (42, 10, 7): 'script', (44, 10, 7): 'stock'}, 'the rule of each base chest')
    off = {c[3]: c[0] for c in base}
    check(T.has_contents(orig, off[(30, 10, 7)]) and not T.has_contents(orig, off[(36, 10, 7)]), 'has_contents: kids or none')

    # dry run: nothing written
    s = T.run(data_dir, dry=True, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == len(SWAP) and s['base'] == len(BASE), 'dry run counts %d (%s)' % (len(SWAP), s))
    check(open(mp, 'rb').read() == orig, 'dry run writes nothing')
    check(not os.path.exists(mp + '.bak'), 'dry run: no backup')
    check(any(l.startswith('base quest system (system.lua, chest with contents): 3 (1 x 1740, 1 x 1749, 1 x 12664)') for l in logs),
          'the log names the rule and the ids: %s' % [l for l in logs if l.startswith('base')])

    # --out: the patched copy elsewhere, the map untouched
    out = os.path.join(tmp, 'copy.otbm')
    T.run(data_dir, dry=True, out=out, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(open(mp, 'rb').read() == orig and os.path.isfile(out), '--out writes the copy only')

    # the run
    s = T.run(data_dir, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == len(SWAP), 'all of them replaced')
    new = open(mp, 'rb').read()
    check(open(mp + '.bak', 'rb').read() == orig, 'backup of the old map')
    check(new == open(out, 'rb').read(), 'the same bytes as the --out copy')
    check(len(new) == len(orig), 'same length (an id without escaped bytes)')
    got = {p: i for i, p in G.find_items(new, [OLD, NEW, 1387, STOCK, 1738, 1410, 12664, 1748, 1749, 18473, 29327])}
    check(all(got.get(p) == NEW for p in SWAP), 'quest chests are the reward chest now')
    check(got.get((14, 10, 7)) == OLD, 'the plain chest stays')
    check(got.get((16, 10, 7)) == OLD, 'a chest with another action id stays')
    check(got.get((18, 10, 7)) == 1387, 'other items stay')
    stays = {(50, 10, 7): OLD, (52, 10, 7): 1738, (54, 10, 7): 1410, (56, 10, 7): OLD, (58, 10, 7): OLD, (60, 10, 7): OLD,
             (62, 10, 7): STOCK, (64, 10, 7): 29327, (66, 10, 7): OLD}
    for p, want in stays.items():
        check(got.get(p) == want, 'not a quest chest, stays: %s (%s)' % (p, got.get(p)))
    check(sorted(G.find_action_items(new, [AID, 2000, 2215, 33735])) == sorted(G.find_action_items(orig, [AID, 2000, 2215, 33735])),
          'the action ids stay on their tiles')
    # the result equals a map built with the new chest (uid, aid and contents kept)
    want = dict(tiles)
    for p in SWAP:
        t = dict(tiles[p])
        t['items'] = [(NEW, a) for _i, a in t['items']]
        want[p] = t
    check(new == otbm_file(want), 'byte for byte the map a plan with the new chest gives (contents, uid, aid kept)')

    # second run: nothing
    s = T.run(data_dir, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == 0 and open(mp, 'rb').read() == new, 'second run changes nothing')

    # the planned areas alone (base=False)
    open(mp, 'wb').write(orig)
    s = T.run(data_dir, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False, base=False)
    check(s['changed'] == len(PLANNED) and s['base'] == 0, 'base=False: only the planned areas')
    # then the full run finishes the base ones, and the planned ones are not touched twice
    s = T.run(data_dir, new_id=NEW, aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == len(BASE), 'the base chests follow: %s' % s)

    # an id whose bytes need escaping (0xFE in the low byte)
    open(mp, 'wb').write(orig)
    T.run(data_dir, new_id=0x01FE, aids=AIDS, log=logs.append, check_otb=False)
    got = {p: i for i, p in G.find_items(open(mp, 'rb').read(), [OLD, 0x01FE])}
    check(got.get((10, 10, 7)) == 0x01FE and got.get((14, 10, 7)) == OLD and got.get((30, 10, 7)) == 0x01FE,
          'escaped id written and read back')

    # the reward chest must be in items.otb
    open(mp, 'wb').write(orig)
    try:
        T.run(data_dir, new_id=NEW, aids=AIDS, log=logs.append)
        check(False, 'no items.otb: refused')
    except T.ChestError:
        check(open(mp, 'rb').read() == orig, 'refused: nothing written')

    # an old id as the new one: refused
    for bad in (OLD, STOCK, 1746):
        try:
            T.run(data_dir, new_id=bad, aids=AIDS, log=logs.append, check_otb=False)
            check(False, 'the old id %d as the new one: refused' % bad)
        except T.ChestError:
            pass
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# the rules' tables
check(T.base_rule(1740, 2000, 5, True) == 'system' and T.base_rule(1740, 2000, 5, False) is None, 'system.lua needs contents')
check(T.base_rule(1740, 2000, 0, True) is None, 'system.lua needs a unique id')
check(T.base_rule(1738, 2000, 5, True) is None, 'a box is no chest')
check(T.base_rule(STOCK, 47961, 0, False, AIDS) is None, 'a planned area chest is not the base rule')
check(all(a in (2000, 2016, 2215, 10544, 12374, 12513, 26300, 27300, 28300) for a in T.SYSTEM_AIDS) and len(T.SYSTEM_AIDS) == 9,
      'nine system.lua action ids')
check(1300 in range(T.SCRIPT_UIDS[0][0], T.SCRIPT_UIDS[0][1] + 1), 'inquisition unique ids')

# the repo's numbers
check(T.reward_chest_id() == 32310, 'rift_config.lua chest: 32310')
aids = T.chest_aids()
check(47960 in aids and 47999 in aids and 47402 not in aids, 'quest chest block, not the rift chest action id')

if failed:
    print('patch_reward_chests_test: %d check(s) failed' % failed)
    sys.exit(1)
print('patch_reward_chests_test: all checks passed')
