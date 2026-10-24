#!/usr/bin/env python3
"""Converts a purchased painted UI pack into the game-ready images of the Chaos skin (docs/CREDITS.md, "Art packs").

usage: python3 -I client/tools/import_hud_kit.py <pack-dir> [--list] [--full]

By default only the orb rings are written: the owner kept the pack's health and mana orbs and asked for the rest of
the UI back as it was (O155 rolled back). --full also writes the plate, action bar, window and control images below.

<pack-dir> holds the pack's own folders (HUD, Popup, Settings ..., see SRC below for the paths read). Nothing of
the pack is copied: every output is cropped, resized to the size the client style expects, 9-sliced or recoloured
here, and written over the image of the same name under client/overlay/data/images (and the orb ring under
client/overlay/modules/game_shaderfx/images). The pack's licence allows modifying, resizing and recolouring for a
game and forbids passing the files on as they are, so the originals never enter the repository.

Run order: gen_ui_reskin.py, gen_skin.py, then this tool (it replaces the images listed below; gen_skin.py draws the
same names procedurally and would overwrite them), then gen_orb_art.py for the liquid masks.

What it writes (same sizes and 9-slice borders as before, so no style changes):
  orbs        game_shaderfx/images/orb_ring_<S>.png   the ring of the health and mana orb, 2S x 2S per size S
                                                      (shaderfxlogic.lua ORB_SIZES); the opening is transparent
  plate       chaos/skin/hud_plate, hud_portrait_cover, hud_hp_fill, hud_mp_fill, hud_xp_fill, hud_level
                                                      the character plate of game_chaoshud (300 x 96)
  action bar  game/actionbar/slot-actionbar (34), slot-actionbar_ (44)
  windows     chaos/window, chaos/skin/window, ui/map-borderimage (minimap window), chaos/panel, panel_dark,
              panel_highlight, chaos/skin/tooltip
  controls    chaos/button_*, chaos/skin/button, chaos/tab_*, chaos/skin/tab, chaos/textedit, textedit_focus
Deterministic (no random numbers). Needs Pillow and numpy.
"""
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OVERLAY = os.path.normpath(os.path.join(HERE, '..', 'overlay'))
IMAGES = os.path.join(OVERLAY, 'data', 'images')
ORB_DIR = os.path.join(OVERLAY, 'modules', 'game_shaderfx', 'images')
LOGIC = os.path.join(OVERLAY, 'modules', 'game_shaderfx', 'shaderfxlogic.lua')
WRITTEN = []

# files read, relative to <pack-dir>
SRC = {
    'panel': 'HUD/PNG/Skill_Slots/Main_Panel.png',
    'avatar': 'HUD/PNG/Avatar_Frames/hud_avatar_frame_001.png',
    'plaque': 'HUD/PNG/Resource_Bars/hud_resource_bar_001.png',
    'hp_bg': 'HUD/PNG/Health_Bars/hud_health_bar_001bg.png',
    'hp': 'HUD/PNG/Health_Bars/hud_health_bar_001.png',
    'mp': 'HUD/PNG/Mana_Bars/hud_mana_bar_002.png',
    'xp': 'HUD/PNG/Energy_Bars/energy_bar_001.png',
    'frame': 'Popup/PNG/General_Popup/popup_general_003.png',
    'tip': 'Tooltip & Item Info UI Kit/tooltip_item_panel_001.png',
    'btn_normal': 'Settings UI Kit/button_primary_normal_001.png',
    'btn_hover': 'Settings UI Kit/button_primary_hover_001_.png',
    'btn_pressed': 'Settings UI Kit/button_primary_pressed_001.png',
    'btn_disabled': 'Settings UI Kit/button_primary_disabled_001.png',
    'tab_on': 'Popup/PNG/Inventory_Detail_Popup/Tab_Button_Active.png',
    'tab_off': 'Popup/PNG/Inventory_Detail_Popup/Tab_Button_Inactive.png',
    'input': 'Popup/PNG/Inventory_Detail_Popup/Input_Field.png',
    'badge': 'Dialogue & NPC/NPC_Nameplate.png',
}

GOLD_L = (232, 184, 74)
WELL = (13, 10, 13)


# ---------------------------------------------------------------- io
def load(kit, key):
    p = os.path.join(kit, SRC[key])
    if not os.path.isfile(p):
        sys.exit('import_hud_kit: missing ' + SRC[key] + ' in ' + kit)
    return Image.open(p).convert('RGBA')


def save(img, path, rel):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    WRITTEN.append(rel)


def save_image(img, rel):
    save(img, os.path.join(IMAGES, rel + '.png'), rel + '.png')


# ---------------------------------------------------------------- pieces
def rs(img, w, h):
    return img.resize((max(1, int(w)), max(1, int(h))), Image.LANCZOS)


def trim(img):
    """the image cropped to its opaque pixels: the pack's frames carry a few transparent texels on one side, which
    made one border of a 9-slice thinner than the other"""
    a = np.asarray(img)[..., 3]
    ys, xs = np.nonzero(a > 128)
    return img.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def seamless(arr, w, h):
    """a w x h tile of `arr` (at least w + f by h + f texels) whose left edge continues its right edge and whose top
    edge continues its bottom edge: the last f columns / rows are cross-faded into the first ones. The engine repeats
    the edges and the middle of a 9-slice image as they are, so any other tile shows a seam."""
    fx, fy = arr.shape[1] - w, arr.shape[0] - h   # the texels beyond the tile that are faded in
    a = arr[:h + fy, :w + fx].astype(np.float32)
    if fx:
        t = ((np.arange(fx) + 0.5) / fx)[None, :, None]
        head = a[:, :fx] * t + a[:, w:w + fx] * (1 - t)
        a = np.concatenate([head, a[:, fx:w]], axis=1)
    else:
        a = a[:, :w]
    if fy:
        t = ((np.arange(fy) + 0.5) / fy)[:, None, None]
        head = a[:fy] * t + a[h:h + fy] * (1 - t)
        a = np.concatenate([head, a[fy:h]], axis=0)
    else:
        a = a[:h]
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def nine(src, W, H, caps, borders, tile=True):
    """A W x H image with borders (l, t, r, b) made of the pack image `src` (trimmed to its opaque pixels). `caps` are
    the source texels the corners take: the whole image is resized so that each cap becomes its border (corners and
    edges stay whole and the same on both sides). The edges and the middle are samples of the resized image, cross-faded
    so that they repeat without a seam (tile=True, for engine 9-slice images, which repeat them), or stretched
    (tile=False, for an image drawn once)."""
    src = trim(src)
    kl, kt, kr, kb = caps
    l, t, r, b = borders
    KW, KH = src.size
    sx = (l + r) / float(kl + kr) if kl + kr else H / float(KH)
    sy = (t + b) / float(kt + kb) if kt + kb else W / float(KW)
    S = rs(src, KW * sx, KH * sy)
    SW, SH = S.size
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    iw, ih = W - l - r, H - t - b
    if l and t:
        out.paste(S.crop((0, 0, l, t)), (0, 0))
    if r and t:
        out.paste(S.crop((SW - r, 0, SW, t)), (W - r, 0))
    if l and b:
        out.paste(S.crop((0, SH - b, l, SH)), (0, H - b))
    if r and b:
        out.paste(S.crop((SW - r, SH - b, SW, SH)), (W - r, H - b))
    mw, mh = max(SW - l - r, 1), max(SH - t - b, 1)

    def part(box, w, h, ax=True, ay=True):
        """the sample of S inside `box` as a w x h piece"""
        bx0, by0, bx1, by1 = box
        if not tile:
            return rs(S.crop(box), w, h)
        n = w + (min(12, w // 3) if ax else 0)   # an edge repeats along itself only
        m = h + (min(12, h // 3) if ay else 0)
        cx, cy = (bx0 + bx1) // 2, (by0 + by1) // 2
        x0 = max(bx0, min(cx - n // 2, bx1 - n)) if bx1 - bx0 >= n else bx0
        y0 = max(by0, min(cy - m // 2, by1 - m)) if by1 - by0 >= m else by0
        arr = np.asarray(S.crop((x0, y0, x0 + n, y0 + m)))
        if arr.shape[1] < n or arr.shape[0] < m:   # the sample is shorter than the tile: stretch it
            arr = np.asarray(rs(S.crop(box), n, m))
        return seamless(arr, w, h)

    if iw > 0 and t:
        out.paste(part((l, 0, SW - r, t), iw, t, True, False), (l, 0))
    if iw > 0 and b:
        out.paste(part((l, SH - b, SW - r, SH), iw, b, True, False), (l, H - b))
    if ih > 0 and l:
        out.paste(part((0, t, l, SH - b), l, ih, False, True), (0, t))
    if ih > 0 and r:
        out.paste(part((SW - r, t, SW, SH - b), r, ih, False, True), (W - r, t))
    if iw > 0 and ih > 0:
        out.paste(part((l, t, SW - r, SH - b), iw, ih), (l, t))
    return out


def stack(*imgs):
    out = Image.new('RGBA', (imgs[0].width, sum(i.height for i in imgs)), (0, 0, 0, 0))
    y = 0
    for i in imgs:
        out.paste(i, (0, y))
        y += i.height
    return out


def tint(img, mul, add=(0, 0, 0)):
    a = np.asarray(img).astype(np.float32)
    for c in range(3):
        a[..., c] = a[..., c] * mul[c] + add[c]
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def outline(img, color, alpha):
    """a one texel outline of `color` over the edge of the image"""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    m = np.zeros((h, w), np.float32)
    m[0, :] = m[-1, :] = m[:, 0] = m[:, -1] = 1
    for c in range(3):
        a[..., c] = a[..., c] * (1 - m * alpha) + color[c] * m * alpha
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def circle_alpha(w, h, cx, cy, r, ramp=1.5):
    """0 inside the circle (r) and 1 outside, with a soft edge `ramp` texels wide"""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    return np.clip((d - r) / ramp + 0.5, 0, 1)


def scale_alpha(img, m):
    a = np.asarray(img).copy()
    a[..., 3] = np.clip(a[..., 3].astype(np.float32) * m + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(a, 'RGBA')


# ---------------------------------------------------------------- orbs
ORB_CENTER = (201.0, 209.0)  # centre of the opening of the left orb of the pack's panel image (image coordinates):
                             # the circle fitted to the edge of its dark disc, measured, not read off the picture
ORB_HOLE = 93.5              # that circle's radius (texels)
ORB_HALF = 142               # half the side of the square kept around it: ORB_HOLE / ORB_HALF is the 50 / 76 of the
                             # liquid (shaderfxlogic.lua L.orbSize), so the opening is as large as the liquid
ORB_EAST = (-55.0, 45.0)     # degrees: the side that joins the panel, cut from ORB_JOIN on
ORB_JOIN = 124
ORB_UNDER = 1.5              # texels the rim overlaps the liquid's soft edge (no gap of background between them)


def orb_source(kit):
    """the orb's ring on its own: a square of 2 * ORB_HALF texels centred on the opening"""
    panel = load(kit, 'panel')
    cx, cy = ORB_CENTER
    n = ORB_HALF
    img = panel.crop((int(cx) - n, int(cy) - n, int(cx) + n, int(cy) + n))
    size = 2 * n
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dx, dy = xx - (n - 0.5), yy - (n - 0.5)
    d = np.sqrt(dx ** 2 + dy ** 2)
    ang = np.degrees(np.arctan2(dy, dx))
    keep = np.clip((n - d) / 10.0, 0, 1)                             # soft outer edge
    # the side that joins the panel is cut back to ORB_JOIN, eased in and out over 20 degrees (no straight edge)
    mid, half = (ORB_EAST[0] + ORB_EAST[1]) / 2.0, (ORB_EAST[1] - ORB_EAST[0]) / 2.0
    f = np.clip((half - np.abs(ang - mid)) / 20.0, 0, 1)
    f = f * f * (3 - 2 * f)
    limit = n - (n - ORB_JOIN) * f
    keep = np.minimum(keep, np.clip((limit - d) / 6.0 + 0.5, 0, 1))
    return scale_alpha(img, keep)


def orb_sizes():
    text = open(LOGIC, encoding='utf-8').read()
    m = re.search(r'L\.ORB_SIZES = \{(.*?)\n\}', text, re.S)
    return [int(v) for v in re.findall(r'size = (\d+)', m.group(1))] if m else []


def liquid_size(size):
    """as shaderfxlogic.lua L.orbSize (and gen_orb_art.py): floor(size * 50 / 76 + 0.5)"""
    return int(size * 50 / 76.0 + 0.5)


def gen_orbs(kit):
    src = orb_source(kit)
    sizes = orb_sizes()
    if not sizes:
        sys.exit('import_hud_kit: no ORB_SIZES in ' + LOGIC)
    for s in sizes:
        ring = rs(src, 2 * s, 2 * s)
        # the opening: the liquid's mask is a disc of radius L - 1 texels (gen_orb_art.py) centred on the canvas, so
        # the ring is cut open on the same centre, a little narrower than the disc
        r_open = liquid_size(s) - 1 - ORB_UNDER
        ring = scale_alpha(ring, circle_alpha(2 * s, 2 * s, s - 0.5, s - 0.5, r_open))
        save(ring, os.path.join(ORB_DIR, 'orb_ring_%d.png' % s), 'orb_ring_%d.png' % s)
    return src


# ---------------------------------------------------------------- character plate (game_chaoshud)
# Every number here is a pixel of the plate (300 x 96); chaoshud.otui and chaoshud.lua (BAR_W) use the same ones.
HUD_W, HUD_H = 300, 96
HUD_PC = (47, 48)          # portrait centre
PLAQUE = (44, 3, 300, 93)  # the frame behind the bars: x0, y0, x1, y1 (its left part is under the portrait ring)
PLAQUE_BORDER = (40, 24, 40, 24)   # its corners; the dark trough is what is inside them
PLAQUE_CAPS = (50, 30, 50, 30)     # the source texels of those corners
TROUGH_X = (93, 287)       # the visible trough: from the portrait ring to the frame
TRACK_CAP = 14             # the rivet caps at the two ends of a bar's track
HUD_BAR_X, HUD_BAR_W = TROUGH_X[0] + TRACK_CAP, 166   # a fill: x and width; the track is 14 wider at each end
assert TROUGH_X[1] - TROUGH_X[0] == HUD_BAR_W + 2 * TRACK_CAP
HUD_BARS = {'hp': (35, 15), 'mp': (54, 13), 'xp': (71, 7)}   # fill y, height; the track is 1 taller at each side
HUD_NAME = (17, 15)        # y, height of the name line above the first track
AVATAR_SCALE = 0.9
AVATAR_CENTER = (49.5, 50.5)   # centre of the avatar ring in the pack image
AVATAR_HOLE = 27.0             # its opening, texels
LEVEL_SIZE = (40, 17)      # the level badge, under the portrait ring: centred on HUD_PC[0], from y 79 to the plate's bottom


def track(src, W, H):
    """the pack's rust-framed bar socket as W x H: its two ends kept, the middle stretched"""
    return nine(src, W, H, (29, 0, 27, 0), (TRACK_CAP, 0, TRACK_CAP, 0), tile=False)


def bar_fill(src, W, H):
    return rs(src.crop(src.getbbox()), W, H)


def gold_ramp(img):
    """the green bar redrawn gold (our experience colour), by brightness"""
    a = np.asarray(img).astype(np.float32)
    lum = a[..., :3].mean(axis=2)
    top = max(float(np.percentile(lum[a[..., 3] > 0], 99)), 1.0)
    t = np.clip(lum / top, 0, 1)[..., None]
    lo = np.array([70, 44, 10], np.float32)
    hi = np.array([255, 224, 140], np.float32)
    out = a.copy()
    out[..., :3] = lo + (hi - lo) * t
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def gen_plate(kit):
    avatar = load(kit, 'avatar')
    plate = Image.new('RGBA', (HUD_W, HUD_H), (0, 0, 0, 0))
    # frame behind the bars: the pack's wide bar frame, warmed (its slate interior is blue-grey)
    plaque = tint(load(kit, 'plaque'), (1.12, 0.98, 0.82))
    x0, y0, x1, y1 = PLAQUE
    plate.alpha_composite(nine(plaque, x1 - x0, y1 - y0, PLAQUE_CAPS, PLAQUE_BORDER, tile=False), (x0, y0))
    # the track of each bar: as wide as the trough, the fill sits between its caps
    socket = load(kit, 'hp_bg')
    for key, (y, h) in sorted(HUD_BARS.items()):
        plate.alpha_composite(track(socket, HUD_BAR_W + 2 * TRACK_CAP, h + 2), (HUD_BAR_X - TRACK_CAP, y - 1))
    # portrait ring
    w, h = int(round(avatar.width * AVATAR_SCALE)), int(round(avatar.height * AVATAR_SCALE))
    ring = rs(avatar, w, h)
    ox = int(round(HUD_PC[0] - AVATAR_CENTER[0] * AVATAR_SCALE))
    oy = int(round(HUD_PC[1] - AVATAR_CENTER[1] * AVATAR_SCALE))
    hole = AVATAR_HOLE * AVATAR_SCALE
    ring = scale_alpha(ring, circle_alpha(w, h, HUD_PC[0] - ox - 0.5, HUD_PC[1] - oy - 0.5, hole))
    plate.alpha_composite(ring, (ox, oy))
    # nothing of the frame behind the bars shows in the opening: the portrait (and the cover over it) is clear there
    plate = scale_alpha(plate, circle_alpha(HUD_W, HUD_H, HUD_PC[0] - 0.5, HUD_PC[1] - 0.5, hole))
    save_image(plate, 'chaos/skin/hud_plate')
    # the part of the plate over the portrait's square corners
    save_image(plate.crop((0, 0, 96, 96)), 'chaos/skin/hud_portrait_cover')
    save_image(bar_fill(load(kit, 'hp'), HUD_BAR_W, HUD_BARS['hp'][1]), 'chaos/skin/hud_hp_fill')
    save_image(bar_fill(load(kit, 'mp'), HUD_BAR_W, HUD_BARS['mp'][1]), 'chaos/skin/hud_mp_fill')
    save_image(bar_fill(gold_ramp(load(kit, 'xp')), HUD_BAR_W, HUD_BARS['xp'][1]), 'chaos/skin/hud_xp_fill')
    save_image(gen_level(kit), 'chaos/skin/hud_level')
    return hole


def gen_level(kit):
    """the level badge: the pack's stone name plate with its pointer (turned to point up at the ring), warmed"""
    plate = trim(load(kit, 'badge')).transpose(Image.FLIP_TOP_BOTTOM)
    return tint(rs(plate, *LEVEL_SIZE), (1.25, 1.05, 0.8), (6, 2, 0))


# ---------------------------------------------------------------- action bar slots
SLOT_BOX = (340, 188, 418, 266)   # the first of the panel's eight slot frames


def gen_slots(kit):
    frame = tint(load(kit, "panel").crop(SLOT_BOX), (1.7, 1.6, 1.5))
    for n, rel in ((34, 'game/actionbar/slot-actionbar'), (44, 'game/actionbar/slot-actionbar_')):
        bg = Image.new('RGBA', (n, n), WELL + (255,))
        bg.alpha_composite(rs(frame, n, n))
        save_image(bg, rel)


# ---------------------------------------------------------------- windows, panels, controls
def gen_windows(kit):
    frame = load(kit, 'frame')
    save_image(nine(frame, 96, 96, (24, 45, 24, 24), (18, 34, 18, 18)), 'chaos/window')
    save_image(nine(frame, 128, 128, (22, 58, 22, 22), (12, 32, 12, 12)), 'chaos/skin/window')
    # the minimap window (stock MapMiniWindow: border 4, top 19, bottom 4): at a third of the pack size
    save_image(nine(frame, 102, 114, (12, 57, 12, 12), (4, 19, 4, 4)), 'ui/map-borderimage')
    save_image(nine(frame, 32, 32, (24, 24, 24, 24), (8, 8, 8, 8)), 'chaos/panel')
    save_image(tint(nine(frame, 32, 32, (18, 18, 18, 18), (6, 6, 6, 6)), (0.8, 0.8, 0.8)), 'chaos/panel_dark')
    save_image(tint(nine(frame, 32, 32, (24, 24, 24, 24), (8, 8, 8, 8)), (1.5, 1.4, 1.2), (14, 9, 2)),
               'chaos/panel_highlight')
    save_image(nine(load(kit, 'tip'), 32, 32, (10, 10, 10, 10), (4, 4, 4, 4)), 'chaos/skin/tooltip')


def gen_controls(kit):
    states = ('normal', 'hover', 'pressed', 'disabled')
    btn = dict((s, load(kit, 'btn_' + s)) for s in states)
    for s in states:
        save_image(nine(btn[s], 48, 24, (18, 18, 18, 18), (6, 6, 6, 6)), 'chaos/button_' + s)
    save_image(stack(*[nine(btn[s], 64, 24, (15, 15, 15, 15), (5, 5, 5, 5)) for s in states]), 'chaos/skin/button')
    on, off = load(kit, 'tab_on'), load(kit, 'tab_off')
    tabs = {'normal': off, 'hover': tint(off, (1.5, 1.4, 1.3), (6, 4, 2)), 'active': on}
    for nm in ('normal', 'hover', 'active'):
        save_image(nine(tabs[nm], 40, 24, (12, 8, 12, 8), (6, 6, 6, 6)), 'chaos/tab_' + nm)
    save_image(stack(*[nine(tabs[nm], 64, 24, (12, 8, 12, 8), (5, 5, 5, 5)) for nm in ('normal', 'hover', 'active')]),
               'chaos/skin/tab')
    field = nine(load(kit, 'input'), 32, 22, (8, 8, 8, 8), (4, 4, 4, 4))
    save_image(field, 'chaos/textedit')
    save_image(outline(field, GOLD_L, 0.85), 'chaos/textedit_focus')


def untrack_reskin():
    """the images written here are ours: off the recolour tool's list (as gen_skin.py does)"""
    lst = os.path.join(IMAGES, 'RESKIN_FILES.txt')
    if not os.path.isfile(lst):
        return
    lines = open(lst).read().split('\n')
    mine = set(WRITTEN)
    kept = [l for l in lines if l.strip() not in mine]
    if len(kept) != len(lines):
        open(lst, 'w').write('\n'.join(kept))


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('--')]
    if '--list' in argv:
        for k in sorted(SRC):
            print(SRC[k])
        return
    if not args or not os.path.isdir(args[0]):
        sys.exit(__doc__)
    kit = args[0]
    gen_orbs(kit)
    if '--full' in argv:
        gen_plate(kit)
        gen_slots(kit)
        gen_windows(kit)
        gen_controls(kit)
    untrack_reskin()
    print('%d images written' % len(WRITTEN))


if __name__ == '__main__':
    main(sys.argv)
