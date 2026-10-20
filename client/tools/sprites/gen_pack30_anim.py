#!/usr/bin/env python3
"""Pair 30, animated objects: portals, fires and torches, animated trees, volcanoes, towers, ships and other animated
decoration cut from the purchased packs, as item ids 36459..36758 (client; server ids + 3000). PLAN_PAIR30 3.5.

    python3 -I gen_pack30_anim.py build --src DRIVEPACKS            # -> art_import/pack30_anim/<pack slug>.png
                                                                    #    + art_import/pack30_anim.csv, .sums
                                                                    #    + art_import/pack30_anim_sources.csv
    python3 -I gen_pack30_anim.py build --src DRIVEPACKS --check    # rebuild in memory, compare with everything
    python3 -I gen_pack30_anim.py build --check                     # CI, no packs: tables agree with each other and
                                                                    #    with pack30_anim.files; atlases on disk (if
                                                                    #    any) match the sums

Needs numpy and Pillow (CI: the fx venv). Import-only (PLAN_PAIR30 section 0, docs/SPRITE_STYLE.md): the packs ban
machine-learning use and sharing. No pack image is viewed, style-measured, palette-sampled or given to an AI tool; this
script reads pixels only to copy them and for one geometry fact (which cut pieces are fully empty). Neither the packs nor
the cut atlases are committed (art_import/pack30_anim/ is ignored by git); the sums hold the sha256 of every atlas.

What is cut (file-name and size rules, no image is looked at). An animated object is a `<name>_strip<N>.png` file: N frames
side by side (frame width = file width / N), N >= 2, one item with N phases. Not taken: the animated floors of
gen_pack30_grounds.ANIM_FILE (lava, lake and sewer water; that generator owns them) and the attack, death and hit strips
(reported). Frames whose size is no multiple of 32 are padded top and left, bottom-right aligned, never scaled (a 92 px
frame becomes 96, a 68 x 128 frame 96 x 128). A picture of up to 4 x 4 tiles is one item. A larger one (volcanoes,
the windmill and keep, the big portals) is cut by pack30lib.plan_split into pieces of at most 4 x 4 tiles, each its own item
`<key>_r<row>c<col>` with extra `group=<key>|gw=|gh=|piece=r,c`; every piece has the same phase count and the same ms, so
the pieces stay in step; a piece that is empty in every phase is dropped. Phase ms: fires, torches, candles and lights 100,
portals 120, the rest 140 (the packs carry no timing). All items are kind `decor`, `stump` or `wall`:
  stump  blocks the tile (trees, mushrooms, volcanoes, towers, ships, altars, barrels): `bottom notwalkable notmoveable`;
         of a split group only the south-east piece blocks, the others are `decor` (the map maker adds blockers)
  wall   hangs on a wall (wall candles, wall lights, vents, fans, ceiling lights): `hangable notmoveable`
  decor  everything else: `notmoveable`
Every item carries `animateAlways`. Light: portals, fires, torches, candles, lamps, lights and volcanoes get the dat light
flag `light:<level>:<colour>` (LIGHT_RULES; the colour index by the element word of the file name, COLOUR_WORDS: fire, lava
and volcano 207, ice 143, void and dark 164, holy 215, nature 130, lightning 191, default 208). A split group carries the light on
its last (south-east) piece only, so the lights do not add up.
Overrides (art_import/pack30_overrides.csv, key = `<pack slug>__<stem>`; a piece key `<key>_r<row>c<col>` accepts skip):
skip, rename, kind (decor|stump|wall), blocking (0|1), flags (verbatim, animateAlways is appended), light (level:colour,
level 0 = no light).
Ids: an item's id is 36459 + its place in the plan order (pack slug, file path, piece row-major); more than the block holds
(300) stops the build with an error (the integrator then moves the overflow, PLAN_PAIR30 section 2).

Import (client/MANIFEST.md "Pack animated objects (pair 30)"):
    python3 -I import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \\
        --things art_import/pack30_anim.csv --first-item 36459 --expect-items 34442 (or the item count before)
Deterministic: numpy and Pillow only; same inputs give byte-identical tables.
"""
import argparse
import csv
import io
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack30_grounds as G  # noqa: E402  (ANIM_FILE: the animated floors that are not ours; LICENCE)
import pack30lib as P  # noqa: E402

CAT = 'anim'
FIRST_ID = 36459
BLOCK = 300
LAST_ID = FIRST_ID + BLOCK - 1          # 36758
ART = P.ART
OUT_DIR = os.path.join(ART, 'pack30_anim')
SPEC = os.path.join(ART, 'pack30_anim.csv')
SUMS = os.path.join(ART, 'pack30_anim.sums')
SOURCES_CSV = os.path.join(ART, 'pack30_anim_sources.csv')
ATLAS_DIR = 'pack30_anim'
GITIGNORE_TEXT = ('# animated objects cut from the purchased packs: not to be redistributed, never committed '
                  '(gen_pack30_anim.py)\n*\n!.gitignore\n')
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
SOURCE_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']
LICENCE = G.LICENCE
KINDS = ('decor', 'stump', 'wall')
FLAG_WORDS = ('bottom', 'notwalkable', 'notmoveable', 'hangable', 'light', 'animateAlways', 'clip', 'ground', 'minimap',
              'fullground')
STUMP_FLAGS = 'bottom notwalkable notmoveable'
DEFAULT_LIGHT_COLOUR = 208

STRIP = re.compile(r'^(?P<stem>.+)_strip(?P<n>\d+)\.png$', re.I)
UNUSED = re.compile(r'(^|_)(attack|death|hit|die)(_|$)')
WALL = re.compile(r'(wall_candle|wall_light|wall_eyes|wall_hole|wall_pip|ceiling_light|(^|_)vent(_|$)|(^|_)fan(_|$))')
BLOCKING = re.compile(r'(tree|mushroom|volcano|windmill|keep|tower|ship|boat|altar|barrel|squid|statue)')
# (file name pattern, light level, level when the picture is 4 tiles or more): the first match wins
LIGHT_RULES = (
    (re.compile(r'portal'), 3, 4),
    (re.compile(r'volcano'), 5, 5),
    (re.compile(r'fire'), 3, 3),
    (re.compile(r'torch'), 2, 2),
    (re.compile(r'candle'), 2, 2),
    (re.compile(r'lamp|lantern'), 3, 3),
    (re.compile(r'light'), 3, 3),
    (re.compile(r'cooking_pot'), 2, 2),
)
COLOUR_WORDS = {'fire': 207, 'lava': 207, 'volcano': 207, 'ice': 143, 'frost': 143, 'void': 164, 'dark': 164, 'holy': 215,
                'nature': 130, 'lighting': 191, 'lightning': 191}
# phase ms by file name (first match), else MS_DEFAULT
MS_RULES = ((re.compile(r'fire|torch|candle|lamp|lantern|light|cooking_pot'), 100), (re.compile(r'portal'), 120))
MS_DEFAULT = 140


class Obj:
    """one animated picture of a pack file and the items it becomes"""

    def __init__(self, row, stem, key, n):
        self.row, self.slug, self.path, self.stem, self.key, self.n = row, row.slug, row.path, stem, key, n
        self.fw, self.fh = int(row.w) // n, int(row.h)
        self.gw, self.gh = P.tiles_of_px(self.fw), P.tiles_of_px(self.fh)
        pieces = P.plan_split(self.gw, self.gh)
        self.group = len(pieces) > 1
        self.pieces = pieces
        self.ms = ms_of(stem)
        self.name = ''
        self.label = ''

    def piece_key(self, piece):
        return P.piece_key(self.key, piece) if self.group else self.key


class Item:
    def __init__(self, obj, piece, frames):
        self.obj, self.piece, self.frames = obj, piece, frames
        self.key = obj.piece_key(piece)
        self.kind = self.flags = self.name = ''
        self.y = 0


def ms_of(stem):
    for rx, ms in MS_RULES:
        if rx.search(stem):
            return ms
    return P.fps_to_ms(None, MS_DEFAULT)


def stem_of(path):
    base = path.rsplit('/', 1)[-1]
    m = STRIP.match(base)
    s = P.slugify(m.group('stem') if m else base.rsplit('.', 1)[0])
    return re.sub(r'^spr?_', '', s)


def light_of(obj, ov):
    """(level, colour) or None"""
    o = P.ov_get(ov, obj.key, 'light')
    if o is not None:
        return o if o[0] > 0 else None
    big = max(obj.gw, obj.gh) >= 4
    for rx, lo, hi in LIGHT_RULES:
        if rx.search(obj.stem):
            level = hi if big else lo
            colour = DEFAULT_LIGHT_COLOUR
            for tok in obj.stem.split('_'):
                if tok in COLOUR_WORDS:
                    colour = COLOUR_WORDS[tok]
                    break
            return level, colour
    return None


def kind_of(obj, ov):
    k = P.ov_get(ov, obj.key, 'kind')
    if k is not None:
        if k not in KINDS:
            raise P.PackError('%s: kind override %r not one of %s' % (obj.key, k, ', '.join(KINDS)))
    else:
        k = 'wall' if WALL.search(obj.stem) else 'stump' if BLOCKING.search(obj.stem) else 'decor'
    b = P.ov_get(ov, obj.key, 'blocking')
    if b is not None and k != 'wall':
        k = 'stump' if b == 1 else 'decor'
    return k


# ------------------------------------------------------------------------------------------------ the plan (names only)
def plan(rows, packs, ov=None):
    """Objects from the file list alone. -> (objs in id order, report {'unused': [...], 'floors': [...], 'static': n})."""
    ov = {} if ov is None else ov
    ready = {p.slug: p for p in P.packs_for(packs, CAT)}
    objs, keys = [], {}
    rep = {'unused': [], 'floors': [], 'static': 0}
    for r in sorted(rows, key=lambda r: (r.slug, r.path.lower(), r.path)):
        if r.slug not in ready or not r.path.lower().endswith('.png'):
            continue
        m = STRIP.match(r.path.rsplit('/', 1)[-1])
        if not m:
            rep['static'] += 1
            continue
        if G.ANIM_FILE.search(r.path):
            rep['floors'].append('%s/%s' % (r.slug, r.path))
            continue
        stem = stem_of(r.path)
        if UNUSED.search(stem):
            rep['unused'].append('%s/%s' % (r.slug, r.path))
            continue
        n, w = int(m.group('n')), int(r.w)
        if n < 2 or w % n or not int(r.h):
            raise P.PackError('%s/%s: %dx%d is not %d whole frames' % (r.slug, r.path, w, int(r.h), n))
        key = P.key_of(r.slug, stem)
        if key in keys:             # two files with one stem: add the folder
            parent = P.slugify(r.path.rsplit('/', 1)[0]) if '/' in r.path else 'x'
            key = P.key_of(r.slug, parent + '_' + stem)
        if key in keys:
            raise P.PackError('%s: two objects with one key (rename one with an override)' % key)
        keys[key] = True
        if P.ov_get(ov, key, 'skip') == 1:
            continue
        o = Obj(r, stem, key, n)
        o.label = ready[r.slug].label
        o.name = P.ov_get(ov, key, 'rename') or '%s (%s)' % (P.humanize(stem), P.humanize(r.slug))
        objs.append(o)
    return objs, rep


# ------------------------------------------------------------------------------------------------ pixels
def cut(obj, load):
    """the padded frames of an object: [array of gh*32 x gw*32]"""
    a = P.clean_alpha(load(obj.row))
    if a.shape[1] != int(obj.row.w) or a.shape[0] != obj.fh:
        raise P.PackError('%s/%s: the file is %dx%d, the list says %sx%s' % (obj.slug, obj.path, a.shape[1], a.shape[0],
                                                                           obj.row.w, obj.row.h))
    fr = [P.pad_to_tile(f) for f in P.strip_frames(a, obj.fw, obj.fh)]
    if len(fr) != obj.n:
        raise P.PackError('%s/%s: %d frames, the name says %d' % (obj.slug, obj.path, len(fr), obj.n))
    if not any(f[..., 3].any() for f in fr):
        raise P.PackError('%s/%s: not a single visible pixel' % (obj.slug, obj.path))
    return fr


def flags_for(item, last, ov, light):
    obj = item.obj
    custom = P.ov_get(ov, obj.key, 'flags')
    if custom:
        toks = custom.split()
        return item.kind, ' '.join(toks + ([] if 'animateAlways' in toks else ['animateAlways']))
    toks = {'stump': STUMP_FLAGS.split(), 'wall': ['hangable', 'notmoveable'], 'decor': ['notmoveable']}[item.kind]
    toks = list(toks)
    if light and last:
        toks.append('light:%d:%d' % light)
    toks.append('animateAlways')
    return item.kind, ' '.join(toks)


def collect(rows, packs, load, ov):
    """Cut every object into items. -> (items in id order, objs, report). Stops on an overflow of the block."""
    objs, rep = plan(rows, packs, ov)
    items, dropped = [], []
    for o in objs:
        frames = cut(o, load)
        kind = kind_of(o, ov)
        light = light_of(o, ov)
        mine = []
        for pc in o.pieces:
            pf = [P.cut_piece(f, pc) for f in frames]
            key = o.piece_key(pc)
            if P.ov_get(ov, key, 'skip') == 1:
                continue
            if not any(f[..., 3].any() for f in pf):
                dropped.append(key)
                continue
            mine.append(Item(o, pc, pf))
        for i, it in enumerate(mine):
            last = i == len(mine) - 1
            it.kind = kind if (kind != 'stump' or not o.group or last) else 'decor'
            it.kind, it.flags = flags_for(it, last, ov, light)
            it.name = o.name + (' %s' % ('R%dC%d' % (it.piece.row, it.piece.col)) if o.group else '')
        items += mine
    if len(items) > BLOCK:
        raise P.PackError('animated objects need %d ids, the block holds %d (client %d..%d): move the overflow to the '
                          'overflow range (PLAN_PAIR30 section 2) or skip objects in pack30_overrides.csv'
                          % (len(items), BLOCK, FIRST_ID, LAST_ID))
    rep['dropped'] = dropped
    return items, objs, rep


# ------------------------------------------------------------------------------------------------ atlases and tables
def layout(items):
    """sets item.y (px row in its pack's atlas) and returns {slug: atlas array}"""
    out, by = {}, {}
    for it in items:
        by.setdefault(it.obj.slug, []).append(it)
    for slug, its in by.items():
        h = sum(it.piece.th * P.TILE for it in its)
        w = max(it.piece.tw * P.TILE * it.obj.n for it in its)
        a = np.zeros((h, w, 4), np.uint8)
        y = 0
        for it in its:
            it.y = y
            fw, fh = it.piece.tw * P.TILE, it.piece.th * P.TILE
            for i, f in enumerate(it.frames):
                a[y:y + fh, i * fw:(i + 1) * fw] = f
            y += fh
        out['%s/%s.png' % (ATLAS_DIR, slug)] = a
    return out


def extra_text(it):
    s = 'family=%s|ms=%d' % (it.obj.slug, it.obj.ms)
    if it.obj.group:
        s += '|' + P.group_extra(it.obj.key, it.obj.gw, it.obj.gh, it.piece)
    return s


def spec_rows(items):
    return [[it.key, 'item', it.kind, it.name, '%s/%s' % (ATLAS_DIR, it.obj.slug), 0, it.y, it.piece.tw, it.piece.th, 1,
             it.obj.n, it.flags, 'new', '', extra_text(it)] for it in items]


def source_rows(items):
    return [[it.key, 'item', it.obj.label, '%s/%s' % (it.obj.slug, it.obj.path), LICENCE[it.obj.label]] for it in items]


def tables(items):
    return {SPEC: P.csv_text(FIELDS, spec_rows(items)), SOURCES_CSV: P.csv_text(SOURCE_FIELDS, source_rows(items))}


# ------------------------------------------------------------------------------------------------ checks without art
def parse_csv(text):
    return list(csv.reader(io.StringIO(text)))


def extra_of(text):
    return dict(p.split('=', 1) for p in text.split('|') if '=' in p)


def check_tables(spec_text, sources_text, sums_text, packs, files, ov=None, atlas_dir=None):
    """Problems in the committed tables, from the tables and the file list alone (CI without the packs). -> [text]"""
    bad = []
    rows = parse_csv(spec_text)
    if not rows or rows[0] != FIELDS:
        return ['spec: header must be %s' % ','.join(FIELDS)]
    rows = rows[1:]
    if len(rows) > BLOCK:
        bad.append('spec: %d rows, the block holds %d' % (len(rows), BLOCK))
    try:
        objs, _rep = plan(files, packs, ov)
    except P.PackError as e:
        return bad + ['plan: %s' % e]
    order = {}
    for o in objs:
        for pc in o.pieces:
            order[o.piece_key(pc)] = (len(order), o, pc)
    seen, last_idx, y_at, by_obj = set(), -1, {}, {}
    for r in rows:
        if len(r) != len(FIELDS):
            bad.append('spec: bad row %r' % r[:1])
            continue
        key, kind, ph, flags = r[0], r[2], r[10], r[11]
        where = 'spec %s' % key
        if key in seen:
            bad.append(where + ': duplicate key')
        seen.add(key)
        if key not in order:
            bad.append(where + ': not an object of pack30_anim.files')
            continue
        idx, o, pc = order[key]
        if idx <= last_idx:
            bad.append(where + ': out of plan order')
        last_idx = idx
        ex = extra_of(r[14])
        if r[1] != 'item' or kind not in KINDS or r[12] != 'new' or r[13] != '' or r[9] != '1':
            bad.append(where + ': cat / kind / patterns / mode')
        if r[7:9] != [str(pc.tw), str(pc.th)]:
            bad.append(where + ': size %sx%s, the plan says %dx%d tiles' % (r[7], r[8], pc.tw, pc.th))
        if ph != str(o.n) or not 2 <= o.n <= 255:
            bad.append(where + ': phases %s, the file has %d' % (ph, o.n))
        toks = flags.split()
        names = [t.split(':')[0] for t in toks]
        if any(n not in FLAG_WORDS for n in names) or len(set(names)) != len(names) or 'animateAlways' not in names:
            bad.append(where + ': flags %r' % flags)
        if ('bottom' in names) != (kind == 'stump') and not P.ov_get(ov or {}, o.key, 'flags'):
            bad.append(where + ': kind %s and flags %r disagree' % (kind, flags))
        if ex.get('family') != o.slug or not ex.get('ms', '').isdigit() or int(ex['ms']) < 1:
            bad.append(where + ': extra family / ms')
        if o.group:
            want = P.group_extra(o.key, o.gw, o.gh, pc)
            if '|'.join(p for p in r[14].split('|') if not p.startswith(('family=', 'ms='))) != want:
                bad.append(where + ': group extra differs from %s' % want)
        elif 'group' in ex:
            bad.append(where + ': a single item with a group')
        if r[4] != '%s/%s' % (ATLAS_DIR, o.slug) or r[5] != '0':
            bad.append(where + ': atlas / x')
        want_y = y_at.get(r[4], 0)
        if r[6] != str(want_y):
            bad.append(where + ': atlas row %s, the layout says %d' % (r[6], want_y))
        y_at[r[4]] = want_y + pc.th * P.TILE
        by_obj.setdefault(o.key, []).append((r, names, ex))
    for o in objs:
        got = by_obj.get(o.key)
        if not got:
            bad.append('spec: no item for %s' % o.key)
            continue
        if len({x[2].get('ms') for x in got}) != 1:
            bad.append('spec %s: pieces with different ms (out of step)' % o.key)
        if len({x[0][10] for x in got}) != 1:
            bad.append('spec %s: pieces with different phase counts' % o.key)
        lit = [i for i, x in enumerate(got) if 'light' in x[1]]
        if len(lit) > 1 or (lit and lit[0] != len(got) - 1 and not P.ov_get(ov or {}, o.key, 'flags')):
            bad.append('spec %s: light on more than the last piece' % o.key)
    src = parse_csv(sources_text)
    if not src or src[0] != SOURCE_FIELDS:
        bad.append('sources: header must be %s' % ','.join(SOURCE_FIELDS))
        src = [[]]
    src = src[1:]
    if [s[0] for s in src] != [r[0] for r in rows]:
        bad.append('sources: names differ from the spec keys (same order)')
    dims = {(f.slug, f.path) for f in files}
    pack_by = P.pack_by_slug(packs)
    for s in src:
        if len(s) != len(SOURCE_FIELDS):
            bad.append('sources: bad row %r' % s)
            continue
        slug, _, path = s[3].partition('/')
        p = pack_by.get(slug)
        if (slug, path) not in dims:
            bad.append('sources %s: %s is not in pack30_anim.files' % (s[0], s[3]))
        elif p is None or s[2] != p.label or s[4] != LICENCE.get(p.label) or s[1] != 'item':
            bad.append('sources %s: kind, label or licence' % s[0])
    sum_of = {}
    for line in sums_text.splitlines():
        d, _, p = line.partition('  ')
        sum_of[p] = d
    want = sorted('%s/%s.png' % (ATLAS_DIR, o.slug) for o in {o.slug: o for o in objs}.values())
    if sorted(sum_of) != want:
        bad.append('sums: must list exactly %s' % ', '.join(want))
    if atlas_dir:
        for rel in want:
            p = os.path.join(atlas_dir, rel)
            if not os.path.exists(p):
                continue
            a = np.asarray(Image.open(p).convert('RGBA'))
            h = y_at.get(rel[:-4], 0)
            if a.shape[0] != h:
                bad.append('%s: height %d differs from the spec (%d)' % (rel, a.shape[0], h))
            elif P.digest(a) != sum_of.get(rel):
                bad.append('%s: differs from pack30_anim.sums' % rel)
    return bad


def read(path):
    return open(path, newline='', encoding='utf-8').read() if os.path.exists(path) else None


def check_without_art():
    texts = [read(p) for p in (SPEC, SOURCES_CSV, SUMS)]
    if None in texts:
        print('missing', [p for p, t in zip((SPEC, SOURCES_CSV, SUMS), texts) if t is None])
        return False
    bad = check_tables(*texts, P.load_packs(), P.read_files(P.files_path(CAT)), ov=P.load_overrides(), atlas_dir=ART)
    gi = os.path.join(OUT_DIR, '.gitignore')
    if not os.path.isfile(gi) or read(gi) != GITIGNORE_TEXT:
        bad.append('%s: missing or changed' % gi)
    n = len(parse_csv(texts[0])) - 1
    print('\n'.join(bad))
    print('pack30 anim check (no sources): %d items, ids %d..%d:' % (n, FIRST_ID, FIRST_ID + n - 1),
          'OK' if not bad else 'FAILED')
    return not bad


# ------------------------------------------------------------------------------------------------ build
def make_load(src, private):
    def load(row):
        return P.load_verified(P.source_path(src, row.slug, row.path, private), row.md5)
    return load


def build(src, check):
    if not src:
        if not check:
            sys.exit('build needs --src (the drivepacks folder); without it only --check runs')
        return check_without_art()
    packs = P.load_packs()
    rows = P.read_files(P.files_path(CAT))
    ov = P.load_overrides()
    items, objs, rep = collect(rows, packs, make_load(src, P.load_private()), ov)
    sheets = layout(items)
    files = dict(tables(items))
    files[SUMS] = P.sums_text(sorted(sheets.items()))
    n = len(items)
    kinds = {k: sum(1 for i in items if i.kind == k) for k in KINDS}
    print('animated objects: %d items from %d pictures (decor %d, stump %d, wall %d; %d lit; %d split into pieces), ids %d..%d '
          'of %d..%d; unused strips %d, floors left to grounds %d, empty pieces dropped %d, static files %d'
          % (n, len(objs), kinds['decor'], kinds['stump'], kinds['wall'], sum(1 for i in items if 'light' in i.flags),
             sum(1 for o in objs if o.group), FIRST_ID, FIRST_ID + n - 1, FIRST_ID, LAST_ID, len(rep['unused']),
             len(rep['floors']), len(rep['dropped']), rep['static']))
    bad = check_tables(files[SPEC], files[SOURCES_CSV], files[SUMS], packs, rows, ov)
    if bad:
        print('\n'.join(bad))
        return False
    if check:
        ok = True
        for p, t in files.items():
            if read(p) != t:
                print(os.path.relpath(p, ART), 'differs from a rebuild')
                ok = False
        for rel, a in sheets.items():
            p = os.path.join(ART, rel)
            if os.path.exists(p) and not np.array_equal(np.asarray(Image.open(p).convert('RGBA')), a):
                print(rel, 'differs from a rebuild')
                ok = False
        gi = os.path.join(OUT_DIR, '.gitignore')
        if read(gi) != GITIGNORE_TEXT:
            print(os.path.relpath(gi, ART), 'missing or changed')
            ok = False
        print('pack30 anim check:', 'OK' if ok else 'FAILED')
        return ok
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, '.gitignore'), 'w', encoding='utf-8', newline='') as f:
        f.write(GITIGNORE_TEXT)
    for rel, a in sheets.items():
        Image.fromarray(a, 'RGBA').save(os.path.join(ART, rel), optimize=True)
    for p, t in files.items():
        with open(p, 'w', newline='', encoding='utf-8') as f:
            f.write(t)
        print('wrote', os.path.relpath(p, ART))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    a = ap.parse_args(argv)
    try:
        return 0 if build(a.src, a.check) else 1
    except P.PackError as e:
        print('ERROR:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())
