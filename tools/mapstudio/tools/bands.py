"""How a group of ground families is layered inside its bodies: per distance from the group's edge (1 = touches
other ground), the share of each family. E.g. lava: crust chunks along the shore, molten lava inside.

python -B run.py tools/bands.py <id>,<id>,<id>,<id> <refs...> [--floors 9-15] [--max 6]
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict, deque
from pathlib import Path

from common import load_area, load_families



def main():
    p = argparse.ArgumentParser()
    p.add_argument("group")
    p.add_argument("refs", nargs="+")
    p.add_argument("--floors", default="9-15")
    p.add_argument("--max", type=int, default=6)
    a = p.parse_args()
    lo, _, hi = a.floors.partition("-")
    floors = range(int(lo), int(hi or lo) + 1)
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    group = set(a.group.split(","))
    bands = defaultdict(Counter)
    for ref in a.refs:
        _, area = load_area(Path(ref) / "area.txt")
        for z in floors:
            layer = area.get(z, {})
            own = {pos: family.get(int(s[0])) for pos, s in layer.items() if s and family.get(int(s[0])) in group}
            dist, q = {}, deque()
            for (x, y) in own:
                if any((x + i, y + j) in layer and (x + i, y + j) not in own
                       for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0))):
                    dist[(x, y)] = 1
                    q.append((x, y))
            while q:
                x, y = q.popleft()
                for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                    t = (x + i, y + j)
                    if t in own and t not in dist:
                        dist[t] = dist[(x, y)] + 1
                        q.append(t)
            for t, f in own.items():
                if t in dist:
                    bands[min(dist[t], a.max)][f] += 1
    name = lambda f: f"{f} {fam['grounds'].get(f, {}).get('name', '')}"
    for d in sorted(bands):
        c = bands[d]
        n = sum(c.values())
        print(f"d={d}{'+' if d == a.max else ' '} {n:6}: " + ", ".join(f"{name(f)} {v / n:.2f}" for f, v in c.most_common()))


if __name__ == "__main__":
    main()
