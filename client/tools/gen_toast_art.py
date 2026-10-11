#!/usr/bin/env python3
"""Art of the game_chaosnotify toasts: the answer buttons and the party invitation icon.

usage: python3 -I client/tools/gen_toast_art.py [OUTDIR] [--sheet SHEET.png]
       default OUTDIR: client/overlay/modules/game_chaosnotify/images/toast
       --sheet also writes a contact sheet at 3x on a toast-coloured backdrop (not shipped)

Files:
  accept.png        80x96: the "yes" button (Accept, Start), four 80x24 states stacked top to bottom:
                    normal, hover, pressed, disabled (image-clip 0 0 / 0 24 / 0 48 / 0 72, toastbuttons.otui)
  decline.png       80x96: the "no" button (Decline, Cancel), same layout
  party_invite.png  48x48: the PARTY INVITATION icon (crossed swords over an iron buckler), drawn at the size the
                    toast shows it, so it is never scaled

The plates carry no text: the client draws the label in its own font (the Chaos heading font when it is loaded), so
one image serves Accept and Start, another Decline and Cancel, and the text stays crisp.

House look (gen_skin.py, gen_monsterbar_art.py): blackened iron lit from the top left, a thin gold rim on a black
outline, a bevel inside the rim (inverted when pressed). The accent tells the answer apart without shouting:
  accept   a faint ember-green tint in the iron, an ember-green hairline under the bevel and a low glow rising from the
           bottom edge; hover brightens the rim to light gold and the glow; pressed sinks the face
  decline  the same in muted crimson
  disabled grey steel rim, no glow, desaturated
Materials come from gen_skin.py. Every alpha edge is hard (the four corner pixels are cut, nothing else is
transparent) and there is no blur halo, so the art stays crisp at 1x. Our own art; deterministic (fixed seeds).
Needs Pillow and numpy.
"""
import importlib.util
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, '..', 'overlay', 'modules', 'game_chaosnotify', 'images', 'toast'))


def _load(name):
    # by path: python -I leaves the script's folder off sys.path
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sk = _load('gen_skin')
hexc = sk.hexc

BW, BH, BB = 80, 24, 5          # button size and bevel border
STATES = ('normal', 'hover', 'pressed', 'disabled')

ACCENTS = {
    # face tint, hairline, glow
    'accept': dict(tint=hexc('#262b24'), line=hexc('#7fae4a'), glow=hexc('#5f9a32'), seed=71),
    'decline': dict(tint=hexc('#2e2226'), line=hexc('#b23a2c'), glow=hexc('#9c1d14'), seed=72),
}


# ============================================================== buttons
def plate(kind, state):
    a = ACCENTS[kind]
    W, H, b = BW, BH, BB
    x, y, dl, dr, dt, db = sk.edge_maps(H, W)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
    tone = {'normal': 1.1, 'hover': 1.28, 'pressed': 0.78, 'disabled': 0.8}[state]
    face = sk.mat_iron(H, W, a['seed'], tone=tone, tint=a['tint'])
    # a soft vertical falloff: the top of the face catches more light than the bottom
    face = face * (1.08 - 0.16 * (y / (H - 1)))[..., None]
    rim = {'normal': sk.GOLD * 0.9, 'hover': sk.GOLD_L * 1.05, 'pressed': sk.GOLD * 0.62,
           'disabled': sk.STEEL * 0.62}[state]
    alb = face.copy()
    alb[(d >= 1) & (d < 2)] = rim
    up = state != 'pressed'
    near = np.argmin(np.stack([dt, dl, db, dr]), 0)
    zone = (d >= 2) & (d < b)
    fall = np.clip(1 - (d - 2) / max(b - 2, 1), 0, 1)
    k = np.ones((H, W), np.float32)
    k = np.where(zone & (near <= 1), 1 + (0.48 if up else -0.38) * fall, k)
    k = np.where(zone & (near >= 2), 1 - (0.42 if up else -0.12) * fall, k)
    rgb = np.clip(alb * k[..., None], 0, 1)
    # the accent glow rises from the bottom edge of the face
    g = {'normal': 0.30, 'hover': 0.55, 'pressed': 0.18, 'disabled': 0.0}[state]
    if g:
        inner = (d >= b)
        rise = np.exp(-np.clip(db - b, 0, None) / 4.5) * inner
        rgb = np.clip(rgb + rise[..., None] * a['glow'][None, None, :] * g, 0, 1)
    # the accent hairline just inside the bevel (dimmer on top, where the bevel is lit)
    if state != 'disabled':
        ln = (d >= b) & (d < b + 1)
        lw = {'normal': 0.45, 'hover': 0.8, 'pressed': 0.35}[state]
        lw_map = np.where(near[..., None] == 0, lw * 0.45, lw)
        rgb = np.where(ln[..., None], rgb * (1 - lw_map) + a['line'][None, None, :] * lw_map, rgb)
    # a lit top edge on the rim
    rgb[(d >= 1) & (d < 2) & (dt < 2)] = np.clip(rim * 1.35, 0, 1)
    out = sk.rgba(rgb)
    sk.blend_rgb(out, sk.BLACK, (d < 1).astype(np.float32) * 0.92)
    for (cx, cy) in ((0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)):
        out[cy, cx, 3] = 0.0
    if state == 'disabled':
        gr = out[..., :3].mean(-1, keepdims=True)
        out[..., :3] = out[..., :3] * 0.35 + gr * 0.65
    return out


def button_sheet(kind):
    return sk.stack(*[plate(kind, st) for st in STATES])


# ============================================================== party invitation icon
N = 48


def icon_party():
    s = 4
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    # backdrop: the abyss stone of the Chaos panels with an ember warmth behind the emblem
    bg = sk.mat_stone(N, N, 81, tint=hexc('#141016'))
    c = (N - 1) / 2.0
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    warm = np.clip(1 - r / 26.0, 0, 1) ** 1.6
    bg = np.clip(bg + warm[..., None] * hexc('#7a2a0c')[None, None, :] * 0.55, 0, 1)
    out = sk.rgba(bg)

    # iron buckler with a gold rim and a central boss
    R0 = 13.0
    disc = np.clip(R0 + 0.5 - r, 0, 1)
    hb = np.sqrt(np.clip(1 - (r / R0) ** 2, 0, 1)) * 2.4
    shield = sk.shade(hb, sk.mat_iron(N, N, 82, tone=1.05), amb=0.4, diff=0.85, spec=0.4, shin=14, strength=1.0)
    ring = (r > R0 - 2.2) & (r <= R0 + 0.5)
    ringh = np.clip(1 - np.abs(r - (R0 - 0.9)) / 1.3, 0, 1) * 1.6
    gold = sk.shade(ringh, sk.mat_gold(N, N, 83), amb=0.45, diff=0.9, spec=0.8, shin=10, strength=1.2)
    shield = np.where(ring[..., None], gold, shield)
    sk.over(out, sk.rgba(np.zeros((N, N, 3), np.float32), np.clip(R0 + 1.6 - np.sqrt((xx - c - 1) ** 2 + (yy - c - 1) ** 2), 0, 1) * 0.7))
    sk.over(out, sk.rgba(shield, (disc > 0.5).astype(np.float32)))

    # two crossed swords, blades to the top corners, hilts to the bottom corners
    def sword(flip):
        def draw(d, ss):
            def P(px, py):
                if flip:
                    px = N - 1 - px
                return (px * ss, py * ss)
            # blade: from the hilt (low left) to the tip (high right)
            bx0, by0, bx1, by1 = 13.0, 35.0, 40.5, 7.5
            ang = math.atan2(by1 - by0, bx1 - bx0)
            nx, ny = -math.sin(ang), math.cos(ang)
            w = 1.9
            tipx, tipy = bx1 + math.cos(ang) * 2.5, by1 + math.sin(ang) * 2.5
            d.polygon([P(bx0 + nx * w, by0 + ny * w), P(bx1 + nx * w, by1 + ny * w), P(tipx, tipy),
                       P(bx1 - nx * w, by1 - ny * w), P(bx0 - nx * w, by0 - ny * w)], fill=255)
        return sk.mask_draw(N, N, draw, ss=s)

    def guard(flip):
        def draw(d, ss):
            def P(px, py):
                if flip:
                    px = N - 1 - px
                return (px * ss, py * ss)
            # crossguard across the blade near the hilt, grip and pommel
            gx, gy = 13.0, 35.0
            ang = math.atan2(7.5 - 35.0, 40.5 - 13.0)
            nx, ny = -math.sin(ang), math.cos(ang)
            ux, uy = math.cos(ang), math.sin(ang)
            gl, gw = 5.2, 1.3
            d.polygon([P(gx + nx * gl + ux * gw, gy + ny * gl + uy * gw), P(gx - nx * gl + ux * gw, gy - ny * gl + uy * gw),
                       P(gx - nx * gl - ux * gw, gy - ny * gl - uy * gw), P(gx + nx * gl - ux * gw, gy + ny * gl - uy * gw)],
                      fill=255)
            hx, hy = gx - ux * 6.0, gy - uy * 6.0
            d.line([P(gx, gy), P(hx, hy)], fill=255, width=int(2.6 * ss))
            pr = 2.0 * ss
            px, py = P(hx - ux * 1.2, hy - uy * 1.2)
            d.ellipse([px - pr, py - pr, px + pr, py + pr], fill=255)
        return sk.mask_draw(N, N, draw, ss=s)

    steel = np.ones((N, N, 3), np.float32) * hexc('#b9b2b4')[None, None, :]
    goldalb = sk.mat_gold(N, N, 84, tone=1.1)
    for flip in (False, True):
        bm = (sword(flip) > 0.5).astype(np.float32)
        gm = (guard(flip) > 0.5).astype(np.float32)
        blade = sk.metal_from_mask(bm, steel, height_scale=1.6, blur=0.6, spec=1.0, shin=16, outline=0.95,
                                   shadow=0.8)
        hilt = sk.metal_from_mask(gm, goldalb, height_scale=1.8, blur=0.6, spec=0.9, shin=10, outline=0.95,
                                  shadow=0.8)
        for img in (blade, hilt):
            img[..., 3] = (img[..., 3] > 0.5).astype(np.float32)   # hard alpha edges
            sk.over(out, img)

    # the buckler's boss: a small ember gem where the blades cross
    g = sk.gem(3, hexc('#a8320c'), sk.EMBER, glow=0.0)
    g[..., 3] = (g[..., 3] > 0.5).astype(np.float32)
    gn = g.shape[0]
    sk.over(out, g, int(round(c - gn // 2)), int(round(c - gn // 2)) + 1)

    # a thin gold rim on a black outline, like the toast's own icon box
    d = sk.dist_rect(N, N)
    sk.blend_rgb(out, sk.GOLD * 0.85, ((d >= 1) & (d < 2)).astype(np.float32))
    sk.blend_rgb(out, sk.GOLD_L, ((d >= 1) & (d < 2) & (yy < 2)).astype(np.float32) * 0.6)
    sk.blend_rgb(out, sk.BLACK, (d < 1).astype(np.float32) * 0.92)
    out[..., 3] = 1.0
    return out


# ============================================================== io
def to_img(a):
    return sk.to_img(a) if hasattr(sk, 'to_img') else Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))


def write(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = to_img(img)
    im.save(path, optimize=True)
    print('wrote', os.path.relpath(path), im.size)
    return im


def sheet(images, path):
    pad, z = 8, 3
    ims = [im.resize((im.width * z, im.height * z), Image.NEAREST) for im in images]
    W = sum(i.width for i in ims) + pad * (len(ims) + 1)
    H = max(i.height for i in ims) + 2 * pad
    bg = Image.new('RGBA', (W, H), (34, 28, 26, 255))
    x = pad
    for i in ims:
        bg.alpha_composite(i, (x, pad))
        x += i.width + pad
    bg.save(path)
    print('wrote', path)


def main(argv):
    args = argv[1:]
    sheet_path = None
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet_path = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else DEFAULT_OUT
    imgs = [write(button_sheet('accept'), os.path.join(out, 'accept.png')),
            write(button_sheet('decline'), os.path.join(out, 'decline.png')),
            write(icon_party(), os.path.join(out, 'party_invite.png'))]
    if sheet_path:
        sheet(imgs, sheet_path)


if __name__ == '__main__':
    main(sys.argv)
