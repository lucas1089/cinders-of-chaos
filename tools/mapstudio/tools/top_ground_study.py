"""Which grounds make raised tops, by place on the top: rim tiles (a rim piece), cliff-foot tiles (a cliff piece
of the level above), and inner tiles.

python -B run.py tools/top_ground_study.py <area dirs...> [--floors 4,5,6]
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import kit_ids, load_area, load_families, load_kit

RIM = kit_ids(load_kit(), "top_rim")
CLIFF = kit_ids(load_kit(), "mountain_cliff")
FILL = kit_ids(load_kit(), "mountain")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("areas", nargs="+")
    p.add_argument("--floors", default="4,5,6")
    a = p.parse_args()
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    name = lambda f: fam["grounds"].get(f, {}).get("name", f)
    floors = [int(z) for z in a.floors.split(",")]
    counts = defaultdict(Counter)
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        for z in floors:
            for s in area.get(z, {}).values():
                if not s or int(s[0]) in FILL or int(s[0]) not in family:
                    continue
                ids = {int(v) for v in s}
                place = "cliff foot" if ids & CLIFF else "rim" if ids & RIM else "inner"
                counts[(z, place)][family[int(s[0])]] += 1
    for z in floors:
        for place in ("rim", "cliff foot", "inner"):
            c = counts[(z, place)]
            t = sum(c.values())
            if t:
                print(f"z{z} {place:10} {t:5}: " + ", ".join(f"{name(f)} {n / t:.2f}" for f, n in c.most_common(5)))


if __name__ == "__main__":
    main()
