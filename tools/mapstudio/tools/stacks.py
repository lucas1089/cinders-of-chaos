"""Prints the floor-7 stacks of a window of an area file, one row per tile row, ids by kind.

python -B run.py tools/stacks.py <area.txt> <x1> <y1> <x2> <y2> [--floor 7]
"""
from __future__ import annotations

import argparse

from common import load_area, load_items, names_of


def main():
    p = argparse.ArgumentParser()
    p.add_argument("area")
    for k in ("x1", "y1", "x2", "y2"):
        p.add_argument(k, type=int)
    p.add_argument("--floor", type=int, default=7)
    a = p.parse_args()
    _, area = load_area(a.area)
    layer = area.get(a.floor, {})
    items, seen = load_items(), set()
    for y in range(a.y1, a.y2 + 1):
        print(f"y={y}: " + " | ".join(f"{x}:" + ",".join(str(int(i)) for i in layer.get((x, y), []))
                                      for x in range(a.x1, a.x2 + 1)))
        for x in range(a.x1, a.x2 + 1):
            seen |= {int(i) for i in layer.get((x, y), [])}
    for i in sorted(seen):
        g = items[i]["groups"][0] if i in items else {"width": 0, "height": 0}
        f = items[i]["flags"] if i in items else {}
        print(f"  {i}: {g['width']}x{g['height']} walk={'not_walkable' not in f} {names_of(i)[:1]}")


if __name__ == "__main__":
    main()
