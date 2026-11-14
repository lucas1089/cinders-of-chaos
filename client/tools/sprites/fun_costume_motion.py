#!/usr/bin/env python3
"""Pixel motion for the fun costumes (O578; client/MANIFEST.md "Pair 72"): clean frames out of a few good pictures.

PixelLab draws the standing picture of a costume well in all four directions but its own animation of an object is nearly still and
drifts in colour from frame to frame. So the objects hop here by script: the standing picture is squashed, stretched, lifted and
leaned by whole pixels (nearest rows and columns, the first and the last row kept so the outline never goes), every frame in the
colours of the standing picture. A figure keeps the limbs PixelLab moved; `lock_palette` pulls its frames back to the colours of the
standing pictures. No third-party code, numpy and Pillow only.

    hop_cycle(a, n=12)          # n phases of two hops with a waddle (n a multiple of 6)
    breath_cycle(a, n=4)        # n phases of a slow stretch
    lock_palette(frames, refs)  # every pixel the nearest colour of the reference pictures, hard alpha
"""
import math

import numpy as np


def bbox(a):
    ys, xs = np.nonzero(a[..., 3] > 0)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def _pin(n_src, n_dst):
    """source index of each destination index, the first and the last kept"""
    if n_dst <= 1:
        return np.zeros(max(n_dst, 0), int)
    return np.round(np.arange(n_dst) * (n_src - 1) / float(n_dst - 1)).astype(int)


def morph(a, sx=1.0, sy=1.0, lift=0, lean=0.0, canvas=None):
    """the opaque box of picture `a` scaled to sx x sy (whole rows and columns), its bottom `lift` pixels above the original bottom
    row, the top leaning `lean` pixels sideways (rows shift in proportion to their height above the base), on a canvas of the same
    size as `a`; the box keeps its bottom-middle where it was"""
    h, w = a.shape[:2]
    x0, y0, x1, y1 = bbox(a)
    crop = a[y0:y1 + 1, x0:x1 + 1]
    ch, cw = crop.shape[:2]
    nh, nw = max(2, int(round(ch * sy))), max(2, int(round(cw * sx)))
    crop = crop[_pin(ch, nh)][:, _pin(cw, nw)]
    out = np.zeros_like(a) if canvas is None else canvas
    cx = (x0 + x1) / 2.0
    left = int(math.floor(cx - (nw - 1) / 2.0 + 0.5))
    bottom = y1 - int(lift)
    for i in range(nh):
        y = bottom - (nh - 1) + i
        if not 0 <= y < h:
            continue
        up = (nh - 1 - i) / float(max(1, nh - 1))
        dx = int(round(lean * up))
        xa = left + dx
        s0, s1 = max(0, -xa), min(nw, w - xa)
        if s1 > s0:
            out[y, xa + s0:xa + s1] = crop[i, s0:s1]
    return out


# one hop of 6 phases: (sx, sy, lift, lean of the first hop): land, push, rise, top, fall, brace
HOP6 = ((1.10, 0.86, 0, 0.0), (0.95, 1.10, 2, 0.5), (0.96, 1.06, 4, 1.0), (1.00, 1.00, 5, 1.0), (0.96, 1.06, 3, 0.5), (1.02, 0.96, 1, 0.0))


def hop_cycle(a, n=12, scale=1.0):
    """n phases (a multiple of 6) of hops, one per 6 phases, leaning to one side then the other (a waddle); `scale` the size of the motion"""
    out = []
    for i in range(n):
        hop, k = divmod(i, 6)
        sx, sy, lift, lean = HOP6[k]
        side = 1 if hop % 2 == 0 else -1
        sx = 1.0 + (sx - 1.0) * scale
        sy = 1.0 + (sy - 1.0) * scale
        out.append(morph(a, sx, sy, int(round(lift * scale)), lean * side * scale))
    return out


def breath_cycle(a, n=4):
    """n phases of a breath: the picture one row taller for the middle phases"""
    h = bbox(a)[3] - bbox(a)[1] + 1
    out = []
    for i in range(n):
        up = 0.5 - 0.5 * math.cos(2 * math.pi * i / n)
        out.append(morph(a, 1.0, (h + round(up * 1.4)) / float(h)))
    return out


def palette_of(refs, min_count=2):
    """the colours (rgb rows) of the reference pictures that are at least `min_count` pixels"""
    cols = {}
    for a in refs:
        px = a[a[..., 3] >= 128][:, :3]
        for c in map(tuple, px):
            cols[c] = cols.get(c, 0) + 1
    keep = [c for c, n in cols.items() if n >= min_count] or list(cols)
    return np.array(sorted(keep), np.int32)


def lock_palette(frames, refs, min_count=2):
    """hard alpha, and every pixel the nearest colour of the reference pictures"""
    pal = palette_of(refs, min_count)
    out = []
    for a in frames:
        b = a.copy()
        op = b[..., 3] >= 128
        px = b[op][:, :3].astype(np.int32)
        if len(px):
            d = ((px[:, None, :] - pal[None, :, :]) ** 2).sum(axis=2)
            b[op, :3] = pal[d.argmin(axis=1)].astype(np.uint8)
        b[..., 3] = np.where(op, 255, 0)
        b[~op] = 0
        out.append(b)
    return out


# ---------------------------------------------------------------- PixelLab downloads -> the layout gen_fun_costumes.py reads

DIRS = ('north', 'east', 'south', 'west')


def _load(path):
    from PIL import Image
    return np.array(Image.open(path).convert('RGBA'))


def _save(a, path):
    import os
    from PIL import Image
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(a).save(path)


def find_state(dl):
    """the folder of an unzipped PixelLab character or object that holds rotations/ (the state, e.g. DL/Idle)"""
    import os
    for root, dirs, _ in os.walk(dl):
        if 'rotations' in dirs:
            return root
    raise SystemExit('%s: no rotations folder' % dl)


def fit_height(a, h):
    """the picture with its opaque box h rows tall (rows dropped or doubled, evenly), the width and the feet kept"""
    cur = bbox(a)[3] - bbox(a)[1] + 1
    return a if cur == h else morph(a, 1.0, h / float(cur))


def prepare(dl, out, mode, anim=None, phases=12, scale=1.0, idle_phases=4, match=0):
    """DL (an unzipped PixelLab download) -> OUT/rot/DIR.png, OUT/idle/DIR/frame_NNN.png, OUT/walk/DIR/frame_NNN.png.
    mode 'hop': the walk is hop_cycle of the standing picture; mode 'walk': the walk is PixelLab's animation `anim`, its colours pulled
    back to the standing pictures. The idle is breath_cycle of the standing picture in both."""
    import os
    st = find_state(dl)
    refs = {d: _load(os.path.join(st, 'rotations', d + '.png')) for d in DIRS}
    if match:
        hs = {d: bbox(refs[d])[3] - bbox(refs[d])[1] + 1 for d in DIRS}
        for d in DIRS:
            if d != 'south' and abs(hs[d] - hs['south']) >= match:
                refs[d] = fit_height(refs[d], hs['south'])
    allrefs = list(refs.values())
    for d in DIRS:
        _save(lock_palette([refs[d]], allrefs, 1)[0], os.path.join(out, 'rot', d + '.png'))
        idle = lock_palette(breath_cycle(refs[d], idle_phases), allrefs, 1)
        for i, f in enumerate(idle):
            _save(f, os.path.join(out, 'idle', d, 'frame_%03d.png' % i))
        if mode == 'hop':
            fr = lock_palette(hop_cycle(refs[d], phases, scale), allrefs, 1)
        else:
            ad = os.path.join(st, 'animations', anim, d)
            names = sorted(n for n in os.listdir(ad) if n.endswith('.png'))
            fr = lock_palette([_load(os.path.join(ad, n)) for n in names], allrefs, 1)
        for i, f in enumerate(fr):
            _save(f, os.path.join(out, 'walk', d, 'frame_%03d.png' % i))
    return len(fr)


if __name__ == '__main__':
    import sys
    a = sys.argv[1:]
    if len(a) >= 4 and a[0] == 'prepare':
        kw = {}
        for x in a[4:]:
            k, v = x.split('=')
            kw[k] = v if k == 'anim' else float(v) if k == 'scale' else int(v)
        print(prepare(a[1], a[2], a[3], **kw))
    else:
        raise SystemExit('usage: fun_costume_motion.py prepare DL_DIR OUT_DIR hop|walk [anim=NAME] [phases=N] [scale=S] [idle_phases=N] [match=MINDIFF]')
