#!/usr/bin/env python3
"""Every outfit stands on the same point of its tile (O585; client/MANIFEST.md "Outfits centred on the tile (O585)").

usage: python3 -I client/tools/sprites/gen_outfit_centre.py measure DAT SPR [--csv PATH] [--check]
       python3 -I client/tools/sprites/gen_outfit_centre.py apply DAT SPR OUT_DIR [--csv PATH]
       python3 -I client/tools/sprites/gen_outfit_centre.py check DAT SPR [--csv PATH]
       python3 -I client/tools/sprites/gen_outfit_centre.py preview DAT SPR OUT_DIR [--csv PATH] [--looks A,B+C,...]
       python3 -I client/tools/sprites/gen_outfit_centre.py knockon [--csv PATH]

Owner 2026-11-16 (translated): "Put all the outfits centred on the same place too; today some are centred up and to
the left, others down and to the right."

Measure. The feet of a look are the point of gen_outfit_anchors.py `measure` (centre "feet": the alpha-weighted centroid
of the lowest 12% of the body's solid mass, thin parts left out), taken per direction as gen_foot_marks.py does: first
frame of the direction, phase 0, base layer, every addon pattern, in pixels at 1x from the top left of the creature's
own tile, the dat displacement (attribute 25) applied. A look's standing point is the median of its four directions,
per axis (one direction with a weapon under the feet does not pull it).

Rule. TARGET is the stock standing point: the median standing point of the stock player looks 128 to 160, x 16.5 and
y 20 (the middle of the tile's width, 12 px over its bottom edge). It is the stock point and not the median of the class
looks (x 13, y 18) because everything else was drawn against it: the wings and head pieces (look 128), the mounts' seats,
the name bar, the shadow; and the class median is itself up and left of the tile's middle, which is the report.
A player body look (KINDS_MOVED: the class looks and every look of outfits.xml) of 1x1 or 2x2 tiles with no negative
displacement moves when its standing point is more than DEAD px from the target on an axis (the stock looks spread
that much). It moves by its dat displacement, the same for all four directions, never per frame:
    new displacement = old + round(standing point - TARGET)
A displacement never goes below 0 (a negative one switches the engine to its other draw pass: mapview.cpp
usesNegativeDisplacement, the name bar, the tile order). What is missing below 0 is moved in the pixels: the art of
every frame (all groups, directions, addons, layers, phases) goes right / down in its canvas by the rest, as far as
the canvas has empty columns / rows on that side (column `shift`; a look with no room keeps the rest, note "short").
Not moved, only listed (action `report`): mounts, wings and auras (not bodies), monster and other looks (reported apart;
no rule yet tells a humanoid from a beast, and stock monsters stand 4 px lower than players by design), looks over 2x2
tiles, looks with a negative displacement, the floating looks of gen_outfit_anchors.FLOATING (no feet).

Table (committed): pair_fixes/outfit_centre.csv, one row per creature thing with a visible frame:
  look, kind, size, action (move / keep / report), old_dx, old_dy, new_dx, new_dy, shift_x, shift_y,
  before_x, before_y, after_x, after_y (the standing point), spread_x, spread_y (range over the four directions), note

apply writes OUT_DIR/Tibia.dat (and Tibia.spr when a row moves pixels; else the spr is the input's, unchanged) from the
table; a row already applied is skipped (its displacement and standing point are the row's `after`), any other state
is refused. check holds a built pair to the table. preview draws the chosen looks on a tile grid before and after, from
the table alone (no built pair needed): preview.mp4 (4x, four directions) and preview_1x.png. Never committed.

Knock-on (regenerate from the built pair, they hold the dat md5): client_chaos_charselect/outfit_anchors.lua
(gen_outfit_anchors.py), game_cosmeticfx/foot_marks.lua (gen_foot_marks.py), client_chaos_wingfit/wing_centres.lua and
head_centres.lua (gen_wing_centres.py), client_chaos_infolift/info_lifts.lua (gen_info_lift.py). `knockon` prints, for
a built pair, what each of them must change by: the table's move, exactly.
"""
import argparse
import csv
import math
import os
import re
import statistics
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import anim_fixes as AF  # noqa: E402
import import_donor_things as idt  # noqa: E402
from datspr import Dat, Spr, sprite_index  # noqa: E402
from gen_info_lift import direction_alpha, displacement  # noqa: E402
from gen_outfit_anchors import FLOATING, measure as anchor_measure  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
CSV = os.path.join(HERE, 'pair_fixes', 'outfit_centre.csv')
PLAYER_LOOKS = os.path.join(REPO, 'server', 'data', 'monster', 'player_looks.csv')
MONSTER_LOOKS = os.path.join(REPO, 'server', 'data', 'monster', 'look_idle.csv')
CLASS_LOOKS = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'class_looks_core.lua')
COLS = ['look', 'kind', 'size', 'action', 'old_dx', 'old_dy', 'new_dx', 'new_dy', 'shift_x', 'shift_y',
        'before_x', 'before_y', 'after_x', 'after_y', 'spread_x', 'spread_y', 'note']
TARGET = (16.5, 20.0)        # the stock standing point (looks 128-160), px from the top left of the tile
STOCK = range(128, 161)
DEAD = 1.5                   # a look this close to the target on both axes stays
SIZES = ((1, 1), (2, 2))
KINDS_MOVED = ('class', 'outfit')
TOL = 0.5                    # check / apply: a standing point this close to the row's is the row's
# the 24 looks of the owner's preview: class looks (far, near, female, monk, floating), store outfits, a rider on a
# mount (MOUNT+RIDER), monsters (listed, not moved)
PREVIEW = ('128,136,2073,2074,2055,2161,2080,2081,2060,2179,2164,2173,2045,2183,1455,696,845,911,1210,2668,'
           '368+2073,35,3434,3406')


# ------------------------------------------------------------------------------------------------ kinds
def class_looks(path=CLASS_LOOKS):
    """the looks the classes wear now (L.looks, replaced by the pair 19 and pair 20 tables)"""
    src = open(path, encoding='utf-8').read()
    cur = {}
    for head in ('L.looks = {', 'L.pair19Looks = {', 'L.pair20Looks = {'):
        b = src[src.index(head):]
        b = b[:b.index('\n}')]
        for m in re.finditer(r'\[(\d+)\] = \{[^}]*?male = (\d+), female = (\d+)', b):
            cur[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
    return {x for v in cur.values() for x in v}


def repo_kinds():
    """{look: kind}: class, outfit, mount, wings, aura (player_looks.csv), monster (look_idle.csv); others: other"""
    kinds = {}
    for r in csv.DictReader(open(MONSTER_LOOKS, newline='', encoding='utf-8')):
        kinds[int(r['look'])] = 'monster'
    names = {'outfits.xml': 'outfit', 'mounts.xml': 'mount', 'wings.xml': 'wings', 'auras.xml': 'aura'}
    for r in csv.DictReader(open(PLAYER_LOOKS, newline='', encoding='utf-8')):
        kinds[int(r['look'])] = names.get(r['source'], 'other')
    for look in class_looks():
        kinds[look] = 'class'
    return kinds


# ------------------------------------------------------------------------------------------------ measure
def direction_feet(t, spr):
    """[(x, y) or None] of the feet facing north, east, south, west: tile pixels at 1x, displacement applied"""
    dx, dy = displacement(t)
    W, H = t.w * 32, t.h * 32
    out = []
    for x in range(4):
        m = anchor_measure(direction_alpha(t, spr, x if t.px >= 4 else 0), -(W - 32) - dx, -(H - 32) - dy, False, 'feet')
        out.append(None if m is None else (m[0], m[1]))
    return out


def standing(feet):
    """((x, y), (spread x, spread y)) of a look's four feet points: the median per axis, or None"""
    pts = [p for p in feet if p is not None]
    if not pts:
        return None
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return (statistics.median(xs), statistics.median(ys)), (max(xs) - min(xs), max(ys) - min(ys))


def rnd(v):
    return int(math.floor(v + 0.5))


def margin(g_list, store):
    """(right, bottom): empty columns / rows at the right / bottom edge of the canvas in every frame of every group"""
    right = bottom = 64
    for g in g_list:
        w, h = g['w'], g['h']
        for i, sid in enumerate(g['sprites']):
            ww, hh = i % w, (i // w) % h
            if not sid or (ww and hh):
                continue
            a = store.tile(sid)[..., 3] > 0
            if not a.any():
                continue
            if ww == 0:
                right = min(right, 31 - int(np.nonzero(a.any(axis=0))[0][-1]))
            if hh == 0:
                bottom = min(bottom, 31 - int(np.nonzero(a.any(axis=1))[0][-1]))
    return min(right, 32), min(bottom, 32)


def plan(look, kind, size, disp, point, room=None, target=TARGET):
    """(action, new displacement, pixel shift, note) of one look. room(): (right, bottom) free px, asked only when the
    displacement cannot do the whole move."""
    if kind not in KINDS_MOVED:
        return 'report', disp, (0, 0), {'monster': 'monster look: reported apart', 'other': 'not a player look'}.get(
            kind, 'not a body')
    if look in FLOATING:
        return 'report', disp, (0, 0), 'floating look, no feet'
    if size not in SIZES:
        return 'report', disp, (0, 0), 'not 1x1 or 2x2'
    if disp[0] < 0 or disp[1] < 0:
        return 'report', disp, (0, 0), 'negative displacement'
    if abs(point[0] - target[0]) <= DEAD and abs(point[1] - target[1]) <= DEAD:
        return 'keep', disp, (0, 0), ''
    want = (disp[0] + rnd(point[0] - target[0]), disp[1] + rnd(point[1] - target[1]))
    new = (max(0, want[0]), max(0, want[1]))
    rest = (new[0] - want[0], new[1] - want[1])
    shift, note = (0, 0), ''
    if rest != (0, 0):
        free = room()
        shift = (min(rest[0], free[0]), min(rest[1], free[1]))
        if shift != rest:
            note = 'short %d,%d: no room in the canvas' % (rest[0] - shift[0], rest[1] - shift[1])
    if new == disp and shift == (0, 0):
        return 'keep', disp, (0, 0), note
    return 'move', new, shift, note


def after_point(point, old, new, shift):
    return (point[0] - (new[0] - old[0]) + shift[0], point[1] - (new[1] - old[1]) + shift[1])


def fmt(v):
    return ('%.1f' % v).rstrip('0').rstrip('.') if isinstance(v, float) else str(v)


def measure_rows(dat_path, spr_path, kinds=None, only=None, log=print):
    """the table rows of a pair (dicts of strings, COLS)"""
    kinds = repo_kinds() if kinds is None else kinds
    dat, spr = Dat(dat_path), Spr(spr_path)
    things = store = None
    rows = []
    for look, t in enumerate(dat.outfits, 1):
        if not t.sprites or (only is not None and look not in only):
            continue
        st = standing(direction_feet(t, spr))
        if st is None:
            continue
        point, spread = st
        disp = displacement(t)

        def room(look=look):
            nonlocal things, store
            if things is None:
                things = idt.parse_dat(open(dat_path, 'rb').read(), idt.OUR_KINDS)['outfit']
                store = AF.Store(spr)
            return margin(things[look - 1].groups, store)
        kind = kinds.get(look, 'other')
        action, new, shift, note = plan(look, kind, (t.w, t.h), disp, point, room)
        after = after_point(point, disp, new, shift)
        rows.append(dict(zip(COLS, [str(look), kind, '%dx%d' % (t.w, t.h), action] + [fmt(v) for v in (
            disp[0], disp[1], new[0], new[1], shift[0], shift[1], point[0], point[1], after[0], after[1],
            spread[0], spread[1])] + [note])))
    return rows


def csv_text(rows):
    import io
    buf = io.StringIO()
    w = csv.DictWriter(buf, COLS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def read_csv(path):
    with open(path, newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    if rows and list(rows[0].keys()) != COLS:
        raise SystemExit('%s: columns are not %s' % (path, ','.join(COLS)))
    return rows


def num(r, *keys):
    return tuple(float(r[k]) if '.' in r[k] else int(r[k]) for k in keys)


def spread_report(rows, log=print):
    """where the feet land, per kind and size, before and after"""
    groups = {}
    for r in rows:
        groups.setdefault((r['kind'], r['size']), []).append(r)

    def q(v, p):
        v = sorted(v)
        return v[min(len(v) - 1, int(p * len(v)))]

    def line(pts):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        near = sum(1 for p in pts if abs(p[0] - TARGET[0]) <= DEAD and abs(p[1] - TARGET[1]) <= DEAD)
        return 'x %s (%s..%s) y %s (%s..%s) on target %d%%' % (
            fmt(float(statistics.median(xs))), fmt(q(xs, .05)), fmt(q(xs, .95)), fmt(float(statistics.median(ys))),
            fmt(q(ys, .05)), fmt(q(ys, .95)), round(100 * near / len(pts)))
    log('standing point: median (5%%..95%%), px from the top left of the tile; target x %s y %s, dead band %s'
        % (fmt(TARGET[0]), fmt(TARGET[1]), fmt(DEAD)))
    for key in sorted(groups):
        rs = groups[key]
        moved = sum(1 for r in rs if r['action'] == 'move')
        before = line([num(r, 'before_x', 'before_y') for r in rs])
        text = '  %-8s %-4s %4d looks  %s' % (key[0], key[1], len(rs), before)
        if moved:
            text += '\n%s after: %s (%d moved)' % (' ' * 24, line([num(r, 'after_x', 'after_y') for r in rs]), moved)
        log(text)
    mv = [r for r in rows if r['action'] == 'move']
    dist = sorted(max(abs(a - b) for a, b in zip(num(r, 'before_x', 'before_y'), num(r, 'after_x', 'after_y')))
                  for r in mv)
    log('moved: %d looks (%d also in the pixels, %d short), by a median of %s px, at most %s px; kept: %d; listed: %d'
        % (len(mv), sum(1 for r in mv if num(r, 'shift_x', 'shift_y') != (0, 0)),
           sum(1 for r in mv if r['note'].startswith('short')), fmt(float(statistics.median(dist))) if dist else '0',
           fmt(dist[-1]) if dist else '0', sum(1 for r in rows if r['action'] == 'keep'),
           sum(1 for r in rows if r['action'] == 'report')))


# ------------------------------------------------------------------------------------------------ apply / check
def shift_pixels(store, ts, sx, sy):
    """move the art of every frame of a thing right by sx and down by sy in its canvas"""
    for g in ts.groups:
        H, W = g['h'] * 32, g['w'] * 32
        for fr in AF.frames_of(g):
            img = AF.frame(store, g, *fr)
            lost = (sy and (img[H - sy:, :, 3] > 0).any()) or (sx and (img[:, W - sx:, 3] > 0).any())
            if lost:
                raise SystemExit('outfit %d: no room for the shift %d,%d' % (ts.id, sx, sy))
            new = np.zeros_like(img)
            new[sy:, sx:] = img[:H - sy, :W - sx]
            AF.put_frame(store, g, new, *fr)
    ts.log.append(('*', 'shift', '0,0', '%d,%d' % (sx, sy)))


def row_state(r, t, spr):
    """'before', 'after' or None: which side of its row a look of a pair is on"""
    st = standing(direction_feet(t, spr))
    if st is None:
        return None
    disp = displacement(t)
    for name, d, p in (('before', ('old_dx', 'old_dy'), ('before_x', 'before_y')),
                       ('after', ('new_dx', 'new_dy'), ('after_x', 'after_y'))):
        want = num(r, *p)
        if disp == num(r, *d) and abs(st[0][0] - want[0]) <= TOL and abs(st[0][1] - want[1]) <= TOL:
            return name
    return None


def apply(dat_path, spr_path, out_dir, csv_path=CSV, log=print):
    rows = [r for r in read_csv(csv_path) if r['action'] == 'move']
    d = open(dat_path, 'rb').read()
    dat, spr = Dat(d), Spr(spr_path)
    things = idt.parse_dat(d, idt.OUR_KINDS)
    store = AF.Store(spr)
    edited, skipped = {}, 0
    for r in rows:
        look = int(r['look'])
        if look > len(dat.outfits):
            raise SystemExit('outfit %d of the table is not in the pair' % look)
        state = row_state(r, dat.outfits[look - 1], spr)
        if state == 'after':
            skipped += 1
            continue
        if state != 'before':
            raise SystemExit('outfit %d is neither before nor after its row: measure this pair again' % look)
        t = things['outfit'][look - 1]
        if idt.entry_bytes(t.cat, t.flags, t.groups) != d[t.raw[0]:t.raw[1]]:
            raise SystemExit('outfit %d: its entry does not round-trip; refusing' % look)
        ts = AF.TS(t)
        AF.set_displacement(ts, '%s,%s' % (r['new_dx'], r['new_dy']))
        sx, sy = num(r, 'shift_x', 'shift_y')
        if sx or sy:
            shift_pixels(store, ts, sx, sy)
        edited[look] = ts
    out = bytearray(d[:things['item'][0].raw[0]])
    for cat in idt.CATS:
        for t in things[cat]:
            ts = edited.get(t.id) if cat == 'outfit' else None
            out += ts.entry() if ts else d[t.raw[0]:t.raw[1]]
    os.makedirs(out_dir, exist_ok=True)
    out_dat, out_spr = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
    wrote_spr = False
    if store.recs:
        size = len(spr.m) + 4 * len(store.recs) + sum(len(x) for x in store.recs)
        fs = os.statvfs(out_dir)
        if fs.f_bavail * fs.f_frsize < size + (16 << 20):
            raise SystemExit('not enough disk space in %s for the spr (%s bytes)' % (out_dir, f'{size:,}'))
        idt.write_spr(out_spr, spr.signature, spr.m, spr.count, store.recs)
        wrote_spr = True
    with open(out_dat, 'wb') as f:
        f.write(out)
    extra = len(dat.outfits) - max([int(r['look']) for r in read_csv(csv_path)] or [0])
    log('applied %d rows (%d already applied), %d new sprites; wrote %s%s'
        % (len(edited), skipped, len(store.recs), out_dat,
           ' and %s' % out_spr if wrote_spr else '; the spr is the input spr, unchanged'))
    if extra > 0:
        log('note: the pair has %d looks after the last row of the table: measure this pair' % extra)
    return len(edited), skipped, wrote_spr


def check(dat_path, spr_path, csv_path=CSV, log=print):
    """a built pair matches the table; returns the list of problems"""
    rows = read_csv(csv_path)
    dat, spr = Dat(dat_path), Spr(spr_path)
    bad = []
    seen = set()
    for r in rows:
        look = int(r['look'])
        seen.add(look)
        if look > len(dat.outfits) or not dat.outfits[look - 1].sprites:
            bad.append('outfit %d of the table is not in the pair' % look)
            continue
        t = dat.outfits[look - 1]
        if r['action'] == 'move':
            if row_state(r, t, spr) != 'after':
                bad.append('outfit %d: displacement %s, the table moves it to %s,%s (shift %s,%s)'
                           % (look, displacement(t), r['new_dx'], r['new_dy'], r['shift_x'], r['shift_y']))
        elif displacement(t) != num(r, 'old_dx', 'old_dy'):
            bad.append('outfit %d: displacement %s, the table keeps %s,%s' % (look, displacement(t), r['old_dx'], r['old_dy']))
    new = [i for i, t in enumerate(dat.outfits, 1) if t.sprites and i not in seen and i > max(seen or [0])]
    if new:
        bad.append('%d looks of the pair have no row (%d..%d): measure this pair' % (len(new), new[0], new[-1]))
    return bad


def knockon(rows):
    """{look: (dx, dy)}: how far the drawn look moves (right, down), which every table that stores tile pixels of a
    look (anchors, foot marks, torso and head centres) changes by; the name bar moves by the displacement part only"""
    out = {}
    for r in rows:
        if r['action'] == 'move':
            b, a = num(r, 'before_x', 'before_y'), num(r, 'after_x', 'after_y')
            out[int(r['look'])] = (rnd(a[0] - b[0]), rnd(a[1] - b[1]))
    return out


# ------------------------------------------------------------------------------------------------ preview
def look_image(t, spr, x):
    """RGBA canvas of direction x, phase 0, base layer, every addon pattern"""
    from PIL import Image
    W, H = t.w * 32, t.h * 32
    cv = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for yy in range(max(1, t.py)):
        for hh in range(t.h):
            for ww in range(t.w):
                a = spr.sprite(t.sprites[sprite_index(t, x if t.px >= 4 else 0, yy, 0, 0, 0, ww, hh)])
                if a is not None:
                    cv.alpha_composite(Image.fromarray(a, 'RGBA'), ((t.w - 1 - ww) * 32, (t.h - 1 - hh) * 32))
    return cv


CELL = 96            # a cell: 3 x 3 tiles, the look's tile in the middle
GRID = (4, 6)        # looks per row, rows


def draw_cell(cell, dat, spr, by_look, x, after):
    """one cell at 1x: `cell` is a look or (mount, rider)"""
    from PIL import Image, ImageDraw
    im = Image.new('RGBA', (CELL, CELL), (46, 52, 44, 255))
    dr = ImageDraw.Draw(im)
    for k in range(0, CELL + 1, 32):
        dr.line([(k, 0), (k, CELL)], fill=(70, 78, 66, 255))
        dr.line([(0, k), (CELL, k)], fill=(70, 78, 66, 255))
    dr.rectangle([32, 32, 64, 64], outline=(120, 132, 110, 255))
    place = [32, 32]
    for look in cell:
        t = dat.outfits[look - 1]
        dx, dy = displacement(t)
        sx = sy = 0
        r = by_look.get(look)
        if after and r is not None and r['action'] == 'move':
            dx, dy = num(r, 'new_dx', 'new_dy')
            sx, sy = num(r, 'shift_x', 'shift_y')
        layer = Image.new('RGBA', (CELL, CELL), (0, 0, 0, 0))
        layer.paste(look_image(t, spr, x), (place[0] - (t.w - 1) * 32 - dx + sx, place[1] - (t.h - 1) * 32 - dy + sy))
        im.alpha_composite(layer)
        place = [place[0] - dx, place[1] - dy]     # a rider sits up and left of its mount by the mount's displacement
    tx, ty = 32 + int(TARGET[0]), 32 + int(TARGET[1])
    dr.line([(tx - 3, ty), (tx + 3, ty)], fill=(255, 60, 60, 255))
    dr.line([(tx, ty - 3), (tx, ty + 3)], fill=(255, 60, 60, 255))
    return im


def parse_looks(spec):
    return [tuple(int(v) for v in part.split('+')) for part in spec.split(',') if part]


def preview(dat_path, spr_path, out_dir, csv_path=CSV, looks=PREVIEW, log=print):
    import shutil
    import subprocess
    from PIL import Image, ImageDraw
    rows = read_csv(csv_path)
    by_look = {int(r['look']): r for r in rows}
    dat, spr = Dat(dat_path), Spr(spr_path)
    cells = [c for c in parse_looks(looks) if all(1 <= v <= len(dat.outfits) and dat.outfits[v - 1].sprites for v in c)]
    cells = cells[:GRID[0] * GRID[1]]
    os.makedirs(out_dir, exist_ok=True)
    head, gap = 14, 8
    pw, ph = GRID[0] * CELL, GRID[1] * CELL

    def panel(x, after):
        im = Image.new('RGBA', (pw, ph), (20, 22, 20, 255))
        for k, cell in enumerate(cells):
            c = draw_cell(cell, dat, spr, by_look, x, after)
            ImageDraw.Draw(c).text((2, 1), '+'.join(str(v) for v in cell), fill=(230, 230, 210, 255))
            im.paste(c, ((k % GRID[0]) * CELL, (k // GRID[0]) * CELL))
        return im

    def frame(x):
        im = Image.new('RGB', (2 * pw + gap, ph + head), (12, 12, 12))
        dr = ImageDraw.Draw(im)
        dr.text((4, 2), 'before (%s)' % 'north east south west'.split()[x], fill=(230, 230, 210))
        dr.text((pw + gap + 4, 2), 'after: feet on the red cross', fill=(230, 230, 210))
        im.paste(panel(x, False), (0, head))
        im.paste(panel(x, True), (pw + gap, head))
        return im
    frames = [frame(x) for x in (2, 3, 0, 1)]
    # the 1x sheet: per look a row of the four directions before, then after
    sheet = Image.new('RGB', (8 * CELL + gap, len(cells) * CELL), (12, 12, 12))
    for k, cell in enumerate(cells):
        for j, x in enumerate((2, 3, 0, 1)):
            for side in (0, 1):
                c = draw_cell(cell, dat, spr, by_look, x, bool(side))
                if j == 0 and side == 0:
                    ImageDraw.Draw(c).text((2, 1), '+'.join(str(v) for v in cell), fill=(230, 230, 210, 255))
                sheet.paste(c, (side * (4 * CELL + gap) + j * CELL, k * CELL))
    sheet_path = os.path.join(out_dir, 'preview_1x.png')
    sheet.save(sheet_path)
    log('wrote %s' % sheet_path)
    if not shutil.which('ffmpeg'):
        log('ffmpeg not found: no MP4')
        return [sheet_path]
    scale = 4
    w, h = frames[0].size[0] * scale, frames[0].size[1] * scale
    w, h = w - w % 2, h - h % 2
    mp4 = os.path.join(out_dir, 'preview.mp4')
    p = subprocess.Popen(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s',
                          '%dx%d' % (w, h), '-r', '2', '-i', '-', '-c:v', 'libx264', '-crf', '18', '-pix_fmt',
                          'yuv420p', '-r', '10', '-movflags', '+faststart', mp4], stdin=subprocess.PIPE)
    for _ in range(3):
        for f in frames:
            big = f.resize((f.size[0] * scale, f.size[1] * scale), Image.NEAREST).crop((0, 0, w, h))
            for _ in range(3):      # each direction 1.5 s
                p.stdin.write(big.tobytes())
    p.stdin.close()
    if p.wait():
        raise SystemExit('ffmpeg failed')
    log('wrote %s' % mp4)
    return [sheet_path, mp4]


# ------------------------------------------------------------------------------------------------ run
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=('measure', 'apply', 'check', 'preview', 'knockon'))
    ap.add_argument('dat', nargs='?')
    ap.add_argument('spr', nargs='?')
    ap.add_argument('out_dir', nargs='?')
    ap.add_argument('--csv', default=CSV)
    ap.add_argument('--check', action='store_true', help='measure: compare with the table, write nothing')
    ap.add_argument('--looks', default=PREVIEW)
    a = ap.parse_args(argv)
    if a.cmd != 'knockon' and not (a.dat and a.spr):
        ap.error('%s needs DAT SPR' % a.cmd)
    if a.cmd == 'measure':
        rows = measure_rows(a.dat, a.spr)
        text = csv_text(rows)
        spread_report(rows)
        if a.check:
            have = open(a.csv, encoding='utf-8').read() if os.path.exists(a.csv) else ''
            if have != text:
                print('%s is not what the pair gives' % a.csv)
                return 1
            print('outfit centre table up to date (%d looks)' % len(rows))
            return 0
        with open(a.csv, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        print('wrote %s (%d looks)' % (os.path.relpath(a.csv, REPO), len(rows)))
        return 0
    if a.cmd == 'apply':
        if not a.out_dir:
            ap.error('apply needs OUT_DIR')
        apply(a.dat, a.spr, a.out_dir, a.csv)
        return 0
    if a.cmd == 'check':
        bad = check(a.dat, a.spr, a.csv)
        for b in bad[:40]:
            print(b)
        print('outfit centre: %s' % ('%d problems' % len(bad) if bad else 'the pair matches the table'))
        return 1 if bad else 0
    if a.cmd == 'knockon':
        for look, (dx, dy) in sorted(knockon(read_csv(a.csv)).items()):
            print('%d: every stored point of the look moves by %d,%d' % (look, dx, dy))
        return 0
    if not a.out_dir:
        ap.error('preview needs OUT_DIR')
    preview(a.dat, a.spr, a.out_dir, a.csv, a.looks)
    return 0


if __name__ == '__main__':
    sys.exit(main())
