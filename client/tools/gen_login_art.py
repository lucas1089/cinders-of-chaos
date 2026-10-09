#!/usr/bin/env python3
"""Procedural art of the login screen (module client_chaos_login).

  python3 -I client/tools/gen_login_art.py [bg] [ui]      (no argument = both; needs Pillow + numpy)

bg  data/images/title.png                 1920x1080 background: night sky, ruined cathedral with red windows,
                                          thorn vines on both sides, iron gate and graveyard, fog, lava-cracked
                                          ground, baked-in embers and vignette. A single file: replace it with any
                                          16:9 picture (the client crops it to the window, see login.lua).
    data/images/chaos/login/glow.png      optional overlay (windows, fires, lava) whose opacity flickers in game;
                                          delete it (or set LOGIN_GLOW = false in login.lua) when title.png is replaced
ui  data/images/chaos/login/*.png         panel frame, rune medallions, buttons, fields, crest, "press any key"
                                          plate, ember sprite

Deterministic (fixed seeds), original art, no third-party assets.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.normpath(os.path.join(HERE, '..', 'overlay', 'data', 'images'))
UI_OUT = os.path.join(IMG, 'chaos', 'login')
W, H = 1920, 1080
S = 2                      # supersampling of the silhouette layers


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print('wrote', os.path.relpath(path, IMG), img.size)


# ------------------------------------------------------------------ helpers
def fbm(h, w, scale, octaves=5, seed=0, persistence=0.5, sx=1.0):
    """fractal value noise in [0,1] (h, w); scale = size of the biggest feature in px, sx stretches x"""
    rng = np.random.RandomState(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot, sc = 1.0, 0.0, float(scale)
    for _ in range(octaves):
        gh = max(2, int(h / sc) + 3)
        gw = max(2, int(w / (sc * sx)) + 3)
        g = Image.fromarray(rng.rand(gh, gw).astype(np.float32), 'F')
        g = g.resize((int(gw * sc * sx), int(gh * sc)), Image.BICUBIC)
        a = np.asarray(g)[:h, :w]
        if a.shape != (h, w):
            a = np.pad(a, ((0, h - a.shape[0]), (0, w - a.shape[1])), mode='edge')
        out += a * amp
        tot += amp
        amp *= persistence
        sc = max(1.0, sc / 2)
    out /= tot
    lo, hi = out.min(), out.max()
    return (out - lo) / (hi - lo + 1e-9)


def _box(a, r, axis):
    """box blur of radius r along axis (edge-replicated), via cumulative sums"""
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode='edge'), axis=axis, dtype=np.float64)
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a, r):
    """gaussian-like blur (three box passes per axis) of an (h,w) or (h,w,3) float array, sigma ~ r"""
    if r <= 0:
        return a
    k = max(1, int(round(r * 0.9)))
    out = a.astype(np.float32)
    for _ in range(3):
        out = _box(_box(out, k, 0), k, 1)
    return out


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


class Layer:
    """draw with PIL at S x supersampling, read back as a float mask at W x H"""

    def __init__(self):
        self.im = Image.new('L', (W * S, H * S), 0)
        self.d = ImageDraw.Draw(self.im)

    def poly(self, pts, v=255):
        self.d.polygon([(x * S, y * S) for x, y in pts], fill=v)

    def line(self, pts, width, v=255):
        self.d.line([(x * S, y * S) for x, y in pts], fill=v, width=max(1, int(width * S)))

    def circle(self, cx, cy, r, v=255):
        self.d.ellipse(((cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S), fill=v)

    def rect(self, x0, y0, x1, y1, v=255):
        self.d.rectangle((x0 * S, y0 * S, x1 * S - 1, y1 * S - 1), fill=v)

    def mask(self):
        return np.asarray(self.im.resize((W, H), Image.BOX), np.float32) / 255.0


# ------------------------------------------------------------------ gothic shapes
def arch_pts(cx, base_y, w, h):
    """lancet (pointed) arch: width w, total height h, bottom at base_y"""
    ys = base_y - (h - 0.866 * w)
    pts = [(cx - w / 2, base_y), (cx - w / 2, ys)]
    c1 = (cx + w / 2, ys)
    for i in range(1, 9):
        a = math.radians(180 - 60 * i / 8)
        pts.append((c1[0] + w * math.cos(a), c1[1] - w * math.sin(a)))
    c2 = (cx - w / 2, ys)
    for i in range(1, 9):
        a = math.radians(60 - 60 * i / 8)
        pts.append((c2[0] + w * math.cos(a), c2[1] - w * math.sin(a)))
    pts += [(cx + w / 2, ys), (cx + w / 2, base_y)]
    return pts


def spire(L, x, base_y, bw, h, rng, crockets=True, cross=True, lean=0.0):
    """tall gothic spire (concave sides) with crockets and a finial"""
    n = 14
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        half = bw / 2 * (1 - t) ** 1.45
        cx = x + lean * t * h
        y = base_y - h * t
        left.append((cx - half, y))
        right.append((cx + half, y))
    L.poly(left + right[::-1])
    if crockets:
        for i in range(2, n - 1):
            t = i / n
            half = bw / 2 * (1 - t) ** 1.45
            cx = x + lean * t * h
            y = base_y - h * t
            s = max(3.0, bw * 0.10 * (1 - t) + 2)
            for sgn in (-1, 1):
                px = cx + sgn * half
                L.poly([(px, y + s * 0.9), (px + sgn * s * 1.5, y - s * 0.2), (px, y - s * 0.7)])
    if cross:
        tx, ty = x + lean * h, base_y - h
        L.line([(tx, ty), (tx, ty - 24)], 2.4)
        L.line([(tx - 7, ty - 16), (tx + 7, ty - 16)], 2.4)
    return (x + lean * h, base_y - h)


def pinnacle(L, x, y, w, h):
    L.rect(x - w / 2, y - h, x + w / 2, y + 40)
    L.poly([(x - w / 2 - 2, y - h), (x, y - h - w * 1.8), (x + w / 2 + 2, y - h)])


def tower(L, x, base_y, w, top_y, spire_h, rng, lean=0.0):
    L.rect(x - w / 2, top_y, x + w / 2, base_y)
    # belfry slits and a stepped cornice
    L.rect(x - w / 2 - 5, top_y - 8, x + w / 2 + 5, top_y)
    for i in range(int(w // 14)):
        L.poly([(x - w / 2 - 5 + i * 14 + 2, top_y - 8), (x - w / 2 - 5 + i * 14 + 7, top_y - 20),
                (x - w / 2 - 5 + i * 14 + 12, top_y - 8)])
    return spire(L, x, top_y - 8, w * 0.95, spire_h, rng, lean=lean)


def vine(L, rng, x, y, ang, length, thick, depth=0, step=5.0, bend=0.16, thorn_p=0.20):
    """thorny vine: a wandering tapered stroke with hooked thorns and side branches"""
    pts = [(x, y)]
    n = int(length / step)
    a = ang
    for i in range(n):
        t = i / max(1, n)
        a += rng.randn() * bend + (0.05 * math.sin(i * 0.31 + x))
        x += math.cos(a) * step
        y += math.sin(a) * step
        pts.append((x, y))
        wdt = thick * (1 - 0.82 * t)
        L.line(pts[-2:], wdt)
        L.circle(x, y, wdt / 2)
        if rng.rand() < thorn_p and wdt > 1.2:
            side = rng.choice([-1, 1])
            ta = a + side * math.radians(rng.uniform(55, 105))
            tl = rng.uniform(8, 20) * (0.55 + 0.7 * wdt / max(thick, 1))
            hook = side * 0.5
            tip = (x + math.cos(ta) * tl, y + math.sin(ta) * tl)
            mid = (x + math.cos(ta - hook * 0.4) * tl * 0.5, y + math.sin(ta - hook * 0.4) * tl * 0.5)
            L.poly([(x - math.cos(a) * wdt * 0.5, y - math.sin(a) * wdt * 0.5), mid, tip,
                    (x + math.cos(a) * wdt * 0.9, y + math.sin(a) * wdt * 0.9)])
        if depth < 3 and rng.rand() < 0.05 and wdt > 2.0:
            side = rng.choice([-1, 1])
            vine(L, rng, x, y, a + side * math.radians(rng.uniform(30, 70)), length * rng.uniform(0.25, 0.5),
                 wdt * 0.8, depth + 1, step, bend * 1.3, thorn_p)


# ------------------------------------------------------------------ background
def make_sky(rng_seed=7):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ty = yy / H
    top = np.array([0.030, 0.026, 0.038], np.float32)
    mid = np.array([0.085, 0.040, 0.045], np.float32)
    hor = np.array([0.30, 0.075, 0.045], np.float32)
    sky = top + (mid - top) * smooth(0, 0.55, ty)[..., None]
    # horizon glow behind the cathedral (right of centre)
    g = np.exp(-(((xx - 1480) / 800) ** 2 + ((yy - 760) / 300) ** 2))
    sky += hor * g[..., None] * 0.8
    # cold moonlit patch of sky, upper right: bluish smoke between the spires
    cl = fbm(H, W, 220, 6, rng_seed, 0.55)
    cl2 = fbm(H, W, 90, 5, rng_seed + 1, 0.6)
    patch = np.exp(-(((xx - 1560) / 520) ** 2 + ((yy - 190) / 260) ** 2))
    cold = np.array([0.20, 0.27, 0.36], np.float32)
    sky += cold[None, None, :] * (patch * smooth(0.30, 0.78, cl * 0.7 + cl2 * 0.3))[..., None] * 0.95
    # smoke: darker towers of cloud all over, a warm underside near the horizon
    smoke = fbm(H, W, 260, 6, rng_seed + 2, 0.58, sx=1.6)
    sky *= (0.45 + 0.9 * smoke)[..., None]
    warm = smooth(0.4, 1.0, ty) * smooth(0.35, 0.75, fbm(H, W, 140, 5, rng_seed + 3, 0.6, sx=2.0))
    sky += np.array([0.10, 0.032, 0.014], np.float32) * warm[..., None]
    return np.clip(sky, 0, 1)


def comp(img, m, col):
    col = np.asarray(col, np.float32)
    if col.ndim == 1:
        col = col[None, None, :]
    return img * (1 - m[..., None]) + col * m[..., None]


def gradient_v(y0, y1, c0, c1):
    t = np.clip((np.arange(H, dtype=np.float32) - y0) / (y1 - y0), 0, 1)[:, None, None]
    return np.asarray(c0, np.float32) * (1 - t) + np.asarray(c1, np.float32) * t


def fog_band(img, cy, spread, color, strength, seed, scale=300):
    yy = np.arange(H, dtype=np.float32)[:, None]
    prof = np.exp(-((yy - cy) / spread) ** 2)
    n = fbm(H, W, scale, 5, seed, 0.55, sx=2.4)
    a = np.clip(prof * (0.25 + 1.1 * n) * strength, 0, 1)
    return img * (1 - a[..., None] * 0.55) + np.asarray(color, np.float32) * a[..., None] * 0.55 + \
        np.asarray(color, np.float32) * a[..., None] * 0.0


def far_layer(rng):
    """distant ruined skyline: pale, low contrast shapes dissolving in fog"""
    L = Layer()
    for x, bw, h, by in [(120, 56, 300, 700), (330, 44, 220, 700), (560, 40, 160, 690), (800, 46, 190, 700),
                         (1080, 40, 150, 700), (1130, 60, 260, 710)]:
        tower(L, x, by + 60, bw, by - h * 0.45, h * 0.6, rng)
    # broken wall runs
    for x0, x1, y in [(40, 440, 690), (640, 1000, 700)]:
        pts = [(x0, 760)]
        x = x0
        while x < x1:
            pts.append((x, y - rng.randint(0, 38)))
            x += rng.randint(14, 36)
            pts.append((x, pts[-1][1]))
        pts.append((x1, 760))
        L.poly(pts)
    return L.mask()


def cathedral(rng):
    """returns (silhouette mask, window glow mask (0..1 float), brightness) for the main cathedral"""
    L = Layer()
    gy = 880
    # nave body + roof ridge
    L.poly([(1190, gy), (1190, 640), (1250, 600), (1300, 560), (1420, 530), (1520, 470), (1660, 470), (1760, 530),
            (1860, 560), (1920, 600), (1920, gy)])
    # transept ruin (left), broken gable
    L.poly([(1090, gy), (1090, 700), (1120, 690), (1135, 650), (1170, 668), (1190, 640), (1190, gy)])
    # central tower + spire
    top = tower(L, 1590, 560, 150, 360, 330, rng)
    # flanking towers
    tower(L, 1380, 600, 84, 470, 250, rng, lean=-0.02)
    tower(L, 1790, 560, 92, 400, 300, rng, lean=0.01)
    tower(L, 1240, 640, 70, 520, 330, rng, lean=-0.03)
    # far right tall spire, almost out of frame
    spire(L, 1894, 700, 70, 600, rng)
    # gable of the facade
    L.poly([(1475, 560), (1590, 430), (1705, 560)])
    # pinnacles on the buttresses
    for x in (1330, 1440, 1740, 1850):
        pinnacle(L, x, 590, 16, 36)
    # flying buttresses: arcs from pinnacles down to the ground
    for x0, x1 in [(1330, 1250), (1440, 1480), (1740, 1700), (1850, 1890)]:
        for i in range(24):
            t = i / 23
            px = x0 + (x1 - x0) * t
            py = 600 + (gy - 600) * (t ** 1.7)
            L.circle(px, py, 7 - 3 * t)
        L.rect(min(x0, x1) - 6, 700, min(x0, x1) + 6, gy)
    # a second, lower row of buttresses behind the first and pinnacle clusters along the whole roofline
    for x0, x1 in [(1300, 1330), (1500, 1470), (1690, 1720), (1810, 1830)]:
        for i in range(18):
            t = i / 17
            L.circle(x0 + (x1 - x0) * t, 640 + (gy - 640) * (t ** 1.5), 5 - 2 * t)
    for x in range(1215, 1910, 46):
        ry = 600 - max(0, 130 - abs(x - 1590) * 0.35) if 1300 < x < 1880 else 612
        pinnacle(L, x + rng.randint(-6, 6), ry + 6, 9, 22 + rng.randint(0, 14))
    # roof crenellations / broken gable teeth
    for x in range(1210, 1900, 26):
        if rng.rand() < 0.8:
            y = 560 - (abs(x - 1560) / 700.0) * -40
            L.poly([(x, 595 - rng.randint(0, 30)), (x + 8, 565 - rng.randint(0, 30)), (x + 16, 595)])
    sil = L.mask()

    # lit windows (red) and the glow they cast
    Wl = Layer()      # window light (mask)
    Wd = Layer()      # tracery drawn over the light (dark)
    win = []
    for x in range(1275, 1890, 58):
        if abs(x - 1590) < 60:
            continue
        win.append((x, 770, 24, 112, 1.0 if rng.rand() < 0.8 else 0.0))
        win.append((x, 640, 20, 78, 0.85 if rng.rand() < 0.7 else 0.0))
    win += [(1380, 560, 28, 110, 1.0), (1790, 520, 30, 120, 0.9), (1240, 590, 24, 90, 0.7),
            (1590, 640, 60, 190, 1.0), (1530, 790, 26, 130, 0.9), (1650, 790, 26, 130, 0.9)]
    for x, by, w, h, on in win:
        if on <= 0:
            continue
        Wl.poly(arch_pts(x, by, w, h), int(255 * on))
        Wd.line([(x, by - h + w * 0.7), (x, by)], 2.2)
        Wd.line([(x - w / 2, by - h * 0.45), (x + w / 2, by - h * 0.45)], 2.0)
    # tower slits and the tracery of the great window (mullions, a fan of arcs)
    for x, by in [(1380, 520), (1790, 470), (1240, 560)]:
        for k in range(3):
            Wl.poly(arch_pts(x, by - 58 - k * 0, 9, 38), 255 if rng.rand() < 0.75 else 0)
            break
    for dx in (-18, 18):
        Wd.line([(1590 + dx, 482), (1590 + dx, 640)], 2.0)
    for r_, yy_ in [(30, 478), (30, 548)]:
        Wd.d.arc(((1590 - r_) * S, (yy_ - r_) * S, (1590 + r_) * S, (yy_ + r_) * S), 200, 340, fill=255, width=2 * S)
    # rose window and the door
    Wl.circle(1590, 405, 38)
    Wd.d.ellipse(((1590 - 38) * S, (405 - 38) * S, (1590 + 38) * S, (405 + 38) * S), outline=255, width=3 * S)
    Wd.d.ellipse(((1590 - 22) * S, (405 - 22) * S, (1590 + 22) * S, (405 + 22) * S), outline=255, width=2 * S)
    for a in range(0, 360, 22):
        Wd.line([(1590, 405), (1590 + 38 * math.cos(math.radians(a)), 405 + 38 * math.sin(math.radians(a)))], 2)
    Wd.circle(1590, 405, 8)
    Wl.poly(arch_pts(1590, gy, 96, 170), 190)
    Wd.line([(1590, gy - 170 + 80), (1590, gy)], 3)
    return sil, Wl.mask(), Wd.mask()


def gate_and_fence(rng):
    """left side: wrought iron fence and gate between stone pillars, leaning gravestones"""
    L = Layer()
    gy = 880

    def pillar(x, h, w=50):
        L.rect(x - w / 2, gy - h, x + w / 2, gy + 30)
        L.rect(x - w / 2 - 6, gy - h - 8, x + w / 2 + 6, gy - h)
        L.poly([(x - w / 2 - 2, gy - h - 8), (x, gy - h - 62), (x + w / 2 + 2, gy - h - 8)])
        L.circle(x, gy - h - 66, 5)

    pillar(430, 215)
    pillar(760, 200)
    # fence left of the gate (rods with spear tips, rails)
    def rods(x0, x1, ytop, ybot, gap=15, broken=0.1):
        for x in np.arange(x0, x1, gap):
            if rng.rand() < broken:
                continue
            top = ytop + rng.randint(-4, 5) + (0 if rng.rand() > 0.12 else rng.randint(20, 60))
            L.line([(x, top), (x, ybot)], 2.6)
            L.poly([(x - 4, top + 2), (x, top - 14), (x + 4, top + 2)])
            L.circle(x, top + 12, 3)
        L.line([(x0, ytop + 28), (x1, ytop + 28)], 3.2)
        L.line([(x0, ytop + 82), (x1, ytop + 82)], 3.2)
    rods(40, 405, 745, gy + 10)
    # gate: two leaves with an arched top and scrolls
    rods(458, 735, 735, gy + 10, gap=14, broken=0.04)
    pts = []
    for i in range(41):
        t = i / 40
        pts.append((458 + (735 - 458) * t, 735 - 70 * math.sin(math.pi * t) ** 0.8))
    L.line(pts, 4)
    for cx in (560, 636):
        for r in (26, 17):
            L.d.ellipse(((cx - r) * S, (810 - r) * S, (cx + r) * S, (810 + r) * S), outline=255, width=3 * S)
    L.line([(597, 735), (597, gy)], 4)
    # broken fence, further right
    rods(790, 990, 790, gy + 10, gap=16, broken=0.28)
    # gravestones and a fallen cross
    for x, y, w, h, tilt in [(250, 905, 40, 58, -0.10), (330, 930, 34, 46, 0.12), (520, 940, 44, 60, 0.05),
                             (680, 925, 36, 52, -0.15), (880, 935, 40, 54, 0.1), (140, 940, 46, 64, 0.08)]:
        pts = [(x - w / 2, y), (x - w / 2, y - h + 14), (x, y - h), (x + w / 2, y - h + 14), (x + w / 2, y)]
        pts = [(px + (y - py) * tilt * -1, py) for px, py in pts]
        L.poly(pts)
    return L.mask()


def ground(rng):
    """cracked ground: returns (rgb albedo-lit image layer, ground mask, emission rgb)"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    top = 850 + 34 * fbm(16, W, 150, 3, 31)[0] + 34 * fbm(16, W, 24, 4, 32, 0.6)[0] + 22 * np.sin(xx[0] / 210.0)
    gm = (yy > top[None, :]).astype(np.float32)
    gm = blur(gm, 1.2)

    # perspective voronoi cracks
    hy = 760.0
    dy = np.maximum(yy - hy, 28.0)
    wx = (xx - 960.0) / dy * 3.0
    wz = 380.0 / dy * 1.0
    f1 = np.full((H, W), 9.0, np.float32)
    f2 = np.full((H, W), 9.0, np.float32)
    cx0, cz0 = np.floor(wx), np.floor(wz)
    seedmap = np.random.RandomState(5)
    tab = seedmap.rand(512, 512, 2).astype(np.float32)
    cell = np.zeros((H, W), np.float32)
    for ox in (-1, 0, 1):
        for oz in (-1, 0, 1):
            ix = (cx0 + ox).astype(np.int64)
            iz = (cz0 + oz).astype(np.int64)
            px = ix + tab[iz % 512, ix % 512, 0]
            pz = iz + tab[iz % 512, ix % 512, 1]
            d = np.sqrt((wx - px) ** 2 + ((wz - pz) * 0.9) ** 2)
            nf1 = np.minimum(f1, d)
            nf2 = np.where(d < f1, f1, np.minimum(f2, d))
            cell = np.where(d < f1, ((ix * 7 + iz * 13) % 17) / 17.0, cell)
            f1, f2 = nf1, nf2
    edge = f2 - f1
    crack_w = 0.035 + 0.02 * np.clip((yy - hy) / 320.0, 0, 1)
    crack = 1 - smooth(0.0, 1.0, edge / crack_w)
    crack = crack * smooth(850, 930, yy)
    # lava is patchy: wide slow noise decides where cracks glow
    patch = smooth(0.40, 0.72, fbm(H, W, 260, 4, 41, 0.6))
    lava = crack * (0.15 + 0.85 * patch)

    # big fissures: bright jagged wounds that run toward the viewer
    Fm = Layer()
    for sx_, sy_, ang, ln, th in [(980, 905, 90, 190, 11), (1180, 930, 82, 160, 9), (760, 940, 100, 140, 8),
                                  (1420, 960, 96, 120, 8), (500, 975, 88, 100, 7)]:
        x, y, a = sx_, sy_, math.radians(ang)
        for i in range(int(ln / 6)):
            t = i / (ln / 6)
            a += rng.randn() * 0.28
            nx, ny = x + math.cos(a) * 6 * (1 + t * 0.6), y + abs(math.sin(a)) * 7 * (1 + t * 0.6)
            Fm.line([(x, y), (nx, ny)], th * (0.4 + t * 0.9))
            if rng.rand() < 0.09:
                bx, by, ba = nx, ny, a + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0)
                for j in range(int(rng.randint(5, 12))):
                    ba += rng.randn() * 0.3
                    ex, ey = bx + math.cos(ba) * 6, by + abs(math.sin(ba)) * 6
                    Fm.line([(bx, by), (ex, ey)], th * 0.3)
                    bx, by = ex, ey
            x, y = nx, ny
    fis = Fm.mask()
    lava = np.maximum(lava, fis * (0.55 + 0.45 * fbm(H, W, 40, 3, 43)))
    heat = blur(lava, 1.0)

    # plate albedo: dark basalt with rough per-plate brightness and fine grain
    grain = fbm(H, W, 30, 5, 47, 0.6)
    plate = 0.55 + 0.9 * cell
    alb = (0.035 + 0.05 * grain) * (0.6 + 0.6 * plate)
    base = np.stack([alb * 1.15, alb * 0.95, alb * 0.95], -1)
    # edges of plates catch the lava light
    lit = blur(lava, 14)
    base += np.stack([lit * 0.55, lit * 0.16, lit * 0.03], -1) * (0.4 + grain[..., None] * 0.9)
    # far ground fades into fog (distance)
    base *= (0.55 + 0.45 * smooth(840, 1040, yy))[..., None]

    ramp_hot = np.stack([heat * 1.25, (heat ** 1.8) * 0.78, (heat ** 3.2) * 0.30], -1)
    emis = ramp_hot * 1.1
    return base, gm, emis, lava


def fires(rng):
    """small ground fires: emission only (blurred later) + hot flame shapes"""
    E = np.zeros((H, W, 3), np.float32)
    L = Layer()
    for x, y, s in [(215, 905, 0.9), (610, 925, 0.55), (1788, 905, 0.7), (1010, 918, 0.4)]:
        for k in range(7):
            ox = rng.uniform(-14, 14) * s
            hgt = rng.uniform(20, 48) * s
            L.poly([(x + ox - 8 * s, y), (x + ox - 2 * s, y - hgt * 0.6), (x + ox + rng.uniform(-6, 6) * s, y - hgt),
                    (x + ox + 3 * s, y - hgt * 0.55), (x + ox + 9 * s, y)], 255)
    m = L.mask()
    return m


def embers_static(rng, n=620):
    L = Layer()
    for _ in range(n):
        x = rng.uniform(0, W)
        y = H * (1 - rng.rand() ** 1.6) * 0.98
        r = rng.choice([0.8, 1.0, 1.3, 1.8, 2.4], p=[0.35, 0.3, 0.2, 0.1, 0.05])
        v = int(255 * rng.uniform(0.35, 1.0))
        L.circle(x, y, r, v)
        if rng.rand() < 0.10:     # streak: the ember is moving
            L.line([(x, y), (x + rng.uniform(2, 8), y - rng.uniform(4, 12))], r * 0.8, v // 2)
    return L.mask()


def make_background():
    rng = np.random.RandomState(1337)
    img = make_sky()
    yy = np.arange(H, dtype=np.float32)[:, None, None]

    # --- distant skyline, then fog
    far = far_layer(np.random.RandomState(2))
    img = comp(img, blur(far, 0.8), (0.085, 0.045, 0.055))
    img = fog_band(img, 700, 90, (0.34, 0.12, 0.10), 1.0, 71, 360)

    # --- cathedral
    sil, win_m, tracery = cathedral(np.random.RandomState(3))
    cath_col = gradient_v(60, 900, (0.040, 0.030, 0.040), (0.022, 0.015, 0.019))
    img = comp(img, blur(sil, 0.6), cath_col)
    # stone texture: faint vertical streaks and block noise
    tex = fbm(H, W, 12, 4, 91, 0.6) * 0.5 + fbm(H, W, 40, 3, 92) * 0.5
    img += (sil * (tex - 0.5) * 0.05)[..., None] * np.array([1, 0.8, 0.8], np.float32)
    course = (0.5 + 0.5 * np.sin(np.arange(H, dtype=np.float32) * 0.7))[:, None] ** 6
    img += (sil * course)[..., None] * np.array([0.005, 0.003, 0.004], np.float32)
    # rim light on the silhouette (cold moon from above-left, warm window light from the inside edges)
    top_rim = np.clip(sil - np.roll(sil, 3, 0), 0, 1)
    left_rim = np.clip(sil - np.roll(sil, 3, 1), 0, 1)
    img += blur(top_rim, 0.8)[..., None] * np.array([0.12, 0.17, 0.24], np.float32) * 0.9
    img += blur(left_rim, 0.8)[..., None] * np.array([0.30, 0.09, 0.05], np.float32) * 0.5

    # window light: gradient from a hot core to deep red, tracery over it
    wl = np.clip(win_m - tracery * 0.9, 0, 1)
    wl = wl * (0.45 + 0.75 * np.clip(blur(win_m, 7) * 1.6, 0, 1))
    wy = np.clip((np.arange(H, dtype=np.float32) - 380) / 520.0, 0, 1)[:, None]
    flick = 0.8 + 0.4 * fbm(H, W, 30, 3, 93)
    win_rgb = np.stack([np.broadcast_to(0.80 + 0.2 * wy, (H, W)), (0.045 + 0.20 * wy ** 1.5) * flick,
                        np.broadcast_to(0.015 + 0.03 * wy, (H, W))], -1)
    win_rgb = np.clip(win_rgb, 0, 1.3)
    img = comp(img, wl, np.zeros(3)) * 1.0
    img = img + wl[..., None] * win_rgb * 0.78
    E = np.zeros((H, W, 3), np.float32)
    E += wl[..., None] * win_rgb * 1.0
    # light spilling out of the door onto the ground is added with the ground (emission)

    # --- fog between cathedral and foreground
    img = fog_band(img, 800, 80, (0.30, 0.11, 0.09), 1.1, 72, 320)

    # --- left: tall dead towers (nearer than the far skyline, behind the gate)
    TL = Layer()
    trng = np.random.RandomState(12)
    tower(TL, 215, 900, 92, 420, 470, trng, lean=0.02)
    tower(TL, 520, 900, 56, 640, 220, trng, lean=-0.02)
    tl = TL.mask()
    img = comp(img, blur(tl, 0.6), gradient_v(60, 900, (0.030, 0.022, 0.030), (0.020, 0.013, 0.017)))
    img += blur(np.clip(tl - np.roll(tl, 3, 0), 0, 1), 0.8)[..., None] * np.array([0.11, 0.15, 0.21], np.float32)
    img += blur(np.clip(tl - np.roll(tl, -3, 1), 0, 1), 0.8)[..., None] * np.array([0.26, 0.07, 0.04], np.float32) * 0.6
    # --- left: gate, fence, gravestones (nearer than the cathedral)
    gate = gate_and_fence(np.random.RandomState(4))
    gate_col = gradient_v(600, 950, (0.050, 0.035, 0.042), (0.015, 0.010, 0.012))
    img = comp(img, blur(gate, 0.5), gate_col)
    img += blur(np.clip(gate - np.roll(gate, 2, 1), 0, 1), 0.7)[..., None] * np.array([0.22, 0.07, 0.04], np.float32)
    img += blur(np.clip(gate - np.roll(gate, 2, 0), 0, 1), 0.7)[..., None] * np.array([0.10, 0.12, 0.16], np.float32) * 0.8

    # --- ground
    gbase, gm, gem, lava = ground(np.random.RandomState(6))
    img = comp(img, gm, gbase)
    E += gem * gm[..., None]
    # the door of the cathedral lights the ground in front of it
    yy2, xx2 = np.mgrid[0:H, 0:W].astype(np.float32)
    spill = np.exp(-(((xx2 - 1590) / 170) ** 2 + ((yy2 - 905) / 40) ** 2)) * gm
    E += spill[..., None] * np.array([0.55, 0.12, 0.03], np.float32)

    # --- fires
    fm = fires(np.random.RandomState(8))
    fmb = blur(fm, 1.6)
    core = blur(fm, 5.0)
    fcol = np.stack([fmb * 1.0, fmb * (0.18 + 0.3 * core), fmb * 0.03], -1)
    img = comp(img, fmb * 0.8, np.array([0.55, 0.12, 0.03], np.float32))
    img += fcol * 0.9
    E += fcol * 1.0 + np.stack([core, core * 0.3, core * 0.05], -1) * 0.8

    # --- foreground silhouettes: vines at both edges, broken spikes, boulders
    rngv = np.random.RandomState(11)
    V = Layer()
    # left edge: thorn trunks climbing the border and reaching into the scene
    for x0, y0, ang, ln, th in [(-10, 1100, -83, 1100, 34), (70, 1100, -90, 760, 24), (-30, 800, -25, 520, 20),
                                (30, 360, 25, 420, 16), (-20, 60, 40, 520, 22), (120, 560, 0, 330, 12),
                                (160, 1100, -80, 420, 14), (10, 540, 10, 260, 12)]:
        vine(V, rngv, x0, y0, math.radians(ang), ln, th * 1.35, thorn_p=0.34, bend=0.13)
    # right edge
    for x0, y0, ang, ln, th in [(1930, 1100, -95, 1100, 36), (1850, 1100, -92, 780, 26), (1945, 540, 200, 560, 20),
                                (1950, 130, 150, 520, 22), (1890, 820, 215, 380, 14), (1780, 250, 120, 230, 9),
                                (1740, 1100, -100, 380, 14), (1930, 700, 190, 360, 14)]:
        vine(V, rngv, x0, y0, math.radians(ang), ln, th * 1.35, thorn_p=0.34, bend=0.13)
    # a thorn arch hanging over the top corners
    vine(V, rngv, 40, -10, math.radians(15), 520, 18, thorn_p=0.3)
    vine(V, rngv, 1900, -10, math.radians(160), 520, 18, thorn_p=0.3)
    # bottom: spikes and broken stakes
    for x, h, lean in [(70, 250, 0.35), (160, 170, -0.15), (260, 120, 0.2), (1730, 210, -0.3), (1830, 270, -0.12),
                       (1630, 130, 0.15), (1880, 160, 0.3)]:
        V.poly([(x - 14, H + 10), (x + lean * h, H - h), (x + 14, H + 10)])
    # boulders in the corners
    def rock(cx, cy, r):
        pts = []
        for i in range(14):
            a = 2 * math.pi * i / 14
            rr = r * (0.75 + 0.35 * rngv.rand())
            pts.append((cx + math.cos(a) * rr * 1.25, cy + math.sin(a) * rr * 0.8))
        V.poly(pts)
    for cx, cy, r in [(60, 1050, 120), (210, 1085, 90), (1850, 1040, 130), (1690, 1090, 90), (1560, 1100, 60)]:
        rock(cx, cy, r)
    vm = V.mask()
    img = comp(img, blur(vm, 0.5), (0.010, 0.007, 0.009))
    # lava light from below and a cold top rim
    low = smooth(700, 1080, yy2)
    img += blur(np.clip(vm - np.roll(vm, -3, 0), 0, 1), 1.0)[..., None] * np.array([0.38, 0.11, 0.04], np.float32) * low[..., None]
    img += blur(np.clip(vm - np.roll(vm, 3, 0), 0, 1), 1.0)[..., None] * np.array([0.10, 0.13, 0.19], np.float32) * (1 - low[..., None] * 0.6)
    img += blur(np.clip(vm - np.roll(vm, 3, 1), 0, 1), 1.0)[..., None] * np.array([0.30, 0.09, 0.04], np.float32) * 0.5

    # --- bloom of everything emissive
    img += blur(E, 3) * 0.55 + blur(E, 14) * 0.65 + blur(E, 48) * 0.85
    # foreground vines occlude the glow again
    img = comp(img, np.clip(vm * 0.82, 0, 1), img * 0.15)

    # --- ground fog in front, low smoke
    img = fog_band(img, 930, 120, (0.28, 0.10, 0.08), 0.8, 73, 280)
    img = fog_band(img, 520, 220, (0.22, 0.10, 0.10), 0.35, 74, 420)

    # --- embers baked into the picture
    em = embers_static(np.random.RandomState(9))
    ec = np.stack([em * 1.0, em * 0.55, em * 0.14], -1)
    img += blur(ec, 0.9) * 1.1 + blur(ec, 4) * 0.55

    # --- darker centre for logo and panel (kept subtle), vignette, grade, grain
    cxn = ((xx2 - 960) / 620) ** 2 + ((yy2 - 600) / 330) ** 2
    img *= (1 - 0.30 * np.exp(-cxn))[..., None]
    vig = 1 - 0.68 * smooth(0.45, 1.25, np.sqrt(((xx2 - 960) / 960) ** 2 + ((yy2 - 540) / 540) ** 2))
    img *= vig[..., None]
    img = np.clip(img, 0, 1.6)
    img = 1 - np.exp(-img * 1.5)              # filmic shoulder
    img = img ** 0.97
    rg = np.random.RandomState(99)
    img += rg.randn(H, W, 1).astype(np.float32) * 0.010
    img += rg.rand(H, W, 3).astype(np.float32) * (1 / 255.0)
    out = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')

    # --- overlay for flicker: windows, fires and lava, additive in spirit, drawn as warm alpha
    glow_src = np.clip(blur(E[..., 0], 6) * 0.9, 0, 1) * vig
    gl = np.zeros((H, W, 4), np.uint8)
    gl[..., 0] = 255
    gl[..., 1] = (np.clip(blur(E[..., 1], 6) / np.maximum(blur(E[..., 0], 6), 1e-3), 0.2, 0.7) * 255 * 0.95).astype(np.uint8)
    gl[..., 2] = 60
    gl[..., 3] = (np.clip(glow_src * 0.55, 0, 1) * 255).astype(np.uint8)
    glow = Image.fromarray(gl, 'RGBA')
    return out, glow


# ------------------------------------------------------------------ UI art
IRON0, IRON1, IRON2, IRON3, IRON4, IRON5 = (10, 8, 11), (22, 18, 21), (38, 31, 35), (62, 54, 58), (96, 86, 90), (140, 128, 130)
BLOOD, BLOOD_HI, BLOOD_LO = (158, 24, 18), (232, 70, 40), (74, 10, 10)


def px_image(w, h):
    return Image.new('RGBA', (w, h), (0, 0, 0, 0))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def chamfer_poly(w, h, c):
    return [(c, 0), (w - 1 - c, 0), (w - 1, c), (w - 1, h - 1 - c), (w - 1 - c, h - 1), (c, h - 1), (0, h - 1 - c), (0, c)]


def metal_plate(w, h, c, rim, hi, top, bottom, grain=0.04, seed=0, inner=None, inner_w=1, rim2=None):
    """chamfered dark-metal plate: gradient fill, 1 px rim with a top highlight, optional inner line"""
    s = 4
    big = Image.new('RGBA', (w * s, h * s), (0, 0, 0, 0))
    md = ImageDraw.Draw(big)
    poly = [(x * s, y * s) for x, y in chamfer_poly(w, h, c)]
    md.polygon(poly, fill=(255, 255, 255, 255))
    mask = np.asarray(big.getchannel('A').resize((w, h), Image.LANCZOS), np.float32) / 255.0
    yy = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    fill = np.asarray(top, np.float32) * (1 - yy) + np.asarray(bottom, np.float32) * yy
    fill = np.broadcast_to(fill, (h, w, 3)).copy()
    rg = np.random.RandomState(seed)
    fill += (rg.randn(h, w, 1) * grain * 255).astype(np.float32)
    # rim: distance to the edge via erosion of the mask
    rimmask = Image.new('L', (w * s, h * s), 0)
    rd = ImageDraw.Draw(rimmask)
    rd.polygon(poly, outline=255, width=s)
    rm = np.asarray(rimmask.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    hi_amt = np.linspace(1, 0.15, h, dtype=np.float32)[:, None, None]
    rimcol = np.asarray(rim, np.float32) * (1 - hi_amt) + np.asarray(hi, np.float32) * hi_amt
    out = fill * (1 - rm[..., None]) + rimcol * rm[..., None]
    if inner is not None:
        im2 = Image.new('L', (w * s, h * s), 0)
        d2 = ImageDraw.Draw(im2)
        k = 2 + inner_w
        ins = chamfer_poly(w - 2 * k, h - 2 * k, max(1, c - k + 1))
        d2.polygon([((x + k) * s, (y + k) * s) for x, y in ins], outline=255, width=max(1, inner_w * s))
        a = np.asarray(im2.resize((w, h), Image.LANCZOS), np.float32) / 255.0
        out = out * (1 - a[..., None] * 0.9) + np.asarray(inner, np.float32) * a[..., None] * 0.9
    arr = np.dstack([np.clip(out, 0, 255), mask * 255]).astype(np.uint8)
    return Image.fromarray(arr, 'RGBA')


def gen_panel():
    # 9-slice (border 26): dark framed plate with an inner red line and corner studs
    w, h, c = 180, 120, 14
    im = metal_plate(w, h, c, IRON3, IRON5, (30, 24, 27), (14, 11, 13), 0.035, 1, inner=BLOOD_LO, inner_w=1)
    d = ImageDraw.Draw(im)
    # inner shadow line and corner studs
    for x, y in [(c + 2, 4), (w - c - 3, 4), (c + 2, h - 5), (w - c - 3, h - 5)]:
        d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=BLOOD)
    # second, darker inner border for the recessed look
    save(im, os.path.join(UI_OUT, 'panel.png'))


def gen_crest():
    """pointed notch at the middle of the top and bottom edge of the panel"""
    w, h = 96, 22
    im = px_image(w * 4, h * 4)
    d = ImageDraw.Draw(im)
    s = 4
    pts = [(0, 0), (w * 0.28, 0), (w * 0.5, h * 0.95), (w * 0.72, 0), (w, 0)]
    d.polygon([(x * s, y * s) for x, y in pts], fill=IRON1 + (255,))
    d.line([(x * s, y * s) for x, y in pts[1:4]], fill=IRON4 + (255,), width=2 * s)
    d.line([(w * 0.5 * s, 2 * s), (w * 0.5 * s, (h * 0.7) * s)], fill=BLOOD + (255,), width=s)
    d.ellipse(((w * 0.5 - 3) * s, (h * 0.55 - 3) * s, (w * 0.5 + 3) * s, (h * 0.55 + 3) * s), fill=BLOOD_HI + (255,))
    im = im.resize((w, h), Image.LANCZOS)
    save(im, os.path.join(UI_OUT, 'crest.png'))
    save(im.transpose(Image.FLIP_TOP_BOTTOM), os.path.join(UI_OUT, 'crest_bottom.png'))


def rune_path(kind, cx, cy, r):
    """strokes of two original angular runes (lists of polylines)"""
    k = r * 0.5
    if kind == 0:     # forked stave with an angled arm
        return [[(cx - k * 0.1, cy - k * 1.2), (cx - k * 0.1, cy + k * 1.2)],
                [(cx - k * 0.1, cy - k * 0.4), (cx + k * 0.9, cy - k * 1.1)],
                [(cx - k * 0.1, cy + 0.1 * k), (cx + k * 0.9, cy - k * 0.55)]]
    return [[(cx - k * 0.7, cy - k * 1.2), (cx - k * 0.7, cy + k * 1.2)],
            [(cx - k * 0.7, cy - k * 1.2), (cx + k * 0.8, cy - k * 0.3), (cx - k * 0.7, cy + k * 0.4)],
            [(cx - k * 0.1, cy + k * 0.2), (cx + k * 0.9, cy + k * 1.2)]]


def gen_medallion(kind, name):
    w = h = 64
    s = 4
    big = Image.new('RGBA', (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    cx, cy = w / 2, h / 2
    # pointed hexagonal body (spikes up and down)
    body = [(cx, 1), (w - 8, 14), (w - 3, cy), (w - 8, h - 14), (cx, h - 1), (8, h - 14), (3, cy), (8, 14)]
    d.polygon([(x * s, y * s) for x, y in body], fill=IRON1 + (255,))
    d.line([(x * s, y * s) for x, y in body + [body[0]]], fill=IRON4 + (255,), width=3 * s)
    inner = [(cx, 6), (w - 12, 17), (w - 8, cy), (w - 12, h - 17), (cx, h - 6), (12, h - 17), (8, cy), (12, 17)]
    d.polygon([(x * s, y * s) for x, y in inner], fill=(46, 6, 7, 255))
    d.line([(x * s, y * s) for x, y in inner + [inner[0]]], fill=BLOOD_LO + (255,), width=2 * s)
    # glow of the rune
    glow = Image.new('RGBA', big.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    strokes = rune_path(kind, cx, cy, 24)
    for st in strokes:
        gd.line([(x * s, y * s) for x, y in st], fill=(255, 60, 30, 255), width=7 * s)
    glow = glow.filter(ImageFilter.GaussianBlur(5 * s))
    big = Image.alpha_composite(big, glow)
    d = ImageDraw.Draw(big)
    for st in strokes:
        d.line([(x * s, y * s) for x, y in st], fill=(255, 92, 54, 255), width=3 * s)
        d.line([(x * s, y * s) for x, y in st], fill=(255, 190, 140, 255), width=1 * s)
    # spike highlights
    d.line([(cx * s, 1 * s), ((w - 8) * s, 14 * s)], fill=IRON5 + (255,), width=s)
    save(big.resize((w, h), Image.LANCZOS), os.path.join(UI_OUT, name))


def gen_buttons():
    # 9-slice, border 9, 54x30
    w, h, c = 54, 30, 6
    sets = {
        'normal': ((98, 88, 92), (150, 138, 140), (46, 38, 42), (22, 18, 20), None),
        'hover': ((150, 118, 100), (230, 190, 150), (66, 40, 38), (30, 18, 18), (120, 20, 14)),
        'pressed': ((60, 52, 56), (80, 70, 74), (16, 13, 15), (30, 24, 27), None),
        'disabled': ((52, 46, 48), (70, 62, 64), (24, 20, 22), (16, 13, 15), None),
    }
    for kind, (rim, hi, top, bot, inner) in sets.items():
        save(metal_plate(w, h, c, rim, hi, top, bot, 0.03, 2, inner=inner), os.path.join(UI_OUT, f'btn_{kind}.png'))
    red = {
        'normal': ((150, 40, 30), (236, 100, 70), (58, 18, 18), (26, 9, 10), (90, 14, 12)),
        'hover': ((220, 70, 44), (255, 170, 120), (92, 24, 20), (40, 12, 12), (170, 30, 20)),
        'pressed': ((110, 28, 22), (150, 50, 40), (26, 8, 8), (44, 14, 14), None),
    }
    for kind, (rim, hi, top, bot, inner) in red.items():
        save(metal_plate(w, h, c, rim, hi, top, bot, 0.03, 3, inner=inner), os.path.join(UI_OUT, f'btn_red_{kind}.png'))


def gen_fields():
    # 9-slice, border 6, 40x24: recessed dark field
    w, h, c = 40, 24, 3
    for kind, rim, hi, top, bot, inner in [
        ('', (88, 78, 82), (120, 108, 110), (6, 5, 7), (14, 11, 13), None),
        ('_focus', (190, 70, 46), (250, 130, 90), (10, 5, 6), (24, 8, 9), (90, 14, 12)),
        ('_pass', (120, 40, 34), (170, 60, 48), (24, 6, 8), (36, 9, 11), None),
        ('_pass_focus', (210, 80, 52), (255, 150, 100), (30, 7, 9), (44, 10, 12), (110, 18, 14)),
    ]:
        save(metal_plate(w, h, c, rim, hi, top, bot, 0.02, 4, inner=inner), os.path.join(UI_OUT, f'field{kind}.png'))


def gen_pressplate():
    w, h = 460, 54
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = np.exp(-(((xx - w / 2) / (w * 0.36)) ** 4)) * np.exp(-(((yy - h / 2) / (h * 0.42)) ** 2))
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = 8, 5, 7
    arr[..., 3] = (a * 190).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'presskey.png'))


def gen_ember():
    n = 16
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    r = np.sqrt((xx - 7.5) ** 2 + (yy - 7.5) ** 2)
    a = np.clip(1 - r / 7.5, 0, 1) ** 2.2
    arr = np.zeros((n, n, 4), np.uint8)
    arr[..., 0] = 255
    arr[..., 1] = (140 + 100 * a).astype(np.uint8)
    arr[..., 2] = (30 + 90 * a ** 2).astype(np.uint8)
    arr[..., 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'ember.png'))


def gen_logo_glow():
    """ember-red halo drawn behind the logo (the logo image itself is chaos/logo.png)"""
    w, h = 900, 380
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r2 = ((xx - w / 2) / (w * 0.5)) ** 2 + ((yy - h * 0.46) / (h * 0.5)) ** 2
    a = np.clip(1 - r2, 0, 1) ** 2.2      # reaches 0 at the border: no visible edge of the image
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = 200, 40, 20
    arr[..., 3] = (a * 120).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'logo_halo.png'))


def gen_ui():
    gen_panel()
    gen_crest()
    gen_medallion(0, 'medallion_left.png')
    gen_medallion(1, 'medallion_right.png')
    gen_buttons()
    gen_fields()
    gen_pressplate()
    gen_ember()
    gen_logo_glow()


def gen_bg():
    bg, glow = make_background()
    save(bg, os.path.join(IMG, 'title.png'))
    save(glow, os.path.join(UI_OUT, 'glow.png'))


if __name__ == '__main__':
    tasks = sys.argv[1:] or ['bg', 'ui']
    for t in tasks:
        {'bg': gen_bg, 'ui': gen_ui}[t]()
