"""BLOOD MOSS: a carpet of dark-crimson moss cushions over black soil, each cushion a little dome lit from the
top-left (cold wine shade, warm red light), a 1 px shadow cast down-right onto the soil, bare soil where the carpet
thins, and a rare bright drop on a cushion. Asked 2026-10-09: "dark-fantasy floors that fit our dark tiles:
blood-moss".

    python floors/blood_moss.py          # out/floors/blood_moss/: block, 16 tiles, preview

One 256 px block (4x4 tiles of 64): the tile at map (x, y) is the window (x % 4, y % 4). `layers()` also gives each
pixel's cushion and its centre, so a border can take cushions WHOLE (floors/blood_moss_border.py).
"""
import numpy as np

import _floorlib as fl
from _floorlib import hash01, tiles, tv

NAME = "blood_moss"
P = 256
CELL = 8
MOSS = tv.ramp([(13, 6, 12), (28, 10, 18), (46, 14, 22), (68, 20, 26), (94, 30, 30), (124, 46, 38), (152, 70, 50)], 8)
SOIL = tv.ramp([(10, 8, 9), (20, 15, 15), (31, 24, 22), (42, 33, 29)], 5)
DROP = np.array((222, 104, 84))
L3 = np.array((-0.55, -0.62, 0.56))


def layers():
    """rgb (P, P, 3), moss (cushion pixels), owner (cushion id, -1 on soil), rel (pixel - its cushion's centre)."""
    n = P // CELL
    px, py = fl.jittered_points(P, CELL, salt=41, jitter=0.9)
    gy, gx = np.mgrid[0:n, 0:n]
    cover = tiles.wrap_noise(P, 32, salt=43) * 0.65 + tiles.wrap_noise(P, 8, salt=44) * 0.35
    cpt = cover[py.astype(int) % P, px.astype(int) % P]
    near_edge = np.minimum(np.minimum(px % 64, 64 - px % 64), np.minimum(py % 64, 64 - py % 64)) < 9
    alive = (cpt > -0.52) | near_edge          # bare soil only inside a tile: at its edges the carpet is whole, so a
                                               # border onto another floor is made of cushions, never a soil line
    rad = 4.2 + 2.2 * hash01(gy, gx, np.full_like(gy, 45)) + 1.2 * np.clip(cpt, 0, 1)
    yy, xx = np.mgrid[0:P, 0:P] + 0.5
    cy, cx = (yy // CELL).astype(int), (xx // CELL).astype(int)
    top = np.full((P, P), -np.inf)
    owner = np.full((P, P), -1)
    rel = np.zeros((P, P, 2))
    rr = np.ones((P, P))
    for oy in (-2, -1, 0, 1, 2):
        for ox in (-2, -1, 0, 1, 2):
            ky, kx = cy + oy, cx + ox
            wy, wx = ky % n, kx % n
            qx = px[wy, wx] + (kx - wx) * CELL
            qy = py[wy, wx] + (ky - wy) * CELL
            r = rad[wy, wx]
            dx, dy = xx - qx, yy - qy
            h = r * r - dx * dx - dy * dy + 0.8 * r                          # bigger cushions sit higher
            m = alive[wy, wx] & (dx * dx + dy * dy <= r * r) & (h > top)
            top = np.where(m, h, top)
            owner = np.where(m, wy * n + wx, owner)
            rel = np.where(m[..., None], np.stack([dx, dy], -1), rel)
            rr = np.where(m, r, rr)
    moss = owner >= 0
    # the cushion's light: a dome
    nx, ny = rel[..., 0] / rr, rel[..., 1] / rr
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    lam = np.clip(nx * L3[0] + ny * L3[1] + nz * L3[2], 0, 1)
    tone = hash01(owner, np.full_like(owner, 46))
    fibre = hash01((yy // 1).astype(int), (xx // 1).astype(int), np.full(yy.shape, 52, int)) - 0.5
    tuft = tiles.wrap_noise(P, 4, salt=53)
    val = 0.06 + 0.66 * lam + 0.12 * (tone - 0.5) + 0.20 * fibre + 0.10 * tuft
    mcol, mk = fl.stepped(np.clip(val, 0, 1), MOSS, salt=47, grain=0.3)
    # the soil
    sval = 0.45 + 0.35 * tiles.wrap_noise(P, 8, salt=48) + 0.15 * tiles.wrap_noise(P, 4, salt=49)
    scol, _ = fl.stepped(np.clip(sval, 0, 1), SOIL, salt=50)
    rgb = np.where(moss[..., None], mcol, scol).astype(int)
    # where one cushion meets another on its lower-right side: one tone down (they read as separate cushions)
    for dy, dx in ((1, 0), (0, 1)):
        nb = np.roll(np.roll(owner, -dy, 0), -dx, 1)
        seam = moss & (nb != owner) & ((rel[..., 0] > 0) | (rel[..., 1] > 0))
        rgb[seam] = MOSS[np.clip(mk[seam] - 1, 0, len(MOSS) - 1)]
    # the shadow down-right on the soil
    upleft = np.roll(np.roll(moss, 1, 0), 1, 1)
    sh = ~moss & upleft
    rgb[sh] = SOIL[0]
    # a rare bright drop on the lit side of a cushion
    drop = moss & (hash01(owner, np.full_like(owner, 51)) > 0.9) & (np.abs(rel[..., 0] + 2) < 0.5) \
        & (np.abs(rel[..., 1] + 2) < 0.5)
    rgb[drop] = DROP
    return rgb, moss, owner, rel


def block():
    return fl.rgba(layers()[0])


if __name__ == "__main__":
    fl.save_floor(NAME, block())
