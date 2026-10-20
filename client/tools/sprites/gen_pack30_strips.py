#!/usr/bin/env python3
"""Pair 30: the single-facing animated creature strips become 4-direction outfits and corpse items (PLAN_PAIR30 3.2).

    python3 -I gen_pack30_strips.py build --src DRIVEPACKS            # cut the sheets, write the tables
    python3 -I gen_pack30_strips.py build --src DRIVEPACKS --check    # rebuild in memory and compare with the repo and the disk
    python3 -I gen_pack30_strips.py build --check                     # CI, no sources: tables agree with the file list

Needs numpy and Pillow (CI: the fx venv). The packs ban machine-learning use and sharing: this script only reads
file names, md5s, sizes, alpha boxes (geometry) and copies pixels; nobody views, measures or samples a palette from a
pack image. The cut sheets (art_import/pack30_strips/, ignored by git) never enter the repo; committed are
art_import/pack30_strips.csv (things file for import_art_things.py), pack30_strips.sums, pack30_strips_sources.csv
and the existing pack30_strips.files. `DRIVEPACKS` is the folder of the extracted packs; the folder of each pack
slug comes from the ignored art_import/pack30_packs.private.csv.

Creatures. A strip is `<creature>_<anim>_strip<N>.png`: N square frames side by side, one facing, side view
presumed. The file name (lower case, a leading `spr_` dropped) gives the creature and the animation: idle, walk,
pray, death are used; attack, hit, take_dmg, bite, sick and walk_death are not (a 10.98 outfit has an idle and a
walking frame group only) and are counted in the report. ALIASES merges two spellings of one creature. A creature
needs an idle or a walk strip; a missing one reuses the other in both frame groups (squid: idle only). Each creature
with a `pray` strip gets a second outfit `<key>_pray` (idle and walk group both the pray frames, for ritual NPCs).
Each creature with a `death` strip gets a corpse item `<key>_corpse` from the LAST death frame.

Layout. Frame cell C = strip height. One union alpha box over every used frame (both orientations, same size);
the box is placed with its right edge and bottom edge 1 px inside a canvas of S x S tiles, the same shift in every
frame and direction (no jitter, the pack anchor is not used). S = the smallest edge holding box + 1 px, at most the
tiles of C (a full-cell box then keeps the source size and no margin). 64 px cells give 2x2, 32 px 1x1, 128 px 4x4.
Directions (dat order n, e, s, w): east is the strip as drawn (face `r`, the default) and west its mirror; north
reuses east and south reuses west. One group of frames, one layer, 110 ms a phase (no timing in these packs).

Overrides (art_import/pack30_overrides.csv, key = `<pack slug>__<creature>`, `<key>_pray` falls back to the base
key): `flip` 1 swaps east and west (the strip faces left), `ns` e|w takes north and south from the other
orientation, `dx` `dy` shift the box, `tiles` N or WxH sets the outfit size, `rename` the name, `skip` 1 drops the
outfit (and its corpse; later ids move up, so only before the pair is pushed).

Blocks: outfits 2312-2431 (120), corpse items 34834-34858 (25); more stops the build. Order: pack fit (high,
medium, low), pack slug, creature, with the pray outfit right after its creature.

Import (client/MANIFEST.md "Pack strips (pair 30)"), after the pair-29 items and the sheet looks:
    python3 -I import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \\
        --things art_import/pack30_strips.csv --first-item 34834 --first-outfit 2312 --expect-items <items before>
"""
import argparse
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack30lib as P  # noqa: E402

ART = P.ART
CAT = 'strips'
OUT = os.path.join(ART, 'pack30_strips')
ATLAS_DIR = 'pack30_strips'
THINGS = os.path.join(ART, 'pack30_strips.csv')
SUMS = os.path.join(ART, 'pack30_strips.sums')
SOURCES = os.path.join(ART, 'pack30_strips_sources.csv')
GITIGNORE_TEXT = ('# strips cut from the purchased creature packs: not to be redistributed, never committed '
                  '(gen_pack30_strips.py)\n*\n!.gitignore\n')

FIRST_OUTFIT, MAX_OUTFITS = 2312, 120
FIRST_CORPSE, MAX_CORPSES = 34834, 25
MS = P.fps_to_ms(None)            # 110 ms a phase: the packs carry no timing
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']
SOURCES_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']
LICENCE = ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
           'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md')
CORPSE_FLAGS = 'container forceuse notmoveable'     # the flags of a stock corpse item
USED = ('idle', 'walk', 'pray', 'death')
ANIMS = ('walk_death', 'take_dmg', 'idle', 'walk', 'attack', 'death', 'hit', 'pray', 'bite', 'sick')
ALIASES = {'pumpkin_headed': 'pumpkin_headed_monster'}   # one pack spells a creature two ways
FIT_RANK = {'high': 0, 'medium': 1, 'low': 2}
NAME_RE = re.compile(r'^(?P<name>.+?)_(?P<anim>%s)_strip(?P<n>\d+)\.png$' % '|'.join(ANIMS))


class Look:
    """one outfit: where its frames come from."""

    def __init__(self, slug, key, name, fit, idle, walk, death, pray=False):
        self.slug, self.key, self.name, self.fit = slug, key, name, fit
        self.idle, self.walk, self.death, self.pray = idle, walk, death, pray
        self.cell = None


# ------------------------------------------------------------------------------------------------ names
def parse_name(path):
    """'Goblin_Shaman_idle_strip9.png' -> ('goblin_shaman', 'idle', 9) or None (not a creature strip)."""
    base = os.path.basename(path).lower()
    if base.startswith('spr_'):
        base = base[4:]
    m = NAME_RE.match(base)
    if not m:
        return None
    name = P.slugify(m.group('name'))
    return ALIASES.get(name, name), m.group('anim'), int(m.group('n'))


def strip_cell(row):
    """frame edge of a strip file: the frames are squares, N of them side by side."""
    got = parse_name(row.path)
    if got is None:
        raise P.PackError('%s/%s: not a strip name' % (row.slug, row.path))
    n = got[2]
    w, h = int(row.w), int(row.h)
    if n < 1 or w % n or w // n != h:
        raise P.PackError('%s/%s: %dx%d is not %d square frames' % (row.slug, row.path, w, h, n))
    return h


def plan(rows, packs):
    """Looks and corpses from the file list alone (names, no pixels).

    Returns (looks, corpses, report): looks in id order, corpses = [Look] with a death strip in the same order,
    report = {'unused': [paths of attack/hit/... strips], 'unmatched': [paths that are no strip name]}."""
    strips = {p.slug: p for p in P.packs_for(packs, CAT)}
    groups, unused, unmatched = {}, [], []
    for r in rows:
        if r.slug not in strips or not r.path.lower().endswith('.png'):
            continue
        got = parse_name(r.path)
        if got is None:
            unmatched.append('%s/%s' % (r.slug, r.path))
            continue
        name, anim, _n = got
        if anim not in USED:
            unused.append('%s/%s' % (r.slug, r.path))
            continue
        g = groups.setdefault((r.slug, name), {})
        if anim in g:
            raise P.PackError('%s: two %s strips for %s (%s, %s)' % (r.slug, anim, name, g[anim].path, r.path))
        strip_cell(r)
        g[anim] = r
    looks = []
    for (slug, name), g in groups.items():
        fit = strips[slug].fit
        idle, walk = g.get('idle') or g.get('walk'), g.get('walk') or g.get('idle')
        key = P.key_of(slug, name)
        if idle is None:
            # only a pray and/or death strip: no body to animate, nothing to build
            unmatched.append('%s/%s (no idle or walk strip)' % (slug, name))
            continue
        cells = {strip_cell(x) for x in (idle, walk)}
        if len(cells) != 1:
            raise P.PackError('%s: idle and walk strips of different frame sizes' % key)
        looks.append(Look(slug, key, P.humanize(name), fit, idle, walk, g.get('death')))
        if 'pray' in g:
            pr = g['pray']
            looks.append(Look(slug, key + '_pray', P.humanize(name) + ' (praying)', fit, pr, pr, None, pray=True))
    looks.sort(key=lambda lk: (FIT_RANK.get(lk.fit, 1), lk.slug, lk.key[:-5] if lk.pray else lk.key, lk.pray))
    return looks, unused, unmatched


def apply_overrides(looks, ov):
    """skip / rename; the pray look falls back to the key of its creature."""
    out = []
    for lk in looks:
        base = lk.key[:-5] if lk.pray else lk.key
        if P.ov_get(ov, lk.key, 'skip', P.ov_get(ov, base, 'skip', 0)):
            continue
        name = P.ov_get(ov, lk.key, 'rename', None)
        if name is None and not lk.pray:
            name = P.ov_get(ov, base, 'rename', None)
        if name:
            lk.name = name
        out.append(lk)
    corpses = [lk for lk in out if not lk.pray and lk.death is not None]
    if len(out) > MAX_OUTFITS:
        raise P.PackError('%d outfits, the block 2312-2431 holds %d' % (len(out), MAX_OUTFITS))
    if len(corpses) > MAX_CORPSES:
        raise P.PackError('%d corpses, the block 34834-34858 holds %d' % (len(corpses), MAX_CORPSES))
    return out, corpses


def ov_of(ov, key, action, default=None):
    """override of a look; `<key>_pray` falls back to the base key."""
    v = P.ov_get(ov, key, action, None)
    if v is None and key.endswith('_pray'):
        v = P.ov_get(ov, key[:-5], action, None)
    return default if v is None else v


# ------------------------------------------------------------------------------------------------ pixels
def cut_frames(a, row):
    n = parse_name(row.path)[2]
    fr = P.strip_frames(P.clean_alpha(a), a.shape[0])
    if len(fr) != n:
        raise P.PackError('%s/%s: %d frames, the name says %d' % (row.slug, row.path, len(fr), n))
    return fr


def edge_tiles(box, cell, margin=1):
    """(tiles, margin): smallest square edge holding box + margin, at most the tiles of the source cell."""
    cap = P.tiles_of_px(cell)
    try:
        s = P.fit_tiles(box[2] - box[0], box[3] - box[1], margin=margin, hi=cap)
        return s, margin
    except P.PackError:
        if margin:
            return cap, 0
        raise


def mirrored_box(box, cell):
    return (cell - box[2], box[1], cell - box[0], box[3])


def sheet_of(idle, walk, face='r', flip=0, ns='e', dx=0, dy=0, tiles=None):
    """The outfit sheet for frame lists idle and walk (arrays of one cell size).

    Returns (sheet, tw, th, margin): rows = idle phases then walk phases, columns = n, e, s, w, each cell
    tw x th tiles."""
    cell = idle[0].shape[0]
    used = idle + [f for f in walk if all(f is not g for g in idle)]
    mir = [P.mirror(f) for f in used]
    box_d, box_m = P.union_bbox(used), P.union_bbox(mir)
    if box_d is None:
        raise P.PackError('a strip without a single visible pixel')
    if tiles:
        tw, th, margin = tiles[0], tiles[1], 1
        need = max(box_d[2] - box_d[0] + margin, box_d[3] - box_d[1] + margin)
        if need > 32 * min(tw, th):
            margin = 0
    else:
        s, margin = edge_tiles(box_d, cell)
        tw = th = s
    place = lambda f, box: P.place_bottom_right(f, box, tw, th, margin=margin, dx=dx, dy=dy)  # noqa: E731
    right = (face == 'r') != bool(flip)
    drawn = {id(f): place(f, box_d) for f in used}
    mirr = {id(f): place(P.mirror(f), box_m) for f in used}
    east, west = (drawn, mirr) if right else (mirr, drawn)
    north, south = (east, west) if ns == 'e' else (west, east)
    rows = []
    for fr in idle + walk:
        k = id(fr)
        rows.append(np.concatenate([north[k], east[k], south[k], west[k]], axis=1))
    return np.concatenate(rows, axis=0), tw, th, margin


def corpse_of(frame):
    """item canvas from the last death frame, as drawn: (canvas, tiles)"""
    cell = frame.shape[0]
    box = P.alpha_bbox(frame)
    if box is None:
        raise P.PackError('a death strip without a visible last frame')
    s, margin = edge_tiles(box, cell)
    return P.place_bottom_right(frame, box, s, s, margin=margin), s


# ------------------------------------------------------------------------------------------------ tables
def durs(n):
    return '/'.join('%d:%d' % (MS, MS) for _ in range(n))


def row_dict(**kw):
    d = {f: '' for f in FIELDS}
    d.update(kw)
    return d


def outfit_extra(lk, ni, nw, w, h):
    parts = ['layers=1', 'gtypes=0+1', 'exact=%d+%d' % (32 * max(w, h), 32 * max(w, h))]
    for g, n in ((0, ni), (1, nw)):
        if n > 1:
            parts.append('durs%d=%s' % (g, durs(n)))
    for g, n in ((0, ni), (1, nw)):
        if n > 1:
            parts.append('anim%d=0:0:0' % g)
    parts.append('family=' + lk.slug)
    return '|'.join(parts)


def strip_n(row):
    return parse_name(row.path)[2]


def things_rows(looks, corpses, sizes):
    """sizes {key: (w, h)} (tiles) of every outfit and `<key>_corpse` item."""
    rows = []
    for lk in looks:
        w, h = sizes[lk.key]
        ni, nw = strip_n(lk.idle), strip_n(lk.walk)
        rows.append(row_dict(key=lk.key, cat='outfit', kind='creature', name=lk.name, atlas='%s/%s' % (ATLAS_DIR, lk.key),
                             x=0, y=0, w=w, h=h, patterns=4, phases='%d+%d' % (ni, nw), mode='new',
                             extra=outfit_extra(lk, ni, nw, w, h)))
    for lk in corpses:
        key = lk.key + '_corpse'
        w, h = sizes[key]
        rows.append(row_dict(key=key, cat='item', kind='corpse', name='dead ' + lk.name.lower(),
                             atlas='%s/%s' % (ATLAS_DIR, key), x=0, y=0, w=w, h=h, patterns=1, phases=1,
                             flags=CORPSE_FLAGS, mode='new', extra='family=' + lk.slug))
    return rows


def things_text(rows):
    return P.csv_text(FIELDS, [[r[f] for f in FIELDS] for r in rows])


def sources_text(looks, corpses, packs):
    label = {p.slug: p.label for p in packs}
    rows = []
    for lk in looks:
        files = [lk.idle] if lk.idle is lk.walk else [lk.idle, lk.walk]
        for f in files:
            rows.append([lk.key, 'outfit', label[lk.slug], '%s/%s' % (f.slug, f.path), LICENCE])
    for lk in corpses:
        rows.append([lk.key + '_corpse', 'corpse', label[lk.slug], '%s/%s' % (lk.death.slug, lk.death.path), LICENCE])
    return P.csv_text(SOURCES_FIELDS, rows)


# ------------------------------------------------------------------------------------------------ build
def render(looks, corpses, load, ov, face_of=None):
    """{atlas name: sheet array} and {key: (w, h)}; load(FileRow) -> RGBA array."""
    sheets, sizes = {}, {}
    cache = {}

    def frames(row):
        k = (row.slug, row.path)
        if k not in cache:
            cache[k] = cut_frames(load(row), row)
        return cache[k]

    for lk in looks:
        idle = frames(lk.idle)
        walk = idle if lk.walk is lk.idle else frames(lk.walk)
        if walk is not idle and walk[0].shape[0] != idle[0].shape[0]:
            raise P.PackError('%s: idle and walk frames differ in size' % lk.key)
        face = face_of(lk) if face_of else 'r'
        tiles = ov_of(ov, lk.key, 'tiles')
        sheet, tw, th, _m = sheet_of(list(idle), list(walk) if walk is not idle else list(idle), face=face,
                                     flip=ov_of(ov, lk.key, 'flip', 0), ns=ov_of(ov, lk.key, 'ns', 'e'),
                                     dx=ov_of(ov, lk.key, 'dx', 0), dy=ov_of(ov, lk.key, 'dy', 0), tiles=tiles)
        sheets[lk.key] = sheet
        sizes[lk.key] = (tw, th)
    for lk in corpses:
        last = frames(lk.death)[-1]
        canvas, s = corpse_of(last)
        sheets[lk.key + '_corpse'] = canvas
        sizes[lk.key + '_corpse'] = (s, s)
    return sheets, sizes


def sums_of(sheets):
    return P.sums_text([('%s/%s.png' % (ATLAS_DIR, k), sheets[k]) for k in sorted(sheets)])


def make_load(src, private):
    def load(row):
        return P.load_verified(P.source_path(src, row.slug, row.path, private), row.md5)
    return load


def write_sheets(sheets, out=OUT):
    os.makedirs(out, exist_ok=True)
    gi = os.path.join(out, '.gitignore')
    if not os.path.isfile(gi) or open(gi, encoding='utf-8').read() != GITIGNORE_TEXT:
        with open(gi, 'w', encoding='utf-8', newline='') as f:
            f.write(GITIGNORE_TEXT)
    for k in sorted(sheets):
        Image.fromarray(sheets[k], 'RGBA').save(os.path.join(out, k + '.png'))


def disk_problems(sheets, out=OUT):
    """sheets on disk that differ from `sheets` (a missing file is fine: CI has none)."""
    bad = []
    for k in sorted(sheets):
        p = os.path.join(out, k + '.png')
        if os.path.isfile(p):
            a = np.asarray(Image.open(p).convert('RGBA'))
            if P.digest(a) != P.digest(sheets[k]):
                bad.append('%s differs from the rebuilt sheet' % p)
    return bad


def load_plan():
    packs = P.load_packs()
    rows = P.read_files(P.files_path(CAT))
    ov = P.load_overrides()
    looks, unused, unmatched = plan(rows, packs)
    looks, corpses = apply_overrides(looks, ov)
    return packs, ov, looks, corpses, unused, unmatched


def check_structure(looks, corpses, packs, out=OUT):
    """Everything that needs no pixels: the committed tables against the plan from the file list."""
    bad = []
    if not os.path.isfile(THINGS):
        return ['%s: missing (run build --src)' % THINGS]
    import csv
    with open(THINGS, newline='', encoding='utf-8') as f:
        rd = csv.DictReader(f)
        if rd.fieldnames != FIELDS:
            return ['%s: header must be %s' % (THINGS, ','.join(FIELDS))]
        spec = list(rd)
    want = [('outfit', lk.key, lk.name, '%s/%s' % (ATLAS_DIR, lk.key), '%d+%d' % (strip_n(lk.idle), strip_n(lk.walk)))
            for lk in looks]
    want += [('item', lk.key + '_corpse', 'dead ' + lk.name.lower(), '%s/%s_corpse' % (ATLAS_DIR, lk.key), '1')
             for lk in corpses]
    got = [(r['cat'], r['key'], r['name'], r['atlas'], r['phases']) for r in spec]
    if got != want:
        bad.append('%s: keys, names or phases differ from the plan of pack30_strips.files (run build --src)' % THINGS)
        return bad
    nout = nitem = 0
    for r in spec:
        try:
            w, h = int(r['w']), int(r['h'])
        except ValueError:
            bad.append('%s: size of %s' % (THINGS, r['key']))
            continue
        if not (1 <= w <= P.MAX_TILES and 1 <= h <= P.MAX_TILES):
            bad.append('%s: %s is %dx%d tiles' % (THINGS, r['key'], w, h))
        if r['cat'] == 'outfit':
            nout += 1
            lk = next(x for x in looks if x.key == r['key'])
            exp = outfit_extra(lk, strip_n(lk.idle), strip_n(lk.walk), w, h)
            if r['extra'] != exp or r['patterns'] != '4' or r['flags'] or r['mode'] != 'new':
                bad.append('%s: row %s differs from the layout rule' % (THINGS, r['key']))
        else:
            nitem += 1
            if r['flags'] != CORPSE_FLAGS or r['patterns'] != '1' or r['kind'] != 'corpse' or r['mode'] != 'new':
                bad.append('%s: corpse %s differs from the rule' % (THINGS, r['key']))
    if FIRST_OUTFIT + nout - 1 > FIRST_OUTFIT + MAX_OUTFITS - 1 or nitem > MAX_CORPSES:
        bad.append('block overflow')
    if not os.path.isfile(SOURCES) or open(SOURCES, encoding='utf-8').read() != sources_text(looks, corpses, packs):
        bad.append('%s differs from the plan (run build --src)' % SOURCES)
    keys = [r['atlas'] for r in spec]
    if not os.path.isfile(SUMS):
        bad.append('%s: missing' % SUMS)
    else:
        lines = open(SUMS, encoding='utf-8').read().splitlines()
        paths = [ln.split('  ', 1)[1] for ln in lines if '  ' in ln]
        if paths != sorted(k + '.png' for k in keys):
            bad.append('%s: paths differ from the things file' % SUMS)
        for ln in lines:
            dg, _, path = ln.partition('  ')
            f = os.path.join(ART, path)
            if os.path.isfile(f):
                a = np.asarray(Image.open(f).convert('RGBA'))
                if P.digest(a) != dg:
                    bad.append('%s differs from %s' % (f, SUMS))
    gi = os.path.join(out, '.gitignore')
    if not os.path.isfile(gi) or open(gi, encoding='utf-8').read() != GITIGNORE_TEXT:
        bad.append('%s: missing or changed' % gi)
    return bad


def cmd_build(src, check):
    packs, ov, looks, corpses, unused, unmatched = load_plan()
    print('creatures: %d outfits (ids %d..%d), %d corpses (ids %d..%d); %d strips not used (attack, hit, ...), '
          'unmatched: %s' % (len(looks), FIRST_OUTFIT, FIRST_OUTFIT + len(looks) - 1, len(corpses), FIRST_CORPSE,
                             FIRST_CORPSE + len(corpses) - 1, len(unused), ', '.join(unmatched) or 'none'))
    bad = []
    if src is None:
        if not check:
            sys.exit('build needs --src DRIVEPACKS (or --check for the source-free check)')
        bad = check_structure(looks, corpses, packs)
    else:
        private = P.load_private()
        sheets, sizes = render(looks, corpses, make_load(src, private), ov)
        rows = things_rows(looks, corpses, sizes)
        texts = {THINGS: things_text(rows), SOURCES: sources_text(looks, corpses, packs), SUMS: sums_of(sheets)}
        if check:
            for path, text in texts.items():
                if not os.path.isfile(path) or open(path, encoding='utf-8').read() != text:
                    bad.append('%s differs from the rebuild' % path)
            bad += disk_problems(sheets)
            bad += check_structure(looks, corpses, packs) if not bad else []
        else:
            write_sheets(sheets)
            for path, text in texts.items():
                with open(path, 'w', encoding='utf-8', newline='') as f:
                    f.write(text)
            print('wrote %d sheets to %s, %s, %s, %s' % (len(sheets), OUT, THINGS, SUMS, SOURCES))
            bad = check_structure(looks, corpses, packs)
    for b in bad:
        print('FAIL', b)
    if bad:
        return 1
    print('ok')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src', default=None, help='the drivepacks folder')
    b.add_argument('--check', action='store_true')
    a = ap.parse_args()
    try:
        return cmd_build(a.src, a.check)
    except P.PackError as e:
        print('STOP', e)
        return 2


if __name__ == '__main__':
    sys.exit(main())
