"""Swamp, acid, lava and water grounds for gen_theme_art.py, with the 12 border pieces of each (edges, outer and inner
corners), drawn in code like the dark tile set (gen_dark_tiles.py, darklib.py): periodic noise and Voronoi cells at
128 px per tile, a 4 x 4 tile texture period (the client picks the pattern by x % 4, y % 4, so the ground tiles with
itself), then downsampled 4:1. No pixel of any client or reference sheet is read.

Border pieces use the dark set's ragged edge geometry (gen_dark_tiles.border_mask: the edge depth is a periodic
function of the world coordinate along the edge, so neighbouring pieces meet). A piece lies on the LOWER tile next to
the family and carries the family's own texture (sampled at that tile's world position, so it continues the ground
next to it) and a rim: a stone lip round the acid, a basalt crust round the lava, a mud bank round the water, a dark
reed fringe round the swamp. The liquids loop over `phases` frames (texture offsets on a circle: periodic in space and
time); their border pieces animate in step (synchronised animation, the same phase count and ms).
"""
import math

import numpy as np

import darklib as L
import gen_dark_tiles as DT

R = DT.R            # 128 px per tile
T = DT.T            # texture period, 4 tiles
PIECES = DT.BORDER_PIECES


def c216(r, g, b):
    return r * 36 + g * 6 + b


# family: key, name, phases, ms, walkable, speed, minimap, light (level, colour), seed
FAMILIES = [
    dict(key='swamp', name='swamp', phases=1, ms=0, walk=True, speed=170, minimap=c216(1, 2, 0), light=None, seed=611),
    dict(key='acid', name='acid pool', phases=8, ms=160, walk=False, speed=100, minimap=c216(3, 5, 0),
         light=(2, c216(2, 5, 0)), seed=612),
    dict(key='lava', name='lava', phases=8, ms=180, walk=False, speed=100, minimap=c216(5, 1, 0),
         light=(3, c216(5, 2, 0)), seed=613),
    dict(key='water', name='deep water', phases=8, ms=200, walk=False, speed=100, minimap=c216(0, 1, 3), light=None,
         seed=614),
]

_Y, _X = L.grid(T, T)


def loop_xy(phase, phases, r):
    a = 2 * math.pi * phase / max(phases, 1)
    return r * math.cos(a), r * math.sin(a)


# ------------------------------------------------------------------------------------------------ textures (T x T)
def swamp_tex(seed, phase, phases):
    X, Y = _X, _Y
    f = L.FBM(seed, 6, T, 5)(X, Y)
    clump = L.Voronoi(seed + 1, 22, T, 0.9)
    f1, f2, idn, _, _ = clump(X, Y)
    tuft = np.clip(1 - f1 / 9.0, 0, 1) ** 1.4
    h = f * 18 + tuft * 9
    base = L.ramp(f * 0.8 + tuft * 0.35, ['#1c260a', '#34420e', '#55631a', '#7a8a26', '#a8b448'])
    col = L.shade(base, h, True, ambient=0.55, diffuse=0.65)
    col = L.relief(col, h, True, ao=0.3, hl=0.25, r=4)
    # murky puddles in the low parts
    wet = L.FBM(seed + 2, 4, T, 3)(X, Y)
    pud = L.sstep(0.36, 0.30, wet)
    water = L.ramp(L.FBM(seed + 3, 16, T, 2)(X, Y), ['#0e1408', '#1a2410', '#2a3818'])
    col = col * (1 - pud[..., None]) + water * pud[..., None]
    edge = (pud > 0.15) & (pud < 0.6)
    col = np.where(edge[..., None], col * 0.7, col)
    # pale reed blades and a few grey-green flowers
    rng = np.random.default_rng(seed + 4)
    for _ in range(70):
        x, y = rng.uniform(0, T), rng.uniform(0, T)
        L_ = rng.uniform(8, 16)
        ang = -math.pi / 2 + rng.uniform(-0.5, 0.5)
        dx, dy = (X - x + T / 2) % T - T / 2, (Y - y + T / 2) % T - T / 2
        d, t = L.seg_dist(dx, dy, 0, 0, math.cos(ang) * L_, math.sin(ang) * L_)
        m = (d < 1.6 * (1 - 0.6 * t)) & (pud < 0.3)
        col = np.where(m[..., None], L.ramp(1 - t, ['#5c6a1c', '#b6c25a'])[...], col)
    return np.clip(col, 0, 1)


def acid_tex(seed, phase, phases):
    X, Y = _X, _Y
    ox, oy = loop_xy(phase, phases, 30)
    f = L.FBM(seed, 5, T, 4)(X + ox, Y + oy)
    g = L.FBM(seed + 1, 8, T, 3)(X - oy * 0.8 + f * 40, Y + ox * 0.8)
    col = L.ramp(0.6 * g + 0.4 * f, ['#3a5a02', '#6a9a06', '#a6d214', '#d6f43a', '#f4ffa0'])
    ridge = np.clip((L.ridged(g) - 0.8) / 0.2, 0, 1)
    col = col + ridge[..., None] * 0.25
    # bubbles: a fixed set of spots, each rising and popping at its own time in the loop
    rng = np.random.default_rng(seed + 2)
    for _ in range(36):
        x, y = rng.uniform(0, T), rng.uniform(0, T)
        t0 = rng.uniform(0, 1)
        life = ((phase / phases) - t0) % 1.0
        if life > 0.5:
            continue
        r = 3 + 9 * life
        dx, dy = (X - x + T / 2) % T - T / 2, (Y - y + T / 2) % T - T / 2
        d = np.hypot(dx, dy)
        rimm = np.abs(d - r) < 1.6
        inner = d < r - 1.6
        col = np.where(rimm[..., None], L.hexcol('#f8ffc0'), col)
        col = np.where(inner[..., None], col * 1.08 + 0.04, col)
        hl = np.hypot(dx + r * 0.35, dy + r * 0.35) < max(r * 0.25, 1.2)
        col = np.where(hl[..., None], L.hexcol('#ffffff'), col)
    return np.clip(col, 0, 1)


def lava_tex(seed, phase, phases):
    X, Y = _X, _Y
    ox, oy = loop_xy(phase, phases, 16)
    v = L.Voronoi(seed, 4, T, 0.85)
    f1, f2, idn, _, _ = v(X + ox * 0.5, Y + oy * 0.5)
    crack = np.clip(1 - (f2 - f1) / (6.0 + 8.0 * L.FBM(seed + 3, 8, T, 2)(X, Y)), 0, 1)
    flow = L.FBM(seed + 1, 6, T, 4)(X + ox, Y + oy)
    pulse = 0.5 + 0.5 * math.sin(2 * math.pi * phase / max(phases, 1))
    plate = L.ramp(flow * 0.7 + 0.2 * (f1 / 30.0), ['#2a0604', '#5a1006', '#8a2008', '#b8380c'])
    h = (1 - crack) * 10 + flow * 6
    plate = L.shade(plate, h, True, ambient=0.6, diffuse=0.6)
    hot = L.ramp(np.clip(crack * (0.8 + 0.2 * pulse) + flow * 0.25, 0, 1),
                 ['#a01e04', '#e0500a', '#ff8c1a', '#ffd04a', '#fff6c0'])
    k = L.sstep(0.35, 0.75, crack)[..., None]
    col = plate * (1 - k) + hot * k
    # molten pools in the larger cells
    pool = L.sstep(0.62, 0.7, L.FBM(seed + 2, 4, T, 3)(X - ox, Y - oy))[..., None]
    col = col * (1 - pool) + hot * pool * 0.95
    return np.clip(col, 0, 1)


def water_tex(seed, phase, phases):
    X, Y = _X, _Y
    ox, oy = loop_xy(phase, phases, 24)
    f = L.FBM(seed, 4, T, 4)(X + ox, Y + oy * 0.5)
    g = L.FBM(seed + 1, 8, T, 3)(X + f * 30 - oy, Y + ox * 0.6)
    col = L.ramp(0.55 * f + 0.45 * g, ['#04142e', '#0a2a5a', '#14468a', '#2a68b0', '#5a98d4'])
    crest = np.clip((L.ridged(g) - 0.9) / 0.1, 0, 1)
    col = col + crest[..., None] * L.hexcol('#7cb4e8') * 0.35
    sp = L.FBM(seed + 2, 32, T, 2)(X - ox * 2, Y - oy * 2)
    spark = (sp > 0.78) & (crest > 0.5)
    col = np.where(spark[..., None], L.hexcol('#e8f6ff'), col)
    return np.clip(col, 0, 1)


TEX = {'swamp': swamp_tex, 'acid': acid_tex, 'lava': lava_tex, 'water': water_tex}

RIM = {   # rim band of a border piece: ramp, width (hi-res px), height relief
    'swamp': (['#0c1206', '#1e2a0a', '#3a4a12', '#5e6e1e'], 9),
    'acid': (['#2a2722', '#4e4940', '#7a7466', '#a8a08c', '#d6ceb8'], 22),
    'lava': (['#0e0808', '#22140e', '#3c2418', '#5a3622', '#7a4a2e'], 18),
    'water': (['#1a0e06', '#3a2412', '#5e3c1e', '#86603a', '#a88052'], 18),
}


def rim_tex(fam, seed):
    stops, _ = RIM[fam]
    X, Y = _X, _Y
    if fam == 'acid':   # pebbles
        f1, f2, idn, _, _ = L.Voronoi(seed + 9, 40, T, 0.9)(X, Y)
        h = np.clip(1 - f1 / 9.0, 0, 1) * 10
        val = L.FBM(seed + 10, 16, T, 2)(X, Y) * 0.5 + np.clip(1 - f1 / 9.0, 0, 1) * 0.5
        col = L.shade(L.ramp(val, stops), h, True, ambient=0.5, diffuse=0.8)
        col = np.where(((f2 - f1) < 1.6)[..., None], col * 0.45, col)
        return col
    f = L.FBM(seed + 9, 12, T, 4)(X, Y)
    h = f * 14
    return L.shade(L.ramp(f, stops), h, True, ambient=0.5, diffuse=0.8)


# ------------------------------------------------------------------------------------------------ build
def piece_masks(seed):
    """{(piece, px, py): (coverage, inside distance)} at R x R"""
    out = {}
    pad = 16
    for piece in PIECES:
        for py in range(4):
            for px in range(4):
                m = DT.border_mask(seed, piece, px, py, pad)
                din = L.erode_dist(m, 48)
                sl = (slice(pad, pad + R), slice(pad, pad + R))
                out[(piece, px, py)] = (m[sl], din[sl])
    return out


def build_family(fam):
    """-> {'ground': frames, '<piece>': frames}; frames = [phase][(px, py)] -> 32 x 32 RGBA uint8"""
    seed, n = fam['seed'], fam['phases']
    rimc = rim_tex(fam['key'], seed)
    _, rw = RIM[fam['key']]
    masks = piece_masks(seed)
    out = {'ground': [dict() for _ in range(n)]}
    for p in PIECES:
        out[p] = [dict() for _ in range(n)]
    for ph in range(n):
        tex = TEX[fam['key']](seed, ph, n)
        img = L.rgba(tex, np.ones(tex.shape[:2], np.float32))
        for py in range(4):
            for px in range(4):
                tile = img[py * R:(py + 1) * R, px * R:(px + 1) * R]
                out['ground'][ph][(px, py)] = L.finish(tile, 4, False, 0.3)
                rtile = rimc[py * R:(py + 1) * R, px * R:(px + 1) * R]
                for p in PIECES:
                    m, din = masks[(p, px, py)]
                    band = m & (din <= rw)
                    col = np.where(band[..., None], rtile, tile[..., :3])
                    # the inner lip of the rim: a dark line where it meets the family's ground, a lit top edge outside
                    lip = m & (din > rw) & (din <= rw + 3)
                    col = np.where(lip[..., None], col * 0.55, col)
                    out_edge = m & (din <= 3)
                    col = np.where(out_edge[..., None], col * 0.6, col)
                    if fam['key'] == 'swamp':
                        col = np.where((m & (din > rw))[..., None], col * (0.75 + 0.25 * L.sstep(rw, rw + 10, din))[..., None], col)
                    piece = L.rgba(col, m.astype(np.float32))
                    out[p][ph][(px, py)] = L.finish(piece, 4, False, 0.3)
    return out


def check(fam, art):
    """grounds opaque edge to edge; every border piece covers its edge; nothing empty"""
    bad = []
    for ph in art['ground']:
        for k, t in ph.items():
            if (t[..., 3] < 255).any():
                bad.append('%s ground %s not opaque' % (fam['key'], k))
    for p in PIECES:
        for ph in art[p]:
            for k, t in ph.items():
                a = t[..., 3] > 0
                if not a.any():
                    bad.append('%s %s %s empty' % (fam['key'], p, k))
                edge = {'n': a[0, :], 's': a[-1, :], 'w': a[:, 0], 'e': a[:, -1]}
                for side in p.replace('outer_', '').replace('inner_', ''):
                    if len(p) <= 1 or p.startswith('inner'):
                        if not edge[side].all():
                            bad.append('%s %s %s: edge %s not continuous' % (fam['key'], p, k, side))
    return bad


def pieces_for(has):
    """the border pieces a LOWER tile gets from its 8 neighbours: has(dx, dy) -> True where the family lies"""
    n, s, w, e = has(0, -1), has(0, 1), has(-1, 0), has(1, 0)
    out = []
    used = set()
    for a, b, name in ((n, w, 'inner_nw'), (n, e, 'inner_ne'), (s, w, 'inner_sw'), (s, e, 'inner_se')):
        if a and b:
            out.append(name)
            used |= {name[-2], name[-1]}
    for flag, name in ((n, 'n'), (s, 's'), (w, 'w'), (e, 'e')):
        if flag and name not in used:
            out.append(name)
    for dx, dy, name, a, b in ((-1, -1, 'outer_nw', n, w), (1, -1, 'outer_ne', n, e), (-1, 1, 'outer_sw', s, w),
                               (1, 1, 'outer_se', s, e)):
        if has(dx, dy) and not a and not b:
            out.append(name)
    return out


def blob(w, h, seed, fill=0.5):
    """a rounded patch (bool h x w) for previews: a smoothed random field, no single-tile holes"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    cx, cy = (w - 1) / 2, (h - 1) / 2
    d = ((xx - cx) / (w / 2)) ** 2 + ((yy - cy) / (h / 2)) ** 2
    m = d + rng.uniform(-0.25, 0.25, (h, w)) < fill
    for _ in range(2):
        nb = sum(np.roll(np.roll(m, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        m = nb >= 5
    m[0, :] = m[-1, :] = False
    m[:, 0] = m[:, -1] = False
    return m


def scene(art, plain, mask, phase=0):
    """32 px scene: `plain` (32 x 32 RGBA) everywhere, the family where mask, its border pieces around it"""
    h, w = mask.shape
    im = np.zeros((h * 32, w * 32, 4), np.uint8)
    ph = phase % len(art['ground'])

    def put(t, x, y):
        a = t[..., 3:4] / 255.0
        blk = im[y * 32:(y + 1) * 32, x * 32:(x + 1) * 32]
        blk[..., :3] = (t[..., :3] * a + blk[..., :3] * (1 - a)).astype(np.uint8)
        blk[..., 3] = 255
    for y in range(h):
        for x in range(w):
            if mask[y, x]:
                put(art['ground'][ph][(x % 4, y % 4)], x, y)
                continue
            put(plain, x, y)
            has = lambda dx, dy: 0 <= y + dy < h and 0 <= x + dx < w and bool(mask[y + dy, x + dx])
            for p in pieces_for(has):
                put(art[p][ph % len(art[p])][(x % 4, y % 4)], x, y)
    return im
