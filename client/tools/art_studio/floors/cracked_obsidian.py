"""CRACKED OBSIDIAN: crimson-black volcanic glass broken into plates, each plate tilted a little, its top-left rim
catching the light and its bottom-right rim in shadow; hairline fractures inside some plates; a few cracks hold a dull
ember glow. Asked 2026-10-09: "dark-fantasy floors that fit our dark tiles: cracked obsidian".

    python floors/cracked_obsidian.py          # out/floors/cracked_obsidian/: block, 16 tiles, preview

One 256 px block (4x4 tiles of 64): the tile at map (x, y) is the window (x % 4, y % 4).
"""
import numpy as np

import _floorlib as fl
from _floorlib import hash01, tiles, tv

NAME = "cracked_obsidian"
P = 256
STONE = tv.ramp([(10, 6, 12), (24, 14, 22), (40, 24, 32), (58, 34, 42), (80, 48, 54), (112, 74, 74),
                 (150, 112, 104)], 9)                                       # cold violet shade -> warm rose light
CRACK = np.array((8, 4, 8))                                                  # the deepest tone of the glass itself
EMBER = tv.ramp([(52, 8, 6), (110, 22, 8), (176, 52, 14)], 3)


def block():
    V = fl.voronoi(P, 32, salt=11, jitter=0.85)                              # plates ~32 px
    F = fl.voronoi(P, 16, salt=23, jitter=0.9)                               # the hairline fractures
    pid = V["id"]
    base = hash01(pid, np.full_like(pid, 1))
    tx = (hash01(pid, np.full_like(pid, 2)) - 0.5) * 0.018                   # each plate tilted a little
    ty = (hash01(pid, np.full_like(pid, 3)) - 0.5) * 0.018
    rel = V["rel"]
    val = 0.30 + 0.20 * base + tx * rel[..., 0] + ty * rel[..., 1]
    val -= 0.05 * tiles.wrap_noise(P, 8, salt=4)                             # a soft cloud inside the glass
    # the rim of a plate: lit where its edge faces the top-left, dark where it faces the bottom-right
    facing = -(V["normal"] @ fl.LIGHT2)                                      # +1: edge on the light side
    rim = np.clip(1 - V["edge"] / 2.6, 0, 1)
    val += np.where(facing > 0, 0.42, 0.30) * facing * rim
    # a glassy streak: a narrow bright band across some plates, parallel to the light
    streak = (hash01(pid, np.full_like(pid, 5)) > 0.55) & (np.abs(rel[..., 0] - rel[..., 1] + 4) < 1.5) & (V["edge"] > 3)
    val = np.where(streak, val + 0.16, val)
    rgb, k = fl.stepped(np.clip(val, 0, 1), STONE, salt=9)
    rgb = rgb.astype(int)
    # hairline fractures on a third of the plates (one tone down, never at the plate's rim)
    frac = (F["edge"] < 0.55) & (hash01(pid, np.full_like(pid, 6)) > 0.62) & (V["edge"] > 3.5)
    rgb[frac] = STONE[np.clip(k[frac] - 2, 0, len(STONE) - 1)]
    # the crack between plates: the glass's darkest tone, 1-2 px
    crack = V["edge"] < 0.9
    rgb[crack] = CRACK
    # embers: a dull glow in the cracks of a few patches
    heat = tiles.wrap_noise(P, 32, salt=7) * 0.7 + tiles.wrap_noise(P, 8, salt=8) * 0.3
    glow = crack & (heat > 0.47)
    lvl = np.clip(((heat - 0.47) / 0.22 * 3).astype(int), 0, 2)
    rgb[glow] = EMBER[lvl[glow]]
    return fl.rgba(rgb)


if __name__ == "__main__":
    fl.save_floor(NAME, block())
