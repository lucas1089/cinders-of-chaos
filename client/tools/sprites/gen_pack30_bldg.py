#!/usr/bin/env python3
"""Pair 30, buildings and landmarks: static pictures of 128 px and more cut into pieces of at most 4 x 4 tiles, one item
per piece, as client ids 36059..36458 (server ids + 3000), PLAN_PAIR30 sections 2, 3.4 and 10 (task T5).

    python3 -I gen_pack30_bldg.py build --src DRIVEPACKS                  # cut -> art_import/pack30_bldg/<group>.png
                                                                          #   + pack30_bldg.csv .sums .dropped
                                                                          #   + pack30_bldg_sources.csv
    python3 -I gen_pack30_bldg.py build --src DRIVEPACKS --check          # rebuild in memory, compare with everything
    python3 -I gen_pack30_bldg.py build --check                           # CI, no packs: tables agree with each other, with
                                                                          #   pack30_bldg.files and with the overrides
    python3 -I gen_pack30_bldg.py build --src DRIVEPACKS --drop-overflow  # keep the highest-priority buildings that fit
    python3 -I gen_pack30_bldg.py preview --src DRIVEPACKS --out DIR      # owner only, DIR outside git, nobody opens it

Needs numpy and Pillow (CI: the fx venv). Import-only (PLAN_PAIR30 section 0): the packs ban machine-learning use and
sharing. This script reads file names, md5s, sizes, alpha boxes and connected components (geometry) and copies pixels;
nobody views, style-measures or samples a palette from a pack image. The cut groups (art_import/pack30_bldg/, ignored by
git) never enter the repo. Committed: pack30_bldg.csv (things file for import_art_things.py), .sums, .dropped,
pack30_bldg_sources.csv and the existing pack30_bldg.files.

What is a building (file names and sizes only, nothing is looked at). RULES: a pack whose category is `bldg` takes every
png whose smaller side is at least 128 px (`min_px`; fishing and vineyard packs lower it); a pack that has `bldg` only as an
extra category (decor packs) takes only the files its `inc` word list names (tents, cottages, inns ...); the market-stall
pack takes nothing (decor task). Never taken: strips (`_strip<N>`, animated objects task), floor folders and floor / tile
sheets, `exc` words. Sheets of several buildings (SHEET_RE: `sheet` with `buildings|structures|icebergs` in the name) are cut with
pack30lib.segment_sheet (alpha components, boxes on the 32 grid); a segment under 2 x 2 tiles (`small`) or over 16 tiles (`large`) is dropped. Every other file
is one building.

Pictures. Alpha under 12 is cleared; a size that is no multiple of 32 is padded top and left (bottom-right aligned, never
scaled; scale2x override for 16 px art); empty outer tile rows and columns are trimmed (the picture stays on its original
tile grid, no pixel moves inside it). The result is a GROUP of gw x gh tiles (at most 16 x 16).

Pieces. pack30lib.plan_split cuts the group into pieces of at most 4 x 4 tiles from the south-east corner (the remainder
goes to the north-west row and column): 128 px = 1 piece, 192 px = 4, 256 px = 4, 512 px = 16 (before trimming). Every
piece that holds any art is one item `<group key>_r<row>c<col>`, extra `family=<pack slug>|group=<key>|gw=|gh=|piece=r,c`
(gw, gh in tiles, so the server gallery can place the whole building). A piece without art takes no id.
Blocking (PLAN_PAIR30 3.4): the pieces of the group's bottom row are the base footprint: kind `stump`, flags `bottom
notwalkable notmoveable`; every piece above is visual only: kind `decor`, flags `notmoveable`. Door and window positions are
unknown and not handled (map makers add blockers).

Ids and priority. Groups are ordered by pack fit (high, medium, low), pack slug, file path, segment; a group's pieces get
consecutive ids from 36059, 400 at most. More than that is an error that lists what does not fit: the lowest-priority
buildings (the end of the order) are dropped first, a building is never cut in half. `--drop-overflow` keeps the highest-
priority prefix that fits and lists the rest in pack30_bldg.dropped (reason `overflow`), together with empty files, exact
duplicates (same tile picture as an earlier group, reason `duplicate of <key>`) and segments skipped by an override. The
ids of a kept building never depend on a lower-priority one.

Overflow set. Buildings that do not fit the main block are not lost: `build --overflow` writes them as a second things
file, pack30_bldg2.csv (.sums, _sources.csv, groups in art_import/pack30_bldg2/, ignored), with the first id 37113, the
start of the overflow range of PLAN_PAIR30 section 2 (client 37113..62535 = server 40113..65535; 37000..37112 are the donor
items' server ids and stay unused). The set is the `overflow` rows of pack30_bldg.dropped, in the same priority order, so
bldg2 is always the tail of the plan; build the main set with --drop-overflow first. Its check (`build --overflow --check`)
compares the group names with those rows.

Overrides (art_import/pack30_overrides.csv, key = the group key `<pack slug>__<file stem>[__s<n>]` or a piece key):
skip (file or segment), rename (group), kind, flags, blocking (0/1; a piece key beats the group key), light (level:colour),
scale2x. Rebuilds are deterministic: same inputs give byte-identical tables.

Import of the overflow set: the same command with --things art_import/pack30_bldg2.csv --first-item 37113 and
--expect-items <item count of the pair at that point> (it pads the gap with blank entries; the pair must hold fewer than
37113 items).

Import (client/MANIFEST.md "Pack buildings (pair 30)"), after the grounds and decor blocks:
    python3 -I import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \\
        --things art_import/pack30_bldg.csv --first-item 36059 --expect-items <items before>
"""
import argparse
import csv
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack30lib as P  # noqa: E402

ART = P.ART
CAT = 'bldg'
MAIN_FIRST, MAIN_BLOCK = 36059, 400     # client ids 36059..36458
OVER_FIRST, OVER_LAST = 37113, 62535    # the overflow range of PLAN_PAIR30 section 2 (server ids 40113..65535)
OVER_BLOCK = OVER_LAST - OVER_FIRST + 1
FIRST_ID, BLOCK = MAIN_FIRST, MAIN_BLOCK    # the variant in use (use_variant)
LAST_ID = FIRST_ID + BLOCK - 1
OVERFLOW = False
MAX_GROUP = 16                          # tiles; a 512 px picture
OUT = os.path.join(ART, 'pack30_bldg')
ATLAS_DIR = 'pack30_bldg'
THINGS = os.path.join(ART, 'pack30_bldg.csv')
SUMS = os.path.join(ART, 'pack30_bldg.sums')
SOURCES = os.path.join(ART, 'pack30_bldg_sources.csv')
DROPPED = os.path.join(ART, 'pack30_bldg.dropped')
MAIN_DROPPED = DROPPED
GITIGNORE_TEXT = ('# strips and sheets cut from the purchased packs: not to be redistributed, never committed '
                  '(gen_pack30_bldg.py)\n*\n!.gitignore\n')
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']
SOURCES_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']
DROPPED_FIELDS = ['name', 'source', 'reason']
LICENCE = ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
           'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md')
BODY_KIND, BODY_FLAGS = 'stump', 'bottom notwalkable notmoveable'
UPPER_KIND, UPPER_FLAGS = 'decor', 'notmoveable'
FIT_RANK = {'high': 0, 'medium': 1, 'low': 2}
MIN_SEGMENT_TILES = 4                   # a sheet segment under 2 x 2 tiles is a prop, not a building

STRIP_RE = re.compile(r'_strip\d+\.png$', re.I)
FLOOR_DIR_RE = re.compile(r'(^|/)(floors?|floor_tiles|paths|ground|fences)/', re.I)
FLOOR_FILE_RE = re.compile(r'floor|tiles', re.I)
SHEET_RE = re.compile(r'sheet.*(buil|buid|struct|iceberg)|(buil|buid|struct).*sheet', re.I)
# per pack slug: min_px (smaller side), inc (names that count), exc (names that never count). A pack with category
# `bldg` and no entry uses MIN_PX = 128 and no word list. A pack with `bldg` only as an extra category needs an entry
# with `inc`; no entry means the decor task owns its files.
MIN_PX = 128
RULES = {
    'autumn_graveyard': {'inc': r'buildings'},
    'desert_camp': {'inc': r'tent'},
    'fishing_village': {'min_px': 64, 'inc': r'house|shed|store|workshop|warehouse|lighthouse|building'},
    'frozen_ruins': {'exc': r'decoration'},
    'ghost_town': {'inc': r'cottage|inn|tavern|house'},
    'goblin_camp': {'inc': r'tent'},
    'graveyard_kit': {'inc': r'large structures'},
    'haunted_manor': {'inc': r'cottage|greenhouse|haunted_manor|house'},
    'ruined_village': {'inc': r'buildings|buidlings'},
    'survivor_base': {'inc': r'base|barracks|medical|storage|workshop|radio'},
    'vineyards': {'min_px': 96},
    'war_camp': {'inc': r'tent'},
}


def use_variant(overflow):
    """switch the module to the main block (pack30_bldg*) or the overflow set (pack30_bldg2*, ids 37113+)"""
    global FIRST_ID, BLOCK, LAST_ID, OVERFLOW, OUT, ATLAS_DIR, THINGS, SUMS, SOURCES, DROPPED
    OVERFLOW = bool(overflow)
    name = 'pack30_bldg2' if overflow else 'pack30_bldg'
    FIRST_ID, BLOCK = (OVER_FIRST, OVER_BLOCK) if overflow else (MAIN_FIRST, MAIN_BLOCK)
    LAST_ID = FIRST_ID + BLOCK - 1
    OUT, ATLAS_DIR = os.path.join(ART, name), name
    THINGS, SUMS = os.path.join(ART, name + '.csv'), os.path.join(ART, name + '.sums')
    SOURCES, DROPPED = os.path.join(ART, name + '_sources.csv'), os.path.join(ART, name + '.dropped')


class Src:
    """one selected file"""

    def __init__(self, pack, row):
        self.pack, self.row = pack, row
        self.slug, self.fit, self.label = pack.slug, pack.fit, pack.label
        stem = os.path.splitext(row.path)[0].split('/')[-1]
        self.stem = stem
        self.key = P.key_of(pack.slug, stem)
        self.sheet = bool(SHEET_RE.search(stem))
        self.source = '%s/%s' % (row.slug, row.path)


class Group:
    """one building: its trimmed tile picture and where it comes from"""

    def __init__(self, src, key, name, arr, seg=None):
        self.src, self.key, self.name, self.arr, self.seg = src, key, name, arr, seg
        self.gh, self.gw = arr.shape[0] // P.TILE, arr.shape[1] // P.TILE
        self.pieces = [pc for pc in P.plan_split(self.gw, self.gh) if P.cut_piece(arr, pc)[..., 3].any()]
        self.last_row = max(pc.row for pc in P.plan_split(self.gw, self.gh))

    @property
    def source(self):
        return self.src.source + ('' if self.seg is None else '[s%d]' % self.seg)

    @property
    def atlas(self):
        return '%s/%s' % (ATLAS_DIR, self.key)


# ------------------------------------------------------------------------------------------------ selection (names only)
def clean_name(stem):
    return P.humanize(re.sub(r'^(spr|sp)_', '', P.slugify(stem)))


def wanted(pack, row, rule=None):
    """does the file list entry of `pack` count as a building file (file name and size rules only)?"""
    path = row.path
    low = path.lower()
    if not low.endswith('.png') or STRIP_RE.search(low) or FLOOR_DIR_RE.search(low):
        return False
    stem = os.path.splitext(low)[0].split('/')[-1]
    if FLOOR_FILE_RE.search(stem):
        return False
    rule = RULES.get(pack.slug, {}) if rule is None else rule
    if pack.category != CAT and 'inc' not in rule:
        return False
    if rule.get('inc') and not re.search(rule['inc'], low):
        return False
    if rule.get('exc') and re.search(rule['exc'], low):
        return False
    try:
        w, h = int(row.w), int(row.h)
    except ValueError:
        return False
    return min(w, h) >= rule.get('min_px', MIN_PX)


def select(rows, packs, ov=None):
    """The building files in priority order: pack fit (high, medium, low), pack slug, path. Files skipped by an override
    are left out. Two files with the same group key stop the build."""
    ov = ov or {}
    ready = {p.slug: p for p in P.packs_for(packs, CAT)}
    out, seen = [], {}
    for r in sorted(rows, key=lambda r: (FIT_RANK.get(ready[r.slug].fit, 1) if r.slug in ready else 9, r.slug, r.path)):
        p = ready.get(r.slug)
        if p is None or not wanted(p, r):
            continue
        s = Src(p, r)
        if s.key in seen:
            raise P.PackError('two files make the key %s: %s and %s' % (s.key, seen[s.key], s.source))
        seen[s.key] = s.source
        if P.ov_get(ov, s.key, 'skip', 0):
            continue
        out.append(s)
    return out


# ------------------------------------------------------------------------------------------------ pixels
def trim_tiles(a):
    """drop empty outer tile rows and columns; None when there is no art at all"""
    box = P.alpha_bbox(a)
    if box is None:
        return None
    x0, y0 = box[0] // P.TILE, box[1] // P.TILE
    x1, y1 = -(-box[2] // P.TILE), -(-box[3] // P.TILE)
    return np.ascontiguousarray(a[y0 * P.TILE:y1 * P.TILE, x0 * P.TILE:x1 * P.TILE])


def prepare(a, scale2x=False):
    a = P.clean_alpha(a)
    if scale2x:
        a = P.scale2x(a)
    if a.shape[0] % P.TILE or a.shape[1] % P.TILE:
        a = P.pad_to_tile(a)
    return a


def groups_of(src, a, ov):
    """-> (groups, dropped): the groups of one file in reading order, [(name, source, reason)] for what is left out"""
    a = prepare(a, bool(P.ov_get(ov, src.key, 'scale2x', 0)))
    groups, dropped = [], []
    if src.sheet:
        boxes, _tiny = P.segment_sheet(a)
        for n, (x0, y0, x1, y1) in enumerate(boxes, 1):
            key = '%s__s%d' % (src.key, n)
            t = trim_tiles(a[y0:y1, x0:x1])
            if t is None or (t.shape[0] // P.TILE) * (t.shape[1] // P.TILE) < MIN_SEGMENT_TILES:
                dropped.append((key, '%s[s%d]' % (src.source, n), 'small'))
            elif max(t.shape[:2]) > MAX_GROUP * P.TILE:
                dropped.append((key, '%s[s%d]' % (src.source, n), 'large'))
            elif P.ov_get(ov, key, 'skip', 0):
                dropped.append((key, '%s[s%d]' % (src.source, n), 'skip'))
            else:
                groups.append(Group(src, key, rename(ov, key, '%s %d' % (clean_name(src.stem), n)), t, n))
    else:
        t = trim_tiles(a)
        if t is None:
            dropped.append((src.key, src.source, 'empty'))
        else:
            groups.append(Group(src, src.key, rename(ov, src.key, clean_name(src.stem)), t))
    for g in groups:
        if g.gw > MAX_GROUP or g.gh > MAX_GROUP:
            raise P.PackError('%s: %dx%d tiles, the limit of a group is %d' % (g.source, g.gw, g.gh, MAX_GROUP))
    return groups, dropped


def rename(ov, key, default):
    return P.ov_get(ov, key, 'rename', default)


def unique(groups, dropped):
    """exact duplicates (same tile picture) are kept once, the earlier group wins"""
    seen, out = {}, []
    for g in groups:
        d = P.digest(g.arr)
        if d in seen:
            dropped.append((g.key, g.source, 'duplicate of %s' % seen[d]))
        else:
            seen[d] = g.key
            out.append(g)
    return out


def allocate(groups, drop_overflow=False, block=None, first=None):
    """-> (kept, overflow): the prefix of groups whose pieces fit the block"""
    block = BLOCK if block is None else block
    first = FIRST_ID if first is None else first
    used, kept = 0, []
    for i, g in enumerate(groups):
        if used + len(g.pieces) > block:
            rest = groups[i:]
            if not drop_overflow:
                need = used + sum(len(x.pieces) for x in rest)
                lst = ', '.join('%s (%d)' % (x.key, len(x.pieces)) for x in rest[:12])
                raise P.PackError(
                    '%d ids needed, the block %d-%d holds %d. Dropped first (lowest priority, the end of the order; '
                    '%d building(s), %d id(s) over): %s%s. Add `skip` rows to pack30_overrides.csv or build with '
                    '--drop-overflow (the first 400 ids) and --overflow (the rest, from id 37113).'
                    % (need, first, first + block - 1, block, len(rest), need - block, lst, ', ...' if len(rest) > 12 else ''))
            return kept, rest
        used += len(g.pieces)
        kept.append(g)
    return kept, []


# ------------------------------------------------------------------------------------------------ tables
def piece_kind(g, pc, ov):
    """(kind, flags) of one piece: the bottom row of the group blocks, everything above is visual"""
    pk = P.piece_key(g.key, pc)
    blocking = P.ov_get(ov, pk, 'blocking', P.ov_get(ov, g.key, 'blocking', 1 if pc.row == g.last_row else 0))
    kind = P.ov_get(ov, pk, 'kind', P.ov_get(ov, g.key, 'kind', BODY_KIND if blocking else UPPER_KIND))
    flags = P.ov_get(ov, pk, 'flags', P.ov_get(ov, g.key, 'flags', BODY_FLAGS if blocking else UPPER_FLAGS))
    light = P.ov_get(ov, pk, 'light', P.ov_get(ov, g.key, 'light'))
    if light:
        flags += ' light:%d:%d' % light
    return kind, flags


def piece_extra(g, pc):
    return 'family=%s|%s' % (g.src.slug, P.group_extra(g.key, g.gw, g.gh, pc))


def piece_name(g, pc):
    return g.name if len(g.pieces) == 1 else '%s R%dC%d' % (g.name, pc.row, pc.col)


def things_rows(groups, ov):
    rows = []
    for g in groups:
        for pc in g.pieces:
            kind, flags = piece_kind(g, pc, ov)
            rows.append({'key': P.piece_key(g.key, pc), 'cat': 'item', 'kind': kind, 'name': piece_name(g, pc),
                         'atlas': g.atlas, 'x': pc.tx * P.TILE, 'y': pc.ty * P.TILE, 'w': pc.tw, 'h': pc.th,
                         'patterns': 1, 'phases': 1, 'flags': flags, 'mode': 'new', 'server_id': '',
                         'extra': piece_extra(g, pc)})
    return rows


def things_text(rows):
    return P.csv_text(FIELDS, [[r[f] for f in FIELDS] for r in rows])


def sources_text(groups):
    return P.csv_text(SOURCES_FIELDS, [[P.piece_key(g.key, pc), 'item', g.src.label, g.source, LICENCE]
                                       for g in groups for pc in g.pieces])


def dropped_text(dropped):
    return P.csv_text(DROPPED_FIELDS, [list(d) for d in dropped])


def sums_of(groups):
    return P.sums_text(sorted(('%s.png' % g.atlas, g.arr) for g in groups))


def texts_of(groups, dropped, ov):
    t = {THINGS: things_text(things_rows(groups, ov)), SOURCES: sources_text(groups), SUMS: sums_of(groups)}
    if not OVERFLOW:
        t[DROPPED] = dropped_text(dropped)
    return t


# ------------------------------------------------------------------------------------------------ build
def make_load(src, private):
    def load(row):
        return P.load_verified(P.source_path(src, row.slug, row.path, private), row.md5)
    return load


def render(srcs, load, ov, drop_overflow=False, overflow=False):
    """-> (kept groups, dropped [(name, source, reason)]) from the selected files; load(FileRow) -> RGBA array.
    overflow=True returns the groups that do not fit the main block, for ids OVER_FIRST.. (nothing is left out then)."""
    groups, dropped = [], []
    for s in srcs:
        g, d = groups_of(s, load(s.row), ov)
        groups += g
        dropped += d
    groups = unique(groups, dropped)
    if overflow:
        _main, over = allocate(groups, True, MAIN_BLOCK, MAIN_FIRST)
        return allocate(over, False, OVER_BLOCK, OVER_FIRST)[0], []
    kept, over = allocate(groups, drop_overflow)
    dropped += [(g.key, g.source, 'overflow') for g in over]
    return kept, dropped


def write_outputs(groups, texts, out=None):
    out = OUT if out is None else out
    os.makedirs(out, exist_ok=True)
    gi = os.path.join(out, '.gitignore')
    if not os.path.isfile(gi) or open(gi, encoding='utf-8').read() != GITIGNORE_TEXT:
        with open(gi, 'w', encoding='utf-8', newline='') as f:
            f.write(GITIGNORE_TEXT)
    for fn in os.listdir(out):
        if fn.endswith('.png') and fn[:-4] not in {g.key for g in groups}:
            os.remove(os.path.join(out, fn))
    for g in groups:
        Image.fromarray(g.arr, 'RGBA').save(os.path.join(out, g.key + '.png'))
    for path, text in texts.items():
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)


def disk_problems(groups, out=None):
    out = OUT if out is None else out
    bad = []
    for g in groups:
        p = os.path.join(out, g.key + '.png')
        if os.path.isfile(p) and P.digest(np.asarray(Image.open(p).convert('RGBA'))) != P.digest(g.arr):
            bad.append('%s differs from the rebuilt group' % p)
    return bad


# ------------------------------------------------------------------------------------------------ check without sources
def _read(path):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f)), None


def check_structure(srcs, packs, ov, out=None):
    out = OUT if out is None else out
    """Everything that needs no pixels: the committed tables agree with each other, with the file list and the overrides."""
    bad = []
    for p in (THINGS, SOURCES, SUMS) + (() if OVERFLOW else (DROPPED,)):
        if not os.path.isfile(p):
            bad.append('%s: missing (run build --src)' % p)
    if bad:
        return bad
    with open(THINGS, newline='', encoding='utf-8') as f:
        rd = csv.DictReader(f)
        if rd.fieldnames != FIELDS:
            return ['%s: header must be %s' % (THINGS, ','.join(FIELDS))]
        spec = list(rd)
    if len(spec) > BLOCK:
        bad.append('%s: %d items, the block holds %d' % (THINGS, len(spec), BLOCK))
    byfile = {s.source: s for s in srcs}
    groups, order = {}, []
    for r in spec:
        ex = dict(kv.split('=', 1) for kv in r['extra'].split('|') if '=' in kv)
        gk = ex.get('group')
        if not gk or not all(k in ex for k in ('family', 'gw', 'gh', 'piece')):
            bad.append('%s: %s has no group extra' % (THINGS, r['key']))
            continue
        if gk not in groups:
            groups[gk] = []
            order.append(gk)
        groups[gk].append((r, ex))
    last_file = None
    files_seen = []
    srcrows = {}
    with open(SOURCES, newline='', encoding='utf-8') as f:
        rd = csv.DictReader(f)
        if rd.fieldnames != SOURCES_FIELDS:
            bad.append('%s: header must be %s' % (SOURCES, ','.join(SOURCES_FIELDS)))
        for r in rd:
            srcrows[r['name']] = r
    label = {p.slug: p.label for p in packs}
    for gk in order:
        rs = groups[gk]
        gw, gh = int(rs[0][1]['gw']), int(rs[0][1]['gh'])
        plan = {(pc.row, pc.col): pc for pc in P.plan_split(gw, gh)}
        last_row = max(r for r, _c in plan)
        fam = rs[0][1]['family']
        atlas = '%s/%s' % (ATLAS_DIR, gk)
        for r, ex in rs:
            rc = tuple(int(v) for v in ex['piece'].split(','))
            pc = plan.get(rc)
            if pc is None or r['key'] != P.piece_key(gk, pc) or ex['group'] != gk or ex['family'] != fam:
                bad.append('%s: %s is not a piece of %s' % (THINGS, r['key'], gk))
                continue
            if (int(ex['gw']), int(ex['gh'])) != (gw, gh):
                bad.append('%s: group %s has two sizes' % (THINGS, gk))
            if (int(r['x']), int(r['y']), int(r['w']), int(r['h'])) != (pc.tx * 32, pc.ty * 32, pc.tw, pc.th) or \
                    r['atlas'] != atlas:
                bad.append('%s: %s does not match plan_split' % (THINGS, r['key']))
            g = type('G', (), {'key': gk, 'last_row': last_row})
            kind, flags = piece_kind(g, pc, ov)
            if (r['kind'], r['flags']) != (kind, flags):
                bad.append('%s: %s kind/flags differ from the blocking rule or the overrides' % (THINGS, r['key']))
            if r['cat'] != 'item' or r['patterns'] != '1' or r['phases'] != '1' or r['mode'] != 'new' or r['server_id']:
                bad.append('%s: %s is not a plain new item' % (THINGS, r['key']))
            sr = srcrows.get(r['key'])
            if sr is None or sr['pack'] != label.get(fam) or sr['licence'] != LICENCE or sr['kind'] != 'item':
                bad.append('%s: no matching row for %s' % (SOURCES, r['key']))
                continue
            fpath = sr['source'].split('[')[0]
            if fpath not in byfile:
                bad.append('%s: %s is not a building file of pack30_bldg.files (or is skipped by an override)'
                           % (SOURCES, sr['source']))
            if fpath != last_file:
                files_seen.append(fpath)
                last_file = fpath
    if set(srcrows) != {r['key'] for r in spec}:
        bad.append('%s: rows differ from the things file' % SOURCES)
    ids = [s.source for s in srcs]
    pos = [ids.index(f) for f in files_seen if f in ids]
    if pos != sorted(pos) or len(set(files_seen)) != len(files_seen):
        bad.append('%s: groups are not in the priority order of the file list' % THINGS)
    if OVERFLOW:
        # the overflow set is exactly what the main table lists as `overflow`
        if not os.path.isfile(MAIN_DROPPED):
            bad.append('%s: missing' % MAIN_DROPPED)
        else:
            with open(MAIN_DROPPED, newline='', encoding='utf-8') as f:
                moved = {d['name'] for d in csv.DictReader(f) if d['reason'] == 'overflow'}
            if moved != set(groups):
                bad.append('%s: groups differ from the `overflow` rows of %s (%d vs %d; rebuild both)'
                           % (THINGS, MAIN_DROPPED, len(groups), len(moved)))
    else:
        # the dropped table plus the built files cover every selected file
        with open(DROPPED, newline='', encoding='utf-8') as f:
            rd = csv.DictReader(f)
            if rd.fieldnames != DROPPED_FIELDS:
                bad.append('%s: header must be %s' % (DROPPED, ','.join(DROPPED_FIELDS)))
            dr = list(rd)
        covered = set(files_seen) | {d['source'].split('[')[0] for d in dr}
        if covered != set(ids):
            miss, extra = sorted(set(ids) - covered), sorted(covered - set(ids))
            bad.append('%s/%s do not cover the building files of pack30_bldg.files: missing %s, unknown %s'
                       % (THINGS, DROPPED, miss[:5], extra[:5]))
        if any(d['reason'] not in ('empty', 'small', 'large', 'skip', 'overflow') and not d['reason'].startswith('duplicate of ')
               for d in dr):
            bad.append('%s: unknown reason' % DROPPED)
        if len({d['name'] for d in dr}) != len(dr) or {d['name'] for d in dr} & set(groups):
            bad.append('%s: names repeat or are also built' % DROPPED)
    # sums
    lines = open(SUMS, encoding='utf-8').read().splitlines()
    paths = [ln.split('  ', 1)[1] for ln in lines if '  ' in ln]
    if paths != sorted('%s/%s.png' % (ATLAS_DIR, gk) for gk in order):
        bad.append('%s: paths differ from the things file' % SUMS)
    for ln in lines:
        dg, _, path = ln.partition('  ')
        f = os.path.join(ART, path)
        if os.path.isfile(f) and P.digest(np.asarray(Image.open(f).convert('RGBA'))) != dg:
            bad.append('%s differs from %s' % (f, SUMS))
    gi = os.path.join(out, '.gitignore')
    if not os.path.isfile(gi) or open(gi, encoding='utf-8').read() != GITIGNORE_TEXT:
        bad.append('%s: missing or changed' % gi)
    return bad


def load_plan():
    packs = P.load_packs()
    rows = P.read_files(P.files_path(CAT))
    ov = P.load_overrides()
    return packs, ov, select(rows, packs, ov)


def cmd_build(src, check, drop_overflow, overflow=False):
    use_variant(overflow)
    packs, ov, srcs = load_plan()
    print('building files: %d (of %d listed); ids %d..%d' % (len(srcs), len(P.read_files(P.files_path(CAT))), FIRST_ID, LAST_ID))
    bad = []
    if src is None:
        if not check:
            sys.exit('build needs --src DRIVEPACKS (or --check for the source-free check)')
        bad = check_structure(srcs, packs, ov)
    else:
        private = P.load_private()
        groups, dropped = render(srcs, make_load(src, private), ov, drop_overflow, overflow)
        texts = texts_of(groups, dropped, ov)
        npieces = sum(len(g.pieces) for g in groups)
        reasons = {}
        for _n, _s, why in dropped:
            k = why.split(' of ')[0]
            reasons[k] = reasons.get(k, 0) + 1
        print('%d groups, %d pieces = ids %d..%d (%d free); left out: %s' % (
            len(groups), npieces, FIRST_ID, FIRST_ID + npieces - 1, BLOCK - npieces,
            ', '.join('%d %s' % (v, k) for k, v in sorted(reasons.items())) or 'none'))
        if check:
            for path, text in texts.items():
                if not os.path.isfile(path) or open(path, encoding='utf-8').read() != text:
                    bad.append('%s differs from the rebuild' % path)
            bad += disk_problems(groups)
            bad += check_structure(srcs, packs, ov) if not bad else []
        else:
            write_outputs(groups, texts)
            print('wrote %d groups to %s and the tables' % (len(groups), OUT))
            bad = check_structure(srcs, packs, ov)
    for b in bad:
        print('FAIL', b)
    if bad:
        return 1
    print('ok')
    return 0


def cmd_preview(src, out, drop_overflow, overflow=False):
    """owner only: every group on a grey ground in a folder outside git; nobody opens it"""
    repo = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
    if os.path.abspath(out).startswith(repo + os.sep):
        raise P.PackError('--out must be outside the repository')
    use_variant(overflow)
    packs, ov, srcs = load_plan()
    groups, _d = render(srcs, make_load(src, P.load_private()), ov, drop_overflow, overflow)
    os.makedirs(out, exist_ok=True)
    for g in groups:
        h, w = g.arr.shape[:2]
        bg = Image.new('RGBA', (w, h), (60, 60, 60, 255))
        bg.alpha_composite(Image.fromarray(g.arr, 'RGBA'))
        bg.save(os.path.join(out, g.key + '.png'))
    print('previews in', out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src', default=None, help='the drivepacks folder')
    b.add_argument('--check', action='store_true')
    b.add_argument('--drop-overflow', action='store_true', help='keep the highest-priority buildings that fit the block')
    b.add_argument('--overflow', action='store_true', help='the buildings that do not fit the block: pack30_bldg2*, ids 37113+')
    p = sub.add_parser('preview')
    p.add_argument('--src', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--drop-overflow', action='store_true')
    p.add_argument('--overflow', action='store_true')
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'preview':
            cmd_preview(a.src, a.out, a.drop_overflow, a.overflow)
            return 0
        return cmd_build(a.src, a.check, a.drop_overflow, a.overflow)
    except P.PackError as e:
        print('STOP', e)
        return 2


if __name__ == '__main__':
    sys.exit(main())
