"""Drawing helpers for gen_dark_tiles.py: periodic noise, periodic Voronoi cells, height-map lighting, colour ramps,
shape fields and careful downsampling (hi-res drawing -> 64 px masters -> 32 px sprites).

Everything works on float32 numpy arrays. Colours are 0..1 RGB, images are (H, W, 4) straight-alpha RGBA.
Textures for grounds are periodic: every function that takes `period` wraps, so a 4x4-tile texture tiles with itself
and with its neighbours (the client picks the pattern by tile position, x % 4 and y % 4).
"""
import numpy as np

LIGHT = np.array([-0.52, -0.62, 0.59], np.float32)   # from the upper left, like the stock sprites
LIGHT /= np.linalg.norm(LIGHT)


def hexcol(s):
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def ramp(v, stops):
    """map v (0..1 array) through colour stops: list of hex strings (evenly spaced) or (pos, hex) pairs."""
    if isinstance(stops[0], str):
        stops = [(i / (len(stops) - 1), s) for i, s in enumerate(stops)]
    pos = np.array([p for p, _ in stops], np.float32)
    cols = np.stack([hexcol(c) for _, c in stops])
    v = np.clip(v, 0, 1)
    out = np.empty(v.shape + (3,), np.float32)
    for k in range(3):
        out[..., k] = np.interp(v, pos, cols[:, k])
    return out


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def sstep(a, b, x):
    return smooth((x - a) / (b - a))


def grid(h, w, ox=0.0, oy=0.0):
    """pixel-centre coordinate arrays (Y, X) of an h x w canvas whose top-left pixel is at (ox, oy)"""
    y = np.arange(h, dtype=np.float32) + 0.5 + oy
    x = np.arange(w, dtype=np.float32) + 0.5 + ox
    return np.meshgrid(y, x, indexing='ij')


class PNoise:
    """value noise, periodic in `period` pixels with `cells` lattice cells per period (both axes)"""

    def __init__(self, seed, cells, period):
        self.g = np.random.default_rng(seed).random((cells, cells)).astype(np.float32)
        self.n = cells
        self.p = float(period)

    def __call__(self, X, Y):
        n = self.n
        u = X * (n / self.p)
        v = Y * (n / self.p)
        x0 = np.floor(u); y0 = np.floor(v)
        fx = smooth(u - x0); fy = smooth(v - y0)
        x0 = x0.astype(np.int64) % n; y0 = y0.astype(np.int64) % n
        x1 = (x0 + 1) % n; y1 = (y0 + 1) % n
        g = self.g
        a = g[y0, x0] * (1 - fx) + g[y0, x1] * fx
        b = g[y1, x0] * (1 - fx) + g[y1, x1] * fx
        return a * (1 - fy) + b * fy


class FBM:
    def __init__(self, seed, cells, period, octaves=4, gain=0.5):
        self.layers = [PNoise(seed * 31 + i, cells * (2 ** i), period) for i in range(octaves)]
        self.gain = gain

    def __call__(self, X, Y):
        v = 0.0; amp = 1.0; tot = 0.0
        for L in self.layers:
            v = v + amp * L(X, Y)
            tot += amp; amp *= self.gain
        return v / tot


def ridged(f):
    """ridge lines from a 0..1 noise value: 1 on the 0.5 iso-line"""
    return 1 - np.abs(f * 2 - 1)


class Voronoi:
    """periodic jittered-grid Voronoi: n x n cells per `period` pixels"""

    def __init__(self, seed, n, period, jitter=0.85):
        r = np.random.default_rng(seed)
        self.n = n
        self.p = float(period)
        self.pts = (0.5 + (r.random((n, n, 2)) - 0.5) * jitter).astype(np.float32)
        self.val = r.random((n, n)).astype(np.float32)

    def __call__(self, X, Y):
        """returns F1, F2 (pixels), id (int: cy * n + cx of the nearest point), dx, dy (to the nearest point)"""
        n, p = self.n, self.p
        cs = p / n
        cx = np.floor(X / cs).astype(np.int64)
        cy = np.floor(Y / cs).astype(np.int64)
        f1 = np.full(X.shape, 1e9, np.float32); f2 = np.full(X.shape, 1e9, np.float32)
        idn = np.zeros(X.shape, np.int64)
        ndx = np.zeros(X.shape, np.float32); ndy = np.zeros(X.shape, np.float32)
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                gx = cx + ox; gy = cy + oy
                wx = gx % n; wy = gy % n
                px = (gx + self.pts[wy, wx, 0]) * cs
                py = (gy + self.pts[wy, wx, 1]) * cs
                dx = px - X; dy = py - Y
                d = np.sqrt(dx * dx + dy * dy)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                idn = np.where(closer, wy * n + wx, idn)
                ndx = np.where(closer, dx, ndx); ndy = np.where(closer, dy, ndy)
                f1 = np.where(closer, d, f1)
        return f1, f2, idn, ndx, ndy


def gradient(h, wrap):
    if wrap:
        gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
        gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    else:
        gy, gx = np.gradient(h)
    return gx, gy


def lighting(h, wrap, strength=1.0):
    """lambert term of a height map (pixels of height per pixel) lit from the upper left, plus a specular term"""
    gx, gy = gradient(h * strength, wrap)
    nz = np.ones_like(h)
    norm = np.sqrt(gx * gx + gy * gy + nz)
    nx, ny, nz = -gx / norm, -gy / norm, nz / norm
    lam = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
    # half vector with the viewer straight above
    hv = LIGHT + np.array([0, 0, 1], np.float32)
    hv /= np.linalg.norm(hv)
    spec = np.clip(nx * hv[0] + ny * hv[1] + nz * hv[2], 0, 1)
    return np.clip(lam, 0, 1), spec


def shade(albedo, h, wrap, strength=1.0, ambient=0.45, diffuse=0.75, spec=0.0, shininess=24, flat=None):
    lam, sp = lighting(h, wrap, strength)
    flat_lam = LIGHT[2]
    lit = ambient + diffuse * (lam / flat_lam) * (1 - ambient)
    out = albedo * lit[..., None]
    if not np.isscalar(spec) or spec:
        s = spec if np.isscalar(spec) else spec[..., None]
        out = out + s * (sp ** shininess)[..., None]
    return np.clip(out, 0, 1)


def blur(a, r, wrap):
    """box blur radius r (separable, repeated twice ~ gaussian)"""
    if r <= 0:
        return a
    for _ in range(2):
        for ax in (0, 1):
            if wrap:
                acc = a.copy()
                for k in range(1, r + 1):
                    acc = acc + np.roll(a, k, ax) + np.roll(a, -k, ax)
                a = acc / (2 * r + 1)
            else:
                pad = [(0, 0)] * a.ndim
                pad[ax] = (r, r)
                p = np.pad(a, pad, mode='edge')
                c = np.cumsum(p, axis=ax, dtype=np.float64)
                zero = np.zeros_like(np.take(c, [0], axis=ax))
                c = np.concatenate([zero, c], axis=ax)
                n = a.shape[ax]
                hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=ax)
                lo = np.take(c, np.arange(0, n), axis=ax)
                a = ((hi - lo) / (2 * r + 1)).astype(np.float32)
    return a


def erode_dist(mask, steps):
    """inside distance (in 4-neighbour steps, capped at `steps`) of a boolean mask; outside = 0"""
    d = np.zeros(mask.shape, np.float32)
    cur = mask.copy()
    for i in range(steps):
        d += cur
        nb = cur.copy()
        nb[1:, :] &= cur[:-1, :]; nb[:-1, :] &= cur[1:, :]
        nb[:, 1:] &= cur[:, :-1]; nb[:, :-1] &= cur[:, 1:]
        cur = nb
    return d


def dilate(mask, steps):
    cur = mask.copy()
    for _ in range(steps):
        nb = cur.copy()
        nb[1:, :] |= cur[:-1, :]; nb[:-1, :] |= cur[1:, :]
        nb[:, 1:] |= cur[:, :-1]; nb[:, :-1] |= cur[:, 1:]
        cur = nb
    return cur


def over(dst, src):
    """straight-alpha 'over' of two RGBA float images"""
    sa = src[..., 3:4]; da = dst[..., 3:4]
    oa = sa + da * (1 - sa)
    rgb = np.where(oa > 1e-6, (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6), 0)
    return np.concatenate([rgb, oa], axis=-1).astype(np.float32)


def rgba(rgb, alpha):
    return np.concatenate([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]], axis=-1).astype(np.float32)


# ------------------------------------------------------------------------------------------- shapes (signed fields)
def seg_dist(X, Y, ax, ay, bx, by):
    """distance to segment a-b and the position t (0..1) along it"""
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy + 1e-9
    t = np.clip(((X - ax) * vx + (Y - ay) * vy) / L2, 0, 1)
    px, py = ax + t * vx - X, ay + t * vy - Y
    return np.sqrt(px * px + py * py), t


def poly_mask(X, Y, pts):
    """inside test of a polygon (even-odd), pts = [(x, y), ...]"""
    inside = np.zeros(X.shape, bool)
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]; x2, y2 = pts[(i + 1) % n]
        cond = ((y1 > Y) != (y2 > Y))
        xin = (x2 - x1) * (Y - y1) / ((y2 - y1) if y2 != y1 else 1e-9) + x1
        inside ^= cond & (X < xin)
    return inside


# ------------------------------------------------------------------------------------------- resampling
def box_down(img, f):
    """premultiplied box average by an integer factor; img (H, W, 4) straight alpha -> straight alpha"""
    H, W = img.shape[:2]
    a = img[..., 3:4]
    pm = np.concatenate([img[..., :3] * a, a], axis=-1)
    pm = pm.reshape(H // f, f, W // f, f, 4).mean(axis=(1, 3))
    al = pm[..., 3:4]
    rgb = np.where(al > 1e-6, pm[..., :3] / np.maximum(al, 1e-6), 0)
    return np.concatenate([rgb, al], axis=-1).astype(np.float32)


def sharpen(img, amount, wrap):
    """unsharp mask on RGB (alpha untouched); 3x3 neighbourhood"""
    rgb = img[..., :3]
    if wrap:
        b = (rgb + np.roll(rgb, 1, 0) + np.roll(rgb, -1, 0) + np.roll(rgb, 1, 1) + np.roll(rgb, -1, 1)) / 5
    else:
        p = np.pad(rgb, ((1, 1), (1, 1), (0, 0)), mode='edge')
        b = (p[1:-1, 1:-1] + p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 5
    out = img.copy()
    out[..., :3] = np.clip(rgb + amount * (rgb - b), 0, 1)
    return out


def finish(img, f, wrap, amount, cut=0.5):
    """hi-res RGBA -> downsampled RGBA uint8 with binary alpha (crisp edges, no fringe)"""
    d = box_down(img, f)
    d = sharpen(d, amount, wrap)
    a = d[..., 3]
    on = a >= cut
    out = np.zeros(d.shape, np.uint8)
    out[..., :3] = np.round(np.clip(d[..., :3], 0, 1) * 255).astype(np.uint8)
    out[..., 3] = np.where(on, 255, 0)
    out[~on] = 0
    return out
