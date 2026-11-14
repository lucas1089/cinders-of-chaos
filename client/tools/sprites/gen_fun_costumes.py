#!/usr/bin/env python3
"""Fun costumes, the Dusk Moth and the round Rune Seal ring of client pair 72 (O566; client/MANIFEST.md "Pair 72").

    python3 -I gen_fun_costumes.py check                         # table, sums and sheets against their own rules (CI; needs Pillow and numpy for the sheets)
    python3 -I gen_fun_costumes.py art --src DIR [--write]       # place the PixelLab downloads of DIR into the sheets (art_import/fun_costumes/KEY.png)
    python3 -I gen_fun_costumes.py art --check                   # the committed sheets are what the tool draws (the Rune Seal ring is drawn by script)
    python3 -I gen_fun_costumes.py sums [--check]                # art_import/fun_costumes.sums (a digest per outfit) from the sheets
    python3 -I gen_fun_costumes.py build DAT SPR OUT_DIR         # pair 71 in, pair 72 out (OUT_DIR must not exist; written beside, then renamed)
    python3 -I gen_fun_costumes.py live DAT SPR                  # the pair holds every outfit at its id, as the sums say (CI job "Live sprite pair")

Twelve costumes, a new Dusk Moth look and a new Rune Seal ring are appended to pair 71 as 14 outfits, one per row of
art_import/fun_costumes.csv: the row at line n is outfit 3511 + n.

The art is ours: the 12 costumes and the moth were drawn with PixelLab (docs/CREDITS.md, Tools; characters and hopping objects, four
directions, a walk or hop cycle each) and placed here by script; the Rune Seal ring is drawn by this script (`draw_ring`). Owned art
is committed the way the repository commits its other PixelLab sheets: one PNG per outfit in art_import/fun_costumes/, rows
north, east, south, west for the idle phases then the same four for the walk phases (the ring: one row, same picture every way).
The downloads themselves stay out of git (`art --src DIR` reads DIR/KEY/rot/DIRECTION.png and DIR/KEY/walk/DIRECTION/frame_NNN.png;
a creature with no west pictures gets its east ones mirrored, the oblique view being symmetric: the Wandering Toaster).

Outfit shapes (all one colour layer, no addons):
  costume  2x2 tiles (64 px), idle group (2 phases) and walk group (N phases, 4 directions); one look for both sexes, locked, sold in
           the store (Cosmetics > Costumes). Feet on row 63, the figure centred on column 47.5 (the creature's own tile, as the 2x2 hunt looks).
  pet      1x1 tile, one always animated walk group (flag animateAlways, like the stock look 213 it replaces), a flap and a hover bob.
  aura     3x3 tiles, one idle-type group of 24 phases (a half turn) and no flags, built like the stock 3x3 ground auras 1518 and 1521 (no displacement:
           the client centres a 3x3 aura frame on the tile, MANIFEST "Aura displacement"), round (width : height 1.0).
Nothing but outfits and sprite records is appended (check_pair.py --old pair 71: 0 errors).
"""
import csv
import hashlib
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SHEETS = os.path.join(ART, 'fun_costumes')
TABLE = os.path.join(ART, 'fun_costumes.csv')
SUMS = os.path.join(ART, 'fun_costumes.sums')
HEADER = ['new', 'key', 'name', 'kind', 'tiles', 'dirs', 'idle', 'walk', 'flags', 'ms', 'src']
PAIR = 72
MIN_PAIR = 71
OUTFITS_71 = 3510
FIRST_NEW = OUTFITS_71 + 1
DAT_71_MD5 = 'f21ef3e3890bc0a7e4a292feea47d572'
KINDS = ('costume', 'pet', 'aura')
DIR_NAMES = ('north', 'east', 'south', 'west')      # engine order of patternX
FOOT_ROW = 63
MID_COL = 47.5
IDLE_MS = 500
MIN_WALK = 4
MIN_PET_PHASES = 8
MIN_AURA_PHASES = 8
# the look each flags column copies from the input pair: the stock moth look (animateAlways)
FLAG_LOOKS = {'moth': 213}
OLD_LOOKS = {'dusk_moth': 213, 'rune_seal': 2186}


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


def cell_of(r):
    return int(r['tiles']) * 32


def problems(table=None, sums=None, first=FIRST_NEW):
    """what is wrong with the table: header, ids in a row from the first new outfit, keys once, kinds, shapes, phases and sums rows"""
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
        if r['kind'] not in KINDS:
            out.append('%s: kind %s is not one of %s' % (k, r['kind'], ', '.join(KINDS)))
            continue
        if not r['name'].strip():
            out.append('%s: no name' % k)
        tiles = {'costume': 2, 'pet': 1, 'aura': 3}[r['kind']]
        if int(r['tiles']) != tiles:
            out.append('%s: a %s is %dx%d tiles, the row says %s' % (k, r['kind'], tiles, tiles, r['tiles']))
        dirs, idle, walk = int(r['dirs']), int(r['idle']), int(r['walk'])
        if r['kind'] == 'costume' and not (dirs == 4 and idle >= 2 and walk >= MIN_WALK):
            out.append('%s: a costume has 4 directions, 2+ idle and %d+ walk phases (row: %d, %d, %d)' % (k, MIN_WALK, dirs, idle, walk))
        if r['kind'] == 'pet' and not (dirs == 4 and idle == 0 and walk >= MIN_PET_PHASES):
            out.append('%s: a pet has 4 directions, no idle group and %d+ phases (row: %d, %d, %d)' % (k, MIN_PET_PHASES, dirs, idle, walk))
        if r['kind'] == 'aura' and not (dirs == 1 and idle == 0 and walk >= MIN_AURA_PHASES):
            out.append('%s: an aura has one drawn direction, no idle group and %d+ phases (row: %d, %d, %d)' % (k, MIN_AURA_PHASES, dirs, idle, walk))
        if r['flags'] and r['flags'] not in FLAG_LOOKS:
            out.append('%s: flags %s is not one of %s' % (k, r['flags'], ', '.join(FLAG_LOOKS)))
        if int(r['ms']) < 40:
            out.append('%s: %s ms a phase is too fast' % (k, r['ms']))
        if r['new'] not in s:
            out.append('%s: no row %s in fun_costumes.sums' % (k, r['new']))
    for k in s:
        if k not in {r['new'] for r in t}:
            out.append('fun_costumes.sums has a row for outfit %s that is not in the table' % k)
    return out


# ---------------------------------------------------------------- sheets: one PNG per outfit

def sheet_path(key):
    return os.path.join(SHEETS, key + '.png')


def read_sheet(r):
    """{(group, dir, phase): RGBA array of the cell} of a row's sheet; group 'idle' or 'walk'"""
    import numpy as np
    from PIL import Image
    cell = cell_of(r)
    im = np.array(Image.open(sheet_path(r['key'])).convert('RGBA'))
    dirs, idle, walk = int(r['dirs']), int(r['idle']), int(r['walk'])
    cols = max(idle, walk)
    rows_n = dirs * ((1 if idle else 0) + 1)
    if im.shape != (rows_n * cell, cols * cell, 4):
        raise SystemExit('%s: sheet is %s, expected %s' % (r['key'], im.shape, (rows_n * cell, cols * cell, 4)))
    out = {}
    row = 0
    for grp, n in (('idle', idle), ('walk', walk)):
        if not n:
            continue
        for d in range(dirs):
            for ph in range(n):
                out[(grp, d, ph)] = im[row * cell:(row + 1) * cell, ph * cell:(ph + 1) * cell].copy()
            row += 1
    return out


def write_sheet(r, frames, path=None):
    import numpy as np
    from PIL import Image
    cell = cell_of(r)
    dirs, idle, walk = int(r['dirs']), int(r['idle']), int(r['walk'])
    cols = max(idle, walk)
    rows_n = dirs * ((1 if idle else 0) + 1)
    im = np.zeros((rows_n * cell, cols * cell, 4), np.uint8)
    row = 0
    for grp, n in (('idle', idle), ('walk', walk)):
        if not n:
            continue
        for d in range(dirs):
            for ph in range(n):
                im[row * cell:(row + 1) * cell, ph * cell:(ph + 1) * cell] = frames[(grp, d, ph)]
            row += 1
    Image.fromarray(im).save(path or sheet_path(r['key']), optimize=True)


def clean(a):
    """the tile as the spr gives it back: no colour under a transparent pixel"""
    import numpy as np
    return np.where(a[..., 3:4] > 0, a, 0).astype(np.uint8)


def binary_alpha(a):
    """hard alpha, as the other imports (pack effect mesh, O523): 0 below half, else 255"""
    import numpy as np
    a = a.copy()
    a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
    return clean(a)


# ---------------------------------------------------------------- placing the PixelLab downloads

OUTLINE = (20, 16, 26)   # the one outline colour of a costume: near-black (style_check.py DARK is luma 24), a little violet like the game's art


def restyle(a):
    """the game's outline rule on a costume picture (docs/SPRITE_STYLE.md): the rim (opaque pixels with a transparent 4-neighbour) is one
    near-black colour, one pixel thick: a dark pixel just inside the rim (the second ring) takes the colour of its lit neighbours
    at 55%, so a PixelLab outline that was brown, coloured or two pixels thick becomes the same thin black line as the rest of the
    game's art. Nothing else changes."""
    import numpy as np
    a = a.copy()
    op = a[..., 3] > 0
    pad = np.pad(op, 1, constant_values=False)
    inner = pad[1:-1, 1:-1] & pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
    rim = op & ~inner
    luma = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    dark2 = op & ~rim & (luma < 24)
    rp = np.pad(rim, 1, constant_values=False)
    near_rim = rp[:-2, 1:-1] | rp[2:, 1:-1] | rp[1:-1, :-2] | rp[1:-1, 2:]
    lit = op & ~rim & ~(luma < 24)
    out = a.copy()
    for y, x in zip(*np.nonzero(dark2 & near_rim)):
        ys, xs = slice(max(0, y - 1), y + 2), slice(max(0, x - 1), x + 2)
        m = lit[ys, xs]
        if m.any():
            out[y, x, :3] = (a[ys, xs, :3][m].mean(axis=0) * 0.55).astype(np.uint8)
    out[rim, :3] = OUTLINE
    return clean(out)

def load_png(path):
    import numpy as np
    from PIL import Image
    return np.array(Image.open(path).convert('RGBA'))


def mirrored_west(base):
    """True when DIR/KEY has no west pictures at all: the west ones are the east ones flipped left to right"""
    return not os.path.exists(os.path.join(base, 'rot', 'west.png')) and not os.path.isdir(os.path.join(base, 'walk', 'west'))


def load_rot(base, d):
    a = load_png(os.path.join(base, 'rot', ('east' if d == 'west' and mirrored_west(base) else d) + '.png'))
    return a[:, ::-1].copy() if d == 'west' and mirrored_west(base) else a


def load_walk(base, d):
    flip = d == 'west' and mirrored_west(base)
    dd = os.path.join(base, 'walk', 'east' if flip else d)
    fs = sorted(f for f in os.listdir(dd) if f.endswith('.png'))
    out = [load_png(os.path.join(dd, f)) for f in fs]
    return [a[:, ::-1].copy() for a in out] if flip else out


def source_files(src, key):
    """every picture file of a creature of the downloads, in a fixed order"""
    out = []
    base = os.path.join(src, key)
    for d in DIR_NAMES:
        p = os.path.join(base, 'rot', d + '.png')
        if os.path.exists(p):
            out.append(p)
    wd = os.path.join(base, 'walk')
    for d in DIR_NAMES:
        dd = os.path.join(wd, d)
        if os.path.isdir(dd):
            out += [os.path.join(dd, f) for f in sorted(os.listdir(dd)) if f.endswith('.png')]
    return out


def src_sum(src, key):
    """12 hex digits over the source picture files of a creature (the bytes of each, in order)"""
    h = hashlib.sha256()
    for p in source_files(src, key):
        h.update(open(p, 'rb').read())
    return h.hexdigest()[:12]


def union_box(frames):
    import numpy as np
    x0 = y0 = 10 ** 6
    x1 = y1 = -1
    for a in frames:
        ys, xs = np.nonzero(a[..., 3] > 0)
        if len(xs):
            x0, x1, y0, y1 = min(x0, int(xs.min())), max(x1, int(xs.max())), min(y0, int(ys.min())), max(y1, int(ys.max()))
    if x1 < 0:
        raise ValueError('no opaque pixel')
    return x0, y0, x1, y1


def shift_into(a, dx, dy, cell):
    import numpy as np
    c = np.zeros((cell, cell, 4), np.uint8)
    h, w = a.shape[:2]
    sy0, sx0 = max(0, -dy), max(0, -dx)
    ey, ex = min(h, cell - dy), min(w, cell - dx)
    if ey > sy0 and ex > sx0:
        c[sy0 + dy:ey + dy, sx0 + dx:ex + dx] = a[sy0:ey, sx0:ex]
    return c


def place_costume(src, key, idle_n=2):
    """DIR/KEY downloads -> {(group, dir, phase): 64 x 64 cell}: one shift for every frame (lowest opaque pixel on FOOT_ROW, middle of the
    union box on MID_COL, moved left when the box would pass the last column); the idle phases are the standing picture and the same
    picture one pixel up (a breath)"""
    import numpy as np
    base = os.path.join(src, key)
    rot = [restyle(binary_alpha(load_rot(base, d))) for d in DIR_NAMES]
    walk = [[restyle(binary_alpha(a)) for a in load_walk(base, d)] for d in DIR_NAMES]
    n = {len(w) for w in walk}
    if len(n) != 1 or min(n) < MIN_WALK:
        raise ValueError('%s: walk phases per direction %s (need the same %d or more)' % (key, sorted(n), MIN_WALK))
    allf = rot + [f for w in walk for f in w]
    x0, y0, x1, y1 = union_box(allf)
    dy = FOOT_ROW - y1
    dx = min(math.floor(MID_COL - (x0 + x1) / 2.0), 63 - x1)
    if x0 + dx < 0 or y0 + dy - 1 < 0 or x1 + dx > 63:
        raise ValueError('%s: the figure (%dx%d) does not fit the 64 px canvas' % (key, x1 - x0 + 1, y1 - y0 + 1))
    out = {}
    for d in range(4):
        out[('idle', d, 0)] = shift_into(rot[d], dx, dy, 64)
        out[('idle', d, 1)] = shift_into(rot[d], dx, dy - 1, 64)
        for ph, f in enumerate(walk[d]):
            out[('walk', d, ph)] = shift_into(f, dx, dy, 64)
    return out, len(walk[0])


def place_pet(src, key):
    """DIR/KEY downloads of a flyer -> {('walk', dir, phase): 32 x 32 cell}: one shift for all frames, the union box centred (the bob stays)"""
    base = os.path.join(src, key)
    walk = [[binary_alpha(a) for a in load_walk(base, d)] for d in DIR_NAMES]
    n = {len(w) for w in walk}
    if len(n) != 1 or min(n) < MIN_PET_PHASES:
        raise ValueError('%s: phases per direction %s (need the same %d or more)' % (key, sorted(n), MIN_PET_PHASES))
    x0, y0, x1, y1 = union_box([f for w in walk for f in w])
    if x1 - x0 + 1 > 32 or y1 - y0 + 1 > 32:
        raise ValueError('%s: the moth with its bob (%dx%d) does not fit 32 px' % (key, x1 - x0 + 1, y1 - y0 + 1))
    dx = math.floor(15.5 - (x0 + x1) / 2.0)
    dy = math.floor(15.5 - (y0 + y1) / 2.0)
    out = {}
    for d in range(4):
        for ph, f in enumerate(walk[d]):
            out[('walk', d, ph)] = shift_into(f, dx, dy, 32)
    return out, len(walk[0])


# ---------------------------------------------------------------- the Rune Seal ring, drawn by script

RING_PHASES = 24
RING_CELL = 96
RING_CENTRE = (46.0, 48.0)   # the stock 3x3 ground auras sit at -11..-2 / -3..+4 px from the tile centre (frame centre is 47.5)
RING_R = 29.0
RING_RUNES = 8
# four 5 x 5 runes (hand drawn, # is a pixel), two of each round the ring
RUNES = (
    ('#...#', '#...#', '#####', '..#..', '..#..'),
    ('..#..', '.##..', '#.#..', '.##..', '..#..'),
    ('#####', '#.#.#', '..#..', '.#.#.', '#...#'),
    ('.###.', '#...#', '..#..', '#...#', '.###.'),
)
RING_COLS = {'dark': (24, 10, 44), 'rim': (104, 62, 170), 'band': (160, 120, 230), 'glow': (225, 195, 255), 'hot': (255, 250, 255)}


def draw_ring(phase):
    """one phase of the round rune ring: a violet double rim, a band with eight runes that turn one step round the ring over the
    cycle (a half turn: four different runes repeat twice round the ring, so the last phase leads back into the first), the runes
    breathing from violet to white, a dashed outer glow turning the other way. 96 x 96 RGBA, hard alpha."""
    import numpy as np
    cell = RING_CELL
    cx, cy = RING_CENTRE
    im = np.zeros((cell, cell, 4), np.uint8)
    yy, xx = np.mgrid[0:cell, 0:cell]
    rr = np.hypot(xx - cx, yy - cy)
    # band and rims
    band = (rr >= RING_R - 5.5) & (rr <= RING_R + 5.5)
    rim = ((rr >= RING_R - 7.5) & (rr < RING_R - 5.5)) | ((rr > RING_R + 5.5) & (rr <= RING_R + 7.5))
    inner = (rr >= RING_R - 9.5) & (rr < RING_R - 8.5)
    pulse = 0.5 + 0.5 * math.sin(2 * math.pi * phase / RING_PHASES)
    c = RING_COLS
    im[band] = (*c['dark'], 255)
    im[rim] = (*c['rim'], 255)
    im[inner] = (*[int(round(v * (0.6 + 0.4 * round(pulse, 6)))) for v in c['band']], 255)
    # a dashed outer glow that turns the other way
    ang = np.arctan2(yy - cy, xx - cx)
    dash = (np.floor((ang / (2 * math.pi) + 1.0 - phase / RING_PHASES / 2) * 32) % 2) == 0
    outer = (rr > RING_R + 8.5) & (rr <= RING_R + 9.5) & dash
    im[outer] = (*c['band'], 255)
    # the runes: eight slots, four different runes twice; the band turns by half a turn (four slots) over the cycle
    turn = phase / RING_PHASES * (RING_RUNES // 2) * (2 * math.pi / RING_RUNES)
    for i in range(RING_RUNES):
        a = i * 2 * math.pi / RING_RUNES + turn - math.pi / 2
        px, py = cx + RING_R * math.cos(a), cy + RING_R * math.sin(a)
        glyph = RUNES[i % 4]
        k = round(0.5 + 0.5 * math.sin(2 * math.pi * (phase / RING_PHASES) + (i % 4) * 1.3), 6)
        col = tuple(int(round(c['glow'][j] + (c['hot'][j] - c['glow'][j]) * k)) for j in range(3))
        hot = k > 0.9
        for gy, line in enumerate(glyph):
            for gx, ch in enumerate(line):
                if ch != '#':
                    continue
                x, y = int(round(px)) - 2 + gx, int(round(py)) - 2 + gy
                if 0 <= x < cell and 0 <= y < cell:
                    im[y, x] = (*(c['hot'] if hot else col), 255)
    return im


def ring_frames():
    return {('walk', 0, ph): draw_ring(ph) for ph in range(RING_PHASES)}


# ---------------------------------------------------------------- the outfit of a row

def groups_of(r, frames):
    """[(Group, [tile arrays in slot order])]: the dat shape and the sprite arrays of one outfit"""
    sys.path.insert(0, HERE)
    from import_outfits import Group
    from gen_effects import tiles_of
    t, cell = int(r['tiles']), cell_of(r)
    dirs, ms = int(r['dirs']), int(r['ms'])
    out = []
    for gtype, key, n, dur in ((0, 'idle', int(r['idle']), IDLE_MS), (1, 'walk', int(r['walk']), ms)):
        if not n:
            continue
        if r['kind'] == 'aura':
            gtype = 0   # like 1518 and 1521: one idle-type group
        g = Group()
        g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases = gtype, t, t, cell, 1, 4, 1, 1, n
        g.anim = (0, 0, 0, tuple([dur, dur] * n)) if n > 1 else None
        tiles = []
        for ph in range(n):
            for d in range(4):
                a = frames[(key, d if dirs == 4 else 0, ph)]
                tl = tiles_of(a, t, t) if t > 1 else {(0, 0): a}
                for hh in range(t):
                    for ww in range(t):
                        tiles.append(tl[(ww, hh)])
        g.sprites = tuple(range(len(tiles)))
        out.append((g, tiles))
    return out


def spec_digest(specs):
    """sha256 over the whole outfit: group shapes and animator, then every sprite slot (empty slots alike) of every group"""
    h = hashlib.sha256()
    for g, tiles in specs:
        h.update(repr((g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim)).encode())
        for a in tiles:
            h.update(b'\0' if a is None or not a[:, :, 3].any() else clean(a).tobytes())
    return h.hexdigest()


def digest(dat, spr, look):
    """the same digest read from a pair"""
    sys.path.insert(0, HERE)
    from import_outfits import parse_body
    specs = [(g, [spr.sprite(sid) for sid in g.sprites]) for g in parse_body(dat, dat.outfit(look))]
    return spec_digest(specs)


def row_specs(r):
    return groups_of(r, read_sheet(r))


def sums_text(table=None):
    t = rows() if table is None else table
    lines = ['# fun_costumes.sums: sha256 of every outfit of pair 72 (group shapes, animator, sprite slots); gen_fun_costumes.py sums',
             '# written by gen_fun_costumes.py sums; checked by `check`, and by `live` against a built pair']
    for r in t:
        lines.append('%s %s' % (r['new'], spec_digest(row_specs(r))))
    return '\n'.join(lines) + '\n'


# ---------------------------------------------------------------- art: downloads -> sheets

def art(src, write):
    """place the downloads of every costume and the moth of the table into sheets; draw the ring. Returns (rows with the new
    src column and phase counts, {key: frames}); writes the sheets when `write`."""
    t = rows()
    out_rows, sheets = [], {}
    for r in t:
        r = dict(r)
        if r['kind'] == 'aura':
            fr = ring_frames()
            r['walk'] = str(RING_PHASES)
            r['src'] = 'script'
        elif r['kind'] == 'pet':
            fr, n = place_pet(src, r['key'])
            r['walk'] = str(n)
            r['src'] = src_sum(src, r['key'])
        else:
            fr, n = place_costume(src, r['key'])
            r['walk'] = str(n)
            r['src'] = src_sum(src, r['key'])
        sheets[r['key']] = (r, fr)
        out_rows.append(r)
    if write:
        os.makedirs(SHEETS, exist_ok=True)
        for k, (r, fr) in sheets.items():
            write_sheet(r, fr)
        write_table(out_rows)
    return out_rows, sheets


def write_table(t, path=TABLE):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=HEADER, lineterminator='\n')
        w.writeheader()
        w.writerows(t)


def art_check():
    """the committed sheets of the ring are what draw_ring gives, and every sheet is a valid cell grid of its row"""
    import numpy as np
    out = []
    for r in rows():
        if not os.path.exists(sheet_path(r['key'])):
            out.append('%s: no sheet %s' % (r['key'], sheet_path(r['key'])))
            continue
        fr = read_sheet(r)
        for k, a in fr.items():
            if a.dtype != np.uint8 or (a[..., 3][(a[..., 3] != 0) & (a[..., 3] != 255)]).size:
                out.append('%s: cell %s has soft alpha (the tool writes hard alpha)' % (r['key'], k))
                break
        if r['kind'] == 'aura':
            want = ring_frames()
            if any(not np.array_equal(fr[k], want[k]) for k in want):
                out.append('%s: the sheet is not what draw_ring draws' % r['key'])
        out += figure_problems(r, fr)
    return out


def figure_problems(r, fr):
    """a costume stands on row 63 and fits; a pet fits one tile; the ring is round (width : height of the union 0.9 to 1.1)"""
    import numpy as np
    out = []
    cell = cell_of(r)
    boxes = [union_box([a]) for a in fr.values() if (a[..., 3] > 0).any()]
    if not boxes:
        return ['%s: empty sheet' % r['key']]
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    if r['kind'] == 'costume':
        if y1 != FOOT_ROW:
            out.append('%s: lowest pixel on row %d, not %d' % (r['key'], y1, FOOT_ROW))
        if not 16 <= h <= 60 or not 12 <= w <= 60:
            out.append('%s: figure %dx%d outside 12..60 x 16..60' % (r['key'], w, h))
    if r['kind'] == 'pet' and (w > cell or h > cell):
        out.append('%s: %dx%d is bigger than one tile' % (r['key'], w, h))
    if r['kind'] == 'aura':
        ratio = w / float(h)
        if not 0.9 <= ratio <= 1.1:
            out.append('%s: width : height %.2f, a round ring is 0.9 to 1.1' % (r['key'], ratio))
    for k, a in fr.items():
        if not (a[..., 3] > 0).any():
            out.append('%s: cell %s is empty' % (r['key'], k))
            break
    distinct = {a.tobytes() for k, a in fr.items() if k[0] == 'walk' and k[1] == 0}
    if len(distinct) < max(3, int(r['walk']) // 2):
        out.append('%s: only %d different walk pictures in one direction: it would not animate' % (r['key'], len(distinct)))
    return out


# ---------------------------------------------------------------- pair 71 -> pair 72

def record_index(spr):
    sys.path.insert(0, HERE)
    import gen_wst_outfits
    return gen_wst_outfits.record_index(spr)


def build(dat, spr, out_dir, table=None, first=FIRST_NEW, expect_md5=None, log=print):
    """pair in (DAT, SPR; its outfits end at first - 1) -> pair out in OUT_DIR (not there yet): every row of the table is one new
    outfit drawn from its sheet. Verified before the rename; returns the new ids."""
    import random
    import shutil
    import struct
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_outfits import build_entry, encode_flags, frame, frames_of, parse_body
    from gen_effects import encode_sprite
    t = rows() if table is None else table
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    if expect_md5:
        with open(dat, 'rb') as f:
            got = hashlib.md5(f.read()).hexdigest()
        if got != expect_md5:
            raise SystemExit('input dat md5 %s, expected %s (pair %d): wrong input pair' % (got, expect_md5, MIN_PAIR))
    od, ospr = Dat(dat), Spr(spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]), 'expected our 10.98 dat: %s' % (od.variant,)
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    nours = len(od.outfits)
    if nours + 1 != first:
        raise SystemExit('the input has %d outfits, the first new outfit would be %d, not %d: wrong input pair (or already built)'
                         % (nours, nours + 1, first))
    tmp = out_dir.rstrip('/') + '.tmp'
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    cnt = ospr.count
    index = record_index(ospr)
    newrecs, recs, reused = [], {}, 0
    entries, src_specs = [], []
    for i, r in enumerate(t):
        specs = row_specs(r)
        flags = b''
        if r['flags']:
            flags, _stripped = encode_flags(od.outfit(FLAG_LOOKS[r['flags']]), od.extra)
        sid_map = {0: 0}
        for g, tiles in specs:
            for slot, a in enumerate(tiles):
                rec = encode_sprite(clean(a))
                if rec is None:
                    sid_map[(id(g), slot)] = 0
                    continue
                key = hashlib.md5(rec).digest()
                if key in index:
                    sid_map[(id(g), slot)] = index[key]
                    reused += 1
                else:
                    if rec not in recs:
                        newrecs.append(rec)
                        recs[rec] = cnt + len(newrecs)
                    sid_map[(id(g), slot)] = recs[rec]
        gs = []
        for g, tiles in specs:
            g2 = type(g)()
            for k in g.__slots__:
                setattr(g2, k, getattr(g, k))
            g2.sprites = tuple((id(g), s) for s in range(len(tiles)))
            gs.append(g2)
        entries.append(build_entry(flags, gs, sid_map))
        src_specs.append((first + i, r, specs, flags))
    d = od.data
    ins = od.effects[0].raw[0]
    assert od.outfits[-1].raw[1] == ins
    out = bytearray(d[:ins]) + b''.join(entries) + d[ins:]
    struct.pack_into('<H', out, 6, nours + len(entries))
    with open(os.path.join(tmp, 'Tibia.dat'), 'wb') as f:
        f.write(out)
    m_, nn = ospr.m, len(newrecs)
    toffs = ospr.offs.astype('<u8').copy()
    toffs[toffs > 0] += 4 * nn
    cur = len(m_) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur)
        cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table_b = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(tmp, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn))
        f.write(table_b.tobytes())
        pos = 8 + 4 * cnt
        while pos < len(m_):
            f.write(m_[pos:pos + (1 << 24)])
            pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    # verify: re-parse, old things byte identical, every slot and frame of every new outfit is the drawn one
    md, ms = Dat(os.path.join(tmp, 'Tibia.dat')), Spr(os.path.join(tmp, 'Tibia.spr'))
    assert md.variant == od.variant and ms.alpha == ospr.alpha and ms.signature == ospr.signature
    assert md.counts == (od.counts[0], nours + len(entries), od.counts[2], od.counts[3]), md.counts
    assert ms.count == cnt + nn and md.max_sprite <= ms.count
    assert md.data[:6] == d[:6] and md.data[8:ins] == d[8:ins], 'items or old outfits changed'
    assert md.data[ins + sum(map(len, entries)):] == d[ins:], 'effects or missiles changed'
    nslots = nframes = 0
    for nid, r, specs, flags in src_specs:
        tm = md.outfit(nid)
        if r['flags']:
            want = od.outfit(FLAG_LOOKS[r['flags']]).flags
            assert {k: v for k, v in tm.flags.items()} == {k: v for k, v in want.items() if not (k[0] == 'x' and k[1:].isdigit())}, \
                (nid, 'flags', tm.flags, want)
        else:
            assert not tm.flags, (nid, 'flags')
        mg = parse_body(md, tm)
        assert len(mg) == len(specs), nid
        for (g, tiles), h in zip(specs, mg):
            assert (g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim) == \
                   (h.gtype, h.w, h.h, h.exact, h.layers, h.px, h.py, h.pz, h.phases, h.anim), (nid, 'group')
            for a, s1 in zip(tiles, h.sprites):
                y = ms.sprite(s1)
                if y is not None and not y[:, :, 3].any():
                    y = None
                want_a = None if not a[:, :, 3].any() else clean(a)
                assert (want_a is None) == (y is None) and (want_a is None or np.array_equal(want_a, y)), (nid, 'slot')
                nslots += 1
            nframes += len(frames_of(h))
        assert digest(md, ms, nid) == spec_digest(specs), (nid, 'digest')
        for h in mg:
            for (xx, yy, zz, ph) in frames_of(h):
                a = frame(h, ms, xx, yy, zz, ph)
                assert a.shape == (h.h * 32, h.w * 32, 4)
    random.seed(1)
    for sid in random.sample(range(1, cnt + 1), min(3000, cnt)) + [1, cnt]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log('verified: %d outfits %d to %d, %d sprite slots and %d frames read back as drawn, %d slots reuse a sprite of the input pair, '
        '%d records appended (%d -> %d), every old outfit, item, effect, missile and 3000 sampled old sprites unchanged'
        % (len(entries), first, first + len(entries) - 1, nslots, nframes, reused, nn, cnt, cnt + nn))
    from check_pair import check_append_only
    check_append_only(dat, spr, os.path.join(tmp, 'Tibia.dat'), os.path.join(tmp, 'Tibia.spr'), log=log)
    os.rename(tmp, out_dir)
    return [first + i for i in range(len(entries))]


def live(dat, spr, table=None, sums=None, first=FIRST_NEW, log=print):
    """the pair holds every outfit at its id, its digest the one of the sums file. Returns the problem lines."""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    d, sp = Dat(dat), Spr(spr)
    if len(d.outfits) < first + len(t) - 1:
        return ['the pair has %d outfits, the fun costumes end at %d' % (len(d.outfits), first + len(t) - 1)]
    out = []
    for r in t:
        if digest(d, sp, int(r['new'])) != s.get(r['new']):
            out.append('outfit %s (%s): the pictures are not the ones of fun_costumes.sums' % (r['new'], r['key']))
    log('live: %d outfits %d to %d checked, %d problems' % (len(t), first, first + len(t) - 1, len(out)))
    return out


def opt(args, key):
    if key in args:
        i = args.index(key)
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return None


def main(argv):
    args = list(argv)
    cmd = args.pop(0) if args else ''
    if cmd == 'check':
        p = problems()
        try:
            p += art_check()
            text = sums_text()
            if text != open(SUMS, encoding='utf-8').read():
                p.append('fun_costumes.sums is not what the sheets give (gen_fun_costumes.py sums)')
        except ImportError:
            print('check: Pillow and numpy missing, the sheets were not read')
        for line in p:
            print('PROBLEM', line)
        print('fun_costumes: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if cmd == 'art':
        src = opt(args, '--src')
        if '--check' in args:
            p = art_check()
            for line in p:
                print('PROBLEM', line)
            print('fun_costumes sheets: %d problems' % len(p))
            return 1 if p else 0
        if not src:
            print(__doc__)
            return 1
        new_rows, sheets = art(src, '--write' in args)
        for r in new_rows:
            fr = sheets[r['key']][1]
            print('%s %-18s %-8s idle %s walk %s src %s%s' % (r['new'], r['key'], r['kind'], r['idle'], r['walk'], r['src'],
                                                           ''.join('\n   ' + x for x in figure_problems(r, fr))))
        return 0
    if cmd == 'sums':
        text = sums_text()
        if '--check' in args:
            old = open(SUMS, encoding='utf-8').read() if os.path.exists(SUMS) else None
            if old != text:
                print('PROBLEM fun_costumes.sums is not what the sheets give')
                return 1
            print('fun_costumes.sums: up to date')
            return 0
        with open(SUMS, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        return 0
    if cmd == 'build' and len(args) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(args[0], args[1], args[2], expect_md5=DAT_71_MD5)
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
