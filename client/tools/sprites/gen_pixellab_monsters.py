#!/usr/bin/env python3
"""24 original monsters made with PixelLab as outfits 3531-3554 of pair 74 (O640; client/MANIFEST.md "PixelLab monsters (O640)").

    python3 -I gen_pixellab_monsters.py check                         # table, sums, sheets and the monster map (CI; needs Pillow and numpy)
    python3 -I gen_pixellab_monsters.py art --src DIR [--src DIR] [--write]
                                                                      # the PixelLab downloads of DIR/KEY (or KEY with the prefix t3_ / t4_) -> sheets, table, sums
    python3 -I gen_pixellab_monsters.py looks [--check]               # server/data/monster/monster_pixellab_looks.csv from the `pixellab` rows of monster_looks/picks.csv
    python3 -I gen_pixellab_monsters.py numbers                       # the numbers of every sheet (size, stand, hang, pictures)
    python3 -I gen_pixellab_monsters.py build DAT SPR OUT_DIR         # a pair with 3,530 outfits in, 24 more out (OUT_DIR must not exist)
    python3 -I gen_pixellab_monsters.py live DAT SPR                  # the pair holds every outfit at its id, as the sheets and sums say
    python3 -I gen_pixellab_monsters.py preview OUT_DIR --dat D --spr S   # monsters_ingame.mp4 drawn from the pair (never committed; ffmpeg)

Owner 2026-11-18 (translated): the 24 original monsters of O629 and O630 are approved ("Aprovados"). They are built into pair 74 and
given to hunt monsters (server/README.md "PixelLab monsters (O640)"). The art is ours: PixelLab characters and objects (docs/CREDITS.md,
Tools) drawn from our own words alone, 8 directions of which the four of the game are kept (south, east, north, west), a breathing idle
(or a bob for what floats) and a walk of 8 pictures. The sheets are committed like those of O618: art_import/pixellab_monsters/KEY.png,
one placed cell per picture, so a built pair can be held to them byte for byte. This script only places; it draws nothing.

Pictures. Every picture of the four directions, idle and walk, in order, as PixelLab gave it: never sampled, never mirrored, no pixel
changed or dropped. The alpha is cut at 128 (opaque or nothing; the sources have no other level). A figure that does not fit the
canvas of its size is not sampled down: the canvas grows to the next whole tile (a sheet taller than 64 px is a 3x3 outfit, like the
bigger stock monsters; nearest 2:1 would halve it and is not used, owner: what the videos show is what must land in the game).

Place. One shift for all frames of an outfit (a turn on the spot stays on the spot), and the dat displacement that puts the standing
point on the tile, the O585 rule (gen_outfit_centre.py): the point is x 16.5 of the tile, y 24 for a 2x2 outfit and y 21 for a 3x3
(the median feet of the stock monster looks of those sizes, outfit_centre.csv); a figure whose lowest pixel would hang more than HANG
px under the tile's last row stands higher by the rest. The feet are gen_outfit_anchors.measure of the first idle picture of each
direction, the median of the four; a floating thing (wisp, maw, bat, broodsac, veil witch: no feet) is centred on its box and has its
lowest pixel on row 29 of the tile. The displacement is as near to (-(16 N - 16), 0) as the figure allows (that puts the middle of the
canvas over the tile's middle) and is the only flag; it is negative on every outfit, as the creature outfits of O608 (the client has
GameNegativeOffset on). The canvas is the smallest of 2x2, 3x3, 4x4 that holds the figure.

Frames. The idle group has as many phases as the sheet has idle pictures (4, 8 or 15), the walk group 8, in every direction. A phase
lasts the time the approved videos showed it for: idle 300 ms (up to 4 pictures), 200 ms (up to 8), 100 ms (more); walk 100 ms.

Sheet. N x N tile cells (32 N px), columns north, east, south, west (engine order), rows the idle pictures, then the walk pictures.
Table art_import/pixellab_monsters.csv (one row per outfit, from 3531 in the order of KEYS), art_import/pixellab_monsters.sums (the
digest of every outfit: shapes, animator, every sprite slot). The outfits go after the 3,530 outfits of pair 74's Malgrath (O637,
gen_malgrath_boss.py): this step needs exactly those in its input and refuses a pair that ends at 3529.
Needs numpy and Pillow (the fx venv of CI); `check` also needs them (it reads the sheets). `preview` needs ffmpeg.
"""
import csv
import hashlib
import math
import os
import re
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_wst_outfits as W  # noqa: E402
import gen_creature_outfits as G  # noqa: E402

ART = os.path.join(HERE, 'art_import')
SHEETS = os.path.join(ART, 'pixellab_monsters')
TABLE = os.path.join(ART, 'pixellab_monsters.csv')
SUMS = os.path.join(ART, 'pixellab_monsters.sums')
REPO = W.REPO
PICKS = W.PICKS
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_pixellab_looks.csv')
MAP_HEADER = ['monster', 'look', 'new_look']
HEADER = ['key', 'name', 'tier', 'role', 'float', 'new', 'tiles', 'disp', 'idle', 'idle_ms', 'walk', 'walk_ms', 'pixels', 'src', 'pl']
FAMILY = 'pixellab'
PAIR = 74
OUTFITS_BEFORE = 3530               # pair 73's 3,529 and Malgrath (O637)
FIRST_NEW = OUTFITS_BEFORE + 1
DIRS = ('north', 'east', 'south', 'west')       # engine order
SOUTH = 2
TX = 16.5                           # the O585 standing point: x of the tile
TY = {1: 24, 2: 24, 3: 21, 4: 20}   # y of the standing point by outfit size (median feet of the stock monster looks of that size)
HANG = 4                            # px a walking figure's lowest pixel may hang under the tile's last row (31)
FLOAT_LOW = 29                      # the lowest pixel row of a floating thing
STAND_TOL = 1.0
MIN_TILES, MAX_TILES = 1, 4
WALK = 8
WALK_MS = 100
MIN_IDLE = 4
MAX_PHASES = 32
MAX_ON_LOOK = 1                     # one hunt monster on each new look (owner rule of O529: no two hunt monsters share a look)
# the level band of each tier, held to the bounty pool (the level of the monster that wears the look)
BANDS = {1: (1, 30), 2: (31, 150), 3: (151, 499), 4: (500, 10 ** 6)}
ROLES = ('roamer', 'chaser', 'hunter', 'sniper')

# key, name, tier, role, floats. The outfits are in this order from FIRST_NEW; `dir` of the PixelLab download is the key, or t3_KEY / t4_KEY.
SPEC = (
    ('imp', 'Cinder Imp', 1, 'roamer', 0), ('thrall', 'Ashbound Thrall', 1, 'roamer', 0), ('arbalist', 'Soot Arbalist', 1, 'roamer', 0),
    ('hound', 'Scorch Hound', 1, 'chaser', 0), ('wisp', 'Ember Wisp', 1, 'chaser', 1), ('crawler', 'Cinder Crawler', 1, 'roamer', 0),
    ('penitent', 'Hollow Penitent', 1, 'roamer', 0),
    ('maw', 'Magma Maw', 2, 'sniper', 1), ('brute', 'Slag Brute', 2, 'roamer', 0), ('stalker', 'Gloom Stalker', 2, 'chaser', 0),
    ('lancer', 'Bone Lancer', 2, 'hunter', 0), ('bloat', 'Pyre Bloat', 2, 'roamer', 0), ('bat', 'Cinder Bat', 2, 'chaser', 1),
    ('ogre', 'Furnace Ogre', 3, 'roamer', 0), ('inquisitor', 'Brand Inquisitor', 3, 'roamer', 0), ('ravager', 'Obsidian Ravager', 3, 'chaser', 0),
    ('fiend', 'Soot Fiend', 3, 'hunter', 0), ('broodsac', 'Ember Broodsac', 3, 'sniper', 1), ('knight', 'Obsidian Knight', 3, 'chaser', 0),
    ('warlord', 'Ashen Warlord', 4, 'hunter', 0), ('colossus', 'Molten Colossus', 4, 'roamer', 0), ('prophet', 'Pyre Prophet', 4, 'sniper', 0),
    ('broodqueen', 'Ashen Brood Queen', 4, 'hunter', 0), ('veilwitch', 'Veil Witch', 4, 'sniper', 1),
)
KEYS = tuple(s[0] for s in SPEC)


def rows(path=None):
    with open(TABLE if path is None else path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_sums(path=None):
    return W.read_sums(SUMS if path is None else path)


def idle_ms_for(phases):
    """how long an idle phase lasts: what the approved videos showed (4 pictures 300 ms, 8 pictures 200 ms, more 100 ms)"""
    return 300 if phases <= 4 else 200 if phases <= 8 else 100


def tiles_of_text(text):
    m = re.fullmatch(r'(\d)x(\d)', text)
    return int(m.group(1)) if m and m.group(1) == m.group(2) and MIN_TILES <= int(m.group(1)) <= MAX_TILES else None


def disp_of_text(text):
    m = re.fullmatch(r'(-?\d+):(-?\d+)', text or '')
    return (int(m.group(1)), int(m.group(2))) if m else None


def flags_of(row):
    """(the flag bytes of an outfit entry, the flags as the dat reader gives them): the displacement only (two u16)"""
    u = tuple(v & 0xFFFF for v in disp_of_text(row['disp']))
    return bytes([G.DISP_FLAG]) + struct.pack('<HH', *u), {'displacement': u}


def tile_origin(n, disp):
    """(x, y) of the creature's own tile on the canvas of an N x N outfit: the last tile, moved by the displacement"""
    c = 32 * n
    return c - 32 + disp[0], c - 32 + disp[1]


def problems(table=None, sums=None, first=FIRST_NEW, spec=SPEC):
    """What is wrong with the table: the rows are SPEC in order, ids from the first new outfit, sizes, displacement, phases, durations,
    and the sums name the same outfits."""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out, seen = [], set()
    if spec is not None and [(r['key'], r['name'], int(r['tier']), r['role'], int(r['float'])) for r in t] != [tuple(x) for x in spec]:
        out.append('the rows are not SPEC of gen_pixellab_monsters.py, in its order')
    for i, r in enumerate(t):
        k = r['key']
        if k in seen:
            out.append('%s is on two rows' % k)
        seen.add(k)
        if int(r['new']) != first + i:
            out.append('%s: new id %s, the row at line %d must be %d' % (k, r['new'], i, first + i))
        if not r['name'].strip():
            out.append('%s: no name' % k)
        if int(r['tier']) not in BANDS or r['role'] not in ROLES or r['float'] not in ('0', '1'):
            out.append('%s: tier %s, role %s, float %s' % (k, r['tier'], r['role'], r['float']))
        n = tiles_of_text(r['tiles'])
        if n is None:
            out.append('%s: size %s is not NxN of %d to %d tiles' % (k, r['tiles'], MIN_TILES, MAX_TILES))
            continue
        d = disp_of_text(r['disp'])
        if d is None or d[0] > 0 or d[1] > 64 or d[1] < -64 or d[0] < -64:
            out.append('%s: displacement %s, a negative x and |y| of 64 at most are wanted' % (k, r['disp']))
        if not MIN_IDLE <= int(r['idle']) <= MAX_PHASES or int(r['idle_ms']) != idle_ms_for(int(r['idle'])):
            out.append('%s: %s idle phases of %s ms, %d to %d phases, %d ms for that many' % (
                k, r['idle'], r['idle_ms'], MIN_IDLE, MAX_PHASES, idle_ms_for(int(r['idle']))))
        if int(r['walk']) != WALK or int(r['walk_ms']) != WALK_MS:
            out.append('%s: the walk is %d phases of %d ms (row: %s of %s)' % (k, WALK, WALK_MS, r['walk'], r['walk_ms']))
        if not re.fullmatch(r'[0-9a-f]{12}', r['src']):
            out.append('%s: src %s is not 12 hex digits' % (k, r['src']))
        if not re.fullmatch(r'[0-9a-f]{8}', r['pl']):
            out.append('%s: pl %s is not 8 hex digits' % (k, r['pl']))
        if not (r['pixels'] or '').isdigit() or int(r['pixels']) < 1:
            out.append('%s: pixels %s is not the count of opaque pixels of the outfit' % (k, r['pixels']))
    if set(s) != {r['new'] for r in t}:
        out.append('pixellab_monsters.sums and the table name other outfits (%s)' % ', '.join(sorted(set(s) ^ {r['new'] for r in t})))
    return out


# ---------------------------------------------------------------- pictures

def cut(a):
    """alpha cut hard at one half: opaque or nothing, nothing under a clear pixel"""
    return G.cut(a)


def union_box(frames):
    import numpy as np
    x0 = y0 = 10 ** 6
    x1 = y1 = -1
    for lst in frames.values():
        for a in lst:
            ys, xs = np.nonzero(a[..., 3] > 0)
            if not len(xs):
                raise ValueError('an empty picture')
            x0, x1, y0, y1 = min(x0, int(xs.min())), max(x1, int(xs.max())), min(y0, int(ys.min())), max(y1, int(ys.max()))
    return x0, y0, x1, y1


def stand_of(frames, floating):
    """(x, y) of a figure's standing point in the pixels of its pictures: the median of the four directions' feet (the first idle
    picture of each, gen_outfit_anchors.measure, the O585 measure); a floating thing has no feet: the middle of its box and its lowest row"""
    import numpy as np
    if floating:
        x0, _y0, x1, y1 = union_box(frames)
        return (x0 + x1 + 1) / 2.0, float(y1)
    from gen_outfit_anchors import measure
    feet = [measure(frames[('idle', d)][0][..., 3])[:2] for d in range(4)]
    return float(np.median([f[0] for f in feet])), float(np.median([f[1] for f in feet]))


def near(centre):
    """0, 1, -1, 2, -2 ... around `centre`"""
    yield centre
    for k in range(1, 130):
        yield centre + k
        yield centre - k


def fit(frames, floating):
    """(tiles, (dx, dy), (shift x, shift y)) of a figure: the smallest canvas of whole tiles that holds its box, the displacement nearest
    (-(16 N - 16), 0) that lets the standing point land on the tile's (TX, ty) after one whole pixel shift of every picture"""
    x0, y0, x1, y1 = union_box(frames)
    sx, sy = stand_of(frames, floating)
    for n in range(MIN_TILES, MAX_TILES + 1):
        c = 32 * n
        if x1 - x0 + 1 > c or y1 - y0 + 1 > c:
            continue
        ty = FLOAT_LOW if floating else min(TY[n], 31 + HANG - (y1 - sy))
        for dx in near(-(16 * n - 16)):
            shx = int(math.floor(c - 32 + dx + TX - sx + 0.5))
            if x0 + shx >= 0 and x1 + shx <= c - 1:
                break
        else:
            continue
        for dy in near(0):
            shy = int(math.floor(c - 32 + dy + ty - sy + 0.5))
            if y0 + shy >= 0 and y1 + shy <= c - 1:
                break
        else:
            continue
        return n, (dx, dy), (shx, shy)
    raise ValueError('a figure of %dx%d px does not fit a canvas of %d tiles' % (x1 - x0 + 1, y1 - y0 + 1, MAX_TILES))


def place_checked(frames, n, shift):
    """{key: [canvas arrays]}: every picture on an N x N canvas moved by one shift; the opaque pixels all land inside the canvas (fit() proved it)"""
    import numpy as np
    c = 32 * n
    out = {}
    for k, lst in frames.items():
        res = []
        for a in lst:
            cv = np.zeros((c, c, 4), np.uint8)
            ys, xs = np.nonzero(a[..., 3] > 0)
            cv[ys + shift[1], xs + shift[0]] = a[ys, xs]
            res.append(cv)
        out[k] = res
    return out


def opaque(a):
    return int((a[..., 3] > 0).sum())


def stand_placed(placed, n, disp, floating):
    """(x, y) of the standing point on the creature's tile, from the cells of an outfit (the same measure as before the move)"""
    sx, sy = stand_of(placed, floating)
    ox, oy = tile_origin(n, disp)
    return sx - ox, sy - oy


def hang_of(placed, n, disp):
    """rows the lowest opaque pixel of any picture is under the tile's last row (negative: over it)"""
    import numpy as np
    low = max(int(np.nonzero(a[..., 3] > 0)[0].max()) for lst in placed.values() for a in lst)
    return low - (tile_origin(n, disp)[1] + 31)


def expected_y(placed, n, disp, floating):
    """the y the standing point has on the tile by the rule: FLOAT_LOW for a floating thing, else TY of the size, less what hangs"""
    if floating:
        return float(FLOAT_LOW)
    import numpy as np
    low = max(int(np.nonzero(a[..., 3] > 0)[0].max()) for lst in placed.values() for a in lst)
    oy = tile_origin(n, disp)[1]
    sy = stand_of(placed, False)[1] - oy
    return float(min(TY[n], 31 + HANG - (low - oy - sy)))


# ---------------------------------------------------------------- the sheets

def sheet_path(key, root=None):
    return os.path.join(SHEETS if root is None else root, key + '.png')


def cells_of(sheet, n, idle, walk):
    """{(group, direction): [cells]} of a sheet array: columns north east south west, rows the idle then the walk pictures"""
    c = 32 * n
    out = {}
    for d in range(4):
        out[('idle', d)] = [sheet[p * c:(p + 1) * c, d * c:(d + 1) * c] for p in range(idle)]
        out[('walk', d)] = [sheet[(idle + p) * c:(idle + p + 1) * c, d * c:(d + 1) * c] for p in range(walk)]
    return out


def sheet_of(placed, n, idle, walk):
    import numpy as np
    c = 32 * n
    sheet = np.zeros(((idle + walk) * c, 4 * c, 4), np.uint8)
    for d in range(4):
        for p, a in enumerate(placed[('idle', d)]):
            sheet[p * c:(p + 1) * c, d * c:(d + 1) * c] = a
        for p, a in enumerate(placed[('walk', d)]):
            sheet[(idle + p) * c:(idle + p + 1) * c, d * c:(d + 1) * c] = a
    return sheet


def read_sheet(r, root=None):
    """(sheet array, {(group, direction): cells}) of a table row"""
    import numpy as np
    from PIL import Image
    a = np.array(Image.open(sheet_path(r['key'], root)).convert('RGBA'))
    n, ni, nw = tiles_of_text(r['tiles']), int(r['idle']), int(r['walk'])
    if a.shape != ((ni + nw) * 32 * n, 4 * 32 * n, 4):
        raise SystemExit('%s: sheet is %s, %d x %d tiles of %d + %d pictures are %s' % (
            r['key'], a.shape, n, n, ni, nw, ((ni + nw) * 32 * n, 4 * 32 * n, 4)))
    return a, cells_of(a, n, ni, nw)


def digest12(key, root=None):
    return hashlib.sha256(open(sheet_path(key, root), 'rb').read()).hexdigest()[:12]


def measure_cells(r, cells):
    """facts of a row's placed cells: pixels, distinct pictures, standing point and hang on the tile, direction pictures"""
    n = tiles_of_text(r['tiles'])
    disp = disp_of_text(r['disp'])
    fl = r['float'] == '1'
    return {'pixels': sum(opaque(a) for lst in cells.values() for a in lst),
            'idle': len(cells[('idle', 0)]), 'walk': len(cells[('walk', 0)]),
            'idle_distinct': min(W.distinct(cells[('idle', d)]) for d in range(4)),
            'walk_distinct': min(W.distinct(cells[('walk', d)]) for d in range(4)),
            'dirs': len({cells[('idle', d)][0].tobytes() for d in range(4)}),
            'stand': stand_placed(cells, n, disp, fl), 'want_y': expected_y(cells, n, disp, fl), 'hang': hang_of(cells, n, disp)}


def sheet_problems(r, cells):
    """the rules of a sheet: hard alpha, no empty picture, four directions of their own, an idle and a walk that move, the standing point"""
    import numpy as np
    k, out = r['key'], []
    n = tiles_of_text(r['tiles'])
    if n is None:
        return ['%s: size %s' % (k, r['tiles'])]
    if disp_of_text(r['disp']) is None:
        return ['%s: displacement %s' % (k, r['disp'])]
    c = 32 * n
    for (g, d), lst in sorted(cells.items()):
        for p, a in enumerate(lst):
            if a.shape != (c, c, 4):
                out.append('%s: %s %s picture %d is %s' % (k, g, DIRS[d], p, a.shape))
                continue
            al = a[..., 3]
            if (al[(al != 0) & (al != 255)]).size:
                out.append('%s: %s %s picture %d has soft alpha' % (k, g, DIRS[d], p))
            if a[al == 0].any():
                out.append('%s: %s %s picture %d has colour under a clear pixel' % (k, g, DIRS[d], p))
            if not al.any():
                out.append('%s: %s %s picture %d is empty' % (k, g, DIRS[d], p))
    if out:
        return out
    m = measure_cells(r, cells)
    if m['dirs'] != 4:
        out.append('%s: %d different standing pictures, 4 wanted (a direction is a copy of another)' % (k, m['dirs']))
    if m['idle_distinct'] < 2:
        out.append('%s: an idle direction shows one picture (the O533 rule: a hunt monster moves while it stands)' % k)
    if m['walk_distinct'] < 4:
        out.append('%s: a walk direction shows %d different pictures, 4 or more wanted' % (k, m['walk_distinct']))
    sx, sy = m['stand']
    if abs(sx - TX) > STAND_TOL or abs(sy - m['want_y']) > STAND_TOL:
        out.append('%s: stands on tile point (%.1f, %.1f), the rule is (%.1f, %.1f)' % (k, sx, sy, TX, m['want_y']))
    if r['float'] == '0' and m['hang'] > HANG:
        out.append('%s: the lowest pixel hangs %d rows under the tile, %d at most' % (k, m['hang'], HANG))
    if m['pixels'] != int(r['pixels']):
        out.append('%s: %d opaque pixels on the sheet, the table counts %s' % (k, m['pixels'], r['pixels']))
    if (m['idle'], m['walk']) != (int(r['idle']), int(r['walk'])):
        out.append('%s: %d + %d pictures on the sheet, the table says %s + %s' % (k, m['idle'], m['walk'], r['idle'], r['walk']))
    return out


def outfit_of(r, cells):
    """the measure dict groups_of() reads"""
    return {'tiles': tiles_of_text(r['tiles']), 'idle': int(r['idle']), 'walk': int(r['walk']), 'idle_ms': int(r['idle_ms']),
            'walk_ms': int(r['walk_ms']), 'placed': cells}


def groups_of(r, cells):
    return G.groups_of(outfit_of(r, cells))


def digest_of(r, cells):
    return W.spec_digest(groups_of(r, cells))


def sums_text(sums):
    return ('# sha256 of each outfit (shapes, animator, every sprite slot) by outfit id, written by gen_pixellab_monsters.py art --write (O640)\n'
            + ''.join('%s %s\n' % (k, sums[k]) for k in sorted(sums, key=int)))


def table_text(rs):
    return ','.join(HEADER) + '\n' + ''.join(','.join(r[k] for k in HEADER) + '\n' for r in rs)


# ---------------------------------------------------------------- the monsters (the server map)

def picks_rows(path=PICKS):
    """[(monster, new look, lib id)] of the rows of family `pixellab` of monster_looks/picks.csv, in file order (lib id = the outfit's
    number in the table, new - 3530)"""
    with open(path, newline='', encoding='utf-8') as f:
        return [(r['monsters'], int(r['look']), int(r['lib_id'])) for r in csv.DictReader(f) if r['family'] == FAMILY]


def pool_levels(path=W.POOL):
    """{monster name: level} of the committed bounty pool hunt list"""
    text = open(path, encoding='utf-8').read().split('bosses = {')[0]
    return {m.group(1).replace('\\"', '"'): int(m.group(2))
            for m in re.finditer(r'\{name = "((?:[^"\\]|\\.)*)", level = (\d+),', text)}


def old_looks(own=None, pool=None):
    return G.old_looks(own, pool)


def map_rows(picks=None, old=None):
    p = picks_rows() if picks is None else picks
    have = old_looks() if old is None else old
    return [(m, have[m], new) for m, new, _d in p]


def map_text(rows_):
    return ','.join(MAP_HEADER) + '\n' + ''.join('%s,%d,%d\n' % r for r in rows_)


def map_problems(table=None, picks=None, old=None, levels=None, hunt=None, first=FIRST_NEW):
    """The `pixellab` rows of picks.csv against the outfit table and the pool: each look is a table outfit (and its lib id), worn by exactly
    one monster (no two hunt monsters share a look), each monster once, known (a file of ours or a row of the pool), a hunt monster of the
    pool, in the level band of the tier of its look."""
    t = rows() if table is None else table
    p = picks_rows() if picks is None else picks
    have = old_looks() if old is None else old
    lv = pool_levels() if levels is None else levels
    by = {int(r['new']): (int(r['new']) - first + 1, int(r['tier'])) for r in t}
    out, seen, used = [], set(), {}
    for m, new, d in p:
        if new not in by or by[new][0] != d:
            out.append('%s: look %d / lib id %d is not a row of pixellab_monsters.csv' % (m, new, d))
        used[new] = used.get(new, 0) + 1
        if used[new] > MAX_ON_LOOK:
            out.append('look %d is on more than %d monster: no two hunt monsters share a look (O529)' % (new, MAX_ON_LOOK))
        if m in seen:
            out.append('%s is on two rows of picks.csv' % m)
        seen.add(m)
        if m not in have:
            out.append('%s has no monster file of ours and no row of the bounty pool' % m)
        if m not in lv:
            out.append('%s is not a hunt monster of the bounty pool (a look of O640 goes to a hunt monster)' % m)
        elif new in by:
            lo, hi = BANDS[by[new][1]]
            if not lo <= lv[m] <= hi:
                out.append('%s: level %d, the band of tier %d is %d to %d' % (m, lv[m], by[new][1], lo, hi))
    for new in sorted(set(by) - set(used)):
        out.append('outfit %d is worn by no monster of picks.csv' % new)
    return out


def write_map(check=False):
    """write monster_pixellab_looks.csv (monster, look, new_look), or with check compare it; returns the problem lines"""
    try:
        text = map_text(map_rows())
    except KeyError:
        return []   # map_problems names the monster
    old = open(MAP, encoding='utf-8', newline='').read() if os.path.exists(MAP) else None
    if old == text:
        return []
    if check:
        return ['server/data/monster/monster_pixellab_looks.csv is not up to date (run gen_pixellab_monsters.py looks)']
    with open(MAP, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return []


# ---------------------------------------------------------------- the PixelLab downloads

def source_dir(key, srcs):
    for s in srcs:
        for name in (key, 't3_' + key, 't4_' + key):
            p = os.path.join(s, name)
            if os.path.isdir(os.path.join(p, 'idle')) and os.path.isdir(os.path.join(p, 'walk')):
                return p
    raise SystemExit('no download of %s under %s' % (key, ', '.join(srcs)))


def load_source(path):
    """({(group, direction): [pictures, alpha cut]}, the pictures' size): DIR/idle|walk/south|east|north|west/NN.png"""
    import numpy as np
    from PIL import Image
    out, size = {}, None
    for g in ('idle', 'walk'):
        for d, name in enumerate(DIRS):
            folder = os.path.join(path, g, name)
            files = sorted(f for f in os.listdir(folder) if f.lower().endswith('.png')) if os.path.isdir(folder) else []
            if not files:
                raise SystemExit('%s: no pictures' % folder)
            lst = []
            for f in files:
                a = np.array(Image.open(os.path.join(folder, f)).convert('RGBA'))
                if size is None:
                    size = a.shape[:2]
                if a.shape[:2] != size:
                    raise SystemExit('%s: a picture of %s, the others are %s' % (os.path.join(folder, f), a.shape[:2], size))
                lst.append(cut(a))
            out[(g, d)] = lst
    for g in ('idle', 'walk'):
        if len({len(out[(g, d)]) for d in range(4)}) != 1:
            raise SystemExit('%s: the four directions have different numbers of %s pictures' % (path, g))
    return out, size


def pl_id(path):
    """the first 8 hex digits of the PixelLab character or object id of a download (its ids.json)"""
    import json
    j = json.load(open(os.path.join(path, 'ids.json'), encoding='utf-8'))
    v = j.get('id') or j.get('object_id') or j.get('character_id')
    if not v:
        raise SystemExit('%s: ids.json names no id' % path)
    return v.replace('-', '')[:8]


def make(spec, first_row, srcs):
    """(table row, cells, source pixels) of a SPEC entry from the PixelLab download of its key"""
    key, name, tier, role, fl = spec
    path = source_dir(key, srcs)
    frames, _size = load_source(path)
    src_px = sum(opaque(a) for lst in frames.values() for a in lst)
    n, disp, shift = fit(frames, bool(fl))
    placed = place_checked(frames, n, shift)
    ni, nw = len(frames[('idle', 0)]), len(frames[('walk', 0)])
    r = {'key': key, 'name': name, 'tier': str(tier), 'role': role, 'float': str(fl), 'new': str(first_row), 'tiles': '%dx%d' % (n, n),
         'disp': '%d:%d' % disp, 'idle': str(ni), 'idle_ms': str(idle_ms_for(ni)), 'walk': str(nw), 'walk_ms': str(WALK_MS),
         'pixels': str(sum(opaque(a) for lst in placed.values() for a in lst)), 'src': '0' * 12, 'pl': pl_id(path)}
    if int(r['pixels']) != src_px:
        raise SystemExit('%s: %s opaque pixels placed, %d in the download: a pixel was lost' % (key, r['pixels'], src_px))
    return r, placed, frames


def art(srcs, write, only=()):
    from PIL import Image
    table, sums, bad = [], {}, []
    old = {r['key']: r for r in rows()} if os.path.exists(TABLE) else {}
    for i, spec in enumerate(SPEC):
        if only and spec[0] not in only:
            if spec[0] in old:
                table.append(old[spec[0]])
            continue
        r, placed, frames = make(spec, FIRST_NEW + i, srcs)
        sheet = sheet_of(placed, tiles_of_text(r['tiles']), int(r['idle']), int(r['walk']))
        os.makedirs(SHEETS, exist_ok=True)
        tmp = os.path.join(SHEETS, '.tmp.png')
        Image.fromarray(sheet).save(tmp, optimize=True)
        r['src'] = hashlib.sha256(open(tmp, 'rb').read()).hexdigest()[:12]
        cells = cells_of(sheet, tiles_of_text(r['tiles']), int(r['idle']), int(r['walk']))
        p = sheet_problems(r, cells)
        m = measure_cells(r, cells)
        print('%-11s %s outfit %s  idle %2s x %3s ms  walk %s  pixels %7s  stand (%.1f, %.1f) want y %.1f hang %d  %s' % (
            r['key'], r['tiles'], r['new'], r['idle'], r['idle_ms'], r['walk'], r['pixels'], m['stand'][0], m['stand'][1], m['want_y'],
            m['hang'], 'ok' if not p else p))
        bad += p
        if write:
            os.replace(tmp, sheet_path(r['key']))
        else:
            os.remove(tmp)
        table.append(r)
        sums[r['new']] = digest_of(r, cells)
    if write and not bad:
        with open(TABLE, 'w', encoding='utf-8', newline='') as f:
            f.write(table_text(table))
        if not only:
            with open(SUMS, 'w', encoding='utf-8', newline='') as f:
                f.write(sums_text(sums))
    return bad


# ---------------------------------------------------------------- check

def check_sheets(table=None, sums=None, root=None):
    """problem lines of every sheet of the table: the rules, the digest of the file (src), the digest of the outfit (sums)"""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out = []
    for r in t:
        if not os.path.exists(sheet_path(r['key'], root)):
            out.append('%s: no sheet art_import/pixellab_monsters/%s.png' % (r['key'], r['key']))
            continue
        _a, cells = read_sheet(r, root)
        out += sheet_problems(r, cells)
        if digest12(r['key'], root) != r['src']:
            out.append('%s: the sheet file is not the one of the table (src %s)' % (r['key'], r['src']))
        if s.get(r['new']) and digest_of(r, cells) != s[r['new']]:
            out.append('%s: the outfit made from the sheet is not the one of pixellab_monsters.sums' % r['key'])
    if root is None and os.path.isdir(SHEETS):
        extra = sorted(set(f[:-4] for f in os.listdir(SHEETS) if f.endswith('.png')) - {r['key'] for r in t})
        if extra:
            out.append('sheets with no row in the table: %s' % ', '.join(extra))
    return out


def check():
    p = problems() + map_problems() + write_map(check=True)
    if not p:
        p += check_sheets()
    return p


# ---------------------------------------------------------------- the pair

def pair_ok(n_outfits, first=FIRST_NEW):
    """None when the pair is the one this step needs (first - 1 outfits), else the reason it is refused"""
    if n_outfits == first - 1:
        return None
    if n_outfits == first - 2:
        return ('the input pair ends at outfit %d: Malgrath (outfit %d, O637, gen_malgrath_boss.py build) has not been built into it. '
                'Build that step first: the PixelLab monsters are outfits %d to %d' % (n_outfits, first - 1, first, first + len(SPEC) - 1))
    return 'the input pair has %d outfits, this step needs %d (pair 74 after Malgrath)' % (n_outfits, first - 1)


def build(dat, spr, out_dir, table=None, first=FIRST_NEW, root=None, log=print):
    """pair in (its outfits end at first - 1) -> pair out in OUT_DIR: one new outfit per row of the table, read from the committed sheets.
    Returns the new ids."""
    sys.path.insert(0, HERE)
    from datspr import Dat
    t = rows() if table is None else table
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    why = pair_ok(len(Dat(dat).outfits), first)
    if why:
        raise SystemExit('refused: ' + why)
    by = {}
    for r in t:
        _a, cells = read_sheet(r, root)
        by[r['new']] = (r, cells)
    return W.build(dat, spr, out_dir, None, table=t, first=first, log=log, specs_of=lambda r: groups_of(*by[r['new']]), flags_of=flags_of)


def outfit_frames(dat, spr, nid, n, gs=None):
    """{(group, direction): [canvas array of each phase]} of an outfit read from a pair, plus its groups"""
    import numpy as np
    from import_outfits import parse_body
    gs = parse_body(dat, dat.outfit(nid)) if gs is None else gs
    c = 32 * n
    out = {}
    for g, key in zip(gs, ('idle', 'walk')):
        for dd in range(4):
            lst = []
            for ph in range(g.phases):
                a = np.zeros((c, c, 4), np.uint8)
                for hh in range(n):
                    for ww in range(n):
                        sid = g.sprites[((ph * 4 + dd) * n + hh) * n + ww]
                        tl = spr.sprite(sid) if sid else None
                        if tl is not None:
                            a[(n - 1 - hh) * 32:(n - hh) * 32, (n - 1 - ww) * 32:(n - ww) * 32] = tl
                lst.append(a)
            out[(key, dd)] = lst
    return out, gs


def live(dat_path, spr_path, table=None, sums=None, first=FIRST_NEW, root=None, log=print):
    """The pair holds every outfit at its id: its digest the one of the sums, the sheet's pictures in every cell, its size, one layer, an idle
    and a walk group, the displacement as its only flag, every phase its duration, the standing point of the rule on the tile. Returns the
    problem lines."""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_outfits import parse_body
    import numpy as np
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    d, sp = Dat(dat_path), Spr(spr_path)
    last = int(t[-1]['new'])
    if len(d.outfits) < last:
        return ['the pair has %d outfits, the PixelLab monsters end at %d' % (len(d.outfits), last)]
    out = []
    for r in t:
        nid, k = int(r['new']), r['key']
        n = tiles_of_text(r['tiles'])
        th = d.outfit(nid)
        if dict(th.flags) != flags_of(r)[1]:
            out.append('outfit %d (%s): flags %s, the displacement %s only' % (nid, k, dict(th.flags), r['disp']))
            continue
        gs = parse_body(d, th)
        if [g.gtype for g in gs] != [0, 1] or any(g.layers != 1 or (g.w, g.h) != (n, n) for g in gs):
            out.append('outfit %d (%s): not an idle and a walk group of %s with one layer' % (nid, k, r['tiles']))
            continue
        if (gs[0].phases, gs[1].phases) != (int(r['idle']), int(r['walk'])):
            out.append('outfit %d (%s): %d / %d phases, the table says %s / %s' % (nid, k, gs[0].phases, gs[1].phases, r['idle'], r['walk']))
            continue
        frames, gs = outfit_frames(d, sp, nid, n, gs)
        for g, key in zip(gs, ('idle', 'walk')):
            ms = int(r[key + '_ms'])
            if not g.anim or tuple(g.anim[3]) != (ms, ms) * g.phases:
                out.append('outfit %d (%s): the %s phases do not last %d ms each' % (nid, k, key, ms))
        if W.digest(d, sp, nid) != s.get(r['new']):
            out.append('outfit %d (%s): the pictures are not the ones of pixellab_monsters.sums' % (nid, k))
        total = sum(opaque(a) for lst in frames.values() for a in lst)
        if total != int(r['pixels']):
            out.append('outfit %d (%s): %d opaque pixels in its sprites, the table counts %s' % (nid, k, total, r['pixels']))
        if os.path.exists(sheet_path(k, root)):
            _a, cells = read_sheet(r, root)
            if any(not np.array_equal(a, b) for key2 in cells for a, b in zip(cells[key2], frames[key2])):
                out.append('outfit %d (%s): a picture is not the one of the sheet' % (nid, k))
        m = measure_cells(r, frames)
        if abs(m['stand'][0] - TX) > STAND_TOL or abs(m['stand'][1] - m['want_y']) > STAND_TOL:
            out.append('outfit %d (%s): stands on tile point (%.1f, %.1f), the rule is (%.1f, %.1f)' % (nid, k, m['stand'][0], m['stand'][1], TX, m['want_y']))
        if r['float'] == '0' and m['hang'] > HANG:
            out.append('outfit %d (%s): the lowest pixel hangs %d rows under the tile' % (nid, k, m['hang']))
    log('live: %d outfits %d to %d checked, %d problems' % (len(t), int(t[0]['new']), last, len(out)))
    return out


# ---------------------------------------------------------------- the preview (never committed)

def preview(out_dir, dat_path, spr_path, table=None, first=FIRST_NEW, log=print):
    """monsters_ingame.mp4 in OUT_DIR, drawn from the built pair as the client draws it (the canvas over the tile by the displacement):
    one page a tier, the south idle and the walk of the four directions at 2x, then every monster at 1x on stone tiles"""
    sys.path.insert(0, HERE)
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
    from datspr import Dat, Spr
    t = rows() if table is None else table
    d, sp = Dat(dat_path), Spr(spr_path)
    os.makedirs(out_dir, exist_ok=True)
    fr_dir = os.path.join(out_dir, 'frames')
    shutil.rmtree(fr_dir, ignore_errors=True)
    os.makedirs(fr_dir)
    font = ImageFont.load_default(size=13)
    font_s = ImageFont.load_default(size=11)
    BG, STONE = (30, 30, 34), ((52, 52, 57), (46, 46, 51))
    data = {}
    for r in t:
        n = tiles_of_text(r['tiles'])
        frames, _gs = outfit_frames(d, sp, int(r['new']), n)
        data[r['key']] = (r, n, disp_of_text(r['disp']), frames)
    pages = [[r for r in t if int(r['tier']) == k] for k in (1, 2, 3, 4)]
    fps, rows_ = 20, (('idle south', 'idle', SOUTH), ('walk south', 'walk', SOUTH), ('walk east', 'walk', 1), ('walk north', 'walk', 0), ('walk west', 'walk', 3))
    cw = max(32 * data[r['key']][1] * 2 for r in t) + 16
    ch = cw
    X0, LAB = 80, 46
    big = max(len(p) for p in pages)
    W_, H_ = X0 + cw * big, LAB + ch * len(rows_) + 170
    W_ += W_ % 2
    H_ += H_ % 2

    def tile_bg(dr, x, y, w, h, s):
        for ty in range(0, h, 32 * s):
            for tx in range(0, w, 32 * s):
                dr.rectangle([x + tx, y + ty, x + tx + 32 * s - 1, y + ty + 32 * s - 1], fill=STONE[((tx + ty) // (32 * s)) % 2])

    def draw(im, dr, key, kind, dd, ms, x0, y0, w, h, s):
        """the picture of `key` at time ms on its canvas, centred on the panel (x0, y0, w, h) and standing on its bottom edge, scale s;
        the creature's own tile is outlined where the displacement puts it"""
        r, n, disp, frames = data[key]
        lst = frames[(kind, dd)]
        a = lst[(ms // int(r[kind + '_ms'])) % len(lst)]
        c = 32 * n * s
        cx, cy = x0 + (w - c) // 2, y0 + h - 4 - c
        img = Image.fromarray(a, 'RGBA')
        if s != 1:
            img = img.resize((img.width * s, img.height * s), Image.NEAREST)
        ox, oy = tile_origin(n, disp)
        dr.rectangle([cx + ox * s, cy + oy * s, cx + ox * s + 32 * s - 1, cy + oy * s + 32 * s - 1], outline=(95, 95, 105))
        im.paste(img, (cx, cy), img)

    count = 0
    for page in pages:
        for tt in range(fps * 4):
            ms = tt * 1000 // fps
            im = Image.new('RGB', (W_, H_), BG)
            dr = ImageDraw.Draw(im)
            for c, r in enumerate(page):
                x0 = X0 + c * cw
                dr.text((x0 + 4, 6), '%s' % r['name'], font=font, fill=(235, 235, 235))
                dr.text((x0 + 4, 24), 'T%s (%s) outfit %s %s' % (r['tier'], r['role'], r['new'], r['tiles']), font=font_s, fill=(230, 120, 100))
            for ri, (lab, kind, dd) in enumerate(rows_):
                y0 = LAB + ri * ch
                dr.line([(0, y0), (W_, y0)], fill=(52, 52, 58))
                dr.text((4, y0 + ch // 2 - 6), lab, font=font_s, fill=(150, 150, 160))
                for c, r in enumerate(page):
                    x0 = X0 + c * cw
                    tile_bg(dr, x0, y0 + 4, cw - 8, ch - 8, 2)
                    draw(im, dr, r['key'], kind, dd, ms, x0, y0 + 4, cw - 8, ch - 8, 2)
            y0 = LAB + len(rows_) * ch
            dr.line([(0, y0), (W_, y0)], fill=(52, 52, 58))
            dr.text((4, y0 + 60), '1x south\ngame size', font=font_s, fill=(150, 150, 160))
            for c, r in enumerate(page):
                x0 = X0 + c * cw
                tile_bg(dr, x0, y0 + 6, cw - 8, 150, 1)
                walking = (ms // 1000) % 2 == 1
                draw(im, dr, r['key'], 'walk' if walking else 'idle', SOUTH, ms, x0, y0 + 6, cw - 8, 150, 1)
            dr.text((X0, y0 + 158), 'true game size on 32 px tiles (outlined: the creature\'s own tile), idle one second, walking the next', font=font_s, fill=(120, 120, 130))
            im.save(os.path.join(fr_dir, 'f%05d.png' % count))
            count += 1
    out = os.path.join(out_dir, 'monsters_ingame.mp4')
    subprocess.check_call(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(fps), '-i', os.path.join(fr_dir, 'f%05d.png'), '-c:v', 'libx264',
                           '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', out])
    shutil.rmtree(fr_dir, ignore_errors=True)
    log('preview: %s %dx%d, %d frames' % (out, W_, H_, count))
    return out


# ---------------------------------------------------------------- command line

def numbers():
    for r in rows():
        _a, cells = read_sheet(r)
        m = measure_cells(r, cells)
        print('%-11s outfit %s %s disp %-7s idle %2s walk %s pixels %7s stand (%.1f, %.1f) hang %d dirs %d idle pics %d walk pics %d' % (
            r['key'], r['new'], r['tiles'], r['disp'], r['idle'], r['walk'], r['pixels'], m['stand'][0], m['stand'][1], m['hang'],
            m['dirs'], m['idle_distinct'], m['walk_distinct']))


def main(argv):
    a = list(argv)
    cmd = a.pop(0) if a else ''
    if cmd == 'check':
        p = check()
        for line in p:
            print('PROBLEM', line)
        print('pixellab_monsters: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if cmd == 'looks':
        p = map_problems() + write_map(check='--check' in a)
        for line in p:
            print('PROBLEM', line)
        print('monster_pixellab_looks: %d rows, %d problems' % (len(picks_rows()), len(p)))
        return 1 if p else 0
    if cmd == 'numbers':
        numbers()
        return 0
    if cmd == 'art':
        srcs = []
        while '--src' in a:
            srcs.append(W.opt(a, '--src'))
        if not srcs:
            print(__doc__)
            return 2
        only = [x for x in a if not x.startswith('--')]
        bad = art(srcs, '--write' in a, only)
        for line in bad:
            print('PROBLEM', line)
        return 1 if bad else 0
    if cmd == 'build' and len(a) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(a[0], a[1], a[2])
        p = live(os.path.join(a[2], 'Tibia.dat'), os.path.join(a[2], 'Tibia.spr'))
        for line in p:
            print('PROBLEM', line)
        print('built %d outfits %d to %d' % (len(ids), ids[0], ids[-1]))
        return 1 if p else 0
    if cmd == 'live' and len(a) == 2:
        p = live(*a)
        for line in p:
            print('PROBLEM', line)
        return 1 if p else 0
    if cmd == 'preview' and len(a) >= 1:
        dat, spr = W.opt(a, '--dat'), W.opt(a, '--spr')
        if not (dat and spr and len(a) == 1):
            print(__doc__)
            return 2
        preview(a[0], dat, spr)
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
