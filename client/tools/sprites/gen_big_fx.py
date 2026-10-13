#!/usr/bin/env python3
"""Large soft spell effects (5x5 to 9x9 tiles, 10-13 frames): telegraph circles, shockwave rings, novas, pillars,
a meteor, a lightning burst, a holy sanctum, a void rift and a blood geyser.

    python3 -I gen_big_fx.py build                  # -> art_import/big_fx/<name>.png + art_import/big_fx.csv
                                                    #    + art_import/big_fx.sums
    python3 -I gen_big_fx.py build --check          # render in memory; the spec, the sums and the strips on disk
                                                    #    (when they are there) must match
    python3 -I gen_big_fx.py stats                  # sprites and spr bytes the set adds to a pair
    python3 -I gen_big_fx.py preview --out DIR [--dat D --spr S]
                                                    # an animated GIF per effect on a sample tile area with a player
                                                    #    for scale (the player look comes from the pair D / S when
                                                    #    given) and one sheet of every effect frame by frame

Our own procedural art. Every frame is computed here as fields over the effect's area at 4x supersampling (numpy only:
radial gradients, value noise with fixed seeds, rings, glow, particles, jagged bolts, beams). No pixel of any other
game, client or reference sheet is read, traced, sampled or recoloured; no painting service is called. The colours are
the element ramps of item_forge_data/style.json (six luminance stops per element; arcane has its own ramp here) with
a hot tip towards white. A frame is an emissive glow field (colour by heat through the ramp, opacity rising with it)
over an optional dark smoke field; it is box-averaged down to the 32 px tile grid with premultiplied alpha and kept
SOFT: alpha 1..254 stays (the pair's spr has an alpha channel and the client blends it, like the animated pack effects
429-558 that import_vfx.py brought in). Pixels under alpha 12 are cut to 0 (no faint wash, and fewer stored pixels).
Deterministic: fixed seeds per effect, no Pillow drawing (Pillow only writes and reads the PNGs); made with Pillow
12.3.0 and numpy 2.5.3. The committed art_import/big_fx.sums holds the sha256 of every strip's decoded RGBA pixels
(PNG bytes depend on the zlib build), so CI checks a rebuild without the strips (they are made by `build`, git
ignores them).

Rules every strip is checked against (build stops otherwise): N x N tiles, N odd, 5..9; 10..13 frames; every frame
but the last has art; the last frame is empty; the outermost pixel ring of every frame is transparent (nothing touches
the frame's edge); the send offset is the centre tile (dx = dy = (N - 1) / 2: the art's centre tile is the target).
Appended to things_custom24 (effects 635-655) with import_fx_art.py --spec art_import/big_fx.csv --merge (the spec's
`alpha` column, soft, keeps the alpha levels). Server side: server/data/lib/chaos_big_fx.lua (which spell, boss
telegraph and use sends which effect, behind the switch ChaosBigFx.BIG_FX, on since 2026-10-13) and chaos_big_fx_ids.lua (written by import_fx_art.py).
"""
import argparse
import csv
import hashlib
import io
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'big_fx')
SPEC = os.path.join(ART, 'big_fx.csv')
SUMS = os.path.join(ART, 'big_fx.sums')
STYLE = os.path.join(HERE, 'item_forge_data', 'style.json')
SS = 4                    # supersampling: fields are computed on (N * 32 * SS)^2 points
ALPHA_CUT = 12            # stored alpha below this is cut to 0
TAU = 2 * math.pi
LEAN = 0.3 / 0.85         # the pair's oblique view: a point at height h is drawn 0.85 h up and 0.3 h left

# ------------------------------------------------------------------------------------------------------- colours
ARCANE = ['#101c3a', '#1b4a74', '#1f86a2', '#33c2c0', '#94f2de', '#eefff8']   # ours: teal arcane (no set ramp)
SMOKE = {'fire': (34, 22, 20), 'void': (14, 6, 24), 'blood': (40, 4, 8), 'poison': (16, 30, 14),
         'frost': (14, 26, 44), 'holy': (60, 44, 20), 'lightning': (14, 18, 40), 'arcane': (10, 24, 34)}


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def load_ramps():
    st = json.load(open(STYLE))['elements']
    src = {'fire': st['fire'], 'frost': st['ice'], 'lightning': st['lightning'], 'poison': st['poison'],
           'holy': st['holy'], 'void': st['void'], 'blood': st['blood'], 'arcane': ARCANE}
    ramps = {}
    for k, hexes in src.items():
        stops = [hex_rgb(h) for h in hexes]
        last = np.array(stops[-1], float)
        stops.append(tuple(last + (255 - last) * 0.75))           # the hot tip, towards white
        ramps[k] = np.array(stops, float)
    return ramps


RAMPS = load_ramps()


def ramp_rgb(element, t):
    """heat t (0..1) -> RGB through the element's stops"""
    stops = RAMPS[element]
    x = np.clip(t, 0, 1) * (len(stops) - 1)
    i = np.minimum(np.floor(x).astype(int), len(stops) - 2)
    f = (x - i)[..., None]
    return stops[i] * (1 - f) + stops[i + 1] * f


# ------------------------------------------------------------------------------------------------------- fields
def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def sstep(e0, e1, x):
    """scalar smoothstep"""
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def ring(r, R, w):
    return np.exp(-((r - R) / w) ** 2)


class Noise:
    """value noise on a seeded lattice (PCG64: the same numbers on every platform); periodic in x by `px` when given"""

    def __init__(self, seed, size=256):
        self.size = size
        self.tab = np.random.default_rng(seed).random((size, size))

    def __call__(self, x, y, px=None):
        n = self.size
        x0 = np.floor(x)
        y0 = np.floor(y)
        fx = x - x0
        fy = y - y0
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        ix = x0.astype(np.int64)
        iy = y0.astype(np.int64)
        mx = px if px else n
        ix0, ix1 = ix % mx, (ix + 1) % mx
        iy0, iy1 = iy % n, (iy + 1) % n
        t = self.tab
        a = t[iy0, ix0] * (1 - fx) + t[iy0, ix1] * fx
        b = t[iy1, ix0] * (1 - fx) + t[iy1, ix1] * fx
        return a * (1 - fy) + b * fy

    def fbm(self, x, y, octaves=3, px=None):
        s, amp, tot = 0.0, 1.0, 0.0
        for o in range(octaves):
            k = 2 ** o
            s = s + amp * self(x * k + 17.3 * o, y * k + 5.1 * o, px * k if px else None)
            tot += amp
            amp *= 0.5
        return s / tot


class Frame:
    """the fields of one frame: glow G (heat / opacity) and smoke D (dark, opacity), in tile units around the centre"""

    def __init__(self, n):
        self.n = n
        m = n * 32 * SS
        c = (n // 2) * 32 + 16                                   # the centre tile's centre, in 32 px pixels
        yy, xx = np.mgrid[0:m, 0:m]
        self.u = ((xx + 0.5) / SS - c) / 32.0                    # tile units, right
        self.v = ((yy + 0.5) / SS - c) / 32.0                    # tile units, down
        self.r = np.hypot(self.u, self.v)
        self.th = np.arctan2(self.v, self.u)
        self.G = np.zeros(self.u.shape)
        self.D = np.zeros(self.u.shape)
        self.half = n / 2.0

    def win(self, x, y, rad):
        """slices of the supersampled grid around tile point (x, y) within rad tiles"""
        m = self.u.shape[0]
        c = (self.n // 2) * 32 + 16
        x0 = int(max(0, math.floor(((x - rad) * 32 + c) * SS)))
        x1 = int(min(m, math.ceil(((x + rad) * 32 + c) * SS) + 1))
        y0 = int(max(0, math.floor(((y - rad) * 32 + c) * SS)))
        y1 = int(min(m, math.ceil(((y + rad) * 32 + c) * SS) + 1))
        if x0 >= x1 or y0 >= y1:
            return None
        return slice(y0, y1), slice(x0, x1)

    def blob(self, x, y, s, val, field='G'):
        """a gaussian dot of radius s tiles at (x, y), added"""
        w = self.win(x, y, s * 3)
        if w is None:
            return
        F = self.G if field == 'G' else self.D
        d2 = (self.u[w] - x) ** 2 + (self.v[w] - y) ** 2
        F[w] += val * np.exp(-d2 / (s * s))

    def segment(self, a, b, core, glow, val, field='G', glow_val=0.45):
        """a glowing line a-b: a hard-ish core of half width `core` and a soft glow of width `glow` (tiles), added"""
        ax, ay = a
        bx, by = b
        w = self.win((ax + bx) / 2, (ay + by) / 2, math.hypot(bx - ax, by - ay) / 2 + glow * 3)
        if w is None:
            return
        F = self.G if field == 'G' else self.D
        px, py = self.u[w] - ax, self.v[w] - ay
        dx, dy = bx - ax, by - ay
        L2 = max(dx * dx + dy * dy, 1e-12)
        t = np.clip((px * dx + py * dy) / L2, 0, 1)
        d = np.hypot(px - t * dx, py - t * dy)
        F[w] += val * (np.exp(-(d / core) ** 2) + glow_val * np.exp(-(d / glow) ** 2))

    def polyline(self, pts, core, glow, val, field='G', glow_val=0.45):
        for p, q in zip(pts[:-1], pts[1:]):
            self.segment(p, q, core, glow, val, field, glow_val)


def ease_out(t, k=2.2):
    return 1 - (1 - min(1.0, max(0.0, t))) ** k


def bell(t, peak, width):
    return math.exp(-((t - peak) / width) ** 2)


# --------------------------------------------------------------------------------------------------- the effects
# every function draws frame f of the effect into F; p = (f + 0.5) / (frames - 1) runs over 0..1 across the visible frames
# (the last frame of every strip is left empty), rng / nz are the effect's own seeded generators.

def telegraph(F, p, e, nz, rng):
    """a warning circle on the ground: a bright rim, a translucent fill, a timer ring that grows from the centre to
    the rim, tick marks turning slowly on the rim's inside, a dashed inner ring"""
    R = F.half - 0.38
    r, th = F.r, F.th
    fade = sstep(0.0, 0.12, p) * (1 - sstep(0.9, 1.0, p))
    pulse = 0.88 + 0.12 * math.cos(p * TAU * 2)
    inside = smooth(R + 0.05, R - 0.05, r)
    grain = 0.75 + 0.5 * nz(F.u * 3.0 + 40, F.v * 3.0 + 40)
    G = 1.15 * ring(r, R, 0.055) * pulse + 0.32 * ring(r, R, 0.24)
    G += inside * 0.17 * grain
    G += 0.75 * ring(r, max(0.15, R * p), 0.07) * inside
    K = 3 * F.n
    a = ((th + p * 0.5) / TAU * K) % 1.0
    G += 0.55 * ((a < 0.3) * ring(r, R - 0.32, 0.07))
    b = ((th - p * 0.8) / TAU * 2 * F.n) % 1.0
    G += 0.3 * ((b < 0.55) * ring(r, R * 0.56, 0.04))
    F.G += G * fade


def shockwave(F, p, e, nz, rng, sparks):
    """an expanding ring with a bright front, a tail inside, broken by angular noise; a flash at the start and sparks
    thrown out with the front"""
    Rm = F.half - 0.45
    Rf = 0.35 + (Rm - 0.35) * ease_out(p)
    w = 0.10 + 0.22 * p
    I = (1 - p) ** 1.1 * 1.25
    r, th = F.r, F.th
    k = 18 if e != 'frost' else 26
    brk = 0.45 + 0.85 * nz.fbm(th / TAU * k, r * 2.0 - p * 3.0, 2, px=k)
    tail = np.where(r < Rf, np.exp(-(Rf - r) / (w * 3.5)), np.exp(-((r - Rf) / (w * 0.7)) ** 2))
    G = I * (ring(r, Rf, w) * 1.1 + 0.45 * tail) * brk
    G += 0.18 * (1 - p) * smooth(Rf, Rf - 0.4, r)
    G += 1.7 * math.exp(-p * 6) * np.exp(-(r / 0.9) ** 2)
    if e == 'frost':                                          # ice spikes on the front
        spike = np.clip((nz(th / TAU * 40, 3.5, px=40) - 0.55) * 3.0, 0, 1)
        G += I * spike * smooth(Rf + 0.55, Rf, r) * smooth(Rf - 0.45, Rf, r) * 1.1
    if e == 'lightning':                                      # crackle on the front
        crack = np.clip((nz.fbm(th / TAU * 60, r * 8 + p * 20, 2, px=60) - 0.5) * 4.0, 0, 1)
        G += I * 1.2 * crack * ring(r, Rf, w * 2.2)
    if e == 'holy':                                           # rays
        ray = np.clip((nz(th / TAU * 24, 1.0, px=24) - 0.45) * 2.0, 0, 1)
        G += 0.6 * (1 - p) * ray * smooth(Rf + 0.3, 0.2, r)
    if e == 'blood':
        F.D += 0.35 * I * tail * brk
    for s in sparks:                                          # (angle, speed, size, value)
        ang, sp, sz, val = s
        rad = Rf * sp
        if rad > Rm + 0.2:
            continue
        F.blob(rad * math.cos(ang), rad * math.sin(ang), sz, val * (1 - p) ** 0.7)
    F.G += G


def nova(F, p, e, nz, rng, parts):
    """a burst that fills the circle: a core that gathers, then a front with radial streaks and a churning body that
    hollows out; embers fly out with it (void: the dark gathers in first, then it bursts)"""
    R = F.half - 0.45
    r, th = F.r, F.th
    gather = 0.22 if e != 'void' else 0.42
    if p < gather:
        q = p / gather
        F.G += (0.6 + 1.6 * q) * np.exp(-(r / (0.25 + 0.6 * q)) ** 2)
        if e == 'void':
            F.D += 0.85 * q * smooth(1.6 * (1 - q) + 0.6, 0.0, r)
            for ang0, sp, sz, val in parts:                   # motes drawn in along a spiral
                rad = R * (1 - q) * sp
                ang = ang0 + q * 2.0
                F.blob(rad * math.cos(ang), rad * math.sin(ang), sz, val * (0.4 + q))
            F.G += (0.35 + 0.5 * q) * ring(r, (R - 0.2) * (1 - q) + 0.35, 0.1 + 0.1 * q)
        else:
            F.G += 0.35 * q * ring(r, R * 0.5 * (1 - q) + 0.4, 0.15)
        return
    q = (p - gather) / (1 - gather)
    Rf = 0.4 + (R - 0.4) * ease_out(q, 2.6)
    I = (1 - q) ** 0.9
    k = {'fire': 20, 'frost': 28, 'poison': 14, 'holy': 32, 'void': 16, 'arcane': 24}[e]
    streak = 0.5 + 0.9 * nz.fbm(th / TAU * k, r * 1.2 - q * 2.5, 2, px=k)
    churn = 0.55 + 0.9 * nz.fbm(F.u * 1.6 + q * 1.5, F.v * 1.6 - q * 1.1, 3)
    body = smooth(Rf + 0.25, Rf - 0.35, r) * smooth(Rf * q * 0.95 - 0.3, Rf * q * 0.95 + 0.6, r)
    G = I * (1.25 * ring(r, Rf, 0.16 + 0.12 * q) * streak + 0.8 * body * churn * streak)
    G += 1.4 * (1 - q) ** 3 * np.exp(-(r / (0.6 + Rf * 0.4)) ** 2)
    if e == 'frost':
        spike = np.clip((nz(th / TAU * 36, 7.5, px=36) - 0.5) * 3.0, 0, 1)
        G += 0.9 * I * spike * smooth(Rf + 0.7, Rf, r) * smooth(Rf - 0.9, Rf - 0.1, r)
    if e == 'holy':
        ray = np.clip((nz(th / TAU * 16, 2.0, px=16) - 0.4) * 2.5, 0, 1)
        G += 0.7 * I * ray * smooth(Rf + 0.5, 0.0, r)
        G += 0.5 * I * (np.exp(-(F.u / 0.08) ** 2) + np.exp(-(F.v / 0.08) ** 2)) * smooth(Rf * 0.8, 0.0, r)
    if e == 'arcane':
        a = ((th + q * 1.2) / TAU * 18) % 1.0
        G += 0.7 * I * (a < 0.35) * ring(r, R * 0.62, 0.06) + 0.6 * I * ring(r, R * 0.62 + 0.18, 0.035)
    if e in ('fire', 'poison', 'void'):
        F.D += (0.35 if e != 'void' else 0.7) * I * body * churn
    for ang, sp, sz, val in parts:
        rad = Rf * sp * (1 + 0.25 * q)
        if rad > R + 0.1:
            continue
        F.blob(rad * math.cos(ang), rad * math.sin(ang), sz, val * (1 - q) ** 0.6)
    F.G += G


def beam_x(v):
    """the beam's centre line: straight up from the base, leaning left like every tall thing in the pair"""
    return LEAN * v                                            # v < 0 above the base -> left


def pillar(F, p, e, nz, rng, motes):
    """a column of light lands on the centre tile from above: a glyph ring on the ground, the beam (leaning like the
    pair's tall things), a flash at its foot and motes rising; then it thins out"""
    r, u, v = F.r, F.u, F.v
    top = -F.half + 0.1
    land = min(1.0, p / 0.22)
    front = top + (0.0 - top) * land                           # the beam's lower end comes down to the base
    width = 0.42 * (1 - sstep(0.6, 1.0, p)) + 0.04
    up = smooth(0.25, -0.1, v)                                  # the beam ends softly at its foot
    dx = u - beam_x(v)
    col = np.exp(-(dx / (width * 0.45)) ** 2) * 1.3 + 0.5 * np.exp(-(dx / (width * 1.3)) ** 2)
    flick = 0.8 + 0.4 * nz(dx * 3, v * 2.5 + p * 9)
    vis = up * smooth(front + 0.05, front - 0.2, v)            # from the top down to the beam's lower end so far
    G = col * flick * vis * smooth(top, top + 0.9, v)
    I = 1 - sstep(0.75, 1.0, p)
    G *= I
    hit = sstep(0.18, 0.26, p)
    gr = 1.25 + 0.35 * sstep(0.2, 0.6, p)
    G += hit * I * (1.0 * ring(r, gr, 0.06) + 0.5 * ring(r, gr - 0.28, 0.035) + 0.15 * smooth(gr, gr - 0.1, r))
    a = ((F.th - p * 1.5) / TAU * 12) % 1.0
    G += hit * I * 0.6 * (a < 0.3) * ring(r, gr - 0.14, 0.05)
    G += 1.8 * bell(p, 0.25, 0.08) * np.exp(-(r / 0.7) ** 2)
    for x0, y0, sz, val, sp in motes:                          # motes rise and lean
        y = y0 - sp * p * 2.2
        if y < top + 0.3:
            continue
        F.blob(x0 + LEAN * y, y, sz, val * hit * I)
    F.G += G


def meteor(F, p, e, nz, rng, debris, impact):
    """a burning rock falls in from the upper left with its trail, its shadow growing on the ground; then the impact:
    a flash, a fire ring, a churning blast and debris"""
    r, u, v = F.r, F.u, F.v
    if p < impact:
        q = p / impact
        sx, sy = -1.9, -F.half + 0.6
        hx, hy = sx * (1 - q) ** 1.3, sy * (1 - q) ** 1.3
        ang = math.atan2(-sy, -sx)
        tl = 0.6 + 1.3 * q
        tx, ty = hx - math.cos(ang) * tl, hy - math.sin(ang) * tl
        F.segment((tx, ty), (hx, hy), 0.10 + 0.08 * q, 0.35, 0.55)
        F.segment((tx - math.cos(ang) * 0.4, ty - math.sin(ang) * 0.4), (hx, hy), 0.2, 0.55, 0.22, field='D', glow_val=0.3)
        F.blob(hx, hy, 0.22 + 0.06 * q, 1.6)
        F.blob(hx, hy, 0.5, 0.35)
        flick = 0.6 + 0.8 * nz(u * 4 + q * 7, v * 4)
        F.G += 0.25 * (0.3 + q) * flick * ring(r, 1.35, 0.08) + 0.09 * (0.3 + q) * smooth(1.4, 1.2, r)
        F.D += 0.18 * q * smooth(1.2, 0.2, r)
        return
    q = (p - impact) / (1 - impact)
    R = F.half - 0.45
    Rf = 0.6 + (R - 0.6) * ease_out(q, 2.0)
    churn = 0.5 + 0.9 * nz.fbm(u * 1.8 + q * 2, v * 1.8 - q * 2, 3)
    I = (1 - q) ** 0.8
    G = 2.2 * (1 - q) ** 4 * np.exp(-(r / 1.4) ** 2)
    G += I * 1.2 * ring(r, Rf, 0.14 + 0.15 * q) * (0.5 + 0.8 * nz(F.th / TAU * 22, q * 3, px=22))
    G += I * 0.9 * smooth(Rf * 0.75, 0.0, r) * churn
    F.D += 0.5 * I * smooth(Rf * 0.85, 0.2, r) * churn
    for ang, sp, sz, val in debris:
        rad = 0.3 + Rf * sp
        if rad > R:
            continue
        F.blob(rad * math.cos(ang), rad * math.sin(ang) - 0.6 * math.sin(math.pi * q) * sp, sz, val * I)
    F.G += G


def bolt(rng, a, b, jag, step=0.22):
    """a jagged polyline from a to b"""
    ax, ay = a
    bx, by = b
    L = math.hypot(bx - ax, by - ay)
    n = max(2, int(L / step))
    nx, ny = -(by - ay) / max(L, 1e-9), (bx - ax) / max(L, 1e-9)
    pts = [a]
    off = 0.0
    for i in range(1, n):
        t = i / n
        off = off * 0.5 + rng.uniform(-jag, jag)
        env = math.sin(math.pi * t)
        pts.append((ax + (bx - ax) * t + nx * off * env, ay + (by - ay) * t + ny * off * env))
    pts.append(b)
    return pts


def lightning(F, p, e, nz, rng, f):
    """forked bolts burst from the centre (new ones every second frame), a bolt from the sky on the first frames, a
    white-hot core and a crackling ring"""
    R = F.half - 0.5
    r = F.r
    I = 1 - sstep(0.55, 1.0, p)
    br = np.random.default_rng(1000 + f // 2)
    nb = 6
    for i in range(nb):
        ang = (i + br.uniform(-0.3, 0.3)) / nb * TAU + 0.4
        L = R * br.uniform(0.7, 1.0) * (0.55 + 0.45 * ease_out(p * 2.5))
        end = (L * math.cos(ang), L * math.sin(ang))
        pts = bolt(br, (0.0, 0.0), end, 0.22)
        F.polyline(pts, 0.035, 0.16, 1.15 * I)
        for j in (len(pts) // 3, 2 * len(pts) // 3):
            if br.random() < 0.7:
                bang = ang + br.choice((-1, 1)) * br.uniform(0.4, 0.9)
                bl = L * br.uniform(0.25, 0.4)
                s = pts[j]
                F.polyline(bolt(br, s, (s[0] + bl * math.cos(bang), s[1] + bl * math.sin(bang)), 0.12), 0.025, 0.12,
                           0.8 * I)
    if p < 0.3:
        sky = (-0.25 + LEAN * (-F.half + 0.2), -F.half + 0.2)
        F.polyline(bolt(br, sky, (0.0, 0.0), 0.25), 0.05, 0.22, 1.4 * (1 - p / 0.3))
    F.G += 1.8 * I * np.exp(-(r / (0.35 + 0.25 * math.sin(p * 9) ** 2)) ** 2)
    crack = np.clip((nz.fbm(F.th / TAU * 50, r * 6 + f * 3.7, 2, px=50) - 0.5) * 4.0, 0, 1)
    Rr = 0.6 + (R - 0.4) * ease_out(p)
    F.G += 0.9 * I * crack * ring(r, Rr, 0.18) + 0.25 * I * ring(r, Rr, 0.06)


def sanctum(F, p, e, nz, rng, motes):
    """a holy circle on the ground: two rings, a turning hexagram, rune ticks between the rings, a soft light inside
    and motes rising"""
    R = F.half - 0.4
    r, th = F.r, F.th
    I = sstep(0.0, 0.18, p) * (1 - sstep(0.75, 1.0, p))
    pulse = 0.85 + 0.15 * math.sin(p * TAU * 1.5)
    G = 1.1 * ring(r, R, 0.05) + 0.8 * ring(r, R - 0.27, 0.04) + 0.25 * ring(r, R, 0.22)
    a = ((th - p * 0.9) / TAU * 20) % 1.0
    G += 0.75 * (a < 0.25) * ring(r, R - 0.135, 0.035)
    G += 0.16 * smooth(R, R - 0.1, r) * (0.8 + 0.4 * nz(F.u * 2.5, F.v * 2.5 + p * 2))
    rot = p * 0.7
    Rs = R - 0.33
    for k in range(2):
        pts = [(Rs * math.cos(rot + k * math.pi / 3 + j * TAU / 3 - math.pi / 2),
                Rs * math.sin(rot + k * math.pi / 3 + j * TAU / 3 - math.pi / 2)) for j in range(4)]
        F.polyline(pts, 0.028, 0.12, 0.7 * I * pulse, glow_val=0.35)
    F.G += 0.9 * I * np.exp(-(r / 0.5) ** 2) * pulse
    for x0, y0, sz, val, sp in motes:
        y = y0 - ((sp * p * 2.4) % 2.6)
        F.blob(x0 + LEAN * min(0, y), y, sz, val * I)
    F.G += G * I * pulse


def rift(F, p, e, nz, rng, parts):
    """a tear opens upright over the centre: a bright rim round a dark inside, spiral arms turning round it, motes
    drawn in; a faint ring on the ground; then it closes"""
    R = F.half - 0.45
    u, v, r, th = F.u, F.v, F.r, F.th
    o = sstep(0.0, 0.3, p) * (1 - sstep(0.72, 0.98, p))
    hh = 0.4 + 1.6 * o                                        # half height of the tear
    hw = 0.08 + 0.42 * o
    cy = -0.55                                                 # the tear stands a little above the ground point
    wob = 0.12 * (nz(v * 2.5 + p * 4, 3.3) - 0.5)
    ex = (u - LEAN * (v - cy) * 0.3 + wob) / hw
    ey = (v - cy) / hh
    q = np.hypot(ex, ey)
    rim = np.exp(-((q - 1) / 0.16) ** 2)
    F.G += 1.25 * o * rim * (0.6 + 0.6 * nz(np.arctan2(ey, ex) / TAU * 18, p * 5, px=18))
    F.D += 1.2 * o * smooth(1.0, 0.7, q)
    F.G += 0.35 * o * smooth(1.0, 0.0, q) * nz.fbm(u * 3 + p * 3, v * 3, 2)
    swirl = np.cos(3 * (th - np.log(r + 0.05) * 2.0 + p * 5.0))
    arms = np.clip(swirl, 0, 1) ** 3 * smooth(R, R * 0.55, r) * smooth(0.5, 1.2, r)
    F.G += 0.55 * o * arms * (0.6 + 0.6 * nz.fbm(th / TAU * 12, r * 2, 2, px=12))
    F.D += 0.25 * o * smooth(R, 0.6, r)
    F.G += 0.45 * o * ring(r, R - 0.05, 0.06)
    for ang0, rad0, sz, val in parts:
        rad = rad0 * (1 - ((p * 1.3 + rad0 * 0.2) % 1.0))
        ang = ang0 + (1 - rad / max(rad0, 1e-6)) * 2.2
        if rad < 0.3:
            continue
        F.blob(rad * math.cos(ang), rad * math.sin(ang) * 0.85 + cy * 0.3, sz, val * o)


def geyser(F, p, e, nz, rng, drops):
    """blood bursts up from the ground: a pool spreads, a spout rises (leaning like the pair's tall things) and
    falls back, droplets fly and splash"""
    u, v, r = F.u, F.v, F.r
    top = -F.half + 0.15
    rise = sstep(0.0, 0.35, p) * (1 - sstep(0.55, 0.9, p))
    H = 0.2 + (-top - 0.2) * rise
    poolR = 0.3 + 0.95 * sstep(0.0, 0.5, p)
    pool_fade = 1 - sstep(0.8, 1.0, p)
    edge = poolR * (0.85 + 0.3 * nz(F.th / TAU * 9, 1.3, px=9))
    pool = smooth(edge, edge - 0.15, r)
    F.D += 0.85 * pool * pool_fade
    F.G += 0.45 * pool * pool_fade * nz.fbm(u * 3, v * 3 + p, 2) + 0.35 * ring(r, edge, 0.06) * pool_fade
    hgt = -v                                                   # height above the base (screen up)
    dx = u - beam_x(v)
    w = 0.32 * (1 - 0.6 * np.clip(hgt / max(H, 0.1), 0, 1)) * (0.8 + 0.5 * rise)
    col = np.exp(-(dx / w) ** 2) * smooth(-0.25, 0.1, hgt) * smooth(H + 0.05, H - 0.25, hgt)
    churn = 0.6 + 0.8 * nz(dx * 4, v * 3 + p * 12)
    F.G += 1.2 * col * churn * (0.3 + 0.7 * rise)
    F.D += 0.5 * col * (0.3 + 0.7 * rise)
    g = 7.0
    for t0, vx, vy, sz, val in drops:                          # ballistic droplets (screen space)
        t = p - t0
        if t <= 0:
            continue
        x = vx * t
        y = -(vy * t - 0.5 * g * t * t)
        if y > 0.4 or y < top:
            continue
        F.blob(x + LEAN * y, y, sz, val * (1 - sstep(0.85, 1.0, p)))
        F.blob(x + LEAN * y, y, sz * 1.6, 0.4 * val, field='D')


# ------------------------------------------------------------------------------------------------------ the set
def _sparks(rng, n, smin=0.85, smax=1.2):
    return [(rng.uniform(0, TAU), rng.uniform(smin, smax), rng.uniform(0.04, 0.08), rng.uniform(0.5, 1.2))
            for _ in range(n)]


def _motes(rng, n, R):
    return [(rng.uniform(-R, R) * 0.8, rng.uniform(-0.2, 0.6), rng.uniform(0.04, 0.07), rng.uniform(0.6, 1.1),
             rng.uniform(0.7, 1.3)) for _ in range(n)]


# name, size, frames, ms, element, kind, note (spec order = id order)
EFFECTS = [
    ('big_telegraph_5', 5, 10, 100, 'blood', 'telegraph', 'boss warning circle, 5x5 (radius 2): a red rim, a translucent fill, a timer ring growing to the rim'),
    ('big_telegraph_7', 7, 10, 100, 'blood', 'telegraph', 'boss warning circle, 7x7 (radius 3)'),
    ('big_telegraph_9', 9, 10, 100, 'blood', 'telegraph', 'boss warning circle, 9x9 (radius 4)'),
    ('big_shock_fire_7', 7, 10, 70, 'fire', 'shockwave', 'fire shockwave ring, 7x7: a flash, a ragged front, sparks'),
    ('big_shock_frost_7', 7, 10, 70, 'frost', 'shockwave', 'frost shockwave ring, 7x7: ice spikes on the front'),
    ('big_shock_lightning_7', 7, 10, 70, 'lightning', 'shockwave', 'storm shockwave ring, 7x7: crackle on the front'),
    ('big_shock_holy_5', 5, 10, 70, 'holy', 'shockwave', 'golden shockwave ring, 5x5: rays behind the front'),
    ('big_shock_blood_9', 9, 10, 80, 'blood', 'shockwave', 'blood shockwave ring, 9x9: a dark red wave, spatter'),
    ('big_nova_fire_9', 9, 12, 70, 'fire', 'nova', 'fire nova, 9x9: a core gathers, a churning blast fills the circle, embers'),
    ('big_nova_frost_7', 7, 12, 70, 'frost', 'nova', 'frost nova, 7x7: a burst with ice spikes on its front'),
    ('big_nova_poison_7', 7, 12, 70, 'poison', 'nova', 'venom nova, 7x7: a churning green cloud bursts out'),
    ('big_nova_holy_7', 7, 12, 70, 'holy', 'nova', 'holy nova, 7x7: a burst of light with rays and a cross flare'),
    ('big_nova_void_7', 7, 13, 70, 'void', 'nova', 'void nova, 7x7: the dark and motes are drawn in, then it bursts'),
    ('big_nova_arcane_7', 7, 12, 70, 'arcane', 'nova', 'arcane nova, 7x7: a turning rune ring and a teal burst'),
    ('big_pillar_holy_5', 5, 12, 70, 'holy', 'pillar', 'pillar of light, 5x5: a beam lands on the target, a glyph ring, motes'),
    ('big_pillar_arcane_5', 5, 12, 70, 'arcane', 'pillar', 'arcane pillar, 5x5: a teal beam lands, a glyph ring, motes'),
    ('big_meteor_fire_7', 7, 13, 70, 'fire', 'meteor', 'meteor, 7x7: a burning rock falls in (8 frames), impact, fire ring, debris'),
    ('big_lightning_burst_7', 7, 10, 60, 'lightning', 'lightning', 'chain lightning burst, 7x7: forked bolts from the centre, a sky bolt'),
    ('big_sanctum_holy_5', 5, 12, 80, 'holy', 'sanctum', 'holy sanctum, 5x5: two rings, a turning hexagram, rune ticks, rising motes'),
    ('big_rift_void_7', 7, 13, 80, 'void', 'rift', 'void rift, 7x7: an upright tear opens, spiral arms turn, motes drawn in'),
    ('big_geyser_blood_5', 5, 12, 70, 'blood', 'geyser', 'blood geyser, 5x5: a pool spreads, a spout rises and falls, droplets'),
]
IMPACT = {'big_meteor_fire_7': 8}      # the impact frame (the server sends meteor_strike 660 ms before the damage)


def seed_of(name):
    return int(hashlib.sha256(name.encode()).hexdigest()[:8], 16)


def gain(e):
    """(glow heat gain, glow opacity gain) per element: dark elements stay deeper"""
    return {'void': (0.75, 1.6), 'blood': (0.8, 1.7)}.get(e, (0.85, 1.5))


def compose(F, element):
    """fields -> premultiplied RGBA at the supersampled size -> box average -> straight RGBA uint8 (32 px grid)"""
    G = np.maximum(F.G, 0)
    D = np.clip(F.D, 0, None)
    hk, ak = gain(element)
    t = 1 - np.exp(-G * hk)
    ag = 1 - np.exp(-G * ak)
    ad = (1 - np.exp(-D * 1.6)) * 0.85
    cg = ramp_rgb(element, t)
    cd = np.array(SMOKE[element], float)
    a = ag + ad * (1 - ag)
    pm = cg * ag[..., None] + cd * (ad * (1 - ag))[..., None]
    m = F.n * 32
    a = a.reshape(m, SS, m, SS).mean(axis=(1, 3))
    pm = pm.reshape(m, SS, m, SS, 3).mean(axis=(1, 3))
    rgb = np.where(a[..., None] > 1e-9, pm / np.maximum(a, 1e-9)[..., None], 0)
    A = np.rint(np.clip(a, 0, 1) * 255).astype(np.int64)
    A[A < ALPHA_CUT] = 0
    out = np.zeros((m, m, 4), np.uint8)
    out[..., :3] = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    out[..., 3] = A.astype(np.uint8)
    out[A == 0] = 0
    out[0, :] = out[-1, :] = 0                                  # nothing on the frame's edge
    out[:, 0] = out[:, -1] = 0
    return out


def frames_of(spec):
    name, n, nf, ms, e, kind, note = spec
    rng = np.random.default_rng(seed_of(name))
    nz = Noise(seed_of(name) ^ 0x5EED)
    R = n / 2.0 - 0.45
    extra = {
        'shockwave': lambda: (_sparks(rng, 26 if n < 9 else 40),),
        'nova': lambda: (_sparks(rng, 30 if n < 9 else 46, 0.5, 1.1),),
        'pillar': lambda: (_motes(rng, 14, R),),
        'sanctum': lambda: (_motes(rng, 16, R),),
        'meteor': lambda: (_sparks(rng, 24, 0.3, 1.0), IMPACT[name] / (nf - 1)),
        'rift': lambda: ([(rng.uniform(0, TAU), rng.uniform(1.4, R), rng.uniform(0.04, 0.07), rng.uniform(0.6, 1.1))
                          for _ in range(22)],),
        'geyser': lambda: ([(rng.uniform(0.15, 0.55), rng.uniform(-2.2, 2.2), rng.uniform(3.0, 5.0),
                             rng.uniform(0.04, 0.08), rng.uniform(0.6, 1.2)) for _ in range(26)],),
        'telegraph': lambda: (),
        'lightning': lambda: (),
    }[kind]()
    fn = {'telegraph': telegraph, 'shockwave': shockwave, 'nova': nova, 'pillar': pillar, 'meteor': meteor,
          'lightning': lightning, 'sanctum': sanctum, 'rift': rift, 'geyser': geyser}[kind]
    frames = []
    for f in range(nf - 1):
        F = Frame(n)
        p = (f + 0.5) / (nf - 1)                               # mid-frame time: never 0 or 1
        if kind == 'lightning':
            fn(F, p, e, nz, rng, f)
        else:
            fn(F, p, e, nz, rng, *extra)
        frames.append(compose(F, e))
    frames.append(np.zeros_like(frames[0]))
    return frames


def check(spec, frames):
    name, n, nf, ms, e, kind, note = spec
    errs = []
    if n % 2 != 1 or not 5 <= n <= 9:
        errs.append(f'{name}: size {n} not 5, 7 or 9')
    if not 10 <= nf <= 13 or len(frames) != nf:
        errs.append(f'{name}: {len(frames)} frames, want {nf} (10..13)')
    for i, fr in enumerate(frames):
        has = fr[:, :, 3].any()
        if i < nf - 1 and not has:
            errs.append(f'{name}: frame {i} empty')
        if i == nf - 1 and has:
            errs.append(f'{name}: last frame not empty')
        edge = np.concatenate([fr[0, :, 3], fr[-1, :, 3], fr[:, 0, 3], fr[:, -1, 3]])
        if edge.any():
            errs.append(f'{name}: frame {i} touches the edge')
    return errs


def strip_of(frames):
    return np.concatenate(frames, axis=1)


def digest(strip):
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


FIELDS = ['kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'alpha', 'note']


def spec_rows():
    return [dict(kind='effect', name=s[0], file=f'big_fx/{s[0]}.png', w=s[1], h=s[1], phases=s[2], ms=s[3],
                 dx=s[1] // 2, dy=s[1] // 2, alpha='soft', note=s[6]) for s in EFFECTS]


def spec_text():
    buf = io.StringIO()
    wr = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    wr.writeheader()
    wr.writerows(spec_rows())
    return buf.getvalue()


def read(path):
    return open(path, newline='').read() if os.path.exists(path) else None


def render_all(log=True):
    out = []
    for spec in EFFECTS:
        frames = frames_of(spec)
        out.append((spec, frames))
        if log:
            print(f'  {spec[0]}: {spec[1]}x{spec[1]}, {spec[2]} frames x {spec[3]} ms', flush=True)
    return out


def build(check_only=False):
    ok = True
    done = render_all()
    for spec, frames in done:
        for e in check(spec, frames):
            print('RULE', e)
            ok = False
    strips = [strip_of(fr) for _, fr in done]
    rows = spec_rows()
    spec = spec_text()
    sums = ''.join(f"{digest(s)}  {r['file']}\n" for r, s in zip(rows, strips))
    if check_only:
        if read(SPEC) != spec:
            print('DIFF', SPEC, '(run: gen_big_fx.py build)')
            ok = False
        if read(SUMS) != sums:
            print('DIFF', SUMS, '(run: gen_big_fx.py build)')
            ok = False
        for r, s in zip(rows, strips):
            p = os.path.join(ART, r['file'])
            if os.path.exists(p):
                have = np.asarray(Image.open(p).convert('RGBA'))
                if have.shape != s.shape or not np.array_equal(have, s):
                    print('DIFF', p)
                    ok = False
        print('big_fx check', 'ok' if ok else 'FAILED', f'({len(rows)} effects)')
        return ok
    if not ok:
        return False
    os.makedirs(OUT, exist_ok=True)
    for r, s in zip(rows, strips):
        Image.fromarray(s, 'RGBA').save(os.path.join(ART, r['file']), optimize=True)
    open(SPEC, 'w', newline='').write(spec)
    open(SUMS, 'w', newline='').write(sums)
    print('wrote', len(rows), 'strips to', OUT, '+', SPEC, '+', SUMS)
    return True


# ------------------------------------------------------------------------------------------------------ stats
def tiles_of(img, n):
    for y in range(n):
        for x in range(n):
            yield img[y * 32:(y + 1) * 32, x * 32:(x + 1) * 32]


def record_size(tile):
    """bytes of the spr record import_fx_art.py writes for a 32x32 tile (gen_effects.encode_sprite's layout), None
    for a transparent tile: 5 header bytes, then per run 4 bytes + 4 per coloured pixel, up to the last coloured one"""
    on = tile.reshape(1024, 4)[:, 3] > 0
    if not on.any():
        return None, None
    last = int(np.nonzero(on)[0][-1]) + 1
    o = on[:last].astype(np.int8)
    runs = int(((o[1:] == 1) & (o[:-1] == 0)).sum()) + int(o[0] == 1)
    return 5 + 4 * runs + 4 * int(on.sum()), hashlib.sha1(tile.tobytes()).digest()


def stats(done=None):
    done = done or render_all(log=False)
    tot_s = tot_b = 0
    seen = set()
    print(f"{'effect':24} {'size':>5} {'frames':>6} {'sprites':>7} {'bytes':>10} {'soft px':>8}")
    for spec, frames in done:
        n = spec[1]
        s = b = soft = 0
        for fr in frames:
            a = fr[:, :, 3]
            soft += int(((a > 0) & (a < 255)).sum())
            for t in tiles_of(fr, n):
                size, key = record_size(t)
                if size is None or key in seen:
                    continue
                seen.add(key)
                s += 1
                b += size + 4                                   # + its u32 in the offset table
        tot_s += s
        tot_b += b
        print(f'{spec[0]:24} {n}x{n:<3} {spec[2]:>6} {s:>7} {b:>10,} {soft:>8,}')
    print(f"{'total':24} {'':>5} {'':>6} {tot_s:>7} {tot_b:>10,}  ({tot_b / 2 ** 20:.1f} MiB added to Tibia.spr)")
    return tot_s, tot_b


# ------------------------------------------------------------------------------------------------------ preview
BG = (20, 18, 16, 255)
PLAYER_LOOK = 2073      # a player look of the pair for scale (the Warrior class look, gen_class_fx.LOOKS[4])


def ground(cols, rows):
    rng = np.random.default_rng(7)
    a = np.zeros((rows * 32, cols * 32, 4), np.int16)
    a[..., 3] = 255
    for y in range(rows):
        for x in range(cols):
            base = 52 + int(rng.integers(-5, 6))
            tile = np.empty((32, 32, 3), np.int16)
            tile[:] = (base, base - 6, base - 12)
            tile += rng.integers(-6, 7, (32, 32))[:, :, None]
            tile[0, :] -= 14
            tile[:, 0] -= 14
            a[y * 32:(y + 1) * 32, x * 32:(x + 1) * 32, :3] = tile
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA')


def player_image(dat, spr):
    if dat is not None:
        try:
            sys.path.insert(0, HERE)
            from datspr import render_outfit
            im = render_outfit(dat, spr, PLAYER_LOOK, direction='south', layers='base')
            if im is not None:
                return im
        except Exception as ex:                                  # a pair without the look: the stand-in below
            print('player look not drawn:', ex)
    im = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    a = np.zeros((32, 32, 4), np.uint8)
    yy, xx = np.mgrid[0:32, 0:32]
    body = ((xx - 14) / 6.5) ** 2 + ((yy - 18) / 11) ** 2 <= 1
    head = ((xx - 14) / 4.5) ** 2 + ((yy - 7) / 4.5) ** 2 <= 1
    a[body] = (70, 80, 110, 255)
    a[head] = (200, 170, 140, 255)
    im = Image.fromarray(a, 'RGBA')
    return im


def place(canvas, img, tx, ty, ox=0, oy=0):
    """the client's rule: the art's bottom-right tile on the map tile (tx, ty)"""
    canvas.alpha_composite(img, (tx * 32 + 32 - img.width + ox, ty * 32 + 32 - img.height + oy))


def preview(out, dat_path=None, spr_path=None):
    from PIL import ImageDraw, ImageFont
    font = ImageFont.load_default()
    os.makedirs(out, exist_ok=True)
    dat = spr = None
    if dat_path and spr_path:
        sys.path.insert(0, HERE)
        from datspr import Dat, Spr
        dat, spr = Dat(dat_path), Spr(spr_path)
    player = player_image(dat, spr)
    done = render_all(log=False)
    cols = rows = 11
    scale = 2
    stills = []
    for spec, frames in done:
        name, n, nf, ms = spec[:4]
        ctr = (cols // 2, rows // 2)
        pics = []
        for fr in frames + [frames[-1]] * 3:                    # a short pause between loops
            img = ground(cols, rows)
            place(img, player, ctr[0], ctr[1] + 0)              # the player stands on the target tile
            place(img, player, ctr[0] - 3, ctr[1] + 1)           # and one three tiles away
            place(img, Image.fromarray(fr, 'RGBA'), ctr[0] + n // 2, ctr[1] + n // 2)
            big = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
            panel = Image.new('RGBA', (big.width, big.height + 16), (12, 12, 16, 255))
            panel.alpha_composite(big, (0, 16))
            ImageDraw.Draw(panel).text((4, 2), f'{name}  {n}x{n}  {nf} x {ms} ms', fill=(255, 220, 120, 255),
                                       font=font)
            pics.append(panel.convert('RGB'))
        pics[0].save(os.path.join(out, name + '.gif'), save_all=True, append_images=pics[1:],
                     duration=[ms] * nf + [ms] * 3, loop=0, disposal=1)
        stills.append((spec, frames))
    # the sheet: every frame of every effect over the ground, one row per effect (scale 1)
    rowh = [s[1] * 32 + 14 for s, _ in stills]
    W = max(s[2] * (s[1] * 32 + 4) for s, _ in stills) + 4
    sheet = Image.new('RGBA', (W, sum(rowh) + 4), (12, 12, 16, 255))
    y = 2
    d = ImageDraw.Draw(sheet)
    for (spec, frames), h in zip(stills, rowh):
        n = spec[1]
        d.text((4, y), f'{spec[0]} {n}x{n} {spec[2]}x{spec[3]}ms ({spec[4]})', fill=(255, 220, 120, 255), font=font)
        for i, fr in enumerate(frames):
            g = ground(n, n)
            place(g, player, n // 2, n // 2)
            g.alpha_composite(Image.fromarray(fr, 'RGBA'))
            sheet.alpha_composite(g, (4 + i * (n * 32 + 4), y + 12))
        y += h
    sheet.convert('RGB').save(os.path.join(out, 'big_fx_sheet.png'))
    print('previews in', out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--check', action='store_true')
    sub.add_parser('stats')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    p.add_argument('--dat')
    p.add_argument('--spr')
    a = ap.parse_args()
    if a.cmd == 'build':
        sys.exit(0 if build(a.check) else 1)
    if a.cmd == 'stats':
        stats()
        return
    preview(a.out, a.dat, a.spr)


if __name__ == '__main__':
    main()
