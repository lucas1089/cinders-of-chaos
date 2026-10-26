"""What lies on the edge tiles of raised tops and what climbs between floors, in reference windows.

python -B run.py tools/rim_items.py <refs...> [--floors 9-14]
Edge tile: a tile on floor z with ground whose 4-neighbour on z is empty while floor z+1 has a tile there (a
drop to the floor below). Prints the commonest border/wall items on edge tiles vs other tiles, and every item
with a floorchange in items.xml, with counts.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from common import floorchanges, kind_of, load_area, load_items, names_of


def main():
    p = argparse.ArgumentParser()
    p.add_argument("refs", nargs="+")
    p.add_argument("--floors", default="9-14")
    a = p.parse_args()
    lo, _, hi = a.floors.partition("-")
    floors = range(int(lo), int(hi or lo) + 1)
    items = load_items()
    fc = floorchanges(any_kind=True)
    edge, other, ramps = Counter(), Counter(), Counter()
    n_edge = n_other = 0
    for ref in a.refs:
        _, area = load_area(Path(ref) / "area.txt")
        for z in floors:
            layer, below = area.get(z, {}), area.get(z + 1, {})
            for (x, y), s in layer.items():
                ids = [int(v) for v in s]
                for i in ids:
                    if i in fc:
                        ramps[(i, fc[i])] += 1
                if not ids or not items.get(ids[0]) or kind_of(items[ids[0]]["flags"]) != "ground":
                    continue
                drop = any((x + dx, y + dy) not in layer and (x + dx, y + dy) in below
                           for dx, dy in ((0, 1), (1, 0), (0, -1), (-1, 0)))
                bucket = edge if drop else other
                if drop:
                    n_edge += 1
                else:
                    n_other += 1
                for i in set(ids[1:]):
                    o = items.get(i)
                    if o and kind_of(o["flags"]) in ("border", "wall"):
                        bucket[i] += 1
    print(f"edge tiles {n_edge}, other tiles {n_other}")
    print("on edge tiles (share, share elsewhere):")
    for i, c in edge.most_common(20):
        print(f"  {i} {c / max(1, n_edge):.3f} {other[i] / max(1, n_other):.3f} {kind_of(items[i]['flags'])} {names_of(i)[:1]}")
    print("floor changes:", [(i, d, c, names_of(i)[:1]) for (i, d), c in ramps.most_common(16)])


if __name__ == "__main__":
    main()
