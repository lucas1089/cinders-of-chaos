#!/usr/bin/env python3
"""Wings painted with PixelLab (O594): the ten rows of drawn_wings/designs.csv the code could not reach.

usage: python3 -I client/tools/sprites/gen_pixellab_wings.py clean RAW_DIR SHEETS_DIR [--only W,...]
       python3 -I client/tools/sprites/gen_pixellab_wings.py fit RAW_DIR DAT SPR [--only W,...] [--write]
       python3 -I client/tools/sprites/gen_pixellab_wings.py table SHEETS_DIR [--check]

No picture is in the repository (the O540 way). The sheets live in a private folder, one `<wings id>.png` a row:
16 columns x 4 rows of 96 px (south, north, east, west), cleaned. The repository holds
drawn_wings/pixellab_rows.csv (row, source, sha256 of the sheet, frames, the measured numbers below, notes) and
drawn_wings/pixellab_rows.sums (the digest of the 128 pictures a row gives with its sheet). gen_drawn_wings.py
takes a row from the folder when `--src SHEETS_DIR` (or CHAOS_WINGS_SRC) names it and draws it by code otherwise
(gen_drawn_wings_families.py).

How a sheet is made. PixelLab painted one face-on picture a view from a text of ours and our own code-drawn O590
picture as the guide, then a 16 frame loop of it (first frame = last frame). RAW_DIR holds what came back:
`<wings>_s_00.png` .. `_16.png` (south) and `<wings>_n_00.png` .. (north), 96 x 96, frame 0 the still picture.
`clean` makes it hold the bar of docs/SPRITE_STYLE.md "Wings":
  alpha cut at 128, crumbs under MIN_PIECE pixels dropped;
  the loop (column `ms`, `mn`): `loop A` keeps the painted loop, `still A` takes the still picture; A degrees of
  beat are added by code, each wing turning about the point where the two meet;
  the fit (`fs`, `fn`): each wing moved onto the old wing's place, angle and length;
  one palette a row for every frame of every view (PALETTE colours, median cut, no dither), then the `tint`
  (hue turn in degrees, saturation and value in per cent);
  the loop's box moved onto the box of the code-drawn row, so the pair stands where the old art stood, in the cell;
  every solid pixel that touches transparency gets the row's outline colour;
  frames 0 to 15 are kept: frame 16 is frame 0 again, so the loop closes;
  east and west are the south and the north picture turned (x and y changed over), placed by the rule of every row;
  the lights of the old art that are no part of the wing come from code at the glow level (EXTRAS: wind streaks,
  twinkles, falling drops), periodic in the frame, drawn a view (a wind streak runs left in every view).
`fit` measures `ms`, `mn`, `fs`, `fn` and `tint` once on the private pair (by hand, never at build): whole numbers
only, as the strips of designs.csv. `clean` reads no pair.
"""
import colorsys
import csv
import hashlib
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_drawn_wings as k  # noqa: E402
import gen_drawn_wings_families as fam  # noqa: E402

S = k.SIZE
F = k.FRAMES
VIEWS = ('south', 'north')                # the painted views
SIDES = (('east', 'south'), ('west', 'north'))
PALETTE = 28
MIN_PIECE = 6
FIELDS = ('wings', 'key', 'source', 'sha256', 'frames', 'ms', 'mn', 'fs', 'fn', 'tint', 'notes')
# the lights round a wing: (kind, count). streak: wind lines that run left; twinkle: stars that blink; drop: drops that fall
EXTRAS = {111: ('streak', 3), 109: ('streak', 2), 96: ('twinkle', 4), 110: ('twinkle', 4), 118: ('twinkle', 3),
          116: ('twinkle', 4), 93: ('drop', 5), 58: ('drop', 4), 104: ('twinkle', 2), 117: ('twinkle', 3)}


# ------------------------------------------------------------------------------------------------ raw frames
def read_raw(raw_dir, wings, view):
    """the 16 frames of one view as PixelLab gave them (frame 16, the first again, is left out)"""
    out = []
    for f in range(F):
        path = os.path.join(raw_dir, '%d_%s_%02d.png' % (wings, view[0], f))
        img = np.asarray(Image.open(path).convert('RGBA'))
        if img.shape != (S, S, 4):
            raise SystemExit('%s: not %d x %d' % (path, S, S))
        out.append(img)
    return out


def pieces(mask):
    """labels of the 8-connected pieces of a mask (0 outside), and their sizes"""
    lab = np.zeros(mask.shape, np.int32)
    sizes = [0]
    h, w = mask.shape
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0]:
            continue
        n = len(sizes)
        lab[y0, x0] = n
        stack, count = [(y0, x0)], 0
        while stack:
            y, x = stack.pop()
            count += 1
            for yy in range(max(0, y - 1), min(h, y + 2)):
                for xx in range(max(0, x - 1), min(w, x + 2)):
                    if mask[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = n
                        stack.append((yy, xx))
        sizes.append(count)
    return lab, sizes


def solid_of(img):
    """the solid pixels of a raw frame without its crumbs"""
    m = img[..., 3] >= 128
    lab, sizes = pieces(m)
    keep = np.asarray([s >= MIN_PIECE for s in sizes])
    return m & keep[lab]


def box_of(masks):
    any_ = np.zeros(masks[0].shape, bool)
    for m in masks:
        any_ |= m
    ys, xs = np.nonzero(any_)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def moved(a, dx, dy):
    out = np.zeros_like(a)
    x0, x1 = max(0, dx), min(S, S + dx)
    y0, y1 = max(0, dy), min(S, S + dy)
    out[y0:y1, x0:x1] = a[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
    return out


def open_edge(m):
    return m & ~(k.nb(m, 1, 0) & k.nb(m, -1, 0) & k.nb(m, 0, 1) & k.nb(m, 0, -1))


# ------------------------------------------------------------------------------------------------ loop and fit
# PixelLab paints the right wing but not at the old wing's angle, length and spread, and its loop beats too little
# or too much. So a view carries numbers measured once on the private pair (`fit`), kept in pixellab_rows.csv:
#   ms, mn   `loop A` or `still A`: the painted loop or the still picture, plus A degrees of beat by code;
#   fs, fn   "split  dx dy turn wide high" for the left wing and the same five for the right one. split: the column
#            that parts the two wings; dx, dy: px; turn: degrees about the point where the wings meet; wide, high: %.
FIT_NONE = (0, 0, 0, 100, 100)
FIT_STEPS = (4, 4, 8, 12, 12)
FIT_LO = (-30, -30, -40, 70, 70)
FIT_HI = (30, 30, 40, 140, 140)
BEATS = (0, 3, 6, 9, 12, 15)
PHASE = 0.2                   # so no two frames of the beat are the same angle
LAG = 0.6                     # the right wing follows the left


def split_of(masks):
    """(split column, joint): the column between the two wings (the emptiest one of the middle of the still
    picture) and the point where they meet (that column, the lowest row of the art near it)"""
    m = masks[0]
    x0, y0, x1, y1 = box_of([m])
    lo, hi = x0 + (x1 - x0) * 3 // 10, x0 + (x1 - x0) * 9 // 10
    cols = m[:, lo:hi + 1].sum(axis=0)
    best = int(np.argmin(cols + np.abs(np.arange(len(cols)) - len(cols) * 0.6) * 0.01))
    xs = lo + best
    near = m[:, max(0, xs - 6):xs + 7]
    rows = np.nonzero(near.any(axis=1))[0]
    return xs, (xs, int(rows.max()) if len(rows) else y1)


def parse_motion(text):
    """'' -> ('loop', 0)"""
    v = (text or '').split()
    if not v:
        return 'loop', 0
    if len(v) != 2 or v[0] not in ('loop', 'still'):
        raise ValueError('a loop is `loop A` or `still A`')
    return v[0], int(v[1])


def parse_fit(text):
    """'' -> None; else (split, left five, right five)"""
    v = [int(t) for t in (text or '').split()]
    if not v:
        return None
    if len(v) != 11:
        raise ValueError('a fit is 11 whole numbers')
    return v[0], tuple(v[1:6]), tuple(v[6:11])


def fit_text(fit):
    return '%d  %s  %s' % (fit[0], ' '.join('%d' % n for n in fit[1]), ' '.join('%d' % n for n in fit[2]))


def _wing_map(joint, five, extra_turn=0.0):
    """for every canvas pixel the source pixel of a wing moved by `five` about the joint (nearest), and what is inside"""
    dx, dy, turn, wide, high = five
    a = math.radians(turn + extra_turn)
    qx = k.XX - joint[0] - dx
    qy = k.YY - joint[1] - dy
    rx = math.cos(a) * qx + math.sin(a) * qy               # turn back
    ry = -math.sin(a) * qx + math.cos(a) * qy
    sx = np.rint(joint[0] + rx * 100.0 / wide).astype(np.int32)
    sy = np.rint(joint[1] + ry * 100.0 / high).astype(np.int32)
    ok = (sx >= 0) & (sx < S) & (sy >= 0) & (sy < S)
    return np.clip(sy, 0, S - 1), np.clip(sx, 0, S - 1), ok


def fitted(imgs, masks, fit, joint, motion=('loop', 0)):
    """the frames and masks of a view: the loop of `motion`, each wing moved by its five numbers; the right wing
    lies over the left"""
    src, beat = motion
    if src == 'still':
        imgs, masks = [imgs[0]] * len(imgs), [masks[0]] * len(masks)
    if (fit is None or (fit[1] == FIT_NONE and fit[2] == FIT_NONE)) and not beat:
        return list(imgs), list(masks)
    if fit is None:
        fit = (split_of(masks)[0], FIT_NONE, FIT_NONE)
    xs = fit[0]
    side = [k.XX < xs, k.XX >= xs]
    still = [_wing_map(joint, fit[1]), _wing_map(joint, fit[2])] if not beat else None
    out_i, out_m = [], []
    for f, (img, m) in enumerate(zip(imgs, masks)):
        if beat:
            ph = k.TAU * f / len(imgs) + PHASE
            maps = [_wing_map(joint, fit[1], beat * math.sin(ph)), _wing_map(joint, fit[2], -beat * math.sin(ph - LAG))]
        else:
            maps = still
        ri = np.zeros_like(img)
        rm = np.zeros_like(m)
        for sel, (sy, sx, ok) in zip(side, maps):
            part = (m & sel)[sy, sx] & ok
            ri[part] = img[sy, sx][part]
            rm |= part
        out_i.append(ri)
        out_m.append(rm)
    return out_i, out_m


def view_distance(old, new):
    """the shape and layout part of fam.likeness for one view (0.4 shape + 0.2 layout), masks in, the smaller the nearer"""
    ob, nb_ = fam._alpha_box(old), fam._alpha_box(new)
    if ob is None or nb_ is None:
        return 1.0
    on = [fam._norm_mask(m, ob) for m in old]
    nn = [fam._norm_mask(m, nb_) for m in new]
    ious = []
    for f in range(len(nn)):
        a, b = on[f * len(on) // len(nn)], nn[f]
        u = (a | b).sum()
        ious.append((a & b).sum() / float(u) if u else 0.0)
    ow, oh = ob[2] - ob[0], ob[3] - ob[1]
    nw, nh = nb_[2] - nb_[0], nb_[3] - nb_[1]
    asp = abs(math.log((ow / float(oh)) / (nw / float(nh))))
    of = np.mean([m.sum() for m in old]) / float(ow * oh)
    nf = np.mean([m.sum() for m in new]) / float(nw * nh)
    orow = np.mean([m.mean(axis=1) for m in on], axis=0)
    nrow = np.mean([m.mean(axis=1) for m in nn], axis=0)
    prof = float(np.abs(orow / max(orow.sum(), 1e-9) - nrow / max(nrow.sum(), 1e-9)).sum()) / 2.0
    return 0.4 * (1.0 - float(np.mean(ious))) + 0.2 * min(1.0, 0.8 * min(asp, 1.0) + 1.2 * abs(of - nf) + prof)


def moved_share(masks):
    """the share of a loop's silhouette that moves, as fam.likeness reads it"""
    box = fam._alpha_box(masks)
    return fam.moved([fam._norm_mask(m, box) for m in masks])


def fit_view(old, masks, log=None):
    """(motion, fit) of one view: the loop that beats as much as the old one, then its wings moved onto the old loop"""
    xs, joint = split_of(masks)
    blank = [np.zeros((S, S, 4), np.uint8)] * len(masks)
    want = moved_share(old)
    motion, gap = ('loop', 0), None
    for src in ('loop', 'still'):
        for beat in BEATS:
            if src == 'still' and not beat:
                continue
            _, ms = fitted(blank, masks, None, joint, (src, beat))
            g = abs(moved_share(ms) - want) + (0.03 if src == 'still' else 0.0)   # the painted loop when it is as near
            if gap is None or g < gap - 1e-9:
                motion, gap = (src, beat), g

    def dist(left, right):
        _, ms = fitted(blank, masks, (xs, tuple(left), tuple(right)), joint, motion)
        if min(int(m.sum()) for m in ms) < 120:
            return 9.0
        x0, y0, x1, y1 = box_of(ms)
        if x1 - x0 > S - 6 or y1 - y0 > S - 6:
            return 9.0
        return view_distance(old, ms) + 0.15 * min(1.0, abs(moved_share(ms) - want) * 2.0)

    cur = [list(FIT_NONE), list(FIT_NONE)]
    best = start = dist(*cur)
    steps = list(FIT_STEPS)
    while max(steps) >= 1:
        better = False
        for w in (0, 1):
            for i in range(5):
                if steps[i] < 1:
                    continue
                for sign in (1, -1):
                    v = cur[w][i] + sign * steps[i]
                    if not FIT_LO[i] <= v <= FIT_HI[i]:
                        continue
                    trial = [list(cur[0]), list(cur[1])]
                    trial[w][i] = v
                    d = dist(*trial)
                    if d < best - 1e-6:
                        best, cur, better = d, trial, True
        if not better:
            steps = [st // 2 for st in steps]
    if log:
        log('    %s %d, distance %.3f -> %.3f' % (motion[0], motion[1], start, best))
    return motion, (xs, tuple(cur[0]), tuple(cur[1]))


# ------------------------------------------------------------------------------------------------ colour
def palette_of(frames, masks, colours=PALETTE):
    """one palette for a row: median cut over every solid pixel of every frame, no dither"""
    px = np.concatenate([img[..., :3][m] for img, m in zip(frames, masks)], axis=0)
    strip = Image.fromarray(np.ascontiguousarray(px.reshape(1, -1, 3)), 'RGB')
    q = strip.quantize(colors=colours, method=Image.MEDIANCUT, dither=Image.NONE)
    pal = np.asarray(q.getpalette()[:colours * 3], np.uint8).reshape(-1, 3)
    used = sorted(set(np.asarray(q).ravel().tolist()))
    return pal[used]


def palette_index(rgb, pal):
    d = ((rgb[:, None, :].astype(np.int32) - pal[None, :, :].astype(np.int32)) ** 2).sum(axis=2)
    return np.argmin(d, axis=1)


TINT_NONE = (0, 100, 100)


def parse_tint(text):
    v = [int(t) for t in (text or '').split()]
    if not v:
        return TINT_NONE
    if len(v) != 3:
        raise ValueError('a tint is 3 whole numbers')
    return tuple(v)


def tinted(pal, tint):
    """a palette with its hue turned (degrees) and its saturation and value scaled (per cent)"""
    if tuple(tint) == TINT_NONE:
        return pal
    out = []
    for r, g, b in pal.tolist():
        h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
        rr, gg, bb = colorsys.hsv_to_rgb((h + tint[0] / 360.0) % 1.0, k.clamp(s * tint[1] / 100.0, 0.0, 1.0),
                                         k.clamp(v * tint[2] / 100.0, 0.0, 1.0))
        out.append((int(round(rr * 255)), int(round(gg * 255)), int(round(bb * 255))))
    return np.asarray(out, np.uint8)


def fit_tint(old_hist, pal, counts, outline, edge_count):
    """the tint that brings the colour areas of a row nearest to the old art's (fam.colour_hist), a small one
    preferred; counts: pixels a palette colour, edge_count: outline pixels"""
    def dist(tint):
        cols = np.concatenate([tinted(pal, tint), np.asarray([outline], np.uint8)], axis=0)
        img = np.zeros((1, len(cols), 4), np.uint8)
        img[0, :, :3] = cols
        img[0, :, 3] = 255
        hist = np.zeros(16)
        weights = list(counts) + [edge_count]
        for i, w in enumerate(weights):
            hist += w * fam.colour_hist([img[:, i:i + 1]])
        hist /= max(hist.sum(), 1e-9)
        return float(np.abs(hist - old_hist).sum() / 2.0) + abs(tint[0]) * 0.0004 + (abs(tint[1] - 100) + abs(tint[2] - 100)) * 0.0002

    cur = list(TINT_NONE)
    best = dist(cur)
    lo, hi = (-40, 30, 70), (40, 200, 150)
    steps = [16, 40, 20]
    while max(steps) >= 2:
        better = False
        for i in range(3):
            for sign in (1, -1):
                trial = list(cur)
                trial[i] += sign * steps[i]
                if not lo[i] <= trial[i] <= hi[i]:
                    continue
                d = dist(trial)
                if d < best - 1e-6:
                    best, cur, better = d, trial, True
        if not better:
            steps = [st // 2 for st in steps]
    return tuple(cur)


# ------------------------------------------------------------------------------------------------ placing
def code_box(sp, view):
    """the box of the code-drawn loop of a row in one face-on view (solid pixels)"""
    keep, check = fam.SRC_DIR, fam.SRC_CHECK
    fam.use_src('')
    try:
        masks = [k.merge(*fam.render_frame(sp, view, f))[..., 3] == 255 for f in range(F)]
    finally:
        fam.use_src(keep, check)
    return box_of(masks)


def shift_for(masks, target):
    """(dx, dy) that puts the middle of the loop's box on the middle of the target box and keeps it off the border"""
    x0, y0, x1, y1 = box_of(masks)
    if x1 - x0 > S - 5 or y1 - y0 > S - 5:
        raise SystemExit('the art is larger than the cell')
    dx = int(round((target[0] + target[2]) / 2.0 - (x0 + x1) / 2.0))
    dy = int(round((target[1] + target[3]) / 2.0 - (y0 + y1) / 2.0))
    dx = min(max(dx, 2 - x0), S - 3 - x1)
    dy = min(max(dy, 2 - y0), S - 3 - y1)
    return dx, dy


# ------------------------------------------------------------------------------------------------ lights
def extras(sp, view, masks):
    """[[(x, y, size)] a frame]: the lights of a row in one view; size as Canvas.spark (0 a glow dot, 1 a core with
    four glow arms). Twinkles and drops stay inside the box of the loop, at places the wing never covers; a wind
    streak starts over the wing and runs left, out of the box, as in the old art."""
    kind, n = EXTRAS.get(sp.wings, ('none', 0))
    out = [[] for _ in range(F)]
    if kind == 'none':
        return out
    any_ = np.zeros((S, S), bool)
    for m in masks:
        any_ |= m
    near = any_.copy()
    for _ in range(2):
        near = k.dilate4(near)
    x0, y0, x1, y1 = box_of(masks)
    salt = sp.wings * 7 + ('south', 'north', 'east', 'west').index(view)
    for i in range(n):
        h1, h2, h3 = fam._hash(salt, i * 3), fam._hash(salt, i * 3 + 1), fam._hash(salt, i * 3 + 2)
        off = int(h3 * F)
        if kind == 'streak':                               # a line of glow that runs left over the wings
            y = int(y0 + 1 + h1 * max(4, (y1 - y0) * 0.5))
            xs = int(x0 + 4 + h2 * max(4, (x1 - x0) * 0.35))
            ln = 7 + int(h1 * 5)
            for f in range(F):
                t = (f + off) % F
                if t >= 11:
                    continue
                for j in range(ln):
                    out[f].append((xs - 3 * t - j, y - t // 4, 0))
        elif kind == 'twinkle':                            # a star that blinks at one place
            spot = None
            for tries in range(60):
                hx, hy = fam._hash(salt + 100 * tries, i * 3), fam._hash(salt + 100 * tries, i * 3 + 1)
                cx = int(x0 + 2 + hx * max(1, x1 - x0 - 4))
                cy = int(y0 + 2 + hy * max(1, y1 - y0 - 4))
                if 4 <= cx < S - 4 and 4 <= cy < S - 4 and not near[cy - 1:cy + 2, cx - 1:cx + 2].any():
                    spot = (cx, cy)
                    break
            if spot is None:
                continue
            for f in range(F):
                t = (f + off) % F
                if t in (0, 5):
                    out[f].append((spot[0], spot[1], 0))
                elif 1 <= t <= 4:
                    out[f].append((spot[0], spot[1], 1))
        elif kind == 'drop':                               # a drop that falls from under the wing, down to the box's foot
            best = None
            for tries in range(30):
                x = int(x0 + 3 + fam._hash(salt + 100 * tries, i * 3) * max(1, x1 - x0 - 6))
                col = np.nonzero(any_[:, x])[0]
                top = (int(col.max()) + 3) if len(col) else y0 + 3
                if y1 - top >= 4:
                    best = (x, top)
                    break
            if best is None:
                continue
            x, top = best
            for f in range(F):
                t = (f + off) % F
                if t <= min(8, y1 - top):
                    out[f].append((x, top + t, 0))
                    if t:
                        out[f].append((x, top + t - 1, 0))
    return out


def light_up(frame, lights, glow):
    """the lights of one frame on a cleaned picture; a light never sits on the wing"""
    a = frame[..., 3]
    for x, y, size in lights:
        if not (2 <= x < S - 2 and 2 <= y < S - 2):
            continue
        spots = [(x, y)] if size == 0 else [(x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
        if any(a[yy, xx] == 255 for xx, yy in spots):
            continue
        for xx, yy in spots:
            frame[yy, xx, :3] = glow
            a[yy, xx] = k.GLOW_ALPHA
        if size:
            a[y, x] = 255
    return frame


# ------------------------------------------------------------------------------------------------ a row
def wings_of(sp, raw, row):
    """{view: (16 RGBA frames, 16 masks)} of the two painted views: the loop, the fit, the row's box; raw colours"""
    out = {}
    for v in VIEWS:
        masks = [solid_of(img) for img in raw[v]]
        joint = split_of(masks)[1]
        imgs, masks = fitted(raw[v], masks, parse_fit(row.get('f' + v[0])), joint, parse_motion(row.get('m' + v[0])))
        dx, dy = shift_for(masks, code_box(sp, v))
        out[v] = ([moved(img, dx, dy) for img in imgs], [moved(m, dx, dy) for m in masks])
    return out


def clean_row(sp, raw, row=None):
    """raw: {view: 16 raw RGBA frames} -> {view: 16 cleaned RGBA frames} (south, north, east, west) of one row"""
    row = row or {}
    wings = wings_of(sp, raw, row)
    pal0 = palette_of([img for v in VIEWS for img in wings[v][0]], [m for v in VIEWS for m in wings[v][1]])
    pal = tinted(pal0, parse_tint(row.get('tint')))
    outline = np.asarray(sp.outline, np.uint8)
    glow = np.asarray(sp.glow, np.uint8)
    plain = {}
    for v in VIEWS:
        frames = []
        for img, m in zip(*wings[v]):
            res = np.zeros((S, S, 4), np.uint8)
            res[..., :3][m] = pal[palette_index(img[..., :3][m], pal0)]
            res[..., 3][m] = 255
            res[..., :3][open_edge(m)] = outline
            frames.append(res)
        plain[v] = frames
    for d, src in SIDES:                                   # the side views: the face-on loop turned, as for every row
        any_ = np.zeros((S, S), bool)
        for m in wings[src][1]:
            any_ |= m
        dx, dy = fam.side_shift_of(any_, d)
        plain[d] = [fam._turned(img, dx, dy) for img in plain[src]]
    out = {}
    for v in fam.SHEET_VIEWS:
        lights = extras(sp, v, [img[..., 3] == 255 for img in plain[v]])
        out[v] = [light_up(img.copy(), lights[f], glow) for f, img in enumerate(plain[v])]
    return out


def sheet_of(cleaned):
    sheet = np.zeros((S * len(fam.SHEET_VIEWS), S * F, 4), np.uint8)
    for r, v in enumerate(fam.SHEET_VIEWS):
        for f in range(F):
            sheet[r * S:(r + 1) * S, f * S:(f + 1) * S] = cleaned[v][f]
    return sheet


def clean(raw_dir, sheets_dir, only=None, log=print, rows=None):
    """the sheets of the painted rows from their raw frames; rows: {wings: row} in place of pixellab_rows.csv"""
    os.makedirs(sheets_dir, exist_ok=True)
    rows = fam.sheet_rows() if rows is None else rows
    done = []
    for sp in fam.load():
        if sp.wings not in rows or (only and sp.wings not in only):
            continue
        raw = {v: read_raw(raw_dir, sp.wings, v) for v in VIEWS}
        sheet = sheet_of(clean_row(sp, raw, rows[sp.wings]))
        path = os.path.join(sheets_dir, '%d.png' % sp.wings)
        Image.fromarray(sheet, 'RGBA').save(path, optimize=False, compress_level=9)
        keep, check = fam.SRC_DIR, fam.SRC_CHECK
        fam.use_src(sheets_dir, check=False)
        try:
            bad = fam.bar_problems(sp)
        finally:
            fam.use_src(keep, check)
        log('%3d %-16s %s%s' % (sp.wings, sp.key, path, '' if not bad else '   BAR: %s' % '; '.join(bad)))
        done.append((sp.wings, bad))
    return done


# ------------------------------------------------------------------------------------------------ the table
def read_table():
    with open(fam.SHEET_CSV, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def table_text(rows):
    return ''.join(','.join(row[name] for name in FIELDS) + '\n' for row in [dict(zip(FIELDS, FIELDS))] + rows)


def fit(raw_dir, dat_path, spr_path, only=None, write=False, log=print):
    """measure the loop, the fit and the tint of every painted row on the old art of a pair; --write puts the
    numbers in pixellab_rows.csv"""
    from datspr import Dat, Spr
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_table()
    by = {sp.wings: sp for sp in fam.load()}
    for row in rows:
        sp = by[int(row['wings'])]
        if only and sp.wings not in only:
            continue
        old, _ = fam.old_frames(dat, spr, sp.look)
        raw = {v: read_raw(raw_dir, sp.wings, v) for v in VIEWS}
        for v in VIEWS:
            log('%3d %-16s %s' % (sp.wings, sp.key, v))
            motion, fit_ = fit_view([f[..., 3] >= 128 for f in old[v]], [solid_of(img) for img in raw[v]], log)
            row['m' + v[0]] = '%s %d' % motion
            row['f' + v[0]] = fit_text(fit_)
            log('    %s' % row['f' + v[0]])
        wings = wings_of(sp, raw, row)
        frames = [img for v in VIEWS for img in wings[v][0]]
        masks = [m for v in VIEWS for m in wings[v][1]]
        pal = palette_of(frames, masks)
        counts = np.zeros(len(pal))
        edges = 0
        for img, m in zip(frames, masks):
            inner = m & ~open_edge(m)
            counts += np.bincount(palette_index(img[..., :3][inner], pal), minlength=len(pal))
            edges += int(open_edge(m).sum())
        row['tint'] = '%d %d %d' % fit_tint(fam.colour_hist([f for d in k.DIRS for f in old[d]]), pal, counts, sp.outline, edges)
        log('    tint %s' % row['tint'])
    if write:
        with open(fam.SHEET_CSV, 'w', newline='\n', encoding='utf-8') as f:
            f.write(table_text(rows))
        fam._SHEET_ROWS.clear()
    return rows


def sha256_file(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def table(sheets_dir, check=False, log=print):
    """write (or hold) the sha256 column of pixellab_rows.csv and pixellab_rows.sums from a sheets folder"""
    rows = read_table()
    for row in rows:
        row['sha256'] = sha256_file(os.path.join(sheets_dir, '%s.png' % row['wings']))
    bad = fam.write_or_check(fam.SHEET_CSV, table_text(rows), check)
    fam._SHEET_ROWS.clear()
    keep, keep_check = fam.SRC_DIR, fam.SRC_CHECK
    fam.use_src(sheets_dir, check=not bad)
    try:
        want = {int(row['wings']) for row in rows}
        specs = [sp for sp in fam.load() if sp.wings in want]
        sums = {sp.wings: fam.digest(fam.patterns(sp)) for sp in specs}
        for sp in specs:
            for what in fam.bar_problems(sp):
                bad.append('%d %s: %s' % (sp.wings, sp.key, what))
    finally:
        fam.use_src(keep, keep_check)
    bad += fam.write_or_check(fam.SHEET_SUMS, fam.sums_text(sums), check)
    for line in bad:
        log(line)
    log('%d PixelLab rows%s' % (len(rows), '' if bad else ': ok'))
    return bad


def main(argv=None):
    argv = sys.argv[1:] if argv is None else list(argv)
    only = None
    if '--only' in argv:
        only = {int(v) for v in argv[argv.index('--only') + 1].split(',')}
    if len(argv) >= 3 and argv[0] == 'clean':
        return 1 if any(bad for _, bad in clean(argv[1], argv[2], only)) else 0
    if len(argv) >= 4 and argv[0] == 'fit':
        fit(argv[1], argv[2], argv[3], only, '--write' in argv)
        return 0
    if len(argv) >= 2 and argv[0] == 'table':
        return 1 if table(argv[1], '--check' in argv) else 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
