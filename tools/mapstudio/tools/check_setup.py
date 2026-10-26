"""Checks that config.json, the adapter and the data work, and shows a few items so a person can confirm the
sprites look right.

python -B run.py tools/check_setup.py
Writes study/setup_check.png: the 48 grounds the reference map uses most (or the first 48 grounds when the map
is not indexed yet), each with its id.
"""
from __future__ import annotations

from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw

from common import ROOT, SpriteCache, adapter, config, item_image, iter_tiles, kind_of, load_items, names_of


def main():
    cfg = config()
    print("adapter:", cfg.get("adapter", "otbm_dat"))
    ad = adapter()
    for key, value in cfg.items():
        if isinstance(value, str) and key not in ("adapter", "kit", "dat_format", "map_ids", "transparency"):
            path = ad.path(key) if hasattr(ad, "path") else Path(value)
            print(f"  {key:12} {'ok     ' if path and path.exists() else 'MISSING'} {path}")
    items = load_items()
    kinds = Counter(kind_of(o["flags"]) for o in items.values())
    print(f"items: {len(items)}  by kind: {dict(kinds.most_common())}")
    named = sum(1 for i in items if names_of(i))
    print(f"named items: {named} ({named / max(1, len(items)):.0%})")
    grounds = [i for i, o in items.items() if kind_of(o["flags"]) == "ground"]
    try:
        use = Counter()
        for z, x, y, ids in iter_tiles(floors={7}):
            use[ids[0]] += 1
        print(f"map floor 7: {sum(use.values())} tiles, {len(use)} distinct grounds")
        show = [i for i, _ in use.most_common(48) if i in items]
    except SystemExit as e:
        print(f"map: {e}")
        show = sorted(grounds)[:48]
    cache, cell = SpriteCache(), 72
    sheet = Image.new("RGB", (8 * cell, ((len(show) + 7) // 8) * cell), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for k, i in enumerate(show):
        img = item_image(items[i], cache)
        x, y = (k % 8) * cell, (k // 8) * cell
        sheet.paste(img.crop((img.width - 32, img.height - 32, img.width, img.height)).resize((48, 48)),
                    (x + 12, y + 2), img.crop((img.width - 32, img.height - 32, img.width, img.height)).resize((48, 48)))
        draw.text((x + 4, y + 54), str(i), fill=(230, 230, 230))
    out = ROOT / "study" / "setup_check.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(out, "- grounds should look like proper floor tiles; if they are noise or wrong, the .dat/.spr format,"
               " transparency or items.otb is off")


if __name__ == "__main__":
    main()
