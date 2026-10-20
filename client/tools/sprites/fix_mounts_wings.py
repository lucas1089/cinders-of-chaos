#!/usr/bin/env python3
"""Mounted frames for player looks without them, and wings placement, in COPIES of our 10.98 pair.

python3 -I fix_mounts_wings.py scan --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr [--looks IDS] [--wings IDS]
        (writes nothing) the stock rider measurements below; for each look of --looks its pattern Z and, without a
        mounted pattern, the planned frame shift and trim per direction; for each wings look of --wings its across and
        root errors per direction and, when it is off, the displacement that centres it and the errors with it.
python3 -I fix_mounts_wings.py build --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir OUT \
        [--spec pair_fixes/mounts_wings.csv] [--expect-dat-md5 MD5] [--changes-out CSV]
python3 -I fix_mounts_wings.py sheet --dat P/Tibia.dat --spr P/Tibia.spr --out PNG --riders IDS [--mounts IDS]
        [--wings IDS] [--phase N] [--group G]
        a contact sheet drawn by the client's rule (`Outfit::draw`, below): one row per rider (then one per wings look on
        the first rider), standing and on each mount, four directions, on a tile grid (the creature's tile outlined).

Why. `Outfit::draw` draws the mount only when the rider's look has a mounted pattern: zPattern = min(1, patternZ - 1)
and the mount is drawn only for zPattern > 0. A player look with pattern Z 1 never shows its mount, on the map or in
a preview. Wings are drawn at the creature's place by the wings look's own displacement, the body 6 px up-left of
them (GameWingOffset); a wings look whose art sits off the body needs another displacement, or its frames moved.

Spec (pair_fixes/mounts_wings.csv: kind, id, disp_old, disp, shift, reason), one row per look:
  mounted   (disp_old, disp, shift empty) give the look a mounted pattern built from its standing frames.
  wings     disp_old "X,Y" the displacement the row was measured on, disp "X,Y" the new one (signed; it must differ:
            the new value marks the row applied), shift "north=DX DY;south=..." frames of these directions moved DX, DY
            px (every group, phase and pattern; empty: none).

Mounted frames. Measured on the stock riders of the pair (outfits 128-999, 2x2, displacement 8,8, two colour layers,
four directions, pattern Z 2, an idle group of 1 phase and a walk group of 8: 90 looks in pair 30), per direction, the
medians of:
  - head delta: where the mounted frame's head (its top row with 3 or more art pixels; the mean x of the 8 rows from
    there) lands on screen against the standing frame's. A stock mount has no displacement, so the client draws the
    rider's mounted frame with no displacement (its own cancels out) and its standing frame by its own;
  - trim: the standing figure's height minus the mounted one's (the legs fold onto the mount);
  - bob: the head of each walk phase's mounted frame against the idle mounted frame (the rider moves with the mount's
    stride; its legs do not walk).
The stock mounted pose is art of its own (a pixel match of the torso fails), so the mounted frame of a look is built
from its own standing frame the way the stock frames relate to the standing ones in place and size: per direction the
standing idle frame (every layer, addon pattern and idle phase; the walk group uses idle phase 0, a look with only a
walk group its phase 0, which is its idle pose) moves by the head delta (+ the bob of the walk phase), and its lowest
`trim` rows (scaled by its height against the stock height) are cut. Every layer and addon pattern moves and is cut
alike, so masks and addons stay registered. The frame offset follows the client: a rider with a displacement of 0 or
more is drawn on a stock mount with none, a rider with a negative displacement by its own, so a frame pixel moves by
the screen shift + (standing offset - mounted offset). A frame is anchored at its bottom-right tile, so it grows up or
left by a tile when the mounted art needs it (the standing frames stay where they are: their sprites keep their slots,
the new tiles are empty there); it cannot grow right or down, so a shift that would push art out there is held back by
the missing room (reported). The z = 0 sprites stay; the new z = 1 sprites are appended (identical records once).
Premise: an outfit whose frame groups all have pattern Z 1 (pattern Z 2 already: a no-op), without Bones, its groups of
one size and direction count.
The feet anchor (lowest row with 3 or more art pixels, the mean x of the 4 rows above it) against the stock one is
reported by scan; it is not applied (the looks already stand right: things_custom21; a cape or weapon moves it).
Riders on the five donor mounts with a negative displacement are drawn by their own displacement plus the mount's
seat (client base patch 0034, seats set for stock 8,8 riders), so a rider whose displacement is not 8,8 sits that much
off there, standing or mounted alike.

Wings. The client draws a wings frame pixel at (x - dx - (w-1)*32, y - dy - (h-1)*32) from the tile's top left; the
body 6 px up-left of that place. Measured per direction against the body (the mean of the stock riders 128-131 and
136-139 as drawn with wings), px, + = right / down, every phase of the first group:
  - across: the mean of the art on the axis across the body (x facing north / south, y facing east / west; the
    stock wings are art mirrored about the diagonal, centred on that axis);
  - root: the mean on the other axis of the art within ROOT_BAND px of the across line, where the wings meet: their
    attachment. For a fan of feathers around the body (the owner art 2225-2230 facing west) this lands on a feather
    tip, so roots are read with the contact sheets, not fixed blindly.
The targets are the medians of the stock wings (STOCK_WINGS: no displacement). A look is off when the mean across
error of an axis (x: north and south; y: east and west) is WING_OFF px or more: the stock wings stay within 3.9. One
displacement moves every direction alike, and the two axes come from different directions, so its least-squares value
is dx = old dx + mean x error, dy = old dy + mean y error (rounded). Per direction differences stay (the art differs
per direction; scan prints them). A frame shift fixes what a displacement cannot: a direction whose across error stays
over WING_DIR, or whose root the displacement pushes off (or that was off: the rows say which). Premise after the row:
no axis off, every direction's across error within WING_DIR, no art leaving a frame at its right or bottom edge.

Idempotent: a mounted look that has pattern Z 2 and a wings look that has its new displacement are left alone, so a
run on its own output gives the same files. Outputs in --out-dir: Tibia.dat, Tibia.spr. Inputs are never modified.
Deterministic. Verification (always run): the output re-parses with the same counts; every thing not in the spec is
byte-identical; a changed look keeps its flags (a wings look but its displacement) and every group field but the size
(grown up / left) and pattern Z (mounted: 2); every standing frame (and every unshifted wings frame) is pixel-identical,
anchored at the bottom right; every built frame decodes to what was built; the old spr records are byte-identical
(3000 sampled) and the new ones decode; then check_pair.py's append-only check with --allow-changed = exactly the
changed looks.
"""
import argparse
import csv
import hashlib
import os
import statistics
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_pair as cp  # noqa: E402
from fix_pair_warnings import flag_chunks, groups_bytes  # noqa: E402
from import_art_things import encode_sprite  # noqa: E402

SPEC = os.path.join(HERE, 'pair_fixes', 'mounts_wings.csv')
DIRS = ('north', 'east', 'south', 'west')       # pattern x order
STOCK_RANGE = (128, 999)     # the stock riders are looked for in these outfit ids
STOCK_MIN = 10               # at least this many stock riders (else the input is not a pair with the stock outfits)
STOCK_WINGS = (937, 938, 939, 940, 941, 1177, 1178, 1179, 1180, 1181, 1182, 1183, 1184)
BODY_LOOKS = (128, 129, 130, 131, 136, 137, 138, 139)   # stock citizen / hunter / mage / knight, both sexes
WING_LIFT = 6        # GameWingOffset: the body is drawn 6 px up-left of the wings
WING_OFF = 4         # wings: off when the mean across error of an axis is this or more (stock wings: up to 3.9)
WING_DIR = 6         # wings: after the fix every direction's across error within this (the art differs per direction)
ROOT_BAND = 3        # wings: the root is measured on the art within this of the across line
ROW_MIN = 3          # an art row counts from this many pixels
DISP = 25            # dat byte of the displacement


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def med(v):
    return statistics.median(v)


# ------------------------------------------------------------------------------------------------------ sprites
class Sprites:
    """decoded RGBA tiles of an spr (alpha records)."""

    def __init__(self, path):
        self.f = cp.SprFile(path)
        self.count = self.f.count
        self.cache = {}

    def tile(self, sid):
        if not sid:
            return None
        a = self.cache.get(sid)
        if a is not None:
            return a
        rec = self.f.record(sid)
        if rec is None:
            return None
        img = np.zeros((1024, 4), np.uint8)
        p, px, end = 5, 0, len(rec)
        while p + 4 <= end:
            skip, cnt = struct.unpack_from('<HH', rec, p)
            p += 4
            px += skip
            if cnt:
                img[px:px + cnt] = np.frombuffer(bytes(rec[p:p + 4 * cnt]), np.uint8).reshape(cnt, 4)
            p += 4 * cnt
            px += cnt
        a = img.reshape(32, 32, 4)
        if len(self.cache) < 100000:
            self.cache[sid] = a
        return a

    def record(self, sid):
        return self.f.record(sid)

    def close(self):
        self.f.close()


def frame(g, spr, x=0, y=0, z=0, phase=0, layer=0):
    """one layer of one frame as the client composes it: (h*32, w*32, 4), anchored at the bottom-right tile."""
    a = np.zeros((g.h * 32, g.w * 32, 4), np.uint8)
    for hh in range(g.h):
        for ww in range(g.w):
            s = spr.tile(g.sprites[cp.sprite_index(g, x, y, z, layer, phase, ww, hh)])
            if s is not None:
                Y, X = (g.h - 1 - hh) * 32, (g.w - 1 - ww) * 32
                m = s[:, :, 3] > 0
                a[Y:Y + 32, X:X + 32][m] = s[m]
    return a


def tiles_of(a, g):
    """inverse of frame(): {(ww, hh): 32x32x4 tile}."""
    out = {}
    for hh in range(g.h):
        for ww in range(g.w):
            Y, X = (g.h - 1 - hh) * 32, (g.w - 1 - ww) * 32
            out[(ww, hh)] = a[Y:Y + 32, X:X + 32]
    return out


def shift(a, dx, dy):
    """move the art dx, dy px (whole pixels); returns (moved array, art pixels that left the frame)."""
    h, w = a.shape[:2]
    out = np.zeros_like(a)
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    lost = int((a[:, :, 3] > 0).sum())
    if xs0 < xs1 and ys0 < ys1:
        out[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx] = a[ys0:ys1, xs0:xs1]
    lost -= int((out[:, :, 3] > 0).sum())
    return out, lost


def rows_of(a):
    return np.nonzero((a[:, :, 3] > 0).sum(1) >= ROW_MIN)[0]


def head(a):
    """(top row, mean x of the 8 rows from it), frame px; None when empty."""
    r = rows_of(a)
    if not len(r):
        return None
    ys, xs = np.nonzero(a[r[0]:r[0] + 8, :, 3] > 0)
    return int(r[0]), float(xs.mean())


def feet(a):
    """(mean x of the 4 rows above the feet line, feet line), frame px; None when empty."""
    r = rows_of(a)
    if not len(r):
        return None
    ys, xs = np.nonzero(a[max(0, r[-1] - 3):r[-1] + 1, :, 3] > 0)
    return float(xs.mean()), int(r[-1])


def height(a):
    r = rows_of(a)
    return int(r[-1] - r[0]) if len(r) else None


# -------------------------------------------------------------------------------------------------------- things
def disp(t):
    v = t.flag('displacement')
    return tuple(v) if v else (0, 0)


def negative(d):
    return d[0] < 0 or d[1] < 0


def screen_off(t, g):
    """frame px -> screen px (from the tile's top left) when the client draws t standing: - disp - (size-1)*32."""
    dx, dy = disp(t)
    return -dx - (g.w - 1) * 32, -dy - (g.h - 1) * 32


def mounted_off(t, g):
    """the same on a stock mount (no displacement): a rider with displacement >= 0 is drawn with none (its own cancels
    out in Outfit::draw), a negative one by its own."""
    if negative(disp(t)):
        return screen_off(t, g)
    return -(g.w - 1) * 32, -(g.h - 1) * 32


def idle_group(t):
    for g in t.groups:
        if g.gtype == 0:
            return g
    return None


def is_stock_rider(t):
    if not STOCK_RANGE[0] <= t.id <= STOCK_RANGE[1] or len(t.groups) != 2 or disp(t) != (8, 8):
        return False
    gi, gw = t.groups
    return (gi.gtype, gw.gtype, gi.phases, gw.phases) == (0, 1, 1, 8) and all(
        (g.w, g.h, g.layers, g.px, g.pz) == (2, 2, 2, 4, 2) for g in t.groups)


def measure_stock(outs, spr):
    """per direction: head delta (screen), trim, stock height, feet anchor (screen), bob [(dx, dy)] * 8."""
    acc = [dict(dx=[], dy=[], trim=[], h=[], fx=[], fy=[], bob=[[] for _ in range(8)]) for _ in DIRS]
    n = 0
    for t in outs:
        if not is_stock_rider(t):
            continue
        n += 1
        gi, gw = t.groups
        so, mo = screen_off(t, gi), mounted_off(t, gi)
        for x in range(4):
            s, m = frame(gi, spr, x, 0, 0, 0), frame(gi, spr, x, 0, 1, 0)
            hs, hm, fs = head(s), head(m), feet(s)
            if not (hs and hm and fs):
                continue
            a = acc[x]
            a['dx'].append(hm[1] + mo[0] - hs[1] - so[0])
            a['dy'].append(hm[0] + mo[1] - hs[0] - so[1])
            a['trim'].append(height(s) - height(m))
            a['h'].append(height(s))
            a['fx'].append(fs[0] + so[0])
            a['fy'].append(fs[1] + so[1])
            for p in range(8):
                hw = head(frame(gw, spr, x, 0, 1, p))
                if hw:
                    a['bob'][p].append((hw[1] - hm[1], hw[0] - hm[0]))
    if n < STOCK_MIN:
        raise SystemExit(f'only {n} stock riders found: not a pair with the stock outfits')
    out = []
    for a in acc:
        out.append(dict(delta=(med(a['dx']), med(a['dy'])), trim=med(a['trim']), h=med(a['h']),
                        feet=(med(a['fx']), med(a['fy'])),
                        bob=[(round(med([b[0] for b in a['bob'][p]])), round(med([b[1] for b in a['bob'][p]])))
                             for p in range(8)]))
    return n, out


def plan_mounted(t, spr, stock):
    """per direction: frame shift (dx, dy) of the idle frame (screen shift + mounted - standing offset), the cut row
    (frame px, rows from it are cut; None = none), and the info for the report."""
    if t.flag('bones') is not None:
        raise SystemExit(f'{t.ref}: has Bones (the bone path of Outfit::draw), not handled')
    g0 = idle_group(t) or t.groups[0]
    if any((g.w, g.h, g.px) != (g0.w, g0.h, g0.px) for g in t.groups):
        raise SystemExit(f'{t.ref}: frame groups of different sizes or directions')
    so, mo = screen_off(t, g0), mounted_off(t, g0)
    fs = []
    for x in range(min(4, g0.px)):
        f = feet(frame(g0, spr, x, 0, 0, 0))
        if f is None:
            raise SystemExit(f'{t.ref}: no standing art facing {DIRS[x]}')
        fs.append((stock[x]['feet'][0] - f[0] - so[0], stock[x]['feet'][1] - f[1] - so[1]))
    corr = (round(med([f[0] for f in fs])), round(med([f[1] for f in fs])))     # reported only
    plan = []
    for x in range(g0.px):
        st = stock[x if g0.px >= 4 else 2]
        a = frame(g0, spr, x, 0, 0, 0)
        sx = round(st['delta'][0])
        sy = round(st['delta'][1])
        fdx, fdy = sx + so[0] - mo[0], sy + so[1] - mo[1]
        # the frame cannot grow right (it is anchored there): art that would leave it holds the shift back
        right = max(int(np.nonzero((frame(g0, spr, x, y, 0, ph, layer)[:, :, 3] > 0).any(0))[0].max(initial=-1))
                    for y in range(g0.py) for ph in range(g0.phases) for layer in range(g0.layers))
        room = g0.w * 32 - 1 - right - max(b[0] for b in st['bob'])
        held = max(0, fdx - room)
        fdx -= held
        r = rows_of(a)
        trim = round(st['trim'] * (r[-1] - r[0]) / st['h'])
        cut = int(r[-1]) + fdy - trim + 1 if trim > 0 else None
        plan.append(dict(shift=(fdx, fdy), cut=cut, trim=trim, screen=(sx - held, sy), held=held))
    return corr, plan


def walk_bob(t, g, phase, stock_x):
    """the stock bob of this phase of group g (idle groups: none)."""
    if g.gtype == 0 or g.phases == 1:
        return 0, 0
    if idle_group(t) is not None:
        k = phase * 8 // g.phases
    else:                                   # a look with only a walk group: phase 0 is its idle pose
        if phase == 0:
            return 0, 0
        k = (phase - 1) * 8 // (g.phases - 1)
    return stock_x['bob'][k]


def mounted_frames(t, spr, stock):
    """{(group index, x, y, layer, phase): mounted frame array} built from the standing frames; and the plan."""
    corr, plan = plan_mounted(t, spr, stock)
    gidle = idle_group(t)
    out = {}
    P = 32                                   # built on a frame one tile larger up and left, cropped below
    for gi, g in enumerate(t.groups):
        src = gidle or g
        for x in range(g.px):
            p = plan[x]
            for phase in range(g.phases):
                sph = phase if g is src else 0
                bx, by = walk_bob(t, g, phase, stock[x if g.px >= 4 else 2])
                for y in range(g.py):
                    for layer in range(g.layers):
                        a = np.pad(frame(src, spr, x, y, 0, sph, layer), ((P, P), (P, P), (0, 0)))
                        a, lost = shift(a, p['shift'][0] + bx, p['shift'][1] + by)
                        if p['cut'] is not None:
                            a[max(0, P + p['cut'] + by):] = 0
                        lost += int((a[-P:, :, 3] > 0).sum() + (a[:-P, -P:, 3] > 0).sum())
                        if lost:
                            raise SystemExit(f'{t.ref}: {lost} art pixels leave the frame (group {gi}, '
                                             f'{DIRS[x]}, addon {y}, layer {layer}, phase {phase})')
                        out[(gi, x, y, layer, phase)] = a[:-P, :-P]
    # grow the frame up / left only where the mounted art needs it (the frame is anchored at its bottom-right tile,
    # so the standing frames stay where they are)
    ys = [np.nonzero(a[:, :, 3] > 0) for a in out.values()]
    top = min((int(v[0].min()) for v in ys if len(v[0])), default=P)
    left = min((int(v[1].min()) for v in ys if len(v[1])), default=P)
    gw, gh = int(left < P), int(top < P)
    for k, a in out.items():
        out[k] = a[P - 32 * gh:, P - 32 * gw:]
    return corr, plan, out, (gw, gh)


# ----------------------------------------------------------------------------------------------------------- wings
def art_weights(t, spr, x):
    """(xs, ys, weights) of the art of direction x, frame px: every phase of the first group, a pixel weighted by the
    number of phases it shows in."""
    g = t.groups[0]
    m = np.zeros((g.h * 32, g.w * 32), np.float64)
    for ph in range(g.phases):
        m += frame(g, spr, min(x, g.px - 1), 0, 0, ph)[:, :, 3] > 0
    ys, xs = np.nonzero(m)
    return xs, ys, m[ys, xs]


def body_centre(outs, spr):
    """per direction the mean of the stock riders' art as the client draws it with wings (lift included), screen px."""
    out = []
    for x in range(4):
        cx, cy = [], []
        for look in BODY_LOOKS:
            t = outs[look - 1]
            xs, ys, w = art_weights(t, spr, x)
            so = screen_off(t, t.groups[0])
            cx.append((xs * w).sum() / w.sum() + so[0] - WING_LIFT)
            cy.append((ys * w).sum() / w.sum() + so[1] - WING_LIFT)
        out.append((med(cx), med(cy)))
    return out


def wing_measure(t, spr, body, d=None, shifts=None):
    """per direction (across, root) against the body, px: across = the mean of the art on the axis across the body
    (x facing north / south, y facing east / west), root = the mean on the other axis of the art within ROOT_BAND px
    of that line (where the two wings meet: the attachment). Drawn with displacement d (default its own) and the
    frame shifts {direction index: (dx, dy)}."""
    g = t.groups[0]
    dx, dy = disp(t) if d is None else d
    out = []
    for x in range(4):
        xs, ys, w = art_weights(t, spr, x)
        sx, sy = (shifts or {}).get(x, (0, 0))
        X = xs + sx - dx - (g.w - 1) * 32 - body[x][0]
        Y = ys + sy - dy - (g.h - 1) * 32 - body[x][1]
        ac_v, al_v = (X, Y) if x in (0, 2) else (Y, X)
        ac = (ac_v * w).sum() / w.sum()
        sel = np.abs(ac_v - ac) <= ROOT_BAND
        out.append((ac, (al_v[sel] * w[sel]).sum() / w[sel].sum()))
    return out


def stock_wings(outs, spr, body):
    """targets: per direction the stock wings' median across and root."""
    m = [wing_measure(outs[w - 1], spr, body) for w in STOCK_WINGS]
    return [(med([v[x][0] for v in m]), med([v[x][1] for v in m])) for x in range(4)]


def wing_errors(t, spr, body, target, d=None, shifts=None):
    return [(v[0] - target[x][0], v[1] - target[x][1])
            for x, v in enumerate(wing_measure(t, spr, body, d, shifts))]


def wing_axis_error(err):
    """(x, y) mean across error: north / south across is x, east / west across is y."""
    return (err[0][0] + err[2][0]) / 2, (err[1][0] + err[3][0]) / 2


def wing_off(err):
    """the wings sit off the body: a mean across error of WING_OFF px or more on either axis (the stock wings stay
    within 3.9)."""
    ex, ey = wing_axis_error(err)
    return abs(ex) >= WING_OFF or abs(ey) >= WING_OFF


def wing_bad(err, shifted=()):
    """what does not pass after a fix: directions with an across error over WING_DIR, and 'mean' when an axis is
    still off (wing_off)."""
    bad = [x for x, (ea, er) in enumerate(err) if abs(ea) > WING_DIR]
    if wing_off(err):
        bad.append('mean')
    return bad


def wing_fit(t, spr, body, target):
    """the displacement that centres the wings across the body: x from the north and south across errors, y from the
    east and west ones (a displacement moves every direction alike, and the two axes come from different directions,
    so this is the least-squares value of each); a look that is not off keeps its own."""
    err = wing_errors(t, spr, body, target)
    d = disp(t)
    if not wing_off(err):
        return d
    ex, ey = wing_axis_error(err)
    return int(round(d[0] + ex)), int(round(d[1] + ey))


def parse_shifts(s):
    """'north=1 -2;south=0 4' -> {0: (1, -2), 2: (0, 4)}"""
    out = {}
    for part in (s or '').split(';'):
        part = part.strip()
        if not part:
            continue
        k, _, v = part.partition('=')
        if k not in DIRS:
            raise SystemExit(f'shift {part!r}: unknown direction')
        a, b = (int(n) for n in v.split())
        out[DIRS.index(k)] = (a, b)
    return out


def shifts_text(sh):
    return ';'.join(f'{DIRS[x]}={v[0]} {v[1]}' for x, v in sorted(sh.items()))


def shifted_wings(t, spr, shifts):
    """{(group, x, y, z, layer, phase): frame} of the directions in shifts, moved; and the growth up / left (tiles)."""
    P = 64
    out = {}
    for gi, g in enumerate(t.groups):
        for x, (sx, sy) in shifts.items():
            for y in range(g.py):
                for z in range(g.pz):
                    for layer in range(g.layers):
                        for ph in range(g.phases):
                            a = np.pad(frame(g, spr, x, y, z, ph, layer), ((P, P), (P, P), (0, 0)))
                            a, lost = shift(a, sx, sy)
                            lost += int((a[-P:, :, 3] > 0).sum() + (a[:-P, -P:, 3] > 0).sum())
                            if lost:
                                raise SystemExit(f'{t.ref}: the {DIRS[x]} frames would leave the frame at its '
                                                 f'right / bottom edge ({lost} px): not a frame shift')
                            out[(gi, x, y, z, layer, ph)] = a[:-P, :-P]
    ys = [np.nonzero(a[:, :, 3] > 0) for a in out.values()]
    top = min((int(v[0].min()) for v in ys if len(v[0])), default=P)
    left = min((int(v[1].min()) for v in ys if len(v[1])), default=P)
    gw, gh = -(-max(0, P - left) // 32), -(-max(0, P - top) // 32)
    for k, a in out.items():
        out[k] = a[P - 32 * gh:, P - 32 * gw:]
    return out, (gw, gh)


def wings_entry(t, spr, frames, grow, records, rec_index, base_count):
    """the groups of t with the shifted directions' frames replaced (frame grown up / left by grow tiles)."""
    groups = []
    for gi, g in enumerate(t.groups):
        n = cp.Group()
        for k in cp.Group.__slots__:
            setattr(n, k, getattr(g, k))
        n.w, n.h = g.w + grow[0], g.h + grow[1]
        sp = [0] * (n.w * n.h * n.layers * n.px * n.py * n.pz * n.phases)
        for i, sid in enumerate(g.sprites):
            ww, hh, layer, x, y, z, ph = slot(g, i)
            sp[cp.sprite_index(n, x, y, z, layer, ph, ww, hh)] = sid
        for (gj, x, y, z, layer, ph), a in frames.items():
            if gj != gi:
                continue
            for (ww, hh), tile in tiles_of(a, n).items():
                rec = encode_sprite(tile)
                sid = 0
                if rec is not None:
                    sid = rec_index.get(rec)
                    if sid is None:
                        records.append(rec)
                        sid = rec_index[rec] = base_count + len(records)
                sp[cp.sprite_index(n, x, y, z, layer, ph, ww, hh)] = sid
        n.sprites = sp
        groups.append(n)
    return groups


# ---------------------------------------------------------------------------------------------------------- render
def colourize(base, mask, colours=((236, 196, 140), (150, 40, 40), (60, 70, 140), (90, 70, 50))):
    """the client's outfit colouring, roughly: a mask pixel of a template colour multiplies the base pixel."""
    out = base.copy().astype(np.float32)
    for tc, c in zip(((255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255)), colours):
        m = np.all(mask[:, :, :3] == tc, axis=2) & (mask[:, :, 3] > 0)
        out[m, :3] = out[m, :3] * np.array(c, np.float32) / 255
    return out.astype(np.uint8)


class Canvas:
    def __init__(self, w, h, ox, oy):
        self.a = np.zeros((h, w, 4), np.uint8)
        self.ox, self.oy = ox, oy             # canvas px of the creature tile's top left

    def put(self, img, sx, sy):
        """alpha-over img with its top left at screen (sx, sy) (tile coordinates)."""
        x0, y0 = sx + self.ox, sy + self.oy
        h, w = img.shape[:2]
        H, W = self.a.shape[:2]
        cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(W, x0 + w), min(H, y0 + h)
        if cx0 >= cx1 or cy0 >= cy1:
            return
        src = img[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0].astype(np.float32)
        dst = self.a[cy0:cy1, cx0:cx1].astype(np.float32)
        al = src[:, :, 3:4] / 255
        dst[:, :, :3] = src[:, :, :3] * al + dst[:, :, :3] * (1 - al)
        dst[:, :, 3:4] = np.maximum(dst[:, :, 3:4], src[:, :, 3:4])
        self.a[cy0:cy1, cx0:cx1] = dst.astype(np.uint8)


def draw_type(cv, t, spr, dest, x, y=0, z=0, phase=0, layers=True, group=0):
    """ThingType::draw: frame pixel at dest - displacement - (size - 1) * 32."""
    g = t.groups[min(group, len(t.groups) - 1)]
    x = min(x, g.px - 1)
    z = min(z, g.pz - 1)
    phase = phase % g.phases
    base = frame(g, spr, x, y, z, phase, 0)
    if layers and g.layers > 1:
        base = colourize(base, frame(g, spr, x, y, z, phase, 1))
    dx, dy = disp(t)
    cv.put(base, dest[0] - dx - (g.w - 1) * 32, dest[1] - dy - (g.h - 1) * 32)


def draw_outfit(cv, outs, spr, look, x, mount=0, wings=0, phase=0, group=0):
    """Outfit::draw on the map (no ignoreDisplacement), 1098 profile: GameWingOffset on, no centred outfits; the wing
    bob is left out (offset 0)."""
    t = outs[look - 1]
    dest = [0, 0]
    wing_dest = [0, 0]
    if wings:
        dest = [-WING_LIFT, -WING_LIFT]
    g = t.groups[min(group, len(t.groups) - 1)]
    zp = min(1, g.pz - 1) if mount else 0
    if mount and zp > 0:
        mt = outs[mount - 1]
        md, rd = disp(mt), disp(t)
        mneg = negative(md)
        if not mneg:
            dest[0] -= md[0]
            dest[1] -= md[1]
        draw_type(cv, mt, spr, dest, x, 0, 0, phase, layers=False, group=group)
        if negative(rd) or mneg:
            if not mneg:
                dest[0] += md[0]
                dest[1] += md[1]
            b = mt.flag('bones')
            if mneg and b is not None and t.flag('bones') is None:
                k = {0: 0, 2: 1, 1: 2, 3: 3}[x]          # file order north, south, east, west
                dest[0] += b[2 * k]
                dest[1] += b[2 * k + 1]
        else:
            dest[0] += rd[0]
            dest[1] += rd[1]
    wt = outs[wings - 1] if wings else None
    if wt is not None and x in (1, 2):
        wd = list(wing_dest)
        if zp > 0:
            wd = [wd[0] - 6, wd[1] - 2] if x == 1 else [wd[0], wd[1] - 6]
        draw_type(cv, wt, spr, wd, x, 0, 0, phase, layers=False)
    for y in range(g.py):
        draw_type(cv, t, spr, dest, x, y, zp, phase, group=group)
    if wt is not None and x in (0, 3):
        wd = list(wing_dest)
        if zp > 0:
            wd = [wd[0] + 4, wd[1] + 6]
        draw_type(cv, wt, spr, wd, x, 0, 0, phase, layers=False)


def sheet(outs, spr, riders, mounts, wings, path, phase=0, group=0, scale=3):
    from PIL import Image, ImageDraw
    cell = 128
    cols = [(0, 0)] + [(m, 0) for m in mounts]
    rows = [(r, 0) for r in riders] + [(riders[0], w) for w in wings]
    W, H = len(cols) * 4 * cell, len(rows) * cell
    img = Image.new('RGBA', (W, H), (52, 56, 52, 255))
    d = ImageDraw.Draw(img)
    for ri, (rider, wing) in enumerate(rows):
        for ci, (mount, _) in enumerate(cols):
            for x in range(4):
                X, Y = (ci * 4 + x) * cell, ri * cell
                for k in range(-2, 2):           # tile grid, creature tile at (80, 80)
                    d.line([(X + 80 + 32 * k, Y), (X + 80 + 32 * k, Y + cell - 1)], fill=(70, 76, 70, 255))
                    d.line([(X, Y + 80 + 32 * k), (X + cell - 1, Y + 80 + 32 * k)], fill=(70, 76, 70, 255))
                d.rectangle([X + 80, Y + 80, X + 111, Y + 111], outline=(120, 120, 90, 255))
                cv = Canvas(cell, cell, 80, 80)
                draw_outfit(cv, outs, spr, rider, x, mount, wing, phase, group)
                img.alpha_composite(Image.fromarray(cv.a, 'RGBA'), (X, Y))
            d.text((ci * 4 * cell + 3, ri * cell + 2), f'{rider}' + (f' w{wing}' if wing else '') +
                   (f' m{mount}' if mount else ' standing'), fill=(230, 230, 200, 255))
    for ci in range(1, len(cols)):
        d.line([(ci * 4 * cell, 0), (ci * 4 * cell, H)], fill=(160, 40, 40, 255), width=2)
    img = img.resize((W * scale // 2, H * scale // 2), Image.NEAREST)
    img.save(path)


# ---------------------------------------------------------------------------------------------------------- build
def read_spec(path):
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            if row['kind'] not in ('mounted', 'wings'):
                raise SystemExit(f'{path}: unknown kind {row["kind"]!r}')
            row['id'] = int(row['id'])
            rows.append(row)
    if not rows:
        raise SystemExit(f'{path}: no rows')
    if len({r['id'] for r in rows}) != len(rows):
        raise SystemExit(f'{path}: a look is listed twice')
    return rows


def set_disp(t, data, d):
    """flag bytes of t with displacement d (inserted in flag order, or replaced); None when already d."""
    chunks = flag_chunks(data, t, t.end - len(groups_bytes(t)))
    new = (DISP, bytes([DISP]) + struct.pack('<hh', *d))
    old = [c for c in chunks if c[0] == DISP]
    if old and old[0][1] == new[1]:
        return None, None
    if old:
        chunks[chunks.index(old[0])] = new
    else:
        k = next((i for i, c in enumerate(chunks) if c[0] > DISP and c[0] != 254), len(chunks))
        chunks.insert(k, new)
    return b''.join(c[1] for c in chunks), (disp(t) if old else None)


def mounted_entry(t, frames, grow, records, rec_index, base_count):
    """the entry's group part with pattern Z 2 (and the frame grown up / left by grow tiles): z = 0 the old ids
    (a grown tile is empty there), z = 1 new records (deduplicated)."""
    groups = []
    for gi, g in enumerate(t.groups):
        n = cp.Group()
        for k in cp.Group.__slots__:
            setattr(n, k, getattr(g, k))
        n.pz = 2
        n.w, n.h = g.w + grow[0], g.h + grow[1]
        sp = [0] * (n.w * n.h * n.layers * n.px * n.py * n.pz * n.phases)
        for i, sid in enumerate(g.sprites):
            ww, hh, layer, x, y, z, ph = slot(g, i)
            sp[cp.sprite_index(n, x, y, 0, layer, ph, ww, hh)] = sid
        for x in range(g.px):
            for y in range(g.py):
                for layer in range(g.layers):
                    for ph in range(g.phases):
                        for (ww, hh), tile in tiles_of(frames[(gi, x, y, layer, ph)], n).items():
                            rec = encode_sprite(tile)
                            sid = 0
                            if rec is not None:
                                sid = rec_index.get(rec)
                                if sid is None:
                                    records.append(rec)
                                    sid = rec_index[rec] = base_count + len(records)
                            sp[cp.sprite_index(n, x, y, 1, layer, ph, ww, hh)] = sid
        n.sprites = sp
        groups.append(n)
    return groups


def slot(g, idx):
    r = idx
    ww = r % g.w; r //= g.w
    hh = r % g.h; r //= g.h
    layer = r % g.layers; r //= g.layers
    x = r % g.px; r //= g.px
    y = r % g.py; r //= g.py
    z = r % g.pz; r //= g.pz
    return ww, hh, layer, x, y, z, r


class _T:
    """a stand-in thing for groups_bytes."""
    def __init__(self, cat, groups):
        self.cat, self.groups, self.ref = cat, groups, cat


def build(a):
    data = open(a.ours_dat, 'rb').read()
    if a.expect_dat_md5 and hashlib.md5(data).hexdigest() not in a.expect_dat_md5.split(','):
        raise SystemExit(f'{a.ours_dat}: md5 {hashlib.md5(data).hexdigest()} is not {a.expect_dat_md5}')
    sig, counts, things, end = cp.parse_dat(data)
    outs = things['outfit']
    spr = Sprites(a.ours_spr)
    spec = read_spec(a.spec)
    n_stock, stock = measure_stock(outs, spr)
    body = body_centre(outs, spr)
    target = stock_wings(outs, spr, body)
    print(f'stock riders: {n_stock}; stock wings: {len(STOCK_WINGS)}')
    new_entries = {}
    records, rec_index = [], {}
    built = {}
    changes = []
    for row in spec:
        if not 1 <= row['id'] <= len(outs):
            raise SystemExit(f'outfit {row["id"]}: not in the pair')
        t = outs[row['id'] - 1]
        flags_end = t.end - len(groups_bytes(t))
        flags = bytes(data[t.start:flags_end - 1])
        if row['kind'] == 'mounted':
            pz = {g.pz for g in t.groups}
            if pz == {2}:
                continue                                     # applied already
            if pz != {1}:
                raise SystemExit(f'{t.ref}: pattern Z {sorted(pz)}, not 1')
            corr, plan, frames, grow = mounted_frames(t, spr, stock)
            groups = mounted_entry(t, frames, grow, records, rec_index, spr.count)
            built[t.id] = ('mounted', frames, grow)
            if grow != (0, 0):
                print(f'{t.ref}: frame grown {grow[0]} tile(s) left, {grow[1]} up for the mounted art')
            new_entries[t.id] = flags + b'\xff' + groups_bytes(_T('outfit', groups))
            changes.append(('outfit', t.id, '*', 'pattern z', 'every group', '1', '2', row['reason']))
        else:
            try:
                d = tuple(int(v) for v in row['disp'].split(','))
                assert len(d) == 2 and all(-64 <= v <= 64 for v in d)
            except (ValueError, AssertionError):
                raise SystemExit(f'{t.ref}: wings disp {row["disp"]!r} is not "X,Y" (-64..64)')
            sh = parse_shifts(row['shift'])
            old_d = tuple(int(v) for v in row['disp_old'].split(','))
            if d == old_d:
                raise SystemExit(f'{t.ref}: disp_old and disp are the same (a row must change the displacement, '
                                 'which marks it applied)')
            if disp(t) == d:
                continue                                     # applied already
            if disp(t) != old_d:
                raise SystemExit(f'{t.ref}: displacement {disp(t)}, not the {old_d} the row was measured on')
            err = wing_errors(t, spr, body, target, d, sh)
            bad = wing_bad(err, sh)
            if bad:
                raise SystemExit(f'{t.ref}: wings with {d[0]},{d[1]} and shifts {sh} do not sit like the stock wings: '
                                 + '; '.join(f'{DIRS[x]} across {err[x][0]:+.1f} root {err[x][1]:+.1f}'
                                             if x != 'mean' else 'an axis still off' for x in bad))
            nf, old = set_disp(t, data, d)
            if nf is None:
                nf = flags
            groups = t.groups
            if sh:
                frames, grow = shifted_wings(t, spr, sh)
                groups = wings_entry(t, spr, frames, grow, records, rec_index, spr.count)
                built[t.id] = ('wings', frames, grow)
                changes.append(('outfit', t.id, '*', 'frames', shifts_text(sh), 'as drawn',
                                'moved' + (f', frame grown {grow[0]} left {grow[1]} up' if grow != (0, 0) else ''),
                                row['reason']))
            new_entries[t.id] = nf + b'\xff' + groups_bytes(_T('outfit', groups))
            if disp(t) != d:
                changes.append(('outfit', t.id, '*', 'displacement', 'flag 25',
                                'none' if old is None else f'{old[0]},{old[1]}', f'{d[0]},{d[1]}', row['reason']))
    # dat
    out = bytearray(data[:12])
    for cat in cp.CATS:
        for t in things[cat]:
            if cat == 'outfit' and t.id in new_entries:
                out += new_entries[t.id]
            else:
                out += data[t.start:t.end]
    os.makedirs(a.out_dir, exist_ok=True)
    od, osp = os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr')
    for p in (od, osp):
        if os.path.abspath(p) in (os.path.abspath(a.ours_dat), os.path.abspath(a.ours_spr)):
            raise SystemExit('--out-dir must not hold the input pair')
    with open(od, 'wb') as f:
        f.write(out)
    write_spr(spr.f, records, osp)
    print(f'dat: {len(new_entries)} looks changed; spr: {spr.count} -> {spr.count + len(records)} sprites')
    verify(data, things, out, spr, osp, new_entries, built, records)
    spr.close()
    if a.changes_out:
        with open(a.changes_out, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f, lineterminator='\n')
            w.writerow(['cat', 'id', 'group', 'field', 'where', 'old', 'new', 'reason'])
            w.writerows(changes)
    allow = ','.join(str(i) for i in sorted(new_entries))
    if allow:
        if not cp.check_append_only(a.ours_dat, a.ours_spr, od, osp, cp.parse_allow('outfit:' + allow)):
            raise SystemExit('check_pair append-only check failed')
    print(f'ok: {od} {md5(od)}; {osp} {md5(osp)}')


def write_spr(sf, records, path):
    """old table + records shifted by the larger table, new records appended (as import_outfits.py)."""
    m = sf.m
    cnt = sf.count
    nn = len(records)
    offs = np.frombuffer(m, dtype='<u4', count=cnt, offset=8).astype('<u8')
    first = int(offs[offs > 0].min()) if (offs > 0).any() else 8 + 4 * cnt
    tail = len(m)
    toffs = offs.copy()
    toffs[toffs > 0] += 4 * nn
    cur = tail + 4 * nn
    new = []
    for rec in records:
        new.append(cur)
        cur += len(rec)
    if cur >= 1 << 32:
        raise SystemExit('spr would exceed 4 GB')
    table = np.concatenate([toffs, np.array(new, dtype='<u8')]).astype('<u4')
    with open(path, 'wb') as f:
        f.write(struct.pack('<II', struct.unpack_from('<I', m, 0)[0], cnt + nn))
        f.write(table.tobytes())
        pos = 8 + 4 * cnt
        if first < pos:
            raise SystemExit('spr: a record inside the offset table')
        while pos < tail:
            f.write(m[pos:min(tail, pos + (1 << 24))])
            pos += 1 << 24
        for rec in records:
            f.write(rec)


def verify(data, things, out, spr, osp, new_entries, built, records):
    sig2, counts2, things2, end2 = cp.parse_dat(bytes(out))
    sig, counts = struct.unpack_from('<I', data, 0)[0], struct.unpack_from('<4H', data, 4)
    if (sig2, counts2) != (sig, counts) or end2 != len(out):
        raise SystemExit('verify: header or length differs')
    for cat in cp.CATS:
        for t, u in zip(things[cat], things2[cat]):
            if cat == 'outfit' and t.id in new_entries:
                continue
            if data[t.start:t.end] != out[u.start:u.end]:
                raise SystemExit(f'verify: {t.ref} changed')
    ns = Sprites(osp)
    if ns.count != spr.count + len(records):
        raise SystemExit('verify: spr count')
    step = max(1, spr.count // 3000)
    for sid in list(range(1, spr.count + 1, step)) + [spr.count]:
        if spr.record(sid) != ns.record(sid):
            raise SystemExit(f'verify: sprite {sid} changed')
    for k, rec in enumerate(records):
        if bytes(ns.record(spr.count + 1 + k)) != rec:
            raise SystemExit(f'verify: new sprite {spr.count + 1 + k}')
    for look in new_entries:
        t, u = things['outfit'][look - 1], things2['outfit'][look - 1]
        kind, frames, grow = built.get(look, ('disp', {}, (0, 0)))
        if kind == 'mounted' and t.flags != u.flags:
            raise SystemExit(f'verify: {t.ref} flags changed')
        if [f for f in t.flags if f[0] != DISP] != [f for f in u.flags if f[0] != DISP]:
            raise SystemExit(f'verify: {t.ref} flags other than the displacement changed')
        if kind == 'disp':
            if groups_bytes(t) != groups_bytes(u):
                raise SystemExit(f'verify: {t.ref} frame groups changed')
            continue
        for gi, (g, h) in enumerate(zip(t.groups, u.groups)):
            for k in ('gtype', 'exact', 'layers', 'px', 'py', 'phases', 'anim'):
                if getattr(g, k) != getattr(h, k):
                    raise SystemExit(f'verify: {t.ref} group {gi} {k}')
            if (h.w, h.h) != (g.w + grow[0], g.h + grow[1]) or h.pz != (2 if kind == 'mounted' else g.pz):
                raise SystemExit(f'verify: {t.ref} group {gi} size or pattern z')
            for x in range(g.px):
                for y in range(g.py):
                    for z in range(g.pz):
                        for layer in range(g.layers):
                            for ph in range(g.phases):
                                b = frame(h, ns, x, y, z, ph, layer)
                                if kind == 'wings' and (gi, x, y, z, layer, ph) in frames:
                                    want = frames[(gi, x, y, z, layer, ph)].copy()
                                    want[want[:, :, 3] == 0] = 0
                                    if not np.array_equal(b, want):
                                        raise SystemExit(f'verify: {t.ref} moved frame {gi} {x} {y} {z} {layer} {ph}')
                                    continue
                                a = frame(g, spr, x, y, z, ph, layer)
                                if not np.array_equal(a, b[b.shape[0] - a.shape[0]:, b.shape[1] - a.shape[1]:]) or \
                                        b[:b.shape[0] - a.shape[0]].any() or b[:, :b.shape[1] - a.shape[1]].any():
                                    raise SystemExit(f'verify: {t.ref} frame {gi} {x} {y} {z} {layer} {ph} changed')
            if kind == 'mounted':
                for x in range(h.px):
                    for y in range(h.py):
                        for layer in range(h.layers):
                            for ph in range(h.phases):
                                want = frames[(gi, x, y, layer, ph)].copy()
                                want[want[:, :, 3] == 0] = 0
                                if not np.array_equal(frame(h, ns, x, y, 1, ph, layer), want):
                                    raise SystemExit(f'verify: {t.ref} mounted frame {gi} {x} {y} {layer} {ph}')
    ns.close()
    print(f'verified: {len(new_entries)} changed looks, the rest byte-identical; {len(records)} new sprites decode '
          f'to the built frames; old sprites sampled byte-identical')


# ----------------------------------------------------------------------------------------------------------- main
def parse_ids(s):
    out = []
    for part in (s or '').split(','):
        if part.strip():
            lo, _, hi = part.partition('-')
            out += list(range(int(lo), int(hi or lo) + 1))
    return out


def scan(a):
    data = open(a.ours_dat, 'rb').read()
    sig, counts, things, end = cp.parse_dat(data)
    outs = things['outfit']
    spr = Sprites(a.ours_spr)
    n, stock = measure_stock(outs, spr)
    print(f'stock riders: {n}')
    for x, s in enumerate(stock):
        print(f'  {DIRS[x]:5}: head delta {s["delta"][0]:+.1f},{s["delta"][1]:+.1f}  trim {s["trim"]}  height '
              f'{s["h"]}  feet {s["feet"][0]:+.1f},{s["feet"][1]:+.1f}  bob {s["bob"]}')
    for look in parse_ids(a.looks):
        t = outs[look - 1]
        pz = sorted({g.pz for g in t.groups})
        line = f'{look}: pattern z {pz} disp {disp(t)} ' + ' '.join(
            f'{g.w}x{g.h}L{g.layers}P{g.px}{g.py}{g.pz}F{g.phases}' for g in t.groups)
        if pz == [1]:
            corr, plan = plan_mounted(t, spr, stock)
            line += f'  feet correction {corr}  ' + ' '.join(
                f'{DIRS[x][0]}:shift{p["shift"]} trim{p["trim"]}' for x, p in enumerate(plan))
        print(line)
    if a.wings:
        body = body_centre(outs, spr)
        target = stock_wings(outs, spr, body)
        print('body centre (screen, lift included): ' + ' '.join(f'{DIRS[x][0]}:{b[0]:+.1f},{b[1]:+.1f}' for x, b in enumerate(body)))
        print('stock wings (across, root) medians: ' + ' '.join(f'{DIRS[x][0]}:{v[0]:+.1f},{v[1]:+.1f}' for x, v in enumerate(target)))
        print(f'per direction: across, root error against the stock median (px); mean across error x (N, S), y (E, W); '
              f'off at {WING_OFF} or more')
        for look in parse_ids(a.wings):
            t = outs[look - 1]
            err = wing_errors(t, spr, body, target)
            ex, ey = wing_axis_error(err)
            d = wing_fit(t, spr, body, target)
            line = f'{look}: disp {disp(t)[0]},{disp(t)[1]} ' + ' '.join(
                f'{DIRS[x][0]}{v[0]:+.1f},{v[1]:+.1f}' for x, v in enumerate(err)) + f'  mean {ex:+.1f},{ey:+.1f}'
            if not wing_off(err):
                print(line + '  ok')
                continue
            err2 = wing_errors(t, spr, body, target, d)
            ex, ey = wing_axis_error(err2)
            print(line + f'  OFF\n      fix: disp {d[0]},{d[1]} -> ' +
                  ' '.join(f'{DIRS[x][0]}{v[0]:+.1f},{v[1]:+.1f}' for x, v in enumerate(err2)) +
                  f'  mean {ex:+.1f},{ey:+.1f}' + ('  still off' if wing_bad(err2) else '  ok'))
    spr.close()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('scan')
    s.add_argument('--ours-dat', required=True)
    s.add_argument('--ours-spr', required=True)
    s.add_argument('--looks', default='')
    s.add_argument('--wings', default='')
    b = sub.add_parser('build')
    b.add_argument('--ours-dat', required=True)
    b.add_argument('--ours-spr', required=True)
    b.add_argument('--out-dir', required=True)
    b.add_argument('--spec', default=SPEC)
    b.add_argument('--expect-dat-md5', default=None)
    b.add_argument('--changes-out', default=None)
    h = sub.add_parser('sheet')
    h.add_argument('--dat', required=True)
    h.add_argument('--spr', required=True)
    h.add_argument('--out', required=True)
    h.add_argument('--riders', required=True)
    h.add_argument('--mounts', default='')
    h.add_argument('--wings', default='')
    h.add_argument('--phase', type=int, default=0)
    h.add_argument('--group', type=int, default=0)
    a = ap.parse_args(argv)
    if a.cmd == 'scan':
        scan(a)
    elif a.cmd == 'build':
        build(a)
    else:
        data = open(a.dat, 'rb').read()
        things = cp.parse_dat(data)[2]
        spr = Sprites(a.spr)
        sheet(things['outfit'], spr, parse_ids(a.riders), parse_ids(a.mounts), parse_ids(a.wings), a.out, a.phase,
              a.group)
        spr.close()


if __name__ == '__main__':
    main()
