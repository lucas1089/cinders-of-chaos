"""Names the pieces of a border/cliff set from where the reference map lays them: for every id in a range, the ground it lies
on, the family it borders (the commonest other family around it) and, from the directions that family lies in,
its piece name (edge_<d>: the family on side d; inner_<dd>: on two adjacent sides; outer_<dd>: only on that
diagonal).

python -B run.py tools/name_set.py <first id> <last id> <refs...> [--floors 9-15] [--json]
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import load_area, load_families

SIDES = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}
DIAGS = {"nw": (-1, -1), "ne": (1, -1), "sw": (-1, 1), "se": (1, 1)}


def classify(owner_at):
    sides = [d for d in "nesw" if owner_at(*SIDES[d])]
    if len(sides) == 1:
        return "edge_" + sides[0]
    if len(sides) == 2 and sides[0] + sides[1] not in ("ns", "ew"):
        a, b = sorted(sides, key="nsew".index)
        return "inner_" + a + b
    if not sides:
        diag = [d for d, v in DIAGS.items() if owner_at(*v)]
        if len(diag) == 1:
            return "outer_" + diag[0]
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("first", type=int)
    p.add_argument("last", type=int)
    p.add_argument("refs", nargs="+")
    p.add_argument("--floors", default="9-15")
    p.add_argument("--json", action="store_true")
    p.add_argument("--merge", action="append", default=[],
                   help="families that count as one, e.g. lava=<id>,<id> (repeatable); families with the "
                        "same name are merged anyway")
    a = p.parse_args()
    lo, _, hi = a.floors.partition("-")
    floors = range(int(lo), int(hi or lo) + 1)
    fam = load_families()
    alias = {}
    for spec in a.merge:
        label, _, keys = spec.partition("=")
        for k in keys.split(","):
            alias[k] = label
    by_name = {}
    for k, g in fam["grounds"].items():
        by_name.setdefault(g.get("name", k), k)
    merged = lambda k: alias.get(k) or by_name.get(fam["grounds"].get(k, {}).get("name"), k)
    family = {i: merged(k) for k, g in fam["grounds"].items() for i in g["members"]}
    name = lambda f: f if f in alias.values() else fam["grounds"].get(f, {}).get("name", f)
    ids = set(range(a.first, a.last + 1))
    under, owner, shape = defaultdict(Counter), defaultdict(Counter), defaultdict(Counter)
    for ref in a.refs:
        _, area = load_area(Path(ref) / "area.txt")
        for z in floors:
            layer = area.get(z, {})
            fam_at = {pos: family.get(int(s[0])) for pos, s in layer.items() if s}
            for (x, y), s in layer.items():
                here = {int(v) for v in s} & ids
                if not here:
                    continue
                f = fam_at.get((x, y))
                around = Counter(fam_at.get((x + i, y + j)) for i in (-1, 0, 1) for j in (-1, 0, 1) if i or j)
                around.pop(f, None)
                around.pop(None, None)
                for i in here:
                    under[i][f] += 1
                    if around:
                        o = around.most_common(1)[0][0]
                        owner[i][o] += 1
                        shape[i][classify(lambda dx, dy: fam_at.get((x + dx, y + dy)) == o)] += 1
    pieces = {}
    for i in sorted(ids):
        if not under[i]:
            continue
        n = sum(under[i].values())
        best = [(s, c) for s, c in shape[i].most_common(3)]
        top = next((s for s, _ in best if s), None)
        print(f"{i}: {n:5} on {str(name(under[i].most_common(1)[0][0]))[:24]:24} borders "
              f"{name(owner[i].most_common(1)[0][0])[:24] if owner[i] else '-':24} {best}")
        if top and top not in pieces:
            pieces[top] = i
    print(f"named {len(pieces)}/12:", json.dumps(dict(sorted(pieces.items()))))


if __name__ == "__main__":
    main()
