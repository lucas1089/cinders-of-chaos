#!/usr/bin/env python3
"""Map fixes of the owner's report of 2026-10-21 (server/README.md "Map fixes"), idempotent, in one pass over the map.

usage: python3 -I server/tools/patch_map_fixes.py DATA_DIR [--dry-run] [--map FILE] [--out FILE]
                                                   [--only teleports,hub,temples]

DATA_DIR is the server's data folder (world/<map>.otbm, items/items.otb). Run it after install_content_areas.py
(install step `mapfixes`, after contentareas and before poi). Three parts:
  teleports  every row of tools/teleport_fixes.csv: the teleport item `item` on x,y,z gets the destination to_x,to_y,
             to_z (`dest`; the destination must be a tile with ground and nothing that blocks, else the run is refused),
             goes (`remove`; only when it has no action id, no unique id and no destination that is a map tile) or keeps its place
             without a destination (`nodest`). A row whose item is not there (any more), or already as the row wants
             it, is left alone. The rows come from a scan of the installed map (teleports with a destination that
             is no tile, in another map's coordinates, or none at all; README "Map fixes" lists them).
  hub        hunt_teleports_config.lua `hall.fill`: every tile of the box that the map does not have becomes deep
             water, the shore tiles next to the new water get the water border pieces of their sides, and a tile of the
             box without a ground (walls on nothing) gets the ground most of its four neighbours have. The tiles of
             the earlier quest hall over the pond (hall.quests.previous) belong to install_content_areas.py: a missing
             one gets its plain `fill` water, the others are left alone.
  temples    data/scripts/chaos/temple_portals_config.lua: the portal gallery at the main town's temple (where the
             NPC arcade of 2026-10-21 stood; the run turns it into the gallery). The tiles of each wing's portal row
             and its three carpet rows are rewritten whole (marble floor, protection zone): a portal tile bare (the
             portal is put there at startup), a marble pillar between two portal tiles, a coal basin on the outer
             end, the red carpet's pieces on the walk; the street lamps of `lamps` are added. A tile of the gallery
             that holds anything with an action id, a unique id or a destination, or is a house tile, refuses the run
             (nothing written): the portals themselves are never on the map file.
The map tiles are read and written with install_content_areas.py's helpers (tile_ranges, hall_order.parse_tile,
write_map): a tile we cannot write back unchanged (contents, an unknown attribute) is left alone and listed (a
teleport row, a shore tile) or refuses the run (the gallery). The map goes through <map>.otbm.tmp, its tile count is
checked, and <map>.otbm.bak is written first when missing. A second run changes nothing. --dry-run lists what would
change and writes nothing; --out writes the new map there instead. Exit 0 on success, 1 on a refusal.
Python 3 and numpy (tools/map/otbm.py, itemdb.py). Test: tools/patch_map_fixes_test.py (synthetic map).
"""
import csv, os, shutil, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import hall_order as H  # noqa: E402

FIXES = os.path.join(HERE, 'teleport_fixes.csv')
HUNT_CONFIG = IC.CONFIG
TEMPLE_CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'temple_portals_config.lua')
PARTS = ('teleports', 'hub', 'temples')
TF_PZ = 1
DIRS = {'n': (0, -1), 'e': (1, 0), 's': (0, 1), 'w': (-1, 0), 'nw': (-1, -1), 'ne': (1, -1), 'sw': (-1, 1), 'se': (1, 1)}


class FixError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ inputs
def read_fixes(path=FIXES):
    rows = csv.DictReader(line for line in open(path, encoding='utf-8') if not line.startswith('#'))
    out = []
    for r in rows:
        to = (int(r['to_x']), int(r['to_y']), int(r['to_z'])) if r.get('to_x') else None
        if r['action'] not in ('dest', 'remove', 'nodest') or (r['action'] == 'dest') != (to is not None):
            raise FixError('teleport_fixes.csv: bad row %s' % dict(r))
        out.append(dict(pos=(int(r['x']), int(r['y']), int(r['z'])), item=int(r['item']), action=r['action'], to=to))
    return out


class Kinds:
    """what the fixes need to know of an item: a ground (items.otb group 1), blocking (flag block solid)"""

    def __init__(self, grounds, solid):
        self.grounds, self.solid = set(grounds), set(solid)

    @classmethod
    def from_otb(cls, data_dir):
        import numpy as np
        from itemdb import ItemDB
        otb = os.path.join(data_dir, 'items', 'items.otb')
        if not os.path.isfile(otb):
            raise FixError('no %s' % otb)
        db = ItemDB(otb)
        return cls((int(i) for i in np.flatnonzero(db.group == 1)), (int(i) for i in np.flatnonzero(db.flags & 1)))


class Tiles:
    """the map's tiles as the fixes see them: stacks from otbm.py (World) for reading, parsed tile nodes (hall_order
    .parse_tile) for the ones a part changes; new tiles where the map has none"""

    def __init__(self, world, map_path):
        self.world, self.map_path = world, map_path
        self.parsed, self.bad, self.changed, self.new = {}, {}, {}, {}

    def load(self, positions):
        todo = sorted({tuple(p) for p in positions if self.world.has(tuple(p))} - set(self.parsed) - set(self.bad))
        if not todo:
            return
        data = open(self.map_path, 'rb').read()
        houses = set()
        ranges = IC.tile_ranges(data, todo, houses=houses)
        for p in houses:
            self.bad[p] = 'a house tile'
        for p in todo:
            if p in houses:
                continue
            s, e = ranges[p]
            try:
                self.parsed[p] = H.parse_tile(data[s:e + 1], p)
            except H.HallError as ex:
                self.bad[p] = str(ex)

    def get(self, p):
        p = tuple(p)
        if p in self.new:
            return self.new[p]
        if p in self.changed:
            return self.changed[p]
        return self.parsed.get(p)

    def set(self, p, tile):
        p = tuple(p)
        if p in self.new or not self.world.has(p):
            self.new[p] = tile
        elif tile != self.parsed.get(p):
            self.changed[p] = tile
        else:
            self.changed.pop(p, None)

    def stack(self, p):
        """the ids on a tile now (ground first), None without a tile"""
        t = self.get(p)
        if t is not None:
            return IC.stack_of(t)
        return self.world.stack(tuple(p))


def ground_of(tile, kinds):
    """the tile's ground id (inline, or its first item when that is a ground), or None"""
    if tile.get('ground'):
        return tile['ground']
    if tile['items'] and tile['items'][0][0] in kinds.grounds:
        return tile['items'][0][0]
    return None


def stack_ground(st, kinds):
    return st[0] if st and st[0] in kinds.grounds else None


# ------------------------------------------------------------------------------------------------ teleports
def plan_teleports(tiles, fixes, kinds, log):
    """apply the rows to the parsed tiles; returns the rows done"""
    tiles.load([f['pos'] for f in fixes])
    done = []
    for f in fixes:
        p, iid = f['pos'], f['item']
        if p in tiles.bad:
            log('teleport %d at %d,%d,%d: %s; left alone' % ((iid,) + p + (tiles.bad[p],)))
            continue
        t = tiles.get(p)
        if t is None:
            log('teleport %d at %d,%d,%d: no tile; left alone' % ((iid,) + p))
            continue
        items = list(t['items'])
        k = next((i for i, (j, _a) in enumerate(items) if j == iid), None)
        if k is None:
            continue  # gone already (a second run) or not on this map
        a = dict(items[k][1])
        if f['action'] == 'dest':
            to = f['to']
            st = tiles.stack(to)
            if not st or stack_ground(st, kinds) is None or any(i in kinds.solid for i in st):
                raise FixError('teleport %d at %d,%d,%d: the new destination %d,%d,%d is not a free tile'
                               % ((iid,) + p + to))
            if tuple(a.get('tele') or ()) == to:
                continue
            a['tele'] = to
            items[k] = (iid, a)
            what = 'leads to %d,%d,%d' % to
        elif f['action'] == 'nodest':
            if 'tele' not in a:
                continue
            a.pop('tele')
            items[k] = (iid, a)
            what = 'destination taken off'
        else:
            d = tuple(a.get('tele') or (0, 0, 0))
            leads = d != (0, 0, 0) and tiles.stack(d) is not None  # a destination that is a tile of the map
            if a.get('aid') or a.get('uid') or leads:
                log('teleport %d at %d,%d,%d has an action id, a unique id or a destination now; not removed' % ((iid,) + p))
                continue
            del items[k]
            what = 'removed'
        tiles.set(p, dict(t, items=items))
        done.append((f, what))
    return done


# ------------------------------------------------------------------------------------------------ hub
def box_positions(fill):
    z = fill['z']
    return [(x, y, z) for y in range(fill['y'][0], fill['y'][1] + 1) for x in range(fill['x'][0], fill['x'][1] + 1)]


def water_at(fill, p):
    w = fill['water']
    return w[(p[0] * 7 + p[1] * 13) % len(w)]


def border_pieces(water_dirs, borders):
    """the border pieces of a shore tile with water on these sides (n, e, s, w, nw, ne, sw, se)"""
    w = set(water_dirs)
    out = []
    sides = {d for d in ('n', 'e', 's', 'w') if d in w}
    covered = set()
    for a, b in (('n', 'w'), ('n', 'e'), ('s', 'w'), ('s', 'e')):
        if a in sides and b in sides:
            out.append(borders['d' + a + b])
            covered |= {a, b}
    for d in ('n', 'e', 's', 'w'):
        if d in sides and d not in covered:
            out.append(borders[d])
    for c in ('nw', 'ne', 'sw', 'se'):
        if c in w and c[0] not in sides and c[1] not in sides:
            out.append(borders['c' + c])
    return out


def previous_hall(cfg):
    """(tiles, fill id) of the quest hall of 2026-10-18 over the pond (hall.quests.previous): install_content_areas.py
    owns them (each as the map's backup has it, else its `fill` water, plain), so the hub fill gives them that water
    and puts no border or ground on them; a second install then changes nothing"""
    import hall_quests as Q
    qcfg = (cfg.get('hall') or {}).get('quests')
    rows = H.read_csv()
    if not qcfg or not qcfg.get('previous') or not rows:
        return set(), None
    qrows = H.quests_of(rows)
    if not qrows:
        return set(), None
    return set(Q.layout(qcfg, cfg['room'], qrows)['prev']), qcfg['previous'].get('fill')


def plan_hub(tiles, fill, kinds, log, keep=frozenset(), keep_fill=None):
    """the new water tiles, the borders of their shore, the ground under groundless tiles; returns counts. keep: tiles
    another step owns (the earlier quest hall): water `keep_fill` when missing, else left alone"""
    box = box_positions(fill)
    void = [p for p in box if not tiles.world.has(p)]
    water = set(fill['water'])
    border_ids = set(fill['borders'].values())
    shore = set(fill.get('shore') or ())
    for p in void:
        g = keep_fill if (p in keep and keep_fill) else water_at(fill, p)
        tiles.set(p, dict(flags=0, ground=g, items=[]))
    newset = set(void)
    # groundless tiles of the box (walls standing on nothing)
    groundless = []
    for p in box:
        if p in newset or p in keep:
            continue
        st = tiles.world.stack(p)
        if st is not None and stack_ground(st, kinds) is None:
            groundless.append(p)
    # shore tiles next to the new water
    near = set()
    for (x, y, z) in void:
        for dx, dy in DIRS.values():
            q = (x + dx, y + dy, z)
            if q not in newset and q not in keep and tiles.world.has(q):
                near.add(q)
    tiles.load(groundless + sorted(near))
    grounded = 0
    for p in groundless:
        if p in tiles.bad:
            log('hub: no ground at %d,%d,%d: %s; left alone' % (p + (tiles.bad[p],)))
            continue
        votes = Counter()
        for dx, dy in (DIRS['n'], DIRS['e'], DIRS['s'], DIRS['w']):
            st = tiles.stack((p[0] + dx, p[1] + dy, p[2]))
            g = stack_ground(st, kinds) if st else None
            if g is not None:
                votes[g] += 1
        if not votes:
            log('hub: no ground at %d,%d,%d and none beside it; left alone' % p)
            continue
        g = sorted(votes.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
        t = tiles.get(p)
        tiles.set(p, dict(t, ground=g))
        grounded += 1
    shored = 0
    for q in sorted(near):
        if q in tiles.bad:
            log('hub: shore tile %d,%d,%d: %s; no border' % (q + (tiles.bad[q],)))
            continue
        t = tiles.get(q)
        g = ground_of(t, kinds)
        if g is None or g not in shore:
            continue
        wet = []
        for d, (dx, dy) in DIRS.items():
            r = (q[0] + dx, q[1] + dy, q[2])
            st = tiles.stack(r)
            if r in newset or (st and st[0] in water):
                wet.append(d)
        pieces = border_pieces(wet, fill['borders'])
        items = [(i, a) for i, a in t['items'] if i not in border_ids]
        at = 0 if t.get('ground') else 1
        items[at:at] = [(i, {}) for i in pieces]
        new = dict(t, items=items)
        if new != t:
            tiles.set(q, new)
            shored += 1
    return dict(water=len(void), grounded=grounded, shore=shored)


# ------------------------------------------------------------------------------------------------ temples
def gallery_tiles(town, items):
    """{pos: tile} of a town's portal gallery (temple_portals_config.lua): the whole portal row and carpet rows of each
    wing, and the lamps to add ({pos: item id})"""
    z = town['z']
    portals = {p['x'] for p in town['portals']}
    floor, car = items['floor'], items['carpet']
    out = {}
    for w in town['wings']:
        a, b = w['from'], w['to']
        for x in range(a, b + 1):
            if x in portals:
                top = []
            elif x == w['outer']:
                top = [items['light']]
            else:
                top = [items['pillar']]
            out[(x, town['portalRow'], z)] = top
            rows = town['aisle']
            for k, y in enumerate(rows):
                ns = 'n' if k == 0 else ('s' if k == len(rows) - 1 else '')
                ew = 'w' if x == a else ('e' if x == b else '')
                key = (ns + ew) or (ns or ew or 'c')
                out[(x, y, z)] = [car[key]]
    tiles = {p: dict(flags=TF_PZ, ground=floor, items=[(i, {}) for i in top]) for p, top in out.items()}
    lamps = {(l['x'], l['y'], z): items['lamp'] for l in town.get('lamps') or ()}
    return tiles, lamps


def plan_temples(tiles, tcfg, log):
    if not tcfg.get('enabled'):
        return dict(tiles=0, lamps=0)
    count, lamps_added = 0, 0
    for town in tcfg.get('towns') or ():
        want, lamps = gallery_tiles(town, tcfg['items'])
        tiles.load(list(want) + list(lamps))
        for p in sorted(want):
            if p in tiles.bad:
                raise FixError('%s gallery: the tile %d,%d,%d is %s' % ((town['name'],) + p + (tiles.bad[p],)))
            t = tiles.get(p)
            if t is None:
                raise FixError('%s gallery: no tile at %d,%d,%d' % ((town['name'],) + p))
            for iid, a in t['items']:
                if a.get('aid') or a.get('uid') or a.get('tele'):
                    raise FixError('%s gallery: item %d at %d,%d,%d has an action id, unique id or destination'
                                   % ((town['name'], iid) + p))
            if t != want[p]:
                tiles.set(p, want[p])
                count += 1
        for p, iid in sorted(lamps.items()):
            if p in tiles.bad or tiles.get(p) is None:
                log('%s gallery: no lamp at %d,%d,%d (%s)' % ((town['name'],) + p + (tiles.bad.get(p, 'no tile'),)))
                continue
            t = tiles.get(p)
            if not any(i == iid for i, _a in t['items']):
                tiles.set(p, dict(t, items=list(t['items']) + [(iid, {})]))
                lamps_added += 1
        log('%s gallery: %d portal tile(s), %d tile(s) to rewrite, %d lamp(s) to add'
            % (town['name'], len(town['portals']), count, lamps_added))
    return dict(tiles=count, lamps=lamps_added)


# ------------------------------------------------------------------------------------------------ run
def run(data_dir, dry=False, map_path=None, out=None, only=PARTS, fixes_path=FIXES, hunt_config=HUNT_CONFIG,
        temple_config=TEMPLE_CONFIG, kinds=None, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise FixError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise FixError('the world map is compressed; unpack it first')
    kinds = kinds or Kinds.from_otb(data_dir)
    import otbm
    world = IC.World(otbm.load_otbm(map_path))
    tiles = Tiles(world, map_path)
    summary = {}
    if 'teleports' in only:
        done = plan_teleports(tiles, read_fixes(fixes_path), kinds, log)
        for f, what in done:
            log('teleport %d at %d,%d,%d: %s' % ((f['item'],) + f['pos'] + (what,)))
        summary['teleports'] = len(done)
    if 'hub' in only:
        hcfg = IC.load_config(hunt_config)
        fill = (hcfg.get('hall') or {}).get('fill')
        keep, keep_fill = previous_hall(hcfg) if fill else (set(), None)
        summary['hub'] = plan_hub(tiles, fill, kinds, log, keep, keep_fill) if fill else {}
        log('hub: %s' % summary['hub'])
    if 'temples' in only:
        summary['temples'] = plan_temples(tiles, IC.load_config(temple_config), log)
    changed = dict(tiles.changed)
    added = dict(tiles.new)
    summary['changed'], summary['added'] = len(changed), len(added)
    if not changed and not added:
        log('map fixes: nothing to do')
        return summary
    log('map fixes: %d tile(s) to rewrite, %d to add' % (len(changed), len(added)))
    if dry and not out:
        return summary
    target = out or map_path
    tmp = target + '.tmp'
    new_tiles = dict(changed)
    new_tiles.update(added)
    IC.write_map(map_path, tmp, list(changed), new_tiles)
    m2 = otbm.load_otbm(tmp)
    if len(m2.tiles['x']) != world.count() + len(added):
        os.remove(tmp)
        raise FixError('internal: the new map has %d tiles, not %d; nothing written'
                       % (len(m2.tiles['x']), world.count() + len(added)))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('map fixes: written to %s' % target)
    return summary


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            opts[a] = True
        elif a in ('--map', '--out', '--only'):
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
    only = tuple(opts['--only'].split(',')) if '--only' in opts else PARTS
    if any(o not in PARTS for o in only):
        print('--only takes %s' % ','.join(PARTS))
        return 1
    try:
        run(pos[0], dry=opts.get('--dry-run', False), map_path=opts.get('--map'), out=opts.get('--out'), only=only)
    except (FixError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
