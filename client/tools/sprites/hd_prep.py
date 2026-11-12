#!/usr/bin/env python3
"""Cleans the frames of an HD creature and writes them where gen_hd_overlay.py reads them (O539).

Input: a folder in the layout of a PixelLab character download (our own text-prompt art, never a pair sprite):
  SRC/rotations/<direction>.png                       the standing picture of each direction
  SRC/animations/<walk name>/<direction>/frame_NNN.png  the walk frames of each direction
Output: client/tools/sprites/hd_overlay/art/<name>/g<G>_<direction>_<NN>.png, every frame the size of the look at its scale
(a 2x2 look at 2x: 128 x 128), plus the numbers it used on stdout.

What it does to every frame, the same way for all of them so the animation does not jitter:
  1. placement: the union of all opaque pixels of the creature (every frame, every direction) is moved so its bottom row
     sits `--bottom` px from the frame's bottom edge (the art of the pair ends 0-1 px from it) and its centre on
     `--center-x` (from the pair's own look with --pair DAT SPR --look ID, else the frame centre). No resampling:
     pixel art stays pixel art.
  2. edges: alpha 0 or 255 (SPRITE_STYLE: no soft pixels on a creature), lone pixels and two-pixel specks removed.
  3. palette: one palette of at most `--colours` colours for the whole look (median cut, no dither).
Group 0 (idle) gets the standing picture of each direction once (the frame repeats on every idle phase), group 1 (walk) the
`--walk-frames` frames spread over the walk cycle: with k frames and n phases, gen_hd_overlay.py shows frame (p * k) // n, so
a 2 phase walk of an 8 frame cycle keeps frames 0 and 4 and this tool writes only those.

  python3 -I client/tools/sprites/hd_prep.py NAME SRC --size 128 --walk-phases 2 [--pair DAT SPR --look 3019]
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART_DIR = os.path.join(HERE, 'hd_overlay', 'art')
DIRS = ('north', 'east', 'south', 'west')


def binarize(a, cut=128):
    out = a.copy()
    solid = out[:, :, 3] >= cut
    out[:, :, 3] = np.where(solid, 255, 0)
    out[~solid] = 0
    return out


def neighbours(mask):
    """count of opaque 8-neighbours of every pixel"""
    p = np.pad(mask.astype(np.int16), 1)
    h, w = mask.shape
    n = np.zeros((h, w), np.int16)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            if dy == 1 and dx == 1:
                continue
            n += p[dy:dy + h, dx:dx + w]
    return n


def despeckle(a):
    """removes opaque pixels with no opaque neighbour, then two-pixel specks (every pixel of a 2 px group has exactly 1)"""
    out = a.copy()
    for _ in range(2):
        mask = out[:, :, 3] > 0
        n = neighbours(mask)
        lone = mask & (n == 0)
        out[lone] = 0
    mask = out[:, :, 3] > 0
    n = neighbours(mask)
    cand = mask & (n == 1)
    ys, xs = np.nonzero(cand)
    for y, x in zip(ys, xs):
        # the one neighbour must be a candidate too: a pair, not the tip of a line
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                yy, xx = y + dy, x + dx
                if (dy or dx) and 0 <= yy < out.shape[0] and 0 <= xx < out.shape[1] and mask[yy, xx]:
                    if cand[yy, xx] and n[yy, xx] == 1:
                        out[y, x] = 0
                        out[yy, xx] = 0
    return out


def union_bbox(frames):
    x0 = y0 = 10 ** 9
    x1 = y1 = -1
    for f in frames:
        ys, xs = np.nonzero(f[:, :, 3] > 0)
        if len(xs):
            x0, x1 = min(x0, xs.min()), max(x1, xs.max())
            y0, y1 = min(y0, ys.min()), max(y1, ys.max())
    if x1 < 0:
        raise ValueError('no opaque pixel in any frame')
    return int(x0), int(y0), int(x1), int(y1)


def shift(a, dx, dy, size):
    """a placed on a size x size transparent canvas moved by dx, dy (what leaves the canvas is cut, and is reported by place())"""
    out = np.zeros((size, size, 4), np.uint8)
    h, w = a.shape[:2]
    sx0, sy0 = max(0, -dx), max(0, -dy)
    dx0, dy0 = max(0, dx), max(0, dy)
    cw, ch = min(w - sx0, size - dx0), min(h - sy0, size - dy0)
    if cw > 0 and ch > 0:
        out[dy0:dy0 + ch, dx0:dx0 + cw] = a[sy0:sy0 + ch, sx0:sx0 + cw]
    return out


def place(frames, size, bottom, center_x):
    """one shift for all frames: union bottom at size - 1 - bottom, union centre x at center_x. Returns (frames, (dx, dy))"""
    x0, y0, x1, y1 = union_bbox(frames)
    dy = (size - 1 - bottom) - y1
    dx = int(round(center_x - (x0 + x1) / 2.0))
    # keep the whole creature inside
    dx = max(-x0, min(size - 1 - x1, dx))
    return [shift(f, dx, dy, size) for f in frames], (dx, dy)


def shared_palette(frames, colours):
    """a PIL palette image of at most `colours` colours from the opaque pixels of all frames"""
    px = np.concatenate([f[f[:, :, 3] > 0][:, :3] for f in frames])
    side = int(np.ceil(np.sqrt(len(px))))
    pad = np.zeros((side * side, 3), np.uint8)
    pad[:len(px)] = px
    pad[len(px):] = px[0]
    img = Image.fromarray(pad.reshape(side, side, 3), 'RGB')
    return img.quantize(colors=colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def apply_palette(a, pal):
    rgb = Image.fromarray(np.ascontiguousarray(a[:, :, :3]), 'RGB').quantize(palette=pal, dither=Image.Dither.NONE).convert('RGB')
    out = np.array(rgb, dtype=np.uint8)
    res = np.zeros_like(a)
    solid = a[:, :, 3] > 0
    res[solid, :3] = out[solid]
    res[solid, 3] = 255
    return res


def colour_count(a):
    px = a[a[:, :, 3] > 0][:, :3]
    return len({tuple(p) for p in px})


def read_png(path):
    with Image.open(path) as im:
        return np.array(im.convert('RGBA'), dtype=np.uint8)


def walk_frame_paths(src, walk_name, direction):
    d = os.path.join(src, 'animations', walk_name, direction)
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith('.png'))


def original_center_x(dat, spr, look, scale):
    """the x centre (HD px) of the opaque union of the pair's own look, south and every phase of every group"""
    sys.path.insert(0, HERE)
    import gen_hd_overlay as g
    t = dat.outfit(look)
    xs = []
    for gi, grp in enumerate(t.groups):
        for dname in g.direction_names(grp[4]).values():
            for ph in range(grp[7]):
                a = g.compose(t, spr, gi, dname, ph, 32, None)
                cols = np.nonzero(a[:, :, 3].any(axis=0))[0]
                if len(cols):
                    xs += [int(cols.min()), int(cols.max())]
    return (min(xs) + max(xs) + 1) / 2.0 * scale


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('name')
    ap.add_argument('src')
    ap.add_argument('--size', type=int, default=128, help='frame size in px (the look at its scale)')
    ap.add_argument('--walk-name', default='walk8')
    ap.add_argument('--walk-phases', type=int, default=0, help='phases of the look walk group; 0 = keep every frame')
    ap.add_argument('--bottom', type=int, default=1)
    ap.add_argument('--colours', type=int, default=48)
    ap.add_argument('--scale', type=int, default=2)
    ap.add_argument('--pair', nargs=2, metavar=('DAT', 'SPR'))
    ap.add_argument('--look', type=int)
    ap.add_argument('--out', default=ART_DIR)
    a = ap.parse_args(argv)

    stand = {d: read_png(os.path.join(a.src, 'rotations', d + '.png')) for d in DIRS}
    walk = {d: [read_png(p) for p in walk_frame_paths(a.src, a.walk_name, d)] for d in DIRS}
    k = len(walk['south'])
    keep = list(range(k)) if not a.walk_phases else sorted({(p * k) // a.walk_phases for p in range(a.walk_phases)})
    center_x = a.size / 2.0
    if a.pair:
        sys.path.insert(0, HERE)
        from datspr import Dat, Spr
        center_x = original_center_x(Dat(a.pair[0]), Spr(a.pair[1]), a.look, a.scale)
    # the canvas of a download may be bigger than the look: pad or cut to size first, centred on the canvas
    def to_size(f):
        h, w = f.shape[:2]
        return shift(f, (a.size - w) // 2, (a.size - h) // 2, a.size) if (h, w) != (a.size, a.size) else f

    order = []     # (group, direction, index, frame)
    for d in DIRS:
        order.append((0, d, 0, to_size(stand[d])))
        for i, idx in enumerate(keep):
            order.append((1, d, i, to_size(walk[d][idx])))
    frames = [binarize(o[3]) for o in order]
    frames = [despeckle(f) for f in frames]
    frames, (dx, dy) = place(frames, a.size, a.bottom, center_x)
    pal = shared_palette(frames, a.colours)
    frames = [apply_palette(f, pal) for f in frames]
    out_dir = os.path.join(a.out, a.name)
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.endswith('.png'):
            os.remove(os.path.join(out_dir, f))
    for (g, d, i, _), f in zip(order, frames):
        Image.fromarray(f, 'RGBA').save(os.path.join(out_dir, 'g%d_%s_%02d.png' % (g, d, i)), optimize=True)
    print('%s: %d frames written (walk frames kept %s of %d), shift %d,%d, centre x %.1f, %d colours' % (
        a.name, len(frames), keep, k, dx, dy, center_x, max(colour_count(f) for f in frames)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
