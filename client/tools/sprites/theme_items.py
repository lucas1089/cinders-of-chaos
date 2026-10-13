"""Themed equipment icons for gen_theme_art.py: every item is drawn in code at 128 px (shape masks, material ramps lit
from the upper left, a dark outline tinted to the item's own colours) and downsampled 4:1 to a 32 px icon, like the
store pouch looks (gen_pouch_art.py, darklib.py). No pixel of any other game, client or reference sheet is read.

A theme is a dict of material ramps (dark -> light, hue-shifted: cold shade, warm light), a motif (the emblem on
shields, books, packs, amulets and chests) and shape choices per kind. Kinds:
    sword axe club bow crossbow wand rod shield helmet armor legs boots amulet ring backpack spellbook arrow bolt
Variant styles of a kind (the class kits of the later sets): helmet hood / hat, armor robe / jerkin, legs skirt /
leather. Arrows and bolts have the 8 stack patterns of the client (1, 2, 3, 4, 5, 10, 25, 50 pieces).
"""
import math

import numpy as np

from darklib import grid, hexcol, ramp, poly_mask, seg_dist, rim_light, finish, over, rgba, dilate, erode_dist

S = 128          # drawing size
F = 4            # 128 -> 32
Y, X = grid(S, S)
LIT = np.array((-0.62, -0.78))   # light direction on screen (from the upper left)

# ------------------------------------------------------------------------------------------------ material ramps
M = {   # dark -> light
    'bone': ['#2a2116', '#5e5038', '#9c8a64', '#cfc29a', '#f4ecd2'],
    'grave': ['#0e100e', '#22261f', '#3a4033', '#56604a', '#7c8868'],
    'necro': ['#06301a', '#0f6a34', '#22b25a', '#6cf29a', '#d8ffe4'],
    'ironblk': ['#0c0c10', '#1e1f26', '#363844', '#565a68', '#8a8e9c'],
    'voidsteel': ['#05060e', '#10152c', '#23305c', '#4a62a4', '#9cb8f0'],
    'voidcloth': ['#06040c', '#140e24', '#261c40', '#3e2f62', '#5e4c8a'],
    'voidglow': ['#0a1e5a', '#1e52c8', '#4a9cff', '#a6dcff', '#f0fbff'],
    'wood': ['#241306', '#4e2c10', '#7c4c22', '#a8743c', '#d4a468'],
    'leaf': ['#0c2410', '#1c4a1a', '#3a7a2a', '#6aae3e', '#b6dc72'],
    'bronze': ['#2a1806', '#6a4214', '#a26e26', '#d6a44a', '#f8dc96'],
    'amber': ['#3a1a02', '#8a4a06', '#d48812', '#ffc23e', '#fff0b0'],
    'leather': ['#1e1008', '#40220e', '#683a1a', '#91592c', '#bb8048'],
    'silver': ['#161c2c', '#3c465e', '#6e7c98', '#b0bcd2', '#f2f6ff'],
    'moonblue': ['#080e2a', '#142656', '#25428a', '#4a70c4', '#8eb2f0'],
    'moonglow': ['#1a3a7a', '#3c78d0', '#7cb8ff', '#c8e6ff', '#ffffff'],
    'gold': ['#3a2204', '#8a5c0c', '#cc961c', '#f4cc52', '#fff4be'],
    'crimson': ['#300406', '#6e0c12', '#aa1c22', '#e04838', '#ff9a7c'],
    'ivory': ['#3a3428', '#7a705c', '#bcb298', '#e8e0c8', '#ffffff'],
    'ruby': ['#3a0208', '#860a1a', '#d01c30', '#ff5a5a', '#ffd2c8'],
    'steel': ['#14181e', '#363e4a', '#626c7c', '#9ea8b6', '#e8eef4'],
    'red': ['#2a0404', '#640a0a', '#a01414', '#d63428', '#ff7a5c'],
    'white': ['#3c3a38', '#7c7872', '#b8b4aa', '#e2ded2', '#fffef8'],
    'ice': ['#06203e', '#10508c', '#2a8ad0', '#7ccaf6', '#e8fbff'],
    'icedeep': ['#040e22', '#0a2652', '#164890', '#2e76c8', '#66aee8'],
    'emerald': ['#02261a', '#05603a', '#0ea25c', '#4ce08e', '#c8ffe0'],
    'teal': ['#022a2c', '#06626a', '#10a2a6', '#4ee0d8', '#d4fff8'],
    'ivorygold': ['#4a3410', '#9a7426', '#d8b452', '#f6e2a0', '#fffcec'],
    'green': ['#0a2a08', '#18561a', '#2e8c2a', '#5ec244', '#b4f07c'],
    'orangewood': ['#2e1004', '#6a2a08', '#a84e14', '#de7c2a', '#ffb468'],
    'lime': ['#123a06', '#2a7a0c', '#52c41a', '#a6ff4a', '#f0ffd0'],
    'string': ['#3a3426', '#6c6450', '#a49a80', '#d8d0b6', '#fffbe8'],
}


def outline_of(th):
    c = hexcol(M[th['metal']][0]) * 0.55
    return c


# ------------------------------------------------------------------------------------------------ canvas
class Pic:
    def __init__(self):
        self.img = np.zeros((S, S, 4), np.float32)
        self.parts = []      # (mask) of every part, for the seams

    def fill(self, mask, mat, light, seam=0.35, wseam=3):
        """mask (bool), material ramp name or list, light 0..1 (array or scalar)"""
        mask = np.asarray(mask, bool)
        if not mask.any():
            return
        stops = M[mat] if isinstance(mat, str) else mat
        L = np.broadcast_to(np.clip(light, 0, 1), mask.shape)
        col = ramp(L, stops)
        if seam:
            din = erode_dist(mask, wseam + 1)
            band = (din <= wseam) & mask
            col = np.where(band[..., None], col * (1 - seam) + hexcol(stops[0]) * seam * 0.6, col)
        self.img = over(self.img, rgba(col, mask.astype(np.float32)))

    def flat(self, mask, col):
        mask = np.asarray(mask, bool)
        c = hexcol(col) if isinstance(col, str) else np.asarray(col, np.float32)
        self.img = over(self.img, rgba(np.broadcast_to(c, mask.shape + (3,)).copy(), mask.astype(np.float32)))

    def glow(self, cx, cy, r, col, k=0.5):
        """an additive soft glow on the art already there (emissive gems and runes)"""
        d2 = (X - cx) ** 2 + (Y - cy) ** 2
        g = np.exp(-d2 / (2 * r * r)) * (self.img[..., 3] > 0.5)
        self.img[..., :3] = np.clip(self.img[..., :3] + g[..., None] * hexcol(col) * k, 0, 1)

    def done(self, th, rim=True, outline=None):
        img = self.img
        if rim:
            img = rim_light(img, width=10, hl=0.8, sh=0.45, form=0.55, gloss=0.2)
        sil = img[..., 3] > 0.5
        ring = dilate(sil, 4) & ~sil
        oc = outline if outline is not None else outline_of(th)
        base = rgba(np.broadcast_to(oc, sil.shape + (3,)).copy(), ring.astype(np.float32))
        return over(base, img)


# ------------------------------------------------------------------------------------------------ geometry
def axis(a, b):
    a = np.asarray(a, np.float32); b = np.asarray(b, np.float32)
    d = b - a
    L = float(np.hypot(*d))
    d = d / L
    n = np.array((-d[1], d[0]))
    u = (X - a[0]) * d[0] + (Y - a[1]) * d[1]
    v = (X - a[0]) * n[0] + (Y - a[1]) * n[1]
    return u, v, L, d, n


def along(a, b, prof):
    """the shape between a and b with half width prof(t) (t 0..1 along); -> mask, t, vn (-1..1 across; - = lit side)"""
    u, v, L, d, n = axis(a, b)
    t = u / L
    w = np.maximum(prof(np.clip(t, 0, 1)), 1e-3)
    m = (t >= 0) & (t <= 1) & (np.abs(v) <= w)
    return m, t, v / w


def bevel(vn, ridge=0.0):
    """light across a long part: the upper-left side lit; an optional bright ridge along the middle"""
    out = 0.55 - 0.42 * vn
    if ridge:
        out = out + ridge * np.exp(-(vn / 0.18) ** 2)
    return out


def cap(a, b, r):
    d, _ = seg_dist(X, Y, a[0], a[1], b[0], b[1])
    return d <= r


def ell(cx, cy, rx, ry, ang=0.0):
    c, s = math.cos(ang), math.sin(ang)
    dx, dy = X - cx, Y - cy
    u = dx * c + dy * s
    v = -dx * s + dy * c
    return (u / rx) ** 2 + (v / ry) ** 2 <= 1


def ball_light(cx, cy, r, k=1.0):
    """light of a sphere lit from the upper left"""
    lx, ly = cx + LIT[0] * r * 0.45, cy + LIT[1] * r * 0.45
    d = np.hypot(X - lx, Y - ly) / (r * 1.45)
    return np.clip(1.05 - d * k, 0, 1)


def vlight(y0, y1, lo=0.25, hi=0.85):
    return lo + (hi - lo) * np.clip((y1 - Y) / max(y1 - y0, 1), 0, 1)


def hlight(x0, x1, lo=0.3, hi=0.85):
    return lo + (hi - lo) * np.clip((x1 - X) / max(x1 - x0, 1), 0, 1)


def poly(pts):
    return poly_mask(X, Y, pts)


def ringm(cx, cy, r, w, ry=None):
    ry = ry or r
    d = np.sqrt(((X - cx) / r) ** 2 + ((Y - cy) / ry) ** 2) * r
    return np.abs(d - r) <= w


def rot(pts, cx, cy, ang):
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def star(cx, cy, r1, r2, n, ang=-math.pi / 2):
    pts = []
    for k in range(2 * n):
        r = r1 if k % 2 == 0 else r2
        a = ang + k * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return poly(pts)


# ------------------------------------------------------------------------------------------------ motifs
def gem(p, cx, cy, r, mat, glow=None):
    m = ell(cx, cy, r, r)
    p.fill(m, mat, ball_light(cx, cy, r) * 0.9 + 0.05, seam=0.25, wseam=2)
    p.flat(ell(cx - r * 0.35, cy - r * 0.35, max(r * 0.28, 1.6), max(r * 0.22, 1.4)), M[mat][-1])
    if glow:
        p.glow(cx, cy, r * 1.8, glow, 0.35)


def motif_skull(p, th, cx, cy, s):
    head = ell(cx, cy - s * 0.12, s * 0.62, s * 0.56)
    jaw = poly([(cx - s * 0.36, cy + s * 0.2), (cx + s * 0.36, cy + s * 0.2), (cx + s * 0.26, cy + s * 0.62),
                (cx - s * 0.26, cy + s * 0.62)])
    p.fill(head | jaw, 'bone', ball_light(cx, cy - s * 0.1, s * 0.6) * 0.85 + 0.1, seam=0.3, wseam=2)
    for ex in (-1, 1):
        eye = ell(cx + ex * s * 0.24, cy - s * 0.06, s * 0.17, s * 0.15)
        p.flat(eye, M['necro'][2] if th.get('glow_eyes', True) else '#120c08')
        p.flat(ell(cx + ex * s * 0.24, cy - s * 0.06, s * 0.07, s * 0.07), M['necro'][4])
    p.flat(poly([(cx, cy + s * 0.12), (cx - s * 0.08, cy + s * 0.26), (cx + s * 0.08, cy + s * 0.26)]), '#1a140c')
    for k in (-2, -1, 0, 1, 2):
        p.flat((np.abs(X - (cx + k * s * 0.11)) < max(s * 0.025, 1.2)) & (Y > cy + s * 0.36) & (Y < cy + s * 0.6),
               '#3a3020')


def motif_eye(p, th, cx, cy, s):
    outer = ell(cx, cy, s * 0.7, s * 0.42)
    p.fill(outer, 'voidcloth', 0.5, seam=0.4, wseam=2)
    iris = ell(cx, cy, s * 0.34, s * 0.34)
    p.fill(iris, 'voidglow', ball_light(cx, cy, s * 0.34) * 0.7 + 0.25, seam=0.2, wseam=2)
    p.flat(ell(cx, cy, s * 0.1, s * 0.24), '#02030a')
    p.glow(cx, cy, s * 0.7, M['voidglow'][2], 0.4)


def motif_tree(p, th, cx, cy, s):
    trunk = poly([(cx - s * 0.1, cy + s * 0.6), (cx + s * 0.1, cy + s * 0.6), (cx + s * 0.06, cy - s * 0.05),
                  (cx - s * 0.06, cy - s * 0.05)])
    p.fill(trunk, 'wood', hlight(cx - s * 0.1, cx + s * 0.1, 0.4, 0.8), seam=0.2, wseam=2)
    for ang, L in ((-2.4, 0.42), (-0.75, 0.42), (-1.57, 0.5), (2.6, 0.3), (0.55, 0.3)):
        a = (cx, cy + s * 0.1)
        b = (cx + math.cos(ang) * s * L, cy + s * 0.1 + math.sin(ang) * s * L)
        p.fill(cap(a, b, s * 0.05), 'wood', 0.6, seam=0)
    crown = ell(cx, cy - s * 0.25, s * 0.62, s * 0.42)
    p.fill(crown, 'leaf', ball_light(cx, cy - s * 0.3, s * 0.6) * 0.8 + 0.15, seam=0.3, wseam=2)
    for k in range(5):
        a = -math.pi * (0.15 + 0.7 * k / 4)
        p.flat(ell(cx + math.cos(a) * s * 0.36, cy - s * 0.25 + math.sin(a) * s * 0.22, s * 0.1, s * 0.07), M['leaf'][4])


def motif_crescent(p, th, cx, cy, s):
    c = ell(cx, cy, s * 0.6, s * 0.6) & ~ell(cx + s * 0.28, cy - s * 0.12, s * 0.5, s * 0.5)
    p.fill(c, 'moonglow', ball_light(cx - s * 0.2, cy, s * 0.6) * 0.6 + 0.35, seam=0.25, wseam=2)
    for dx, dy, r in ((0.42, -0.42, 0.16), (0.55, 0.25, 0.1)):
        p.flat(star(cx + dx * s, cy + dy * s, r * s, r * s * 0.35, 4), M['moonglow'][4])
    p.glow(cx - s * 0.2, cy, s * 0.6, M['moonglow'][2], 0.3)


def motif_sun(p, th, cx, cy, s):
    p.fill(star(cx, cy, s * 0.66, s * 0.36, 8), 'gold', ball_light(cx, cy, s * 0.6) * 0.8 + 0.2, seam=0.25, wseam=2)
    p.fill(ell(cx, cy, s * 0.32, s * 0.32), 'gold', ball_light(cx, cy, s * 0.3) * 0.6 + 0.4, seam=0.3, wseam=2)
    crs = ((np.abs(X - cx) < s * 0.07) & (np.abs(Y - cy) < s * 0.24)) | \
          ((np.abs(Y - cy + s * 0.04) < s * 0.07) & (np.abs(X - cx) < s * 0.17))
    p.fill(crs, 'ruby', 0.7, seam=0.2, wseam=1)


def motif_cross(p, th, cx, cy, s):
    v = (np.abs(X - cx) < s * 0.15) & (np.abs(Y - cy) < s * 0.62)
    h = (np.abs(Y - cy + s * 0.15) < s * 0.15) & (np.abs(X - cx) < s * 0.46)
    p.fill(v | h, 'red', vlight(cy - s * 0.6, cy + s * 0.6, 0.35, 0.8), seam=0.3, wseam=2)


def motif_snow(p, th, cx, cy, s):
    for k in range(3):
        a = k * math.pi / 3
        dx, dy = math.cos(a) * s * 0.62, math.sin(a) * s * 0.62
        p.fill(cap((cx - dx, cy - dy), (cx + dx, cy + dy), s * 0.09), 'ice', 0.8, seam=0.2, wseam=1)
        for sg in (-1, 1):
            bx, by = cx + sg * dx * 0.6, cy + sg * dy * 0.6
            for sd in (-1, 1):
                aa = a + sd * 0.8 + (math.pi if sg < 0 else 0)
                p.fill(cap((bx, by), (bx + math.cos(aa) * s * 0.2, by + math.sin(aa) * s * 0.2), s * 0.06), 'ice', 0.9,
                       seam=0)
    p.fill(ell(cx, cy, s * 0.16, s * 0.16), 'ice', 1.0, seam=0.2, wseam=1)
    p.glow(cx, cy, s * 0.6, M['ice'][3], 0.3)


def motif_emerald(p, th, cx, cy, s):
    p.fill(star(cx, cy, s * 0.62, s * 0.42, 6, ang=0), 'gold', ball_light(cx, cy, s * 0.6) * 0.7 + 0.25, seam=0.3,
           wseam=2)
    pts = [(cx, cy - s * 0.44), (cx + s * 0.3, cy - s * 0.12), (cx + s * 0.2, cy + s * 0.4), (cx - s * 0.2, cy + s * 0.4),
           (cx - s * 0.3, cy - s * 0.12)]
    p.fill(poly(pts), 'emerald', ball_light(cx, cy, s * 0.4) * 0.8 + 0.15, seam=0.25, wseam=2)
    p.flat(poly([(cx - s * 0.1, cy - s * 0.26), (cx + s * 0.02, cy - s * 0.3), (cx - s * 0.06, cy - s * 0.08)]),
           M['emerald'][4])
    p.glow(cx, cy, s * 0.5, M['emerald'][3], 0.25)


def motif_wing(p, th, cx, cy, s):
    for sg in (-1, 1):
        for k in range(4):
            y = cy - s * 0.3 + k * s * 0.18
            x0 = cx + sg * s * 0.12
            x1 = cx + sg * s * (0.75 - k * 0.12)
            p.fill(cap((x0, y), (x1, y - s * (0.2 - k * 0.05)), s * 0.09), 'ivorygold', 0.75 - k * 0.1, seam=0.3,
                   wseam=1)
    p.fill(ell(cx, cy, s * 0.2, s * 0.24), 'teal', ball_light(cx, cy, s * 0.2) * 0.8 + 0.2, seam=0.2, wseam=2)
    p.glow(cx, cy, s * 0.4, M['teal'][3], 0.35)


def motif_sprout(p, th, cx, cy, s):
    p.fill(cap((cx, cy + s * 0.55), (cx, cy - s * 0.1), s * 0.07), 'orangewood', 0.6, seam=0.2, wseam=1)
    for sg, yy, L in ((-1, 0.1, 0.5), (1, -0.15, 0.55), (-1, -0.42, 0.38)):
        ang = -0.5 if sg > 0 else math.pi + 0.5
        ax, ay = cx, cy + yy * s
        bx, by = ax + math.cos(ang) * s * L, ay + math.sin(ang) * s * L
        m, t, vn = along((ax, ay), (bx, by), lambda t: s * 0.16 * np.sin(np.pi * t) + 0.5)
        p.fill(m, 'green', bevel(vn, 0.2) * 0.9, seam=0.3, wseam=2)
    p.fill(ell(cx, cy - s * 0.6, s * 0.12, s * 0.12), 'lime', 0.95, seam=0.1, wseam=1)
    p.glow(cx, cy - s * 0.4, s * 0.45, M['lime'][3], 0.35)


MOTIF = {'skull': motif_skull, 'eye': motif_eye, 'tree': motif_tree, 'crescent': motif_crescent, 'sun': motif_sun,
         'cross': motif_cross, 'snow': motif_snow, 'emerald': motif_emerald, 'wing': motif_wing,
         'sprout': motif_sprout}


def motif(p, th, cx, cy, s):
    MOTIF[th['motif']](p, th, cx, cy, s)


# ------------------------------------------------------------------------------------------------ weapons
BL, TR = (18.0, 110.0), (110.0, 18.0)     # the diagonal of a weapon: grip at the bottom left, tip at the top right


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def handle(p, th, a, b, r, mat=None, wrap=True):
    m, t, vn = along(a, b, lambda t: r + 0 * t)
    p.fill(m, mat or th['grip'], bevel(vn) * 0.85, seam=0.3, wseam=2)
    if wrap:
        u, v, L, d, n = axis(a, b)
        bands = m & (np.sin(u / 3.2) > 0.55)
        p.fill(bands, mat or th['grip'], bevel(vn) * 0.5, seam=0)


def pommel(p, th, c, r):
    if th.get('pommel') == 'skull':
        motif_skull(p, th, c[0], c[1], r * 1.6)
    else:
        p.fill(ell(c[0], c[1], r, r), th['trim'], ball_light(c[0], c[1], r) * 0.9, seam=0.3, wseam=2)
        if th.get('gem'):
            gem(p, c[0], c[1], r * 0.5, th['gem'], th.get('glowcol'))


def draw_sword(th, style=None):
    p = Pic()
    blade = style or th['blade']
    g0 = lerp(BL, TR, 0.24)                    # guard
    tip = (TR[0] + 2, TR[1] - 2)
    handle(p, th, lerp(BL, TR, 0.04), g0, 4.6)
    pommel(p, th, lerp(BL, TR, 0.02), 7.5)
    # blade profile
    if blade == 'serrated':
        prof = lambda t: (9.5 - 6 * t) + 2.8 * (np.sin(t * 38) > 0) * (t < 0.85)
    elif blade == 'wavy':
        prof = lambda t: (9 - 6.5 * t) * (1 + 0.28 * np.sin(t * 26))
    elif blade == 'leaf':
        prof = lambda t: 4 + 9 * np.sin(np.pi * np.clip(t * 0.95, 0, 1)) ** 0.8 * (1 - 0.3 * t)
    elif blade == 'slim':
        prof = lambda t: 6.5 * (1 - t ** 3) + 0.6
    elif blade == 'broad':
        prof = lambda t: 11.5 * (1 - t ** 4) * (1 - 0.15 * t) + 0.6
    elif blade == 'crystal':
        prof = lambda t: (10 - 7 * t) * (1 + 0.22 * (np.abs(((t * 6) % 1) - 0.5) * 2 - 0.5))
    else:   # long
        prof = lambda t: 8.5 * (1 - t ** 5) + 0.6
    m, t, vn = along(g0, tip, prof)
    # the point: cut the last part to a tip
    p.fill(m, th['metal'], bevel(vn, 0.35 if blade != 'serrated' else 0.1), seam=0.3, wseam=2)
    if th.get('fuller'):
        fm = m & (np.abs(vn) < 0.22) & (t < 0.7) & (t > 0.04)
        p.fill(fm, th['fuller'], 0.55 + 0.3 * (1 - t), seam=0)
    if th.get('edgeglow'):
        em = m & (vn < -0.55) & (t < 0.92)
        p.fill(em, th['edgeglow'], 0.85, seam=0)
    # guard
    u, v, L, d, n = axis(BL, TR)
    gc = np.asarray(g0)
    gw = th.get('guard', 20)
    if th.get('guardstyle') == 'crescent':
        gm = ringm(gc[0] - 4, gc[1] - 4, 15, 3.5) & (((X - gc[0]) * d[0] + (Y - gc[1]) * d[1]) > -2)
        gm |= ell(gc[0], gc[1], 6, 6)
    elif th.get('guardstyle') == 'wing':
        gm = np.zeros_like(m)
        for sg in (-1, 1):
            a = gc + n * sg * 4
            b = gc + n * sg * gw + d * 7
            gm |= cap(a, b, 4.2) | cap(gc + n * sg * 6, gc + n * sg * (gw - 6) + d * 12, 3)
    elif th.get('guardstyle') == 'thorn':
        gm = cap(gc - n * gw, gc + n * gw, 4.2) | cap(gc - n * gw, gc - n * gw + d * 8, 3) | \
            cap(gc + n * gw, gc + n * gw - d * 8, 3)
    else:
        gm = cap(gc - n * gw, gc + n * gw, 4.6)
    p.fill(gm, th['trim'], 0.65 + 0.25 * np.clip(-(((X - gc[0]) * n[0] + (Y - gc[1]) * n[1]) / gw), -1, 1), seam=0.3,
           wseam=2)
    if th.get('gem'):
        gem(p, gc[0], gc[1], 4.6, th['gem'], th.get('glowcol'))
    return p.done(th)


def draw_axe(th, style=None):
    p = Pic()
    a, b = lerp(BL, TR, 0.0), lerp(BL, TR, 0.9)
    handle(p, th, a, b, 5, th['haft'], wrap=False)
    handle(p, th, lerp(BL, TR, 0.02), lerp(BL, TR, 0.22), 5.4)
    u, v, L, d, n = axis(BL, TR)
    hc = np.asarray(lerp(BL, TR, 0.7))
    shape = style or th['axe']
    # blade towards the upper left (-n), socket on the haft
    def P(s_, t_):   # s_ along the haft (px), t_ outwards (px, towards the upper left)
        s_, t_ = s_ * 1.35, t_ * 1.35
        q = hc + d * s_ - n * t_
        return (float(q[0]), float(q[1]))
    if shape == 'crescent':
        outer = ell(*P(0, 22), 30, 26)
        inner = ell(*P(0, 35), 26, 22)
        bm = outer & ~inner & ((X - hc[0]) * (-n[0]) + (Y - hc[1]) * (-n[1]) > 4)
    elif shape == 'jagged':
        bm = poly([P(-14, 4), P(-26, 30), P(-12, 24), P(-6, 40), P(8, 26), P(16, 38), P(22, 22), P(16, 4)])
    elif shape == 'bone':
        bm = poly([P(-12, 4), P(-24, 22), P(-22, 38), P(-4, 30), P(10, 40), P(24, 28), P(16, 4)])
    elif shape == 'winged':
        bm = poly([P(-12, 4), P(-30, 18), P(-26, 40), P(0, 30), P(26, 40), P(30, 18), P(12, 4)])
        bm |= poly([P(-8, -4), P(-16, -18), P(0, -12), P(16, -18), P(8, -4)])
    elif shape == 'double':
        bm = poly([P(-12, 4), P(-26, 34), P(0, 26), P(26, 34), P(12, 4)])
        bm |= poly([P(-10, -4), P(-20, -26), P(0, -20), P(20, -26), P(10, -4)])
    else:   # bearded
        bm = poly([P(-10, 4), P(-30, 16), P(-24, 36), P(4, 32), P(20, 40), P(18, 4)])
    # edge light: the outer rim bright
    tt = np.clip(((X - hc[0]) * (-n[0]) + (Y - hc[1]) * (-n[1])) / 38, 0, 1)
    p.fill(bm, th['metal'], 0.35 + 0.55 * tt + 0.1 * (-(X - hc[0]) * 0.02), seam=0.35, wseam=3)
    edge = bm & ~dilate(~bm, 5) & (tt > 0.55)
    p.fill(bm & dilate(~bm, 4) & (tt > 0.5), th['metal'], 0.98, seam=0)
    del edge
    sock = cap(P(-9, 0), P(9, 0), 6.5)
    p.fill(sock, th['trim'], 0.65, seam=0.3, wseam=2)
    if th.get('axe_motif'):
        motif(p, th, *P(0, 18), 14)
    elif th.get('gem'):
        gem(p, *P(0, 0), 4, th['gem'], th.get('glowcol'))
    top = P(26, 0)
    p.fill(ell(top[0], top[1], 4.5, 4.5), th['trim'], 0.7, seam=0.3, wseam=2)
    return p.done(th)


def draw_club(th, style=None):
    p = Pic()
    shape = style or th['club']
    handle(p, th, lerp(BL, TR, 0.0), lerp(BL, TR, 0.7), 5, th['haft'], wrap=False)
    handle(p, th, lerp(BL, TR, 0.02), lerp(BL, TR, 0.24), 5.6)
    hc = lerp(BL, TR, 0.8)
    u, v, L, d, n = axis(BL, TR)
    if shape == 'skull':
        motif_skull(p, th, hc[0], hc[1] - 2, 30)
    elif shape == 'spiked':
        r = 17
        for k in range(8):
            a = k * math.pi / 4 + 0.2
            tip = (hc[0] + math.cos(a) * (r + 10), hc[1] + math.sin(a) * (r + 10))
            p.fill(poly([(hc[0] + math.cos(a + 0.3) * r, hc[1] + math.sin(a + 0.3) * r), tip,
                         (hc[0] + math.cos(a - 0.3) * r, hc[1] + math.sin(a - 0.3) * r)]), th['trim'], 0.7, seam=0.2,
                   wseam=2)
        p.fill(ell(hc[0], hc[1], r, r), th['metal'], ball_light(hc[0], hc[1], r), seam=0.3, wseam=2)
        if th.get('gem'):
            gem(p, hc[0], hc[1], 6, th['gem'], th.get('glowcol'))
    elif shape == 'gnarled':
        for k, (s_, w_) in enumerate(((-6, 13), (6, 15), (16, 12))):
            c = (hc[0] + d[0] * s_ + n[0] * (3 - 3 * k), hc[1] + d[1] * s_ + n[1] * (3 - 3 * k))
            p.fill(ell(c[0], c[1], w_, w_ * 0.9), th['haft'], ball_light(c[0], c[1], w_), seam=0.3, wseam=2)
        for c, a in (((hc[0] - 12, hc[1] - 10), -2.3), ((hc[0] + 12, hc[1] + 2), 0.2), ((hc[0] + 2, hc[1] - 20), -1.2)):
            m, t, vn = along(c, (c[0] + math.cos(a) * 16, c[1] + math.sin(a) * 16),
                             lambda t: 6 * np.sin(np.pi * t) + 0.5)
            p.fill(m, 'leaf', bevel(vn, 0.25), seam=0.3, wseam=2)
    elif shape == 'hammer':
        P = lambda s_, t_: (hc[0] + d[0] * s_ * 1.4 - n[0] * t_ * 1.4, hc[1] + d[1] * s_ * 1.4 - n[1] * t_ * 1.4)
        hm = poly([P(-12, -16), P(12, -16), P(12, 22), P(-12, 22)])
        p.fill(hm, th['metal'], 0.35 + 0.5 * np.clip((Y - hc[1] - 20) / -40, 0, 1), seam=0.35, wseam=3)
        face = poly([P(-12, 16), P(12, 16), P(12, 22), P(-12, 22)])
        p.fill(face, th['metal'], 0.9, seam=0.2, wseam=2)
        if th.get('club_motif', True):
            motif(p, th, *P(0, 3), 13)
    elif shape == 'orb':
        cage = ringm(hc[0], hc[1], 15, 2.6) | ringm(hc[0], hc[1], 15, 2.6, ry=6)
        p.fill(ell(hc[0], hc[1], 12, 12), th['gem'], ball_light(hc[0], hc[1], 12) * 0.8 + 0.2, seam=0.2, wseam=2)
        p.glow(hc[0], hc[1], 16, M[th['gem']][3], 0.5)
        p.fill(cage, th['trim'], 0.7, seam=0.2, wseam=1)
    else:   # flanged
        r = 17
        for k in range(6):
            a = k * math.pi / 3 + 0.3
            fl = poly([(hc[0] + math.cos(a - 0.22) * 4, hc[1] + math.sin(a - 0.22) * 4),
                       (hc[0] + math.cos(a - 0.1) * (r + 8), hc[1] + math.sin(a - 0.1) * (r + 8)),
                       (hc[0] + math.cos(a + 0.1) * (r + 8), hc[1] + math.sin(a + 0.1) * (r + 8)),
                       (hc[0] + math.cos(a + 0.22) * 4, hc[1] + math.sin(a + 0.22) * 4)])
            p.fill(fl, th['metal'], 0.45 + 0.4 * max(0, -math.cos(a + 0.9)), seam=0.3, wseam=2)
        p.fill(ell(hc[0], hc[1], 8, 8), th['trim'], ball_light(hc[0], hc[1], 8), seam=0.3, wseam=2)
        if th.get('gem'):
            gem(p, hc[0], hc[1], 5, th['gem'], th.get('glowcol'))
    pommel(p, th, lerp(BL, TR, 0.01), 6.5)
    return p.done(th)


def bow_arc(cx, cy, R, ang0, ang1, w0, w1):
    """a limb along an arc (screen angles), tapering"""
    a = np.arctan2(Y - cy, X - cx)
    da = (a - ang0) % (2 * math.pi)
    span = (ang1 - ang0) % (2 * math.pi)
    t = da / span
    w = w0 + (w1 - w0) * np.abs(t - 0.5) * 2
    d = np.hypot(X - cx, Y - cy)
    m = (da <= span) & (np.abs(d - R) <= w)
    vn = (d - R) / np.maximum(w, 1e-3)
    return m, t, vn


def draw_bow(th, style=None):
    p = Pic()
    # string along the diagonal from the bottom left to the top right; the limbs bulge to the upper left
    A, B = (22.0, 106.0), (106.0, 22.0)
    cx, cy = 96.0, 96.0
    R = math.hypot(A[0] - cx, A[1] - cy)
    a0, a1 = math.atan2(A[1] - cy, A[0] - cx), math.atan2(B[1] - cy, B[0] - cx)
    p.fill(cap(A, B, 1.3), 'string', 0.8, seam=0)
    m, t, vn = bow_arc(cx, cy, R, a0, a1, 7.5, 3.0)
    p.fill(m, th['bowmat'], 0.5 - 0.4 * vn, seam=0.35, wseam=2)
    if th.get('bowtrim'):
        mt = m & (vn < -0.2) & (np.abs(t - 0.5) > 0.12)
        p.fill(mt, th['bowtrim'], 0.85, seam=0)
    # grip at the middle
    gm = m & (np.abs(t - 0.5) < 0.09)
    p.fill(gm, th['grip'], 0.55 - 0.3 * vn, seam=0.3, wseam=2)
    mid = (cx - R * 0.7071, cy - R * 0.7071)
    # tips
    tip = th.get('bowtip')
    for P_ in (A, B):
        if tip == 'skull':
            motif_skull(p, th, P_[0], P_[1], 13)
        elif tip == 'leaf':
            m2, t2, vn2 = along(P_, (P_[0] - 12 if P_ is A else P_[0] - 14, P_[1] - 14 if P_ is A else P_[1] - 4),
                                lambda t: 5 * np.sin(np.pi * t) + 0.4)
            p.fill(m2, 'leaf', bevel(vn2, 0.2), seam=0.3, wseam=2)
        elif tip == 'crescent':
            p.fill(ell(P_[0], P_[1], 7, 7) & ~ell(P_[0] + 3, P_[1] - 3, 6, 6), 'moonglow', 0.8, seam=0.2, wseam=1)
        elif tip == 'wing':
            for k in range(3):
                p.fill(cap(P_, (P_[0] - 14 + k * 3, P_[1] - 4 - k * 5), 2.6), th.get('bowtrim') or 'gold',
                       0.8 - 0.1 * k, seam=0.2, wseam=1)
        elif tip == 'crystal':
            p.fill(star(P_[0], P_[1], 8, 3, 4, ang=-0.78), 'ice', 0.9, seam=0.2, wseam=1)
        else:
            p.fill(ell(P_[0], P_[1], 4.5, 4.5), th['trim'], 0.7, seam=0.3, wseam=2)
    if th.get('gem'):
        gem(p, mid[0], mid[1], 4.5, th['gem'], th.get('glowcol'))
    return p.done(th)


def draw_crossbow(th, style=None):
    p = Pic()
    u, v, L, d, n = axis(BL, TR)
    a, b = lerp(BL, TR, 0.04), lerp(BL, TR, 0.86)
    m, t, vn = along(a, b, lambda t: 6.5 - 2.2 * t + 2.5 * (t < 0.25))
    p.fill(m, th['haft'], bevel(vn, 0.2), seam=0.3, wseam=2)
    # the bow arms across the front, bulging forward
    c = np.asarray(lerp(BL, TR, 0.78))
    P = lambda s_, t_: (float(c[0] + d[0] * s_ + n[0] * t_), float(c[1] + d[1] * s_ + n[1] * t_))
    for sg in (-1, 1):
        arm, ta, va = along(P(2, 0), P(-14, sg * 44), lambda t: 6.0 - 3.0 * t)
        p.fill(arm, th['bowmat'], bevel(va * sg) * 0.95, seam=0.3, wseam=2)
        p.fill(cap(P(-14, sg * 44), P(-30, 0), 1.3), 'string', 0.8, seam=0)
    p.fill(cap(P(-2, -6), P(-2, 6), 5.5), th['trim'], 0.7, seam=0.3, wseam=2)
    # bolt in the groove
    p.fill(cap(P(-26, 0), P(14, 0), 1.8), 'wood', 0.7, seam=0)
    p.fill(poly([P(14, -4), P(22, 0), P(14, 4)]), th['metal'], 0.85, seam=0.2, wseam=1)
    # trigger and stirrup
    p.fill(cap(P(-46, 4), P(-50, 12), 2.5), th['trim'], 0.6, seam=0.2, wseam=1)
    if th.get('xbow_motif', True):
        q = P(-38, 0)
        if th['motif'] in ('cross', 'sun', 'emerald', 'wing'):
            gem(p, q[0], q[1], 5, th.get('gem') or 'ruby', th.get('glowcol'))
        else:
            gem(p, q[0], q[1], 5, th.get('gem') or 'ruby', th.get('glowcol'))
    return p.done(th)


def draw_wand(th, style=None):
    p = Pic()
    a, b = (34.0, 98.0), (86.0, 46.0)
    m, t, vn = along(a, b, lambda t: 4.6 - 1.4 * t)
    p.fill(m, th['wandmat'], bevel(vn, 0.25), seam=0.3, wseam=2)
    for tt in (0.25, 0.55):
        q = lerp(a, b, tt)
        p.fill(ell(q[0], q[1], 5.5, 5.5), th['trim'], 0.7, seam=0.3, wseam=2)
    hc = (94.0, 38.0)
    head = th.get('wandhead', 'gem')
    if head == 'skull':
        motif_skull(p, th, hc[0], hc[1], 20)
        p.glow(hc[0], hc[1] - 10, 14, M['necro'][3], 0.5)
    elif head == 'crescent':
        motif_crescent(p, th, hc[0], hc[1], 20)
    elif head == 'star':
        p.fill(star(hc[0], hc[1], 16, 6, 4, ang=-0.78), th['gem'], ball_light(hc[0], hc[1], 14) * 0.7 + 0.3, seam=0.2,
               wseam=2)
        p.glow(hc[0], hc[1], 16, M[th['gem']][3], 0.45)
    elif head == 'leaf':
        for ang in (-2.0, -0.6, -1.3):
            m2, t2, vn2 = along(hc, (hc[0] + math.cos(ang) * 22, hc[1] + math.sin(ang) * 22),
                                lambda t: 6 * np.sin(np.pi * t) + 0.5)
            p.fill(m2, 'leaf', bevel(vn2, 0.2), seam=0.3, wseam=2)
        gem(p, hc[0], hc[1], 6, th['gem'], th.get('glowcol'))
    else:
        cl = poly([(hc[0] - 12, hc[1] + 10), (hc[0] - 4, hc[1] - 4), (hc[0] + 4, hc[1] + 2)]) | \
            poly([(hc[0] - 8, hc[1] + 12), (hc[0] + 6, hc[1] + 6), (hc[0] + 10, hc[1] - 2)])
        p.fill(cl, th['trim'], 0.7, seam=0.3, wseam=2)
        gem(p, hc[0], hc[1] - 3, 9, th['gem'], th.get('glowcol'))
    return p.done(th)


def draw_rod(th, style=None):
    p = Pic()
    a, b = (14.0, 114.0), (82.0, 46.0)
    m, t, vn = along(a, b, lambda t: 4.4 + 0.8 * t)
    p.fill(m, th['rodmat'], bevel(vn, 0.2), seam=0.3, wseam=2)
    q = lerp(a, b, 0.0)
    p.fill(ell(q[0], q[1], 5, 5), th['trim'], 0.6, seam=0.3, wseam=2)
    hc = (92.0, 36.0)
    head = th.get('rodhead', 'claw')
    if head == 'crescent':
        c = ell(hc[0], hc[1], 24, 24) & ~ell(hc[0] + 10, hc[1] - 8, 21, 21)
        p.fill(c, th['trim'], ball_light(hc[0] - 6, hc[1], 22) * 0.8 + 0.15, seam=0.3, wseam=2)
        gem(p, hc[0] + 2, hc[1] + 2, 8, th['gem'], th.get('glowcol'))
    elif head == 'skull':
        p.fill(cap(b, (hc[0] - 14, hc[1] - 18), 3.5), 'bone', 0.7, seam=0.3, wseam=2)
        p.fill(cap(b, (hc[0] + 18, hc[1] + 14), 3.5), 'bone', 0.6, seam=0.3, wseam=2)
        motif_skull(p, th, hc[0] + 2, hc[1] - 2, 24)
        p.glow(hc[0], hc[1], 20, M['necro'][3], 0.5)
    elif head == 'branch':
        for ang, L in ((-2.2, 26), (-1.0, 28), (-0.2, 22)):
            p.fill(cap(b, (b[0] + math.cos(ang) * L, b[1] + math.sin(ang) * L), 3.2), th['rodmat'], 0.6, seam=0.3,
                   wseam=2)
            tip = (b[0] + math.cos(ang) * L, b[1] + math.sin(ang) * L)
            m2, t2, vn2 = along(tip, (tip[0] + math.cos(ang - 0.6) * 12, tip[1] + math.sin(ang - 0.6) * 12),
                                lambda t: 4.5 * np.sin(np.pi * t) + 0.4)
            p.fill(m2, 'leaf' if th['motif'] != 'sprout' else 'green', bevel(vn2, 0.2), seam=0.3, wseam=2)
        gem(p, b[0] + 6, b[1] - 8, 8, th['gem'], th.get('glowcol'))
    elif head == 'sun':
        motif_sun(p, th, hc[0], hc[1], 30)
        p.glow(hc[0], hc[1], 20, M['gold'][4], 0.3)
    elif head == 'wing':
        motif_wing(p, th, hc[0], hc[1], 34)
    elif head == 'crystal':
        for k, (dx, dy, r) in enumerate(((0, -8, 14), (-10, 4, 9), (11, 6, 9))):
            p.fill(star(hc[0] + dx, hc[1] + dy, r, r * 0.35, 3, ang=-math.pi / 2 + k * 0.4), 'ice',
                   ball_light(hc[0], hc[1], 20) * 0.7 + 0.3, seam=0.25, wseam=2)
        p.glow(hc[0], hc[1], 18, M['ice'][3], 0.45)
    else:   # claw holding an orb
        for sg in (-1, 1):
            p.fill(cap(b, (hc[0] - sg * 16, hc[1] - 16 + sg * 2), 3.6), th['trim'], 0.65, seam=0.3, wseam=2)
            p.fill(cap((hc[0] - sg * 16, hc[1] - 16 + sg * 2), (hc[0] - sg * 4, hc[1] - 24), 3), th['trim'], 0.75,
                   seam=0.3, wseam=2)
        gem(p, hc[0], hc[1] - 4, 12, th['gem'], th.get('glowcol'))
    return p.done(th)


# ------------------------------------------------------------------------------------------------ shield, book
def draw_shield(th, style=None):
    p = Pic()
    shape = style or th['shield']
    cx, cy = 64.0, 62.0
    if shape in ('round', 'round_spiked', 'round_wood'):
        r = 46
        body = ell(cx, cy, r, r)
        rim = body & ~ell(cx, cy, r - 7, r - 7)
        p.fill(body, th['shieldface'] if shape != 'round_wood' else 'wood',
               ball_light(cx, cy, r) * 0.8 + 0.1, seam=0.3, wseam=3)
        if shape == 'round_wood':
            planks = body & (np.abs(((X - cx) % 18) - 9) < 1.2)
            p.fill(planks, 'wood', 0.2, seam=0)
        p.fill(rim, th['trim'], ball_light(cx, cy, r) * 0.9 + 0.1, seam=0.25, wseam=2)
        if shape == 'round_spiked':
            for k in range(8):
                a = k * math.pi / 4
                q = (cx + math.cos(a) * (r - 3), cy + math.sin(a) * (r - 3))
                p.fill(star(q[0], q[1], 8, 3, 4, ang=a), th['trim'], 0.85, seam=0.2, wseam=1)
        for k in range(8):
            a = k * math.pi / 4 + math.pi / 8
            q = (cx + math.cos(a) * (r - 3.5), cy + math.sin(a) * (r - 3.5))
            p.fill(ell(q[0], q[1], 2.6, 2.6), th['trim'], 1.0, seam=0)
        motif(p, th, cx, cy, 30)
    else:
        if shape == 'kite':
            pts = [(cx - 36, cy - 44), (cx + 36, cy - 44), (cx + 38, cy - 6), (cx, cy + 52), (cx - 38, cy - 6)]
        elif shape == 'tower':
            pts = [(cx - 34, cy - 48), (cx, cy - 54), (cx + 34, cy - 48), (cx + 34, cy + 30), (cx, cy + 52),
                   (cx - 34, cy + 30)]
        elif shape == 'crystal':
            pts = [(cx, cy - 54), (cx + 40, cy - 22), (cx + 30, cy + 30), (cx, cy + 54), (cx - 30, cy + 30),
                   (cx - 40, cy - 22)]
        else:   # heater
            pts = [(cx - 40, cy - 44), (cx + 40, cy - 44), (cx + 40, cy + 2), (cx + 20, cy + 36), (cx, cy + 50),
                   (cx - 20, cy + 36), (cx - 40, cy + 2)]
        body = poly(pts)
        inner = poly([(cx + (x - cx) * 0.82, cy - 2 + (y - cy) * 0.82) for x, y in pts])
        p.fill(body, th['trim'], vlight(cy - 50, cy + 50, 0.4, 0.95), seam=0.3, wseam=3)
        p.fill(inner, th['shieldface'], ball_light(cx, cy - 6, 44) * 0.75 + 0.15, seam=0.3, wseam=2)
        if th.get('quarter'):
            q = inner & (((X > cx) & (Y < cy - 6)) | ((X < cx) & (Y > cy - 6)))
            p.fill(q, th['quarter'], ball_light(cx, cy - 6, 44) * 0.7 + 0.15, seam=0)
        motif(p, th, cx, cy - 6, 34)
    return p.done(th)


def draw_spellbook(th, style=None):
    p = Pic()
    # a closed book in three-quarter view: cover (front), pages on the right / bottom, spine on the left
    cov = [(26, 22), (92, 14), (104, 92), (36, 106)]
    pages = [(92, 14), (102, 20), (112, 96), (104, 92)]
    bottom = [(36, 106), (104, 92), (112, 96), (44, 112)]
    p.fill(poly(pages) | poly(bottom), 'ivory', 0.75, seam=0.3, wseam=2)
    p.fill(poly(bottom) & (np.sin((Y - X * 0.2) * 1.4) > 0.3), 'ivory', 0.45, seam=0)
    p.fill(poly(cov), th['bookmat'], vlight(14, 106, 0.3, 0.85), seam=0.3, wseam=3)
    # corners and spine bands of the trim metal
    for q in cov:
        p.fill(ell(q[0] + (8 if q[0] < 60 else -8) * 0.7, q[1] + (8 if q[1] < 60 else -8) * 0.7, 9, 9) & poly(cov),
               th['trim'], 0.8, seam=0.3, wseam=2)
    spine = cap((28, 28), (37, 100), 5)
    p.fill(spine, th['trim'], hlight(22, 40, 0.4, 0.9), seam=0.3, wseam=2)
    motif(p, th, 64, 60, 28)
    # clasp
    p.fill(poly([(98, 52), (112, 50), (114, 62), (100, 64)]), th['trim'], 0.7, seam=0.3, wseam=2)
    return p.done(th)


# ------------------------------------------------------------------------------------------------ armour
def draw_helmet(th, style=None):
    p = Pic()
    st = style or th['helm']
    cx = 64.0
    if st == 'hat':     # a wizard hat: wide brim, a tall bent cone
        brim = ell(cx, 92, 50, 13)
        p.fill(brim, th['cloth'], vlight(80, 104, 0.25, 0.75), seam=0.3, wseam=3)
        cone = poly([(cx - 30, 92), (cx + 30, 92), (cx + 14, 50), (cx + 30, 18), (cx + 4, 40), (cx - 10, 60)])
        p.fill(cone, th['cloth'], hlight(cx - 30, cx + 30, 0.3, 0.85), seam=0.3, wseam=3)
        band = cone & (Y > 78) & (Y < 88)
        p.fill(band, th['trim'], 0.75, seam=0.2, wseam=1)
        motif(p, th, cx, 74, 16)
        return p.done(th)
    if st == 'hood':
        hood = ell(cx, 62, 40, 46) | poly([(cx - 40, 66), (cx + 40, 66), (cx + 46, 108), (cx - 46, 108)])
        p.fill(hood, th['cloth'], ball_light(cx, 56, 44) * 0.8 + 0.1, seam=0.3, wseam=3)
        face = ell(cx, 72, 23, 28)
        p.fill(face, th['cloth'], 0.05, seam=0)
        p.flat(face & (Y > 62), '#05040a')
        for ex in (-9, 9):
            p.flat(ell(cx + ex, 74, 4, 2.6), M[th['gem']][3] if th.get('gem') else '#c8c0a0')
        p.fill(hood & (Y > 98), th['trim'], 0.7, seam=0.2, wseam=2)
        if th.get('hoodleaf'):
            for k in range(5):
                a = -math.pi * (0.1 + 0.8 * k / 4)
                q = (cx + math.cos(a) * 38, 58 + math.sin(a) * 42)
                m2, t2, vn2 = along(q, (q[0] + math.cos(a) * 14, q[1] + math.sin(a) * 14),
                                    lambda t: 5 * np.sin(np.pi * t) + 0.4)
                p.fill(m2, th.get('hoodleaf'), bevel(vn2, 0.2), seam=0.3, wseam=2)
        return p.done(th)
    # helms: a dome with cheek guards
    dome = ell(cx, 58, 38, 40) & (Y < 80)
    cheeks = poly([(cx - 38, 56), (cx + 38, 56), (cx + 34, 100), (cx + 12, 106), (cx - 12, 106), (cx - 34, 100)])
    if st == 'great':
        cheeks = poly([(cx - 36, 40), (cx + 36, 40), (cx + 36, 104), (cx - 36, 104)])
        dome = ell(cx, 44, 36, 30)
    body = dome | cheeks
    p.fill(body, th['metal'], ball_light(cx - 4, 50, 46) * 0.85 + 0.1, seam=0.3, wseam=3)
    if st == 'skull':
        motif_skull(p, th, cx, 70, 44)
        for sg in (-1, 1):
            horn = along((cx + sg * 30, 40), (cx + sg * 50, 8), lambda t: 7 * (1 - t) + 0.8)
            p.fill(horn[0], 'bone', bevel(horn[2] * sg, 0.2), seam=0.3, wseam=2)
    elif st == 'void':
        p.fill(poly([(cx - 30, 66), (cx + 30, 66), (cx + 26, 74), (cx - 26, 74)]), 'voidglow', 0.75, seam=0.1, wseam=1)
        p.glow(cx, 70, 20, M['voidglow'][2], 0.4)
        for sg in (-1, 1):
            spike = along((cx + sg * 20, 26), (cx + sg * 36, 2), lambda t: 6 * (1 - t) + 0.6)
            p.fill(spike[0], th['metal'], bevel(spike[2] * sg, 0.3), seam=0.3, wseam=2)
        p.fill(along((cx, 22), (cx, 0), lambda t: 6 * (1 - t) + 0.6)[0], th['metal'], 0.85, seam=0.3, wseam=2)
    elif st == 'winged':
        p.fill(poly([(cx - 6, 64), (cx + 6, 64), (cx + 4, 100), (cx - 4, 100)]), th['metal'], 0.9, seam=0.2, wseam=1)
        for ex in (-14, 14):
            p.flat(ell(cx + ex, 70, 9, 4), '#060814')
        for sg in (-1, 1):
            for k in range(3):
                p.fill(cap((cx + sg * 34, 50 - k * 6), (cx + sg * (60 - k * 6), 22 - k * 9), 4.5 - k * 0.8),
                       th['wingmat'], 0.85 - k * 0.1, seam=0.3, wseam=1)
        motif(p, th, cx, 34, 18)
    elif st == 'great':
        slit = (np.abs(Y - 62) < 3.5) & (np.abs(X - cx) < 30)
        p.flat(slit, '#050608')
        breath = (np.abs(X - cx) < 3) & (Y > 68) & (Y < 96)
        p.flat(breath, '#050608')
        motif(p, th, cx, 82, 26) if th['motif'] == 'cross' else None
        if th.get('plume'):
            pl = poly([(cx - 6, 18), (cx + 4, 6), (cx + 30, 0), (cx + 44, 18), (cx + 30, 12), (cx + 8, 22)])
            p.fill(pl, th['plume'], vlight(0, 24, 0.4, 0.9), seam=0.3, wseam=2)
    elif st == 'crown':
        p.fill(poly([(cx - 26, 70), (cx + 26, 70), (cx + 22, 78), (cx - 22, 78)]), '#06080a' if False else th['cloth'],
               0.15, seam=0)
        for k in range(5):
            x = cx - 32 + k * 16
            p.fill(poly([(x - 6, 28), (x, 6 + (k % 2) * 8), (x + 6, 28)]), th['trim'], 0.85, seam=0.3, wseam=2)
        p.fill((Y > 24) & (Y < 34) & dome, th['trim'], 0.8, seam=0.3, wseam=2)
        motif(p, th, cx, 46, 18)
    else:   # plumed (holy) / crystal (frost)
        p.fill(poly([(cx - 30, 64), (cx + 30, 64), (cx + 4, 98), (cx - 4, 98)]) & ~poly(
            [(cx - 4, 64), (cx + 4, 64), (cx + 4, 98), (cx - 4, 98)]), 'ironblk', 0.15, seam=0)
        p.fill(poly([(cx - 4, 58), (cx + 4, 58), (cx + 4, 100), (cx - 4, 100)]), th['trim'], 0.85, seam=0.2, wseam=1)
        if st == 'crystal':
            for k, (dx, h) in enumerate(((-24, 30), (-8, 46), (8, 46), (24, 30))):
                p.fill(star(cx + dx, 30 - h * 0.25, 7, 2.5, 3, ang=-math.pi / 2), 'ice', 0.9, seam=0.2, wseam=1)
                p.fill(poly([(cx + dx - 6, 30), (cx + dx, 30 - h * 0.5), (cx + dx + 6, 30)]), 'ice', 0.8, seam=0.25,
                       wseam=2)
        else:
            pl = poly([(cx - 8, 22), (cx - 2, 2), (cx + 14, -2), (cx + 36, 10), (cx + 46, 34), (cx + 26, 20),
                       (cx + 8, 24)])
            p.fill(pl, th.get('plume', 'crimson'), vlight(0, 30, 0.35, 0.95), seam=0.3, wseam=2)
            motif(p, th, cx, 40, 16)
    return p.done(th)


def torso(cx, top, bot, wsh, wwa):
    return poly([(cx - wsh, top + 10), (cx - wsh + 10, top), (cx + wsh - 10, top), (cx + wsh, top + 10),
                 (cx + wwa, bot), (cx - wwa, bot)])


def draw_armor(th, style=None):
    p = Pic()
    st = style or th['armor']
    cx = 64.0
    if st == 'robe':
        body = poly([(cx - 24, 14), (cx + 24, 14), (cx + 34, 30), (cx + 44, 114), (cx - 44, 114), (cx - 34, 30)])
        p.fill(body, th['cloth'], hlight(cx - 44, cx + 44, 0.25, 0.85), seam=0.3, wseam=3)
        for sg in (-1, 1):
            sl = poly([(cx + sg * 30, 24), (cx + sg * 56, 64), (cx + sg * 50, 74), (cx + sg * 32, 56)])
            p.fill(sl, th['cloth'], 0.5 - 0.15 * sg, seam=0.3, wseam=3)
        p.fill(body & (np.abs(X - cx) < 7), th['trim'], 0.75, seam=0.2, wseam=1)
        p.fill(body & (Y > 104), th['trim'], 0.6, seam=0.2, wseam=1)
        p.fill(poly([(cx - 22, 14), (cx + 22, 14), (cx, 40)]), th['trim'], 0.8, seam=0.3, wseam=2)
        motif(p, th, cx, 54, 22)
        return p.done(th)
    body = torso(cx, 22, 104, 48, 34)
    p.fill(body, th['metal'] if st != 'jerkin' else th.get('jerkinmat', th['cloth']), ball_light(cx - 8, 50, 60) * 0.8 + 0.12, seam=0.3,
           wseam=3)
    neck = ell(cx, 22, 16, 8)
    p.fill(neck, 'ironblk', 0.1, seam=0)
    for sg in (-1, 1):   # pauldrons
        pa = ell(cx + sg * 40, 32, 18, 14)
        p.fill(pa, th['trim'], ball_light(cx + sg * 40, 28, 18) * 0.8 + 0.15, seam=0.3, wseam=2)
        if st == 'spiked' or th.get('spikes'):
            p.fill(along((cx + sg * 44, 24), (cx + sg * 58, 4), lambda t: 5 * (1 - t) + 0.5)[0], 'bone'
                   if th['motif'] == 'skull' else th['trim'], 0.8, seam=0.3, wseam=1)
    if st == 'ribs':
        for k in range(4):
            y = 50 + k * 12
            for sg in (-1, 1):
                p.fill(cap((cx + sg * 4, y), (cx + sg * 26, y + 6), 3.4), 'bone', 0.85, seam=0.3, wseam=1)
        p.fill(cap((cx, 40), (cx, 98), 4.2), 'bone', 0.9, seam=0.3, wseam=1)
        motif_skull(p, th, cx, 30, 18)
    elif st == 'tabard':
        tb = poly([(cx - 22, 26), (cx + 22, 26), (cx + 24, 114), (cx - 24, 114)])
        p.fill(tb, 'white', hlight(cx - 24, cx + 24, 0.4, 0.95), seam=0.3, wseam=2)
        motif_cross(p, th, cx, 64, 34)
        p.fill(body & (Y > 84) & (Y < 92) & ~tb, 'leather', 0.5, seam=0.2, wseam=1)
    elif st == 'leaf':
        for k in range(5):
            for j in range(-2, 3):
                q = (cx + j * 15 + (k % 2) * 7, 42 + k * 13)
                lm = ell(q[0], q[1], 7.5, 9.5) & body
                p.fill(lm, th['scale'], 0.55 + 0.3 * (1 - k / 5) - 0.06 * j, seam=0.35, wseam=2)
        p.fill(body & (Y > 92) & (Y < 100), 'leather', 0.55, seam=0.2, wseam=1)
        motif(p, th, cx, 46, 16) if th['motif'] != 'tree' else motif_tree(p, th, cx, 50, 16)
    elif st == 'jerkin':
        for k in range(3):
            p.fill(body & (np.abs(Y - (56 + k * 16)) < 2.2), th['trim'], 0.5, seam=0)
        p.fill(cap((cx - 34, 30), (cx + 28, 98), 4.2), th['trim'], 0.7, seam=0.3, wseam=1)
        motif(p, th, cx, 56, 16)
    else:   # plate / crystal / regal: a breastplate with a centre ridge and a belt
        p.fill(body & (np.abs(X - cx) < 3), th['metal'], 0.95, seam=0)
        belt = body & (Y > 88) & (Y < 98)
        p.fill(belt, th.get('beltmat', 'leather'), 0.55, seam=0.2, wseam=1)
        if st == 'crystal':
            for q in ((cx - 18, 54), (cx + 18, 54), (cx, 74)):
                p.fill(star(q[0], q[1], 10, 4, 3, ang=-math.pi / 2), 'ice', 0.9, seam=0.25, wseam=1)
            motif(p, th, cx, 40, 16)
        else:
            motif(p, th, cx, 56, 26)
        if th.get('skirt'):
            sk = poly([(cx - 34, 98), (cx + 34, 98), (cx + 38, 116), (cx - 38, 116)])
            p.fill(sk, th['skirt'], 0.5, seam=0.3, wseam=2)
    return p.done(th)


def draw_legs(th, style=None):
    p = Pic()
    st = style or th['legs']
    cx = 64.0
    if st == 'skirt':
        sk = poly([(cx - 30, 16), (cx + 30, 16), (cx + 46, 112), (cx - 46, 112)])
        p.fill(sk, th['cloth'], hlight(cx - 46, cx + 46, 0.25, 0.85), seam=0.3, wseam=3)
        for k in (-2, -1, 1, 2):
            p.fill(sk & (np.abs(X - cx - k * 14 - (Y - 16) * k * 0.05) < 1.6), th['cloth'], 0.2, seam=0)
        p.fill(sk & (Y < 26), th['trim'], 0.8, seam=0.2, wseam=1)
        p.fill(sk & (Y > 102), th['trim'], 0.6, seam=0.2, wseam=1)
        motif(p, th, cx, 22, 10)
        return p.done(th)
    mat = th['metal'] if st != 'leather' else th.get('jerkinmat', th['cloth'])
    belt = poly([(cx - 34, 14), (cx + 34, 14), (cx + 34, 28), (cx - 34, 28)])
    for sg in (-1, 1):
        leg = poly([(cx + sg * 2, 26), (cx + sg * 34, 26), (cx + sg * 30, 112), (cx + sg * 8, 112)])
        p.fill(leg, mat, hlight(cx + sg * 2 - 20 * (sg < 0) - 6, cx + sg * 34, 0.25, 0.9) if sg > 0 else
               hlight(cx - 34, cx - 2, 0.35, 0.9), seam=0.3, wseam=3)
        knee = ell(cx + sg * 18, 68, 12, 10)
        p.fill(knee, th['trim'], ball_light(cx + sg * 18, 66, 12) * 0.8 + 0.15, seam=0.3, wseam=2)
        if th.get('gem') and st != 'leather':
            gem(p, cx + sg * 18, 68, 4, th['gem'], th.get('glowcol'))
        for k in range(3):
            p.fill(leg & (np.abs(Y - (40 + k * 10)) < 1.4), mat, 0.15, seam=0)
            p.fill(leg & (np.abs(Y - (86 + k * 9)) < 1.4), mat, 0.15, seam=0)
    p.fill(belt, th.get('beltmat', 'leather') if st != 'plate' else th['trim'], vlight(14, 28, 0.4, 0.8), seam=0.3,
           wseam=2)
    p.fill(ell(cx, 21, 7, 6), th['trim'], 0.9, seam=0.3, wseam=1)
    if th.get('tasset'):
        ts = poly([(cx - 12, 28), (cx + 12, 28), (cx + 8, 56), (cx, 62), (cx - 8, 56)])
        p.fill(ts, th['tasset'], vlight(28, 62, 0.35, 0.85), seam=0.3, wseam=2)
    return p.done(th)


def draw_boots(th, style=None):
    p = Pic()
    mat = th.get('bootmat') or th['metal']
    for k, ox in enumerate((-4.0, 30.0)):   # the back boot first (left, darker), then the front one
        oy = -10 if k == 0 else 0
        shaft = poly([(ox + 26, oy + 18), (ox + 54, oy + 18), (ox + 56, oy + 82), (ox + 26, oy + 82)])
        foot = poly([(ox + 22, oy + 76), (ox + 58, oy + 74), (ox + 80, oy + 92), (ox + 82, oy + 106), (ox + 22, oy + 106)])
        lv = 0.75 if k else 0.5
        p.fill(shaft | foot, mat, hlight(ox + 20, ox + 82, 0.2, lv), seam=0.3, wseam=3)
        sole = poly([(ox + 20, oy + 102), (ox + 84, oy + 102), (ox + 84, oy + 110), (ox + 20, oy + 110)])
        p.fill(sole, 'ironblk' if th['metal'] not in ('leather', 'wood') else 'leather', 0.2, seam=0.2, wseam=1)
        cuff = poly([(ox + 22, oy + 12), (ox + 58, oy + 12), (ox + 58, oy + 26), (ox + 22, oy + 26)])
        p.fill(cuff, th['trim'], vlight(oy + 12, oy + 26, 0.45, 0.9), seam=0.3, wseam=2)
        if th.get('bootwing'):
            for j in range(3):
                p.fill(cap((ox + 26, oy + 30 + j * 6), (ox + 4 - j * 2, oy + 16 + j * 10), 3.2 - j * 0.5),
                       th['bootwing'], 0.85 - 0.1 * j, seam=0.2, wseam=1)
        if k == 1:
            if th.get('gem'):
                gem(p, ox + 40, oy + 19, 4.5, th['gem'], th.get('glowcol'))
            p.fill(cap((ox + 44, oy + 86), (ox + 74, oy + 92), 3), th['trim'], 0.7, seam=0.2, wseam=1)
    return p.done(th)


# ------------------------------------------------------------------------------------------------ jewellery, pack
def draw_amulet(th, style=None):
    p = Pic()
    cx, cy = 64.0, 44.0
    chain = ringm(cx, cy - 8, 36, 2.6, ry=34) & (Y < 70)
    links = chain & (np.sin(np.arctan2(Y - cy + 8, X - cx) * 22) > -0.2)
    p.fill(links, th['trim'], 0.75, seam=0.2, wseam=1)
    pc = (cx, 86.0)
    if th['motif'] in ('skull',):
        motif_skull(p, th, pc[0], pc[1], 34)
    elif th['motif'] == 'tree':
        p.fill(ell(pc[0], pc[1], 18, 22), 'bronze', ball_light(pc[0], pc[1], 20) * 0.8 + 0.15, seam=0.3, wseam=2)
        for ang in (-2.3, -0.8):
            m2, t2, vn2 = along((pc[0], pc[1] - 14), (pc[0] + math.cos(ang) * 24, pc[1] - 14 + math.sin(ang) * 24),
                                lambda t: 7 * np.sin(np.pi * t) + 0.5)
            p.fill(m2, 'leaf', bevel(vn2, 0.2), seam=0.3, wseam=2)
        gem(p, pc[0], pc[1] + 2, 10, th['gem'], th.get('glowcol'))
    else:
        p.fill(ell(pc[0], pc[1], 22, 24), th['trim'], ball_light(pc[0], pc[1], 22) * 0.85 + 0.12, seam=0.3, wseam=2)
        motif(p, th, pc[0], pc[1], 26)
    p.fill(ell(cx, 64, 5, 5), th['trim'], 0.8, seam=0.3, wseam=1)
    return p.done(th)


def draw_ring(th, style=None):
    p = Pic()
    cx, cy = 62.0, 74.0
    band = ringm(cx, cy, 30, 7, ry=20)
    back = band & (Y < cy)
    front = band & (Y >= cy)
    p.fill(back, th['trim'], 0.35, seam=0.3, wseam=2)
    p.fill(front, th['trim'], hlight(cx - 30, cx + 30, 0.45, 0.95), seam=0.3, wseam=2)
    # setting on the front top
    sc = (cx, cy - 22)
    p.fill(ell(sc[0], sc[1] + 4, 20, 14), th['metal'] if th['metal'] != 'bone' else 'ironblk', 0.6, seam=0.3, wseam=2)
    if th['motif'] == 'skull':
        motif_skull(p, th, sc[0], sc[1] - 4, 26)
    elif th['motif'] in ('crescent', 'eye', 'snow', 'wing', 'sprout', 'tree'):
        gem(p, sc[0], sc[1] - 2, 14, th['gem'], th.get('glowcol'))
        if th['motif'] == 'crescent':
            p.fill(ell(sc[0], sc[1] - 2, 9, 9) & ~ell(sc[0] + 4, sc[1] - 5, 8, 8), 'white', 0.95, seam=0)
        if th['motif'] == 'eye':
            p.flat(ell(sc[0], sc[1] - 2, 3, 8), '#02030a')
    else:
        gem(p, sc[0], sc[1] - 2, 14, th['gem'] or 'ruby', th.get('glowcol'))
        if th['motif'] == 'cross':
            motif_cross(p, th, sc[0], sc[1] - 2, 14)
    return p.done(th)


def draw_backpack(th, style=None):
    p = Pic()
    cx = 64.0
    body = poly([(cx - 40, 34), (cx + 40, 34), (cx + 46, 108), (cx - 46, 108)]) | ell(cx, 36, 40, 16)
    p.fill(body, th['packmat'], ball_light(cx - 6, 60, 64) * 0.8 + 0.12, seam=0.3, wseam=3)
    for sg in (-1, 1):
        pk = poly([(cx + sg * 46, 62), (cx + sg * 58, 66), (cx + sg * 56, 102), (cx + sg * 46, 104)])
        p.fill(pk, th['packmat'], 0.35 if sg > 0 else 0.6, seam=0.3, wseam=2)
    flap = poly([(cx - 38, 30), (cx + 38, 30), (cx + 36, 70), (cx, 78), (cx - 36, 70)]) | ell(cx, 32, 38, 14)
    p.fill(flap, th['packflap'], vlight(18, 78, 0.35, 0.9), seam=0.3, wseam=3)
    handle_ = ringm(cx, 22, 16, 3.6, ry=12) & (Y < 22)
    p.fill(handle_, 'leather', 0.6, seam=0.2, wseam=1)
    for sg in (-1, 1):
        st = poly([(cx + sg * 22 - 4, 70), (cx + sg * 22 + 4, 70), (cx + sg * 24 + 4, 108), (cx + sg * 24 - 4, 108)])
        p.fill(st, 'leather', 0.5, seam=0.25, wseam=1)
        p.fill(ell(cx + sg * 22, 70, 5, 4), th['trim'], 0.85, seam=0.2, wseam=1)
    motif(p, th, cx, 52, 22)
    return p.done(th)


# ------------------------------------------------------------------------------------------------ ammunition
STACK = (1, 2, 3, 4, 5, 10, 25, 50)   # the client's stack patterns (count -> pattern 0..7)


def arrow_shape(p, th, a, b, bolt=False):
    m, t, vn = along(a, b, lambda t: (3.4 if bolt else 2.6) + 0 * t)
    p.fill(m, th.get('shaftmat', 'wood'), bevel(vn), seam=0.3, wseam=1)
    u, v, L, d, n = axis(a, b)
    tip = np.asarray(b)
    hl = 18 if bolt else 16
    hw = 8 if bolt else 7
    base = tip - d * hl
    p.fill(poly([tuple(base + n * hw), tuple(tip + d * 4), tuple(base - n * hw), tuple(base + d * 3)]),
           th['headmat'], 0.55 + 0.35 * np.clip(-((X - tip[0]) * n[0] + (Y - tip[1]) * n[1]) / hw, -1, 1), seam=0.3,
           wseam=1)
    fa = np.asarray(a)
    fl = th.get('fletch', 'white')
    for sg in (-1, 1):
        p.fill(poly([tuple(fa + d * 2), tuple(fa + d * (16 if not bolt else 12) + n * sg * 1.5),
                     tuple(fa + d * (4 if not bolt else 2) + n * sg * (8 if not bolt else 6)),
                     tuple(fa - d * 2 + n * sg * 6)]), fl, 0.75 if sg < 0 else 0.45, seam=0.3, wseam=1)


def draw_ammo(th, count, bolt=False):
    """1-5 pieces fanned from the nock end; 10, 25 and 50 as bigger fans tied with a leather band"""
    p = Pic()
    shown = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 10: 5, 25: 6, 50: 7}[count]
    L = 92.0 if not bolt else 70.0
    spread = 0.13 if shown < 6 else 0.11
    piv = np.array((26.0, 102.0)) if not bolt else np.array((36.0, 92.0))
    for k in range(shown):
        o = k - (shown - 1) / 2
        ang = -math.pi / 4 + o * spread
        a = piv + np.array((1, 1)) / math.sqrt(2) * o * 3.0
        b = a + np.array((math.cos(ang), math.sin(ang))) * L
        arrow_shape(p, th, tuple(a), tuple(b), bolt)
    if count >= 10:
        c = piv + np.array((1, -1)) / math.sqrt(2) * L * 0.34
        u = ell(c[0], c[1], 7, 16, math.pi / 4) & dilate(p.img[..., 3] > 0.5, 3)
        p.fill(u, 'leather', 0.6, seam=0.3, wseam=1)
    return p.done(th)


def draw_arrow(th, style=None):
    return [draw_ammo(th, c) for c in STACK]


def draw_bolt(th, style=None):
    return [draw_ammo(th, c, bolt=True) for c in STACK]


DRAW = {'sword': draw_sword, 'axe': draw_axe, 'club': draw_club, 'bow': draw_bow, 'crossbow': draw_crossbow,
        'wand': draw_wand, 'rod': draw_rod, 'shield': draw_shield, 'helmet': draw_helmet, 'armor': draw_armor,
        'legs': draw_legs, 'boots': draw_boots, 'amulet': draw_amulet, 'ring': draw_ring, 'backpack': draw_backpack,
        'spellbook': draw_spellbook, 'arrow': draw_arrow, 'bolt': draw_bolt}


def to32(img):
    return finish(img, F, False, 0.35)


def render(kind, th, style=None):
    """-> list of 32 x 32 RGBA uint8 (one per stack pattern; one for most kinds)"""
    out = DRAW[kind](th, style)
    if isinstance(out, list):
        return [to32(o) for o in out]
    return [to32(out)]
