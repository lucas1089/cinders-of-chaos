"""Learns a biome kit from reference windows: which ground families make the surface, which pairs touch and with
which border, and what grows on each family.

python -B run.py tools/learn_kit.py <refs/...> [...] [--out study/<name>_kit.json]
Ground ids are grouped into families with the studio's families.json; border ownership comes from its
borders table (BG<owner>/G<onto>), counted here by what the refs actually draw.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import ROOT, kind_of, load_area, load_families, load_items, names_of, write_json

N8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("refs", nargs="+")
    p.add_argument("--out", type=Path, default=ROOT / "study" / "kit_learned.json")
    p.add_argument("--floors", default="7", help="floors to read, e.g. 7 or 9-14 (caves are 8-15)")
    a = p.parse_args()
    lo, _, hi = a.floors.partition("-")
    floors = range(int(lo), int(hi or lo) + 1)
    fam = load_families()
    family = {i: key for key, g in fam["grounds"].items() for i in g["members"]}
    border_ids = {}  # item id -> border key, from the borders table's piece ids
    for key, b in fam["borders"].items():
        for ids in b["pieces"].values():
            for i, _ in ids:
                border_ids.setdefault(i, key)
    items = load_items()

    def kind(i):
        o = items.get(i)
        return kind_of(o["flags"]) if o else "?"

    tiles, ground_ids = Counter(), defaultdict(Counter)
    pairs, drawn = Counter(), Counter()
    flora = defaultdict(Counter)
    layers = []
    for ref in a.refs:
        _, area = load_area(Path(ref) / "area.txt")
        layers += [area[z] for z in floors if z in area]
    for layer in layers:
        fams = {pos: family.get(int(s[0]), f"G{int(s[0])}") for pos, s in layer.items()}
        for (x, y), s in layer.items():
            f = fams[(x, y)]
            tiles[f] += 1
            ground_ids[f][int(s[0])] += 1
            for dx, dy in N8:
                g = fams.get((x + dx, y + dy))
                if g and g != f:
                    pairs[tuple(sorted((f, g)))] += 1
            for i in {int(v) for v in s[1:]}:
                if i in border_ids:
                    drawn[border_ids[i]] += 1
                elif kind(i) in ("decor", "wall", "bottom", "container"):  # The reference map's jungle trees are containers
                    flora[f][i] += 1
    total = sum(tiles.values())
    out = {"refs": a.refs, "tiles": total, "families": {}, "pairs": {}, "borders": {}}
    print(f"{total} tiles")
    print("families:")
    for f, n in tiles.most_common(15):
        name = fam["grounds"].get(f, {}).get("name", "?")
        top = flora[f].most_common(24)
        out["families"][f] = {"name": name, "share": round(n / total, 4),
                              "ids": dict(ground_ids[f].most_common()),
                              "flora": {str(i): round(c / n, 4) for i, c in top}}
        print(f"  {f:9} {n / total:6.3f} {name:28} ids {len(ground_ids[f])}")
        for i, c in top[:16]:
            print(f"      {i:7} {c / n:6.3f} {kind(i):7} {names_of(i)[:1]}")
    print("touching pairs (tile-neighbour counts) and the borders the refs draw for them:")
    for (f, g), n in pairs.most_common(20):
        keys = [k for k in (f"B{f}/{g}", f"B{g}/{f}") if k in fam["borders"]]
        use = {k: drawn[k] for k in keys}
        out["pairs"][f"{f}|{g}"] = {"touch": n, "borders": use}
        print(f"  {f:9} {g:9} {n:6}  {use}")
    for k, n in drawn.most_common():
        out["borders"][k] = n
    write_json(a.out, out)
    print(a.out)


if __name__ == "__main__":
    main()
