#!/usr/bin/env python3
"""Three creature packs of one author as boss outfits of 4x4 and 5x5 tiles (O608, after O605; client/MANIFEST.md "Creature packs as boss outfits (O608)").

    python3 -I gen_creature_outfits.py check                     # the table, the sums keys, the monster rows and the map (no pair, no pack files)
    python3 -I gen_creature_outfits.py looks [--check]           # server/data/monster/monster_creature_looks.csv from the `creature` rows of monster_looks/picks.csv
    python3 -I gen_creature_outfits.py ids --src DIR             # src id and measures of every creature under DIR (author's aid)
    python3 -I gen_creature_outfits.py table --src DIR [--write] # measure the creatures of ROWS, print (or write) the table and the sums
    python3 -I gen_creature_outfits.py sums --src DIR --check    # the pack files give the committed sums
    python3 -I gen_creature_outfits.py build DAT SPR OUT_DIR --src DIR
                                                                 # a pair with 3,526 outfits in, 3 more out (OUT_DIR must not exist)
    python3 -I gen_creature_outfits.py live DAT SPR              # the pair holds every outfit at its id, as the sums say

Owner 2026-11-17 (translated), after the nine 2x2 outfits of O605: "Put the creatures back the way they were. Forget the humanoids
and add the others to bosses. They can be bigger." and "3 is the number of monsters". So the three creatures that are no humanoid
(a drifting ooze, a floating aberration, a hovering shard of ice) are boss looks at the size they were drawn; the humanoids and the winged angel
are not imported, and the hunt monsters of O605 keep their old looks. docs/CREDITS.md names the author and each pack. The licence
allows commercial use and changes, asks for the credit, and allows distribution only inside the finished game: no sharing of the
original or changed files on their own. So no art is committed, as in O540: committed are this tool, the table
art_import/creature_outfits.csv and art_import/creature_outfits.sums (a digest of every outfit, to hold a built pair and the pack
files to). The pack files are read locally by this script only: never sent to a web or AI service, never shown to one.

Source. `--src DIR` holds the unpacked packs in any folder layout. A creature is found by its files, not by a name: a folder with
an idle animation folder (its name holds "idle") that has the four folders south, east, north, west of numbered PNG frames on one
256 px canvas. Its walk animation is the sibling folder whose name holds "walk", else the one that holds "move"; a creature with
neither walks on its idle frames (walk_src idle: a thing that hovers has no step). Attack and death frames are not read. A creature
is named by `src`: the first 12 hex digits of the sha256 of its first south idle frame file, so no pack name is in the repository.

Scale. None, ever (owner 2026-11-17, O616, translated: "Keep it as it is so no pixel is lost, apply this to the others too, it has
to look as good as possible."). A figure is taken pixel for pixel, at the size it was drawn (120 to 144 px on its long side on the
256 px canvas). The canvas is the smallest whole number of tiles that holds the box of all idle and walk frames of the four
directions: 4x4 (128 px) up to 128 px, 5x5 (160 px) up to 160 px, and so on up to 8x8 (the source canvas). The scale column says
so: 128/128 or 160/160. No step samples, crops or drops a pixel: `pixel_problems` holds every built frame to its source frame
(the same number of opaque pixels in the source frame, on the canvas and in the sprite tiles, and the same colours at the same
places). The packs have alpha 0 or 255 only; a frame with a soft pixel is refused, since the hard cut would lose or change it.

Place. One shift for all frames: the lowest opaque pixel of any frame on the last row of the canvas, the middle of the box on the
middle column. The dat displacement, (-48, 0) for 4x4 and (-64, 0) for 5x5, then moves the picture right, so the middle of the
figure stands over the middle of the creature's own tile and its lowest pixel on the tile's bottom row: a boss four tiles wide
reaches a tile and a half to each side of the tile it stands on. Negative displacements centre the big looks of the pair (the 5x5
world boss looks 1534 and 1538: (-64, -32) and (-64, -64); the client profile has GameNegativeOffset on); a 4x4 look without one
(3361) hangs up and left of its tile.

Frames. Every source frame is used (O616). The source runs at 12 pictures a second and has another number of frames in every
direction (11 to 21). A dat group has one number of phases for its four directions and one list of durations: the group has as
many phases as its longest direction has frames, and one phase lasts 83 ms, the pack's 12 a second. The longest direction plays
frame for frame at the pack's speed. A direction with n frames, fewer than the P phases, shows frame floor(i * n / P) at phase i:
every frame in order, the loop closed, P - n frames held for two phases, spread evenly, so its loop lasts P / n of the pack's
(the dat format has no per-direction phase count; the table columns idle_frames and walk_frames name the counts north / east /
south / west). The four directions are the pack's own: nothing is mirrored. A pack without a walk animation walks on its idle
frames (walk_src idle). The client plays the idle group by these durations; the phase of a walking creature is the engine's step
phase.

Foot point. The lowest pixel of every frame lies in the rows of the boss's tile, and the middle of the lowest 8 rows of the
figure, as a mean over the frames of a direction, in its columns (`foot_problems`).

The outfits go after the 3,526 outfits of pair 72 (3511-3524 costumes, 3525-3526 Ki auras): the row at line n (0-based) is outfit
3527 + n. They join pair 73. No other step planned for pair 73 adds an outfit (the centring O585 and the drawn wings O583 / O594
change outfits in place, the spell effects O596 / O600 / O606 / O607 add effects and missiles), so the order of the steps is free:
this step asks only for 3,526 outfits in its input. An outfit has an idle group (gtype 0) and a walk group (gtype 1), NxN, one
layer, 4 directions, and the displacement as its only flag. The append and its checks are gen_wst_outfits.build (old things byte
identical, every slot read back).
Needs numpy and Pillow (the fx venv of CI) for everything but `check` and `looks`.
"""
import csv
import os
import math
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_wst_outfits as W  # noqa: E402

ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'creature_outfits.csv')
SUMS = os.path.join(ART, 'creature_outfits.sums')
HEADER = ['src', 'new', 'kind', 'size', 'scale', 'disp', 'idle', 'idle_ms', 'walk', 'walk_ms', 'walk_src', 'colours', 'idle_frames',
          'walk_frames', 'pixels']
REPO = W.REPO
PICKS = W.PICKS
POOL = W.POOL
MONSTERS = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_creature_looks.csv')
MAP_HEADER = ['monster', 'look', 'new_look']
FAMILY = 'creature'
PAIR = 73
OUTFITS_72 = 3526
FIRST_NEW = OUTFITS_72 + 1
MIN_TILES = 4                       # a boss look is 4x4 tiles (128 px) or more
MAX_TILES = 8                       # up to the source canvas (256 px): never sampled down (owner 2026-11-17, O616)
SRC_CANVAS = 256
DISP_FLAG = 25                      # the displacement flag byte of our 10.98 dat (datspr.TABLE_NEW)
FPS = 12
FRAME_MS = int(round(1000.0 / FPS))  # one phase: 83 ms, the pack's 12 pictures a second
MAX_PHASES = 32                      # a sanity bound on the frames of one direction
MIN_IDLE = 2
MIN_WALK = 3
FOOT_ROWS = 8                        # the foot point of a frame: the middle of its lowest FOOT_ROWS rows
MAX_ON_LOOK = 2
DIRS = ('north', 'east', 'south', 'west')   # engine order
SOUTH = 2
KIND_NAMES = ('aberration', 'elemental', 'ooze')   # no humanoid and no angel: the owner dropped them (O608)

# the outfits in id order: (src id, kind). The boss that wears each one is in monster_looks/picks.csv (family `creature`).
ROWS = (
    ('cc1b36d161cb', 'ooze'),
    ('851989630524', 'aberration'),
    ('48602508e8e2', 'elemental'),
)


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_sums(path=SUMS):
    return W.read_sums(path)


def tiles_of_size(text):
    """N of a size text NxN from MIN_TILES to MAX_TILES, or None"""
    m = re.fullmatch(r'(\d)x(\d)', text)
    return int(m.group(1)) if m and m.group(1) == m.group(2) and MIN_TILES <= int(m.group(1)) <= MAX_TILES else None


def tiles_for(side):
    """the tiles of the canvas for a figure whose longer side is `side` px: the smallest canvas that holds it pixel for pixel"""
    return min(MAX_TILES, max(MIN_TILES, -(-side // 32)))


def scale_d(text, canvas):
    """D of a scale text C/D with C the canvas, or None"""
    m = re.fullmatch(r'%d/(\d+)' % canvas, text)
    return int(m.group(1)) if m else None


def frames_of(text):
    """[frames north, east, south, west] of a frames text n/e/s/w, or None"""
    m = re.fullmatch(r'(\d+)/(\d+)/(\d+)/(\d+)', text)
    return [int(v) for v in m.groups()] if m and all(1 <= int(v) <= MAX_PHASES for v in m.groups()) else None


def tile_box(tiles):
    """(x0, y0, x1, y1) of the creature's own tile on the canvas of an NxN outfit: the last tile, moved by the displacement"""
    c, (dx, dy) = 32 * tiles, disp_of(tiles)
    return (c - 32 + dx, c - 32 + dy, c - 1 + dx, c - 1 + dy)


def disp_of(tiles):
    """the dat displacement of an NxN outfit: the middle column of the canvas over the middle of the creature's tile, the last row on
    the tile's last row"""
    return (-(16 * tiles - 16), 0)


def disp_text(tiles):
    return '%d:%d' % disp_of(tiles)


def flags_of(row):
    """(the flag bytes of an outfit entry, the flags as the dat reader gives them) of a table row: the displacement only"""
    u = tuple(v & 0xFFFF for v in disp_of(tiles_of_size(row['size'])))
    return bytes([DISP_FLAG]) + struct.pack('<HH', *u), {'displacement': u}


def problems(table=None, sums=None, first=FIRST_NEW, want=ROWS):
    """What is wrong with the table: the rows are ROWS in order, ids in a row from the first new outfit, a src once, kinds, the size,
    the scale, the displacement, phases, durations, and the sums name the same outfits."""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out, seen = [], set()
    if want is not None and [(r['src'], r['kind']) for r in t] != list(want):
        out.append('the rows are not ROWS of gen_creature_outfits.py, in its order')
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
        n = tiles_of_size(r['size'])
        if n is None:
            out.append('src %s: size %s, a boss look is %dx%d to %dx%d (owner 2026-11-17)' % (d, r['size'], MIN_TILES, MIN_TILES, MAX_TILES, MAX_TILES))
            continue
        if scale_d(r['scale'], 32 * n) != 32 * n:
            out.append('src %s: scale %s is not %d/%d (pixel for pixel); nothing is sampled down (owner 2026-11-17)'
                       % (d, r['scale'], 32 * n, 32 * n))
        if r['disp'] != disp_text(n):
            out.append('src %s: displacement %s, a %s outfit stands on its tile with %s' % (d, r['disp'], r['size'], disp_text(n)))
        if not MIN_IDLE <= int(r['idle']) <= MAX_PHASES:
            out.append('src %s: %s idle phases, %d to %d' % (d, r['idle'], MIN_IDLE, MAX_PHASES))
        if not MIN_WALK <= int(r['walk']) <= MAX_PHASES:
            out.append('src %s: %s walk phases, %d to %d' % (d, r['walk'], MIN_WALK, MAX_PHASES))
        if r['walk_src'] not in ('walk', 'idle'):
            out.append('src %s: walk_src %s is not walk or idle' % (d, r['walk_src']))
        if int(r['idle_ms']) != FRAME_MS or int(r['walk_ms']) != FRAME_MS:
            out.append('src %s: a phase lasts %d ms, the pack\'s %d pictures a second' % (d, FRAME_MS, FPS))
        if int(r['colours']) < 1:
            out.append('src %s: no colours in the output' % d)
        # no frame dropped: a group has as many phases as its longest direction has frames
        for g in ('idle', 'walk'):
            ns = frames_of(r.get(g + '_frames') or '')
            if ns is None:
                out.append('src %s: %s_frames %s is not four frame counts north/east/south/west' % (d, g, r.get(g + '_frames')))
            elif max(ns) != int(r[g]):
                out.append('src %s: %s %s phases, its longest direction has %d frames: a frame is dropped or shown twice'
                           % (d, r[g], g, max(ns)))
        if r['walk_src'] == 'idle' and r.get('walk_frames') != r.get('idle_frames'):
            out.append('src %s: walk_src idle, but walk_frames is not idle_frames' % d)
        if not (r.get('pixels') or '').isdigit() or int(r['pixels']) < 1:
            out.append('src %s: pixels %s is not the count of opaque pixels of the outfit' % (d, r.get('pixels')))
    if set(s) != {r['new'] for r in t}:
        out.append('creature_outfits.sums and the table name other outfits (%s)' % ', '.join(sorted(set(s) ^ {r['new'] for r in t})))
    return out


# ---------------------------------------------------------------- the monsters

def picks_rows(path=PICKS):
    """[(monster, new look, lib id)] of the rows of family `creature` of monster_looks/picks.csv, in file order (lib id = the outfit's
    number in the table, new - 3526)"""
    with open(path, newline='', encoding='utf-8') as f:
        return [(r['monsters'], int(r['look']), int(r['lib_id'])) for r in csv.DictReader(f) if r['family'] == FAMILY]


def own_looks(root=MONSTERS):
    """{monster name: lookType} of our monster XML files (the look the repository gives each)"""
    out = {}
    for dp, _dn, fs in os.walk(root):
        for f in fs:
            if f.endswith('.xml'):
                t = open(os.path.join(dp, f), encoding='utf-8').read()
                m, look = re.search(r'<monster\s[^>]*name="([^"]+)"', t), re.search(r'<look\s+type="(\d+)"', t)
                if m and look:
                    out[m.group(1)] = int(look.group(1))
    return out


def old_looks(own=None, pool=None):
    """{monster: the look the repository gives it}: its XML file, else its row of the committed bounty pool (a base server monster)"""
    have = dict(W.pool_looks() if pool is None else pool)
    have.update(own_looks() if own is None else own)
    return have


def map_rows(picks=None, old=None):
    p = picks_rows() if picks is None else picks
    have = old_looks() if old is None else old
    return [(m, have[m], new) for m, new, _d in p]


def map_text(rows_):
    return ','.join(MAP_HEADER) + '\n' + ''.join('%s,%d,%d\n' % r for r in rows_)


def map_problems(table=None, picks=None, old=None, first=FIRST_NEW):
    """The `creature` rows of picks.csv against the outfit table: each look is a table outfit (and its lib id), every outfit is worn,
    at most MAX_ON_LOOK monsters on one, each monster once and known (a file of ours or a row of the pool)."""
    t = rows() if table is None else table
    p = picks_rows() if picks is None else picks
    have = old_looks() if old is None else old
    by = {int(r['new']): int(r['new']) - first + 1 for r in t}
    out, seen, used = [], set(), {}
    for m, new, d in p:
        if by.get(new) != d:
            out.append('%s: look %d / lib id %d is not a row of creature_outfits.csv' % (m, new, d))
        used[new] = used.get(new, 0) + 1
        if used[new] > MAX_ON_LOOK:
            out.append('look %d is on more than %d monsters' % (new, MAX_ON_LOOK))
        if m in seen:
            out.append('%s is on two rows of picks.csv' % m)
        seen.add(m)
        if m not in have:
            out.append('%s has no monster file of ours and no row of the bounty pool' % m)
    for new in sorted(set(by) - set(used)):
        out.append('outfit %d is worn by no monster of picks.csv' % new)
    return out


def write_map(check=False):
    """write monster_creature_looks.csv (monster, look, new_look), or with check compare it; returns the problem lines"""
    try:
        text = map_text(map_rows())
    except KeyError:
        return []   # map_problems names the monster
    old = open(MAP, encoding='utf-8', newline='').read() if os.path.exists(MAP) else None
    if old == text:
        return []
    if check:
        return ['server/data/monster/monster_creature_looks.csv is not up to date (run gen_creature_outfits.py looks)']
    with open(MAP, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return []


# ---------------------------------------------------------------- the pack files

class Creature:
    """one creature of the pack files: id, the frame files {('idle' | 'walk', direction 0..3 n e s w): [paths]}, walk_src"""

    def __init__(self, cid, files, walk_src):
        self.id, self.files, self.walk_src = cid, files, walk_src


def _frames_dir(path):
    """the sorted PNG files of a direction folder"""
    return sorted(os.path.join(path, f) for f in os.listdir(path) if f.lower().endswith('.png')) if os.path.isdir(path) else []


def _anim(path):
    """{direction: [files]} of an animation folder, or None when one of the four directions is missing"""
    out = {d: _frames_dir(os.path.join(path, name)) for d, name in enumerate(DIRS)}
    return out if all(out.values()) else None


def discover(src):
    """[Creature] of every creature under src (read only), sorted by id"""
    found = []
    for root, dirs, _files in os.walk(src):
        idle = sorted(d for d in dirs if 'idle' in d.lower() and _anim(os.path.join(root, d)))
        if not idle:
            continue
        ia = _anim(os.path.join(root, idle[0]))
        walk = None
        for word in ('walk', 'move'):
            names = sorted(d for d in dirs if word in d.lower() and d not in idle and _anim(os.path.join(root, d)))
            if names:
                walk = _anim(os.path.join(root, names[0]))
                break
        files = {('idle', d): ia[d] for d in range(4)}
        files.update({('walk', d): (walk or ia)[d] for d in range(4)})
        found.append(Creature(W._sha12(ia[SOUTH][0]), files, 'walk' if walk else 'idle'))
    found.sort(key=lambda c: c.id)
    if len({c.id for c in found}) != len(found):
        raise SystemExit('two creatures with one src id under %s' % src)
    return found


def cut(a):
    """alpha cut hard at one half: opaque or nothing"""
    import numpy as np
    out = np.zeros_like(a)
    m = a[..., 3] > 127
    out[m] = a[m]
    out[m, 3] = 255
    return out


def pick(n, phases):
    """the frames of a loop of n pictures shown as `phases` phases: evenly spaced, the first frame first. With phases >= n every
    frame is shown, in order, phases - n of them for two phases"""
    return [(i * n) // phases for i in range(phases)]


def opaque(a):
    """the opaque pixels of an RGBA array"""
    return int((a[..., 3] > 0).sum())


def sample(a, box, d, canvas):
    """nearest neighbour: the box (x0, y0, x1, y1 inclusive) of a source frame at scale canvas/d (d = canvas: pixel for pixel)"""
    import numpy as np
    x0, y0, x1, y1 = box
    xs = [x0 + ((2 * i + 1) * d) // (2 * canvas) for i in range(canvas) if ((2 * i + 1) * d) // (2 * canvas) <= x1 - x0]
    ys = [y0 + ((2 * i + 1) * d) // (2 * canvas) for i in range(canvas) if ((2 * i + 1) * d) // (2 * canvas) <= y1 - y0]
    return np.ascontiguousarray(a[np.ix_(ys, xs)])


def place(fr, canvas):
    """shift every frame by one (dx, dy) onto the canvas: the lowest opaque pixel on the last row, the middle of the union box on the
    middle of the canvas (the dat displacement then puts it over the tile). Returns {key: [canvas x canvas RGBA arrays]}; raises
    ValueError when a frame does not fit."""
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
    dy = canvas - 1 - y1
    dx = math.floor((canvas - 1) / 2.0 - (x0 + x1) / 2.0)
    if x0 + dx < 0 or y0 + dy < 0 or x1 + dx > canvas - 1:
        raise ValueError('the figure (%dx%d) does not fit the %d px canvas' % (x1 - x0 + 1, y1 - y0 + 1, canvas))
    out = {}
    for k, lst in fr.items():
        res = []
        for a in lst:
            c = np.zeros((canvas, canvas, 4), np.uint8)
            h, w = a.shape[:2]
            sy0, sx0 = max(0, -dy), max(0, -dx)     # rows and columns past the canvas hold no opaque pixel (checked above)
            ey, ex = min(h, canvas - dy), min(w, canvas - dx)
            c[sy0 + dy:ey + dy, sx0 + dx:ex + dx] = a[sy0:ey, sx0:ex]
            res.append(c)
        out[k] = res
    return out


def measure(c):
    """the outfit of a creature: {'placed': {(group, direction): [frames of the canvas]}, 'tiles', 'scale', 'idle', 'walk', 'idle_ms', 'walk_ms',
    'colours', 'box', 'counts', 'loop', 'use': {(group, direction): [source frame of each phase]}, 'src': {(group, direction): [the
    source frames as read]}, 'pixels'}; raises ValueError when it cannot be one"""
    import numpy as np
    raw = {k: [W._read_png(p) for p in ps] for k, ps in c.files.items()}
    for lst in raw.values():
        for a in lst:
            if a.shape[2] == 4 and ((a[..., 3] > 0) & (a[..., 3] < 255)).any():
                raise ValueError('a frame with soft alpha: the hard cut would lose or change a pixel')
    src = {k: [cut(a) for a in lst] for k, lst in raw.items()}
    x0 = y0 = 10 ** 6
    x1 = y1 = -1
    for lst in src.values():
        for a in lst:
            if a.shape != (SRC_CANVAS, SRC_CANVAS, 4):
                raise ValueError('a frame of %dx%d px, the canvas is %d' % (a.shape[1], a.shape[0], SRC_CANVAS))
            ys, xs = np.nonzero(a[..., 3])
            if not len(xs):
                raise ValueError('an empty frame')
            x0, x1, y0, y1 = min(x0, int(xs.min())), max(x1, int(xs.max())), min(y0, int(ys.min())), max(y1, int(ys.max()))
    box = (x0, y0, x1, y1)
    side = max(x1 - x0 + 1, y1 - y0 + 1)
    tiles = tiles_for(side)
    canvas = 32 * tiles
    if side > canvas:
        raise ValueError('a figure of %d px, longer than the %d px canvas: nothing is sampled down' % (side, canvas))
    d = canvas      # pixel for pixel, always (owner 2026-11-17)
    out = {'box': box, 'tiles': tiles, 'scale': '%d/%d' % (canvas, d), 'counts': {k: len(v) for k, v in src.items()}, 'src': raw,
           'use': {}}
    fr = {}
    for g in ('idle', 'walk'):
        ns = [len(src[(g, k)]) for k in range(4)]
        phases = max(ns)        # no frame dropped: as many phases as the longest direction has frames
        if phases > MAX_PHASES:
            raise ValueError('%d %s frames in one direction, %d at most' % (phases, g, MAX_PHASES))
        out[g] = phases
        out[g + '_ms'] = FRAME_MS
        for k in range(4):
            out['use'][(g, k)] = pick(ns[k], phases)
            fr[(g, k)] = [sample(src[(g, k)][i], box, d, canvas) for i in out['use'][(g, k)]]
    out['placed'] = place(fr, canvas)
    out['pixels'] = sum(opaque(a) for lst in out['placed'].values() for a in lst)
    out['colours'] = W.colours_south(out['placed'])
    # how closed the source loop is, facing south: the step last -> first against the median step (pixels that change)
    loop = {}
    for g in ('idle', 'walk'):
        lst = src[(g, SOUTH)]
        steps = [int((lst[i] != lst[(i + 1) % len(lst)]).any(-1).sum()) for i in range(len(lst))]
        loop[g] = (steps[-1], int(np.median(steps[:-1])) if len(steps) > 1 else 0)
    out['loop'] = loop
    return out


def pixel_problems(m, name=''):
    """No pixel lost (owner 2026-11-17, O616): every phase of every direction against its source frame as read from the pack. The
    same number of opaque pixels in the source frame, on the canvas and in the sprite tiles; the canvas is the source frame moved
    by one shift, colour for colour; every source frame of every direction is shown, in order; nothing sampled."""
    import numpy as np
    from gen_effects import tiles_of
    out, n = [], m['tiles']
    c = 32 * n
    if m['scale'] != '%d/%d' % (c, c):
        out.append('%sscale %s: sampled, not pixel for pixel' % (name, m['scale']))
    shift = None
    for (g, d), lst in sorted(m['placed'].items()):
        use, srcs = m['use'][(g, d)], m['src'][(g, d)]
        where = '%s%s %s' % (name, g, DIRS[d])
        if len(lst) != m[g] or len(use) != m[g]:
            out.append('%s: %d phases, the group has %d' % (where, len(lst), m[g]))
            continue
        if sorted(set(use)) != list(range(len(srcs))) or use != sorted(use):
            out.append('%s: the phases show the frames %s of %d: a frame is dropped or out of order' % (where, use, len(srcs)))
        for ph, a in enumerate(lst):
            s = srcs[use[ph]]
            want, got = opaque(s), opaque(a)
            tl = tiles_of(a, n, n)
            in_tiles = sum(opaque(tl[(ww, hh)]) for hh in range(n) for ww in range(n) if tl[(ww, hh)] is not None)
            if not want == got == in_tiles:
                out.append('%s phase %d (frame %d): %d opaque pixels in the source, %d on the canvas, %d in the tiles'
                           % (where, ph, use[ph], want, got, in_tiles))
                continue
            ys, xs = np.nonzero(s[..., 3] > 0)
            cy, cx = np.nonzero(a[..., 3] > 0)
            sh = (int(cx.min()) - int(xs.min()), int(cy.min()) - int(ys.min()))
            shift = sh if shift is None else shift
            if sh != shift:
                out.append('%s phase %d: moved by %s, the other frames by %s' % (where, ph, sh, shift))
            elif not ((cy - sh[1] == ys).all() and (cx - sh[0] == xs).all() and (a[cy, cx] == s[ys, xs]).all()):
                out.append('%s phase %d (frame %d): not the source frame pixel for pixel' % (where, ph, use[ph]))
    return out


def foot_of(a):
    """(x, y) of the foot point of a placed frame: the mean column of the opaque pixels of its lowest FOOT_ROWS rows, its lowest row"""
    import numpy as np
    ys, xs = np.nonzero(a[..., 3] > 0)
    low = int(ys.max())
    return float(xs[ys > low - FOOT_ROWS].mean()), low


def foot_problems(m, name=''):
    """The body's foot point stands on the boss's tile: the lowest pixel of every frame in the tile's rows, and the mean foot column
    of the frames of a direction in the tile's columns (a tentacle that trails in one frame does not move the body)."""
    x0, y0, x1, y1 = tile_box(m['tiles'])
    out = []
    for (g, d), lst in sorted(m['placed'].items()):
        feet = [foot_of(a) for a in lst]
        lows = [f[1] for f in feet]
        mx = sum(f[0] for f in feet) / len(feet)
        if min(lows) < y0 or max(lows) > y1:
            out.append('%s%s %s: lowest pixel on rows %d to %d, the tile has %d to %d' % (name, g, DIRS[d], min(lows), max(lows), y0, y1))
        if not x0 <= mx <= x1:
            out.append('%s%s %s: foot column %.1f, the tile has %d to %d' % (name, g, DIRS[d], mx, x0, x1))
    return out


def foot_line(m):
    """the foot numbers of an outfit for the log: per group the range of the lowest row and of the mean foot column over the directions"""
    x0, y0, x1, y1 = tile_box(m['tiles'])
    parts = []
    for g in ('idle', 'walk'):
        lows, cols = [], []
        for d in range(4):
            feet = [foot_of(a) for a in m['placed'][(g, d)]]
            lows += [f[1] for f in feet]
            cols.append(sum(f[0] for f in feet) / len(feet))
        parts.append('%s rows %d-%d cols %.1f-%.1f' % (g, min(lows), max(lows), min(cols), max(cols)))
    return 'tile cols %d-%d rows %d-%d; %s' % (x0, x1, y0, y1, '; '.join(parts))


def frames_text(m, g):
    return '/'.join(str(m['counts'][(g, d)]) for d in range(4))


def groups_of(m):
    """[(Group, [tile arrays in slot order])] idle then walk: the dat shape and the sprite arrays of one outfit"""
    from import_outfits import Group
    from gen_effects import tiles_of
    out, n = [], m['tiles']
    for gtype, key in ((0, 'idle'), (1, 'walk')):
        phases, ms = m[key], m[key + '_ms']
        g = Group()
        g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases = gtype, n, n, 32 * n, 1, 4, 1, 1, phases
        g.anim = (0, 0, 0, tuple([ms, ms] * phases)) if phases > 1 else None
        tiles = []
        for ph in range(phases):
            for d in range(4):
                t = tiles_of(m['placed'][(key, d)][ph], n, n)
                for hh in range(n):
                    for ww in range(n):
                        tiles.append(t[(ww, hh)])
        g.sprites = tuple(range(len(tiles)))
        out.append((g, tiles))
    return out


def measured(src, want=ROWS, first=FIRST_NEW):
    """[(row dict, measure)] of the rows of `want` (src, kind) from the pack files, ids from `first`"""
    by = {c.id: c for c in discover(src)}
    out = []
    for i, (cid, kind) in enumerate(want):
        if cid not in by:
            raise SystemExit('no creature %s under %s' % (cid, src))
        try:
            m = measure(by[cid])
        except ValueError as e:
            raise SystemExit('creature %s: %s' % (cid, e))
        bad = pixel_problems(m) + foot_problems(m)
        if bad:
            raise SystemExit('creature %s: %s' % (cid, '; '.join(bad[:5])))
        r = {'src': cid, 'new': str(first + i), 'kind': kind, 'size': '%dx%d' % (m['tiles'], m['tiles']), 'scale': m['scale'], 'disp': disp_text(m['tiles']),
             'idle': str(m['idle']), 'idle_ms': str(m['idle_ms']), 'walk': str(m['walk']), 'walk_ms': str(m['walk_ms']),
             'walk_src': by[cid].walk_src, 'colours': str(m['colours']), 'idle_frames': frames_text(m, 'idle'),
             'walk_frames': frames_text(m, 'walk'), 'pixels': str(m['pixels'])}
        out.append((r, m))
    return out


def table_text(rs):
    return ','.join(HEADER) + '\n' + ''.join(','.join(r[k] for k in HEADER) + '\n' for r in rs)


def sums_text(sums):
    return ('# sha256 of each outfit (shapes, animator, every sprite slot) by outfit id, written by gen_creature_outfits.py table --write (O608)\n'
            + ''.join('%s %s\n' % (k, sums[k]) for k in sorted(sums)))


def pack_sums(ms):
    return {r['new']: W.spec_digest(groups_of(m)) for r, m in ms}


def idle_problems(ms):
    """the idle rule of O533 on the built frames: the idle group has 2 or more phases with different pictures facing south (and every way)"""
    out = []
    for r, m in ms:
        for d in range(4):
            if W.distinct(m['placed'][('idle', d)]) < MIN_IDLE:
                out.append('outfit %s: the idle frames facing %s are one picture' % (r['new'], DIRS[d]))
    return out


# ---------------------------------------------------------------- the pair

def build(dat, spr, out_dir, src, want=ROWS, first=FIRST_NEW, log=print):
    """pair in (its outfits end at first - 1) -> pair out in OUT_DIR: one new outfit per row. Returns the new ids."""
    ms = measured(src, want, first)
    by = {r['new']: m for r, m in ms}
    return W.build(dat, spr, out_dir, None, table=[r for r, _m in ms], first=first, log=log, specs_of=lambda r: groups_of(by[r['new']]),
                   flags_of=flags_of)


def live(dat, spr, table=None, sums=None, log=print):
    """the pair holds every outfit at its id, its digest the one of the sums file, its size, one layer, idle and walk group, the displacement
    as its only flag; and (O616) every phase lasts the pack's 83 ms, the sprite tiles hold the opaque pixels the table counts, a
    direction shows as many different pictures as the pack has frames, and its foot point stands on the boss's tile"""
    import numpy as np
    from datspr import Dat, Spr
    from import_outfits import parse_body
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    d, sp = Dat(dat), Spr(spr)
    last = int(t[-1]['new'])
    if len(d.outfits) < last:
        return ['the pair has %d outfits, the creature outfits end at %d' % (len(d.outfits), last)]
    out = []
    for r in t:
        nid = int(r['new'])
        if W.digest(d, sp, nid) != s.get(r['new']):
            out.append('outfit %d (src %s): the pictures are not the ones of creature_outfits.sums' % (nid, r['src']))
        th = d.outfit(nid)
        gs = parse_body(d, th)
        n = tiles_of_size(r['size'])
        if dict(th.flags) != flags_of(r)[1]:
            out.append('outfit %d (src %s): flags %s, the displacement %s only' % (nid, r['src'], dict(th.flags), r['disp']))
        elif [g.gtype for g in gs] != [0, 1] or any(g.layers != 1 or (g.w, g.h) != (n, n) for g in gs):
            out.append('outfit %d (src %s): not an idle and a walk group of %s with one layer' % (nid, r['src'], r['size']))
        elif (gs[0].phases, gs[1].phases) != (int(r['idle']), int(r['walk'])):
            out.append('outfit %d (src %s): %d / %d phases, the table says %s / %s' % (nid, r['src'], gs[0].phases, gs[1].phases, r['idle'], r['walk']))
        else:
            c = 32 * n
            placed, total = {}, 0
            for g, key in zip(gs, ('idle', 'walk')):
                ms = int(r[key + '_ms'])
                if not g.anim or tuple(g.anim[3]) != (ms, ms) * g.phases:
                    out.append('outfit %d (src %s): the %s phases do not last %d ms each' % (nid, r['src'], key, ms))
                for dd in range(4):
                    lst = []
                    for ph in range(g.phases):
                        a = np.zeros((c, c, 4), np.uint8)
                        for hh in range(n):
                            for ww in range(n):
                                sid = g.sprites[((ph * 4 + dd) * n + hh) * n + ww]
                                tl = sp.sprite(sid) if sid else None
                                if tl is not None:
                                    a[(n - 1 - hh) * 32:(n - hh) * 32, (n - 1 - ww) * 32:(n - ww) * 32] = tl
                        total += opaque(a)
                        lst.append(a)
                    placed[(key, dd)] = lst
                    want = (frames_of(r[key + '_frames']) or [0] * 4)[dd]
                    if W.distinct(lst) != want:
                        out.append('outfit %d (src %s): %s %s shows %d different pictures, the pack has %d frames'
                                   % (nid, r['src'], key, DIRS[dd], W.distinct(lst), want))
            if total != int(r['pixels']):
                out.append('outfit %d (src %s): %d opaque pixels in its sprites, the table counts %d' % (nid, r['src'], total, int(r['pixels'])))
            out += foot_problems({'tiles': n, 'placed': placed}, 'outfit %d: ' % nid)
    log('live: %d outfits %d to %d checked, %d problems' % (len(t), int(t[0]['new']), last, len(out)))
    return out


def main(argv):
    args = list(argv)
    if args[:1] == ['check']:
        p = problems() + map_problems() + write_map(check=True)
        for line in p:
            print('PROBLEM', line)
        print('creature_outfits: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if args[:1] == ['looks']:
        p = map_problems() + write_map(check='--check' in args)
        for line in p:
            print('PROBLEM', line)
        print('monster_creature_looks: %d rows, %d problems' % (len(picks_rows()), len(p)))
        return 1 if p else 0
    cmd = args.pop(0) if args else ''
    src = W.opt(args, '--src')
    if cmd == 'ids' and src:
        for c in discover(src):
            try:
                m = measure(c)
                print('%s walk_src %s frames %s box %s scale %s idle %d x %d ms walk %d x %d ms colours %d loop (last step, median step) %s' % (
                    c.id, c.walk_src, ' '.join('%s%s=%d' % (g[0], DIRS[d][0], n) for (g, d), n in sorted(m['counts'].items())), m['box'],
                    m['scale'], m['idle'], m['idle_ms'], m['walk'], m['walk_ms'], m['colours'], m['loop']))
                print('    pixels %d; %s; problems %s' % (m['pixels'], foot_line(m), (pixel_problems(m) + foot_problems(m)) or 'none'))
            except ValueError as e:
                print('%s cannot be an outfit: %s' % (c.id, e))
        return 0
    if cmd in ('table', 'sums') and src:
        ms = measured(src)
        p = idle_problems(ms)
        for line in p:
            print('PROBLEM', line)
        if p:
            return 1
        ttext, stext = table_text([r for r, _m in ms]), sums_text(pack_sums(ms))
        if cmd == 'sums' or '--check' in args:
            old = open(SUMS, encoding='utf-8').read() if os.path.exists(SUMS) else None
            oldt = open(TABLE, encoding='utf-8', newline='').read() if os.path.exists(TABLE) else None
            if old != stext or oldt != ttext:
                print('PROBLEM creature_outfits.csv / .sums are not what the pack files give')
                return 1
            print('creature_outfits.csv and .sums: up to date')
            return 0
        sys.stdout.write(ttext)
        if '--write' in args:
            with open(TABLE, 'w', encoding='utf-8', newline='') as f:
                f.write(ttext)
            with open(SUMS, 'w', encoding='utf-8', newline='') as f:
                f.write(stext)
        return 0
    if cmd == 'build' and src and len(args) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(args[0], args[1], args[2], src)
        p = live(os.path.join(args[2], 'Tibia.dat'), os.path.join(args[2], 'Tibia.spr'))
        for line in p:
            print('PROBLEM', line)
        print('built %d outfits %d to %d' % (len(ids), ids[0], ids[-1]))
        return 1 if p else 0
    if cmd == 'live' and len(args) == 2:
        p = live(args[0], args[1])
        for line in p:
            print('PROBLEM', line)
        return 1 if p else 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
