#!/usr/bin/env python3
"""Frames of the level-up wings (client module game_levelwings): a pair of golden feathered wings unfolding behind a
character, with a warm glow and a few embers. Drawn from scratch here (no reference pixels).

  wings_01.png .. wings_12.png   192 x 160 RGBA, 2x the 32 px tile scale (96 x 80 at 1x: three tiles wide)
                                 frame 1 folded behind the back, frame 12 fully open; frames 9-10 overshoot a little
                                 and 11-12 settle, so the opening has some weight.

The image centre is the creature's centre on the map (the engine centres a creature's widgets there); the wing roots
sit a few pixels above it, at the shoulders. The client (levelwingsmath.lua) shows the frames over ~0.65 s, holds the
last one and fades it out by ~1.8 s.

python3 -I client/tools/gen_levelwings_art.py   (writes into client/overlay/modules/game_levelwings/images/)"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_levelwings', 'images')

FRAMES = 12
W, H = 96, 80          # 1x size (32 px tiles); the files are OUT_SCALE x this
OUT_SCALE = 2
SS = 4                 # supersampling on top of OUT_SCALE
K = OUT_SCALE * SS     # drawing units -> canvas pixels

# palette: ember gold of the Chaos skin, bronze edges, a dark ember outline so the wings read on grass and on stone
OUTLINE = (46, 20, 8, 255)
BRONZE = (150, 92, 22)
AMBER = (236, 168, 40)
GOLD = (255, 214, 72)
PALE = (255, 246, 192)
RIM = (255, 230, 150)
GLOW = (255, 176, 48)
EMBER = (255, 120, 30)

# the right wing's root, in 1x units relative to the image centre (the creature's centre); x grows outwards
ROOT = (4.0, -6.0)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_col(c1, c2, t):
    return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))


def ease_out_back(t, k=1.25):
    t -= 1.0
    return 1.0 + t * t * ((k + 1.0) * t + k)


def spread_of(frame):
    """0 folded .. 1 open, frame 0..FRAMES-1, with a small overshoot before it settles."""
    t = frame / float(FRAMES - 1)
    return max(0.0, min(1.08, 0.04 + 0.96 * ease_out_back(t)))


def rot(v, ang):
    c, s = math.cos(ang), math.sin(ang)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def unit(ang):
    # screen angle: 0 = outwards (right), positive = up
    return (math.cos(ang), -math.sin(ang))


def skeleton(s):
    """Shoulder, elbow, wrist and tip of the right wing for spread s (1x units, relative to the image centre)."""
    sh = ROOT
    sc, over = min(s, 1.0), max(0.0, s - 1.0)
    # folded: the arm lies up along the back and the hand hangs down; open: a raised arm, the hand reaching out
    a_hum = math.radians(lerp(84, 38, sc) - 60 * over)
    a_fore = math.radians(lerp(-96, 50, sc) - 50 * over)
    a_hand = math.radians(lerp(-100, 16, sc) - 40 * over)
    l_hum, l_fore, l_hand = lerp(6, 10, sc), lerp(5, 12, sc), lerp(4, 12, sc)
    el = (sh[0] + unit(a_hum)[0] * l_hum, sh[1] + unit(a_hum)[1] * l_hum)
    wr = (el[0] + unit(a_fore)[0] * l_fore, el[1] + unit(a_fore)[1] * l_fore)
    tip = (wr[0] + unit(a_hand)[0] * l_hand, wr[1] + unit(a_hand)[1] * l_hand)
    return sh, el, wr, tip


def feather_poly(base, ang, length, width):
    """A tapered feather from base pointing at screen angle ang: rounded tip, narrow quill end."""
    d = unit(ang)
    n = (-d[1], d[0])
    pts_l, pts_r = [], []
    steps = 10
    for i in range(steps + 1):
        t = i / float(steps)
        # narrow at the quill, widest past the middle, rounded at the end
        w = width * (0.35 + 0.65 * t ** 0.5)
        if t > 0.8:
            w *= math.sqrt(max(0.0, 1.0 - ((t - 0.8) / 0.2) ** 2)) * 0.85 + 0.15
        p = (base[0] + d[0] * length * t, base[1] + d[1] * length * t)
        pts_l.append((p[0] + n[0] * w, p[1] + n[1] * w))
        pts_r.append((p[0] - n[0] * w * 0.8, p[1] - n[1] * w * 0.8))
    return pts_l + pts_r[::-1], (base[0] + d[0] * length, base[1] + d[1] * length)


def feathers(s):
    """Feathers of the right wing, back to front: list of (base, angle, length, width, shade 0..1)."""
    sh, el, wr, tip = skeleton(s)
    out = []
    sc = min(s, 1.0)
    hand_deg = math.degrees(math.atan2(-(tip[1] - wr[1]), tip[0] - wr[0]))
    # primaries along the hand: at the tip they carry on the hand's line, at the wrist they point down and out
    n_prim = 8
    for i in range(n_prim):
        t = i / float(n_prim - 1)                      # 0 at the tip, 1 at the wrist
        base = (lerp(tip[0], wr[0], t), lerp(tip[1], wr[1], t))
        open_deg = lerp(hand_deg - 12, -62, t ** 0.8)
        ang = math.radians(lerp(-92 + 4 * t, open_deg, sc))
        length = lerp(6 + 2 * (1 - t), lerp(20, 23, math.sin(math.pi * min(1, t + 0.3))), sc)
        out.append((base, ang, length, lerp(1.4, 2.5, sc), 0.2 + 0.45 * t))
    # secondaries along the forearm, hanging down
    n_sec = 6
    for i in range(n_sec):
        t = (i + 1) / float(n_sec + 1)                  # 0 at the wrist, 1 at the elbow
        base = (lerp(wr[0], el[0], t), lerp(wr[1], el[1], t))
        ang = math.radians(lerp(-92, lerp(-68, -86, t), sc))
        length = lerp(6, lerp(21, 17, t), sc)
        out.append((base, ang, length, lerp(1.5, 2.6, sc), 0.45 + 0.3 * t))
    # tertials near the body
    for i in range(3):
        t = (i + 1) / 4.0
        base = (lerp(el[0], sh[0], t), lerp(el[1], sh[1], t))
        ang = math.radians(lerp(-95, -88 + 4 * t, sc))
        length = lerp(5, 14 - 3 * t, sc)
        out.append((base, ang, length, 2.3, 0.7 + 0.2 * t))
    return out


def coverts(s):
    """Short gold coverts on top of the arm (the bright leading edge)."""
    sh, el, wr, tip = skeleton(s)
    sc = min(s, 1.0)
    out = []
    pts = [(sh, el, 4), (el, wr, 5), (wr, tip, 3)]
    for a, b, n in pts:
        for i in range(n):
            t = (i + 0.5) / n
            base = (lerp(a[0], b[0], t), lerp(a[1], b[1], t))
            seg = math.atan2(-(b[1] - a[1]), b[0] - a[0])
            ang = seg - math.radians(lerp(160, 115, sc))
            out.append((base, ang, lerp(4.5, 6.5, sc), 1.9, 1.0))
    return out


ZOOM = 0.8             # the wing geometry below is drawn at this size


def to_px(p, cx, cy, mirror):
    x = (-p[0] if mirror else p[0]) * ZOOM
    return ((cx + x) * K, (cy + p[1] * ZOOM) * K)


def draw_wing(img, s, mirror):
    dr = ImageDraw.Draw(img)
    cx, cy = W / 2.0, H / 2.0
    ow = max(1, int(round(0.55 * K)))
    for group in (feathers(s), coverts(s)):
        for base, ang, length, width, shade in group:
            poly, end = feather_poly(base, ang, length, width)
            pts = [to_px(p, cx, cy, mirror) for p in poly]
            # outline: the polygon drawn a little larger in the dark ember colour first
            dr.polygon(pts, fill=OUTLINE)
            inner, _ = feather_poly(base, ang, length * 0.95, max(0.4, width - 0.75))
            ipts = [to_px(p, cx, cy, mirror) for p in inner]
            base_col = lerp_col(AMBER, GOLD, shade)
            dr.polygon(ipts, fill=base_col + (255,))
            # lighter vane towards the tip, darker near the quill
            tip_part, _ = feather_poly((lerp(base[0], end[0], 0.45), lerp(base[1], end[1], 0.45)), ang,
                                       length * 0.5, max(0.3, width - 0.9))
            dr.polygon([to_px(p, cx, cy, mirror) for p in tip_part], fill=lerp_col(GOLD, PALE, shade) + (255,))
            # the quill
            q0 = to_px(base, cx, cy, mirror)
            q1 = to_px((lerp(base[0], end[0], 0.8), lerp(base[1], end[1], 0.8)), cx, cy, mirror)
            dr.line([q0, q1], fill=lerp_col(BRONZE, AMBER, shade) + (255,), width=ow)
    # the arm bone as a bright leading edge
    sh, el, wr, tip = skeleton(s)
    line = [to_px(p, cx, cy, mirror) for p in (sh, el, wr, tip)]
    dr.line(line, fill=OUTLINE, width=int(1.9 * K), joint='curve')
    dr.line(line, fill=RIM + (255,), width=int(0.9 * K), joint='curve')


def embers(img, frame, s):
    if frame < 4:
        return
    rnd = random.Random(1000 + frame)
    dr = ImageDraw.Draw(img)
    cx, cy = W / 2.0, H / 2.0
    for mirror in (False, True):
        sh, el, wr, tip = skeleton(s)
        for _ in range(4 + frame // 3):
            t = rnd.random()
            p = (lerp(el[0], tip[0], t) + rnd.uniform(-3, 5), lerp(el[1], tip[1], t) + rnd.uniform(-2, 14))
            p = (p[0], p[1] - (frame - 4) * rnd.uniform(0.3, 0.9))
            x, y = to_px(p, cx, cy, mirror)
            r = rnd.uniform(0.35, 0.8) * K
            col = (PALE if rnd.random() < 0.4 else EMBER) + (int(rnd.uniform(150, 255)),)
            dr.ellipse([x - r, y - r, x + r, y + r], fill=col)


def frame_image(frame):
    s = spread_of(frame)
    big = Image.new('RGBA', (W * K, H * K), (0, 0, 0, 0))
    draw_wing(big, s, mirror=True)
    draw_wing(big, s, mirror=False)
    # glow: the wings' shape, blurred, in warm gold, under the wings
    alpha = big.split()[3]
    glow_a = alpha.filter(ImageFilter.GaussianBlur(2.4 * K)).point(lambda v: int(v * (0.3 + 0.3 * min(s, 1.0))))
    glow = Image.new('RGBA', big.size, GLOW + (0,))
    glow.putalpha(glow_a)
    out = Image.alpha_composite(glow, big)
    embers(out, frame, s)
    return out.resize((W * OUT_SCALE, H * OUT_SCALE), Image.LANCZOS)


def main(argv):
    out = argv[1] if len(argv) > 1 else OUT
    os.makedirs(out, exist_ok=True)
    for f in range(FRAMES):
        frame_image(f).save(os.path.join(out, 'wings_%02d.png' % (f + 1)), optimize=True)
    print('wrote %d frames to %s' % (FRAMES, os.path.normpath(out)))


if __name__ == '__main__':
    main(sys.argv)
