#!/usr/bin/env python3
"""The bolt from the sky, drawn by code (O614; joins client pair 73). Our own art: no art file is read, none is committed.

    python3 -I gen_lightning_fx.py sheets OUT_DIR              # PNG sheets of every variant and tint (never committed)
    python3 -I gen_lightning_fx.py preview OUT_DIR --dat D --spr S   # lightning.mp4 and lightning_ingame.mp4 on the game
                                                               # ground, effect 458 and a player beside (never committed)
    python3 -I gen_lightning_fx.py build DAT SPR OUT_DIR       # OUT_DIR gets Tibia.dat, Tibia.spr and strips/
    python3 -I gen_lightning_fx.py table                       # writes art_import/lightning_fx.csv and .sums
    python3 -I gen_lightning_fx.py ids [--check]               # server/data/lib/chaos_lightning_fx_ids.lua, the tags of
                                                               # spell_fx_elements.csv
    python3 -I gen_lightning_fx.py check                       # CI, no pair: the script draws the committed table and sums,
                                                               # the ids file and the tags are current
    python3 -I gen_lightning_fx.py live DAT SPR                # the pair holds every bolt at its id, pixel for pixel

Owner (2026-11-17): "For the lightning falling from the sky, make the tool to draw the lightning." The senders:
server/data/lib/chaos_lightning_fx.lua (README "Bolt from the sky (O614)").

The drawing, per variant (a seed and a size):
  channel   from a point high up and to the left of the target (the oblique view of the game: what falls from the sky
            comes from up-left, as effect 458 and the meteor do) to the standing point of the target tile, by midpoint
            displacement: each segment's middle is pushed sideways by a share of its length, a few times over.
  branches  leave the channel in its upper two thirds, run down and outward, end in the air and fade: the far part is
            thinner, the tip is only glow.
  frames    two leader frames (a thin stroke growing down), the strike (the full thick channel, every branch, the ground
            burst), a second strike on a slightly shaken channel, a dim frame, a re-strike, then the afterglow: the channel
            breaks into dashes, the last sparks land. 9 frames, the heavy bolt 10.
  ground    on the target tile: a flat burst (the floor is seen from above at an angle, so a circle is an ellipse half
            as high as wide) with spikes, a ring that runs out, and sparks thrown up that fall back.
  colours   one palette of four per tint: core, light, rim, glow. Alpha is 0 or 255 and ONE glow level, 144
            (docs/SPRITE_STYLE.md, the bar of the drawn wings, O581). No dark outline: a bolt is light, its saturated
            rim is what holds it against bright ground. A transparent pixel carries no colour.
  tints     energy (white and blue, the default). holy (gold) and dark (violet) are drawn by `sheets` and `preview`;
            no sender needs them today, so they are not in the pair.
  sizes     std: a 4 x 4 tile canvas, the target tile is the third of the bottom row (send offset 1, 0), the bolt comes in
            at the top, 116 px above the target point (measured in pair 72: effect 458 is 4 x 4 at 1, 1 and reaches 77 px
            above it, the level up pillar 457 is 4 x 5 at 1, 2 and reaches 56 px). heavy: 5 x 6 at 1, 1, 148 px, thicker,
            more branches, a wider burst, for boss strikes.
Everything is integer raster work on a seeded random.Random: the same bytes on every run.

Pair step: appended after the last effect of pair 73 (5320, the long beams of O609 after O613), so FIRST is 5321. The input pair
needs 253 missiles and 4,742 to 5,320 effects; one with fewer than 5,320 is padded with blank effects up to 5320, so the
ids are fixed whatever came before. This step runs last. No missile is added, nothing is replaced.

Needs numpy and Pillow (the fx venv of CI); `preview` needs ffmpeg.
"""
import argparse
import csv
import hashlib
import io
import math
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'lightning_fx.csv')
SUMS = os.path.join(ART, 'lightning_fx.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_lightning_fx_ids.lua')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')

MIN_EFFECTS, NEED_MISSILES = 4742, 253      # the input pair: pair 72 or later steps of pair 73
FIRST = 5321                                # 4743..5320 belong to the effect steps before (O596, O597, O606, O607, O609, O613)
LAST = 5340                                 # this step's block ends here
PAIR = 73
GLOW = 144                                  # the one glow level (docs/SPRITE_STYLE.md)
STAND = (16, 20)                            # the target point in the target tile: where a creature's feet are

# tint -> core, light, rim, glow
PALETTES = {
    'energy': ((255, 255, 255), (188, 226, 255), (58, 116, 246), (104, 166, 255)),
    'holy': ((255, 255, 236), (255, 232, 140), (226, 150, 34), (255, 204, 92)),
    'dark': ((250, 240, 255), (214, 170, 255), (122, 52, 204), (158, 98, 236)),
}
TAG = {'energy': 'energy', 'holy': 'holy', 'dark': 'death'}

# size -> canvas tiles, send offset, the frame script (kind, argument, ms), drawing numbers
SIZES = {
    'std': dict(w=4, h=4, dx=1, dy=0, thick=0, rx=12, forks=3, sparks=7, lean=0.56, depth=3,
                script=[('lead', 0.45, 50), ('lead', 0.9, 50), ('strike', 0, 80), ('strike2', 1, 70), ('dim', 0, 50),
                        ('restrike', 1, 70), ('ghost', 0, 70), ('ghost2', 0, 80), ('embers', 0, 90)]),
    'heavy': dict(w=5, h=6, dx=1, dy=1, thick=1, rx=17, forks=5, sparks=11, lean=0.58, depth=4,
                  script=[('lead', 0.4, 50), ('lead', 0.85, 50), ('strike', 0, 90), ('strike2', 1, 70), ('dim', 0, 50),
                          ('restrike', 2, 80), ('strike2', 1, 60), ('ghost', 0, 70), ('ghost2', 0, 80), ('embers', 0, 90)]),
}
FIELDS = ['kind', 'id', 'name', 'seed', 'tint', 'size', 'w', 'h', 'phases', 'durs', 'dx', 'dy', 'tag', 'note']

# (name, seed, tint, size, note): the effects of the pair, at FIRST.. in this order
VARIANTS = [
    ('lf_bolt_a', 11, 'energy', 'std', 'bolt from the sky, energy, first shape'),
    ('lf_bolt_b', 23, 'energy', 'std', 'bolt from the sky, energy, second shape'),
    ('lf_bolt_c', 37, 'energy', 'std', 'bolt from the sky, energy, third shape'),
    ('lf_bolt_heavy_a', 53, 'energy', 'heavy', 'heavy bolt from the sky, energy, first shape (boss strikes)'),
    ('lf_bolt_heavy_b', 71, 'energy', 'heavy', 'heavy bolt from the sky, energy, second shape (boss strikes)'),
]


def pieces():
    out = []
    for i, (name, seed, tint, size, note) in enumerate(VARIANTS):
        s = SIZES[size]
        out.append(dict(kind='effect', id=FIRST + i, name=name, seed=seed, tint=tint, size=size, w=s['w'], h=s['h'],
                        phases=len(s['script']), durs=';'.join(str(k[2]) for k in s['script']), dx=s['dx'], dy=s['dy'],
                        tag=TAG[tint], note=note))
    return out


def table_errors(rows):
    errs = []
    ids = [int(r['id']) for r in rows]
    if ids != list(range(FIRST, FIRST + len(ids))):
        errs.append('effect ids are not %d.. in order' % FIRST)
    if ids and ids[-1] > LAST:
        errs.append('effect ids past %d' % LAST)
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names) or any(not n.startswith('lf_') for n in names):
        errs.append('names: not unique or not lf_*')
    if len({(int(r['seed']), r['tint'], r['size']) for r in rows}) != len(rows):
        errs.append('two rows draw the same bolt')
    for r in rows:
        if r['tint'] not in PALETTES or r['size'] not in SIZES or r['tag'] != TAG.get(r['tint']):
            errs.append('%s: tint, size or tag' % r['name'])
            continue
        n = int(r['phases'])
        if not 6 <= n <= 10:
            errs.append('%s: 6 to 10 frames' % r['name'])
        if len(str(r['durs']).split(';')) != n:
            errs.append('%s: one duration per frame' % r['name'])
        if not (0 <= int(r['dx']) < int(r['w']) and 0 <= int(r['dy']) < int(r['h'])):
            errs.append('%s: the send offset is not in the canvas' % r['name'])
    return errs


def pair_ok(effects, missiles):
    return MIN_EFFECTS <= effects < FIRST and missiles == NEED_MISSILES


def pads(effects):
    """how many blank effects come before FIRST on a pair with this many effects"""
    return FIRST - 1 - effects


# ------------------------------------------------------------------------------------------------- the drawing
def rng(seed, salt):
    return random.Random(seed * 7919 + salt)


def target(size):
    """the target point on the canvas: STAND of the target tile"""
    s = SIZES[size]
    return (s['w'] - 1 - s['dx']) * 32 + STAND[0], (s['h'] - 1 - s['dy']) * 32 + STAND[1]


def displace(rnd, pts, rough, depth):
    """midpoint displacement: every segment's middle moves sideways by up to rough * its length, depth times"""
    for _ in range(depth):
        new = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dy) or 1.0
            off = (rnd.random() * 2 - 1) * rough * ln
            new.append(((a[0] + b[0]) / 2 - dy / ln * off, (a[1] + b[1]) / 2 + dx / ln * off))
            new.append(b)
        pts = new
    return pts


def clamp_pts(pts, W, H, margin):
    return [(min(max(x, margin), W - 1 - margin), min(max(y, 1), H - 2)) for x, y in pts]


def line_px(a, b):
    """Bresenham, both ends included"""
    x0, y0, x1, y1 = int(round(a[0])), int(round(a[1])), int(round(b[0])), int(round(b[1]))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    out = []
    while True:
        out.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return out
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def path_px(pts):
    """the pixels of a polyline in order, none twice in a row"""
    out = []
    for a, b in zip(pts, pts[1:]):
        for p in line_px(a, b):
            if not out or out[-1] != p:
                out.append(p)
    return out


def shape(seed, size):
    """the geometry of a variant: channel pixels (two more shaken copies), branches, burst spikes, sparks"""
    s = SIZES[size]
    W, H = s['w'] * 32, s['h'] * 32
    tx, ty = target(size)
    rnd = rng(seed, 1)
    top = (tx - s['lean'] * (ty - 1) + (rnd.random() * 2 - 1) * 5, 1.0)
    margin = 4 + s['thick']
    pts = displace(rnd, [top, (float(tx), float(ty))], 0.26, s['depth'])
    above = [i for i, p in enumerate(pts[:-2]) if p[1] < 1]      # the bolt comes in where it last crosses the top
    pts = clamp_pts(pts[above[-1] if above else 0:], W, H, margin)
    pts[-1] = (float(tx), float(ty))
    shaken = []
    for k in (2, 3):                                             # the same channel, shaken by a pixel or two
        r2 = rng(seed, k)
        q = [pts[0]] + [(x + (r2.random() * 2 - 1) * 1.6, y + (r2.random() * 2 - 1) * 1.2) for x, y in pts[1:-1]] + [pts[-1]]
        shaken.append(path_px(clamp_pts(q, W, H, margin)))
    branches = []
    rb = rng(seed, 4)
    n = len(pts)
    for i in range(s['forks']):
        at = int(n * (0.12 + 0.56 * (i + rb.random() * 0.8) / s['forks']))
        a, b = pts[at], pts[min(at + 1, n - 1)]
        base = math.atan2(b[1] - a[1], b[0] - a[0])
        side = 1 if i % 2 == 0 else -1
        ang = base + side * math.radians(28 + rb.random() * 30)
        ln = (0.3 + rb.random() * 0.2) * (ty - 1) * (1.0 - 0.4 * at / n)
        end = (a[0] + math.cos(ang) * ln, a[1] + abs(math.sin(ang)) * ln * 0.9 + ln * 0.15)
        bp = clamp_pts(displace(rb, [a, end], 0.3, 2), W, H, 3)
        bp = [p for p in bp if p[1] < ty - 14]                   # a branch ends in the air, above the ground burst
        if len(bp) >= 3:
            branches.append(path_px(bp))
    rs = rng(seed, 5)
    spikes = []
    for i in range(8):
        ang = (i + rs.random() * 0.7) * math.pi / 4
        spikes.append((ang, s['rx'] + 3 + rs.random() * 6))
    sparks = []
    for i in range(s['sparks']):
        ang = (i + rs.random()) * 2 * math.pi / s['sparks']
        sparks.append((ang, 2.2 + rs.random() * 2.3, 2.6 + rs.random() * 2.6))
    return dict(W=W, H=H, T=(tx, ty), main=path_px(pts), shaken=shaken, branches=branches, spikes=spikes, sparks=sparks,
                size=size, seed=seed)


def mask_of(pixels, W, H):
    import numpy as np
    m = np.zeros((H, W), bool)
    for x, y in pixels:
        if 0 <= x < W and 0 <= y < H:
            m[y, x] = True
    return m


def shift(m, dx, dy):
    import numpy as np
    out = np.zeros_like(m)
    H, W = m.shape
    out[max(0, dy):H + min(0, dy), max(0, dx):W + min(0, dx)] = m[max(0, -dy):H + min(0, -dy), max(0, -dx):W + min(0, -dx)]
    return out


def grow(m, n=1):
    """n rounds of growth, the 4 neighbours and the 8 neighbours in turn (a round corner)"""
    for i in range(n):
        g = m | shift(m, 1, 0) | shift(m, -1, 0) | shift(m, 0, 1) | shift(m, 0, -1)
        if i % 2:
            g |= shift(m, 1, 1) | shift(m, -1, 1) | shift(m, 1, -1) | shift(m, -1, -1)
        m = g
    return m


def fat(m):
    """a 1 px stroke made 2 px"""
    return m | shift(m, 1, 0)


def ellipse(W, H, cx, cy, rx):
    """a circle of radius rx on the floor, seen at the game's angle: half as high as wide"""
    import numpy as np
    if rx <= 0:
        return np.zeros((H, W), bool)
    ys, xs = np.indices((H, W))
    return (xs - cx) ** 2 * 1 + (ys - cy) ** 2 * 4 <= rx * rx


def paint(img, m, colour, alpha=255):
    img[m, 0], img[m, 1], img[m, 2], img[m, 3] = colour[0], colour[1], colour[2], alpha


def stroke(img, pal, pixels, level):
    """a stroke of the channel: level 0 a thin rim-coloured line .. 4 the thick strike with its glow"""
    core, light, rim, glow = pal
    H, W = img.shape[:2]
    line = mask_of(pixels, W, H)
    if level <= 0:
        paint(img, line, rim)
    elif level == 1:                                             # dim: a light line in a rim
        paint(img, grow(line, 1), rim)
        paint(img, line, light)
    elif level == 2:                                             # re-strike
        body = grow(line, 1)
        paint(img, grow(body, 2) & ~body, glow, GLOW)
        paint(img, body, rim)
        paint(img, line, core)
    else:                                                        # the strike, level - 3 px thicker
        white = fat(line) if level == 3 else grow(line, level - 3)
        body = grow(white, 1)
        edge = grow(body, 1)
        paint(img, grow(edge, 2) & ~edge, glow, GLOW)
        paint(img, edge, rim)
        paint(img, body, light)
        paint(img, white, core)


def branch(img, pal, pixels, level):
    """a branch: level 2 full (white near the channel, a rim line further out, a glow tip), 1 fading, 0 the first half"""
    core, light, rim, glow = pal
    H, W = img.shape[:2]
    n = len(pixels)
    if level == 0:
        paint(img, mask_of(pixels[:n // 2], W, H), rim)
        return
    near, far, tip = pixels[:int(n * 0.45)], pixels[int(n * 0.45):int(n * 0.8)], pixels[int(n * 0.8):]
    if level == 1:
        paint(img, mask_of(near + far, W, H), glow, GLOW)
        return
    nm = mask_of(near, W, H)
    paint(img, grow(mask_of(near + far, W, H), 1), glow, GLOW)
    paint(img, mask_of(tip, W, H), glow, GLOW)
    paint(img, fat(nm) | shift(nm, 0, 1), rim)
    paint(img, mask_of(far, W, H), rim)
    paint(img, nm, light)


def burst(img, pal, sh, kind):
    """the ground under the strike"""
    import numpy as np
    core, light, rim, glow = pal
    H, W = img.shape[:2]
    cx, cy = sh['T']
    rx = SIZES[sh['size']]['rx']

    def ring(r, width=2):
        return ellipse(W, H, cx, cy, r) & ~ellipse(W, H, cx, cy, r - width)

    if kind == 'strike':
        paint(img, ellipse(W, H, cx, cy, rx + 4), glow, GLOW)
        sp = np.zeros((H, W), bool)
        for ang, ln in sh['spikes']:
            sp |= mask_of(line_px((cx, cy), (cx + math.cos(ang) * ln, cy + math.sin(ang) * ln * 0.5)), W, H)
        paint(img, grow(sp, 1) & ~ellipse(W, H, cx, cy, rx), rim)
        paint(img, ellipse(W, H, cx, cy, rx), rim)
        paint(img, ellipse(W, H, cx, cy, rx - 2), light)
        paint(img, sp, light)
        paint(img, ellipse(W, H, cx, cy, rx - 5), core)
    elif kind == 'strike2':
        paint(img, ellipse(W, H, cx, cy, rx + 3), glow, GLOW)
        paint(img, ring(rx + 4, 3), rim)
        paint(img, ring(rx + 3, 2), light)
        paint(img, ellipse(W, H, cx, cy, rx - 5), light)
        paint(img, ellipse(W, H, cx, cy, rx - 8), core)
    elif kind == 'dim':
        paint(img, ellipse(W, H, cx, cy, rx - 4), glow, GLOW)
        paint(img, ring(rx + 6, 2), rim)
    elif kind == 'restrike':
        paint(img, ellipse(W, H, cx, cy, rx - 1), glow, GLOW)
        paint(img, ellipse(W, H, cx, cy, rx - 5), rim)
        paint(img, ellipse(W, H, cx, cy, rx - 7), core)
        paint(img, ring(rx + 8, 2), glow, GLOW)
    elif kind == 'ghost':
        ys, xs = np.indices((H, W))
        dash = ((np.arctan2((ys - cy) * 2.0, xs - cx) + math.pi) * 6 / math.pi).astype(int) % 2 == 0
        paint(img, ring(rx + 9, 2) & dash, glow, GLOW)
        paint(img, ellipse(W, H, cx, cy, rx - 6), glow, GLOW)
    elif kind == 'ghost2':
        paint(img, ellipse(W, H, cx, cy, rx - 8), glow, GLOW)


def sparks(img, pal, sh, t):
    """sparks thrown up by the strike, t frames after it; one is gone when it lands"""
    core, light, rim, glow = pal
    H, W = img.shape[:2]
    cx, cy = sh['T']

    def at(a, v, vz, k):
        z = vz * k - 0.65 * k * k
        return (int(round(cx + math.cos(a) * v * k)), int(round(cy + math.sin(a) * v * k * 0.5 - z))), z

    for a, v, vz in sh['sparks']:
        p, z = at(a, v, vz, t)
        if t <= 0 or z < 0 or not (1 <= p[0] < W - 1 and 1 <= p[1] < H - 1):
            continue
        q, _ = at(a, v, vz, t - 0.6)
        if q != p and 0 <= q[0] < W and 0 <= q[1] < H:
            img[q[1], q[0]] = glow + (GLOW,)
        img[p[1], p[0]] = (core if t <= 2 else light if t <= 4 else rim) + (255,)


def dashes(pixels, seed, salt, keep):
    """the channel broken up: runs of 3 to 7 px, a share `keep` of them stays"""
    rnd = rng(seed, salt)
    out, i = [], 0
    while i < len(pixels):
        n = 3 + int(rnd.random() * 5)
        if rnd.random() < keep:
            out.extend(pixels[i:i + n])
        i += n
    return out


def draw_frame(sh, tint, f):
    """frame f of a variant: uint8 RGBA H x W"""
    import numpy as np
    pal = PALETTES[tint]
    core, light, rim, glow = pal
    s = SIZES[sh['size']]
    kind, arg, _ms = s['script'][f]
    strike_at = next(i for i, k in enumerate(s['script']) if k[0] == 'strike')
    img = np.zeros((sh['H'], sh['W'], 4), np.uint8)
    main = sh['main']
    if kind == 'lead':
        part = main[:max(2, int(len(main) * arg))]
        if arg > 0.6:
            for b in sh['branches']:
                branch(img, pal, b, 0)
        stroke(img, pal, part, 0)
        paint(img, mask_of(part[int(len(part) * 0.7):], sh['W'], sh['H']), light)
        tip = mask_of(part[-2:], sh['W'], sh['H'])
        paint(img, grow(tip, 1) & ~tip, glow, GLOW)
        paint(img, tip, core)
    elif kind == 'strike':
        burst(img, pal, sh, 'strike')
        for b in sh['branches']:
            branch(img, pal, b, 2)
        stroke(img, pal, main, 3 + s['thick'])
    elif kind == 'strike2':
        burst(img, pal, sh, 'strike2')
        for b in sh['branches']:
            branch(img, pal, b, 1)
        stroke(img, pal, sh['shaken'][arg - 1], 2 + s['thick'])
    elif kind == 'dim':
        burst(img, pal, sh, 'dim')
        stroke(img, pal, main, 1 if s['thick'] else 0)
    elif kind == 'restrike':
        burst(img, pal, sh, 'restrike')
        stroke(img, pal, sh['shaken'][arg - 1], 2 + s['thick'])
    elif kind == 'ghost':
        burst(img, pal, sh, 'ghost')
        d = mask_of(dashes(main, sh['seed'], 6, 0.6), sh['W'], sh['H'])
        paint(img, grow(d, 1) & ~d, glow, GLOW)
        paint(img, d, rim)
    elif kind == 'ghost2':
        burst(img, pal, sh, 'ghost2')
        paint(img, mask_of(dashes(main, sh['seed'], 7, 0.3), sh['W'], sh['H']), glow, GLOW)
    sparks(img, pal, sh, f - strike_at)
    img[img[..., 3] == 0] = 0
    return img


def frames(seed, tint, size):
    sh = shape(seed, size)
    return [draw_frame(sh, tint, f) for f in range(len(SIZES[size]['script']))]


def strip_of(fr):
    import numpy as np
    return np.ascontiguousarray(np.concatenate(fr, axis=1))


def digest(strip):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


def build_rows():
    """[(row, strip)] of the pair's variants"""
    out = []
    for r in pieces():
        out.append((r, strip_of(frames(r['seed'], r['tint'], r['size']))))
    return out


def art_errors(strip, r):
    """the bar a bolt is held to (the test and `check`): frames, alpha, palette, the channel reaches the target tile"""
    import numpy as np
    errs = []
    s = SIZES[r['size']]
    W, H = s['w'] * 32, s['h'] * 32
    n = len(s['script'])
    if strip.shape != (H, W * n, 4):
        return ['%s: strip shape' % r['name']]
    if not set(np.unique(strip[..., 3]).tolist()) <= {0, GLOW, 255}:
        errs.append('%s: an alpha other than 0, %d, 255' % (r['name'], GLOW))
    if strip[strip[..., 3] == 0].any():
        errs.append('%s: a transparent pixel carries a colour' % r['name'])
    cols = {tuple(c) for c in strip[strip[..., 3] > 0][:, :3].tolist()}
    if not cols <= set(PALETTES[r['tint']]):
        errs.append('%s: a colour outside the palette' % r['name'])
    tx, ty = target(r['size'])
    x0, y0 = tx - STAND[0], ty - STAND[1]
    for f in range(n):
        a = strip[:, f * W:(f + 1) * W, 3]
        if not a.any():
            errs.append('%s: frame %d is empty' % (r['name'], f))
        if a[-1].any() or a[:, 0].any() or a[:, -1].any():              # the top is the sky: the bolt comes in there
            errs.append('%s: frame %d touches the left, right or bottom edge of the canvas' % (r['name'], f))
    k = next(i for i, e in enumerate(s['script']) if e[0] == 'strike')
    solid = strip[:, k * W:(k + 1) * W, 3] == 255
    seen = np.zeros_like(solid)
    todo = [(y, x) for y in range(0, 6) for x in range(W) if solid[y, x]]
    for p in todo:
        seen[p] = True
    while todo:                                                  # the strike is one piece from the sky to the tile
        y, x = todo.pop()
        for yy in (y - 1, y, y + 1):
            for xx in (x - 1, x, x + 1):
                if 0 <= yy < H and 0 <= xx < W and solid[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    todo.append((yy, xx))
    if not seen[y0:y0 + 32, x0:x0 + 32].any() or not seen[ty, tx]:
        errs.append('%s: the strike does not reach the target tile from the sky' % r['name'])
    return errs


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    n = len(rows)
    w.writerow(dict(kind='total', id=n, name='effects_%d_%d' % (FIRST, FIRST + n - 1),
                    note='this step appends exactly %d effects at %d.. after blank effects up to %d and no missile; '
                         'its block ends at %d' % (n, FIRST, FIRST - 1, LAST)))
    return buf.getvalue()


def sums_text(pairs):
    return ''.join('%s  %s\n' % (digest(s), r['name']) for r, s in pairs)


def read_spec():
    with open(SPEC, newline='') as fh:
        return [r for r in csv.DictReader(fh) if r['kind'] != 'total']


def read_total():
    with open(SPEC, newline='') as fh:
        return [int(r['id']) for r in csv.DictReader(fh) if r['kind'] == 'total']


def read_sums():
    return dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))


def table():
    pairs = build_rows()
    for p, t in ((SPEC, spec_text([r for r, _ in pairs])), (SUMS, sums_text(pairs))):
        open(p, 'w', newline='').write(t)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


# ------------------------------------------------------------------------------------------------- the pair
def import_spec(path, strips, first, pairs):
    """the spec import_fx_art.py reads: blank effects from `first` up to FIRST - 1, then the bolts"""
    import numpy as np
    from PIL import Image
    blank = os.path.join(strips, 'lf_blank.png')
    Image.fromarray(np.zeros((32, 32, 4), np.uint8)).save(blank, optimize=False)
    with open(path, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs', 'lua', 'blank'])
        for i in range(first, FIRST):
            w.writerow(['', 'effect', 'lf_pad_%d' % i, blank, 1, 1, 1, 83, 0, 0, 'blank', 'soft', '', '', 1])
        for r, s in pairs:
            f = os.path.join(strips, r['name'] + '.png')
            Image.fromarray(np.ascontiguousarray(s)).save(f, optimize=False)
            w.writerow(['', 'effect', r['name'], f, r['w'], r['h'], r['phases'], str(r['durs']).split(';')[0], r['dx'], r['dy'],
                        r['note'], 'soft', r['durs'], '', ''])


def build(dat, spr, out):
    sys.path.insert(0, HERE)
    from datspr import Dat
    d = Dat(dat)
    if not pair_ok(len(d.effects), len(d.missiles)):
        sys.exit('refused: the input pair has %d effects and %d missiles, this step needs %d to %d effects and %d missiles '
                 '(pair 72 or the earlier steps of pair 73)' % (len(d.effects), len(d.missiles), MIN_EFFECTS, FIRST - 1,
                                                                NEED_MISSILES))
    if check(quiet=True):
        sys.exit('refused: `check` fails (the table, the sums or the ids file are not current)')
    pairs = build_rows()
    strips = os.path.join(os.path.abspath(out), 'strips')
    os.makedirs(strips, exist_ok=True)
    spec = os.path.join(strips, 'import.csv')
    first = len(d.effects) + 1
    import_spec(spec, strips, first, pairs)
    cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', dat, '--ours-spr', spr, '--out-dir', out,
           '--spec', spec, '--expect-first-effect', str(first), '--keep-donor-names']
    if subprocess.run(cmd).returncode:
        sys.exit('import_fx_art.py failed')
    for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv'):                # this step's ids come from the table
        p = os.path.join(out, f)
        if os.path.exists(p):
            os.remove(p)
    print('lightning fx: %d blank effects %d..%d, then %d effects %d..%d' % (
        pads(len(d.effects)), first, FIRST - 1, len(pairs), FIRST, FIRST + len(pairs) - 1))
    return live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))


def live(dat_path, spr_path):
    """the pair holds each bolt at its id: size, phases, durations and the pixels of the sums"""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_vfx import render_back
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_spec()
    sums = read_sums()
    errs = []
    n = len(rows)
    if len(dat.effects) < FIRST + n - 1 or len(dat.missiles) != NEED_MISSILES:
        errs.append('the pair has %d effects and %d missiles' % (len(dat.effects), len(dat.missiles)))
    for r in rows if not errs else []:
        t = dat.effects[int(r['id']) - 1]
        ph, w, h = int(r['phases']), int(r['w']), int(r['h'])
        if (t.w, t.h, t.phases) != (w, h, ph):
            errs.append('%s: size or phases differ at %s' % (r['name'], r['id']))
            continue
        durs = [int(v) for v in r['durs'].split(';')]
        if not t.anim or list(t.anim[3]) != [v for v in durs for _ in (0, 1)]:       # the dat holds min, max per phase
            errs.append('%s: durations differ' % r['name'])
        back = render_back(t, spr, 1)
        strip = np.concatenate([back[(f, 0, 0, 0)] for f in range(ph)], axis=1).copy()
        strip[strip[..., 3] == 0] = 0
        if digest(strip) != sums.get(r['name']):
            errs.append('%s: pixels differ from the sum' % r['name'])
    for e in errs:
        print(e)
    print('lightning fx live: %d effects at %d..%d, %s' % (n, FIRST, FIRST + n - 1, 'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


# ------------------------------------------------------------------------------------------------- server files
def lua_text(rows):
    L = ['-- GENERATED by client/tools/sprites/gen_lightning_fx.py from art_import/lightning_fx.csv (O614). Do not edit by hand.',
         '-- The bolt from the sky, drawn by code (our own art), in client pair %d: %d effects at the ids %d..%d, after the' % (
             PAIR, len(rows), FIRST, FIRST + len(rows) - 1),
         '-- last effect of the steps before (%d). No projectile.' % (FIRST - 1),
         '-- dx, dy: the send offset (the bottom-right tile of the art is the target tile + dx, dy); ms: the whole play.',
         '-- A plain table: data/lib/chaos_lightning_fx.lua sends these ids only when config.lua chaosClientPair is %d or more,' % PAIR,
         '-- so a server on an older pair never sends one.',
         'ChaosLightningFxIds = {',
         '\tpair = %d, first = %d, count = %d,' % (PAIR, FIRST, len(rows)),
         '\teffects = {']
    for r in rows:
        L.append('\t\t%s = {id = %s, dx = %s, dy = %s, ms = %d, tint = "%s", size = "%s"},  -- %s' % (
            r['name'], r['id'], r['dx'], r['dy'], sum(int(v) for v in str(r['durs']).split(';')), r['tint'], r['size'], r['note']))
    L += ['\t},', '}']
    return '\n'.join(L) + '\n'


def tags_text(rows):
    """spell_fx_elements.csv with this step's rows (id, name, element) in id order, the other rows as they are"""
    with open(TAGS, encoding='utf-8', newline='') as fh:
        keep = [l for l in fh.read().splitlines() if not l.split(',')[1:2] or not l.split(',')[1].startswith('lf_')]
    mine = ['%s,%s,%s' % (r['id'], r['name'], r['tag']) for r in rows if r['tag']]
    return '\n'.join(keep[:1] + sorted(keep[1:] + mine, key=lambda l: int(l.split(',')[0]))) + '\n'


def ids(check_only, quiet=False):
    rows = read_spec()
    want = {LUA: lua_text(rows), TAGS: tags_text(rows)}
    if check_only:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            if not quiet:
                print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_lightning_fx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


def check(quiet=False):
    errs = table_errors(pieces())
    rows = read_spec() if os.path.exists(SPEC) else []
    if [[str(r[k]) for k in FIELDS] for r in pieces()] != [[r[k] for k in FIELDS] for r in rows]:
        errs.append('art_import/lightning_fx.csv is not the table of the script (run gen_lightning_fx.py table)')
    n = len(rows)
    if not rows or read_total() != [n]:
        errs.append('lightning_fx.csv: the total row does not record the %d effects' % n)
    try:
        import numpy  # noqa: F401
    except ImportError:
        print('lightning fx: numpy missing, the drawing is not checked against the sums')
    else:
        pairs = build_rows()
        for r, s in pairs:
            errs += art_errors(s, r)
        if not os.path.exists(SUMS) or open(SUMS).read() != sums_text(pairs):
            errs.append('lightning_fx.sums is not what the script draws (run gen_lightning_fx.py table after a wanted change)')
    bad = ids(True, quiet) if rows else 1
    if not quiet:
        for e in errs:
            print(e)
        print('lightning fx: %d effects %d..%d, %s' % (n, FIRST, FIRST + n - 1, 'OK' if not errs and not bad else 'PROBLEMS'))
    return 1 if errs or bad else 0


# ------------------------------------------------------------------------------------------------- sheets and previews
def all_variants():
    """the pair's variants, then the tints no sender uses yet (one std and one heavy bolt each)"""
    out = [(n, s, t, z) for n, s, t, z, _ in VARIANTS]
    for tint in ('holy', 'dark'):
        out += [('lf_bolt_%s' % tint, 11, tint, 'std'), ('lf_bolt_heavy_%s' % tint, 53, tint, 'heavy')]
    return out


def flat(rgb, W, H):
    import numpy as np
    g = np.empty((H, W, 3), np.float64)
    g[:] = rgb
    return g


def over(dst, src, x=0, y=0):
    """alpha blend src (RGBA uint8) on dst (RGB float) at x, y; parts outside are dropped"""
    H, W = dst.shape[:2]
    h, w = src.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + w), min(H, y + h)
    if x0 >= x1 or y0 >= y1:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]
    a = s[..., 3:4].astype('float64') / 255.0
    dst[y0:y1, x0:x1] = dst[y0:y1, x0:x1] * (1 - a) + s[..., :3] * a


def upscale(img, k):
    import numpy as np
    return np.repeat(np.repeat(img, k, axis=0), k, axis=1)


def sheets(out_dir):
    """one PNG per variant: the frames on dark, on grass green and on stone grey, 2x; and all strike frames together"""
    import numpy as np
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    written = []
    strikes = []
    for name, seed, tint, size in all_variants():
        fr = frames(seed, tint, size)
        rows = []
        for bg in ((22, 22, 28), (62, 110, 48), (128, 126, 122)):
            row = flat(bg, fr[0].shape[1] * len(fr), fr[0].shape[0])
            for i, f in enumerate(fr):
                over(row, f, i * f.shape[1], 0)
            rows.append(row)
        p = os.path.join(out_dir, name + '.png')
        Image.fromarray(upscale(np.concatenate(rows, 0).astype(np.uint8), 2), 'RGB').save(p)
        written.append(p)
        k = next(i for i, e in enumerate(SIZES[size]['script']) if e[0] == 'strike')
        cell = flat((62, 110, 48), 160, 192)
        over(cell, fr[k], 160 - fr[k].shape[1], 192 - fr[k].shape[0])
        strikes.append(cell)
    p = os.path.join(out_dir, 'strikes.png')
    Image.fromarray(upscale(np.concatenate(strikes, 1).astype(np.uint8), 2), 'RGB').save(p)
    written.append(p)
    for p in written:
        print('wrote', p)
    return 0


def write_mp4(path, images, fps):
    import numpy as np
    h, w = images[0].shape[:2]
    assert w % 2 == 0 and h % 2 == 0, 'even sizes'
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (w, h),
           '-framerate', str(fps), '-i', '-', '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-crf', '18',
           '-movflags', '+faststart', path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for img in images:
        proc.stdin.write(np.ascontiguousarray(img).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit('ffmpeg failed for ' + path)


class Anim:
    """an effect as the client plays it: frames with a duration each, a canvas in tiles, a send offset"""

    def __init__(self, fr, durs, w, h, dx, dy):
        self.fr, self.durs, self.w, self.h, self.dx, self.dy = fr, durs, w, h, dx, dy
        self.total = sum(durs)

    def frame(self, ms):
        if ms < 0:
            return None
        for f, d in zip(self.fr, self.durs):
            if ms < d:
                return f
            ms -= d
        return None

    def draw(self, dst, tile_x, tile_y, ms):
        """on a scene whose tile (tile_x, tile_y) has its corner at tile * 32"""
        f = self.frame(ms)
        if f is not None:
            over(dst, f, (tile_x + self.dx - self.w + 1) * 32, (tile_y + self.dy - self.h + 1) * 32)


def drawn_anim(seed, tint, size):
    s = SIZES[size]
    return Anim(frames(seed, tint, size), [k[2] for k in s['script']], s['w'], s['h'], s['dx'], s['dy'])


def pair_anim(dat, spr, eid, dx, dy):
    from import_vfx import render_back
    t = dat.effects[eid - 1]
    back = render_back(t, spr, 1)
    durs = [(a + b) // 2 for a, b in zip(t.anim[3][0::2], t.anim[3][1::2])] if t.anim else [100] * t.phases
    return Anim([back[(f, 0, 0, 0)] for f in range(t.phases)], durs, t.w, t.h, dx, dy)


def ground_tiles(dat, spr):
    """(grass, stone): two full ground tiles of the pair, picked by their mean colour (the greenest, the most even grey)"""
    import numpy as np
    best = {}
    for t in dat.items[:6000]:
        if 'ground' not in t.flags or 'fullground' not in t.flags or (t.w, t.h, t.phases) != (1, 1, 1) or not t.sprites:
            continue
        a = spr.sprite(t.sprites[0])
        if a is None or (a[..., 3] < 255).any():
            continue
        r, g, b = (float(a[..., i].mean()) for i in range(3))
        var = float(a[..., :3].std())
        green = g - max(r, b) - var * 0.5
        grey = -abs(r - g) - abs(g - b) - abs(110 - g) * 0.3 - var * 0.5
        for key, score in (('grass', green), ('stone', grey)):
            if key not in best or score > best[key][0]:
                best[key] = (score, a[..., :3].astype(np.float64), t.id)
    return best['grass'][1], best['stone'][1]


def scene_ground(tile, cols, rows):
    import numpy as np
    return np.tile(tile, (rows, cols, 1))


def body_of(dat, spr, look):
    """a standing outfit, facing south, with the offset of its corner from the corner of its tile"""
    import numpy as np
    from datspr import render_outfit
    img = np.asarray(render_outfit(dat, spr, look).convert('RGBA'))
    t = dat.outfit(look)
    disp = tuple(t.flags.get('displacement', (0, 0)))
    return img, (32 - img.shape[1] - disp[0], 32 - img.shape[0] - disp[1])


def put_body(dst, body, tile_x, tile_y):
    img, (ox, oy) = body
    over(dst, img, tile_x * 32 + ox, tile_y * 32 + oy)


def preview(out_dir, dat_path, spr_path):
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    os.makedirs(out_dir, exist_ok=True)
    dat, spr = Dat(dat_path), Spr(spr_path)
    grass, stone = ground_tiles(dat, spr)
    player = body_of(dat, spr, 128)
    old = pair_anim(dat, spr, 458, 1, 1)
    step = 10                                                    # ms per video frame
    fps = 1000 // step

    # 1. the variants side by side, effect 458 first, on grass and on stone, a player on every target tile
    cols = [('458', old)] + [(n, drawn_anim(s, t, z)) for n, s, t, z in all_variants()]
    cw, ch = 6, 6                                                # tiles per cell; the target tile is (3, 4)
    span = max(a.total for _, a in cols) + 500
    seq = []
    for k in range(0, span * 2, step):
        ms = k % span - 250
        rows_ = []
        for tile in (grass, stone):
            row = scene_ground(tile, cw * len(cols), ch)
            for i, (_n, a) in enumerate(cols):
                put_body(row, player, i * cw + 3, 4)
                a.draw(row, i * cw + 3, 4, ms)
            rows_.append(row)
        img = np.concatenate(rows_, 0).astype(np.uint8)
        seq.append(img)
    slow = [f for f in seq for _ in range(3)]                    # a third of the speed: the frames can be read
    p1 = os.path.join(out_dir, 'lightning.mp4')
    write_mp4(p1, seq + slow, fps)

    # 2. as senders use it: a ring of four bolts round a caster among a monster pack (Doomtide, Glacial Doom), then a
    #    boss whose marks are struck (Thalcyra's Storm Marks), as data/lib/chaos_lightning_fx.lua picks the shapes
    std = [drawn_anim(s, t, z) for n, s, t, z in all_variants()[:3]]
    heavy = [drawn_anim(s, t, z) for n, s, t, z in all_variants()[3:5]]
    monster = body_of(dat, spr, 5)
    boss = body_of(dat, spr, 35)
    W, H = 17, 12
    seq = []
    for part, tile in (('pack', grass), ('boss', stone)):
        if part == 'pack':
            caster = (8, 6)
            mobs = [(4, 6), (12, 6), (8, 2), (8, 10), (5, 3), (11, 9)]
            hits = [(4, 6, 0), (8, 2, 60), (12, 6, 120), (8, 10, 180)]
            casts = [(300 + 900 * c, [(x, y, d, std[(i + c) % 3]) for i, (x, y, d) in enumerate(hits)]) for c in range(3)]
            bodies = [(player, caster)] + [(monster, m) for m in mobs]
        else:
            # a boss mark is 3 x 3 and its hit is drawn on every second tile; one strike in four is the heavy bolt
            marks = [(5, 6), (10, 8), (12, 5), (7, 9), (11, 7)]
            casts, k = [], 0
            for c in range(3):
                bolts = []
                for x, y in marks[c:c + 3]:
                    for ox, oy in ((-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)):
                        bolts.append((x + ox, y + oy, 0, heavy[(k // 4) % 2] if k % 4 == 0 else std[k % 3]))
                        k += 1
                casts.append((300 + 1100 * c, bolts))
            bodies = [(boss, (8, 3))] + [(player, m) for m in ((5, 6), (10, 8), (12, 5))]
        for ms in range(0, 3600, step):
            img = scene_ground(tile, W, H)
            for b, (x, y) in sorted(bodies, key=lambda e: e[1][1]):
                put_body(img, b, x, y)
            for t0, bolts in casts:
                for x, y, d, a in bolts:
                    a.draw(img, x, y, ms - t0 - d)
            seq.append(upscale(img.astype(np.uint8), 2))
    p2 = os.path.join(out_dir, 'lightning_ingame.mp4')
    write_mp4(p2, seq, fps)
    for p in (p1, p2):
        print('wrote', p, '%.1f MB' % (os.path.getsize(p) / 1e6))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['sheets', 'preview', 'build', 'table', 'ids', 'check', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'sheets':
        if len(a.rest) != 1:
            sys.exit('sheets OUT_DIR')
        return sheets(a.rest[0])
    if a.cmd == 'preview':
        if len(a.rest) != 1 or not a.dat or not a.spr:
            sys.exit('preview OUT_DIR --dat DAT --spr SPR')
        return preview(a.rest[0], a.dat, a.spr)
    if a.cmd == 'build':
        if len(a.rest) != 3:
            sys.exit('build DAT SPR OUT_DIR')
        return build(*a.rest)
    if a.cmd == 'table':
        return table()
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'live':
        if len(a.rest) != 2:
            sys.exit('live DAT SPR')
        return live(*a.rest)
    return check()


if __name__ == '__main__':
    sys.exit(main())
