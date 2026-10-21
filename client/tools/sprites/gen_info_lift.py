#!/usr/bin/env python3
"""How far each look lifts the name and bars of a player or NPC wearing it (client/MANIFEST.md "Name over tall looks").

usage: python3 -I client/tools/sprites/gen_info_lift.py Tibia.dat Tibia.spr [--out PATH] [--check]

The engine puts a creature's health bar 2 px above the top of its 32x32 cell, moved up by the look's displacement,
and the name 12 px above the bar (mapview.cpp drawMapForeground, Creature::drawInformation). The place comes from the
dat alone and never from the picture. A stock look's head is at the top of that cell, so its name is over its head.
Many of our imported looks are 64x64 and draw the head higher in their canvas: the class looks with no displacement
(the Necromancer 2183 / 2184, the Lich 2173 / 2174, the old Necromancer 2064: displacement 0, the figure drawn high in
its canvas) and the tall hats, helmets and crowns. On those the name and the bar fell across the face or the chest (owner
report 2026-10-22: "alguns outfits ficam com o nome no meio dele, nao em cima", a Necromancer in the witch hat).

This tool measures each creature thing of the pair: per direction (phase 0, base layer, every addon pattern, as a
character wears its class look) the top row of the solid body (gen_outfit_anchors.solid with r = 2 and its biggest
part: a raised staff, a spear or a thin plume does not count), in the cell coordinates the bar uses. gap = how far
that top is above the bar's top line; the look's gap is the largest of its directions, so the name does not jump
when the creature turns. The stock player looks (128-160) reach up to ALLOW px over the line (median 2); a look
whose gap is over that gets a lift of gap - ALLOW (from MIN_LIFT on), so its head shows as much over the line as a
stock look's does.

  [look] = lift    sprite pixels at 1x; looks with no lift are left out

Output (default): client/overlay/modules/client_chaos_infolift/info_lifts.lua (`ChaosInfoLifts`). The module hands
each entry to Creature.setInformationLift (base patch 0111); the engine adds it to a player's or an NPC's name and
bar anchor before the map's stretch. Monsters keep the classic place. Deterministic: the same pair writes the same
file; --check exits 1 when the file differs from what the pair gives. Regenerate it with every new pair (the dat md5
is written in the file).
"""
import argparse
import hashlib
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from datspr import Dat, Spr, sprite_index  # noqa: E402
from gen_outfit_anchors import ALPHA, largest_part, solid  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_infolift', 'info_lifts.lua')
ALLOW = 4      # px a stock player look's body reaches over the bar's top line (128-160: median 2, 25 of 32 <= 4)
MAX_LIFT = 96  # the engine's cap (Creature::setInformationLift)
MIN_LIFT = 3   # a smaller lift is left out (a stock look a pixel or two taller keeps its place)


def signed(v):
    """the dat stores the displacement as two u16: a negative one reads as 65536 - n"""
    return v - 65536 if v > 32767 else v


def displacement(t):
    d = t.flags.get('displacement')
    return (signed(d[0]), signed(d[1])) if isinstance(d, tuple) else (0, 0)


def direction_alpha(t, spr, x):
    """alpha of direction x (pattern x), phase 0, base layer, every addon pattern; canvas = the thing's w x h tiles"""
    W, H = t.w * 32, t.h * 32
    alpha = np.zeros((H, W), np.uint8)
    for yy in range(max(1, t.py)):
        for hh in range(t.h):
            for ww in range(t.w):
                a = spr.sprite(t.sprites[sprite_index(t, x, yy, 0, 0, 0, ww, hh)])
                if a is not None:
                    oy, ox = (t.h - 1 - hh) * 32, (t.w - 1 - ww) * 32
                    np.maximum(alpha[oy:oy + 32, ox:ox + 32], a[..., 3], out=alpha[oy:oy + 32, ox:ox + 32])
    return alpha


def body_top(alpha):
    """the top row of the solid body in a canvas (None when nothing is visible)"""
    mask = alpha >= ALPHA
    if not mask.any():
        return None
    body = largest_part(solid(mask, 2))
    return int(np.nonzero(body.any(axis=1))[0][0])


def gap_of(top_row, h_tiles, dy, negative=False):
    """how far a body whose top is canvas row top_row reaches over the bar's top line, in px. The canvas's bottom
    right cell is the creature's own cell and the client draws the thing up by dy; the bar goes up by dy too, but by
    nothing for a look with a negative displacement on either axis (mapview.cpp, usesNegativeDisplacement)"""
    top = top_row - (h_tiles - 1) * 32 - dy          # relative to the top of the creature's tile
    bar = -(0 if negative else dy) - 2
    return bar - top


def lift_of(gaps, allow=ALLOW):
    """the lift for a look's per-direction gaps"""
    if not gaps:
        return 0
    lift = min(MAX_LIFT, max(gaps) - allow)
    return lift if lift >= MIN_LIFT else 0


def thing_lift(t, spr):
    dx, dy = displacement(t)
    gaps = []
    for x in range(min(4, t.px)):
        row = body_top(direction_alpha(t, spr, x))
        if row is not None:
            gaps.append(gap_of(row, t.h, dy, dx < 0 or dy < 0))
    return lift_of(gaps)


def build(dat_path, spr_path):
    dat = Dat(dat_path)
    spr = Spr(spr_path)
    md5 = hashlib.md5(open(dat_path, 'rb').read()).hexdigest()
    rows = []
    for i, t in enumerate(dat.outfits, 1):
        if not t.sprites:
            continue
        lift = thing_lift(t, spr)
        if lift > 0:
            rows.append('[%d]=%d' % (i, lift))
    lines = ['-- Generated by client/tools/sprites/gen_info_lift.py from the pair with dat md5 %s.' % md5,
             '-- Do not edit: regenerate with the tool for every new pair. Per look type: how many sprite pixels (1x)',
             "-- the name and bars of a player or an NPC wearing it go up (base patch 0111); other looks: 0.",
             'ChaosInfoLifts = {', '  dat = "%s",' % md5]
    for k in range(0, len(rows), 12):
        lines.append('  ' + ','.join(rows[k:k + 12]) + ',')
    lines.append('}')
    lines.append('return ChaosInfoLifts')
    return '\n'.join(lines) + '\n', len(rows)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('dat')
    ap.add_argument('spr')
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args(argv)
    text, n = build(a.dat, a.spr)
    if a.check:
        have = open(a.out, encoding='utf-8').read() if os.path.exists(a.out) else ''
        if have != text:
            print('%s is not what the pair gives: run %s' % (a.out, os.path.basename(__file__)))
            return 1
        print('information lifts up to date (%d looks)' % n)
        return 0
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote %s (%d looks)' % (os.path.relpath(a.out, REPO), n))
    return 0


if __name__ == '__main__':
    sys.exit(main())
