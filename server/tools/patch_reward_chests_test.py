#!/usr/bin/env python3
"""python3 -I server/tools/patch_reward_chests_test.py : patch_reward_chests.py on a synthetic tiny map: the old quest
chests of the planned areas (1740 or the stock 21584 with an action id of the quest chest block) become the reward chest
(one tile, 32311); the base server's quest chests (by the rules of the module docstring: system.lua action ids with
contents, system2.lua unique ids, quest script unique ids), the boxes 1738 / 1741 under the system / system2 rules and the
stock reward chest with an action id become the same one; chests of the legacy 2 x 2 look (32310, an earlier run's) move to it
on the next run, whatever their action id; a plain 1740, empty system.lua chests and boxes, coffins, chests with an
unowned unique id and other items stay; uid / aid / contents stay; a dry run writes nothing, a second run changes
nothing, the map otherwise keeps its bytes, an id whose bytes need escaping works, a missing reward chest in items.otb is
refused. Also: the reward chest id of rift_config.lua is the one the Lua test expects. No base server needed."""
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


GROUND, OLD, NEW, LEGACY = 100, 1740, 32311, 32310
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
    (46, 10, 7): dict(ground=GROUND, items=[(1738, {'aid': 2000, 'uid': 3058, 'kids': [2160]})], flags=0),          # a box, system.lua
    (48, 10, 7): dict(ground=GROUND, items=[(1741, {'aid': 2001, 'uid': 3009})], flags=0),                          # a box, system2.lua
}
KEEP = {
    (50, 10, 7): dict(ground=GROUND, items=[(1740, {'aid': 2000, 'uid': 3058})], flags=0),                # system.lua, empty: stays
    (52, 10, 7): dict(ground=GROUND, items=[(1738, {'aid': 2000, 'uid': 3058})], flags=0),                 # an empty box: stays
    (68, 10, 7): dict(ground=GROUND, items=[(1738, {'aid': 2000, 'kids': [2160]})], flags=0),             # a box without a unique id: stays
    (70, 10, 7): dict(ground=GROUND, items=[(1741, {'uid': 1304})], flags=0),                             # a box with a script uid: stays
    (72, 10, 7): dict(ground=GROUND, items=[(1738, {'aid': 2001, 'uid': 65207})], flags=0),               # a box, not system2's table
    (74, 10, 7): dict(ground=GROUND, items=[(1738, {})], flags=0),                                        # a plain box
    (54, 10, 7): dict(ground=GROUND, items=[(1410, {'aid': 2000, 'uid': 3059, 'kids': [2160]})], flags=0),  # a coffin: stays
    (56, 10, 7): dict(ground=GROUND, items=[(1740, {'uid': 61907})], flags=0),                            # a unique id nothing owns
    (58, 10, 7): dict(ground=GROUND, items=[(1740, {'aid': 2001, 'uid': 65207})], flags=0),               # system2.lua, not its table
    (60, 10, 7): dict(ground=GROUND, items=[(1740, {'uid': 3164 + 1})], flags=0),                         # just past a script's unique id
    (62, 10, 7): dict(ground=GROUND, items=[(STOCK, {})], flags=0),                                        # a bare stock chest
    (64, 10, 7): dict(ground=GROUND, items=[(29327, {'uid': 34801})], flags=0),                           # the plaza's royal chest
    (78, 10, 7): dict(ground=GROUND, items=[(32312, {'aid': 47403})], flags=0),                           # a Sealed Coffer (O315): not a reward chest, never moved
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
    check(sorted(c[3] for c in base) == sorted(BASE), 'the ten base quest chests and boxes found: %s' % sorted(c[3] for c in base))
    check({c[3]: c[4] for c in base} == {(30, 10, 7): 'system', (32, 10, 7): 'system', (34, 10, 7): 'system',
                                         (36, 10, 7): 'system2', (38, 10, 7): 'script', (40, 10, 7): 'script',
                                         (42, 10, 7): 'script', (44, 10, 7): 'stock', (46, 10, 7): 'system',
                                         (48, 10, 7): 'system2'}, 'the rule of each base chest')
    off = {c[3]: c[0] for c in base}
    check(T.has_contents(orig, off[(30, 10, 7)]) and not T.has_contents(orig, off[(36, 10, 7)]), 'has_contents: kids or none')

    # dry run: nothing written
    s = T.run(data_dir, dry=True, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == len(SWAP) and s['base'] == len(BASE) and s['migrated'] == 0, 'dry run counts %d (%s)' % (len(SWAP), s))
    check(s['rules'] == {'system': 4, 'system2': 2, 'script': 3, 'stock': 1}, 'dry run: chests per rule: %s' % s['rules'])
    check(open(mp, 'rb').read() == orig, 'dry run writes nothing')
    check(not os.path.exists(mp + '.bak'), 'dry run: no backup')
    check(any(l.startswith('base quest system (system.lua, chest or box with contents): 4 (1 x 1738, 1 x 1740, 1 x 1749, 1 x 12664) -> 32311') for l in logs),
          'the log names the rule and the ids: %s' % [l for l in logs if l.startswith('base')])

    # --out: the patched copy elsewhere, the map untouched
    out = os.path.join(tmp, 'copy.otbm')
    T.run(data_dir, dry=True, out=out, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False)
    check(open(mp, 'rb').read() == orig and os.path.isfile(out), '--out writes the copy only')

    # the run
    s = T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == len(SWAP), 'all of them replaced')
    new = open(mp, 'rb').read()
    check(open(mp + '.bak', 'rb').read() == orig, 'backup of the old map')
    check(new == open(out, 'rb').read(), 'the same bytes as the --out copy')
    check(len(new) == len(orig), 'same length (an id without escaped bytes)')
    got = {p: i for i, p in G.find_items(new, [OLD, NEW, LEGACY, 1387, STOCK, 1738, 1741, 1410, 12664, 1748, 1749, 18473, 29327, 32312])}
    check(all(got.get(p) == NEW for p in SWAP), 'planned area chests, the stock chest, base quest chests and boxes are the reward chest now: %s' % [(p, got.get(p)) for p in SWAP])
    check(got[(46, 10, 7)] == NEW and got[(48, 10, 7)] == NEW, 'a system.lua box and a system2.lua box are swapped')
    check(not any(i == LEGACY for _p, i in G.find_items(new, [LEGACY])), 'no 2 x 2 look is left')
    check(got.get((14, 10, 7)) == OLD, 'the plain chest stays')
    check(got.get((16, 10, 7)) == OLD, 'a chest with another action id stays')
    check(got.get((18, 10, 7)) == 1387, 'other items stay')
    stays = {(50, 10, 7): OLD, (52, 10, 7): 1738, (54, 10, 7): 1410, (56, 10, 7): OLD, (58, 10, 7): OLD, (60, 10, 7): OLD,
             (62, 10, 7): STOCK, (64, 10, 7): 29327, (66, 10, 7): OLD, (68, 10, 7): 1738, (70, 10, 7): 1741, (72, 10, 7): 1738,
             (74, 10, 7): 1738, (78, 10, 7): 32312}
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
    check(new == otbm_file(want), 'byte for byte the map a plan with the new chests gives (contents, uid, aid kept)')

    # second run: nothing
    s = T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == 0 and open(mp, 'rb').read() == new, 'second run changes nothing')

    # migration: a server whose earlier run put the 2 x 2 look on every swap: planned, stock and base chests are 32310; the boxes
    # were never swapped by that run, they are still boxes. Build that map.
    BOXES = [(46, 10, 7), (48, 10, 7)]
    first = {}
    for p, t in tiles.items():
        t = dict(t)
        if p in SWAP and p not in BOXES:
            t['items'] = [(LEGACY, a) for _i, a in t['items']]
        first[p] = t
    # a 32310 that carries a planned area's action id and a script unique id, and one with no action id at all: both move
    first[(300, 300, 6)] = dict(ground=GROUND, items=[(LEGACY, {'aid': AID, 'uid': 1304})], flags=1)
    first[(76, 10, 7)] = dict(ground=GROUND, items=[(LEGACY, {})], flags=0)
    open(mp, 'wb').write(otbm_file(first))
    s = T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False)
    moved = len([p for p in first if first[p]['items'] and first[p]['items'][0][0] == LEGACY])
    check(s['changed'] == len(SWAP) + 1 and s['migrated'] == moved, 'migration: every 2 x 2 chest moves, the boxes are swapped: %s' % s)
    mig = open(mp, 'rb').read()
    got = {p: i for i, p in G.find_items(mig, [NEW, LEGACY, 1738, 1741])}
    check(all(got.get(p) == NEW for p in SWAP) and got.get((76, 10, 7)) == NEW, 'migration: everything ends up the one-tile look: %s' % [(p, got.get(p)) for p in SWAP])
    check(LEGACY not in got.values(), 'migration: no 2 x 2 look left')
    s = T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == 0 and open(mp, 'rb').read() == mig, 'migration: a second run changes nothing')
    check(open(mp + '.bak', 'rb').read() == orig, 'the backup is still the first map')
    open(mp, 'wb').write(orig)

    # the planned areas alone (base=False)
    open(mp, 'wb').write(orig)
    s = T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False, base=False)
    check(s['changed'] == len(PLANNED) and s['base'] == 0, 'base=False: only the planned areas')
    # then the full run finishes the base ones, and the planned ones are not touched twice
    s = T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False)
    check(s['changed'] == len(BASE), 'the base chests follow: %s' % s)

    # an id whose bytes need escaping (0xFE in the low byte)
    open(mp, 'wb').write(orig)
    T.run(data_dir, new_id=0x01FE, legacy_ids=(0x02FE,), aids=AIDS, log=logs.append, check_otb=False)
    got = {p: i for i, p in G.find_items(open(mp, 'rb').read(), [OLD, 0x01FE, 0x02FE])}
    check(got.get((10, 10, 7)) == 0x01FE and got.get((14, 10, 7)) == OLD and got.get((30, 10, 7)) == 0x01FE and got.get((44, 10, 7)) == 0x01FE,
          'escaped id written and read back')

    # the reward chest must be in items.otb
    open(mp, 'wb').write(orig)
    try:
        T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append)
        check(False, 'no items.otb: refused')
    except T.ChestError:
        check(open(mp, 'rb').read() == orig, 'refused: nothing written')
    import struct as _st
    os.makedirs(os.path.join(data_dir, 'items'))
    def otb_with(*sids):
        root = b'\xFE\x00' + b'\x00' * 4
        nodes = b''
        for sid in sids:
            body = _st.pack('<I', 0) + bytes([0x10, 2, 0]) + _st.pack('<H', sid) + bytes([0x11, 2, 0]) + _st.pack('<H', sid)
            nodes += b'\xFE\x00' + body + b'\xFF'
        return b'\x00\x00\x00\x00' + root + nodes + b'\xFF'
    open(os.path.join(data_dir, 'items', 'items.otb'), 'wb').write(otb_with(LEGACY))
    try:
        T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append)
        check(False, 'the reward chest missing in items.otb (only the legacy look there): refused')
    except T.ChestError as e:
        check(str(NEW) in str(e) and open(mp, 'rb').read() == orig, 'the reward chest missing in items.otb: refused, nothing written: %s' % e)
    open(os.path.join(data_dir, 'items', 'items.otb'), 'wb').write(otb_with(NEW))
    s = T.run(data_dir, new_id=NEW, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append)
    check(s['changed'] == len(SWAP), 'the reward chest in items.otb: the run goes through (the legacy id need not be there)')
    open(mp, 'wb').write(orig)

    # an old id as the new one: refused
    for bad in (OLD, STOCK, 1746, 1738, 1741):
        try:
            T.run(data_dir, new_id=bad, legacy_ids=(LEGACY,), aids=AIDS, log=logs.append, check_otb=False)
            check(False, 'the old id %d as the new one: refused' % bad)
        except T.ChestError:
            pass
    try:
        T.run(data_dir, new_id=NEW, legacy_ids=(NEW,), aids=AIDS, log=logs.append, check_otb=False)
        check(False, 'the same id as the reward chest and as a legacy look: refused')
    except T.ChestError:
        pass
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# the rules' tables
check(T.base_rule(1740, 2000, 5, True) == 'system' and T.base_rule(1740, 2000, 5, False) is None, 'system.lua needs contents')
check(T.base_rule(1740, 2000, 0, True) is None, 'system.lua needs a unique id')
check(T.base_rule(STOCK, 47961, 0, False, AIDS) is None, 'a planned area chest is not the base rule')
check(T.base_rule(1738, 2000, 5, True) == 'system' and T.base_rule(1741, 2001, 3009, False) == 'system2', 'boxes: system / system2 rules')
check(T.base_rule(1738, 2000, 5, False) is None and T.base_rule(1738, 0, 5, True) is None, 'boxes: empty or without an action id stay')
check(T.base_rule(1741, 0, 1304, True) is None, 'boxes: no script rule')
check(T.base_rule(32310, 2000, 5, True, AIDS) is None and T.base_rule(32311, 2000, 5, True, AIDS) is None,
      'the reward chest ids are not base chests (the legacy look is moved by id, find_legacy)')
check(all(a in (2000, 2016, 2215, 10544, 12374, 12513, 26300, 27300, 28300) for a in T.SYSTEM_AIDS) and len(T.SYSTEM_AIDS) == 9,
      'nine system.lua action ids')
check(1300 in range(T.SCRIPT_UIDS[0][0], T.SCRIPT_UIDS[0][1] + 1), 'inquisition unique ids')

# the repo's numbers
check(T.reward_chest_id() == 32311 and T.reward_chest_legacy_ids() == (32310,), 'rift_config.lua chest: 32311 (one tile), legacy 32310 (2 x 2)')
aids = T.chest_aids()
check(47960 in aids and 47999 in aids and 47402 not in aids, 'quest chest block, not the rift chest action id')

if failed:
    print('patch_reward_chests_test: %d check(s) failed' % failed)
    sys.exit(1)
print('patch_reward_chests_test: all checks passed')
