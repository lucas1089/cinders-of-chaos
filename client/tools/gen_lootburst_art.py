#!/usr/bin/env python3
"""Art of the loot burst animation (O677; client/MANIFEST.md "Loot burst (O677)", module game_lootburst).

Owner 2026-11-19 (pt-BR): "Faça uma animação legal no Loot Explosion, por favor, deixe mais bonito". The server sends the flights of a
kill's loot (opcode 230 `explode`) and the client draws them: a flash on the death tile, every item flying in an arc with a soft shadow
on the ground, a trail of glows behind the rarer ones, a dust puff and (for Legendary, Divine, set and unique items) a ring where it
lands. These are the pictures of those parts. Like the loot beams (gen_lootbeam_art.py) they are drawn from soft light fields (additive
energy turned into straight alpha), so nothing has a hard edge; everything is drawn here from shapes with a fixed seed (no reference
art, nothing third-party). The light parts are white: the module tints them with the colour of the item's beam group
(UIWidget:setImageColor), so one strip serves every group.

images/ in game_lootburst:
  flash.png    8 frames of 64 x 64 (one row): the burst on the death tile: a hot core, a soft ring shooting out, eight short streaks of light
  ring.png     6 frames of 64 x 40: a ring lying on the ground (the game's oblique view, 2:1.2) that grows and fades; foot at (32, 20)
  dust.png     6 frames of 48 x 48: a puff of dust (warm grey, not tinted): seven soft clouds drifting out and up
  shadow.png   1 frame of 32 x 20: the soft dark ellipse under a flying item
  glow.png     1 frame of 24 x 24: a soft round glow, a trail dot

python3 -I client/tools/gen_lootburst_art.py                 # write the pictures into the module (overlay/modules/game_lootburst/images)
python3 -I client/tools/gen_lootburst_art.py --check         # the committed pictures are what the generator draws (exit 1 if not)
python3 -I client/tools/gen_lootburst_art.py --out DIR       # write them somewhere else

numpy and Pillow are needed (CI runs the check with the pinned versions of the fx venv, because float maths differs a little between
versions). The check compares the decoded pixels, not the file bytes, with a tolerance of TOL per channel.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.join(os.path.dirname(HERE), 'overlay', 'modules', 'game_lootburst')
OUT = os.path.join(MODULE, 'images')

# name -> (frame width, frame height, frames); lootburstlogic.lua ART keeps the same numbers (lootburst_test.lua reads the files)
SHEETS = {
    'flash': (64, 64, 8),
    'ring': (64, 40, 6),
    'dust': (48, 48, 6),
    'shadow': (32, 20, 1),
    'glow': (24, 24, 1),
}
SEED = 20261119
TOL = 4

WHITE = np.array([1.0, 1.0, 1.0], np.float32)
DUST = np.array([0.80, 0.72, 0.60], np.float32)


# ---------------------------------------------------------------- the light kit (float energy, RGB)
def grid(w, h):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    return x + 0.5, y + 0.5


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def blob(X, Y, cx, cy, rad):
    """a soft round light: 1 in the middle, 0 at rad and beyond, no hard edge"""
    d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / max(rad, 1e-3)
    return (1 - smooth(0.0, 1.0, d)) ** 1.4


def ellipse_ring(X, Y, cx, cy, rx, ry, width, glow=2.6):
    """a thin soft ring on an ellipse: a gaussian across the line, a wider fainter halo round it"""
    d = np.sqrt(((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2)
    dist = np.abs(d - 1.0) * (rx + ry) * 0.5
    return np.exp(-(dist / width) ** 2) + 0.28 * np.exp(-(dist / (width * glow)) ** 2)


def streak(X, Y, cx, cy, ang, r0, r1, width):
    """a soft streak of light along a ray from r0 to r1 pixels from the centre"""
    dx, dy = X - cx, Y - cy
    along = dx * math.cos(ang) + dy * math.sin(ang)
    across = -dx * math.sin(ang) + dy * math.cos(ang)
    body = np.exp(-(across / width) ** 2)
    span = smooth(r0 - 2, r0 + 2, along) * (1 - smooth(r1 - 5, r1 + 1, along))
    return body * span


def finish(E, color, gain=1.0):
    """energy -> straight RGBA (uint8): the alpha saturates softly (no hard edge, nothing above 1), the colour is the part's"""
    m = E * gain
    alpha = 1 - np.exp(-1.7 * m)
    alpha[alpha < 0.012] = 0.0
    out = np.zeros(m.shape + (4,), np.float32)
    out[..., :3] = color
    out[..., 3] = alpha
    return np.clip(np.round(out * 255), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- the pictures
def flash_frame(k, n):
    """the burst on the death tile: frame 0 is the hot core, then a ring shoots out and the streaks reach and fade"""
    w, h, _ = SHEETS['flash']
    X, Y = grid(w, h)
    cx, cy = w / 2.0, h / 2.0
    u = (k + 0.5) / n
    fade = (1 - u) ** 1.35
    E = np.zeros((h, w), np.float32)
    E += blob(X, Y, cx, cy, 10 + 14 * u) * fade * 1.4
    E += blob(X, Y, cx, cy, 6 + 4 * u) * fade * 1.2
    rs = 6 + 16 * (1 - (1 - u) ** 2)
    E += ellipse_ring(X, Y, cx, cy, rs, rs, 1.4 + 0.8 * u) * (1 - u) ** 1.1 * 0.95
    # short streaks that leave the ring outwards (they never cross it, so the burst reads as light, not as a wheel)
    rng = np.random.RandomState(SEED + 7)
    for i in range(8):
        ang = (i + rng.uniform(-0.2, 0.2)) * math.pi / 4 + 0.2
        E += streak(X, Y, cx, cy, ang, rs + 1, rs + 4 + 3 * u + rng.uniform(0, 1.5), 1.1) * (1 - u) ** 1.3 * 0.7
    return finish(E, WHITE)


def ring_frame(k, n):
    """a ring on the ground: an ellipse 2 : 1.2 that grows from a small flash and fades"""
    w, h, _ = SHEETS['ring']
    X, Y = grid(w, h)
    cx, cy = w / 2.0, h / 2.0
    u = (k + 0.5) / n
    fade = (1 - u) ** 1.25
    rx = 5 + 19 * (1 - (1 - u) ** 2)
    ry = rx * 0.6
    E = ellipse_ring(X, Y, cx, cy, rx, ry, 1.4 + 0.6 * u) * fade * 1.15
    E += blob(X, Y, cx, cy, 7 + 4 * u) * fade * 0.5 * (1 - u)
    return finish(E, WHITE)


def dust_frame(k, n):
    """a puff of dust: seven soft clouds that drift out and up from the foot and thin out"""
    w, h, _ = SHEETS['dust']
    X, Y = grid(w, h)
    cx, cy = w / 2.0, h * 0.62
    u = (k + 0.5) / n
    rng = np.random.RandomState(SEED + 31)
    E = np.zeros((h, w), np.float32)
    for i in range(7):
        side = (i - 3) / 3.0
        ang = side * 1.15 + rng.uniform(-0.15, 0.15)
        speed = 9 + rng.uniform(0, 4)
        px = cx + math.sin(ang) * speed * (1 - (1 - u) ** 2) * 1.0
        py = cy - 2 - speed * 0.5 * u - abs(side) * 2 * u
        rad = 5 + 5 * u + rng.uniform(0, 1.5)
        E += blob(X, Y, px, py, rad) * (1 - u) ** 1.1 * 0.8
    return finish(E, DUST)


def shadow_frame(k, n):
    w, h, _ = SHEETS['shadow']
    X, Y = grid(w, h)
    d = np.sqrt(((X - w / 2.0) / (w / 2.0 - 1)) ** 2 + ((Y - h / 2.0) / (h / 2.0 - 1)) ** 2)
    a = (1 - smooth(0.2, 1.0, d)) ** 1.2 * 0.62
    out = np.zeros((h, w, 4), np.uint8)
    out[..., 3] = np.round(np.clip(a, 0, 1) * 255).astype(np.uint8)
    out[a < 0.012, 3] = 0
    return out


def glow_frame(k, n):
    w, h, _ = SHEETS['glow']
    X, Y = grid(w, h)
    E = blob(X, Y, w / 2.0, h / 2.0, w / 2.0 - 1) * 1.1 + blob(X, Y, w / 2.0, h / 2.0, 4) * 0.8
    return finish(E, WHITE)


DRAW = {'flash': flash_frame, 'ring': ring_frame, 'dust': dust_frame, 'shadow': shadow_frame, 'glow': glow_frame}


def sheet(name):
    w, h, n = SHEETS[name]
    img = np.zeros((h, w * n, 4), np.uint8)
    for k in range(n):
        img[:, k * w:(k + 1) * w] = DRAW[name](k, n)
    return img


def sheet_name(name):
    return name + '.png'


def all_sheets():
    for name in SHEETS:
        yield sheet_name(name), sheet(name)


def save(path, arr):
    Image.fromarray(arr, 'RGBA').save(path, optimize=True)


def load(path):
    return np.array(Image.open(path).convert('RGBA'))


def main(argv):
    args = argv[1:]
    out = OUT
    if '--out' in args:
        out = args[args.index('--out') + 1]
    if '--check' in args:
        bad = []
        for fname, arr in all_sheets():
            path = os.path.join(OUT, fname)
            if not os.path.exists(path):
                bad.append(fname + ' (missing)')
            elif load(path).shape != arr.shape or np.abs(load(path).astype(np.int16) - arr.astype(np.int16)).max() > TOL:
                bad.append(fname + ' (differs)')
        known = set(sheet_name(n) for n in SHEETS)
        for f in sorted(os.listdir(OUT)) if os.path.isdir(OUT) else []:
            if f.endswith('.png') and f not in known:
                bad.append(f + ' (not drawn by the generator)')
        if bad:
            print('loot burst pictures out of date:', ', '.join(bad))
            return 1
        print('loot burst pictures ok (%d)' % len(known))
        return 0
    os.makedirs(out, exist_ok=True)
    for fname, arr in all_sheets():
        save(os.path.join(out, fname), arr)
    print('wrote %d pictures to %s' % (len(SHEETS), out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
