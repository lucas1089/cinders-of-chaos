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
                no legs below, a weapon stays in); x is the alpha-weighted mean of that band.
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

REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_wingfit', 'wing_centres.lua')
PACK33 = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_pack33_cosmetics.lua')
# the wings looks of wings.xml: base 1-15, Chaos 16-29 (fix_pair_warnings.py WINGS_LOOKS), then the pair 33 wings
BASE_WINGS = '937-941,1177-1186,1486,2140-2142,2187,2225-2233'
TORSO_LO, TORSO_HI = 0.30, 0.70
SHADOW_ALPHA = 200      # a baked shadow pixel: alpha under this and luminance under SHADOW_LUM
SHADOW_LUM = 150
GAP_MIN = 2             # empty columns that split the wings into a left and a right mass
MASS_MIN = 0.25         # each mass holds at least this share of the art, else one mass
DIRS = 4


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
    """x (canvas px) of the torso of a body: the alpha-weighted mean of the rows from TORSO_LO to TORSO_HI of the opaque
    box; None when nothing is visible. alpha: 2-D array."""
    a = np.asarray(alpha, np.float64)
    ys, xs = np.nonzero(a > 0)
    if not len(ys):
        return None
    top, bot = ys.min(), ys.max() + 1
    r0 = top + TORSO_LO * (bot - top)
    r1 = top + TORSO_HI * (bot - top)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    wt = a * ((yy >= r0) & (yy < r1))
    n = wt.sum()
    if n <= 0:
        return None
    return float((wt * xx).sum() / n)


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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('dat')
    ap.add_argument('spr')
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args(argv)
    text, nb, nw = build(a.dat, a.spr)
    if a.check:
        have = open(a.out, encoding='utf-8').read() if os.path.exists(a.out) else ''
        if have != text:
            print('%s is not what the pair gives: run %s' % (a.out, os.path.basename(__file__)))
            return 1
        print('wing centres up to date (%d bodies, %d wings)' % (nb, nw))
        return 0
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote %s (%d bodies, %d wings)' % (os.path.relpath(a.out, REPO), nb, nw))
    return 0


if __name__ == '__main__':
    sys.exit(main())
