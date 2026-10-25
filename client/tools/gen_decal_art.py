#!/usr/bin/env python3
"""Ground decal pictures of game_combatdecals (O231): the stains combat leaves on the floor.
  images/blood<N>.png    64x64  blood where a creature dies (a pool and a few drops)
  images/scorch<N>.png   64x64  a burn mark under a fire hit (charred middle, ember edge)
  images/frost<N>.png    64x64  frost cracks under an ice hit (cracks from the middle over a pale rime)
  images/stain<N>.png    64x64  a green stain under a poison or earth hit (a pool with bubbles)
N = 1..VARIANTS (CombatDecalsLogic.VARIANTS). The module turns each by a quarter at random and fades it out; the
pictures are drawn at full opacity in the colours of the elements.
All drawn here from shapes with a seeded generator and plain per-pixel maths (no filters, no reference art, nothing
copied), so the bytes do not depend on the Pillow version.
Usage: python3 client/tools/gen_decal_art.py [--check] [--preview PATH]   (Pillow; writes into
  client/overlay/modules/game_combatdecals/images/)
  --check: the committed pictures have the pixels the generator draws (exit 1 when not); nothing is written.
  --preview PATH: one sheet with every picture on a dark ground (not shipped)."""
import math
import os
import random
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_combatdecals', 'images')
S = 64
VARIANTS = 2   # CombatDecalsLogic.VARIANTS (checked by combatdecals_test.lua through the file names)

# art name -> colours
BLOOD = {'deep': (88, 6, 10), 'main': (150, 14, 18), 'bright': (196, 34, 30)}
SCORCH = {'char': (22, 18, 16), 'ash': (58, 50, 44), 'ember': (232, 112, 28), 'glow': (255, 190, 70)}
FROST = {'rime': (196, 228, 250), 'crack': (240, 252, 255), 'deep': (96, 160, 226)}
STAIN = {'deep': (38, 92, 24), 'main': (84, 168, 44), 'bright': (170, 238, 96)}


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smooth(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


class Blob:
    """A round-ish spot with a wobbling edge (a few seeded harmonics of the angle)."""

    def __init__(self, cx, cy, r, rnd, wobble=0.22):
        self.cx, self.cy, self.r = cx, cy, r
        self.h = [(k, rnd.uniform(0, 2 * math.pi), rnd.uniform(0.3, 1.0) * wobble / k) for k in (2, 3, 5)]

    def depth(self, x, y):
        """1 in the middle, 0 at the edge, negative outside."""
        dx, dy = x - self.cx, y - self.cy
        d = math.hypot(dx, dy)
        a = math.atan2(dy, dx)
        edge = self.r * (1 + sum(amp * math.sin(k * a + ph) for k, ph, amp in self.h))
        return 1.0 - d / max(edge, 0.5)


def field(blobs, x, y):
    return max(b.depth(x, y) for b in blobs)


def to_image(fn):
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    px = im.load()
    for y in range(S):
        for x in range(S):
            r, g, b, a = fn(x + 0.5, y + 0.5)
            if a > 0:
                px[x, y] = (int(r + 0.5), int(g + 0.5), int(b + 0.5), int(max(0, min(255, a)) + 0.5))
    return im


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L = vx * vx + vy * vy
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / L))
    return math.hypot(px - (ax + vx * t), py - (ay + vy * t))


def draw_blood(seed):
    rnd = random.Random(seed)
    c = S / 2
    main = Blob(c + rnd.uniform(-2, 2), c + rnd.uniform(-2, 2), rnd.uniform(15, 19), rnd, 0.28)
    drops = []
    for _ in range(rnd.randint(5, 7)):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(18, 27)
        drops.append(Blob(c + math.cos(a) * d, c + math.sin(a) * d, rnd.uniform(1.6, 4.2), rnd, 0.15))
    shine = (c - 5 + rnd.uniform(-2, 2), c - 6 + rnd.uniform(-2, 2))

    def fn(x, y):
        f = field([main] + drops, x, y)
        if f <= 0:
            return 0, 0, 0, 0
        col = mix(BLOOD['deep'], BLOOD['main'], smooth(0.0, 0.5, f))
        col = mix(col, BLOOD['bright'], 0.55 * smooth(0.55, 1.0, f) * (1 if f == main.depth(x, y) else 0.3))
        sh = max(0.0, 1.0 - math.hypot(x - shine[0], y - shine[1]) / 4.0)
        col = mix(col, (255, 220, 214), 0.45 * sh * sh)
        return col[0], col[1], col[2], 235 * smooth(0.0, 0.12, f)
    return to_image(fn)


def draw_scorch(seed):
    rnd = random.Random(seed)
    c = S / 2
    main = Blob(c, c, rnd.uniform(20, 24), rnd, 0.3)
    core = Blob(c + rnd.uniform(-2, 2), c + rnd.uniform(-2, 2), rnd.uniform(11, 14), rnd, 0.35)
    flecks = []
    for _ in range(22):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0.62, 1.0)
        flecks.append((c + math.cos(a) * d * 22, c + math.sin(a) * d * 22, rnd.uniform(0.6, 1.4)))

    def fn(x, y):
        f = main.depth(x, y)
        spark = 0.0
        for fx, fy, fr in flecks:
            spark = max(spark, 1.0 - math.hypot(x - fx, y - fy) / fr)
        if f <= 0 and spark <= 0:
            return 0, 0, 0, 0
        inner = core.depth(x, y)
        col = mix(SCORCH['ash'], SCORCH['char'], smooth(-0.1, 0.5, inner))
        # a thin ember ring at the edge of the burn
        ring = smooth(0.0, 0.06, f) * (1 - smooth(0.06, 0.2, f))
        col = mix(col, SCORCH['ember'], 0.6 * ring)
        col = mix(col, SCORCH['glow'], 0.35 * ring * smooth(0.55, 1.0, 0.5 + 0.5 * math.sin(x * 0.9 + y * 1.3)))
        a = 225 * smooth(0.0, 0.1, f)
        if spark > 0:
            col = mix(col, SCORCH['glow'], 0.9 * smooth(0, 0.5, spark))
            a = max(a, 200 * smooth(0, 0.5, spark))
        return col[0], col[1], col[2], a
    return to_image(fn)


def draw_frost(seed):
    rnd = random.Random(seed)
    c = S / 2
    rime = Blob(c, c, rnd.uniform(18, 22), rnd, 0.3)
    cracks = []   # (ax, ay, bx, by, width)

    def branch(x, y, ang, length, width, depth):
        for _ in range(3 if depth == 0 else 2):
            ang += rnd.uniform(-0.45, 0.45)
            step = length / 3
            nx, ny = x + math.cos(ang) * step, y + math.sin(ang) * step
            cracks.append((x, y, nx, ny, width))
            x, y = nx, ny
            if depth < 2 and rnd.random() < 0.7:
                branch(x, y, ang + rnd.choice((-1, 1)) * rnd.uniform(0.6, 1.1), length * 0.55, width * 0.75, depth + 1)

    n = rnd.randint(6, 8)
    off = rnd.uniform(0, 2 * math.pi)
    for i in range(n):
        branch(c, c, off + i * 2 * math.pi / n + rnd.uniform(-0.2, 0.2), rnd.uniform(20, 28), 1.5, 0)

    def fn(x, y):
        f = rime.depth(x, y)
        dist = 99.0
        wid = 1.0
        for ax, ay, bx, by, w in cracks:
            d = seg_dist(x, y, ax, ay, bx, by) / w
            if d < dist:
                dist, wid = d, w
        line = 1.0 - smooth(0.35, 1.0, dist)
        if f <= 0 and line <= 0:
            return 0, 0, 0, 0
        col = mix(FROST['deep'], FROST['rime'], smooth(0.0, 0.7, f))
        a = 120 * smooth(0.0, 0.3, f)
        col = mix(col, FROST['crack'], line)
        a = max(a, 250 * line)
        return col[0], col[1], col[2], a
    return to_image(fn)


def draw_stain(seed):
    rnd = random.Random(seed)
    c = S / 2
    main = Blob(c + rnd.uniform(-2, 2), c + rnd.uniform(-2, 2), rnd.uniform(15, 19), rnd, 0.3)
    lobes = [Blob(c + math.cos(a) * 15, c + math.sin(a) * 15, rnd.uniform(5, 8), rnd, 0.25)
             for a in (rnd.uniform(0, 2 * math.pi) for _ in range(rnd.randint(3, 4)))]
    drops = []
    for _ in range(rnd.randint(3, 5)):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(22, 28)
        drops.append(Blob(c + math.cos(a) * d, c + math.sin(a) * d, rnd.uniform(1.4, 3.0), rnd, 0.15))
    bubbles = [(c + rnd.uniform(-11, 11), c + rnd.uniform(-11, 11), rnd.uniform(1.8, 3.4)) for _ in range(5)]

    def fn(x, y):
        f = field([main] + lobes + drops, x, y)
        if f <= 0:
            return 0, 0, 0, 0
        col = mix(STAIN['deep'], STAIN['main'], smooth(0.0, 0.45, f))
        for bx, by, br in bubbles:
            d = math.hypot(x - bx, y - by)
            if d < br:
                rim = smooth(br - 1.1, br, d)
                col = mix(col, STAIN['bright'], 0.75 * rim + 0.2)
                if math.hypot(x - bx + br * 0.35, y - by + br * 0.35) < br * 0.3:
                    col = mix(col, (240, 255, 220), 0.8)
        return col[0], col[1], col[2], 225 * smooth(0.0, 0.12, f)
    return to_image(fn)


ARTS = (('blood', draw_blood), ('scorch', draw_scorch), ('frost', draw_frost), ('stain', draw_stain))


def images():
    out = {}
    for i, (name, fn) in enumerate(ARTS):
        for v in range(1, VARIANTS + 1):
            out['%s%d' % (name, v)] = fn(3100 + 17 * i + 101 * v)
    return out


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
        have_files = sorted(f for f in os.listdir(OUT) if f.endswith('.png')) if os.path.isdir(OUT) else []
        for f in have_files:
            if f[:-4] not in made:
                bad.append(f + ': not made by the generator')
        for b in bad:
            print('gen_decal_art --check:', b)
        if bad:
            return 1
        print('gen_decal_art --check: %d images up to date' % len(made))
        return 0
    os.makedirs(OUT, exist_ok=True)
    for name, img in made.items():
        img.save(os.path.join(OUT, name + '.png'), optimize=True)
        print('wrote', name + '.png')
    if '--preview' in argv:
        path = argv[argv.index('--preview') + 1]
        sheet = Image.new('RGBA', (VARIANTS * 136 + 8, len(ARTS) * 136 + 8), (60, 54, 48, 255))
        for i, (name, _) in enumerate(ARTS):
            for v in range(1, VARIANTS + 1):
                sheet.alpha_composite(made['%s%d' % (name, v)].resize((128, 128), Image.NEAREST),
                                      (8 + (v - 1) * 136, 8 + i * 136))
        sheet.save(path)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
