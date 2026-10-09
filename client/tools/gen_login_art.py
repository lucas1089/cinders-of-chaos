#!/usr/bin/env python3
"""Procedural art of the login screen (module client_chaos_login).

  python3 -I client/tools/gen_login_art.py [bg] [ui] [logo]      (no argument = all; needs Pillow + numpy)

bg  data/images/title.png                 1920x1080 background: night sky, ruined cathedral with ember-red windows,
                                          thorn vines on both sides, iron gate and graveyard, fog, lava-cracked
                                          ground, baked-in embers, falling ash, smoke lit by the title, vignette. A single file: replace it with any
                                          16:9 picture (the client crops it to the window, see login.lua).
    data/images/chaos/login/glow.png      optional overlay (windows, fires, lava) whose opacity flickers in game;
                                          delete it (or set LOGIN_GLOW = false in login.lua) when title.png is replaced
ui  data/images/chaos/login/*.png         panel frame, rune medallions, buttons, fields, crest, "press any key"
                                          plate, ember, spark and ash sprites, the halo behind the wordmark
logo data/images/chaos/logo.png           the "Cinders of Chaos" wordmark (1000x560): charred iron capitals with
                                          glowing cracks; also logo_small.png and ui/logo.png (the stock slot)
     data/images/chaos/login/logo_hot.png the glow of the wordmark (cracks, hot cores, near halo); login.lua lets
                                          its opacity smoulder over logo.png

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
    hor = np.array([0.34, 0.095, 0.040], np.float32)
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
    sky += np.array([0.12, 0.040, 0.014], np.float32) * warm[..., None]
    # the burning title lights the smoke above the scene from below (top centre, where the wordmark sits)
    lit = np.exp(-(((xx - 960) / 560) ** 2 + ((yy - 250) / 190) ** 2)) * (0.35 + 0.9 * smoke)
    sky += np.array([0.15, 0.045, 0.016], np.float32) * lit[..., None]
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


def ash_static(rng, n=560):
    """falling ash: ragged grey flakes, a few large and soft (near the eye), most small"""
    L = Layer()
    for _ in range(n):
        x = rng.uniform(0, W)
        y = rng.uniform(0, H * 0.92)
        r = rng.choice([0.9, 1.3, 1.8, 2.6, 4.0], p=[0.35, 0.3, 0.2, 0.1, 0.05])
        v = int(255 * rng.uniform(0.25, 0.75))
        pts = []
        for i in range(6):
            a = 2 * math.pi * i / 6 + rng.uniform(-0.3, 0.3)
            rr = r * rng.uniform(0.55, 1.2)
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr * 0.65))
        L.poly(pts, v)
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
    win_rgb = np.stack([np.broadcast_to(0.80 + 0.2 * wy, (H, W)), (0.085 + 0.26 * wy ** 1.5) * flick,
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
    em = embers_static(np.random.RandomState(9), 820)
    ec = np.stack([em * 1.0, em * 0.62, em * 0.18], -1)
    img += blur(ec, 0.9) * 1.1 + blur(ec, 4) * 0.55
    # --- and ash drifting down through it, lit warm from below
    ash = ash_static(np.random.RandomState(10))
    ash = blur(ash, 0.7) * 0.75 + blur(ash, 2.5) * 0.35
    ash_col = np.array([0.30, 0.27, 0.26], np.float32) + np.array([0.10, 0.03, 0.0], np.float32) * smooth(500, 1000, yy2)[..., None]
    img = img * (1 - ash[..., None] * 0.6) + ash_col * ash[..., None] * 0.6

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
    """smouldering halo drawn behind the wordmark: crimson outside, orange fire low under the letters
    (the wordmark itself is chaos/logo.png, see gen_logo)"""
    w, h = 900, 480
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r2 = ((xx - w / 2) / (w * 0.5)) ** 2 + ((yy - h * 0.5) / (h * 0.5)) ** 2
    a = np.clip(1 - r2, 0, 1) ** 2.0      # reaches 0 at the border: no visible edge of the image
    # the fire sits under each line of letters: two low, wide warm bands
    core = np.zeros((h, w), np.float32)
    for cy, sx in ((0.40, 0.40), (0.86, 0.33)):
        core += np.exp(-(((xx - w / 2) / (w * sx)) ** 2 + ((yy - h * cy) / (h * 0.11)) ** 2))
    core = np.clip(core, 0, 1)
    t = np.clip(core * 0.9, 0, 1)
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., 0] = (180 + 75 * t).astype(np.uint8)
    arr[..., 1] = (26 + 84 * t).astype(np.uint8)
    arr[..., 2] = (10 + 22 * t).astype(np.uint8)
    arr[..., 3] = (np.clip(a * 110 + core * a * 60, 0, 255)).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'logo_halo.png'))


def gen_spark():
    """small hot spark (white-yellow core) for the sparks that leave the burning title"""
    n = 12
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    r = np.sqrt((xx - 5.5) ** 2 + (yy - 5.5) ** 2)
    core = np.clip(1 - r / 2.6, 0, 1) ** 1.2
    halo = np.clip(1 - r / 5.8, 0, 1) ** 2.0
    a = np.clip(core + halo * 0.55, 0, 1)
    arr = np.zeros((n, n, 4), np.uint8)
    arr[..., 0] = 255
    arr[..., 1] = (110 + 140 * core).astype(np.uint8)
    arr[..., 2] = (24 + 200 * core ** 2).astype(np.uint8)
    arr[..., 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'spark.png'))


def gen_ash():
    """grey ash flake (ragged, soft) that drifts down over the scene"""
    n = 12
    rng = np.random.RandomState(17)
    big = Image.new('L', (n * 4, n * 4), 0)
    d = ImageDraw.Draw(big)
    pts = []
    for i in range(9):
        a = 2 * math.pi * i / 9
        rr = n * 4 * 0.5 * (0.45 + 0.5 * rng.rand())
        pts.append((n * 2 + math.cos(a) * rr, n * 2 + math.sin(a) * rr * 0.7))
    d.polygon(pts, fill=255)
    a = np.asarray(big.filter(ImageFilter.GaussianBlur(2.5)).resize((n, n), Image.LANCZOS), np.float32) / 255
    arr = np.zeros((n, n, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = 150, 140, 136
    arr[..., 3] = (a * 200).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'ash.png'))


# ------------------------------------------------------------------ wordmark "Cinders of Chaos"
# Original gothic capitals drawn as polygons (no font): each glyph lives in a 100 x 140 unit box (y down), spikes
# reach above and below it. C H A O S are the shapes of the earlier "CHAOS" logo; I N D E R F are new in the same
# style. The letters are charred iron with glowing cracks; a second image holds only the glow (cracks, hot cores,
# the halo under the letters), and login.lua lets its opacity smoulder over the base image.
LOGO_W, LOGO_H = 1000, 560                 # room around the letters for the glow
LOGO_OY = 30                               # top of the lettering in the image
LOGO_SS = 2


def _chaikin_open(pts, it=3):
    pts = list(pts)
    for _ in range(it):
        new = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            new.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            new.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        new.append(pts[-1])
        pts = new
    return pts


def _arc(cx, cy, rx, ry, a0, a1, n=18):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def glyphs():
    """letter -> (draw(d, ox, oy, k), width in units)"""
    def mk(fn):
        def draw(d, ox, oy, k):
            P = lambda pts: [(ox + x * k, oy + y * k) for x, y in pts]
            fn(d, P, ox, oy, k)
        return draw

    def stem(d, P, x=0, top=True, bottom=True):
        d.polygon(P([(x, 0), (x + 12, -16 if top else 0), (x + 24, 0), (x + 24, 140), (x + 12, 154 if bottom else 140),
                     (x, 140)]), fill=255)

    def Hf(d, P, ox, oy, k):
        stem(d, P, 0)
        stem(d, P, 76)
        d.polygon(P([(24, 56), (76, 56), (76, 70), (50, 86), (24, 70)]), fill=255)
        d.polygon(P([(24, 76), (50, 92), (76, 76), (76, 84), (24, 84)]), fill=255)

    def Af(d, P, ox, oy, k):
        d.polygon(P([(0, 140), (44, -6), (50, -26), (56, -6), (100, 140), (74, 140), (50, 40), (26, 140)]), fill=255)
        d.polygon(P([(24, 84), (76, 84), (80, 100), (20, 100)]), fill=255)
        d.polygon(P([(0, 140), (14, 156), (26, 140)]), fill=255)
        d.polygon(P([(74, 140), (86, 156), (100, 140)]), fill=255)

    def Of(d, P, ox, oy, k):
        d.ellipse([ox, oy, ox + 100 * k, oy + 140 * k], fill=255)
        d.ellipse([ox + 28 * k, oy + 30 * k, ox + 72 * k, oy + 110 * k], fill=0)
        d.polygon(P([(38, 2), (50, -22), (62, 2)]), fill=255)
        d.polygon(P([(38, 138), (50, 162), (62, 138)]), fill=255)
        d.polygon(P([(50, 56), (58, 70), (50, 84), (42, 70)]), fill=255)

    def Cf(d, P, ox, oy, k):
        d.ellipse([ox, oy, ox + 100 * k, oy + 140 * k], fill=255)
        d.ellipse([ox + 26 * k, oy + 28 * k, ox + 74 * k, oy + 112 * k], fill=0)
        d.polygon(P([(50, 70), (150, -10), (150, 150)]), fill=0)
        d.polygon(P([(88, 22), (112, 6), (94, 40)]), fill=255)
        d.polygon(P([(88, 118), (112, 134), (94, 100)]), fill=255)
        d.polygon(P([(30, 2), (42, -20), (54, 2)]), fill=255)

    def Sf(d, P, ox, oy, k):
        pts = _chaikin_open([(86, 26), (66, 6), (36, 4), (16, 26), (28, 52), (60, 70), (84, 92), (78, 120), (54, 138),
                             (24, 134), (8, 112)], 3)
        Q = P(pts)
        w = int(23 * k)
        d.line(Q, fill=255, width=w, joint='curve')
        r = w / 2
        for (x, y) in Q[::2]:
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        for (x, y, dx, dy) in ((86, 26, 18, -6), (8, 112, -14, 12)):
            X, Y = ox + x * k, oy + y * k
            d.polygon([(X - 12 * k, Y - 10 * k), (X + dx * k, Y + dy * k), (X + 12 * k, Y + 10 * k)], fill=255)

    def If(d, P, ox, oy, k):
        stem(d, P, 10)
        d.polygon(P([(0, -2), (44, -2), (34, 14), (10, 14)]), fill=255)
        d.polygon(P([(10, 126), (34, 126), (44, 142), (0, 142)]), fill=255)

    def Nf(d, P, ox, oy, k):
        stem(d, P, 0, bottom=False)
        stem(d, P, 76, top=False)
        d.polygon(P([(0, 0), (26, 0), (100, 140), (74, 140)]), fill=255)

    def Df(d, P, ox, oy, k):
        d.polygon(P([(12, 0), (50, 0)] + _arc(50, 70, 48, 70, -90, 90) + [(12, 140)]), fill=255)
        d.polygon(P([(24, 26), (48, 26)] + _arc(48, 70, 26, 44, -90, 90) + [(24, 114)]), fill=0)
        stem(d, P, 0)
        d.polygon(P([(94, 58), (110, 70), (94, 82)]), fill=255)

    def bar_top(d, P, right):
        d.polygon(P([(24, 0), (right, 0), (right - 8, 24), (24, 24)]), fill=255)
        d.polygon(P([(right - 14, 0), (right, 0), (right + 2, 36)]), fill=255)

    def bar_mid(d, P, right):
        d.polygon(P([(24, 58), (right - 14, 58), (right, 70), (right - 14, 82), (24, 82)]), fill=255)

    def Ef(d, P, ox, oy, k):
        stem(d, P, 0)
        bar_top(d, P, 92)
        bar_mid(d, P, 80)
        d.polygon(P([(24, 116), (84, 116), (92, 140), (24, 140)]), fill=255)
        d.polygon(P([(78, 140), (94, 140), (96, 102)]), fill=255)

    def Ff(d, P, ox, oy, k):
        stem(d, P, 0)
        bar_top(d, P, 90)
        bar_mid(d, P, 78)

    def Rf(d, P, ox, oy, k):
        d.polygon(P([(12, 0), (56, 0)] + _arc(56, 41, 40, 41, -90, 90) + [(12, 82)]), fill=255)
        d.polygon(P([(24, 22), (54, 22)] + _arc(54, 41, 20, 19, -90, 90) + [(24, 60)]), fill=0)
        stem(d, P, 0)
        d.polygon(P([(40, 70), (66, 70), (100, 140), (74, 140)]), fill=255)
        d.polygon(P([(74, 140), (86, 156), (100, 140)]), fill=255)

    return {'C': (mk(Cf), 100), 'H': (mk(Hf), 100), 'A': (mk(Af), 100), 'O': (mk(Of), 100), 'S': (mk(Sf), 100),
            'I': (mk(If), 44), 'N': (mk(Nf), 100), 'D': (mk(Df), 104), 'E': (mk(Ef), 94), 'R': (mk(Rf), 100),
            'F': (mk(Ff), 90)}


def word_width(word, k, gap=22):
    G = glyphs()
    return (sum(G[c][1] for c in word) + gap * (len(word) - 1)) * k


def draw_word(word, cx, top, k, size, gap=22):
    """mask (L, size) with the word centred on cx, glyph box top at `top` (all in output pixels x LOGO_SS)"""
    G = glyphs()
    m = Image.new('L', size, 0)
    d = ImageDraw.Draw(m)
    x = cx - word_width(word, k, gap) / 2
    for c in word:
        fn, wd = G[c]
        fn(d, x, top, k)
        x += (wd + gap) * k
    return m


def ember_ramp(h):
    """0..1 heat -> rgb 0..255: dull red, crimson, orange, yellow, white-hot"""
    stops = [(0.0, (70, 8, 4)), (0.3, (176, 28, 8)), (0.55, (246, 86, 16)), (0.8, (255, 170, 60)),
             (1.0, (255, 238, 186))]
    out = np.zeros(h.shape + (3,), np.float32)
    for i in range(3):
        out[..., i] = np.interp(h, [s[0] for s in stops], [s[1][i] for s in stops])
    return out


def make_wordmark():
    """returns (base RGBA, hot glow RGBA), both LOGO_W x LOGO_H"""
    s = LOGO_SS
    Wd, Hd = LOGO_W * s, LOGO_H * s
    cx = Wd / 2
    k1, k2 = 1.04 * s, 1.18 * s                       # CINDERS, CHAOS
    top1, top2 = (34 + LOGO_OY) * s, (280 + LOGO_OY) * s
    m1 = draw_word('CINDERS', cx, top1, k1, (Wd, Hd))
    m2 = draw_word('CHAOS', cx, top2, k2, (Wd, Hd))
    # "OF" between the lines: O left and F right of the spike of the A that rises between them
    ko = 0.40 * s
    of_top = (197 + LOGO_OY) * s
    m3 = Image.new('L', (Wd, Hd), 0)
    g = glyphs()
    g['O'][0](ImageDraw.Draw(m3), cx - 18 * s - 100 * ko, of_top, ko)
    g['F'][0](ImageDraw.Draw(m3), cx + 18 * s, of_top, ko)
    M = np.maximum(np.maximum(np.asarray(m1), np.asarray(m2)), np.asarray(m3)).astype(np.float32) / 255
    mimg = Image.fromarray((M * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6 * s))
    M = np.asarray(mimg, np.float32) / 255

    def sh(a, dx, dy):
        return np.roll(np.roll(a, dy, 0), dx, 1)

    def erode(img, r):
        return np.asarray(img.filter(ImageFilter.MinFilter(2 * r + 1)), np.float32) / 255

    def dilate(img, r):
        return np.asarray(img.filter(ImageFilter.MaxFilter(2 * r + 1)), np.float32) / 255

    # depth inside the strokes (0 at the edge, 1 in the middle of a thick stroke)
    depth = np.clip((blur(M, 5 * s) - 0.5) * 2.2, 0, 1) * M
    # cracks: ridges of two noise scales, wider where the stroke is deep
    n1 = fbm(Hd, Wd, 30 * s, 4, 501, 0.55)
    n2 = fbm(Hd, Wd, 12 * s, 3, 502, 0.5)
    r1 = 1 - smooth(0.0, 0.042, np.abs(n1 - 0.5))
    r2 = 1 - smooth(0.0, 0.030, np.abs(n2 - 0.5))
    cracks = np.maximum(r1, r2 * 0.6)
    patch = 0.2 + 1.0 * smooth(0.25, 0.8, fbm(Hd, Wd, 60 * s, 3, 503))   # hotter and cooler parts of the letters
    yy = np.arange(Hd, dtype=np.float32)[:, None]
    # each line burns hotter toward its foot (the fire is under the letters)
    foot = np.clip(np.where(yy < (240 + LOGO_OY) * s, (yy - top1) / (150 * s), (yy - top2) / (170 * s)), 0, 1)
    hot = cracks * (0.35 + 0.85 * depth) * patch * (0.6 + 0.6 * foot) + depth ** 2 * 0.22 * (0.5 + foot)
    of_m = np.asarray(m3.filter(ImageFilter.GaussianBlur(0.6 * s)), np.float32) / 255
    hot = np.maximum(np.clip(hot, 0, 1), of_m * 0.62) * M

    # charred crust: near-black with grey ash flecks and a little warmth
    grain = fbm(Hd, Wd, 6 * s, 3, 504, 0.6)
    ash = smooth(0.62, 0.8, fbm(Hd, Wd, 9 * s, 3, 505))
    crust = np.stack([20 + 22 * grain, 13 + 13 * grain, 13 + 11 * grain], -1)
    ash = ash * smooth(0.55, 0.75, fbm(Hd, Wd, 40 * s, 2, 506))
    crust = crust * (1 - ash[..., None] * 0.55) + np.array([96, 88, 84], np.float32) * ash[..., None] * 0.55
    a_base = smooth(0.04, 0.55, hot) * 0.7
    body = crust * (1 - a_base[..., None]) + ember_ramp(np.clip(hot * 0.8, 0, 1)) * a_base[..., None]
    # iron edge: a rim of dark iron, lit from the top left, shaded bottom right
    rim = np.clip(M - erode(mimg, 3 * s), 0, 1)
    iron = np.array([58, 50, 52], np.float32)
    body = body * (1 - rim[..., None] * 0.85) + iron * rim[..., None] * 0.85
    hi = blur(np.clip(M - sh(M, 2 * s, 2 * s), 0, 1), 1.0 * s)
    lo = blur(np.clip(M - sh(M, -2 * s, -2 * s), 0, 1), 1.0 * s)
    body = body + hi[..., None] * (np.array([176, 150, 136], np.float32) - body) * 0.75
    body = body * (1 - lo[..., None] * 0.55)
    # the glowing underside of the rim (embers light the iron from below)
    under = blur(np.clip(M - sh(M, 0, -3 * s), 0, 1), 1.2 * s) * (0.4 + 0.6 * foot)
    body = body + under[..., None] * (np.array([255, 110, 30], np.float32) - body) * 0.55

    # outline, shadow and glow under the letters
    out = np.zeros((Hd, Wd, 4), np.float32)
    g_far = blur(sh(M, 0, 10 * s), 24 * s)
    g_near = blur(M, 7 * s)
    glow_a = np.clip(g_far * 0.95 + g_near * 0.55, 0, 1)
    glow_c = np.array([196, 34, 10], np.float32) * (1 - g_near[..., None]) + \
        np.array([255, 96, 24], np.float32) * g_near[..., None]
    out[..., :3] = glow_c
    out[..., 3] = glow_a * 255
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')
    outline = dilate(mimg, 2 * s)
    ol = np.zeros((Hd, Wd, 4), np.float32)
    ol[..., 0], ol[..., 1], ol[..., 2] = 8, 4, 4
    ol[..., 3] = np.clip(outline + blur(sh(M, 3 * s, 5 * s), 3 * s) * 0.7, 0, 1) * 255
    img.alpha_composite(Image.fromarray(ol.astype(np.uint8), 'RGBA'))

    # ornament: two ember lines from the "OF" outward, with a diamond at each end
    od = ImageDraw.Draw(img)
    ly = of_top + 70 * ko
    for sgn in (-1, 1):
        x0 = cx + sgn * (18 * s + 100 * ko + 14 * s)
        span = 230 * s
        for i in range(int(span)):
            t = i / span
            col = tuple(int(c) for c in ember_ramp(np.array(0.75 - 0.5 * t))) + (int(235 * (1 - t) ** 0.8),)
            od.point((x0 + sgn * i, ly), col)
            od.point((x0 + sgn * i, ly + 1), col)
            if t < 0.55:
                od.point((x0 + sgn * i, ly + 2), col[:3] + (col[3] // 3,))
        for (dx, r) in ((0, 5), (span * 0.62, 4)):
            px = x0 + sgn * (dx + 2 * s)
            od.polygon([(px, ly - r * s), (px + r * s, ly + 1), (px, ly + 2 + r * s), (px - r * s, ly + 1)],
                       fill=(10, 5, 5, 255))
            od.polygon([(px, ly - (r - 2) * s), (px + (r - 2) * s, ly + 1), (px, ly + 2 + (r - 2) * s),
                        (px - (r - 2) * s, ly + 1)], fill=(246, 96, 22, 255))

    layer = np.dstack([np.clip(body, 0, 255), M * 255]).astype(np.uint8)
    img.alpha_composite(Image.fromarray(layer, 'RGBA'))

    # a few sparks frozen above the letters (the moving ones are widgets, see login.lua)
    rng = np.random.RandomState(77)
    sp = ImageDraw.Draw(img)
    ys, xs = np.nonzero(M[::4, ::4] > 0.5)
    for i in rng.choice(len(xs), 46, replace=False):
        x, y = xs[i] * 4 + rng.uniform(-6, 6) * s, ys[i] * 4 - rng.uniform(6, 40) * s
        r = rng.choice([0.7, 1.0, 1.4]) * s
        c = tuple(int(v) for v in ember_ramp(np.array(rng.uniform(0.55, 0.95)))) + (int(rng.uniform(120, 240)),)
        sp.ellipse([x - r, y - r, x + r, y + r], fill=c)

    # the glow image: the cracks at full heat, the hot cores and the near halo
    hot2 = np.clip(hot * 1.25, 0, 1)
    ha = np.clip(smooth(0.06, 0.6, hot2) * M + np.clip(g_near - M, 0, 1) * 0.42, 0, 1)
    hc = ember_ramp(np.maximum(hot2, 0.5 * (1 - M)))
    hot_img = Image.fromarray(np.dstack([np.clip(hc, 0, 255), ha * 255]).astype(np.uint8), 'RGBA')

    size = (LOGO_W, LOGO_H)
    return img.resize(size, Image.LANCZOS), hot_img.resize(size, Image.LANCZOS)


def gen_logo():
    base, hot = make_wordmark()
    save(base, os.path.join(IMG, 'chaos', 'logo.png'))
    save(base.resize((LOGO_W // 2, LOGO_H // 2), Image.LANCZOS), os.path.join(IMG, 'chaos', 'logo_small.png'))
    save(hot, os.path.join(UI_OUT, 'logo_hot.png'))
    # the stock login screen's own logo slot (hidden by client_chaos_login, 225 x 261)
    ui = Image.new('RGBA', (225, 261), (0, 0, 0, 0))
    sm = base.resize((225, round(225 * LOGO_H / LOGO_W)), Image.LANCZOS)
    ui.alpha_composite(sm, (0, (261 - sm.height) // 2))
    save(ui, os.path.join(IMG, 'ui', 'logo.png'))


def gen_ui():
    gen_panel()
    gen_crest()
    gen_medallion(0, 'medallion_left.png')
    gen_medallion(1, 'medallion_right.png')
    gen_buttons()
    gen_fields()
    gen_pressplate()
    gen_ember()
    gen_spark()
    gen_ash()
    gen_logo_glow()


def gen_bg():
    bg, glow = make_background()
    save(bg, os.path.join(IMG, 'title.png'))
    save(glow, os.path.join(UI_OUT, 'glow.png'))


if __name__ == '__main__':
    tasks = sys.argv[1:] or ['bg', 'ui', 'logo']
    for t in tasks:
        {'bg': gen_bg, 'ui': gen_ui, 'logo': gen_logo}[t]()
