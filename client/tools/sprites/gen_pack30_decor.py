#!/usr/bin/env python3
"""Pair 30, decoration and props: single objects cut from the object files and the prop sheets of the purchased builder
and prop packs, as items of client ids 35159..36058 (server ids + 3000). Three blocks, three spec CSVs:

    decor-1   35159..35558  (400)  art_import/pack30_decor1.csv   1x1, 1x2 and 2x1 objects (wall decoration included)
    decor-2   35559..36058  (500)  art_import/pack30_decor2.csv   everything bigger, up to 4x4; larger art is cut into pieces
    decor-3   37713..38312  (600)  art_import/pack30_decor3.csv   what the variant and pack caps keep out of decor-1/2 (overflow
                                                                   range, any size; importer pads the gap with blank entries)

    python3 -I gen_pack30_decor.py build --src DRIVEPACKS            # -> art_import/pack30_decor/decor<block>_<n>.png
                                                                     #    + pack30_decor1.csv, pack30_decor2.csv, .sums,
                                                                     #    + pack30_decor_sources.csv   (--verbose lists what was skipped)
    python3 -I gen_pack30_decor.py build --src DRIVEPACKS --check    # rebuild in memory, compare with everything
    python3 -I gen_pack30_decor.py build --check                     # CI, no packs: tables agree with each other and with
                                                                     #    pack30_decor.files; atlases on disk (if any) match the sums
    python3 -I gen_pack30_decor.py preview --out DIR                 # owner only: a mosaic of the atlases, outside git

Import-only (PLAN_PAIR30 section 0, docs/SPRITE_STYLE.md): the packs ban machine-learning use and sharing. No pack image is
viewed, style-measured, palette-sampled or given to an AI tool. Pixels are read for geometry only: the alpha box of an
object, 8-connected components of alpha, exact duplicates. Names: an object has a neutral key
`<pack slug>__<stem>[__r<row>c<col>]` (pack slugs of art_import/pack30_packs.csv); docs/CREDITS.md names the packs. Neither the
packs nor the cut atlases are committed (art_import/pack30_decor/ is ignored by git); the sums hold the sha256 of every atlas.

What is cut (rules are file-name and size tables, no image is looked at):
  * objects     one PNG = one object. 16 px art (both sides at most 16) is Scale2x upscaled (extra `scale2x=1`); every other
                size is padded top/left to a multiple of 32 (bottom-right aligned, never scaled); then whole empty 32 px rows and
                columns at the edges are dropped (the art keeps its place inside the 32 grid).
  * prop sheets SHEETS lists the sheets by hand: `grid` sheets are cut at 32 px cells (empty cells dropped; the wall decoration
                sheets), `segment` sheets are cut with pack30lib.segment_sheet (connected components of alpha, each box grown
                to the 32 grid; a component that crosses a cell edge stays whole; specks under 8 px area are dropped).
  * left to other tasks, listed by --verbose: floors and ground pieces (what gen_pack30_grounds.py claims, taken from its plan),
                animated strips (`_strip<N>`), buildings (BLDG words at 64 px or more, any file of a building pack at 96 px or
                more, any single file over 192 px), light overlays and shadows.
  * art over 4x4 tiles (up to 6x6) is cut by pack30lib.plan_split into pieces of at most 4x4: item `<key>_r<row>c<col>`, extra
                group=<key>|gw=|gh=|piece=r,c; only the south-east piece of a blocking group blocks. Over 6 tiles is skipped.
  Kinds (name words, KIND tables): `wall` hangs on a wall (banners, paintings, portraits, mirrors, windows, shields, hanging
  things; every wall decoration sheet), `stump` blocks (trees, rocks, statues, thrones, tables, chests, barrels, carts, beds,
  shelves, fences, gravestones ...), `decor` is everything else (walkable). Flags: decor `notmoveable`, stump
  `bottom notwalkable notmoveable`, wall `hangable notmoveable`.
  Overrides (art_import/pack30_overrides.csv, key = the object key): skip, rename, kind, flags, blocking, light, tiles (force the
  canvas to W x H tiles, art bottom-right aligned; art that does not fit stops the build), scale2x (0/1), hideout (0/1).
  Exact duplicates (same pixels) are kept once. Extra: family=<pack slug>|hideout=0/1 (size at most 2x2, decor or stump, not a
  low-fit pack; for the hideout catalog) [|scale2x=1] [|group=...].
Ids: an object's id is its place in the plan order (pack slug, file path, cell) inside its block; more than a block holds stops
the build with `block overflow` (the integrator moves the overflow, PLAN_PAIR30 section 2). Atlases hold one object per row
stack, 128 px wide. Deterministic: numpy and Pillow only; same inputs give byte-identical tables.
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
import gen_pack30_grounds as G  # noqa: E402   (its plan decides which files are floors; those are not decoration)

CAT = 'decor'
FIRST_1, BLOCK_1 = 35159, 400
FIRST_2, BLOCK_2 = 35559, 500
LAST_ID = FIRST_2 + BLOCK_2 - 1                   # 36058
# decor-3: everything the family and pack caps keep out of decor-1/2, in the overflow range of PLAN_PAIR30 section 2 (client
# 37113 and up, never 37000..37112 = the donor items; the building overflow uses 37113..37603, so this block starts at 37713)
FIRST_3, BLOCK_3 = 37713, 600
LAST_3 = FIRST_3 + BLOCK_3 - 1                    # 38312 (server 41312)
ART = P.ART
OUT_DIR = os.path.join(ART, 'pack30_decor')
SPEC_1 = os.path.join(ART, 'pack30_decor1.csv')
SPEC_2 = os.path.join(ART, 'pack30_decor2.csv')
SPEC_3 = os.path.join(ART, 'pack30_decor3.csv')
SUMS = os.path.join(ART, 'pack30_decor.sums')
SOURCES_CSV = os.path.join(ART, 'pack30_decor_sources.csv')
ATLAS_REL = 'pack30_decor/decor%d_%d'             # block, number; the spec's atlas column (no .png), relative to art_import/
ATLAS_H = 4096                                    # px; a new atlas starts when the next object would pass it
SPLIT_MAX = 6                                     # art up to 6x6 tiles is cut into pieces, more is skipped
SINGLE_MAX_PX = SPLIT_MAX * P.TILE                # a single file over this is a building or a sheet
MIN_AREA = 8                                      # specks of a segmented sheet under this many px are dropped
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
SOURCE_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']
_LIC = ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
        'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md')
LICENCE = {'set30 mutter': _LIC, 'set30 pocket': _LIC}
KINDS = ('decor', 'stump', 'wall', 'prop')
FLAG_WORDS = ('bottom', 'top', 'clip', 'notwalkable', 'notmoveable', 'blockmissile', 'blockpath', 'hangable', 'light',
              'translucent', 'donthide')
KIND_FLAGS = {'decor': 'notmoveable', 'prop': 'notmoveable', 'stump': 'bottom notwalkable notmoveable',
              'wall': 'hangable notmoveable'}

# ---------------------------------------------------------------------------------------------- selection tables
_I = re.I
STRIP = re.compile(r'_strip\d+\.png$', _I)
SKIP_FILE = re.compile(r'shadow|shawdow|window_light', _I)


def _words(*ws):
    """a regex that matches any of the words as whole words (letters around it do not count; `_`, digits, spaces do),
    optionally in the plural"""
    return re.compile(r'(?<![a-z])(?:%s)s?(?![a-z])' % '|'.join(ws), _I)


BLDG = _words('house', 'houses', 'cottage', 'greenhouse', 'inn', 'tavern', 'barracks', 'black_smith', 'smith', 'keep',
              'tower', 'store(?!age)', 'station', 'school', 'hospital', 'pharmacy', 'supermarket', 'apartment', 'diner',
              'warehouse', 'workshop', 'lighthouse', 'shed', 'building', 'buildings', 'temple')
MOUNT = _words(r'banner(?!_?stand)', 'painting', 'picture', 'portrait', 'mirror', r'window(?!_light)', r'shield(?!_?stand)',
               'hanging', 'wall_pillow', 'wall_banner', 'wall_light')
BLOCK = _words('tree', 'rock', 'stone', 'statue', 'throne', 'table', 'chest', 'barrel', 'cart', 'stove', 'bed(?!_?roll)',
               'wardrobe', 'clock', 'fireplace', 'bench', 'shelf', 'shelve', 'rack', 'cage', 'altar', 'totem', 'fountain',
               'well', 'pillar', 'ancient_pillow', 'wall', 'crate', 'box', 'dumpster', 'bin', 'machine', 'tank', 'bus', 'taxi',
               'sedan', 'car', 'shelter', 'stall', 'fence', 'gate', 'barricade', 'cactus', 'crystal', 'cluster', 'gravestone',
               'grave', 'tomb(?:stone)?', 'coffin', 'sarcophagus', 'obelisk', 'cliff', 'lift', 'wheelbarrow', 'dummy',
               'target', 'lamp_post', 'street_lamp', 'hydrant', 'pump', 'drum', 'stand', 'book_unit', 'dresser', 'draws',
               'bars', 'tent', 'truck', 'pyre', 'cauldron', 'anvil', 'forge', 'bookshelf', 'book_shelf', 'barrier')
PACK_KIND = {'wall_decor': 'wall'}            # every object of the pack
# Budget: decor-1/2 hold 900 ids and the packs hold about 1200 objects. Numbered variants of one family (`tree_1` ... `tree_16`)
# keep the first FAMILY_CAP in natural order in decor-1/2, the rest goes to decor-3; PACK_CAPS is the most objects a pack gives
# to decor-1/2 (the ones with most opaque pixels), the rest goes to decor-3 too. Low-fit packs come last in a block.
FAMILY_CAP = 8
FIT_RANK = {'high': 0, 'medium': 1, 'low': 2}
PACK_CAPS = {                 # slug: (small objects, big objects); None = all
    'autumn_graveyard': (80, None),
    'desert_kit': (30, 35),
    'graveyard_kit': (None, 55),
    'bathroom': (8, None),
    'sewer_kit': (8, None),
}
# prop sheets: (pack slug, file) -> (mode, cap on the objects taken in reading order, None = all); None = not decoration
SHEETS = {
    ('wall_decor', 'Hero_and_Battle_Portraits_Sheet.png'): ('grid', None),
    ('wall_decor', 'Medieval_Banners_Sheet.png'): ('grid', None),
    ('wall_decor', 'Medieval_Paintings_Sheet.png'): ('grid', None),
    ('wall_decor', 'Royal_Portraits_Sheet.png'): ('grid', None),
    ('wall_decor', 'Wall_Shields_Sheet.png'): ('grid', None),
    ('autumn_graveyard', 'Sheet_2_Autumn_Graveyard_Ground_Objects.png'): ('segment', None),
    ('autumn_graveyard', 'Sheet_3_Autumn_Graveyard_Props.png'): ('segment', None),
    ('autumn_graveyard', 'Sheet_4_Autumn_Graveyard_Nature_Details.png'): ('segment', None),
    ('autumn_graveyard', 'Sheet_5_Autumn_Gravestones.png'): ('segment', None),
    ('autumn_graveyard', 'Sheet_6_Autumn_GATES.png'): ('segment', None),
    ('autumn_graveyard', 'Sheet_7_Autumn_buildings.png'): None,
    ('autumn_graveyard', 'Sheet_8_autumm_trees.png'): ('segment', None),
    ('ruined_village', 'Sheet_5_Overgrown_Nature.png'): ('segment', None),
    ('ruined_village', 'Sheet_6_Ruined_Village_Props.png'): ('segment', None),
    ('desert_kit', 'Desert Props.png'): ('segment', None),
    ('desert_kit', 'Desert Nature.png'): ('segment', None),
    ('desert_kit', 'Cliffs.png'): None,
    ('desert_kit', 'Desert Walls.png'): None,
    ('graveyard_kit', '2_Tombstones & Graves_Sheet.png'): ('segment', None),
    ('graveyard_kit', '3_Gates&Fences_Sheet.png'): ('segment', None),
    ('graveyard_kit', '4_Nature Assets Sheet.png'): ('segment', None),
    ('graveyard_kit', '5 Large Structures Sheet.png'): None,
    ('graveyard_kit', '6 Large Dead Tree Sheet.png'): ('segment', None),
    ('frozen_ruins', 'sheet 6 ruins decorations.png'): ('segment', None),
}


class Obj:
    """one cut object, before block assignment. canvas is RGBA, (th*32, tw*32)."""
    def __init__(self, pack, path, canvas, box=None, scaled=False):
        self.pack, self.path, self.canvas, self.box, self.scaled = pack, path, canvas, box, scaled
        self.th, self.tw = canvas.shape[0] // P.TILE, canvas.shape[1] // P.TILE
        self.key = self.name = self.kind = self.label = self.fit = None
        self.hide = 0


class Item:
    """one spec row"""
    def __init__(self, obj, key, name, kind, canvas, flags, extra, piece=None):
        self.obj, self.key, self.name, self.kind, self.canvas, self.flags, self.extra = obj, key, name, kind, canvas, flags, extra
        self.w, self.h = canvas.shape[1] // P.TILE, canvas.shape[0] // P.TILE
        self.piece = piece


def natural(text):
    """sort key: digits compare as numbers (tree_2 before tree_10), case ignored"""
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r'(\d+)', text)]


def stem_of(slug, path):
    """the file stem as a neutral slug: no extension, no sprite prefix, no pack slug"""
    s = P.slugify(os.path.splitext(path.split('/')[-1])[0])
    s = re.sub(r'^(spr|sp)_', '', s)
    s = re.sub(r'^(sheet_)?\d+_', '', s)
    s = s.replace(slug + '_', '').replace('_' + slug, '')
    return s or 'object'


def cell_suffix(box):
    return None if box is None else 'r%dc%d' % (box[1] // P.TILE, box[0] // P.TILE)


def auto_scale2x(w, h):
    return w <= 16 and h <= 16


# ---------------------------------------------------------------------------------------------- plan
def plan_jobs(rows, packs):
    """The files to cut, in plan order: [(slug, path, mode, cap)] with mode single|grid|segment, and the skipped files
    [(slug, path, why)], and the set of files that go to decor-3 (variants beyond FAMILY_CAP). Decided by file name and size only."""
    ok = {p.slug: p for p in packs if p.status == 'ready' and CAT in p.cats()}
    claimed = {(j[0], j[1]) for j in G.plan_jobs(rows, packs)}
    jobs, skipped, fam, late = [], [], {}, set()
    for r in sorted(rows, key=lambda r: (FIT_RANK.get(ok[r.slug].fit, 3) if r.slug in ok else 9, r.slug, natural(r.path))):
        if r.slug not in ok or not r.path.lower().endswith('.png'):
            continue
        ident = (r.slug, r.path)
        w, h = int(r.w), int(r.h)
        stem = P.slugify(os.path.splitext(r.path.split('/')[-1])[0])
        if ident in claimed:
            skipped.append(ident + ('floor (grounds)',))
        elif ident in SHEETS:
            spec = SHEETS[ident]
            if spec is None:
                skipped.append(ident + ('sheet of buildings or terrain',))
            else:
                jobs.append((r.slug, r.path, spec[0], spec[1]))
        elif STRIP.search(r.path):
            skipped.append(ident + ('animated strip',))
        elif SKIP_FILE.search(r.path):
            skipped.append(ident + ('shadow or light overlay',))
        elif max(w, h) > SINGLE_MAX_PX:
            skipped.append(ident + ('over %d px: building or sheet' % SINGLE_MAX_PX,))
        elif (BLDG.search(stem) and max(w, h) >= 2 * P.TILE) or (ok[r.slug].category == 'bldg' and max(w, h) >= 3 * P.TILE):
            skipped.append(ident + ('building',))
        else:
            f = (r.slug, r.path.rsplit('/', 1)[0] if '/' in r.path else '', re.sub(r'_?\d+$', '', stem))
            fam[f] = fam.get(f, 0) + 1
            if fam[f] > FAMILY_CAP and re.search(r'\d$', stem):
                late.add(ident)         # variant 9 and up: decor-3
            jobs.append((r.slug, r.path, 'single', None))
    return jobs, skipped, late


def trim_tiles(a):
    """drop whole empty 32 px rows and columns at the edges; None when there is no art"""
    box = P.alpha_bbox(a)
    if box is None:
        return None
    T = P.TILE
    x0, y0, x1, y1 = box[0] // T * T, box[1] // T * T, -(-box[2] // T) * T, -(-box[3] // T) * T
    return np.ascontiguousarray(a[y0:y1, x0:x1])


def fit_canvas(a, tiles):
    """art bottom-right aligned in a W x H tile canvas (override `tiles`); art that would be cropped stops the build"""
    tw, th = tiles
    h, w = a.shape[:2]
    if w > tw * P.TILE or h > th * P.TILE:
        raise P.PackError('art %dx%d px does not fit %dx%d tiles (tiles override)' % (w, h, tw, th))
    out = np.zeros((th * P.TILE, tw * P.TILE, 4), np.uint8)
    out[out.shape[0] - h:, out.shape[1] - w:] = a
    return out


def cut_job(job, rows_by, src, private, ov):
    """-> ([Obj], [empty cell texts], [oversize texts], unreadable file text or None) for one file (md5 checked before decoding)"""
    slug, path, mode, cap = job
    row = rows_by[(slug, path)]
    try:
        a = P.clean_alpha(P.load_verified(P.source_path(src, slug, path, private), row.md5))
    except OSError:          # a damaged member of a partly recovered archive: left out and listed
        return [], [], [], '%s/%s' % (slug, path)
    H, W = a.shape[:2]
    if (W, H) != (int(row.w), int(row.h)):
        raise P.PackError('%s/%s: %dx%d, the list has %sx%s' % (slug, path, W, H, row.w, row.h))
    T = P.TILE
    empty, big, out = [], [], []
    if mode == 'single':
        key = P.key_of(slug, stem_of(slug, path))
        sc = P.ov_get(ov, key, 'scale2x')
        scaled = auto_scale2x(W, H) if sc is None else bool(sc)
        if scaled:
            a = P.scale2x(a)
        a = P.pad_to_tile(a)
        t = trim_tiles(a)
        if t is None:
            return [], ['%s/%s' % (slug, path)], [], None
        out.append(Obj(slug, path, t, None, scaled))
    else:
        if W % T or H % T:
            raise P.PackError('%s/%s: sheet %dx%d is not a whole number of 32 px cells' % (slug, path, W, H))
        if mode == 'grid':
            boxes = [(x, y, x + T, y + T) for y in range(0, H, T) for x in range(0, W, T)]
        else:
            boxes, _ = P.segment_sheet(a, T, MIN_AREA)
        taken = 0
        for b in boxes:
            c = np.ascontiguousarray(a[b[1]:b[3], b[0]:b[2]])
            if P.alpha_bbox(c) is None:
                empty.append('%s/%s %s' % (slug, path, cell_suffix(b)))
                continue
            if max(c.shape[0], c.shape[1]) > SPLIT_MAX * T:
                big.append('%s/%s %s' % (slug, path, cell_suffix(b)))
                continue
            if cap is not None and taken >= cap:
                continue
            taken += 1
            out.append(Obj(slug, path, c, b, False))
    return out, empty, big, None


# ---------------------------------------------------------------------------------------------- classify
def kind_of(obj):
    if obj.pack in PACK_KIND:
        return PACK_KIND[obj.pack]
    stem = stem_of(obj.pack, obj.path)
    if MOUNT.search(stem):
        return 'wall'
    if BLOCK.search(stem):
        return 'stump'
    return 'decor'


def flags_of(kind, key, ov, blocking_piece=True):
    custom = P.ov_get(ov, key, 'flags')
    if custom:
        return custom
    if kind == 'stump' and not blocking_piece:
        kind = 'decor'
    toks = KIND_FLAGS[kind]
    lt = P.ov_get(ov, key, 'light')
    return toks + (' light:%d:%d' % lt if lt else '')


def collect(src, rows, packs, private=None, ov=None):
    """Cut and classify every object. -> (objs in plan order, report dict). Names, keys and kinds are set here."""
    ov = {} if ov is None else ov
    rows_by = {(r.slug, r.path): r for r in rows}
    pack_by = P.pack_by_slug(packs)
    jobs, skipped, late = plan_jobs(rows, packs)
    order = [j for j in jobs if (j[0], j[1]) not in late] + [j for j in jobs if (j[0], j[1]) in late]   # duplicates keep decor-1/2
    seq = {j: i for i, j in enumerate(jobs)}
    objs, seen, dups, empty, big, ovskip, capped = [], {}, [], [], [], [], []
    keys = set()
    for job in order:
        slug, path, mode, cap = job
        cut, e, b, bad = cut_job(job, rows_by, src, private, ov)
        empty += e
        big += b
        if bad:
            skipped.append((slug, path, 'unreadable PNG'))
        for o in cut:
            stem = stem_of(slug, path)
            o.late, o.seq = (slug, path) in late, seq[job]
            o.key = P.key_of(slug, stem, cell_suffix(o.box))
            if o.key in keys:       # two files with one stem: add the folder
                parent = P.slugify(path.rsplit('/', 1)[0]) if '/' in path else 'x'
                o.key = P.key_of(slug, parent + '_' + stem, cell_suffix(o.box))
            if o.key in keys:
                raise P.PackError('%s: two objects with one key (rename one with an override)' % o.key)
            if P.ov_get(ov, o.key, 'skip') == 1:
                ovskip.append(o.key)
                continue
            tiles = P.ov_get(ov, o.key, 'tiles')
            if tiles:
                o.canvas = fit_canvas(o.canvas, tiles)
                o.th, o.tw = tiles[1], tiles[0]
            d = P.digest(o.canvas)
            if d in seen:
                dups.append((o.key, seen[d]))
                continue
            seen[d] = o.key
            keys.add(o.key)
            pk = pack_by[slug]
            o.label, o.fit = pk.label, pk.fit
            o.kind = P.ov_get(ov, o.key, 'kind') or kind_of(o)
            if o.kind not in KINDS:
                raise P.PackError('%s: kind override %r not one of %s' % (o.key, o.kind, ', '.join(KINDS)))
            bl = P.ov_get(ov, o.key, 'blocking')
            if bl is not None and not P.ov_get(ov, o.key, 'kind'):
                o.kind = 'stump' if bl else ('decor' if o.kind == 'stump' else o.kind)
            o.name = P.ov_get(ov, o.key, 'rename') or '%s (%s)' % (
                P.humanize(stem) + (' ' + cell_suffix(o.box).upper() if o.box else ''), P.humanize(slug))
            small = o.tw <= 2 and o.th <= 2
            h = P.ov_get(ov, o.key, 'hideout')
            o.hide = int(h) if h is not None else int(small and o.kind in ('decor', 'stump') and o.fit != 'low')
            objs.append(o)
    objs.sort(key=lambda o: (o.late, o.seq, (o.box[1], o.box[0]) if o.box else (0, 0)))
    objs, capped = apply_caps(objs)
    objs.sort(key=lambda o: (o.late, o.seq, (o.box[1], o.box[0]) if o.box else (0, 0)))
    return objs, {'skipped': skipped, 'dups': dups, 'empty': empty, 'big': big, 'ovskip': ovskip, 'capped': capped}


def is_small(o):
    return o.tw * o.th <= 2


def opaque(o):
    return int((o.canvas[..., 3] > 0).sum())


def apply_caps(objs):
    """PACK_CAPS: a pack keeps at most (small, big) objects, the ones with the most opaque pixels (a pixel count, no look at
    the art); the others move to decor-3 (`late`). -> (objs, keys moved)"""
    drop = set()
    for slug, caps in PACK_CAPS.items():
        for cls, cap in zip((True, False), caps):
            mine = [(i, o) for i, o in enumerate(objs) if o.pack == slug and is_small(o) == cls and not o.late]
            if cap is not None and len(mine) > cap:
                best = sorted(mine, key=lambda t: (-opaque(t[1]), t[0]))[:cap]
                drop |= {i for i, _ in mine} - {i for i, _ in best}
    for i in drop:
        objs[i].late = True
    return objs, [objs[i].key for i in sorted(drop)]


def make_items(objs, ov):
    """Split into rows: -> (items of block 1, 2, 3). Raises on a block overflow."""
    one, two, three = [], [], []
    for o in objs:
        base = 'family=%s|hideout=%d' % (o.pack, o.hide)
        if o.scaled:
            base += '|scale2x=1'
        if o.tw <= P.MAX_TILES and o.th <= P.MAX_TILES:
            it = Item(o, o.key, o.name, o.kind, o.canvas, flags_of(o.kind, o.key, ov), base)
            (three if o.late else one if is_small(o) else two).append(it)
            continue
        pieces = P.plan_split(o.tw, o.th)
        se = (pieces[-1].row, pieces[-1].col)
        for pc in pieces:
            blocking = (pc.row, pc.col) == se
            k = o.kind if blocking or o.kind != 'stump' else 'decor'
            (three if o.late else two).append(Item(o, P.piece_key(o.key, pc), '%s R%dC%d' % (o.name, pc.row, pc.col), k, P.cut_piece(o.canvas, pc),
                            flags_of(o.kind, o.key, ov, blocking), base + '|' + P.group_extra(o.key, o.tw, o.th, pc), pc))
    if len(one) > BLOCK_1:
        raise P.PackError('block overflow: decor-1 needs %d ids, the block holds %d (client %d..%d): move the overflow to the '
                          'overflow range (PLAN_PAIR30 section 2) or skip objects with overrides' % (
                              len(one), BLOCK_1, FIRST_1, FIRST_1 + BLOCK_1 - 1))
    if len(two) > BLOCK_2:
        raise P.PackError('block overflow: decor-2 needs %d ids, the block holds %d (client %d..%d): move the overflow to the '
                          'overflow range (PLAN_PAIR30 section 2) or skip objects with overrides' % (
                              len(two), BLOCK_2, FIRST_2, FIRST_2 + BLOCK_2 - 1))
    if len(three) > BLOCK_3:
        raise P.PackError('block overflow: decor-3 needs %d ids, the block holds %d (client %d..%d): raise BLOCK_3 or skip objects '
                          'with overrides' % (len(three), BLOCK_3, FIRST_3, LAST_3))
    return one, two, three


# ---------------------------------------------------------------------------------------------- tables
def layout(sizes, block):
    """[(atlas rel name, y px)] for a list of (w, h) tiles: objects stacked down an atlas of ATLAS_H px"""
    out, n, y = [], 1, 0
    for w, h in sizes:
        if y and y + h * P.TILE > ATLAS_H:
            n, y = n + 1, 0
        out.append((ATLAS_REL % (block, n), y))
        y += h * P.TILE
    return out


def spec_rows(items, block):
    rows = []
    for it, (atlas, y) in zip(items, layout([(i.w, i.h) for i in items], block)):
        rows.append([it.key, 'item', it.kind, it.name, atlas, 0, y, it.w, it.h, 1, 1, it.flags, 'new', '', it.extra])
    return rows


def source_of(it):
    o = it.obj
    s = '%s/%s' % (o.pack, o.path)
    if o.box:
        s += '[%d,%d,%d,%d]' % o.box
    if it.piece is not None:
        s += ' piece r%dc%d' % (it.piece.row, it.piece.col)
    return s


def atlases(items, block):
    out = {}
    rows = spec_rows(items, block)
    by = {}
    for it, r in zip(items, rows):
        by.setdefault(r[4], []).append((it, r[6]))
    for atlas, lst in by.items():
        a = np.zeros((max(y + it.h * P.TILE for it, y in lst), max(it.w * P.TILE for it, _ in lst), 4), np.uint8)
        for it, y in lst:
            a[y:y + it.canvas.shape[0], :it.canvas.shape[1]] = it.canvas
        out[atlas + '.png'] = a
    return out


def tables(one, two, three):
    src = [[it.key, 'item', it.obj.label, source_of(it), LICENCE[it.obj.label]] for it in one + two + three]
    return {SPEC_1: P.csv_text(FIELDS, spec_rows(one, 1)), SPEC_2: P.csv_text(FIELDS, spec_rows(two, 2)),
            SPEC_3: P.csv_text(FIELDS, spec_rows(three, 3)),
            SOURCES_CSV: P.csv_text(SOURCE_FIELDS, src)}


# ---------------------------------------------------------------------------------------------- checks without art
def parse_csv(text):
    return list(csv.reader(io.StringIO(text)))


def extra_of(text):
    return dict(p.split('=', 1) for p in text.split('|') if '=' in p)


SRC_RE = re.compile(r'([a-z0-9_]+)/(.+?)(?:\[(\d+),(\d+),(\d+),(\d+)\])?(?: piece r(\d+)c(\d+))?')


def check_tables(spec1, spec2, spec3, sources_text, sums_text, packs, files, ov=None, atlas_dir=None):
    """Problems in the committed tables, from the tables alone (CI without the packs). -> [text]"""
    bad = []
    ov = {} if ov is None else ov
    blocks = []
    for n, (text, first, cap) in enumerate(((spec1, FIRST_1, BLOCK_1), (spec2, FIRST_2, BLOCK_2), (spec3, FIRST_3, BLOCK_3)), 1):
        rows = parse_csv(text)
        if not rows or rows[0] != FIELDS:
            return ['spec %d: header must be %s' % (n, ','.join(FIELDS))]
        rows = rows[1:]
        if len(rows) > cap:
            bad.append('spec %d: %d rows, the block holds %d (block overflow)' % (n, len(rows), cap))
        blocks.append(rows)
    pack_by = P.pack_by_slug(packs)
    dims = {(f.slug, f.path): (int(f.w), int(f.h)) for f in files if f.w}
    keys, groups = set(), {}
    for n, rows in enumerate(blocks, 1):
        want = layout([(int(r[7]), int(r[8])) for r in rows], n)
        for i, r in enumerate(rows):
            key, kind, flags, ex = r[0], r[2], r[11], extra_of(r[14])
            w, h = int(r[7]), int(r[8])
            where = 'spec%d %s' % (n, key)
            if key in keys:
                bad.append(where + ': duplicate key')
            keys.add(key)
            if not re.fullmatch(r'[a-z0-9_]+__[a-z0-9_]+', key):
                bad.append(where + ': key is not <pack slug>__<stem>')
            if r[1] != 'item' or kind not in KINDS or r[12] != 'new' or r[13] != '' or r[9:11] != ['1', '1'] or \
                    not (1 <= w <= P.MAX_TILES and 1 <= h <= P.MAX_TILES):
                bad.append(where + ': cat / kind / size / patterns / phases / mode')
            if (r[4], r[5], r[6]) != (want[i][0], '0', str(want[i][1])):
                bad.append(where + ': atlas place differs from the layout')
            toks = flags.split()
            names = [t.split(':')[0] for t in toks]
            if any(t not in FLAG_WORDS for t in names) or len(set(names)) != len(names) or 'notmoveable' not in names:
                bad.append(where + ': flags %r' % flags)
            fam = ex.get('family')
            if fam not in pack_by or CAT not in pack_by[fam].cats() or not key.startswith(fam + '__'):
                bad.append(where + ': family %r' % fam)
            if ex.get('hideout') not in ('0', '1'):
                bad.append(where + ': hideout 0 or 1')
            if 'group' in ex:
                g = groups.setdefault(ex['group'], [])
                g.append((key, int(ex['gw']), int(ex['gh']), tuple(int(x) for x in ex['piece'].split(',')), w, h, n))
                if n == 1:
                    bad.append(where + ': a piece belongs in decor-2 or decor-3')
            elif n != 3 and (w * h <= 2) != (n == 1):
                bad.append(where + ': %dx%d item in the wrong block' % (w, h))
    for gk, ps in groups.items():
        gw, gh = ps[0][1], ps[0][2]
        plan = P.plan_split(gw, gh)
        got = sorted((p[3], p[4], p[5]) for p in ps)
        exp = sorted(((pc.row, pc.col), pc.tw, pc.th) for pc in plan)
        if any((p[1], p[2]) != (gw, gh) for p in ps) or got != exp or gw <= P.MAX_TILES and gh <= P.MAX_TILES or \
                any(p[0] != '%s_r%dc%d' % (gk, p[3][0], p[3][1]) for p in ps) or len({p[6] for p in ps}) != 1:
            bad.append('group %s: pieces differ from plan_split(%d, %d)' % (gk, gw, gh))
    src = parse_csv(sources_text)
    if not src or src[0] != SOURCE_FIELDS:
        bad.append('sources: header must be %s' % ','.join(SOURCE_FIELDS))
        src = [[]]
    src = src[1:]
    allrows = blocks[0] + blocks[1] + blocks[2]
    if [s[0] for s in src] != [r[0] for r in allrows]:
        bad.append('sources: names differ from the spec keys (decor-1, decor-2, decor-3 rows)')
    for s, r in zip(src, allrows):
        if len(s) != len(SOURCE_FIELDS):
            bad.append('sources: bad row %r' % s)
            continue
        m = SRC_RE.fullmatch(s[3])
        if not m or (m.group(1), m.group(2)) not in dims:
            bad.append('sources %s: %s is not in pack30_decor.files' % (s[0], s[3]))
            continue
        p = pack_by.get(m.group(1))
        if p is None or s[2] != p.label or s[4] != LICENCE.get(p.label):
            bad.append('sources %s: label or licence' % s[0])
        W, H = dims[(m.group(1), m.group(2))]
        ex = extra_of(r[14])
        if m.group(3) is not None:
            x0, y0, x1, y1 = (int(m.group(i)) for i in (3, 4, 5, 6))
            if not (0 <= x0 < x1 <= W and 0 <= y0 < y1 <= H) or (m.group(1), m.group(2)) not in SHEETS:
                bad.append('sources %s: cell box outside the file or the file is not a listed sheet' % s[0])
        elif s[0] not in ov and (m.group(1), m.group(2)) not in SHEETS:
            sc = 'scale2x' in ex
            bw, bh = (W * 2, H * 2) if sc else (W, H)
            lim = (P.tiles_of_px(bw), P.tiles_of_px(bh))
            gw, gh = (int(ex['gw']), int(ex['gh'])) if 'group' in ex else (int(r[7]), int(r[8]))
            if gw > lim[0] or gh > lim[1] or (sc and (W > 16 or H > 16)):
                bad.append('sources %s: size %dx%d tiles is more than the %dx%d file holds' % (s[0], gw, gh, W, H))
        if ('piece' in ex) != (m.group(7) is not None) or \
                (m.group(7) is not None and '%s,%s' % (m.group(7), m.group(8)) != ex['piece']):
            bad.append('sources %s: piece' % s[0])
    sum_of = {}
    for line in sums_text.splitlines():
        d, _, p = line.partition('  ')
        sum_of[p] = d
    shapes = {}
    for rows in blocks:
        for r in rows:
            sh = shapes.setdefault(r[4] + '.png', [0, 0])
            sh[0] = max(sh[0], int(r[6]) + int(r[8]) * P.TILE)
            sh[1] = max(sh[1], int(r[7]) * P.TILE)
    if sorted(sum_of) != sorted(shapes):
        bad.append('sums: must list exactly %s' % ', '.join(sorted(shapes)))
    if atlas_dir:
        for rel, (hh, ww) in sorted(shapes.items()):
            p = os.path.join(atlas_dir, rel)
            if not os.path.exists(p):
                continue
            a = np.asarray(Image.open(p).convert('RGBA'))
            if a.shape != (hh, ww, 4):
                bad.append('%s: shape %s differs from the spec' % (rel, a.shape))
            elif P.digest(a) != sum_of.get(rel):
                bad.append('%s: differs from pack30_decor.sums' % rel)
    return bad


def read(path):
    return open(path, newline='', encoding='utf-8').read() if os.path.exists(path) else None


def check_without_art():
    paths = (SPEC_1, SPEC_2, SPEC_3, SOURCES_CSV, SUMS)
    texts = [read(p) for p in paths]
    if None in texts:
        print('missing', [p for p, t in zip(paths, texts) if t is None])
        return False
    bad = check_tables(*texts, P.load_packs(), P.read_files(P.files_path(CAT)), P.load_overrides(), atlas_dir=ART)
    n1, n2, n3 = (len(parse_csv(t)) - 1 for t in texts[:3])
    print('\n'.join(bad))
    print('pack30 decor check (no sources): %d + %d + %d items, ids %d..%d, %d..%d and %d..%d:' % (
        n1, n2, n3, FIRST_1, FIRST_1 + n1 - 1, FIRST_2, FIRST_2 + n2 - 1, FIRST_3, FIRST_3 + n3 - 1), 'OK' if not bad else 'FAILED')
    return not bad


# ---------------------------------------------------------------------------------------------- build
def build(src, check, verbose=False):
    if not src:
        if not check:
            sys.exit('build needs --src (the drivepacks folder); without it only --check runs')
        return check_without_art()
    packs = P.load_packs()
    rows = P.read_files(P.files_path(CAT))
    ov = P.load_overrides()
    objs, rep = collect(src, rows, packs, P.load_private(), ov)
    one, two, three = make_items(objs, ov)
    files = dict(tables(one, two, three))
    sheets = dict(atlases(one, 1))
    sheets.update(atlases(two, 2))
    sheets.update(atlases(three, 3))
    files[SUMS] = P.sums_text(sorted(sheets.items()))
    kinds = {k: sum(1 for it in one + two + three if it.kind == k) for k in KINDS}
    groups = len({o.key for o in objs if o.tw > P.MAX_TILES or o.th > P.MAX_TILES})
    print('decor: %d objects -> %d + %d + %d items (stump %d, decor %d, wall %d, prop %d; %d groups cut into pieces), ids %d..%d of '
          '%d..%d, %d..%d of %d..%d and %d..%d of %d..%d; %d duplicates skipped, %d empty cells dropped, %d over %d tiles, '
          '%d moved to decor-3 by a pack cap, '
          '%d files left to other tasks, %d skipped by override' % (
              len(objs), len(one), len(two), len(three), kinds['stump'], kinds['decor'], kinds['wall'], kinds['prop'], groups,
              FIRST_1, FIRST_1 + len(one) - 1, FIRST_1, FIRST_1 + BLOCK_1 - 1, FIRST_2, FIRST_2 + len(two) - 1, FIRST_2, FIRST_2 + BLOCK_2 - 1,
              FIRST_3, FIRST_3 + len(three) - 1, FIRST_3, LAST_3,
              len(rep['dups']), len(rep['empty']), len(rep['big']), SPLIT_MAX, len(rep['capped']), len(rep['skipped']),
              len(rep['ovskip'])))
    if verbose:
        for s in rep['skipped']:
            print('  left out: %s/%s (%s)' % s)
        for s in rep['big']:
            print('  too big: ' + s)
        for k, d in rep['dups']:
            print('  duplicate: %s = %s' % (k, d))
    bad = check_tables(files[SPEC_1], files[SPEC_2], files[SPEC_3], files[SOURCES_CSV], files[SUMS], packs, rows, ov)
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
        print('pack30 decor check:', 'OK' if ok else 'FAILED')
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
    """owner only: every atlas at 3x on a dark ground; outside git, not opened by agents"""
    os.makedirs(a.out, exist_ok=True)
    for b in (1, 2, 3):
        for n in range(1, 50):
            p = os.path.join(ART, (ATLAS_REL % (b, n)) + '.png')
            if not os.path.exists(p):
                break
            im = Image.open(p).convert('RGBA')
            w, h = im.size
            bg = Image.new('RGBA', (w, h), (60, 60, 60, 255))
            bg.alpha_composite(im)
            bg.resize((w * 3, h * 3), Image.NEAREST).save(os.path.join(a.out, 'decor%d_%d.png' % (b, n)))
    print('previews in', a.out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    b.add_argument('--verbose', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'preview':
            cmd_preview(a)
            return 0
        return 0 if build(a.src, a.check, a.verbose) else 1
    except P.PackError as e:
        print('ERROR:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())
