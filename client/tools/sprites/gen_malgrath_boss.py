#!/usr/bin/env python3
"""Malgrath, the Drowned Crown: one purchased boss pack as an arena boss that always faces the front (O637; joins client pair 74;
client/MANIFEST.md "Malgrath, the Drowned Crown (O637)").

    python3 -I gen_malgrath_boss.py check                      # the table, the sums, the geometry and the ids file (no pair, no pack files)
    python3 -I gen_malgrath_boss.py table --src DIR [--write]  # measure the pack, print (or write) the table and the sums
    python3 -I gen_malgrath_boss.py sums --src DIR             # the pack files give the committed table and sums
    python3 -I gen_malgrath_boss.py ids [--check]              # server/data/lib/chaos_malgrath_fx_ids.lua
    python3 -I gen_malgrath_boss.py build DAT SPR OUT_DIR --src DIR
                                                               # a pair with 3,529 outfits and 5,325 effects in: 1 outfit and 8 effects out
    python3 -I gen_malgrath_boss.py live DAT SPR               # the pair holds the outfit and every effect at its id, as the sums say
    python3 -I gen_malgrath_boss.py preview OUT_DIR --dat D --spr S   # malgrath.mp4 drawn from the pair (never committed)

Owner 2026-11-18 (translated), option 1 for the new boss pack: "an arena boss that always faces the front". The pack has one view
only, so the outfit shows the same frames in all four directions (the owner's choice). The licence allows commercial use and changes,
no resale, no redistribution: no pixel of the pack is committed. Committed are this tool, art_import/malgrath_boss.csv (ids, frame
counts, timing, offsets, 12 hex digits of every source file) and art_import/malgrath_boss.sums (a digest of the outfit and of every
effect strip, to hold a built pair and the pack files to). docs/CREDITS.md names the pack. The pack files are read locally by this
script only: never sent to a web or AI service, never shown to one.

Source. `--src DIR` holds the unpacked pack in any folder layout. The tool finds the folders `Color (N)` that hold a `Sheets` folder:
Color (1) is imported (the composite sheets, body and effect layers together, every frame left to right in one PNG), the others
(Color (2) to Color (5), palette variants) are noted in the table as `variant` rows, a digest of each one's Idle sheet, for later.
Every sheet is a crop of one 400 x 360 canvas at the fixed offset (ox, oy) of the table (measured on the pack's layered source, no
mismatch), so all animations share one coordinate system: that is what lets the outfit and the effects join without a jump.
Alpha is 0 or 255 apart from a ground shadow baked at 110: it is dropped (alpha cut at 128, as O608), nothing else is touched. A
sheet with another alpha level is refused.

Outfit. Idle (16 frames, 110 ms) is the idle group, Move (12 frames, 105 ms) the walk group, every frame, never sampled, the same in
the four directions. The canvas is the smallest odd square of tiles that holds the box of every Idle and Move frame, 7 x 7 (224 px):
an odd count makes the dat displacement, (-96, 0), a whole number of tiles, so the middle column of the canvas stands over the middle
of the boss's own tile and the canvas column 3 is that tile; the lowest opaque pixel of the figure is on the last row (the foot on
the bottom tile row), the middle of the box on the middle column (gen_creature_outfits.place's rule, one shift for all frames:
`shift` below). `pixel_problems` and `foot_problems` of gen_creature_outfits.py hold every built frame to its source frame.

Effects. The body poses of an attack cannot play in an outfit. The eight effects carry the body and its effect layers together (the
composite sheet), at the same shift as the outfit, so the picture of an effect frame is the picture of the outfit frame it replaces,
pixel for pixel, plus the attack: the server hides the boss while the effect plays (README "Malgrath, the Drowned Crown (O637)").
Each effect is the smallest window of whole tiles, on the outfit's own tile grid, that holds every frame: `win` = tiles added to the
left, right, top and bottom of the 7 x 7 outfit canvas, `tiles` the size (e.g. 13x10), `send` the send offset (the art's bottom-right
tile is the boss's tile + send; the boss's tile is canvas column 3, so dx = 3 + right, dy = bottom). A window frame holds the opaque
pixels of its source frame, no more and no less.

Pair step. The outfit is appended after the 3,529 outfits of pair 73 (id 3530), the effects after its 5,325 effects (5326 to 5333, in
the order of EFFECTS). The input pair needs exactly those counts. Nothing is replaced. The step joins pair 74 with the decor flames
(O623: items and the torch, no outfit and no effect), so the order of the two is free. Needs numpy and Pillow (the fx venv of CI);
`preview` needs ffmpeg.
"""
import csv
import hashlib
import math
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_wst_outfits as W  # noqa: E402
import gen_creature_outfits as G  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'malgrath_boss.csv')
SUMS = os.path.join(ART, 'malgrath_boss.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_malgrath_fx_ids.lua')
HEADER = ['kind', 'name', 'id', 'src', 'sheet', 'frames', 'ms', 'ox', 'oy', 'bx0', 'by0', 'bx1', 'by1', 'tiles', 'win', 'send', 'pixels', 'pics']

PAIR = 74
FIRST_OUTFIT = 3530                 # after the 3,529 outfits of pair 73
FIRST_EFFECT = 5326                 # after the 5,325 effects of pair 73 (the bolt from the sky ends at 5325)
NEED_MISSILES = 253
CANVAS_W, CANVAS_H = 400, 360       # the pack's canvas: every sheet is a crop of it
SHADOW = 110                        # the baked ground shadow's alpha: dropped by the cut at 128
MIN_TILES, MAX_TILES = 3, 9         # the outfit canvas: an odd square (the displacement is a whole number of tiles)
EXPECT_TILES = 7                    # what the pack gives (the committed table): 188 x 199 px figure
PHASE_LIMIT = 40
DIRS = ('north', 'east', 'south', 'west')

# sheet, frames, ms a frame, ox, oy: measured on the pack's layered source (no mismatch), one entry per animation used
ANIMS = (
    ('Idle', 16, 110, 109, 99), ('Move', 12, 105, 106, 100), ('Ground Slam', 22, 90, 49, 93), ('Lightning Rain', 26, 85, 8, 66),
    ('Eye Laser', 24, 80, 105, 97), ('Crown Inferno', 20, 95, 67, 87), ('Summon', 20, 100, 72, 97),
    ('Earthquake Stomp', 20, 90, 89, 96), ('Death', 32, 100, 71, 53), ('Spawn Rise', 24, 100, 77, 91))
# the effects in id order: name, sheet (the server names are data/lib/chaos_malgrath_fx_ids.lua)
EFFECTS = (('mg_ground_slam', 'Ground Slam'), ('mg_lightning_rain', 'Lightning Rain'), ('mg_eye_laser', 'Eye Laser'),
           ('mg_crown_inferno', 'Crown Inferno'), ('mg_summon', 'Summon'), ('mg_earthquake_stomp', 'Earthquake Stomp'),
           ('mg_death', 'Death'), ('mg_spawn_rise', 'Spawn Rise'))
VARIANTS = (2, 3, 4, 5)             # Color (2) .. Color (5): palette variants, not imported
OUTFIT_NAME = 'malgrath'


def anim_of(sheet, anims=ANIMS):
    for a in anims:
        if a[0] == sheet:
            return a
    raise KeyError(sheet)


# ---------------------------------------------------------------- geometry (pure)

def union(boxes):
    return (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))


def outfit_geometry(box):
    """(tiles n, shift (sx, sy)) of the outfit canvas for the box (x0, y0, x1, y1 inclusive, pack canvas pixels): the smallest odd
    square of tiles that holds it; the lowest row of the box on the last row, its middle on the middle column. ValueError when it
    does not fit."""
    x0, y0, x1, y1 = box
    side = max(x1 - x0 + 1, y1 - y0 + 1)
    n = max(MIN_TILES, -(-side // 32))
    if n % 2 == 0:
        n += 1
    if n > MAX_TILES:
        raise ValueError('a figure of %d px is longer than the %d x %d tiles allowed: nothing is sampled down' % (side, MAX_TILES, MAX_TILES))
    c = 32 * n
    sx = int(math.floor((c - 1) / 2.0 - (x0 + x1) / 2.0))
    sy = c - 1 - y1
    if x0 + sx < 0 or x1 + sx > c - 1 or y0 + sy < 0:
        raise ValueError('the figure does not fit the %d px canvas' % c)
    return n, (sx, sy)


def window(box, n, shift):
    """(a, b, c, d): the tiles an effect adds left, right, top and bottom of the n x n outfit canvas to hold the box"""
    x0, y0, x1, y1 = box
    sx, sy = shift
    return (max(0, -((x0 + sx) // 32)), max(0, (x1 + sx) // 32 - (n - 1)), max(0, -((y0 + sy) // 32)), max(0, (y1 + sy) // 32 - (n - 1)))


def effect_geometry(box, n, shift):
    """(width tiles, height tiles, win text, send offset (dx, dy)) of an effect holding the box"""
    a, b, c, d = window(box, n, shift)
    return n + a + b, n + c + d, '%d:%d:%d:%d' % (a, b, c, d), ((n - 1) // 2 + b, d)


def boss_tile_col(n):
    """the canvas column (in tiles) of the boss's own tile: the displacement moves the picture right by (n - 1) / 2 tiles"""
    return (n - 1) // 2


# ---------------------------------------------------------------- the pack files

def discover(src):
    """{N: {sheet name: path of its composite sheet}} of every folder `Color (N)` under src that has a `Sheets` folder"""
    out = {}
    for root, _dirs, _files in os.walk(src):
        m = re.fullmatch(r'Color \((\d+)\)', os.path.basename(root))
        sheets = os.path.join(root, 'Sheets')
        if m and os.path.isdir(sheets):
            out[int(m.group(1))] = {f[:-4]: os.path.join(sheets, f) for f in sorted(os.listdir(sheets)) if f.lower().endswith('.png')}
    return out


def read_frames(path, frames):
    """the frames of a sheet (frames side by side), RGBA arrays; ValueError when it is no whole number of frames"""
    a = W._read_png(path)
    if a.shape[1] % frames:
        raise ValueError('%s: %d px wide, not %d whole frames' % (os.path.basename(path), a.shape[1], frames))
    fw = a.shape[1] // frames
    return [a[:, i * fw:(i + 1) * fw] for i in range(frames)]


def to_canvas(frame, ox, oy):
    """the frame on the pack's 400 x 360 canvas at its fixed offset"""
    import numpy as np
    h, w = frame.shape[:2]
    if ox < 0 or oy < 0 or ox + w > CANVAS_W or oy + h > CANVAS_H:
        raise ValueError('a frame of %dx%d at %d,%d leaves the %dx%d canvas' % (w, h, ox, oy, CANVAS_W, CANVAS_H))
    c = np.zeros((CANVAS_H, CANVAS_W, 4), np.uint8)
    c[oy:oy + h, ox:ox + w] = frame
    return c


def load_anim(path, anim):
    """{'cut': [canvas frames, alpha cut at 128], 'box', 'pixels', 'dropped', 'pics'} of one sheet; ValueError for another alpha level"""
    import numpy as np
    sheet, frames, _ms, ox, oy = anim
    cuts, dropped = [], 0
    for f in read_frames(path, frames):
        bad = set(np.unique(f[..., 3]).tolist()) - {0, SHADOW, 255}
        if bad:
            raise ValueError('%s: alpha %s: only 0, %d (the ground shadow) and 255 are known; the hard cut would change a pixel'
                             % (sheet, sorted(bad)[:3], SHADOW))
        c = G.cut(to_canvas(f, ox, oy))
        dropped += int(((f[..., 3] > 0) & (f[..., 3] < 255)).sum())
        cuts.append(c)
    x0 = y0 = 10 ** 6
    x1 = y1 = -1
    for c in cuts:
        ys, xs = np.nonzero(c[..., 3])
        if not len(xs):
            raise ValueError('%s: an empty frame' % sheet)
        x0, x1, y0, y1 = min(x0, int(xs.min())), max(x1, int(xs.max())), min(y0, int(ys.min())), max(y1, int(ys.max()))
    return {'cut': cuts, 'box': (x0, y0, x1, y1), 'pixels': sum(G.opaque(c) for c in cuts), 'dropped': dropped,
            'pics': len({c.tobytes() for c in cuts})}


def paste(src, h, w, sx, sy):
    """src moved by (sx, sy) onto an empty h x w RGBA canvas; what falls outside is dropped (the callers hold the pixel counts)"""
    import numpy as np
    out = np.zeros((h, w, 4), np.uint8)
    sh, sw = src.shape[:2]
    x0, y0 = max(0, -sx), max(0, -sy)
    x1, y1 = min(sw, w - sx), min(sh, h - sy)
    if x1 > x0 and y1 > y0:
        out[y0 + sy:y1 + sy, x0 + sx:x1 + sx] = src[y0:y1, x0:x1]
    return out


# ---------------------------------------------------------------- the plan: the outfit and the effects of the pack files

def strip_digest(strip):
    import numpy as np
    s = np.ascontiguousarray(strip).copy()
    s[s[..., 3] == 0] = 0
    h = hashlib.sha256()
    h.update(repr(s.shape).encode())
    h.update(s.tobytes())
    return h.hexdigest()


def outfit_measure(idle, walk, n, shift, idle_ms, walk_ms):
    """the dict gen_creature_outfits' checks and groups_of read: the same frames in the four directions"""
    c = 32 * n
    sx, sy = shift
    m = {'tiles': n, 'scale': '%d/%d' % (c, c), 'idle': len(idle['cut']), 'walk': len(walk['cut']), 'idle_ms': idle_ms, 'walk_ms': walk_ms,
         'placed': {}, 'use': {}, 'src': {}, 'counts': {}}
    for g, a in (('idle', idle), ('walk', walk)):
        placed = [paste(f, c, c, sx, sy) for f in a['cut']]
        for d in range(4):
            m['placed'][(g, d)] = placed
            m['use'][(g, d)] = list(range(len(placed)))
            m['src'][(g, d)] = a['cut']
            m['counts'][(g, d)] = len(placed)
    m['pixels'] = sum(G.opaque(f) for g in ('idle', 'walk') for f in m['placed'][(g, 0)])
    return m


def effect_strip(a, n, shift, win):
    """the strip of an effect: its frames left to right, each (n + left + right) x (n + top + bottom) tiles, on the outfit's tile grid"""
    import numpy as np
    wa, wb, wc, wd = win
    w, h = (n + wa + wb) * 32, (n + wc + wd) * 32
    frames = [paste(f, h, w, shift[0] + 32 * wa, shift[1] + 32 * wc) for f in a['cut']]
    return np.concatenate(frames, axis=1), frames


def plan(src, first_outfit=FIRST_OUTFIT, first_effect=FIRST_EFFECT, anims=ANIMS, effects=EFFECTS, variants=VARIANTS):
    """measure the pack files: {'rows': table rows, 'sums': {key: digest}, 'm': the outfit, 'n', 'shift', 'strips': [(row, strip)]}.
    SystemExit with the reason when the pack cannot be this boss."""
    files = discover(src)
    if 1 not in files:
        raise SystemExit('no folder `Color (1)` with a `Sheets` folder under %s' % src)
    sheets = files[1]
    need = ['Idle', 'Move'] + [s for _n, s in effects]
    missing = [s for s in need if s not in sheets]
    if missing:
        raise SystemExit('Color (1) has no sheet %s' % ', '.join(missing))
    try:
        loaded = {s: load_anim(sheets[s], anim_of(s, anims)) for s in dict.fromkeys(need)}
        box = union([loaded['Idle']['box'], loaded['Move']['box']])
        n, shift = outfit_geometry(box)
    except ValueError as e:
        raise SystemExit(str(e))
    idle, walk = anim_of('Idle', anims), anim_of('Move', anims)
    m = outfit_measure(loaded['Idle'], loaded['Move'], n, shift, idle[2], walk[2])
    bad = G.pixel_problems(m) + G.foot_problems(m)
    if bad:
        raise SystemExit('the outfit: ' + '; '.join(bad[:5]))
    rows, strips, sums = [], [], {}

    def row(kind, name, nid, sheet, a, tiles='', win='', send='', pixels=0, pics=0):
        an = anim_of(sheet, anims)
        bx = a['box']
        return {'kind': kind, 'name': name, 'id': str(nid), 'src': W._sha12(sheets[sheet]), 'sheet': sheet, 'frames': str(an[1]), 'ms': str(an[2]),
                'ox': str(an[3]), 'oy': str(an[4]), 'bx0': str(bx[0]), 'by0': str(bx[1]), 'bx1': str(bx[2]), 'by1': str(bx[3]), 'tiles': tiles,
                'win': win, 'send': send, 'pixels': str(pixels), 'pics': str(pics)}

    one = '%dx%d' % (n, n)
    rows.append(row('idle', OUTFIT_NAME + '_idle', first_outfit, 'Idle', loaded['Idle'], one,
                    pixels=sum(G.opaque(f) for f in m['placed'][('idle', 0)]), pics=loaded['Idle']['pics']))
    rows.append(row('walk', OUTFIT_NAME + '_walk', first_outfit, 'Move', loaded['Move'], one,
                    pixels=sum(G.opaque(f) for f in m['placed'][('walk', 0)]), pics=loaded['Move']['pics']))
    sums[str(first_outfit)] = W.spec_digest(G.groups_of(m))
    for i, (name, sheet) in enumerate(effects):
        a = loaded[sheet]
        w, h, win, send = effect_geometry(a['box'], n, shift)
        wins = tuple(int(v) for v in win.split(':'))
        strip, frames = effect_strip(a, n, shift, wins)
        for k, (f, src_f) in enumerate(zip(frames, a['cut'])):
            if G.opaque(f) != G.opaque(src_f):
                raise SystemExit('%s frame %d: %d opaque pixels in the window, %d in the source: a pixel is lost' % (name, k, G.opaque(f), G.opaque(src_f)))
        r = row('effect', name, first_effect + i, sheet, a, '%dx%d' % (w, h), win, '%d:%d' % send, G.opaque(strip), a['pics'])
        rows.append(r)
        strips.append((r, strip))
        sums[name] = strip_digest(strip)
    for v in variants:
        if v not in files or 'Idle' not in files[v]:
            raise SystemExit('Color (%d) has no Idle sheet: the variants are noted from it' % v)
        rows.append({'kind': 'variant', 'name': 'color_%d' % v, 'id': '', 'src': W._sha12(files[v]['Idle']), 'sheet': 'Idle', 'frames': '', 'ms': '',
                     'ox': '', 'oy': '', 'bx0': '', 'by0': '', 'bx1': '', 'by1': '', 'tiles': '', 'win': '', 'send': '', 'pixels': '', 'pics': ''})
    return {'rows': rows, 'sums': sums, 'm': m, 'n': n, 'shift': shift, 'strips': strips, 'loaded': loaded}


# ---------------------------------------------------------------- the table

def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_sums(path=SUMS):
    return W.read_sums(path)


def table_text(rs):
    return ','.join(HEADER) + '\n' + ''.join(','.join(r[k] for k in HEADER) + '\n' for r in rs)


def sums_text(sums):
    return ('# sha256 of the outfit (shapes, animator, every sprite slot) by outfit id and of every effect strip by name, written by '
            'gen_malgrath_boss.py table --write (O637)\n' + ''.join('%s %s\n' % (k, sums[k]) for k in sorted(sums)))


def box_of(r):
    return tuple(int(r[k]) for k in ('bx0', 'by0', 'bx1', 'by1'))


def problems(table=None, sums=None, first_outfit=FIRST_OUTFIT, first_effect=FIRST_EFFECT, anims=ANIMS, effects=EFFECTS, variants=VARIANTS,
             expect_tiles=EXPECT_TILES):
    """What is wrong with the table: the rows are the idle row, the walk row, the effects in EFFECTS order and the variants, ids in a
    row from the first new outfit and effect, a source once, timing and offsets as ANIMS, the geometry (tiles, window, send offset)
    the one the boxes give, and the sums name the same things."""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out = []
    kinds = ['idle', 'walk'] + ['effect'] * len(effects) + ['variant'] * len(variants)
    names = [OUTFIT_NAME + '_idle', OUTFIT_NAME + '_walk'] + [n for n, _s in effects] + ['color_%d' % v for v in variants]
    if [r['kind'] for r in t] != kinds or [r['name'] for r in t] != names:
        return ['the rows are not idle, walk, the effects of EFFECTS and the variants, in that order']
    seen = set()
    for r in t:
        d = r['src']
        if not re.fullmatch(r'[0-9a-f]{12}', d):
            out.append('%s: src %s is not 12 hex digits' % (r['name'], d))
        if d in seen:
            out.append('%s: src %s is on two rows' % (r['name'], d))
        seen.add(d)
    for r in t[:2]:
        if r['id'] != str(first_outfit):
            out.append('%s: outfit id %s, it must be %d' % (r['name'], r['id'], first_outfit))
    for i, r in enumerate(t[2:2 + len(effects)]):
        if r['id'] != str(first_effect + i):
            out.append('%s: effect id %s, the row at position %d must be %d' % (r['name'], r['id'], i, first_effect + i))
    for r in t[:2 + len(effects)]:
        try:
            an = anim_of(r['sheet'], anims)
        except KeyError:
            out.append('%s: sheet %s is not an animation of ANIMS' % (r['name'], r['sheet']))
            continue
        if (int(r['frames']), int(r['ms']), int(r['ox']), int(r['oy'])) != an[1:]:
            out.append('%s: frames, ms, offset %s are not those of ANIMS %s' % (r['name'], (r['frames'], r['ms'], r['ox'], r['oy']), an[1:]))
        if not (int(r['pixels']) > 0 and 1 <= int(r['pics']) <= int(r['frames']) <= PHASE_LIMIT):
            out.append('%s: pixels %s, pictures %s of %s frames' % (r['name'], r['pixels'], r['pics'], r['frames']))
    try:
        n, shift = outfit_geometry(union([box_of(t[0]), box_of(t[1])]))
    except ValueError as e:
        return out + [str(e)]
    if expect_tiles is not None and n != expect_tiles:
        out.append('the outfit is %dx%d, the pack gives %dx%d' % (n, n, expect_tiles, expect_tiles))
    for r in t[:2]:
        if r['tiles'] != '%dx%d' % (n, n) or r['win'] or r['send']:
            out.append('%s: tiles %s, the boxes give %dx%d and an outfit has no window and no send offset' % (r['name'], r['tiles'], n, n))
    for r in t[2:2 + len(effects)]:
        w, h, win, send = effect_geometry(box_of(r), n, shift)
        if (r['tiles'], r['win'], r['send']) != ('%dx%d' % (w, h), win, '%d:%d' % send):
            out.append('%s: tiles, window, send %s, the box gives %s' % (r['name'], (r['tiles'], r['win'], r['send']), ('%dx%d' % (w, h), win, '%d:%d' % send)))
    for r in t[2 + len(effects):]:
        if any(r[k] for k in HEADER[2:] if k not in ('src', 'sheet')) or r['sheet'] != 'Idle':
            out.append('%s: a variant row holds the digest of its Idle sheet and nothing else' % r['name'])
    want = {str(first_outfit)} | {n for n, _s in effects}
    if set(s) != want:
        out.append('malgrath_boss.sums and the table name other things (%s)' % ', '.join(sorted(set(s) ^ want)))
    elif any(not re.fullmatch(r'[0-9a-f]{64}', v) for v in s.values()):
        out.append('malgrath_boss.sums: a digest is not 64 hex digits')
    return out


# ---------------------------------------------------------------- the pair

def flags_of(row):
    """(the flag bytes of the outfit entry, the flags as the dat reader gives them): the displacement only"""
    n = int(row['tiles'].split('x')[0])
    u = tuple(v & 0xFFFF for v in G.disp_of(n))
    return bytes([G.DISP_FLAG]) + struct.pack('<HH', *u), {'displacement': u}


def pair_ok(outfits, effects, missiles, first_outfit=FIRST_OUTFIT, first_effect=FIRST_EFFECT, need_missiles=NEED_MISSILES):
    return outfits == first_outfit - 1 and effects == first_effect - 1 and missiles == need_missiles


def import_spec(path, strips_dir, pairs, first_effect):
    """the spec import_fx_art.py reads: one row per effect, in id order"""
    import numpy as np
    from PIL import Image
    os.makedirs(strips_dir, exist_ok=True)
    with open(path, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs', 'lua', 'blank'])
        for r, s in pairs:
            f = os.path.join(strips_dir, r['name'] + '.png')
            Image.fromarray(np.ascontiguousarray(s)).save(f, optimize=False)
            tw, th = (int(v) for v in r['tiles'].split('x'))
            dx, dy = (int(v) for v in r['send'].split(':'))
            w.writerow(['', 'effect', r['name'], f, tw, th, r['frames'], r['ms'], dx, dy, r['sheet'].lower(), '', ';'.join([r['ms']] * int(r['frames'])), '', ''])


def build(dat, spr, out_dir, src, first_outfit=FIRST_OUTFIT, first_effect=FIRST_EFFECT, need_missiles=NEED_MISSILES, anims=ANIMS,
          effects=EFFECTS, variants=VARIANTS, log=print):
    """pair in (3,529 outfits, 5,325 effects, 253 missiles) -> pair out in OUT_DIR (not there yet): the outfit, then the effects.
    Returns the (table rows, sums) it built; the pair is read back before it is renamed in place."""
    import shutil
    sys.path.insert(0, HERE)
    from datspr import Dat
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    d = Dat(dat)
    if not pair_ok(len(d.outfits), len(d.effects), len(d.missiles), first_outfit, first_effect, need_missiles):
        raise SystemExit('refused: the input pair has %d outfits, %d effects and %d missiles, this step needs %d, %d and %d (pair 73)'
                         % (len(d.outfits), len(d.effects), len(d.missiles), first_outfit - 1, first_effect - 1, need_missiles))
    p = plan(src, first_outfit, first_effect, anims, effects, variants)
    m, table = p['m'], p['rows']
    one = [r for r in table if r['kind'] == 'idle']
    work = out_dir.rstrip('/') + '.work'
    if os.path.exists(work):
        shutil.rmtree(work)
    os.makedirs(work)
    try:
        step1 = os.path.join(work, 'outfit')
        W.build(dat, spr, step1, None, table=one, first=first_outfit, log=log, specs_of=lambda r: G.groups_of(m), flags_of=flags_of)
        pairs = p['strips']
        spec = os.path.join(work, 'import.csv')
        import_spec(spec, os.path.join(work, 'strips'), pairs, first_effect)
        step2 = os.path.join(work, 'effects')
        os.makedirs(step2)
        cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', os.path.join(step1, 'Tibia.dat'),
               '--ours-spr', os.path.join(step1, 'Tibia.spr'), '--out-dir', step2, '--spec', spec, '--expect-first-effect', str(first_effect),
               '--keep-donor-names']
        if subprocess.run(cmd).returncode:
            raise SystemExit('import_fx_art.py failed')
        for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv'):         # the ids come from the table
            q = os.path.join(step2, f)
            if os.path.exists(q):
                os.remove(q)
        problems_ = live(os.path.join(step2, 'Tibia.dat'), os.path.join(step2, 'Tibia.spr'), table=table, sums=p['sums'], first_outfit=first_outfit,
                         first_effect=first_effect, log=log)
        if problems_:
            raise SystemExit('the built pair does not read back as drawn: ' + '; '.join(problems_[:5]))
        os.makedirs(out_dir)
        for f in ('Tibia.dat', 'Tibia.spr'):
            os.rename(os.path.join(step2, f), os.path.join(out_dir, f))
    finally:
        shutil.rmtree(work, ignore_errors=True)    # the strips are pack pictures: nothing stays on disk but the pair
    log('malgrath: outfit %d and %d effects %d..%d appended' % (first_outfit, len(pairs), first_effect, first_effect + len(pairs) - 1))
    return table, p['sums']


def outfit_frames(dat, spr, nid, n):
    """{(group, direction): [canvas array of each phase]} of an outfit read from a pair, plus the groups"""
    import numpy as np
    from import_outfits import parse_body
    gs = parse_body(dat, dat.outfit(nid))
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


def live(dat_path, spr_path, table=None, sums=None, first_outfit=FIRST_OUTFIT, first_effect=FIRST_EFFECT, log=print):
    """The pair holds the outfit and every effect: the outfit's digest the one of the sums, its size, one layer, an idle and a walk
    group, the displacement as its only flag, every phase its own duration, the sprite tiles the opaque pixels the table counts, the
    same pictures in all four directions, as many different pictures as the pack has frames, the foot point on the boss's tile; each
    effect at its id with its size, phases, durations and the pixels of its sum. Returns the problem lines."""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_vfx import render_back
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    d, sp = Dat(dat_path), Spr(spr_path)
    out = []
    one, walk = t[0], t[1]
    effs = [r for r in t if r['kind'] == 'effect']
    if len(d.outfits) < first_outfit or len(d.effects) < first_effect + len(effs) - 1:
        return ['the pair has %d outfits and %d effects, the boss ends at outfit %d and effect %d'
                % (len(d.outfits), len(d.effects), first_outfit, first_effect + len(effs) - 1)]
    n = int(one['tiles'].split('x')[0])
    if W.digest(d, sp, first_outfit) != s.get(str(first_outfit)):
        out.append('outfit %d: the pictures are not the ones of malgrath_boss.sums' % first_outfit)
    th = d.outfit(first_outfit)
    if dict(th.flags) != flags_of(one)[1]:
        out.append('outfit %d: flags %s, the displacement only' % (first_outfit, dict(th.flags)))
    frames, gs = outfit_frames(d, sp, first_outfit, n)
    import numpy as np
    if [g.gtype for g in gs] != [0, 1] or any(g.layers != 1 or (g.w, g.h) != (n, n) for g in gs):
        out.append('outfit %d: not an idle and a walk group of %dx%d with one layer' % (first_outfit, n, n))
    elif (gs[0].phases, gs[1].phases) != (int(one['frames']), int(walk['frames'])):
        out.append('outfit %d: %d / %d phases, the table says %s / %s' % (first_outfit, gs[0].phases, gs[1].phases, one['frames'], walk['frames']))
    else:
        for g, r, key in zip(gs, (one, walk), ('idle', 'walk')):
            ms = int(r['ms'])
            if not g.anim or tuple(g.anim[3]) != (ms, ms) * g.phases:
                out.append('outfit %d: the %s phases do not last %d ms each' % (first_outfit, key, ms))
            total = sum(G.opaque(a) for a in frames[(key, 0)])
            if total != int(r['pixels']):
                out.append('outfit %d: %d opaque pixels in the %s sprites, the table counts %s' % (first_outfit, total, key, r['pixels']))
            if W.distinct(frames[(key, 0)]) != int(r['pics']):
                out.append('outfit %d: %s shows %d different pictures, the pack has %s' % (first_outfit, key, W.distinct(frames[(key, 0)]), r['pics']))
            for dd in range(1, 4):
                if any(not np.array_equal(a, b) for a, b in zip(frames[(key, 0)], frames[(key, dd)])):
                    out.append('outfit %d: %s facing %s is not the front picture (the boss always faces the front)' % (first_outfit, key, DIRS[dd]))
        out += G.foot_problems({'tiles': n, 'placed': frames}, 'outfit %d: ' % first_outfit)
    for r in effs:
        eid = int(r['id'])
        te = d.effects[eid - 1]
        w, h = (int(v) for v in r['tiles'].split('x'))
        ph, ms = int(r['frames']), int(r['ms'])
        if (te.w, te.h, te.phases) != (w, h, ph):
            out.append('%s (effect %d): size or phases differ' % (r['name'], eid))
            continue
        if not te.anim or list(te.anim[3]) != [ms] * (2 * ph):
            out.append('%s (effect %d): the phases do not last %d ms each' % (r['name'], eid, ms))
        back = render_back(te, sp, 1)
        strip = np.concatenate([back[(f, 0, 0, 0)] for f in range(ph)], axis=1)
        if strip_digest(strip) != s.get(r['name']):
            out.append('%s (effect %d): the pixels are not the ones of malgrath_boss.sums' % (r['name'], eid))
        if G.opaque(strip) != int(r['pixels']):
            out.append('%s (effect %d): %d opaque pixels, the table counts %s' % (r['name'], eid, G.opaque(strip), r['pixels']))
    log('live: outfit %d and %d effects %d..%d checked, %d problems' % (first_outfit, len(effs), first_effect, first_effect + len(effs) - 1, len(out)))
    return out


# ---------------------------------------------------------------- the server ids

def lua_text(t):
    effs = [r for r in t if r['kind'] == 'effect']
    first, last = int(effs[0]['id']), int(effs[-1]['id'])
    L = ['-- GENERATED by client/tools/sprites/gen_malgrath_boss.py from art_import/malgrath_boss.csv (O637). Do not edit by hand.',
         '-- Malgrath, the Drowned Crown, in client pair %d: the outfit %s (7x7 tiles, the same frames in all four directions) and' % (PAIR, t[0]['id']),
         '-- %d effects at the ids %d..%d, after the last effect of pair 73 (%d). Each effect carries the boss body and its effect layers' % (len(effs), first, last, first - 1),
         '-- (the attack as it plays), at the outfit\'s own pixel grid: the server hides the boss while one plays.',
         '-- dx, dy: the send offset (the bottom-right tile of the art is the boss\'s tile + dx, dy); w, h: tiles; ms: the whole play.',
         '-- A plain table: data/lib/chaos_malgrath_fx.lua sends these ids only when config.lua chaosClientPair is %d or more,' % PAIR,
         '-- so a server on an older pair never sends one.',
         'ChaosMalgrathFxIds = {',
         '\tpair = %d, outfit = %s, first = %d, count = %d,' % (PAIR, t[0]['id'], first, len(effs)),
         '\teffects = {']
    for r in effs:
        w, h = r['tiles'].split('x')
        dx, dy = r['send'].split(':')
        L.append('\t\t%s = {id = %s, dx = %s, dy = %s, w = %s, h = %s, ms = %d},  -- %s' % (
            r['name'], r['id'], dx, dy, w, h, int(r['ms']) * int(r['frames']), r['sheet'].lower()))
    L += ['\t},', '}']
    return '\n'.join(L) + '\n'


def ids(check_only, quiet=False):
    text = lua_text(rows())
    have = open(LUA, encoding='utf-8', newline='').read() if os.path.exists(LUA) else None
    if check_only:
        if not quiet:
            print(os.path.relpath(LUA, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_malgrath_boss.py ids)'))
        return 0 if have == text else 1
    with open(LUA, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote', os.path.relpath(LUA, ROOT))
    return 0


def check():
    t = rows()
    p = problems(t)
    for line in p:
        print('PROBLEM', line)
    bad = ids(True, quiet=True)
    if bad:
        print('PROBLEM server/data/lib/chaos_malgrath_fx_ids.lua is not up to date (run gen_malgrath_boss.py ids)')
    print('malgrath_boss: %d rows, %d problems' % (len(t), len(p) + bad))
    return 1 if p or bad else 0


# ---------------------------------------------------------------- the preview (from the built pair)

def preview(out_dir, dat_path, spr_path):
    import numpy as np
    from PIL import Image, ImageDraw
    import gen_lightning_fx as L
    from datspr import Dat, Spr
    os.makedirs(out_dir, exist_ok=True)
    t = rows()
    dat, spr = Dat(dat_path), Spr(spr_path)
    n = int(t[0]['tiles'].split('x')[0])
    frames, gs = outfit_frames(dat, spr, FIRST_OUTFIT, n)
    c = 32 * n
    disp = G.disp_of(n)
    off = (32 - c - disp[0], 32 - c - disp[1])
    idle, walk = frames[('idle', 2)], frames[('walk', 2)]
    idle_ms, walk_ms = int(t[0]['ms']), int(t[1]['ms'])
    effs = {r['name']: r for r in t if r['kind'] == 'effect'}
    anims = {name: L.pair_anim(dat, spr, int(r['id']), *(int(v) for v in r['send'].split(':'))) for name, r in effs.items()}
    # the effect carries a 3 x 3 window of tiles, ours is on the boss's tile: Anim.draw puts the art's bottom-right tile on tile + send
    _grass, stone = L.ground_tiles(dat, spr)
    COLS, ROWS = 17, 13
    bx, by = 8, 9                                      # the boss's tile: the figure is six tiles tall
    step = 20
    fps = 1000 // step

    def scene(label, boss_at=None, boss_frame=None, effect=None, ms=0):
        img = L.scene_ground(stone, COLS, ROWS)
        if boss_at is not None:
            L.over(img, boss_frame, int(boss_at[0]) + off[0], int(boss_at[1]) + off[1])
        if effect is not None:
            effect.draw(img, bx, by, ms)
        pic = Image.fromarray(img.astype(np.uint8))
        dr = ImageDraw.Draw(pic)
        dr.rectangle((0, 0, COLS * 32, 14), fill=(0, 0, 0))
        dr.text((4, 1), label[:88], fill=(255, 255, 255))
        return np.asarray(pic)

    def standing(ms):
        return idle[(ms // idle_ms) % len(idle)]

    seq = []
    home = (bx * 32, by * 32)
    # 0. arrival: the rise, the boss hidden while it plays, then standing
    a = anims['mg_spawn_rise']
    for ms in range(0, a.total + 600, step):
        seq.append(scene('arrival: spawn rise (effect %s, %s tiles, %d ms), the boss is hidden' % (effs['mg_spawn_rise']['id'], effs['mg_spawn_rise']['tiles'], a.total),
                         home if ms >= a.total else None, standing(ms), a, ms))
    # 1. standing: the idle loop twice
    for ms in range(0, 2 * idle_ms * len(idle), step):
        seq.append(scene('standing: idle, %d frames of %d ms, 1x' % (len(idle), idle_ms), home, standing(ms)))
    # 2. walking: five tiles right and back, the walk group at its own clock
    for k, direction in enumerate((1, -1)):
        x0 = (bx - 3) * 32 if direction == 1 else (bx + 3) * 32
        for ms in range(0, 3000, step):
            x = x0 + direction * (ms / 3000.0) * 6 * 32
            seq.append(scene('walking: %d frames of %d ms, one tile in 500 ms, always facing the front' % (len(walk), walk_ms), (x, home[1]),
                             walk[(ms // walk_ms) % len(walk)]))
    # 3. the six attacks as the server plays them: standing, the boss hidden while the effect plays, standing again
    for name, label in (('mg_ground_slam', 'ground slam'), ('mg_lightning_rain', 'lightning rain'), ('mg_eye_laser', 'eye laser'),
                        ('mg_crown_inferno', 'crown inferno'), ('mg_summon', 'summon'), ('mg_earthquake_stomp', 'earthquake stomp')):
        a = anims[name]
        r = effs[name]
        for ms in range(-600, a.total + 600, step):
            text = '%s (effect %s, %s tiles, send %s, %d ms): the boss is hidden while it plays' % (label, r['id'], r['tiles'], r['send'], a.total)
            live_ = 0 <= ms < a.total
            seq.append(scene(text, None if live_ else home, standing(ms + 600), a if live_ else None, ms))
    # 4. death: standing, then the effect alone (the boss is gone at the first frame), the ground empty at the end
    a = anims['mg_death']
    for ms in range(-600, a.total + 600, step):
        live_ = 0 <= ms < a.total
        text = 'death (effect %s, %s tiles, %d ms): the boss is removed, the effect plays alone' % (effs['mg_death']['id'], effs['mg_death']['tiles'], a.total)
        seq.append(scene(text, home if ms < 0 else None, standing(ms + 600), a if live_ else None, ms))
    path = os.path.join(out_dir, 'malgrath.mp4')
    L.write_mp4(path, seq, fps)
    print('wrote %s, %d frames at %d fps, %.1f MB' % (path, len(seq), fps, os.path.getsize(path) / 1e6))
    return 0


# ---------------------------------------------------------------- command line

def main(argv):
    args = list(argv)
    if args[:1] == ['check']:
        return check()
    cmd = args.pop(0) if args else ''
    src = W.opt(args, '--src')
    if cmd == 'ids':
        return ids('--check' in args)
    if cmd in ('table', 'sums') and src:
        p = plan(src)
        ttext, stext = table_text(p['rows']), sums_text(p['sums'])
        if cmd == 'sums' or '--check' in args:
            old = open(SUMS, encoding='utf-8').read() if os.path.exists(SUMS) else None
            oldt = open(TABLE, encoding='utf-8', newline='').read() if os.path.exists(TABLE) else None
            if old != stext or oldt != ttext:
                print('PROBLEM malgrath_boss.csv / .sums are not what the pack files give')
                return 1
            print('malgrath_boss.csv and .sums: up to date')
            return 0
        sys.stdout.write(ttext)
        print('outfit %dx%d, shift %s, %d shadow pixels dropped in Idle and Move' % (
            p['n'], p['n'], p['shift'], p['loaded']['Idle']['dropped'] + p['loaded']['Move']['dropped']))
        if '--write' in args:
            with open(TABLE, 'w', encoding='utf-8', newline='') as f:
                f.write(ttext)
            with open(SUMS, 'w', encoding='utf-8', newline='') as f:
                f.write(stext)
        return 0
    if cmd == 'build' and src and len(args) == 3:
        bad = problems()
        if bad:
            print('\n'.join(bad))
            return 1
        table, sums = build(args[0], args[1], args[2], src)
        if table_text(table) != open(TABLE, encoding='utf-8', newline='').read() or sums_text(sums) != open(SUMS, encoding='utf-8').read():
            print('PROBLEM the pack files do not give the committed malgrath_boss.csv / .sums')
            return 1
        return 0
    if cmd == 'live' and len(args) == 2:
        p = live(args[0], args[1])
        for line in p:
            print('PROBLEM', line)
        return 1 if p else 0
    if cmd == 'preview':
        dat, spr = W.opt(args, '--dat'), W.opt(args, '--spr')
        if dat and spr and len(args) == 1:
            return preview(args[0], dat, spr)
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
