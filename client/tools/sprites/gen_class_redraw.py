#!/usr/bin/env python3
"""Class outfits drawn again at the stock bar (O618, pilot; client/MANIFEST.md "Class outfits redrawn (O618)").

    python3 -I gen_class_redraw.py check                       # table, sums and sheets against the rules (CI; needs Pillow and numpy)
    python3 -I gen_class_redraw.py art --src DIR [--write]     # the PixelLab downloads of DIR/KEY -> art_import/class_redraw/KEY.png
    python3 -I gen_class_redraw.py sums [--check]              # art_import/class_redraw.sums (a digest per sheet)
    python3 -I gen_class_redraw.py numbers                     # the audit numbers of every sheet (lean, height, rim, walk, mask)
    python3 -I gen_class_redraw.py build DAT SPR OUT_DIR       # the looks of the table rewritten in place (import_art_things.py, mode=replace)
    python3 -I gen_class_redraw.py live DAT SPR                # a built pair holds every look of the table as its sheet says

Owner 2026-11-17: the class outfits that miss the stock bar are drawn again, same name and theme. The O610 audit names them:
the ten donor B class outfits 1551 to 1560 (upright camera, too tall, 3x3 tiles, no outline, no colour template) and every
class outfit that walks in 2 pictures (1505-1510, 2039-2044, 2060-2064, 2067-2072, 2078-2081; 2043 is unused and stays). A row of
art_import/class_redraw.csv is one drawing and the looks it fills (`looks`: ids joined by +; a class look that was a copy of a
class outfit gets the same sheet: 2069 = 1505, 2070 = 1506, 2071 = 1508, 2072 = 1510).

The art is ours: PixelLab characters (docs/CREDITS.md, Tools) drawn from the words of the row's `prompt` alone, in the
tool's oblique view (the game's camera: the figure leans up and left), `standard` mode, 4 directions, size 44 or 52, and its v3
walk of 8 pictures a direction (the standing picture is the end frame, so the walk loops). No picture of the old look goes
to the tool, and nothing is held in the hands (a held weapon comes and goes between pictures). This script only places and cleans:
  hard alpha; the walk's colours pulled back to the standing pictures (fun_costume_motion.lock_palette);
  a dark outline on the whole rim (a rim pixel brighter than RIM_LUMA is darkened);
  the look moved by whole pixels (one move for all four directions) so it stands on the O585 point (x 16.5, y 20 of
  the tile; the row's `disp` is the dat displacement: 8 like the stock looks, lower when the walk needs the room);
  the colour template: the pixels of the row's accent become grey in the art and head / body / legs / feet in the template
  by where they sit along the figure (yellow, red, green, blue; the client multiplies them by the player's colours). `accent`
  is hue ranges joined by +: LO-HI degrees (it may wrap through 0), LO-HI@SATMIN for a range that must stay clear of skin,
  `white` for pale cloth and plate;
  `idle` 4: a breath of 4 pictures (the standing picture one row taller in the middle phases; the old looks 2060 / 2061, 2062 /
  2063, 2067 / 2068 had an idle of their own), else one picture;
  `addons` templar | monk: the two addon overlays (pattern y 1 and 2) drawn by script on every placed picture (templar: a halo, two
  ice crystals on the shoulders; monk: a red headband with tails, a staff across the back). The server gives every class look both
  addons, so they are always on; the overlays carry no template.
The sheet is the import_art_things.py outfit layout: 2x2 tiles, rows idle (1 or 4 phases) then walk (8 phases), columns
(addon * 2 + layer) * 4 + direction (north, east, south, west; art then template; addon 0 is the body).
"""
import colorsys
import csv
import hashlib
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SHEETS = os.path.join(ART, 'class_redraw')
TABLE = os.path.join(ART, 'class_redraw.csv')
SUMS = os.path.join(ART, 'class_redraw.sums')
HEADER = ['key', 'name', 'looks', 'walk', 'ms', 'disp', 'accent', 'anim', 'idle', 'addons', 'prompt']
IDLES = (1, 4)               # idle phases: one picture, or a breath of 4 (the old look had an idle of its own)
IDLE_MS = 600
ADDONS = ('0', 'templar', 'monk')   # the addon kind of a row: 0 none, else the two overlays of ADDON_KINDS
DIR_NAMES = ('north', 'east', 'south', 'west')      # engine order of patternX
CELL = 64
CANVAS = 128
MAX_DISP = 8                # the stock player displacement; a row's is lower when its walk needs the room right and below
TARGET = (16.5, 20.0)       # the O585 standing point, px from the top left of the creature's tile
WALK = 8
RIM_LUMA = 40
MAX_CLIPPED = 4             # pixels of a whole look that may fall over the edge of the 64 px frame at displacement 0 (a weapon tip)
ZONES = ((0.30, (255, 255, 0)), (0.62, (255, 0, 0)), (0.86, (0, 255, 0)), (9.0, (0, 0, 255)))   # head, body, legs, feet
# the stock bar (O610 flags.py): what `check` holds every sheet to
LEAN = (9.0, 22.0)          # px, the body's bottom quarter right of its top quarter (stock 13 to 18; per direction it spreads)
HEIGHT = (28, 44)           # px, the standing south picture
MIRROR_MAX = 0.65           # east must not be the mirrored west
RIM_MIN = 0.88
SAT_MIN = 0.32              # accent pixels are at least this saturated (a range can ask for more: 15-35@0.6 keeps skin out)
MASK_MIN = 0.03             # share of the body the template colours (the mean of the four standing pictures)


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def looks_of(r):
    return [int(v) for v in r['looks'].split('+')]


def read_sums(path=SUMS):
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding='utf-8'):
            line = line.strip()
            if line and not line.startswith('#'):
                k, v = line.split()
                out[k] = v
    return out


def accents_of(r):
    """the hue ranges of a row's accent: LO-HI[@SATMIN] joined by + (cloth, leather, hair ...), degrees; a range may wrap through 0;
    `white` is the pale, unsaturated cloth (robes)"""
    out = []
    for part in r['accent'].split('+'):
        if part == 'white':
            out.append(('white',))
            continue
        rng, _, smin = part.partition('@')
        lo, hi = (float(v) for v in rng.split('-'))
        out.append((lo, hi, float(smin) if smin else SAT_MIN))
    return out


def n_idle(r):
    return int(r.get('idle') or 1)


def n_addons(r):
    return 1 if (r.get('addons') or '0') == '0' else 3


def problems(table=None, sums=None):
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out, keys, looks = [], set(), set()
    for r in t:
        k = r['key']
        if k in keys:
            out.append('%s is on two rows' % k)
        keys.add(k)
        if not r['name'].strip() or not r['prompt'].strip():
            out.append('%s: a row needs a name and the words it was drawn from' % k)
        try:
            ids = looks_of(r)
        except ValueError:
            out.append('%s: looks %r is not ids joined by +' % (k, r['looks']))
            continue
        for i in ids:
            if i in looks:
                out.append('%s: look %d is on two rows' % (k, i))
            looks.add(i)
        if int(r['walk']) != WALK:
            out.append('%s: the walk has %d pictures (row: %s)' % (k, WALK, r['walk']))
        if not 0 <= int(r['disp']) <= MAX_DISP:
            out.append('%s: disp %s is not 0 to %d' % (k, r['disp'], MAX_DISP))
        if int(r['ms']) < 40:
            out.append('%s: %s ms a phase is too fast' % (k, r['ms']))
        try:
            for rg in accents_of(r):
                if rg != ('white',) and not (0 <= rg[0] < 360 and 0 <= rg[1] < 360 and 0 <= rg[2] <= 1):
                    raise ValueError
        except ValueError:
            out.append('%s: accent %r is not a hue range LO-HI in degrees' % (k, r['accent']))
        if n_idle(r) not in IDLES:
            out.append('%s: idle %s is not %s phases' % (k, r.get('idle'), '/'.join(map(str, IDLES))))
        if (r.get('addons') or '0') not in ADDONS:
            out.append('%s: addons %r is not one of %s' % (k, r.get('addons'), ADDONS))
        if k not in s:
            out.append('%s: no row in class_redraw.sums' % k)
    for k in s:
        if k not in keys:
            out.append('class_redraw.sums has a row for %s that is not in the table' % k)
    return out


# ---------------------------------------------------------------- pictures

def luma(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def rim_of(m):
    import numpy as np
    p = np.pad(m, 1)
    inner = p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return m & ~inner


def outline(a):
    """a dark outline on the whole rim: a rim pixel brighter than RIM_LUMA keeps its hue at a luma under it"""
    import numpy as np
    b = a.copy()
    m = b[..., 3] > 0
    lum = luma(b[..., :3].astype(np.float64))
    fix = rim_of(m) & (lum >= RIM_LUMA)
    if fix.any():
        k = (RIM_LUMA - 8) / np.maximum(lum[fix], 1.0)
        b[fix, :3] = np.floor(b[fix, :3] * k[:, None]).astype(np.uint8)
    return b


def crop(a):
    import numpy as np
    ys, xs = np.nonzero(a[..., 3] > 0)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def lean(a):
    """O610 audit.py `lean`: the centroid of the bottom quarter right of the top quarter's, px"""
    import numpy as np
    c = crop(a)
    m = c[..., 3] > 0
    k = max(1, m.shape[0] // 4)
    xs = np.arange(m.shape[1])
    top, bot = m[:k], m[-k:]
    return float((bot.sum(0) * xs).sum() / bot.sum() - (top.sum(0) * xs).sum() / top.sum())


def rim_dark(a):
    c = crop(a)
    m = c[..., 3] > 0
    return float((luma(c[..., :3].astype(float))[rim_of(m)] < RIM_LUMA).mean())


def csim(a, b):
    """O610 audit.py `csim`: colour likeness of two cropped pictures centred on one canvas, 0..1"""
    import numpy as np
    H, W = max(a.shape[0], b.shape[0]), max(a.shape[1], b.shape[1])

    def put(p):
        c = np.zeros((H, W, 4), np.float32)
        oy, ox = (H - p.shape[0]) // 2, (W - p.shape[1]) // 2
        c[oy:oy + p.shape[0], ox:ox + p.shape[1]] = p
        return c
    A, B = put(a), put(b)
    ma, mb = A[..., 3] > 0, B[..., 3] > 0
    d = np.abs(A[..., :3] - B[..., :3]).mean(axis=2) / 255.0
    return float((1.0 - d)[ma & mb].sum() / (ma | mb).sum())


def feet_of(a):
    """(x, y) of the feet of a frame, gen_outfit_anchors.measure (the O585 measure)"""
    from gen_outfit_anchors import measure
    m = measure(a[..., 3])
    return m[0], m[1]


def stand_of(refs):
    """the standing point of a look in its download's canvas: the median of the four directions' feet (the O585 measure; one
    direction with a weapon under the feet does not pull it). PixelLab draws every direction around one pivot, so one move
    for the whole look keeps the turn on the spot."""
    import numpy as np
    feet = [feet_of(refs[d]) for d in DIR_NAMES]
    return float(np.median([f[0] for f in feet])), float(np.median([f[1] for f in feet]))


def place(frames, stand, disp):
    """the frames on 64 px cells, the look's standing point on the O585 point; -> (cells, pixels lost over the cell's edge)"""
    import numpy as np
    dx, dy = int(round(disp + 32 + TARGET[0] - stand[0])), int(round(disp + 32 + TARGET[1] - stand[1]))
    out, lost = [], 0
    for a in frames:
        c = np.zeros((CELL, CELL, 4), np.uint8)
        ys, xs = np.nonzero(a[..., 3] > 0)
        ty, tx = ys + dy, xs + dx
        ok = (ty >= 0) & (ty < CELL) & (tx >= 0) & (tx < CELL)
        lost += int((~ok).sum())
        c[ty[ok], tx[ok]] = a[ys[ok], xs[ok]]
        out.append(c)
    return out, lost


def accent_mask(a, ranges):
    """the pixels of the accent hues (saturated, not dark, off the rim)"""
    import numpy as np
    m = a[..., 3] > 0
    out = np.zeros(m.shape, bool)
    rim = rim_of(m)
    for y, x in zip(*np.nonzero(m & ~rim)):
        r, g, b = (int(v) / 255.0 for v in a[y, x, :3])
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        h *= 360.0
        hit = False
        for rg in ranges:
            if rg == ('white',):
                hit = hit or (s < 0.20 and v > 0.72)
            else:
                lo, hi, smin = rg
                hit = hit or (((lo <= h <= hi) if lo <= hi else (h >= lo or h <= hi)) and s >= smin and v >= 0.16)
        out[y, x] = hit
    return out


def template(a, ranges, top):
    """(art with the accent in grey, template layer) of a placed cell; `top` the brightest accent luma of the look"""
    import numpy as np
    acc = accent_mask(a, ranges)
    art, tpl = a.copy(), np.zeros_like(a)
    ys, xs = np.nonzero(a[..., 3] > 0)
    if not acc.any() or not len(ys):
        return art, tpl
    d = (xs + ys).astype(np.float64)
    d0, d1 = d.min(), d.max()
    lum = luma(a[..., :3].astype(np.float64))
    for y, x in zip(*np.nonzero(acc)):
        g = int(min(255, round(lum[y, x] * 235.0 / top)))
        art[y, x, :3] = (g, g, g)
        t = (x + y - d0) / max(1.0, d1 - d0)
        tpl[y, x] = next(c for lim, c in ZONES if t < lim) + (255,)
    return art, tpl


def load(path):
    import numpy as np
    from PIL import Image
    a = np.array(Image.open(path).convert('RGBA'))
    op = a[..., 3] >= 128
    a[..., 3] = np.where(op, 255, 0)
    a[~op] = 0
    # one canvas for every picture of a look: PixelLab grows an animation's canvas around the same middle
    c = np.zeros((CANVAS, CANVAS, 4), np.uint8)
    oy, ox = (CANVAS - a.shape[0]) // 2, (CANVAS - a.shape[1]) // 2
    c[oy:oy + a.shape[0], ox:ox + a.shape[1]] = a
    return c


# ---------------------------------------------------------------- addons: two overlays drawn by script on the placed pictures

def anchors(m):
    """head (x, top y) and feet (x, bottom y) of a placed picture's mask"""
    import numpy as np
    ys, xs = np.nonzero(m)
    y0, y1 = int(ys.min()), int(ys.max())
    return (float(xs[ys <= y0 + 2].mean()), y0), (float(xs[ys >= y1 - 2].mean()), y1), (int(xs.min()), int(xs.max()))


def _stamp(fill, pts):
    for x, y in pts:
        if 0 <= x < CELL and 0 <= y < CELL:
            fill[y, x] = True


def _finish(base, fills, rim):
    """overlay cell from [(fill mask, rgb)] drawn in order, then a dark `rim` colour on the 4-neighbours of every fill"""
    import numpy as np
    out = np.zeros((CELL, CELL, 4), np.uint8)
    every = np.zeros((CELL, CELL), bool)
    for f, _ in fills:
        every |= f
    p = np.pad(every, 1)
    grown = p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    out[grown & ~every] = rim + (255,)
    for f, col in fills:
        out[f] = col + (255,)
    return out


def addon_halo(base, d):
    import math
    import numpy as np
    (cx, y0), _, _ = anchors(base[..., 3] > 0)
    f = np.zeros((CELL, CELL), bool)
    _stamp(f, [(int(round(cx + 5 * math.cos(t / 20.0 * 2 * math.pi))), int(round(y0 - 3 + 1.6 * math.sin(t / 20.0 * 2 * math.pi)))) for t in range(20)])
    return _finish(base, [(f, (255, 218, 80))], (120, 78, 8))


def addon_shards(base, d):
    import numpy as np
    (cx, y0), _, _ = anchors(base[..., 3] > 0)
    f, hi = np.zeros((CELL, CELL), bool), np.zeros((CELL, CELL), bool)
    for sx, sy in ((cx - 7, y0 + 5), (cx + 6, y0 + 6)):
        sx, sy = int(round(sx)), int(round(sy))
        _stamp(f, [(sx, sy - 4), (sx, sy - 3), (sx - 1, sy - 2), (sx, sy - 2), (sx + 1, sy - 2), (sx - 1, sy - 1), (sx, sy - 1), (sx + 1, sy - 1), (sx, sy)])
        _stamp(hi, [(sx, sy - 3), (sx, sy - 2), (sx, sy - 1)])
    return _finish(base, [(f, (110, 190, 245)), (hi, (225, 248, 255))], (20, 56, 100))


def addon_headband(base, d):
    import numpy as np
    m = base[..., 3] > 0
    (cx, y0), _, _ = anchors(m)
    f, t = np.zeros((CELL, CELL), bool), np.zeros((CELL, CELL), bool)
    for y in (y0 + 3, y0 + 4):
        for x in range(CELL):
            if m[y, x] and abs(x - cx) <= 7:
                f[y, x] = True
    xs = np.nonzero(f)[1]
    if len(xs):
        x1 = int(xs.max())
        _stamp(t, [(x1 + 1, y0 + 4), (x1 + 2, y0 + 5), (x1 + 2, y0 + 6), (x1 + 3, y0 + 7), (x1 + 3, y0 + 8)])
    return _finish(base, [(f, (205, 40, 40)), (t, (205, 40, 40))], (70, 10, 10))


def addon_staff(base, d):
    import numpy as np
    m = base[..., 3] > 0
    (hx, hy), (fx, fy), _ = anchors(m)
    ux, uy = fx - hx, fy - (hy + 3)
    n = (ux * ux + uy * uy) ** 0.5 or 1.0
    ux, uy = ux / n, uy / n
    f = np.zeros((CELL, CELL), bool)
    for i in range(-6, int(n * 0.92)):
        x, y = int(round(hx + 7 + ux * i)), int(round(hy + 3 + uy * i))
        if 0 <= x < CELL and 0 <= y < CELL and (d == 0 or not m[y, x]):    # across the back: seen over the body from the north only
            f[y, x] = True
    return _finish(base, [(f, (170, 118, 62))], (62, 36, 14))


ADDON_KINDS = {'templar': (addon_halo, addon_shards), 'monk': (addon_headband, addon_staff)}


def walk_dir(st, anim, d):
    """the folder of the animation `anim` in direction d: one animation, or one per direction (named anim-GROUP8 when the names repeat)"""
    base = os.path.join(st, 'animations')
    for n in sorted(os.listdir(base)):
        if (n == anim or n.startswith(anim + '-')) and os.path.isdir(os.path.join(base, n, d)):
            return os.path.join(base, n, d)
    raise SystemExit('%s: no %s animation for %s' % (st, anim, d))


def make_sheet(r, src):
    """the sheet of a row from the PixelLab download SRC/KEY (rotations/DIR.png, animations/ANIM/DIR/frame_NNN.png)"""
    import numpy as np
    from fun_costume_motion import find_state, lock_palette, breath_cycle
    st = find_state(os.path.join(src, r['key']))
    refs = {d: load(os.path.join(st, 'rotations', d + '.png')) for d in DIR_NAMES}
    ranges = accents_of(r)
    ni, na = n_idle(r), n_addons(r)
    stand = stand_of(refs)
    todo = {}
    for d in DIR_NAMES:
        ad = walk_dir(st, r['anim'], d)
        names = sorted(n for n in os.listdir(ad) if n.endswith('.png'))
        if len(names) != WALK:
            raise SystemExit('%s: %s has %d walk pictures, %d wanted' % (r['key'], ad, len(names), WALK))
        walk = lock_palette([load(os.path.join(ad, n)) for n in names], list(refs.values()), 1)
        idle = breath_cycle(refs[d], ni) if ni > 1 else [refs[d]]
        todo[d] = [outline(a) for a in idle + walk]

    def lost_at(disp):
        return sum(place(todo[d], stand, disp)[1] for d in DIR_NAMES)
    best = next((v for v in range(MAX_DISP, -1, -1) if not lost_at(v)), None)
    if best is None and lost_at(0) <= MAX_CLIPPED:
        best = 0                        # a sword tip over the edge: the few pixels are cut, the look keeps its size
    if best is None:
        raise SystemExit('%s: %d pixels fall over the edge of the 64 px frame at displacement 0' % (r['key'], lost_at(0)))
    if r['disp'] == 'auto':
        r['disp'] = str(best)           # a new row: the highest displacement that loses no pixel (`art --write` stores it in the table)
    if int(r['disp']) != best:
        raise SystemExit('%s: disp %s, the highest displacement that loses no pixel is %d' % (r['key'], r['disp'], best))
    cells = {d: place(todo[d], stand, best)[0] for d in DIR_NAMES}
    top = 1.0
    for d in DIR_NAMES:
        for c in cells[d]:
            acc = accent_mask(c, ranges)
            if acc.any():
                top = max(top, float(luma(c[..., :3].astype(np.float64))[acc].max()))
    sheet = np.zeros(((ni + WALK) * CELL, 8 * na * CELL, 4), np.uint8)
    for x, d in enumerate(DIR_NAMES):
        for p, c in enumerate(cells[d]):
            art, tpl = template(c, ranges, top)
            sheet[p * CELL:(p + 1) * CELL, x * CELL:(x + 1) * CELL] = art
            sheet[p * CELL:(p + 1) * CELL, (4 + x) * CELL:(5 + x) * CELL] = tpl
            if na > 1:
                for y, paint in enumerate(ADDON_KINDS[r['addons']], 1):
                    sheet[p * CELL:(p + 1) * CELL, (y * 8 + x) * CELL:(y * 8 + x + 1) * CELL] = paint(c, x)
    return sheet


def sheet_path(key):
    return os.path.join(SHEETS, key + '.png')


def read_sheet(r):
    import numpy as np
    from PIL import Image
    a = np.array(Image.open(sheet_path(r['key'])).convert('RGBA'))
    if a.shape != ((n_idle(r) + WALK) * CELL, 8 * n_addons(r) * CELL, 4):
        raise SystemExit('%s: sheet is %s' % (r['key'], a.shape))
    return a


def cell(sheet, layer, x, p, y=0):
    c = (y * 8 + layer * 4 + x) * CELL
    return sheet[p * CELL:(p + 1) * CELL, c:c + CELL]


def tinted(sheet, x, p, colours):
    """a cell as the client draws it: the art, its template pixels multiplied by the player's colours (rgb per zone)"""
    import numpy as np
    art, tpl = cell(sheet, 0, x, p).copy(), cell(sheet, 1, x, p)
    for (_, zc), col in zip(ZONES, colours):
        m = (tpl[..., 3] > 0) & (tpl[..., :3] == np.array(zc, np.uint8)).all(axis=2)
        art[m, :3] = (art[m, :3].astype(np.int32) * np.array(col, np.int32) // 255).astype(np.uint8)
    return art


def numbers(r, sheet=None):
    """the O610 audit numbers of a sheet"""
    import numpy as np
    DISP = int(r['disp'])
    NI = n_idle(r)
    s = read_sheet(r) if sheet is None else sheet
    idle = [cell(s, 0, x, 0) for x in range(4)]
    N, E, S, W = idle
    body = S[..., 3] > 0
    px = np.concatenate([cell(s, 0, x, p)[cell(s, 0, x, p)[..., 3] > 0][:, :3] for x in range(4) for p in range(NI + WALK)])
    feet = [feet_of(c) for c in idle]
    return {'lean': [round(lean(c), 1) for c in idle], 'height': crop(S).shape[0], 'width': crop(S).shape[1],
            'mirror': round(csim(crop(W), crop(E)[:, ::-1]), 3),
            'rim': round(min(rim_dark(cell(s, 0, x, p)) for x in range(4) for p in range(NI + WALK)), 2),
            'walk': min(len({cell(s, 0, x, p).tobytes() for p in range(NI, NI + WALK)}) for x in range(4)),
            'dirs': len({c.tobytes() for c in idle}),
            'soft': int(((s[..., 3] > 0) & (s[..., 3] < 255)).sum()),
            'colours': len({tuple(v) for v in px}),
            'mask': round(float(np.mean([float((cell(s, 1, x, 0)[..., 3] > 0).sum()) / max(1, (cell(s, 0, x, 0)[..., 3] > 0).sum()) for x in range(4)])), 3),
            'zones': len({tuple(v) for x in range(4) for v in cell(s, 1, x, 0)[cell(s, 1, x, 0)[..., 3] > 0][:, :3]}),
            'mask_outside': int(sum(((cell(s, 1, x, p)[..., 3] > 0) & ~(cell(s, 0, x, p)[..., 3] > 0)).sum()
                                    for x in range(4) for p in range(NI + WALK))),
            'feet': [(fx - DISP - 32, fy - DISP - 32) for fx, fy in feet],
            'stand': (float(np.median([f[0] for f in feet])) - DISP - 32, float(np.median([f[1] for f in feet])) - DISP - 32)}


def sheet_problems(r, sheet=None):
    n = numbers(r, sheet)
    k, out = r['key'], []
    if n['dirs'] != 4:
        out.append('%s: %d different standing pictures, 4 wanted' % (k, n['dirs']))
    sl, el = n['lean'][2], n['lean'][1]
    if not LEAN[0] <= max(n['lean']) or min(n['lean']) < 0 or not (sl >= LEAN[0] or el >= LEAN[0]):
        out.append('%s: lean %s px, an oblique figure leans %s to %s' % (k, n['lean'], LEAN[0], LEAN[1]))
    if not HEIGHT[0] <= n['height'] <= HEIGHT[1]:
        out.append('%s: %d px tall, %d to %d wanted' % (k, n['height'], HEIGHT[0], HEIGHT[1]))
    if n['mirror'] >= MIRROR_MAX:
        out.append('%s: east is the mirrored west (%.2f)' % (k, n['mirror']))
    if n['rim'] < RIM_MIN:
        out.append('%s: %d%% of the rim is dark, %d%% wanted' % (k, round(100 * n['rim']), round(100 * RIM_MIN)))
    if n['walk'] != WALK:
        out.append('%s: the walk has %d different pictures in a direction' % (k, n['walk']))
    if n['soft']:
        out.append('%s: %d soft pixels' % (k, n['soft']))
    if n['mask'] < MASK_MIN or n['zones'] < 2:
        out.append('%s: the colour template covers %.0f%% of the body in %d zones' % (k, 100 * n['mask'], n['zones']))
    if n['mask_outside']:
        out.append('%s: %d template pixels outside the art' % (k, n['mask_outside']))
    if abs(n['stand'][0] - 16.5) > 1 or abs(n['stand'][1] - 20) > 1:
        out.append('%s: stands on %s, the O585 point is 16.5, 20' % (k, n['stand']))
    return out


def digest(key):
    return hashlib.sha256(open(sheet_path(key), 'rb').read()).hexdigest()[:16]


def sums_text():
    return '# key  sha256[:16] of art_import/class_redraw/KEY.png\n' + ''.join('%s %s\n' % (r['key'], digest(r['key'])) for r in rows())


# ---------------------------------------------------------------- the pair

FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id', 'extra']


def things_rows():
    out = []
    for r in rows():
        durs = '/'.join(['%s:%s' % (r['ms'], r['ms'])] * WALK)
        ni = n_idle(r)
        idle = ('|durs0=%s' % '/'.join(['%d:%d' % (IDLE_MS, IDLE_MS)] * ni)) if ni > 1 else ''
        for look in looks_of(r):
            out.append({'key': 'classredraw_%s_%d' % (r['key'], look), 'cat': 'outfit', 'kind': 'class', 'name': r['name'],
                        'atlas': 'class_redraw/' + r['key'], 'x': 0, 'y': 0, 'w': 2, 'h': 2, 'patterns': 4, 'phases': '%d+%d' % (ni, WALK),
                        'flags': 'displacement:%s:%s' % (r['disp'], r['disp']), 'mode': 'replace', 'server_id': '',
                        'extra': 'gtypes=0+1|layers=2|addons=%d|mounts=1|exact=64+64|durs1=%s|anim1=0:0:0%s|look=%d' % (n_addons(r), durs, idle, look)})
    return out


def build(dat, spr, out_dir):
    if os.path.exists(out_dir):
        raise SystemExit('%s exists' % out_dir)
    with tempfile.NamedTemporaryFile('w', suffix='.csv', dir=ART, delete=False, newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, FIELDS)
        w.writeheader()
        w.writerows(things_rows())
        things = f.name
    try:
        subprocess.check_call([sys.executable, '-I', os.path.join(HERE, 'import_art_things.py'), '--ours-dat', dat, '--ours-spr', spr,
                               '--out-dir', out_dir, '--things', things])
    finally:
        os.remove(things)


def live(dat_path, spr_path):
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr, sprite_index
    dat, spr = Dat(dat_path), Spr(spr_path)
    bad = 0
    for r in rows():
        s = read_sheet(r)
        for look in looks_of(r):
            t = dat.outfit(look)
            gs = t.groups
            if len(gs) != 2 or (gs[0][0], gs[0][1], gs[0][3], gs[0][4], gs[0][7], gs[1][7]) != (2, 2, 2, 4, n_idle(r), WALK) \
                    or gs[0][5] != n_addons(r) or t.flags.get('displacement') != (int(r['disp']), int(r['disp'])):
                print('look %d: not the layout of the table' % look)
                bad += 1
                continue

            class G:
                pass
            row = 0
            for g in gs:
                o = G()
                o.w, o.h, o.layers, o.px, o.py, o.pz, o.phases, o.sprites = g[0], g[1], g[3], g[4], g[5], g[6], g[7], g[8]
                for ph in range(o.phases):
                    for layer in range(2):
                        for x, y in ((x, y) for y in range(o.py) for x in range(4)):
                            c = np.zeros((CELL, CELL, 4), np.uint8)
                            for hh in range(2):
                                for ww in range(2):
                                    a = spr.sprite(o.sprites[sprite_index(o, x, y, 0, layer, ph, ww, hh)])
                                    if a is not None:
                                        c[(1 - hh) * 32:(2 - hh) * 32, (1 - ww) * 32:(2 - ww) * 32] = a
                            c[c[..., 3] == 0] = 0
                            if not (c == cell(s, layer, x, row, y)).all():
                                bad += 1
                    row += 1
    n = sum(len(looks_of(r)) for r in rows())
    print('class redraw live: %d looks of %d sheets, %d cells differ' % (n, len(rows()), bad))
    return 1 if bad else 0


def main(argv):
    sys.path.insert(0, HERE)
    a = list(argv)
    cmd = a.pop(0) if a else ''
    if cmd == 'check':
        bad = problems()
        if not bad:
            if sums_text() != open(SUMS, encoding='utf-8').read():
                bad.append('class_redraw.sums is stale: python3 -I gen_class_redraw.py sums')
            for r in rows():
                bad += sheet_problems(r)
        for b in bad:
            print(b)
        print('class redraw: %d rows, %d looks, %d problems' % (len(rows()), sum(len(looks_of(r)) for r in rows()), len(bad)))
        return 1 if bad else 0
    if cmd == 'art' and '--src' in a:
        from PIL import Image
        src, write = a[a.index('--src') + 1], '--write' in a
        only = [x for x in a if not x.startswith('--') and x != src]
        table = rows()
        for r in table:
            if only and r['key'] not in only:
                continue
            s = make_sheet(r, src)
            for b in sheet_problems(r, s):
                print(b)
            print(r['key'], numbers(r, s))
            if write:
                os.makedirs(SHEETS, exist_ok=True)
                Image.fromarray(s).save(sheet_path(r['key']), optimize=True)
        if write:
            with open(TABLE, 'w', newline='', encoding='utf-8') as f:
                w = csv.DictWriter(f, HEADER)
                w.writeheader()
                w.writerows({k: r.get(k, '') for k in HEADER} for r in table)
        return 0
    if cmd == 'sums':
        if '--check' in a:
            return 0 if sums_text() == open(SUMS, encoding='utf-8').read() else 1
        open(SUMS, 'w', encoding='utf-8').write(sums_text())
        return 0
    if cmd == 'numbers':
        for r in rows():
            print(r['key'], r['looks'], numbers(r))
        return 0
    if cmd == 'build' and len(a) == 3:
        build(*a)
        return 0
    if cmd == 'live' and len(a) == 2:
        return live(*a)
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
