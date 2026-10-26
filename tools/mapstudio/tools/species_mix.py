"""Which plants make up dense and sparse parts of a family's ground: share of each big plant among the big
plants whose 5x5 neighbourhood holds few (<= 2), some (3-5) or many (6+) big plants.

python -B run.py tools/species_mix.py <G-family> <area dirs...> [--window x1,y1,x2,y2]
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from common import kind_of, kit_ids, load_area, load_families, load_items, load_kit, names_of

CLIFF = kit_ids(load_kit(), "mountain_cliff")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("family")
    p.add_argument("areas", nargs="+")
    a = p.parse_args()
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    items = load_items()
    mix = {"few": Counter(), "some": Counter(), "many": Counter()}
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        layer = area[7]
        big = {}
        for pos, s in layer.items():
            if family.get(int(s[0])) != a.family:
                continue
            for i in {int(v) for v in s[1:]}:
                o = items.get(i)
                if o and i not in CLIFF and kind_of(o["flags"]) in ("decor", "bottom", "wall", "container") \
                        and o["groups"][0]["width"] * o["groups"][0]["height"] > 1:
                    big[pos] = i
        for (x, y), i in big.items():
            n = sum((x + dx, y + dy) in big for dx in range(-2, 3) for dy in range(-2, 3))
            mix["few" if n <= 2 else "some" if n <= 5 else "many"][i] += 1
    for k, c in mix.items():
        t = sum(c.values())
        print(f"{k}: {t} plants:", [(i, round(n / t, 2), names_of(i)[:1]) for i, n in c.most_common(8)])


if __name__ == "__main__":
    main()
