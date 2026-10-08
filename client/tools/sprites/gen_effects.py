#!/usr/bin/env python3
"""Procedurally drawn magic effects + distance missiles for our 10.98 Tibia.dat / Tibia.spr.

Every picture is generated here from code (noise fields, particles, polygons, quantised palette ramps); no sprite of
any client is read, traced or recoloured.  The spec table `fx_custom.csv` (next to this file) lists every thing written:

  mode=replace  stock effect / missile ids that spells use (scripts in data/spells, the per-damage-type hit effects the
                engine shows in game.cpp / combat.cpp, and the area effects monster spells name in their XML).  The dat
                entry is rebuilt at the SAME id, so stock spell scripts keep working unchanged.
  mode=append   our own effects 372..423 and missiles 116..125 (names = server/data/lib/chaos_fx.lua).

python3 -I gen_effects.py --ours-dat Tibia.dat --ours-spr Tibia.spr --out-dir out/final \
        [--spec fx_custom.csv] [--preview DIR] [--overview fx_sheets/custom_overview.jpg] \
        [--lua-out ../../../server/data/lib/chaos_fx.lua] [--catalog-out ../../../server/data/spells/effects_catalog.csv]

* Input: the stock pair, or the merge_outfits.py result (outfits appended; effects/missiles untouched).  Running it again
  on its own output is allowed (the appended ids then exist and are rebuilt in place).  Input files are never modified.
* Spr: new sprite records (colour key ff00ff, u16 size, runs of u16 transparent / u16 coloured + RGBA pixels, exactly
  the layout datspr.Spr decodes) are appended; the offset table grows, old records are copied byte for byte.  Identical
  records are written once and records already present in the input spr are reused.  Fully transparent tiles use id 0.
* Dat: items and outfits are copied untouched; each spec row gets a new entry (optional light flag, then frame size,
  layers 1, patterns (missiles 3x3), phases, animator with per-frame ms, u32 sprite ids).  All other effect and missile
  entries are copied byte for byte.
* Outputs in --out-dir: Tibia.dat, Tibia.spr, chaos_fx.lua, effects_catalog.csv.  --lua-out / --catalog-out also write
  those two files elsewhere; --lua-out refuses to write when a chaos name/id of the file already there would change or vanish (adding is fine).
* Verification (always run): the output dat is re-parsed; every written effect/missile frame and pattern is rendered back
  from the output spr and compared pixel-exact with the generated picture; every other dat entry and 3000 sampled old
  sprites are checked unchanged.
"""
import sys, os, csv, struct, argparse, hashlib, random, zlib, math, re, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw
from datspr import Dat, Spr, sprite_index

HERE = os.path.dirname(os.path.abspath(__file__))
SS = 2                        # supersampling of the analytic fields (averaged down before quantising)
STOCK_EFFECTS, STOCK_MISSILES = 371, 115

# ----------------------------------------------------------------------------------------------------------- palettes
# 8-step ramps, dark -> bright.  `glow` palettes also give the dat entry a light source.
def _hex(s):
    return [tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in s.split()]


PALETTES = {
    'fire':    (_hex('1c0604 4e0d06 8c1c08 c43c0c e96a1a f7a43a ffd876 fff4d6'), True),
    'ember':   (_hex('16030a 3c0712 700e13 a5190f d23e12 ef7a2a fdbd5e ffeab4'), True),
    'hellfire': (_hex('12020e 38061c 6a0c20 9c1420 cc2a18 ec5a1c f99a3c ffd890'), True),
    'frost':   (_hex('050d24 0d2550 1a4c86 2f7cb8 5fb0dd 9ad8f2 d2f2ff ffffff'), True),
    'energy':  (_hex('12041f 2c0b52 4f1a94 7a3fd0 8e7cf2 8fc7ff d4f0ff ffffff'), True),
    'storm':   (_hex('0b1020 1d2c5a 3a58a0 6f95d8 b0cdf5 e6f0ff fffbe0 ffffff'), True),
    'poison':  (_hex('071205 13300b 255c12 3d8a1a 6cb52a a6dc4a dcf78c f8ffd8'), True),
    'venom':   (_hex('0c0f04 262c08 47520c 6f7c12 9aa61c c6cc38 e8ec80 fcffd8'), True),
    'holy':    (_hex('1c1405 4a3a10 8a6c1c c9a232 ecd060 fae89a fff8d8 ffffff'), True),
    'gold':    (_hex('180f04 40280a 6e4610 a06a18 d09a28 f0c848 fde68a fffbe0'), True),
    'shadow':  (_hex('07030d 1a0b2a 331650 4f2475 70399c 9a5fc4 c79ae6 f0dcff'), True),
    'void':    (_hex('020206 0c0818 1c1036 2e1a58 3e2c80 5a58b4 8ea6e0 d8f0ff'), True),
    'death':   (_hex('050a0c 0f1d24 1c3440 2d5260 4a7f86 7eb6aa c2ecd6 f2fff6'), True),
    'blood':   (_hex('100204 2e050a 580a10 861318 b0201f d4473a f08a74 ffd0c0'), False),
    'bloodglow': (_hex('14020a 3a0612 6c0c18 a0141c d02a24 f05a44 ff9a86 ffe0d6'), True),
    'arcane':  (_hex('12031a 330a45 5c1477 8a23a8 b543cf dc78e8 f3b8f6 fff0ff'), True),
    'heal':    (_hex('04140c 0a3320 12603a 1f9654 48c574 8ee6a0 d0f8d6 ffffff'), True),
    'earth':   (_hex('120c08 2b1e14 4a3524 6b5036 8f6f4c b2936a d4bb92 efe0c0'), False),
    'moss':    (_hex('0a0c06 1c2410 34401a 4e5c24 6e7a32 949c4a c0c47a e8ecc0'), False),
    'nature':  (_hex('060e06 102410 1c4018 2c6020 4a8428 78a838 b0d060 e4f4b0'), False),
    'ash':     (_hex('0c0c10 1e1e26 34343e 4e4e5a 6c6c78 9090a0 bcbcc8 e8e8f0'), False),
    'soot':    (_hex('050406 0e0c10 1a171e 28242e 3a3442 504858 706878 a49cb0'), False),
    'water':   (_hex('030c1a 082040 0f3c70 1d64a0 3a90c8 70bde6 b0e2f8 f0fcff'), True),
    'steel':   (_hex('0e0e12 26262e 44444e 66666e 8c8c94 b4b4b8 dedcd4 fffff0'), False),
    'bone':    (_hex('0e0c08 26221a 443e30 666050 8c8670 b4ae96 dcd6c0 fbf8ec'), False),
    'wood':    (_hex('0e0804 241608 3c260e 583818 74502a 966c40 b89060 dcc090'), False),
    'snow':    (_hex('101c2c 263c58 46648a 7094bc a0c0e0 c8e0f4 e8f4ff ffffff'), False),
    'ethereal': (_hex('040c18 0a2238 104060 1a6a8e 30a0bc 6ad4e0 b4f4f4 f4ffff'), True),
    'crit':    (_hex('180404 4a0808 8a1010 c82014 f0501c fa9a30 ffe070 ffffff'), True),
    'necro':   (_hex('0c0204 26040a 4a0812 6e0c18 92141e b42a2a d05a4e ecaa98'), True),
    'aegis':   (_hex('080c14 18243a 2c4466 4a6e98 76a0c8 a8cce8 dcecfa ffffff'), True),
    'wraith':  (_hex('0a0c10 1c2028 343a46 525c6c 7a8698 a6b2c4 d2dae6 f6f8fc'), False),
}
# alpha per ramp level.  No level is a faint wash: whatever passes the cut is a visible, crisp-edged shape.
ALPHA = {
    'glow':  (150, 180, 210, 235, 255, 255, 255, 255),
    'soft':  (120, 145, 170, 195, 220, 240, 255, 255),
    'smoke': (135, 155, 175, 190, 205, 215, 225, 235),
    'solid': (255,) * 8,
    'crystal': (190, 215, 235, 255, 255, 255, 255, 255),
}
CUT = 0.2                     # intensity below which a pixel is fully transparent (raised per thing if needed)
MIN_CLEAR = 0.65              # area effects: at least this share of every 32x32 frame stays alpha 0
LIFT = {'glow': 2, 'soft': 2}
BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) + 0.5) / 16 - 0.5


def light_of(pal):
    """small light source for glowing missiles.  Effects get none: dozens of lit tiles in an area spell tint the
    whole screen."""
    ramp, glows = PALETTES[pal]
    if not glows:
        return None
    r, g, b = ramp[5]
    return (2, round(r / 51) * 36 + round(g / 51) * 6 + round(b / 51))


# ---------------------------------------------------------------------------------------------- field primitives
def smooth(x):
    return x * x * (3 - 2 * x)


def ease_out(t):
    t = min(max(t, 0.0), 1.0)
    return 1 - (1 - t) ** 2


def life(t, peak=0.25, k=1.5):
    """burst -> dissipate envelope: eases up to 1 at `peak`, then falls to 0 at t=1 (last frames almost empty)."""
    if t <= peak:
        return ease_out(t / peak) if peak > 0 else 1.0
    return max(0.0, 1 - (t - peak) / (1 - peak)) ** k


def window(t, a, b, fin=0.15, fout=0.3):
    """1 inside [a,b] with linear fade-in over `fin` and fade-out over `fout` (both in t units)."""
    if t < a or t > b:
        return 0.0
    v = 1.0
    if fin > 0:
        v = min(v, (t - a) / fin)
    if fout > 0:
        v = min(v, (b - t) / fout)
    return max(0.0, min(1.0, v))


class Noise:
    def __init__(self, rng, n=16):
        self.g = rng.random((n, n)).astype(np.float32)
        self.n = n

    def __call__(self, x, y):
        n = self.n
        x0 = np.floor(x); y0 = np.floor(y)
        fx = smooth(x - x0); fy = smooth(y - y0)
        x0 = x0.astype(int) % n; y0 = y0.astype(int) % n
        x1 = (x0 + 1) % n; y1 = (y0 + 1) % n
        g = self.g
        a = g[y0, x0] * (1 - fx) + g[y0, x1] * fx
        b = g[y1, x0] * (1 - fx) + g[y1, x1] * fx
        return a * (1 - fy) + b * fy

    def fbm(self, x, y, octaves=3):
        v = 0.0; amp = 0.5; tot = 0.0
        for i in range(octaves):
            v = v + amp * self(x * (2 ** i) + 7.3 * i, y * (2 ** i) + 3.1 * i)
            tot += amp; amp *= 0.5
        return v / tot


class Cv:
    """Drawing context of one thing: supersampled coordinate grid + seeded randomness."""

    def __init__(self, S, seed, opts, centre, area=False):
        self.S = S
        self.area = area
        n = S * SS
        c = (np.arange(n, dtype=np.float32) + 0.5) / SS
        self.X, self.Y = np.meshgrid(c, c)
        self.seed = seed
        self.rng = np.random.default_rng(seed)
        self.noise = Noise(np.random.default_rng(seed + 1))
        self.noise2 = Noise(np.random.default_rng(seed + 2))
        self.o = opts
        self.cx, self.cy = centre
        self.R = (10.5 if area else 12.0) if S == 32 else 21.0
        if area:                                    # off-centre, different for every pattern variant
            g = np.random.default_rng(seed + 3)
            self.cx += g.uniform(-3, 3); self.cy += g.uniform(-3, 3)
        self._memo = {}

    def memo(self, key, fn):
        if key not in self._memo:
            self._memo[key] = fn()
        return self._memo[key]

    def frng(self, f):
        return np.random.default_rng(self.seed * 1000 + f + 17)

    def opt(self, k, d):
        v = self.o.get(k, d)
        return type(d)(v) if d is not None and not isinstance(d, str) else v

    def zeros(self):
        return np.zeros_like(self.X)

    # --- shapes (all return float fields on the supersampled grid)
    def dist(self, cx, cy, ry=1.0):
        return np.hypot(self.X - cx, (self.Y - cy) / ry)

    def gauss(self, cx, cy, r, ry=1.0):
        return np.exp(-((self.X - cx) ** 2 + ((self.Y - cy) / ry) ** 2) / (r * r))

    def disc(self, cx, cy, r, soft=0.6, ry=1.0):
        return np.clip((r - self.dist(cx, cy, ry)) / soft + 0.5, 0, 1)

    def ring(self, cx, cy, R, w, ry=1.0):
        return np.exp(-((self.dist(cx, cy, ry) - R) / w) ** 2)

    def blob(self, cx, cy, r, amp=0.35, key=0):
        """crisp lumpy disc: radius wobbles with angle (noise), so no two blobs are round or alike."""
        a = np.arctan2(self.Y - cy, self.X - cx)
        wob = self.noise(np.cos(a) * 1.7 + key * 3.7 + 11, np.sin(a) * 1.7 + key * 1.9 + 5) - 0.5
        return np.clip((r * (1 + 2 * amp * wob) - self.dist(cx, cy)) / 0.5 + 0.5, 0, 1)

    def arcs(self, cx, cy, R, w, ry=1.0, key=0, keep=0.55):
        """ring; for area effects broken into irregular arcs so a grid of them does not read as a pattern."""
        rg = self.ring(cx, cy, R, w, ry)
        if not self.area:
            return rg
        a = np.arctan2((self.Y - cy) / ry, self.X - cx)
        m = self.noise(np.cos(a) * 1.6 + key * 5.1 + 20, np.sin(a) * 1.6 + 20)
        return rg * np.clip((m - (1 - keep)) * 8, 0, 1)

    def segd(self, x0, y0, x1, y1):
        X, Y = self.X, self.Y
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy
        if L2 < 1e-9:
            return np.hypot(X - x0, Y - y0)
        u = np.clip(((X - x0) * dx + (Y - y0) * dy) / L2, 0, 1)
        return np.hypot(X - x0 - u * dx, Y - y0 - u * dy)

    def line(self, pts, w, core=None):
        d = None
        for (a, b), (c, e) in zip(pts[:-1], pts[1:]):
            s = self.segd(a, b, c, e)
            d = s if d is None else np.minimum(d, s)
        return np.exp(-(d / w) ** 2)

    def poly(self, pts):
        n = self.S * SS
        im = Image.new('L', (n, n), 0)
        ImageDraw.Draw(im).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
        return np.asarray(im, np.float32) / 255

    def star4(self, cx, cy, size, thin=0.55):
        X, Y = np.abs(self.X - cx), np.abs(self.Y - cy)
        a = np.exp(-(X / thin) ** 2 - (Y / size) ** 2)
        b = np.exp(-(Y / thin) ** 2 - (X / size) ** 2)
        return np.maximum(np.maximum(a, b), self.gauss(cx, cy, thin * 1.6))

    def angle(self, cx, cy):
        return np.arctan2(self.Y - cy, self.X - cx)

    def local(self, cx, cy, ux, uy):
        """coordinates along (A) and across (B) the unit direction (ux,uy)."""
        dx, dy = self.X - cx, self.Y - cy
        return dx * ux + dy * uy, -dx * uy + dy * ux


def shade(cv, I, pal, mode='glow', cut=CUT, dither=0.4):
    """quantise an intensity field (supersampled) to an RGBA uint8 tile with a palette ramp and crisp alpha levels."""
    S = cv.S
    I = I.reshape(S, SS, S, SS).mean(axis=(1, 3))
    ramp = np.array(PALETTES[pal][0], np.uint8)
    al = np.array(ALPHA[mode], np.uint8)
    b = np.tile(BAYER4, (S // 4, S // 4))
    n = len(ramp)
    q = np.clip(I, 0, 1) * n + b * dither
    idx = np.clip(np.floor(q).astype(int), 0, n - 1)
    on = I > cut                                  # crisp alpha edge (colour is dithered, alpha is not)
    lift = LIFT.get(mode, 0)                      # light-emitting layers never fade to near-black: compress the ramp
    cidx = np.round(lift + idx * (n - 1 - lift) / (n - 1)).astype(int)
    out = np.zeros((S, S, 4), np.uint8)
    out[..., :3] = ramp[cidx]
    out[..., 3] = np.where(on, al[idx], 0)
    return out


def over(dst, src):
    """alpha-over of uint8 RGBA arrays."""
    sa = src[..., 3:4].astype(np.float32) / 255
    da = dst[..., 3:4].astype(np.float32) / 255
    oa = sa + da * (1 - sa)
    rgb = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    out = np.zeros_like(dst)
    out[..., :3] = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(np.round(oa[..., 0] * 255), 0, 255).astype(np.uint8)
    out[out[..., 3] == 0] = 0
    return out


# ---------------------------------------------------------------------------------------------------- effect styles
# style(cv, t, f, n, pal) -> list of (field, palette, alpha-mode); t in [0,1] over the animation.
def particles(cv, key, k, fn):
    return cv.memo(key, lambda: fn(cv.rng, k))


def st_burst(cv, t, f, n, pal):
    """fire explosion: a lumpy, off-centre cluster of flame blobs with hot cores, embers flung out, soot puffs last."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('lumps', 6))
    lp = particles(cv, 'lp', k, lambda g, m: (g.random(m) * 6.283, g.random(m), 0.23 + 0.17 * g.random(m)))
    fire = cv.zeros()
    for i, (a, v, rk) in enumerate(zip(*lp)):
        rr = R * (0.06 + 0.5 * v * ease_out(min(1, t * 1.6)))
        x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.85 - 3 * t * t
        r = R * rk * (0.45 + 0.75 * ease_out(min(1, t / 0.25))) * (1 - t) ** 0.8
        if r < 0.6:
            continue
        heat = 0.95 - 0.5 * t
        fire = np.maximum(fire, cv.blob(x, y, r, 0.4, i) * heat * 0.72)
        fire = np.maximum(fire, cv.blob(x - r * 0.15, y - r * 0.2, r * 0.5, 0.3, i + 9) * heat)
    emb = particles(cv, 'emb', int(cv.opt('embers', 8)), lambda g, m: (g.random(m) * 6.283, 0.4 + 0.6 * g.random(m)))
    for a, v in zip(*emb):
        rr = R * (0.3 + 0.75 * v * ease_out(t))
        fire = np.maximum(fire, cv.gauss(cx + math.cos(a) * rr, cy + math.sin(a) * rr + 3 * t * t, 0.75) * (1 - t) * 1.1)
    smoke = cv.zeros()
    if t > 0.4:
        s = (t - 0.4) / 0.6
        sp = particles(cv, 'smk', 3, lambda g, m: (g.normal(0, 0.35, m), g.normal(0, 0.25, m)))
        for i, (dx, dy) in enumerate(zip(*sp)):
            r = R * 0.2 * (0.6 + 0.8 * s) * (1 - s) ** 0.5
            if r > 0.6:
                smoke = np.maximum(smoke, cv.blob(cx + dx * R, cy + dy * R - s * R * 0.6, r, 0.3, i + 30) * 0.55)
    return [(smoke, cv.opt('smoke', 'soot'), 'smoke'), (fire, pal, 'glow')]


def st_nova(cv, t, f, n, pal):
    """expanding ring(s) with sparks on the front; area effects get broken arcs on a slightly squashed ellipse."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    rings = int(cv.opt('rings', 1))
    ry = cv.opt('ry', 1.0) * (cv.memo('ry', lambda: 0.72 + 0.25 * cv.rng.random()) if cv.area else 1.0)
    out = cv.zeros()
    for k in range(rings):
        tk = (t - k * 0.18) / (1 - (rings - 1) * 0.18) if rings > 1 else t
        if tk <= 0 or tk > 1:
            continue
        Rt = 1.5 + (R - 1.5) * ease_out(tk)
        w = 1.4 * (1 - 0.5 * tk) + 0.45
        a = cv.angle(cx, cy)
        mod = 0.6 + 0.5 * cv.noise((np.cos(a) * 3 + 8 + k * 3) + tk * 2, np.sin(a) * 3 + 8)
        env = (1 - tk) ** 1.2
        out = np.maximum(out, cv.arcs(cx, cy, Rt, w, ry, k + 3 * f // max(1, n // 3)) * mod * env)
        sp = particles(cv, ('sp', k), 6, lambda g, m: (g.random(m) * 6.283, g.random(m)))
        for ang, ph in zip(*sp):
            rr = Rt * (1.0 + 0.12 * ph)
            out = np.maximum(out, cv.star4(cx + math.cos(ang) * rr, cy + math.sin(ang) * rr * ry, 1.4, 0.45) * env * (0.6 + 0.5 * ph))
    if t < 0.2:
        out = np.maximum(out, cv.gauss(cx, cy, 2.2) * (1 - t * 5))
    return [(out, pal, 'glow')]


def st_flame(cv, t, f, n, pal):
    """separate flame tongues licking up at random spots, flickering, then sinking; a few embers."""
    cx, cy = cv.cx, cv.cy
    k = int(cv.opt('tongues', 3))
    H = cv.R * cv.opt('height', 1.9)
    base = cy + cv.R * 0.6
    grow = ease_out(min(1.0, t / 0.2))
    die = 1.0 if t < 0.45 else max(0.0, 1 - (t - 0.45) / 0.55) ** 1.2
    tongues = particles(cv, 'tg', k, lambda g, m: (np.sort(g.uniform(-0.6, 0.6, m)), 0.55 + 0.45 * g.random(m), g.random(m) * 10))
    out = cv.zeros()
    for dx, hk, ph in zip(*tongues):
        h = H * hk * (0.35 + 0.65 * grow) * (0.1 + 0.9 * die) * (0.85 + 0.15 * math.sin(t * 19 + ph))
        if h < 1.5:
            continue
        x0 = cx + dx * cv.R
        s = np.clip((base - cv.Y) / h, 0, 1.2)
        sway = 1.8 * np.sin(s * 3.2 + t * 9 + ph) * s
        w = cv.R * cv.opt('width', 0.3) * np.clip(s * 4, 0, 1) ** 0.5 * np.clip(1 - s, 0, 1) ** 0.7 + 0.01
        shape = np.clip(1 - np.abs(cv.X - x0 - sway) / w, 0, 1) * (s > 0) * (s < 1)
        nz = cv.noise.fbm((cv.X - x0) / 4 + ph, (cv.Y + t * 26) / 4.5, 3)
        out = np.maximum(out, shape ** 0.6 * (0.6 + 0.6 * nz) * (1.25 - 0.45 * s))
    emb = particles(cv, 'emb', 5, lambda g, m: (g.normal(0, 0.45, m), g.random(m), 0.6 + 0.6 * g.random(m)))
    for ex, ph, sp in zip(*emb):
        u = (t * sp + ph) % 1.0
        out = np.maximum(out, cv.gauss(cx + ex * cv.R + 1.5 * math.sin(u * 9), base - u * H * 0.9, 0.7) * (1 - u) * die * 1.2)
    return [(out, pal, 'glow')]


def _kite(cx, cy, ang, L, W, back=0.0):
    ux, uy = math.cos(ang), math.sin(ang)
    px, py = -uy, ux
    b = (cx - ux * back, cy - uy * back)
    tip = (cx + ux * L, cy + uy * L)
    m1 = (cx + ux * L * 0.35 + px * W, cy + uy * L * 0.35 + py * W)
    m2 = (cx + ux * L * 0.35 - px * W, cy + uy * L * 0.35 - py * W)
    mid = (cx + ux * L * 0.35, cy + uy * L * 0.35)
    return [b, m1, tip, m2], [b, m1, tip, mid]


def st_shards(cv, t, f, n, pal):
    """ice crystals erupting (radial or upward spikes), then shattering into falling fragments and mist."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('count', 6))
    up = cv.opt('up', 0)
    sh = particles(cv, 'sh', k, lambda g, m: (
        (np.linspace(-2.4, -0.75, m) + g.normal(0, 0.12, m)) if up else (np.arange(m) / m * 6.283 + g.random() * 6.283 + g.normal(0, 0.2, m)),
        0.6 + 0.4 * g.random(m), 0.6 + 0.5 * g.random(m), g.random(m) * 0.25))
    body = cv.zeros(); hi = cv.zeros()
    shatter = cv.opt('shatter', 0.62)
    by = cy + (R * 0.45 if up else 0)
    for ang, lk, wk, dl in zip(*sh):
        g = ease_out(min(1, max(0, (t - dl) / 0.3)))
        if t > shatter or g <= 0:
            continue
        L = R * 0.95 * lk * g; W = 2.2 * wk * (0.5 + 0.5 * g) * cv.opt('width', 1.0)
        bx = cx + (math.cos(ang) * 2 if not up else (ang + 1.57) * 4)
        full, half = _kite(bx, by, ang, L, W, back=1.5)
        m_full = cv.poly(full); m_half = cv.poly(half)
        body = np.maximum(body, m_full * 0.55 + m_half * 0.25)
        tx, ty = bx + math.cos(ang) * L, by + math.sin(ang) * L
        hi = np.maximum(hi, cv.gauss(tx, ty, 1.0) * 0.9)
    frag = cv.zeros()
    if t > shatter - 0.05:
        s = (t - shatter + 0.05) / (1 - shatter + 0.05)
        fr = particles(cv, 'fr', k * 3, lambda g, m: (g.random(m) * 6.283, 0.3 + 0.8 * g.random(m), 0.6 + 0.8 * g.random(m)))
        for ang, v, sz in zip(*fr):
            rr = R * (0.25 + 0.75 * v * s)
            fx, fy = cx + math.cos(ang) * rr, (by if up else cy) + math.sin(ang) * rr * 0.8 + 10 * s * s
            frag = np.maximum(frag, cv.disc(fx, fy, sz * (1 - 0.6 * s), 0.6) * (0.85 - 0.5 * s))
    glint = cv.zeros()
    if 0.25 < t < shatter:
        gl = particles(cv, 'gl', 3, lambda g, m: (g.normal(0, 0.4, m), g.normal(0, 0.4, m)))
        for gx, gy in zip(*gl):
            glint = np.maximum(glint, cv.star4(cx + gx * R, by + gy * R * (0.5 if up else 1) - (4 if up else 0), 2.6, 0.45))
    return [(np.maximum(body, frag), pal, 'crystal'), (np.maximum(hi, glint), pal, 'glow')]


def _bolt(rng, x0, y0, x1, y1, depth=4, disp=0.32):
    pts = [(x0, y0), (x1, y1)]
    for _ in range(depth):
        new = [pts[0]]
        for (a, b), (c, d) in zip(pts[:-1], pts[1:]):
            L = math.hypot(c - a, d - b)
            off = rng.normal(0, disp) * L
            mx, my = (a + c) / 2 - (d - b) / max(L, 1e-6) * off, (b + d) / 2 + (c - a) / max(L, 1e-6) * off
            new += [(mx, my), (c, d)]
        pts = new
    return pts


def st_sparks(cv, t, f, n, pal):
    """crackling arcs: jagged bolts re-rolled every frame around a flash; strike=1 drops one bolt from the sky."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    g = cv.frng(f)
    k = int(cv.opt('bolts', 3))
    env = life(t, 0.2, 1.2)
    core = cv.zeros(); glow = cv.zeros()
    if cv.opt('strike', 0):
        top = -4 if cv.S == 32 else 0
        reach = min(1.0, t / 0.3)
        sx = cx + cv.memo('sx', lambda: cv.rng.normal(0, 3))
        pts = _bolt(g, sx, top, cx, cy + R * 0.3, 4, 0.18)
        npts = max(2, int(len(pts) * reach))
        if env > 0:
            core = np.maximum(core, cv.line(pts[:npts], 0.75) * env)
            glow = np.maximum(glow, cv.line(pts[:npts], 1.4) * 0.55 * env)
        if reach >= 1:
            s = (t - 0.3) / 0.7
            glow = np.maximum(glow, cv.arcs(cx, cy + R * 0.3, 2 + R * 0.8 * s, 1.1, 0.5, f) * (1 - s))
            glow = np.maximum(glow, cv.gauss(cx, cy + R * 0.3, 2.5 * (1 - s) + 0.8) * (1 - s))
        k = 2
    for i in range(k):
        a = g.random() * 6.283
        L = R * (0.55 + 0.45 * g.random()) * (0.6 + 0.4 * env)
        x0, y0 = cx + math.cos(a) * 2, cy + math.sin(a) * 2
        pts = _bolt(g, x0, y0, cx + math.cos(a) * L, cy + math.sin(a) * L, 3, 0.3)
        core = np.maximum(core, cv.line(pts, 0.6) * env)
        glow = np.maximum(glow, cv.line(pts, 1.3) * 0.5 * env)
    flash = cv.gauss(cx, cy, 1.8 + 0.8 * math.sin(f * 2.1) ** 2) * (0.9 * env)
    spk = cv.zeros()
    for i in range(4):
        a = g.random() * 6.283; rr = R * g.random()
        spk = np.maximum(spk, cv.gauss(cx + math.cos(a) * rr, cy + math.sin(a) * rr, 0.7) * env)
    return [(np.maximum(glow, flash * 0.7), pal, 'soft'), (np.maximum(np.maximum(core, flash), spk), pal, 'glow')]


def st_cloud(cv, t, f, n, pal):
    """a few separate lumpy puffs that swell, drift apart and up, then shrink away (no tile-filling haze)."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('puffs', 4))
    rise = cv.opt('rise', 0.4)
    mode = cv.opt('alpha', 'smoke')
    pf = particles(cv, 'pf', k, lambda g, m: (g.normal(0, 0.42, m), g.normal(0, 0.3, m), 0.2 + 0.13 * g.random(m), g.random(m) * 0.25))
    val = cv.zeros()
    for i, (px, py, pr, dl) in enumerate(zip(*pf)):
        u = (t - dl) / (1 - dl)
        if u <= 0:
            continue
        r = R * pr * (0.5 + 0.8 * ease_out(min(1, u * 2))) * (1 - u) ** 0.6
        if r < 0.7:
            continue
        bx = min(max(cx + px * R * (0.6 + 0.5 * u), r + 1), cv.S - r - 1)
        by = min(max(cy + py * R * 0.7 - rise * R * u, r + 1), cv.S - r - 1)
        b = cv.blob(bx, by, r, 0.35, i)
        lit = cv.blob(bx - r * 0.3, by - r * 0.35, r * 0.5, 0.3, i + 20)
        val = np.maximum(val, b * (0.45 + 0.32 * lit))
    layers = [(val, pal, mode)]
    if cv.opt('bolt', 0) and 0.2 < t < 0.7:
        g = cv.frng(f)
        pts = _bolt(g, cx + g.normal(0, 2), cy - R * 0.1, cx + g.normal(0, 4), cy + R * 0.8, 3, 0.25)
        layers.append((cv.line(pts, 0.6), cv.opt('boltpal', 'storm'), 'glow'))
    if cv.opt('skull', 0):
        w = life(t, 0.35, 1.2)
        if w > 0.05:
            layers.append((_skull(cv, cx, cy - 2 - 3 * t, R * 0.36) * w * 0.85, cv.opt('skullpal', 'death'), 'soft'))
    if cv.opt('motes', 0):
        mo = particles(cv, 'mo', 5, lambda g, m: (g.normal(0, 0.5, m), g.random(m)))
        m_ = cv.zeros()
        for mx, ph in zip(*mo):
            u = (t + ph) % 1
            m_ = np.maximum(m_, cv.gauss(cx + mx * R, cy + R * 0.4 - u * R * 1.2, 0.7) * (1 - u) * (1 - t))
        layers.append((m_, cv.opt('motepal', pal), 'glow'))
    return layers


def _skull(cv, cx, cy, s):
    """ghostly skull: cranium + jaw, with sockets / nose / teeth cut out.  s ~ half width."""
    cran = cv.disc(cx, cy - s * 0.15, s, 0.8, 0.95)
    jaw = cv.disc(cx, cy + s * 0.65, s * 0.62, 0.8, 0.55)
    sk = np.maximum(cran, jaw)
    eyes = np.maximum(cv.disc(cx - s * 0.42, cy + s * 0.05, s * 0.3, 0.6), cv.disc(cx + s * 0.42, cy + s * 0.05, s * 0.3, 0.6))
    nose = cv.poly([(cx, cy + s * 0.3), (cx - s * 0.15, cy + s * 0.55), (cx + s * 0.15, cy + s * 0.55)])
    teeth = np.exp(-((cv.Y - cy - s * 0.82) / 0.5) ** 2) * (np.abs(cv.X - cx) < s * 0.45) * 0.7
    shade_ = 0.75 + 0.25 * np.clip((cy - cv.Y) / s, -1, 1)
    return np.clip(sk * shade_ - eyes - nose * 0.9 - teeth, 0, 1) + np.maximum(eyes, nose) * sk * 0.12


def st_skull(cv, t, f, n, pal):
    """spectral skull rising out of dark smoke, jaw dropping, then dissolving."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    w = window(t, 0.0, 1.0, 0.3, 0.35)
    sy = cy + 3 - 6 * ease_out(t)
    sk = _skull(cv, cx, sy, R * 0.5)
    nz = cv.noise.fbm(cv.X / 3.5, cv.Y / 3.5 + t * 2, 3)
    sk = sk * np.clip((nz + 0.85 - max(0, t - 0.55) * 2.2) * 2, 0, 1) * w
    eyes = (cv.gauss(cx - R * 0.21, sy + R * 0.03, 1.2) + cv.gauss(cx + R * 0.21, sy + R * 0.03, 1.2)) * window(t, 0.2, 0.8, 0.1, 0.2)
    smoke = cv.zeros()
    for i in range(3):
        u = (t + i / 3) % 1
        r = R * 0.16 * (1 - u) * window(t, 0, 1, 0.15, 0.3)
        if r > 0.6:
            smoke = np.maximum(smoke, cv.blob(cx + (i - 1) * R * 0.45, cy + R * 0.55 - u * R * 0.5, r, 0.3, i + 40) * 0.6)
    return [(smoke, cv.opt('smoke', 'shadow'), 'smoke'), (sk * 0.85, pal, 'soft'), (eyes, cv.opt('eyes', 'hellfire'), 'glow')]


def st_rays(cv, t, f, n, pal):
    """holy light: rotating rays around a flare, optional cross-shaped flare, twinkles."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('rays', 8))
    cross = cv.opt('cross', 0)
    a = cv.angle(cx, cy); d = cv.dist(cx, cy)
    grow = ease_out(min(1, t * 2.2))
    env = life(t, 0.3, 1.3)
    rot = t * 0.9
    rays = np.clip(np.cos(k / 2 * (a - rot)), 0, 1) ** 10 * np.clip(1 - d / (R * (0.4 + 0.65 * grow)), 0, 1)
    rays2 = np.clip(np.cos(k / 2 * (a + rot * 0.7) + 1.57), 0, 1) ** 14 * np.clip(1 - d / (R * 0.7 * grow + 1), 0, 1) * 0.6
    out = np.maximum(rays, rays2) * env
    if cross:
        L = R * (0.4 + 0.6 * grow)
        X, Y = np.abs(cv.X - cx), cv.Y - cy
        arm = np.maximum(np.exp(-(X / 1.1) ** 2) * np.clip(1 - np.abs(Y + 1.5) / (L * 1.05), 0, 1),
                         np.exp(-((Y + R * 0.25) / 1.1) ** 2) * np.clip(1 - X / (L * 0.62), 0, 1))
        out = np.maximum(out * 0.6, arm * env)
    out = np.maximum(out, cv.gauss(cx, cy, 1.6 + 1.6 * grow) * env)
    tw = particles(cv, 'tw', 6, lambda g, m: (g.normal(0, 0.45, m), g.normal(0, 0.45, m), g.random(m) * 0.6))
    for x, y, ph in zip(*tw):
        w = window(t, ph, ph + 0.4, 0.15, 0.2)
        if w > 0:
            out = np.maximum(out, cv.star4(cx + x * R, cy + y * R - t * 4, 2.4, 0.45) * w)
    return [(out, pal, 'glow')]


def st_pillar(cv, t, f, n, pal):
    """column of light falling from above onto the tile, flash ring at the base, motes rising."""
    cx, cy, R = cv.cx, cv.cy, cv.R
    base = cy + R * 0.45
    reach = min(1.0, t / 0.25)
    env = 1.0 if t < 0.55 else max(0.0, 1 - (t - 0.55) / 0.45)
    w = (1.8 if cv.S == 32 else 3.2) * (1 - 0.5 * max(0, t - 0.5))
    top = base - (base - 2) * reach
    X = np.abs(cv.X - cx)
    beam = np.exp(-(X / w) ** 2) * (cv.Y > top) * (cv.Y < base + 1) * env
    beam = beam * (0.7 + 0.3 * np.sin(cv.Y * 0.8 + t * 20))
    core = np.exp(-(X / (w * 0.35)) ** 2) * (cv.Y > top) * (cv.Y < base) * env
    s = max(0.0, (t - 0.2) / 0.8)
    ringf = cv.arcs(cx, base, 2 + R * 0.85 * s, 1.1, 0.45, 2) * (1 - s) if t > 0.2 else cv.zeros()
    mo = particles(cv, 'mo', 6, lambda g, m: (g.normal(0, 0.45, m), g.random(m)))
    m_ = cv.zeros()
    for mx, ph in zip(*mo):
        u = (t * 1.3 + ph) % 1
        m_ = np.maximum(m_, cv.gauss(cx + mx * R, base - u * R * 1.4, 0.8) * (1 - u) * env)
    return [(np.maximum(np.maximum(np.maximum(beam * 0.55, core), ringf), m_), pal, 'glow')]


def st_splash(cv, t, f, n, pal):
    """liquid splash: a splat in the middle and droplets thrown out on ballistic arcs."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('drops', 9))
    mode = cv.opt('alpha', 'solid')
    dr = particles(cv, 'dr', k, lambda g, m: (g.random(m) * 6.283, 0.5 + 0.6 * g.random(m), 0.7 + 0.8 * g.random(m)))
    body = cv.zeros(); hi = cv.zeros()
    T = t * 1.0
    for a, v, sz in zip(*dr):
        x = cx + math.cos(a) * v * R * 1.1 * ease_out(T)
        y = cy + math.sin(a) * v * R * 0.9 * ease_out(T) - 7 * T + 14 * T * T
        r = sz * (1 - 0.6 * t) + 0.35
        if t > 0.85:
            r *= (1 - t) / 0.15
        body = np.maximum(body, cv.disc(x, y, r, 0.6))
        if r > 0.9:
            hi = np.maximum(hi, cv.disc(x - r * 0.35, y - r * 0.35, r * 0.35, 0.5))
        # short streak behind each fast droplet
        if t < 0.5:
            body = np.maximum(body, np.exp(-(cv.segd(x, y, cx + (x - cx) * 0.6, cy + (y - cy) * 0.6) / (r * 0.6)) ** 2) * 0.8)
    sr = R * (0.16 + 0.2 * ease_out(min(1, t * 3))) * (1 - 0.8 * max(0, t - 0.4) / 0.6)
    nz = cv.noise.fbm((cv.X - cx) / 2.5, (cv.Y - cy) / 2.5, 2)
    splat = np.clip((sr - cv.dist(cx, cy, 0.8) + (nz - 0.5) * 4) / 1.0, 0, 1)
    body = np.maximum(body, splat)
    val = body * 0.5 + np.maximum(hi, cv.disc(cx - sr * 0.3, cy - sr * 0.35, sr * 0.3, 0.6) * splat) * 0.3
    return [(val * (1 - 0.3 * t), pal, mode)]


def st_slash(cv, t, f, n, pal):
    """claw / blade slashes: crescent arcs drawn one after another, then a spray of droplets."""
    R = cv.R * cv.opt('scale', 1.0) * 0.85
    cx, cy = cv.cx - (3 if cv.S > 32 else 0), cv.cy - (3 if cv.S > 32 else 0)
    k = int(cv.opt('count', 3))
    out = cv.zeros()
    for i in range(k):
        off = (i - (k - 1) / 2) * R * 0.42
        t0 = i * 0.12
        u = (t - t0) / 0.45
        if u <= 0:
            continue
        head = min(1.0, u * 1.8)
        tail = max(0.0, (u - 0.45) / 0.8)
        if tail >= 1:
            continue
        th = cv.memo('th', lambda: 0.785 + (cv.rng.uniform(-0.7, 0.7) if cv.area else 0) + (math.pi / 2 if cv.area and cv.rng.random() < 0.4 else 0))
        ux, uy = math.cos(th), math.sin(th)
        pts = []
        for s in np.linspace(tail, head, 10):
            a_ = (s - 0.5) * R * 2.4
            b_ = off - math.sin(s * math.pi) * R * 0.32
            pts.append((cx + a_ * ux - b_ * uy, cy + a_ * uy + b_ * ux))
        if len(pts) > 1 and head > tail:
            m = len(pts) - 1
            for j in range(m):                      # crescent: thick in the middle, sharp at both ends
                wj = 0.5 + 1.1 * math.sin(math.pi * (j + 0.5) / m)
                out = np.maximum(out, cv.line(pts[j:j + 2], wj) * (1 - tail))
            out = np.maximum(out, cv.line(pts, 1.6) * 0.4 * (1 - tail))
    layers = [(out, pal, 'glow')]
    if t > 0.35 and cv.opt('drops', 1):
        s = (t - 0.35) / 0.65
        dr = particles(cv, 'dr', 8, lambda g, m: (g.normal(0, 0.6, m), g.normal(0, 0.6, m), 0.6 + 0.6 * g.random(m)))
        b = cv.zeros()
        for x, y, sz in zip(*dr):
            b = np.maximum(b, cv.disc(cx + x * R * (0.4 + 0.5 * s), cy + y * R * 0.4 + 10 * s * s, sz * (1 - 0.5 * s), 0.6))
        layers.insert(0, (b * 0.5 * (1 - s * 0.5), cv.opt('droppal', 'blood'), 'solid'))
    return layers


def st_impact(cv, t, f, n, pal):
    """hit flash: star of sharp spikes with a hot centre, debris flying off."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('spikes', 7))
    sp = particles(cv, 'sp', k, lambda g, m: (np.arange(m) / m * 6.283 + g.normal(0, 0.25, m), 0.6 + 0.4 * g.random(m)))
    grow = ease_out(min(1, t * 2.5))
    env = 1.0 if t < 0.35 else max(0.0, 1 - (t - 0.35) / 0.65)
    out = cv.zeros()
    for a, L in zip(*sp):
        Lt = R * L * (0.35 + 0.65 * grow)
        ux, uy = math.cos(a), math.sin(a)
        poly = [(cx + -uy * 1.2, cy + ux * 1.2), (cx + ux * Lt, cy + uy * Lt), (cx + uy * 1.2, cy - ux * 1.2)]
        out = np.maximum(out, cv.poly(poly) * (0.7 + 0.3 * L) * env)
    out = np.maximum(out, cv.disc(cx, cy, 3.5 * (1 - t) + 0.5, 1.0) * env)
    db = particles(cv, 'db', 7, lambda g, m: (g.random(m) * 6.283, 0.5 + 0.5 * g.random(m)))
    for a, v in zip(*db):
        rr = R * (0.3 + 0.8 * v * ease_out(t))
        out = np.maximum(out, cv.gauss(cx + math.cos(a) * rr, cy + math.sin(a) * rr + 4 * t * t, 0.7) * (1 - t))
    layers = [(out, pal, 'glow')]
    if cv.opt('ring', 0):
        layers.append((cv.arcs(cx, cy, 2 + R * 0.9 * ease_out(t), 1.0, 1.0, 1) * (1 - t), cv.opt('ringpal', pal), 'glow'))
    return layers


def _rock(g, r):
    m = 7
    ang = np.arange(m) / m * 6.283 + g.normal(0, 0.25, m) + g.random() * 6.283
    rad = r * (0.7 + 0.45 * g.random(m))
    return list(zip(ang, rad))


def st_eruption(cv, t, f, n, pal):
    """rocks bursting out of the ground on ballistic arcs over a dark crater, dust cloud spreading."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('rocks', 6))
    base = cy + R * 0.35
    rk = cv.memo('rk', lambda: [(cv.rng.normal(0, 0.55), 0.6 + 0.6 * cv.rng.random(), cv.rng.random() * 6.283,
                                  _rock(cv.rng, (1.4 + 1.9 * cv.rng.random()) * cv.R / 13.5), cv.rng.normal(0, 4)) for _ in range(k)])
    rocks = cv.zeros()
    for vx, vy, rot, shape, spin in rk:
        T = t * 1.15
        x = cx + vx * R * T
        y = base - vy * R * 2.1 * T + R * 2.3 * T * T
        if y > base + 3 or T > 1:
            continue
        ang = rot + spin * T
        pts = [(x + math.cos(a + ang) * r, y + math.sin(a + ang) * r) for a, r in shape]
        m = cv.poly(pts)
        rr = max(r for _, r in shape)
        light = np.clip(((x - cv.X) + (y - cv.Y)) / (2.4 * rr), -1, 1)
        rocks = np.maximum(rocks, m * (0.5 + 0.3 * light))
    crater = cv.zeros()
    if cv.opt('cracks', 0):
        cr = cv.memo('cr', lambda: [_bolt(cv.rng, cx, base, cx + math.cos(a) * R * 1.0, base + math.sin(a) * R * 0.5, 3, 0.2)
                                    for a in np.linspace(0, 6.283, 6, endpoint=False) + cv.rng.random()])
        reach = min(1.0, t * 3)
        for pts in cr:
            npt = max(2, int(len(pts) * reach))
            crater = np.maximum(crater, cv.line(pts[:npt], 0.5) * 0.55 * (1 - max(0, t - 0.6) / 0.4))
    dust = cv.zeros()
    for i, a in enumerate(cv.memo('dust', lambda: cv.rng.random(4) * 6.283)):
        s = ease_out(t)
        r = R * 0.17 * (0.5 + 0.8 * s) * (1 - t) ** 0.7
        if r > 0.6:
            dust = np.maximum(dust, cv.blob(cx + math.cos(a) * R * (0.25 + 0.55 * s), base + math.sin(a) * R * 0.3 * s - 3 * s, r, 0.35, i + 50) * 0.5)
    return [(crater, 'soot', 'soft'), (dust, cv.opt('dust', 'ash'), 'smoke'), (rocks, pal, 'solid')]


def st_thorns(cv, t, f, n, pal):
    """thorny vines spearing up out of the ground, curling, then sinking back; a few leaves/spores."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('count', 4))
    base = cy + R * 0.5
    th = particles(cv, 'th', k, lambda g, m: (np.linspace(-0.8, 0.8, m) + g.normal(0, 0.1, m), 0.7 + 0.5 * g.random(m), g.normal(0, 0.5, m)))
    g = min(1.0, t / 0.35) if t < 0.65 else max(0.0, 1 - (t - 0.65) / 0.35)
    g = ease_out(g)
    out = cv.zeros()
    for dx, hk, curl in zip(*th):
        h = R * 1.35 * hk * g
        if h < 1:
            continue
        x0 = cx + dx * R * 0.8
        left, right = [], []
        for s in np.linspace(0, 1, 7):
            x = x0 + curl * s * s * R * 0.5
            y = base - s * h
            w = 2.0 * (1 - s) + 0.2
            left.append((x - w, y)); right.append((x + w, y))
        out = np.maximum(out, cv.poly(left + right[::-1]) * (0.55 + 0.2 * dx))
        for s in (0.35, 0.6, 0.8):
            if s * h > 2:
                x = x0 + curl * s * s * R * 0.5; y = base - s * h
                sd = 1 if (s * 10) % 2 > 1 else -1
                out = np.maximum(out, cv.poly([(x, y - 0.8), (x + sd * 3.2 * (1 - s * 0.5), y - 2.2), (x, y + 0.8)]) * 0.75)
    hi = out * np.clip((cx - cv.X) / R + 0.5, 0, 1) * 0.25
    layers = [(np.clip(out + hi, 0, 1), pal, 'solid')]
    sp = particles(cv, 'sp', 5, lambda g_, m: (g_.normal(0, 0.5, m), g_.random(m)))
    m_ = cv.zeros()
    for x, ph in zip(*sp):
        u = (t + ph) % 1
        m_ = np.maximum(m_, cv.gauss(cx + x * R, base - u * R * 1.2, 0.7) * (1 - u) * g)
    layers.append((m_, cv.opt('spore', 'poison'), 'glow'))
    return layers


def st_sparkle(cv, t, f, n, pal):
    """shimmer: twinkling 4-point stars spiralling around the body and rising, with a soft glow."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('count', 7))
    sp = particles(cv, 'sp', k, lambda g, m: (g.random(m) * 6.283, 0.35 + 0.65 * g.random(m), g.random(m) * 0.5, 0.8 + 0.5 * g.random(m)))
    out = cv.zeros()
    for a, r, ph, sz in zip(*sp):
        w = window(t, ph, ph + 0.5, 0.15, 0.25)
        if w <= 0:
            continue
        u = (t - ph) / 0.5
        ang = a + u * 2.2
        x = cx + math.cos(ang) * r * R * (1 - 0.3 * u)
        y = cy + math.sin(ang) * r * R * 0.6 - u * R * cv.opt('rise', 0.6) + 2
        out = np.maximum(out, cv.star4(x, y, 2.6 * sz, 0.45) * w)
    if cv.opt('ring', 0):
        s = ease_out(t)
        out = np.maximum(out, cv.arcs(cx, cy + R * 0.4 - s * R * 0.9, R * 0.65, 1.0, 0.4, 4) * (1 - t) * 0.9)
    return [(out, pal, 'glow')]


def st_rings(cv, t, f, n, pal):
    """flat glowing rings rising from the feet over the body, sparkles riding them."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('count', 3))
    out = cv.zeros()
    for i in range(k):
        u = (t - i * 0.18) / 0.64
        if not 0 < u < 1:
            continue
        y = cy + R * 0.55 - u * R * 1.25
        rr = R * (0.75 - 0.25 * u)
        e = window(u, 0, 1, 0.2, 0.35)
        a = cv.angle(cx, y)
        out = np.maximum(out, cv.ring(cx, y, rr, 1.1, 0.38) * e * (0.65 + 0.35 * np.sin(a * 2 + u * 6)))
        out = np.maximum(out, cv.star4(cx + math.cos(u * 9 + i) * rr, y + math.sin(u * 9 + i) * rr * 0.38, 2.0, 0.45) * e)
    return [(out, pal, 'glow')]


def st_circle(cv, t, f, n, pal):
    """rune circle on the ground: rings drawn in, rotating runes or a star figure, light motes, fade."""
    cx, cy, R = cv.cx, cv.cy + cv.opt('dy', 2.0), cv.R * cv.opt('scale', 1.0)
    ry = cv.opt('ry', 0.62)
    fig = cv.opt('figure', 'runes')
    a = cv.angle(cx, cy)
    a_ell = np.arctan2((cv.Y - cy) / ry, cv.X - cx)
    draw = min(1.0, t / 0.35)
    env = 1.0 if t < 0.65 else max(0.0, 1 - (t - 0.65) / 0.35)
    arc = ((a_ell + math.pi) / 6.283 < draw).astype(np.float32)
    r1, r2 = R * 0.95, R * 0.72
    out = (cv.arcs(cx, cy, r1, 0.8, ry, 1, 0.65) + cv.arcs(cx, cy, r2, 0.65, ry, 2, 0.6) * 0.8) * arc
    rot = t * 1.6
    if fig in ('star', 'pentagram'):
        pts = [(cx + math.cos(-1.5708 + i * 4 * math.pi / 5 + rot * 0.3) * r2, cy + math.sin(-1.5708 + i * 4 * math.pi / 5 + rot * 0.3) * r2 * ry) for i in range(6)]
        npt = 1 + int(5 * min(1.0, max(0.0, (t - 0.15) / 0.35)) + 0.999)
        if npt >= 2:
            out = np.maximum(out, cv.line(pts[:npt], 0.6) * 0.95)
    else:
        m = int(cv.opt('runes', 10))
        rm = (r1 + r2) / 2
        for i in range(m):
            ang = i * 6.283 / m + rot
            x, y = cx + math.cos(ang) * rm, cy + math.sin(ang) * rm * ry
            if (ang - rot) / 6.283 > draw:
                continue
            g = (i * 7) % 3
            if g == 0:
                out = np.maximum(out, cv.line([(x - 0.9, y - 1.4), (x + 0.9, y + 1.0)], 0.45))
            elif g == 1:
                out = np.maximum(out, cv.line([(x, y - 1.5), (x, y + 1.2), (x + 1.2, y + 0.2)], 0.45))
            else:
                out = np.maximum(out, cv.gauss(x, y, 0.8) * 1.1)
    out = out * env * (0.85 + 0.15 * math.sin(t * 18))
    mo = particles(cv, 'mo', 7, lambda g, k: (g.random(k) * 6.283, g.random(k)))
    m_ = cv.zeros()
    for ang, ph in zip(*mo):
        u = (t * 1.4 + ph) % 1
        if t > 0.25:
            m_ = np.maximum(m_, cv.gauss(cx + math.cos(ang) * r2, cy + math.sin(ang) * r2 * ry - u * R * 0.9, 0.7) * (1 - u) * env)
    return [(np.maximum(out, m_), pal, 'glow')]


def st_swirl(cv, t, f, n, pal):
    """vortex: spiral arms winding inward around a dark core; eye=1 opens an eye in the centre."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    ry = cv.opt('ry', 0.8)
    k = int(cv.opt('arms', 3))
    d = cv.dist(cx, cy, ry); a = np.arctan2((cv.Y - cy) / ry, cv.X - cx)
    env = window(t, 0, 1, 0.2, 0.35)
    grow = ease_out(min(1, t * 2))
    rot = t * 7 * cv.opt('spin', 1.0)
    rr = R * (0.45 + 0.55 * grow)
    arms = np.clip(np.cos(k * (a + d / R * 3.2 - rot)), 0, 1) ** 3
    radial = np.clip(d / (rr * 0.25), 0, 1) * np.clip(1 - d / rr, 0, 1) ** 0.7
    out = arms * radial * env * (0.6 + 0.6 * cv.noise.fbm(d / 3, a * 2, 2))
    core = cv.disc(cx, cy, R * 0.14 * grow, 0.8, ry) * env
    pt = particles(cv, 'pt', 8, lambda g, m: (g.random(m) * 6.283, g.random(m)))
    for ang, ph in zip(*pt):
        u = (t * 1.5 + ph) % 1
        r_ = rr * (1 - u)
        aa = ang + u * 4
        out = np.maximum(out, cv.gauss(cx + math.cos(aa) * r_, cy + math.sin(aa) * r_ * ry, 0.75) * env * u)
    layers = [(core * 0.55, cv.opt('corepal', 'void'), 'solid'), (out, pal, 'glow')]
    if cv.opt('eye', 0):
        w = window(t, 0.25, 0.9, 0.2, 0.2)
        if w > 0:
            ex, ey = R * 0.55, R * 0.26 * w
            X, Y = (cv.X - cx) / ex, (cv.Y - cy) / max(ey, 0.3)
            lid = np.clip((1 - (np.abs(X) ** 1.0 + Y * Y)) * 3, 0, 1) * (np.abs(X) < 1)
            iris = cv.disc(cx, cy, R * 0.16, 0.6) * lid
            pupil = np.exp(-((cv.X - cx) / 0.7) ** 2) * (np.abs(cv.Y - cy) < R * 0.13) * lid
            layers.append((np.clip(lid * 0.45 + iris * 0.45 - pupil * 0.9, 0, 1), cv.opt('eyepal', 'hellfire'), 'glow'))
    return layers


def st_tornado(cv, t, f, n, pal):
    """whirlwind: stack of spinning ellipses widening upward, with debris orbiting."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    base = cy + R * 0.55
    H = R * 1.75 * ease_out(min(1, t * 2.5))
    env = window(t, 0, 1, 0.1, 0.35)
    out = cv.zeros()
    m = 9
    for i in range(m):
        s = i / (m - 1)
        y = base - s * H
        rr = 2 + R * 0.75 * s ** 0.8
        xo = math.sin(t * 6 + s * 3) * 2
        a = np.arctan2((cv.Y - y) / 0.3, cv.X - cx - xo)
        band = cv.ring(cx + xo, y, rr, 1.1 + 0.8 * s, 0.32) * (0.5 + 0.5 * np.cos(a * 2 + t * 14 + i))
        band = band * (0.55 + 0.7 * cv.noise.fbm(cv.X / 3 + t * 3, cv.Y / 2, 2))
        out = np.maximum(out, band * env * (0.75 + 0.35 * s))
    db = particles(cv, 'db', 6, lambda g, k: (g.random(k), g.random(k) * 6.283))
    for s, ph in zip(*db):
        y = base - s * H; rr = 2 + R * 0.75 * s
        a = ph + t * 12
        out = np.maximum(out, cv.gauss(cx + math.cos(a) * rr, y + math.sin(a) * rr * 0.3, 0.8) * env)
    return [(out, pal, 'glow')]


def st_aura(cv, t, f, n, pal):
    """self-buff aura: pulsing ring at the feet, flame streaks and motes rising around the body."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    base = cy + R * 0.45
    env = window(t, 0, 1, 0.15, 0.3)
    pulse = 0.75 + 0.25 * math.sin(t * 6.283 * 2)
    out = cv.arcs(cx, base, R * 0.8, 1.1, 0.4, 5) * env * pulse
    st = particles(cv, 'st', 9, lambda g, k: (g.random(k) * 6.283, g.random(k), 0.6 + 0.6 * g.random(k)))
    wisp = cv.zeros()
    for a, ph, L in zip(*st):
        u = (t * 1.6 + ph) % 1
        x = cx + math.cos(a) * R * 0.72 + math.sin(u * 7 + a) * 1.2
        y = base + math.sin(a) * R * 0.72 * 0.4 - u * R * 1.25
        wisp = np.maximum(wisp, np.exp(-((cv.X - x) / 1.1) ** 2 - ((cv.Y - y) / (2.2 * L + 1)) ** 2) * (1 - u) * env)
    return [(np.maximum(out, wisp), pal, 'glow')]


def st_bubbles(cv, t, f, n, pal):
    """bubbles rising with a wobble and popping."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    k = int(cv.opt('count', 6))
    bb = particles(cv, 'bb', k, lambda g, m: (g.normal(0, 0.45, m), g.random(m) * 0.4, 1.0 + 1.6 * g.random(m), g.random(m) * 6))
    out = cv.zeros()
    for x, ph, r, w in zip(*bb):
        u = (t - ph) / 0.6
        if not 0 < u < 1:
            continue
        bx = cx + x * R + 1.5 * math.sin(u * 8 + w)
        by = cy + R * 0.5 - u * R * 1.3
        if u > 0.85:
            s = (u - 0.85) / 0.15
            out = np.maximum(out, cv.ring(bx, by, r * (1 + s * 1.2), 0.5) * (1 - s))
        else:
            out = np.maximum(out, cv.ring(bx, by, r, 0.55) * 0.8)
            out = np.maximum(out, cv.gauss(bx - r * 0.4, by - r * 0.4, 0.6))
    return [(out, pal, 'glow')]


def _note(cv, x, y, s, flag=True):
    head = cv.disc(x, y, 1.6 * s, 0.6, 0.7)
    stem = np.exp(-((cv.X - x - 1.3 * s) / (0.45 * s)) ** 2) * (cv.Y < y) * (cv.Y > y - 6 * s)
    fl = cv.line([(x + 1.3 * s, y - 6 * s), (x + 3.2 * s, y - 4.2 * s)], 0.55 * s) if flag else 0
    return np.maximum(np.maximum(head, stem), fl)


def st_notes(cv, t, f, n, pal):
    """music notes (or z glyphs: glyph=z) floating up and swaying."""
    cx, cy, R = cv.cx, cv.cy, cv.R
    k = int(cv.opt('count', 3))
    z = cv.opt('glyph', 'note') == 'z'
    out = cv.zeros()
    for i in range(k):
        u = (t - i * 0.2) / 0.6
        if not 0 < u < 1:
            continue
        e = window(u, 0, 1, 0.2, 0.3)
        x = cx - R * 0.4 + i * R * 0.45 + math.sin(u * 6 + i) * 2
        y = cy + R * 0.3 - u * R * 1.0
        s = 0.8 + 0.25 * i
        if z:
            w = 2.2 * s
            out = np.maximum(out, cv.line([(x - w, y - w), (x + w, y - w), (x - w, y + w), (x + w, y + w)], 0.5) * e)
        else:
            out = np.maximum(out, _note(cv, x, y, s) * e)
    return [(out * 0.8, pal, 'solid' if cv.opt('solid', 0) else 'glow')]


def _star5(cx, cy, r, rot=0.0):
    pts = []
    for i in range(10):
        a = -1.5708 + rot + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


def st_stun(cv, t, f, n, pal):
    """little stars circling over the head."""
    cx, cy, R = cv.cx, cv.cy - cv.R * 0.45, cv.R
    out = cv.zeros()
    for i in range(3):
        a = t * 6.283 * 1.5 + i * 2.094
        x, y = cx + math.cos(a) * R * 0.6, cy + math.sin(a) * R * 0.22
        out = np.maximum(out, cv.poly(_star5(x, y, 2.6 + 0.6 * math.sin(a), a)) * (0.7 + 0.3 * math.sin(a)))
    out = np.maximum(out, cv.ring(cx, cy, R * 0.6, 0.5, 0.36) * 0.25)
    return [(out * window(t, 0, 1, 0.1, 0.2), pal, 'glow')]


def st_hearts(cv, t, f, n, pal):
    """hearts rising and fading."""
    cx, cy, R = cv.cx, cv.cy, cv.R
    out = cv.zeros()
    for i in range(3):
        u = (t - i * 0.18) / 0.64
        if not 0 < u < 1:
            continue
        s = 3.0 + i * 0.4
        x = cx + (i - 1) * R * 0.45 + math.sin(u * 5 + i) * 1.5
        y = cy + R * 0.35 - u * R * 1.1
        X = (cv.X - x) / s; Y = -(cv.Y - y) / s
        h = (X * X + Y * Y - 1) ** 3 - X * X * Y ** 3
        m = np.clip(-h * 40, 0, 1)
        hl = cv.gauss(x - s * 0.45, y - s * 0.35, s * 0.3)
        out = np.maximum(out, (m * 0.62 + hl * m * 0.35) * window(u, 0, 1, 0.2, 0.3))
    return [(out, pal, 'glow')]


def st_meteor(cv, t, f, n, pal):
    """burning rock dropping in from the upper left, then exploding (burst) on the tile."""
    cx, cy, R = cv.cx, cv.cy, cv.R
    cut = 0.3
    if t >= cut:
        layers = st_burst(cv, (t - cut) / (1 - cut), f, n, pal)
        return layers
    u = t / cut
    sx, sy = max(4.0, cx - R * 1.3), max(4.0, cy - R * 1.7)
    x, y = sx + (cx - sx) * u, sy + (cy - sy) * u
    L = math.hypot(cx - sx, cy - sy); ux, uy = (cx - sx) / L, (cy - sy) / L
    A, B = cv.local(x, y, ux, uy)
    s = np.clip(-A / 22, 0, 1)
    tail = np.exp(-(B / (4.2 * (1 - s) + 0.6)) ** 2) * (A < 0) * (1 - s) * (0.6 + 0.6 * cv.noise.fbm(cv.X / 3, cv.Y / 3 + f, 2))
    fire = np.maximum(tail, cv.gauss(x, y, 6.5) * 0.85)
    rock = cv.disc(x, y, 3.6, 0.7) * (0.45 + 0.25 * np.clip(((x - cv.X) + (y - cv.Y)) / 7, -1, 1))
    return [(fire, pal, 'glow'), (rock, 'earth', 'solid')]


# --- combat feedback (crit / dodge / reflect / elemental weapon hit), sent by server/data/scripts/chaos/combat_fx.lua
def st_critstar(cv, t, f, n, pal):
    """critical hit: a sharp, slightly tilted star (four long blades, four short ones) snapping open at once with a
    white-hot core, then the blades thin and retract while a few sparks fly off.  No ring, no haze."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    rot = cv.opt('rot', 0.32)
    snap = ease_out(min(1.0, t / 0.12))
    fade = 1.0 if t < 0.3 else max(0.0, 1 - (t - 0.3) / 0.7)
    blades = cv.zeros()
    for i in range(8):
        a = rot + i * math.pi / 4
        L = R * (1.15 if i % 2 == 0 else 0.55) * (0.4 + 0.6 * snap) * (0.55 + 0.45 * fade)
        W = (1.9 if i % 2 == 0 else 1.3) * (0.35 + 0.65 * fade)
        ux, uy = math.cos(a), math.sin(a)
        poly = [(cx - uy * W, cy + ux * W), (cx + ux * L, cy + uy * L), (cx + uy * W, cy - ux * W)]
        blades = np.maximum(blades, cv.poly(poly) * (0.75 if i % 2 == 0 else 0.55) * fade)
    core = cv.disc(cx, cy, 2.6 * (1 - 0.7 * t) + 0.6, 0.8) * fade
    hot = np.maximum(core, cv.star4(cx, cy, R * 0.5 * snap * fade + 0.5, 0.5) * fade)
    spk = cv.zeros()
    sp = particles(cv, 'sp', 6, lambda g, m: (np.arange(m) / m * 6.283 + 0.4 + g.normal(0, 0.2, m), 0.6 + 0.4 * g.random(m)))
    if t > 0.15:
        s = (t - 0.15) / 0.85
        for a, v in zip(*sp):
            rr = R * (0.5 + 0.7 * v * ease_out(s))
            spk = np.maximum(spk, cv.gauss(cx + math.cos(a) * rr, cy + math.sin(a) * rr + 3 * s * s, 0.65) * (1 - s))
    return [(blades, pal, 'glow'), (np.maximum(hot, spk), pal, 'glow')]


def st_whoosh(cv, t, f, n, pal):
    """dodge: an afterimage leaving sideways: three tapered speed streaks sweep across the creature (right to left),
    a pale ghost sliver at the tail, a little dust kicked up at the feet."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    d = cv.opt('dir', -1.0)
    out = cv.zeros()
    for i, (dy, L, dl) in enumerate(((-0.6, 1.7, 0.0), (-0.05, 2.2, 0.05), (0.5, 1.5, 0.1))):
        u = (t - dl) / 0.75
        if u <= 0 or u >= 1:
            continue
        head = cx + d * R * (-0.7 + 1.4 * ease_out(u))
        tail = head - d * R * L * (0.3 + 0.7 * min(1.0, u * 2.5)) * (1 - u)
        y = cy + dy * R + 1.2 * math.sin(u * 3.0 + i)
        lo, hi = min(head, tail), max(head, tail)
        if hi - lo < 1:
            continue
        s = np.clip((cv.X - tail) / (head - tail), 0, 1)                    # 0 at the tail, 1 at the head
        inside = (cv.X >= lo) * (cv.X <= hi)
        w = 0.45 + 1.7 * s ** 1.5
        out = np.maximum(out, np.exp(-((cv.Y - y - 1.5 * (1 - s) ** 2) / w) ** 2) * inside * (0.35 + 0.65 * s) * (1 - u ** 2))
    ghost = cv.zeros()                                                     # crescent afterimage edge
    if t < 0.6:
        u = t / 0.6
        gx = cx - d * R * 0.15 + d * R * 0.55 * ease_out(u)
        a = cv.angle(gx, cy)
        m = np.clip((np.cos(a) * -d - 0.15) * 2.2, 0, 1)
        ghost = cv.ring(gx, cy, R * 0.55, 0.8, 1.35) * m * (1 - u) * 0.9
    dust = cv.zeros()
    dp = particles(cv, 'dp', 4, lambda g, m: (g.uniform(-0.5, 0.6, m), g.random(m)))
    for x, v in zip(*dp):
        s = min(1.0, t * 1.4)
        dust = np.maximum(dust, cv.disc(cx - d * R * (x + 0.4 * s), cy + R * 0.8 - 3 * s * v, 1.1 * (1 - s) + 0.2, 0.6) * (1 - s))
    return [(dust, 'ash', 'smoke'), (ghost, pal, 'glow'), (out, pal, 'glow')]


def _shield(cx, cy, w, h):
    """heater shield outline points: flat top, straight-ish sides, curving to a point at the bottom."""
    top = cy - h * 0.5
    right = [(cx + w * (1 - (k / 10) ** 1.7) ** 0.6, top + h * k / 10) for k in range(11)]
    left = [(2 * cx - x, y) for x, y in reversed(right)]
    return [(cx - w, top)] + right + left[1:]


def st_aegis(cv, t, f, n, pal):
    """reflect: a heater-shield outline flashes up in front of the creature, a glint sweeps across it, then the
    outline bounces outward in three short arcs (the damage being thrown back) and fades."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    w, h = R * 0.68, R * 1.35
    grow = ease_out(min(1.0, t / 0.18))
    fade = 1.0 if t < 0.45 else max(0.0, 1 - (t - 0.45) / 0.55)
    s = 0.75 + 0.25 * grow
    outer = cv.poly(_shield(cx, cy, w * s, h * s))
    inner = cv.poly(_shield(cx, cy + 0.6, (w - 2.0) * s, (h - 3.2) * s))
    rim = np.clip(outer - inner, 0, 1)
    body = rim * 0.85 * fade
    face = inner * 0.12 * fade * (t < 0.35)
    glint = cv.zeros()
    if 0.08 < t < 0.6:
        u = (t - 0.08) / 0.52
        A, B = cv.local(cx - w + 2 * w * u, cy - h * 0.2, 0.7071, 0.7071)
        glint = np.exp(-(B / 1.3) ** 2) * outer * (1 - u)
    arcs = cv.zeros()
    if t > 0.3:
        u = (t - 0.3) / 0.7
        for k, a0 in enumerate((-2.2, -1.57, -0.94)):
            rr = h * 0.6 + R * 0.9 * ease_out(u)
            a = cv.angle(cx, cy)
            m = np.clip(1 - np.abs(((a - a0 + math.pi) % (2 * math.pi)) - math.pi) / 0.32, 0, 1)
            arcs = np.maximum(arcs, cv.ring(cx, cy, rr, 0.9) * m * (1 - u))
    return [(face, pal, 'soft'), (np.maximum(body, arcs), pal, 'glow'), (glint, 'storm', 'glow')]


def st_imbue(cv, t, f, n, pal):
    """elemental weapon hit: a thin crescent edge-trail in the element's colour cutting across the tile (the strike),
    plus a few element particles: kind=fire embers rising, ice glints, energy micro-arcs, earth spores, death wisps,
    holy motes.  Small and mostly transparent on purpose: it shows on every auto-attack hit."""
    cx, cy, R = cv.cx, cv.cy, cv.R * cv.opt('scale', 1.0)
    kind = cv.opt('kind', 'fire')
    th = cv.memo('th', lambda: -0.6 + cv.rng.uniform(-0.45, 0.45))
    ux, uy = math.cos(th), math.sin(th)
    trail = cv.zeros()
    head = min(1.0, 0.3 + t / 0.3); tail = max(0.0, (t - 0.1) / 0.55)
    if tail < head:
        pts = []
        for s in np.linspace(tail, head, 9):
            a_ = (s - 0.5) * R * 2.0
            b_ = -math.sin(s * math.pi) * R * 0.35
            pts.append((cx + a_ * ux - b_ * uy, cy + a_ * uy + b_ * ux))
        m = len(pts) - 1
        for j in range(m):
            wj = 0.45 + 1.0 * math.sin(math.pi * (j + 0.5) / m)
            trail = np.maximum(trail, cv.line(pts[j:j + 2], wj) * (1 - tail) * 0.9)
    g = cv.frng(f)
    pt = cv.zeros()
    k = int(cv.opt('count', 5))
    pp = particles(cv, 'pp', k, lambda r, m: (r.normal(0, 0.45, m), r.normal(0, 0.35, m), 0.6 + 0.6 * r.random(m), r.random(m)))
    s = t
    env = (1 - s) ** 1.1
    for x, y, v, ph in zip(*pp):
        px_, py_ = cx + x * R, cy + y * R
        if kind == 'fire':                  # embers drift up and flicker
            pt = np.maximum(pt, cv.gauss(px_ + 1.5 * math.sin(s * 8 + ph * 6), py_ - R * 0.9 * s * v, 0.75) * env * (0.7 + 0.3 * math.sin(f * 2 + ph * 9)))
        elif kind == 'ice':                 # tiny four-point glints that twinkle and fall a little
            pt = np.maximum(pt, cv.star4(px_, py_ + 3 * s * s, 1.8 * v * env + 0.3, 0.4) * env)
        elif kind == 'energy':              # micro arcs re-rolled every frame
            a = g.random() * 6.283; L = 2.5 + 3 * g.random()
            pts = _bolt(g, px_, py_, px_ + math.cos(a) * L, py_ + math.sin(a) * L, 2, 0.35)
            pt = np.maximum(pt, cv.line(pts, 0.5) * env)
        elif kind == 'earth':               # spores swelling then popping
            pt = np.maximum(pt, cv.disc(px_, py_ - R * 0.3 * s * v, (0.6 + 1.0 * v) * (1 - s) + 0.2, 0.6) * env)
        elif kind == 'death':               # dark wisps curling upward
            pts = [(px_ + 1.6 * math.sin(q * 2.5 + ph * 6 + s * 5), py_ - R * 0.5 * s - q * 4) for q in np.linspace(0, 1, 5)]
            pt = np.maximum(pt, cv.line(pts, 0.55) * env)
        else:                               # holy motes rising slowly with a glint
            pt = np.maximum(pt, cv.gauss(px_, py_ - R * 0.5 * s * v, 0.7) * env)
            if ph > 0.6:
                pt = np.maximum(pt, cv.star4(px_, py_ - R * 0.5 * s * v, 2.2 * env + 0.3, 0.35) * env * 0.9)
    return [(trail, pal, 'glow'), (pt, cv.opt('ptpal', pal), 'glow')]


STYLES = {
    'critstar': st_critstar, 'whoosh': st_whoosh, 'aegis': st_aegis, 'imbue': st_imbue,
    'meteor': st_meteor, 'burst': st_burst, 'nova': st_nova, 'flame': st_flame, 'shards': st_shards, 'sparks': st_sparks, 'cloud': st_cloud,
    'skull': st_skull, 'rays': st_rays, 'pillar': st_pillar, 'splash': st_splash, 'slash': st_slash, 'impact': st_impact,
    'eruption': st_eruption, 'thorns': st_thorns, 'sparkle': st_sparkle, 'rings': st_rings, 'circle': st_circle,
    'swirl': st_swirl, 'tornado': st_tornado, 'aura': st_aura, 'bubbles': st_bubbles, 'notes': st_notes,
    'stun': st_stun, 'hearts': st_hearts,
}


# --------------------------------------------------------------------------------------------------- missile styles
# mstyle(cv, ux, uy, f, n, pal) -> layers; (ux,uy) unit flight direction in screen coords ((0,0) = same tile).
def tail_field(cv, ux, uy, L, w0, w1=0.4, cx=None, cy=None):
    A, B = cv.local(cv.cx if cx is None else cx, cv.cy if cy is None else cy, ux, uy)
    s = np.clip(-A / L, 0, 1)
    w = w0 * (1 - s) + w1 * s
    return np.exp(-(B / w) ** 2) * (A < 0.5) * (1 - s) ** 0.9


def ms_orb(cv, ux, uy, f, n, pal):
    """glowing orb with a flickering comet tail; spark=1 adds crackles, skull=1 a tiny skull face."""
    r = cv.opt('r', 3.6)
    moving = ux or uy
    cx, cy = cv.cx + ux * 3, cv.cy + uy * 3                   # head slightly ahead, the tail gets the room behind
    g = cv.frng(f)
    nz = cv.noise.fbm(cv.X / 2.5 + f * 1.7, cv.Y / 2.5 - f * 1.3, 2)
    core = cv.disc(cx, cy, r, 1.4) * (0.75 + 0.3 * nz)
    halo = cv.gauss(cx, cy, r * 1.6) * 0.42
    out = np.maximum(core, halo)
    if moving:
        tl = tail_field(cv, ux, uy, cv.opt('tail', 15.0), r * 1.05, cx=cx, cy=cy)
        out = np.maximum(out, tl * (0.6 + 0.5 * nz))
        for i in range(3):
            s = (f / max(n, 1) + i / 3) % 1
            px = cx - ux * (r + s * 11) + g.normal(0, 1.2); py = cy - uy * (r + s * 11) + g.normal(0, 1.2)
            out = np.maximum(out, cv.gauss(px, py, 0.7) * (1 - s))
    layers = [(out, pal, 'glow')]
    if cv.opt('spark', 0):
        sp = cv.zeros()
        for i in range(2):
            a = g.random() * 6.283
            pts = _bolt(g, cx, cy, cx + math.cos(a) * (r + 5), cy + math.sin(a) * (r + 5), 2, 0.3)
            sp = np.maximum(sp, cv.line(pts, 0.5))
        layers.append((sp, cv.opt('sparkpal', pal), 'glow'))
    if cv.opt('skull', 0):
        layers.append((_skull(cv, cx, cy - 0.5, r * 0.85) * 0.8, cv.opt('skullpal', 'bone'), 'solid'))
    return layers


def ms_bolt(cv, ux, uy, f, n, pal):
    """elongated energy bolt: a hot lance-shaped core, long streak, flickering edge."""
    cx, cy = cv.cx, cv.cy
    if not (ux or uy):
        return ms_orb(cv, 0, 0, f, n, pal)
    A, B = cv.local(cx, cy, ux, uy)
    L = cv.opt('len', 6.0); W = cv.opt('w', 2.2)
    core = np.clip(1 - (A / L) ** 2 - (B / W) ** 2, 0, 1) ** 0.6
    nz = cv.noise.fbm(cv.X / 2 + f * 2, cv.Y / 2 - f, 2)
    tl = tail_field(cv, ux, uy, cv.opt('tail', 15.0), W * 1.1, 0.3) * (0.5 + 0.6 * nz)
    halo = np.exp(-(A / (L * 1.6)) ** 2 - (B / (W * 2.2)) ** 2) * 0.45
    return [(np.maximum(np.maximum(core, tl), halo), pal, 'glow')]


def ms_shard(cv, ux, uy, f, n, pal):
    """crystal shard (kite polygon with a lit and a dark facet) with a faint frosty trail."""
    cx, cy = cv.cx, cv.cy
    if not (ux or uy):
        ux, uy = 0.0, 1.0
    ang = math.atan2(uy, ux)
    L = cv.opt('len', 8.0); W = cv.opt('w', 2.4)
    full, half = _kite(cx - ux * L * 0.4, cy - uy * L * 0.4, ang, L, W, back=L * 0.25)
    body = cv.poly(full) * 0.5 + cv.poly(half) * 0.28
    tip = cv.gauss(cx + ux * L * 0.6, cy + uy * L * 0.6, 0.9) * 0.9
    tl = tail_field(cv, ux, uy, 10.0, 1.8, 0.3) * 0.45 * (0.7 + 0.3 * math.sin(f * 2.5))
    return [(tl, pal, 'soft'), (body, cv.opt('bodypal', pal), 'crystal'), (tip, pal, 'glow')]


def ms_arrow(cv, ux, uy, f, n, pal):
    """arrow / spear: shaft, head, fletching; glow=1 adds a magic trail and a light halo on the head."""
    cx, cy = cv.cx, cv.cy
    if not (ux or uy):
        ux, uy = 0.0, 1.0
    L = cv.opt('len', 11.0)
    head = cv.opt('head', 3.2)
    spear = cv.opt('spear', 0)
    px, py = -uy, ux
    tipx, tipy = cx + ux * L * 0.55, cy + uy * L * 0.55
    bx, by = cx - ux * L * 0.55, cy - uy * L * 0.55
    shaft = cv.line([(bx, by), (tipx - ux * head, tipy - uy * head)], 0.65)
    hb = head * (1.0 if not spear else 1.3)
    hw = 1.9 if not spear else 1.5
    hx, hy = tipx - ux * hb, tipy - uy * hb
    headm = cv.poly([(tipx, tipy), (hx + px * hw, hy + py * hw), (hx + ux * hb * 0.25, hy + uy * hb * 0.25), (hx - px * hw, hy - py * hw)])
    fl = np.zeros_like(shaft)
    if not spear:
        for sd in (1, -1):
            fl = np.maximum(fl, cv.line([(bx + ux * 2.5, by + uy * 2.5), (bx + px * sd * 1.8, by + py * sd * 1.8)], 0.5))
    layers = []
    if cv.opt('glow', 0):
        tl = tail_field(cv, ux, uy, 14.0, 1.6, 0.3) * (0.6 + 0.2 * math.sin(f * 3))
        layers.append((np.maximum(tl, cv.gauss(tipx, tipy, 3.0) * 0.55), cv.opt('glowpal', pal), 'soft'))
    layers.append((shaft * 0.5, cv.opt('shaftpal', 'wood'), 'solid'))
    layers.append((fl * 0.7, cv.opt('fletchpal', 'bone'), 'solid'))
    layers.append((headm * (0.65 + 0.2 * np.clip(-((cv.X - tipx) * px + (cv.Y - tipy) * py), -1, 1)), pal, 'solid'))
    return layers


def ms_dart(cv, ux, uy, f, n, pal):
    """thin needle dart dripping venom."""
    cx, cy = cv.cx, cv.cy
    if not (ux or uy):
        ux, uy = 0.0, 1.0
    needle = cv.line([(cx - ux * 5, cy - uy * 5), (cx + ux * 5, cy + uy * 5)], 0.6)
    tip = cv.gauss(cx + ux * 5, cy + uy * 5, 0.9)
    g = cv.frng(f)
    drip = cv.zeros()
    for i in range(3):
        s = (f / max(n, 1) + i / 3) % 1
        drip = np.maximum(drip, cv.gauss(cx - ux * (3 + s * 8), cy - uy * (3 + s * 8) + s * 3, 0.9) * (1 - s))
    tl = tail_field(cv, ux, uy, 9.0, 1.2, 0.3) * 0.5
    return [(np.maximum(tl, drip), pal, 'glow'), (needle * 0.55, 'steel', 'solid'), (tip, pal, 'glow')]


def ms_rock(cv, ux, uy, f, n, pal):
    """tumbling boulder (or snowball: round=1) with a dust trail."""
    cx, cy = cv.cx, cv.cy
    r = cv.opt('r', 6.0)
    if cv.opt('round', 0):
        body = cv.disc(cx, cy, r, 0.8)
        light = np.clip(((cx - cv.X) + (cy - cv.Y)) / (2.2 * r), -1, 1)
        val = body * (0.55 + 0.35 * light)
        a = f * 1.3
        val = np.maximum(val, cv.gauss(cx + math.cos(a) * r * 0.5, cy + math.sin(a) * r * 0.5, 0.8) * 0.7 * body)
    else:
        shape = cv.memo('shape', lambda: _rock(cv.rng, r))
        ang = f * 6.283 / max(n, 1)
        pts = [(cx + math.cos(a + ang) * rr, cy + math.sin(a + ang) * rr) for a, rr in shape]
        body = cv.poly(pts)
        light = np.clip(((cx - cv.X) + (cy - cv.Y)) / (2.2 * r), -1, 1)
        nz = cv.noise.fbm(cv.X / 2 + f, cv.Y / 2, 2)
        val = body * (0.48 + 0.3 * light + 0.15 * (nz - 0.5))
    layers = []
    if ux or uy:
        layers.append((tail_field(cv, ux, uy, 12.0, r * 0.8, 0.5) * 0.4, cv.opt('dust', 'ash'), 'smoke'))
    layers.append((val, pal, 'solid'))
    return layers


def ms_spin(cv, ux, uy, f, n, pal):
    """spinning blade: a sword silhouette rotating a quarter turn per frame, with a motion blur disc."""
    cx, cy = cv.cx, cv.cy
    ang = f * math.pi / 2 + 0.6
    blur = cv.ring(cx, cy, 9.0, 1.6) * 0.22 * (0.5 + 0.5 * np.cos(cv.angle(cx, cy) - f * math.pi / 2 - 2.2))
    ux_, uy_ = math.cos(ang), math.sin(ang)
    px, py = -uy_, ux_
    tip = (cx + ux_ * 11, cy + uy_ * 11)
    blade = cv.poly([tip, (cx + px * 1.6, cy + py * 1.6), (cx - ux_ * 1, cy - uy_ * 1), (cx - px * 1.6, cy - py * 1.6)])
    guard = cv.line([(cx - ux_ * 1.5 + px * 3.5, cy - uy_ * 1.5 + py * 3.5), (cx - ux_ * 1.5 - px * 3.5, cy - uy_ * 1.5 - py * 3.5)], 0.7)
    grip = cv.line([(cx - ux_ * 2, cy - uy_ * 2), (cx - ux_ * 6, cy - uy_ * 6)], 0.7)
    light = np.clip(((cv.X - cx) * px + (cv.Y - cy) * py) / 2, -1, 1)
    return [(blur, pal, 'soft'), (blade * (0.68 + 0.2 * light), 'steel', 'solid'), (np.maximum(guard, grip) * 0.55, 'gold', 'solid')]


MSTYLES = {'orb': ms_orb, 'bolt': ms_bolt, 'shard': ms_shard, 'arrow': ms_arrow, 'dart': ms_dart, 'rock': ms_rock,
           'spin': ms_spin}
DIRS = [(x, y) for y in range(3) for x in range(3)]          # pattern (x,y): x 0/1/2 = west/centre/east, y = north/../south


# ----------------------------------------------------------------------------------------------------- rendering
def parse_opts(s):
    o = {}
    for kv in filter(None, (s or '').split(';')):
        k, v = kv.split('=', 1)
        try:
            v = float(v)
        except ValueError:
            pass
        o[k.strip()] = v
    return o


def seed_of(row):
    return zlib.crc32(f"{row['category']}:{row['name']}:{row.get('seed', '')}".encode()) & 0x7fffffff


CUTS = (CUT, 0.26, 0.32, 0.4, 0.5, 0.62)


def clear_share(img):
    return float((img[..., 3] == 0).mean())


def render_row(row):
    """-> dict(w, h, px, py, phases, durs, frames={(phase,x,y): RGBA uint8 array (h*32, w*32, 4)}, light, stats)

    Area effects get 3x3 pattern variants (the client picks one by tile position: x % 3, y % 3), each drawn off-centre
    from its own seed, so a grid of them does not repeat.  The alpha cut is raised (deterministically) until every
    frame keeps at least MIN_CLEAR (area) / 50 % (single) of its pixels fully transparent."""
    size = int(row['size']); S = 32 * size; n = int(row['frames']); ms = int(row['ms'])
    opts = parse_opts(row['opts'])
    pal = row['palette']
    assert pal in PALETTES, pal
    centre = (16.0, 16.0) if size == 1 else (40.0, 40.0)
    stats = None
    if row['category'] == 'effect':
        fn = STYLES[row['style']]
        area = row['use'] == 'area'
        px = py = 3 if area else 1
        layers = {}
        for y in range(py):
            for x in range(px):
                cv = Cv(S, seed_of(row) + 7919 * (y * px + x), opts, centre, area)
                for f in range(n):
                    t = f / (n - 1) if n > 1 else 0.0
                    layers[(f, x, y)] = (cv, fn(cv, t, f, n, pal))
        need = MIN_CLEAR if area else 0.5
        for cut in CUTS:
            frames = {k: compose(cv, ly, cut) for k, (cv, ly) in layers.items()}
            clear = [clear_share(im) for im in frames.values()]
            if min(clear) >= need:
                break
        last = [1 - clear_share(frames[(n - 1, x, y)]) for y in range(py) for x in range(px)]
        stats = dict(cut=cut, clear_min=min(clear), clear_mean=sum(clear) / len(clear), last_cover=max(last))
        light = None
    else:
        fn = MSTYLES[row['style']]
        frames = {}
        for (x, y) in DIRS:
            dx, dy = x - 1, y - 1
            L = math.hypot(dx, dy)
            ux, uy = (dx / L, dy / L) if L else (0.0, 0.0)
            cv = Cv(S, seed_of(row), opts, centre)
            for f in range(n):
                frames[(f, x, y)] = compose(cv, fn(cv, ux, uy, f, n, pal))
        px = py = 3
        light = light_of(pal) if opts.get('light', 1) else None
    return dict(w=size, h=size, px=px, py=py, phases=n, durs=[ms] * n, frames=frames, light=light, stats=stats)


def compose(cv, layers, cut=CUT):
    out = np.zeros((cv.S, cv.S, 4), np.uint8)
    for field, pal, mode in layers:
        if np.isscalar(field) or not np.any(field > 0.02):
            continue
        out = over(out, shade(cv, np.clip(field, 0, 1), pal, mode, cut=max(cut, CUT if mode != 'solid' else 0.15)))
    out[out[..., 3] == 0] = 0
    return out


# ---------------------------------------------------------------------------------------------------- spr / dat io
def encode_sprite(tile):
    """32x32x4 uint8 -> spr record bytes (None if fully transparent)."""
    a = tile.reshape(1024, 4)
    on = a[:, 3] > 0
    if not on.any():
        return None
    body = bytearray()
    i = 0
    last = int(np.nonzero(on)[0][-1]) + 1
    while i < last:
        j = i
        while j < last and not on[j]:
            j += 1
        k = j
        while k < last and on[k]:
            k += 1
        body += struct.pack('<HH', j - i, k - j) + a[j:k].tobytes()
        i = k
    return b'\xff\x00\xff' + struct.pack('<H', len(body)) + bytes(body)


def tiles_of(img, w, h):
    """split a (h*32, w*32) canvas into dat tile order: ww/hh = 0 is the bottom-right tile."""
    out = {}
    for hh in range(h):
        for ww in range(w):
            y0 = (h - 1 - hh) * 32; x0 = (w - 1 - ww) * 32
            out[(ww, hh)] = img[y0:y0 + 32, x0:x0 + 32]
    return out


def build_entry(g, sprite_ids, loop):
    b = bytearray()
    if g['light']:
        b += bytes([0x16]) + struct.pack('<HH', *g['light'])      # 'light' in the >=10.10 flag table
    b += b'\xff'
    w, h = g['w'], g['h']
    b += bytes([w, h])
    if w > 1 or h > 1:
        b += bytes([32 * max(w, h)])
    b += bytes([1, g['px'], g['py'], 1, g['phases']])           # layers, patterns x/y/z, phases
    if g['phases'] > 1:
        b += bytes([0]) + struct.pack('<ib', loop, 0)           # async, loop count, start phase
        for d in g['durs']:
            b += struct.pack('<II', d, d)
    b += struct.pack(f'<{len(sprite_ids)}I', *sprite_ids)
    return bytes(b)


class Thing_:
    """minimal stand-in for datspr.Thing so sprite_index can address generated sprite lists."""
    def __init__(self, g):
        self.w, self.h, self.layers, self.px, self.py, self.pz, self.phases = g['w'], g['h'], 1, g['px'], g['py'], 1, g['phases']


def render_back(t, spr):
    """every (phase, x, y) full canvas of a parsed thing as uint8 RGBA arrays."""
    out = {}
    for ph in range(t.phases):
        for y in range(t.py):
            for x in range(t.px):
                c = np.zeros((t.h * 32, t.w * 32, 4), np.uint8)
                for hh in range(t.h):
                    for ww in range(t.w):
                        a = spr.sprite(t.sprites[sprite_index(t, x, y, 0, 0, ph, ww, hh)])
                        if a is not None:
                            y0 = (t.h - 1 - hh) * 32; x0 = (t.w - 1 - ww) * 32
                            c[y0:y0 + 32, x0:x0 + 32] = a
                out[(ph, x, y)] = c
    return out


# ------------------------------------------------------------------------------------------------------ outputs
def read_spec(path):
    rows = list(csv.DictReader(open(path, newline='')))
    for r in rows:
        r['id'] = int(r['id'])
        assert r['category'] in ('effect', 'missile') and r['mode'] in ('replace', 'append'), r
        assert (r['style'] in STYLES) if r['category'] == 'effect' else (r['style'] in MSTYLES), r
        assert r['size'] in ('1', '2') and 2 <= int(r['frames']) <= 32 or (r['category'] == 'missile' and int(r['frames']) >= 1), r
        if r['category'] == 'effect':
            assert r['use'] in ('area', 'single'), r
            assert r['use'] == 'single' or r['size'] == '1', ('area effects are 1x1', r['name'])
            assert 400 <= int(r['frames']) * int(r['ms']) <= 900, ('effect length 400..900 ms', r['name'])
    for cat in ('effect', 'missile'):
        ids = [r['id'] for r in rows if r['category'] == cat]
        names = [r['name'] for r in rows if r['category'] == cat]
        assert len(set(ids)) == len(ids), f'duplicate {cat} id'
        assert len(set(names)) == len(names), f'duplicate {cat} name'
        stock = STOCK_EFFECTS if cat == 'effect' else STOCK_MISSILES
        app = sorted(r['id'] for r in rows if r['category'] == cat and r['mode'] == 'append')
        assert app == list(range(stock + 1, stock + 1 + len(app))), f'{cat} append ids must be {stock + 1}.. contiguous'
        assert all(1 <= r['id'] <= stock for r in rows if r['category'] == cat and r['mode'] == 'replace')
    return rows


def lua_text(rows):
    lua = ['-- GENERATED by client/tools/sprites/gen_effects.py from fx_custom.csv (ids = positions in the generated Tibia.dat;',
           '-- all art is drawn procedurally by that script).  Magic effects > 255 need the client feature GameMagicEffectU16',
           '-- (enabled in the 10.98 profile); the server already sends effects as uint16 (protocolgame.cpp sendMagicEffect).',
           '-- Distance shots are uint8 (max 255).',
           'ChaosFx = {']
    for r in rows:
        if r['mode'] == 'append' and r['category'] == 'effect':
            lua.append(f"\t{r['name']} = {r['id']},  -- {r['theme']}: {r['note']}")
    lua += ['}', '', 'ChaosFxMissile = {']
    for r in rows:
        if r['mode'] == 'append' and r['category'] == 'missile':
            lua.append(f"\t{r['name']} = {r['id']},  -- {r['theme']}: {r['note']}")
    lua += ['}', '',
            'function Fx(name, fallback)', '\treturn ChaosFx[name] or fallback or CONST_ME_NONE', 'end', '',
            'function FxMissile(name, fallback)', '\treturn ChaosFxMissile[name] or fallback or CONST_ANI_NONE', 'end', '']
    return '\n'.join(lua)


def lua_ids(text):
    out = {}
    for tab, body in re.findall(r'(ChaosFx(?:Missile)?)\s*=\s*\{(.*?)\n\}', text, re.S):
        for name, i in re.findall(r'^\s*(\w+)\s*=\s*(\d+)', body, re.M):
            out[(tab, name)] = int(i)
    return out


def write_catalog(rows, path):
    with open(path, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['name', 'theme', 'category', 'id', 'mode', 'use', 'style', 'palette', 'size', 'frames', 'ms', 'note'])
        for r in rows:
            w.writerow([r['name'], r['theme'], r['category'], r['id'], r['mode'], r['use'], r['style'], r['palette'],
                        f"{r['size']}x{r['size']}", r['frames'], r['ms'], r['note']])


TILED_N = 7


def ground(n=TILED_N, seed=5):
    """procedural mid grey-brown flagstone ground, n x n tiles (only for previews)."""
    g = np.random.default_rng(seed)
    W = n * 32
    img = np.zeros((W, W, 3), np.float32)
    for ty in range(n):
        for tx in range(n):
            base = np.array([98, 88, 74], np.float32) + g.normal(0, 7)
            img[ty * 32:(ty + 1) * 32, tx * 32:(tx + 1) * 32] = base + g.normal(0, 5, (32, 32, 1))
    img[::32, :] *= 0.7; img[:, ::32] *= 0.7
    out = np.full((W, W, 4), 255, np.uint8); out[..., :3] = np.clip(img, 0, 255)
    return out


def tiled(g, frame, n=TILED_N):
    """the effect on every tile of an n x n area at one frame, as the client draws it (pattern = position % 3,
    bigger things anchored at their bottom-right tile).  -> RGBA layer (n*32)^2 without ground."""
    m = 32 * (g['w'] - 1)
    W = n * 32
    c = Image.new('RGBA', (W + m, W + m), (0, 0, 0, 0))
    for ty in range(n):
        for tx in range(n):
            im = Image.fromarray(g['frames'][(frame, tx % g['px'], ty % g['py'])], 'RGBA')
            c.alpha_composite(im, (tx * 32, ty * 32))
    return np.asarray(c)[m:, m:]


def tiled_clear(g):
    """share of the inner 5x5 tiles left fully uncovered: (worst frame, mean over frames)."""
    v = [float((tiled(g, f)[32:-32, 32:-32, 3] == 0).mean()) for f in range(g['phases'])]
    return min(v), sum(v) / len(v)


def preview(rows, gens, out_dir, overview):
    from PIL import ImageFont
    os.makedirs(out_dir, exist_ok=True)
    bg = (34, 38, 34, 255)

    def strip(row, g, maxf=12):
        n = g['phases']
        idx = list(range(n)) if n <= maxf else sorted(set(int(round(i * (n - 1) / (maxf - 1))) for i in range(maxf)))
        box = 64 * g['w']                                   # everything at 2x, nearest neighbour
        if row['category'] == 'missile':
            pats = [(2, 1), (2, 0), (1, 0), (0, 0), (0, 1), (0, 2), (1, 2), (2, 2), (1, 1)]
            cells = [(idx[0], x, y) for x, y in pats] + [(f, 2, 1) for f in idx[1:]]
        else:
            cells = [(f, 0, 0) for f in idx]
        im = Image.new('RGBA', (len(cells) * (box + 2), box), bg)
        for i, k in enumerate(cells):
            fr = Image.fromarray(g['frames'][k], 'RGBA')
            fr = fr.resize((fr.width * 2, fr.height * 2), Image.NEAREST)
            im.alpha_composite(fr, (i * (box + 2), 0))
        return im

    sheets = {}
    for cat in ('effect', 'missile'):
        for mode in ('replace', 'append'):
            sel = [(r, g) for r, g in zip(rows, gens) if r['category'] == cat and r['mode'] == mode]
            if not sel:
                continue
            per = 12
            for p in range(0, len(sel), per):
                part = sel[p:p + per]
                strips = [strip(r, g) for r, g in part]
                W = max(s.width for s in strips) + 200
                H = sum(s.height + 8 for s in strips) + 4
                sheet = Image.new('RGB', (W, H), (12, 12, 16))
                dr = ImageDraw.Draw(sheet)
                y = 4
                for (r, g), s in zip(part, strips):
                    dr.text((6, y + 4), f"{r['category'][0]}{r['id']} {r['name']}"[:30], fill=(255, 220, 120))
                    dr.text((6, y + 20), f"{r['style']} / {r['palette']}", fill=(170, 170, 190))
                    dr.text((6, y + 36), f"{r['size']}x{r['size']} f{r['frames']} {r['ms']}ms", fill=(140, 140, 160))
                    sheet.paste(s.convert('RGB'), (196, y))
                    y += s.height + 8
                name = f"{cat}_{mode}_{p // per + 1:02d}.png"
                sheet.save(os.path.join(out_dir, name))
                sheets[name] = sheet
    gr = ground()
    sel = [(r, g) for r, g in zip(rows, gens) if r['category'] == 'effect']
    per = 20
    for p in range(0, len(sel), per):
        part = sel[p:p + per]
        cols = 4; cw = 2 * (TILED_N * 32 + 4) + 8; ch = TILED_N * 32 + 22
        sheet = Image.new('RGB', (cols * cw, ((len(part) + cols - 1) // cols) * ch), (12, 12, 16))
        dr = ImageDraw.Draw(sheet)
        for i, (r, g) in enumerate(part):
            x0 = (i % cols) * cw; y0 = (i // cols) * ch
            st = g['stats']
            dr.text((x0 + 4, y0 + 3), f"{r['category'][0]}{r['id']} {r['name']}  [{r['use']}]  clear {st['clear_min']:.0%}"
                    f"  tiled {st['tiled_min']:.0%}", fill=(255, 220, 120))
            for j, fr in enumerate((int(round((g['phases'] - 1) * 0.3)), int(round((g['phases'] - 1) * 0.6)))):
                bg_ = Image.fromarray(gr, 'RGBA')
                bg_.alpha_composite(Image.fromarray(tiled(g, fr), 'RGBA'))
                sheet.paste(bg_.convert('RGB'), (x0 + 4 + j * (TILED_N * 32 + 4), y0 + 18))
        name = f"tiled_{p // per + 1:02d}.png"
        sheet.save(os.path.join(out_dir, name))
        sheets[name] = sheet
    if overview:
        # one mid-animation frame per thing, packed in a grid, kept small (jpg < 1 MB)
        cells = []
        for r, g in zip(rows, gens):
            k = (g['phases'] // 3, 2, 1) if r['category'] == 'missile' else (int(g['phases'] * 0.35), 0, 0)
            fr = Image.fromarray(g['frames'][k], 'RGBA')
            if g['w'] == 1:
                fr = fr.resize((64, 64), Image.NEAREST)
            cells.append((r, fr))
        cols = 16; cw = 72; ch = 84
        rows_ = (len(cells) + cols - 1) // cols
        ov = Image.new('RGBA', (cols * cw, rows_ * ch + 20), (12, 12, 16, 255))
        dr = ImageDraw.Draw(ov)
        dr.text((4, 4), f'gen_effects.py: {len(cells)} procedurally drawn effects / missiles (mid-animation frame)', fill=(255, 220, 120))
        for i, (r, fr) in enumerate(cells):
            x = (i % cols) * cw; y = 20 + (i // cols) * ch
            tile = Image.new('RGBA', (64, 64), bg); tile.alpha_composite(fr)
            ov.alpha_composite(tile, (x + 4, y + 2))
            dr.text((x + 4, y + 68), (r['name'] if r['mode'] == 'append' else f"{r['category'][0]}{r['id']}")[:11], fill=(180, 180, 200))
        os.makedirs(os.path.dirname(os.path.abspath(overview)), exist_ok=True)
        ov.convert('RGB').save(overview, quality=85)
        assert os.path.getsize(overview) < 1 << 20, 'overview jpg too large'
    return sorted(sheets)


# --------------------------------------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat', required=True); ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--spec', default=os.path.join(HERE, 'fx_custom.csv'))
    ap.add_argument('--preview', default=None, help='directory for PNG filmstrip sheets')
    ap.add_argument('--overview', default=None, help='small overview jpg (e.g. fx_sheets/custom_overview.jpg)')
    ap.add_argument('--lua-out', default=None); ap.add_argument('--catalog-out', default=None)
    a = ap.parse_args()
    t0 = time.time()
    os.makedirs(a.out_dir, exist_ok=True)
    for p in (a.ours_dat, a.ours_spr):
        assert os.path.abspath(os.path.dirname(p)) != os.path.abspath(a.out_dir), 'out-dir must differ from the input dir'
    rows = read_spec(a.spec)

    od = Dat(a.ours_dat); ospr = Spr(a.ours_spr)
    assert od.variant[0] == 'new' and od.variant[1] and od.variant[2], f'expected a 10.98 dat (u32 sprites, animator): {od.variant}'
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    ne0, nm0 = len(od.effects), len(od.missiles)
    assert ne0 >= STOCK_EFFECTS and nm0 >= STOCK_MISSILES, (ne0, nm0)
    for cat, have in (('effect', ne0), ('missile', nm0)):
        app = [r['id'] for r in rows if r['category'] == cat and r['mode'] == 'append']
        stock = STOCK_EFFECTS if cat == 'effect' else STOCK_MISSILES
        # stock pair, or an earlier output of this script (fewer appended ids than the spec: the new ones are added)
        assert have >= stock, f'{cat}s in input: {have}; expected at least {stock}'

    # --- 1. draw
    gens = [render_row(r) for r in rows]
    print(f'drew {len(rows)} things ({sum(len(g["frames"]) for g in gens)} frames) in {time.time() - t0:.1f}s')
    print('alpha stats per effect: clear = share of fully transparent pixels per frame (worst / mean over frames and '
          'pattern variants); tiled = share of the inner 5x5 of a 7x7 area left uncovered (worst / mean frame); '
          'last = coverage of the last frame; cut = alpha threshold used')
    srows = []
    for r, g in zip(rows, gens):
        st = g['stats']
        if st is None:
            continue
        st['tiled_min'], st['tiled_mean'] = tiled_clear(g)
        srows.append([r['id'], r['name'], r['use'], f"{r['size']}x{r['size']}", g['px'] * g['py'], g['phases'],
                      g['phases'] * g['durs'][0], f"{st['clear_min']:.2f}", f"{st['clear_mean']:.2f}",
                      f"{st['tiled_min']:.2f}", f"{st['tiled_mean']:.2f}", f"{st['last_cover']:.2f}", st['cut']])
        print(f"  e{r['id']:<4} {r['name'][:24]:<24} {r['use']:<6} {r['size']}x{r['size']} var {g['px'] * g['py']} "
              f"{g['phases'] * g['durs'][0]:>3}ms  clear {st['clear_min']:.0%}/{st['clear_mean']:.0%}  "
              f"tiled {st['tiled_min']:.0%}/{st['tiled_mean']:.0%}  last {st['last_cover']:.0%}  cut {st['cut']}")
    with open(os.path.join(a.out_dir, 'fx_alpha_stats.csv'), 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['id', 'name', 'use', 'size', 'variants', 'frames', 'ms_total', 'clear_min', 'clear_mean',
                    'tiled_clear_min', 'tiled_clear_mean', 'last_frame_cover', 'cut'])
        w.writerows(srows)
    area = [x for x in srows if x[2] == 'area']
    print(f'area effects: {len(area)}; worst per-frame clear {min(float(x[7]) for x in area):.0%} '
          f'(target {MIN_CLEAR:.0%}); worst tiled clear {min(float(x[9]) for x in area):.0%}; '
          f'mean tiled clear {sum(float(x[10]) for x in area) / len(area):.0%}')
    assert all(float(x[7]) >= MIN_CLEAR for x in area), 'an area effect frame is below MIN_CLEAR'

    # --- 2. sprite records (dedupe inside the new set and against the input spr)
    recs = {}                                   # record -> None (ordered set)
    tiles = []                                  # per row: list of record-or-None in dat sprite order
    for r, g in zip(rows, gens):
        T = Thing_(g)
        ids = [None] * (g['w'] * g['h'] * g['px'] * g['py'] * g['phases'])
        for (ph, x, y), img in g['frames'].items():
            for (ww, hh), tile in tiles_of(img, g['w'], g['h']).items():
                rec = encode_sprite(tile)
                ids[sprite_index(T, x, y, 0, 0, ph, ww, hh)] = rec
                if rec is not None:
                    recs.setdefault(rec, None)
        tiles.append(ids)
    mb = np.frombuffer(ospr.m, dtype=np.uint8)
    offs = ospr.offs.astype(np.int64)
    nzi = np.nonzero(offs)[0]
    lens = 5 + mb[offs[nzi] + 3].astype(np.int64) + (mb[offs[nzi] + 4].astype(np.int64) << 8)
    want = {}
    for rec in recs:
        want.setdefault(len(rec), {})[hashlib.md5(rec).digest()] = rec
    existing = {}
    cand = np.nonzero(np.isin(lens, np.array(list(want), np.int64)))[0]
    for i in cand:
        o = int(offs[nzi[i]]); ln = int(lens[i])
        rec = bytes(ospr.m[o:o + ln])
        hit = want[ln].get(hashlib.md5(rec).digest())
        if hit is not None and hit == rec and rec not in existing:
            existing[rec] = int(nzi[i]) + 1
    base = ospr.count
    newrecs, rec_id = [], {}
    for rec in recs:
        if rec in existing:
            rec_id[rec] = existing[rec]
        else:
            newrecs.append(rec); rec_id[rec] = base + len(newrecs)

    # --- 3. dat
    entries = {}
    for r, g, ids in zip(rows, gens, tiles):
        sids = [rec_id[x] if x is not None else 0 for x in ids]
        entries[(r['category'], r['id'])] = build_entry(g, sids, 1 if r['category'] == 'effect' else 0)
    d = od.data
    e0 = od.effects[0].raw[0]
    assert od.outfits[-1].raw[1] == e0 and od.effects[-1].raw[1] == od.missiles[0].raw[0] and od.missiles[-1].raw[1] == len(d)
    out = bytearray(d[:e0])
    counts = {}
    for cat, lst in (('effect', od.effects), ('missile', od.missiles)):
        n = len(lst)
        for t in lst:
            out += entries.get((cat, t.id), d[t.raw[0]:t.raw[1]])
        for r in rows:
            if r['category'] == cat and r['id'] > n:
                assert r['id'] == n + 1, (cat, r['id'], n)
                out += entries[(cat, r['id'])]; n += 1
        counts[cat] = n
    struct.pack_into('<HH', out, 8, counts['effect'], counts['missile'])
    open(os.path.join(a.out_dir, 'Tibia.dat'), 'wb').write(out)

    # --- 4. spr (streamed: bigger table, old records shifted by 4*n, new records appended)
    m = ospr.m; cnt = ospr.count; nn = len(newrecs)
    old_table_end = 8 + 4 * cnt
    toffs = ospr.offs.astype('<u8').copy(); toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur); cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(a.out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn)); f.write(table.tobytes())
        pos = old_table_end
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)]); pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    n_rep_e = sum(1 for r in rows if r['category'] == 'effect' and r['mode'] == 'replace')
    n_rep_m = sum(1 for r in rows if r['category'] == 'missile' and r['mode'] == 'replace')
    print(f'dat: {n_rep_e} effects + {n_rep_m} missiles replaced in place, effects {ne0} -> {counts["effect"]}, '
          f'missiles {nm0} -> {counts["missile"]}; spr: {len(recs)} distinct sprites, {nn} appended, '
          f'{len(recs) - nn} reused from the input spr ({cnt} -> {cnt + nn})')

    # --- 5. lua / catalog
    lua = lua_text(rows)
    open(os.path.join(a.out_dir, 'chaos_fx.lua'), 'w').write(lua)
    write_catalog(rows, os.path.join(a.out_dir, 'effects_catalog.csv'))
    if a.lua_out:
        if os.path.exists(a.lua_out):
            old, new = lua_ids(open(a.lua_out).read()), lua_ids(lua)
            if any(new.get(k) != v for k, v in old.items()):     # new names may be added; none may move or vanish
                diff = sorted(set(old.items()) - set(new.items()))
                sys.exit(f'refusing to write {a.lua_out}: chaos names/ids differ from the existing file: {diff[:10]}')
        open(a.lua_out, 'w').write(lua)
        print('wrote', a.lua_out)
    if a.catalog_out:
        write_catalog(rows, a.catalog_out); print('wrote', a.catalog_out)

    # --- 6. verification
    md = Dat(os.path.join(a.out_dir, 'Tibia.dat')); ms = Spr(os.path.join(a.out_dir, 'Tibia.spr'))
    assert md.variant == od.variant, md.variant
    assert md.counts == (od.counts[0], od.counts[1], counts['effect'], counts['missile']), md.counts
    assert len(md.outfits) == len(od.outfits) and len(md.items) == len(od.items)
    assert ms.count == cnt + nn and md.max_sprite <= ms.count and ms.alpha
    assert md.data[:8] == od.data[:8] and md.data[12:e0] == od.data[12:e0], 'items/outfits changed'
    nframes = 0
    for r, g in zip(rows, gens):
        t = (md.effects if r['category'] == 'effect' else md.missiles)[r['id'] - 1]
        assert (t.w, t.h, t.layers, t.px, t.py, t.pz, t.phases) == (g['w'], g['h'], 1, g['px'], g['py'], 1, g['phases']), r['name']
        assert t.anim is None or list(t.anim[3]) == [x for dd in g['durs'] for x in (dd, dd)], r['name']
        assert t.flags == ({'light': g['light']} if g['light'] else {}), (r['name'], t.flags)
        back = render_back(t, ms)
        assert back.keys() == g['frames'].keys()
        for k, img in g['frames'].items():
            nframes += 1
            if not np.array_equal(back[k], img):
                raise SystemExit(f'MISMATCH {r["category"]} {r["id"]} {r["name"]} frame {k}')
    touched = {(r['category'], r['id']) for r in rows}
    kept = 0
    for cat, lo, lm in (('effect', od.effects, md.effects), ('missile', od.missiles, md.missiles)):
        for to in lo:
            if (cat, to.id) not in touched:
                tm = lm[to.id - 1]
                assert od.data[to.raw[0]:to.raw[1]] == md.data[tm.raw[0]:tm.raw[1]], (cat, to.id)
                kept += 1
    random.seed(1)
    for sid in random.sample(range(1, cnt + 1), min(3000, cnt)) + [1, cnt]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    print(f'verified: output dat parses ({md.variant}); {len(rows)} written things x all frames/patterns = {nframes} '
          f'frames pixel-identical to the generated art; items/outfits byte-identical, {kept} other effects/missiles '
          f'byte-identical; 3000 sampled old sprites unchanged; {ms.count} sprites')

    if a.preview or a.overview:
        sheets = preview(rows, gens, a.preview or os.path.join(a.out_dir, 'preview'), a.overview)
        print(f'preview: {len(sheets)} sheets in {a.preview or os.path.join(a.out_dir, "preview")}'
              + (f'; overview {a.overview} ({os.path.getsize(a.overview) // 1024} KB)' if a.overview else ''))
    print(f'done in {time.time() - t0:.1f}s')


if __name__ == '__main__':
    main()
