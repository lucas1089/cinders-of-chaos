"""Read a stock outfit of a 10.98 pair into numpy frames (a size and perspective ruler only: no pixels are copied).

frames(dat, spr, lookType) -> {(group, phase, direction, addon, mount, layer): 64x64 RGBA (w*32 x h*32)}
"""
import os
import sys

import numpy as np

SPRITES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sprites")
sys.path.insert(0, SPRITES)
from datspr import Dat, Spr, sprite_index  # noqa: E402
from import_outfits import parse_body  # noqa: E402


def load(pair_dir):
    return Dat(os.path.join(pair_dir, "Tibia.dat")), Spr(os.path.join(pair_dir, "Tibia.spr"))


def frames(dat, spr, look, idle_only=False):
    t = dat.outfit(look)
    out = {}
    for gi, g in enumerate(parse_body(dat, t)):
        if idle_only and gi > 0:
            break
        W, H = g.w * 32, g.h * 32
        for ph in range(1 if idle_only else g.phases):
            for d in range(g.px):
                for a in range(g.py):
                    for z in range(g.pz):
                        for layer in range(g.layers):
                            c = np.zeros((H, W, 4), np.uint8)
                            for hh in range(g.h):
                                for ww in range(g.w):
                                    sp = spr.sprite(g.sprites[sprite_index(g, d, a, z, layer, ph, ww, hh)])
                                    if sp is not None:
                                        y0, x0 = (g.h - 1 - hh) * 32, (g.w - 1 - ww) * 32
                                        m = sp[..., 3] > 0
                                        c[y0:y0 + 32, x0:x0 + 32][m] = sp[m]
                            out[(gi, ph, d, a, z, layer)] = c
    return out
