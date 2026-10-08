#!/usr/bin/env python3
"""Ornate dark-fantasy UI skin for the Chaos client (procedural, original art).

usage: python3 client/tools/gen_skin.py [--base <base-client-dir>] [group ...]

Groups (default: all): frames, controls, stock, hud, ornaments.

Everything here is drawn by code: tileable value noise for iron, leather and stone, a height
map + light model for bevels, rivets, gold filigree and gems, all deterministic (fixed seeds).
It writes
  overlay/data/images/chaos/skin/*      new art used by the skin styles (data/styles overrides,
                                        client_chaos_theme, game_chaoshud)
  overlay/data/images/chaos/*.png       the frame/control art of the Chaos* styles (same sizes and
                                        9-slice borders as before, so styles.otui keeps working)
  overlay/data/images/<stock path>      stock images redrawn in place with the same size and layout
                                        (listed in STOCK below); they are removed from
                                        RESKIN_FILES.txt so tools/gen_ui_reskin.py leaves them alone.
Run gen_ui_reskin.py first (if at all), then this script. The 'stock' group needs --base (the assembled
base client source) for the layouts and silhouettes of the stock images it redraws.
nine_slice() renders a frame the way the engine stretches it (tiled edges), handy for previews.
Needs Pillow and numpy.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OVERLAY = os.path.normpath(os.path.join(HERE, '..', 'overlay'))
IMAGES = os.path.join(OVERLAY, 'data', 'images')
SKIN = 'chaos/skin'
WRITTEN = []


# ============================================================== palette
def hexc(s):
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


IRON_D = hexc('#141115')
IRON = hexc('#2b252b')
IRON_L = hexc('#4a4148')
STEEL = hexc('#6e656c')
LEATHER = hexc('#1a1214')
STONE = hexc('#16131a')
GOLD_D = hexc('#5c3d12')
GOLD = hexc('#b58331')
GOLD_L = hexc('#e8b84a')
GOLD_H = hexc('#ffe7a6')
BLOOD_D = hexc('#3a0606')
BLOOD = hexc('#9c120d')
BLOOD_L = hexc('#e03a1e')
ARCANE_D = hexc('#0a1a3a')
ARCANE = hexc('#2456b8')
ARCANE_L = hexc('#6fb4ff')
EMBER = hexc('#ff8a2a')
TEXT = hexc('#d6c9ae')
BLACK = np.zeros(3, np.float32)


# ============================================================== io
def out_path(rel):
    return os.path.join(IMAGES, rel if rel.endswith('.png') else rel + '.png')


def save(img, rel):
    p = out_path(rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if isinstance(img, np.ndarray):
        img = to_img(img)
    img.save(p, optimize=True)
    WRITTEN.append(rel if rel.endswith('.png') else rel + '.png')
    return img


def to_img(a):
    a = np.clip(a, 0, 1)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA')


def from_img(im):
    return np.asarray(im.convert('RGBA')).astype(np.float32) / 255.0


# ============================================================== noise
def tnoise(h, w, cells_y, cells_x, seed):
    """Tileable value noise (period = image size), smooth cosine interpolation, values 0..1."""
    rng = np.random.RandomState(seed)
    g = rng.rand(cells_y, cells_x).astype(np.float32)
    ys = np.arange(h, dtype=np.float32) * cells_y / h
    xs = np.arange(w, dtype=np.float32) * cells_x / w
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = (1 - np.cos(fy * math.pi)) / 2
    fx = (1 - np.cos(fx * math.pi)) / 2
    y1 = (y0 + 1) % cells_y
    x1 = (x0 + 1) % cells_x
    y0 %= cells_y
    x0 %= cells_x
    a = g[y0][:, x0]
    b = g[y0][:, x1]
    c = g[y1][:, x0]
    d = g[y1][:, x1]
    fx = fx[None, :]
    fy = fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(h, w, base=4, octaves=5, seed=0, persistence=0.55, aspect=1.0):
    """Tileable fractal noise in 0..1. base = lattice cells on the shorter side."""
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    tot = 0.0
    s = min(h, w)
    for o in range(octaves):
        cy = max(1, int(round(base * (2 ** o) * h / s)))
        cx = max(1, int(round(base * (2 ** o) * w / s * aspect)))
        out += amp * tnoise(h, w, cy, cx, seed * 131 + o * 7)
        tot += amp
        amp *= persistence
    out /= tot
    lo, hi = np.percentile(out, 1), np.percentile(out, 99)
    return np.clip((out - lo) / max(hi - lo, 1e-6), 0, 1)


def grain(h, w, seed, strength=1.0):
    rng = np.random.RandomState(seed)
    return (rng.rand(h, w).astype(np.float32) - 0.5) * strength


def scratches(h, w, seed, n=40, horizontal=True):
    """Fine tileable straight scratches, 0..1 mask."""
    rng = np.random.RandomState(seed)
    m = np.zeros((h, w), np.float32)
    for _ in range(n):
        ln = rng.randint(3, max(4, (w if horizontal else h) // 2))
        y = rng.randint(0, h)
        x = rng.randint(0, w)
        v = rng.uniform(0.3, 1.0)
        for i in range(ln):
            if horizontal:
                m[y % h, (x + i) % w] = max(m[y % h, (x + i) % w], v)
            else:
                m[(y + i) % h, x % w] = max(m[(y + i) % h, x % w], v)
    return m


# ============================================================== materials (albedo, h x w x 3)
def mat_iron(h, w, seed, tone=1.0, tint=IRON):
    n = fbm(h, w, base=3, octaves=5, seed=seed)
    n2 = fbm(h, w, base=12, octaves=3, seed=seed + 1)
    sc = scratches(h, w, seed + 2, n=max(4, h * w // 90))
    v = 0.78 + 0.32 * n + 0.10 * n2 + grain(h, w, seed + 3, 0.06) + 0.18 * sc
    return np.clip(tint[None, None, :] * (v * tone)[..., None], 0, 1)


def mat_gold(h, w, seed, tone=1.0):
    n = fbm(h, w, base=4, octaves=4, seed=seed)
    v = 0.85 + 0.25 * n + grain(h, w, seed + 5, 0.05)
    return np.clip(GOLD[None, None, :] * (v * tone)[..., None], 0, 1)


def mat_leather(h, w, seed, tint=LEATHER, tone=1.0):
    n = fbm(h, w, base=3, octaves=5, seed=seed)
    cells = fbm(h, w, base=14, octaves=2, seed=seed + 9)
    v = 0.80 + 0.45 * n + 0.15 * cells + grain(h, w, seed + 1, 0.05)
    return np.clip(tint[None, None, :] * (v * tone)[..., None], 0, 1)


def mat_stone(h, w, seed, tint=STONE, tone=1.0):
    n = fbm(h, w, base=2, octaves=6, seed=seed, persistence=0.6)
    v = 0.75 + 0.55 * n + grain(h, w, seed + 1, 0.05)
    return np.clip(tint[None, None, :] * (v * tone)[..., None], 0, 1)


# ============================================================== lighting
LIGHT = np.array([-0.55, -0.75, 0.9], np.float32)
LIGHT /= np.linalg.norm(LIGHT)


def shade(height, albedo, amb=0.42, diff=0.75, spec=0.35, shin=18.0, strength=1.0, spec_color=None):
    """Light an albedo with the normals of a height map (light from the top left)."""
    gy, gx = np.gradient(height.astype(np.float32))
    nx, ny, nz = -gx * strength, -gy * strength, np.ones_like(gx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    ndl = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
    hv = LIGHT + np.array([0, 0, 1], np.float32)
    hv /= np.linalg.norm(hv)
    sp = np.clip(nx * hv[0] + ny * hv[1] + nz * hv[2], 0, 1) ** shin
    # a flat area shows the plain albedo; slopes facing the light get brighter, others darker
    flat = LIGHT[2]
    k = np.clip(1.0 + diff * (ndl - flat) / flat, amb * 0.4, 2.2)
    sc = spec_color if spec_color is not None else np.array([1.0, 0.95, 0.85], np.float32)
    rgb = albedo * k[..., None] + spec * np.clip(sp - hv[2] ** shin, 0, None)[..., None] * sc
    return np.clip(rgb, 0, 1)


def rgba(rgb, alpha=None):
    h, w = rgb.shape[:2]
    a = np.ones((h, w), np.float32) if alpha is None else alpha
    return np.dstack([rgb, a]).astype(np.float32)


def over(dst, src, x=0, y=0):
    """Alpha-composite src (RGBA float) onto dst in place at x, y (clipped)."""
    h, w = src.shape[:2]
    H, W = dst.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(W, x + w), min(H, y + h)
    if x1 <= x0 or y1 <= y0:
        return dst
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]
    d = dst[y0:y1, x0:x1]
    sa = s[..., 3:4]
    da = d[..., 3:4]
    oa = sa + da * (1 - sa)
    rgb = (s[..., :3] * sa + d[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    dst[y0:y1, x0:x1] = np.dstack([rgb, oa])
    return dst


def blend_rgb(dst, color, mask):
    """dst rgb towards color by mask (h, w)."""
    m = np.clip(mask, 0, 1)[..., None]
    dst[..., :3] = dst[..., :3] * (1 - m) + np.asarray(color)[None, None, :3] * m
    return dst


# ============================================================== shapes (supersampled masks)
SS = 4


def mask_draw(w, h, fn, ss=SS, blur=0):
    """Draw with PIL at ss x and return an antialiased float mask (h, w)."""
    im = Image.new('L', (w * ss, h * ss), 0)
    d = ImageDraw.Draw(im)
    fn(d, ss)
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur * ss))
    im = im.resize((w, h), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def gauss(m, r):
    if r <= 0:
        return m
    im = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8), 'L').filter(ImageFilter.GaussianBlur(r))
    return np.asarray(im).astype(np.float32) / 255.0


def dist_rect(h, w):
    """Distance (px) of each pixel to the nearest image edge."""
    y = np.arange(h, dtype=np.float32)[:, None]
    x = np.arange(w, dtype=np.float32)[None, :]
    return np.minimum(np.minimum(x, w - 1 - x), np.minimum(y, h - 1 - y))


def sphere(r, ss=1):
    """Height of a hemisphere of radius r centred in a (2r+1) square, plus its mask."""
    n = 2 * r + 1
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    d2 = ((x - r) ** 2 + (y - r) ** 2) / max(r * r, 1e-6)
    m = np.clip((1.0 - d2) * r, 0, 1)
    h = np.sqrt(np.clip(1 - d2, 0, 1)) * r
    return h, m


# ============================================================== reusable pieces
def rivet(r=2.5, tone=1.0, metal=None):
    """Domed rivet, RGBA, size 2*ceil(r)+3 (with a soft drop shadow)."""
    R = int(math.ceil(r)) + 1
    n = 2 * R + 1
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt((xx - R) ** 2 + (yy - R) ** 2)
    hgt = np.sqrt(np.clip(1 - (d / r) ** 2, 0, 1)) * r * 1.2
    m = np.clip(r + 0.5 - d, 0, 1)
    alb = np.ones((n, n, 3), np.float32) * (STEEL if metal is None else metal)[None, None, :] * tone
    rgb = shade(hgt, alb, amb=0.35, diff=0.9, spec=0.9, shin=14, strength=0.9)
    out = np.zeros((n + 1, n + 1, 4), np.float32)
    sh = np.clip(r + 1.2 - d, 0, 1) * 0.6
    out[1:, 1:, 3] = sh
    over(out, rgba(rgb, m), 0, 0)
    return out


def gem(r, color, color_l, glow=0.0):
    """Faceted cabochon gem with a gold bezel; RGBA (2R+1)^2 where R = r + 2."""
    R = int(math.ceil(r)) + 2
    n = 2 * R + 1
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt((xx - R) ** 2 + (yy - R) ** 2)
    out = np.zeros((n, n, 4), np.float32)
    if glow > 0:
        g = np.clip(1 - d / (R + 0.5), 0, 1) ** 2 * glow
        out[..., :3] = color_l
        out[..., 3] = g
    # bezel ring
    ring_h = np.clip(1 - np.abs(d - (r + 0.9)) / 1.4, 0, 1)
    ring_m = np.clip(r + 2.2 - d, 0, 1)
    bez = shade(ring_h * 1.6, np.ones((n, n, 3), np.float32) * GOLD, amb=0.4, diff=0.9, spec=0.8, shin=10)
    over(out, rgba(bez, ring_m))
    # stone
    t = np.clip(d / max(r, 1e-6), 0, 1)
    hgt = np.sqrt(np.clip(1 - t ** 2, 0, 1)) * r
    alb = color[None, None, :] * (1 - t[..., None]) * 0.6 + color[None, None, :] * 0.5
    # inner glow from below right
    inner = np.clip(1 - np.sqrt((xx - R - r * 0.25) ** 2 + (yy - R - r * 0.3) ** 2) / (r * 0.9), 0, 1)
    alb = alb + color_l[None, None, :] * inner[..., None] * 0.7
    rgb = shade(hgt, alb, amb=0.55, diff=0.6, spec=1.0, shin=30, strength=1.2)
    # specular dot top-left
    sd = np.sqrt((xx - R + r * 0.38) ** 2 + (yy - R + r * 0.38) ** 2)
    rgb = rgb + np.clip(1 - sd / max(r * 0.28, 0.7), 0, 1)[..., None] * 0.8
    m = np.clip(r + 0.4 - d, 0, 1)
    over(out, rgba(np.clip(rgb, 0, 1), m))
    return out


def ridge_profile(d, start, width, height=1.0, round_=True):
    """Height of a ridge running along an iso-line of d (distance field)."""
    t = (d - start) / max(width, 1e-6)
    inside = (t >= 0) & (t <= 1)
    if round_:
        v = np.sin(np.clip(t, 0, 1) * math.pi) * height
    else:
        v = np.ones_like(d) * height
    return np.where(inside, v, 0.0).astype(np.float32)


def bevel_box(w, h, bw, face, edge_hi=0.35, edge_lo=0.45, outline=True, round_px=0):
    """Generic bevelled plate: face is an albedo (h, w, 3); returns RGBA."""
    d = dist_rect(h, w)
    hgt = np.clip(d / max(bw, 1e-6), 0, 1)
    hgt = np.sin(hgt * math.pi / 2) * bw * 0.9
    rgb = shade(hgt, face, amb=0.5, diff=0.7, spec=0.25, shin=12, strength=1.0)
    a = np.ones((h, w), np.float32)
    if round_px:
        a = round_mask(w, h, round_px)
    out = rgba(rgb, a)
    if outline:
        edge = (d < 1).astype(np.float32)
        blend_rgb(out, BLACK, edge * 0.85)
    return out


def round_mask(w, h, r):
    return mask_draw(w, h, lambda d, s: d.rounded_rectangle([0, 0, w * s - 1, h * s - 1], radius=r * s, fill=255))


# ============================================================== filigree
def curl_points(cx, cy, r0, r1, a0, turns, n=60, flip=1):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = a0 + flip * turns * 2 * math.pi * t
        r = r0 + (r1 - r0) * t
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def poly_stroke(d, pts, width, s, fill=255):
    p = [(x * s, y * s) for x, y in pts]
    d.line(p, fill=fill, width=max(1, int(round(width * s))), joint='curve')
    r = width * s / 2
    for x, y in (p[0], p[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def bezier(p0, p1, p2, p3, n=40):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        e = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1]))
    return out


def metal_from_mask(m, albedo, height_scale=2.2, blur=0.8, amb=0.38, diff=0.85, spec=0.9, shin=12,
                    outline=0.9, shadow=0.75, shadow_off=(1, 1)):
    """Turn a coverage mask into an embossed metal piece with a dark outline and a drop shadow (RGBA)."""
    h, w = m.shape
    hg = gauss(m, blur) * height_scale
    rgb = shade(hg, albedo, amb=amb, diff=diff, spec=spec, shin=shin, strength=1.4)
    out = np.zeros((h, w, 4), np.float32)
    if shadow:
        sh = gauss(m, 1.2) * shadow
        sh = np.roll(np.roll(sh, shadow_off[1], 0), shadow_off[0], 1)
        out[..., 3] = sh
    if outline:
        ol = np.clip(gauss(m, 0.7) * 2.2, 0, 1)
        over(out, rgba(np.zeros((h, w, 3), np.float32) + IRON_D * 0.4, ol * outline))
    over(out, rgba(rgb, m))
    return out


# ============================================================== 9-slice preview (engine-like: edges tiled)
def nine_slice(img, w, h, l, t, r, b):
    src = img
    H, W = src.shape[:2]
    out = np.zeros((h, w, 4), np.float32)
    cw, ch = W - l - r, H - t - b

    def tile(part, tw, th):
        if tw <= 0 or th <= 0 or part.size == 0:
            return np.zeros((max(th, 0), max(tw, 0), 4), np.float32)
        ry = int(math.ceil(th / part.shape[0]))
        rx = int(math.ceil(tw / part.shape[1]))
        return np.tile(part, (ry, rx, 1))[:th, :tw]

    iw, ih = w - l - r, h - t - b
    out[:t, :l] = src[:t, :l]
    out[:t, w - r:] = src[:t, W - r:]
    out[h - b:, :l] = src[H - b:, :l]
    out[h - b:, w - r:] = src[H - b:, W - r:]
    out[:t, l:w - r] = tile(src[:t, l:W - r], iw, t)
    out[h - b:, l:w - r] = tile(src[H - b:, l:W - r], iw, b)
    out[t:h - b, :l] = tile(src[t:H - b, :l], l, ih)
    out[t:h - b, w - r:] = tile(src[t:H - b, W - r:], r, ih)
    out[t:h - b, l:w - r] = tile(src[t:H - b, l:W - r], iw, ih)
    return out


# ============================================================== frames
def tiled(tex, H, W, L, T):
    """Spread a (ch, cw) tileable texture over H x W so that it repeats seamlessly from (L, T)."""
    ch, cw = tex.shape[:2]
    ys = (np.arange(H) - T) % ch
    xs = (np.arange(W) - L) % cw
    return tex[ys][:, xs]


def center_material(kind, ch, cw, seed):
    if kind == 'leather':
        return mat_leather(ch, cw, seed)
    if kind == 'stone':
        return mat_stone(ch, cw, seed)
    if kind == 'iron':
        return mat_iron(ch, cw, seed, tone=0.75)
    if kind == 'abyss':
        return mat_stone(ch, cw, seed, tint=hexc('#100d12'))
    raise ValueError(kind)


def frame(W, H, L, T, R, B, outer=None, trim=True, title=0, center='leather', seed=1, gold_trim=True,
          corner_caps=True, title_grooves=True, outer_tint=IRON, center_tone=1.0, rivets=True):
    """A 9-slice window frame.

    outer: thickness of the iron band (default min(L, R, B) - 3); a gold trim ridge follows it, then a
    dark inset line.  title: height of a title plate inside the top border (0 = none).
    Every texture repeats with the period of the stretchable middle, so the engine's tiling is seamless.
    """
    ch, cw = H - T - B, W - L - R
    if outer is None:
        outer = max(2, min(L, R, B) - 3)
    d = dist_rect(H, W)
    iron = tiled(mat_iron(ch, cw, seed, tint=outer_tint), H, W, L, T)
    cen = tiled(center_material(center, ch, cw, seed + 10), H, W, L, T) * center_tone

    hgt = np.zeros((H, W), np.float32)
    alb = cen.copy()
    # iron band
    band = d < outer
    hgt += ridge_profile(d, 0, outer, outer * 0.55)
    alb[band] = iron[band]
    # title plate (inside the top border, between the side bands)
    if title:
        y = np.arange(H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
        tp = (y >= outer) & (y < title) & (d >= outer)
        plate = tiled(mat_iron(ch, cw, seed + 3, tone=0.62, tint=outer_tint), H, W, L, T)
        if title_grooves:
            g = ((y - outer) % 4 == 0) & (y > outer + 2) & (y < title - 3)
            plate = plate * np.where(g, 0.82, 1.0)[..., None]
        # soft vertical gradient: lighter at the top
        tt = np.clip((y - outer) / max(title - outer, 1), 0, 1)
        plate = plate * (1.15 - 0.3 * tt)[..., None]
        alb[tp] = plate[tp]
        hgt[tp] = 0.6 + (1 - tt[tp]) * 0.4
    # gold trim ridge around the content (and under the title plate)
    if trim:
        if title:
            yy = np.arange(H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
            dt = np.minimum(d, np.where(yy >= title - 2, yy - (title - 2), 1e3))
            dt = np.where(yy < title - 2, np.where(d >= outer, np.minimum(d, 1e3), d), d)
            # distance to the content box (left/right/bottom = outer, top = title - 2)
            xx = np.arange(W, dtype=np.float32)[None, :] * np.ones((H, 1), np.float32)
            dx = np.minimum(xx - outer, W - 1 - outer - xx)
            dyb = H - 1 - outer - yy
            dyt = yy - (title - 2)
            dc = np.minimum(np.minimum(dx, dyb), dyt)
            ring = (dc >= 0) & (dc < 2)
        else:
            dc = d - outer
            ring = (dc >= 0) & (dc < 2)
        gold = tiled(mat_gold(ch, cw, seed + 4), H, W, L, T) if gold_trim else iron * 1.4
        hgt = np.where(ring, 1.4 + np.sin(np.clip(dc, 0, 2) / 2 * math.pi) * 0.8, hgt)
        alb[ring] = gold[ring]
        # inset shadow just inside the trim, kept inside the borders so the tiled middle stays clean
        yy = np.arange(H)[:, None] * np.ones((1, W))
        xx = np.arange(W)[None, :] * np.ones((H, 1))
        in_border = (xx < L) | (xx >= W - R) | (yy < T) | (yy >= H - B)
        sh = (dc >= 2) & (dc < 4) & in_border
        k = np.where(sh, 0.5 + 0.5 * np.clip((dc - 2) / 2, 0, 1), 1.0)
        alb = alb * k[..., None]
    rgb = shade(hgt, alb, amb=0.4, diff=0.85, spec=0.45, shin=14, strength=1.1)
    out = rgba(rgb)
    # bright steel edge on the inner side of the iron band
    if outer >= 5:
        blend_rgb(out, STEEL * 1.2, ((d >= outer - 1) & (d < outer) & ~((np.arange(H)[:, None] < title) & (d >= outer - 1) & (np.arange(H)[:, None] >= outer))).astype(np.float32) * 0.35)
    # one rivet per tile period on the side and bottom bands
    if rivets and outer >= 6:
        rv = rivet(outer * 0.22, metal=STEEL * 0.95)
        rh, rw = rv.shape[:2]
        cyy = T + ch // 2 - rh // 2
        cxx = L + cw // 2 - rw // 2
        mid = outer // 2
        over(out, rv, mid - rw // 2, cyy)
        over(out, rv, W - 1 - mid - rw // 2, cyy)
        over(out, rv, cxx, H - 1 - mid - rh // 2)
        if not title:
            over(out, rv, cxx, mid - rh // 2)
    # outer black outline + a faint inner highlight line of the band
    blend_rgb(out, BLACK, (d < 1).astype(np.float32) * 0.9)
    if corner_caps:
        cap = min(L, outer + 3)
        for (cx, cy, fx, fy) in ((0, 0, 1, 1), (W - cap, 0, -1, 1), (0, H - cap, 1, -1), (W - cap, H - cap, -1, -1)):
            if cap >= 6 and (cy == 0 or B >= cap) and (cx == 0 or R >= cap):
                over(out, corner_cap(cap, seed + cx + cy), cx, cy)
    return out


def corner_cap(n, seed):
    """Square gold-edged iron boss with a rivet, n x n."""
    face = mat_iron(n, n, seed, tone=1.1)
    d = dist_rect(n, n)
    hgt = np.clip(d / 2.0, 0, 1) * 1.5
    alb = face.copy()
    rim = d < 1.6
    alb[rim] = (GOLD * 0.9)[None, :]
    rgb = shade(hgt, alb, amb=0.4, diff=0.8, spec=0.6)
    o = rgba(rgb)
    blend_rgb(o, BLACK, (d < 0.8).astype(np.float32) * 0.9)
    rv = rivet(max(1.2, n / 5.5), metal=GOLD_L * 0.9)
    over(o, rv, (n - rv.shape[1]) // 2, (n - rv.shape[0]) // 2)
    return o


def gold_albedo(h, w, seed=7, tone=1.0):
    n = fbm(h, w, base=3, octaves=3, seed=seed)
    v = (0.9 + 0.25 * n) * tone
    return np.clip(GOLD[None, None, :] * v[..., None] * 1.05, 0, 1)


def ornament_corner(size=44, gem_color=None, gem_light=None, seed=1):
    """Top-left corner ornament: gold bracket with scroll curls, a fleur spike and a set gem.
    The gem centre sits at (14, 14); mirror it for the other corners."""
    gem_color = BLOOD if gem_color is None else gem_color
    gem_light = BLOOD_L if gem_light is None else gem_light
    S = size

    def draw(d, s):
        # arms along the top and the left edge
        poly_stroke(d, [(12, 9.5), (S - 12, 9.5)], 3.2, s)
        poly_stroke(d, [(9.5, 12), (9.5, S - 12)], 3.2, s)
        # thin outer rail
        poly_stroke(d, [(16, 5.5), (S - 16, 5.5)], 1.4, s)
        poly_stroke(d, [(5.5, 16), (5.5, S - 16)], 1.4, s)
        # scroll curls at the arm ends, turning inwards
        poly_stroke(d, curl_points(S - 9.5, 14.5, 5.0, 1.2, -math.pi / 2, 0.85, flip=1), 2.2, s)
        poly_stroke(d, curl_points(14.5, S - 9.5, 5.0, 1.2, math.pi, 0.85, flip=-1), 2.2, s)
        # inner vine from the corner, curling into a small scroll on the diagonal
        poly_stroke(d, bezier((16, 16), (22, 16), (24, 20), (22, 24)), 1.6, s)
        poly_stroke(d, curl_points(20.3, 22.6, 2.4, 0.6, 0.2, 0.9, flip=1), 1.4, s)
        poly_stroke(d, bezier((16, 16), (16, 22), (20, 24), (24, 22)), 1.6, s)
        # fleur spike pointing out of the corner
        pts = [(1, 1), (8.5, 5), (14, 14), (5, 8.5)]
        d.polygon([(x * s, y * s) for x, y in pts], fill=255)
        # boss around the gem
        r = 7.2
        d.ellipse([(14 - r) * s, (14 - r) * s, (14 + r) * s, (14 + r) * s], fill=255)

    m = mask_draw(S, S, draw)
    piece = metal_from_mask(m, gold_albedo(S, S, seed), height_scale=2.6, blur=0.9)
    g = gem(4.6, gem_color, gem_light)
    over(piece, g, 14 - g.shape[1] // 2, 14 - g.shape[0] // 2)
    return piece


def mirror(img, fx, fy):
    o = img
    if fx:
        o = o[:, ::-1]
    if fy:
        o = o[::-1, :]
    return np.ascontiguousarray(o)


def ornament_crest(w=84, h=30, gem_color=None, gem_light=None, seed=2):
    """Title crest: a pointed gem in a winged gold setting with scroll ends."""
    gem_color = BLOOD if gem_color is None else gem_color
    gem_light = BLOOD_L if gem_light is None else gem_light
    cx, cy = w / 2, h / 2 + 1

    def draw(d, s):
        # wings: two swept blades
        for sg in (-1, 1):
            p = bezier((cx + sg * 8, cy - 3), (cx + sg * 20, cy - 9), (cx + sg * 30, cy - 4), (cx + sg * 38, cy + 1))
            q = bezier((cx + sg * 38, cy + 1), (cx + sg * 28, cy + 1), (cx + sg * 18, cy + 5), (cx + sg * 8, cy + 5))
            d.polygon([(x * s, y * s) for x, y in p + q], fill=255)
            poly_stroke(d, curl_points(cx + sg * 35.5, cy + 3.8, 3.0, 0.8, -math.pi / 2 if sg > 0 else -math.pi / 2,
                                       0.8, flip=sg), 1.6, s)
            poly_stroke(d, bezier((cx + sg * 9, cy - 7), (cx + sg * 14, cy - 13), (cx + sg * 20, cy - 12), (cx + sg * 22, cy - 9)), 1.5, s)
        # central pointed setting (diamond)
        d.polygon([(cx * s, (cy - 14) * s), ((cx + 10) * s, cy * s), (cx * s, (cy + 14) * s), ((cx - 10) * s, cy * s)], fill=255)

    m = mask_draw(w, h, draw)
    piece = metal_from_mask(m, gold_albedo(h, w, seed), height_scale=2.6, blur=0.9)
    # dark inlay lines on the wings
    g = gem(5.2, gem_color, gem_light, glow=0.0)
    over(piece, g, int(cx) - g.shape[1] // 2, int(cy) - g.shape[0] // 2)
    return piece


# ============================================================== controls
def edge_maps(H, W):
    y = np.arange(H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
    x = np.arange(W, dtype=np.float32)[None, :] * np.ones((H, 1), np.float32)
    return x, y, x, W - 1 - x, y, H - 1 - y   # x, y, dl, dr, dt, db


def button_face(W, H, b, state, seed=11, rim=None, face_tint=None, round_corner=True):
    """Bevelled iron button with a metal rim. Bevel and rim live inside the b px border, the middle is
    flat (tileable) so the engine can stretch it.  state: normal, hover, pressed, disabled, on."""
    ch, cw = max(1, H - 2 * b), max(1, W - 2 * b)
    x, y, dl, dr, dt, db = edge_maps(H, W)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
    tint = IRON if face_tint is None else face_tint
    tone = {'normal': 1.15, 'hover': 1.35, 'pressed': 0.8, 'disabled': 0.75, 'on': 0.95}[state]
    face = tiled(mat_iron(ch, cw, seed, tone=tone, tint=tint), H, W, b, b)
    if state == 'on':
        face = face * 0.55 + BLOOD[None, None, :] * 0.35
    if rim is None:
        rim = {'normal': GOLD * 0.85, 'hover': GOLD_L * 1.05, 'pressed': GOLD * 0.6, 'disabled': STEEL * 0.6,
               'on': GOLD_L}[state]
    alb = face.copy()
    ring = (d >= 1) & (d < 2)
    alb[ring] = rim
    # bevel inside the rim: light top/left, dark bottom/right (inverted when pressed)
    up = state != 'pressed'
    k = np.ones((H, W), np.float32)
    bev = b - 2
    if bev > 0:
        near = np.argmin(np.stack([dt, dl, db, dr]), 0)
        zone = (d >= 2) & (d < b)
        fall = np.clip(1 - (d - 2) / max(bev, 1), 0, 1)
        lit = zone & (near <= 1)
        drk = zone & (near >= 2)
        k = np.where(lit, 1 + (0.5 if up else -0.4) * fall, k)
        k = np.where(drk, 1 - (0.45 if up else -0.15) * fall, k)
    rgb = np.clip(alb * k[..., None], 0, 1)
    if state == 'hover':
        # ember glow creeping in from the rim
        glow = np.exp(-np.clip(d - 2, 0, None) / 1.6) * (d >= 2)
        rgb = np.clip(rgb + glow[..., None] * EMBER[None, None, :] * 0.45, 0, 1)
    # rim highlight on top edge
    rgb[(d >= 1) & (d < 2) & (dt < 2)] = np.clip(rim * 1.35, 0, 1)
    out = rgba(rgb)
    blend_rgb(out, BLACK, (d < 1).astype(np.float32) * 0.92)
    if round_corner:
        for (cx, cy) in ((0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)):
            out[cy, cx, 3] = 0.0
    if state == 'disabled':
        g = out[..., :3].mean(-1, keepdims=True)
        out[..., :3] = out[..., :3] * 0.4 + g * 0.6
    return out


def stack(*imgs):
    return np.concatenate(imgs, 0)


def panel(W, H, b, kind='inset', center='abyss', seed=21, rim=None, outline=0.9, tone=1.0, gold=False, bev=2):
    """Inner panel: an inset (sunken) or raised plate, bevel inside the b px border, tileable middle."""
    ch, cw = max(1, H - 2 * b), max(1, W - 2 * b)
    x, y, dl, dr, dt, db = edge_maps(H, W)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
    face = tiled(center_material(center, ch, cw, seed), H, W, b, b) * tone
    rgb = face.copy()
    tl = (np.minimum(dt, dl) < np.minimum(db, dr))
    inner = (d >= 1) & (d < min(b, bev + 1))
    if kind == 'inset':
        rgb[inner & tl] *= 0.45
        rgb[inner & ~tl] = rgb[inner & ~tl] * 0.7 + (GOLD * 0.45 if gold else IRON_L * 0.5)
    else:
        rgb[inner & tl] = rgb[inner & tl] * 0.5 + (GOLD * 0.55 if gold else IRON_L * 0.75)
        rgb[inner & ~tl] *= 0.5
    out = rgba(np.clip(rgb, 0, 1))
    if rim is not None:
        blend_rgb(out, rim, ((d >= 1) & (d < 2)).astype(np.float32) * 0.85)
    blend_rgb(out, BLACK, (d < 1).astype(np.float32) * outline)
    return out


def slot(n=34, seed=31, rim=GOLD, inner=None):
    """Item slot: dark recessed well, bronze bevel, gold hairline, small corner studs."""
    x, y, dl, dr, dt, db = edge_maps(n, n)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
    face = mat_stone(n, n, seed, tint=hexc('#120e12') if inner is None else inner)
    # radial darkening towards the middle (a well)
    c = (n - 1) / 2
    rr = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    face = face * (0.75 + 0.35 * np.clip(rr, 0, 1))[..., None]
    rgb = face
    tl = np.minimum(dt, dl) < np.minimum(db, dr)
    band = d < 3
    metal = mat_iron(n, n, seed + 1, tone=1.2)
    rgb[band] = metal[band]
    hg = np.where(band, np.sin(np.clip(d / 3, 0, 1) * math.pi), 0)
    rgb = shade(hg * 1.2, rgb, amb=0.4, diff=0.8, spec=0.4)
    out = rgba(rgb)
    blend_rgb(out, rim, ((d >= 3) & (d < 4)).astype(np.float32) * 0.8)
    blend_rgb(out, BLACK, ((d >= 4) & (d < 5) & tl).astype(np.float32) * 0.6)
    blend_rgb(out, BLACK, (d < 1).astype(np.float32) * 0.95)
    for cx, cy in ((1, 1), (n - 4, 1), (1, n - 4), (n - 4, n - 4)):
        over(out, corner_stud(), cx, cy)
    return out


def corner_stud():
    m = np.zeros((3, 3, 4), np.float32)
    m[..., :3] = GOLD * 1.05
    m[..., 3] = np.array([[0.3, 0.9, 0.3], [0.9, 1, 0.9], [0.3, 0.9, 0.3]])
    m[0, 0, :3] = m[0, 1, :3] = GOLD_H
    return m


def text_field(W, H, b=1, seed=41, focus=False):
    x, y, dl, dr, dt, db = edge_maps(H, W)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
    ch, cw = max(1, H - 2 * b), max(1, W - 2 * b)
    face = tiled(mat_stone(ch, cw, seed, tint=hexc('#0c090b')), H, W, b, b)
    out = rgba(face)
    blend_rgb(out, GOLD_L if focus else hexc('#6b4f2a'), (d < 1).astype(np.float32))
    if b >= 2:
        blend_rgb(out, BLACK, ((d >= 1) & (d < 2) & (np.minimum(dt, dl) < np.minimum(db, dr))).astype(np.float32) * 0.8)
    return out


# ---------------------------------------------------------------- relight (layout-faithful reskin of small sheets)
def relight(src, glyph_gold=True, seed=51):
    """Redraw a stock grey sheet in the skin's materials, keeping every pixel's role:
    shadows -> black iron, faces -> textured iron, bright bevel lines -> bronze/gold, glyphs -> bright gold.
    Saturated pixels (red arrows, flags) keep their hue, warmed."""
    a = from_img(src)
    rgb, al = a[..., :3], a[..., 3]
    h, w = al.shape
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    # the stock stone grain would show through as diagonal streaks: smooth it on the flat faces
    soft = gauss(lum, 1.5)
    flatness = np.clip(1 - np.abs(lum - 0.26) / 0.12, 0, 1)
    lum = lum * (1 - flatness) + soft * flatness
    tex = mat_iron(h, w, seed, tone=1.0)
    out = np.zeros_like(rgb)
    # piecewise palette by luminance
    stops = [(0.00, BLACK), (0.12, IRON_D * 0.9), (0.24, IRON * 1.0), (0.33, IRON_L * 1.05),
             (0.45, GOLD_D * 1.2), (0.60, GOLD * 1.0), (0.78, GOLD_L), (1.0, GOLD_H)]
    xs = np.array([s_[0] for s_ in stops], np.float32)
    for c in range(3):
        out[..., c] = np.interp(lum, xs, np.array([s_[1][c] for s_ in stops], np.float32))
    # texture only on the iron range
    ironish = np.clip(1 - np.abs(lum - 0.26) / 0.14, 0, 1)[..., None]
    out = out * (1 - ironish * 0.6) + (tex * (out.mean(-1, keepdims=True) / max(IRON.mean(), 1e-3))) * ironish * 0.6
    keep = np.clip((sat - 0.2) / 0.2, 0, 1)[..., None]
    warm = rgb * np.array([1.1, 0.85, 0.7], np.float32)
    out = out * (1 - keep) + np.clip(warm, 0, 1) * keep
    return np.dstack([np.clip(out, 0, 1), al])


# ============================================================== groups
def gen_ornaments():
    c = ornament_corner(44)
    for name, fx, fy in (('tl', 0, 0), ('tr', 1, 0), ('bl', 0, 1), ('br', 1, 1)):
        save(mirror(c, fx, fy), SKIN + '/orn_corner_' + name)
    save(ornament_crest(), SKIN + '/orn_crest')
    c = ornament_corner(44, ARCANE, ARCANE_L, seed=5)
    for name, fx, fy in (('tl', 0, 0), ('tr', 1, 0), ('bl', 0, 1), ('br', 1, 1)):
        save(mirror(c, fx, fy), SKIN + '/orn_corner_blue_' + name)


def gen_frames():
    # main window: borders 12 / 32 / 12 / 12 (title plate inside the top border)
    save(frame(128, 128, 12, 32, 12, 12, outer=8, title=30, seed=3), SKIN + '/window')
    # Chaos* windows (styles.otui: border 18, top 34)
    save(frame(96, 96, 18, 34, 18, 18, outer=11, title=32, seed=4), 'chaos/window')
    # stock frames redrawn in place (same size; their styles slice them with small borders)
    save(frame(236, 207, 4, 19, 4, 4, outer=2, title=19, seed=5, corner_caps=False, rivets=False), 'ui/window')
    save(frame(236, 207, 4, 17, 4, 4, outer=2, title=17, seed=6, corner_caps=False, rivets=False), 'ui/popupwindow')
    save(frame(102, 114, 4, 19, 4, 4, outer=2, title=19, seed=7, corner_caps=False, rivets=False), 'ui/map-borderimage')
    save(frame(45, 30, 5, 5, 5, 5, outer=3, seed=8, corner_caps=False, rivets=False), 'ui/window_headless')


def gen_controls():
    states = ('normal', 'hover', 'pressed', 'disabled')
    # skin Button sheet (data/styles/10-buttons.otui): 4 states of 64 x 24, image-border 5
    save(stack(*[button_face(64, 24, 5, st, seed=11) for st in states]), SKIN + '/button')
    # Chaos* buttons (48 x 24, border 6)
    for st in states:
        save(button_face(48, 24, 6, st, seed=12), 'chaos/button_' + st)
    # tabs: normal / hover / on
    save(stack(*[button_face(64, 24, 5, st, seed=13) for st in ('normal', 'hover', 'on')]), SKIN + '/tab')
    for st, nm in (('normal', 'normal'), ('hover', 'hover'), ('on', 'active')):
        save(button_face(40, 24, 6, st, seed=14), 'chaos/tab_' + nm)
    # panels
    save(panel(32, 32, 8, 'inset', 'abyss', seed=22, gold=True), 'chaos/panel')
    save(panel(32, 32, 6, 'inset', 'abyss', seed=23, tone=0.8), 'chaos/panel_dark')
    save(panel(32, 32, 8, 'raised', 'leather', seed=24, gold=True, rim=GOLD_L), 'chaos/panel_highlight')
    save(text_field(32, 22, 4, seed=42), 'chaos/textedit')
    save(text_field(32, 22, 4, seed=42, focus=True), 'chaos/textedit_focus')
    save(slot(34, seed=32), 'chaos/itemslot')
    save(title_plate(64, 24), 'chaos/title_plate')
    save(separator(64, 8), 'chaos/separator')
    save(progress_frame(32, 16), 'chaos/progress_frame')
    save(checkbox_sheet(16), 'chaos/checkbox')
    save(combobox_img(40, 22, 18), 'chaos/combobox')
    for st, nm in (('normal', ''), ('hover', '_hover'), ('pressed', '_pressed')):
        save(button_face(13, 17, 3, st, seed=15), 'chaos/scroll_slider' + nm)
        save(arrow_button(13, st, 'up'), 'chaos/scroll_up' + nm)
        save(arrow_button(13, st, 'down'), 'chaos/scroll_down' + nm)
    save(panel(13, 32, 1, 'inset', 'abyss', seed=25), 'chaos/scroll_track')
    save(topbar_bg(32, 44), 'chaos/topbar_bg')
    # menu bar of client_chaos_topbar (image-border 8)
    save(frame(64, 36, 8, 8, 8, 8, outer=5, seed=20, center='abyss', rivets=False), SKIN + '/menubar')
    # highlight frame a base module asks for but the base client does not ship (proficiency window)
    save(glow_frame(22, 22), 'animations/button-highlight-22x22')
    # tooltip and popup menu
    save(panel(32, 32, 4, 'raised', 'abyss', seed=26, rim=GOLD), SKIN + '/tooltip')


def glow_frame(W, H):
    d = dist_rect(H, W)
    a = np.exp(-d / 1.6) * 0.9
    o = np.zeros((H, W, 4), np.float32)
    o[..., :3] = GOLD_L
    o[..., 3] = a
    o[d < 1, :3] = GOLD_H
    return o


def title_plate(W, H):
    o = button_face(W, H, 6, 'normal', seed=16, face_tint=hexc('#2a1a1c'))
    for x in (4, W - 8):
        rv = rivet(1.6, metal=GOLD_L)
        over(o, rv, x - 1, H // 2 - rv.shape[0] // 2)
    return o


def separator(W, H):
    def draw(d, s):
        poly_stroke(d, [(6, H / 2), (W - 6, H / 2)], 1.3, s)
        for cx in (4, W - 4):
            d.polygon([((cx) * s, (H / 2 - 3.5) * s), ((cx + 3.5) * s, H / 2 * s), (cx * s, (H / 2 + 3.5) * s),
                       ((cx - 3.5) * s, H / 2 * s)], fill=255)
    m = mask_draw(W, H, draw)
    return metal_from_mask(m, gold_albedo(H, W), height_scale=1.2, blur=0.5, shadow=0.5)


def progress_frame(W, H):
    o = panel(W, H, 3, 'inset', 'abyss', seed=27, rim=GOLD * 0.8)
    o[3:-3, 3:-3, 3] = 0.35   # translucent track so the fill shows through
    return o


def checkbox_sheet(n):
    box = text_field(n, n, 2, seed=43)
    x, y, dl, dr, dt, db = edge_maps(n, n)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
    blend_rgb(box, GOLD * 0.9, (d < 1).astype(np.float32))
    chk = box.copy()

    def draw(dd, s):
        poly_stroke(dd, [(n * 0.22, n * 0.52), (n * 0.42, n * 0.72), (n * 0.80, n * 0.24)], n * 0.16, s)
    m = mask_draw(n, n, draw)
    over(chk, metal_from_mask(m, gold_albedo(n, n) * 1.2, height_scale=1.0, blur=0.4, shadow=0.6))
    return stack(box, chk)


def arrow_glyph(n, direction, color=GOLD_L, scale=0.3):
    c = (n - 1) / 2
    r = n * scale
    pts = {'up': [(c, c - r), (c + r, c + r * 0.6), (c - r, c + r * 0.6)],
           'down': [(c, c + r), (c + r, c - r * 0.6), (c - r, c - r * 0.6)],
           'left': [(c - r, c), (c + r * 0.6, c - r), (c + r * 0.6, c + r)],
           'right': [(c + r, c), (c - r * 0.6, c - r), (c - r * 0.6, c + r)]}[direction]
    m = mask_draw(n, n, lambda d, s: d.polygon([((x + 0.5) * s, (y + 0.5) * s) for x, y in pts], fill=255))
    return metal_from_mask(m, np.ones((n, n, 3), np.float32) * color, height_scale=1.0, blur=0.4, shadow=0.6)


def arrow_button(n, state, direction, w=None):
    w = n if w is None else w
    o = button_face(w, n, 3, state, seed=17)
    g = arrow_glyph(n, direction, GOLD_H if state == 'hover' else GOLD_L)
    over(o, g, (w - n) // 2 + (1 if state == 'pressed' else 0), 1 if state == 'pressed' else 0)
    return o


def combobox_img(W, H, rb):
    o = text_field(W, H, 4, seed=44)
    x, y, dl, dr, dt, db = edge_maps(H, W)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
    blend_rgb(o, GOLD * 0.8, (d < 1).astype(np.float32))
    btn = button_face(rb - 2, H - 4, 3, 'normal', seed=18)
    over(o, btn, W - rb, 2)
    g = arrow_glyph(H - 4, 'down', scale=0.22)
    over(o, g, W - rb + (rb - 2 - g.shape[1]) // 2, 2)
    return o


def topbar_bg(W, H):
    o = frame(W, H, 4, 4, 4, 4, outer=2, seed=19, corner_caps=False, rivets=False, center='iron', trim=False)
    blend_rgb(o, GOLD * 0.9, (np.arange(H)[:, None] * np.ones((1, W)) == H - 3).astype(np.float32))
    return o


# ---------------------------------------------------------------- stock images, redrawn in place
BASE = None   # base client directory (--base), needed by the 'stock' group


def stock(rel):
    if not BASE:
        sys.exit("the 'stock' group needs --base <base-client-dir> (the assembled client source)")
    return Image.open(os.path.join(BASE, 'data', 'images', rel + '.png')).convert('RGBA')


RELIGHT = [
    'ui/scrollbar', 'ui/checkbox', 'ui/checkboxcircle', 'ui/checkbox-checked', 'ui/checkbox-unchecked',
    'ui/miniwindow_buttons', 'ui/console_direction_button', 'ui/regular_direction_button',
    'ui/arrow_horizontal', 'ui/arrow_vertical', 'ui/combobox_square', 'ui/combobox_rounded', 'ui/spinbox',
    'ui/console', 'ui/chat_channel_selected', 'ui/chat_channel_deselected', 'ui/miniborder',
    'ui/separator_horizontal', 'ui/separator_vertical', 'ui/browse-arrow-left', 'ui/browse-arrow-right',
    'ui/colorbox-border-13', 'ui/rotate_button',
    'common_buttons/add-button', 'common_buttons/apply-button', 'common_buttons/back-button',
    'common_buttons/button-clear-search', 'common_buttons/cancel-button', 'common_buttons/clear-button',
    'common_buttons/close-button', 'common_buttons/copy-button', 'common_buttons/delete-button',
    'common_buttons/gift-button', 'common_buttons/history-button', 'common_buttons/new-button',
    'common_buttons/ok-button', 'common_buttons/open-button', 'common_buttons/refresh-button',
    'common_buttons/rename-button', 'common_buttons/reset-button', 'common_buttons/save-button',
    'common_buttons/send-button', 'common_buttons/small-apply-button',
    'game/actionbar/arrow-down', 'game/actionbar/arrow-left', 'game/actionbar/arrow-right', 'game/actionbar/arrow-up',
    'game/actionbar/double-arrow-down', 'game/actionbar/double-arrow-left', 'game/actionbar/double-arrow-right',
    'game/actionbar/double-arrow-up',
]

SLOTS = ['ammo', 'back', 'body', 'feet', 'finger', 'head', 'left-hand', 'legs', 'neck', 'right-hand']


def slot_with_silhouette(src, blessed, seed):
    """Our slot well with the stock slot's silhouette (the part brighter than its background) in dim bronze."""
    a = from_img(src)
    n = a.shape[0]
    lum = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
    d = dist_rect(n, a.shape[1])
    inner = d >= 4
    bg = np.median(lum[inner]) if inner.any() else 0.2
    m = np.clip((lum - bg - 0.04) * 6.0, 0, 1) * inner
    o = slot(n, seed=seed, rim=GOLD_L if blessed else GOLD)
    sil = np.zeros_like(o)
    sil[..., :3] = (GOLD_L if blessed else hexc('#7a6040'))
    sil[..., 3] = m * (0.5 if blessed else 0.42)
    over(o, sil)
    if blessed:
        glow = np.exp(-np.clip(d - 3, 0, None) / 2.0) * (d >= 3)
        o[..., :3] = np.clip(o[..., :3] + glow[..., None] * GOLD_L * 0.25, 0, 1)
    return o


def bar_texture(W, H, seed, tint=IRON):
    """Plain dark iron backdrop (not sliced) with a gold hairline at the bottom."""
    o = rgba(mat_iron(H, W, seed, tone=0.7, tint=tint))
    o[-2, :, :3] = GOLD * 0.9
    o[-1, :, :3] = 0.02
    o[0, :, :3] = np.clip(o[0, :, :3] * 1.6, 0, 1)
    return o


def gen_stock():
    for rel in RELIGHT:
        try:
            src = stock(rel)
        except FileNotFoundError:
            print('skip (not in base):', rel)
            continue
        img = relight(src, seed=sum(map(ord, rel)) % 1000)
        if rel == 'ui/console':
            # chat text area (clip 184 0 166 150, border 3) and input area (clip 0 50 184 124, border 4)
            img[0:150, 184:350] = panel(166, 150, 3, 'inset', 'abyss', seed=91, tone=0.85)
            img[50:174, 0:184] = panel(184, 124, 4, 'inset', 'abyss', seed=92, tone=0.85, rim=GOLD * 0.6)
        save(img, rel)
    # buttons: Button style uses its own sheet now; these keep the stock clips for direct users
    save(stack(button_face(43, 20, 1, 'normal', seed=61, round_corner=False),
               button_face(43, 20, 1, 'pressed', seed=61, round_corner=False)), 'ui/buttons')
    for rel in ('ui/button', 'ui/button_rounded'):
        save(stack(*[button_face(22, 23, 3, st, seed=62) for st in ('normal', 'hover', 'pressed')]), rel)
    save(stack(*[button_face(22, 23, 3, st, seed=63) for st in ('normal', 'hover', 'on')]), 'ui/tabbutton_rounded')
    save(stack(*[button_face(96, 19, 3, st, seed=64) for st in ('normal', 'hover', 'on')]), 'ui/tabbutton_square')
    # popup menu box (top-left 32x2 doubles as the menu separator: dark line + gold line)
    save(panel(121, 116, 3, 'raised', 'abyss', seed=65, rim=GOLD, bev=2), 'ui/menubox')
    save(text_field(32, 32, 1, seed=66), 'ui/textedit')
    # inner panels and frames
    for rel in ('ui/2pixel-up-frame-borderimage', 'ui/2pixel_up_frame_borderimage'):
        save(panel(100, 100, 2, 'raised', 'abyss', seed=67), rel)
    for rel in ('ui/2pixel-up-frame-borderimage-dark', 'ui/2pixel_up_frame_borderimage_dark'):
        save(panel(100, 100, 2, 'raised', 'abyss', seed=68, tone=0.75), rel)
    for rel in ('ui/2pixel-up-frame-borderimage-upside-down', 'ui/2pixel-up-frame-borderimage-dark-upside-down',
                'ui/2pixel_up_frame_borderimage_dark_reversed'):
        save(panel(100, 100, 2, 'inset', 'abyss', seed=69, tone=0.8), rel)
    for rel in ('ui/1pixel-down-frame', 'ui/1pixel_down_frame'):
        save(panel(96, 96, 1, 'inset', 'abyss', seed=70, tone=0.85), rel)
    save(panel(96, 96, 1, 'raised', 'abyss', seed=71), 'ui/1pixel-up-frame')
    for rel in ('ui/3pixel-frame-borderimage', 'ui/3pixel_frame_borderimage'):
        save(panel(102, 102, 3, 'inset', 'abyss', seed=72, rim=GOLD * 0.8), rel)
    save(panel(68, 68, 1, 'inset', 'abyss', seed=73, tone=0.9), 'ui/panel_flat')
    save(panel(32, 32, 1, 'inset', 'leather', seed=74), 'ui/panel_lightflat')
    save(panel(98, 98, 1, 'inset', 'abyss', seed=75), 'ui/panel-1-pixel')
    save(panel(96, 97, 2, 'inset', 'abyss', seed=76, rim=GOLD * 0.7), 'ui/panel_map_bordered')
    save(map_frame(96), 'ui/panel_map')
    for rel in ('ui/background-dark', 'ui/background_dark'):
        save(rgba(mat_stone(96, 96, 77, tint=hexc('#0f0c10'))), rel)
    save(bar_texture(941, 60, 78), 'ui/panel_bottom2')
    save(bar_texture(43, 31, 79), 'ui/panel_top')
    # slots
    for rel in ('ui/item', 'game/slots/item-slot', 'game/actionbar/actionbarslot', 'game/actionbar/slot-actionbar'):
        save(slot(34, seed=80), rel)
    save(slot(34, seed=81, rim=GOLD_L), 'ui/item-blessed')
    save(slot(44, seed=82), 'game/actionbar/slot-actionbar_')
    save(slot(66, seed=83), 'ui/item66')
    for nm in SLOTS:
        save(slot_with_silhouette(stock('game/slots/' + nm), False, 90), 'game/slots/' + nm)
        save(slot_with_silhouette(stock('game/slots/' + nm), True, 90), 'game/slots/' + nm + '-blessed')


def map_frame(n):
    """Frame around the game map (image-border 4): black, gold, iron, black."""
    o = rgba(mat_stone(n, n, 84, tint=hexc('#0a080a')))
    d = dist_rect(n, n)
    blend_rgb(o, BLACK, (d < 1).astype(np.float32))
    blend_rgb(o, GOLD, ((d >= 1) & (d < 2)).astype(np.float32))
    blend_rgb(o, IRON_L, ((d >= 2) & (d < 3)).astype(np.float32) * 0.8)
    blend_rgb(o, BLACK, ((d >= 3) & (d < 4)).astype(np.float32))
    return o


# ---------------------------------------------------------------- HUD (game_chaoshud)
HUD_W, HUD_H = 300, 96
HUD_PC = (47, 48)        # portrait centre
HUD_HOLE = 30            # portrait opening radius
HUD_RING = 40            # outer radius of the portrait ring
HUD_BAR_X, HUD_BAR_W = 96, 166
HUD_BARS = {'name': (20, 13), 'hp': (35, 15), 'mp': (54, 13), 'xp': (71, 5)}   # y, height


def hud_plate():
    W, H = HUD_W, HUD_H
    out = np.zeros((H, W, 4), np.float32)
    cx, cy = HUD_PC
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # plaque body: rounded bar from the portrait to the right end, with a pointed tip
    x0, x1, y0, y1 = cx, W - 6, 14, 84

    def body(d, s):
        d.rounded_rectangle([x0 * s, y0 * s, (x1 - 10) * s, y1 * s], radius=10 * s, fill=255)
        d.polygon([((x1 - 14) * s, y0 * s), (x1 * s, (y0 + y1) / 2 * s), ((x1 - 14) * s, y1 * s)], fill=255)
    m = mask_draw(W, H, body)
    iron = mat_iron(H, W, 101, tone=0.85)
    # height: bevelled rim
    hm = gauss(m, 2.5) * 3
    rgb = shade(hm, iron, amb=0.4, diff=0.9, spec=0.3)
    plate = rgba(rgb, m)
    # gold trim along the plaque edge
    edge = np.clip(m - gauss(m, 1.0) * 1.0, 0, 1)
    inner = np.clip(gauss(m, 3.0) * 1.8 - 1.0, 0, 1)
    trim = np.clip(m * 2 - 1, 0, 1) * np.clip((1 - inner) * 3 - 1.8, 0, 1)
    blend_rgb(plate, GOLD * 1.05, trim * 0.85)
    over(out, plate)
    # sockets for the name, the bars and the experience line
    for key, (y, h) in HUD_BARS.items():
        if key == 'name':
            continue
        sk = panel(HUD_BAR_W + 4, h + 4, 2, 'inset', 'abyss', seed=102 + y, rim=GOLD * 0.75, tone=0.6)
        over(out, sk, HUD_BAR_X - 2, y - 2)
    # filigree at the tip
    def fil(d, s):
        poly_stroke(d, curl_points(W - 26, 25, 6, 1.4, math.pi / 2, 0.9, flip=-1), 1.6, s)
        poly_stroke(d, curl_points(W - 26, 73, 6, 1.4, -math.pi / 2, 0.9, flip=1), 1.6, s)
    over(out, metal_from_mask(mask_draw(W, H, fil), gold_albedo(H, W), height_scale=1.8, blur=0.6))
    g = gem(3.4, BLOOD, BLOOD_L)
    over(out, g, W - 14 - g.shape[1] // 2, (y0 + y1) // 2 - g.shape[0] // 2)
    # portrait ring: iron disc with a gold bezel and four studs
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    ring_m = np.clip(HUD_RING + 0.5 - d, 0, 1)
    rh = np.where(d < HUD_RING, np.sin(np.clip((d - HUD_HOLE) / (HUD_RING - HUD_HOLE), 0, 1) * math.pi), 0) * 4
    alb = mat_iron(H, W, 103, tone=1.0)
    gold_band = (d >= HUD_HOLE) & (d < HUD_HOLE + 3)
    gold_out = (d >= HUD_RING - 2.5) & (d < HUD_RING)
    alb[gold_band | gold_out] = gold_albedo(H, W, 104)[gold_band | gold_out]
    rgb = shade(rh, alb, amb=0.4, diff=0.9, spec=0.7, shin=10)
    over(out, rgba(rgb, ring_m))
    # dark well behind the portrait
    well = np.clip(HUD_HOLE + 0.5 - d, 0, 1)
    wc = mat_stone(H, W, 105, tint=hexc('#120b0e')) * (0.6 + 0.6 * np.clip(d / HUD_HOLE, 0, 1))[..., None]
    wc = wc + BLOOD_D[None, None, :] * np.clip(1 - d / HUD_HOLE, 0, 1)[..., None] * 0.8
    over(out, rgba(np.clip(wc, 0, 1), well))
    for ang in (45, 135, 225, 315):
        a = math.radians(ang)
        rv = rivet(2.0, metal=GOLD_L)
        px = cx + math.cos(a) * (HUD_RING - 5) - rv.shape[1] / 2
        py = cy + math.sin(a) * (HUD_RING - 5) - rv.shape[0] / 2
        over(out, rv, int(round(px)), int(round(py)))
    return out, d


def hud_fill(W, H, base, light, seed):
    y = np.arange(H, dtype=np.float32)[:, None] / max(H - 1, 1)
    n = fbm(H, W, base=2, octaves=4, seed=seed, aspect=3)
    v = 0.75 + 0.35 * n
    col = base[None, None, :] * v[..., None]
    col = col * (1.1 - 0.5 * y)[..., None]
    gloss = np.exp(-((y - 0.22) ** 2) / 0.012)
    col = col + light[None, None, :] * gloss[..., None] * 0.45
    out = rgba(np.clip(col, 0, 1))
    out[0, :, :3] = np.clip(out[0, :, :3] * 1.3, 0, 1)
    out[-1, :, :3] *= 0.5
    return out


def gen_hud():
    plate, d = hud_plate()
    save(plate, SKIN + '/hud_plate')
    # the part of the plate that covers the portrait's square corners (the opening is cut out)
    cov = plate[0:96, 0:96].copy()
    cov[..., 3] = cov[..., 3] * np.clip(d[0:96, 0:96] - HUD_HOLE + 0.5, 0, 1)
    save(cov, SKIN + '/hud_portrait_cover')
    save(hud_fill(HUD_BAR_W, HUD_BARS['hp'][1], BLOOD, BLOOD_L, 111), SKIN + '/hud_hp_fill')
    save(hud_fill(HUD_BAR_W, HUD_BARS['mp'][1], ARCANE, ARCANE_L, 112), SKIN + '/hud_mp_fill')
    save(hud_fill(HUD_BAR_W, HUD_BARS['xp'][1], GOLD, GOLD_H, 113), SKIN + '/hud_xp_fill')
    # level badge (a small gold-rimmed plaque under the portrait)
    save(button_face(40, 18, 4, 'on', seed=114, rim=GOLD_L), SKIN + '/hud_level')


GROUPS = {
    'frames': gen_frames,
    'controls': gen_controls,
    'stock': gen_stock,
    'hud': gen_hud,
    'ornaments': gen_ornaments,
}


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('--')]
    global BASE
    if '--base' in argv:
        BASE = argv[argv.index('--base') + 1]
        args = [a for a in args if a != BASE]
    for g in (args or list(GROUPS)):
        GROUPS[g]()
    # stock files drawn here are ours now: take them off the recolour tool's list so it never overwrites them
    lst = os.path.join(IMAGES, 'RESKIN_FILES.txt')
    if os.path.isfile(lst):
        lines = open(lst).read().split('\n')
        mine = set(WRITTEN)
        kept = [l for l in lines if l.strip() not in mine]
        if len(kept) != len(lines):
            open(lst, 'w').write('\n'.join(kept))
    print('%d images written' % len(WRITTEN))


if __name__ == '__main__':
    main(sys.argv)
