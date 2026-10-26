"""The yardstick: a reference window and a generated window of the same size, rendered at the same scale, side by
side, with their numbers underneath.

python -B run.py tools/side_by_side.py <reference area.txt> <x,y> <ours area.txt> <x,y> [--size 48] [--scale 0.75]
    [--out study/compare/<name>.png]
x,y is each window's top-left tile. Floors above 7 are drawn (as the client shows them).
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw

from common import ROOT, kind_of, load_area, load_items
from render import render


def numbers(area, x1, y1, x2, y2, items):
    layer = area.get(7, {})
    tiles = [(x, y) for y in range(y1, y2 + 1) for x in range(x1, x2 + 1) if (x, y) in layer]
    kinds, ids = Counter(), set()
    for z, lay in area.items():
        for y in range(y1, y2 + 1):
            for x in range(x1, x2 + 1):
                for i in lay.get((x, y), []):
                    ids.add(int(i))
    for t in tiles:
        for i in layer[t][1:]:
            o = items.get(int(i))
            kinds[kind_of(o["flags"]) if o else "?"] += 1
    n = max(1, len(tiles))
    grounds = len({int(layer[t][0]) for t in tiles})
    return (f"ids {len(ids)}  grounds {grounds}  items/tile {sum(kinds.values()) / n:.2f}  "
            f"border {kinds['border'] / n:.2f}  plants {(kinds['bottom'] + kinds['decor'] + kinds['wall'] + kinds['container']) / n:.2f}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("ref")
    p.add_argument("ref_at")
    p.add_argument("ours")
    p.add_argument("ours_at")
    p.add_argument("--size", type=int, default=48)
    p.add_argument("--scale", type=float, default=0.75)
    p.add_argument("--out", type=Path, default=ROOT / "study" / "compare" / "side_by_side.png")
    a = p.parse_args()
    items = load_items()
    panels = []
    for path, at in ((a.ref, a.ref_at), (a.ours, a.ours_at)):
        _, area = load_area(path)
        x1, y1 = map(int, at.split(","))
        x2, y2 = x1 + a.size - 1, y1 + a.size - 1
        floors = [7] + [z for z in area if z < 7]
        img = render(area, x1, y1, x2, y2, floors, a.scale, False, False, None, camera=7).convert("RGB")
        panels.append((img, f"{Path(path).parent.name} @ {x1},{y1}", numbers(area, x1, y1, x2, y2, items)))
    w, h = panels[0][0].size
    sheet = Image.new("RGB", (w * 2 + 16, h + 44), (30, 30, 30))
    draw = ImageDraw.Draw(sheet)
    for k, (img, title, nums) in enumerate(panels):
        sheet.paste(img, (k * (w + 16), 0))
        draw.text((k * (w + 16) + 4, h + 4), title, fill="white")
        draw.text((k * (w + 16) + 4, h + 22), nums, fill=(200, 220, 255))
    a.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print(a.out)
    for _, title, nums in panels:
        print(f"  {title}: {nums}")


if __name__ == "__main__":
    main()
