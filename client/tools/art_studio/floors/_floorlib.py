"""Shared pieces of the floor scripts: periodic cells on the torus, stepped shading to a ramp, and the files.

Every function works on ONE periodic block (P x P): distances are taken around the wrap, so the block tiles with no
seam. The light comes from the top-left (screen), as everywhere in the studio.
"""
import os
import sys

import numpy as np
from PIL import Image

STUDIO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(STUDIO, "kit"))
import tiles  # noqa: E402
import tibia_view as tv  # noqa: E402
from tibia_view import hash01  # noqa: E402

LIGHT2 = np.array((-1.0, -1.0)) / np.sqrt(2.0)     # toward the light, screen (x, y)


def out_dir(name):
    path = os.path.join(STUDIO, "out", "floors", name)
    os.makedirs(path, exist_ok=True)
    return path


def jittered_points(P, cell, salt, jitter=0.8):
    """One point per cell of a periodic grid: arrays px, py of shape (n, n) (world pixels, inside the block)."""
    n = P // cell
    gy, gx = np.mgrid[0:n, 0:n]
    jx = 0.5 + (hash01(gy, gx, np.full_like(gy, salt)) - 0.5) * jitter
    jy = 0.5 + (hash01(gy, gx, np.full_like(gy, salt + 1)) - 0.5) * jitter
    return (gx + jx) * cell, (gy + jy) * cell


def voronoi(P, cell, salt, jitter=0.8, reach=2):
    """Periodic Voronoi: the id of the nearest point, its offset (pixel - point), the distance to the cell edge and the
    unit normal of that edge (from this cell toward the neighbour)."""
    n = P // cell
    px, py = jittered_points(P, cell, salt, jitter)
    yy, xx = np.mgrid[0:P, 0:P] + 0.5
    gy, gx = (yy // cell).astype(int), (xx // cell).astype(int)
    best = [np.full((P, P), np.inf), np.full((P, P), np.inf)]
    pos = [np.zeros((P, P, 2)), np.zeros((P, P, 2))]
    ids = [np.zeros((P, P), int), np.zeros((P, P), int)]
    for oy in range(-reach, reach + 1):
        for ox in range(-reach, reach + 1):
            cy, cx = gy + oy, gx + ox
            wy, wx = cy % n, cx % n
            qx = px[wy, wx] + (cx - wx) * cell
            qy = py[wy, wx] + (cy - wy) * cell
            d = np.hypot(xx - qx, yy - qy)
            q = np.stack([qx, qy], -1)
            k = wy * n + wx
            first = d < best[0]
            second = ~first & (d < best[1])
            best[1] = np.where(first, best[0], np.where(second, d, best[1]))
            pos[1] = np.where(first[..., None], pos[0], np.where(second[..., None], q, pos[1]))
            ids[1] = np.where(first, ids[0], np.where(second, k, ids[1]))
            best[0] = np.where(first, d, best[0])
            pos[0] = np.where(first[..., None], q, pos[0])
            ids[0] = np.where(first, k, ids[0])
    sep = pos[1] - pos[0]
    L = np.maximum(np.linalg.norm(sep, axis=-1), 1e-9)
    edge = (best[1] ** 2 - best[0] ** 2) / (2 * L)
    rel = np.stack([xx, yy], -1) - pos[0]
    return dict(id=ids[0], id2=ids[1], rel=rel, edge=edge, normal=sep / L[..., None], n=n)


def stepped(value, palette, salt=5, grain=0.35):
    """A value 0..1 per pixel to the discrete tones of `palette` (a (k, 3) ramp), with a small hashed grain so the steps
    do not band into lines."""
    P = value.shape[0]
    yy, xx = np.mgrid[0:P, 0:P]
    g = (hash01(yy, xx, np.full_like(yy, salt)) - 0.5) * grain
    k = np.clip(np.round(value * (len(palette) - 1) + g), 0, len(palette) - 1).astype(int)
    return palette[k], k


def rgba(rgb):
    a = np.full(rgb.shape[:2] + (1,), 255, np.uint8)
    return np.concatenate([np.clip(rgb, 0, 255).astype(np.uint8), a], -1)


def save_floor(name, block, tile=64):
    """block.png, tile_<col>_<row>.png, preview.png (3x3 blocks, real size) and the seam number."""
    folder = out_dir(name)
    Image.fromarray(block, "RGBA").save(os.path.join(folder, "block.png"))
    for (c, r), t in tiles.cut(block, tile).items():
        Image.fromarray(t, "RGBA").save(os.path.join(folder, "tile_%d_%d.png" % (c, r)))
    tiles.tiled(block, 3).save(os.path.join(folder, "preview.png"))
    print("%s: seam %.2f  -> %s" % (name, tiles.seam_score(block), folder))
    return folder
