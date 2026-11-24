#!/usr/bin/env python3
"""Cliff pieces of our own, drawn by code (O746; joins client pair 83): the rock face below a raised edge and the lip of its top,
for the plateaus of the area planner (server/README.md "Plateaus and cliffs (O744)"; client/MANIFEST.md "Cliff pieces (O746)").

    python3 -I gen_cliff_art.py table [--write]          # the table art_import/cliff_art.csv and cliff_art.sums (--write writes them)
    python3 -I gen_cliff_art.py check                    # CI, no pair: table, sums, the rules of every piece, style_check
    python3 -I gen_cliff_art.py sheets OUT_DIR           # PNG sheets of both palettes at 1x and 4x (never committed)
    python3 -I gen_cliff_art.py preview OUT_DIR          # a sample plateau drawn from the pieces: PNG and MP4 (ffmpeg; never committed)
    python3 -I gen_cliff_art.py quality OUT_DIR          # sprite_quality.py check --kind item of every piece (prints the rows it misses)
    python3 -I gen_cliff_art.py build DAT SPR OUT_DIR    # pair 82 (dat md5 ee8c32fc...) -> OUT_DIR/Tibia.dat, Tibia.spr; any other pair refused
    python3 -I gen_cliff_art.py live DAT SPR             # a built pair holds every piece at its id, pixel for pixel

No art file is read and no outside art or service is used: every pixel comes from this script (integer maths and a seeded integer
generator, so the same bytes on every machine). Only the committed table and the sums are in git; `check` draws the pieces again and
holds them to the sums.

The view (docs/SPRITE_STYLE.md "View and light", the game's oblique angle of O728): a thing one floor up is drawn 32 px up and left, so
of a raised footprint F the visible rock is the south face and the east face. In screen space the south face is a band of horizontal
strata with joints running down to the right (a vertical line of the face, sheared); the east face shows its strata as vertical lines
(a level line of an east face is a vertical screen line) and its joints on the same diagonal. Both are periodic: the south face in x,
the east face in y, so the pieces tile side by side in any order of their variants (the variants differ only away from the tile edge).
A tile c of F is visible when its south-east neighbour is not in F; its piece follows from its south (S) and east (E) neighbours:

    S out, E in   face_s_a / face_s_b   the south face (variant by position)
    S in,  E out  face_e_a / face_e_b   the east face
    S out, E out  outer_se              outer corner: south face lower left, east face upper right, a lit ridge on the diagonal
    S in,  E in   inner_se_a / _b       inner corner: east face lower left, south face upper right, a dark crease on the diagonal
  and on the tile beside the face where it turns out of view (the face of c spills a triangle there):
    outer_sw  on the tile west of a south face whose west neighbour is out: the face's end, upper right triangle, outlined
    outer_ne  on the tile north of an east face whose north neighbour is out: the face's top end, lower left triangle, outlined
The oblique view shows one kind of concave corner only (where a south face meets an east face, inner_se); it has two variants. The
other three corners are convex (the south-east turn and the two ends). The lip: the 12 border pieces of the planner's piece order
(n e s w cnw cne csw cse dnw dne dse dsw; ChaosAreaGenCore.borderPieces, map_tile_rules.border_pieces): a rock edge on the lower
tile, the higher ground in the named directions, its free edge outlined, lit where it faces the light (top left) and shaded where it
faces away. Two palettes: stone (the grey ramp of the theme blightfang) and earth (the brown and red ramps of bloodmoon, for caves).

Ids: 42 items appended to pair 82 (44,563 items) at client ids 44564-44605, server id = client id + 4000 (48564-48605, the decor
flames rule). Kind border: items.otb group 0, flag ONTOP, top order 1; dat flags clip and notmoveable; 1 x 1, one phase. The server
step: server/tools/install_cliff_art.py (install_all step `cliffart`, behind client_pair.PAIR_CLIFF = 83).
Needs numpy and Pillow (the fx venv of CI), ffmpeg for `preview`.
"""
import csv
import hashlib
import io
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import style_check as sc  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'cliff_art.csv')
SUMS = os.path.join(ART, 'cliff_art.sums')

PAIR = 83
PAIR82_DAT_MD5 = 'ee8c32fc87be4372f4668b635148b9bf'
EXPECT_ITEMS = 44563         # the items of pair 82 (pair 74 appended the last ones, 44560-44563)
FIRST = 44564
SERVER_OFFSET = 4000
CELL = 32
KIND = 'border'
DAT_FLAGS = 'clip notmoveable'
OTB_GROUP, OTB_FLAGS, TOP_ORDER = 0, 1 << 13, 1      # import_art_things.OTB['border']

LIP = ('n', 'e', 's', 'w', 'cnw', 'cne', 'csw', 'cse', 'dnw', 'dne', 'dse', 'dsw')     # the planner's border piece order
FACE = ('face_s_a', 'face_s_b', 'face_e_a', 'face_e_b', 'outer_se', 'outer_sw', 'outer_ne', 'inner_se_a', 'inner_se_b')
WORDS = {'face_s_a': 'south face a', 'face_s_b': 'south face b', 'face_e_a': 'east face a', 'face_e_b': 'east face b',
         'outer_se': 'outer corner south-east', 'outer_sw': 'outer corner south-west', 'outer_ne': 'outer corner north-east',
         'inner_se_a': 'inner corner a', 'inner_se_b': 'inner corner b'}
LIP_WORDS = {'n': 'north', 'e': 'east', 's': 'south', 'w': 'west', 'cnw': 'corner north-west', 'cne': 'corner north-east',
             'csw': 'corner south-west', 'cse': 'corner south-east', 'dnw': 'bend north-west', 'dne': 'bend north-east',
             'dse': 'bend south-east', 'dsw': 'bend south-west'}
NOTE = {'face_s_a': 'the south face; S out, E in', 'face_s_b': 'the south face, second variant',
        'face_e_a': 'the east face; S in, E out', 'face_e_b': 'the east face, second variant',
        'outer_se': 'S out, E out: south face lower left, east face upper right',
        'outer_sw': 'on the tile west of a south face end: the end triangle',
        'outer_ne': 'on the tile north of an east face end: the end triangle',
        'inner_se_a': 'S in, E in, SE out: the concave corner', 'inner_se_b': 'the concave corner, second variant'}

# palette: (theme of style_palettes.json, colours of it in use, luma levels of the parts, seed)
PALETTES = {
    'stone': dict(theme='blightfang', seed=7461,
                  colours=['#1a1818', '#1f2225', '#262a2d', '#2f2d2e', '#2c2428', '#333839', '#3b3935', '#393b41', '#424748',
                           '#4b5154', '#53494e', '#535958', '#5c5257', '#615f5d', '#696664', '#626968', '#6f7a74', '#81837c'],
                  outline=['#010201', '#030303']),
    'earth': dict(theme='bloodmoon', seed=7462,
                  colours=['#301618', '#3a2325', '#3d1913', '#41211e', '#4b302e', '#4a2120', '#5b3e38', '#61352d', '#623721',
                           '#68504b', '#7a412a', '#804f33', '#7f6050', '#955b31', '#8d766b', '#a56d3f', '#a57b54', '#b3977b'],
                  outline=['#060303', '#0b0503']),
}
PALETTE_ORDER = ('stone', 'earth')
FIELDS = ['key', 'palette', 'piece', 'client_id', 'server_id', 'name', 'kind', 'flags', 'otb_group', 'otb_flags', 'top_order',
          'theme', 'note']


def pieces():
    """the table: stone faces, stone lip, earth faces, earth lip"""
    out = []
    cid = FIRST
    for pal in PALETTE_ORDER:
        for p in FACE + LIP:
            lip = p in LIP
            out.append(dict(key='%s_%s' % (pal, ('lip_' + p) if lip else p), palette=pal, piece=('lip_' + p) if lip else p,
                            client_id=cid, server_id=cid + SERVER_OFFSET,
                            name='cliff %s %s' % (pal, ('lip ' + LIP_WORDS[p]) if lip else WORDS[p]), kind=KIND, flags=DAT_FLAGS,
                            otb_group=OTB_GROUP, otb_flags=OTB_FLAGS, top_order=TOP_ORDER, theme=PALETTES[pal]['theme'],
                            note=('lip piece %s: the higher ground %s' % (p, LIP_WORDS[p])) if lip else NOTE[p]))
            cid += 1
    return out


def table_errors(rows):
    errs = []
    if [int(r['client_id']) for r in rows] != list(range(FIRST, FIRST + len(rows))):
        errs.append('client ids are not %d.. in order' % FIRST)
    if len(rows) != len(PALETTE_ORDER) * (len(FACE) + len(LIP)):
        errs.append('%d rows, want %d' % (len(rows), len(PALETTE_ORDER) * (len(FACE) + len(LIP))))
    if len({r['key'] for r in rows}) != len(rows) or len({r['name'] for r in rows}) != len(rows):
        errs.append('keys or names repeat')
    for r in rows:
        if int(r['server_id']) != int(r['client_id']) + SERVER_OFFSET:
            errs.append('%s: server id is client id + %d' % (r['key'], SERVER_OFFSET))
        if not r['name'].startswith('cliff '):
            errs.append('%s: a name starts with "cliff "' % r['key'])
        if r['palette'] not in PALETTES or r['theme'] != PALETTES[r['palette']]['theme']:
            errs.append('%s: palette / theme' % r['key'])
        if (r['kind'], r['flags'], int(r['otb_group']), int(r['otb_flags']), int(r['top_order'])) != (
                KIND, DAT_FLAGS, OTB_GROUP, OTB_FLAGS, TOP_ORDER):
            errs.append('%s: a border piece: clip, not moveable, ONTOP, top order 1' % r['key'])
    return errs


# ------------------------------------------------------------------------------------------------------------- integer maths
class Rand:
    """a seeded integer generator (64-bit LCG, the high bits): the same numbers on every machine"""

    def __init__(self, seed):
        self.s = (seed * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF

    def next(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        return self.s >> 33

    def int(self, lo, hi):
        """lo..hi inclusive"""
        return lo + self.next() % (hi - lo + 1)


def wobble(seed, amp, n=CELL, passes=3):
    """a periodic integer edge profile of n steps in -amp..amp (circular box blur of random steps)"""
    r = Rand(seed)
    v = np.array([r.int(-4 * amp, 4 * amp) for _ in range(n)], np.int64)
    for _ in range(passes):
        v = (np.roll(v, 1) + v + np.roll(v, -1)) // 3
    m = int(np.abs(v).max()) or 1
    v = v - int(v.sum()) // n
    m = int(np.abs(v).max()) or 1
    return np.sign(v) * ((np.abs(v) * amp + m // 2) // m)


def grain(seed, n=CELL, passes=2):
    """a periodic integer value field n x n in about -16..16"""
    r = Rand(seed)
    g = np.array([[r.int(0, 255) for _ in range(n)] for _ in range(n)], np.int64)
    for _ in range(passes):
        g = (g * 4 + np.roll(g, 1, 0) + np.roll(g, -1, 0) + np.roll(g, 1, 1) + np.roll(g, -1, 1)) // 8
    return (g - 128) // 3


def unhex(h):
    return int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)


def luma_of(rgb):
    return (299 * rgb[0] + 587 * rgb[1] + 114 * rgb[2]) // 1000


def ramp(pal):
    """(colours sorted by luma, their lumas) of a palette"""
    cols = sorted((unhex(h) for h in PALETTES[pal]['colours']), key=lambda c: (luma_of(c), c))
    return np.array(cols, np.uint8), np.array([luma_of(c) for c in cols], np.int64)


def paint(L, mask, pal, dark=None):
    """RGBA of a luma field: each pixel the ramp colour of the nearest luma; dark: pixels in the outline colour"""
    cols, lum = ramp(pal)
    idx = np.abs(L[..., None] - lum[None, None, :]).argmin(axis=2)
    out = np.zeros(L.shape + (4,), np.uint8)
    out[..., :3] = cols[idx]
    out[..., 3] = 255
    if dark is not None:
        oc = np.array([unhex(h) for h in PALETTES[pal]['outline']], np.uint8)
        yy, xx = np.nonzero(dark & mask)
        for y, x in zip(yy, xx):
            out[y, x, :3] = oc[(x + y) % len(oc)]
    out[~mask] = 0
    return out


# ------------------------------------------------------------------------------------------------------------- the faces
EDGE = 4        # pixels at the tile edge every variant shares (the joints and block shades of a variant stay inside)


def south_face(pal, variant):
    """the south face as a luma field and its dark lines: periodic in x, horizontal strata, joints down to the right"""
    base_seed = PALETTES[pal]['seed']
    earth = pal == 'earth'
    u = np.arange(CELL)[None, :].repeat(CELL, 0)
    v = np.arange(CELL)[:, None].repeat(CELL, 1)
    L = 128 - (v * 52) // 31                                   # lit under the lip, darker down to the foot
    L += grain(base_seed + 3) // (3 if earth else 4)
    dark = np.zeros((CELL, CELL), bool)
    # strata (shared by every variant): seams at about these rows, wandering a pixel along x
    rows = (6, 14, 21, 27) if not earth else (9, 19, 26)
    band = np.zeros((CELL, CELL), np.int64)
    for k, y0 in enumerate(rows):
        w = wobble(base_seed + 11 + k, 1)
        seam = y0 + w[u]
        dark |= v == seam
        band += v > seam
    shade = np.array([10, 2, -4, 4, -6, 0], np.int64)          # each stratum a little apart
    L += shade[band % len(shade)]
    above = np.zeros((CELL, CELL), bool)                         # the row under a seam is lit, the row over it shaded
    above[1:] = dark[:-1]
    below = np.zeros((CELL, CELL), bool)
    below[:-1] = dark[1:]
    L += np.where(above & ~dark, 16, 0) - np.where(below & ~dark, 10, 0)
    # joints of this variant: short diagonals inside a stratum, away from the tile edge; the block right of a joint is lit
    r = Rand(base_seed * 31 + variant * 977 + 5)
    tops = (0,) + tuple(rows)
    bots = tuple(rows) + (CELL,)
    for k in range(len(tops)):
        y_top, y_bot = tops[k] + 1, bots[k] - 1
        if y_bot - y_top < 2:
            continue
        n_j = 1 if earth else r.int(1, 2)
        for _j in range(n_j):
            x0 = r.int(EDGE, CELL - EDGE - (y_bot - y_top) - 2)
            for y in range(y_top, y_bot + 1):
                x = x0 + (y - y_top)
                if EDGE <= x < CELL - EDGE and not dark[y, x]:
                    dark[y, x] = True
                    if x + 1 < CELL - EDGE:
                        L[y, x + 1] += 14
                    if x - 1 >= EDGE:
                        L[y, x - 1] -= 10
        # the block of this variant: a lighter or darker stone inside the window
        d = r.int(-10, 10)
        win = (v > tops[k]) & (v < bots[k]) & (u >= EDGE + 2) & (u < CELL - EDGE - 2)
        L += np.where(win, d, 0)
    # small highlights of this variant: two to three pixel chips on the lit rows
    for _h in range(3 if not earth else 5):
        y, x = r.int(2, CELL - 4), r.int(EDGE + 1, CELL - EDGE - 3)
        if not dark[y, x] and not dark[y, x + 1]:
            L[y, x] += 34
            L[y, x + 1] += 22
    if earth:      # pebbles in the earth: dark round specks of three pixels, kept off the seams
        for _p in range(4):
            y, x = r.int(2, CELL - 4), r.int(EDGE + 1, CELL - EDGE - 3)
            for yy, xx in ((y, x), (y, x + 1), (y + 1, x)):
                if not dark[yy, xx]:
                    L[yy, xx] -= 26
    L = np.where(dark, 30, L)
    return L


def east_face(pal, variant):
    """the east face: periodic in y, its strata vertical lines, joints on the same diagonal, a shade darker than the south face"""
    base_seed = PALETTES[pal]['seed'] + 500
    earth = pal == 'earth'
    u = np.arange(CELL)[None, :].repeat(CELL, 0)
    v = np.arange(CELL)[:, None].repeat(CELL, 1)
    L = 104 - (u * 44) // 31                                   # the top of the face (left) catches the light
    L += grain(base_seed + 3) // (2 if earth else 4)
    dark = np.zeros((CELL, CELL), bool)
    cols = (7, 15, 22, 28) if not earth else (10, 20, 27)
    band = np.zeros((CELL, CELL), np.int64)
    for k, x0 in enumerate(cols):
        w = wobble(base_seed + 11 + k, 1)
        seam = x0 + w[v]
        dark |= u == seam
        band += u > seam
    shade = np.array([8, 0, -5, 3, -7, 0], np.int64)
    L += shade[band % len(shade)]
    left = np.zeros((CELL, CELL), bool)                           # right of a seam lit (the top of the next stratum)
    left[:, 1:] = dark[:, :-1]
    right = np.zeros((CELL, CELL), bool)
    right[:, :-1] = dark[:, 1:]
    L += np.where(left & ~dark, 12, 0) - np.where(right & ~dark, 9, 0)
    r = Rand(base_seed * 31 + variant * 977 + 5)
    lefts = (0,) + tuple(cols)
    rights = tuple(cols) + (CELL,)
    for k in range(len(lefts)):
        x_l, x_r = lefts[k] + 1, rights[k] - 1
        if x_r - x_l < 2:
            continue
        for _j in range(1 if earth else r.int(1, 2)):
            y0 = r.int(EDGE, CELL - EDGE - (x_r - x_l) - 2)
            for x in range(x_l, x_r + 1):
                y = y0 + (x - x_l)
                if EDGE <= y < CELL - EDGE and not dark[y, x]:
                    dark[y, x] = True
                    if y + 1 < CELL - EDGE:
                        L[y + 1, x] += 10
                    if y - 1 >= EDGE:
                        L[y - 1, x] -= 8
        d = r.int(-9, 9)
        win = (u > lefts[k]) & (u < rights[k]) & (v >= EDGE + 2) & (v < CELL - EDGE - 2)
        L += np.where(win, d, 0)
    for _h in range(2 if not earth else 4):
        y, x = r.int(EDGE + 1, CELL - EDGE - 3), r.int(2, CELL - 4)
        if not dark[y, x] and not dark[y + 1, x]:
            L[y, x] += 26
            L[y + 1, x] += 16
    if earth:
        for _p in range(4):
            y, x = r.int(EDGE + 1, CELL - EDGE - 3), r.int(2, CELL - 4)
            for yy, xx in ((y, x), (y + 1, x), (y, x + 1)):
                if not dark[yy, xx]:
                    L[yy, xx] -= 22
    L = np.where(dark, 26, L)
    return L


def face(pal, piece):
    """RGBA of a face piece"""
    u = np.arange(CELL)[None, :].repeat(CELL, 0)
    v = np.arange(CELL)[:, None].repeat(CELL, 1)
    full = np.ones((CELL, CELL), bool)
    if piece in ('face_s_a', 'face_s_b'):
        return paint(south_face(pal, piece[-1] == 'b'), full, pal)
    if piece in ('face_e_a', 'face_e_b'):
        return paint(east_face(pal, piece[-1] == 'b'), full, pal)
    S = south_face(pal, 0)
    E = east_face(pal, 0)
    if piece == 'outer_se':
        L = np.where(u <= v, S, E)
        ridge = u == v
        L = np.where(ridge, np.maximum(S, E) + 36, L)
        L = np.where(u == v + 1, L - 12, L)          # the east side of the ridge turns away from the light
        return paint(L, full, pal)
    if piece in ('inner_se_a', 'inner_se_b'):
        S = south_face(pal, piece[-1] == 'b')
        E = east_face(pal, piece[-1] == 'b')
        L = np.where(u >= v, S, E)
        L = np.where(u == v, 28, L)                  # the crease
        L = np.where(u == v + 1, L - 14, L)          # the south face darkens into the corner
        return paint(L, full, pal)
    if piece == 'outer_sw':                         # the end of a south face spilling onto the tile west of it
        mask = u >= v
        L = np.where(u == v + 1, S + 18, S)          # the end edge catches the light
        return paint(L, mask, pal, dark=(u == v))
    if piece == 'outer_ne':                         # the top end of an east face spilling onto the tile north of it
        mask = v >= u
        L = np.where(v == u + 1, E + 14, E)
        return paint(L, mask, pal, dark=(v == u))
    raise KeyError(piece)


# ------------------------------------------------------------------------------------------------------------- the lip
LIP_W = 8       # about how far the rock edge reaches into the lower tile


def lip_profiles(pal):
    """the four sides' reach into the tile, periodic, shared by every piece (the pieces join along a side)"""
    s = PALETTES[pal]['seed'] + 900
    return {side: LIP_W + wobble(s + k, 2, passes=6) for k, side in enumerate('nesw')}


def lip_mask(pal, piece):
    u = np.arange(CELL)[None, :].repeat(CELL, 0)
    v = np.arange(CELL)[:, None].repeat(CELL, 1)
    P = lip_profiles(pal)
    band = {'n': v < P['n'][u], 's': v > CELL - 1 - P['s'][u], 'w': u < P['w'][v], 'e': u > CELL - 1 - P['e'][v]}
    # a corner alone: the block where the two bands of its sides cross, its inner corner rounded off
    def block(a, b, ua, vb):
        # the block grows up to two pixels past the sides inside the tile (a rock corner, not a chip); on the tile border it
        # has the reach of the side it continues (the side piece of the neighbouring tile ends there)
        ra = P[a][u] - 1 - vb + np.minimum(2, ua // 2)        # pixels left to the inner edge along each axis
        rb = P[b][v] - 1 - ua + np.minimum(2, vb // 2)
        return (ra >= 0) & (rb >= 0) & ~((ra < 3) & (rb < 3) & ((3 - ra) + (3 - rb) > 3))
    corner = {'cnw': block('n', 'w', u, v), 'cne': block('n', 'e', CELL - 1 - u, v),
              'csw': block('s', 'w', u, CELL - 1 - v), 'cse': block('s', 'e', CELL - 1 - u, CELL - 1 - v)}
    if piece in band:
        m = band[piece]
    elif piece in corner:
        m = corner[piece]
    else:
        a, b = piece[1], piece[2]
        m = band[a] | band[b]
        # the inside of the bend rounded: a fillet of three pixels
        ia = {'n': v - P['n'][u], 's': (CELL - 1 - P['s'][u]) - v, 'w': u - P['w'][v], 'e': (CELL - 1 - P['e'][v]) - u}
        m |= (ia[a] >= 0) & (ia[b] >= 0) & (ia[a] + ia[b] < 3)
    return clean(m)


def clean(m):
    """no lone pixel, no pinhole, no one pixel spur: the mask is smoothed until it holds"""
    m = m.copy()
    for _ in range(4):
        p = np.pad(m, 1, mode='edge')
        n4 = p[:-2, 1:-1].astype(int) + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
        m = np.where(m & (n4 <= 1), False, m)
        m = np.where(~m & (n4 >= 3), True, m)
    return m


def lip(pal, piece):
    m = lip_mask(pal, piece)
    u = np.arange(CELL)[None, :].repeat(CELL, 0)
    v = np.arange(CELL)[:, None].repeat(CELL, 1)
    earth = pal == 'earth'
    # the top of the rock: lighter at its free edge (it catches the light), a shade darker where it runs into the rim
    P = lip_profiles(pal)
    depth = np.minimum.reduce([np.where(v < P['n'][u], P['n'][u] - v, 99), np.where(v > CELL - 1 - P['s'][u], v - (CELL - 1 - P['s'][u]), 99),
                               np.where(u < P['w'][v], P['w'][v] - u, 99), np.where(u > CELL - 1 - P['e'][v], u - (CELL - 1 - P['e'][v]), 99)])
    depth = np.where(depth == 99, 0, depth)
    L = 134 - 9 * np.minimum(depth, 9) + grain(PALETTES[pal]['seed'] + 1300) * 2
    L += (CELL - (u + v) // 2) // 2 - 8                          # the light falls from the top left
    p = np.pad(m, 1, mode='edge')
    edge = m & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
    # the inner side of the free edge: lit where the edge faces up or left, shaded where it faces down or right
    up = m & ~p[:-2, 1:-1]
    down = m & ~p[2:, 1:-1]
    left = m & ~p[1:-1, :-2]
    right = m & ~p[1:-1, 2:]
    inner = m & ~edge
    q = np.pad(edge, 1)
    near = inner & (q[:-2, 1:-1] | q[2:, 1:-1] | q[1:-1, :-2] | q[1:-1, 2:])
    nq = np.pad(up | left, 1)
    lit = near & (nq[2:, 1:-1] | nq[1:-1, 2:])                 # the pixel below an up edge, right of a left edge
    sq = np.pad(down | right, 1)
    shaded = near & (sq[:-2, 1:-1] | sq[1:-1, :-2])
    L = np.where(lit, L + 22, L)
    L = np.where(shaded, L - 22, L)
    # cracks: short dark runs inside the stone, away from the edge
    r = Rand(PALETTES[pal]['seed'] * 13 + LIP.index(piece) + 1)
    crack = np.zeros((CELL, CELL), bool)
    ok_in = inner & ~near
    cands = list(zip(*np.nonzero(ok_in)))
    for _c in range(2 if not earth else 3):
        if not cands:
            break
        y, x = cands[r.int(0, len(cands) - 1)]
        dx, dy = (1, 1) if r.int(0, 1) else (1, 0)
        for _s in range(3):
            if 0 <= y < CELL and 0 <= x < CELL and ok_in[y, x]:
                crack[y, x] = True
            y, x = y + dy, x + dx
    L = np.where(crack, 40, L)
    # where the stone meets the tile edge it continues into the rim: no outline there
    dark = edge & ~((u == 0) | (u == CELL - 1) | (v == 0) | (v == CELL - 1))
    # an edge pixel on the tile border is still outline when the mask stops beside it (the free edge reaches the border)
    border = (u == 0) | (u == CELL - 1) | (v == 0) | (v == CELL - 1)
    free = edge & border & (
        ((u == 0) | (u == CELL - 1)) & (~p[:-2, 1:-1] | ~p[2:, 1:-1]) |
        ((v == 0) | (v == CELL - 1)) & (~p[1:-1, :-2] | ~p[1:-1, 2:]))
    dark = dark | free
    return paint(L, m, pal, dark=dark)


def draw(pal, piece):
    """RGBA 32 x 32 of a table piece name (face piece or lip_<name>)"""
    if piece.startswith('lip_'):
        return lip(pal, piece[4:])
    return face(pal, piece)


def draw_all():
    return {r['key']: draw(r['palette'], r['piece']) for r in pieces()}


# ------------------------------------------------------------------------------------------------------------- files
def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def spec_text(rows):
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(FIELDS)
    for r in rows:
        w.writerow([r[k] for k in FIELDS])
    return out.getvalue()


def sums_text(arts):
    return ''.join('%s  %s\n' % (digest(arts[r['key']]), r['key']) for r in pieces())


def things_text(rows, atlas_dir='cliff_art'):
    """import_art_things.py's things file of the pieces"""
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id', 'extra'])
    for r in rows:
        w.writerow([r['key'], 'item', r['kind'], r['name'], '%s/%s' % (atlas_dir, r['key']), 0, 0, 1, 1, 1, 1, r['flags'], 'new', '',
                    'family=cliff|palette=%s|piece=%s' % (r['palette'], r['piece'])])
    return out.getvalue()


# ------------------------------------------------------------------------------------------------------------- the bar
def opaque(a):
    return a[..., 3] > 0


def piece_problems(key, a, piece):
    """why a piece does not hold the rules ([] = fine)"""
    out = []
    if a.shape != (CELL, CELL, 4):
        return ['size %s' % (a.shape,)]
    al = a[..., 3]
    if set(np.unique(al).tolist()) - {0, 255}:
        out.append('alpha is not 0 / 255')
    if (a[al == 0][:, :3] != 0).any():
        out.append('colour under transparent pixels')
    vis = opaque(a)
    full = piece.startswith(('face_', 'inner_')) or piece == 'outer_se'
    if full and not vis.all():
        out.append('a face piece covers the whole tile')
    if not full and not (0 < vis.sum() < CELL * CELL):
        out.append('an end or lip piece leaves part of the tile free')
    ms = sc.measure(a)
    if ms['isolated'] or ms['specks'] or ms['holes']:
        out.append('lone pixels %d, specks %d, holes %d' % (ms['isolated'], ms['specks'], ms['holes']))
    return out


def seam_problems(arts):
    """the pieces join: the south face variants share their edge columns, the east face variants their edge rows, the corners
    continue the faces they meet, the lip pieces of a side meet along it"""
    out = []
    for pal in PALETTE_ORDER:
        A = {k[len(pal) + 1:]: v for k, v in arts.items() if k.startswith(pal + '_')}
        sa, sb = A['face_s_a'], A['face_s_b']
        if not (np.array_equal(sa[:, :2], sb[:, :2]) and np.array_equal(sa[:, -2:], sb[:, -2:])):
            out.append('%s: the south face variants differ at the tile edge' % pal)
        ea, eb = A['face_e_a'], A['face_e_b']
        if not (np.array_equal(ea[:2], eb[:2]) and np.array_equal(ea[-2:], eb[-2:])):
            out.append('%s: the east face variants differ at the tile edge' % pal)
        o = A['outer_se']
        if not np.array_equal(o[1:, 0], sa[1:, 0]):
            out.append('%s: outer_se does not continue the south face west of it' % pal)
        if not np.array_equal(o[0, 2:], ea[0, 2:]):
            out.append('%s: outer_se does not continue the east face north of it' % pal)
        n, s, w, e = A['lip_n'], A['lip_s'], A['lip_w'], A['lip_e']
        if abs(int(opaque(n)[:, 0].sum()) - int(opaque(n)[:, -1].sum())) > 1 or \
                abs(int(opaque(w)[0].sum()) - int(opaque(w)[-1].sum())) > 1:
            out.append('%s: a lip side does not repeat along itself (its reach steps more than a pixel at the seam)' % pal)
        if not np.array_equal(opaque(A['lip_dnw'])[:, -1], opaque(A['lip_n'])[:, -1]) or \
                not np.array_equal(opaque(A['lip_dnw'])[-1], opaque(A['lip_w'])[-1]):
            out.append('%s: the north-west bend does not meet the north and west sides' % pal)
        c = opaque(A['lip_cnw'])
        if abs(int(c[0].sum()) - int(opaque(A['lip_w'])[-1].sum())) > 1 or abs(int(c[:, 0].sum()) - int(opaque(n)[:, -1].sum())) > 1:
            out.append('%s: the north-west corner does not meet the west side above it and the north side west of it' % pal)
        if not (opaque(s)[-1].all() and opaque(e)[:, -1].all()):
            out.append('%s: the south / east lip does not reach its rim' % pal)
    return out


def style_problems(key, a, piece, pal):
    """style_check of a piece against its theme; a full tile (a face) has no silhouette, so its outline rule is not judged"""
    data = sc.load_palettes()
    t = data['themes'][PALETTES[pal]['theme']]
    pal_rgb = np.array([sc.unhex(x) for x in t['palette']], np.uint8)
    bad, _warn = sc.judge(sc.measure(a), pal_rgb, t['light'], data['thresholds'])
    if opaque(a).all():
        bad = [b for b in bad if not b.startswith('outline:')]
    return bad


def check(quiet=False):
    say = (lambda *a: None) if quiet else print
    rows = pieces()
    errs = table_errors(rows)
    have = list(csv.DictReader(open(SPEC, encoding='utf-8'))) if os.path.exists(SPEC) else []
    if [[str(r[k]) for k in FIELDS] for r in rows] != [[r[k] for k in FIELDS] for r in have]:
        errs.append('art_import/cliff_art.csv is not the table of the script (run gen_cliff_art.py table --write)')
    arts = draw_all()
    again = draw_all()
    if any(not np.array_equal(arts[k], again[k]) for k in arts):
        errs.append('two draws differ')
    for r in rows:
        a = arts[r['key']]
        errs += ['%s: %s' % (r['key'], e) for e in piece_problems(r['key'], a, r['piece'])]
        errs += ['%s: style: %s' % (r['key'], e) for e in style_problems(r['key'], a, r['piece'], r['palette'])]
    errs += seam_problems(arts)
    if (open(SUMS, encoding='utf-8').read() if os.path.exists(SUMS) else '') != sums_text(arts):
        errs.append('art_import/cliff_art.sums is stale (run gen_cliff_art.py table --write)')
    if len({digest(a) for a in arts.values()}) != len(arts):
        errs.append('two pieces are the same picture')
    for e in errs:
        print('FAIL', e)
    say('cliff art: %d pieces, %s' % (len(rows), 'OK' if not errs else '%d problems' % len(errs)))
    return 1 if errs else 0


def cmd_table(write):
    rows = pieces()
    arts = draw_all()
    if write:
        open(SPEC, 'w', encoding='utf-8', newline='').write(spec_text(rows))
        open(SUMS, 'w', encoding='utf-8', newline='').write(sums_text(arts))
        print('wrote', os.path.relpath(SPEC, ROOT), 'and', os.path.relpath(SUMS, ROOT))
    else:
        sys.stdout.write(spec_text(rows))
    return 0


# ------------------------------------------------------------------------------------------------------------- previews
def sheet(arts, scale=1):
    keys = [r['key'] for r in pieces()]
    per = len(FACE) + len(LIP)
    S = CELL + 4
    img = np.zeros((S * len(PALETTE_ORDER), S * per, 4), np.uint8)
    img[..., :3] = (70, 100, 60)
    img[..., 3] = 255
    for i, k in enumerate(keys):
        y, x = (i // per) * S + 2, (i % per) * S + 2
        a = arts[k]
        m = a[..., 3] > 0
        img[y:y + CELL, x:x + CELL][m] = a[m]
    if scale > 1:
        img = img.repeat(scale, 0).repeat(scale, 1)
    return img


def cmd_sheets(out):
    os.makedirs(out, exist_ok=True)
    arts = draw_all()
    for s in (1, 4):
        Image.fromarray(sheet(arts, s), 'RGBA').save(os.path.join(out, 'cliff_sheet_%dx.png' % s))
    print('sheets in', out)
    return 0


def sample_plateau(seed=5):
    """a footprint of the planner's shape rule and a south ramp notch: {(x, y)} and the notch"""
    sys.path.insert(0, os.path.join(ROOT, 'server', 'tools'))
    import random
    import area_plan_plateau as PL
    G = PL.shape(random.Random(seed), 12, 10)
    spots = PL.ramp_spots(G)
    notch = PL.notch(spots[len(spots) // 2]) if spots else set()
    return G, notch, PL


def scene(pal='stone', seed=5):
    """RGBA of a small map: the floor below with the cliff faces, then the top one floor up (32 px up and left) with its lip"""
    arts = {r['piece']: draw(pal, r['piece']) for r in pieces() if r['palette'] == pal}
    G, notch, PL = sample_plateau(seed)
    F = set(G) - notch
    faces, ends = PL.cliff_face_pieces(F, blocked=notch)
    W, H = 20, 16
    ox, oy = 4, 3
    img = np.zeros((H * CELL, W * CELL, 3), np.int64)
    gr = grain(99) // 2
    ground = np.zeros((CELL, CELL, 3), np.int64)
    ground[...] = (58, 84, 44)
    ground += gr[..., None]
    rock = np.zeros((CELL, CELL, 3), np.int64)
    rock[...] = (88, 86, 80) if pal == 'stone' else (104, 76, 60)
    rock += gr[..., None]

    def put(tx, ty, a, dz=0):
        x0, y0 = (tx + ox) * CELL - dz * CELL, (ty + oy) * CELL - dz * CELL
        if a.shape[-1] == 3:
            img[y0:y0 + CELL, x0:x0 + CELL] = a
            return
        m = a[..., 3] > 0
        img[y0:y0 + CELL, x0:x0 + CELL][m] = a[..., :3][m]
    xs = [x for x, _y in G]
    ys = [y for _x, y in G]
    for ty in range(min(ys) - 2, max(ys) + 3):
        for tx in range(min(xs) - 2, max(xs) + 3):
            put(tx, ty, ground)
    for (tx, ty), ps in sorted(ends.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        for p in ps:
            put(tx, ty, arts[p])
    for (tx, ty), p in sorted(faces.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        put(tx, ty, arts[p])
    rim = PL.rim(G) - notch
    for tx, ty in sorted(G, key=lambda t: (t[1], t[0])):
        put(tx, ty, rock if (tx, ty) in rim else ground, dz=1)
    for tx, ty in sorted(G, key=lambda t: (t[1], t[0])):
        if (tx, ty) in rim:
            continue
        near = {(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (tx + dx, ty + dy) in rim}
        import map_tile_rules as MR
        for nm in MR.border_pieces((0, -1) in near, (1, 0) in near, (0, 1) in near, (-1, 0) in near, (1, -1) in near,
                                   (-1, -1) in near, (1, 1) in near, (-1, 1) in near):
            put(tx, ty, arts['lip_' + nm], dz=1)
    return np.clip(img, 0, 255).astype(np.uint8)


def cmd_preview(out):
    os.makedirs(out, exist_ok=True)
    made = []
    for pal in PALETTE_ORDER:
        img = scene(pal)
        p = os.path.join(out, 'cliff_plateau_%s.png' % pal)
        Image.fromarray(img, 'RGB').save(p)
        made.append(p)
    a, b = [np.array(Image.open(p)) for p in made]
    tmp = tempfile.mkdtemp(prefix='cliff_frames_', dir=out)
    try:
        H, W = 270, 480
        k = 0
        for img in (a, b):
            big = img.repeat(2, 0).repeat(2, 1)
            for step in range(60):
                x = (big.shape[1] - W) * step // 59
                y = (big.shape[0] - H) * step // 59
                Image.fromarray(np.ascontiguousarray(big[y:y + H, x:x + W]), 'RGB').save(os.path.join(tmp, 'f%04d.png' % k))
                k += 1
        mp4 = os.path.join(out, 'cliff_plateau.mp4')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '20', '-i', os.path.join(tmp, 'f%04d.png'),
                        '-pix_fmt', 'yuv420p', '-vf', 'scale=960:540:flags=neighbor', mp4], check=True)
        made.append(mp4)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for p in made:
        print('wrote', p)
    return 0


def cmd_quality(out):
    """sprite_quality.py check --kind item of every piece: which rows of the O625 item bar the pieces miss"""
    import sprite_quality as sq
    os.makedirs(out, exist_ok=True)
    bar = sq.load_bar() if hasattr(sq, 'load_bar') else None
    arts = draw_all()
    misses = {}
    for r in pieces():
        p = os.path.join(out, r['key'] + '.png')
        Image.fromarray(arts[r['key']], 'RGBA').save(p)
        res = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'sprite_quality.py'), 'check', '--kind', 'item', p],
                             capture_output=True, text=True)
        for line in res.stdout.splitlines()[1:]:
            words = line.split()
            if line.startswith('  ') and len(words) >= 2 and words[0] in ('FAIL', 'warn'):
                misses.setdefault((words[0], words[1]), []).append(r['key'])
    del bar
    for (level, name), keys in sorted(misses.items()):
        print('%-4s %-22s missed by %d of %d pieces' % (level, name, len(keys), len(pieces())))
    if not misses:
        print('every piece meets the item bar')
    return 0


# ------------------------------------------------------------------------------------------------------------- pair
def md5_of(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def build(dat, spr, out_dir, want_md5=PAIR82_DAT_MD5, first=FIRST, expect=EXPECT_ITEMS):
    """pair 82 + the 42 pieces appended as new items (import_art_things.py); every other byte stays"""
    import import_art_things as iat
    if os.path.abspath(os.path.dirname(dat)) == os.path.abspath(out_dir):
        sys.exit('out-dir must differ from the input dir')
    have = md5_of(dat)
    if have != want_md5:
        sys.exit('refused: the input dat has md5 %s, this step takes pair 82 only (%s)' % (have, want_md5))
    if check(quiet=True):
        sys.exit('refused: `check` fails (the table or the sums are not current)')
    rows = pieces()
    arts = draw_all()
    work = tempfile.mkdtemp(prefix='cliff_art_', dir=os.path.dirname(os.path.abspath(out_dir)) or '.')
    try:
        os.makedirs(os.path.join(work, 'cliff_art'))
        for r in rows:
            Image.fromarray(arts[r['key']], 'RGBA').save(os.path.join(work, 'cliff_art', r['key'] + '.png'))
        things = os.path.join(work, 'things.csv')
        open(things, 'w', newline='').write(things_text(rows))
        argv = ['import_art_things.py', '--ours-dat', dat, '--ours-spr', spr, '--out-dir', out_dir, '--things', things,
                '--first-item', str(first), '--expect-items', str(expect), '--server-offset', str(SERVER_OFFSET)]
        old_argv = sys.argv
        sys.argv = argv
        try:
            iat.main()
        finally:
            sys.argv = old_argv
            iat._atlas.clear()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    bad = live(os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr'), first)
    for b in bad:
        print('FAIL', b)
    print('cliff art: %d items %d..%d appended%s' % (len(rows), first, first + len(rows) - 1, '' if not bad else '; live check FAILS'))
    return 1 if bad else 0


def live(dat, spr, first=FIRST):
    """the pair holds every piece at its id: 1 x 1, one phase, the pixels of the drawing; [] problems = fine"""
    import import_art_things as iat
    import import_donor_things as idt
    from datspr import Dat, Spr
    d, s = Dat(dat), Spr(spr)
    ours = idt.parse_dat(d.data, idt.OUR_KINDS)
    items = {t.id: t for t in ours['item']}
    arts = draw_all()
    bad = []
    for k, r in enumerate(pieces()):
        cid = first + k
        t = items.get(cid)
        if t is None:
            bad.append('%s: item %d is not in the pair' % (r['key'], cid))
            continue
        g = t.groups[0]
        if (len(t.groups), g['w'], g['h'], g['layers'], g['px'], g['py'], g['phases']) != (1, 1, 1, 1, 1, 1, 1):
            bad.append('%s: item %d is not one 1 x 1 picture' % (r['key'], cid))
            continue
        sid = g['sprites'][0]
        px = s.sprite(sid) if sid else None
        want = iat.decoded(arts[r['key']])
        if px is None or not bool((px == want).all()):
            bad.append('%s: item %d differs from the drawing' % (r['key'], cid))
    return bad


def main(argv=None):
    a = list(sys.argv[1:] if argv is None else argv)
    if not a:
        print(__doc__)
        return 1
    cmd = a[0]
    if cmd == 'check' and len(a) == 1:
        return check()
    if cmd == 'table':
        return cmd_table('--write' in a)
    if cmd == 'sheets' and len(a) == 2:
        return cmd_sheets(a[1])
    if cmd == 'preview' and len(a) == 2:
        return cmd_preview(a[1])
    if cmd == 'quality' and len(a) == 2:
        return cmd_quality(a[1])
    if cmd == 'build' and len(a) == 4:
        return build(a[1], a[2], a[3])
    if cmd == 'live' and len(a) == 3:
        bad = live(a[1], a[2])
        for b in bad:
            print('FAIL', b)
        print('cliff art live: %d pieces, %s' % (len(pieces()), 'OK' if not bad else '%d problems' % len(bad)))
        return 1 if bad else 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main())
