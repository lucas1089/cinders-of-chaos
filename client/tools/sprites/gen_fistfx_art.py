#!/usr/bin/env python3
"""Build the Monk fist weapon icons and the Necromancer bone effects from the PixelLab paintings in art_import/fistfx_src/.

python3 -I gen_fistfx_art.py [--preview DIR]

Sources (art_import/fistfx_src/, picked unchanged from PixelLab Create image Pro runs; the prompts are in
client/tools/art_studio/prompts/items/fist-weapons.md, bone-spear.md, bone-shards.md, bone-skulls.md; our own art):
  fist_t1..fist_t5.png, fist_pyre.png   32x32 item paintings
  bone_spear.png                         32x32, a bone spear lying from bottom-left to top-right
  shard_0..7.png, skull_0..2.png         16x16 bone pieces
Outputs (deterministic; the same sources give byte-identical PNGs):
  art_import/fist_weapons.png            6 items side by side (atlas of art_import/fist_weapons.csv)
  art_import/bone_fx/bone_spear_missile.png   missile, 3x3 direction patterns x 2 frames (art_import/fx_art.csv)
  art_import/bone_fx/bone_spear.png      effect: the spear's impact, splinters and a violet snap (3x3 tiles)
  art_import/bone_fx/bone_burst.png      effect: a burst of bone shards from a corpse (3x3 tiles)
  art_import/bone_fx/bone_aura.png       effect: skulls and shards rising and circling a creature (3x3 tiles)
Nothing here is repainted per frame: the animation moves, flips and turns the painted pieces (RotSprite: Scale2x three
times, nearest rotation, nearest sampling back), and adds crisp violet arcs and dust drawn in code. Alpha is 0 or 255.
Effects are 3x3 tiles sent with the offset (1, 1) (fx_art.csv dx, dy), so the middle tile is the target tile; every
effect fades by an ordered dither and its last frame is nearly empty.
"""
import argparse, math, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'art_import', 'fistfx_src')
OUT = os.path.join(HERE, 'art_import')
ITEMS = ['fist_t1', 'fist_t2', 'fist_t3', 'fist_t4', 'fist_t5', 'fist_pyre']
VIOLET = [(34, 12, 52), (70, 28, 110), (118, 62, 178), (172, 128, 240), (226, 206, 255)]
DUST = [(58, 50, 44), (120, 108, 92), (196, 184, 160)]
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])
C = 96                      # effect canvas (3x3 tiles), target tile = pixels 32..63
CENTRE = (45, 45)           # the body of a creature on the target tile (drawn 8 px up-left like the client)
FEET = (46, 54)


def load(name):
    a = np.asarray(Image.open(os.path.join(SRC, name + '.png')).convert('RGBA')).copy()
    on = a[:, :, 3] >= 128
    a[:, :, 3] = np.where(on, 255, 0)
    a[~on] = 0
    return a


def crisp(a):
    a = a.copy()
    on = a[:, :, 3] >= 128
    a[:, :, 3] = np.where(on, 255, 0)
    a[~on] = 0
    return a


# ------------------------------------------------------------------------------------------------ RotSprite
def scale2x(a):
    h, w = a.shape[:2]
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode='edge')
    B, D, E, F, H = p[:-2, 1:-1], p[1:-1, :-2], p[1:-1, 1:-1], p[1:-1, 2:], p[2:, 1:-1]
    eq = lambda x, y: (x == y).all(axis=2)
    out = np.zeros((h * 2, w * 2, 4), a.dtype)
    c = ~eq(B, H) & ~eq(D, F)
    for (dy, dx), (s1, s2, o) in {(0, 0): (D, B, F), (0, 1): (B, F, D), (1, 0): (D, H, F), (1, 1): (H, F, D)}.items():
        pick = c & eq(s1, s2)
        q = np.where(pick[:, :, None], s1, E)
        out[dy::2, dx::2] = q
    return out


def rotsprite(a, deg, scale=1.0):
    """rotate (counter-clockwise, degrees) and scale a pixel-art sprite, keeping it crisp; returns a tight crop"""
    up = a
    for _ in range(3):
        up = scale2x(up)
    im = Image.fromarray(up).rotate(deg, resample=Image.NEAREST, expand=True)
    w, h = im.size
    k = 8 / scale
    im = im.resize((max(1, int(round(w / k))), max(1, int(round(h / k)))), Image.NEAREST)
    r = crisp(np.asarray(im))
    ys, xs = np.nonzero(r[:, :, 3])
    return r[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()


def tight(a):
    ys, xs = np.nonzero(a[:, :, 3])
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()


# ------------------------------------------------------------------------------------------------ drawing helpers
def paste(cv, spr, cx, cy, keep=1.0, seed=0):
    """spr centred at (cx, cy); keep < 1 drops pixels by the ordered dither (a crisp fade)"""
    h, w = spr.shape[:2]
    x0, y0 = int(round(cx - w / 2)), int(round(cy - h / 2))
    for y in range(h):
        for x in range(w):
            if spr[y, x, 3] == 0:
                continue
            X, Y = x0 + x, y0 + y
            if not (0 <= X < cv.shape[1] and 0 <= Y < cv.shape[0]):
                continue
            if keep < 1 and BAYER[(Y + seed) % 4, (X + seed * 3) % 4] >= keep * 16:
                continue
            cv[Y, X] = spr[y, x]


def dot(cv, x, y, col, keep=1.0):
    X, Y = int(round(x)), int(round(y))
    if 0 <= X < cv.shape[1] and 0 <= Y < cv.shape[0] and (keep >= 1 or BAYER[Y % 4, X % 4] < keep * 16):
        cv[Y, X] = col + (255,)


def arcs(cv, cx, cy, r, width, segments, phase, keep=1.0, squash=1.0):
    """broken ring: `segments` arcs of 60% of their share, coloured inner dark -> outer bright"""
    yy, xx = np.mgrid[0:cv.shape[0], 0:cv.shape[1]]
    dx, dy = xx - cx, (yy - cy) / squash
    dist = np.hypot(dx, dy)
    ang = (np.degrees(np.arctan2(dy, dx)) - phase) % 360
    share = 360 / segments
    on = (np.abs(dist - r) <= width / 2) & ((ang % share) < share * 0.6)
    t = np.clip((dist - (r - width / 2)) / max(width, 1), 0, 0.999)
    idx = (1 + t * (len(VIOLET) - 1)).astype(int).clip(1, len(VIOLET) - 1)
    if keep < 1:
        on &= BAYER[yy % 4, xx % 4] < keep * 16
    for i in range(1, len(VIOLET)):
        m = on & (idx == i)
        cv[m] = VIOLET[i] + (255,)


def spark(cv, cx, cy, size, keep=1.0):
    """a small four-point necrotic glint"""
    for d in range(-size, size + 1):
        col = VIOLET[4] if abs(d) <= size // 3 else VIOLET[3] if abs(d) <= 2 * size // 3 else VIOLET[2]
        dot(cv, cx + d, cy, col, keep); dot(cv, cx, cy + d, col, keep)


def turn(spr, k, flip):
    s = np.rot90(spr, k)
    return np.ascontiguousarray(s[:, ::-1] if flip else s)


# ------------------------------------------------------------------------------------------------ items
def fist_items():
    ims = [load(n) for n in ITEMS]
    # the unique: the skull's eye sockets burn like embers (the Pyre Saint)
    pyre = ims[ITEMS.index('fist_pyre')]
    for (x, y), col in {(14, 13): (255, 196, 92), (15, 13): (236, 104, 34), (14, 14): (150, 44, 22),
                        (18, 13): (236, 104, 34), (19, 13): (255, 196, 92), (20, 13): (150, 44, 22),
                        (18, 14): (150, 44, 22), (19, 14): (236, 104, 34), (19, 12): (150, 44, 22)}.items():
        pyre[y, x] = col + (255,)
    return np.concatenate(ims, axis=1)


# ------------------------------------------------------------------------------------------------ missile
MISSILE_DIR = {(0, 0): 'nw', (1, 0): 'n', (2, 0): 'ne', (0, 1): 'w', (1, 1): 's', (2, 1): 'e',
               (0, 2): 'sw', (1, 2): 's', (2, 2): 'se'}


def spear_missile():
    sp = tight(load('bone_spear'))                         # points north-east
    ne = rotsprite(sp, 0, 0.78)
    e = rotsprite(sp, -45, 0.6)                            # the straight ones are longer: shrink them to fit a tile
    n = rotsprite(sp, 45, 0.6)
    look = {'ne': ne, 'nw': ne[:, ::-1], 'se': ne[::-1], 'sw': ne[::-1, ::-1], 'e': e, 'w': e[:, ::-1], 'n': n,
            's': n[::-1]}
    back = {'ne': (-1, 1), 'nw': (1, 1), 'se': (-1, -1), 'sw': (1, -1), 'e': (-1, 0), 'w': (1, 0), 'n': (0, 1), 's': (0, -1)}
    W = 32
    out = np.zeros((3 * W, 3 * W * 2, 4), np.uint8)
    for (px, py), d in MISSILE_DIR.items():
        s = np.ascontiguousarray(look[d])
        for f in range(2):
            cv = np.zeros((W, W, 4), np.uint8)
            bx, by = back[d]
            # a short trail of violet motes behind the butt, alternating between the two frames
            for i in range(3):
                t = 9 + i * 3 + (f * 2 if i % 2 == 0 else 0)
                dot(cv, 16 + bx * t + (i % 2) * (1 - f), 16 + by * t, VIOLET[3 - i] if i < 3 else VIOLET[1])
            paste(cv, s, 16, 16)
            x0 = (px * 2 + f) * W
            out[py * W:(py + 1) * W, x0:x0 + W] = cv
    return out


# ------------------------------------------------------------------------------------------------ effects
def shard_set(scale=1.0):
    return [rotsprite(tight(load('shard_%d' % i)), 0, scale) if scale != 1.0 else tight(load('shard_%d' % i))
            for i in range(8)]


def bone_burst():
    """corpse explosion: a violet snap at the ground, eight shards thrown out and falling, dust, a dithered fade"""
    shards = shard_set(0.85)
    n = 9
    rng = np.random.RandomState(7)
    ang = [i * 45 + rng.uniform(-14, 14) for i in range(8)]
    speed = [rng.uniform(3.4, 4.6) for _ in range(8)]
    lift = [rng.uniform(3.5, 5.5) for _ in range(8)]
    dust = [(rng.uniform(0, 360), rng.uniform(2.0, 5.0), rng.uniform(1.5, 4.0), rng.randint(0, 3)) for _ in range(18)]
    frames = []
    for f in range(n):
        cv = np.zeros((C, C, 4), np.uint8)
        fade = 1.0 if f < 5 else max(0.0, 1 - (f - 4) / 4.2)
        if f < 4:
            arcs(cv, FEET[0], FEET[1] - 2, 5 + f * 7, 3 if f < 2 else 2 if f < 3 else 1, 7, f * 17, keep=1.0 if f < 3 else 0.5)
        if f < 2:
            spark(cv, FEET[0], FEET[1] - 6, 4 + 2 * f)
        for k, (a, v, lf, c) in enumerate(dust):
            t = f + 0.6
            r = v * t
            h = max(0.0, lf * t - 0.55 * t * t)
            x = FEET[0] + r * math.cos(math.radians(a)) - h / 1.5
            y = FEET[1] - 2 + r * math.sin(math.radians(a)) - h / 1.5
            dot(cv, x, y, DUST[c], keep=fade * (1.0 if f < 6 else 0.5))
        for i, s in enumerate(shards):
            t = f + 0.8
            r = speed[i] * t
            h = max(0.0, lift[i] * t - 0.62 * t * t)
            x = FEET[0] + r * math.cos(math.radians(ang[i])) - h / 1.5
            y = FEET[1] - 3 + r * math.sin(math.radians(ang[i])) - h / 1.5
            paste(cv, turn(s, (f // 2 + i) % 4, i % 2 == 1), x, y, keep=fade, seed=i)
        frames.append(cv)
    frames[-1][:] = 0                                      # the last frame is empty: the effect is gone
    return np.concatenate(frames, axis=1)


def bone_spear_hit():
    """the spear strikes: a violet snap and six bone splinters, small enough for a filler spell"""
    pieces = [rotsprite(tight(load('shard_%d' % i)), 0, 0.5) for i in (0, 2, 3, 4, 6, 7)]
    n = 7
    rng = np.random.RandomState(11)
    ang = [i * 60 + rng.uniform(-20, 20) for i in range(6)]
    frames = []
    for f in range(n):
        cv = np.zeros((C, C, 4), np.uint8)
        fade = 1.0 if f < 4 else max(0.0, 1 - (f - 3) / 3.0)
        if f < 3:
            arcs(cv, CENTRE[0], CENTRE[1], 3 + f * 4, 2 if f < 2 else 1, 5, 20 + f * 25)
            spark(cv, CENTRE[0], CENTRE[1], 3 - f)
        for i, s in enumerate(pieces):
            t = f + 0.7
            r = 3.2 * t
            h = max(0.0, 3.0 * t - 0.7 * t * t)
            x = CENTRE[0] + r * math.cos(math.radians(ang[i])) - h / 1.5
            y = CENTRE[1] + 4 + r * math.sin(math.radians(ang[i])) - h / 1.5
            paste(cv, turn(s, (f + i) % 4, i % 2 == 0), x, y, keep=fade, seed=i)
        frames.append(cv)
    frames[-1][:] = 0
    return np.concatenate(frames, axis=1)


def bone_aura():
    """three skulls and four shards rise from a violet ring at the feet, circle the creature once, sink and fade"""
    skulls = [rotsprite(tight(load('skull_%d' % i)), 0, 0.72) for i in range(3)]
    shards = shard_set(0.6)[:4]
    n = 14
    frames = []
    for f in range(n):
        cv = np.zeros((C, C, 4), np.uint8)
        rise = min(1.0, (f + 1) / 3.0) if f < 10 else max(0.0, 1 - (f - 9) / 4.0)
        fade = 1.0 if f < 10 else max(0.0, 1 - (f - 9) / 4.0)
        ring_keep = min(1.0, (f + 1) / 2.0) * fade
        arcs(cv, FEET[0], FEET[1], 21, 2, 9, f * 9, keep=ring_keep)
        arcs(cv, FEET[0], FEET[1], 15, 1, 6, -f * 13, keep=ring_keep * 0.75)
        things = []
        for i, s in enumerate(skulls):
            a = math.radians(i * 120 + f * 24)
            things.append((math.sin(a), s, FEET[0] + 20 * math.cos(a), FEET[1] + 20 * math.sin(a), 13 * rise + 2 * math.sin(a * 2), i))
        for i, s in enumerate(shards):
            a = math.radians(60 + i * 90 - f * 30)
            things.append((math.sin(a), turn(s, f % 4, i % 2 == 0), FEET[0] + 25 * math.cos(a), FEET[1] + 25 * math.sin(a),
                           7 * rise, 3 + i))
        for _, s, x, y, h, i in sorted(things, key=lambda t: t[0]):   # the far (north) side first
            paste(cv, s, x - h / 1.5, y - h / 1.5 - s.shape[0] / 2 + 3, keep=fade, seed=i)
        if 2 <= f <= 9 and f % 3 == 2:
            spark(cv, CENTRE[0] - 1, CENTRE[1] - 14, 3)
        frames.append(cv)
    frames[-1][:] = 0
    return np.concatenate(frames, axis=1)


def preview(path, strips):
    """each effect's frames over a grey-brown ground at 1x and 2x (judge at 1x)"""
    rows = []
    for name, a, fw in strips:
        n = a.shape[1] // fw
        g = Image.new('RGBA', (n * (fw + 4), a.shape[0]), (74, 66, 54, 255))
        for i in range(n):
            g.alpha_composite(Image.fromarray(np.ascontiguousarray(a[:, i * fw:(i + 1) * fw])), (i * (fw + 4), 0))
        rows.append(g)
    W = max(r.width for r in rows) * 3
    H = sum(r.height * 3 + 6 for r in rows)
    sh = Image.new('RGBA', (W, H), (20, 18, 16, 255))
    y = 0
    for r in rows:
        sh.alpha_composite(r, (0, y))
        sh.alpha_composite(r.resize((r.width * 2, r.height * 2), Image.NEAREST), (0, y + r.height + 2))
        y += r.height * 3 + 6
    sh.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--preview', default=None)
    a = ap.parse_args()
    os.makedirs(os.path.join(OUT, 'bone_fx'), exist_ok=True)
    outs = {'fist_weapons.png': fist_items(), 'bone_fx/bone_spear_missile.png': spear_missile(),
            'bone_fx/bone_spear.png': bone_spear_hit(), 'bone_fx/bone_burst.png': bone_burst(),
            'bone_fx/bone_aura.png': bone_aura()}
    for rel, arr in outs.items():
        Image.fromarray(arr, 'RGBA').save(os.path.join(OUT, rel), optimize=True)
        print('wrote', rel, arr.shape[1], 'x', arr.shape[0])
    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        preview(os.path.join(a.preview, 'fistfx_preview.png'),
                [('items', outs['fist_weapons.png'], 32), ('missile', outs['bone_fx/bone_spear_missile.png'], 32),
                 ('bone_spear', outs['bone_fx/bone_spear.png'], C), ('bone_burst', outs['bone_fx/bone_burst.png'], C),
                 ('bone_aura', outs['bone_fx/bone_aura.png'], C)])
        print('preview', a.preview)


if __name__ == '__main__':
    main()
