#!/usr/bin/env python3
"""Art of the ambient particles (client/MANIFEST.md "Ambient particles (O226)"): six seamless 512 x 512 tiles of sparse
specks, drawn here from plain geometry (no source images, nothing third-party). The module game_chaosweather scrolls each
tile slowly across the game window as a repeated image (one widget per layer), so the particles are a few textured
rectangles the engine already batches, with no particle system, no per-speck Lua and no engine change.

  ember_far.png  / ember_near.png   warm orange sparks with a bright core and a short faint trail (hot, burnt land)
  mote_far.png   / mote_near.png    pale green-yellow soft glows (fireflies and motes in forest and swamp)
  dust_far.png   / dust_near.png    faint warm grey specks (caves)

The count of specks per tile is the cap of the effect: COUNTS below (ember 12 + 5, mote 9 + 4, dust 16 + 6 per tile, so a
kind shows at most 17 / 13 / 22 specks for each 512 x 512 pixels of the game window). chaosambient_logic.lua L.ART names the
same numbers and its test compares them with this file. Positions come from a fixed pseudo random sequence, keep a minimum
distance from each other and wrap around the tile edges, so the tile repeats with no seam.

Usage: python3 client/tools/gen_ambient_art.py [--check]   (Pillow; writes into overlay/modules/game_chaosweather/images/)
  --check: the committed pictures have the pixels the generator draws (exit 1 when not); nothing is written.
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'overlay', 'modules', 'game_chaosweather', 'images')
SIZE = 512         # chaosambient_logic.lua L.TILE is the same number
# name, kind, specks per tile, radius in pixels (the glow reaches this far), peak alpha range, colour, min distance
LAYERS = [
    ('ember_far', 'ember', 12, 2.3, (150, 205), (255, 140, 50), 70),
    ('ember_near', 'ember', 5, 3.6, (190, 245), (255, 170, 70), 110),
    ('mote_far', 'mote', 9, 4.2, (95, 140), (190, 235, 120), 80),
    ('mote_near', 'mote', 4, 7.0, (130, 185), (210, 245, 140), 120),
    ('dust_far', 'dust', 16, 1.9, (55, 95), (205, 190, 165), 60),
    ('dust_near', 'dust', 6, 2.8, (80, 125), (215, 200, 175), 100),
]
COUNTS = {name: count for name, _kind, count, _r, _a, _c, _d in LAYERS}


class Lcg:
    def __init__(self, seed):
        self.state = seed & 0xFFFFFFFF

    def next(self, n):
        self.state = (self.state * 1664525 + 1013904223) & 0xFFFFFFFF
        return (self.state >> 8) % n


def put(px, x, y, color, alpha):
    x, y = x % SIZE, y % SIZE
    if alpha > px[x, y][3]:
        px[x, y] = (color[0], color[1], color[2], alpha)


def draw(kind, count, radius, alpha, color, min_dist, seed):
    rng = Lcg(seed)
    heads = []
    guard = 0
    while len(heads) < count and guard < 10000:
        guard += 1
        x, y = rng.next(SIZE), rng.next(SIZE)
        ok = True
        for hx, hy in heads:
            dx, dy = abs(x - hx), abs(y - hy)
            dx, dy = min(dx, SIZE - dx), min(dy, SIZE - dy)
            if dx * dx + dy * dy < min_dist * min_dist:
                ok = False
                break
        if ok:
            heads.append((x, y))
    img = Image.new('RGBA', (SIZE, SIZE), (color[0], color[1], color[2], 0))
    px = img.load()
    reach = int(math.ceil(radius)) + 1
    for hx, hy in heads:
        peak = alpha[0] + rng.next(alpha[1] - alpha[0] + 1)
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                d = math.hypot(dx, dy)
                if d > radius:
                    continue
                # a soft round speck: full in the middle, falling to nothing at the radius (squared falloff)
                a = int(peak * (1.0 - d / radius) ** 1.5 + 0.5) if kind != 'dust' else int(peak * (1.0 - d / (radius + 0.5)) + 0.5)
                if a > 0:
                    put(px, hx + dx, hy + dy, color, a)
        if kind == 'ember':
            # a bright core pixel and a two to four pixel tail under it (the spark rises, the tail trails below)
            put(px, hx, hy, (255, 235, 170), min(255, peak + 20))
            tail = 2 + rng.next(3)
            for i in range(1, tail + 1):
                put(px, hx, hy + i, color, int(peak * 0.45 * (1.0 - i / (tail + 1.0))))
    return img


def images():
    return {name: draw(kind, count, radius, alpha, color, dist, 5000 + 41 * i)
            for i, (name, kind, count, radius, alpha, color, dist) in enumerate(LAYERS)}


def main(argv):
    made = images()
    if '--check' in argv:
        bad = []
        for name, img in made.items():
            path = os.path.join(OUT, name + '.png')
            if not os.path.isfile(path):
                bad.append(name + ': missing')
                continue
            have = Image.open(path).convert('RGBA')
            if have.size != img.size or have.tobytes() != img.tobytes():
                bad.append(name + ': differs from the generator')
        for b in bad:
            print('gen_ambient_art --check:', b)
        if bad:
            return 1
        print('gen_ambient_art --check: %d images up to date' % len(made))
        return 0
    os.makedirs(OUT, exist_ok=True)
    for name, img in made.items():
        img.save(os.path.join(OUT, name + '.png'), optimize=True)
        print('wrote', name + '.png')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
