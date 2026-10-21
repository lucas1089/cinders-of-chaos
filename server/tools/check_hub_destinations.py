#!/usr/bin/env python3
"""Check that every guild hall Teleport Hub destination has a landing tile on the map.

usage: python3 -I server/tools/check_hub_destinations.py DATA_DIR [--config guild_config.lua]

DATA_DIR is a server data folder with world/<map>.otbm (the map named in --map, default: the only .otbm in world/) and items/items.otb.
guild_hall.lua lands a player on the nearest free tile within 3 tiles of a destination (a ground, nothing that blocks
walking or pathing, no house); a destination without one answers "This portal leads nowhere right now." Run it after
the content areas are installed into the map. Each destination's way back (`back`, owner 2026-10-21) must be a free
tile too (guild_hall.lua puts its forcefield there at startup). Exit 1 when a destination has no landing tile or its
way back is not free.
The map is read with tools/map/otbm.py (numpy; about 90 s for the base map). The blocking flags are the items.otb
ones (bit 0 block solid, bit 2 block path), as the engine reads them.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FLAG_BLOCK_SOLID, FLAG_BLOCK_PATH, GROUP_GROUND = 1, 4, 1
RADIUS = 3


def read_hub(config_path):
    """[{name, x, y, z, level}] from the hall.hub table of guild_config.lua"""
    text = open(config_path, encoding='utf-8').read()
    i = text.index('hub = {')
    block = text[i:text.index('},\n\n', i)]
    out = []
    for m in re.finditer(r'name = "([^"]+)", pos = \{x = (\d+), y = (\d+), z = (\d+)\}(?:, level = (\d+))?'
                         r'(?:, back = \{x = (\d+), y = (\d+), z = (\d+)\})?', block):
        out.append({'name': m.group(1), 'x': int(m.group(2)), 'y': int(m.group(3)), 'z': int(m.group(4)),
                    'level': int(m.group(5) or 0),
                    'back': (int(m.group(6)), int(m.group(7)), int(m.group(8))) if m.group(6) else None})
    return out


def landing(dest, free):
    """(x, y) of the nearest free tile within RADIUS (square rings outwards, as C.landingSpot), or None"""
    for r in range(RADIUS + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) == r and free(dest['x'] + dx, dest['y'] + dy, dest['z']):
                    return dest['x'] + dx, dest['y'] + dy
    return None


def dead_ends(hub, free):
    return [d for d in hub if landing(d, free) is None]


def bad_backs(hub, free):
    """the destinations without a way back or whose way back is not a free tile"""
    return [d for d in hub if not d.get('back') or not free(*d['back'])]


def map_free(data_dir, map_name):
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools', 'map'))
    from otbm import load_map
    from itemdb import ItemDB
    m = load_map(os.path.join(data_dir, 'world', map_name))
    db = ItemDB(os.path.join(data_dir, 'items', 'items.otb'))

    def free(x, y, z):
        i = m.find(x, y, z)
        if i < 0 or int(m.tiles['house'][i]):
            return False
        st = m.stack(i)
        if len(st) == 0 or int(db.group[st[0]]) != GROUP_GROUND:
            return False
        return not any(int(db.flags[s]) & (FLAG_BLOCK_SOLID | FLAG_BLOCK_PATH) for s in st)
    return free


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if not args:
        print(__doc__)
        return 2
    cfg = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'guild_config.lua')
    map_name = None
    for k, a in enumerate(argv):
        if a == '--config':
            cfg = argv[k + 1]
            args.remove(cfg)
        if a == '--map':
            map_name = argv[k + 1]
            args.remove(map_name)
    hub = read_hub(cfg)
    if not hub:
        print('no hub destinations found in', cfg)
        return 1
    if map_name is None:
        maps = sorted(n for n in os.listdir(os.path.join(args[0], 'world')) if n.endswith('.otbm'))
        if len(maps) != 1:
            print('pass --map NAME: world/ holds %d .otbm files' % len(maps))
            return 2
        map_name = maps[0]
    free = map_free(args[0], map_name)
    bad = dead_ends(hub, free) + bad_backs(hub, free)
    for d in hub:
        at = landing(d, free)
        back = d.get('back')
        print('%-16s (%d,%d,%d) level %d: %s; %s' % (d['name'], d['x'], d['y'], d['z'], d['level'],
              'lands at %d,%d' % at if at else 'LEADS NOWHERE',
              ('way back at %d,%d,%d' % back + ('' if free(*back) else ' NOT FREE')) if back else 'NO WAY BACK'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
