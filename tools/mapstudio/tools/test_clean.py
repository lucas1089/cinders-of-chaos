"""Checks lib.clean on random and adversarial masks: it settles, leaves no pinched outside tile and no isolated
region tile. python -B run.py tools/test_clean.py"""
from __future__ import annotations

import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gen"))

from lib import clean, pinched  # noqa: E402


def check(mask):
    size = len(mask)
    at = lambda x, y: 0 <= x < size and 0 <= y < size and mask[y][x]
    for y in range(size):
        for x in range(size):
            if not mask[y][x] and pinched(at, x, y):
                return f"pinched outside tile at {x},{y}"
            if mask[y][x] and not (at(x, y - 1) or at(x + 1, y) or at(x, y + 1) or at(x - 1, y)):
                return f"isolated region tile at {x},{y}"
    return None


def main():
    rng = random.Random(1)
    cases = [[[(x + y) % 2 == 0 for x in range(20)] for y in range(20)]]  # checkerboard
    cases.append([[x == y or x == y + 1 for x in range(20)] for y in range(20)])  # diagonal staircase
    for density in (0.2, 0.4, 0.5, 0.6, 0.8):
        for _ in range(20):
            cases.append([[rng.random() < density for _ in range(30)] for _ in range(30)])
    t = time.time()
    bad = 0
    for k, m in enumerate(cases):
        clean(m)
        err = check(m)
        if err:
            bad += 1
            print(f"case {k}: {err}")
    print(f"{len(cases)} cases, {bad} failing, {time.time() - t:.2f}s")


if __name__ == "__main__":
    main()
