"""What lies on the floor above tiles of a given ground, over refs/.

python -B run.py tools/above_items.py <ground id> [--top 30]
For every tile of the ground on floor z, looks at floor z-1 at the same x, y and at x-1, y-1 (the client draws
each higher floor one tile up-left). Prints how often each holds a tile, then the grounds and items found there.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from common import DEFAULT_REFS, kind_of, load_area, load_items, names_of



def main():
    p = argparse.ArgumentParser()
    p.add_argument("ground", type=int)
    p.add_argument("--top", type=int, default=30)
    a = p.parse_args()
    items = load_items()
    hits = {"same": Counter(), "shift": Counter()}
    grounds = {"same": Counter(), "shift": Counter()}
    stack = {"same": Counter(), "shift": Counter()}
    tiles = 0
    for ref in sorted(DEFAULT_REFS.iterdir()):
        if not (ref / "area.txt").exists():
            continue
        _, area = load_area(ref / "area.txt")
        for z, layer in area.items():
            up = area.get(z - 1, {})
            for (x, y), ids in layer.items():
                if int(ids[0]) != a.ground:
                    continue
                tiles += 1
                for key, pos in (("same", (x, y)), ("shift", (x - 1, y - 1))):
                    above = up.get(pos)
                    hits[key]["tile" if above else "none"] += 1
                    if above:
                        grounds[key][int(above[0])] += 1
                        for i in set(int(v) for v in above[1:]):
                            stack[key][i] += 1
    print(f"ground {a.ground}: {tiles} tiles")
    for key in ("same", "shift"):
        print(f"== {key}: {dict(hits[key])}")
        print("  grounds:", [(g, n, names_of(g)[:1]) for g, n in grounds[key].most_common(6)])
        for i, n in stack[key].most_common(a.top):
            o = items.get(i)
            g = o["groups"][0] if o else {"width": 0, "height": 0}
            print(f"  {i:7} {n:6} {n / tiles:6.3f} {kind_of(o['flags']) if o else '?':8} {g['width']}x{g['height']} {names_of(i)[:1]}")


if __name__ == "__main__":
    main()
