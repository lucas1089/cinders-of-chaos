"""Where a ground family sits: its share per floor, its depth (distance to its own edge, i.e. patch/road
width), and how far its tiles are from raised ground (mountain fill or cliff pieces) on floor 7.

python -B run.py tools/ground_context.py <G-family> <area dirs...>
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, deque
from pathlib import Path

from common import kit_ids, load_area, load_families, load_kit

N4 = [(0, -1), (1, 0), (0, 1), (-1, 0)]
CLIFF = kit_ids(load_kit(), "mountain_cliff")
FILL = kit_ids(load_kit(), "mountain")


def bfs(layer, sources):
    dist, q = {}, deque()
    for pos in sources:
        dist[pos] = 0
        q.append(pos)
    while q:
        x, y = q.popleft()
        for dx, dy in N4:
            nb = (x + dx, y + dy)
            if nb in layer and nb not in dist:
                dist[nb] = dist[(x, y)] + 1
                q.append(nb)
    return dist


def main():
    p = argparse.ArgumentParser()
    p.add_argument("family")
    p.add_argument("areas", nargs="+")
    a = p.parse_args()
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    share, depth, near = Counter(), Counter(), Counter()
    totals = Counter()
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        for z, layer in area.items():
            own = {pos for pos, s in layer.items() if family.get(int(s[0])) == a.family}
            totals[z] += len(layer)
            share[z] += len(own)
            if not own:
                continue
            d = bfs(layer, [pos for pos in layer if pos not in own])
            for pos in own:
                depth[min(d.get(pos, 9), 9)] += 1
            if z == 7:
                raised = [pos for pos, s in layer.items() if int(s[0]) in FILL or {int(v) for v in s} & CLIFF]
                r = bfs(layer, raised)
                for pos in own:
                    near[min(r.get(pos, 20), 20)] += 1
    print("share per floor:", {z: round(share[z] / totals[z], 3) for z in sorted(totals) if share[z]})
    t = sum(depth.values())
    print("depth (1 = edge tile):", {k: round(v / t, 2) for k, v in sorted(depth.items())})
    t = sum(near.values())
    if t:
        print("distance to raised ground on z7:", {k: round(v / t, 2) for k, v in sorted(near.items())})


if __name__ == "__main__":
    main()
