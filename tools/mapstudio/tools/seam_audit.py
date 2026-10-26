"""Seams between different grounds: how often a border covers them, per pair of ground families.

python -B run.py tools/seam_audit.py <area dirs...> [--top 25] [--pair G1,G2]
A seam = two 4-neighbour tiles on one floor whose grounds belong to different families. It is covered when
either tile carries a border-kind item or a cliff piece. Prints per pair: seams, share bare, and (with
--pair) which border items lie on each side, to learn the set the reference map uses.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import kind_of, load_area, load_families, load_items, names_of



def sides_of(piece):
    kind, _, d = piece.partition("_")
    return set(d) if kind in ("edge", "inner") else set()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("areas", nargs="+")
    p.add_argument("--top", type=int, default=25)
    p.add_argument("--pair")
    a = p.parse_args()
    fam = load_families()
    family = {i: k for k, g in fam["grounds"].items() for i in g["members"]}
    name = lambda f: fam["grounds"].get(f, {}).get("name", f)
    items = load_items()
    # piece names of every known set: which sides a piece covers (edge_e: e; inner_ne: n and e; outer: none)
    facing = {}
    for table in (fam["borders"], fam["cliffs"]):
        for b in table.values():
            for pname, ids in b["pieces"].items():
                for i, _ in ids:
                    facing.setdefault(i, set()).update(sides_of(pname))
    for s in fam["piece_sets"].values():
        for pname, i in s["pieces"].items():
            facing.setdefault(i, set()).update(sides_of(pname))

    def kind(i):
        o = items.get(int(i))
        return kind_of(o["flags"]) if o else "?"

    seams, bare = Counter(), Counter()
    sides = defaultdict(Counter)
    want = tuple(sorted(a.pair.split(","))) if a.pair else None
    for path in a.areas:
        _, area = load_area(Path(path) / "area.txt")
        for z, layer in area.items():
            for (x, y), s in layer.items():
                if not s or kind(s[0]) != "ground":
                    continue
                f = family.get(int(s[0]), f"id{int(s[0])}")
                for dx, dy, here, there in ((1, 0, "e", "w"), (0, 1, "s", "n")):
                    t = layer.get((x + dx, y + dy))
                    if not t or kind(t[0]) != "ground":
                        continue
                    g = family.get(int(t[0]), f"id{int(t[0])}")
                    if f == g:
                        continue
                    pair = tuple(sorted((f, g)))
                    seams[pair] += 1
                    # covered: a piece on this tile facing the neighbour, or on the neighbour facing back; an
                    # unknown border or wall item counts as covering (no direction known)
                    covered = any(here in facing[int(i)] if int(i) in facing else kind(i) in ("border", "wall")
                                  for i in s[1:]) or \
                        any(there in facing[int(i)] if int(i) in facing else kind(i) in ("border", "wall")
                            for i in t[1:])
                    if not covered:
                        bare[pair] += 1
                    if pair == want:
                        for fam_, stack in ((f, s), (g, t)):
                            for i in stack[1:]:
                                if kind(i) in ("border", "wall"):
                                    sides[fam_][int(i)] += 1
    print(f"{'pair':58} seams  bare")
    for pair, n in seams.most_common(a.top):
        print(f"{name(pair[0])[:27]:27} | {name(pair[1])[:27]:27} {n:6} {bare[pair] / n:5.2f}")
    for fam_, c in sides.items():
        print(f"on {name(fam_)} tiles:", [(i, n, names_of(i)[:1]) for i, n in c.most_common(10)])


if __name__ == "__main__":
    main()
