#!/usr/bin/env python3
"""Procedural art for the Project Chaos website and its promotion material, in the style of the client theme
(client/tools/gen_theme_art.py: iron blacks, gold, crimson; the same palette, glyph badges, logo and frames).

Run:  python3 -I website/tools/gen_site_art.py [task ...]      (no task = all)
Tasks: theme (site logo, header, favicon, frame pieces), classes (class badges), social, discord, otlist,
       showcase (class showcase), features (features infographic)
Output: website/overlay/layouts/chaos/assets/img/ (site), website/overlay/plugins/chaos/assets/img/ (class badges),
        website/art/ (banners and material to post elsewhere).
Needs Pillow + numpy. Reads the client's generated art (client/overlay/data/images/chaos/) and reuses the client
generator's code, so the site and the client stay one look. Text uses a serif TrueType font: the first found of
FONTS below, searched in $CHAOS_ART_FONTS and the system font folders; the result is deterministic for a given font.
All text and art here is original: no third-party logos, screenshots or names.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "client", "tools"))
import gen_theme_art as gta  # noqa: E402  (the client theme generator: palette, noise, glyph badges, logo)

CLIENT_IMG = os.path.join(REPO, "client", "overlay", "data", "images", "chaos")
OUT_THEME = os.path.join(REPO, "website", "overlay", "layouts", "chaos", "assets", "img")
OUT_PLUGIN = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "assets", "img")
OUT_ART = os.path.join(REPO, "website", "art")

BLACK, IRON_0, IRON_1, IRON_2, IRON_3, IRON_4, IRON_5 = gta.BLACK, gta.IRON_0, gta.IRON_1, gta.IRON_2, gta.IRON_3, gta.IRON_4, gta.IRON_5
BLOOD_1, BLOOD_2, BLOOD_3, BLOOD_4 = gta.BLOOD_1, gta.BLOOD_2, gta.BLOOD_3, gta.BLOOD_4
GOLD_0, GOLD_1, GOLD_2, GOLD_3, GOLD_4 = gta.GOLD_0, gta.GOLD_1, gta.GOLD_2, gta.GOLD_3, gta.GOLD_4
TEXT = gta.hexc("#d6c9ae")
MUTED = gta.hexc("#8c8070")

TAGLINE = "The world was not ended. It was broken, and the pieces still bleed."

# ---------------------------------------------------------------- fonts
FONTS = {
    "display": ["Cinzel-Bold.ttf", "CinzelDecorative-Bold.ttf", "CrimsonPro-Bold.ttf", "LiberationSerif-Bold.ttf",
                "DejaVuSerif-Bold.ttf", "FreeSerifBold.ttf"],
    "text": ["CrimsonPro-Regular.ttf", "LiberationSerif-Regular.ttf", "DejaVuSerif.ttf", "FreeSerif.ttf"],
    "italic": ["CrimsonPro-Italic.ttf", "LiberationSerif-Italic.ttf", "DejaVuSerif-Italic.ttf", "FreeSerifItalic.ttf"],
}
_FONT_INDEX = None
_FONT_CACHE = {}


def _font_index():
    global _FONT_INDEX
    if _FONT_INDEX is None:
        _FONT_INDEX = {}
        dirs = [d for d in os.environ.get("CHAOS_ART_FONTS", "").split(os.pathsep) if d]
        dirs += ["/usr/share/fonts", "/usr/local/share/fonts", os.path.expanduser("~/.fonts"),
                 os.path.expanduser("~/.local/share/fonts"), "/Library/Fonts", "C:/Windows/Fonts"]
        for d in dirs:
            for root, _, files in os.walk(d):
                for f in files:
                    _FONT_INDEX.setdefault(f, os.path.join(root, f))
    return _FONT_INDEX


def font(size, kind="display"):
    key = (size, kind)
    if key not in _FONT_CACHE:
        idx = _font_index()
        for name in FONTS[kind]:
            if name in idx:
                _FONT_CACHE[key] = ImageFont.truetype(idx[name], size)
                break
        else:
            _FONT_CACHE[key] = ImageFont.load_default(size)
    return _FONT_CACHE[key]


# ---------------------------------------------------------------- helpers
def save(img, folder, name, colors=0):
    """PNG, optionally quantised to a palette (keeps the material small)."""
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name)
    if colors:
        if img.mode == "RGBA":
            img = img.quantize(colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
        else:
            img = img.convert("RGB").quantize(colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    img.save(path, optimize=True)
    print("wrote %s %s %d KB" % (os.path.relpath(path, REPO), img.size, (os.path.getsize(path) + 1023) // 1024))


def client_image(name):
    return Image.open(os.path.join(CLIENT_IMG, name)).convert("RGBA")


def cover(img, w, h, focus_y=0.5):
    """Scale and crop to fill w x h."""
    s = max(w / img.width, h / img.height)
    im = img.resize((max(w, int(img.width * s + 0.5)), max(h, int(img.height * s + 0.5))), Image.LANCZOS)
    x = (im.width - w) // 2
    y = int((im.height - h) * focus_y)
    return im.crop((x, y, x + w, y + h))


def backdrop(w, h, focus_y=0.45, dark=0.55, seed=1):
    """The client's login background (moon, mountains, blood), darkened, with a vignette and crimson haze."""
    bg = cover(client_image("background.png"), w, h, focus_y)
    a = np.asarray(bg.convert("RGB")).astype(np.float32) / 255
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt(((xx - w / 2) / (w * 0.62)) ** 2 + ((yy - h * 0.45) / (h * 0.75)) ** 2)
    vig = np.clip(1.15 - r * 0.85, 0.15, 1.0)
    haze = gta.fbm(h, w, max(40, w / 9), 4, seed)
    a = a * (1 - dark) * vig[..., None]
    a[..., 0] += haze * 0.05 * (1 - vig * 0.5)
    return Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def iron_texture(w, h, seed=5):
    """Dark iron plate with low-frequency mottling and a crimson glow at the bottom."""
    n = gta.fbm(h, w, max(30, w / 12), 5, seed)
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32) / h
    base = np.zeros((h, w, 3), np.float32)
    for i in range(3):
        base[..., i] = IRON_1[i] * (1 - yy) + IRON_0[i] * yy
    base *= (0.75 + 0.5 * n)[..., None]
    glow = np.clip((yy - 0.55) / 0.45, 0, 1) ** 2 * gta.fbm(h, w, max(30, w / 6), 3, seed + 3)
    base[..., 0] += glow * 70
    base[..., 1] += glow * 8
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def _mask_text(size, xy, text, fnt, anchor="la", spacing=0):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    if spacing:
        x, y = xy
        total = sum(d.textlength(c, font=fnt) for c in text) + spacing * (len(text) - 1)
        if anchor[0] == "m":
            x -= total / 2
        elif anchor[0] == "r":
            x -= total
        for c in text:
            d.text((x, y), c, font=fnt, fill=255, anchor="l" + anchor[1])
            x += d.textlength(c, font=fnt) + spacing
    else:
        d.text(xy, text, font=fnt, fill=255, anchor=anchor)
    return m


def gold_text(img, xy, text, fnt, anchor="la", spacing=0, glow=0.0, shadow=True, colors=(GOLD_4, GOLD_3, GOLD_1)):
    """Engraved gold text: gradient body, dark outline, drop shadow, optional ember glow."""
    W, H = img.size
    m = _mask_text((W, H), xy, text, fnt, anchor, spacing)
    box = m.getbbox()
    if not box:
        return
    M = np.asarray(m).astype(np.float32) / 255
    if glow:
        g = np.asarray(m.filter(ImageFilter.GaussianBlur(max(2, fnt.size / 5)))).astype(np.float32) / 255
        img.alpha_composite(layer((200, 40, 15), np.clip(g * glow, 0, 1), W, H))
    if shadow:
        s = np.asarray(gta.shift(m, max(1, fnt.size // 22), max(1, fnt.size // 16)).filter(
            ImageFilter.GaussianBlur(max(1, fnt.size / 24)))).astype(np.float32) / 255
        img.alpha_composite(layer((0, 0, 0), s * 0.9, W, H))
    ol = np.asarray(m.filter(ImageFilter.MaxFilter(3 if fnt.size < 40 else 5))).astype(np.float32) / 255
    img.alpha_composite(layer((8, 3, 3), ol * 0.95, W, H))
    y0, y1 = box[1], box[3]
    t = np.clip((np.mgrid[0:H, 0:W][0].astype(np.float32) - y0) / max(1, y1 - y0), 0, 1)
    body = np.zeros((H, W, 3), np.float32)
    c0, c1, c2 = colors
    for i in range(3):
        body[..., i] = np.interp(t, [0, 0.5, 1], [c0[i], c1[i], c2[i]])
    lay = Image.fromarray(np.clip(body, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    lay.putalpha(Image.fromarray((M * 255).astype(np.uint8)))
    img.alpha_composite(lay)


def plain_text(img, xy, text, fnt, fill=TEXT, anchor="la", shadow=True):
    d = ImageDraw.Draw(img)
    if shadow:
        d.text((xy[0] + 1, xy[1] + 2), text, font=fnt, fill=(0, 0, 0, 200), anchor=anchor)
    d.text(xy, text, font=fnt, fill=tuple(fill) + (255,), anchor=anchor)


def wrap(text, fnt, width):
    d = ImageDraw.Draw(Image.new("L", (1, 1)))
    lines, cur = [], ""
    for word in text.split():
        trial = (cur + " " + word).strip()
        if d.textlength(trial, font=fnt) <= width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def layer(color, a, w, h):
    lay = Image.new("RGBA", (w, h), tuple(int(c) for c in color) + (0,))
    lay.putalpha(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)))
    return lay


_ORN = {}


def ornament(name, size):
    key = (name, size)
    if key not in _ORN:
        im = Image.open(os.path.join(CLIENT_IMG, "skin", name)).convert("RGBA")
        s = size / max(im.width, im.height)
        _ORN[key] = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    return _ORN[key]


def panel(img, box, corner=30, crest=False, fill_alpha=225, gold=True):
    """A client-style window: iron band, black groove, gold trim, crimson etch, gold corner ornaments."""
    x0, y0, x1, y1 = [int(v) for v in box]
    w, h = x1 - x0, y1 - y0
    face = iron_texture(w, h, seed=(x0 * 7 + y0) % 997)
    a = np.asarray(face).copy()
    a[..., 3] = fill_alpha
    img.alpha_composite(Image.fromarray(a, "RGBA"), (x0, y0))
    d = ImageDraw.Draw(img)
    d.rectangle([x0, y0, x1 - 1, y1 - 1], outline=BLACK + (255,), width=2)
    d.rectangle([x0 + 2, y0 + 2, x1 - 3, y1 - 3], outline=IRON_4 + (255,), width=1)
    d.rectangle([x0 + 3, y0 + 3, x1 - 4, y1 - 4], outline=IRON_2 + (255,), width=3)
    d.rectangle([x0 + 6, y0 + 6, x1 - 7, y1 - 7], outline=BLACK + (255,), width=1)
    if gold:
        d.rectangle([x0 + 7, y0 + 7, x1 - 8, y1 - 8], outline=GOLD_2 + (255,), width=1)
        d.rectangle([x0 + 8, y0 + 8, x1 - 9, y1 - 9], outline=GOLD_0 + (200,), width=1)
    d.rectangle([x0 + 9, y0 + 9, x1 - 10, y1 - 10], outline=BLOOD_1 + (160,), width=1)
    if corner:
        for name, (cx, cy) in (("orn_corner_tl.png", (x0 - 3, y0 - 3)), ("orn_corner_tr.png", (x1 + 3 - corner, y0 - 3)),
                               ("orn_corner_bl.png", (x0 - 3, y1 + 3 - corner)), ("orn_corner_br.png", (x1 + 3 - corner, y1 + 3 - corner))):
            img.alpha_composite(ornament(name, corner), (int(cx), int(cy)))
    if crest:
        c = ornament("orn_crest.png", int(corner * 2.6))
        img.alpha_composite(c, (x0 + (w - c.width) // 2, y0 - c.height // 2 + 2))


def divider(img, cx, y, half):
    d = ImageDraw.Draw(img)
    for s in (-1, 1):
        for i in range(half):
            t = i / half
            col = tuple(int(c) for c in gta.lerp(GOLD_3, BLOOD_2, t)) + (int(255 * (1 - t) ** 0.7),)
            d.point((cx + s * (10 + i), y), col)
            d.point((cx + s * (10 + i), y + 1), col)
    d.polygon([(cx, y - 7), (cx + 7, y), (cx, y + 7), (cx - 7, y)], fill=BLACK + (255,))
    d.polygon([(cx, y - 4), (cx + 4, y), (cx, y + 4), (cx - 4, y)], fill=BLOOD_3 + (255,))


def chaos_word(height):
    """The client's CHAOS logo (gen_theme_art.make_logo), trimmed, scaled to a height."""
    lg = gta.make_logo()
    box = lg.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    lg = lg.crop(box)
    s = height / lg.height
    return lg.resize((max(1, int(lg.width * s)), height), Image.LANCZOS)


_WORD = {}


def word(height):
    if height not in _WORD:
        _WORD[height] = chaos_word(height)
    return _WORD[height]


# ---------------------------------------------------------------- class glyphs (client glyph space, 0..100)
def glyph_warrior(g):
    gta.sword(g, 30, 75, 70, 25)
    gta.sword(g, 70, 75, 30, 25)


def glyph_ranger(g):
    U = gta.U
    g.d.arc([22 * U, 22 * U, 70 * U, 78 * U], 290, 70, fill=255, width=int(5.5 * U))
    g.line([(57, 27), (57, 73)], 1.6)
    g.line([(28, 50), (74, 50)], 3.2)
    g.poly([(80, 50), (71, 45), (71, 55)])
    g.poly([(28, 50), (22, 44), (25, 50), (22, 56)])


def glyph_mystic(g):
    g.line([(34, 78), (58, 36)], 5)
    g.circ(62, 30, 10)
    g.circ(62, 30, 5, 0)
    g.circ(62, 30, 2.4)
    g.poly(gta.star_pts(36, 34, 7, 2.6, 4, -90))
    g.poly(gta.star_pts(76, 56, 5, 2.0, 4, -90))


def glyph_thief(g):
    # dagger
    g.poly([(30, 76), (26, 72), (56, 38), (64, 34), (60, 42)])
    g.line([(26, 64), (38, 76)], 3.6)
    g.line([(24, 78), (30, 72)], 4.2)
    # shuriken
    g.poly(gta.star_pts(64, 64, 15, 4.5, 4, -45))
    g.circ(64, 64, 3.2, 0)


def glyph_monk(g):
    g.circ(50, 50, 25)
    g.circ(50, 50, 19, 0)
    for i in range(5):
        a = math.radians(-90 + i * 72)
        g.circ(50 + 11 * math.cos(a), 50 + 11 * math.sin(a), 3.6)
    g.circ(50, 50, 4.4)


def glyph_templar(g):
    g.smooth([(28, 28), (50, 22), (72, 28), (70, 54), (50, 78), (30, 54)], 255, 2)
    g.smooth([(34, 33), (50, 28.5), (66, 33), (64.5, 52), (50, 70), (35.5, 52)], 0, 2)
    g.rect(47, 32, 53, 64)
    g.rect(38, 42, 62, 48)


CLASSES = [
    ("warrior", glyph_warrior), ("ranger", glyph_ranger), ("mystic", glyph_mystic), ("thief", glyph_thief),
    ("monk", glyph_monk), ("necromancer", gta.glyph_pvp), ("templar", glyph_templar),
]
_BADGE = {}


def badge(name, size, hover=False):
    key = (name, size, hover)
    if key not in _BADGE:
        fn = dict(CLASSES)[name]
        icon = gta.render_icon(fn, hover)
        icon = icon.crop((10, 10, gta.N - 10, gta.N - 10))
        _BADGE[key] = icon.resize((size, size), Image.LANCZOS)
    return _BADGE[key]


def gen_classes():
    for name, _ in CLASSES:
        save(badge(name, 64), OUT_PLUGIN, "class-%s.png" % name)


# ---------------------------------------------------------------- site theme
def make_wordmark(width):
    """'PROJECT' over the client's CHAOS logo, the tagline under it (transparent)."""
    H = int(width * 0.47)
    img = Image.new("RGBA", (width, H), (0, 0, 0, 0))
    w = word(int(H * 0.56))
    if w.width > width * 0.94:
        w = w.resize((int(width * 0.94), int(w.height * width * 0.94 / w.width)), Image.LANCZOS)
    top = int(H * 0.2)
    img.alpha_composite(w, ((width - w.width) // 2, top))
    gold_text(img, (width // 2, int(H * 0.12)), "PROJECT", font(int(H * 0.115)), anchor="mm", spacing=int(H * 0.05), glow=0.35)
    y = top + w.height + int(H * 0.025)
    divider(img, width // 2, y, int(width * 0.3))
    plain_text(img, (width // 2, y + int(H * 0.085)), TAGLINE, font(max(11, int(H * 0.06)), "italic"), fill=TEXT, anchor="mm")
    return img


def gen_theme():
    # logo (header and footer of the layout)
    save(make_wordmark(640), OUT_THEME, "logo.png", colors=256)
    # header band: the client's login background, darker at the bottom where the panels start
    W, H = 1280, 448
    bg = backdrop(W, H, focus_y=0.35, dark=0.35, seed=11)
    a = np.asarray(bg).astype(np.float32)
    yy = np.mgrid[0:H, 0:W][0].astype(np.float32) / H
    fade = np.clip((yy - 0.55) / 0.45, 0, 1) ** 1.4
    a[..., :3] = a[..., :3] * (1 - fade[..., None]) + np.array(BLACK, np.float32) * fade[..., None]
    save(Image.fromarray(a.astype(np.uint8), "RGBA").convert("RGB"), OUT_THEME, "header.png", colors=96)
    # favicon: the C of the logo on a client badge
    fav = gta.render_icon(glyph_letter_c, False).crop((10, 10, gta.N - 10, gta.N - 10))
    save(fav.resize((64, 64), Image.LANCZOS), OUT_THEME, "favicon.png")
    save(fav.resize((180, 180), Image.LANCZOS), OUT_THEME, "apple-touch-icon.png", colors=256)
    # frame pieces for the stylesheet (the client's own ornaments)
    for name in ("orn_corner_tl.png", "orn_corner_tr.png", "orn_corner_bl.png", "orn_corner_br.png", "orn_crest.png"):
        save(Image.open(os.path.join(CLIENT_IMG, "skin", name)).convert("RGBA"), OUT_THEME, name.replace("orn_", "frame-"))
    # iron texture tile for panels
    save(seamless(iron_texture(256, 256, seed=21).convert("RGB")), OUT_THEME, "iron.png", colors=64)


def seamless(img):
    """Cross-fade a tile with its half-offset copy so it repeats without seams."""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    r = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    m = np.minimum(np.minimum(xx, w - 1 - xx) / (w / 2), np.minimum(yy, h - 1 - yy) / (h / 2))
    m = np.clip(m * 1.6, 0, 1)[..., None]
    return Image.fromarray(np.clip(a * m + r * (1 - m), 0, 255).astype(np.uint8), "RGB")


def glyph_letter_c(g):
    L = gta.letter_masks()
    fn, _ = L["C"]
    k = gta.U * 0.36
    fn(g.d, 32 * gta.U, 27 * gta.U, k)


# ---------------------------------------------------------------- promotion material
FEATURE_CHIPS = ["4 classes, 8 ascensions", "600+ node passive tree", "Rifts, world bosses, seasons"]


def chip(img, cx, y, text, fnt):
    d = ImageDraw.Draw(img)
    tw = d.textlength(text, font=fnt)
    x0, x1 = int(cx - tw / 2 - 16), int(cx + tw / 2 + 16)
    h = int(fnt.size * 1.7)
    d.rectangle([x0, y, x1, y + h], fill=IRON_1 + (230,), outline=GOLD_1 + (255,))
    d.rectangle([x0 + 2, y + 2, x1 - 2, y + h - 2], outline=BLOOD_1 + (255,))
    plain_text(img, (cx, y + h // 2), text, fnt, fill=TEXT, anchor="mm")
    return x1 - x0


def gen_social():
    W, H = 1200, 630
    img = backdrop(W, H, focus_y=0.3, dark=0.45, seed=3)
    panel(img, (24, 24, W - 24, H - 24), corner=40, fill_alpha=0, gold=True)
    lg = make_wordmark(820)
    img.alpha_composite(lg, ((W - lg.width) // 2, 70))
    f = font(24, "text")
    d = ImageDraw.Draw(img)
    widths = [d.textlength(t, font=f) + 32 for t in FEATURE_CHIPS]
    gap = 22
    x = (W - (sum(widths) + gap * (len(widths) - 1))) / 2
    for t, w in zip(FEATURE_CHIPS, widths):
        chip(img, x + w / 2, 500, t, f)
        x += w + gap
    plain_text(img, (W // 2, 572), "Dark fantasy OT server  |  protocol 10.98  |  own client", font(20, "text"), fill=MUTED, anchor="mm")
    save(img.convert("RGB"), OUT_ART, "social-share-1200x630.png", colors=128)


def gen_discord():
    W, H = 960, 540
    img = backdrop(W, H, focus_y=0.25, dark=0.4, seed=4)
    lg = make_wordmark(700)
    img.alpha_composite(lg, ((W - lg.width) // 2, 90))
    x = W // 2 - 4 * 70 // 2 - 3 * 14 // 2
    for name in ("warrior", "ranger", "mystic", "thief"):
        img.alpha_composite(badge(name, 70), (x, 420))
        x += 84
    save(img.convert("RGB"), OUT_ART, "discord-banner-960x540.png", colors=128)
    icon = gta.render_icon(glyph_letter_c, True).crop((10, 10, gta.N - 10, gta.N - 10)).resize((512, 512), Image.LANCZOS)
    bg = Image.new("RGBA", (512, 512), BLACK + (255,))
    bg.alpha_composite(icon)
    save(bg.convert("RGB"), OUT_ART, "discord-icon-512.png", colors=128)


def gen_otlist():
    # 468 x 60, the classic list banner
    W, H = 468, 60
    img = backdrop(W, H, focus_y=0.4, dark=0.5, seed=6)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=BLACK + (255,), width=1)
    d.rectangle([1, 1, W - 2, H - 2], outline=GOLD_1 + (255,), width=1)
    d.rectangle([2, 2, W - 3, H - 3], outline=BLOOD_1 + (255,), width=1)
    w = word(40)
    img.alpha_composite(w, (12, 8))
    gold_text(img, (12 + w.width // 2, 54), "PROJECT", font(9), anchor="mb", spacing=3, shadow=False)
    tx = 12 + w.width + 14
    plain_text(img, (tx, 19), "Dark fantasy  |  10.98  |  own client", font(13, "display"), fill=GOLD_3, anchor="lm")
    plain_text(img, (tx, 40), "4 classes, 8 ascensions, rifts, seasons", font(12, "text"), fill=TEXT, anchor="lm")
    bx0, bx1 = W - 86, W - 10
    d.rectangle([bx0, 14, bx1, 46], fill=BLOOD_2 + (255,), outline=GOLD_2 + (255,))
    d.rectangle([bx0 + 2, 16, bx1 - 2, 44], outline=BLOOD_4 + (255,))
    gold_text(img, ((bx0 + bx1) // 2, 31), "PLAY", font(16), anchor="mm", spacing=2)
    save(img.convert("RGB"), OUT_ART, "otlist-468x60.png", colors=128)
    # 88 x 31 button
    W, H = 88, 31
    img = backdrop(W, H, focus_y=0.4, dark=0.55, seed=7)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=GOLD_1 + (255,))
    w = word(19)
    if w.width > 60:
        w = w.resize((60, int(w.height * 60 / w.width)), Image.LANCZOS)
    img.alpha_composite(w, ((W - w.width) // 2, 2))
    plain_text(img, (W // 2, 26), "10.98 DARK FANTASY", font(7, "text"), fill=TEXT, anchor="mm", shadow=False)
    save(img.convert("RGB"), OUT_ART, "otlist-88x31.png", colors=64)


SHOWCASE = [
    ("warrior", "Warrior", "Melee, heavy armour, the most health",
     [("Juggernaut", "The tank: taunts, damage reduction, block and reflect"),
      ("Berserker", "Two-handed area damage; Rage grows as health drops")]),
    ("ranger", "Ranger", "Bows and crossbows",
     [("Deadeye", "The best single-target damage: crossbows, marks, crits"),
      ("Beastmaster", "Fights beside a War Wolf that grows with you")]),
    ("mystic", "Mystic", "Spells, wands and rods",
     [("Elementalist", "The best area damage: fire, ice and energy combos"),
      ("Illusionist", "The support: party attack buffs, debuffs and heals")]),
    ("thief", "Thief", "Fast light blades, shurikens and stealth",
     [("Ninja", "Dual daggers, Shadow Step, Smoke Bomb"),
      ("Samurai", "One sword, Counter Stance, Iaijutsu, Bushido")]),
]


def gen_showcase():
    W, H = 1400, 900
    img = backdrop(W, H, focus_y=0.2, dark=0.6, seed=8)
    gold_text(img, (W // 2, 70), "CHOOSE YOUR PATH", font(54), anchor="mm", spacing=6, glow=0.5)
    plain_text(img, (W // 2, 122), "Four base classes. At level 100 each ascends into one of two specialisations.",
               font(24, "italic"), fill=TEXT, anchor="mm")
    divider(img, W // 2, 152, 300)
    colw, gap, top = 316, 24, 190
    x = (W - (4 * colw + 3 * gap)) // 2
    for key, name, plays, ascs in SHOWCASE:
        panel(img, (x, top, x + colw, top + 610), corner=34, crest=True)
        img.alpha_composite(badge(key, 120), (x + (colw - 120) // 2, top + 34))
        gold_text(img, (x + colw // 2, top + 186), name.upper(), font(36), anchor="mm", spacing=4, glow=0.3)
        for i, line in enumerate(wrap(plays, font(19, "italic"), colw - 50)):
            plain_text(img, (x + colw // 2, top + 222 + i * 24), line, font(19, "italic"), fill=MUTED, anchor="mm")
        y = top + 280
        for aname, adesc in ascs:
            d = ImageDraw.Draw(img)
            d.rectangle([x + 22, y, x + colw - 22, y + 140], fill=(12, 8, 10, 200), outline=BLOOD_2 + (255,))
            d.line([(x + 22, y), (x + colw - 22, y)], fill=GOLD_2 + (255,), width=1)
            gold_text(img, (x + colw // 2, y + 28), aname, font(28), anchor="mm", colors=(GOLD_4, GOLD_3, GOLD_2))
            for i, line in enumerate(wrap(adesc, font(19, "text"), colw - 70)):
                plain_text(img, (x + colw // 2, y + 66 + i * 24), line, font(19, "text"), fill=TEXT, anchor="mm")
            y += 158
        x += colw + gap
    plain_text(img, (W // 2, 845), "Unlockable classes: Monk  |  Necromancer  |  Templar", font(24, "display"), fill=GOLD_3, anchor="mm")
    save(img.convert("RGB"), OUT_ART, "class-showcase-1400x900.png", colors=128)


FEATURES = [
    ("Classes and ascensions", ["4 base classes, 2 ascensions each", "Own Chaos spells, icons and effects",
                                "Balanced at levels 300 and 1000"]),
    ("Passive tree and Paragon", ["Over 600 nodes, class keystones", "Build codes to share, priced respec",
                                  "Paragon points after level 1000"]),
    ("Items and loot", ["15 rarities, item levels, modifiers", "About 50 build-defining uniques",
                        "Loot filter, loot rays, rarity autoloot"]),
    ("Crafting orbs", ["Awakening, Gilding, Grafting", "Unmaking, Erasure, Upheaval, Fate",
                       "A crafting bench that shows it all"]),
    ("Endgame", ["Five world bosses with phases", "Rifts with keys, tiers and modifiers",
                 "Infinity Tower, dungeons, bounties"]),
    ("Seasons", ["Fresh season characters and ladder", "Season uniques and a reward track",
                 "Everything kept when the season ends"]),
    ("PvP", ["Ranked arena 1v1 and 2v2 with Elo", "Weekly Guild Siege for the Obelisk",
             "Nobody really dies in either"]),
    ("Leaderboards and titles", ["Seven weekly boards, reset Monday", "Top 3 earn titles and orbs",
                                 "All-time Class Ladder"]),
]


def gen_features():
    W, H = 1200, 1560
    img = iron_texture(W, H, seed=12)
    img.alpha_composite(backdrop(W, 420, focus_y=0.25, dark=0.35, seed=13), (0, 0))
    a = np.asarray(img).astype(np.float32)
    yy = np.mgrid[0:H, 0:W][0].astype(np.float32)
    fade = np.clip((yy - 300) / 160, 0, 1) * (yy < 460)
    base = np.asarray(iron_texture(W, H, seed=12)).astype(np.float32)
    a = a * (1 - fade[..., None]) + base * fade[..., None]
    img = Image.fromarray(a.astype(np.uint8), "RGBA")
    lg = make_wordmark(560)
    img.alpha_composite(lg, ((W - lg.width) // 2, 40))
    gold_text(img, (W // 2, 340), "A HUNT-AND-LOOT WORLD WITH ACTION RPG DEPTH", font(30), anchor="mm", spacing=2, glow=0.3)
    plain_text(img, (W // 2, 380), "Protocol 10.98  |  Level cap 1000, then Paragon  |  Own client with a custom skin",
               font(21, "text"), fill=MUTED, anchor="mm")
    cw, ch, gx, gy, top = 540, 230, 40, 40, 430
    x0 = (W - (2 * cw + gx)) // 2
    for i, (title, lines) in enumerate(FEATURES):
        cx = x0 + (i % 2) * (cw + gx)
        cy = top + (i // 2) * (ch + gy)
        panel(img, (cx, cy, cx + cw, cy + ch), corner=28)
        gold_text(img, (cx + 34, cy + 46), title.upper(), font(27), anchor="lm", spacing=1)
        d = ImageDraw.Draw(img)
        d.line([(cx + 34, cy + 72), (cx + cw - 34, cy + 72)], fill=BLOOD_2 + (255,), width=1)
        for j, line in enumerate(lines):
            ly = cy + 108 + j * 40
            d.polygon([(cx + 40, ly - 6), (cx + 46, ly), (cx + 40, ly + 6), (cx + 34, ly)], fill=BLOOD_3 + (255,))
            plain_text(img, (cx + 58, ly), line, font(23, "text"), fill=TEXT, anchor="lm")
    plain_text(img, (W // 2, H - 52), "Daily rewards and streaks  |  hunt tracker  |  patch notes in the client  |  store",
               font(21, "text"), fill=GOLD_3, anchor="mm")
    save(img.convert("RGB"), OUT_ART, "features-1200x1560.png", colors=96)


TASKS = {"theme": gen_theme, "classes": gen_classes, "social": gen_social, "discord": gen_discord,
         "otlist": gen_otlist, "showcase": gen_showcase, "features": gen_features}


def main(argv):
    for t in (argv[1:] or list(TASKS)):
        if t not in TASKS:
            print("unknown task %r (%s)" % (t, ", ".join(TASKS)))
            return 2
        TASKS[t]()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
