#!/usr/bin/env python3
"""Swap the old plain reward chests already placed on an installed map for the reward chest of today.

usage: python3 -I server/tools/patch_reward_chests.py DATA_DIR [--dry-run] [--map FILE] [--out FILE]

DATA_DIR is the server's data folder. The reward chest is read from server/data/scripts/chaos/rift_config.lua
(`chest = {itemId = N, ...}`): the rift's chest, the Descent's and the quest chest of every planned area
(tools/areaplan_build.lua hands it to the area planner). server/README.md "Reward chests".

What changes: on the world map, every item of an OLD id (OLD_IDS, the plain chest 1740) that carries an action id of
the quest chests of the planned areas (area_plan_core.CHEST_ACTION_BLOCK, 47960-47999, and any plan's own
`chest_action`) becomes the new reward chest. Only the item id of those nodes is rewritten; the action id, the tile and
everything else stay. The runtime chests (rift, coffer, Descent) are created by their scripts and need nothing here.

Why a step of its own: install_content_areas.py recognises a placed area only when every tile holds the items of the
plan; once the plan's chest is the new item, a map that still holds the old chest would read as a changed plan. This
step runs right before `contentareas` (install_all.py) and makes the map match again.

Idempotent: a second run finds no old chest and writes nothing. The new id must be in DATA_DIR/items/items.otb, else
nothing is written. The map is written through <map>.otbm.tmp (its chests checked again) and <map>.otbm.bak is
written first when missing. --dry-run lists the chests and writes nothing; --out FILE writes the patched map there
instead (install_all.py --dry-run: its copy has no map). Exit 0 on success, 1 on a refusal.
Python 3 standard library.
"""
import json, os, re, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)  # python -I leaves the script's folder off sys.path

import gen_poi as G  # noqa: E402

OLD_IDS = (1740,)  # the plain chest every reward chest used before (2026-10-20)
RIFT_CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'rift_config.lua')
PLAN_DIRS = [os.path.join(HERE, 'areaplan', d) for d in ('plans', 'chronicle', 'rooms', 'examples')]


class ChestError(Exception):
    pass


def reward_chest_id(path=RIFT_CONFIG):
    m = re.search(r'^\s*chest\s*=\s*\{\s*itemId\s*=\s*(\d+)', open(path, encoding='utf-8').read(), re.M)
    if not m:
        raise ChestError('no `chest = {itemId = N` in %s' % path)
    return int(m.group(1))


def chest_aids(plan_dirs=PLAN_DIRS):
    """the action ids of the planned areas' quest chests: the block, and any plan's own chest_action"""
    import area_plan_core as C
    lo, hi = C.CHEST_ACTION_BLOCK
    aids = set(range(lo, hi + 1))
    for d in plan_dirs:
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name.endswith('.json'):
                try:
                    plan = json.load(open(os.path.join(d, name), encoding='utf-8'))
                except (OSError, ValueError):
                    continue
                if isinstance(plan, dict) and plan.get('chest_action'):
                    aids.add(int(plan['chest_action']))
    return aids


def find_chests(data, old_ids, aids):
    """[(node offset, old id, action id, (x, y, z))] of every item node with an old id and one of these action ids"""
    out = []
    for iid in sorted(old_ids):
        needle = bytes([G.START, G.T_ITEM]) + G.esc(struct.pack('<H', iid))
        i = data.find(needle)
        while i >= 0:
            if G.real(data, i):
                parsed = G.parse_item(G.payload(data, i + 2))
                if parsed and parsed[0] == iid and G.A_ACTION in parsed[1]:
                    aid = struct.unpack('<H', parsed[1][G.A_ACTION])[0]
                    if aid in aids:
                        out.append((i, iid, aid, G.tile_position(data, i)))
            i = data.find(needle, i + 1)
    return out


def patch(data, chests, new_id):
    """the map bytes with the item id of these nodes set to new_id (the id is the node's first two payload bytes)"""
    out, pos = bytearray(), 0
    new = G.esc(struct.pack('<H', new_id))
    for off, iid, _aid, _p in sorted(chests):
        head = off + 2
        old = G.esc(struct.pack('<H', iid))
        if data[head:head + len(old)] != old:
            raise ChestError('internal: no item id at offset %d' % off)
        out += data[pos:head] + new
        pos = head + len(old)
    out += data[pos:]
    return bytes(out)


def otb_has(items_otb, iid):
    import check_monsters
    return iid in check_monsters.otb_ids(items_otb)


def run(data_dir, dry=False, map_path=None, out=None, new_id=None, old_ids=OLD_IDS, aids=None, log=print,
        check_otb=True):
    new_id = new_id or reward_chest_id()
    if new_id in old_ids:
        raise ChestError('the reward chest %d is one of the old ids' % new_id)
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise ChestError('no world map in %s/world' % data_dir)
    if check_otb:
        otb = os.path.join(data_dir, 'items', 'items.otb')
        if not os.path.isfile(otb) or not otb_has(otb, new_id):
            raise ChestError('the reward chest %d is not in %s; nothing changed' % (new_id, otb))
    data = open(map_path, 'rb').read()
    if data[:2] == b'\x1f\x8b':
        raise ChestError('the world map is compressed; unpack it first')
    aids = chest_aids() if aids is None else aids
    chests = find_chests(data, old_ids, aids)
    for _off, iid, aid, p in chests:
        log('chest %d (action id %d) at %d,%d,%d -> %d' % ((iid, aid) + p + (new_id,)))
    if not chests:
        log('reward chests: none of the old ones on the map; nothing to do')
        return dict(changed=0, chests=[])
    new = patch(data, chests, new_id)
    left = find_chests(new, old_ids, aids)
    if left or len(find_chests(new, (new_id,), aids)) < len(chests):
        raise ChestError('internal: the patched map does not hold the new chests; nothing written')
    summary = dict(changed=len(chests), chests=[c[3] for c in chests])
    if dry and not out:
        log('reward chests: would replace %d' % len(chests))
        return summary
    if out:
        open(out, 'wb').write(new)
        log('reward chests: %d replaced in %s' % (len(chests), out))
        return summary
    bak = map_path + '.bak'
    if not os.path.exists(bak):
        shutil.copyfile(map_path, bak)
        log('backup %s' % bak)
    tmp = map_path + '.tmp'
    open(tmp, 'wb').write(new)
    os.replace(tmp, map_path)
    log('reward chests: %d replaced in %s' % (len(chests), map_path))
    return summary


def main(argv):
    args, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            args[a] = True
        elif a in ('--map', '--out'):
            if i + 1 >= len(argv):
                sys.exit('%s needs a value' % a)
            args[a] = argv[i + 1]
            i += 1
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            sys.exit('unknown option %s' % a)
        else:
            pos.append(a)
        i += 1
    if len(pos) != 1:
        print(__doc__)
        return 1
    try:
        run(pos[0], dry=args.get('--dry-run', False), map_path=args.get('--map'), out=args.get('--out'))
    except ChestError as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
