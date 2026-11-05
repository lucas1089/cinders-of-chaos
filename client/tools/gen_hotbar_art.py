#!/usr/bin/env python3
"""Art of the central hotbar and the floating chat (client/MANIFEST.md "Floating chat and central hotbar (O414)").
Drawn here from plain geometry and seeded noise (no source images, nothing third-party): charred iron, ember gold trim,
rivets, a green frame for a ready slot. Every piece is drawn at 4x and reduced with a Lanczos filter, so the output is
the same on every run.

Writes into client/overlay/modules/game_hotbar/images/ (hotbar_*.png) and game_floatchat/images/ (chat_*.png).
Nine-slice pieces keep their border in whole pixels (the border sizes are the constants below; the otui files use the
same numbers as image-border).

Usage: python3 client/tools/gen_hotbar_art.py [--check] [--preview OUT.png]
  (no flag)  write the images
  --check    the committed images have the pixels the generator draws, the sizes match the geometry in
             hotbar_logic.lua and floatchat_logic.lua, no stray image is left (exit 1 when not); nothing is written
  --preview  write a picture of the bar (globes on and off, 6 slots) and of the chat window; for looking at only
Needs Pillow and numpy."""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.path.join(os.path.dirname(HERE), 'overlay', 'modules')
BAR_DIR = os.path.join(MODULES, 'game_hotbar', 'images')
CHAT_DIR = os.path.join(MODULES, 'game_floatchat', 'images')
BAR_LOGIC = os.path.join(MODULES, 'game_hotbar', 'hotbar_logic.lua')
CHAT_LOGIC = os.path.join(MODULES, 'game_floatchat', 'floatchat_logic.lua')
SS = 4  # supersampling

# palette: charred iron, ember gold, a green for ready, ink for outlines
INK = (12, 9, 11)
IRON_D = (24, 21, 25)
IRON = (40, 36, 41)
IRON_L = (78, 70, 74)
IRON_H = (116, 104, 98)
GOLD = (222, 168, 72)
GOLD_D = (128, 82, 30)
GOLD_L = (255, 224, 140)
EMBER = (226, 98, 36)
EMBER_D = (118, 36, 18)
GREEN = (86, 214, 120)
GREEN_D = (24, 98, 52)
RUST = (92, 52, 36)

# geometry shared with the Lua logic (checked): name -> (value, lua constant)
BODY_W, BODY_H, BODY_BORDER = 96, 84, 20
SLOT_FRAME = 44
KEY_W, KEY_H, KEY_BORDER = 30, 14, 4
SOCKET = 44
CAP_CLOSED_W, CAP_OPEN_W = 26, 22
CHAT_BORDER_SIZE, CHAT_BORDER = 48, 10
ICON = 20


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def canvas(w, h):
    img = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def down(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def noise(w, h, seed, amp):
    """seeded grain, amp in 0..255 levels, as an (h, w) float array in -amp..amp"""
    rng = np.random.RandomState(seed)
    n = rng.rand(h, w).astype(np.float32) * 2.0 - 1.0
    # one blur pass so the grain reads as stone and not as static
    img = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), 'L').filter(ImageFilter.GaussianBlur(1.2))
    a = (np.asarray(img).astype(np.float32) / 255.0 - 0.5) * 2.0
    return a * amp


def grain(img, seed, amp=14):
    """add the grain to the colour of the opaque pixels"""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    g = noise(w, h, seed, amp)
    for c in range(3):
        a[:, :, c] = np.clip(a[:, :, c] + g, 0, 255)
    return Image.fromarray(a.astype(np.uint8), 'RGBA')


def rr(d, box, radius, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def rivet(d, x, y, r):
    d.ellipse((x - r, y - r, x + r, y + r), fill=rgba(IRON_D), outline=rgba(INK), width=max(1, r // 4))
    d.ellipse((x - r * 0.5, y - r * 0.6, x + r * 0.1, y - r * 0.05), fill=rgba(IRON_H))


def body():
    """the frame of the bar: a nine-slice, iron with an ember gold trim and corner rivets"""
    w, h = BODY_W, BODY_H
    img, d = canvas(w, h)
    W, H = w * SS, h * SS
    rr(d, (0, 0, W - 1, H - 1), 14 * SS, fill=rgba(INK))
    rr(d, (SS, SS, W - SS - 1, H - SS - 1), 13 * SS, fill=rgba(IRON))
    # a darker well in the middle, a lighter bevel on the top edge
    rr(d, (6 * SS, 6 * SS, W - 6 * SS - 1, H - 6 * SS - 1), 9 * SS, fill=rgba(IRON_D))
    d.line((12 * SS, 2 * SS, W - 12 * SS, 2 * SS), fill=rgba(IRON_H), width=SS)
    d.line((12 * SS, H - 3 * SS, W - 12 * SS, H - 3 * SS), fill=rgba(INK), width=SS)
    # the gold trim
    rr(d, (4 * SS, 4 * SS, W - 4 * SS - 1, H - 4 * SS - 1), 10 * SS, outline=rgba(GOLD_D), width=SS)
    rr(d, (5 * SS - SS // 2, 5 * SS - SS // 2, W - 5 * SS + SS // 2 - 1, H - 5 * SS + SS // 2 - 1), 9 * SS,
       outline=rgba(GOLD), width=max(1, SS // 2))
    for (x, y) in ((9, 9), (w - 10, 9), (9, h - 10), (w - 10, h - 10)):
        rivet(d, x * SS, y * SS, 2 * SS)
    # ember cracks: short lines in the corners, only on the corner cells so the stretch keeps the middle clean
    for (x0, y0, x1, y1) in ((13, 16, 17, 20), (w - 14, 16, w - 18, 20), (13, h - 17, 17, h - 21),
                             (w - 14, h - 17, w - 18, h - 21)):
        d.line((x0 * SS, y0 * SS, x1 * SS, y1 * SS), fill=rgba(EMBER_D), width=SS)
    out = down(img, w, h)
    return grain(out, 11, 9)


def slot(ready):
    """frame of one slot: a dark inset (the button is drawn inside it)"""
    s = SLOT_FRAME
    img, d = canvas(s, s)
    S = s * SS
    rr(d, (0, 0, S - 1, S - 1), 5 * SS, fill=rgba(INK))
    edge = GREEN if ready else IRON_L
    rr(d, (SS, SS, S - SS - 1, S - SS - 1), 4 * SS, fill=rgba(edge))
    rr(d, (2 * SS, 2 * SS, S - 2 * SS - 1, S - 2 * SS - 1), 3 * SS, fill=rgba(GREEN_D if ready else IRON_D))
    rr(d, (3 * SS, 3 * SS, S - 3 * SS - 1, S - 3 * SS - 1), 2 * SS, fill=rgba((10, 8, 10)))
    if ready:
        rr(d, (SS, SS, S - SS - 1, S - SS - 1), 4 * SS, outline=rgba(GREEN_D), width=SS // 2)
    else:
        d.line((4 * SS, SS + SS // 2, S - 4 * SS, SS + SS // 2), fill=rgba(IRON_H), width=SS // 2)
    return down(img, s, s)


def keybox():
    """the small box under a slot for its key label: a nine-slice"""
    w, h = KEY_W, KEY_H
    img, d = canvas(w, h)
    W, H = w * SS, h * SS
    rr(d, (0, 0, W - 1, H - 1), 4 * SS, fill=rgba(INK))
    rr(d, (SS, SS, W - SS - 1, H - SS - 1), 3 * SS, fill=rgba(IRON_D), outline=rgba(GOLD_D), width=SS // 2)
    d.line((3 * SS, 2 * SS, W - 3 * SS, 2 * SS), fill=rgba(IRON_L), width=SS // 2)
    return down(img, w, h)


def socket():
    """the round socket of the side slots (potion on the left, utility on the right)"""
    s = SOCKET
    img, d = canvas(s, s)
    S = s * SS
    d.ellipse((0, 0, S - 1, S - 1), fill=rgba(INK))
    d.ellipse((SS, SS, S - SS - 1, S - SS - 1), fill=rgba(GOLD_D))
    d.ellipse((2 * SS, 2 * SS, S - 2 * SS - 1, S - 2 * SS - 1), fill=rgba(GOLD))
    d.ellipse((3 * SS, 3 * SS, S - 3 * SS - 1, S - 3 * SS - 1), fill=rgba(IRON_D))
    d.ellipse((4 * SS, 4 * SS, S - 4 * SS - 1, S - 4 * SS - 1), fill=rgba((10, 8, 10)))
    d.arc((2 * SS, 2 * SS, S - 2 * SS - 1, S - 2 * SS - 1), 200, 290, fill=rgba(GOLD_L), width=SS)
    return down(img, s, s)


def cap(left, closed):
    """an end of the bar. closed: a rounded finial with an ember gem (no globe); open: a bracket the globe sits in,
    its inner side hollowed. Left ends are the mirror of the right ones."""
    w = CAP_CLOSED_W if closed else CAP_OPEN_W
    h = BODY_H
    img, d = canvas(w, h)
    W, H = w * SS, h * SS
    if closed:
        rr(d, (0, 0, W * 2, H - 1), 16 * SS, fill=rgba(INK))
        rr(d, (SS, SS, W * 2, H - SS - 1), 15 * SS, fill=rgba(IRON))
        rr(d, (5 * SS, 5 * SS, W * 2, H - 5 * SS - 1), 11 * SS, fill=rgba(IRON_D))
        rr(d, (4 * SS, 4 * SS, W * 2, H - 4 * SS - 1), 12 * SS, outline=rgba(GOLD), width=SS)
        cx, cy, r = 12 * SS, H // 2, 5 * SS
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=rgba(EMBER_D), outline=rgba(GOLD), width=SS)
        d.ellipse((cx - r * 0.5, cy - r * 0.6, cx + r * 0.1, cy - r * 0.1), fill=rgba(EMBER))
    else:
        rr(d, (0, 0, W * 2, H - 1), 10 * SS, fill=rgba(INK))
        rr(d, (SS, SS, W * 2, H - SS - 1), 9 * SS, fill=rgba(IRON))
        rr(d, (4 * SS, 4 * SS, W * 2, H - 4 * SS - 1), 7 * SS, outline=rgba(GOLD_D), width=SS)
        # the hollow the globe sits in, cut out of the inner side
        d.ellipse((W - 6 * SS, -8 * SS, W + 60 * SS, H + 8 * SS), fill=(0, 0, 0, 0))
        d.arc((W - 8 * SS, -8 * SS, W + 60 * SS, H + 8 * SS), 90, 270, fill=rgba(GOLD), width=SS)
        # claws over the top and bottom
        for y in (6, h - 7):
            rivet(d, 7 * SS, y * SS, 2 * SS)
    out = down(img, w, h)
    out = grain(out, 21 if closed else 22, 8)
    out = out.crop((0, 0, w, h))
    return out if left else out.transpose(Image.FLIP_LEFT_RIGHT)


def gem():
    s = 14
    img, d = canvas(s, s)
    S = s * SS
    d.polygon([(S // 2, 0), (S - 1, S // 2), (S // 2, S - 1), (0, S // 2)], fill=rgba(INK))
    d.polygon([(S // 2, 2 * SS), (S - 2 * SS, S // 2), (S // 2, S - 2 * SS), (2 * SS, S // 2)], fill=rgba(EMBER))
    d.polygon([(S // 2, 2 * SS), (S // 2, S // 2), (2 * SS, S // 2)], fill=rgba(GOLD_L))
    return down(img, s, s)


def handle():
    w, h = 36, 10
    img, d = canvas(w, h)
    rr(d, (0, 0, w * SS - 1, h * SS - 1), 4 * SS, fill=rgba(INK))
    rr(d, (SS, SS, w * SS - SS - 1, h * SS - SS - 1), 3 * SS, fill=rgba(IRON))
    for i in range(5):
        x = (8 + i * 5) * SS
        d.ellipse((x - SS, 4 * SS, x + SS, 6 * SS), fill=rgba(GOLD_D))
    return down(img, w, h)


def dot():
    s = 8
    img, d = canvas(s, s)
    d.ellipse((0, 0, s * SS - 1, s * SS - 1), fill=rgba(INK))
    d.ellipse((SS, SS, s * SS - SS - 1, s * SS - SS - 1), fill=rgba(EMBER))
    d.ellipse((2 * SS, 2 * SS, 4 * SS, 4 * SS), fill=rgba(GOLD_L))
    return down(img, s, s)


def button_sheet(icon_fn):
    """three states side by side (normal, hover, pressed) of a small round button with an icon"""
    s = ICON + 2
    sheet = Image.new('RGBA', (s * 3, s), (0, 0, 0, 0))
    for i, (edge, fill) in enumerate(((GOLD_D, IRON_D), (GOLD, IRON), (GOLD_L, EMBER_D))):
        img, d = canvas(s, s)
        S = s * SS
        d.ellipse((0, 0, S - 1, S - 1), fill=rgba(INK))
        d.ellipse((SS, SS, S - SS - 1, S - SS - 1), fill=rgba(edge))
        d.ellipse((2 * SS, 2 * SS, S - 2 * SS - 1, S - 2 * SS - 1), fill=rgba(fill))
        b = down(img, s, s)
        ic = icon_fn(i)
        b.alpha_composite(ic, ((s - ic.width) // 2, (s - ic.height) // 2 + (1 if i == 2 else 0)))
        sheet.alpha_composite(b, (i * s, 0))
    return sheet


def icon_chat(state):
    s = 12
    img, d = canvas(s, s)
    c = rgba(GOLD_L if state else GOLD)
    d.rounded_rectangle((0, SS, s * SS - 1, 8 * SS), radius=2 * SS, fill=c)
    d.polygon([(2 * SS, 8 * SS), (2 * SS, 11 * SS), (5 * SS, 8 * SS)], fill=c)
    for i in range(3):
        x = (3 + i * 3) * SS
        d.ellipse((x - SS // 2, 3 * SS, x + SS // 2 + SS // 2, 4 * SS + SS // 2), fill=rgba(IRON_D))
    return down(img, s, s)


def icon_gear(state):
    s = 12
    img, d = canvas(s, s)
    c = rgba(GOLD_L if state else GOLD)
    cx = cy = s * SS // 2
    for k in range(8):
        a = k * math.pi / 4
        x, y = cx + math.cos(a) * 5 * SS, cy + math.sin(a) * 5 * SS
        d.ellipse((x - SS * 1.2, y - SS * 1.2, x + SS * 1.2, y + SS * 1.2), fill=c)
    d.ellipse((cx - 4 * SS, cy - 4 * SS, cx + 4 * SS, cy + 4 * SS), fill=c)
    d.ellipse((cx - 1.6 * SS, cy - 1.6 * SS, cx + 1.6 * SS, cy + 1.6 * SS), fill=rgba(IRON_D))
    return down(img, s, s)


# ------------------------------------------------------------------ the chat window
def chat_border():
    """dark frame of the floating chat: only the edge is drawn, the inside stays clear (the body colour and its alpha
    are set in Lua from the opacity option). A nine-slice."""
    s = CHAT_BORDER_SIZE
    img, d = canvas(s, s)
    S = s * SS
    rr(d, (0, 0, S - 1, S - 1), 8 * SS, outline=rgba(INK), width=2 * SS)
    rr(d, (2 * SS, 2 * SS, S - 2 * SS - 1, S - 2 * SS - 1), 6 * SS, outline=rgba(IRON_L, 230), width=SS)
    rr(d, (3 * SS, 3 * SS, S - 3 * SS - 1, S - 3 * SS - 1), 5 * SS, outline=rgba(GOLD_D, 170), width=SS // 2)
    for (x, y) in ((5, 5), (s - 6, 5), (5, s - 6), (s - 6, s - 6)):
        d.ellipse(((x - 1) * SS, (y - 1) * SS, (x + 1) * SS, (y + 1) * SS), fill=rgba(GOLD))
    return down(img, s, s)


def chat_icon(kind):
    s = 14
    img, d = canvas(s, s)
    c = rgba(GOLD)
    S = s * SS
    if kind == 'channels':  # three lines, a hash
        for y in (3, 7, 11):
            d.rounded_rectangle((2 * SS, y * SS - SS // 2, 12 * SS, y * SS + SS // 2), radius=SS // 2, fill=c)
    elif kind == 'private':  # an envelope
        d.rounded_rectangle((SS, 3 * SS, 13 * SS, 11 * SS), radius=SS, fill=c)
        d.line((2 * SS, 4 * SS, 7 * SS, 8 * SS), fill=rgba(IRON_D), width=SS)
        d.line((12 * SS, 4 * SS, 7 * SS, 8 * SS), fill=rgba(IRON_D), width=SS)
    elif kind == 'close':
        d.line((3 * SS, 3 * SS, 11 * SS, 11 * SS), fill=rgba(GOLD_L), width=2 * SS)
        d.line((11 * SS, 3 * SS, 3 * SS, 11 * SS), fill=rgba(GOLD_L), width=2 * SS)
    elif kind == 'caret':
        d.polygon([(3 * SS, 5 * SS), (11 * SS, 5 * SS), (7 * SS, 10 * SS)], fill=c)
    elif kind == 'gear':
        return icon_gear(0).resize((s, s), Image.LANCZOS)
    elif kind == 'grip':  # the resize corner
        for i in range(3):
            d.line(((12 - i * 4) * SS, 13 * SS, 13 * SS, (12 - i * 4) * SS), fill=rgba(IRON_H), width=SS)
    return down(img, s, s)


def art():
    """relative path (dir key + file) -> image"""
    out = {}
    out[('bar', 'hotbar_body.png')] = body()
    out[('bar', 'hotbar_slot.png')] = slot(False)
    out[('bar', 'hotbar_slot_ready.png')] = slot(True)
    out[('bar', 'hotbar_key.png')] = keybox()
    out[('bar', 'hotbar_socket.png')] = socket()
    for left, name in ((True, 'l'), (False, 'r')):
        out[('bar', 'hotbar_cap_closed_%s.png' % name)] = cap(left, True)
        out[('bar', 'hotbar_cap_open_%s.png' % name)] = cap(left, False)
    out[('bar', 'hotbar_gem.png')] = gem()
    out[('bar', 'hotbar_handle.png')] = handle()
    out[('bar', 'hotbar_dot.png')] = dot()
    out[('bar', 'hotbar_btn_chat.png')] = button_sheet(lambda st: icon_chat(st))
    out[('bar', 'hotbar_btn_gear.png')] = button_sheet(lambda st: icon_gear(st))
    out[('chat', 'chat_border.png')] = chat_border()
    for kind in ('channels', 'private', 'close', 'caret', 'gear', 'grip'):
        out[('chat', 'chat_%s.png' % kind)] = chat_icon(kind)
    return out


def path_of(key):
    return os.path.join(BAR_DIR if key[0] == 'bar' else CHAT_DIR, key[1])


# ------------------------------------------------------------------ checks
def lua_const(path, name):
    text = open(path, encoding='utf-8').read()
    m = re.search(r'\bL\.%s\s*=\s*(-?\d+)' % re.escape(name), text)
    return int(m.group(1)) if m else None


def check(images):
    bad = []
    for key, img in images.items():
        p = path_of(key)
        if not os.path.exists(p):
            bad.append('%s missing' % os.path.relpath(p))
            continue
        have = Image.open(p).convert('RGBA')
        if have.size != img.size or have.tobytes() != img.tobytes():
            bad.append('%s differs from the generator' % os.path.relpath(p))
    wanted = {path_of(k) for k in images}
    for d in (BAR_DIR, CHAT_DIR):
        if os.path.isdir(d):
            for f in sorted(os.listdir(d)):
                if f.endswith('.png') and os.path.join(d, f) not in wanted:
                    bad.append('stray image %s' % os.path.relpath(os.path.join(d, f)))
    pairs = (('SLOT_FRAME', SLOT_FRAME), ('KEY_W', KEY_W), ('KEY_H', KEY_H), ('KEY_BORDER', KEY_BORDER),
             ('SOCKET', SOCKET), ('BODY_H', BODY_H), ('BODY_BORDER', BODY_BORDER),
             ('CAP_CLOSED_W', CAP_CLOSED_W), ('CAP_OPEN_W', CAP_OPEN_W))
    for name, value in pairs:
        got = lua_const(BAR_LOGIC, name)
        if got != value:
            bad.append('hotbar_logic.lua L.%s = %s, the art is %d' % (name, got, value))
    for name, value in (('BORDER', CHAT_BORDER),):
        got = lua_const(CHAT_LOGIC, name)
        if got != value:
            bad.append('floatchat_logic.lua L.%s = %s, the art is %d' % (name, got, value))
    return bad


# ------------------------------------------------------------------ preview
def nine(src, border, w, h):
    """a nine-slice stretched to w x h"""
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    sw, sh = src.size
    b = border
    xs = [(0, b, 0, b), (b, sw - b, b, w - b), (sw - b, sw, w - b, w)]
    ys = [(0, b, 0, b), (b, sh - b, b, h - b), (sh - b, sh, h - b, h)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            if dx1 <= dx0 or dy1 <= dy0:
                continue
            piece = src.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST)
            out.alpha_composite(piece, (dx0, dy0))
    return out


def globe(d_px, color, fill):
    """a stand-in globe for the preview: the real ring art over a flat disc"""
    ring_path = os.path.join(MODULES, 'game_shaderfx', 'images', 'orb_ring_150.png')
    img = Image.new('RGBA', (d_px, d_px), (0, 0, 0, 0))
    dd = ImageDraw.Draw(img)
    inner = int(d_px * 50 / 76)
    box = ((d_px - inner) // 2, (d_px - inner) // 2, (d_px + inner) // 2, (d_px + inner) // 2)
    dd.ellipse(box, fill=color + (255,))
    top = box[1] + int(inner * (1 - fill))
    dd.rectangle((box[0], box[1], box[2], top), fill=(0, 0, 0, 0))
    # redraw the disc edge so the empty part is clipped round
    mask = Image.new('L', (d_px, d_px), 0)
    ImageDraw.Draw(mask).ellipse(box, fill=255)
    img.putalpha(Image.fromarray(np.minimum(np.asarray(img.getchannel('A')), np.asarray(mask))))
    if os.path.exists(ring_path):
        ring = Image.open(ring_path).convert('RGBA').resize((d_px, d_px), Image.LANCZOS)
        img.alpha_composite(ring)
    return img


def preview(images, out_path, slots=6, scale=2):
    bar = {k[1]: v for k, v in images.items() if k[0] == 'bar'}
    chat = {k[1]: v for k, v in images.items() if k[0] == 'chat'}
    pitch = SLOT_FRAME + 4
    body_w = 2 * 14 + slots * pitch - 4 + 2 * (SOCKET + 8)
    orb = 110
    shots = []
    for globes in (True, False):
        capw = (orb + 6) if globes else CAP_CLOSED_W
        total = capw * 2 + body_w
        w, h = total, orb + 20
        img = Image.new('RGBA', (w, h), (30, 38, 30, 255))
        y0 = h - BODY_H - 4
        # frame: one nine-slice under everything, the caps over its ends
        img.alpha_composite(nine(bar['hotbar_body.png'], BODY_BORDER, total - (0 if globes else 0), BODY_H), (0, y0))
        cl = bar['hotbar_cap_open_l.png' if globes else 'hotbar_cap_closed_l.png']
        cr = bar['hotbar_cap_open_r.png' if globes else 'hotbar_cap_closed_r.png']
        if not globes:
            img.alpha_composite(cl, (0, y0))
            img.alpha_composite(cr, (total - cr.width, y0))
        x = capw + 14 + SOCKET + 8
        sy = y0 + 10
        img.alpha_composite(bar['hotbar_socket.png'], (capw + 14, sy + 6))
        img.alpha_composite(bar['hotbar_socket.png'], (total - capw - 14 - SOCKET, sy + 6))
        for i in range(slots):
            ready = i in (0, 2)
            img.alpha_composite(bar['hotbar_slot_ready.png' if ready else 'hotbar_slot.png'], (x + i * pitch, sy))
            if i == 1:  # a cooldown fill and number
                ov = Image.new('RGBA', (36, 36), (0, 0, 0, 170))
                img.alpha_composite(ov, (x + i * pitch + 4, sy + 4))
                ImageDraw.Draw(img).text((x + i * pitch + 14, sy + 14), '7', fill=(240, 232, 220, 255))
            kb = nine(bar['hotbar_key.png'], KEY_BORDER, KEY_W, KEY_H)
            img.alpha_composite(kb, (x + i * pitch + (SLOT_FRAME - KEY_W) // 2, sy + SLOT_FRAME - 4))
            ImageDraw.Draw(img).text((x + i * pitch + SLOT_FRAME // 2 - 2, sy + SLOT_FRAME - 2), str(i + 1),
                                     fill=(240, 220, 170, 255))
        img.alpha_composite(bar['hotbar_gem.png'], (total // 2 - 7, y0 - 5))
        img.alpha_composite(bar['hotbar_handle.png'], (total // 2 - 18, y0 + BODY_H - 6))
        if globes:
            img.alpha_composite(globe(orb, (200, 36, 40), 0.8), (3, h - orb - 2))
            img.alpha_composite(globe(orb, (47, 110, 240), 0.6), (total - orb - 3, h - orb - 2))
            img.alpha_composite(cl.crop((0, 0, cl.width, cl.height)), (capw - cl.width + 2, y0))
            img.alpha_composite(cr, (total - capw - 2, y0))
        shots.append(img)
    # the chat window
    cw, ch = 380, 150
    cimg = Image.new('RGBA', (cw, ch), (46, 58, 46, 255))
    shade = Image.new('RGBA', (cw, ch), (14, 10, 12, 191))  # 75%
    cimg.alpha_composite(shade)
    cimg.alpha_composite(nine(chat['chat_border.png'], CHAT_BORDER, cw, ch))
    dd = ImageDraw.Draw(cimg)
    dd.rectangle((6, 6, cw - 7, 26), fill=(10, 8, 10, 150))
    cimg.alpha_composite(chat['chat_channels.png'], (10, 9))
    dd.text((28, 10), 'Channels', fill=(232, 200, 154, 255))
    cimg.alpha_composite(chat['chat_caret.png'], (84, 9))
    dd.ellipse((100, 10, 114, 24), fill=(226, 98, 36, 255))
    dd.text((104, 11), '3', fill=(255, 255, 255, 255))
    cimg.alpha_composite(chat['chat_private.png'], (126, 9))
    dd.text((144, 10), 'Private', fill=(232, 200, 154, 255))
    cimg.alpha_composite(chat['chat_caret.png'], (190, 9))
    cimg.alpha_composite(chat['chat_close.png'], (cw - 24, 9))
    for i, line in enumerate(('21:04  Vexa: need a heal at the gate', '21:04  You see a stone tower.',
                              '21:05  Loot: 3 gold coins, a charred helm', '21:05  Mira: on my way')):
        dd.text((12, 34 + i * 14), line, fill=(222, 214, 200, 255))
    dd.rectangle((12, ch - 24, cw - 24, ch - 10), outline=(78, 70, 74, 255))
    cimg.alpha_composite(chat['chat_grip.png'], (cw - 20, ch - 20))
    pad = 10
    W = max(s.width for s in shots) + pad * 2
    H = sum(s.height for s in shots) + ch + pad * 4
    sheet = Image.new('RGBA', (W, H), (20, 24, 20, 255))
    y = pad
    for s in shots + [cimg]:
        sheet.alpha_composite(s, (pad, y))
        y += s.height + pad
    sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    sheet.convert('RGB').save(out_path)


def main(argv):
    images = art()
    if '--check' in argv:
        bad = check(images)
        for b in bad:
            print('gen_hotbar_art --check:', b)
        if bad:
            return 1
        print('gen_hotbar_art --check: %d images up to date' % len(images))
        return 0
    if '--preview' in argv:
        out = argv[argv.index('--preview') + 1]
        preview(images, out)
        print('wrote', out)
        return 0
    for d in (BAR_DIR, CHAT_DIR):
        os.makedirs(d, exist_ok=True)
    for key, img in images.items():
        img.save(path_of(key))
    print('wrote %d images' % len(images))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
