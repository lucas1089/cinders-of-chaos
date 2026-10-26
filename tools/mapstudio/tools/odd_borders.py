"""Tiles whose border pieces of one 12-piece set face opposite ways (e.g. a north edge with a south-east outer
corner): the signature of a strip of ground too thin for the set, where the pieces pile up and look broken.

python -B run.py tools/odd_borders.py <area dirs...> [--show 10]
Sets: every 12-piece set of the kit (--kit; default the one named in the first area's header). Prints per set: tiles with any piece, odd tiles, share, and a few positions.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from pathlib import Path

from common import load_area, load_kit

SETS = ("shore_on_base", "base_on_sand", "grey_on_sand", "rock_on_gravel", "gravel_border", "mountain_cliff",
        "hill_cliff", "top_rim", "hill_rim")
OPPOSITE = {"n": "s", "s": "n", "e": "w", "w": "e"}


def faces(piece):
    kind, _, d = piece.partition("_")
    return set(d)


def odd(names):
    dirs = [faces(n) for n in names]
    return any(OPPOSITE[a] in other for i, f in enumerate(dirs) for a in f for other in dirs[i + 1:])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("areas", nargs="+")
    p.add_argument("--show", type=int, default=6)
    p.add_argument("--kit")
    a = p.parse_args()
    kit = load_kit(a.kit or load_area(Path(a.areas[0]) / "area.txt")[0].get("kit"))
    sets = [s for s, v in kit.items() if isinstance(v, dict) and "edge_n" in v and "inner_se" in v]
    piece = {int(i): (s, n) for s in sets for n, i in kit[s].items()}
    tiles, bad, where = Counter(), Counter(), defaultdict(list)
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        for z, layer in area.items():
            for pos, stack in layer.items():
                by_set = defaultdict(list)
                for i in stack:
                    if int(i) in piece:
                        s, n = piece[int(i)]
                        by_set[s].append(n)
                for s, names in by_set.items():
                    tiles[s] += 1
                    if odd(names):
                        bad[s] += 1
                        where[s].append((Path(path).name, z, *pos))
    for s in sets:
        if tiles[s]:
            print(f"{s:15} {tiles[s]:6} tiles, odd {bad[s]:4} ({bad[s] / tiles[s]:.3f})  {where[s][:a.show]}")


if __name__ == "__main__":
    main()
