"""How outlines are shaped, read from the 12-piece sets drawn along them: the share of straight edge pieces,
inner corners (two sides) and outer corners (diagonal only). Square outlines are mostly edges; the reference map's
staircase outlines carry many corners. Also the share of edge pieces in straight runs of 4+ same pieces.

python -B run.py tools/outline_study.py <area dirs...> [--floors 4,5,6,7]
Sets come from the kit (--kit, default the configured one): every 12-piece set named in SETS that the kit has.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from pathlib import Path

from common import load_area, load_kit

SETS = ("shore_on_base", "base_on_sand", "mountain_cliff", "top_rim", "grey_on_sand", "rock_on_gravel", "edge_on_lava", "edge_on_rock")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("areas", nargs="+")
    p.add_argument("--floors", default="4,5,6,7")
    p.add_argument("--kit")
    a = p.parse_args()
    kit = load_kit(a.kit)
    piece = {}
    for s in [s for s in SETS if s in kit]:
        for name, i in kit[s].items():
            piece[int(i)] = (s, name)
    counts, runs = defaultdict(Counter), defaultdict(Counter)
    floors = [int(z) for z in a.floors.split(",")]
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        for z in floors:
            layer = area.get(z, {})
            at = defaultdict(set)
            for pos, stack in layer.items():
                for i in stack:
                    if int(i) in piece:
                        s, name = piece[int(i)]
                        counts[s][name.split("_")[0]] += 1
                        at[(s, name)].add(pos)
            for (s, name), tiles in at.items():
                if not name.startswith("edge"):
                    continue
                horiz = name in ("edge_n", "edge_s")
                for x, y in tiles:
                    line = [(x + k, y) if horiz else (x, y + k) for k in range(-3, 4)]
                    longest, cur = 0, 0
                    for t in line:
                        cur = cur + 1 if t in tiles else 0
                        longest = max(longest, cur)
                    runs[s]["long" if longest >= 4 else "short"] += 1
    for s in SETS:
        c = counts[s]
        t = sum(c.values())
        if not t:
            continue
        r = runs[s]
        print(f"{s:15} {t:6} pieces: edge {c['edge'] / t:.2f} inner {c['inner'] / t:.2f} outer {c['outer'] / t:.2f}"
              f"   edges in runs of 4+: {r['long'] / max(1, r['long'] + r['short']):.2f}")


if __name__ == "__main__":
    main()
