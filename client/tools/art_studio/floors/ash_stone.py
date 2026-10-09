"""ASH STONE: cold grey-blue flagstones in uneven courses, their top-left edges lit and bottom-right edges dark, with
drifts of pale ash settled over them and in the joints, and a rare ember fleck in the ash. Asked 2026-10-09:
"dark-fantasy floors that fit our dark tiles: ash-covered stone".

    python floors/ash_stone.py          # out/floors/ash_stone/: block, 16 tiles, preview

One 256 px block (4x4 tiles of 64): the tile at map (x, y) is the window (x % 4, y % 4).
"""
import numpy as np

import _floorlib as fl
from _floorlib import hash01, tiles, tv

NAME = "ash_stone"
P = 256
STONE = tv.ramp([(12, 13, 20), (26, 28, 36), (42, 44, 52), (60, 61, 68), (82, 80, 84), (110, 104, 102)], 8)
JOINT = np.array((9, 9, 14))                                                 # the stone's darkest, cold
ASH = tv.ramp([(46, 43, 44), (64, 59, 57), (84, 78, 73), (108, 101, 92), (132, 124, 110)], 6)
EMBER = np.array((168, 52, 16))


def courses(salt=31):
    """Heights of the courses of stones, summing exactly to P."""
    hs, k = [], 0
    while sum(hs) < P:
        hs.append(26 + int(hash01(np.array([k]), np.array([salt]))[0] * 15))
        k += 1
    over = sum(hs) - P
    hs[-1] -= over
    if hs[-1] < 22:
        last = hs.pop()
        hs[-1] += last
    return hs


def cuts(row, salt=37):
    """Where the stones of a course begin (x), around the wrap: widths 34..64, the last one closes the circle."""
    x0 = int(hash01(np.array([row]), np.array([salt]))[0] * P)
    xs, x, k = [], 0, 0
    while x < P:
        xs.append(x)
        x += 34 + int(hash01(np.array([row]), np.array([k]), np.array([salt + 1]))[0] * 31)
        k += 1
    if P - xs[-1] < 28:
        xs.pop()
    return [(v + x0) % P for v in xs]


def slabs():
    """Per pixel: the stone id, x and y inside the stone, its width and height."""
    sid = np.zeros((P, P), int)
    lx, ly, W, H = (np.zeros((P, P), int) for _ in range(4))
    y = 0
    for r, h in enumerate(courses()):
        starts = sorted(cuts(r))
        for i, s in enumerate(starts):
            e = starts[(i + 1) % len(starts)] + (P if i + 1 == len(starts) else 0)
            xs = np.arange(s, e) % P
            sid[y:y + h, xs] = r * 64 + i
            lx[y:y + h, xs] = np.arange(e - s)[None, :]
            ly[y:y + h, xs] = np.arange(h)[:, None]
            W[y:y + h, xs] = e - s
            H[y:y + h, xs] = h
        y += h
    return sid, lx, ly, W, H


def block():
    sid, lx, ly, W, H = slabs()
    val = 0.42 + 0.22 * (hash01(sid, np.full_like(sid, 1)) - 0.5)
    val += 0.06 * tiles.wrap_noise(P, 8, salt=3) + 0.04 * tiles.wrap_noise(P, 4, salt=5)
    val = val + 0.30 * ((lx == 1) | (ly == 1)) - 0.26 * ((lx == W - 1) | (ly == H - 1))
    rgb, k = fl.stepped(np.clip(val, 0, 1), STONE, salt=6)
    rgb = rgb.astype(int)
    joint = (lx == 0) | (ly == 0)
    cx = np.minimum(lx, W - lx)
    cy = np.minimum(ly, H - ly)
    corner = (cx + cy) <= 2 + (hash01(sid, np.full_like(sid, 2)) > 0.6)       # the corners worn round
    rgb[joint | corner] = JOINT
    # the ash: drifts over the stones, and in the joints a little further out
    cover = tiles.wrap_noise(P, 64, salt=11) * 0.62 + tiles.wrap_noise(P, 16, salt=12) * 0.33 \
        + tiles.wrap_noise(P, 4, salt=13) * 0.05
    yy, xx = np.mgrid[0:P, 0:P]
    speck = hash01(yy, xx, np.full_like(yy, 14))
    ash = (cover > 0.02) | (joint & (cover > -0.12))
    aval = np.clip(0.30 + (cover - 0.02) * 1.5 + 0.08 * tiles.wrap_noise(P, 4, salt=15), 0, 1)
    aval = np.where(joint, aval * 0.5, aval)                                  # ash in a joint sits in shadow
    acol, ak = fl.stepped(aval, ASH, salt=16)
    rgb[ash] = acol[ash]
    # a drift is a low relief: its top-left rim lit, a 1 px shadow cast down-right onto the stone (wrapping with
    # the block, which is the world)
    upleft = np.roll(np.roll(ash, 1, 0), 1, 1)
    lit = ash & ~upleft & ~joint
    rgb[lit] = ASH[np.clip(ak[lit] + 1, 0, len(ASH) - 1)]
    shade = ~ash & upleft & ~joint
    rgb[shade] = (rgb[shade] * 0.7).astype(int)
    rgb[ash & (cover > 0.2) & (speck > 0.9975)] = EMBER
    # the wrap must not fall on a joint (the whole block moves: it still tiles)
    rgb = np.roll(np.roll(rgb, 9, 0), 5, 1)
    return fl.rgba(rgb)


if __name__ == "__main__":
    fl.save_floor(NAME, block())
