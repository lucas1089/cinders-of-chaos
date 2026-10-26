"""What lies on the boundary tiles between two ground families in reference windows.

python -B run.py tools/pair_items.py <G-family> <G-family> <refs/...> [...]
For tiles of the first family with the second as a 4-neighbour (and the other way round): how many there are,
and the commonest items on them, with kind and name.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from common import kind_of, load_area, load_families, load_items, names_of

N4 = [(0, -1), (1, 0), (0, 1), (-1, 0)]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("a")
    p.add_argument("b")
    p.add_argument("refs", nargs="+")
    args = p.parse_args()
    fam = load_families()
    family = {i: key for key, g in fam["grounds"].items() for i in g["members"]}
    items = load_items()
    for f, g in ((args.a, args.b), (args.b, args.a)):
        count, n = Counter(), 0
        for ref in args.refs:
            _, area = load_area(Path(ref) / "area.txt")
            layer = area[7]
            for (x, y), s in layer.items():
                if family.get(int(s[0])) != f:
                    continue
                if not any((t := layer.get((x + dx, y + dy))) and family.get(int(t[0])) == g for dx, dy in N4):
                    continue
                n += 1
                for i in {int(v) for v in s[1:]}:
                    count[i] += 1
        print(f"== {f} tiles touching {g}: {n}")
        for i, c in count.most_common(14):
            o = items.get(i)
            print(f"  {i:7} {c / max(n, 1):6.3f} {kind_of(o['flags']) if o else '?':7} {names_of(i)[:1]}")


if __name__ == "__main__":
    main()
