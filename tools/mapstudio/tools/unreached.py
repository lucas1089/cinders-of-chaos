"""Walkable tiles a player cannot reach, grouped into pockets, with what blocks each pocket's rim.

python -B run.py tools/unreached.py <area.txt> [--min 4] [--landmass 30]
Also prints the landmasses (4-connected non-liquid ground tiles of the main floor, mountains included) of
--landmass+ tiles that hold no reached tile at all, and the floor 6 (and above) unreached share.
Uses gen/access.py's walk rules (ramp directions from the kit named in the area header, or --kit).
"""
from __future__ import annotations

import argparse
import sys
from collections import Counter, deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gen"))

import access  # noqa: E402
from common import load_area, load_items, load_kit, names_of, water_ids  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument("area")
    p.add_argument("--min", type=int, default=4)
    p.add_argument("--kit")
    p.add_argument("--landmass", type=int, default=30)
    a = p.parse_args()
    items = load_items()
    meta, floors = load_area(a.area)
    kit = load_kit(a.kit or meta.get("kit"))
    ramp_dirs = {ids[0]: d for key in ("mountain_ramp", "hill_ramp") for d, ids in kit.get(key, {}).items()}
    access.NO_WALK = water_ids(kit)  # liquid never counts as walkable (gen/access.py NO_WALK)
    start = access.main_start(floors, items)
    got = access.reach(floors, items, ramp_dirs, start)
    layer = floors[max(floors)]
    land = {pos for pos, s in layer.items() if s and int(s[0]) not in access.NO_WALK}
    seen, lost = set(), []
    for pos in sorted(land):
        if pos in seen:
            continue
        part, q = [], deque([pos])
        seen.add(pos)
        while q:
            x, y = q.popleft()
            part.append((x, y))
            for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0)):  # 4-connected: corner contact is no way over
                nb = (x + i, y + j)
                if nb in land and nb not in seen:
                    seen.add(nb)
                    q.append(nb)
        if len(part) >= a.landmass and not any((max(floors), *t) in got for t in part):
            lost.append((len(part), min(part)))
    print(f"landmasses of {a.landmass}+ tiles with no reached tile: {lost or 'none'}")
    for z in sorted(floors, reverse=True):
        layer = floors[z]
        w = sum(1 for s in layer.values() if access.walkable(items, s))
        r = sum(1 for pos, s in layer.items() if access.walkable(items, s) and (z, *pos) in got)
        print(f"z{z}: reached {r}/{w}, unreached {100 * (w - r) / max(1, w):.1f}%")
        loose = {pos for pos, s in layer.items() if access.walkable(items, s) and (z, *pos) not in got}
        seen = set()
        for pos in sorted(loose):
            if pos in seen:
                continue
            part, q = [], deque([pos])
            seen.add(pos)
            while q:
                x, y = q.popleft()
                part.append((x, y))
                for i, j in access.STEPS:
                    nb = (x + i, y + j)
                    if nb in loose and nb not in seen:
                        seen.add(nb)
                        q.append(nb)
            if len(part) < a.min:
                continue
            rim = Counter()
            for x, y in part:
                for i, j in access.STEPS:
                    s = layer.get((x + i, y + j))
                    if s and not access.walkable(items, s):
                        for it in s:
                            if access.blocks(items, it):
                                rim[(names_of(int(it)) or [str(int(it))])[0]] += 1
            print(f"z{z} pocket of {len(part)} at {min(part)}: blocked by {rim.most_common(4)}")


if __name__ == "__main__":
    main()

