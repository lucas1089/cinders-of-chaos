"""Which neighbours a piece set's pieces see in reference windows.

python -B run.py tools/piece_check.py <key> [--refs dir ...]
python -B run.py tools/piece_check.py ids:<id,id,...> --target G<family> [--refs dir ...]
<key> is a families.json key: BG<owner>/G<onto> under borders, or CG<fill> under cliffs; its target is the
owner (or fill). Prints, per piece: the most common sets of 8 neighbours holding the target family, and the
most common ground under the piece. Settles the piece naming before a set goes into a kit. Default refs: the
archive's.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import DEFAULT_REFS, load_area, load_families

DIRS = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0), "nw": (-1, -1), "ne": (1, -1), "sw": (-1, 1), "se": (1, 1)}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("key")
    p.add_argument("--target")
    p.add_argument("--refs", nargs="+")
    a = p.parse_args()
    fam = load_families()
    if a.key.startswith("ids:"):
        piece = {int(i): i for i in a.key[4:].split(",")}
        target_key = a.target
    else:
        table = fam["cliffs" if a.key.startswith("C") else "borders"][a.key]
        target_key = table.get("fill") or "G" + a.key.split("/")[0][2:]
        piece = {int(ids[0][0]): name for name, ids in table["pieces"].items()}
    target = set(fam["grounds"][target_key]["members"])
    refs = [Path(r) for r in a.refs] if a.refs else sorted(DEFAULT_REFS.iterdir())
    seen, under = defaultdict(Counter), defaultdict(Counter)
    for ref in refs:
        if not (ref / "area.txt").exists():
            continue
        _, area = load_area(ref / "area.txt")
        for layer in area.values():
            for (x, y), ids in layer.items():
                for i in ids:
                    name = piece.get(int(i))
                    if not name:
                        continue
                    key = " ".join(d for d, (dx, dy) in DIRS.items()
                                   if layer.get((x + dx, y + dy)) and int(layer[(x + dx, y + dy)][0]) in target)
                    seen[name][key or "-"] += 1
                    under[name][int(ids[0])] += 1
    print("target", target_key, "pieces", len(piece))
    for name in sorted(seen, key=str):
        print(f"{name!s:9} {seen[name].most_common(3)}  under {under[name].most_common(2)}")


if __name__ == "__main__":
    main()
