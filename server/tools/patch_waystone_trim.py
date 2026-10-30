#!/usr/bin/env python3
"""Block the dead-end lobes of the waystone maps that are too big (server/README.md "Spawn fills of the waystone maps and the late
game areas (O337)"), idempotent.

usage: python3 -I server/tools/patch_waystone_trim.py DATA_DIR [--dry-run] [--map FILE] [--out FILE] [--rows FILE]

Owner, 2026-10-30 ("faca o que achar melhor"): waystone map 12 (tier VI forest and desert) is 20,896 walkable tiles, a 391 s full
sweep against the rift limit of 300 s (rift_layout_balance_config.lua sweepSecondsMax), map 9 (tier V desert) 304 s. Their long
dead ends hold few monsters and nothing a run needs (no boss lever, no entrance): tools/waystone_trim.json lists, per map, the
tiles of the narrow necks in front of those lobes (tools/gen_spawn_expand.py finds them on the installed map: a lobe behind a neck
of at most NECK tiles, no lever or entrance in it, few monsters) with the solid decoration of the neighbourhood (a bush, a palm, a
stone wall) to put on each. A lobe behind blocked necks cannot be reached on foot, so the full sweep is shorter and the audit counts
the rest of the map; the monsters in it are taken out by the spawn file (spawn_expand.json `remove`).
DATA_DIR is the server's data folder (world/<map>.otbm). Install step `waystonetrim`, after `huntannexes`, before `hubnpcs`. A tile
that has the item already is left alone; a tile with no ground, a house tile and a tile the writer cannot write back unchanged (a
container, an unknown attribute) are left alone and listed. The map goes through <map>.otbm.tmp, its tile count is checked, and
<map>.otbm.bak is written first when missing. A second run changes nothing. --dry-run lists and writes nothing; --out writes the new
map there. Exit 0 on success, 1 on a refusal.
Python 3 and numpy (tools/map/otbm.py). Test: tools/patch_waystone_trim_test.py (synthetic map).
"""
import json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import patch_map_fixes as PM  # noqa: E402

ROWS = os.path.join(HERE, 'waystone_trim.json')


class TrimError(Exception):
    pass


def read_rows(path=ROWS):
    """[dict(map, items=[(x, y, z, item)])] of tools/waystone_trim.json"""
    with open(path, encoding='utf-8') as f:
        doc = json.load(f)
    out = []
    for m in doc['maps']:
        items = [tuple(int(v) for v in r) for r in m['items']]
        if any(len(r) != 4 for r in items):
            raise TrimError('waystone_trim.json: map %s has a row that is not [x, y, z, item]' % m.get('map'))
        if len(set(r[:3] for r in items)) != len(items):
            raise TrimError('waystone_trim.json: map %s names a tile twice' % m.get('map'))
        out.append(dict(map=int(m['map']), items=items))
    return out


def plan(tiles, rows, kinds, log):
    """put the items on the parsed tiles; returns dict(done, kept, left)"""
    res = dict(done=0, kept=0, left=0)
    want = [r[:3] for m in rows for r in m['items']]
    tiles.load(want)
    for m in rows:
        for x, y, z, item in m['items']:
            p = (x, y, z)
            if p in tiles.bad:
                log('waystone map %d: %s: %s; left alone' % (m['map'], p, tiles.bad[p]))
                res['left'] += 1
                continue
            t = tiles.get(p)
            if t is None:
                raise TrimError('waystone map %d: no tile at %s' % (m['map'], p))
            if PM.ground_of(t, kinds) is None:
                log('waystone map %d: the tile %s has no ground; left alone' % (m['map'], p))
                res['left'] += 1
                continue
            if any(i == item for i, _a in t['items']):
                res['kept'] += 1
                continue
            tiles.set(p, dict(t, items=list(t['items']) + [(item, {})]))
            res['done'] += 1
    return res


def run(data_dir, dry=False, map_path=None, out=None, rows_path=ROWS, kinds=None, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise TrimError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise TrimError('the world map is compressed; unpack it first')
    if kinds is None:
        kinds = PM.Kinds.from_otb(data_dir)
    rows = read_rows(rows_path)
    import otbm
    m = otbm.load_otbm(map_path)
    world = IC.World(m)
    tiles = PM.Tiles(world, map_path)
    res = plan(tiles, rows, kinds, log)
    log('waystone trim: %d tile(s) blocked, %d there already, %d left alone' % (res['done'], res['kept'], res['left']))
    changed = dict(tiles.changed)
    if not changed:
        log('waystone trim: nothing to do')
        return res
    if dry and not out:
        return res
    target = out or map_path
    tmp = target + '.tmp'
    IC.write_map(map_path, tmp, list(changed), dict(changed))
    m2 = otbm.load_otbm(tmp)
    if len(m2.tiles['x']) != world.count():
        os.remove(tmp)
        raise TrimError('internal: the new map has %d tiles, not %d; nothing written' % (len(m2.tiles['x']), world.count()))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('waystone trim: written to %s' % target)
    return res


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            opts[a] = True
        elif a in ('--map', '--out', '--rows'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            print('unknown option %s' % a)
            return 1
        else:
            pos.append(a)
        i += 1
    if len(pos) != 1:
        print(__doc__)
        return 1
    try:
        run(pos[0], dry=opts.get('--dry-run', False), map_path=opts.get('--map'), out=opts.get('--out'),
            rows_path=opts.get('--rows', ROWS))
    except (TrimError, PM.FixError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
