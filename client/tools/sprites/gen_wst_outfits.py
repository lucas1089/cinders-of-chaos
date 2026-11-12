#!/usr/bin/env python3
"""Purchased creature packs as polished creature outfits (O540; client/MANIFEST.md "Pair 71").

    python3 -I gen_wst_outfits.py check                         # the table against its own rules (no pair, no pack files)
    python3 -I gen_wst_outfits.py looks [--check]               # server/data/monster/monster_wst_looks.csv from the `purchased` rows of monster_looks/picks.csv
    python3 -I gen_wst_outfits.py ids                           # print src id, name-free kind and measures of every creature under --src (author's aid)
    python3 -I gen_wst_outfits.py select --src DIR [--pair DAT SPR] [--write]
                                                                # apply the pick rule to the pack files, print (or write) the table
    python3 -I gen_wst_outfits.py sums --src DIR [--check]      # write (or compare) art_import/purchased_outfits.sums from the pack files
    python3 -I gen_wst_outfits.py build DAT SPR OUT_DIR --src DIR
                                                                # pair 70 in, pair 71 out (OUT_DIR must not exist; written beside, then renamed)
    python3 -I gen_wst_outfits.py live DAT SPR                  # the pair holds every outfit at its id, as the sums say (CI job "Live sprite pair")

The owner decided (2026-11-12, translated: "Use the purchased creature packs. Import the 77 into pair 71, stored in the repository only in
encrypted form, like the other purchased packs") and confirmed that the licence allows in-game use. CI does not need the art, so none is committed,
not even encrypted: committed are this tool, the table art_import/purchased_outfits.csv and art_import/purchased_outfits.sums (a digest of every
outfit's pictures, to check a built pair and the pack files against). The pack files are read locally by this script only (never sent
to a web or AI service, never a style reference, never training data; docs/CREDITS.md has the licence terms).

Source. `--src DIR` holds the unpacked packs, in any folder layout. A creature is found by its files, not by a name: a folder with
an `animations.json` and `sheets/*_sheet.png` (grey base on the left 4 columns, colour marker mask on the right 4, 11 pose rows:
idle1-2, walk1-4, attack, death; 4 directions up / right / down / left; cell 64 px for a small creature, 128 px for a large one), or
a set of strips `<key>_{idle,walk}_{n,e,s,w}_strip.png` (4 frames of one canvas each, full colour). A creature is named in the table by
`src`: the first 12 hex digits of the sha256 of its south idle picture file, so no name of the pack is in the repository.

Colour (monster packs). The default tint scheme (the first of `schemes`): where the mask holds a marker colour (yellow head, red
body, green legs, blue feet) the pixel is the base grey times the scheme colour / 255; every other pixel keeps its colour. Alpha stays
as drawn (binary in the monster packs, soft in a few strips of the harvest kit).

Pick rule (`select`), all of it measured on the pack files:
  * polished: 500 or more colours (every opaque RGB over the idle and walk frames facing south at the source scale, default tint);
  * 4 directions, 2 or more idle pictures that differ, 4 walk frames, a canvas of 64 or 128 px (the 160 px canvas of the boss strip set is a 3x3 creature);
  * a creature (KINDS: the kind of each, from the pack's own text);
  * not identical (every group, direction, phase, sprite pixel) to an outfit of the input pair, and not identical to a pick of lower id.

Scale (decided by measurement, client/MANIFEST.md "Pair 71"). A 64 px cell is 2x2 tiles at 32 px per tile: the small creatures draw a
figure of 26 to 44 px (median 34) like our 1x1 hunt monsters (31 px), so a small creature keeps its pixels (scale 1). A 128 px cell
holds a figure of 71 to 117 px (median 82), bigger than every 2x2 outfit of ours (median 51) and than 3x3 (66): at 1:1 it would
need 3x3 or 4x4 outfits, and a monster that is no boss stays 2x2 at most, and cropping to 64 px loses 2 to 30 % of the pixels. So a
large creature is halved with nearest neighbour (every second pixel, the one of the two offsets that keeps the most opaque pixels, no
other filter), which gives a figure of 35 to 63 px, the size of our 2x2 monsters (34 to 64).

Place. Every outfit is 2x2 (64 px). One shift for all frames: the lowest opaque pixel of any frame of the creature on row 63 (our
monsters stand on the bottom row of their outfit), the middle of the union box on column 47.5 (the middle of the creature's own
tile), moved left when the box would pass column 63. Every frame must lie inside the 64 px canvas (build checks).

Pair 71 (`build`) appends the picks as new outfits after the 3,433 outfits of pair 70, one per row, in table order: the row at
line n (0-based) becomes outfit 3434 + n. An outfit has an idle group (gtype 0, 2 or 4 phases, 333 ms or 220 ms a frame) and a walk
group (gtype 1, 4 phases, 125 ms or 140 ms), 2x2, one layer, 4 directions, no flags. Sprites are cut in tiles; an empty tile is
slot 0; a picture that is already a record of the input pair takes that sprite id, a new one is appended once. Nothing but
outfits and sprite records is appended (check_pair.py --old pair 70: 0 errors).
Needs numpy and Pillow (the fx venv of CI) for build, select, sums, ids and live; `check` needs neither.
"""
import csv
import hashlib
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'purchased_outfits.csv')
SUMS = os.path.join(ART, 'purchased_outfits.sums')
HEADER = ['src', 'new', 'kind', 'size', 'scale', 'idle', 'walk', 'colours', 'outcolours']
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
PICKS = os.path.join(HERE, 'monster_looks', 'picks.csv')
POOL = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'bounty_pool.lua')
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_wst_looks.csv')
MAP_HEADER = ['monster', 'look', 'new_look']
PAIR = 71
MIN_PAIR = 70
OUTFITS_70 = 3433
FIRST_NEW = OUTFITS_70 + 1
DAT_70_MD5 = '11439d6c5b87968cc0a3d5aef3e42e6a'
MIN_COLOURS = 500
MIN_WALK = 4
MIN_IDLE = 2
MAX_TILES = 2
MAX_ON_LOOK = 2      # owner rule of O533: at most 2 hunt monsters wear one look
CANVAS = 64          # every outfit is 2x2 tiles
FOOT_ROW = 63
MID_COL = 47.5
IDLE_MS = {'pack': 333, 'strip': 220}
WALK_MS = {'pack': 125, 'strip': 140}
KIND_NAMES = ('angel/spirit', 'beast', 'bird/bat', 'demon', 'dragon/drake', 'golem/construct', 'humanoid', 'plant', 'reptile',
              'spider/insect', 'troll/ogre/orc', 'undead', 'worm')
MARKERS = {'head': (255, 255, 0), 'body': (255, 0, 0), 'legs': (0, 255, 0), 'feet': (0, 0, 255)}
DIRS_STRIP = ('n', 'e', 's', 'w')     # engine order north, east, south, west = the pack's up, right, down, left
SOUTH = 2
# creatures that pass the rule and are not imported: src id -> reason
EXCLUDED = {
    'd5121e645e2a': 'a black cat: 376 colours in its walk strip (815 with the idle frames), not one of the owner\'s 77 (O537 survey: not polished)',
}

# the kind of every creature of the packs by src id (read from the pack's own descriptions: what the creature is, not what it is called)
KINDS = {
    '03d39ebfce5d': 'beast', '04a96635cef4': 'spider/insect', '05b0bcf0c115': 'undead',
    '08727c7bcc2b': 'plant', '09619d3d932e': 'beast', '0dca38b7bc8d': 'undead',
    '144132f49d3a': 'troll/ogre/orc', '147ffe8fc7f3': 'troll/ogre/orc', '14ff13e62fce': 'plant',
    '150408513d75': 'undead', '150b0becd93e': 'golem/construct', '15cdd423a116': 'undead',
    '16df1c10bb19': 'humanoid', '19509c0f8244': 'golem/construct', '1c040a5e6769': 'beast',
    '1f93ebe6554e': 'plant', '2b17362e759e': 'beast', '2bea9880363a': 'spider/insect',
    '35b801958738': 'undead', '3c711f243cf3': 'worm', '4051c22ff237': 'bird/bat',
    '41582e6f4a18': 'bird/bat', '426c3010dde7': 'troll/ogre/orc', '430c083b2b28': 'troll/ogre/orc',
    '48a1aee830d0': 'beast', '49692be29396': 'beast', '49bcb4aef37f': 'troll/ogre/orc',
    '4a6a789044a6': 'humanoid', '4be5b43481d2': 'undead', '4dc15258b539': 'dragon/drake',
    '4e6f3a075dec': 'beast', '4e8ee0f2e403': 'troll/ogre/orc', '4fed6937e722': 'beast',
    '539754efa42f': 'spider/insect', '54eb4ebbd0b3': 'worm', '56292cb39f00': 'dragon/drake',
    '56ed1222b626': 'troll/ogre/orc', '5a2fd8321a4c': 'golem/construct', '5f1a117bf9b3': 'troll/ogre/orc',
    '6097e18f43f0': 'troll/ogre/orc', '6112ac85fb18': 'spider/insect', '679ac7d60390': 'plant',
    '6e86387c2e04': 'troll/ogre/orc', '74bba39bd91e': 'bird/bat', '77da4db1ffee': 'humanoid',
    '78f87bd528df': 'undead', '7b0856d411ea': 'humanoid', '7ba5eb177c7b': 'undead',
    '7bd817a20f82': 'bird/bat', '7caf92a03b3a': 'troll/ogre/orc', '83964eced323': 'humanoid',
    '852067902048': 'angel/spirit', '866e9a179c70': 'undead', '8ae4394ba463': 'angel/spirit',
    '8b311992617c': 'spider/insect', '8bb26147aca0': 'undead', '95b135f0c25f': 'troll/ogre/orc',
    '96b8406402fc': 'golem/construct', '99360752f922': 'angel/spirit', '9b75b93d8b38': 'spider/insect',
    '9d5126ccf079': 'beast', 'a75cd9e8cfeb': 'undead', 'ac7e457d3f81': 'troll/ogre/orc',
    'af4a71e96378': 'troll/ogre/orc', 'bdc5880ee18e': 'humanoid', 'c64736e58806': 'worm',
    'cc8b9fd77a72': 'angel/spirit', 'd1ab2fdf4fac': 'golem/construct', 'd319be513e95': 'undead',
    'd4ce76093793': 'plant', 'd5121e645e2a': 'beast', 'd7949899a76b': 'golem/construct',
    'd7e7d8ccdf4a': 'humanoid', 'd8509f33f3a3': 'demon', 'db4286f1e890': 'reptile',
    'e244e845a685': 'troll/ogre/orc', 'e6b82dda8f61': 'plant', 'ebb66a4693a8': 'golem/construct',
    'ec057a9c08e9': 'angel/spirit', 'ef091d4d2d8d': 'golem/construct', 'f453842f4e37': 'beast',
    'fa81d9ace373': 'undead', 'fcbbd719c51f': 'demon', 'fec0425888f8': 'troll/ogre/orc',
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
    """What is wrong with the table: header, ids in a row from the first new outfit, a src once, kinds, sizes, colours and the sums rows."""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out, seen = [], set()
    for i, r in enumerate(t):
        d, n = r['src'], int(r['new'])
        if not re.fullmatch(r'[0-9a-f]{12}', d):
            out.append('row %d: src %s is not 12 hex digits' % (i, d))
        if n != first + i:
            out.append('src %s: new id %d, the row at line %d must be %d' % (d, n, i, first + i))
        if d in seen:
            out.append('src %s is on two rows' % d)
        seen.add(d)
        if r['kind'] not in KIND_NAMES:
            out.append('src %s: kind %s is not one of %s' % (d, r['kind'], ', '.join(KIND_NAMES)))
        if KINDS.get(d) != r['kind']:
            out.append('src %s: kind %s, KINDS says %s' % (d, r['kind'], KINDS.get(d)))
        if d in EXCLUDED:
            out.append('src %s is excluded (%s), no row' % (d, EXCLUDED[d]))
        try:
            w, h = (int(x) for x in r['size'].split('x'))
        except ValueError:
            out.append('src %s: size %s is not WxH' % (d, r['size']))
            continue
        if w > MAX_TILES or h > MAX_TILES:
            out.append('src %s: size %s is above %dx%d (a monster that is no boss stays 2x2 at most)' % (d, r['size'], MAX_TILES, MAX_TILES))
        if r['scale'] not in ('1', '1/2'):
            out.append('src %s: scale %s is not 1 or 1/2' % (d, r['scale']))
        if int(r['walk']) < MIN_WALK:
            out.append('src %s: %s walk frames, at least %d' % (d, r['walk'], MIN_WALK))
        if int(r['idle']) < MIN_IDLE:
            out.append('src %s: %s idle frames, at least %d' % (d, r['idle'], MIN_IDLE))
        if int(r['colours']) < MIN_COLOURS:
            out.append('src %s: %s colours, polished is %d or more' % (d, r['colours'], MIN_COLOURS))
        if int(r['outcolours']) < 1:
            out.append('src %s: no colours in the output' % d)
    if set(s) != seen:
        out.append('purchased_outfits.sums and the table name other outfits (%s)' % ', '.join(sorted(set(s) ^ seen)))
    return out


def write_table(picks, path=TABLE):
    """picks: [(src, kind, size 'WxH', scale, idle, walk, colours, outcolours)] -> the csv (new ids follow the order)"""
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(HEADER)
        for i, p in enumerate(picks):
            w.writerow([p[0], FIRST_NEW + i] + list(p[1:]))


# ---------------------------------------------------------------- the monsters

def picks_rows(path=PICKS):
    """[(monster, new look, lib id)] of the rows of family `purchased` of monster_looks/picks.csv, in file order (lib id = the outfit number
    in the table, new - 3433)"""
    with open(path, newline='', encoding='utf-8') as f:
        return [(r['monsters'], int(r['look']), int(r['lib_id'])) for r in csv.DictReader(f) if r['family'] == 'purchased']


def pool_looks(path=POOL):
    """{monster name: look} of the committed bounty pool (the look every monster wears below pair 70)"""
    text = open(path, encoding='utf-8').read()
    return {m.group(1).replace('\\"', '"'): int(m.group(2))
            for m in re.finditer(r'\{name = "((?:[^"\\]|\\.)*)",[^}]*?\blook = (\d+)', text)}


def map_rows(picks=None, pool=None):
    """[(monster, old look, new look)]: the purchased rows of picks.csv with the look the committed pool gives each monster today"""
    p = picks_rows() if picks is None else picks
    have = pool_looks() if pool is None else pool
    return [(m, have[m], new) for m, new, _d in p]


def map_text(rows_):
    return ','.join(MAP_HEADER) + '\n' + ''.join('%s,%d,%d\n' % r for r in rows_)


def map_problems(table=None, picks=None, pool=None):
    """The `purchased` rows of picks.csv against the outfit table and the pool: each look is a table outfit (and its lib id), used by at most
    MAX_ON_LOOK monsters, each monster once and in the pool."""
    t = rows() if table is None else table
    p = picks_rows() if picks is None else picks
    have = pool_looks() if pool is None else pool
    by = {int(r['new']): int(r['new']) - FIRST_NEW + 1 for r in t}
    out, seen, used = [], set(), {}
    for m, new, d in p:
        if by.get(new) != d:
            out.append('%s: look %d / lib id %d is not a row of purchased_outfits.csv' % (m, new, d))
        used[new] = used.get(new, 0) + 1
        if used[new] > MAX_ON_LOOK:
            out.append('look %d is on more than %d monsters (owner rule of O533)' % (new, MAX_ON_LOOK))
        if m in seen:
            out.append('%s is on two rows of picks.csv' % m)
        seen.add(m)
        if m not in have:
            out.append('%s is not in the bounty pool' % m)
    return out


def write_map(check=False):
    """write monster_wst_looks.csv (monster, look, new_look), or with check compare it; returns the problem lines"""
    text = map_text(map_rows())
    old = open(MAP, encoding='utf-8', newline='').read() if os.path.exists(MAP) else None
    if old == text:
        return []
    if check:
        return ['server/data/monster/monster_wst_looks.csv is not up to date (run gen_wst_outfits.py looks)']
    with open(MAP, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return []


# ---------------------------------------------------------------- the pack files

class Creature:
    """one creature of the pack files: id (12 hex of its south idle picture file), source kind ('pack' sheets or 'strip' sets),
    the canvas size, and `frames()`: {('idle' | 'walk', direction 0..3 n e s w): [RGBA uint8 arrays, one per phase]} at the source scale"""

    def __init__(self, cid, kind, cell, loader):
        self.id, self.kind, self.cell, self._load = cid, kind, cell, loader

    def frames(self):
        return self._load()


def _read_png(path):
    import numpy as np
    from PIL import Image
    return np.asarray(Image.open(path).convert('RGBA'))


def _sha12(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()[:12]


def tint_frames(meta, sheet):
    """the creature sheet (base | mask, rows = poses) at the default tint scheme -> {(pose, direction): array}"""
    import numpy as np
    cell, poses = int(meta['cell']), meta['poses']
    tint = meta['tints'][meta['schemes'][0]]
    out = {}
    for r, pose in enumerate(poses):
        for d in range(4):
            base = sheet[r * cell:(r + 1) * cell, d * cell:(d + 1) * cell].copy()
            mask = sheet[r * cell:(r + 1) * cell, (4 + d) * cell:(5 + d) * cell]
            res = base.astype(np.float64)
            for part, m in MARKERS.items():
                sel = (mask[..., 0] == m[0]) & (mask[..., 1] == m[1]) & (mask[..., 2] == m[2]) & (mask[..., 3] > 0)
                res[sel, :3] = base[sel, :3] * (np.array(tint[part], dtype=np.float64) / 255)
            res = np.clip(np.round(res), 0, 255).astype(np.uint8)
            res[res[..., 3] == 0] = 0
            out[(pose, d)] = res
    return out


def discover(src):
    """[Creature] of every creature under src (read only: json, png), sorted by id"""
    found = []
    for root, _dirs, files in os.walk(src):
        if 'animations.json' in files and os.path.isdir(os.path.join(root, 'sheets')):
            sheets = [f for f in os.listdir(os.path.join(root, 'sheets')) if f.endswith('_sheet.png')]
            if len(sheets) != 1:
                continue
            sheet_path = os.path.join(root, 'sheets', sheets[0])
            meta = json.load(open(os.path.join(root, 'animations.json'), encoding='utf-8'))
            if not all(k in meta for k in ('cell', 'poses', 'tints', 'schemes')):
                continue

            def load(meta=meta, sheet_path=sheet_path):
                fr = tint_frames(meta, _read_png(sheet_path))
                return {(g, d): [fr[(p, d)] for p in ps] for g, ps in (('idle', ('idle1', 'idle2')), ('walk', ('walk1', 'walk2', 'walk3', 'walk4')))
                        for d in range(4)}
            found.append(Creature(_sha12(sheet_path), 'pack', int(meta['cell']), load))
        for f in files:
            m = re.fullmatch(r'(.+)_idle_s_strip\.png', f)
            if not m:
                continue
            key = m.group(1)
            need = ['%s_%s_%s_strip.png' % (key, g, d) for g in ('idle', 'walk') for d in DIRS_STRIP]
            if not all(n in files for n in need):
                continue

            def load(root=root, key=key):
                import numpy as np
                out = {}
                for g in ('idle', 'walk'):
                    for d, letter in enumerate(DIRS_STRIP):
                        a = _read_png(os.path.join(root, '%s_%s_%s_strip.png' % (key, g, letter)))
                        n = a.shape[1] // a.shape[0]
                        out[(g, d)] = [np.ascontiguousarray(a[:, i * a.shape[0]:(i + 1) * a.shape[0]]) for i in range(n)]
                return out
            from PIL import Image
            with Image.open(os.path.join(root, f)) as im:
                cell = im.size[1]
            found.append(Creature(_sha12(os.path.join(root, f)), 'strip', cell, load))
    found.sort(key=lambda c: c.id)
    ids = [c.id for c in found]
    if len(set(ids)) != len(ids):
        raise SystemExit('two creatures with one src id under %s' % src)
    return found


# ---------------------------------------------------------------- measuring and drawing

def colours_south(fr, groups=('idle', 'walk')):
    """number of opaque RGB values over the idle and walk frames facing south"""
    import numpy as np
    cols = set()
    for g in groups:
        for a in fr[(g, SOUTH)]:
            v = a[..., 3] > 0
            if v.any():
                cols.update(map(tuple, np.unique(a[v][:, :3], axis=0)))
    return len(cols)


def half(a, ox, oy):
    """nearest neighbour 2:1: every second pixel, starting at (ox, oy)"""
    import numpy as np
    return np.ascontiguousarray(a[oy::2, ox::2])


def best_phase(fr):
    """the offset (ox, oy) of the 2:1 sampling that keeps the most opaque pixels over every frame (first of the four on a tie)"""
    best = None
    for oy in (0, 1):
        for ox in (0, 1):
            n = sum(int((half(a, ox, oy)[..., 3] > 0).sum()) for lst in fr.values() for a in lst)
            if best is None or n > best[0]:
                best = (n, ox, oy)
    return best[1], best[2]


def scaled(c, fr):
    """(frames at the output scale, scale text, sampling offset or None); raises ValueError for a canvas that is neither 64 nor 128 px"""
    if c.cell == CANVAS:
        return fr, '1', None
    if c.cell == 2 * CANVAS:
        ox, oy = best_phase(fr)
        return {k: [half(a, ox, oy) for a in lst] for k, lst in fr.items()}, '1/2', (ox, oy)
    raise ValueError('canvas %d px' % c.cell)


def place(fr):
    """shift every frame by one (dx, dy): lowest opaque pixel on FOOT_ROW, middle of the union box on MID_COL, left when the box would pass
    the last column. Returns {key: [64 x 64 RGBA arrays]}; raises ValueError when a frame does not fit."""
    import numpy as np
    x0 = y0 = 10 ** 6
    x1 = y1 = -1
    for lst in fr.values():
        for a in lst:
            ys, xs = np.nonzero(a[..., 3] > 0)
            if len(xs):
                x0, x1, y0, y1 = min(x0, int(xs.min())), max(x1, int(xs.max())), min(y0, int(ys.min())), max(y1, int(ys.max()))
    if x1 < 0:
        raise ValueError('no opaque pixel')
    dy = FOOT_ROW - y1
    dx = math.floor(MID_COL - (x0 + x1) / 2.0)
    dx = min(dx, CANVAS - 1 - x1)
    if x0 + dx < 0 or y0 + dy < 0 or x1 + dx > CANVAS - 1 or y1 + dy > CANVAS - 1:
        raise ValueError('the figure (%dx%d) does not fit the %d px canvas' % (x1 - x0 + 1, y1 - y0 + 1, CANVAS))
    out = {}
    for k, lst in fr.items():
        res = []
        for a in lst:
            c = np.zeros((CANVAS, CANVAS, 4), np.uint8)
            h, w = a.shape[:2]
            sy0, sx0 = max(0, -dy), max(0, -dx)
            ey, ex = min(h, CANVAS - dy), min(w, CANVAS - dx)
            c[sy0 + dy:ey + dy, sx0 + dx:ex + dx] = a[sy0:ey, sx0:ex]
            res.append(c)
        out[k] = res
    return out


def distinct(lst):
    return len({a.tobytes() for a in lst})


def measure(c):
    """facts of a creature: scale, idle / walk frames, directions, colours at the source scale, colours of the output, or the reason it cannot be one"""
    fr = c.frames()
    m = {'colours': colours_south(fr), 'idle': len(fr[('idle', SOUTH)]), 'walk': len(fr[('walk', SOUTH)]), 'dirs': 4,
         'idle_distinct': distinct(fr[('idle', SOUTH)]), 'tiles': 2 if c.cell <= 2 * CANVAS else 3, 'cell': c.cell}
    try:
        sc, text, _ph = scaled(c, fr)
        m['scale'] = text
        m['placed'] = place(sc)
        m['outcolours'] = colours_south(m['placed'])
        m['reason'] = ''
    except ValueError as e:
        m['reason'] = str(e)
    return m


def passes(m):
    return (not m['reason'] and m['colours'] >= MIN_COLOURS and m['dirs'] == 4 and m['walk'] >= MIN_WALK and m['idle_distinct'] >= MIN_IDLE
            and m['tiles'] <= MAX_TILES)


# ---------------------------------------------------------------- the outfit of a creature

def groups_of(c, placed):
    """[(Group, [64 x 64... tile arrays in slot order])] idle then walk: the dat shape and the sprite arrays of one outfit"""
    sys.path.insert(0, HERE)
    from import_outfits import Group
    from gen_effects import tiles_of
    out = []
    for gtype, key in ((0, 'idle'), (1, 'walk')):
        phases = len(placed[(key, 0)])
        g = Group()
        g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases = gtype, 2, 2, 64, 1, 4, 1, 1, phases
        ms = (IDLE_MS if key == 'idle' else WALK_MS)[c.kind]
        g.anim = (0, 0, 0, tuple([ms, ms] * phases)) if phases > 1 else None
        tiles = []
        for ph in range(phases):
            for d in range(4):
                t = tiles_of(placed[(key, d)][ph], 2, 2)
                for hh in range(2):
                    for ww in range(2):
                        tiles.append(t[(ww, hh)])
        g.sprites = tuple(range(len(tiles)))
        out.append((g, tiles))
    return out


def clean(a):
    """the tile as the spr gives it back: no colour under a transparent pixel"""
    import numpy as np
    return np.where(a[..., 3:4] > 0, a, 0).astype(np.uint8)


def spec_digest(specs):
    """sha256 over the whole outfit: group shapes and animator, then every sprite slot (empty slots alike) of every group"""
    h = hashlib.sha256()
    for g, tiles in specs:
        h.update(repr((g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim)).encode())
        for a in tiles:
            h.update(b'\0' if a is None or not a[:, :, 3].any() else clean(a).tobytes())
    return h.hexdigest()


def digest(dat, spr, look):
    """the same digest read from a pair: sha256 over the group shapes and every sprite slot of the outfit"""
    sys.path.insert(0, HERE)
    from import_outfits import parse_body
    specs = []
    for g in parse_body(dat, dat.outfit(look)):
        specs.append((g, [spr.sprite(sid) for sid in g.sprites]))
    return spec_digest(specs)


def select(src, pair=None, log=print):
    """[(src, kind, size, scale, idle, walk, colours, outcolours)] ordered by kind then src: the pick rule on the pack files. pair: (dat, spr)
    of the input pair, a pick identical to one of its outfits is dropped; a pick identical to an earlier pick is dropped too."""
    sys.path.insert(0, HERE)
    ours = None
    if pair:
        from datspr import Dat, Spr
        od, osp = Dat(pair[0]), Spr(pair[1])
        ours = {}
        for o in od.outfits:
            t = od.outfit(o.id)
            g = t.groups[-1] if t.groups else None
            if g and g[0] <= MAX_TILES and g[1] <= MAX_TILES:
                try:
                    ours[digest(od, osp, o.id)] = o.id
                except Exception:   # a blank or odd stock outfit cannot equal a pick
                    pass
    picks, seen = [], {}
    found = discover(src)
    ids = {c.id for c in found}
    for k in sorted(set(KINDS) - ids):
        log('note: KINDS names %s, which is not under %s' % (k, src))
    for c in found:
        if c.id not in KINDS:
            raise SystemExit('creature %s has no kind in KINDS' % c.id)
        if c.id in EXCLUDED:
            log('drop %s: %s' % (c.id, EXCLUDED[c.id]))
            continue
        m = measure(c)
        if not passes(m):
            log('drop %s: %s' % (c.id, {k: v for k, v in m.items() if k != 'placed'}))
            continue
        h = spec_digest(groups_of(c, m['placed']))
        if ours is not None and h in ours:
            log('drop %s: identical to outfit %d of the pair' % (c.id, ours[h]))
            continue
        if h in seen:
            log('drop %s: identical to the pick %s' % (c.id, seen[h]))
            continue
        seen[h] = c.id
        picks.append((c.id, KINDS[c.id], '2x2', m['scale'], m['idle'], m['walk'], m['colours'], m['outcolours']))
    picks.sort(key=lambda p: (p[1], p[0]))
    return picks


def pack_sums(src, ids):
    """{src id: digest of the outfit built from the pack files}"""
    by = {c.id: c for c in discover(src)}
    out = {}
    for i in ids:
        if i not in by:
            raise SystemExit('no creature %s under %s' % (i, src))
        m = measure(by[i])
        if m['reason']:
            raise SystemExit('creature %s: %s' % (i, m['reason']))
        out[i] = spec_digest(groups_of(by[i], m['placed']))
    return out


def sums_text(sums):
    return ('# sha256 of each outfit (shapes, animator, every sprite slot), written by gen_wst_outfits.py sums (O540)\n'
            + ''.join('%s %s\n' % (k, sums[k]) for k in sorted(sums)))


# ---------------------------------------------------------------- the pair

def record_index(spr):
    """{md5 of a record: sprite id} of every record of a spr (the first id of equal records)"""
    import struct
    m, idx = spr.m, {}
    for sid in range(1, spr.count + 1):
        o = int(spr.offs[sid - 1])
        if o:
            ln = struct.unpack_from('<H', m, o + 3)[0]
            idx.setdefault(hashlib.md5(m[o:o + 5 + ln]).digest(), sid)
    return idx


def build(dat, spr, out_dir, src, table=None, first=FIRST_NEW, expect_md5=None, log=print):
    """pair in (DAT, SPR; its outfits end at first - 1) -> pair out in OUT_DIR (not there yet): every row of the table is one new
    outfit, built from the creature of the row. Verified before the rename; returns the new ids."""
    import random
    import shutil
    import struct
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_outfits import build_entry, frame, frames_of, parse_body
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
    by = {c.id: c for c in discover(src)}
    tmp = out_dir.rstrip('/') + '.tmp'
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    cnt = ospr.count
    index = record_index(ospr)
    newrecs, recs, reused = [], {}, 0
    entries, src_specs = [], []
    for i, r in enumerate(t):
        c = by.get(r['src'])
        if c is None:
            raise SystemExit('no creature %s under %s' % (r['src'], src))
        m = measure(c)
        if m['reason']:
            raise SystemExit('creature %s: %s' % (r['src'], m['reason']))
        specs = groups_of(c, m['placed'])
        sid_map = {0: 0}
        for g, tiles in specs:
            for slot, a in enumerate(tiles):
                rec = encode_sprite(a)
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
        # the entry writer reads g.sprites as keys of the map: give each group its own keyed copy
        gs = []
        for g, tiles in specs:
            g2 = type(g)()
            for k in g.__slots__:
                setattr(g2, k, getattr(g, k))
            g2.sprites = tuple((id(g), s) for s in range(len(tiles)))
            gs.append(g2)
        entries.append(build_entry(b'', gs, sid_map))
        src_specs.append((first + i, r, specs))
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
    for nid, r, specs in src_specs:
        tm = md.outfit(nid)
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
                want = None if not a[:, :, 3].any() else clean(a)
                assert (want is None) == (y is None) and (want is None or np.array_equal(want, y)), (nid, 'slot')
                nslots += 1
            nframes += len(frames_of(h))
        assert digest(md, ms, nid) == spec_digest(specs), (nid, 'digest')
        for (g, tiles), h in zip(specs, mg):
            for (xx, yy, zz, ph) in frames_of(h):
                a = frame(h, ms, xx, yy, zz, ph)
                assert a.shape == (CANVAS, CANVAS, 4)
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
    """the pair holds every outfit at its id, its digest the one of the sums file, 2x2, one colour layer. Returns the problem lines."""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_outfits import parse_body
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    d, sp = Dat(dat), Spr(spr)
    if len(d.outfits) < first + len(t) - 1:
        return ['the pair has %d outfits, the pack outfits end at %d' % (len(d.outfits), first + len(t) - 1)]
    out = []
    for r in t:
        nid, src = int(r['new']), r['src']
        if digest(d, sp, nid) != s.get(src):
            out.append('outfit %d (src %s, %s): the pictures are not the ones of purchased_outfits.sums' % (nid, src, r['kind']))
        gs = parse_body(d, d.outfit(nid))
        if any(g.layers != 1 or (g.w, g.h) != (2, 2) for g in gs):
            out.append('outfit %d (src %s): not 2x2 with one layer' % (nid, src))
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
    if args[:1] == ['check']:
        p = problems() + map_problems() + write_map(check=True)
        for line in p:
            print('PROBLEM', line)
        print('purchased_outfits: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if args[:1] == ['looks']:
        p = map_problems() + write_map(check='--check' in args)
        for line in p:
            print('PROBLEM', line)
        print('monster_wst_looks: %d rows, %d problems' % (len(picks_rows()), len(p)))
        return 1 if p else 0
    cmd = args.pop(0) if args else ''
    src = opt(args, '--src')
    if cmd == 'ids' and src:
        for c in discover(src):
            m = measure(c)
            print('%s %s cell %d colours %d idle %d/%d walk %d scale %s out %s %s' % (
                c.id, c.kind, c.cell, m['colours'], m['idle'], m['idle_distinct'], m['walk'], m.get('scale'), m.get('outcolours'), m['reason']))
        return 0
    if cmd == 'select' and src:
        pair = None
        if '--pair' in args:
            i = args.index('--pair')
            pair = (args[i + 1], args[i + 2])
            del args[i:i + 3]
        picks = select(src, pair)
        for p in picks:
            print('%s  %-16s %s  scale %-3s idle %d walk %d  colours %5d  out %5d' % p)
        print('%d picks' % len(picks))
        if '--write' in args:
            write_table(picks)
        return 0
    if cmd == 'sums' and src:
        text = sums_text(pack_sums(src, [r['src'] for r in rows()]))
        if '--check' in args:
            old = open(SUMS, encoding='utf-8').read() if os.path.exists(SUMS) else None
            if old != text:
                print('PROBLEM purchased_outfits.sums is not what the pack files give')
                return 1
            print('purchased_outfits.sums: up to date')
            return 0
        with open(SUMS, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        return 0
    if cmd == 'build' and src and len(args) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(args[0], args[1], args[2], src, expect_md5=DAT_70_MD5)
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
