#!/usr/bin/env python3
# Kept as the record of how the approved style sample (lich_soul_drain) was made: it ran in the sample's own work
# folder. gen_necro_fx.py build rebuilds the effect from soul_drain_paint.png (the one repaint it produced).
"""Soul Drain: a Necromancer magic effect, 64x64, 8 frames, drawn in Python (shapes on a 4x supersample,
quantized per material to hard ramps, 1 px dark outline). Oblique view: the target tile is the frame's
bottom-right tile (centre 48,48); a point at height h is drawn h/1.5 up and h/1.5 left.

    python3 -I soul_drain.py        # -> work/soul_drain.npz (8,64,64,4) + work/soul_drain_look.png
"""
import math
import os
import sys

sys.dont_write_bytecode = True
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(HERE, "work")
N, SS = 64, 4
C = np.array((48.0, 48.0))            # the target tile's centre on the ground
TOP = 21.0                            # where the souls meet (height)

RAMPS = {   # dark -> light; [0] is the outline
    "void": [(34, 10, 58), (70, 24, 118), (118, 52, 190), (170, 104, 240), (222, 186, 255)],
    "soul": [(12, 44, 24), (34, 104, 48), (78, 180, 70), (150, 234, 104), (220, 255, 182)],
    "core": [(70, 24, 118), (182, 140, 250), (236, 222, 255), (255, 255, 255)],
    "bone": [(34, 24, 40), (110, 100, 112), (172, 166, 164), (222, 216, 200)],
}
ORDER = ["void", "bone", "soul", "core"]          # later wins where both cover


def scr(x, y, h):
    """ground (x, y) at height h -> screen."""
    return np.array((x - h / 1.5, y - h / 1.5))


class Canvas:
    def __init__(self):
        n = N * SS
        yy, xx = np.mgrid[0:n, 0:n]
        self.X = (xx + 0.5) / SS
        self.Y = (yy + 0.5) / SS
        self.I = {m: np.zeros((n, n)) for m in ORDER}

    def put(self, mat, inside, val):
        self.I[mat] = np.where(inside, np.maximum(self.I[mat], val), self.I[mat])

    def disc(self, mat, c, r, lo=0.35, hi=1.0, lit=0.35):
        dx, dy = self.X - c[0], self.Y - c[1]
        d = np.hypot(dx, dy)
        inside = d <= r
        rel = np.clip(1 - d / max(r, 1e-6), 0, 1)
        # top-left light: brighter up-left
        tl = np.clip((-dx - dy) / (r * 1.414 + 1e-6), -1, 1)
        self.put(mat, inside, lo + (hi - lo) * rel + lit * tl * 0.5)

    def capsule(self, mat, a, b, ra, rb, lo=0.3, hi=0.9):
        a, b = np.asarray(a, float), np.asarray(b, float)
        ab = b - a
        L2 = max(ab @ ab, 1e-9)
        t = np.clip(((self.X - a[0]) * ab[0] + (self.Y - a[1]) * ab[1]) / L2, 0, 1)
        px, py = a[0] + t * ab[0], a[1] + t * ab[1]
        d = np.hypot(self.X - px, self.Y - py)
        r = ra + (rb - ra) * t
        inside = d <= r
        self.put(mat, inside, lo + (hi - lo) * (1 - t) * np.clip(1 - d / np.maximum(r, 1e-6), 0, 1) + 0.1)

    def ring(self, mat, c, R, w, start=0.0, span=2 * math.pi, val=0.75):
        dx, dy = self.X - c[0], self.Y - c[1]
        d = np.hypot(dx, dy)
        ang = (np.arctan2(dy, dx) - start) % (2 * math.pi)
        inside = (np.abs(d - R) <= w / 2) & (ang <= span)
        tl = np.clip((-dx - dy) / (R * 1.414), -1, 1)
        self.put(mat, inside, val + 0.18 * tl)

    def spark(self, mat, c, s, val=1.0):
        """a 4-point star: a plus of arm s px."""
        for dx, dy in ((1, 0), (0, 1)):
            self.capsule(mat, c - np.array((dx, dy)) * s, c + np.array((dx, dy)) * s, 0.45, 0.45, val, val)
        self.disc(mat, c, 0.8, val, val, 0)

    def finish(self):
        """-> 64x64 RGBA: per pixel the top material covering >= 40% of it, its mean value on a ramp, outlined."""
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


RUNE_ANGLES = [i * 2 * math.pi / 6 for i in range(6)]


def rune(cv, c, ang, val):
    """a small angular glyph on the ring (3 strokes), facing out."""
    u = np.array((math.cos(ang), math.sin(ang)))
    v = np.array((-u[1], u[0]))
    p = c + u * 9.6
    cv.capsule("void", p - v * 1.5 + u * 1.0, p + v * 1.5 + u * 1.0, 0.5, 0.5, val, val)
    cv.capsule("void", p + u * 1.0, p - u * 1.8, 0.5, 0.5, val, val)
    cv.capsule("void", p - u * 1.8 - v * 1.1, p - u * 1.8 + v * 1.1, 0.45, 0.45, val, val)


def soul_pos(i, p):
    a = RUNE_ANGLES[i] + 0.4 + p * 2.4
    r = 12.0 * (1 - p) ** 1.2
    h = TOP * (p ** 0.85)
    return scr(C[0] + r * math.cos(a), C[1] + r * math.sin(a), h)


def skull(cv, c, s, val):
    """a ghost skull (violet-white) with soul-green sockets; c the cranium centre, s its scale."""
    cv.disc("bone", c, 5.0 * s, 0.35 * val, 1.0 * val, 0.5)
    cv.capsule("bone", c + (0, 3.2 * s), c + (0, 5.2 * s), 3.0 * s, 2.4 * s, 0.3 * val, 0.7 * val)
    for sx in (-1, 1):
        cv.disc("soul", c + (sx * 1.9 * s, 1.0 * s), 1.35 * s, 0.7, 1.0, 0.0)
    cv.disc("void", c + (0, 3.4 * s), 0.7 * s, 0.4, 0.5, 0)


def frame(t, rng):
    cv = Canvas()
    meet = scr(C[0], C[1], TOP)
    # 1. the ground circle draws itself, holds, breaks
    if t <= 5:
        span = (0.4, 0.8, 1.0, 1.0, 1.0, 1.0)[t] * 2 * math.pi
        cv.ring("void", C, 13.2, 2.3, start=-math.pi / 2, span=span, val=0.55 + 0.08 * min(t, 3))
        cv.ring("void", C, 6.2, 1.0, start=math.pi / 2, span=span * 0.9, val=0.4)
        for i, a in enumerate(RUNE_ANGLES):
            if ((a + math.pi / 2) % (2 * math.pi)) <= span:
                rune(cv, C, a + 0.3 * t * 0.0, 0.62 + 0.1 * ((i + t) % 2))
    elif t == 6:
        for i in range(6):
            a0 = RUNE_ANGLES[i] + 0.2
            cv.ring("void", C, 13.2, 1.8, start=a0, span=0.45, val=0.45)
    # 2. the souls rise from the circle and spiral in
    if 1 <= t <= 4:
        p = (t - 1) / 3.6
        for i in range(6):
            q = min(p + 0.05 * (i % 2), 1.0)
            head = soul_pos(i, q)
            trail = [soul_pos(i, max(q - dq, 0)) for dq in (0.06, 0.12, 0.18, 0.24)]
            pts = [head] + trail
            for k, (a, b) in enumerate(zip(pts, pts[1:])):
                cv.capsule("soul", a, b, 2.2 - 0.45 * k, 1.8 - 0.45 * k, 0.7 - 0.12 * k, 0.6 - 0.12 * k)
            cv.disc("soul", head, 2.5, 0.5, 1.0, 0.6)
            cv.disc("core", head + (-0.6, -0.6), 0.9, 0.55, 0.65, 0)
    # 3. they meet: the burst and the skull
    if t == 4:
        cv.disc("soul", meet, 4.0, 0.4, 0.95, 0.4)
        cv.disc("core", meet, 2.2, 0.5, 0.95, 0.3)
    if t == 5:
        for k in range(8):
            a = k * math.pi / 4 + math.pi / 8
            L = 13.5 if k % 2 else 9.5
            cv.capsule("void", meet, meet + L * np.array((math.cos(a), math.sin(a))), 2.0, 0.3, 0.55, 0.9)
        cv.ring("void", meet, 10.5, 1.3, val=0.5)
        cv.disc("soul", meet, 7.2, 0.45, 0.95, 0.5)
        cv.disc("core", meet, 4.2, 0.45, 1.0, 0.3)
    if t == 6:
        cv.disc("void", meet + (0, -0.5), 9.0, 0.2, 0.45, 0.3)
        cv.ring("void", meet, 12.5, 1.6, val=0.65)
        skull(cv, meet + (0, -1.5), 1.4, 1.0)
    if t == 7:
        cv.ring("void", meet, 12.0, 1.0, start=0.3, span=1.1, val=0.45)
        cv.ring("void", meet, 12.0, 1.0, start=2.4, span=1.0, val=0.45)
        cv.ring("void", meet, 12.0, 1.0, start=4.3, span=1.0, val=0.45)
        skull(cv, meet + (-1, -5.0), 1.0, 0.55)
    # 4. sparkles
    nsp = (0, 2, 3, 3, 4, 5, 6, 5)[t]
    for _ in range(nsp):
        if t >= 5:
            a, r = rng.uniform(0, 2 * math.pi), rng.uniform(5, 13 + t)
            c = meet + r * np.array((math.cos(a), math.sin(a)))
        else:
            a, r = rng.uniform(0, 2 * math.pi), rng.uniform(4, 13)
            c = scr(C[0] + r * math.cos(a), C[1] + r * math.sin(a), rng.uniform(2, TOP * 0.8))
        c = np.round(c) + 0.5
        cv.spark("core" if rng.random() < 0.5 else "soul", c, 1.0 + (rng.random() < 0.4), 0.95)
    return cv.finish()


def main():
    rng = np.random.default_rng(13)
    F = np.stack([frame(t, rng) for t in range(8)])
    for t, f in enumerate(F):
        a = f[..., 3] > 0
        if a[63].any() or a[:, 63].any() or a[0].any() or a[:, 0].any():
            print("EDGE TOUCH frame", t)
    os.makedirs(WORK, exist_ok=True)
    np.savez_compressed(os.path.join(WORK, "soul_drain.npz"), frames=F)
    z = 4
    im = Image.new("RGBA", (8 * 64 * z, 64 * z * 2), (36, 33, 34, 255))
    for t, f in enumerate(F):
        im.alpha_composite(Image.fromarray(f, "RGBA").resize((64 * z, 64 * z), Image.NEAREST), (t * 64 * z, 0))
        im.alpha_composite(Image.fromarray(f, "RGBA"), (t * 64 * z, 64 * z + 8))
    p = os.path.join(WORK, "soul_drain_look.png")
    im.convert("RGB").save(p)
    print(p)


if __name__ == "__main__":
    main()
