"""FLOORS: a floor is ONE periodic block of the world (256 px = 4x4 tiles of 64, or 512 = 8x8) cut into tiles; the
tile at map position (x, y) is the window of the block at (x % P, y % P). Every variant of a floor family cuts the
SAME block, so no two tiles ever show a seam.

    from tiles import wrap_blur, wrap_noise, cut, tiled, seam_score
    block = ...                                 # paint it in a floors/<name>.py script (numpy, RGBA uint8, P x P)
    tiles = cut(block, 64)                      # {(col, row): 64x64 RGBA}
    tiled(block, 3).save("out/floors/<name>/preview.png")   # 3x3 blocks side by side: look for seams and lines

Every filter goes with mode="wrap" (or an FFT), or the block stops tiling.
"""
import numpy as np
from PIL import Image
from scipy import ndimage

from tibia_view import hash01


def wrap_blur(a, sigma):
    return ndimage.gaussian_filter(a, sigma, mode="wrap")


def wrap_noise(P, cell, salt=0):
    """Smooth periodic noise in [-1, 1] on a P x P block (`cell` must divide P)."""
    n = P // cell
    yy, xx = np.mgrid[0:P, 0:P] / cell
    gy, gx = np.floor(yy).astype(int), np.floor(xx).astype(int)
    fy, fx = yy - gy, xx - gx
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)

    def h(y, x):
        return hash01(y % n, x % n, np.full_like(y, salt))
    top = h(gy, gx) * (1 - fx) + h(gy, gx + 1) * fx
    bot = h(gy + 1, gx) * (1 - fx) + h(gy + 1, gx + 1) * fx
    return (top * (1 - fy) + bot * fy) * 2 - 1


def cut(block, tile=64):
    P = block.shape[0]
    return {(c, r): np.ascontiguousarray(block[r * tile:(r + 1) * tile, c * tile:(c + 1) * tile])
            for r in range(P // tile) for c in range(P // tile)}


def tiled(block, reps=3):
    return Image.fromarray(np.tile(block, (reps, reps, 1)), "RGBA" if block.shape[2] == 4 else "RGB")


def seam_score(block):
    """The mean colour jump across the block's own wrap, against the mean jump inside it (1 or less = no seam)."""
    a = block[..., :3].astype(float)
    inner = np.abs(np.diff(a, axis=1)).mean() + np.abs(np.diff(a, axis=0)).mean()
    wrap = np.abs(a[:, 0] - a[:, -1]).mean() + np.abs(a[0] - a[-1]).mean()
    return wrap / max(inner, 1e-9)
