"""ITEM SHEETS: PixelLab draws many items in one image (Create image Pro); here they are cut into one sprite each.

    python kit/items.py gen <prompt.md> <name> [size]    # the sheet(s): out/items/<name>/sheet_<k>.png
    python kit/items.py split <sheet.png> <name> [cell]  # one PNG per item: out/items/<name>/item_<row>_<col>.png
    python kit/items.py board <name>                     # every cut item at x1 and x4 on grass, to judge them

The prompt file is the one the skill /item-sheet writes (the prompt inside a ```text block). The cut finds each item
as a blob of opaque pixels (small specks join the nearest blob), crops it, and centres it in a `cell` square with its
foot at the bottom-right like the game draws items; the alpha is cut at half (the game draws 0 or 255).
"""
import os
import re
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pixellab  # noqa: E402
import tibia_view as pt  # noqa: E402

STUDIO = os.path.dirname(HERE)


def out_dir(name):
    path = os.path.join(STUDIO, "out", "items", name)
    os.makedirs(path, exist_ok=True)
    return path


def read_prompt(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r"```text\s*\n(.*?)```", text, re.S)
    return (m.group(1) if m else text).strip()


def cut_alpha(a):
    a = np.asarray(a).copy()
    on = a[..., 3] >= 128
    a[..., 3] = np.where(on, 255, 0)
    a[~on, :3] = 0
    return a


def split(sheet, cell=64, min_px=40):
    """The items of a sheet, in reading order (rows top to bottom, then left to right): a list of (row, col, rgba)."""
    a = cut_alpha(sheet)
    on = a[..., 3] > 0
    lab, n = ndimage.label(on, np.ones((3, 3)))
    sizes = ndimage.sum(on, lab, range(1, n + 1))
    big = [i + 1 for i, s in enumerate(sizes) if s >= min_px]
    if not big:
        return []
    # a speck joins the nearest big blob (a loose spark, a dot of a gem)
    keep = np.isin(lab, big)
    _, (iy, ix) = ndimage.distance_transform_edt(~keep, return_indices=True)
    owner = np.where(on, lab[iy, ix], 0)
    boxes = ndimage.find_objects(owner)
    items = []
    for b in big:
        sl = boxes[b - 1]
        if sl is None:
            continue
        cy = (sl[0].start + sl[0].stop) / 2
        cx = (sl[1].start + sl[1].stop) / 2
        crop = a[sl].copy()
        crop[owner[sl] != b] = 0
        items.append((cy, cx, crop))
    # rows: blobs whose centres are within half a cell vertically
    items.sort(key=lambda t: t[0])
    rows, cur = [], [items[0]]
    for it in items[1:]:
        if abs(it[0] - cur[0][0]) < cell / 2:
            cur.append(it)
        else:
            rows.append(cur)
            cur = [it]
    rows.append(cur)
    out = []
    for r, row in enumerate(rows):
        for c, (_, _, crop) in enumerate(sorted(row, key=lambda t: t[1])):
            out.append((r, c, fit(crop, cell)))
    return out


def fit(crop, cell):
    """A cropped item in a `cell` square: shrunk (nearest) only if it does not fit, then centred, resting low-right."""
    h, w = crop.shape[:2]
    if h > cell or w > cell:
        k = cell / max(h, w)
        crop = np.asarray(Image.fromarray(crop).resize((max(1, int(w * k)), max(1, int(h * k))), Image.NEAREST))
        h, w = crop.shape[:2]
    out = np.zeros((cell, cell, 4), np.uint8)
    y0 = min(cell - h, (cell - h + 1) // 2 + (cell - h) // 4)
    x0 = min(cell - w, (cell - w + 1) // 2 + (cell - w) // 4)
    out[y0:y0 + h, x0:x0 + w] = crop
    return out


def board(name, zoom=4):
    folder = out_dir(name)
    files = sorted(f for f in os.listdir(folder) if f.startswith("item_") and f.endswith(".png"))
    if not files:
        raise SystemExit("no item_*.png in " + folder)
    ims = [Image.open(os.path.join(folder, f)).convert("RGBA") for f in files]
    cell = ims[0].width
    cols = min(6, len(ims))
    rows = (len(ims) + cols - 1) // cols
    W = cols * (cell * (zoom + 1) + 12)
    out = Image.new("RGBA", (W, rows * (cell * zoom + 12)), (34, 36, 40, 255))
    for i, im in enumerate(ims):
        x = (i % cols) * (cell * (zoom + 1) + 12)
        y = (i // cols) * (cell * zoom + 12)
        g = pt.grass_tile(cell, cell)
        g.alpha_composite(im)
        out.alpha_composite(g, (x, y))
        out.alpha_composite(g.resize((cell * zoom, cell * zoom), Image.NEAREST), (x + cell + 4, y))
    path = os.path.join(folder, "board.png")
    out.save(path)
    print(path)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    if what == "gen":
        prompt, name = read_prompt(sys.argv[2]), sys.argv[3]
        size = int(sys.argv[4]) if len(sys.argv) > 4 else 256
        print(pixellab.balance())
        ims = pixellab.create_image_pro(prompt, size, size, label=name)
        for k, im in enumerate(ims, 1):
            path = os.path.join(out_dir(name), "sheet_%d.png" % k)
            Image.fromarray(im, "RGBA").save(path)
            print(path)
        print(pixellab.balance())
    elif what == "split":
        sheet, name = sys.argv[2], sys.argv[3]
        cell = int(sys.argv[4]) if len(sys.argv) > 4 else 64
        for r, c, rgba in split(Image.open(sheet).convert("RGBA"), cell):
            path = os.path.join(out_dir(name), "item_%d_%d.png" % (r + 1, c + 1))
            Image.fromarray(rgba, "RGBA").save(path)
            print(path)
        board(name)
    elif what == "board":
        board(sys.argv[2])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
