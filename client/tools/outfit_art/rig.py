"""The outfit rig: a humanoid made of signed-distance parts on bones, drawn in the oblique projection of the client
(a point at height h is drawn h/1.5 up and h/1.5 to the left; light from the top-left), painted with ramps per
material, outlined, and split into the base layer and the colour template layer (yellow head, red body, green legs,
blue feet: the client multiplies those base pixels by the player's colours, so tinted materials are painted in grey).

This is the creature method of the art studio (client/tools/art_studio, PIXEL-ART-STUDIO.md) without the PixelLab
repaint: the shape is the art. Every frame is the posed shape rendered again (whole-body moves by whole pixels), so
the colour mask always follows the pixels it tints.

Body coordinates: u forward, v the figure's right, h up, in pixels of the frame. A part sits on a bone; a pose turns
bones about their pivots, children follow their parents.
"""
import math
import os
import sys

import numpy as np

KIT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art_studio", "kit")
sys.path.insert(0, KIT)
import tibia_view as pt  # noqa: E402

VIEWS = ("north", "east", "south", "west")      # the dat's pattern x order
REGIONS = {"head": (255, 255, 0), "body": (255, 0, 0), "legs": (0, 255, 0), "feet": (0, 0, 255)}


# ------------------------------------------------------------------------------------------------ primitives
class Prim:
    """A distance function with a bounding sphere (centre, radius): far points get the cheap sphere distance."""

    def __init__(self, fn, c, r):
        self.fn, self.c, self.r = fn, np.asarray(c, float), float(r)

    def __call__(self, X):
        d = np.linalg.norm(X - self.c, axis=1) - self.r
        near = d < 1.5
        if near.any():
            d = d.copy()
            d[near] = self.fn(X[near])
        return d


def ell(c, r):
    c, r = np.asarray(c, float), np.asarray(r, float)
    return Prim(lambda X: pt.sd_ellipsoid(X, c, r), c, r.max())


def cone(a, b, ra, rb):
    a, b = np.asarray(a, float), np.asarray(b, float)
    return Prim(lambda X: pt.sd_cone(X, a, b, ra, rb), (a + b) / 2, np.linalg.norm(b - a) / 2 + max(ra, rb))


def box(c, half, rnd=0.0, rot=None):
    """A box; `rot` a 3x3 matrix turning the box's own axes into body axes."""
    c, half = np.asarray(c, float), np.asarray(half, float)
    if rot is None:
        return Prim(lambda X: pt.sd_box(X, c, half, rnd), c, np.linalg.norm(half))
    R = np.asarray(rot, float)
    return Prim(lambda X: pt.sd_box((X - c) @ R, np.zeros(3), half, rnd), c, np.linalg.norm(half))


def cyl(a, b, r, rnd=0.2):
    """A flat-ended cylinder from a to b (discs, rims, hafts)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ax = b - a
    L = np.linalg.norm(ax)
    ax = ax / L

    def fn(X):
        q = X - a
        t = q @ ax
        radial = np.linalg.norm(q - t[:, None] * ax, axis=1)
        dx = radial - (r - rnd)
        dy = np.abs(t - L / 2) - (L / 2 - rnd)
        return np.minimum(np.maximum(dx, dy), 0) + np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) - rnd
    return Prim(fn, (a + b) / 2, math.hypot(L / 2, r))


def union(*ps, k=0.0):
    c = np.mean([p.c for p in ps], 0)
    r = max(np.linalg.norm(p.c - c) + p.r for p in ps)

    def fn(X):
        d = ps[0](X)
        for p in ps[1:]:
            d = pt.smin(d, p(X), k) if k > 0 else np.minimum(d, p(X))
        return d
    return Prim(fn, c, r)


def cut(p, q):
    """p minus q."""
    return Prim(lambda X: np.maximum(p(X), -q(X)), p.c, p.r)


def clip(p, q):
    """p intersected with q."""
    return Prim(lambda X: np.maximum(p(X), q(X)), p.c, p.r)


def halfspace(n, d):
    """The points with X.n <= d (n a unit vector)."""
    n = np.asarray(n, float)
    n = n / np.linalg.norm(n)
    return Prim(lambda X: X @ n - d, np.zeros(3), 1e9)


def rot(axis, deg):
    a = np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    K = np.array(((0, -a[2], a[1]), (a[2], 0, -a[0]), (-a[1], a[0], 0)))
    t = math.radians(deg)
    return np.eye(3) + math.sin(t) * K + (1 - math.cos(t)) * K @ K


def moved(p, R=None, about=(0, 0, 0), t=(0, 0, 0)):
    """The part turned by R about `about` and moved by t (built in place, at rest)."""
    R = np.eye(3) if R is None else R
    about, t = np.asarray(about, float), np.asarray(t, float)
    c = R @ (p.c - about) + about + t
    return Prim(lambda X: p((X - about - t) @ R + about), c, p.r)


# ------------------------------------------------------------------------------------------------ materials
class Mat:
    """kind: matte, metal (specular), skin, glow (lit by itself), cloth; region: None or a template region."""

    def __init__(self, ramp, outline, region=None, kind="matte", grain=0.0, spec=0.0, line=3):
        self.ramp = np.asarray(ramp, np.uint8)
        self.outline = tuple(outline)
        self.region, self.kind, self.grain, self.spec, self.line = region, kind, grain, spec, line


def ramp(anchors, n):
    return pt.ramp(anchors, n)


def grey(n, lo=34, hi=236):
    """A neutral ramp for tinted cloth: the client multiplies it by the player's colour."""
    v = np.linspace(lo, hi, n)
    return np.stack([v, v, v], 1).round().astype(np.uint8)


# ------------------------------------------------------------------------------------------------ the rig
class Part:
    def __init__(self, name, bone, mat, prim):
        self.name, self.bone, self.mat, self.prim = name, bone, mat, prim


class Rig:
    def __init__(self, bones, parts, mats, scale=(1.0, 1.0, 1.0)):
        """bones: name -> (parent or None, pivot); parts: [Part]; mats: name -> Mat. scale: the whole figure is
        drawn this much bigger along (u, v, h) -- design in plain units, widen at the end."""
        self.bones, self.parts, self.mats = bones, parts, mats
        self.scale = np.asarray(scale, float)
        self.mat_names = list(mats)
        self.order = []
        seen = set()

        def visit(b):
            if b in seen:
                return
            p = bones[b][0]
            if p is not None:
                visit(p)
            seen.add(b)
            self.order.append(b)
        for b in bones:
            visit(b)

    def world(self, pose):
        """pose: bone -> (R, t) local (R about the bone's pivot, then t); -> bone -> (R, c, t) as creature_anim."""
        W = {}
        for b in self.order:
            parent, piv = self.bones[b]
            R, t = pose.get(b, (np.eye(3), np.zeros(3)))
            local = (np.asarray(R, float), np.asarray(piv, float), np.asarray(t, float))
            W[b] = compose(W[parent], local) if parent is not None else local
        return W


def compose(outer, inner):
    Ro, co, to = outer
    Ri, ci, ti = inner
    return Ro @ Ri, ci, Ro @ (ci + ti - co) + co + to - ci


def posed(rig, W):
    """The posed distance: (total, per-part distances, per-part rest points) for body points X."""
    inv = {}
    for b, (R, c, t) in W.items():
        inv[b] = (R, c, t)

    def to_rest(b, X):
        R, c, t = inv[b]
        return (X - c - t) @ R + c

    sc, smin_ = rig.scale, rig.scale.min()

    def sdf(X, full=False):
        X = X / sc
        ds = np.empty((len(X), len(rig.parts)))
        cache = {}
        for i, p in enumerate(rig.parts):
            if p.bone not in cache:
                cache[p.bone] = to_rest(p.bone, X)
            ds[:, i] = p.prim(cache[p.bone])
        ds *= smin_
        if full:
            return ds.min(1), ds, cache
        return ds.min(1)
    return sdf


# ------------------------------------------------------------------------------------------------ the render
def render(rig, view, pose, frame=64, ground=(52.5, 53.5), top=62.0, ss=5, shadow=True):
    """Per pixel of the frame: on, material index, value 0..1, part index, nearness (ray depth, smaller = nearer)."""
    W = rig.world(pose)
    sdf = posed(rig, W)
    fc = pt.Facing(view, ground)
    n, SS = frame, ss
    Wd = n * SS
    jj, ii = np.meshgrid(np.arange(Wd), np.arange(Wd))
    sx, sy = (jj.ravel() + 0.5) / SS, (ii.ravel() + 0.5) / SS
    origins = np.stack([sx + top / 1.5, sy + top / 1.5, np.full(sx.shape, top)], 1)
    direction = -pt.TOWARD_VIEW
    # only rays that can meet the figure: those whose ground point lies near the feet, up-left of them
    reach = (sx <= ground[0] + 12) & (sy <= ground[1] + 12) & (sx >= ground[0] - top / 1.5 - 14) & (sy >= ground[1] - top / 1.5 - 14)
    sel = np.nonzero(reach)[0]
    hit_s, t_s = pt.march(fc, origins[sel], direction, max_t=(top + 1) / pt.TOWARD_VIEW[2], sdf=sdf, steps=140)
    idx = sel[hit_s]
    t = t_s[hit_s]
    Pw = origins[idx] + t[:, None] * direction
    X = fc.to_body(Pw)
    _, ds, rest = sdf(X, full=True)
    part = np.argmin(ds, 1)
    bones = [p.bone for p in rig.parts]
    Xr = np.zeros_like(X)
    for pi in np.unique(part):
        m = part == pi
        Xr[m] = rest[bones[pi]][m]
    nb = pt.normals(X, sdf)
    nw = np.stack([nb[:, 0] * fc.F[0] + nb[:, 1] * fc.R[0], nb[:, 0] * fc.F[1] + nb[:, 1] * fc.R[1], nb[:, 2]], 1)
    lam = np.clip(nw @ pt.LIGHT, 0, 1)
    sh = pt.soft_shadow(fc, X + nb * 0.3, sdf, max_t=20.0, steps=40) if shadow else np.ones(len(X))
    ao = pt.occlusion(X, nb, sdf)
    sky = 0.5 + 0.5 * nw[:, 2]
    front = np.clip(nw @ pt.TOWARD_VIEW, 0, 1)
    spec = np.clip(nw @ pt.HALF, 0, 1) ** 24
    v = 0.10 + 0.62 * lam * (0.4 + 0.6 * sh) + 0.16 * sky + 0.24 * front - 0.24 * ao
    mi = np.array([rig.mat_names.index(rig.parts[p].mat) for p in part])
    kinds = np.array([rig.mats[m].kind for m in rig.mat_names])[mi]
    specs = np.array([rig.mats[m].spec for m in rig.mat_names])[mi]
    v = v + specs * spec
    g = kinds == "glow"
    v[g] = 0.45 + 0.55 * front[g]
    v = np.clip(v, 0, 1)
    blk = (idx // Wd // SS) * n + (idx % Wd) // SS
    cov = np.bincount(blk, minlength=n * n)
    on = cov >= 0.45 * SS * SS
    npart = len(rig.parts)
    cnt = np.zeros((n * n, npart))
    np.add.at(cnt, (blk, part), 1)
    pmain = np.argmax(cnt, 1)
    s = part == pmain[blk]
    k = np.maximum(np.bincount(blk[s], minlength=n * n), 1)
    val = np.bincount(blk[s], weights=v[s], minlength=n * n) / k
    dep = np.full(n * n, np.inf)
    np.minimum.at(dep, blk, t)
    matmain = np.array([rig.mat_names.index(p.mat) for p in rig.parts])[pmain]
    restm = np.stack([np.bincount(blk[s], weights=Xr[s, i], minlength=n * n) / k for i in range(3)], 1)
    rs = lambda a: a.reshape(n, n)  # noqa: E731
    return dict(on=rs(on), mat=rs(matmain), val=rs(val), part=rs(pmain), dep=rs(dep), rest=restm.reshape(n, n, 3))


def _nb(a, dy, dx, fill):
    n0, n1 = a.shape
    P = np.pad(a, 1, constant_values=fill)
    return P[1 + dy:n0 + 1 + dy, 1 + dx:n1 + 1 + dx]


BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.47


def paint(rig, r, line_depth=1.0, outline=True):
    """-> (base RGBA, template RGBA). Ramps per material, a dark line where a part passes behind a nearer one, and
    the outer outline one pixel outside the shape."""
    on, mat, val, part, dep = r["on"], r["mat"], r["val"], r["part"], r["dep"]
    n0, n1 = on.shape
    on = pt.tidy_silhouette(on)
    # a pixel the tidy filled takes its neighbour's material
    rest = r["rest"].copy()
    done = r["on"].copy()
    for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        fill = on & ~done & _nb(done, dy, dx, False)
        rest = np.where(fill[..., None], np.stack([_nb(rest[..., i], dy, dx, 0.0) for i in range(3)], -1), rest)
        mat = np.where(fill, _nb(mat, dy, dx, 0), mat)
        val = np.where(fill, _nb(val, dy, dx, 0.5), val)
        dep = np.where(fill, _nb(dep, dy, dx, np.inf), dep)
        part = np.where(fill, _nb(part, dy, dx, 0), part)
        done |= fill
    yy, xx = np.mgrid[0:n0, 0:n1]
    noise = pt.hash01(yy, xx, np.full_like(yy, 5)) - 0.5
    base = np.zeros((n0, n1, 4), np.uint8)
    tmpl = np.zeros((n0, n1, 4), np.uint8)
    kidx = np.zeros((n0, n1), int)
    for mi, name in enumerate(rig.mat_names):
        M = rig.mats[name]
        m = on & (mat == mi)
        if not m.any():
            continue
        nr = len(M.ramp)
        k = np.clip(np.round(val * (nr - 1) + noise * M.grain), 0, nr - 1).astype(int)
        kidx[m] = k[m]
        base[m, :3] = M.ramp[k[m]]
        base[m, 3] = 255
        if M.region:
            tmpl[m, :3] = REGIONS[M.region]
            tmpl[m, 3] = 255
    # inner lines: a pixel whose neighbour is another part clearly nearer the eye
    line = np.zeros((n0, n1), bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        q_on = _nb(on, dy, dx, False)
        q_part = _nb(part, dy, dx, -1)
        q_dep = _nb(dep, dy, dx, np.inf)
        line |= on & q_on & (q_part != part) & (q_dep < dep - line_depth)
    for mi, name in enumerate(rig.mat_names):
        M = rig.mats[name]
        m = line & (mat == mi)
        if M.kind == "glow" or not m.any():
            continue
        k = np.clip(kidx - M.line, 0, len(M.ramp) - 1)
        base[m, :3] = M.ramp[k[m]]
    if outline:
        ring = ~on & (_nb(on, 1, 0, False) | _nb(on, -1, 0, False) | _nb(on, 0, 1, False) | _nb(on, 0, -1, False))
        # the outline colour: from the neighbour's material (the first found)
        col = np.zeros((n0, n1, 3), int)
        got = np.zeros((n0, n1), bool)
        for dy, dx in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            q_on = _nb(on, dy, dx, False) & ring & ~got
            q_mat = _nb(mat, dy, dx, 0)
            for mi, name in enumerate(rig.mat_names):
                mm = q_on & (q_mat == mi)
                col[mm] = rig.mats[name].outline
            got |= q_on
        base[ring, :3] = col[ring]
        base[ring, 3] = 255
    else:
        ring = np.zeros_like(on)
    # the maps of the painted pixels (for re-dressing a frame in a repainted standing frame, repaint.py)
    r["maps"] = dict(on=on, ring=ring, part=part.astype(np.int16), mat=mat.astype(np.int16), rest=rest.astype(np.float32))
    return base, tmpl


# ------------------------------------------------------------------------------------------------ the client's colours
def outfit_color(c):
    """The client's outfit palette (133 colours, Color::getOutfitColor)."""
    S, H = 7, 19
    if c >= H * S:
        c = 0
    if c % H != 0:
        l1 = c % H / 18.0
        l2, l3 = {0: (0.25, 1.0), 1: (0.25, 0.75), 2: (0.5, 0.75), 3: (0.667, 0.75), 4: (1.0, 1.0), 5: (1.0, 0.75),
                  6: (1.0, 0.5)}[c // H]
    else:
        l1, l2, l3 = 0, 0, 1 - c / H / S
    if l3 == 0:
        return (0, 0, 0)
    if l2 == 0:
        g = int(l3 * 255)
        return (g, g, g)
    if l1 < 1 / 6:
        r_ = l3; b = l3 * (1 - l2); g = b + (l3 - b) * 6 * l1
    elif l1 < 2 / 6:
        g = l3; b = l3 * (1 - l2); r_ = g - (l3 - b) * (6 * l1 - 1)
    elif l1 < 3 / 6:
        g = l3; r_ = l3 * (1 - l2); b = r_ + (l3 - r_) * (6 * l1 - 2)
    elif l1 < 4 / 6:
        b = l3; r_ = l3 * (1 - l2); g = b - (l3 - r_) * (6 * l1 - 3)
    elif l1 < 5 / 6:
        b = l3; g = l3 * (1 - l2); r_ = g + (l3 - g) * (6 * l1 - 4)
    else:
        r_ = l3; g = l3 * (1 - l2); b = r_ - (l3 - g) * (6 * l1 - 5)
    return (int(r_ * 255), int(g * 255), int(b * 255))


def colourize(base, tmpl, head, body, legs, feet):
    """What the client draws: base pixels under the template multiplied by the outfit colours."""
    out = base.copy().astype(np.float64)
    t = tmpl
    for cidx, m in ((head, (t[..., 0] > 229) & (t[..., 1] > 229)),
                    (body, (t[..., 0] > 229) & (t[..., 1] <= 229)),
                    (legs, (t[..., 0] <= 229) & (t[..., 1] > 229)),
                    (feet, (t[..., 0] <= 229) & (t[..., 1] <= 229) & (t[..., 2] > 229))):
        m = m & (t[..., 3] > 0)
        out[m, :3] = out[m, :3] * np.array(outfit_color(cidx)) / 255.0
    return out.astype(np.uint8)


def overflow(rig, view, pose, ground, frame=64, margin=12, ss=2, top=62.0):
    """How many pixels of the posed figure fall right of or below the outfit frame (the client draws a 2x2 outfit
    up and left of its tile: nothing can show past the frame's right or bottom edge, so such pixels are cut off)."""
    W = rig.world(pose)
    sdf = posed(rig, W)
    fc = pt.Facing(view, ground)
    n = frame + margin
    jj, ii = np.meshgrid(np.arange(n * ss), np.arange(n * ss))
    sx, sy = (jj.ravel() + 0.5) / ss, (ii.ravel() + 0.5) / ss
    sel = (sx >= frame) | (sy >= frame)
    origins = np.stack([sx[sel] + top / 1.5, sy[sel] + top / 1.5, np.full(sel.sum(), top)], 1)
    hit, _ = pt.march(fc, origins, -pt.TOWARD_VIEW, max_t=(top + 1) / pt.TOWARD_VIEW[2], sdf=sdf, steps=100)
    return int(hit.sum()) // (ss * ss)
