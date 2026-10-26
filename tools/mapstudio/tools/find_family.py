"""Where ground families sit on the reference map: tile counts per 64x64 block and floor, with the other grounds
in the best blocks.

python -B run.py tools/find_family.py G<lead> [G<lead> ...] [--top 12] [--block 64] [--map <map>]
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import iter_tiles, load_families



def main():
    p = argparse.ArgumentParser()
    p.add_argument("families", nargs="+")
    p.add_argument("--top", type=int, default=12)
    p.add_argument("--block", type=int, default=64)
    p.add_argument("--map", help="default: the reference map")
    a = p.parse_args()
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    name = lambda f: fam["grounds"].get(f, {}).get("name", f)
    want = set(a.families)
    hits = Counter()
    others = defaultdict(Counter)
    for z, x, y, ids in iter_tiles(a.map):
        g = family.get(int(ids[0]))
        key = (z, x // a.block * a.block, y // a.block * a.block)
        if g in want:
            hits[key] += 1
        others[key][g] += 1
    print(f"total tiles: {sum(hits.values())}")
    by_floor = Counter()
    for (z, _, _), n in hits.items():
        by_floor[z] += n
    print("by floor:", dict(sorted(by_floor.items())))
    for (z, x, y), n in hits.most_common(a.top):
        mix = [(name(g), c) for g, c in others[(z, x, y)].most_common(6)]
        print(f"z{z} block {x},{y}: {n} tiles   {mix}")


if __name__ == "__main__":
    main()
