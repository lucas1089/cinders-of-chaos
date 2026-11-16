#!/usr/bin/env python3
"""Families of code-drawn wings (O583): one generator per shape class, each read from a row of drawn_wings/designs.csv.

A row names a family and a variant, three colours (main, accent, glow), a spark kind, a count and a size. The kit, the
projection and the frame rules are gen_drawn_wings.py's; this file only places pieces. Every motion reads the frame
phase, so every design loops in 16 frames. No art file is read.

Families: feather, bone, bat, insect, crystal, fan, leaf, energy, orbit (variants: VARIANTS below).
"""
import colorsys
import csv
import math
import os

import numpy as np

import gen_drawn_wings as k

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, 'drawn_wings', 'designs.csv')
S = k.SIZE
TAU = k.TAU
rad = k.rad
sin, cos = math.sin, math.cos

VARIANTS = {
    'feather': ('pinion', 'angel', 'owl', 'swift', 'plume', 'peacock', 'seraph', 'scaled'),
    'bone': ('rib', 'finger', 'wire'),
    'bat': ('bat', 'dragon', 'torn', 'demon', 'gargoyle'),
    'insect': ('butterfly', 'moth', 'dragonfly', 'fairy', 'beetle', 'ray'),
    'crystal': ('shard', 'cluster', 'needle', 'flake', 'prism', 'pane', 'drop'),
    'fan': ('blade', 'slat', 'web', 'tile', 'ribbon', 'pipe', 'kite'),
    'leaf': ('oval', 'needle', 'petal', 'maple', 'fern', 'flower'),
    'energy': ('flame', 'cloud', 'bolt', 'water', 'ray', 'spiral', 'veil'),
    'orbit': ('firefly', 'circle'),
}
SPARKS = ('none', 'rise', 'fall', 'twinkle')


# ------------------------------------------------------------------------------------------------ colour
def rgb(text):
    text = text.strip().lstrip('#')
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


def ramp5(colour):
    """five shades round a colour, dark to light: shadows more saturated and cooler, lights paler and warmer"""
    h, s, v = colorsys.rgb_to_hsv(colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0)
    step = max(0.1, min(0.15, v * 0.2))
    v = k.clamp(v, 0.12 + 2 * step, 1.0 - step)             # a pale colour sits one shade under the light end
    out = []
    for i in (-2, -1, 0, 1, 2):
        vv = k.clamp(v + i * step, 0.0, 1.0)
        ss = k.clamp(s * (1.0 - 0.16 * i), 0.0, 1.0)
        hh = h
        if s > 0.08:
            hh = (h - 0.018 * i * (1 if ((h - 0.11) % 1.0) < 0.5 else -1)) % 1.0
        elif i < 0:
            hh, ss = 0.66, 0.1 * -i                         # a grey or white gets a cool shadow
        r, g, b = colorsys.hsv_to_rgb(hh, ss, vv)
        out.append((int(round(r * 255)), int(round(g * 255)), int(round(b * 255))))
    return tuple(out)


def outline_of(colour):
    h, s, v = colorsys.rgb_to_hsv(colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0)
    r, g, b = colorsys.hsv_to_rgb((h + 0.03) % 1.0 if s > 0.08 else 0.72, max(s, 0.35) * 0.9, 0.13)
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


def hue_turn(colour, turn):
    h, s, v = colorsys.rgb_to_hsv(colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0)
    r, g, b = colorsys.hsv_to_rgb((h + turn) % 1.0, max(s, 0.5), max(v, 0.6))
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


class Spec:
    """one row of designs.csv"""

    def __init__(self, row):
        self.wings = int(row['wings'])
        self.look = int(row['look'])
        self.key = row['key']
        self.name = row['name']
        self.family = row['family']
        self.var = row['variant']
        self.main = rgb(row['main'])
        self.accent = rgb(row['accent'])
        self.glow = rgb(row['glow'])
        self.spark = row['spark']
        self.n = int(row['n'])
        self.size = float(row['size'])
        self.old = row.get('old', '')
        self.R = ramp5(self.main)
        self.A = ramp5(self.accent)
        self.outline = outline_of(self.main)
        self.jit = (self.wings * 0.6180339887) % 1.0       # a fixed offset a row, so two rows never move in step
        self.PAL = self.R + self.A + (self.glow,)          # one table for two-colour pieces: 0-4 main, 5-9 accent, 10 glow
        if self.family not in VARIANTS or self.var not in VARIANTS[self.family]:
            raise ValueError('%s: no variant %s/%s' % (self.key, self.family, self.var))
        if self.spark not in SPARKS:
            raise ValueError('%s: no spark kind %s' % (self.key, self.spark))


def load(path=CSV):
    with open(path, newline='', encoding='utf-8') as f:
        return [Spec(row) for row in csv.DictReader(f)]


# ------------------------------------------------------------------------------------------------ helpers
ROOT = (3.0, 9.0, -3.5)


def sides(sc, sweep, elev_at, length, root=ROOT):
    """the two wings, the far one first: (side, wing, canvas, dim)"""
    for sgn in k.sides_far_first(sc.d):
        wing = k.Wing(sgn, (sgn * root[0], root[1], root[2]), rad(sweep), elev_at, length)
        yield sgn, wing, sc.layer(sc.P(wing.at(length * 0.4, 0))[2]), k.side_dim(sc.d, sgn)


def lfeather(sc, canvas, wing, a, b, ang, ln, hw, knots, shader, ramp, bend=0.0, dim=0, minw=1.2):
    base = wing.at(a, b)
    tip = wing.at(a + ln * cos(ang), b + ln * sin(ang))
    return sc.leaf3(canvas, base, tip, wing.wdir(a, ang), hw, knots, shader, ramp, bend=bend * wing.sgn, dim=dim, minw=minw)


def lpts(sc, wing, pts):
    return [sc.P(wing.at(a, b))[:2] for a, b in pts]


def lline(sc, wing, pts, hw0, hw1, knob0=0.0, knob1=0.0):
    """mask of a thick line through local points"""
    m = np.zeros((S, S), bool)
    sp = lpts(sc, wing, pts)
    n = len(sp) - 1
    for i in range(n):
        m |= k.capsule_mask(sp[i], sp[i + 1], hw0 + (hw1 - hw0) * i / n, hw0 + (hw1 - hw0) * (i + 1) / n)
    if knob0:
        m |= k.disc_mask(sp[0][0], sp[0][1], knob0)
    if knob1:
        m |= k.disc_mask(sp[-1][0], sp[-1][1], knob1)
    return m


def lbone(sc, canvas, wing, pts, hw0, hw1, ramp, dim=0, knob0=0.0, knob1=0.0, shade=(4, 3, 1)):
    m = lline(sc, wing, pts, hw0, hw1, knob0, knob1)
    canvas.piece(m, k.edge_shade(m, *shade) - dim, ramp)


def motes(sc, canvas, wing, pts, sp, sgn, count=2, reach=14.0):
    """sparks from local points of the mean pose: they rise, fall or twinkle"""
    if sp.spark == 'none' or not pts:
        return
    for i in range(count):
        a, b = pts[(i * 2 + (1 if sgn > 0 else 0)) % len(pts)]
        x, y, _ = sc.P(wing.at(a, b))
        q = (sc.f / k.FRAMES + i / float(count) + sp.jit + (0.29 if sgn > 0 else 0.0)) % 1.0
        if sp.spark == 'twinkle':
            g = cos(TAU * q)
            if g > 0.55:
                canvas.spark(x, y, sp.glow, 2 if g > 0.93 else 1)
            continue
        x += 2.0 * sin(TAU * (q * 1.2 + i * 0.37))
        y += -reach * q if sp.spark == 'rise' else 3 + reach * q
        if q < 0.4:
            canvas.spark(x, y, sp.glow, 1)
        elif q < 0.8:
            canvas.spark(x, y, sp.glow, 0)


def arch(length, lift=3.6):
    def edge(s):
        return length * s, -lift * sin(math.pi * min(s, 1.0)) ** 0.8
    return edge


# ------------------------------------------------------------------------------------------------ feather
PLUME = ((0.0, 0.3), (0.1, 0.7), (0.28, 1.0), (0.55, 0.86), (0.8, 0.5), (1.0, 0.0))
FEATHER_VARS = {
    #          span  sweep elev amp  primaries (n, len, hw, first angle, step)  secondaries (n, len, grow, hw)  coverts
    'pinion': (22.0, 42, 30, 22, (6, 21.0, 2.8, 66, 12), (5, 13.0, 2.0, 2.9), 7),
    'angel': (24.0, 40, 34, 20, (7, 22.0, 2.9, 72, 11), (6, 14.0, 2.0, 3.0), 8),
    'owl': (17.0, 38, 26, 18, (5, 14.5, 3.4, 70, 14), (4, 10.0, 1.3, 3.3), 5),
    'swift': (26.0, 50, 26, 22, (5, 20.0, 2.3, 42, 8), (4, 8.0, 1.5, 2.5), 6),
    'scaled': (21.0, 40, 30, 18, (5, 14.0, 3.3, 64, 13), (6, 8.5, 1.0, 3.3), 0),
}


def feather_shaders(sp, bars=False):
    def body(tt, ss, lit, hw):
        idx = np.select([tt < 0.36, tt < 0.62, tt < 0.84], [1, 2, 3], 4).astype(np.int8)
        idx = idx - (~lit).astype(np.int8)
        if bars:
            idx = idx - (((tt * 6).astype(np.int32) % 2) == 1)
        return idx

    def covert(tt, ss, lit, hw):
        return np.where(lit, 2, 1).astype(np.int8) + (tt > 0.72)
    return body, covert


def feather_wing(sc, canvas, wing, sp, var, dim, wph, scale=1.0):
    span, sweep, elev, amp, prim, sec, ncov = FEATHER_VARS[var]
    F = (sp.R[0], sp.R[1], sp.R[2], sp.A[2], sp.A[3])
    C = (k.EMBER_OUT if False else sp.R[0], sp.R[0], sp.R[1], sp.R[2], sp.R[3])
    body, covert = feather_shaders(sp, bars=(var == 'owl'))
    length = span * scale
    edge = arch(length)
    spread = 1.0 + 0.16 * sin(wph - 0.6)
    n, ln, hw, a0, st = prim
    n = max(4, min(8, n + sp.n))
    tips = []
    for j in range(n - 1, -1, -1):
        ang = rad((a0 - st * j * 6.0 / n) * spread - 6)
        a, b = edge(0.60 + 0.4 * j / n)
        lfeather(sc, canvas, wing, a, b, ang, (ln - 0.9 * j) * scale, hw, k.FEATHER, body, F, bend=1.4, dim=dim)
        tips.append((a + (ln - 0.9 * j) * scale * 0.85 * cos(ang), b + (ln - 0.9 * j) * scale * 0.85 * sin(ang)))
    m, sl, grow, shw = sec
    for i in range(m - 1, -1, -1):
        a, b = edge(0.10 + 0.5 * i / m)
        lfeather(sc, canvas, wing, a, b, rad(96 - 7 * i), (sl + grow * i) * scale, shw, k.FEATHER, body, F, bend=0.6, dim=dim)
    if var == 'scaled':                                   # a second, shorter row of scales over the first
        for i in range(8, -1, -1):
            a, b = edge(0.08 + 0.105 * i)
            lfeather(sc, canvas, wing, a, b, rad(88 - 7 * i), 7.5 * scale, 3.2, k.FEATHER, body, F, dim=dim)
    for c in range(ncov - 1, -1, -1):
        a, b = edge(0.06 + 0.86 * c / max(1, ncov - 1))
        lfeather(sc, canvas, wing, a, b, rad(84 - 8 * c * 6.0 / max(1, ncov - 1)), 6.5 * scale, 2.4, k.FEATHER, covert, C, dim=dim)
    pts = [edge(i / 8.0) for i in range(9)]
    arm_ramp = sp.A if var == 'scaled' else C
    lbone(sc, canvas, wing, [(a, b - 0.6) for a, b in pts], 1.7 * scale, 1.0 * scale, arm_ramp, dim, shade=(3, 2, 1))
    return tips


def fam_feather(sc, sp):
    ph = sc.ph
    wph = ph + 0.35 * sin(ph) + TAU * sp.jit * 0.0
    var = sp.var
    if var in ('plume', 'peacock'):
        return plume_wings(sc, sp)
    base = 'pinion' if var == 'seraph' else var
    span, sweep, elev, amp = FEATHER_VARS[base][:4]
    scale = sp.size * (0.84 if var == 'seraph' else 1.0)
    for sgn, wing, canvas, dim in sides(sc, sweep, lambda s: rad(elev + (8 if var == 'seraph' else 0)) + rad(amp) * sin(wph - 0.9 * s),
                                        span * scale):
        if var == 'seraph':                               # a small second pair below, half a beat behind
            low = k.Wing(sgn, wing.root, rad(sweep + 6), lambda s: rad(-16) + rad(14) * sin(wph - 1.2 - 0.9 * s), span * 0.56)
            feather_wing(sc, canvas, low, sp, base, dim, wph - 1.2, 0.56 * sp.size)
        tips = feather_wing(sc, canvas, wing, sp, base, dim, wph, scale)
        if var == 'scaled':
            x, y, _ = sc.P(wing.at(1.5, 0.5))
            m = k.disc_mask(x, y, 2.6)
            canvas.piece(m, k.sphere_shade(x, y, 3.1), ramp5(sp.glow))
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(elev), span * scale)
        motes(sc, canvas, mean, tips, sp, sgn, 3)


def plume_wings(sc, sp):
    """long pointed plumes that stand up from the shoulder, no arm"""
    ph = sc.ph
    n = max(4, min(7, 5 + sp.n))
    F = (sp.R[0], sp.R[1], sp.R[2], sp.A[2], sp.A[3])

    def shader(tt, ss, lit, hw):
        idx = np.select([tt < 0.3, tt < 0.62, tt < 0.86], [1, 2, 3], 4).astype(np.int8) - (~lit).astype(np.int8)
        rib = (np.abs(ss) * hw < 0.55) & (tt > 0.1) & (tt < 0.8) & (hw > 2.2)
        idx[rib] -= 1
        return idx

    for sgn, wing, canvas, dim in sides(sc, 34, lambda s: rad(24) + rad(10) * sin(ph - 0.6 * s), 22.0 * sp.size):
        tips = []
        order = sorted(range(n), key=lambda i: abs(i - 1.2), reverse=True)
        for i in order:
            u = i / float(n - 1)
            ang = rad(-62 + 104 * u + 5 * sin(ph - 0.7 * i))
            ln = (25.0 - 13.0 * abs(u - 0.22) ** 1.2) * sp.size
            got = lfeather(sc, canvas, wing, 1.0, 0.0, ang, ln, 3.3 - 0.8 * u, PLUME, shader, F,
                           bend=2.2 * sin(ph - 0.7 * i) + 1.5, dim=dim)
            tip = (1.0 + ln * 0.84 * cos(ang), ln * 0.84 * sin(ang))
            tips.append(tip)
            if sp.var == 'peacock' and got and i % 2 == 0:
                b, t = got
                x, y = b[0] + (t[0] - b[0]) * 0.8, b[1] + (t[1] - b[1]) * 0.8
                m = k.disc_mask(x, y, 2.3)
                idx = np.full((S, S), 6, np.int8)
                idx[k.disc_mask(x, y, 1.1)] = 10
                canvas.piece(m, idx, sp.PAL)
        for i in range(3):                                # short tuft at the root
            ang = rad(20 + 34 * i)
            lfeather(sc, canvas, wing, 0.5, 0.5, ang, 7.5 * sp.size, 2.4, PLUME, shader, F, dim=dim)
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(24), 22.0 * sp.size)
        motes(sc, canvas, mean, tips, sp, sgn, 3)


# ------------------------------------------------------------------------------------------------ bone
def fam_bone(sc, sp):
    ph = sc.ph
    length = 24.0 * sp.size
    z = sp.size
    arm = ((0.0, 0.0), (7.0 * z, -5.0 * z), (15.0 * z, -7.0 * z), (22.5 * z, -3.5 * z))
    for sgn, wing, canvas, dim in sides(sc, 36, lambda s: rad(24) + rad(13) * sin(ph - 0.8 * s), length):
        tips = []
        if sp.var == 'wire':                              # thin chains that hang in arcs, a shackle at each end
            n = max(3, min(6, 4 + sp.n))
            for i in range(n - 1, -1, -1):
                u = i / float(n - 1)
                end = ((22.0 - 9.0 * u) * z, (-6.0 + 17.0 * u) * z)
                sag = 3.0 + 1.2 * sin(ph - 0.7 * i)
                pts = [(end[0] * t, end[1] * t + sag * sin(math.pi * t)) for t in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0)]
                m = lline(sc, wing, pts, 0.9, 0.9)
                x, y = lpts(sc, wing, [end])[0]
                idx = k.edge_shade(m, 4, 3, 2)
                idx[((k.XX + k.YY) % 3) == 0] -= 2
                canvas.piece(m, idx - dim, sp.R)
                ring = k.disc_mask(x, y, 2.0)
                canvas.piece(ring, k.sphere_shade(x, y, 2.5), sp.A)
                tips.append(end)
        elif sp.var == 'finger':                          # a bare hand of long finger bones, a claw on each
            wrist = arm[2]
            n = max(3, min(5, 4 + sp.n))
            fingers = []
            for j in range(n):
                a0 = rad(-18 + 100.0 * j / (n - 1) + (4 + 2 * j) * sin(ph - 0.5 - 0.45 * j))
                ln = (17.0 - 1.6 * abs(j - 1)) * z
                mid = (wrist[0] + 0.55 * ln * cos(a0), wrist[1] + 0.55 * ln * sin(a0))
                tip = (mid[0] + 0.45 * ln * cos(a0 + rad(18)), mid[1] + 0.45 * ln * sin(a0 + rad(18)))
                fingers.append((mid, tip))
            for j in range(n - 1, -1, -1):
                mid, tip = fingers[j]
                web = lpts(sc, wing, [wrist, (wrist[0] + (mid[0] - wrist[0]) * 0.8, wrist[1] + (mid[1] - wrist[1]) * 0.8),
                                      (wrist[0] + 2.5, wrist[1] + 4.0)])
                m = k.poly_mask(web)
                canvas.piece(m, k.edge_shade(m, 2, 1, 0) - dim, sp.A)
            for j in range(n - 1, -1, -1):
                mid, tip = fingers[j]
                lbone(sc, canvas, wing, [mid, tip], 1.25, 0.6, sp.R, dim, knob0=1.7)
                lbone(sc, canvas, wing, [wrist, mid], 1.5, 1.25, sp.R, dim)
                tips.append(tip)
            lbone(sc, canvas, wing, [arm[1], arm[2]], 1.8, 1.6, sp.R, dim, knob1=2.4)
            lbone(sc, canvas, wing, [arm[0], arm[1]], 2.0, 1.8, sp.R, dim, knob0=2.4, knob1=2.5)
        else:                                             # 'rib': ribs that curl back, torn skin at their roots
            ribs = []
            roots = (arm[1], (11.0 * z, -6.2 * z), arm[2], arm[3])
            for i, (root, ang, ln) in enumerate(zip(roots, (82, 70, 56, 40), (10.5, 14.0, 16.5, 13.0))):
                a0 = rad(ang + 5.0 * sin(ph - 0.5 - 0.45 * i))
                pts = [root]
                x, y = root
                for step in range(4):
                    x += ln * z / 4.0 * cos(a0 + rad(17) * step)
                    y += ln * z / 4.0 * sin(a0 + rad(17) * step)
                    pts.append((x, y))
                ribs.append(pts)
            for i in (3, 2, 1, 0):
                root, nxt = ribs[i][0], ribs[i][2]
                m = k.poly_mask(lpts(sc, wing, [(root[0] - 3.2, root[1] + 0.6), (root[0] + 3.2, root[1] + 0.2),
                                                (nxt[0] + 1.6, nxt[1]), (nxt[0] - 1.2, nxt[1] - 1.0)]))
                canvas.piece(m, k.edge_shade(m, 2, 1, 0) - dim, sp.A)
            for i in (3, 2, 1, 0):
                lbone(sc, canvas, wing, ribs[i], 1.45, 0.75, sp.R, dim)
                tips.append(ribs[i][-1])
            lbone(sc, canvas, wing, [arm[2], arm[3]], 1.6, 1.3, sp.R, dim, knob1=1.9)
            lbone(sc, canvas, wing, [arm[1], arm[2]], 1.8, 1.6, sp.R, dim, knob1=2.4)
            lbone(sc, canvas, wing, [arm[0], arm[1]], 2.0, 1.8, sp.R, dim, knob0=2.4, knob1=2.5)
            lbone(sc, canvas, wing, [arm[2], (arm[2][0] + 1.5, arm[2][1] - 5.0)], 1.1, 0.6, sp.R, dim)
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(24), length)
        motes(sc, canvas, mean, tips, sp, sgn, 2)


# ------------------------------------------------------------------------------------------------ bat
BAT_VARS = {
    #           fingers (angle, length)                         bone hw  flap  claws  holes  thorns
    'bat': (((-24, 19.0), (10, 21.0), (46, 19.0), (84, 15.0)), 0.55, 22, False, False, False),
    'dragon': (((-30, 22.0), (-2, 24.0), (28, 23.0), (60, 20.0), (94, 15.0)), 0.7, 20, True, False, False),
    'torn': (((-26, 20.0), (8, 22.0), (44, 18.0), (82, 15.0)), 0.55, 22, False, True, False),
    'demon': (((-34, 21.0), (0, 23.0), (36, 21.0), (76, 17.0)), 0.75, 20, True, False, True),
    'gargoyle': (((-18, 17.0), (16, 19.0), (52, 17.0), (88, 13.0)), 1.1, 12, True, False, False),
}
THORN = ((0.0, 1.0), (1.0, 0.0))


def fam_bat(sc, sp):
    ph = sc.ph
    wph = ph + 0.35 * sin(ph)
    fing, bhw, amp, claws, holes, thorns = BAT_VARS[sp.var]
    z = sp.size
    elbow = (6.0 * z, -5.0 * z)
    wrist = (11.0 * z, -8.5 * z)
    spread = 1.0 + 0.13 * sin(wph - 0.6)
    for sgn, wing, canvas, dim in sides(sc, 40, lambda s: rad(24) + rad(amp) * sin(wph - 0.9 * s), 24.0 * z):
        tips = []
        for i, (ang, ln) in enumerate(fing):
            a = rad((ang + 3 * sin(wph - 0.5 * i)) * spread)
            tips.append((wrist[0] + ln * z * cos(a), wrist[1] + ln * z * sin(a)))
        body = (1.5, 10.0 * z)
        panels = []
        for i in range(len(tips) - 1):
            t0, t1 = tips[i], tips[i + 1]
            mid = ((t0[0] + t1[0]) / 2.0, (t0[1] + t1[1]) / 2.0)
            mid = (mid[0] + (wrist[0] - mid[0]) * 0.24, mid[1] + (wrist[1] - mid[1]) * 0.24)
            panels.append([wrist, t0, mid, t1])
        t0 = tips[-1]
        mid = ((t0[0] + body[0]) / 2.0 + 1.5, (t0[1] + body[1]) / 2.0 - 2.5)
        panels.append([wrist, t0, mid, body, (0.0, 0.0), elbow])
        for i in range(len(panels) - 1, -1, -1):
            m = k.poly_mask(lpts(sc, wing, panels[i]))
            if holes and i % 2 == 0:
                cx = sum(p[0] for p in panels[i]) / len(panels[i])
                cy = sum(p[1] for p in panels[i]) / len(panels[i])
                hx, hy = lpts(sc, wing, [(cx + 1.5, cy + 2.0)])[0]
                m &= ~k.disc_mask(hx, hy, 1.9)
            shade = k.edge_shade(m, 3, 2, 1)
            idx = shade - (i % 2)
            canvas.piece(m, idx - dim, sp.R, line=sp.R[0])
        for i in range(len(tips) - 1, -1, -1):
            lbone(sc, canvas, wing, [wrist, tips[i]], bhw, bhw * 0.55, sp.A, dim, shade=(3, 2, 1))
            if claws:
                a = math.atan2(tips[i][1] - wrist[1], tips[i][0] - wrist[0])
                lfeather(sc, canvas, wing, tips[i][0], tips[i][1], a + rad(18), 2.6, 0.8, THORN, lambda tt, ss, lit, hw: np.where(lit, 4, 3).astype(np.int8),
                         sp.A, dim=dim, minw=1.0)
        if thorns:
            for i, s in enumerate((0.3, 0.6, 0.9)):
                a = elbow[0] * s if s < 0.5 else elbow[0] + (wrist[0] - elbow[0]) * (s - 0.5) * 2
                b = elbow[1] * s * 2 if s < 0.5 else elbow[1] + (wrist[1] - elbow[1]) * (s - 0.5) * 2
                lfeather(sc, canvas, wing, a, b - 0.5, rad(-80 + 12 * i), 5.0, 1.4, THORN, lambda tt, ss, lit, hw: np.where(lit, 3, 2).astype(np.int8),
                         ramp5(sp.glow), dim=dim, minw=1.0)
        lbone(sc, canvas, wing, [elbow, wrist], bhw + 0.7, bhw + 0.5, sp.A, dim, knob1=bhw + 1.2, shade=(3, 2, 1))
        lbone(sc, canvas, wing, [(0.0, 0.0), elbow], bhw + 0.9, bhw + 0.7, sp.A, dim, knob0=bhw + 1.2, knob1=bhw + 1.3, shade=(3, 2, 1))
        lbone(sc, canvas, wing, [wrist, (wrist[0] + 1.5, wrist[1] - 4.5)], 1.1, 0.5, sp.A, dim, shade=(4, 3, 2))
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(24), 24.0 * z)
        motes(sc, canvas, mean, tips, sp, sgn, 2)


# ------------------------------------------------------------------------------------------------ insect
LOBE = ((0.0, 0.14), (0.12, 0.55), (0.3, 0.86), (0.55, 1.0), (0.78, 0.92), (0.92, 0.62), (1.0, 0.0))
MOTH = ((0.0, 0.12), (0.2, 0.42), (0.5, 0.78), (0.8, 1.0), (0.94, 0.72), (1.0, 0.0))
GLASS = ((0.0, 0.3), (0.15, 0.8), (0.55, 1.0), (0.88, 0.8), (1.0, 0.0))
INSECT_VARS = {
    #             lobes (angle, length, half width, knots)                              beats  amplitude
    'butterfly': (((34, 12.5, 6.2, LOBE), (-36, 18.0, 7.2, LOBE)), 2, 30),
    'moth': (((40, 10.5, 5.2, LOBE), (-28, 20.0, 6.4, MOTH)), 1, 22),
    'dragonfly': (((16, 21.0, 2.6, GLASS), (-18, 24.0, 2.8, GLASS)), 2, 16),
    'fairy': (((38, 12.0, 3.6, GLASS), (-34, 20.0, 4.6, GLASS)), 2, 24),
    'beetle': (((22, 17.0, 3.8, GLASS), (-24, 17.0, 5.6, LOBE)), 1, 14),
    'ray': (((8, 23.0, 7.5, MOTH),), 1, 20),
}


def fam_insect(sc, sp):
    ph = sc.ph
    lobes, beats, amp = INSECT_VARS[sp.var]
    z = sp.size
    var = sp.var

    def wing_shader(front):
        def shader(tt, ss, lit, hw):
            ax = np.abs(ss)
            idx = (2 + (tt > 0.5) - (~lit)).astype(np.int8)
            if var in ('dragonfly', 'fairy') or (var == 'beetle' and not front):
                idx = (3 + lit - (tt < 0.25)).astype(np.int8)            # clear wings: pale, a cell pattern of veins
                vein = ((np.abs(ss) * hw < 0.5) | (((tt * 7).astype(np.int32) % 2 == 0) & (ax > 0.45))) & (tt < 0.92)
                idx[vein] = 6 if var != 'fairy' else 2
                return idx
            border = (ax > 0.66) | (tt > 0.9)
            idx[border] = 6 - (~lit[border]).astype(np.int8) + 1
            vein = (np.abs(ss) * hw < 0.5) & (tt < 0.72) & ~border
            idx[vein] = 5 if var != 'beetle' else 4
            if var in ('butterfly', 'moth'):
                dots = border & (((tt * 9).astype(np.int32) % 2) == 0) & (ax > 0.82) & (tt > 0.3)
                idx[dots] = 10
            if var == 'beetle':
                idx[(ax < 0.3) & lit & (tt > 0.2) & (tt < 0.8)] = 4       # the shine of the shell
            return idx
        return shader

    # two beats a cycle: a strong one and a soft one, so the 16 frames are 16 pictures and not 8 shown twice
    flut = sin(beats * ph + TAU * sp.jit) * ((0.86 + 0.2 * sin(ph + TAU * sp.jit)) if beats == 2 else 1.0)
    for sgn, wing, canvas, dim in sides(sc, 30, lambda s: rad(14) + rad(amp) * flut, 20.0 * z):
        tips = []
        for li, (ang, ln, hw, knots) in enumerate(lobes):
            front = li == len(lobes) - 1
            a = rad(ang + (5 if front else -4) * sin(beats * ph + TAU * sp.jit - 0.6))
            got = lfeather(sc, canvas, wing, 1.0, 0.0, a, ln * z, hw * z, knots, wing_shader(front), sp.PAL, dim=dim, minw=1.6)
            tips.append((1.0 + ln * z * 0.8 * cos(a), ln * z * 0.8 * sin(a)))
            if var == 'moth' and front and got:           # the eye on the fore wing
                b, t = got
                x, y = b[0] + (t[0] - b[0]) * 0.66, b[1] + (t[1] - b[1]) * 0.66
                if canvas.op[int(k.clamp(y, 0, S - 1)), int(k.clamp(x, 0, S - 1))]:
                    m = k.disc_mask(x, y, 2.2) & canvas.op & ~(k.dilate4(~canvas.op))
                    canvas.rgb[m] = sp.A[0]
                    canvas.rgb[k.disc_mask(x, y, 1.0) & m] = sp.glow
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(14), 20.0 * z)
        motes(sc, canvas, mean, tips, sp, sgn, 2)


# ------------------------------------------------------------------------------------------------ crystal
PANE = ((0.0, 0.5), (0.1, 1.0), (0.84, 1.0), (1.0, 0.3))
DROP = ((0.0, 0.2), (0.3, 0.5), (0.62, 1.0), (0.86, 0.9), (1.0, 0.0))
CRYSTAL_VARS = {
    #          shards (angle, length, half width)
    'shard': ((-44, 15.0, 2.6), (-16, 23.0, 3.2), (11, 26.5, 3.5), (40, 20.0, 3.1), (72, 13.5, 2.5)),
    'cluster': ((-58, 11.0, 2.4), (-36, 18.0, 3.0), (-14, 13.0, 2.6), (6, 22.0, 3.4), (28, 14.0, 2.7), (50, 18.0, 3.0),
                (76, 10.5, 2.4)),
    'prism': ((-50, 14.0, 2.4), (-26, 21.0, 2.8), (-2, 25.0, 3.0), (22, 21.0, 2.8), (46, 16.0, 2.6), (70, 11.5, 2.3)),
    'pane': ((-34, 17.0, 4.0), (-4, 22.0, 4.4), (26, 19.0, 4.2), (58, 14.0, 3.8)),
    'drop': ((8, 10.0, 2.6), (30, 15.0, 3.2), (52, 12.0, 2.8), (74, 16.0, 3.3), (96, 10.0, 2.5)),
}


def crystal_shader(var):
    def shader(tt, ss, lit, hw):
        idx = np.where(lit, 3, 1).astype(np.int8)
        idx = idx + (tt > 0.7) - ((tt < 0.2) & ~lit)
        if var == 'pane':                                 # a glare runs across a flat pane
            idx[((tt * 2.0 + ss * 0.35) % 1.0) < 0.16] = 4
        elif var == 'drop':
            idx = (2 + lit).astype(np.int8)
            idx[(np.abs(ss - 0.35) < 0.22) & (tt > 0.55) & (tt < 0.8)] = 4
        else:
            idx[(np.abs(ss) * hw < 0.55) & lit & (tt > 0.12) & (hw > 1.6)] = 4
        return idx
    return shader


def fam_crystal(sc, sp):
    ph = sc.ph
    z = sp.size
    var = sp.var
    if var in ('needle', 'flake'):
        return crystal_branch(sc, sp)
    shards = CRYSTAL_VARS[var]
    knots = PANE if var == 'pane' else DROP if var == 'drop' else k.SHARD
    shader = crystal_shader(var)
    order = sorted(range(len(shards)), key=lambda i: shards[i][1])
    for sgn, wing, canvas, dim in sides(sc, 30, lambda s: rad(20) + rad(6) * sin(ph), 24.0 * z):
        got_all = {}
        tips = []
        for i in order:
            ang, ln, hw = shards[i]
            pulse = 1.0 + 0.15 * sin(ph - 0.75 * i + TAU * sp.jit)
            a = rad(ang + 2.5 * sin(ph - 0.75 * i))
            ramp = ramp5(hue_turn(sp.main, i / float(len(shards)))) if var == 'prism' else sp.R
            got = lfeather(sc, canvas, wing, 2.0 * cos(a), 2.0 * sin(a), a, ln * z * pulse - 2.0, hw, knots, shader, ramp, dim=dim)
            tips.append((ln * z * 0.8 * cos(rad(ang)), ln * z * 0.8 * sin(rad(ang))))
            if got:
                got_all[i] = got
        for i, r in ((1, 5.5), (len(shards) - 2, 5.0)):   # small crystals at the root, in the accent
            ang = rad(shards[i][0] + 13)
            ln = r + 0.5 * sin(ph)
            lfeather(sc, canvas, wing, 0.0, 0.0, ang, ln, 1.9, k.SHARD, crystal_shader('shard'), sp.A, dim=dim)
        for i, (b, t) in sorted(got_all.items()):
            g = cos(ph - TAU * i / float(len(shards)) - (math.pi if sgn > 0 else 0.0) + TAU * sp.jit)
            if g > 0.72:
                canvas.spark(b[0] + (t[0] - b[0]) * 0.8, b[1] + (t[1] - b[1]) * 0.8, sp.glow, 2 if g > 0.93 else 1)
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(20), 24.0 * z)
        motes(sc, canvas, mean, tips, sp, sgn, 2)


def crystal_branch(sc, sp):
    """needle: icicles under an arm; flake: three arms with side branches"""
    ph = sc.ph
    z = sp.size
    shader = crystal_shader('shard')
    for sgn, wing, canvas, dim in sides(sc, 34, lambda s: rad(22) + rad(7) * sin(ph - 0.5 * s), 24.0 * z):
        tips = []
        if sp.var == 'needle':
            edge = arch(23.0 * z, 5.0)
            n = max(5, min(9, 7 + sp.n))
            for i in range(n - 1, -1, -1):
                a, b = edge(0.1 + 0.88 * i / (n - 1))
                ln = (7.0 + 8.0 * sin(math.pi * (0.15 + 0.8 * i / (n - 1)))) * z * (1.0 + 0.14 * sin(ph - 0.8 * i))
                lfeather(sc, canvas, wing, a, b + 0.5, rad(92 - 3 * i), ln, 1.7, k.SHARD, shader, sp.R, dim=dim)
                tips.append((a, b + ln))
            lbone(sc, canvas, wing, [edge(i / 8.0) for i in range(9)], 1.6, 0.9, sp.A, dim, shade=(4, 3, 1))
        else:
            for j, (ang, ln) in enumerate(((52, 16.0), (-48, 18.0), (2, 24.0))):
                a = rad(ang + 3 * sin(ph - 0.8 * j))
                pulse = 1.0 + 0.1 * sin(ph - 0.9 * j)
                for u in (0.42, 0.68):
                    for side in (-1, 1):
                        ba, bb = ln * z * u * cos(a), ln * z * u * sin(a)
                        lfeather(sc, canvas, wing, ba, bb, a + side * rad(52), ln * z * 0.36 * (1.25 - u) * pulse + 1.5, 1.5, k.SHARD,
                                 shader, sp.A, dim=dim, minw=1.0)
                lfeather(sc, canvas, wing, 0.5, 0.0, a, ln * z * pulse, 2.2, k.SHARD, shader, sp.R, dim=dim)
                tips.append((ln * z * 0.85 * cos(a), ln * z * 0.85 * sin(a)))
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(22), 24.0 * z)
        motes(sc, canvas, mean, tips, sp, sgn, 3)


# ------------------------------------------------------------------------------------------------ fan
SLAT = ((0.0, 0.6), (0.06, 0.85), (0.9, 1.0), (0.97, 0.8), (1.0, 0.45))
KITE = ((0.0, 0.0), (0.38, 1.0), (1.0, 0.0))
RIBBON = ((0.0, 0.5), (0.2, 1.0), (0.8, 0.8), (1.0, 0.0))
FAN_VARS = {
    #          slats  from  to   length  half width  knots     open by
    'blade': (5, -66, 44, 24.0, 2.7, k.BLADE, 0.55),
    'slat': (6, -62, 50, 21.0, 2.3, SLAT, 0.5),
    'web': (6, -64, 52, 21.0, 1.2, SLAT, 0.5),
    'tile': (5, -56, 60, 15.0, 3.6, SLAT, 0.3),
    'ribbon': (5, -70, 40, 24.0, 1.5, RIBBON, 0.35),
    'pipe': (7, -30, 84, 20.0, 1.7, SLAT, 0.25),
    'kite': (3, -48, 42, 19.0, 4.6, KITE, 0.4),
}


def fam_fan(sc, sp):
    ph = sc.ph
    n, a0, a1, ln0, hw, knots, by = FAN_VARS[sp.var]
    n = max(3, min(9, n + sp.n))
    z = sp.size
    var = sp.var

    def shader(tt, ss, lit, hw2):
        if var == 'blade':
            return k.blade_shader(tt, ss, lit, hw2)
        idx = np.where(lit, 3, 2).astype(np.int8)
        if var in ('tile', 'slat'):
            idx = idx - (tt < 0.18) + ((tt > 0.86) & lit)
        if var == 'pipe':
            idx = idx - (((tt * 5).astype(np.int32) % 2) == 1) + (tt > 0.9)
        if var == 'kite':
            idx = (2 + lit + (np.abs(ss) < 0.18)).astype(np.int8)
        if var == 'ribbon':
            idx = (2 + lit + (tt > 0.6)).astype(np.int8)
        return idx

    for sgn, wing, canvas, dim in sides(sc, 36, lambda s: rad(22) + rad(5) * sin(ph), 24.0 * z):
        angs, lens = [], []
        for i in range(n):
            u = i / float(n - 1)
            opened = k.ease(0.5 - 0.5 * cos(ph - 0.25 * i + TAU * sp.jit))
            mid = (a0 + a1) / 2.0
            ang = mid + (a0 + (a1 - a0) * u - mid) * ((1.0 - by) + by * opened)
            ln = ln0 * z * (1.0 - 0.28 * abs(u - 0.4) ** 1.3)
            if var == 'pipe':
                ln = ln0 * z * (1.0 - 0.55 * u)
            if var == 'tile':
                ln = ln0 * z * (1.0 + 0.25 * (i % 2))
            angs.append(rad(ang))
            lens.append(ln)
        tips = [(lens[i] * cos(angs[i]), lens[i] * sin(angs[i])) for i in range(n)]
        if var == 'web':                                  # the leaf of the fan, a panel between each pair of ribs
            for i in range(n - 2, -1, -1):
                p0, p1 = tips[i], tips[i + 1]
                mid = ((p0[0] + p1[0]) * 0.46, (p0[1] + p1[1]) * 0.46)
                m = k.poly_mask(lpts(sc, wing, [(0.0, 0.0), (p0[0] * 0.94, p0[1] * 0.94), mid, (p1[0] * 0.94, p1[1] * 0.94)]))
                idx = k.edge_shade(m, 3, 2, 1) - (i % 2)
                band = lpts(sc, wing, [(mid[0] * 0.62 / 0.92, mid[1] * 0.62 / 0.92)])[0]
                idx[k.disc_mask(band[0], band[1], 1.3) & m] = 4
                canvas.piece(m, idx - dim, sp.A, line=sp.A[0])
        order = sorted(range(n), key=lambda i: -abs(i - (n - 1) * 0.4))
        for i in order:
            bend = 3.5 * sin(ph - 0.9 * i) if var == 'ribbon' else 0.0
            ramp = sp.R
            if var == 'kite' and i % 2 == 1:
                ramp = sp.A
            if var == 'ribbon' and i % 2 == 1:
                ramp = sp.A
            got = lfeather(sc, canvas, wing, 1.5 * cos(angs[i]), 1.5 * sin(angs[i]), angs[i], lens[i] - 1.5, hw, knots, shader, ramp,
                           bend=bend, dim=dim)
            if got and var in ('slat', 'tile', 'pipe', 'web'):     # a cap in the accent at the end of each rib
                b, t = got
                x, y = b[0] + (t[0] - b[0]) * 0.96, b[1] + (t[1] - b[1]) * 0.96
                m = k.disc_mask(x, y, 1.5 if var != 'tile' else 1.2)
                canvas.piece(m, k.sphere_shade(x, y, 2.0), sp.A if var != 'web' else ramp5(sp.glow))
            if got and var == 'blade':
                b, t = got
                glint = max(0.0, cos(ph - math.pi - 0.5 * i + TAU * sp.jit)) ** 6
                if glint > 0.4:
                    canvas.spark(b[0] + (t[0] - b[0]) * 0.86, b[1] + (t[1] - b[1]) * 0.86, sp.glow, 2 if glint > 0.8 else 1)
        x, y, _ = sc.P(wing.at(0.5, 0.0))
        m = k.disc_mask(x, y, 2.4)
        canvas.piece(m, k.sphere_shade(x, y, 2.9), sp.A)
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(22), 24.0 * z)
        motes(sc, canvas, mean, [(a * 0.9, b * 0.9) for a, b in tips], sp, sgn, 2)


# ------------------------------------------------------------------------------------------------ leaf
LEAF = ((0.0, 0.12), (0.22, 0.8), (0.5, 1.0), (0.8, 0.66), (1.0, 0.0))
PETAL = ((0.0, 0.2), (0.3, 0.86), (0.64, 1.0), (0.9, 0.72), (1.0, 0.12))
LEAF_VARS = {
    #          leaves  length  half width  knots
    'oval': (9, 9.5, 3.3, LEAF),
    'needle': (15, 8.0, 1.4, k.SHARD),
    'petal': (6, 15.0, 4.4, PETAL),
    'maple': (6, 9.5, 2.9, LEAF),
    'fern': (17, 7.0, 1.7, LEAF),
    'flower': (6, 9.0, 3.0, LEAF),
}


def leaf_shader(tt, ss, lit, hw):
    idx = (2 + lit - (tt < 0.22) + ((tt > 0.75) & lit)).astype(np.int8)
    idx[(np.abs(ss) * hw < 0.5) & (tt < 0.8) & (hw > 2.4)] = 1
    return idx


def fam_leaf(sc, sp):
    ph = sc.ph
    n, ln0, hw, knots = LEAF_VARS[sp.var]
    n = max(4, n + sp.n)
    z = sp.size
    var = sp.var
    length = 22.0 * z
    for sgn, wing, canvas, dim in sides(sc, 38, lambda s: rad(26) + rad(9) * sin(ph - 0.8 * s), length):
        tips = []
        if var == 'petal':                                # petals fan from the shoulder as a flower opens
            for i in sorted(range(n), key=lambda i: -abs(i - (n - 1) * 0.35)):
                u = i / float(n - 1)
                opened = 0.8 + 0.2 * sin(ph - 0.5 * i)
                ang = rad((-58 + 118 * u) * opened + 6)
                ln = ln0 * z * (1.25 - 0.5 * abs(u - 0.3))
                lfeather(sc, canvas, wing, 1.0, 0.0, ang, ln, hw, knots, leaf_shader, sp.R if i % 2 == 0 else sp.A, dim=dim,
                         bend=1.5 * sin(ph - 0.5 * i))
                tips.append((ln * 0.85 * cos(ang), ln * 0.85 * sin(ang)))
            x, y, _ = sc.P(wing.at(1.0, 0.0))
            m = k.disc_mask(x, y, 2.5)
            canvas.piece(m, k.sphere_shade(x, y, 3.0), ramp5(sp.glow))
            mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(26), length)
            motes(sc, canvas, mean, tips, sp, sgn, 2)
            continue
        edge = arch(length, 4.5)
        heads = []
        for i in range(n - 1, -1, -1):
            u = i / float(n - 1)
            a, b = edge(0.08 + 0.92 * u)
            up = (i % 2 == 0)
            flut = 6 * sin(ph - 0.7 * i + TAU * sp.jit)
            ang = rad((-58 if up else 72) - 22 * u * (1 if up else -0.3) + flut + (20 if not up else 0) * 0)
            ln = ln0 * z * (1.0 - 0.45 * u if var == 'fern' else 1.0 - 0.25 * abs(u - 0.45))
            ramp = sp.R
            if var == 'maple':
                for side in (-1, 1):
                    lfeather(sc, canvas, wing, a, b, ang + side * rad(42), ln * 0.68, hw * 0.8, knots, leaf_shader, ramp, dim=dim)
            if var == 'flower' and i in (n - 1, n // 2):
                heads.append((a + 4.5 * cos(ang), b + 4.5 * sin(ang)))
                continue
            lfeather(sc, canvas, wing, a, b, ang, ln, hw, knots, leaf_shader, ramp, dim=dim)
            tips.append((a + ln * 0.8 * cos(ang), b + ln * 0.8 * sin(ang)))
        lbone(sc, canvas, wing, [edge(i / 8.0) for i in range(9)], 1.5, 0.8, sp.A, dim, shade=(3, 2, 1))
        for hx, hy in heads:                              # a flower head: a ring of petals round a dark heart
            cx, cy, _ = sc.P(wing.at(hx, hy))
            turn = ph * 0.0 + TAU * sp.jit
            gr = ramp5(sp.glow)
            for j in range(8):
                px, py = cx + 4.3 * cos(turn + TAU * j / 8.0), cy + 4.3 * sin(turn + TAU * j / 8.0)
                m = k.disc_mask(px, py, 1.9)
                canvas.piece(m, k.sphere_shade(px, py, 2.4), gr, line=gr[0])
            m = k.disc_mask(cx, cy, 2.7 + 0.3 * sin(ph))
            canvas.piece(m, k.sphere_shade(cx, cy, 3.2), sp.A)
            tips.append((hx, hy))
        if sp.spark == 'none' and var in ('needle', 'oval'):    # berries, fixed
            pass
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(26), length)
        motes(sc, canvas, mean, tips, sp, sgn, 3)


# ------------------------------------------------------------------------------------------------ energy
TONGUE = ((0.0, 0.7), (0.16, 1.0), (0.45, 0.8), (0.75, 0.42), (1.0, 0.0))
RAY = ((0.0, 0.25), (0.45, 1.0), (1.0, 0.0))
STRIP = ((0.0, 0.8), (0.1, 1.0), (0.7, 0.9), (1.0, 0.2))


def fam_energy(sc, sp):
    ph = sc.ph
    z = sp.size
    var = sp.var
    n = sp.n
    length = 23.0 * z
    for sgn, wing, canvas, dim in sides(sc, 34, lambda s: rad(24) + rad(8) * sin(ph - 0.6 * s), length):
        tips = []
        if var == 'flame':
            cnt = max(4, min(8, 6 + n))
            for i in sorted(range(cnt), key=lambda i: -abs(i - 1.5)):
                u = i / float(cnt - 1)
                flick = 1.0 + 0.15 * sin(2 * ph + 1.7 * i + TAU * sp.jit)
                ang = rad(-68 + 104 * u + 4 * sin(ph + 1.1 * i))
                ln = (25.0 - 14.0 * abs(u - 0.2) ** 1.1) * z * flick
                bend = 2.6 * sin(ph + 1.1 * i) + 1.2
                lfeather(sc, canvas, wing, 0.5, 0.0, ang, ln, 3.4, TONGUE,
                         lambda tt, ss, lit, hw: (1 + lit + (tt > 0.55)).astype(np.int8), sp.R, bend=bend, dim=dim)
                lfeather(sc, canvas, wing, 0.5, 0.0, ang, ln * 0.66, 1.9, TONGUE,
                         lambda tt, ss, lit, hw: (2 + lit + (tt < 0.5)).astype(np.int8), sp.A, bend=bend * 0.5, dim=dim, minw=1.0)
                tips.append((ln * cos(ang), ln * sin(ang)))
        elif var == 'cloud':
            puffs = [(3.0, -1.0, 4.4), (9.0, -5.0, 5.2), (15.0, -7.5, 4.8), (21.0, -6.5, 3.9), (25.5, -3.5, 2.8), (7.5, 2.5, 3.8),
                     (13.5, 1.0, 3.6), (19.0, 0.5, 2.8)][:max(5, min(8, 8 + n))]
            for i, (a, b, r) in sorted(enumerate(puffs), key=lambda it: -it[1][2] + 0.0, reverse=True):
                rr = (r + 0.5 * sin(ph + 0.9 * i + TAU * sp.jit)) * z
                x, y, _ = sc.P(wing.at(a * z + 0.6 * sin(ph + i), b * z))
                m = k.disc_mask(x, y, rr)
                canvas.piece(m, k.sphere_shade(x, y, rr + 0.6, (-0.1, 0.25, 0.6, 0.88)) - dim, sp.R, line=sp.R[0])
                if i >= 5:
                    tips.append((a * z, b * z))
            tips = tips or [(12.0, 0.0)]
        elif var == 'bolt':
            def zig(pts, amp, seed):
                out = []
                for q, (a, b) in enumerate(pts):
                    j = amp * sin(q * 2.4 + seed + ph * (1 + q % 3)) if 0 < q < len(pts) - 1 else 0.0
                    out.append((a, b + j))
                return out
            main = zig([(0, 0), (5 * z, -5 * z), (9 * z, -2 * z), (14 * z, -8 * z), (18 * z, -5 * z), (24 * z, -10 * z)], 1.6, sp.jit * 9)
            forks = [zig([main[2], (12 * z, 4 * z), (15 * z, 2 * z), (19 * z, 8 * z)], 1.3, 2.0 + sp.jit * 9),
                     zig([main[4], (21 * z, 0), (25 * z, -1 * z), (27 * z, 4 * z)], 1.2, 4.0 + sp.jit * 9)]
            if n > 0:
                forks.append(zig([main[1], (6 * z, 3 * z), (8 * z, 7 * z), (7 * z, 12 * z)], 1.2, 5.5 + sp.jit * 9))
            for pts in forks + [main]:
                m = lline(sc, wing, pts, 1.5, 0.75)
                idx = k.edge_shade(m, 4, 4, 2)
                canvas.piece(m, idx, sp.A, line=sp.R[1])
                tips.append(pts[-1])
        elif var == 'water':
            cnt = max(2, min(5, 3 + n))
            for i in range(cnt - 1, -1, -1):
                u = i / float(max(1, cnt - 1))
                reach = (24.0 - 8.0 * u) * z
                rise = (11.0 - 8.0 * u) * z
                sway = 1.4 * sin(ph - 0.9 * i + TAU * sp.jit)
                pts = [(reach * t, -rise * 4 * t * (1 - t) + (6.0 + 9.0 * u) * z * t * t + sway * t) for t in (0, 0.18, 0.36, 0.54, 0.72, 0.88, 1.0)]
                m = lline(sc, wing, pts, 2.3 - 0.4 * u, 0.8)
                canvas.piece(m, k.edge_shade(m, 4, 2, 1) - dim, sp.R if i % 2 == 0 else sp.A)
                tips.append(pts[-1])
        elif var == 'ray':
            cnt = max(4, min(9, 6 + n))
            for i in sorted(range(cnt), key=lambda i: -abs(i - 2)):
                u = i / float(cnt - 1)
                ang = rad(-64 + 112 * u)
                ln = (25.0 - 9.0 * abs(u - 0.3)) * z * (0.78 + 0.22 * sin(ph + 2.0 * i + TAU * sp.jit))
                lfeather(sc, canvas, wing, 1.5 * cos(ang), 1.5 * sin(ang), ang, ln, 1.9 + 0.5 * (i % 2), RAY,
                         lambda tt, ss, lit, hw: np.where(np.abs(ss) < 0.34, 9, np.where(lit, 3, 2)).astype(np.int8), sp.PAL, dim=0)
                tips.append((ln * cos(ang), ln * sin(ang)))
            x, y, _ = sc.P(wing.at(0.5, 0.0))
            m = k.disc_mask(x, y, 2.8)
            canvas.piece(m, k.sphere_shade(x, y, 3.3), sp.A)
        elif var == 'spiral':
            turns = 2.2 + 0.4 * n
            pts = []
            steps = 26
            for q in range(steps + 1):
                t = q / float(steps)
                th = TAU * turns * t - ph * sgn - TAU * sp.jit
                r = (1.5 + 10.5 * t) * z
                pts.append((12.0 * z + r * cos(th) * 1.15, -2.0 * z + r * sin(th) * 0.85))
            m = lline(sc, wing, pts, 2.0, 0.9)
            canvas.piece(m, k.edge_shade(m, 4, 3, 1) - dim, sp.R)
            x, y, _ = sc.P(wing.at(12.0 * z, -2.0 * z))
            m = k.disc_mask(x, y, 2.2)
            canvas.piece(m, k.sphere_shade(x, y, 2.7), sp.A)
            tips = [pts[-1], pts[steps // 2]]
        else:                                             # 'veil': strips of light hang from an arch and wave
            edge = arch(24.0 * z, 6.0)
            cnt = max(6, min(11, 9 + n))
            for i in range(cnt - 1, -1, -1):
                u = i / float(cnt - 1)
                a, b = edge(0.06 + 0.92 * u)
                ln = (8.0 + 9.0 * sin(math.pi * (0.1 + 0.85 * u))) * z * (1.0 + 0.28 * sin(ph - 0.8 * i + TAU * sp.jit))
                mixc = tuple(int(round(sp.main[c] + (sp.accent[c] - sp.main[c]) * u)) for c in range(3))
                lfeather(sc, canvas, wing, a, b, rad(90 + 8 * sin(ph - 0.8 * i)), ln, 1.5, STRIP,
                         lambda tt, ss, lit, hw: (4 - (tt > 0.3) - (tt > 0.6) - (tt > 0.85) - (~lit & (tt > 0.3))).astype(np.int8),
                         ramp5(mixc), dim=0, minw=1.4)
                tips.append((a, b + ln))
            lbone(sc, canvas, wing, [edge(i / 8.0) for i in range(9)], 1.3, 0.8, ramp5(sp.glow), 0, shade=(4, 3, 2))
        mean = k.Wing(sgn, wing.root, wing.sweep, lambda s: rad(24), length)
        motes(sc, canvas, mean, tips, sp, sgn, 3)


# ------------------------------------------------------------------------------------------------ orbit
def fam_orbit(sc, sp):
    items = []
    if sp.var == 'firefly':                               # small lights on two rings that turn against each other
        for ring, (cnt, radius, tilt, way, height) in enumerate(((5, 22.0, 12, 1, 3.0), (4, 14.0, -18, -1, 8.0))):
            cnt = max(3, cnt + sp.n)
            for i in range(cnt):
                th = way * TAU * (i / float(cnt) + sc.f / float(k.FRAMES * cnt)) + ring * 1.3 + TAU * sp.jit
                x, zz = radius * cos(th), radius * sin(th)
                p = (x * cos(rad(tilt)), height + x * sin(rad(tilt)) + 1.5 * sin(3 * th), zz)
                items.append((sc.P(p), th, ring))
        items.sort(key=lambda it: it[0][2])
        for (x, y, depth), th, ring in items:
            canvas = sc.layer(depth)
            blink = cos(2 * th + ring)
            r = 1.9 + 0.5 * blink
            m = k.disc_mask(x, y, r)
            canvas.piece(m, k.sphere_shade(x, y, r + 0.5, (-0.3, 0.1, 0.5, 0.85)), sp.R)
            canvas.spark(x, y, sp.glow, 2 if blink > 0.6 else 1)
            canvas.spark(x - 3.0 * cos(th + 1.57) * 0, y + 3.5, sp.accent, 0)
        return
    # 'circle': a dashed ring that turns round the body, four rune stones on it
    dashes = 18
    radius = 21.0 * sp.size
    for i in range(dashes):
        th = TAU * (i / float(dashes) + sc.f / float(k.FRAMES * dashes))
        pts = []
        for q in (-0.085, 0.0, 0.085):
            x, zz = radius * cos(th + q), radius * sin(th + q)
            pts.append(sc.P((x * cos(rad(10)), 2.0 + x * sin(rad(10)), zz)))
        items.append((pts[1][2], 'dash', pts, i))
    stones = max(3, 4 + sp.n)
    for i in range(stones):
        th = -TAU * (i / float(stones) + sc.f / float(k.FRAMES * stones)) + TAU * sp.jit
        x, zz = (radius + 0.5) * cos(th), (radius + 0.5) * sin(th)
        p = sc.P((x * cos(rad(10)), 2.5 + x * sin(rad(10)) + 1.5 * sin(stones * th), zz))
        items.append((p[2] + 0.01, 'stone', p, th))
    items.sort(key=lambda it: it[0])
    for depth, kind, arg, extra in items:
        canvas = sc.layer(depth)
        if kind == 'dash':
            m = k.capsule_mask(arg[0][:2], arg[1][:2], 1.0) | k.capsule_mask(arg[1][:2], arg[2][:2], 1.0)
            canvas.piece(m, k.edge_shade(m, 4, 3, 2), sp.A)
        else:
            x, y = arg[0], arg[1]
            m = k.poly_mask([(x, y - 4.6), (x + 3.4, y), (x, y + 4.6), (x - 3.4, y)])
            idx = np.where((k.PX - x) + (k.PY - y) < 0, 3, 1).astype(np.int8)
            idx[k.disc_mask(x, y, 1.2)] = 4
            canvas.piece(m, idx, sp.R)
            g = cos(stones * extra)
            if g > 0.5:
                canvas.spark(x, y, sp.glow, 2 if g > 0.9 else 1)


FAMILIES = {
    'feather': (fam_feather, 9.0), 'bone': (fam_bone, 9.0), 'bat': (fam_bat, 9.0), 'insect': (fam_insect, 9.0),
    'crystal': (fam_crystal, 9.0), 'fan': (fam_fan, 9.0), 'leaf': (fam_leaf, 9.0), 'energy': (fam_energy, 9.0),
    'orbit': (fam_orbit, 3.0),
}


def render_frame(sp, d, f):
    fn, pivot = FAMILIES[sp.family]
    sc = k.Scene(sp.outline, d, f, pivot)
    fn(sc, sp)
    return sc.result()


def render(sp, dirs=k.DIRS, frames=None):
    frames = range(k.FRAMES) if frames is None else frames
    return {d: [render_frame(sp, d, f) for f in frames] for d in dirs}


# ------------------------------------------------------------------------------------------------ frames of a row
TILES = S // 32
PATTERN_Y = 2               # y0: the whole wing (old clients), y1: the part in front of the body (base patch 0203)
FRAME_MS = 83               # 16 frames in 1.33 s, the speed of the previews
SUMS = os.path.join(HERE, 'drawn_wings', 'designs.sums')
ANCHORS = os.path.normpath(os.path.join(HERE, '..', '..', 'overlay', 'modules', 'client_chaos_wingfit', 'wing_anchors.lua'))


def whole(back, front):
    """pattern y0: the back layer with the opaque pixels of the front on it (a client without base patch 0203 draws
    only this one; the glow of the front stays out, the patched client draws it once, with y1)"""
    out = back.copy()
    solid = front[..., 3] == 255
    out[solid] = front[solid]
    return out


def patterns(sp):
    """{(y, direction index, frame): RGBA 96 x 96} of a row, directions in the dat order (north, east, south, west)"""
    out = {}
    for x, d in enumerate(k.DIRS):
        for f in range(k.FRAMES):
            back, front = render_frame(sp, d, f)
            out[(0, x, f)] = whole(back, front)
            out[(1, x, f)] = front
    return out


def digest(pats):
    import hashlib
    h = hashlib.sha256()
    for key in sorted(pats):
        h.update(bytes(key))
        h.update(np.ascontiguousarray(pats[key]).tobytes())
    return h.hexdigest()


def _digest_row(sp):
    return sp.wings, digest(patterns(sp))


def all_digests(specs=None, jobs=None):
    """{wings id: sha256 of its 128 pictures}; the rows are drawn in parallel"""
    import multiprocessing
    specs = load() if specs is None else specs
    jobs = jobs or min(4, os.cpu_count() or 1)
    if jobs <= 1 or len(specs) < 4:
        return dict(_digest_row(sp) for sp in specs)
    with multiprocessing.Pool(jobs) as pool:
        return dict(pool.map(_digest_row, specs, chunksize=4))


def sums_text(sums):
    return ''.join('%d %s\n' % (w, sums[w]) for w in sorted(sums))


def read_sums(path=SUMS):
    out = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            w, h = line.split()
            out[int(w)] = h
    return out


def problems(specs=None):
    """the rules of the table that need no drawing"""
    specs = load() if specs is None else specs
    bad = []
    seen, keys, looks = set(), set(), set()
    for sp in specs:
        if sp.wings in seen or sp.key in keys or sp.look in looks:
            bad.append('%s: wings id, key or look twice' % sp.key)
        seen.add(sp.wings)
        keys.add(sp.key)
        looks.add(sp.look)
        if not 0.85 <= sp.size <= 1.1 or not -2 <= sp.n <= 2:
            bad.append('%s: size or n out of range' % sp.key)
    recipe = {}
    for sp in specs:
        key = (sp.family, sp.var, sp.main, sp.accent, sp.glow, sp.spark, sp.n, sp.size)
        if key in recipe:
            bad.append('%s and %s: the same recipe' % (recipe[key], sp.key))
        recipe[key] = sp.key
    return bad


# ------------------------------------------------------------------------------------------------ the engine's anchor
def anchor_rel():
    """the wings' own anchor, sprite px at 1x from the creature's place (the top left of its tile), displacement 0:
    the point of the 96 x 96 picture that goes on the body's torso (base patch 0204)"""
    return (k.ANCHOR[0] - (S - 32), k.ANCHOR[1] - (S - 32))


def anchors_text(specs=None):
    specs = load() if specs is None else specs
    ax, ay = anchor_rel()
    lines = ['-- Generated by client/tools/sprites/gen_drawn_wings.py table from drawn_wings/designs.csv. Do not edit.',
             '-- Code-drawn wings (O583): the point of every drawn wings look that sits on the body torso, sprite px at 1x',
             "-- from the creature's place, the same for the four directions (base patch 0204 measures the body and puts",
             '-- this point on its torso). bodies: a look whose measured torso is wrong gets a row',
             '-- {look, direction 0-3, x, y} here, by hand, in gen_drawn_wings_families.py BODY_OVERRIDES.',
             'ChaosWingAnchors = {',
             '  anchor = {%d, %d},' % (ax, ay),
             '  wings = {']
    looks = sorted(sp.look for sp in specs)
    for i in range(0, len(looks), 16):
        lines.append('    ' + ','.join(str(v) for v in looks[i:i + 16]) + ',')
    lines += ['  },', '  bodies = {']
    for row in BODY_OVERRIDES:
        lines.append('    {%d,%d,%d,%d},' % row)
    lines += ['  },', '}', 'return ChaosWingAnchors', '']
    return '\n'.join(lines)


BODY_OVERRIDES = ()         # (look, direction, x, y): the short list of bodies the rule gets wrong; none so far

# the rule of base patch 0204 (chaoswinganchor.h), the same as gen_wing_centres.torso_x plus a y: kept in integers so
# the C++ and this twin agree on every mask
TORSO_ALPHA = 64
TORSO_OPEN = 2
TORSO_LO_PCT, TORSO_HI_PCT = 30, 70


def _erode(m):
    p = np.zeros((m.shape[0] + 2, m.shape[1] + 2), bool)
    p[1:-1, 1:-1] = m
    out = np.ones_like(m)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            out &= p[dy:dy + m.shape[0], dx:dx + m.shape[1]]
    return out


def torso_anchor(alpha):
    """(x2, y2): twice the torso point of a body picture, canvas px (x: the median column of the torso band, y: the
    middle of the band), or None when the picture is empty. alpha: 2-D uint8."""
    a = np.asarray(alpha)
    m = a >= TORSO_ALPHA
    if not m.any():
        m = a > 0
    if not m.any():
        return None
    core = m
    for _ in range(TORSO_OPEN):
        core = _erode(core)
    for _ in range(TORSO_OPEN):
        core = ~_erode(~core)
    core &= m
    if not core.any():
        core = m
    # the biggest 8-connected part; ties go to the part met first in row order
    H, W = core.shape
    label = np.zeros((H, W), np.int32)
    best, best_n, n = 0, 0, 0
    for y0 in range(H):
        for x0 in range(W):
            if not core[y0, x0] or label[y0, x0]:
                continue
            n += 1
            label[y0, x0] = n
            stack, cnt = [(y0, x0)], 0
            while stack:
                y, x = stack.pop()
                cnt += 1
                for yy in range(max(0, y - 1), min(H, y + 2)):
                    for xx in range(max(0, x - 1), min(W, x + 2)):
                        if core[yy, xx] and not label[yy, xx]:
                            label[yy, xx] = n
                            stack.append((yy, xx))
            if cnt > best_n:
                best, best_n = n, cnt
    ys, xs = np.nonzero(label == best)
    top, bot = int(ys.min()), int(ys.max()) + 1
    r0 = top * 100 + TORSO_LO_PCT * (bot - top)          # in hundredths of a row
    r1 = top * 100 + TORSO_HI_PCT * (bot - top)
    sel = (ys * 100 >= r0) & (ys * 100 < r1)
    if not sel.any():
        sel = np.ones(len(ys), bool)
    cols = np.sort(xs[sel])
    c = len(cols)
    x2 = int(cols[(c - 1) // 2]) + int(cols[c // 2])
    y2 = int(ys[sel].min()) + int(ys[sel].max())
    return x2, y2


def body_rel(alpha, disp=(0, 0)):
    """the torso of a body as drawn, sprite px at 1x from the creature's place (halves round up), or None"""
    got = torso_anchor(alpha)
    if got is None:
        return None
    h, w = np.asarray(alpha).shape
    return ((got[0] + 1) // 2 - (w - 32) - disp[0], (got[1] + 1) // 2 - (h - 32) - disp[1])


def wing_shift(body, lift=6, limit=64):
    """the shift of the wings' place for a body torso (body_rel): body - lift - anchor; (0, 0) when out of range"""
    ax, ay = anchor_rel()
    sx, sy = body[0] - lift - ax, body[1] - lift - ay
    if abs(sx) > limit or abs(sy) > limit:
        return (0, 0)
    return (sx, sy)


# ------------------------------------------------------------------------------------------------ the pair
class _G:
    pass


def new_group(old, pats, index):
    """the frame group of a drawn wing: 3 x 3 tiles, one layer, 4 directions, 2 y patterns, the old group's z
    patterns and type, 16 phases of FRAME_MS; index(tile RGBA) -> sprite id"""
    from datspr import sprite_index
    g = _G()
    g.gtype = old.gtype
    g.w = g.h = TILES
    g.exact = S
    g.layers, g.px, g.py, g.pz, g.phases = 1, 4, PATTERN_Y, old.pz, k.FRAMES
    g.anim = (0, 0, 0, (FRAME_MS, FRAME_MS) * k.FRAMES)
    sprites = [0] * (g.w * g.h * g.px * g.py * g.pz * g.phases)
    for (y, x, f), img in pats.items():
        for hh in range(g.h):
            for ww in range(g.w):
                tile = img[(g.h - 1 - hh) * 32:(g.h - hh) * 32, (g.w - 1 - ww) * 32:(g.w - ww) * 32]
                sid = index(tile)
                for z in range(g.pz):
                    sprites[sprite_index(g, x, y, z, 0, f, ww, hh)] = sid
    g.sprites = tuple(sprites)
    return g


def group_frame(g, spr, x, y, z, f):
    from datspr import sprite_index
    img = np.zeros((g.h * 32, g.w * 32, 4), np.uint8)
    for hh in range(g.h):
        for ww in range(g.w):
            a = spr.sprite(g.sprites[sprite_index(g, x, y, z, 0, f, ww, hh)])
            if a is not None:
                img[(g.h - 1 - hh) * 32:(g.h - hh) * 32, (g.w - 1 - ww) * 32:(g.w - ww) * 32] = a
    return img


def pair_patterns(dat, spr, look):
    """the pictures of a wings look of a pair in the shape `patterns` gives, or a text saying why not"""
    from import_outfits import parse_body
    t = dat.outfit(look)
    if t is None:
        return 'look %d is not in the pair' % look
    if 'displacement' in t.flags or 'animateAlways' not in t.flags:
        return 'look %d: displacement set or animateAlways missing' % look
    out = None
    for g in parse_body(dat, t):
        if (g.w, g.h, g.layers, g.px, g.py, g.phases) != (TILES, TILES, 1, 4, PATTERN_Y, k.FRAMES):
            return 'look %d: not a drawn wing (%dx%d tiles, %d y patterns, %d phases)' % (look, g.w, g.h, g.py, g.phases)
        if g.anim is None or tuple(g.anim[3]) != (FRAME_MS, FRAME_MS) * k.FRAMES:
            return 'look %d: frame times' % look
        for z in range(g.pz):
            got = {(y, x, f): group_frame(g, spr, x, y, z, f) for y in range(PATTERN_Y) for x in range(4) for f in range(k.FRAMES)}
            if out is None:
                out = got
            elif any(not np.array_equal(out[key], got[key]) for key in out):
                return 'look %d: its groups or z patterns differ' % look
    return out


def apply(dat_path, spr_path, out_dir, specs=None, log=print):
    """pair in -> pair out in OUT_DIR (not there yet): every row's wings look keeps its id, its flags without the
    displacement, its frame groups and z patterns, and gets the drawn pictures. Outfits, items, effects and missiles
    that are not wings stay byte for byte, sprites are only appended. Verified before the rename."""
    import hashlib
    import shutil
    import struct
    from datspr import Dat, Spr
    from import_outfits import parse_body, build_entry, encode_flags
    from gen_effects import encode_sprite
    specs = load() if specs is None else specs
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    od, ospr = Dat(dat_path), Spr(spr_path)
    assert od.variant[0] == 'new' and all(od.variant[1:]), 'expected our 10.98 dat: %s' % (od.variant,)
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    cnt = ospr.count
    newrecs, recs = [], {}

    def index(tile):
        rec = encode_sprite(np.ascontiguousarray(tile))
        if rec is None:
            return 0
        rec = bytes(rec)
        if rec not in recs:
            newrecs.append(rec)
            recs[rec] = cnt + len(newrecs)
        return recs[rec]

    entries, expect = {}, {}
    for sp in specs:
        t = od.outfit(sp.look)
        if t is None:
            raise SystemExit('the pair has no outfit %d (%s)' % (sp.look, sp.key))
        if 'animateAlways' not in t.flags:
            raise SystemExit('outfit %d (%s) is not a wings look of the pair: no animateAlways' % (sp.look, sp.key))
        keep = _G()
        keep.flags = {name: v for name, v in t.flags.items() if name != 'displacement'}
        flags, stripped = encode_flags(keep, od.extra)
        if stripped:
            raise SystemExit('outfit %d: flags %s cannot be kept' % (sp.look, stripped))
        pats = patterns(sp)
        expect[sp.look] = pats
        groups = [new_group(g, pats, index) for g in parse_body(od, t)]
        entries[sp.look] = build_entry(flags, groups, {s: s for g in groups for s in g.sprites})
        log('%3d %-22s look %d drawn' % (sp.wings, sp.key, sp.look))
    d = od.data
    parts = [bytes(d[:od.outfits[0].raw[0]])]
    for i, t in enumerate(od.outfits):
        parts.append(entries.get(i + 1) or bytes(d[t.raw[0]:t.raw[1]]))
    parts.append(bytes(d[od.outfits[-1].raw[1]:]))
    tmp = out_dir.rstrip('/') + '.tmp'
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    with open(os.path.join(tmp, 'Tibia.dat'), 'wb') as f:
        f.write(b''.join(parts))
    m, nn = ospr.m, len(newrecs)
    toffs = ospr.offs.astype('<u8').copy()
    toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur)
        cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(tmp, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn))
        f.write(table.tobytes())
        pos = 8 + 4 * cnt
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)])
            pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    md, ms = Dat(os.path.join(tmp, 'Tibia.dat')), Spr(os.path.join(tmp, 'Tibia.spr'))
    assert md.variant == od.variant and md.counts == od.counts and ms.count == cnt + nn and md.max_sprite <= ms.count
    looks = set(entries)
    for i, (a, b) in enumerate(zip(od.outfits, md.outfits)):
        if i + 1 not in looks:
            assert d[a.raw[0]:a.raw[1]] == md.data[b.raw[0]:b.raw[1]], 'outfit %d changed' % (i + 1)
    assert d[:od.outfits[0].raw[0]] == md.data[:md.outfits[0].raw[0]], 'items changed'
    assert d[od.outfits[-1].raw[1]:] == md.data[md.outfits[-1].raw[1]:], 'effects or missiles changed'
    for look, pats in expect.items():
        got = pair_patterns(md, ms, look)
        assert not isinstance(got, str), got
        assert all(np.array_equal(pats[key], got[key]) for key in pats), 'look %d: pictures differ' % look
    step = max(1, cnt // 3000)
    sample = list(range(1, cnt + 1, step)) + [cnt]
    for sid in sample:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), sid
    log('verified: %d wings looks redrawn in place, %d sprite records appended (%d -> %d), every other outfit, item, effect, '
        'missile and %d sampled old sprites unchanged' % (len(entries), nn, cnt, cnt + nn, len(sample)))
    with open(os.path.join(tmp, 'Tibia.dat'), 'rb') as f:
        log('dat md5 %s' % hashlib.md5(f.read()).hexdigest())
    os.rename(tmp, out_dir)
    return sorted(entries)


def check_pair(dat_path, spr_path, specs=None, sums=None, log=print):
    """a built pair holds the drawn wings: every row's look has the shape and the pictures of designs.sums"""
    from datspr import Dat, Spr
    specs = load() if specs is None else specs
    sums = read_sums() if sums is None else sums
    dat, spr = Dat(dat_path), Spr(spr_path)
    bad = []
    for sp in specs:
        got = pair_patterns(dat, spr, sp.look)
        if isinstance(got, str):
            bad.append(got)
        elif digest(got) != sums.get(sp.wings):
            bad.append('look %d (%s): pictures are not those of designs.sums' % (sp.look, sp.key))
    for line in bad:
        log(line)
    log('%d of %d wings looks hold the drawn pictures' % (len(specs) - len(bad), len(specs)))
    return bad


# ------------------------------------------------------------------------------------------------ pictures
def old_frames(dat, spr, look):
    """({direction: [RGBA of every phase]}, side): a wings look of the pair on a square canvas, bottom right aligned"""
    from datspr import sprite_index
    t = dat.outfit(look)
    disp = (0, 0)
    d = t.flags.get('displacement')
    if isinstance(d, tuple):
        disp = tuple(v - 65536 if v >= 32768 else v for v in d)
    side = max(S, t.w * 32 + 16, t.h * 32 + 16)
    out = {}
    for x, name in enumerate(k.DIRS):
        seq = []
        for p in range(t.phases):
            img = np.zeros((side, side, 4), np.uint8)
            for hh in range(t.h):
                for ww in range(t.w):
                    a = spr.sprite(t.sprites[sprite_index(t, x if t.px >= 4 else 0, 0, 0, 0, p, ww, hh)])
                    if a is None:
                        continue
                    y0, x0 = side - (hh + 1) * 32 - disp[1], side - (ww + 1) * 32 - disp[0]
                    y1, x1 = max(0, y0), max(0, x0)
                    y2, x2 = min(side, y0 + 32), min(side, x0 + 32)
                    if y2 > y1 and x2 > x1:
                        img[y1:y2, x1:x2] = a[y1 - y0:y2 - y0, x1 - x0:x2 - x0]
            seq.append(img)
        out[name] = seq
    return out, side


def on_bg(img):
    out = np.empty(img.shape[:2] + (3,), np.float64)
    out[:] = k.BG
    return k.over(out, img).astype(np.uint8)


def label_strip(width, text, height=12):
    from PIL import Image, ImageDraw
    im = Image.new('RGB', (width, height), (30, 32, 38))
    ImageDraw.Draw(im).text((2, 0), text, fill=(236, 236, 236))
    return np.asarray(im)


def family_sheet(specs, scale):
    """one row a wing: the four directions at frame 0 and the south view six frames on, on the plain figure"""
    bodies = {d: k.silhouette(d) for d in k.DIRS}
    rows = []
    for sp in specs:
        cells = [k.compose({d: {0: render_frame(sp, d, 0)}}, bodies, d, 0) for d in ('south', 'east', 'north', 'west')]
        cells.append(k.compose({'south': {0: render_frame(sp, 'south', 6)}}, bodies, 'south', 0))
        row = k.upscale(np.concatenate(cells, axis=1), scale)
        rows.append(np.concatenate([label_strip(row.shape[1], '%d  %s  %s / %s' % (sp.wings, sp.name, sp.family, sp.var)), row], axis=0))
    return np.concatenate(rows, axis=0)


def by_family(specs):
    out = {}
    for sp in specs:
        out.setdefault(sp.family, []).append(sp)
    return out


def sheets(out_dir, specs=None, log=print):
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for name, rows in sorted(by_family(load() if specs is None else specs).items()):
        for scale in (1, 3):
            path = os.path.join(out_dir, 'sheet_%s_%dx.png' % (name, scale))
            Image.fromarray(family_sheet(rows, scale), 'RGB').save(path)
            written.append(path)
            log(path)
    return written


def compare(out_dir, dat_path, spr_path, specs=None, loops=3, scale=2, per_file=8, log=print):
    """MP4s a family, at most per_file wings a file: every wing a row, the old art of the pair on the left and the drawn wing on the right, four
    directions each"""
    from PIL import Image
    from datspr import Dat, Spr
    os.makedirs(out_dir, exist_ok=True)
    dat, spr = Dat(dat_path), Spr(spr_path)
    bodies = {d: k.silhouette(d) for d in k.DIRS}
    written = []
    jobs = []
    for name, rows in sorted(by_family(load() if specs is None else specs).items()):
        chunks = [rows[i:i + per_file] for i in range(0, len(rows), per_file)]
        for i, chunk in enumerate(chunks):
            jobs.append((name if len(chunks) == 1 else '%s_%d' % (name, i + 1), chunk))
    for name, rows in jobs:
        parts = []
        for sp in rows:
            old, side = old_frames(dat, spr, sp.look)
            for d in k.DIRS:
                seq = [on_bg(img) for img in old[d]]
                if side > S:
                    seq = [np.asarray(Image.fromarray(img).resize((S, S), Image.NEAREST)) for img in seq]
                old[d] = seq
            new = {d: [render_frame(sp, d, f) for f in range(k.FRAMES)] for d in k.DIRS}
            parts.append((sp, old, new))
        frames = []
        for f in range(k.FRAMES * loops):
            lines = []
            for sp, old, new in parts:
                left = [old[d][(f % k.FRAMES) * len(old[d]) // k.FRAMES] for d in k.DIRS]
                right = [k.compose(new, bodies, d, f % k.FRAMES) for d in k.DIRS]
                gap = np.full((S, 8, 3), 20, np.uint8)
                row = np.concatenate(left + [gap] + right, axis=1)
                row = np.concatenate([label_strip(row.shape[1], '%d  %s    old: %s    new: %s / %s'
                                                  % (sp.wings, sp.name, sp.old, sp.family, sp.var)), row], axis=0)
                lines.append(row)
            sheet = k.upscale(np.concatenate(lines, axis=0), scale)
            frames.append(sheet[:sheet.shape[0] // 2 * 2, :sheet.shape[1] // 2 * 2])
        path = os.path.join(out_dir, 'compare_%s.mp4' % name)
        k.write_mp4(path, frames)
        written.append(path)
        log(path)
    return written


def fit_preview(out_dir, dat_path, spr_path, looks, wings=1, loops=4, scale=3, log=print):
    """one new wing on several looks, four directions: left the engine rule of base patch 0204 (the body measured from
    its picture, emulated here), right the old table rule of base patch 0193 (x only, the torso of gen_wing_centres on
    the wings' own centre). A look written as LOOK:MOUNT is drawn riding (its z pattern 1) over the mount."""
    from datspr import Dat, Spr, sprite_index
    import gen_wing_centres as gw
    os.makedirs(out_dir, exist_ok=True)
    dat, spr = Dat(dat_path), Spr(spr_path)
    sp = [s for s in load() if s.wings == wings][0]
    new = {d: [render_frame(sp, d, f) for f in range(k.FRAMES)] for d in k.DIRS}
    ax, ay = anchor_rel()
    cell = 128                                              # the creature's tile is at (64..96, 64..96) of a cell

    def picture(t, x, z):
        layers = []
        for layer in range(min(t.layers, 2)):
            img = np.zeros((t.h * 32, t.w * 32, 4), np.uint8)
            for hh in range(t.h):
                for ww in range(t.w):
                    a = spr.sprite(t.sprites[sprite_index(t, x if t.px >= 4 else 0, 0, min(z, t.pz - 1), layer, 0, ww, hh)])
                    if a is not None:
                        img[(t.h - 1 - hh) * 32:(t.h - hh) * 32, (t.w - 1 - ww) * 32:(t.w - ww) * 32] = a
            layers.append(img)
        body = layers[0].astype(np.float64)
        if len(layers) > 1:
            for key, colour in k.TINT.items():
                sel = (layers[1][..., :3] == key).all(axis=2) & (layers[1][..., 3] > 0)
                body[sel, :3] = body[sel, :3] * np.asarray(colour) / 170.0
        return np.clip(body, 0, 255).astype(np.uint8)

    rows = []
    for item in looks:
        look, _, mount = str(item).partition(':')
        look, mount = int(look), int(mount or 0)
        t = dat.outfit(look)
        disp = gw.displacement(t)
        mt = dat.outfit(mount) if mount else None
        mdisp = gw.displacement(mt) if mt else (0, 0)
        per = []
        for x, d in enumerate(k.DIRS):
            body = picture(t, x, 1 if mount else 0)
            # a rider is drawn at the mount's displacement, its own left out (Outfit::draw, positive mounts)
            off = mdisp if mt else disp
            rel = body_rel(body[..., 3], off)
            new_shift = wing_shift(rel) if rel else (0, 0)
            tx = gw.torso_x(picture(t, x, 0)[..., 3])
            old_shift = (0, 0)
            if tx is not None:
                old_shift = (int(round(tx - (t.w * 32 - 32) - disp[0])) - 6 - ax, 0)
            per.append((d, body, off, picture(mt, x, 0) if mt else None, new_shift, old_shift))
        rows.append((item, t, mt, mdisp, per))

    def put(dst, src, x0, y0):
        h, w = src.shape[:2]
        x1, y1 = max(0, x0), max(0, y0)
        x2, y2 = min(cell, x0 + w), min(cell, y0 + h)
        if x2 > x1 and y2 > y1:
            dst[y1:y2, x1:x2] = k.over(dst[y1:y2, x1:x2], src[y1 - y0:y2 - y0, x1 - x0:x2 - x0])

    frames = []
    for f in range(k.FRAMES * loops):
        lines = []
        for item, t, mt, mdisp, per in rows:
            cells = []
            for which in (0, 1):
                for d, body, off, mount_img, new_shift, old_shift in per:
                    shift = (new_shift, old_shift)[which]
                    img = np.empty((cell, cell, 3), np.float64)
                    img[:] = k.BG
                    back, front = new[d][f % k.FRAMES]
                    wx, wy = 96 - S + shift[0], 96 - S + shift[1]
                    if mount_img is not None:
                        put(img, mount_img, 96 - mt.w * 32 - mdisp[0] - 6, 96 - mt.h * 32 - mdisp[1] - 6)
                    put(img, back, wx, wy)
                    put(img, body, 96 - t.w * 32 - off[0] - 6, 96 - t.h * 32 - off[1] - 6)
                    put(img, front, wx, wy)
                    cells.append(img.astype(np.uint8)[16:, 16:])
                cells.append(np.full((cell - 16, 8, 3), 20, np.uint8))
            row = np.concatenate(cells[:-1], axis=1)
            row = np.concatenate([label_strip(row.shape[1], 'look %s    left: the body measured by the engine (0204)    '
                                              'right: the old table (0193, x only)' % item), row], axis=0)
            lines.append(row)
        sheet = k.upscale(np.concatenate(lines, axis=0), scale)
        frames.append(sheet[:sheet.shape[0] // 2 * 2, :sheet.shape[1] // 2 * 2])
    path = os.path.join(out_dir, 'fit_%s.mp4' % sp.key)
    k.write_mp4(path, frames)
    log(path)
    return path


def write_or_check(path, text, check):
    old = None
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            old = f.read()
    if check:
        return [] if old == text else ['%s is stale: run `gen_drawn_wings.py table`' % os.path.basename(path)]
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    return []


def main(argv):
    """the commands of the table (gen_drawn_wings.py hands them over)"""
    import sys
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    cmd, args = argv[0], argv[1:]
    check = '--check' in args
    args = [a for a in args if a != '--check']
    if cmd == 'table':
        bad = problems()
        if not bad:
            sums = all_digests()
            if len(set(sums.values())) != len(sums):
                bad.append('two rows draw the same pictures')
            bad += write_or_check(SUMS, sums_text(sums), check)
            bad += write_or_check(ANCHORS, anchors_text(), check)
            bad += write_or_check(FIXTURES, fixtures_text(), check)
        for line in bad:
            print(line)
        print('%d rows, %d families%s' % (len(load()), len(by_family(load())), '' if bad else ': ok'))
        return 1 if bad else 0
    if cmd == 'sheets':
        sheets(args[0])
        return 0
    if cmd == 'compare':
        compare(args[0], args[1], args[2])
        return 0
    if cmd == 'fit':
        fit_preview(args[0], args[1], args[2], args[3].split(','), wings=int(args[4]) if len(args) > 4 else 1)
        return 0
    if cmd == 'apply':
        apply(args[0], args[1], args[2])
        return 0
    if cmd == 'live':
        return 1 if check_pair(args[0], args[1]) else 0
    raise SystemExit('unknown command %s' % cmd)


COMMANDS = ('table', 'sheets', 'compare', 'fit', 'apply', 'live')


# ------------------------------------------------------------------------------------------------ shared fixtures
FIXTURES = os.path.join(HERE, 'drawn_wings', 'anchor_fixtures.txt')
FIX_CHARS = {'.': 0, '-': 30, '+': 100, '#': 255}


def _blank(w, h):
    return np.zeros((h, w), np.uint8)


def _figure(a, cx, top, bot, half=7, value=255):
    """a plain standing figure: a head, a trunk and two legs"""
    hh = bot - top
    a[top:top + hh // 4, cx - 4:cx + 4] = value
    a[top + hh // 4:top + 3 * hh // 4, cx - half:cx + half] = value
    a[top + 3 * hh // 4:bot, cx - half:cx - 1] = value
    a[top + 3 * hh // 4:bot, cx + 1:cx + half] = value
    return a


def anchor_fixtures():
    """[(name, alpha)]: masks the C++ header and the Python twin must measure alike"""
    out = []
    out.append(('plain', _figure(_blank(64, 64), 34, 18, 58)))
    a = _figure(_blank(64, 64), 34, 18, 58)
    a[4:60, 50:52] = 255                                   # a staff two wide, held apart
    a[30:32, 41:50] = 255                                  # the arm that holds it
    out.append(('thin_staff', a))
    a = _figure(_blank(64, 64), 30, 18, 58)
    a[26:54, 37:58] = 255                                  # a cape that hangs wide on one side
    out.append(('wide_cape', a))
    a = _figure(_blank(96, 96), 52, 20, 52, half=6)        # a rider drawn high in a big canvas
    out.append(('mounted', a))
    a = _figure(_blank(64, 64), 30, 14, 52)
    a[52:60, 34:60] = 40                                   # a faint ground shadow under the kAlpha cut
    a[54:59, 44:56] = 120                                  # its darker heart: visible, but a small part of its own
    out.append(('shadow_blob', a))
    out.append(('empty', _blank(64, 64)))
    a = _blank(32, 32)
    a[10:24, 12:20] = 30                                   # only faint pixels: they are the figure
    out.append(('faint_only', a))
    a = _blank(32, 32)
    a[15:17, 3:29] = 255                                   # nothing survives the opening: the mask itself
    out.append(('thin_only', a))
    a = _figure(_blank(64, 64), 8, 20, 60, half=7)         # a figure against the left edge of the picture
    out.append(('at_the_edge', a))
    a = _blank(64, 64)
    a[20:40, 10:22] = 255                                  # two parts of one size: the first in row order wins
    a[20:40, 40:52] = 255
    out.append(('two_equal', a))
    return out


def fixtures_text():
    back = {v: c for c, v in FIX_CHARS.items()}
    lines = ['# Generated by client/tools/sprites/gen_drawn_wings.py table. Masks for the torso rule of base patch 0204:',
             '# name width height x2 y2 (twice the canvas point; - - when there is nothing to measure), then the rows.',
             '# . 0   - 30   + 100   # 255. client/tools/chaoswinganchor_test.cpp and gen_drawn_wings_test.py read it.']
    for name, a in anchor_fixtures():
        got = torso_anchor(a)
        lines.append('%s %d %d %s' % (name, a.shape[1], a.shape[0], '%d %d' % got if got else '- -'))
        for row in a:
            lines.append(''.join(back[min(back, key=lambda v: abs(v - int(p)))] for p in row))
    return '\n'.join(lines) + '\n'


def read_fixtures(path=FIXTURES):
    out = []
    with open(path, encoding='utf-8') as f:
        lines = [ln.rstrip('\n') for ln in f if not ln.startswith('#')]
    i = 0
    while i < len(lines):
        name, w, h, x2, y2 = lines[i].split()
        w, h = int(w), int(h)
        a = np.array([[FIX_CHARS[c] for c in lines[i + 1 + r]] for r in range(h)], np.uint8)
        assert a.shape == (h, w), name
        out.append((name, a, None if x2 == '-' else (int(x2), int(y2))))
        i += 1 + h
    return out


# ------------------------------------------------------------------------------------------------ the bar (O581)
def _touches_open(alpha):
    """opaque pixels with a transparent 4-neighbour"""
    op = alpha == 255
    clear = alpha == 0
    near = np.zeros_like(op)
    near[1:, :] |= clear[:-1, :]
    near[:-1, :] |= clear[1:, :]
    near[:, 1:] |= clear[:, :-1]
    near[:, :-1] |= clear[:, 1:]
    return op & near


def _frame_bar(img, outline):
    a = img[..., 3]
    bad = []
    if not set(np.unique(a).tolist()) <= {0, 255, k.GLOW_ALPHA}:
        bad.append('alpha is not 0, 255 or the glow level')
    edge = _touches_open(a)
    if (edge & ~(img[..., :3] == np.asarray(outline, np.uint8)).all(axis=2)).any():
        bad.append('an open edge is not the outline colour')
    if a[0, :].any() or a[-1, :].any() or a[:, 0].any() or a[:, -1].any():
        bad.append('art touches the cell border')
    if img[a == 0][:, :3].any():
        bad.append('a transparent pixel carries colour')
    return bad


def bar_problems(sp, frames=None):
    """the bar of docs/SPRITE_STYLE.md "Wings" on one row: what the six wings of O581 hold, every redone wing holds.
    16 frames a direction, alpha 0 / 255 / one glow level, the outline on every open edge of the back, the front and
    the two together, nothing on the cell border, a loop that moves at every step and closes without a jump, four
    directions that differ, both layers used, the art round the anchor."""
    frames = render(sp) if frames is None else frames
    bad = set()
    used = {'back': 0, 'front': 0}
    merged = {}
    for d in k.DIRS:
        if len(frames[d]) != k.FRAMES:
            bad.add('%s: not 16 frames' % d)
        merged[d] = []
        for back, front in frames[d]:
            both = k.merge(back, front)
            for name, img in (('back', back), ('front', front), ('merged', both)):
                for what in _frame_bar(img, sp.outline):
                    bad.add('%s: %s' % (name, what))
            used['back'] += int((back[..., 3] == 255).sum())
            used['front'] += int((front[..., 3] == 255).sum())
            if (both[..., 3] == 255).sum() < 120:
                bad.add('%s: a frame with under 120 solid pixels' % d)
            merged[d].append(both)
        n = len(merged[d])
        steps = [int((merged[d][i] != merged[d][(i + 1) % n]).any(axis=2).sum()) for i in range(n)]
        if min(steps) == 0:
            bad.add('%s: a frame equals the next' % d)
        if steps[n - 1] > 1.5 * max(steps[:n - 1]):
            bad.add('%s: a jump from the last frame to the first' % d)
        if np.array_equal(merged[d][0], merged[d][n // 2]):
            bad.add('%s: half a cycle later it looks the same' % d)
    if not used['back'] or not used['front']:
        bad.add('a layer is empty (%s)' % used)
    for i, a in enumerate(k.DIRS):
        for b in k.DIRS[i + 1:]:
            if np.array_equal(merged[a][0], merged[b][0]):
                bad.add('%s and %s look the same' % (a, b))
    ys, xs = np.nonzero(np.max([m[..., 3] for d in k.DIRS for m in merged[d]], axis=0))
    if abs(xs.mean() - k.ANCHOR[0]) >= 16 or abs(ys.mean() - k.ANCHOR[1]) >= 24:
        bad.add('the art is far from the anchor (%.1f, %.1f)' % (xs.mean(), ys.mean()))
    return sorted(bad)


def _report_row(sp):
    frames = render(sp)
    pats = {}
    for x, d in enumerate(k.DIRS):
        for f, (back, front) in enumerate(frames[d]):
            pats[(0, x, f)] = whole(back, front)
            pats[(1, x, f)] = front
    return sp.wings, digest(pats), bar_problems(sp, frames)


def all_reports(specs=None, jobs=None):
    """{wings id: (sha256 of its pictures, the bar's problems)}; one drawing a row, in parallel"""
    import multiprocessing
    specs = load() if specs is None else specs
    jobs = jobs or min(4, os.cpu_count() or 1)
    if jobs <= 1 or len(specs) < 4:
        rows = [_report_row(sp) for sp in specs]
    else:
        with multiprocessing.Pool(jobs) as pool:
            rows = pool.map(_report_row, specs, chunksize=4)
    return {w: (h, bad) for w, h, bad in rows}
