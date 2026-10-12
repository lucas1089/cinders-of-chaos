#!/usr/bin/env python3
"""Class signature effects: each class line's signature spells get an effect of their own (ROADMAP C4 "effects").

    python3 -I gen_class_fx.py build                 # -> art_import/class_fx/<name>.png + art_import/class_fx.csv
    python3 -I gen_class_fx.py build --check         # rebuild in memory, compare with the checked-in strips and spec
    python3 -I gen_class_fx.py preview --out DIR [--dat D --spr S]
                                                     # frame-by-frame sheets and a mock combat scene per class
                                                     # (the class looks come from the pair D / S when given)

Our own procedural art, drawn here frame by frame: discs, capsules, triangles, polygons and rings on a 4x supersample,
quantised per material to hard colour ramps with a dark outline, in the oblique view of the pair (a point at height h
is drawn 0.85 h up and 0.3 h left). No pixel of any other game, client or reference sheet is used, and no painting
service is called: the build is plain Python and deterministic (fixed seeds per effect).

Rules every strip is checked against (build stops otherwise): alpha 0 / 255; every frame but the last has art; the
last frame is empty; nothing touches the frame's edge; the 1x1 area effects (sent on every tile of an area) keep at
least 65 % of every frame fully transparent, like the procedural set (server/data/spells/README_FX.md).

The 2x2 effects have the target as their bottom-right tile (send offset 0,0), the 1x1 ones sit on the target tile.
Server side: server/data/lib/chaos_class_fx.lua (which spell of which class sends which effect, behind the pair
switch ChaosClassFx.PAIR22_FX) and chaos_class_fx_ids.lua (written by import_fx_art.py from art_import/class_fx.csv).
"""
import argparse
import csv
import io
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'class_fx')
SPEC = os.path.join(ART, 'class_fx.csv')
SS = 4

RAMPS = {   # [0] is the outline, then dark -> light
    'shade': [(10, 8, 14), (30, 26, 38), (48, 42, 58)],
    'rock': [(22, 16, 12), (62, 48, 38), (98, 80, 62), (138, 116, 90), (176, 154, 122)],
    'smoke': [(14, 14, 18), (48, 46, 56), (80, 78, 90), (114, 112, 124), (152, 150, 162)],
    'ink': [(4, 2, 8), (22, 16, 32), (40, 30, 56), (66, 54, 88)],
    'steel': [(18, 20, 26), (58, 64, 76), (98, 106, 122), (150, 158, 174), (214, 220, 230)],
    'bronze': [(34, 20, 8), (106, 66, 28), (166, 112, 50), (218, 168, 88), (250, 222, 158)],
    'blood': [(28, 2, 6), (88, 8, 16), (146, 18, 26), (204, 44, 44), (248, 116, 104)],
    'ember': [(40, 10, 4), (124, 36, 10), (198, 76, 18), (244, 142, 40), (255, 216, 120)],
    'leaf': [(8, 28, 12), (28, 72, 28), (56, 118, 42), (108, 168, 62), (182, 218, 108)],
    'amber': [(40, 22, 4), (120, 70, 14), (190, 122, 28), (236, 180, 60), (255, 234, 150)],
    'wind': [(18, 38, 42), (66, 116, 116), (126, 178, 168), (194, 230, 214), (240, 255, 246)],
    'frost': [(6, 18, 42), (28, 68, 128), (68, 128, 198), (138, 196, 240), (220, 244, 255)],
    'storm': [(22, 8, 46), (68, 38, 138), (128, 88, 218), (188, 158, 255), (240, 230, 255)],
    'prism': [(6, 28, 42), (18, 88, 118), (48, 168, 198), (128, 228, 240), (228, 255, 255)],
    'rose': [(42, 6, 34), (118, 28, 98), (194, 68, 168), (238, 138, 218), (255, 218, 248)],
    'sakura': [(38, 4, 14), (138, 22, 44), (204, 58, 82), (242, 138, 158), (255, 224, 230)],
    'soul': [(10, 40, 20), (32, 100, 46), (76, 176, 68), (148, 232, 102), (218, 255, 180)],
    'void': [(32, 8, 56), (68, 22, 116), (116, 50, 188), (168, 102, 238), (220, 184, 255)],
    'jade': [(6, 32, 24), (22, 90, 64), (48, 148, 104), (108, 204, 148), (198, 248, 212)],
    'chi': [(48, 14, 2), (158, 58, 8), (228, 118, 28), (255, 178, 66), (255, 238, 176)],
    'gold': [(46, 28, 4), (148, 102, 18), (218, 168, 38), (250, 218, 98), (255, 250, 208)],
    'core': [(70, 60, 48), (226, 216, 196), (250, 246, 236), (255, 255, 255)],
}
ORDER = ['shade', 'rock', 'smoke', 'ink', 'steel', 'bronze', 'blood', 'leaf', 'amber', 'wind', 'frost', 'storm',
         'prism', 'rose', 'sakura', 'soul', 'void', 'jade', 'chi', 'ember', 'gold', 'core']   # later wins

TAU = 2 * math.pi


def scr(c, h):
    """ground point c=(x, y) at height h -> screen: mostly up, a little left (the pair's oblique view; tall shapes
    such as banners, flames and blades stay readable as upright)."""
    return np.array((c[0] - h * 0.3, c[1] - h * 0.85))


def pol(c, r, a):
    return np.array((c[0] + r * math.cos(a), c[1] + r * math.sin(a)))


class Canvas:
    def __init__(self, n):
        self.n = n
        m = n * SS
        yy, xx = np.mgrid[0:m, 0:m]
        self.X = (xx + 0.5) / SS
        self.Y = (yy + 0.5) / SS
        self.I = {}

    def put(self, mat, inside, val):
        cur = self.I.get(mat)
        if cur is None:
            cur = self.I[mat] = np.zeros(self.X.shape)
        v = np.clip(val, 0.01, 1.0)
        self.I[mat] = np.where(inside, np.maximum(cur, v), cur)

    def disc(self, mat, c, r, lo=0.35, hi=1.0, lit=0.35):
        dx, dy = self.X - c[0], self.Y - c[1]
        d = np.hypot(dx, dy)
        rel = np.clip(1 - d / max(r, 1e-6), 0, 1)
        tl = np.clip((-dx - dy) / (r * 1.414 + 1e-6), -1, 1)
        self.put(mat, d <= r, lo + (hi - lo) * rel + lit * tl * 0.5)

    def ellipse(self, mat, c, a, b, ang, lo=0.4, hi=0.95):
        dx, dy = self.X - c[0], self.Y - c[1]
        u = dx * math.cos(ang) + dy * math.sin(ang)
        v = -dx * math.sin(ang) + dy * math.cos(ang)
        q = (u / max(a, 1e-6)) ** 2 + (v / max(b, 1e-6)) ** 2
        self.put(mat, q <= 1, lo + (hi - lo) * np.clip(1 - q, 0, 1) + 0.15 * np.clip(-v / max(b, 1e-6), -1, 1))

    def capsule(self, mat, a, b, ra, rb, lo=0.3, hi=0.9):
        a, b = np.asarray(a, float), np.asarray(b, float)
        ab = b - a
        L2 = max(ab @ ab, 1e-9)
        t = np.clip(((self.X - a[0]) * ab[0] + (self.Y - a[1]) * ab[1]) / L2, 0, 1)
        d = np.hypot(self.X - (a[0] + t * ab[0]), self.Y - (a[1] + t * ab[1]))
        r = ra + (rb - ra) * t
        self.put(mat, d <= r, lo + (hi - lo) * (1 - t) * np.clip(1 - d / np.maximum(r, 1e-6), 0, 1) + 0.1)

    def line(self, mat, pts, r, val=0.6):
        for p, q in zip(pts[:-1], pts[1:]):
            self.capsule(mat, p, q, r, r, val, val)

    def poly(self, mat, pts, val=0.7, lit=0.25):
        m = self.n * SS
        im = Image.new('L', (m, m), 0)
        ImageDraw.Draw(im).polygon([(float(x) * SS, float(y) * SS) for x, y in pts], fill=255)
        inside = np.asarray(im) > 0
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        span = max(max(abs(p[0] - cx) + abs(p[1] - cy) for p in pts), 1.0)
        tl = np.clip((-(self.X - cx) - (self.Y - cy)) / span, -1, 1)
        self.put(mat, inside, val + lit * tl)

    def tri(self, mat, a, b, c, val=0.7, lit=0.25):
        self.poly(mat, [a, b, c], val, lit)

    def ring(self, mat, c, R, w, start=0.0, span=TAU, val=0.75, taper=False):
        dx, dy = self.X - c[0], self.Y - c[1]
        d = np.hypot(dx, dy)
        ang = (np.arctan2(dy, dx) - start) % TAU
        ww = w / 2 * (np.sin(np.pi * np.clip(ang / span, 0, 1)) if taper else 1.0)
        tl = np.clip((-dx - dy) / (R * 1.414 + 1e-6), -1, 1)
        self.put(mat, (np.abs(d - R) <= ww) & (ang <= span), val + 0.18 * tl)

    def arcs(self, mat, c, R, w, n, phase, fill=0.6, val=0.75):
        """a broken ring: n arcs, each `fill` of its sector"""
        for k in range(n):
            self.ring(mat, c, R, w, phase + k * TAU / n, fill * TAU / n, val)

    def spark(self, mat, c, s, val=1.0):
        c = np.asarray(c, float)
        for dx, dy in ((1, 0), (0, 1)):
            self.capsule(mat, c - np.array((dx, dy)) * s, c + np.array((dx, dy)) * s, 0.45, 0.45, val, val)
        self.disc(mat, c, 0.8, val, val, 0)

    def dot(self, mat, c, r=0.9, val=0.9):
        self.disc(mat, c, r, val, val, 0)

    def finish(self):
        """-> n x n RGBA: per pixel the top material covering >= 40% of it, its mean value on a ramp, outlined."""
        N = self.n
        out = np.zeros((N, N, 4), np.uint8)
        owner = np.full((N, N), -1)
        value = np.zeros((N, N))
        mats = [m for m in ORDER if m in self.I]
        for m in mats:
            mi = ORDER.index(m)
            I = self.I[m].reshape(N, SS, N, SS)
            cov = (I > 0).mean((1, 3))
            mean = I.sum((1, 3)) / np.maximum((I > 0).sum((1, 3)), 1)
            on = cov >= 0.4
            owner[on] = mi
            value[on] = mean[on]
        for m in mats:
            mi = ORDER.index(m)
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
            for m in mats:
                mi = ORDER.index(m)
                s = ring & (q == mi) & (out[..., 3] == 0)
                out[s, :3] = RAMPS[m][0]
                out[s, 3] = 255
        return out


# ------------------------------------------------------------------------------------------------ helpers
C64 = np.array((48.0, 48.0))       # the target tile's centre on the ground (3x3 frame: the target is the centre tile)
C32 = np.array((16.0, 16.0))       # 1x1 frame


def ease(t, n):
    return t / max(n - 1, 1)


def bell(t, peak, width):
    return max(0.0, 1.0 - abs(t - peak) / width)


def flying(rng, n, rmin, rmax, hmin=0, hmax=0):
    return [(rng.uniform(0, TAU), rng.uniform(rmin, rmax), rng.uniform(hmin, hmax), rng.random()) for _ in range(n)]


def sparks(cv, rng, n, c, rmin, rmax, mats, val=0.95):
    for _ in range(n):
        a, r = rng.uniform(0, TAU), rng.uniform(rmin, rmax)
        p = np.round(pol(c, r, a)) + 0.5
        cv.spark(mats[0] if rng.random() < 0.5 else mats[-1], p, 1.0 + (rng.random() < 0.35), val)


def leaf(cv, mat, c, s, ang, val=0.75):
    cv.ellipse(mat, c, 2.2 * s, 1.0 * s, ang, val - 0.25, val + 0.15)


def claw(cv, mat, a, b, w, val=0.85):
    """a tapering curved rake mark from a to b"""
    a, b = np.asarray(a, float), np.asarray(b, float)
    mid = (a + b) / 2 + np.array((-(b - a)[1], (b - a)[0])) * 0.12
    cv.capsule(mat, a, mid, w * 0.5, w, val, val)
    cv.capsule(mat, mid, b, w, 0.3, val, val)


def blade(cv, mat, a, b, w, val=0.85, edge='core'):
    a, b = np.asarray(a, float), np.asarray(b, float)
    cv.capsule(mat, a, b, w, 0.35, val - 0.2, val)
    u = (b - a) / max(np.linalg.norm(b - a), 1e-6)
    cv.capsule(edge, a + u * 1.5, b - u * 1.0, 0.45, 0.35, 0.9, 0.9)


def hexagon(c, r, rot=0.0):
    return [tuple(pol(c, r, rot + k * TAU / 6)) for k in range(6)]


def shield_pts(c, w, h):
    x, y = c
    return [(x - w, y - h), (x + w, y - h), (x + w, y + h * 0.2), (x, y + h), (x - w, y + h * 0.2)]


# ------------------------------------------------------------------------------------------------ the effects
EFFECTS = []   # (name, tiles, frames, ms, note, fn, area)


def effect(name, tiles, frames, ms, note, area=False):
    def deco(fn):
        EFFECTS.append(dict(name=name, tiles=tiles, frames=frames, ms=ms, note=note, fn=fn, area=area))
        return fn
    return deco


# ---- Warrior line: iron, rock and ember
@effect('warrior_quake', 3, 8, 85, 'warrior: the ground splits in ember cracks, slabs of rock thrown up (Earthbreaker, Colossus Fall)')
def warrior_quake(cv, t, R):
    P = C64
    cracks = [(k * TAU / 7 + R.uniform(-0.3, 0.3), R.uniform(11, 17), R.uniform(-1, 1)) for k in range(7)]
    chunks = flying(R, 6, 0.0, 1.0)
    g = (0.35, 0.7, 1, 1, 1, 0.9, 0.6, 0)[t]
    if g:
        for a, L, bend in cracks:
            pts = [P, pol(P, L * g * 0.45, a + 0.12 * bend), pol(P, L * g * 0.8, a - 0.1 * bend), pol(P, L * g, a)]
            cv.line('rock', pts, 1.3, 0.25)
            if t <= 5:
                cv.line('ember', pts[:-1] if t >= 4 else pts, 0.55, 0.95 if t <= 3 else 0.55)
    if t <= 1:
        cv.disc('rock', P, 4.5, 0.2, 0.5, 0.3)
        cv.disc('core' if t == 0 else 'ember', scr(P, 3), 2.5, 0.7, 1.0, 0)
    if 1 <= t <= 5:
        for a, s, _, k in chunks:
            r = 4 + (t - 1) * (2.4 + 1.4 * s)
            h = 18 * math.sin(math.pi * (t - 1) / 5) * (0.6 + 0.4 * k)
            c = scr(pol(P, r, a), h)
            rot = t * 0.9 + a
            cv.tri('rock', pol(c, 3.0, rot), pol(c, 2.4, rot + 2.2), pol(c, 2.8, rot + 4.1), 0.6, 0.3)
    if 2 <= t <= 5:
        cv.arcs('rock', P, 8 + 2.6 * t, 1.6, 5, t * 0.4, 0.5, 0.45)
    if 1 <= t <= 4:
        sparks(cv, R, 4, scr(P, 6), 4, 14, ('ember', 'core'))


@effect('warrior_gyre', 3, 8, 70, 'warrior: two steel crescents sweep a full circle at blade height (Reaping Gyre)')
def warrior_gyre(cv, t, R):
    P = C64
    if t >= 7:
        return
    H = scr(P, 9)
    for k in range(2):
        st = t * 0.95 + k * math.pi
        cv.ring('steel', H, 13 - (t >= 5) * 2, 3.2, st, 2.0, 0.65, taper=True)
        cv.ring('core', H, 13 - (t >= 5) * 2, 1.0, st + 0.3, 1.3, 0.9, taper=True) if t <= 5 else None
    if t <= 5:
        cv.arcs('rock', P, 9 + t, 1.2, 4, t * 0.7, 0.35, 0.4)
    if 1 <= t <= 4:
        sparks(cv, R, 3, H, 10, 15, ('steel', 'core'))


@effect('warrior_bellow', 3, 8, 80, 'warrior: an iron war cry; chevrons and broken rings rush outward (Iron Bellow)')
def warrior_bellow(cv, t, R):
    P = C64
    if t >= 7:
        return
    H = scr(P, 14)
    if t <= 2:
        cv.disc('core', H, 2.4 + t, 0.7, 1.0, 0)
        cv.ring('steel', H, 4 + t * 2, 1.4, val=0.7)
    for k in range(3):
        r = 5 + (t - k * 1.2) * 4.2
        if 3 <= r <= 21:
            cv.arcs('steel', scr(P, 6), r, 1.6 if k == 0 else 1.1, 6, k * 0.5 + t * 0.15, 0.55, 0.75 - k * 0.12)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d = 7 + t * 2.6
        if t >= 1 and d <= 20:
            tip = pol(H, d + 3, a)
            cv.line('bronze', [pol(tip, 3.5, a + 2.4), tip, pol(tip, 3.5, a - 2.4)], 0.8, 0.8)


@effect('juggernaut_bulwark', 3, 8, 90, 'juggernaut: an iron tower shield slams down before the caster and cracks the ground (Iron Bellow)')
def juggernaut_bulwark(cv, t, R):
    P = C64
    if t >= 7:
        return
    drop = (22, 9, 0, 0, 0, 0, -2)[t]
    c = scr(P, 13 + drop) + np.array((0.0, 0.0))
    sink = (0, 0, 0, 0, 0, 3, 7)[t]
    if t <= 5:
        pts = shield_pts(c + (0, sink), 8, 12 - sink * 0.8)
        cv.poly('steel', pts, 0.55, 0.3)
        cv.line('bronze', pts + [pts[0]], 1.0, 0.75)
        cv.capsule('bronze', c + (0, -9 + sink), c + (0, 9), 1.0, 1.0, 0.65, 0.65)
        cv.capsule('bronze', c + (-6, -2 + sink), c + (6, -2 + sink), 1.0, 1.0, 0.65, 0.65)
        for dx, dy in ((-5, -8), (5, -8), (-5, 3), (5, 3)):
            cv.dot('core' if t == 3 and dx < 0 else 'steel', c + (dx, dy + sink), 0.8, 0.95)
    else:
        for k in range(5):
            a = k * TAU / 5 + 0.4
            p = c + (0, 6) + pol((0, 0), 4 + t, a)
            cv.tri('steel', pol(p, 2.6, a), pol(p, 2.0, a + 2.2), pol(p, 2.4, a + 4.1), 0.5, 0.2)
    if 2 <= t <= 5:
        cv.arcs('rock', P, 9 + (t - 2) * 3, 1.8, 6, t * 0.3, 0.5, 0.4)
        for k in range(5):
            a = k * TAU / 5 + 0.3
            cv.line('rock', [P, pol(P, 6 + (t - 2) * 2, a)], 0.9, 0.25)
    if t == 2 or t == 3:
        sparks(cv, R, 5, P, 5, 13, ('ember', 'core'))


@effect('berserker_rage', 3, 8, 80, 'berserker: blood flames tear up around the caster, droplets spray and fall (Red Frenzy, Bloodrage)')
def berserker_rage(cv, t, R):
    P = C64
    if t >= 7:
        return
    flames = [(k * TAU / 9 + R.uniform(-0.2, 0.2), R.uniform(0.7, 1.2)) for k in range(9)]
    drops = flying(R, 10, 3, 14, 0, 1)
    g = (0.4, 0.8, 1.0, 1.0, 0.85, 0.6, 0.3)[t]
    for a, s in flames:
        b = pol(P, 9, a)
        tip = scr(b, 22 * g * s)
        cv.tri('blood', tip, pol(b, 2.6, a + math.pi / 2), pol(b, 2.6, a - math.pi / 2), 0.55, 0.35)
        if t <= 4:
            cv.capsule('ember', b, scr(b, 9 * g * s), 0.7, 0.3, 0.8, 0.95)
    if t <= 3:
        cv.ring('blood', P, 9, 1.6, val=0.4)
    if 1 <= t <= 6:
        for a, r, _, k in drops:
            h = 26 * (t / 3.5) - 7 * (t / 3.5) ** 2 * 2 * (0.6 + 0.6 * k)
            if h > 0:
                cv.disc('blood', scr(pol(P, r * t / 4, a), h), 1.2, 0.6, 0.95, 0.3)
    if t == 1:
        cv.disc('core', scr(P, 14), 2.2, 0.8, 1.0, 0)


@effect('berserker_cleave', 3, 7, 70, 'berserker: a huge crimson crescent falls overhead and splits the ground (Skyfall Cleave)')
def berserker_cleave(cv, t, R):
    P = C64
    if t >= 6:
        return
    if t <= 2:
        st = -2.4 + t * 0.9
        H = scr(P, 12 - t * 3)
        cv.ring('blood', H, 15, 4.2, st, 2.2, 0.7, taper=True)
        cv.ring('core', H, 15, 1.2, st + 0.4, 1.4, 0.95, taper=True)
    if t >= 2:
        g = min(1.0, (t - 1) / 2)
        a = -math.pi / 4
        pts = [pol(P, -16 * g, a), pol(P, -6 * g, a + 0.15), P, pol(P, 7 * g, a - 0.15), pol(P, 15 * g, a)]
        cv.line('rock', pts, 1.8 - 0.2 * (t - 2), 0.25)
        cv.line('blood', pts[1:-1], 0.7, 0.9 if t <= 4 else 0.5)
    if 2 <= t <= 4:
        for k, (a, r, _, s) in enumerate(flying(R, 9, 4, 14)):
            h = 12 * math.sin(math.pi * (t - 1.5) / 3.5) * (0.5 + s)
            cv.disc('blood', scr(pol(P, r * (t - 1) / 3, a), max(h, 0)), 1.1, 0.6, 0.95, 0.3)
    if t == 2:
        cv.disc('core', P, 3.0, 0.7, 1.0, 0)


# ---- Ranger line: amber, leaf and wind
@effect('ranger_pierce', 3, 7, 70, 'ranger: a fletched arrow strikes and splits; feathers and amber splinters burst (Dawnpiercer)')
def ranger_pierce(cv, t, R):
    P = C64
    if t >= 6:
        return
    H = scr(P, 10)
    a = -0.75 * math.pi
    tail = pol(H, 14, a)
    if t <= 3:
        cv.capsule('amber', tail, H, 0.9, 0.9, 0.55, 0.75)
        cv.tri('steel', pol(H, 2.8, a + math.pi), pol(H, 2.0, a + math.pi / 2), pol(H, 2.0, a - math.pi / 2), 0.8, 0.2)
        for s in (-1, 1):
            cv.tri('leaf', tail, pol(tail, 4, a - 0.6 * s), pol(pol(tail, 3, a), 2.5, a - 1.2 * s), 0.6, 0.2)
    if t <= 1:
        cv.ring('core', H, 3 + 3 * t, 1.2, val=0.95)
    if 1 <= t <= 5:
        for k, (b, r, _, s) in enumerate(flying(R, 7, 6, 15)):
            c = scr(pol(P, r * t / 4, b), 10 - t * 1.6)
            if k % 2:
                leaf(cv, 'leaf', c, 0.8 + 0.3 * s, b + t * 0.6, 0.75)
            else:
                cv.capsule('amber', c, pol(c, 3, b + t), 0.6, 0.4, 0.7, 0.9)
    if 1 <= t <= 3:
        cv.arcs('wind', P, 6 + t * 3, 1.0, 4, t * 0.8, 0.4, 0.8)


@effect('ranger_arrowfall', 1, 6, 80, 'ranger: two arrows drop steeply and stick in the ground, a puff of dust (Hail of Dawn, each tile)', area=True)
def ranger_arrowfall(cv, t, R):
    P = C32
    if t >= 5:
        return
    for k, (dx, dy) in enumerate(((-4, 2), (4, -2))):
        g = P + (dx, dy)
        land = min(1.0, (t + 1 - k * 0.5) / 2)
        if land <= 0:
            continue
        tip = scr(g, 9 * (1 - land))
        cv.capsule('amber', tip, scr(tip, 7), 0.5, 0.5, 0.6, 0.7)
        cv.dot('steel', tip, 0.7, 0.9)
        cv.tri('leaf', scr(tip, 7), scr(tip, 4) + (-1.5, 0), scr(tip, 4) + (1.5, 0), 0.6, 0.2)
        if land >= 1 and t - k <= 3:
            cv.arcs('rock', g, 2.5 + (t - k), 0.7, 3, k, 0.4, 0.5)


@effect('ranger_thornseal', 3, 8, 90, 'ranger: a ring of thorned vines grows from the earth, amber motes rise (Blessed Earth)')
def ranger_thornseal(cv, t, R):
    P = C64
    if t >= 7:
        return
    g = (0.3, 0.6, 0.9, 1, 1, 0.8, 0.5)[t]
    cv.ring('leaf', P, 13, 2.2, 0.2, TAU * g, 0.5)
    for k in range(10):
        a = 0.2 + k * TAU / 10
        if (a - 0.2) / TAU <= g:
            b = pol(P, 13, a)
            cv.tri('leaf', scr(b, 5 * g), pol(b, 1.5, a + math.pi / 2), pol(b, 1.5, a - math.pi / 2), 0.7, 0.2)
    if t >= 2:
        cv.arcs('amber', P, 8, 1.0, 3, t * 0.5, 0.45, 0.75)
    for a, r, h, s in flying(R, 8, 2, 12, 0, 1):
        hh = (t - 1 - s * 2) * 4
        if 0 < hh < 22:
            cv.dot('amber' if s < 0.5 else 'gold', scr(pol(P, r, a), hh), 0.9, 0.95)


@effect('ranger_canopy', 3, 8, 90, 'ranger: leaves whirl up into a canopy around the caster, a gust of wind (Lightward)')
def ranger_canopy(cv, t, R):
    P = C64
    if t >= 7:
        return
    leaves = [(k * TAU / 12, R.uniform(0.7, 1.1), R.random()) for k in range(12)]
    for a, s, k in leaves:
        ang = a + t * 0.7
        h = 3 + t * 3 * s + 4 * k
        r = 13 - t * 0.6
        if h < 26:
            leaf(cv, 'leaf' if k < 0.6 else 'amber', scr(pol(P, r, ang), h), 0.9 * s, ang + 1.2, 0.8)
    for k in range(2):
        if 1 <= t <= 5:
            cv.ring('wind', scr(P, 4 + 6 * k + t), 12 - k * 2, 1.0, t * 0.8 + k * 2, 2.2, 0.75, taper=True)
    if t == 3:
        cv.spark('core', scr(P, 20), 2.0)


@effect('deadeye_mark', 3, 7, 70, 'deadeye: a reticle closes on the target, then a piercing flash and cracks (Final Verdict)')
def deadeye_mark(cv, t, R):
    P = C64
    if t >= 6:
        return
    H = scr(P, 9)
    if t <= 3:
        r = (15, 11, 8, 6)[t]
        cv.arcs('blood', H, r, 1.5, 4, math.pi / 4 + t * 0.25, 0.55, 0.75)
        for k in range(4):
            a = k * math.pi / 2
            cv.capsule('amber', pol(H, r + 4, a), pol(H, r - 1, a), 0.8, 0.5, 0.75, 0.95)
        cv.dot('ember', H, 1.0, 0.95)
    else:
        cv.disc('core', H, 3.5 - (t - 4) * 1.2, 0.7, 1.0, 0)
        for k in range(6):
            a = k * TAU / 6 + 0.3
            cv.capsule('amber', pol(H, 3, a), pol(H, 9 + (t - 4) * 4, a), 1.0, 0.3, 0.75, 0.95)
        cv.arcs('blood', H, 7 + (t - 4) * 5, 1.2, 6, 0.2, 0.4, 0.6)


@effect('beast_spirit', 3, 8, 90, 'beastmaster: claw rakes tear the ground, paw prints and spirit wisps of amber and green (Wild Bond)')
def beast_spirit(cv, t, R):
    P = C64
    if t >= 7:
        return
    if t <= 4:
        g = min(1.0, (t + 1) / 2)
        for k in range(3):
            o = (k - 1) * 4.5
            a0 = P + (-8 + o, -9 - o)
            a1 = P + (8 + o, 6 - o)
            claw(cv, 'amber', a0, a0 + (a1 - a0) * g, 1.4, 0.85 if t <= 2 else 0.6)
    for k in range(4):
        a = k * TAU / 4 + 0.8
        if t >= 1 + k * 0.7 and t <= 6:
            c = pol(P, 12, a)
            cv.disc('rock', c, 1.6, 0.3, 0.5, 0.2)
            for j in range(3):
                cv.dot('rock', pol(c, 2.6, a + math.pi + (j - 1) * 0.6), 0.8, 0.45)
    for a, r, h, s in flying(R, 7, 3, 12, 0, 1):
        hh = (t - 1) * 4 + 6 * s
        if 2 < hh < 26 and t >= 2:
            c = scr(pol(P, r, a + t * 0.4), hh)
            cv.disc('soul' if s < 0.5 else 'amber', c, 1.4, 0.6, 1.0, 0.2)
            cv.capsule('soul' if s < 0.5 else 'amber', c, c + (1.5, 3.5), 0.8, 0.2, 0.6, 0.6)


# ---- Mystic line: prism, rose, and the three elements
@effect('mystic_mend', 3, 8, 90, 'mystic: prismatic petals spiral up and open, rose and cyan motes (Purifying Wellspring, Mirror Mend)')
def mystic_mend(cv, t, R):
    P = C64
    if t >= 7:
        return
    for k in range(8):
        a = k * TAU / 8 + t * 0.55
        r = 6 + t * 1.3
        h = 2 + t * 2.5 + (k % 2) * 3
        c = scr(pol(P, r, a), h)
        if h < 24:
            leaf(cv, 'rose' if k % 2 else 'prism', c, 1.1, a + math.pi / 2, 0.8)
    if 1 <= t <= 5:
        cv.ring('prism', scr(P, 2), 9 + t, 1.0, t, 2.6, 0.8, taper=True)
    for a, r, h, s in flying(R, 6, 2, 10, 0, 1):
        hh = t * 3.5 + 8 * s
        if t >= 2 and hh < 27:
            cv.spark('core' if s < 0.3 else 'prism', scr(pol(P, r, a), hh), 1.0)


@effect('elementalist_glyph', 3, 8, 90, 'elementalist: a rune circle in three arcs of fire, frost and storm turns and flares (Falling Pyre)')
def elementalist_glyph(cv, t, R):
    P = C64
    if t >= 7:
        return
    g = (0.4, 0.75, 1, 1, 1, 0.8, 0.45)[t]
    for k, mat in enumerate(('ember', 'frost', 'storm')):
        st = k * TAU / 3 + t * 0.35
        cv.ring(mat, P, 14 * g + 1, 2.0, st, TAU / 3 * 0.8, 0.7)
        cv.ring(mat, P, 8 * g + 1, 1.0, st + 1.0, TAU / 3 * 0.5, 0.8)
        tip = pol(P, 14 * g + 1, st + TAU / 6 * 0.8)
        if t >= 1:
            cv.tri(mat, pol(tip, 3, st), pol(tip, 2.4, st + 2.3), pol(tip, 2.4, st - 2.3), 0.85, 0.2)
    if 2 <= t <= 4:
        for k, mat in enumerate(('ember', 'frost', 'storm')):
            a = k * TAU / 3 - math.pi / 2
            cv.capsule(mat, scr(P, 2), scr(pol(P, 3, a), 10 + 3 * (t - 2)), 1.4, 0.5, 0.75, 0.95)
        cv.disc('core', scr(P, 6), 2.0 + (t == 3), 0.8, 1.0, 0)


@effect('illusion_mirror', 3, 8, 90, 'illusionist: four mirror panes rise around the target, a glint crosses them, they shatter (Hall of Mirrors)')
def illusion_mirror(cv, t, R):
    P = C64
    if t >= 7:
        return
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4 + t * 0.1
        b = pol(P, 11, a)
        if t <= 4:
            up = min(1.0, (t + 1) / 2.5)
            h0, h1 = 2, 2 + 16 * up
            u = np.array((-math.sin(a), math.cos(a))) * 3.5
            pts = [scr(b - u, h0), scr(b + u, h0), scr(b + u, h1), scr(b - u, h1)]
            cv.poly('prism', pts, 0.45, 0.25)
            cv.line('rose', pts + [pts[0]], 0.6, 0.75)
            if t == 3:
                cv.capsule('core', scr(b - u * 0.6, h0 + 4), scr(b + u * 0.6, h1 - 3), 0.6, 0.6, 1, 1)
        else:
            for j in range(4):
                c = scr(pol(b, (t - 4) * 4 + j, a + j), 10 - (t - 4) * 2 + j * 2)
                cv.tri('prism' if j % 2 else 'rose', pol(c, 2.2, j), pol(c, 1.8, j + 2.1), pol(c, 2.0, j + 4.0), 0.75, 0.2)


@effect('illusion_shatter', 3, 7, 70, 'illusionist: a figure breaks into glass shards of cyan and rose (Umbral Stride)')
def illusion_shatter(cv, t, R):
    P = C64
    if t >= 6:
        return
    H = scr(P, 10)
    if t <= 1:
        cv.ellipse('prism', H, 5.5, 9, 0, 0.45, 0.8)
        cv.line('rose', [H + (-3, -6), H + (1, -1), H + (-1, 3), H + (3, 8)], 0.5, 0.9)
    for k, (a, r, h, s) in enumerate(flying(R, 12, 6, 17, -6, 6)):
        if t >= 1:
            c = scr(pol(P, r * t / 4, a), 10 + h * t / 4 - (t > 3) * (t - 3) * 3)
            rot = a + t * (1 + s)
            cv.tri('prism' if k % 2 else 'rose', pol(c, 2.4, rot), pol(c, 1.6, rot + 2.3), pol(c, 2.0, rot + 4.2), 0.8, 0.25)
    if t == 1:
        cv.disc('core', H, 2.5, 0.8, 1, 0)


# ---- Thief line: smoke, ink, steel and sakura
@effect('thief_vanish', 3, 7, 80, 'thief: low smoke billows from the feet, two dagger glints spin out (Shadow Veil, Shadow Mend)')
def thief_vanish(cv, t, R):
    P = C64
    if t >= 6:
        return
    puffs = flying(R, 8, 3, 10, 0, 1)
    for a, r, h, s in puffs:
        g = (0.5, 0.9, 1.0, 1.0, 0.8, 0.5)[t]
        c = scr(pol(P, r * (0.6 + t * 0.15), a), 2 + h * 5 + t * 1.5)
        cv.disc('smoke', c, (2.2 + 2.4 * s) * g, 0.3, 0.75, 0.4)
    if 1 <= t <= 4:
        for k in range(2):
            a = k * math.pi + t * 1.3
            c = scr(pol(P, 6 + t * 2.5, a), 12 + t)
            blade(cv, 'steel', c, pol(c, 5, a + t * 1.7), 0.9, 0.8)


@effect('ninja_vanish', 3, 7, 70, 'ninja: an ink slash crosses the spot, ink drops and leaves whirl (Shadow Step)')
def ninja_vanish(cv, t, R):
    P = C64
    if t >= 6:
        return
    H = scr(P, 9)
    if t <= 3:
        g = min(1.0, (t + 1) / 2)
        for s in (-1, 1):
            a0 = H + (-10, -10 * s)
            a1 = H + (10, 10 * s)
            cv.capsule('ink', a0, a0 + (a1 - a0) * g, 0.6, 2.0 if t <= 1 else 1.2, 0.6, 0.9)
        if t == 1:
            cv.capsule('core', H + (-6, -6), H + (6, 6), 0.4, 0.4, 1, 1)
    for k, (a, r, h, s) in enumerate(flying(R, 10, 5, 15, 0, 1)):
        if t >= 1:
            c = scr(pol(P, r * t / 4, a + t * 0.3), 9 + 6 * h - t * 1.2)
            if k % 3 == 0:
                leaf(cv, 'leaf', c, 0.8, a + t, 0.6)
            else:
                cv.disc('ink', c, 1.3 - 0.15 * t, 0.5, 0.9, 0.2)


@effect('ninja_smoke', 1, 6, 90, 'ninja: a smoke bomb tile; grey puffs and a red spark (Smoke Bomb, each tile)', area=True)
def ninja_smoke(cv, t, R):
    P = C32
    if t >= 5:
        return
    for k, (a, r, h, s) in enumerate(flying(R, 3, 2, 8, 0, 1)):
        g = (0.5, 1.0, 1.0, 0.75, 0.45)[t]
        c = scr(pol(P, r, a), 2 + h * 4 + t)
        cv.disc('smoke', c, (2.6 + 1.6 * s) * g, 0.3, 0.75, 0.4)
    if t == 1:
        cv.spark('sakura', scr(P, 6), 1.5)


@effect('samurai_focus', 3, 8, 90, 'samurai: a blade gleam rises before the caster, crimson petals circle it (Bushido Focus)')
def samurai_focus(cv, t, R):
    P = C64
    if t >= 7:
        return
    if 1 <= t <= 4:
        b0 = scr(P + (3, 3), 2 + t * 2)
        blade(cv, 'steel', b0, scr(P + (3, 3), 18 + t * 2), 1.0, 0.85)
    if t == 3:
        cv.spark('core', scr(P + (3, 3), 18), 2.5)
    for k in range(9):
        a = k * TAU / 9 + t * 0.6
        h = 4 + (k % 3) * 5 + t * 1.5
        r = 12 - (k % 2) * 3
        if h < 26:
            leaf(cv, 'sakura', scr(pol(P, r, a), h), 0.8, a + t, 0.75)
    if t <= 5:
        cv.arcs('sakura', P, 10 + t * 0.8, 1.0, 3, t * 0.5, 0.5, 0.55)


@effect('samurai_parry', 3, 7, 70, 'samurai: crossed blades flash, sparks and a crescent of steel (Counter Stance)')
def samurai_parry(cv, t, R):
    P = C64
    if t >= 6:
        return
    H = scr(P, 11)
    if t <= 3:
        for s in (-1, 1):
            blade(cv, 'steel', H + (-8 * s, 8), H + (9 * s, -9), 1.0, 0.85)
    if t <= 2:
        cv.disc('core', H, 2.0 + t, 0.8, 1.0, 0)
    if 1 <= t <= 4:
        cv.ring('steel', H, 9 + t * 2, 1.6, -2.4 + t * 0.2, 1.8, 0.8, taper=True)
        sparks(cv, R, 5, H, 4 + t * 2, 9 + t * 3, ('sakura', 'core'))
    if t == 5:
        cv.arcs('sakura', H, 18, 0.9, 5, 0.4, 0.3, 0.6)


# ---- Necromancer line: soul green and void violet
@effect('necro_curse', 3, 8, 90, 'necromancer: a violet brand of runes closes on the target, a green skull mark sinks in (Withering Curse)')
def necro_curse(cv, t, R):
    P = C64
    if t >= 7:
        return
    r = (16, 12, 9, 8, 8, 7, 6)[t]
    cv.arcs('void', P, r, 1.6, 5, t * 0.3, 0.6, 0.7)
    for k in range(5):
        a = k * TAU / 5 + t * 0.3 + 0.3
        c = pol(P, r, a)
        cv.line('soul', [pol(c, 1.6, a + 1), c, pol(c, 1.6, a - 1)], 0.5, 0.8)
    if 2 <= t <= 5:
        H = scr(P, 16 - (t - 2) * 3)
        cv.disc('void', H, 3.2, 0.4, 0.8, 0.3)
        cv.capsule('void', H + (0, 2), H + (0, 4), 2.0, 1.5, 0.4, 0.6)
        for s in (-1, 1):
            cv.dot('soul', H + (1.3 * s, 0.4), 0.8, 0.95)
    if t >= 4:
        for k in range(3):
            c = scr(P + (k * 3 - 3, 0), 3 - (t - 4))
            cv.capsule('soul', c, c + (0, 2 + t - 4), 0.6, 0.3, 0.7, 0.8)


@effect('lich_rot', 3, 8, 90, 'lich: rot bubbles swell and burst on the target, green skull wisps rise (Soul Rot)')
def lich_rot(cv, t, R):
    P = C64
    if t >= 7:
        return
    for k, (a, r, h, s) in enumerate(flying(R, 7, 1, 9, 0, 1)):
        phase = t - s * 3
        if 0 <= phase <= 3:
            c = scr(pol(P, r, a), 2 + h * 6)
            if phase < 3:
                cv.disc('soul', c, 1.2 + phase * 0.9, 0.35, 0.85, 0.5)
                cv.dot('core', c + (-0.6 - phase * 0.3, -0.6 - phase * 0.3), 0.5, 0.95)
            else:
                cv.arcs('soul', c, 3.5, 0.8, 4, a, 0.4, 0.8)
    for k in range(2):
        hh = (t - 1 - k * 2) * 4
        if 0 < hh < 24:
            c = scr(pol(P, 4, k * math.pi + 1), 6 + hh)
            cv.disc('soul', c, 2.6, 0.4, 0.9, 0.3)
            for s in (-1, 1):
                cv.dot('shade', c + (0.9 * s, 0.2), 0.6, 0.3)
            cv.capsule('soul', c + (0, 2), c + (1.5, 6), 1.4, 0.3, 0.5, 0.5)
    if t <= 5:
        cv.arcs('void', P, 10, 1.0, 4, t * 0.25, 0.35, 0.5)


# ---- Monk line: chi, void and jade
@effect('monk_heel', 3, 7, 70, 'monk: a ring of chi sweeps at kick height, ember footfalls flare (Whirling Heel)')
def monk_heel(cv, t, R):
    P = C64
    if t >= 6:
        return
    H = scr(P, 7)
    cv.ring('chi', H, 11 + t * 0.8, 2.6, t * 1.1, 3.0 - t * 0.3, 0.7, taper=True)
    if t <= 4:
        cv.ring('core', H, 11 + t * 0.8, 0.9, t * 1.1 + 0.6, 1.8, 0.95, taper=True)
    for k in range(3):
        a = k * TAU / 3 + 0.5
        if t >= k and t <= k + 2:
            c = pol(P, 9, a)
            cv.ellipse('chi', c, 2.4, 1.3, a, 0.5, 0.95)
            cv.arcs('ember', c, 3 + (t - k) * 1.5, 0.8, 3, a, 0.4, 0.8)
    if 1 <= t <= 3:
        sparks(cv, R, 3, H, 9, 14, ('chi', 'core'))


@effect('shadowfist_mark', 3, 7, 80, 'shadowfist: five violet pressure points light up on the target, joined, then pulse (Pressure Points)')
def shadowfist_mark(cv, t, R):
    P = C64
    if t >= 6:
        return
    pts = [scr(P, h) + (dx, 0) for dx, h in ((0, 22), (-4, 15), (4, 15), (-2, 7), (3, 6))]
    lit = min(5, t + 2)
    for i in range(lit):
        cv.disc('void', pts[i], 1.8 if t <= 3 else 2.6, 0.6, 1.0, 0)
        if t >= 2:
            cv.dot('core', pts[i], 0.7, 1.0)
    if t >= 2:
        for a, b in ((0, 1), (0, 2), (1, 3), (2, 4), (1, 2)):
            if b < lit:
                cv.capsule('void', pts[a], pts[b], 0.45, 0.45, 0.5, 0.5)
    if t >= 4:
        cv.arcs('void', scr(P, 12), 8 + (t - 4) * 5, 1.2, 5, 0.3, 0.45, 0.75)


@effect('ironsage_ward', 3, 8, 90, 'iron sage: jade hexagon plates close into a dome over the target and crumble (Chi Ward)')
def ironsage_ward(cv, t, R):
    P = C64
    if t >= 7:
        return
    plates = [(a, h) for h in (4, 12, 20) for a in np.linspace(0, TAU, 6 if h < 20 else 3, endpoint=False) + h * 0.1]
    for i, (a, h) in enumerate(plates):
        due = i / len(plates) * 2.5
        if t < due:
            continue
        r = 11 if h < 20 else 4
        if t >= 5:
            c = scr(pol(P, r + (t - 4) * 2, a), h - (t - 4) * 3)
        else:
            c = scr(pol(P, r, a), h)
        cv.poly('jade', hexagon(c, 3.2 if h < 20 else 2.8, a), 0.6, 0.25)
        cv.line('bronze', hexagon(c, 3.2 if h < 20 else 2.8, a) + [hexagon(c, 3.2 if h < 20 else 2.8, a)[0]], 0.4, 0.7)
    if 2 <= t <= 4:
        cv.ring('jade', P, 13, 1.0, val=0.8)
        cv.spark('core', scr(P, 22), 1.5)


# ---- Templar line: gold and dawn white
@effect('templar_mend', 3, 8, 90, 'templar: a cross of gold light descends, feathers drift down (Vow of Mending, Lay on Hands)')
def templar_mend(cv, t, R):
    P = C64
    if t >= 7:
        return
    if t <= 4:
        h = (26, 20, 16, 15, 15)[t]
        c = scr(P, h)
        cv.capsule('gold', c + (0, -7), c + (0, 9), 1.6, 1.6, 0.55, 0.9)
        cv.capsule('gold', c + (-6, -2), c + (6, -2), 1.6, 1.6, 0.55, 0.9)
        cv.capsule('core', c + (0, -5), c + (0, 6), 0.5, 0.5, 1, 1)
    if t >= 2:
        cv.ring('gold', P, 10 + (t - 2) * 1.2, 1.2, t * 0.6, 4.6, 0.75, taper=True)
    for a, r, h, s in flying(R, 6, 3, 12, 0, 1):
        hh = 24 - (t - 1) * 3.5 - 6 * s
        if t >= 1 and 1 < hh < 27:
            c = scr(pol(P, r, a), hh)
            sw = math.sin(t + a) * 0.6
            cv.ellipse('core' if s < 0.4 else 'gold', c, 2.2, 0.9, 0.6 + sw, 0.6, 0.95)


@effect('inquisitor_zeal', 3, 8, 80, 'inquisitor: white-gold holy flames rise in a ring, sparks climb, a brand circle (Zealotry)')
def inquisitor_zeal(cv, t, R):
    P = C64
    if t >= 7:
        return
    g = (0.4, 0.8, 1.0, 1.0, 0.85, 0.6, 0.3)[t]
    for k in range(8):
        a = k * TAU / 8 + 0.2
        b = pol(P, 10, a)
        s = 0.8 + 0.3 * ((k * 5) % 3) / 2
        cv.tri('gold', scr(b, 18 * g * s), pol(b, 2.4, a + math.pi / 2), pol(b, 2.4, a - math.pi / 2), 0.6, 0.3)
        if t <= 4:
            cv.capsule('core', b, scr(b, 7 * g * s), 0.6, 0.3, 0.9, 1.0)
    cv.arcs('gold', P, 10, 1.4, 8, 0.0, 0.7, 0.5)
    for a, r, h, s in flying(R, 7, 2, 10, 0, 1):
        hh = (t - 1) * 4 + 8 * s
        if t >= 1 and 4 < hh < 27:
            cv.spark('gold' if s < 0.5 else 'core', scr(pol(P, r, a), hh), 1.0)


@effect('sentinel_aegis', 3, 8, 90, 'sentinel: three radiant wall panes rise around the caster under a dome of light (Aegis of Faith)')
def sentinel_aegis(cv, t, R):
    P = C64
    if t >= 7:
        return
    up = (0.3, 0.7, 1.0, 1.0, 1.0, 0.8, 0.45)[t]
    for k in range(3):
        a = math.pi * 0.25 + (k - 1) * 1.1
        b = pol(P, 12, a)
        u = np.array((-math.sin(a), math.cos(a))) * 4.5
        h1 = 3 + 17 * up
        pts = [scr(b - u, 2), scr(b + u, 2), scr(b + u, h1), scr(b, h1 + 3), scr(b - u, h1)]
        cv.poly('gold', pts, 0.5, 0.3)
        cv.line('core', [scr(b, 4), scr(b, h1)], 0.5, 1.0)
    if 2 <= t <= 5:
        cv.ring('gold', scr(P, 8), 14, 1.0, math.pi * 1.05, math.pi * 0.9, 0.9, taper=True)
        cv.spark('core', scr(P, 22), 1.5)
    if t <= 3:
        cv.arcs('gold', P, 12, 1.2, 6, 0.1, 0.6, 0.5)


# ---- snares (traps and mines) and vigils (banners)
@effect('snare_jaws', 3, 6, 70, 'snare: iron jaws snap shut on the tile, sparks and dust (Snare Trap, triggered)')
def snare_jaws(cv, t, R):
    P = C64
    if t >= 5:
        return
    close = (0.0, 0.6, 1.0, 1.0, 0.8)[t]
    for s in (-1, 1):
        R0 = 8
        base = scr(P, 3 + 7 * (1 - close)) if s < 0 else P
        cv.ring('steel', base, R0, 1.4, math.pi if s < 0 else 0.0, math.pi, 0.6)
        for k in range(5):
            a = (math.pi if s < 0 else 0.0) + (k + 0.5) * math.pi / 5
            b = pol(base, R0, a)
            cv.tri('steel', pol(base, R0 - 3.5, a), pol(b, 1.2, a + math.pi / 2), pol(b, 1.2, a - math.pi / 2), 0.8, 0.2)
    cv.disc('bronze', P, 1.6, 0.5, 0.9, 0.3)
    if t >= 2:
        sparks(cv, R, 4, scr(P, 3), 4, 10, ('ember', 'core'))
        cv.arcs('rock', P, 11 + t, 1.2, 5, t * 0.3, 0.4, 0.4)


@effect('snare_blast', 3, 7, 70, 'snare: a mine bursts; ember shards, iron fragments and smoke (Seeker Mine, Detonate Mines)')
def snare_blast(cv, t, R):
    P = C64
    if t >= 6:
        return
    if t <= 1:
        cv.disc('core', scr(P, 4), 4 + t * 3, 0.7, 1.0, 0)
        cv.disc('ember', scr(P, 4), 6 + t * 4, 0.6, 0.9, 0.2)
    for k, (a, r, h, s) in enumerate(flying(R, 10, 6, 16, 0, 1)):
        if t >= 1:
            c = scr(pol(P, r * t / 4, a), 4 + 10 * h * math.sin(math.pi * t / 6))
            if k % 2:
                cv.tri('steel', pol(c, 2, a), pol(c, 1.5, a + 2.2), pol(c, 1.7, a + 4.1), 0.6, 0.2)
            else:
                cv.capsule('ember', c, pol(c, 3, a + math.pi), 1.0, 0.3, 0.8, 0.95)
    if t >= 2:
        for a, r, h, s in flying(R, 5, 2, 8, 0, 1):
            cv.disc('smoke', scr(pol(P, r, a), 4 + t * 2 + h * 4), (2.5 + 2 * s) * (1.3 - t * 0.15), 0.3, 0.7, 0.4)


def vigil(cv, t, R, cloth, emblem):
    P = C64
    if t >= 7:
        return
    up = (0.3, 0.75, 1.0, 1.0, 1.0, 0.7, 0.35)[t]
    top = scr(P, 26 * up)
    cv.capsule('bronze', scr(P, 1), top, 0.9, 0.9, 0.5, 0.75)
    cv.dot('gold', top, 1.3, 0.9)
    wave = math.sin(t * 1.4) * 1.5
    if up >= 0.7:
        f0 = top + (1.5, 2)
        pts = [f0, f0 + (11, wave), f0 + (11, 9 + wave), f0 + (8, 7 + wave * 0.5), f0 + (5, 10), f0 + (0, 10)]
        cv.poly(cloth, pts, 0.55, 0.3)
        cv.line('gold', [pts[0], pts[1]], 0.5, 0.85)
        emblem(cv, f0 + (5.5, 4.5 + wave * 0.4))
    if t <= 4:
        cv.arcs(cloth, P, 6 + t * 2, 1.2, 4, t * 0.4, 0.5, 0.7)
    if t == 3:
        cv.spark('core', top, 2.0)


@effect('vigil_wrath', 3, 8, 90, 'vigil: a red war banner with a sword rises from the ground (Vigil of Wrath)')
def vigil_wrath(cv, t, R):
    vigil(cv, t, R, 'blood', lambda cv, c: cv.capsule('core', c + (0, -3), c + (0, 3), 0.6, 0.6, 1, 1))


@effect('vigil_iron', 3, 8, 90, 'vigil: a steel banner with a shield rises from the ground (Vigil of Iron)')
def vigil_iron(cv, t, R):
    vigil(cv, t, R, 'steel', lambda cv, c: cv.poly('gold', shield_pts(c, 2.2, 3), 0.8, 0.2))


@effect('vigil_haste', 3, 8, 90, 'vigil: a green banner with a wing rises from the ground (Vigil of Haste)')
def vigil_haste(cv, t, R):
    vigil(cv, t, R, 'leaf', lambda cv, c: cv.tri('core', c + (-3, 2), c + (3, -3), c + (2, 2), 0.9, 0.1))


@effect('vigil_clarity', 3, 8, 90, 'vigil: a blue banner with an eye rises from the ground (Vigil of Clarity)')
def vigil_clarity(cv, t, R):
    vigil(cv, t, R, 'frost', lambda cv, c: (cv.ellipse('core', c, 3, 1.6, 0, 0.8, 1), cv.dot('frost', c, 0.9, 0.3)))


# ------------------------------------------------------------------------------------------------ build and checks
def seed_of(name):
    return sum((i + 1) * ord(ch) for i, ch in enumerate(name)) * 7919 + 17


def frames_of(e):
    N = 32 * e['tiles']
    out = []
    for t in range(e['frames']):
        cv = Canvas(N)
        e['fn'](cv, t, random.Random(seed_of(e['name'])))
        out.append(cv.finish())
    return out


def check(e, frames):
    errs = []
    N = 32 * e['tiles']
    for t, f in enumerate(frames):
        a = f[:, :, 3]
        if not set(np.unique(a)) <= {0, 255}:
            errs.append(f'frame {t}: alpha not 0/255')
        if t < len(frames) - 1 and not a.any():
            errs.append(f'frame {t}: empty')
        if t == len(frames) - 1 and a.any():
            errs.append('last frame not empty')
        if a[0].any() or a[-1].any() or a[:, 0].any() or a[:, -1].any():
            errs.append(f'frame {t}: touches the edge')
        if e['area'] and (a == 0).mean() < 0.65:
            errs.append(f'frame {t}: only {(a == 0).mean():.0%} transparent (area effect)')
    return errs


def strip_png(frames):
    im = Image.fromarray(np.concatenate(frames, axis=1), 'RGBA')
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def spec_rows():
    rows = []
    for e in EFFECTS:
        off = e['tiles'] // 2      # 3x3: the target is the centre tile, sent at the target + (1, 1)
        rows.append(['effect', e['name'], f"class_fx/{e['name']}.png", e['tiles'], e['tiles'], e['frames'], e['ms'], off,
                     off, e['note']])
    return rows


def spec_text():
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(['kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note'])
    w.writerows(spec_rows())
    return buf.getvalue()


def build(check_only=False):
    names = [e['name'] for e in EFFECTS]
    assert len(set(names)) == len(names), 'duplicate effect name'
    bad = 0
    os.makedirs(OUT, exist_ok=True)
    for e in EFFECTS:
        frames = frames_of(e)
        errs = check(e, frames)
        for x in errs:
            print(f"{e['name']}: {x}")
        bad += len(errs)
        path = os.path.join(OUT, e['name'] + '.png')
        if check_only:
            if not os.path.exists(path):
                print(f"{e['name']}: strip missing"); bad += 1
                continue
            old = np.asarray(Image.open(path).convert('RGBA'))
            if not np.array_equal(old, np.concatenate(frames, axis=1)):
                print(f"{e['name']}: strip differs from the generator"); bad += 1
        else:
            open(path, 'wb').write(strip_png(frames))
    if check_only:
        if not os.path.exists(SPEC) or open(SPEC).read() != spec_text():
            print('class_fx.csv differs from the generator'); bad += 1
        extra = sorted(set(f[:-4] for f in os.listdir(OUT) if f.endswith('.png')) - set(names)) if os.path.isdir(OUT) else []
        for x in extra:
            print(f'{x}.png: not made by the generator'); bad += 1
    else:
        open(SPEC, 'w').write(spec_text())
    print(f"{len(EFFECTS)} effects, {sum(e['frames'] for e in EFFECTS)} frames: {'OK' if not bad else f'{bad} problems'}")
    return bad == 0


# ------------------------------------------------------------------------------------------------ previews
BG = (24, 22, 28, 255)
SCENES = [   # (title, vocation id, [(effect, 'caster' | 'target' | 'area')])  -- as server/data/lib/chaos_class_fx.lua
    ('Warrior', 4, [('warrior_quake', 'caster'), ('warrior_gyre', 'caster'), ('warrior_bellow', 'caster')]),
    ('Juggernaut', 8, [('juggernaut_bulwark', 'caster'), ('warrior_quake', 'target')]),
    ('Berserker', 14, [('berserker_rage', 'caster'), ('berserker_cleave', 'target')]),
    ('Ranger', 3, [('ranger_pierce', 'target'), ('ranger_arrowfall', 'area'), ('ranger_canopy', 'caster')]),
    ('Deadeye', 7, [('deadeye_mark', 'target'), ('ranger_thornseal', 'caster')]),
    ('Beastmaster', 15, [('beast_spirit', 'caster'), ('ranger_pierce', 'target')]),
    ('Mystic', 1, [('mystic_mend', 'caster'), ('illusion_mirror', 'target')]),
    ('Elementalist', 5, [('elementalist_glyph', 'target'), ('mystic_mend', 'caster')]),
    ('Illusionist', 10, [('illusion_shatter', 'caster'), ('illusion_mirror', 'target'), ('mystic_mend', 'caster')]),
    ('Thief', 11, [('thief_vanish', 'caster')]),
    ('Ninja', 12, [('ninja_vanish', 'caster'), ('ninja_smoke', 'area')]),
    ('Samurai', 13, [('samurai_focus', 'caster'), ('samurai_parry', 'caster')]),
    ('Necromancer', 20, [('necro_curse', 'target')]),
    ('Lich', 21, [('lich_rot', 'target'), ('necro_curse', 'target')]),
    ('Bone Lord', 22, [('necro_curse', 'target')]),
    ('Monk', 17, [('monk_heel', 'caster')]),
    ('Shadowfist', 18, [('shadowfist_mark', 'target'), ('monk_heel', 'caster')]),
    ('Iron Sage', 19, [('ironsage_ward', 'caster'), ('monk_heel', 'caster')]),
    ('Templar', 23, [('templar_mend', 'caster')]),
    ('Inquisitor', 24, [('inquisitor_zeal', 'caster'), ('templar_mend', 'caster')]),
    ('Sentinel', 25, [('sentinel_aegis', 'caster'), ('templar_mend', 'target')]),
    ('Snares and vigils', 3, [('snare_jaws', 'target'), ('snare_blast', 'area1'), ('vigil_wrath', 'v1'),
                              ('vigil_iron', 'v2'), ('vigil_haste', 'v3'), ('vigil_clarity', 'v4')]),
]
LOOKS = {4: 2073, 8: 2161, 14: 2075, 3: 2163, 7: 2045, 15: 2165, 1: 2060, 5: 2062, 10: 2049, 11: 2175, 12: 2177,
         13: 2071, 20: 2183, 21: 2173, 22: 2167, 17: 2080, 18: 2169, 19: 2055, 23: 2179, 24: 2181, 25: 2171}
TARGET_LOOK = 2100      # a rift minion (things_custom11 picks)


def ground(cols, rows):
    rng = random.Random(7)
    im = Image.new('RGBA', (cols * 32, rows * 32), BG)
    a = np.asarray(im).copy()
    for y in range(rows):
        for x in range(cols):
            base = 52 + rng.randint(-5, 5)
            tile = np.full((32, 32, 3), (base, base - 6, base - 12), np.int16)
            noise = np.array([[rng.randint(-6, 6) for _ in range(32)] for _ in range(32)])
            tile += noise[:, :, None]
            tile[0, :] -= 14
            tile[:, 0] -= 14
            a[y * 32:(y + 1) * 32, x * 32:(x + 1) * 32, :3] = np.clip(tile, 0, 255)
    return Image.fromarray(a.astype(np.uint8), 'RGBA')


_CACHE = {}


def frames_img(name):
    e = next(x for x in EFFECTS if x['name'] == name)
    if name not in _CACHE:
        _CACHE[name] = [Image.fromarray(f, 'RGBA') for f in frames_of(e)]
    return e, _CACHE[name]


def place(canvas, img, tx, ty, ox=0, oy=0):
    """the client's rule: the art's bottom-right tile on the map tile (tx, ty)"""
    canvas.alpha_composite(img, (tx * 32 + 32 - img.width + ox, ty * 32 + 32 - img.height + oy))


def creature(dat, spr, look, direction):
    if dat is None:
        return None
    from datspr import render_outfit
    t = dat.outfit(look)
    if t is None:
        return None
    im = render_outfit(dat, spr, look, direction=direction, layers='base')
    disp = getattr(t, 'flags', {}).get('displacement') if hasattr(t, 'flags') else None
    if isinstance(disp, (tuple, list)) and len(disp) == 2:
        return im, int(disp[0]), int(disp[1])
    return im, 0, 0


def sheet(out, scale=3):
    """every effect frame by frame, on a ground tile grid, scaled; one row per effect"""
    from PIL import ImageFont
    font = ImageFont.load_default()
    rows = []
    for e in EFFECTS:
        _, frames = frames_img(e['name'])
        N = 32 * e['tiles']
        cell = 96 * scale
        row = Image.new('RGBA', (220 + e['frames'] * (cell + 6), cell + 20), (12, 12, 16, 255))
        d = ImageDraw.Draw(row)
        d.text((6, 6), e['name'], fill=(255, 220, 120, 255), font=font)
        d.text((6, 22), f"{e['tiles']}x{e['tiles']}, {e['frames']} x {e['ms']} ms", fill=(190, 190, 200, 255), font=font)
        words, line, y = e['note'].split(' '), '', 40
        for w in words:
            if len(line) + len(w) > 32:
                d.text((6, y), line, fill=(150, 150, 160, 255), font=font); y += 12; line = ''
            line += w + ' '
        d.text((6, y), line, fill=(150, 150, 160, 255), font=font)
        g = ground(3, 3)
        for t, f in enumerate(frames):
            c = g.copy()
            o = e['tiles'] // 2
            place(c, f, 1 + o, 1 + o)
            ImageDraw.Draw(c).rectangle([32, 32, 63, 63], outline=(200, 80, 80, 255))
            c = c.resize((cell, cell), Image.NEAREST)
            row.alpha_composite(c, (220 + t * (cell + 6), 10))
            d.text((224 + t * (cell + 6), 12), str(t), fill=(255, 255, 255, 255), font=font)
        rows.append(row)
    W = max(r.width for r in rows)
    sh = Image.new('RGBA', (W, sum(r.height for r in rows)), (12, 12, 16, 255))
    y = 0
    for r in rows:
        sh.alpha_composite(r, (0, y)); y += r.height
    sh.convert('RGB').save(os.path.join(out, 'class_fx_frames.png'))
    for e in EFFECTS:     # one sheet per effect as well
        _, frames = frames_img(e['name'])
        cell = 96 * 4
        im = Image.new('RGBA', (e['frames'] * (cell + 4), cell), (12, 12, 16, 255))
        for t, f in enumerate(frames):
            c = ground(3, 3)
            o = e['tiles'] // 2
            place(c, f, 1 + o, 1 + o)
            im.alpha_composite(c.resize((cell, cell), Image.NEAREST), (t * (cell + 4), 0))
        im.convert('RGB').save(os.path.join(out, 'frames', e['name'] + '.png'))


def scenes(out, dat, spr, scale=2):
    from PIL import ImageFont
    font = ImageFont.load_default()
    cols, rows = 9, 6
    panels = []
    for title, voc, fx in SCENES:
        snaps = []
        peak = {}
        for name, where in fx:
            e, frames = frames_img(name)
            peak[name] = frames[max(1, len(frames) // 2 - 1)]
        img = ground(cols, rows)
        caster, target = (2, 3), (6, 3)
        area = [(x, y) for x in range(5, 8) for y in range(2, 5)]
        cl = creature(dat, spr, LOOKS.get(voc, 128), 'east') if voc else None
        tl = creature(dat, spr, TARGET_LOOK, 'west')
        under = []
        for name, where in fx:
            e = next(x for x in EFFECTS if x['name'] == name)
            if where == 'caster':
                under.append((peak[name], caster))
            elif where == 'target':
                under.append((peak[name], target))
            elif where == 'area':
                for i, p in enumerate(area):
                    _, frames = frames_img(name)
                    under.append((frames[(i % 3) + 1], p))
            elif where == 'area1':
                under.append((peak[name], (4, 1)))
            elif where.startswith('v'):
                k = int(where[1:])
                under.append((peak[name], (k * 2 - 1, 5)))
        # creatures first, then the effects (the client draws effects over creatures on the same tile)
        for look, p in ((cl, caster), (tl, target)):
            if look:
                im, dx, dy = look
                place(img, im, p[0], p[1], -dx, -dy)
            else:
                d = ImageDraw.Draw(img)
                x, y = p[0] * 32, p[1] * 32
                d.ellipse([x + 8, y + 4, x + 24, y + 30], fill=(90, 90, 110, 255), outline=(20, 20, 30, 255))
        for im, p in under:
            o = (im.width // 32) // 2
            place(img, im, p[0] + o, p[1] + o)
        big = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
        panel = Image.new('RGBA', (big.width, big.height + 18), (12, 12, 16, 255))
        panel.alpha_composite(big, (0, 18))
        ImageDraw.Draw(panel).text((6, 3), f"{title}: " + ', '.join(n for n, _ in fx), fill=(255, 220, 120, 255),
                                   font=font)
        panel.convert('RGB').save(os.path.join(out, 'scenes', title.lower().replace(' ', '_') + '.png'))
        panels.append(panel)
    per = 3
    W = per * (panels[0].width + 6)
    H = ((len(panels) + per - 1) // per) * (panels[0].height + 6)
    board = Image.new('RGBA', (W, H), (8, 8, 10, 255))
    for i, p in enumerate(panels):
        board.alpha_composite(p, ((i % per) * (p.width + 6), (i // per) * (p.height + 6)))
    board.convert('RGB').save(os.path.join(out, 'class_fx_scenes.png'))


def preview(out, dat_path=None, spr_path=None):
    os.makedirs(os.path.join(out, 'frames'), exist_ok=True)
    os.makedirs(os.path.join(out, 'scenes'), exist_ok=True)
    dat = spr = None
    if dat_path and spr_path:
        sys.path.insert(0, HERE)
        from datspr import Dat, Spr
        dat, spr = Dat(dat_path), Spr(spr_path)
    sheet(out)
    scenes(out, dat, spr)
    print('previews in', out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    p.add_argument('--dat')
    p.add_argument('--spr')
    a = ap.parse_args()
    if a.cmd == 'build':
        sys.exit(0 if build(a.check) else 1)
    preview(a.out, a.dat, a.spr)


if __name__ == '__main__':
    main()
