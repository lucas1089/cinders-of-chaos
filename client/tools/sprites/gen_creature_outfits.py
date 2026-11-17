#!/usr/bin/env python3
"""Eight creature packs of one author as 2x2 creature outfits (O605; client/MANIFEST.md "Creature packs as 2x2 outfits (O605)").

    python3 -I gen_creature_outfits.py check                     # the table, the sums keys, the monster rows and the map (no pair, no pack files)
    python3 -I gen_creature_outfits.py looks [--check]           # server/data/monster/monster_creature_looks.csv from the `creature` rows of monster_looks/picks.csv
    python3 -I gen_creature_outfits.py ids --src DIR             # src id and measures of every creature under DIR (author's aid)
    python3 -I gen_creature_outfits.py table --src DIR [--write] # measure the creatures of ROWS, print (or write) the table and the sums
    python3 -I gen_creature_outfits.py sums --src DIR --check    # the pack files give the committed sums
    python3 -I gen_creature_outfits.py build DAT SPR OUT_DIR --src DIR
                                                                 # a pair with 3,526 outfits in, 9 more out (OUT_DIR must not exist)
    python3 -I gen_creature_outfits.py live DAT SPR              # the pair holds every outfit at its id, as the sums say

Owner 2026-11-17 (translated): "Import the creatures. They are 2x2." Eight creature packs of one author (docs/CREDITS.md names the
author and each pack). The licence allows commercial use and changes, asks for the credit, and allows distribution only inside the
finished game: no sharing of the original or changed files on their own. So no art is committed, as in O540: committed are this tool,
the table art_import/creature_outfits.csv and art_import/creature_outfits.sums (a digest of every outfit, to hold a built pair and
the pack files to). The pack files are read locally by this script only: never sent to a web or AI service, never shown to one.

Source. `--src DIR` holds the unpacked packs in any folder layout. A creature is found by its files, not by a name: a folder with
an idle animation folder (its name holds "idle") that has the four folders south, east, north, west of numbered PNG frames on one
256 px canvas. Its walk animation is the sibling folder whose name holds "walk", else the one that holds "move"; a creature with
neither walks on its idle frames (walk_src idle: a thing that hovers has no step). Attack and death frames are not read. A creature
is named by `src`: the first 12 hex digits of the sha256 of its first south idle frame file, so no pack name is in the repository.

Scale. One figure of these packs is 120 to 144 px on its long side on the 256 px canvas. A 2x2 outfit is 64 px, so the frames go
down 2:1 with nearest neighbour sampling (no filter, so no colour the art does not have; the art is drawn in 2 px blocks). Where
the box of all idle and walk frames of the four directions is longer than 128 px, the sampling step grows so that the box is 64 px:
scale 64/D, D = the longer side of that box, at least 128. Alpha is cut hard at one half.

Place (the rule of gen_wst_outfits.py, measured on the 671 2x2 monster looks of pair 71: feet 0 to 6 px above the bottom row, no
displacement flag, the box right against the right edge): one shift for all frames, the lowest opaque pixel of any frame on row 63,
the middle of the box on column 47.5, moved left when the box would pass column 63.

Frames. The source runs at 12 pictures a second and has another number of frames in every direction. A dat group has one number
of phases: the idle group has IDLE_PHASES (4), the walk group WALK_PHASES (8), fewer when a direction has fewer frames. A direction
with n frames gives the frames floor(i * n / phases): evenly spaced over its own loop, so the loop stays closed. One phase lasts
the mean loop time of the four directions divided by the phases.

Tint. A row with a tint is a second outfit of the same creature: `cold+120` turns every pixel whose hue is cold (150 to 270 degrees,
saturation 0.15 or more) by 120 degrees and leaves the warm and the grey ones (skin, metal). The elite of a monster family wears it,
so no two hunt monsters share a look (O529).

The outfits go after the 3,526 outfits of pair 72 (3511-3524 costumes, 3525-3526 Ki auras): the row at line n (0-based) is outfit
3527 + n. They join pair 73. No other step planned for pair 73 adds an outfit (the centring O585 and the drawn wings O583 / O594
change outfits in place, the spell effects O596 / O600 add effects and missiles), so the order of the steps is free: this step asks
only for 3,526 outfits in its input. An outfit has an idle group (gtype 0) and a walk group (gtype 1), 2x2, one layer, 4 directions,
no flags. The append and its checks are gen_wst_outfits.build (old things byte identical, every slot read back).
Needs numpy and Pillow (the fx venv of CI) for everything but `check` and `looks`.
"""
import colorsys
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_wst_outfits as W  # noqa: E402

ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'creature_outfits.csv')
SUMS = os.path.join(ART, 'creature_outfits.sums')
HEADER = ['src', 'new', 'kind', 'size', 'scale', 'idle', 'idle_ms', 'walk', 'walk_ms', 'walk_src', 'tint', 'colours']
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
CANVAS = W.CANVAS
SRC_CANVAS = 256
FPS = 12
IDLE_PHASES = 4
WALK_PHASES = 8
MIN_IDLE = 2
MIN_WALK = 3
MAX_ON_LOOK = 2
DIRS = ('north', 'east', 'south', 'west')   # engine order
SOUTH = 2
KIND_NAMES = ('aberration', 'angel/spirit', 'elemental', 'humanoid', 'ooze')
TINTS = {'': None, 'cold+120': (150.0, 270.0, 0.15, 120.0)}   # hue from, hue to (degrees), least saturation, turn

# the outfits in id order: (src id, kind, tint). The monster that wears each one is in monster_looks/picks.csv (family `creature`).
ROWS = (
    ('cc1b36d161cb', 'ooze', ''),
    ('851989630524', 'aberration', ''),
    ('48602508e8e2', 'elemental', ''),
    ('f4dcb7077799', 'humanoid', ''),
    ('89411b15353c', 'humanoid', ''),
    ('8e477f3018bc', 'humanoid', ''),
    ('28a8b3a3df23', 'angel/spirit', ''),
    ('9f3b1c04adc4', 'humanoid', ''),
    ('8e477f3018bc', 'humanoid', 'cold+120'),
)


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_sums(path=SUMS):
    return W.read_sums(path)


def scale_d(text):
    """D of a scale text 64/D, or None"""
    m = re.fullmatch(r'64/(\d+)', text)
    return int(m.group(1)) if m else None


def problems(table=None, sums=None, first=FIRST_NEW, want=ROWS):
    """What is wrong with the table: the rows are ROWS in order, ids in a row from the first new outfit, a (src, tint) once, kinds,
    2x2, the scale, phases, durations, and the sums name the same outfits."""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out, seen = [], set()
    if want is not None and [(r['src'], r['kind'], r['tint']) for r in t] != list(want):
        out.append('the rows are not ROWS of gen_creature_outfits.py, in its order')
    for i, r in enumerate(t):
        d, n = r['src'], int(r['new'])
        if not re.fullmatch(r'[0-9a-f]{12}', d):
            out.append('row %d: src %s is not 12 hex digits' % (i, d))
        if n != first + i:
            out.append('src %s: new id %d, the row at line %d must be %d' % (d, n, i, first + i))
        if (d, r['tint']) in seen:
            out.append('src %s with tint "%s" is on two rows' % (d, r['tint']))
        seen.add((d, r['tint']))
        if r['kind'] not in KIND_NAMES:
            out.append('src %s: kind %s is not one of %s' % (d, r['kind'], ', '.join(KIND_NAMES)))
        if r['size'] != '2x2':
            out.append('src %s: size %s, every outfit of this table is 2x2 (owner 2026-11-17)' % (d, r['size']))
        dd = scale_d(r['scale'])
        if dd is None or dd < SRC_CANVAS // 2 or dd > SRC_CANVAS:
            out.append('src %s: scale %s is not 64/D with D from %d to %d' % (d, r['scale'], SRC_CANVAS // 2, SRC_CANVAS))
        if not MIN_IDLE <= int(r['idle']) <= IDLE_PHASES:
            out.append('src %s: %s idle phases, %d to %d' % (d, r['idle'], MIN_IDLE, IDLE_PHASES))
        if not MIN_WALK <= int(r['walk']) <= WALK_PHASES:
            out.append('src %s: %s walk phases, %d to %d' % (d, r['walk'], MIN_WALK, WALK_PHASES))
        if r['walk_src'] not in ('walk', 'idle'):
            out.append('src %s: walk_src %s is not walk or idle' % (d, r['walk_src']))
        if not 40 <= int(r['idle_ms']) <= 1000 or not 40 <= int(r['walk_ms']) <= 1000:
            out.append('src %s: a phase lasts 40 to 1000 ms' % d)
        if r['tint'] not in TINTS:
            out.append('src %s: tint %s is not one of %s' % (d, r['tint'], ', '.join(k for k in TINTS if k)))
        if r['tint'] and (d, '') not in seen:
            out.append('src %s: the tinted row comes after the plain row of its creature' % d)
        if int(r['colours']) < 1:
            out.append('src %s: no colours in the output' % d)
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
    """the frames of a loop of n pictures shown as `phases` phases: evenly spaced, the first frame first"""
    return [(i * n) // phases for i in range(phases)]


def tint_colour(rgb, spec):
    lo, hi, sat, turn = spec
    h, s, v = colorsys.rgb_to_hsv(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0)
    if s < sat or not lo <= h * 360.0 <= hi:
        return rgb
    r, g, b = colorsys.hsv_to_rgb((h + turn / 360.0) % 1.0, s, v)
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


def tinted(a, tint):
    """the frame with the tint of a row ('' = as drawn)"""
    import numpy as np
    spec = TINTS[tint]
    if spec is None:
        return a
    out = a.copy()
    m = a[..., 3] > 0
    cols, inv = np.unique(a[m][:, :3], axis=0, return_inverse=True)
    new = np.array([tint_colour(tuple(int(x) for x in c), spec) for c in cols], np.uint8).reshape(-1, 3)
    out[m, :3] = new[inv.reshape(-1)]
    return out


def sample(a, box, d):
    """nearest neighbour: the box (x0, y0, x1, y1 inclusive) of a source frame at scale 64/d"""
    import numpy as np
    x0, y0, x1, y1 = box
    xs = [x0 + ((2 * i + 1) * d) // 128 for i in range(CANVAS) if ((2 * i + 1) * d) // 128 <= x1 - x0]
    ys = [y0 + ((2 * i + 1) * d) // 128 for i in range(CANVAS) if ((2 * i + 1) * d) // 128 <= y1 - y0]
    return np.ascontiguousarray(a[np.ix_(ys, xs)])


def measure(c, tint='', idle_phases=IDLE_PHASES, walk_phases=WALK_PHASES):
    """the outfit of a creature: {'placed': {(group, direction): [64 px frames]}, 'scale', 'idle', 'walk', 'idle_ms', 'walk_ms',
    'colours', 'box', 'counts', 'loop'}; raises ValueError when it cannot be one"""
    import numpy as np
    src = {k: [cut(W._read_png(p)) for p in ps] for k, ps in c.files.items()}
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
    d = max(SRC_CANVAS // 2, x1 - x0 + 1, y1 - y0 + 1)
    out = {'box': box, 'scale': '64/%d' % d, 'counts': {k: len(v) for k, v in src.items()}}
    fr = {}
    for g, want in (('idle', idle_phases), ('walk', walk_phases)):
        ns = [len(src[(g, k)]) for k in range(4)]
        phases = min([want] + ns)
        out[g] = phases
        out[g + '_ms'] = int(round(1000.0 * sum(ns) / 4.0 / FPS / phases))
        for k in range(4):
            fr[(g, k)] = [tinted(sample(src[(g, k)][i], box, d), tint) for i in pick(ns[k], phases)]
    out['placed'] = W.place(fr)
    out['colours'] = W.colours_south(out['placed'])
    # how closed the source loop is, facing south: the step last -> first against the median step (pixels that change)
    loop = {}
    for g in ('idle', 'walk'):
        lst = src[(g, SOUTH)]
        steps = [int((lst[i] != lst[(i + 1) % len(lst)]).any(-1).sum()) for i in range(len(lst))]
        loop[g] = (steps[-1], int(np.median(steps[:-1])) if len(steps) > 1 else 0)
    out['loop'] = loop
    return out


def groups_of(m):
    """[(Group, [tile arrays in slot order])] idle then walk: the dat shape and the sprite arrays of one outfit"""
    from import_outfits import Group
    from gen_effects import tiles_of
    out = []
    for gtype, key in ((0, 'idle'), (1, 'walk')):
        phases, ms = m[key], m[key + '_ms']
        g = Group()
        g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases = gtype, 2, 2, 64, 1, 4, 1, 1, phases
        g.anim = (0, 0, 0, tuple([ms, ms] * phases)) if phases > 1 else None
        tiles = []
        for ph in range(phases):
            for d in range(4):
                t = tiles_of(m['placed'][(key, d)][ph], 2, 2)
                for hh in range(2):
                    for ww in range(2):
                        tiles.append(t[(ww, hh)])
        g.sprites = tuple(range(len(tiles)))
        out.append((g, tiles))
    return out


def measured(src, want=ROWS, first=FIRST_NEW):
    """[(row dict, measure)] of the rows of `want` (src, kind, tint) from the pack files, ids from `first`"""
    by = {c.id: c for c in discover(src)}
    out = []
    for i, (cid, kind, tint) in enumerate(want):
        if cid not in by:
            raise SystemExit('no creature %s under %s' % (cid, src))
        try:
            m = measure(by[cid], tint)
        except ValueError as e:
            raise SystemExit('creature %s: %s' % (cid, e))
        r = {'src': cid, 'new': str(first + i), 'kind': kind, 'size': '2x2', 'scale': m['scale'], 'idle': str(m['idle']),
             'idle_ms': str(m['idle_ms']), 'walk': str(m['walk']), 'walk_ms': str(m['walk_ms']), 'walk_src': by[cid].walk_src,
             'tint': tint, 'colours': str(m['colours'])}
        out.append((r, m))
    return out


def table_text(rs):
    return ','.join(HEADER) + '\n' + ''.join(','.join(r[k] for k in HEADER) + '\n' for r in rs)


def sums_text(sums):
    return ('# sha256 of each outfit (shapes, animator, every sprite slot) by outfit id, written by gen_creature_outfits.py table --write (O605)\n'
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
    return W.build(dat, spr, out_dir, None, table=[r for r, _m in ms], first=first, log=log, specs_of=lambda r: groups_of(by[r['new']]))


def live(dat, spr, table=None, sums=None, log=print):
    """the pair holds every outfit at its id, its digest the one of the sums file, 2x2, one layer, idle and walk group, no flags"""
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
        if th.flags or [g.gtype for g in gs] != [0, 1] or any(g.layers != 1 or (g.w, g.h) != (2, 2) for g in gs):
            out.append('outfit %d (src %s): not an idle and a walk group of 2x2 with one layer and no flags' % (nid, r['src']))
        elif (gs[0].phases, gs[1].phases) != (int(r['idle']), int(r['walk'])):
            out.append('outfit %d (src %s): %d / %d phases, the table says %s / %s' % (nid, r['src'], gs[0].phases, gs[1].phases, r['idle'], r['walk']))
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
