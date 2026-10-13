#!/usr/bin/env python3
"""Deterministic clean-up of painted 32x32 item candidates (PixelLab Create image Pro results) into game-ready item
sprites. No painting happens here: the same raw PNGs and picks give byte-identical sprites.

    python3 -I item_post.py --picks PICKS.csv --raw RAW_DIR --out OUT_DIR [--colours 24] [--margin 1]
    python3 -I item_post.py --check OUT_DIR [--colours 24] [--margin 1]

PICKS.csv columns: variant,piece,tag,cand,slot[,roll][,box]
  tag    a folder of RAW_DIR holding the job's candidates (cand_<NN>.png)
  cand   the candidate number
  slot   where the item lies in the candidate: full (a 32x32 job), left / right (a 64x32 pair job),
         tl / tr / bl / br (a 64x64 2x2 job). The opaque blobs whose centre falls in the slot are the item.
  roll   optional "dx dy": the candidate is first rolled (wrapped) by whole pixels; some jobs come back wrapped
         around the canvas edge (half an item on the far side)
  box    optional "x0 y0 x1 y1" (x1, y1 exclusive): pixels outside it are cleared first, for two items that touch
Output: OUT_DIR/<variant>/<piece>.png (32x32 RGBA) and OUT_DIR/<variant>/strip.png (the pieces in pick order).

Steps, per item:
  1. alpha cut to 0 / 255 at 128; the item is the biggest blob (8-connected) whose centre is in the slot, plus the
     blobs of at least `speck` pixels lying inside its box (+2 px); everything else is dropped;
  2. the item is cropped; if it is larger than 32 - 2 * margin it is shrunk with nearest sampling (aspect kept);
  3. outline: every opaque pixel on the silhouette edge (a 4-neighbour is transparent or off the canvas) whose luma
     is above `rim` is darkened to `dark` x its colour, so every item keeps a 1 px dark rim on any background;
  4. palette clamp: median cut over the item's opaque pixels to at most `colours` colours, every pixel snapped to
     its box (no dither);
  5. centred in 32x32 (the extra pixel of an odd gap goes right / down).
"""
import argparse
import csv
import os
import sys

import numpy as np
from PIL import Image

CELL = 32


def cut_alpha(a):
    a = a.copy()
    on = a[..., 3] >= 128
    a[..., 3] = np.where(on, 255, 0).astype(np.uint8)
    a[~on, :3] = 0
    return a


def label8(mask):
    """8-connected components: (labels, count). Plain BFS so the tool needs numpy and Pillow only."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not lab[y, x]:
                n += 1
                lab[y, x] = n
                stack = [(y, x)]
                while stack:
                    cy, cx = stack.pop()
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = cy + dy, cx + dx
                            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                                lab[ny, nx] = n
                                stack.append((ny, nx))
    return lab, n


SLOTS = {'full': (0, 0, 1, 1), 'left': (0, 0, 0.5, 1), 'right': (0.5, 0, 1, 1),
         'tl': (0, 0, 0.5, 0.5), 'tr': (0.5, 0, 1, 0.5), 'bl': (0, 0.5, 0.5, 1), 'br': (0.5, 0.5, 1, 1)}


def take_slot(a, slot, speck):
    """The item of `slot`: the blobs whose pixel centre lies inside the slot's box, specks dropped."""
    a = cut_alpha(a)
    h, w = a.shape[:2]
    x0, y0, x1, y1 = SLOTS[slot]
    lab, n = label8(a[..., 3] > 0)
    keep = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        cy, cx = ys.mean() / h, xs.mean() / w
        if x0 <= cx < x1 and y0 <= cy < y1:
            keep.append((len(ys), i))
    if not keep:
        raise SystemExit('no item in slot %s' % slot)
    big = max(keep)[1]
    ys, xs = np.nonzero(lab == big)
    y0b, y1b, x0b, x1b = ys.min() - 2, ys.max() + 2, xs.min() - 2, xs.max() + 2
    ids = [big]
    for s, i in keep:
        if i != big and s >= speck:
            ys, xs = np.nonzero(lab == i)
            if ys.min() >= y0b and ys.max() <= y1b and xs.min() >= x0b and xs.max() <= x1b:
                ids.append(i)      # a loose part of the item (a gem, a plume tip) inside its box
    out = a.copy()
    out[~np.isin(lab, ids)] = 0
    return out


def crop(a):
    ys, xs = np.nonzero(a[..., 3])
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def fit(a, margin):
    lim = CELL - 2 * margin
    h, w = a.shape[:2]
    if h > lim or w > lim:
        k = lim / max(h, w)
        nw, nh = max(1, int(round(w * k))), max(1, int(round(h * k)))
        a = cut_alpha(np.asarray(Image.fromarray(a, 'RGBA').resize((nw, nh), Image.NEAREST)))
        a = crop(a)
    return a


def outline(a, rim, dark):
    a = a.copy()
    on = a[..., 3] > 0
    pad = np.pad(on, 1)
    edge = on & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    rgb = a[..., :3].astype(np.float64)
    luma = rgb @ [0.299, 0.587, 0.114]
    hit = edge & (luma > rim)
    a[hit, :3] = np.clip(rgb[hit] * dark, 0, 255).astype(np.uint8)
    return a


def clamp(a, colours):
    on = a[..., 3] > 0
    px = a[on][:, :3]
    if len(np.unique(px, axis=0)) <= colours:
        return a
    strip = Image.fromarray(px.reshape(1, -1, 3).astype(np.uint8), 'RGB')
    q = strip.quantize(colors=colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.array(q.getpalette()[:3 * colours], np.uint8).reshape(-1, 3)
    idx = np.asarray(q).reshape(-1)
    out = a.copy()
    out[on, :3] = pal[idx]
    return out


def centre(a):
    h, w = a.shape[:2]
    out = np.zeros((CELL, CELL, 4), np.uint8)
    y0, x0 = (CELL - h + 1) // 2, (CELL - w + 1) // 2
    out[y0:y0 + h, x0:x0 + w] = a
    return out


def process(a, slot='full', colours=24, margin=1, speck=4, rim=60, dark=0.35, roll=None, box=None):
    a = np.asarray(a, np.uint8)
    if roll:
        a = np.roll(a, (roll[1], roll[0]), axis=(0, 1))
    if box:
        keep = np.zeros(a.shape[:2], bool)
        keep[box[1]:box[3], box[0]:box[2]] = True
        a = a.copy()
        a[~keep] = 0
    it = crop(take_slot(a, slot, speck))
    it = fit(it, margin)
    it = outline(it, rim, dark)
    it = clamp(it, colours)
    return centre(it)


def check(a, colours, margin):
    """Problems of one finished sprite (an empty list when it is fine)."""
    bad = []
    if a.shape != (CELL, CELL, 4):
        bad.append('size %s' % (a.shape,))
        return bad
    if not set(np.unique(a[..., 3])) <= {0, 255}:
        bad.append('alpha not 0/255')
    on = a[..., 3] > 0
    n = len(np.unique(a[on][:, :3], axis=0))
    if n > colours:
        bad.append('%d colours' % n)
    ys, xs = np.nonzero(on)
    if ys.min() < margin or xs.min() < margin or ys.max() > CELL - 1 - margin or xs.max() > CELL - 1 - margin:
        bad.append('inside the %d px margin' % margin)
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--picks')
    ap.add_argument('--raw')
    ap.add_argument('--out')
    ap.add_argument('--check')
    ap.add_argument('--colours', type=int, default=24)
    ap.add_argument('--margin', type=int, default=1)
    o = ap.parse_args()
    if o.check:
        bad = 0
        for root, _, files in sorted(os.walk(o.check)):
            for f in sorted(files):
                if f.endswith('.png') and f != 'strip.png':
                    p = check(np.asarray(Image.open(os.path.join(root, f)).convert('RGBA')), o.colours, o.margin)
                    if p:
                        bad += 1
                        print(os.path.join(root, f), ', '.join(p))
        print('item check:', 'OK' if not bad else '%d bad' % bad)
        return 1 if bad else 0
    if not (o.picks and o.raw and o.out):
        ap.error('--picks, --raw and --out are needed (or --check)')
    strips = {}
    for r in csv.DictReader(open(o.picks, newline='')):
        src = os.path.join(o.raw, r['tag'], 'cand_%02d.png' % int(r['cand']))
        roll = [int(v) for v in (r.get('roll') or '').split()] or None
        box = [int(v) for v in (r.get('box') or '').split()] or None
        a = process(np.asarray(Image.open(src).convert('RGBA')), r['slot'].strip() or 'full', o.colours, o.margin,
                    roll=roll, box=box)
        d = os.path.join(o.out, r['variant'])
        os.makedirs(d, exist_ok=True)
        Image.fromarray(a, 'RGBA').save(os.path.join(d, r['piece'] + '.png'))
        strips.setdefault(r['variant'], []).append(a)
        n = len(np.unique(a[a[..., 3] > 0][:, :3], axis=0))
        print('%s/%s <- %s #%s %s: %d colours' % (r['variant'], r['piece'], r['tag'], r['cand'], r['slot'], n))
    for v, ims in strips.items():
        Image.fromarray(np.concatenate(ims, axis=1), 'RGBA').save(os.path.join(o.out, v, 'strip.png'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
