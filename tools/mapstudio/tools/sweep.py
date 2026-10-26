"""Runs gen/generate.py's build() without rendering over seeds and knob values, and prints the measures that
matter for tuning: sea-cliff share of water edges, ground reached, ramps usable, mountain share.

python -B run.py tools/sweep.py --knob sea_cliffs --values 10,15,20 [--seeds 7,11,23] [--size 112]
    [--set rivers=1 lakes=2 ...]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gen"))

import generate as jungle  # noqa: E402
from common import kit_ids, load_kit  # noqa: E402

DEFAULTS = dict(size=112, seed=1, rough=70, mountains=36, levels=4, hills=4, lakes=0, rivers=0, river_width=3,
                roads=3, sand=4, vegetation=100, sea_cliffs=15)
WATER = kit_ids(load_kit(), "water")
FILL = kit_ids(load_kit(), "mountain")


def water_edges(floor):
    grass = cliff = 0
    for (x, y), s in floor.items():
        if int(s[0]) not in WATER:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            t = floor.get((x + dx, y + dy))
            if not t or int(t[0]) in WATER:
                continue
            if int(t[0]) in FILL:
                cliff += 1
            else:
                grass += 1
    return cliff / max(1, cliff + grass)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--knob", required=True)
    p.add_argument("--values", required=True)
    p.add_argument("--seeds", default="7,11,23")
    p.add_argument("--size", type=int, default=112)
    p.add_argument("--set", nargs="*", default=[])
    a = p.parse_args()
    fixed = dict(DEFAULTS, size=a.size)
    for kv in a.set:
        k, v = kv.split("=")
        fixed[k] = type(DEFAULTS[k])(float(v)) if isinstance(DEFAULTS[k], float) else type(DEFAULTS[k])(v)
    for value in a.values.split(","):
        for seed in a.seeds.split(","):
            knobs = dict(fixed, seed=int(seed))
            knobs[a.knob] = type(DEFAULTS[a.knob])(float(value))
            floors, stats = jungle.build(argparse.Namespace(**knobs))
            acc = stats["access"]
            r7 = acc["reached/walkable"].get(7, (0, 1))
            land = a.size * a.size - stats["water"]
            print(f"{a.knob}={value} seed {seed}: sea cliffs {water_edges(floors[7]):.2f}  ground reached "
                  f"{r7[0] / r7[1]:.3f}  ramps {acc['ramps_usable']}  mountains {stats['levels'][0] / land:.2f}  "
                  f"sealed {acc['pockets_sealed']}  bridges {len(stats['bridges'])}")


if __name__ == "__main__":
    main()
