"""What separates an unreachable pocket from the reached ground: blocked tiles that lie within 2 steps of both.

python -B run.py tools/separators.py <area.txt> <x,y of a pocket tile> [--floor 7]
"""
from __future__ import annotations

import argparse
import sys
from collections import Counter, deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gen"))

import access  # noqa: E402
from common import load_area, load_items, load_kit, names_of  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument("area")
    p.add_argument("at")
    p.add_argument("--floor", type=int, default=7)
    p.add_argument("--kit", help="default: the kit named in the area header")
    a = p.parse_args()
    items = load_items()
    meta, floors = load_area(a.area)
    kit = load_kit(a.kit or meta.get("kit"))
    ramp_dirs = {ids[0]: d for key in ("mountain_ramp", "hill_ramp") for d, ids in kit.get(key, {}).items()}
    layer = floors[a.floor]
    got = {(x, y) for z, x, y in access.reach(floors, items, ramp_dirs, access.main_start(floors, items)) if z == a.floor}
    x0, y0 = map(int, a.at.split(","))
    pocket, q = {(x0, y0)}, deque([(x0, y0)])
    while q:
        x, y = q.popleft()
        for i, j in access.STEPS:
            n = (x + i, y + j)
            if n not in pocket and n in layer and access.walkable(items, layer[n]):
                pocket.add(n)
                q.append(n)
    near = lambda t, s: any((t[0] + i, t[1] + j) in s for i in range(-2, 3) for j in range(-2, 3))
    seps = Counter()
    tiles = []
    for t, stack in layer.items():
        if t in pocket or t in got or access.walkable(items, stack):
            continue
        if near(t, pocket) and near(t, got):
            tiles.append(t)
            for i in stack:
                if access.blocks(items, i):
                    seps[(int(i), (names_of(int(i)) or [""])[0])] += 1
    print(f"pocket {len(pocket)} tiles; separating blocked tiles {len(tiles)}")
    print(seps.most_common(12))
    print(sorted(tiles)[:20])


if __name__ == "__main__":
    main()
