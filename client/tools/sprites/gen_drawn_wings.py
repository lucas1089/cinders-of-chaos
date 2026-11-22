#!/usr/bin/env python3
"""Code-drawn wings (O581): back cosmetics drawn by this script, no art file read. A prototype for the owner's pick.

usage: python3 -I client/tools/sprites/gen_drawn_wings.py build OUT_DIR [--only KEY,...]
       python3 -I client/tools/sprites/gen_drawn_wings.py preview OUT_DIR [--dat Tibia.dat --spr Tibia.spr] [--look N]

Each design is a small model in 3D round the body (x right, y up, z towards the viewer; the character faces +z). A
direction turns the model about the vertical axis and projects it on a 3 x 3 tile canvas (96 x 96 px), 16 frames,
rows north, east, south, west. Motion comes from periodic curves of the frame phase only, so frame 15 runs into frame 0.

The canvas and the body. The engine puts the bottom right tile of a 3 x 3 look on the creature's tile, draws the wings
at the creature's place and the body 6 px up and left of it (client/MANIFEST.md "Wings centred on the body"). With
displacement 0 for the wings the torso of a class look lies at canvas y 63.5 (median of the class looks, measured on
pair 71; the stock look 128: 66). ANCHOR is that point, x in the middle of the canvas. Since O714 the art does not lean (LEAN, LEAN_ART are 0): a pair
is the same on both sides of the anchor column (the left half drawn and its mirror picture, Canvas.pair) and west is the
east frame mirrored, so the engine's anchor on the torso (base patch 0204) puts the pair on the body, not beside it.
The x needs a row in wing_centres.lua that says ANCHOR's x (base patch 0193 then puts it on any body's torso);
gen_wing_centres.py would measure the art's mass instead, so pair 73 must write the row from `anchor_row()` here.
Until a pair has these looks nothing reads this.

Drawing rules (the kit, top of the file):
  whole pixels only: alpha is 0 or 255, plus GLOW_ALPHA for the arms of a spark, the last dots of a trail and a
  haze (smoke, mist, a glow round a cloud: Canvas.haze, O587);
  a ramp of 5 shades per material and one dark outline colour per design; light from the top left;
  every piece gets a 1 px ring, then every opaque pixel that touches transparency becomes the outline colour;
  two layers a frame: `back` (behind the body) and `front`; a piece goes by its depth after the turn.

build writes per design KEY: KEY_sheet.png (back and front merged; 16 columns x 4 rows of 96 px), KEY_back.png and
KEY_front.png (the same grid, one layer). Deterministic: the same bytes every run.
preview writes MP4s at 4x (the four directions side by side on a plain body; with --dat/--spr a class look of the pair,
tinted, else a drawn silhouette), all_designs.mp4 and scale_1x.png (game size). Previews are never committed.

Designs (our own, dark fantasy): ember_pinions, ossuary_wings, void_orbit, bladefan, rimeshard, grave_lanterns.

The 121 wings looks of the pair (O583) are rows of drawn_wings/designs.csv, drawn by gen_drawn_wings_families.py
with this kit. Their commands, handed over from here:
  table [--check]              the table rules, drawn_wings/designs.sums, client_chaos_wingfit/wing_anchors.lua
  sheets OUT_DIR               a contact sheet a family, 1x and 3x
  compare OUT_DIR DAT SPR      an MP4 a family: old art of the pair left, the drawn wing right, four directions
  fit OUT_DIR DAT SPR LOOKS [WINGS]   one wing on several player looks (LOOK, LOOK+ADDONS, LOOK:MOUNT; rows of
                               player_looks.csv only, O587): engine anchor left, old table right
  measure DAT SPR [--write]    read the strips, zone colours and beat of the old wings into designs.csv (O587, O590)
  score DAT SPR [OUT.tsv]      likeness of every row to the old art: shape, colour, layout, motion, 0 is the same
  apply DAT SPR OUT_DIR [--new] [--keep-painted]   the pair with the drawn wings in the same ids (pair 73 step); --new also redraws the six
                               looks 3555-3560 in place (a pair that holds them already: pair 78, O714)
                               --keep-painted: the ten painted rows stay as the input pair has them (no --src needed, O714b)
  live DAT SPR [--new] [--keep-painted [--base DAT SPR]]   a built pair holds them (kept rows: equal to --base, else skipped)
  new-table [--check]          the six wings of this file as wings looks 3555-3560 of pair 78 (O581 phase 2): drawn_wings/new_looks.csv, .sums,
                               wing_anchors.lua and the server's ids file (gen_drawn_wings_new.py)
  build-new DAT SPR OUT_DIR    pair 77 (and no other) -> pair 78: the six looks appended, nothing else changes
  live-new DAT SPR             a built pair 78 holds them
  --src DIR                    with sheets, compare, fit, score, apply, live: ten rows come from the painted sheets of
                               DIR (O594, gen_pixellab_wings.py, drawn_wings/pixellab_rows.csv); without it every row
                               is drawn by code. CHAOS_WINGS_SRC names the folder for the test
"""
import argparse
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

SIZE = 96
FRAMES = 16
DIRS = ('north', 'east', 'south', 'west')
ANCHOR = (48, 64)            # canvas px of the body's torso centre (see the docstring)
GLOW_ALPHA = 144             # the one partial alpha: spark arms, trail ends
TAU = 2 * math.pi
DIR_ANGLE = {'south': 0.0, 'east': 90.0, 'north': 180.0, 'west': 270.0}
# O714: a pair is as wide left as right about the anchor column in the south and north views (no yaw there) and the
# west view is the east view mirrored (yaw -14 and +14 about the side). The owner saw a wing mirrored or on the wrong
# side in nearly every wing of the store preview (client/MANIFEST.md "Wings that stand the same on both sides (O714)"):
# a lean to the left and a yaw of -14 face on put the mass of a pair 10 px left of the anchor from behind, and the east
# view twice as far left as the west view was right.
VIEW_YAW = {'south': 0.0, 'north': 0.0, 'east': -14.0, 'west': 14.0}
LEAN = 0.0                   # px left per px of height: none, the pair stands on the torso column (-0.55 before O714)
LEAN_ART = 0.0               # the lean of the art itself above and below its pivot height (-0.2 before O714)
DEPTH = 0.42                 # px down per px towards the viewer
LIGHT2 = (-0.6, -0.8)        # screen light direction (from the top left)
LIGHT3 = (-0.52, -0.62, 0.59)

YY, XX = np.mgrid[0:SIZE, 0:SIZE]
PX = XX + 0.5
PY = YY + 0.5


# ------------------------------------------------------------------------------------------------ maths
def rad(deg):
    return deg * math.pi / 180.0


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def ease(v):
    """smoothstep on 0..1"""
    v = clamp(v, 0.0, 1.0)
    return v * v * (3 - 2 * v)


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vmul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def vnorm(a):
    n = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def project(p, d, pivot=0.0, depth=DEPTH):
    """model point -> (screen x, screen y, depth); depth > 0 is nearer than the body. `pivot` is the height at
    which the art sits on the leaning body: it leans with the body up to there and by LEAN_ART about it. `depth`:
    px down per px towards the viewer (a higher camera shows more of what lies towards and away from it)"""
    a = rad(DIR_ANGLE[d] + VIEW_YAW[d])
    xr = p[0] * math.cos(a) + p[2] * math.sin(a)
    zr = -p[0] * math.sin(a) + p[2] * math.cos(a)
    return (ANCHOR[0] + xr + LEAN * pivot + LEAN_ART * (p[1] - pivot), ANCHOR[1] - p[1] + depth * zr, zr)


# ------------------------------------------------------------------------------------------------ the kit: masks
def nb(mask, dx, dy):
    """the mask's value at (x + dx, y + dy); outside the canvas False"""
    out = np.zeros_like(mask)
    h, w = mask.shape
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    out[ys0:ys1, xs0:xs1] = mask[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
    return out


def mirrored(a):
    """the picture mirrored about the anchor column (column c goes to 96 - c; column 0 has no partner and stays empty).
    Wings are drawn about this column, the engine puts it on the body's torso (base patch 0204)"""
    out = np.zeros_like(a)
    out[:, 1:] = a[:, 1:][:, ::-1]
    return out


def dilate4(mask):
    return mask | nb(mask, 1, 0) | nb(mask, -1, 0) | nb(mask, 0, 1) | nb(mask, 0, -1)


def poly_mask(pts):
    """pixels whose centre lies in the polygon (even-odd)"""
    inside = np.zeros((SIZE, SIZE), bool)
    n = len(pts)
    if n < 3:
        return inside
    bx0 = max(0, int(math.floor(min(p[0] for p in pts))) - 1)
    bx1 = min(SIZE, int(math.ceil(max(p[0] for p in pts))) + 1)
    by0 = max(0, int(math.floor(min(p[1] for p in pts))) - 1)
    by1 = min(SIZE, int(math.ceil(max(p[1] for p in pts))) + 1)
    if bx0 >= bx1 or by0 >= by1:
        return inside
    px = PX[by0:by1, bx0:bx1]
    py = PY[by0:by1, bx0:bx1]
    sub = np.zeros(px.shape, bool)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        if y0 == y1:
            continue
        cross = (y0 <= py) != (y1 <= py)
        xint = x0 + (py - y0) * (x1 - x0) / (y1 - y0)
        sub ^= cross & (px < xint)
    inside[by0:by1, bx0:bx1] = sub
    return inside


def disc_mask(cx, cy, r):
    return (PX - cx) ** 2 + (PY - cy) ** 2 <= r * r


def capsule_mask(p0, p1, hw0, hw1=None):
    """a thick line with round ends, the width may taper"""
    hw1 = hw0 if hw1 is None else hw1
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    n = math.hypot(dx, dy)
    m = disc_mask(p0[0], p0[1], hw0) | disc_mask(p1[0], p1[1], hw1)
    if n > 1e-6:
        nx, ny = -dy / n, dx / n
        m |= poly_mask([(p0[0] + nx * hw0, p0[1] + ny * hw0), (p1[0] + nx * hw1, p1[1] + ny * hw1),
                        (p1[0] - nx * hw1, p1[1] - ny * hw1), (p0[0] - nx * hw0, p0[1] - ny * hw0)])
    return m


def edge_shade(mask, hi=3, mid=2, lo=1):
    """shade a flat piece by its edges: lit where the top or left is open, dark where the bottom or right is"""
    lit = mask & ~(nb(mask, 0, -1) & nb(mask, -1, 0))
    dark = mask & ~(nb(mask, 0, 1) & nb(mask, 1, 0))
    idx = np.full(mask.shape, mid, np.int8)
    idx[dark] = lo
    idx[lit] = hi
    idx[lit & dark] = mid
    return idx


def sphere_shade(cx, cy, r, levels=(0.05, 0.38, 0.68, 0.9)):
    """ramp index of a ball lit from the top left"""
    nx = (PX - cx) / r
    ny = (PY - cy) / r
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    lam = nx * LIGHT3[0] + ny * LIGHT3[1] + nz * LIGHT3[2]
    idx = np.zeros((SIZE, SIZE), np.int8)
    for lv in levels:
        idx += (lam > lv)
    return idx


FEATHER = ((0.0, 0.28), (0.14, 0.72), (0.34, 0.96), (0.6, 1.0), (0.82, 0.86), (0.94, 0.56), (1.0, 0.0))
BLADE = ((0.0, 0.42), (0.1, 0.42), (0.16, 1.0), (0.3, 0.92), (0.78, 0.6), (1.0, 0.0))
SHARD = ((0.0, 0.3), (0.22, 1.0), (0.68, 0.82), (1.0, 0.0))


def leaf(b, t, hw, knots, bend=0.0):
    """a long piece from b to t (screen px), half width hw, the outline from `knots` (place along, share of hw);
    returns the mask and per pixel the place along (0..1), the signed place across (-1..1) and the lit side"""
    ax, ay = t[0] - b[0], t[1] - b[1]
    ln = math.hypot(ax, ay) or 1e-6
    ux, uy = ax / ln, ay / ln
    nx, ny = -uy, ux
    left, right = [], []
    for k, w in knots:
        cx = b[0] + ax * k + nx * bend * k * k
        cy = b[1] + ay * k + ny * bend * k * k
        left.append((cx + nx * w * hw, cy + ny * w * hw))
        right.append((cx - nx * w * hw, cy - ny * w * hw))
    mask = poly_mask(left + right[::-1])
    tt = ((PX - b[0]) * ux + (PY - b[1]) * uy) / ln
    ss = ((PX - b[0]) * nx + (PY - b[1]) * ny - bend * tt * tt) / max(hw, 1e-6)
    side = nx * LIGHT2[0] + ny * LIGHT2[1]
    lit = (ss * side) > 0
    return mask, tt, ss, lit


# ------------------------------------------------------------------------------------------------ the kit: canvas
class Canvas:
    """one layer of one frame: opaque pixels, then sparks"""

    def __init__(self, outline):
        self.rgb = np.zeros((SIZE, SIZE, 3), np.uint8)
        self.op = np.zeros((SIZE, SIZE), bool)
        self.outline = outline
        self.sparks = []
        self.hazes = []

    def piece(self, mask, idx, ramp, line=None, ring=True):
        if not mask.any():
            return
        if ring:
            r = dilate4(mask) & ~mask
            self.rgb[r] = line or self.outline
            self.op |= r
        table = np.asarray(ramp, np.uint8)
        self.rgb[mask] = table[np.clip(idx[mask], 0, len(ramp) - 1)]
        self.op |= mask

    def spark(self, x, y, colour, size=1):
        """size 0: one glow pixel; 1: a bright core with four glow arms; 2: the arms two long"""
        self.sparks.append((int(math.floor(x)), int(math.floor(y)), colour, size))

    def haze(self, mask, colour):
        """a soft field at the glow level (smoke, mist, light): only where the layer is clear"""
        self.hazes.append((mask, colour))

    def mirror_in(self):
        """add the mirror picture of everything drawn so far, about the anchor column: opaque pixels, sparks and
        hazes. The first drawing keeps a pixel both own (O714: a pair is one wing and its mirror picture)"""
        rgb, op = mirrored(self.rgb), mirrored(self.op)
        new = op & ~self.op
        self.rgb[new] = rgb[new]
        self.op |= op
        # the outline ring of a piece may reach column 1 (a piece stays inside columns 2..93): its partner would be on
        # the cell border, so the two columns go together and finish() draws the edge in the outline colour
        self.op[:, :2] = False
        self.op[:, SIZE - 1:] = False
        self.rgb[~self.op] = 0
        self.sparks = self.sparks + [(2 * (SIZE // 2) - x, y, c, s) for x, y, c, s in self.sparks]
        self.hazes = self.hazes + [(mirrored(m), c) for m, c in self.hazes]

    def keep_left(self):
        """drop what lies right of the anchor column"""
        half = SIZE // 2
        self.op[:, half + 1:] = False
        self.rgb[:, half + 1:] = 0
        self.sparks = [s for s in self.sparks if s[0] <= half]
        self.hazes = [(m & (XX <= half), c) for m, c in self.hazes]

    def pair(self):
        """what the left half drew and its mirror picture: a pair that is the same on both sides"""
        self.keep_left()
        self.mirror_in()

    def finish(self):
        op = self.op
        edge = op & ~(nb(op, 1, 0) & nb(op, -1, 0) & nb(op, 0, 1) & nb(op, 0, -1))
        # the canvas border is not transparency, but art should not touch it anyway
        self.rgb[edge] = self.outline
        alpha = np.where(op, 255, 0).astype(np.uint8)
        rgb = self.rgb.copy()
        inner = np.zeros((SIZE, SIZE), bool)
        inner[2:SIZE - 2, 2:SIZE - 2] = True
        for mask, colour in self.hazes:
            sel = mask & inner & (alpha == 0)
            rgb[sel] = colour
            alpha[sel] = GLOW_ALPHA
        for x, y, colour, size in self.sparks:
            if not (2 <= x < SIZE - 2 and 2 <= y < SIZE - 2):
                continue
            if size == 0:
                if alpha[y, x] == 0:
                    rgb[y, x] = colour
                    alpha[y, x] = GLOW_ALPHA
                continue
            if alpha[y, x] == 255 and edge[y, x]:
                continue                        # never repaint the outline
            rgb[y, x] = colour
            alpha[y, x] = 255
            for step in range(1, size + 1):
                for dx, dy in ((step, 0), (-step, 0), (0, step), (0, -step)):
                    if alpha[y + dy, x + dx] == 0:
                        rgb[y + dy, x + dx] = colour
                        alpha[y + dy, x + dx] = GLOW_ALPHA
        rgb[alpha == 0] = 0
        return np.dstack([rgb, alpha])


class Scene:
    """the two layers of a frame"""

    def __init__(self, outline, d, f, pivot=0.0, side_depth=None):
        self.pivot = pivot
        self.depth = side_depth if side_depth is not None and d in ('east', 'west') else DEPTH
        self.back = Canvas(outline)
        self.front = Canvas(outline)
        self.d = d
        self.f = f
        self.ph = TAU * f / FRAMES

    def layer(self, depth):
        return self.front if depth >= 0 else self.back

    def P(self, p):
        return project(p, self.d, self.pivot, self.depth)

    def leaf3(self, canvas, base, tip, wdir, hw, knots, shader, ramp, bend=0.0, minw=1.2, dim=0, line=None):
        """a long piece between two model points; wdir is the model direction of its width"""
        b = self.P(base)
        t = self.P(tip)
        w = self.P(vadd(base, wdir))
        ax, ay = t[0] - b[0], t[1] - b[1]
        ln = math.hypot(ax, ay)
        if ln < 1.5:
            return None
        across = abs((w[0] - b[0]) * (-ay / ln) + (w[1] - b[1]) * (ax / ln))
        hw2 = max(minw, hw * across)
        mask, tt, ss, lit = leaf(b, t, hw2, knots, bend)
        idx = shader(tt, ss, lit, hw2) - dim
        canvas.piece(mask, idx.astype(np.int8), ramp, line=line)
        return b, t

    def result(self, pair=False):
        """the two finished layers; pair: first make each the left half and its mirror picture (O714)"""
        if pair:
            self.back.pair()
            self.front.pair()
        return self.back.finish(), self.front.finish()


def merge(back, front):
    """front over back; a glow pixel of the front never repaints an opaque pixel of the back"""
    out = back.copy()
    fa = front[..., 3]
    solid = fa == 255
    out[solid] = front[solid]
    glow = (fa == GLOW_ALPHA) & (back[..., 3] != 255)
    out[glow] = front[glow]
    return out


# ------------------------------------------------------------------------------------------------ wing frame
def wing_axes(sgn, sweep, elev):
    """span direction of a wing (side sgn, swept back, raised by elev) and the direction its feathers hang"""
    u = (sgn * math.cos(sweep) * math.cos(elev), math.sin(elev), -math.sin(sweep) * math.cos(elev))
    k = -u[1]
    w = vnorm((-k * u[0], -1 - k * u[1], -k * u[2]))
    return u, w


class Wing:
    """local wing coordinates (a along the span, b down) -> model; the elevation may lag towards the tip"""

    def __init__(self, sgn, root, sweep, elev_at, length):
        self.sgn, self.root, self.sweep, self.elev_at, self.length = sgn, root, sweep, elev_at, length

    def at(self, a, b):
        u, w = wing_axes(self.sgn, self.sweep, self.elev_at(clamp(a / self.length, 0.0, 1.4)))
        return vadd(self.root, vadd(vmul(u, a), vmul(w, b)))

    def wdir(self, a, ang):
        """model direction across a feather that lies at angle `ang` (from the span towards down) at span place a"""
        u, w = wing_axes(self.sgn, self.sweep, self.elev_at(clamp(a / self.length, 0.0, 1.4)))
        return vadd(vmul(u, -math.sin(ang)), vmul(w, math.cos(ang)))


def sides_far_first(d):
    """the two wing sides, the far one first"""
    return sorted((-1, 1), key=lambda s: project((s * 3.0, 0, 0), d)[2])


def side_dim(d, sgn):
    """1 for the far wing when the wings are seen from the side: it is drawn a shade darker"""
    return 1 if d in ('east', 'west') and project((sgn * 3.0, 0, 0), d)[2] < 0 else 0


# ------------------------------------------------------------------------------------------------ designs
BONE = ((84, 72, 74), (140, 124, 112), (198, 184, 158), (234, 224, 198), (255, 250, 236))

EMBER_OUT = (30, 10, 14)
EMBER = ((52, 30, 38), (88, 44, 46), (160, 40, 30), (232, 104, 32), (255, 204, 92))
EMBER_ARM = ((40, 24, 32), (66, 38, 44), (98, 58, 58), (138, 86, 74), (180, 124, 100))


def ember_shader(tt, ss, lit, hw):
    idx = np.select([tt < 0.36, tt < 0.62, tt < 0.84], [1, 2, 3], 4).astype(np.int8)
    idx = idx - (~lit).astype(np.int8)
    return idx


def covert_shader(tt, ss, lit, hw):
    return np.where(lit, 2, 1).astype(np.int8) + (tt > 0.72)


def ember_pinions(sc):
    ph, d = sc.ph, sc.d
    wph = ph + 0.35 * math.sin(ph)
    length = 22.0
    for sgn in sides_far_first(d):
        dim = side_dim(d, sgn)
        wing = Wing(sgn, (sgn * 3.0, 9.0, -3.5), rad(42), lambda s: rad(30) + rad(22) * math.sin(wph - 0.9 * s), length)
        canvas = sc.layer(sc.P(wing.at(length * 0.4, 0))[2])
        spread = 1.0 + 0.16 * math.sin(wph - 0.6)

        def edge(s):
            return length * s, -3.6 * math.sin(math.pi * min(s, 1.0)) ** 0.8

        def feather(s, ang, ln, hw, shader, ramp, bend):
            a, b = edge(s)
            base = wing.at(a, b)
            tip = wing.at(a + ln * math.cos(ang), b + ln * math.sin(ang))
            sc.leaf3(canvas, base, tip, wing.wdir(a, ang), hw, FEATHER, shader, ramp, bend=bend * sgn, dim=dim)

        for j in range(5, -1, -1):                       # primaries, the outer ones below
            ang = rad((66 - 12 * j) * spread - 6)
            feather(0.60 + 0.08 * j, ang, 21.0 - 1.0 * j, 2.8, ember_shader, EMBER, 1.4)
        for i in range(4, -1, -1):                       # secondaries
            ang = rad(96 - 7 * i)
            feather(0.10 + 0.10 * i, ang, 13.0 + 2.0 * i, 2.9, ember_shader, EMBER, 0.6)
        for k in range(6, -1, -1):                       # coverts, a darker row over the feather roots
            ang = rad(84 - 8 * k)
            feather(0.06 + 0.14 * k, ang, 6.5, 2.4, covert_shader, EMBER_ARM, 0.0)
        arm = np.zeros((SIZE, SIZE), bool)
        prev = None
        for i in range(9):
            a, b = edge(i / 8.0)
            p = sc.P(wing.at(a, b - 0.6))
            if prev is not None:
                arm |= capsule_mask(prev, p, 1.7 - 0.08 * i, 1.7 - 0.08 * (i + 1))
            prev = p
        canvas.piece(arm, edge_shade(arm, 3, 2, 1) - dim, EMBER_ARM)
        # embers rise from the feather tips of the mean pose
        mean = Wing(sgn, wing.root, wing.sweep, lambda s: rad(30), length)
        for k in range(4):
            q = (sc.f / FRAMES + k / 4.0 + (0.13 if sgn > 0 else 0.0)) % 1.0
            j = (k * 2 + (1 if sgn > 0 else 0)) % 6
            a, b = edge(0.60 + 0.08 * j)
            ang = rad(60 - 12 * j)
            p = mean.at(a + 18 * math.cos(ang), b + 18 * math.sin(ang))
            x, y, _ = sc.P(p)
            x += 2.2 * math.sin(TAU * (q * 1.2 + k * 0.37))
            y -= 17 * q
            if q < 0.42:
                canvas.spark(x, y, EMBER[4], 1)
            elif q < 0.8:
                canvas.spark(x, y, EMBER[3], 0)


OSS_OUT = (30, 22, 28)
OSS_MOTE = (170, 240, 214)
OSS_SKIN = ((46, 28, 48), (72, 44, 70), (104, 66, 96), (140, 96, 128), (180, 140, 168))


def ossuary_wings(sc):
    ph, d = sc.ph, sc.d
    length = 24.0
    arm = ((0.0, 0.0), (7.0, -5.0), (15.0, -7.0), (22.5, -3.5))
    for sgn in sides_far_first(d):
        dim = side_dim(d, sgn)
        wing = Wing(sgn, (sgn * 3.0, 9.0, -3.5), rad(36), lambda s: rad(24) + rad(13) * math.sin(ph - 0.8 * s), length)
        canvas = sc.layer(sc.P(wing.at(length * 0.4, 0))[2])

        def bone(pts, hw0, hw1, knob0=0.0, knob1=0.0):
            m = np.zeros((SIZE, SIZE), bool)
            sp = [sc.P(wing.at(a, b)) for a, b in pts]
            n = len(sp) - 1
            for i in range(n):
                w0 = hw0 + (hw1 - hw0) * i / n
                w1 = hw0 + (hw1 - hw0) * (i + 1) / n
                m |= capsule_mask(sp[i], sp[i + 1], w0, w1)
            if knob0:
                m |= disc_mask(sp[0][0], sp[0][1], knob0)
            if knob1:
                m |= disc_mask(sp[-1][0], sp[-1][1], knob1)
            canvas.piece(m, edge_shade(m, 4, 3, 1) - dim, BONE)
            return sp

        ribs = []
        for i, (root, ang, ln) in enumerate(((arm[1], 82, 10.5), ((11.0, -6.2), 70, 14.0), (arm[2], 56, 16.5),
                                             (arm[3], 40, 13.0))):
            a0 = rad(ang + 5.0 * math.sin(ph - 0.5 - 0.45 * i))
            pts = [root]
            x, y = root
            for step in range(4):                         # a rib curls back towards the body, as a ribcage does
                turn = a0 + rad(17) * step
                x += ln / 4.0 * math.cos(turn)
                y += ln / 4.0 * math.sin(turn)
                pts.append((x, y))
            ribs.append(pts)
        for i in (3, 2, 1, 0):                           # torn skin at the root of each rib
            root, nxt = ribs[i][0], ribs[i][2]
            web = [sc.P(wing.at(root[0] - 3.2, root[1] + 0.6)), sc.P(wing.at(root[0] + 3.2, root[1] + 0.2)),
                   sc.P(wing.at(nxt[0] + 1.6, nxt[1])), sc.P(wing.at(nxt[0] - 1.2, nxt[1] - 1.0))]
            m = poly_mask([(q[0], q[1]) for q in web])
            canvas.piece(m, edge_shade(m, 2, 1, 0) - dim, OSS_SKIN)
        for i in (3, 2, 1, 0):
            bone(ribs[i], 1.45, 0.75)
        bone([arm[2], arm[3]], 1.6, 1.3, knob1=1.9)
        bone([arm[1], arm[2]], 1.8, 1.6, knob1=2.4)
        bone([arm[0], arm[1]], 2.0, 1.8, knob0=2.4, knob1=2.5)
        bone([arm[2], (arm[2][0] + 1.5, arm[2][1] - 5.0)], 1.1, 0.6)        # the thumb claw
        mean = Wing(sgn, wing.root, wing.sweep, lambda s: rad(24), length)
        for k in range(2):                                                # pale motes sink from the rib tips
            q = (sc.f / FRAMES + k / 2.0 + (0.27 if sgn > 0 else 0.0)) % 1.0
            tip = ribs[1 + k][-1]
            x, y, _ = sc.P(mean.at(tip[0], tip[1]))
            x += 1.6 * math.sin(TAU * (q + k * 0.4))
            y += 3 + 11 * q
            if q < 0.3:
                canvas.spark(x, y, OSS_MOTE, 1)
            elif q < 0.75:
                canvas.spark(x, y, OSS_MOTE, 0)


VOID_OUT = (20, 6, 34)
VOID = ((40, 14, 70), (66, 24, 112), (104, 40, 162), (160, 78, 220), (236, 196, 255))
VOID_GLOW = (206, 140, 255)


def void_orbit(sc):
    n = 5
    radius = 23.0
    tilt = rad(10)
    items = []

    def place(theta):
        x, z = radius * math.cos(theta), radius * math.sin(theta)
        return (x * math.cos(tilt), 2.0 + x * math.sin(tilt), z)

    for k in range(n):
        theta = TAU * (k / n + sc.f / (FRAMES * n))
        items.append((sc.P(place(theta)), 'orb', theta))
        for back_by in (0.33, 0.43, 0.52, 0.6, 0.67):
            items.append((sc.P(place(theta - back_by)), 'dot', 0))
    items.sort(key=lambda it: (it[0][2], it[1] != 'tail'))
    for (x, y, z), kind, arg in items:
        canvas = sc.layer(z)
        if kind == 'dot':
            canvas.spark(x, y, VOID_GLOW, 0)
        elif kind == 'tail':
            m = disc_mask(x, y, arg)
            canvas.piece(m, sphere_shade(x, y, arg + 0.5, (-0.2, 0.3, 0.8)), VOID)
        else:
            r = 4.5
            m = disc_mask(x, y, r)
            idx = sphere_shade(x, y, r + 0.6, (0.1, 0.5, 0.78, 0.93))
            rim = m & ~disc_mask(x - 0.8, y - 0.8, r - 0.75) & ((PX - x) + (PY - y) > 1.5)
            idx[rim] = 2                                               # light thrown back on the dark side
            canvas.piece(m, idx, VOID)
            flare = math.cos(arg - rad(70))
            canvas.spark(x - 1.6, y - 1.9, VOID[4], 2 if flare > 0.985 else 1 if flare > 0.93 else 0)
            hl = disc_mask(x - 1.6, y - 1.9, 0.8) & m
            canvas.rgb[hl & canvas.op] = VOID[4]


STEEL_OUT = (16, 18, 30)
STEEL = ((50, 56, 78), (88, 98, 124), (142, 154, 178), (198, 208, 224), (246, 250, 255))
GEM = ((70, 8, 22), (130, 16, 30), (196, 30, 42), (244, 96, 84), (255, 214, 200))
GRIP = ((36, 28, 30), (60, 46, 44), (92, 70, 60), (128, 100, 84), (170, 140, 116))


def blade_shader(tt, ss, lit, hw):
    idx = np.where(lit, 3, 1).astype(np.int8)
    idx = idx + ((tt > 0.5) & lit) - ((tt < 0.24) & ~lit)
    ridge = (np.abs(ss) * hw < 0.55) & lit & (tt > 0.18) & (hw > 1.6)
    idx[ridge] = 4
    return idx


def grip_shader(tt, ss, lit, hw):
    return np.where(lit, 3, 1).astype(np.int8) + (((tt * 6).astype(np.int32) % 2) == 0)


def bladefan(sc):
    ph, d = sc.ph, sc.d
    hub = (0.0, 9.0, -4.0)
    tau_back = rad(30)
    order = (0, 6, 1, 5, 2, 4, 3)
    for i in order:
        k = i - 3
        opened = ease(0.5 - 0.5 * math.cos(ph - 0.22 * abs(k)))
        half = rad(24 + 58 * opened)
        al = half * k / 3.0
        dirv = vnorm((math.sin(al), math.cos(al) * math.cos(tau_back), -math.cos(al) * math.sin(tau_back) - 0.12))
        wd = vnorm((math.cos(al), -math.sin(al) * math.cos(tau_back), math.sin(al) * math.sin(tau_back)))
        ln = 28.0 - 1.5 * abs(k)
        base = vadd(hub, vmul(dirv, 5.0))
        tip = vadd(hub, vmul(dirv, ln))
        canvas = sc.layer(sc.P(vadd(hub, vmul(dirv, ln * 0.5)))[2] + (0.01 if k == 0 else 0.0))
        sc.leaf3(canvas, vadd(hub, vmul(dirv, 1.0)), vadd(hub, vmul(dirv, 6.0)), wd, 1.3, ((0, 1), (1, 1)),
                 grip_shader, GRIP, minw=1.0)
        got = sc.leaf3(canvas, base, tip, wd, 2.9, BLADE, blade_shader, STEEL)
        if got:
            b, t = got
            glint = max(0.0, math.cos(ph - math.pi - 0.5 * k)) ** 6
            if glint > 0.35:
                gx, gy = b[0] + (t[0] - b[0]) * 0.86, b[1] + (t[1] - b[1]) * 0.86
                canvas.spark(gx, gy, STEEL[4], 2 if glint > 0.8 else 1)
    x, y, z = sc.P(hub)
    canvas = sc.layer(z + 0.02)
    m = disc_mask(x, y, 3.1)
    canvas.piece(m, sphere_shade(x, y, 3.6), GEM)


RIME_OUT = (14, 32, 74)
RIME = ((36, 80, 150), (66, 136, 206), (126, 194, 240), (198, 236, 252), (255, 255, 255))
RIME_GLOW = (214, 244, 255)


def shard_shader(tt, ss, lit, hw):
    idx = np.where(lit, 3, 1).astype(np.int8)
    idx = idx + (tt > 0.7) - ((tt < 0.2) & ~lit)
    ridge = (np.abs(ss) * hw < 0.55) & lit & (tt > 0.12) & (hw > 1.6)
    idx[ridge] = 4
    return idx


def rimeshard(sc):
    ph, d = sc.ph, sc.d
    length = 24.0
    shards = ((-44, 15.0, 2.6), (-16, 23.0, 3.2), (11, 26.5, 3.5), (40, 20.0, 3.1), (72, 13.5, 2.5))
    for sgn in sides_far_first(d):
        dim = side_dim(d, sgn)
        wing = Wing(sgn, (sgn * 3.0, 9.0, -3.5), rad(30), lambda s: rad(20) + rad(6) * math.sin(ph), length)
        canvas = sc.layer(sc.P(wing.at(length * 0.4, 0))[2])
        tips = {}
        for i in (4, 0, 3, 1, 2):
            ang, ln, hw = shards[i]
            pulse = 1.0 + 0.15 * math.sin(ph - 0.75 * i)
            a = rad(ang + 2.5 * math.sin(ph - 0.75 * i))
            base = wing.at(2.0 * math.cos(a), 2.0 * math.sin(a))
            tip = wing.at(ln * pulse * math.cos(a), ln * pulse * math.sin(a))
            got = sc.leaf3(canvas, base, tip, wing.wdir(0, a), hw, SHARD, shard_shader, RIME, dim=dim)
            if got:
                tips[i] = got
        for i, r in ((1, 5.5), (3, 5.0)):                              # small crystals at the root
            ang = rad(shards[i][0] + 13)
            base = wing.at(0, 0)
            tip = wing.at((r + 0.5 * math.sin(ph)) * math.cos(ang), (r + 0.5 * math.sin(ph)) * math.sin(ang))
            sc.leaf3(canvas, base, tip, wing.wdir(0, ang), 1.9, SHARD, shard_shader, RIME, dim=dim)
        for i, (b, t) in sorted(tips.items()):                         # a glint walks over the shards
            g = math.cos(ph - TAU * i / 5.0 - (math.pi if sgn > 0 else 0.0))
            if g > 0.72:
                canvas.spark(b[0] + (t[0] - b[0]) * 0.8, b[1] + (t[1] - b[1]) * 0.8, RIME[4], 2 if g > 0.93 else 1)
        mean = Wing(sgn, wing.root, wing.sweep, lambda s: rad(20), length)
        for k in range(2):                                             # frost falls
            q = (sc.f / FRAMES + k / 2.0 + (0.31 if sgn > 0 else 0.0)) % 1.0
            ang, ln, hw = shards[2 + k]
            x, y, _ = sc.P(mean.at(ln * 0.8 * math.cos(rad(ang)), ln * 0.8 * math.sin(rad(ang))))
            x += 1.5 * math.sin(TAU * (q + k * 0.3))
            y += 4 + 12 * q
            if q < 0.7:
                canvas.spark(x, y, RIME_GLOW, 0)


LANT_OUT = (16, 22, 18)
FLAME = ((16, 78, 40), (36, 150, 58), (112, 226, 88), (222, 255, 176), (255, 255, 236))
SKULLS = {
    'front': ("..xxxxx..",
              ".xxxxxxx.",
              "xxxxxxxxx",
              "xxxxxxxxx",
              "xkkxxxkkx",
              "xkgxxxgkx",
              "xxxxkxxxx",
              ".xxxxxxx.",
              ".xkxkxkx.",
              "..xxxxx.."),
    'side': ("..xxxxx..",
             ".xxxxxxx.",
             "xxxxxxxxx",
             "xxxxxxxxx",
             "xxxxxkkxx",
             "xxxxxgkxx",
             ".xxxxxxx.",
             "..xxxxxxx",
             "..xxkxkxk",
             "...xxxxx."),
    'back': ("..xxxxx..",
             ".xxxxxxx.",
             "xxxxxxxxx",
             "xxxxcxxxx",
             "xxxcxxxxx",
             "xxxxcxxxx",
             "xxxxxxxxx",
             ".xxxxxxx.",
             ".xxxxxxx.",
             "..xxxxx.."),
}
SKULL_FACE = {'south': ('front', False), 'north': ('back', False), 'east': ('side', False), 'west': ('side', True)}


def skull(canvas, cx, cy, facing, flip):
    rows = SKULLS[facing]
    h, w = len(rows), len(rows[0])
    x0 = int(math.floor(cx - w / 2.0 + 0.5))
    y0 = int(math.floor(cy - h / 2.0 + 0.5))
    mask = np.zeros((SIZE, SIZE), bool)
    marks = []
    for j, row in enumerate(rows):
        row = row[::-1] if flip else row
        for i, ch in enumerate(row):
            x, y = x0 + i, y0 + j
            if ch == '.' or not (1 <= x < SIZE - 1 and 1 <= y < SIZE - 1):
                continue
            mask[y, x] = True
            if ch != 'x':
                marks.append((x, y, ch))
    canvas.piece(mask, edge_shade(mask, 4, 3, 1), BONE)
    for x, y, ch in marks:
        canvas.rgb[y, x] = {'k': canvas.outline, 'g': FLAME[3], 'c': BONE[0]}[ch]
    return x0 + w / 2.0, y0


def grave_lanterns(sc):
    n = 3
    radius = 22.0
    items = []
    for k in range(n):
        theta = TAU * (k / n + sc.f / (FRAMES * n))
        p = (radius * math.cos(theta), 2.0 + 2.0 * math.sin(3 * theta), radius * 0.9 * math.sin(theta))
        items.append((sc.P(p), theta))
    items.sort(key=lambda it: it[0][2])
    facing, flip = SKULL_FACE[sc.d]
    for (x, y, z), theta in items:
        canvas = sc.layer(z)
        fl = sc.ph * 2 + 6 * theta
        topx, topy = skull(canvas, x, y, facing, flip)
        # the flame stands on the skull, three tongues of light
        h = 7.0 + 1.4 * math.sin(fl)
        sway = 1.3 * math.sin(fl * 0.5 + 1.0)
        bx, by = topx, topy + 0.5
        outer = poly_mask([(bx - 2.9, by), (bx - 3.2, by - h * 0.35), (bx - 1.4 + sway * 0.4, by - h * 0.7),
                           (bx + sway, by - h), (bx + 1.6 + sway * 0.4, by - h * 0.62), (bx + 3.2, by - h * 0.3),
                           (bx + 2.9, by)])
        inner = poly_mask([(bx - 1.6, by), (bx - 1.8, by - h * 0.3), (bx + sway * 0.5, by - h * 0.72),
                           (bx + 1.8, by - h * 0.28), (bx + 1.6, by)])
        idx = np.full((SIZE, SIZE), 1, np.int8)
        idx[inner] = 2
        idx[disc_mask(bx, by - 1.6, 1.1)] = 3
        canvas.piece(outer, idx, FLAME)
        for j in range(2):                                             # sparks leave the flame
            q = (sc.f / FRAMES * 2 + j / 2.0 + theta * 3 / TAU) % 1.0
            sx = bx + sway + 1.8 * math.sin(TAU * q + j * 2.0)
            sy = by - h - 1.5 - 7 * q
            if q < 0.75:
                canvas.spark(sx, sy, FLAME[2], 0)


DESIGNS = (
    ('ember_pinions', 'Ember Pinions', EMBER_OUT, ember_pinions, 9.0),
    ('ossuary_wings', 'Ossuary Wings', OSS_OUT, ossuary_wings, 9.0),
    ('void_orbit', 'Void Orbit', VOID_OUT, void_orbit, 4.0),
    ('bladefan', 'Bladefan', STEEL_OUT, bladefan, 9.0),
    ('rimeshard', 'Rimeshard', RIME_OUT, rimeshard, 9.0),
    ('grave_lanterns', 'Grave Lanterns', LANT_OUT, grave_lanterns, 3.0),
)
KEYS = tuple(row[0] for row in DESIGNS)


def design(key):
    for row in DESIGNS:
        if row[0] == key:
            return row
    raise KeyError(key)


def render_frame(key, d, f):
    """(back, front) RGBA arrays of one frame. O714: south and north are a left half and its mirror picture, west is
    the east frame mirrored about the anchor column"""
    if d == 'west':
        back, front = render_frame(key, 'east', f)
        return mirrored(back), mirrored(front)
    _, _, outline, fn, pivot = design(key)
    sc = Scene(outline, d, f, pivot)
    fn(sc)
    return sc.result(pair=d in ('south', 'north'))


def render(key):
    """{direction: [(back, front) per frame]}"""
    return {d: [render_frame(key, d, f) for f in range(FRAMES)] for d in DIRS}


def sheets(frames):
    """the three grids of one design: merged, back, front (rows north east south west, 16 columns)"""
    out = [np.zeros((SIZE * len(DIRS), SIZE * FRAMES, 4), np.uint8) for _ in range(3)]
    for r, d in enumerate(DIRS):
        for f in range(FRAMES):
            back, front = frames[d][f]
            for sheet, img in zip(out, (merge(back, front), back, front)):
                sheet[r * SIZE:(r + 1) * SIZE, f * SIZE:(f + 1) * SIZE] = img
    return out


def anchor_row():
    """the wings' centre x for wing_centres.lua, px from the creature's place with displacement 0, per direction"""
    return {d: ANCHOR[0] - 2 * 32 for d in DIRS}


def build(out_dir, keys=KEYS):
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for key in keys:
        for name, sheet in zip(('sheet', 'back', 'front'), sheets(render(key))):
            path = os.path.join(out_dir, '%s_%s.png' % (key, name))
            Image.fromarray(sheet, 'RGBA').save(path, optimize=False, compress_level=9)
            written.append(path)
    return written


# ------------------------------------------------------------------------------------------------ preview
BG = (56, 60, 68)
TINT = {(255, 255, 0): (150, 110, 80), (255, 0, 0): (120, 50, 54), (0, 255, 0): (72, 76, 100), (0, 0, 255): (84, 62, 50)}


def silhouette(d):
    """a plain leaning figure when there is no pair: (RGBA 96 x 96, already at the anchor)"""
    c = Canvas((30, 30, 36))
    grey = ((70, 72, 80), (104, 106, 116), (140, 142, 152), (176, 178, 186), (210, 212, 218))
    ax, ay = ANCHOR
    for (x0, y0), (x1, y1), w in (((ax + 3, ay + 13), (ax + 1, ay + 5), 2.4), ((ax - 2, ay + 14), (ax - 2, ay + 5), 2.4)):
        m = capsule_mask((x0, y0), (x1, y1), w)
        c.piece(m, edge_shade(m), grey)
    m = capsule_mask((ax, ay + 4), (ax - 2, ay - 5), 5.2, 5.8)
    c.piece(m, edge_shade(m), grey)
    hx, hy = ax - 5, ay - 12
    m = disc_mask(hx, hy, 4.6)
    c.piece(m, sphere_shade(hx, hy, 5.2), grey)
    if d != 'north':
        ex = {'south': 0, 'east': 2, 'west': -2}[d]
        c.rgb[int(hy), int(hx + ex) - 1] = c.outline
        c.rgb[int(hy), int(hx + ex) + 1] = c.outline
    return c.finish()


def pair_body(dat_path, spr_path, look):
    """{direction: RGBA 96 x 96} of a look of the pair, tinted through its colour template, torso on the anchor"""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr, sprite_index
    import gen_wing_centres as gw
    dat = Dat(dat_path)
    spr = Spr(spr_path)
    t = dat.outfit(look)
    if t is None:
        raise SystemExit('look %d is not in the pair' % look)
    disp = gw.displacement(t)
    out = {}
    for x, d in enumerate(DIRS):
        w, h = t.w * 32, t.h * 32
        layers = []
        for layer in range(min(t.layers, 2)):
            img = np.zeros((h, w, 4), np.uint8)
            for hh in range(t.h):
                for ww in range(t.w):
                    a = spr.sprite(t.sprites[sprite_index(t, x if t.px >= 4 else 0, 0, 0, layer, 0, ww, hh)])
                    if a is not None:
                        img[(t.h - 1 - hh) * 32:(t.h - hh) * 32, (t.w - 1 - ww) * 32:(t.w - ww) * 32] = a
            layers.append(img)
        body = layers[0].astype(np.float64)
        if len(layers) > 1:
            for key, colour in TINT.items():
                sel = (layers[1][..., :3] == key).all(axis=2) & (layers[1][..., 3] > 0)
                body[sel, :3] = body[sel, :3] * np.asarray(colour) / 170.0
        body = np.clip(body, 0, 255).astype(np.uint8)
        tx = gw.torso_x(body[..., 3])
        ox = int(round(ANCHOR[0] - (tx if tx is not None else w / 2.0)))
        oy = SIZE - h - disp[1] - 6
        canvas = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
        canvas.paste(Image.fromarray(body, 'RGBA'), (ox, oy))
        out[d] = np.asarray(canvas).copy()
    return out


def over(dst, src):
    """alpha blend src (RGBA) on dst (RGB float)"""
    a = src[..., 3:4].astype(np.float64) / 255.0
    return dst * (1 - a) + src[..., :3] * a


def compose(frames, bodies, d, f):
    back, front = frames[d][f]
    img = np.empty((SIZE, SIZE, 3), np.float64)
    img[:] = BG
    img = over(img, back)
    img = over(img, bodies[d])
    img = over(img, front)
    return img.astype(np.uint8)


def strip(frames, bodies, f):
    return np.concatenate([compose(frames, bodies, d, f) for d in DIRS], axis=1)


def upscale(img, k):
    return np.repeat(np.repeat(img, k, axis=0), k, axis=1)


def write_mp4(path, images, fps=12):
    h, w = images[0].shape[:2]
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (w, h),
           '-framerate', str(fps), '-i', '-', '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-crf', '18',
           '-movflags', '+faststart', path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for img in images:
        proc.stdin.write(np.ascontiguousarray(img).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit('ffmpeg failed for ' + path)


def preview(out_dir, dat=None, spr=None, look=2050, loops=6):
    os.makedirs(out_dir, exist_ok=True)
    bodies = pair_body(dat, spr, look) if dat and spr else {d: silhouette(d) for d in DIRS}
    every = {key: render(key) for key in KEYS}
    written = []
    for key in KEYS:
        seq = [upscale(strip(every[key], bodies, f), 4) for f in range(FRAMES)]
        path = os.path.join(out_dir, '%s.mp4' % key)
        write_mp4(path, seq * loops)
        written.append(path)
    seq = [upscale(np.concatenate([strip(every[key], bodies, f) for key in KEYS], axis=0), 3) for f in range(FRAMES)]
    path = os.path.join(out_dir, 'all_designs.mp4')
    write_mp4(path, seq * loops)
    written.append(path)
    rows = [np.concatenate([strip(every[key], bodies, f) for f in (0, 4, 8, 12)], axis=1) for key in KEYS]
    path = os.path.join(out_dir, 'scale_1x.png')
    Image.fromarray(np.concatenate(rows, axis=0), 'RGB').save(path)
    written.append(path)
    return written


def main(argv=None):
    argv = sys.argv[1:] if argv is None else list(argv)
    if argv and argv[0] in ('new-table', 'build-new', 'live-new'):
        sys.path.insert(0, HERE)
        import gen_drawn_wings_new as new        # the six looks of O581 phase 2 (pair 78)
        return new.main(argv)
    if argv and argv[0] in ('table', 'sheets', 'compare', 'fit', 'apply', 'live', 'measure', 'score'):
        sys.path.insert(0, HERE)
        import gen_drawn_wings_families as fam        # the 121 looks of the pair (O583)
        return fam.main(argv)
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('out_dir')
    b.add_argument('--only', default='')
    p = sub.add_parser('preview')
    p.add_argument('out_dir')
    p.add_argument('--dat')
    p.add_argument('--spr')
    p.add_argument('--look', type=int, default=2050)
    args = ap.parse_args(argv)
    if args.cmd == 'build':
        keys = tuple(k for k in args.only.split(',') if k) or KEYS
        for k in keys:
            design(k)
        for path in build(args.out_dir, keys):
            print(path)
    else:
        for path in preview(args.out_dir, args.dat, args.spr, args.look):
            print(path)
    return 0


if __name__ == '__main__':
    sys.exit(main())
