#!/usr/bin/env python3
"""Append animated spell effects, missiles and outfit auras from three art sets to COPIES of our 10.98 Tibia.dat/.spr.

python3 -I import_vfx.py --ours-dat Tibia.dat --ours-spr Tibia.spr --out-dir out/vfx \
        --src-spells DIR_A --src-ki DIR_B --src-fx DIR_C \
        --expect-first-effect 429 --expect-first-missile 126 --expect-first-outfit 1511 \
        [--spec vfx_import.csv] [--preview DIR] [--lua-out ../../../server/data/lib/chaos_vfx.lua] \
        [--catalog-out ../../../server/data/spells/vfx_catalog.csv] [--auras-out ../../../server/data/XML/chaos_auras.csv]

Art sets (read only; nothing is executed from them):
  --src-spells  oblique spell effects: metadata.json + oblique/32px/<category>/<id>.png sheets (frames left to right,
                directional effects one row per direction E, SE, S, SW, W, NW, N, NE; anchor_tile = the target tile).
                The oblique 32 px renders are used: height leans up-left like our client's view.
  --src-ki      tintable greyscale energy effects: effects.json + effects/<id>/*_sheet.png (one frame per row, four
                identical columns); layered ones have back/front sheets and marker masks (core/flame/rim/sparks).
  --src-fx      pixel bursts: Part N/<id>.png, 64x64 frames left to right, nine colour rows.
The spec table (vfx_import.csv next to this file) lists every thing written, in id order:
  kind (effect | missile | aura), name, src (spells | ki | fx), src_id, var (direction for directional melee, segment
  for split effects, colour row for fx), tint (a mask preset name or rrggbb for the greyscale set), frames ('' all,
  'step2' every other frame, 'a-b'), ms per frame, place (feet | ground | centre | chest), note.

Placement.  The client draws a thing with its bottom-right tile on the map tile, so art that reaches right of / below
the target tile cannot be centred there.  Every effect/missile is therefore built on a w x h canvas whose bottom-right
tile is the target tile plus (dx, dy) (dx/dy = whole tiles the art reaches right of / below the target tile, 0..3), and
the server sends it at target + (dx, dy): server/data/lib/chaos_vfx.lua (written here) does that (Vfx(pos, name),
VfxShoot(from, to, name)).  The art's anchor point goes to a fixed point of the target tile,
near where our creatures stand (outfits are drawn 8 px up-left): feet/ground (14, 20) for the oblique set (its feet
point, a quarter tile right/down of its tile centre), (10, 22) for the front-on greyscale set (its own anchor),
centre (13, 13), chest (11, 8); the bursts anchor at their frame centre.  Layered art (back / front) is merged for
effects with the back layer at 60 % opacity: an effect is always drawn over the creature, so a dark ground disc of the
back layer would hide it.  Frame timing is kept (ms column; the bursts' own preview timing, the oblique set's 12 fps, the
greyscale set's 20 fps, auras every other frame at 100 ms).

Auras are outfit entries like the base client's (layers 2 = back / front, 4 identical direction patterns, animated
always by the animator, no 'animateAlways' flag so the timing is the animator's): with the client features
GameAuraFrontAndBack and GameBigAurasCenter (both on in our 10.98 profile) the client shifts an aura of w x h tiles by
((w-1)*16, (h-1)*16); the displacement flag places the feet point on the creature's feet.
Outputs in --out-dir: Tibia.dat, Tibia.spr, chaos_vfx.lua, vfx_catalog.csv, chaos_auras.csv.  Inputs are never
modified.  Deterministic: the same inputs give byte-identical outputs.  New ids = the input's effect / missile /
outfit counts + 1.. in spec order; --expect-first-* stop the run when the input pair is not the one the ids were
planned for (the Lua names / auras.xml depend on them).
Verification (always run): the output is re-parsed; every frame / pattern / layer of every new thing is rendered back
from the output spr and compared pixel-exact with the built canvas; all old dat entries are byte-identical; 3000
sampled old sprites (plus the first and last) are unchanged.
"""
import sys, os, csv, json, math, struct, argparse, random, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw
from datspr import Dat, Spr, TABLE_NEW, sprite_index
from gen_effects import encode_sprite

HERE = os.path.dirname(os.path.abspath(__file__))
NEW_BYTE = {name: b for b, name in TABLE_NEW.items()}

# tile-coordinate point (px from the target tile's top-left) the art's anchor is put on
PLACE = {'feet': (14, 20), 'ground': (14, 20), 'centre': (13, 13), 'chest': (11, 8)}
KI_FEET = (10, 22)          # the greyscale set is drawn front-on: its feet go under the figure's body, not its toes
BACK_ALPHA = 0.6            # effects are drawn over the creature: their back layer is merged at this opacity
DIRS8 = ['e', 'se', 's', 'sw', 'w', 'nw', 'n', 'ne']                  # row order of the oblique set
# missile pattern (x, y) -> direction (x 0/1/2 = west/centre/east, y = north/centre/south; centre unused -> south)
MISSILE_DIR = {(0, 0): 'nw', (1, 0): 'n', (2, 0): 'ne', (0, 1): 'w', (1, 1): 's', (2, 1): 'e',
               (0, 2): 'sw', (1, 2): 's', (2, 2): 'se'}
ROT = {'e': 0, 'ne': 45, 'n': 90, 'nw': 135, 'w': 180, 'sw': 225, 's': 270, 'se': 315}
EXTRA_PRESETS = {'holy_white': {'head': [255, 255, 255], 'body': [255, 244, 200], 'legs': [214, 176, 96], 'feet': [255, 252, 226]}}


# ------------------------------------------------------------------------------------------------ art readers
def rgba(path):
    return np.asarray(Image.open(path).convert('RGBA'))


def merge(back, front):
    """front over back, back at BACK_ALPHA (an effect cannot go behind the creature, so its back layer must not hide it)"""
    out = []
    for b, f in zip(back, front):
        b = b.copy(); b[:, :, 3] = np.rint(b[:, :, 3] * BACK_ALPHA).astype(np.uint8); b[b[:, :, 3] == 0] = 0
        im = Image.fromarray(b); im.alpha_composite(Image.fromarray(f)); out.append(np.asarray(im).copy())
    return out


def select(frames, spec):
    if not spec:
        return frames
    if spec == 'step2':
        return frames[::2]
    a, b = (int(x) for x in spec.split('-'))
    return frames[a:b + 1]


class SpellsSet:
    def __init__(self, root):
        self.root = root
        self.meta = {e['id']: e for e in json.load(open(os.path.join(root, 'metadata.json')))['effects']}

    def frames(self, sid, var='', layer='all', point='feet'):
        """-> (list of RGBA arrays, anchor point (x, y) in frame pixels)"""
        e = self.meta[sid]; v = e['variants']['oblique/32']
        assert v['tile'] == 32
        fw, fh, n = v['frame_w'], v['frame_h'], e['frames']
        row = DIRS8.index(var) if var else 0
        assert row < v['rows'], (sid, var)
        def load(ln):
            sheet = rgba(os.path.join(self.root, v['files'][ln]))
            return [sheet[row * fh:(row + 1) * fh, i * fw:(i + 1) * fw].copy() for i in range(n)]
        if layer == 'all' and 'back' in v['files']:
            out = merge(load('back'), load('front'))
        else:
            out = load(layer)
        ax, ay = v['anchor_tile']
        off = (16, 16) if point == 'centre' else (24, 24)                 # tile centre / oblique feet point
        return out, (ax * 32 + off[0], ay * 32 + off[1])


class KiSet:
    def __init__(self, root):
        self.root = root
        self.meta = json.load(open(os.path.join(root, 'effects.json')))['effects']

    def _sheet(self, rel, e):
        s = rgba(os.path.join(self.root, rel))
        cw, ch = e['cell']
        return [s[i * ch:(i + 1) * ch, 0:cw].copy() for i in range(e['frames'])]

    def tint(self, grey, tint, mask=None, masks=None):
        g = grey[:, :, 0].astype(np.float32) / 255.0
        out = np.zeros_like(grey)
        if mask is not None and not all(c in '0123456789abcdef' for c in tint):
            pre = dict(masks['presets']); pre.update(EXTRA_PRESETS)
            col = np.zeros(grey.shape[:2] + (3,), np.float32)
            mk = mask[:, :, :3].astype(np.int32)
            keys = sorted(masks['marker_colors'])
            d = np.stack([np.abs(mk - np.array(masks['marker_colors'][k])).sum(axis=2) for k in keys])
            near = d.argmin(axis=0)
            for i, k in enumerate(keys):
                col[near == i] = pre[tint][k]
        else:
            if all(c in '0123456789abcdef' for c in tint) and len(tint) == 6:
                c = [int(tint[i:i + 2], 16) for i in (0, 2, 4)]
            else:
                pre = dict(self.meta['aura_ki']['masks']['presets']); pre.update(EXTRA_PRESETS)
                c = pre[tint]['body']
            col = np.broadcast_to(np.array(c, np.float32), grey.shape[:2] + (3,)).copy()
            hot = np.clip((g - 0.78) / 0.22, 0, 1)[:, :, None] * 0.65         # white-hot core
            col = col * (1 - hot) + 255.0 * hot
        rgb = np.clip(np.rint(col * g[:, :, None]), 0, 255).astype(np.uint8)
        out[:, :, :3] = rgb; out[:, :, 3] = grey[:, :, 3]
        out[out[:, :, 3] == 0] = 0
        return out

    def frames(self, sid, var='', tint='', layer=None):
        """layer None = merged (front over back) ; 'back' / 'front' for auras"""
        e = self.meta[sid]
        if 'layers' in e and e['layers']:
            masks = e.get('masks')
            lay = {}
            for ln in ('back', 'front'):
                g = self._sheet(e['layers'][ln], e)
                mk = self._sheet(masks[ln], e) if masks else [None] * len(g)
                lay[ln] = [self.tint(a, tint, m, masks) for a, m in zip(g, mk)]
            if layer:
                out = lay[layer]
            else:
                out = merge(lay['back'], lay['front'])
        else:
            out = [self.tint(a, tint) for a in self._sheet(e['sheet'], e)]
        if var:
            a, b = e['segments'][var]['frames']
            out = out[a:b + 1]
        return out, tuple(e['anchor'])


class FxSet:
    def __init__(self, root):
        self.root = root
        self.index = {}
        for part in sorted(os.listdir(root)):
            p = os.path.join(root, part)
            if os.path.isdir(p):
                for f in sorted(os.listdir(p)):
                    if f.endswith('.png'):
                        self.index[f[:-4]] = os.path.join(p, f)

    def frames(self, sid, var):
        s = rgba(self.index[sid]); row = int(var)
        n = s.shape[1] // 64
        assert s.shape[0] == 9 * 64 and row < 9, sid
        return [s[row * 64:(row + 1) * 64, i * 64:(i + 1) * 64].copy() for i in range(n)], (32, 32)


def rotated(frame, anchor, deg):
    """rotate a frame about its anchor (nearest, so pixels stay crisp) on a square canvas centred on the anchor."""
    h, w = frame.shape[:2]
    R = int(math.ceil(math.hypot(max(anchor[0], w - anchor[0]), max(anchor[1], h - anchor[1])))) + 1
    cv = Image.new('RGBA', (2 * R, 2 * R), (0, 0, 0, 0))
    cv.paste(Image.fromarray(frame), (R - anchor[0], R - anchor[1]))
    if deg:
        cv = cv.rotate(deg, resample=Image.NEAREST, center=(R, R))
    a = np.asarray(cv).copy(); a[a[:, :, 3] == 0] = 0
    return a, (R, R)


# ------------------------------------------------------------------------------------------------ building
def bbox_tiles(items, point):
    """items: [(frame, anchor)] -> (left, top, right, bottom) whole tiles the art reaches beyond the target tile."""
    x0 = y0 = 10 ** 6; x1 = y1 = -10 ** 6
    for fr, (ax, ay) in items:
        al = fr[:, :, 3] > 0
        if not al.any():
            continue
        ys, xs = np.nonzero(al)
        ox, oy = point[0] - ax, point[1] - ay
        x0 = min(x0, xs.min() + ox); x1 = max(x1, xs.max() + 1 + ox)
        y0 = min(y0, ys.min() + oy); y1 = max(y1, ys.max() + 1 + oy)
    assert x1 > x0, 'empty art'
    t = lambda v: int(math.ceil(max(0, v) / 32))
    return t(-x0), t(-y0), t(x1 - 32), t(y1 - 32)


def place(fr, anchor, point, left, top, w, h):
    cv = np.zeros((h * 32, w * 32, 4), np.uint8)
    px = left * 32 + point[0] - anchor[0]; py = top * 32 + point[1] - anchor[1]
    fh, fw = fr.shape[:2]
    sx0, sy0 = max(0, -px), max(0, -py)
    dx0, dy0 = px + sx0, py + sy0
    ww = min(fw - sx0, w * 32 - dx0); hh = min(fh - sy0, h * 32 - dy0)
    src = fr[sy0:sy0 + hh, sx0:sx0 + ww]
    assert not (fr[:, :, 3] > 0).sum() - (src[:, :, 3] > 0).sum(), 'art clipped'
    cv[dy0:dy0 + hh, dx0:dx0 + ww] = src
    return cv


def build_thing(row, sets):
    """-> dict(kind, w, h, layers, px, py, phases, ms, frames={(phase, x, y, layer): canvas}, dx, dy, disp)"""
    kind, src, sid, var, tint = row['kind'], row['src'], row['src_id'], row['var'], row['tint']
    point = KI_FEET if src == 'ki' and row['place'] in ('feet', 'ground') else PLACE[row['place']]
    ms = int(row['ms'])
    if kind == 'aura':
        lay = []
        for ln in ('back', 'front'):
            if src == 'spells':
                f, anc = sets['spells'].frames(sid, layer=ln)
            else:
                f, anc = sets['ki'].frames(sid, tint=tint, layer=ln)
            lay.append(select(f, row['frames']))
        n = len(lay[0])
        items = [(fr, anc) for L in lay for fr in L]
        # union bbox of the art in frame pixels
        al = np.zeros(lay[0][0].shape[:2], bool)
        for fr, _ in items:
            al |= fr[:, :, 3] > 0
        ys, xs = np.nonzero(al)
        bx0, by0, bx1, by1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
        aw, ah = bx1 - bx0, by1 - by0
        # tile point of the art's top-left = point - anchor + bbox origin; find the smallest w,h and displacement >= 0
        tx, ty = point[0] - anc[0] + bx0, point[1] - anc[1] + by0
        def fit(size, t, art):
            for n_ in range(max(1, math.ceil(art / 32)), 12):
                p = t + (n_ - 1) * 16                       # canvas x of the art with displacement 0
                lo, hi = max(0, -p), n_ * 32 - art - p
                if lo <= hi:
                    return n_, lo, p + lo
            raise SystemExit(f'aura {row["name"]}: does not fit')
        w, dispx, cx = fit(None, tx, aw); h, dispy, cy = fit(None, ty, ah)
        frames = {}
        for li, L in enumerate(lay):
            for ph, fr in enumerate(L):
                cv = np.zeros((h * 32, w * 32, 4), np.uint8)
                cv[cy:cy + ah, cx:cx + aw] = fr[by0:by1, bx0:bx1]
                for x in range(4):
                    frames[(ph, x, 0, li)] = cv
        return dict(kind=kind, w=w, h=h, layers=2, px=4, py=1, phases=n, ms=ms, frames=frames, dx=0, dy=0,
                    disp=(dispx, dispy))
    # effects / missiles
    pats = {}
    if kind == 'missile':
        if src == 'spells':
            for pat, d in MISSILE_DIR.items():
                f, anc = sets['spells'].frames(sid, var=d, point='centre')
                pats[pat] = [(fr, anc) for fr in select(f, row['frames'])]
        else:
            f, anc = sets['ki'].frames(sid, tint=tint)
            f = select(f, row['frames'])
            directional = sid == 'ki_blast'
            for pat, d in MISSILE_DIR.items():
                pats[pat] = [rotated(fr, anc, ROT[d] if directional else 0) for fr in f]
        px = py = 3
    else:
        if src == 'spells':
            f, anc = sets['spells'].frames(sid, var=var)
        elif src == 'ki':
            f, anc = sets['ki'].frames(sid, var=var, tint=tint)
        else:
            f, anc = sets['fx'].frames(sid, var)
        pats[(0, 0)] = [(fr, anc) for fr in select(f, row['frames'])]
        px = py = 1
    n = len(next(iter(pats.values())))
    assert all(len(v) == n for v in pats.values())
    left, top, right, bottom = bbox_tiles([it for v in pats.values() for it in v], point)
    w, h = left + 1 + right, top + 1 + bottom
    frames = {}
    for (x, y), lst in pats.items():
        for ph, (fr, anc) in enumerate(lst):
            frames[(ph, x, y, 0)] = place(fr, anc, point, left, top, w, h)
    return dict(kind=kind, w=w, h=h, layers=1, px=px, py=py, phases=n, ms=ms, frames=frames, dx=right, dy=bottom, disp=None)


def tiles_of(img, w, h):
    out = {}
    for hh in range(h):
        for ww in range(w):
            y0 = (h - 1 - hh) * 32; x0 = (w - 1 - ww) * 32
            out[(ww, hh)] = img[y0:y0 + 32, x0:x0 + 32]
    return out


class T_:
    def __init__(self, g):
        self.w, self.h, self.layers, self.px, self.py, self.pz, self.phases = g['w'], g['h'], g['layers'], g['px'], g['py'], 1, g['phases']


def entry_bytes(g, sids):
    b = bytearray()
    if g['disp'] is not None and any(g['disp']):
        b += bytes([NEW_BYTE['displacement']]) + struct.pack('<HH', *g['disp'])
    b += b'\xff'
    if g['kind'] == 'aura':
        b += bytes([1, 0])                                   # one frame group (idle)
    w, h = g['w'], g['h']
    b += bytes([w, h])
    if w > 1 or h > 1:
        b += bytes([min(255, 32 * max(w, h))])
    b += bytes([g['layers'], g['px'], g['py'], 1, g['phases']])
    if g['phases'] > 1:
        loop = 1 if g['kind'] == 'effect' else 0             # effects play once, missiles / auras loop
        b += bytes([0]) + struct.pack('<ib', loop, 0)
        b += struct.pack('<' + 'II' * g['phases'], *([g['ms']] * 2 * g['phases']))
    b += struct.pack(f'<{len(sids)}I', *sids)
    return bytes(b)


def render_back(t, spr, layers):
    out = {}
    for ph in range(t.phases):
        for y in range(t.py):
            for x in range(t.px):
                for l in range(layers):
                    c = np.zeros((t.h * 32, t.w * 32, 4), np.uint8)
                    for hh in range(t.h):
                        for ww in range(t.w):
                            a = spr.sprite(t.sprites[sprite_index(t, x, y, 0, l, ph, ww, hh)])
                            if a is not None:
                                y0 = (t.h - 1 - hh) * 32; x0 = (t.w - 1 - ww) * 32
                                c[y0:y0 + 32, x0:x0 + 32] = a
                    out[(ph, x, y, l)] = c
    return out


# ------------------------------------------------------------------------------------------------ text outputs
def lua_text(rows, gens, ids):
    L = ['-- GENERATED by client/tools/sprites/import_vfx.py from vfx_import.csv: animated spell effects, missiles and',
         '-- auras appended to the client Tibia.dat/.spr after the ids of chaos_fx.lua.  Do not edit by hand.',
         '-- Big effects are drawn with their bottom-right tile at the target tile + (dx, dy), so they must be sent there:',
         '-- use Vfx(pos, name) / VfxShoot(fromPos, toPos, name) instead of sendMagicEffect with the raw id.  Both return',
         '-- false (and send nothing) for an unknown name, so a caller can fall back to a stock effect.',
         'ChaosVfx = {']
    for r, g in zip(rows, gens):
        if r['kind'] == 'effect':
            L.append(f"\t{r['name']} = {{id = {ids[r['name']]}, dx = {g['dx']}, dy = {g['dy']}, ms = {g['ms'] * g['phases']}}},  -- {r['note']}")
    L.append('}\n\nChaosVfxMissile = {')
    for r, g in zip(rows, gens):
        if r['kind'] == 'missile':
            L.append(f"\t{r['name']} = {{id = {ids[r['name']]}, dx = {g['dx']}, dy = {g['dy']}}},  -- {r['note']}")
    L.append('}\n\n-- auras: look = client outfit id (auras.xml clientid), aura = the id in data/XML/auras.xml (server/tools/install_auras.py)')
    L.append('ChaosVfxAura = {')
    for r, g in zip(rows, gens):
        if r['kind'] == 'aura':
            L.append(f"\t{r['name']} = {{look = {ids[r['name']]}, aura = {ids['aura:' + r['name']]}, title = \"{r['note']}\"}},")
    L += ['}', '',
          'function Vfx(pos, name)',
          '\tlocal e = ChaosVfx[name]',
          '\tif not e or not pos then',
          '\t\treturn false',
          '\tend',
          '\tPosition(pos.x + e.dx, pos.y + e.dy, pos.z):sendMagicEffect(e.id)',
          '\treturn true',
          'end', '',
          '-- directional effects (name_n, name_ne, ... name_nw) by a creature direction (NORTH .. NORTHWEST)',
          'local DIRNAME = {[0] = "n", [1] = "e", [2] = "s", [3] = "w", [4] = "sw", [5] = "se", [6] = "nw", [7] = "ne"}',
          'function VfxDir(pos, base, direction)',
          '\treturn Vfx(pos, base .. "_" .. (DIRNAME[direction] or "s"))',
          'end', '',
          'function VfxShoot(fromPos, toPos, name)',
          '\tlocal m = ChaosVfxMissile[name]',
          '\tif not m or not fromPos or not toPos then',
          '\t\treturn false',
          '\tend',
          '\tPosition(fromPos.x + m.dx, fromPos.y + m.dy, fromPos.z):sendDistanceEffect(',
          '\t\tPosition(toPos.x + m.dx, toPos.y + m.dy, toPos.z), m.id)',
          '\treturn true',
          'end', '']
    return '\n'.join(L)


def write_catalog(rows, gens, ids, path):
    with open(path, 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['kind', 'id', 'name', 'size', 'send_offset', 'patterns', 'layers', 'frames', 'ms', 'note'])
        for r, g in zip(rows, gens):
            w.writerow([r['kind'], ids[r['name']], r['name'], f"{g['w']}x{g['h']}", f"{g['dx']},{g['dy']}",
                        f"{g['px']}x{g['py']}", g['layers'], g['phases'], g['ms'], r['note']])


def write_auras(rows, ids, path):
    with open(path, 'w', newline='') as fh:
        w = csv.writer(fh); w.writerow(['aura_id', 'client_id', 'name'])
        for r in rows:
            if r['kind'] == 'aura':
                w.writerow([ids['aura:' + r['name']], ids[r['name']], r['note']])


# ------------------------------------------------------------------------------------------------ preview
def ground(n):
    g = Image.new('RGBA', (n * 32, n * 32), (74, 66, 54, 255))
    d = ImageDraw.Draw(g)
    for i in range(n):
        for j in range(n):
            if (i + j) % 2:
                d.rectangle([i * 32, j * 32, i * 32 + 31, j * 32 + 31], fill=(84, 75, 61, 255))
    return g


def preview(rows, gens, dat, spr, out_dir):
    """filmstrips: each thing on a 5x5 ground with a reference outfit on the centre tile, as the client places it."""
    from datspr import render_outfit
    os.makedirs(out_dir, exist_ok=True)
    body = render_outfit(dat, spr, 128)                     # 64x64, drawn 8 px up-left like the client
    N = 5; C = 2
    def scene(g, ph, pat=(0, 0), layer_order=None):
        im = ground(N)
        tile = (C * 32, C * 32)
        if g['kind'] == 'missile':
            im.alpha_composite(body, (tile[0] - 32 - 8, tile[1] - 32 - 8))
        def draw_thing(l):
            fr = Image.fromarray(g['frames'][(ph,) + pat + (l,)])
            if g['kind'] == 'aura':
                ox = tile[0] + (g['w'] - 1) * 16 - g['disp'][0] - (g['w'] - 1) * 32
                oy = tile[1] + (g['h'] - 1) * 16 - g['disp'][1] - (g['h'] - 1) * 32
            else:
                ox = tile[0] + g['dx'] * 32 - (g['w'] - 1) * 32
                oy = tile[1] + g['dy'] * 32 - (g['h'] - 1) * 32
            big = Image.new('RGBA', im.size); big.alpha_composite(fr, (max(0, ox), max(0, oy)), (max(0, -ox), max(0, -oy)))
            im.alpha_composite(big)
        if g['kind'] == 'aura':
            draw_thing(0); im.alpha_composite(body, (tile[0] - 32 - 8, tile[1] - 32 - 8)); draw_thing(1)
        elif g['kind'] == 'effect':
            im.alpha_composite(body, (tile[0] - 32 - 8, tile[1] - 32 - 8)); draw_thing(0)
        else:
            draw_thing(0)
        return im
    sheets = {'effect': [], 'missile': [], 'aura': []}
    for r, g in zip(rows, gens):
        n = g['phases']; k = 6
        idx = sorted(set(int(round(i * (n - 1) / (k - 1))) for i in range(k)))
        if g['kind'] == 'missile':
            fr = [scene(g, 0, p) for p in [(2, 1), (1, 0), (0, 2), (2, 2)]] + [scene(g, n // 2, (2, 1))]
        else:
            fr = [scene(g, i) for i in idx]
        strip = Image.new('RGBA', (len(fr) * N * 32 + 4 * len(fr), N * 32 + 14), (12, 12, 16, 255))
        for i, f in enumerate(fr):
            strip.alpha_composite(f, (i * (N * 32 + 4), 14))
        ImageDraw.Draw(strip).text((2, 1), f"{r['name']} {g['w']}x{g['h']} +{g['dx']},{g['dy']} f{g['phases']}x{g['ms']}ms", fill=(255, 220, 120, 255))
        sheets[g['kind']].append(strip)
    paths = []
    for kind, strips in sheets.items():
        for part in range(0, len(strips), 20):
            chunk = strips[part:part + 20]
            W = max(s.width for s in chunk); H = sum(s.height for s in chunk)
            sh = Image.new('RGB', (W, H), (12, 12, 16)); y = 0
            for s in chunk:
                sh.paste(s.convert('RGB'), (0, y)); y += s.height
            p = os.path.join(out_dir, f'vfx_{kind}_{part // 20 + 1}.png'); sh.save(p); paths.append(p)
    return paths


# ------------------------------------------------------------------------------------------------ main
def read_spec(path):
    with open(path, newline='') as fh:
        rows = list(csv.DictReader(fh))
    names = [r['name'] for r in rows]
    assert len(set(names)) == len(names), 'duplicate name in spec'
    order = {'effect': 0, 'missile': 1, 'aura': 2}
    assert all(r['kind'] in order for r in rows)
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat', required=True); ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--src-spells', required=True); ap.add_argument('--src-ki', required=True); ap.add_argument('--src-fx', required=True)
    ap.add_argument('--spec', default=os.path.join(HERE, 'vfx_import.csv'))
    ap.add_argument('--expect-first-effect', type=int, default=None)
    ap.add_argument('--expect-first-missile', type=int, default=None)
    ap.add_argument('--expect-first-outfit', type=int, default=None)
    ap.add_argument('--aura-first-id', type=int, default=6, help='first auras.xml id (the base server has 1..5)')
    ap.add_argument('--preview', default=None)
    ap.add_argument('--lua-out', default=None); ap.add_argument('--catalog-out', default=None); ap.add_argument('--auras-out', default=None)
    a = ap.parse_args()
    t0 = time.time()
    os.makedirs(a.out_dir, exist_ok=True)
    for p in (a.ours_dat, a.ours_spr):
        assert os.path.abspath(os.path.dirname(p)) != os.path.abspath(a.out_dir), 'out-dir must differ from the input dir'
    rows = read_spec(a.spec)
    od = Dat(a.ours_dat); ospr = Spr(a.ours_spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]), f'expected our 10.98 dat (animator, u32, frame groups): {od.variant}'
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    ne0, nm0, no0 = len(od.effects), len(od.missiles), len(od.outfits)
    print(f'input: effects {ne0}, missiles {nm0}, outfits {no0}, sprites {ospr.count}')
    for flag, have in ((a.expect_first_effect, ne0), (a.expect_first_missile, nm0), (a.expect_first_outfit, no0)):
        if flag is not None and have + 1 != flag:
            sys.exit(f'first new id would be {have + 1}, expected {flag}: wrong input pair (or already imported). '
                     f'input has effects {ne0}, missiles {nm0}, outfits {no0}')
    sets = {'spells': SpellsSet(a.src_spells), 'ki': KiSet(a.src_ki), 'fx': FxSet(a.src_fx)}

    # --- 1. build
    gens = [build_thing(r, sets) for r in rows]
    ids, cnt = {}, {'effect': ne0, 'missile': nm0, 'aura': no0}
    aura_id = a.aura_first_id
    for r in rows:
        cnt[r['kind']] += 1; ids[r['name']] = cnt[r['kind']]
        if r['kind'] == 'aura':
            ids['aura:' + r['name']] = aura_id; aura_id += 1
    assert cnt['missile'] <= 255, 'distance effects are uint8 on the wire'
    assert cnt['effect'] <= 65535
    print(f"built {len(rows)} things ({sum(len(g['frames']) for g in gens)} canvases) in {time.time() - t0:.1f}s")

    # --- 2. sprite records (deduplicated inside the new set)
    recs = {}
    sid_lists = []
    for g in gens:
        T = T_(g)
        lst = [0] * (g['w'] * g['h'] * g['layers'] * g['px'] * g['py'] * g['phases'])
        for (ph, x, y, l), img in g['frames'].items():
            for (ww, hh), tile in tiles_of(img, g['w'], g['h']).items():
                rec = encode_sprite(np.ascontiguousarray(tile))
                if rec is not None:
                    recs.setdefault(rec, len(recs) + 1)
                    lst[sprite_index(T, x, y, 0, l, ph, ww, hh)] = rec
        sid_lists.append(lst)
    base = ospr.count
    newrecs = list(recs)
    rid = {rec: base + i + 1 for i, rec in enumerate(newrecs)}
    entries = [entry_bytes(g, [rid[x] if x else 0 for x in lst]) for g, lst in zip(gens, sid_lists)]

    # --- 3. dat: outfits | effects | missiles, each with the new entries at its end
    d = od.data
    o_end = od.outfits[-1].raw[1]; e_end = od.effects[-1].raw[1]; m_end = od.missiles[-1].raw[1]
    assert od.effects[0].raw[0] == o_end and od.missiles[0].raw[0] == e_end and m_end == len(d)
    part = {k: b''.join(e for r, e in zip(rows, entries) if r['kind'] == k) for k in ('aura', 'effect', 'missile')}
    out = bytearray(d[:o_end]) + part['aura'] + d[o_end:e_end] + part['effect'] + d[e_end:m_end] + part['missile']
    struct.pack_into('<HHH', out, 6, cnt['aura'], cnt['effect'], cnt['missile'])
    open(os.path.join(a.out_dir, 'Tibia.dat'), 'wb').write(out)

    # --- 4. spr (streamed: bigger table, old records shifted by 4*n, new records appended)
    m = ospr.m; oc = ospr.count; nn = len(newrecs)
    toffs = ospr.offs.astype('<u8').copy(); toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur); cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(a.out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, oc + nn)); f.write(table.tobytes())
        pos = 8 + 4 * oc
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)]); pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    print(f"dat: outfits {no0} -> {cnt['aura']}, effects {ne0} -> {cnt['effect']}, missiles {nm0} -> {cnt['missile']}; "
          f"spr: {nn} sprites appended ({oc} -> {oc + nn}, +{sum(map(len, newrecs)) / 1e6:.1f} MB)")

    # --- 5. text outputs
    lua = lua_text(rows, gens, ids)
    open(os.path.join(a.out_dir, 'chaos_vfx.lua'), 'w').write(lua)
    write_catalog(rows, gens, ids, os.path.join(a.out_dir, 'vfx_catalog.csv'))
    write_auras(rows, ids, os.path.join(a.out_dir, 'chaos_auras.csv'))
    for opt, fn in ((a.lua_out, lambda p: open(p, 'w').write(lua)), (a.catalog_out, lambda p: write_catalog(rows, gens, ids, p)),
                    (a.auras_out, lambda p: write_auras(rows, ids, p))):
        if opt:
            fn(opt); print('wrote', opt)

    # --- 6. verification
    md = Dat(os.path.join(a.out_dir, 'Tibia.dat')); ms = Spr(os.path.join(a.out_dir, 'Tibia.spr'))
    assert md.variant == od.variant, md.variant
    assert md.counts == (od.counts[0], cnt['aura'], cnt['effect'], cnt['missile']), md.counts
    assert ms.count == oc + nn and md.max_sprite <= ms.count and ms.alpha and ms.signature == ospr.signature
    assert md.data[:6] == d[:6] and md.data[12:o_end] == d[12:o_end], 'items / old outfits changed'
    for cat, lo, lm in (('o', od.outfits, md.outfits), ('e', od.effects, md.effects), ('m', od.missiles, md.missiles)):
        for to in lo:
            tm = lm[to.id - 1]
            assert md.data[tm.raw[0]:tm.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id)
    nframes = 0
    for r, g in zip(rows, gens):
        lst = {'effect': md.effects, 'missile': md.missiles, 'aura': md.outfits}[r['kind']]
        t = lst[ids[r['name']] - 1]
        assert (t.w, t.h, t.layers, t.px, t.py, t.pz, t.phases) == (g['w'], g['h'], g['layers'], g['px'], g['py'], 1, g['phases']), r['name']
        assert t.anim is None or list(t.anim[3]) == [g['ms']] * 2 * g['phases'], r['name']
        want_flags = {'displacement': tuple(g['disp'])} if g['disp'] and any(g['disp']) else {}
        assert t.flags == want_flags, (r['name'], t.flags)
        back = render_back(t, ms, g['layers'])
        assert back.keys() == g['frames'].keys(), r['name']
        for k, img in g['frames'].items():
            nframes += 1
            if not np.array_equal(back[k], img):
                raise SystemExit(f"MISMATCH {r['kind']} {r['name']} frame {k}")
    random.seed(1)
    for sid in random.sample(range(1, oc + 1), min(3000, oc)) + [1, oc]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    print(f'verified: output dat parses ({md.variant}); {len(rows)} new things, {nframes} frames/patterns/layers '
          f'pixel-identical to the built art; all {no0} outfits, {ne0} effects, {nm0} missiles and every item byte-identical; '
          f'3000 sampled old sprites unchanged; {ms.count} sprites')
    print(f"ids: effects {ne0 + 1}..{cnt['effect']}, missiles {nm0 + 1}..{cnt['missile']}, aura outfits {no0 + 1}..{cnt['aura']} "
          f"(auras.xml ids {a.aura_first_id}..{aura_id - 1})")
    if a.preview:
        ps = preview(rows, gens, od, ospr, a.preview)
        print(f'preview: {len(ps)} sheets in {a.preview}')
    print(f'done in {time.time() - t0:.1f}s')


if __name__ == '__main__':
    main()
