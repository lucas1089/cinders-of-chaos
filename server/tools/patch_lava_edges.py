#!/usr/bin/env python3
"""Take the lava edge strips off the placed lava hunts (server/README.md "Lava edge strips (O288)"), idempotent.

usage: python3 -I server/tools/patch_lava_edges.py DATA_DIR [--dry-run] [--map FILE] [--out FILE]

Owner, 2026-10-28: "some hunts have wrong floors", brown strips and an ochre bar on the grey rock of Ironhorn Slagworks.
The cause: the lava decoration kit (areaplan/decor_kits.json) laid the stock items 5840-5843 ("small lava cracks"), the
old lava edge pieces, as floor detail: a narrow brown strip with a crack line (5840, 5841, 5843) and a flat bar (5842).
The kit is fixed (its group is gone; area_planner_test.py rejects ground, border and edge pieces as decoration), but the
hunts already on the map keep their tiles. DATA_DIR is the server's data folder (world/<map>.otbm). Install step
`lavaedges`, after `deadholes`, before poi. Every tile of a plan of areaplan/plans/ and areaplan/chronicle/ whose biome
uses the lava kit (lava, waste), on all its floors, loses its items 5840-5843; the ground and everything else stay.
A house tile and a tile the writer cannot write back unchanged are left alone and counted. The map goes through
<map>.otbm.tmp, its tile count is checked, and <map>.otbm.bak is written first when missing. A second run changes
nothing. --dry-run lists and writes nothing; --out writes the new map there. Exit 0 on success, 1 on a refusal.
Python 3 and numpy (tools/map/otbm.py). Test: tools/patch_lava_edges_test.py (synthetic map).
"""
import glob, json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import patch_map_fixes as PM  # noqa: E402

EDGES = frozenset((5840, 5841, 5842, 5843))
PLANS = [os.path.join(HERE, 'areaplan', d) for d in ('plans', 'chronicle')]
KITS = os.path.join(HERE, 'areaplan', 'decor_kits.json')


class EdgeError(Exception):
    pass


def lava_rects(plan_dirs=PLANS, kits_path=KITS):
    """(id, x0, y0, x1, y1, z0, z1) of every plan whose biome uses the lava decoration kit"""
    biome_kit = json.load(open(kits_path, encoding='utf-8'))['biome_kit']
    out = []
    for d in plan_dirs:
        for f in sorted(glob.glob(os.path.join(d, '*.json'))):
            p = json.load(open(f, encoding='utf-8'))
            if biome_kit.get(p.get('biome')) != 'lava':
                continue
            o, (w, h) = p['origin'], p['size']
            out.append((p['id'], o['x'], o['y'], o['x'] + w - 1, o['y'] + h - 1, o['z'], o['z'] + p['floors'] - 1))
    return out


def plan(tiles, world_tiles, rects, log):
    """strip the edge items from the parsed tiles; returns (removed, tiles changed, tiles left alone)"""
    want = [p for p in world_tiles if any(r[1] <= p[0] <= r[3] and r[2] <= p[1] <= r[4] and r[5] <= p[2] <= r[6]
                                         for r in rects)]
    tiles.load(want)
    removed = changed = left = 0
    for p in want:
        if p in tiles.bad:
            left += 1
            continue
        t = tiles.get(p)
        if t is None or not any(i in EDGES for i, _a in t['items']):
            continue
        keep = [(i, a) for i, a in t['items'] if i not in EDGES]
        removed += len(t['items']) - len(keep)
        changed += 1
        tiles.set(p, dict(t, items=keep))
    return removed, changed, left


def run(data_dir, dry=False, map_path=None, out=None, rects=None, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise EdgeError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise EdgeError('the world map is compressed; unpack it first')
    import otbm
    m = otbm.load_otbm(map_path)
    world = IC.World(m)
    tiles = PM.Tiles(world, map_path)
    rects = lava_rects() if rects is None else rects
    pos = [(int(x), int(y), int(z)) for x, y, z in zip(m.tiles['x'], m.tiles['y'], m.tiles['z'])]
    # only tiles that hold an edge item are parsed: the rest of the rectangles is skipped by the stack check
    near = [p for p in pos if any(r[1] <= p[0] <= r[3] and r[2] <= p[1] <= r[4] and r[5] <= p[2] <= r[6] for r in rects)
            and EDGES & set(world.stack(p))]
    removed, n, left = plan(tiles, near, rects, log)
    log('lava edges: %d strip(s) removed on %d tile(s) of %d lava hunt(s), %d tile(s) left alone'
        % (removed, n, len(rects), left))
    changed = dict(tiles.changed)
    if not changed:
        log('lava edges: nothing to do')
        return removed
    if dry and not out:
        return removed
    target = out or map_path
    tmp = target + '.tmp'
    IC.write_map(map_path, tmp, list(changed), dict(changed))
    m2 = otbm.load_otbm(tmp)
    if len(m2.tiles['x']) != world.count():
        os.remove(tmp)
        raise EdgeError('internal: the new map has %d tiles, not %d; nothing written' % (len(m2.tiles['x']), world.count()))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('lava edges: written to %s' % target)
    return removed


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
    except (EdgeError, PM.FixError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
