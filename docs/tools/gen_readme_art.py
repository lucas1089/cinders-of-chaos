#!/usr/bin/env python3
"""README art for Project Chaos: the banner and the framed feature cards.

usage: python3 docs/tools/gen_readme_art.py [--shots DIR] [name ...]

Writes PNGs to docs/images/ (no name = all). Everything is drawn by code (value noise, glow, cracks,
embers, sigils, emblems), in the palette of the client skin (client/tools/gen_theme_art.py,
gen_skin.py). The card frames reuse the client's own ornaments from
client/overlay/data/images/chaos/skin (corners, crest) when they are present.

Some cards show crops of in-game screenshots. Their sources are listed in SHOTS below, relative to the
screenshot folder (--shots DIR, or the CHAOS_SHOTS environment variable). When a source is missing the
card is left as it is in docs/images/ (it is only drawn from scratch if it does not exist yet, with an
emblem in place of the screenshot), so the purely generated images can always be rebuilt.

Fonts: Caladea (titles, captions), Inter (small labels), with DejaVu as the fallback.
Needs Pillow and numpy. Deterministic (fixed seeds).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "docs", "images")
SKIN = os.path.join(REPO, "client", "overlay", "data", "images", "chaos", "skin")
DEFAULT_SHOTS = os.environ.get("CHAOS_SHOTS", "")

# ---------------------------------------------------------------- palette (client skin)
def hexc(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


BLACK = hexc("#050405")
IRON_0, IRON_1, IRON_2, IRON_3, IRON_4 = (hexc(c) for c in ("#0d0b0e", "#17141a", "#241f27", "#3a3339", "#574d52"))
BLOOD_0, BLOOD_1, BLOOD_2, BLOOD_3, BLOOD_4 = (hexc(c) for c in ("#2a0505", "#5a0a0a", "#8a1010", "#b8160f", "#e03a1e"))
GOLD_0, GOLD_1, GOLD_2, GOLD_3, GOLD_4 = (hexc(c) for c in ("#6b4a14", "#a87420", "#d9a53a", "#f6cf72", "#fff0b8"))
PARCH = hexc("#d9c9a6")
PARCH_DIM = hexc("#a8977a")
EMBER = hexc("#ff8a2a")

RARITIES = [  # names and colours as in the client loot filter (game_lootfilter/lootfilterlogic.lua)
    ("Common", "#c8c8c8"), ("Uncommon", "#5ccf5c"), ("Rare", "#4a90ff"), ("Epic", "#a35cf0"),
    ("Legendary", "#ffd040"), ("Exotic", "#f5b13a"), ("Mythic", "#ff5a5a"), ("Chaos", "#e02424"),
    ("Eternal", "#ff8a70"), ("Divine", "#c8e8ff"), ("Phantasmal", "#9ad8ff"), ("Celestial", "#e4f2ff"),
    ("Cosmic", "#b878ff"), ("Abyssal", "#9a4ce0"), ("Transcendent", "#e070ff"),
]

# ---------------------------------------------------------------- fonts
FONT_FILES = {
    "title": ["/usr/share/fonts/truetype/crosextra/Caladea-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"],
    "serif": ["/usr/share/fonts/truetype/crosextra/Caladea-Regular.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"],
    "italic": ["/usr/share/fonts/truetype/crosextra/Caladea-Italic.ttf",
               "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf"],
    "sans": ["/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
}
_font_cache = {}


def font(kind, size):
    key = (kind, size)
    if key not in _font_cache:
        f = None
        for path in FONT_FILES[kind]:
            if os.path.exists(path):
                f = ImageFont.truetype(path, size)
                break
        _font_cache[key] = f or ImageFont.load_default()
    return _font_cache[key]


# ---------------------------------------------------------------- helpers
def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def fbm(h, w, scale, octaves=5, seed=0, persistence=0.5):
    """Fractal value noise in [0,1], float32 (h, w)."""
    rng = np.random.RandomState(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        gh = max(2, int(h / scale * (2 ** o)) + 2)
        gw = max(2, int(w / scale * (2 ** o)) + 2)
        g = rng.rand(gh, gw).astype(np.float32)
        out += np.asarray(Image.fromarray(g, "F").resize((w, h), Image.BICUBIC)) * amp
        tot += amp
        amp *= persistence
    return np.clip(out / tot, 0, 1)


def ramp(t, stops):
    """Map t (array in [0,1]) through colour stops [(pos, rgb), ...] -> (h, w, 3) float."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(t, [p for p, _ in stops], [col[c] for _, col in stops])
    return out


def rgb_img(arr):
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGB")


def glow_layer(size, draw_fn, color, radius, strength=1.0):
    """RGBA glow: draw_fn(draw) paints white on an L mask, blurred and tinted."""
    m = Image.new("L", size, 0)
    draw_fn(ImageDraw.Draw(m))
    m = m.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        m = m.point(lambda v: min(255, int(v * strength)))
    layer = Image.new("RGBA", size, color + (0,))
    layer.putalpha(m)
    return layer


def add_glow(base, mask, color, radius, strength=1.0):
    m = mask.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        m = m.point(lambda v: min(255, int(v * strength)))
    layer = Image.new("RGBA", base.size, color + (0,))
    layer.putalpha(m)
    base.alpha_composite(layer)


def gradient_fill(mask, stops, box=None):
    """RGBA image of mask filled with a vertical gradient over the mask's bounding box."""
    w, h = mask.size
    y0, y1 = (box if box else (lambda b: (b[1], b[3]) if b else (0, h))(mask.getbbox()))
    ys = (np.arange(h, dtype=np.float32) - y0) / max(1, (y1 - y0))
    col = ramp(np.repeat(ys[:, None], w, 1), stops)
    img = rgb_img(col).convert("RGBA")
    img.putalpha(mask)
    return img


GOLD_STOPS = [(0.0, GOLD_4), (0.35, GOLD_3), (0.62, GOLD_2), (1.0, GOLD_0)]
CHAOS_STOPS = [(0.0, GOLD_4), (0.28, GOLD_3), (0.5, GOLD_2), (0.66, BLOOD_4), (0.82, BLOOD_3), (1.0, BLOOD_1)]


def text_mask(txt, fnt, tracking=0, pad=8):
    """L mask of txt with extra letter spacing; returns (mask, ascent offset)."""
    widths = [fnt.getlength(ch) for ch in txt]
    w = int(sum(widths) + tracking * (len(txt) - 1)) + pad * 2
    asc, desc = fnt.getmetrics()
    h = asc + desc + pad * 2
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    x = pad
    for ch, cw in zip(txt, widths):
        d.text((x, pad), ch, font=fnt, fill=255)
        x += cw + tracking
    return m.crop(m.getbbox() or (0, 0, 1, 1))


def draw_fancy_text(base, txt, fnt, center, stops=GOLD_STOPS, tracking=0, outline=2, glow=None,
                    shadow=True):
    """Gradient-filled text with a dark outline, optional glow, centred on center=(x, y)."""
    m = text_mask(txt, fnt, tracking)
    pad = outline + 12
    big = Image.new("L", (m.width + pad * 2, m.height + pad * 2), 0)
    big.paste(m, (pad, pad))
    x = int(center[0] - big.width / 2)
    y = int(center[1] - big.height / 2)
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    full = Image.new("L", base.size, 0)
    full.paste(big, (x, y))
    if glow:
        add_glow(base, full, glow[0], glow[1], glow[2] if len(glow) > 2 else 1.0)
    if shadow:
        sh = full.filter(ImageFilter.MaxFilter(outline * 2 + 1)) if outline else full
        sh = ImageChops.offset(sh, 2, 3).filter(ImageFilter.GaussianBlur(2))
        s = Image.new("RGBA", base.size, (0, 0, 0, 0))
        s.putalpha(sh.point(lambda v: int(v * 0.8)))
        base.alpha_composite(s)
    if outline:
        ol = full.filter(ImageFilter.MaxFilter(outline * 2 + 1))
        o = Image.new("RGBA", base.size, BLACK + (0,))
        o.putalpha(ol)
        base.alpha_composite(o)
    bb = full.getbbox()
    fill = gradient_fill(full, stops, (bb[1], bb[3]) if bb else None)
    layer.alpha_composite(fill)
    base.alpha_composite(layer)
    return (x + pad, y + pad, x + pad + m.width, y + pad + m.height)


def plain_text(draw, txt, fnt, center, fill, anchor="mm"):
    draw.text(center, txt, font=fnt, fill=fill, anchor=anchor)


def save_png(img, name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    # full colour: a 256-colour palette bands the gradients and greys out the small saturated details
    img.convert("RGB").save(path, optimize=True)
    print("wrote %-28s %dx%d  %5.0f KB" % (name, img.width, img.height, os.path.getsize(path) / 1024))


def load_skin(name):
    p = os.path.join(SKIN, name)
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


# ---------------------------------------------------------------- shared backgrounds
def iron_background(w, h, seed, glow_color=BLOOD_1, glow_strength=0.55):
    n = fbm(h, w, 160, 4, seed)
    fine = fbm(h, w, 40, 2, seed + 1)
    t = n * 0.8 + fine * 0.2
    col = ramp(t, [(0.0, BLACK), (0.45, IRON_0), (0.7, IRON_1), (1.0, IRON_2)])
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w / 2, h * 0.55
    r = np.sqrt(((xx - cx) / (w * 0.55)) ** 2 + ((yy - cy) / (h * 0.65)) ** 2)
    g = np.clip(1 - r, 0, 1) ** 2 * glow_strength
    col = col * (1 - g[..., None]) + np.array(glow_color, np.float32) * g[..., None] + col * g[..., None] * 0.6
    vig = np.clip(1.15 - r * 0.55, 0.35, 1)
    col *= vig[..., None]
    return rgb_img(col).convert("RGBA")


# ---------------------------------------------------------------- card frame
CARD_W, CARD_H = 900, 500
CONTENT = (34, 96, CARD_W - 34, 436)  # x0, y0, x1, y1 of the content area


def draw_frame(img):
    w, h = img.size
    d = ImageDraw.Draw(img)
    band = 11
    # iron band with a bevel
    for i in range(band):
        t = i / (band - 1)
        c = lerp(IRON_3, IRON_1, abs(t - 0.35) * 1.4)
        d.rectangle([i, i, w - 1 - i, h - 1 - i], outline=c + (255,))
    d.rectangle([0, 0, w - 1, h - 1], outline=BLACK + (255,), width=2)
    # gold trim inside
    d.rectangle([band, band, w - 1 - band, h - 1 - band], outline=GOLD_0 + (255,), width=1)
    d.rectangle([band + 1, band + 1, w - 2 - band, h - 2 - band], outline=GOLD_2 + (255,), width=1)
    d.rectangle([band + 2, band + 2, w - 3 - band, h - 3 - band], outline=BLACK + (255,), width=1)
    # rivets along the band
    for x in range(60, w - 40, 120):
        for y in (band // 2, h - 1 - band // 2):
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=IRON_4 + (255,), outline=BLACK + (255,))
    corners = {k: load_skin("orn_corner_%s.png" % k) for k in ("tl", "tr", "bl", "br")}
    if all(corners.values()):
        s = 58
        for k, im in corners.items():
            im = im.resize((s, s), Image.LANCZOS)
            x = 3 if k[1] == "l" else w - s - 3
            y = 3 if k[0] == "t" else h - s - 3
            img.alpha_composite(im, (x, y))
    else:  # fallback: gold studs
        for x, y in ((14, 14), (w - 15, 14), (14, h - 15), (w - 15, h - 15)):
            d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=GOLD_2 + (255,), outline=BLACK + (255,))
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=BLOOD_3 + (255,))
    crest = load_skin("orn_crest.png")
    if crest:
        crest = crest.resize((118, 42), Image.LANCZOS)
        img.alpha_composite(crest, ((w - crest.width) // 2, 0))


def divider(img, y, half, x=None):
    """Thin gold rule with a crimson diamond in the middle."""
    w = img.width
    x = w // 2 if x is None else x
    d = ImageDraw.Draw(img)
    for i in range(half):
        a = int(255 * (1 - i / half) ** 0.7)
        c = lerp(GOLD_3, GOLD_0, i / half)
        d.point((x - i, y), fill=c + (a,))
        d.point((x + i, y), fill=c + (a,))
    d.polygon([(x, y - 6), (x + 6, y), (x, y + 6), (x - 6, y)], fill=BLOOD_3 + (255,), outline=GOLD_2 + (255,))


def framed_shot(im, border=True):
    """Screenshot panel with a dark line, a gold line and a drop shadow (RGBA, padded)."""
    pad = 10
    out = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("L", out.size, 0)
    ImageDraw.Draw(sh).rectangle([pad - 2, pad + 1, pad + im.width + 3, pad + im.height + 5], fill=210)
    sh = sh.filter(ImageFilter.GaussianBlur(5))
    s = Image.new("RGBA", out.size, (0, 0, 0, 0))
    s.putalpha(sh)
    out.alpha_composite(s)
    out.alpha_composite(im.convert("RGBA"), (pad, pad))
    if border:
        d = ImageDraw.Draw(out)
        d.rectangle([pad - 1, pad - 1, pad + im.width, pad + im.height], outline=BLACK + (255,))
        d.rectangle([pad - 2, pad - 2, pad + im.width + 1, pad + im.height + 1], outline=GOLD_1 + (255,))
    return out


def layout_panels(img, panels, gap=26):
    """Place panels [(RGBA image, max_scale, framed)] side by side, same height where possible."""
    x0, y0, x1, y1 = CONTENT
    aw, ah = x1 - x0, y1 - y0
    # height h such that sum of widths fits; framed panels get 20 px of padding
    def widths(h):
        tot = 0
        sizes = []
        for im, ms, fr in panels:
            s = min(h / im.height, ms)
            sw, shh = im.width * s, im.height * s
            sizes.append((s, sw, shh))
            tot += sw + (20 if fr else 0)
        return tot + gap * (len(panels) - 1), sizes

    h = ah - 20
    while h > 40:
        tot, sizes = widths(h)
        if tot <= aw:
            break
        h -= 2
    tot, sizes = widths(h)
    x = x0 + (aw - tot) / 2
    cy = y0 + ah / 2
    for (im, ms, fr), (s, sw, shh) in zip(panels, sizes):
        r = im.resize((max(1, int(round(sw))), max(1, int(round(shh)))), Image.LANCZOS) if abs(s - 1) > 1e-3 else im
        if fr:
            p = framed_shot(r)
            img.alpha_composite(p, (int(x), int(cy - p.height / 2)))
            x += p.width + gap
        else:
            img.alpha_composite(r.convert("RGBA"), (int(x), int(cy - r.height / 2)))
            x += r.width + gap


def make_card(name, title, caption, panels, seed, glow=BLOOD_1):
    img = iron_background(CARD_W, CARD_H, seed, glow)
    draw_frame(img)
    draw_fancy_text(img, title.upper(), font("title", 32), (CARD_W / 2, 58), GOLD_STOPS, tracking=5,
                    outline=2, glow=(BLOOD_3, 10, 0.9))
    divider(img, 82, 210)
    layout_panels(img, panels)
    d = ImageDraw.Draw(img)
    divider(img, 450, 300)
    plain_text(d, caption, font("italic", 19), (CARD_W / 2 + 1, 472 + 1), BLACK)
    plain_text(d, caption, font("italic", 19), (CARD_W / 2, 472), PARCH)
    save_png(img, name)


# ---------------------------------------------------------------- shape helpers (supersampled)
SS = 4


def rot(pts, ang, cx, cy):
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def sword(d, cx, cy, ang, L, W):
    """Sword centred on (cx, cy), pointing up before rotation."""
    top = cy - L * 0.55
    blade = [(cx, top), (cx + W * 0.5, top + W * 1.2), (cx + W * 0.5, cy + L * 0.18),
             (cx - W * 0.5, cy + L * 0.18), (cx - W * 0.5, top + W * 1.2)]
    guard = [(cx - W * 2.2, cy + L * 0.18), (cx + W * 2.2, cy + L * 0.18),
             (cx + W * 2.6, cy + L * 0.18 + W * 0.9), (cx - W * 2.6, cy + L * 0.18 + W * 0.9)]
    grip = [(cx - W * 0.35, cy + L * 0.18 + W * 0.9), (cx + W * 0.35, cy + L * 0.18 + W * 0.9),
            (cx + W * 0.35, cy + L * 0.42), (cx - W * 0.35, cy + L * 0.42)]
    for poly in (blade, guard, grip):
        d.polygon(rot(poly, ang, cx, cy), fill=255)
    px, py = rot([(cx, cy + L * 0.46)], ang, cx, cy)[0]
    d.ellipse([px - W * 0.7, py - W * 0.7, px + W * 0.7, py + W * 0.7], fill=255)


def arc_poly(cx, cy, r_out, r_in, a0, a1, n=48):
    out = [(cx + r_out * math.cos(a), cy + r_out * math.sin(a)) for a in np.linspace(a0, a1, n)]
    inn = [(cx + r_in * math.cos(a), cy + r_in * math.sin(a)) for a in np.linspace(a1, a0, n)]
    return out + inn


def sigil_mask(kind, size):
    S = size * SS
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    c = S / 2
    if kind == "warrior":
        sword(d, c, c, math.radians(40), S * 0.8, S * 0.075)
        sword(d, c, c, math.radians(-40), S * 0.8, S * 0.075)
    elif kind == "ranger":
        d.polygon(arc_poly(c + S * 0.12, c, S * 0.36, S * 0.31, math.radians(110), math.radians(250)), fill=255)
        top = (c + S * 0.12 + S * 0.335 * math.cos(math.radians(110)), c + S * 0.335 * math.sin(math.radians(110)))
        bot = (c + S * 0.12 + S * 0.335 * math.cos(math.radians(250)), c + S * 0.335 * math.sin(math.radians(250)))
        d.line([top, bot], fill=255, width=int(S * 0.012))
        # arrow
        ax0, ax1 = c - S * 0.16, c + S * 0.40
        d.rectangle([ax0, c - S * 0.014, ax1 - S * 0.06, c + S * 0.014], fill=255)
        d.polygon([(ax1, c), (ax1 - S * 0.1, c - S * 0.055), (ax1 - S * 0.1, c + S * 0.055)], fill=255)
        for k in (1, -1):
            d.polygon([(ax0, c), (ax0 + S * 0.08, c), (ax0 + S * 0.03, c + k * S * 0.06), (ax0 - S * 0.04, c + k * S * 0.06)],
                      fill=255)
    elif kind == "mystic":  # arcane circle, triangle and an open eye
        r = S * 0.4
        d.ellipse([c - r, c - r, c + r, c + r], outline=255, width=int(S * 0.025))
        tri = [(c + r * 0.93 * math.cos(math.radians(-90 + i * 120)), c + r * 0.93 * math.sin(math.radians(-90 + i * 120)))
               for i in range(3)]
        d.line(tri + [tri[0]], fill=255, width=int(S * 0.03), joint="curve")
        for i in range(3):  # small studs on the circle between the corners
            a = math.radians(90 + i * 120)
            x, y = c + r * math.cos(a), c + r * math.sin(a)
            d.ellipse([x - S * 0.03, y - S * 0.03, x + S * 0.03, y + S * 0.03], fill=255)
        ew, eh, ey = S * 0.17, S * 0.09, c + S * 0.07
        top = [(c + ew * math.cos(a), ey - eh * math.sin(a)) for a in np.linspace(0, math.pi, 40)]
        bot = [(c + ew * math.cos(a), ey - eh * math.sin(a)) for a in np.linspace(math.pi, 2 * math.pi, 40)]
        d.polygon(top + bot, fill=255)
        d.ellipse([c - S * 0.06, ey - S * 0.06, c + S * 0.06, ey + S * 0.06], fill=0)
        d.ellipse([c - S * 0.028, ey - S * 0.028, c + S * 0.028, ey + S * 0.028], fill=255)
    elif kind == "thief":
        # crescent
        cm = Image.new("L", (S, S), 0)
        cd = ImageDraw.Draw(cm)
        cd.ellipse([c - S * 0.36, c - S * 0.36, c + S * 0.36, c + S * 0.36], fill=255)
        cd.ellipse([c - S * 0.36 + S * 0.13, c - S * 0.36 - S * 0.05, c + S * 0.36 + S * 0.13, c + S * 0.36 - S * 0.05], fill=0)
        m.paste(255, (0, 0), cm)
        # dagger across
        dd = ImageDraw.Draw(m)
        ang = math.radians(28)
        sword(dd, c + S * 0.06, c + S * 0.02, ang, S * 0.62, S * 0.05)
        # throwing star
        sx, sy, sr = c + S * 0.22, c - S * 0.22, S * 0.075
        pts = []
        for i in range(8):
            rr = sr if i % 2 == 0 else sr * 0.35
            a = math.radians(i * 45 + 22)
            pts.append((sx + rr * math.cos(a), sy + rr * math.sin(a)))
        dd.polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def boss_mask(kind, size):
    S = size * SS
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    c = S / 2
    if kind == "kaelgor":  # horned great helm
        d.rounded_rectangle([c - S * 0.17, c - S * 0.2, c + S * 0.17, c + S * 0.26], radius=int(S * 0.12), fill=255)
        d.polygon([(c - S * 0.17, c + S * 0.1), (c + S * 0.17, c + S * 0.1), (c + S * 0.12, c + S * 0.33),
                   (c - S * 0.12, c + S * 0.33)], fill=255)
        for k in (1, -1):
            horn = [(c + k * S * 0.12, c - S * 0.08), (c + k * S * 0.24, c - S * 0.1), (c + k * S * 0.34, c - S * 0.22),
                    (c + k * S * 0.38, c - S * 0.38), (c + k * S * 0.31, c - S * 0.24), (c + k * S * 0.22, c - S * 0.17),
                    (c + k * S * 0.12, c - S * 0.16)]
            d.polygon(horn, fill=255)
        d.rectangle([c - S * 0.12, c - S * 0.01, c + S * 0.12, c + S * 0.025], fill=0)  # eye slit
        d.rectangle([c - S * 0.018, c - S * 0.01, c + S * 0.018, c + S * 0.2], fill=0)
    elif kind == "skaldra":  # crown of ice over a frost star
        for i in range(6):
            a = math.radians(i * 60 + 90)
            p = [(c, c + S * 0.1)]
            p = [(c + S * 0.02 * math.cos(a + 1.57), c + S * 0.1 + S * 0.02 * math.sin(a + 1.57)),
                 (c + S * 0.24 * math.cos(a), c + S * 0.1 + S * 0.24 * math.sin(a)),
                 (c - S * 0.02 * math.cos(a + 1.57), c + S * 0.1 - S * 0.02 * math.sin(a + 1.57))]
            d.polygon(p, fill=255)
        base_y = c - S * 0.12
        d.rectangle([c - S * 0.26, base_y, c + S * 0.26, base_y + S * 0.06], fill=255)
        for i, hgt in enumerate((0.14, 0.22, 0.32, 0.22, 0.14)):
            x = c - S * 0.21 + i * S * 0.105
            d.polygon([(x - S * 0.045, base_y + 1), (x, base_y - S * hgt), (x + S * 0.045, base_y + 1)], fill=255)
    elif kind == "rotmother":  # bloated hunched mass with spores
        d.ellipse([c - S * 0.3, c - S * 0.12, c + S * 0.3, c + S * 0.33], fill=255)
        d.ellipse([c - S * 0.14, c - S * 0.34, c + S * 0.1, c - S * 0.06], fill=255)
        d.ellipse([c - S * 0.05, c - S * 0.24, c + S * 0.0, c - S * 0.19], fill=0)
        d.ellipse([c - S * 0.12, c - S * 0.25, c - S * 0.07, c - S * 0.2], fill=0)
        for (x, y, r) in ((0.25, -0.28, 0.035), (0.33, -0.12, 0.025), (-0.32, -0.25, 0.03), (-0.38, -0.05, 0.02),
                          (0.36, 0.05, 0.03), (0.2, -0.38, 0.02)):
            d.ellipse([c + S * (x - r), c + S * (y - r), c + S * (x + r), c + S * (y + r)], fill=255)
        for x in (-0.18, -0.05, 0.1, 0.22):
            d.rounded_rectangle([c + S * (x - 0.018), c + S * 0.25, c + S * (x + 0.018), c + S * (0.36 + abs(x) * 0.2)],
                                radius=int(S * 0.018), fill=255)
    elif kind == "nyxareth":  # hooded archon with one eye and a broken halo
        d.polygon(arc_poly(c, c - S * 0.12, S * 0.36, S * 0.32, math.radians(200), math.radians(320)), fill=255)
        d.polygon(arc_poly(c, c - S * 0.12, S * 0.36, S * 0.32, math.radians(335), math.radians(520)), fill=255)
        hood = [(c, c - S * 0.36), (c + S * 0.16, c - S * 0.1), (c + S * 0.2, c + S * 0.12), (c + S * 0.36, c + S * 0.38),
                (c - S * 0.36, c + S * 0.38), (c - S * 0.2, c + S * 0.12), (c - S * 0.16, c - S * 0.1)]
        d.polygon(hood, fill=255)
        d.ellipse([c - S * 0.1, c - S * 0.16, c + S * 0.1, c + S * 0.08], fill=0)
        d.ellipse([c - S * 0.03, c - S * 0.06, c + S * 0.03, c - S * 0.0], fill=255)
    elif kind == "vharok":  # hulking colossus
        d.polygon([(c - S * 0.34, c - S * 0.12), (c + S * 0.34, c - S * 0.12), (c + S * 0.2, c + S * 0.2),
                   (c - S * 0.2, c + S * 0.2)], fill=255)
        d.rounded_rectangle([c - S * 0.4, c - S * 0.16, c - S * 0.26, c + S * 0.3], radius=int(S * 0.06), fill=255)
        d.rounded_rectangle([c + S * 0.26, c - S * 0.16, c + S * 0.4, c + S * 0.3], radius=int(S * 0.06), fill=255)
        d.ellipse([c - S * 0.43, c + S * 0.22, c - S * 0.23, c + S * 0.38], fill=255)
        d.ellipse([c + S * 0.23, c + S * 0.22, c + S * 0.43, c + S * 0.38], fill=255)
        d.ellipse([c - S * 0.08, c - S * 0.3, c + S * 0.08, c - S * 0.1], fill=255)
        d.polygon([(c - S * 0.14, c + S * 0.18), (c + S * 0.14, c + S * 0.18), (c + S * 0.12, c + S * 0.4),
                   (c - S * 0.12, c + S * 0.4)], fill=255)
        d.ellipse([c - S * 0.045, c - S * 0.23, c - S * 0.015, c - S * 0.2], fill=0)
        d.ellipse([c + S * 0.015, c - S * 0.23, c + S * 0.045, c - S * 0.2], fill=0)
    return m.resize((size, size), Image.LANCZOS)


def medallion(size, color, seed=0):
    """Round gold-rimmed medallion with an inner coloured glow (RGBA)."""
    S = size * 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    c = S / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (S / 2)
    n = fbm(S, S, 40, 4, seed)
    inner = ramp(np.clip(1 - r / 0.82, 0, 1) * (0.7 + 0.3 * n),
                 [(0, IRON_0), (0.4, lerp(IRON_1, color, 0.25)), (0.8, lerp(IRON_2, color, 0.5)), (1, lerp(color, GOLD_4, 0.15))])
    ring_t = np.clip((r - 0.82) / 0.13, 0, 1)
    ang = np.arctan2(yy - c, xx - c)
    shade = 0.5 + 0.5 * np.cos(ang + 2.2)
    ring = ramp(shade * 0.85 + n * 0.15, [(0, GOLD_0), (0.5, GOLD_2), (0.8, GOLD_3), (1, GOLD_4)])
    col = np.where((r < 0.82)[..., None], inner, ring)
    edge = (np.abs(r - 0.82) < 0.012) | (np.abs(r - 0.95) < 0.012)
    col[edge] = BLACK
    alpha = np.clip((0.97 - r) * S / 2, 0, 1) * 255
    arr = np.dstack([np.clip(col, 0, 255), alpha]).astype(np.uint8)
    img = Image.fromarray(arr, "RGBA")
    d = ImageDraw.Draw(img)
    for k in range(4):  # four gems on the rim
        a = math.radians(k * 90 - 90)
        gx, gy = c + S * 0.445 * math.cos(a), c + S * 0.445 * math.sin(a)
        rr = S * 0.035
        d.ellipse([gx - rr, gy - rr, gx + rr, gy + rr], fill=lerp(color, (255, 255, 255), 0.25) + (255,), outline=BLACK + (255,), width=2)
        d.ellipse([gx - rr * 0.4, gy - rr * 0.5, gx, gy - rr * 0.1], fill=(255, 255, 255, 170))
    return img.resize((size, size), Image.LANCZOS)


def emblem(size, mask_fn, kind, color, mode="gold", seed=0):
    """Medallion + sigil. mode 'gold': gilded sigil; 'shadow': black silhouette with a coloured rim light."""
    pad = 24
    out = Image.new("RGBA", (size + pad * 2, size + pad * 2), (0, 0, 0, 0))
    ring = Image.new("L", out.size, 0)
    ImageDraw.Draw(ring).ellipse([pad + 6, pad + 6, pad + size - 6, pad + size - 6], fill=255)
    add_glow(out, ring, color, 14, 0.8)
    out.alpha_composite(medallion(size, color, seed), (pad, pad))
    inner = int(size * 0.68)
    m = mask_fn(kind, inner)
    full = Image.new("L", out.size, 0)
    full.paste(m, ((out.width - inner) // 2, (out.height - inner) // 2))
    if mode == "gold":
        sh = ImageChops.offset(full.filter(ImageFilter.MaxFilter(3)), 2, 3).filter(ImageFilter.GaussianBlur(2))
        s = Image.new("RGBA", out.size, BLACK + (0,))
        s.putalpha(sh)
        out.alpha_composite(s)
        ol = full.filter(ImageFilter.MaxFilter(3))
        o = Image.new("RGBA", out.size, BLACK + (0,))
        o.putalpha(ol)
        out.alpha_composite(o)
        bb = full.getbbox()
        out.alpha_composite(gradient_fill(full, GOLD_STOPS, (bb[1], bb[3])))
        hl = ImageChops.subtract(full, ImageChops.offset(full, 0, 2))
        h = Image.new("RGBA", out.size, GOLD_4 + (0,))
        h.putalpha(hl.point(lambda v: v // 2))
        out.alpha_composite(h)
    else:
        add_glow(out, full.filter(ImageFilter.MaxFilter(5)), color, 6, 1.6)
        rim = ImageChops.subtract(full.filter(ImageFilter.MaxFilter(5)), full)
        r = Image.new("RGBA", out.size, lerp(color, (255, 255, 255), 0.3) + (0,))
        r.putalpha(rim)
        out.alpha_composite(r)
        s = Image.new("RGBA", out.size, (8, 5, 8, 0))
        s.putalpha(full)
        out.alpha_composite(s)
        if kind in ("nyxareth", "kaelgor", "vharok", "rotmother"):  # glowing eyes
            eye = ImageChops.subtract(full.filter(ImageFilter.MaxFilter(9)), full)
            bb = full.getbbox()
            cx, cy = out.width // 2, out.height // 2
            em = Image.new("L", out.size, 0)
            ed = ImageDraw.Draw(em)
            if kind == "nyxareth":
                ed.ellipse([cx - 4, cy - inner * 0.06 - 4, cx + 4, cy - inner * 0.06 + 4], fill=255)
            elif kind == "kaelgor":
                ed.rectangle([cx - inner * 0.1, cy, cx + inner * 0.1, cy + 2], fill=255)
            elif kind == "vharok":
                ed.ellipse([cx - inner * 0.04, cy - inner * 0.22, cx - inner * 0.02, cy - inner * 0.2], fill=255)
                ed.ellipse([cx + inner * 0.02, cy - inner * 0.22, cx + inner * 0.04, cy - inner * 0.2], fill=255)
            else:
                ed.ellipse([cx - inner * 0.1, cy - inner * 0.25, cx - inner * 0.06, cy - inner * 0.2], fill=255)
                ed.ellipse([cx - inner * 0.04, cy - inner * 0.24, cx + inner * 0.0, cy - inner * 0.19], fill=255)
            add_glow(out, em, color, 4, 3.0)
            e = Image.new("RGBA", out.size, lerp(color, (255, 255, 255), 0.5) + (0,))
            e.putalpha(em)
            out.alpha_composite(e)
    return out


# ---------------------------------------------------------------- generated panels
CLASSES = [
    ("warrior", "Warrior", "melee, heavy armour", "Juggernaut", "Berserker", hexc("#c0281a")),
    ("ranger", "Ranger", "bows and crossbows", "Deadeye", "Beastmaster", hexc("#3f9a3a")),
    ("mystic", "Mystic", "spells, wands, rods", "Elementalist", "Illusionist", hexc("#2f62d0")),
    ("thief", "Thief", "speed, stealth", "Ninja", "Samurai", hexc("#7d3ad0")),
]

BOSSES = [
    ("kaelgor", "Kaelgor", "the Infernal Warlord", hexc("#ff5a14")),
    ("skaldra", "Skaldra", "the Rime Queen", hexc("#7fc8ff")),
    ("rotmother", "The Rotmother", "plague abomination", hexc("#7ccf2a")),
    ("nyxareth", "Nyxareth", "the Void Archon", hexc("#a050ff")),
    ("vharok", "Vharok", "the Blood Colossus", hexc("#e0141e")),
]


def panel_classes():
    W, H = 832, 330
    p = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cell = W // 4
    d = ImageDraw.Draw(p)
    for i, (kind, name, plays, a1, a2, col) in enumerate(CLASSES):
        cx = cell * i + cell // 2
        e = emblem(150, sigil_mask, kind, col, "gold", seed=10 + i)
        p.alpha_composite(e, (cx - e.width // 2, 0))
        draw_fancy_text(p, name.upper(), font("title", 25), (cx, 215), GOLD_STOPS, tracking=3, outline=2)
        plain_text(d, plays, font("italic", 16), (cx, 243), PARCH_DIM)
        d.line([cx - 50, 263, cx + 50, 263], fill=GOLD_0 + (255,))
        plain_text(d, "ascends into", font("sans", 11), (cx, 278), PARCH_DIM)
        plain_text(d, a1, font("title", 18), (cx, 299), lerp(col, (255, 255, 255), 0.45))
        plain_text(d, a2, font("title", 18), (cx, 321), lerp(col, (255, 255, 255), 0.45))
    return p


def panel_bosses():
    W, H = 560, 340
    p = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(p)
    pos = [(W * 0.17, 0), (W * 0.5, 0), (W * 0.83, 0), (W * 0.33, 172), (W * 0.67, 172)]
    for (kind, name, epi, col), (cx, y) in zip(BOSSES, pos):
        e = emblem(112, boss_mask, kind, col, "shadow", seed=30 + len(name))
        p.alpha_composite(e, (int(cx - e.width / 2), int(y) - 14))
        draw_fancy_text(p, name.upper(), font("title", 17), (cx, y + 128), GOLD_STOPS, tracking=2, outline=1,
                        shadow=False)
        plain_text(d, epi, font("italic", 14), (cx, y + 148), lerp(col, PARCH, 0.55))
    return p


def panel_rarity():
    W, H = 250, 340
    p = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(p)
    row = H / len(RARITIES)
    for i, (name, c) in enumerate(RARITIES):
        col = hexc(c)
        y = int(i * row + row / 2)
        x = 30
        gem = [(x, y - 8), (x + 8, y), (x, y + 8), (x - 8, y)]
        g = Image.new("L", p.size, 0)
        ImageDraw.Draw(g).polygon(gem, fill=255)
        add_glow(p, g, col, 5, 1.4)
        d.polygon(gem, fill=col + (255,), outline=BLACK + (255,))
        d.polygon([(x, y - 5), (x + 3, y - 1), (x, y), (x - 3, y - 1)], fill=(255, 255, 255, 140))
        bar_w = int(60 + i * 8.5)
        for k in range(bar_w):
            a = int(120 * (1 - k / bar_w))
            d.point((x + 16 + k, y), fill=col + (a,))
        plain_text(d, name, font("title", 17), (x + 18, y - 1), col, anchor="lm")
        plain_text(d, str(i + 1), font("sans", 10), (W - 6, y), PARCH_DIM, anchor="rm")
    return p


def panel_season():
    W, H = 830, 330
    p = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(p)
    # emblem: ash flame in a medallion
    ash = hexc("#b9b2a8")
    def flame(kind, size):
        S = size * SS
        m = Image.new("L", (S, S), 0)
        dd = ImageDraw.Draw(m)
        c = S / 2

        def tongue(cx, base, height, width, bend, fill, round_base=True):
            left, right = [], []
            for t in np.linspace(0, 1, 60):
                hw = width * (1 - t) ** 0.9 * min(1.0, (t + 0.2) * 2.2)
                x = cx + bend * t ** 2
                y = base - height * t
                left.append((x - hw, y))
                right.append((x + hw, y))
            dd.polygon(left + right[::-1], fill=fill)
            if round_base:
                dd.ellipse([cx - width * 0.98, base - width * 0.9, cx + width * 0.98, base + width * 0.85], fill=fill)

        base = c + S * 0.24
        tongue(c - S * 0.12, base - S * 0.04, S * 0.4, S * 0.11, -S * 0.1, 255, False)
        tongue(c + S * 0.12, base - S * 0.04, S * 0.44, S * 0.11, S * 0.1, 255, False)
        tongue(c, base, S * 0.66, S * 0.2, S * 0.04, 255)
        return m.resize((size, size), Image.LANCZOS)
    e = emblem(190, flame, "ash", hexc("#d0602a"), "gold", seed=77)
    p.alpha_composite(e, (10, 10))
    ex = 10 + e.width // 2
    draw_fancy_text(p, "SEASON OF ASH", font("title", 24), (ex, 262), GOLD_STOPS, tracking=3, outline=2)
    plain_text(d, "season characters  [S1]", font("italic", 16), (ex, 290), ash)
    # reward track
    x0, x1, ty = 300, 800, 70
    plain_text(d, "REWARD TRACK", font("sans", 13), (x0, ty - 42), GOLD_2, anchor="lm")
    for k in range(x1 - x0):
        t = k / (x1 - x0)
        d.line([(x0 + k, ty - 3), (x0 + k, ty + 3)], fill=lerp(GOLD_1, BLOOD_3, t) + (255,))
    d.rectangle([x0, ty - 4, x1, ty + 4], outline=BLACK + (255,))
    for i, lv in enumerate(("100", "300", "600", "1000")):
        x = x0 + 30 + i * (x1 - x0 - 60) / 3
        g = Image.new("L", p.size, 0)
        ImageDraw.Draw(g).ellipse([x - 16, ty - 16, x + 16, ty + 16], fill=255)
        add_glow(p, g, EMBER, 8, 1.2)
        d.ellipse([x - 15, ty - 15, x + 15, ty + 15], fill=IRON_1 + (255,), outline=GOLD_2 + (255,), width=3)
        d.polygon([(x, ty - 7), (x + 7, ty), (x, ty + 7), (x - 7, ty)], fill=BLOOD_4 + (255,))
        plain_text(d, "Level " + lv, font("title", 17), (x, ty + 32), PARCH)
    plain_text(d, "also: bounties, world bosses, rifts", font("italic", 15), ((x0 + x1) / 2, ty + 60), PARCH_DIM)
    # three pillars
    items = [("Own economy", "trade, mail, party\nand loot only inside\nyour season"),
             ("Season uniques", "some uniques drop\nonly in the season,\nthen for everyone"),
             ("Kept forever", "outfits, addons,\nmounts and titles for\nyour whole account")]
    bw = (x1 - x0 + 20) / 3
    for i, (head, body) in enumerate(items):
        bx = x0 - 10 + i * bw
        by = 170
        d.rounded_rectangle([bx + 4, by, bx + bw - 6, by + 140], radius=6, fill=(13, 11, 14, 220),
                            outline=GOLD_0 + (255,))
        d.line([bx + 14, by + 40, bx + bw - 16, by + 40], fill=GOLD_0 + (255,))
        plain_text(d, head, font("title", 19), (bx + bw / 2 - 1, by + 22), GOLD_3)
        d.multiline_text((bx + bw / 2 - 1, by + 82), body, font=font("serif", 15), fill=PARCH, anchor="mm",
                         align="center", spacing=6)
    return p


ORBS = [  # the crafting bench orbs, as in the README table
    ("Orb of Transmutation", "normal to Common or Uncommon", hexc("#3f7fe0")),
    ("Orb of Alchemy", "normal to Rare, Epic or Legendary", hexc("#e0b030")),
    ("Exalted Orb", "adds one modifier", hexc("#f0e6c8")),
    ("Orb of Annulment", "removes a random modifier", hexc("#c8d8e8")),
    ("Orb of Scouring", "back to a normal item", hexc("#9a948c")),
    ("Chaos Orb", "rerolls, same rarity", hexc("#e03a1e")),
    ("Divine Orb", "rerolls with a new rarity", hexc("#fff0b8")),
]


def orb_icon(size, color, seed):
    S = size * SS
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    c = S / 2
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (S * 0.42)
    lx, ly = (xx - c * 0.72) / (S * 0.42), (yy - c * 0.68) / (S * 0.42)
    spec = np.clip(1 - np.sqrt(lx ** 2 + ly ** 2) * 2.2, 0, 1) ** 2
    n = fbm(S, S, S / 3, 3, seed)
    shade = np.clip(1.15 - r * 0.9, 0, 1) * (0.75 + 0.35 * n)
    col = np.array(color, np.float32) * shade[..., None] + 255 * spec[..., None] * 0.9
    alpha = np.clip((1 - r) * S * 0.1, 0, 1) * 255
    img = Image.fromarray(np.dstack([np.clip(col, 0, 255), alpha]).astype(np.uint8), "RGBA")
    img = img.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size + 16, size + 16), (0, 0, 0, 0))
    m = Image.new("L", out.size, 0)
    ImageDraw.Draw(m).ellipse([8, 8, 8 + size, 8 + size], fill=255)
    add_glow(out, m, color, 5, 1.0)
    ImageDraw.Draw(out).ellipse([7, 7, 9 + size, 9 + size], outline=BLACK + (255,), width=2)
    out.alpha_composite(img, (8, 8))
    return out


def panel_orbs():
    W, H = 330, 336
    p = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(p)
    row = H / len(ORBS)
    for i, (name, what, col) in enumerate(ORBS):
        y = int(i * row + row / 2)
        ic = orb_icon(30, col, 90 + i)
        p.alpha_composite(ic, (4, y - ic.height // 2))
        plain_text(d, name, font("title", 18), (52, y - 9), GOLD_3, anchor="lm")
        plain_text(d, what, font("italic", 14), (52, y + 11), PARCH_DIM, anchor="lm")
    return p


def panel_placeholder(color=BLOOD_3):
    """Used when a screenshot source is missing and the card has never been drawn."""
    return emblem(220, boss_mask, "nyxareth", color, "shadow", seed=5)


# ---------------------------------------------------------------- screenshot sources
# name -> list of (path relative to the screenshot folder, crop box in that image). Crops keep to the
# game windows and HUDs: no debug text, chat logs, test map edges or other names.
SHOTS = {
    "passive_tree": [("pt_new.png", (560, 80, 1180, 720)), ("paragon_applied.png", (395, 108, 885, 678))],
    "loot": [("lootfilter_shots/05_filter_window_after_relog.png", (314, 133, 966, 652))],
    "crafting": [("craft/bench_after_exalted.png", (288, 118, 997, 681))],
    "endgame": [("rift_t10_chest.png", (146, 223, 377, 478))],
    "pvp": [("arena_window.png", (359, 128, 924, 585)), ("hud_hold.png", (514, 128, 766, 272))],
    "leaderboards": [("lb_worldboss_titles.png", (338, 126, 942, 462)), ("nameplate/09_zoom.png", (62, 0, 468, 150))],
    "achievements": [("achievements/07_window_rifts.png", (278, 118, 1007, 687))],
    "pets": [("pets/16_window_final.png", (352, 140, 1018, 622)), ("pets/03_spark_aura_on_heroes.png", (560, 180, 920, 400))],
    "qol": [("hunt/tab_loot.png", (419, 118, 866, 677)), ("daily/day7_milestone.png", (359, 153, 921, 637))],
}


def shot(shots_dir, name, idx):
    path, box = SHOTS[name][idx]
    full = os.path.join(shots_dir, path) if shots_dir else ""
    if not full or not os.path.exists(full):
        return None
    return Image.open(full).convert("RGB").crop(box)


def shots_or_none(shots_dir, name):
    ims = [shot(shots_dir, name, i) for i in range(len(SHOTS[name]))]
    return None if any(im is None for im in ims) else ims


# ---------------------------------------------------------------- cards
def card_classes(_):
    make_card("feature_classes.png", "Classes and Ascensions",
              "Four paths at level 1. Two ascensions each at level 100. Necromancer, Monk and Templar are coming.",
              [(panel_classes(), 1.0, False)], seed=11)


def card_bosses_rifts(sd):
    ims = shots_or_none(sd, "endgame")
    panels = [(panel_bosses(), 1.0, False)]
    if ims:
        panels.append((ims[0], 1.3, True))
    elif os.path.exists(os.path.join(OUT, "feature_endgame.png")):
        print("skip feature_endgame.png (screenshot missing, kept the existing image)")
        return
    make_card("feature_endgame.png", "World Bosses and Rifts",
              "Five colossi answer the portals at every temple. Rift Keys open ten minutes of chosen danger.",
              panels, seed=21, glow=hexc("#3a0a24"))


def card_loot(sd):
    ims = shots_or_none(sd, "loot")
    panels = [(panel_rarity(), 1.0, False)]
    if ims:
        panels.append((ims[0], 1.0, True))
    elif os.path.exists(os.path.join(OUT, "feature_loot.png")):
        print("skip feature_loot.png (screenshot missing, kept the existing image)")
        return
    make_card("feature_loot.png", "Fifteen Rarities",
              "From Common to Transcendent. The loot filter makes the good drops glow in their colour.",
              panels, seed=31)


def card_crafting(sd):
    ims = shots_or_none(sd, "crafting")
    panels = [(panel_orbs(), 1.0, False)]
    if ims:
        panels.append((ims[0], 1.0, True))
    elif os.path.exists(os.path.join(OUT, "feature_crafting.png")):
        print("skip feature_crafting.png (screenshot missing, kept the existing image)")
        return
    make_card("feature_crafting.png", "The Crafting Bench",
              "Orbs drop from monsters, bounties and the weekly chest. Uniques stay unique.", panels, seed=61,
              glow=hexc("#3a2a0a"))


def card_season(_):
    make_card("feature_seasons.png", "Seasons",
              "Start again with nothing but your name. What you earn on the ladder, your account keeps.",
              [(panel_season(), 1.0, False)], seed=41, glow=hexc("#3a1a0a"))


SHOT_CARDS = {
    # name: (file, title, caption, max scale per panel, background glow)
    "passive_tree": ("feature_passive_tree.png", "Passive Tree and Paragon",
                     "Over 600 nodes, class keystones, shareable build codes, and Paragon points past level 1000.",
                     (1.0, 1.0), BLOOD_1),
    "pvp": ("feature_pvp.png", "Arena and Guild Siege",
            "Ranked 1v1 and 2v2 duels. Every Saturday, guilds fight over the Chaos Obelisk.", (1.0, 1.25), BLOOD_1),
    "leaderboards": ("feature_leaderboards.png", "Leaderboards and Titles",
                     "Weekly boards, reset every Monday. The top three wear their title above their name.",
                     (1.0, 0.55), hexc("#2a1a3a")),
    "achievements": ("feature_achievements.png", "Achievements",
                     "Over 90 deeds to record, from the first rift sealed to the secrets nobody talks about.",
                     (1.0,), hexc("#1a2a3a")),
    "pets": ("feature_pets.png", "Pets",
             "A companion at your side that levels with your kills: it mends, wards, burns and fetches gold.",
             (1.0, 1.0), hexc("#2a1a10")),
    "qol": ("feature_qol.png", "Quality of Life",
            "A hunt tracker counted by the server, daily rewards and streaks, and patch notes in the client.",
            (1.0, 1.0), hexc("#1a2a1a")),
}


def card_from_shots(sd, key):
    fname, title, caption, scales, glow = SHOT_CARDS[key]
    ims = shots_or_none(sd, key)
    if ims is None:
        if os.path.exists(os.path.join(OUT, fname)):
            print("skip %s (screenshot missing, kept the existing image)" % fname)
            return
        panels = [(panel_placeholder(), 1.0, False)]
    else:
        panels = [(im, s, True) for im, s in zip(ims, scales)]
    make_card(fname, title, caption, panels, seed=50 + len(key), glow=glow)


# ---------------------------------------------------------------- banner
def crack_path(rng, x0, y0, x1, y1, depth, rough):
    """Jagged line by midpoint displacement (depth levels, rough = displacement / segment length)."""
    pts = [(x0, y0), (x1, y1)]
    for _ in range(depth):
        new = [pts[0]]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            L = math.hypot(bx - ax, by - ay)
            nx, ny = (-(by - ay) / (L or 1), (bx - ax) / (L or 1))
            o = rng.uniform(-1, 1) * L * rough
            new += [((ax + bx) / 2 + nx * o, (ay + by) / 2 + ny * o), (bx, by)]
        pts = new
    return pts


def banner(_):
    W, H = 1280, 320
    rng = np.random.RandomState(1998)
    # sky: dark violet-black smoke with a crimson horizon
    n = fbm(H, W, 220, 6, 3)
    n2 = fbm(H, W, 60, 4, 4)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    t = n * 0.7 + n2 * 0.3
    col = ramp(t, [(0, BLACK), (0.45, hexc("#0e0710")), (0.7, hexc("#1d0c16")), (1, hexc("#3a1018"))])
    horizon = np.exp(-((yy - H * 0.62) / (H * 0.28)) ** 2) * (0.6 + 0.4 * n2)
    col = col + np.array(BLOOD_2, np.float32) * horizon[..., None] * 0.55
    img = rgb_img(col).convert("RGBA")

    # the broken world: floating shards of land with molten rims
    for k in range(26):
        cx = rng.uniform(-40, W + 40)
        cy = H * 0.66 + rng.uniform(-30, 70) + (abs(cx - W / 2) / W) * 50
        s = rng.uniform(24, 90) * (1.4 if abs(cx - W / 2) > 380 else 0.8)
        top = [(cx - s, cy), (cx - s * 0.6, cy - s * rng.uniform(0.1, 0.35)), (cx + s * 0.2, cy - s * rng.uniform(0.15, 0.4)),
               (cx + s, cy - s * rng.uniform(0.0, 0.2))]
        bottom = [(cx + s * 0.7, cy + s * 0.3), (cx + s * 0.1, cy + s * rng.uniform(0.8, 1.3)), (cx - s * 0.5, cy + s * 0.4)]
        poly = top + bottom
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon(poly, fill=255)
        rimm = Image.new("L", (W, H), 0)
        ImageDraw.Draw(rimm).line(top, fill=255, width=2)
        add_glow(img, rimm, BLOOD_4, 4, 1.4)
        shard = Image.new("RGBA", (W, H), (9, 6, 9, 0))
        shard.putalpha(m)
        img.alpha_composite(shard)
        r = Image.new("RGBA", (W, H), EMBER + (0,))
        r.putalpha(rimm.point(lambda v: int(v * 0.8)))
        img.alpha_composite(r)

    # the crack: a glowing tear across the sky, with branches
    main = crack_path(rng, -20, H * 0.5, W + 20, H * 0.47, 7, 0.13)
    branches = []
    for _ in range(14):
        i = rng.randint(8, len(main) - 8)
        x, y = main[i]
        ang = rng.uniform(-1.2, 1.2) + (math.pi if rng.rand() < 0.5 else 0)
        L = rng.uniform(40, 150)
        branches.append(crack_path(rng, x, y, x + math.cos(ang) * L, y + math.sin(ang) * L * 0.8, 4, 0.3))

    def paint(d, wmain, wbr):
        d.line(main, fill=255, width=wmain, joint="curve")
        for b in branches:
            d.line(b, fill=255, width=wbr, joint="curve")

    img.alpha_composite(glow_layer((W, H), lambda d: paint(d, 22, 8), BLOOD_2, 26, 1.0))
    img.alpha_composite(glow_layer((W, H), lambda d: paint(d, 8, 3), BLOOD_4, 8, 1.2))
    img.alpha_composite(glow_layer((W, H), lambda d: paint(d, 3, 1), EMBER, 2, 1.6))
    core = Image.new("L", (W, H), 0)
    ImageDraw.Draw(core).line(main, fill=255, width=2, joint="curve")
    c = Image.new("RGBA", (W, H), GOLD_4 + (0,))
    c.putalpha(core)
    img.alpha_composite(c)

    # embers drifting up
    em = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ed = ImageDraw.Draw(em)
    for _ in range(260):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        r = rng.choice([0.6, 0.9, 1.2, 1.8], p=[0.4, 0.3, 0.2, 0.1])
        a = int(rng.uniform(90, 255))
        colr = lerp(EMBER, GOLD_4, rng.rand() * 0.6)
        ed.line([(x, y), (x - rng.uniform(-2, 2), y + rng.uniform(2, 7) * r)], fill=colr + (a // 3,), width=1)
        ed.ellipse([x - r, y - r, x + r, y + r], fill=colr + (a,))
    img.alpha_composite(em.filter(ImageFilter.GaussianBlur(0.6)))
    img.alpha_composite(em)

    # vignette
    r = np.sqrt(((xx - W / 2) / (W * 0.6)) ** 2 + ((yy - H / 2) / (H * 0.75)) ** 2)
    v = np.clip((r - 0.55) * 1.3, 0, 0.85)
    vig = Image.fromarray((v * 255).astype(np.uint8), "L")
    dark = Image.new("RGBA", (W, H), BLACK + (0,))
    dark.putalpha(vig)
    img.alpha_composite(dark)

    # backdrop behind the wordmark
    plate = Image.new("L", (W, H), 0)
    ImageDraw.Draw(plate).ellipse([W / 2 - 360, 60, W / 2 + 360, 260], fill=170)
    plate = plate.filter(ImageFilter.GaussianBlur(40))
    p = Image.new("RGBA", (W, H), BLACK + (0,))
    p.putalpha(plate)
    img.alpha_composite(p)

    # wordmark
    draw_fancy_text(img, "PROJECT", font("title", 30), (W / 2, 62), GOLD_STOPS, tracking=22, outline=2,
                    glow=(BLOOD_3, 8, 0.8))
    box = draw_fancy_text(img, "CHAOS", font("title", 128), (W / 2, 150), CHAOS_STOPS, tracking=14, outline=4,
                          glow=(BLOOD_3, 22, 1.3))
    # blood dripping from the letters
    word = text_mask("CHAOS", font("title", 128), 14)
    bx, by = box[0], box[1]
    wa = np.asarray(word) > 128
    drips = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(drips)
    cols = rng.choice(np.arange(6, word.width - 6), 16, replace=False)
    for cx in cols:
        ys = np.nonzero(wa[:, cx])[0]
        if len(ys) == 0:
            continue
        y0 = by + ys.max() - 3
        L = rng.uniform(8, 34)
        x = bx + cx
        dd.line([(x, y0), (x, y0 + L)], fill=BLOOD_2 + (255,), width=4)
        dd.ellipse([x - 3.5, y0 + L - 3, x + 3.5, y0 + L + 4], fill=BLOOD_2 + (255,))
        dd.line([(x - 1, y0 + 2), (x - 1, y0 + L - 2)], fill=BLOOD_4 + (200,), width=1)
    img.alpha_composite(drips)
    divider(img, 236, 300)
    d = ImageDraw.Draw(img)
    tag = "Seal the rifts. Slay the colossi. Ascend."
    plain_text(d, tag, font("italic", 22), (W / 2 + 1, 264 + 2), BLACK)
    plain_text(d, tag, font("italic", 22), (W / 2, 264), PARCH)
    sub = "DARK FANTASY  •  CLASSES & ASCENSIONS  •  WORLD BOSSES  •  RIFTS  •  SEASONS"
    plain_text(d, sub, font("sans", 12), (W / 2, 296), GOLD_2)
    # thin frame
    d.rectangle([0, 0, W - 1, H - 1], outline=GOLD_0 + (255,), width=1)
    d.rectangle([1, 1, W - 2, H - 2], outline=BLACK + (255,), width=1)
    save_png(img, "banner.png")


# ---------------------------------------------------------------- main
TASKS = {
    "banner": banner,
    "classes": card_classes,
    "passive_tree": lambda sd: card_from_shots(sd, "passive_tree"),
    "loot": card_loot,
    "crafting": card_crafting,
    "endgame": card_bosses_rifts,
    "seasons": card_season,
    "pvp": lambda sd: card_from_shots(sd, "pvp"),
    "leaderboards": lambda sd: card_from_shots(sd, "leaderboards"),
    "achievements": lambda sd: card_from_shots(sd, "achievements"),
    "pets": lambda sd: card_from_shots(sd, "pets"),
    "qol": lambda sd: card_from_shots(sd, "qol"),
}


def main(argv):
    shots_dir = DEFAULT_SHOTS
    names = []
    i = 0
    while i < len(argv):
        if argv[i] == "--shots" and i + 1 < len(argv):
            shots_dir = argv[i + 1]
            i += 2
            continue
        names.append(argv[i])
        i += 1
    for n in names:
        if n not in TASKS:
            sys.exit("unknown image %r (choose from: %s)" % (n, ", ".join(TASKS)))
    if not shots_dir:
        print("no screenshot folder (--shots DIR or CHAOS_SHOTS): screenshot cards are kept as they are")
    for n in names or list(TASKS):
        TASKS[n](shots_dir)


if __name__ == "__main__":
    main(sys.argv[1:])
