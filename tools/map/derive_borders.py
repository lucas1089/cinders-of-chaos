"""Derive border and wall piece tables from a real map (the data behind the area generator's palettes).

    python3 -I tools/map/derive_borders.py MAP(.otbm|.npz) ITEMS.otb ITEMS.xml neighbours UNDER_IDS
    python3 -I tools/map/derive_borders.py MAP ITEMS.otb ITEMS.xml edges OVER_IDS UNDER_IDS [--lua]
    python3 -I tools/map/derive_borders.py MAP ITEMS.otb ITEMS.xml walls H_IDS V_IDS C_IDS P_IDS

IDS are comma separated server ids, ranges allowed (351-355,9021).

neighbours  which other grounds touch tiles of UNDER_IDS (4-neighbours), most common first: the pairs that real
            maps put next to each other.
edges       for every tile of UNDER_IDS, the 8 neighbours that are OVER_IDS give one of the 12 border patterns:
            n, e, s, w (one side), cnw, cne, csw, cse (one corner only), dnw, dne, dsw, dse (two sides and the
            corner between them). The piece is named after the side where the OVER ground lies, the way the
            map editor names its border items. For each pattern the most common non-ground items on those tiles
            are printed with their share; --lua prints the winning item per pattern as a Lua table
            (server/data/scripts/chaos/areagen_config.lua `borders`).
walls       the wall pieces of one wall brush (horizontal, vertical, corner, pole ids) by which of the 4 neighbours
            also carry a piece of the brush (N, E, S, W): the table the generator uses to pick a piece
            (areagen_core.lua A.wallPiece).

Only tiles whose 8 neighbours all exist are counted. Deterministic.
"""
import sys, os, collections
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import otbm
from itemdb import ItemDB

PATTERNS = {'n': ['n'], 'e': ['e'], 's': ['s'], 'w': ['w'], 'cnw': ['nw'], 'cne': ['ne'], 'csw': ['sw'], 'cse': ['se'],
            'dnw': ['n', 'w', 'nw'], 'dne': ['n', 'e', 'ne'], 'dsw': ['s', 'w', 'sw'], 'dse': ['s', 'e', 'se']}
DIRS = {'n': (0, -1), 'e': (1, 0), 's': (0, 1), 'w': (-1, 0), 'nw': (-1, -1), 'ne': (1, -1), 'sw': (-1, 1), 'se': (1, 1)}


def parse_ids(s):
    out = []
    for part in s.split(','):
        part = part.strip()
        if not part:
            continue
        if '-' in part:
            a, b = part.split('-')
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return np.array(sorted(set(out)), np.int64)


class Grid:
    """ground id of every tile and lookups of the neighbours"""

    def __init__(self, m):
        t = m.tiles
        self.m = m
        self.x = t['x'].astype(np.int64)
        self.y = t['y'].astype(np.int64)
        self.z = t['z'].astype(np.int64)
        self.g = np.zeros(len(self.x), np.int64)
        has = t['cnt'] > 0
        self.g[has] = m.items[t['off'][has]]
        key = (self.z << 32) | (self.y << 16) | self.x
        self.order = np.argsort(key, kind='stable')
        self.sk = key[self.order]

    def ground_at(self, dx, dy):
        k = (self.z << 32) | ((self.y + dy) << 16) | (self.x + dx)
        i = np.minimum(np.searchsorted(self.sk, k), len(self.sk) - 1)
        ok = self.sk[i] == k
        r = np.full(len(self.x), -1, np.int64)
        r[ok] = self.g[self.order[i[ok]]]
        return r


def neighbours(grid, db, under):
    isu = np.isin(grid.g, under)
    c = collections.Counter()
    for d in ('n', 'e', 's', 'w'):
        gn = grid.ground_at(*DIRS[d])
        sel = isu & (gn > 0) & ~np.isin(gn, under)
        for v, n in zip(*np.unique(gn[sel], return_counts=True)):
            c[int(v)] += int(n)
    total = sum(c.values())
    print(f'{int(isu.sum())} tiles; {total} contacts with other grounds')
    for v, n in c.most_common(40):
        print(f'  {v:6d} {db.name[v][:28]:28s} {n:8d} {100.0 * n / max(1, total):5.1f}%  blocks={bool(db.block[v])}')


def edges(grid, db, over, under, lua=False):
    isu = np.isin(grid.g, under)
    nb = {}
    present = np.ones(len(grid.x), bool)
    for d, (dx, dy) in DIRS.items():
        gn = grid.ground_at(dx, dy)
        present &= gn >= 0
        nb[d] = np.isin(gn, over)
    best = {}
    for name, sides in PATTERNS.items():
        sel = isu & present
        for d in DIRS:
            sel &= nb[d] if d in sides else ~nb[d]
        idx = np.flatnonzero(sel)
        c = collections.Counter()
        for i in idx[:50000]:
            for s in grid.m.stack(i)[1:]:
                if db.cls[int(s)] != 1:
                    c[int(s)] += 1
        top = c.most_common(4)
        share = (top[0][1] / max(1, len(idx[:50000]))) if top else 0
        best[name] = (top[0][0] if top else None, share, len(idx))
        print(f'  {name:4s} {len(idx):7d} tiles  ' + ', '.join(f'{s} {db.name[s][:16]} {100.0 * n / max(1, len(idx[:50000])):.0f}%'
                                                         for s, n in top))
    if lua:
        print('{' + ', '.join(f'{k} = {v[0]}' for k, v in best.items() if v[0]) + '}')
    return best


def walls(grid, db, h, v, c, p):
    m = grid.m
    kind = {}
    for ids, k in ((h, 'horizontal'), (v, 'vertical'), (c, 'corner'), (p, 'pole')):
        for i in ids:
            kind[int(i)] = k
    allids = np.array(sorted(kind), np.int64)
    t = m.tiles
    tile_of = np.repeat(np.arange(len(grid.x)), t['cnt'].astype(np.int64))
    cells = {}
    for i in np.unique(tile_of[np.isin(m.items, allids)]):
        for s in m.stack(i):
            if int(s) in kind:
                cells[(int(grid.x[i]), int(grid.y[i]), int(grid.z[i]))] = kind[int(s)]
                break
    cnt = collections.Counter()
    for (x, y, z), k in cells.items():
        mask = ''.join(d for d, (dx, dy) in (('N', (0, -1)), ('E', (1, 0)), ('S', (0, 1)), ('W', (-1, 0)))
                       if (x + dx, y + dy, z) in cells)
        cnt[(mask, k)] += 1
    print(f'{len(cells)} wall tiles')
    for mask in sorted({k[0] for k in cnt}, key=lambda s: (len(s), s)):
        row = sorted(((n, k) for (mm, k), n in cnt.items() if mm == mask), reverse=True)
        tot = sum(n for n, _ in row)
        print(f'  {mask or "-":5s} ' + ', '.join(f'{k} {100.0 * n / tot:.0f}%' for n, k in row) + f'  ({tot})')


def main():
    a = sys.argv[1:]
    if len(a) < 5:
        print(__doc__)
        sys.exit(2)
    m = otbm.load_map(a[0])
    db = ItemDB(a[1], a[2])
    grid = Grid(m)
    mode = a[3]
    if mode == 'neighbours':
        neighbours(grid, db, parse_ids(a[4]))
    elif mode == 'edges':
        edges(grid, db, parse_ids(a[4]), parse_ids(a[5]), lua='--lua' in a)
    elif mode == 'walls':
        walls(grid, db, *[parse_ids(s) for s in a[4:8]])
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == '__main__':
    main()
