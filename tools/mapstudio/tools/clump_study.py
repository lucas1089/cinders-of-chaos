"""How plants clump on a ground family: the distribution of local density, by distance to the nearest edge.

python -B run.py tools/clump_study.py <G-family> <area dirs...> [--window 5] [--out study/<name>.json]
Local density at a tile = plant bases of a class in the window x window square around it / window^2.
Classes: big (multi-tile walls and containers: palms, ferns, bushes) and small (1x1 tufts, debris, leaves).
Prints, per edge-distance bucket, the share of tiles and the density quantiles; --out saves the quantile
tables gen uses to reproduce the same clumping (quantile matching of a noise field).
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict, deque
from pathlib import Path

from common import kind_of, kit_ids, load_area, load_families, load_items, load_kit, write_json

N4 = [(0, -1), (1, 0), (0, 1), (-1, 0)]
BUCKETS = [(1, 1), (2, 3), (4, 6), (7, 99)]
CLIFF = kit_ids(load_kit(), "mountain_cliff")


def bucket(d):
    return next(k for k, (lo, hi) in enumerate(BUCKETS) if lo <= d <= hi)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("family")
    p.add_argument("areas", nargs="+")
    p.add_argument("--window", type=int, default=5)
    p.add_argument("--out", type=Path)
    p.add_argument("--floor", default="7", help="a floor or a range, e.g. 9-15")
    p.add_argument("--exclude", default="", help="item id ranges that are not plants, e.g. <id>-<id>,<id>-<id>")
    a = p.parse_args()
    lo, _, hi = str(a.floor).partition("-")
    floors = range(int(lo), int(hi or lo) + 1)
    skip = set()
    for part in filter(None, a.exclude.split(",")):
        s, _, e = part.partition("-")
        skip |= set(range(int(s), int(e or s) + 1))
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    items = load_items()
    samples = {c: defaultdict(list) for c in ("big", "small")}
    r = a.window // 2
    layers = []
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        layers += [area[z] for z in floors if z in area]
    for layer in layers:
        own = {pos for pos, s in layer.items() if family.get(int(s[0])) == a.family}
        bases = {"big": set(), "small": set()}
        for pos, s in layer.items():
            for i in {int(v) for v in s[1:]}:
                o = items.get(i)
                if not o or i in CLIFF or i in skip or kind_of(o["flags"]) not in ("decor", "bottom", "wall", "container"):
                    continue
                g = o["groups"][0]
                bases["big" if g["width"] * g["height"] > 1 else "small"].add(pos)
        dist, q = {}, deque()
        for pos in layer:
            if pos not in own:
                dist[pos] = 0
                q.append(pos)
        while q:
            x, y = q.popleft()
            for dx, dy in N4:
                nb = (x + dx, y + dy)
                if nb in layer and nb not in dist:
                    dist[nb] = dist[(x, y)] + 1
                    q.append(nb)
        for (x, y) in own:
            win = [(x + i, y + j) for i in range(-r, r + 1) for j in range(-r, r + 1)]
            inside = [t for t in win if t in layer]
            for c in ("big", "small"):
                samples[c][bucket(dist.get((x, y), 99))].append(sum(t in bases[c] for t in inside) / len(inside))
    out = {"family": a.family, "window": a.window, "buckets": BUCKETS, "quantiles": {}}
    total = sum(len(v) for v in samples["big"].values())
    for c in ("big", "small"):
        out["quantiles"][c] = {}
        print(f"== {c}")
        for b in sorted(samples[c]):
            v = sorted(samples[c][b])
            qs = [round(v[min(len(v) - 1, int(len(v) * k / 20))], 3) for k in range(21)]
            out["quantiles"][c][str(b)] = qs
            print(f"  edge {BUCKETS[b]} share {len(v) / total:.2f} mean {sum(v) / len(v):.3f} "
                  f"zero {sum(1 for d in v if d == 0) / len(v):.2f}  q25/50/75/95 {qs[5]} {qs[10]} {qs[15]} {qs[19]}")
    if a.out:
        write_json(a.out, out)
        print(a.out)


if __name__ == "__main__":
    main()
