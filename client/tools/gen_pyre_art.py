#!/usr/bin/env python3
"""Art of the Pyre Oath keystone: the ember ring under the character and the burn on struck monsters (O518, module game_chestaura).

The looks are the ones the owner approved from the preview GIF combo_C1_v2 on 2026-11-12 (ring "C": a rune circle of fire with ash,
cinders and pop sparks; burn "1": embers rising, char flecks, a spark burst on the tick, ash flakes). Everything is drawn here from
shapes and noise with a fixed seed (no reference art, nothing third-party). A filmstrip is one row of square frames, left to right.

  pyre/ring.png   160 px x 12   the ring under the feet of a player holding Pyre Oath: 5 x 5 tiles, the circle at 64 px radius = the
                                keystone's 2 sqm reach (archetypes_config.lua arPyreOath.radius), one loop = 1 s (12 frames at 83 ms)
  pyre/burn.png    64 px x 8    the burn on a monster the aura struck: 8 frames at 125 ms = one 1 s tick, played from the tick

python3 -I client/tools/gen_pyre_art.py                 # write the strips into the module (overlay/modules/game_chestaura/images/pyre)
python3 -I client/tools/gen_pyre_art.py --check         # the committed strips are what the generator draws (exit 1 if not); writes nothing
python3 -I client/tools/gen_pyre_art.py --out DIR       # write the strips somewhere else
python3 -I client/tools/gen_pyre_art.py --combo DIR     # preview GIF and sheet of the ring and the burn on a mock (never committed)

numpy and Pillow are needed (CI runs the check with the pinned versions of the fx venv, because float maths differs a little between
versions; the strips were made with Pillow 12.3.0 and numpy 2.5.3).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

SEED = 20261112
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'overlay', 'modules', 'game_chestaura', 'images')
RING_PX = 160          # 5 x 5 tiles of 32 px, centred on the character's feet; the ring's reach is 2 sqm = 64 px
RING_FRAMES = 12
BURN_PX = 64
BURN_FRAMES = 8
TAU = math.tau


def canvas(n):
    return np.zeros((n, n, 4), np.float32)


def over(dst, src):
    sa, da = src[..., 3:4], dst[..., 3:4]
    oa = sa + da * (1 - sa)
    dst[..., :3] = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    dst[..., 3:4] = oa


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return x + 0.5, y + 0.5


def layer(n, alpha, color):
    out = canvas(n)
    out[..., :3] = np.array(color, np.float32) / 255.0
    out[..., 3] = np.clip(alpha, 0, 1)
    return out


def blob(n, cx, cy, rx, ry, color, a, power=1.5):
    x, y = grid(n)
    r = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    return layer(n, a * np.clip(1 - r, 0, 1) ** power, color)


def ring_alpha(n, cx, cy, radius, width, soft=1.0):
    x, y = grid(n)
    d = np.abs(np.sqrt((x - cx) ** 2 + (y - cy) ** 2) - radius)
    return np.clip((width - d) / soft, 0, 1)


def ember(n, cx, cy, size, heat, a):
    """a point of light: white-yellow core inside an orange halo; heat 0..1 shifts toward red as it cools"""
    col = (255, int(120 + 110 * heat), int(30 + 80 * heat))
    out = blob(n, cx, cy, size * 2.2, size * 2.2, (255, int(60 + 70 * heat), 20), a * 0.45, 2.0)
    core = blob(n, cx, cy, size, size, col, a, 1.0)
    over(out, core)
    return out


def noise_field(n, rng, scale):
    k = max(2, n // scale)
    small = np.array([[rng.random() for _ in range(k)] for _ in range(k)], np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
    return np.asarray(img, np.float32) / 255.0


# ---------------------------------------------------------------- rings (frames of RING_PX, loop of RING_FRAMES)
def rising(rng, count):
    """particles: (angle, radial jitter, phase, speed, drift, size)"""
    return [(rng.random() * TAU, rng.uniform(-6, 6), rng.random(), rng.uniform(0.8, 1.2), rng.uniform(-6, 6),
             rng.uniform(0.9, 1.7)) for _ in range(count)]


def rune(n, cx, cy, ang, r0, r1, kind, color, a):
    """a small angular glyph of straight strokes between radii r0 and r1 at angle ang"""
    im = Image.new('L', (n * 4, n * 4), 0)
    dr = ImageDraw.Draw(im)
    ca, sa = math.cos(ang), math.sin(ang)

    def pt(rad, off):
        return ((cx + rad * ca - off * sa) * 4, (cy + rad * sa + off * ca) * 4)
    mid = (r0 + r1) / 2
    shapes = {
        0: [(pt(r0, 0), pt(r1, 0)), (pt(mid, 0), pt(r1, 3)), (pt(mid, 0), pt(r1, -3))],
        1: [(pt(r0, -2.5), pt(r1, 2.5)), (pt(r0, 2.5), pt(r1, -2.5))],
        2: [(pt(r0, -2.5), pt(r1, 0)), (pt(r1, 0), pt(r0, 2.5)), (pt(r0, 2.5), pt(r0, -2.5))],
        3: [(pt(r0, 0), pt(r1, 0)), (pt(mid, -3), pt(mid, 3))],
    }[kind % 4]
    for p, q in shapes:
        dr.line([p, q], fill=255, width=5)
    arr = np.asarray(im.resize((n, n), Image.BOX), np.float32) / 255.0
    return layer(n, arr * a, color)


def ring_c(f):
    n, c = RING_PX, RING_PX / 2
    t = f / RING_FRAMES
    rng = random.Random(SEED + 3)
    img = canvas(n)
    over(img, blob(n, c, c, 80, 80, (40, 8, 6), 0.5, 0.7))
    breathe = 0.75 + 0.25 * math.sin(TAU * t)
    over(img, layer(n, ring_alpha(n, c, c, 70, 4.5, 3.5) * 0.28 * breathe, (200, 50, 10)))
    over(img, layer(n, ring_alpha(n, c, c, 72, 1.1, 0.9) * 0.9, (230, 80, 20)))
    over(img, layer(n, ring_alpha(n, c, c, 58, 0.9, 0.8) * 0.75, (190, 55, 14)))
    over(img, layer(n, ring_alpha(n, c, c, 40, 0.8, 0.7) * 0.4, (150, 40, 12)))
    turn = TAU * t / 6.0
    for i in range(12):
        ang = TAU * i / 12 + turn
        glow = 0.55 + 0.45 * math.sin(TAU * (t + i / 12.0))
        over(img, rune(n, c, c, ang, 60, 70, i, (255, int(110 + 70 * glow), 40), 0.55 + 0.4 * glow))
    for i in range(6):
        ang = TAU * i / 6 - turn * 2
        x0, y0 = c + 12 * math.cos(ang), c + 12 * math.sin(ang)
        x1, y1 = c + 40 * math.cos(ang), c + 40 * math.sin(ang)
        im = Image.new('L', (n * 4, n * 4), 0)
        ImageDraw.Draw(im).line([(x0 * 4, y0 * 4), (x1 * 4, y1 * 4)], fill=255, width=4)
        over(img, layer(n, np.asarray(im.resize((n, n), Image.BOX), np.float32) / 255.0 * 0.35, (200, 60, 15)))
    for (a0, jit, ph, sp, drift, size) in rising(rng, 38):
        p = (ph + t) % 1.0
        rad = 20 + (a0 % 1.0) * 52
        x = c + rad * math.cos(a0) + drift * 1.4 * p
        y = c + rad * math.sin(a0) - 40 * p
        a = math.sin(math.pi * p) ** 0.7
        hot = max(0.0, 1 - p * 2.2)
        over(img, blob(n, x, y, size * 1.1, size * 1.1, (170, 160, 150), a * 0.8 * (1 - hot), 1.0))
        if hot > 0:
            over(img, ember(n, x, y, size * 0.9, 1 - hot, a * hot))
    # a steady drift of grey ash flakes over the whole ring area (small, thin, never more than a few percent of the area)
    for i in range(34):
        r_ = 78 * math.sqrt(rng.random())
        a0 = rng.random() * TAU
        ph, drift, size = rng.random(), rng.uniform(-8, 8), rng.uniform(1.0, 1.7)
        p = (ph + t) % 1.0
        x = c + r_ * math.cos(a0) + drift * math.sin(TAU * p + i)
        y = c + r_ * math.sin(a0) - 30 * p + 12
        a = math.sin(math.pi * p) * 0.6
        g = int(140 + 40 * ((i * 37) % 5) / 4)
        over(img, blob(n, x, y, size * 1.2, size * 0.8, (g, g - 4, g - 8), a, 0.8))
    # a few slow glowing cinders
    for i in range(5):
        a0 = rng.random() * TAU
        r_ = 20 + rng.random() * 54
        ph, size = rng.random(), rng.uniform(2.0, 2.8)
        p = (ph + t) % 1.0
        x = c + r_ * math.cos(a0) + 4 * math.sin(TAU * p + i)
        y = c + r_ * math.sin(a0) - 18 * p
        glow = 0.6 + 0.4 * math.sin(TAU * (t * 2 + i / 5.0))
        over(img, ember(n, x, y, size, 0.2 + 0.3 * glow, math.sin(math.pi * p) * glow))
    # sparks that pop from the rune ring now and then: a short arc, a hot yellow-white head fading to orange
    for i in range(7):
        a0 = TAU * (i * 0.3819 + 0.11) % TAU
        ph = (i * 0.143 + 0.05) % 1.0
        q = ((t - ph) % 1.0) / 0.3
        if q >= 1.0:
            continue
        ox, oy = c + 70 * math.cos(a0), c + 70 * math.sin(a0)
        vx, vy = 16 * math.cos(a0) + 5 * math.sin(i), -22 + 10 * math.sin(a0)
        for k in range(4):                       # head and a fading trail along the arc
            qq = q - k * 0.07
            if qq < 0:
                continue
            x = ox + vx * qq
            y = oy + vy * qq + 38 * qq * qq
            fade = (1 - q) ** 0.8 * (1 - k * 0.25)
            col_t = max(0.0, 1 - q * 1.6) * (1 - k * 0.3)
            over(img, blob(n, x, y, 3.2 - 0.6 * k, 3.2 - 0.6 * k, (255, int(120 + 135 * col_t), int(30 + 190 * col_t * col_t)),
                           min(1.0, fade * 1.3), 0.9))
    return img


# ---------------------------------------------------------------- burns (frames of BURN_PX, loop of BURN_FRAMES = one second tick)
def burn_1(f):
    n, c = BURN_PX, BURN_PX / 2
    t = f / BURN_FRAMES
    rng = random.Random(SEED + 11)
    img = canvas(n)
    pulse = 0.85 + 0.15 * math.sin(TAU * t)
    # heat glow over the whole body, then a hotter patch low on it
    over(img, blob(n, c, c + 2, 20, 17, (255, 110, 30), 0.38 * pulse, 1.0))
    over(img, blob(n, c, c + 8, 17, 9, (255, 160, 50), 0.55 * pulse, 1.1))
    for i in range(20):
        x0 = c + rng.uniform(-12, 12)
        ph, sp, dr, size = rng.random(), 1.0, rng.uniform(-5, 5), rng.uniform(1.5, 2.4)
        p = (ph + t * sp) % 1.0
        x = x0 + dr * math.sin(TAU * p)
        y = c + 10 - 38 * p
        over(img, ember(n, x, y, size * (1 - 0.4 * p), p, min(1.0, math.sin(math.pi * min(1, p * 1.1)) * 1.3)))
    for i in range(10):
        x0 = c + rng.uniform(-11, 11)
        ph, dr, size = rng.random(), rng.uniform(-6, 6), rng.uniform(1.6, 2.4)
        p = (ph + t) % 1.0
        x = x0 + dr * p
        y = c - 10 + 24 * p * p + 8 * p
        a = min(1.0, math.sin(math.pi * min(1, p * 1.2)) * 1.2)
        over(img, blob(n, x, y, size * 1.5, size * 1.3, (210, 80, 25), a * 0.7, 0.8))
        over(img, blob(n, x, y, size * 1.2, size, (24, 18, 16), a, 0.5))
    # ash flakes peeling up with the embers: light grey, slow, a little sideways
    for i in range(9):
        x0 = c + rng.uniform(-12, 12)
        ph, dr, size = rng.random(), rng.uniform(-6, 6), rng.uniform(1.3, 2.0)
        p = (ph + t) % 1.0
        x = x0 + dr * math.sin(TAU * p + i)
        y = c + 4 - 32 * p
        a = math.sin(math.pi * p) * 0.9
        over(img, blob(n, x, y, size * 1.4, size, (176, 170, 164), a, 0.7))
    # a small spark burst on the tick (frames 0-3): short arcs from the body, white-yellow heads fading to orange
    if t < 0.5:
        q0 = t / 0.5
        for i in range(10):
            a0 = TAU * (i / 10.0) + 0.3
            sp = 11 + 6 * ((i * 7) % 3)
            for k in range(3):
                q = q0 - k * 0.12
                if q < 0:
                    continue
                x = c + sp * q * math.cos(a0)
                y = c + 2 + sp * 0.8 * q * math.sin(a0) - 10 * q + 14 * q * q
                col_t = max(0.0, 1 - q0 * 1.5) * (1 - k * 0.3)
                over(img, blob(n, x, y, 2.0 - 0.4 * k, 2.0 - 0.4 * k,
                               (255, int(130 + 125 * col_t), int(40 + 180 * col_t * col_t)), min(1.0, (1 - q0) * 1.4), 0.9))
    return img


# ---------------------------------------------------------------- preview mocks
def ground(tiles, rng, scale=2):
    s = 32 * scale
    n = tiles * s
    yy, xx = np.mgrid[0:n, 0:n]
    tx, ty = xx // s, yy // s
    tone = np.array([[rng.uniform(-6, 6) for _ in range(tiles)] for _ in range(tiles)], np.float32)[ty, tx]
    jit = (((xx * 7 + yy * 13 + tx * 31 + ty * 17) % 11) - 5) * 0.9
    edge = ((xx % s == 0) | (yy % s == 0)) * -5.0
    base = np.array([88, 104, 84], np.float32)
    arr = base[None, None, :] + (tone + jit + edge)[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB')


def character(scale=2, monster=False):
    """a 32 x 32 placeholder; drawn at 4x then reduced; feet at y = 28"""
    k = 4
    im = Image.new('RGBA', (32 * k, 32 * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if monster:
        d.ellipse([6 * k, 12 * k, 26 * k, 29 * k], fill=(96, 52, 44, 255), outline=(40, 20, 18, 255), width=k)
        d.ellipse([9 * k, 5 * k, 23 * k, 18 * k], fill=(112, 62, 52, 255), outline=(40, 20, 18, 255), width=k)
        d.polygon([(10 * k, 7 * k), (8 * k, 1 * k), (13 * k, 6 * k)], fill=(200, 190, 160, 255))
        d.polygon([(22 * k, 7 * k), (24 * k, 1 * k), (19 * k, 6 * k)], fill=(200, 190, 160, 255))
        d.ellipse([12 * k, 10 * k, 15 * k, 13 * k], fill=(230, 200, 60, 255))
        d.ellipse([17 * k, 10 * k, 20 * k, 13 * k], fill=(230, 200, 60, 255))
    else:
        d.rectangle([10 * k, 4 * k, 22 * k, 15 * k], fill=(190, 150, 120, 255), outline=(40, 30, 28, 255), width=k)
        d.rectangle([9 * k, 3 * k, 23 * k, 8 * k], fill=(70, 70, 80, 255))
        d.rectangle([8 * k, 15 * k, 24 * k, 25 * k], fill=(88, 90, 104, 255), outline=(40, 40, 50, 255), width=k)
        d.rectangle([10 * k, 25 * k, 14 * k, 29 * k], fill=(60, 50, 44, 255))
        d.rectangle([18 * k, 25 * k, 22 * k, 29 * k], fill=(60, 50, 44, 255))
        d.rectangle([24 * k, 14 * k, 27 * k, 26 * k], fill=(150, 150, 160, 255))
    return im.resize((32 * scale, 32 * scale), Image.LANCZOS)


def to_image(arr, scale):
    a = np.clip(arr, 0, 1)
    im = Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA')
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


def combo(out, ring_fn=ring_c, burn_fn=burn_1):
    """ring and burn working together: 4 s at 12 fps, 7 x 7 tiles at 2x. Monsters within 2 sqm (Chebyshev) of the character burn
    once a second and show a damage number; the one outside nothing; at 3.0 s the character walks one tile right in 0.4 s."""
    from PIL import ImageFont
    scale, tiles, fps, secs = 2, 7, 12, 4
    s = 32 * scale
    rng = random.Random(SEED)
    bg = ground(tiles, rng, scale).convert('RGBA')
    char = character(scale, False)
    mon = character(scale, True)
    try:
        font = ImageFont.load_default(size=14)
    except TypeError:
        font = ImageFont.load_default()
    monsters = [(2, 3), (3, 5), (5, 2), (6, 3)]
    frames_im = []
    for i in range(fps * secs):
        t = i / fps
        walk = min(1.0, max(0.0, (t - 3.0) / 0.4))
        walk = walk * walk * (3 - 2 * walk)
        cxt = 3 + walk                       # character tile x (float)
        im = bg.copy()
        cx, cy = (cxt + 0.5) * s, 3.5 * s
        feet = cy + 12 * scale
        ring = to_image(ring_fn(i % RING_FRAMES), scale)
        im.alpha_composite(ring, (int(round(cx - ring.width / 2)), int(round(feet - ring.height / 2))))
        # draw back to front by row
        sprites = [(3.5 * s, 'p', cx)] + [((my + 0.5) * s, 'm', (mx, my)) for (mx, my) in monsters]
        phase = t % 1.0
        for _, kind, info in sorted(sprites, key=lambda e: e[0]):
            if kind == 'p':
                im.alpha_composite(char, (int(round(cx - char.width / 2)), int(round(feet - 28 * scale))))
                continue
            mx, my = info
            px, py = (mx + 0.5) * s, (my + 0.5) * s
            im.alpha_composite(mon, (int(px - mon.width / 2), int(py + 12 * scale - 28 * scale)))
            inside = max(abs(mx - 3), abs(my - 3)) <= 2      # the ring is fixed at the tick: the character's tile at the time
            if inside:
                art = to_image(burn_fn(phase * BURN_FRAMES), scale)
                im.alpha_composite(art, (int(px - art.width / 2), int(py - 4 * scale - art.height / 2)))
                d = ImageDraw.Draw(im)
                ty = py - 18 * scale - 18 * scale * phase
                a = int(255 * min(1.0, (1 - phase) * 2.2))
                txt = str(31 + (mx * 7 + my * 5) % 9)
                layer_ = Image.new('RGBA', im.size, (0, 0, 0, 0))
                ld = ImageDraw.Draw(layer_)
                ld.text((px - 9 * scale + 1, ty + 1), txt, font=font, fill=(20, 10, 5, a))
                ld.text((px - 9 * scale, ty), txt, font=font, fill=(255, 150, 40, a))
                im.alpha_composite(layer_)
        frames_im.append(im.convert('RGB'))
    w, h = frames_im[0].size
    show = (2, 14, 26, 40)       # 0.17 s, 1.17 s, 2.17 s (just after a tick: spark burst) and 3.3 s (walking)
    sheet = Image.new('RGB', (w * len(show), h))
    for k, f in enumerate(show):
        sheet.paste(frames_im[f], (k * w, 0))
    sheet.save(os.path.join(out, 'combo_C1.png'))
    frames_im[0].save(os.path.join(out, 'combo_C1.gif'), save_all=True, append_images=frames_im[1:], duration=1000 // fps,
                      loop=0)
    return [os.path.join(out, 'combo_C1.png'), os.path.join(out, 'combo_C1.gif')]



# ---------------------------------------------------------------- strips, files, check
def to_img(f):
    return Image.fromarray((np.clip(f, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA')


def strip(frames, n):
    st = Image.new('RGBA', (n * len(frames), n))
    for i, f in enumerate(frames):
        st.paste(to_img(f), (i * n, 0))
    return st


def build():
    """{(folder, name): strip image}"""
    return {
        ('pyre', 'ring'): strip([ring_c(i) for i in range(RING_FRAMES)], RING_PX),
        ('pyre', 'burn'): strip([burn_1(i) for i in range(BURN_FRAMES)], BURN_PX),
    }


def write(res, out):
    for (kind, key), st in res.items():
        os.makedirs(os.path.join(out, kind), exist_ok=True)
        st.save(os.path.join(out, kind, key + '.png'))


TOL = 2


def check(res, out):
    """the committed strips equal the generated ones (decoded pixels), and no other picture lies in the folder"""
    bad = []
    want = set()
    for (kind, key), st in res.items():
        path = os.path.join(out, kind, key + '.png')
        want.add(os.path.normpath(path))
        if not os.path.isfile(path):
            bad.append('%s/%s.png: missing' % (kind, key))
            continue
        have = Image.open(path).convert('RGBA')
        # a tolerance of TOL per channel: numpy's exp and arctan round differently on other CPUs (vector paths)
        if have.size != st.size or np.abs(np.asarray(have, np.int16) - np.asarray(st.convert('RGBA'), np.int16)).max() > TOL:
            bad.append('%s/%s.png: differs from the generator' % (kind, key))
    for kind in sorted(set(k for k, _ in res)):
        folder = os.path.join(out, kind)
        for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
            if os.path.normpath(os.path.join(folder, name)) not in want:
                bad.append('%s/%s: not made by the generator' % (kind, name))
    return bad


def main(argv):
    out = OUT
    args = list(argv)
    if '--out' in args and args.index('--out') + 1 < len(args):
        out = args[args.index('--out') + 1]
    if '--combo' in args and args.index('--combo') + 1 < len(args):
        d = args[args.index('--combo') + 1]
        os.makedirs(d, exist_ok=True)
        print('\n'.join(combo(d)))
        return 0
    if '-h' in args or '--help' in args:
        print(__doc__)
        return 0
    res = build()
    if '--check' in args:
        bad = check(res, out)
        for b in bad:
            print('gen_pyre_art --check:', b)
        if bad:
            return 1
        print('gen_pyre_art --check: %d strips up to date' % len(res))
        return 0
    write(res, out)
    print('wrote %d strips into %s' % (len(res), out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
