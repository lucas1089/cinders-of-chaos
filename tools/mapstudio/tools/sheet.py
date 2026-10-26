"""Labelled sheet of item sprites: python -B run.py tools/sheet.py <out.png> <id> [<id> ...]"""
from __future__ import annotations

import sys

from PIL import Image, ImageDraw

from common import SpriteCache, item_image, load_items, names_of


def main():
    out, ids = sys.argv[1], [int(v) for v in sys.argv[2:]]
    items, cache = load_items(), SpriteCache()
    cell = 112
    img = Image.new("RGBA", (cell * len(ids), cell + 28), (40, 40, 40, 255))
    draw = ImageDraw.Draw(img)
    for k, i in enumerate(ids):
        o = items.get(i)
        if o:
            im = item_image(o, cache)
            img.alpha_composite(im, (k * cell + cell - im.width, cell - im.height))
            g = o["groups"][0]
            draw.text((k * cell + 2, cell + 2), f"{i} {g['width']}x{g['height']}", fill="white")
            draw.text((k * cell + 2, cell + 14), ("walk " if "not_walkable" not in o["flags"] else "") +
                      (names_of(i) or [""])[0][:12], fill="white")
        else:
            draw.text((k * cell + 2, cell + 2), f"{i} missing", fill="red")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
