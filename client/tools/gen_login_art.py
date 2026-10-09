#!/usr/bin/env python3
"""Art of the login screen (module client_chaos_login), made from the login artwork in client/tools/art_src/.

  python3 -I client/tools/gen_login_art.py [bg] [ui] [logo] [brand]      (no argument = all)

Needs Pillow, numpy, scipy and OpenCV with the contrib modules (pip install opencv-contrib-python-headless) for
bg / logo / brand; ui needs Pillow + numpy and a serif TrueType font (Liberation Serif, searched in $CHAOS_ART_FONTS
and the system font folders) for the lettering of the press-key bar.

Source: art_src/login_reference.webp (1376x768, the team's login artwork: cathedral city over lava, the "Cinders
of Chaos" logo in its thorn frame, and mock interface elements painted in). Everything below is derived from it:

bg    data/images/title.png              1920x1536 background. The artwork is cleaned of its painted mock interface
                                         (see clean_reference), upscaled to a 1920x1072 band (Lanczos + light
                                         unsharp mask) and extended above and below by a darkened, blurred mirror
                                         of its edges, so a 16:10 or 4:3 window shows the whole width without
                                         stretching; login.lua crops it to cover the window. The small four-pointed
                                         mark in the bottom right corner of the artwork is kept exactly as it is.
      data/images/chaos/login/glow.png   flicker overlay of the lava and the lit windows (same frame as title.png)
logo  data/images/chaos/logo.png         the logo cut out of the artwork (1168x740, 2x, alpha matte: hand traced
                                         frame outline refined with a guided filter, flames and glow keyed by heat)
      data/images/chaos/logo_small.png   half size; data/images/ui/logo.png: the stock 225x261 slot
      data/images/chaos/login/logo_hot.png  the hottest parts of the letters; login.lua lets its opacity breathe
                                         over the logo (the logo layer sits exactly on the logo in the background)
ui    data/images/chaos/login/*.png      panel frame, rune medallions, buttons, fields, crest, press-key bar and
                                         its serif lettering, spinner, ember, spark and ash sprites
brand docs/brand/cinders_logo*.png       the logo for general use: transparent, on black, square icon

Deterministic for given library and font versions.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
IMG = os.path.normpath(os.path.join(HERE, '..', 'overlay', 'data', 'images'))
UI_OUT = os.path.join(IMG, 'chaos', 'login')
BRAND_OUT = os.path.join(REPO, 'docs', 'brand')
REF_SRC = os.path.join(HERE, 'art_src', 'login_reference.webp')

REF_W, REF_H = 1376, 768                  # the artwork
BG_W, BAND_H = 1920, 1072                 # the artwork upscaled into title.png ...
BAND_Y = 232                              # ... at this row, with this much extension above and below
BG_H = BAND_Y * 2 + BAND_H                # 1536 (5:4): any window from 16:9 to 5:4 sees the full width
LOGO_BOX = (396, 196, 980, 566)           # the logo in artwork pixels (frame tips, flames, glow)
LOGO_K = 2                                # logo.png is LOGO_K x the artwork's pixels
LOGO_W, LOGO_H = (LOGO_BOX[2] - LOGO_BOX[0]) * LOGO_K, (LOGO_BOX[3] - LOGO_BOX[1]) * LOGO_K


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print('wrote', os.path.relpath(path, REPO), img.size)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def _cv():
    try:
        import cv2
    except ImportError:
        sys.exit('bg / logo / brand need OpenCV with the contrib modules: pip install opencv-contrib-python-headless')
    if not hasattr(cv2, 'xphoto'):
        sys.exit('OpenCV without the contrib modules (cv2.xphoto missing): pip install opencv-contrib-python-headless')
    return cv2


# ------------------------------------------------------------------ the artwork
def load_reference():
    """the artwork as float32 RGB 0..1 (REF_H, REF_W, 3)"""
    im = Image.open(REF_SRC).convert('RGB')
    assert im.size == (REF_W, REF_H), im.size
    return np.asarray(im, np.float32) / 255.0


def _box(x0, y0, x1, y1):
    m = np.zeros((REF_H, REF_W), bool)
    m[y0:y1, x0:x1] = True
    return m


def _dil(m, r):
    cv2 = _cv()
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    return cv2.dilate(m.astype(np.uint8), k).astype(bool)


def generator_mark(img):
    """mask of the four-pointed sparkle mark the image generator left in the bottom right corner. It is never
    painted over: clean_reference puts these pixels back unchanged, and login.lua keeps widgets and particles off it.
    Found as the bright neutral blob there, then fitted with a four-pointed star |dx|^q + |dy|^q <= r^q (+1 px)."""
    from scipy import ndimage as ndi
    lum, sat = img.mean(2), img.max(2) - img.min(2)
    lab, _ = ndi.label(_box(1288, 682, 1350, 742) & (lum > 0.45) & (sat < 0.10))
    blob = lab == lab[710, 1318]
    cy, cx = np.argwhere(blob).mean(0)
    yy, xx = np.mgrid[0:REF_H, 0:REF_W]
    dx, dy = np.abs(xx - cx), np.abs(yy - cy)
    best = (0, 0.6, 28.0)
    for q in np.arange(0.45, 0.95, 0.05):
        p = dx ** q + dy ** q
        for r in np.arange(18, 30, 0.5):
            s = p <= r ** q
            iou = (s & blob).sum() / max(1, (s | blob).sum())
            if iou > best[0]:
                best = (iou, q, r)
    _, q, r = best
    return dx ** q + dy ** q <= (r + 1.0) ** q


def _fsr(img, hole):
    """frequency selective reconstruction (OpenCV xphoto) of the pixels in hole"""
    cv2 = _cv()
    bgr = cv2.cvtColor((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), cv2.COLOR_RGB2BGR)
    dst = np.zeros_like(bgr)
    cv2.xphoto.inpaint(bgr, (~hole).astype(np.uint8), dst, cv2.xphoto.INPAINT_FSR_BEST)
    out = cv2.cvtColor(dst, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    return np.where(hole[..., None], out, img)


def _clone(img, src_box, dx, dy, pad=3):
    """gradient-domain copy (OpenCV seamlessClone) of src_box moved by (dx, dy): the texture of the source with the
    colours of the destination's surroundings"""
    cv2 = _cv()
    x0, y0, x1, y1 = src_box
    u8 = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    patch = np.ascontiguousarray(u8[y0:y1, x0:x1])
    m = np.zeros(patch.shape[:2], np.uint8)
    m[pad:-pad, pad:-pad] = 255
    centre = ((x0 + x1) // 2 + dx, (y0 + y1) // 2 + dy)
    out = cv2.seamlessClone(cv2.cvtColor(patch, cv2.COLOR_RGB2BGR), cv2.cvtColor(u8, cv2.COLOR_RGB2BGR), m, centre,
                            cv2.NORMAL_CLONE)
    return cv2.cvtColor(out, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0


def _no_embers(img):
    """the glowing ember dots replaced by their surroundings (median), for copies that would repeat them"""
    from scipy import ndimage as ndi
    med = np.stack([ndi.median_filter(img[..., c], size=9) for c in range(3)], -1)
    hot = ndi.binary_dilation((img[..., 0] - med[..., 0]) > 0.07, iterations=1)
    return np.where(hot[..., None], med, img)


def clean_reference(img):
    """the artwork without its painted mock interface. Returns (clean image, generator mark mask).
    1. "PRESS ANY KEY TO START" bar: a translucent black band (rows 571-605, fading out at both ends). Its darkening
       is measured per column against the rows above and below it and divided out, which brings back the stairs
       painted under it; the lettering is filled by FSR and then covered by a gradient-domain copy of the stairs
       just above it (they repeat upwards), the band's edge rows and the rule under it by FSR.
    2. "CONNECTING..." and the spinner ring: FSR on tight masks of the letters and the ring.
    3. LOGIN button: gradient-domain copy of the rock floor 52 px above it.
    4. Top right icon: gradient-domain copy of the stonework below it.
    5. Bottom right "LOGIN" and crosshair icon: gradient-domain copy of the rocks to the left; the generator mark that
       overlaps the icon is filled only temporarily (so it does not bleed into the copy) and then put back exactly."""
    from scipy import ndimage as ndi
    mark = generator_mark(img)
    out = img.copy()
    lum, sat = img.mean(2), img.max(2) - img.min(2)
    yy, xx = np.mgrid[0:REF_H, 0:REF_W]

    # 1. the bar: divide its darkening out, per colour channel (target level: rows above at the top, rows below at
    #    the bottom)
    X0, X1, Y0, Y1 = 470, 930, 571, 606
    sm = lambda a: ndi.uniform_filter1d(a, 61, axis=-1, mode='nearest')
    rows = np.arange(Y0, Y1)
    t = ((rows - Y0 + 0.5) / (Y1 - Y0))[:, None]
    for c in range(3):
        ch = img[..., c]
        above = sm(ch[562:570, X0:X1].mean(0))
        below = sm(ch[608:615, X0:X1].mean(0))
        seen = np.stack([sm(ch[y, X0:X1]) for y in range(Y0, Y1)])
        top, bot = seen[1:9].mean(0), seen[26:34].mean(0)
        for i, y in enumerate(rows):      # rows with lettering: level interpolated from the clean rows
            if 580 <= y <= 596:
                k = (y - 579.5) / (597 - 579.5)
                seen[i] = top * (1 - k) + bot * k
        gain = np.clip((above[None] * (1 - t) + below[None] * t) / np.maximum(seen, 1e-3), 1, 6)
        out[Y0:Y1, X0:X1, c] = np.clip(out[Y0:Y1, X0:X1, c] * gain, 0, 1)
    # 2. small things: band edges, rule and its ornament, CONNECTING..., spinner ring
    conn = _box(620, 612, 758, 637) & (lum > 0.28) & (sat < 0.25)
    ring = ((xx - 687.5) ** 2 + (yy - 657) ** 2 >= 25) & ((xx - 687.5) ** 2 + (yy - 657) ** 2 <= 361)
    out = _fsr(out, _box(X0, 569, X1, 574) | _box(X0, 602, X1, 609) | _dil(conn, 2) | ring)
    # the lettering
    letters = _box(540, 575, 840, 602) & (lum > 0.30) & (sat < 0.25)
    band = (_dil(letters, 3) | _box(562, 578, 816, 599)) & ~_box(0, 0, REF_W, 573) & ~_box(0, 603, REF_W, REF_H)
    out = _fsr(out, band)
    cl = _clone(_no_embers(out), (548 + 37, 554, 830 + 37, 580), -37, 24)
    cv2 = _cv()
    f = np.zeros((REF_H, REF_W), np.float32)
    f[554 + 24 + 2:580 + 24 - 2, 548 + 6:830 - 6] = 1
    f = cv2.GaussianBlur(f, (0, 0), 2.0)
    f = np.maximum(f, band.astype(np.float32)) * cv2.GaussianBlur(
        _box(550, 554 + 24 + 1, 828, 580 + 24 - 1).astype(np.float32), (0, 0), 1.5)
    out = out * (1 - f[..., None]) + cl * f[..., None]
    out = _fsr(out, _box(664, 597, 712, 617) | _box(X0, 569, X1, 574) | _box(X0, 602, X1, 607))
    # 3. the LOGIN button
    out = _clone(out, (586, 635, 793, 693), 0, 52)
    # 4. the top right icon
    out = np.where(_box(1326, 0, REF_W, 48)[..., None], _clone(out, (1328, 44, REF_W, 92), 0, -44, pad=2), out)
    # 5. bottom right: LOGIN and the crosshair icon, around the generator mark
    tmp = _fsr(out, _dil(mark, 1))
    cl = _clone(tmp, (1126, 708, 1246, 766), 120, 0)
    out = np.where(_box(1246, 708, 1366, 766)[..., None], cl, out)
    out = np.where(mark[..., None], img, out)
    assert np.array_equal(out[mark], img[mark])
    return out, mark


# ------------------------------------------------------------------ the logo
# outline of the thorn frame (artwork pixels), traced by hand: left half from the top spike down to the bottom spike,
# then the right half; the letters, flames and glow are added from the picture (see logo_matte)
LOGO_LEFT = [(687, 212), (685, 255), (670, 254), (655, 257), (650, 249), (647, 260), (637, 264), (627, 267), (626, 232),
             (622, 270), (609, 250), (605, 275), (595, 282), (585, 290), (560, 292), (540, 290), (520, 284), (505, 290),
             (495, 300), (489, 320), (489, 340), (495, 350), (492, 357), (485, 360), (475, 361), (470, 364), (460, 365),
             (450, 370), (437, 375), (412, 377), (412, 379), (437, 380), (450, 382), (465, 390), (469, 394), (475, 389),
             (485, 390), (492, 394), (499, 400), (510, 410), (517, 420), (522, 430), (527, 442), (537, 462), (545, 478),
             (555, 481), (567, 483), (580, 483), (592, 478), (600, 475), (610, 481), (620, 490), (630, 496), (642, 501),
             (648, 505), (651, 522), (656, 508), (665, 512), (675, 517), (682, 525), (688, 553)]
LOGO_RIGHT = [(687, 212), (690, 255), (705, 254), (720, 257), (725, 249), (729, 260), (739, 264), (749, 267), (750, 232),
              (754, 270), (767, 250), (771, 275), (781, 282), (791, 290), (815, 290), (835, 285), (855, 286), (868, 295),
              (875, 310), (876, 330), (873, 350), (878, 357), (888, 360), (900, 362), (908, 365), (920, 370), (935, 374),
              (960, 377), (960, 379), (940, 381), (925, 384), (912, 388), (907, 394), (900, 390), (890, 392), (882, 396),
              (875, 402), (866, 412), (860, 422), (857, 432), (852, 444), (843, 460), (834, 470), (822, 477), (810, 481),
              (797, 482), (785, 479), (776, 476), (766, 481), (756, 490), (746, 495), (734, 500), (728, 505), (725, 522),
              (720, 508), (711, 512), (701, 517), (694, 525), (688, 553)]


def logo_outline():
    return LOGO_LEFT + list(reversed(LOGO_RIGHT[1:-1]))


def _guided(I, p, r, eps):
    """colour guided filter (He et al.): p smoothed along the edges of the guide image I"""
    from scipy import ndimage as ndi
    box = lambda a: ndi.uniform_filter(a, 2 * r + 1, mode='reflect')
    h, w = p.shape
    mI = [box(I[..., c]) for c in range(3)]
    mp = box(p)
    cov = np.stack([box(I[..., c] * p) - mI[c] * mp for c in range(3)], -1)
    var = np.zeros((h, w, 3, 3), np.float32)
    for i in range(3):
        for j in range(3):
            var[..., i, j] = box(I[..., i] * I[..., j]) - mI[i] * mI[j]
    var += eps * np.eye(3, dtype=np.float32)
    a = np.linalg.solve(var, cov[..., None])[..., 0]
    b = mp - sum(a[..., c] * mI[c] for c in range(3))
    return sum(box(a[..., c]) * I[..., c] for c in range(3)) + box(b)


def logo_matte(img):
    """(colour, alpha) of the logo inside LOGO_BOX, artwork resolution. alpha: the frame outline (4x supersampled
    polygon) snapped to the picture by a guided filter in a 4 px band, plus the flames and sparks outside it keyed by
    heat (warm brightness over the local background, within 22 px); isolated specks are dropped. colour: the
    background estimate (grey opening, blurred) is removed from the partly transparent pixels."""
    from scipy import ndimage as ndi
    x0, y0, x1, y1 = LOGO_BOX
    I = img[y0:y1, x0:x1]
    h, w = I.shape[:2]
    ss = 4
    m = Image.new('L', (w * ss, h * ss), 0)
    ImageDraw.Draw(m).polygon([((x - x0 + 0.5) * ss, (y - y0 + 0.5) * ss) for x, y in logo_outline()], fill=255)
    P = np.asarray(m.resize((w, h), Image.BOX), np.float32) / 255.0
    G = np.clip(_guided(I, P, 3, 2e-3), 0, 1)
    band = (ndi.distance_transform_edt(P < 0.5) <= 4) & (ndi.distance_transform_edt(P >= 0.5) <= 4)
    A = np.where(band, G, P)
    mx = I.max(2)
    bg = ndi.gaussian_filter(ndi.grey_opening(mx, size=9), 4)
    warm = np.clip((I[..., 0] - I[..., 2]) * 3, 0, 1)
    fire = np.clip((mx - bg - 0.10) / 0.45, 0, 1) * warm * (ndi.distance_transform_edt(P < 0.5) <= 22)
    lab, n = ndi.label(fire > 0.04)
    if n:
        size = ndi.sum(np.ones_like(fire), lab, np.arange(1, n + 1))
        near = ndi.minimum(ndi.distance_transform_edt(P < 0.5), lab, np.arange(1, n + 1))
        keep = np.concatenate([[False], (size >= 12) | (near <= 3)])
        fire = fire * keep[lab]
    A = np.maximum(A, ndi.gaussian_filter(fire, 0.6))
    A[A < 0.02] = 0
    B = np.stack([ndi.gaussian_filter(ndi.grey_opening(I[..., c], size=9), 4) for c in range(3)], -1)
    a3 = A[..., None]
    F = np.where(a3 > 0.98, I, (I - (1 - a3) * B) / np.maximum(a3, 1e-3))
    return np.clip(F, 0, 1), A


def logo_hot(F, A):
    """the hottest parts of the letters (alpha) and their colour, artwork resolution"""
    from scipy import ndimage as ndi
    lum = F.max(2)
    warm = np.clip((F[..., 0] - F[..., 2]) * 2.5, 0, 1)
    heat = smooth(0.62, 0.98, lum) * warm * smooth(0.6, 0.95, A)
    heat = ndi.gaussian_filter(heat, 0.7)
    col = ember_ramp(np.clip(0.55 + 0.45 * heat, 0, 1)) / 255.0
    return col, np.clip(heat * 0.85, 0, 1)


def _resize(a, size, sharpen=0.0, sigma=1.0):
    """Lanczos resize of a float image (h, w[, c]) to size (w, h) with an optional unsharp mask"""
    cv2 = _cv()
    out = cv2.resize(np.ascontiguousarray(a, np.float32), size, interpolation=cv2.INTER_LANCZOS4)
    if sharpen:
        out = out + sharpen * (out - cv2.GaussianBlur(out, (0, 0), sigma))
    return np.clip(out, 0, 1)


def _rgba(F, A, size=None):
    """RGBA image from colour and alpha (resized premultiplied, so no dark or bright fringes)"""
    if size:
        pm = _resize(F * A[..., None], size, 0.25, 0.8)
        A = _resize(A, size)
        F = np.where(A[..., None] > 1e-3, pm / np.maximum(A[..., None], 1e-3), 0)
    arr = np.dstack([np.clip(F, 0, 1), np.clip(A, 0, 1)])
    return Image.fromarray((arr * 255 + 0.5).astype(np.uint8), 'RGBA')


def make_wordmark():
    """the logo cut out of the artwork: (logo RGBA, hot glow RGBA), both LOGO_W x LOGO_H"""
    F, A = logo_matte(load_reference())
    col, ha = logo_hot(F, A)
    return _rgba(F, A, (LOGO_W, LOGO_H)), _rgba(col, ha, (LOGO_W, LOGO_H))


# ------------------------------------------------------------------ background
def make_background():
    """(title.png RGB, glow.png RGBA), both BG_W x BG_H"""
    from scipy import ndimage as ndi
    cv2 = _cv()
    ref = load_reference()
    clean, mark = clean_reference(ref)
    band = _resize(clean, (BG_W, BAND_H), 0.35, 1.0)
    # extension: mirror of the band's edges (mark filled in the mirrored copy only), blurred and darkened outwards
    src = _resize(_fsr(clean, _dil(mark, 2)), (BG_W, BAND_H))
    canvas = np.zeros((BG_H, BG_W, 3), np.float32)
    canvas[BAND_Y:BAND_Y + BAND_H] = band
    e = BAND_Y
    top = src[1:e + 1][::-1]
    bot = src[BAND_H - e - 1:BAND_H - 1][::-1]
    for part, rows in ((top, np.arange(e)[::-1]), (bot, np.arange(e))):
        d = (rows + 1)[:, None, None] / e                  # 0 at the band, 1 at the image edge
        soft = cv2.GaussianBlur(part, (0, 0), 7)
        mixed = part * np.clip(1 - d * 6, 0, 1) + soft * np.clip(d * 6, 0, 1)
        part[:] = mixed * (1 - 0.82 * d ** 0.9)
    canvas[:BAND_Y] = top
    canvas[BAND_Y + BAND_H:] = bot
    # glow overlay: the lava and the lit windows, brighter and warmer; nothing on the logo or the generator mark
    lum = band.max(2)
    warm = np.clip((band[..., 0] - band[..., 2]) * 2.2, 0, 1)
    g = smooth(0.5, 0.92, lum) * warm
    lm = Image.new('L', (BG_W, BAND_H), 0)
    s = BG_W / REF_W
    ImageDraw.Draw(lm).polygon([(x * s, y * s) for x, y in logo_outline()], fill=255)
    lm = np.asarray(lm.filter(ImageFilter.MaxFilter(31)).filter(ImageFilter.GaussianBlur(10)), np.float32) / 255
    mk = cv2.resize(_dil(mark, 6).astype(np.float32), (BG_W, BAND_H), interpolation=cv2.INTER_LINEAR)
    g = ndi.gaussian_filter(g * (1 - lm) * (1 - np.clip(mk * 4, 0, 1)), 1.2)
    glow = np.zeros((BG_H, BG_W, 4), np.float32)
    glow[BAND_Y:BAND_Y + BAND_H, :, :3] = np.clip(band * 1.35 + np.array([0.10, 0.04, 0.0]), 0, 1)
    glow[BAND_Y:BAND_Y + BAND_H, :, 3] = np.clip(g * 0.6, 0, 1)
    glow[glow[..., 3] < 1.5 / 255] = 0                  # fully transparent pixels carry no colour (smaller file)
    title = Image.fromarray((np.clip(canvas, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')
    return title, Image.fromarray((glow * 255 + 0.5).astype(np.uint8), 'RGBA')


# ------------------------------------------------------------------ UI art
IRON0, IRON1, IRON2, IRON3, IRON4, IRON5 = (10, 8, 11), (22, 18, 21), (38, 31, 35), (62, 54, 58), (96, 86, 90), (140, 128, 130)
BLOOD, BLOOD_HI, BLOOD_LO = (158, 24, 18), (232, 70, 40), (74, 10, 10)


def px_image(w, h):
    return Image.new('RGBA', (w, h), (0, 0, 0, 0))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def chamfer_poly(w, h, c):
    return [(c, 0), (w - 1 - c, 0), (w - 1, c), (w - 1, h - 1 - c), (w - 1 - c, h - 1), (c, h - 1), (0, h - 1 - c), (0, c)]


def metal_plate(w, h, c, rim, hi, top, bottom, grain=0.04, seed=0, inner=None, inner_w=1, rim2=None):
    """chamfered dark-metal plate: gradient fill, 1 px rim with a top highlight, optional inner line"""
    s = 4
    big = Image.new('RGBA', (w * s, h * s), (0, 0, 0, 0))
    md = ImageDraw.Draw(big)
    poly = [(x * s, y * s) for x, y in chamfer_poly(w, h, c)]
    md.polygon(poly, fill=(255, 255, 255, 255))
    mask = np.asarray(big.getchannel('A').resize((w, h), Image.LANCZOS), np.float32) / 255.0
    yy = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    fill = np.asarray(top, np.float32) * (1 - yy) + np.asarray(bottom, np.float32) * yy
    fill = np.broadcast_to(fill, (h, w, 3)).copy()
    rg = np.random.RandomState(seed)
    fill += (rg.randn(h, w, 1) * grain * 255).astype(np.float32)
    # rim: distance to the edge via erosion of the mask
    rimmask = Image.new('L', (w * s, h * s), 0)
    rd = ImageDraw.Draw(rimmask)
    rd.polygon(poly, outline=255, width=s)
    rm = np.asarray(rimmask.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    hi_amt = np.linspace(1, 0.15, h, dtype=np.float32)[:, None, None]
    rimcol = np.asarray(rim, np.float32) * (1 - hi_amt) + np.asarray(hi, np.float32) * hi_amt
    out = fill * (1 - rm[..., None]) + rimcol * rm[..., None]
    if inner is not None:
        im2 = Image.new('L', (w * s, h * s), 0)
        d2 = ImageDraw.Draw(im2)
        k = 2 + inner_w
        ins = chamfer_poly(w - 2 * k, h - 2 * k, max(1, c - k + 1))
        d2.polygon([((x + k) * s, (y + k) * s) for x, y in ins], outline=255, width=max(1, inner_w * s))
        a = np.asarray(im2.resize((w, h), Image.LANCZOS), np.float32) / 255.0
        out = out * (1 - a[..., None] * 0.9) + np.asarray(inner, np.float32) * a[..., None] * 0.9
    arr = np.dstack([np.clip(out, 0, 255), mask * 255]).astype(np.uint8)
    return Image.fromarray(arr, 'RGBA')


def gen_panel():
    # 9-slice (border 26): dark framed plate with an inner red line and corner studs
    w, h, c = 180, 120, 14
    im = metal_plate(w, h, c, IRON3, IRON5, (30, 24, 27), (14, 11, 13), 0.035, 1, inner=BLOOD_LO, inner_w=1)
    d = ImageDraw.Draw(im)
    # inner shadow line and corner studs
    for x, y in [(c + 2, 4), (w - c - 3, 4), (c + 2, h - 5), (w - c - 3, h - 5)]:
        d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=BLOOD)
    # second, darker inner border for the recessed look
    save(im, os.path.join(UI_OUT, 'panel.png'))


def gen_crest():
    """pointed notch at the middle of the top and bottom edge of the panel"""
    w, h = 96, 22
    im = px_image(w * 4, h * 4)
    d = ImageDraw.Draw(im)
    s = 4
    pts = [(0, 0), (w * 0.28, 0), (w * 0.5, h * 0.95), (w * 0.72, 0), (w, 0)]
    d.polygon([(x * s, y * s) for x, y in pts], fill=IRON1 + (255,))
    d.line([(x * s, y * s) for x, y in pts[1:4]], fill=IRON4 + (255,), width=2 * s)
    d.line([(w * 0.5 * s, 2 * s), (w * 0.5 * s, (h * 0.7) * s)], fill=BLOOD + (255,), width=s)
    d.ellipse(((w * 0.5 - 3) * s, (h * 0.55 - 3) * s, (w * 0.5 + 3) * s, (h * 0.55 + 3) * s), fill=BLOOD_HI + (255,))
    im = im.resize((w, h), Image.LANCZOS)
    save(im, os.path.join(UI_OUT, 'crest.png'))
    save(im.transpose(Image.FLIP_TOP_BOTTOM), os.path.join(UI_OUT, 'crest_bottom.png'))


def rune_path(kind, cx, cy, r):
    """strokes of two original angular runes (lists of polylines)"""
    k = r * 0.5
    if kind == 0:     # forked stave with an angled arm
        return [[(cx - k * 0.1, cy - k * 1.2), (cx - k * 0.1, cy + k * 1.2)],
                [(cx - k * 0.1, cy - k * 0.4), (cx + k * 0.9, cy - k * 1.1)],
                [(cx - k * 0.1, cy + 0.1 * k), (cx + k * 0.9, cy - k * 0.55)]]
    return [[(cx - k * 0.7, cy - k * 1.2), (cx - k * 0.7, cy + k * 1.2)],
            [(cx - k * 0.7, cy - k * 1.2), (cx + k * 0.8, cy - k * 0.3), (cx - k * 0.7, cy + k * 0.4)],
            [(cx - k * 0.1, cy + k * 0.2), (cx + k * 0.9, cy + k * 1.2)]]


def gen_medallion(kind, name):
    w = h = 64
    s = 4
    big = Image.new('RGBA', (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    cx, cy = w / 2, h / 2
    # pointed hexagonal body (spikes up and down)
    body = [(cx, 1), (w - 8, 14), (w - 3, cy), (w - 8, h - 14), (cx, h - 1), (8, h - 14), (3, cy), (8, 14)]
    d.polygon([(x * s, y * s) for x, y in body], fill=IRON1 + (255,))
    d.line([(x * s, y * s) for x, y in body + [body[0]]], fill=IRON4 + (255,), width=3 * s)
    inner = [(cx, 6), (w - 12, 17), (w - 8, cy), (w - 12, h - 17), (cx, h - 6), (12, h - 17), (8, cy), (12, 17)]
    d.polygon([(x * s, y * s) for x, y in inner], fill=(46, 6, 7, 255))
    d.line([(x * s, y * s) for x, y in inner + [inner[0]]], fill=BLOOD_LO + (255,), width=2 * s)
    # glow of the rune
    glow = Image.new('RGBA', big.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    strokes = rune_path(kind, cx, cy, 24)
    for st in strokes:
        gd.line([(x * s, y * s) for x, y in st], fill=(255, 60, 30, 255), width=7 * s)
    glow = glow.filter(ImageFilter.GaussianBlur(5 * s))
    big = Image.alpha_composite(big, glow)
    d = ImageDraw.Draw(big)
    for st in strokes:
        d.line([(x * s, y * s) for x, y in st], fill=(255, 92, 54, 255), width=3 * s)
        d.line([(x * s, y * s) for x, y in st], fill=(255, 190, 140, 255), width=1 * s)
    # spike highlights
    d.line([(cx * s, 1 * s), ((w - 8) * s, 14 * s)], fill=IRON5 + (255,), width=s)
    save(big.resize((w, h), Image.LANCZOS), os.path.join(UI_OUT, name))


def gen_buttons():
    # 9-slice, border 9, 54x30
    w, h, c = 54, 30, 6
    sets = {
        'normal': ((98, 88, 92), (150, 138, 140), (46, 38, 42), (22, 18, 20), None),
        'hover': ((150, 118, 100), (230, 190, 150), (66, 40, 38), (30, 18, 18), (120, 20, 14)),
        'pressed': ((60, 52, 56), (80, 70, 74), (16, 13, 15), (30, 24, 27), None),
        'disabled': ((52, 46, 48), (70, 62, 64), (24, 20, 22), (16, 13, 15), None),
    }
    for kind, (rim, hi, top, bot, inner) in sets.items():
        save(metal_plate(w, h, c, rim, hi, top, bot, 0.03, 2, inner=inner), os.path.join(UI_OUT, f'btn_{kind}.png'))
    red = {
        'normal': ((150, 40, 30), (236, 100, 70), (58, 18, 18), (26, 9, 10), (90, 14, 12)),
        'hover': ((220, 70, 44), (255, 170, 120), (92, 24, 20), (40, 12, 12), (170, 30, 20)),
        'pressed': ((110, 28, 22), (150, 50, 40), (26, 8, 8), (44, 14, 14), None),
    }
    for kind, (rim, hi, top, bot, inner) in red.items():
        save(metal_plate(w, h, c, rim, hi, top, bot, 0.03, 3, inner=inner), os.path.join(UI_OUT, f'btn_red_{kind}.png'))


def gen_fields():
    # 9-slice, border 6, 40x24: recessed dark field
    w, h, c = 40, 24, 3
    for kind, rim, hi, top, bot, inner in [
        ('', (88, 78, 82), (120, 108, 110), (6, 5, 7), (14, 11, 13), None),
        ('_focus', (190, 70, 46), (250, 130, 90), (10, 5, 6), (24, 8, 9), (90, 14, 12)),
        ('_pass', (120, 40, 34), (170, 60, 48), (24, 6, 8), (36, 9, 11), None),
        ('_pass_focus', (210, 80, 52), (255, 150, 100), (30, 7, 9), (44, 10, 12), (110, 18, 14)),
    ]:
        save(metal_plate(w, h, c, rim, hi, top, bot, 0.02, 4, inner=inner), os.path.join(UI_OUT, f'field{kind}.png'))



PRESS_SIZE = (960, 112)                   # 2x the bar's size on a 1920x1080 screen; login.lua scales it


def gen_pressplate():
    """the "Press any key to start" bar, as painted in the artwork: a dark translucent band fading out at both ends
    with thin gold-iron lines along its edges and a small diamond on the lower line (presskey.png), and the words in
    pale parchment serif capitals in the same frame (presskey_text.png; login.lua pulses it, and shows its own label
    on the plate instead when the text is translated). The client's font atlas has no room for another font, so the
    serif lettering is an image (Liberation Serif, or the first serif font found)."""
    w, h = PRESS_SIZE
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = np.abs(xx - (w - 1) / 2) / (w / 2)                   # 0 centre .. 1 ends
    fade = 1 - smooth(0.68, 1.0, u)
    body = smooth(0, 6, yy) * smooth(0, 6, h - 1 - yy)
    rgb = np.zeros((h, w, 3), np.float32)
    rgb[:] = (10, 7, 8)
    a = body * fade * 0.78
    line_fade = 1 - smooth(0.45, 0.97, u)
    for y in (4, h - 6):
        ln = np.exp(-((yy - y) / 1.3) ** 2) * line_fade
        rgb = rgb * (1 - ln[..., None]) + np.array((150, 122, 82), np.float32) * ln[..., None]
        a = np.maximum(a, ln * 0.95)
    cx, cy = (w - 1) / 2, h - 6
    dm = smooth(0, 0.25, np.clip(1 - (np.abs(xx - cx) / 14 + np.abs(yy - cy) / 8), 0, 1))
    rgb = rgb * (1 - dm[..., None]) + np.array((214, 182, 120), np.float32) * dm[..., None]
    a = np.maximum(a, dm)
    arr = np.dstack([np.clip(rgb, 0, 255), np.clip(a, 0, 1) * 255]).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'presskey.png'))
    # the words
    path = _find_font(SERIF_FILES)
    txt = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    if path:
        text, cap = 'PRESS ANY KEY TO START', 36           # cap height in px (2x)
        font = ImageFont.truetype(path, int(cap / 0.66))
        m = Image.new('L', (w, h), 0)
        d = ImageDraw.Draw(m)
        spacing = 3
        widths = [d.textlength(c, font=font) for c in text]
        total = sum(widths) + spacing * (len(text) - 1)
        x = (w - total) / 2
        for c, cw in zip(text, widths):
            d.text((x, h / 2 - 2), c, font=font, fill=255, anchor='lm')
            x += cw + spacing
        al = np.asarray(m, np.float32) / 255
        sh = np.asarray(m.filter(ImageFilter.GaussianBlur(2.5)), np.float32) / 255
        sh = np.roll(sh, 2, 0)
        col = np.zeros((h, w, 3), np.float32)
        col[:] = (233, 220, 192)
        alpha = np.clip(al + sh * (1 - al) * 0.8, 0, 1)
        col = col * (al / np.maximum(alpha, 1e-3))[..., None]
        txt = Image.fromarray(np.dstack([col, alpha * 255]).astype(np.uint8), 'RGBA')
    else:
        print('no serif font found (%s): presskey_text.png left empty' % ', '.join(SERIF_FILES))
    save(txt, os.path.join(UI_OUT, 'presskey_text.png'))


def gen_spinner():
    """12 frames (32x32 each, side by side) of a pale ring with a bright head, as the artwork's loading spinner"""
    n, fr, ss = 32, 12, 4
    sheet = Image.new('RGBA', (n * fr, n), (0, 0, 0, 0))
    N = n * ss
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    c = (N - 1) / 2
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / ss
    ring = np.clip(1 - np.abs(r - 13.0) / 1.9, 0, 1)
    ang = np.arctan2(yy - c, xx - c)
    for i in range(fr):
        head = 2 * math.pi * i / fr
        d = (head - ang) % (2 * math.pi)                     # 0 at the head, growing backwards along the tail
        tail = np.clip(1 - d / (1.6 * math.pi), 0, 1) ** 1.6
        a = ring * (0.18 + 0.82 * tail)
        arr = np.zeros((N, N, 4), np.float32)
        arr[..., 0], arr[..., 1], arr[..., 2] = 232, 222, 204
        arr[..., 3] = a * 255
        im = Image.fromarray(arr.astype(np.uint8), 'RGBA').resize((n, n), Image.LANCZOS)
        sheet.paste(im, (i * n, 0))
    save(sheet, os.path.join(UI_OUT, 'spinner.png'))


SERIF_FILES = ('LiberationSerif-Regular.ttf', 'DejaVuSerif.ttf', 'FreeSerif.ttf')


def _find_font(names):
    dirs = [d for d in os.environ.get('CHAOS_ART_FONTS', '').split(os.pathsep) if d]
    dirs += ['/usr/share/fonts', '/usr/local/share/fonts', os.path.expanduser('~/.fonts'), 'C:/Windows/Fonts',
             '/Library/Fonts', '/System/Library/Fonts']
    for name in names:
        for d in dirs:
            for root, _, files in os.walk(d):
                if name in files:
                    return os.path.join(root, name)
    return None


def gen_ember():
    n = 16
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    r = np.sqrt((xx - 7.5) ** 2 + (yy - 7.5) ** 2)
    a = np.clip(1 - r / 7.5, 0, 1) ** 2.2
    arr = np.zeros((n, n, 4), np.uint8)
    arr[..., 0] = 255
    arr[..., 1] = (140 + 100 * a).astype(np.uint8)
    arr[..., 2] = (30 + 90 * a ** 2).astype(np.uint8)
    arr[..., 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'ember.png'))



def gen_spark():
    """small hot spark (white-yellow core) for the sparks that leave the burning title"""
    n = 12
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    r = np.sqrt((xx - 5.5) ** 2 + (yy - 5.5) ** 2)
    core = np.clip(1 - r / 2.6, 0, 1) ** 1.2
    halo = np.clip(1 - r / 5.8, 0, 1) ** 2.0
    a = np.clip(core + halo * 0.55, 0, 1)
    arr = np.zeros((n, n, 4), np.uint8)
    arr[..., 0] = 255
    arr[..., 1] = (110 + 140 * core).astype(np.uint8)
    arr[..., 2] = (24 + 200 * core ** 2).astype(np.uint8)
    arr[..., 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'spark.png'))


def gen_ash():
    """grey ash flake (ragged, soft) that drifts down over the scene"""
    n = 12
    rng = np.random.RandomState(17)
    big = Image.new('L', (n * 4, n * 4), 0)
    d = ImageDraw.Draw(big)
    pts = []
    for i in range(9):
        a = 2 * math.pi * i / 9
        rr = n * 4 * 0.5 * (0.45 + 0.5 * rng.rand())
        pts.append((n * 2 + math.cos(a) * rr, n * 2 + math.sin(a) * rr * 0.7))
    d.polygon(pts, fill=255)
    a = np.asarray(big.filter(ImageFilter.GaussianBlur(2.5)).resize((n, n), Image.LANCZOS), np.float32) / 255
    arr = np.zeros((n, n, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = 150, 140, 136
    arr[..., 3] = (a * 200).astype(np.uint8)
    save(Image.fromarray(arr, 'RGBA'), os.path.join(UI_OUT, 'ash.png'))


# ------------------------------------------------------------------ letter shapes
# The gothic capitals of the earlier procedural wordmark, drawn as polygons in a 100 x 140 unit box (y down). The
# login screen now uses the logo of the artwork; website/tools/gen_site_art.py still draws its favicon from the C.
def _chaikin_open(pts, it=3):
    pts = list(pts)
    for _ in range(it):
        new = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            new.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            new.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        new.append(pts[-1])
        pts = new
    return pts


def _arc(cx, cy, rx, ry, a0, a1, n=18):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def glyphs():
    """letter -> (draw(d, ox, oy, k), width in units)"""
    def mk(fn):
        def draw(d, ox, oy, k):
            P = lambda pts: [(ox + x * k, oy + y * k) for x, y in pts]
            fn(d, P, ox, oy, k)
        return draw

    def stem(d, P, x=0, top=True, bottom=True):
        d.polygon(P([(x, 0), (x + 12, -16 if top else 0), (x + 24, 0), (x + 24, 140), (x + 12, 154 if bottom else 140),
                     (x, 140)]), fill=255)

    def Hf(d, P, ox, oy, k):
        stem(d, P, 0)
        stem(d, P, 76)
        d.polygon(P([(24, 56), (76, 56), (76, 70), (50, 86), (24, 70)]), fill=255)
        d.polygon(P([(24, 76), (50, 92), (76, 76), (76, 84), (24, 84)]), fill=255)

    def Af(d, P, ox, oy, k):
        d.polygon(P([(0, 140), (44, -6), (50, -26), (56, -6), (100, 140), (74, 140), (50, 40), (26, 140)]), fill=255)
        d.polygon(P([(24, 84), (76, 84), (80, 100), (20, 100)]), fill=255)
        d.polygon(P([(0, 140), (14, 156), (26, 140)]), fill=255)
        d.polygon(P([(74, 140), (86, 156), (100, 140)]), fill=255)

    def Of(d, P, ox, oy, k):
        d.ellipse([ox, oy, ox + 100 * k, oy + 140 * k], fill=255)
        d.ellipse([ox + 28 * k, oy + 30 * k, ox + 72 * k, oy + 110 * k], fill=0)
        d.polygon(P([(38, 2), (50, -22), (62, 2)]), fill=255)
        d.polygon(P([(38, 138), (50, 162), (62, 138)]), fill=255)
        d.polygon(P([(50, 56), (58, 70), (50, 84), (42, 70)]), fill=255)

    def Cf(d, P, ox, oy, k):
        d.ellipse([ox, oy, ox + 100 * k, oy + 140 * k], fill=255)
        d.ellipse([ox + 26 * k, oy + 28 * k, ox + 74 * k, oy + 112 * k], fill=0)
        d.polygon(P([(50, 70), (150, -10), (150, 150)]), fill=0)
        d.polygon(P([(88, 22), (112, 6), (94, 40)]), fill=255)
        d.polygon(P([(88, 118), (112, 134), (94, 100)]), fill=255)
        d.polygon(P([(30, 2), (42, -20), (54, 2)]), fill=255)

    def Sf(d, P, ox, oy, k):
        pts = _chaikin_open([(86, 26), (66, 6), (36, 4), (16, 26), (28, 52), (60, 70), (84, 92), (78, 120), (54, 138),
                             (24, 134), (8, 112)], 3)
        Q = P(pts)
        w = int(23 * k)
        d.line(Q, fill=255, width=w, joint='curve')
        r = w / 2
        for (x, y) in Q[::2]:
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        for (x, y, dx, dy) in ((86, 26, 18, -6), (8, 112, -14, 12)):
            X, Y = ox + x * k, oy + y * k
            d.polygon([(X - 12 * k, Y - 10 * k), (X + dx * k, Y + dy * k), (X + 12 * k, Y + 10 * k)], fill=255)

    def If(d, P, ox, oy, k):
        stem(d, P, 10)
        d.polygon(P([(0, -2), (44, -2), (34, 14), (10, 14)]), fill=255)
        d.polygon(P([(10, 126), (34, 126), (44, 142), (0, 142)]), fill=255)

    def Nf(d, P, ox, oy, k):
        stem(d, P, 0, bottom=False)
        stem(d, P, 76, top=False)
        d.polygon(P([(0, 0), (26, 0), (100, 140), (74, 140)]), fill=255)

    def Df(d, P, ox, oy, k):
        d.polygon(P([(12, 0), (50, 0)] + _arc(50, 70, 48, 70, -90, 90) + [(12, 140)]), fill=255)
        d.polygon(P([(24, 26), (48, 26)] + _arc(48, 70, 26, 44, -90, 90) + [(24, 114)]), fill=0)
        stem(d, P, 0)
        d.polygon(P([(94, 58), (110, 70), (94, 82)]), fill=255)

    def bar_top(d, P, right):
        d.polygon(P([(24, 0), (right, 0), (right - 8, 24), (24, 24)]), fill=255)
        d.polygon(P([(right - 14, 0), (right, 0), (right + 2, 36)]), fill=255)

    def bar_mid(d, P, right):
        d.polygon(P([(24, 58), (right - 14, 58), (right, 70), (right - 14, 82), (24, 82)]), fill=255)

    def Ef(d, P, ox, oy, k):
        stem(d, P, 0)
        bar_top(d, P, 92)
        bar_mid(d, P, 80)
        d.polygon(P([(24, 116), (84, 116), (92, 140), (24, 140)]), fill=255)
        d.polygon(P([(78, 140), (94, 140), (96, 102)]), fill=255)

    def Ff(d, P, ox, oy, k):
        stem(d, P, 0)
        bar_top(d, P, 90)
        bar_mid(d, P, 78)

    def Rf(d, P, ox, oy, k):
        d.polygon(P([(12, 0), (56, 0)] + _arc(56, 41, 40, 41, -90, 90) + [(12, 82)]), fill=255)
        d.polygon(P([(24, 22), (54, 22)] + _arc(54, 41, 20, 19, -90, 90) + [(24, 60)]), fill=0)
        stem(d, P, 0)
        d.polygon(P([(40, 70), (66, 70), (100, 140), (74, 140)]), fill=255)
        d.polygon(P([(74, 140), (86, 156), (100, 140)]), fill=255)

    return {'C': (mk(Cf), 100), 'H': (mk(Hf), 100), 'A': (mk(Af), 100), 'O': (mk(Of), 100), 'S': (mk(Sf), 100),
            'I': (mk(If), 44), 'N': (mk(Nf), 100), 'D': (mk(Df), 104), 'E': (mk(Ef), 94), 'R': (mk(Rf), 100),
            'F': (mk(Ff), 90)}




def ember_ramp(h):
    """0..1 heat -> rgb 0..255: dull red, crimson, orange, yellow, white-hot"""
    stops = [(0.0, (70, 8, 4)), (0.3, (176, 28, 8)), (0.55, (246, 86, 16)), (0.8, (255, 170, 60)),
             (1.0, (255, 238, 186))]
    out = np.zeros(h.shape + (3,), np.float32)
    for i in range(3):
        out[..., i] = np.interp(h, [s[0] for s in stops], [s[1][i] for s in stops])
    return out



def gen_logo():
    base, hot = make_wordmark()
    save(base, os.path.join(IMG, 'chaos', 'logo.png'))
    save(base.resize((LOGO_W // 2, LOGO_H // 2), Image.LANCZOS), os.path.join(IMG, 'chaos', 'logo_small.png'))
    save(hot, os.path.join(UI_OUT, 'logo_hot.png'))
    # the stock login screen's own logo slot (hidden by client_chaos_login, 225 x 261)
    ui = Image.new('RGBA', (225, 261), (0, 0, 0, 0))
    sm = base.resize((225, round(225 * LOGO_H / LOGO_W)), Image.LANCZOS)
    ui.alpha_composite(sm, (0, (261 - sm.height) // 2))
    save(ui, os.path.join(IMG, 'ui', 'logo.png'))


def gen_brand():
    """docs/brand/: the logo on transparency (trimmed, 2x), on black, and a square icon on black"""
    base, _ = make_wordmark()
    box = base.getchannel('A').point(lambda v: 255 if v > 6 else 0).getbbox()
    lg = base.crop(box)
    pad = 24
    tr = Image.new('RGBA', (lg.width + 2 * pad, lg.height + 2 * pad), (0, 0, 0, 0))
    tr.alpha_composite(lg, (pad, pad))
    save(tr, os.path.join(BRAND_OUT, 'cinders_logo.png'))
    blk = Image.new('RGBA', tr.size, (0, 0, 0, 255))
    blk.alpha_composite(tr)
    save(blk.convert('RGB'), os.path.join(BRAND_OUT, 'cinders_logo_black.png'))
    n = 1024
    icon = Image.new('RGBA', (n, n), (0, 0, 0, 255))
    # a faint ember glow behind it, then the logo at 94% of the width
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    g = np.exp(-(((xx - n / 2) / (n * 0.42)) ** 2 + ((yy - n / 2) / (n * 0.30)) ** 2))
    glow = np.zeros((n, n, 4), np.uint8)
    glow[..., 0], glow[..., 1], glow[..., 2] = 120, 30, 8
    glow[..., 3] = (g * 90).astype(np.uint8)
    icon.alpha_composite(Image.fromarray(glow, 'RGBA'))
    s = n * 0.94 / lg.width
    sm = lg.resize((round(lg.width * s), round(lg.height * s)), Image.LANCZOS)
    icon.alpha_composite(sm, ((n - sm.width) // 2, (n - sm.height) // 2))
    save(icon.convert('RGB'), os.path.join(BRAND_OUT, 'cinders_logo_icon.png'))


def gen_ui():
    gen_panel()
    gen_crest()
    gen_medallion(0, 'medallion_left.png')
    gen_medallion(1, 'medallion_right.png')
    gen_buttons()
    gen_fields()
    gen_pressplate()
    gen_spinner()
    gen_ember()
    gen_spark()
    gen_ash()


def gen_bg():
    bg, glow = make_background()
    save(bg, os.path.join(IMG, 'title.png'))
    save(glow, os.path.join(UI_OUT, 'glow.png'))


if __name__ == '__main__':
    tasks = sys.argv[1:] or ['bg', 'ui', 'logo', 'brand']
    for t in tasks:
        {'bg': gen_bg, 'ui': gen_ui, 'logo': gen_logo, 'brand': gen_brand}[t]()
