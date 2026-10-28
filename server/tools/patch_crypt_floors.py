#!/usr/bin/env python3
"""Lay one crypt floor on the placed catacomb hunts (server/README.md "Crypt floor (O288)"), idempotent.

usage: python3 -I server/tools/patch_crypt_floors.py DATA_DIR [--dry-run] [--map FILE] [--out FILE]

Owner, 2026-10-28: "some hunts have wrong floors": in the Hollow Crypt the corridors alternated, tile by tile, dark
streaked tiles and round reddish-brown pebble discs. The area generator's `crypt` ground family (areagen_config.lua)
mixed 13189 ("dark sandy floor") with 12237 ("rutted stone floor"), a patch tile of the stain family 12234-12237 that does
not tile with it. The family is fixed (13189 only; area_planner_test.py checks it), but the hunts already on the map keep
their tiles. DATA_DIR is the server's data folder (world/<map>.otbm). Install step `cryptfloors`, after `lavaedges`,
before poi. Every tile of a plan of areaplan/plans/ and areaplan/chronicle/ whose biome is `catacomb` (the biomes of the
`crypt` family: Hollow Crypt, Bonechoir Catacomb, Bonewright Galleries, Graveknell Catacombs, Lanternless Catacombs), on
all its floors, whose ground is 12237 gets ground 13189; everything else stays. A house tile and a tile the writer
cannot write back unchanged are left alone and counted. The map goes through <map>.otbm.tmp, its tile count is checked,
and <map>.otbm.bak is written first when missing. A second run changes nothing. --dry-run lists and writes nothing; --out
writes the new map there. Exit 0 on success, 1 on a refusal.
Python 3 and numpy (tools/map/otbm.py). Test: tools/patch_crypt_floors_test.py (synthetic map).
"""
import glob, json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import patch_map_fixes as PM  # noqa: E402

BAD, GOOD = 12237, 13189
BIOMES = ('catacomb',)
PLANS = [os.path.join(HERE, 'areaplan', d) for d in ('plans', 'chronicle')]


class FloorError(Exception):
    pass


def crypt_rects(plan_dirs=PLANS):
    """(id, x0, y0, x1, y1, z0, z1) of every plan whose biome lays the crypt ground family"""
    out = []
    for d in plan_dirs:
        for f in sorted(glob.glob(os.path.join(d, '*.json'))):
            p = json.load(open(f, encoding='utf-8'))
            if p.get('biome') not in BIOMES:
                continue
            o, (w, h) = p['origin'], p['size']
            out.append((p['id'], o['x'], o['y'], o['x'] + w - 1, o['y'] + h - 1, o['z'], o['z'] + p['floors'] - 1))
    return out


def plan(tiles, world_tiles, rects, log):
    """swap the ground on the parsed tiles; returns (tiles changed, tiles left alone)"""
    want = [p for p in world_tiles if any(r[1] <= p[0] <= r[3] and r[2] <= p[1] <= r[4] and r[5] <= p[2] <= r[6]
                                         for r in rects)]
    tiles.load(want)
    changed = left = 0
    for p in want:
        if p in tiles.bad:
            left += 1
            continue
        t = tiles.get(p)
        if t is None:
            continue
        if t.get('ground') == BAD:
            tiles.set(p, dict(t, ground=GOOD))
        elif not t.get('ground') and t['items'] and t['items'][0][0] == BAD:
            tiles.set(p, dict(t, items=[(GOOD, t['items'][0][1])] + list(t['items'][1:])))
        else:
            continue
        changed += 1
    return changed, left


def run(data_dir, dry=False, map_path=None, out=None, rects=None, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise FloorError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise FloorError('the world map is compressed; unpack it first')
    import otbm
    m = otbm.load_otbm(map_path)
    world = IC.World(m)
    tiles = PM.Tiles(world, map_path)
    rects = crypt_rects() if rects is None else rects
    pos = [(int(x), int(y), int(z)) for x, y, z in zip(m.tiles['x'], m.tiles['y'], m.tiles['z'])]
    near = [p for p in pos if any(r[1] <= p[0] <= r[3] and r[2] <= p[1] <= r[4] and r[5] <= p[2] <= r[6] for r in rects)
            and world.stack(p)[:1] == [BAD]]
    n, left = plan(tiles, near, rects, log)
    log('crypt floors: ground %d -> %d on %d tile(s) of %d catacomb hunt(s), %d tile(s) left alone'
        % (BAD, GOOD, n, len(rects), left))
    changed = dict(tiles.changed)
    if not changed:
        log('crypt floors: nothing to do')
        return n
    if dry and not out:
        return n
    target = out or map_path
    tmp = target + '.tmp'
    IC.write_map(map_path, tmp, list(changed), dict(changed))
    m2 = otbm.load_otbm(tmp)
    if len(m2.tiles['x']) != world.count():
        os.remove(tmp)
        raise FloorError('internal: the new map has %d tiles, not %d; nothing written' % (len(m2.tiles['x']), world.count()))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('crypt floors: written to %s' % target)
    return n


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            opts[a] = True
        elif a in ('--map', '--out'):
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
        run(pos[0], dry=opts.get('--dry-run', False), map_path=opts.get('--map'), out=opts.get('--out'))
    except (FloorError, PM.FixError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
