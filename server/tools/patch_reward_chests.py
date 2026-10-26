#!/usr/bin/env python3
"""Swap the quest chests already placed on an installed map for the reward chest of today.

usage: python3 -I server/tools/patch_reward_chests.py DATA_DIR [--dry-run] [--map FILE] [--out FILE] [--items-otb FILE]

DATA_DIR is the server's data folder. The reward chest is read from server/data/scripts/chaos/rift_config.lua
(`chest = {itemId = N, ...}`, today the own look 32310 of tools/install_reward_chest.py): the rift's chest, the Descent's
and the quest chest of every planned area (tools/areaplan_build.lua hands it to the area planner). Owner request
2026-10-26: every quest chest wears it. server/README.md "Reward chests".

What changes (only the item id of the node; the action id, unique id, the contents, the tile and everything else stay):
1. Planned areas: every item of an OLD id (OLD_IDS: the plain chest 1740 and the stock reward chest 21584) that carries an
   action id of the quest chests of the planned areas (area_plan_core.CHEST_ACTION_BLOCK, 47960-47999, and any plan's
   own `chest_action`).
2. The base server's own quest chests (BASE_CHEST_IDS: the chest looks 1740 / 1746-1749 / 8587 / 12664 / 18472-18474),
   when the base quest system opens them (data/actions/actions.xml, scripts/quests):
   - an action id of system.lua (SYSTEM_AIDS: 2000, 2016, 2215, 10544, 12374, 12513, 26300, 27300, 28300; the unique id is
     the storage key) AND items inside: system.lua gives the contents, and a chest with nothing inside gives a copy of
     itself, so an empty one is no quest chest;
   - action id 2001 and a unique id of system2.lua's table (SYSTEM2_UIDS: it gives a fixed reward);
   - a unique id a quest script owns (SCRIPT_UIDS: the Inquisition 1300-1308, In Service of Yalahar 3088-3090, Bigfoot's
     Burden 3147-3150, Children of the Revolution 3164, Wrath of the Emperor 3200, Demon Oak 9008-9011, the warzone
     9172-9174).
   - the base's own reward chest 21584 with any other action id (the starter chest 33735, the Soul War chest 33733).
   Not touched: boxes, coffins, drawers, bookcases, barrels and the other things that carry the quest action id but are
   no chest (1738, 1741, 1716-1721, 1410, 1419 ...), chests without a script (a unique id nothing owns, no action id:
   decoration or loot containers), the plaza's royal chests, the runtime chests (rift, coffer, Descent, cursed chest),
   and containers players keep things in (houses, depots: no quest action id).
The runtime chests (rift, coffer, Descent) are created by their scripts and need nothing here.

Why a step of its own: install_content_areas.py recognises a placed area only when every tile holds the items of the
plan; once the plan's chest is the new item, a map that still holds the old chest would read as a changed plan. This
step runs right before `contentareas` (install_all.py) and makes the map match again.

Idempotent: a second run finds no old chest and writes nothing. The new id must be in DATA_DIR/items/items.otb (or
--items-otb FILE: install_all.py --dry-run reads its copy's), else nothing is written. The map is written through
<map>.otbm.tmp (its chests checked again) and <map>.otbm.bak is written first when missing. --dry-run lists the chests
and writes nothing; --out FILE writes the patched map there instead (install_all.py --dry-run: its copy has no map).
Exit 0 on success, 1 on a refusal. Python 3 standard library.
"""
import json, os, re, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)  # python -I leaves the script's folder off sys.path

import gen_poi as G  # noqa: E402

OLD_IDS = (1740, 21584)  # the looks a planned area's quest chest had: the plain chest (until 2026-10-20), the stock reward chest
STOCK_REWARD = 21584     # the base server's own reward chest item
# the base server's quest chests (rule 2 of the docstring); the ids come from a scan of the base map and its actions.xml
BASE_CHEST_IDS = (1740, 1746, 1747, 1748, 1749, 8587, 12664, 18472, 18473, 18474)
SYSTEM_AIDS = (2000, 2016, 2215, 10544, 12374, 12513, 26300, 27300, 28300)   # scripts/quests/system.lua (items inside)
SYSTEM2_AID = 2001                                                           # scripts/quests/system2.lua (fixed rewards)
SYSTEM2_UIDS = frozenset((2285, 2286, 3002, 3003, 3004, 3005, 3007, 3009, 3010, 3012, 3014, 3018, 3020, 3024, 3027, 3062,
                          3064, 3084, 3085, 3112, 3114, 3116, 3120, 3162, 3311, 3312, 3313, 4010, 5556, 9055, 9136, 9185,
                          9196, 9226, 12125, 12126, 12331, 12507, 12578, 50032, 50112, 50125))
SCRIPT_UIDS = ((1300, 1308), (3088, 3090), (3147, 3150), (3164, 3164), (3200, 3200), (9008, 9011), (9172, 9174))
RULE_NAMES = {'planned': 'planned area quest chest', 'system': 'base quest system (system.lua, chest with contents)',
              'system2': 'base quest system 2 (fixed reward)', 'script': 'base quest script (unique id)',
              'stock': 'base reward chest 21584 with an action id'}
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


A_UNIQUE = 5


def has_contents(data, off):
    """does the item node at `off` hold item nodes (a container with things inside)?"""
    j, n = off + 2, len(data)
    while j < n:
        c = data[j]
        if c == G.ESC:
            j += 2
        elif c in (G.START, G.END):
            break
        else:
            j += 1
    return j + 1 < n and data[j] == G.START and data[j + 1] == G.T_ITEM


def base_rule(iid, aid, uid, contents, aids=()):
    """the rule that makes this item a base quest chest ('system', 'system2', 'script', 'stock'), or None"""
    if iid == STOCK_REWARD:
        return 'stock' if aid and aid not in aids else None
    if iid not in BASE_CHEST_IDS:
        return None
    if aid in SYSTEM_AIDS and uid and contents:
        return 'system'
    if aid == SYSTEM2_AID and uid in SYSTEM2_UIDS:
        return 'system2'
    if uid and any(lo <= uid <= hi for lo, hi in SCRIPT_UIDS):
        return 'script'
    return None


def find_base_quest_chests(data, aids=()):
    """[(node offset, item id, action id, (x, y, z), rule)] of the base server's quest chests (docstring, rule 2). Nodes
    that carry one of `aids` (the planned areas' block) are the first rule's."""
    out = []
    for iid in sorted(set(BASE_CHEST_IDS) | {STOCK_REWARD}):
        needle = bytes([G.START, G.T_ITEM]) + G.esc(struct.pack('<H', iid))
        i = data.find(needle)
        while i >= 0:
            if G.real(data, i):
                parsed = G.parse_item(G.payload(data, i + 2))
                if parsed and parsed[0] == iid:
                    attrs = parsed[1]
                    aid = struct.unpack('<H', attrs[G.A_ACTION])[0] if G.A_ACTION in attrs else 0
                    uid = struct.unpack('<H', attrs[A_UNIQUE])[0] if A_UNIQUE in attrs else 0
                    rule = base_rule(iid, aid, uid, has_contents(data, i) if aid or uid else False, aids)
                    if rule:
                        out.append((i, iid, aid, G.tile_position(data, i), rule))
            i = data.find(needle, i + 1)
    return out


def count_id(data, iid):
    needle = bytes([G.START, G.T_ITEM]) + G.esc(struct.pack('<H', iid))
    n, i = 0, data.find(needle)
    while i >= 0:
        n += G.real(data, i)
        i = data.find(needle, i + 1)
    return n


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
        check_otb=True, base=True, items_otb=None):
    new_id = new_id or reward_chest_id()
    if new_id in old_ids or new_id in BASE_CHEST_IDS or new_id == STOCK_REWARD:
        raise ChestError('the reward chest %d is one of the old ids' % new_id)
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise ChestError('no world map in %s/world' % data_dir)
    if check_otb:
        otb = items_otb or os.path.join(data_dir, 'items', 'items.otb')
        if not os.path.isfile(otb) or not otb_has(otb, new_id):
            raise ChestError('the reward chest %d is not in %s; nothing changed' % (new_id, otb))
    data = open(map_path, 'rb').read()
    if data[:2] == b'\x1f\x8b':
        raise ChestError('the world map is compressed; unpack it first')
    aids = chest_aids() if aids is None else aids
    chests = find_chests(data, old_ids, aids)
    seen = {c[0] for c in chests}
    for _off, iid, aid, p in chests:
        log('chest %d (action id %d) at %d,%d,%d -> %d' % ((iid, aid) + p + (new_id,)))
    by_rule = {}
    if base:
        for off, iid, aid, p, rule in find_base_quest_chests(data, aids):
            if off in seen:
                continue
            seen.add(off)
            chests.append((off, iid, aid, p))
            by_rule.setdefault(rule, []).append(iid)
        for rule in ('system', 'system2', 'script', 'stock'):
            ids = by_rule.get(rule)
            if ids:
                kinds = ', '.join('%d x %d' % (ids.count(i), i) for i in sorted(set(ids)))
                log('%s: %d (%s) -> %d' % (RULE_NAMES[rule], len(ids), kinds, new_id))
    if not chests:
        log('reward chests: none of the old ones on the map; nothing to do')
        return dict(changed=0, chests=[], base=0)
    new = patch(data, chests, new_id)
    left = find_chests(new, old_ids, aids) + ([c[:4] for c in find_base_quest_chests(new, aids)] if base else [])
    if left or count_id(new, new_id) != count_id(data, new_id) + len(chests):
        raise ChestError('internal: the patched map does not hold the new chests; nothing written')
    summary = dict(changed=len(chests), chests=[c[3] for c in chests], base=sum(len(v) for v in by_rule.values()))
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
        elif a in ('--map', '--out', '--items-otb'):
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
        run(pos[0], dry=args.get('--dry-run', False), map_path=args.get('--map'), out=args.get('--out'),
            items_otb=args.get('--items-otb'))
    except ChestError as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
