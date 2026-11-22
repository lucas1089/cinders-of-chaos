#!/usr/bin/env python3
"""Awakened spell look kit, drawn by code (O711, PROTOTYPE; docs/SPELL_UPGRADES.md 3.4). Our own art: no art file is read,
none is committed except the table and the sums.

    python3 -I gen_awakened_fx.py table                 # writes art_import/awakened_fx.csv and .sums
    python3 -I gen_awakened_fx.py check                 # CI, no pair: the code redraws the committed table and sums, the ids
                                                        # file and the tags are current
    python3 -I gen_awakened_fx.py sheets OUT_DIR        # sheet.png (contact sheet), one PNG per kit and the strips (never committed)
    python3 -I gen_awakened_fx.py preview OUT_DIR       # awakened_kits.mp4 (game scale) and awakened_kits_3x.mp4, ffmpeg,
                                                        # on a plain dark ground (never committed)
    python3 -I gen_awakened_fx.py build DAT SPR OUT_DIR # pair 75 -> pair 76 (the kit and the missiles) or pair 76 -> pair 77 (the
                                                        # 48 heading effects 5394..5441); any other pair is refused; OUT_DIR gets
                                                        # Tibia.dat, Tibia.spr and strips/
    python3 -I gen_awakened_fx.py live DAT SPR          # pair 76 or 77 holds every effect and missile at its id, pixel for pixel
    python3 -I gen_awakened_fx.py ids [--check]         # server/data/lib/chaos_awakened_fx_ids.lua, the tags of
                                                        # spell_fx_elements.csv

STATUS (O711, the owner approved the import): the kit is built into pair 76. The effects are appended after effect 5353 of
pair 75 (the footprints, O649) as 5354..5393. A missile id is ONE BYTE on the wire (254 is the weapon-type constant) and pair 75
holds 253 missiles, so the 8 missiles cannot be appended: they fill 3 blank stock ids (43, 47, 52) and rebuild 5 donor ids that
no script sends (147-151, pair 51) in place, as 3 x 3 direction patterns of 1 x 1 tiles made here from the east strip.
Server: data/lib/chaos_awakened_fx.lua (gate chaosClientPair >= 76), the awakened casts send these through data/lib/chaos_awakened_look.lua (O711).
The `slot` column of the table is the position inside the kit (effects 1..40, projectiles 1..8); the client id comes from it
(FIRST, MISSILE_IDS).

HEADINGS (O711 follow-up, pair 77): a line and a wave of each element also run north, south and west: 8 x 2 x 3 = 48 effects
5394..5441 (af_ELEMENT_SHAPE_north|south|west), slots 41..88 of the table, appended after the kit. The layout code takes the heading:
every body, the beam, the fan and the end ring are placed by `hp` (along the heading, across it) from the caster point; the bodies
themselves are drawn upright as ever, so the light and the ground rule stay and nothing is turned as pixels. The caster's tile of
a canvas is column w-1-dx, row h-1-dy (the client puts the bottom right tile of a canvas on the tile the effect is sent to, and
the server sends it on the caster's tile moved by dx, dy): west 8 x 2 (dx 0), north 3 x 9 (the caster at the bottom, dx 1), south
3 x 9 (the caster at the top below a head room row, dy 7); a wave west 5 x 4, north and south 5 x 5. The fan keeps its tile reach
and spread (126 px, 0.5 across), so the cone covers the same tiles turned. `sheets` writes headings.png, `preview` the MP4
awakened_headings.mp4 (fire, energy, holy: the line and the wave in four headings from one caster tile).

The kit (3.4): 8 elements x 5 shapes = 40 effects of 10 to 12 frames, plus 8 projectile strips.
  elements  fire, ice, energy, earth, death, holy, physical (the seven of spelldata.lua) and arcane (the eighth: the tag
            `arcane` of spell_fx_elements.csv, 13 effects of the old packs; a spell without a damage element of its own)
  shapes    single  3 x 3 tiles, on the target tile           around  3 x 3, a ring of the element around the caster
            circle  5 x 5, a blast spreading from the centre   line    8 x 2, a beam running east from the caster
            wave    5 x 4, a fan running east from the caster
            (a line or a wave of the 40 is drawn heading east; the other headings are the 48 effects of pair 77, below)
  missiles  1 x 1, 4 phases that close the loop, heading east (the 3 x 3 direction patterns are made by the build step)
The sigil ring is the awakened mark of every effect and missile: a double ring flat on the ground (a circle seen at the game's
angle is an ellipse half as high as wide) with rune ticks, small diamonds and four points, turning while the effect plays;
a missile carries a small vertical ring round its head. The element is the body of the effect: flames, shards of ice, bolts,
rock spikes, soul wisps with a skull, lances of light, crossed slashes, a rune eye with orbiting beads.

The drawing (the model of gen_lightning_fx.py, O614):
  alpha     0, one glow level (144) and 255. A transparent pixel carries no colour. No black outline: the edge of a body is
            the dark end of the element's own ramp.
  colour    a ramp of 24 steps a element (6 anchors, integer interpolation), dark rim to white core, hue moving along it.
  shapes    every body is a mask; its colour is the ramp step by the depth of the pixel inside it (erosion), a vertical
            gradient and a facet shift. The glow is a 2 px halo round the bright bodies.
Everything is integer raster work and scalar math on a seeded random.Random: the same bytes on every run.

Needs numpy and Pillow (the fx venv of CI); `preview` needs ffmpeg.
"""
import argparse
import contextlib
import csv
import hashlib
import io
import math
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'awakened_fx.csv')
SUMS = os.path.join(ART, 'awakened_fx.sums')

GLOW = 144                                  # the one glow level (docs/SPRITE_STYLE.md)
STAND = (16, 20)                            # the target point in the target tile: where a creature's feet are
MS = 80                                     # one frame
N = 24                                      # steps of a ramp
HALO = 9                                    # the glow colour: this step of the ramp

ELEMENTS = ['fire', 'ice', 'energy', 'earth', 'death', 'holy', 'physical', 'arcane']
SHAPES = ['single', 'circle', 'around', 'line', 'wave']

# element -> 6 anchors, dark rim .. white core
ANCHORS = {
    'fire': ((40, 8, 6), (120, 26, 12), (212, 70, 16), (255, 150, 36), (255, 214, 96), (255, 248, 214)),
    'ice': ((12, 28, 64), (34, 84, 148), (84, 170, 214), (150, 222, 240), (214, 246, 255), (255, 255, 255)),
    'energy': ((20, 8, 66), (58, 40, 170), (70, 126, 255), (130, 196, 255), (206, 238, 255), (255, 255, 255)),
    'earth': ((22, 12, 10), (62, 48, 44), (112, 110, 110), (164, 152, 140), (218, 180, 122), (255, 238, 184)),
    'death': ((4, 18, 16), (14, 62, 46), (40, 140, 84), (110, 220, 120), (190, 255, 170), (240, 255, 226)),
    'holy': ((64, 36, 8), (146, 92, 18), (226, 162, 40), (255, 214, 96), (255, 240, 170), (255, 255, 240)),
    'physical': ((44, 18, 22), (78, 66, 78), (126, 126, 140), (178, 184, 200), (222, 228, 238), (255, 255, 255)),
    'arcane': ((28, 6, 50), (84, 22, 126), (160, 56, 206), (222, 110, 240), (250, 186, 255), (255, 244, 255)),
}

# extra accent colours after the N steps of a ramp: earth gets moss and ember (indices N .. N + 3)
EXTRA = {'earth': ((84, 128, 52), (150, 188, 84), (214, 84, 28), (255, 178, 72))}

# shape -> canvas tiles, send offset (the target tile is column w-1-dx, row h-1-dy), frames
SHAPE = {
    'single': dict(w=3, h=3, dx=1, dy=1, n=10),
    'circle': dict(w=5, h=5, dx=2, dy=2, n=12),
    'around': dict(w=3, h=3, dx=1, dy=1, n=12),
    'line': dict(w=8, h=2, dx=7, dy=0, n=11),
    'wave': dict(w=5, h=4, dx=4, dy=1, n=11),
}
# O711 headings: line and wave drawn for the other three headings (pair 77). Canvas tiles; the caster's tile is column w-1-dx, row h-1-dy.
# north: the caster at the bottom, the body runs up; south: the caster at the top; west: the caster at the right. A tall body needs a
# row of head room above the caster (line south) or above the last body (line north).
HEADINGS = ['east', 'north', 'south', 'west']
NEW_HEADINGS = ['north', 'south', 'west']
HSHAPES = ['line', 'wave']
HSHAPE = {
    ('line', 'north'): dict(w=3, h=9, dx=1, dy=0, n=11),
    ('line', 'south'): dict(w=3, h=9, dx=1, dy=7, n=11),
    ('line', 'west'): dict(w=8, h=2, dx=0, dy=0, n=11),
    ('wave', 'north'): dict(w=5, h=5, dx=2, dy=0, n=11),
    ('wave', 'south'): dict(w=5, h=5, dx=2, dy=4, n=11),
    ('wave', 'west'): dict(w=5, h=4, dx=0, dy=1, n=11),
}
MISSILE_FRAMES = 4
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_awakened_fx_ids.lua')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')
PAIR = 76
PAIR_HEADINGS = 77                          # the pair that holds the 48 heading effects
FIRST = 5354                                # pair 75 ends at effect 5353 (footprints, O649)
NEED_EFFECTS, NEED_MISSILES = 5353, 253     # the input pair, exactly
KIT_EFFECTS = len(ELEMENTS) * len(SHAPES)   # 40 effects of pair 76: 5354..5393
HEAD_FIRST = FIRST + KIT_EFFECTS            # 5394: the heading effects follow the kit
HEAD_EFFECTS = len(ELEMENTS) * len(HSHAPES) * len(NEW_HEADINGS)   # 48: 5394..5441
MISSILE_IDS = [43, 47, 52, 147, 148, 149, 150, 151]   # element order: 3 blank stock ids, then 5 unsent donor ids rebuilt in place
BLANK_IDS = (43, 47, 52)
# the client's 3 x 3 missile patterns (x west / centre / east, y north / centre / south) and the heading of each (screen y down)
DIRS = {'east': (1, 0), 'west': (-1, 0), 'north': (0, -1), 'south': (0, 1),
        'northeast': (1, -1), 'southeast': (1, 1), 'southwest': (-1, 1), 'northwest': (-1, -1)}
PATTERN = {'east': (2, 1), 'west': (0, 1), 'north': (1, 0), 'south': (1, 2),
           'northeast': (2, 0), 'southeast': (2, 2), 'southwest': (0, 2), 'northwest': (0, 0)}
STEPS = {(1, 0): 0, (1, 1): 1, (0, 1): 2, (-1, 1): 3, (-1, 0): 4, (-1, -1): 5, (0, -1): 6, (1, -1): 7}
FIELDS = ['kind', 'slot', 'name', 'element', 'shape', 'heading', 'frames', 'w', 'h', 'dx', 'dy', 'ms', 'seed', 'note']


def ramp(el):
    """N colours from the 6 anchors, integer interpolation"""
    a = ANCHORS[el]
    den = N - 1
    out = []
    for i in range(N):
        num = i * (len(a) - 1)
        seg, rem = num // den, num % den
        if seg >= len(a) - 1:
            out.append(tuple(a[-1]))
            continue
        out.append(tuple((a[seg][c] * (den - rem) + a[seg + 1][c] * rem + den // 2) // den for c in range(3)))
    return out + [tuple(c) for c in EXTRA.get(el, ())]


def dims(shape, head='east'):
    """canvas tiles, send offset and frames of a shape heading `head`"""
    return SHAPE[shape] if head == 'east' else HSHAPE[(shape, head)]


def hp(head, gx, gy, d, c=0.0):
    """the screen point `d` px along the heading and `c` px across it (right of the heading is +c for east and west, +x for
    north and south) from the caster point (gx, gy)"""
    if head == 'east':
        return gx + d, gy + c
    if head == 'west':
        return gx - d, gy + c
    if head == 'north':
        return gx + c, gy - d
    return gx + c, gy + d


def anchor_of(shape, head='east'):
    """the caster / target point on the canvas of a shape"""
    s = dims(shape, head)
    return (s['w'] - 1 - s['dx']) * 32 + STAND[0], (s['h'] - 1 - s['dy']) * 32 + STAND[1]


# ------------------------------------------------------------------------------------------------- patches and the canvas
# a patch is (x0, y0, bool array): a mask on its own small window of the canvas
def _grid(x0, y0, x1, y1):
    import numpy as np
    ys, xs = np.mgrid[y0:y1, x0:x1]
    return xs + 0.5, ys + 0.5


def p_ell(cx, cy, rx, ry):
    x0, y0 = int(math.floor(cx - rx)) - 1, int(math.floor(cy - ry)) - 1
    x1, y1 = int(math.ceil(cx + rx)) + 2, int(math.ceil(cy + ry)) + 2
    xs, ys = _grid(x0, y0, x1, y1)
    return x0, y0, ((xs - cx) / max(rx, 0.3)) ** 2 + ((ys - cy) / max(ry, 0.3)) ** 2 <= 1.0


def p_disc(cx, cy, r):
    return p_ell(cx, cy, r, r)


def p_ring(cx, cy, rx, ry, th):
    a = p_ell(cx, cy, rx, ry)
    b = p_ell(cx, cy, max(0.3, rx - th), max(0.3, ry - th * 0.6))
    return p_minus(a, b)


def p_poly(pts):
    import numpy as np
    x0, y0 = int(math.floor(min(p[0] for p in pts))) - 1, int(math.floor(min(p[1] for p in pts))) - 1
    x1, y1 = int(math.ceil(max(p[0] for p in pts))) + 2, int(math.ceil(max(p[1] for p in pts))) + 2
    xs, ys = _grid(x0, y0, x1, y1)
    m = np.zeros(xs.shape, bool)
    n = len(pts)
    for i in range(n):
        xa, ya = pts[i]
        xb, yb = pts[(i + 1) % n]
        if ya == yb:
            continue
        lo, hi = min(ya, yb), max(ya, yb)
        cond = (ys >= lo) & (ys < hi)
        xi = xa + (ys - ya) * (xb - xa) / (yb - ya)
        m ^= cond & (xs < xi)
    return x0, y0, m


def p_pts(pts, size=1):
    import numpy as np
    pts = [(int(x), int(y)) for x, y in pts]
    if not pts:
        return 0, 0, np.zeros((1, 1), bool)
    x0, y0 = min(p[0] for p in pts), min(p[1] for p in pts)
    x1, y1 = max(p[0] for p in pts) + size, max(p[1] for p in pts) + size
    m = np.zeros((y1 - y0, x1 - x0), bool)
    for x, y in pts:
        m[y - y0:y - y0 + size, x - x0:x - x0 + size] = True
    return x0, y0, m


def p_grow(a, n=1):
    import numpy as np
    x0, y0, m = a
    m = np.pad(m, n)
    for i in range(n):
        g = m.copy()
        g[1:, :] |= m[:-1, :]
        g[:-1, :] |= m[1:, :]
        g[:, 1:] |= m[:, :-1]
        g[:, :-1] |= m[:, 1:]
        if i % 2:
            g[1:, 1:] |= m[:-1, :-1]
            g[1:, :-1] |= m[:-1, 1:]
            g[:-1, 1:] |= m[1:, :-1]
            g[:-1, :-1] |= m[1:, 1:]
        m = g
    return x0 - n, y0 - n, m


def _union_box(a, b):
    return (min(a[0], b[0]), min(a[1], b[1]),
            max(a[0] + a[2].shape[1], b[0] + b[2].shape[1]), max(a[1] + a[2].shape[0], b[1] + b[2].shape[0]))


def _in(a, box):
    import numpy as np
    x0, y0, x1, y1 = box
    out = np.zeros((y1 - y0, x1 - x0), bool)
    out[a[1] - y0:a[1] - y0 + a[2].shape[0], a[0] - x0:a[0] - x0 + a[2].shape[1]] = a[2]
    return out


def p_minus(a, b):
    box = _union_box(a, b)
    return box[0], box[1], _in(a, box) & ~_in(b, box)


def p_and(a, b):
    box = _union_box(a, b)
    return box[0], box[1], _in(a, box) & _in(b, box)


def p_or(a, b):
    box = _union_box(a, b)
    return box[0], box[1], _in(a, box) | _in(b, box)


def line_pts(a, b):
    """Bresenham, both ends included"""
    x0, y0, x1, y1 = int(round(a[0])), int(round(a[1])), int(round(b[0])), int(round(b[1]))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    out = []
    while True:
        out.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return out
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def path_pts(pts):
    out = []
    for a, b in zip(pts, pts[1:]):
        for p in line_pts(a, b):
            if not out or out[-1] != p:
                out.append(p)
    return out


def ribbon(pts, wid):
    """a polygon along a polyline, wid(t) the half width at t in 0..1 along it"""
    left, right = [], []
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        a, b = pts[max(0, i - 1)], pts[min(n - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        w = wid(i / max(1, n - 1))
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return p_poly(left + right[::-1])


class Cv:
    """the canvas of one frame: a ramp step and an alpha for every pixel"""

    def __init__(self, W, H, el):
        import numpy as np
        self.W, self.H, self.el = W, H, el
        self.ramp = ramp(el)
        self.idx = np.zeros((H, W), np.int16)
        self.al = np.zeros((H, W), np.uint8)
        self.glow = np.zeros((H, W), bool)

    def _win(self, patch):
        x0, y0, m = patch
        h, w = m.shape
        cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(self.W, x0 + w), min(self.H, y0 + h)
        if cx0 >= cx1 or cy0 >= cy1:
            return None
        return (slice(cy0, cy1), slice(cx0, cx1)), (slice(cy0 - y0, cy1 - y0), slice(cx0 - x0, cx1 - x0))

    def fill(self, patch, lo=8, hi=18, K=3, edge=2, vg=(0, 0), lr=None, bands=None, glow=False, alpha=255, flat=False):
        """paint a mask. Colour: lo..hi by the depth inside (K steps), edge (a step of the ramp) on the rim pixels, vg = shift
        at the top and at the bottom, lr = (axis x, shift left, shift right), bands = (period, thick, shift) of rows"""
        import numpy as np
        x0, y0, m = patch
        w = self._win(patch)
        if w is None or not m.any():
            return
        rows, cols = m.shape
        if flat:
            idx = np.full(m.shape, lo, np.int32)
            rim = np.zeros(m.shape, bool)
        else:
            cur = np.pad(m, 1)
            depth = np.zeros(m.shape, np.int32)
            for _ in range(K):
                inner = cur[1:-1, 1:-1] & cur[:-2, 1:-1] & cur[2:, 1:-1] & cur[1:-1, :-2] & cur[1:-1, 2:]
                nxt = np.zeros_like(cur)
                nxt[1:-1, 1:-1] = inner
                depth += nxt[1:-1, 1:-1]
                cur = nxt
            idx = lo + ((hi - lo) * np.minimum(depth, K)) // max(1, K)
            rim = m & (depth == 0)
            r = np.arange(rows, dtype=np.int32)[:, None]
            if vg != (0, 0):
                idx = idx + (vg[0] * (rows - 1 - r) + vg[1] * r) // max(1, rows - 1)
            if lr is not None:
                cx = np.arange(cols, dtype=np.int32)[None, :] + x0
                idx = idx + np.where(cx < lr[0], lr[1], lr[2])
            if bands is not None:
                yy = np.arange(rows, dtype=np.int32)[:, None] + y0
                idx = idx - np.where((yy % bands[0]) < bands[1], bands[2], 0)
            idx = np.clip(idx, 1, N - 1)
            if edge is not None:
                idx = np.where(rim, edge, idx)
        (cs, ps) = w
        mm = m[ps]
        self.idx[cs] = np.where(mm, idx[ps], self.idx[cs])
        self.al[cs] = np.where(mm, alpha, self.al[cs])
        if glow:
            self.glow[cs] |= mm

    def px(self, pts, idx, alpha=255, glow=False, size=1):
        self.fill(p_pts(pts, size), lo=idx, flat=True, alpha=alpha, glow=glow)

    def finish(self):
        """the halo of the glowing bodies, then RGBA"""
        import numpy as np
        g = self.glow
        h = g.copy()
        for i in range(2):
            n = h.copy()
            n[1:, :] |= h[:-1, :]
            n[:-1, :] |= h[1:, :]
            n[:, 1:] |= h[:, :-1]
            n[:, :-1] |= h[:, 1:]
            h = n
        h &= self.al == 0
        self.idx[h] = HALO
        self.al[h] = GLOW
        out = np.zeros((self.H, self.W, 4), np.uint8)
        lut = np.array(self.ramp, np.uint8)
        vis = self.al > 0
        out[vis, :3] = lut[self.idx[vis]]
        out[..., 3] = self.al
        return out


# ------------------------------------------------------------------------------------------------- the sigil ring
def sigil(cv, cx, cy, rx, spin, pres, bright=15):
    """the awakened mark: a double ring flat on the ground, rune ticks, diamonds and four points, turning with `spin`"""
    ry = rx * 0.5

    def at(a, k, kk=None):
        return cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * (k if kk is None else kk)

    def keep(i):
        return (i * 0.6180339887) % 1.0 < pres + 0.12

    seg = 36
    pts = []
    for i in range(seg):                                   # the outer ring in pieces, so it breaks up while it fades
        if not keep(i):
            continue
        a0 = 2 * math.pi * i / seg
        for j in range(8):
            x, y = at(a0 + 2 * math.pi * j / (seg * 8), 1.0)
            pts.append((x, y))
    cv.px(pts, bright, glow=True)
    if rx < 13:
        return
    pts = []
    for i in range(24):                                    # the inner ring: dashes that turn
        if i % 2 or not keep(i + 7):
            continue
        a0 = spin + 2 * math.pi * i / 24
        for j in range(5):
            x, y = at(a0 + math.radians(j * 4.5), 0.72)
            pts.append((x, y))
    cv.px(pts, bright - 4)
    ticks, diam = [], []
    for k in range(12):                                    # between the rings: a tick, a diamond, a tick ...
        if not keep(k + 3):
            continue
        a = spin + k * math.pi / 6
        if k % 2 == 0:
            ticks += line_pts(at(a, 0.74), at(a, 0.97))
        else:
            x, y = at(a, 0.86)
            diam += [(x, y - 1), (x - 1, y), (x, y), (x + 1, y), (x, y + 1)]
    cv.px(ticks, bright + 2)
    cv.px(diam, min(N - 1, bright + 5))
    if rx >= 16:
        pts = []
        for k in range(4):                                 # four points beyond the ring
            if keep(k + 11):
                pts += line_pts(at(spin + k * math.pi / 2, 1.0), at(spin + k * math.pi / 2, 1.16))
        cv.px(pts, min(N - 1, bright + 6), glow=True)


# ------------------------------------------------------------------------------------------------- the bodies of the elements
def env(p):
    """life p in 0..1 -> (grow, fade): up fast, hold, thin out"""
    if p <= 0 or p >= 1:
        return 0.0, 0.0
    g = min(1.0, p / 0.34)
    g = 1 - (1 - g) ** 2
    f = 1.0 if p < 0.6 else max(0.0, 1.0 - (p - 0.6) / 0.4)
    return g, f


def u_fire(cv, x, y, s, p, seed, t):
    g, f = env(p)
    if g <= 0:
        return
    rnd = random.Random(seed)
    H = s * g * (0.25 + 0.75 * f)
    rx = max(3.0, s * 0.30 * (0.4 + 0.6 * g) * (0.5 + 0.5 * f))
    cv.fill(p_ell(x, y, rx, rx * 0.5), lo=7, flat=True, alpha=GLOW)
    for dx, hs, ws, ph in ((-0.2, 0.62, 0.75, 1.9), (0.23, 0.55, 0.7, 3.7), (0.0, 1.0, 1.0, 0.0)):
        h = H * hs
        if h < 4:
            continue
        w0 = max(2.5, s * 0.15 * ws)
        m = max(4, int(h / 3))
        for core in (0, 1):
            hh, ww = (h, w0) if not core else (h * 0.58, w0 * 0.5)
            left, right = [], []
            for j in range(m + 1):
                ty = j / m
                cx = x + dx * s + s * 0.08 * ty * ty * math.sin(ph + t * 1.3)
                half = ww * (1 - ty) ** 0.75
                left.append((cx - half, y - hh * ty))
                right.append((cx + half, y - hh * ty))
            if core:
                cv.fill(p_poly(left + right[::-1]), lo=14, hi=22, K=2, edge=None, vg=(-1, 2))
            else:
                cv.fill(p_poly(left + right[::-1]), lo=9, hi=17, K=4, edge=3, vg=(-4, 3), glow=True)
    if f > 0.12:
        for i in range(5):
            off = rnd.uniform(-1, 1)
            q = (p * 1.3 + i * 0.21 + rnd.random() * 0.08) % 1.0
            ex = x + off * s * 0.36 + math.sin(q * 6 + i) * 2
            ey = y - s * (0.12 + 0.9 * q) * g
            cv.px([(ex, ey)], 21 - int(q * 7), size=2 if q < 0.5 else 1, glow=q < 0.5)


def u_ice(cv, x, y, s, p, seed, t):
    g, f = env(p)
    if g <= 0:
        return
    rnd = random.Random(seed)
    H = s * g * (0.3 + 0.7 * f)
    rx = max(3.0, s * 0.34 * (0.5 + 0.5 * g))
    cv.fill(p_ell(x, y, rx, rx * 0.5), lo=10, flat=True, alpha=GLOW)
    for dx, hs, tilt, bwf in ((-0.24, 0.62, -0.32, 0.10), (0.22, 0.78, 0.28, 0.11), (0.0, 1.0, 0.0, 0.12)):
        h = H * hs
        if h < 5:
            continue
        bw = max(2.6, s * bwf)
        bx = x + dx * s
        c, sn = math.cos(tilt), math.sin(tilt)
        loc = [(-bw, 0), (-bw * 1.15, 0.38 * h), (0, h), (bw * 1.15, 0.38 * h), (bw, 0)]
        pts = [(bx + u * c + v * sn, y - (v * c - u * sn)) for u, v in loc]
        axis = (pts[0][0] + pts[4][0]) / 2 * 0.5 + pts[2][0] * 0.5
        cv.fill(p_poly(pts), lo=8, hi=17, K=3, edge=2, lr=(axis, 3, -4), glow=True)
        tip = pts[2]
        ridge = line_pts(((pts[0][0] + pts[4][0]) / 2, y), tip)
        cv.px(ridge, 21)
        cv.px([tip], 23)
    for i in range(3):                                       # chips on the ground
        a = rnd.uniform(0, 2 * math.pi)
        d = s * (0.25 + 0.15 * rnd.random())
        cv.px([(x + math.cos(a) * d, y + math.sin(a) * d * 0.5)], 14 + i * 2, size=2)
    if p > 0.45:                                             # the shatter: motes thrown out
        q = (p - 0.45) / 0.55
        for i in range(8):
            a = (i + rnd.random() * 0.6) * math.pi / 4
            d = s * (0.18 + 0.5 * q)
            cv.px([(x + math.cos(a) * d, y - s * 0.3 + math.sin(a) * d * 0.7 - q * 4)], 22 if q < 0.6 else 17,
                  size=2 if q < 0.4 else 1, glow=q < 0.6)


def u_energy(cv, x, y, s, p, seed, t):
    """a forked jagged bolt from above to the ground: thin at the top, forks run down and out and end in the air"""
    g, f = env(p)
    if g <= 0:
        return
    rnd = random.Random(seed * 131 + t * 17)
    H = s * g * (0.35 + 0.65 * f)
    rx = max(3.0, s * 0.3 * (0.5 + 0.5 * g))
    cv.fill(p_ell(x, y, rx, rx * 0.5), lo=8, flat=True, alpha=GLOW)
    for i in range(4):                                       # sparks along the ground
        a = i * math.pi / 2 + 0.5 + rnd.random() * 0.4
        cv.px(line_pts((x + math.cos(a) * rx * 0.3, y + math.sin(a) * rx * 0.15),
                       (x + math.cos(a) * rx, y + math.sin(a) * rx * 0.5)), 16)
    if H < 6:
        return
    lean = s * 0.22 * math.sin(seed * 0.7 + 0.3)
    top = (x + lean, y - H)
    pts = _disp(rnd, [top, (x, y)], 0.17, 4)
    main = path_pts(pts)
    n = len(pts)
    cv.fill(p_grow(p_pts(main), 1), lo=9, hi=14, K=2, edge=7, glow=True)
    cv.px(main, 22)
    for k, side in enumerate((-1, 1)):                       # forks: they leave the upper half and run down and out
        at = min(n - 3, int(n * (0.22 + 0.2 * k) + rnd.random() * 2))
        a = pts[at]
        ln = H * (0.45 - 0.08 * k)
        end = (a[0] + side * ln * 0.55, a[1] + ln * 0.8)
        fk = [q for q in _disp(rnd, [a, end], 0.22, 3) if q[1] < y - 3]
        if len(fk) < 3:
            continue
        fp = path_pts(fk)
        cv.px(fp, 15, glow=True)
        cv.px(fp[:len(fp) * 2 // 3], 19)
        if len(fp) > 6:                                      # a short twig
            b = fp[len(fp) // 2]
            tw = path_pts(_disp(rnd, [b, (b[0] - side * ln * 0.2, b[1] + ln * 0.22)], 0.3, 2))
            cv.px(tw, 13)


def _disp(rnd, pts, rough, depth):
    """midpoint displacement (the bolt)"""
    for _ in range(depth):
        new = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dy) or 1.0
            off = (rnd.random() * 2 - 1) * rough * ln
            new.append(((a[0] + b[0]) / 2 - dy / ln * off, (a[1] + b[1]) / 2 + dx / ln * off))
            new.append(b)
        pts = new
    return pts


def u_earth(cv, x, y, s, p, seed, t):
    g, f = env(p)
    if g <= 0:
        return
    rnd = random.Random(seed)
    H = s * g * (0.25 + 0.75 * f)
    for i in range(3):                                       # cracks in the ground
        a = math.pi * (0.15 + 0.35 * i) + rnd.random() * 0.3
        a = a if i != 1 else a + math.pi
        e = s * 0.52 * g
        mid = (x + math.cos(a) * e * 0.5, y + math.sin(a) * e * 0.25 + rnd.uniform(-2, 2))
        cv.px(path_pts([(x, y), mid, (x + math.cos(a) * e, y + math.sin(a) * e * 0.5)]), N + 2)
    spikes = ((-0.26, 0.58, 0.16), (0.27, 0.66, 0.17), (0.0, 1.0, 0.2))
    for dx, hs, bwf in spikes:
        h = H * hs
        if h < 5:
            continue
        bw = max(3.2, s * bwf)
        bx = x + dx * s
        j = [rnd.uniform(-0.12, 0.12) for _ in range(6)]
        pts = [(bx - bw, y), (bx - bw * (0.82 + j[0]), y - h * 0.3), (bx - bw * (0.46 + j[1]), y - h * 0.62),
               (bx + bw * 0.06, y - h), (bx + bw * (0.5 + j[2]), y - h * 0.56), (bx + bw * (0.9 + j[3]), y - h * 0.26),
               (bx + bw, y)]
        cv.fill(p_poly(pts), lo=5, hi=11, K=3, edge=1, lr=(bx + bw * 0.04, 4, -4), bands=(5, 1, 3), vg=(3, -2))
        cv.px([(bx - bw * 0.3, y - h * 0.62), (bx - bw * 0.25, y - h * 0.3)], 20, size=2)
        cv.px([(bx + bw * 0.1, y - h + 1)], 22, size=2)
        cv.px([(bx - bw * 0.7, y - 2), (bx + bw * 0.2, y - 1), (bx + bw * 0.6, y - 3)], N + 1 if dx else N, size=2)
        cv.px([(bx + bw * 0.3, y - h * 0.2)], N + 3)
    for i in range(3):                                       # rock thrown up
        q = (p * 1.15 + i * 0.17) % 1.0
        d = (-1, 1, 0.4)[i]
        cx = x + d * s * 0.62 * q
        cy = y - s * 1.0 * (1 - (2 * q - 1) ** 2) * g - 2
        if f <= 0.05:
            continue
        r0 = 2.6 + i * 0.7
        pts = [(cx + math.cos(a0 + t * 0.9) * r0 * (0.8 + 0.4 * ((k + i) % 2)),
                cy + math.sin(a0 + t * 0.9) * r0 * (0.8 + 0.4 * ((k + i) % 2)))
               for k, a0 in enumerate((0, 1.25, 2.5, 3.8, 5.0))]
        cv.fill(p_poly(pts), lo=7, hi=15, K=2, edge=1, lr=(cx, 3, -3))
        cv.px([(cx, cy)], N + 3)
    if p < 0.8:                                              # dust
        for sd in (-1, 1):
            r0 = s * 0.12 * (0.6 + g) * (1.1 - p * 0.6)
            cv.fill(p_disc(x + sd * s * (0.28 + 0.4 * p), y - s * 0.1 * p, r0), lo=11, flat=True, alpha=GLOW)


def u_death(cv, x, y, s, p, seed, t):
    g, f = env(p)
    if g <= 0:
        return
    rnd = random.Random(seed)
    H = s * g * (0.3 + 0.7 * f)
    rx = max(3.0, s * 0.32 * (0.5 + 0.5 * g))
    cv.fill(p_ell(x, y, rx, rx * 0.5), lo=3, flat=True, alpha=GLOW)
    cv.fill(p_ring(x, y, rx, rx * 0.5, 1.4), lo=11, flat=True)
    tips = []
    for dx, hs, ph in ((-0.22, 0.8, 0.0), (0.22, 0.7, 2.1), (0.0, 1.0, 4.2)):
        h = H * hs
        if h < 5:
            continue
        pts = []
        m = max(5, int(h / 3))
        for j in range(m + 1):
            ty = j / m
            pts.append((x + dx * s + s * 0.14 * math.sin(ph + t * 0.8 + ty * 4.4) * (0.3 + ty), y - h * ty))
        cv.fill(ribbon(pts, lambda ty: 1.0 + s * 0.085 * (1 - ty) ** 0.8), lo=5, hi=15, K=3, edge=1, vg=(3, -2), glow=True)
        tips.append((pts[-1], dx))
    for (tx, ty), dx in tips:
        if dx == 0.0 and s >= 30:                            # a skull on the tallest wisp
            r0 = max(3.4, s * 0.115)
            cv.fill(p_ell(tx, ty - r0 * 0.1, r0, r0 * 0.95), lo=13, hi=21, K=2, edge=5, glow=True)
            cv.fill(p_poly([(tx - r0 * 0.55, ty + r0 * 0.6), (tx + r0 * 0.55, ty + r0 * 0.6),
                            (tx + r0 * 0.45, ty + r0 * 1.35), (tx - r0 * 0.45, ty + r0 * 1.35)]), lo=12, hi=18, K=1, edge=4)
            for e in (-1, 1):
                cv.fill(p_disc(tx + e * r0 * 0.42, ty - r0 * 0.05, max(1.2, r0 * 0.27)), lo=0, flat=True)
            cv.px([(tx - 0.5, ty + r0 * 0.4)], 1)
        else:
            r0 = max(2.4, s * 0.07)
            cv.fill(p_ring(tx, ty, r0, r0, 1.6), lo=17, flat=True, glow=True)
    if f > 0.1:
        for i in range(5):                                   # souls drifting up
            q = (p * 1.2 + i * 0.2 + rnd.random() * 0.1) % 1.0
            sx = x + rnd.uniform(-1, 1) * s * 0.4 + math.sin(q * 7 + i) * 2
            cv.px([(sx, y - s * (0.1 + 0.9 * q) * g)], 19 - int(q * 6), size=2 if q < 0.45 else 1, glow=q < 0.45)


def u_holy(cv, x, y, s, p, seed, t):
    g, f = env(p)
    if g <= 0:
        return
    rnd = random.Random(seed)
    h = s * g * (0.3 + 0.7 * f)
    rx = max(3.0, s * 0.36 * (0.5 + 0.5 * g))
    cv.fill(p_ell(x, y, rx, rx * 0.5), lo=12, flat=True, alpha=GLOW)
    cv.fill(p_ring(x, y, rx, rx * 0.5, 1.2), lo=18, flat=True)
    if h < 5:
        return
    oy = y - 0.5 * h
    for i, ang in enumerate((-88, -62, -30, 30, 62, 88)):    # rays: from the vertical
        L = s * (0.55 if i % 2 == 0 else 0.4) * g * (0.4 + 0.6 * f)
        a = math.radians(ang)
        ex, ey = x + math.sin(a) * L, oy - math.cos(a) * L * 0.9
        nx, ny = math.cos(a), math.sin(a)
        cv.fill(p_poly([(x - nx * 1.4, oy + ny * 1.0), (x + nx * 1.4, oy - ny * 1.0), (ex, ey)]), lo=13, flat=True, glow=True)
    bw = max(2.6, s * 0.085)
    pts = [(x - bw, y), (x - bw * 0.8, y - 0.55 * h), (x, y - h), (x + bw * 0.8, y - 0.55 * h), (x + bw, y)]
    cv.fill(p_poly(pts), lo=12, hi=22, K=3, edge=8, glow=True)
    cv.px(line_pts((x, y), (x, y - h)), 23)
    cv.fill(p_ring(x, y - 0.8 * h, s * 0.2, s * 0.07, 1.4), lo=18, flat=True, glow=True)
    r1, r2 = s * 0.14 * g, s * 0.2 * g                        # the star at the tip
    sx, sy = x, y - h
    cv.fill(p_poly([(sx - r1, sy), (sx, sy - 1.5), (sx + r1, sy), (sx, sy + 1.5)]), lo=22, flat=True, glow=True)
    cv.fill(p_poly([(sx, sy - r2), (sx + 1.5, sy), (sx, sy + r2), (sx - 1.5, sy)]), lo=23, flat=True, glow=True)
    if f > 0.1:
        for i in range(5):
            q = (p * 1.1 + i * 0.2 + rnd.random() * 0.1) % 1.0
            cv.px([(x + rnd.uniform(-1, 1) * s * 0.38, y - s * (0.08 + 0.95 * q) * g)], 22 - int(q * 5), size=2 if q < 0.4 else 1,
                  glow=q < 0.4)


def _bez(a, c, b, n):
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t * t * b[0],
                    (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t * t * b[1]))
    return out


def u_physical(cv, x, y, s, p, seed, t):
    g, f = env(p)
    if g <= 0:
        return
    rnd = random.Random(seed)
    for k, (sg, delay) in enumerate(((1, 0.0), (-1, 0.14))):  # two slashes, one across the other
        u = (p - delay) / 0.4
        if u <= 0:
            continue
        u = min(1.0, u)
        a = (x - sg * 0.46 * s, y - 0.98 * s)
        b = (x + sg * 0.46 * s, y - 0.1 * s)
        c = (x + sg * 0.34 * s, y - 0.9 * s)
        path = _bez(a, c, b, 16)
        i1 = max(2, int(len(path) * u))
        i0 = 0 if p < 0.55 else int((len(path) - 2) * min(1.0, (p - 0.55) / 0.45))
        part = path[i0:i1 + 1]
        if len(part) >= 3:
            th = 0.095 * s
            cv.fill(ribbon(part, lambda tt: max(0.8, th * (math.sin(math.pi * min(1, max(0, tt))) ** 0.7))),
                    lo=9, hi=22, K=3, edge=3, glow=True)
    if p > 0.3:                                              # the impact
        q = min(1.0, (p - 0.3) / 0.2)
        sh = max(0.0, 1.0 - max(0.0, (p - 0.6) / 0.4))
        R = s * 0.3 * q * (0.4 + 0.6 * sh)
        if R > 2:
            star = []
            for i in range(16):
                a = i * math.pi / 8 + 0.2
                r0 = R if i % 2 == 0 else R * 0.3
                star.append((x + math.cos(a) * r0, y - 0.1 * s + math.sin(a) * r0 * 0.55))
            cv.fill(p_poly(star), lo=10, hi=22, K=2, edge=3, glow=True)
        cv.fill(p_ell(x, y - 0.1 * s, R * 0.9 + 1, R * 0.4 + 1), lo=14, flat=True, alpha=GLOW)
        for i in range(4):
            ang = rnd.uniform(0.15, math.pi - 0.15)
            q2 = min(1.0, (p - 0.3) / 0.6)
            d = s * 0.65 * q2
            cx, cy = x + math.cos(ang) * d * (1 if i % 2 else -1), y - s * 0.1 - math.sin(ang) * d * 0.9 + q2 * q2 * s * 0.3
            if sh > 0.05:
                cv.fill(p_poly([(cx - 2, cy + 2), (cx + 2, cy + 1), (cx, cy - 2.5)]), lo=11 + i * 2, flat=True)


def u_arcane(cv, x, y, s, p, seed, t):
    g, f = env(p)
    if g <= 0:
        return
    rnd = random.Random(seed)
    k = g * (0.45 + 0.55 * f)
    R = max(3.0, 0.15 * s * (0.5 + 0.5 * g) * (0.55 + 0.45 * f))
    cx, cy = x, y - 0.46 * s * (0.7 + 0.3 * g)
    cv.fill(p_ell(x, y, max(3, s * 0.3 * k), max(3, s * 0.3 * k) * 0.5), lo=8, flat=True, alpha=GLOW)
    cv.fill(p_poly([(x - 2, y), (x - 1, cy), (x + 1, cy), (x + 2, y)]), lo=10, flat=True, alpha=GLOW)
    beads = []
    for i in range(3):
        a = t * 0.6 + i * 2.094
        beads.append((math.sin(a), cx + math.cos(a) * s * 0.3 * k, cy + math.sin(a) * s * 0.3 * k * 0.45))
    for sn, bx, by in beads:
        if sn < 0:
            cv.fill(p_disc(bx, by, 2.0), lo=14, hi=19, K=1, edge=6, glow=True)
    cv.fill(p_disc(cx, cy, R), lo=7, hi=19, K=4, edge=2, glow=True)
    cv.fill(p_ell(cx, cy, R * 0.3, R * 0.78), lo=1, flat=True)
    cv.px([(cx, cy - 1)], 22)
    fl, fv = s * 0.34 * k, s * 0.3 * k
    cv.fill(p_poly([(cx - fl, cy), (cx, cy - 1.3), (cx + fl, cy), (cx, cy + 1.3)]), lo=19, flat=True, glow=True)
    cv.fill(p_poly([(cx, cy - fv), (cx + 1.3, cy), (cx, cy + fv * 0.8), (cx - 1.3, cy)]), lo=20, flat=True, glow=True)
    cv.fill(p_ring(cx, cy, R * 1.9, R * 0.85, 1.3), lo=13, flat=True)
    for sn, bx, by in beads:
        if sn >= 0:
            cv.fill(p_disc(bx, by, 2.0), lo=15, hi=21, K=1, edge=6, glow=True)
    if f > 0.1:
        for i in range(6):
            q = (p * 1.1 + i * 0.17 + rnd.random() * 0.1) % 1.0
            cv.px([(x + rnd.uniform(-1, 1) * s * 0.4, y - s * (0.9 - 0.8 * q) * g)], 20 - int(q * 6), size=2 if q < 0.4 else 1,
                  glow=q < 0.4)


UNITS = dict(fire=u_fire, ice=u_ice, energy=u_energy, earth=u_earth, death=u_death, holy=u_holy, physical=u_physical,
             arcane=u_arcane)


# ------------------------------------------------------------------------------------------------- the shapes
def _life(f, start, dur):
    return (f - start) / dur


def lay_single(cv, el, f, n, seed):
    gx, gy = anchor_of('single')
    unit = UNITS[el]
    sg = min(1.0, (f + 1) / 3)
    pres = 1.0 if f < n - 3 else max(0.0, 1.0 - (f - (n - 3)) / 2.0)
    sigil(cv, gx, gy, 23 * sg, f * 0.42, pres)
    unit(cv, gx - 15, gy + 3, 25, _life(f, 2.0, 7.0), seed + 1, f)
    unit(cv, gx + 15, gy + 3, 25, _life(f, 2.5, 7.0), seed + 2, f)
    unit(cv, gx, gy + 1, 40, _life(f, 1.0, 8.0), seed, f)


def lay_circle(cv, el, f, n, seed):
    gx, gy = anchor_of('circle')
    unit = UNITS[el]
    R = 62
    sg = min(1.0, (f + 1) / 5)
    pres = 1.0 if f < n - 3 else max(0.0, 1.0 - (f - (n - 3)) / 2.0)
    sigil(cv, gx, gy, 18 + (R - 18) * sg, f * 0.5, pres)
    items = [(gx, gy + 2, 50, 1.0, 0)]
    for i in range(2):
        a = i * math.pi + 0.9
        items.append((gx + math.cos(a) * R * 0.38, gy + math.sin(a) * R * 0.19 + 2, 28, 2.5 + (i % 2) * 0.8, i + 1))
    for i in range(6):
        a = i * 2 * math.pi / 6 + 0.15
        items.append((gx + math.cos(a) * R * 0.8, gy + math.sin(a) * R * 0.4 + 2, 33, 3.2 + (i % 3) * 0.9, i + 6))
    items.sort(key=lambda it: it[1])
    for x, y, s, start, k in items:
        unit(cv, x, y, s, _life(f, start, 6.5), seed + 10 + k, f)


def lay_around(cv, el, f, n, seed):
    gx, gy = anchor_of('around')
    unit = UNITS[el]
    sg = min(1.0, (f + 1) / 3)
    pres = 1.0 if f < n - 3 else max(0.0, 1.0 - (f - (n - 3)) / 2.0)
    spin = f * 0.34
    sigil(cv, gx, gy, 37 * sg, spin, pres)
    items = []
    for i in range(6):
        a = i * math.pi / 3 + f * 0.13
        items.append((gx + math.cos(a) * 28, gy + math.sin(a) * 14 + 3, 26, 1.0 + i * 0.7, i))
    items.sort(key=lambda it: it[1])
    for x, y, s, start, k in items:
        unit(cv, x, y, s, _life(f, start, 6.0), seed + 20 + k, f)


def lay_line(cv, el, f, n, seed, head='east'):
    """a beam running along `head` from the caster: the bodies stand on the line, the far ones first (the lower on screen is in front)"""
    gx, gy = anchor_of('line', head)
    unit = UNITS[el]
    pres = 1.0 if f < n - 3 else max(0.0, 1.0 - (f - (n - 3)) / 2.0)
    sigil(cv, gx, gy, 12 * min(1.0, (f + 1) / 3), f * 0.45, pres)
    front = min(1.0, f / (n - 5.0)) * 216
    if f < n - 2:                                            # a faint beam under the bodies, running to the front
        beam = p_poly([hp(head, gx, gy, 12, -4), hp(head, gx, gy, front, -3), hp(head, gx, gy, front, 3), hp(head, gx, gy, 12, 4)])
        cv.fill(beam, lo=HALO + 2, flat=True, alpha=GLOW)
    if f >= 5:
        ex, ey = hp(head, gx, gy, 216)
        sigil(cv, ex, ey, 12 * min(1.0, (f - 4) / 3), -f * 0.45, pres)
    items = []
    for i in range(7, 0, -1):
        x, y = hp(head, gx, gy, 28 * i + 4)
        items.append((x, y + 1, 36, 0.8 + i * 0.75, i))
    items.sort(key=lambda it: it[1])
    for x, y, s_, start, i in items:
        unit(cv, x, y, s_, _life(f, start, 5.2), seed + 30 + i, f)


def lay_wave(cv, el, f, n, seed, head='east'):
    """a fan running along `head`: a filled sector that opens to the full cone, its edges and arcs, the bodies of the element in it"""
    gx, gy = anchor_of('wave', head)
    unit = UNITS[el]
    pres = 1.0 if f < n - 3 else max(0.0, 1.0 - (f - (n - 3)) / 2.0)
    sigil(cv, gx, gy, 12 * min(1.0, (f + 1) / 3), f * 0.5, pres)
    A = 36
    rf = min(126.0, 20 + f * 15.0)                           # the front of the fan
    angs = [math.radians(-A + 7.2 * j) for j in range(11)]
    if f <= n - 3:
        top = [hp(head, gx, gy, math.cos(a) * rf, math.sin(a) * rf * 0.5) for a in angs]
        cv.fill(p_poly([hp(head, gx, gy, 6, -1), hp(head, gx, gy, 6, 1)] + top), lo=HALO + 1, flat=True, alpha=GLOW)
        for k in (0.35, 0.65):                               # arcs inside the fan
            pts = [hp(head, gx, gy, math.cos(a) * rf * k, math.sin(a) * rf * k * 0.5) for a in angs]
            cv.px(path_pts(pts), 13)
        for a in (angs[0], angs[-1]):                        # the two edges of the fan
            cv.px(line_pts(hp(head, gx, gy, 8, 0), hp(head, gx, gy, math.cos(a) * rf, math.sin(a) * rf * 0.5)), 17, glow=True)
        arc = path_pts(top)                                  # the front: a thick continuous crest
        cv.fill(p_grow(p_pts(arc), 1), lo=12, hi=20, K=2, edge=HALO + 3, glow=True)
    items = []
    for ri, (r, angles) in enumerate(((42, (-22, 0, 22)), (72, (-31, -15, 0, 15, 31)), (102, (-35, -18, 0, 18, 35)))):
        for ai, ad in enumerate(angles):
            a = math.radians(ad)
            x, y = hp(head, gx, gy, math.cos(a) * r, math.sin(a) * r * 0.5)
            items.append((x, y + 2, 24 + ri * 3, (r - 20) / 15.0 - 1.0, ri * 5 + ai))
    items.sort(key=lambda it: it[1])
    for x, y, s_, start, k in items:
        unit(cv, x, y, s_, _life(f, start, 5.2), seed + 40 + k, f)


LAYOUT = dict(single=lay_single, circle=lay_circle, around=lay_around, line=lay_line, wave=lay_wave)


def effect_frames(el, shape, seed, head='east'):
    s = dims(shape, head)
    W, H = s['w'] * 32, s['h'] * 32
    out = []
    for f in range(s['n']):
        cv = Cv(W, H, el)
        if head == 'east':
            LAYOUT[shape](cv, el, f, s['n'], seed)
        else:
            LAYOUT[shape](cv, el, f, s['n'], seed, head)
        out.append(cv.finish())
    return out


# ------------------------------------------------------------------------------------------------- missiles
def _vring(cv, hx, hy, f, bright=15):
    """the awakened mark of a missile: a small vertical ring round the head, dashes that turn"""
    pts = []
    for i in range(36):
        if (i + f * 9) % 12 < 8:
            a = 2 * math.pi * i / 36
            pts.append((hx + math.cos(a) * 3.2, hy + math.sin(a) * 8.5))
    cv.px(pts, bright, glow=True)


def m_fire(cv, f):
    hx, hy = 23, 16
    left, right = [], []
    for j in range(9):
        ty = j / 8
        yy = hy + math.sin(f * math.pi / 2 + ty * 6) * 2.2 * ty
        half = 4.2 * (1 - ty) ** 0.8
        left.append((hx - 3 - 16 * ty, yy - half))
        right.append((hx - 3 - 16 * ty, yy + half))
    cv.fill(p_poly(left + right[::-1]), lo=9, hi=16, K=3, edge=3, vg=(0, 0), glow=True)
    cv.fill(p_disc(hx, hy, 5), lo=10, hi=22, K=4, edge=4, glow=True)
    for i in range(3):
        q = ((f + i * 1.3) % 4) / 4
        cv.px([(hx - 6 - 14 * q, hy + (-3 + i * 3) + math.sin(q * 6 + i)), ], 20 - int(q * 8))


def m_ice(cv, f):
    hx = 27
    pts = [(hx, 16), (hx - 8, 11.2), (hx - 19, 12.5), (hx - 22, 16), (hx - 19, 19.5), (hx - 8, 20.8)]
    cv.fill(p_poly(pts), lo=8, hi=17, K=3, edge=2, vg=(3, -3), glow=True)
    cv.px(line_pts((hx - 21, 16), (hx - 1, 16)), 22)
    for i in range(5):
        q = ((f + i * 0.8) % 4) / 4
        cv.px([(hx - 22 - 6 * q - i * 1.5, 16 + (i - 2) * 2.4 + math.sin(q * 5 + i) * 1.5)], 21 - int(q * 6), size=2 if q < 0.4 else 1,
              glow=q < 0.4)


def m_energy(cv, f):
    hx, hy = 22, 16
    rnd = random.Random(500 + f)
    for k in range(3):
        a = (hx, hy)
        b = (hx - 15 - rnd.random() * 4, hy + (k - 1) * 4 + rnd.uniform(-1, 1))
        arc = path_pts(_disp(rnd, [a, b], 0.3, 2))
        cv.px(arc, 16 if k == 1 else 12, glow=True)
    cv.fill(p_disc(hx, hy, 4.6), lo=10, hi=22, K=3, edge=7, glow=True)
    cv.px([(hx - 1, hy - 1)], 23, size=2)


def m_earth(cv, f):
    hx, hy = 21, 16
    pts = []
    for k, a in enumerate((0, 1.1, 2.1, 3.3, 4.3, 5.4)):
        r = 6.2 * (0.8 + 0.3 * ((k * 5) % 3) / 2)
        pts.append((hx + math.cos(a + f * math.pi / 2) * r, hy + math.sin(a + f * math.pi / 2) * r))
    cv.fill(p_poly(pts), lo=7, hi=15, K=3, edge=1, lr=(hx, 2, -2))
    for i in range(3):
        q = ((f + i * 1.3) % 4) / 4
        cv.fill(p_disc(hx - 8 - 12 * q, hy + (i - 1) * 3.2, 2.6 - q * 1.2), lo=11, flat=True, alpha=GLOW)
    cv.px([(hx - 12, hy - 2), (hx - 15, hy + 3)], 14, size=2)


def m_death(cv, f):
    hx, hy = 23, 16
    pts = [(hx - 4 - 17 * j / 9, hy + math.sin(f * math.pi / 2 + j * 0.9) * 3 * j / 9) for j in range(10)]
    cv.fill(ribbon(pts, lambda tt: 0.8 + 3.8 * (1 - tt) ** 0.9), lo=5, hi=14, K=2, edge=1, glow=True)
    cv.fill(p_ell(hx, hy - 0.5, 5.2, 5), lo=13, hi=21, K=2, edge=5, glow=True)
    cv.fill(p_poly([(hx - 3, hy + 3), (hx + 3, hy + 3), (hx + 2.4, hy + 6.6), (hx - 2.4, hy + 6.6)]), lo=12, hi=18, K=1, edge=4)
    for e in (-1, 1):
        cv.fill(p_disc(hx + e * 2.2, hy - 0.4, 1.35), lo=0, flat=True)


def m_holy(cv, f):
    hx, hy = 23, 16
    for i in range(4):                                       # streaks of light behind
        L = 20 - i * 3
        cv.px(line_pts((hx - 5, hy + (i - 1.5) * 2.2), (hx - 5 - L, hy + (i - 1.5) * 2.6)), 12 + i * 2, glow=i == 1)
    r1, r2 = 9 + (f % 2), 7
    cv.fill(p_poly([(hx - r1, hy), (hx, hy - 2), (hx + r1, hy), (hx, hy + 2)]), lo=21, flat=True, glow=True)
    cv.fill(p_poly([(hx, hy - r2), (hx + 2, hy), (hx, hy + r2), (hx - 2, hy)]), lo=22, flat=True, glow=True)
    cv.fill(p_disc(hx, hy, 3.4), lo=16, hi=23, K=2, edge=9, glow=True)


def m_physical(cv, f):
    hx, hy = 21, 16
    a0 = f * math.pi / 2
    pts = [(hx + math.cos(a0 + math.radians(a)) * 7.5, hy + math.sin(a0 + math.radians(a)) * 7.5) for a in range(0, 211, 15)]
    cv.fill(ribbon(pts, lambda tt: max(0.7, 2.8 * math.sin(math.pi * min(1, max(0, tt))) ** 0.7)), lo=9, hi=22, K=2, edge=3,
            glow=True)
    for i in range(3):
        cv.px(line_pts((hx - 10 - i * 2, hy + (i - 1) * 4), (hx - 19 - i * 2, hy + (i - 1) * 4)), 8 + i * 2)


def m_arcane(cv, f):
    hx, hy = 22, 16
    for i in range(4):                                       # beads left behind
        cv.fill(p_disc(hx - 6 - i * 4, hy + math.sin(f * math.pi / 2 + i) * 2.5, 2.1 - i * 0.35), lo=17 - i * 3, flat=True,
                glow=i < 2)
    cv.fill(p_disc(hx, hy, 4.6), lo=7, hi=19, K=3, edge=2, glow=True)
    cv.fill(p_ell(hx, hy, 1.4, 3.4), lo=1, flat=True)
    cv.px([(hx - 1, hy - 1)], 22)
    for i in range(2):
        a = f * math.pi / 2 + i * math.pi
        cv.fill(p_disc(hx + math.cos(a) * 7, hy + math.sin(a) * 4.5, 1.6), lo=18, flat=True, glow=True)


MISSILE = dict(fire=m_fire, ice=m_ice, energy=m_energy, earth=m_earth, death=m_death, holy=m_holy, physical=m_physical,
               arcane=m_arcane)


def missile_frames(el):
    out = []
    for f in range(MISSILE_FRAMES):
        cv = Cv(32, 32, el)
        MISSILE[el](cv, f)
        _vring(cv, 23, 16, f)
        out.append(cv.finish())
    return out


# ------------------------------------------------------------------------------------------------- the table
def pieces():
    out = []
    slot = 0
    for ei, el in enumerate(ELEMENTS):
        for si, sh in enumerate(SHAPES):
            slot += 1
            s = SHAPE[sh]
            out.append(dict(kind='effect', slot=slot, name='af_%s_%s' % (el, sh), element=el, shape=sh, heading='east',
                            frames=s['n'], w=s['w'], h=s['h'], dx=s['dx'], dy=s['dy'], ms=MS, seed=101 + ei * 17 + si * 5,
                            note='awakened %s, %s' % (el, sh)))
    for ei, el in enumerate(ELEMENTS):                       # O711 headings, pair 77: after the 40 effects, element, shape, heading
        for si, sh in enumerate(HSHAPES):
            for hi, hd in enumerate(NEW_HEADINGS):
                slot += 1
                s = HSHAPE[(sh, hd)]
                out.append(dict(kind='effect', slot=slot, name='af_%s_%s_%s' % (el, sh, hd), element=el, shape=sh, heading=hd,
                                frames=s['n'], w=s['w'], h=s['h'], dx=s['dx'], dy=s['dy'], ms=MS,
                                seed=300 + ei * 17 + si * 5 + hi, note='awakened %s, %s heading %s' % (el, sh, hd)))
    for ei, el in enumerate(ELEMENTS):
        out.append(dict(kind='missile', slot=ei + 1, name='af_%s_proj' % el, element=el, shape='proj', heading='',
                        frames=MISSILE_FRAMES, w=1, h=1, dx=0, dy=0, ms=MS, seed=900 + ei,
                        note='awakened %s projectile, heading east; the 3 x 3 direction patterns come with the build step' % el))
    return out


def table_errors(rows):
    errs = []
    eff = [r for r in rows if r['kind'] == 'effect']
    mis = [r for r in rows if r['kind'] == 'missile']
    if len(eff) != KIT_EFFECTS + HEAD_EFFECTS:
        errs.append('%d effects, the kit is %d and %d with the headings' % (len(eff), KIT_EFFECTS, KIT_EFFECTS + HEAD_EFFECTS))
    if len(mis) != len(ELEMENTS):
        errs.append('%d missiles, the kit is %d' % (len(mis), len(ELEMENTS)))
    for grp in (eff, mis):
        if [int(r['slot']) for r in grp] != list(range(1, len(grp) + 1)):
            errs.append('slots are not 1.. in order')
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names) or any(not n.startswith('af_') for n in names):
        errs.append('names: not unique or not af_*')
    if len({int(r['seed']) for r in rows}) != len(rows):
        errs.append('two rows share a seed')
    want = {(e, s, 'east') for e in ELEMENTS for s in SHAPES} | {(e, s, h) for e in ELEMENTS for s in HSHAPES for h in NEW_HEADINGS}
    if {(r['element'], r['shape'], r['heading']) for r in eff} != want:
        errs.append('the effects are not every element times every shape, and a line and a wave times every heading')
    for r in eff:
        if not 10 <= int(r['frames']) <= 12:
            errs.append('%s: 10 to 12 frames' % r['name'])
        if r['heading'] not in HEADINGS or (r['heading'] != 'east' and r['shape'] not in HSHAPES):
            errs.append('%s: a heading is only for a line or a wave' % r['name'])
        if r['heading'] in ('north', 'south') and not (int(r['h']) > int(r['w']) if r['shape'] == 'line' else int(r['h']) >= int(r['w'])):
            errs.append('%s: a north or south strip is tall, not wide' % r['name'])
        if r['heading'] in ('east', 'west') and r['shape'] in HSHAPES and int(r['w']) <= int(r['h']):
            errs.append('%s: an east or west strip is wide, not tall' % r['name'])
        if not (0 <= int(r['dx']) < int(r['w']) and 0 <= int(r['dy']) < int(r['h'])):
            errs.append('%s: the send offset is not in the canvas' % r['name'])
    for r in mis:
        if (int(r['w']), int(r['h'])) != (1, 1) or int(r['frames']) != MISSILE_FRAMES:
            errs.append('%s: a missile is 1 x 1 with %d phases' % (r['name'], MISSILE_FRAMES))
    return errs


def strip_of(fr):
    import numpy as np
    return np.ascontiguousarray(np.concatenate(fr, axis=1))


def digest(strip):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


def draw_row(r):
    if r['kind'] == 'effect':
        return effect_frames(r['element'], r['shape'], int(r['seed']), r['heading'])
    return missile_frames(r['element'])


def build_rows():
    return [(r, strip_of(draw_row(r))) for r in pieces()]


def art_errors(strip, r):
    """the bar a strip is held to (the test and `check`): shape, alpha, palette, margins, a start and an end that close"""
    import numpy as np
    errs = []
    n = int(r['frames'])
    W, H = int(r['w']) * 32, int(r['h']) * 32
    if strip.shape != (H, W * n, 4):
        return ['%s: strip shape' % r['name']]
    if not set(np.unique(strip[..., 3]).tolist()) <= {0, GLOW, 255}:
        errs.append('%s: an alpha other than 0, %d, 255' % (r['name'], GLOW))
    if strip[strip[..., 3] == 0].any():
        errs.append('%s: a transparent pixel carries a colour' % r['name'])
    cols = {tuple(c) for c in strip[strip[..., 3] > 0][:, :3].tolist()}
    if not cols <= set(ramp(r['element'])):
        errs.append('%s: a colour outside the ramp of the element' % r['name'])
    counts = []
    prev = None
    for f in range(n):
        a = strip[:, f * W:(f + 1) * W]
        op = int((a[..., 3] > 0).sum())
        counts.append(op)
        if not op:
            errs.append('%s: frame %d is empty' % (r['name'], f))
        if r['kind'] == 'effect' and (a[0, :, 3].any() or a[-1, :, 3].any() or a[:, 0, 3].any() or a[:, -1, 3].any()):
            errs.append('%s: frame %d touches the edge of the canvas' % (r['name'], f))
        if prev is not None and (a == prev).all():
            errs.append('%s: frame %d equals the one before' % (r['name'], f))
        prev = a
    if r['kind'] == 'effect':
        if counts[-1] > 0.4 * max(counts):
            errs.append('%s: the last frame is not a fade (%d of a peak of %d pixels)' % (r['name'], counts[-1], max(counts)))
        if counts[0] > 0.6 * max(counts):
            errs.append('%s: the first frame is not a start (%d of a peak of %d pixels)' % (r['name'], counts[0], max(counts)))
    else:
        first, last = strip[:, :W], strip[:, (n - 1) * W:n * W]
        if (first == last).all():
            errs.append('%s: the last phase equals the first' % r['name'])
    return errs


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    e = sum(1 for r in rows if r['kind'] == 'effect')
    m = len(rows) - e
    w.writerow(dict(kind='total', slot=len(rows), name='effects_%d_missiles_%d' % (e, m),
                    note='O711: pair 76 holds the effect slots 1..%d and the missiles, pair 77 the heading slots %d..%d; the slot is the place in the kit' % (
                        KIT_EFFECTS, KIT_EFFECTS + 1, KIT_EFFECTS + HEAD_EFFECTS)))
    return buf.getvalue()


def sums_text(pairs):
    return ''.join('%s  %s\n' % (digest(s), r['name']) for r, s in pairs)


def read_spec():
    with open(SPEC, newline='') as fh:
        return [r for r in csv.DictReader(fh) if r['kind'] != 'total']


def read_total():
    with open(SPEC, newline='') as fh:
        return [int(r['slot']) for r in csv.DictReader(fh) if r['kind'] == 'total']


def read_sums():
    return dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))


def table():
    pairs = build_rows()
    errs = []
    for r, s in pairs:
        errs += art_errors(s, r)
    errs += table_errors(pieces())
    if errs:
        print('\n'.join(errs))
        return 1
    for p, t in ((SPEC, spec_text([r for r, _ in pairs])), (SUMS, sums_text(pairs))):
        open(p, 'w', newline='').write(t)
        print('wrote', os.path.relpath(p, os.path.join(HERE, '..', '..', '..')))
    return 0


def check(quiet=False):
    errs = table_errors(pieces())
    rows = read_spec() if os.path.exists(SPEC) else []
    if [[str(r[k]) for k in FIELDS] for r in pieces()] != [[r[k] for k in FIELDS] for r in rows]:
        errs.append('art_import/awakened_fx.csv is not the table of the script (run gen_awakened_fx.py table)')
    if not rows or read_total() != [len(rows)]:
        errs.append('awakened_fx.csv: the total row does not record the %d rows' % len(rows))
    try:
        import numpy  # noqa: F401
    except ImportError:
        print('awakened fx: numpy missing, the drawing is not checked against the sums')
    else:
        pairs = build_rows()
        for r, s in pairs:
            errs += art_errors(s, r)
        if not os.path.exists(SUMS) or open(SUMS).read() != sums_text(pairs):
            errs.append('awakened_fx.sums is not what the script draws (run gen_awakened_fx.py table after a wanted change)')
    bad = ids(True, quiet) if rows else 1
    if not quiet:
        for e in errs:
            print(e)
        print('awakened fx: %d effects %d..%d (%d of the headings from %d), %d missiles, %s' % (
            KIT_EFFECTS + HEAD_EFFECTS, FIRST, HEAD_FIRST + HEAD_EFFECTS - 1, HEAD_EFFECTS, HEAD_FIRST, len(ELEMENTS),
            'OK' if not errs and not bad else 'PROBLEMS'))
    return 1 if errs or bad else 0


# ------------------------------------------------------------------------------------------------- the pair
def effect_id(r):
    return FIRST + int(r['slot']) - 1


def missile_id(r):
    return MISSILE_IDS[int(r['slot']) - 1]


def stage_of(effects, missiles):
    """the pair a build makes from an input pair: 76 from pair 75 (the kit and the missiles), 77 from pair 76 (the headings), else None"""
    if missiles != NEED_MISSILES:
        return None
    if effects == NEED_EFFECTS:
        return PAIR
    if effects == NEED_EFFECTS + KIT_EFFECTS:
        return PAIR_HEADINGS
    return None


def pair_ok(effects, missiles):
    return stage_of(effects, missiles) is not None


def stage_rows(pairs, stage):
    """the rows a build to `stage` imports: pair 76 the east kit and the missiles, pair 77 only the heading effects"""
    if stage == PAIR:
        return [(r, s) for r, s in pairs if r['heading'] in ('east', '')]
    return [(r, s) for r, s in pairs if r['heading'] not in ('east', '')]


def missile_strip(east):
    """the east strip (32 x 32 * n, heading east) -> the 3 x 3 direction patterns of the client, each n frames left to right:
    (3 * 32, 3 * 32 * n, 4). Nearest-pixel turns about the middle of the tile, so no colour or alpha level is made; the middle
    cell repeats the south one (every pack missile does)."""
    import numpy as np
    n = east.shape[1] // 32
    out = np.zeros((96, 96 * n, 4), np.uint8)
    cells = {}
    for d, hd in DIRS.items():
        k = STEPS[hd]
        c, s = math.cos(k * math.pi / 4), math.sin(k * math.pi / 4)
        frames = []
        for f in range(n):
            a = east[:, f * 32:(f + 1) * 32]
            b = np.zeros((32, 32, 4), np.uint8)
            for y in range(32):
                for x in range(32):
                    rx, ry = x - 15.5, y - 15.5
                    sx = int(math.floor(rx * c + ry * s + 15.5 + 0.5))      # the inverse turn
                    sy = int(math.floor(-rx * s + ry * c + 15.5 + 0.5))
                    if 0 <= sx < 32 and 0 <= sy < 32:
                        b[y, x] = a[sy, sx]
            frames.append(b)
        cells[PATTERN[d]] = frames
    cells[(1, 1)] = cells[PATTERN['south']]
    for (px, py), fr in cells.items():
        for f, im in enumerate(fr):
            x0 = (px * n + f) * 32
            out[py * 32:(py + 1) * 32, x0:x0 + 32] = im
    out[out[..., 3] == 0] = 0
    return out


def import_spec(path, strips, pairs):
    """the spec import_fx_art.py reads: the 40 effects appended, then the 8 missiles at their ids (`replace`, `lua` names)"""
    import numpy as np
    from PIL import Image
    with open(path, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs', 'lua'])
        for r, s in pairs:
            f = os.path.join(strips, r['name'] + '.png')
            if r['kind'] == 'missile':
                s = missile_strip(s)
            Image.fromarray(np.ascontiguousarray(s)).save(f, optimize=False)
            if r['kind'] == 'effect':
                w.writerow(['', 'effect', r['name'], f, r['w'], r['h'], r['frames'], r['ms'], r['dx'], r['dy'], r['note'], 'soft',
                            '', ''])
            else:
                w.writerow([missile_id(r), 'missile', r['name'], f, 1, 1, r['frames'], 50, 0, 0, r['note'], 'soft', '', r['name']])


def build(dat, spr, out):
    sys.path.insert(0, HERE)
    from datspr import Dat
    d = Dat(dat)
    stage = stage_of(len(d.effects), len(d.missiles))
    if stage is None:
        sys.exit('refused: the input pair has %d effects and %d missiles, this step needs %d (pair 75, the footprints of O649) or '
                 '%d (pair 76, the kit) effects and exactly %d missiles' % (len(d.effects), len(d.missiles), NEED_EFFECTS,
                                                                           NEED_EFFECTS + KIT_EFFECTS, NEED_MISSILES))
    if stage == PAIR:
        for mid in BLANK_IDS:
            if any(d.missiles[mid - 1].sprites):
                sys.exit('refused: missile %d is not blank in the input pair' % mid)
    else:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            bad = live(dat, spr)
        if bad:
            sys.exit('refused: the input pair is not pair 76 of this kit (%s)' % buf.getvalue().strip().splitlines()[-1])
    if check(quiet=True):
        sys.exit('refused: `check` fails (the table, the sums or the ids file are not current)')
    pairs = stage_rows(build_rows(), stage)
    strips = os.path.join(os.path.abspath(out), 'strips')
    os.makedirs(strips, exist_ok=True)
    spec = os.path.join(strips, 'import.csv')
    import_spec(spec, strips, pairs)
    first = FIRST if stage == PAIR else HEAD_FIRST
    cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', dat, '--ours-spr', spr, '--out-dir', out,
           '--spec', spec, '--expect-first-effect', str(first), '--keep-donor-names']
    if subprocess.run(cmd).returncode:
        sys.exit('import_fx_art.py failed')
    for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv'):                # this step's ids come from the table
        p = os.path.join(out, f)
        if os.path.exists(p):
            os.remove(p)
    if stage == PAIR:
        print('awakened fx: %d effects %d..%d, 8 missiles at %s' % (KIT_EFFECTS, FIRST, FIRST + KIT_EFFECTS - 1, ' '.join(map(str, MISSILE_IDS))))
    else:
        print('awakened fx: %d heading effects %d..%d (pair %d)' % (HEAD_EFFECTS, HEAD_FIRST, HEAD_FIRST + HEAD_EFFECTS - 1, stage))
    return live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))


def live(dat_path, spr_path):
    """the pair holds every effect and missile at its id: size, phases and the pixels of the sums (a missile: the east cell
    is the sum, all nine cells are the turned strip)"""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_vfx import render_back
    from fxlib import render_frame
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_spec()
    sums = read_sums()
    errs = []
    if len(dat.effects) not in (NEED_EFFECTS + KIT_EFFECTS, NEED_EFFECTS + KIT_EFFECTS + HEAD_EFFECTS) or len(dat.missiles) != NEED_MISSILES:
        errs.append('the pair has %d effects and %d missiles' % (len(dat.effects), len(dat.missiles)))
    else:                                                    # pair 76 holds the kit, pair 77 the kit and the headings
        rows = [r for r in rows if r['kind'] != 'effect' or effect_id(r) <= len(dat.effects)]
    ne = sum(1 for r in rows if r['kind'] == 'effect')
    for r in rows if not errs else []:
        ph, w, h = int(r['frames']), int(r['w']), int(r['h'])
        if r['kind'] == 'effect':
            t = dat.effects[effect_id(r) - 1]
            if (t.w, t.h, t.phases) != (w, h, ph):
                errs.append('%s: size or phases differ at %d' % (r['name'], effect_id(r)))
                continue
            back = render_back(t, spr, 1)
            strip = np.concatenate([back[(f, 0, 0, 0)] for f in range(ph)], axis=1).copy()
            strip[strip[..., 3] == 0] = 0
            if digest(strip) != sums.get(r['name']):
                errs.append('%s: pixels differ from the sum' % r['name'])
        else:
            t = dat.missiles[missile_id(r) - 1]
            if (t.w, t.h, t.phases) != (1, 1, ph):
                errs.append('%s: size or phases differ at missile %d' % (r['name'], missile_id(r)))
                continue
            got = np.zeros((96, 96 * ph, 4), np.uint8)
            for py in range(3):
                for px in range(3):
                    for f in range(ph):
                        a = np.array(render_frame(t, spr, f, px, py))
                        a[a[..., 3] == 0] = 0
                        got[py * 32:(py + 1) * 32, (px * ph + f) * 32:(px * ph + f + 1) * 32] = a
            east = np.ascontiguousarray(got[32:64, 2 * ph * 32:3 * ph * 32])
            if digest(east) != sums.get(r['name']):
                errs.append('%s: the east pattern differs from the sum' % r['name'])
            elif not (got == missile_strip(east)).all():
                errs.append('%s: the nine patterns are not the turned east strip' % r['name'])
    for e in errs:
        print(e)
    print('awakened fx live: %d effects at %d..%d, %d missiles, %s' % (ne, FIRST, FIRST + ne - 1, len(rows) - ne,
                                                                      'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


# ------------------------------------------------------------------------------------------------- server files
def lua_text(rows):
    L = ['-- GENERATED by client/tools/sprites/gen_awakened_fx.py from art_import/awakened_fx.csv (O711). Do not edit by hand.',
         '-- The awakened spell look kit, drawn by code (our own art), in client pair %d: %d effects at the ids %d..%d, after the' % (
             PAIR, KIT_EFFECTS, FIRST, FIRST + KIT_EFFECTS - 1),
         '-- footprints of pair 75 (%d), and 8 projectiles. A projectile id is one byte on the wire (254 is the weapon-type' % (
             FIRST - 1),
         '-- constant, pair 75 holds 253), so none is appended: ids 43, 47, 52 were blank stock ids, 147-151 are donor ids no script',
         '-- sends, rebuilt in place (1 x 1 tiles, 4 phases, 3 x 3 direction patterns). dx, dy: the send offset; ms: the whole play.',
         '-- Headings: the line and the wave of the kit run east (heading = "east"); pair %d adds the %d effects %d..%d, a line and a' % (
             PAIR_HEADINGS, HEAD_EFFECTS, HEAD_FIRST, HEAD_FIRST + HEAD_EFFECTS - 1),
         '-- wave of each element heading north, south and west (af_ELEMENT_SHAPE_HEADING, heading = "north"|"south"|"west").',
         '-- A plain table: data/lib/chaos_awakened_fx.lua answers the kit when config.lua chaosClientPair is %d or more, the headings' % PAIR,
         '-- when it is %d or more.' % PAIR_HEADINGS,
         'ChaosAwakenedFxIds = {',
         '\tpair = %d, first = %d, count = %d,' % (PAIR, FIRST, KIT_EFFECTS),
         '\theadingPair = %d, headingFirst = %d, headingCount = %d,' % (PAIR_HEADINGS, HEAD_FIRST, HEAD_EFFECTS),
         '\teffects = {']
    for r in rows:
        if r['kind'] == 'effect':
            L.append('\t\t%s = {id = %d, dx = %s, dy = %s, ms = %d, element = "%s", shape = "%s", heading = "%s"},' % (
                r['name'], effect_id(r), r['dx'], r['dy'], int(r['ms']) * int(r['frames']), r['element'], r['shape'], r['heading']))
    L += ['\t},', '\tmissiles = {']
    for r in rows:
        if r['kind'] == 'missile':
            L.append('\t\t%s = {id = %d, dx = 0, dy = 0, element = "%s"},' % (r['name'], missile_id(r), r['element']))
    L += ['\t},', '}']
    return '\n'.join(L) + '\n'


def tags_text(rows):
    """spell_fx_elements.csv with the 88 effect rows of the kit and its headings (id, name, element) in id order, the other rows as they are
    (a missile id is no effect id, so the 8 projectiles carry no tag)"""
    with open(TAGS, encoding='utf-8', newline='') as fh:
        keep = [l for l in fh.read().splitlines() if not l.split(',')[1:2] or not l.split(',')[1].startswith('af_')]
    mine = ['%d,%s,%s' % (effect_id(r), r['name'], r['element']) for r in rows if r['kind'] == 'effect']
    return '\n'.join(keep[:1] + sorted(keep[1:] + mine, key=lambda l: int(l.split(',')[0]))) + '\n'


def ids(check_only, quiet=False):
    rows = read_spec()
    want = {LUA: lua_text(rows), TAGS: tags_text(rows)}
    if check_only:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            if not quiet:
                print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_awakened_fx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


# ------------------------------------------------------------------------------------------------- sheets and previews
GROUND = (26, 24, 31)


def flat(rgb, W, H):
    import numpy as np
    g = np.empty((H, W, 3), np.float64)
    g[:] = rgb
    return g


def over(dst, src, x=0, y=0):
    H, W = dst.shape[:2]
    h, w = src.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + w), min(H, y + h)
    if x0 >= x1 or y0 >= y1:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]
    a = s[..., 3:4].astype('float64') / 255.0
    dst[y0:y1, x0:x1] = dst[y0:y1, x0:x1] * (1 - a) + s[..., :3] * a


def upscale(img, k):
    import numpy as np
    return np.repeat(np.repeat(img, k, axis=0), k, axis=1)


def ground(W, H):
    """a plain dark ground with a faint tile grid"""
    g = flat(GROUND, W, H)
    g[::32, :] += 5
    g[:, ::32] += 5
    return g


def split(strip, n):
    W = strip.shape[1] // n
    return [strip[:, i * W:(i + 1) * W] for i in range(n)]


def sheets(out_dir):
    """sheet.png: every kit, one row an element, the peak frame of each shape and the missile; kit_ELEMENT.png: all frames"""
    import numpy as np
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    pairs = build_rows()
    by = {r['name']: (r, s) for r, s in pairs}
    written = []
    os.makedirs(os.path.join(out_dir, 'strips'), exist_ok=True)
    for r, s in pairs:                                       # the strips at 1x, as the quality check reads them
        Image.fromarray(s, 'RGBA').save(os.path.join(out_dir, 'strips', r['name'] + '.png'))
    cellw = {'single': 96, 'circle': 160, 'around': 96, 'line': 256, 'wave': 160, 'proj': 32}
    cellh = 160
    gap = 8
    cols = SHAPES + ['proj']
    SW = sum(cellw[c] for c in cols) + gap * (len(cols) + 1)
    rows_img = []
    for el in ELEMENTS:
        row = ground(SW, cellh + 2 * gap)
        x = gap
        for c in cols:
            name = 'af_%s_%s' % (el, c)
            r, s = by[name]
            fr = split(s, int(r['frames']))
            k = max(range(len(fr)), key=lambda i: int((fr[i][..., 3] > 0).sum())) if c != 'proj' else 1
            over(row, fr[k], x, gap + cellh - fr[k].shape[0])
            x += cellw[c] + gap
        rows_img.append(row)
        wide = flat(GROUND, max(1, 1), 1)
        allrows = []
        for c in cols:
            r, s = by['af_%s_%s' % (el, c)]
            fr = split(s, int(r['frames']))
            line = ground(fr[0].shape[1] * len(fr), fr[0].shape[0])
            for i, f in enumerate(fr):
                over(line, f, i * f.shape[1], 0)
            allrows.append(line)
        W = max(a.shape[1] for a in allrows)
        parts = []
        for a in allrows:
            pad = flat(GROUND, W, a.shape[0])
            pad[:, :a.shape[1]] = a
            parts.append(pad)
        p = os.path.join(out_dir, 'kit_%s.png' % el)
        Image.fromarray(upscale(np.concatenate(parts, 0).astype(np.uint8), 2), 'RGB').save(p)
        written.append(p)
    p = os.path.join(out_dir, 'sheet.png')
    Image.fromarray(upscale(np.concatenate(rows_img, 0).astype(np.uint8), 2), 'RGB').save(p)
    written.append(p)
    for p in written:
        print('wrote', p)
    heading_sheet(out_dir)
    return 0


def write_mp4(path, images, fps):
    import numpy as np
    h, w = images[0].shape[:2]
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (w, h),
           '-framerate', str(fps), '-i', '-', '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-crf', '30', '-an',
           '-movflags', '+faststart', path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for img in images:
        proc.stdin.write(np.ascontiguousarray(img).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit('ffmpeg failed for ' + path)


def scene(els, pairs_by, t_ms, k, label_rows=True):
    """one video picture: a row for each element in `els`, the five effects and the missile flying, at scale k"""
    import numpy as np
    cellw = {'single': 96, 'circle': 160, 'around': 96, 'line': 256, 'wave': 160, 'proj': 128}
    cols = SHAPES + ['proj']
    gap = 12
    rowh = 160 + gap
    SW = sum(cellw[c] for c in cols) + gap * (len(cols) + 1)
    SW += SW % 2
    img = ground(SW, rowh * len(els) + gap)
    for ri, el in enumerate(els):
        x = gap
        for c in cols:
            r, s = pairs_by['af_%s_%s' % (el, c)]
            n = int(r['frames'])
            fr = split(s, n)
            cyc = (n * MS + 480) if c != 'proj' else MISSILE_FRAMES * MS * 3
            ms = t_ms % cyc
            base_y = gap + ri * rowh + 160
            if c == 'proj':
                i = (ms // MS) % MISSILE_FRAMES
                px = x + int(ms / cyc * (cellw[c] + 20)) - 10 - 16
                over(img, fr[i], px, base_y - 80 - 16)
                if False:
                    pass
            else:
                i = ms // MS
                if i < n:
                    over(img, fr[i], x, base_y - fr[i].shape[0])
            x += cellw[c] + gap
    out = img.astype(np.uint8)
    out = upscale(out, k) if k > 1 else out
    h, w = out.shape[:2]
    return out[:h - h % 2, :w - w % 2]


def preview(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    pairs = build_rows()
    by = {r['name']: (r, s) for r, s in pairs}
    fps = 25
    step = 1000 // fps
    dur = 3600                                               # ms a view
    frames = [scene(ELEMENTS, by, t, 1) for t in range(0, dur, step)]
    p1 = os.path.join(out_dir, 'awakened_kits.mp4')
    write_mp4(p1, frames, fps)
    frames = []
    for i in range(0, len(ELEMENTS), 2):                     # 3x: two elements at a time
        for t in range(0, dur, step):
            frames.append(scene(ELEMENTS[i:i + 2], by, t, 3))
    p3 = os.path.join(out_dir, 'awakened_kits_3x.mp4')
    write_mp4(p3, frames, fps)
    for p in (p1, p3):
        print('wrote', p, os.path.getsize(p) // 1024, 'KiB')
    heading_preview(out_dir, pairs)
    return 0


# ------------------------------------------------------------------------------------------------- the headings
HEAD_VIEW = (15, 15)                                         # tiles of the compass picture
HEAD_ELEMENTS = ['fire', 'energy', 'holy']                   # the elements of the heading video


def head_row(by, el, shape, head):
    name = 'af_%s_%s' % (el, shape) + ('' if head == 'east' else '_' + head)
    return by[name]


def compass(by, el, shape, t_ms, k=2):
    """one picture: the shape of `el` cast from the middle tile in the four headings at once. Each canvas is placed the way the
    client places it: the tile the effect is sent on (the caster's tile moved by dx, dy) is the bottom right tile of the canvas."""
    import numpy as np
    vw, vh = HEAD_VIEW
    img = ground(vw * 32, vh * 32)
    cx, cy = vw // 2, vh // 2                                # the caster's tile
    img[cy * 32 + 8:cy * 32 + 24, cx * 32 + 12:cx * 32 + 20] = (150, 146, 156)   # a marker body on the caster's tile
    img[cy * 32 + 4:cy * 32 + 10, cx * 32 + 12:cx * 32 + 20] = (200, 190, 170)
    cyc = 11 * MS + 480
    f = (t_ms % cyc) // MS
    for head in HEADINGS:
        r, st = head_row(by, el, shape, head)
        n = int(r['frames'])
        if f >= n:
            continue
        w, h, dx, dy = int(r['w']), int(r['h']), int(r['dx']), int(r['dy'])
        fr = split(st, n)[f]
        over(img, fr, (cx - (w - 1 - dx)) * 32, (cy - (h - 1 - dy)) * 32)
    out = img.astype(np.uint8)
    return upscale(out, k) if k > 1 else out


def heading_sheet(out_dir):
    """headings.png: the peak frame of the line and the wave in the four headings, one row an element, compass pictures"""
    import numpy as np
    from PIL import Image
    pairs = build_rows()
    by = {r['name']: (r, s) for r, s in pairs}
    rows = []
    for el in ELEMENTS:
        parts = []
        for shape in HSHAPES:
            r0, s0 = head_row(by, el, shape, 'east')
            vw, vh = HEAD_VIEW
            img = ground(vw * 32, vh * 32)
            cx, cy = vw // 2, vh // 2
            for head in HEADINGS:
                r, st = head_row(by, el, shape, head)
                n = int(r['frames'])
                fr = split(st, n)
                k = max(range(n), key=lambda i: int((fr[i][..., 3] > 0).sum()))
                w, h, dx, dy = int(r['w']), int(r['h']), int(r['dx']), int(r['dy'])
                over(img, fr[k], (cx - (w - 1 - dx)) * 32, (cy - (h - 1 - dy)) * 32)
            parts.append(img)
        rows.append(np.concatenate(parts, 1))
    p = os.path.join(out_dir, 'headings.png')
    Image.fromarray(np.concatenate(rows, 0).astype(np.uint8), 'RGB').save(p)
    print('wrote', p)


def heading_preview(out_dir, pairs=None):
    pairs = pairs or build_rows()
    by = {r['name']: (r, s) for r, s in pairs}
    fps = 25
    step = 1000 // fps
    dur = 11 * MS + 480
    frames = []
    for el in HEAD_ELEMENTS:
        for shape in HSHAPES:
            for rep in range(2):
                for t in range(0, dur, step):
                    frames.append(compass(by, el, shape, t))
    p = os.path.join(out_dir, 'awakened_headings.mp4')
    write_mp4(p, frames, fps)
    print('wrote', p, os.path.getsize(p) // 1024, 'KiB')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['sheets', 'preview', 'build', 'table', 'ids', 'check', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'sheets':
        if len(a.rest) != 1:
            sys.exit('sheets OUT_DIR')
        return sheets(a.rest[0])
    if a.cmd == 'preview':
        if len(a.rest) != 1:
            sys.exit('preview OUT_DIR')
        return preview(a.rest[0])
    if a.cmd == 'build':
        if len(a.rest) != 3:
            sys.exit('build DAT SPR OUT_DIR')
        return build(*a.rest)
    if a.cmd == 'live':
        if len(a.rest) != 2:
            sys.exit('live DAT SPR')
        return live(*a.rest)
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'table':
        return table()
    return check()


if __name__ == '__main__':
    sys.exit(main())
