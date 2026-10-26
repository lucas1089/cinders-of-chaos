"""How raised ground is shaped in reference windows: levels, terrace widths, tops, outlines, cliff plants.

python -B run.py tools/relief_study.py <refs/...> [...]
Height of a column = 7 - the highest floor holding a tile there (same x, y). Prints per level: tile share,
patch count and sizes, how far the level's edge sits inside the level below (terrace width), the top
grounds and the items on tops, how straight the outlines run, and what grows on cliff-piece tiles.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict, deque
from pathlib import Path

from common import kind_of, load_area, load_families, load_items, names_of

N4 = [(0, -1), (1, 0), (0, 1), (-1, 0)]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("refs", nargs="+")
    a = p.parse_args()
    fam = load_families()
    family = {i: key for key, g in fam["grounds"].items() for i in g["members"]}
    cliff_ids = {i for c in fam["cliffs"].values() for ids in c["pieces"].values() for i, _ in ids}
    items = load_items()

    def kind(i):
        o = items.get(i)
        return kind_of(o["flags"]) if o else "?"

    share, patches, terrace, tops, top_items, straight = (Counter(), defaultdict(list), defaultdict(Counter),
                                                          defaultdict(Counter), defaultdict(Counter), Counter())
    cliff_plants, cliff_tiles = Counter(), 0
    for ref in a.refs:
        _, area = load_area(Path(ref) / "area.txt")
        height, top_stack = {}, {}
        for z in sorted(area, reverse=True):          # 7 first, so higher floors overwrite
            for pos, s in area[z].items():
                if s and kind(int(s[0])) == "ground":
                    height[pos] = 7 - z
                    top_stack[pos] = s
        for pos, h in height.items():
            share[h] += 1
            tops[h][family.get(int(top_stack[pos][0]), int(top_stack[pos][0]))] += 1
            for i in {int(v) for v in top_stack[pos][1:]}:
                if kind(i) in ("decor", "bottom", "wall") and i not in cliff_ids:
                    top_items[h][i] += 1
        for pos, s in area.get(7, {}).items():
            ids = {int(v) for v in s}
            if ids & cliff_ids:
                cliff_tiles += 1
                for i in ids - cliff_ids:
                    if kind(i) in ("decor", "bottom", "wall"):
                        cliff_plants[i] += 1
        for k in range(1, 5):
            mask = {pos for pos, h in height.items() if h >= k}
            seen = set()
            for start in mask:
                if start in seen:
                    continue
                part, q = 0, deque([start])
                seen.add(start)
                while q:
                    x, y = q.popleft()
                    part += 1
                    for dx, dy in N4:
                        n = (x + dx, y + dy)
                        if n in mask and n not in seen:
                            seen.add(n)
                            q.append(n)
                patches[k].append(part)
            # terrace width: for edge tiles of level k+1, distance to the nearest tile below level k
            if k >= 2:
                lower = {pos for pos, h in height.items() if h < k - 1}
                for (x, y) in mask:
                    if any((x + dx, y + dy) not in mask for dx, dy in N4):
                        d = next((r for r in range(1, 9) if any((x + i, y + j) in lower
                                  for i in range(-r, r + 1) for j in range(-r, r + 1))), 9)
                        terrace[k][d] += 1
            # outline straightness: edge tiles whose two along-edge neighbours are edge tiles with the same side
            for (x, y) in mask:
                for dx, dy in N4:
                    if (x + dx, y + dy) in mask:
                        continue
                    run = all((x + s * dy, y + s * dx) in mask and (x + s * dy + dx, y + s * dx + dy) not in mask
                              for s in (-1, 1, -2, 2))
                    straight[(k, run)] += 1
    total = sum(share.values())
    print("height share:", {h: round(n / total, 3) for h, n in sorted(share.items())})
    for k in sorted(patches):
        sizes = sorted(patches[k], reverse=True)
        if not sizes:
            continue
        runs = straight[(k, True)] / max(1, straight[(k, True)] + straight[(k, False)])
        print(f"level >= {k}: {len(sizes)} patches, sizes {sizes[:8]} ... median {sizes[len(sizes) // 2]}; "
              f"edges in straight runs of 5: {runs:.2f}")
        if terrace[k]:
            t = terrace[k]
            print(f"   terrace width (edge of level {k} to below level {k - 1}):",
                  {d: round(n / sum(t.values()), 2) for d, n in sorted(t.items())})
    for h in sorted(tops):
        if h == 0:
            continue
        n = share[h]
        print(f"tops at height {h}: grounds", [(g, round(c / n, 2), fam['grounds'].get(g, {}).get('name', '?'))
                                              for g, c in tops[h].most_common(4)])
        print("   items", [(i, round(c / n, 3), names_of(i)[:1]) for i, c in top_items[h].most_common(10)])
    print(f"cliff tiles on z7: {cliff_tiles}; plants on them:",
          [(i, round(c / max(cliff_tiles, 1), 3), names_of(i)[:1]) for i, c in cliff_plants.most_common(10)])


if __name__ == "__main__":
    main()
