#!/usr/bin/env python3
"""Render the new class looks of class_art_line.py into the import_art_things.py outfit layout, with previews.

    python3 -I client/tools/outfit_art/class_art.py look  [KEY ...] --out-dir DIR        # standing, 4 directions, addons
    python3 -I client/tools/outfit_art/class_art.py build [KEY ...] --out-dir DIR [--layout 2+4|1+8] [--procs 4]

KEY is a look of class_art_line.LOOKS (lich, inquisitor, necromancer, thief, ninja, templar) or look_sex
(necromancer_female); none means all. `build` writes, per look and sex:
  DIR/<look>_<sex>.png    the sheet (one row per group and phase; one 64x64 column per
                          ((z * 3 + addon) * 2 + layer) * 4 + direction: on foot / riding, base / addon 1 / addon 2,
                          art / colour template, north / east / south / west)
  DIR/things.csv          one row per outfit (import_art_things.py --things DIR/things.csv)
  DIR/preview/<key>_*.png the directions with and without addons (tinted and as art + template), idle and walk,
                          riding, colour combinations; a walk GIF; DIR/preview/overview.png (every look, side by side)

The layout: 2x2 tiles, displacement 8,8 (the stock player looks' place), 2 layers (art + colour template: yellow
head, red body, green legs, blue feet), 4 directions, 3 addon patterns, 2 mount patterns (on foot, riding).
--layout 2+4 (the default, the importer's own creature layout): idle 2 phases (standing and a breath, 600 ms each),
walking 4 phases (steps 1, 3, 5, 7 of the 8-step walk). --layout 1+8: the stock player layout (idle 1, walking 8).
An addon pattern holds only the pixels the addon changes (the figure rendered with the addon minus the figure
without it): the client draws it over pattern 0. Deterministic: the same code gives the same PNGs.
"""
import argparse
import csv
import math
import os
import sys
import time
from multiprocessing import Pool

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rig  # noqa: E402
from body import pose, swing  # noqa: E402
import class_art_line as L  # noqa: E402

GROUND = (57.5, 58.5)      # where the feet stand in the 64 frame (stock player looks, displacement 8,8)
FRAME = 64
LAYOUTS = {"2+4": ((None, "breath"), (0, 2, 4, 6)), "1+8": ((None,), tuple(range(8)))}
VARIANTS = ((), (1,), (2,))   # pattern y: base, addon 1, addon 2
IDLE_MS, WALK_MS = 600, 150
FIELDS = ["key", "cat", "kind", "name", "atlas", "x", "y", "w", "h", "patterns", "phases", "flags", "mode", "server_id", "extra"]
DEFAULT_COLOURS = (78, 69, 58, 76)
COMBOS = [((78, 69, 58, 76), "default"), ((0, 114, 95, 114), "ash & blood"), ((95, 76, 57, 114), "ember"),
          ((114, 87, 86, 95), "iron & bone"), ((57, 38, 19, 0), "pale"), ((116, 21, 2, 116), "black & gold")]


def all_keys():
    return [(look, sex) for look, (_, sexes, _) in L.LOOKS.items() for sex in sexes]


def pick_keys(args):
    keys = all_keys()
    if not args:
        return keys
    out = []
    for a in args:
        got = [k for k in keys if a in (k[0], "%s_%s" % k)]
        if not got:
            raise SystemExit("unknown look %s (have: %s)" % (a, ", ".join("%s_%s" % k for k in keys)))
        out += [k for k in got if k not in out]
    return out


_cache = {}


def get_look(look, sex):
    if (look, sex) not in _cache:
        _cache[(look, sex)] = L.LOOKS[look][0](sex)
    return _cache[(look, sex)]


def get_rig(look, sex, var):
    k = (look, sex, var)
    if k not in _cache:
        lk = get_look(look, sex)
        _cache[k] = lk.with_addons(var) if var else lk.rig
    return _cache[k]


STRIDE, KNEE = 7.0, 12.0      # the walk's thigh swing and knee bend (body.pose: 24 and 30): the stock players keep the
                              # feet under the body, and a longer stride crosses the frame's bottom / right edge


def pose_of(st, ph, mount):
    """ph: None standing, "breath" standing with the chest and head 1 px lower, 0..7 a walking step."""
    if ph not in (None, "breath") and not mount:
        P = pose(st, ph, mount)
        s, c = math.sin(2 * math.pi * ph / 8), math.cos(2 * math.pi * ph / 8)
        P["thigh_r"] = (swing(STRIDE * s), np.zeros(3))
        P["thigh_l"] = (swing(-STRIDE * s), np.zeros(3))
        P["shin_r"] = (swing(-KNEE * max(0.0, c) - 4 * max(0.0, -s)), np.zeros(3))
        P["shin_l"] = (swing(-KNEE * max(0.0, -c) - 4 * max(0.0, s)), np.zeros(3))
        return P
    if ph == "breath":
        P = pose(st, None, mount)
        R, _ = P["torso"]
        P["torso"] = (R, np.array((0, 0, -1.5 / 1.2)))     # one pixel down the diagonal (the h scale is 1.2)
        return P
    return pose(st, ph, mount)


def render_job(job):
    look, sex, var, z, view, ph, ss = job
    lk = get_look(look, sex)
    rg = get_rig(look, sex, var)
    p = pose_of(lk.stance, ph, z == 1)
    r = rig.render(rg, view, p, frame=FRAME, ground=GROUND, ss=ss)
    base, tmpl = rig.paint(rg, r)
    ov = rig.overflow(rg, view, p, GROUND) if ss >= 4 else 0
    return job, base, tmpl, ov


def run(jobs, procs):
    out, over = {}, []
    if procs <= 1:
        it = map(render_job, jobs)
        for j, b, t, ov in it:
            out[j] = (b, t)
            if ov:
                over.append((j, ov))
        return out, over
    with Pool(procs) as pool:
        for j, b, t, ov in pool.imap_unordered(render_job, jobs, chunksize=2):
            out[j] = (b, t)
            if ov:
                over.append((j, ov))
    return out, over


# ------------------------------------------------------------------------------------------------ the sheet
def addon_layer(base, var):
    """(art, template) of an addon pattern: the pixels where the figure with the addon differs from the base."""
    (b0, t0), (b1, t1) = base, var
    ch = (b0 != b1).any(-1) | (t0 != t1).any(-1)
    a = np.where(ch[..., None], b1, 0).astype(np.uint8)
    t = np.where((ch & (t1[..., 3] > 0))[..., None], t1, 0).astype(np.uint8)
    return a, t


def column(z, y, layer, d, addons=3, layers=2):
    return ((z * addons + y) * layers + layer) * 4 + d


def slots(res, look, sex, layout, ss):
    """{(group, phase, z, y, d): (art, template)} from the rendered jobs."""
    groups = LAYOUTS[layout]
    out = {}
    for g, phs in enumerate(groups):
        for i, ph in enumerate(phs):
            for z in (0, 1):
                for d, view in enumerate(rig.VIEWS):
                    base = res[(look, sex, (), z, view, ph, ss)]
                    out[(g, i, z, 0, d)] = base
                    for y in (1, 2):
                        out[(g, i, z, y, d)] = addon_layer(base, res[(look, sex, VARIANTS[y], z, view, ph, ss)])
    return out


def sheet(sl, layout):
    groups = LAYOUTS[layout]
    rows = sum(len(p) for p in groups)
    img = np.zeros((rows * FRAME, 48 * FRAME, 4), np.uint8)
    row = 0
    for g, phs in enumerate(groups):
        for i in range(len(phs)):
            for (gg, ii, z, y, d), (a, t) in sl.items():
                if (gg, ii) != (g, i):
                    continue
                for layer, px in ((0, a), (1, t)):
                    c = column(z, y, layer, d)
                    img[row * FRAME:(row + 1) * FRAME, c * FRAME:(c + 1) * FRAME] = px
            row += 1
    return img


def things_row(look, sex, layout):
    groups = LAYOUTS[layout]
    n0, n1 = len(groups[0]), len(groups[1])
    durs = []
    for g, n in enumerate((n0, n1)):
        if n > 1:
            ms = IDLE_MS if g == 0 else WALK_MS
            durs.append("durs%d=%s|anim%d=0:0:0" % (g, "/".join(["%d:%d" % (ms, ms)] * n), g))
    head, body, legs, feet = L.COLOURS[look]
    extra = "|".join(["gtypes=0+1", "layers=2", "addons=3", "mounts=2", "exact=64+64"] + durs +
                     ["head=%d" % head, "body=%d" % body, "legs=%d" % legs, "feet=%d" % feet])
    key = "%s_%s" % (look, sex)
    return {"key": "classart_" + key, "cat": "outfit", "kind": "class", "name": "%s (%s)" % (L.LOOKS[look][2], sex),
            "atlas": key, "x": 0, "y": 0, "w": 2, "h": 2, "patterns": 4, "phases": "%d+%d" % (n0, n1),
            "flags": "displacement:8:8", "mode": "new", "server_id": "", "extra": extra}


def check_template(t):
    """Template pixels are only the four region colours (or empty)."""
    on = t[..., 3] > 0
    cols = {tuple(c) for c in t[on][:, :3].tolist()}
    ok = {tuple(v) for v in rig.REGIONS.values()}
    return cols <= ok, cols - ok


# ------------------------------------------------------------------------------------------------ previews
def ground(w, h):
    yy, xx = np.mgrid[0:h, 0:w]
    import tibia_view as pt
    nz = pt.hash01(yy // 2, xx // 2, np.full_like(yy, 3)) * 0.6 + pt.hash01(yy // 6, xx // 6, np.full_like(yy, 4)) * 0.4
    col = np.array((58, 52, 50))[None, None, :] * (0.8 + 0.3 * nz[..., None])
    return Image.fromarray(np.dstack([np.clip(col, 0, 255), np.full((h, w), 255)]).astype(np.uint8), "RGBA")


def client_draw(sl, g, i, z, d, addons, cols):
    """What the client draws: pattern 0 tinted, then each worn addon pattern tinted over it."""
    a, t = sl[(g, i, z, 0, d)]
    out = rig.colourize(a, t, *cols) if cols else a.copy()
    for y in addons:
        aa, tt = sl[(g, i, z, y, d)]
        top = rig.colourize(aa, tt, *cols) if cols else aa
        m = top[..., 3] > 0
        out[m] = top[m]
    return out


def board(cells, cols, labels=None, zoom=4, gap=4, label_h=12):
    from PIL import ImageDraw
    rows = (len(cells) + cols - 1) // cols
    one = Image.new("RGBA", (cols * (FRAME + 2) + 2, rows * (FRAME + 2) + 2), (20, 20, 20, 255))
    big = Image.new("RGBA", (cols * (FRAME * zoom + gap) + gap, rows * (FRAME * zoom + gap + label_h) + gap), (28, 26, 26, 255))
    dr = ImageDraw.Draw(big)
    g = ground(FRAME, FRAME)
    for k, c in enumerate(cells):
        r_, c_ = divmod(k, cols)
        cell = g.copy()
        if c is not None:
            cell.alpha_composite(Image.fromarray(np.ascontiguousarray(c), "RGBA"))
        one.alpha_composite(cell, (2 + c_ * (FRAME + 2), 2 + r_ * (FRAME + 2)))
        x = gap + c_ * (FRAME * zoom + gap)
        y = gap + r_ * (FRAME * zoom + gap + label_h)
        big.alpha_composite(cell.resize((FRAME * zoom, FRAME * zoom), Image.NEAREST), (x, y + label_h))
        if labels and labels[k]:
            dr.text((x + 2, y + 1), labels[k], fill=(220, 210, 190, 255))
    out = Image.new("RGBA", (max(one.width, big.width), one.height + big.height + 6), (20, 20, 20, 255))
    out.alpha_composite(one, (0, 0))
    out.alpha_composite(big, (0, one.height + 6))
    return out


def save(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.convert("RGB").save(path, optimize=True)
    print(path)


WEAR = (((), "no addons"), ((1,), "addon 1"), ((2,), "addon 2"), ((1, 2), "both addons"))


def previews(sl, key, layout, pdir):
    groups = LAYOUTS[layout]
    # 1. the directions, standing: tinted (default colours) without / with each addon, then art and template
    cells, labels = [], []
    for wear, name in WEAR:
        for d, v in enumerate(rig.VIEWS):
            cells.append(client_draw(sl, 0, 0, 0, d, wear, DEFAULT_COLOURS)); labels.append("%s %s" % (v, name))
    for d, v in enumerate(rig.VIEWS):
        cells.append(client_draw(sl, 0, 0, 0, d, (1, 2), None)); labels.append(v + " art")
    for d, v in enumerate(rig.VIEWS):
        t = sl[(0, 0, 0, 0, d)][1].copy()
        for y in (1, 2):
            tt = sl[(0, 0, 0, y, d)][1]
            m = tt[..., 3] > 0
            t[m] = tt[m]
        cells.append(t); labels.append(v + " mask")
    save(board(cells, 4, labels), os.path.join(pdir, key + "_directions.png"))
    # 2. idle and walk, every direction, without and with both addons
    cells, labels = [], []
    nph = len(groups[0]) + len(groups[1])
    for wear, name in (WEAR[0], WEAR[3]):
        for d, v in enumerate(rig.VIEWS):
            for g, phs in enumerate(groups):
                for i in range(len(phs)):
                    cells.append(client_draw(sl, g, i, 0, d, wear, DEFAULT_COLOURS))
                    labels.append("%s %s %d%s" % (v[0], "idle" if g == 0 else "walk", i + 1, " +a" if wear else ""))
    save(board(cells, nph, labels, zoom=3), os.path.join(pdir, key + "_anim.png"))
    # 3. riding (pattern z 1): standing and walking, south and east, with both addons
    cells, labels = [], []
    for d in (2, 1):
        for g, phs in enumerate(groups):
            for i in range(len(phs)):
                cells.append(client_draw(sl, g, i, 1, d, (1, 2), DEFAULT_COLOURS))
                labels.append("ride %s %s %d" % (rig.VIEWS[d][0], "idle" if g == 0 else "walk", i + 1))
    save(board(cells, nph, labels, zoom=3), os.path.join(pdir, key + "_riding.png"))
    # 4. the tinted row: colour combinations, south and east, both addons
    cells, labels = [], []
    for d in (2, 1):
        for cols, name in COMBOS:
            cells.append(client_draw(sl, 0, 0, 0, d, (1, 2), cols)); labels.append(name)
    save(board(cells, len(COMBOS), labels), os.path.join(pdir, key + "_colours.png"))
    # 5. the walk as a GIF (4 directions, both addons, default colours)
    frames = []
    for i in range(len(groups[1])):
        im = ground(4 * FRAME, FRAME)
        for d in range(4):
            im.alpha_composite(Image.fromarray(client_draw(sl, 1, i, 0, d, (1, 2), DEFAULT_COLOURS)), (FRAME * d, 0))
        frames.append(im.resize((im.width * 3, im.height * 3), Image.NEAREST).convert("RGB"))
    strip = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for k, f in enumerate(frames):
        strip.paste(f, (0, k * f.height))
    pal = strip.quantize(255, method=Image.Quantize.MEDIANCUT)
    gq = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    path = os.path.join(pdir, key + "_walk.gif")
    gq[0].save(path, save_all=True, append_images=gq[1:], duration=[WALK_MS * 2] * len(gq), loop=0, disposal=1)
    print(path)


# ------------------------------------------------------------------------------------------------ commands
def cmd_look(keys, out, procs, ss):
    J = [(lk, sx, var, 0, v, None, ss) for lk, sx in keys for var in (VARIANTS + ((1, 2),)) for v in rig.VIEWS]
    t0 = time.time()
    res, _ = run(J, procs)
    print("rendered %d in %.0fs" % (len(J), time.time() - t0))
    for lk, sx in keys:
        cells, labels = [], []
        for cols in (L.COLOURS[lk], DEFAULT_COLOURS):
            for var in VARIANTS + ((1, 2),):
                for v in rig.VIEWS:
                    b, t = res[(lk, sx, var, 0, v, None, ss)]
                    cells.append(rig.colourize(b, t, *cols)); labels.append("%s +%s" % (v, "".join(map(str, var))))
        save(board(cells, 16, labels, zoom=4), os.path.join(out, "look_%s_%s.png" % (lk, sx)))


def cmd_build(keys, out, procs, layout, ss=5):
    groups = LAYOUTS[layout]
    J = [(lk, sx, var, z, v, ph, ss) for lk, sx in keys for var in VARIANTS for z in (0, 1) for v in rig.VIEWS
         for phs in groups for ph in phs]
    t0 = time.time()
    res, over = run(J, procs)
    print("rendered %d frames in %.0fs" % (len(J), time.time() - t0))
    for j, n in sorted(over, key=str):
        print("OVERFLOW %s: %d px past the frame's right / bottom edge (cut off in the client)" % (j, n))
    rows = []
    pdir = os.path.join(out, "preview")
    for lk, sx in keys:
        key = "%s_%s" % (lk, sx)
        sl = slots(res, lk, sx, layout, ss)
        for (g, i, z, y, d), (a, t) in sl.items():
            ok, bad = check_template(t)
            assert ok, (key, g, i, z, y, d, "template colours", bad)
        img = sheet(sl, layout)
        os.makedirs(out, exist_ok=True)
        Image.fromarray(img, "RGBA").save(os.path.join(out, key + ".png"), optimize=True)
        print(os.path.join(out, key + ".png"))
        rows.append(things_row(lk, sx, layout))
        previews(sl, key, layout, pdir)
    path = os.path.join(out, "things.csv")
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, FIELDS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    print(path)
    if over:
        print("WARNING: %d frames overflow the outfit frame" % len(over))
    return res


def overview(out, keys, layout):
    """Every look built in OUT, south / east / north, without and with both addons (the look's class colours), from
    the sheets."""
    cells, labels = [], []
    groups = LAYOUTS[layout]
    for lk, sx in keys:
        key = "%s_%s" % (lk, sx)
        img = np.asarray(Image.open(os.path.join(out, key + ".png")).convert("RGBA"))
        sl = {}
        for y in range(3):
            for d in range(4):
                a = img[0:FRAME, column(0, y, 0, d) * FRAME:(column(0, y, 0, d) + 1) * FRAME]
                t = img[0:FRAME, column(0, y, 1, d) * FRAME:(column(0, y, 1, d) + 1) * FRAME]
                sl[(0, 0, 0, y, d)] = (a, t)
        for wear in ((), (1, 2)):
            for d in (2, 1, 0):
                cells.append(client_draw(sl, 0, 0, 0, d, wear, L.COLOURS[lk]))
                labels.append("%s %s %s%s" % (lk[:6], sx[0], rig.VIEWS[d][0], " +a" if wear else ""))
    save(board(cells, 6, labels, zoom=3), os.path.join(out, "preview", "overview.png"))


def cmd_edges(keys, layout, procs):
    """Overflow of every pose, direction and variant (no frames are drawn): what the client would cut off."""
    groups = LAYOUTS[layout]
    J = [(lk, sx, var, z, v, ph) for lk, sx in keys for var in VARIANTS + ((1, 2),) for z in (0, 1) for v in rig.VIEWS
         for phs in groups for ph in phs]
    with Pool(procs) as pool:
        got = pool.map(edge_job, J, chunksize=4)
    bad = [(j, n) for j, n in zip(J, got) if n]
    for j, n in bad:
        print("OVERFLOW %s: %d px" % (j, n))
    print("%d of %d poses overflow" % (len(bad), len(J)))
    return bad


def edge_job(job):
    look, sex, var, z, view, ph = job
    lk = get_look(look, sex)
    return rig.overflow(get_rig(look, sex, var), view, pose_of(lk.stance, ph, z == 1), GROUND)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cmd", choices=("look", "build", "overview", "edges"))
    ap.add_argument("keys", nargs="*")
    ap.add_argument("--out-dir", default=None, help="required for look, build and overview")
    ap.add_argument("--layout", default="2+4", choices=sorted(LAYOUTS))
    ap.add_argument("--procs", type=int, default=4)
    ap.add_argument("--ss", type=int, default=5, help="supersampling (5 for the sheets; 3 for quick looks)")
    a = ap.parse_args()
    keys = pick_keys(a.keys)
    if a.cmd != "edges" and not a.out_dir:
        ap.error("--out-dir is required for " + a.cmd)
    if a.cmd == "look":
        cmd_look(keys, a.out_dir, a.procs, min(a.ss, 3))
    elif a.cmd == "edges":
        sys.exit(1 if cmd_edges(keys, a.layout, a.procs) else 0)
    elif a.cmd == "build":
        cmd_build(keys, a.out_dir, a.procs, a.layout, a.ss)
        overview(a.out_dir, [k for k in all_keys() if os.path.exists(os.path.join(a.out_dir, "%s_%s.png" % k))], a.layout)
    else:
        overview(a.out_dir, [k for k in all_keys() if os.path.exists(os.path.join(a.out_dir, "%s_%s.png" % k))], a.layout)


if __name__ == "__main__":
    main()
