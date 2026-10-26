"""Shape lab: scores outline treatments against the reference map's outline signature (tools/outline_study.py: about 0.30
edge, 0.34 inner, 0.34 outer pieces, almost no 4+ runs of one edge piece).

python -B run.py tools/shape_lab.py [--seeds 6] [--size 96]
Each treatment turns noise blobs into masks; the outline is scored with the same piece logic gen uses.
"""
from __future__ import annotations

import argparse
import random
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gen"))

from shapes import blend, region  # noqa: E402
from lib import DIAG, N4, clean, roughen  # noqa: E402
import lib  # noqa: E402

TARGET = {"edge": 0.30, "inner": 0.34, "outer": 0.34, "runs": 0.02}


def score(mask):
    size = len(mask)
    c, runs = Counter(), Counter()
    names = {}
    for y in range(size):
        for x in range(size):
            if mask[y][x]:
                continue
            ps = lib.edge_pieces(mask, x, y, {k: k for k in [f"edge_{d}" for d in "nesw"] +
                                              [f"{t}_{a}{b}" for t in ("inner", "outer") for a in "ns" for b in "we"]})
            for name in ps:
                c[name.split("_")[0]] += 1
                names.setdefault(name, set()).add((x, y))
    for name, tiles in names.items():
        if not name.startswith("edge"):
            continue
        horiz = name in ("edge_n", "edge_s")
        for x, y in tiles:
            line = [(x + k, y) if horiz else (x, y + k) for k in range(-3, 4)]
            longest = cur = 0
            for t in line:
                cur = cur + 1 if t in tiles else 0
                longest = max(longest, cur)
            runs["long" if longest >= 4 else "short"] += 1
    t = max(1, sum(c.values()))
    out = {k: c[k] / t for k in ("edge", "inner", "outer")}
    out["runs"] = runs["long"] / max(1, runs["long"] + runs["short"])
    return out


def chamfer(mask, rng, passes=1, p=1.0):
    """Majority smoothing on 8 neighbours: a region tile with 3 or fewer region neighbours leaves (cuts a
    convex corner), an outside tile with 5 or more joins (fills a concave one); then clean."""
    size = len(mask)
    for _ in range(passes):
        flips = []
        for y in range(size):
            for x in range(size):
                n = sum(mask[y + j][x + i] for i in (-1, 0, 1) for j in (-1, 0, 1)
                        if (i or j) and 0 <= x + i < size and 0 <= y + j < size)
                if (mask[y][x] and n <= 3 or not mask[y][x] and n >= 5) and rng.random() < p:
                    flips.append((x, y))
        for x, y in flips:
            mask[y][x] = not mask[y][x]
        clean(mask)


def rotated_field(size, rng, cell):
    """Value noise on a lattice turned 45 degrees: its contours favour diagonal staircases."""
    big = blend(size * 2, rng, [(cell, 1.0)])
    return [[big[(x + y) // 2 + size // 2][(x - y) // 2 + size // 2] for x in range(size)] for y in range(size)]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--seeds", type=int, default=6)
    p.add_argument("--size", type=int, default=96)
    a = p.parse_args()
    size = a.size
    treatments = {
        "plain": lambda m, r: None,
        "roughen (gen)": lambda m, r: roughen(m, r),
        "breaker only": lambda m, r: lib.break_runs(m, r),
        "roughen grow": lambda m, r: roughen(m, r, mode="grow"),
    }

    def jitter(amount):
        def make(r):
            f = blend(size, r, [(12, 0.6), (5, 0.4)])
            return [[v + amount * (r.random() - 0.5) for v in row] for row in f]
        return make

    fields = {"plain noise": lambda r: blend(size, r, [(12, 0.6), (5, 0.4)]),
              "jitter .15": jitter(0.15), "jitter .3": jitter(0.3),
              "cell2 mix": lambda r: blend(size, r, [(12, 0.5), (5, 0.3), (2, 0.2)])}
    print(f"target {TARGET}")
    for fname, make in fields.items():
        for tname, treat in treatments.items():
            acc = Counter()
            for s in range(a.seeds):
                r = random.Random(s)
                f = make(r)
                mask = region(size, f, 0.55, lambda x, y: 2 <= x < size - 2 and 2 <= y < size - 2)
                treat(mask, r)
                for k, v in score(mask).items():
                    acc[k] += v / a.seeds
            err = sum(abs(acc[k] - TARGET[k]) for k in TARGET)
            print(f"{fname:12} {tname:18} edge {acc['edge']:.2f} inner {acc['inner']:.2f} outer {acc['outer']:.2f} "
                  f"runs4 {acc['runs']:.2f}   error {err:.2f}")


if __name__ == "__main__":
    main()
