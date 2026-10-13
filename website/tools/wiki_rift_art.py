#!/usr/bin/env python3
"""The rift icons of the website's wiki (gen_wiki_art.py imports this file; website/README.md "Wiki art").

Painted-look icons, drawn here from shapes: every shape is a mask, shaded by a height field lit from the upper left
(a colour ramp, a soft specular, a fine grain), outlined in near black and set on one framed plate. Work size 192 px,
written at 64 px (gen_wiki_art.py scales; heroes use the full drawing). Our own art only: the guardian portraits and the rift monsters of `rx-clear` are crops of our own
rift looks (client/tools/sprites/art_import/big_bosses/, rift_variants/), kept as a snapshot in
website/tools/wiki_art_src/rift_creatures.png (`python3 -I website/tools/gen_wiki_art.py import-creatures` refreshes
it), so a repaint of those looks never changes the wiki by surprise.

Names (wiki/i/<name>.png, chosen by server/tools/gen_wiki_data.lua):
  rm-<side>-<key>     a rift modifier: its motif says what it does; the frame says who it hits (prefix: the monsters
                      grow stronger, crimson; suffix: the players or the ground get worse, violet; boon: a reward, gold)
  rk-<tier>           a Rift Key of that tier: the tier band's gem and metal, pips for the tier inside the band
  ro-<omen>[-asc]     an Omen's emblem (bloodmoon, hollow, storm); -asc: its Ascended form
  rt-<theme>          a rift theme's vignette (abyss, hall, crypt, sanctum)
  rg-<look>           a guardian portrait (abyss, hall, crypt, sanctum, seer)
  an-<kind>-<branch>-<glyph>  a Rift Atlas node: a star map medallion in the branch's colour, the node's motif
  rx-<thing>          portal, chest, atlas, lives, clear, omenkey, omenfragment, ascended
Deterministic (no clock, no unseeded random). Needs Pillow and numpy.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
CREATURES = os.path.join(HERE, "wiki_art_src", "rift_creatures.png")
ART = os.path.join(REPO, "client", "tools", "sprites", "art_import")

W = 192
OUT = 64

# ---------------------------------------------------------------- palettes (dark to light)
IRON = [(12, 10, 14), (44, 40, 48), (88, 82, 92), (146, 138, 148), (212, 206, 214)]
GOLD = [(38, 22, 6), (112, 70, 16), (192, 132, 40), (242, 198, 98), (255, 242, 196)]
BLOOD = [(30, 4, 4), (92, 10, 10), (164, 26, 18), (222, 64, 42), (255, 156, 124)]
FLESH = [(16, 10, 20), (52, 34, 60), (98, 70, 108), (152, 122, 160), (214, 194, 222)]
BONE = [(40, 32, 24), (108, 94, 74), (178, 164, 138), (226, 214, 186), (252, 246, 230)]
VOID = [(14, 6, 26), (52, 20, 92), (112, 52, 184), (174, 116, 244), (236, 214, 255)]
FIRE = [(64, 10, 0), (172, 52, 10), (242, 124, 32), (255, 204, 84), (255, 250, 214)]
ICE = [(10, 30, 62), (40, 92, 152), (102, 172, 232), (182, 226, 255), (242, 252, 255)]
STORM = [(26, 26, 66), (68, 80, 172), (132, 152, 252), (204, 216, 255), (252, 252, 255)]
POISON = [(10, 30, 8), (40, 92, 22), (102, 172, 52), (172, 232, 104), (232, 255, 204)]
ROT = [(14, 18, 10), (44, 54, 30), (88, 100, 58), (140, 150, 96), (198, 204, 158)]
WOOD = [(30, 16, 8), (82, 46, 20), (132, 82, 40), (182, 128, 72), (222, 182, 124)]
MANA = [(8, 16, 62), (30, 52, 152), (72, 112, 232), (152, 182, 255), (232, 242, 255)]
SILVER = [(20, 22, 30), (72, 78, 92), (142, 150, 166), (202, 210, 224), (250, 252, 255)]
SOUL = [(10, 30, 50), (30, 90, 130), (80, 170, 210), (170, 230, 250), (240, 255, 255)]
ASH = [(16, 14, 14), (48, 44, 42), (92, 86, 80), (144, 136, 126), (200, 192, 180)]
OBSID = [(8, 6, 8), (28, 22, 28), (56, 46, 54), (96, 84, 92), (150, 136, 144)]
MOSS = [(12, 24, 10), (34, 62, 24), (70, 112, 46), (122, 164, 80), (186, 214, 140)]

SIDE = {"prefix": ((150, 22, 14), BLOOD), "suffix": ((96, 40, 170), VOID), "boon": ((200, 140, 40), GOLD),
        "neutral": ((150, 104, 40), GOLD)}
THEME = {"abyss": (124, 60, 210), "hall": (232, 100, 30), "crypt": (200, 180, 140), "sanctum": (90, 180, 70),
         "core": (232, 190, 90)}


def P(v):
    return v * W / 100.0


def box(cx, cy, rx, ry=None):
    ry = rx if ry is None else ry
    return [P(cx - rx), P(cy - ry), P(cx + rx), P(cy + ry)]


def pts(seq):
    return [(P(x), P(y)) for x, y in seq]


def rot(seq, cx, cy, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in seq]


def mask(fn):
    m = Image.new("L", (W, W), 0)
    fn(ImageDraw.Draw(m))
    return m


def _grain(seed):
    rng = np.random.RandomState(seed)
    g = rng.rand(W // 4 + 2, W // 4 + 2).astype(np.float32)
    return np.asarray(Image.fromarray(g, "F").resize((W, W), Image.BICUBIC))


def ramp_at(ramp, t):
    r = np.array(ramp, np.float32)
    x = np.clip(t, 0, 1) * (len(ramp) - 1)
    i = np.clip(np.floor(x).astype(int), 0, len(ramp) - 2)
    f = (x - i)[..., None]
    return r[i] * (1 - f) + r[i + 1] * f


class Icon:
    """A 192 px RGBA canvas that shapes are painted on."""

    def __init__(self, seed=1):
        self.a = np.zeros((W, W, 4), np.float32)
        self.seed = seed

    def over(self, rgba, alpha):
        a = np.clip(alpha, 0, 1)[..., None]
        self.a[..., :3] = self.a[..., :3] * (1 - a) + rgba * a
        self.a[..., 3] = self.a[..., 3] + (1 - self.a[..., 3]) * a[..., 0]

    def add(self, rgb, alpha):
        """additive light (glows)"""
        self.a[..., :3] = np.clip(self.a[..., :3] + np.array(rgb, np.float32) * np.clip(alpha, 0, 1)[..., None], 0, 255)
        self.a[..., 3] = np.clip(self.a[..., 3] + alpha * 0.8, 0, 1)

    def paint(self, fn, ramp, gloss=0.35, outline=2.2, soft=W / 34, base=0.1, opacity=1.0):
        m = mask(fn)
        mf = np.asarray(m.filter(ImageFilter.GaussianBlur(0.7))).astype(np.float32) / 255
        if outline:
            ol = np.asarray(m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(outline))).astype(np.float32) / 255
            self.over(np.array((10, 6, 10), np.float32), np.clip(ol * 1.6, 0, 1) * 0.95 * opacity)
        h = np.asarray(m.filter(ImageFilter.GaussianBlur(soft))).astype(np.float32) / 255
        gy, gx = np.gradient(h)
        k = 9.0
        nx, ny, nz = -gx * k, -gy * k, np.ones_like(h)
        n = np.sqrt(nx * nx + ny * ny + nz * nz)
        lx, ly, lz = -0.55, -0.62, 0.56
        lam = np.clip((nx * lx + ny * ly + nz * lz) / n, 0, 1)
        g = _grain(self.seed)
        self.seed += 1
        t = np.clip(base + 1.05 * lam ** 1.4 + (g - 0.5) * 0.12, 0, 1)
        col = ramp_at(ramp, t)
        col += 255 * (lam ** 18)[..., None] * gloss
        self.over(np.clip(col, 0, 255), mf * opacity)
        return m

    def glow(self, fn, rgb, radius=10, strength=1.0):
        m = mask(fn).filter(ImageFilter.GaussianBlur(P(radius) / 4))
        self.add(rgb, np.asarray(m).astype(np.float32) / 255 * strength)

    def flat(self, fn, rgb, alpha=1.0, blur=0.6):
        m = mask(fn).filter(ImageFilter.GaussianBlur(blur))
        self.over(np.array(rgb, np.float32), np.asarray(m).astype(np.float32) / 255 * alpha)

    def image(self):
        return Image.fromarray(np.clip(np.dstack([self.a[..., :3], self.a[..., 3:] * 255]), 0, 255).astype(np.uint8), "RGBA")


# ---------------------------------------------------------------- shapes (draw on a mask, units 0..100)
def s_circle(cx, cy, r):
    return lambda d: d.ellipse(box(cx, cy, r), fill=255)


def s_heart(cx, cy, s):
    def f(d):
        d.ellipse(box(cx - 11 * s, cy - 6 * s, 13 * s), fill=255)
        d.ellipse(box(cx + 11 * s, cy - 6 * s, 13 * s), fill=255)
        d.polygon(pts([(cx - 23.5 * s, cy - 3 * s), (cx + 23.5 * s, cy - 3 * s), (cx, cy + 26 * s)]), fill=255)
    return f


def s_head(cx, cy, s, eyes=True):
    """a horned monster head"""
    def f(d):
        d.ellipse(box(cx, cy, 17 * s, 20 * s), fill=255)
        d.polygon(pts([(cx - 12 * s, cy + 8 * s), (cx + 12 * s, cy + 8 * s), (cx + 6 * s, cy + 24 * s), (cx - 6 * s, cy + 24 * s)]), fill=255)
        for sx in (-1, 1):
            d.polygon(pts([(cx + sx * 8 * s, cy - 13 * s), (cx + sx * 20 * s, cy - 19 * s), (cx + sx * 29 * s, cy - 27 * s),
                           (cx + sx * 31 * s, cy - 40 * s), (cx + sx * 25 * s, cy - 31 * s), (cx + sx * 18 * s, cy - 25 * s),
                           (cx + sx * 13 * s, cy - 21 * s)]), fill=255)
        if eyes:
            for sx in (-1, 1):
                d.polygon(pts([(cx + sx * 3 * s, cy - 1 * s), (cx + sx * 12 * s, cy - 4 * s), (cx + sx * 10 * s, cy + 3 * s)]), fill=0)
            for i in range(-2, 3):
                d.polygon(pts([(cx + i * 3.4 * s - 1.4 * s, cy + 14 * s), (cx + i * 3.4 * s + 1.4 * s, cy + 14 * s),
                               (cx + i * 3.4 * s, cy + 19 * s)]), fill=0)
    return f


def head_eyes(ic, cx, cy, s, rgb=(255, 60, 30)):
    ic.glow(lambda d: [d.ellipse(box(cx + sx * 7.5 * s, cy - 1 * s, 3.4 * s), fill=255) for sx in (-1, 1)], rgb, 6 * s, 1.4)
    ic.flat(lambda d: [d.polygon(pts([(cx + sx * 3 * s, cy - 1 * s), (cx + sx * 12 * s, cy - 4 * s), (cx + sx * 10 * s, cy + 3 * s)]), fill=255)
                       for sx in (-1, 1)], tuple(min(255, c + 90) for c in rgb), 0.9)


def s_helm(cx, cy, s):
    """a guardian's great helm with horns"""
    def f(d):
        d.rounded_rectangle(box(cx, cy + 2 * s, 18 * s, 22 * s), radius=P(9 * s), fill=255)
        d.polygon(pts([(cx - 18 * s, cy + 10 * s), (cx + 18 * s, cy + 10 * s), (cx + 12 * s, cy + 28 * s), (cx - 12 * s, cy + 28 * s)]), fill=255)
        for sx in (-1, 1):
            d.polygon(pts([(cx + sx * 14 * s, cy - 10 * s), (cx + sx * 34 * s, cy - 18 * s), (cx + sx * 40 * s, cy - 40 * s),
                           (cx + sx * 30 * s, cy - 24 * s), (cx + sx * 16 * s, cy - 18 * s)]), fill=255)
        d.rectangle(box(cx, cy - 1 * s, 14 * s, 2.6 * s), fill=0)
        d.rectangle(box(cx, cy + 8 * s, 1.6 * s, 8 * s), fill=0)
    return f


def helm_eyes(ic, cx, cy, s, rgb=(255, 50, 30)):
    ic.glow(lambda d: d.rectangle(box(cx, cy - 1 * s, 13 * s, 2.4 * s), fill=255), rgb, 7 * s, 1.5)
    ic.flat(lambda d: d.rectangle(box(cx, cy - 1 * s, 12 * s, 1.4 * s), fill=255), tuple(min(255, c + 110) for c in rgb), 0.9)


def s_skull(cx, cy, s):
    def f(d):
        d.ellipse(box(cx, cy - 4 * s, 20 * s, 19 * s), fill=255)
        d.rounded_rectangle(box(cx, cy + 14 * s, 11 * s, 8 * s), radius=P(3 * s), fill=255)
        for sx in (-1, 1):
            d.ellipse(box(cx + sx * 8 * s, cy, 5.5 * s, 6 * s), fill=0)
        d.polygon(pts([(cx, cy + 5 * s), (cx - 3 * s, cy + 11 * s), (cx + 3 * s, cy + 11 * s)]), fill=0)
        for i in (-1, 0, 1):
            d.rectangle(box(cx + i * 5 * s, cy + 18 * s, 0.9 * s, 4 * s), fill=0)
    return f


def s_claws(cx, cy, s, ang=-35):
    def f(d):
        for i in (-1, 0, 1):
            ox = cx + i * 13 * s
            seq = [(ox - 3 * s, cy - 30 * s), (ox + 4 * s, cy - 6 * s), (ox + 2 * s, cy + 30 * s), (ox - 1 * s, cy + 6 * s)]
            d.polygon(pts(rot(seq, cx, cy, ang)), fill=255)
    return f


def s_sword(cx, cy, s, ang=-45, broken=False):
    def f(d):
        blade = [(cx - 3.5 * s, cy - 6 * s), (cx + 3.5 * s, cy - 6 * s), (cx + 3.5 * s, cy - 36 * s), (cx, cy - 44 * s), (cx - 3.5 * s, cy - 36 * s)]
        if broken:
            blade = [(cx - 3.5 * s, cy - 6 * s), (cx + 3.5 * s, cy - 6 * s), (cx + 3.5 * s, cy - 20 * s), (cx - 1 * s, cy - 24 * s), (cx - 3.5 * s, cy - 18 * s)]
        d.polygon(pts(rot(blade, cx, cy, ang)), fill=255)
        d.polygon(pts(rot([(cx - 14 * s, cy - 6 * s), (cx + 14 * s, cy - 6 * s), (cx + 14 * s, cy - 1 * s), (cx - 14 * s, cy - 1 * s)], cx, cy, ang)), fill=255)
        d.polygon(pts(rot([(cx - 2.5 * s, cy - 1 * s), (cx + 2.5 * s, cy - 1 * s), (cx + 2.5 * s, cy + 14 * s), (cx - 2.5 * s, cy + 14 * s)], cx, cy, ang)), fill=255)
        d.ellipse(box(*rot([(cx, cy + 17 * s)], cx, cy, ang)[0], 4 * s), fill=255)
    return f


def s_crown(cx, cy, s):
    def f(d):
        d.polygon(pts([(cx - 26 * s, cy + 12 * s), (cx + 26 * s, cy + 12 * s), (cx + 28 * s, cy - 14 * s), (cx + 14 * s, cy),
                       (cx, cy - 20 * s), (cx - 14 * s, cy), (cx - 28 * s, cy - 14 * s)]), fill=255)
        d.rectangle(box(cx, cy + 15 * s, 26 * s, 4 * s), fill=255)
        for x, y in ((-28, -16), (0, -22), (28, -16)):
            d.ellipse(box(cx + x * s, cy + y * s, 4 * s), fill=255)
    return f


def s_shard(cx, cy, s, ang=0):
    return lambda d: d.polygon(pts(rot([(cx - 6 * s, cy - 32 * s), (cx + 14 * s, cy - 20 * s), (cx + 18 * s, cy + 10 * s), (cx + 4 * s, cy + 32 * s),
                                        (cx - 14 * s, cy + 18 * s), (cx - 16 * s, cy - 10 * s)], cx, cy, ang)), fill=255)


def s_shield(cx, cy, s):
    def f(d):
        seq = [(cx - 24 * s, cy - 26 * s), (cx + 24 * s, cy - 26 * s), (cx + 24 * s, cy)]
        for i in range(11):
            a = math.radians(i * 9)
            seq.append((cx + 24 * s * math.cos(a), cy + 28 * s * math.sin(a)))
        seq += [(cx - 24 * s * math.cos(math.radians(i * 9)), cy + 28 * s * math.sin(math.radians(i * 9))) for i in range(10, -1, -1)]
        d.polygon(pts(seq), fill=255)
    return f


def s_drop(cx, cy, s):
    def f(d):
        d.ellipse(box(cx, cy + 8 * s, 18 * s), fill=255)
        d.polygon(pts([(cx, cy - 28 * s), (cx - 16.5 * s, cy + 2 * s), (cx + 16.5 * s, cy + 2 * s)]), fill=255)
    return f


def s_coins(cx, cy, s, n=4):
    def f(d):
        for i in range(n):
            d.ellipse(box(cx, cy - i * 6 * s, 15 * s, 6 * s), fill=255)
    return f


def s_hourglass(cx, cy, s):
    def f(d):
        d.rectangle(box(cx, cy - 26 * s, 20 * s, 3.5 * s), fill=255)
        d.rectangle(box(cx, cy + 26 * s, 20 * s, 3.5 * s), fill=255)
        for sx in (-1, 1):
            d.rectangle(box(cx + sx * 16 * s, cy, 2 * s, 24 * s), fill=255)
    return f


def s_glass(cx, cy, s):
    return lambda d: d.polygon(pts([(cx - 13 * s, cy - 22 * s), (cx + 13 * s, cy - 22 * s), (cx + 2.5 * s, cy), (cx + 13 * s, cy + 22 * s),
                                    (cx - 13 * s, cy + 22 * s), (cx - 2.5 * s, cy)]), fill=255)


def s_flame(cx, cy, s):
    def f(d):
        d.ellipse(box(cx, cy + 10 * s, 14 * s, 13 * s), fill=255)
        d.polygon(pts([(cx - 14 * s, cy + 8 * s), (cx - 6 * s, cy - 14 * s), (cx - 2 * s, cy - 4 * s), (cx + 3 * s, cy - 30 * s),
                       (cx + 9 * s, cy - 8 * s), (cx + 12 * s, cy - 16 * s), (cx + 14 * s, cy + 8 * s)]), fill=255)
    return f


def s_flake(cx, cy, s):
    def f(d):
        for k in range(6):
            a = math.radians(k * 60 - 90)
            x2, y2 = cx + 24 * s * math.cos(a), cy + 24 * s * math.sin(a)
            d.line(pts([(cx, cy), (x2, y2)]), fill=255, width=max(1, int(P(4 * s))))
            for side in (-1, 1):
                b = a + side * math.radians(40)
                mx, my = cx + 14 * s * math.cos(a), cy + 14 * s * math.sin(a)
                d.line(pts([(mx, my), (mx + 8 * s * math.cos(b), my + 8 * s * math.sin(b))]), fill=255, width=max(1, int(P(3 * s))))
        d.ellipse(box(cx, cy, 5 * s), fill=255)
    return f


def s_bolt(cx, cy, s):
    return lambda d: d.polygon(pts([(cx + 6 * s, cy - 30 * s), (cx - 14 * s, cy + 4 * s), (cx - 1 * s, cy + 4 * s), (cx - 8 * s, cy + 30 * s),
                                    (cx + 15 * s, cy - 6 * s), (cx + 2 * s, cy - 6 * s)]), fill=255)


def s_fang(cx, cy, s):
    return lambda d: d.polygon(pts([(cx - 14 * s, cy - 26 * s), (cx + 14 * s, cy - 26 * s), (cx + 10 * s, cy - 6 * s), (cx + 2 * s, cy + 18 * s),
                                    (cx - 4 * s, cy + 32 * s), (cx - 6 * s, cy + 10 * s), (cx - 12 * s, cy - 10 * s)]), fill=255)


def s_cross(cx, cy, s):
    def f(d):
        d.rounded_rectangle(box(cx, cy, 8 * s, 26 * s), radius=P(3 * s), fill=255)
        d.rounded_rectangle(box(cx, cy, 26 * s, 8 * s), radius=P(3 * s), fill=255)
    return f


def s_ring(cx, cy, r, w):
    def f(d):
        d.ellipse(box(cx, cy, r), fill=255)
        d.ellipse(box(cx, cy, r - w), fill=0)
    return f


def s_tear(cx, cy, s, seed=3):
    """a jagged vertical tear in the world"""
    rng = np.random.RandomState(seed)

    def f(d):
        left, right = [], []
        n = 22
        for i in range(n + 1):
            t = i / n
            y = cy - 38 * s + t * 76 * s
            wdt = math.sin(math.pi * t) ** 0.7 * 17 * s
            j = (rng.rand() - 0.5) * 9 * s
            left.append((cx - wdt + j + math.sin(t * 7) * 3 * s, y))
            right.append((cx + wdt + j * 0.6 + math.sin(t * 7) * 3 * s, y))
        d.polygon(pts(left + right[::-1]), fill=255)
    return f


def s_banner(cx, cy, s):
    def f(d):
        d.rectangle(box(cx, cy - 30 * s, 26 * s, 2.5 * s), fill=255)
        d.polygon(pts([(cx - 22 * s, cy - 28 * s), (cx + 22 * s, cy - 28 * s), (cx + 22 * s, cy + 26 * s), (cx, cy + 14 * s), (cx - 22 * s, cy + 26 * s)]), fill=255)
    return f


def s_star(cx, cy, r, inner=0.42, n=4, ang=-90):
    def f(d):
        seq = []
        for i in range(n * 2):
            a = math.radians(ang + i * 180 / n)
            rr = r if i % 2 == 0 else r * inner
            seq.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        d.polygon(pts(seq), fill=255)
    return f


def s_bag(cx, cy, s):
    def f(d):
        d.ellipse(box(cx, cy + 8 * s, 24 * s, 22 * s), fill=255)
        d.polygon(pts([(cx - 10 * s, cy - 18 * s), (cx + 10 * s, cy - 18 * s), (cx + 16 * s, cy - 6 * s), (cx - 16 * s, cy - 6 * s)]), fill=255)
        d.polygon(pts([(cx - 14 * s, cy - 26 * s), (cx - 4 * s, cy - 18 * s), (cx + 4 * s, cy - 18 * s), (cx + 14 * s, cy - 26 * s), (cx, cy - 20 * s)]), fill=255)
    return f


def s_cloud(cx, cy, s):
    def f(d):
        for x, y, r in ((-16, 4, 12), (0, -4, 16), (16, 4, 12), (-6, 8, 12), (8, 8, 12)):
            d.ellipse(box(cx + x * s, cy + y * s, r * s), fill=255)
    return f


def s_egg(cx, cy, s):
    return lambda d: d.ellipse(box(cx, cy, 13 * s, 17 * s), fill=255)


def s_sigil(cx, cy, s):
    """a hex circle: a ring with a triangle and runes"""
    def f(d):
        d.ellipse(box(cx, cy, 30 * s), fill=255)
        d.ellipse(box(cx, cy, 25 * s), fill=0)
        d.ellipse(box(cx, cy, 22 * s), fill=255)
        d.ellipse(box(cx, cy, 20 * s), fill=0)
        tri = [(cx + 20 * s * math.cos(math.radians(-90 + k * 120)), cy + 20 * s * math.sin(math.radians(-90 + k * 120))) for k in range(3)]
        for i in range(3):
            d.line(pts([tri[i], tri[(i + 1) % 3]]), fill=255, width=max(1, int(P(2.6 * s))))
        for k in range(6):
            a = math.radians(k * 60 - 60)
            d.ellipse(box(cx + 27.5 * s * math.cos(a), cy + 27.5 * s * math.sin(a), 2 * s), fill=0)
    return f


def s_ground(cy, rough=3, seed=5):
    rng = np.random.RandomState(seed)

    def f(d):
        seq = [(0, 100), (0, cy)]
        for i in range(11):
            seq.append((i * 10, cy + (rng.rand() - 0.5) * rough))
        seq += [(100, cy), (100, 100)]
        d.polygon(pts(seq), fill=255)
    return f


def s_key(cx, cy, s, ang=-40):
    """an ornate key: a lobed bow, a shaft with a collar, the bit's teeth"""
    def f(d):
        bow = []
        for i in range(48):
            a = 2 * math.pi * i / 48
            r = 15 * s * (1 + 0.16 * math.cos(4 * a))
            bow.append((cx + r * math.cos(a), cy - 20 * s + r * math.sin(a)))
        d.polygon(pts(rot(bow, cx, cy, ang)), fill=255)
        shaft = [(cx - 3.2 * s, cy - 8 * s), (cx + 3.2 * s, cy - 8 * s), (cx + 3.2 * s, cy + 34 * s), (cx - 3.2 * s, cy + 34 * s)]
        d.polygon(pts(rot(shaft, cx, cy, ang)), fill=255)
        collar = [(cx - 6.5 * s, cy - 2 * s), (cx + 6.5 * s, cy - 2 * s), (cx + 6.5 * s, cy + 3 * s), (cx - 6.5 * s, cy + 3 * s)]
        d.polygon(pts(rot(collar, cx, cy, ang)), fill=255)
        for y0, w in ((22, 11), (29, 8)):
            tooth = [(cx + 2 * s, cy + y0 * s), (cx + w * s, cy + y0 * s), (cx + w * s, cy + (y0 + 4.5) * s), (cx + 2 * s, cy + (y0 + 4.5) * s)]
            d.polygon(pts(rot(tooth, cx, cy, ang)), fill=255)
        hole = [(cx + 7.5 * s * math.cos(2 * math.pi * i / 24), cy - 20 * s + 7.5 * s * math.sin(2 * math.pi * i / 24)) for i in range(24)]
        d.polygon(pts(rot(hole, cx, cy, ang)), fill=0)
    return f


def key_center(cx, cy, s, ang):
    return rot([(cx, cy - 20 * s)], cx, cy, ang)[0]


# ---------------------------------------------------------------- plates
def plate(side, seed=1, round_=False):
    """The shared frame: a dark painted plate, an inner light of the side's colour, an iron and gold rim."""
    tint, ramp = SIDE.get(side, SIDE["neutral"])
    ic = Icon(seed)
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
    r = np.sqrt(((xx - W / 2) / (W * 0.5)) ** 2 + ((yy - W * 0.46) / (W * 0.5)) ** 2)
    g = _grain(seed + 40)
    bg = np.array((10, 8, 12), np.float32) + np.array(tint, np.float32)[None, None, :] * (np.clip(1 - r, 0, 1) ** 1.3 * 0.75 + (g - 0.5) * 0.08)[..., None]
    if round_:
        m = mask(lambda d: d.ellipse([6, 6, W - 7, W - 7], fill=255))
    else:
        m = mask(lambda d: d.rounded_rectangle([6, 6, W - 7, W - 7], radius=26, fill=255))
    ic.over(np.clip(bg, 0, 255), np.asarray(m.filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255)
    return ic, m


def rim(ic, side, round_=False):
    tint, ramp = SIDE.get(side, SIDE["neutral"])
    if round_:
        outer = lambda d: (d.ellipse([3, 3, W - 4, W - 4], fill=255), d.ellipse([12, 12, W - 13, W - 13], fill=0))
    else:
        outer = lambda d: (d.rounded_rectangle([3, 3, W - 4, W - 4], radius=28, fill=255),
                           d.rounded_rectangle([11, 11, W - 12, W - 12], radius=22, fill=0))
    ic.paint(outer, IRON, gloss=0.3, outline=1.2, soft=3)
    if round_:
        inner = lambda d: (d.ellipse([10, 10, W - 11, W - 11], fill=255), d.ellipse([13, 13, W - 14, W - 14], fill=0))
    else:
        inner = lambda d: (d.rounded_rectangle([9, 9, W - 10, W - 10], radius=23, fill=255),
                           d.rounded_rectangle([12, 12, W - 13, W - 13], radius=21, fill=0))
    ic.paint(inner, ramp, gloss=0.5, outline=0, soft=1.5, base=0.25)
    if not round_:
        for x, y in ((12, 12), (W - 13, 12), (12, W - 13), (W - 13, W - 13)):
            ic.paint(lambda d, x=x, y=y: d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=255), GOLD, gloss=0.7, outline=1, soft=2)


def clip_inside(ic, m):
    a = np.asarray(m.filter(ImageFilter.MinFilter(7))).astype(np.float32) / 255
    ic.a[..., 3] *= 1.0  # the plate stays; motifs are clipped below
    return a


class Framed:
    """plate + motif layer (clipped to the plate) + rim; badge on top"""

    def __init__(self, side="neutral", seed=1, round_=False):
        self.side, self.round = side, round_
        self.base, self.m = plate(side, seed, round_)
        self.ic = Icon(seed + 100)

    def done(self, badge=None):
        clip = np.asarray(self.m.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.GaussianBlur(1))).astype(np.float32) / 255
        mot = self.ic.a.copy()
        mot[..., 3] *= clip
        self.base.over(mot[..., :3], mot[..., 3])
        rim(self.base, self.side, self.round)
        if badge:
            draw_badge(self.base, badge, self.side)
        return self.base.image()


def draw_badge(ic, kind, side):
    tint, ramp = SIDE.get(side, SIDE["neutral"])
    cx, cy, r = 80, 80, 13
    ic.paint(s_circle(cx, cy, r), IRON, gloss=0.4, outline=2, soft=3)
    ic.flat(s_circle(cx, cy, r - 3), tuple(int(c * 0.6) for c in tint), 1.0)
    white = (255, 240, 220)
    if kind == "plus":
        ic.flat(lambda d: (d.rectangle(box(cx, cy, 7, 2), fill=255), d.rectangle(box(cx, cy, 2, 7), fill=255)), white)
    elif kind in ("up", "down"):
        sg = -1 if kind == "up" else 1
        ic.flat(lambda d: (d.polygon(pts([(cx, cy + sg * 8), (cx - 7, cy - sg * 0), (cx + 7, cy - sg * 0)]), fill=255),
                           d.rectangle([P(cx - 2.2), P(min(cy, cy - sg * 7)), P(cx + 2.2), P(max(cy, cy - sg * 7))], fill=255)), white)
    elif kind == "no":
        ic.flat(lambda d: d.line(pts([(cx - 7, cy + 7), (cx + 7, cy - 7)]), fill=255, width=int(P(4))), white)


def finish(img, size=OUT):
    """the 192 px drawing at `size`, lightly sharpened"""
    out = img.resize((size, size), Image.LANCZOS)
    return out.filter(ImageFilter.UnsharpMask(radius=1, percent=55, threshold=2))


# ---------------------------------------------------------------- small painted props
def orb(ic, cx, cy, r, ramp):
    ic.glow(s_circle(cx, cy, r * 1.3), ramp[3], r * 0.8, 0.6)
    ic.paint(s_circle(cx, cy, r), ramp, gloss=0.9, outline=1.5, soft=r * 0.9, base=0.2)
    ic.flat(s_circle(cx - r * 0.35, cy - r * 0.38, r * 0.22), (255, 255, 255), 0.75, blur=1.2)


def soul(ic, cx, cy, s, ramp=SOUL, lit=True):
    if lit:
        ic.glow(s_flame(cx, cy, s * 1.1), ramp[3], 10 * s, 0.9)
    ic.paint(s_flame(cx, cy, s), ramp, gloss=0.6, base=0.35 if lit else 0.05)


def element(ic, el, cx, cy, s):
    if el == "fire":
        ic.glow(s_flame(cx, cy, s), (255, 140, 40), 8 * s, 0.9)
        ic.paint(s_flame(cx, cy, s), FIRE, gloss=0.5, base=0.3)
    elif el == "ice":
        ic.glow(s_flake(cx, cy, s), (120, 200, 255), 7 * s, 0.8)
        ic.paint(s_flake(cx, cy, s), ICE, gloss=0.5, base=0.35, soft=2)
    elif el == "storm":
        ic.glow(s_bolt(cx, cy, s), (150, 170, 255), 8 * s, 1.0)
        ic.paint(s_bolt(cx, cy, s), STORM, gloss=0.6, base=0.35)


def monster(ic, cx, cy, s, ramp=FLESH, eye=(255, 60, 30)):
    s *= 1.12
    ic.paint(s_head(cx, cy, s), ramp, gloss=0.3)
    head_eyes(ic, cx, cy, s, eye)


def guardian_helm(ic, cx, cy, s, ramp=IRON, eye=(255, 50, 30)):
    ic.paint(s_helm(cx, cy, s), ramp, gloss=0.55)
    helm_eyes(ic, cx, cy, s, eye)


def chest(ic, cx, cy, s, open_=True, spill=True):
    if open_:
        ic.glow(lambda d: d.ellipse(box(cx, cy - 10 * s, 26 * s, 16 * s), fill=255), (255, 200, 90), 14 * s, 1.0)
        ic.paint(lambda d: d.polygon(pts([(cx - 28 * s, cy - 6 * s), (cx + 28 * s, cy - 6 * s), (cx + 24 * s, cy - 28 * s), (cx - 24 * s, cy - 28 * s)]), fill=255), WOOD, gloss=0.2)
        ic.paint(lambda d: d.rectangle(box(cx, cy - 27 * s, 25 * s, 2.5 * s), fill=255), GOLD, gloss=0.6, soft=2)
        for i, (ox, rmp) in enumerate(((-12, VOID), (2, FIRE), (14, ICE))):
            orb(ic, cx + ox * s, cy - 8 * s - (i % 2) * 3 * s, 6.5 * s, rmp)
    body = lambda d: d.rounded_rectangle(box(cx, cy + 8 * s, 28 * s, 15 * s), radius=P(3 * s), fill=255)
    ic.paint(body, WOOD, gloss=0.25)
    for bx in (-18, 18):
        ic.paint(lambda d, bx=bx: d.rectangle(box(cx + bx * s, cy + 8 * s, 3.2 * s, 15 * s), fill=255), GOLD, gloss=0.7, soft=2)
    ic.paint(lambda d: d.rectangle(box(cx, cy - 5 * s, 28 * s, 2.6 * s), fill=255), GOLD, gloss=0.7, soft=2)
    ic.paint(lambda d: d.rounded_rectangle(box(cx, cy + 4 * s, 5 * s, 6 * s), radius=P(1.5 * s), fill=255), GOLD, gloss=0.8, soft=2)
    if not open_:
        ic.paint(lambda d: d.polygon(pts([(cx - 28 * s, cy - 6 * s), (cx + 28 * s, cy - 6 * s), (cx + 24 * s, cy - 18 * s), (cx - 24 * s, cy - 18 * s)]), fill=255), WOOD, gloss=0.2)
        ic.paint(lambda d: d.rectangle(box(cx, cy - 12 * s, 26 * s, 2.4 * s), fill=255), GOLD, gloss=0.6, soft=2)
    if spill:
        orb(ic, cx - 20 * s, cy + 26 * s, 6 * s, BLOOD)
        orb(ic, cx + 22 * s, cy + 25 * s, 5.5 * s, POISON)
        ic.paint(s_coins(cx + 2 * s, cy + 30 * s, 0.45 * s, 2), GOLD, gloss=0.8, soft=2)


# ---------------------------------------------------------------- rift modifiers
def _head_pack(ic, spots, s, ramp=FLESH):
    for (x, y) in spots:
        monster(ic, x, y, s, ramp)


def mod_motif(key, f):
    ic = f.ic
    if key == "vitality":
        monster(ic, 44, 46, 0.95)
        ic.glow(s_heart(66, 66, 0.55), (255, 60, 50), 6, 0.8)
        ic.paint(s_heart(66, 66, 0.55), BLOOD, gloss=0.8, base=0.25)
        return "plus"
    if key == "brutality":
        monster(ic, 40, 46, 0.85)
        ic.glow(s_claws(62, 54, 0.75), (255, 40, 30), 6, 0.7)
        ic.paint(s_claws(62, 54, 0.75), BLOOD, gloss=0.5, base=0.3)
        return "up"
    if key == "haste":
        for i, y in enumerate((36, 50, 64)):
            ic.paint(lambda d, y=y, i=i: d.polygon(pts([(14 + i * 4, y), (44, y - 2.4), (46, y), (44, y + 2.4)]), fill=255), SILVER, gloss=0.4, soft=2)
        monster(ic, 62, 50, 0.8)
        return "up"
    if key == "elites":
        monster(ic, 50, 60, 0.8, eye=(255, 200, 60))
        ic.glow(s_crown(50, 24, 0.55), (255, 200, 80), 8, 0.7)
        ic.paint(s_crown(50, 24, 0.55), GOLD, gloss=0.9)
        return "plus"
    if key == "reflection":
        ic.glow(s_shard(52, 50, 0.95), (200, 210, 255), 8, 0.5)
        ic.paint(s_shard(52, 50, 0.95), SILVER, gloss=1.0, base=0.3)
        ic.paint(lambda d: d.polygon(pts([(12, 24), (40, 44), (36, 47), (12, 30)]), fill=255), BLOOD, gloss=0.4, soft=2)
        ic.paint(lambda d: d.polygon(pts([(48, 52), (84, 76), (80, 82), (46, 58)]), fill=255), BLOOD, gloss=0.4, soft=2)
        ic.paint(lambda d: d.polygon(pts([(88, 86), (74, 84), (82, 74)]), fill=255), BLOOD, gloss=0.4, soft=2)
        return None
    if key == "warding":
        ic.paint(s_shield(50, 50, 0.95), VOID, gloss=0.6)
        ic.flat(s_sigil(50, 48, 0.55), (230, 210, 255), 0.55)
        element(ic, "fire", 28, 24, 0.32)
        element(ic, "ice", 72, 24, 0.36)
        element(ic, "storm", 50, 80, 0.34)
        return None
    if key == "withering":
        ic.paint(s_heart(50, 52, 0.95), ROT, gloss=0.2)
        ic.flat(lambda d: d.line(pts([(46, 32), (54, 46), (44, 56), (52, 70)]), fill=255, width=int(P(2.5))), (20, 14, 16), 0.9)
        return "no"
    if key == "swarm":
        _head_pack(ic, [(30, 62), (70, 62), (50, 38)], 0.55)
        return "plus"
    if key == "teeming":
        _head_pack(ic, [(24, 40), (50, 36), (76, 40), (36, 70), (64, 70)], 0.42)
        return "up"
    if key == "gilded":
        ic.paint(s_bag(52, 52, 0.85), WOOD, gloss=0.3)
        for (x, y, sc) in ((26, 78, 0.5), (76, 80, 0.45)):
            ic.paint(s_coins(x, y, sc, 2), GOLD, gloss=0.9, soft=2)
        ic.glow(s_star(72, 26, 9), (255, 220, 120), 6, 0.9)
        ic.paint(s_star(72, 26, 9), GOLD, gloss=1.0, soft=2)
        ic.flat(lambda d: [d.ellipse(box(44 + sx * 7, 54, 2.4), fill=255) for sx in (-1, 1)], (255, 220, 80), 0.95)
        return None
    if key == "warband":
        ic.paint(lambda d: d.rectangle(box(22, 52, 2, 40), fill=255), WOOD, gloss=0.3, soft=2)
        ic.paint(s_banner(54, 50, 0.85), BLOOD, gloss=0.3)
        ic.paint(s_skull(54, 46, 0.48), BONE, gloss=0.5)
        return None
    if key == "coffer":
        chest(ic, 50, 54, 0.95, open_=False, spill=False)
        for (a, b) in (((18, 30), (82, 78)), ((82, 30), (18, 78))):
            ic.paint(lambda d, a=a, b=b: d.line(pts([a, b]), fill=255, width=int(P(4))), IRON, gloss=0.5, soft=2)
        ic.paint(s_circle(50, 54, 8), BLOOD, gloss=0.7)
        return None
    if key == "twin":
        guardian_helm(ic, 32, 54, 0.62)
        guardian_helm(ic, 68, 54, 0.62)
        return None
    if key == "echo":
        ic.paint(s_coins(38, 66, 0.9, 4), GOLD, gloss=0.9)
        ic.paint(s_coins(64, 52, 0.75, 3), GOLD, gloss=0.9, opacity=0.55)
        for r in (34, 40):
            ic.flat(s_ring(62, 46, r, 1.4), (255, 220, 140), 0.35)
        return None
    if key == "cinder":
        ic.glow(s_star(50, 50, 40, 0.45, 8, -90), (255, 120, 30), 10, 1.0)
        ic.paint(s_star(50, 50, 38, 0.5, 8, -90), FIRE, gloss=0.4, base=0.35)
        ic.paint(s_skull(50, 52, 0.72), BONE, gloss=0.5)
        return None
    if key == "blight":
        ic.paint(s_cross(50, 48, 0.95), ROT, gloss=0.3)
        ic.flat(lambda d: d.line(pts([(40, 26), (52, 44), (44, 54), (58, 72)]), fill=255, width=int(P(2.4))), (18, 14, 10), 0.9)
        for x, y in ((34, 76), (62, 82)):
            ic.paint(s_drop(x, y, 0.22), POISON, gloss=0.6, soft=2)
        return "down"
    if key == "waning":
        portal(ic, 68, 48, 0.55, 9)
        ic.paint(s_glass(40, 50, 1.0), SILVER, gloss=0.8, opacity=0.8)
        ic.paint(lambda d: d.polygon(pts([(32, 64), (48, 64), (40, 56)]), fill=255), GOLD, gloss=0.6, soft=2)
        ic.paint(s_hourglass(40, 50, 1.0), WOOD, gloss=0.5)
        return "down"
    if key == "dread":
        guardian_helm(ic, 50, 54, 0.95)
        return "up"
    if key == "fragile":
        soul(ic, 26, 56, 0.55)
        soul(ic, 50, 52, 0.62)
        soul(ic, 74, 56, 0.55, ASH, lit=False)
        ic.flat(lambda d: d.line(pts([(68, 46), (78, 58), (70, 70)]), fill=255, width=int(P(2))), (10, 8, 10), 0.9)
        return "down"
    if key in ("emberbrand", "frostbrand", "stormbrand"):
        el, rmp, glw = {"emberbrand": ("fire", FIRE, (255, 120, 30)), "frostbrand": ("ice", ICE, (120, 200, 255)),
                        "stormbrand": ("storm", STORM, (150, 170, 255))}[key]
        ic.glow(s_claws(44, 52, 0.85), glw, 8, 0.9)
        ic.paint(s_claws(44, 52, 0.85), rmp, gloss=0.6, base=0.3)
        element(ic, el, 74, 28, 0.55)
        return None
    if key == "keen":
        ic.paint(s_fang(46, 52, 1.0), BONE, gloss=0.7)
        ic.glow(s_star(70, 30, 14, 0.3, 4, -45), (255, 230, 120), 8, 1.0)
        ic.paint(s_star(70, 30, 13, 0.3, 4, -45), GOLD, gloss=1.0, soft=2)
        return None
    if key == "ironhide":
        ic.paint(s_shield(50, 48, 0.95), IRON, gloss=0.7)
        for x, y in ((34, 34), (66, 34), (34, 58), (66, 58), (50, 74)):
            ic.paint(s_circle(x, y, 3.4), SILVER, gloss=0.9, soft=1.5)
        ic.flat(lambda d: (d.line(pts([(26, 46), (74, 46)]), fill=255, width=int(P(1.6))), d.line(pts([(50, 24), (50, 78)]), fill=255, width=int(P(1.6)))), (16, 14, 18), 0.7)
        ic.paint(s_sword(78, 80, 0.42, -135, broken=True), SILVER, gloss=0.6, soft=2)
        return None
    if key == "festering":
        ic.paint(s_claws(46, 46, 0.8), POISON, gloss=0.5, base=0.25)
        for x, y, sc in ((30, 80, 0.2), (50, 84, 0.25), (68, 78, 0.18)):
            ic.glow(s_drop(x, y, sc), (120, 230, 60), 4, 0.6)
            ic.paint(s_drop(x, y, sc), POISON, gloss=0.7, soft=2)
        return None
    if key == "spiteglass":
        ic.glow(s_shard(50, 52, 0.85, 20), (180, 120, 255), 8, 0.7)
        ic.paint(s_shard(50, 52, 0.85, 20), VOID, gloss=1.0, base=0.35)
        element(ic, "fire", 22, 30, 0.28)
        element(ic, "ice", 80, 40, 0.3)
        element(ic, "storm", 28, 78, 0.28)
        return None
    if key == "brood":
        for x, y in ((30, 64), (70, 64)):
            ic.paint(s_egg(x, y, 0.85), FLESH, gloss=0.5)
        ic.paint(s_egg(50, 48, 1.1), FLESH, gloss=0.5)
        ic.flat(lambda d: d.polygon(pts([(42, 40), (48, 46), (52, 38), (58, 46)]), fill=255), (12, 8, 14), 0.95, blur=0.4)
        ic.glow(s_circle(50, 50, 4), (255, 80, 40), 6, 1.2)
        ic.flat(s_circle(50, 50, 2.5), (255, 200, 140), 1.0)
        return None
    if key == "wrath":
        ic.glow(s_ring(50, 52, 42, 6), (255, 110, 30), 6, 1.0)
        ic.paint(s_ring(50, 52, 40, 4), FIRE, gloss=0.6, soft=2, base=0.4)
        guardian_helm(ic, 50, 54, 0.62)
        return None
    if key == "breach":
        portal(ic, 50, 40, 0.7, 4)
        _head_pack(ic, [(24, 70), (76, 70)], 0.4)
        return "plus"
    if key in ("searing", "flaying", "sapping"):
        ic.glow(s_sigil(50, 50, 1.2), (170, 80, 255), 6, 0.8)
        ic.paint(s_sigil(50, 50, 1.2), VOID, gloss=0.4, soft=2, base=0.35)
        if key == "searing":
            element(ic, "fire", 38, 56, 0.3)
            element(ic, "ice", 62, 56, 0.32)
            element(ic, "storm", 50, 38, 0.3)
            return "up"
        if key == "flaying":
            ic.paint(s_claws(50, 52, 0.5), BLOOD, gloss=0.5)
            return "up"
        ic.paint(s_sword(50, 50, 0.6, 180, broken=True), SILVER, gloss=0.6)
        return "down"
    if key == "parched":
        ic.glow(s_drop(50, 50, 1.0), (90, 130, 255), 8, 0.6)
        ic.paint(s_drop(50, 50, 1.0), MANA, gloss=0.8, base=0.2)
        ic.flat(lambda d: d.line(pts([(46, 30), (54, 48), (44, 58), (52, 74)]), fill=255, width=int(P(2.4))), (10, 14, 40), 0.9)
        return "no"
    if key == "scorched":
        ic.paint(s_ground(68, 6, 2), OBSID, gloss=0.2)
        ic.glow(lambda d: d.rectangle(box(50, 70, 50, 6), fill=255), (255, 100, 20), 8, 0.9)
        for x, sc in ((24, 0.6), (50, 0.85), (76, 0.6)):
            element(ic, "fire", x, 60 - sc * 14, sc)
        return None
    if key == "rimefloor":
        ic.paint(s_ground(70, 4, 3), ICE, gloss=0.6, base=0.25)
        for x, y, sc in ((28, 54, 0.6), (52, 46, 0.85), (74, 56, 0.55)):
            ic.glow(s_shard(x, y, sc, (x - 50) * 0.4), (150, 210, 255), 6, 0.6)
            ic.paint(s_shard(x, y, sc, (x - 50) * 0.4), ICE, gloss=1.0, base=0.3)
        return None
    if key == "veilstorm":
        ic.flat(lambda d: d.ellipse(box(50, 80, 26, 7), fill=255), (220, 40, 30), 0.5)
        ic.flat(s_ring(50, 80, 26, 1.6), (255, 90, 60), 0.9)
        ic.glow(s_bolt(50, 58, 0.8), (160, 170, 255), 10, 1.0)
        ic.paint(s_bolt(50, 58, 0.8), STORM, gloss=0.7, base=0.4)
        ic.paint(s_cloud(50, 24, 1.1), ASH, gloss=0.2)
        return None
    return None


def draw_mod(side, key):
    side = side if side in SIDE else "neutral"
    f = Framed(side, seed=sum(map(ord, key)))
    badge = mod_motif(key, f)
    if not f.ic.a[..., 3].any():
        # an unknown modifier: the side's generic motif
        if side == "prefix":
            monster(f.ic, 50, 52, 0.95)
            badge = "up"
        elif side == "suffix":
            f.ic.paint(s_sigil(50, 50, 1.2), VOID, gloss=0.4, soft=2)
        else:
            chest(f.ic, 50, 52, 0.9)
    return f.done(badge)


# ---------------------------------------------------------------- keys, chest, portal, atlas, lives
TIER_BANDS = [  # gem ramp, metal ramp, glow
    (ICE, IRON, (110, 180, 255)), (POISON, IRON, (110, 230, 80)), (VOID, GOLD, (180, 110, 255)),
    (FIRE, GOLD, (255, 160, 50)), (BLOOD, GOLD, (255, 60, 40))]


def draw_key(tier, omen=False):
    f = Framed("neutral", seed=200 + tier)
    ic = f.ic
    tier = max(1, int(tier))
    band = min(len(TIER_BANDS) - 1, (tier - 1) // 3)
    gem, metal, glw = TIER_BANDS[band]
    if omen:
        gem, metal, glw = VOID, OBSID, (190, 110, 255)
    cx, cy, s, ang = 52, 54, 1.05, -40
    ic.glow(s_key(cx, cy, s, ang), glw, 10, 0.55)
    ic.paint(s_key(cx, cy, s, ang), metal, gloss=0.7)
    # runes along the shaft
    for t in (6, 12, 18):
        p = rot([(cx, cy + t * s)], cx, cy, ang)[0]
        ic.glow(s_circle(p[0], p[1], 1.6), glw, 2.5, 1.0)
    gx, gy = key_center(cx, cy, s, ang)
    ic.glow(s_circle(gx, gy, 9), glw, 8, 1.0)
    ic.paint(s_circle(gx, gy, 7), gem, gloss=1.0, soft=4, base=0.3)
    if omen:
        ic.flat(lambda d: d.ellipse(box(gx, gy, 4.5, 2.2), fill=255), (16, 4, 24), 0.9)
        ic.flat(s_circle(gx, gy, 1.4), (255, 200, 255), 1.0)
    else:
        n = (tier - 1) % 3 + 1
        for i in range(n):
            px = 18 + i * 9
            ic.glow(s_circle(px, 84, 3.6), glw, 4, 0.9)
            ic.paint(s_circle(px, 84, 3.2), gem, gloss=1.0, soft=2, base=0.4)
    return f.done()


def draw_chest():
    f = Framed("boon", seed=301)
    chest(f.ic, 50, 50, 1.0)
    return f.done()


def portal(ic, cx, cy, s, seed=4, rgb=(170, 100, 255), ramp=VOID):
    """a torn rift: cracks in the world, a glowing torn rim, the dark beyond with its stars"""
    rng = np.random.RandomState(seed + 30)
    for k in range(7):
        a = math.radians(rng.rand() * 360)
        x0, y0 = cx + 14 * s * math.cos(a), cy + 30 * s * math.sin(a)
        seq = [(x0, y0)]
        for _ in range(3):
            a += (rng.rand() - 0.5) * 0.9
            x0, y0 = x0 + 8 * s * math.cos(a), y0 + 8 * s * math.sin(a)
            seq.append((x0, y0))
        ic.glow(lambda d, seq=seq: d.line(pts(seq), fill=255, width=max(1, int(P(1.4 * s)))), rgb, 3 * s, 0.9)
    ic.glow(s_tear(cx, cy, s * 1.3, seed), rgb, 18 * s, 1.0)
    m = mask(s_tear(cx, cy, s, seed))
    mf = np.asarray(m.filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255
    ol = np.asarray(m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255
    ic.over(np.array(ramp[4], np.float32), ol)
    ic.over(np.array((8, 2, 16), np.float32), mf)
    edge = np.clip(mf - np.asarray(m.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255, 0, 1)
    ic.add(rgb, edge * 1.4)
    ic.add((255, 235, 255), edge ** 2 * 0.9)
    for _ in range(int(10 * s) + 3):
        x, y = cx + (rng.rand() - 0.5) * 14 * s, cy + (rng.rand() - 0.5) * 50 * s
        ic.add((230, 210, 255), np.asarray(mask(s_circle(x, y, 0.5 + rng.rand() * 0.8)).filter(ImageFilter.GaussianBlur(0.7))).astype(np.float32) / 255 * mf)


def draw_portal():
    f = Framed("suffix", seed=401)
    ic = f.ic
    ic.paint(s_ground(78, 5, 7), OBSID, gloss=0.2)
    rng = np.random.RandomState(12)
    portal(ic, 50, 46, 0.95)
    for i in range(7):
        x, y, r = 14 + rng.rand() * 72, 14 + rng.rand() * 56, 2 + rng.rand() * 3.5
        if abs(x - 50) < 14:
            x += 24 if x > 50 else -24
        ic.paint(lambda d, x=x, y=y, r=r: d.polygon(pts([(x - r, y), (x, y - r * 1.2), (x + r, y - r * 0.2), (x + r * 0.4, y + r)]), fill=255), OBSID, gloss=0.6, soft=2, base=0.3)
    return f.done()


def starfield(ic, seed, tint, n=40):
    rng = np.random.RandomState(seed)
    for _ in range(n):
        x, y, r = 12 + rng.rand() * 76, 12 + rng.rand() * 76, 0.5 + rng.rand() * 0.9
        ic.add(tuple(int(160 + c * 0.35) for c in tint), np.asarray(mask(s_circle(x, y, r)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255 * (0.4 + rng.rand() * 0.6))


def constellation(ic, nodes, links, tint):
    for a, b in links:
        ic.glow(lambda d, a=a, b=b: d.line(pts([nodes[a], nodes[b]]), fill=255, width=int(P(2))), (255, 200, 110), 3, 0.5)
        ic.flat(lambda d, a=a, b=b: d.line(pts([nodes[a], nodes[b]]), fill=255, width=int(P(1.4))), (250, 220, 160), 0.85)
    for i, (x, y) in enumerate(nodes):
        r = 4.4 if i == 0 else 3.2
        ic.glow(s_circle(x, y, r * 2.2), tint, r * 2, 1.0)
        ic.paint(s_circle(x, y, r), GOLD, gloss=1.0, soft=1.5, base=0.5)


def draw_atlas():
    f = Framed("neutral", seed=501, round_=True)
    ic = f.ic
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
    r = np.sqrt((xx - W / 2) ** 2 + (yy - W / 2) ** 2) / (W / 2)
    ic.add((60, 70, 160), np.clip(1 - r, 0, 1) ** 1.5 * 0.6)
    starfield(ic, 3, THEME["core"], 60)
    nodes = [(50, 50), (30, 30), (70, 28), (76, 62), (56, 78), (26, 66), (40, 46)]
    constellation(ic, nodes, [(0, 6), (6, 1), (0, 2), (0, 3), (3, 4), (6, 5), (1, 2)], (255, 210, 120))
    ic.paint(s_star(50, 50, 12, 0.3, 4, -90), GOLD, gloss=1.0, soft=2)
    return f.done()


def draw_lives():
    f = Framed("neutral", seed=601)
    ic = f.ic
    for x, sc in ((26, 0.5), (50, 0.62), (74, 0.5)):
        ic.paint(lambda d, x=x: d.rounded_rectangle(box(x, 76, 9, 4), radius=6, fill=255), IRON, gloss=0.5, soft=2)
        soul(ic, x, 56, sc)
    return f.done()


# ---------------------------------------------------------------- omens
def omen_motif(ic, kind):
    if kind == "bloodmoon":
        ic.glow(s_circle(50, 44, 32), (255, 40, 30), 14, 0.9)
        ic.paint(s_circle(50, 44, 28), BLOOD, gloss=0.3, soft=14, base=0.25)
        for x, y, r in ((40, 36, 5), (60, 50, 4), (54, 30, 3)):
            ic.flat(s_circle(x, y, r), (90, 10, 10), 0.5, blur=2)
        ic.paint(lambda d: d.polygon(pts([(14, 92), (30, 64), (40, 70), (50, 52), (60, 70), (70, 64), (86, 92)]), fill=255), OBSID, gloss=0.2)
        ic.paint(lambda d: d.polygon(pts([(38, 60), (30, 46), (44, 56)]), fill=255), BONE, gloss=0.5, soft=2)
        ic.paint(lambda d: d.polygon(pts([(62, 60), (70, 46), (56, 56)]), fill=255), BONE, gloss=0.5, soft=2)
    elif kind == "hollow":
        ic.glow(s_ring(50, 54, 26, 10), (150, 90, 255), 10, 0.8)
        ic.flat(s_circle(50, 56, 20), (4, 2, 8), 0.95, blur=3)
        ic.paint(s_crown(50, 42, 0.95), OBSID, gloss=0.8, base=0.2)
        for x in (-28, 0, 28):
            ic.glow(s_circle(50 + x * 0.95, 42 - (22 if x == 0 else 16) * 0.95, 3), (180, 120, 255), 5, 1.2)
        ic.flat(lambda d: d.polygon(pts([(36, 60), (64, 60), (60, 86), (40, 86)]), fill=255), (0, 0, 0), 0.6, blur=4)
    else:  # storm
        ic.paint(s_cloud(50, 26, 1.25), STORM[:3] + [(90, 100, 170), (150, 160, 220)], gloss=0.2)
        ic.glow(lambda d: d.ellipse(box(50, 58, 22, 13), fill=255), (140, 170, 255), 10, 1.0)
        ic.paint(lambda d: d.ellipse(box(50, 58, 22, 12), fill=255), STORM, gloss=0.5, base=0.4)
        ic.flat(s_circle(50, 58, 9), (250, 250, 255), 1.0)
        ic.flat(lambda d: d.ellipse(box(50, 58, 3, 8), fill=255), (10, 10, 40), 1.0)
        for x in (24, 76):
            ic.glow(s_bolt(x, 76, 0.35), (160, 180, 255), 6, 1.0)
            ic.paint(s_bolt(x, 76, 0.35), STORM, gloss=0.6, soft=2)


def draw_omen(kind, asc=False):
    f = Framed("boon" if asc else "suffix", seed=700 + len(kind))
    omen_motif(f.ic, kind)
    if asc:
        f.ic.glow(s_crown(50, 14, 0.3), (255, 210, 100), 5, 0.8)
        f.ic.paint(s_crown(50, 14, 0.3), GOLD, gloss=1.0, soft=2)
    return f.done()


def draw_ascended():
    f = Framed("boon", seed=801)
    ic = f.ic
    for k, (x, y) in zip(("bloodmoon", "hollow", "storm"), ((26, 62), (50, 30), (74, 62))):
        sub = Icon(900 + x)
        omen_motif(sub, k)
        img = Image.fromarray(np.clip(np.dstack([sub.a[..., :3], sub.a[..., 3:] * 255]), 0, 255).astype(np.uint8), "RGBA")
        img = img.resize((int(P(42)), int(P(42))), Image.LANCZOS)
        layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        layer.alpha_composite(img, (int(P(x - 21)), int(P(y - 21))))
        a = np.asarray(layer).astype(np.float32)
        ic.over(a[..., :3], a[..., 3] / 255)
    ic.glow(s_flame(50, 66, 0.55), (255, 190, 80), 8, 1.0)
    ic.paint(s_flame(50, 66, 0.5), FIRE, gloss=0.6, base=0.4)
    return f.done()


def draw_fragment():
    f = Framed("suffix", seed=811)
    ic = f.ic
    ic.glow(s_shard(50, 50, 0.85, 25), (180, 110, 255), 12, 1.0)
    ic.paint(s_shard(50, 50, 0.85, 25), VOID, gloss=1.0, base=0.4)
    ic.flat(lambda d: d.ellipse(box(50, 50, 6, 3), fill=255), (16, 4, 24), 0.9)
    ic.flat(s_circle(50, 50, 1.6), (255, 220, 255), 1.0)
    for x, y in ((24, 74), (78, 28), (70, 80)):
        ic.paint(s_shard(x, y, 0.18, x), VOID, gloss=1.0, soft=2, base=0.4)
    return f.done()


# ---------------------------------------------------------------- theme vignettes
def sky(ic, top, bottom, seed):
    yy = np.mgrid[0:W, 0:W][0].astype(np.float32) / W
    g = _grain(seed)
    col = np.array(top, np.float32) * (1 - yy[..., None]) + np.array(bottom, np.float32) * yy[..., None]
    col *= (0.85 + 0.3 * g)[..., None]
    ic.over(np.clip(col, 0, 255), np.ones((W, W), np.float32))


def vignette(ic, theme):
    if theme == "abyss":
        sky(ic, (10, 4, 22), (54, 22, 90), 11)
        starfield(ic, 5, THEME["abyss"], 30)
        portal(ic, 64, 34, 0.42, 6)
        for x, y, r in ((22, 30, 7), (40, 50, 4), (82, 58, 5)):
            ic.paint(lambda d, x=x, y=y, r=r: d.polygon(pts([(x - r, y), (x - r * 0.4, y - r * 0.8), (x + r, y - r * 0.4), (x + r * 0.5, y + r * 1.4), (x, y + r * 2)]), fill=255), OBSID, gloss=0.4, soft=2, base=0.3)
        ic.paint(s_ground(74, 8, 21), VOID[:2] + [(60, 40, 80), (90, 70, 110), (130, 110, 150)], gloss=0.2)
    elif theme == "hall":
        sky(ic, (8, 4, 4), (96, 30, 10), 13)
        ic.glow(lambda d: d.ellipse(box(50, 92, 60, 22), fill=255), (255, 90, 20), 14, 0.8)
        for x in (18, 40, 62, 84):
            ic.paint(lambda d, x=x: d.rectangle(box(x, 44, 6, 40), fill=255), OBSID, gloss=0.6)
            ic.glow(lambda d, x=x: d.rectangle(box(x + 4, 50, 1.2, 30), fill=255), (255, 120, 40), 3, 0.5)
            ic.paint(lambda d, x=x: d.rectangle(box(x, 8, 9, 3), fill=255), OBSID, gloss=0.6, soft=2)
        ic.paint(s_ground(80, 2, 3), OBSID, gloss=0.4)
        for seq in (((4, 88), (24, 84), (38, 92), (60, 86)), ((50, 96), (66, 88), (90, 92)), ((10, 96), (30, 90))):
            ic.glow(lambda d, seq=seq: d.line(pts(seq), fill=255, width=int(P(2))), (255, 110, 30), 4, 1.0)
            ic.flat(lambda d, seq=seq: d.line(pts(seq), fill=255, width=int(P(1))), (255, 220, 120), 1.0)
    elif theme == "crypt":
        sky(ic, (20, 16, 14), (70, 56, 42), 17)
        ic.flat(s_circle(74, 26, 9), (220, 200, 160), 0.5, blur=6)
        for x, y, w, h in ((22, 62, 8, 14), (48, 58, 10, 18), (76, 64, 7, 12)):
            ic.paint(lambda d, x=x, y=y, w=w, h=h: (d.rectangle(box(x, y + 3, w, h - 3), fill=255), d.ellipse(box(x, y - h + 6, w, w), fill=255)), ASH, gloss=0.3)
        ic.paint(s_cross(48, 26, 0.35), ASH, gloss=0.3, soft=2)
        ic.paint(s_ground(78, 5, 9), ASH[:3] + [(110, 92, 70), (150, 130, 100)], gloss=0.2)
        for x in (12, 90):
            ic.paint(lambda d, x=x: d.rectangle(box(x, 70, 2, 10), fill=255), IRON, gloss=0.4, soft=2)
            ic.glow(s_flame(x, 56, 0.3), (255, 140, 40), 6, 1.0)
            ic.paint(s_flame(x, 56, 0.28), FIRE, gloss=0.5, soft=2, base=0.4)
    else:  # sanctum
        sky(ic, (10, 20, 12), (44, 70, 30), 19)
        ic.paint(lambda d: (d.rectangle(box(28, 54, 6, 30), fill=255), d.rectangle(box(72, 54, 6, 30), fill=255)), GOLD[:1] + [(90, 70, 30), (140, 110, 50), (190, 160, 80), (230, 210, 140)], gloss=0.4)
        ic.paint(lambda d: (d.ellipse(box(50, 26, 28, 14), fill=255), d.ellipse(box(50, 30, 20, 10), fill=0)), GOLD[:1] + [(90, 70, 30), (140, 110, 50), (190, 160, 80), (230, 210, 140)], gloss=0.4, soft=3)
        for x, y, s in ((50, 66, 1.0), (16, 74, 0.6), (86, 72, 0.7)):
            ic.paint(lambda d, x=x, y=y, s=s: d.rectangle(box(x, y + 6 * s, 3 * s, 10 * s), fill=255), BONE, gloss=0.3, soft=2)
            ic.paint(lambda d, x=x, y=y, s=s: d.chord(box(x, y, 14 * s, 10 * s), 180, 360, fill=255), MOSS, gloss=0.5)
        ic.paint(s_ground(84, 4, 4), MOSS, gloss=0.2)
        starfield(ic, 9, (120, 230, 90), 18)


def draw_theme(theme):
    f = Framed("neutral", seed=1000 + len(theme))
    vignette(f.ic, theme)
    return f.done()


# ---------------------------------------------------------------- guardians and the pack (our rift looks)
CREATURE_CELLS = [  # name, source, frame size (the south-facing first frame: column 2, row 0)
    ("abyss", "big_bosses/abyss_guardian_big.png", 128), ("hall", "big_bosses/obsidian_guardian_big.png", 128),
    ("crypt", "big_bosses/crypt_guardian_big.png", 128), ("sanctum", "big_bosses/sanctum_guardian_big.png", 128),
    ("seer", "big_bosses/omen_seer_big.png", 128),
    ("pallid", "rift_variants/abyss_brute_pallid.png", 64), ("ashwalker", "rift_variants/crypt_minion_ashwalker.png", 64),
    ("thornrot", "rift_variants/sanctum_brute_thornrot.png", 64), ("runeshade", "rift_variants/abyss_elite_runeshade.png", 96),
]


def import_creatures():
    """Refresh the snapshot strip from the committed rift looks (one 128 px cell each)."""
    out = Image.new("RGBA", (128 * len(CREATURE_CELLS), 128), (0, 0, 0, 0))
    for i, (name, src, size) in enumerate(CREATURE_CELLS):
        im = Image.open(os.path.join(ART, src)).convert("RGBA")
        cell = im.crop((2 * size, 0, 3 * size, size))
        if size != 128:
            cell = cell.resize((128, 128), Image.NEAREST if 128 % size == 0 else Image.LANCZOS)
        out.alpha_composite(cell, (i * 128, 0))
    os.makedirs(os.path.dirname(CREATURES), exist_ok=True)
    out.save(CREATURES, optimize=True)
    return CREATURES


_STRIP = {}


def creature(name):
    if "strip" not in _STRIP:
        _STRIP["strip"] = Image.open(CREATURES).convert("RGBA")
    i = [c[0] for c in CREATURE_CELLS].index(name)
    cell = _STRIP["strip"].crop((i * 128, 0, i * 128 + 128, 128))
    box_ = cell.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    return cell.crop(box_)


def paste(ic, img, cx, cy, h):
    s = P(h) / img.height
    im = img.resize((max(1, int(img.width * s)), max(1, int(img.height * s))), Image.LANCZOS)
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    x, y = int(P(cx) - im.width / 2), int(P(cy) - im.height / 2)
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sh.putalpha(im.getchannel("A").filter(ImageFilter.GaussianBlur(4)))
    layer.alpha_composite(sh, (x + 3, y + 4))
    layer.alpha_composite(im, (x, y))
    a = np.asarray(layer).astype(np.float32)
    ic.over(a[..., :3], a[..., 3] / 255)


GUARDIAN_THEME = {"abyss": "abyss", "hall": "hall", "crypt": "crypt", "sanctum": "sanctum", "seer": "abyss"}


def draw_guardian(look):
    f = Framed("prefix", seed=1100 + len(look))
    ic = f.ic
    vignette(ic, GUARDIAN_THEME.get(look, "abyss"))
    ic.over(np.zeros((W, W, 3), np.float32), np.full((W, W), 0.35, np.float32))
    tint = THEME.get(GUARDIAN_THEME.get(look, "abyss"))
    ic.glow(s_circle(50, 52, 34), tint, 14, 0.6)
    paste(ic, creature(look), 50, 54, 82)
    return f.done()


def draw_clear():
    f = Framed("prefix", seed=1201)
    ic = f.ic
    portal(ic, 50, 34, 0.5, 8)
    ic.paint(s_ground(74, 4, 11), OBSID, gloss=0.2)
    for name, x, y, h in (("runeshade", 50, 50, 44), ("pallid", 24, 66, 30), ("ashwalker", 78, 66, 30), ("thornrot", 50, 72, 30)):
        paste(ic, creature(name), x, y, h)
    ic.flat(lambda d: d.arc(box(50, 50, 40), -90, 180, fill=255, width=int(P(3))), (255, 200, 90), 0.9)
    return f.done()


# ---------------------------------------------------------------- the atlas nodes
def atlas_motif(ic, glyph, branch, cx=50, cy=50, s=0.62):
    g = glyph
    if g.startswith("theme"):
        th = branch if branch in THEME and branch != "core" else "abyss"
        portal(ic, cx, cy, s * 0.8, 3, THEME[th], VOID if th == "abyss" else [tuple(int(c * k) for c in THEME[th]) for k in (0.1, 0.35, 0.65, 0.9, 1.1)])
    elif g in ("density",):
        _head_pack(ic, [(cx - 12 * s, cy + 6 * s), (cx + 12 * s, cy + 6 * s), (cx, cy - 10 * s)], 0.5 * s)
    elif g in ("elite", "ks_crown"):
        ic.paint(s_crown(cx, cy, 0.8 * s), GOLD, gloss=0.9)
    elif g in ("time", "ks_hourglass"):
        ic.paint(s_glass(cx, cy, 0.9 * s), SILVER, gloss=0.8, opacity=0.8)
        ic.paint(s_hourglass(cx, cy, 0.9 * s), WOOD, gloss=0.5)
    elif g == "reward":
        ic.glow(s_star(cx, cy, 20 * s), (255, 220, 120), 6, 0.8)
        ic.paint(s_star(cx, cy, 20 * s, 0.4, 5), GOLD, gloss=1.0)
    elif g == "gold":
        ic.paint(s_coins(cx, cy + 10 * s, 1.0 * s, 4), GOLD, gloss=0.9)
    elif g in ("key", "upgrade", "ks_ascent"):
        ic.paint(s_key(cx, cy, 0.75 * s, -40), GOLD, gloss=0.8)
        if g != "key":
            ic.paint(lambda d: d.polygon(pts([(cx + 14 * s, cy - 26 * s), (cx + 24 * s, cy - 12 * s), (cx + 4 * s, cy - 12 * s)]), fill=255), POISON, gloss=0.7, soft=2)
    elif g == "fragment":
        ic.paint(s_shard(cx, cy, 0.8 * s, 20), VOID, gloss=1.0, base=0.4)
    elif g == "orb":
        orb(ic, cx, cy, 16 * s, VOID)
    elif g in ("rolls", "coffer"):
        chest(ic, cx, cy + 4 * s, 0.75 * s, open_=(g == "rolls"), spill=False)
    elif g == "goblin":
        ic.paint(s_bag(cx, cy, 0.8 * s), WOOD, gloss=0.3)
    elif g == "life":
        soul(ic, cx, cy, 0.8 * s)
    elif g == "ks_ember":
        element(ic, "fire", cx, cy, 0.9 * s)
    else:
        ic.paint(s_star(cx, cy, 18 * s), GOLD, gloss=1.0)


def draw_atlas_node(kind, branch, glyph):
    tint = THEME.get(branch, THEME["core"])
    f = Framed("neutral", seed=1300 + sum(map(ord, branch + glyph)), round_=True)
    ic = f.ic
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
    r = np.sqrt((xx - W / 2) ** 2 + (yy - W / 2) ** 2) / (W / 2)
    ic.add(tint, np.clip(1 - r, 0, 1) ** 2 * 0.35)
    starfield(ic, len(glyph) + len(branch), tint, 28)
    nodes = [(20, 30), (34, 18), (80, 26), (84, 64), (22, 74), (66, 86)]
    for a, b in ((0, 1), (2, 3), (4, 5)):
        ic.flat(lambda d, a=a, b=b: d.line(pts([nodes[a], nodes[b]]), fill=255, width=int(P(1))), (230, 200, 140), 0.4)
    if kind == "keystone":
        ic.glow(s_ring(50, 50, 32, 4), tint, 6, 0.9)
        ic.paint(s_ring(50, 50, 31, 4), GOLD, gloss=0.8, soft=2)
        for k in range(4):
            a = math.radians(k * 90 - 90)
            ic.paint(s_star(50 + 34 * math.cos(a), 50 + 34 * math.sin(a), 6, 0.35, 4, -90), GOLD, gloss=1.0, soft=1.5)
    else:
        ic.paint(s_ring(50, 50, 29, 2.5), GOLD, gloss=0.6, soft=2)
    atlas_motif(ic, glyph, branch, 50, 50, 0.95 if kind == "keystone" else 0.8)
    return f.done()


# ---------------------------------------------------------------- dispatch
RIFT_KINDS = ("rm", "rk", "ro", "rt", "rg", "an", "rx")


def draw(name):
    """The 192 px drawing of a rift icon (name without folder and extension); None when it is not one."""
    kind, _, rest = name.partition("-")
    if kind == "rm":
        side, _, key = rest.partition("-")
        return draw_mod(side, key)
    if kind == "rk":
        return draw_key(int(rest))
    if kind == "ro":
        asc = rest.endswith("-asc")
        return draw_omen(rest[:-4] if asc else rest, asc)
    if kind == "rt":
        return draw_theme(rest)
    if kind == "rg":
        return draw_guardian(rest)
    if kind == "an":
        k, branch, glyph = rest.split("-", 2)
        return draw_atlas_node(k, branch, glyph)
    if kind == "rx":
        return {"portal": draw_portal, "chest": draw_chest, "atlas": draw_atlas, "lives": draw_lives,
                "clear": draw_clear, "omenkey": lambda: draw_key(9, omen=True), "omenfragment": draw_fragment,
                "ascended": draw_ascended}[rest]()
    return None
