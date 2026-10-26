"""Draws a map area with the real sprites.

    python tools/render.py refs/<name>/area.txt --floor 7 --out out.png
    python tools/render.py refs/<name>/area.txt --floor 7 --upper --from 3200,4800 --to 3240,4830 --grid
    python tools/render.py areas/<name>/area.txt --floor 7 --scale 0.5

Floors are drawn like the client: deeper floors first, every floor above shifted one tile up-left.
--upper adds the floors above the chosen one (roofs, upper storeys); without it only that floor is drawn.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from common import (MAX_ELEVATION, TILE, Placed, SpriteCache, displacement, item_image, items_otml, load_area,
                    load_items)

MARGIN = 4  # tiles drawn outside the crop so big items that reach into it are not cut


def draw_order(ids, items):
    """Client order inside a tile: ground and borders, bottom items, common items, top items."""
    def rank(item_id):
        obj = items.get(item_id)
        if obj is None:
            return 2
        f = obj["flags"]
        if "ground_speed" in f or "full_ground" in f:
            return 0
        if "ground_border" in f:
            return 1
        if "on_bottom" in f:
            return 2
        if "on_top" in f:
            return 4
        return 3
    return sorted(ids, key=rank)  # stable: keeps the stored order inside each rank


def render(area, x1, y1, x2, y2, floors, scale=1.0, grid=False, coords=False, highlight=None, cache=None,
           camera=None):
    """`camera` is the floor the viewer stands on; bounds are in its coordinates. Floors below it are drawn
    first, shifted down-right one tile per floor (seen through empty tiles), floors above shifted up-left."""
    items = load_items()
    otml = items_otml()
    cache = cache or SpriteCache()
    width, height = (x2 - x1 + 1) * TILE, (y2 - y1 + 1) * TILE
    m = MARGIN * TILE
    canvas = Image.new("RGBA", (width + 2 * m, height + 2 * m), (12, 12, 12, 255))
    base = max(floors) if camera is None else camera
    for z in sorted(floors, reverse=True):
        layer = area.get(z, {})
        shift = (z - base) * TILE
        for y in range(y1 - MARGIN, y2 + MARGIN + 1):
            for x in range(x1 - MARGIN, x2 + MARGIN + 1):
                ids = layer.get((x - (z - base), y - (z - base))) if shift else layer.get((x, y))
                if not ids:
                    continue
                tx, ty = (x - x1) * TILE + m, (y - y1) * TILE + m
                elevation = 0
                for item_id in draw_order(ids, items):
                    obj = items.get(item_id)
                    if obj is None:
                        continue
                    sx, sy = (x - (z - base), y - (z - base)) if shift else (x, y)
                    img = item_image(obj, cache, sx, sy)
                    dx, dy = displacement(obj)
                    # client offsets: the type's items.otml offset, then the placement's own offset
                    cfg = otml.get(int(item_id), {})
                    if cfg.get("invisible"):
                        continue          # items.otml invisible: hidden in the client and Redux
                    ox = cfg.get("offset-x", 0) + (item_id.offset[0] if isinstance(item_id, Placed) else 0)
                    oy = cfg.get("offset-y", 0) + (item_id.offset[1] if isinstance(item_id, Placed) else 0)
                    if cfg.get("opacity", 1.0) < 1.0:
                        img = img.copy()
                        img.putalpha(img.getchannel("A").point(lambda a, o=cfg["opacity"]: int(a * o)))
                    px = tx + TILE - img.width - dx - elevation + ox
                    py = ty + TILE - img.height - dy - elevation + oy
                    if px + img.width <= 0 or py + img.height <= 0:
                        continue
                    canvas.alpha_composite(img, (max(px, 0), max(py, 0)),
                                           (max(-px, 0), max(-py, 0)))
                    if "elevation" in obj["flags"]:
                        elevation = min(MAX_ELEVATION, elevation + obj["flags"]["elevation"])
    canvas = canvas.crop((m, m, m + width, m + height))
    draw = ImageDraw.Draw(canvas)
    if highlight:
        for (hx, hy) in highlight:
            if x1 <= hx <= x2 and y1 <= hy <= y2:
                bx, by = (hx - x1) * TILE, (hy - y1) * TILE
                draw.rectangle((bx, by, bx + TILE - 1, by + TILE - 1), outline=(255, 40, 200, 255), width=2)
    if grid:
        for gx in range(0, width + 1, TILE):
            draw.line((gx, 0, gx, height), fill=(255, 255, 255, 40))
        for gy in range(0, height + 1, TILE):
            draw.line((0, gy, width, gy), fill=(255, 255, 255, 40))
    if coords:
        step = 8
        for x in range(x1 - x1 % step + step, x2 + 1, step):
            draw.text(((x - x1) * TILE + 2, 2), str(x), fill=(255, 255, 0, 255))
        for y in range(y1 - y1 % step + step, y2 + 1, step):
            draw.text((2, (y - y1) * TILE + 2), str(y), fill=(255, 255, 0, 255))
    if scale != 1.0:
        canvas = canvas.resize((max(1, int(width * scale)), max(1, int(height * scale))), Image.Resampling.LANCZOS)
    return canvas


def bounds_of(meta, area):
    if "bounds" in meta:
        b = meta["bounds"]
        return b["x1"], b["y1"], b["x2"], b["y2"]
    xs = [x for layer in area.values() for x, _ in layer]
    ys = [y for layer in area.values() for _, y in layer]
    return min(xs), min(ys), max(xs), max(ys)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("area")
    p.add_argument("--floor", type=int, default=7)
    p.add_argument("--upper", action="store_true", help="also draw the floors above, as the client would")
    p.add_argument("--only", action="store_true", help="draw only --floor, not the floors below it")
    p.add_argument("--from", dest="start")
    p.add_argument("--to", dest="end")
    p.add_argument("--scale", type=float, default=1.0)
    p.add_argument("--grid", action="store_true")
    p.add_argument("--coords", action="store_true")
    p.add_argument("--mark", help="x,y;x,y tiles to outline")
    p.add_argument("--out", type=Path)
    a = p.parse_args()
    meta, area = load_area(a.area)
    x1, y1, x2, y2 = bounds_of(meta, area)
    if a.start:
        x1, y1 = map(int, a.start.split(","))
    if a.end:
        x2, y2 = map(int, a.end.split(","))
    # what the client shows a player standing on --floor: the floors below it down to 7 on the surface
    # (or 2 floors down underground), seen through empty tiles; --upper adds the floors above it
    lowest = 7 if a.floor <= 7 else min(a.floor + 2, 15)
    floors = [z for z in range(a.floor, lowest + 1) if not a.only]
    floors = floors or [a.floor]
    if a.upper:
        floors += [z for z in area if z < a.floor and (a.floor <= 7) == (z <= 7)]
    marks = [tuple(map(int, t.split(","))) for t in a.mark.split(";")] if a.mark else None
    image = render(area, x1, y1, x2, y2, floors, a.scale, a.grid, a.coords, marks, camera=a.floor)
    out = a.out or Path(a.area).with_name(f"render_z{a.floor}{'_upper' if a.upper else ''}.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        image.convert("RGB").save(out)
    except OSError:  # the file is open elsewhere (an image viewer locks it on Windows): write beside it
        out = out.with_name(out.stem + "_new" + out.suffix)
        image.convert("RGB").save(out)
    print(out, image.size)


if __name__ == "__main__":
    main()
