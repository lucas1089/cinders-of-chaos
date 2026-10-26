"""What lines the water in reference windows: bank grounds, bank items, and water widths.

python -B run.py tools/bank_study.py <refs/...> [...]
Bank = a floor-7 land tile with water on one of its 8 neighbours (cliff-piece tiles counted apart). Width = the
shorter of the horizontal and vertical water runs through a water tile.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from common import kind_of, load_area, load_families, load_items, load_kit, names_of

WATER = load_kit()["water"]["family"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("refs", nargs="+")
    a = p.parse_args()
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    cliff = {i for c in fam.get("cliffs", {}).values() for ids in c["pieces"].values() for i, _ in ids}
    items = load_items()
    banks, ring2, bank_items, widths, n_bank, n_cliff = Counter(), Counter(), Counter(), Counter(), 0, 0
    for ref in a.refs:
        _, area = load_area(Path(ref) / "area.txt")
        layer = area[7]
        fam_at = {pos: family.get(int(s[0])) for pos, s in layer.items()}
        wet = {pos for pos, f in fam_at.items() if f == WATER}
        for (x, y), s in layer.items():
            if (x, y) in wet:
                runs = []
                for dx, dy in ((1, 0), (0, 1)):
                    n = 1
                    for sgn in (1, -1):
                        k = 1
                        while (x + sgn * k * dx, y + sgn * k * dy) in wet and k < 40:
                            n, k = n + 1, k + 1
                    runs.append(n)
                widths[min(min(runs), 13)] += 1
                continue
            near = [(x + i, y + j) in wet for i in (-1, 0, 1) for j in (-1, 0, 1)]
            near2 = any((x + i, y + j) in wet for i in range(-2, 3) for j in range(-2, 3))
            ids = {int(v) for v in s}
            if any(near):
                if ids & cliff:
                    n_cliff += 1
                    continue
                n_bank += 1
                banks[fam_at[(x, y)]] += 1
                for i in ids:
                    o = items.get(i)
                    if o and kind_of(o["flags"]) in ("decor", "bottom", "wall", "container"):
                        bank_items[i] += 1
            elif near2:
                ring2[fam_at[(x, y)]] += 1
    name = lambda f: fam["grounds"].get(f, {}).get("name", f)
    print(f"bank tiles {n_bank} (+{n_cliff} cliff tiles at water)")
    print("bank grounds:", [(name(f), round(c / n_bank, 2)) for f, c in banks.most_common(6)])
    print("second ring grounds:", [(name(f), round(c / sum(ring2.values()), 2)) for f, c in ring2.most_common(5)])
    print("bank plants:", [(i, round(c / n_bank, 3), names_of(i)[:1]) for i, c in bank_items.most_common(12)])
    t = sum(widths.values())
    print("water width share:", {w: round(c / t, 2) for w, c in sorted(widths.items())})


if __name__ == "__main__":
    main()
