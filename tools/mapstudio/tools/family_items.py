"""Per ground family: which non-border items lie on its tiles, per tile, with size and walkability.

python -B run.py tools/family_items.py <G-family,...> <refs...> [--floors 9-15] [--exclude a-b,c-d] [--top 14]
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import kind_of, load_area, load_families, load_items, names_of



def main():
    p = argparse.ArgumentParser()
    p.add_argument("families")
    p.add_argument("refs", nargs="+")
    p.add_argument("--floors", default="9-15")
    p.add_argument("--exclude", default="")
    p.add_argument("--top", type=int, default=14)
    a = p.parse_args()
    lo, _, hi = a.floors.partition("-")
    floors = range(int(lo), int(hi or lo) + 1)
    skip = set()
    for part in filter(None, a.exclude.split(",")):
        s, _, e = part.partition("-")
        skip |= set(range(int(s), int(e or s) + 1))
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    want = a.families.split(",")
    items = load_items()
    count, tiles = defaultdict(Counter), Counter()
    for ref in a.refs:
        _, area = load_area(Path(ref) / "area.txt")
        for z in floors:
            for s in area.get(z, {}).values():
                f = family.get(int(s[0])) if s else None
                if f not in want:
                    continue
                tiles[f] += 1
                for i in {int(v) for v in s[1:]}:
                    o = items.get(i)
                    if i in skip or not o or kind_of(o["flags"]) == "border":
                        continue
                    count[f][i] += 1
    for f in want:
        n = max(1, tiles[f])
        print(f"== {f} {fam['grounds'][f]['name']} ({tiles[f]} tiles)")
        for i, c in count[f].most_common(a.top):
            o = items[i]
            g = o["groups"][0]
            print(f"  {i} {c / n:.4f} {kind_of(o['flags'])} {g['width']}x{g['height']} "
                  f"{'walk' if 'not_walkable' not in o['flags'] else 'BLOCK'} {names_of(i)[:1]}")


if __name__ == "__main__":
    main()
