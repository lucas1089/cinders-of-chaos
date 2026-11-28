#!/usr/bin/env python3
"""Put the animated decor flames of pair 74 on the world map (server/README.md "Decor flames on the map (O788)"), idempotent.

usage: python3 -I server/tools/patch_decor_flames_map.py DATA_DIR [--dry-run] [--map FILE] [--out FILE] [--rows FILE]

Owner, 2026-11-28, on where the flames go: "Pode escolher". tools/decor_flames_map.csv lists each spot (x, y, z, item, action,
old, on, why): the flame brazier 48560 (2x2, solid), the flame campfire 48561 (2x2), the flame candle 48562 and the flame
cold spirit 48563 (1x1) of install_decor_flames.py (step `decorflames`). Two actions:
  swap  the stock item `old` on the tile (a still coal basin, candelabrum or candlestick) becomes the flame, in its place in
        the stack; an `old` with an action id, unique id or any other attribute is refused;
  add   the flame goes on top of the tile, whose top item now must be `on` (its floor, or the altar or table it stands on).
The tool refuses the whole run (nothing written) when a tile is not what the row expects: no tile, a house tile, a tile it
cannot write back unchanged, `old` or `on` missing, a door, a teleport or a floor change on the tile, a spawn centre or a
creature's place of the spawn file, a blocking item on a floor spot, a 2x2 flame whose west, north and north-west tiles
(the picture reaches over them) are not plain free floor, or a floor spot that would cut the walk: the walkable neighbours
of the tile must stay joined through the 7 x 7 tiles around it with every listed flame in the way. A tile that holds its
flame already is left as it is, so a second run changes nothing.
DATA_DIR is the server's data folder (world/<map>.otbm, items/items.otb, items/items.xml). Install step `decorflamesmap`,
after `questshowcase`. Client pair guard: like `decorflames` it waits for config.lua chaosClientPair >= 74
(client_pair.PAIR_DECOR): below it a WARNING line and nothing read or written. The map goes through <map>.otbm.tmp and the
map write guard (map_write_guard.py, README "Map write guard (O512)": only the listed tiles may differ), its tile count is
checked, <map>.otbm.bak is written first when missing. --dry-run lists and writes nothing; --out writes the new map there.
Exit 0 on success, 1 on a refusal.
Python 3 and numpy (tools/map/otbm.py). Test: tools/patch_decor_flames_map_test.py (synthetic map).
"""
import csv, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import patch_map_fixes as PM  # noqa: E402

ROWS = os.path.join(HERE, 'decor_flames_map.csv')
BRAZIER, CAMPFIRE, CANDLE, SPIRIT = 48560, 48561, 48562, 48563
FLAMES = {BRAZIER: 'flame brazier', CAMPFIRE: 'flame campfire', CANDLE: 'flame candle', SPIRIT: 'flame cold spirit'}
LARGE = {BRAZIER, CAMPFIRE}          # 2x2: the picture stands on the tile and reaches over its west, north and north-west
SOLID = {BRAZIER}
REACH = ((-1, 0), (0, -1), (-1, -1))
BOX = 3                              # the walk check looks at the 7 x 7 tiles around a spot
STEPS4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


class FlameError(Exception):
    pass


class Kinds:
    """what the rows need to know of an item: grounds (otb group 1), blocking (flag block solid), and the ids a flame never
    shares a tile with or reaches over: doors, teleports, floor changes (stairs, ladders, holes)"""

    def __init__(self, grounds, solid, banned):
        self.grounds, self.solid, self.banned = set(grounds), set(solid), set(banned)

    @classmethod
    def from_data(cls, data_dir):
        import numpy as np
        from itemdb import ItemDB, C
        otb = os.path.join(data_dir, 'items', 'items.otb')
        xml = os.path.join(data_dir, 'items', 'items.xml')
        if not os.path.isfile(otb):
            raise FlameError('no %s' % otb)
        db = ItemDB(otb, xml if os.path.isfile(xml) else None)
        banned = set(int(i) for i in np.flatnonzero((db.group == 7) | (db.cls == C['door']) | (db.cls == C['floorchg'])))
        _g, tele = IC.item_kinds(data_dir, log=lambda s: None)
        banned |= set(tele)
        return cls((int(i) for i in np.flatnonzero(db.group == 1)), (int(i) for i in np.flatnonzero(db.flags & 1)), banned)


def read_rows(path=ROWS):
    """[dict(pos, item, action, old, on, why)] of tools/decor_flames_map.csv (lines starting with # are notes)"""
    out, seen = [], set()
    with open(path, encoding='utf-8') as f:
        for r in csv.DictReader(line for line in f if not line.startswith('#')):
            try:
                pos = (int(r['x']), int(r['y']), int(r['z']))
                item = int(r['item'])
                old = int(r['old']) if r['old'].strip() else None
                on = int(r['on']) if r['on'].strip() else None
            except (KeyError, ValueError):
                raise FlameError('decor_flames_map.csv: bad row %s' % dict(r))
            act = r['action'].strip()
            if item not in FLAMES:
                raise FlameError('decor_flames_map.csv: %s: item %d is not a decor flame' % (pos, item))
            if act not in ('swap', 'add') or (act == 'swap') != (old is not None) or (act == 'add') != (on is not None):
                raise FlameError('decor_flames_map.csv: %s: a swap names old, an add names on' % (pos,))
            if pos in seen:
                raise FlameError('decor_flames_map.csv: %s is named twice' % (pos,))
            if not r.get('why', '').strip():
                raise FlameError('decor_flames_map.csv: %s: say why' % (pos,))
            seen.add(pos)
            out.append(dict(pos=pos, item=item, action=act, old=old, on=on, why=r['why'].strip()))
    return out


def spawn_spots(data_dir, map_path):
    """{(x, y, z)} of the spawn file: every spawn centre and every creature's place (monsters and NPCs)"""
    import xml.etree.ElementTree as ET
    base = os.path.splitext(os.path.basename(map_path))[0]
    path = os.path.join(os.path.dirname(map_path), base + '-spawn.xml')
    if not os.path.isfile(path):
        return set()
    out = set()
    for sp in ET.parse(path).getroot().iter('spawn'):
        try:
            cx, cy, cz = int(sp.get('centerx')), int(sp.get('centery')), int(sp.get('centerz'))
        except (TypeError, ValueError):
            continue
        out.add((cx, cy, cz))
        for c in sp:
            try:
                out.add((cx + int(c.get('x')), cy + int(c.get('y')), int(c.get('z', cz))))
            except (TypeError, ValueError):
                pass
    return out


def walkable(stack, kinds):
    return bool(stack) and stack[0] in kinds.grounds and not any(i in kinds.solid for i in stack)


def free_floor(world, p, kinds):
    """why the tile is not plain free floor for a flame to stand on or reach over, or None"""
    st = world.stack(p)
    if st is None:
        return 'no tile'
    if world.house(p):
        return 'a house tile'
    if not st or st[0] not in kinds.grounds:
        return 'no ground'
    if any(i in kinds.banned for i in st):
        return 'a door, teleport or floor change'
    if any(i in kinds.solid for i in st):
        return 'a blocking item'
    return None


def walk_cut(world, p, kinds, blocked):
    """why a flame on floor tile p cuts the walk, or None: its walkable neighbours stay joined around it"""
    x0, y0, z = p
    box = {(x0 + dx, y0 + dy, z) for dx in range(-BOX, BOX + 1) for dy in range(-BOX, BOX + 1)}
    ok = {q for q in box if q not in blocked and walkable(world.stack(q) or [], kinds)}
    ends = [(x0 + dx, y0 + dy, z) for dx, dy in STEPS4 if (x0 + dx, y0 + dy, z) in ok]
    if len(ends) < 2:
        return None if ends else 'no walkable neighbour'
    seen, todo = {ends[0]}, [ends[0]]
    while todo:
        x, y, _z = todo.pop()
        for dx, dy in STEPS4:
            q = (x + dx, y + dy, z)
            if q in ok and q not in seen:
                seen.add(q)
                todo.append(q)
    lost = [q for q in ends if q not in seen]
    return ('the way past it is cut (%d,%d,%d)' % lost[0]) if lost else None


def check_row(world, kinds, spots, row, blocked):
    """why the row cannot go on the map as it is now (None when it can, 'kept' when its flame is there already)"""
    p, item = row['pos'], row['item']
    st = world.stack(p)
    if st is None:
        return 'no tile'
    if world.house(p):
        return 'a house tile'
    if item in st and (row['action'] == 'add' or row['old'] not in st):
        return 'kept'
    if p in spots:
        return 'a spawn centre or a creature\'s place'
    if any(i in kinds.banned for i in st):
        return 'a door, teleport or floor change on the tile'
    if not st or st[0] not in kinds.grounds:
        return 'no ground'
    if row['action'] == 'swap':
        if st.count(row['old']) != 1:
            return 'the tile holds %d of %d, not one' % (st.count(row['old']), row['old'])
    else:
        if st[-1] != row['on']:
            return 'its top item is %d, not %d' % (st[-1], row['on'])
        if item in LARGE and any(i in kinds.solid for i in st):
            return 'a blocking item under a 2x2 flame'
    floor = walkable(st, kinds)      # the tile is walked on now: the flame must not cut the way
    if item in LARGE:
        for dx, dy in REACH:
            q = (p[0] + dx, p[1] + dy, p[2])
            why = free_floor(world, q, kinds)
            if why:
                return 'the picture reaches over %d,%d,%d: %s' % (q + (why,))
    if floor:
        return walk_cut(world, p, kinds, blocked)
    return None


def plan(tiles, world, rows, kinds, spots, log):
    """put the flames on the parsed tiles; returns dict(done, kept); raises FlameError naming every refused row"""
    res = dict(done=0, kept=0)
    tiles.load([r['pos'] for r in rows])
    blocked = {r['pos'] for r in rows}
    bad = []
    for r in rows:
        p = r['pos']
        why = check_row(world, kinds, spots, r, blocked)
        if why == 'kept':
            res['kept'] += 1
            continue
        if why is None and p in tiles.bad:
            why = tiles.bad[p]
        if why is None:
            t = tiles.get(p)
            if r['action'] == 'swap':
                items = list(t['items'])
                k = [j for j, (i, _a) in enumerate(items) if i == r['old']]
                if len(k) != 1 or items[k[0]][1]:
                    why = 'the %d on the tile carries attributes (or is the ground)' % r['old']
                else:
                    items[k[0]] = (r['item'], {})
                    tiles.set(p, dict(t, items=items))
            else:
                tiles.set(p, dict(t, items=list(t['items']) + [(r['item'], {})]))
        if why:
            bad.append('%d,%d,%d %s: %s' % (p + (FLAMES[r['item']], why)))
            continue
        res['done'] += 1
        log('%d,%d,%d: %s (%s) - %s' % (p + (FLAMES[r['item']], r['action'], r['why'])))
    if bad:
        raise FlameError('%d spot(s) are not what the rows expect; nothing written: %s' % (len(bad), '; '.join(bad)))
    return res


def run(data_dir, dry=False, map_path=None, out=None, rows_path=ROWS, kinds=None, log=print, pair_check=True):
    if pair_check:
        import client_pair
        ok, why = client_pair.allows(data_dir, client_pair.PAIR_DECOR, 'decorflamesmap')
        log(why)
        if not ok:
            return dict(done=0, kept=0, skipped=True)
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise FlameError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise FlameError('the world map is compressed; unpack it first')
    if kinds is None:
        kinds = Kinds.from_data(data_dir)
    rows = read_rows(rows_path)
    import otbm
    m = otbm.load_otbm(map_path)
    world = IC.World(m)
    tiles = PM.Tiles(world, map_path)
    res = plan(tiles, world, rows, kinds, spawn_spots(data_dir, map_path), log)
    log('decor flames on the map: %d placed, %d there already (%d rows)' % (res['done'], res['kept'], len(rows)))
    changed = dict(tiles.changed)
    if not changed:
        log('decor flames on the map: nothing to do')
        return res
    if dry and not out:
        log('dry run: nothing written')
        return res
    target = out or map_path
    tmp = target + '.tmp'
    IC.write_map(map_path, tmp, list(changed), dict(changed), log=log)
    m2 = otbm.load_otbm(tmp)
    if len(m2.tiles['x']) != world.count():
        os.remove(tmp)
        raise FlameError('internal: the new map has %d tiles, not %d; nothing written' % (len(m2.tiles['x']), world.count()))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('decor flames on the map: written to %s' % target)
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
    except (FlameError, PM.FixError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
