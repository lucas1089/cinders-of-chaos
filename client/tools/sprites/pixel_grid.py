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
"""Picture to a clean pixel grid (O781; docs/SPRITE_FORGE.md "pixel_grid.py").

An AI drop (PixelLab, a local model) often comes back larger than its art: every art pixel painted as an s x s block,
the blocks a little noisy, the grid shifted by a pixel or two, the edge blended into a flat backdrop. This tool brings it
back to one art pixel per pixel, before item_post.py / oblique_lean.py / style_check.py. It paints nothing.

    python3 -I pixel_grid.py scale IN.png                  # prints the block size and grid phase it finds
    python3 -I pixel_grid.py clean IN.png OUT.png [--scale auto|N] [--colours 24] [--theme NAME] [--no-key] [--speck 3]

Steps of `clean`, in order:
  1. backdrop: the exact key #ff00ff anywhere, and a flat border colour (the channel median of the border, half the
     border or more within KEY_TOL of it, |dr| + |dg| + |db|) flood filled from the border within KEY_TOL, and
     enclosed holes when within KEY_TOL / 2 (the gap between two legs);
  2. scale: an exact nearest upscale (every s x s block one colour, at most 0.1 % off) is found first; else the block
     size of a painted render from where its colour edges fall (painted_scale: the largest period whose edges gather
     on one phase as well as the best one); `--scale N` forces it;
  3. phase: the offset (0 to s - 1 a side) where the blocks are flattest (least spread of colour inside a block);
  4. one pixel per block: the median of each channel; alpha cut at 128 to 0 or 255 (docs/SPRITE_STYLE.md: alpha 0 or
     255); a transparent pixel carries no colour;
  5. specks: opaque islands (8-connected) under `--speck` px dropped (no lone pixels, no two-pixel specks);
  6. palette: `--theme` snaps every colour to that theme of style_palettes.json (style_check.snap), else median cut to
     at most `--colours` (item_post.clamp; 0 keeps every colour).
Same input, same bytes: no randomness.

Parts adapt the depixel and the upscale check of Dotsmith (MIT, Copyright (c) 2026 Michael Araque,
https://github.com/michyaraque/dotsmith, commit 4e33791): the grid phase search, the block median, the upscale test.
Rewritten in Python here; docs/CREDITS.md. Needs numpy and Pillow (the fx venv of CI).
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import item_post  # noqa: E402

KEY = (255, 0, 255)       # the spr colour key
KEY_TOL = 60              # |dr| + |dg| + |db| to the measured backdrop
BORDER_SHARE = 0.5        # the backdrop covers at least this share of the border
EXACT_SCALES = (32, 16, 8, 4, 2)
MIN_CELLS = 8             # a scale leaves at least 8 art pixels a side
EXACT_OFF = 0.001         # share of pixels an exact upscale may miss (compression noise)
PAINTED_SCALES = range(2, 17)
CONC_MIN = 0.35          # below this the edges do not sit on any grid: a native picture
CONC_TIE = 0.85
SPECK = 3


def load(path):
    return np.array(Image.open(path).convert('RGBA'))


def save(a, path):
    Image.fromarray(a.astype(np.uint8), 'RGBA').save(path)


# ------------------------------------------------------------------------------------------------------------- backdrop
def border_pixels(a):
    h, w = a.shape[:2]
    return np.concatenate([a[0], a[h - 1], a[1:h - 1, 0], a[1:h - 1, w - 1]])


def backdrop_colour(a, tol=KEY_TOL):
    """the flat border colour (rgb ints, the channel median of the opaque border) when BORDER_SHARE of the whole
    border lies within tol of it, else None."""
    b = border_pixels(a)
    opaque = b[b[:, 3] >= 128][:, :3].astype(int)
    if len(opaque) < BORDER_SHARE * len(b):
        return None
    col = np.median(opaque, axis=0).astype(int)
    near = (np.abs(opaque - col).sum(-1) < tol).sum()
    if near < BORDER_SHARE * len(b):
        return None
    return tuple(int(v) for v in col)


def key_out(a, tol=KEY_TOL):
    """a copy with the exact key and a flat border backdrop made transparent; (out, backdrop or None)."""
    out = a.copy()
    rgb = out[..., :3].astype(int)
    exact = (rgb[..., 0] == KEY[0]) & (rgb[..., 1] == KEY[1]) & (rgb[..., 2] == KEY[2])
    out[exact] = 0
    col = backdrop_colour(out, tol)
    if col is None:
        return out, None
    near = (np.abs(rgb - np.array(col)).sum(-1) < tol) & (out[..., 3] >= 128)
    h, w = near.shape
    seen = np.zeros_like(near)
    stack = [(y, x) for x in range(w) for y in (0, h - 1) if near[y, x]]
    stack += [(y, x) for y in range(h) for x in (0, w - 1) if near[y, x]]
    while stack:
        y, x = stack.pop()
        if seen[y, x]:
            continue
        seen[y, x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < h and 0 <= xx < w and near[yy, xx] and not seen[yy, xx]:
                stack.append((yy, xx))
    out[seen] = 0
    hole = (np.abs(rgb - np.array(col)).sum(-1) < tol // 2) & (out[..., 3] >= 128)
    out[hole] = 0                      # enclosed holes (between legs, inside a ring) only when nearly exact
    return out, col


# ---------------------------------------------------------------------------------------------------------------- scale
def exact_scale(a):
    """the largest nearest-neighbour upscale factor of a (1 when it is native)."""
    h, w = a.shape[:2]
    for s in EXACT_SCALES:
        if w % s or h % s or w // s < MIN_CELLS or h // s < MIN_CELLS:
            continue
        top = a[::s, ::s].repeat(s, 0).repeat(s, 1)
        off = np.any(top != a, axis=-1).sum()
        if off <= EXACT_OFF * w * h:
            return s
    return 1


def edge_energy(a):
    """(column energy, row energy): colour change between a pixel and its left / upper neighbour, alpha weighted."""
    f = a.astype(float)
    f = np.concatenate([f[..., :3] * (f[..., 3:] / 255.0), f[..., 3:]], -1)
    ex = np.abs(np.diff(f, axis=1)).sum(-1).sum(0)       # change at column x+1
    ey = np.abs(np.diff(f, axis=0)).sum(-1).sum(1)
    return np.concatenate([[0], ex]), np.concatenate([[0], ey])


def painted_scale(a):
    """(scale, concentration) of a painted render: the period whose colour edges gather on one phase.

    share(s) = the edge energy on the best phase of period s; noise puts 1 / s of itself there by chance, so the
    concentration (share - 1 / s) / (1 - 1 / s) leaves it out. The true size and its divisors gather every edge (the same
    concentration), a multiple about half of them: the largest period within CONC_TIE of the best wins."""
    ex, ey = edge_energy(a)
    total = ex.sum() + ey.sum()
    if total <= 0:
        return 1, 0.0
    h, w = a.shape[:2]
    conc = {}
    for s in PAINTED_SCALES:
        if w // s < MIN_CELLS or h // s < MIN_CELLS:
            continue
        bx = max(ex[p::s].sum() for p in range(s))
        by = max(ey[p::s].sum() for p in range(s))
        share = (bx + by) / total
        conc[s] = (share - 1.0 / s) / (1 - 1.0 / s)
    if not conc:
        return 1, 0.0
    best = max(conc.values())
    if best < CONC_MIN:
        return 1, best
    s = max(k for k, v in conc.items() if v >= CONC_TIE * best)
    return s, conc[s]


def flattest_phase(a, s):
    """(dy, dx) where the s x s blocks are flattest: the least mean colour spread inside a block."""
    h, w = a.shape[:2]
    pad = np.pad(a.astype(float), ((0, s), (0, s), (0, 0)), mode='edge')
    best = None
    for dy in range(s):
        for dx in range(s):
            hh, ww = (h - dy) // s, (w - dx) // s
            if hh < 1 or ww < 1:
                continue
            blk = pad[dy:dy + hh * s, dx:dx + ww * s].reshape(hh, s, ww, s, 4)
            score = blk.std(axis=(1, 3)).mean()
            if best is None or score < best[0] - 1e-9:
                best = (score, dy, dx)
    return best[1], best[2]


def find_grid(a, scale='auto'):
    """(scale, dy, dx, how)."""
    if scale != 'auto':
        s = int(scale)
        how = 'forced'
    else:
        s = exact_scale(a)
        how = 'exact upscale'
        if s == 1:
            s, _lift = painted_scale(a)
            how = 'painted render' if s > 1 else 'native'
    if s == 1:
        return 1, 0, 0, how
    if how == 'exact upscale':
        return s, 0, 0, how
    dy, dx = flattest_phase(a, s)
    return s, dy, dx, how


def depixel(a, s, dy=0, dx=0):
    """one pixel per s x s block from (dy, dx): channel median, alpha cut 0 / 255."""
    if s == 1:
        out = a.copy()
    else:
        h, w = a.shape[:2]
        hh, ww = (h - dy) // s, (w - dx) // s
        blk = a[dy:dy + hh * s, dx:dx + ww * s].reshape(hh, s, ww, s, 4).transpose(0, 2, 1, 3, 4)
        blk = blk.reshape(hh, ww, s * s, 4).astype(float)
        out = np.floor(np.median(blk, axis=2) + 0.5).clip(0, 255).astype(np.uint8)
    out = item_post.cut_alpha(out)
    out[out[..., 3] == 0] = 0
    return out


def despeckle(a, speck=SPECK):
    out = a.copy()
    if speck <= 1:
        return out
    lab, n = item_post.label8(a[..., 3] > 0)
    if n:
        sizes = np.bincount(lab.ravel(), minlength=n + 1)
        small = (sizes < speck)
        small[0] = False
        out[small[lab]] = 0
    return out


def theme_palette(name):
    import style_check
    pal = style_check.load_palettes()['themes'][name]['palette']
    return np.array([style_check.unhex(c) for c in pal])


def palette(a, colours=24, theme=None):
    if theme:
        import style_check
        return style_check.snap(a, theme_palette(theme))
    if colours and colours > 0:
        return item_post.clamp(a, colours)
    return a


def clean(a, scale='auto', colours=24, theme=None, key=True, speck=SPECK):
    """(clean picture, facts)."""
    facts = {'in': '%dx%d' % (a.shape[1], a.shape[0])}
    b = a
    if key:
        b, col = key_out(a)
        facts['backdrop'] = '#%02x%02x%02x' % col if col else 'none'
    s, dy, dx, how = find_grid(b, scale)
    facts.update(scale=s, phase=(dy, dx), how=how)
    out = depixel(b, s, dy, dx)
    out = despeckle(out, speck)
    out = palette(out, colours, theme)
    facts['out'] = '%dx%d' % (out.shape[1], out.shape[0])
    facts['colours'] = int(len(np.unique(out[out[..., 3] > 0][:, :3], axis=0)))
    return out, facts


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('scale', help='print the block size and grid phase of a picture')
    s.add_argument('png')
    c = sub.add_parser('clean', help='picture -> one art pixel per pixel, hard alpha, palette')
    c.add_argument('png')
    c.add_argument('out')
    c.add_argument('--scale', default='auto', help='auto (default) or the block size')
    c.add_argument('--colours', type=int, default=24, help='median cut to at most N colours (0 keeps all)')
    c.add_argument('--theme', help='snap to a theme of style_palettes.json instead')
    c.add_argument('--no-key', action='store_true', help='keep the backdrop')
    c.add_argument('--speck', type=int, default=SPECK, help='drop opaque islands under N px')
    args = p.parse_args(argv)
    a = load(args.png)
    if args.cmd == 'scale':
        b, col = key_out(a)
        sc, dy, dx, how = find_grid(b)
        print('%s: scale %d, phase dy %d dx %d (%s), backdrop %s' % (
            args.png, sc, dy, dx, how, '#%02x%02x%02x' % col if col else 'none'))
        return 0
    out, facts = clean(a, args.scale, args.colours, args.theme, not args.no_key, args.speck)
    save(out, args.out)
    print('%s -> %s: %s' % (args.png, args.out, ', '.join('%s %s' % kv for kv in facts.items())))
    return 0


if __name__ == '__main__':
    sys.exit(main())
