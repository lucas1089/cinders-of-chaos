#!/usr/bin/env python3
"""Pair 30, grounds: 32 x 32 floor tiles, ground overlays and animated floors (lava, water) cut from the floor parts of
the purchased builder and ground packs, as ground items of client ids 34859..35158 (server ids + 3000).

    python3 -I gen_pack30_grounds.py build --src DRIVEPACKS            # -> art_import/pack30_grounds/grounds_<n>.png
                                                                       #    + art_import/pack30_grounds.csv, .sums
                                                                       #    + art_import/pack30_grounds_sources.csv
    python3 -I gen_pack30_grounds.py build --src DRIVEPACKS --check    # rebuild in memory, compare with everything
    python3 -I gen_pack30_grounds.py build --check                     # CI, no packs: tables agree with each other and
                                                                       #    with pack30_grounds.files; atlases on disk
                                                                       #    (if any) match the sums
    python3 -I gen_pack30_grounds.py preview --out DIR                 # owner only: a mosaic of the atlases, outside git

Import-only (PLAN_PAIR30 section 0, docs/SPRITE_STYLE.md): the packs ban machine-learning use and sharing. No pack image is
viewed, style-measured, palette-sampled or given to an AI tool. This script reads pixels only for geometry (which cells
of a sheet are empty or opaque, exact duplicates) and for the one number an item needs, the mean colour of a tile, which
picks its minimap colour. Names: a tile has a neutral key `<pack slug>__<stem>[__r<row>c<col>]` (the pack slugs of
art_import/pack30_packs.csv); the internal labels of the packs are in the sources CSV; docs/CREDITS.md names the packs.
Neither the packs nor the cut atlases are committed (art_import/pack30_grounds/ is ignored by git); the sums hold the sha256
of every atlas' pixels.

What is cut (rules are file-name and size tables, no image is looked at):
  * single tiles   files in a floor folder (`floor`, `floors`, `floor_tiles`, `paths`, `ground` and their path / mud
                   sub-folders) or with a floor word in the name (FLOOR_FILE), 32 x 32 (or 64 x 64: four cells), minus
                   the object words of NOT_FLOOR (flowers, logs, rocks, stumps, tufts);
  * strips         the animated floors of ANIM_FILE: `_strip<N>` files of N frames of 32 px (one animated item) or of 64 px
                   (four animated items, one per 32 px quarter), all phases of a family with the same ms;
  * sheets         floor sheets: gap grids of 33 px pitch (131 px = 4 cells, 197 px = 6 cells, 1 px gaps, pack30lib.grid_detect)
                   and the two 1024 px sheets cut at 32 px (a seam test shows distinct 32 px cells; there are about 1000 each,
                   so SHEETS caps how many, in reading order, exact duplicates skipped).
  A tile whose every frame is fully opaque (alpha >= 12 everywhere) is a floor: kind `ground` (`water` for lava and water
  liquids), flags `ground:100 notmoveable minimap:<mean colour> fullground`, liquids `notwalkable`, lava `light:2:195`.
  Any other tile with some art is an overlay: kind `border` (flags `clip notmoveable`, top order 1, drawn over the ground);
  no auto-border logic is built, the map maker places them by hand. A tile with no art is dropped and listed. Animated tiles
  carry `animateAlways` and `ms=<ms>` (LIQUID_MS / FLOOR_MS). Exact duplicates (same pixels and frames) are kept once.
  Overrides (art_import/pack30_overrides.csv, key = the tile key): skip, rename, kind, flags, light, blocking.
Ids: a tile's id is FIRST_ID + its place in the plan order (pack slug, then file path, then cell); more than the block holds
(300) stops the build with an error (the integrator then moves the overflow, PLAN_PAIR30 section 2).
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

CAT = 'grounds'
FIRST_ID = 34859
BLOCK = 300
LAST_ID = FIRST_ID + BLOCK - 1          # 35158
ART = P.ART
OUT_DIR = os.path.join(ART, 'pack30_grounds')
SPEC = os.path.join(ART, 'pack30_grounds.csv')
SUMS = os.path.join(ART, 'pack30_grounds.sums')
SOURCES_CSV = os.path.join(ART, 'pack30_grounds_sources.csv')
ATLAS_REL = 'pack30_grounds/grounds_%d'          # the spec's atlas column (no .png), relative to art_import/
ATLAS_ROWS = 100                                  # tiles per atlas, one tile per 32 px row, phases to the right
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
SOURCE_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']
LICENCE = {
    'set30 mutter': ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
                     'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md'),
    'set30 pocket': ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
                     'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md'),
}
GROUND_SPEED = 100
LAVA_LIGHT = (2, 195)       # level, minimap colour index (PLAN_PAIR30 3.3)
LIQUID_MS = 160             # lava and water, every phase of every family
FLOOR_MS = 140              # other animated floors and overlays
KINDS = ('ground', 'water', 'border')
FLAG_WORDS = ('ground', 'notmoveable', 'minimap', 'fullground', 'notwalkable', 'light', 'clip', 'animateAlways')

# ---------------------------------------------------------------------------------------------- selection tables
_I = re.I
FLOOR_DIR = re.compile(r'(^|/)(floors?|floor_tiles|paths|ground|dirt path|stone path|mud)(/|$)', _I)
FLOOR_FILE = re.compile(r'(floor_?t[il][lt]es?[._]|sand_floor_tile_|mud_floor\.|stone_floor|castle_floor_|'
                        r'sewer_floor_\d\.|(^|/)spr_lava\.png$|lava_island_floor\.)', _I)
NOT_FLOOR = re.compile(r'flower|mushroom|stump|tall_grass|leaf_pile|tuft|rock|(^|[_/ ])logs?[_.]', _I)
ANIM_FILE = re.compile(r'(lava_pool_|lava_bubbles_|lava_island_[a-z_]+_strip\d+|lake_tile\w*_strip|'
                       r'sewer_floor_\d_strip|sewer_water\w*_strip)', _I)
LIQUID = re.compile(r'(lava_pool|lava_bubbles|(^|/)spr_lava\.png|lake_|sewer_water)', _I)
STRIP = re.compile(r'_strip(\d+)\.png$', _I)
# floor sheets: (pack slug, file) -> cap on the cells taken in reading order (None = all)
SHEETS = {
    ('autumn_graveyard', 'Sheet_1_Autumn_Graveyard_Floors.png'): None,
    ('frozen_ruins', 'Sheet 1 Snowy Stone Floor Tiles.png'): None,
    ('frozen_ruins', 'sheet 2 Snow Ground Tiles.png'): None,
    ('desert_kit', 'Desert Floor Tiles.png'): 48,
    ('graveyard_kit', '1_FloorTiles_Sheet.png'): 48,
}


class Tile:
    def __init__(self, pack, path, frames, cell=None, anim=False):
        self.pack, self.path, self.frames, self.cell, self.anim = pack, path, frames, cell, anim
        self.key = self.name = self.kind = self.flags = None
        self.cov = 0.0
        self.opaque = False


def stem_of(slug, path):
    """the file stem as a neutral slug: no extension, no sprite prefix, no strip count, no sheet number, no pack slug"""
    s = P.slugify(os.path.splitext(path.split('/')[-1])[0])
    s = re.sub(r'_?strip\d+$', '', s)
    s = re.sub(r'^(spr|sp)_', '', s)
    s = re.sub(r'^(sheet_)?\d+_', '', s)
    s = s.replace(slug + '_', '').replace('_' + slug, '')
    return s or 'tile'


def cell_suffix(cell):
    return None if cell is None else 'r%dc%d' % cell


def plan_jobs(rows, packs):
    """The files to cut, in plan order: [(slug, path, mode, cap)] with mode tile|strip|sheet. Only ready packs that list
    `grounds` in their categories; decided by file name and size only."""
    ok = {p.slug for p in packs if p.status == 'ready' and CAT in p.cats()}
    jobs = []
    for r in sorted(rows, key=lambda r: (r.slug, r.path)):
        if r.slug not in ok or not r.path.lower().endswith('.png'):
            continue
        w, h = int(r.w), int(r.h)
        if (r.slug, r.path) in SHEETS:
            jobs.append((r.slug, r.path, 'sheet', SHEETS[(r.slug, r.path)]))
        elif STRIP.search(r.path):
            if ANIM_FILE.search(r.path):
                jobs.append((r.slug, r.path, 'strip', None))
        elif (FLOOR_DIR.search(r.path) or FLOOR_FILE.search(r.path)) and not NOT_FLOOR.search(r.path):
            if w % P.TILE == 0 and h % P.TILE == 0 and w <= 2 * P.TILE and h <= 2 * P.TILE:
                jobs.append((r.slug, r.path, 'tile', None))
    return jobs


def cut_job(job, rows_by, src, private):
    """-> [Tile] for one job (verified against the md5 of the committed list before decoding)"""
    slug, path, mode, cap = job
    row = rows_by[(slug, path)]
    a = P.clean_alpha(P.load_verified(P.source_path(src, slug, path, private), row.md5))
    H, W = a.shape[:2]
    if (W, H) != (int(row.w), int(row.h)):
        raise P.PackError('%s/%s: %dx%d, the list has %sx%s' % (slug, path, W, H, row.w, row.h))
    T = P.TILE
    out = []
    if mode == 'tile':
        multi = W > T or H > T
        for r in range(H // T):
            for c in range(W // T):
                out.append(Tile(slug, path, [a[r * T:(r + 1) * T, c * T:(c + 1) * T]], (r, c) if multi else None))
    elif mode == 'strip':
        n = int(STRIP.search(path).group(1))
        if W % n:
            raise P.PackError('%s/%s: width %d is not %d frames' % (slug, path, W, n))
        fw = W // n
        if fw not in (T, 2 * T) or H != fw:
            raise P.PackError('%s/%s: frames of %dx%d, expected square 32 or 64 px' % (slug, path, fw, H))
        fr = P.strip_frames(a, fw)
        for r in range(fw // T):
            for c in range(fw // T):
                out.append(Tile(slug, path, [f[r * T:(r + 1) * T, c * T:(c + 1) * T] for f in fr],
                                (r, c) if fw > T else None, anim=True))
    else:
        g = P.grid_detect(a)
        if g is None:
            if W % T or H % T:
                raise P.PackError('%s/%s: no grid found for %dx%d' % (slug, path, W, H))
            g = {'cell': T, 'gap': 0, 'nx': W // T, 'ny': H // T, 'pitch': T, 'how': 'cells32 (assumed)'}
        if g['cell'] != T:
            raise P.PackError('%s/%s: grid of %d px cells, expected 32' % (slug, path, g['cell']))
        for r in range(g['ny']):
            for c in range(g['nx']):
                y, x = r * g['pitch'], c * g['pitch']
                out.append(Tile(slug, path, [a[y:y + T, x:x + T]], (r, c)))
    return out


def coverage(t):
    return min(float((f[..., 3] >= P.ALPHA_MIN).mean()) for f in t.frames), max(
        float((f[..., 3] >= P.ALPHA_MIN).mean()) for f in t.frames)


def tile_digest(t):
    return P.digest(np.stack(t.frames))


def classify(t, ov):
    lo, hi = coverage(t)
    t.cov, t.opaque = lo, lo == 1.0
    full = ('%s/%s' % (t.pack, t.path)).lower()
    liquid = bool(LIQUID.search(t.path))
    kind = 'ground' if t.opaque else 'border'
    if t.opaque and liquid:
        kind = 'water'
    k = P.ov_get(ov, t.key, 'kind')
    if k:
        if k not in KINDS:
            raise P.PackError('%s: kind override %r not one of %s' % (t.key, k, ', '.join(KINDS)))
        kind = k
    t.kind = kind
    t.liquid = liquid
    t.lava = liquid and 'lava' in full
    return t


def flags_of(t, ov):
    custom = P.ov_get(ov, t.key, 'flags')
    if custom:
        return custom
    toks = []
    if t.kind in ('ground', 'water'):
        toks += ['ground:%d' % GROUND_SPEED, 'notmoveable', 'minimap:%d' % t.minimap, 'fullground']
        if t.liquid or P.ov_get(ov, t.key, 'blocking') == 1:
            toks.append('notwalkable')
        lt = P.ov_get(ov, t.key, 'light') or (LAVA_LIGHT if t.lava else None)
        if lt:
            toks.append('light:%d:%d' % lt)
    else:
        toks += ['clip', 'notmoveable']
        lt = P.ov_get(ov, t.key, 'light')
        if lt:
            toks.append('light:%d:%d' % lt)
    if len(t.frames) > 1:
        toks.append('animateAlways')
    return ' '.join(toks)


def collect(src, rows, packs, private=None, ov=None):
    """Cut and classify every tile. -> (tiles in id order, report dict). Stops on an overflow of the block."""
    ov = {} if ov is None else ov
    rows_by = {(r.slug, r.path): r for r in rows}
    pack_by = P.pack_by_slug(packs)
    tiles, seen, dropped, dups, capped = [], {}, [], [], []
    keys = set()
    for job in plan_jobs(rows, packs):
        slug, path, mode, cap = job
        taken = 0
        for t in cut_job(job, rows_by, src, private):
            stem = stem_of(slug, path)
            t.key = P.key_of(slug, stem, cell_suffix(t.cell))
            if t.key in keys:       # two files with one stem: add the folder
                parent = P.slugify(path.rsplit('/', 1)[0]) if '/' in path else 'x'
                t.key = P.key_of(slug, parent + '_' + stem, cell_suffix(t.cell))
            if t.key in keys:
                raise P.PackError('%s: two tiles with one key (rename one with an override)' % t.key)
            if P.ov_get(ov, t.key, 'skip') == 1:
                continue
            classify(t, ov)
            lo, hi = coverage(t)
            if hi == 0.0:
                dropped.append('%s/%s %s' % (slug, path, cell_suffix(t.cell) or ''))
                continue
            d = tile_digest(t)
            if d in seen:
                dups.append((t.key, seen[d]))
                continue
            if cap is not None and taken >= cap:
                capped.append(t.key)
                continue
            taken += 1
            keys.add(t.key)
            seen[d] = t.key
            allf = np.concatenate([f.reshape(-1, 4) for f in t.frames])
            t.minimap = P.rgb_to_minimap_index(P.mean_rgb(allf.reshape(1, -1, 4))) if t.kind != 'border' else 0
            t.pack_label = pack_by[slug].label
            t.name = P.ov_get(ov, t.key, 'rename') or '%s (%s)' % (
                P.humanize(stem) + (' ' + cell_suffix(t.cell).upper() if t.cell else ''), P.humanize(slug))
            t.flags = flags_of(t, ov)
            tiles.append(t)
    if len(tiles) > BLOCK:
        raise P.PackError('grounds need %d ids, the block holds %d (client %d..%d): move the overflow to the overflow range '
                          '(PLAN_PAIR30 section 2) or lower the SHEETS caps' % (len(tiles), BLOCK, FIRST_ID, LAST_ID))
    return tiles, {'dropped': dropped, 'dups': dups, 'capped': capped}


# ---------------------------------------------------------------------------------------------- tables
def ms_of(t):
    return LIQUID_MS if t.liquid or 'lava_island' in t.path.lower() else FLOOR_MS


def atlas_of(i):
    return ATLAS_REL % (i // ATLAS_ROWS + 1), (i % ATLAS_ROWS) * P.TILE


def family_variants(tiles):
    n, out = {}, []
    for t in tiles:
        n[t.pack] = n.get(t.pack, 0) + 1
        out.append(n[t.pack])
    return out


def spec_rows(tiles):
    rows = []
    var = family_variants(tiles)
    for i, t in enumerate(tiles):
        atlas, y = atlas_of(i)
        extra = 'family=%s|variant=%d' % (t.pack, var[i])
        if len(t.frames) > 1:
            extra += '|ms=%d' % ms_of(t)
        rows.append([t.key, 'item', t.kind, t.name, atlas, 0, y, 1, 1, 1, len(t.frames), t.flags, 'new', '', extra])
    return rows


def source_of(t):
    return '%s/%s' % (t.pack, t.path) + ('[%s]' % cell_suffix(t.cell) if t.cell else '')


def source_rows(tiles):
    return [[t.key, 'item', t.pack_label, source_of(t), LICENCE[t.pack_label]] for t in tiles]


def atlases(tiles):
    """{ 'pack30_grounds/grounds_<n>.png': RGBA array } : one 32 px row per tile, its phases left to right"""
    out = {}
    for n in range((len(tiles) + ATLAS_ROWS - 1) // ATLAS_ROWS):
        part = tiles[n * ATLAS_ROWS:(n + 1) * ATLAS_ROWS]
        a = np.zeros((len(part) * P.TILE, max(len(t.frames) for t in part) * P.TILE, 4), np.uint8)
        for r, t in enumerate(part):
            for f, fr in enumerate(t.frames):
                a[r * P.TILE:(r + 1) * P.TILE, f * P.TILE:(f + 1) * P.TILE] = fr
        out[(ATLAS_REL % (n + 1)) + '.png'] = a
    return out


def tables(tiles):
    return {SPEC: P.csv_text(FIELDS, spec_rows(tiles)), SOURCES_CSV: P.csv_text(SOURCE_FIELDS, source_rows(tiles))}


# ---------------------------------------------------------------------------------------------- checks without art
def parse_csv(text):
    return list(csv.reader(io.StringIO(text)))


def extra_of(text):
    return dict(p.split('=', 1) for p in text.split('|') if '=' in p)


def check_tables(spec_text, sources_text, sums_text, packs, files, atlas_dir=None):
    """Problems in the committed tables, from the tables alone (CI without the packs). -> [text]"""
    bad = []
    rows = parse_csv(spec_text)
    if not rows or rows[0] != FIELDS:
        return ['spec: header must be %s' % ','.join(FIELDS)]
    rows = rows[1:]
    if len(rows) > BLOCK:
        bad.append('spec: %d rows, the block holds %d' % (len(rows), BLOCK))
    pack_by = P.pack_by_slug(packs)
    dims = {(f.slug, f.path): (int(f.w), int(f.h)) for f in files if f.w}
    keys, maxph = set(), {}
    for i, r in enumerate(rows):
        key, kind, ph, flags, ex = r[0], r[2], int(r[10]), r[11], extra_of(r[14])
        where = 'spec %s' % key
        if key in keys:
            bad.append(where + ': duplicate key')
        keys.add(key)
        if not re.fullmatch(r'[a-z0-9_]+__[a-z0-9_]+', key):
            bad.append(where + ': key is not <pack slug>__<stem>')
        if r[1] != 'item' or kind not in KINDS or r[12] != 'new' or r[13] != '' or r[7:10] != ['1', '1', '1']:
            bad.append(where + ': cat / kind / size / patterns / mode')
        atlas, y = atlas_of(i)
        if (r[4], r[5], r[6]) != (atlas, '0', str(y)):
            bad.append(where + ': atlas place differs from the layout')
        maxph[atlas] = max(maxph.get(atlas, 1), ph)
        toks = flags.split()
        names = [t.split(':')[0] for t in toks]
        if any(n not in FLAG_WORDS for n in names) or len(set(names)) != len(names):
            bad.append(where + ': flags %r' % flags)
        if kind == 'border' and 'minimap' in names:
            bad.append(where + ': an overlay has no minimap colour')
        if kind != 'border':
            m = [t for t in toks if t.startswith('minimap:')]
            if not m or not 1 <= int(m[0][8:]) <= 215 or 'fullground' not in names or 'ground' not in names:
                bad.append(where + ': ground flags / minimap colour')
        if (ph > 1) != ('animateAlways' in names) or (ph > 1) != ('ms' in ex) or not 1 <= ph <= 13:
            bad.append(where + ': phases %d and animateAlways / ms' % ph)
        fam = ex.get('family')
        if fam not in pack_by or CAT not in pack_by[fam].cats() or not key.startswith(fam + '__'):
            bad.append(where + ': family %r' % fam)
    src = parse_csv(sources_text)
    if not src or src[0] != SOURCE_FIELDS:
        bad.append('sources: header must be %s' % ','.join(SOURCE_FIELDS))
        src = [[]]
    src = src[1:]
    if [s[0] for s in src] != [r[0] for r in rows]:
        bad.append('sources: names differ from the spec keys (same order)')
    for s in src:
        if len(s) != len(SOURCE_FIELDS):
            bad.append('sources: bad row %r' % s)
            continue
        m = re.fullmatch(r'([a-z0-9_]+)/(.+?)(?:\[r(\d+)c(\d+)\])?', s[3])
        if not m or (m.group(1), m.group(2)) not in dims:
            bad.append('sources %s: %s is not in pack30_grounds.files' % (s[0], s[3]))
            continue
        p = pack_by.get(m.group(1))
        if p is None or s[2] != p.label or s[4] != LICENCE.get(p.label):
            bad.append('sources %s: label or licence' % s[0])
        if m.group(3) is not None:
            w, h = dims[(m.group(1), m.group(2))]
            pitch = 33 if (w + 1) % 33 == 0 and (w % 32) else 32
            if int(m.group(4)) * pitch + 32 > w or int(m.group(3)) * pitch + 32 > h:
                bad.append('sources %s: cell outside the file' % s[0])
    sum_of = {}
    for line in sums_text.splitlines():
        d, _, p = line.partition('  ')
        sum_of[p] = d
    want = sorted(a + '.png' for a in maxph)
    if sorted(sum_of) != want:
        bad.append('sums: must list exactly %s' % ', '.join(want))
    if atlas_dir:
        for rel in want:
            p = os.path.join(atlas_dir, rel)
            if not os.path.exists(p):
                continue
            a = np.asarray(Image.open(p).convert('RGBA'))
            n = int(re.search(r'_(\d+)\.png$', rel).group(1)) - 1
            part = rows[n * ATLAS_ROWS:(n + 1) * ATLAS_ROWS]
            if a.shape != (len(part) * P.TILE, maxph[rel[:-4]] * P.TILE, 4):
                bad.append('%s: shape %s differs from the spec' % (rel, a.shape))
            elif P.digest(a) != sum_of.get(rel):
                bad.append('%s: differs from pack30_grounds.sums' % rel)
    return bad


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
    print('pack30 grounds check (no sources): %d tiles, ids %d..%d:' % (n, FIRST_ID, FIRST_ID + n - 1),
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
    tiles, rep = collect(src, rows, packs, P.load_private(), P.load_overrides())
    files = dict(tables(tiles))
    sheets = atlases(tiles)
    files[SUMS] = P.sums_text(sorted(sheets.items()))
    n = len(tiles)
    kinds = {k: sum(1 for t in tiles if t.kind == k) for k in KINDS}
    anim = sum(1 for t in tiles if len(t.frames) > 1)
    print('grounds: %d tiles (ground %d, water %d, border %d; %d animated), ids %d..%d of %d..%d; %d duplicates skipped, '
          '%d empty cells dropped, %d beyond a sheet cap' % (n, kinds['ground'], kinds['water'], kinds['border'], anim,
                                                           FIRST_ID, FIRST_ID + n - 1, FIRST_ID, LAST_ID,
                                                           len(rep['dups']), len(rep['dropped']), len(rep['capped'])))
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
        print('pack30 grounds check:', 'OK' if ok else 'FAILED')
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
    """owner only: every atlas as a mosaic (4 tiles wide per atlas row of 25), 3x, on a checker; outside git, not opened by
    agents"""
    os.makedirs(a.out, exist_ok=True)
    for n in range(1, 10):
        p = os.path.join(ART, (ATLAS_REL % n) + '.png')
        if not os.path.exists(p):
            break
        im = Image.open(p).convert('RGBA')
        w, h = im.size
        bg = Image.new('RGBA', (w, h), (60, 60, 60, 255))
        bg.alpha_composite(im)
        bg.resize((w * 3, h * 3), Image.NEAREST).save(os.path.join(a.out, 'grounds_%d.png' % n))
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
