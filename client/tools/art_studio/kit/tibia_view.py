"""The Tibia oblique projection, as a tiny ray-marcher of signed distances.

A point of the world at height h is drawn h/1.5 UP and h/1.5 to the LEFT of where it stands; the ground is seen from
straight above, never squashed; you see the top and the SOUTH and EAST faces of things. The light comes from the
top-left. Everything here works on numpy arrays of points (N, 3): body coordinates u forward, v the creature's right,
h up, in pixels of the frame.
"""
import numpy as np
from PIL import Image

GROUND = np.array((39.5, 40.0))  # where a 1-tile creature stands in a 64 frame (the tile at the bottom-right)
AO_SCALE = 1.3                   # the reach of the ambient occlusion probes


def unit(*v):
    v = np.asarray(v[0] if len(v) == 1 else v, float)
    return v / np.linalg.norm(v)


LIGHT = unit(-0.55, -0.75, 1.0)            # from the top-left of the screen, and above
TOWARD_VIEW = unit(1 / 1.5, 1 / 1.5, 1.0)  # a screen pixel is the ray along this; higher is nearer
HALF = unit(LIGHT + TOWARD_VIEW)
SCR_E = unit(np.array((1.0, 0, 0)) - TOWARD_VIEW[0] * TOWARD_VIEW)       # the world directions of screen right
SCR_S = unit(np.array((0, 1.0, 0)) - TOWARD_VIEW[1] * TOWARD_VIEW)       # and screen down
PAINT_LIGHT = unit(-0.75, -0.30, 0.60)    # screen x, screen y, toward the viewer: the light a pixel artist paints by

FACINGS = {"north": (0, -1), "east": (1, 0), "south": (0, 1), "west": (-1, 0)}   # x east, y south


# ------------------------------------------------------------------ hashes (integers: a sine hash makes blocks)

def hash01(*ints):
    h = np.zeros(np.broadcast(*ints).shape, np.uint64)
    for k, a in enumerate(ints):
        h ^= (np.asarray(a).astype(np.int64).astype(np.uint64) + np.uint64(0x9E3779B97F4A7C15 * (k + 1) & (2 ** 64 - 1)))
        h = (h ^ (h >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        h = (h ^ (h >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        h ^= h >> np.uint64(31)
    return (h >> np.uint64(11)).astype(np.float64) / float(2 ** 53)


def value_noise(P, cell, salt=0):
    """Smooth noise in [-1, 1] over 3D points (trilinear value noise)."""
    q = P / cell
    g = np.floor(q).astype(np.int64)
    f = q - g
    f = f * f * (3 - 2 * f)
    out = np.zeros(len(P))
    for ox in (0, 1):
        for oy in (0, 1):
            for oz in (0, 1):
                w = (f[:, 0] if ox else 1 - f[:, 0]) * (f[:, 1] if oy else 1 - f[:, 1]) * (f[:, 2] if oz else 1 - f[:, 2])
                out += w * hash01(g[:, 0] + ox, g[:, 1] + oy, g[:, 2] + oz, np.full(len(P), salt))
    return out * 2 - 1


# ------------------------------------------------------------------ distance primitives (body coordinates)

def sd_ellipsoid(P, c, r):
    q = (P - c) / r
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / r, axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_cone(P, a, b, ra, rb):
    """A round cone from `a` (radius ra) to `b` (radius rb): limbs, horns, spikes, tails."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ab = b - a
    L2 = ab @ ab
    t = np.clip(((P - a) @ ab) / L2, 0, 1)
    d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
    return (d - (ra + (rb - ra) * t)) * 0.9


def sd_box(P, c, half, round_=0.0):
    """An axis-aligned box (body axes) with rounded edges: blades, planks, plates."""
    q = np.abs(P - np.asarray(c, float)) - (np.asarray(half, float) - round_)
    return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - round_


def smin(a, b, k):
    """Smooth union INSIDE one part only; between parts use plain np.minimum (the animation moves them apart)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


# ------------------------------------------------------------------ the camera

class Facing:
    def __init__(self, name, ground=None):
        f = np.array(FACINGS[name], float)
        self.F = f
        self.R = np.array((-f[1], f[0]))
        self.ground = GROUND if ground is None else np.asarray(ground, float)

    def to_body(self, W):
        d = W[:, :2] - self.ground
        return np.stack([d @ self.F, d @ self.R, W[:, 2]], 1)

    def dir_to_body(self, D):
        return np.stack([D[:, :2] @ self.F, D[:, :2] @ self.R, D[:, 2]], 1)


def march(fc, origins, direction, max_t, sdf, steps=160, eps=0.015):
    """Sphere tracing along `direction` (world) from each origin; returns the hit mask and the distance."""
    t = np.zeros(len(origins))
    hit = np.zeros(len(origins), bool)
    alive = np.ones(len(origins), bool)
    for _ in range(steps):
        idx = np.nonzero(alive)[0]
        if not len(idx):
            break
        X = fc.to_body(origins[idx] + t[idx, None] * direction)
        d = sdf(X)
        done = d < eps
        hit[idx[done]] = True
        t[idx] += np.maximum(d, eps * 0.5) * 0.85
        alive[idx[done | (t[idx] > max_t)]] = False
    return hit, t


def soft_shadow(fc, X0, sdf, k=7.0, max_t=30.0, steps=70):
    """1 lit .. 0 in the shadow, toward the light from body points X0 (already lifted off the surface)."""
    Lb = fc.dir_to_body(LIGHT[None, :])[0]
    res = np.ones(len(X0))
    t = np.full(len(X0), 0.35)
    alive = np.ones(len(X0), bool)
    for _ in range(steps):
        idx = np.nonzero(alive)[0]
        if not len(idx):
            break
        d = sdf(X0[idx] + t[idx, None] * Lb)
        res[idx] = np.minimum(res[idx], np.clip(k * d / t[idx], 0, 1))
        t[idx] += np.clip(d, 0.12, 2.0)
        alive[idx[(res[idx] < 0.02) | (t[idx] > max_t)]] = False
    return res ** 1.3


def normals(X, sdf, e=0.06):
    n = np.zeros_like(X)
    for i in range(3):
        o = np.zeros(3)
        o[i] = e
        n[:, i] = sdf(X + o) - sdf(X - o)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)


def occlusion(X, n, sdf):
    S = AO_SCALE
    occ = np.zeros(len(X))
    for i, hgt in enumerate((0.5, 1.1, 2.0, 3.2)):
        d = sdf(X + n * hgt * S)
        occ += (hgt * S - np.minimum(d, hgt * S)) / (hgt * S) * (0.5 ** i)
    return np.clip(occ / 1.6, 0, 1)


# ------------------------------------------------------------------ colour ramps (blended in OKLab)

_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])


def srgb_to_oklab(rgb):
    c = np.asarray(rgb, float) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return np.cbrt(lin @ _M1.T) @ _M2.T


def oklab_to_srgb(lab):
    lms = (np.asarray(lab, float) @ np.linalg.inv(_M2).T) ** 3
    lin = np.clip(lms @ np.linalg.inv(_M1).T, 0, 1)
    c = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)
    return c * 255.0


def ramp(anchors, n):
    """`n` tones from dark to light through the anchor colours (hue-shift them: cold shade, warm light)."""
    lab = np.array([srgb_to_oklab(c) for c in anchors])
    t = np.linspace(0, len(anchors) - 1, n)
    i = np.clip(np.floor(t).astype(int), 0, len(anchors) - 2)
    f = (t - i)[:, None]
    out = lab[i] * (1 - f) + lab[i + 1] * f
    return np.clip(oklab_to_srgb(out).round(), 0, 255).astype(np.uint8)


# ------------------------------------------------------------------ small helpers

def tidy_silhouette(on):
    """Fill the 1 px notches of an edge (an empty pixel with filled neighbours on three sides)."""
    on = on.copy()
    for _ in range(2):
        P = np.pad(on, 1)
        nb = P[:-2, 1:-1].astype(int) + P[2:, 1:-1] + P[1:-1, :-2] + P[1:-1, 2:]
        on |= (~on) & (nb >= 3)
    return on


def grass_tile(w, h):
    """A plain grass ground to judge a sprite on (a flat field with a little noise)."""
    yy, xx = np.mgrid[0:h, 0:w]
    nz = hash01(yy // 2, xx // 2, np.full_like(yy, 3)) * 0.5 + hash01(yy // 5, xx // 5, np.full_like(yy, 4)) * 0.5
    base = np.array((62, 104, 46))
    col = base[None, None, :] * (0.86 + 0.24 * nz[..., None])
    a = np.dstack([np.clip(col, 0, 255), np.full((h, w), 255)]).astype(np.uint8)
    return Image.fromarray(a, "RGBA")
