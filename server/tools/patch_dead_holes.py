#!/usr/bin/env python3
"""Take the dead floor changes off the base map (server/README.md "Dead holes (O264)"), idempotent.

usage: python3 -I server/tools/patch_dead_holes.py DATA_DIR [--dry-run] [--map FILE] [--out FILE] [--csv FILE]

Owner, 2026-10-26: "esse buraco nao leva a lugar nenhum" (this hole leads nowhere). tools/check_dead_holes.py found the
floor changes of the installed map whose landing has no walkable ground (no tile one floor down, a wall there, nothing
above a ramp or ladder); tools/dead_holes.csv lists them (positions and item ids only, no map data). DATA_DIR is the
server's data folder (world/<map>.otbm, items/items.otb and items.xml). Install step `deadholes`, after `mapfixes`
(the hall's map and the earlier fixes are in), before poi. For each row:
  remove   the item `item` goes off the tile (a hole, pitfall, trapdoor, grate, ladder, ramp: the ground under it stays)
  ground   the tile's ground IS the floor change (stairs, an open pitfall): it becomes `ground`, the plain walkable
           ground round it (chosen when the CSV was written)
  none     no plain ground was near: left alone
A row is applied only while the tile is still dead on the map in front of the tool (check_dead_holes.check_tile): a lower
floor mapped since, or an area installed below, keeps its hole. A row whose item is not on the tile (a second run, a
map that is not this one), a house tile and a tile the writer cannot write back unchanged (a container, an unknown
attribute) are left alone; the last two are listed. The map goes through <map>.otbm.tmp, its tile count is checked,
and <map>.otbm.bak is written first when missing. A second run changes nothing. --dry-run lists and writes nothing;
--out writes the new map there. Exit 0 on success, 1 on a refusal.
Our own areas (areaplan plans, install_*.py decor) have none: check_dead_holes.py found no dead change in the 73
compiled plans, the hall or the fixed areas; a new one is fixed in its plan, not here.
Python 3 and numpy (tools/map/otbm.py, itemdb.py). Test: tools/patch_dead_holes_test.py (synthetic map).
"""
import csv, os, shutil, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import patch_map_fixes as PM  # noqa: E402
import check_dead_holes as CD  # noqa: E402

LIST = os.path.join(HERE, 'dead_holes.csv')
ACTIONS = ('remove', 'ground', 'none')


class HoleError(Exception):
    pass


def read_rows(path=LIST):
    rows = csv.DictReader(line for line in open(path, encoding='utf-8') if not line.startswith('#'))
    out = []
    for r in rows:
        if r['action'] not in ACTIONS or (r['action'] == 'ground') != bool(r['ground']):
            raise HoleError('dead_holes.csv: bad row %s' % dict(r))
        out.append(dict(pos=(int(r['x']), int(r['y']), int(r['z'])), item=int(r['item']), action=r['action'],
                        ground=int(r['ground']) if r['ground'] else None, kind=r.get('kind', '')))
    return out


def plan(tiles, rows, kinds, mworld, log):
    """apply the rows to the parsed tiles; returns Counter of what was done by action"""
    tiles.load([r['pos'] for r in rows if r['action'] != 'none'])
    done, alive, left = Counter(), 0, Counter()
    still = {}
    for r in rows:
        p, iid = r['pos'], r['item']
        if r['action'] == 'none':
            left['no plain ground'] += 1
            continue
        if p in tiles.bad:
            left[tiles.bad[p]] += 1
            log('dead hole %d at %d,%d,%d: %s; left alone' % ((iid,) + p + (tiles.bad[p],)))
            continue
        t = tiles.get(p)
        if t is None:
            continue  # not this map
        if p not in still:
            res = CD.check_tile(kinds, mworld, p)
            still[p] = res is not None and res['dead']
        ids = IC.stack_of(t)
        if iid not in ids:
            continue  # gone already (a second run)
        if not still[p]:
            alive += 1
            continue  # it leads somewhere now
        items = list(t['items'])
        if r['action'] == 'remove':
            items = [(j, a) for j, a in items if j != iid]
            tiles.set(p, dict(t, items=items))
        else:
            if t.get('ground') == iid:
                tiles.set(p, dict(t, ground=r['ground']))
            elif items and items[0][0] == iid:
                items[0] = (r['ground'], items[0][1])
                tiles.set(p, dict(t, items=items))
            else:
                continue  # the item is not the ground of this tile: not what the row meant
        done[r['action']] += 1
    return done, alive, left


def run(data_dir, dry=False, map_path=None, out=None, list_path=LIST, kinds=None, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise HoleError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise HoleError('the world map is compressed; unpack it first')
    if kinds is None:
        otb = os.path.join(data_dir, 'items', 'items.otb')
        if not os.path.isfile(otb):
            raise HoleError('no %s' % otb)
        xml = os.path.join(data_dir, 'items', 'items.xml')
        kinds = CD.Kinds.from_files(otb, xml if os.path.isfile(xml) else None)
    import otbm
    m = otbm.load_otbm(map_path)
    world = IC.World(m)
    tiles = PM.Tiles(world, map_path)
    done, alive, left = plan(tiles, read_rows(list_path), kinds, CD.MapWorld(m), log)
    changed = dict(tiles.changed)
    log('dead holes: %d removed, %d turned into plain ground, %d still lead somewhere (kept), %d left alone'
        % (done['remove'], done['ground'], alive, sum(left.values())))
    for why, n in sorted(left.items()):
        log('  left alone: %s x %d' % (why, n))
    if not changed:
        log('dead holes: nothing to do')
        return dict(done)
    log('dead holes: %d tile(s) to rewrite' % len(changed))
    if dry and not out:
        return dict(done)
    target = out or map_path
    tmp = target + '.tmp'
    IC.write_map(map_path, tmp, list(changed), dict(changed))
    m2 = otbm.load_otbm(tmp)
    if len(m2.tiles['x']) != world.count():
        os.remove(tmp)
        raise HoleError('internal: the new map has %d tiles, not %d; nothing written' % (len(m2.tiles['x']), world.count()))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('dead holes: written to %s' % target)
    return dict(done)


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            opts[a] = True
        elif a in ('--map', '--out', '--csv'):
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
            list_path=opts.get('--csv', LIST))
    except (HoleError, PM.FixError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
