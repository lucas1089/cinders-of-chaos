"""Where a raised floor's rim pieces sit, over refs/.

python -B run.py tools/rim_check.py <piece-set key from families.json piece_sets, or id,id,...> [--refs ...]
Per piece: the most common sets of 8 neighbours on the same floor that hold no tile (the drop), the grounds
under the piece, and what lies one floor below at the same x, y.
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
    p.add_argument("key", help="piece-set key, or comma-separated item ids (each reported under its own id)")
    p.add_argument("--refs", nargs="+", help="reference windows (default: refs/)")
    a = p.parse_args()
    if not a.key.replace(",", "").isdigit():
        fam = load_families()
        piece = {i: name for name, i in fam["piece_sets"][a.key]["pieces"].items()}
    else:
        piece = {int(i): i for i in a.key.split(",")}
    drop, under, below = defaultdict(Counter), defaultdict(Counter), defaultdict(Counter)
    for ref in [Path(r) for r in a.refs] if a.refs else sorted(DEFAULT_REFS.iterdir()):
        if not (ref / "area.txt").exists():
            continue
        _, area = load_area(ref / "area.txt")
        for z, layer in area.items():
            low = area.get(z + 1, {})
            for (x, y), ids in layer.items():
                for i in ids:
                    name = piece.get(int(i))
                    if not name:
                        continue
                    key = " ".join(d for d, (dx, dy) in DIRS.items() if (x + dx, y + dy) not in layer)
                    drop[name][key or "-"] += 1
                    under[name][int(ids[0])] += 1
                    b = low.get((x, y))
                    below[name][int(b[0]) if b else 0] += 1
    for name in sorted(drop):
        print(f"{name:9} drop {drop[name].most_common(3)}  under {under[name].most_common(2)}  below {below[name].most_common(2)}")


if __name__ == "__main__":
    main()
