"""How walkable space behaves around relief, per floor: corridor widths, room around ramps, plants near ramps.

python -B run.py tools/path_study.py <area dirs...> [--floors 4,5,6,7]
Walkable = gen/access.py rules (item flags). Width of a walkable tile = min(horizontal run, vertical run) of
walkable tiles through it, capped at 9: 1 = a one-tile gap. "Near relief" = within 2 tiles of a cliff piece or
fill. Ramps: every tile holding an item with a floorchange in items.xml; room = walkable tiles in the 5x5 around
the tile below the ramp (approach) and around the tile it leads onto (landing); plants = blocking non-relief
items within 2 tiles of the ramp.
"""
from __future__ import annotations

import argparse
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gen"))

import access  # noqa: E402
from common import floorchanges, kind_of, kit_ids, load_area, load_items, load_kit  # noqa: E402

CLIFF = kit_ids(load_kit(), "mountain_cliff", "hill_cliff", "mountain", "hill")
DIRS = {"north": (0, -1), "south": (0, 1), "east": (1, 0), "west": (-1, 0)}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("areas", nargs="+")
    p.add_argument("--floors", default="4,5,6,7")
    a = p.parse_args()
    items = load_items()
    fc = floorchanges()
    floors = [int(z) for z in a.floors.split(",")]
    width = defaultdict(Counter)
    ramps = Counter()
    room = defaultdict(list)
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        for z in floors:
            layer = area.get(z, {})
            walk = {pos for pos, s in layer.items() if access.walkable(items, s)}
            rough = {pos for pos, s in layer.items() if {int(i) for i in s} & CLIFF}
            near = {(x + i, y + j) for x, y in rough for i in range(-2, 3) for j in range(-2, 3)}

            def run(x, y, dx, dy):
                n = 1
                for sgn in (1, -1):
                    k = 1
                    while (x + sgn * k * dx, y + sgn * k * dy) in walk and n < 9:
                        n, k = n + 1, k + 1
                return n

            for x, y in walk:
                w = min(run(x, y, 1, 0), run(x, y, 0, 1))
                width[(z, "near relief" if (x, y) in near else "open")][w] += 1
            up = area.get(z - 1, {})
            up_walk = {pos for pos, s in up.items() if access.walkable(items, s)}
            for (x, y), s in layer.items():
                d = next((fc[int(i)] for i in s if int(i) in fc), None)
                if not d:
                    continue
                dx, dy = DIRS[d]
                ramps[z] += 1
                below = (x - dx, y - dy)
                land = (x + dx, y + dy)
                room["approach"].append(sum((below[0] + i, below[1] + j) in walk for i in range(-2, 3) for j in range(-2, 3)))
                room["landing"].append(sum((land[0] + i, land[1] + j) in up_walk for i in range(-2, 3) for j in range(-2, 3)))
                blockers = 0
                for i in range(-2, 3):
                    for j in range(-2, 3):
                        for it in layer.get((x + i, y + j), []):
                            o = items.get(int(it))
                            if o and "not_walkable" in o["flags"] and int(it) not in CLIFF \
                                    and kind_of(o["flags"]) in ("wall", "container", "decor"):
                                blockers += 1
                room["plants within 2"].append(blockers)
    for (z, kind), c in sorted(width.items()):
        t = sum(c.values())
        print(f"z{z} {kind:11} {t:6} tiles  width " + " ".join(f"{w}:{c[w] / t:.2f}" for w in range(1, 10)))
    print("ramps per floor:", dict(ramps))
    for k, v in room.items():
        v = sorted(v)
        if v:
            print(f"{k:16} median {v[len(v) // 2]}  q10 {v[len(v) // 10]}  q90 {v[9 * len(v) // 10]}  (of 25)")


if __name__ == "__main__":
    main()
