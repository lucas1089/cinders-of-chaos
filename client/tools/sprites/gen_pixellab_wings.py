#!/usr/bin/env python3
"""Wings painted with PixelLab (O594, layout O620): the ten rows of drawn_wings/designs.csv the code could not reach.

usage: python3 -I client/tools/sprites/gen_pixellab_wings.py clean RAW_DIR SHEETS_DIR [--only W,...]
       python3 -I client/tools/sprites/gen_pixellab_wings.py table SHEETS_DIR [--check]
       python3 -I client/tools/sprites/gen_pixellab_wings.py measure SHEETS_DIR [--only W,...]

No picture is in the repository (the O540 way). The sheets live in a private folder, one `<wings id>.png` a row:
16 columns x 4 rows of 96 px (south, north, east, west), cleaned. The repository holds
drawn_wings/pixellab_rows.csv (row, source, sha256 of the sheet, frames, the numbers below, notes) and
drawn_wings/pixellab_rows.sums (the digest of the 128 pictures a row gives with its sheet). gen_drawn_wings.py
takes a row from the folder when `--src SHEETS_DIR` (or CHAOS_WINGS_SRC) names it and draws it by code otherwise
(gen_drawn_wings_families.py).

How a sheet is made. PixelLab painted one face-on picture a view from a text of ours and a picture of ours as the
guide (O594: our code-drawn O590 picture; O620, rows 111, 96 and 118: one wing alone, 48 px, the north from the
south picture with its colours), for most rows also a 16 frame loop (first frame = last frame). RAW_DIR holds what
came back: `<wings>_s_00.png` .. `_16.png` (south) and `<wings>_n_00.png` .. (north), 96 x 96, frame 0 the still
picture. `clean` makes it hold the bar of docs/SPRITE_STYLE.md "Wings" and the layout of O620:
  alpha cut at 128, crumbs under MIN_PIECE pixels dropped;
  the layout (see "the layout" below): the left wing of a view is taken, its root put on the join over the anchor,
  the right wing is its mirror picture; east and west are own side views made of the same wing, rising from the
  same join; a knot of the outline colour holds the pair together;
  the loop (column `ms`, `mn`): `loop A` keeps the painted loop, `still A` takes the still picture; A degrees of
  beat are added by code, the wing turning about its root;
  one palette a row for every frame of every view (PALETTE colours, median cut, no dither), then the `tint`
  (hue turn in degrees, saturation and value in per cent);
  every solid pixel that touches transparency gets the row's outline colour; a `rim` colour (rrggbb) lights the
  line just inside it, for a dark wing on dark ground;
  frames 0 to 15 are kept: frame 16 is frame 0 again, so the loop closes;
  the lights of the old art that are no part of the wing come from code at the glow level (EXTRAS: wind streaks,
  twinkles, falling drops), periodic in the frame, drawn a view (a wind streak runs left in every view).
`clean` reads no pair. `measure` prints the numbers of the layout for any folder of sheets; `clean` and `table`
refuse a row that does not hold them (fit_problems).
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
FIELDS = ('wings', 'key', 'source', 'sha256', 'frames', 'ms', 'mn', 'fs', 'fn', 'tint', 'rim', 'notes')
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


# ------------------------------------------------------------------------------------------------ the layout (O620)
# One wing is painted, the pair is made by rule, so every row stands the same way on the body:
#   north, south   the left wing of the painted view with its root on the join, the right wing its mirror picture
#                  about the anchor column. The pair is as wide left as right and its middle is the torso's middle.
#   east, west     own side views: the same wing seen from the side (SIDE_NEAR of its width), the far wing behind it
#                  (SIDE_FAR, a step darker, SIDE_FAR_AT away), both rising from the join. East is made of the south
#                  wing and trails left; west of the north wing and trails right. Nothing hangs under the body.
#   the join       JOIN, the shoulder line over the anchor, the same point in the four views; a knot of the outline
#                  colour lies on it and every wing reaches it (a bridge is drawn when a painted loop lets go).
# A view carries numbers in pixellab_rows.csv:
#   ms, mn   `loop A` or `still A`: the painted loop or the still picture, plus A degrees of beat by code;
#   fs, fn   "split rx ry turn wide high": the column that parts the painted wings (-1: found), the root of the left
#            wing in the raw picture (-1 -1: found), degrees the wing is turned about its root, its width and height
#            in per cent. '' is "-1 -1 -1 0 100 100".
JOIN = (k.ANCHOR[0], k.ANCHOR[1] - 6)
KNOT = 1                      # the knot is (2 KNOT + 1) px square
EDGE = 3                      # px of the cell border no wing pixel may enter (2 for the outline rule and the lights)
FIT_NONE = (-1, -1, -1, 0, 100, 100)
PHASE = 0.1                   # so frame 0 and frame 8 of the beat are not the same angle
SIDE_NEAR, SIDE_FAR = 0.7, 0.55
SIDE_TURN = {'near': 18, 'far': 28}     # degrees a side wing is raised (it trails less and stands more)
SIDE_FAR_AT = (2, -3)
SIDE_FAR_SHADE = 0.74
SIDE_LAG = 0.5                # the far wing follows the near one
SIDE_OF = {'east': 'south', 'west': 'north'}


def wave(f, lag=0.0):
    """the beat at frame f, -1 to 1: half a sine, half a saw, so every frame is a step away from the next"""
    t = k.TAU * f / F + PHASE - lag
    return 0.5 * math.sin(t) + 0.5 * (2.0 / math.pi) * math.asin(math.sin(t))


def split_of(masks):
    """the column between the two painted wings: the emptiest one of the middle of the still picture"""
    m = masks[0]
    x0, y0, x1, y1 = box_of([m])
    lo, hi = x0 + (x1 - x0) * 3 // 10, x0 + (x1 - x0) * 9 // 10
    cols = m[:, lo:hi + 1].sum(axis=0)
    best = int(np.argmin(cols + np.abs(np.arange(len(cols)) - len(cols) * 0.6) * 0.01))
    return lo + best


def root_of(wing):
    """the root of a left wing: its pixel furthest right and down"""
    ys, xs = np.nonzero(wing)
    i = int(np.argmax(xs + 0.3 * ys))
    return int(xs[i]), int(ys[i])


def parse_motion(text):
    """'' -> ('loop', 0)"""
    v = (text or '').split()
    if not v:
        return 'loop', 0
    if len(v) != 2 or v[0] not in ('loop', 'still'):
        raise ValueError('a loop is `loop A` or `still A`')
    return v[0], int(v[1])


def parse_fit(text):
    """'' -> FIT_NONE; else (split, rx, ry, turn, wide, high)"""
    v = [int(t) for t in (text or '').split()]
    if not v:
        return FIT_NONE
    if len(v) != 6:
        raise ValueError('a fit is 6 whole numbers')
    if not (30 <= v[4] <= 160 and 30 <= v[5] <= 160):
        raise ValueError('a wing is 30 to 160 per cent wide and high')
    return tuple(v)


def left_wing(masks, fit):
    """(split, root) of a painted view: fit's numbers, or found on the still picture"""
    xs = fit[0] if fit[0] >= 0 else split_of(masks)
    if fit[1] >= 0 and fit[2] >= 0:
        return xs, (fit[1], fit[2])
    wing = masks[0] & (k.XX < xs)
    if not wing.any():
        raise SystemExit('no wing left of column %d' % xs)
    return xs, root_of(wing)


def wing_at(img, mask, root, at, turn, wide, high):
    """a wing (RGBA and mask) with its root moved to `at`, turned by `turn` degrees about it (a positive turn
    lowers the tip of a left wing) and scaled; nearest pixel"""
    a = math.radians(turn)
    qx = k.XX - at[0]
    qy = k.YY - at[1]
    rx = math.cos(a) * qx - math.sin(a) * qy               # turn back
    ry = math.sin(a) * qx + math.cos(a) * qy
    sx = np.rint(root[0] + rx * 100.0 / wide).astype(np.int32)
    sy = np.rint(root[1] + ry * 100.0 / high).astype(np.int32)
    ok = (sx >= 0) & (sx < S) & (sy >= 0) & (sy < S)
    sy, sx = np.clip(sy, 0, S - 1), np.clip(sx, 0, S - 1)
    m = mask[sy, sx] & ok
    out = np.zeros_like(img)
    out[m] = img[sy, sx][m]
    return out, m


def mirrored(a):
    """the picture mirrored about the anchor column (column 0 has no partner and stays empty)"""
    out = np.zeros_like(a)
    out[:, 1:] = a[:, 1:][:, ::-1]
    return out


def line_pixels(x0, y0, x1, y1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    return [(int(round(x0 + (x1 - x0) * i / float(n))), int(round(y0 + (y1 - y0) * i / float(n)))) for i in range(n + 1)]


def joined(img, m, ink):
    """the wing bridged to the join when it does not touch the knot (2 px wide, colour `ink`)"""
    at = JOIN
    if m[at[1] - KNOT - 1:at[1] + KNOT + 2, at[0] - KNOT - 1:at[0] + KNOT + 2].any() or not m.any():
        return img, m
    ys, xs = np.nonzero(m)
    i = int(np.argmin((xs - at[0]) ** 2 + (ys - at[1]) ** 2))
    img, m = img.copy(), m.copy()
    for x, y in line_pixels(int(xs[i]), int(ys[i]), at[0], at[1]):
        for xx, yy in ((x, y), (x, y - 1)):
            if 0 <= xx < S and 0 <= yy < S and not m[yy, xx]:
                img[yy, xx, :3] = ink
                img[yy, xx, 3] = 255
                m[yy, xx] = True
    return img, m


def knot_on(img, m, ink):
    y0, y1, x0, x1 = JOIN[1] - KNOT, JOIN[1] + KNOT + 1, JOIN[0] - KNOT, JOIN[0] + KNOT + 1
    img[y0:y1, x0:x1, :3] = ink
    img[y0:y1, x0:x1, 3] = 255
    m[y0:y1, x0:x1] = True
    return img, m


def inside(m, what):
    if m[:EDGE, :].any() or m[-EDGE:, :].any() or m[:, :EDGE].any() or m[:, -EDGE:].any():
        raise SystemExit('%s: the wing leaves the cell; make it smaller (wide, high) or turn it' % what)


def face_on(imgs, masks, fit, motion, ink, what=''):
    """the 16 frames of a face-on view: [(RGBA in raw colours, mask)]"""
    src, beat = motion
    xs, root = left_wing(masks, fit)
    at = (JOIN[0] - 1, JOIN[1])
    out = []
    for f in range(F):
        i = 0 if src == 'still' else f
        ang = fit[3] + beat * wave(f)
        img, m = wing_at(imgs[i], masks[i] & (k.XX < xs), root, at, ang, fit[4], fit[5])
        inside(m, what)
        img, m = joined(img, m, ink)
        mi = mirrored(img)
        mi[m] = img[m]
        out.append(knot_on(mi, m | mirrored(m), ink))
    return out


def side_on(imgs, masks, fit, motion, ink, west, what=''):
    """the 16 frames of a side view from the painted wing of a face-on view: [(RGBA, mask, the near wing's edge)]"""
    src, beat = motion
    xs, root = left_wing(masks, fit)
    far_at = (JOIN[0] + SIDE_FAR_AT[0], JOIN[1] + SIDE_FAR_AT[1])
    out = []
    for f in range(F):
        i = 0 if src == 'still' else f
        wing = masks[i] & (k.XX < xs)
        dark = imgs[i].copy()
        dark[..., :3] = (dark[..., :3].astype(np.float64) * SIDE_FAR_SHADE).astype(np.uint8)
        fi, fm_ = wing_at(dark, wing, root, far_at, fit[3] + SIDE_TURN['far'] + beat * wave(f, SIDE_LAG),
                          fit[4] * SIDE_FAR, fit[5])
        fi, fm_ = joined(fi, fm_, ink)
        ni, nm = wing_at(imgs[i], wing, root, JOIN, fit[3] + SIDE_TURN['near'] + beat * wave(f),
                         fit[4] * SIDE_NEAR, fit[5])
        ni, nm = joined(ni, nm, ink)
        img, m = fi.copy(), fm_ | nm
        img[nm] = ni[nm]
        cut = open_edge(nm) & fm_                          # the near wing keeps its edge where it lies on the far one
        img, m = knot_on(img, m, ink)
        if west:
            img, m, cut = mirrored(img), mirrored(m), mirrored(cut)
        inside(m, what)
        out.append((img, m, cut))
    return out


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
            ln = 10 + int(h1 * 6)
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
def rim_of(row):
    """'' -> None; `rrggbb`: the light edge inside the outline (a dark wing on dark ground)"""
    text = (row.get('rim') or '').strip()
    if not text:
        return None
    if len(text) != 6:
        raise ValueError('a rim is rrggbb')
    return np.asarray([int(text[i:i + 2], 16) for i in (0, 2, 4)], np.uint8)


def clean_row(sp, raw, row=None):
    """raw: {view: 16 raw RGBA frames} -> {view: 16 cleaned RGBA frames} (south, north, east, west) of one row"""
    row = row or {}
    ink = np.asarray(sp.outline, np.uint8)
    glow = np.asarray(sp.glow, np.uint8)
    rim = rim_of(row)
    views = {}
    for v in VIEWS:
        masks = [solid_of(img) for img in raw[v]]
        fit_, motion = parse_fit(row.get('f' + v[0])), parse_motion(row.get('m' + v[0]))
        what = '%d %s' % (sp.wings, v)
        views[v] = [(img, m, None) for img, m in face_on(raw[v], masks, fit_, motion, ink, what)]
        side = 'east' if v == 'south' else 'west'
        views[side] = side_on(raw[v], masks, fit_, motion, ink, side == 'west', '%d %s' % (sp.wings, side))
    pal0 = palette_of([img for v in VIEWS for img, _, _ in views[v]], [m for v in VIEWS for _, m, _ in views[v]])
    pal = tinted(pal0, parse_tint(row.get('tint')))
    out = {}
    for v in fam.SHEET_VIEWS:
        plain = []
        for img, m, cut in views[v]:
            res = np.zeros((S, S, 4), np.uint8)
            res[..., :3][m] = pal[palette_index(img[..., :3][m], pal0)]
            res[..., 3][m] = 255
            edge = open_edge(m)
            if rim is not None:                            # a light line inside the outline, brighter toward the light
                lit = m & ~edge & (k.nb(edge, 0, -1) | k.nb(edge, -1, 0))
                dim = m & ~edge & ~lit & (k.nb(edge, 0, 1) | k.nb(edge, 1, 0))
                res[..., :3][lit] = rim
                res[..., :3][dim] = (rim.astype(np.float64) * 0.62).astype(np.uint8)
            if cut is not None:
                res[..., :3][cut] = ink
            res[..., :3][edge] = ink
            plain.append(res)
        lights = extras(sp, v, [img[..., 3] == 255 for img in plain])
        out[v] = [light_up(img.copy(), lights[f], glow) for f, img in enumerate(plain)]
    return out


# ------------------------------------------------------------------------------------------------ the fit (O620)
# what the layout promises, measured on the pictures a row gives (any source): gen_drawn_wings_test.py and `table`
GROUND_DARK = (56, 60, 68)    # the preview ground
GROUND_LIGHT = (196, 190, 170)
NEAR = 60                      # the distance in RGB under which two colours are one
PAIR_GAP = 0.15               # the most of a face-on view that may be painted in colours the other one lacks
CONTRAST = 1.5                # the least contrast of a wing on dark ground and of its outline on light ground
LOPSIDED = 0.02               # the share of a face-on pair without a mirror partner (the solid heart of a light)
SIDE_RISE = 8                 # px a side wing rises over the join at least
SIDE_HANG = 0.12              # the most of a side wing that may lie under the anchor row


def _lin(c):
    c = np.asarray(c, np.float64) / 255.0
    c = np.where(c <= 0.03928, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722


def contrast(a, b):
    """the contrast ratio of two colours (1 to 21)"""
    la, lb = float(_lin(a)), float(_lin(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def wing_of(img):
    """the solid pixels of a finished picture without its lights (a light's solid heart is a crumb)"""
    m = img[..., 3] == 255
    lab, sizes = pieces(m)
    return m & np.asarray([n >= MIN_PIECE for n in sizes])[lab]


def colour_shares(frames):
    """{colour: share} of the wing pixels inside the outline, over a loop"""
    count = {}
    for img in frames:
        m = wing_of(img)
        m &= ~open_edge(m)
        cols, n = np.unique(img[..., :3][m], axis=0, return_counts=True)
        for c, v in zip(cols.tolist(), n.tolist()):
            count[tuple(c)] = count.get(tuple(c), 0) + v
    total = float(sum(count.values())) or 1.0
    return {c: v / total for c, v in count.items()}


def strangers(a, b, known=0.004, near=NEAR):
    """the share of loop a painted in colours that loop b does not know: no colour of b (one that fills `known`
    of it or more) lies within `near` of it"""
    sa, sb = colour_shares(a), colour_shares(b)
    have = np.asarray([c for c, v in sb.items() if v >= known], np.float64).reshape(-1, 3)
    if not len(have):
        return 1.0
    return sum(v for c, v in sa.items() if np.sqrt(((have - np.asarray(c, np.float64)) ** 2).sum(axis=1)).min() > near)


def measure(frames):
    """frames: {direction: [RGBA whole pictures]} -> the numbers of the fit:
    centre[d]   the largest offset in a loop of the wings' middle from the anchor column, px. Face on: the middle
                of the solid box. From the side: the join, where the wings stand on the body (the nearest solid
                pixel to JOIN).
    box[d]      the offset of the middle of the solid box (the same as centre face on)
    join[d]     the largest distance in a loop from JOIN to the nearest solid pixel, px
    one[d]      the smallest share in a loop of the solid pixels that hang together with the join
    lopsided[d] the largest share in a loop of solid pixels without a mirror partner (face on)
    top[d], hang[d]   px the wing rises over the join (the least of a loop); the share of it under the anchor row
    pair        the share of the north view painted in colours the south view does not know, or the other way round
    edge_dark[d], line_light[d]   contrast on dark ground of the pixels just inside the outline (their mean
                colour), of the outline on light ground"""
    out = {name: {} for name in ('centre', 'box', 'join', 'one', 'lopsided', 'top', 'hang', 'edge_dark', 'line_light')}
    for d, seq in frames.items():
        c, b, j, one, lop, top, hang, ed, ll = [], [], [], [], [], [], [], [], []
        for img in seq:
            m = wing_of(img)
            ys, xs = np.nonzero(m)
            if not len(xs):
                continue
            mid = (int(xs.min()) + int(xs.max())) / 2.0 - JOIN[0]
            dist = np.hypot(xs - JOIN[0], ys - JOIN[1])
            i = int(np.argmin(dist))
            b.append(mid)
            c.append(mid if d in VIEWS else float(xs[i] - JOIN[0]))
            j.append(float(dist[i]))
            lab, sizes = pieces(m)
            one.append(sizes[lab[ys[i], xs[i]]] / float(len(xs)))
            lop.append(float((m ^ mirrored(m))[:, 1:].sum()) / len(xs))
            top.append(JOIN[1] - int(ys.min()))
            hang.append(float((ys > k.ANCHOR[1]).sum()) / len(xs))
            edge = open_edge(m)
            ring = m & ~edge & (k.nb(edge, 0, -1) | k.nb(edge, -1, 0) | k.nb(edge, 0, 1) | k.nb(edge, 1, 0))
            if ring.any():                                 # the line inside the outline is what parts wing and ground
                ed.append(contrast(img[..., :3][ring].mean(axis=0), GROUND_DARK))
            ll.append(contrast(img[..., :3][edge].mean(axis=0), GROUND_LIGHT))
        out['centre'][d] = max(c, key=abs)
        out['box'][d] = max(b, key=abs)
        out['join'][d] = max(j)
        out['one'][d] = min(one)
        out['lopsided'][d] = max(lop)
        out['top'][d] = min(top)
        out['hang'][d] = max(hang)
        out['edge_dark'][d] = min(ed) if ed else 0.0
        out['line_light'][d] = min(ll)
    if 'north' in frames and 'south' in frames:
        out['pair'] = max(strangers(frames['north'], frames['south']), strangers(frames['south'], frames['north']))
    return out


def fit_problems(frames):
    """what a painted row's pictures do not hold of the layout"""
    n = measure(frames)
    bad = []
    for d in frames:
        if abs(n['centre'][d]) > 1.0:
            bad.append('%s: the wings stand %.1f px beside the torso' % (d, n['centre'][d]))
        if n['join'][d] > 1.0:
            bad.append('%s: a gap of %.1f px between the wings and the join' % (d, n['join'][d]))
        if n['one'][d] < 0.9:
            bad.append('%s: the pair comes apart (%.0f%% hangs together)' % (d, 100 * n['one'][d]))
        if d in VIEWS and n['lopsided'][d] > LOPSIDED:
            bad.append('%s: the pair is not the same left and right' % d)
        if d not in VIEWS and (n['top'][d] < SIDE_RISE or n['hang'][d] > SIDE_HANG):
            bad.append('%s: the side wing hangs (rises %d px, %.0f%% under the torso)' % (d, n['top'][d], 100 * n['hang'][d]))
        if n['line_light'][d] < CONTRAST:
            bad.append('%s: the outline is lost on light ground (%.1f)' % (d, n['line_light'][d]))
    if 'north' in frames:
        if n['edge_dark']['north'] < CONTRAST:
            bad.append('north: the wing is lost on dark ground (%.1f)' % n['edge_dark']['north'])
        if n.get('pair', 0.0) > PAIR_GAP:
            bad.append('north and south do not share their colours (%.2f)' % n['pair'])
    return bad


def on_body(centre, body, lift=6):
    """px the middle of the wings lies beside the torso of a body (fam.body_rel) as the engine draws the two: the
    wings at the creature's place moved by fam.wing_shift, the body `lift` px up and left of it"""
    shift = fam.wing_shift(body, lift)
    return (fam.anchor_rel()[0] + shift[0] + centre) - (body[0] - lift)


def row_frames(sp):
    """{direction: [whole pictures]} of a row as gen_drawn_wings_families draws it now"""
    return {d: [k.merge(*fam.render_frame(sp, d, f)) for f in range(F)] for d in k.DIRS}


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
            bad = fam.bar_problems(sp) + fit_problems(row_frames(sp))
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


def measure_sheets(sheets_dir, only=None, log=print):
    """print the numbers of the fit for the sheets of a folder (any sheet, the sha256 is not asked)"""
    keep, check = fam.SRC_DIR, fam.SRC_CHECK
    fam.use_src(sheets_dir, check=False)
    rows = fam.sheet_rows()
    try:
        log('row  key               centre N    E    S    W | box E    W | join N    E    S    W | one N    E    S    W | lop N    S | top E  W | hang E    W | pair | dark N | light N')
        for sp in fam.load():
            if sp.wings not in rows or (only and sp.wings not in only):
                continue
            n = measure(row_frames(sp))
            log('%3d  %-16s %+8.1f %+4.1f %+4.1f %+4.1f | %+5.1f %+4.1f | %6.1f %4.1f %4.1f %4.1f | %5.2f %4.2f %4.2f %4.2f | %5.2f %4.2f | %5d %2d | %6.2f %4.2f | %4.2f | %6.1f | %7.1f' % (
                (sp.wings, sp.key) + tuple(n['centre'][d] for d in k.DIRS) + (n['box']['east'], n['box']['west'])
                + tuple(n['join'][d] for d in k.DIRS) + tuple(n['one'][d] for d in k.DIRS)
                + (n['lopsided']['north'], n['lopsided']['south'], n['top']['east'], n['top']['west'],
                   n['hang']['east'], n['hang']['west'], n['pair'], n['edge_dark']['north'], n['line_light']['north'])))
    finally:
        fam.use_src(keep, check)
    return 0


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
            for what in fam.bar_problems(sp) + fit_problems(row_frames(sp)):
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
    if len(argv) >= 2 and argv[0] == 'measure':
        return measure_sheets(argv[1], only)
    if len(argv) >= 2 and argv[0] == 'table':
        return 1 if table(argv[1], '--check' in argv) else 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
