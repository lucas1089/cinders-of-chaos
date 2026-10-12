"""BLOOD MOSS onto ASH STONE: the border set (the passage from a blood-moss tile into an ash-stone tile).

    python floors/blood_moss_border.py     # out/floors/blood_moss_border/: one sheet per piece + scene.png

A border tile is an ASH STONE tile (the same world pixels as floors/ash_stone.py) on which the moss of the
neighbouring tile spills in ~7 px: the cushions of floors/blood_moss.py at the SAME world pixels, taken WHOLE (a cushion
goes in when its centre is within the depth of the edge), and their 1 px shadow down-right on the stone.

Pieces, named by WHERE THE MOSS IS: edge_n/e/s/w (moss on that side), corner_nw/ne/sw/se (moss only on the diagonal
neighbour), inner_nw/ne/sw/se (moss on two sides: edge + edge, cushion for cushion the same). Each piece is a 256 px
sheet: the 4x4 world positions, like the floor (tile (x, y) of the map uses window (x % 4, y % 4)). The shape of the
edge changes with the tile: (x + 3y) % 4 -> straight, set back, advancing with loose tufts, wavy; it changes only away
from the corners, so neighbours always meet. `*_overlay.png` keeps only the moss (transparent elsewhere) for a client
that draws borders over the ground.
"""
import os

import numpy as np
from PIL import Image

import _floorlib as fl
from _floorlib import hash01
import ash_stone
import blood_moss

NAME = "blood_moss_border"
P, T = 256, 64
DEPTH = 7.0
EDGES = ("n", "e", "s", "w")
PIECES = ["edge_" + e for e in EDGES] + ["corner_" + c for c in ("nw", "ne", "sw", "se")] + \
    ["inner_" + c for c in ("nw", "ne", "sw", "se")]

STONE = ash_stone.block()[..., :3].astype(int)
MOSS_RGB, MOSS_ON, OWNER, REL = blood_moss.layers()


def depth(shape, t, tuft):
    """How far in the moss reaches at position t (0..64) along the edge; 7 at the corners whatever the shape."""
    win = np.sin(np.pi * np.clip(t, 0, T) / T) ** 2
    d = [DEPTH + 0 * t, DEPTH - 3.5 * win, DEPTH + 4.5 * win + 8 * win * tuft, DEPTH + 3.5 * np.sin(4 * np.pi * t / T) * win]
    return d[shape]


def selected(tx, ty, sides):
    """The moss pixels of the window (-1 .. 64) of world tile (tx, ty) for these sides; world-wrapped into the block."""
    yy, xx = np.mgrid[-1:T, -1:T]
    wy, wx = (ty * T + yy) % P, (tx * T + xx) % P
    on = MOSS_ON[wy, wx]
    cx = xx + 0.5 - REL[wy, wx, 0]                       # the cushion's centre, in the tile's own pixels
    cy = yy + 0.5 - REL[wy, wx, 1]
    shape = (tx + 3 * ty) % 4
    tuft = (hash01(OWNER[wy, wx], np.full_like(wy, 61)) > 0.6).astype(float)   # loose tufts, whole cushions
    sel = np.zeros(on.shape, bool)
    inward = {"n": (cy, cx), "s": (T - cy, cx), "w": (cx, cy), "e": (T - cx, cy)}
    for s in sides:
        if s in inward:
            d_in, t = inward[s]
            sel |= d_in < depth(shape, t, tuft)
        else:                                            # a diagonal: radial from that corner
            ox = 0 if "w" in s else T
            oy = 0 if "n" in s else T
            sel |= np.hypot(cx - ox, cy - oy) < DEPTH + (1.5 if shape == 2 else 0)
    return on & sel, wy, wx


def border_tile(tx, ty, sides):
    """The full ash-stone tile with the moss spilling in from `sides` (opaque), and the moss alone (overlay)."""
    sel, wy, wx = selected(tx, ty, sides)
    rgb = np.where(sel[..., None], MOSS_RGB[wy, wx], STONE[wy, wx])
    shade = ~sel[1:, 1:] & sel[:-1, :-1]                 # the shadow down-right onto the stone
    out = rgb[1:, 1:].copy()
    out[shade] = (out[shade] * 0.62).astype(int)
    full = fl.rgba(out)
    ov = full.copy()
    ov[..., 3] = np.where(sel[1:, 1:], 255, 0)
    ov[~sel[1:, 1:], :3] = 0
    return full, ov


def sides_of(piece):
    kind, where = piece.split("_")
    return list(where) if kind == "inner" else [where]


def sheets(folder):
    for piece in PIECES:
        full = np.zeros((P, P, 4), np.uint8)
        ov = np.zeros((P, P, 4), np.uint8)
        for ty in range(4):
            for tx in range(4):
                f, o = border_tile(tx, ty, sides_of(piece))
                full[ty * T:(ty + 1) * T, tx * T:(tx + 1) * T] = f
                ov[ty * T:(ty + 1) * T, tx * T:(tx + 1) * T] = o
        Image.fromarray(full, "RGBA").save(os.path.join(folder, piece + ".png"))
        Image.fromarray(ov, "RGBA").save(os.path.join(folder, piece + "_overlay.png"))


def scene(folder, w=10, h=7):
    """A small map: a blob of blood moss inside ash stone, each stone tile picking its piece from its neighbours."""
    moss = np.zeros((h, w), bool)
    moss[1:5, 2:6] = True
    moss[2:6, 4:8] = True
    moss[1, 2] = False
    moss[5, 7] = False
    img = np.zeros((h * T, w * T, 4), np.uint8)
    for ty in range(h):
        for tx in range(w):
            if moss[ty, tx]:
                wy, wx = (ty * T + np.mgrid[0:T, 0:T][0]) % P, (tx * T + np.mgrid[0:T, 0:T][1]) % P
                tile = fl.rgba(MOSS_RGB[wy, wx])
            else:
                m = lambda dy, dx: 0 <= ty + dy < h and 0 <= tx + dx < w and moss[ty + dy, tx + dx]   # noqa: E731
                sides = [s for s, (dy, dx) in zip(EDGES, ((-1, 0), (0, 1), (1, 0), (0, -1))) if m(dy, dx)]
                for c, (dy, dx) in (("nw", (-1, -1)), ("ne", (-1, 1)), ("sw", (1, -1)), ("se", (1, 1))):
                    if m(dy, dx) and c[0] not in sides and c[1] not in sides:
                        sides.append(c)
                tile = border_tile(tx, ty, sides)[0]
            img[ty * T:(ty + 1) * T, tx * T:(tx + 1) * T] = tile
    im = Image.fromarray(img, "RGBA")
    im.save(os.path.join(folder, "scene.png"))
    print(os.path.join(folder, "scene.png"))


if __name__ == "__main__":
    folder = fl.out_dir(NAME)
    sheets(folder)
    scene(folder)
