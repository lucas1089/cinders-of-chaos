#!/usr/bin/env python3
"""House audit: every house of houses.xml against the map (server/README.md "House audit (O513)").

usage: python3 -I server/tools/audit_houses.py SERVER_DIR [--houses FILE] [--known FILE] [--check] [--summary] [--csv OUT]
                                               [--limit N] [--max-floors N] [--quiet]
       python3 -I server/tools/audit_houses.py --map FILE.otbm --items ITEMS.otb [--xml ITEMS.xml] --houses FILE [same options]

Read only, report only: there is no fixer (the live map's 1,057 houses are of mixed origin; docs/MAP_GUIDE.md "Map editing
rules": a house is never added, removed, resized or moved by a tool). SERVER_DIR is an installed server folder (or its data
folder): the map and the items as in audit_map_tiles.py, the house file DATA/world/<mapName>-house.xml (how
patch_base_houses.py finds it). The house tiles of the map are the tiles of OTBM house nodes (tools/map/otbm.py, `house`).
Codes, per house id (one line each: CODE house=ID "name" tiles=N first=x,y,z: what)
  MULTI_FLOOR       tiles on more than MAX_FLOORS floors (default 1: every house with an upper floor is listed; the guide
                    counts 77 % of the live houses on one floor, 10 % on two, big ones on 3-5: raise --max-floors to 2 or 5
                    to list only the odd ones)
  NO_DOOR           no door item on a tile of the house edge (a house tile with a side that is not the house)
  DOOR_UNREACHABLE  doors on the edge, but none has a walkable tile outside the house (house id 0) next to it
  ENTRY_BLOCKED     the entry of houses.xml is not a tile, or one nobody can stand on (a door on it does not block);
                    also a house on the map with no row in houses.xml
  HOUSE_FLAGS       the tiles of the house disagree on the protection zone flag (some have it, some not), or a tile has
                    the PvP zone flag (the engine makes every house tile a protection zone)
  SIZE              fewer tiles than HOUSE_MIN_TILES or more than HOUSE_MAX_TILES (a house of no tile at all too)
  ROOF_SHARE        under ROOF_MIN_SHARE of the house tiles on floors 1-7 have a tile on the floor above (the roof);
                    houses on floor 8 and below, which have no sky, are not judged
Limits (constants at the top; the numbers of docs/MAP_GUIDE.md "Towns": size median 40-60, p25 25, p75 80-90, 97-100 %
of the house tiles roofed, one door, 77 % one floor): HOUSE_MIN_TILES 13 (half of p25), HOUSE_MAX_TILES 180 (twice the top
of p75), ROOF_MIN_SHARE 0.97.
--known FILE (default server/tools/house_audit_known.csv, columns house,code,reason): findings that were looked at and left;
--check exits 1 for a finding that is not listed (a listed one that is gone is only printed). --summary prints the counts
per code and stops. --csv writes every finding (house,code,name,tiles,x,y,z,detail). Python 3 and numpy.
Test: audit_houses_test.py (synthetic map and houses.xml).
"""
import csv
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import audit_map_tiles as A  # noqa: E402

KNOWN = os.path.join(HERE, 'house_audit_known.csv')

HOUSE_MIN_TILES = 13       # MAP_GUIDE "Towns": house size p25 is 25 tiles; half of it
HOUSE_MAX_TILES = 180      # p75 is 80-90; twice the top of it (big houses and guildhalls)
ROOF_MIN_SHARE = 0.97      # MAP_GUIDE: 97-100 % of the house tiles have a roof on the floor above
MAX_FLOORS = 1
ROOF_Z = (1, 7)            # floors with a sky above
TF_PZ, TF_PVP = 1, 16      # tile flags (tools/map/otbm.py)
CODES = ('MULTI_FLOOR', 'NO_DOOR', 'DOOR_UNREACHABLE', 'ENTRY_BLOCKED', 'HOUSE_FLAGS', 'SIZE', 'ROOF_SHARE')
HOUSE_TAG = re.compile(r'<house\b[^>]*>')


class HouseAuditError(Exception):
    pass


def read_houses(path):
    """{house id: dict(name, entry (x, y, z), size)} of a houses.xml"""
    out = {}
    text = open(path, encoding='utf-8', errors='replace').read()
    for tag in HOUSE_TAG.findall(text):
        a = dict(re.findall(r'(\w+)="([^"]*)"', tag))
        if 'houseid' not in a:
            continue
        try:
            entry = (int(a.get('entryx', 0)), int(a.get('entryy', 0)), int(a.get('entryz', 0)))
        except ValueError:
            entry = (0, 0, 0)
        out[int(a['houseid'])] = dict(name=a.get('name', ''), entry=entry, size=int(a.get('size', 0) or 0))
    return out


def audit(w, houses, max_floors=MAX_FLOORS):
    """-> {house id: [(code, detail)]} and {house id: (tile count, first tile)} for every house of the file and of the map"""
    t = w.m.tiles
    hid = t['house'].astype(np.int64)
    idx = np.flatnonzero(hid > 0)
    order = np.argsort(hid[idx], kind='stable')
    idx = idx[order]
    ids, starts = np.unique(hid[idx], return_index=True)
    ends = np.append(starts[1:], len(idx))
    tiles_of = {int(i): idx[a:b] for i, a, b in zip(ids, starts, ends)}
    door_tiles = np.zeros(w.n, bool)
    dt, _d = A._special_tiles(w, w.doors)
    door_tiles[dt] = True
    X, Y, Z = (t[k].astype(np.int64) for k in ('x', 'y', 'z'))
    found, meta = {}, {}

    for h in sorted(set(tiles_of) | set(houses)):
        tl = tiles_of.get(h, np.zeros(0, np.int64))
        info = houses.get(h)
        out = found.setdefault(h, [])
        first = (int(X[tl[0]]), int(Y[tl[0]]), int(Z[tl[0]])) if len(tl) else (0, 0, 0)
        meta[h] = (len(tl), first)
        # size
        if len(tl) < HOUSE_MIN_TILES or len(tl) > HOUSE_MAX_TILES:
            out.append(('SIZE', '%d tiles (band %d-%d)' % (len(tl), HOUSE_MIN_TILES, HOUSE_MAX_TILES)))
        if len(tl):
            floors = sorted({int(z) for z in Z[tl]})
            if len(floors) > max_floors:
                out.append(('MULTI_FLOOR', 'floors %s' % ','.join(str(z) for z in floors)))
            # the edge: house tiles with a 4-neighbour that is not this house
            edge = np.zeros(len(tl), bool)
            nbr = {}
            for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                j = w.lookup(X[tl] + dx, Y[tl] + dy, Z[tl])
                nh = np.where(j >= 0, hid[np.maximum(j, 0)], -1)
                nbr[(dx, dy)] = (j, nh)
                edge |= nh != h
            doors = np.flatnonzero(edge & door_tiles[tl])
            if not len(doors):
                out.append(('NO_DOOR', 'no door on the %d edge tiles' % int(edge.sum())))
            else:
                ok = False
                for k in doors:
                    for (dx, dy), (j, nh) in nbr.items():
                        if nh[k] == 0 and j[k] >= 0 and w.walkable_stack(w.stack(int(j[k]))):
                            ok = True
                if not ok:
                    out.append(('DOOR_UNREACHABLE', '%d door(s), none with a walkable tile outside the house' % len(doors)))
            # flags
            fl = t['flags'][tl].astype(np.int64)
            pz = (fl & TF_PZ) > 0
            if pz.any() and not pz.all():
                out.append(('HOUSE_FLAGS', 'protection zone on %d of %d tiles' % (int(pz.sum()), len(tl))))
            if ((fl & TF_PVP) > 0).any():
                out.append(('HOUSE_FLAGS', 'PvP zone flag on %d tile(s)' % int(((fl & TF_PVP) > 0).sum())))
            # roof
            sky = (Z[tl] >= ROOF_Z[0]) & (Z[tl] <= ROOF_Z[1])
            if sky.any():
                up = w.lookup(X[tl][sky], Y[tl][sky], Z[tl][sky] - 1)
                roofed = np.zeros(len(up), bool)
                have = up >= 0
                roofed[have] = w.cnt[up[have]] > 0
                share = roofed.sum() / float(len(up))
                if share < ROOF_MIN_SHARE:
                    out.append(('ROOF_SHARE', '%.0f%% of %d tiles have a roof (band %.0f%%)' % (100 * share, len(up), 100 * ROOF_MIN_SHARE)))
        # entry
        if info is None:
            out.append(('ENTRY_BLOCKED', 'no row in houses.xml'))
        else:
            ex, ey, ez = info['entry']
            if not w.walk_at(ex, ey, ez):
                out.append(('ENTRY_BLOCKED', 'entry %d,%d,%d is %s' % (ex, ey, ez, 'not a tile' if w.m.find(ex, ey, ez) < 0 else 'blocked')))
    return found, meta


def read_known(path=KNOWN):
    """{(house id, code): reason}"""
    out = {}
    if path and os.path.isfile(path):
        for row in csv.DictReader(l for l in open(path, encoding='utf-8') if not l.startswith('#')):
            out[(int(row['house']), row['code'])] = row.get('reason', '')
    return out


def report(found, meta, houses, known, limit=20, summary=False, log=print):
    """prints the report; -> (new count, stale known keys)"""
    new = total = 0
    by = {c: [] for c in CODES}
    for h, rows in sorted(found.items()):
        for code, detail in rows:
            by[code].append((h, detail))
    for c in CODES:
        keys = {h for h, _d in by[c]}
        n_new = sum(1 for h in keys if (h, c) not in known)
        new += n_new
        total += len(keys)
        log('%-17s %5d  (%d known, %d new)' % (c, len(keys), len(keys) - n_new, n_new))
    log('%d houses, %d findings, %d not in the known list' % (len(found), total, new))
    if not summary:
        for c in CODES:
            for k, (h, detail) in enumerate(by[c]):
                if k >= limit:
                    log('  ... %d more %s (--csv has all of them, --limit N)' % (len(by[c]) - k, c))
                    break
                n, first = meta[h]
                name = (houses.get(h) or {}).get('name', '?')
                log('%s house=%d "%s" tiles=%d first=%d,%d,%d: %s%s' % (c, h, name, n, first[0], first[1], first[2], detail,
                                                                       ' (known)' if (h, c) in known else ''))
    have = {(h, c) for c in CODES for h, _d in by[c]}
    return new, sorted(k for k in known if k not in have)


def write_csv(path, found, meta, houses):
    with open(path, 'w', encoding='utf-8', newline='') as fh:
        wr = csv.writer(fh, lineterminator='\n')
        wr.writerow(['house', 'code', 'name', 'tiles', 'x', 'y', 'z', 'detail'])
        for h, rows in sorted(found.items()):
            n, first = meta[h]
            for code, detail in rows:
                wr.writerow([h, code, (houses.get(h) or {}).get('name', ''), n, first[0], first[1], first[2], detail])


def run(server_dir=None, map_file=None, otb=None, xml=None, houses_file=None, csv_path=None, known_path=KNOWN, check=False,
        summary=False, limit=20, max_floors=MAX_FLOORS, log=print, world=None):
    if world is None:
        if server_dir:
            import patch_base_houses
            ddir = A.data_dir(server_dir)
            map_file = map_file or A.map_path(ddir)
            otb = otb or os.path.join(ddir, 'items', 'items.otb')
            xml = xml or os.path.join(ddir, 'items', 'items.xml')
            houses_file = houses_file or patch_base_houses.house_file(ddir)
        if not map_file or not os.path.isfile(map_file):
            raise HouseAuditError('no map (give SERVER_DIR with data/world/<map>.otbm, or --map)')
        if not houses_file or not os.path.isfile(houses_file):
            raise HouseAuditError('no house file (data/world/<mapName>-house.xml, or --houses)')
        w, _found = A.load_world(map_file, otb, xml, log=log, tables=dict(borders={}, grounds={}, walls={}))
    else:
        w = world
    houses = read_houses(houses_file)
    found, meta = audit(w, houses, max_floors)
    known = read_known(known_path)
    new, stale = report(found, meta, houses, known, limit, summary, log)
    for h, c in stale[:limit]:
        log('known entry no longer found: house %d %s' % (h, c))
    if csv_path:
        write_csv(csv_path, found, meta, houses)
        log('wrote %s' % csv_path)
    if check and new:
        log('NEW findings: %d (not in %s)' % (new, os.path.basename(known_path or KNOWN)))
        return found, 1
    return found, 0


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--houses', '--known', '--csv', '--map', '--items', '--xml', '--limit', '--max-floors'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('--check', '--summary', '--quiet'):
            opts[a] = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            print('unknown option %s' % a)
            return 1
        else:
            pos.append(a)
        i += 1
    if len(pos) > 1 or (not pos and '--map' not in opts):
        print(__doc__)
        return 1
    try:
        limit = int(opts.get('--limit', 20))
        max_floors = int(opts.get('--max-floors', MAX_FLOORS))
    except ValueError:
        print('bad --limit or --max-floors')
        return 1
    try:
        _f, rc = run(pos[0] if pos else None, opts.get('--map'), opts.get('--items'), opts.get('--xml'), opts.get('--houses'),
                     opts.get('--csv'), opts.get('--known', KNOWN), bool(opts.get('--check')), bool(opts.get('--summary')), limit,
                     max_floors, log=(lambda *_: None) if opts.get('--quiet') else print)
    except (HouseAuditError, A.AuditError, OSError) as e:
        print('refused: %s' % e)
        return 1
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
