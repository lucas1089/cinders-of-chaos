#!/usr/bin/env python3
"""Art of the game_chaosnotify toasts: the answer buttons and every toast icon of our own.

usage: python3 -I client/tools/gen_toast_art.py [OUTDIR] [--sheet SHEET.png]
       python3 -I client/tools/gen_toast_art.py --check     (draws into a temporary folder, fails when a shipped file differs)
       default OUTDIR: client/overlay/modules/game_chaosnotify/images/toast
       --sheet also writes a contact sheet at 3x on a toast-coloured backdrop (not shipped)

Files:
  accept.png        80x96: the "yes" button (Accept, Start), four 80x24 states stacked top to bottom:
                    normal, hover, pressed, disabled (image-clip 0 0 / 0 24 / 0 48 / 0 72, toastbuttons.otui)
  decline.png       80x96: the "no" button (Decline, Cancel), same layout
  party_invite.png  48x48: the PARTY INVITATION icon (crossed swords over an iron buckler), drawn at the size the
                    toast shows it, so it is never scaled
  catacomb_invite.png 48x48: the CATACOMB AVAILABLE icon (a stone archway with a skull keystone, an iron band
                    outside, a gold rim round the doorway, ember light rising from the stairs inside), same size and
                    frame as the party icon
  message icons     48x48 each, same frame, backdrop and materials, no text (TYPE -> file, notifications.lua):
    announce.png      GM_BROADCAST and the fallback: a sealed scroll, crimson ribbon, gold seal with an ember stone
    task.png          TASK_COMPLETE: a parchment pinned by an iron nail, ruled lines, an ember-green check mark
    season_pass.png   BATTLE_PASS, SEASON_PASS: a gold medallion with an ember stone in a laurel wreath
    new_player.png    NEW_PLAYER: an iron lantern with an ember flame
    ascension.png     ASCENSION: a rising flame between two gold wings
    market.png        MARKET: gold balance scales on an iron post
    invasion.png      INVASION: two crossed war axes over a blood-red glow
    bounty.png        BOUNTY: a wanted poster (hooded head) pinned by a dagger
    bestiary.png      BESTIARY: a leather tome torn by three claw marks
    journey.png       JOURNEY: a compass, gold ring, ember north needle
    boss_point.png    BOSS_POINT: a crowned skull with ember eyes
    pact.png          PACT: the Chaos Pact runs out soon (O317): a gold-capped hourglass, ember sand, an ember stone

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


# ============================================================== catacomb invitation icon
def _grow(m):
    """Binary mask grown by one pixel (4-neighbours)."""
    g = m.copy()
    g[1:, :] |= m[:-1, :]
    g[:-1, :] |= m[1:, :]
    g[:, 1:] |= m[:, :-1]
    g[:, :-1] |= m[:, 1:]
    return g


def icon_catacomb():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    c = (N - 1) / 2.0
    # backdrop: the same abyss stone as the party icon, a colder warmth (the light is in the door)
    bg = sk.mat_stone(N, N, 91, tint=hexc('#141016'))
    r0 = np.sqrt((xx - c) ** 2 + (yy - 30) ** 2)
    bg = np.clip(bg + (np.clip(1 - r0 / 30.0, 0, 1) ** 2)[..., None] * hexc('#5a1e0a')[None, None, :] * 0.35, 0, 1)
    out = sk.rgba(bg)

    # the archway: a round arch on two jambs, the doorway inside it
    ay = 20.0                      # springing line of the arch
    ri, ro = 7.5, 14.5             # inner and outer radius
    floor_y = 41
    r = np.sqrt((xx - c) ** 2 + (yy - ay) ** 2)
    upper = yy <= ay
    opening = np.where(upper, r <= ri, np.abs(xx - c) <= ri) & (yy <= floor_y)
    outer = np.where(upper, r <= ro, np.abs(xx - c) <= ro) & (yy <= floor_y + 1)
    ring = outer & ~opening

    # joints: seven voussoirs over the arch (the middle one is the keystone), coursed blocks down the jambs
    ang = np.arctan2(ay - yy, xx - c)                       # 0 at the right springer, pi at the left
    step = math.pi / 7
    k = np.round(ang / step)
    arcjoint = upper & (np.abs(ang - k * step) * r < 0.55) & (k > 0) & (k < 7)
    course = np.floor((yy - ay) / 5.5)
    jamb = ~upper
    rowjoint = jamb & (np.abs((yy - ay) - np.round((yy - ay) / 5.5) * 5.5) < 0.5) & (yy > ay + 1)
    side = np.where(xx < c, -1, 1)
    mid = c + side * (ri + ro) / 2 + np.where(course % 2 == 0, -1.0, 1.0) * side * 0.5
    vjoint = jamb & (np.abs(xx - mid) < 0.5) & (course % 2 == 0)
    joints = ring & (arcjoint | rowjoint | vjoint | (upper & (np.abs(yy - ay) < 0.5)))
    blocks = ring & ~joints

    # the stone: each block a low cushion (lit from the top left), the joints sunk and dark
    stone = sk.mat_stone(N, N, 92, tint=hexc('#544c52'), tone=1.0)
    hgt = sk.gauss(blocks.astype(np.float32), 0.7) * 2.2
    lit = sk.shade(hgt, stone, amb=0.4, diff=0.9, spec=0.25, shin=12, strength=1.3)
    # ember light from the doorway warms the inner faces of the arch
    din = np.where(upper, r - ri, np.abs(xx - c) - ri)
    warm = np.clip(1 - din / 5.0, 0, 1) ** 1.5 * np.clip((yy - 4) / 30.0, 0.25, 1)
    lit = np.clip(lit + warm[..., None] * hexc('#c2410c')[None, None, :] * 0.55, 0, 1)
    lit = np.where(joints[..., None], hexc('#0c090b')[None, None, :], lit)

    # inside the door: black depth, an ember glow rising from the stairs going down
    gd = np.sqrt(((xx - c) / 1.15) ** 2 + (yy - (floor_y + 2)) ** 2)
    glow = np.clip(1 - gd / 17.0, 0, 1) ** 1.7
    dark = hexc('#07040a')[None, None, :] * np.ones((N, N, 1), np.float32)
    inside = np.clip(dark + glow[..., None] * hexc('#ff6a1a')[None, None, :] * 1.05
                     + (glow ** 3)[..., None] * hexc('#ffd27a')[None, None, :] * 0.6, 0, 1)
    for sy in (floor_y - 9, floor_y - 6, floor_y - 3):
        w = ri - (floor_y - sy) * 0.35
        edge = (np.abs(yy - sy) < 0.5) & (np.abs(xx - c) <= w)
        inside = np.where(edge[..., None], np.clip(inside * 1.6 + hexc('#ffb347') * 0.18, 0, 1), inside)
        under = (np.abs(yy - sy - 1) < 0.5) & (np.abs(xx - c) <= w)
        inside = np.where(under[..., None], inside * 0.45, inside)

    # drop shadow of the arch on the wall, then the arch and the door
    sh = np.zeros((N, N), bool)
    sh[1:, 1:] = outer[:-1, :-1]
    sk.blend_rgb(out, sk.BLACK, (sh & ~outer).astype(np.float32) * 0.7)
    out[..., :3] = np.where(ring[..., None], lit, out[..., :3])
    out[..., :3] = np.where(opening[..., None], inside, out[..., :3])

    # iron band round the outside of the arch, gold rim round the doorway
    iron_band = ring & _grow(~outer)
    gold_band = ring & _grow(opening) & ~iron_band
    ironc = sk.mat_iron(N, N, 93, tone=1.0, tint=sk.STEEL * 0.85)
    ironc = np.where(((yy < ay) & (xx < c + 2))[..., None], np.clip(ironc * 1.35, 0, 1), ironc * 0.8)
    out[..., :3] = np.where(iron_band[..., None], ironc, out[..., :3])
    goldc = sk.mat_gold(N, N, 94, tone=1.05)
    goldc = np.where(((yy < ay) & (xx < c + 2))[..., None], np.clip(goldc * 1.3, 0, 1), goldc)
    out[..., :3] = np.where(gold_band[..., None], goldc, out[..., :3])
    sk.blend_rgb(out, sk.BLACK, (_grow(outer) & ~outer).astype(np.float32) * 0.85)

    # threshold slab under the door
    slab = (yy >= floor_y + 2) & (yy <= floor_y + 3) & (np.abs(xx - c) <= ro + 1.5)
    slabc = sk.mat_stone(N, N, 95, tint=hexc('#3b3439'))
    slabc = np.where((yy == floor_y + 2)[..., None], np.clip(slabc * 1.35 + hexc('#7a2a0c') * 0.25, 0, 1), slabc)
    out[..., :3] = np.where(slab[..., None], slabc, out[..., :3])

    # the skull keystone: bone, hard edged, ember light in the eyes
    sx, sy0 = c, 8.0
    cran = ((xx - sx) / 4.6) ** 2 + ((yy - sy0) / 4.1) ** 2 <= 1.0
    jaw = (np.abs(xx - sx) <= 2.6) & (yy > sy0) & (yy <= sy0 + 5.0)
    skull = cran | jaw
    bone = np.ones((N, N, 3), np.float32) * hexc('#cbbd9f')[None, None, :]
    sk_img = sk.metal_from_mask(skull.astype(np.float32), bone, height_scale=2.0, blur=0.8, spec=0.35, shin=10,
                                outline=0.95, shadow=0.85)
    sk_img[..., 3] = (sk_img[..., 3] > 0.5).astype(np.float32)
    sk.over(out, sk_img)
    eyes = ((np.abs(xx - (sx - 2.0)) <= 1.0) | (np.abs(xx - (sx + 2.0)) <= 1.0)) & (yy >= sy0) & (yy <= sy0 + 1.0)
    out[..., :3] = np.where(eyes[..., None], hexc('#1a0604')[None, None, :], out[..., :3])
    pupils = eyes & (yy == sy0 + 1.0) & ((np.abs(xx - (sx - 2.0)) <= 0.5) | (np.abs(xx - (sx + 2.0)) <= 0.5))
    out[..., :3] = np.where(pupils[..., None], sk.EMBER[None, None, :], out[..., :3])
    nose = (np.abs(xx - sx) <= 0.5) & (yy == sy0 + 2.0)
    teeth = (yy == sy0 + 4.0) & (np.abs(xx - sx) <= 2.0) & ((np.floor(xx - sx + 0.5) % 2) == 0)
    out[..., :3] = np.where((nose | teeth)[..., None], hexc('#2a1f1a')[None, None, :], out[..., :3])

    # a thin gold rim on a black outline, like the party icon
    d = sk.dist_rect(N, N)
    sk.blend_rgb(out, sk.GOLD * 0.85, ((d >= 1) & (d < 2)).astype(np.float32))
    sk.blend_rgb(out, sk.GOLD_L, ((d >= 1) & (d < 2) & (yy < 2)).astype(np.float32) * 0.6)
    sk.blend_rgb(out, sk.BLACK, (d < 1).astype(np.float32) * 0.92)
    out[..., 3] = 1.0
    return out


# ============================================================== message toast icons
# Same frame, backdrop and materials as the party and catacomb icons. Shapes are drawn at 4x and thresholded, so
# every edge is hard; colour layers inside a shape are set per pixel. One emblem per icon, no text.
YY, XX = np.mgrid[0:N, 0:N].astype(np.float32)
CC = (N - 1) / 2.0
STEEL_A = hexc('#b9b2b4')
BONE = hexc('#cbbd9f')
PARCH = hexc('#d2bd93')
INK = hexc('#5a3a22')
CRIMSON = hexc('#8e1a14')


def _backdrop(seed, warm, cx=CC, cy=CC, k=0.55, rad=26.0):
    """Abyss stone with a coloured warmth round (cx, cy), as RGBA."""
    bg = sk.mat_stone(N, N, seed, tint=hexc('#141016'))
    r = np.sqrt((XX - cx) ** 2 + (YY - cy) ** 2)
    w = np.clip(1 - r / rad, 0, 1) ** 1.6
    return sk.rgba(np.clip(bg + w[..., None] * hexc(warm)[None, None, :] * k, 0, 1))


def _frame(out):
    """The thin gold rim on a black outline of every toast icon; the icon is opaque."""
    d = sk.dist_rect(N, N)
    sk.blend_rgb(out, sk.GOLD * 0.85, ((d >= 1) & (d < 2)).astype(np.float32))
    sk.blend_rgb(out, sk.GOLD_L, ((d >= 1) & (d < 2) & (YY < 2)).astype(np.float32) * 0.6)
    sk.blend_rgb(out, sk.BLACK, (d < 1).astype(np.float32) * 0.92)
    out[..., 3] = 1.0
    return out


def _mask(fn):
    """Hard 0/1 mask drawn with PIL at 4x; fn(d, P, s) where P(x, y) maps icon pixels to the canvas."""
    def draw(d, ss):
        fn(d, lambda x, y: (x * ss, y * ss), ss)
    return (sk.mask_draw(N, N, draw, ss=4) > 0.5)


def _ell(d, P, x0, y0, x1, y1, fill=255):
    d.ellipse([*P(x0, y0), *P(x1, y1)], fill=fill)


def _piece(out, m, alb, hs=1.8, spec=0.7, shin=12, shadow=0.8):
    """Emboss a mask in a material (dark outline, drop shadow) and lay it on out, hard edged."""
    img = sk.metal_from_mask(m.astype(np.float32), alb, height_scale=hs, blur=0.6, spec=spec, shin=shin,
                             outline=0.95, shadow=shadow)
    img[..., 3] = (img[..., 3] > 0.5).astype(np.float32)
    sk.over(out, img)


def _paint(out, m, col):
    out[..., :3] = np.where(m[..., None], np.broadcast_to(col, out[..., :3].shape), out[..., :3])


def _flat(col):
    return np.ones((N, N, 3), np.float32) * hexc(col)[None, None, :] if isinstance(col, str) \
        else np.ones((N, N, 3), np.float32) * col[None, None, :]


def _parch(seed, tone=1.0):
    n = sk.fbm(N, N, base=3, octaves=4, seed=seed)
    return np.clip(PARCH[None, None, :] * ((0.82 + 0.24 * n) * tone)[..., None], 0, 1)


def _wood(seed):
    return sk.mat_leather(N, N, seed, tint=hexc('#4f321d'), tone=1.15)


def _gem(out, cx, cy, r=3, col='#a8320c', light=None):
    g = sk.gem(r, hexc(col), sk.EMBER if light is None else hexc(light), glow=0.0)
    g[..., 3] = (g[..., 3] > 0.5).astype(np.float32)
    n = g.shape[0]
    sk.over(out, g, int(round(cx - n // 2)), int(round(cy - n // 2)))


def _flame(cx, by, h, w):
    """Mask of a flame: a round base at (cx, by) of half width w, rising to a tip h above it."""
    def fn(d, P, s):
        _ell(d, P, cx - w, by - w, cx + w, by + w)
        d.polygon([P(cx - w, by - 0.2), P(cx - w * 0.55, by - h * 0.55), P(cx + w * 0.1, by - h),
                   P(cx + w * 0.35, by - h * 0.62), P(cx + w, by - 0.2)], fill=255)
    return _mask(fn)


def _fire(out, cx, by, h, w):
    """Three nested flames: blood red, ember, a pale gold core."""
    for k, col in ((1.0, '#b3260c'), (0.7, '#ff7a1c'), (0.4, '#ffd27a')):
        m = _flame(cx, by + (1 - k) * w * 0.6, h * k, w * k)
        _paint(out, m, hexc(col))


# -- announcement: a sealed scroll tied with a crimson ribbon, a gold seal with an ember stone
def icon_announce():
    out = _backdrop(101, '#7a2a0c')
    x0, x1, cy, r = 8.0, 40.0, 21.0, 7.0
    body = (XX >= x0) & (XX <= x1) & (np.abs(YY - cy) <= r)
    caps = [((XX - ex) / 2.6) ** 2 + ((YY - cy) / r) ** 2 <= 1.0 for ex in (x0, x1)]
    shape = body | caps[0] | caps[1]
    # the rolled paper is a lit cylinder; the two ends show the curl
    t = np.clip((YY - cy) / r, -1, 1)
    hgt = np.sqrt(1 - t ** 2) * r * 0.9
    paper = sk.shade(hgt, _parch(102), amb=0.45, diff=0.9, spec=0.15, shin=10, strength=1.0)
    sh = np.zeros((N, N), bool)
    sh[2:, 2:] = shape[:-2, :-2]
    sk.blend_rgb(out, sk.BLACK, (sh & ~shape).astype(np.float32) * 0.7)
    _paint(out, _grow(shape) & ~shape, sk.IRON_D * 0.5)
    out[..., :3] = np.where(shape[..., None], paper, out[..., :3])
    _paint(out, caps[0], PARCH * 0.62)
    _paint(out, caps[1] & ~body, PARCH * 0.5)
    curl = np.abs(((XX - x0) / 1.4) ** 2 + ((YY - cy - 0.5) / 3.6) ** 2 - 1) < 0.45
    _paint(out, curl, INK * 0.9)

    # ribbon round the roll and its two tails
    def ribbon(d, P, s):
        d.rectangle([*P(21.5, cy - r - 0.6), *P(26.5, cy + r + 0.6)], fill=255)
        d.polygon([P(22, 28), P(25, 28), P(20.5, 41), P(18.5, 39.5), P(17, 42)], fill=255)
        d.polygon([P(23, 28), P(26, 28), P(31, 42), P(29.5, 39.5), P(27.5, 41)], fill=255)
    rb = _mask(ribbon)
    alb = _flat(CRIMSON) * (0.9 + 0.2 * sk.fbm(N, N, base=6, octaves=3, seed=103))[..., None]
    _piece(out, rb, alb, hs=1.4, spec=0.4, shin=10)
    # the seal: a gold disc with a raised ring and an ember stone
    seal = _mask(lambda d, P, s: _ell(d, P, 17.5, 22.5, 30.5, 35.5))
    _piece(out, seal, sk.mat_gold(N, N, 104, tone=1.05), hs=2.2, spec=0.9, shin=10)
    rr = np.sqrt((XX - 24) ** 2 + (YY - 29) ** 2)
    ring = (np.abs(rr - 4.6) < 0.55)
    _paint(out, ring & seal, sk.GOLD_D)
    _paint(out, (np.abs(rr - 5.4) < 0.5) & seal & (YY < 29) & (XX < 26), sk.GOLD_H)
    _gem(out, 24, 29, r=2)
    return _frame(out)


# -- task: a parchment pinned with an iron nail, a few ruled lines and an ember-green check mark
def icon_task():
    out = _backdrop(111, '#6a4a14', k=0.5)
    sheet = _mask(lambda d, P, s: d.polygon([P(11, 8), P(37, 6.5), P(38.5, 33), P(32.5, 41.5), P(10, 42)],
                                            fill=255))
    _piece(out, sheet, _parch(112), hs=1.2, spec=0.15, shin=10)
    # the folded corner at the bottom right
    fold = _mask(lambda d, P, s: d.polygon([P(38.5, 33), P(32.5, 41.5), P(33.5, 34.5)], fill=255))
    _paint(out, fold, PARCH * 0.62)
    _paint(out, _grow(fold) & ~fold & sheet & (XX > 31) & (YY > 31), INK * 0.8)
    # ruled lines (no writing)
    for i, ly in enumerate((14, 18, 22)):
        ln = _mask(lambda d, P, s, ly=ly, i=i: d.line([P(15, ly + 0.2), P(33 - i * 3, ly - 0.6)], fill=255,
                                                      width=max(1, int(1.1 * s))))
        _paint(out, ln & sheet, INK * 1.1)
    # the check mark
    chk = _mask(lambda d, P, s: d.line([P(15, 27), P(21.5, 34.5), P(34.5, 17.5)], fill=255,
                                       width=int(4.2 * s), joint='curve'))
    _piece(out, chk, _flat('#6f9e3a'), hs=1.8, spec=0.6, shin=12, shadow=0.7)
    _paint(out, _mask(lambda d, P, s: d.line([P(15.5, 26.2), P(21.5, 33), P(33.6, 17.2)], fill=255,
                                             width=max(1, int(1.0 * s)))) & chk, hexc('#b6e07a'))
    # the nail
    rv = sk.rivet(2.6, tone=1.2)
    rv[..., 3] = (rv[..., 3] > 0.5).astype(np.float32)
    sk.over(out, rv, 24 - rv.shape[0] // 2, 9 - rv.shape[0] // 2)
    return _frame(out)


# -- season pass: a gold medallion with an ember stone in a laurel wreath, crimson ribbon tails
def icon_season():
    out = _backdrop(121, '#a4420e', cy=22, k=0.6)
    cx, cy = CC, 21.0

    def tails(d, P, s):
        d.polygon([P(20, 30), P(24, 31), P(17, 43), P(15.5, 39.5), P(12.5, 41)], fill=255)
        d.polygon([P(24, 31), P(28, 30), P(35.5, 41), P(32.5, 39.5), P(31, 43)], fill=255)
    _piece(out, _mask(tails), _flat(CRIMSON), hs=1.4, spec=0.4)

    def laurel(d, P, s):
        R = 15.5
        for side in (-1, 1):
            # phi: 0 at the bottom of the wreath, rising up this side
            stem = [P(cx + side * R * math.sin(math.radians(f)), cy + R * math.cos(math.radians(f)))
                    for f in range(18, 122, 6)]
            d.line(stem, fill=255, width=max(1, int(1.2 * s)))
            for i in range(5):
                f = math.radians(30 + i * 22)
                lx, ly = cx + side * R * math.sin(f), cy + R * math.cos(f)
                tx, ty = side * math.cos(f), -math.sin(f)
                ox, oy = side * math.sin(f), math.cos(f)
                for o in (1, -1):        # a leaf each side of the stem, leaning up the wreath
                    mx, my = lx + ox * o * 1.9 + tx * 1.2, ly + oy * o * 1.9 + ty * 1.2
                    L, W = 3.4, 2.0
                    ax, ay = tx + ox * o * 0.45, ty + oy * o * 0.45
                    al = math.hypot(ax, ay)
                    ax, ay = ax / al, ay / al
                    nx, ny = -ay, ax
                    d.polygon([P(mx - ax * L, my - ay * L), P(mx - ax * L * 0.3 + nx * W, my - ay * L * 0.3 + ny * W),
                               P(mx + ax * L, my + ay * L), P(mx - ax * L * 0.3 - nx * W, my - ay * L * 0.3 - ny * W)],
                              fill=255)
    _piece(out, _mask(laurel), sk.mat_gold(N, N, 122, tone=0.95), hs=1.6, spec=0.7)
    med = _mask(lambda d, P, s: _ell(d, P, cx - 10.5, cy - 10.5, cx + 10.5, cy + 10.5))
    _piece(out, med, sk.mat_gold(N, N, 123, tone=1.08), hs=2.6, spec=0.9, shin=10)
    rr = np.sqrt((XX - cx) ** 2 + (YY - cy) ** 2)
    face = rr <= 6.8
    _paint(out, face, hexc('#2a1a14'))
    _paint(out, (np.abs(rr - 7.4) < 0.55), sk.GOLD_D)
    _paint(out, (np.abs(rr - 8.6) < 0.5) & (YY < cy) & (XX < cx + 2), sk.GOLD_H)
    _gem(out, cx, cy, r=4)
    return _frame(out)


# -- new player: an iron lantern with an ember flame
def icon_newplayer():
    out = _backdrop(131, '#b0520f', cy=26, k=0.7, rad=22)
    iron = sk.mat_iron(N, N, 132, tone=1.25, tint=sk.STEEL * 0.8)

    def handle(d, P, s):
        d.ellipse([*P(18.5, 3.5), *P(29.5, 13.5)], outline=255, width=int(2.0 * s))
    hm = _mask(handle) & (YY < 10)
    _piece(out, hm, iron, hs=1.4)
    # glass and its light
    glass = (XX >= 16) & (XX <= 31) & (YY >= 15) & (YY <= 35)
    gd = np.sqrt(((XX - 23.5) / 1.1) ** 2 + (YY - 29) ** 2)
    light = np.clip(1 - gd / 13.0, 0, 1) ** 1.3
    gl = np.clip(hexc('#2a0e06')[None, None, :] + light[..., None] * hexc('#ff7a1c')[None, None, :] * 0.85, 0, 1)
    out[..., :3] = np.where(glass[..., None], gl, out[..., :3])
    _fire(out, 23.5, 30.5, 13, 4.2)

    def frame_(d, P, s):
        d.polygon([P(17, 12), P(30, 12), P(33, 15.5), P(14, 15.5)], fill=255)      # cap
        d.rectangle([*P(19, 9.5), *P(28, 12)], fill=255)
        d.rectangle([*P(14, 35), *P(33, 38)], fill=255)                             # base
        d.polygon([P(16, 38), P(31, 38), P(29.5, 40.5), P(17.5, 40.5)], fill=255)
        for bx in (14, 31.2):                                                        # corner posts
            d.rectangle([*P(bx, 15), *P(bx + 2.8, 35.5)], fill=255)
        d.rectangle([*P(14, 24.5), *P(33, 25.8)], fill=0)
    fm = _mask(frame_)
    bar = (np.abs(YY - 25) <= 0.6) & (XX >= 16) & (XX <= 31)
    _piece(out, fm, iron, hs=1.8, spec=0.8, shin=14)
    _paint(out, bar, sk.IRON_D * 0.8)
    _paint(out, (np.abs(YY - 15) < 0.5) & (XX >= 17) & (XX <= 30), sk.GOLD)
    _paint(out, (np.abs(YY - 35) < 0.5) & (XX >= 15) & (XX <= 32), sk.GOLD)
    return _frame(out)


# -- ascension: a rising flame between two gold wings
def icon_ascension():
    out = _backdrop(141, '#a4420e', cy=20, k=0.65)

    def wings(d, P, s):
        for side in (-1, 1):
            bx, by = CC + side * 3.5, 31.0
            for i, (ang, ln, wd) in enumerate(((150, 17, 2.6), (135, 18, 2.6), (118, 17, 2.6), (100, 13, 2.4))):
                a = math.radians(ang)
                dx, dy = math.cos(a) * -side, -math.sin(a)
                nx, ny = -dy, dx
                x0, y0 = bx + side * i * 0.4, by - i * 1.6
                x1, y1 = x0 + dx * ln, y0 + dy * ln
                d.polygon([P(x0 + nx * wd, y0 + ny * wd), P(x1 + nx * wd * 0.5, y1 + ny * wd * 0.5),
                           P(x1 + dx * 2.2, y1 + dy * 2.2), P(x1 - nx * wd * 0.5, y1 - ny * wd * 0.5),
                           P(x0 - nx * wd, y0 - ny * wd)], fill=255)
    wm = _mask(wings)
    _piece(out, wm, sk.mat_gold(N, N, 142, tone=1.08), hs=1.6, spec=0.8)
    # feather joints
    for side in (-1, 1):
        for i, ang in enumerate((142, 126, 109)):
            a = math.radians(ang)
            dx, dy = math.cos(a) * -side, -math.sin(a)
            x0, y0 = CC + side * 3.5 + side * i * 0.4, 31.0 - i * 1.6 - 0.8
            ln = _mask(lambda d, P, s, x0=x0, y0=y0, dx=dx, dy=dy: d.line(
                [P(x0 + dx * 4, y0 + dy * 4), P(x0 + dx * 15, y0 + dy * 15)], fill=255, width=max(1, int(0.9 * s))))
            _paint(out, ln & wm, sk.GOLD_D)
    # the flame, rising from an ember on a gold base
    fl = _flame(CC, 30, 25, 6.5)
    ol = _grow(fl) & ~fl
    _paint(out, ol, hexc('#1a0604'))
    _fire(out, CC, 30, 25, 6.5)
    base = _mask(lambda d, P, s: d.polygon([P(17, 36), P(31, 36), P(28.5, 41), P(19.5, 41)], fill=255))
    _piece(out, base, sk.mat_iron(N, N, 143, tone=1.2, tint=sk.STEEL * 0.8), hs=1.6)
    _paint(out, (np.abs(YY - 36) < 0.5) & (XX >= 18) & (XX <= 30), sk.GOLD)
    return _frame(out)


# -- market: gold balance scales on an iron post
def icon_market():
    out = _backdrop(151, '#7a4a0c', k=0.5)
    gold = sk.mat_gold(N, N, 152, tone=1.08)

    def chains(d, P, s):
        for px in (11.0, 37.0):
            d.line([P(px, 13), P(px - 6.5, 28)], fill=255, width=max(1, int(1.1 * s)))
            d.line([P(px, 13), P(px + 6.5, 28)], fill=255, width=max(1, int(1.1 * s)))
    cm = _mask(chains)
    _paint(out, cm, hexc('#8a7f78'))

    def post(d, P, s):
        d.rectangle([*P(22.6, 10), *P(25.4, 37)], fill=255)
        d.polygon([P(17, 40.5), P(31, 40.5), P(28, 36.5), P(20, 36.5)], fill=255)
    _piece(out, _mask(post), sk.mat_iron(N, N, 153, tone=1.25, tint=sk.STEEL * 0.8), hs=1.6)

    def beam(d, P, s):
        d.polygon([P(9, 11.6), P(39, 11.6), P(39, 14.2), P(9, 14.2)], fill=255)
        _ell(d, P, 21, 5.5, 27, 11.5)
        for px in (11.0, 37.0):
            _ell(d, P, px - 2, 11, px + 2, 15)

    def pans(d, P, s):
        for px in (11.0, 37.0):
            d.chord([*P(px - 8, 21), *P(px + 8, 34)], 0, 180, fill=255)
    _piece(out, _mask(beam), gold, hs=1.8, spec=0.9, shin=10)
    pm = _mask(pans)
    _piece(out, pm, gold, hs=2.2, spec=0.9, shin=10)
    _paint(out, pm & (np.abs(YY - 27.6) < 0.55), sk.GOLD_H)
    _gem(out, 24, 8.5, r=1.5)
    return _frame(out)


# -- invasion: two crossed war axes over a blood-red glow
def icon_invasion():
    out = _backdrop(161, '#8a160c', k=0.7)
    steel = _flat(STEEL_A)

    def axe(flip, part):
        def fn(d, P0, s):
            def P(x, y):
                return P0(N - 1 - x if flip else x, y)
            hx0, hy0, hx1, hy1 = 11.0, 41.0, 33.0, 8.0
            L = math.hypot(hx1 - hx0, hy1 - hy0)
            ux, uy = (hx1 - hx0) / L, (hy1 - hy0) / L
            nx, ny = -uy, ux          # outward: right and down
            if part == 'haft':
                w = 1.6
                d.polygon([P(hx0 + nx * w, hy0 + ny * w), P(hx1 + nx * w + ux, hy1 + ny * w + uy),
                           P(hx1 - nx * w + ux, hy1 - ny * w + uy), P(hx0 - nx * w, hy0 - ny * w)], fill=255)
            else:
                def Q(a, b):            # a along the haft from the top, b outward
                    return P(hx1 - ux * a + nx * b, hy1 - uy * a + ny * b)
                pts = [Q(2.5, 1.0), Q(-0.5, 4.0), Q(-4.5, 8.0)]
                for k in range(11):       # the curved edge
                    t = k / 10.0
                    pts.append(Q(-4.5 + t * 16.0, 8.0 + 3.4 * math.sin(math.pi * t)))
                pts += [Q(9.0, 4.0), Q(6.0, 1.0), Q(5.6, -1.6), Q(2.9, -1.6)]
                pts += [Q(3.4, -4.6), Q(4.6, -1.6)]       # back spike
                d.polygon(pts, fill=255)
        return _mask(fn)
    for flip in (False, True):
        _piece(out, axe(flip, 'haft'), _wood(162), hs=1.4, spec=0.3)
    for flip in (False, True):
        hm = axe(flip, 'head')
        _piece(out, hm, steel, hs=1.8, spec=1.0, shin=16)
        _paint(out, hm & ~_shrink(hm, 1) & _far_side(flip), hexc('#e8e2e0'))
    _gem(out, CC + 0.5, 25.5, r=2, col='#8e1a14', light='#ff5a2a')
    return _frame(out)


def _shrink(m, n=1):
    for _ in range(n):
        m = ~_grow(~m)
    return m


def _far_side(flip):
    """Pixels on the outer (edge) side of an axe head."""
    return (XX + YY > 46) if not flip else ((N - 1 - XX) + YY > 46)


# -- bounty: a wanted poster with a hooded head, pinned by a dagger
def icon_bounty():
    out = _backdrop(171, '#8a160c', k=0.55)
    sheet = _mask(lambda d, P, s: d.polygon([P(8, 11), P(31, 9), P(33, 41), P(9.5, 42)], fill=255))
    _piece(out, sheet, _parch(172, tone=0.95), hs=1.2, spec=0.15)

    def head(d, P, s):
        _ell(d, P, 15.5, 16, 25.5, 27)
        d.polygon([P(11.5, 37), P(14, 29), P(20.5, 26), P(27, 29), P(29.5, 37)], fill=255)
    _paint(out, _mask(head) & sheet, hexc('#2a1c14'))
    _paint(out, _mask(lambda d, P, s: _ell(d, P, 17.4, 20.0, 19.4, 21.6)), hexc('#c2410c'))
    _paint(out, _mask(lambda d, P, s: _ell(d, P, 21.6, 20.0, 23.6, 21.6)), hexc('#c2410c'))
    _paint(out, (np.abs(YY - 13.5) < 0.6) & (XX >= 12) & (XX <= 28) & sheet, INK)
    _paint(out, (np.abs(YY - 39) < 0.6) & (XX >= 13) & (XX <= 29) & sheet, INK)

    # the dagger, point in the poster's top right corner
    def blade(d, P, s):
        d.polygon([P(24.5, 20.5), P(33.7, 9.9), P(36.1, 12.3), P(26.1, 22.1)], fill=255)

    def hilt(d, P, s):
        d.polygon([P(31.7, 7.1), P(32.9, 5.9), P(39.1, 12.1), P(37.9, 13.3)], fill=255)     # guard
        d.line([P(36.5, 8.5), P(40.5, 4.5)], fill=255, width=int(2.4 * s))
        _ell(d, P, 39.5, 3.3, 42.5, 6.3)
    bm = _mask(blade)
    _piece(out, bm, _flat(STEEL_A), hs=1.6, spec=1.0, shin=16)
    _paint(out, bm & (np.abs((XX - 25.3) + (YY - 21.3)) < 0.8), hexc('#e8e2e0'))
    _piece(out, _mask(hilt), sk.mat_gold(N, N, 173, tone=1.05), hs=1.6, spec=0.9)
    cut = _mask(lambda d, P, s: d.polygon([P(22.9, 21.7), P(25.9, 18.7), P(26.7, 23.7)], fill=255))
    _paint(out, cut & sheet, hexc('#5a0c08'))
    return _frame(out)


# -- bestiary: a leather tome torn by three claw marks
def icon_bestiary():
    out = _backdrop(181, '#6a2a0c', k=0.55)
    pages = _mask(lambda d, P, s: d.polygon([P(14, 9), P(39, 9), P(39, 41), P(14, 41)], fill=255))
    _piece(out, pages, _parch(182, tone=0.9), hs=1.0, spec=0.1)
    for px in (37.0, 38.2):
        _paint(out, (np.abs(XX - px) < 0.5) & (YY > 10) & (YY < 40), INK * 1.2)
    cover = _mask(lambda d, P, s: d.polygon([P(9, 7), P(36, 7), P(36, 41), P(9, 41)], fill=255))
    lea = sk.mat_leather(N, N, 183, tint=hexc('#4a1d16'), tone=1.25)
    _piece(out, cover, lea, hs=1.6, spec=0.3)
    spine = cover & (XX <= 12)
    out[..., :3] = np.where(spine[..., None], out[..., :3] * 0.6, out[..., :3])
    _paint(out, cover & (np.abs(XX - 12.5) < 0.5), sk.GOLD_D)
    for y in (12.0, 36.0):
        _paint(out, spine & (np.abs(YY - y) < 0.8), sk.GOLD)
    # iron corners
    corners = _mask(lambda d, P, s: [d.polygon(p, fill=255) for p in (
        [P(30, 7), P(36, 7), P(36, 13)], [P(30, 41), P(36, 41), P(36, 35)])])
    _piece(out, corners, sk.mat_iron(N, N, 184, tone=1.3, tint=sk.STEEL * 0.8), hs=1.2, shadow=0)

    # three claw gashes, black inside with an ember rim
    def claws(d, P, s):
        for i in range(3):
            ox = i * 5.2
            x0, y0, x1, y1 = 23 + ox, 10.5, 12 + ox, 37.5
            mx, my = (x0 + x1) / 2 + 2.0, (y0 + y1) / 2
            d.polygon([P(x0, y0), P(mx + 2.4, my), P(x1, y1), P(mx - 1.8, my)], fill=255)
    cl = _mask(claws) & cover
    _paint(out, _grow(cl) & cover & ~cl, hexc('#d8501a'))
    _paint(out, cl, hexc('#0a0406'))
    _paint(out, cl & ~_shrink(cl, 1), hexc('#5a0c08'))
    return _frame(out)


# -- journey: a compass with a gold ring and an ember north needle
def icon_journey():
    out = _backdrop(191, '#6a4a14', k=0.5)
    ringm = _mask(lambda d, P, s: _ell(d, P, CC - 18, CC - 18, CC + 18, CC + 18))
    _piece(out, ringm, sk.mat_gold(N, N, 192, tone=1.05), hs=2.4, spec=0.9, shin=10)
    rr = np.sqrt((XX - CC) ** 2 + (YY - CC) ** 2)
    face = rr <= 14.6
    fc = sk.mat_iron(N, N, 193, tone=0.9, tint=hexc('#2a2024'))
    out[..., :3] = np.where(face[..., None], fc, out[..., :3])
    _paint(out, np.abs(rr - 15.2) < 0.6, sk.GOLD_D)
    ang = np.arctan2(YY - CC, XX - CC)
    for k in range(8):
        a = k * math.pi / 4
        tick = (np.abs(np.angle(np.exp(1j * (ang - a)))) * rr < 0.7) & (rr > 12.2) & (rr < 14.4)
        _paint(out, tick, sk.GOLD_L if k % 2 == 0 else sk.GOLD * 0.8)

    def star(d, P, s, axis):
        if axis == 'ns':
            d.polygon([P(CC, CC - 13), P(CC + 3, CC), P(CC, CC + 13), P(CC - 3, CC)], fill=255)
        else:
            d.polygon([P(CC - 10.5, CC), P(CC, CC - 2.4), P(CC + 10.5, CC), P(CC, CC + 2.4)], fill=255)
    ew = _mask(lambda d, P, s: star(d, P, s, 'ew'))
    _piece(out, ew, _flat(hexc('#8a8286')), hs=1.4, spec=0.8, shadow=0.6)
    ns = _mask(lambda d, P, s: star(d, P, s, 'ns'))
    alb = np.where((YY < CC)[..., None], _flat('#d2420e'), _flat(STEEL_A))
    _piece(out, ns, alb, hs=1.6, spec=0.9, shadow=0.6)
    _paint(out, ns & (XX < CC) & (YY < CC), hexc('#ff8a3a'))
    _paint(out, ns & (XX < CC) & (YY > CC), hexc('#d8d2d4'))
    _gem(out, CC, CC, r=1.5)
    return _frame(out)


# -- boss points: a crowned skull with ember eyes
def icon_bosspoint():
    out = _backdrop(201, '#8a2a0c', cy=28, k=0.6)
    skull = _mask(lambda d, P, s: (_ell(d, P, 13, 15, 35, 36), d.rectangle([*P(17.5, 30), *P(30.5, 42)], fill=255)))
    _piece(out, skull, _flat(BONE), hs=2.2, spec=0.35, shin=10)
    # cheek notches beside the jaw
    for sx in (-1, 1):
        notch = _mask(lambda d, P, s, sx=sx: _ell(d, P, CC + sx * 8 - 2.5, 33, CC + sx * 8 + 2.5, 38))
        _paint(out, notch & skull & (np.abs(XX - CC) > 6.2), hexc('#141016'))
    for sx in (-1, 1):
        ex = CC + sx * 5.2
        eye = _mask(lambda d, P, s, ex=ex, sx=sx: d.polygon(
            [P(ex - sx * 3.6, 23.2), P(ex + sx * 3.4, 25.2), P(ex + sx * 3.0, 30.2), P(ex - sx * 3.4, 30.2)], fill=255))
        _paint(out, eye, hexc('#1a0604'))
        pu = (np.abs(XX - (ex - sx * 0.3) + 0.5 * (sx < 0)) <= 1.0) & (YY >= 26.5) & (YY <= 28.5)
        _paint(out, pu & eye, sk.EMBER)
        _paint(out, pu & eye & (YY < 27.5), hexc('#ffd27a'))
    nose = _mask(lambda d, P, s: d.polygon([P(CC, 30.5), P(CC + 1.8, 34), P(CC - 1.8, 34)], fill=255))
    _paint(out, nose, hexc('#2a1f1a'))
    teeth = (YY >= 37) & (YY <= 40) & (np.abs(XX - CC) <= 5.6) & ((np.floor(XX) % 3) == 0)
    _paint(out, teeth & skull, hexc('#3a2c24'))
    _paint(out, (np.abs(YY - 38.5) < 0.5) & (np.abs(XX - CC) <= 5.6), hexc('#3a2c24'))

    def crown(d, P, s):
        d.polygon([P(12.5, 19.5), P(12, 6.5), P(17.5, 12), P(CC, 3.5), P(29.5, 12), P(35, 6.5), P(34.5, 19.5)],
                  fill=255)
    cm = _mask(crown)
    _piece(out, cm, sk.mat_gold(N, N, 202, tone=1.08), hs=2.0, spec=0.9, shin=10)
    _paint(out, cm & (np.abs(YY - 16.5) < 0.5), sk.GOLD_D)
    _gem(out, CC, 15.5, r=1.5)
    for px in (12.5, 34.5):
        _paint(out, (np.abs(XX - px) <= 1) & (np.abs(YY - 7) <= 1) & cm, sk.EMBER)
    return _frame(out)


# -- Chaos Pact: a gold-capped hourglass, ember sand running down, an ember stone on the top cap (the Pact is running out)
def icon_pact():
    out = _backdrop(211, '#8a3a0c', k=0.55)

    def glass(d, P, s):
        # two cones that meet at a narrow neck
        d.polygon([P(15.5, 11.5), P(32.5, 11.5), P(25.2, 23.2), P(25.2, 24.8), P(32.5, 36.5), P(15.5, 36.5), P(22.8, 24.8), P(22.8, 23.2)],
                  fill=255)
    gm = _mask(glass)
    glassc = np.clip(hexc('#9db4b8')[None, None, :] * (0.55 + 0.45 * np.clip((XX - 14) / 20.0, 0, 1))[..., None], 0, 1)
    _piece(out, gm, glassc, hs=1.2, spec=0.9, shin=14, shadow=0.5)
    # the sand: the top cone is nearly empty, the bottom cone holds most of it, a thread falls through the neck
    top = gm & (YY >= 17.5) & (YY <= 22.8)
    bottom = gm & (YY >= 31.0)
    thread = (np.abs(XX - CC) < 0.6) & (YY >= 22.5) & (YY <= 30.5)
    for m, col in ((top, '#ff7a1c'), (bottom, '#ff7a1c'), (thread, '#ffb04a')):
        _paint(out, m, hexc(col))
    _paint(out, bottom & (YY <= 31.9), hexc('#ffd27a'))
    _paint(out, top & (YY <= 18.4), hexc('#ffd27a'))
    for cy in (9.5, 38.5):
        cap = _mask(lambda d, P, s, cy=cy: d.rectangle([*P(12.5, cy - 2.2), *P(35.5, cy + 2.2)], fill=255))
        _piece(out, cap, sk.mat_gold(N, N, 212 + int(cy), tone=1.06), hs=2.0, spec=0.9, shin=10)
    for px in (14.5, 33.5):
        post = _mask(lambda d, P, s, px=px: d.rectangle([*P(px - 0.9, 11.7), *P(px + 0.9, 36.3)], fill=255))
        _piece(out, post, sk.mat_gold(N, N, 214, tone=0.95), hs=1.4, spec=0.8, shadow=0.5)
    _gem(out, CC, 9.5, r=1.5)
    return _frame(out)


# file name -> drawing, in the order of the contact sheet
MESSAGE_ICONS = (
    ('announce.png', icon_announce),
    ('task.png', icon_task),
    ('season_pass.png', icon_season),
    ('new_player.png', icon_newplayer),
    ('ascension.png', icon_ascension),
    ('market.png', icon_market),
    ('invasion.png', icon_invasion),
    ('bounty.png', icon_bounty),
    ('bestiary.png', icon_bestiary),
    ('journey.png', icon_journey),
    ('boss_point.png', icon_bosspoint),
    ('pact.png', icon_pact),
)


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


def check():
    """Draw every file into a temporary folder and compare with the shipped ones (pixels, not bytes)."""
    import tempfile
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        stdout, sys.stdout = sys.stdout, open(os.devnull, 'w')
        try:
            main(['gen_toast_art.py', tmp])
        finally:
            sys.stdout.close()
            sys.stdout = stdout
        for name in sorted(os.listdir(tmp)):
            shipped = os.path.join(DEFAULT_OUT, name)
            if not os.path.exists(shipped):
                bad.append(name + ': missing')
                continue
            a, b = Image.open(os.path.join(tmp, name)).convert('RGBA'), Image.open(shipped).convert('RGBA')
            if a.size != b.size or a.tobytes() != b.tobytes():
                bad.append(name + ': differs')
    for line in bad:
        print('gen_toast_art --check:', line)
    if bad:
        print('run: python3 -I client/tools/gen_toast_art.py')
        return 1
    print('toast art: up to date')
    return 0


def main(argv):
    args = argv[1:]
    if '--check' in args:
        return check()
    sheet_path = None
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet_path = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else DEFAULT_OUT
    imgs = [write(button_sheet('accept'), os.path.join(out, 'accept.png')),
            write(button_sheet('decline'), os.path.join(out, 'decline.png')),
            write(icon_party(), os.path.join(out, 'party_invite.png')),
            write(icon_catacomb(), os.path.join(out, 'catacomb_invite.png'))]
    imgs += [write(fn(), os.path.join(out, name)) for name, fn in MESSAGE_ICONS]
    if sheet_path:
        sheet(imgs, sheet_path)


if __name__ == '__main__':
    sys.exit(main(sys.argv) or 0)
