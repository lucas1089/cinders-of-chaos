"""Plants on raised-floor rim tiles vs inner top tiles in reference windows.

python -B run.py tools/rim_plants.py <area dirs...>
Rim tile = a tile on floors 1-6 carrying a piece of the rock rim <id>-<id> or the earth rim. Counts big
(multi-tile) and small plants per tile on rim tiles and on other top tiles, and the commonest rim plants.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from common import kind_of, kit_ids, load_area, load_items, load_kit, names_of

RIM = kit_ids(load_kit(), "top_rim", "hill_rim")
CLIFF = kit_ids(load_kit(), "mountain_cliff")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("areas", nargs="+")
    a = p.parse_args()
    items = load_items()
    n, big, small, which = Counter(), Counter(), Counter(), Counter()
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        for z, layer in area.items():
            if not 1 <= z <= 6:
                continue
            for s in layer.values():
                ids = {int(v) for v in s}
                kind = "rim" if ids & RIM else "inner"
                n[kind] += 1
                for i in ids:
                    o = items.get(i)
                    if not o or i in CLIFF or i in RIM or kind_of(o["flags"]) not in ("decor", "bottom", "wall", "container"):
                        continue
                    g = o["groups"][0]
                    (big if g["width"] * g["height"] > 1 else small)[kind] += 1
                    if kind == "rim":
                        which[i] += 1
    for k in ("rim", "inner"):
        print(f"{k}: {n[k]} tiles, big/tile {big[k] / max(1, n[k]):.3f}, small/tile {small[k] / max(1, n[k]):.3f}")
    print("rim plants:", [(i, c, names_of(i)[:1]) for i, c in which.most_common(10)])


if __name__ == "__main__":
    main()
