"""A 1-pixel-per-tile minimap of a map folder's floor, for finding areas worth studying.

python -B run.py tools/minimap.py [<map>] [--floor 7] [--out minimap.png]   (default map: the reference map)
Colour per tile: the mean colour of its ground sprite (top floors hide nothing; one floor only).
Prints the occupied bounds.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from common import ROOT, SpriteCache, item_image, iter_tiles, load_items


def main():
    p = argparse.ArgumentParser()
    p.add_argument("map", nargs="?")
    p.add_argument("--floor", type=int, default=7)
    p.add_argument("--out", type=Path, default=ROOT / "study" / "minimap.png")
    a = p.parse_args()
    items, cache, colour = load_items(), SpriteCache(), {}
    tiles = {}
    for z, x, y, ids in iter_tiles(a.map, {a.floor}):
        tiles[(x, y)] = int(ids[0])
    xs, ys = [x for x, _ in tiles], [y for _, y in tiles]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    print(f"floor {a.floor}: {len(tiles)} tiles, bounds {x0},{y0} - {x1},{y1}")
    img = Image.new("RGB", (x1 - x0 + 1, y1 - y0 + 1))
    px = img.load()
    for (x, y), i in tiles.items():
        if i not in colour:
            obj = items.get(i)
            c = (255, 0, 255)
            if obj:
                im = item_image(obj, cache).convert("RGBA").resize((1, 1), Image.BOX)
                c = im.getpixel((0, 0))[:3]
            colour[i] = c
        px[x - x0, y - y0] = colour[i]
    a.out.parent.mkdir(parents=True, exist_ok=True)
    img.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
