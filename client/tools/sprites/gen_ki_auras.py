#!/usr/bin/env python3
"""Golden Ki and Crimson Blaze, two new oblique ground auras of client pair 72 (O577; client/MANIFEST.md "Pair 72", "Ki auras").

    python3 -I gen_ki_auras.py check                       # table, sums and sheets against their own rules (CI; needs Pillow and numpy for the sheets)
    python3 -I gen_ki_auras.py art [--write]               # draw the sheets (art_import/ki_auras/KEY.png); --write saves them, --check compares
    python3 -I gen_ki_auras.py art --check                 # the committed sheets are what the tool draws (a few pixels per cell may differ: libm)
    python3 -I gen_ki_auras.py sums [--check]              # art_import/ki_auras.sums (a digest per outfit) from the sheets
    python3 -I gen_ki_auras.py build DAT SPR OUT_DIR       # a pair with the 3,524 outfits of pair 72 (gen_fun_costumes.py build) in, 3525 and 3526 appended
    python3 -I gen_ki_auras.py build71 DAT71 SPR71 OUT_DIR # pair 71 in, the whole pair 72 out: gen_fun_costumes.py build, then `build`
    python3 -I gen_ki_auras.py live DAT SPR                # the pair holds both outfits at their ids, as the sums say (CI job "Live sprite pair")

Owner 2026-11-14 (pt-BR): "esses dois efeitos nao estao obliquos, troque por outros". The old Golden Ki (outfit 1511) and Crimson Blaze
(1512) are one tall flame drawn straight up, in the side view of a fighting game, and sit beside the character. These two replace them
for the auras 6 and 7 (server/data/XML/chaos_auras_pair72.csv, config.lua chaosClientPair >= 72); the old outfits stay in the pair.

Built like the stock 3x3 ground auras 1518 and 1521 (client/MANIFEST.md "Aura displacement"): one idle-type group, 3x3 tiles (exact 96), no
flags, no displacement (the client centres a 3x3 aura frame on the tile), 4 directions (all four the same pictures: the sprite records
are shared), **24 phases** and **2 layers**: layer 0 is drawn under the body, layer 1 over it (the client's aura back and front layers).
The art is ours, drawn by script (`draw`), not by PixelLab: a round ground ring (the other ground auras are round, 0.9 to 1.1) centred
on the feet point of docs/SPRITE_STYLE.md (tile 14, 20: frame 46, 52), with a crown of flames rising from it. The flames are a heat field:
tongue shapes (tall at the sides, short at the back and the front) eroded by value noise that scrolls upward one lattice period in 24
phases, so the loop closes exactly; the heat is cut into 6 colour bands. The ring and the flames based on its back and sides are layer 0; the flames
based on the front of the ring (more than 8 px under the feet point) and the embers drifting there are layer 1. Hard alpha, 1:1 pixels.
"""
import csv
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SHEETS = os.path.join(ART, 'ki_auras')
TABLE = os.path.join(ART, 'ki_auras.csv')
SUMS = os.path.join(ART, 'ki_auras.sums')
HEADER = ['new', 'key', 'name', 'kind', 'tiles', 'layers', 'phases', 'flags', 'ms', 'src']
PAIR = 72
FIRST_NEW = 3525          # after the 14 outfits 3511-3524 of gen_fun_costumes.py
CELL = 96
PHASES = 24
LAYERS = 2
CENTRE = (46.0, 52.0)     # the feet point of docs/SPRITE_STYLE.md (tile 14, 20) in the 96 px frame, the client puts the frame centre (48, 48) on the tile centre
RING_R = 27.0
TAU = 2 * math.pi
ART_TOL = 24              # pixels of a cell that may differ between the committed sheet and a redraw (libm differences at a threshold)
OLD_LOOKS = {'ki_gold': 1511, 'ki_blaze': 1512}
AURA_IDS = {'ki_gold': 6, 'ki_blaze': 7}

STYLES = {
    'ki_gold': dict(
        # rim, outer, mid, bright, core, white
        pal=[(120, 60, 0), (206, 130, 6), (246, 184, 22), (255, 224, 80), (255, 246, 170), (255, 255, 238)],
        thr=(0.06, 0.16, 0.30, 0.44, 0.58, 0.74),
        ring=[(110, 54, 0), (206, 130, 8), (255, 222, 76), (255, 253, 214)],
        n=17, n2=12, hmax=42, hmin=18, w=8.0, lean=5.0, sway=1.5, seed=7, kn=0.50, q=0.9, inner_scale=0.60,
        embers=16, ember_rise=44, dashes=16),
    'ki_blaze': dict(
        pal=[(60, 0, 10), (140, 8, 24), (208, 38, 28), (244, 94, 40), (255, 162, 86), (255, 228, 178)],
        thr=(0.06, 0.16, 0.30, 0.46, 0.62, 0.80),
        ring=[(52, 0, 8), (150, 14, 24), (236, 70, 36), (255, 196, 128)],
        n=14, n2=10, hmax=40, hmin=16, w=10.0, lean=8.0, sway=3.0, seed=23, kn=0.62, q=0.7, inner_scale=0.62,
        embers=26, ember_rise=46, dashes=0),
}


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_sums(path=SUMS):
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding='utf-8'):
            line = line.strip()
            if line and not line.startswith('#'):
                k, v = line.split()
                out[k] = v
    return out


def problems(table=None, sums=None, first=FIRST_NEW):
    """what is wrong with the table: header, ids in a row from the first new outfit, keys once and styled, the shape, the sums rows"""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out, seen = [], set()
    for i, r in enumerate(t):
        k = r['key']
        if int(r['new']) != first + i:
            out.append('%s: new id %s, the row at line %d must be %d' % (k, r['new'], i, first + i))
        if k in seen:
            out.append('%s is on two rows' % k)
        seen.add(k)
        if k not in STYLES:
            out.append('%s: no style in gen_ki_auras.py' % k)
        if r['kind'] != 'aura' or int(r['tiles']) != 3 or int(r['layers']) != LAYERS or int(r['phases']) != PHASES:
            out.append('%s: an aura here is 3x3 tiles, %d layers, %d phases (row: %s, %s, %s, %s)' % (k, LAYERS, PHASES, r['kind'], r['tiles'], r['layers'], r['phases']))
        if r['flags']:
            out.append('%s: no flags (the stock 3x3 ground auras have none)' % k)
        if not r['name'].strip():
            out.append('%s: no name' % k)
        if not 40 <= int(r['ms']) <= 200:
            out.append('%s: %s ms a phase is outside 40..200' % (k, r['ms']))
        if r['new'] not in s:
            out.append('%s: no row %s in ki_auras.sums' % (k, r['new']))
    for k in s:
        if k not in {r['new'] for r in t}:
            out.append('ki_auras.sums has a row for outfit %s that is not in the table' % k)
    return out


# ---------------------------------------------------------------- the drawing

_grid = {}


def grid():
    import numpy as np
    if not _grid:
        yy, xx = np.mgrid[0:CELL, 0:CELL]
        _grid['x'] = xx.astype(float) + 0.5
        _grid['y'] = yy.astype(float) + 0.5
    return _grid['x'], _grid['y']


def lcg(seed):
    """a tiny deterministic generator (no numpy RandomState: the sheets must not depend on a library's stream)"""
    s = seed & 0x7fffffff
    while True:
        s = (s * 1103515245 + 12345) & 0x7fffffff
        yield s / 2147483648.0


def noise_table(seed, nx, ny):
    import numpy as np
    r = lcg(seed)
    return np.array([[next(r) for _ in range(ny)] for _ in range(nx)])


def value_noise(tab, cw, ch, scroll, ny):
    """value noise on a lattice of cw x ch px cells, ny rows, periodic in y: the pattern moves up by `scroll` px; scroll = ny * ch at the
    end of the cycle brings the same picture back"""
    import numpy as np
    xx, yy = grid()
    u = xx / cw
    v = (yy + scroll) / ch
    ix = np.floor(u).astype(int)
    iy = np.floor(v).astype(int)
    fx = u - ix
    fy = v - iy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    nx = tab.shape[0]
    a = tab[ix % nx, iy % ny]
    b = tab[(ix + 1) % nx, iy % ny]
    c = tab[ix % nx, (iy + 1) % ny]
    d = tab[(ix + 1) % nx, (iy + 1) % ny]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


_tabs = {}


def tabs():
    if not _tabs:
        _tabs['n'] = (noise_table(11, 24, 6), noise_table(12, 48, 12))
    return _tabs['n']


def make_tongues(st):
    """the flame sources: two ranks on the ring (outer on the ring, inner 5 px inside, shorter); tall at the sides, short at the back and
    the front. `front` marks the ones whose base lies in the front half (layer 1)."""
    rnd = lcg(st['seed'])
    out = []
    for rank, (n, rad, hs) in enumerate(((st['n'], RING_R, 1.0), (st['n2'], RING_R - 5.0, st['inner_scale']))):
        for i in range(n):
            th = (i + 0.7 * next(rnd)) * TAU / n + (0.3 if rank == 0 else 0.9)
            c, s = math.cos(th), math.sin(th)
            bx, by = CENTRE[0] + rad * c, CENTRE[1] + rad * s
            side = abs(c) ** 1.2
            h0 = (st['hmin'] + (st['hmax'] - st['hmin']) * side) * hs
            h0 *= 0.85 + 0.3 * next(rnd)
            h0 = min(h0, by - 3)
            out.append(dict(
                bx=bx, by=by, h0=h0, w=st['w'] * (0.8 + 0.4 * next(rnd)) * (0.8 if rank else 1.0),
                lean=st['lean'] * c * (0.5 + 0.9 * next(rnd)) + (next(rnd) - 0.5) * 3,
                f1=1 + int(next(rnd) * 3), f2=2 + int(next(rnd) * 2),
                p1=next(rnd), p2=next(rnd), p3=next(rnd), fs=1 + int(next(rnd) * 2), front=s > 0.30))
    return out


def heat_field(st, ph, front):
    import numpy as np
    xx, yy = grid()
    tt = ph / PHASES
    env = np.zeros((CELL, CELL))
    sbest = np.zeros((CELL, CELL))
    for t in make_tongues(st):
        if t['front'] != front:
            continue
        H = t['h0'] * (1 + 0.14 * math.sin(TAU * (t['f1'] * tt + t['p1'])) + 0.08 * math.sin(TAU * (t['f2'] * tt + t['p2'])))
        H = min(H, t['by'] - 2)
        lean = t['lean'] * (1 + 0.3 * math.sin(TAU * (tt + t['p3'])))
        s = (t['by'] + 2.0 - yy) / H
        sc = np.clip(s, 0, 1)
        xc = lean * sc ** 1.4 + st['sway'] * np.sin(TAU * (t['fs'] * tt) - 3.2 * sc + t['p3'] * TAU) * sc
        hw = t['w'] * (1 - 0.65 * sc) + 0.5
        e = np.clip(1 - np.abs(xx - t['bx'] - xc) / hw, 0, 1) * np.clip(1 - sc ** 1.3, 0, 1) ** st['q']
        e = np.where(s >= 0, e, 0)
        better = e > env
        env = np.where(better, e, env)
        sbest = np.where(better, sc, sbest)
    ta, tb = tabs()
    n = 0.65 * value_noise(ta, 6.0, 6.0, 6 * 6.0 / PHASES * ph, 6) + 0.35 * value_noise(tb, 3.0, 3.0, 12 * 3.0 / PHASES * ph, 12)
    return env - st['kn'] * n * (0.25 + 0.9 * sbest) * (env > 0)


def flame_layer(st, ph, front):
    import numpy as np
    im = np.zeros((CELL, CELL, 4), np.uint8)
    heat = heat_field(st, ph, front)
    for thr, col in zip(st['thr'], st['pal']):
        im[heat > thr] = (*col, 255)
    return im


def ring_layer(st, ph):
    """the ground ring: a dark rim, an orange band, a bright core line with two light spots running round once in the cycle; the gold ring
    has a dashed inner ring turning the other way (one dash step in the cycle)"""
    import numpy as np
    xx, yy = grid()
    cx, cy = CENTRE
    d = np.hypot(xx - cx, yy - cy)
    a = np.arctan2(yy - cy, xx - cx)
    im = np.zeros((CELL, CELL, 4), np.uint8)
    rc = st['ring']
    dd = np.abs(d - RING_R)
    im[dd <= 2.5] = (*rc[0], 255)
    im[dd <= 1.6] = (*rc[1], 255)
    core = dd <= 0.9
    im[core] = (*rc[2], 255)
    hl = np.cos(a - TAU * ph / PHASES)
    hl2 = np.cos(a - TAU * ph / PHASES - math.pi)
    im[core & ((hl > 0.82) | (hl2 > 0.92))] = (*rc[3], 255)
    if st['dashes']:
        k = st['dashes']
        inner = np.abs(d - (RING_R - 8.0)) <= 0.5
        dash = ((a / TAU * k + 1.0 - ph / PHASES) % 1.0) < 0.5
        im[inner & dash] = (*rc[1], 255)
    return im


def ember_layer(st, ph, front):
    """sparks that rise from the ring and shrink: 2 px, then 1 px, hot to dull; each is one trip in the cycle (the picture closes)"""
    import numpy as np
    rnd = lcg(st['seed'] * 31 + 5)
    pal = st['pal']
    im = np.zeros((CELL, CELL, 4), np.uint8)
    for _ in range(st['embers']):
        th = next(rnd) * TAU
        off = next(rnd)
        rise = st['ember_rise'] * (0.6 + 0.6 * next(rnd))
        dr = (next(rnd) - 0.5) * 8
        ph0 = next(rnd)
        next(rnd)
        if (math.sin(th) > 0.2) != front:
            continue
        u = (ph / PHASES + off) % 1.0
        r0 = RING_R * (0.35 + 0.65 * abs(math.cos(th)) ** 0.5)
        bx = CENTRE[0] + r0 * math.cos(th) + dr * u + 2.5 * math.sin(TAU * (u * 2 + ph0))
        by = CENTRE[1] + r0 * math.sin(th) * 0.9 - rise * u
        if u > 0.92 or by < 2:
            continue
        size = 2 if u < 0.45 else 1
        col = pal[4] if u < 0.2 else (pal[3] if u < 0.5 else pal[2])
        x0, y0 = int(round(bx)), int(round(by))
        for yo in range(size):
            for xo in range(size):
                x, y = x0 + xo, y0 + yo
                if 0 <= x < CELL and 0 <= y < CELL:
                    im[y, x] = (*col, 255)
    return im


def over(base, top):
    m = top[..., 3] > 0
    base[m] = top[m]
    return base


def draw(key, ph):
    """(layer 0, layer 1) of one phase, 96 x 96 RGBA: layer 0 under the body (ring, back and side flames, embers behind), layer 1 over it
    (the flames of the front half of the ring and the embers there)"""
    st = STYLES[key]
    back = ring_layer(st, ph)
    over(back, flame_layer(st, ph, False))
    over(back, ember_layer(st, ph, False))
    front = flame_layer(st, ph, True)
    over(front, ember_layer(st, ph, True))
    return back, front


def frames_of_key(key):
    out = {}
    for ph in range(PHASES):
        b, f = draw(key, ph)
        out[(0, ph)] = b
        out[(1, ph)] = f
    return out


# ---------------------------------------------------------------- sheets: one PNG per outfit, a row per layer

def sheet_path(key):
    return os.path.join(SHEETS, key + '.png')


def write_sheet(key, frames, path=None):
    import numpy as np
    from PIL import Image
    im = np.zeros((LAYERS * CELL, PHASES * CELL, 4), np.uint8)
    for (layer, ph), a in frames.items():
        im[layer * CELL:(layer + 1) * CELL, ph * CELL:(ph + 1) * CELL] = a
    Image.fromarray(im).save(path or sheet_path(key), optimize=True)


def read_sheet(r):
    import numpy as np
    from PIL import Image
    im = np.array(Image.open(sheet_path(r['key'])).convert('RGBA'))
    if im.shape != (LAYERS * CELL, PHASES * CELL, 4):
        raise SystemExit('%s: sheet is %s, expected %s' % (r['key'], im.shape, (LAYERS * CELL, PHASES * CELL, 4)))
    return {(l, p): im[l * CELL:(l + 1) * CELL, p * CELL:(p + 1) * CELL].copy() for l in range(LAYERS) for p in range(PHASES)}


def clean(a):
    import numpy as np
    return np.where(a[..., 3:4] > 0, a, 0).astype(np.uint8)


def art(write):
    out = {}
    for r in rows():
        out[r['key']] = frames_of_key(r['key'])
    if write:
        os.makedirs(SHEETS, exist_ok=True)
        for k, fr in out.items():
            write_sheet(k, fr)
    return out


def figure_problems(r, fr):
    """the rules of a ground aura of ours: nothing empty, hard alpha, inside the cell with a margin, centred on the feet point, round
    enough, and a loop that closes (the step from the last phase to the first is not bigger than the usual step)"""
    import numpy as np
    k = r['key']
    out = []
    for (layer, ph), a in sorted(fr.items()):
        if a.shape != (CELL, CELL, 4):
            return ['%s: cell %s is %s' % (k, (layer, ph), a.shape)]
        if ((a[..., 3] != 0) & (a[..., 3] != 255)).any():
            out.append('%s: cell %s has soft alpha' % (k, (layer, ph)))
            break
    for layer in range(LAYERS):
        if not any((fr[(layer, p)][..., 3] > 0).any() for p in range(PHASES)):
            out.append('%s: layer %d is empty' % (k, layer))
    x0 = y0 = 10 ** 6
    x1 = y1 = -1
    for a in fr.values():
        ys, xs = np.nonzero(a[..., 3] > 0)
        if len(xs):
            x0, x1, y0, y1 = min(x0, int(xs.min())), max(x1, int(xs.max())), min(y0, int(ys.min())), max(y1, int(ys.max()))
    if x1 < 0:
        return out + ['%s: empty sheet' % k]
    w, h = x1 - x0 + 1, y1 - y0 + 1
    if x0 < 1 or y0 < 1 or x1 > CELL - 2 or y1 > CELL - 2:
        out.append('%s: art box %d,%d..%d,%d touches the edge of the cell' % (k, x0, y0, x1, y1))
    if not 56 <= w <= 84 or not 64 <= h <= 90:
        out.append('%s: art box %dx%d outside 56..84 x 64..90 (the stock ground auras are 67..76)' % (k, w, h))
    if abs((x0 + x1) / 2.0 - CENTRE[0]) > 4:
        out.append('%s: art box centre x %.1f, the feet point is %.0f' % (k, (x0 + x1) / 2.0, CENTRE[0]))
    # the ring itself (layer 0, the lowest rows): its lowest row is the ring's front rim, 27 + 2 px under the centre
    low = max(int(np.nonzero(fr[(0, p)][..., 3].any(axis=1))[0].max()) for p in range(PHASES))
    if abs(low - (CENTRE[1] + RING_R + 2.5)) > 2:
        out.append('%s: the ring ends on row %d, it should end on row %d' % (k, low, CENTRE[1] + RING_R + 2.5))
    comp = []
    for p in range(PHASES):
        c = fr[(0, p)].copy()
        m = fr[(1, p)][..., 3] > 0
        c[m] = fr[(1, p)][m]
        comp.append(c)
    steps = [float((comp[p] != comp[(p + 1) % PHASES]).any(axis=2).mean()) for p in range(PHASES)]
    med = sorted(steps[:-1])[len(steps[:-1]) // 2]
    if med < 0.01:
        out.append('%s: median step between phases %.4f of the cell: it would not animate' % (k, med))
    if steps[-1] > 1.6 * max(steps[:-1]) or steps[-1] > 2.5 * med:
        out.append('%s: the step from the last phase to the first (%.4f) is bigger than the usual one (median %.4f): the loop jumps' % (k, steps[-1], med))
    if len({a.tobytes() for a in comp}) < PHASES:
        out.append('%s: only %d different phases of %d' % (k, len({a.tobytes() for a in comp}), PHASES))
    return out


def art_check():
    """every sheet is a valid cell grid, passes the figure rules, and is what `draw` gives (a few pixels per cell may differ)"""
    import numpy as np
    out = []
    for r in rows():
        if not os.path.exists(sheet_path(r['key'])):
            out.append('%s: no sheet %s' % (r['key'], sheet_path(r['key'])))
            continue
        fr = read_sheet(r)
        if r['key'] in STYLES:
            for (layer, ph), a in sorted(fr.items()):
                want = draw(r['key'], ph)[layer]
                diff = int((a != want).any(axis=2).sum())
                if diff > ART_TOL:
                    out.append('%s: layer %d phase %d differs from draw() in %d pixels (tolerance %d)' % (r['key'], layer, ph, diff, ART_TOL))
                    break
        out += figure_problems(r, fr)
    return out


# ---------------------------------------------------------------- the outfit of a row

def groups_of(r, frames):
    """[(Group, [tile arrays in slot order])] of one aura: 3x3, 4 directions (the same pictures), 2 layers, 24 phases; the slot order of
    the dat is phase, direction, layer, row, column"""
    sys.path.insert(0, HERE)
    from import_outfits import Group
    from gen_effects import tiles_of
    ms = int(r['ms'])
    g = Group()
    g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases = 0, 3, 3, CELL, LAYERS, 4, 1, 1, PHASES
    g.anim = (0, 0, 0, tuple([ms, ms] * PHASES))
    tiles = []
    for ph in range(PHASES):
        for _d in range(4):
            for layer in range(LAYERS):
                tl = tiles_of(frames[(layer, ph)], 3, 3)
                for hh in range(3):
                    for ww in range(3):
                        tiles.append(tl[(ww, hh)])
    g.sprites = tuple(range(len(tiles)))
    return [(g, tiles)]


def row_specs(r):
    return groups_of(r, read_sheet(r))


def sums_text(table=None):
    sys.path.insert(0, HERE)
    import gen_fun_costumes as F
    t = rows() if table is None else table
    lines = ['# ki_auras.sums: sha256 of every outfit of the Ki auras of pair 72 (group shapes, animator, sprite slots); gen_ki_auras.py sums',
             '# written by gen_ki_auras.py sums; checked by `check`, and by `live` against a built pair']
    for r in t:
        lines.append('%s %s' % (r['new'], F.spec_digest(row_specs(r))))
    return '\n'.join(lines) + '\n'


# ---------------------------------------------------------------- the pair

def build(dat, spr, out_dir, table=None, first=FIRST_NEW, log=print):
    """a pair with the outfits up to first - 1 in (the output of gen_fun_costumes.py build), the table's outfits appended, verified (the same
    code as gen_fun_costumes.build with this tool's group shape in place of its own)"""
    sys.path.insert(0, HERE)
    import gen_fun_costumes as F
    t = rows() if table is None else table
    saved = F.row_specs
    F.row_specs = row_specs
    try:
        return F.build(dat, spr, out_dir, table=t, first=first, log=log)
    finally:
        F.row_specs = saved


def build71(dat, spr, out_dir, log=print):
    """pair 71 in, pair 72 out: the fun costumes first, then these two auras; the half-way pair is removed"""
    sys.path.insert(0, HERE)
    import gen_fun_costumes as F
    half = out_dir.rstrip('/') + '.half'
    if os.path.exists(out_dir) or os.path.exists(half):
        raise SystemExit('%s or %s exists: remove it or name another folder' % (out_dir, half))
    F.build(dat, spr, half, expect_md5=F.DAT_71_MD5, log=log)
    try:
        ids = build(os.path.join(half, 'Tibia.dat'), os.path.join(half, 'Tibia.spr'), out_dir, log=log)
    finally:
        shutil.rmtree(half, ignore_errors=True)
    return ids


def live(dat, spr, table=None, sums=None, first=FIRST_NEW, log=print):
    """the pair holds every outfit at its id, its digest the one of the sums file. Returns the problem lines."""
    sys.path.insert(0, HERE)
    import gen_fun_costumes as F
    from datspr import Dat, Spr
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    d, sp = Dat(dat), Spr(spr)
    if len(d.outfits) < first + len(t) - 1:
        return ['the pair has %d outfits, the Ki auras end at %d' % (len(d.outfits), first + len(t) - 1)]
    out = []
    for r in t:
        if F.digest(d, sp, int(r['new'])) != s.get(r['new']):
            out.append('outfit %s (%s): the pictures are not the ones of ki_auras.sums' % (r['new'], r['key']))
    log('live: %d outfits %d to %d checked, %d problems' % (len(t), first, first + len(t) - 1, len(out)))
    return out


def main(argv):
    args = list(argv)
    cmd = args.pop(0) if args else ''
    if cmd == 'check':
        p = problems()
        try:
            p += art_check()
            if sums_text() != open(SUMS, encoding='utf-8').read():
                p.append('ki_auras.sums is not what the sheets give (gen_ki_auras.py sums)')
        except ImportError:
            print('check: Pillow and numpy missing, the sheets were not read')
        for line in p:
            print('PROBLEM', line)
        print('ki_auras: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if cmd == 'art':
        if '--check' in args:
            p = art_check()
            for line in p:
                print('PROBLEM', line)
            print('ki_auras sheets: %d problems' % len(p))
            return 1 if p else 0
        out = art('--write' in args)
        for r in rows():
            print('%s %-9s %s' % (r['new'], r['key'], ''.join('\n   ' + x for x in figure_problems(r, out[r['key']]))))
        return 0
    if cmd == 'sums':
        text = sums_text()
        if '--check' in args:
            old = open(SUMS, encoding='utf-8').read() if os.path.exists(SUMS) else None
            if old != text:
                print('PROBLEM ki_auras.sums is not what the sheets give')
                return 1
            print('ki_auras.sums: up to date')
            return 0
        with open(SUMS, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        return 0
    if cmd in ('build', 'build71') and len(args) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = (build if cmd == 'build' else build71)(args[0], args[1], args[2])
        print('built %d outfits %d to %d' % (len(ids), ids[0], ids[-1]))
        return 0
    if cmd == 'live' and len(args) == 2:
        p = live(args[0], args[1])
        for line in p:
            print('PROBLEM', line)
        return 1 if p else 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
