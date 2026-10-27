#!/usr/bin/env python3
"""Clean roofs for the Bone Warrior / Bone Mage hunt next to the Astro tower (server/README.md "Hunt roofs"), idempotent.

usage: python3 -I server/tools/patch_hunt_roofs.py DATA_DIR [--dry-run] [--map FILE] [--out FILE]

Owner 2026-10-27 ("Trocar por telhado bonito"): in the hunt of Bone Slicer, Bone Warrior and Bone Mage (hunt marks
31583,33009,7 and 31566,33004,8 of chaos_poi.lua) the base map's roofs look wrong: red tile fill with 2x2 wooden-frame
gables, "stone ledge" spikes along the edges, oriel windows, edge pieces stacked on them. DATA_DIR is the server's data
folder (world/<map>.otbm, items/items.otb). Install step `huntroofs`, after `astrodoor`.

The roofs are on floors 5 and 6 over the cabins of floor 7, inside the box BOX (x 31575-31607, y 32996-33029; the cave
only: the farm roofs south of it, y 33031 and more, and every other building of the map keep their pieces). The old pieces
(server id / client id) and what they become:
  9535, 9536   red tile fill (a ground)      stays under the roof: it is what hides the roof when a player is under it;
                                             the new interior piece (1 of 3 by position) covers it
  9537-9544    edge pieces NW N NE SW S SE W E   the new piece of the same side: nw n ne sw s se w e
  9545-9548    inner corner pieces           the interior piece (the staircase edge along the cave wall stays smooth)
  9092-9099    red tile roof with wooden frame (2x2)   gone
  9100, 9101   stone ledge (the grey spikes)         gone
  9102, 9103   oriel window                          gone
The new pieces are the "rusty tin" roof of the pair 33 kit (client ids 38477-38487, server ids +3000 = 41477-41487,
installed by install step `pack33items`; flat brown-grey tin, a thin shaded edge): interior 41477-41479, n 41480, s 41481,
e 41482, w 41483, nw 41484, ne 41485, sw 41486, se 41487. The kit art is drawn one tile up and left of the tile it stands
on (a 64x64 picture whose tile is its bottom right quarter, art in the top left), so each new piece stands one tile down
and right of the old piece it replaces (x + 1, y + 1, same floor): the roof then covers the same spot on screen as
before. A tile left without ground and items goes; a tile the roof needs and the map has not is added (no ground).
A tile we cannot write back unchanged (a house tile, a container, an unknown attribute) is left alone and listed.
The map goes through <map>.otbm.tmp, its tile count is checked, and <map>.otbm.bak is written first when missing.
A second run changes nothing (a tile that already holds the piece wanted from its old one is left alone). --dry-run
lists what would change and writes nothing; --out writes the new map there. Exit 0 on success, 1 on a refusal.
Python 3 and numpy (tools/map/otbm.py, itemdb.py). Test: tools/patch_hunt_roofs_test.py (synthetic map).
"""
import os, shutil, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import patch_map_fixes as PM  # noqa: E402

BOX = dict(x=(31575, 31607), y=(32996, 33029), z=(5, 6))
SHIFT = (1, 1)  # the kit art hangs one tile up and left of its tile: the new piece stands one tile down and right

FILL = (9535, 9536)
EDGES = {9537: 'nw', 9538: 'n', 9539: 'ne', 9540: 'sw', 9541: 's', 9542: 'se', 9543: 'w', 9544: 'e'}
INNER = (9545, 9546, 9547, 9548)
GONE = tuple(range(9092, 9104))  # frames 9092-9099, ledges 9100-9101, oriel windows 9102-9103
OLD = set(EDGES) | set(INNER) | set(GONE)  # removed from a tile (the fill ground stays)

# rusty tin roof of the pair 33 kit, server ids (client id + 3000)
INTERIOR = (41477, 41478, 41479)
PIECE = {'n': 41480, 's': 41481, 'e': 41482, 'w': 41483, 'nw': 41484, 'ne': 41485, 'sw': 41486, 'se': 41487}
NEW = set(INTERIOR) | set(PIECE.values())


class RoofError(Exception):
    pass


def box_positions(box=BOX):
    return [(x, y, z) for z in range(box['z'][0], box['z'][1] + 1)
            for y in range(box['y'][0], box['y'][1] + 1) for x in range(box['x'][0], box['x'][1] + 1)]


def role_of(stack):
    """the roof role of an old tile (a stack of ids): an edge side 'nw'.. 'e', 'c' (fill or inner corner), None"""
    for i in stack:
        if i in EDGES:
            return EDGES[i]
    if any(i in INNER or i in FILL for i in stack):
        return 'c'
    return None


def piece_for(role, q):
    """the new piece of a role standing on tile q"""
    if role == 'c':
        return INTERIOR[(q[0] * 7 + q[1] * 13 + q[2]) % len(INTERIOR)]
    return PIECE[role]


def plan(world, tiles, log, box=BOX):
    """the roof tiles of the box -> final tile dicts of the tiles that change: ({pos: tile}, {pos: tile} new, set deleted,
    Counter of pieces). Reads old stacks from the world, rewrites parsed tiles (PM.Tiles)"""
    roofs = {}
    for p in box_positions(box):
        st = world.stack(p)
        if st and (any(i in OLD for i in st) or any(i in FILL for i in st)):
            roofs[p] = st
    want = {}  # q -> (piece, from p)
    for p, st in sorted(roofs.items()):
        role = role_of(st)
        if role is not None:
            q = (p[0] + SHIFT[0], p[1] + SHIFT[1], p[2])
            want[q] = (piece_for(role, q), p, role)
    touch = {p for p, st in roofs.items() if any(i in OLD for i in st)} | set(want)
    tiles.load(touch)
    skipped = Counter()
    cur = {}  # pos -> tile as it will be
    for p in sorted(touch):
        if p in tiles.bad:
            skipped[tiles.bad[p]] += 1
            continue
        t = tiles.get(p)
        cur[p] = t if t is not None else dict(flags=0, ground=None, items=[])
    pieces = Counter()
    final = {}
    for p, t in cur.items():
        ground = t['ground']
        items = [(i, a) for i, a in t['items'] if i not in OLD]
        if ground in OLD:
            ground = None  # never happens (no old piece is a ground but the fill)
        final[p] = dict(t, ground=ground, items=items)
    for q, (piece, p, role) in sorted(want.items()):
        if q not in final:
            skipped['no tile for the piece of %d,%d,%d' % p] += 1
            continue
        if any(i == piece for i, _a in final[q]['items']):
            continue  # already there (a second run)
        final[q]['items'].append((piece, {}))
        pieces[role] += 1
    changed, added, deleted = {}, {}, set()
    for p, t in sorted(final.items()):
        old = tiles.get(p)
        if old is None:
            if t['ground'] or t['items']:
                added[p] = t
            continue
        if t['ground'] is None and not t['items'] and not t['flags']:
            deleted.add(p)
        elif t != old:
            changed[p] = t
    for why, n in sorted(skipped.items()):
        log('hunt roofs: left alone x %d: %s' % (n, why))
    return changed, added, deleted, pieces, len(roofs)


def run(data_dir, dry=False, map_path=None, out=None, known=None, box=BOX, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise RoofError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise RoofError('the world map is compressed; unpack it first')
    if known is None:
        otb = os.path.join(data_dir, 'items', 'items.otb')
        if not os.path.isfile(otb):
            raise RoofError('no %s' % otb)
        from itemdb import ItemDB
        db = ItemDB(otb)
        known = {i for i in NEW if i < len(db.cid) and int(db.cid[i])}
    missing = sorted(NEW - set(known))
    if missing:
        raise RoofError('the roof items %s are not in items.otb: run install step pack33items first' % missing)
    import otbm
    world = IC.World(otbm.load_otbm(map_path))
    tiles = PM.Tiles(world, map_path)
    changed, added, deleted, pieces, n_old = plan(world, tiles, log, box)
    summary = dict(roofs=n_old, pieces=sum(pieces.values()), changed=len(changed), added=len(added), deleted=len(deleted))
    if not (changed or added or deleted):
        log('hunt roofs: nothing to do')
        return summary
    log('hunt roofs: %d old roof tile(s), %d new piece(s) (%s); %d tile(s) to rewrite, %d to add, %d to remove'
        % (n_old, sum(pieces.values()), ', '.join('%s %d' % kv for kv in sorted(pieces.items())), len(changed),
           len(added), len(deleted)))
    if dry and not out:
        return summary
    target = out or map_path
    tmp = target + '.tmp'
    new_tiles = dict(changed)
    new_tiles.update(added)
    IC.write_map(map_path, tmp, list(changed) + sorted(deleted), new_tiles)
    m2 = otbm.load_otbm(tmp)
    want_count = world.count() + len(added) - len(deleted)
    if len(m2.tiles['x']) != want_count:
        os.remove(tmp)
        raise RoofError('internal: the new map has %d tiles, not %d; nothing written' % (len(m2.tiles['x']), want_count))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('hunt roofs: written to %s' % target)
    return summary


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
    except (RoofError, PM.FixError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
