#!/usr/bin/env python3
"""Art of the two alternative interface skins of the Cinders of Chaos client (client/MANIFEST.md "Interface skins").

  forge  "Forge and Embers"  (Forged Iron and Embers): void black, iron slabs with riveted corner plates, ember orange
                              cracks under titles, notched tabs with an ember cap, a spiked iron orb ring.
  abyss  "Abyssal Arcane"    (Abyssal Arcane): flat obsidian with 1 px gold hairlines, filigree only at the corners,
                              chamfered buttons, underline tabs, thin violet scroll bars, a thin gold orb ring with
                              teal ticks and four diamond studs.

The classic look is the client's own art (gen_skin.py, gen_ui_reskin.py); it is not touched here. Each skin is a folder
of images in overlay/data/skins/<id>/ that mirrors the client's virtual paths: images/chaos/window.png shadows
/images/chaos/window.png, modules/game_shaderfx/images/orb_ring_150.png shadows that module's ring. Every image has the
size and 9-slice borders of the classic image it replaces, so no style changes. skin_boot.lua copies the folder in
front of the client's files at start (skin_core.lua explains the mechanism). manifest.lua lists the files and a revision.

All art is drawn here with Pillow, pixel by pixel, no source images: flat colours, 1 px bevels and hairlines, hard
edges. The orb rings are drawn at 1x and doubled (a ring is 2x its orb size, shaderfx draws it smoothed 2x2 -> crisp).
The stock sheets whose layout the base client owns (miniwindow buttons, arrows, check boxes, ...) are recoloured from
the classic images in the overlay through the skin's two colour ramps (neutral and accent); saturated pixels
that are not gold (status icons) are kept.

Usage: python3 client/tools/gen_skin_variants.py [--check] [--preview DIR]   (Pillow only; not -I)
  no flag   write the images, the manifests and the classic copy of the primary button sheet
  --check   nothing written; exit 1 when a committed file differs in pixels, is missing, is left over, has another
            size than the classic image it shadows, or a manifest is out of date
  --preview DIR  write DIR/skins_preview_<classic|forge|abyss>.png (frames drawn the way the engine 9-slices them)
"""
import colorsys
import hashlib
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OVERLAY = os.path.normpath(os.path.join(HERE, '..', 'overlay'))
DATA = os.path.join(OVERLAY, 'data')
IMAGES = os.path.join(DATA, 'images')
SKINS = os.path.join(DATA, 'skins')
SKIN_IDS = ('forge', 'abyss')
PRIMARY_CLASSIC = 'images/chaos/skin/button_primary.png'   # classic copy of button.png (same look as Button)


# ============================================================== pixel toolkit
def C(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))


def new(w, h, fill=(0, 0, 0, 0)):
    return Image.new('RGBA', (w, h), fill)


def R(im, x, y, w, h, c):
    if w > 0 and h > 0:
        ImageDraw.Draw(im).rectangle([x, y, x + w - 1, y + h - 1], fill=c)


def px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


def box(im, x, y, w, h, c):
    """1 px outline"""
    R(im, x, y, w, 1, c)
    R(im, x, y + h - 1, w, 1, c)
    R(im, x, y, 1, h, c)
    R(im, x + w - 1, y, 1, h, c)


def shape(im, x, y, w, h, c, n=0):
    """a filled rectangle with its corners cut by n pixels at 45 degrees"""
    for r in range(h):
        inset = max(n - r, n - (h - 1 - r), 0)
        R(im, x + inset, y + r, w - 2 * inset, 1, c)


def vgrad(im, x, y, w, h, c0, c1):
    for r in range(h):
        R(im, x, y + r, w, 1, mix(c0, c1, r / max(h - 1, 1)))


def over(dst, src, x=0, y=0):
    dst.alpha_composite(src, (x, y)) if x >= 0 and y >= 0 else dst.alpha_composite(src.crop((max(-x, 0), max(-y, 0), src.width, src.height)), (max(x, 0), max(y, 0)))


def stack(*ims):
    out = new(ims[0].width, sum(i.height for i in ims))
    y = 0
    for i in ims:
        out.paste(i, (0, y))
        y += i.height
    return out


def mirror(im, fx, fy):
    if fx:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if fy:
        im = im.transpose(Image.FLIP_TOP_BOTTOM)
    return im


def diamond(im, cx, cy, r, c):
    for dy in range(-r, r + 1):
        w = r - abs(dy)
        R(im, cx - w, cy + dy, 2 * w + 1, 1, c)


def disc(im, cx, cy, r, c):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= r:
                px(im, x, y, c)


def arrow(im, cx, cy, direction, c, r=3):
    """a pixel triangle of 2r+1 columns, pointing up/down/left/right, centred on (cx, cy)"""
    for k in range(r + 1):
        w = k
        if direction == 'up':
            R(im, cx - w, cy - r // 2 + k, 2 * w + 1, 1, c)
        elif direction == 'down':
            R(im, cx - w, cy + r // 2 - k, 2 * w + 1, 1, c)
        elif direction == 'left':
            R(im, cx - r // 2 + k, cy - w, 1, 2 * w + 1, c)
        else:
            R(im, cx + r // 2 - k, cy - w, 1, 2 * w + 1, c)


def polyline(im, pts, c):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            px(im, round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), c)


# ============================================================== recolour of the classic stock sheets
def lerp_ramp(ramp, t):
    t = max(0.0, min(1.0, t)) * (len(ramp) - 1)
    i = min(int(t), len(ramp) - 2)
    return mix(ramp[i], ramp[i + 1], t - i)


def recolor(src, neutral, accent):
    """classic image -> skin colours: neutral pixels through the neutral ramp by brightness, gold pixels through the
    accent ramp, other saturated pixels (status icons, red, green, blue) unchanged. Alpha is kept."""
    out = src.convert('RGBA').copy()
    pix = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = pix[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            if s >= 0.30 and 0.03 <= h <= 0.20:
                c = lerp_ramp(accent, lum / 0.9)
            elif s >= 0.45:
                continue
            else:
                c = lerp_ramp(neutral, lum / 0.75)
            pix[x, y] = (c[0], c[1], c[2], a)
    return out


# stock images (base client layouts) recoloured from the classic ones, relative to data/images/
RECOLOR = [
    'ui/miniwindow_buttons', 'ui/arrow_horizontal', 'ui/arrow_vertical', 'ui/regular_direction_button',
    'ui/console_direction_button', 'ui/browse-arrow-left', 'ui/browse-arrow-right', 'ui/rotate_button',
    'ui/miniborder', 'ui/separator_horizontal', 'ui/separator_vertical', 'ui/spinbox', 'ui/spinbox_up',
    'ui/spinbox_down', 'ui/checkbox', 'ui/checkboxcircle', 'ui/checkbox-checked', 'ui/checkbox-unchecked',
    'ui/checkbox-checked-disabled', 'ui/colorbox-border-13', 'ui/combobox_square', 'ui/combobox_rounded',
    'game/actionbar/arrow-down', 'game/actionbar/arrow-left', 'game/actionbar/arrow-right', 'game/actionbar/arrow-up',
    'game/actionbar/double-arrow-down', 'game/actionbar/double-arrow-left', 'game/actionbar/double-arrow-right',
    'game/actionbar/double-arrow-up',
    'common_buttons/add-button', 'common_buttons/apply-button', 'common_buttons/back-button',
    'common_buttons/cancel-button', 'common_buttons/clear-button', 'common_buttons/close-button',
    'common_buttons/copy-button', 'common_buttons/delete-button', 'common_buttons/new-button',
    'common_buttons/ok-button', 'common_buttons/open-button', 'common_buttons/refresh-button',
    'common_buttons/rename-button', 'common_buttons/reset-button', 'common_buttons/save-button',
    'common_buttons/send-button', 'common_buttons/small-apply-button',
]


# ============================================================== skin styles
class Style:
    """what every skin draws; the two skins differ in colours and in how each part is built"""
    name = ''
    NEUTRAL = ACCENT = ()
    P = {}

    # -- shared part: sheets built from faces
    def sheet(self, *faces):
        return stack(*faces)


class Forge(Style):
    name = 'forge'
    P = dict(
        void=C('#0b0908'), dk=C('#14110f'), lo=C('#1c1815'), iron=C('#2f2a26'), mid=C('#3a342f'), hi=C('#5c544b'),
        hi2=C('#7a6e60'), ash=C('#d8ccb8'), ember=C('#ff7a1a'), ember_hi=C('#ffb347'), ember_lo=C('#8a3d0c'),
        ember_dk=C('#4a2008'), body=C('#17130f'), well=C('#0f0c0a'), red=C('#c2260f'), red_hi=C('#e8532f'),
        red_lo=C('#6a1208'), blue=C('#2d68b8'), blue_hi=C('#5b95e0'), blue_lo=C('#16355f'),
        rivet=C('#7a6a58'), rivet_hi=C('#d8ccb8'))
    NEUTRAL = [C('#0b0908'), C('#1c1815'), C('#2f2a26'), C('#5c544b'), C('#a09482')]
    ACCENT = [C('#2a1004'), C('#8a3d0c'), C('#ff7a1a'), C('#ffb347'), C('#ffe2b0')]

    # ---- windows
    def frame(self, W, H, L, T, Rr, B, title=True, crack=None, body=None):
        p = self.P
        im = new(W, H, p['void'])
        t = max(1, min(4, L - 1, Rr - 1, B - 1))
        R(im, 1, 1, W - 2, H - 2, p['iron'])
        R(im, 1, 1, W - 2, 1, p['hi'])          # light from the top left
        R(im, 1, 1, 1, H - 2, p['hi'])
        R(im, 1, H - 2, W - 2, 1, p['lo'])
        R(im, W - 2, 1, 1, H - 2, p['lo'])
        top = T if title else 1 + t
        if title:
            vgrad(im, 2, 2, W - 4, T - 6, p['mid'], p['iron'])
            cy = crack if crack is not None else T - 3
            R(im, 1, cy - 1, W - 2, 1, p['lo'])
            R(im, 1, cy, W - 2, 1, p['ember'])
            R(im, 1, cy + 1, W - 2, 1, p['ember_lo'])
            R(im, 1, cy + 2, W - 2, 1, p['void'])
            top = cy + 3
        bx, by, bw, bh = 1 + t, top, W - 2 - 2 * t, H - top - 1 - t
        R(im, bx - 1, by - 1, bw + 2, bh + 2, p['void'])   # the inset: a dark rim
        R(im, bx, by, bw, bh, body or p['body'])
        return im

    def orn_corner(self, blue=False):
        p = self.P
        im = new(44, 44)
        # a riveted square plate, 16 x 16, its rivet at (14, 14)
        R(im, 5, 5, 18, 18, p['void'])
        R(im, 6, 6, 16, 16, p['iron'])
        R(im, 6, 6, 16, 1, p['hi'])
        R(im, 6, 6, 1, 16, p['hi'])
        R(im, 6, 21, 16, 1, p['lo'])
        R(im, 21, 6, 1, 16, p['lo'])
        glow = p['blue'] if blue else p['ember']
        glow_lo = p['blue_lo'] if blue else p['ember_lo']
        R(im, 12, 12, 5, 5, p['void'])
        R(im, 13, 13, 3, 3, glow_lo)
        px(im, 14, 14, glow)
        px(im, 13, 13, p['ember_hi'] if not blue else p['blue_hi'])
        for x, y in ((8, 8), (19, 8), (8, 19), (19, 19)):
            px(im, x, y, p['rivet'])
        return im

    def crest(self):
        p = self.P
        im = new(84, 30)
        # an iron plaque with an ember eye, over the title bar
        shape(im, 22, 3, 40, 22, p['void'], 4)
        shape(im, 23, 4, 38, 20, p['iron'], 3)
        R(im, 26, 4, 32, 1, p['hi'])
        R(im, 26, 22, 32, 1, p['lo'])
        diamond(im, 42, 14, 6, p['void'])
        diamond(im, 42, 14, 5, p['ember_lo'])
        diamond(im, 42, 14, 3, p['ember'])
        diamond(im, 42, 14, 1, p['ember_hi'])
        for x in (27, 56):
            px(im, x, 14, p['rivet'])
            px(im, x, 13, p['rivet_hi'])
        return im

    # ---- panels and controls
    def panel(self, W, H, b, kind='inset'):
        p = self.P
        body = {'inset': p['body'], 'dark': p['dk'], 'raised': p['iron'], 'highlight': p['body'], 'flat': p['body'],
                'bar': p['iron']}[kind]
        im = new(W, H, p['void'])
        R(im, 1, 1, W - 2, H - 2, body)
        if b >= 2:
            hi, lo = (p['lo'], p['hi']) if kind in ('inset', 'dark') else (p['hi'], p['lo'])
            if kind == 'highlight':
                hi = lo = p['ember_lo']
            R(im, 1, 1, W - 2, 1, hi)
            R(im, 1, 1, 1, H - 2, hi)
            R(im, 1, H - 2, W - 2, 1, lo)
            R(im, W - 2, 1, 1, H - 2, lo)
        return im

    def button(self, W, H, b, state, primary=False):
        p = self.P
        im = new(W, H, p['void'])
        if primary:
            top, body0, body1, bot = {
                'normal': (p['ember_hi'], C('#f0700f'), C('#d9610f'), p['ember_lo']),
                'hover': (C('#ffd08a'), C('#ff8c33'), p['ember'], C('#b4520d')),
                'pressed': (p['ember_dk'], C('#a64a0d'), C('#8a3d0c'), p['void']),
                'disabled': (p['mid'], p['lo'], p['lo'], p['void']),
                'on': (p['ember_dk'], C('#a64a0d'), C('#8a3d0c'), p['void'])}[state]
            R(im, 1, 1, W - 2, H - 2, body1)
            vgrad(im, 1, 1, W - 2, (H - 2) // 2, body0, body1)
            R(im, 1, 1, W - 2, 1, top)
            R(im, 1, H - 2, W - 2, 1, bot)
            return im
        if state == 'normal':
            R(im, 1, 1, W - 2, H - 2, p['iron'])
            vgrad(im, 1, 1, W - 2, (H - 2) // 2, p['mid'], p['iron'])
            R(im, 1, 1, W - 2, 1, p['hi'])
            R(im, 1, H - 2, W - 2, 1, p['lo'])
        elif state == 'hover':
            R(im, 1, 1, W - 2, H - 2, C('#3d342d'))
            vgrad(im, 1, 1, W - 2, (H - 2) // 2, C('#52443a'), C('#3d342d'))
            R(im, 1, 1, W - 2, 1, p['hi2'])
            R(im, 1, H - 3, W - 2, 2, p['ember'])             # hotter, with an ember underline
        elif state in ('pressed', 'on'):
            box(im, 0, 0, W, H, p['ember'])
            R(im, 1, 1, W - 2, H - 2, p['dk'])
            R(im, 1, 1, W - 2, 1, p['void'])
        else:
            box(im, 0, 0, W, H, p['lo'])
            R(im, 1, 1, W - 2, H - 2, p['lo'])
            R(im, 1, 1, W - 2, 1, p['iron'])
        return im

    def tab(self, W, H, b, state):
        p = self.P
        im = new(W, H)
        body = {'normal': p['lo'], 'hover': p['mid'], 'on': p['iron']}[state]
        shape(im, 0, 0, W, H, p['void'], 2)
        shape(im, 1, 1, W - 2, H - 1, body, 1)
        R(im, 2, 1, W - 4, 1, p['hi'] if state != 'normal' else p['iron'])
        if state == 'on':
            R(im, 2, 1, W - 4, 2, p['ember'])                 # the ember cap
            R(im, 1, H - 1, W - 2, 1, body)                   # open at the bottom: it joins the panel
        elif state == 'hover':
            R(im, 2, H - 2, W - 4, 1, p['ember_lo'])
        return im

    def slot(self, w, h=None, rim=None):
        p = self.P
        h = w if h is None else h
        im = new(w, h, p['void'])
        R(im, 1, 1, w - 2, h - 2, rim or p['hi'])
        R(im, 2, 2, w - 4, h - 4, p['void'])
        R(im, 3, 3, w - 6, h - 6, p['well'])
        R(im, 3, 3, w - 6, 1, p['dk'])
        return im

    def text_field(self, W, H, focus=False):
        p = self.P
        im = new(W, H, p['void'])
        R(im, 1, 1, W - 2, H - 2, p['ember'] if focus else p['hi'])
        R(im, 2, 2, W - 4, H - 4, p['well'])
        R(im, 2, 2, W - 4, 1, p['void'])
        return im

    def checkbox(self, n):
        p = self.P
        cells = []
        for checked in (False, True):
            im = new(n, n, p['void'])
            R(im, 1, 1, n - 2, n - 2, p['hi'])
            R(im, 2, 2, n - 4, n - 4, p['well'])
            if checked:
                polyline(im, [(4, 8), (7, 11), (12, 4)], p['ember_hi'])
                polyline(im, [(4, 9), (7, 12), (12, 5)], p['ember'])
            cells.append(im)
        return stack(*cells)

    def combobox(self, W, H, rb):
        im = self.text_field(W, H)
        btn = self.button(rb - 2, H - 4, 3, 'normal')
        im.paste(btn, (W - rb, 2))
        arrow(im, W - rb + (rb - 2) // 2, H // 2, 'down', self.P['ember_hi'], 3)
        return im

    def scroll_button(self, state, direction):
        p = self.P
        im = self.button(13, 13, 3, state)
        arrow(im, 6, 6, direction, p['ember_hi'] if state == 'hover' else p['ember'], 3)
        return im

    def scroll_slider(self, state):
        p = self.P
        im = self.button(13, 17, 3, state)
        for y in (6, 8, 10):
            R(im, 3, y, 7, 1, p['ember_lo'] if state != 'hover' else p['ember'])
        return im

    def scroll_track(self):
        p = self.P
        im = new(13, 32, p['void'])
        R(im, 1, 0, 11, 32, p['well'])
        R(im, 1, 0, 1, 32, p['lo'])
        return im

    def progress_frame(self, W, H, b=3):
        p = self.P
        im = new(W, H, p['void'])
        R(im, 1, 1, W - 2, H - 2, p['hi'])
        R(im, 2, 2, W - 4, H - 4, p['void'])
        R(im, 3, 3, W - 6, H - 6, (11, 9, 8, 90))             # a translucent track: the fill shows through
        return im

    def title_plate(self, W, H):
        p = self.P
        im = self.button(W, H, 6, 'normal')
        R(im, 2, H - 4, W - 4, 1, p['ember'])
        R(im, 2, H - 3, W - 4, 1, p['ember_lo'])
        for x in (4, W - 6):
            R(im, x, H // 2 - 2, 2, 2, p['rivet'])
        return im

    def separator(self, W, H):
        p = self.P
        im = new(W, H)
        y = H // 2
        R(im, 4, y - 1, W - 8, 1, p['lo'])
        R(im, 4, y, W - 8, 1, p['ember_lo'])
        R(im, W // 2 - 8, y, 16, 1, p['ember'])
        for x in (3, W - 4):
            R(im, x - 1, y - 1, 3, 3, p['ember'])
        return im

    def topbar(self, W, H):
        p = self.P
        im = self.frame(W, H, 4, 4, 4, 4, title=False, body=p['dk'])
        R(im, 0, H - 3, W, 1, p['ember'])
        R(im, 0, H - 2, W, 1, p['ember_lo'])
        R(im, 0, H - 1, W, 1, p['void'])
        return im

    def menubar(self):
        p = self.P
        im = self.frame(64, 36, 8, 8, 8, 8, title=False, body=p['dk'])
        R(im, 4, 31, 56, 1, p['ember_lo'])
        return im

    def tooltip(self):
        p = self.P
        im = new(32, 32, p['void'])
        R(im, 1, 1, 30, 30, p['ember_lo'])
        R(im, 2, 2, 28, 28, p['body'])
        return im

    def menubox(self):
        im = self.panel(121, 116, 3, 'raised')
        p = self.P
        R(im, 2, 2, 117, 112, p['body'])
        R(im, 1, 1, 119, 1, p['ember_lo'])                    # the top two rows double as the menu separator
        return im

    def map_frame(self, n):
        p = self.P
        im = new(n, n, p['body'])
        box(im, 0, 0, n, n, p['void'])
        box(im, 1, 1, n - 2, n - 2, p['ember_lo'])
        box(im, 2, 2, n - 4, n - 4, p['mid'])
        box(im, 3, 3, n - 6, n - 6, p['void'])
        return im

    # ---- HUD
    def hud_chrome(self):
        """returns the plate image and the portrait ring colours"""
        p = self.P
        W, H = 300, 96
        im = new(W, H)
        shape(im, 47, 14, W - 47 - 6, 70, p['void'], 7)
        shape(im, 48, 15, W - 49 - 6, 68, p['iron'], 6)
        R(im, 56, 15, W - 70, 1, p['hi'])
        R(im, 56, 81, W - 70, 1, p['lo'])
        R(im, 56, 79, W - 70, 1, p['ember_lo'])
        R(im, 56, 80, W - 70, 1, p['ember'])
        for y, h in ((35, 15), (54, 13), (71, 5)):
            R(im, 94, y - 3, 170, h + 6, p['void'])
            R(im, 95, y - 2, 168, h + 4, p['hi'])
            R(im, 96, y - 1, 166, h + 2, p['well'])
        for x in (268, 270):
            R(im, x, 44, 2, 8, p['ember'])
        return im

    def hud_ring(self, im, hole_c):
        p = self.P
        cx, cy = 47, 48
        for y in range(96):
            for x in range(96):
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                if d < 30:
                    im.putpixel((x, y), hole_c)
                elif d < 31.5:
                    im.putpixel((x, y), p['ember'])
                elif d < 32.5:
                    im.putpixel((x, y), p['ember_lo'])
                elif d < 39:
                    t = (d - 32.5) / 6.5
                    im.putpixel((x, y), p['hi'] if t < 0.2 else (p['iron'] if t < 0.65 else p['mid']))
                elif d < 40:
                    im.putpixel((x, y), p['void'])
        for k in range(8):
            a = math.radians(22.5 + 45 * k)
            rx, ry = cx + math.cos(a) * 35.5, cy + math.sin(a) * 35.5
            disc(im, rx, ry, 1.9, p['void'])
            disc(im, rx, ry, 1.4, p['rivet'])
            px(im, int(rx), int(ry) - 1, p['rivet_hi'])

    def level_badge(self):
        im = self.button(40, 18, 4, 'on', primary=True)
        return im

    def fill(self, W, H, kind):
        p = self.P
        c0, c1, c2 = {'hp': (p['red_hi'], p['red'], p['red_lo']), 'mp': (p['blue_hi'], p['blue'], p['blue_lo']),
                      'xp': (p['ember_hi'], p['ember'], p['ember_lo'])}[kind]
        im = new(W, H)
        vgrad(im, 0, 0, W, H, c1, c2)
        R(im, 0, 0, W, 1, c0)
        return im

    # ---- orb ring
    def orb_ring(self, S, L):
        p = self.P
        rh = (L - 1) / 2.0
        outer = S / 2.0
        spike = max(3, int(round(S / 25.0)))
        base = outer - spike
        im = new(S, S)
        c = S / 2.0
        for y in range(S):
            for x in range(S):
                dx, dy = x + 0.5 - c, y + 0.5 - c
                d = math.hypot(dx, dy)
                if d < rh or d > outer:
                    continue
                col = None
                if d < rh + 1.5:
                    col = p['ember']
                elif d < rh + 2.5:
                    col = p['ember_lo']
                elif d < rh + 3.5:
                    col = p['void']
                elif d < base:
                    t = (d - rh - 3.5) / max(base - rh - 3.5, 1)
                    col = p['hi'] if t < 0.14 else (p['mid'] if t < 0.45 else (p['iron'] if t < 0.85 else p['lo']))
                    if d >= base - 1:
                        col = p['void']
                # spikes: four triangles on the compass points
                if col is None and d >= base - 1:
                    for ax, ay in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                        along = dx * ax + dy * ay
                        across = abs(dx * ay - dy * ax)
                        if along >= base - 1 and across <= (outer - along) * 1.2 + 0.4:
                            col = p['hi2'] if across < 0.9 else p['hi']
                            break
                if col is not None:
                    im.putpixel((x, y), col)
        rv = max(1.6, S / 60.0)
        rr = rh + 3.5 + (base - rh - 3.5) * 0.5
        for k in range(8):
            a = math.radians(22.5 + 45 * k)
            rx, ry = c + math.cos(a) * rr, c + math.sin(a) * rr
            disc(im, rx, ry, rv + 0.8, p['void'])
            disc(im, rx, ry, rv, p['rivet'])
            px(im, int(rx), int(ry) - 1, p['rivet_hi'])
        return im


class Abyss(Style):
    name = 'abyss'
    P = dict(
        void=C('#06070b'), obs=C('#0d1019'), obs2=C('#141a29'), obs3=C('#1c2234'), gold=C('#c9a45a'),
        gold_hi=C('#e8cf8a'), gold_lo=C('#6e5a2e'), gold_dk=C('#3a2f14'), violet=C('#8a5cf0'), vio_hi=C('#b394ff'),
        vio_lo=C('#4a2f8f'), vio_dk=C('#2a1a5c'), teal=C('#2fd0c0'), teal_lo=C('#17665f'), text=C('#d9d6e6'),
        red=C('#d23a5a'), red_hi=C('#ee7a92'), red_lo=C('#7c1e36'), blue=C('#25b5c8'), blue_hi=C('#7fe3ee'),
        blue_lo=C('#115866'))
    NEUTRAL = [C('#06070b'), C('#0d1019'), C('#1c2234'), C('#3a4260'), C('#8d89a3')]
    ACCENT = [C('#1e1808'), C('#6e5a2e'), C('#c9a45a'), C('#e8cf8a'), C('#fff3cf')]

    def frame(self, W, H, L, T, Rr, B, title=True, crack=None, body=None):
        p = self.P
        im = new(W, H, p['void'])
        R(im, 1, 1, W - 2, H - 2, p['gold'])                  # the hairline
        R(im, 2, 2, W - 4, H - 4, body or p['obs'])
        if title:
            R(im, 2, 2, W - 4, T - 5, p['obs2'])
            cy = crack if crack is not None else T - 3
            R(im, 1, cy, W - 2, 1, p['gold'])
            R(im, 2, cy + 1, W - 4, 1, p['void'])
            R(im, 2, cy - 1, W - 4, 1, p['obs3'])
        return im

    def _filigree(self, im):
        p = self.P
        g, gh = p['gold'], p['gold_hi']
        # an L bracket along the two edges, a curl and a diamond stud at the corner
        R(im, 8, 8, 20, 1, g)
        R(im, 8, 8, 1, 20, g)
        R(im, 10, 10, 12, 1, p['gold_lo'])
        R(im, 10, 10, 1, 12, p['gold_lo'])
        polyline(im, [(22, 10), (24, 12), (24, 14)], g)
        polyline(im, [(10, 22), (12, 24), (14, 24)], g)
        diamond(im, 8, 8, 4, p['void'])
        diamond(im, 8, 8, 3, g)
        diamond(im, 8, 8, 1, gh)

    def orn_corner(self, blue=False):
        im = new(44, 44)
        self._filigree(im)
        if blue:
            diamond(im, 8, 8, 1, self.P['teal'])
        else:
            diamond(im, 8, 8, 1, self.P['violet'])
        return im

    def crest(self):
        p = self.P
        im = new(84, 30)
        R(im, 14, 15, 56, 1, p['gold'])
        R(im, 24, 17, 36, 1, p['gold_lo'])
        diamond(im, 42, 15, 8, p['void'])
        diamond(im, 42, 15, 7, p['gold'])
        diamond(im, 42, 15, 5, p['obs'])
        diamond(im, 42, 15, 3, p['violet'])
        px(im, 42, 15, p['teal'])
        for x in (11, 72):
            diamond(im, x, 15, 2, p['gold'])
        return im

    def panel(self, W, H, b, kind='inset'):
        p = self.P
        fill = {'inset': p['obs'], 'dark': p['void'], 'raised': p['obs2'], 'highlight': p['obs2'], 'flat': p['obs'],
                'bar': p['obs']}[kind]
        edge = {'highlight': p['gold'], 'raised': p['gold_lo'], 'dark': p['obs3']}.get(kind, p['gold_lo'])
        im = new(W, H, p['void'])
        R(im, 1, 1, W - 2, H - 2, edge)
        R(im, 2, 2, W - 4, H - 4, fill) if W > 4 and H > 4 else None
        if b <= 1:
            R(im, 1, 1, W - 2, H - 2, fill)
            box(im, 0, 0, W, H, edge)
        return im

    def button(self, W, H, b, state, primary=False):
        p = self.P
        n = 2 if min(W, H) >= 12 else 1
        im = new(W, H)
        if primary:
            edge, fill, inner = {
                'normal': (p['vio_hi'], p['vio_lo'], None), 'hover': (p['vio_hi'], p['violet'], p['teal']),
                'pressed': (p['teal'], p['vio_dk'], None), 'on': (p['teal'], p['vio_dk'], None),
                'disabled': (p['gold_dk'], p['obs'], None)}[state]
        else:
            edge, fill, inner = {
                'normal': (p['gold'], p['obs2'], None), 'hover': (p['gold_hi'], p['obs3'], p['teal']),
                'pressed': (p['teal'], p['void'], None), 'on': (p['teal'], p['void'], None),
                'disabled': (p['gold_dk'], p['obs'], None)}[state]
        shape(im, 0, 0, W, H, p['void'], n)
        shape(im, 0, 0, W, H, edge, n)
        shape(im, 1, 1, W - 2, H - 2, fill, max(n - 1, 0))
        if inner:
            R(im, 2 + n, 1, W - 4 - 2 * n, 1, inner)            # hover: a teal inner line along the top
        return im

    def tab(self, W, H, b, state):
        p = self.P
        im = new(W, H)
        fill = {'normal': p['obs'], 'hover': p['obs3'], 'on': p['obs2']}[state]
        R(im, 0, 0, W, H, fill)
        under = {'normal': p['obs3'], 'hover': p['vio_lo'], 'on': p['teal']}[state]
        R(im, 0, H - 2, W, 2, under)
        if state == 'on':
            R(im, 0, 0, W, 1, p['gold_lo'])
        return im

    def slot(self, w, h=None, rim=None):
        p = self.P
        h = w if h is None else h
        im = new(w, h, p['void'])
        R(im, 0, 0, w, h, p['void'])
        box(im, 0, 0, w, h, rim or p['gold_lo'])
        R(im, 1, 1, w - 2, h - 2, p['obs'])
        for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
            px(im, x, y, p['gold'] if rim is None else rim)
        return im

    def text_field(self, W, H, focus=False):
        p = self.P
        im = new(W, H, p['void'])
        box(im, 0, 0, W, H, p['teal'] if focus else p['gold_lo'])
        R(im, 1, 1, W - 2, H - 2, p['void'])
        R(im, 1, 1, W - 2, 1, p['obs'])
        return im

    def checkbox(self, n):
        p = self.P
        cells = []
        for checked in (False, True):
            im = new(n, n, p['void'])
            box(im, 0, 0, n, n, p['gold'])
            R(im, 1, 1, n - 2, n - 2, p['obs'])
            if checked:
                polyline(im, [(4, 8), (7, 11), (12, 4)], p['teal'])
                polyline(im, [(4, 9), (7, 12), (12, 5)], p['teal_lo'])
            cells.append(im)
        return stack(*cells)

    def combobox(self, W, H, rb):
        im = self.text_field(W, H)
        btn = self.button(rb - 2, H - 4, 3, 'normal')
        im.paste(btn, (W - rb, 2))
        arrow(im, W - rb + (rb - 2) // 2, H // 2, 'down', self.P['gold_hi'], 3)
        return im

    def scroll_button(self, state, direction):
        p = self.P
        im = new(13, 13)
        R(im, 1, 1, 11, 11, p['gold_lo'] if state != 'hover' else p['gold'])
        R(im, 2, 2, 9, 9, p['obs2'] if state != 'pressed' else p['void'])
        arrow(im, 6, 6, direction, p['gold_hi'] if state != 'pressed' else p['teal'], 3)
        return im

    def scroll_slider(self, state):
        p = self.P
        im = new(13, 17)
        body = {'normal': p['violet'], 'hover': p['vio_hi'], 'pressed': p['vio_lo']}[state]
        R(im, 3, 0, 7, 17, p['vio_dk'])                         # thin: 7 wide in a 13 wide part
        R(im, 4, 1, 5, 15, body)
        R(im, 4, 1, 1, 15, p['vio_hi'] if state != 'pressed' else p['violet'])
        return im

    def scroll_track(self):
        p = self.P
        im = new(13, 32)
        R(im, 5, 0, 3, 32, p['void'])
        R(im, 6, 0, 1, 32, p['obs3'])
        return im

    def progress_frame(self, W, H, b=3):
        p = self.P
        im = new(W, H, p['void'])
        box(im, 0, 0, W, H, p['gold_lo'])
        R(im, 1, 1, W - 2, H - 2, p['void'])
        R(im, 2, 2, W - 4, H - 4, (6, 7, 11, 90))
        return im

    def title_plate(self, W, H):
        p = self.P
        im = self.button(W, H, 6, 'normal')
        R(im, 8, H - 3, W - 16, 1, p['gold_lo'])
        diamond(im, W // 2, H - 3, 1, p['violet'])
        return im

    def separator(self, W, H):
        p = self.P
        im = new(W, H)
        y = H // 2
        R(im, 8, y, W - 16, 1, p['gold_lo'])
        R(im, W // 2 - 12, y, 24, 1, p['gold'])
        diamond(im, W // 2, y, 2, p['gold_hi'])
        diamond(im, W // 2, y, 0, p['violet'])
        diamond(im, 4, y, 1, p['gold'])
        diamond(im, W - 5, y, 1, p['gold'])
        return im

    def topbar(self, W, H):
        p = self.P
        im = new(W, H, p['obs'])
        R(im, 0, 0, W, 1, p['void'])
        R(im, 0, H - 3, W, 1, p['gold'])
        R(im, 0, H - 2, W, 2, p['void'])
        return im

    def menubar(self):
        p = self.P
        im = new(64, 36, p['void'])
        box(im, 1, 1, 62, 34, p['gold_lo'])
        R(im, 2, 2, 60, 32, p['obs'])
        for x, y in ((1, 1), (62, 1), (1, 34), (62, 34)):
            px(im, x, y, p['gold'])
        return im

    def tooltip(self):
        p = self.P
        im = new(32, 32, p['void'])
        box(im, 0, 0, 32, 32, p['gold'])
        R(im, 1, 1, 30, 30, p['obs'])
        R(im, 1, 1, 30, 1, p['violet'])
        return im

    def menubox(self):
        p = self.P
        im = new(121, 116, p['void'])
        box(im, 0, 0, 121, 116, p['gold_lo'])
        R(im, 1, 1, 119, 114, p['obs'])
        R(im, 1, 1, 119, 1, p['gold_lo'])                        # the top two rows double as the menu separator
        return im

    def map_frame(self, n):
        p = self.P
        im = new(n, n, p['obs'])
        box(im, 0, 0, n, n, p['void'])
        box(im, 1, 1, n - 2, n - 2, p['gold'])
        box(im, 2, 2, n - 4, n - 4, p['obs3'])
        box(im, 3, 3, n - 6, n - 6, p['void'])
        return im

    def hud_chrome(self):
        p = self.P
        W, H = 300, 96
        im = new(W, H)
        shape(im, 47, 14, W - 47 - 6, 70, p['void'], 7)
        shape(im, 48, 15, W - 49 - 6, 68, p['gold'], 6)
        shape(im, 49, 16, W - 51 - 6, 66, p['obs'], 5)
        for y, h in ((35, 15), (54, 13), (71, 5)):
            R(im, 94, y - 3, 170, h + 6, p['void'])
            box(im, 95, y - 2, 168, h + 4, p['gold_lo'])
            R(im, 96, y - 1, 166, h + 2, p['void'])
        diamond(im, 280, 49, 4, p['gold'])
        diamond(im, 280, 49, 2, p['violet'])
        return im

    def hud_ring(self, im, hole_c):
        p = self.P
        cx, cy = 47, 48
        for y in range(96):
            for x in range(96):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                d = math.hypot(dx, dy)
                if d < 30:
                    im.putpixel((x, y), hole_c)
                elif d < 31:
                    im.putpixel((x, y), p['gold_hi'])
                elif d < 39:
                    im.putpixel((x, y), p['obs'])
                elif d < 40:
                    im.putpixel((x, y), p['gold'])
        for k in range(24):
            a = math.radians(15 * k)
            r0, r1 = (33, 37) if k % 6 == 0 else (34, 36)
            for d in range(r0, r1):
                px(im, int(cx + math.cos(a) * d), int(cy + math.sin(a) * d), p['teal'] if k % 6 == 0 else p['teal_lo'])
        for ax, ay in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            sx, sy = cx + ax * 35, cy + ay * 35
            diamond(im, sx, sy, 4, p['void'])
            diamond(im, sx, sy, 3, p['gold'])
            diamond(im, sx, sy, 1, p['gold_hi'])

    def level_badge(self):
        return self.button(40, 18, 4, 'on', primary=True)

    def fill(self, W, H, kind):
        p = self.P
        c0, c1, c2 = {'hp': (p['red_hi'], p['red'], p['red_lo']), 'mp': (p['blue_hi'], p['blue'], p['blue_lo']),
                      'xp': (p['vio_hi'], p['violet'], p['vio_lo'])}[kind]
        im = new(W, H)
        vgrad(im, 0, 0, W, H, c1, c2)
        R(im, 0, 0, W, 1, c0)
        return im

    def orb_ring(self, S, L):
        p = self.P
        rh = (L - 1) / 2.0
        outer = S / 2.0
        im = new(S, S)
        c = S / 2.0
        for y in range(S):
            for x in range(S):
                dx, dy = x + 0.5 - c, y + 0.5 - c
                d = math.hypot(dx, dy)
                if d < rh or d > outer:
                    continue
                col = None
                if d < rh + 1.2:
                    col = p['gold_hi']
                elif d < outer - 4.2:
                    col = p['obs']
                elif d < outer - 3.2:
                    col = p['gold']
                elif d < outer - 2.2:
                    col = p['void']
                elif d < outer - 1.0:
                    col = p['violet']
                if col is not None:
                    im.putpixel((x, y), col)
        # teal ticks, a long one every 30 degrees
        for k in range(60):
            a = math.radians(6 * k)
            major = k % 5 == 0
            r0 = rh + 3.5
            r1 = r0 + (4 if major else 2)
            n = int((r1 - r0) * 2)
            for i in range(n):
                d = r0 + (r1 - r0) * i / n
                px(im, int(c + math.cos(a) * d), int(c + math.sin(a) * d), p['teal'] if major else p['teal_lo'])
        # four diamond studs on the outer hairline
        sr = max(3, int(round(S / 32.0)))
        dist = outer - 3.7 - 0.0
        for ax, ay in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            sx, sy = int(round(c + ax * (dist - sr * 0.3))), int(round(c + ay * (dist - sr * 0.3)))
            diamond(im, sx, sy, sr + 1, p['void'])
            diamond(im, sx, sy, sr, p['gold'])
            diamond(im, sx, sy, max(sr - 2, 0), p['gold_hi'])
        return im


STYLES = {'forge': Forge(), 'abyss': Abyss()}


# ============================================================== the file set
ORB_SIZES = (76, 150, 190)       # game_shaderfx/shaderfxlogic.lua ORB_SIZES


def liquid(size):
    return int(math.floor(size * 50 / 76 + 0.5))


def read_orb_sizes():
    import re
    path = os.path.join(OVERLAY, 'modules', 'game_shaderfx', 'shaderfxlogic.lua')
    m = re.search(r'L\.ORB_SIZES = \{(.*?)\n\}', open(path, encoding='utf-8').read(), re.S)
    return [int(v) for v in re.findall(r'size = (\d+)', m.group(1))] if m else list(ORB_SIZES)


def classic_path(virtual):
    if virtual.startswith('images/'):
        return os.path.join(IMAGES, virtual[len('images/'):])
    return os.path.join(OVERLAY, virtual)


def classic_image(virtual):
    path = classic_path(virtual)
    return Image.open(path).convert('RGBA') if os.path.isfile(path) else None


def hud_images(st):
    """plate, portrait cover and the level badge of the HUD (geometry of gen_skin.py: portrait centre 47,48, opening
    radius 30, ring 40, bars at x 96, 166 wide)"""
    plate = st.hud_chrome()
    well = st.P.get('well') or st.P['void']
    st.hud_ring(plate, tuple(int(v * 0.8) for v in well[:3]) + (255,))
    cover = plate.crop((0, 0, 96, 96))
    cpx = cover.load()
    for y in range(96):
        for x in range(96):
            if math.hypot(x + 0.5 - 47, y + 0.5 - 48) < 30:
                cpx[x, y] = (0, 0, 0, 0)
    return plate, cover


def build(style):
    """virtual path -> image, for one skin"""
    st = STYLES[style] if isinstance(style, str) else style
    art = {}
    states = ('normal', 'hover', 'pressed', 'disabled')

    def put(path, img):
        art[path] = img

    # windows and frames (borders left, top, right, bottom as in gen_skin.py)
    put('images/chaos/skin/window.png', st.frame(128, 128, 12, 32, 12, 12))
    put('images/chaos/window.png', st.frame(96, 96, 18, 34, 18, 18))
    put('images/ui/window.png', st.frame(236, 207, 4, 19, 4, 4, crack=16))
    put('images/ui/popupwindow.png', st.frame(236, 207, 4, 17, 4, 4, crack=14))
    put('images/ui/map-borderimage.png', st.frame(102, 114, 4, 19, 4, 4, crack=16))
    put('images/ui/window_headless.png', st.frame(45, 30, 5, 5, 5, 5, title=False))
    # ornaments
    for nm, fx, fy in (('tl', 0, 0), ('tr', 1, 0), ('bl', 0, 1), ('br', 1, 1)):
        put('images/chaos/skin/orn_corner_%s.png' % nm, mirror(st.orn_corner(False), fx, fy))
        put('images/chaos/skin/orn_corner_blue_%s.png' % nm, mirror(st.orn_corner(True), fx, fy))
    put('images/chaos/skin/orn_crest.png', st.crest())
    # buttons
    put('images/chaos/skin/button.png', stack(*[st.button(64, 24, 5, s) for s in states]))
    put('images/chaos/skin/button_primary.png', stack(*[st.button(64, 24, 5, s, primary=True) for s in states]))
    for s in states:
        put('images/chaos/button_%s.png' % s, st.button(48, 24, 6, s))
    put('images/chaos/skin/tab.png', stack(*[st.tab(64, 24, 5, s) for s in ('normal', 'hover', 'on')]))
    for s, nm in (('normal', 'normal'), ('hover', 'hover'), ('on', 'active')):
        put('images/chaos/tab_%s.png' % nm, st.tab(40, 24, 6, s))
    put('images/ui/buttons.png', stack(st.button(43, 20, 1, 'normal'), st.button(43, 20, 1, 'pressed')))
    for nm in ('button', 'button_rounded'):
        put('images/ui/%s.png' % nm, stack(*[st.button(22, 23, 3, s) for s in ('normal', 'hover', 'pressed')]))
    put('images/ui/tabbutton_rounded.png', stack(*[st.button(22, 23, 3, s) for s in ('normal', 'hover', 'on')]))
    put('images/ui/tabbutton_square.png', stack(*[st.tab(96, 19, 3, s) for s in ('normal', 'hover', 'on')]))
    put('images/ui/chat_channel_selected.png', st.tab(96, 18, 3, 'on'))
    put('images/ui/chat_channel_deselected.png', st.tab(96, 16, 3, 'normal'))
    # panels
    put('images/chaos/panel.png', st.panel(32, 32, 8, 'inset'))
    put('images/chaos/panel_dark.png', st.panel(32, 32, 6, 'dark'))
    put('images/chaos/panel_highlight.png', st.panel(32, 32, 8, 'highlight'))
    for nm in ('2pixel-up-frame-borderimage', '2pixel_up_frame_borderimage'):
        put('images/ui/%s.png' % nm, st.panel(100, 100, 2, 'raised'))
    for nm in ('2pixel-up-frame-borderimage-dark', '2pixel_up_frame_borderimage_dark'):
        put('images/ui/%s.png' % nm, st.panel(100, 100, 2, 'dark'))
    for nm in ('2pixel-up-frame-borderimage-upside-down', '2pixel-up-frame-borderimage-dark-upside-down',
               '2pixel_up_frame_borderimage_dark_reversed'):
        put('images/ui/%s.png' % nm, st.panel(100, 100, 2, 'inset'))
    for nm in ('1pixel-down-frame', '1pixel_down_frame'):
        put('images/ui/%s.png' % nm, st.panel(96, 96, 1, 'inset'))
    put('images/ui/1pixel-up-frame.png', st.panel(96, 96, 1, 'raised'))
    for nm in ('3pixel-frame-borderimage', '3pixel_frame_borderimage'):
        put('images/ui/%s.png' % nm, st.panel(102, 102, 3, 'inset'))
    put('images/ui/panel_flat.png', st.panel(68, 68, 1, 'flat'))
    put('images/ui/panel-1-pixel.png', st.panel(98, 98, 1, 'inset'))
    put('images/ui/panel_map_bordered.png', st.panel(96, 97, 2, 'inset'))
    put('images/ui/panel_map.png', st.map_frame(96))
    put('images/ui/menubox.png', st.menubox())
    put('images/chaos/skin/tooltip.png', st.tooltip())
    put('images/chaos/skin/menubar.png', st.menubar())
    put('images/chaos/topbar_bg.png', st.topbar(32, 44))
    put('images/chaos/title_plate.png', st.title_plate(64, 24))
    put('images/chaos/separator.png', st.separator(64, 8))
    # text fields, check boxes, combo box
    put('images/chaos/textedit.png', st.text_field(32, 22))
    put('images/chaos/textedit_focus.png', st.text_field(32, 22, focus=True))
    put('images/ui/textedit.png', st.text_field(32, 32))
    put('images/chaos/checkbox.png', st.checkbox(16))
    put('images/chaos/combobox.png', st.combobox(40, 22, 18))
    # scroll bars: the Chaos parts and the stock sheet (ui/scrollbar: 36 x 74, layout of 10-scrollbars.otui)
    for s, suffix in (('normal', ''), ('hover', '_hover'), ('pressed', '_pressed')):
        put('images/chaos/scroll_slider%s.png' % suffix, st.scroll_slider(s))
        put('images/chaos/scroll_up%s.png' % suffix, st.scroll_button(s, 'up'))
        put('images/chaos/scroll_down%s.png' % suffix, st.scroll_button(s, 'down'))
    put('images/chaos/scroll_track.png', st.scroll_track())
    put('images/ui/scrollbar.png', stock_scrollbar(st))
    # slots
    for nm in ('chaos/itemslot', 'ui/item', 'ui/item-slot', 'game/slots/item-slot', 'game/actionbar/actionbarslot',
               'game/actionbar/slot-actionbar'):
        put('images/%s.png' % nm, st.slot(34))
    put('images/ui/item-blessed.png', st.slot(34, rim=st.P.get('ember_hi') or st.P['gold_hi']))
    put('images/game/actionbar/slot-actionbar_.png', st.slot(44))
    put('images/ui/item66.png', st.slot(66))
    for cw, ch in ((1, 1), (2, 1), (1, 2), (2, 2)):
        put('images/chaos/charmslot_%dx%d.png' % (cw, ch), st.slot(cw * 46 - 2, ch * 46 - 2))
    put('images/chaos/progress_frame.png', st.progress_frame(32, 16))
    # HUD
    plate, cover = hud_images(st)
    put('images/chaos/skin/hud_plate.png', plate)
    put('images/chaos/skin/hud_portrait_cover.png', cover)
    put('images/chaos/skin/hud_hp_fill.png', st.fill(166, 15, 'hp'))
    put('images/chaos/skin/hud_mp_fill.png', st.fill(166, 13, 'mp'))
    put('images/chaos/skin/hud_xp_fill.png', st.fill(166, 5, 'xp'))
    put('images/chaos/skin/hud_level.png', st.level_badge())
    # orb rings, 2x the orb size (game_shaderfx)
    for s in read_orb_sizes():
        ring = st.orb_ring(s, liquid(s))
        put('modules/game_shaderfx/images/orb_ring_%d.png' % s, ring.resize((s * 2, s * 2), Image.NEAREST))
    # the chat frame: the classic sheet with its two panels redrawn (text area 184,0 166x150 b3; input 0,50 184x124 b4)
    con = classic_image('images/ui/console.png')
    if con is not None:
        con.paste(st.panel(166, 150, 3, 'dark'), (184, 0))
        con.paste(st.panel(184, 124, 4, 'dark'), (0, 50))
        put('images/ui/console.png', con)
    # stock sheets recoloured from the classic ones
    for rel in RECOLOR:
        src = classic_image('images/%s.png' % rel)
        if src is not None:
            put('images/%s.png' % rel, recolor(src, st.NEUTRAL, st.ACCENT))
    return art


def stock_scrollbar(st):
    """ui/scrollbar.png 36 x 74, the layout of the base 10-scrollbars.otui: vertical decrement 0,0 (pressed 12,0),
    increment 0,12 (pressed 12,12); vertical slider 0,24 12x14; vertical track 24,0 12x74; horizontal track 0,38
    24x12; horizontal slider 12,26 12x12; horizontal decrement / increment 0,50 / 12,50 (pressed 0,62 / 12,62)"""
    im = new(36, 74)

    def part(state, d):
        return st.scroll_button(state, d).crop((0, 0, 12, 12))
    for dx, state in ((0, 'normal'), (12, 'pressed')):
        im.paste(part(state, 'up'), (dx, 0))
        im.paste(part(state, 'down'), (dx, 12))
    for y, state in ((50, 'normal'), (62, 'pressed')):
        im.paste(part(state, 'left'), (0, y))
        im.paste(part(state, 'right'), (12, y))
    trk = st.scroll_track()
    for y in range(0, 74, 32):
        im.paste(trk.crop((0, 0, 12, min(32, 74 - y))), (24, y))
    im.paste(trk.transpose(Image.ROTATE_90).crop((0, 0, 24, 12)), (0, 38))
    sl = st.scroll_slider('normal')
    im.paste(sl.crop((0, 0, 12, 14)), (0, 24))
    im.paste(sl.transpose(Image.ROTATE_90).crop((0, 0, 12, 12)), (12, 26))
    return im


# ============================================================== files, manifest, check
def skin_dir(style):
    return os.path.join(SKINS, style)


def file_path(style, virtual):
    return os.path.join(skin_dir(style), *virtual.split('/'))


def manifest_text(style, files):
    h = hashlib.sha1()
    for v in sorted(files):
        h.update(v.encode() + b'\0')
        h.update(open(file_path(style, v), 'rb').read())
    lines = ['-- written by client/tools/gen_skin_variants.py; regenerate instead of editing',
             '-- the images of the skin "%s": each shadows the client file at the same virtual path (skin_core.lua)' % style,
             'return {', "  rev = '%s'," % h.hexdigest()[:16], '  files = {']
    lines += ["    '%s'," % v for v in sorted(files)]
    lines += ['  },', '}', '']
    return '\n'.join(lines)


def write_all():
    n = 0
    for style in SKIN_IDS:
        art = build(style)
        d = skin_dir(style)
        os.makedirs(d, exist_ok=True)
        for v, img in sorted(art.items()):
            p = file_path(style, v)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            img.save(p, optimize=True)
            n += 1
        # files of an earlier run that are no longer drawn
        for v in list_files(style):
            if v not in art:
                os.remove(file_path(style, v))
        open(os.path.join(d, 'manifest.lua'), 'w', newline='\n').write(manifest_text(style, list(art)))
    src = os.path.join(IMAGES, 'chaos', 'skin', 'button.png')
    dst = os.path.join(OVERLAY, 'data', PRIMARY_CLASSIC)
    open(dst, 'wb').write(open(src, 'rb').read())
    print('wrote %d images for %d skins' % (n, len(SKIN_IDS)))


def list_files(style):
    out = []
    root = skin_dir(style)
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn.endswith('.png'):
                out.append(os.path.relpath(os.path.join(dp, fn), root).replace(os.sep, '/'))
    return out


def check():
    bad = []
    try:
        sys.path.insert(0, HERE)
        import gen_orb_art
    except Exception:
        gen_orb_art = None
    for style in SKIN_IDS:
        art = build(style)
        have = set(list_files(style))
        for v, img in sorted(art.items()):
            p = file_path(style, v)
            if not os.path.isfile(p):
                bad.append('%s/%s: missing' % (style, v))
                continue
            got = Image.open(p).convert('RGBA')
            if got.size != img.size or got.tobytes() != img.tobytes():
                bad.append('%s/%s: differs from the generator' % (style, v))
            cl = classic_path(v)
            if os.path.isfile(cl) and Image.open(cl).size != img.size:
                bad.append('%s/%s: size %s, the classic image is %s' % (style, v, img.size, Image.open(cl).size))
        for v in sorted(have - set(art)):
            bad.append('%s/%s: not made by the generator (left over)' % (style, v))
        mp = os.path.join(skin_dir(style), 'manifest.lua')
        if not os.path.isfile(mp):
            bad.append('%s/manifest.lua: missing' % style)
        elif all(os.path.isfile(file_path(style, v)) for v in art) and open(mp).read() != manifest_text(style, list(art)):
            bad.append('%s/manifest.lua: out of date' % style)
        if gen_orb_art:
            for s in read_orb_sizes():
                p = file_path(style, 'modules/game_shaderfx/images/orb_ring_%d.png' % s)
                if not os.path.isfile(p):
                    continue
                hole = gen_orb_art.opening(Image.open(p).convert('RGBA'))
                c = s * 2 / 2.0
                mask_r = (liquid(s) * 2) / 2.0 - 1.0
                if hole is None:
                    bad.append('%s ring %d: no opening' % (style, s))
                elif abs(hole[0] - c) > 1 or abs(hole[1] - c) > 1 or abs(hole[2] - mask_r) > 2:
                    bad.append('%s ring %d: opening %.2f,%.2f r %.2f, wanted centre %.1f radius %.1f' % (style, s, hole[0], hole[1], hole[2], c, mask_r))
    dst = os.path.join(OVERLAY, 'data', PRIMARY_CLASSIC)
    src = os.path.join(IMAGES, 'chaos', 'skin', 'button.png')
    if not os.path.isfile(dst) or open(dst, 'rb').read() != open(src, 'rb').read():
        bad.append(PRIMARY_CLASSIC + ': not a copy of chaos/skin/button.png')
    for b in bad:
        print('gen_skin_variants --check:', b)
    if bad:
        print('run: python3 client/tools/gen_skin_variants.py')
        return 1
    print('gen_skin_variants --check: %d skins up to date' % len(SKIN_IDS))
    return 0


# ============================================================== preview
def nine(img, W, H, L, T, Rr, B):
    """the engine's 9-slice (corners as they are, edges and centre stretched)"""
    w, h = img.size
    out = new(W, H)
    xs = [(0, L, 0, L), (L, W - Rr, L, w - Rr), (W - Rr, W, w - Rr, w)]
    ys = [(0, T, 0, T), (T, H - B, T, h - B), (H - B, H, h - B, h)]
    for dx0, dx1, sx0, sx1 in xs:
        for dy0, dy1, sy0, sy1 in ys:
            if dx1 > dx0 and dy1 > dy0 and sx1 > sx0 and sy1 > sy0:
                out.paste(img.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST), (dx0, dy0))
    return out


def preview(outdir):
    os.makedirs(outdir, exist_ok=True)
    pal = {'classic': dict(title='#e8c477', text='#d6c9ae', bg='#0d0b0e'),
           'forge': dict(title='#ffb347', text='#d8ccb8', bg='#0b0908'),
           'abyss': dict(title='#e8cf8a', text='#d9d6e6', bg='#06070b')}
    try:
        font = ImageFont.load_default(size=11)
    except TypeError:
        font = ImageFont.load_default()

    def get(style, virtual):
        if style == 'classic':
            return classic_image(virtual)
        return Image.open(file_path(style, virtual)).convert('RGBA')

    for style in ('classic', 'forge', 'abyss'):
        P = pal[style]
        sheet = new(560, 420, C(P['bg']))
        d = ImageDraw.Draw(sheet)
        # window with title bar and ornaments
        win = nine(get(style, 'images/chaos/skin/window.png'), 250, 170, 12, 32, 12, 12)
        sheet.alpha_composite(win, (10, 12))
        d.text((135, 20), 'WINDOW TITLE', fill=C(P['title']), font=font, anchor='mt')
        for nm, (ox, oy) in (('tl', (10 - 8, 12 - 8)), ('tr', (10 + 250 - 44 + 8, 12 - 8)),
                             ('bl', (10 - 8, 12 + 170 - 44 + 8)), ('br', (10 + 250 - 44 + 8, 12 + 170 - 44 + 8))):
            sheet.alpha_composite(get(style, 'images/chaos/skin/orn_corner_%s.png' % nm), (ox, oy))
        sheet.alpha_composite(get(style, 'images/chaos/skin/orn_crest.png'), (10 + 125 - 42, 12 - 17))
        d.text((24, 70), 'Body text on the window.', fill=C(P['text']), font=font)
        # mini window
        mw = nine(get(style, 'images/ui/window.png'), 150, 100, 4, 19, 4, 4)
        sheet.alpha_composite(mw, (280, 12))
        d.text((290, 14), 'Mini window', fill=C(P['title']), font=font)
        # buttons: normal hover pressed disabled, primary row
        for row, nm in enumerate(('button', 'button_primary')):
            sh = get(style, 'images/chaos/skin/%s.png' % nm)
            for i in range(4):
                b = nine(sh.crop((0, 24 * i, 64, 24 * i + 24)), 70, 24, 5, 5, 5, 5)
                sheet.alpha_composite(b, (280 + 76 * (i % 2), 125 + 30 * (i // 2) + row * 66))
                d.text((280 + 76 * (i % 2) + 35, 125 + 30 * (i // 2) + row * 66 + 12), ('Normal', 'Hover', 'Pressed', 'Disabled')[i],
                       fill=C(P['text']), font=font, anchor='mm')
        # tabs
        tb = get(style, 'images/chaos/skin/tab.png')
        for i, nm in enumerate(('Active', 'Normal', 'Hover')):
            src = (2, 0, 1)[i]
            t = nine(tb.crop((0, 24 * src, 64, 24 * src + 24)), 64, 24, 5, 5, 5, 5)
            sheet.alpha_composite(t, (10 + 68 * i, 200))
            d.text((10 + 68 * i + 32, 212), nm, fill=C(P['text']), font=font, anchor='mm')
        # slots, item
        for i in range(4):
            sheet.alpha_composite(get(style, 'images/chaos/itemslot.png' if i < 3 else 'images/ui/item-blessed.png'), (10 + 40 * i, 236))
        # scroll bar (vertical, from the stock sheet), text field, check boxes, progress frame
        sb = get(style, 'images/ui/scrollbar.png')
        sheet.alpha_composite(sb.crop((0, 0, 12, 12)), (200, 236))
        for y in range(12, 60, 1):
            sheet.alpha_composite(sb.crop((24, 20, 36, 21)), (200, 236 + y))
        sheet.alpha_composite(sb.crop((0, 24, 12, 38)), (200, 252))
        sheet.alpha_composite(sb.crop((0, 12, 12, 24)), (200, 284))
        sheet.alpha_composite(get(style, 'images/chaos/textedit_focus.png'), (10, 282))
        sheet.alpha_composite(get(style, 'images/chaos/textedit.png'), (50, 282))
        cb = get(style, 'images/chaos/checkbox.png')
        sheet.alpha_composite(cb.crop((0, 0, 16, 16)), (100, 282))
        sheet.alpha_composite(cb.crop((0, 16, 16, 32)), (120, 282))
        pf = nine(get(style, 'images/chaos/progress_frame.png'), 150, 16, 3, 3, 3, 3)
        sheet.alpha_composite(pf, (10, 312))
        R(sheet, 13, 315, 100, 10, C(pal_color(style, 'hp')))
        # tooltip and menu
        tt = nine(get(style, 'images/chaos/skin/tooltip.png'), 140, 44, 4, 4, 4, 4)
        sheet.alpha_composite(tt, (10, 340))
        d.text((18, 348), 'Crown of the Last Pyre', fill=C(P['title']), font=font)
        # HUD and the 150 px orb
        hud = get(style, 'images/chaos/skin/hud_plate.png')
        sheet.alpha_composite(hud, (170, 322))
        ring = get(style, 'modules/game_shaderfx/images/orb_ring_150.png').resize((150, 150), Image.LANCZOS)
        back = new(150, 150)
        disc(back, 75, 75, 49, C(pal_color(style, 'hp')))
        sheet.alpha_composite(back, (405, 235))
        sheet.alpha_composite(ring, (405, 235))
        big = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
        big.save(os.path.join(outdir, 'skins_preview_%s.png' % style), optimize=True)
    print('previews in', outdir)


def pal_color(style, kind):
    return {'classic': {'hp': '#8a1010'}, 'forge': {'hp': '#c2260f'}, 'abyss': {'hp': '#d23a5a'}}[style][kind]


def main(argv):
    if '--check' in argv:
        return check()
    if '--preview' in argv:
        preview(argv[argv.index('--preview') + 1])
        return 0
    write_all()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
