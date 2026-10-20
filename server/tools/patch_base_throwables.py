#!/usr/bin/env python3
"""Stackable throwing weapons leave the base server's data (owner 2026-10-20; server/README.md "Throwing weapons").

usage: python3 -I patch_base_throwables.py DATA_DIR [--dry-run]

The ids are the block in server/data/lib/chaos_throwables.lua (small stone, spear, throwing star and knife, hunting spear,
viper star, enchanted spear, assassin star, royal spear), the same list the loot layer and the hunt tracker read. Like
patch_base_archery.py does for arrows and bolts (its functions do the editing here):

1. data/monster (XML and Lua, not the Chaos folders): loot entries of them (by id or by name) are removed.
2. data/npc: shop lists of the XML NPCs lose them; in the NPC scripts one-line shop entries go and buy keywords for them
   are commented out; rewards and trade results become gold coins worth the item (sell_prices.lua, else 5 gold each).
3. Other base Lua scripts (not data/scripts/chaos, monster, npc, lib, weapons, spells): rewards of them become gold coins.

items.xml, weapons.xml and what a character already holds stay as they are. Idempotent: a second run changes nothing.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_base_archery as A  # noqa: E402

SERVER = os.path.dirname(HERE)
CONFIG = os.path.join(SERVER, 'data', 'lib', 'chaos_throwables.lua')
SELL = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'sell_prices.lua')
MARK = '-- Chaos: no throwing weapons (patch_base_throwables.py) '
DEFAULT_GOLD = 5


def read_items(path=CONFIG):
    """{id: name} from the `T.items = { [id] = "name", ... }` block"""
    text = A._strip_comments(open(path, encoding='utf-8').read())
    m = re.search(r'T\.items\s*=\s*\{(.*?)\n\}', text, re.S)
    assert m, 'T.items not found in ' + path
    items = {int(i): n for i, n in re.findall(r'\[(\d+)\]\s*=\s*"([^"]+)"', m.group(1))}
    assert items, 'no throwables listed'
    return items


def read_ids(path=CONFIG):
    return sorted(read_items(path))


def gold_cfg(ids):
    prices = {}
    if os.path.exists(SELL):
        for i, v in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', open(SELL, encoding='utf-8').read()):
            if int(i) in ids:
                prices[int(i)] = max(1, int(v))
    return {'ammo': prices, 'defaultRefund': DEFAULT_GOLD}


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data = args[0]
    items = read_items()
    ids = set(items)
    names = {n.lower() for n in items.values()}
    is_gone = A._id_or_name(ids, names)
    cfg = gold_cfg(ids)
    writes = {}
    chaos_dir = os.sep + 'chaos' + os.sep

    loot = 0
    for p in A.walk(os.path.join(data, 'monster'), ('.xml', '.lua')):
        if chaos_dir in p:
            continue
        t = A.read(p)
        new, k = (A.patch_monster_xml if p.lower().endswith('.xml') else A.patch_monster_lua)(t, is_gone)
        if k:
            loot += k
            writes[p] = new
    print('monsters: %d throwing weapon loot entr%s removed' % (loot, 'y' if loot == 1 else 'ies'))

    shop = 0
    for p in A.walk(os.path.join(data, 'npc'), ('.xml', '.lua')):
        t = A.read(p)
        if p.lower().endswith('.xml'):
            new, k = A.patch_npc_xml(t, ids)
        else:
            new, k = A.patch_npc_lua(t, ids)
            new = new.replace(A.LUA_MARK, MARK)
            new, k2 = A.patch_rewards(new, cfg, ids, npc_script=True)
            k += k2
        if k:
            shop += k
            writes[p] = new
    print('NPCs: %d throwing weapon offer(s) or reward(s) removed' % shop)

    rewards = 0
    skip = tuple(os.path.join(data, d) for d in
                 (os.path.join('scripts', 'chaos'), 'monster', 'npc', 'lib', 'weapons', 'spells'))
    for p in A.walk(data, ('.lua',)):
        if p.startswith(skip):
            continue
        t = A.read(p)
        new, k = A.patch_rewards(t, cfg, ids)
        if k:
            rewards += k
            writes[p] = new
            print('  rewards: %s (%d)' % (os.path.relpath(p, data), k))
    print('scripts: %d throwing weapon reward(s) turned into gold' % rewards)

    if dry:
        print('dry run: nothing written (%d file(s) would change)' % len(writes))
        return 0
    for p, t in writes.items():
        A.write(p, t)
    print('%d file(s) written' % len(writes))
    return 0


if __name__ == '__main__':
    sys.exit(main())
