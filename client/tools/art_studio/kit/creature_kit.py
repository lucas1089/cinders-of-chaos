"""The CREATURE KIT: from a creature's SHAPE (Python) to its PixelLab painting.

    from creature_kit import Shape
    SHAPE = Shape("crab", parts, ramps, outline, frame=64, ...)     # a creature file: creatures/<name>.py

The way: the SHAPE from Python, a small model of signed distances seen by the Tibia projection (tibia_view.py), lit
from the top-left and read off ramps of discrete tones per material; then PixelLab's Edit images (Pro) only REPAINTS it
(its Create, from scratch, goes back to its own frontal RPG view); then the painting is put on the posed shape, frame
by frame (creature_anim.py).

Each material goes in the shading class it needs:

    mottle    a soft noise of feathers, fur, shell                 painter   thin upright parts (legs, spikes, ribs):
    gloss     a specular spot (beak, horn, eye, wet shell)                   their visible faces turn away from the
    glow      lit by itself (glowing eyes, magic)                            top-left light, so they get the light a
                                                                             pixel artist paints by (screen left)
`shade_hook(ctx)` may change the values after that (a gradient along a part: dark pincer tips).
"""
import os
import random
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tibia_view as pt  # noqa: E402
from tibia_view import hash01, value_noise  # noqa: E402
import pixellab  # noqa: E402

STUDIO = os.path.dirname(HERE)


def out_dir(name):
    """Where everything of a creature goes: out/<name>/ at the root of the studio."""
    path = os.path.join(STUDIO, "out", name)
    os.makedirs(path, exist_ok=True)
    return path


VIEWS = ("north", "east", "south", "west")


class Shape:
    """A creature's shape. `parts`: name -> (material, distance of body points: u forward, v its right, h up, pixels).
    `ground`: where it stands in the frame -- (39.5, 40) in a 64 frame; in a bigger frame the creature stands in the
    bottom-right tile (+32 per 32 more: (71.5, 72) in a 96) and grows up and to the left."""

    def __init__(self, name, parts, ramps, outline, frame=64, ground=None, top=30.0, ss=6,
                 mottle=(), mottle_cell=2.0, gloss=(), glow=(), painter=(), painter_base=0.10,
                 shadow_reach=30.0, rim_drop=3, grain=0.3, grain_salt=9, glint=(), shade_hook=None,
                 folder=None):
        self.name, self.parts, self.names = name, parts, list(parts)
        self.ramps, self.outline = ramps, outline
        self.frame, self.top, self.ss = frame, top, ss
        self.ground = np.asarray(ground if ground is not None else (frame - 24.5, frame - 24.0), float)
        self.mottle, self.mottle_cell, self.gloss, self.glow = mottle, mottle_cell, gloss, glow
        self.painter, self.painter_base = painter, painter_base
        self.shadow_reach, self.rim_drop, self.grain, self.grain_salt = shadow_reach, rim_drop, grain, grain_salt
        self.glint, self.shade_hook = glint, shade_hook
        self.out = out_dir(folder or name)

    def sdf(self, X, with_parts=False):
        ds = np.stack([self.parts[n][1](X) for n in self.names], 1)
        total = ds.min(1)
        return (total, ds) if with_parts else total

    # ---------------------------------------------------------------- the render

    def render(self, view):
        """Per pixel of the frame: covered, the part, the light value (0..1), the height."""
        fc = pt.Facing(view, self.ground)
        n, SS, top = self.frame, self.ss, self.top
        W = n * SS
        jj, ii = np.meshgrid(np.arange(W), np.arange(W))
        sx, sy = (jj.ravel() + 0.5) / SS, (ii.ravel() + 0.5) / SS
        origins = np.stack([sx + top / 1.5, sy + top / 1.5, np.full(sx.shape, top)], 1)
        direction = -pt.TOWARD_VIEW
        hit, t = pt.march(fc, origins, direction, max_t=(top + 1) / pt.TOWARD_VIEW[2], sdf=self.sdf)
        idx = np.nonzero(hit)[0]
        Pw = origins[idx] + t[idx, None] * direction
        X = fc.to_body(Pw)
        nb = pt.normals(X, sdf=self.sdf)
        _, ds = self.sdf(X, with_parts=True)
        part = np.argmin(ds, 1)
        mat = np.array([self.parts[self.names[p]][0] for p in part])
        nw = np.stack([nb[:, 0] * fc.F[0] + nb[:, 1] * fc.R[0], nb[:, 0] * fc.F[1] + nb[:, 1] * fc.R[1], nb[:, 2]], 1)
        lam = np.clip(nw @ pt.LIGHT, 0, 1)
        sh = pt.soft_shadow(fc, X + nb * 0.25, sdf=self.sdf, max_t=self.shadow_reach)
        ao = pt.occlusion(X, nb, sdf=self.sdf)
        sky = 0.5 + 0.5 * nw[:, 2]
        front = np.clip(nw @ pt.TOWARD_VIEW, 0, 1)
        spec = np.clip(nw @ pt.HALF, 0, 1) ** 30
        v = 0.06 + 0.70 * lam * sh + 0.12 * sky + 0.18 * front - 0.28 * ao
        m = np.isin(mat, self.mottle)
        v[m] += value_noise(X[m], self.mottle_cell, 7) * 0.04
        m = np.isin(mat, self.gloss)
        v[m] += 0.25 * spec[m]
        m = np.isin(mat, self.glow)
        v[m] = 0.55 + 0.45 * front[m]
        m = np.isin(mat, self.painter)
        ns = np.stack([nw[m] @ pt.SCR_E, nw[m] @ pt.SCR_S, nw[m] @ pt.TOWARD_VIEW], 1)
        v[m] = self.painter_base + 0.80 * np.clip(ns @ pt.PAINT_LIGHT * 0.6 + 0.4, 0, 1) - 0.12 * ao[m]
        if self.shade_hook:
            v = self.shade_hook(dict(shape=self, X=X, mat=mat, part=part, v=v, nw=nw, lam=lam, sh=sh, ao=ao,
                                     spec=spec, front=front))
        v = np.clip(v, 0, 1)
        blk = (idx // W // SS) * n + (idx % W) // SS
        cov = np.bincount(blk, minlength=n * n)
        on = cov >= 0.45 * SS * SS
        cnt = np.zeros((n * n, len(self.names)))
        np.add.at(cnt, (blk, part), 1)
        pmain = np.argmax(cnt, 1)
        sel = part == pmain[blk]
        vs = np.bincount(blk[sel], weights=v[sel], minlength=n * n) / np.maximum(np.bincount(blk[sel], minlength=n * n), 1)
        hs = np.full(n * n, -np.inf)
        np.maximum.at(hs, blk, Pw[:, 2])
        return on.reshape(n, n), pmain.reshape(n, n), vs.reshape(n, n), hs.reshape(n, n)

    def paint(self, on, part, val, dep):
        """The ramps (discrete tones, a small grain), the rim of a part in front of another, the dark outline."""
        n = self.frame
        on = pt.tidy_silhouette(on)
        mats = np.array([self.parts[self.names[p]][0] for p in part.ravel()]).reshape(n, n)
        yy, xx = np.mgrid[0:n, 0:n]
        grain = (hash01(yy, xx, np.full_like(yy, self.grain_salt)) - 0.5) * self.grain
        rgba = np.zeros((n, n, 4), np.uint8)
        idx = np.zeros((n, n), int)
        for mname, rp in self.ramps.items():
            m = on & (mats == mname)
            k = np.clip(np.round(val * (len(rp) - 1) + grain), 0, len(rp) - 1).astype(int)
            idx = np.where(m, k, idx)
            rgba[m, :3] = rp[k[m]]
            rgba[m, 3] = 255

        def nbr(a, dy, dx, fillv):
            P = np.pad(a, 1, constant_values=fillv)
            return P[1 + dy:n + 1 + dy, 1 + dx:n + 1 + dx]
        rim = np.zeros((n, n), bool)
        sil = np.zeros((n, n), bool)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            non = nbr(on, dy, dx, False)
            sil |= on & ~non
            rim |= on & non & (nbr(part, dy, dx, -1) != part) & (nbr(dep, dy, dx, -np.inf) < dep - 0.9)
        for mname, rp in self.ramps.items():
            m = mats == mname
            k = np.clip(idx - self.rim_drop, 0, len(rp) - 1)
            r = rim & m & ~sil
            rgba[r, :3] = rp[k[r]]
            rgba[sil & m, :3] = self.outline[mname]
        for gm in self.glint:                     # a dark eye's glint: its top-left pixel
            eye = on & (mats == gm)
            glint = eye & ~nbr(eye, -1, 0, False) & ~nbr(eye, 0, -1, False)
            rgba[glint, :3] = (236, 236, 244)
        return rgba

    def view(self, v):
        return self.paint(*self.render(v))

    # ---------------------------------------------------------------- the files

    def save_shape(self, views=("north", "south")):
        """<name>_python.png (the views PixelLab will paint, side by side), the x5 on magenta, all four at x3."""
        frames = {v: self.view(v) for v in VIEWS}
        sheet = np.concatenate([frames[v] for v in views], 1)
        path = os.path.join(self.out, self.name + "_python.png")
        Image.fromarray(sheet, "RGBA").save(path)
        magenta(sheet, 5).save(os.path.join(self.out, self.name + "_python_x5.png"))
        magenta(np.concatenate([frames[v] for v in VIEWS], 1), 3).save(os.path.join(self.out, self.name + "_python_4dir_x3.png"))
        for v in VIEWS:
            ys, xs = np.nonzero(frames[v][..., 3])
            print("%-5s %dx%d px" % (v, xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))
        print(path)
        return path


def magenta(rgba, zoom):
    im = Image.new("RGBA", (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
    im.alpha_composite(Image.fromarray(np.ascontiguousarray(rgba), "RGBA"))
    return im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)


def ramp(anchors, n):
    return pt.ramp(anchors, n)


# ------------------------------------------------------------------ PixelLab: the repaint over the shape

EDIT_PROMPT = """Improve and refine the texture quality of this existing {WHAT} creature sprite sheet: the same creature in {N} views, {CELLS}, idle.

Do NOT redesign it.
Do NOT change the silhouettes, proportions, positions, the perspective, or where its parts are.

THE CREATURE:
{DESIGN}

LIGHTING / DEPTH:
Maintain Tibia-style 45-degree oblique top-down 2.5D perspective: height goes up and to the left.
Light from the upper-left. Deeper shadows on the lower-right.

OUTLINE:
A thin 1-pixel dark outline around each silhouette, tinted toward the creature's own colors, not pure black.

PIXEL ART QUALITY:
Crisp, detailed fantasy game sprite, in the style of the classic Tibia creatures.
Rich tonal variation with hue shifting, texture in readable pixel clusters.
No blurry upscale appearance.
No smooth vector gradients.
No anti-aliasing.
No ground shadow.

IMPORTANT:
Preserve each view's silhouette as closely as possible: the same {WHAT}, only with significantly improved texture, shading and detail.
"""


def edit_prompt(what, design, views=("north", "south"), size=64):
    where = {"north": "facing up (north, seen from behind)", "south": "facing down (south, toward the viewer)",
             "east": "facing right (east)", "west": "facing left (west)"}
    pos = ("left", "right") if len(views) == 2 else ["#%d" % (i + 1) for i in range(len(views))]
    cells = ", ".join("the %s %dx%d cell %s" % (p, size, size, where[v]) for p, v in zip(pos, views))
    return EDIT_PROMPT.format(WHAT=what.upper(), N=len(views), CELLS=cells, DESIGN=design)


def pixellab_edit(src_path, prompt, out_dir_, variants=3):
    """Edit images (Pro) over the shape, `variants` times (different seeds): out_dir_/edit_v<k>.png. Check the
    balance before and after the first round to learn what one costs on your plan; 3 jobs run at once."""
    os.makedirs(out_dir_, exist_ok=True)
    src = np.ascontiguousarray(np.asarray(Image.open(src_path).convert("RGBA")))

    def one(k):
        for attempt in range(4):
            try:
                imgs = pixellab.edit_image_pro(src, prompt, seed=random.randint(1, 2 ** 30), label="v%d" % k)
                break
            except SystemExit as e:
                print("  v%d failed: %s" % (k, e), flush=True)
                imgs = []
                if "402" in str(e) or "422" in str(e):
                    return
        for i, a in enumerate(imgs):
            Image.fromarray(a, "RGBA").save(os.path.join(out_dir_, "edit_v%d%s.png" % (k, "" if i == 0 else "_%d" % (i + 1))))

    with ThreadPoolExecutor(3) as ex:
        list(ex.map(one, range(1, variants + 1)))


def cut_alpha(a):
    """The game draws 0 or 255: the alpha cut at half."""
    a = np.asarray(a).copy()
    on = a[..., 3] >= 128
    a[..., 3] = np.where(on, 255, 0)
    a[~on, :3] = 0
    return a


def review(shape_png, edit_dir, frame, views=("north", "south")):
    """How much of each variant's silhouette is the shape's (1.00 = the same): under ~0.9 PixelLab redrew it."""
    b = np.asarray(Image.open(shape_png).convert("RGBA"))[..., 3] > 0
    rows = [("shape", Image.open(shape_png).convert("RGBA"))]
    for f in sorted(x for x in os.listdir(edit_dir) if x.startswith("edit_v") and x.endswith(".png")):
        a = cut_alpha(Image.open(os.path.join(edit_dir, f)).convert("RGBA"))
        on = a[..., 3] > 0
        if on.shape == b.shape:
            ious = [(on[:, i * frame:(i + 1) * frame] & b[:, i * frame:(i + 1) * frame]).sum() /
                    max((on[:, i * frame:(i + 1) * frame] | b[:, i * frame:(i + 1) * frame]).sum(), 1)
                    for i in range(len(views))]
            print(f, "  ".join("%s %.2f" % (v, x) for v, x in zip(views, ious)))
        rows.append((f, Image.fromarray(a, "RGBA")))
    z = 4 if frame <= 64 else 3
    w, h = rows[0][1].size
    out = Image.new("RGBA", (w * z + 10, len(rows) * (h * z + 10)), (34, 36, 40, 255))
    for r, (_, im) in enumerate(rows):
        bg = Image.new("RGBA", im.size, (255, 0, 255, 255))
        bg.alpha_composite(im)
        out.alpha_composite(bg.resize((w * z, h * z), Image.NEAREST), (5, r * (h * z + 10) + 5))
    path = os.path.join(os.path.dirname(edit_dir.rstrip("/\\")), "edit_compare.png")
    out.save(path)
    print(path)


def pick(path, out_path):
    Image.fromarray(cut_alpha(Image.open(path).convert("RGBA")), "RGBA").save(out_path)
    print(out_path)
