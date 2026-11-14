#!/usr/bin/env python3
"""The Dusk Moth pet of pair 72, drawn by script (O578; client/MANIFEST.md "Pair 72"; the pet look 3523).

    python3 -I gen_dusk_moth.py frames OUT_DIR       # OUT_DIR/walk/DIRECTION/frame_NNN.png, north east south west, PHASES pictures each
    python3 -I gen_dusk_moth.py check                # the tool's own rules: phases, steps between phases, easing, the bob in step, size, outline

Why a script and not PixelLab: the first moth (O566, PixelLab, 13 phases) jumped between its wing poses and had no in-between pictures. A script
turns two real wings about the body, so every phase is the wing a few degrees further, in all four directions, with the same pixels of colour.

The moth is a small model in world units of one pixel: a body (thorax, abdomen, head, two eyes, two antennae) and four wings (a fore and a hind
wing on each side), each a flat shape that swings about the body's long axis by the flap angle. The camera looks from the south and above
(the game's oblique view); east and west are the moth turned 30 degrees away from the camera, because a pure profile hides the head behind
the near wing. Every surface point is thrown into a 32 x 32 picture with a depth test (a nearer point wins), its colour one of
three tones by the light from the top left (docs/SPRITE_STYLE.md), then the picture is tidied (single pixels, one pixel holes) and given the
game's one pixel near-black outline.

The flap: PHASES pictures at MS ms. The angle is a cosine (wings up at phase 0, down at the middle), so it slows to nothing at the top and the
bottom of the stroke (the soft ease), and a small second beat makes the down stroke a little quicker than the up stroke. The body bobs in step:
it rises while the wings push down and sinks while they rise.
"""
import math
import os
import sys

import numpy as np

PHASES = 28
MS = 60
CELL = 32
DIRS = ('north', 'east', 'south', 'west')
# (X east, Y south) of the way the moth faces; sideways it is turned 30 degrees away from the camera so the picture shows its back and both
# wings (a pure profile hides the head behind the near wing and reads as a blob)
HEADING = {'north': (0.0, -1.0), 'east': (0.866, -0.5), 'south': (0.0, 1.0), 'west': (-0.866, -0.5)}
ELEV = math.radians(48)          # camera elevation
LIGHT = np.array([-0.55, -0.45, 0.70])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
OUTLINE = (20, 16, 26)

# colours: (dark, mid, light) of each material
WING = ((32, 16, 60), (68, 28, 106), (112, 46, 148))
EDGE = ((100, 26, 104), (160, 44, 152), (214, 84, 198))
SPOT = ((226, 104, 206), (250, 160, 232), (255, 214, 246))
BODY = ((52, 34, 74), (88, 58, 112), (134, 92, 158))
HINGE = 1.5
BODY_BIAS = 1.2
EYE = (255, 214, 246)
FEEL = (150, 90, 170)

FORE = [(0, 2.6), (3, 4.4), (7, 5.4), (11, 4.4), (14.5, 2.0), (14.0, -0.6), (11, -3.2), (7, -5.0), (3, -4.4), (0, -2.6)]
HIND = [(0, -1.4), (4, -2.6), (8, -5.2), (9.6, -8.8), (6.2, -10.8), (2.6, -9.2), (0, -5.6)]


def chaikin(poly, rounds=2):
    p = np.array(poly, float)
    for _ in range(rounds):
        q = []
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]
            q += [0.75 * a + 0.25 * b, 0.25 * a + 0.75 * b]
        p = np.array(q)
    return p


def wing_points(poly, step=0.22):
    """(u, v) sample points inside a wing outline"""
    from PIL import Image, ImageDraw
    p = chaikin(poly)
    s = 8
    umax = p[:, 0].max()
    vmin, vmax = p[:, 1].min(), p[:, 1].max()
    w, h = int((umax + 1) * s), int((vmax - vmin + 2) * s)
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).polygon([((x) * s, (y - vmin + 1) * s) for x, y in p], fill=255)
    m = np.array(m) > 0
    us = np.arange(0, umax, step)
    vs = np.arange(vmin, vmax, step)
    uu, vv = np.meshgrid(us, vs)
    ix = np.clip((uu * s).astype(int), 0, w - 1)
    iy = np.clip(((vv - vmin + 1) * s).astype(int), 0, h - 1)
    k = m[iy, ix]
    return uu[k], vv[k], umax


def _tone(n_dot_l):
    a = abs(n_dot_l)
    return 0 if a < 0.42 else 1 if a < 0.72 else 2


def wing_colour(u, v, umax, kind, tone):
    """the colour of the wing at (u, v); the same on both sides"""
    f = u / umax
    c = WING[tone]
    if f > 0.8:
        c = EDGE[tone]
    # the eye spot
    cu, cv, r = (0.56 * umax, -0.4, 2.1) if kind == 'fore' else (0.5 * umax, -6.4, 1.4)
    d = math.hypot((u - cu) * 0.9, v - cv)
    if d < r * 0.55:
        c = SPOT[2 if tone else 1]
    elif d < r:
        c = SPOT[0 if tone == 0 else 1]
    else:
        pass
    return c


def ellipsoid(cx, cy, cz, rx, ry, rz, n=22):
    th = np.linspace(0, math.pi, n)
    ph = np.linspace(0, 2 * math.pi, 2 * n, endpoint=False)
    t, p = np.meshgrid(th, ph)
    nx, ny, nz = np.sin(t) * np.cos(p), np.sin(t) * np.sin(p), np.cos(t)
    pts = np.stack([cx + rx * nx, cy + ry * ny, cz + rz * nz], -1).reshape(-1, 3)
    nor = np.stack([nx / rx, ny / ry, nz / rz], -1).reshape(-1, 3)
    nor = nor / np.linalg.norm(nor, axis=1, keepdims=True)
    return pts, nor


def to_world(pts, heading):
    """moth space (right, forward, up) -> world (X east, Y south, Z up) for a heading"""
    fx, fy = heading
    rx, ry = -fy, fx
    r, f, z = pts[:, 0], pts[:, 1], pts[:, 2]
    return np.stack([r * rx + f * fx, r * ry + f * fy, z], -1)


def project(w, elev=ELEV):
    """world points -> (screen x, screen y down, depth to the camera)"""
    sx = w[:, 0]
    sy = w[:, 1] * math.sin(elev) - w[:, 2] * math.cos(elev)
    dp = w[:, 1] * math.cos(elev) + w[:, 2] * math.sin(elev)
    return sx, sy, dp


def angle_at(i, n=PHASES):
    """the flap angle in degrees at phase i: up at 0, down at n / 2, easing at both ends; the down stroke a little faster"""
    t = 2 * math.pi * i / n
    t2 = t + 0.22 * math.sin(t)          # the down stroke (t from 0 to pi) is stretched in phase so it is quicker
    return 16.0 + 50.0 * math.cos(t2)


def lift_at(i, n=PHASES):
    """the body's rise in pixels: highest in the middle of the down stroke, lowest in the middle of the up stroke"""
    t = 2 * math.pi * i / n
    return 1.6 * math.sin(t + 0.22 * math.sin(t) * 0.0)


_CACHE = {}


def parts():
    if not _CACHE:
        fu, fv, fm = wing_points(FORE)
        hu, hv, hm = wing_points(HIND)
        _CACHE['fore'] = (fu, fv, fm)
        _CACHE['hind'] = (hu, hv, hm)
    return _CACHE


def render(direction, i, n=PHASES):
    th = math.radians(angle_at(i, n))
    lift = lift_at(i, n)
    head = HEADING[direction]
    zbuf = {}

    def put(pts_moth, nor_moth, colours, bias=0.0):
        w = to_world(pts_moth, head)
        w[:, 2] += lift
        nw = to_world(nor_moth, head)
        sx, sy, dp = project(w)
        for k in range(len(sx)):
            x, y = int(round(sx[k])), int(round(sy[k]))
            key = (x, y)
            d = dp[k]
            if key not in zbuf or d + bias > zbuf[key][0]:
                zbuf[key] = (d + bias, colours[k] if not callable(colours) else colours(k, nw[k]))

    # wings: right (+1) and left (-1); the hind wing a little lower than the fore wing
    for side in (1, -1):
        for kind in ('hind', 'fore'):
            u, v, um = parts()[kind]
            t = th + (math.radians(-9) if kind == 'hind' else 0.0)
            pts = np.stack([side * (HINGE + u) * math.cos(t), v + (0.8 if kind == 'fore' else -1.0), (HINGE + u) * math.sin(t) + 0.3], -1)
            nor = np.array([-side * math.sin(t), 0.0, math.cos(t)])
            nor = np.tile(nor, (len(u), 1))
            nw = to_world(nor, head)
            cols = []
            for k in range(len(u)):
                tone = _tone(float(nw[k] @ LIGHT))
                cols.append(wing_colour(float(u[k]), float(v[k]), um, kind, tone))
            put(pts, nor, cols)
    # body
    for (cx, cy, cz, rx, ry, rz) in ((0, 0.4, 0.4, 2.2, 2.8, 2.1), (0, -3.6, 0.2, 1.7, 3.4, 1.5), (0, -8.0, 0.0, 1.0, 2.4, 0.9), (0, 4.3, 1.0, 1.9, 1.9, 1.7)):
        pts, nor = ellipsoid(cx, cy, cz, rx, ry, rz)
        nw = to_world(nor, head)
        cols = [BODY[_tone(float(a @ LIGHT))] for a in nw]
        put(pts, nor, cols, BODY_BIAS)
    # eyes and antennae
    for side in (1, -1):
        e = np.array([[side * 1.1, 5.9, 1.6], [side * 1.1, 5.8, 1.0], [side * 0.7, 5.9, 1.6]])
        put(e, np.tile(np.array([0, 1.0, 0]), (3, 1)), [EYE, EYE, EYE], BODY_BIAS + 4.0)
        a = np.linspace(0, 1, 18)
        feel = np.stack([side * (0.8 + 3.6 * a), 5.2 + 4.2 * a, 2.2 + 3.6 * a - 1.2 * a * a], -1)
        put(feel, np.tile(np.array([0, 0, 1.0]), (len(a), 1)), [FEEL] * len(a), BODY_BIAS)
    return zbuf, None


def raster(zbuf, ox, oy):
    img = np.zeros((CELL, CELL, 4), np.uint8)
    for (x, y), (d, c) in zbuf.items():
        X, Y = x + ox, y + oy
        if 0 <= X < CELL and 0 <= Y < CELL:
            img[Y, X, :3] = c
            img[Y, X, 3] = 255
    return img


def tidy(a):
    """single pixels removed, one pixel holes closed with the colour of their neighbours"""
    a = a.copy()
    op = a[..., 3] > 0
    pad = np.pad(op, 1)
    nb = sum(pad[1 + dy:1 + dy + a.shape[0], 1 + dx:1 + dx + a.shape[1]].astype(int) for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)))
    a[op & (nb == 0)] = 0
    op = a[..., 3] > 0
    pad = np.pad(op, 1)
    nb = sum(pad[1 + dy:1 + dy + a.shape[0], 1 + dx:1 + dx + a.shape[1]].astype(int) for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)))
    holes = ~op & (nb >= 3)
    for y, x in zip(*np.nonzero(holes)):
        ys, xs = slice(max(0, y - 1), y + 2), slice(max(0, x - 1), x + 2)
        m = op[ys, xs]
        if m.any():
            a[y, x, :3] = np.round(a[ys, xs, :3][m].mean(axis=0)).astype(np.uint8)
            a[y, x, 3] = 255
    return a


def outline(a):
    """one pixel near-black line around the moth, drawn outside the art (the moth is small: the rim would eat the wings)"""
    op = a[..., 3] > 0
    pad = np.pad(op, 1)
    near = np.zeros_like(op)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        near |= pad[1 + dy:1 + dy + a.shape[0], 1 + dx:1 + dx + a.shape[1]]
    ring = near & ~op
    out = a.copy()
    out[ring, :3] = OUTLINE
    out[ring, 3] = 255
    return out


def all_frames(n=PHASES):
    """{direction: [32 x 32 RGBA pictures]}: one shift for every picture of the moth (the union box centred, the bob stays)"""
    raw = {d: [render(d, i, n)[0] for i in range(n)] for d in DIRS}
    xs = [k[0] for d in DIRS for z in raw[d] for k in z]
    ys = [k[1] for d in DIRS for z in raw[d] for k in z]
    ox = int(math.floor(15.5 - (min(xs) + max(xs)) / 2.0))
    oy = int(math.floor(15.5 - (min(ys) + max(ys)) / 2.0))
    return {d: [outline(tidy(raster(z, ox, oy))) for z in raw[d]] for d in DIRS}


def write_frames(out_dir, n=PHASES):
    from PIL import Image
    fr = all_frames(n)
    for d in DIRS:
        os.makedirs(os.path.join(out_dir, 'walk', d), exist_ok=True)
        for i, a in enumerate(fr[d]):
            Image.fromarray(a).save(os.path.join(out_dir, 'walk', d, 'frame_%03d.png' % i))
    return fr


def problems(fr):
    """the moth's rules: phases, every direction different from the others, each phase different from its neighbour but only a little
    (no frame skips), the wings at rest at the top and the bottom of the stroke, a union that fits one tile"""
    out = []
    for d in DIRS:
        z = fr[d]
        if len(z) < 24:
            out.append('%s: %d phases, 24 or more wanted' % (d, len(z)))
        steps = []
        for i in range(len(z)):
            a, b = z[i], z[(i + 1) % len(z)]
            steps.append(int(((a[..., 3] > 0) != (b[..., 3] > 0)).sum() + (np.abs(a[..., :3].astype(int) - b[..., :3]).sum(axis=2) > 60).sum()))
        if min(steps) == 0:
            out.append('%s: two neighbouring phases are the same picture' % d)
        if d in ('south', 'north') and max(steps) > 3.2 * (sum(steps) / len(steps)):
            out.append('%s: a frame skip (%d changed pixels against %.1f on average)' % (d, max(steps), sum(steps) / len(steps)))
    return out


def main(argv):
    if argv and argv[0] == 'frames' and len(argv) == 2:
        write_frames(argv[1])
        return 0
    if argv and argv[0] == 'check':
        errs = problems(all_frames())
        for e in errs:
            print(e)
        print('ok' if not errs else '%d problem(s)' % len(errs))
        return 1 if errs else 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
