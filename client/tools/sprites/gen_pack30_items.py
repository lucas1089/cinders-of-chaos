#!/usr/bin/env python3
"""Pair 30, items: look-only weapon icons, magic books and throwable-potion flasks as 1x1 items of client ids
34443..34758 (server ids + 3000), from the purchased weapon sheets, the book strips (second batch) and the freely shared
potion pack.

    python3 -I gen_pack30_items.py build --src DRIVEPACKS            # -> art_import/pack30_items/items_{a,b,c}.png
                                                                     #    + art_import/pack30_items.csv, .sums
                                                                     #    + art_import/pack30_items_sources.csv
    python3 -I gen_pack30_items.py build --src DRIVEPACKS --check    # rebuild in memory, compare with everything
    python3 -I gen_pack30_items.py build --check                     # CI, no packs: tables agree with each other and
                                                                     #    with pack30_items.files; atlases on disk
                                                                     #    (if any) match the sums
    python3 -I gen_pack30_items.py preview --out DIR                 # owner only: a mosaic of the atlases, outside git

Import-only (PLAN_PAIR30 section 0, docs/SPRITE_STYLE.md): the packs ban machine-learning use and sharing. No pack image is
viewed, style-measured, palette-sampled or given to an AI tool. This script reads pixels only for geometry (alpha
connected components to decide a sheet's grid, empty cells, exact duplicates). Items have a neutral key
`<pack slug>__<stem>[__r<row>c<col>]`; the internal labels of the packs are in the sources CSV; docs/CREDITS.md names the
packs. Neither the packs nor the cut atlases are committed (art_import/pack30_items/ is ignored by git); the sums hold the
sha256 of every atlas' pixels.

Blocks (client ids, fixed so ids stay stable; unused ids of a block that is followed by rows are blank pad rows):
  A 34443..34698 (256)  weapon icons       slug `weapons`, one item per non-empty cell of every sheet, sheets in file name order
  B 34699..34718 (20)   magic books        slug `mini_books` (second batch: skipped while its status is pending), one item per
                                           strip of square frames, animated (`animateAlways`)
  C 34719..34738 (20)   potion flasks      slug `potions`, `pocoes/<lava|veneno>/<health|strong|great>/tira.png`: 8 frames of 32 px,
                                           125 ms, stackable like a potion; the still `parada.png`, the 64 px projectile and the
                                           bursts are not items (gen_pack30_fx.py)
  D 34739..34758 (20)   reserve (nothing written; the next generator's first id is 34759)
More ids than a block holds stops the build with an error (the integrator then moves the overflow, PLAN_PAIR30 section 2).
Pad rows (`pad_<id>`, kind decor, no flags, a clear cell) keep the later blocks on their ids; the importer makes them blank
dat entries, the manifest rows carry `blank=1` in extra.

Weapon grid (geometry only): the smallest cell of 16, 32, 64, 96, 128 px that divides the sheet and that no alpha
component crosses (art larger than a cell cannot sit in it, so the art decides; the build prints every valid cell); none ->
segment_sheet boxes. Art is never scaled, except a 16 px grid, which is Scale2x upscaled to a 1x1 item. A 32 px cell is a
1x1 item, a 64 px cell a 2x2 item (the sheets of the real pack: 4 x 4 cells of 64 px), 96 and 128 px cells 3x3 and 4x4.
The owner overrides a wrong guess per sheet key `<slug>__<stem>` in art_import/pack30_overrides.csv: `scale2x,1` forces 16 px
cells, `tiles,N` forces N x N tile cells (`scale2x,0` = `tiles,1`). Kind of a weapon: from the words of the sheet name
(sword, axe, club, bow, wand, shield) when all the words name one class, else `weapon`. Per item overrides (key = item key):
skip, rename, kind, flags, light. Look-only items: no stats, no shop, no loot.
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
import pack30lib as P  # noqa: E402

CAT = 'items'
FIRST_ID = 34443
BLOCKS = {'a': (34443, 256), 'b': (34699, 20), 'c': (34719, 20), 'd': (34739, 20)}
LAST_ID = BLOCKS['d'][0] + BLOCKS['d'][1] - 1          # 34758
ALL_IDS = LAST_ID - FIRST_ID + 1                       # 316
ART = P.ART
OUT_DIR = os.path.join(ART, 'pack30_items')
SPEC = os.path.join(ART, 'pack30_items.csv')
SUMS = os.path.join(ART, 'pack30_items.sums')
SOURCES_CSV = os.path.join(ART, 'pack30_items_sources.csv')
ATLAS_REL = {'a': 'pack30_items/items_a', 'b': 'pack30_items/items_b', 'c': 'pack30_items/items_c'}
PAD_ATLAS = ATLAS_REL['a']
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
SOURCE_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']
LICENCE = {
    'set30 mutter': ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
                     'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md'),
    'set30 pocket': ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
                     'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md'),
    'set30 potions': ('shared freely by its maker; no licence text in the pack; used as shared; no resale or sharing of '
                      'the raw files; never a style reference; docs/CREDITS.md'),
}
# slug -> (block, what); a ready pack of the items category without a rule here stops the build
PACK_BLOCK = {'weapons': 'a', 'mini_books': 'b', 'potions': 'c'}
# kinds an item may have (all are in import_art_things.OTB): the pack kinds plus the weapon classes
WEAPON_KINDS = ('sword', 'axe', 'club', 'bow', 'crossbow', 'wand', 'rod', 'shield')
KINDS = ('weapon', 'spellbook', 'flask', 'prop', 'decor', 'product') + WEAPON_KINDS
FLAG_WORDS = ('pickupable', 'stackable', 'animateAlways', 'notmoveable', 'light', 'usable', 'look')
# words of a sheet name -> weapon class
CLASS_WORD = {'sword': 'sword', 'swords': 'sword', 'blade': 'sword', 'blades': 'sword', 'axe': 'axe', 'axes': 'axe',
              'mace': 'club', 'maces': 'club', 'hammer': 'club', 'hammers': 'club', 'club': 'club', 'clubs': 'club',
              'bow': 'bow', 'bows': 'bow', 'wand': 'wand', 'wands': 'wand', 'staff': 'wand', 'staves': 'wand',
              'magic': 'wand', 'shield': 'shield', 'shields': 'shield'}
FLASK_FILE = re.compile(r'^pocoes/(lava|veneno)/(health|strong|great)/tira\.png$')
FLASK_ELEMENT = {'lava': 'lava', 'veneno': 'venom'}
FLASK_SIZE = {'health': 'small', 'strong': 'medium', 'great': 'large'}
FLASK_ORDER = {'lava': 0, 'veneno': 1, 'health': 0, 'strong': 1, 'great': 2}
FLASK_MS = 125
BOOK_MS = 120
FRAME = P.TILE
CELLS = (16, 32, 64, 96, 128)      # candidate cells of a weapon sheet, smallest valid one wins


class Item:
    """one item: `frames` are tw*32 x th*32 RGBA arrays (phases)."""

    def __init__(self, pack, path, frames, cell=None, grid=None):
        self.pack, self.path, self.frames, self.cell, self.grid = pack, path, frames, cell, grid
        self.th, self.tw = frames[0].shape[0] // P.TILE, frames[0].shape[1] // P.TILE
        self.block = PACK_BLOCK[pack]
        self.key = self.name = self.kind = self.flags = self.stem = self.pack_label = None
        self.extra = {}


# ---------------------------------------------------------------------------------------------- selection
def stem_of(slug, path):
    """the file stem as a neutral slug: no extension, no sheet number, no pack slug"""
    s = P.slugify(os.path.splitext(path.split('/')[-1])[0])
    s = re.sub(r'^(sheet_)?\d+_', '', s)
    s = s.replace(slug + '_', '').replace('_' + slug, '')
    return s or 'item'


def plan_jobs(rows, packs):
    """The files to cut, in plan order: [(slug, path, mode)] with mode sheet|flask|book. Only ready packs that list `items`."""
    ok = {p.slug for p in packs if p.status == 'ready' and CAT in p.cats()}
    for s in sorted(ok):
        if s not in PACK_BLOCK:
            raise P.PackError('%s: a ready items pack without a rule in PACK_BLOCK' % s)
    jobs = []
    for r in sorted(rows, key=lambda r: (r.slug, r.path)):
        if r.slug not in ok or not r.path.lower().endswith('.png'):
            continue
        if r.slug == 'weapons':
            jobs.append((r.slug, r.path, 'sheet'))
        elif r.slug == 'potions':
            if FLASK_FILE.match(r.path):
                jobs.append((r.slug, r.path, 'flask'))
        elif r.slug == 'mini_books':
            jobs.append((r.slug, r.path, 'book'))
    jobs.sort(key=lambda j: (j[0], flask_order(j[1]) if j[2] == 'flask' else (0, 0), j[1]))
    return jobs


def flask_order(path):
    m = FLASK_FILE.match(path)
    return (FLASK_ORDER[m.group(1)], FLASK_ORDER[m.group(2)]) if m else (9, 9)


def weapon_kind(stem):
    kinds = {CLASS_WORD[w] for w in stem.split('_') if w in CLASS_WORD}
    return kinds.pop() if len(kinds) == 1 else 'weapon'


# ---------------------------------------------------------------------------------------------- cutting
def cut_sheet(a, slug, path, key, ov):
    """-> ([Item], chosen grid text, valid cells) for one weapon sheet. The grid is the smallest cell of CELLS that divides
    the sheet and that no alpha component crosses (a component larger than a cell cannot fit it, so the art decides); none
    -> segment_sheet boxes. Art is never scaled except the 16 px cells (Scale2x); a 64 px cell is a 2x2 item."""
    H, W = a.shape[:2]
    T = P.TILE
    s2, tl = P.ov_get(ov, key, 'scale2x'), P.ov_get(ov, key, 'tiles')
    valid = [c for c in CELLS if not (W % c or H % c) and P.grid_detect(a, cells=(c,)) is not None]
    c = None
    if s2 == 1:
        c = 16
    elif tl is not None or s2 == 0:
        c = T * (tl[0] if tl else 1)
    elif valid:
        c = valid[0]
    if c is not None and (W % c or H % c):
        raise P.PackError('%s/%s: %dx%d is not a grid of %d px cells (override)' % (slug, path, W, H, c))
    out = []
    if c is None:
        boxes, _ = P.segment_sheet(a, T)
        for x0, y0, x1, y1 in boxes:
            tw, th = (x1 - x0) // T, (y1 - y0) // T
            if tw > P.MAX_TILES or th > P.MAX_TILES:
                raise P.PackError('%s/%s: art of %dx%d px at %d,%d is larger than %d tiles' % (
                    slug, path, x1 - x0, y1 - y0, x0, y0, P.MAX_TILES))
            out.append(Item(slug, path, [a[y0:y1, x0:x1]], 'y%dx%d' % (y0, x0), 'seg'))
        return out, 'seg', valid
    for r in range(H // c):
        for k in range(W // c):
            tile = np.ascontiguousarray(a[r * c:(r + 1) * c, k * c:(k + 1) * c])
            if c == 16:
                tile = P.scale2x(tile)
            out.append(Item(slug, path, [tile], 'r%dc%d' % (r, k), str(c)))
    return out, str(c), valid


def cut_strip(a, slug, path, n_min=1, small=False):
    """-> [32 px frames] of a strip of square frames (16 px frames are upscaled when `small`)"""
    H, W = a.shape[:2]
    if H not in ((16, FRAME) if small else (FRAME,)) or W % H:
        raise P.PackError('%s/%s: strip %dx%d, expected square frames of %s px' % (slug, path, W, H, '16 or 32' if small else '32'))
    frames = P.strip_frames(a, H)
    if len(frames) < n_min:
        raise P.PackError('%s/%s: %d frame(s), expected at least %d' % (slug, path, len(frames), n_min))
    if H == 16:
        frames = [P.scale2x(np.ascontiguousarray(f)) for f in frames]
    return frames


def coverage(it):
    return max(float((f[..., 3] >= P.ALPHA_MIN).mean()) for f in it.frames)


def item_digest(it):
    return P.digest(np.stack(it.frames))


def flags_of(it, ov):
    custom = P.ov_get(ov, it.key, 'flags')
    toks = custom.split() if custom else (['pickupable'] + (['stackable'] if it.kind == 'flask' else []))
    if not custom:
        lt = P.ov_get(ov, it.key, 'light')
        if lt:
            toks.append('light:%d:%d' % lt)
        if len(it.frames) > 1:
            toks.append('animateAlways')
    return ' '.join(toks)


def collect(src, rows, packs, private=None, ov=None):
    """Cut and classify every item. -> ([Item] in id order, report dict). Stops on an overflow of a block."""
    ov = {} if ov is None else ov
    rows_by = {(r.slug, r.path): r for r in rows}
    pack_by = P.pack_by_slug(packs)
    items, seen, dropped, dups, grids = [], {}, [], [], {}
    keys = set()
    for slug, path, mode in plan_jobs(rows, packs):
        row = rows_by[(slug, path)]
        a = P.clean_alpha(P.load_verified(P.source_path(src, slug, path, private), row.md5))
        if a.shape[1::-1] != (int(row.w), int(row.h)):
            raise P.PackError('%s/%s: %dx%d, the list has %sx%s' % (slug, path, a.shape[1], a.shape[0], row.w, row.h))
        stem = stem_of(slug, path)
        sheet_key = P.key_of(slug, stem)
        if mode == 'sheet':
            if P.ov_get(ov, sheet_key, 'skip') == 1:
                continue
            cut, grid, valid = cut_sheet(a, slug, path, sheet_key, ov)
            grids[(slug, path)] = (grid, valid)
            kind0 = weapon_kind(stem)
        elif mode == 'flask':
            m = FLASK_FILE.match(path)
            el, sz = FLASK_ELEMENT[m.group(1)], FLASK_SIZE[m.group(2)]
            fr = cut_strip(a, slug, path)
            it = Item(slug, path, fr)
            it.stem = '%s_flask_%s' % (el, sz)
            it.name = '%s flask (%s)' % (el, sz)
            it.extra = {'ms': str(FLASK_MS), 'element': el, 'size': sz}
            cut, kind0 = [it], 'flask'
        else:
            fr = cut_strip(a, slug, path, 2, small=True)
            it = Item(slug, path, fr)
            it.stem = stem
            it.name = P.humanize(stem).lower()
            it.extra = {'ms': str(BOOK_MS)}
            cut, kind0 = [it], 'spellbook'
        for it in cut:
            it.stem = it.stem or stem
            it.key = P.key_of(slug, it.stem, it.cell)
            if it.key in keys:
                raise P.PackError('%s: two items with one key (rename one with an override)' % it.key)
            if P.ov_get(ov, it.key, 'skip') == 1:
                continue
            if coverage(it) == 0.0:
                dropped.append('%s/%s %s' % (slug, path, it.cell or ''))
                continue
            d = item_digest(it)
            if d in seen:
                dups.append((it.key, seen[d]))
                continue
            kind = P.ov_get(ov, it.key, 'kind') or kind0
            if kind not in KINDS:
                raise P.PackError('%s: kind override %r not one of %s' % (it.key, kind, ', '.join(KINDS)))
            it.kind = kind
            keys.add(it.key)
            seen[d] = it.key
            it.pack_label = pack_by[slug].label
            it.name = P.ov_get(ov, it.key, 'rename') or it.name or (
                P.humanize(it.stem).lower() + (' ' + it.cell if it.cell else ''))
            it.flags = flags_of(it, ov)
            items.append(it)
    for b, (first, size) in BLOCKS.items():
        n = sum(1 for it in items if it.block == b)
        if n > size:
            raise P.PackError('block %s needs %d ids, it holds %d (client %d..%d of the %d owned by items): move the overflow to '
                              'the overflow range (PLAN_PAIR30 section 2) or skip items in pack30_overrides.csv' % (
                                  b.upper(), n, size, first, first + size - 1, ALL_IDS))
    items.sort(key=lambda it: it.block)        # stable: block order, plan order inside
    return items, {'dropped': dropped, 'dups': dups, 'grids': grids}


# ---------------------------------------------------------------------------------------------- tables
def layout(items):
    """-> [(client id, Item | None)] for ids FIRST_ID..last used id; None = a pad row. Rows end at the last real item."""
    by = {b: [it for it in items if it.block == b] for b in BLOCKS}
    slots = []
    last = max((i for i, b in enumerate('abcd') if by[b]), default=-1)
    for i, b in enumerate('abcd'):
        first, size = BLOCKS[b]
        if i > last:
            break
        rows = by[b]
        slots += [(first + k, it) for k, it in enumerate(rows)]
        if i < last:
            slots += [(first + k, None) for k in range(len(rows), size)]
    return slots


def atlas_place(items):
    """{id(item): (atlas rel, x, y)} (rows of th*32 px, cumulative) and the pad cell y of atlas A"""
    place, pad_y = {}, 0
    for b in 'abc':
        y = 0
        for it in (i for i in items if i.block == b):
            place[id(it)] = (ATLAS_REL[b], 0, y)
            y += it.th * P.TILE
        if b == 'a':
            pad_y = y
    return place, pad_y


def family_variants(items):
    n, out = {}, {}
    for it in items:
        n[it.pack] = n.get(it.pack, 0) + 1
        out[id(it)] = n[it.pack]
    return out


def extra_text(it, variant):
    parts = ['family=%s|variant=%d' % (it.pack, variant)]
    if it.grid:
        parts.append('grid=%s' % it.grid)
    parts += ['%s=%s' % kv for kv in it.extra.items()]
    return '|'.join(parts)


def spec_rows(items):
    place, pad_y = atlas_place(items)
    var = family_variants(items)
    rows = []
    for cid, it in layout(items):
        if it is None:
            rows.append(['pad_%d' % cid, 'item', 'decor', 'blank padding', PAD_ATLAS, 0, pad_y, 1, 1, 1, 1, '', 'new', '',
                         'blank=1'])
            continue
        atlas, x, y = place[id(it)]
        ex = extra_text(it, var[id(it)])
        rows.append([it.key, 'item', it.kind, it.name, atlas, x, y, it.tw, it.th, 1, len(it.frames), it.flags, 'new', '', ex])
    return rows


def source_of(it):
    return '%s/%s' % (it.pack, it.path) + ('[%s]' % it.cell if it.cell else '')


def source_rows(items):
    return [[it.key, 'item', it.pack_label, source_of(it), LICENCE[it.pack_label]] for it in items]


def atlases(items):
    """{ 'pack30_items/items_<a|b|c>.png': RGBA array }: one 32 px row per item, its phases to the right; atlas A ends with a
    clear pad cell when any pad row exists"""
    out = {}
    slots = layout(items)
    pads = any(it is None for _, it in slots)
    for b in 'abc':
        part = [it for it in items if it.block == b]
        if not part and not (b == 'a' and pads):
            continue
        high = sum(it.th for it in part) + (1 if b == 'a' and pads else 0)
        a = np.zeros((high * P.TILE, max([len(it.frames) * it.tw for it in part] + [1]) * P.TILE, 4), np.uint8)
        y = 0
        for it in part:
            h, w = it.th * P.TILE, it.tw * P.TILE
            for f, fr in enumerate(it.frames):
                a[y:y + h, f * w:(f + 1) * w] = fr
            y += h
        out[ATLAS_REL[b] + '.png'] = a
    return out


def tables(items):
    return {SPEC: P.csv_text(FIELDS, spec_rows(items)), SOURCES_CSV: P.csv_text(SOURCE_FIELDS, source_rows(items))}


# ---------------------------------------------------------------------------------------------- checks without art
def parse_csv(text):
    return list(csv.reader(io.StringIO(text)))


def extra_of(text):
    return dict(p.split('=', 1) for p in text.split('|') if '=' in p)


def block_of(cid):
    for b, (first, size) in BLOCKS.items():
        if first <= cid < first + size:
            return b
    return None


def check_tables(spec_text, sources_text, sums_text, packs, files, atlas_dir=None):
    """Problems in the committed tables, from the tables alone (CI without the packs). -> [text]"""
    bad = []
    rows = parse_csv(spec_text)
    if not rows or rows[0] != FIELDS:
        return ['spec: header must be %s' % ','.join(FIELDS)]
    rows = rows[1:]
    if len(rows) > ALL_IDS:
        bad.append('spec: %d rows, the items blocks hold %d' % (len(rows), ALL_IDS))
    pack_by = P.pack_by_slug(packs)
    dims = {(f.slug, f.path): (int(f.w), int(f.h)) for f in files if f.w}
    keys, used, per_block = set(), set(), {}
    pad_y = sum(int(r[8]) for r in rows[:BLOCKS['a'][1]] if len(r) == len(FIELDS) and not r[0].startswith('pad_')) * P.TILE
    ycum = {}
    for i, r in enumerate(rows):
        cid = FIRST_ID + i
        b = block_of(cid)
        if len(r) != len(FIELDS):
            bad.append('spec row %d: bad row' % (i + 1))
            continue
        key, kind, ph, flags, ex = r[0], r[2], int(r[10]), r[11], extra_of(r[14])
        where = 'spec %s' % key
        if b is None or b == 'd':
            bad.append(where + ': id %d is outside the used blocks (D is reserve)' % cid)
            continue
        if key in keys:
            bad.append(where + ': duplicate key')
        keys.add(key)
        pad = key.startswith('pad_')
        size_ok = r[7:10] == ['1', '1', '1'] if pad else (r[7].isdigit() and r[8].isdigit() and r[9] == '1' and
                                                          1 <= int(r[7]) <= P.MAX_TILES and 1 <= int(r[8]) <= P.MAX_TILES)
        if r[1] != 'item' or r[12] != 'new' or r[13] != '' or not size_ok:
            bad.append(where + ': cat / size / patterns / mode')
            continue
        if pad:
            if key != 'pad_%d' % cid or kind != 'decor' or flags or ex.get('blank') != '1' or ph != 1 or \
                    (r[4], r[5], r[6]) != (PAD_ATLAS, '0', str(pad_y)):
                bad.append(where + ': a pad row is pad_<id>, decor, no flags, blank=1 and the pad cell of atlas A')
            per_block.setdefault(b, []).append('pad')
            continue
        per_block.setdefault(b, []).append('real')
        if per_block[b][-2:-1] == ['pad']:
            bad.append(where + ': a real row after a pad row of its block')
        used.add(r[4])
        if not re.fullmatch(r'[a-z0-9_]+__[a-z0-9_]+', key):
            bad.append(where + ': key is not <pack slug>__<stem>')
        if kind not in KINDS:
            bad.append(where + ': kind %r' % kind)
        toks = flags.split()
        names = [t.split(':')[0] for t in toks]
        if any(n not in FLAG_WORDS for n in names) or len(set(names)) != len(names):
            bad.append(where + ': flags %r' % flags)
        if (ph > 1) != ('animateAlways' in names) or (ph > 1) != ('ms' in ex) or not 1 <= ph <= 255:
            bad.append(where + ': phases %d and animateAlways / ms' % ph)
        fam = ex.get('family')
        if fam not in pack_by or CAT not in pack_by[fam].cats() or not key.startswith(fam + '__') or \
                PACK_BLOCK.get(fam) != b:
            bad.append(where + ': family %r in block %s' % (fam, b.upper()))
        want_atlas = ATLAS_REL[b]
        if r[4] != want_atlas or r[5] != '0':
            bad.append(where + ': atlas %s x %s, expected %s x 0' % (r[4], r[5], want_atlas))
        elif int(r[6]) != ycum.get(b, 0):
            bad.append(where + ': atlas row differs from the layout')
        ycum[b] = ycum.get(b, 0) + int(r[8]) * P.TILE
    if rows and rows[-1][0].startswith('pad_'):
        bad.append('spec: the last row is a pad row')
    reals = [r for r in rows if not r[0].startswith('pad_') and len(r) == len(FIELDS)]
    src = parse_csv(sources_text)
    if not src or src[0] != SOURCE_FIELDS:
        bad.append('sources: header must be %s' % ','.join(SOURCE_FIELDS))
        src = [[]]
    src = src[1:]
    if [s[0] for s in src] != [r[0] for r in reals]:
        bad.append('sources: names differ from the spec keys (same order, no pad rows)')
    for s, r in zip(src, reals):
        if len(s) != len(SOURCE_FIELDS):
            bad.append('sources: bad row %r' % s)
            continue
        m = re.fullmatch(r'([a-z0-9_]+)/(.+?)(?:\[(r\d+c\d+|y\d+x\d+)\])?', s[3])
        if not m or (m.group(1), m.group(2)) not in dims:
            bad.append('sources %s: %s is not in pack30_items.files' % (s[0], s[3]))
            continue
        p = pack_by.get(m.group(1))
        if p is None or s[2] != p.label or s[4] != LICENCE.get(p.label):
            bad.append('sources %s: label or licence' % s[0])
        w, h = dims[(m.group(1), m.group(2))]
        cell = m.group(3)
        grid = extra_of(r[14]).get('grid')
        if bool(cell) != bool(grid):
            bad.append('sources %s: cell and grid extra disagree' % s[0])
        elif cell and cell[0] == 'r':
            rr, cc = (int(v) for v in re.fullmatch(r'r(\d+)c(\d+)', cell).groups())
            c = int(grid) if grid.isdigit() else 0
            if c not in CELLS or (cc + 1) * c > w or (rr + 1) * c > h:
                bad.append('sources %s: cell outside the file' % s[0])
        elif cell:
            yy, xx = (int(v) for v in re.fullmatch(r'y(\d+)x(\d+)', cell).groups())
            if grid != 'seg' or yy + P.TILE > h or xx + P.TILE > w:
                bad.append('sources %s: cell outside the file' % s[0])
        elif m.group(1) == 'potions' and (w, h) != (FRAME * ph_of(r), FRAME):
            bad.append('sources %s: strip size differs from the phases' % s[0])
    sum_of = {}
    for line in sums_text.splitlines():
        d, _, p = line.partition('  ')
        sum_of[p] = d
    want = sorted(a + '.png' for a in used | ({PAD_ATLAS} if any(r[0].startswith('pad_') for r in rows) else set()))
    if sorted(sum_of) != want:
        bad.append('sums: must list exactly %s' % ', '.join(want))
    if atlas_dir:
        for rel in want:
            p = os.path.join(atlas_dir, rel)
            if not os.path.exists(p):
                continue
            a = np.asarray(Image.open(p).convert('RGBA'))
            blk = [k for k, v in ATLAS_REL.items() if rel == v + '.png'][0]
            part = [r for r in rows if r[4] + '.png' == rel and not r[0].startswith('pad_')]
            high = sum(int(r[8]) for r in part) + (1 if blk == 'a' and any(r[0].startswith('pad_') for r in rows) else 0)
            wid = max([int(r[10]) * int(r[7]) for r in part] + [1]) * P.TILE
            if a.shape != (high * P.TILE, wid, 4):
                bad.append('%s: shape %s differs from the spec' % (rel, a.shape))
            elif P.digest(a) != sum_of.get(rel):
                bad.append('%s: differs from pack30_items.sums' % rel)
    return bad


def ph_of(r):
    return int(r[10])


def read(path):
    return open(path, newline='', encoding='utf-8').read() if os.path.exists(path) else None


def check_without_art():
    texts = [read(p) for p in (SPEC, SOURCES_CSV, SUMS)]
    if None in texts:
        print('missing', [p for p, t in zip((SPEC, SOURCES_CSV, SUMS), texts) if t is None])
        return False
    bad = check_tables(*texts, P.load_packs(), P.read_files(P.files_path(CAT)), atlas_dir=ART)
    n = len(parse_csv(texts[0])) - 1
    print('\n'.join(bad))
    print('pack30 items check (no sources): %d rows, ids %d..%d:' % (n, FIRST_ID, FIRST_ID + n - 1),
          'OK' if not bad else 'FAILED')
    return not bad


# ---------------------------------------------------------------------------------------------- build
def build(src, check):
    if not src:
        if not check:
            sys.exit('build needs --src (the drivepacks folder); without it only --check runs')
        return check_without_art()
    packs = P.load_packs()
    rows = P.read_files(P.files_path(CAT))
    items, rep = collect(src, rows, packs, P.load_private(), P.load_overrides())
    if not items:
        print('ERROR: nothing to build (no ready items pack)')
        return False
    files = dict(tables(items))
    sheets = atlases(items)
    files[SUMS] = P.sums_text(sorted(sheets.items()))
    slots = layout(items)
    n = {b: sum(1 for it in items if it.block == b) for b in BLOCKS}
    pad = sum(1 for _, it in slots if it is None)
    print('items: %d (weapons %d, books %d, flasks %d), %d pad rows, ids %d..%d of %d..%d; %d duplicates skipped, %d empty '
          'cells dropped' % (len(items), n['a'], n['b'], n['c'], pad, FIRST_ID, FIRST_ID + len(slots) - 1, FIRST_ID, LAST_ID,
                             len(rep['dups']), len(rep['dropped'])))
    for (slug, path), (g, valid) in sorted(rep['grids'].items()):
        print('  grid %s/%s: %s (cells no component crosses: %s)' % (slug, path, 'segments' if g == 'seg' else '%s px cells' % g,
                                                                  valid or 'none'))
    bad = check_tables(files[SPEC], files[SOURCES_CSV], files[SUMS], packs, rows)
    if bad:
        print('\n'.join(bad))
        return False
    if check:
        ok = all(read(p) == t for p, t in files.items())
        for rel, a in sheets.items():
            p = os.path.join(ART, rel)
            if os.path.exists(p) and not np.array_equal(np.asarray(Image.open(p).convert('RGBA')), a):
                print(rel, 'differs from a rebuild')
                ok = False
        for p, t in files.items():
            if read(p) != t:
                print(os.path.relpath(p, ART), 'differs from a rebuild')
        print('pack30 items check:', 'OK' if ok else 'FAILED')
        return ok
    os.makedirs(OUT_DIR, exist_ok=True)
    for rel, a in sheets.items():
        Image.fromarray(a, 'RGBA').save(os.path.join(ART, rel), optimize=True)
    for p, t in files.items():
        with open(p, 'w', newline='', encoding='utf-8') as f:
            f.write(t)
        print('wrote', os.path.relpath(p, ART))
    return True


def cmd_preview(a):
    """owner only: every atlas as a mosaic, 3x, on a grey background; outside git, not opened by agents"""
    os.makedirs(a.out, exist_ok=True)
    for b in 'abc':
        p = os.path.join(ART, ATLAS_REL[b] + '.png')
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert('RGBA')
        w, h = im.size
        bg = Image.new('RGBA', (w, h), (60, 60, 60, 255))
        bg.alpha_composite(im)
        bg.resize((w * 3, h * 3), Image.NEAREST).save(os.path.join(a.out, 'items_%s.png' % b))
    print('previews in', a.out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'preview':
            cmd_preview(a)
            return 0
        return 0 if build(a.src, a.check) else 1
    except P.PackError as e:
        print('ERROR:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())
