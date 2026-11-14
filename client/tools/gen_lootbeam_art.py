#!/usr/bin/env python3
"""Art of the loot beams (O569; client/MANIFEST.md "Loot beams (O569)", module game_lootbeams).

Owner 2026-11-14 (pt-BR): "o loot beam parece que está em baixa qualidade. tente fazer novos pra ver se ficam melhores". The old
beam was a flat bar with a hard edge, a few square sparks and an orange oval. These are drawn from soft light instead: every
picture is a sum of smooth light fields (additive energy) turned into straight alpha, so nothing has a hard edge and the centre
burns towards white the way a real light does. Everything is drawn here from shapes and noise with a fixed seed (no reference
art, nothing third-party).

One strip per style and tier group: images/<style>_<group>.png, style a | b | c, group white | blue | orange | divine | unique | orb
(the rarity colours of game_lootbeams/lootbeamslogic.lua LB.GROUPS, which the test keeps in step). A strip is one row of 64 x 128 px
frames, left to right:

  frames 0-5    the burst when a beam appears (6 frames, played once): a flash at the foot, a ring that shoots out over the ground,
                the column rising to its height
  frames 6-17   the loop (12 frames, a seamless loop of 1.2 s): the beam, a pulse travelling up, motes drifting up, the ground ring

The foot of the beam (the centre of the ground ring) is at x = 32, y = 112 of the frame; the ring is an ellipse lying on the floor,
2:1.2 (the game's oblique ground view), the column rises from its centre and fades out towards the top. Styles (the owner picks one
in Loot Beams > Style; A is the default):

  a  soft light pillar   a feathered column with a bright centre line and a wide halo, a pulse travelling up
  b  twisted twin strands  two strands winding round each other, the front one brighter, glints where they cross
  c  rune column         a slim column with small glyphs rising beside it, tick marks round the ground ring

The tiers are richer upwards, not brighter (the peak is the same): Common / Uncommon stand low with a plain ring and three motes;
Magic / Rare add a travelling glint on the ring; Legendary has the full set; Divine and Uniques stand tallest with a pillar halo,
an inner ring and twinkles; Orbs are short and calm. The module draws the strip as ONE widget over the tile (Tile:addOverlayWidget,
base patch 0041) scaled with the map, so the ring and the column are one picture.

python3 -I client/tools/gen_lootbeam_art.py                    # write the strips into the module (overlay/modules/game_lootbeams/images)
python3 -I client/tools/gen_lootbeam_art.py --check            # the committed strips are what the generator draws (exit 1 if not)
python3 -I client/tools/gen_lootbeam_art.py --out DIR          # write the strips somewhere else
python3 -I client/tools/gen_lootbeam_art.py --preview DIR      # + beams_styles.mp4 (Legendary, A | B | C) and beams_tiers.mp4 (all tiers,
                                                               #   style A) on a mock ice floor, 3x nearest (needs ffmpeg; never committed)

numpy and Pillow are needed (CI runs the check with the pinned versions of the fx venv, because float maths differs a little between
versions; the strips were made with Pillow 12.3.0 and numpy 2.5.3). The check compares the decoded pixels, not the file bytes.
"""
import math
import os
import random
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.join(os.path.dirname(HERE), 'overlay', 'modules', 'game_lootbeams')
OUT = os.path.join(MODULE, 'images')

W, H = 64, 128          # one frame
FOOT_X, FOOT_Y = 32.0, 112.0
BURST, LOOP = 6, 12     # frames; the module's LB.ART keeps the same numbers (lootbeams_test.lua reads the files)
FRAMES = BURST + LOOP
SEED = 20261114

STYLES = ('a', 'b', 'c')
# the rarity colours (LB.GROUPS of lootbeamslogic.lua) and what makes a tier richer; col = column height in px (the share of the
# beam height of the group), motes, halo = (sigma px, energy) of the pillar halo, ring = gain of the ground ring, glint = a
# travelling highlight on the ring, inner = an inner ring, stars = twinkles, glyphs = runes of style c, amp = the strands of style b
GROUPS = {
    'white':  dict(color='#eef3f8', col=75, motes=3, halo=(9.0, 0.17), ring=0.55, glint=False, inner=False, stars=0, glyphs=2, amp=4.5),
    'blue':   dict(color='#3d8bff', col=85, motes=5, halo=(10.0, 0.20), ring=0.70, glint=True, inner=False, stars=0, glyphs=3, amp=5.5),
    'orange': dict(color='#ff8c1a', col=100, motes=8, halo=(11.0, 0.24), ring=0.80, glint=True, inner=False, stars=1, glyphs=4, amp=6.5),
    'divine': dict(color='#7fe3ff', col=110, motes=12, halo=(15.0, 0.25), ring=0.85, glint=True, inner=True, stars=3, glyphs=5, amp=7.0),
    'unique': dict(color='#2bff7a', col=112, motes=12, halo=(15.0, 0.25), ring=0.85, glint=True, inner=True, stars=3, glyphs=5, amp=7.0),
    'orb':    dict(color='#39e0c8', col=80, motes=4, halo=(9.0, 0.17), ring=0.60, glint=False, inner=False, stars=0, glyphs=3, amp=5.0),
}
GROUP_ORDER = ('white', 'blue', 'orange', 'divine', 'unique', 'orb')

# ---------------------------------------------------------------- the light kit (float energy, RGB)
Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
X, Y = X + 0.5, Y + 0.5


def rgb(hexcolor):
    h = hexcolor.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def mix(a, b, t):
    return a + (b - a) * t


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def add(E, field, color):
    E += field[..., None] * color


def gauss(v, s):
    return np.exp(-(v / s) ** 2)


def blob(x0, y0, rad):
    return np.exp(-(((X - x0) ** 2 + (Y - y0) ** 2) / (rad * rad)))


def ellipse_r(cx, cy, rx, ry):
    return np.sqrt(((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2)


def ring_field(cx, cy, rx, ry, width=1.0, glow=3.2, arc=None):
    """an ellipse line with a soft edge; arc = (angle, half width, gain) brightens a travelling stretch"""
    r = ellipse_r(cx, cy, rx, ry)
    d = np.abs(r - 1.0) * (rx + ry) / 2
    f = gauss(d, width) * 0.9 + gauss(d, glow) * 0.28
    if arc is not None:
        ang, half, gain = arc
        da = np.angle(np.exp(1j * (np.arctan2((Y - cy) / ry, (X - cx) / rx) - ang)))
        f = f * (1 + gain * np.exp(-(da / half) ** 2))
    return f


def finish(E):
    """energy -> straight RGBA (uint8): the alpha saturates softly, the hue stays the tier's, the hottest part burns to white"""
    edge = smooth(0.5, 6, X) * smooth(0.5, 6, W - X) * smooth(0.5, 8, Y) * smooth(0.5, 6, H - Y)
    E = E * edge[..., None]
    m = E.max(axis=2)
    a = 1.0 - np.exp(-1.35 * m)
    hue = E / np.maximum(m, 1e-6)[..., None]
    white = (np.clip((m - 0.8) / 1.4, 0, 1) ** 1.2 * 0.75)[..., None]
    col = hue * (1 - white) + white
    a = np.where(a < 0.004, 0.0, a)
    out = np.zeros((H, W, 4), np.float32)
    out[..., :3] = col
    out[..., 3] = a
    out[a == 0] = 0
    return np.clip(np.rint(out * 255.0), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- the parts of a beam
def column_env(t, grow):
    """vertical envelope of the column: t = 0 at the foot, 1 at the top; it fades out with height, rises softly out of the floor, and
    during the burst only reaches up to `grow` (a soft front)"""
    env = np.clip(1 - t, 0, 1) ** 1.35 * smooth(0.0, 0.06, t + 0.02)
    env = np.where(t < 0, 0.0, env)
    if grow < 1.0:
        env = env * smooth(0.0, 0.14, grow - t)
    return env


def tparam(g):
    return (FOOT_Y - Y) / float(g['col'])


def pillar(E, g, p, grow, core_sigma, core_gain, line_gain):
    """style a (and the base of c): a feathered column, a bright centre line, a halo, a pulse travelling up"""
    C = rgb(g['color'])
    hot = mix(C, np.ones(3, np.float32), 0.65)
    t = tparam(g)
    env = column_env(t, grow)
    widen = 1 + 0.4 * np.clip(t, 0, 1)
    shimmer = 1 + 0.22 * np.sin(2 * math.pi * (1.6 * t - p))
    xs = X - FOOT_X
    core = gauss(xs, core_sigma * widen)
    line = gauss(xs, 0.8 * widen)
    hs, he = g['halo']
    halo = gauss(xs, hs * widen)
    add(E, env * shimmer * core * core_gain, C)
    add(E, env * shimmer * halo * he, C)
    add(E, env * shimmer * line * line_gain, hot)


def strands(E, g, p, grow):
    """style b: two strands winding round each other, the front one brighter, glints where they cross"""
    C = rgb(g['color'])
    hot = mix(C, np.ones(3, np.float32), 0.65)
    t = tparam(g)
    env = column_env(t, grow)
    tt = np.clip(t, 0, 1)
    phi = 2 * math.pi * (2.0 * tt - p)
    grow_amp = g['amp'] * (1 + 0.3 * tt) * np.clip(tt / 0.14, 0, 1)
    for i in (0, 1):
        xi = FOOT_X + grow_amp * np.sin(phi + i * math.pi)
        depth = 0.62 + 0.38 * np.cos(phi + i * math.pi)
        d = X - xi
        add(E, env * depth * gauss(d, 1.7) * 0.95, C)
        add(E, env * depth * gauss(d, 0.7) * 0.85, hot)
    hs, he = g['halo']
    add(E, env * gauss(X - FOOT_X, hs * 0.7 * (1 + 0.4 * tt)) * he * 1.1, C)
    cross = gauss(np.sin(phi), 0.14) * np.clip(tt / 0.1, 0, 1)
    add(E, env * cross * gauss(X - FOOT_X, 2.4) * 0.7, hot)


# glyph strokes in a 5 x 8 cell (x right, y down), each a polyline; they are not letters of any script
RUNES = (
    ((0.1, 0.0), (0.1, 1.0), (0.9, 0.55), (0.1, 0.3)),
    ((0.1, 0.0), (0.9, 0.0), (0.5, 0.5), (0.9, 1.0), (0.1, 1.0)),
    ((0.5, 0.0), (0.5, 1.0), (0.1, 0.35), (0.9, 0.35)),
    ((0.1, 0.0), (0.9, 0.5), (0.1, 1.0), (0.9, 1.0)),
    ((0.9, 0.0), (0.1, 0.5), (0.9, 1.0), (0.1, 0.5), (0.5, 0.5)),
    ((0.1, 0.1), (0.5, 0.0), (0.9, 0.1), (0.5, 1.0), (0.1, 0.1)),
)


def seg_dist(px, py, ax, ay, bx, by):
    abx, aby = bx - ax, by - ay
    t = np.clip(((px - ax) * abx + (py - ay) * aby) / max(abx * abx + aby * aby, 1e-6), 0, 1)
    return np.sqrt((px - (ax + t * abx)) ** 2 + (py - (ay + t * aby)) ** 2)


def glyph_field(idx, cx, cy, w=5.0, h=8.0):
    pts = RUNES[idx % len(RUNES)]
    d = np.full((H, W), 99.0, np.float32)
    for a, b in zip(pts, pts[1:]):
        ax, ay = cx - w / 2 + a[0] * w, cy - h / 2 + a[1] * h
        bx, by = cx - w / 2 + b[0] * w, cy - h / 2 + b[1] * h
        # only the box of the glyph is needed
        d = np.minimum(d, seg_dist(X, Y, ax, ay, bx, by))
    return gauss(d, 0.75) * 0.9 + gauss(d, 2.0) * 0.18


def glyphs(E, g, p, style_seed):
    """style c: small glyphs rise beside the column, fade in and out, one life a loop"""
    C = rgb(g['color'])
    hot = mix(C, np.ones(3, np.float32), 0.75)
    n = g['glyphs']
    rs = random.Random(style_seed)
    for k in range(n):
        life = (p + k / float(n)) % 1.0
        side = -1 if k % 2 == 0 else 1
        cx = FOOT_X + side * (9.5 + 1.5 * math.sin(2 * math.pi * (life + k * 0.37)))
        cy = FOOT_Y - 10 - life * (g['col'] - 22)
        a = math.sin(math.pi * life) ** 0.9
        idx = rs.randrange(len(RUNES))
        f = glyph_field(idx, cx, cy)
        add(E, f * a * 0.95, mix(C, hot, 0.5))


def motes(E, g, p, style_seed):
    """soft sparks drifting up, a blob each with a hot centre; the count grows with the tier"""
    C = rgb(g['color'])
    hot = mix(C, np.ones(3, np.float32), 0.7)
    rs = random.Random(style_seed)
    n = g['motes']
    for k in range(n):
        off, x0, rad, m = rs.random(), rs.uniform(-12, 12), rs.uniform(1.2, 2.0), rs.choice((1, 2))
        life = (p * m + off) % 1.0
        x = FOOT_X + x0 * (1 + 0.5 * life) + 3.0 * math.sin(2 * math.pi * (life + off))
        y = FOOT_Y - 6 - life * (g['col'] * 0.95)
        a = math.sin(math.pi * life) ** 0.8 
        add(E, blob(x, y, rad * 1.8) * a * 0.35, C)
        add(E, blob(x, y, rad) * a * 0.8, hot)


def twinkles(E, g, p, style_seed):
    """four point flares that open and close, along the column (Divine, Uniques, one on Legendary)"""
    n = g['stars']
    if not n:
        return
    hot = mix(rgb(g['color']), np.ones(3, np.float32), 0.8)
    rs = random.Random(style_seed + 99)
    for k in range(n):
        x0 = rs.uniform(-9, 9)
        yy = FOOT_Y - rs.uniform(0.25, 0.8) * g['col']
        a = math.sin(math.pi * ((p * 1 + k / float(n)) % 1.0)) ** 3
        dx, dy = np.abs(X - (FOOT_X + x0)), np.abs(Y - yy)
        size = 5.5
        core = np.exp(-((dx * dx + dy * dy) / (size * size * 0.15)))
        arms = gauss(dx, size * 0.13) * np.clip(1 - dy / size, 0, 1) + gauss(dy, size * 0.13) * np.clip(1 - dx / size, 0, 1)
        add(E, np.clip(core + arms * 0.8, 0, 1) * a * 0.85, hot)


def ground(E, g, style, p, scale=1.0):
    """the ground ring and pool, an ellipse lying on the floor; scale < 1 is the ring still opening in the burst"""
    C = rgb(g['color'])
    hot = mix(C, np.ones(3, np.float32), 0.65)
    breath = 1 + 0.03 * math.sin(2 * math.pi * p)
    rx, ry = 26.0 * breath * scale, 15.5 * breath * scale
    gain = g['ring'] * scale
    r = ellipse_r(FOOT_X, FOOT_Y, rx * 1.05, ry * 1.05)
    add(E, np.clip(1 - r, 0, 1) ** 1.7 * 0.34 * gain, C)
    add(E, np.clip(1 - ellipse_r(FOOT_X, FOOT_Y, rx * 0.5, ry * 0.5), 0, 1) ** 1.4 * 0.30 * gain, hot)
    arc = (2 * math.pi * p, 0.7, 0.9) if g['glint'] else None
    add(E, ring_field(FOOT_X, FOOT_Y, rx, ry, arc=arc) * 0.85 * gain, mix(C, hot, 0.35))
    if g['inner']:
        arc2 = (-2 * math.pi * p + 1.5, 0.8, 0.8)
        add(E, ring_field(FOOT_X, FOOT_Y, rx * 0.56, ry * 0.56, width=0.8, glow=2.2, arc=arc2) * 0.55 * gain, hot)
    if style == 'c':
        # tick marks round the ring, turning once a loop
        r1 = ellipse_r(FOOT_X, FOOT_Y, rx * 1.2, ry * 1.2)
        d = np.abs(r1 - 1.0) * (rx + ry) / 2
        seg = 2 * math.pi / 16
        ang = np.arctan2((Y - FOOT_Y) / (ry * 1.2), (X - FOOT_X) / (rx * 1.2))
        on = smooth(0.0, 0.25, 1.0 - np.abs(((ang - 2 * math.pi * p / 16 * 1.0) % seg) / seg - 0.5) * 2 * 1.0) ** 2
        add(E, gauss(d, 1.0) * on * 0.6 * gain, mix(C, hot, 0.3))


def burst_parts(E, g, u):
    """the flash and the shock ring of the first frames, u in 0..1 over the burst"""
    C = rgb(g['color'])
    hot = mix(C, np.ones(3, np.float32), 0.8)
    fade = (1 - u) ** 1.5
    add(E, blob(FOOT_X, FOOT_Y - 4, 9 + 5 * u) * fade * 1.2, hot)
    add(E, blob(FOOT_X, FOOT_Y - 10, 5) * fade * 0.9, hot)
    rs = 6 + 26 * u
    add(E, ring_field(FOOT_X, FOOT_Y, rs, rs * 0.6, width=1.3, glow=3.6) * (1 - u) ** 1.2 * 1.1, mix(C, hot, 0.5))


def frame(style, name, k):
    """frame k (0..FRAMES - 1) of the strip of a style and group, straight RGBA uint8"""
    g = GROUPS[name]
    seed = SEED + STYLES.index(style) * 1000 + GROUP_ORDER.index(name) * 37
    E = np.zeros((H, W, 3), np.float32)
    if k < BURST:
        u = (k + 1) / float(BURST + 1)
        grow = 1 - (1 - u) ** 2
        p = 0.0
        scale = float(smooth(0.0, 1.0, np.float32(u)))
        burst_parts(E, g, u)
        ground(E, g, style, p, max(scale, 0.12))
    else:
        p = (k - BURST) / float(LOOP)
        grow = 1.0
        ground(E, g, style, p)
    if style == 'a':
        pillar(E, g, p, grow, 3.8, 0.85, 1.0)
    elif style == 'b':
        strands(E, g, p, grow)
    else:
        pillar(E, g, p, grow, 2.6, 0.6, 0.85)
        if k >= BURST:
            glyphs(E, g, p, seed + 5)
    if k >= BURST:
        motes(E, g, p, seed + 11)
        twinkles(E, g, p, seed)
    return finish(E)


def strip(style, name):
    img = np.zeros((H, W * FRAMES, 4), np.uint8)
    for k in range(FRAMES):
        img[:, k * W:(k + 1) * W] = frame(style, name, k)
    return img


def strip_name(style, name):
    return '%s_%s.png' % (style, name)


def all_strips():
    for style in STYLES:
        for name in GROUP_ORDER:
            yield strip_name(style, name), strip(style, name)


def save(path, arr):
    Image.fromarray(arr, 'RGBA').save(path, optimize=True)


def load(path):
    return np.array(Image.open(path).convert('RGBA'))


# ---------------------------------------------------------------- preview (never committed)
def ice_floor(w, h, seed=3):
    """a mock ice floor of 32 px tiles, blue-grey with faint cracks"""
    rs = np.random.RandomState(seed)
    base = np.zeros((h, w, 3), np.float32)
    ty, tx = np.mgrid[0:h, 0:w]
    tile = ((tx // 32) + (ty // 32)) % 2
    base[:] = np.array([58, 78, 100], np.float32)
    base += (tile[..., None] * np.array([6, 7, 8], np.float32))
    base += rs.normal(0, 3.0, (h, w, 1)).astype(np.float32)
    seam = ((tx % 32 == 0) | (ty % 32 == 0))[..., None]
    base = np.where(seam, base - 12, base)
    return np.clip(base, 0, 255)


def blend(floor, fr, x0, y0):
    """alpha-blend a straight RGBA frame onto an RGB float picture at (x0, y0), clipped"""
    h, w = fr.shape[:2]
    ys, xs = max(0, y0), max(0, x0)
    ye, xe = min(floor.shape[0], y0 + h), min(floor.shape[1], x0 + w)
    if ye <= ys or xe <= xs:
        return
    sub = fr[ys - y0:ye - y0, xs - x0:xe - x0].astype(np.float32)
    a = sub[..., 3:4] / 255.0
    floor[ys:ye, xs:xe] = floor[ys:ye, xs:xe] * (1 - a) + sub[..., :3] * a


def item_marks(floor, cx, cy):
    """a little dark bag on the floor under the beam, so the foot has something to stand on"""
    y, x = np.mgrid[0:floor.shape[0], 0:floor.shape[1]].astype(np.float32)
    d = ((x - cx) / 6.0) ** 2 + ((y - cy) / 4.5) ** 2
    m = np.clip(1.5 - d, 0, 1)[..., None]
    floor[:] = floor * (1 - m * 0.85) + np.array([54, 38, 26], np.float32) * m * 0.85


def render_video(out_path, columns, labels_ms, fps=25, seconds=4.5, scale=3):
    """columns = [(style, group)]: a beam each, side by side, all appearing at t = 0 and then looping"""
    cw = 96
    width, height = cw * len(columns), 160
    n = int(fps * seconds)
    tmp = out_path + '.frames'
    os.makedirs(tmp, exist_ok=True)
    base = ice_floor(width, height)
    for i in range(len(columns)):
        item_marks(base, i * cw + cw // 2, 140)
    strips = [strip(s, gname) for s, gname in columns]
    for f in range(n):
        ms = f * 1000.0 / fps
        pic = base.copy()
        for i, st in enumerate(strips):
            if ms < BURST * labels_ms[0]:
                k = int(ms // labels_ms[0])
            else:
                k = BURST + int((ms - BURST * labels_ms[0]) // labels_ms[1]) % LOOP
            blend(pic, st[:, k * W:(k + 1) * W], i * cw + (cw - W) // 2, 140 - int(FOOT_Y))
        img = Image.fromarray(np.clip(pic, 0, 255).astype(np.uint8), 'RGB')
        img = img.resize((width * scale, height * scale), Image.NEAREST)
        img.save(os.path.join(tmp, 'f%04d.png' % f))
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(fps), '-i', os.path.join(tmp, 'f%04d.png'),
           '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-crf', '18', '-movflags', '+faststart', out_path]
    subprocess.check_call(cmd)
    shutil.rmtree(tmp)


def preview(outdir):
    if not shutil.which('ffmpeg'):
        print('no ffmpeg: no preview')
        return 1
    os.makedirs(outdir, exist_ok=True)
    timing = (60, 100)  # ms a burst frame, ms a loop frame (lootbeamslogic.lua LB.ART)
    render_video(os.path.join(outdir, 'beams_styles.mp4'), [('a', 'orange'), ('b', 'orange'), ('c', 'orange')], timing)
    render_video(os.path.join(outdir, 'beams_tiers.mp4'), [('a', g) for g in GROUP_ORDER], timing)
    print('wrote', os.path.join(outdir, 'beams_styles.mp4'), os.path.join(outdir, 'beams_tiers.mp4'))
    return 0


# a tolerance of TOL per channel in --check: numpy's exp, sin and power round differently on other CPUs (vector
# paths), so a CI runner may draw a pixel one or two steps off the committed strip
TOL = 4


# ---------------------------------------------------------------- main
def main(argv):
    args = argv[1:]
    out = OUT
    if '--out' in args:
        out = args[args.index('--out') + 1]
    if '--preview' in args:
        return preview(args[args.index('--preview') + 1])
    if '--check' in args:
        bad = []
        for name, arr in all_strips():
            path = os.path.join(OUT, name)
            if not os.path.exists(path):
                bad.append(name + ' (missing)')
            elif load(path).shape != arr.shape or np.abs(load(path).astype(np.int16) - arr.astype(np.int16)).max() > TOL:
                bad.append(name + ' (differs)')
        known = set(n for n, _ in ((strip_name(s, g), 0) for s in STYLES for g in GROUP_ORDER))
        for f in sorted(os.listdir(OUT)) if os.path.isdir(OUT) else []:
            if f.endswith('.png') and f not in known:
                bad.append(f + ' (not drawn by the generator)')
        if bad:
            print('loot beam strips out of date:', ', '.join(bad))
            return 1
        print('loot beam strips ok (%d)' % len(known))
        return 0
    os.makedirs(out, exist_ok=True)
    for name, arr in all_strips():
        save(os.path.join(out, name), arr)
    print('wrote %d strips to %s' % (len(STYLES) * len(GROUP_ORDER), out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
