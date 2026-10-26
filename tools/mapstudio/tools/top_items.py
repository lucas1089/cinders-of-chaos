"""What the reference map stacks on tiles of a given ground, over refs/.

python -B run.py tools/top_items.py <ground id> [--top 30] [--interior]
Per item: tiles carrying it, share of the ground's tiles, kind, size, name. --interior counts only tiles whose
8 neighbours have the same ground (tops away from the rim).
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
    p.add_argument("--interior", action="store_true")
    a = p.parse_args()
    items = load_items()
    count, tiles = Counter(), 0
    for ref in sorted(DEFAULT_REFS.iterdir()):
        if not (ref / "area.txt").exists():
            continue
        _, area = load_area(ref / "area.txt")
        for layer in area.values():
            for (x, y), ids in layer.items():
                if int(ids[0]) != a.ground:
                    continue
                if a.interior and not all(
                        layer.get((x + i, y + j)) and int(layer[(x + i, y + j)][0]) == a.ground
                        for i in (-1, 0, 1) for j in (-1, 0, 1)):
                    continue
                tiles += 1
                for i in set(int(v) for v in ids[1:]):
                    count[i] += 1
    print(f"ground {a.ground}: {tiles} tiles")
    for i, n in count.most_common(a.top):
        o = items.get(i)
        g = o["groups"][0] if o else {"width": 0, "height": 0}
        print(f"{i:7} {n:6} {n / tiles:6.3f} {kind_of(o['flags']) if o else '?':8} {g['width']}x{g['height']} {names_of(i)[:1]}")


if __name__ == "__main__":
    main()
