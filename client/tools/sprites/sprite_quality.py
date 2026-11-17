#!/usr/bin/env python3
"""Quality bar for sprites, by numbers (O625; docs/SPRITE_STYLE.md "Quality bar (O625)", client/MANIFEST.md "Quality bar (O625)").

    python3 -I sprite_quality.py measure [--kind KIND] [--cell N] [--ms N] [--json] [--frames] IMAGE_OR_STRIP...
    python3 -I sprite_quality.py measure --dat Tibia.dat --spr Tibia.spr --outfit ID [--outfit ID ...]
    python3 -I sprite_quality.py check --kind boss|creature|outfit|item|effect [--bar BAR.json] [--strict] FILES
    python3 -I sprite_quality.py check --kind boss --dat D --spr S --outfit ID

`measure` prints the metrics of one drawing: canvas use, alpha, palette and colour ramps, shading and light, outline, texture
and detail, and the animation from frame to frame. `check` holds the same numbers to the thresholds of
sprite_quality_bar.json (numbers only, each with a "why"); a failed row is a reason, the run exits 1 when any row fails
(a row marked "warn" only prints). The bar is derived from one reference outfit and has floors per kind and size.

What is read.
  IMAGE        a PNG. Kinds item and effect: one picture, or a strip of square frames side by side (width / height frames).
               Kinds boss, creature, outfit: the import_art_things.py outfit sheet, cells of --cell px (default 128 for boss,
               64 for creature and outfit), one column per direction (north, east, south, west; more columns, the colour
               template and addon overlays, are not read), one row per phase; the last 8 rows are the walk when there are
               more than 8, the rows above them the idle (the layout of art_import/class_redraw and big_bosses).
  --dat --spr  the frames of a pair: an outfit by its id (every frame group, every direction, the base layer, addon 0), or
               --item ID / --effect ID. Frame durations come from the dat.
  --npz FILE   a private reference saved by the O625 study (g0_sprites arrays and a json `meta`), for work without a pair.
Metrics are means over all frames of the art unless a name says otherwise. Deterministic: numpy and Pillow only.
"""
import argparse
import collections
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
BAR = os.path.join(HERE, 'sprite_quality_bar.json')
DIR_NAMES = ('north', 'east', 'south', 'west')
SOLID = 128            # alpha at or above this is a solid pixel
OUTLINE_LUMA = 56.0    # a rim pixel darker than this is an outline pixel
BLACK_MAX = 36         # an outline pixel with every channel below this and little chroma is black
FAMILY_MIN = 0.03      # a hue family is at least this share of the chromatic pixels
STEP_BIN = 6.0         # luma width of one shading step in a ramp
STEP_MIN = 0.015       # a ramp step holds at least this share of its family
RUN_MIN = 8            # a horizontal or vertical run of one colour this long is a flat run
TILE = 32              # detail density is measured per tile of this size
CHANGE_TOL = 12        # a pixel moved by this much in a channel between two frames has changed (a visible change)
LIGHT_CAP = 12         # px from the rim in which the mask normal is used for the light direction


# ---------------------------------------------------------------------------------------------------------------- loading

class Art:
    """frames[group][direction] = list of RGBA uint8 arrays of one shape; ms[group] = durations (or None)."""

    def __init__(self, name, kind=None):
        self.name = name
        self.kind = kind
        self.frames = collections.OrderedDict()
        self.ms = {}

    def add(self, group, direction, frames, ms=None):
        self.frames.setdefault(group, collections.OrderedDict())[direction] = [np.asarray(f, np.uint8) for f in frames]
        if ms is not None:
            self.ms[group] = list(ms)


def _cell_default(kind):
    return 128 if kind == 'boss' else 64


def load_image(path, kind='creature', cell=None, ms=None):
    im = np.array(Image.open(path).convert('RGBA'))
    h, w = im.shape[:2]
    art = Art(os.path.basename(path), kind)
    if kind in ('item', 'effect'):
        n = w // h if w > h and w % h == 0 else 1
        fs = [im[:, i * h:(i + 1) * h] if n > 1 else im for i in range(n)]
        art.add('strip', '-', fs, [ms] * n if ms else None)
        return art
    c = cell or _cell_default(kind)
    if w % c or h % c or (w // c) < 4:
        raise ValueError(f'{path}: {w}x{h} is not a sheet of {c} px cells with 4 direction columns (--cell)')
    cols, rows = w // c, h // c
    cut = lambda r, d: im[r * c:(r + 1) * c, d * c:(d + 1) * c]
    groups = [('idle', range(0, rows - 8)), ('walk', range(rows - 8, rows))] if rows > 8 else [('walk', range(rows))]
    for g, rs in groups:
        rs = list(rs)
        if not rs:
            continue
        for d in range(4):
            art.add(g, DIR_NAMES[d], [cut(r, d) for r in rs], [ms] * len(rs) if ms else None)
    return art


def _compose(t, spr, g, x, ph, layers='base'):
    w, h, exact, nl, px, py, pz, phases, sprites, anim = t.groups[g]
    cv = np.zeros((h * 32, w * 32, 4), np.uint8)
    for l in (range(nl) if layers == 'all' else range(1)):
        for hh in range(h):
            for ww in range(w):
                i = ((((((ph * pz) * py) * px + x) * nl + l) * h + hh) * w + ww)
                a = spr.sprite(sprites[i])
                if a is None:
                    continue
                y0, x0 = (h - 1 - hh) * 32, (w - 1 - ww) * 32
                dst = cv[y0:y0 + 32, x0:x0 + 32].astype(np.float32)
                sa = a[..., 3:4].astype(np.float32) / 255.0
                da = dst[..., 3:4] / 255.0
                oa = sa + da * (1 - sa)
                rgb = (a[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
                cv[y0:y0 + 32, x0:x0 + 32] = np.concatenate([rgb, oa * 255], -1).round().astype(np.uint8)
    return cv


def load_pair(dat_path, spr_path, ident, cat='outfit'):
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    dat, spr = load_pair.cache.get((dat_path, spr_path)) or (Dat(dat_path), Spr(spr_path))
    load_pair.cache[(dat_path, spr_path)] = (dat, spr)
    t = {'outfit': dat.outfit, 'effect': lambda i: dat.effects[i - 1], 'item': lambda i: dat.items[i - 100]}[cat](ident)
    if t is None:
        raise ValueError(f'{cat} {ident} is not in the pair')
    art = Art(f'{cat}{ident}', 'outfit' if cat == 'outfit' else cat)
    for gi, g in enumerate(t.groups):
        w, h, exact, nl, px, py, pz, phases, sprites, anim = g
        gname = 'idle' if (gi == 0) else 'walk'
        if len(t.groups) == 1:
            gname = 'anim'
        durs = [anim[3][i] for i in range(0, len(anim[3]), 2)] if anim else None
        for x in range(px if px >= 4 else 1):
            art.add(gname, DIR_NAMES[x] if px >= 4 else '-', [_compose(t, spr, gi, x, p) for p in range(phases)], durs)
    return art


load_pair.cache = {}


def load_npz(path):
    z = np.load(path)
    meta = json.loads(str(z['meta']))
    art = Art(os.path.basename(path), 'boss')
    for gi, g in enumerate(meta['groups']):
        n = z[f'g{gi}_sprites']
        w, h, nl, px, py, pz, ph = (g[k] for k in ('w', 'h', 'layers', 'px', 'py', 'pz', 'phases'))
        gname = 'anim' if len(meta['groups']) == 1 else ('idle' if gi == 0 else 'walk')
        durs = [d[0] for d in g['anim']['durations']] if g.get('anim') else None
        for x in range(px if px >= 4 else 1):
            fs = []
            for p in range(ph):
                cv = np.zeros((h * 32, w * 32, 4), np.uint8)
                for hh in range(h):
                    for ww in range(w):
                        i = ((((((p * pz) * py) * px + x) * nl) * h + hh) * w + ww)
                        cv[(h - 1 - hh) * 32:(h - hh) * 32, (w - 1 - ww) * 32:(w - ww) * 32] = n[i]
                fs.append(cv)
            art.add(gname, DIR_NAMES[x] if px >= 4 else '-', fs, durs)
    return art


# ---------------------------------------------------------------------------------------------------------------- helpers

def shift(m, dy, dx, fill=0):
    """m moved by (dy, dx): out[y, x] = m[y - dy, x - dx], fill outside."""
    out = np.full_like(m, fill)
    h, w = m.shape[:2]
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = m[ys, xs]
    return out


def nb4(m):
    return [shift(m, 1, 0), shift(m, -1, 0), shift(m, 0, 1), shift(m, 0, -1)]


def luma(rgb):
    rgb = rgb.astype(np.float64)
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def hsv(rgb):
    c = rgb.astype(np.float64) / 255.0
    mx, mn = c.max(-1), c.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-9), 0.0)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    h = np.zeros_like(mx)
    nz = d > 1e-9
    h = np.where(nz & (mx == r), ((g - b) / np.maximum(d, 1e-9)) % 6, h)
    h = np.where(nz & (mx == g) & (mx != r), (b - r) / np.maximum(d, 1e-9) + 2, h)
    h = np.where(nz & (mx == b) & (mx != r) & (mx != g), (r - g) / np.maximum(d, 1e-9) + 4, h)
    return h * 60.0, s, mx


def label(mask, conn=4):
    """connected components of a boolean mask: (labels int32, sizes list indexed by label; label 0 = background)."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    flat = mask.ravel().tolist()
    lf = [0] * (h * w)
    sizes = [0]
    n = 0
    offs = [-1, -w, -w - 1, -w + 1] if conn == 8 else [-1, -w]
    for i in range(h * w):
        if not flat[i] or lf[i]:
            continue
        n += 1
        lf[i] = n
        stack = [i]
        cnt = 0
        while stack:
            p = stack.pop()
            cnt += 1
            y, x = divmod(p, w)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if (dy or dx) and (conn == 8 or not (dy and dx)):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < h and 0 <= xx < w:
                            q = yy * w + xx
                            if flat[q] and not lf[q]:
                                lf[q] = n
                                stack.append(q)
        sizes.append(cnt)
    return np.array(lf, np.int32).reshape(h, w), sizes


def label_equal(key, solid):
    """4-connected components of equal key among solid pixels: sizes list."""
    h, w = key.shape
    kf = key.ravel().tolist()
    sf = solid.ravel().tolist()
    seen = [False] * (h * w)
    sizes = []
    for i in range(h * w):
        if not sf[i] or seen[i]:
            continue
        seen[i] = True
        stack = [i]
        cnt = 0
        k = kf[i]
        while stack:
            p = stack.pop()
            cnt += 1
            y, x = divmod(p, w)
            for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= yy < h and 0 <= xx < w:
                    q = yy * w + xx
                    if sf[q] and not seen[q] and kf[q] == k:
                        seen[q] = True
                        stack.append(q)
        sizes.append(cnt)
    return sizes


def inner_distance(solid):
    """city-block distance of every solid pixel to the nearest non-solid pixel (1 on the rim)."""
    d = np.zeros(solid.shape, np.int32)
    cur = solid.copy()
    k = 1
    while cur.any():
        d[cur] = k
        nxt = cur.copy()
        for n in nb4(cur):
            nxt &= n
        cur = nxt
        k += 1
    return d


def box3(a):
    out = np.zeros_like(a, dtype=np.float64)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            out += shift(a.astype(np.float64), dy, dx)
    return out / 9.0


def circ_mean(deg, wgt=None):
    r = np.radians(deg)
    w = np.ones_like(r) if wgt is None else wgt
    return math.degrees(math.atan2((np.sin(r) * w).sum(), (np.cos(r) * w).sum())) % 360.0


def hue_diff(a, b):
    return (a - b + 180.0) % 360.0 - 180.0


def warmth(h):
    return math.cos(math.radians(h - 40.0))


def compass(lx, ly):
    ang = math.degrees(math.atan2(-ly, lx)) % 360.0
    names = ['right', 'top-right', 'top', 'top-left', 'left', 'bottom-left', 'bottom', 'bottom-right']
    return names[int(((ang + 22.5) % 360) // 45)]


# ---------------------------------------------------------------------------------------------------------------- one frame

def frame_metrics(a, solid_thr=SOLID):
    """metrics of one RGBA frame (HxWx4 uint8): a flat dict of numbers, plus 'families' (list) and 'light' (tuple)."""
    h, w = a.shape[:2]
    al = a[..., 3].astype(np.int32)
    rgb = a[..., :3]
    solid = al >= solid_thr
    vis = al > 0
    n_solid = int(solid.sum())
    m = collections.OrderedDict()
    m['solid_px'] = n_solid
    m['visible_px'] = int(vis.sum())
    if n_solid < 12:
        m['empty'] = 1
        return m, [], (0.0, 0.0)
    m['empty'] = 0
    ys, xs = np.nonzero(solid)
    bw, bh = int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)
    m['bbox_w'], m['bbox_h'] = bw, bh
    m['canvas_w'], m['canvas_h'] = w, h
    m['fill_share'] = n_solid / float(bw * bh)
    m['canvas_share'] = n_solid / float(w * h)
    n4 = nb4(solid)
    ns = sum(n.astype(np.int32) for n in n4)
    perim = int((4 - ns)[solid].sum())
    m['complexity'] = perim / math.sqrt(n_solid)
    pad = np.pad(~solid, 1, constant_values=True)
    lab, sizes = label(pad, 4)
    outside = lab[0, 0]
    holes = [s for i, s in enumerate(sizes) if i and i != outside]
    m['holes'] = len(holes)
    m['hole_px'] = int(sum(holes))
    # alpha
    vals, cnts = np.unique(al[vis], return_counts=True)
    m['alpha_levels'] = int(len(vals))
    m['alpha_255_share'] = float(cnts[vals == 255].sum()) / vis.sum() if (vals == 255).any() else 0.0
    semi = vis & (al < 255)
    m['semi_share'] = float(semi.sum()) / vis.sum()
    clear = al == 0
    clear_n = [shift(clear, 1, 0, True), shift(clear, -1, 0, True), shift(clear, 0, 1, True), shift(clear, 0, -1, True)]
    touch = clear_n[0] | clear_n[1] | clear_n[2] | clear_n[3]
    m['semi_edge_share'] = float((semi & touch).sum()) / max(1, semi.sum())
    m['semi_inside_px'] = int((semi & ~touch).sum())
    # palette
    px = rgb[solid]
    key = (rgb[..., 0].astype(np.int64) << 16) | (rgb[..., 1].astype(np.int64) << 8) | rgb[..., 2].astype(np.int64)
    kk = key[solid]
    m['colours'] = int(len(np.unique(kk)))
    uq, uc = np.unique(kk, return_counts=True)
    m['colours_1pct'] = int((uc >= max(2, 0.001 * n_solid)).sum())
    L = luma(px)
    H, S, V = hsv(px)
    for p in (1, 5, 25, 50, 75, 95, 99):
        m[f'luma_p{p}'] = float(np.percentile(L, p))
    m['contrast'] = m['luma_p95'] - m['luma_p5']
    m['near_black_share'] = float((L < 28).mean())
    m['near_white_share'] = float((L > 232).mean())
    m['sat_mean'], m['sat_std'] = float(S.mean()), float(S.std())
    m['val_mean'], m['val_std'] = float(V.mean()), float(V.std())
    # hue families and ramps
    chrom = (S > 0.15) & (V > 0.12)
    fams = []
    if chrom.sum() >= 12:
        hh = H[chrom]
        hist = np.bincount((hh // 10).astype(int) % 36, minlength=36).astype(float)
        free = np.ones(36, bool)
        total = float(chrom.sum())
        while free.any():
            hw = np.where(free, hist, 0)
            b = int(hw.argmax())
            if hw[b] < FAMILY_MIN * total:
                break
            centre = b * 10 + 5
            sel = np.abs(hue_diff(np.arange(36) * 10 + 5, centre)) <= 30
            sel &= free
            free &= ~sel
            inf = sel[(hh // 10).astype(int) % 36]
            fam_idx = np.nonzero(chrom)
            fh, fl, fs = hh[inf], L[chrom][inf], S[chrom][inf]
            if len(fh) < FAMILY_MIN * total:
                continue
            fk = kk[chrom][inf]
            order = np.argsort(fl)
            q = max(1, len(fl) // 4)
            light, dark = order[-q:], order[:q]
            hl, hd = circ_mean(fh[light]), circ_mean(fh[dark])
            bins = np.floor(fl / STEP_BIN).astype(int)
            bc = np.bincount(bins)
            steps = int((bc >= max(2, STEP_MIN * len(fl))).sum())
            fams.append(dict(hue=circ_mean(fh), px=int(len(fh)), steps=steps, colours=int(len(np.unique(fk))),
                             shift=hue_diff(hl, hd), warm_cool=warmth(hl) - warmth(hd), luma_lo=float(fl[dark].mean()),
                             luma_hi=float(fl[light].mean()), sat=float(fs.mean())))
    grey = ~chrom
    m['families'] = len(fams)
    fp = sum(f['px'] for f in fams) or 1
    m['ramp_steps'] = sum(f['steps'] * f['px'] for f in fams) / fp if fams else 0.0
    m['ramp_steps_max'] = max([f['steps'] for f in fams] or [0])
    m['ramp_warm_cool'] = sum(f['warm_cool'] * f['px'] for f in fams) / fp if fams else 0.0
    m['ramp_hue_shift'] = sum(abs(f['shift']) * f['px'] for f in fams) / fp if fams else 0.0
    m['grey_share'] = float(grey.mean())
    # shading: light from the mask normal, global gradient, pillow
    d = inner_distance(solid)
    hgt = np.minimum(d, LIGHT_CAP).astype(np.float64)
    for _ in range(2):
        hgt = box3(hgt)
    gy, gx = np.gradient(hgt)
    Lf = np.zeros((h, w))
    Lf[solid] = L
    sel = solid & (d <= LIGHT_CAP) & ((np.abs(gx) + np.abs(gy)) > 0.02)
    lx = ly = 0.0
    m['light_r2'] = 0.0
    m['light_strength'] = 0.0
    if sel.sum() >= 30:
        X = np.stack([np.ones(sel.sum()), -gx[sel], -gy[sel]], 1)
        yv = Lf[sel]
        coef, *_ = np.linalg.lstsq(X, yv, rcond=None)
        res = yv - X @ coef
        tot = ((yv - yv.mean()) ** 2).sum()
        m['light_r2'] = float(1 - (res ** 2).sum() / tot) if tot > 0 else 0.0
        nrm = math.hypot(coef[1], coef[2])
        m['light_strength'] = float(nrm)
        if nrm > 1e-9:
            lx, ly = coef[1] / nrm, coef[2] / nrm
    yy, xx = np.nonzero(solid)
    Xg = np.stack([np.ones(len(yy)), xx - xx.mean(), yy - yy.mean()], 1)
    cg, *_ = np.linalg.lstsq(Xg, L, rcond=None)
    rg = L - Xg @ cg
    tg = ((L - L.mean()) ** 2).sum()
    m['lumgrad_r2'] = float(1 - (rg ** 2).sum() / tg) if tg > 0 else 0.0
    ng = math.hypot(cg[1], cg[2])
    m['lumgrad_x'], m['lumgrad_y'] = (float(cg[1] / ng), float(cg[2] / ng)) if ng > 1e-9 else (0.0, 0.0)
    dd = d[solid].astype(np.float64)
    m['pillow_r'] = float(np.corrcoef(dd, L)[0, 1]) if dd.std() > 0 and L.std() > 0 else 0.0
    m['pillow'] = int(abs(m['pillow_r']) >= 0.45 and m['pillow_r'] ** 2 > m['light_r2'])
    # banding: runs of one colour
    run = np.zeros((h, w), bool)
    for arr, axis in ((key, 1), (key.T, 0)):
        sol = solid if axis == 1 else solid.T
        r = np.zeros(sol.shape, bool)
        for yv in range(arr.shape[0]):
            row, rs = arr[yv], sol[yv]
            i = 0
            n = len(row)
            while i < n:
                if not rs[i]:
                    i += 1
                    continue
                j = i
                while j + 1 < n and rs[j + 1] and row[j + 1] == row[i]:
                    j += 1
                if j - i + 1 >= RUN_MIN:
                    r[yv, i:j + 1] = True
                i = j + 1
        run |= r if axis == 1 else r.T
    m['flat_run_share'] = float(run.sum()) / n_solid
    # specular highlights
    mean5 = np.zeros((h, w))
    cnt5 = np.zeros((h, w))
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            mean5 += shift(Lf, dy, dx)
            cnt5 += shift(solid.astype(np.float64), dy, dx)
    loc = mean5 / np.maximum(cnt5, 1)
    spec = solid & (Lf >= np.percentile(L, 98)) & (Lf - loc >= 20)
    if spec.any():
        _, ssz = label(spec, 8)
        ssz = [s for s in ssz[1:] if s <= 40]
    else:
        ssz = []
    m['spec_clusters'] = len(ssz)
    m['spec_mean_size'] = float(np.mean(ssz)) if ssz else 0.0
    m['spec_share'] = float(sum(ssz)) / n_solid
    # outline
    rim = solid & ~(n4[0] & n4[1] & n4[2] & n4[3])
    m['rim_px'] = int(rim.sum())
    dark = solid & (Lf < OUTLINE_LUMA)
    mx = rgb.max(-1).astype(int)
    mnc = rgb.min(-1).astype(int)
    black = dark & (mx <= BLACK_MAX) & ((mx - mnc) <= 16)
    m['outline_coverage'] = float((rim & dark).sum()) / max(1, rim.sum())
    m['outline_black_share'] = float((rim & black).sum()) / max(1, (rim & dark).sum())
    m['outline_hue_share'] = 1.0 - m['outline_black_share'] if (rim & dark).any() else 0.0
    layers = [float((solid & (d == k) & dark).sum()) / max(1, (solid & (d == k)).sum()) for k in (1, 2, 3, 4)]
    m['outline_thick'] = float(sum(layers))
    # selective outline: dark rim px whose hue follows the interior hue near it
    inner = solid & (d >= 3)
    Hr, Sf, Vf = np.zeros((h, w)), np.zeros((h, w)), np.zeros((h, w))
    Hf, Sf2, _ = hsv(rgb)
    wgt = np.where(inner & (Sf2 > 0.15), Sf2, 0.0)
    cs = np.zeros((h, w))
    sn = np.zeros((h, w))
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            cs += shift(np.cos(np.radians(Hf)) * wgt, dy, dx)
            sn += shift(np.sin(np.radians(Hf)) * wgt, dy, dx)
    has = (np.hypot(cs, sn) > 0.5)
    ih = np.degrees(np.arctan2(sn, cs)) % 360
    sel = rim & dark & has
    if sel.any():
        follows = (Sf2[sel] >= 0.2) & (np.abs(hue_diff(Hf[sel], ih[sel])) <= 35)
        m['outline_selout_share'] = float(follows.mean())
    else:
        m['outline_selout_share'] = 0.0
    # texture
    mm = np.zeros((h, w))
    m2 = np.zeros((h, w))
    full = solid.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            full &= shift(solid, dy, dx)
            sh = shift(Lf, dy, dx)
            mm += sh
            m2 += sh * sh
    mm /= 9
    var = np.maximum(m2 / 9 - mm * mm, 0)
    m['local_std'] = float(np.sqrt(var[full]).mean()) if full.any() else 0.0
    sz = label_equal(key, solid)
    sz = np.array(sz)
    m['lone_px_share'] = float(sz[sz == 1].sum()) / n_solid
    m['tiny_px_share'] = float(sz[sz <= 3].sum()) / n_solid
    m['cluster_mean'] = float(sz.mean())
    m['cluster_px_mean'] = float((sz * sz).sum()) / n_solid      # the size of the cluster an average pixel sits in
    m['clusters_per_100px'] = 100.0 * len(sz) / n_solid
    qk = (rgb[..., 0].astype(np.int64) >> 4 << 8) | (rgb[..., 1].astype(np.int64) >> 4 << 4) | (rgb[..., 2].astype(np.int64) >> 4)
    sq = np.array(label_equal(qk, solid))
    m['lone_px_share_q'] = float(sq[sq == 1].sum()) / n_solid
    # dithering: checkerboard 2x2 blocks
    k00, k01, k10, k11 = key[:-1, :-1], key[:-1, 1:], key[1:, :-1], key[1:, 1:]
    s4 = solid[:-1, :-1] & solid[:-1, 1:] & solid[1:, :-1] & solid[1:, 1:]
    chk = s4 & (k00 == k11) & (k01 == k10) & (k00 != k01)
    m['checker_share'] = float(chk.sum()) / max(1, s4.sum())
    # detail density per tile
    ph, pw = -(-h // TILE) * TILE, -(-w // TILE) * TILE
    Lp = np.zeros((ph, pw))
    Lp[:h, :w] = Lf
    sp_ = np.zeros((ph, pw), bool)
    sp_[:h, :w] = solid
    kp = np.zeros((ph, pw), np.int64)
    kp[:h, :w] = key
    dens, cols = [], []
    for ty in range(0, ph, TILE):
        for tx in range(0, pw, TILE):
            ts = sp_[ty:ty + TILE, tx:tx + TILE]
            ns_ = ts.sum()
            if ns_ < 0.25 * TILE * TILE:
                continue
            tl = Lp[ty:ty + TILE, tx:tx + TILE]
            hd = (ts[:, 1:] & ts[:, :-1]) & (np.abs(tl[:, 1:] - tl[:, :-1]) >= 12)
            vd = (ts[1:] & ts[:-1]) & (np.abs(tl[1:] - tl[:-1]) >= 12)
            dens.append((hd.sum() + vd.sum()) / float(ns_))
            cols.append(len(np.unique(kp[ty:ty + TILE, tx:tx + TILE][ts])))
    dens = np.array(dens or [0.0])
    m['detail_mean'] = float(dens.mean())
    m['detail_p10'] = float(np.percentile(dens, 10))
    m['flat_tile_share'] = float((dens < 0.12).mean())
    m['tile_colours_mean'] = float(np.mean(cols or [0]))
    m['tiles'] = len(dens)
    return m, fams, (lx, ly)


# ---------------------------------------------------------------------------------------------------------------- animation

def _changed(a, b, solid_thr=SOLID, tol=CHANGE_TOL):
    """pixels that differ between two frames: solid in one only, or both solid and a channel apart by `tol` or more
    (tol 1: any difference at all)."""
    sa, sb = a[..., 3] >= solid_thr, b[..., 3] >= solid_thr
    both = sa & sb
    dc = np.abs(a[..., :3].astype(np.int16) - b[..., :3].astype(np.int16)).max(-1)
    diff = (sa != sb) | (both & (dc >= tol))
    return diff, sa, sb


def _best_shift(a, b, box, rad=6):
    y0, y1, x0, x1 = box
    la, lb = luma(a[..., :3]) * (a[..., 3] >= SOLID), luma(b[..., :3]) * (b[..., 3] >= SOLID)
    ref = la[y0:y1, x0:x1]
    best, bs = None, (0, 0)
    for dy in range(-rad, rad + 1):
        for dx in range(-rad, rad + 1):
            yy0, yy1, xx0, xx1 = y0 + dy, y1 + dy, x0 + dx, x1 + dx
            if yy0 < 0 or xx0 < 0 or yy1 > lb.shape[0] or xx1 > lb.shape[1]:
                continue
            sad = np.abs(lb[yy0:yy1, xx0:xx1] - ref).sum() + 0.01 * (abs(dy) + abs(dx))
            if best is None or sad < best:
                best, bs = sad, (dy, dx)
    return bs


def seq_metrics(frames, ms=None):
    """animation numbers of one direction's frames."""
    n = len(frames)
    o = collections.OrderedDict()
    o['frames'] = n
    o['distinct_frames'] = len({f.tobytes() for f in frames})
    if ms:
        o['ms_mean'] = float(np.mean(ms))
        o['loop_ms'] = float(np.sum(ms))
    sol = [f[..., 3] >= SOLID for f in frames]
    area = np.array([s.sum() for s in sol], float)
    bb = []
    cen = []
    for s in sol:
        if s.any():
            y, x = np.nonzero(s)
            bb.append((x.max() - x.min() + 1, y.max() - y.min() + 1))
            cen.append((x.mean(), y.mean()))
        else:
            bb.append((0, 0))
            cen.append((0.0, 0.0))
    bb = np.array(bb, float)
    cen = np.array(cen)
    o['area_range'] = float((area.max() - area.min()) / max(1.0, area.mean()))
    o['bbox_w_range'] = float(bb[:, 0].max() - bb[:, 0].min())
    o['bbox_h_range'] = float(bb[:, 1].max() - bb[:, 1].min())
    ratio = bb[:, 1] / np.maximum(bb[:, 0], 1)
    o['ratio_range'] = float((ratio.max() - ratio.min()) / max(ratio.mean(), 1e-9))
    o['centroid_x_range'] = float(cen[:, 0].max() - cen[:, 0].min())
    o['centroid_y_range'] = float(cen[:, 1].max() - cen[:, 1].min())
    if n < 2:
        o.update(changed_px=0.0, changed_share=0.0, changed_exact_share=0.0, loop_ratio=0.0, regions=0.0, motion_px=0.0, shade_only_share=0.0,
                 silhouette_change_share=0.0, largest_region_share=0.0)
        return o
    chg, regs, mot, shade, silh, big = [], [], [], [], [], []
    for i in range(n - 1):
        d, sa, sb = _changed(frames[i], frames[i + 1])
        c = int(d.sum())
        chg.append(c)
        union = max(1, int((sa | sb).sum()))
        silh.append(int((sa != sb).sum()) / union)
        shade.append(float((d & sa & sb).sum()) / max(1, c))
        if c:
            lab, sizes = label(shift(d, 0, 0) | shift(d, 1, 0) | shift(d, -1, 0) | shift(d, 0, 1) | shift(d, 0, -1), 8)
            real = [(j, s) for j, s in enumerate(sizes) if j and s >= 6]
            regs.append(len(real))
            big.append(max([int((d & (lab == j)).sum()) for j, _ in real] or [0]) / c)
            amp = []
            for j, s in real[:8]:
                yy, xx = np.nonzero(lab == j)
                box = (max(0, yy.min() - 1), min(d.shape[0], yy.max() + 2), max(0, xx.min() - 1), min(d.shape[1], xx.max() + 2))
                dy, dx = _best_shift(frames[i], frames[i + 1], box)
                amp.append((math.hypot(dy, dx), int((d & (lab == j)).sum())))
            tw = sum(w for _, w in amp) or 1
            mot.append(sum(a * w for a, w in amp) / tw if amp else 0.0)
        else:
            regs.append(0)
            mot.append(0.0)
            big.append(0.0)
    unions = [max(1, int((a | b).sum())) for a, b in zip(sol[:-1], sol[1:])]
    ex = [int(_changed(frames[i], frames[i + 1], SOLID, 1)[0].sum()) for i in range(n - 1)]
    o['changed_exact_share'] = float(np.mean([c / u for c, u in zip(ex, unions)]))
    o['changed_px'] = float(np.mean(chg))
    o['changed_share'] = float(np.mean([c / u for c, u in zip(chg, unions)]))
    last, _, _ = _changed(frames[-1], frames[0])
    o['loop_ratio'] = float(last.sum()) / max(1.0, float(np.mean(chg)))
    o['loop_exact'] = int(last.sum() == 0)
    o['regions'] = float(np.mean(regs))
    o['motion_px'] = float(np.mean(mot))
    o['motion_max'] = float(np.max(mot))
    o['shade_only_share'] = float(np.mean(shade))
    o['silhouette_change_share'] = float(np.mean(silh))
    o['largest_region_share'] = float(np.mean(big))
    return o


def same_share(a, b, shifted=False, rad=8):
    """share of the pixels of two frames that are equal (1.0: the same picture); with `shifted` b is first moved by the whole-pixel
    shift (within `rad`) that fits best, so a copy placed a few pixels off still counts as the same picture."""
    if shifted:
        sa_, sb_ = a[..., 3] >= SOLID, b[..., 3] >= SOLID
        if not (sa_.any() and sb_.any()):
            return 0.0
        ya, xa = np.nonzero(sa_)
        yb, xb = np.nonzero(sb_)
        cy, cx = int(round(ya.mean() - yb.mean())), int(round(xa.mean() - xb.mean()))
        la, lb = luma(a[..., :3]) * sa_, luma(b[..., :3]) * sb_
        best, bs = None, (cy, cx)
        for dy in range(cy - 2, cy + 3):
            for dx in range(cx - 2, cx + 3):
                if abs(dy) > rad or abs(dx) > rad:
                    continue
                sad = np.abs(shift(lb, dy, dx) - la).sum()
                if best is None or sad < best:
                    best, bs = sad, (dy, dx)
        b = shift(b, bs[0], bs[1])
    d, sa, sb = _changed(a, b, SOLID, 1)
    return 1.0 - float(d.sum()) / max(1, int((sa | sb).sum()))


def mirror_share(east, west, shifted=False):
    """share of pixels equal between the east frames and the mirrored west frames (1.0: the west is a mirror)."""
    return float(np.mean([same_share(e, w[:, ::-1], shifted) for e, w in zip(east, west)]))


# ---------------------------------------------------------------------------------------------------------------- art

def merge_families(fams):
    """the hue families of all frames merged by hue (within 25 degrees), weighted by pixels, biggest first."""
    out = []
    for f in sorted(fams, key=lambda f: -f['px']):
        for o in out:
            if abs(hue_diff(f['hue'], o['hue'])) <= 25:
                o['members'].append(f)
                break
        else:
            out.append(dict(hue=f['hue'], members=[f]))
    res = []
    for o in out:
        ms = o['members']
        tw = float(sum(m['px'] for m in ms))
        r = {k: sum(m[k] * m['px'] for m in ms) / tw for k in ('steps', 'colours', 'shift', 'warm_cool', 'luma_lo', 'luma_hi', 'sat')}
        r.update(hue=o['hue'], px=tw / len(ms) * len(ms) / max(1, len(ms)), frames=len(ms))
        res.append(r)
    for r in res:
        r['px'] = r['px']
    return sorted(res, key=lambda r: -r['px'] * r['frames'])[:8]


STAT = ['solid_px', 'bbox_w', 'bbox_h', 'fill_share', 'canvas_share', 'complexity', 'holes', 'hole_px', 'alpha_levels',
        'alpha_255_share', 'semi_share', 'semi_edge_share', 'semi_inside_px', 'colours', 'colours_1pct', 'luma_p1',
        'luma_p5', 'luma_p25', 'luma_p50', 'luma_p75', 'luma_p95', 'luma_p99', 'contrast', 'near_black_share',
        'near_white_share', 'sat_mean', 'sat_std', 'val_mean', 'val_std', 'families', 'ramp_steps', 'ramp_steps_max',
        'ramp_warm_cool', 'ramp_hue_shift', 'grey_share', 'light_r2', 'light_strength', 'lumgrad_r2', 'pillow_r',
        'pillow', 'flat_run_share', 'spec_clusters', 'spec_mean_size', 'spec_share', 'rim_px', 'outline_coverage',
        'outline_black_share', 'outline_hue_share', 'outline_thick', 'outline_selout_share', 'local_std',
        'lone_px_share', 'tiny_px_share', 'cluster_mean', 'cluster_px_mean', 'clusters_per_100px', 'lone_px_share_q',
        'checker_share', 'detail_mean', 'detail_p10', 'flat_tile_share', 'tile_colours_mean']
ANIM = ['frames', 'distinct_frames', 'ms_mean', 'loop_ms', 'area_range', 'bbox_w_range', 'bbox_h_range', 'ratio_range',
        'centroid_x_range', 'centroid_y_range', 'changed_px', 'changed_share', 'changed_exact_share', 'loop_ratio', 'loop_exact', 'regions',
        'motion_px', 'motion_max', 'shade_only_share', 'silhouette_change_share', 'largest_region_share']


def analyse(art, solid_thr=SOLID, per_frame=False):
    """-> dict: summary (flat means), dirs (per direction means), anim (per group and direction), frames (optional)."""
    allm, bydir, fam_all, lights = [], collections.OrderedDict(), [], collections.defaultdict(list)
    frames_out = []
    anim = collections.OrderedDict()
    cache = {}
    for g, dirs in art.frames.items():
        for dn, fs in dirs.items():
            for i, f in enumerate(fs):
                kb = f.tobytes()
                if kb not in cache:
                    cache[kb] = frame_metrics(f, solid_thr)
                m, fams, lv = cache[kb]
                if m.get('empty'):
                    continue
                allm.append(m)
                bydir.setdefault(dn, []).append(m)
                fam_all.extend(fams)
                if lv != (0.0, 0.0):
                    lights[dn].append(lv)
                if per_frame:
                    frames_out.append(dict(group=g, dir=dn, frame=i, **m))
            anim[(g, dn)] = seq_metrics(fs, art.ms.get(g))
    summary = collections.OrderedDict()
    for k in STAT:
        v = [m[k] for m in allm if k in m]
        summary[k] = float(np.mean(v)) if v else 0.0
    for k in ('solid_px', 'bbox_w', 'bbox_h'):
        v = [m[k] for m in allm]
        summary[k + '_max'] = float(np.max(v)) if v else 0.0
    # light direction: mean vector over frames, its spread by direction
    lv = [x for v in lights.values() for x in v]
    if lv:
        mx_, my_ = np.mean([a for a, _ in lv]), np.mean([b for _, b in lv])
        nn = math.hypot(mx_, my_) or 1.0
        summary['light_x'], summary['light_y'] = float(mx_ / nn), float(my_ / nn)
        summary['light_name'] = compass(mx_, my_)
        angs = [math.degrees(math.atan2(-b, a)) for a, b in lv]
        summary['light_spread_deg'] = float(math.degrees(math.sqrt(max(0.0, -2 * math.log(max(1e-9, min(1.0, nn)))))))
        summary['light_frames_agree'] = float(np.mean([a * mx_ + b * my_ > 0.0 for a, b in lv]))
    else:
        summary.update(light_x=0.0, light_y=0.0, light_name='none', light_spread_deg=180.0, light_frames_agree=0.0)
    am = collections.OrderedDict()
    for k in ANIM:
        v = [a[k] for a in anim.values() if k in a]
        am[k] = float(np.mean(v)) if v else 0.0
    # directions drawn or mirrored
    mir = []
    for g, dirs in art.frames.items():
        if 'east' in dirs and 'west' in dirs:
            mir.append(mirror_share(dirs['east'], dirs['west'], True))
    am['ew_mirror_share'] = float(np.mean(mir)) if mir else -1.0
    same, shsame = [], []
    for g, dirs in art.frames.items():
        names = list(dirs)
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                a_, b_ = dirs[names[i]], dirs[names[j]]
                same.append(float(np.mean([x.tobytes() == y.tobytes() for x, y in zip(a_, b_)])))
                shsame.append(float(np.mean([same_share(x, y, True) for x, y in zip(a_, b_)])))
    am['frames_max'] = float(max(len(fs) for dirs in art.frames.values() for fs in dirs.values()))
    am['dup_frames'] = float(np.mean([a['frames'] - a['distinct_frames'] for a in anim.values()]))
    am['dirs_identical_share'] = float(np.mean(same)) if same else -1.0
    am['dirs_same_shifted'] = float(np.mean(shsame)) if shsame else -1.0
    summary.update(am)
    out = dict(name=art.name, kind=art.kind, summary=summary,
               dirs={d: {k: float(np.mean([m[k] for m in v if k in m])) for k in STAT} for d, v in bydir.items()},
               anim={f'{g}/{d}': a for (g, d), a in anim.items()},
               families=merge_families(fam_all))
    if per_frame:
        out['frames'] = frames_out
    return out


# ---------------------------------------------------------------------------------------------------------------- the bar

def load_bar(path=BAR):
    with open(path) as f:
        return json.load(f)


def effective(entry, summary):
    """the min / max of a bar entry for this art: the min scaled by the solid pixels against the entry's reference pixels when
    it has `scale` (sqrt or linear), a bigger sprite never asked for more than `scale_cap` times the min, never below `floor`."""
    lo, hi = entry.get('min'), entry.get('max')
    sc = entry.get('scale')
    if sc:
        ref = float(entry.get('ref_px') or 1)
        k = (max(1.0, summary['solid_px']) / ref)
        f = math.sqrt(k) if sc == 'sqrt' else k
        f = min(f, float(entry.get('scale_cap', 1.0)))   # a bigger sprite is never asked for more than the reference
        if lo is not None:
            lo = lo * f
        if hi is not None:
            hi = hi * (f if entry.get('scale_max') else 1.0)
    if lo is not None and 'floor' in entry:
        lo = max(lo, entry['floor'])
    return lo, hi


def check(result, kind, bar):
    """-> list of rows (metric, value, lo, hi, ok, level, why)."""
    spec = bar['kinds'][kind]
    s = result['summary']
    rows = []
    for name, e in spec['metrics'].items():
        if name not in s:
            continue
        v = s[name]
        if s.get('frames_max', 1) < e.get('needs_frames', 0):
            continue
        lo, hi = effective(e, s)
        ok = (lo is None or v >= lo) and (hi is None or v <= hi)
        rows.append(dict(metric=name, value=v, lo=lo, hi=hi, ok=bool(ok), level=e.get('level', 'fail'), why=e.get('why', '')))
    return rows


def passed(rows, strict=False):
    return all(r['ok'] or (r['level'] == 'warn' and not strict) for r in rows)


# ---------------------------------------------------------------------------------------------------------------- cli

def _fmt(v):
    if isinstance(v, str):
        return v
    if abs(v) >= 1000 or float(v).is_integer():
        return f'{v:.0f}'
    return f'{v:.3f}' if abs(v) < 10 else f'{v:.2f}'


def print_measure(res, frames=False, out=None):
    out = out or sys.stdout
    s = res['summary']
    w = out.write
    w(f"== {res['name']} (kind {res['kind']}) ==\n")
    sections = [
        ('canvas', ['solid_px', 'bbox_w', 'bbox_h', 'fill_share', 'canvas_share', 'complexity', 'holes', 'hole_px']),
        ('alpha', ['alpha_levels', 'alpha_255_share', 'semi_share', 'semi_edge_share', 'semi_inside_px']),
        ('palette', ['colours', 'colours_1pct', 'families', 'ramp_steps', 'ramp_steps_max', 'ramp_hue_shift', 'ramp_warm_cool',
                     'sat_mean', 'sat_std', 'val_std', 'luma_p5', 'luma_p50', 'luma_p95', 'contrast', 'near_black_share',
                     'near_white_share', 'grey_share']),
        ('shading', ['light_name', 'light_x', 'light_y', 'light_r2', 'light_frames_agree', 'lumgrad_r2', 'pillow_r', 'pillow',
                     'flat_run_share', 'spec_clusters', 'spec_mean_size', 'spec_share']),
        ('outline', ['rim_px', 'outline_coverage', 'outline_black_share', 'outline_hue_share', 'outline_thick',
                     'outline_selout_share']),
        ('texture', ['local_std', 'lone_px_share', 'lone_px_share_q', 'tiny_px_share', 'cluster_px_mean', 'clusters_per_100px',
                     'checker_share', 'detail_mean', 'detail_p10', 'flat_tile_share', 'tile_colours_mean']),
        ('animation', ['frames', 'distinct_frames', 'ms_mean', 'loop_ms', 'changed_px', 'changed_share', 'regions',
                       'largest_region_share', 'motion_px', 'motion_max', 'shade_only_share', 'silhouette_change_share',
                       'area_range', 'bbox_w_range', 'bbox_h_range', 'ratio_range', 'centroid_x_range', 'centroid_y_range',
                       'loop_ratio', 'loop_exact', 'ew_mirror_share', 'dirs_identical_share', 'dirs_same_shifted', 'dup_frames'])]
    for title, keys in sections:
        w(f'  {title}\n')
        for k in keys:
            if k in s:
                w(f'    {k:26s} {_fmt(s[k])}\n')
    for f in res['families'][:4]:
        w(f"  family hue {f['hue']:.0f} px {f['px']} steps {f['steps']} colours {f['colours']} shift {f['shift']:+.0f} "
          f"warm/cool {f['warm_cool']:+.2f} luma {f['luma_lo']:.0f}-{f['luma_hi']:.0f}\n")
    if frames:
        for fr in res.get('frames', []):
            w(f"  frame {fr['group']}/{fr['dir']}/{fr['frame']}: solid {fr['solid_px']} bbox {fr.get('bbox_w', 0)}x{fr.get('bbox_h', 0)} "
              f"colours {fr.get('colours', 0)} light_r2 {fr.get('light_r2', 0):.2f}\n")


def _short(why):
    one = why.split('. ')[0].rstrip('.')
    return one if len(one) <= 100 else one[:97] + '...'


def print_check(res, rows, kind, out=None):
    out = out or sys.stdout
    ok = passed(rows)
    out.write(f"{'PASS' if ok else 'FAIL'}  {res['name']}  (kind {kind}, solid px {res['summary']['solid_px']:.0f})\n")
    for r in rows:
        if r['ok']:
            continue
        lo = '' if r['lo'] is None else f">= {_fmt(r['lo'])}"
        hi = '' if r['hi'] is None else f"<= {_fmt(r['hi'])}"
        out.write(f"  {'warn' if r['level'] == 'warn' else 'FAIL'}  {r['metric']:24s} {_fmt(r['value']):>9s}  needs {lo}{hi}  {_short(r['why'])}\n")


def gather(args):
    arts = []
    for p in args.files:
        arts.append(load_image(p, args.kind or 'creature', args.cell, args.ms))
    if args.dat or args.spr or args.outfit or args.item or args.effect:
        if not (args.dat and args.spr):
            raise SystemExit('--dat and --spr go together')
        for cat, ids in (('outfit', args.outfit), ('item', args.item), ('effect', args.effect)):
            for i in ids or []:
                a = load_pair(args.dat, args.spr, i, cat)
                a.kind = args.kind or a.kind
                arts.append(a)
    for p in args.npz or []:
        a = load_npz(p)
        a.kind = args.kind or a.kind
        arts.append(a)
    if not arts:
        raise SystemExit('nothing to read: give IMAGE files, --dat/--spr/--outfit or --npz')
    return arts


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    for name in ('measure', 'check'):
        p = sub.add_parser(name)
        p.add_argument('files', nargs='*')
        p.add_argument('--kind', choices=['boss', 'creature', 'outfit', 'item', 'effect'], required=(name == 'check'))
        p.add_argument('--cell', type=int)
        p.add_argument('--ms', type=int, help='frame duration of PNG input')
        p.add_argument('--dat')
        p.add_argument('--spr')
        p.add_argument('--outfit', type=int, action='append')
        p.add_argument('--item', type=int, action='append')
        p.add_argument('--effect', type=int, action='append')
        p.add_argument('--npz', action='append')
        p.add_argument('--bar', default=BAR)
        p.add_argument('--json', action='store_true')
        p.add_argument('--frames', action='store_true')
        p.add_argument('--strict', action='store_true', help='warnings fail too')
    args = ap.parse_args(argv)
    arts = gather(args)
    bar = load_bar(args.bar) if args.cmd == 'check' else None
    rc = 0
    outj = []
    for a in arts:
        kind = args.kind or a.kind
        solid = bar['kinds'][kind].get('solid', SOLID) if bar else (40 if kind == 'effect' else SOLID)
        res = analyse(a, solid, per_frame=args.frames)
        if args.cmd == 'measure':
            if args.json:
                outj.append(res)
            else:
                print_measure(res, args.frames)
        else:
            rows = check(res, kind, bar)
            ok = passed(rows, args.strict)
            rc |= 0 if ok else 1
            if args.json:
                outj.append(dict(name=res['name'], kind=kind, ok=ok, rows=rows))
            else:
                print_check(res, rows, kind)
    if args.json:
        json.dump(outj, sys.stdout, indent=1, default=float)
        sys.stdout.write('\n')
    return rc


if __name__ == '__main__':
    sys.exit(main())
