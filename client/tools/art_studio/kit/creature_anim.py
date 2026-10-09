"""Animating a PixelLab painting without repainting it.

PixelLab repaints a creature's Python shape and keeps its silhouette, so each pixel of the painting belongs to a part of
the shape. A frame poses the shape -- a rigid transform per part, X_posed = R @ (X_rest - c) + c + t -- ray-marches it
in the Tibia projection, and every pixel takes its colour from the pixel of the painting where the SAME point of its
part sat at rest (or the nearest pixel of that part, when it was hidden there). A part moved by whole pixels comes out
identical, only shifted; the silhouette is outlined again with the painting's own dark, and a lone pixel goes. Where the
painting left the shape's silhouette (ragged feathers), `exact` keeps the painting's: its fringe moves with the nearest
part, its gaps stay gaps.

The sheet: a column per direction -- north, east, south, west -- and the frames going down, the idle on top and the
walk below, named <creature>_idle<frames>_walking<frames>.png.
"""
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tibia_view as pt  # noqa: E402

ORDER = ("north", "east", "south", "west")


class Model:
    """A creature's shape: its parts (name -> (material, distance of rest body points)), its frame and where it
    stands in it, and how high its rays start (above everything it has)."""

    def __init__(self, parts, names, frame=64, ground=None, top=30.0, ss=4):
        self.parts, self.names = parts, names
        self.frame, self.top, self.ss = frame, top, ss
        self.ground = pt.GROUND if ground is None else np.asarray(ground, float)
        self.mats = np.array([parts[n][0] for n in names])

    def rest(self):
        return {n: (np.eye(3), np.zeros(3), np.zeros(3)) for n in self.names}


def rotation(axis, ang):
    a = np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    K = np.array(((0, -a[2], a[1]), (a[2], 0, -a[0]), (-a[1], a[0], 0)))
    return np.eye(3) + math.sin(ang) * K + (1 - math.cos(ang)) * K @ K


def posed_sdf(model, T):
    def inv(name, X):
        R, c, t = T[name]
        return (X - c - t) @ R + c          # R orthonormal: R^-1 = R^T, and (R^T v) as rows is v @ R

    def sdf(X, with_parts=False):
        ds = np.stack([model.parts[n][1](inv(n, X)) for n in model.names], 1)
        total = ds.min(1)
        return (total, ds) if with_parts else total
    return sdf, inv


def render_map(model, view, T):
    """Per pixel: covered, the part, and the mean REST position (body coordinates) of the part's samples there."""
    fc = pt.Facing(view, model.ground)
    sdf, inv = posed_sdf(model, T)
    n, SS, top = model.frame, model.ss, model.top
    W = n * SS
    jj, ii = np.meshgrid(np.arange(W), np.arange(W))
    sx, sy = (jj.ravel() + 0.5) / SS, (ii.ravel() + 0.5) / SS
    origins = np.stack([sx + top / 1.5, sy + top / 1.5, np.full(sx.shape, top)], 1)
    direction = -pt.TOWARD_VIEW
    hit, t = pt.march(fc, origins, direction, max_t=(top + 1) / pt.TOWARD_VIEW[2], sdf=sdf)
    idx = np.nonzero(hit)[0]
    X = fc.to_body(origins[idx] + t[idx, None] * direction)
    _, ds = sdf(X, with_parts=True)
    part = np.argmin(ds, 1)
    rest = np.zeros_like(X)
    for p in np.unique(part):
        m = part == p
        rest[m] = inv(model.names[p], X[m])
    blk = (idx // W // SS) * n + (idx % W) // SS
    cov = np.bincount(blk, minlength=n * n)
    on = cov >= 0.45 * SS * SS
    cnt = np.zeros((n * n, len(model.names)))
    np.add.at(cnt, (blk, part), 1)
    pmain = np.argmax(cnt, 1)
    sel = part == pmain[blk]
    k = np.maximum(np.bincount(blk[sel], minlength=n * n), 1)
    mean = np.stack([np.bincount(blk[sel], weights=rest[sel, i], minlength=n * n) / k for i in range(3)], 1)
    return on.reshape(n, n), pmain.reshape(n, n), mean.reshape(n, n, 3), fc


def rest_pixel(model, fc, Xr):
    """Where a rest point of the body is drawn (the frame's pixel)."""
    wx = model.ground[0] + Xr[..., 0] * fc.F[0] + Xr[..., 1] * fc.R[0] - Xr[..., 2] / 1.5
    wy = model.ground[1] + Xr[..., 0] * fc.F[1] + Xr[..., 1] * fc.R[1] - Xr[..., 2] / 1.5
    return np.floor(wx).astype(int), np.floor(wy).astype(int)


def lum(c):
    return 0.299 * c[..., 0] + 0.587 * c[..., 1] + 0.114 * c[..., 2]


def posed_pixel(model, fc, T, name, Xr):
    """Where a rest point of a part is drawn once the part is posed."""
    R, c, t = T[name]
    return rest_pixel(model, fc, (Xr - c) @ R.T + c + t)


def posed_paint(shape, model, view, T, own=(), drop=()):
    """The SHAPE's own painting of a pose (creature_kit.Shape), for the parts the painting never had (`own`), and
    where they come out in front. `drop`: parts left out of it -- features PixelLab painted somewhere else than the
    shape has them (eyes that sat lower in the shape than in the painting)."""
    import copy
    _, inv = posed_sdf(model, T)
    s2 = copy.copy(shape)
    s2.names = [n for n in shape.names if n not in drop]
    s2.parts = {n: (shape.parts[n][0], (lambda X, n=n: shape.parts[n][1](inv(n, X)))) for n in s2.names}
    on, part, val, dep = s2.render(view)
    return s2.paint(on, part, val, dep), on & np.isin(part, [s2.names.index(n) for n in own if n in s2.names])


def animate(model, view, painting, poses, exact=False, thin=(), own=None, hook=None, post=None):
    """The frames of one view in these poses (`painting`: PixelLab's frame of it, standing).

    `exact`: the painting's own silhouette, where it left the shape's -- the ragged feathers PixelLab drew past it move
    with the part nearest them, and the gaps it left inside the shape stay empty (the seagull; the crab's painting
    matched its shape, and goes the plain way). `thin`: parts the painter drew a little off the shape (a gull's legs):
    no gaps in them, the shape's pixels take the nearest painted pixel of the part, so the leg comes with its foot.
    `own`: (shape, part names, frame indices[, parts to drop, or {view: parts to drop}]) -- parts the painting never
    shows (a tongue): in those frames they are painted by the shape itself (its ramps), over the reprojected frame.
    `hook(view, frame index, rgba) -> rgba`: a 2D touch on the painting before the own parts.
    `post(ctx) -> rgba`: the last touch of a frame, with its part map, the source pixel of each pixel and the pose
    (ctx: view, fi, out, part, on, src, T, fc) -- the frog's sword pasted whole instead of resampled."""
    n = model.frame
    paint_on = painting[..., 3] >= 128
    on0, part0, mean0, fc0 = render_map(model, view, model.rest())
    known = paint_on & on0
    fringe = []
    if exact:
        # each pixel of the fringe goes with the part of the shape nearest it, painted there or not
        _, (fy, fx) = ndimage.distance_transform_edt(~on0, return_indices=True)
        for y, x in zip(*np.nonzero(paint_on & ~on0)):
            sy, sx = fy[y, x], fx[y, x]
            fringe.append((y, x, sy, sx, model.names[part0[sy, sx]], mean0[sy, sx]))
    # for every part: the nearest pixel of the painting that is that part, from anywhere
    nearest = {}
    for p in np.unique(part0[known]):
        m = known & (part0 == p)
        _, (iy, ix) = ndimage.distance_transform_edt(~m, return_indices=True)
        nearest[p] = (iy, ix)
    # the painting's outline colour per material: the darkest of its silhouette pixels
    P = np.pad(paint_on, 1)
    sil0 = paint_on & ~(P[:-2, 1:-1] & P[2:, 1:-1] & P[1:-1, :-2] & P[1:-1, 2:])
    mats = model.mats
    outline = {}
    for mname in set(mats):
        m = sil0 & known & (mats[part0] == mname)
        cols = painting[m][:, :3].astype(int) if m.any() else painting[sil0][:, :3].astype(int)
        outline[mname] = cols[np.argsort(lum(cols))[: max(1, len(cols) // 3)]].mean(0).round().astype(np.uint8)
    frames = []
    # (exact) which pixels of the painting were edge, and which stood alone: those stay as the painter left them
    alone0 = paint_on & (ndimage.convolve(paint_on.astype(int), np.ones((3, 3), int), mode="constant") == 1)
    for fi, T in enumerate(poses):
        on, part, mean, fc = render_map(model, view, T)
        if not exact:
            on = pt.tidy_silhouette(on)
        px, py = rest_pixel(model, fc, mean)
        out = np.zeros((n, n, 4), np.uint8)
        src = np.full((n, n, 2), -1, int)
        for y, x in zip(*np.nonzero(on)):
            p = part[y, x]
            sx, sy = px[y, x], py[y, x]
            if (exact and model.names[p] not in thin and 0 <= sx < n and 0 <= sy < n and on0[sy, sx]
                    and part0[sy, sx] == p and not paint_on[sy, sx]):
                continue                                # a gap the painting left: it stays a gap
            if not (0 <= sx < n and 0 <= sy < n and known[sy, sx] and part0[sy, sx] == p):
                if p not in nearest:
                    continue
                iy, ix = nearest[p]
                cy, cx = min(max(sy, 0), n - 1), min(max(sx, 0), n - 1)
                sy, sx = iy[cy, cx], ix[cy, cx]
            out[y, x, :3] = painting[sy, sx, :3]
            out[y, x, 3] = 255
            src[y, x] = (sy, sx)
        # the painting's fringe, moved as the pixel of the shape nearest it moves
        for y, x, sy, sx, name, Xr in fringe:
            ox, oy = rest_pixel(model, fc, Xr)
            px2, py2 = posed_pixel(model, fc, T, name, Xr)
            ty, tx = y + (py2 - oy), x + (px2 - ox)
            if 0 <= ty < n and 0 <= tx < n and out[ty, tx, 3] == 0:
                out[ty, tx, :3] = painting[y, x, :3]
                out[ty, tx, 3] = 255
                src[ty, tx] = (y, x)
        if hook is not None:
            out = hook(view, fi, out)
        # the parts the painting never had, painted by the shape where they come out in front
        if own is not None and fi in own[2]:
            drop = own[3] if len(own) > 3 else ()
            drop = drop.get(view, ()) if isinstance(drop, dict) else drop
            rgba, m = posed_paint(own[0], model, view, T, own[1], drop)
            out[m] = rgba[m]
            src[m] = -1
        # a lone pixel (the tip of a moved limb, cut off by the coverage) goes
        o = out[..., 3] > 0
        lone = o & (ndimage.convolve(o.astype(int), np.ones((3, 3), int), mode="constant") == 1)
        if exact:
            ok = src[..., 0] >= 0
            lone &= ~(ok & alone0[np.clip(src[..., 0], 0, n - 1), np.clip(src[..., 1], 0, n - 1)])
        out[lone] = 0
        # the silhouette outlined again, with the painting's own dark: a moved limb brings its inside to the edge
        o = out[..., 3] > 0
        Q = np.pad(o, 1)
        sil = o & ~(Q[:-2, 1:-1] & Q[2:, 1:-1] & Q[1:-1, :-2] & Q[1:-1, 2:])
        for y, x in zip(*np.nonzero(sil)):
            if exact and src[y, x, 0] >= 0 and sil0[src[y, x, 0], src[y, x, 1]]:
                continue                                # an edge of the painting: already the painter's edge
            oc = outline[mats[part[y, x]]]
            if lum(out[y, x, :3].astype(int)) > lum(oc.astype(int)) + 18:
                out[y, x, :3] = oc
        if post is not None:
            out = post(dict(view=view, fi=fi, out=out, part=part, on=on, src=src, T=T, fc=fc))
        frames.append(out)
    return frames


def flip(f):
    """The flip on the main diagonal: the Tibia projection's own symmetry (east is south transposed)."""
    return np.ascontiguousarray(f.transpose(1, 0, 2))


def save_gif(out_dir, cols, name, durations, zoom=4):
    """The four directions side by side, on grass, one palette for every frame (nothing blinks)."""
    n = cols["north"][0].shape[0]
    frames = []
    for r in range(len(durations)):
        im = pt.grass_tile(4 * n, n)
        for i, d in enumerate(ORDER):
            im.alpha_composite(Image.fromarray(cols[d][r], "RGBA"), (n * i, 0))
        frames.append(im.resize((4 * n * zoom, n * zoom), Image.NEAREST).convert("RGB"))
    montage = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for i, f in enumerate(frames):
        montage.paste(f, (0, i * f.height))
    pal = montage.quantize(255, method=Image.Quantize.MEDIANCUT)
    gif = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    gif[0].save(os.path.join(out_dir, name + "_x4.gif"), save_all=True, append_images=gif[1:],
                duration=list(durations), loop=0, disposal=1)


def save_sheet(out_dir, cols, name, cell=128):
    """The sheet (a column per direction, the frames down) and the same on grass, each frame `cell` pixels wide."""
    n = cols["north"][0].shape[0]
    rows = len(cols["north"])
    sheet = np.concatenate([np.concatenate([cols[d][r] for d in ORDER], 1) for r in range(rows)], 0)
    Image.fromarray(sheet, "RGBA").save(os.path.join(out_dir, name + ".png"))
    strip = Image.new("RGBA", (4 * (cell + 4) - 4, rows * (cell + 4) - 4), (34, 36, 40, 255))
    for i, d in enumerate(ORDER):
        for r in range(rows):
            g = pt.grass_tile(n, n)
            g.alpha_composite(Image.fromarray(cols[d][r], "RGBA"))
            strip.alpha_composite(g.resize((cell, cell), Image.NEAREST), (i * (cell + 4), r * (cell + 4)))
    strip.save(os.path.join(out_dir, name + "_frames_x2.png"))
    print(os.path.join(out_dir, name + ".png"))


# ------------------------------------------------------------------ for a creature file (creatures/<name>.py)

def compose(outer, inner):
    """The rigid transform `inner`, then `outer`, as one (R, c, t): X -> R (X - c) + c + t."""
    Ro, co, to = outer
    Ri, ci, ti = inner
    return Ro @ Ri, ci, Ro @ (ci + ti - co) + co + to - ci


def turn(axis, degrees, about, then=None):
    """A part turned `degrees` about the line through `about` along `axis` (body axes: (1,0,0) forward, (0,1,0) its
    right, (0,0,1) up), and then moved as `then` (the body it hangs from). TEST the sign (render it
    and look): which way a positive angle goes depends on the axis."""
    t = (rotation(axis, math.radians(degrees)), np.asarray(about, float), np.zeros(3))
    return compose(then, t) if then is not None else t


def lifted(pixels=0, forward=0):
    """A whole-pixel move (it comes out identical, only shifted): `pixels` up the diagonal (1.5 of height each),
    `forward` along its facing."""
    return np.eye(3), np.zeros(3), np.array((float(forward), 0.0, 1.5 * pixels))


def by_movement(frames, walks="forward"):
    """A column per direction of MOVEMENT from PixelLab's two views (north, south) and their flips on the main
    diagonal (east is south transposed). "forward": the creature faces where it goes. "sideways" (the crab): it goes
    the way its RIGHT flank points, so moving east is the north view."""
    if walks == "sideways":
        return {"north": [flip(f) for f in frames["north"]], "east": frames["north"],
                "south": [flip(f) for f in frames["south"]], "west": frames["south"]}
    return {"north": frames["north"], "east": [flip(f) for f in frames["south"]],
            "south": frames["south"], "west": [flip(f) for f in frames["north"]]}


def make_sheet(model, painting, idle_poses, walk_poses, name, out_dir, idle_ms, walk_ms, walks="forward",
               exact=True, thin=(), cell=None, own_idle=None, own_walk=None, idle_hook=None, walk_hook=None,
               idle_post=None, walk_post=None):
    """The whole thing: `painting` = the north | south sheet (PixelLab's, or the shape's own to judge the motion
    first). Writes <name>_idle<N>_walking<N>.png (the idle on top, the walk below) and the GIFs.
    `idle_poses`/`walk_poses` may be {view: poses}: a painting that put a part somewhere else in one view (a
    north view painted with the tail where the shape has the sword) gets that view's own poses."""
    n = model.frame
    per_view = lambda poses, v: poses[v] if isinstance(poses, dict) else poses     # noqa: E731
    count = lambda poses: len(poses["north"] if isinstance(poses, dict) else poses)  # noqa: E731
    a = np.asarray(painting).copy()
    a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
    a[a[..., 3] == 0, :3] = 0
    views = {"north": a[:, :n], "south": a[:, n:2 * n]}
    idle = by_movement({v: animate(model, v, views[v], per_view(idle_poses, v), exact, thin, own_idle, idle_hook, idle_post)
                        for v in views}, walks)
    walk = by_movement({v: animate(model, v, views[v], per_view(walk_poses, v), exact, thin, own_walk, walk_hook, walk_post)
                        for v in views}, walks)
    sheet = "%s_idle%d_walking%d" % (name, count(idle_poses), count(walk_poses))
    save_sheet(out_dir, {d: idle[d] + walk[d] for d in ORDER}, sheet, cell=cell or (128 if n <= 64 else 144))
    zoom = 4 if n <= 64 else 3
    save_gif(out_dir, idle, "%s_idle%d" % (name, count(idle_poses)), idle_ms, zoom=zoom)
    save_gif(out_dir, walk, "%s_walking%d" % (name, count(walk_poses)), walk_ms, zoom=zoom)
    for v in ("north", "south"):
        d = int((idle[v][0] != views[v]).any(-1).sum())
        print(v, "idle frame 1 vs the painting: %d px differ" % d)
    return os.path.join(out_dir, sheet + ".png")
