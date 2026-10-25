#!/usr/bin/env python3
"""Art of the client-drawn rain (client/MANIFEST.md "game_chaosweather", O208): three seamless 256 x 256 tiles of thin
slanted streaks, drawn here from plain geometry (no source images, nothing third-party). The module scrolls each tile
across the game window as a repeated image (one widget per layer), so the rain is a few dozen textured rectangles that
the engine already batches, with no particles, no per-drop Lua and no engine change.

  rain_far.png   short faint streaks, many   (the back layer, slowest)
  rain_mid.png   medium streaks              (heavy rain only)
  rain_near.png  long bright streaks, fewer  (the front layer, fastest, two pixels wide)

Every streak slants the same way (SLANT pixels right for each pixel down, matching the scroll direction in
chaosweather_logic.lua), fades from a bright head at the bottom to a dim tail, and wraps around the tile edges, so the tile
repeats with no seam. Positions come from a fixed pseudo random sequence and keep a minimum distance from each other.

Usage: python3 client/tools/gen_rain_art.py [--check]   (Pillow; writes into overlay/modules/game_chaosweather/images/)
  --check: the committed pictures have the pixels the generator draws (exit 1 when not); nothing is written.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'overlay', 'modules', 'game_chaosweather', 'images')
SIZE = 256
SLANT = 0.30       # pixels right per pixel down; chaosweather_logic.lua L.SLANT is the same number
COLOR = (178, 208, 255)
# name, streaks per tile, length range, head alpha range, width, minimum distance between two streak heads
LAYERS = [
    ('rain_far', 12, (8, 12), (95, 135), 1, 44),
    ('rain_mid', 8, (12, 17), (125, 165), 1, 52),
    ('rain_near', 6, (17, 25), (150, 205), 2, 60),
]


class Lcg:
    def __init__(self, seed):
        self.state = seed & 0xFFFFFFFF

    def next(self, n):
        self.state = (self.state * 1664525 + 1013904223) & 0xFFFFFFFF
        return (self.state >> 8) % n


def draw(name, count, length, alpha, width, min_dist, seed):
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
    img = Image.new('RGBA', (SIZE, SIZE), (COLOR[0], COLOR[1], COLOR[2], 0))
    px = img.load()
    for hx, hy in heads:
        n = length[0] + rng.next(length[1] - length[0] + 1)
        a_head = alpha[0] + rng.next(alpha[1] - alpha[0] + 1)
        for i in range(n):
            t = (n - 1 - i) / float(n)          # 0 at the head (bottom), near 1 at the tail
            a = int(a_head * (1.0 - t) ** 1.3 + 0.5)
            y = (hy - i) % SIZE
            x = int(round(hx - i * SLANT)) % SIZE
            for w in range(width):
                xx = (x + w) % SIZE
                shade = a if w == 0 else a // 2
                if shade > px[xx, y][3]:
                    px[xx, y] = (COLOR[0], COLOR[1], COLOR[2], shade)
    return img


def images():
    return {name: draw(name, count, length, alpha, width, dist, 1000 + 37 * i)
            for i, (name, count, length, alpha, width, dist) in enumerate(LAYERS)}


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
            print('gen_rain_art --check:', b)
        if bad:
            return 1
        print('gen_rain_art --check: %d images up to date' % len(made))
        return 0
    os.makedirs(OUT, exist_ok=True)
    for name, img in made.items():
        img.save(os.path.join(OUT, name + '.png'), optimize=True)
        print('wrote', name + '.png')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
