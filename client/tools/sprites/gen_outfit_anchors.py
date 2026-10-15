#!/usr/bin/env python3
"""Where each outfit stands, for the character select's big preview (client/MANIFEST.md "Character select").

usage: python3 -I client/tools/sprites/gen_outfit_anchors.py Tibia.dat Tibia.spr [--out PATH] [--check]

The character select draws a character 3 or 4 times its size on a stone dais. Our sprites are oblique: the body leans
up and left with its height, and its lowest pixel is often a cape tip, a weapon or a trailing robe, not the feet; some
looks float and have no feet at all. So the anchor is what the eye reads (owner, 2026-10-13: the first anchors, the
lowest row and the median column of the lowest quarter, left looks off-centre, the flying ones most). This tool
reads the pair and writes, per creature thing (outfits, wings and auras share that category), from the first
south-facing frame (base layer with every addon pattern, phase 0), in the coordinates the client draws it in: pixels
relative to the top left of the creature's own tile, displacement applied (the client draws a thing's bottom right
32x32 cell on its tile, the other cells up and left, all moved up and left by the displacement).

  [id] = {cx, ground, top, left, right, w, h, float, reach}
    cx       the horizontal anchor (--centre; default body): the body's visual centre: the alpha-weighted centroid of its solid pixels, what it holds (a blade, a
             staff, a torch, a chain up to four pixels wide) left out by an opening of the mask, and of what is left
             only the biggest connected part (the leaves at a staff's end fall away)
    ground   the row the body stands on: where the lowest GROUND_MASS of its solid mass begins (the feet and shins),
             so a cape tip or a weapon under the feet does not count; a floating look's is found the same way (the
             character select then lifts it: CharSelectCore.HOVER)
    top, left, right  the visible bounds, everything counted (to keep the whole picture inside the screen)
    w, h     the thing's size in tiles (the client centres a big aura by (w-1)*16, (h-1)*16)
    float    1 for a look drawn floating (a robe or a wraith tail, no feet: FLOATING, chosen by eye), else 0
    reach    how far the solid body reaches left or right of cx (3% of its columns trimmed on each side): the
             character select picks a bigger dais for a wide body

Output (default): client/overlay/modules/client_chaos_charselect/outfit_anchors.lua, a Lua table the module loads
(`CharSelectAnchors`; charselect_core.lua does the placement). Things with no visible pixel are left out; the module
falls back to the size and displacement for them (and for looks of a newer pair). Deterministic: the same pair
writes the same file; --check exits 1 when the file differs from what the pair gives. Regenerate it with every new
pair (the dat md5 is written in the file).
"""
import argparse
import hashlib
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from datspr import Dat, Spr, sprite_index  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_charselect', 'outfit_anchors.lua')
ALPHA = 64          # a pixel counts as visible from this alpha on
GROUND_MASS = 0.12  # the ground row: where the lowest 12% of the solid mass begins
TRIM = 0.03         # reach: columns trimmed on each side
# Looks drawn floating, chosen by eye on the pair (a robe or a wraith tail, no pair of feet): the Lich's chained
# black robe, the robed wizard, the Bone Lord wraiths and the Necromancer ascension's robes. Winged characters float
# by the engine's own lift (GameWingOffset) and need no entry.
# The horizontal anchor. Compared live on the ten test characters and the class looks (owner, 2026-10-13: "move the
# characters left"): the full figure's box and the blend move most looks right (weapons and staffs held out to the
# left and right), the body centroid with CharSelectCore.NUDGE_X = -2 read best. --centre writes the others.
CENTRES = ('body', 'bbox', 'blend')
CENTRE = 'body'
FLOATING = {2059, 2077, 2167, 2168, 2183, 2184}


def south_alpha(t, spr):
    """alpha of the first south frame with every addon (pattern y): characters wear their class looks with both
    addons, and an addon (a cape, a staff) can reach below or beside the body"""
    x = 2 if t.px >= 4 else 0
    W, H = t.w * 32, t.h * 32
    alpha = np.zeros((H, W), np.uint8)
    for yy in range(max(1, t.py)):
        for hh in range(t.h):
            for ww in range(t.w):
                a = spr.sprite(t.sprites[sprite_index(t, x, yy, 0, 0, 0, ww, hh)])
                if a is not None:
                    oy, ox = (t.h - 1 - hh) * 32, (t.w - 1 - ww) * 32
                    np.maximum(alpha[oy:oy + 32, ox:ox + 32], a[..., 3], out=alpha[oy:oy + 32, ox:ox + 32])
    return alpha


def _erode(m):
    out = m.copy()
    H, W = m.shape
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            sh = np.zeros_like(m)
            sh[max(0, -dy):H - max(0, dy), max(0, -dx):W - max(0, dx)] = \
                m[max(0, dy):H - max(0, -dy), max(0, dx):W - max(0, -dx)]
            out &= sh
    return out


def solid(mask, r=1):
    """the mask without its thin parts: an opening with a square of side 2r + 1 (r = 1: lines one or two pixels wide,
    r = 2: also a staff, a torch or a spear up to four wide); the mask itself when nothing is left"""
    core = mask
    for _ in range(r):
        core = _erode(core)
    for _ in range(r):
        core = ~_erode(~core)
    core &= mask
    return core if core.any() else mask


def largest_part(mask):
    """the biggest 8-connected part of a mask (what the body holds, cut off by the opening, falls away)"""
    H, W = mask.shape
    seen = np.zeros_like(mask)
    best = None
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        part, stack = [], [(y0, x0)]
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            part.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < H and 0 <= xx < W and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
        if best is None or len(part) > len(best):
            best = part
    out = np.zeros_like(mask)
    ys, xs = zip(*best)
    out[list(ys), list(xs)] = True
    return out


def measure(alpha, ox=0, oy=0, floating=False, centre='body'):
    """(cx, ground, top, left, right, float, reach) of one frame's alpha (canvas pixel + (ox, oy) = tile pixel), or
    None when nothing is visible"""
    mask = alpha >= ALPHA
    if not mask.any():
        return None
    ys, xs = np.nonzero(mask)
    # the centre and the reach: the body without what it holds (a staff, a torch, a spear: r = 2; the leaves or the
    # flame at a staff's end are then cut off from the body and fall away with the smaller parts)
    body = largest_part(solid(mask, 2))
    cy, cxs = np.nonzero(body)
    w = alpha[cy, cxs].astype(np.float64)
    cx = float((cxs + 0.5) @ w / w.sum())
    # the horizontal anchor (CENTRES): the body's centroid; the box of the whole figure (body, weapons, shields,
    # addons; a body thing has no wings or aura); or halfway between the two
    box = (xs.min() + xs.max() + 1) / 2
    body_cx, cx = cx, {'body': cx, 'bbox': box, 'blend': (cx + box) / 2}[centre]
    # the ground: legs are thin, so only lines one or two pixels wide are left out (r = 1), and only the columns the
    # body spans count (a staff held out beside it does not)
    core = solid(mask, 1)
    span = np.zeros_like(core)
    span[:, cxs.min():cxs.max() + 1] = True
    core = core & span if (core & span).any() else core
    rows = core.sum(axis=1).astype(np.float64)
    from_bottom = np.cumsum(rows[::-1]) / rows.sum()
    ground = len(rows) - int(np.searchsorted(from_bottom, GROUND_MASS))
    lo, hi = np.quantile(cxs, TRIM), np.quantile(cxs + 1, 1 - TRIM)
    reach = max(body_cx - lo, hi - body_cx)   # the body's own spread, whatever the anchor
    return (int(np.floor(cx + ox + 0.5)), ground + oy, int(ys.min()) + oy, int(xs.min()) + ox,
            int(xs.max()) + 1 + ox, 1 if floating else 0, int(np.ceil(reach)))


def anchor_of(t, spr, lid=0, centre='body'):
    """measure() of a creature thing's first south frame, in its tile pixels"""
    W, H = t.w * 32, t.h * 32
    dx, dy = t.flags.get('displacement', (0, 0)) if isinstance(t.flags.get('displacement'), tuple) else (0, 0)
    # the dat stores two u16: a negative displacement reads as 65536 - n
    dx, dy = (v - 65536 if v > 32767 else v for v in (dx, dy))
    return measure(south_alpha(t, spr), -(W - 32) - dx, -(H - 32) - dy, lid in FLOATING, centre)


def build(dat_path, spr_path, centre=CENTRE):
    dat = Dat(dat_path)
    spr = Spr(spr_path)
    md5 = hashlib.md5(open(dat_path, 'rb').read()).hexdigest()
    rows = []
    for i, t in enumerate(dat.outfits, 1):
        if not t.sprites:
            continue
        a = anchor_of(t, spr, i, centre)
        if a is None:
            continue
        rows.append('[%d]={%d,%d,%d,%d,%d,%d,%d,%d,%d}' % ((i,) + a[:5] + (t.w, t.h) + a[5:]))
    lines = ['-- Generated by client/tools/sprites/gen_outfit_anchors.py from the pair with dat md5 %s.' % md5,
             '-- Do not edit: regenerate with the tool for every new pair. Per creature thing (outfits, wings, auras):',
             '-- [id] = {centre x, ground row, top, left, right, width, height, floating, reach}: pixels at 1x relative to',
             "-- the top left of the creature's own tile, displacement applied (first south frame); width and height in",
             '-- tiles; floating 1 or 0; reach: how far the solid body reaches either side of its centre.',
             'CharSelectAnchors = {', '  dat = "%s",' % md5]
    for k in range(0, len(rows), 6):
        lines.append('  ' + ','.join(rows[k:k + 6]) + ',')
    lines.append('}')
    lines.append('return CharSelectAnchors')
    return '\n'.join(lines) + '\n', len(rows)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('dat')
    ap.add_argument('spr')
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--centre', choices=CENTRES, default=CENTRE, help='the horizontal anchor (default %(default)s)')
    a = ap.parse_args(argv)
    text, n = build(a.dat, a.spr, a.centre)
    if a.check:
        have = open(a.out, encoding='utf-8').read() if os.path.exists(a.out) else ''
        if have != text:
            print('%s is not what the pair gives: run %s' % (a.out, os.path.basename(__file__)))
            return 1
        print('outfit anchors up to date (%d things)' % n)
        return 0
    with open(a.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote %s (%d things)' % (os.path.relpath(a.out, REPO), n))
    return 0


if __name__ == '__main__':
    sys.exit(main())
