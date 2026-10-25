#!/usr/bin/env python3
"""Cuts walkability windows out of an installed server's map for server/tools/path_bench.cpp (O211).

Reads the ground floor (z 7) of an .otbm and the blocking flags of items.otb, and writes one text file the benchmark
reads with --grid: a header line "W H" and then H rows of W characters, '.' = a tile a monster can step on, '#' = a tile
that blocks (an item with the solid or path-blocking flag, also a ground with it, like water), ' ' = no tile.
Several windows can follow one another in the file (each starts with its own "W H" line).

Windows are picked by the share of walkable tiles (default 0.30-0.85: not open sea, not solid rock) and by how many
of their tiles are blocking (so the window has walls, trees, rooms). The pick is deterministic. Nothing from the map is
kept in the repository: run it on an installed server and keep the file outside git.

    python3 -I server/tools/path_bench_grid.py --map DIR/data/world/WORLD.otbm --items DIR/data/items/items.otb \
        --out grid.txt --windows 6 --size 96
"""

import argparse
import importlib.util
import os
import struct
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("packet_compress_bench", os.path.join(_HERE, "packet_compress_bench.py"))
_bench = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_bench)

FLAG_BLOCK_SOLID = 1 << 0
FLAG_BLOCK_PATHFIND = 1 << 2


def load_block_flags(path):
    """server id -> True when a monster cannot walk over the item (solid or path blocking)."""
    blob = open(path, "rb").read()
    table = {}
    for depth, _group, data in _bench._nodes(blob):
        if depth != 2 or len(data) < 4:
            continue
        flags = struct.unpack_from("<I", data, 0)[0]
        pos = 4
        server = None
        while pos + 3 <= len(data):
            attr, ln = data[pos], struct.unpack_from("<H", data, pos + 1)[0]
            if attr == 0x10 and ln == 2:
                server = struct.unpack_from("<H", data, pos + 3)[0]
            pos += 3 + ln
        if server:
            table[server] = bool(flags & (FLAG_BLOCK_SOLID | FLAG_BLOCK_PATHFIND))
    return table


def load_floor(path, blocking, sample_mod):
    """grid[(x, y)] = 1 walkable, 2 blocking, for the areas of floor 7 picked by sample_mod."""
    blob = open(path, "rb").read()
    grid = {}
    area = None
    keep = False
    tile = None
    for depth, ty, data in _bench._nodes(blob):
        if ty == 4 and len(data) >= 5:
            ax, ay, az = struct.unpack_from("<HHB", data, 0)
            area = (ax, ay)
            keep = az == 7 and ((ax >> 8) * 7 + (ay >> 8) * 13) % sample_mod == 0
        elif ty in (5, 14) and keep and len(data) >= 2:
            tile = (area[0] + data[0], area[1] + data[1])
            state = 1
            pos = 6 if ty == 14 else 2
            while pos < len(data):
                attr = data[pos]
                pos += 1
                if attr == 3:
                    pos += 4
                elif attr == 9 and pos + 2 <= len(data):
                    item = struct.unpack_from("<H", data, pos)[0]
                    if blocking.get(item, False):
                        state = 2
                    pos += 2
                else:
                    break
            grid[tile] = state
        elif ty == 6 and keep and tile is not None and len(data) >= 2 and depth == 5:
            if blocking.get(struct.unpack_from("<H", data, 0)[0], False):
                grid[tile] = 2
    return grid


def pick_windows(grid, size, count, lo, hi):
    """Non overlapping size x size windows whose walkable share is in [lo, hi], most blocking tiles first."""
    cells = {}
    for (x, y), state in grid.items():
        key = (x // size, y // size)
        walk, block = cells.get(key, (0, 0))
        cells[key] = (walk + (state == 1), block + (state == 2))
    total = size * size
    cand = []
    for key, (walk, block) in cells.items():
        share = walk / total
        if lo <= share <= hi and block >= total * 0.10:
            cand.append((-block, key))
    cand.sort()
    return [key for _b, key in cand[:count]]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--map", required=True)
    ap.add_argument("--items", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", type=int, default=96)
    ap.add_argument("--windows", type=int, default=6)
    ap.add_argument("--sample", type=int, default=3, help="read 1 of N areas of 256x256 tiles (default 3)")
    ap.add_argument("--min-walk", type=float, default=0.30)
    ap.add_argument("--max-walk", type=float, default=0.85)
    args = ap.parse_args()

    blocking = load_block_flags(args.items)
    grid = load_floor(args.map, blocking, args.sample)
    keys = pick_windows(grid, args.size, args.windows, args.min_walk, args.max_walk)
    if not keys:
        print("no window matched", file=sys.stderr)
        return 1
    with open(args.out, "w") as out:
        for kx, ky in sorted(keys):
            out.write("%d %d\n" % (args.size, args.size))
            for y in range(ky * args.size, (ky + 1) * args.size):
                row = []
                for x in range(kx * args.size, (kx + 1) * args.size):
                    state = grid.get((x, y), 0)
                    row.append(" " if state == 0 else ("." if state == 1 else "#"))
                out.write("".join(row) + "\n")
    print("%d windows of %dx%d from %d tiles" % (len(keys), args.size, args.size, len(grid)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
