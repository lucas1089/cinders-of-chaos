"""What lies on a ground family deep inside open areas (edge distance >= --min), per tile, with kind and walkability.

python -B run.py tools/meadow_items.py <G-family> <area dirs...> [--min 5]
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, deque
from pathlib import Path

from common import kind_of, load_area, load_families, load_items, names_of



def main():
    p = argparse.ArgumentParser()
    p.add_argument("family")
    p.add_argument("areas", nargs="+")
    p.add_argument("--min", type=int, default=5)
    a = p.parse_args()
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    items = load_items()
    count, n = Counter(), 0
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        layer = area[7]
        own = {pos for pos, s in layer.items() if family.get(int(s[0])) == a.family}
        dist, q = {}, deque()
        for pos in layer:
            if pos not in own:
                dist[pos] = 0
                q.append(pos)
        while q:
            x, y = q.popleft()
            for dx, dy in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                t = (x + dx, y + dy)
                if t in layer and t not in dist:
                    dist[t] = dist[(x, y)] + 1
                    q.append(t)
        for pos in own:
            if dist.get(pos, 99) < a.min:
                continue
            n += 1
            for i in {int(v) for v in layer[pos][1:]}:
                count[i] += 1
    print(f"{n} deep tiles")
    for i, c in count.most_common(25):
        o = items.get(i)
        g = o["groups"][0] if o else {"width": 0, "height": 0}
        print(f"  {i:7} {c / n:.4f} {kind_of(o['flags']) if o else '?':9} {g['width']}x{g['height']} "
              f"{'walk' if o and 'not_walkable' not in o['flags'] else 'BLOCK'} {names_of(i)[:1]}")


if __name__ == "__main__":
    main()
