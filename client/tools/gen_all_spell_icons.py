#!/usr/bin/env python3
"""Draw the client's three spell icon sheets from scratch (every cell is generated art).
usage: python3 -I client/tools/gen_all_spell_icons.py --spells-lua <client>/modules/gamelib/spells.lua \\
           --out-dir client/overlay/data/images/game/spells [--preview PREVIEW.png]
Writes spell-icons-32x32.png (RGBA), spell-icons-22x24.png (RGBA) and spell-icons-20x20.png (RGB), 20 columns,
cell n (1-based) at col (n-1)%20, row (n-1)//20, like Spells.getImageClipNormal.
 - cells named in the client's SpellIcons table: an icon derived from the spell's words (element, kind, tier);
   spells are matched by their icon key, never by their display name (the client renames them at runtime)
 - cells 201..277: the Chaos spell icons from gen_spell_icons.py (same drawings, same downscale)
 - every other cell: a neutral filler (dark plate + plain sigil)
Needs Pillow."""
import argparse, math, os, re, sys
from collections import Counter
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_spell_icons as chaos  # noqa: E402

S = 128
COLS = 20
CHAOS_FIRST = 201
SHEETS = [  # file suffix, cell w, cell h, mode, min rows
    ('32x32', 32, 32, 'RGBA', 12), ('22x24', 22, 24, 'RGBA', 12), ('20x20', 20, 20, 'RGB', 12)]

# ---------------------------------------------------------------- palettes: (main, light, dark)
PAL = {
    'fire': ((240, 105, 30), (255, 214, 120), (120, 24, 8)),
    'ice': ((120, 200, 250), (232, 248, 255), (24, 58, 128)),
    'energy': ((176, 108, 255), (236, 214, 255), (58, 18, 128)),
    'earth': ((128, 178, 58), (214, 234, 140), (44, 68, 18)),
    'poison': ((172, 222, 40), (232, 255, 150), (54, 80, 8)),
    'death': ((198, 34, 92), (255, 170, 192), (68, 8, 38)),
    'holy': ((250, 208, 96), (255, 248, 212), (128, 78, 18)),
    'physical': ((188, 188, 200), (246, 246, 252), (66, 66, 82)),
    'blood': ((212, 30, 36), (255, 142, 122), (80, 6, 12)),
    'heal': ((86, 220, 138), (212, 255, 222), (18, 88, 48)),
    'arcane': ((88, 140, 255), (206, 222, 255), (24, 38, 120)),
    'light': ((255, 234, 148), (255, 255, 236), (150, 108, 38)),
    'shadow': ((140, 100, 192), (216, 196, 242), (44, 24, 70)),
    'monk': ((222, 112, 72), (255, 208, 172), (92, 34, 18)),
    'spirit': ((240, 158, 58), (255, 226, 170), (118, 58, 14)),
    'harmony': ((88, 210, 198), (202, 255, 246), (18, 80, 80)),
    'nature': ((104, 196, 76), (204, 246, 170), (30, 80, 24)),
    'food': ((196, 112, 62), (250, 214, 168), (88, 40, 16)),
    'neutral': ((116, 106, 128), (184, 174, 198), (40, 34, 46)),
}
EL = {'flam': 'fire', 'frigo': 'ice', 'vis': 'energy', 'tera': 'earth', 'mort': 'death', 'san': 'holy', 'pox': 'poison',
      'ico': 'physical', 'kor': 'blood', 'vita': 'heal', 'lux': 'light', 'pug': 'monk', 'nia': 'spirit',
      'tio': 'harmony', 'virtu': 'harmony', 'ina': 'shadow', 'eq': 'physical', 'sac': 'holy', 'ven': 'energy',
      'dru': 'nature', 'con': 'physical', 'ani': 'shadow'}
INK = (14, 8, 14, 255)

def rgba(c, a=255):
    return tuple(c[:3]) + (a,)

# ---------------------------------------------------------------- geometry helpers
def star_pts(cx, cy, n, r1, r2, rot=-90.0):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + 180.0 * i / n)
        r = r1 if i % 2 == 0 else r2
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

def rot_pts(pts, deg, cx=64, cy=64):
    a = math.radians(deg); ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]

def taper(p0, p1, w0, w1):
    """quad from p0 (width w0) to p1 (width w1)"""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy) or 1
    nx, ny = -dy / ln, dx / ln
    return [(p0[0] + nx * w0 / 2, p0[1] + ny * w0 / 2), (p1[0] + nx * w1 / 2, p1[1] + ny * w1 / 2),
            (p1[0] - nx * w1 / 2, p1[1] - ny * w1 / 2), (p0[0] - nx * w0 / 2, p0[1] - ny * w0 / 2)]

def crescent(cx, cy, r, a0, a1, w, steps=24):
    """tapered arc (a slash): thick in the middle, pointed at both ends"""
    outer, inner = [], []
    for i in range(steps + 1):
        f = i / steps
        a = math.radians(a0 + (a1 - a0) * f)
        th = w * math.sin(math.pi * f)
        outer.append((cx + (r + th / 2) * math.cos(a), cy + (r + th / 2) * math.sin(a)))
        inner.append((cx + (r - th / 2) * math.cos(a), cy + (r - th / 2) * math.sin(a)))
    return outer + inner[::-1]

def heart_pts(cx, cy, s):
    pts = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * s, cy - y * s))
    return pts

def stamp(dst, fn, scale, cx, cy, *args):
    """draw fn(img, *args) on a fresh layer and paste it scaled, centred at (cx, cy)"""
    lay = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    fn(lay, *args)
    n = max(1, int(round(S * scale)))
    lay = lay.resize((n, n), Image.LANCZOS)
    dst.alpha_composite(lay, (int(round(cx - n / 2)), int(round(cy - n / 2))))

# ---------------------------------------------------------------- element motifs (the shared "family" mark)
def motif(d, el, cx, cy, r):
    m, l, k = PAL.get(el, PAL['neutral'])
    M, L, K = rgba(m), rgba(l), rgba(k)
    if el == 'fire':
        f = lambda s, dy: [(cx, cy - r * s + dy), (cx + .5 * r * s, cy - .15 * r * s + dy), (cx + .72 * r * s, cy + .38 * r * s + dy),
                           (cx + .42 * r * s, cy + .86 * r * s + dy), (cx, cy + .96 * r * s + dy), (cx - .42 * r * s, cy + .86 * r * s + dy),
                           (cx - .72 * r * s, cy + .38 * r * s + dy), (cx - .52 * r * s, cy - .2 * r * s + dy), (cx - .3 * r * s, cy - .5 * r * s + dy),
                           (cx - .12 * r * s, cy - .18 * r * s + dy)]
        d.polygon(f(1, 0), fill=M); d.polygon(f(.55, r * .4), fill=L)
    elif el == 'ice':
        d.polygon([(cx, cy - r), (cx + .42 * r, cy), (cx, cy + r), (cx - .42 * r, cy)], fill=M)
        d.polygon([(cx - .5 * r, cy - .55 * r), (cx - .3 * r, cy - .1 * r), (cx - .75 * r, cy + .1 * r)], fill=M)
        d.polygon([(cx + .5 * r, cy - .55 * r), (cx + .3 * r, cy - .1 * r), (cx + .75 * r, cy + .1 * r)], fill=M)
        d.polygon([(cx, cy - r * .8), (cx + .16 * r, cy), (cx, cy + r * .5), (cx - .1 * r, cy)], fill=L)
    elif el == 'energy':
        b = [(.2, -1), (-.55, .1), (-.05, .1), (-.25, 1), (.6, -.2), (.08, -.2), (.35, -1)]
        d.polygon([(cx + x * r, cy + y * r) for x, y in b], fill=M)
        d.line([(cx + .22 * r, cy - .8 * r), (cx - .3 * r, cy + .02 * r)], fill=L, width=max(2, int(r * .14)))
    elif el in ('earth', 'neutral_rock'):
        rock = [(-.8, -.2), (-.4, -.8), (.35, -.85), (.85, -.25), (.7, .6), (.05, .9), (-.65, .6)]
        d.polygon([(cx + x * r, cy + y * r) for x, y in rock], fill=M)
        d.polygon([(cx + x * r, cy + y * r) for x, y in [(-.6, -.25), (-.3, -.65), (.25, -.68), (0, -.2)]], fill=L)
        d.line([(cx + .1 * r, cy - .1 * r), (cx + .3 * r, cy + .35 * r), (cx + .05 * r, cy + .7 * r)], fill=K, width=max(2, int(r * .1)))
    elif el in ('poison', 'blood'):
        d.polygon([(cx, cy - r), (cx + .6 * r, cy + .4 * r), (cx - .6 * r, cy + .4 * r)], fill=M)
        d.ellipse((cx - .62 * r, cy - .32 * r, cx + .62 * r, cy + .92 * r), fill=M)
        d.ellipse((cx - .36 * r, cy + .05 * r, cx - .08 * r, cy + .4 * r), fill=L)
        if el == 'poison':
            d.ellipse((cx + .55 * r, cy - .75 * r, cx + .9 * r, cy - .4 * r), fill=M)
    elif el == 'death':
        d.ellipse((cx - .72 * r, cy - .9 * r, cx + .72 * r, cy + .45 * r), fill=M)
        d.rounded_rectangle((cx - .42 * r, cy + .1 * r, cx + .42 * r, cy + .85 * r), int(r * .15), fill=M)
        d.ellipse((cx - .5 * r, cy - .35 * r, cx - .1 * r, cy + .08 * r), fill=K)
        d.ellipse((cx + .1 * r, cy - .35 * r, cx + .5 * r, cy + .08 * r), fill=K)
        d.polygon([(cx, cy + .12 * r), (cx - .1 * r, cy + .35 * r), (cx + .1 * r, cy + .35 * r)], fill=K)
        for x in (-.2, 0, .2):
            d.line([(cx + x * r, cy + .55 * r), (cx + x * r, cy + .85 * r)], fill=K, width=max(1, int(r * .07)))
        d.ellipse((cx - .45 * r, cy - .8 * r, cx - .05 * r, cy - .5 * r), fill=L)
    elif el in ('holy', 'light'):
        d.polygon(star_pts(cx, cy, 4, r, r * .3), fill=M)
        d.polygon(star_pts(cx, cy, 4, r * .55, r * .2, -45), fill=M)
        d.ellipse((cx - .2 * r, cy - .2 * r, cx + .2 * r, cy + .2 * r), fill=L)
    elif el == 'physical':
        d.polygon(star_pts(cx, cy, 4, r, r * .28, -45), fill=M)
        d.polygon(star_pts(cx, cy, 4, r * .5, r * .18, -45), fill=L)
    elif el == 'heal':
        a = r * .32
        d.rounded_rectangle((cx - a, cy - r * .9, cx + a, cy + r * .9), int(a * .5), fill=M)
        d.rounded_rectangle((cx - r * .9, cy - a, cx + r * .9, cy + a), int(a * .5), fill=M)
        d.rectangle((cx - a * .4, cy - r * .6, cx + a * .4, cy + r * .6), fill=L)
    elif el == 'arcane':
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=M, width=max(2, int(r * .2)))
        d.polygon([(cx, cy - .6 * r), (cx + .52 * r, cy + .3 * r), (cx - .52 * r, cy + .3 * r)], outline=L, width=max(2, int(r * .12)))
        d.ellipse((cx - .18 * r, cy - .18 * r, cx + .18 * r, cy + .18 * r), fill=L)
    elif el == 'shadow':
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=M)
        d.ellipse((cx - .45 * r, cy - 1.05 * r, cx + 1.25 * r, cy + .75 * r), fill=(0, 0, 0, 0))
    elif el == 'spirit':
        d.ellipse((cx - .7 * r, cy - .2 * r, cx + .7 * r, cy + .9 * r), fill=M)
        d.polygon([(cx - .7 * r, cy + .35 * r), (cx - .2 * r, cy - r), (cx + .6 * r, cy - .6 * r), (cx + .7 * r, cy + .35 * r)], fill=M)
        d.ellipse((cx - .3 * r, cy + .15 * r, cx + .3 * r, cy + .65 * r), fill=L)
    elif el == 'harmony':
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=M)
        d.pieslice((cx - r, cy - r, cx + r, cy + r), 90, 270, fill=L)
        d.ellipse((cx - r / 2, cy - r, cx + r / 2, cy), fill=M)
        d.ellipse((cx - r / 2, cy, cx + r / 2, cy + r), fill=L)
        d.ellipse((cx - r * .15, cy - r * .65, cx + r * .15, cy - r * .35), fill=L)
        d.ellipse((cx - r * .15, cy + r * .35, cx + r * .15, cy + r * .65), fill=M)
    elif el == 'nature':
        d.polygon([(cx - .8 * r, cy + .8 * r), (cx - .7 * r, cy - .1 * r), (cx - .1 * r, cy - .8 * r), (cx + .85 * r, cy - .85 * r),
                   (cx + .75 * r, cy + .1 * r), (cx + .05 * r, cy + .75 * r)], fill=M)
        d.line([(cx - .75 * r, cy + .8 * r), (cx + .55 * r, cy - .55 * r)], fill=K, width=max(2, int(r * .12)))
    else:
        d.polygon([(cx, cy - r), (cx + r * .7, cy), (cx, cy + r), (cx - r * .7, cy)], fill=M)
        d.polygon([(cx, cy - r * .45), (cx + r * .3, cy), (cx, cy + r * .45), (cx - r * .3, cy)], fill=K)

# ---------------------------------------------------------------- glyphs: g(img, el, tier, var)
def P(el):
    m, l, k = PAL.get(el, PAL['neutral'])
    return rgba(m), rgba(l), rgba(k)

def g_strike(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    hx, hy = 78, 50
    r = (20, 25, 30, 33)[t]
    if t >= 3:
        d.polygon(star_pts(hx, hy, 12, r + 26, r + 4), fill=rgba(L, 150))
    if t >= 2:
        for off in (-22, 22):
            d.polygon(taper((hx - 8 + off * .7, hy + 8 + off * .7), (24 + off * .9, 104 + off * .9), 7, 1), fill=rgba(M, 200))
    d.polygon(taper((hx, hy), (16, 112), r * 1.3, 2), fill=M)
    d.polygon(taper((hx, hy), (30, 98), r * .55, 1), fill=L)
    motif(d, el, hx, hy, r)

def g_wave(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    ox, oy = 16, 112
    span = (24, 34, 42, 46)[t]
    a0, a1 = -45 - span, -45 + span
    R = 98
    d.pieslice((ox - R, oy - R, ox + R, oy + R), a0, a1, fill=rgba(M, 210))
    for i in range(1 + t):
        rr = 36 + (R - 36) * (i + 1) / (t + 1.6)
        d.arc((ox - rr, oy - rr, ox + rr, oy + rr), a0 + 4, a1 - 4, fill=L, width=6)
    d.arc((ox - R, oy - R, ox + R, oy + R), a0, a1, fill=L, width=4)
    motif(d, el, 34, 94, 16)

def g_beam(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    w = (16, 20, 26, 30)[t]
    d.polygon(star_pts(104, 24, 8, 24 + 3 * t, 8), fill=rgba(L, 210))
    d.polygon(taper((26, 102), (108, 20), w, w * .7), fill=M)
    d.polygon(taper((26, 102), (108, 20), w * .4, w * .25), fill=L)
    if el == 'energy':
        d.line([(30, 98), (50, 70), (58, 78), (78, 50), (86, 58), (104, 28)], fill=K, width=3)
    d.ellipse((6, 82, 46, 122), fill=K)
    motif(d, el, 26, 102, 18)

def g_area(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    n = 8 + 2 * t
    d.polygon(star_pts(64, 64, n, 54 + 2 * t, 26), fill=M)
    d.polygon(star_pts(64, 64, n, 36, 20, -90 + 180 / n), fill=L)
    d.ellipse((38, 38, 90, 90), fill=K)
    motif(d, el, 64, 64, 22)

def g_burstring(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for i in range(12):
        a = math.radians(i * 30)
        d.polygon(taper((64 + 40 * math.cos(a), 64 + 40 * math.sin(a)), (64 + 60 * math.cos(a), 64 + 60 * math.sin(a)), 12, 1), fill=M)
    d.ellipse((18, 18, 110, 110), outline=M, width=12)
    d.ellipse((24, 24, 104, 104), outline=L, width=3)
    motif(d, el, 64, 64, 22)

def cross_shape(d, cx, cy, r, M, L, arm=.34):
    a = r * arm
    d.rounded_rectangle((cx - a, cy - r, cx + a, cy + r), int(a * .55), fill=M)
    d.rounded_rectangle((cx - r, cy - a, cx + r, cy + a), int(a * .55), fill=M)
    d.rounded_rectangle((cx - a * .35, cy - r * .75, cx + a * .35, cy + r * .75), int(a * .3), fill=L)
    d.rounded_rectangle((cx - r * .75, cy - a * .35, cx + r * .75, cy + a * .35), int(a * .3), fill=L)

def g_heal(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    r = (34, 42, 48, 46)[t]
    cx, cy = 64, 64
    if t >= 3:
        d.ellipse((8, 8, 120, 120), outline=L, width=7)
        d.polygon(star_pts(64, 64, 8, 58, 40, -67.5), fill=rgba(M, 90))
    if var == 'friend':
        cx, cy, r = 54, 54, min(r, 40)
        cross_shape(d, 96, 96, 20, M, L)
    elif var == 'mass':
        r = min(r, 34)
        for x, y in ((24, 24), (104, 24), (24, 104), (104, 104)):
            cross_shape(d, x, y, 14, M, L)
    if el == 'physical':  # wound cleansing: bandage band across the cross
        cross_shape(d, cx, cy, r, rgba((220, 60, 60)), rgba((255, 170, 160)))
        d.polygon(taper((cx - r * .9, cy + r * .5), (cx + r * .9, cy - r * .5), r * .3, r * .3), fill=M)
    else:
        cross_shape(d, cx, cy, r, M, L)
    if t >= 2 and var not in ('friend', 'mass'):
        d.ellipse((cx - 8, cy - 8, cx + 8, cy + 8), fill=rgba((255, 255, 255)))

def g_regen(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.arc((10, 10, 118, 118), 200, 520 - 40, fill=L, width=8)
    d.polygon([(30, 18), (52, 10), (44, 34)], fill=L)
    if t >= 2:
        d.arc((20, 20, 108, 108), 20, 330 - 20, fill=rgba(M, 200), width=5)
    d.polygon(heart_pts(64, 66, 2.3), fill=M)
    d.polygon(heart_pts(56, 56, .9), fill=L)

def g_cure(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    glass = (210, 220, 230, 255)
    d.rounded_rectangle((52, 14, 76, 26), 4, fill=glass)
    d.rectangle((54, 24, 74, 56), fill=glass)
    d.ellipse((26, 46, 102, 122), fill=glass)
    d.ellipse((31, 51, 97, 117), fill=K)
    d.chord((31, 51, 97, 117), 0, 180, fill=M)
    d.rectangle((31, 83, 97, 86), fill=M)
    d.ellipse((40, 58, 54, 72), fill=(255, 255, 255, 200))
    motif(d, el, 64, 98, 12)
    d.polygon(star_pts(100, 30, 4, 16, 4), fill=rgba((255, 255, 255)))

def g_dot(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.ellipse((14, 14, 114, 114), outline=M, width=10)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        d.polygon(taper((64 + 52 * math.cos(a), 64 + 52 * math.sin(a)), (64 + 30 * math.cos(a), 64 + 30 * math.sin(a)), 14, 1), fill=M)
    for i in range(8):
        a = math.radians(22.5 * (2 * i + 1))
        d.ellipse((64 + 50 * math.cos(a) - 3, 64 + 50 * math.sin(a) - 3, 64 + 50 * math.cos(a) + 3, 64 + 50 * math.sin(a) + 3), fill=L)
    motif(d, el, 64, 64, 26)

def g_haste(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    n = 2 if t <= 1 else 3
    w = 92 / (n + .6)
    for i in range(n):
        x = 18 + i * w * .8
        pts = [(x, 24), (x + w * .55, 24), (x + w * 1.15, 64), (x + w * .55, 104), (x, 104), (x + w * .6, 64)]
        d.polygon(pts, fill=M)
        d.line([(x + w * .55, 28), (x + w * 1.05, 64)], fill=L, width=4)
    if var == 'charge':
        d.polygon(star_pts(104, 64, 6, 22, 9), fill=L)
    for y in (40, 88):
        d.line([(4, y), (16, y)], fill=rgba(L, 180), width=4)

def g_levitate(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.rectangle((56, 34, 72, 94), fill=M)
    d.polygon([(64, 8), (96, 42), (32, 42)], fill=M)
    d.polygon([(64, 120), (96, 86), (32, 86)], fill=M)
    d.line([(64, 18), (64, 110)], fill=L, width=4)
    for x in (18, 110):
        d.arc((x - 14, 52, x + 14, 76), 0, 180, fill=L, width=5)

def g_rope(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    rope = (196, 160, 104, 255)
    d.line([(64, 120), (64, 50)], fill=rope, width=10)
    for y in range(56, 120, 12):
        d.line([(58, y), (70, y + 6)], fill=(120, 90, 50, 255), width=3)
    d.arc((40, 14, 88, 62), 180, 360 + 20, fill=M, width=10)
    d.arc((60, 30, 100, 70), 200, 360, fill=M, width=10)
    d.polygon([(30, 38), (52, 30), (40, 54)], fill=M)
    d.polygon(star_pts(98, 22, 4, 12, 3), fill=L)

def shield_pts(cx=64, cy=64, s=1.0):
    pts = [(-40, -46), (40, -46), (40, 2), (0, 52), (-40, 2)]
    return [(cx + x * s, cy + y * s) for x, y in pts]

def g_shield(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.polygon(shield_pts(), fill=M)
    d.polygon(shield_pts(64, 62, .8), fill=K)
    d.polygon([(64, 24), (90, 24), (90, 62), (64, 96)], fill=rgba(M, 160))
    if var == 'magic':
        motif(d, 'arcane', 64, 58, 18)
    elif var == 'broken':
        d.line([(70, 12), (56, 40), (72, 60), (54, 84), (64, 118)], fill=INK, width=8)
        d.line([(70, 12), (56, 40), (72, 60), (54, 84), (64, 118)], fill=L, width=2)
    elif var == 'meditate':
        motif(d, 'harmony', 64, 58, 18)
    else:
        d.ellipse((50, 42, 78, 70), fill=L)
        d.ellipse((57, 49, 71, 63), fill=M)
    if t >= 2:
        d.polygon(shield_pts(), outline=L, width=4)

def g_light(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    r = (14, 18, 20, 22)[t]
    n = (8, 8, 12, 16)[t]
    rl = (40, 46, 54, 58)[t]
    d.polygon(star_pts(64, 64, n, rl, r + 6), fill=M)
    if t >= 3:
        d.ellipse((64 - rl + 6, 64 - rl + 6, 64 + rl - 6, 64 + rl - 6), outline=L, width=4)
    d.ellipse((64 - r - 6, 64 - r - 6, 64 + r + 6, 64 + r + 6), fill=M)
    d.ellipse((64 - r, 64 - r, 64 + r, 64 + r), fill=L)

def eye(d, M, L, K, cx=64, cy=64, s=1.0, open_=True):
    pts = [(cx - 56 * s, cy), (cx - 28 * s, cy - 28 * s), (cx, cy - 36 * s), (cx + 28 * s, cy - 28 * s), (cx + 56 * s, cy),
           (cx + 28 * s, cy + 28 * s), (cx, cy + 36 * s), (cx - 28 * s, cy + 28 * s)]
    if open_:
        d.polygon(pts, fill=M)
        d.ellipse((cx - 22 * s, cy - 22 * s, cx + 22 * s, cy + 22 * s), fill=K)
        d.ellipse((cx - 9 * s, cy - 9 * s, cx + 9 * s, cy + 9 * s), fill=L)
    else:
        d.chord((cx - 56 * s, cy - 40 * s, cx + 56 * s, cy + 40 * s), 0, 180, fill=M)
        d.line([(cx - 56 * s, cy), (cx + 56 * s, cy)], fill=L, width=max(2, int(5 * s)))
        for x in (-30, -10, 10, 30):
            d.line([(cx + x * s, cy + 34 * s), (cx + x * 1.3 * s, cy + 50 * s)], fill=M, width=max(2, int(5 * s)))

def g_invis(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for i, a in enumerate((60, 110, 160)):
        d.ellipse((14 - i * 4, 14 - i * 4, 114 + i * 4, 114 + i * 4), outline=rgba(M, a), width=3)
    eye(d, M, L, K, 64, 64, .9, open_=True)
    d.line([(22, 106), (106, 22)], fill=INK, width=14)
    d.line([(22, 106), (106, 22)], fill=L, width=6)

def g_reveal(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.polygon(star_pts(64, 64, 12, 62, 40), fill=rgba(L, 120))
    eye(d, M, L, K, 64, 64, .95, open_=True)

def g_find(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.ellipse((12, 12, 116, 116), outline=M, width=8)
    d.polygon(star_pts(64, 64, 4, 50, 10), fill=M)
    d.polygon([(64, 14), (74, 64), (54, 64)], fill=L)
    if var == 'fiend':
        eye(d, rgba((212, 30, 36)), rgba((255, 200, 120)), INK, 64, 64, .42)
    else:
        d.ellipse((56, 56, 72, 72), fill=K)

def g_mask(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.chord((18, 8, 110, 120), 180, 360, fill=M)
    d.rectangle((18, 63, 110, 70), fill=M)
    d.pieslice((18, 20, 110, 116), 0, 180, fill=M)
    d.polygon([(30, 50), (56, 44), (54, 60), (34, 62)], fill=K)
    d.polygon([(98, 50), (72, 44), (74, 60), (94, 62)], fill=K)
    d.arc((40, 72, 88, 104), 20, 160, fill=K, width=6)
    d.line([(64, 14), (64, 116)], fill=rgba(L, 120), width=3)

def g_summon(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.ellipse((10, 10, 118, 118), outline=M, width=8 + 2 * t)
    pts = [(64 + 50 * math.cos(math.radians(-90 + 144 * i)), 64 + 50 * math.sin(math.radians(-90 + 144 * i))) for i in range(6)]
    d.line(pts, fill=L, width=5)
    if var:
        d.ellipse((44, 44, 84, 84), fill=K)
        motif(d, var, 64, 64, 18)

def figure(d, cx, cy, s, C):
    d.ellipse((cx - 10 * s, cy - 30 * s, cx + 10 * s, cy - 10 * s), fill=C)
    d.pieslice((cx - 22 * s, cy - 8 * s, cx + 22 * s, cy + 36 * s), 180, 360, fill=C)

def g_avatar(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.polygon(star_pts(64, 60, 16, 60, 38), fill=rgba(M, 190))
    d.ellipse((22, 18, 106, 102), fill=K)
    d.ellipse((22, 18, 106, 102), outline=L, width=4)
    d.ellipse((50, 26, 78, 54), fill=L)
    d.pieslice((28, 56, 100, 128), 180, 360, fill=L)
    d.polygon([(46, 26), (52, 14), (58, 24), (64, 10), (70, 24), (76, 14), (82, 26)], fill=M)
    motif(d, el, 64, 80, 12)

def party(d, M, L, K):
    for x, s in ((30, .85), (98, .85), (64, 1.0)):
        figure(d, x, 104, s, L if x == 64 else M)

def g_party(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    sub = {'shield': lambda: (d.polygon(shield_pts(64, 46, .62), fill=M), d.polygon(shield_pts(64, 45, .45), fill=L)),
           'heal': lambda: cross_shape(d, 64, 42, 30, M, L),
           'sword': lambda: (d.polygon([(64, 4), (74, 18), (74, 56), (54, 56), (54, 18)], fill=L), d.rectangle((40, 56, 88, 64), fill=M),
                             d.rectangle((60, 64, 68, 76), fill=M)),
           'spark': lambda: (d.polygon(star_pts(64, 40, 4, 34, 9), fill=M), d.polygon(star_pts(64, 40, 4, 18, 5, -45), fill=L)),
           'sun': lambda: (d.polygon(star_pts(64, 40, 10, 34, 18), fill=M), d.ellipse((50, 26, 78, 54), fill=L)),
           'star': lambda: (d.polygon(star_pts(64, 40, 5, 34, 14), fill=M), d.polygon(star_pts(64, 41, 5, 16, 7), fill=L)),
           }
    sub.get(var, sub['spark'])()
    party(d, M, L, K)

def g_buff(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    if var == 'crosshair':
        d.ellipse((18, 18, 110, 110), outline=M, width=8)
        d.ellipse((42, 42, 86, 86), outline=L, width=5)
        for a, b in (((64, 6), (64, 44)), ((64, 84), (64, 122)), ((6, 64), (44, 64)), ((84, 64), (122, 64))):
            d.line([a, b], fill=M, width=7)
        d.ellipse((58, 58, 70, 70), fill=L)
    else:  # rage: rising arrow over a burst
        d.polygon(star_pts(64, 82, 10, 40, 22), fill=rgba(M, 200))
        d.polygon([(64, 6), (104, 50), (78, 50), (78, 110), (50, 110), (50, 50), (24, 50)], fill=M)
        d.polygon([(64, 18), (88, 46), (68, 46), (68, 100), (60, 100), (60, 46)], fill=L)

def g_virtue(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.ellipse((10, 10, 118, 118), outline=M, width=8)
    tri = [(64, 18), (104, 88), (24, 88)]
    if var == 'down':
        tri = [(64, 110), (104, 40), (24, 40)]
    d.polygon(tri, outline=L, width=6)
    if var == 'up':
        d.polygon([(64, 30), (78, 56), (50, 56)], fill=L)
    d.ellipse((50, 50 if var != 'down' else 50, 78, 78), fill=M)
    d.ellipse((58, 58, 70, 70), fill=L)

def g_meditate(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for a in (-60, -30, 0, 30, 60):
        petal = [(64, 104), (52, 70), (64, 34), (76, 70)]
        d.polygon(rot_pts(petal, a, 64, 104), fill=M if a else L)
    d.ellipse((50, 8, 78, 36), fill=L)
    d.line([(20, 108), (108, 108)], fill=M, width=6)

def g_holyground(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for x in (30, 48, 64, 80, 98):
        h = 70 if x == 64 else 50
        d.polygon(taper((x, 96), (x, 96 - h), 10, 1), fill=M)
    d.ellipse((10, 80, 118, 116), outline=L, width=7)
    motif(d, el, 64, 36, 20)

def g_flash(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.polygon(star_pts(64, 64, 4, 58, 12), fill=M)
    d.polygon(star_pts(64, 64, 4, 34, 8, -45), fill=M)
    d.polygon(star_pts(64, 64, 4, 30, 7), fill=L)
    for x, y in ((24, 28), (102, 98), (100, 24)):
        d.polygon(star_pts(x, y, 4, 12, 3), fill=L)

def g_challenge(img, el, t, var):
    """two crossed swords over a red shout burst (taunt)"""
    d = ImageDraw.Draw(img); M, L, K = P(el)
    steel, shine = rgba(PAL['physical'][0]), rgba(PAL['physical'][1])
    d.polygon(star_pts(64, 64, 10 if t >= 2 else 8, 48 if t >= 2 else 40, 20), fill=rgba(M, 220))
    for a in (-42, 42):
        R = lambda pts: rot_pts(pts, a, 64, 64)
        d.polygon(R([(64, 6), (73, 18), (73, 84), (55, 84), (55, 18)]), fill=steel)
        d.line(R([(64, 14), (64, 80)]), fill=shine, width=3)
        d.polygon(R([(44, 84), (84, 84), (84, 93), (44, 93)]), fill=L)
        d.polygon(R([(59, 93), (69, 93), (69, 112), (59, 112)]), fill=K)
        d.polygon(R([(56, 112), (72, 112), (72, 122), (56, 122)]), fill=L)

def g_ammo(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    wood = (176, 128, 76, 255)
    arrows = [(0, 0)] if t == 0 else [(-12, 12), (12, -12)]
    for ox, oy in arrows:
        d.line([(24 + ox, 104 + oy), (92 + ox, 36 + oy)], fill=wood, width=7)
        d.polygon([(104 + ox, 24 + oy), (82 + ox, 34 + oy), (94 + ox, 46 + oy)], fill=(214, 214, 224, 255))
        for k in (0, 10):
            d.polygon([(22 + ox + k, 106 + oy - k), (14 + ox + k, 96 + oy - k), (30 + ox + k, 98 + oy - k)], fill=M)
    if var == 'explosive':
        d.polygon(star_pts(102, 26, 8, 26, 10), fill=rgba(PAL['fire'][0]))
        motif(d, 'fire', 102, 26, 14)
    else:
        d.polygon(star_pts(30, 30, 4, 16, 4), fill=L)

def g_spear(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    ln = (70, 92, 100, 100)[t]
    x0, y0 = 64 - ln / 2 * .707, 64 + ln / 2 * .707
    x1, y1 = 64 + ln / 2 * .707, 64 - ln / 2 * .707
    if t >= 2 or var == 'enchant':
        d.polygon(taper((x0 - 12, y0 - 12), (x1 - 12, y1 - 12), 12, 2), fill=rgba(L, 130))
        d.polygon(taper((x0 + 12, y0 + 12), (x1 + 12, y1 + 12), 12, 2), fill=rgba(L, 130))
    d.line([(x0, y0), (x1 - 14, y1 + 14)], fill=(150, 116, 80, 255), width=8)
    head = [(x1 + 6, y1 - 6), (x1 - 22, y1 + 6), (x1 - 6, y1 + 22)]
    d.polygon(head, fill=M)
    d.polygon([(x1 + 4, y1 - 4), (x1 - 12, y1 + 4), (x1 - 4, y1 + 12)], fill=L)
    if var == 'enchant':
        for x, y in ((28, 34), (98, 96), (46, 22)):
            d.polygon(star_pts(x, y, 4, 13, 3), fill=L)

def g_wand(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.line([(22, 108), (82, 48)], fill=(70, 50, 60, 255), width=10)
    d.line([(22, 108), (82, 48)], fill=(130, 100, 110, 255), width=3)
    d.polygon(star_pts(90, 38, 8, 34, 14), fill=rgba(M, 170))
    d.ellipse((72, 20, 108, 56), fill=K)
    motif(d, el, 90, 38, 15)

def g_food(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    bone = (236, 226, 206, 255)
    d.line([(34, 94), (14, 114)], fill=bone, width=10)
    d.ellipse((4, 104, 20, 120), fill=bone); d.ellipse((12, 108, 28, 124), fill=bone)
    d.ellipse((30, 14, 114, 98), fill=M)
    d.polygon([(30, 70), (40, 94), (60, 82)], fill=M)
    d.ellipse((46, 26, 84, 56), fill=L)

def g_melee(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    if var == 'spin':
        n = 3 if t <= 1 else 4
        for i in range(n):
            a = 360 / n * i
            d.polygon(crescent(64, 64, 40, a, a + 360 / n * .8, 22), fill=M)
            d.polygon(crescent(64, 64, 40, a + 10, a + 360 / n * .6, 8), fill=L)
        d.ellipse((50, 50, 78, 78), fill=L)
        if t >= 2:
            d.ellipse((6, 6, 122, 122), outline=rgba(M, 160), width=4)
    elif var == 'slash':
        d.polygon(crescent(140, 140, 120, 196, 254, 30), fill=M)
        d.polygon(crescent(140, 140, 120, 204, 246, 10), fill=L)
        if t >= 2:
            d.polygon(crescent(-12, 140, 120, -74, -16, 30), fill=M)
            d.polygon(crescent(-12, 140, 120, -66, -24, 10), fill=L)
            d.polygon(star_pts(64, 64, 8, 26, 10), fill=L)
        else:
            d.polygon(star_pts(96, 96, 4, 14, 4), fill=L)
    elif var == 'sweep':
        d.polygon(crescent(64, 92, 52 if t else 44, 190, 350, 30 if t else 22), fill=M)
        d.polygon(crescent(64, 92, 52 if t else 44, 210, 330, 10), fill=L)
        motif(d, 'physical', 64, 94, 12)
    elif var == 'quake':
        d.polygon([(6, 96), (122, 96), (122, 124), (6, 124)], fill=K)
        d.polygon([(6, 92), (122, 92), (122, 102), (6, 102)], fill=M)
        d.line([(64, 92), (56, 104), (68, 114), (60, 124)], fill=INK, width=5)
        d.line([(30, 92), (36, 108)], fill=INK, width=4); d.line([(98, 92), (90, 110)], fill=INK, width=4)
        for x, y, r in ((30, 60, 10), (64, 34, 13), (98, 58, 9), (46, 22, 6), (86, 24, 7)):
            d.polygon([(x - r, y), (x - r * .3, y - r), (x + r, y - r * .5), (x + r * .6, y + r), (x - r * .5, y + r)], fill=M)
        d.arc((20, 50, 108, 130), 200, 340, fill=L, width=5)
    elif var in ('axe', 'throw'):
        if var == 'throw':
            for i in range(2):
                r = 44 + 10 * i
                d.arc((64 - r, 64 - r, 64 + r, 64 + r), 100 + 30 * i, 220 + 30 * i, fill=rgba(L, 200), width=5)
        handle = [(30, 108), (84, 36)]
        d.line(handle, fill=(140, 104, 70, 255), width=8)
        d.polygon([(70, 26), (110, 16), (118, 44), (100, 70), (80, 52)], fill=M)
        d.polygon([(76, 32), (106, 24), (110, 42)], fill=L)
        if var == 'axe':
            for k in (0, 14):
                d.line([(16 + k, 60 - k), (40 + k, 84 - k)], fill=rgba(L, 200), width=4)
    elif var == 'shatter':
        d.ellipse((14, 14, 114, 114), fill=M)
        d.ellipse((30, 30, 98, 98), fill=K)
        d.line([(64, 10), (58, 40), (70, 56), (54, 80), (66, 118)], fill=INK, width=7)
        d.line([(14, 60), (40, 66), (54, 80)], fill=INK, width=6)
        d.polygon(star_pts(64, 64, 4, 18, 5), fill=L)
    elif var == 'drain':
        motif(d, 'blood', 64, 46, 34)
        d.polygon([(64, 122), (90, 92), (74, 92), (74, 76), (54, 76), (54, 92), (38, 92)], fill=L)

def fist(d, cx, cy, s, M, L, K):
    """front view of a clenched fist: four knuckles, folded fingers, thumb across, wrist wrap"""
    d.rounded_rectangle((cx - 30 * s, cy - 26 * s, cx + 30 * s, cy + 26 * s), int(12 * s), fill=M)
    for i in range(4):
        x = cx - 30 * s + i * 15 * s
        d.rounded_rectangle((x + 1 * s, cy - 34 * s, x + 14 * s, cy - 6 * s), int(6 * s), fill=M)
        d.ellipse((x + 4 * s, cy - 31 * s, x + 10 * s, cy - 25 * s), fill=L)
        if i:
            d.line([(x, cy - 30 * s), (x, cy - 8 * s)], fill=K, width=max(2, int(3 * s)))
    d.line([(cx - 28 * s, cy - 6 * s), (cx + 28 * s, cy - 6 * s)], fill=K, width=max(2, int(3 * s)))
    d.rounded_rectangle((cx - 34 * s, cy - 2 * s, cx + 8 * s, cy + 14 * s), int(8 * s), fill=L, outline=K, width=max(2, int(3 * s)))
    d.rectangle((cx - 24 * s, cy + 26 * s, cx + 24 * s, cy + 42 * s), fill=K)
    for k in (0, 1):
        y = cy + 30 * s + k * 7 * s
        d.line([(cx - 24 * s, y), (cx + 24 * s, y + 3 * s)], fill=M, width=max(2, int(3 * s)))

def g_fist(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    if var == 'double':
        fist(d, 46, 74, .8, rgba(M, 255), L, K); fist(d, 80, 54, .8, M, L, K)
        return
    if var == 'uppercut':
        for x in (24, 104):
            d.polygon(taper((x, 110), (x, 30), 8, 1), fill=rgba(L, 200))
        fist(d, 64, 64, 1.1, M, L, K)
        d.polygon(star_pts(64, 18, 6, 16, 6), fill=L)
        return
    if var == 'chain':
        for i, (x, y) in enumerate(((20, 106), (36, 90), (52, 74))):
            d.ellipse((x - 10, y - 7, x + 10, y + 7), outline=L, width=4)
        fist(d, 78, 52, .9, M, L, K)
        return
    if var == 'flurry':
        for i in range(6 + 2 * min(t, 2)):
            a = math.radians(360 / (6 + 2 * min(t, 2)) * i)
            d.polygon(star_pts(64 + 48 * math.cos(a), 64 + 48 * math.sin(a), 4, 11, 3), fill=L)
        fist(d, 64, 66, .85, M, L, K)
        return
    if var == 'repulse':
        for i in range(3):
            r = 30 + 14 * i
            d.arc((70 - r, 64 - r, 70 + r, 64 + r), -50, 50, fill=rgba(L, 230 - 50 * i), width=6)
        d.rounded_rectangle((20, 40, 60, 98), 12, fill=M)
        for i in range(4):
            d.rounded_rectangle((22 + i * 10, 18, 30 + i * 10, 48), 4, fill=M)
        d.rounded_rectangle((52, 64, 74, 76), 5, fill=M)
        return
    fist(d, 64, 64, (.8, 1.0, 1.1, 1.15)[t], M, L, K)
    if t == 0:
        d.polygon(star_pts(100, 28, 4, 14, 4), fill=L)

def g_claw(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    w = (14, 18, 22, 24)[t]
    for i in (-1, 0, 1):
        d.polygon(crescent(118 + i * 26, 118 - i * 26 + 10, 96, 196, 252, w), fill=M)
        d.polygon(crescent(118 + i * 26, 118 - i * 26 + 10, 96, 206, 242, w * .35), fill=L)
    if t >= 2:
        d.polygon(star_pts(98, 98, 8, 22, 9), fill=L)

def g_rune(img, el, t, var):
    """rune stone tablet with an engraved, glowing glyph"""
    d = ImageDraw.Draw(img)
    edge = (200, 160, 80, 255) if t >= 3 else (150, 140, 146, 255) if t >= 2 else (120, 112, 118, 255)
    d.rounded_rectangle((26, 10, 102, 118), 18, fill=(70, 62, 70, 255), outline=edge, width=5)
    d.rounded_rectangle((34, 18, 94, 110), 12, fill=(52, 46, 54, 255))
    d.line([(36, 24), (36, 104)], fill=(110, 102, 110, 255), width=3)
    d.line([(40, 20), (88, 20)], fill=(110, 102, 110, 255), width=3)
    lay = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    RUNE_GLYPH.get(var, rg_orb)(lay, el, t)
    glow = Image.new('RGBA', (S, S), rgba(PAL.get(el, PAL['neutral'])[0], 0))
    glow.putalpha(lay.getchannel('A').filter(ImageFilter.GaussianBlur(5)).point(lambda v: int(v * .8)))
    lay = Image.alpha_composite(glow, lay).resize((80, 80), Image.LANCZOS)
    img.alpha_composite(lay, (24, 24))

def rg_orb(img, el, t):
    d = ImageDraw.Draw(img)
    motif(d, el, 64, 64, (40, 46, 52, 54)[t])

def rg_area(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.polygon(star_pts(64, 64, 10, 60, 34), fill=M)
    d.ellipse((34, 34, 94, 94), fill=K)
    motif(d, el, 64, 64, 26)

def rg_field(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.rectangle((18, 18, 110, 110), outline=M, width=8)
    motif(d, el, 64, 64, 34)

def rg_wall(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for y in (24, 64, 104):
        d.rectangle((40, y - 18, 88, y + 18), outline=M, width=6)
        motif(d, el, 64, y, 13)

def rg_bomb(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for x, y in ((40, 40), (88, 40), (40, 88), (88, 88)):
        d.rectangle((x - 20, y - 20, x + 20, y + 20), outline=M, width=5)
        motif(d, el, x, y, 13)

def rg_heal(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    cross_shape(d, 64, 64, 50, M, L)

def rg_chain(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for i, (x, y) in enumerate(((30, 30), (52, 52), (74, 74), (96, 96))):
        box = (x - 22, y - 14, x + 22, y + 14)
        lay = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(lay).ellipse(box, outline=M if i % 2 else L, width=8)
        img.alpha_composite(lay.rotate(45 if i % 2 else -45, center=(x, y)))

def rg_brick(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for r, y in enumerate((18, 50, 82)):
        off = 0 if r % 2 == 0 else 22
        for x in range(-22 + off, 120, 44):
            d.rectangle((max(14, x + 2), y + 2, min(114, x + 42), y + 28), fill=M if (x // 44 + r) % 2 else L)

def rg_leaf(img, el, t):
    d = ImageDraw.Draw(img)
    motif(d, 'nature', 64, 64, 50)

def rg_destroy(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.rectangle((22, 22, 106, 106), outline=M, width=8)
    d.line([(18, 18), (110, 110)], fill=L, width=12)
    d.line([(110, 18), (18, 110)], fill=L, width=12)

def rg_shatter(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for pts in ([(20, 20), (60, 14), (54, 56)], [(70, 16), (110, 30), (76, 58)], [(18, 70), (52, 66), (40, 110)],
                [(66, 70), (112, 76), (90, 112)]):
        d.polygon(pts, fill=M)
    d.polygon(star_pts(64, 62, 4, 16, 4), fill=L)

def rg_heart(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.polygon(heart_pts(64, 66, 3.0), fill=M)
    d.polygon(heart_pts(52, 52, 1.0), fill=L)

def rg_mask(img, el, t):
    g_mask(img, el, t, None)

def rg_flask(img, el, t):
    g_cure(img, el, t, None)

def rg_skull(img, el, t):
    d = ImageDraw.Draw(img)
    motif(d, 'death', 64, 64, 54)

def rg_raise(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    d.ellipse((8, 8, 120, 120), outline=M, width=8)
    pts = [(64 + 52 * math.cos(math.radians(-90 + 144 * i)), 64 + 52 * math.sin(math.radians(-90 + 144 * i))) for i in range(6)]
    d.line(pts, fill=M, width=5)
    motif(d, 'death', 64, 64, 28)

def rg_soul(img, el, t):
    d = ImageDraw.Draw(img); M, L, K = P(el)
    for k, w in enumerate((12, 8)):
        pts = [(64 + (6 + i * 1.4) * math.cos(.22 * i + k * 3.1), 64 + (6 + i * 1.4) * math.sin(.22 * i + k * 3.1)) for i in range(36)]
        d.line(pts, fill=M if k == 0 else L, width=w)
    motif(d, 'fire', 64, 64, 18)

RUNE_GLYPH = {'orb': rg_orb, 'area': rg_area, 'field': rg_field, 'wall': rg_wall, 'bomb': rg_bomb, 'heal': rg_heal,
              'chain': rg_chain, 'brick': rg_brick, 'leaf': rg_leaf, 'destroy': rg_destroy, 'shatter': rg_shatter,
              'heart': rg_heart, 'mask': rg_mask, 'flask': rg_flask, 'skull': rg_skull, 'raise': rg_raise, 'soul': rg_soul}

def g_filler(img, el, t, var):
    d = ImageDraw.Draw(img); M, L, K = P('neutral')
    d.ellipse((30, 30, 98, 98), outline=rgba(M, 200), width=6)
    d.polygon([(64, 38), (84, 64), (64, 90), (44, 64)], fill=rgba(M, 220))
    d.polygon([(64, 52), (74, 64), (64, 76), (54, 64)], fill=K)

GLYPHS = {'strike': g_strike, 'wave': g_wave, 'beam': g_beam, 'area': g_area, 'burst': g_burstring, 'heal': g_heal,
          'regen': g_regen, 'cure': g_cure, 'dot': g_dot, 'haste': g_haste, 'levitate': g_levitate, 'rope': g_rope,
          'shield': g_shield, 'light': g_light, 'invis': g_invis, 'reveal': g_reveal, 'find': g_find, 'illusion': g_mask,
          'summon': g_summon, 'avatar': g_avatar, 'party': g_party, 'buff': g_buff, 'virtue': g_virtue,
          'meditate': g_meditate, 'holyground': g_holyground, 'flash': g_flash, 'challenge': g_challenge, 'ammo': g_ammo,
          'spear': g_spear, 'wand': g_wand, 'food': g_food, 'melee': g_melee, 'fist': g_fist, 'claw': g_claw,
          'rune': g_rune, 'filler': g_filler}

# ---------------------------------------------------------------- classification (words + icon key only)
def tier_of(tok, key):
    t = 1
    if {'infir', 'dis'} & set(tok) or ('min' in tok and tok[0] != 'exori'):
        t = 0
    if 'min' in tok and tok[:2] == ['exori', 'infir']:
        t = 0
    if {'gran', 'ulus'} & set(tok) or any(k in key for k in ('strong', 'intense', 'great')):
        t = max(t, 2)
    if 'max' in tok or 'ultimate' in key:
        t = 3
    return t

def element(tok, default='physical'):
    for w in tok:
        if w in EL:
            return EL[w]
    return default

def classify(words, typ, key):
    tok = words.lower().split()
    s = set(tok)
    w0 = tok[0] if tok else ''
    t = tier_of(tok, key)
    el = element(tok[1:])
    def r(kind, e=None, tier=None, var=None):
        return {'kind': kind, 'el': e or el, 'tier': t if tier is None else tier, 'var': var}
    # runes
    if typ == 'Conjure' and w0 in ('adori', 'adevo', 'adura', 'adana', 'adito', 'adeta'):
        if w0 == 'adori':
            if 'gran' in s and 'mort' in s: return r('rune', 'death', 2, 'skull')
            if 'mas' in s: return r('rune', tier=2, var='area')
            return r('rune', var='orb', tier=0 if 'min' in s else t)
        if w0 == 'adevo':
            if 'ina' in s: return r('rune', 'shadow', var='mask')
            if 'vita' in s: return r('rune', 'nature', var='leaf')
            if 'res' in s: return r('rune', 'fire', var='soul')
            if 'grav' in s and 'tera' in s: return r('rune', 'arcane', var='brick')
            if 'hur' in s: return r('rune', 'physical', 2, 'area')
            if 'mas' in s and 'grav' in s: return r('rune', tier=1, var='wall')
            if 'grav' in s: return r('rune', tier=1, var='field')
            if 'mas' in s: return r('rune', tier=1, var='bomb')
        if w0 == 'adura': return r('rune', 'heal', 3 if 'vita' in s else 2, 'heal')
        if w0 == 'adana':
            if 'ani' in s: return r('rune', 'shadow', 2, 'chain')
            if 'pox' in s: return r('rune', 'poison', var='flask')
            if 'mort' in s: return r('rune', 'death', var='raise')
        if w0 == 'adito':
            if 'tera' in s: return r('rune', 'earth', var='shatter')
            return r('rune', 'arcane', var='destroy')
        if w0 == 'adeta': return r('rune', 'holy', var='heart')
        return r('rune', var='orb')
    if w0 == 'uteta':
        if 'res' in s: return r('avatar', el, 3)
        return r('party', 'harmony', var='star')
    if w0 == 'utevo':
        if 'res' in s and 'ina' in s: return r('illusion', 'shadow')
        if 'res' in s:
            fam = element([x for x in tok if x in ('eq', 'sac', 'ven', 'dru', 'tio')], None)
            return r('summon', 'death' if not fam else fam, 2 if fam else 1, fam)
        if 'lux' in s: return r('light', 'light')
        if 'grav' in s: return r('holyground', el)
        if 'sio' in s: return r('party', 'light', var='sun')
        if 'nia' in s: return r('meditate', 'spirit')
    if w0 == 'exevo':
        if 'pan' in s: return r('food', 'food')
        if 'con' in s:
            return r('ammo', 'physical', 0 if 'infir' in s else 1, 'explosive' if 'flam' in s else None)
        if typ == 'Conjure' and 'mort' in s: return r('wand', 'death', 2)
        if 'hur' in s: return r('wave')
        if 'lux' in s or ('max' in s and 'mort' in s): return r('beam')
        if 'ulus' in s: return r('burst')
        if 'mas' in s: return r('area')
    if w0 == 'exeta':
        if 'con' in s: return r('spear', 'holy', var='enchant')
        return r('challenge', 'blood', 2 if 'amp' in s else 1)
    if w0 == 'exiva': return r('find', 'blood' if 'moe' in s else 'holy', var='fiend' if 'moe' in s else None)
    if w0 == 'utana': return r('invis', 'shadow')
    if w0 == 'exana':
        if 'ina' in s: return r('reveal', 'light')
        if 'amp' in s: return r('flash', 'holy')
        if 'vita' in s: return r('shield', 'arcane', var='broken')
        return r('cure')
    if w0 == 'utani':
        return r('haste', 'blood' if 'tempo' in s else 'arcane', var='charge' if 'tempo' in s else None)
    if w0 == 'exani': return r('rope', 'earth') if 'tera' in s else r('levitate', 'arcane')
    if w0 == 'utamo':
        if 'sio' in s: return r('party', 'arcane', var='shield')
        if 'vita' in s: return r('shield', 'arcane', 2, 'magic')
        if 'tio' in s: return r('shield', 'harmony', var='meditate')
        if 'san' in s: return r('haste', 'holy')
        return r('shield', 'physical', 2)
    if w0 == 'utito':
        if 'sio' in s: return r('party', 'blood', var='sword')
        if 'virtu' in s: return r('virtue', 'holy', var='up')
        if 'san' in s: return r('buff', 'holy', var='crosshair')
        return r('buff', 'blood', 2)
    if w0 == 'utori':
        if 'sio' in s: return r('party', 'energy', var='spark')
        if 'virtu' in s: return r('virtue', 'harmony')
        return r('dot')
    if w0 == 'utura':
        if 'sio' in s: return r('party', 'heal', var='heal')
        if 'tio' in s: return r('virtue', 'heal', var='down')
        return r('regen', 'heal')
    if w0 == 'exura':
        e = element(tok[1:], 'heal')
        if 'dis' in s or 'infir' in s:
            t = 0
        if 'sio' in s: return r('heal', e, var='friend')
        if 'mas' in s: return r('heal', e, var='mass')
        return r('heal', e, t)
    if w0 == 'exori':
        if 'amp' in s:
            if 'vis' in s: return r('strike', 'energy', 2)
            if 'kor' in s: return r('melee', 'blood', 2, 'axe')
            if 'pug' in s: return r('fist', 'monk', var='repulse')
        if 'hur' in s: return r('melee', 'physical', var='throw')
        if 'con' in s: return r('spear')
        if 'pug' in s:
            if 'mas' in s: return r('fist', var='flurry')
            if 'med' in s: return r('fist', var='chain')
            if 'gran' in s: return r('fist', var='uppercut')
            if 'infir' in s: return r('fist', tier=0)
            return r('fist', var='double')
        if 'nia' in s:
            if 'mas' in s and 'gran' in s: return r('area', 'spirit', 2)
            if 'mas' in s: return r('melee', 'spirit', var='sweep')
            return r('claw', 'spirit')
        if 'mas' in s:
            if 'res' in s: return r('area', 'harmony', 1)
            return r('melee', 'earth', var='quake')
        if 'moe' in s:
            if 'ico' in s: return r('strike', 'physical')
            return r('melee', 'arcane', var='shatter')
        if 'kor' in s: return r('melee', 'blood', var='drain')
        if 'ico' in s: return r('melee', 'blood', var='slash')
        if 'min' in s: return r('melee', 'physical', var='sweep')
        if len(tok) == 1 or tok[1:] == ['gran']: return r('melee', 'physical', var='spin')
        return r('strike')
    return r('filler', 'neutral', 1)

# ---------------------------------------------------------------- rendering
def frame(el, t):
    m, l, k = PAL.get(el, PAL['neutral'])
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rim = (120, 108, 112, 255) if t < 3 else (196, 150, 70, 255)
    d.rounded_rectangle((2, 2, S - 3, S - 3), 14, fill=(18, 13, 18, 255), outline=rim, width=4)
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((14, 14, S - 14, S - 14), fill=rgba(m, (70, 110, 130, 150)[t]))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(img)
    if t >= 2:
        d.rounded_rectangle((8, 8, S - 9, S - 9), 10, outline=rgba(m, 150), width=3)
    if t >= 3:
        for x, y in ((10, 10), (S - 11, 10), (10, S - 11), (S - 11, S - 11)):
            d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=rgba(l), outline=(90, 60, 20, 255), width=2)
    return img

def finish_glyph(g):
    """shade (light from the top left), add a dark outline and a soft drop shadow"""
    a = g.getchannel('A')
    grad = Image.linear_gradient('L').rotate(45, resample=Image.BILINEAR, expand=False).resize((S, S))
    light = Image.new('RGBA', (S, S), (255, 255, 255, 0))
    light.putalpha(Image.composite(Image.eval(grad, lambda v: int(max(0, 110 - v) * .5)), Image.new('L', (S, S), 0), a))
    dark = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    dark.putalpha(Image.composite(Image.eval(grad, lambda v: int(max(0, v - 150) * .55)), Image.new('L', (S, S), 0), a))
    g = Image.alpha_composite(Image.alpha_composite(g, light), dark)
    hard = a.point(lambda v: 255 if v > 60 else 0)
    outline = Image.new('RGBA', (S, S), INK[:3] + (0,))
    outline.putalpha(hard.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(.8)))
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    shadow.putalpha(hard.filter(ImageFilter.GaussianBlur(4)).point(lambda v: int(v * .6)))
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.alpha_composite(shadow, (3, 4))
    out.alpha_composite(outline)
    out.alpha_composite(g)
    return out

TIER_SCALE = (.8, .92, 1.0, 1.0)

def render(spec):
    el, t = spec['el'], spec['tier']
    if spec['kind'] == 'filler':
        img = frame('neutral', 0)
    else:
        img = frame(el, t)
    g = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    GLYPHS[spec['kind']](g, el, t, spec['var'])
    g = finish_glyph(g)
    n = int(round(100 * TIER_SCALE[t] if spec['kind'] not in ('rune', 'filler') else 100))
    g = g.resize((n, n), Image.LANCZOS)
    img.alpha_composite(g, ((S - n) // 2, (S - n) // 2))
    return img

def downscale(big, w, h):
    small = big.resize((w, h), Image.LANCZOS)
    rgb, a = small.convert('RGB'), small.getchannel('A')
    rgb = rgb.filter(ImageFilter.UnsharpMask(radius=0.7, percent=45, threshold=2))
    small = rgb.convert('RGBA'); small.putalpha(a)
    return small

# ---------------------------------------------------------------- spells.lua
def parse_spells_lua(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    i0 = text.index('SpellIcons = {')
    icons = {}
    body = text[i0:text.index('\n}', i0)]
    for m in re.finditer(r"\[\s*['\"]([^'\"]+)['\"]\s*\]\s*=\s*\{\s*(\d+)\s*,\s*(\d+)", body):
        icons[m.group(1)] = int(m.group(2))
    spells = {}
    j0 = text.index('SpellInfo = {')
    for line in text[j0:i0].splitlines():
        m = re.match(r'\s*\[\s*["\'](.+?)["\']\s*\]\s*=\s*\{(.*)\}\s*,?\s*$', line)
        if not m:
            continue
        b = m.group(2)
        def f(k):
            mm = re.search(r'\b' + k + r'\s*=\s*"([^"]*)"', b) or re.search(r'\b' + k + r"\s*=\s*'([^']*)'", b)
            return mm.group(1) if mm else ''
        ic = f('icon')
        if ic and ic not in spells:
            spells[ic] = {'name': m.group(1), 'words': f('words'), 'type': f('type')}
    cells = {}
    for key, cell in sorted(icons.items(), key=lambda kv: kv[1]):
        if cell in cells or key not in spells:
            continue
        cells[cell] = dict(spells[key], key=key)
    return cells

def build(cells):
    """cell -> (big 128 image or None, {size: small image}, label, spec)"""
    last = max(max(cells, default=0), CHAOS_FIRST + len(chaos.ICONS) - 1)
    rows = max(SHEETS[0][4], (last - 1) // COLS + 1)
    total = rows * COLS
    out = {}
    for n in range(1, total + 1):
        if CHAOS_FIRST <= n < CHAOS_FIRST + len(chaos.ICONS):
            name, theme, glyph = chaos.ICONS[n - CHAOS_FIRST]
            big = chaos.render(theme, glyph)
            smalls = {(w, h): big.resize((w, h), Image.LANCZOS) for _, w, h, _, _ in SHEETS}
            out[n] = (smalls, name, {'kind': 'chaos'})
            continue
        if n in cells:
            c = cells[n]
            spec = classify(c['words'], c['type'], c['key'])
            label = c['name']
        else:
            spec = {'kind': 'filler', 'el': 'neutral', 'tier': 1, 'var': None}
            label = ''
        big = render(spec)
        out[n] = ({(w, h): downscale(big, w, h) for _, w, h, _, _ in SHEETS}, label, spec)
    return out, rows

def write_sheets(icons, rows, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for suffix, w, h, mode, _ in SHEETS:
        sheet = Image.new('RGBA', (COLS * w, rows * h), (0, 0, 0, 0 if mode == 'RGBA' else 255))
        for n, (smalls, _, _) in icons.items():
            col, row = (n - 1) % COLS, (n - 1) // COLS
            sheet.alpha_composite(smalls[(w, h)], (col * w, row * h))
        if mode == 'RGB':
            base = Image.new('RGBA', sheet.size, (0, 0, 0, 255)); base.alpha_composite(sheet); sheet = base.convert('RGB')
        sheet.save(os.path.join(out_dir, f'spell-icons-{suffix}.png'), optimize=True)

def write_preview(icons, rows, path):
    cw, ch = 132, 118
    img = Image.new('RGB', (COLS * cw, rows * ch), (24, 20, 26))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.load_default(size=11)
    except TypeError:
        font = ImageFont.load_default()
    for n, (smalls, label, spec) in icons.items():
        col, row = (n - 1) % COLS, (n - 1) // COLS
        x, y = col * cw, row * ch
        s32 = smalls[(32, 32)]
        img.paste(s32.resize((64, 64), Image.NEAREST), (x + 4, y + 4), s32.resize((64, 64), Image.NEAREST))
        img.paste(s32, (x + 74, y + 4), s32)
        s22 = smalls[(22, 24)]; img.paste(s22, (x + 74, y + 40), s22)
        s20 = smalls[(20, 20)]; img.paste(s20, (x + 100, y + 42), s20)
        d.text((x + 4, y + 72), str(n) + ' ' + spec.get('kind', ''), fill=(150, 140, 160), font=font)
        words = (label or '-').split()
        lines, cur = [], ''
        for wd in words:
            if len(cur) + len(wd) + 1 > 21:
                lines.append(cur); cur = wd
            else:
                cur = (cur + ' ' + wd).strip()
        lines.append(cur)
        for i, ln in enumerate(lines[:2]):
            d.text((x + 4, y + 86 + 13 * i), ln, fill=(220, 210, 225), font=font)
    img.save(path, optimize=True)

def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--spells-lua', required=True, help="the client's modules/gamelib/spells.lua")
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--preview', help='also write a labelled preview (32x32 icons at x2, plus 32/22x24/20 at x1)')
    a = ap.parse_args()
    cells = parse_spells_lua(a.spells_lua)
    icons, rows = build(cells)
    write_sheets(icons, rows, a.out_dir)
    if a.preview:
        write_preview(icons, rows, a.preview)
    kinds = Counter(spec['kind'] for _, _, spec in icons.values())
    print(f'{len(icons)} cells ({rows} rows): ' + ', '.join(f'{k} {v}' for k, v in sorted(kinds.items())))

if __name__ == '__main__':
    main()
