#!/usr/bin/env python3
"""Procedural art generator for the Chaos dark-fantasy OTClient theme.

Run:  python3 -I client/tools/gen_theme_art.py [icons] [background] [logo]
(no argument = all three).  The frame and control images of chaos/ (window, buttons, panels, tabs,
scroll bars, ...) are drawn by gen_skin.py now; the old "frames" task here would overwrite them with the
previous flat look, so it only runs when asked for by name.  Needs Pillow + numpy.  Output goes to
client/overlay/data/images/chaos/.  Deterministic (fixed seeds).
"""
import os
import sys
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "overlay", "data", "images", "chaos"))

# ---------------------------------------------------------------- palette
def hexc(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))

BLACK = hexc("#050405")
IRON_0 = hexc("#0d0b0e")
IRON_1 = hexc("#17141a")
IRON_2 = hexc("#241f27")
IRON_3 = hexc("#3a3339")
IRON_4 = hexc("#574d52")
IRON_5 = hexc("#7d7176")
BLOOD_0 = hexc("#2a0505")
BLOOD_1 = hexc("#5a0a0a")
BLOOD_2 = hexc("#8a1010")
BLOOD_3 = hexc("#b8160f")
BLOOD_4 = hexc("#e03a1e")
GOLD_0 = hexc("#6b4a14")
GOLD_1 = hexc("#a87420")
GOLD_2 = hexc("#d9a53a")
GOLD_3 = hexc("#f6cf72")
GOLD_4 = hexc("#fff0b8")
MANA_1 = hexc("#101f4a")
MANA_2 = hexc("#1f3f8f")


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)


# ---------------------------------------------------------------- noise
def fbm(h, w, scale, octaves=5, seed=0, persistence=0.5):
    """Fractal value noise in [0,1], float32 (h,w)."""
    rng = np.random.RandomState(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        gh = max(2, int(h / scale * (2 ** o)) + 2)
        gw = max(2, int(w / scale * (2 ** o)) + 2)
        g = rng.rand(gh, gw).astype(np.float32)
        im = Image.fromarray(g, "F").resize((w, h), Image.BICUBIC)
        out += np.asarray(im) * amp
        tot += amp
        amp *= persistence
    out /= tot
    return np.clip(out, 0, 1)


def to_img(arr):
    return Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8))


def blur(img, r):
    return img.filter(ImageFilter.GaussianBlur(r))


# ---------------------------------------------------------------- frames
def metal(w, h, c_hi, c_lo, seed, vertical_grain=False, grain=7):
    """Brushed iron texture (float array h,w,3 in 0..255)."""
    rng = np.random.RandomState(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = (xx / max(w, 1) * 0.5 + yy / max(h, 1) * 0.5)
    base = np.zeros((h, w, 3), np.float32)
    for i in range(3):
        base[..., i] = c_hi[i] + (c_lo[i] - c_hi[i]) * t
    if vertical_grain:
        g = rng.randn(1, w).astype(np.float32) * grain
    else:
        g = rng.randn(h, 1).astype(np.float32) * grain
    g = g + rng.randn(h, w).astype(np.float32) * grain * 0.45
    base += g[..., None]
    return base


def plate(w, h, bw, face=(IRON_1, IRON_0), band=(IRON_4, IRON_2), inset=False,
          etch=BLOOD_2, seed=1, corner_cut=1, groove=True, etch_inner=True):
    """Generic beveled iron plate. Returns RGBA image."""
    arr = np.zeros((h, w, 4), np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.minimum(np.minimum(xx, yy), np.minimum(w - 1 - xx, h - 1 - yy))
    # interior face: vertical gradient + low freq mottling
    t = (yy / max(h - 1, 1)).astype(np.float32)
    mott = fbm(h, w, 14, 3, seed) * 10 - 5
    rng = np.random.RandomState(seed + 7)
    fine = rng.randn(h, w).astype(np.float32) * 2.2
    for i in range(3):
        arr[..., i] = face[0][i] + (face[1][i] - face[0][i]) * t + mott + fine
    arr[..., 3] = 255
    # band
    m = metal(w, h, band[0], band[1], seed + 3)
    mv = metal(w, h, band[0], band[1], seed + 4, vertical_grain=True)
    side = (np.minimum(xx, w - 1 - xx) < np.minimum(yy, h - 1 - yy))
    mm = np.where(side[..., None], mv, m)
    inband = dist < bw
    arr[..., :3] = np.where(inband[..., None], mm, arr[..., :3])
    hi = np.array(IRON_5, np.float32)
    lo = np.array(IRON_0, np.float32)
    topleft = (yy <= xx * (h / w) * 0 + yy) & True
    # bevel lines on dist==1
    is_tl = ((yy == 1) & (xx >= 1) & (xx <= w - 2)) | ((xx == 1) & (yy >= 1) & (yy <= h - 2))
    is_br = ((yy == h - 2) & (xx >= 1) & (xx <= w - 2)) | ((xx == w - 2) & (yy >= 1) & (yy <= h - 2))
    if inset:
        is_tl, is_br = is_br, is_tl
    arr[is_tl, :3] = hi
    arr[is_br, :3] = lo
    # inner edge of the band
    if groove:
        g = dist == bw
        arr[g, :3] = BLACK
        if etch_inner:
            e = dist == bw + 1
            arr[e, :3] = etch
            e2 = dist == bw + 2
            arr[e2, :3] = np.array(etch, np.float32) * 0.35 + arr[e2, :3] * 0.65
    # outline
    arr[dist == 0, :3] = BLACK
    # cut corners
    for cx in (0, w - 1):
        for cy in (0, h - 1):
            for k in range(corner_cut):
                for j in range(corner_cut - k):
                    arr[cy + (j if cy == 0 else -j), cx + (k if cx == 0 else -k), 3] = 0
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def ss_patch(w, h, fn, k=4):
    """Draw with supersampling: fn(draw, k) paints on an RGBA (w*k,h*k) canvas."""
    im = Image.new("RGBA", (w * k, h * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    fn(d, k)
    return im.resize((w, h), Image.LANCZOS)


def rivet(img, cx, cy, r=3, tone=1.0):
    S = int(r * 2 + 6)
    def f(d, k):
        c = S * k / 2
        d.ellipse([c - (r + 1) * k, c - (r + 1) * k, c + (r + 1) * k, c + (r + 1) * k], fill=(5, 4, 5, 255))
        n = 14
        for i in range(n):
            rr = r * k * (1 - i / n)
            col = lerp((70, 60, 64), (170, 150, 140), i / n)
            col = tuple(int(c_ * tone) for c_ in col)
            ox = -0.35 * k * (i / n) * r * 0.5
            d.ellipse([c + ox - rr, c + ox - rr, c + ox + rr, c + ox + rr], fill=col + (255,))
        d.ellipse([c - r * k * 0.35 - k * 0.6, c - r * k * 0.35 - k * 0.6, c - r * k * 0.35 + k * 0.6, c - r * k * 0.35 + k * 0.6], fill=(235, 215, 190, 255))
    p = ss_patch(S, S, f)
    img.alpha_composite(p, (int(cx - S / 2), int(cy - S / 2)))


def gold_bracket(img, x, y, sx, sy, length=13, thick=2):
    """Corner bracket in ember gold, sx/sy = direction (+1/-1) away from the corner."""
    arr = img
    d = ImageDraw.Draw(arr)
    for i in range(length):
        t = i / length
        col = lerp(GOLD_3, GOLD_1, t)
        col = tuple(int(c) for c in col) + (255,)
        for k in range(thick):
            d.point((x + sx * i, y + sy * k), col)
            d.point((x + sx * k, y + sy * i), col)
    # shadow beneath
    for i in range(length):
        d.point((x + sx * i, y + sy * thick), (20, 10, 4, 255))
        d.point((x + sx * thick, y + sy * i), (20, 10, 4, 255))
    # tip diamond
    cx, cy = x + sx * 1, y + sy * 1
    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        d.point((cx + sx * dx, cy + sy * dy), GOLD_4 + (255,))


def make_window():
    w = h = 96
    img = plate(w, h, 8, face=(hexc("#1b171d"), hexc("#0e0c10")), seed=11)
    d = ImageDraw.Draw(img)
    # title band
    tb = 30
    arr = np.asarray(img).astype(np.float32).copy()
    ty = np.arange(tb)[:, None].astype(np.float32)
    for i in range(3):
        c = lerp(hexc("#2f272c"), hexc("#120f12"), ty / tb)
        arr[:tb, 1:w - 1, i] = c[..., i if c.ndim == 3 else 0] if False else (hexc("#34292e")[i] + (hexc("#100d10")[i] - hexc("#34292e")[i]) * ty / tb)
    rng = np.random.RandomState(5)
    arr[:tb, 1:w - 1, :3] += rng.randn(tb, w - 2, 1) * 3
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    # re-do outline + bevel on the top band
    d.line([(1, 0), (w - 2, 0)], fill=BLACK + (255,))
    d.line([(1, 1), (w - 2, 1)], fill=IRON_5 + (255,))
    d.line([(1, tb - 1), (w - 2, tb - 1)], fill=BLACK + (255,))
    d.line([(1, tb), (w - 2, tb)], fill=BLOOD_2 + (255,))
    d.line([(1, tb + 1), (w - 2, tb + 1)], fill=BLOOD_0 + (255,))
    d.line([(1, 2), (w - 2, 2)], fill=hexc("#4a3f45") + (255,))
    # re-join side outlines
    d.line([(0, 1), (0, h - 2)], fill=BLACK + (255,))
    d.line([(w - 1, 1), (w - 1, h - 2)], fill=BLACK + (255,))
    # inner shadow in the body
    arr = np.asarray(img).astype(np.float32).copy()
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.minimum(np.minimum(xx, yy - tb), np.minimum(w - 1 - xx, h - 1 - yy)).astype(np.float32)
    inb = (yy > tb + 2) & (xx > 9) & (xx < w - 10) & (yy < h - 10)
    sh = np.clip(1 - dist / 16.0, 0, 1) * 0.55
    arr[..., :3] = np.where(inb[..., None], arr[..., :3] * (1 - sh[..., None]) + np.array([40, 4, 4], np.float32) * sh[..., None] * 0.35, arr[..., :3])
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    # iron corner reinforcements with gold bracket + rivet
    cs = 18
    for i, (x, y) in enumerate(((0, 0), (w - cs, 0), (0, h - cs), (w - cs, h - cs))):
        cp = plate(cs, cs, 3, face=(hexc("#3b3238"), hexc("#1c171b")), band=(IRON_5, IRON_3), seed=200 + i, groove=False, corner_cut=2)
        img.alpha_composite(cp, (x, y))
    for (x, y, sx, sy) in ((3, 3, 1, 1), (w - 4, 3, -1, 1), (3, h - 4, 1, -1), (w - 4, h - 4, -1, -1)):
        gold_bracket(img, x, y, sx, sy, 12, 2)
    for (x, y) in ((9, 9), (w - 10, 9), (9, h - 10), (w - 10, h - 10)):
        rivet(img, x, y, 2.5)
    return img


def make_button(state):
    w, h = 48, 24
    if state == "normal":
        img = plate(w, h, 3, face=(hexc("#2c2429"), hexc("#14100f")), band=(IRON_4, IRON_2), seed=21, etch=BLOOD_2)
    elif state == "hover":
        img = plate(w, h, 3, face=(hexc("#43302a"), hexc("#241512")), band=(GOLD_2, GOLD_0), seed=22, etch=BLOOD_4)
    elif state == "pressed":
        img = plate(w, h, 3, face=(hexc("#0d0a0b"), hexc("#1a1214")), band=(IRON_2, IRON_3), seed=23, inset=True, etch=BLOOD_1)
    else:
        img = plate(w, h, 3, face=(hexc("#1a181b"), hexc("#121013")), band=(IRON_2, IRON_1), seed=24, etch=IRON_2)
        a = np.asarray(img).astype(np.float32)
        a[..., :3] = a[..., :3] * 0.8
        img = Image.fromarray(a.astype(np.uint8), "RGBA")
    if state in ("normal", "hover"):
        # tiny corner studs
        for (x, y) in ((4, 4), (w - 5, 4), (4, h - 5), (w - 5, h - 5)):
            img.putpixel((x, y), (GOLD_2 if state == "hover" else IRON_5) + (255,))
    return img


def make_panel(kind):
    w = h = 32
    if kind == "panel":
        return plate(w, h, 3, face=(hexc("#1a161c"), hexc("#0f0d11")), band=(IRON_3, IRON_1), seed=31, etch=BLOOD_1)
    if kind == "dark":
        return plate(w, h, 2, face=(hexc("#0c0a0d"), hexc("#070608")), band=(IRON_2, IRON_1), seed=32, inset=True, etch=BLOOD_0)
    if kind == "highlight":
        return plate(w, h, 3, face=(hexc("#241917"), hexc("#150f0f")), band=(GOLD_1, GOLD_0), seed=33, etch=BLOOD_3)


def make_textedit(focus):
    w, h = 32, 22
    if focus:
        return plate(w, h, 2, face=(hexc("#0b0809"), hexc("#060405")), band=(GOLD_2, GOLD_0), seed=41, inset=True, etch=BLOOD_3, etch_inner=False)
    return plate(w, h, 2, face=(hexc("#0b0809"), hexc("#060405")), band=(IRON_3, IRON_1), seed=42, inset=True, etch=BLOOD_1, etch_inner=False)


def make_tab(state):
    w, h = 40, 24
    if state == "active":
        img = plate(w, h, 3, face=(hexc("#2a1b19"), hexc("#17100f")), band=(GOLD_2, GOLD_0), seed=51, etch=BLOOD_3)
    elif state == "hover":
        img = plate(w, h, 3, face=(hexc("#241d22"), hexc("#141014")), band=(IRON_5, IRON_3), seed=52, etch=BLOOD_2)
    else:
        img = plate(w, h, 3, face=(hexc("#171316"), hexc("#0c0a0c")), band=(IRON_3, IRON_1), seed=53, etch=BLOOD_0)
    return img


def make_progress_frame():
    w, h = 32, 16
    a = np.zeros((h, w, 4), np.uint8)
    img = Image.fromarray(a, "RGBA")
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=BLACK + (255,))
    d.rectangle([1, 1, w - 2, h - 2], outline=IRON_4 + (255,))
    d.rectangle([2, 2, w - 3, h - 3], outline=IRON_1 + (255,))
    d.line([(1, 1), (w - 2, 1)], fill=IRON_5 + (255,))
    d.line([(1, h - 2), (w - 2, h - 2)], fill=IRON_2 + (255,))
    # translucent dark track
    for y in range(3, h - 3):
        for x in range(3, w - 3):
            img.putpixel((x, y), (6, 4, 6, 85))
    for (x, y) in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        img.putpixel((x, y), (0, 0, 0, 0))
    return img


def make_slot():
    w = h = 34
    img = plate(w, h, 2, face=(hexc("#0a0809"), hexc("#141012")), band=(IRON_4, IRON_2), seed=61, inset=True, etch=BLOOD_1, etch_inner=True)
    return img


def make_scroll():
    out = {}
    # track
    t = plate(13, 32, 1, face=(hexc("#0b090c"), hexc("#070507")), band=(IRON_2, IRON_1), seed=71, inset=True, groove=False)
    out["scroll_track"] = t
    for st, (hi, lo, fa) in {"": (IRON_5, IRON_3, hexc("#3a2f34")), "_hover": (GOLD_3, GOLD_1, hexc("#4a3024")), "_pressed": (BLOOD_3, BLOOD_1, hexc("#2a1010"))}.items():
        s = plate(13, 17, 2, face=(fa, lerp(fa, (0, 0, 0), 0.45)), band=(hi, lo), seed=72, groove=False)
        out["scroll_slider" + st] = s
    for nm, up in (("up", True), ("down", False)):
        for st, (hi, lo, fa, ac) in {"": (IRON_4, IRON_2, hexc("#2a2227"), IRON_5), "_hover": (GOLD_2, GOLD_0, hexc("#3a2820"), GOLD_3), "_pressed": (IRON_2, IRON_3, hexc("#0e0a0b"), BLOOD_3)}.items():
            b = plate(13, 13, 2, face=(fa, lerp(fa, (0, 0, 0), 0.4)), band=(hi, lo), seed=73, groove=False, inset=(st == "_pressed"))
            d = ImageDraw.Draw(b)
            cx = 6
            if up:
                pts = [(cx, 4), (cx - 3, 8), (cx + 3, 8)]
            else:
                pts = [(cx, 8), (cx - 3, 4), (cx + 3, 4)]
            d.polygon(pts, fill=ac + (255,))
            out["scroll_%s%s" % (nm, st)] = b
    return out


def make_checkbox():
    # sheet 16x32: row0 unchecked, row1 checked
    sheet = Image.new("RGBA", (16, 32), (0, 0, 0, 0))
    for row, chk in enumerate((False, True)):
        b = plate(16, 16, 2, face=(hexc("#0c090b"), hexc("#050405")), band=(IRON_4, IRON_2), seed=81, inset=True, etch=BLOOD_1, etch_inner=False)
        d = ImageDraw.Draw(b)
        if chk:
            for i in range(5):
                col = lerp(GOLD_4, GOLD_2, i / 5)
                col = tuple(int(c) for c in col) + (255,)
            # engraved ember cross-mark (check)
            pts = [(4, 8), (7, 11), (12, 4)]
            d.line(pts, fill=(20, 8, 4, 255), width=3)
            d.line([(4, 7), (7, 10), (12, 3)], fill=GOLD_3 + (255,), width=2)
            d.line([(4, 7), (7, 10), (12, 3)], fill=GOLD_4 + (255,), width=1)
        sheet.alpha_composite(b, (0, row * 16))
    return sheet


def make_combobox():
    w, h = 40, 22
    img = plate(w, h, 2, face=(hexc("#1b1519"), hexc("#0e0b0d")), band=(IRON_4, IRON_2), seed=91, etch=BLOOD_1, etch_inner=False)
    d = ImageDraw.Draw(img)
    # arrow well on the right
    d.rectangle([w - 17, 2, w - 3, h - 3], fill=hexc("#120d10") + (255,))
    d.line([(w - 17, 2), (w - 17, h - 3)], fill=BLACK + (255,))
    d.line([(w - 16, 3), (w - 16, h - 4)], fill=IRON_3 + (255,))
    cx, cy = w - 10, h // 2
    d.polygon([(cx - 4, cy - 2), (cx + 4, cy - 2), (cx, cy + 3)], fill=BLACK + (255,))
    d.polygon([(cx - 4, cy - 3), (cx + 4, cy - 3), (cx, cy + 2)], fill=GOLD_2 + (255,))
    return img


def make_separator():
    w, h = 64, 8
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # center plain line (stretches), ornate ends
    for x in range(w):
        d.point((x, 3), BLACK + (255,))
        d.point((x, 4), hexc("#6a1010") + (255,))
        d.point((x, 5), BLACK + (200,))
    for x in range(0, 14):
        t = x / 14
        d.point((x, 4), tuple(int(c) for c in lerp(GOLD_3, BLOOD_2, t)) + (255,))
        d.point((x, 3), tuple(int(c) for c in lerp(GOLD_1, BLACK, t)) + (255,))
        d.point((w - 1 - x, 4), tuple(int(c) for c in lerp(GOLD_3, BLOOD_2, t)) + (255,))
        d.point((w - 1 - x, 3), tuple(int(c) for c in lerp(GOLD_1, BLACK, t)) + (255,))
    for cx in (3, w - 4):
        d.polygon([(cx, 0), (cx + 3, 4), (cx, 7), (cx - 3, 4)], fill=BLACK + (255,))
        d.polygon([(cx, 1), (cx + 2, 4), (cx, 6), (cx - 2, 4)], fill=GOLD_2 + (255,))
        d.point((cx - 1, 3), GOLD_4 + (255,))
    return img


def make_topbar_bg():
    w, h = 32, 44
    img = plate(w, h, 0, face=(hexc("#1a151a"), hexc("#0b090c")), seed=101, groove=False, corner_cut=0)
    arr = np.asarray(img).astype(np.float32).copy()
    # gentle top-down gradient & iron lower edge
    d = ImageDraw.Draw(img)
    for x in range(w):
        d.point((x, h - 1), BLACK + (255,))
        d.point((x, h - 2), IRON_4 + (255,))
        d.point((x, h - 3), IRON_2 + (255,))
        d.point((x, h - 4), BLOOD_1 + (255,))
        d.point((x, h - 5), BLOOD_2 + (255,))
        d.point((x, h - 6), BLACK + (255,))
        d.point((x, 0), BLACK + (255,))
    return img


def make_title_plate():
    """Small ornate banner for window headers / section titles (9-slice, border 12 sides)."""
    w, h = 64, 24
    img = plate(w, h, 2, face=(hexc("#2a1514"), hexc("#150909")), band=(GOLD_2, GOLD_0), seed=111, etch=BLOOD_3, corner_cut=2)
    for (x, y) in ((6, h // 2), (w - 7, h // 2)):
        rivet(img, x, y, 2.5, 1.1)
    return img


def make_hudbar():
    """Dark engraved icon backing plate for the top bar (button back)."""
    return plate(40, 40, 3, face=(hexc("#201a20"), hexc("#0c0a0d")), band=(IRON_4, IRON_2), seed=121)


def gen_frames():
    save(make_window(), "window.png")
    for s in ("normal", "hover", "pressed", "disabled"):
        save(make_button(s), "button_%s.png" % s)
    for k in ("panel", "dark", "highlight"):
        save(make_panel(k), "%s.png" % ("panel" if k == "panel" else "panel_" + k))
    save(make_textedit(False), "textedit.png")
    save(make_textedit(True), "textedit_focus.png")
    for s in ("normal", "hover", "active"):
        save(make_tab(s), "tab_%s.png" % s)
    save(make_progress_frame(), "progress_frame.png")
    save(make_slot(), "itemslot.png")
    for k, v in make_scroll().items():
        save(v, k + ".png")
    save(make_checkbox(), "checkbox.png")
    save(make_combobox(), "combobox.png")
    save(make_separator(), "separator.png")
    save(make_topbar_bg(), "topbar_bg.png")
    save(make_title_plate(), "title_plate.png")


# ---------------------------------------------------------------- icons
N = 256
U = N / 100.0


class Glyph:
    """Mask painter in a 0..100 coordinate space (255 = add metal, 0 = carve)."""

    def __init__(self):
        self.im = Image.new("L", (N, N), 0)
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def _p(pts):
        return [(x * U, y * U) for (x, y) in pts]

    def poly(self, pts, v=255):
        self.d.polygon(self._p(pts), fill=v)

    def smooth(self, pts, v=255, it=3):
        pts = list(pts)
        for _ in range(it):
            new = []
            for i in range(len(pts)):
                a, b = pts[i], pts[(i + 1) % len(pts)]
                new.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
                new.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
            pts = new
        self.poly(pts, v)

    def circ(self, cx, cy, r, v=255):
        self.d.ellipse([(cx - r) * U, (cy - r) * U, (cx + r) * U, (cy + r) * U], fill=v)

    def ell(self, cx, cy, rx, ry, v=255):
        self.d.ellipse([(cx - rx) * U, (cy - ry) * U, (cx + rx) * U, (cy + ry) * U], fill=v)

    def ring(self, cx, cy, r, w, v=255):
        self.d.ellipse([(cx - r) * U, (cy - r) * U, (cx + r) * U, (cy + r) * U], outline=v, width=int(w * U))

    def rect(self, x0, y0, x1, y1, v=255):
        self.d.rectangle([x0 * U, y0 * U, x1 * U, y1 * U], fill=v)

    def rrect(self, x0, y0, x1, y1, r, v=255):
        self.d.rounded_rectangle([x0 * U, y0 * U, x1 * U, y1 * U], radius=r * U, fill=v)

    def line(self, pts, w, v=255, caps=True):
        P = self._p(pts)
        self.d.line(P, fill=v, width=max(1, int(w * U)), joint="curve")
        if caps:
            r = w * U / 2
            for (x, y) in (P[0], P[-1]):
                self.d.ellipse([x - r, y - r, x + r, y + r], fill=v)

    def arc(self, cx, cy, r, a0, a1, w, v=255):
        self.d.arc([(cx - r) * U, (cy - r) * U, (cx + r) * U, (cy + r) * U], a0, a1, fill=v, width=max(1, int(w * U)))


def star_pts(cx, cy, ro, ri, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180.0 / n)
        r = ro if i % 2 == 0 else ri
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def sword(g, x1, y1, x2, y2):
    """Sword from hilt end (x1,y1) to tip (x2,y2)."""
    dx, dy = x2 - x1, y2 - y1
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    nx, ny = -uy, ux
    gx, gy = x1 + ux * L * 0.30, y1 + uy * L * 0.30
    g.line([(gx, gy), (x2 - ux * 3, y2 - uy * 3)], 7.5)
    g.poly([(x2, y2), (x2 - ux * 8 + nx * 3.7, y2 - uy * 8 + ny * 3.7), (x2 - ux * 8 - nx * 3.7, y2 - uy * 8 - ny * 3.7)])
    g.line([(gx + nx * 11, gy + ny * 11), (gx - nx * 11, gy - ny * 11)], 5.5)
    g.line([(x1 + ux * 3, y1 + uy * 3), (gx, gy)], 5)
    g.circ(x1, y1, 4.2)


def glyph_inventory(g):
    g.poly([(39, 29), (61, 29), (66, 41), (34, 41)])
    g.ell(50, 59, 25, 21)
    g.rrect(36, 24, 64, 33, 3)
    g.line([(34, 45), (66, 45)], 2.6, 0)
    g.rrect(41, 51, 59, 66, 3, 0)
    g.rrect(44, 54, 56, 63, 2)
    g.circ(50, 58, 2.2, 0)


def glyph_skills(g):
    sword(g, 22, 78, 78, 22)
    sword(g, 78, 78, 22, 22)


def glyph_battlelist(g):
    g.circ(50, 44, 24)
    g.rrect(36, 54, 64, 78, 6)
    g.circ(40, 46, 7, 0)
    g.circ(60, 46, 7, 0)
    g.poly([(50, 53), (45, 63), (55, 63)], 0)
    for x in (43.5, 50, 56.5):
        g.line([(x, 69), (x, 78)], 1.8, 0, caps=False)
    g.circ(40, 46, 2.4, 255)
    g.circ(60, 46, 2.4, 255)


def glyph_vip(g):
    g.poly([(32, 30), (68, 30), (80, 46), (50, 80), (20, 46)])
    g.line([(20, 46), (80, 46)], 2.2, 0, caps=False)
    g.line([(32, 30), (40, 46), (50, 80), (60, 46), (68, 30)], 2.2, 0, caps=False)
    g.line([(40, 46), (50, 30), (60, 46)], 2.2, 0, caps=False)


def glyph_spells(g):
    g.smooth([(50, 82), (33, 72), (27, 58), (33, 46), (40, 38), (42, 48), (46, 38), (46, 26), (54, 17), (55, 30), (64, 40), (71, 52), (69, 67), (61, 77)], it=3)
    g.smooth([(50, 76), (42, 70), (40, 62), (46, 54), (50, 58), (56, 54), (60, 62), (58, 70)], v=0, it=3)
    g.smooth([(50, 73), (46, 69), (47, 64), (50, 62), (53, 65), (54, 69)], v=255, it=3)


def glyph_quests(g):
    g.rect(31, 27, 69, 73)
    g.rrect(26, 20, 74, 31, 5)
    g.rrect(26, 69, 74, 80, 5)
    g.line([(26, 26), (74, 26)], 1.4, 0, caps=False)
    g.line([(26, 74), (74, 74)], 1.4, 0, caps=False)
    g.rrect(46.5, 36, 53.5, 58, 3, 0)
    g.circ(50, 65, 4.2, 0)


def glyph_market(g):
    g.line([(50, 24), (50, 74)], 5)
    g.rrect(32, 72, 68, 80, 3)
    g.line([(24, 34), (76, 34)], 5)
    g.circ(50, 24, 6)
    for cx in (26, 74):
        g.line([(cx, 34), (cx - 11, 56)], 2.4, caps=False)
        g.line([(cx, 34), (cx + 11, 56)], 2.4, caps=False)
        g.poly([(cx - 15, 55), (cx + 15, 55), (cx + 10, 66), (cx - 10, 66)])
        g.circ(cx, 34, 3.5)
    g.circ(50, 24, 2.5, 0)


def glyph_bank(g):
    g.poly([(20, 40), (50, 20), (80, 40)])
    g.rect(24, 42, 76, 47)
    for x in (28, 41, 54, 67):
        g.rrect(x, 49, x + 6, 70, 1.5)
    g.rrect(20, 72, 80, 80, 2)
    g.circ(50, 33, 4, 0)


def glyph_stash(g):
    g.rrect(22, 46, 78, 78, 4)
    g.smooth([(22, 46), (24, 36), (36, 28), (64, 28), (76, 36), (78, 46)], it=2)
    g.line([(22, 46), (78, 46)], 2.2, 0, caps=False)
    g.line([(34, 46), (34, 78)], 2.2, 0, caps=False)
    g.line([(66, 46), (66, 78)], 2.2, 0, caps=False)
    g.rrect(44, 42, 56, 60, 3, 0)
    g.rrect(46, 44, 54, 58, 2)
    g.circ(50, 50, 2, 0)
    g.rect(49, 50, 51, 55, 0)


def glyph_autoloot(g):
    g.poly([(40, 50), (60, 50), (66, 60), (34, 60)])
    g.ell(50, 69, 24, 15)
    g.rrect(36, 46, 64, 53, 3)
    g.line([(35, 57), (65, 57)], 2.2, 0, caps=False)
    g.circ(50, 25, 10.5)
    g.circ(50, 25, 6, 0)
    g.rrect(48.2, 21, 51.8, 29, 1, 255)
    g.poly([(42, 34), (58, 34), (50, 42)])


def glyph_daily(g):
    g.rrect(24, 26, 76, 78, 5)
    g.rect(24, 26, 76, 40, 255)
    g.rrect(33, 17, 40, 32, 2.5)
    g.rrect(60, 17, 67, 32, 2.5)
    g.line([(24, 40), (76, 40)], 2.2, 0, caps=False)
    g.rrect(30, 45, 70, 73, 2, 0)
    g.poly(star_pts(50, 60, 12, 5.3))


def glyph_battlepass(g):
    g.poly([(30, 22), (70, 22), (70, 80), (50, 66), (30, 80)])
    g.line([(37, 36), (50, 46), (63, 36)], 4.4, 0)
    g.line([(37, 48), (50, 58), (63, 48)], 4.4, 0)
    g.line([(30, 28), (70, 28)], 2, 0, caps=False)


def glyph_passivetree(g):
    nodes = [(50, 24), (28, 48), (72, 48), (50, 52), (36, 76), (64, 76)]
    for a, b in ((0, 3), (1, 3), (2, 3), (1, 4), (2, 5), (3, 4), (3, 5)):
        g.line([nodes[a], nodes[b]], 4)
    for i, (x, y) in enumerate(nodes):
        g.circ(x, y, 8 if i == 0 else 6.5)
    g.circ(50, 24, 3.2, 0)
    g.circ(50, 24, 1.4, 255)


def glyph_dungeons(g):
    g.circ(50, 44, 25)
    g.rect(25, 44, 75, 80)
    g.circ(50, 46, 15, 0)
    g.rect(35, 46, 65, 80, 0)
    for x in (41, 50, 59):
        g.line([(x, 38), (x, 76)], 3.2, caps=False)
    g.line([(36, 56), (64, 56)], 3.2, caps=False)
    g.line([(36, 68), (64, 68)], 3.2, caps=False)
    for x in (41, 50, 59):
        g.poly([(x - 2, 76), (x + 2, 76), (x, 81)])
    g.poly([(46, 22), (54, 22), (50, 29)], 0)


def glyph_events(g):
    g.line([(30, 20), (30, 82)], 5)
    g.smooth([(33, 24), (74, 30), (62, 40), (74, 52), (33, 48)], it=2)
    g.poly(star_pts(52, 38, 7.5, 3.2), 0)
    g.rrect(24, 76, 36, 82, 2)


def glyph_infinitytower(g):
    g.poly([(38, 36), (62, 36), (67, 80), (33, 80)])
    for x in (32, 44.5, 57):
        g.rect(x, 24, x + 11, 38)
    g.rect(32, 36, 68, 41)
    g.rrect(46, 44, 54, 54, 3.5, 0)
    g.ring(43.5, 66, 5.5, 2.4, 0)
    g.ring(56.5, 66, 5.5, 2.4, 0)


def glyph_minimap(g):
    g.circ(50, 50, 30)
    g.circ(50, 50, 24, 0)
    for a in (0, 90, 180, 270):
        r = math.radians(a)
        g.line([(50 + 24 * math.cos(r), 50 + 24 * math.sin(r)), (50 + 30 * math.cos(r), 50 + 30 * math.sin(r))], 4, 255, caps=False)
    g.poly([(50, 26), (59, 50), (50, 74), (41, 50)])
    g.line([(41, 50), (59, 50)], 2, 0, caps=False)
    g.circ(50, 50, 3, 0)


def glyph_options(g):
    for i in range(8):
        a = math.radians(i * 45)
        c, s = math.cos(a), math.sin(a)
        cx, cy = 50 + 22 * c, 50 + 22 * s
        nx, ny = -s, c
        pts = [(cx + c * 8 + nx * 6.5, cy + s * 8 + ny * 6.5), (cx + c * 8 - nx * 6.5, cy + s * 8 - ny * 6.5),
               (cx - c * 8 - nx * 8, cy - s * 8 - ny * 8), (cx - c * 8 + nx * 8, cy - s * 8 + ny * 8)]
        g.poly(pts)
    g.circ(50, 50, 24)
    g.circ(50, 50, 10, 0)
    g.ring(50, 50, 17, 1.6, 0)


def glyph_notifications(g):
    g.circ(50, 22, 4)
    g.circ(50, 42, 19)
    g.poly([(31, 42), (69, 42), (70, 58), (78, 68), (22, 68), (30, 58)])
    g.rrect(22, 66, 78, 72, 3)
    g.ell(50, 78, 6.5, 5)


def glyph_help(g):
    g.arc(50, 38, 15, 150, 40, 9)
    g.line([(63, 46), (51, 57), (50, 62)], 9)
    g.circ(50, 77, 5.5)


def glyph_logout(g):
    g.line([(52, 24), (30, 24), (30, 76), (52, 76)], 6, caps=False)
    g.rect(27, 22, 33, 78)
    g.line([(42, 50), (70, 50)], 6.5)
    g.poly([(64, 36), (82, 50), (64, 64)])


def glyph_admin(g):
    g.poly([(24, 24), (50, 18), (76, 24), (76, 52), (50, 82), (24, 52)])
    g.poly([(32, 59), (32, 40), (41, 49), (50, 34), (59, 49), (68, 40), (68, 59)], 0)
    g.rect(32, 62, 68, 66, 0)
    g.circ(32, 38, 2.4, 0)
    g.circ(50, 32, 2.4, 0)
    g.circ(68, 38, 2.4, 0)


def glyph_ranking(g):
    g.poly([(33, 24), (67, 24), (65, 46), (56, 58), (44, 58), (35, 46)])
    g.ring(30, 38, 8, 3.6)
    g.ring(70, 38, 8, 3.6)
    g.rect(44, 56, 56, 68)
    g.rrect(34, 68, 66, 78, 2.5)
    g.poly(star_pts(50, 40, 8, 3.6), 0)


ICONS = [
    ("inventory", glyph_inventory, "Inventory"), ("skills", glyph_skills, "Skills"),
    ("battlelist", glyph_battlelist, "Battle List"), ("vip", glyph_vip, "VIP"),
    ("spells", glyph_spells, "Spells"), ("quests", glyph_quests, "Quests"),
    ("market", glyph_market, "Market / Store"), ("bank", glyph_bank, "Bank"),
    ("stash", glyph_stash, "Stash"), ("autoloot", glyph_autoloot, "Auto Loot"),
    ("daily", glyph_daily, "Daily Reward"), ("battlepass", glyph_battlepass, "Battle Pass"),
    ("passivetree", glyph_passivetree, "Passive Tree"), ("dungeons", glyph_dungeons, "Dungeons"),
    ("events", glyph_events, "Events"), ("infinitytower", glyph_infinitytower, "Infinity Tower"),
    ("minimap", glyph_minimap, "Minimap"), ("options", glyph_options, "Options"),
    ("notifications", glyph_notifications, "Notifications"), ("help", glyph_help, "Help"),
    ("logout", glyph_logout, "Logout"), ("admin", glyph_admin, "Admin"),
    ("ranking", glyph_ranking, "Ranking"),
]


def rr_mask(inset, radius):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).rounded_rectangle([inset, inset, N - 1 - inset, N - 1 - inset], radius=radius, fill=255)
    return m


_PLATE_CACHE = {}


def badge_plate(hover):
    if hover in _PLATE_CACHE:
        return _PLATE_CACHE[hover].copy()
    ins, rad = 16, 46
    M = rr_mask(ins, rad)
    arr = np.zeros((N, N, 4), np.float32)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    t = (xx * 0.4 + yy * 0.6) / N
    rng = np.random.RandomState(3)
    n = fbm(N, N, 28, 4, 9) * 22 - 11 + rng.randn(N, N).astype(np.float32) * 3
    top, bot = (IRON_5, IRON_2) if hover else (IRON_4, IRON_1)
    for i in range(3):
        arr[..., i] = top[i] + (bot[i] - top[i]) * t + n
    arr[..., 3] = 255
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)

    def rrim(i, col, w=3):
        d.rounded_rectangle([ins + i, ins + i, N - 1 - ins - i, N - 1 - ins - i], radius=rad - i, outline=col, width=w)
    rrim(0, BLACK + (255,), 5)
    rrim(5, (hexc("#a89ba0") if not hover else GOLD_3) + (255,), 3)
    ia = np.zeros((N, N, 4), np.float32)
    c0, c1 = (hexc("#241513"), hexc("#07050a")) if not hover else (hexc("#43211a"), hexc("#12070a"))
    r = np.sqrt((xx - N / 2) ** 2 + (yy - N / 2 - 10) ** 2) / (N * 0.62)
    r = np.clip(r, 0, 1)
    for i in range(3):
        ia[..., i] = c0[i] + (c1[i] - c0[i]) * r
    ia[..., 3] = 255
    inner = Image.fromarray(ia.astype(np.uint8), "RGBA")
    img.paste(inner, (0, 0), rr_mask(ins + 22, rad - 20))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([ins + 14, ins + 14, N - 1 - ins - 14, N - 1 - ins - 14], radius=rad - 14, outline=(BLOOD_3 if hover else BLOOD_2) + (255,), width=3)
    d.rounded_rectangle([ins + 19, ins + 19, N - 1 - ins - 19, N - 1 - ins - 19], radius=rad - 19, outline=BLACK + (255,), width=3)
    d.rounded_rectangle([ins + 11, ins + 11, N - 1 - ins - 11, N - 1 - ins - 11], radius=rad - 11, outline=BLACK + (255,), width=3)
    a = np.asarray(img).copy()
    a[..., 3] = np.minimum(a[..., 3], np.asarray(M))
    img = Image.fromarray(a, "RGBA")
    _PLATE_CACHE[hover] = img
    return img.copy()


def shift(m, dx, dy):
    return ImageChops.offset(m, dx, dy)


def alpha_layer(color, a):
    lay = Image.new("RGBA", (N, N), tuple(color) + (0,))
    lay.putalpha(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)))
    return lay


def render_icon(glyph_fn, hover):
    img = badge_plate(hover)
    g = Glyph()
    glyph_fn(g)
    M = g.im.filter(ImageFilter.GaussianBlur(0.9))
    yy = np.mgrid[0:N, 0:N][0].astype(np.float32)
    tn = np.clip((yy - 40) / 176.0, 0, 1)
    rm = np.asarray(rr_mask(16 + 24, 24)).astype(np.float32) / 255
    # glow behind the glyph
    glow_col = (255, 120, 30) if hover else (150, 22, 14)
    ga = np.asarray(blur(M, 11 if hover else 9)).astype(np.float32) / 255.0 * (0.85 if hover else 0.40)
    img.alpha_composite(alpha_layer(glow_col, ga * rm))
    # drop shadow
    sa = np.asarray(blur(shift(M, 4, 5), 3)).astype(np.float32) / 255 * 0.9
    img.alpha_composite(alpha_layer((0, 0, 0), sa))
    # dark outline
    ola = np.asarray(M.filter(ImageFilter.MaxFilter(7))).astype(np.float32) / 255
    img.alpha_composite(alpha_layer((6, 3, 3), ola * 0.92))
    # gold body
    top, bot = (GOLD_4, GOLD_2) if hover else (GOLD_3, GOLD_1)
    body = np.zeros((N, N, 3), np.float32)
    for i in range(3):
        body[..., i] = top[i] + (bot[i] - top[i]) * tn
    bl = np.clip((tn - 0.55) * 1.6, 0, 1) * (0.25 if hover else 0.42)
    for i in range(3):
        body[..., i] = body[..., i] * (1 - bl) + BLOOD_3[i] * bl
    pat = fbm(N, N, 9, 4, 17)
    body *= (0.78 + 0.4 * pat)[..., None]
    ma = np.asarray(M).astype(np.float32) / 255
    hi = np.clip(ma - np.asarray(shift(M, 4, 4)).astype(np.float32) / 255, 0, 1)
    lo = np.clip(ma - np.asarray(shift(M, -4, -4)).astype(np.float32) / 255, 0, 1)
    hi = np.asarray(blur(Image.fromarray((hi * 255).astype(np.uint8)), 1.2)).astype(np.float32) / 255
    lo = np.asarray(blur(Image.fromarray((lo * 255).astype(np.uint8)), 1.2)).astype(np.float32) / 255
    body = body + hi[..., None] * (np.array(GOLD_4, np.float32) - body) * 0.9
    body = body * (1 - lo[..., None] * 0.65)
    layer = Image.fromarray(np.clip(body, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    layer.putalpha(M)
    img.alpha_composite(layer)
    if hover:
        pm = np.asarray(rr_mask(16, 46)).astype(np.float32) / 255
        wide = np.asarray(blur(rr_mask(19, 46), 7)).astype(np.float32) / 255.0
        wide = np.clip(wide * (1 - pm), 0, 1) * 1.25
        under = alpha_layer((255, 130, 40), wide)
        under.alpha_composite(img)
        img = under
    return img


def gen_icons():
    for name, fn, _label in ICONS:
        for hover in (False, True):
            big = render_icon(fn, hover)
            suf = "_hover" if hover else ""
            save(big.resize((64, 64), Image.LANCZOS), "topbutton_%s%s.png" % (name, suf))
            save(big.resize((32, 32), Image.LANCZOS), "small/topbutton_%s%s.png" % (name, suf))


# ---------------------------------------------------------------- background
BW, BH = 1920, 1080


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def mix(base, color, m):
    """base (h,w,3) float, color (3,) or (h,w,3), m (h,w) in 0..1."""
    return base * (1 - m[..., None]) + np.asarray(color, np.float32) * m[..., None]


def mask_arr(img):
    return np.asarray(img).astype(np.float32) / 255.0


def ridge_line(w, base, amp, scale, seed, octaves=5):
    """1D fractal ridge (array of y values)."""
    rng = np.random.RandomState(seed)
    out = np.zeros(w, np.float32)
    a, tot = 1.0, 0
    for o in range(octaves):
        n = max(3, int(w / scale * 2 ** o) + 3)
        g = rng.rand(n).astype(np.float32)
        xs = np.linspace(0, n - 1.001, w)
        i0 = xs.astype(int)
        f = xs - i0
        f = f * f * (3 - 2 * f)
        out += (g[i0] * (1 - f) + g[i0 + 1] * f) * a
        tot += a
        a *= 0.5
    out /= tot
    return base - (out - 0.5) * 2 * amp


def pointed_arch(x0, w, ys, n=14):
    pts = []
    for i in range(n + 1):
        a = math.radians(180 - 60 * i / n)
        pts.append((x0 + w + w * math.cos(a), ys - w * math.sin(a)))
    for i in range(n + 1):
        a = math.radians(60 - 60 * i / n)
        pts.append((x0 + w * math.cos(a), ys - w * math.sin(a)))
    # right arc ends at angle 0 -> (x0+w, ys); left start at angle 180 -> (x0, ys)
    return pts


def spire(d, cx, base, hw, h, fill=255, concave=0.25):
    pts = [(cx - hw, base)]
    n = 10
    for i in range(n + 1):
        t = i / n
        pts.append((cx - hw * (1 - t) ** (1 + concave) , base - h * t))
    for i in range(n + 1):
        t = 1 - i / n
        pts.append((cx + hw * (1 - t) ** (1 + concave), base - h * t))
    pts.append((cx + hw, base))
    d.polygon(pts, fill=fill)
    # little crockets (thorns) on both flanks
    for k in range(1, 6):
        t = k / 6.5
        y = base - h * t
        x = hw * (1 - t) ** (1 + concave)
        s = hw * 0.22 * (1 - t) + 2
        d.polygon([(cx - x, y), (cx - x - s * 1.4, y + s * 0.2), (cx - x + 1, y + s * 1.6)], fill=fill)
        d.polygon([(cx + x, y), (cx + x + s * 1.4, y + s * 0.2), (cx + x - 1, y + s * 1.6)], fill=fill)
    # finial cross
    d.rectangle([cx - 1.5, base - h - 26, cx + 1.5, base - h + 2], fill=fill)
    d.rectangle([cx - 8, base - h - 18, cx + 8, base - h - 14], fill=fill)


def cathedral(cx, base, s, fill_img, glow_img, rng):
    """Draws a gothic cathedral silhouette into fill_img (L) and lit windows into glow_img (L)."""
    d = ImageDraw.Draw(fill_img)
    g = ImageDraw.Draw(glow_img)
    S = lambda v: v * s
    # nave
    nave_h = S(210)
    d.rectangle([cx - S(330), base - nave_h, cx + S(330), base], fill=255)
    # roof ridge with serrated edge
    d.polygon([(cx - S(340), base - nave_h), (cx - S(120), base - nave_h - S(60)), (cx + S(120), base - nave_h - S(60)), (cx + S(340), base - nave_h)], fill=255)
    # battlement thorns along nave
    for i in range(-14, 15):
        x = cx + i * S(23)
        d.polygon([(x - S(7), base - nave_h), (x, base - nave_h - S(26) - (i % 3) * S(8)), (x + S(7), base - nave_h)], fill=255)
    # central facade tower
    tw = S(95)
    d.rectangle([cx - tw, base - S(420), cx + tw, base], fill=255)
    spire(d, cx, base - S(420), tw * 0.92, S(230), concave=0.35)
    for sx in (-1, 1):
        d.rectangle([cx + sx * tw - S(14), base - S(470), cx + sx * tw + S(14), base - S(400)], fill=255)
        spire(d, cx + sx * tw, base - S(465), S(14), S(70))
    # side towers
    for sx in (-1, 1):
        x = cx + sx * S(215)
        d.rectangle([x - S(48), base - S(330), x + S(48), base], fill=255)
        spire(d, x, base - S(330), S(46), S(165), concave=0.3)
        d.rectangle([x - S(55), base - S(335), x + S(55), base - S(318)], fill=255)
    # outer pinnacle towers
    for sx in (-1, 1):
        x = cx + sx * S(340)
        d.rectangle([x - S(24), base - S(290), x + S(24), base], fill=255)
        spire(d, x, base - S(290), S(24), S(120))
    # flying buttresses
    for sx in (-1, 1):
        for k, off in enumerate((95, 150, 270)):
            px = cx + sx * S(off + 125 * (1 if k == 2 else 0) + 20)
        for k in range(3):
            x_in = cx + sx * S(120 + k * 70)
            x_out = cx + sx * S(445 + k * 5) if False else cx + sx * S(395 + k * 60)
            # pier
            pw = S(14)
            d.rectangle([x_out - pw, base - S(240 - k * 10), x_out + pw, base], fill=255)
            spire(d, x_out, base - S(240 - k * 10), pw, S(70))
            # arc
            pts_o = []
            pts_i = []
            for t in np.linspace(0, 1, 16):
                x = x_in + (x_out - x_in) * t
                y = base - nave_h + S(18) - math.sin(t * math.pi * 0.5) * 0 + (S(70) * (1 - math.cos(t * math.pi / 2)) if True else 0) - S(0)
                y = base - nave_h - S(8) + S(75) * t * t
                pts_o.append((x, y))
                pts_i.append((x, y + S(16)))
            d.polygon(pts_o + pts_i[::-1], fill=255)
    # ground buttress wall chunks
    d.rectangle([cx - S(470), base - S(70), cx + S(470), base], fill=255)
    # ------------------------------------------------- lit windows
    # nave lancets
    for i in range(-7, 8):
        if abs(i) < 2 and False:
            continue
        x0 = cx + i * S(40) - S(9)
        if abs(i * 40) < 110 or abs(i * 40) > 300:
            continue
        pts = pointed_arch(x0, S(18), base - S(95), 8)
        g.polygon(pts + [(x0 + S(18), base - S(40)), (x0, base - S(40))], fill=int(rng.randint(120, 255)))
    # tall tower lancets
    for sx in (-1, 1):
        x = cx + sx * S(215)
        for yy_, hh in ((base - S(190), S(80)), (base - S(280), S(55))):
            pts = pointed_arch(x - S(10), S(20), yy_, 8)
            g.polygon(pts + [(x + S(10), yy_ + hh), (x - S(10), yy_ + hh)], fill=230)
    # facade: rose window + big lancet
    rcx, rcy, rr = cx, base - S(300), S(42)
    g.ellipse([rcx - rr, rcy - rr, rcx + rr, rcy + rr], fill=255)
    pts = pointed_arch(cx - S(22), S(44), base - S(110), 10)
    g.polygon(pts + [(cx + S(22), base - S(20)), (cx - S(22), base - S(20))], fill=200)
    for sx in (-1, 1):
        pts = pointed_arch(cx + sx * S(62) - S(8), S(16), base - S(250), 6)
        g.polygon(pts + [(cx + sx * S(62) + S(8), base - S(190)), (cx + sx * S(62) - S(8), base - S(190))], fill=170)
    # carve rose window tracery (spokes / ring) from the glow so it reads as stone
    for a in range(0, 360, 30):
        r_ = math.radians(a)
        g.line([(rcx, rcy), (rcx + rr * math.cos(r_), rcy + rr * math.sin(r_))], fill=0, width=max(2, int(S(3))))
    g.ellipse([rcx - rr * 0.32, rcy - rr * 0.32, rcx + rr * 0.32, rcy + rr * 0.32], fill=0)
    g.ellipse([rcx - rr * 0.18, rcy - rr * 0.18, rcx + rr * 0.18, rcy + rr * 0.18], fill=255)
    # lancet mullions
    g.line([(cx, base - S(190)), (cx, base - S(20))], fill=0, width=max(2, int(S(3))))
    # main door glow
    pts = pointed_arch(cx - S(16), S(32), base - S(20) if False else base - S(2), 10)


def dead_tree(d, x, y, ang, length, width, depth, rng):
    ex = x + math.cos(ang) * length
    ey = y + math.sin(ang) * length
    d.line([(x, y), (ex, ey)], fill=255, width=max(1, int(width)))
    d.ellipse([ex - width / 2, ey - width / 2, ex + width / 2, ey + width / 2], fill=255)
    if depth <= 0 or length < 6:
        return
    n = 2 if rng.rand() < 0.7 else 3
    for i in range(n):
        da = rng.uniform(-0.75, 0.75) + (i - (n - 1) / 2) * 0.25
        dead_tree(d, ex, ey, ang + da, length * rng.uniform(0.62, 0.8), width * 0.68, depth - 1, rng)


def cracks_mask(w, h, y0, rng, count=26):
    big = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(big)

    def walk(x, y, ang, steps, wd, depth):
        for i in range(steps):
            persp = 0.35 + 0.65 * (y - y0) / (h - y0)
            step = rng.uniform(8, 18) * (0.5 + persp)
            ang += rng.normal(0, 0.32)
            nx = x + math.cos(ang) * step
            ny = y + math.sin(ang) * step * 0.55
            ww = max(1, wd * persp * (1 - i / (steps * 1.1)))
            d.line([(x, y), (nx, ny)], fill=255, width=int(ww + 0.5))
            x, y = nx, ny
            if y > h or y < y0 or x < -50 or x > w + 50:
                break
            if depth < 3 and rng.rand() < 0.04:
                walk(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.2), int(steps * 0.5), wd * 0.7, depth + 1)

    for i in range(count):
        y = rng.uniform(y0 + 20, h - 10)
        x = rng.uniform(0, w)
        walk(x, y, rng.uniform(-0.5, 0.5) + (math.pi if rng.rand() < 0.5 else 0), rng.randint(14, 34), rng.uniform(2, 4.5), 0)
    return big


def bg_sky(rng):
    yy = np.linspace(0, 1, BH, dtype=np.float32)[:, None]
    stops = [(0.0, (0.005, 0.003, 0.007)), (0.35, (0.03, 0.007, 0.014)), (0.56, (0.11, 0.02, 0.026)), (0.73, (0.40, 0.075, 0.04)), (1.0, (0.10, 0.02, 0.018))]
    sky = np.zeros((BH, BW, 3), np.float32)
    for i in range(3):
        col = np.interp(yy[:, 0], [s[0] for s in stops], [s[1][i] for s in stops])
        sky[..., i] = col[:, None]
    # clouds: anisotropic noise
    base = fbm(BH // 2, BW // 4, 30, 6, 4)
    cl = np.asarray(Image.fromarray(base.astype(np.float32), "F").resize((BW, BH), Image.BICUBIC))
    cl2 = fbm(BH, BW, 120, 5, 8)
    clouds = np.clip((cl * 0.65 + cl2 * 0.35 - 0.38) * 2.6, 0, 1)
    vert = smoothstep(0.0, 0.25, yy) * (1 - smoothstep(0.62, 0.9, yy))
    sky = sky * (1 - 0.0) + clouds[..., None] * np.array([0.30, 0.055, 0.05], np.float32) * vert[..., None] * 0.55
    # blood moon
    mcx, mcy, mr = 1335, 295, 150
    Y, X = np.mgrid[0:BH, 0:BW].astype(np.float32)
    dist = np.sqrt((X - mcx) ** 2 + (Y - mcy) ** 2)
    glow = np.exp(-(dist / (mr * 2.8)) ** 1.4) * 0.55 + np.exp(-(dist / (mr * 1.3)) ** 2) * 0.45
    sky += glow[..., None] * np.array([0.55, 0.06, 0.035], np.float32) * 0.95
    disc = np.clip((mr - dist) / 2.2, 0, 1)
    tex = fbm(BH, BW, 60, 5, 21)
    maria = fbm(BH, BW, 140, 3, 33)
    limb = np.clip(dist / mr, 0, 1)
    shade = 1.0 - limb ** 3 * 0.55
    dark = np.clip((maria - 0.45) * 3.0, 0, 1) * 0.6 + (tex - 0.5) * 0.5
    lit = np.array([0.80, 0.11, 0.045], np.float32)
    dk = np.array([0.25, 0.025, 0.02], np.float32)
    mc = lit[None, None] * (1 - np.clip(dark, 0, 1)[..., None]) + dk[None, None] * np.clip(dark, 0, 1)[..., None]
    # hot core toward upper-left
    hot = np.exp(-(((X - (mcx - 45)) ** 2 + (Y - (mcy - 50)) ** 2) / (mr * 0.9) ** 2))
    mc += hot[..., None] * np.array([0.25, 0.18, 0.05], np.float32)
    # craters
    for _ in range(40):
        a = rng.uniform(0, 2 * math.pi)
        r = mr * 0.85 * math.sqrt(rng.rand())
        cx_, cy_ = mcx + r * math.cos(a), mcy + r * math.sin(a)
        cr = rng.uniform(4, 16)
        dd = np.sqrt((X - cx_) ** 2 + (Y - cy_) ** 2)
        ring = np.exp(-((dd - cr) / 2.0) ** 2) * 0.22
        mc -= ring[..., None] * np.array([0.7, 0.1, 0.05], np.float32)
        mc += (np.exp(-(((X - cx_ + 2) ** 2 + (Y - cy_ + 2) ** 2) / (cr * 0.5) ** 2)) * 0.06)[..., None] * 0.0
    sky = mix(sky, mc * shade[..., None] * 1.5, disc)
    hz = np.exp(-(((X - 1120) / 820) ** 2 + ((Y - 770) / 170) ** 2))
    sky += hz[..., None] * np.array([0.42, 0.075, 0.03], np.float32)
    # thin clouds drifting across the moon
    streak = fbm(BH // 3, BW // 6, 18, 5, 55)
    streak = np.asarray(Image.fromarray(streak, "F").resize((BW, BH), Image.BICUBIC))
    cm = np.clip((streak - 0.52) * 4.0, 0, 1) * np.exp(-((Y - mcy) / (mr * 1.5)) ** 2) * 0.8
    sky = mix(sky, np.array([0.045, 0.01, 0.015], np.float32), cm * np.exp(-(dist / (mr * 2.2)) ** 2))
    # sparse dim stars
    for _ in range(140):
        x, y = rng.randint(0, BW), int(abs(rng.normal(0, 0.18)) * BH)
        if y < BH * 0.4 and dist[y, x] > mr * 1.4:
            sky[y, x] += rng.uniform(0.1, 0.5) * np.array([1.0, 0.7, 0.6], np.float32) * (1 - cl[y, x])
    return np.clip(sky, 0, None), (mcx, mcy, mr), dist


def silhouette_layer(img, mask_img, top_col, base_col, base_y, span, moon_rim=0.0, rim_col=(0.8, 0.16, 0.07)):
    M = mask_arr(mask_img)
    Y = np.arange(BH, dtype=np.float32)[:, None]
    t = np.clip((Y - (base_y - span)) / span, 0, 1)
    col = np.zeros((BH, BW, 3), np.float32)
    for i in range(3):
        col[..., i] = top_col[i] + (base_col[i] - top_col[i]) * t
    out = mix(img, col, M)
    if moon_rim > 0:
        sh = np.asarray(ImageChops.offset(mask_img, -3, 1)).astype(np.float32) / 255
        rim = np.clip(M - sh, 0, 1)
        rim = np.asarray(blur(Image.fromarray((rim * 255).astype(np.uint8)), 1.3)).astype(np.float32) / 255
        out = out + rim[..., None] * np.array(rim_col, np.float32) * moon_rim
    return out


def fog_band(img, y_center, thick, color, strength, seed, scale=170, wind=3.5):
    n = fbm(BH // 2, BW // int(wind), scale / 2, 6, seed)
    n = np.asarray(Image.fromarray(n, "F").resize((BW, BH), Image.BICUBIC))
    n2 = fbm(BH, BW, scale, 4, seed + 1)
    dens = np.clip((n * 0.6 + n2 * 0.4 - 0.30) * 2.2, 0, 1)
    Y = np.arange(BH, dtype=np.float32)[:, None]
    prof = np.exp(-((Y - y_center) / thick) ** 2)
    m = np.clip(dens * prof * strength, 0, 1)
    return img + m[..., None] * np.array(color, np.float32) * 0.55


def make_background():
    rng = np.random.RandomState(1337)
    img, (mcx, mcy, mr), mdist = bg_sky(rng)
    print("sky done")
    Y = np.arange(BH, dtype=np.float32)[:, None]
    # ---- L0 far mountains
    xs = np.arange(BW)
    ridge0 = ridge_line(BW, 640, 85, 380, 5)
    m0 = Image.new("L", (BW, BH), 0)
    ImageDraw.Draw(m0).polygon([(0, BH)] + [(int(x), float(ridge0[x])) for x in xs[::4]] + [(BW, BH)], fill=255)
    img = silhouette_layer(img, m0, (0.075, 0.015, 0.025), (0.22, 0.045, 0.045), 640, 160, 0.3)
    img = fog_band(img, 690, 70, (0.38, 0.07, 0.05), 0.55, 61)
    # ---- L1 far ruins/towers
    m1 = Image.new("L", (BW, BH), 0)
    d1 = ImageDraw.Draw(m1)
    ridge1 = ridge_line(BW, 735, 40, 260, 9)
    d1.polygon([(0, BH)] + [(int(x), float(ridge1[x])) for x in xs[::4]] + [(BW, BH)], fill=255)
    for x, h, w in ((90, 250, 36), (210, 150, 26), (1700, 230, 34), (1810, 160, 24), (1560, 120, 20), (700, 110, 20)):
        yb = ridge1[x] + 20
        d1.rectangle([x - w, yb - h, x + w, yb], fill=255)
        spire(d1, x, yb - h, w * 0.9, h * 0.55)
        d1.polygon(pointed_arch(x - w * 0.35, w * 0.7, yb - h * 0.35, 8), fill=0)
    img = silhouette_layer(img, m1, (0.05, 0.01, 0.02), (0.15, 0.03, 0.035), 740, 150, 0.35)
    img = fog_band(img, 760, 60, (0.33, 0.06, 0.045), 0.5, 71)
    # ---- cathedral
    mc = Image.new("L", (BW, BH), 0)
    gw = Image.new("L", (BW, BH), 0)
    cathedral(1130, 830, 1.0, mc, gw, rng)
    # cut the glow where the silhouette doesn't exist (windows are inside)
    img = silhouette_layer(img, mc, (0.012, 0.004, 0.01), (0.07, 0.014, 0.02), 830, 500, 0.9, (1.0, 0.2, 0.08))
    G = mask_arr(gw) * mask_arr(mc)
    gb = mask_arr(blur(Image.fromarray((G * 255).astype(np.uint8)), 7))
    gb2 = mask_arr(blur(Image.fromarray((G * 255).astype(np.uint8)), 26))
    flick = 0.8 + 0.4 * fbm(BH, BW, 40, 2, 9)
    wcol = np.array([1.0, 0.52, 0.16], np.float32)
    img = img + (G * flick)[..., None] * wcol * 0.95 + gb[..., None] * wcol * 0.45 + gb2[..., None] * np.array([0.9, 0.2, 0.05], np.float32) * 0.5
    print("cathedral done")
    img = fog_band(img, 800, 55, (0.30, 0.055, 0.04), 0.6, 81)
    # smaller secondary ruin on the left
    m2 = Image.new("L", (BW, BH), 0)
    d2 = ImageDraw.Draw(m2)
    ridge2 = ridge_line(BW, 850, 38, 200, 14)
    d2.polygon([(0, BH)] + [(int(x), float(ridge2[x])) for x in xs[::3]] + [(BW, BH)], fill=255)
    # broken gothic arch ruin (left)
    ax = 300
    d2.rectangle([ax - 150, 560, ax - 105, 880], fill=255)
    d2.rectangle([ax + 105, 610, ax + 150, 880], fill=255)
    d2.polygon([(ax - 150, 560), (ax - 128, 520), (ax - 105, 560)], fill=255)
    d2.polygon(pointed_arch(ax - 105, 105, 640, 14) + [(ax + 105, 640), (ax - 105, 640)], fill=255)  # arch top slab
    d2.polygon(pointed_arch(ax - 85, 85, 660, 14), fill=0)
    d2.polygon([(ax - 105, 640), (ax - 60, 560), (ax - 20, 610), (ax + 20, 575), (ax + 105, 650)], fill=0)  # broken top
    for k in range(8):
        px = rng.randint(ax - 130, ax + 130)
        d2.polygon([(px, 880), (px + 10, 840 - rng.randint(0, 40)), (px + 25, 880)], fill=255)
    img = silhouette_layer(img, m2, (0.018, 0.006, 0.012), (0.10, 0.022, 0.025), 880, 300, 0.7)
    img = fog_band(img, 895, 50, (0.30, 0.055, 0.04), 0.55, 91)
    # ---- ground with lava cracks
    gy = 900
    m3 = Image.new("L", (BW, BH), 0)
    d3 = ImageDraw.Draw(m3)
    ridge3 = ridge_line(BW, gy, 24, 130, 22)
    d3.polygon([(0, BH)] + [(int(x), float(ridge3[x])) for x in xs[::3]] + [(BW, BH)], fill=255)
    # rocks & spikes
    for _ in range(26):
        x = rng.randint(0, BW)
        h = rng.randint(30, 120)
        w = rng.randint(12, 36)
        yb = float(ridge3[min(x, BW - 1)]) + 8
        d3.polygon([(x - w, yb), (x - w * 0.3, yb - h), (x + w * 0.2, yb - h * 0.8), (x + w, yb)], fill=255)
    gm = mask_arr(m3)
    ground_col = np.zeros((BH, BW, 3), np.float32)
    tex = fbm(BH, BW, 18, 5, 123)
    t = np.clip((Y - gy) / (BH - gy), 0, 1)
    ground_col[...] = np.array([0.045, 0.012, 0.014], np.float32) * (0.5 + tex[..., None] * 1.1)
    ground_col += (1 - t[..., None]) * np.array([0.05, 0.01, 0.01], np.float32)
    img = mix(img, ground_col, gm)
    cm = cracks_mask(BW, BH, gy + 15, rng, 28)
    cm = Image.fromarray((mask_arr(cm) * gm * 255).astype(np.uint8))
    core = mask_arr(blur(cm, 0.8))
    glow1 = mask_arr(blur(cm, 6))
    glow2 = mask_arr(blur(cm, 22))
    pulse = 0.75 + 0.5 * fbm(BH, BW, 90, 3, 144)
    lavacol = np.array([1.0, 0.55, 0.13], np.float32)
    img = img + gm[..., None] * (glow2[..., None] * np.array([0.65, 0.11, 0.02], np.float32) * 0.7 * pulse[..., None] + glow1[..., None] * np.array([0.9, 0.25, 0.05], np.float32) * 1.0)
    img = mix(img, lavacol * (0.8 + 0.5 * pulse[..., None]) , np.clip(core * 1.3, 0, 1))
    # ground rim light and edge
    rimg = np.clip(gm - mask_arr(ImageChops.offset(m3, 0, 3)), 0, 1)
    img = img + rimg[..., None] * np.array([0.5, 0.1, 0.04], np.float32)
    img = fog_band(img, 965, 70, (0.28, 0.05, 0.035), 0.45, 101, 200, 3)
    print("ground done")
    # ---- dead trees and stakes (mid/foreground silhouettes)
    m4 = Image.new("L", (BW, BH), 0)
    d4 = ImageDraw.Draw(m4)
    dead_tree(d4, 80, 1010, -1.45, 230, 26, 7, rng)
    dead_tree(d4, 1850, 1030, -1.7, 270, 30, 7, rng)
    dead_tree(d4, 470, 905, -1.6, 90, 8, 5, rng)
    dead_tree(d4, 1650, 905, -1.5, 100, 9, 5, rng)
    for x in (150, 380, 640, 1010, 1330, 1600, 1760):
        h = rng.randint(50, 130)
        yb = 1000 + rng.randint(-30, 70)
        d4.line([(x, yb), (x + rng.randint(-8, 8), yb - h)], fill=255, width=5)
        d4.line([(x - 18, yb - h * 0.7), (x + 18, yb - h * 0.7 + 4)], fill=255, width=4)
        d4.polygon([(x - 4, yb - h), (x, yb - h - 14), (x + 4, yb - h)], fill=255)
    m4 = m4.filter(ImageFilter.GaussianBlur(0.8)).point(lambda v: 255 if v > 110 else v * 2)
    img = silhouette_layer(img, m4, (0.006, 0.002, 0.004), (0.02, 0.006, 0.008), 1040, 300, 0.5)
    # ---- fog in front, low
    img = fog_band(img, 1030, 80, (0.20, 0.035, 0.03), 0.55, 111, 220, 3)
    return img, (mcx, mcy, mr)


def embers(img, rng, n=700):
    """Additive ember particles with streaks and bokeh."""
    add = Image.new("RGB", (BW, BH), (0, 0, 0))
    d = ImageDraw.Draw(add)
    wide = Image.new("RGB", (BW, BH), (0, 0, 0))
    dw = ImageDraw.Draw(wide)
    for i in range(n):
        x = rng.uniform(0, BW)
        y = BH * (1 - rng.beta(1.1, 2.4))
        size = rng.choice([1, 1, 1.5, 2, 2, 3, 4], p=[0.45, 0.25, 0.15, 0.1, 0.03, 0.015, 0.005])
        life = rng.uniform(0.3, 1.0)
        heat = rng.rand()
        col = lerp((255, 70, 15), (255, 210, 110), heat)
        col = tuple(int(c * life) for c in col)
        ang = math.radians(-70 + rng.normal(0, 12))
        ln = rng.uniform(1, 5) * size / 2
        d.line([(x, y), (x - math.cos(ang) * ln * 0.4 * -1, y + math.sin(ang) * ln * -0.6)], fill=col, width=max(1, int(size)))
        dw.ellipse([x - size * 2, y - size * 2, x + size * 2, y + size * 2], fill=tuple(int(c * 0.9) for c in col))
    # bokeh embers (out of focus)
    bk = Image.new("RGB", (BW, BH), (0, 0, 0))
    db = ImageDraw.Draw(bk)
    for i in range(26):
        x = rng.uniform(0, BW)
        y = BH * (1 - rng.beta(1.2, 2.0))
        r = rng.uniform(7, 20)
        c = lerp((120, 28, 8), (230, 110, 30), rng.rand())
        db.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(v * rng.uniform(0.2, 0.45)) for v in c))
    a = np.asarray(add).astype(np.float32) / 255
    b = np.asarray(blur(wide, 3.5)).astype(np.float32) / 255
    c = np.asarray(blur(bk, 5)).astype(np.float32) / 255
    return img + a * 1.4 + b * 1.1 + c * 0.7


def blood_layer(rng):
    """Returns (rgb float image, alpha float) for drips + top blood band, rendered at 3x for smoothness."""
    k = 3
    HH = 520
    W3, H3 = BW * k, HH * k
    m = Image.new("L", (W3, H3), 0)
    d = ImageDraw.Draw(m)
    # irregular band along top edge
    xs = np.arange(0, BW + 8, 8)
    band = 6 + 14 * fbm(1, len(xs) + 2, 6, 4, 77)[0][: len(xs)] + 12 * np.abs(np.sin(xs / 61.0 + 1.3))
    pts = [(0, 0)] + [(int(x * k), int(b * k)) for x, b in zip(xs, band)] + [(W3, 0)]
    d.polygon(pts, fill=255)
    # drips
    xsd = np.sort(rng.uniform(10, BW - 10, 30))
    for x in xsd:
        yb = float(np.interp(x, xs, band))
        w = rng.uniform(4, 9)
        if rng.rand() < 0.15:
            w *= 1.6
        L = rng.choice([rng.uniform(30, 90), rng.uniform(90, 220), rng.uniform(140, 440)], p=[0.5, 0.35, 0.15])
        tip = yb + L
        # stem: width narrows slightly toward the bulb, bulb at the end
        stem_w = w * 0.55
        d.polygon([((x - w * 0.9) * k, (yb - 6) * k), ((x + w * 0.9) * k, (yb - 6) * k), ((x + stem_w) * k, (tip - w) * k), ((x - stem_w) * k, (tip - w) * k)], fill=255)
        r = w * 0.85
        d.ellipse([(x - r) * k, (tip - r * 1.1) * k, (x + r) * k, (tip + r * 1.3) * k], fill=255)
        # teardrop point
        d.polygon([((x - r * 0.6) * k, (tip + r * 0.9) * k), ((x + r * 0.6) * k, (tip + r * 0.9) * k), ((x) * k, (tip + r * 2.0) * k)], fill=255) if False else None
    m = m.resize((BW, HH), Image.LANCZOS)
    M = mask_arr(m)
    # shading: darker body, brighter wet specular on the left, rim darkening
    Yv = np.arange(HH, dtype=np.float32)[:, None]
    base_c = np.zeros((HH, BW, 3), np.float32)
    n = fbm(HH, BW, 30, 3, 5)
    for i, (a, b) in enumerate(zip((0.30, 0.015, 0.014), (0.10, 0.004, 0.006))):
        base_c[..., i] = a + (b - a) * np.clip(Yv / 300, 0, 1) + (n - 0.5) * 0.08 * (1 if i == 0 else 0.2)
    left = mask_arr(ImageChops.offset(m, 3, 1))
    spec = np.clip(M - left, 0, 1)
    spec = mask_arr(blur(Image.fromarray((spec * 255).astype(np.uint8)), 1.1))
    right = mask_arr(ImageChops.offset(m, -3, -1))
    edge_dark = np.clip(M - right, 0, 1)
    edge_dark = mask_arr(blur(Image.fromarray((edge_dark * 255).astype(np.uint8)), 1.2))
    col = base_c + spec[..., None] * np.array([0.75, 0.22, 0.18], np.float32) - edge_dark[..., None] * 0.12
    # soft gloss at the bulbs
    gl = mask_arr(blur(Image.fromarray((np.clip(M - mask_arr(m.filter(ImageFilter.MinFilter(9))), 0, 1) * 255).astype(np.uint8)), 2))
    col += gl[..., None] * np.array([0.25, 0.06, 0.05], np.float32)
    return col, M


def finish(img, rng):
    # bloom
    bright = np.clip(img - 0.55, 0, None)
    bl = np.asarray(blur(to_img(np.clip(bright, 0, 1)), 24)).astype(np.float32) / 255
    img = img + bl * 1.2
    # vignette
    Y, X = np.mgrid[0:BH, 0:BW].astype(np.float32)
    r = np.sqrt(((X - BW / 2) / (BW / 2)) ** 2 * 0.95 + ((Y - BH * 0.48) / (BH / 2)) ** 2)
    vig = 1 - smoothstep(0.55, 1.35, r) * 0.82
    img = img * vig[..., None]
    # centre dim for UI legibility (login box sits there)
    cd = np.exp(-(((X - BW / 2) / 330) ** 2 + ((Y - BH * 0.52) / 280) ** 2)) * 0.28
    img = img * (1 - cd[..., None])
    # grade: filmic-ish curve, crush blacks, bias red
    img = np.clip(img, 0, 4)
    img = 1 - np.exp(-img * 1.15)
    img = img ** np.array([1.12, 1.25, 1.25], np.float32)
    img[..., 0] *= 1.04
    # fine hairline cracks near corners (damaged look)
    cr = Image.new("L", (BW, BH), 0)
    dc = ImageDraw.Draw(cr)
    def hair(x, y, ang, n):
        for i in range(n):
            nx, ny = x + math.cos(ang) * rng.uniform(10, 26), y + math.sin(ang) * rng.uniform(10, 26)
            dc.line([(x, y), (nx, ny)], fill=255, width=1)
            if rng.rand() < 0.12:
                hair(nx, ny, ang + rng.choice([-1, 1]) * rng.uniform(0.4, 1.1), n // 2)
            x, y, ang = nx, ny, ang + rng.normal(0, 0.35)
    for (x, y, a) in ((0, 0, 0.8), (BW, 0, 2.3), (0, BH, -0.8), (BW, BH, -2.3), (0, 520, 0.1), (BW, 600, math.pi)):
        for k in range(3):
            hair(x, y, a + rng.uniform(-0.5, 0.5), rng.randint(12, 26))
    hm = mask_arr(blur(cr, 0.6)) * (0.20 + 0.0)
    img = img - hm[..., None] * 0.18
    img = img + hm[..., None] * np.array([0.12, 0.0, 0.0], np.float32)
    # grain
    img += (rng.randn(BH, BW, 1).astype(np.float32)) * 0.018
    return np.clip(img, 0, 1)


def gen_background():
    rng = np.random.RandomState(2024)
    img, moon = make_background()
    img = embers(img, rng)
    col, M = blood_layer(rng)
    HH = col.shape[0]
    top = img[:HH]
    img[:HH] = top * (1 - M[..., None]) + col * M[..., None]
    # a faint wet red cast below each drip
    img = finish(img, rng)
    out = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB")
    save(out, "background.png")
    # smaller 1280x720 preview-friendly copy is not needed by the client; skip.


# ---------------------------------------------------------------- logo
def chaikin_open(pts, it=3):
    pts = list(pts)
    for _ in range(it):
        new = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            new.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            new.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        new.append(pts[-1])
        pts = new
    return pts


def letter_masks():
    """Returns a dict letter -> (draw_fn, width) in a 100x140 box (y down)."""
    def Hf(d, ox, oy, k):
        P = lambda pts: [(ox + x * k, oy + y * k) for x, y in pts]
        d.polygon(P([(0, 0), (12, -16), (24, 0), (24, 140), (12, 154), (0, 140)]), fill=255)
        d.polygon(P([(76, 0), (88, -16), (100, 0), (100, 140), (88, 154), (76, 140)]), fill=255)
        d.polygon(P([(24, 56), (76, 56), (76, 70), (50, 86), (24, 70)]), fill=255)
        d.polygon(P([(24, 76), (50, 92), (76, 76), (76, 84), (24, 84)]), fill=255)

    def Af(d, ox, oy, k):
        P = lambda pts: [(ox + x * k, oy + y * k) for x, y in pts]
        d.polygon(P([(0, 140), (44, -6), (50, -26), (56, -6), (100, 140), (74, 140), (50, 40), (26, 140)]), fill=255)
        d.polygon(P([(24, 84), (76, 84), (80, 100), (20, 100)]), fill=255)
        d.polygon(P([(0, 140), (14, 156), (26, 140)]), fill=255)
        d.polygon(P([(74, 140), (86, 156), (100, 140)]), fill=255)

    def Of(d, ox, oy, k):
        P = lambda pts: [(ox + x * k, oy + y * k) for x, y in pts]
        d.ellipse([ox, oy, ox + 100 * k, oy + 140 * k], fill=255)
        d.ellipse([ox + 28 * k, oy + 30 * k, ox + 72 * k, oy + 110 * k], fill=0)
        d.polygon(P([(38, 2), (50, -22), (62, 2)]), fill=255)
        d.polygon(P([(38, 138), (50, 162), (62, 138)]), fill=255)
        d.polygon(P([(50, 56), (58, 70), (50, 84), (42, 70)]), fill=255)

    def Cf(d, ox, oy, k):
        P = lambda pts: [(ox + x * k, oy + y * k) for x, y in pts]
        d.ellipse([ox, oy, ox + 100 * k, oy + 140 * k], fill=255)
        d.ellipse([ox + 26 * k, oy + 28 * k, ox + 74 * k, oy + 112 * k], fill=0)
        d.polygon(P([(50, 70), (150, -10), (150, 150)]), fill=0)
        d.polygon(P([(88, 22), (112, 6), (94, 40)]), fill=255)
        d.polygon(P([(88, 118), (112, 134), (94, 100)]), fill=255)
        d.polygon(P([(30, 2), (42, -20), (54, 2)]), fill=255)

    def Sf(d, ox, oy, k):
        pts = [(86, 26), (66, 6), (36, 4), (16, 26), (28, 52), (60, 70), (84, 92), (78, 120), (54, 138), (24, 134), (8, 112)]
        pts = chaikin_open(pts, 3)
        P = [(ox + x * k, oy + y * k) for x, y in pts]
        w = int(23 * k)
        d.line(P, fill=255, width=w, joint="curve")
        r = w / 2
        for (x, y) in P[::2]:
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        for (x, y, dx, dy) in ((86, 26, 18, -6), (8, 112, -14, 12)):
            X, Y = ox + x * k, oy + y * k
            d.polygon([(X - 12 * k, Y - 10 * k), (X + dx * k, Y + dy * k), (X + 12 * k, Y + 10 * k)], fill=255)

    return {"C": (Cf, 100), "H": (Hf, 100), "A": (Af, 100), "O": (Of, 100), "S": (Sf, 100)}


def make_logo():
    SS = 2
    W, H = 760 * SS, 300 * SS
    k = 1.2 * SS
    L = letter_masks()
    word = "CHAOS"
    gap = 22
    total = sum(L[c][1] for c in word) * 1.2 + gap * (len(word) - 1)
    ox = (760 - total) / 2 * SS
    oy = 52 * SS
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    x = ox
    for c in word:
        fn, wd = L[c]
        fn(d, x, oy, k)
        x += (wd * 1.2 + gap) * SS
    m = m.filter(ImageFilter.GaussianBlur(0.7))
    M = mask_arr(m)
    # drips below letters
    rng = np.random.RandomState(99)
    dm = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(dm)
    mm = np.asarray(m)
    for xx_ in range(int(ox), int(W - ox), 5 * SS):
        col = mm[:, xx_]
        ys = np.where(col > 128)[0]
        if len(ys) and rng.rand() < 0.2:
            yb = ys.max()
            w = rng.uniform(3, 7) * SS
            ln = rng.uniform(14, 40) * SS
            dd.polygon([(xx_ - w, yb - 6 * SS), (xx_ + w, yb - 6 * SS), (xx_ + w * 0.5, yb + ln), (xx_ - w * 0.5, yb + ln)], fill=255)
            dd.ellipse([xx_ - w * 0.9, yb + ln - w, xx_ + w * 0.9, yb + ln + w * 1.4], fill=255)
    dm = dm.filter(ImageFilter.GaussianBlur(0.8))
    DM = mask_arr(dm)
    yy = np.mgrid[0:H, 0:W][0].astype(np.float32)
    top = oy - 30 * SS
    t = np.clip((yy - top) / (170 * SS), 0, 1)
    # gold-to-blood gradient, "blood soaked" from below
    stops = [(0.0, GOLD_4), (0.28, GOLD_3), (0.5, GOLD_2), (0.68, GOLD_1), (0.82, BLOOD_3), (1.0, BLOOD_1)]
    body = np.zeros((H, W, 3), np.float32)
    for i in range(3):
        body[..., i] = np.interp(t, [s[0] for s in stops], [s[1][i] for s in stops])
    pat = fbm(H, W, 7 * SS, 4, 5)
    body *= (0.74 + 0.5 * pat)[..., None]
    # brushed scratches
    sc = np.random.RandomState(4).randn(1, W).astype(np.float32)
    body *= (1 + 0.04 * sc)[..., None]
    sh = lambda im, dx, dy: ImageChops.offset(im, dx, dy)
    hi = np.clip(M - mask_arr(sh(m, 3 * SS, 3 * SS)), 0, 1)
    lo = np.clip(M - mask_arr(sh(m, -3 * SS, -3 * SS)), 0, 1)
    hi = mask_arr(blur(Image.fromarray((hi * 255).astype(np.uint8)), 1.5 * SS))
    lo = mask_arr(blur(Image.fromarray((lo * 255).astype(np.uint8)), 1.5 * SS))
    body = body + hi[..., None] * (np.array(GOLD_4, np.float32) - body) * 0.95
    body *= (1 - lo[..., None] * 0.7)
    # inner chisel line
    inner = mask_arr(m.filter(ImageFilter.MinFilter(2 * SS * 3 + 1)))
    ring = np.clip(M - inner, 0, 1)
    body = body * (1 - ring[..., None] * 0.25)
    out = np.zeros((H, W, 4), np.float32)
    # ember glow
    gl = mask_arr(blur(m, 26 * SS))
    gl2 = mask_arr(blur(m, 8 * SS))
    out[..., :3] = np.array([200, 40, 15], np.float32)
    out[..., 3] = np.clip(gl * 0.75 + gl2 * 0.4, 0, 1) * 255
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    # shadow + outline
    shd = alpha_layer_wh((0, 0, 0), mask_arr(blur(sh(m, 4 * SS, 6 * SS), 4 * SS)) * 0.9, W, H)
    img.alpha_composite(shd)
    ol = alpha_layer_wh((8, 3, 3), mask_arr(m.filter(ImageFilter.MaxFilter(4 * SS + 1))), W, H)
    img.alpha_composite(ol)
    # blood drips
    bcol = np.zeros((H, W, 3), np.float32)
    bcol[...] = np.array([150, 14, 12], np.float32)
    bcol *= (0.7 + 0.5 * pat)[..., None]
    dsp = np.clip(DM - mask_arr(sh(dm, 2 * SS, 0)), 0, 1)
    bcol += dsp[..., None] * 120
    dl = Image.fromarray(np.clip(bcol, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    dl.putalpha(dm)
    img.alpha_composite(dl)
    layer = Image.fromarray(np.clip(body, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    layer.putalpha(m)
    img.alpha_composite(layer)
    # ornament line under the word
    od = ImageDraw.Draw(img)
    y0 = int(284 * SS)
    cxm = W // 2
    for s_ in (-1, 1):
        for i in range(0, int(260 * SS)):
            tt = i / (260 * SS)
            col = tuple(int(c) for c in lerp(GOLD_3, BLOOD_2, tt)) + (int(255 * (1 - tt) ** 0.7),)
            od.point((cxm + s_ * (14 * SS + i), y0), col)
            od.point((cxm + s_ * (14 * SS + i), y0 + 1), col)
    od.polygon([(cxm, y0 - 8 * SS), (cxm + 8 * SS, y0), (cxm, y0 + 8 * SS), (cxm - 8 * SS, y0)], fill=BLACK + (255,))
    od.polygon([(cxm, y0 - 5 * SS), (cxm + 5 * SS, y0), (cxm, y0 + 5 * SS), (cxm - 5 * SS, y0)], fill=BLOOD_3 + (255,))
    return img.resize((W // SS, H // SS), Image.LANCZOS)


def alpha_layer_wh(color, a, w, h):
    lay = Image.new("RGBA", (w, h), tuple(color) + (0,))
    lay.putalpha(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)))
    return lay


def gen_logo():
    lg = make_logo()
    save(lg, "logo.png")
    save(lg.resize((lg.width // 2, lg.height // 2), Image.LANCZOS), "logo_small.png")


# ---------------------------------------------------------------- main
def main(argv):
    tasks = argv[1:] or ["icons", "logo", "background"]
    for t in tasks:
        {"frames": gen_frames, "icons": gen_icons, "logo": gen_logo, "background": gen_background}[t]()


if __name__ == "__main__":
    main(sys.argv)
