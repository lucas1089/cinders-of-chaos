#!/usr/bin/env python3
# Parts of this file adapt Dotsmith (repository michyaraque/dotsmith), under this licence:
#
# MIT License
#
# Copyright (c) 2026 Michael Araque
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
"""Cut a sheet of ours into game pieces on our anchors (O781; docs/SPRITE_FORGE.md "sheet_cut.py").

A pack sheet (2 x 2 or 3 x 3 items in one picture) or a wall set (post, north run, east run, corner in a 2 x 2 sheet)
comes back from an AI drop or a generator as one picture. This tool finds its grid, cuts it and places every piece the
way the client draws it (docs/SPRITE_STYLE.md "Grid, size and anchors": a thing is anchored bottom right; an item fills
its 32 px cell, centred with a 1 px margin). It paints nothing.

    python3 -I sheet_cut.py pack SHEET.png OUT_DIR [--grid K | --cell C] [--anchor item|bottom|bottom-right] [--size 32]
    python3 -I sheet_cut.py walls SHEET.png OUT_DIR [--cell 64]       # -> post.png north.png east.png corner.png
    python3 -I sheet_cut.py room OUT_DIR ROOM.png [--tiles 3]          # the four wall pieces as a closed room (preview)

How the pack grid is found, most trusted first:
  1. `--grid K` (a K x K sheet) or `--cell C` (square cells of C px);
  2. a json next to the sheet with "grid" or "cell" (what our generators and idle_loop.py write);
  3. transparent gutters between the items: rows of items, then the items in each row; a piece under 1/25 of the
     biggest means stray pixels, not a grid, and this step gives up;
  4. square cells of 32 px (64 when the sheet is not a whole number of 32 px cells, or bigger than 6 a side).
Before any of it: a nearest upscale is undone and the backdrop keyed (pixel_grid.py), the alpha cut to 0 / 255.

Pack pieces (`--anchor`): `item` crops each piece and centres it in a `--size` cell with a 1 px margin (refused when it
does not fit: never resized here, item_post.py does that); `bottom` centres it on the bottom row (a map prop);
`bottom-right` moves its opaque box onto the bottom-right corner (a 2 x 2 or larger thing). Empty cells are skipped;
OUT_DIR/pieces.csv lists every piece (row, column, file, box, opaque pixels).

Wall set: a 2 x 2 sheet of `--cell` px cells in reading order post, north, east, corner (the order the wall prompts of
forge_prompts.py ask for). Each piece is moved so its opaque box touches the bottom-right corner of its cell: the tile
it stands on is its bottom-right 32 px, the rest reaches up and left. A piece under MIN_WALL px is refused.
Room: a (tiles + 1) x (tiles + 1) ring of tiles, post at the north-west corner, north runs along the top and bottom
rows, east runs down the left and right columns, the corner at the south-east, drawn row by row so a lower tile covers
the one above (the client's order). A preview to judge a wall set, not a map.

Parts adapt the pack split and the wall set of Dotsmith (MIT, Copyright (c) 2026 Michael Araque,
https://github.com/michyaraque/dotsmith, commit 4e33791): the grid search order, the gutter cut, the wall pieces and the
room layout. Rewritten in Python with our anchors; docs/CREDITS.md. Needs numpy and Pillow (the fx venv of CI).
"""
import argparse
import csv
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pixel_grid  # noqa: E402

TILE = 32
WALL_CELL = 64
WALL_PIECES = ('post', 'north', 'east', 'corner')
MIN_WALL = 24          # opaque px a wall piece needs
STRAY = 25             # a gutter piece under 1/STRAY of the biggest is a stray, not an item
MARGIN = 1


class CutError(Exception):
    pass


def prepare(a):
    """undo an exact upscale, key the backdrop, cut the alpha."""
    s = pixel_grid.exact_scale(a)
    if s > 1:
        a = a[::s, ::s]
    a, _col = pixel_grid.key_out(a)
    a = a.copy()
    on = a[..., 3] >= 128
    a[..., 3] = np.where(on, 255, 0)
    a[~on] = 0
    return a, s


def bands(full):
    out, start = [], None
    for i, f in enumerate(full):
        if f and start is None:
            start = i
        elif not f and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(full)))
    return out


def gutter_cells(a):
    """[(row, col, y0, x0, y1, x1)] of items between transparent rows and columns, or None."""
    m = a[..., 3] > 0
    rows = bands(m.any(1).tolist())
    if not rows:
        return None
    boxes = []
    for ri, (y0, y1) in enumerate(rows):
        for ci, (x0, x1) in enumerate(bands(m[y0:y1].any(0).tolist())):
            boxes.append((ri, ci, y0, x0, y1, x1))
    if len(boxes) < 2:
        return None
    big = max((b[4] - b[2]) * (b[5] - b[3]) for b in boxes)
    if any((b[4] - b[2]) * (b[5] - b[3]) * STRAY < big for b in boxes):
        return None
    return boxes


def grid_cells(a, cw, ch):
    h, w = a.shape[:2]
    return [(r, c, r * ch, c * cw, (r + 1) * ch, (c + 1) * cw) for r in range(h // ch) for c in range(w // cw)]


def meta_grid(path, w, h):
    j = os.path.splitext(path)[0] + '.json'
    if not os.path.exists(j):
        return None
    try:
        meta = json.load(open(j))
    except ValueError:
        return None
    if meta.get('cell'):
        c = int(meta['cell'])
        return (c, int(meta.get('cell_h', c)))
    if meta.get('grid'):
        k = int(meta['grid'])
        if w % k == 0 and h % k == 0:
            return (w // k, h // k)
    return None


def find_cells(a, grid=None, cell=None, path=None):
    """(cells, how)."""
    h, w = a.shape[:2]
    if grid:
        if w % grid or h % grid:
            raise CutError('%dx%d is not a %dx%d grid' % (w, h, grid, grid))
        return grid_cells(a, w // grid, h // grid), 'grid %dx%d' % (grid, grid)
    if cell:
        if w % cell or h % cell:
            raise CutError('%dx%d is not a whole number of %d px cells' % (w, h, cell))
        return grid_cells(a, cell, cell), 'cell %d' % cell
    if path:
        mg = meta_grid(path, w, h)
        if mg:
            return grid_cells(a, mg[0], mg[1]), 'json next to the sheet'
    g = gutter_cells(a)
    if g:
        return g, 'gutters between items'
    if w % TILE == 0 and h % TILE == 0 and w // TILE <= 6 and h // TILE <= 6 and (w > TILE or h > TILE):
        return grid_cells(a, TILE, TILE), '32 px cells'
    if w % 64 == 0 and h % 64 == 0:
        return grid_cells(a, 64, 64), '64 px cells'
    raise CutError('%dx%d px: no grid found (no json, no gutters, not 32 / 64 px cells)' % (w, h))


def bbox(a):
    ys, xs = np.nonzero(a[..., 3] > 0)
    if not len(ys):
        return None
    return int(ys.min()), int(xs.min()), int(ys.max()) + 1, int(xs.max()) + 1


def crop(a):
    b = bbox(a)
    return a[b[0]:b[2], b[1]:b[3]] if b else a[:0, :0]


def place_item(piece, size=TILE, margin=MARGIN):
    p = crop(piece)
    ph, pw = p.shape[:2]
    if ph > size - 2 * margin or pw > size - 2 * margin:
        raise CutError('a %dx%d piece does not fit a %d px cell with a %d px margin' % (pw, ph, size, margin))
    out = np.zeros((size, size, 4), np.uint8)
    y0, x0 = (size - ph) // 2, (size - pw) // 2
    out[y0:y0 + ph, x0:x0 + pw] = p
    return out


def place_bottom(piece, w, h):
    p = crop(piece)
    ph, pw = p.shape[:2]
    if ph > h or pw > w:
        raise CutError('a %dx%d piece does not fit %dx%d' % (pw, ph, w, h))
    out = np.zeros((h, w, 4), np.uint8)
    x0 = (w - pw) // 2
    out[h - ph:h, x0:x0 + pw] = p
    return out


def anchor_bottom_right(piece):
    """the piece moved so its opaque box touches the bottom-right corner of its cell (nothing resampled)."""
    b = bbox(piece)
    if not b:
        return piece.copy()
    h, w = piece.shape[:2]
    dy, dx = h - b[2], w - b[3]
    out = np.zeros_like(piece)
    out[b[0] + dy:h, b[1] + dx:w] = piece[b[0]:b[2], b[1]:b[3]]
    return out


def cut_pack(a, grid=None, cell=None, anchor='item', size=TILE, path=None):
    """[(row, col, piece)], how."""
    cells, how = find_cells(a, grid, cell, path)
    out = []
    cw = max(c[5] - c[3] for c in cells)
    ch = max(c[4] - c[2] for c in cells)
    for r, c, y0, x0, y1, x1 in cells:
        part = a[y0:y1, x0:x1]
        if not (part[..., 3] > 0).any():
            continue
        if anchor == 'item':
            piece = place_item(part, size)
        elif anchor == 'bottom':
            piece = place_bottom(part, cw, ch)
        elif anchor == 'bottom-right':
            cellpic = np.zeros((ch, cw, 4), np.uint8)
            cellpic[:part.shape[0], :part.shape[1]] = part
            piece = anchor_bottom_right(cellpic)
        else:
            raise CutError('unknown anchor %s' % anchor)
        out.append((r, c, piece))
    if not out:
        raise CutError('every cell is empty')
    return out, how


def cut_walls(a, cell=WALL_CELL):
    h, w = a.shape[:2]
    if (w, h) != (2 * cell, 2 * cell):
        raise CutError('a wall set is a 2 x 2 sheet of %d px cells (%dx%d), not %dx%d' % (cell, 2 * cell, 2 * cell, w, h))
    pieces = {}
    for i, name in enumerate(WALL_PIECES):
        r, c = divmod(i, 2)
        part = a[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
        n = int((part[..., 3] > 0).sum())
        if n < MIN_WALL:
            raise CutError('the %s piece has %d opaque px (at least %d)' % (name, n, MIN_WALL))
        pieces[name] = anchor_bottom_right(part)
    return pieces


def room(pieces, tiles=3):
    """a closed square room of (tiles + 1)^2 tiles from the four anchored pieces."""
    cell = pieces['post'].shape[0]
    reach = cell - TILE
    n = tiles
    side = (n + 1) * TILE + reach
    out = np.zeros((side, side, 4), np.uint8)
    for y in range(n + 1):
        for x in range(n + 1):
            if (x, y) == (0, 0):
                key = 'post'
            elif (x, y) == (n, n):
                key = 'corner'
            elif y == 0 or (y == n and x > 0):
                key = 'north'
            elif x == 0 or x == n:
                key = 'east'
            else:
                continue
            p = pieces[key]
            oy, ox = y * TILE, x * TILE        # the piece's bottom-right 32 px on tile (x, y) of the padded room
            on = p[..., 3] > 0
            region = out[oy:oy + cell, ox:ox + cell]
            region[on] = p[on]
    return out


def load(path):
    return np.array(Image.open(path).convert('RGBA'))


def save(a, path):
    Image.fromarray(a.astype(np.uint8), 'RGBA').save(path)


def cmd_pack(args):
    a, s = prepare(load(args.sheet))
    pieces, how = cut_pack(a, args.grid, args.cell, args.anchor, args.size, args.sheet)
    os.makedirs(args.out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(args.sheet))[0]
    rows = []
    for r, c, p in pieces:
        name = '%s_r%dc%d.png' % (stem, r + 1, c + 1)
        save(p, os.path.join(args.out_dir, name))
        b = bbox(p)
        rows.append({'row': r + 1, 'col': c + 1, 'file': name, 'box': '%d %d %d %d' % (b[1], b[0], b[3], b[2]),
                     'opaque': int((p[..., 3] > 0).sum())})
    with open(os.path.join(args.out_dir, 'pieces.csv'), 'w', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=['row', 'col', 'file', 'box', 'opaque'], lineterminator='\n')
        wr.writeheader()
        wr.writerows(rows)
    print('%s: %d pieces (%s%s) -> %s' % (args.sheet, len(rows), how, ', upscale %d undone' % s if s > 1 else '',
                                          args.out_dir))
    return 0


def cmd_walls(args):
    a, _s = prepare(load(args.sheet))
    pieces = cut_walls(a, args.cell)
    os.makedirs(args.out_dir, exist_ok=True)
    for k, p in pieces.items():
        save(p, os.path.join(args.out_dir, k + '.png'))
    print('%s: %s -> %s' % (args.sheet, ', '.join(WALL_PIECES), args.out_dir))
    return 0


def cmd_room(args):
    pieces = {k: load(os.path.join(args.dir, k + '.png')) for k in WALL_PIECES}
    save(room(pieces, args.tiles), args.out)
    print('room of %d tiles a side -> %s' % (args.tiles + 1, args.out))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    k = sub.add_parser('pack', help='cut a pack sheet into pieces')
    k.add_argument('sheet')
    k.add_argument('out_dir')
    k.add_argument('--grid', type=int)
    k.add_argument('--cell', type=int)
    k.add_argument('--anchor', default='item', choices=('item', 'bottom', 'bottom-right'))
    k.add_argument('--size', type=int, default=TILE, help='the cell of an item piece (32)')
    w = sub.add_parser('walls', help='cut a 2 x 2 wall set into post, north, east, corner')
    w.add_argument('sheet')
    w.add_argument('out_dir')
    w.add_argument('--cell', type=int, default=WALL_CELL)
    r = sub.add_parser('room', help='the four wall pieces of a folder as a closed room')
    r.add_argument('dir')
    r.add_argument('out')
    r.add_argument('--tiles', type=int, default=3)
    args = p.parse_args(argv)
    try:
        return {'pack': cmd_pack, 'walls': cmd_walls, 'room': cmd_room}[args.cmd](args)
    except CutError as e:
        print('%s: %s' % (args.cmd, e), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
