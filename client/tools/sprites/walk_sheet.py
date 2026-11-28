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
"""Walk sheets to the engine layout, and the derived directions measured before use (O781; docs/SPRITE_FORGE.md).

A walk drop comes in many layouts: one row per direction in the order the generator likes (south, west, north, east is
common), 8 frames in a 4 x 2 grid per direction, or four standing pictures. The importers want ours
(docs/SPRITE_STYLE.md "Creatures, outfits and wings"): the 4 directions as columns in the order north, east, south,
west, one row per phase. gen_pixellab_monsters.py and gen_drive_monsters.py read PixelLab folders; this tool covers
every other sheet and measures whether a direction may be made from another one.

    python3 -I walk_sheet.py engine SHEET.png OUT.png --order swne --frames 8 [--grid 4x2]
            # rows = directions in --order, each row --frames frames (or a COLSxROWS grid per direction block)
    python3 -I walk_sheet.py derive SHEET.png OUT.png --make west=mirror:east [--make ...]
            # on an engine sheet: a direction made from another by a mirror (left-right) or a transpose (x <-> y)
    python3 -I walk_sheet.py fit (SHEET.png | DIR)  # how well each derivation matches the drawn direction, and the lean

Derivations, measured with `fit` on the nine committed PixelLab redraws of ours (art_import/drive_redraw, 2026-11-28):
  transpose  swap x and y (square frames only). Our view draws height diagonally up and to the left, so a standing
             figure's east is close to the transpose of its south and west to the transpose of north: match 0.82 to 0.93
             for east (all nine), 0.77 to 0.93 for west (seven of nine), the lean kept (made 8 to 23 px against drawn 9
             to 26). A draft for a missing direction, still checked by eye and by the lean rule.
  mirror     left-right flip. It turns the lean round (made -8 to -26 px): east and west of our figures are NOT mirrors
             (match 0.20 to 0.41). Only a thing with no lean (a flat rune, a puddle, a ring) may be mirrored.
`derive` refuses a derivation whose silhouette match against a drawn target is under FIT_MIN, or, when the target is
not drawn, whose made frame leans under the rule (oblique_lean.LEAN, 9 px) in east or south; --force takes it anyway.
`fit` prints, per derivation, the silhouette match (intersection over union after the best whole-pixel shift within
SHIFT px) of the made direction against the drawn one, and oblique_lean.lean of each drawn direction and of the made
one (the rule: south or east 9 to 26 px).

Parts adapt the walk sheet handling of Dotsmith (MIT, Copyright (c) 2026 Michael Araque,
https://github.com/michyaraque/dotsmith, commit 4e33791): the direction rows, the frame grid, the mirror / transpose
derivation. Rewritten in Python for our layout and measured against our view; docs/CREDITS.md. Needs numpy and Pillow.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ENGINE = ('north', 'east', 'south', 'west')      # columns of an engine sheet
LETTER = {'n': 'north', 'e': 'east', 's': 'south', 'w': 'west'}
FIT_MIN = 0.8
SHIFT = 4
DERIVATIONS = (('west', 'mirror', 'east'), ('east', 'mirror', 'west'),
               ('east', 'transpose', 'south'), ('west', 'transpose', 'north'))


class SheetError(Exception):
    pass


def parse_order(s):
    s = s.lower()
    if sorted(s) != sorted('nesw') or len(s) != 4:
        raise SheetError('--order is the four letters n e s w in the sheet order, not %r' % s)
    return [LETTER[c] for c in s]


def cut(a, cols, rows):
    h, w = a.shape[:2]
    if w % cols or h % rows:
        raise SheetError('%dx%d is not %d x %d whole cells' % (w, h, cols, rows))
    cw, ch = w // cols, h // rows
    return [[a[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] for c in range(cols)] for r in range(rows)]


def to_engine(a, order, frames, grid=None):
    """sheet with one block per direction (rows in `order`) -> engine sheet (columns N E S W, one row a phase)."""
    if grid:
        gc, gr = grid
        if gc * gr != frames:
            raise SheetError('a %dx%d grid holds %d frames, not %d' % (gc, gr, gc * gr, frames))
        cells = cut(a, gc, 4 * gr)
        per = {}
        for i, d in enumerate(order):
            block = cells[i * gr:(i + 1) * gr]
            per[d] = [f for row in block for f in row]
    else:
        cells = cut(a, frames, 4)
        per = {d: cells[i] for i, d in enumerate(order)}
    rows = [np.concatenate([per[d][f] for d in ENGINE], axis=1) for f in range(frames)]
    return np.concatenate(rows, axis=0)


def engine_frames(a):
    """{direction: [frames]} of an engine sheet (square frames of the sheet width / 4)."""
    h, w = a.shape[:2]
    if w % 4:
        raise SheetError('an engine sheet is 4 columns wide')
    fw = w // 4
    if h % fw:
        raise SheetError('frames are square (%d px): height %d' % (fw, h))
    cells = cut(a, 4, h // fw)
    return {d: [row[i] for row in cells] for i, d in enumerate(ENGINE)}


def from_engine(per):
    n = len(per['north'])
    return np.concatenate([np.concatenate([per[d][f] for d in ENGINE], axis=1) for f in range(n)], axis=0)


def mirror(f):
    return f[:, ::-1].copy()


def transpose(f):
    if f.shape[0] != f.shape[1]:
        raise SheetError('a transpose needs square frames')
    return f.transpose(1, 0, 2).copy()


OPS = {'mirror': mirror, 'transpose': transpose}


def iou(a, b, shift=SHIFT):
    """best silhouette intersection over union of a and b over whole-pixel shifts of b within +-shift, with the
    centroids aligned first."""
    ma, mb = a[..., 3] > 0, b[..., 3] > 0
    if not ma.any() or not mb.any():
        return 0.0
    ya, xa = [v.mean() for v in np.nonzero(ma)]
    yb, xb = [v.mean() for v in np.nonzero(mb)]
    cy, cx = int(round(ya - yb)), int(round(xa - xb))
    h, w = ma.shape
    pad = shift + max(abs(cy), abs(cx)) + 1
    A = np.pad(ma, pad)
    B = np.pad(mb, pad)
    best = 0.0
    for dy in range(cy - shift, cy + shift + 1):
        for dx in range(cx - shift, cx + shift + 1):
            Bs = np.roll(np.roll(B, dy, 0), dx, 1)
            inter = (A & Bs).sum()
            union = (A | Bs).sum()
            best = max(best, inter / union)
    return float(best)


def lean(f):
    import gen_class_redraw as CR
    if not (f[..., 3] > 0).any():
        return 0.0
    return CR.lean(f)


def lean_min():
    import oblique_lean
    return oblique_lean.LEAN[0]


def fit(per):
    """[(made, op, source, match, lean of the made one, lean of the drawn one)] on the first frame of each direction."""
    out = []
    for made, op, src in DERIVATIONS:
        try:
            m = OPS[op](per[src][0])
        except SheetError:
            continue
        out.append((made, op, src, iou(m, per[made][0]), lean(m), lean(per[made][0])))
    return out


def derive(per, makes, force=False):
    per = {d: list(v) for d, v in per.items()}
    for spec in makes:
        try:
            made, rest = spec.split('=')
            op, src = rest.split(':')
        except ValueError:
            raise SheetError('--make DIR=OP:SOURCE, not %r' % spec)
        if made not in ENGINE or src not in ENGINE or op not in OPS or made == src:
            raise SheetError('--make %r: directions %s, ops %s' % (spec, ', '.join(ENGINE), ', '.join(OPS)))
        frames = [OPS[op](f) for f in per[src]]
        if not force:
            drawn = (per[made][0][..., 3] > 0).any()
            if drawn:
                m = iou(frames[0], per[made][0])
                if m < FIT_MIN:
                    raise SheetError('%s = %s of %s does not hold (match %.2f, at least %.2f); --force' % (
                        made, op, src, m, FIT_MIN))
            elif made in ('east', 'south') and lean(frames[0]) < lean_min():
                raise SheetError('%s = %s of %s leans %.1f px (at least %.1f); --force' % (
                    made, op, src, lean(frames[0]), lean_min()))
        per[made] = frames
    return per


def load_dir(path):
    per = {}
    for d in ENGINE:
        p = os.path.join(path, d + '.png')
        if not os.path.exists(p):
            raise SheetError('%s has no %s.png' % (path, d))
        per[d] = [np.array(Image.open(p).convert('RGBA'))]
    return per


def load(path):
    return np.array(Image.open(path).convert('RGBA'))


def save(a, path):
    Image.fromarray(a.astype(np.uint8), 'RGBA').save(path)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    e = sub.add_parser('engine', help='a sheet of direction rows -> the engine layout')
    e.add_argument('sheet')
    e.add_argument('out')
    e.add_argument('--order', default='swne', help='the four letters in the sheet row order (swne)')
    e.add_argument('--frames', type=int, default=8)
    e.add_argument('--grid', help='COLSxROWS frames per direction block (4x2)')
    d = sub.add_parser('derive', help='make directions of an engine sheet from others')
    d.add_argument('sheet')
    d.add_argument('out')
    d.add_argument('--make', action='append', required=True, help='DIR=mirror:SOURCE or DIR=transpose:SOURCE')
    d.add_argument('--force', action='store_true', help='take a transpose that does not fit')
    f = sub.add_parser('fit', help='measure each derivation against the drawn direction')
    f.add_argument('src', help='an engine sheet or a folder with north / east / south / west .png')
    args = p.parse_args(argv)
    try:
        if args.cmd == 'engine':
            grid = tuple(int(v) for v in args.grid.lower().split('x')) if args.grid else None
            save(to_engine(load(args.sheet), parse_order(args.order), args.frames, grid), args.out)
            print('%s -> %s (columns north, east, south, west)' % (args.sheet, args.out))
        elif args.cmd == 'derive':
            per = derive(engine_frames(load(args.sheet)), args.make, args.force)
            save(from_engine(per), args.out)
            print('%s -> %s: %s' % (args.sheet, args.out, ', '.join(args.make)))
        else:
            per = load_dir(args.src) if os.path.isdir(args.src) else engine_frames(load(args.src))
            for made, op, src, m, lm, ld in fit(per):
                print('%-5s = %-9s of %-5s: match %.2f %s, lean made %5.1f px, drawn %5.1f px' % (
                    made, op, src, m, 'holds' if m >= FIT_MIN else 'does not hold', lm, ld))
    except SheetError as err:
        print('%s: %s' % (args.cmd, err), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
