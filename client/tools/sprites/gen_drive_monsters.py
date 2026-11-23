#!/usr/bin/env python3
"""Eleven hunt monster outfits 3561-3571 of pair 81 (O726; client/MANIFEST.md "Drive characters as hunt monsters (O726)"): nine from our
own PixelLab redraws, two from purchased 8-direction character packs.

    python3 -I gen_drive_monsters.py check                       # the table, the sums keys, the redraw pictures and the monster map (no pair)
    python3 -I gen_drive_monsters.py looks [--check]             # server/data/monster/monster_drive_looks.csv from PICKS
    python3 -I gen_drive_monsters.py redraw-import DIR           # copy the redraw pictures of DIR/<any name>/ into art_import/drive_redraw/<key>/
    python3 -I gen_drive_monsters.py ids --src DIR [--src DIR]   # src id and measures of every pack character under the folders (author's aid)
    python3 -I gen_drive_monsters.py table --src DIR... [--write]  # measure the rows of ROWS, print (or write) the table and the sums
    python3 -I gen_drive_monsters.py sums --src DIR... --check   # the pictures give the committed sums
    python3 -I gen_drive_monsters.py build DAT SPR OUT_DIR --src DIR...
                                                                 # a pair with 3,560 outfits in (pair 80), 11 more out (OUT_DIR must not exist)
    python3 -I gen_drive_monsters.py live DAT SPR                # the pair holds every outfit at its id, as the sums say
    python3 -I gen_drive_monsters.py quality DAT SPR             # sprite_quality.py check --kind creature of every outfit (numbers, a report)
    python3 -I gen_drive_monsters.py preview OUT.mp4 --dat D --spr S   # the looks in game at true size on grass, a PixelLab look beside (never committed)

Owner 2026-11-23 (translated): the new 8-direction characters of the owner's Drive become hunt monsters ("Monstros de hunt"); then: every
one 3x3 to keep the detail, none sheared; then: the nine man-shaped ones are drawn again by us in PixelLab with adult proportions (words
only, our art), the wolf and the crab keep the pack art.

Redraws (art `redraw`). art_import/drive_redraw/<key>/ holds our own pictures, committed like art_import/pixellab_monsters: the standing
picture of each direction (north.png, east.png, south.png, west.png, 96 x 96, hard alpha) and, when drawn, the frames idle/<direction>/
frame_NNN.png and walk/<direction>/frame_NNN.png. `redraw-import DIR` copies them from a drop folder DIR/<name>/ (the same layout; the
name is not read): the row is the one whose src is the first 12 hex digits of the sha256 of <name>/south.png. A redraw without idle frames
stands still (idle 1 phase, its standing pictures; server/data/monster/no_idle_allow.csv has a TEMPORARY row for its monster), one without
walk frames walks on its standing pictures (walk 1 phase, walk_src `still`). Frames dropped later are picked up by `redraw-import`, then
`table --write` and `build`: no other change. No tone and no scale: the pictures are drawn at game size (scale 1.00).
A key of EAST_FROM_WEST walks east on its walk west mirrored (column east `mirror`): `facing` measures which standing picture each
frame is nearest to, and the drawn walk east of that redraw had frames nearer the front or the back.

Packs (art `pack`). docs/CREDITS.md names them. Their licences allow use inside the finished game and forbid sharing the files on their
own, so no pack picture is committed, as in O540 / O608: committed are the table rows and the sums. The pack files are read locally by
this script only: never viewed, never sent to a web or AI service. `--src DIR` (repeatable) holds the unpacked packs in any layout. A
character is a folder with an animation folder named exactly "idle" (any case) that has the four folders north, east, south, west of PNG
frames. Its walk is the sibling folder named walk, else running, run or move; a character without one walks on its idle frames (walk_src
idle). A walk without a west folder walks west on its east frames mirrored (west column `mirror`). Attack, jump, flying and death frames
are not read. src: the first 12 hex digits of the sha256 of its first south idle frame file, so no pack name is in the repository; two
folders with one src id are one character.

Canvas. The frames of one character are put on one square canvas, the largest of its frames: centred across, standing on the bottom.

Size. Every outfit is 3x3 (TILES). Scale s in hundredths, the largest of at most 1.00 (no frame is enlarged) for which every frame fits
a 3x3 outfit at the standing point (fit3, gen_pixellab_monsters.fit on 3 tiles), tried down from 96 px over the longer side of the box of
every frame. The filter keeps the hard alpha and the palette: an output pixel covers a block of source pixels (1 or more a side, counted
from the bottom row); it is opaque when at least half of them are, and takes the colour most of its opaque pixels have (the first such in
the block on a tie). No colour is made that is not in the source. Nothing is sheared or leaned.

Frames. Idle: as many phases as the longest idle direction has frames, at most 8, at least 4 (1 for a redraw with none); walk: 8 phases
(1 for a redraw with none). A direction with n frames shows frame floor(i * n / P) at phase i (gen_creature_outfits.pick). Durations like
the O640 outfits: idle 300 ms a phase up to 4 phases, 200 ms up to 8; walk 100 ms; a 1-phase group has none (0 in the table).

Place. The O585 / O640 standing point (gen_pixellab_monsters.fit): the median feet of the four idle directions on x 16.5, y 21 of the
tile (3x3), one whole pixel shift for every frame, the dat displacement as the only flag; a floating thing (FLOAT) is centred on its box
with its lowest pixel on row 29.

The outfits go after the 3,560 outfits of pair 80: the row at line n (0-based) is outfit 3561 + n. The append and its checks are
gen_wst_outfits.build (old things byte identical, every slot read back). Needs numpy and Pillow (the fx venv of CI) for everything but
`check` and `looks`; `preview` needs ffmpeg.
"""
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_wst_outfits as W  # noqa: E402
import gen_creature_outfits as G  # noqa: E402
import gen_pixellab_monsters as P  # noqa: E402

ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'drive_monsters.csv')
SUMS = os.path.join(ART, 'drive_monsters.sums')
REPO = W.REPO
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_drive_looks.csv')
MAP_HEADER = ['monster', 'look', 'new_look']
REDRAW = os.path.join(ART, 'drive_redraw')
HEADER = ['key', 'src', 'art', 'new', 'tiles', 'scale', 'disp', 'float', 'idle', 'idle_ms', 'walk', 'walk_ms', 'walk_src', 'west', 'east',
          'idle_frames', 'walk_frames', 'colours', 'pixels']
PAIR = 81
OUTFITS_BEFORE = 3560               # pair 80: pair 79's 3,560 (the six drawn wings 3555-3560 of pair 78), changed in place by O724 / O725b
FIRST_NEW = OUTFITS_BEFORE + 1
DIRS = P.DIRS                       # north, east, south, west (engine order)
SOUTH = P.SOUTH
TILES = 3                           # every outfit 3x3 (owner 2026-11-23: keep the detail, none 2x2)
MIN_IDLE, MAX_IDLE = 4, 8
WALK = 8
WALK_MS = 100
MAX_ON_LOOK = 1                     # one hunt monster on each new look (O529)
WALK_NAMES = ('walk', 'running', 'run', 'move')

# (src, key, art) in outfit order; key is our own word for the figure, never a pack name; art `redraw` (art_import/drive_redraw/<key>,
# src of its south.png) or `pack` (src of its first south idle frame). FLOAT: keys of things with no feet.
ROWS = (
    ('e86cc8933b0f', 'seraph', 'redraw'),
    ('f838b8411d2d', 'relicbearer', 'redraw'),
    ('19e703a3576d', 'aberration', 'redraw'),
    ('a131cf8f2824', 'wolf', 'pack'),
    ('162d4e858320', 'voidmage', 'redraw'),
    ('435a175bc234', 'plaguemedic', 'redraw'),
    ('83e9ddc20794', 'seacaptain', 'redraw'),
    ('35ecd304f399', 'templar', 'redraw'),
    ('3973b8038abc', 'stormmage', 'redraw'),
    ('8e37a4728f97', 'voidpriest', 'redraw'),
    ('f49d946fb82c', 'crab', 'pack'),
)
FLOAT = ('aberration',)
# keys whose walk east is their walk west mirrored (column east `mirror`): a frame of the drawn walk east is nearer the south or north
# standing picture than the east one (the colour distance of `facing`), the mirrored west walk is not
EAST_FROM_WEST = ('seacaptain',)
STANDING = ('north.png', 'east.png', 'south.png', 'west.png')    # a redraw's standing picture per direction, engine order
# key -> the hunt monster that wears the look (O726 picks: theme and level band, from looks that are crowded or shared today, no boss)
PICKS = (
    ('seraph', "Paladin's Apparition"),
    ('relicbearer', 'Guardian of Tales'),
    ('aberration', 'Terrordream'),
    ('wolf', 'Scourgejaw'),
    ('voidmage', 'Dark Magician'),
    ('plaguemedic', 'Mad Scientist'),
    ('seacaptain', 'Ironhook Corsair'),
    ('templar', "Knight's Apparition"),
    ('stormmage', 'Dark Apprentice'),
    ('voidpriest', 'Death Priest'),
    ('crab', 'Saltkin Pincher'),
)


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_sums(path=SUMS):
    return W.read_sums(path)


def idle_ms_for(phases):
    return P.idle_ms_for(phases)


def problems(table=None, sums=None, first=FIRST_NEW, want=ROWS):
    """What is wrong with the table: its rows are ROWS in order, ids from the first new outfit, sizes, displacement, phases, durations,
    scale, and the sums name the same outfits."""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out = []
    if want is not None and [(r['src'], r['key'], r['art']) for r in t] != [tuple(x) for x in want]:
        out.append('the rows are not ROWS of gen_drive_monsters.py, in its order')
    seen = set()
    for i, r in enumerate(t):
        k = r['key']
        if k in seen or not re.fullmatch(r'[a-z]+', k):
            out.append('%s: a key twice or not a lower-case word' % k)
        seen.add(k)
        if not re.fullmatch(r'[0-9a-f]{12}', r['src']):
            out.append('%s: src %s is not 12 hex digits' % (k, r['src']))
        if int(r['new']) != first + i:
            out.append('%s: new id %s, the row at line %d must be %d' % (k, r['new'], i, first + i))
        n = P.tiles_of_text(r['tiles'])
        if n != TILES:
            out.append('%s: size %s, every outfit of O726 is %dx%d' % (k, r['tiles'], TILES, TILES))
        d = P.disp_of_text(r['disp'])
        if d is None or d[0] > 0 or abs(d[0]) > 64 or abs(d[1]) > 64:
            out.append('%s: displacement %s, a negative x and |y| of 64 at most are wanted' % (k, r['disp']))
        if not re.fullmatch(r'(0\.\d\d|1\.00)', r['scale']) or float(r['scale']) < 0.2:
            out.append('%s: scale %s is not a number of hundredths from 0.20 to 1.00' % (k, r['scale']))
        red = r['art'] == 'redraw'
        if r['art'] not in ('redraw', 'pack'):
            out.append('%s: art %s, redraw or pack' % (k, r['art']))
        if red and r['scale'] != '1.00':
            out.append('%s: scale %s, a redraw is drawn at game size (1.00)' % (k, r['scale']))
        if r['float'] != ('1' if k in FLOAT else '0'):
            out.append('%s: float %s, FLOAT says %s' % (k, r['float'], k in FLOAT))
        still_idle = red and (r['idle'], r['idle_ms']) == ('1', '0')
        if not still_idle and (not MIN_IDLE <= int(r['idle']) <= MAX_IDLE or int(r['idle_ms']) != idle_ms_for(int(r['idle']))):
            out.append('%s: %s idle phases of %s ms (1 of 0 only for a redraw without idle frames)' % (k, r['idle'], r['idle_ms']))
        still_walk = red and (r['walk'], r['walk_ms'], r['walk_src']) == ('1', '0', 'still')
        if not still_walk and (int(r['walk']) != WALK or int(r['walk_ms']) != WALK_MS or r['walk_src'] == 'still'):
            out.append('%s: the walk is %d phases of %d ms (row: %s of %s; 1 of 0, still, only for a redraw without walk frames)'
                       % (k, WALK, WALK_MS, r['walk'], r['walk_ms']))
        if r.get('east') != ('mirror' if k in EAST_FROM_WEST else 'own'):
            out.append('%s: east %s, EAST_FROM_WEST says %s' % (k, r.get('east'), k in EAST_FROM_WEST))
        if r['walk_src'] not in ('walk', 'idle', 'still') or r['west'] not in ('own', 'mirror'):
            out.append('%s: walk_src %s, west %s' % (k, r['walk_src'], r['west']))
        if not (r['pixels'] or '').isdigit() or int(r['pixels']) < 1:
            out.append('%s: pixels %s' % (k, r['pixels']))
    if want is ROWS:
        out += redraw_problems(t)
    if set(s) != {r['new'] for r in t}:
        out.append('drive_monsters.sums and the table name other outfits (%s)' % ', '.join(sorted(set(s) ^ {r['new'] for r in t})))
    return out


def redraw_problems(table, root=None):
    """every redraw row has its four standing pictures in art_import/drive_redraw/<key>/, its src is the one of south.png, and no folder
    there belongs to no row"""
    root = REDRAW if root is None else root
    out = []
    keys = set()
    for r in table:
        if r['art'] != 'redraw':
            continue
        keys.add(r['key'])
        d = os.path.join(root, r['key'])
        miss = [f for f in STANDING if not os.path.isfile(os.path.join(d, f))]
        if miss:
            out.append('%s: art_import/drive_redraw/%s has no %s' % (r['key'], r['key'], ', '.join(miss)))
        elif W._sha12(os.path.join(d, 'south.png')) != r['src']:
            out.append('%s: src %s, south.png gives %s' % (r['key'], r['src'], W._sha12(os.path.join(d, 'south.png'))))
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            if name not in keys:
                out.append('art_import/drive_redraw/%s belongs to no redraw row' % name)
    return out


# ---------------------------------------------------------------- the monsters (the server map)

def map_rows(table=None, picks=PICKS, old=None):
    t = rows() if table is None else table
    have = G.old_looks() if old is None else old
    by = {r['key']: int(r['new']) for r in t}
    return [(m, have[m], by[k]) for k, m in picks]


def map_text(rows_):
    return ','.join(MAP_HEADER) + '\n' + ''.join('%s,%d,%d\n' % r for r in rows_)


def map_problems(table=None, picks=PICKS, old=None, levels=None):
    """PICKS against the table and the pool: every row key once, every outfit worn by exactly one monster, each monster once, known (a file
    of ours or a row of the pool) and a hunt monster of the committed bounty pool (its hunt list: no boss)."""
    t = rows() if table is None else table
    have = G.old_looks() if old is None else old
    lv = P.pool_levels() if levels is None else levels
    keys = [r['key'] for r in t]
    out, seen = [], set()
    used = {}
    for k, m in picks:
        if k not in keys:
            out.append('%s: key %s is no row of drive_monsters.csv' % (m, k))
        used[k] = used.get(k, 0) + 1
        if used[k] > MAX_ON_LOOK:
            out.append('the look of %s is on more than %d monster: no two hunt monsters share a look (O529)' % (k, MAX_ON_LOOK))
        if m in seen:
            out.append('%s is picked twice' % m)
        seen.add(m)
        if m not in have:
            out.append('%s has no monster file of ours and no row of the bounty pool' % m)
        if m not in lv:
            out.append('%s is not a hunt monster of the bounty pool (a look of O726 goes to a hunt monster)' % m)
    for k in keys:
        if k not in used:
            out.append('the outfit of %s is worn by no monster of PICKS' % k)
    return out


def write_map(check=False):
    """write monster_drive_looks.csv, or with check compare it; returns the problem lines"""
    try:
        text = map_text(map_rows())
    except KeyError:
        return []   # map_problems names it
    old = open(MAP, encoding='utf-8', newline='').read() if os.path.exists(MAP) else None
    if old == text:
        return []
    if check:
        return ['server/data/monster/monster_drive_looks.csv is not up to date (run gen_drive_monsters.py looks)']
    with open(MAP, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return []


# ---------------------------------------------------------------- the pack files

class Character:
    """one character: id, the frame files {('idle' | 'walk', direction 0..3 n e s w): [paths]}, walk_src, west ('own' | 'mirror')"""

    def __init__(self, cid, files, walk_src, west, still_idle=False):
        self.id, self.files, self.walk_src, self.west, self.still_idle = cid, files, walk_src, west, still_idle


def _pngs(path):
    return sorted(os.path.join(path, f) for f in os.listdir(path) if f.lower().endswith('.png')) if os.path.isdir(path) else []


def _anim(path, need_west=True):
    """{direction: [files]} of an animation folder; None when north, east or south is missing (or west, with need_west)"""
    out = {d: _pngs(os.path.join(path, name)) for d, name in enumerate(DIRS)}
    if not (out[0] and out[1] and out[2]) or (need_west and not out[3]):
        return None
    return out


def discover(srcs):
    """[Character] of every character under the folders (read only), sorted by id; a src id met twice is read once"""
    found = {}
    for src in srcs:
        for root, dirs, _files in sorted(os.walk(src)):
            dirs.sort()
            idle = [d for d in dirs if d.lower() == 'idle' and _anim(os.path.join(root, d))]
            if not idle:
                continue
            ia = _anim(os.path.join(root, idle[0]))
            walk = None
            for word in WALK_NAMES:
                names = [d for d in dirs if d.lower() == word and _anim(os.path.join(root, d), need_west=False)]
                if names:
                    walk = _anim(os.path.join(root, names[0]), need_west=False)
                    break
            files = {('idle', d): ia[d] for d in range(4)}
            files.update({('walk', d): (walk or ia)[d] for d in range(4)})
            west = 'own'
            if not files[('walk', 3)]:
                files[('walk', 3)] = files[('walk', 1)]
                west = 'mirror'
            cid = W._sha12(ia[SOUTH][0])
            if cid not in found:
                found[cid] = Character(cid, files, 'walk' if walk else 'idle', west)
    return [found[k] for k in sorted(found)]


def redraw_character(folder):
    """the Character of a redraw folder (STANDING pictures, optional idle/ and walk/ frames), None without the four standing pictures"""
    stand = [os.path.join(folder, f) for f in STANDING]
    if not all(os.path.isfile(f) for f in stand):
        return None
    ia = _anim(os.path.join(folder, 'idle'))
    wa = _anim(os.path.join(folder, 'walk'), need_west=False)
    files = {('idle', d): (ia[d] if ia else [stand[d]]) for d in range(4)}
    files.update({('walk', d): (wa[d] if wa else [stand[d]]) for d in range(4)})
    west = 'own'
    if wa and not wa[3]:
        files[('walk', 3)] = files[('walk', 1)]
        west = 'mirror'
    return Character(W._sha12(stand[SOUTH]), files, 'walk' if wa else 'still', west, still_idle=not ia)


def discover_redraws(root=None):
    """[Character] of every folder of art_import/drive_redraw (or `root`) with its four standing pictures"""
    root = REDRAW if root is None else root
    out = []
    for name in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        c = redraw_character(os.path.join(root, name))
        if c:
            out.append(c)
    return out


def redraw_import(drop, root=None, want=ROWS, log=print):
    """copy the redraw pictures of drop/<any name>/ (STANDING, idle/<dir>/*.png, walk/<dir>/*.png) into root/<key>/, the key the row whose
    src is the one of <name>/south.png, or, when the file was written again, whose committed south.png has the same pixels (then the
    committed standing pictures stay where their pixels are the same, so src holds). A picture must be a 96 x 96 PNG with hard alpha.
    Returns the keys written."""
    import numpy as np
    from PIL import Image

    def px(path):
        return np.array(Image.open(path).convert('RGBA'))
    root = REDRAW if root is None else root
    by = {cid: key for cid, key, art in want if art == 'redraw'}
    done = []
    for name in sorted(os.listdir(drop)):
        src = os.path.join(drop, name)
        if not os.path.isfile(os.path.join(src, 'south.png')):
            continue
        key = by.get(W._sha12(os.path.join(src, 'south.png')))
        if key is None:
            south = px(os.path.join(src, 'south.png'))
            for k in by.values():
                c = os.path.join(root, k, 'south.png')
                if os.path.isfile(c) and np.array_equal(px(c), south):
                    key = k
                    break
        if key is None:
            log('skipped %s: its south.png is no redraw row of ROWS' % name)
            continue
        dst0 = os.path.join(root, key)
        files = [f for f in STANDING if not (os.path.isfile(os.path.join(dst0, f))
                                             and np.array_equal(px(os.path.join(dst0, f)), px(os.path.join(src, f))))]
        for anim in ('idle', 'walk'):
            for d in DIRS:
                files += [os.path.relpath(f, src) for f in _pngs(os.path.join(src, anim, d))]
        for f in files:
            a = np.array(Image.open(os.path.join(src, f)).convert('RGBA'))
            al = a[..., 3]
            if a.shape != (96, 96, 4) or al[(al != 0) & (al != 255)].size:
                raise SystemExit('refused %s/%s: a redraw picture is 96 x 96 with hard alpha' % (name, f))
        dst = os.path.join(root, key)
        for anim in ('idle', 'walk'):
            shutil.rmtree(os.path.join(dst, anim), ignore_errors=True)
        for f in files:
            os.makedirs(os.path.dirname(os.path.join(dst, f)), exist_ok=True)
            shutil.copyfile(os.path.join(src, f), os.path.join(dst, f))
        log('%s: %d pictures into art_import/drive_redraw/%s' % (name, len(files), key))
        done.append(key)
    return done


def facing(frames_dir, standing):
    """{(group, direction): [the standing direction nearest each frame]} of a redraw folder's frames: the mean colour distance over the
    union of the two figures (a clear pixel against an opaque one counts 255); the measure EAST_FROM_WEST is chosen by"""
    import numpy as np
    from PIL import Image

    def ld(f):
        return np.array(Image.open(f).convert('RGBA')).astype(float)

    def dist(a, b):
        ma, mb = a[..., 3] > 0, b[..., 3] > 0
        d = np.where(ma & mb, np.abs(a[..., :3] - b[..., :3]).mean(axis=2), 255.0)
        return float(d[ma | mb].mean()) if (ma | mb).any() else 0.0
    st = {d: ld(os.path.join(standing, f)) for d, f in zip(DIRS, STANDING)}
    out = {}
    for g in ('idle', 'walk'):
        for d in DIRS:
            for f in _pngs(os.path.join(frames_dir, g, d)):
                a = ld(f)
                out.setdefault((g, d), []).append(min(DIRS, key=lambda x: dist(a, st[x])))
    return out


def load(ch):
    """{(group, direction): [arrays]} of a character, alpha cut, every frame on one square canvas (centred across, on the bottom),
    the west walk mirrored from the east one when the pack has none"""
    import numpy as np
    from PIL import Image
    raw = {k: [G.cut(np.array(Image.open(f).convert('RGBA'))) for f in fs] for k, fs in ch.files.items()}
    side = max(max(a.shape[0], a.shape[1]) for lst in raw.values() for a in lst)
    out = {}
    for k, lst in raw.items():
        res = []
        for a in lst:
            c = np.zeros((side, side, 4), np.uint8)
            h, w = a.shape[:2]
            ox, oy = (side - w) // 2, side - h
            c[oy:oy + h, ox:ox + w] = a
            res.append(c)
        out[k] = res
    if ch.west == 'mirror':
        out[('walk', 3)] = [np.ascontiguousarray(a[:, ::-1]) for a in out[('walk', 1)]]
    return out


def box_of(lst):
    import numpy as np
    x0 = y0 = 10 ** 6
    x1 = y1 = -1
    for a in lst:
        ys, xs = np.nonzero(a[..., 3])
        if len(xs):
            x0, x1, y0, y1 = min(x0, int(xs.min())), max(x1, int(xs.max())), min(y0, int(ys.min())), max(y1, int(ys.max()))
    return x0, y0, x1, y1


def resize_idx(n, s):
    """[(start, end)] of the source pixels of every output pixel along one axis of n source pixels at scale s (0 < s <= 1), counted from
    the far end (the bottom row, the right column), so the last source row stays the last output row"""
    import math
    m = int(math.ceil(n * s - 1e-9))
    out = []
    for r in range(m):
        a, b = int(math.floor(r / s + 1e-9)), min(n, int(math.floor((r + 1) / s + 1e-9)))
        out.append((n - max(b, a + 1), n - a))
    return out[::-1]


def resize(a, s):
    """a at scale s (0 < s <= 1) by blocks: an output pixel covers the source pixels of resize_idx (1 or more a side); it is opaque when
    at least half of them are, and takes the colour most of its opaque pixels have (the first of them in the block when two tie). Hard
    alpha in, hard alpha out, no new colour. At 1 the picture is kept (no colour under a clear pixel)."""
    import numpy as np
    if s >= 1:
        return np.where(a[..., 3:4] > 0, a, 0).astype(np.uint8)
    ys, xs = resize_idx(a.shape[0], s), resize_idx(a.shape[1], s)
    m = max(max(b - x for x, b in ys), max(b - x for x, b in xs))

    def grid(idx):
        g = np.zeros((len(idx), m), np.int64)
        v = np.zeros((len(idx), m), bool)
        for i, (x, b) in enumerate(idx):
            g[i, :b - x] = np.arange(x, b)
            v[i, :b - x] = True
        return g, v
    gy, vy = grid(ys)
    gx, vx = grid(xs)
    blk = a[gy[:, None, :, None], gx[None, :, None, :]]                     # H', W', m, m, 4
    valid = vy[:, None, :, None] & vx[None, :, None, :]
    h2, w2 = blk.shape[:2]
    blk = blk.reshape(h2, w2, m * m, 4)
    valid = valid.reshape(h2, w2, m * m)
    op = (blk[..., 3] > 0) & valid
    key = (blk[..., 0].astype(np.uint32) << 16) | (blk[..., 1].astype(np.uint32) << 8) | blk[..., 2].astype(np.uint32)
    cnt = np.zeros(op.shape, np.int32)
    for j in range(m * m):
        cnt += ((key == key[..., j:j + 1]) & op[..., j:j + 1]).astype(np.int32)
    cnt[~op] = -1
    best = np.argmax(cnt, axis=2)
    pick = np.take_along_axis(blk, best[..., None, None], axis=2)[:, :, 0]
    out = np.zeros((h2, w2, 4), np.uint8)
    on = op.sum(axis=2) * 2 >= valid.sum(axis=2)
    out[on] = pick[on]
    out[on, 3] = 255
    return out


def shrink(a, k):
    """a / k (resize at 1 / k: k x k blocks)"""
    return resize(a, 1.0 / k)


def fit3(frames, floating):
    """gen_pixellab_monsters.fit on a 3x3 canvas only: (3, (dx, dy), (shift x, shift y)); ValueError when the figure does not fit"""
    import math
    n, c = TILES, 32 * TILES
    x0, y0, x1, y1 = P.union_box(frames)
    sx, sy = P.stand_of(frames, floating)
    if x1 - x0 + 1 > c or y1 - y0 + 1 > c:
        raise ValueError('a figure of %dx%d px is over %d px' % (x1 - x0 + 1, y1 - y0 + 1, c))
    ty = P.FLOAT_LOW if floating else min(P.TY[n], 31 + P.HANG - (y1 - sy))
    for dx in P.near(-(16 * n - 16)):
        shx = int(math.floor(c - 32 + dx + P.TX - sx + 0.5))
        if x0 + shx >= 0 and x1 + shx <= c - 1:
            break
    else:
        raise ValueError('no displacement x holds the figure')
    for dy in P.near(0):
        shy = int(math.floor(c - 32 + dy + ty - sy + 0.5))
        if y0 + shy >= 0 and y1 + shy <= c - 1:
            break
    else:
        raise ValueError('no displacement y holds the figure')
    return n, (dx, dy), (shx, shy)


def scale_start(frames):
    """the first scale tried: 96 px over the longer side of the box of every frame, in hundredths, at most 1 (no frame is enlarged)"""
    x0, y0, x1, y1 = box_of([a for lst in frames.values() for a in lst])
    return min(100, int(100.0 * 32 * TILES / max(x1 - x0 + 1, y1 - y0 + 1))) / 100.0


def resample(frames, idle_p, walk_p=WALK):
    """the frames shown in the phases: idle `idle_p` phases, walk `walk_p`, evenly spaced per direction (gen_creature_outfits.pick)"""
    out = {}
    for (g, d), lst in frames.items():
        ph = idle_p if g == 'idle' else walk_p
        out[(g, d)] = [lst[i] for i in G.pick(len(lst), ph)]
    return out


def colours(frames):
    import numpy as np
    cs = set()
    for lst in frames.values():
        for a in lst:
            cs |= set(map(tuple, a[a[..., 3] > 0][:, :3].tolist()))
    return len(cs)


def measure(ch, key, new, art='pack'):
    import numpy as np
    """(table row, placed frames {(group, direction): [canvas arrays]}) of a character"""
    full = load(ch)
    if key in EAST_FROM_WEST:
        full[('walk', 1)] = [np.ascontiguousarray(a[:, ::-1]) for a in full[('walk', 3)]]
    counts = {k: len(v) for k, v in full.items()}
    idle_p = 1 if ch.still_idle else max(MIN_IDLE, min(MAX_IDLE, max(counts[('idle', d)] for d in range(4))))
    walk_p = 1 if ch.walk_src == 'still' else WALK
    sel = resample(full, idle_p, walk_p)
    fl = key in FLOAT
    hund = int(round(scale_start(sel) * 100))
    while True:
        if hund < 20:
            raise ValueError('no scale of 0.20 or more fits a 3x3 outfit')
        frames = {kk: [resize(a, hund / 100.0) for a in lst] for kk, lst in sel.items()}
        if any(not a[..., 3].any() for lst in frames.values() for a in lst):
            raise ValueError('an empty frame after the scale')
        try:
            n, disp, shift = fit3(frames, fl)
            break
        except ValueError:
            hund -= 1
    placed = P.place_checked(frames, n, shift)
    r = {'key': key, 'src': ch.id, 'art': art, 'new': str(new), 'tiles': '%dx%d' % (n, n), 'scale': '%.2f' % (hund / 100.0),
         'disp': '%d:%d' % disp, 'float': '1' if fl else '0', 'idle': str(idle_p), 'idle_ms': str(idle_ms_for(idle_p) if idle_p > 1 else 0),
         'walk': str(walk_p), 'walk_ms': str(WALK_MS if walk_p > 1 else 0),
         'walk_src': ch.walk_src, 'west': ch.west, 'east': 'mirror' if key in EAST_FROM_WEST else 'own',
         'idle_frames': '/'.join(str(counts[('idle', d)]) for d in range(4)),
         'walk_frames': '/'.join(str(counts[('walk', d)]) for d in range(4)),
         'colours': str(colours(placed)), 'pixels': str(sum(P.opaque(a) for lst in placed.values() for a in lst))}
    return r, placed


STILL_RULES = ('an idle direction shows one picture', 'a walk direction shows')


def frame_problems(r, placed):
    """the rules of the built frames (gen_pixellab_monsters.sheet_problems: hard alpha, four directions of their own, an idle that moves,
    a walk of 4 or more pictures, the standing point); a 1-phase idle or walk of a redraw is let through those two motion rules only
    (the idle gap is a TEMPORARY row of no_idle_allow.csv, held by check_content.py)"""
    out = P.sheet_problems(r, placed)
    if r.get('art') == 'redraw':
        skip = [STILL_RULES[0]] * (r['idle'] == '1') + [STILL_RULES[1]] * (r['walk'] == '1')
        out = [x for x in out if not any(s in x for s in skip)]
    return out


def outfit_of(r, placed):
    return {'tiles': P.tiles_of_text(r['tiles']), 'idle': int(r['idle']), 'walk': int(r['walk']), 'idle_ms': int(r['idle_ms']),
            'walk_ms': int(r['walk_ms']), 'placed': placed}


def groups_of(r, placed):
    return G.groups_of(outfit_of(r, placed))


def measured(srcs, want=ROWS, first=FIRST_NEW, redraw=None):
    """[(row, placed)] of the rows of `want` (src, key, art) from the pack files under `srcs` and the redraw folders, ids from `first`"""
    packs = {c.id: c for c in discover(srcs)} if any(a == 'pack' for _c, _k, a in want) else {}
    reds = {c.id: c for c in discover_redraws(redraw)}
    out = []
    for i, (cid, key, art) in enumerate(want):
        by = reds if art == 'redraw' else packs
        if cid not in by:
            raise SystemExit('no %s character %s (%s) under %s' % (art, cid, key, 'art_import/drive_redraw' if art == 'redraw'
                                                                   else ', '.join(srcs) or 'no --src'))
        try:
            r, placed = measure(by[cid], key, first + i, art)
        except ValueError as e:
            raise SystemExit('character %s (%s): %s' % (cid, key, e))
        bad = frame_problems(r, placed)
        if bad:
            raise SystemExit('character %s (%s): %s' % (cid, key, '; '.join(bad[:5])))
        out.append((r, placed))
    return out


def table_text(rs):
    return ','.join(HEADER) + '\n' + ''.join(','.join(r[k] for k in HEADER) + '\n' for r in rs)


def sums_text(sums):
    return ('# sha256 of each outfit (shapes, animator, every sprite slot) by outfit id, written by gen_drive_monsters.py table --write (O726)\n'
            + ''.join('%s %s\n' % (k, sums[k]) for k in sorted(sums, key=int)))


def pack_sums(ms):
    return {r['new']: W.spec_digest(groups_of(r, placed)) for r, placed in ms}


# ---------------------------------------------------------------- the pair

def pair_ok(n_outfits, first=FIRST_NEW):
    if n_outfits == first - 1:
        return None
    return 'the input pair has %d outfits, this step needs %d (pair 80)' % (n_outfits, first - 1)


def build(dat, spr, out_dir, srcs, want=ROWS, first=FIRST_NEW, log=print, redraw=None):
    """pair in (its outfits end at first - 1) -> pair out in OUT_DIR: one new outfit per row. Returns the new ids."""
    sys.path.insert(0, HERE)
    from datspr import Dat
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    why = pair_ok(len(Dat(dat).outfits), first)
    if why:
        raise SystemExit('refused: ' + why)
    ms = measured(srcs, want, first, redraw)
    by = {r['new']: (r, placed) for r, placed in ms}
    return W.build(dat, spr, out_dir, None, table=[r for r, _p in ms], first=first, log=log,
                   specs_of=lambda r: groups_of(*by[r['new']]), flags_of=P.flags_of)


def live(dat, spr, table=None, sums=None, first=FIRST_NEW, log=print):
    """the pair holds every outfit at its id: gen_pixellab_monsters.live (no sheets: the sums, the shape, the durations, the pixel count and
    the standing point) for the outfits that move, the same checks with a 1-phase group and no animator for a still redraw. Returns the
    problem lines."""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_outfits import parse_body
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    moving = [r for r in t if r['idle'] != '1' and r['walk'] != '1']
    still = [r for r in t if r not in moving]
    out = []
    if moving:
        out += P.live(dat, spr, table=moving, sums=s, first=first, root=os.path.join(tempfile.gettempdir(), 'no-sheets-o726'),
                      log=lambda *_: None)
    if still:
        d, sp = Dat(dat), Spr(spr)
        if len(d.outfits) < max(int(r['new']) for r in still):
            return out + ['the pair has %d outfits, the drive looks end at %s' % (len(d.outfits), t[-1]['new'])]
        for r in still:
            nid, k, n = int(r['new']), r['key'], P.tiles_of_text(r['tiles'])
            th = d.outfit(nid)
            if dict(th.flags) != P.flags_of(r)[1]:
                out.append('outfit %d (%s): flags %s, the displacement %s only' % (nid, k, dict(th.flags), r['disp']))
                continue
            gs = parse_body(d, th)
            if [g.gtype for g in gs] != [0, 1] or any(g.layers != 1 or (g.w, g.h) != (n, n) for g in gs):
                out.append('outfit %d (%s): not an idle and a walk group of %s with one layer' % (nid, k, r['tiles']))
                continue
            if (gs[0].phases, gs[1].phases) != (int(r['idle']), int(r['walk'])):
                out.append('outfit %d (%s): %d / %d phases, the table says %s / %s' % (nid, k, gs[0].phases, gs[1].phases, r['idle'], r['walk']))
                continue
            for g, key in zip(gs, ('idle', 'walk')):
                ms = int(r[key + '_ms'])
                want_anim = None if g.phases == 1 else (ms, ms) * g.phases
                if (tuple(g.anim[3]) if g.anim else None) != want_anim:
                    out.append('outfit %d (%s): the %s group is not %s' % (nid, k, key, 'still' if g.phases == 1 else '%d ms a phase' % ms))
            frames, gs = P.outfit_frames(d, sp, nid, n, gs)
            if W.digest(d, sp, nid) != s.get(r['new']):
                out.append('outfit %d (%s): the pictures are not the ones of drive_monsters.sums' % (nid, k))
            total = sum(P.opaque(a) for lst in frames.values() for a in lst)
            if total != int(r['pixels']):
                out.append('outfit %d (%s): %d opaque pixels in its sprites, the table counts %s' % (nid, k, total, r['pixels']))
            m = P.measure_cells(r, frames)
            if abs(m['stand'][0] - P.TX) > P.STAND_TOL or abs(m['stand'][1] - m['want_y']) > P.STAND_TOL:
                out.append('outfit %d (%s): stands on tile point (%.1f, %.1f), the rule is (%.1f, %.1f)'
                           % (nid, k, m['stand'][0], m['stand'][1], P.TX, m['want_y']))
            if r['float'] == '0' and m['hang'] > P.HANG:
                out.append('outfit %d (%s): the lowest pixel hangs %d rows under the tile' % (nid, k, m['hang']))
    log('live: %d outfits %s to %s checked (%d still), %d problems' % (len(t), t[0]['new'], t[-1]['new'], len(still), len(out)))
    return out


def quality(dat, spr, table=None):
    """sprite_quality.py check --kind creature of every outfit of the table; [(key, exit code, report text)]"""
    t = rows() if table is None else table
    out = []
    for r in t:
        p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'sprite_quality.py'), 'check', '--kind', 'creature', '--dat', dat,
                            '--spr', spr, '--outfit', r['new']], capture_output=True, text=True)
        out.append((r['key'], p.returncode, p.stdout + p.stderr))
    return out


# ---------------------------------------------------------------- the preview (never committed)

SCALE_LOOK = 3545                   # a PixelLab 3x3 hunt monster (O640) shown next to the new looks for scale


def preview(out_mp4, dat_path, spr_path, table=None, log=print, with_look=SCALE_LOOK):
    """OUT.mp4: the looks from the built pair as the client draws them, at their true size, each on its tile of a grass ground (dat item
    4526), the displacement applied as the client does, one row a direction (north, east, south, west), idle for 5 s then walking 5 s;
    `with_look` (a PixelLab 3x3 outfit of the same pair) stands last for scale. ffmpeg -vf scale=-2:720 (nearest) -crf 30 -an"""
    sys.path.insert(0, HERE)
    from PIL import Image, ImageDraw, ImageFont
    from datspr import Dat, Spr, render_thing
    t = rows() if table is None else table
    d, sp = Dat(dat_path), Spr(spr_path)
    tmp = tempfile.mkdtemp(prefix='o726prev')
    font = ImageFont.load_default(size=11)
    ground = render_thing(d.items[4526 - 100], sp).convert('RGB')
    looks = [(r['new'], r['key'], r) for r in t]
    if with_look:
        pr = {x['new']: x for x in P.rows()}[str(with_look)]
        looks.append((pr['new'], 'pixellab', pr))
    data = []
    for nid, key, r in looks:
        n = P.tiles_of_text(r['tiles'])
        frames, _gs = P.outfit_frames(d, sp, int(nid), n)
        data.append((nid, key, r, n, P.disp_of_text(r['disp']), frames))
    fps, cell, X0, LAB = 20, 128, 64, 22
    W_, H_ = X0 + cell * len(data), LAB + cell * 4
    W_ += W_ % 2
    H_ += H_ % 2
    count = 0
    for tt in range(fps * 10):
        ms = tt * 1000 // fps
        kind = 'idle' if ms < 5000 else 'walk'
        im = Image.new('RGB', (W_, H_), (24, 24, 28))
        dr = ImageDraw.Draw(im)
        for y in range(LAB, H_ - 31, 32):
            for x in range(X0, W_ - 31, 32):
                im.paste(ground, (x, y))
        for c, (nid, key, r, n, disp, frames) in enumerate(data):
            dr.text((X0 + c * cell + 2, 5), '%s %s' % (nid, key), font=font, fill=(235, 235, 235))
        for row, dd in enumerate((0, 1, SOUTH, 3)):
            dr.text((4, LAB + row * cell + cell // 2 - 6), DIRS[dd], font=font, fill=(200, 200, 210))
            for c, (nid, key, r, n, disp, frames) in enumerate(data):
                lst = frames[(kind, dd)]
                a = lst[(ms // max(1, int(r[kind + '_ms']))) % len(lst)]
                img = Image.fromarray(a, 'RGBA')
                tx, ty = X0 + c * cell + 32, LAB + row * cell + 96          # the creature's tile
                im.paste(img, (tx - (n - 1) * 32 - disp[0], ty - (n - 1) * 32 - disp[1]), img)
        im.save(os.path.join(tmp, 'f%05d.png' % count))
        count += 1
    subprocess.check_call(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(fps), '-i', os.path.join(tmp, 'f%05d.png'),
                           '-vf', 'scale=-2:720:flags=neighbor', '-c:v', 'libx264', '-crf', '30', '-an', '-pix_fmt', 'yuv420p', out_mp4])
    shutil.rmtree(tmp, ignore_errors=True)
    log('preview: %s, %d frames' % (out_mp4, count))
    return out_mp4


# ---------------------------------------------------------------- command line

def srcs_of(a):
    out = []
    while '--src' in a:
        out.append(W.opt(a, '--src'))
    return out


def main(argv):
    a = list(argv)
    cmd = a.pop(0) if a else ''
    if cmd == 'check':
        p = problems() + map_problems() + write_map(check=True)
        for line in p:
            print('PROBLEM', line)
        print('drive_monsters: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if cmd == 'looks':
        p = map_problems() + write_map(check='--check' in a)
        for line in p:
            print('PROBLEM', line)
        print('monster_drive_looks: %d rows, %d problems' % (len(PICKS), len(p)))
        return 1 if p else 0
    if cmd == 'redraw-import' and len(a) == 1:
        keys = redraw_import(a[0])
        print('redraw-import: %d characters' % len(keys))
        return 0
    srcs = srcs_of(a)
    if cmd == 'ids' and srcs:
        for c in discover(srcs):
            f = load(c)
            x0, y0, x1, y1 = box_of([x for lst in f.values() for x in lst])
            print('%s %s walk %s west %s idle %s walk %s box %dx%d start %.2f' % (
                c.id, os.path.dirname(os.path.dirname(os.path.dirname(c.files[('idle', 0)][0])))[-40:], c.walk_src, c.west,
                '/'.join(str(len(c.files[('idle', d)])) for d in range(4)), '/'.join(str(len(c.files[('walk', d)])) for d in range(4)),
                x1 - x0 + 1, y1 - y0 + 1, scale_start(f)))
        return 0
    if cmd == 'table':
        ms = measured(srcs)
        print(table_text([r for r, _p in ms]), end='')
        sums = pack_sums(ms)
        if '--write' in a:
            open(TABLE, 'w', encoding='utf-8', newline='').write(table_text([r for r, _p in ms]))
            open(SUMS, 'w', encoding='utf-8', newline='').write(sums_text(sums))
            print('wrote %s and %s' % (TABLE, SUMS))
        return 0
    if cmd == 'sums':
        got = pack_sums(measured(srcs))
        bad = [k for k in sorted(set(got) | set(read_sums())) if got.get(k) != read_sums().get(k)]
        for k in bad:
            print('PROBLEM outfit %s: the pack files give another outfit than drive_monsters.sums' % k)
        print('sums: %d outfits, %d differ' % (len(got), len(bad)))
        return 1 if bad else 0
    if cmd == 'build' and len(a) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(a[0], a[1], a[2], srcs)
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
    if cmd == 'quality' and len(a) == 2:
        for key, code, text in quality(*a):
            print('==== %s (exit %d)\n%s' % (key, code, text.rstrip()))
        return 0
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
