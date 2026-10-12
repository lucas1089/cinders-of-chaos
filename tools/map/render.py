"""Render a rectangle of an OTBM map with the client sprites (32 px per tile).

    python3 -I render.py MAP(.otbm|.npz) ITEMS.otb ITEMS.xml Tibia.dat Tibia.spr X0 Y0 X1 Y1 Z OUT.(png|jpg) [--grid]

Draw order per tile follows the client: ground, borders, bottom items (walls), common items in stack
order, top items (arches, frames). Tiles are drawn row by row, so large sprites (2x2 trees) overlap their
north-west neighbours as in game. Elevation (parcels, tables) lifts the items above it. Only the given
floor is drawn (no roofs from the floor above, no creatures, no light). Items whose server id is not in
items.otb, or whose client id has no sprite, are skipped and counted.
"""
import sys, os
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def render(m, db, spr, x0, y0, x1, y1, z, grid=False):
    W, H = x1 - x0 + 1, y1 - y0 + 1
    pad = 3
    canvas = Image.new('RGBA', ((W + pad) * 32, (H + pad) * 32), (0, 0, 0, 255))
    things = db.dat.items
    missing = 0
    cache = {}

    def sprite_img(sid):
        im = cache.get(sid)
        if im is None:
            a = spr.sprite(sid)
            im = Image.fromarray(a, 'RGBA') if a is not None else False
            cache[sid] = im
        return im

    # include a margin to the south-east so big sprites standing outside the crop still overlap it
    for y in range(y0, y1 + pad + 1):
        for x in range(x0, x1 + pad + 1):
            i = m.find(x, y, z)
            if i < 0:
                continue
            st = m.stack(i)
            orders = []
            for k, sid in enumerate(st):
                sid = int(sid)
                c = int(db.cid[sid]) if sid < len(db.cid) else 0
                if not c or c - 100 >= len(things):
                    missing += 1; continue
                o = 0 if db.cls[sid] == 1 else int(db.order[sid]) if db.order[sid] in (1, 2, 3) else 4
                pr = {0: 0, 1: 1, 2: 2, 4: 3, 3: 4}[o]
                orders.append((pr, k, things[c - 100]))
            orders.sort(key=lambda t: (t[0], t[1]))
            elev = 0
            for pr, k, t in orders:
                px, py, pz = x % t.px, y % t.py, z % t.pz
                for hh in range(t.h):
                    for ww in range(t.w):
                        idx = ((((((0 * t.pz + pz) * t.py + py) * t.px + px) * t.layers + 0) * t.h + hh) * t.w + ww)
                        if idx >= len(t.sprites):
                            continue
                        im = sprite_img(t.sprites[idx])
                        if not im:
                            continue
                        dx = (x - x0 - ww + pad - 0) * 32 - elev
                        dy = (y - y0 - hh + pad - 0) * 32 - elev
                        if -32 < dx < canvas.width and -32 < dy < canvas.height:
                            canvas.alpha_composite(im, (max(dx, 0), max(dy, 0)), (max(-dx, 0), max(-dy, 0)))
                if 'elevation' in t.flags:
                    elev = min(24, elev + t.flags['elevation'])
    out = canvas.crop((pad * 32, pad * 32, (W + pad) * 32, (H + pad) * 32))
    if grid:
        d = ImageDraw.Draw(out)
        for gx in range(0, W, 8):
            d.line([(gx * 32, 0), (gx * 32, H * 32)], fill=(255, 255, 255, 60))
        for gy in range(0, H, 8):
            d.line([(0, gy * 32), (W * 32, gy * 32)], fill=(255, 255, 255, 60))
    return out.convert('RGB'), missing


def main():
    a = sys.argv[1:]
    import otbm, pickle
    from itemdb import ItemDB
    from datspr import Spr
    m = otbm.load_map(a[0])
    db = ItemDB(a[1], a[2], a[3])
    spr = Spr(a[4])
    x0, y0, x1, y1, z = map(int, a[5:10])
    img, miss = render(m, db, spr, x0, y0, x1, y1, z, grid='--grid' in a)
    img.save(a[10], quality=85) if a[10].endswith('.jpg') else img.save(a[10])
    print(a[10], img.size, 'skipped items', miss)


if __name__ == '__main__':
    main()
