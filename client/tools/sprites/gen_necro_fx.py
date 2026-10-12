#!/usr/bin/env python3
"""The Necromancer line's own spell effects in the approved style sample (shape in Python, one PixelLab repaint of the
whole sheet, re-centred on the tile).

    python3 -I gen_necro_fx.py shapes                 # -> art_import/necro_fx_src/sheet_shape.png
    python3 -I gen_necro_fx.py paint [--seed N]       # one PixelLab "Edit images (Pro)" call over that sheet
                                                      #    -> art_import/necro_fx_src/sheet_paint_<seed>.png (logs the balance)
    python3 -I gen_necro_fx.py build [--paint FILE]   # -> art_import/necro_fx/<name>.png (frame strips, fx spec necro_fx.csv)

Only `build` is needed to rebuild the art: it reads the checked-in shape and painting (default: the painting named in
PAINT below) and is deterministic. `shapes` is deterministic too (fixed seeds); `paint` costs generations.

Where the art comes from (client/tools/sprites/art_import/necro_fx.csv is the importer spec, one row per effect):
  - Most of the line's effects are effects already in the pair (pack and procedural effects: necro_seal, cursed,
    toxic_burst, px633_green, px448_green, px633_indigo, heal_sparkle, the skull orb...). The donor libraries were
    surveyed first (server/data/spells/README_FX.md "Necromancer line effects"); only the bone effects had no fitting donor.
  - The Bone Lord's bone effects and the bone spear impact are drawn here: each frame is a shape built from discs,
    capsules, triangles and rings on a 4x supersample, quantised per material to hard ramps (dark violet / green / ash
    outline), in the oblique view (a point at height h is drawn h/1.5 up and h/1.5 left; the target tile is the frame's
    bottom-right tile). The sheet of all their frames went through one PixelLab "Edit images (Pro)" call (PROMPT below);
    `build` cuts the painting, moves every effect back onto its shape (the shift with the best silhouette overlap),
    keeps only the painted pixels near the shape (no bleed from the neighbouring cells), hard alpha, and checks that
    nothing touches the frame's edge.
  - lich_soul_drain is the owner-approved style sample itself (necro_fx_src/soul_drain.png, frames unchanged; its
    shape script and repaint call are necro_fx_src/soul_drain_shape.py / soul_drain_paint.py).
No pixel of any other game or of the owner's style reference sheets is used.
"""
import argparse
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'art_import', 'necro_fx_src')
OUT = os.path.join(HERE, 'art_import', 'necro_fx')
PAINT = 'sheet_paint.png'           # the picked painting (copied from sheet_paint_<seed>.png)
SS = 4

RAMPS = {   # dark -> light; [0] is the outline
    'ash': [(26, 22, 24), (62, 56, 54), (98, 90, 84), (136, 126, 116)],
    'void': [(34, 10, 58), (70, 24, 118), (118, 52, 190), (170, 104, 240), (222, 186, 255)],
    'bone': [(40, 30, 40), (112, 100, 104), (168, 158, 148), (210, 202, 184), (240, 234, 216)],
    'shade': [(16, 10, 20), (40, 30, 46), (58, 46, 62)],
    'soul': [(12, 44, 24), (34, 104, 48), (78, 180, 70), (150, 234, 104), (220, 255, 182)],
    'core': [(70, 24, 118), (182, 140, 250), (236, 222, 255), (255, 255, 255)],
}
ORDER = ['ash', 'void', 'bone', 'shade', 'soul', 'core']          # later wins where both cover


def scr(c, h):
    """ground point c=(x, y) at height h -> screen."""
    return np.array((c[0] - h / 1.5, c[1] - h / 1.5))


def pol(c, r, a):
    return np.array((c[0] + r * math.cos(a), c[1] + r * math.sin(a)))


class Canvas:
    def __init__(self, n):
        self.n = n
        m = n * SS
        yy, xx = np.mgrid[0:m, 0:m]
        self.X = (xx + 0.5) / SS
        self.Y = (yy + 0.5) / SS
        self.I = {k: np.zeros((m, m)) for k in ORDER}

    def put(self, mat, inside, val):
        self.I[mat] = np.where(inside, np.maximum(self.I[mat], val), self.I[mat])

    def disc(self, mat, c, r, lo=0.35, hi=1.0, lit=0.35):
        dx, dy = self.X - c[0], self.Y - c[1]
        d = np.hypot(dx, dy)
        rel = np.clip(1 - d / max(r, 1e-6), 0, 1)
        tl = np.clip((-dx - dy) / (r * 1.414 + 1e-6), -1, 1)
        self.put(mat, d <= r, lo + (hi - lo) * rel + lit * tl * 0.5)

    def capsule(self, mat, a, b, ra, rb, lo=0.3, hi=0.9):
        a, b = np.asarray(a, float), np.asarray(b, float)
        ab = b - a
        L2 = max(ab @ ab, 1e-9)
        t = np.clip(((self.X - a[0]) * ab[0] + (self.Y - a[1]) * ab[1]) / L2, 0, 1)
        d = np.hypot(self.X - (a[0] + t * ab[0]), self.Y - (a[1] + t * ab[1]))
        r = ra + (rb - ra) * t
        self.put(mat, d <= r, lo + (hi - lo) * (1 - t) * np.clip(1 - d / np.maximum(r, 1e-6), 0, 1) + 0.1)

    def tri(self, mat, a, b, c, lo=0.35, hi=0.95):
        """filled triangle, lit along the a->(b,c) axis: a (the tip) brightest"""
        P = [np.asarray(p, float) for p in (a, b, c)]
        s = []
        for i in range(3):
            p, q = P[i], P[(i + 1) % 3]
            s.append((q[0] - p[0]) * (self.Y - p[1]) - (q[1] - p[1]) * (self.X - p[0]))
        inside = ((s[0] >= 0) & (s[1] >= 0) & (s[2] >= 0)) | ((s[0] <= 0) & (s[1] <= 0) & (s[2] <= 0))
        base = (P[1] + P[2]) / 2
        ax = P[0] - base
        L2 = max(ax @ ax, 1e-9)
        t = np.clip(((self.X - base[0]) * ax[0] + (self.Y - base[1]) * ax[1]) / L2, 0, 1)
        # left half (towards the light, up-left) lighter
        side = np.sign((self.X - base[0]) * -ax[1] + (self.Y - base[1]) * ax[0])
        self.put(mat, inside, lo + (hi - lo) * t * 0.7 + 0.12 * side * (1 if ax[1] <= 0 else -1) + 0.15)

    def ring(self, mat, c, R, w, start=0.0, span=2 * math.pi, val=0.75):
        dx, dy = self.X - c[0], self.Y - c[1]
        d = np.hypot(dx, dy)
        ang = (np.arctan2(dy, dx) - start) % (2 * math.pi)
        tl = np.clip((-dx - dy) / (R * 1.414), -1, 1)
        self.put(mat, (np.abs(d - R) <= w / 2) & (ang <= span), val + 0.18 * tl)

    def spark(self, mat, c, s, val=1.0):
        for dx, dy in ((1, 0), (0, 1)):
            self.capsule(mat, c - np.array((dx, dy)) * s, c + np.array((dx, dy)) * s, 0.45, 0.45, val, val)
        self.disc(mat, c, 0.8, val, val, 0)

    def bone(self, a, b, r=1.0, val=1.0):
        """a long bone: shaft + two knobs at each end"""
        a, b = np.asarray(a, float), np.asarray(b, float)
        u = (b - a) / max(np.linalg.norm(b - a), 1e-6)
        v = np.array((-u[1], u[0]))
        self.capsule('bone', a, b, r * 0.8, r * 0.8, 0.45 * val, 0.95 * val)
        for e in (a, b):
            for s in (-1, 1):
                self.disc('bone', e + v * s * r * 0.75, r * 0.85, 0.45 * val, 0.95 * val, 0.4)

    def skull(self, c, s, val=1.0, eyes='soul'):
        c = np.asarray(c, float)
        self.disc('bone', c, 5.0 * s, 0.35 * val, 1.0 * val, 0.5)
        self.capsule('bone', c + (0, 3.2 * s), c + (0, 5.2 * s), 3.0 * s, 2.4 * s, 0.3 * val, 0.7 * val)
        for sx in (-1, 1):
            self.disc('shade', c + (sx * 1.9 * s, 1.0 * s), max(1.45 * s, 1.3), 0.2, 0.4, 0.0)
            if eyes != 'ash':
                self.disc(eyes, c + (sx * 1.9 * s, 1.0 * s), max(0.8 * s, 0.8), 0.75, 1.0, 0.0)
        self.disc('shade', c + (0, 3.4 * s), max(0.7 * s, 0.7), 0.2, 0.3, 0)

    def finish(self):
        """-> n x n RGBA: per pixel the top material covering >= 40% of it, its mean value on a ramp, outlined."""
        N = self.n
        out = np.zeros((N, N, 4), np.uint8)
        owner = np.full((N, N), -1)
        value = np.zeros((N, N))
        for mi, m in enumerate(ORDER):
            I = self.I[m].reshape(N, SS, N, SS)
            cov = (I > 0).mean((1, 3))
            mean = I.sum((1, 3)) / np.maximum((I > 0).sum((1, 3)), 1)
            on = cov >= 0.4
            owner[on] = mi
            value[on] = mean[on]
        for mi, m in enumerate(ORDER):
            R = np.array(RAMPS[m], np.uint8)
            sel = owner == mi
            k = np.clip(1 + np.floor(value * (len(R) - 1)).astype(int), 1, len(R) - 1)
            out[sel, :3] = R[k[sel]]
            out[sel, 3] = 255
        on = owner >= 0
        P = np.pad(on, 1)
        ring = ~on & (P[2:, 1:-1] | P[:-2, 1:-1] | P[1:-1, 2:] | P[1:-1, :-2])
        Po = np.pad(owner, 1, constant_values=-1)
        for dy, dx in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            q = Po[1 + dy:N + 1 + dy, 1 + dx:N + 1 + dx]
            for mi, m in enumerate(ORDER):
                s = ring & (q == mi) & (out[..., 3] == 0)
                out[s, :3] = RAMPS[m][0]
                out[s, 3] = 255
        return out


# ------------------------------------------------------------------------------------------------ the effects
C64 = np.array((48.0, 48.0))           # the target tile's centre on the ground (64 px frame, target = bottom-right tile)


def sparks(cv, rng, n, c, rmin, rmax, mats=('soul', 'core')):
    for _ in range(n):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(rmin, rmax)
        p = np.round(pol(c, r, a)) + 0.5
        cv.spark(mats[0] if rng.random() < 0.5 else mats[1], p, 1.0 + (rng.random() < 0.35), 0.95)


def spear_hit(t, rng):
    """the bone spear strikes: a violet snap, six bone splinters thrown out and falling, green motes (7 frames)"""
    cv = Canvas(64)
    P = scr(C64, 10)
    angs = [i * math.pi / 3 + 0.35 for i in range(6)]
    if t == 0:
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            cv.capsule('void', P, pol(P, 7.5, a), 1.6, 0.3, 0.6, 0.95)
        cv.disc('core', P, 2.6, 0.5, 1.0, 0.3)
        cv.ring('soul', P, 4.5, 1.0, val=0.6)
    if t == 1:
        cv.ring('void', P, 7.0, 2.0, val=0.7)
        cv.disc('soul', P, 3.6, 0.45, 0.95, 0.4)
        cv.disc('core', P, 2.0, 0.6, 1.0, 0.2)
    if 1 <= t <= 4:
        r = (6.0, 10.0, 12.5, 14.0)[t - 1]
        drop = (0.0, 0.6, 2.4, 5.0)[t - 1]
        for i, a in enumerate(angs):
            p = pol(P, r, a) + (0, drop)
            u = np.array((math.cos(a + 0.4 * t), math.sin(a + 0.4 * t)))
            ln = 2.8 if i % 2 else 2.2
            cv.bone(p - u * ln, p + u * ln, 0.85, 1.0 - 0.1 * (t - 1))
    if t == 2:
        for k in range(5):
            cv.ring('void', P, 10.0, 1.4, start=k * 1.26 + 0.2, span=0.75, val=0.6)
    if t == 3:
        for k in range(4):
            cv.ring('void', P, 12.0, 1.0, start=k * 1.57 + 0.6, span=0.5, val=0.45)
    if t == 5:
        for i, a in enumerate(angs[::2]):
            p = pol(C64, 9 + 2 * i, a + 0.5)
            cv.bone(p - (1.8, 0.6), p + (1.8, 0.6), 0.7, 0.75)
    if t == 6:
        p = pol(C64, 10, angs[1])
        cv.capsule('bone', p - (1.2, 0), p + (1.2, 0), 0.6, 0.6, 0.4, 0.6)
    sparks(cv, rng, (0, 3, 4, 4, 3, 2, 2)[t], P, 4, 12 + t)
    return cv.finish()


def golem_rise(t, rng):
    """the Bone Golem rises: the ground cracks, a ring of bone spikes erupts and closes into a ribcage, a skull with
    green eyes flares at its top, the spikes sink back (8 frames)"""
    cv = Canvas(64)
    n = 7
    base = [pol(C64, 11.0, i * 2 * math.pi / n + 0.2) for i in range(n)]
    apex = scr(C64, 14)
    if t <= 2:
        for i in range(9):
            a = i * 2 * math.pi / 9 + 0.1
            ln = (6, 10, 12)[t]
            cv.capsule('ash', pol(C64, 2.5, a), pol(C64, ln + (i % 3), a + 0.15), 0.7, 0.4, 0.4, 0.7)
        cv.disc('void', C64, (2.5, 4.0, 4.5)[t], 0.4, 0.8, 0.2)
        cv.disc('soul', C64, (1.2, 2.2, 2.6)[t], 0.6, 1.0, 0.0)
    H = (0, 3.5, 7, 10, 11, 11, 6, 2.5)[t]
    lean = (0, -0.1, -0.2, -0.25, -0.2, -0.2, -0.1, 0.0)[t]      # the spikes splay outwards: a crown, not a comb
    if H > 0:
        for i, b in enumerate(base):
            g = b + (C64 - b) * lean
            tip = scr(g, H + (i % 2) * 1.5)
            u = tip - b
            u = u / max(np.linalg.norm(u), 1e-6)
            v = np.array((-u[1], u[0]))
            w = 2.6 if t < 6 else 2.0
            cv.tri('bone', tip, b + v * w, b - v * w)
            cv.disc('ash', b + (0.6, 0.8), 2.4, 0.3, 0.6, 0.1)
    if t in (4, 5):
        cv.disc('void', apex + (0, 2.5), 7.0, 0.2, 0.45, 0.2)
        cv.skull(apex + (0, 2.5), 1.3 if t == 4 else 1.45, 1.0)
        cv.ring('void', apex + (0, 2.5), 8.0 if t == 4 else 9.5, 1.2, val=0.55)
        if t == 5:
            cv.ring('soul', C64, 13.5, 1.2, val=0.55)
    if t >= 6:
        for i in range(10):
            a = i * 0.63 + 0.3
            cv.disc('ash', pol(C64, 9.5 + (i % 3), a), 1.3 + 0.4 * (i % 2), 0.3, 0.5, 0.1)
    sparks(cv, rng, (0, 1, 2, 2, 3, 4, 3, 2)[t], scr(C64, 10), 4, 13, ('soul', 'bone'))
    return cv.finish()


def banner(t, rng):
    """Banner of Bones on the Bone Lord: a violet ring with bone chips, six bone shards rise and circle into a
    spinning crown above him, it flares green and the shards rain back (8 frames)"""
    cv = Canvas(64)
    span = (0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 0.7, 0.35)[t] * 2 * math.pi
    cv.ring('void', C64, 12.5, 2.0, start=-math.pi / 2 + (0.6 if t >= 6 else 0), span=span, val=0.6)
    if t <= 5:
        for i in range(6):
            a = i * math.pi / 3
            if ((a + math.pi / 2) % (2 * math.pi)) <= span:
                p = pol(C64, 12.5, a)
                cv.capsule('bone', p - (0.9, 0.3), p + (0.9, 0.3), 0.7, 0.7, 0.5, 0.9)
    H = (0, 2, 7, 12, 16, 19, 0, 0)[t]
    R = (12, 11, 10, 8.5, 7, 6, 0, 0)[t]
    if 1 <= t <= 5:
        for i in range(6):
            a = i * math.pi / 3 + 0.55 * t
            g = pol(C64, R, a)
            p = scr(g, H)
            tr = scr(pol(C64, R + 0.8, a - 0.5), max(H - 3, 0))
            cv.capsule('soul', tr, p, 0.5, 1.2, 0.5, 0.85)
            u = np.array((-math.sin(a), math.cos(a)))
            cv.bone(p - u * 2.4, p + u * 2.4, 0.9, 1.0)
    if t == 5:
        top = scr(C64, 21)
        cv.disc('soul', top, 3.0, 0.5, 1.0, 0.4)
        cv.disc('core', top, 1.6, 0.6, 1.0, 0.2)
    if t == 6:
        top = scr(C64, 21)
        cv.ring('soul', top, 8.0, 1.6, val=0.7)
        cv.disc('core', top, 2.4, 0.5, 1.0, 0.2)
        for i in range(6):
            a = i * math.pi / 3 + 0.2
            p = pol(top, 10.5, a) + (0, 2)
            u = np.array((math.cos(a), math.sin(a)))
            cv.bone(p - u * 2.0, p + u * 2.0, 0.85, 0.9)
    if t == 7:
        for i in range(6):
            a = i * math.pi / 3 + 0.5
            p = pol(C64, 9 + (i % 3) * 1.5, a)
            cv.bone(p - (1.7, 0.4), p + (1.7, 0.4), 0.7, 0.75)
    sparks(cv, rng, (1, 2, 3, 3, 4, 5, 6, 4)[t], scr(C64, 10), 5, 14, ('soul', 'core'))
    return cv.finish()


C32 = np.array((18.0, 18.0))


def rally(t, rng):
    """a minion rallied by the banner: three bone shards spiral up around it, a green spark on top (32 px, 6 frames)"""
    cv = Canvas(32)
    if t <= 3:
        cv.ring('void', C32, 7.0, 1.4, start=-math.pi / 2, span=(0.5, 1.0, 1.0, 0.8)[t] * 2 * math.pi, val=0.6)
    H = (0, 3, 7, 11, 0, 0)[t]
    R = (6.5, 6, 5, 3.5, 0, 0)[t]
    if 1 <= t <= 3:
        for i in range(3):
            a = i * 2 * math.pi / 3 + 0.9 * t
            p = scr(pol(C32, R, a), H)
            u = np.array((-math.sin(a), math.cos(a)))
            cv.bone(p - u * 1.8, p + u * 1.8, 0.75, 1.0)
            cv.capsule('soul', scr(pol(C32, R + 0.5, a - 0.6), max(H - 3, 0)), p, 0.4, 0.9, 0.5, 0.85)
    if t == 4:
        top = scr(C32, 14)
        cv.disc('soul', top, 2.6, 0.5, 1.0, 0.4)
        cv.disc('core', top, 1.3, 0.6, 1.0, 0.2)
        for i in range(3):
            a = i * 2 * math.pi / 3 + 0.4
            cv.capsule('bone', pol(top, 4.0, a), pol(top, 6.0, a), 0.8, 0.5, 0.5, 0.9)
    if t == 5:
        top = scr(C32, 14)
        cv.spark('soul', np.round(top) + 0.5, 2.0, 0.95)
    if t >= 1:
        sparks(cv, rng, (0, 1, 1, 2, 2, 2)[t], scr(C32, 7), 2, 8, ('soul', 'core'))
    return cv.finish()


def offering(t, rng):
    """Bone Offering: the skeleton bursts: a violet crack-flash, ribs, long bones and the skull thrown out in a ring of
    ash, they fall and scatter (8 frames)"""
    cv = Canvas(64)
    P = scr(C64, 9)
    if t == 0:
        for k in range(6):
            a = k * math.pi / 3 + 0.3
            cv.capsule('void', P, pol(P, 8.5 if k % 2 else 6.0, a), 1.4, 0.3, 0.55, 0.95)
        cv.skull(P + (0, -1), 0.9, 1.0)
        cv.disc('core', P + (0, 4), 1.4, 0.6, 1.0, 0.2)
    if t == 1:
        cv.disc('void', P, 8.0, 0.25, 0.6, 0.3)
        cv.disc('soul', P, 5.2, 0.45, 0.95, 0.4)
        cv.disc('core', P, 3.0, 0.5, 1.0, 0.3)
    r = (0, 5.5, 9.0, 11.5, 12.5, 0, 0, 0)[t]
    drop = (0, 0, 1.0, 3.0, 5.0, 0, 0, 0)[t]
    kinds = ['bone', 'rib', 'bone', 'rib', 'bone', 'rib', 'bone', 'rib']
    if 1 <= t <= 4:
        for i, k in enumerate(kinds):
            a = i * math.pi / 4 + 0.2
            p = pol(P, r, a) + (0, drop * (0.6 + 0.4 * (i % 2)))
            u = np.array((math.cos(a + 0.7 * t + i), math.sin(a + 0.7 * t + i)))
            if k == 'bone':
                cv.bone(p - u * 3.0, p + u * 3.0, 0.95, 1.0)
            else:
                cv.ring('bone', p + u * 3.0, 3.2, 1.3, start=math.atan2(-u[1], -u[0]) - 0.9, span=1.8, val=0.75)
        sk = P + (-0.6 * r, -0.9 * r + drop * 0.5)
        cv.skull(sk, 0.85, 1.0)
    if 2 <= t <= 5:
        R = (0, 0, 8.5, 10.5, 11.5, 12)[t]
        for i in range(12):
            a = i * math.pi / 6 + 0.1 * t
            cv.disc('ash', pol(C64, R, a), (2.8, 2.6, 2.0, 1.4)[t - 2], 0.3, 0.7, 0.3)
    if t >= 5:
        pieces = (8, 6, 3)[t - 5]
        for i in range(pieces):
            a = i * math.pi / 4 + 0.6
            p = pol(C64, 7 + (i % 3) * 2.5, a)
            if i % 2:
                cv.bone(p - (2.0, 0.5), p + (2.0, 0.5), 0.75, 0.8)
            else:
                cv.capsule('bone', p - (1.4, -0.4), p + (1.4, -0.4), 0.7, 0.6, 0.4, 0.7)
        if t == 5:
            cv.skull(C64 + (-6, 2), 0.7, 0.75, eyes='ash')
    sparks(cv, rng, (2, 3, 4, 4, 3, 3, 2, 2)[t], P, 5, 14, ('soul', 'void'))
    return cv.finish()


def ward(t, rng):
    """the Bone Lord's bone ward: six curved rib plates grow from an ash ring and close over him, a violet rim and a
    green glint, then they crack and drop as chips (8 frames)"""
    cv = Canvas(64)
    n = 6
    cv.ring('ash', C64, 12.0, 1.6, val=0.5 if t < 7 else 0.35)
    H = (0, 3, 8, 13, 15, 15, 8, 0)[t]
    if H > 0:
        for i in range(n):
            a = i * 2 * math.pi / n + 0.35
            b = pol(C64, 12.0, a)
            pts = []
            for s in np.linspace(0, 1, 5):
                g = b + (C64 - b) * (0.55 * s * s * min(1, H / 13))
                pts.append(scr(g, H * s))
            for k, (p, q) in enumerate(zip(pts, pts[1:])):
                r0 = 1.9 - 0.32 * k
                cv.capsule('bone', p, q, r0, r0 - 0.32, 0.45, 0.95)
            if t == 6:
                cv.bone(pts[-1] + (1.5, 4.5), pts[-1] + (3.5, 6.5), 0.7, 0.8)
    if t in (4, 5):
        top = scr(C64, 15)
        cv.ring('void', top + (2.5, 2.5), 6.5, 1.3, val=0.65 if t == 4 else 0.8)
        cv.disc('soul', top + (2.5, 2.5), 1.8, 0.6, 1.0, 0.2)
    if t == 7:
        for i in range(8):
            a = i * math.pi / 4 + 0.3
            p = pol(C64, 10 + (i % 2) * 2.5, a)
            cv.capsule('bone', p - (1.3, 0.2), p + (1.3, 0.2), 0.7, 0.6, 0.4, 0.75)
    sparks(cv, rng, (1, 2, 2, 3, 4, 4, 3, 2)[t], scr(C64, 9), 4, 14, ('void', 'core'))
    return cv.finish()


# name, function, frame size, frames, ms per frame, note (importer spec)
EFFECTS = [
    ('necro_spear_hit', spear_hit, 64, 7, 70, 'bone: the bone spear strikes, splinters and a violet snap'),
    ('bonelord_golem_rise', golem_rise, 64, 8, 90, 'bone: spikes erupt into a ribcage, a skull flares (Bone Golem)'),
    ('bonelord_banner', banner, 64, 8, 90, 'bone: shards circle up into a crown and rain back (Banner of Bones)'),
    ('bonelord_offering', offering, 64, 8, 85, 'bone: a skeleton bursts into ribs, bones and ash (Bone Offering)'),
    ('bonelord_ward', ward, 64, 8, 90, 'bone: rib plates close over the caster and crumble (bone ward)'),
    ('bonelord_rally', rally, 32, 6, 90, 'bone: shards spiral up a rallied minion (Banner of Bones)'),
]
SHEET = (512, 384)


def layout():
    """name -> list of (x, y, size) cells on the sheet, in frame order"""
    cells, row = {}, 0
    for name, _, size, n, _, _ in EFFECTS:
        if size == 64:
            cells[name] = [(64 * f, 64 * row, 64) for f in range(n)]
            row += 1
        else:
            cells[name] = [(32 * f, 64 * row, 32) for f in range(n)]
            row += 1
    assert 64 * row <= SHEET[1]
    return cells


def shapes():
    cells = layout()
    sheet = np.zeros((SHEET[1], SHEET[0], 4), np.uint8)
    frames = {}
    for k, (name, fn, size, n, _, _) in enumerate(EFFECTS):
        rng = np.random.default_rng(100 + k)
        F = [fn(t, rng) for t in range(n)]
        for t, f in enumerate(F):
            a = f[..., 3] > 0
            if a[0].any() or a[-1].any() or a[:, 0].any() or a[:, -1].any():
                raise SystemExit('%s frame %d touches the edge' % (name, t))
            assert a.any() or t == n - 1, (name, t, 'empty')
        frames[name] = F
        for (x, y, s), f in zip(cells[name], F):
            sheet[y:y + s, x:x + s] = f
    return sheet, frames


PROMPT = """Improve and refine the texture quality of this existing pixel-art magic effect sheet. Each row is one dark-fantasy necromancer spell effect animation, frames left to right in 64x64 cells (the last row: 32x32 cells).

Do NOT redesign it.
Do NOT move, resize or add shapes. Keep every frame in its own cell, in the same place. Keep empty cells empty.

ROWS:
1. a bone spear impact: a violet snap, six bone splinters flying out and falling.
2. a bone golem rising: the ground cracks, bone spikes erupt in a ring and close into a ribcage, a skull with glowing green eyes on top, then they sink.
3. a war banner of bones: bone shards rise from a violet rune ring and circle up into a crown, a green flare, the shards rain back down.
4. a skeleton bursting apart: ribs, long bones and a skull thrown out in a ring of ash dust, then scattered on the ground.
5. a bone ward: curved rib plates grow from the ground and close over the caster, a violet rim, then they crack into chips.
6. small: three bone shards spiral up around a creature, a green spark.

STYLE:
Tibia-style 45-degree oblique top-down 2.5D game effect. Light from the upper-left. Old ivory and ash-grey bone with hue-shifted shading, sickly soul-green and arcane violet glow only as accents, white-hot cores, small sparkles. Thin dark outline around every shape, dark violet or dark ash, not pure black.

PIXEL ART QUALITY:
Crisp fantasy game sprite effect, readable pixel clusters at 1x. No blur, no smooth gradients, no anti-aliasing, no background.
"""


def cmd_shapes():
    sheet, _ = shapes()
    os.makedirs(SRC, exist_ok=True)
    p = os.path.join(SRC, 'sheet_shape.png')
    Image.fromarray(sheet, 'RGBA').save(p)
    print(p, sheet.shape)


def cmd_paint(seed):
    sys.path.insert(0, os.path.join(HERE, '..', 'art_studio', 'kit'))
    import pixellab  # noqa: E402  (the session proxy or .pixellab_token supplies the credential)
    sheet = np.asarray(Image.open(os.path.join(SRC, 'sheet_shape.png')).convert('RGBA'))
    print('prompt %d chars' % len(PROMPT))
    print('balance before', json.dumps(pixellab.balance()))
    seed = seed if seed is not None else random.randint(1, 2 ** 30)
    imgs = pixellab.edit_image_pro(sheet, PROMPT, seed=seed, label='necro fx %d' % seed)
    for i, a in enumerate(imgs):
        p = os.path.join(SRC, 'sheet_paint_%d%s.png' % (seed, '' if i == 0 else '_%d' % i))
        Image.fromarray(a, 'RGBA').save(p)
        print('wrote', p, a.shape)
    print('balance after', json.dumps(pixellab.balance()))


def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out |= shift(m, dx, dy)
    return out


def shift(a, dx, dy):
    """shift an array (H, W[, C]) by (dx, dy), zero fill"""
    out = np.zeros_like(a)
    H, W = a.shape[:2]
    xs, xd = (slice(0, W - dx), slice(dx, W)) if dx >= 0 else (slice(-dx, W), slice(0, W + dx))
    ys, yd = (slice(0, H - dy), slice(dy, H)) if dy >= 0 else (slice(-dy, H), slice(0, H + dy))
    out[yd, xd] = a[ys, xs]
    return out


def cmd_build(paint_name):
    cells = layout()
    shape_sheet = np.asarray(Image.open(os.path.join(SRC, 'sheet_shape.png')).convert('RGBA'))
    paint = np.asarray(Image.open(os.path.join(SRC, paint_name)).convert('RGBA')).copy()
    assert paint.shape == shape_sheet.shape, (paint.shape, shape_sheet.shape)
    paint[..., 3] = np.where(paint[..., 3] >= 128, 255, 0)
    paint[paint[..., 3] == 0] = 0
    os.makedirs(OUT, exist_ok=True)
    report = []
    for name, _, size, n, ms, _ in EFFECTS:
        S = [shape_sheet[y:y + s, x:x + s] for x, y, s in cells[name]]
        P = [paint[y:y + s, x:x + s] for x, y, s in cells[name]]
        rng_ = range(-8, 9) if size == 64 else range(-4, 5)
        best = max(((sum(int(((shift(p[..., 3] > 0, dx, dy)) & (s[..., 3] > 0)).sum()) for p, s in zip(P, S)), dx, dy)
                    for dx in rng_ for dy in rng_))
        _, dx, dy = best
        frames, fell = [], []
        for t, (p, s) in enumerate(zip(P, S)):
            q = shift(p, dx, dy)
            keep = dilate(s[..., 3] > 0, 2)
            q[~keep] = 0
            q[:1] = 0; q[-1:] = 0; q[:, :1] = 0; q[:, -1:] = 0
            sa, qa = s[..., 3] > 0, q[..., 3] > 0
            iou = (sa & qa).sum() / max((sa | qa).sum(), 1)
            if sa.any() and (iou < 0.3 or qa.sum() < 0.5 * sa.sum()):
                q = s.copy()                       # the painting lost this frame: keep the shape frame
                fell.append(t)
            frames.append(q)
        strip = np.concatenate(frames, 1)
        Image.fromarray(strip, 'RGBA').save(os.path.join(OUT, name + '.png'), optimize=True)
        report.append('%s: shift (%d, %d), shape frames kept for %s' % (name, dx, dy, fell or 'none'))
    # the approved style sample (Soul Drain, 8 x 64 px): its repaint moved back onto the tile by (7, 5), hard alpha
    sd = np.asarray(Image.open(os.path.join(SRC, 'soul_drain_paint.png')).convert('RGBA')).copy()
    sd[..., 3] = np.where(sd[..., 3] >= 128, 255, 0)
    sd[sd[..., 3] == 0] = 0
    sd = np.concatenate([shift(sd[:, t * 64:(t + 1) * 64], 7, 5) for t in range(8)], 1)
    Image.fromarray(sd, 'RGBA').save(os.path.join(OUT, 'lich_soul_drain.png'), optimize=True)
    report.append('lich_soul_drain: the style sample, shift (7, 5)')
    for line in report:
        print(line)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['shapes', 'paint', 'build'])
    ap.add_argument('--seed', type=int, default=None)
    ap.add_argument('--paint', default=PAINT)
    a = ap.parse_args()
    if a.cmd == 'shapes':
        cmd_shapes()
    elif a.cmd == 'paint':
        cmd_paint(a.seed)
    else:
        cmd_build(a.paint)


if __name__ == '__main__':
    main()
