"""Picture of ground families, one row per family (lead first, then its members), to check the grouping by eye.

python -B run.py tools/family_sheet.py [G<lead> ...] [--top 24] [--out study/family_sheet.png]
Without families named, shows the --top most used families (uses come from build_families.py --count).
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from common import ROOT, SpriteCache, item_image, load_families, load_items


def main():
    p = argparse.ArgumentParser()
    p.add_argument("families", nargs="*")
    p.add_argument("--top", type=int, default=24)
    p.add_argument("--most", type=int, default=12, help="members shown per row")
    p.add_argument("--out", type=Path, default=ROOT / "study" / "family_sheet.png")
    a = p.parse_args()
    fam, items, cache = load_families()["grounds"], load_items(), SpriteCache()
    keys = a.families or sorted(fam, key=lambda k: -fam[k].get("uses", 0))[:a.top]
    cell, label = 40, 230
    sheet = Image.new("RGB", (label + cell * a.most, cell * len(keys)), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for row, key in enumerate(keys):
        g = fam[key]
        members = [g["lead"]] + [i for i in g["members"] if i != g["lead"]]
        draw.text((4, row * cell + 4), f"{key} ({len(members)})", fill=(235, 235, 235))
        draw.text((4, row * cell + 20), str(g.get("name", ""))[:34], fill=(160, 160, 160))
        for k, i in enumerate(members[:a.most]):
            if i in items:
                im = item_image(items[i], cache)
                tile = im.crop((im.width - 32, im.height - 32, im.width, im.height))
                sheet.paste(tile, (label + k * cell + 4, row * cell + 4), tile)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
