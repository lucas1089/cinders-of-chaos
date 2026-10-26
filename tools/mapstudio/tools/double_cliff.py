"""How the reference map stacks a cliff two levels high: finds columns of height 2+ next to a column of height 0 and prints
the stacks on floors 5-7 around one, plus counts of what the floor-6 and floor-7 tiles below the edge carry.

python -B run.py tools/double_cliff.py <area dir> [--show 2]
Height of a column = 7 - the highest floor with a ground there.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from common import kind_of, load_area, load_items, names_of

N4 = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("area")
    p.add_argument("--show", type=int, default=2)
    a = p.parse_args()
    items = load_items()
    _, area = load_area(Path(a.area) / "area.txt")
    ground = lambda s: s and kind_of(items[int(s[0])]["flags"]) == "ground" if int(s[0]) in items else False
    height = {}
    for z in sorted(area, reverse=True):
        for pos, s in area[z].items():
            if ground(s):
                height[pos] = 7 - z
    shown = 0
    on6, on7 = Counter(), Counter()
    for (x, y), h in height.items():
        if h < 2:
            continue
        for d, (dx, dy) in N4.items():
            low = (x + dx, y + dy)
            if height.get(low) != 0:
                continue
            # the low column right outside a level-2 edge: what floors 6 and 7 carry there
            s6, s7 = area.get(6, {}).get(low, []), area.get(7, {}).get(low, [])
            on6[tuple(sorted({names_of(int(i))[0] if names_of(int(i)) else str(int(i)) for i in s6}))] += 1
            on7["has 7"] += 1 if s7 else 0
            natural = s6 and all(names_of(int(i))[:1] == ["mountain"] for i in s6)
            if shown < a.show and d == "s" and natural:
                shown += 1
                print(f"== level {h} edge at {x},{y}, low column to the {d} at {low}")
                for z in (5, 6, 7):
                    for yy in range(y - 2, y + 4):
                        print(f"  z{z} y={yy}: " + " | ".join(
                            ",".join(str(int(i)) for i in area.get(z, {}).get((xx, yy), [])) or "."
                            for xx in range(x - 2, x + 3)))
    print("floor-6 contents of the low column:", on6.most_common(8))
    print(on7)


if __name__ == "__main__":
    main()
