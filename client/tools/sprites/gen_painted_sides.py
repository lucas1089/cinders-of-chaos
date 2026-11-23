#!/usr/bin/env python3
"""Side views of the ten painted wings from PixelLab (O724, owner 2026-11-23).

usage: python3 -I client/tools/sprites/gen_painted_sides.py build [--check]
       python3 -I client/tools/sprites/gen_painted_sides.py preview DAT SPR OUT.mp4

The ten painted rows of drawn_wings/designs.csv (pixellab_rows.csv: 58 foam crest, 93 rain veil, 96 rose window,
104 slate plate, 109 squall kite, 110 star gossamer, 111 storm gull, 116 tide swan, 117 tornado funnel, 118 void
raven) keep the north and south pictures the input pair has (`apply --keep-painted`). Their east and west views
were clumpy. This script draws new side views from one wing a row that PixelLab painted from words only (the row's
name, family and colours; the row's colours as a forced palette). No picture of a pair or of a pack went to PixelLab.

drawn_wings/painted_sides/raw/<wings>.png   the PixelLab wing, 96 x 96, as it came back (our own art)
drawn_wings/painted_sides/sides.csv         a row a wing: face-on reach in the pair, aim, flap, the words sent
drawn_wings/painted_sides/<wings>.png       the east strip: 16 frames of 96 x 96 side by side (west is it mirrored)
drawn_wings/painted_sides/sides.sums        sha256 of each raw wing and each strip

How a strip is made (the side rules of O714c, gen_drawn_wings.py "the side view"):
  the raw wing: alpha cut at 128, crumbs under MIN_PIECE px dropped; its root is the end of its long axis that lies
  lower, its tip the other end; mirrored so the tip trails left (east faces right);
  the near wing: scaled to SIDE_NEAR (92%) of the face-on reach of the row in the pair (column `reach`, measured
  once on pair 79 by script), root on the shoulder blade SIDE_ROOT (44, 58), turned so the middle of its pixels
  lies `aim` degrees over the horizontal (30 to 40);
  the far wing: the same wing at SIDE_FAR (80%) of the reach, SIDE_FAR_SHADE (0.74) darker, root up and back and
  steeper by the first place of SIDE_FARS that leaves a quarter of it in sight over the near one;
  the flap: both wings turn about their roots by `flap` degrees times sin(phase), 16 frames, frame 15 runs into 0;
  nothing more than SIDE_FRONT px in front of the back line; whole pixels (alpha 0 or 255); every solid pixel
  that touches transparency gets the row's outline colour (docs/SPRITE_STYLE.md "Wings").
`build` writes the strips and the sums; `build --check` rebuilds them in memory and fails on any difference and on
any rule of `problems`. `gen_drawn_wings.py apply --keep-painted` puts these strips in east and west of the ten looks
and keeps their north and south (gen_drawn_wings_families.apply).
`preview` draws the ten looks of a pair on the plain grey figure of gen_drawn_wings.py, four directions, idle flap.
"""
import csv
import hashlib
import io
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_drawn_wings as k  # noqa: E402

S = k.SIZE
F = k.FRAMES
DIR = os.path.join(HERE, 'drawn_wings', 'painted_sides')
CSV = os.path.join(DIR, 'sides.csv')
SUMS = os.path.join(DIR, 'sides.sums')
MIN_PIECE = 6
FAR_FLAP = 1.25              # the far wing beats a little wider: it is further from the eye
FIELDS = ('wings', 'key', 'reach', 'aim', 'flap', 'seed', 'words')


def rows(path=CSV):
    with open(path, newline='', encoding='utf-8') as f:
        return {int(r['wings']): r for r in csv.DictReader(f)}


def wings_ids():
    return sorted(rows())


def spec(wings):
    import gen_drawn_wings_families as fam
    for sp in fam.load():
        if sp.wings == wings:
            return sp
    raise SystemExit('row %d is not in designs.csv' % wings)


# ------------------------------------------------------------------------------------------------ the raw wing
def pieces(mask):
    """sizes and labels of the 8-connected pieces of a mask"""
    lab = np.zeros(mask.shape, np.int32)
    sizes = [0]
    h, w = mask.shape
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0]:
            continue
        n = len(sizes)
        lab[y0, x0] = n
        stack, size = [(y0, x0)], 0
        while stack:
            y, x = stack.pop()
            size += 1
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = n
                        stack.append((yy, xx))
        sizes.append(size)
    return lab, sizes


def raw_wing(wings):
    """(RGBA, root (x, y)) of the raw wing, cleaned and mirrored so the tip lies left of the root"""
    img = np.asarray(Image.open(os.path.join(DIR, 'raw', '%d.png' % wings)).convert('RGBA')).copy()
    solid = img[..., 3] >= 128
    lab, sizes = pieces(solid)
    keep = np.isin(lab, [i for i, n in enumerate(sizes) if i and n >= MIN_PIECE])
    img[~keep] = 0
    img[keep, 3] = 255
    ys, xs = np.nonzero(keep)
    pts = np.stack([xs + 0.5, ys + 0.5], axis=1)
    c = pts.mean(axis=0)
    u = np.linalg.svd(pts - c, full_matrices=False)[2][0]
    t = (pts - c) @ u
    lo, hi = pts[t <= np.quantile(t, 0.04)].mean(axis=0), pts[t >= np.quantile(t, 0.96)].mean(axis=0)
    root, tip = (lo, hi) if lo[1] > hi[1] else (hi, lo)
    if tip[0] > root[0]:
        img = img[:, ::-1].copy()
        root = np.array([S - root[0], root[1]])
    # the root on the wing: the solid pixel nearest to the end point
    ys, xs = np.nonzero(img[..., 3] == 255)
    i = int(np.argmin(np.hypot(xs + 0.5 - root[0], ys + 0.5 - root[1])))
    return img, (xs[i] + 0.5, ys[i] + 0.5)


def place(src, sroot, scale, angle, root):
    """the wing turned by `angle` degrees (counter-clockwise on screen) and scaled about its root, root on `root`;
    nearest pixel, so it stays whole pixels and its own colours"""
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    dx, dy = k.PX - root[0], k.PY - root[1]
    # screen y grows down: a counter-clockwise turn on screen is (x, y) -> (x ca + y sa, -x sa + y ca)
    sx = (dx * ca - dy * sa) / scale + sroot[0]
    sy = (dx * sa + dy * ca) / scale + sroot[1]
    ix, iy = np.floor(sx).astype(int), np.floor(sy).astype(int)
    ok = (ix >= 0) & (ix < S) & (iy >= 0) & (iy < S)
    out = np.zeros((S, S, 4), np.uint8)
    out[ok] = src[iy[ok], ix[ok]]
    out[out[..., 3] < 255] = 0
    return out


def reach_of(mask, root):
    ys, xs = np.nonzero(mask)
    return float(np.hypot(xs + 0.5 - root[0], ys + 0.5 - root[1]).max()) if len(xs) else 0.0


def clip(img):
    """nothing more than SIDE_FRONT px in front of the back line, nothing on column 0 or 1 (the west mirror)"""
    out = img.copy()
    lim = k.SIDE_ROOT[0] + k.SIDE_FRONT
    out[:, lim + 1:] = 0
    out[:, :2] = 0
    return out


def outlined(img, colour):
    out = img.copy()
    m = out[..., 3] == 255
    edge = m & ~(k.nb(m, 1, 0) & k.nb(m, -1, 0) & k.nb(m, 0, 1) & k.nb(m, 0, -1))
    out[edge, :3] = colour
    return out


def shaded(img):
    out = img.copy()
    m = out[..., 3] == 255
    out[m, :3] = (out[m, :3].astype(np.float64) * k.SIDE_FAR_SHADE).astype(np.uint8)
    return out


# ------------------------------------------------------------------------------------------------ the strip
def fit(wings, row=None):
    """(aim turn, far choice) of a row: the turn that puts the middle of the near wing on the aim, then the first
    place of SIDE_FARS at which the far wing shows over the near one in every frame"""
    row = row or rows()[wings]
    src, sroot = raw_wing(wings)
    base = reach_of(src[..., 3] == 255, sroot)
    reach = float(row['reach'])
    aim = float(row['aim'])
    near_scale = k.SIDE_NEAR * reach / base
    # a turn of t degrees (counter-clockwise on screen) lowers the sweep angle of side_tip by t
    turn = k.side_tip(src[..., 3] == 255, sroot)[1] - aim
    for _ in range(8):
        m = clip(place(src, sroot, near_scale, turn, k.SIDE_ROOT))[..., 3] == 255
        err = aim - k.side_tip(m)[1]
        if abs(err) < 0.3:
            break
        turn -= err
    return src, sroot, base, turn


def frames(wings, row=None, sp=None):
    """[16 RGBA east frames], [(near, far) masks] of a row"""
    row = row or rows()[wings]
    sp = sp or spec(wings)
    src, sroot, base, turn = fit(wings, row)
    reach = float(row['reach'])
    flap = float(row['flap'])
    ns, fs = k.SIDE_NEAR * reach / base, k.SIDE_FAR * reach / base
    choice = None
    for far_turn, at in k.SIDE_FARS:
        ok = True
        for f in range(F):
            b = flap * math.sin(2 * math.pi * f / F)
            near = clip(place(src, sroot, ns, turn + b, k.SIDE_ROOT))[..., 3] == 255
            far = clip(place(src, sroot, fs, turn - far_turn + FAR_FLAP * b,
                             (k.SIDE_ROOT[0] + at[0], k.SIDE_ROOT[1] + at[1])))[..., 3] == 255
            fy, ny = np.nonzero(far)[0], np.nonzero(near)[0]
            if (not len(fy) or (far & ~near).sum() < (k.SIDE_FAR_FREE + 0.05) * far.sum()
                    or fy.mean() >= ny.mean() - 1 or fy.min() > ny.min() or k.side_cut(far) or k.side_cut(near)):
                ok = False
                break
        if ok:
            choice = (far_turn, at)
            break
    if choice is None:
        choice = k.SIDE_FARS[-1]
    far_turn, at = choice
    out, masks = [], []
    for f in range(F):
        b = flap * math.sin(2 * math.pi * f / F)
        near = outlined(clip(place(src, sroot, ns, turn + b, k.SIDE_ROOT)), sp.outline)
        far = outlined(shaded(clip(place(src, sroot, fs, turn - far_turn + FAR_FLAP * b,
                                         (k.SIDE_ROOT[0] + at[0], k.SIDE_ROOT[1] + at[1])))), sp.outline)
        img = far.copy()
        nm = near[..., 3] == 255
        img[nm] = near[nm]
        img = outlined(img, sp.outline)
        out.append(img)
        masks.append((nm, (far[..., 3] == 255)))
    return out, masks


def strip_png(imgs):
    buf = io.BytesIO()
    Image.fromarray(np.concatenate(imgs, axis=1), 'RGBA').save(buf, 'PNG', optimize=False, compress_level=9)
    return buf.getvalue()


def read_strip(wings, folder=DIR):
    """[16 RGBA east frames] of the committed strip"""
    a = np.asarray(Image.open(os.path.join(folder, '%d.png' % wings)).convert('RGBA'))
    if a.shape != (S, F * S, 4):
        raise SystemExit('%d.png: a strip is %d x %d' % (wings, F * S, S))
    return [np.ascontiguousarray(a[:, f * S:(f + 1) * S]) for f in range(F)]


def problems(wings, imgs, masks=None, row=None, outline=None):
    """the side rules of O714c on every frame of a strip (masks: (near, far) a frame, when known)"""
    row = row or rows()[wings]
    outline = outline or spec(wings).outline
    bad = []
    reach = float(row['reach'])
    seen = set()
    for f, img in enumerate(imgs):
        a = img[..., 3]
        if not set(np.unique(a).tolist()) <= {0, k.GLOW_ALPHA, 255}:
            bad.append('%d frame %d: alpha other than 0, %d, 255' % (wings, f, k.GLOW_ALPHA))
        m = a == 255
        if not m.any():
            bad.append('%d frame %d: empty' % (wings, f))
            continue
        if int(np.nonzero(a.any(axis=0))[0].max()) > k.SIDE_ROOT[0] + k.SIDE_FRONT or a[:, :2].any():
            bad.append('%d frame %d: art in front of the back line or on the mirror column' % (wings, f))
        if k.side_cut(m) > k.SIDE_CUT_MAX:
            bad.append('%d frame %d: over the head the wing reaches the back line' % (wings, f))
        edge = m & ~(k.nb(m, 1, 0) & k.nb(m, -1, 0) & k.nb(m, 0, 1) & k.nb(m, 0, -1))
        if (edge & ~(img[..., :3] == np.asarray(outline, np.uint8)).all(axis=2)).any():
            bad.append('%d frame %d: an open edge is not the outline colour' % (wings, f))
        if float((np.nonzero(m)[0] >= k.ANCHOR[1]).mean()) > k.SIDE_HANG:
            bad.append('%d frame %d: more than %d%% under the anchor row' % (wings, f, 100 * k.SIDE_HANG))
        seen.add(img.tobytes())
        if masks is None:
            continue
        near, far = masks[f]
        r, ang, behind = k.side_tip(near)
        if r < k.SIDE_LEN * reach:
            bad.append('%d frame %d: the near wing is short (%.0f of %.0f)' % (wings, f, r, reach))
        if behind <= 0 or not k.SIDE_ANGLE[0] <= ang <= k.SIDE_ANGLE[1]:
            bad.append('%d frame %d: the near wing is not swept back at %d-%d degrees (%.0f)' % ((wings, f) + k.SIDE_ANGLE + (ang,)))
        ys, xs = np.nonzero(near)
        if float(np.hypot(xs + 0.5 - k.SIDE_ROOT[0], ys + 0.5 - k.SIDE_ROOT[1]).min()) > 4.0:
            bad.append('%d frame %d: the near wing has no root on the shoulder blade' % (wings, f))
        nf = int(far.sum())
        if nf == 0 or (far & ~near).sum() < k.SIDE_FAR_FREE * nf:
            bad.append('%d frame %d: the far wing is hidden under the near one' % (wings, f))
        else:
            fy = np.nonzero(far)[0]
            if fy.mean() >= ys.mean() or fy.min() > ys.min():
                bad.append('%d frame %d: the far wing does not stand over the near one' % (wings, f))
            own = far & ~near & m
            ncols = set(map(tuple, img[near & m][:, :3].tolist())) - {tuple(outline)}
            same = sum(1 for c in img[own][:, :3].tolist() if tuple(c) in ncols)
            if same >= 0.5 * max(1, int(own.sum())):
                bad.append('%d frame %d: the far wing is not a step darker' % (wings, f))
    if len(seen) < F // 2:
        bad.append('%d: the strip hardly moves (%d different frames)' % (wings, len(seen)))
    return bad


def sha(data):
    return hashlib.sha256(data).hexdigest()


def sums_text():
    lines = []
    for w in wings_ids():
        with open(os.path.join(DIR, 'raw', '%d.png' % w), 'rb') as f:
            lines.append('raw/%d.png %s\n' % (w, sha(f.read())))
        with open(os.path.join(DIR, '%d.png' % w), 'rb') as f:
            lines.append('%d.png %s\n' % (w, sha(f.read())))
    return ''.join(lines)


def read_sums(path=SUMS):
    with open(path, encoding='utf-8') as f:
        return dict(line.split() for line in f if line.strip())


def build(check=False, log=print):
    bad = []
    for w, row in sorted(rows().items()):
        sp = spec(w)
        if sp.key != row['key']:
            bad.append('%d: key %s, designs.csv says %s' % (w, row['key'], sp.key))
        imgs, masks = frames(w, row, sp)
        bad += problems(w, imgs, masks, row, sp.outline)
        data = strip_png(imgs)
        path = os.path.join(DIR, '%d.png' % w)
        if check:
            if not os.path.isfile(path) or any(not np.array_equal(a, b) for a, b in zip(read_strip(w), imgs)):
                bad.append('%d.png: not what build draws (run build)' % w)
        else:
            with open(path, 'wb') as f:
                f.write(data)
            log('%d %s' % (w, path))
    if check:
        if read_sums() != dict(line.split() for line in sums_text().splitlines()):
            bad.append('sides.sums is not current (run build)')
    elif not bad:
        with open(SUMS, 'w', encoding='utf-8') as f:
            f.write(sums_text())
    for line in bad:
        log(line)
    log('%d painted side strips%s' % (len(rows()), ': ok' if not bad else ''))
    return bad


# ------------------------------------------------------------------------------------------------ the pair
def side_patterns(base_pats, wings, folder=DIR):
    """the pictures of a painted look with the side strips in east (x 1) and west (x 3), behind the body; north and
    south as the base pair has them"""
    east = read_strip(wings, folder)
    out = dict(base_pats)
    none = np.zeros((S, S, 4), np.uint8)
    for f in range(F):
        out[(0, 1, f)] = east[f]
        out[(1, 1, f)] = none
        out[(0, 3, f)] = k.mirrored(east[f])
        out[(1, 3, f)] = none
    return out


def preview(dat_path, spr_path, out_path, loops=3, scale=3, log=print):
    """the ten looks of a pair on the plain grey figure, four directions a row, idle flap"""
    import gen_drawn_wings_families as fam
    from datspr import Dat, Spr
    dat, spr = Dat(dat_path), Spr(spr_path)
    bodies = {d: k.silhouette(d) for d in k.DIRS}
    lines = []
    for w in wings_ids():
        sp = spec(w)
        pats = fam.pair_patterns(dat, spr, sp.look)
        if isinstance(pats, str):
            raise SystemExit(pats)
        none = np.zeros((S, S, 4), np.uint8)
        fr = {d: {f: ((pats[(0, x, f)], pats[(1, x, f)]) if d == 'north' else (pats[(0, x, f)], none))
                  for f in range(F)} for x, d in enumerate(k.DIRS)}
        lines.append((sp, fr))
    images = []
    for i in range(F * loops):
        f = i % F
        rowsimg = []
        for sp, fr in lines:
            cells = [k.compose(fr, bodies, d, f) for d in ('south', 'east', 'north', 'west')]
            rowsimg.append(np.concatenate(cells, axis=1))
        half = (len(rowsimg) + 1) // 2
        cols = [np.concatenate(rowsimg[:half], axis=0), np.concatenate(rowsimg[half:] + [np.zeros_like(rowsimg[0])] * (2 * half - len(rowsimg)), axis=0)]
        sheet = k.upscale(np.concatenate([cols[0], np.full((cols[0].shape[0], 8, 3), 20, np.uint8), cols[1]], axis=1), scale)
        images.append(sheet[:sheet.shape[0] // 2 * 2, :sheet.shape[1] // 2 * 2])
    k.write_mp4(out_path, images)
    log(out_path)
    return out_path


def main(argv=None):
    argv = sys.argv[1:] if argv is None else list(argv)
    if argv[:1] == ['build']:
        return 1 if build(check='--check' in argv) else 0
    if argv[:1] == ['preview'] and len(argv) == 4:
        preview(argv[1], argv[2], argv[3])
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
