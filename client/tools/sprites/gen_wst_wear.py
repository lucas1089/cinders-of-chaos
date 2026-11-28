#!/usr/bin/env python3
"""Purchased wings, heads and capes as cosmetics of client pair 83, with levitation and a head / cape layer (O747).

    python3 -I gen_wst_wear.py table --src DIR --curation FILE [--check]  # the table and sums from the pack sheets
    python3 -I gen_wst_wear.py check                  # CI, no art, no pair: table rules, sums, the generated files
    python3 -I gen_wst_wear.py ids [--check]          # the generated files from the table (no art)
    python3 -I gen_wst_wear.py build DAT SPR OUT_DIR --src DIR   # the cliff-built pair 82 -> pair 83; any other refused
    python3 -I gen_wst_wear.py live DAT SPR           # a built pair holds every piece (pending while PAIR_ASSETS < 83)
    python3 -I gen_wst_wear.py shifts DAT SPR [--check]   # the north move of every pack wing from the pair (O779)
    python3 -I gen_wst_wear.py preview OUT_DIR --src DIR         # wear_preview.mp4 on the class sheets (never committed)

Owner 2026-11-24: "Pode importar, com levitação e camada nova. Remova as nossas artes já publicadas que estão com qualidade
inferior a essas." Three purchased sets of the same seller (docs/CREDITS.md names them; this file does not): wings that lift
their wearer, head pieces and capes, oblique 32 px, 8 direction rows, a back and a front layer per piece. Only the pieces of
the owner's curation (`keep`) enter: 74 wings, 66 heads, 78 capes. The cut ones never do.

No picture is in the repository. Committed: this script, the table art_import/pack_wear.csv (one row a piece: category, the
pack id, the name, the element, the client look, the wings.xml id or the design it replaces, the price, the twin aura of pair
33, frames, frame size, anchor tile, src = 12 hex of the sha256 of the back and the front sheet file, the lift of a wing per
frame) and art_import/pack_wear.sums (one sha256 a look over its pictures as the pair holds them). The sheets are read by this
local script only; nothing is sent to a web or AI service.

Wings (category wings). Our code-drawn wings (drawn_wings/designs.csv, O583) are of lower quality than the pack. A row of
designs.csv whose name, slugged (lower case, other characters `_`), is a kept pack wing gets the pack piece IN PLACE: the same
look and wings.xml id (owners keep what they own, the server's wings.xml stays). 73 rows. The one kept wing with no row
(Plasma Fly Wings) is a new wings look after the last outfit, wings.xml id 128. Rows that match a cut pack wing (19) or none
(29) keep the drawn art, and so do the six looks 3555-3560 of O581 phase 2. drawn_wings/art_by_row.csv records the art of
every row (pack or drawn). An imported wing is not anchored by the torso measure of base patch 0204: client_chaos_wingfit
hands the engine its anchor tile (setOutfitPackPiece) and its lift (setOutfitWingsLift, base patch 0209) once the dat holds
look 3589 (pair 83); wing_anchors.lua keeps the look, so an older pair still anchors the drawn art by the torso.

Heads and capes (categories heads, capes): a new layer (base patch 0210). Each piece is a creature look like a wing (one
layer, 4 directions, y pattern 0 the back with the solid front pixels on it, y pattern 1 the front, its frames at 83 ms,
animateAlways, no displacement), appended after the new wing. The engine draws the back before the body and the front after
it, placed by the anchor tile on the wearer's tile, lifted with the body. Who wears what comes from the server's cosmetics
(kinds head and cape, server data/lib/chaos_wst_wear.lua).

The cut (house rules, every piece): alpha a hard cut at 0.5 (gen_pack27_fx.clean_alpha); the pack's soft ground shadow of a
wing (dark, half see-through pixels of the back layer) is taken out first, because the hard cut would make it a black disc:
the engine's own soft shadow stays on the ground under a floating wearer. Rows N, E, S, W of the sheet (6, 0, 2, 4) in the dat
order north, east, south, west. Placement in the engine: the frame's top left is the wearer's tile minus anchor x 32 px, the
wearer's tile being the creature's place minus the body's displacement (client/BASE.md "0209").

North view (O779, V46 seen in a client on pair 90). The pack draws its four direction rows from straight above: they turn
one picture (north is the west row mirrored on the diagonal), so facing north the wings lie on the body's side towards the
viewer and the picture hangs 8.4 to 12.8 px under the south one, 2 to 5 px left (alpha centre, mean of the frames; in a client
11 to 15 px). The game's camera looks from the south at a slant, and a wing on the back stands as high from behind as from the
front (the rule of the code-drawn wings, O770 `north_hang`). art_import/pack_wear_shift.csv holds per wings look the move of its
north picture: the whole pixels that put the alpha centre of y pattern 0 facing north on the one facing south (`turn_of`,
`hang` = north minus south before, px). `shifts DAT SPR` measures them on a built pair; `live` holds the table to the pair.
wear_pieces.lua `shifts` hands them to the engine (base patch 0217, setOutfitPackShift): the wings' picture moves, the body,
its lift and the head / cape layer stay. East and west keep the pack's place (the wings trail behind the body, 2 to 11 px
under the south view, inside the range of the code-drawn wings). Heads and capes are not moved: their north views differ by
the piece (a cape seen from behind covers the back), not by one rule.

Input pair: pair 82 with the cliff pieces of O746 (gen_cliff_art.py build): items end at 44605, outfits at 3588, and the
cliff pieces pass gen_cliff_art.py live. Any other pair is refused. The order of pair 83 is therefore cliff art first, then
this step (client/MANIFEST.md "Pair 83 build order"). Needs numpy and Pillow (the fx venv of CI).
"""
import csv
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

TABLE = os.path.join(HERE, 'art_import', 'pack_wear.csv')
SUMS = os.path.join(HERE, 'art_import', 'pack_wear.sums')
DESIGNS = os.path.join(HERE, 'drawn_wings', 'designs.csv')
ART_BY_ROW = os.path.join(HERE, 'drawn_wings', 'art_by_row.csv')
PACK33 = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_pack33_cosmetics.lua')
CLIENT_DATA = os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_wingfit', 'wear_pieces.lua')
SERVER_IDS = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_wst_wear_ids.lua')
CLASS_SHEETS = os.path.join(HERE, 'art_import', 'class_redraw')

PAIR_IN = 82
PAIR_OUT = 83
CLIFF_LAST_ITEM = 44605           # pair 82 + the 42 cliff pieces 44564-44605 (gen_cliff_art.py FIRST + 41)
INPUT_OUTFITS = 3588              # pair 82 ends at the last hunt monster of O726 / O729
FIRST_NEW = INPUT_OUTFITS + 1     # 3589: the new wing, then the heads, then the capes
FIRST_NEW_WINGS = 128             # wings.xml: 1-121 the old wings, 122-127 the drawn wings of O581 phase 2
FRAME_MS = 83                     # 12 frames a second, the pack's speed
CATS = ('wings', 'heads', 'capes')
KIND = {'wings': 'wings', 'heads': 'head', 'capes': 'cape'}
COST = {'wings': 300, 'heads': 150, 'capes': 200}   # a piece with a pair 33 twin keeps the twin's price
ELEMENTS = ('fire', 'water', 'wind', 'earth', 'energy', 'light', 'dark', 'neutral')
# the element of a kept piece with no pair 33 twin (the store text names it)
EXTRA_ELEMENT = {'plasma_fly_wings': 'energy', 'atom_orbit': 'energy', 'tesla_crown': 'energy', 'academic_gown_cape': 'neutral',
                 'hex_shield_cape': 'energy', 'ion_hood': 'energy', 'magnet_plate_cape': 'neutral', 'plasma_train': 'energy'}
ROWS = (6, 0, 2, 4)               # sheet rows of north, east, south, west (the sheet: E SE S SW W NW N NE)
SHIFTS = os.path.join(HERE, 'art_import', 'pack_wear_shift.csv')
SHIFT_HEADER = ['look', 'key', 'dir', 'dx', 'dy', 'hang']
SHIFT_MAX = 24                    # px; base patch 0217 ignores a larger move (chaospieceshift.h kMaxShiftPx)
SHADOW_SUM = 60                   # a back-layer pixel darker than this (r + g + b), half see-through, is the pack's ground shadow
HEADER = ['cat', 'key', 'name', 'element', 'look', 'wings', 'design', 'cost', 'aura', 'frames', 'fw', 'fh', 'ax', 'ay',
          'src_back', 'src_front', 'lift']


def slug(s):
    return re.sub(r'[^a-z0-9]', '_', s.lower())


# ------------------------------------------------------------------------------------------------ inputs
def designs(path=DESIGNS):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def pack33(path=PACK33):
    """{(kind, pack id): (auras.xml or wings.xml id, look, name, element, cost)} of the pair 33 cosmetics"""
    out = {}
    text = open(path, encoding='utf-8').read()
    for kind, key, i, look, name, el, cost in re.findall(
            r'key = "(wings|head|cape)_(\w+)", id = (\d+), look = (\d+), name = "([^"]+)", element = "(\w+)", cost = (\d+)', text):
        pid = key + '_wings' if kind == 'wings' else key
        out[(kind, pid)] = (int(i), int(look), name, el, int(cost))
    return out


def meta(src, cat):
    with open(os.path.join(src, cat, 'fontes', 'metadata.json'), encoding='utf-8') as f:
        return {e['id']: e for e in json.load(f)['effects']}


def sheet_path(src, cat, e, layer):
    return os.path.join(src, cat, 'efeitos', e['variants']['oblique/32']['files'][layer])


def sha12(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()[:12]


def lift_text(e):
    return ' '.join('%d %d' % (int(dx), int(dy)) for dx, dy in e['lift_px'])


def lift_of(row):
    v = [int(x) for x in row['lift'].split()] if row['lift'] else []
    return [(v[i], v[i + 1]) for i in range(0, len(v), 2)]


# ------------------------------------------------------------------------------------------------ the table
def table_rows(src, curation, rows_designs=None, twins=None):
    """the rows the table must hold, from the pack metadata, the curation, designs.csv and the pair 33 cosmetics"""
    rows_designs = designs() if rows_designs is None else rows_designs
    twins = pack33() if twins is None else twins
    by_name = {slug(r['name']): r for r in rows_designs}
    out, look = [], FIRST_NEW
    for cat in CATS:
        m = meta(src, cat)
        keep = list(curation[cat]['keep'])
        missing = [k for k in keep if k not in m]
        if missing:
            raise SystemExit('curation names pieces the %s metadata has not: %s' % (cat, missing))
        if cat == 'wings':     # replaced rows first (designs order), then the new one(s)
            keep = sorted([k for k in keep if k in by_name], key=lambda k: int(by_name[k]['wings'])) + \
                sorted(k for k in keep if k not in by_name)
        else:
            keep = sorted(keep)
        new_wings = FIRST_NEW_WINGS
        for k in keep:
            e = m[k]
            v = e['variants']['oblique/32']
            twin = twins.get((KIND[cat], k))
            r = {'cat': cat, 'key': k, 'name': e['name'], 'frames': str(e['frames']), 'fw': str(v['frame_w']), 'fh': str(v['frame_h']),
                 'ax': str(v['anchor_tile'][0]), 'ay': str(v['anchor_tile'][1]),
                 'src_back': sha12(sheet_path(src, cat, e, 'back')), 'src_front': sha12(sheet_path(src, cat, e, 'front')),
                 'lift': lift_text(e) if cat == 'wings' else '', 'aura': '', 'design': '', 'wings': ''}
            r['element'] = twin[3] if twin else EXTRA_ELEMENT.get(k, 'neutral')
            r['cost'] = str(twin[4] if twin else COST[cat])
            if cat == 'wings' and k in by_name:
                d = by_name[k]
                r.update(look=d['look'], wings=d['wings'], design=d['key'], name=d['name'])
            else:
                r['look'] = str(look)
                look += 1
                if cat == 'wings':
                    r['wings'] = str(new_wings)
                    new_wings += 1
                elif twin:
                    r['aura'] = str(twin[0])
            out.append(r)
    return out


def table_text(rows):
    return ','.join(HEADER) + '\n' + ''.join(','.join(r[c] for c in HEADER) + '\n' for r in rows)


def load(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def problems(rows=None, rows_designs=None):
    """the rules of the table that need no art"""
    rows = load() if rows is None else rows
    rows_designs = designs() if rows_designs is None else rows_designs
    bad = []
    if not rows or set(rows[0].keys()) != set(HEADER):
        return ['the table columns are not %s' % HEADER]
    by_key = {r['key']: r for r in rows_designs}
    counts = {c: sum(1 for r in rows if r['cat'] == c) for c in CATS}
    if counts != {'wings': 74, 'heads': 66, 'capes': 78}:
        bad.append('the curation keeps 74 wings, 66 heads, 78 capes: the table has %s' % counts)
    seen, keys = set(), set()
    new_looks = []
    for r in rows:
        tag = '%s %s' % (r['cat'], r['key'])
        if r['cat'] not in CATS:
            bad.append('%s: category' % tag)
            continue
        if (r['cat'], r['key']) in keys:
            bad.append('%s: twice' % tag)
        keys.add((r['cat'], r['key']))
        if r['look'] in seen:
            bad.append('%s: look %s twice' % (tag, r['look']))
        seen.add(r['look'])
        if r['element'] not in ELEMENTS:
            bad.append('%s: element %s' % (tag, r['element']))
        if not r['cost'].isdigit() or not 100 <= int(r['cost']) <= 350:
            bad.append('%s: price %s outside 100-350' % (tag, r['cost']))
        fw, fh, ax, ay, n = (int(r[c]) for c in ('fw', 'fh', 'ax', 'ay', 'frames'))
        if fw % 32 or fh % 32 or not 64 <= fw <= 160 or not 64 <= fh <= 160:
            bad.append('%s: frame %dx%d' % (tag, fw, fh))
        if not (0 <= ax < fw // 32 and 0 <= ay < fh // 32):
            bad.append('%s: anchor tile %d %d outside the frame' % (tag, ax, ay))
        if not 8 <= n <= 32:
            bad.append('%s: %d frames' % (tag, n))
        if not re.fullmatch(r'[0-9a-f]{12}', r['src_back']) or not re.fullmatch(r'[0-9a-f]{12}', r['src_front']):
            bad.append('%s: src digests' % tag)
        if r['cat'] == 'wings':
            lift = lift_of(r)
            if len(lift) != n or any(dx > 0 or dy > 0 or dx < -16 or dy < -16 for dx, dy in lift):
                bad.append('%s: lift needs %d pairs of 0..-16 px' % (tag, n))
            if r['design']:
                d = by_key.get(r['design'])
                if d is None or d['look'] != r['look'] or d['wings'] != r['wings'] or slug(d['name']) != r['key']:
                    bad.append('%s: replaces %s, but look, wings id or name differ from designs.csv' % (tag, r['design']))
            else:
                new_looks.append(int(r['look']))
                if not r['wings'].isdigit() or int(r['wings']) < FIRST_NEW_WINGS:
                    bad.append('%s: a new wing needs a wings.xml id from %d' % (tag, FIRST_NEW_WINGS))
            if r['aura']:
                bad.append('%s: a wing has no twin aura' % tag)
        else:
            new_looks.append(int(r['look']))
            if r['wings'] or r['design'] or r['lift']:
                bad.append('%s: wings id, design or lift on a %s' % (tag, r['cat']))
            if r['aura'] and not r['aura'].isdigit():
                bad.append('%s: aura' % tag)
    if new_looks != list(range(FIRST_NEW, FIRST_NEW + len(new_looks))):
        bad.append('the new looks must be %d.. dense in table order' % FIRST_NEW)
    if sum(1 for r in rows if r['design']) != 73:
        bad.append('73 designs.csv rows get the pack art, the table has %d' % sum(1 for r in rows if r['design']))
    names = {}
    for r in rows:
        k = (r['cat'], r['name'].lower())
        if k in names:
            bad.append('%s: the name %s twice' % (r['cat'], r['name']))
        names[k] = 1
    return bad


# ------------------------------------------------------------------------------------------------ the pictures
def clean(fr, back):
    """one frame of a layer -> the hard-alpha frame of the pair: the ground shadow out (back layer), alpha cut at 0.5"""
    import numpy as np
    from gen_pack27_fx import clean_alpha
    fr = np.ascontiguousarray(fr)
    if back:
        a = fr[..., 3]
        dark = fr[..., :3].astype(np.int32).sum(axis=2) < SHADOW_SUM
        shadow = dark & (a > 0) & (a < 255)
        if shadow.any():
            fr = fr.copy()
            fr[shadow] = 0
    return clean_alpha(fr)


def whole(back, front):
    """y pattern 0: the back with the solid pixels of the front on it (the stock order of a client without base patch 0203)"""
    out = back.copy()
    solid = front[..., 3] == 255
    out[solid] = front[solid]
    return out


def read_sheet(path):
    import numpy as np
    from PIL import Image
    with Image.open(path) as im:
        return np.asarray(im.convert('RGBA'))


def pictures(src, row, cache=None):
    """{(y, direction index, frame): RGBA fh x fw} of a piece: y 0 whole, y 1 front; directions north, east, south, west"""
    m = meta(src, row['cat'])
    e = m[row['key']]
    sheets = {}
    for layer in ('back', 'front'):
        p = sheet_path(src, row['cat'], e, layer)
        if sha12(p) != row['src_' + layer]:
            raise SystemExit('%s %s: the %s sheet is not the one of the table (src digest)' % (row['cat'], row['key'], layer))
        sheets[layer] = read_sheet(p)
    fw, fh, n = int(row['fw']), int(row['fh']), int(row['frames'])
    out = {}
    for x, r in enumerate(ROWS):
        for f in range(n):
            box = (slice(r * fh, (r + 1) * fh), slice(f * fw, (f + 1) * fw))
            back = clean(sheets['back'][box], True)
            front = clean(sheets['front'][box], False)
            out[(0, x, f)] = whole(back, front)
            out[(1, x, f)] = front
    return out


def digest(pats):
    import numpy as np
    h = hashlib.sha256()
    for key in sorted(pats):
        h.update(bytes(key))
        h.update(np.ascontiguousarray(pats[key]).tobytes())
    return h.hexdigest()


def sums_text(sums):
    return ''.join('%d %s\n' % (look, sums[look]) for look in sorted(sums))


def read_sums(path=SUMS):
    out = {}
    if os.path.isfile(path):
        with open(path, encoding='utf-8') as f:
            for line in f:
                look, h = line.split()
                out[int(look)] = h
    return out


# ------------------------------------------------------------------------------------------------ the north move (O779)
def rnd(v):
    """to the nearest whole pixel, a half away from zero"""
    return int(v + 0.5) if v >= 0 else -int(-v + 0.5)


def centre(frames):
    """the mean over the frames of the alpha centre (x, y) of RGBA pictures; None when every frame is empty"""
    import numpy as np
    xs, ys = [], []
    for img in frames:
        yy, xx = np.nonzero(img[..., 3] > 0)
        if len(yy):
            xs.append(xx.mean())
            ys.append(yy.mean())
    return (float(np.mean(xs)), float(np.mean(ys))) if xs else None


def turn_of(pats, frames):
    """(dx, dy, hang) of a wing's pictures {(y, direction, frame): RGBA}: the whole px that put the north picture's centre (y
    pattern 0, the whole wing) on the south one's, and the north minus south row before (px)"""
    n = centre([pats[(0, 0, f)] for f in range(frames)])
    s = centre([pats[(0, 2, f)] for f in range(frames)])
    if n is None or s is None:
        return 0, 0, 0.0
    return rnd(s[0] - n[0]), rnd(s[1] - n[1]), round(n[1] - s[1], 1)


def shift_rows(dat, spr, rows=None, log=print):
    """one row a pack wing, in table order, measured on a built pair; None when a wing is not in the pair"""
    rows = load() if rows is None else rows
    out = []
    for r in rows:
        if r['cat'] != 'wings':
            continue
        pats = pair_pictures(dat, spr, r)
        if isinstance(pats, str):
            log(pats)
            return None
        dx, dy, hang = turn_of(pats, int(r['frames']))
        out.append({'look': r['look'], 'key': r['key'], 'dir': 'north', 'dx': str(dx), 'dy': str(dy), 'hang': '%.1f' % hang})
    return out


def shift_text(srows):
    return ','.join(SHIFT_HEADER) + '\n' + ''.join(','.join(r[c] for c in SHIFT_HEADER) + '\n' for r in srows)


def load_shifts(path=SHIFTS):
    if not os.path.isfile(path):
        return []
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def shift_problems(srows=None, rows=None):
    """the rules of pack_wear_shift.csv that need no pair: one north row per pack wing in table order, whole px inside
    SHIFT_MAX, dy the hang rounded the other way, the move up (a pack wing never hangs higher facing north)"""
    srows = load_shifts() if srows is None else srows
    rows = load() if rows is None else rows
    if not srows or set(srows[0].keys()) != set(SHIFT_HEADER):
        return ['pack_wear_shift.csv: the columns are not %s (run gen_wst_wear.py shifts DAT SPR)' % SHIFT_HEADER]
    wings = [(r['look'], r['key']) for r in rows if r['cat'] == 'wings']
    if [(r['look'], r['key']) for r in srows] != wings:
        return ['pack_wear_shift.csv: one row per pack wing of pack_wear.csv in its order (%d wings, %d rows)' % (len(wings), len(srows))]
    bad = []
    for r in srows:
        tag = 'pack_wear_shift.csv %s %s' % (r['look'], r['key'])
        if r['dir'] != 'north':
            bad.append('%s: only the north view moves' % tag)
        if not re.fullmatch(r'-?\d+', r['dx']) or not re.fullmatch(r'-?\d+', r['dy']) or not re.fullmatch(r'-?\d+\.\d', r['hang']):
            bad.append('%s: dx, dy whole px, hang px with one decimal' % tag)
            continue
        dx, dy, hang = int(r['dx']), int(r['dy']), float(r['hang'])
        if abs(dx) > SHIFT_MAX or abs(dy) > SHIFT_MAX:
            bad.append('%s: a move over %d px' % (tag, SHIFT_MAX))
        if abs(dy + hang) > 0.55:
            bad.append('%s: dy %d is not the hang %.1f rounded the other way' % (tag, dy, hang))
        if dy > 0:
            bad.append('%s: a pack wing moves up facing north, not down' % tag)
    return bad


# ------------------------------------------------------------------------------------------------ generated files
def art_by_row_text(rows=None, rows_designs=None, curation_cut=None):
    """one line per designs.csv row: its look, wings id, key and the art it has from pair 83"""
    rows = load() if rows is None else rows
    rows_designs = designs() if rows_designs is None else rows_designs
    packed = {r['design']: r['key'] for r in rows if r['design']}
    lines = ['wings,look,key,art,pack']
    for d in rows_designs:
        if d['key'] in packed:
            lines.append('%s,%s,%s,pack,%s' % (d['wings'], d['look'], d['key'], packed[d['key']]))
        else:
            lines.append('%s,%s,%s,drawn,' % (d['wings'], d['look'], d['key']))
    return '\n'.join(lines) + '\n'


def packed_looks(rows=None):
    """the wings looks of designs.csv that carry the pack art from pair 83 (placed by their anchor tile there)"""
    rows = load() if rows is None else rows
    return sorted(int(r['look']) for r in rows if r['design'])


def lua_str(s):
    return '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')


def client_text(rows=None, shifts=None):
    rows = load() if rows is None else rows
    lines = ['-- Generated by client/tools/sprites/gen_wst_wear.py ids from client/tools/sprites/art_import/pack_wear.csv. Do not edit.',
             '-- The purchased wings, heads and capes of client pair %d (O747): per look the anchor tile (the column and row of the' % PAIR_OUT,
             "-- wearer's tile inside the piece's picture: base patch 0209 puts the picture's top left at the wearer's tile minus",
             '-- anchor x 32 px), and per wings look the lift of the body in every frame (px at 1x, x then y; negative is up and left,',
             '-- the frame of the wings animation at %d ms). heads / capes: the pieces of the layer of base patch 0210 by key.' % FRAME_MS,
             '-- client_chaos_wingfit hands it to the engine; game_cosmetics reads heads / capes for the window and the preview.',
             'ChaosWearPieces = {',
             '  pair = %d,' % PAIR_OUT,
             '  frameMs = %d,' % FRAME_MS,
             '  first = %d,' % FIRST_NEW,
             '  pieces = {']
    for r in rows:
        lines.append('    {%s,%s,%s},' % (r['look'], r['ax'], r['ay']))
    lines += ['  },', '  lifts = {']
    for r in rows:
        if r['cat'] == 'wings':
            lines.append('    [%s] = "%s",' % (r['look'], r['lift']))
    lines.append('  },')
    lines.append('  -- O779, base patch 0217: a pack wing\'s picture moved facing a direction {look, dir (0 north), dx, dy}, px at 1x')
    lines.append('  shifts = {')
    for r in (load_shifts() if shifts is None else shifts):
        if r['dx'] != '0' or r['dy'] != '0':
            lines.append('    {%s,%d,%s,%s},' % (r['look'], ('north', 'east', 'south', 'west').index(r['dir']), r['dx'], r['dy']))
    lines.append('  },')
    for cat in ('heads', 'capes'):
        lines.append('  %s = {' % cat)
        for r in rows:
            if r['cat'] == cat:
                lines.append('    {key = %s, look = %s, name = %s},' % (lua_str(r['key']), r['look'], lua_str(r['name'])))
        lines.append('  },')
    lines += ['}', 'return ChaosWearPieces', '']
    return '\n'.join(lines)


def server_text(rows=None):
    rows = load() if rows is None else rows
    lines = ['-- Generated by client/tools/sprites/gen_wst_wear.py ids from client/tools/sprites/art_import/pack_wear.csv. Do not edit.',
             '-- The purchased wings, heads and capes of client pair %d (O747). wings: the new wings look(s) (wings.xml id, client' % PAIR_OUT,
             '-- look appended after outfit %d); the %d designs.csv wings that get the pack art in place keep their ids and need no' % (INPUT_OUTFITS, sum(1 for r in rows if r['design'])),
             '-- server change. heads / capes: the pieces of the head / cape layer (key, client look, name, element, price, the auras.xml',
             '-- id of the pair 33 aura of the same piece or nil). Read by data/lib/chaos_wst_wear.lua (the gate, the cosmetics, the store)',
             '-- and server/tools/install_outfits.py (the wings.xml line).',
             'local M = {}', '', 'M.PAIR = %d' % PAIR_OUT, '', 'M.wings = {']
    lines.append(',\n'.join('\t{key = "wings_%s", id = %s, look = %s, name = %s, element = "%s", cost = %s}'
                            % (re.sub(r'_wings$', '', r['key']), r['wings'], r['look'], lua_str(r['name']), r['element'], r['cost'])
                            for r in rows if r['cat'] == 'wings' and not r['design']))
    lines += ['}', '']
    for cat in ('heads', 'capes'):
        lines.append('M.%s = {' % cat)
        lines.append(',\n'.join('\t{key = "%s", look = %s, name = %s, element = "%s", cost = %s%s}'
                                % (r['key'], r['look'], lua_str(r['name']), r['element'], r['cost'],
                                   ', aura = %s' % r['aura'] if r['aura'] else '')
                                for r in rows if r['cat'] == cat))
        lines += ['}', '']
    lines += ['return M', '']
    return '\n'.join(lines)


def write_or_check(path, text, check):
    old = open(path, encoding='utf-8').read() if os.path.isfile(path) else None
    if old == text:
        return []
    if check:
        return ['%s is stale: run gen_wst_wear.py ids' % os.path.relpath(path, REPO)]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote ' + os.path.relpath(path, REPO))
    return []


def generated(check, rows=None):
    rows = load() if rows is None else rows
    bad = write_or_check(ART_BY_ROW, art_by_row_text(rows), check)
    bad += write_or_check(CLIENT_DATA, client_text(rows), check)
    bad += write_or_check(SERVER_IDS, server_text(rows), check)
    return bad


# ------------------------------------------------------------------------------------------------ the pair
class _G:
    pass


def new_group(row, pats, index, old=None):
    """the frame group of a piece: frame size in tiles, one layer, 4 directions, 2 y patterns, the frames at FRAME_MS;
    the old group's type and z patterns for a wing replaced in place"""
    from datspr import sprite_index
    g = _G()
    g.gtype = old.gtype if old is not None else 0
    g.w, g.h = int(row['fw']) // 32, int(row['fh']) // 32
    g.exact = max(int(row['fw']), int(row['fh']))
    g.layers, g.px, g.py, g.pz, g.phases = 1, 4, 2, (old.pz if old is not None else 1), int(row['frames'])
    g.anim = (0, 0, 0, (FRAME_MS, FRAME_MS) * g.phases)
    sprites = [0] * (g.w * g.h * g.px * g.py * g.pz * g.phases)
    for (y, x, f), img in pats.items():
        for hh in range(g.h):
            for ww in range(g.w):
                tile = img[(g.h - 1 - hh) * 32:(g.h - hh) * 32, (g.w - 1 - ww) * 32:(g.w - ww) * 32]
                sid = index(tile)
                for z in range(g.pz):
                    sprites[sprite_index(g, x, y, z, 0, f, ww, hh)] = sid
    g.sprites = tuple(sprites)
    return g


def group_frame(g, spr, x, y, z, f):
    import numpy as np
    from datspr import sprite_index
    img = np.zeros((g.h * 32, g.w * 32, 4), np.uint8)
    for hh in range(g.h):
        for ww in range(g.w):
            a = spr.sprite(g.sprites[sprite_index(g, x, y, z, 0, f, ww, hh)])
            if a is not None:
                img[(g.h - 1 - hh) * 32:(g.h - hh) * 32, (g.w - 1 - ww) * 32:(g.w - ww) * 32] = a
    return img


def pair_pictures(dat, spr, row):
    """the pictures a pair holds for a row, in the shape `pictures` gives, or a text saying why not"""
    import numpy as np
    from import_outfits import parse_body
    look = int(row['look'])
    t = dat.outfit(look)
    if t is None:
        return 'look %d (%s) is not in the pair' % (look, row['key'])
    if 'animateAlways' not in t.flags or 'displacement' in t.flags:
        return 'look %d (%s): flags %s: animateAlways and no displacement' % (look, row['key'], sorted(t.flags))
    shape = (int(row['fw']) // 32, int(row['fh']) // 32, 1, 4, 2, int(row['frames']))
    out = None
    for g in parse_body(dat, t):
        if (g.w, g.h, g.layers, g.px, g.py, g.phases) != shape:
            return 'look %d (%s): not the piece shape %s' % (look, row['key'], shape)
        if g.anim is None or tuple(g.anim[3]) != (FRAME_MS, FRAME_MS) * int(row['frames']):
            return 'look %d (%s): frame times' % (look, row['key'])
        for z in range(g.pz):
            got = {(y, x, f): group_frame(g, spr, x, y, z, f) for y in range(2) for x in range(4) for f in range(int(row['frames']))}
            if out is None:
                out = got
            elif any(not np.array_equal(out[k], got[k]) for k in out):
                return 'look %d (%s): its groups or z patterns differ' % (look, row['key'])
    return out


def input_ok(dat, spr, last_item=CLIFF_LAST_ITEM, outfits=INPUT_OUTFITS, cliff=True):
    """None when the pair is pair 82 with the cliff pieces, else why it is refused"""
    if dat.counts[0] != last_item:
        return 'the input items end at %d, the cliff-built pair 82 ends at %d (run gen_cliff_art.py build first)' % (dat.counts[0], last_item)
    if len(dat.outfits) != outfits:
        return 'the input has %d outfits, pair 82 has %d (already built?)' % (len(dat.outfits), outfits)
    if cliff:
        import gen_cliff_art
        bad = gen_cliff_art.live(dat.path, spr.path) if hasattr(dat, 'path') else ['no path']
        if bad:
            return 'the cliff pieces are not those of gen_cliff_art.py: %s' % bad[0]
    return None


def build(dat_path, spr_path, out_dir, src, rows=None, first=FIRST_NEW, last_item=CLIFF_LAST_ITEM, cliff=True, sums=None, log=print):
    """the cliff-built pair 82 -> pair 83 in OUT_DIR (not there yet): the replaced wings looks keep their id, their flags without a
    displacement, their frame groups' type and z patterns, and get the pack pictures; the new looks are appended after the last
    outfit; sprites are only appended. Verified before the rename. `first`, `last_item`, `cliff` are the test's (a synthetic pair)."""
    import numpy as np
    from datspr import Dat, Spr
    from import_outfits import parse_body, build_entry, encode_flags
    from gen_effects import encode_sprite
    rows = load() if rows is None else rows
    sums = read_sums() if sums is None else sums
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    od, ospr = Dat(dat_path), Spr(spr_path)
    od.path, ospr.path = dat_path, spr_path
    assert od.variant[0] == 'new' and all(od.variant[1:]), 'expected our 10.98 dat: %s' % (od.variant,)
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    why = input_ok(od, ospr, last_item, first - 1, cliff)
    if why:
        raise SystemExit('refused: ' + why)
    news = [r for r in rows if not r['design']]
    if [int(r['look']) for r in news] != list(range(first, first + len(news))):
        raise SystemExit('refused: the new looks of the table are not %d.. dense' % first)
    cnt = ospr.count
    newrecs, recs = [], {}

    def index(tile):
        rec = encode_sprite(np.ascontiguousarray(tile))
        if rec is None:
            return 0
        rec = bytes(rec)
        if rec not in recs:
            newrecs.append(rec)
            recs[rec] = cnt + len(newrecs)
        return recs[rec]

    replaced, appended, expect = {}, [], {}
    flags_new = bytes([__import__('import_outfits').NEW_BYTE['animateAlways']])
    for r in rows:
        pats = pictures(src, r)
        look = int(r['look'])
        if look in sums and digest(pats) != sums[look]:
            raise SystemExit('%s %s: the pictures are not those of pack_wear.sums' % (r['cat'], r['key']))
        expect[look] = digest(pats)
        if r['design']:
            t = od.outfit(look)
            if t is None or 'animateAlways' not in t.flags:
                raise SystemExit('outfit %d (%s) is not a wings look of the pair' % (look, r['key']))
            keep = _G()
            keep.flags = {k: v for k, v in t.flags.items() if k != 'displacement'}
            flags, stripped = encode_flags(keep, od.extra)
            if stripped:
                raise SystemExit('outfit %d: flags %s cannot be kept' % (look, stripped))
            groups = [new_group(r, pats, index, g) for g in parse_body(od, t)]
            replaced[look] = build_entry(flags, groups, {s: s for g in groups for s in g.sprites})
        else:
            g = new_group(r, pats, index)
            appended.append(build_entry(flags_new, [g], {s: s for s in g.sprites}))
        log('%-5s %-26s look %d %s' % (r['cat'], r['key'], look, 'in place' if r['design'] else 'new'))
    d = od.data
    ins = od.effects[0].raw[0]
    assert od.outfits[-1].raw[1] == ins
    parts = [bytes(d[:od.outfits[0].raw[0]])]
    for i, t in enumerate(od.outfits):
        parts.append(replaced.get(i + 1) or bytes(d[t.raw[0]:t.raw[1]]))
    parts += appended
    parts.append(bytes(d[ins:]))
    out = bytearray(b''.join(parts))
    struct.pack_into('<H', out, 6, len(od.outfits) + len(appended))
    tmp = out_dir.rstrip('/') + '.tmp'
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    with open(os.path.join(tmp, 'Tibia.dat'), 'wb') as f:
        f.write(out)
    m, nn = ospr.m, len(newrecs)
    toffs = ospr.offs.astype('<u8').copy()
    toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur)
        cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(tmp, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn))
        f.write(table.tobytes())
        pos = 8 + 4 * cnt
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)])
            pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    md, ms = Dat(os.path.join(tmp, 'Tibia.dat')), Spr(os.path.join(tmp, 'Tibia.spr'))
    assert md.variant == od.variant and ms.count == cnt + nn and md.max_sprite <= ms.count
    assert md.counts == (od.counts[0], len(od.outfits) + len(appended), od.counts[2], od.counts[3]), md.counts
    for i, (a, b) in enumerate(zip(od.outfits, md.outfits)):
        if i + 1 not in replaced:
            assert d[a.raw[0]:a.raw[1]] == md.data[b.raw[0]:b.raw[1]], 'outfit %d changed' % (i + 1)
    assert d[:6] == md.data[:6] and d[8:od.outfits[0].raw[0]] == md.data[8:md.outfits[0].raw[0]], 'items changed'
    assert d[ins:] == md.data[md.effects[0].raw[0]:], 'effects or missiles changed'
    for r in rows:
        got = pair_pictures(md, ms, r)
        assert not isinstance(got, str), got
        assert digest(got) == expect[int(r['look'])], 'look %s: pictures differ' % r['look']
    step = max(1, cnt // 3000)
    for sid in list(range(1, cnt + 1, step)) + [cnt]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), sid
    with open(os.path.join(tmp, 'Tibia.dat'), 'rb') as f:
        md5 = hashlib.md5(f.read()).hexdigest()
    os.rename(tmp, out_dir)
    log('verified: %d wings looks drawn in place, %d looks appended %d..%d, %d sprite records appended (%d -> %d); dat md5 %s'
        % (len(replaced), len(appended), first, first + len(appended) - 1, nn, cnt, cnt + nn, md5))
    return md5


def live(dat_path, spr_path, rows=None, sums=None, assets=None, log=print, shifts=None):
    """a built pair holds every piece at its look with the pictures of pack_wear.sums and the north moves of
    pack_wear_shift.csv (O779; the committed table when the rows are the committed ones, else `shifts` when given);
    pending while windows-assets is older than 83"""
    from datspr import Dat, Spr
    own = rows is None
    rows = load() if rows is None else rows
    sums = read_sums() if sums is None else sums
    if assets is None:
        sys.path.insert(0, os.path.join(REPO, 'server', 'tools'))
        import client_pair
        assets = client_pair.PAIR_ASSETS
    dat = Dat(dat_path)
    if len(dat.outfits) < FIRST_NEW and assets < PAIR_OUT:
        log('pending (pair %d, windows-assets has pair %d): the pair has %d outfits, no piece yet' % (PAIR_OUT, assets, len(dat.outfits)))
        return []
    spr = Spr(spr_path)
    bad = []
    for r in rows:
        got = pair_pictures(dat, spr, r)
        if isinstance(got, str):
            bad.append(got)
        elif digest(got) != sums.get(int(r['look'])):
            bad.append('look %s (%s %s): pictures are not those of pack_wear.sums' % (r['look'], r['cat'], r['key']))
    if shifts is None and own:
        shifts = load_shifts()
    if shifts is not None and not bad:
        got = shift_rows(dat, spr, rows, log=log)
        if got != shifts:
            diff = [g['key'] for g, w in zip(got or [], shifts) if g != w] or ['%d rows, the table %d' % (len(got or []), len(shifts))]
            bad.append('pack_wear_shift.csv is not the north move of the pair (%s): run gen_wst_wear.py shifts DAT SPR' % ', '.join(diff[:5]))
    for line in bad:
        log(line)
    log('%d of %d pieces hold their pictures' % (len(rows) - len(bad), len(rows)))
    return bad


# ------------------------------------------------------------------------------------------------ preview
CLASS_BODIES = ('necromancer_m', 'archmage', 'monk_m', 'golden_templar')
BODY_COLUMN = (0, 1, 2, 3)        # class sheet columns: north, east, south, west (64 x 64 cells)


def preview(out_dir, src, rows=None, per_dir=24, log=print):
    """wear_preview.mp4: every imported piece on our class sheets, the pack's composite (back, body lifted by the wing's lift,
    front), pages of 8 x 3, the four directions; frames at 12 a second. Needs ffmpeg."""
    import numpy as np
    from PIL import Image, ImageDraw
    rows = load() if rows is None else rows
    os.makedirs(out_dir, exist_ok=True)
    bodies = {}
    for b in CLASS_BODIES:
        p = os.path.join(CLASS_SHEETS, b + '.png')
        if os.path.isfile(p):
            bodies[b] = Image.open(p).convert('RGBA')
    names = sorted(bodies)
    out = os.path.join(out_dir, 'wear_preview.mp4')
    # the frames go to ffmpeg through a pipe: no frame file on disk
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', '12', '-c:v', 'png', '-i', '-',
                           '-vf', 'scale=-2:720,format=yuv420p', '-crf', '30', '-an', out], stdin=subprocess.PIPE)
    slot, cols, rws, sc = 128, 8, 3, 2
    floor = Image.new('RGBA', (slot, slot), (58, 62, 52, 255))
    fd = ImageDraw.Draw(floor)
    for yy in range(0, slot, 32):
        for xx in range(0, slot, 32):
            if (xx // 32 + yy // 32) % 2:
                fd.rectangle([xx, yy, xx + 31, yy + 31], fill=(66, 70, 58, 255))
    n = 0
    for cat in CATS:
        items = [r for r in rows if r['cat'] == cat]
        pages = [items[i:i + cols * rws] for i in range(0, len(items), cols * rws)]
        pics = {}
        for pi, page in enumerate(pages):
            for r in page:
                if r['key'] not in pics:
                    pics[r['key']] = {k: Image.fromarray(v) for k, v in pictures(src, r).items()}
            for x in range(4):
                for t in range(per_dir):
                    canvas = Image.new('RGBA', (cols * slot, rws * (slot + 12) + 14), (20, 20, 24, 255))
                    cd = ImageDraw.Draw(canvas)
                    for k, r in enumerate(page):
                        p = pics[r['key']]
                        f = t % int(r['frames'])
                        s = floor.copy()
                        tx, ty = slot - 48, slot - 40           # the wearer's tile
                        fx, fy = tx - int(r['ax']) * 32, ty - int(r['ay']) * 32
                        back = p[(0, x, f)]
                        front = p[(1, x, f)]
                        s.alpha_composite(back, (fx, fy))
                        lx, ly = (lift_of(r)[f] if r['cat'] == 'wings' else (0, 0))
                        if names:
                            b = bodies[names[k % len(names)]].crop((BODY_COLUMN[x] * 64, 0, BODY_COLUMN[x] * 64 + 64, 64))
                            s.alpha_composite(b, (tx - 32 + lx, ty - 32 + ly))
                        s.alpha_composite(front, (fx, fy))
                        cx, cy = (k % cols) * slot, 14 + (k // cols) * (slot + 12)
                        canvas.alpha_composite(s, (cx, cy))
                        cd.text((cx + 3, cy + slot), r['name'][:22], fill=(200, 200, 190, 255))
                    cd.text((4, 1), '%s  %d/%d  %s' % (cat, pi + 1, len(pages), 'NESW'[x]), fill=(255, 220, 120, 255))
                    canvas.resize((canvas.width * sc, canvas.height * sc), Image.NEAREST).convert('RGB').save(
                        ff.stdin, 'PNG', compress_level=1)
                    n += 1
        pics.clear()
    ff.stdin.close()
    if ff.wait():
        raise SystemExit('ffmpeg failed')
    log('%s: %d frames' % (out, n))
    return out


# ------------------------------------------------------------------------------------------------ commands
def opt(args, name):
    if name in args:
        i = args.index(name)
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return None


def check(log=print):
    bad = problems()
    rows = load()
    sums = read_sums()
    looks = {int(r['look']) for r in rows}
    if set(sums) != looks:
        bad.append('pack_wear.sums names %d looks, the table %d: run table --src' % (len(sums), len(looks)))
    if len(set(sums.values())) != len(sums):
        bad.append('two pieces have the same pictures')
    bad += shift_problems(rows=rows)
    bad += generated(True, rows)
    for line in bad:
        log(line)
    log('%d pieces (%s)%s' % (len(rows), ', '.join('%d %s' % (sum(1 for r in rows if r['cat'] == c), c) for c in CATS),
                              '' if bad else ': ok'))
    return 1 if bad else 0


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd, args = argv[0], list(argv[1:])
    chk = '--check' in args
    args = [a for a in args if a != '--check']
    src = opt(args, '--src')
    if cmd == 'check':
        return check()
    if cmd == 'ids':
        bad = generated(chk)
        for line in bad:
            print(line)
        return 1 if bad else 0
    if cmd == 'table':
        cur = opt(args, '--curation')
        if not src or not cur:
            print(__doc__)
            return 2
        with open(cur, encoding='utf-8') as f:
            curation = json.load(f)
        rows = table_rows(src, curation)
        bad = write_or_check(TABLE, table_text(rows), chk)
        sums = {int(r['look']): digest(pictures(src, r)) for r in rows}
        bad += write_or_check(SUMS, sums_text(sums), chk)
        bad += problems(rows) + generated(chk, rows)
        for line in bad:
            print(line)
        print('%d pieces%s' % (len(rows), '' if bad else ': ok'))
        return 1 if bad else 0
    if cmd == 'build':
        if len(args) != 3 or not src:
            print(__doc__)
            return 2
        build(args[0], args[1], args[2], src)
        return 0
    if cmd == 'live':
        if len(args) != 2:
            print(__doc__)
            return 2
        return 1 if live(args[0], args[1]) else 0
    if cmd == 'shifts':
        if len(args) != 2:
            print(__doc__)
            return 2
        from datspr import Dat, Spr
        srows = shift_rows(Dat(args[0]), Spr(args[1]))
        if srows is None:
            return 1
        bad = write_or_check(SHIFTS, shift_text(srows), chk)
        bad += shift_problems(srows)
        if not bad:
            bad += generated(chk)
        for line in bad:
            print(line)
        hang = sorted(float(r['hang']) for r in srows)
        print('%d pack wings: north minus south %.1f to %.1f px before, moved %d to %d px up%s' % (
            len(srows), hang[0], hang[-1], min(-int(r['dy']) for r in srows), max(-int(r['dy']) for r in srows), '' if bad else ': ok'))
        return 1 if bad else 0
    if cmd == 'preview':
        if len(args) != 1 or not src:
            print(__doc__)
            return 2
        preview(args[0], src)
        return 0
    raise SystemExit('unknown command %s' % cmd)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
