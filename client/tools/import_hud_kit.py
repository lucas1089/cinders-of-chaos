#!/usr/bin/env python3
"""Converts a purchased painted UI pack into the game-ready images of the Chaos skin (docs/CREDITS.md, "Art packs").

usage: python3 -I client/tools/import_hud_kit.py <pack-dir> [--list]

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


def mirrored(img, axis, n):
    """`img` (a sample) laid out to n texels along `axis` (0 = x, 1 = y) as itself and its mirror image, so the
    result tiles without a seam (the engine tiles the edges and the middle of a 9-slice image)"""
    arr = np.asarray(img)
    ax = 1 if axis == 0 else 0
    both = np.concatenate([arr, np.flip(arr, ax)], axis=ax)
    sl = [slice(None), slice(None)]
    sl[ax] = slice(0, n)
    return Image.fromarray(np.ascontiguousarray(both[tuple(sl)]), 'RGBA')


def nine(src, W, H, caps, borders):
    """A W x H image with borders (l, t, r, b) made of the pack image `src`: its corners (caps in pack texels),
    a sample of its edges and of its middle, each resized and made tileable"""
    kl, kt, kr, kb = caps
    l, t, r, b = borders
    KW, KH = src.size
    iw, ih = W - l - r, H - t - b
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sx = (l + r) / float(kl + kr) if kl + kr else H / float(KH)
    sy = (t + b) / float(kt + kb) if kt + kb else W / float(KW)
    nx = max(2, int(round(iw / sx / 2)))   # texels of a sample that fills half of the middle
    ny = max(2, int(round(ih / sy / 2)))
    x0, y0 = (KW - nx) // 2, (KH - ny) // 2
    if l and t:
        out.paste(rs(src.crop((0, 0, kl, kt)), l, t), (0, 0))
    if r and t:
        out.paste(rs(src.crop((KW - kr, 0, KW, kt)), r, t), (W - r, 0))
    if l and b:
        out.paste(rs(src.crop((0, KH - kb, kl, KH)), l, b), (0, H - b))
    if r and b:
        out.paste(rs(src.crop((KW - kr, KH - kb, KW, KH)), r, b), (W - r, H - b))
    half_w, half_h = (iw + 1) // 2, (ih + 1) // 2
    if t and iw > 0:
        out.paste(mirrored(rs(src.crop((x0, 0, x0 + nx, kt)), half_w, t), 0, iw), (l, 0))
    if b and iw > 0:
        out.paste(mirrored(rs(src.crop((x0, KH - kb, x0 + nx, KH)), half_w, b), 0, iw), (l, H - b))
    if l and ih > 0:
        out.paste(mirrored(rs(src.crop((0, y0, kl, y0 + ny)), l, half_h), 1, ih), (0, t))
    if r and ih > 0:
        out.paste(mirrored(rs(src.crop((KW - kr, y0, KW, y0 + ny)), r, half_h), 1, ih), (W - r, t))
    if iw > 0 and ih > 0:
        mid = rs(src.crop((x0, y0, x0 + nx, y0 + ny)), half_w, half_h)
        out.paste(mirrored(mirrored(mid, 0, iw), 1, ih), (l, t))
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
ORB_CENTER = (198, 207)   # centre of the left orb of the pack's panel image
ORB_HOLE = 97             # radius of its opening (texels)
ORB_RADIUS = 152          # radius kept (the outer spikes and the chain beyond it are cut with a soft edge)
ORB_EAST = (-55.0, 45.0)  # degrees: the side that joins the panel, cut from ORB_JOIN on
ORB_JOIN = 134


def orb_source(kit):
    """the orb's ring on its own: a square of 2 * ORB_RADIUS texels, the opening transparent"""
    panel = load(kit, 'panel')
    cx, cy = ORB_CENTER
    n = ORB_RADIUS
    img = panel.crop((cx - n, cy - n, cx + n, cy + n))
    size = 2 * n
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dx, dy = xx - (n - 0.5), yy - (n - 0.5)
    d = np.sqrt(dx ** 2 + dy ** 2)
    ang = np.degrees(np.arctan2(dy, dx))
    keep = np.clip((n - d) / 10.0, 0, 1)                             # soft outer edge
    east = (ang > ORB_EAST[0]) & (ang < ORB_EAST[1])
    keep = np.where(east, np.minimum(keep, np.clip((ORB_JOIN - d) / 6.0 + 0.5, 0, 1)), keep)
    keep = keep * np.clip((d - ORB_HOLE) / 1.5 + 0.5, 0, 1)         # the opening
    return scale_alpha(img, keep)


def orb_sizes():
    text = open(LOGIC, encoding='utf-8').read()
    m = re.search(r'L\.ORB_SIZES = \{(.*?)\n\}', text, re.S)
    return [int(v) for v in re.findall(r'size = (\d+)', m.group(1))] if m else []


def gen_orbs(kit):
    src = orb_source(kit)
    sizes = orb_sizes()
    if not sizes:
        sys.exit('import_hud_kit: no ORB_SIZES in ' + LOGIC)
    for s in sizes:
        save(rs(src, 2 * s, 2 * s), os.path.join(ORB_DIR, 'orb_ring_%d.png' % s), 'orb_ring_%d.png' % s)
    return src


# ---------------------------------------------------------------- character plate (game_chaoshud)
HUD_W, HUD_H = 300, 96
HUD_PC = (47, 48)          # portrait centre
HUD_BAR_X, HUD_BAR_W = 96, 166
HUD_BARS = {'hp': (35, 15), 'mp': (54, 13), 'xp': (71, 5)}   # y, height
AVATAR_SCALE = 0.9
AVATAR_CENTER = (49.5, 50.5)   # centre of the avatar ring in the pack image
AVATAR_HOLE = 27.0             # its opening, texels


def bar_frame(src, W, H):
    """the pack's rust-framed bar socket as W x H: its two ends kept, the middle repeated"""
    cap = int(round(28 * H / float(src.height)))
    return nine(src, W, H, (28, 0, 28, 0), (cap, 0, cap, 0))


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
    # plaque behind the bars: the pack's wide bar frame, warmed (its slate interior is blue-grey)
    plaque = tint(load(kit, 'plaque'), (1.12, 0.98, 0.82))
    plate.alpha_composite(rs(plaque, 246, 70), (51, 14))
    # sockets of the three bars
    hp_bg = load(kit, 'hp_bg')
    for key, (y, h) in sorted(HUD_BARS.items()):
        plate.alpha_composite(bar_frame(hp_bg, HUD_BAR_W + 4, h + 4), (HUD_BAR_X - 2, y - 2))
    # portrait ring
    w, h = int(round(avatar.width * AVATAR_SCALE)), int(round(avatar.height * AVATAR_SCALE))
    ring = rs(avatar, w, h)
    ox = int(round(HUD_PC[0] - AVATAR_CENTER[0] * AVATAR_SCALE))
    oy = int(round(HUD_PC[1] - AVATAR_CENTER[1] * AVATAR_SCALE))
    hole = AVATAR_HOLE * AVATAR_SCALE
    ring = scale_alpha(ring, circle_alpha(w, h, HUD_PC[0] - ox - 0.5, HUD_PC[1] - oy - 0.5, hole))
    plate.alpha_composite(ring, (ox, oy))
    save_image(plate, 'chaos/skin/hud_plate')
    # the part of the plate over the portrait's square corners
    save_image(plate.crop((0, 0, 96, 96)), 'chaos/skin/hud_portrait_cover')
    save_image(bar_fill(load(kit, 'hp'), HUD_BAR_W, HUD_BARS['hp'][1]), 'chaos/skin/hud_hp_fill')
    save_image(bar_fill(load(kit, 'mp'), HUD_BAR_W, HUD_BARS['mp'][1]), 'chaos/skin/hud_mp_fill')
    save_image(bar_fill(gold_ramp(load(kit, 'xp')), HUD_BAR_W, HUD_BARS['xp'][1]), 'chaos/skin/hud_xp_fill')
    save_image(nine(load(kit, 'btn_pressed'), 40, 18, (18, 18, 18, 18), (4, 4, 4, 4)), 'chaos/skin/hud_level')
    return hole


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
    save_image(nine(frame, 96, 96, (18, 34, 18, 18), (18, 34, 18, 18)), 'chaos/window')
    save_image(nine(frame, 128, 128, (12, 32, 12, 12), (12, 32, 12, 12)), 'chaos/skin/window')
    # the minimap window (stock MapMiniWindow: border 4, top 19, bottom 4): half the size
    save_image(nine(frame, 102, 114, (8, 38, 8, 8), (4, 19, 4, 4)), 'ui/map-borderimage')
    save_image(nine(frame, 32, 32, (8, 8, 8, 8), (8, 8, 8, 8)), 'chaos/panel')
    save_image(tint(nine(frame, 32, 32, (6, 6, 6, 6), (6, 6, 6, 6)), (0.8, 0.8, 0.8)), 'chaos/panel_dark')
    save_image(tint(nine(frame, 32, 32, (8, 8, 8, 8), (8, 8, 8, 8)), (1.5, 1.4, 1.2), (14, 9, 2)),
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
    gen_plate(kit)
    gen_slots(kit)
    gen_windows(kit)
    gen_controls(kit)
    untrack_reskin()
    print('%d images written' % len(WRITTEN))


if __name__ == '__main__':
    main(sys.argv)
