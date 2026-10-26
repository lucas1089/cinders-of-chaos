"""Side-by-side numbers for area files: ground variety, item density, floors used.

python -B run.py tools/compare_stats.py <area.txt> [...]
"""
from __future__ import annotations

import argparse
from collections import Counter

from common import kind_of, load_area, load_items


def main():
    p = argparse.ArgumentParser()
    p.add_argument("areas", nargs="+")
    a = p.parse_args()
    items = load_items()

    def kind(i):
        o = items.get(int(i))
        return kind_of(o["flags"]) if o else "?"

    print(f"{'area':32} {'tiles':>6} {'grounds':>7} {'top3 %':>6} {'items/t':>7} {'border%':>7} "
          f"{'decor/t':>7} {'ids':>5}  floors")
    for path in a.areas:
        _, area = load_area(path)
        surface = area[7]
        grounds = Counter(int(s[0]) for s in surface.values())
        kinds = Counter(kind(i) for s in surface.values() for i in s[1:])
        bordered = sum(1 for s in surface.values() if any(kind(i) == "border" for i in s[1:]))
        n = len(surface)
        ids = {int(i) for layer in area.values() for s in layer.values() for i in s}
        top3 = sum(c for _, c in grounds.most_common(3)) / n
        name = path.replace("\\", "/").split("/")[-2]
        print(f"{name:32} {n:6} {len(grounds):7} {top3 * 100:6.0f} "
              f"{sum(len(s) - 1 for s in surface.values()) / n:7.2f} {bordered / n * 100:7.0f} "
              f"{(kinds['decor'] + kinds['bottom'] + kinds['wall']) / n:7.2f} {len(ids):5}  "
              f"{ {z: len(t) for z, t in sorted(area.items()) if t} }")


if __name__ == "__main__":
    main()
