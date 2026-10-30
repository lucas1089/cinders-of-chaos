#!/usr/bin/env python3
"""Put the portal of every hunt annex into its base hunt (server/README.md "Hunt annexes (O337)"), idempotent.

usage: python3 -I server/tools/patch_hunt_annexes.py DATA_DIR [--dry-run] [--map FILE] [--out FILE] [--rows FILE]

Owner, 2026-10-30 ("expanda o mapa deles"): five rare high level base hunts (Emerald Mage, Scaledrake, deathrattle, Blackblade,
fangclaw) have too few monsters on too little ground. Each gets an annex: a planned cave of areaplan/annexes/<id>.json (the
fixed-area folder install_content_areas.py places at the plan's own origin, with its spawns, no hall teleport). This step is
the way in: a magic forcefield (item 1387) with a destination on the tile `portal` of the base hunt, leading to `dest`, the
arrival tile of the annex. The way out is the annex's exit portal (the plan's `exit.to`, the hunt's tile `back`).
tools/hunt_annexes.json: {"annexes": [{"id": plan id, "hunt": hall_hunts.csv id, "portal": [x, y, z], "dest": [x, y, z],
"back": [x, y, z]}]}; tools/hunt_annexes_test.py compiles each plan and checks `dest` is its arrival and `back` its exit.
DATA_DIR is the server's data folder (world/<map>.otbm). Install step `huntannexes`, after `huntgates`, before `hubnpcs`.
For each row, when the annex is on the map (its `dest` tile has ground): the portal tile gets the forcefield with the
destination and a description; a tile that has it already (same destination) is left alone; a tile that is no ground, a house
tile and a tile the writer cannot write back unchanged (a container, an unknown attribute) are left alone and listed. A row
whose annex is not placed yet (the dest tile is missing: a run with --only) is skipped. The map goes through <map>.otbm.tmp,
its tile count is checked, and <map>.otbm.bak is written first when missing. A second run changes nothing. --dry-run lists and
writes nothing; --out writes the new map there. Exit 0 on success, 1 on a refusal.
Python 3 and numpy (tools/map/otbm.py). Test: tools/patch_hunt_annexes_test.py (synthetic map).
"""
import json, os, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import patch_map_fixes as PM  # noqa: E402

ROWS = os.path.join(HERE, 'hunt_annexes.json')
PORTAL = 1387  # the magic forcefield the hunt teleports and the plans' exit portals use
ATTR_DESC = 1
TEXT = 'A portal to the deeper part of this hunt (%s).'


class AnnexError(Exception):
    pass


def read_rows(path=ROWS):
    with open(path, encoding='utf-8') as f:
        rows = json.load(f)['annexes']
    out = []
    for r in rows:
        for k in ('id', 'hunt', 'portal', 'dest', 'back'):
            if k not in r:
                raise AnnexError('hunt_annexes.json: row without %s: %s' % (k, r))
        for k in ('portal', 'dest', 'back'):
            if len(r[k]) != 3 or not all(isinstance(v, int) for v in r[k]):
                raise AnnexError('hunt_annexes.json: %s of %s is not [x, y, z]' % (k, r['id']))
        out.append(dict(id=r['id'], hunt=r['hunt'], portal=tuple(r['portal']), dest=tuple(r['dest']), back=tuple(r['back']),
                        name=r.get('name') or r['hunt']))
    ids = [r['id'] for r in out]
    if len(set(ids)) != len(ids):
        raise AnnexError('hunt_annexes.json: an annex twice')
    return out


def description(name):
    text = (TEXT % name).encode('latin-1', 'replace')
    return bytes([ATTR_DESC]) + struct.pack('<H', len(text)) + text


def plan(tiles, world, rows, kinds, log):
    """put the portals on the parsed tiles; returns Counter-like dict(done, kept, skipped, left)"""
    res = dict(done=0, kept=0, skipped=0, left=0)
    tiles.load([r['portal'] for r in rows])
    for r in rows:
        p = tuple(r['portal'])
        if not world.has(tuple(r['dest'])):
            log('annex %s: its arrival %s is not on the map (area not placed); skipped' % (r['id'], tuple(r['dest'])))
            res['skipped'] += 1
            continue
        if p in tiles.bad:
            log('annex %s: portal tile %s: %s; left alone' % (r['id'], p, tiles.bad[p]))
            res['left'] += 1
            continue
        t = tiles.get(p)
        if t is None:
            raise AnnexError('annex %s: no tile at the portal position %s' % (r['id'], p))
        ground = PM.ground_of(t, kinds)
        if ground is None:
            log('annex %s: the tile %s has no ground; left alone' % (r['id'], p))
            res['left'] += 1
            continue
        have = [(i, a) for i, a in t['items'] if i == PORTAL]
        if have:
            if tuple(have[0][1].get('tele') or ()) == tuple(r['dest']):
                res['kept'] += 1
                continue
            log('annex %s: another teleport stands at %s; left alone' % (r['id'], p))
            res['left'] += 1
            continue
        items = list(t['items']) + [(PORTAL, dict(tele=tuple(r['dest']), raw=description(r['name'])))]
        tiles.set(p, dict(t, items=items))
        res['done'] += 1
    return res


def run(data_dir, dry=False, map_path=None, out=None, rows_path=ROWS, kinds=None, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise AnnexError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise AnnexError('the world map is compressed; unpack it first')
    if kinds is None:
        kinds = PM.Kinds.from_otb(data_dir)
    rows = read_rows(rows_path)
    import otbm
    m = otbm.load_otbm(map_path)
    world = IC.World(m)
    tiles = PM.Tiles(world, map_path)
    res = plan(tiles, world, rows, kinds, log)
    log('hunt annexes: %d portal(s) put in, %d there already, %d skipped, %d left alone' % (res['done'], res['kept'], res['skipped'], res['left']))
    changed = dict(tiles.changed)
    if not changed:
        log('hunt annexes: nothing to do')
        return res
    if dry and not out:
        return res
    target = out or map_path
    tmp = target + '.tmp'
    IC.write_map(map_path, tmp, list(changed), dict(changed))
    m2 = otbm.load_otbm(tmp)
    if len(m2.tiles['x']) != world.count():
        os.remove(tmp)
        raise AnnexError('internal: the new map has %d tiles, not %d; nothing written' % (len(m2.tiles['x']), world.count()))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('hunt annexes: written to %s' % target)
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
    except (AnnexError, PM.FixError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
