"""Geometry of ramp pieces over the whole reference map.

python -B run.py tools/ramp_check.py <ramp id>:<lower half id> [...] [--map <map>]
Per ramp: ground under it, grounds of its 4 neighbours on the same floor, where the lower half sits, the
ground below the lower half, and what the floor above holds at the ramp and at each neighbour.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict

from common import iter_tiles

N4 = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}


def load_floors(floors, map_dir=None):
    out = defaultdict(dict)
    for z, x, y, ids in iter_tiles(map_dir, floors):
        out[z][(x, y)] = [int(i) for i in ids]
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("pairs", nargs="+")
    p.add_argument("--map", help="default: the reference map")
    a = p.parse_args()
    pairs = [tuple(int(v) for v in s.split(":")) for s in a.pairs]
    world = load_floors(range(16), a.map)
    for ramp, lower in pairs:
        under, side, half, above, n = Counter(), {d: Counter() for d in N4}, Counter(), Counter(), 0
        for z, layer in world.items():
            up = world.get(z - 1, {})
            for (x, y), ids in layer.items():
                if ramp not in ids:
                    continue
                n += 1
                under[ids[0]] += 1
                for d, (dx, dy) in N4.items():
                    t = layer.get((x + dx, y + dy))
                    side[d][t[0] if t else 0] += 1
                    if t and lower in t:
                        half[d] += 1
                    u = up.get((x + dx, y + dy))
                    above[f"{d}:{u[0] if u else 0}"] += 1
                u = up.get((x, y))
                above[f"same:{u[0] if u else 0}" + (f"+{u[1:]}" if u and len(u) > 1 else "")] += 1
        print(f"== ramp {ramp} (lower {lower}): {n}")
        print("  under", under.most_common(3), " lower half at", dict(half))
        for d in N4:
            print(f"  side {d}", side[d].most_common(3))
        print("  above", above.most_common(10))


if __name__ == "__main__":
    main()
