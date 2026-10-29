#!/usr/bin/env python3
"""Art of the chest auras and the Templar foot aura (client/MANIFEST.md "Chest and Templar auras (O315)", module game_chestaura).

The looks are the ones the owner approved from preview pictures on 2026-10-29. Everything is drawn here from shapes and noise with a
fixed seed (no reference art, nothing third-party). A filmstrip is one row of square frames, left to right.

  chest/reward_sigil.png     64 px x 12   the reward chest (client 38758, one tile): gold pool, fine ring with a travelling glint,
                                          four twinkles, a dashed sigil ring
  chest/cursed_smoke.png     64 px x 12   the cursed chest (client 38642): a dark pool, violet smoke rising, a few embers (no ring)
  chest/coffer_smoke.png    128 px x 12   the Sealed Coffer on the big gold chest (client 38657, 2 x 2): golden smoke with coins of
                                          light, a gold pool (no ring); centred on the chest's 2 x 2 footprint
  foot/templar_sigil.png     64 px x 24   the Templar line's foot aura, one turn of 24 frames (6 s at 250 ms): a ring with a slow
  foot/inquisitor_sigil.png               travelling highlight and a dashed sigil, in the line's tint (holy gold, white and ember,
  foot/sentinel_sigil.png                 steel and blue); the total light is the same in every frame
  frame/templar.png          96 px       the range frame: a faint square on the floor, 3 x 3 tiles, in the line's tint (gold, warm white,
  frame/inquisitor.png                   blue); a nine-slice picture (image-border 32: the four 32 px corners stay, the edges stretch, the
  frame/sentinel.png                     middle is empty), so the client draws one widget of (2r + 1) x (2r + 1) tiles for a Templar
                                         whose aura has radius r (4, 3 and 5, more with the passive tree), no matter which r

The chest and foot pictures are 1x (64 px cover two tiles of 32 px; the client scales them with the map); the frame is 3 tiles
across with a 1 tile border. The module's loops are 12 frames (chests) and 24 frames (foot): client/overlay/modules/game_chestaura/chestaura_logic.lua
keeps the same counts and sizes (chestaura_test.lua checks the files against them).

python3 -I client/tools/gen_aura_art.py                  # write the strips into the module (overlay/modules/game_chestaura/images)
python3 -I client/tools/gen_aura_art.py --check          # the committed strips are what the generator draws (exit 1 if not); writes nothing
python3 -I client/tools/gen_aura_art.py --out DIR        # write the strips (DIR/chest, DIR/foot, DIR/frame) somewhere else
python3 -I client/tools/gen_aura_art.py --preview DIR2 --pair PAIR_DIR   # + pictures on the real sprites (needs Tibia.dat / Tibia.spr)

numpy and Pillow are needed (CI runs the check with the pinned versions of the fx venv, because float maths differs a little between
versions; the strips were made with Pillow 12.3.0 and numpy 2.5.3).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

SEED = 20261029
HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.join(os.path.dirname(HERE), 'overlay', 'modules', 'game_chestaura')
OUT = os.path.join(MODULE, 'images')

# ---------------------------------------------------------------- drawing kit (float RGBA, straight alpha)


def canvas(n):
    return np.zeros((n, n, 4), np.float32)


def over(dst, src):
    sa, da = src[..., 3:4], dst[..., 3:4]
    oa = sa + da * (1 - sa)
    dst[..., :3] = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    dst[..., 3:4] = oa


def layer(n, alpha, color):
    out = canvas(n)
    out[..., :3] = np.array(color, np.float32) / 255.0
    out[..., 3] = np.clip(alpha, 0, 1)
    return out


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return x + 0.5, y + 0.5


def pool(n, cx, cy, rx, ry, color, a, power=1.6):
    x, y = grid(n)
    r = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    return layer(n, a * np.clip(1 - r, 0, 1) ** power, color)


def ring(n, cx, cy, rx, ry, color, a, width=1.3, glow=3.0, arc=None):
    """an ellipse line with a soft edge; arc = (angle, half width, gain) brightens a travelling stretch"""
    x, y = grid(n)
    dx, dy = (x - cx) / rx, (y - cy) / ry
    d = np.abs(np.sqrt(dx ** 2 + dy ** 2) - 1.0) * (rx + ry) / 2
    al = np.clip(1.0 - d / width, 0, 1) * 0.9 + np.exp(-(d / glow) ** 2) * 0.35
    if arc is not None:
        ang, half, gain = arc
        da = np.angle(np.exp(1j * (np.arctan2(dy, dx) - ang)))
        al = al * (1 + gain * np.exp(-(da / half) ** 2))
    return layer(n, a * al, color)


def blob(n, x0, y0, rad, color, a):
    x, y = grid(n)
    return layer(n, a * np.exp(-(((x - x0) ** 2 + (y - y0) ** 2) / (rad * rad))), color)


def star(n, x0, y0, size, color, a):
    x, y = grid(n)
    dx, dy = np.abs(x - x0), np.abs(y - y0)
    core = np.exp(-((dx * dx + dy * dy) / (size * size * 0.18)))
    arms = np.exp(-(dx / (size * 0.12)) ** 2) * np.clip(1 - dy / size, 0, 1) + \
        np.exp(-(dy / (size * 0.12)) ** 2) * np.clip(1 - dx / size, 0, 1)
    return layer(n, a * np.clip(core + arms * 0.9, 0, 1), color)


def dot(n, x0, y0, color, a):
    out = blob(n, x0, y0, 1.7, color, a * 0.35)
    over(out, blob(n, x0, y0, 0.8, (255, 246, 214), a))
    return out


def dashes(n, cx, cy, rx, ry, count, rot, frac, color, a, width=1.5):
    x, y = grid(n)
    dx, dy = (x - cx) / rx, (y - cy) / ry
    d = np.abs(np.sqrt(dx ** 2 + dy ** 2) - 1.0) * (rx + ry) / 2
    seg = 2 * math.pi / count
    on = (((np.arctan2(dy, dx) - rot) % seg) < seg * frac).astype(np.float32)
    return layer(n, a * np.clip(1 - d / width, 0, 1) * on, color)


def tint(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def tw(p, k, off):
    """a twinkle 0..1, k whole cycles per loop"""
    return math.sin(math.pi * ((p * k + off) % 1.0)) ** 3

# ---------------------------------------------------------------- chest auras (a loop of N frames)
N = 12


def reward_gold(n, p, sigil=False):
    """Reward chest: warm gold pool, fine ring with a travelling glint, four twinkles (sigil=True, the look in use: a dashed sigil ring)"""
    out = canvas(n)
    c = n / 2
    cy = c + 6
    over(out, pool(n, c, cy, 27, 18, (255, 190, 60), 0.34))
    over(out, pool(n, c, cy, 18, 12, (255, 226, 130), 0.22))
    over(out, ring(n, c, cy, 23, 15.5, (255, 224, 120), 0.8, arc=(2 * math.pi * p, 0.7, 0.9)))
    if sigil:
        over(out, dashes(n, c, cy, 16, 10.5, 8, -2 * math.pi * p / 8, 0.55, (255, 240, 180), 0.75, 1.1))
    for k in range(4):
        a = 2 * math.pi * (k + 0.5) / 4 + 0.4
        over(out, star(n, c + 23 * math.cos(a), cy + 15.5 * math.sin(a), 6, (255, 246, 210), 0.95 * tw(p, 1, k / 4.0)))
    for k in range(3):
        life = (p + k / 3.0) % 1.0
        x = c + (-17 if k % 2 == 0 else 17) + 3 * math.sin(2 * math.pi * (life + k))
        over(out, blob(n, x, cy + 4 - 26 * life, 1.6, (255, 220, 110), 0.85 * math.sin(math.pi * life)))
    return out


def cursed_smoke(n, p):
    """Cursed chest: a dark pool, smoke rising round the chest, a few embers. No ring under it."""
    out = canvas(n)
    c = n / 2
    cy = c + 7
    over(out, pool(n, c, cy, 27, 18, (14, 4, 24), 0.62, 0.9))
    rs = random.Random(SEED + 7)
    for _ in range(22):
        off, x0, size, sgn = rs.random(), rs.uniform(-17, 17), rs.uniform(0.7, 1.4), rs.choice((1, -1))
        life = (p + off) % 1.0
        x = c + x0 + sgn * 6 * math.sin(2 * math.pi * life) * size
        col = tint((70, 24, 120), (170, 110, 235), 0.25 + 0.5 * life)
        over(out, blob(n, x, cy + 6 - 30 * life, 4 + 6 * life * size, col, 0.72 * math.sin(math.pi * life) ** 1.2))
    re = random.Random(SEED + 8)
    for k in range(7):
        life = (p * 2 + k / 7.0) % 1.0
        x = c + re.uniform(-18, 18) + 4 * math.sin(2 * math.pi * (life + k))
        over(out, dot(n, x, cy + 4 - 34 * life, (255, 140, 40), (1 - life) * (0.6 + 0.4 * tw(p, 3, k / 7.0))))
    return out


def coffer_smoke(n, p):
    """Sealed Coffer on the big gold chest (client 38657): golden smoke curling up round the chest, coins of light in it. No ring."""
    out = canvas(n)
    c = n / 2
    cy = c + 10
    over(out, pool(n, c, cy, 44, 28, (220, 150, 30), 0.38, 1.0))
    rs = random.Random(SEED + 23)
    for _ in range(26):
        off, x0, size, sgn = rs.random(), rs.uniform(-32, 32), rs.uniform(0.7, 1.4), rs.choice((1, -1))
        life = (p + off) % 1.0
        xx = c + x0 * (1 - 0.35 * life) + sgn * 7 * math.sin(2 * math.pi * life) * size
        col = tint((200, 130, 30), (255, 236, 170), 0.2 + 0.7 * life)
        over(out, blob(n, xx, cy + 8 - 48 * life, 5 + 8 * life * size, col, 0.62 * math.sin(math.pi * life) ** 1.2))
    re = random.Random(SEED + 24)
    for k in range(9):
        life = (p * 2 + k / 9.0) % 1.0
        xx = c + re.uniform(-28, 28) + 4 * math.sin(2 * math.pi * (life + k))
        over(out, dot(n, xx, cy + 2 - 46 * life, (255, 210, 80), (1 - life) * (0.6 + 0.4 * tw(p, 3, k / 9.0))))
    return out


# ---------------------------------------------------------------- foot auras (steady; a slow travelling highlight)
F = 24   # frames of one slow turn (6 s at 250 ms); the total light stays the same, only the bright stretch moves
FOOT = {
    'templar': ((255, 214, 110), (255, 246, 214), 'Templar, holy gold'),
    'inquisitor': ((255, 238, 200), (255, 150, 60), 'Inquisitor, white and ember'),
    'sentinel': ((196, 224, 255), (120, 170, 255), 'Sentinel, steel and blue'),
}


def foot(n, p, key):
    main, acc, _ = FOOT[key]
    out = canvas(n)
    c = n / 2
    rx, ry = 21.0, 11.5
    over(out, pool(n, c, c, rx + 5, ry + 4, main, 0.20, 1.3))
    over(out, ring(n, c, c, rx, ry, main, 0.62, width=1.1, glow=2.2, arc=(2 * math.pi * p, 0.9, 0.55)))
    over(out, ring(n, c, c, rx - 4.5, ry - 2.6, acc, 0.28, width=0.8, glow=1.5))
    over(out, dashes(n, c, c, rx - 9, ry - 5.2, 6, 2 * math.pi * p / 6, 0.45, acc, 0.5, 0.9))
    for k in range(6):
        a = 2 * math.pi * k / 6
        over(out, blob(n, c + rx * math.cos(a), c + ry * math.sin(a), 1.4, acc, 0.75))
    return out


# ---------------------------------------------------------------- the range frame (a faint square on the floor)
TILE = 32
FRAME_TILES = 3   # the picture is 3 x 3 tiles; the module draws it as a nine-slice with a border of TILE px
FRAME_TINT = {'templar': (255, 214, 110), 'inquisitor': (255, 200, 150), 'sentinel': (150, 195, 255)}


def frame_square(side, tint):
    """a faint square frame `side` tiles wide: a 1.5 px line with a soft glow inside it and brighter corners. No fill: only the
    edges are drawn, the middle stays clear"""
    n = side * TILE
    out = canvas(n)
    xx, yy = grid(n)
    x0 = y0 = 0.0
    x1 = y1 = float(n)
    inside = (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
    d = np.minimum.reduce([xx - x0, x1 - xx, yy - y0, y1 - yy])
    edge = inside * (np.clip(1 - np.abs(d - 1.5) / 1.5, 0, 1) * 0.55 + np.exp(-(d / 7.0) ** 2) * 0.22)
    corner = inside * ((np.minimum(xx - x0, x1 - xx) < 12) & (np.minimum(yy - y0, y1 - yy) < 12)) * (d < 3) * 0.4
    over(out, layer(n, edge + corner, tint))
    return out


def nine_slice(img, tiles):
    """the frame picture drawn at `tiles` x `tiles` tiles the way the client's image-border does: the 32 px corners stay, the edges
    stretch along their length, the middle is stretched too (it is empty)"""
    b = TILE
    n = tiles * TILE
    out = Image.new('RGBA', (n, n))
    w = img.width
    src = [(0, b), (b, w - b), (w - b, w)]
    dst = [(0, b), (b, n - b), (n - b, n)]
    for (sy0, sy1), (dy0, dy1) in zip(src, dst):
        for (sx0, sx1), (dx0, dx1) in zip(src, dst):
            piece = img.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST)
            out.paste(piece, (dx0, dy0))
    return out


# ---------------------------------------------------------------- strips and files
CHEST = {
    'reward_sigil': (64, lambda n, p: reward_gold(n, p, True)),
    'cursed_smoke': (64, cursed_smoke),
    'coffer_smoke': (128, coffer_smoke),
}


def to_img(f):
    return Image.fromarray((np.clip(f, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA')


def strip(frames, n):
    """frames (float RGBA) side by side, n px each: the filmstrip image"""
    st = Image.new('RGBA', (n * len(frames), n))
    for i, f in enumerate(frames):
        st.paste(to_img(f), (i * n, 0))
    return st


def build():
    """{(folder, name): (frame size, [float frames], strip image)}"""
    res = {}
    for key, (n, fn) in CHEST.items():
        frames = [fn(n, i / N) for i in range(N)]
        res[('chest', key)] = (n, frames, strip(frames, n))
    for k in FOOT:
        frames = [foot(64, i / F, k) for i in range(F)]
        res[('foot', k + '_sigil')] = (64, frames, strip(frames, 64))
    for k, tint in FRAME_TINT.items():
        frames = [frame_square(FRAME_TILES, tint)]
        res[('frame', k)] = (TILE * FRAME_TILES, frames, strip(frames, TILE * FRAME_TILES))
    return res


def write(res, out):
    for (kind, key), (_n, _frames, st) in res.items():
        os.makedirs(os.path.join(out, kind), exist_ok=True)
        st.save(os.path.join(out, kind, key + '.png'))


def check(res, out):
    """the committed strips equal the generated ones (decoded pixels), and no other picture lies in the folders"""
    bad = []
    want = set()
    for (kind, key), (_n, _frames, st) in res.items():
        path = os.path.join(out, kind, key + '.png')
        want.add(os.path.normpath(path))
        if not os.path.isfile(path):
            bad.append('%s/%s.png: missing' % (kind, key))
            continue
        have = Image.open(path).convert('RGBA')
        if have.size != st.size or have.tobytes() != st.tobytes():
            bad.append('%s/%s.png: differs from the generator' % (kind, key))
    for kind in sorted(set(k for k, _ in res)):
        folder = os.path.join(out, kind)
        for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
            if os.path.normpath(os.path.join(folder, name)) not in want:
                bad.append('%s/%s: not made by the generator' % (kind, name))
    return bad


# ---------------------------------------------------------------- previews on the real sprites (needs the pair)
def preview(res, pair, outdir):
    sys.path.insert(0, os.path.join(HERE, 'sprites'))
    from datspr import Dat, Spr, render_thing, sprite_index
    d, s = Dat(os.path.join(pair, 'Tibia.dat')), Spr(os.path.join(pair, 'Tibia.spr'))
    os.makedirs(outdir, exist_ok=True)
    Z = 3

    def item(i):
        return render_thing(d.items[i - 100], s)

    def floor(gid, w, h):
        tile = item(gid).crop((0, 0, 32, 32))
        im = Image.new('RGBA', (w * 32, h * 32))
        for x in range(w):
            for y in range(h):
                im.paste(tile, (x * 32, y * 32))
        return im

    def aura(key, kind, f):
        frames = res[(kind, key)][1]
        return to_img(frames[f % len(frames)])

    def label(im, text):
        ImageDraw.Draw(im).rectangle((0, 0, im.width, 11), fill=(0, 0, 0, 200))
        ImageDraw.Draw(im).text((3, 0), text, fill=(255, 255, 255, 255))
        return im

    def scene(gid, cid, key, f, big, text):
        tiles = 4 if big else 3
        base = floor(gid, tiles, tiles)
        mx = my = tiles // 2 * 32
        if key:
            a = aura(key, 'chest', f)   # centred on the chest's tile, or on the corner of its 2 x 2 footprint
            base.alpha_composite(a, (mx + 16 - a.width // 2 + (-16 if big else 0), my + 16 - a.height // 2 + (-16 if big else 0)))
        base.alpha_composite(item(cid), (mx - (32 if big else 0), my - (32 if big else 0)))
        return label(base.resize((base.width * Z, base.height * Z), Image.NEAREST), text)

    floors = [410, 15000, 4526]
    rows = []
    for title, cid, key, big in (('reward chest 38758', 38758, 'reward_sigil', False), ('cursed chest 38642', 38642, 'cursed_smoke', False),
                                 ('sealed coffer on the big gold chest 38657', 38657, 'coffer_smoke', True)):
        cells = [scene(floors[0], cid, None, 0, big, 'no aura')]
        cells += [scene(g, cid, key, f, big, '%s f%d' % (key, f)) for g, f in zip(floors, (0, 4, 8))]
        row = Image.new('RGBA', (sum(c.width for c in cells) + 6 * len(cells), cells[0].height + 14), (24, 24, 28, 255))
        ImageDraw.Draw(row).text((4, 1), title, fill=(255, 220, 120, 255))
        x = 0
        for c in cells:
            row.alpha_composite(c, (x, 14))
            x += c.width + 6
        rows.append(row)
    sheet_rows(rows, os.path.join(outdir, 'chest_auras.png'))

    def outfit(look, colors):
        t = d.outfits[look - 1]
        size = (t.w * 32, t.h * 32)
        arrs = []
        for li in range(t.layers):
            lay = Image.new('RGBA', size)
            for hh in range(t.h):
                for ww in range(t.w):
                    a = s.sprite(t.sprites[sprite_index(t, 2, 0, 0, li, 0, ww, hh)])
                    if a is not None:
                        lay.alpha_composite(Image.fromarray(a, 'RGBA'), ((t.w - 1 - ww) * 32, (t.h - 1 - hh) * 32))
            arrs.append(np.asarray(lay).astype(np.float32))
        base = arrs[0]
        if len(arrs) > 1:
            m = arrs[1]
            grey = base[..., :3].mean(axis=2) / 255.0
            on = m[..., 3] > 0
            head = on & (m[..., 0] > 128) & (m[..., 1] > 128) & (m[..., 2] < 140)
            legs = on & ~head & (m[..., 1] > m[..., 0]) & (m[..., 1] > m[..., 2])
            feetm = on & ~head & ~legs & (m[..., 2] > m[..., 0]) & (m[..., 2] > m[..., 1])
            body = on & ~head & ~legs & ~feetm
            for chan, rgb in zip((head, body, legs, feetm), colors):
                for ch in range(3):
                    base[..., ch] = np.where(chan, np.clip(rgb[ch] * (0.45 + grey * 0.85), 0, 255), base[..., ch])
                base[..., 3] = np.where(chan, np.maximum(base[..., 3], m[..., 3]), base[..., 3])
        return Image.fromarray(base.astype(np.uint8), 'RGBA')

    def feet(im):
        a = np.asarray(im)[..., 3]
        yb = np.where(a.max(axis=1) > 0)[0].max()
        xs = np.where(a[max(yb - 3, 0):yb + 1].max(axis=0) > 0)[0]
        return int((xs.min() + xs.max()) / 2), int(yb)

    gold = ((205, 170, 110), (236, 196, 84), (200, 156, 60), (130, 96, 40))
    inq = ((230, 215, 190), (240, 240, 245), (240, 150, 60), (150, 90, 40))
    sen = ((190, 200, 215), (150, 175, 210), (110, 140, 190), (80, 100, 140))
    mate_colors = ((200, 160, 120), (120, 60, 50), (70, 60, 50), (60, 50, 40))

    def range_stage(gid, line, colors, radius, in_party):
        w = h = 2 * 5 + 3
        base = floor(gid, w, h)
        cx, cy = w // 2, h // 2

        def put(im, tx, ty):   # the feet of `im` on the middle of tile (tx, ty)
            ffx, ffy = feet(im)
            base.alpha_composite(im, (tx * 32 + 16 - ffx, ty * 32 + 26 - ffy))

        if in_party:   # one nine-slice widget of (2r + 1) tiles square, centred on the Templar (what the module lays)
            side = 2 * radius + 1
            base.alpha_composite(nine_slice(to_img(res[('frame', line)][1][0]), side), ((cx - radius) * 32, (cy - radius) * 32))
        look = outfit(131, colors)
        base.alpha_composite(aura(line + '_sigil', 'foot', 5), (cx * 32 + 16 - 32, cy * 32 + 26 - 34))
        put(look, cx, cy)
        if in_party:
            m = outfit(131, mate_colors)
            put(m, cx + radius - 1, cy - 2)
            put(m, cx + radius + 1, cy + 1)
        return base.resize((base.width * 2, base.height * 2), Image.NEAREST)

    cells = []
    for line, col, r, name in (('templar', gold, 4, 'Templar'), ('inquisitor', inq, 3, 'Inquisitor'), ('sentinel', sen, 5, 'Sentinel')):
        cells.append((range_stage(15000, line, col, r, True), '%s: sigil + range %d (party member in, one out)' % (name, r)))
    cells.append((range_stage(15000, 'templar', gold, 4, False), 'solo (no party): only the sigil'))
    cw, ch = cells[0][0].size
    im = Image.new('RGBA', (2 * (cw + 6), 2 * (ch + 22) + 16), (24, 24, 28, 255))
    ImageDraw.Draw(im).text((4, 2), 'Templar line: foot sigil, range frame in a party only', fill=(255, 220, 120, 255))
    for i, (c, t) in enumerate(cells):
        x, y = (i % 2) * (cw + 6), (i // 2) * (ch + 22) + 16
        im.alpha_composite(c, (x, y + 12))
        ImageDraw.Draw(im).text((x + 3, y), t, fill=(255, 255, 255, 255))
    im.convert('RGB').save(os.path.join(outdir, 'templar_foot_range.png'))

    rows2 = []
    for kind, keys, step in (('chest', list(k for (kd, k) in res if kd == 'chest'), 1), ('foot', ['templar_sigil'], 3)):
        for key in keys:
            n, frames, _st = res[(kind, key)]
            pick = list(range(0, len(frames), step))
            row = Image.new('RGBA', (len(pick) * (n + 2), n + 11), (30, 28, 34, 255))
            ImageDraw.Draw(row).text((2, 0), key + ' (frames, left to right)', fill=(255, 255, 255, 255))
            for i, f in enumerate(pick):
                row.alpha_composite(aura(key, kind, f), (i * (n + 2), 11))
            rows2.append(row)
    sheet_rows([r.resize((r.width * 2, r.height * 2), Image.NEAREST) for r in rows2], os.path.join(outdir, 'loop_frames.png'))
    print('previews in', outdir)


def sheet_rows(rows, path, bg=(24, 24, 28, 255)):
    im = Image.new('RGBA', (max(r.width for r in rows), sum(r.height + 6 for r in rows)), bg)
    y = 0
    for r in rows:
        im.alpha_composite(r, (0, y))
        y += r.height + 6
    im.convert('RGB').save(path)


def main(argv):
    arg = {}
    flags = set()
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('--out', '--preview', '--pair') and i + 1 < len(argv):
            arg[a] = argv[i + 1]
            i += 2
        elif a in ('--check', '-h', '--help'):
            flags.add(a)
            i += 1
        else:
            print('unknown argument:', a)
            print(__doc__)
            return 2
    if '-h' in flags or '--help' in flags:
        print(__doc__)
        return 0
    res = build()
    if '--check' in flags:
        bad = check(res, arg.get('--out', OUT))
        for b in bad:
            print('gen_aura_art --check:', b)
        if bad:
            return 1
        print('gen_aura_art --check: %d strips up to date' % len(res))
        return 0
    write(res, arg.get('--out', OUT))
    print('wrote %d strips into %s' % (len(res), arg.get('--out', OUT)))
    if '--preview' in arg:
        if '--pair' not in arg:
            print('--preview needs --pair PAIR_DIR (the folder with Tibia.dat and Tibia.spr)')
            return 2
        preview(res, arg['--pair'], arg['--preview'])
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
