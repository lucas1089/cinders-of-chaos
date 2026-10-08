#!/usr/bin/env python3
"""Project Chaos dark environment tile set: procedurally drawn grounds, borders, walls and objects, appended as new
items to a 10.98 Tibia.dat / Tibia.spr pair.

Every picture is drawn here from code (periodic noise, Voronoi cells, height maps lit from the upper left, shape
fields); no sprite of any client is read, traced or recoloured.  Each tile is drawn at 128 px, averaged down to the
64 px masters (kept as PNG next to this file, for a future 64 px spr) and to the 32 px sprites the client uses.
Before the downsampling a detail pass adds readable shading: grounds get cavity shading and lit rims from their height
maps (darklib.relief); objects get a soft volume light from their silhouette, a bright rim on the edge that faces the
light, a core shadow on the far edge and a small gloss (darklib.rim_light; matte for rubble and bones, rim only for
walls).

python3 -I gen_dark_tiles.py --ours-dat Tibia.dat --ours-spr Tibia.spr --out-dir out/dark \
        [--masters dark_tiles/masters] [--sheets dark_tiles] [--manifest-out ../../../server/data/items/dark_tiles.csv]
        [--lua-out ../../../server/data/lib/chaos_dark_tiles.lua] [--preview-only]

* Order in the full rebuild chain: merge_outfits.py -> gen_effects.py -> set_multiuse.py -> gen_dark_tiles.py.
  gen_effects.py and set_multiuse.py copy the item section byte for byte, so running them after this script is also
  fine; this script copies outfits, effects and missiles byte for byte.
* Client ids: FIRST_ID (27484) and up, in the order of THINGS below (they are appended after the last stock item,
  27483).  Server ids (items.otb) are client id + SERVER_OFFSET (3000): 30484 and up.  The installer
  server/tools/install_dark_tiles.py writes them into items.otb / items.xml from the manifest.
* Input: a dat with exactly FIRST_ID - 1 items (the set is appended), or an earlier output of this script (FIRST_ID - 1 +
  len(THINGS) items: the set is rebuilt in place, every sprite is reused, the pair comes out identical).
  Input files are never modified.
* Spr: new records are appended (colour key ff00ff, RLE runs, RGBA), the offset table grows, old records are copied byte
  for byte; identical records are written once and records already in the input spr are reused.
* Outputs in --out-dir: Tibia.dat, Tibia.spr, dark_tiles.csv (manifest), chaos_dark_tiles.lua, contact sheets.
  --masters writes the 64 px master PNGs (one sheet per thing: patterns as laid out in the world, animation phases
  side by side); --sheets writes contact_32.jpg, contact_64.jpg (first frame of every thing) and scene_32.png (a
  sample area at 32 px: grounds with borders over a plain green, walls, objects); scene_32_x2.png (nearest x2) goes to
  --out-dir. The xBRZ look is checked in the client (HD upscaling).
* Fill check (always, before anything is written): grounds must be opaque edge to edge, walls and objects must fill
  their canvas (objects are scaled to fit after drawing), every 32x32 part of a multi-tile thing must be used, border
  pieces must reach the edges they continue. The run stops when a sprite fails.
* Verification (always): the output dat is re-parsed; every written thing is rendered back from the output spr and
  compared pixel-exact with the generated 32 px picture; every other dat entry and 3000 sampled old sprites are
  checked unchanged.
"""
import argparse, csv, hashlib, math, os, random, struct, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw
from datspr import Dat, Spr, sprite_index
import darklib as L

HERE = os.path.dirname(os.path.abspath(__file__))
R = 128                      # drawing resolution per tile
T = 4 * R                    # ground texture period (4 x 4 tiles)
FIRST_ID = 27484
SERVER_OFFSET = 3000

# dat flag bytes (10.10+ table)
F_GROUND, F_CLIP, F_BOTTOM, F_TOP = 0, 1, 2, 3
F_NOTWALK, F_NOTMOVE, F_BLOCKMISSILE, F_BLOCKPATH = 12, 13, 14, 15
F_LIGHT, F_MINIMAP, F_FULLGROUND = 22, 29, 31

# light colours (8-bit 6x6x6 index r*36 + g*6 + b)
def c216(r, g, b):
    return r * 36 + g * 6 + b

LC_FIRE = c216(5, 3, 1)      # 199, warm flame
LC_MAGMA = c216(5, 1, 0)     # 186, red-orange
LC_PURPLE = c216(3, 0, 5)    # 113
LC_TEAL = c216(0, 4, 4)      # 28
LC_CRIMSON = c216(5, 0, 1)   # 181


# =================================================================================================== ground textures
def tile_window(X, Y, margin=0.24):
    """1 in the middle of every tile, 0 at its edges (accents that must not cross a tile edge)"""
    lx = X % R; ly = Y % R
    m = margin * R
    return L.sstep(0, m, np.minimum(lx, R - lx)) * L.sstep(0, m, np.minimum(ly, R - ly))


def obsidian(seed, glow, Y=None, X=None):
    """cracked crimson-black obsidian plates. glow 0 = faint embers in a few cracks, 1 = magma veins inside the tile"""
    if Y is None:
        Y, X = L.grid(T, T)
    w1 = L.FBM(seed + 1, 4, T, 3); w2 = L.FBM(seed + 2, 4, T, 3)
    WX = X + (w1(X, Y) - 0.5) * 46
    WY = Y + (w2(X, Y) - 0.5) * 46
    V = L.Voronoi(seed, 8, T, 0.9)
    f1, f2, idn, dx, dy = V(WX, WY)
    crack = f2 - f1
    cm = 1 - L.sstep(1.2, 6.5, crack)
    V2 = L.Voronoi(seed + 5, 22, T, 0.9)
    g1, g2, _, _, _ = V2(WX, WY)
    fine = (1 - L.sstep(0.6, 2.6, g2 - g1)) * (L.FBM(seed + 6, 8, T, 2)(X, Y) > 0.52)
    val = V.val.reshape(-1)[idn]
    rough = L.FBM(seed + 3, 16, T, 4)(X, Y)
    vv = V.val.reshape(-1)
    tilt = ((vv[(idn * 7 + 3) % vv.size] - 0.5) * dx + (vv[(idn * 13 + 5) % vv.size] - 0.5) * dy) * 0.12
    h = 5 * val + tilt + 3.0 * rough + 5 * L.sstep(0, 16, crack) - 9 * cm - 2.5 * fine
    big = L.FBM(seed + 4, 4, T, 3)(X, Y)
    tone = 0.5 * val + 0.3 * big + 0.2 * rough
    alb = L.ramp(tone, ['0f0a0d', '1b1216', '271a1f', '352126', '45282d'])
    alb = alb * (1 - 0.75 * cm[..., None]) * (1 - 0.35 * fine[..., None])
    out = L.shade(alb, h, True, strength=1.0, ambient=0.5, diffuse=0.8, spec=0.28, shininess=26)
    core = 1 - L.sstep(0.0, 4.5, crack)
    if glow:
        win = tile_window(X, Y, 0.26)
        sel = (L.FBM(seed + 8, 6, T, 2)(X, Y) > 0.38) * win
        heat = np.clip(core * sel * 1.15, 0, 1)
        halo = np.exp(-crack / 9.0) * sel * 0.55
        em = L.ramp(heat, [(0, '000000'), (0.25, '5c0c04'), (0.55, 'c22a08'), (0.8, 'ff7a1e'), (1, 'ffd070')])
        em = em + halo[..., None] * L.hexcol('a21a06')[None, None, :] * 0.6
        out = np.clip(out * (1 - 0.5 * heat[..., None]) + em, 0, 1)
    else:
        sel = (L.FBM(seed + 9, 6, T, 2)(X, Y) > 0.66).astype(np.float32)
        heat = core * sel * 0.8
        out = np.clip(out + heat[..., None] * L.hexcol('6a1206')[None, None, :], 0, 1)
    return out, h


def ash_soil(seed, Y=None, X=None):
    if Y is None:
        Y, X = L.grid(T, T)
    big = L.FBM(seed + 1, 4, T, 3)(X, Y)
    mid = L.FBM(seed + 2, 16, T, 3)(X, Y)
    fine = L.PNoise(seed + 3, 128, T)(X, Y)
    V = L.Voronoi(seed, 26, T, 0.9)
    f1, f2, idn, dx, dy = V(X, Y)
    pv = V.val.reshape(-1)[idn]
    rad = 3 + 7 * ((pv * 7.3) % 1)
    peb = (pv > 0.62) * np.clip(1 - (f1 / rad) ** 2, 0, 1)
    h = 9 * big + 5 * mid + 1.2 * fine + 7 * np.sqrt(peb)
    tone = 0.45 * big + 0.4 * mid + 0.15 * fine
    alb = L.ramp(tone, ['1c1918', '2a2624', '383330', '47413c', '57504a'])
    flecks = (fine > 0.8) * (mid > 0.45)
    alb = np.where(flecks[..., None], alb * 1.35, alb)
    pebc = L.ramp(pv * 0.6 + 0.2, ['221e1d', '3a3432', '524a46'])
    alb = np.where((peb > 0)[..., None], pebc, alb)
    out = L.shade(alb, h, True, strength=1.0, ambient=0.5, diffuse=0.75)
    V3 = L.Voronoi(seed + 7, 18, T, 0.9)
    c1, _, cid, _, _ = V3(X, Y)
    cin = (V3.val.reshape(-1)[cid] > 0.95) * (1 - L.sstep(1.0, 3.2, c1))
    out = np.clip(out + cin[..., None] * L.hexcol('a0300c')[None, None, :], 0, 1)
    return out, h


def wet_rock(seed, Y=None, X=None):
    if Y is None:
        Y, X = L.grid(T, T)
    big = L.FBM(seed + 1, 4, T, 4)(X, Y)
    rid = L.ridged(L.FBM(seed + 2, 8, T, 3)(X, Y))
    fine = L.FBM(seed + 3, 32, T, 2)(X, Y)
    h = 34 * big + 10 * rid ** 2 + 3 * fine
    puddle = L.sstep(0.40, 0.36, big)
    h = h * (1 - puddle) + puddle * (34 * 0.36)
    tone = 0.55 * big + 0.3 * rid + 0.15 * fine
    alb = L.ramp(tone, ['0d0f12', '15181c', '1d2126', '262a31', '30353d'])
    water = L.ramp(fine, ['080b10', '0e141c', '18202b'])
    alb = alb * (1 - puddle[..., None]) + water * puddle[..., None]
    spec = 0.16 + 0.22 * puddle
    out = L.shade(alb, h, True, strength=0.55, ambient=0.55, diffuse=0.7, spec=spec, shininess=40)
    return out, h


def moss_layer(seed, X, Y, cover):
    """moss colour + height on a 0..1 cover field"""
    clump = L.Voronoi(seed + 11, 30, T, 0.9)
    f1, _, idn, _, _ = clump(X, Y)
    cv = clump.val.reshape(-1)[idn]
    dome = np.clip(1 - (f1 / (9 + 6 * cv)) ** 2, 0, 1)
    fib = L.PNoise(seed + 12, 160, T)(X, Y)
    tone = 0.45 * cv + 0.35 * dome + 0.2 * fib
    col = L.ramp(tone, ['0a120f', '101c17', '17271e', '203226', '2b3d2e'])
    col = col * (0.88 + 0.24 * fib[..., None])
    return col, 4 * dome + 1.2 * fib


def dark_moss(seed, Y=None, X=None):
    if Y is None:
        Y, X = L.grid(T, T)
    big = L.FBM(seed + 1, 4, T, 3)(X, Y)
    soil = L.ramp(L.FBM(seed + 2, 16, T, 3)(X, Y), ['120f0c', '1c1813', '28221b'])
    cover = L.sstep(0.22, 0.32, big)
    mc, mh = moss_layer(seed, X, Y, cover)
    alb = soil * (1 - cover[..., None]) + mc * cover[..., None]
    h = 6 * big + cover * mh + 2 * cover
    out = L.shade(alb, h, True, strength=1.0, ambient=0.5, diffuse=0.75)
    return out, h


def mossy_rock(seed, Y=None, X=None):
    """wet rock with moss patches inside the tile (mixes seamlessly with wet_rock tiles)"""
    if Y is None:
        Y, X = L.grid(T, T)
    rock, h = wet_rock(seed, Y, X)
    cover = L.sstep(0.45, 0.58, L.FBM(seed + 21, 8, T, 3)(X, Y)) * tile_window(X, Y, 0.3)
    mc, mh = moss_layer(seed + 20, X, Y, cover)
    mh2 = h + cover * (mh + 2)
    moss = L.shade(mc, mh2, True, strength=1.0, ambient=0.5, diffuse=0.75)
    return rock * (1 - cover[..., None]) + moss * cover[..., None], mh2


def bone_earth(seed, Y=None, X=None):
    """ash soil with bones lying inside each tile (mixes seamlessly with ash_soil tiles)"""
    if Y is None:
        Y, X = L.grid(T, T)
    soil, h = ash_soil(seed, Y, X)
    out = np.concatenate([soil, np.ones(soil.shape[:2] + (1,), np.float32)], axis=-1)
    for ty in range(4):
        for tx in range(4):
            rng = np.random.default_rng(seed * 100 + ty * 4 + tx)
            sl = (slice(ty * R, (ty + 1) * R), slice(tx * R, (tx + 1) * R))
            ly, lx = L.grid(R, R)
            layer = np.zeros((R, R, 4), np.float32)
            n = int(rng.integers(2, 4))
            for _ in range(n):
                layer = L.over(layer, bone_sprite(lx, ly, rng, scale=1.0))
            if rng.random() < 0.4:
                layer = L.over(layer, skull_sprite(lx, ly, rng.uniform(30, 98), rng.uniform(30, 98), 0.9))
            out[sl] = L.over(out[sl], layer)
    return out[..., :3], h


def bone_sprite(X, Y, rng, scale=1.0, cx=None, cy=None, ang=None, length=None):
    """one bone (shaft + knobbed ends) as an RGBA layer with a dark outline"""
    length = length or rng.uniform(26, 44) * scale
    ang = rng.uniform(0, math.pi) if ang is None else ang
    m = length / 2 + 12 * scale
    cx = rng.uniform(m, R - m) if cx is None else cx
    cy = rng.uniform(m, R - m) if cy is None else cy
    ux, uy = math.cos(ang), math.sin(ang)
    ax, ay = cx - ux * length / 2, cy - uy * length / 2
    bx, by = cx + ux * length / 2, cy + uy * length / 2
    r = 3.6 * scale
    d, t = L.seg_dist(X, Y, ax, ay, bx, by)
    field = r - d
    px, py = -uy, ux
    for ex, ey in ((ax, ay), (bx, by)):
        for s in (-1, 1):
            k = 4.8 * scale
            dd = np.hypot(X - (ex + px * s * 3.2 * scale), Y - (ey + py * s * 3.2 * scale))
            field = np.maximum(field, k - dd)
    body = field > 0
    h = np.sqrt(np.clip(field, 0, None)) * 2.4
    tone = 0.55 + 0.25 * L.sstep(0, 6, field)
    alb = L.ramp(tone * 0.9, ['3d372c', '6e6655', '9a917a', 'bdb39a'])
    rgb = L.shade(alb, h, False, strength=1.0, ambient=0.5, diffuse=0.85)
    outline = (field > -2.6 * scale) & ~body
    rgb = np.where(outline[..., None], L.hexcol('100c0a')[None, None, :], rgb)
    return L.rgba(rgb, (body | outline).astype(np.float32))


def skull_sprite(X, Y, cx, cy, scale=1.0):
    rx, ry = 13 * scale, 11 * scale
    e = ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2
    jaw = ((X - cx) / (rx * 0.62)) ** 2 + ((Y - cy - ry * 0.75) / (ry * 0.45)) ** 2
    body = (e < 1) | (jaw < 1)
    h = np.sqrt(np.clip(1 - np.minimum(e, jaw), 0, 1)) * 10 * scale
    alb = L.ramp(np.clip(0.75 - 0.3 * e, 0, 1), ['4a4436', '7a7260', 'a59c84', 'c4bba2'])
    rgb = L.shade(alb, h, False, strength=1.0, ambient=0.5, diffuse=0.85)
    holes = np.zeros(X.shape, bool)
    for s in (-1, 1):
        holes |= ((X - (cx + s * rx * 0.42)) / (rx * 0.27)) ** 2 + ((Y - (cy + ry * 0.08)) / (ry * 0.3)) ** 2 < 1
    holes |= ((X - cx) / (rx * 0.12)) ** 2 + ((Y - (cy + ry * 0.55)) / (ry * 0.18)) ** 2 < 1
    rgb = np.where((holes & body)[..., None], L.hexcol('0c0907')[None, None, :], rgb)
    outline = L.dilate(body, int(round(2.6 * scale))) & ~body
    rgb = np.where(outline[..., None], L.hexcol('100c0a')[None, None, :], rgb)
    return L.rgba(rgb, (body | outline).astype(np.float32))


def flagstones(seed, Y=None, X=None):
    """ruined dark stone floor: rows of flagstones, some cracked or missing"""
    if Y is None:
        Y, X = L.grid(T, T)
    rng = np.random.default_rng(seed)
    rows = 8
    rh = T / rows
    row = (np.floor(Y / rh).astype(np.int64)) % rows
    ry = Y - np.floor(Y / rh) * rh
    sid = np.zeros(X.shape, np.int64)
    dxe = np.zeros(X.shape, np.float32)
    for r_ in range(rows):
        widths = []
        while sum(widths) < T:
            widths.append(int(rng.choice([48, 64, 64, 80, 96])))
        widths[-1] -= sum(widths) - T
        if widths[-1] < 32:
            widths[-2] += widths[-1]; widths.pop()
        cum = np.cumsum([0] + widths)
        off = rng.uniform(0, T)
        sel = row == r_
        xr = (X[sel] - off) % T
        k = np.searchsorted(cum, xr, side='right') - 1
        sid[sel] = r_ * 100 + k
        dxe[sel] = np.minimum(xr - cum[k], cum[k + 1] - xr)
    dye = np.minimum(ry, rh - ry)
    edge = np.minimum(dxe, dye)
    chip = L.FBM(seed + 3, 32, T, 2)(X, Y)
    edge = edge - 3.5 * chip
    mortar = edge < 2.2
    srng = np.random.default_rng(seed + 1)
    table = srng.random((rows * 100 + 100, 4)).astype(np.float32)
    sv = table[sid]
    missing = sv[..., 1] < 0.07
    cracked = sv[..., 2] < 0.3
    big = L.FBM(seed + 4, 8, T, 3)(X, Y)
    fine = L.FBM(seed + 5, 32, T, 3)(X, Y)
    crk = L.ridged(L.FBM(seed + 6, 12, T, 3)(X, Y))
    crack = cracked & (crk > 0.93)
    bevel = L.sstep(0, 10, edge)
    h = 6 * bevel + 2.5 * fine + 3 * (sv[..., 3] - 0.5) - 4 * crack
    tone = 0.45 * sv[..., 0] + 0.35 * big + 0.2 * fine
    alb = L.ramp(tone, ['1c1a20', '27242b', '332f37', '3f3a44', '4b4551'])
    alb = alb * (1 - 0.6 * crack[..., None])
    dirt, dh = ash_soil(seed + 40, Y, X)
    gapmoss = (L.FBM(seed + 7, 8, T, 2)(X, Y) > 0.6)
    mcol = L.ramp(fine, ['0c140e', '15241a', '1f3222'])
    gapcol = np.where(gapmoss[..., None], mcol, L.ramp(fine, ['09080b', '110f13', '19161b']))
    low = mortar | missing
    h = np.where(low, -6 + (dh * 0.15 if True else 0), h)
    alb = np.where(mortar[..., None], gapcol, alb)
    out = L.shade(alb, h, True, strength=1.0, ambient=0.5, diffuse=0.8, spec=0.12, shininess=20)
    dirt = dirt * 0.62
    out = np.where((missing & ~mortar)[..., None], dirt, out)
    return out, h


def cursed_pool(seed, phase, phases, Y=None, X=None):
    """obsidian floor with a cursed puddle in every tile; the liquid swirls (loops over `phases`)"""
    if Y is None:
        Y, X = L.grid(T, T)
    base, h = obsidian(seed, 0, Y, X)
    lx = X % R - R / 2; ly = Y % R - R / 2
    tix = (X // R).astype(np.int64); tiy = (Y // R).astype(np.int64)
    jit = np.random.default_rng(seed + 50).uniform(-8, 8, (4, 4, 2)).astype(np.float32)
    lx = lx - jit[tiy, tix, 0]; ly = ly - jit[tiy, tix, 1]
    ang = np.arctan2(ly, lx)
    rn = L.PNoise(seed + 51, 8, 2 * math.pi)
    rad = R * 0.4 * (0.86 + 0.26 * rn(ang + math.pi, (tiy * 4 + tix) * 1.0))
    dist = np.hypot(lx, ly * 1.12)
    liquid = dist < rad
    rim = (dist < rad + 9) & ~liquid
    a = 2 * math.pi * phase / phases
    sw = L.FBM(seed + 52, 6, T, 4)
    ox, oy = 40 * math.cos(a), 40 * math.sin(a)
    rot = sw(X + ox + 18 * np.sin(Y / 23.0), Y + oy)
    swirl = sw(X - oy * 0.7 + rot * 30, Y + ox * 0.7)
    depth = np.clip(dist / np.maximum(rad, 1), 0, 1)
    col = L.ramp(0.55 * swirl + 0.45 * (1 - depth) * 0.6, ['06030a', '12081c', '220e36', '3a1858', '5c2a7c'])
    glint = np.clip((L.ridged(swirl) - 0.86) / 0.14, 0, 1)
    col = col + glint[..., None] * L.hexcol('2fc2b0')[None, None, :] * 1.0 + (1 - depth[..., None]) * L.hexcol('2a0f40')[None, None, :]
    sheen = np.exp(-(((lx + rad * 0.35) / (rad * 0.35)) ** 2 + ((ly + rad * 0.4) / (rad * 0.18)) ** 2))
    col = col + sheen[..., None] * 0.18
    rimh = h + 6 * np.sqrt(np.clip(1 - ((dist - rad - 4.5) / 4.5) ** 2, 0, 1))
    rimc = L.shade(L.ramp(L.FBM(seed + 53, 32, T, 2)(X, Y), ['120c10', '2a1e24', '3e2c34']), rimh, True, ambient=0.5)
    out = np.where(liquid[..., None], np.clip(col, 0, 1), np.where(rim[..., None], rimc, base))
    edge = liquid & ~L.erode_dist(liquid, 3).astype(bool)
    out = np.where(edge[..., None], L.hexcol('050307')[None, None, :], out)
    return out, h


# =================================================================================================== borders
def edge_depth(seed, coord, side):
    """ragged edge depth (hi-res px) along a world coordinate, periodic in T"""
    n = L.FBM(seed * 7 + side, 8, T, 4)
    d = R * 0.32 + (n(coord, np.full_like(coord, 17.0 * side)) - 0.5) * R * 0.95
    return np.clip(d, R * 0.12, R * 0.56)


BORDER_PIECES = ['n', 'e', 's', 'w', 'outer_ne', 'outer_nw', 'outer_se', 'outer_sw',
                 'inner_ne', 'inner_nw', 'inner_se', 'inner_sw']
PIECE_TEXT = {'n': 'north edge', 'e': 'east edge', 's': 'south edge', 'w': 'west edge',
              'outer_ne': 'outer corner north-east', 'outer_nw': 'outer corner north-west',
              'outer_se': 'outer corner south-east', 'outer_sw': 'outer corner south-west',
              'inner_ne': 'inner corner north-east', 'inner_nw': 'inner corner north-west',
              'inner_se': 'inner corner south-east', 'inner_sw': 'inner corner south-west'}


def border_mask(seed, piece, px, py, pad):
    """coverage of a border piece on the tile at pattern (px, py), with `pad` px of the neighbours around it.
    The piece is named by where the dark ground lies: 'n' = the dark ground is north of this tile (its edge runs along
    the top); 'outer_nw' = dark only on the diagonal north-west tile; 'inner_nw' = dark north and west."""
    n = R + 2 * pad
    ly, lx = L.grid(n, n, -pad, -pad)
    X = px * R + lx; Y = py * R + ly
    jit = (L.PNoise(seed * 7 + 9, 40, T)(X % T, Y % T) - 0.5) * R * 0.12
    dn = edge_depth(seed, X % T, 1) + jit
    ds = edge_depth(seed, X % T, 2) + jit
    dw = edge_depth(seed, Y % T, 3) + jit
    de = edge_depth(seed, Y % T, 4) + jit
    N = ly < dn
    S = (R - ly) < ds
    W = lx < dw
    E = (R - lx) < de

    def outer(fx, fy, cx, cy):
        # corner at (cx, cy); fx / fy distances from the two edges, scaled by the edge depths
        ax = np.where(cx == 0, lx, R - lx); ay = np.where(cy == 0, ly, R - ly)
        dX = dw if cx == 0 else de
        dY = dn if cy == 0 else ds
        inner = ((np.clip(ax, 0, None) / dX) ** 2.2 + (np.clip(ay, 0, None) / dY) ** 2.2) < 1
        outside_x = ax < 0; outside_y = ay < 0
        return np.where(outside_x & outside_y, True,
                        np.where(outside_y, ax < dX, np.where(outside_x, ay < dY, inner)))
    if piece == 'n':
        return N
    if piece == 's':
        return S
    if piece == 'w':
        return W
    if piece == 'e':
        return E
    if piece == 'outer_nw':
        return outer(None, None, 0, 0)
    if piece == 'outer_ne':
        return outer(None, None, R, 0)
    if piece == 'outer_sw':
        return outer(None, None, 0, R)
    if piece == 'outer_se':
        return outer(None, None, R, R)
    if piece == 'inner_nw':
        return N | W
    if piece == 'inner_ne':
        return N | E
    if piece == 'inner_sw':
        return S | W
    if piece == 'inner_se':
        return S | E
    raise ValueError(piece)


def border_layers(seed, piece, px, py):
    """hi-res (R x R): coverage, darkening factor (1 = plain ground), outline mask"""
    pad = 16
    m = border_mask(seed, piece, px, py, pad)
    din = L.erode_dist(m, 14)
    sl = (slice(pad, pad + R), slice(pad, pad + R))
    m, din = m[sl], din[sl]
    k = 0.55 + 0.45 * L.sstep(3, 14, din)
    outline = m & (din <= 4)
    return m, k.astype(np.float32), outline


# =================================================================================================== walls (cubes)
def masonry(u, v, seed, period, course=32, brick=64, mortar=2.6, ruined=False):
    """brick pattern on a face: u along the face (world, periodic `period`), v up from the ground. Returns
    (height, tone, mortar mask, brick id)"""
    c = np.floor(v / course).astype(np.int64)
    off = (c % 2) * (brick / 2)
    uu = (u + off) % period
    b = np.floor(uu / brick).astype(np.int64)
    du = np.minimum(uu - b * brick, (b + 1) * brick - uu)
    dv = np.minimum(v - c * course, (c + 1) * course - v)
    chip = L.FBM(seed + 3, 16, period, 2)(u % period, v)
    e = np.minimum(du, dv) - 2.5 * chip
    tab = np.random.default_rng(seed).random((64, 64)).astype(np.float32)
    bid = (c % 64, (b + c * 3) % 64)
    tv = tab[bid]
    mort = e < mortar
    h = 5 * L.sstep(0, 7, e) + 2 * L.FBM(seed + 4, 16, period, 3)(u % period, v)
    tone = 0.55 * tv + 0.45 * L.FBM(seed + 5, 8, period, 3)(u % period, v)
    hole = np.zeros(u.shape, bool)
    if ruined:
        hole = (tab[(bid[0] * 3 + 1) % 64, (bid[1] * 5 + 2) % 64] < 0.12) & ~mort
    return h, tone, mort, hole


def wall_cube(seed, style, px, py):
    """2x2 canvas: a block one tile high, footprint = bottom-right tile, top face shifted one tile up-left
    (the stock 3/4 projection).  Faces: top, south, east."""
    n = 2 * R
    Y, X = L.grid(n, n)
    top = (X < R) & (Y < R)
    south = (Y >= R) & (X >= Y - R) & (X < Y)
    east = (X >= R) & (Y >= X - R) & (Y <= X)
    sv = 2 * R - Y; su = X - R + sv            # south face: u along x, v up
    ev = 2 * R - X; eu = Y - R + ev            # east face: u along y, v up
    P = 2 * R
    rgb = np.zeros((n, n, 3), np.float32)
    pal = {'masonry': ['18161b', '232027', '2e2a33', '3a3540', '47414e'],
           'ruined': ['1a181b', '252126', '302b31', '3c363d', '48414a'],
           'obsidian': ['0d090b', '1a1013', '28171c', '361e24', '46262d']}[style]
    face_mult = {'top': 1.0, 'south': 1.0, 'east': 0.74}
    for face, mask, u, v, uoff in (('south', south, su, sv, px * R), ('east', east, eu, ev, py * R)):
        if not mask.any():
            continue
        uw = u + uoff
        if style == 'obsidian':
            V = L.Voronoi(seed + 30, 6, P, 0.9)
            f1, f2, idn, _, _ = V(uw % P, v * 1.0 + 0.0)
            cr = 1 - L.sstep(0.8, 4.5, f2 - f1)
            tone = 0.5 * V.val.reshape(-1)[idn] + 0.5 * L.FBM(seed + 31, 8, P, 3)(uw % P, v)
            h = 4 * L.sstep(0, 12, f2 - f1) + 3 * L.FBM(seed + 32, 16, P, 3)(uw % P, v)
            mort = cr > 0.5
            hole = np.zeros(u.shape, bool)
        else:
            h, tone, mort, hole = masonry(uw, v, seed + (0 if face == 'south' else 7), P, ruined=(style == 'ruined'))
        alb = L.ramp(tone, pal) * face_mult[face]
        alb = np.where(mort[..., None], L.hexcol('09080b')[None, None, :], alb)
        alb = np.where(hole[..., None], L.hexcol('050406')[None, None, :], alb)
        if style == 'obsidian':
            vein = (1 - L.sstep(0.0, 2.2, (f2 - f1))) * (L.FBM(seed + 33, 6, P, 2)(uw % P, v) > 0.62)
            alb = alb + vein[..., None] * L.hexcol('8a1608')[None, None, :]
        if style == 'ruined':
            moss = (v < 26 + 18 * L.FBM(seed + 40, 8, P, 2)(uw % P, v)) & (L.FBM(seed + 41, 8, P, 2)(uw % P, v) > 0.45)
            alb = np.where((moss & ~mort)[..., None], L.ramp(tone, ['0e1810', '172619', '223424']), alb)
        sh = L.shade(alb, h, False, strength=0.8, ambient=0.6, diffuse=0.6, spec=0.18 if style == 'obsidian' else 0.0)
        rgb = np.where(mask[..., None], sh, rgb)
    # top face: capstones / raw rock, world-continuous
    TX = X + px * R; TY = Y + py * R
    V = L.Voronoi(seed + 61, 4, P, 0.6)
    f1, f2, idn, _, _ = V(TX % P, TY % P)
    tone = 0.6 * V.val.reshape(-1)[idn] + 0.4 * L.FBM(seed + 62, 16, P, 3)(TX % P, TY % P)
    th = 5 * L.sstep(0, 10, f2 - f1) + 2 * L.FBM(seed + 63, 32, P, 2)(TX % P, TY % P)
    alb = L.ramp(tone, pal) * 1.12
    alb = np.where(((f2 - f1) < 2.4)[..., None], L.hexcol('0a090c')[None, None, :], alb)
    topc = L.shade(alb, th, False, strength=0.8, ambient=0.55, diffuse=0.75,
                   spec=0.2 if style == 'obsidian' else 0.0)
    rgb = np.where(top[..., None], topc, rgb)
    body = top | south | east
    if style == 'ruined':
        # broken top edge: notches bitten out of the top face's south / east rims
        bite = L.FBM(seed + 70, 6, P, 3)
        nb = (top & ((Y > R - 22 * bite(TX % P, TY % P) ** 2 * 1.6) | (X > R - 22 * bite(TY % P + 55, TX % P) ** 2 * 1.6)))
        nb &= (L.FBM(seed + 71, 4, P, 2)(TX % P, TY % P) > 0.5)
        rgb = np.where(nb[..., None], rgb * 0.45, rgb)
    # edges: light rim on the top face's south / east borders, dark seam between south and east faces
    rim = top & ((Y > R - 4) | (X > R - 4))
    rgb = np.where(rim[..., None], np.clip(rgb * 1.45 + 0.03, 0, 1), rgb)
    seam = (south | east) & (np.abs(X - Y) < 2.2) & (Y > R)
    rgb = np.where(seam[..., None], L.hexcol('060507')[None, None, :], rgb)
    outline = L.dilate(body, 4) & ~body
    rgb = np.where(outline[..., None], L.hexcol('050406')[None, None, :], rgb)
    return L.rgba(rgb, (body | outline).astype(np.float32))


# =================================================================================================== objects
def outline_layer(img, width=4, col='070506'):
    body = img[..., 3] > 0.5
    ol = L.dilate(body, width) & ~body
    out = img.copy()
    out[ol, :3] = L.hexcol(col)
    out[ol, 3] = 1
    return out


def draw_segments(n_h, n_w, segs, pal, seed, bark=True):
    """capsules (ax, ay, bx, by, r0, r1) drawn in order (later ones on top) with cylinder lighting and bark streaks"""
    Y, X = L.grid(n_h, n_w)
    img = np.zeros((n_h, n_w, 4), np.float32)
    streak = L.PNoise(seed + 5, 32, 256)
    for (ax, ay, bx, by, r0, r1) in segs:
        x0 = int(max(0, min(ax, bx) - max(r0, r1) - 2)); x1 = int(min(n_w, max(ax, bx) + max(r0, r1) + 3))
        y0 = int(max(0, min(ay, by) - max(r0, r1) - 2)); y1 = int(min(n_h, max(ay, by) + max(r0, r1) + 3))
        if x1 <= x0 or y1 <= y0:
            continue
        sx, sy = X[y0:y1, x0:x1], Y[y0:y1, x0:x1]
        d, t = L.seg_dist(sx, sy, ax, ay, bx, by)
        r = r0 + (r1 - r0) * t
        inside = d < r
        if not inside.any():
            continue
        vx, vy = bx - ax, by - ay
        ln = math.hypot(vx, vy) + 1e-6
        nx_, ny_ = -vy / ln, vx / ln
        side = ((sx - ax) * nx_ + (sy - ay) * ny_) / np.maximum(r, 0.5)
        side = np.clip(side, -1, 1)
        nz = np.sqrt(1 - side ** 2)
        lam = np.clip(side * (nx_ * L.LIGHT[0] + ny_ * L.LIGHT[1]) + nz * L.LIGHT[2], 0, 1)
        along = ((sx - ax) * vx + (sy - ay) * vy) / ln
        st = streak(side * 30 + 100, along * 0.25) if bark else 0.5
        tone = np.clip(0.25 + 0.6 * lam + 0.25 * (st - 0.5), 0, 1)
        col = L.ramp(tone, pal)
        blk = img[y0:y1, x0:x1]
        blk[inside, :3] = col[inside]
        blk[inside, 3] = 1
    return img


def twisted_tree(seed, w, h, base, height, spread, depth=5, trunk_r=12.0):
    """recursive branching with a wandering direction; branches that would leave the canvas stop"""
    rng = random.Random(seed)
    segs = []

    def grow(x, y, ang, length, r, d):
        steps = 4
        for i in range(steps):
            ang += rng.uniform(-0.3, 0.3) + 0.04 * (-math.pi / 2 - ang)
            nx = x + math.cos(ang) * length / steps
            ny = y + math.sin(ang) * length / steps
            nr = max(2.4, r * 0.95)
            if not (5 < nx < w - 5 and 5 < ny < h - 5):
                return
            segs.append((x, y, nx, ny, r, nr))
            x, y, r = nx, ny, nr
        if d <= 0:
            return
        k = 2 if rng.random() < 0.5 else 3
        for j in range(k):
            a = ang + (j - (k - 1) / 2) * spread + rng.uniform(-0.18, 0.18)
            a = min(max(a, -math.pi + 0.15), -0.15)
            grow(x, y, a, length * rng.uniform(0.7, 0.86), max(2.4, r * rng.uniform(0.58, 0.68)), d - 1)

    bx, by = base
    for i in range(5):   # gnarled roots: short ones to the right, long ones sprawling left along the ground
        left = i % 2 == 0
        a = rng.uniform(math.pi - 0.35, math.pi - 0.05) if left else rng.uniform(0.05, 0.45)
        L_ = (rng.uniform(0.32, 0.5) * w if left else rng.uniform(22, 34) * trunk_r / 14)
        x0, y0, r0 = bx, by - 4, trunk_r * 0.8
        for k in range(3):
            a += rng.uniform(-0.25, 0.25)
            x1 = min(max(x0 + math.cos(a) * L_ / 3, 6), w - 6); y1 = min(max(y0 + math.sin(a) * L_ / 3 * 0.5, 6), h - 6)
            segs.append((x0, y0, x1, y1, r0, max(2.6, r0 * 0.62)))
            x0, y0, r0 = x1, y1, max(2.6, r0 * 0.62)
    grow(bx, by, -math.pi / 2 - 0.3 + rng.uniform(-0.1, 0.1), height, trunk_r, depth)
    segs.sort(key=lambda s: s[4])     # thick parts last: the trunk overlaps its twigs
    return segs


def tree_img(seed, size, depth, height, trunk_r, spread):
    w = h = size * R
    base = (w - R / 2 - 2, h - R * 0.2)
    segs = twisted_tree(seed, w, h, base, height, spread, depth, trunk_r)
    img = draw_segments(h, w, segs, ['0d0a09', '1c1613', '2e2520', '41352e', '56483f'], seed)
    return outline_layer(img, 4)


def dome_field(X, Y, cx, cy, rx, ry, seed, rough=0.18):
    ang = np.arctan2(Y - cy, X - cx)
    rn = L.PNoise(seed, 7, 2 * math.pi)(ang + math.pi, np.full_like(ang, seed % 13))
    k = 1 + rough * (rn - 0.5) * 2
    e = ((X - cx) / (rx * k)) ** 2 + ((Y - cy) / (ry * k)) ** 2
    return np.sqrt(np.clip(1 - e, 0, 1))


def rock_img(seed, wt, ht, lumps, pal=None, veins=False):
    w, h = wt * R, ht * R
    Y, X = L.grid(h, w)
    hgt = np.zeros((h, w), np.float32)
    for (cx, cy, rx, ry, hh) in lumps:
        hgt = np.maximum(hgt, dome_field(X, Y, cx, cy, rx, ry, seed + int(cx), 0.34) ** 0.8 * hh)
        seed += 1
    body = hgt > 0
    V = L.Voronoi(seed + 3, 10, 256, 0.9)
    f1, f2, idn, _, _ = V(X % 256, Y % 256)
    facet = V.val.reshape(-1)[idn]
    hgt2 = hgt + 14 * facet * body + 2 * L.FBM(seed + 4, 16, 256, 3)(X % 256, Y % 256) * body
    tone = 0.45 + 0.3 * facet + 0.25 * L.FBM(seed + 5, 8, 256, 2)(X % 256, Y % 256)
    alb = L.ramp(tone, pal or ['141012', '211b1d', '2e2629', '3d3236', '4d4045'])
    crease = ((f2 - f1) < 1.8) & body
    alb = np.where(crease[..., None], alb * 0.55, alb)
    rgb = L.shade(alb, hgt2, False, strength=1.0, ambient=0.42, diffuse=0.9, spec=0.12, shininess=18)
    if veins:
        vein = ((f2 - f1) < 1.6) & body & (L.FBM(seed + 6, 6, 256, 2)(X % 256, Y % 256) > 0.68)
        rgb = np.where(vein[..., None], rgb * 0.4 + L.hexcol('6a1408')[None, None, :], rgb)
    return outline_layer(L.rgba(rgb, body.astype(np.float32)), 4)


def pillar_img(seed, broken_at, stump=False):
    """1x2 (or 1x1 stump) ruined column: plinth, fluted shaft, jagged break"""
    ht = 1 if stump else 2
    w, h = R, ht * R
    Y, X = L.grid(h, w)
    rng = random.Random(seed)
    cx = R * 0.5
    base_y = h - R * 0.16
    pal = ['121016', '1d1a22', '2a2630', '38333f', '48424f']
    img = np.zeros((h, w, 4), np.float32)
    # plinth: front box + top ellipse
    pw, ph_ = R * 0.36, R * 0.15
    front = (np.abs(X - cx) < pw) & (Y > base_y - ph_) & (Y < base_y)
    topel = ((X - cx) / pw) ** 2 + ((Y - (base_y - ph_)) / (pw * 0.4)) ** 2 < 1
    fn = L.FBM(seed + 1, 16, 256, 3)(X, Y)
    c_front = L.ramp(0.35 + 0.3 * fn, pal) * 0.8
    c_top = L.ramp(0.55 + 0.3 * fn, pal)
    img[front, :3] = c_front[front]; img[front, 3] = 1
    img[topel, :3] = c_top[topel]; img[topel, 3] = 1
    # shaft
    rs = R * 0.21
    top_y = R * broken_at
    brk = top_y + (L.PNoise(seed + 2, 10, R)(X, np.zeros_like(X)) - 0.5) * 26 + (X - cx) * 0.25
    shaft = (np.abs(X - cx) < rs) & (Y < base_y - ph_ * 0.9) & (Y > brk)
    side = np.clip((X - cx) / rs, -1, 1)
    nz = np.sqrt(1 - side ** 2)
    lam = np.clip(side * L.LIGHT[0] + nz * L.LIGHT[2] + 0.12, 0, 1)
    flutes = 0.5 + 0.5 * np.cos(np.arcsin(side) * 7)
    tone = 0.18 + 0.62 * lam - 0.12 * (1 - flutes) + 0.15 * (fn - 0.5)
    crack = L.ridged(L.FBM(seed + 3, 8, 256, 3)(X * 0.5, Y)) > 0.94
    c_sh = L.ramp(np.clip(tone, 0, 1), pal)
    c_sh = np.where(crack[..., None], c_sh * 0.45, c_sh)
    img[shaft, :3] = c_sh[shaft]; img[shaft, 3] = 1
    # broken top face
    cap = (np.abs(X - cx) < rs) & (Y <= brk + 9) & (Y > brk - 2) & shaft
    img[cap, :3] = L.ramp(0.6 + 0.3 * fn, pal)[cap] * 1.1
    # moss at the base
    moss = (front | (shaft & (Y > base_y - ph_ - R * 0.18))) & (L.FBM(seed + 4, 12, 256, 2)(X, Y) > 0.55)
    img[moss, :3] = L.ramp(fn, ['0c160e', '162619', '213424'])[moss]
    # rubble at the foot
    for i in range(5 if stump else 3):
        rx_ = cx + rng.uniform(-R * 0.42, R * 0.42); ry_ = base_y + rng.uniform(-4, 10)
        rr = rng.uniform(5, 9)
        d = ((X - rx_) / rr) ** 2 + ((Y - ry_) / (rr * 0.75)) ** 2
        st = d < 1
        sh = L.ramp(np.clip(0.75 - 0.5 * ((X - rx_ + Y - ry_) / (2 * rr)), 0, 1), pal)
        img[st, :3] = sh[st]; img[st, 3] = 1
    return outline_layer(img, 4)


def flame_field(X, Y, cx, base_y, width, height, phase, phases, seed):
    a = phase / phases
    n = L.FBM(seed, 4, 128, 4)
    yy = (Y - base_y) / height        # 0 at the base, -1 at the top
    taper = np.clip(1 + yy, 0, 1) ** 0.8
    wob = (n(X * 0.9 + 37, Y * 0.6 + 128 * a) - 0.5) * 0.9
    dx = (X - cx) / (width * (0.25 + 0.75 * taper) + 1e-3) + wob * (-yy)
    core = np.clip(1 - dx ** 2, 0, 1) * L.sstep(-1.05, -0.55, yy) * L.sstep(0.12, -0.02, yy)
    turb = n(X * 1.6, Y * 1.1 + 256 * a)
    tongues = n(X * 2.6 + 91, Y * 0.5 + 384 * a)
    f = core * (0.35 + 0.9 * turb) * (0.6 + 0.8 * tongues) - 0.35 * np.clip(-yy, 0, 1) ** 1.5
    return np.clip(f * (yy < 0.1), 0, 1)


FIRE = [(0, '000000'), (0.18, '4a0a04'), (0.38, '9c1c06'), (0.58, 'dc4a0e'), (0.78, 'f8952a'), (0.92, 'ffd779'),
        (1, 'fff3cc')]


def brazier_img(seed, phase, phases):
    w, h = R, 2 * R
    Y, X = L.grid(h, w)
    cx = R * 0.5
    img = np.zeros((h, w, 4), np.float32)
    iron = ['0b0a0c', '17151a', '25222a', '35313b', '4a4552']
    bowl_y = R * 1.28
    for lx_ in (-0.3, 0.0, 0.3):
        segs = [(cx + lx_ * R * 0.6, bowl_y + 6, cx + lx_ * R * 1.05, h - R * 0.12, 4.5, 3.6)]
        img = L.over(img, draw_segments(h, w, segs, iron, seed, bark=False))
    bw, bh = R * 0.36, R * 0.2
    bowl = (((X - cx) / bw) ** 2 + ((Y - bowl_y) / bh) ** 2 < 1) & (Y > bowl_y - 2)
    side = np.clip((X - cx) / bw, -1, 1)
    tone = 0.3 + 0.5 * np.clip(-side * 0.6 + 0.5, 0, 1)
    c = L.ramp(tone, iron)
    img[bowl, :3] = c[bowl]; img[bowl, 3] = 1
    rim = ((X - cx) / bw) ** 2 + ((Y - bowl_y) / (bh * 0.32)) ** 2
    coals = rim < 1
    cn = L.FBM(seed + 3, 8, 128, 3)(X, Y + 40 * phase / phases)
    cc = L.ramp(0.35 + 0.6 * cn, FIRE)
    img[coals, :3] = cc[coals]; img[coals, 3] = 1
    rimline = (rim >= 1) & (rim < 1.5) & (Y < bowl_y + 3)
    img[rimline, :3] = L.hexcol('4e4858'); img[rimline, 3] = 1
    f = flame_field(X, Y, cx, bowl_y - 2, bw * 0.9, R * 0.8, phase, phases, seed + 7)
    fl = f > 0.2
    fc = L.ramp(f, FIRE)
    img[fl, :3] = fc[fl]; img[fl, 3] = 1
    return outline_layer(img, 3)


def torch_img(seed, phase, phases):
    w, h = R, 2 * R
    Y, X = L.grid(h, w)
    cx = R * 0.5
    wood = ['0c0807', '1a120e', '2b1f18', '3d2d22', '503d2f']
    segs = [(cx, h - R * 0.3, cx + dx, h - R * 0.06, 4.0, 3.2) for dx in (-R * 0.36, R * 0.36)]
    segs += [(cx, h - R * 0.3, cx - R * 0.08, h - R * 0.03, 4.0, 3.2), (cx, h - R * 0.12, cx, R * 0.98, 6.0, 5.0)]
    img = draw_segments(h, w, segs, wood, seed)
    head = (np.abs(X - cx) < 11) & (Y > R * 0.86) & (Y < R * 1.02)
    img[head, :3] = L.ramp(0.3 + 0.4 * np.clip(-(X - cx) / 11 * 0.5 + 0.5, 0, 1), ['0b0a0c', '211e25', '3a3541'])[head]
    img[head, 3] = 1
    f = flame_field(X, Y, cx, R * 0.88, 15, R * 0.6, phase, phases, seed + 7)
    fl = f > 0.2
    img[fl, :3] = L.ramp(f, FIRE)[fl]; img[fl, 3] = 1
    return outline_layer(img, 3)


def fungus_img(seed, hue, phase, phases):
    w = h = R
    Y, X = L.grid(h, w)
    rng = random.Random(seed)
    pals = {'purple': (['1a0f22', '3b1a52', '6a2c8e', 'a24fd0', 'e2a8ff'], '1c1220'),
            'teal': (['08181a', '0f3a3a', '1a6a66', '30b0a0', 'a8fff0'], '0f1a1a')}
    capal, stemc = pals[hue]
    pulse = 0.85 + 0.2 * math.sin(2 * math.pi * phase / phases)
    img = np.zeros((h, w, 4), np.float32)
    caps = []
    for i in range(5):
        caps.append((rng.uniform(R * 0.24, R * 0.76), rng.uniform(R * 0.42, R * 0.84), rng.uniform(13, 26)))
    caps.sort(key=lambda c: c[1])
    for (fx, fy, s) in caps:
        stem = (np.abs(X - fx) < s * 0.28) & (Y > fy - s * 0.2) & (Y < fy + s * 0.9)
        st = L.ramp(np.clip(0.5 - (X - fx) / (s * 0.6), 0, 1), [stemc, '3a3438', '6a6268'])
        img[stem, :3] = st[stem]; img[stem, 3] = 1
        e = ((X - fx) / s) ** 2 + ((Y - fy) / (s * 0.55)) ** 2
        cap = (e < 1) & (Y < fy + s * 0.12)
        light = np.clip(1 - e, 0, 1)
        tone = np.clip(0.25 + 0.55 * light + 0.2 * np.clip(-(X - fx) / s, -1, 1), 0, 1) * pulse
        cc = L.ramp(np.clip(tone, 0, 1), capal)
        spots = L.PNoise(seed + int(fx), 6, 64)(X, Y * 1.6) > 0.72
        cc = np.where(spots[..., None], np.clip(cc * 1.5 + 0.12, 0, 1), cc)
        img[cap, :3] = cc[cap]; img[cap, 3] = 1
    return outline_layer(img, 3)


def crystal_img(seed):
    w = h = R
    Y, X = L.grid(h, w)
    rng = random.Random(seed)
    img = np.zeros((h, w, 4), np.float32)
    shards = []
    for i in range(6):
        bx = rng.uniform(R * 0.25, R * 0.75); by = rng.uniform(R * 0.68, R * 0.88)
        ang = -math.pi / 2 + rng.uniform(-0.65, 0.65)
        ln = rng.uniform(R * 0.32, R * 0.6); wd = rng.uniform(7, 13)
        shards.append((by, bx, ang, ln, wd))
    shards.sort()
    for (by, bx, ang, ln, wd) in shards:
        ux, uy = math.cos(ang), math.sin(ang)
        px_, py_ = -uy, ux
        tipx, tipy = bx + ux * ln, by + uy * ln
        pts = [(bx + px_ * wd, by + py_ * wd), (bx + ux * ln * 0.78 + px_ * wd * 0.7, by + uy * ln * 0.78 + py_ * wd * 0.7),
               (tipx, tipy), (bx + ux * ln * 0.78 - px_ * wd * 0.7, by + uy * ln * 0.78 - py_ * wd * 0.7),
               (bx - px_ * wd, by - py_ * wd)]
        m = L.poly_mask(X, Y, pts)
        side = ((X - bx) * px_ + (Y - by) * py_)
        lit = side < 0
        t = np.clip(((X - bx) * ux + (Y - by) * uy) / ln, 0, 1)
        base = np.where(lit, 0.62, 0.3) + 0.25 * t
        col = L.ramp(np.clip(base, 0, 1), ['0b0608', '1e0c10', '3a1018', '6a1620', 'b02a24'])
        core = np.abs(side) < 1.8
        col = np.where(core[..., None], L.hexcol('ff6a3a')[None, None, :] * 0.9, col)
        img[m, :3] = col[m]; img[m, 3] = 1
    return outline_layer(img, 3)


def rubble_img(seed, bones=False):
    w = h = R
    Y, X = L.grid(h, w)
    rng = np.random.default_rng(seed)
    img = np.zeros((h, w, 4), np.float32)
    if bones:
        for i in range(5):
            img = L.over(img, bone_sprite(X, Y, rng, 1.1, cx=rng.uniform(34, 94), cy=rng.uniform(52, 100)))
        img = L.over(img, skull_sprite(X, Y, rng.uniform(52, 76), rng.uniform(56, 72), 1.25))
        return img
    stones = sorted([(rng.uniform(R * 0.5, R * 0.9), rng.uniform(R * 0.18, R * 0.82), rng.uniform(6, 14))
                     for _ in range(11)])
    for (sy, sx, s) in stones:
        d = dome_field(X, Y, sx, sy, s, s * 0.78, int(sx * 10), 0.3)
        body = d > 0
        hh = d * s * 0.9
        alb = L.ramp(0.4 + 0.3 * L.PNoise(int(sy), 8, 128)(X, Y), ['131116', '221f26', '332f38', '45404b'])
        rgb = L.shade(alb, hh, False, ambient=0.4, diffuse=0.9)
        lay = L.rgba(rgb, body.astype(np.float32))
        img = L.over(img, outline_layer(lay, 3))
    return img


# =================================================================================================== the set
# small loose pieces (stones, bones): softer volume light and no gloss, so they stay matte floor clutter
SMALL_RIM = dict(form=0.6, gloss=0.0, hl=0.45, sh=0.55, width=6)

def ground(key, name, fn, seed, speed, minimap, phases=1, ms=0, light=None, walk=True, border=False):
    return dict(key=key, name=name, kind='ground', w=1, h=1, px=4, py=4, phases=phases, ms=ms, seed=seed, fn=fn,
                speed=speed, minimap=minimap, light=light, walk=walk, border=border)


GROUNDS = [
    ground('obsidian_floor', 'cracked obsidian floor', lambda s, p, n: obsidian(s, 0), 101, 100, c216(1, 0, 0), border=True),
    ground('magma_floor', 'magma-veined obsidian', lambda s, p, n: obsidian(s, 1), 101, 100, c216(3, 1, 0),
           light=(2, LC_MAGMA)),
    ground('ash_soil', 'ash soil', lambda s, p, n: ash_soil(s), 201, 120, c216(2, 2, 2), border=True),
    ground('bone_earth', 'bone-strewn earth', lambda s, p, n: bone_earth(s), 201, 120, c216(2, 2, 1)),
    ground('wet_rock', 'wet black rock', lambda s, p, n: wet_rock(s), 301, 120, c216(1, 1, 1), border=True),
    ground('mossy_rock', 'mossy black rock', lambda s, p, n: mossy_rock(s), 301, 120, c216(1, 1, 1)),
    ground('dark_moss', 'dark moss', lambda s, p, n: dark_moss(s), 401, 130, c216(0, 1, 0), border=True),
    ground('ruined_floor', 'ruined dark stone floor', lambda s, p, n: flagstones(s), 501, 100, c216(2, 2, 2)),
    ground('cursed_pool', 'cursed pool', lambda s, p, n: cursed_pool(s, p, n), 101, 100, c216(1, 0, 2), phases=6,
           ms=180, light=(2, LC_PURPLE), walk=False),
]


def build_things():
    things = list(GROUNDS)
    for g in GROUNDS:
        if g['border']:
            for piece in BORDER_PIECES:
                things.append(dict(key='%s_border_%s' % (g['key'], piece), name=g['name'], kind='border',
                                   ground=g['key'], piece=piece, w=1, h=1, px=4, py=4, phases=1, ms=0, seed=g['seed'],
                                   minimap=g['minimap'], light=None))
    for key, name, style, seed in (('dark_wall', 'dark stone wall', 'masonry', 601),
                                   ('ruined_wall', 'ruined stone wall', 'ruined', 602),
                                   ('obsidian_wall', 'obsidian rock wall', 'obsidian', 603)):
        things.append(dict(key=key, name=name, kind='wall', style=style, w=2, h=2, px=2, py=2, phases=1, ms=0, seed=seed,
                           minimap=c216(5, 1, 0) if False else 186, light=None, block=('solid', 'missile', 'path')))
    O = []

    def obj(key, name, w, h, seed, draw, block=(), light=None, phases=1, ms=0, minimap=None, bottom=False, sync=False, rim=None):
        O.append(dict(key=key, name=name, kind='object', w=w, h=h, px=1, py=1, phases=phases, ms=ms, seed=seed, draw=draw,
                      block=block, light=light, minimap=minimap, bottom=bottom, sync=sync, rim=rim or {}))
    obj('dead_tree', 'dead tree', 2, 2, 701, lambda s, p, n: tree_img(s, 2, 4, R * 0.52, 16.0, 0.85),
        block=('solid',), minimap=c216(1, 1, 0))
    obj('twisted_tree', 'twisted dead tree', 2, 2, 702, lambda s, p, n: tree_img(s, 2, 5, R * 0.5, 15.0, 0.75),
        block=('solid',), minimap=c216(1, 1, 0))
    obj('dead_bush', 'dead bush', 1, 1, 703, lambda s, p, n: tree_img(s, 1, 3, R * 0.3, 8.0, 0.9),
        block=('solid',), minimap=c216(1, 1, 0))
    obj('dark_boulder', 'dark boulder', 1, 1, 704,
        lambda s, p, n: rock_img(s, 1, 1, [(R * 0.5, R * 0.6, R * 0.38, R * 0.3, 40), (R * 0.36, R * 0.48, R * 0.22, R * 0.2, 30)]),
        block=('solid', 'missile'), minimap=c216(1, 1, 1))
    obj('rock_outcrop', 'jagged rock outcrop', 2, 2, 705,
        lambda s, p, n: rock_img(s, 2, 2, [(R * 1.42, R * 1.56, R * 0.52, R * 0.4, 60), (R * 1.05, R * 1.22, R * 0.55, R * 0.5, 90),
                                         (R * 0.68, R * 0.98, R * 0.44, R * 0.42, 70), (R * 1.38, R * 1.02, R * 0.4, R * 0.45, 76),
                                         (R * 0.95, R * 0.72, R * 0.38, R * 0.36, 62)],
                                 veins=True),
        block=('solid', 'missile', 'path'), minimap=c216(1, 1, 1), bottom=True)
    obj('ruined_pillar', 'ruined pillar', 1, 2, 706, lambda s, p, n: pillar_img(s, 0.32), block=('solid',),
        minimap=186, bottom=True)
    obj('broken_pillar', 'broken pillar', 1, 1, 707, lambda s, p, n: pillar_img(s, 0.38, stump=True), block=('solid',),
        minimap=186, bottom=True)
    obj('brazier', 'iron brazier', 1, 2, 708, lambda s, p, n: brazier_img(s, p, n), block=('solid', 'path'),
        light=(7, LC_FIRE), phases=6, ms=140, minimap=c216(5, 2, 0))
    obj('standing_torch', 'standing torch', 1, 2, 709, lambda s, p, n: torch_img(s, p, n), block=('solid', 'path'),
        light=(5, LC_FIRE), phases=6, ms=140, minimap=c216(5, 2, 0))
    obj('glowcap_purple', 'violet glowcaps', 1, 1, 710, lambda s, p, n: fungus_img(s, 'purple', p, n),
        light=(2, LC_PURPLE), phases=4, ms=420)
    obj('glowcap_teal', 'teal glowcaps', 1, 1, 711, lambda s, p, n: fungus_img(s, 'teal', p, n),
        light=(2, LC_TEAL), phases=4, ms=420)
    obj('blood_crystals', 'blood crystals', 1, 1, 712, lambda s, p, n: crystal_img(s), block=('solid',),
        light=(2, LC_CRIMSON), minimap=c216(3, 0, 0))
    obj('bone_pile', 'pile of bones', 1, 1, 713, lambda s, p, n: rubble_img(s, bones=True),
        rim=SMALL_RIM)
    obj('rubble', 'dark rubble', 1, 1, 714, lambda s, p, n: rubble_img(s), rim=SMALL_RIM)
    things += O
    for i, t in enumerate(things):
        t['cid'] = FIRST_ID + i
        t['sid'] = t['cid'] + SERVER_OFFSET
    return things


# =================================================================================================== rendering
def render(things, log=print):
    """returns {key: {'s32': {(ph, x, y): uint8 (h*32, w*32, 4)}, 'm64': {...}}}"""
    out = {}
    gtex = {}
    t0 = time.time()
    for t in things:
        k = t['key']
        s32, m64 = {}, {}
        if t['kind'] == 'ground':
            for ph in range(t['phases']):
                rgb, hmap = t['fn'](t['seed'], ph, t['phases'])
                rgb = L.relief(rgb, hmap, True, **t.get('relief', {}))
                tex = L.rgba(rgb, np.ones(rgb.shape[:2], np.float32))
                d32 = L.finish(tex, 4, True, 0.55)
                d64 = L.finish(tex, 2, True, 0.3)
                if ph == 0:
                    gtex[k] = (d32, d64)
                for y in range(4):
                    for x in range(4):
                        s32[(ph, x, y)] = d32[y * 32:(y + 1) * 32, x * 32:(x + 1) * 32]
                        m64[(ph, x, y)] = d64[y * 64:(y + 1) * 64, x * 64:(x + 1) * 64]
        elif t['kind'] == 'border':
            d32, d64 = gtex[t['ground']]
            for y in range(4):
                for x in range(4):
                    m, kf, ol = border_layers(t['seed'], t['piece'], x, y)
                    for f, dd, store in ((4, d32, s32), (2, d64, m64)):
                        n = R // f
                        cov = m.reshape(n, f, n, f).mean(axis=(1, 3))
                        kk = (kf * m).reshape(n, f, n, f).sum(axis=(1, 3)) / np.maximum(m.reshape(n, f, n, f).sum(axis=(1, 3)), 1)
                        oo = ol.reshape(n, f, n, f).mean(axis=(1, 3))
                        g = dd[y * n:(y + 1) * n, x * n:(x + 1) * n].astype(np.float32)
                        rgb = g[..., :3] * kk[..., None]
                        rgb = np.where((oo >= 0.4)[..., None], rgb * 0.35 + 4, rgb)
                        img = np.zeros((n, n, 4), np.uint8)
                        on = cov >= 0.5
                        img[..., :3] = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
                        img[..., 3] = np.where(on, 255, 0)
                        img[~on] = 0
                        store[(0, x, y)] = img
        elif t['kind'] == 'wall':
            for y in range(t['py']):
                for x in range(t['px']):
                    hi = L.rim_light(wall_cube(t['seed'], t['style'], x, y), hl=0.35, sh=0.3, form=0, width=6)
                    s32[(0, x, y)] = L.finish(hi, 4, False, 0.45)
                    m64[(0, x, y)] = L.finish(hi, 2, False, 0.25)
        else:
            his = fit_frames([t['draw'](t['seed'], ph, t['phases']) for ph in range(t['phases'])], t['w'], t['h'])
            his = [L.rim_light(hi, **t.get('rim', {})) for hi in his]
            for ph, hi in enumerate(his):
                s32[(ph, 0, 0)] = L.finish(hi, 4, False, 0.45)
                m64[(ph, 0, 0)] = L.finish(hi, 2, False, 0.25)
        out[k] = {'s32': s32, 'm64': m64}
        log(f'  {t["cid"]} {k:<34} {t["kind"]:<7} {t["w"]}x{t["h"]} p{t["px"]}x{t["py"]} f{t["phases"]}  {time.time() - t0:6.1f}s')
    return out


def _resize_rgba(img, size):
    """high-quality resize of a float straight-alpha RGBA image (premultiplied Lanczos per channel)"""
    a = img[..., 3]
    out = []
    for c in range(4):
        ch = img[..., c] * a if c < 3 else a
        out.append(np.asarray(Image.fromarray(ch.astype(np.float32), 'F').resize(size, Image.LANCZOS)))
    al = np.clip(out[3], 0, 1)
    rgb = np.stack([np.where(al > 1e-4, out[c] / np.maximum(al, 1e-4), 0) for c in range(3)], -1)
    return L.rgba(rgb, al)


def fit_frames(frames, w, h, side=0.02, top=0.02, bottom=0.03):
    """scale every frame of an object by the same factor so that the union of their visible content fills the
    w x h canvas (largest fit with small margins, centred, standing on the bottom).  Objects are drawn at whatever
    size reads best and always ship filling their cells."""
    W, H = w * R, h * R
    on = np.zeros((H, W), bool)
    for f in frames:
        on |= f[..., 3] > 0.5
    ys, xs = np.nonzero(on)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    bw, bh = x1 - x0, y1 - y0
    sc = min(W * (1 - 2 * side) / bw, H * (1 - top - bottom) / bh)
    nw, nh = max(1, int(round(bw * sc))), max(1, int(round(bh * sc)))
    ox = (W - nw) // 2
    oy = int(round(H * (1 - bottom))) - nh
    out = []
    for f in frames:
        crop = f[y0:y1, x0:x1]
        r = _resize_rgba(crop, (nw, nh))
        c = np.zeros((H, W, 4), np.float32)
        c[oy:oy + nh, ox:ox + nw] = r
        out.append(c)
    return out


def check_fill(things, art):
    """the set must ship full cells: grounds opaque edge to edge, walls and objects filling their canvas, every
    32x32 part of a multi-tile thing used, border pieces reaching the edge they continue"""
    bad = []
    for t in things:
        fr = art[t['key']]['s32']
        W, H = t['w'] * 32, t['h'] * 32
        if t['kind'] == 'ground':
            for k, img in fr.items():
                if (img[..., 3] != 255).any():
                    bad.append('%s %s: ground sprite not fully opaque' % (t['key'], k))
            continue
        if t['kind'] == 'border':
            side = {'n': (slice(0, 1), slice(None)), 's': (slice(31, 32), slice(None)),
                    'w': (slice(None), slice(0, 1)), 'e': (slice(None), slice(31, 32))}
            for k, img in fr.items():
                cov = (img[..., 3] > 0).mean()
                p = t['piece']
                if p.startswith('outer'):
                    cy = 0 if p[6] == 'n' else 31
                    cx = 0 if p[7] == 'w' else 31
                    if img[cy, cx, 3] == 0 or cov < 0.015:
                        bad.append('%s %s: corner piece does not reach its corner' % (t['key'], k))
                    continue
                if cov < 0.12:
                    bad.append('%s %s: border covers only %.0f%%' % (t['key'], k, cov * 100))
                edges = [p] if p in side else (list(p[-2:]) if p.startswith('inner') else [])
                for e in edges:
                    if not (img[side[e]][..., 3] > 0).all():
                        bad.append('%s %s: edge %s not continuous with the ground' % (t['key'], k, e))
            continue
        on = np.zeros((H, W), bool)
        for img in fr.values():
            on |= img[..., 3] > 0
        ys, xs = np.nonzero(on)
        if not len(xs):
            bad.append('%s: empty' % t['key']); continue
        rw = (xs.max() - xs.min() + 1) / W; rh = (ys.max() - ys.min() + 1) / H
        need_max, need_min = (0.97, 0.97) if t['kind'] == 'wall' else (0.9, 0.45)
        if max(rw, rh) < need_max or min(rw, rh) < need_min:
            bad.append('%s: content spans %.0f%% x %.0f%% of its %dx%d cell(s)' % (t['key'], rw * 100, rh * 100, t['w'], t['h']))
        for hh in range(t['h']):
            for ww in range(t['w']):
                part = on[hh * 32:(hh + 1) * 32, ww * 32:(ww + 1) * 32]
                if part.mean() < 0.06:
                    bad.append('%s: part (%d,%d) is almost empty (%.0f%%)' % (t['key'], ww, hh, part.mean() * 100))
    return bad


# =================================================================================================== dat / spr
def dat_flags(t):
    b = bytearray()
    if t['kind'] == 'ground':
        b += bytes([F_GROUND]) + struct.pack('<H', t['speed'])
    if t['kind'] == 'border':
        b += bytes([F_CLIP])
    if t['kind'] == 'wall' or t.get('bottom'):
        b += bytes([F_BOTTOM])
    block = set(t.get('block', ()))
    if t['kind'] == 'ground' and not t['walk']:
        block |= {'solid'}
    if 'solid' in block:
        b += bytes([F_NOTWALK])
    b += bytes([F_NOTMOVE])
    if 'missile' in block:
        b += bytes([F_BLOCKMISSILE])
    if 'path' in block:
        b += bytes([F_BLOCKPATH])
    if t.get('light'):
        b += bytes([F_LIGHT]) + struct.pack('<HH', *t['light'])
    if t.get('minimap') is not None and t['kind'] != 'border':
        b += bytes([F_MINIMAP]) + struct.pack('<H', t['minimap'])
    if t['kind'] == 'ground':
        b += bytes([F_FULLGROUND])
    return bytes(b)


def build_entry(t, sids):
    b = bytearray(dat_flags(t))
    b += b'\xff'
    b += bytes([t['w'], t['h']])
    if t['w'] > 1 or t['h'] > 1:
        b += bytes([32 * max(t['w'], t['h'])])
    b += bytes([1, t['px'], t['py'], 1, t['phases']])
    if t['phases'] > 1:
        sync = t['kind'] == 'ground' or t.get('sync')
        b += bytes([1 if sync else 0]) + struct.pack('<ib', 0, -1 if not sync else 0)
        for _ in range(t['phases']):
            b += struct.pack('<II', t['ms'], t['ms'])
    b += struct.pack(f'<{len(sids)}I', *sids)
    return bytes(b)


class _T:
    def __init__(self, t):
        self.w, self.h, self.layers, self.px, self.py, self.pz, self.phases = t['w'], t['h'], 1, t['px'], t['py'], 1, t['phases']


def tiles_of(img, w, h):
    out = {}
    for hh in range(h):
        for ww in range(w):
            y0 = (h - 1 - hh) * 32; x0 = (w - 1 - ww) * 32
            out[(ww, hh)] = img[y0:y0 + 32, x0:x0 + 32]
    return out


def encode_sprite(tile):
    a = np.ascontiguousarray(tile).reshape(1024, 4)
    on = a[:, 3] > 0
    if not on.any():
        return None
    body = bytearray()
    i = 0
    last = int(np.nonzero(on)[0][-1]) + 1
    while i < last:
        j = i
        while j < last and not on[j]:
            j += 1
        k = j
        while k < last and on[k]:
            k += 1
        body += struct.pack('<HH', j - i, k - j) + a[j:k].tobytes()
        i = k
    return b'\xff\x00\xff' + struct.pack('<H', len(body)) + bytes(body)


def write_pair(things, art, od, ospr, out_dir, log=print):
    n_base = FIRST_ID - 1
    ni = od.counts[0]
    if ni == n_base:
        mode = 'append'
    elif ni == n_base + len(things):
        mode = 'rebuild'
    else:
        sys.exit(f'input dat has {ni} items; expected {n_base} (stock) or {n_base + len(things)} (an earlier output '
                 f'of this script)')
    recs = {}
    per = []
    for t in things:
        T_ = _T(t)
        ids = [None] * (t['w'] * t['h'] * t['px'] * t['py'] * t['phases'])
        for (ph, x, y), img in art[t['key']]['s32'].items():
            for (ww, hh), tile in tiles_of(img, t['w'], t['h']).items():
                rec = encode_sprite(tile)
                ids[sprite_index(T_, x, y, 0, 0, ph, ww, hh)] = rec
                if rec is not None:
                    recs.setdefault(rec, None)
        per.append(ids)
    # reuse records already in the input spr
    mb = np.frombuffer(ospr.m, dtype=np.uint8)
    offs = ospr.offs.astype(np.int64)
    nzi = np.nonzero(offs)[0]
    lens = 5 + mb[offs[nzi] + 3].astype(np.int64) + (mb[offs[nzi] + 4].astype(np.int64) << 8)
    want = {}
    for rec in recs:
        want.setdefault(len(rec), {})[hashlib.md5(rec).digest()] = rec
    existing = {}
    for i in np.nonzero(np.isin(lens, np.array(list(want), np.int64)))[0]:
        o = int(offs[nzi[i]]); ln = int(lens[i])
        rec = bytes(ospr.m[o:o + ln])
        hit = want[ln].get(hashlib.md5(rec).digest())
        if hit is not None and hit == rec and rec not in existing:
            existing[rec] = int(nzi[i]) + 1
    cnt = ospr.count
    newrecs, rec_id = [], {}
    for rec in recs:
        if rec in existing:
            rec_id[rec] = existing[rec]
        else:
            newrecs.append(rec); rec_id[rec] = cnt + len(newrecs)
    # dat
    d = od.data
    o0 = od.outfits[0].raw[0]
    keep_items_end = od.items[n_base - 100].raw[1]
    out = bytearray(d[:keep_items_end])
    for t, ids in zip(things, per):
        out += build_entry(t, [rec_id[x] if x is not None else 0 for x in ids])
    out += d[o0:]
    struct.pack_into('<H', out, 4, n_base + len(things))
    open(os.path.join(out_dir, 'Tibia.dat'), 'wb').write(out)
    # spr (streamed)
    m = ospr.m; nn = len(newrecs)
    toffs = ospr.offs.astype('<u8').copy(); toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur); cur += len(rec)
    assert cur < 1 << 32
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn)); f.write(table.tobytes())
        pos = 8 + 4 * cnt
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)]); pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    log(f'dat ({mode}): items {ni} -> {n_base + len(things)} (client ids {FIRST_ID}..{FIRST_ID + len(things) - 1}); '
        f'spr: {len(recs)} distinct sprites, {nn} appended, {len(recs) - nn} reused ({cnt} -> {cnt + nn})')
    return n_base


def verify(things, art, od, ospr, out_dir, log=print):
    md = Dat(os.path.join(out_dir, 'Tibia.dat')); ms = Spr(os.path.join(out_dir, 'Tibia.spr'))
    n_base = FIRST_ID - 1
    assert md.variant == od.variant, md.variant
    assert md.counts[1:] == od.counts[1:] and md.counts[0] == n_base + len(things), md.counts
    assert ms.alpha and ms.count >= ospr.count and md.max_sprite <= ms.count
    keep_items_end = od.items[n_base - 100].raw[1]
    assert md.data[12:keep_items_end] == od.data[12:keep_items_end], 'stock items changed'
    assert md.data[md.outfits[0].raw[0]:] == od.data[od.outfits[0].raw[0]:], 'outfits/effects/missiles changed'
    nfr = 0
    for t in things:
        mt = md.items[t['cid'] - 100]
        assert (mt.w, mt.h, mt.px, mt.py, mt.phases) == (t['w'], t['h'], t['px'], t['py'], t['phases']), t['key']
        for (ph, x, y), img in art[t['key']]['s32'].items():
            back = np.zeros((t['h'] * 32, t['w'] * 32, 4), np.uint8)
            for hh in range(t['h']):
                for ww in range(t['w']):
                    a = ms.sprite(mt.sprites[sprite_index(mt, x, y, 0, 0, ph, ww, hh)])
                    if a is not None:
                        back[(t['h'] - 1 - hh) * 32:(t['h'] - hh) * 32, (t['w'] - 1 - ww) * 32:(t['w'] - ww) * 32] = a
            if not np.array_equal(back, img):
                sys.exit(f'MISMATCH {t["key"]} frame {(ph, x, y)}')
            nfr += 1
    random.seed(1)
    for sid in random.sample(range(1, ospr.count + 1), min(3000, ospr.count)) + [1, ospr.count]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log(f'verified: output dat parses ({md.variant}); {len(things)} things, {nfr} frames pixel-identical to the drawn '
        f'32 px art; stock items, outfits, effects and missiles byte-identical; 3000 sampled old sprites unchanged')
    return md, ms


# =================================================================================================== manifest, lua
OTB_FLAG = {'solid': 1 << 0, 'missile': 1 << 1, 'path': 1 << 2}
OTB_ALWAYSONTOP, OTB_ANIMATION = 1 << 13, 1 << 24


def otb_of(t):
    """(group, flags, top order) for items.otb"""
    group = 1 if t['kind'] == 'ground' else 0
    block = set(t.get('block', ()))
    if t['kind'] == 'ground' and not t['walk']:
        block |= {'solid'}
    flags = 0
    for b in block:
        flags |= OTB_FLAG[b]
    top = 0
    if t['kind'] == 'border':
        top = 1
    elif t['kind'] == 'wall' or t.get('bottom'):
        top = 2
    if top:
        flags |= OTB_ALWAYSONTOP
    if t['phases'] > 1:
        flags |= OTB_ANIMATION
    return group, flags, top


def describe(t):
    return t['name']


MANIFEST_COLS = ['client_id', 'server_id', 'key', 'name', 'kind', 'piece', 'size', 'patterns', 'phases', 'frame_ms', 'speed',
                 'otb_group', 'otb_flags', 'top_order', 'light_level', 'light_color', 'minimap', 'dat_flags']


def manifest_rows(things):
    rows = []
    for t in things:
        g, fl, top = otb_of(t)
        names = []
        b = dat_flags(t)
        i = 0
        while i < len(b):
            c = b[i]; i += 1
            nm = {0: 'ground', 1: 'clip', 2: 'bottom', 12: 'notwalkable', 13: 'notmoveable', 14: 'blockmissile',
                  15: 'blockpath', 22: 'light', 29: 'minimap', 31: 'fullground'}[c]
            names.append(nm)
            i += {0: 2, 22: 4, 29: 2}.get(c, 0)
        lt = t.get('light') or (0, 0)
        rows.append([t['cid'], t['sid'], t['key'], describe(t), t['kind'], t.get('piece', ''), '%dx%d' % (t['w'], t['h']),
                     '%dx%d' % (t['px'], t['py']), t['phases'], t['ms'], t.get('speed', 0), g, fl, top, lt[0], lt[1],
                     t.get('minimap') if t.get('minimap') is not None and t['kind'] != 'border' else '',
                     ' '.join(names)])
    return rows


def write_manifest(things, path):
    with open(path, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(MANIFEST_COLS)
        w.writerows(manifest_rows(things))


def lua_text(things):
    lines = ['-- Dark tile set: server ids of the items drawn by client/tools/sprites/gen_dark_tiles.py.',
             '-- Generated by that script (--lua-out); do not edit by hand. server id = client id + %d.' % SERVER_OFFSET,
             '-- The items exist only after server/tools/install_dark_tiles.py (items.otb / items.xml) and need the',
             '-- matching client Tibia.dat / Tibia.spr. ChaosDarkTiles.id(name, fallback) returns the fallback when the',
             '-- item is not installed, so every caller keeps working on a server without the set.',
             '',
             'ChaosDarkTiles = ChaosDarkTiles or {}',
             'local D = ChaosDarkTiles',
             '',
             'D.ids = {']
    for t in things:
        lines.append('\t%s = %d,' % (t['key'], t['sid']))
    lines[-1] = lines[-1].rstrip(',')
    lines += ['}',
              '',
              'local known = {}',
              '',
              '-- true when the server knows the item (items.otb has it)',
              'function D.installed(name)',
              '\tlocal id = D.ids[name]',
              '\tif not id then',
              '\t\treturn false',
              '\tend',
              '\tif known[id] == nil then',
              '\t\tlocal ok, yes = pcall(function()',
              '\t\t\tlocal it = ItemType(id)',
              '\t\t\treturn it ~= nil and it:getId() == id',
              '\t\tend)',
              '\t\tknown[id] = (ok and yes) and true or false',
              '\tend',
              '\treturn known[id]',
              'end',
              '',
              '-- the server id of a dark tile, or `fallback` when it is not installed (or name is nil)',
              'function D.id(name, fallback)',
              '\tif name and D.installed(name) then',
              '\t\treturn D.ids[name]',
              '\tend',
              '\treturn fallback',
              'end',
              '',
              '-- a list of server ids for a list of names, or `fallback` when any of them is missing',
              'function D.list(names, fallback)',
              '\tif type(names) ~= "table" or #names == 0 then',
              '\t\treturn fallback',
              '\tend',
              '\tlocal out = {}',
              '\tfor i, name in ipairs(names) do',
              '\t\tif not D.installed(name) then',
              '\t\t\treturn fallback',
              '\t\tend',
              '\t\tout[i] = D.ids[name]',
              '\tend',
              '\treturn out',
              'end',
              '']
    return '\n'.join(lines)


# =================================================================================================== sheets
def master_sheet(t, frames, size):
    W = t['w'] * size; H = t['h'] * size
    sheet = Image.new('RGBA', (t['phases'] * t['px'] * W, t['py'] * H), (0, 0, 0, 0))
    for (ph, x, y), img in frames.items():
        sheet.paste(Image.fromarray(img, 'RGBA'), ((ph * t['px'] + x) * W, y * H))
    return sheet


def contact(things, art, which, size, path, cols=8):
    cells = []
    for t in things:
        fr = art[t['key']][which]
        sh = master_sheet(dict(t, phases=1), {k: v for k, v in fr.items() if k[0] == 0}, size)
        cells.append((t, sh))
    cw = max(min(s.width, 4 * size) for _, s in cells) + 12
    ch = max(min(s.height, 4 * size) for _, s in cells) + 26
    rows = (len(cells) + cols - 1) // cols
    img = Image.new('RGBA', (cols * cw, rows * ch), (24, 22, 28, 255))
    dr = ImageDraw.Draw(img)
    for i, (t, s) in enumerate(cells):
        x0, y0 = (i % cols) * cw, (i // cols) * ch
        if s.width > 4 * size or s.height > 4 * size:
            s = s.crop((0, 0, min(s.width, 4 * size), min(s.height, 4 * size)))
        checker = Image.new('RGBA', s.size, (52, 58, 44, 255))
        checker.alpha_composite(s)
        img.paste(checker, (x0 + 6, y0 + 20))
        dr.text((x0 + 6, y0 + 4), '%d %s' % (t['cid'], t['key'][:26]), fill=(235, 205, 140, 255))
    img.convert('RGB').save(path, quality=90)


def scene(things, art, ospr_dat, path, scale_paths):
    """a sample area at 32 px: stock-like plain ground (a flat earth colour of our own), the dark grounds with their
    borders, walls and objects, to judge the set side by side"""
    by = {t['key']: t for t in things}
    Wt, Ht = 22, 14
    img = Image.new('RGBA', (Wt * 32, Ht * 32), (0, 0, 0, 255))
    rng = np.random.default_rng(3)
    plain = np.zeros((32, 32, 4), np.uint8)
    pl = (L.ramp(L.FBM(9, 4, 32, 3)(*L.grid(32, 32)[::-1]), ['2f4a22', '3b5a29', '476a31']) * 255).astype(np.uint8)
    plain[..., :3] = pl; plain[..., 3] = 255
    grid = [[None] * Wt for _ in range(Ht)]
    # regions
    for y in range(Ht):
        for x in range(Wt):
            if 2 <= x <= 7 and 2 <= y <= 10:
                grid[y][x] = 'obsidian_floor' if rng.random() > 0.15 else 'magma_floor'
            elif 9 <= x <= 13 and 3 <= y <= 11:
                grid[y][x] = 'ash_soil' if rng.random() > 0.35 else 'bone_earth'
            elif 15 <= x <= 20 and 1 <= y <= 6:
                grid[y][x] = 'wet_rock' if rng.random() > 0.35 else 'mossy_rock'
            elif 15 <= x <= 20 and 8 <= y <= 12:
                grid[y][x] = 'dark_moss'
    grid[6][4] = 'cursed_pool'
    for x in range(9, 14):
        grid[1][x] = 'ruined_floor'; grid[2][x] = 'ruined_floor'

    def draw(key, x, y, ph=0):
        t = by[key]
        fr = art[key]['s32'][(ph, x % t['px'], y % t['py'])]
        im = Image.fromarray(fr, 'RGBA')
        img.alpha_composite(im, ((x - t['w'] + 1) * 32, (y - t['h'] + 1) * 32))
    for y in range(Ht):
        for x in range(Wt):
            g = grid[y][x]
            if g:
                draw(g, x, y)
            else:
                img.paste(Image.fromarray(plain, 'RGBA'), (x * 32, y * 32))
    # borders on plain tiles next to bordered grounds
    fam = {'obsidian_floor': 'obsidian_floor', 'magma_floor': 'obsidian_floor', 'cursed_pool': 'obsidian_floor',
           'ash_soil': 'ash_soil', 'bone_earth': 'ash_soil', 'wet_rock': 'wet_rock', 'mossy_rock': 'wet_rock',
           'dark_moss': 'dark_moss'}

    def g(x, y):
        if 0 <= x < Wt and 0 <= y < Ht and grid[y][x]:
            return fam.get(grid[y][x])
        return None
    for y in range(Ht):
        for x in range(Wt):
            if grid[y][x]:
                continue
            for base in ('obsidian_floor', 'ash_soil', 'wet_rock', 'dark_moss'):
                n, s, w, e = g(x, y - 1) == base, g(x, y + 1) == base, g(x - 1, y) == base, g(x + 1, y) == base
                pieces = []
                if n and w: pieces.append('inner_nw')
                elif n and e: pieces.append('inner_ne')
                elif s and w: pieces.append('inner_sw')
                elif s and e: pieces.append('inner_se')
                else:
                    for f, p in ((n, 'n'), (s, 's'), (w, 'w'), (e, 'e')):
                        if f: pieces.append(p)
                    if not (n or w) and g(x - 1, y - 1) == base: pieces.append('outer_nw')
                    if not (n or e) and g(x + 1, y - 1) == base: pieces.append('outer_ne')
                    if not (s or w) and g(x - 1, y + 1) == base: pieces.append('outer_sw')
                    if not (s or e) and g(x + 1, y + 1) == base: pieces.append('outer_se')
                for p in pieces:
                    draw('%s_border_%s' % (base, p), x, y)
    objs = [('dead_tree', 3, 3), ('twisted_tree', 18, 11), ('dead_bush', 12, 8), ('dark_boulder', 6, 9),
            ('rock_outcrop', 19, 4), ('ruined_pillar', 9, 2), ('broken_pillar', 13, 2), ('brazier', 11, 5),
            ('standing_torch', 7, 3), ('glowcap_purple', 16, 9), ('glowcap_teal', 17, 12), ('blood_crystals', 5, 7),
            ('bone_pile', 10, 9), ('rubble', 12, 10)]
    walls = [(x, 13) for x in range(1, 9)] + [(8, y) for y in range(11, 13)]
    for wx, wy in walls:
        draw('dark_wall' if wx % 3 else 'ruined_wall', wx, wy)
    for x in range(15, 21):
        draw('obsidian_wall', x, 7) if x != 18 else None
    for key, x, y in objs:
        draw(key, x, y)
    img.convert('RGB').save(path)
    return img


# =================================================================================================== main
def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat'); ap.add_argument('--ours-spr')
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--masters', default=None, help='directory for the 64 px master PNGs')
    ap.add_argument('--sheets', default=None, help='directory for contact sheets and the sample scene')
    ap.add_argument('--manifest-out', default=None); ap.add_argument('--lua-out', default=None)
    ap.add_argument('--preview-only', action='store_true', help='draw and write sheets only (no dat/spr)')
    ap.add_argument('--only', default=None, help='comma list of keys to draw (preview only)')
    a = ap.parse_args()
    t0 = time.time()
    os.makedirs(a.out_dir, exist_ok=True)
    things = build_things()
    if a.only:
        assert a.preview_only, '--only needs --preview-only'
        want = set(a.only.split(','))
        need = set(want) | {t['ground'] for t in things if t['key'] in want and t['kind'] == 'border'}
        draw_list = [t for t in things if t['key'] in need]
    else:
        draw_list = things
    print(f'{len(things)} things, client ids {FIRST_ID}..{FIRST_ID + len(things) - 1}, server ids '
          f'{FIRST_ID + SERVER_OFFSET}..{FIRST_ID + SERVER_OFFSET + len(things) - 1}')
    art = render(draw_list)
    print(f'drawn in {time.time() - t0:.1f}s')
    bad = check_fill(draw_list, art)
    for b in bad:
        print('FILL CHECK:', b)
    if bad:
        sys.exit(f'{len(bad)} sprite(s) do not fill their cells')
    print('fill check: every sprite fills its cell (grounds opaque, objects and walls fit their canvas)')
    sheets = a.sheets or a.out_dir
    os.makedirs(sheets, exist_ok=True)
    contact(draw_list, art, 's32', 32, os.path.join(sheets, 'contact_32.jpg'))
    contact(draw_list, art, 'm64', 64, os.path.join(sheets, 'contact_64.jpg'), cols=6)
    if not a.only:
        sc = scene(things, art, None, os.path.join(sheets, 'scene_32.png'), None)
        sc.resize((sc.width * 2, sc.height * 2), Image.NEAREST).convert('RGB').save(os.path.join(a.out_dir, 'scene_32_x2.png'))
    if a.masters:
        os.makedirs(a.masters, exist_ok=True)
        for t in draw_list:
            master_sheet(t, art[t['key']]['m64'], 64).save(os.path.join(a.masters, t['key'] + '.png'), optimize=True)
        print(f'masters: {len(draw_list)} sheets in {a.masters}')
    write_manifest(things, os.path.join(a.out_dir, 'dark_tiles.csv'))
    open(os.path.join(a.out_dir, 'chaos_dark_tiles.lua'), 'w').write(lua_text(things))
    if a.manifest_out:
        write_manifest(things, a.manifest_out); print('wrote', a.manifest_out)
    if a.lua_out:
        open(a.lua_out, 'w').write(lua_text(things)); print('wrote', a.lua_out)
    if a.preview_only:
        print(f'preview only: done in {time.time() - t0:.1f}s')
        return
    assert a.ours_dat and a.ours_spr, '--ours-dat and --ours-spr are needed'
    for p in (a.ours_dat, a.ours_spr):
        assert os.path.abspath(os.path.dirname(p)) != os.path.abspath(a.out_dir), 'out-dir must differ from the input dir'
    od = Dat(a.ours_dat); ospr = Spr(a.ours_spr)
    assert od.variant[0] == 'new' and od.variant[1] and od.variant[2], f'expected a 10.98 dat: {od.variant}'
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    write_pair(things, art, od, ospr, a.out_dir)
    verify(things, art, od, ospr, a.out_dir)
    print(f'done in {time.time() - t0:.1f}s')


if __name__ == '__main__':
    main()
