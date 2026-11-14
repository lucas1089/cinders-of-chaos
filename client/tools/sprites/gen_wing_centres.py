#!/usr/bin/env python3
"""Where each body's torso and each wings' pair centre are, for the engine to centre wings on the body (O495, base patch 0193).

usage: python3 -I client/tools/sprites/gen_wing_centres.py Tibia.dat Tibia.spr [--out PATH] [--check]

Outfit::draw (GameWingOffset) draws the wings at the creature's place and the body 6 px up and left of it. The wings' art
was placed against one body (the stock look 128), so on a class look that stands further left or right in its tile the
wings sat off its back: facing south a median 3.4 px right of a class look's torso, a Warrior 12 px (client/MANIFEST.md
"Wings centred on the body"). This tool measures, per direction (north, east, south, west):
  bodies[look]  x of the body's torso, sprite px at 1x from the creature's place, the look's own displacement taken out.
                Idle group, phase 0, base layer, the union of the base and every addon pattern (a character may wear
                any). The torso is the band of rows from 30% to 70% of the opaque box's height (no head or hat above,
                no legs below) of the body CORE (O576): the visible pixels with their thin parts opened away (TORSO_OPEN, a
                staff, torch or spear up to four wide) and only the biggest part kept, so a weapon does not pull the centre
                (it pulled a staff look's torso 4 to 6 px); x is the median column of the core's pixels in that band.
  wings[look]   x of the wings' pair centre, same frame. Every phase and layer, alpha-weighted, WITHOUT the baked ground
                shadow (below). Two masses (a gap of 2 or more empty columns between used columns of the union of all
                phases, the widest one splits it) that each hold 25% or more of the art: the midpoint of the two masses'
                means. Otherwise (one mass, or a thin streak beside a main wing) the mean of all the art.
The baked shadow: most pack wings carry the vendor's soft ground shadow in their sprites (100 of 121 wings, a dark core
and ring, 24 px right of and 30 px below the wings' centre). A pixel is shadow when its alpha is under 200 and its
luminance (mean of r, g, b) under 150. Limits: a pale shadow ring or a dark glow of a wing is taken wrongly the one
way or the other (16 wings carry partial alpha that is wing art; their centre moves by at most a pixel or two); faint
pixels (alpha under about 40) weigh little either way. The older measures (fix_pair_warnings.py wing_offset,
gen_pack33.py wingx) counted the shadow in the alpha mean, which is why WING_X_FIX was tuned to the wrong centre.

Heads (O561, base patch 0200): the same run writes client_chaos_wingfit/head_centres.lua, per body look the x and y of the
head (the solid body, thin parts opened away, the top HEAD_BAND rows) and the same for look 128; the engine moves a head
piece (aura looks 2477 to 2568) by head(body) - head(128). Details: client/MANIFEST.md "Head accessories on the head".

Output (default): client/overlay/modules/client_chaos_wingfit/wing_centres.lua (`ChaosWingCentres`: dat md5, bodies,
wings; integer px). The module hands the rows to the engine (setOutfitBodyCentre, setOutfitWingsCentre; base patch
0193), which shifts the wings by bodyCentre - wingsCentre - 6 so the pair centre lands on the torso. A look not in a table
gets no shift. Deterministic: the same pair writes the same file; --check exits 1 when the file differs from what the
pair gives. Regenerate it with every new pair (the dat md5 is in the file).
"""
import argparse
import hashlib
import math
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from datspr import Dat, Spr, sprite_index  # noqa: E402
import gen_outfit_anchors as anchors  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_wingfit', 'wing_centres.lua')
OUT_HEADS = os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_wingfit', 'head_centres.lua')
PACK33 = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_pack33_cosmetics.lua')
# the wings looks of wings.xml: base 1-15, Chaos 16-29 (fix_pair_warnings.py WINGS_LOOKS), then the pair 33 wings
BASE_WINGS = '937-941,1177-1186,1486,2140-2142,2187,2225-2233'
TORSO_LO, TORSO_HI = 0.30, 0.70
TORSO_OPEN = 2          # the opening that drops a staff, a torch or a spear from the torso core (gen_outfit_anchors.solid)
SHADOW_ALPHA = 200      # a baked shadow pixel: alpha under this and luminance under SHADOW_LUM
SHADOW_LUM = 150
GAP_MIN = 2             # empty columns that split the wings into a left and a right mass
MASS_MIN = 0.25         # each mass holds at least this share of the art, else one mass
DIRS = 4
# head accessories (O561, base patch 0200): the pair 33 head pieces are the aura looks 2477 to 2568 (capes follow from 2569);
# the pieces were placed against the stock look 128, so a body's head is measured against 128's
HEAD_PIECES = (2477, 2568)
HEAD_REF = 128
HEAD_BAND = 10          # rows from the top of the body's solid mass that make the head (px)
HEAD_OPEN = 2           # the opening that drops a staff, a torch or a spear above the head (gen_outfit_anchors.solid)


def ids(spec):
    out = []
    for p in spec.split(','):
        if '-' in p:
            a, b = p.split('-')
            out += range(int(a), int(b) + 1)
        elif p:
            out.append(int(p))
    return out


def pack33_wings(path=PACK33):
    """the pair 33 wings looks from the server's generated list (lines {key = "wings_..", id, look, ...})"""
    text = open(path, encoding='utf-8').read()
    return [int(m.group(1)) for m in re.finditer(r'\{key = "wings_\w+", id = \d+, look = (\d+)', text)]


def signed(v):
    return v - 65536 if v > 32767 else v


def displacement(t):
    d = t.flags.get('displacement')
    return (signed(d[0]), signed(d[1])) if isinstance(d, tuple) else (0, 0)


def rnd(v):
    return int(math.floor(v + 0.5))


# ------------------------------------------------------------------------------------------------ pure measures
def torso_x(alpha):
    """x (canvas px) of the torso of a body, the body core's: the visible pixels (alpha from anchors.ALPHA) without their thin
    parts (an opening of TORSO_OPEN, a staff, a torch or a spear up to four wide goes) and with only the biggest part kept
    (a weapon held apart falls away); the rows from TORSO_LO to TORSO_HI of that core's own box (no head or hat above, no
    legs below, a staff raised over the head does not stretch the box); x is the MEDIAN column of its pixels, so a broad
    weapon that is attached still moves it only by half of its width. None when nothing is visible. alpha: 2-D array.
    (O576: the whole figure's alpha mean pulled a staff look's torso 4 to 6 px towards the staff and the wings sat off.)"""
    a = np.asarray(alpha, np.float64)
    m = a >= anchors.ALPHA
    if not m.any():
        m = a > 0                      # only faint pixels: they are the figure
    if not m.any():
        return None
    core = anchors.largest_part(anchors.solid(m, TORSO_OPEN))
    ys, xs = np.nonzero(core)
    top, bot = ys.min(), ys.max() + 1
    r0 = top + TORSO_LO * (bot - top)
    r1 = top + TORSO_HI * (bot - top)
    sel = (ys >= r0) & (ys < r1)
    if not sel.any():
        sel = np.ones(len(ys), bool)
    return float(np.median(xs[sel]))


def shadow_mask(rgba):
    """the baked ground shadow pixels of a wings frame (RGBA uint8)"""
    a = rgba[..., 3]
    lum = rgba[..., :3].astype(np.float64).mean(axis=2)
    return (a > 0) & (a < SHADOW_ALPHA) & (lum < SHADOW_LUM)


def wings_x(frames):
    """x (canvas px) of the wings' pair centre from the RGBA frames of every phase and layer; None when empty"""
    art = None
    union = None
    for f in frames:
        f = np.asarray(f)
        w = np.where(shadow_mask(f), 0, f[..., 3]).astype(np.float64)
        art = w if art is None else art + w
        union = (w > 0) if union is None else union | (w > 0)
    if art is None or not union.any():
        return None
    xx = np.mgrid[0:art.shape[0], 0:art.shape[1]][1]
    tot = art.sum()
    mean = (art * xx).sum() / tot
    cols = np.nonzero(union.any(axis=0))[0]
    gaps = [(b - a - 1, a, b) for a, b in zip(cols[:-1], cols[1:]) if b - a - 1 >= GAP_MIN]
    if not gaps:
        return float(mean)
    _, ga, gb = max(gaps)
    left, right = art * (xx <= ga), art * (xx >= gb)
    if left.sum() < MASS_MIN * tot or right.sum() < MASS_MIN * tot:
        return float(mean)
    return float(((left * xx).sum() / left.sum() + (right * xx).sum() / right.sum()) / 2)


# ------------------------------------------------------------------------------------------------ the pair
def frame_alpha_union(t, spr, d):
    """alpha canvas of direction d: phase 0, base layer, the union of every addon pattern"""
    W, H = t.w * 32, t.h * 32
    out = np.zeros((H, W), np.uint8)
    for yy in range(max(1, t.py)):
        for hh in range(t.h):
            for ww in range(t.w):
                a = spr.sprite(t.sprites[sprite_index(t, d, yy, 0, 0, 0, ww, hh)])
                if a is not None:
                    oy, ox = (t.h - 1 - hh) * 32, (t.w - 1 - ww) * 32
                    np.maximum(out[oy:oy + 32, ox:ox + 32], a[..., 3], out=out[oy:oy + 32, ox:ox + 32])
    return out


def wings_frames(t, spr, d):
    W, H = t.w * 32, t.h * 32
    for ph in range(max(1, t.phases)):
        for layer in range(max(1, t.layers)):
            img = np.zeros((H, W, 4), np.uint8)
            for hh in range(t.h):
                for ww in range(t.w):
                    a = spr.sprite(t.sprites[sprite_index(t, d, 0, 0, layer, ph, ww, hh)])
                    if a is not None:
                        oy, ox = (t.h - 1 - hh) * 32, (t.w - 1 - ww) * 32
                        img[oy:oy + 32, ox:ox + 32] = a
            yield img


def to_place(x, t):
    """canvas x -> px from the creature's place: the look's displacement and the (tiles - 1) tiles of its frame out"""
    return x - displacement(t)[0] - (t.w - 1) * 32


def body_row(t, spr):
    if not t.sprites or t.px < DIRS:
        return None
    row = []
    for d in range(DIRS):
        x = torso_x(frame_alpha_union(t, spr, d))
        if x is None:
            return None
        row.append(rnd(to_place(x, t)))
    return row


def wings_row(t, spr):
    if not t.sprites or t.px < DIRS:
        return None
    row = []
    for d in range(DIRS):
        x = wings_x(list(wings_frames(t, spr, d)))
        if x is None:
            return None
        row.append(rnd(to_place(x, t)))
    return row


def head_xy(alpha):
    """(x, y) in canvas px of a body's head: the solid body (thin parts opened away, only the biggest part kept) from its
    top row down HEAD_BAND rows; x the mean of those pixels, y the middle of the band; None when nothing is visible"""
    m = np.asarray(alpha) >= anchors.ALPHA
    if not m.any():
        return None
    core = anchors.largest_part(anchors.solid(m, HEAD_OPEN))
    ys, xs = np.nonzero(core)
    top = ys.min()
    sel = ys < top + HEAD_BAND
    return float(xs[sel].mean()), float(top + HEAD_BAND / 2.0)


def head_row(t, spr):
    """[x north, y north, x east, y east, ...] of a body's head, px from the creature's place; None without art"""
    if not t.sprites or t.px < DIRS:
        return None
    row = []
    for d in range(DIRS):
        h = head_xy(frame_alpha_union(t, spr, d))
        if h is None:
            return None
        row.append(rnd(to_place(h[0], t)))
        row.append(rnd(h[1] - displacement(t)[1] - (t.h - 1) * 32))
    return row


def wing_ids():
    return sorted(set(ids(BASE_WINGS)) | set(pack33_wings()))


def build(dat_path, spr_path):
    dat = Dat(dat_path)
    spr = Spr(spr_path)
    md5 = hashlib.md5(open(dat_path, 'rb').read()).hexdigest()
    wing_set = wing_ids()
    wing_rows, body_rows = [], []
    for i in wing_set:
        if 1 <= i <= len(dat.outfits):
            r = wings_row(dat.outfits[i - 1], spr)
            if r:
                wing_rows.append('[%d]={%s}' % (i, ','.join(map(str, r))))
    ws = set(wing_set)
    for i, t in enumerate(dat.outfits, 1):
        if i in ws:
            continue
        r = body_row(t, spr)
        if r:
            body_rows.append('[%d]={%s}' % (i, ','.join(map(str, r))))
    lines = ['-- Generated by client/tools/sprites/gen_wing_centres.py from the pair with dat md5 %s.' % md5,
             '-- Do not edit: regenerate with the tool for every new pair. x in sprite px at 1x from the creature\'s place,',
             '-- the look\'s displacement out, north / east / south / west: bodies = the torso, wings = the pair centre',
             '-- without the baked shadow (base patch 0193 shifts the wings onto the torso).',
             'ChaosWingCentres = {', '  dat = "%s",' % md5, '  bodies = {']
    for k in range(0, len(body_rows), 6):
        lines.append('    ' + ','.join(body_rows[k:k + 6]) + ',')
    lines += ['  },', '  wings = {']
    for k in range(0, len(wing_rows), 4):
        lines.append('    ' + ','.join(wing_rows[k:k + 4]) + ',')
    lines += ['  },', '}', 'return ChaosWingCentres']
    return '\n'.join(lines) + '\n', len(body_rows), len(wing_rows)


def build_heads(dat_path, spr_path):
    """the text of head_centres.lua and the number of bodies: the head of every body look (the wings looks left out, as in
    wing_centres.lua) and of the reference look"""
    dat = Dat(dat_path)
    spr = Spr(spr_path)
    md5 = hashlib.md5(open(dat_path, 'rb').read()).hexdigest()
    ws = set(wing_ids())
    ref = head_row(dat.outfits[HEAD_REF - 1], spr)
    rows = []
    for i, t in enumerate(dat.outfits, 1):
        if i in ws:
            continue
        r = head_row(t, spr)
        if r:
            rows.append('[%d]={%s}' % (i, ','.join(map(str, r))))
    lines = ['-- Generated by client/tools/sprites/gen_wing_centres.py from the pair with dat md5 %s.' % md5,
             '-- Do not edit: regenerate with the tool for every new pair. Per look the x and y of the body\'s head (north, east,',
             '-- south, west), sprite px at 1x from the creature\'s place, the look\'s displacement out; ref = look %d. The head' % HEAD_REF,
             '-- pieces (aura looks first..last) are shifted by head(body) - ref (base patch 0200).',
             'ChaosHeadCentres = {', '  dat = "%s",' % md5, '  first = %d,' % HEAD_PIECES[0], '  last = %d,' % HEAD_PIECES[1],
             '  ref = {%s},' % ','.join(map(str, ref)), '  bodies = {']
    for k in range(0, len(rows), 4):
        lines.append('    ' + ','.join(rows[k:k + 4]) + ',')
    lines += ['  },', '}', 'return ChaosHeadCentres']
    return '\n'.join(lines) + '\n', len(rows)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('dat')
    ap.add_argument('spr')
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--out-heads', default=OUT_HEADS)
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args(argv)
    text, nb, nw = build(a.dat, a.spr)
    htext, nh = build_heads(a.dat, a.spr)
    if a.check:
        bad = 0
        for path, want in ((a.out, text), (a.out_heads, htext)):
            have = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
            if have != want:
                print('%s is not what the pair gives: run %s' % (path, os.path.basename(__file__)))
                bad = 1
        if bad:
            return 1
        print('wing centres up to date (%d bodies, %d wings), head centres up to date (%d bodies)' % (nb, nw, nh))
        return 0
    for path, want in ((a.out, text), (a.out_heads, htext)):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(want)
    print('wrote %s (%d bodies, %d wings) and %s (%d bodies)' % (os.path.relpath(a.out, REPO), nb, nw, os.path.relpath(a.out_heads, REPO), nh))
    return 0


if __name__ == '__main__':
    sys.exit(main())
