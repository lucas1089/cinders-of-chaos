#!/usr/bin/env python3
"""Render the class outfits and their previews.

    python3 -I client/tools/outfit_art/build.py look  [line]          # standing, 4 directions, all outfits + a stock look
    python3 -I client/tools/outfit_art/build.py frames [line]         # every frame -> out/<key>/<key>.npz + sheet PNG
    python3 -I client/tools/outfit_art/build.py previews [line] --stock PAIR_DIR

Frames per outfit (the stock player layout of the 10.98 dat): directions north, east, south, west; group 0 idle
(1 phase) and group 1 walking (8 phases); pattern z 0 on foot and 1 riding; layer 0 the art, layer 1 the colour
template; addons (pattern y 1, 2) empty. Output in client/tools/outfit_art/out/ (not committed: the code is the source).
"""
import argparse
import os
import sys
import time
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rig  # noqa: E402
from body import pose  # noqa: E402

OUT = os.path.join(HERE, "out")
GROUND = (57.5, 58.5)       # where the feet stand in the 64 frame (the stock looks' place, displacement 8,8)
WALK = 8
LINES = {"warrior": ("warrior", "juggernaut", "berserker")}
SEXES = ("male", "female")


def module_for(line):
    if line == "warrior":
        import warrior_line
        return warrior_line
    raise SystemExit("unknown line " + line)


_cache = {}


def get_rig(line, cls, sex):
    k = (line, cls, sex)
    if k not in _cache:
        _cache[k] = module_for(line).CLASSES[cls](sex)
    return _cache[k]


def render_one(job):
    line, cls, sex, view, kind, k = job
    rg, st = get_rig(line, cls, sex)
    p = pose(st, k=k, mount=(kind == "mount"))
    r = rig.render(rg, view, p, ground=GROUND)
    base, tmpl = rig.paint(rg, r)
    m = r["maps"]
    return job, base, tmpl, (m["part"] + 1) * m["on"] - m["ring"].astype(np.int16), m["rest"]


def jobs_for(line, cls, sex, full=True):
    J = []
    for v in rig.VIEWS:
        J.append((line, cls, sex, v, "idle", None))
        if full:
            J += [(line, cls, sex, v, "walk", k) for k in range(WALK)]
            J.append((line, cls, sex, v, "mount", None))
            J += [(line, cls, sex, v, "mount", k) for k in range(WALK)]
    return J


def run(jobs, procs=4):
    with Pool(procs) as pool:
        out = {}
        for j, b, t, part, rest in pool.imap_unordered(render_one, jobs, chunksize=1):
            out[j] = (b, t)
            MAPS[j] = (part, rest)
        return out


MAPS = {}   # job -> (part map: part index + 1 inside, -1 outline ring, 0 empty; rest coordinates)


def key(cls, sex):
    return "%s_%s" % (cls, sex)


def frames_array(res, line, cls, sex):
    """[group][phase][z][dir][layer] -> 64x64x4, as arrays: idle (1,2,4,2,64,64,4), walk (8,2,4,2,64,64,4)."""
    idle = np.zeros((1, 2, 4, 2, 64, 64, 4), np.uint8)
    walk = np.zeros((WALK, 2, 4, 2, 64, 64, 4), np.uint8)
    for d, v in enumerate(rig.VIEWS):
        for z, kind in ((0, "idle"), (1, "mount")):
            b, t = res[(line, cls, sex, v, kind, None)]
            idle[0, z, d] = (b, t)
        for k in range(WALK):
            for z, kind in ((0, "walk"), (1, "mount")):
                b, t = res[(line, cls, sex, v, kind, k)]
                walk[k, z, d] = (b, t)
    return idle, walk


# ------------------------------------------------------------------------------------------------ pictures
BG = (52, 48, 46, 255)


def ash_ground(w, h):
    """A dark ash-stone ground to judge on (the game's own floors are this dark)."""
    yy, xx = np.mgrid[0:h, 0:w]
    import tibia_view as pt
    nz = pt.hash01(yy // 2, xx // 2, np.full_like(yy, 3)) * 0.6 + pt.hash01(yy // 6, xx // 6, np.full_like(yy, 4)) * 0.4
    base = np.array((58, 52, 50))
    col = base[None, None, :] * (0.8 + 0.3 * nz[..., None])
    return Image.fromarray(np.dstack([np.clip(col, 0, 255), np.full((h, w), 255)]).astype(np.uint8), "RGBA")


def compose(cells, cols, cell=64, zoom=1, bg=None, gap=0, labels=None, label_h=0):
    rows = (len(cells) + cols - 1) // cols
    W = cols * (cell * zoom + gap) + gap
    Hh = rows * (cell * zoom + gap + label_h) + gap
    im = Image.new("RGBA", (W, Hh), (28, 26, 26, 255))
    dr = ImageDraw.Draw(im)
    for i, c in enumerate(cells):
        x = gap + (i % cols) * (cell * zoom + gap)
        y = gap + (i // cols) * (cell * zoom + gap + label_h)
        g = (bg or ash_ground)(cell, cell) if callable(bg or ash_ground) else bg
        if c is not None:
            g = g.copy()
            g.alpha_composite(Image.fromarray(np.ascontiguousarray(c), "RGBA"))
        im.alpha_composite(g.resize((cell * zoom, cell * zoom), Image.NEAREST), (x, y + label_h))
        if labels and labels[i]:
            dr.text((x + 2, y + 1), labels[i], fill=(220, 210, 190, 255))
    return im


def save(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.convert("RGB").save(path)
    print(path)


def stock_frames(pair, look):
    import stockread
    d, s = stockread.load(pair)
    return stockread.frames(d, s, look)


def cmd_look(line, stock):
    classes = LINES[line]
    J = []
    for c in classes:
        for sx in SEXES:
            J += jobs_for(line, c, sx, full=False)
    t0 = time.time()
    res = run(J)
    print("rendered %d in %.1fs" % (len(J), time.time() - t0))
    cells, labels = [], []
    for c in classes:
        for sx in SEXES:
            for v in rig.VIEWS:
                cells.append(res[(line, c, sx, v, "idle", None)][0])
                labels.append("%s %s %s" % (c[:4], sx[0], v[0]))
    if stock:
        F = stock_frames(stock, 131)
        for d, v in enumerate(rig.VIEWS):
            cells.append(F[(0, 0, d, 0, 0, 0)])
            labels.append("stock ruler %s" % v[0])
    one = compose(cells, 8)
    big = compose(cells, 8, zoom=4, gap=4, labels=labels, label_h=12)
    out = Image.new("RGBA", (one.width + big.width + 8, max(one.height, big.height)), (20, 20, 20, 255))
    out.alpha_composite(one, (0, 0))
    out.alpha_composite(big, (one.width + 8, 0))
    save(out, os.path.join(OUT, "look_%s.png" % line))


def cmd_frames(line):
    J = []
    for c in LINES[line]:
        for sx in SEXES:
            J += jobs_for(line, c, sx)
    t0 = time.time()
    res = run(J)
    print("rendered %d frames in %.0fs" % (len(J), time.time() - t0))
    for c in LINES[line]:
        for sx in SEXES:
            idle, walk = frames_array(res, line, c, sx)
            d = os.path.join(OUT, key(c, sx))
            os.makedirs(d, exist_ok=True)
            np.savez_compressed(os.path.join(d, "frames.npz"), idle=idle, walk=walk)
            mp = {}
            for (l2, c2, s2, v, kind, k), (part, rest) in MAPS.items():
                if (c2, s2) == (c, sx):
                    tag = "%s_%s_%s" % (v, kind, "x" if k is None else k)
                    mp["part_" + tag] = part
                    mp["rest_" + tag] = rest.astype(np.float16)
            np.savez_compressed(os.path.join(d, "maps.npz"), **mp)
            print(os.path.join(d, "frames.npz"))


VARIANT = ""     # "" the shape's own painting; else frames_<variant>.npz (e.g. a PixelLab repaint, repaint.py)


def load_frames(c, sx, variant=None):
    v = VARIANT if variant is None else variant
    z = np.load(os.path.join(OUT, key(c, sx), "frames%s.npz" % ("_" + v if v else "")))
    return z["idle"], z["walk"]


DEFAULT_COLOURS = (78, 69, 58, 76)       # the client's default new-character colours (head, body, legs, feet)
COMBOS = [((78, 69, 58, 76), "default"), ((0, 114, 95, 114), "ash & blood"), ((95, 76, 57, 114), "ember"),
          ((114, 87, 86, 95), "iron & bone"), ((57, 38, 19, 0), "pale"), ((116, 21, 2, 116), "black & gold")]


def tinted(b, t, cols):
    return rig.colourize(b, t, *cols)


def cmd_previews(line, stock):
    classes = LINES[line]
    SF = stock_frames(stock, 131) if stock else None
    SFf = stock_frames(stock, 139) if stock else None
    for c in classes:
        for sx in SEXES:
            idle, walk = load_frames(c, sx)
            k = key(c, sx) + ("_" + VARIANT if VARIANT else "")
            base = os.path.join(OUT, key(c, sx))
            # 1. the four directions, standing: art, template, default colours; 1x and 4x
            cells, labels = [], []
            for d, v in enumerate(rig.VIEWS):
                cells.append(tinted(idle[0, 0, d, 0], idle[0, 0, d, 1], DEFAULT_COLOURS)); labels.append(v)
            for d, v in enumerate(rig.VIEWS):
                cells.append(idle[0, 0, d, 0]); labels.append(v + " art")
            for d, v in enumerate(rig.VIEWS):
                cells.append(idle[0, 0, d, 1]); labels.append(v + " mask")
            sheet(cells, labels, 4, os.path.join(base, k + "_directions.png"))
            # 2. the walk: 8 phases x 4 directions, default colours
            cells, labels = [], []
            for d, v in enumerate(rig.VIEWS):
                for p in range(WALK):
                    cells.append(tinted(walk[p, 0, d, 0], walk[p, 0, d, 1], DEFAULT_COLOURS)); labels.append("%s %d" % (v[0], p + 1))
            sheet(cells, labels, WALK, os.path.join(base, k + "_walk.png"))
            gif(walk, os.path.join(base, k + "_walk_x4.gif"))
            # 3. riding (pattern z 1): standing + 8 steps, south and east
            cells, labels = [], []
            for d in (2, 1):
                cells.append(tinted(idle[0, 1, d, 0], idle[0, 1, d, 1], DEFAULT_COLOURS)); labels.append("ride " + rig.VIEWS[d][0])
                for p in range(0, WALK, 2):
                    cells.append(tinted(walk[p, 1, d, 0], walk[p, 1, d, 1], DEFAULT_COLOURS)); labels.append("ride %d" % (p + 1))
            if SF is not None:
                cells.append((SF if sx == "male" else SFf)[(0, 0, 2, 0, 1, 0)]); labels.append("stock ride")
            sheet(cells, labels, 5, os.path.join(base, k + "_riding.png"))
            # 4. colour combinations (south and east), with the stock look beside it for scale
            cells, labels = [], []
            for cols, name in COMBOS:
                cells.append(tinted(idle[0, 0, 2, 0], idle[0, 0, 2, 1], cols)); labels.append(name)
            if SF is not None:
                S = SF if sx == "male" else SFf
                cells.append(rig.colourize(S[(0, 0, 2, 0, 0, 0)], S[(0, 0, 2, 0, 0, 1)], *DEFAULT_COLOURS)); labels.append("stock (ruler)")
            for cols, name in COMBOS:
                cells.append(tinted(idle[0, 0, 1, 0], idle[0, 0, 1, 1], cols)); labels.append(name)
            if SF is not None:
                cells.append(rig.colourize(S[(0, 0, 1, 0, 0, 0)], S[(0, 0, 1, 0, 0, 1)], *DEFAULT_COLOURS)); labels.append("stock (ruler)")
            sheet(cells, labels, len(COMBOS) + (1 if SF is not None else 0), os.path.join(base, k + "_colours.png"))
    # the line side by side: base and both ascensions, both sexes, south and east, default colours, with the stock look
    cells, labels = [], []
    for sx in SEXES:
        for c in classes:
            idle, _ = load_frames(c, sx)
            for d in (2, 1, 0):
                cells.append(tinted(idle[0, 0, d, 0], idle[0, 0, d, 1], DEFAULT_COLOURS)); labels.append("%s %s %s" % (c, sx[0], rig.VIEWS[d][0]))
    if SF is not None:
        for d in (2, 1, 0):
            cells.append(rig.colourize(SF[(0, 0, d, 0, 0, 0)], SF[(0, 0, d, 0, 0, 1)], *DEFAULT_COLOURS)); labels.append("stock ruler")
    sheet(cells, labels, 9, os.path.join(OUT, "line_%s%s.png" % (line, "_" + VARIANT if VARIANT else "")))


def sheet(cells, labels, cols, path):
    """The same cells at 1x (top) and 4x (below, labelled) on the dark ground."""
    one = compose(cells, cols, gap=2)
    big = compose(cells, cols, zoom=4, gap=4, labels=labels, label_h=12)
    out = Image.new("RGBA", (max(one.width, big.width), one.height + big.height + 6), (20, 20, 20, 255))
    out.alpha_composite(one, (0, 0))
    out.alpha_composite(big, (0, one.height + 6))
    save(out, path)


def gif(walk, path, zoom=4):
    frames = []
    for p in range(WALK):
        im = ash_ground(4 * 64, 64)
        for d in range(4):
            im.alpha_composite(Image.fromarray(tinted(walk[p, 0, d, 0], walk[p, 0, d, 1], DEFAULT_COLOURS)), (64 * d, 0))
        frames.append(im.resize((im.width * zoom, im.height * zoom), Image.NEAREST).convert("RGB"))
    strip = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for i, f in enumerate(frames):
        strip.paste(f, (0, i * f.height))
    pal = strip.quantize(255, method=Image.Quantize.MEDIANCUT)
    g = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    g[0].save(path, save_all=True, append_images=g[1:], duration=[150] * len(g), loop=0, disposal=1)
    print(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("line", nargs="?", default="warrior")
    ap.add_argument("--stock", default=None)
    ap.add_argument("--variant", default="")
    a = ap.parse_args()
    global VARIANT
    VARIANT = a.variant
    if a.cmd == "look":
        cmd_look(a.line, a.stock)
    elif a.cmd == "frames":
        cmd_frames(a.line)
    elif a.cmd == "previews":
        cmd_previews(a.line, a.stock)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
