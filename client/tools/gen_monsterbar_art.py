#!/usr/bin/env python3
"""Art of game_monsterbar (the bar of the monster you attack), one look per style.

usage: python3 -I client/tools/gen_monsterbar_art.py [OUTDIR] [--sheet SHEET.png]
       default OUTDIR: client/overlay/data/images/chaos/monsterbar
       --sheet also writes a contact sheet of every style at 3x (not shipped)

Styles (game_monsterbar/monsterbarstyle.lua picks one from the server's tier and role):
  normal     plain blackened iron, steel hairline, rivets on the end caps
  magic      sapphire gems in the caps, blue-steel hairline
  rare       gold filigree curls and topaz gems, gold hairline
  legendary  ember crowns of iron flames over ember gems, ember hairline
  boss       crimson: bone horns rising from skull caps, blood hairline
  guardian   a rift guardian: the boss look with violet rift shards behind the horns and violet eyes
  omen       an Omen guardian: obsidian band, pale gold crescents around a violet omen eye, violet hairline

Files (sizes are the layout of monsterbar.otui):
  frame_<style>.png  420x58: the band, the socket and the end caps; the socket window x 38..381, y 30..45 is
                     transparent (the fill widgets under it show through)
  fill_<style>.png   344x16: the health fill (blood red for every style, a sheen in the style's colour)
  trail.png          344x16: the recent damage, drawn under the fill and shrinking after it
  plaque_<style>.png 48x22 9-slice (border 10 left / right, 6 top / bottom): the name and level plates
  mods/<key>.png     26x26: modifier chips (keys of ChaosMods in server monster_tiers.lua, plus `unknown`)

House rules this follows (client_chaos_theme, gen_skin.py, gen_buff_icons.py): blackened iron lit from the top left,
thin metal hairlines, cabochon gems in gold bezels, blood red health; tier colours as the server names them.
Materials come from gen_skin.py (iron, gold, gems, rivets, the HUD bar fill) and the chips from gen_buff_icons.py
(its motifs, ramps, plate and the blood-red debuff frame: a modifier is a threat to the player). Every alpha edge is
hardened to 0 or 255 and there is no blur or glow halo, so the art stays crisp at 1x. Our own art; deterministic
(fixed seeds). Needs Pillow and numpy.
"""
import importlib.util
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, '..', 'overlay', 'data', 'images', 'chaos', 'monsterbar'))


def _load(name):
    # by path: python -I leaves the script's folder off sys.path
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sk = _load('gen_skin')
bi = _load('gen_buff_icons')
hexc = sk.hexc

# ---------------------------------------------------------------- layout (monsterbar.otui)
W, H = 420, 58
SX, SY, SW, SH = 38, 30, 344, 16          # socket window (the fill)
BAND = (28, 22, 392, 53)                  # the iron band behind the socket: x0, y0, x1, y1 (exclusive)
CAP_L, CAP_R, CAP_Y = 20, W - 21, 37      # end cap centres
PW, PH, PB = 48, 22, 10                   # plaque size and side border

BONE = hexc('#d8ccb0')
BONE_D = hexc('#7a6a52')
VIOLET = hexc('#7a3cc8')
VIOLET_L = hexc('#c79bff')
OBSIDIAN = hexc('#17121e')
SAPPHIRE = hexc('#1f4fb8')
SAPPHIRE_L = hexc('#7fb0ff')
TOPAZ = hexc('#c88a18')
TOPAZ_L = hexc('#ffe08a')
EMBER_D = hexc('#a8320c')

# style: hairline, gem (colour, light) or None, band tint, sheen of the fill, fill base
STYLES = {
    'normal':    dict(line=hexc('#7d7176'), gem=None, tint=sk.IRON, sheen=hexc('#e07060'), base=sk.BLOOD),
    'magic':     dict(line=hexc('#4a86f0'), gem=(SAPPHIRE, SAPPHIRE_L), tint=sk.IRON, sheen=hexc('#9cc4ff'),
                      base=sk.BLOOD),
    'rare':      dict(line=hexc('#e8b84a'), gem=(TOPAZ, TOPAZ_L), tint=sk.IRON, sheen=hexc('#ffe08a'), base=sk.BLOOD),
    'legendary': dict(line=hexc('#ff8a2a'), gem=(EMBER_D, sk.EMBER), tint=sk.IRON, sheen=hexc('#ffb060'),
                      base=sk.BLOOD),
    'boss':      dict(line=hexc('#e03a1e'), gem=(sk.BLOOD, sk.BLOOD_L), tint=hexc('#2e2226'), sheen=hexc('#ff6a50'),
                      base=hexc('#8a0c0a')),
    'guardian':  dict(line=hexc('#e03a1e'), gem=(VIOLET, VIOLET_L), tint=hexc('#2e2226'), sheen=hexc('#d0a0ff'),
                      base=hexc('#8a0c0a')),
    'omen':      dict(line=hexc('#a070e0'), gem=(VIOLET, VIOLET_L), tint=OBSIDIAN, sheen=hexc('#d8b8ff'),
                      base=hexc('#860e1c')),
}
ORDER = ['normal', 'magic', 'rare', 'legendary', 'boss', 'guardian', 'omen']


# ---------------------------------------------------------------- helpers
def harden(a, cut=0.5):
    """crisp pixels: alpha to 0 or 1 (colour kept)"""
    a = a.copy()
    a[..., 3] = (a[..., 3] >= cut).astype(np.float32)
    return a


def mask(fn):
    return sk.mask_draw(W, H, fn)


def piece(m, albedo, **kw):
    """an embossed piece from a coverage mask, without the soft drop shadow"""
    kw.setdefault('shadow', 0)
    return sk.metal_from_mask(m, albedo, **kw)


def flat(color, h=H, w=W):
    return np.ones((h, w, 3), np.float32) * color[None, None, :]


def put(out, src, cx, cy):
    sk.over(out, src, int(round(cx - src.shape[1] / 2)), int(round(cy - src.shape[0] / 2)))


# ---------------------------------------------------------------- the band and the socket
def band(st, seed):
    x0, y0, x1, y1 = BAND
    out = np.zeros((H, W, 4), np.float32)
    bw, bh = x1 - x0, y1 - y0
    plate = sk.bevel_box(bw, bh, 3, sk.mat_iron(bh, bw, seed, tone=0.9, tint=st['tint']))
    # the style's hairline one pixel inside the black outline, a lit top edge
    d = sk.dist_rect(bh, bw)
    sk.blend_rgb(plate, st['line'], ((d >= 1) & (d < 2)).astype(np.float32) * 0.9)
    sk.over(out, plate, x0, y0)
    for x in range(x0 + 26, x1 - 20, 46):
        rv = sk.rivet(1.2, metal=sk.STEEL * 1.1)
        sk.over(out, rv, x, y0 + 2)
        sk.over(out, rv, x, y1 - 6)
    # the socket: black well, a dark bevel and the style's hairline around the window
    sx0, sy0, sx1, sy1 = SX - 3, SY - 3, SX + SW + 3, SY + SH + 3
    sock = sk.panel(sx1 - sx0, sy1 - sy0, 3, 'inset', 'abyss', seed=seed + 7, rim=st['line'] * 0.85, tone=0.5)
    sk.over(out, sock, sx0, sy0)
    out[SY:SY + SH, SX:SX + SW] = 0
    return out


# ---------------------------------------------------------------- end caps
def cap_plate(st, seed, out, dark=1.0):
    """an iron boss at each end, slightly larger than the band, with a gold or steel rim"""
    def draw(d, s):
        for cx in (CAP_L, CAP_R):
            r = 15
            d.polygon([((cx) * s, (CAP_Y - r - 2) * s), ((cx + r) * s, CAP_Y * s), (cx * s, (CAP_Y + r + 2) * s),
                       ((cx - r) * s, CAP_Y * s)], fill=255)
    m = mask(draw)
    alb = sk.mat_iron(H, W, seed, tone=1.05 * dark, tint=st['tint'])
    p = piece(m, alb, height_scale=3.0, blur=1.2, spec=0.5)
    edge = np.clip(m - sk.gauss(m, 0.8) * 1.0, 0, 1)
    sk.blend_rgb(p, st['line'], np.clip(edge * 2.2, 0, 1) * 0.9)
    sk.over(out, p)


def gems(st, out, r=5.0):
    if st['gem']:
        g = sk.gem(r, *st['gem'])
        for cx in (CAP_L, CAP_R):
            put(out, g, cx + 0.5, CAP_Y + 0.5)


def rivets(out):
    for cx in (CAP_L, CAP_R):
        put(out, sk.rivet(3.2, metal=sk.STEEL * 1.15), cx + 0.5, CAP_Y + 0.5)


def filigree(out, metal, seed):
    def draw(d, s):
        for side, cx in ((-1, CAP_L), (1, CAP_R)):
            # a scroll curling over and under the cap, toward the band
            sk.poly_stroke(d, sk.curl_points(cx - side * 2, CAP_Y - 13, 5.5, 1.2, math.pi if side < 0 else 0, 0.85,
                                             flip=side), 1.6, s)
            sk.poly_stroke(d, sk.curl_points(cx - side * 2, CAP_Y + 13, 5.5, 1.2, math.pi if side < 0 else 0, 0.85,
                                             flip=-side), 1.6, s)
            sk.poly_stroke(d, [(cx - side * 3, CAP_Y - 18), (cx + side * 10, CAP_Y - 20)], 1.3, s)
            sk.poly_stroke(d, [(cx - side * 3, CAP_Y + 18), (cx + side * 10, CAP_Y + 20)], 1.3, s)
    m = mask(draw)
    sk.over(out, piece(m, metal(H, W, seed), height_scale=1.8, blur=0.6))


def flames(out, seed):
    """a crown of hammered iron flames over each cap, ember inside"""
    heights = [(-9, 9), (-4.5, 14), (0, 19), (4.5, 14), (9, 9)]

    def draw(d, s):
        for cx in (CAP_L, CAP_R):
            for dx, h in heights:
                bx, by = cx + dx, CAP_Y - 12
                d.polygon([((bx - 3.2) * s, by * s), ((bx - 1.2) * s, (by - h * 0.6) * s), (bx * s, (by - h) * s),
                           ((bx + 2.4) * s, (by - h * 0.55) * s), ((bx + 3.2) * s, by * s)], fill=255)
    m = mask(draw)
    yy = np.arange(H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
    t = np.clip((CAP_Y - 12 - yy) / 19.0, 0, 1)[..., None]       # 0 at the base, 1 at the tip
    alb = EMBER_D[None, None, :] * (1 - t) + hexc('#ffd27a')[None, None, :] * t
    p = piece(m, alb, height_scale=2.0, blur=0.7, spec=0.6, outline=1.0)
    sk.over(out, p)


def horns(out, seed, color=BONE):
    """bone horns rising from the caps, curving outward, with darker growth rings"""
    def draw(d, s):
        for side, cx in ((-1, CAP_L), (1, CAP_R)):
            outer = sk.bezier((cx - side * 7, CAP_Y - 8), (cx - side * 9, CAP_Y - 24), (cx + side * 4, CAP_Y - 34),
                              (cx + side * 16, CAP_Y - 36))
            inner = sk.bezier((cx + side * 16, CAP_Y - 36), (cx + side * 6, CAP_Y - 28), (cx + side * 3, CAP_Y - 18),
                              (cx + side * 6, CAP_Y - 8))
            d.polygon([(x * s, y * s) for x, y in outer + inner], fill=255)
    m = mask(draw)
    yy = np.arange(H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
    rings = (np.sin((CAP_Y - yy) * 1.1) > 0.55).astype(np.float32) * 0.35
    tip = np.clip((CAP_Y - 8 - yy) / 28.0, 0, 1)
    alb = flat(color) * (1 - rings)[..., None] * (1.0 - 0.25 * (1 - tip))[..., None]
    sk.over(out, piece(m, alb, height_scale=2.4, blur=1.0, spec=0.35, shin=8, outline=1.0))


def skulls(out, eye, seed):
    """a bone skull on each cap (over the iron boss)"""
    def draw(d, s):
        for cx in (CAP_L, CAP_R):
            d.ellipse([(cx - 8) * s, (CAP_Y - 10) * s, (cx + 8) * s, (CAP_Y + 5) * s], fill=255)
            d.rounded_rectangle([(cx - 5) * s, (CAP_Y + 2) * s, (cx + 5) * s, (CAP_Y + 9) * s], radius=1.5 * s,
                                fill=255)
    m = mask(draw)
    p = piece(m, flat(BONE), height_scale=2.4, blur=1.0, spec=0.3, shin=8, outline=1.0)
    sk.over(out, p)
    hole = np.array(sk.IRON_D * 0.5)
    for cx in (CAP_L, CAP_R):
        for ex in (-4, 2):
            out[CAP_Y - 4:CAP_Y + 1, cx + ex - 1:cx + ex + 3, :3] = hole
            out[CAP_Y - 3:CAP_Y, cx + ex:cx + ex + 2, :3] = eye
            out[CAP_Y - 3, cx + ex, :3] = np.clip(eye * 1.4 + 0.2, 0, 1)
        out[CAP_Y + 2:CAP_Y + 4, cx - 1:cx + 1, :3] = hole          # the nose
        for tx in range(-4, 5, 2):                                      # the teeth
            out[CAP_Y + 5:CAP_Y + 8, cx + tx, :3] = hole


def shards(out, seed):
    """violet rift crystals behind a guardian's horns"""
    def draw(d, s):
        for side, cx in ((-1, CAP_L), (1, CAP_R)):
            for dx, h, w in ((-side * 9, 20, 3), (side * 12, 16, 3), (side * 2, 26, 3.5)):
                bx, by = cx + dx, CAP_Y - 6
                d.polygon([((bx - w) * s, by * s), (bx * s, (by - h) * s), ((bx + w) * s, by * s)], fill=255)
    m = mask(draw)
    yy = np.arange(H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
    t = np.clip((CAP_Y - 6 - yy) / 26.0, 0, 1)[..., None]
    alb = VIOLET[None, None, :] * (1 - t) + VIOLET_L[None, None, :] * t
    sk.over(out, piece(m, alb, height_scale=2.0, blur=0.5, spec=1.0, shin=24, outline=1.0))


def crescents(out, seed):
    """pale gold crescent moons (the omen) cupping each cap from below, their horns rising past it"""
    def draw(d, s):
        for cx in (CAP_L, CAP_R):
            d.ellipse([(cx - 17) * s, (CAP_Y - 21) * s, (cx + 17) * s, (CAP_Y + 20) * s], fill=255)
            d.ellipse([(cx - 13) * s, (CAP_Y - 29) * s, (cx + 13) * s, (CAP_Y + 13) * s], fill=0)
    m = mask(draw)
    yy = np.arange(H, dtype=np.float32)[:, None] * np.ones((1, W), np.float32)
    t = np.clip((CAP_Y + 20 - yy) / 40.0, 0, 1)[..., None]
    alb = hexc('#a8884a')[None, None, :] * (1 - t) + hexc('#f2e2b0')[None, None, :] * t
    sk.over(out, piece(m, alb, height_scale=2.2, blur=0.8, spec=0.8, outline=1.0))


def omen_eyes(out):
    """a violet omen eye in each cap: almond of bone, violet iris, black slit"""
    def draw(d, s):
        for cx in (CAP_L, CAP_R):
            d.polygon([((cx - 9) * s, CAP_Y * s), ((cx - 3) * s, (CAP_Y - 5) * s), ((cx + 3) * s, (CAP_Y - 5) * s),
                       ((cx + 9) * s, CAP_Y * s), ((cx + 3) * s, (CAP_Y + 5) * s), ((cx - 3) * s, (CAP_Y + 5) * s)],
                      fill=255)
    m = mask(draw)
    sk.over(out, piece(m, flat(hexc('#2a1838')), height_scale=1.6, blur=0.6, spec=0.3, outline=1.0))
    g = sk.gem(3.6, VIOLET, VIOLET_L)
    for cx in (CAP_L, CAP_R):
        put(out, g, cx + 0.5, CAP_Y + 0.5)
        out[CAP_Y - 3:CAP_Y + 4, cx, :3] = 0.03                         # the slit pupil


def frame(style):
    st = STYLES[style]
    seed = 300 + ORDER.index(style) * 17
    out = np.zeros((H, W, 4), np.float32)
    if style == 'omen':
        crescents(out, seed)
    if style in ('boss', 'guardian'):
        if style == 'guardian':
            shards(out, seed)
        horns(out, seed)
    if style == 'legendary':
        flames(out, seed)
    sk.over(out, band(st, seed))
    cap_plate(st, seed + 3, out, dark=0.8 if style == 'omen' else 1.0)
    if style == 'normal':
        rivets(out)
    elif style == 'rare':
        filigree(out, sk.gold_albedo, seed)
        gems(st, out)
    elif style in ('magic', 'legendary'):
        gems(st, out)
    elif style in ('boss', 'guardian'):
        skulls(out, st['gem'][1], seed)
    elif style == 'omen':
        omen_eyes(out)
    out = harden(out)
    out[SY:SY + SH, SX:SX + SW] = 0
    return out


# ---------------------------------------------------------------- fill, trail, plaque
def fill(style):
    st = STYLES[style]
    return harden(sk.hud_fill(SW, SH, st['base'], st['sheen'], 400 + ORDER.index(style)))


def trail():
    y = np.arange(SH, dtype=np.float32)[:, None] / (SH - 1)
    top, bottom = hexc('#f6dfa8'), hexc('#b8864a')
    col = top[None, None, :] * (1 - y[..., None]) + bottom[None, None, :] * y[..., None]
    col = np.repeat(col, SW, axis=1)
    out = sk.rgba(col)
    out[0, :, :3] = np.clip(out[0, :, :3] * 1.08, 0, 1)
    out[-1, :, :3] *= 0.6
    return out


def plaque(style):
    """name / level plate: pointed ends, iron face, the style's hairline; a flat middle that stretches cleanly"""
    st = STYLES[style]
    im = Image.new('RGBA', (PW, PH), (0, 0, 0, 0))
    p = im.load()
    face_top = tuple(int(c * 255) for c in np.clip(st['tint'] * 1.35, 0, 1))
    face_bot = tuple(int(c * 255) for c in np.clip(st['tint'] * 0.55, 0, 1))
    line = tuple(int(c * 255) for c in st['line'])
    hi = tuple(min(255, int(c * 1.25) + 30) for c in line)
    mid = (PH - 1) / 2.0

    def inside(x, y):
        cut = max(0, 6 - int(round(min(y, PH - 1 - y) * 6 / mid)))   # the chevron ends
        return cut <= x <= PW - 1 - cut

    for y in range(PH):
        for x in range(PW):
            if not inside(x, y):
                continue
            edge = not (inside(x - 1, y) and inside(x + 1, y) and inside(x, y - 1) and inside(x, y + 1))
            near = not all(inside(x + dx, y + dy) for dx in (-2, -1, 0, 1, 2) for dy in (-1, 0, 1)
                           if abs(dx) + abs(dy) <= 2)
            if edge:
                p[x, y] = (8, 6, 8, 255)
            elif near:
                p[x, y] = (hi if y < mid else line) + (255,)
            else:
                t = (y - 2) / float(PH - 5)
                c = bi.mix(face_top, face_bot, max(0.0, min(1.0, t)))
                p[x, y] = c + (238,) if 3 <= y <= PH - 4 else c + (255,)
    # a small gem stud in each end
    if st['gem']:
        g = tuple(int(c * 255) for c in st['gem'][1])
        gd = tuple(int(c * 255) for c in st['gem'][0])
        for cx in (5, PW - 6):
            for (dx, dy, c) in ((0, 0, g), (-1, 0, gd), (1, 0, gd), (0, -1, gd), (0, 1, gd)):
                p[cx + dx, int(mid) + dy] = c + (255,)
    else:
        for cx in (5, PW - 6):
            p[cx, int(mid)] = (150, 140, 146, 255)
    return im


# ---------------------------------------------------------------- modifier chips (buff-icon style, debuff frame)
A, AH, AD, B, BH, BD, KK, W_ = bi.A, bi.AH, bi.AD, bi.B, bi.BH, bi.BD, bi.KK, bi.W


def m_vampiric(c):
    c.poly([(13, 8), (17, 5), (22, 4), (24, 9), (21, 9), (19, 13), (16, 11), (13, 15), (10, 11), (7, 13), (5, 9),
            (2, 9), (4, 4), (9, 5)], A)                                  # a bat
    c.ell(10.5, 6, 15.5, 12, A)
    c.px(['h.h'], 11, 8, {'h': W_})
    bi.drop(c, 13, 14, 0.75, B)                                          # a drop of blood under it
    c.px(['h'], 12, 18, {'h': BH})


def m_stoneskin(c):
    bi.shield(c, 5, 3, 21, 23, A)                                        # a stone shield, cracked
    c.line([(9, 6), (12, 11), (10, 15), (13, 20)], AD, 1)
    c.line([(16, 7), (14, 12), (17, 15)], AD, 1)
    c.px(['h', 'h'], 7, 5, {'h': AH})


def m_explosive(c):
    bi.star(c, 13, 13, 11, 5, A, n=8, rot=-90)                           # a burst
    bi.star(c, 13, 13, 6, 3, AH, n=8, rot=-67)
    c.ell(10.5, 10.5, 15.5, 15.5, W_)


def m_juggernaut(c):
    bi.shield(c, 4, 4, 22, 24, B)                                       # a great shield and a rising arrow
    bi.m_up_arrow(c, 13, 5, 0.75, A)


def m_unknown(c):
    bi.skull(c, 6, 6)


MODS = {  # key: (motif, ramps); keys of ChaosMods (server monster_tiers.lua)
    'blazing': (bi.m_burning, 'ember'), 'chilling': (bi.m_freezing, 'frost'), 'venomous': (bi.m_poison, 'poison', 'poison'),
    'shocking': (bi.m_energy, 'energy'), 'vampiric': (m_vampiric, 'shadow', 'blood'),
    'berserker': (bi.m_rage, 'steel', 'bone', 'blood'), 'brutal': (bi.m_infight, 'steel', 'wood', 'blood'),
    'stoneskin': (m_stoneskin, 'bone'), 'reflective': (bi.m_reprisal, 'steel', 'arcane'),
    'regenerating': (bi.m_regen, 'nature'), 'swift': (bi.m_haste, 'wind', 'wood'),
    'explosive': (m_explosive, 'ember'), 'juggernaut': (m_juggernaut, 'blood', 'steel'),
    'unknown': (m_unknown, 'bone'),
}


def chip(key):
    fn, *ramps = MODS[key]
    c = bi.Canvas()
    fn(c)
    rr = [bi.R[r] for r in ramps]
    return bi.frame(bi.paint(bi.plate('debuff', rr[0]), c.grid(), rr), 'debuff')


# ---------------------------------------------------------------- output
def build():
    files = {}
    for s in ORDER:
        files['frame_%s.png' % s] = sk.to_img(frame(s))
        files['fill_%s.png' % s] = sk.to_img(fill(s))
        files['plaque_%s.png' % s] = plaque(s)
    files['trail.png'] = sk.to_img(trail())
    for k in MODS:
        files['mods/%s.png' % k] = chip(k)
    return files


def nine(im, w, h, l, t):
    """the engine's 9-slice (stretched middle) for the sheet"""
    a = np.asarray(im)
    H0, W0 = a.shape[:2]
    xs = [0, l, W0 - l, W0]
    ys = [0, t, H0 - t, H0]
    dx = [0, l, w - l, w]
    dy = [0, t, h - t, h]
    out = Image.new('RGBA', (w, h))
    for j in range(3):
        for i in range(3):
            part = im.crop((xs[i], ys[j], xs[i + 1], ys[j + 1]))
            out.paste(part.resize((dx[i + 1] - dx[i], dy[j + 1] - dy[j]), Image.NEAREST), (dx[i], dy[j]))
    return out


def sheet(files, path, scale=3):
    """every style as the bar shows it (fill at 70%, trail to 82%, three chips), at `scale` x"""
    rows = []
    mods = ['blazing', 'vampiric', 'explosive']
    for s in ORDER:
        im = Image.new('RGBA', (W, 92), (40, 34, 30, 255))
        back = Image.new('RGBA', (SW, SH), (14, 10, 12, 255))
        im.alpha_composite(back, (SX, SY + 6))
        im.alpha_composite(files['trail.png'].crop((0, 0, int(SW * 0.82), SH)), (SX, SY + 6))
        im.alpha_composite(files['fill_%s.png' % s].crop((0, 0, int(SW * 0.70), SH)), (SX, SY + 6))
        im.alpha_composite(files['frame_%s.png' % s], (0, 6))
        im.alpha_composite(nine(files['plaque_%s.png' % s], 170, PH, PB, 6), ((W - 170) // 2, 2))
        im.alpha_composite(nine(files['plaque_%s.png' % s], 50, PH, PB, 6), ((W - 170) // 2 - 52, 2))
        for i, k in enumerate(mods[:1 + ORDER.index(s) % 3]):
            im.alpha_composite(files['mods/%s.png' % k], (W // 2 - 42 + i * 28, 64))
        d = ImageDraw.Draw(im)
        d.text((8, 76), s, fill=(214, 201, 174, 255))
        rows.append(im.resize((W * scale, 92 * scale), Image.NEAREST))
    chips = Image.new('RGBA', (W * scale, 40 * scale), (40, 34, 30, 255))
    for i, k in enumerate(sorted(MODS)):
        c = files['mods/%s.png' % k].resize((26 * scale, 26 * scale), Image.NEAREST)
        chips.alpha_composite(c, (6 * scale + i * 29 * scale, 6 * scale))
    rows.append(chips)
    out = Image.new('RGBA', (W * scale, sum(r.height for r in rows)), (0, 0, 0, 255))
    y = 0
    for r in rows:
        out.alpha_composite(r, (0, y))
        y += r.height
    out.convert('RGB').save(path)


def main():
    args = sys.argv[1:]
    sheet_path = None
    if '--sheet' in args:
        i = args.index('--sheet')
        sheet_path = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else DEFAULT_OUT
    files = build()
    os.makedirs(os.path.join(out, 'mods'), exist_ok=True)
    for name, im in files.items():
        im.save(os.path.join(out, name), optimize=True)
    if sheet_path:
        sheet(files, sheet_path)
    print(len(files), 'images written to', out)


if __name__ == '__main__':
    main()
