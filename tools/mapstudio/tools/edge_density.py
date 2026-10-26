"""Plant density on a ground family by distance to the nearest tile of another family (path, sand, water, cliff).

python -B run.py tools/edge_density.py <G-family> <refs/...> [...]
Distance is in 4-neighbour steps on floor 7. Prints, per distance: tiles, plants per tile (decor, bottom, wall,
container items) and trees per tile (multi-tile containers and walls), relative to the family's mean.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, deque
from pathlib import Path

from common import kind_of, kit_ids, load_area, load_families, load_items, load_kit

N4 = [(0, -1), (1, 0), (0, 1), (-1, 0)]

CLIFF = kit_ids(load_kit(), "mountain_cliff")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("family")
    p.add_argument("refs", nargs="+")
    a = p.parse_args()
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    items = load_items()
    tiles, plants, trees = Counter(), Counter(), Counter()
    for ref in a.refs:
        _, area = load_area(Path(ref) / "area.txt")
        layer = area[7]
        own = {pos for pos, s in layer.items() if family.get(int(s[0])) == a.family}
        dist, q = {}, deque()
        for pos in layer:
            if pos not in own:
                dist[pos] = 0
                q.append(pos)
        while q:
            x, y = q.popleft()
            for dx, dy in N4:
                n = (x + dx, y + dy)
                if n in layer and n not in dist:
                    dist[n] = dist[(x, y)] + 1
                    q.append(n)
        for pos in own:
            d = min(dist.get(pos, 99), 12)
            tiles[d] += 1
            for i in {int(v) for v in layer[pos][1:]}:
                o = items.get(i)
                if not o:
                    continue
                k = kind_of(o["flags"])
                if k in ("decor", "bottom", "wall", "container") and i not in CLIFF:
                    plants[d] += 1
                    if k in ("container", "wall") and o["groups"][0]["width"] >= 2:
                        trees[d] += 1
    mp = sum(plants.values()) / sum(tiles.values())
    mt = sum(trees.values()) / sum(tiles.values())
    print(f"{a.family}: mean plants/tile {mp:.3f}, big plants/tile {mt:.3f}")
    for d in sorted(tiles):
        print(f"  d={d:2} tiles {tiles[d]:6}  plants x{plants[d] / tiles[d] / mp:4.2f}  big x{trees[d] / tiles[d] / mt:4.2f}")


if __name__ == "__main__":
    main()
