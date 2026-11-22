#!/usr/bin/env python3
"""A wing as a strip (O590): a spine from the point where the two wings meet to the tip, and at each station of the
spine how far the wing reaches to its two sides. The numbers are measured once on the old art of the private pair
(`gen_drawn_wings.py measure DAT SPR --write`, by hand) for the south and the north view and for the left and the
right wing, and kept in drawn_wings/designs.csv (`sl`, `sr`, `nl`, `nr`). The build reads no pair and no picture.

Why. The old art shows a pair seen a little from the side: a long left wing that lies flat, a short right wing that
stands up. A wing is often a stalk with a head (a flower, a disc, a funnel). The outline of O587 (13 radii of the
larger wing, mirrored) cannot say that. A strip can: it bends, it is thin where the stalk is and wide at the head.

A strip has its own coordinates: s from 0 (root) to 1 (tip) along the spine, t from -1 (the upper edge) to 1 (the
lower edge) across it. The families of gen_drawn_wings_families.py place their pieces in (s, t).

Format of a strip in the table: STATIONS * 4 + 4 whole numbers: the root (x, y), then STATIONS times (x, y, up,
down), then the tip (x, y); px of the old art from the point where the wings meet, y down.
"""
import math

import numpy as np

import gen_drawn_wings as k

S = k.SIZE
STATIONS = 5
SUB = 6                      # points of the smooth spine between two stations
MEET = (48, 58)              # canvas px of the point where the wings meet, before the pair is centred
ROOM = (3, 3, S - 4, S - 5)  # the pair stays inside these canvas px (x0, y0, x1, y1)


# ------------------------------------------------------------------------------------------------ measuring
def _dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        out = out | np.roll(out, 1, 0) | np.roll(out, -1, 0) | np.roll(out, 1, 1) | np.roll(out, -1, 1)
    return out


def _geodesic(mask, root):
    """steps from the root pixel to every pixel of the mask (8 neighbours), -1 where none leads"""
    dist = np.full(mask.shape, -1, np.int32)
    front = np.zeros(mask.shape, bool)
    front[root[1], root[0]] = True
    dist[root[1], root[0]] = 0
    step = 0
    while front.any():
        step += 1
        grown = front.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx or dy:
                    grown |= np.roll(np.roll(front, dy, 0), dx, 1)
        front = grown & mask & (dist < 0)
        dist[front] = step
    return dist


def meet_point(masks):
    """(column, row) where the two wings of a picture meet: the thinnest column near the middle, the middle row of
    the art there"""
    any_ = np.zeros(masks[0].shape, bool)
    for m in masks:
        any_ |= m
    ys, xs = np.nonzero(any_)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    cols = np.mean([m.sum(axis=0) for m in masks], axis=0).astype(np.float64)
    smooth = np.convolve(cols, np.ones(5) / 5.0, mode='same')
    w = x1 - x0
    c0, c1 = x0 + int(w * 0.3), x1 - int(w * 0.3)
    mid = (x0 + x1 - 1) / 2.0
    cand = np.arange(c0, max(c0 + 1, c1))
    cut = int(cand[np.lexsort((np.abs(cand - mid), np.round(smooth[cand], 1)))[0]])
    yy, xx = np.nonzero(masks[0])
    near = np.abs(xx - cut)
    sel = near <= max(2, int(np.sort(near)[min(len(near) - 1, 12)]))
    return cut, int(round(float(np.median(yy[sel]))))


def measure_side(mask, meet, sgn):
    """the strip of one wing: the numbers of the table, or None when the side is empty. mask: the pixels the wing
    covers in most frames; sgn -1 the left wing, 1 the right"""
    h, w = mask.shape
    xx = np.arange(w)[None, :]
    side = mask & ((xx < meet[0]) if sgn < 0 else (xx >= meet[0]))
    ys, xs = np.nonzero(side)
    if len(xs) < 12:
        return None
    i = int(np.argmin((xs - meet[0]) ** 2 + (ys - meet[1]) ** 2))
    root = (int(xs[i]), int(ys[i]))
    dist = None
    for grow in (1, 2, 4, 7):                             # loose parts (sparks, beads) are joined to the wing
        dist = _geodesic(_dilate(side, grow), root)
        if (dist[side] >= 0).mean() >= 0.85:
            break
    ok = side & (dist >= 0)
    ys, xs = np.nonzero(ok)
    g = dist[ys, xs].astype(np.float64)
    gmax = max(float(g.max()), 1.0)
    far = g >= gmax - 1.5
    j = int(np.argmax(np.where(far, (xs - root[0]) ** 2 + (ys - root[1]) ** 2, -1)))
    tip = (int(xs[j]), int(ys[j]))
    cents = []
    for b in range(STATIONS):
        sel = (g >= gmax * b / STATIONS) & (g <= gmax * (b + 1) / STATIONS)
        if not sel.any():
            sel = np.ones(len(g), bool)
        cents.append((float(xs[sel].mean()), float(ys[sel].mean()), sel))
    pts = [root] + [(c[0], c[1]) for c in cents] + [tip]
    out = [root[0] - meet[0], root[1] - meet[1]]
    prev = None
    for b in range(STATIONS):
        tx, ty = pts[b + 2][0] - pts[b][0], pts[b + 2][1] - pts[b][1]
        n = normal_of(tx, ty, sgn, prev)
        prev = n
        sel = cents[b][2]
        off = (xs[sel] - cents[b][0]) * n[0] + (ys[sel] - cents[b][1]) * n[1]
        up, down = max(0.5, -float(np.percentile(off, 4))), max(0.5, float(np.percentile(off, 96)))
        out += [int(round(cents[b][0] - meet[0])), int(round(cents[b][1] - meet[1])), int(round(up + 0.5)), int(round(down + 0.5))]
    out += [tip[0] - meet[0], tip[1] - meet[1]]
    return out


def normal_of(tx, ty, sgn, prev=None):
    """the unit normal of a spine direction that points to the lower edge: down, and for a wing that stands up, away
    from the other wing; it never turns over along a spine"""
    ln = math.hypot(tx, ty) or 1.0
    n = (-ty / ln, tx / ln)
    if prev is not None:
        return n if n[0] * prev[0] + n[1] * prev[1] >= 0 else (-n[0], -n[1])
    return n if n[1] + 0.5 * sgn * n[0] >= 0 else (-n[0], -n[1])


def stable_mask(frames):
    """the pixels a wing covers in at least 4 of 10 frames"""
    masks = [f[..., 3] >= 128 for f in frames]
    return np.mean(masks, axis=0) >= 0.4, masks


PAD = 8


def view_meet(frames):
    """the px of a picture where its two wings meet, as measure_view takes it"""
    return _measure(frames)[2]


def measure_view(frames):
    """(left strip, right strip) of the pictures of one direction; a missing wing is None"""
    return _measure(frames)[:2]


def _measure(frames):
    stable, masks = stable_mask(frames)
    stable = np.pad(stable, PAD)
    masks = [np.pad(m, PAD) for m in masks]
    if not stable.any():
        return None, None, (0, 0)
    meet = meet_point(masks)
    out = _sides(stable, meet)
    return out[0], out[1], (out[2][0] - PAD, out[2][1] - PAD)


def _sides(stable, meet):
    left, right = measure_side(stable, meet, -1), measure_side(stable, meet, 1)
    ys, xs = np.nonzero(stable)
    nl, nr = int((xs < meet[0]).sum()), int((xs >= meet[0]).sum())
    if left is None or right is None or min(nl, nr) < 0.12 * max(nl, nr):   # a thin line fooled the cut: take the middle
        mid = int((xs.min() + xs.max() + 1) // 2)
        near = np.abs(xs - mid) <= 3
        if near.any():
            meet2 = (mid, int(round(float(np.median(ys[near])))))
            l2, r2 = measure_side(stable, meet2, -1), measure_side(stable, meet2, 1)
            if l2 is not None and r2 is not None:
                return l2, r2, meet2
    return left, right, meet


def text_of(strip):
    return '' if strip is None else ' '.join(str(v) for v in strip)


def parse(text):
    vals = [int(v) for v in text.split()]
    if not vals:
        return None
    if len(vals) != STATIONS * 4 + 4:
        raise ValueError('a strip needs %d numbers, got %d' % (STATIONS * 4 + 4, len(vals)))
    return vals


# ------------------------------------------------------------------------------------------------ geometry
def _catmull(p0, p1, p2, p3, u):
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


class Places:
    """what a strip and a part of a strip share: places, masks"""

    def pts(self, places):
        return [self.pt(s, t) for s, t in places]

    def rim(self, q):
        """a place on the outline by one number: 0 the root of the lower edge, 0.42 the lower edge near the tip,
        0.5 the tip, 0.58 the upper edge near the tip, 1 the root of the upper edge"""
        q = k.clamp(q, 0.0, 1.0)
        if q <= 0.42:
            return self.pt(q / 0.42 * 0.94, 1.0)
        if q >= 0.58:
            return self.pt((1.0 - q) / 0.42 * 0.94, -1.0)
        a = (q - 0.42) / 0.16                               # round the tip
        return self.pt(0.94 + 0.06 * math.sin(math.pi * a), math.cos(math.pi * a))

    def region(self, s0=0.0, s1=1.0, t0=-1.0, t1=1.0, n=None):
        """the pixels of the strip between two places along and two across (a row of four-sided pieces, so a
        tight bend never turns the outline inside out)"""
        n = n or max(6, int(round((s1 - s0) * 30)))
        top = [self.pt(s0 + (s1 - s0) * i / float(n), t0) for i in range(n + 1)]
        bot = [self.pt(s0 + (s1 - s0) * i / float(n), t1) for i in range(n + 1)]
        mask = np.zeros((S, S), bool)
        for i in range(n):
            mask |= k.poly_mask([top[i], top[i + 1], bot[i + 1], bot[i]])
        return mask

    def body(self):
        return self.region(0.0, 1.0, -1.0, 1.0, 36)

    def line(self, places, hw0, hw1=None, knob0=0.0, knob1=0.0):
        """a thick line through strip places"""
        hw1 = hw0 if hw1 is None else hw1
        p = self.pts(places)
        mask = np.zeros((S, S), bool)
        n = len(p) - 1
        for i in range(n):
            mask |= k.capsule_mask(p[i], p[i + 1], hw0 + (hw1 - hw0) * i / n, hw0 + (hw1 - hw0) * (i + 1) / n)
        if knob0:
            mask |= k.disc_mask(p[0][0], p[0][1], knob0)
        if knob1:
            mask |= k.disc_mask(p[-1][0], p[-1][1], knob1)
        return mask


    def mid(self):
        """the middle of the strip (or of the part) and half its mean width"""
        x, y = self.pt(0.5, 0.0)
        return x, y, (self.half(0.5, -1) + self.half(0.5, 1)) / 2.0


class Sub(Places):
    """the part of a strip from s0 on, with its own s from 0 to 1 (the head of a wing that begins as a stalk)"""

    def __init__(self, strip, s0):
        self.w, self.s0, self.sgn = strip, s0, strip.sgn
        self.length = strip.length * (1.0 - s0)
        self.width = strip.width

    def pt(self, s, t):
        return self.w.pt(self.s0 + s * (1.0 - self.s0), t)

    def half(self, s, t):
        return self.w.half(self.s0 + s * (1.0 - self.s0), t)

    def field(self):
        ss, tt = self.w.field()
        return (ss - self.s0) / (1.0 - self.s0), tt



class Strip(Places):
    """one wing in canvas px. vals: the numbers of the table; sgn: -1 the left wing, 1 the right; origin: the canvas
    px of the point where the wings meet; scale: px of the drawing per px of the old art; bend(u) -> radians: how
    far the wing is turned about its root at the share u of its length (the beat)"""

    def __init__(self, vals, sgn, origin, scale=1.0, bend=None, stretch=1.0):
        self.sgn = sgn
        n = STATIONS + 2
        xs = [vals[0]] + [vals[2 + 4 * i] for i in range(STATIONS)] + [vals[-2]]
        ys = [vals[1]] + [vals[3 + 4 * i] for i in range(STATIONS)] + [vals[-1]]
        ups = [0.0] + [float(vals[4 + 4 * i]) for i in range(STATIONS)] + [0.6]
        dns = [0.0] + [float(vals[5 + 4 * i]) for i in range(STATIONS)] + [0.6]
        ups[0], dns[0] = min(ups[1], 2.5) * 0.7, min(dns[1], 2.5) * 0.7
        px = np.asarray(xs, np.float64) * scale
        py = np.asarray(ys, np.float64) * scale
        if bend is not None or stretch != 1.0:
            rx, ry = px[0], py[0]
            seg = np.hypot(np.diff(px), np.diff(py))
            along = np.concatenate([[0.0], np.cumsum(seg)]) / max(float(seg.sum()), 1e-6)
            for i in range(1, n):
                a = bend(float(along[i])) if bend is not None else 0.0
                dx, dy = (px[i] - rx) * stretch, (py[i] - ry) * stretch
                px[i] = rx + dx * math.cos(a) - dy * math.sin(a)
                py[i] = ry + dx * math.sin(a) + dy * math.cos(a)
        px += origin[0]
        py += origin[1]
        # the smooth spine
        m = (n - 1) * SUB + 1
        self.m = m
        sx, sy, su, sd = np.zeros(m), np.zeros(m), np.zeros(m), np.zeros(m)
        for j in range(m):
            i, u = divmod(j, SUB)
            if i >= n - 1:
                i, u = n - 2, SUB
            u = u / float(SUB)
            i0, i1, i2, i3 = max(i - 1, 0), i, i + 1, min(i + 2, n - 1)
            sx[j] = _catmull(px[i0], px[i1], px[i2], px[i3], u)
            sy[j] = _catmull(py[i0], py[i1], py[i2], py[i3], u)
            su[j] = (ups[i1] + (ups[i2] - ups[i1]) * u) * scale
            sd[j] = (dns[i1] + (dns[i2] - dns[i1]) * u) * scale
        self.x, self.y, self.up, self.dn = sx, sy, su, sd
        nx, ny = np.zeros(m), np.zeros(m)
        prev = None
        for j in range(m):
            a, b = max(j - 1, 0), min(j + 1, m - 1)
            nrm = normal_of(sx[b] - sx[a], sy[b] - sy[a], sgn, prev)
            prev = nrm
            nx[j], ny[j] = nrm
        self.nx, self.ny = nx, ny
        seg = np.hypot(np.diff(sx), np.diff(sy))
        self.length = float(seg.sum())
        self.width = float((su + sd).max())

    # -- places
    def _at(self, s):
        f = k.clamp(s, 0.0, 1.0) * (self.m - 1)
        j = min(int(f), self.m - 2)
        return j, f - j

    def spine(self, s):
        j, u = self._at(s)
        return (self.x[j] + (self.x[j + 1] - self.x[j]) * u, self.y[j] + (self.y[j + 1] - self.y[j]) * u)

    def half(self, s, t):
        """the reach of the wing at s on the side of t, px"""
        j, u = self._at(s)
        a = self.up if t < 0 else self.dn
        return a[j] + (a[j + 1] - a[j]) * u

    def pt(self, s, t):
        """canvas px of the strip place (s, t); s past 1 runs on beyond the tip"""
        j, u = self._at(s)
        x, y = self.spine(s)
        nx = self.nx[j] + (self.nx[j + 1] - self.nx[j]) * u
        ny = self.ny[j] + (self.ny[j + 1] - self.ny[j]) * u
        r = self.half(s, t) * t
        if s > 1.0:
            tx, ty = self.x[-1] - self.x[-3], self.y[-1] - self.y[-3]
            ln = math.hypot(tx, ty) or 1.0
            x += tx / ln * (s - 1.0) * self.length
            y += ty / ln * (s - 1.0) * self.length
        return (x + nx * r, y + ny * r)

    def field(self):
        """per pixel the strip place (s, t) of the nearest point of the spine; t is cut at -1.6 .. 1.6"""
        best = np.full((S, S), 1e9)
        ss = np.zeros((S, S))
        tt = np.zeros((S, S))
        for j in range(self.m - 1):
            ax, ay = self.x[j], self.y[j]
            bx, by = self.x[j + 1] - ax, self.y[j + 1] - ay
            ln2 = bx * bx + by * by or 1e-9
            u = np.clip(((k.PX - ax) * bx + (k.PY - ay) * by) / ln2, 0.0, 1.0)
            dx, dy = k.PX - (ax + bx * u), k.PY - (ay + by * u)
            d2 = dx * dx + dy * dy
            better = d2 < best
            if not better.any():
                continue
            nx = self.nx[j] + (self.nx[j + 1] - self.nx[j]) * u
            ny = self.ny[j] + (self.ny[j + 1] - self.ny[j]) * u
            side = dx * nx + dy * ny
            up = self.up[j] + (self.up[j + 1] - self.up[j]) * u
            dn = self.dn[j] + (self.dn[j + 1] - self.dn[j]) * u
            t = np.where(side < 0, side / np.maximum(up, 0.6), side / np.maximum(dn, 0.6))
            best = np.where(better, d2, best)
            ss = np.where(better, (j + u) / float(self.m - 1), ss)
            tt = np.where(better, t, tt)
        return ss, np.clip(tt, -1.6, 1.6)

    def box(self):
        """(x0, y0, x1, y1) of the outline"""
        xs = np.concatenate([self.x - self.nx * self.up, self.x + self.nx * self.dn])
        ys = np.concatenate([self.y - self.ny * self.up, self.y + self.ny * self.dn])
        return float(xs.min()), float(ys.min()), float(xs.max()), float(ys.max())

    def head(self):
        """(s, radius): where the strip is widest, and half its width there"""
        wsum = self.up + self.dn
        j = int(np.argmax(wsum))
        return j / float(self.m - 1), float(wsum[j]) / 2.0

    def stalk(self):
        """the share of the length over which the wing is a thin stalk before it widens (0: no stalk)"""
        wsum = self.up + self.dn
        thin = wsum < max(4.5, 0.38 * float(wsum.max()))
        j = 0
        while j < self.m and thin[j]:
            j += 1
        return j / float(self.m - 1) if j > SUB else 0.0


def place(strips, room=ROOM, amp=0.0, tries=8):
    """(origin, scale) that puts a pair of strips (table numbers, either may be None) round the anchor: the box of
    the pair centred on the anchor's column, the meeting point on MEET's row, moved and at last scaled down so that
    it stays inside `room` through the whole beat (`amp`, radians). `tries` steps of 4% at most (O714: a pair that is
    one wing and its mirror picture must never be pushed off the column, so its caller gives 40)"""
    scale = 1.0
    for _ in range(tries):
        boxes = [Strip(v, sgn, (0.0, 0.0), scale, (lambda u, a=a: a * (0.25 + 0.75 * u)) if a else None).box()
                 for v, sgn in zip(strips, (-1, 1)) if v is not None for a in ((-amp, 0.0, amp) if amp else (0.0,))]
        x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
        x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
        if x1 - x0 <= room[2] - room[0] - 4 and y1 - y0 <= room[3] - room[1] - 4:
            break
        scale *= 0.96
    ox = k.ANCHOR[0] - (x0 + x1) / 2.0
    oy = float(MEET[1])
    ox = k.clamp(ox, room[0] + 2 - x0, room[2] - 2 - x1)
    oy = k.clamp(oy, room[1] + 2 - y0, room[3] - 2 - y1)
    return (round(ox), round(oy)), scale
