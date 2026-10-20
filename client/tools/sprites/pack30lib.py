#!/usr/bin/env python3
"""Shared helpers of the pair 30 pack importers (gen_pack30_<cat>.py). Nothing here draws or measures style: it
reads tables, verifies source files by md5 and does plain geometry (alpha boxes, connected components, cuts, mirrors,
placement). No generator edits this file; a generator that needs more asks the integrator.

    python3 -I pack30lib.py check                       # audit CSV, overrides and *.files agree with each other (CI)
    python3 -I pack30lib.py check --src DRIVEPACKS      # also every listed file exists with its size and md5

Hard rules (PLAN_PAIR30 section 0): the packs ban machine-learning use and sharing. Nobody views, style-measures,
samples a palette from or gives a pack image to an AI tool. Allowed on pack files: names, sizes, PIL `.size`, md5,
alpha boxes and connected components computed inside a script. Names: no vendor, pack title or other game's name in a
committed file; the audit uses neutral slugs and the internal labels below, the real folder names live in the ignored
art_import/pack30_packs.private.csv.

API (all functions pure unless a path is given; arrays are numpy uint8 HxWx4 RGBA)
-------------------------------------------------------------------------------------------------------------
Constants      TILE=32, MAX_TILES=4, ALPHA_MIN=12, LABELS, CATEGORIES, STATUSES, MASK_MARKERS,
               PACKS_CSV, PRIVATE_CSV, OVERRIDES_CSV, ART; files_path(cat) -> art_import/pack30_<cat>.files
Errors         PackError (a clear stop: unknown slug, missing file, md5 mismatch, art that does not fit)
Pack table     load_packs(path=PACKS_CSV) -> [Pack]            Pack fields: slug label vendor_class status category also
                                                                licence_class fit dup_of readme_md5 file_count png_count
                                                                note; Pack.cats() -> [category] + also
               packs_for(packs, cat, status='ready') -> [Pack] (category or also)
               pack_by_slug(packs) -> {slug: Pack}
               check_packs(packs) -> [problem text]
               load_private(path=PRIVATE_CSV) -> {slug: {'folder','root'}}   ({} when the file is absent, e.g. in CI)
               pack_root(src, slug, private=None) -> abs path of a pack's content root under DRIVEPACKS
               source_path(src, slug, rel, private=None) -> abs path of one listed file (refuses '..')
File lists     FileRow(slug, path, size, md5, w, h)  (w and h empty for non-images)
               read_files(path) -> [FileRow];  files_text(rows) -> str (sorted, deterministic)
               scan_pack(slug, root, looks=False) -> [FileRow]  (png and json, no previews / godot / archives)
               verify_files(src, rows, private=None, md5=True) -> [problem text]
               file_md5(path) -> hex;  load_verified(path, md5) -> RGBA array (md5 checked before decoding)
               png_size(path) -> (w, h) from the PNG header only
Pixels         clean_alpha(a, amin=ALPHA_MIN)   pixels under amin become 0,0,0,0
               strip_frames(a, cw, ch=None) -> [frame]          a horizontal strip, whole frames only
               mirror(a)                                          left-right flip
               alpha_bbox(a, thr=1) -> (x0,y0,x1,y1) | None       x1, y1 exclusive
               union_bbox(frames, thr=1) -> box | None            union over frames (and directions)
               fit_tiles(bw, bh, margin=1, lo=1, hi=3) -> S       smallest square edge in tiles holding the box
               place_bottom_right(a, box, tw, th, margin=1, dx=0, dy=0) -> canvas th*32 x tw*32 with the box's right
                               and bottom edges `margin` px from the canvas edges (same shift for every frame)
               pad_to_tile(a, tile=TILE) -> a padded top/left to a multiple of the tile (bottom-right aligned)
               scale2x(a) -> a at 2x (Scale2x / EPX, for 16 px sources)
               snap_mask(m, tol=40, amin=128) -> mask with only the four marker colours (alpha 255) or cleared
               mean_rgb(a, amin=1) -> (r, g, b) alpha-weighted mean of the opaque pixels
Geometry       components(mask) -> [(x0,y0,x1,y1,area)]  8-connected components of a bool mask, reading order
               segment_sheet(a, grid=32, min_area=8) -> (boxes, dropped)   component boxes grown to the grid
               grid_detect(a, cells=(32, 16)) -> dict | None   {'cell','gap','nx','ny','pitch','how'}; gap grids are
                               `33*n - 1` px wide (131 = 4 cells, 197 = 6 cells, 1 px gaps); None -> use segment_sheet
               Piece(row, col, tx, ty, tw, th);  plan_split(gw, gh, max_tiles=MAX_TILES) -> [Piece] (row-major; cut
                               from the south-east corner, the remainder goes to the north-west piece)
               cut_piece(a, piece) -> sub-array;  piece_key(key, piece) -> '<key>_r<row>c<col>'
               group_extra(key, gw, gh, piece) -> 'group=<key>|gw=<gw>|gh=<gh>|piece=<row>,<col>' (gw, gh in tiles)
               tiles_of_px(px) -> ceil(px / 32)
Palettes       rgb_to_outfit_index(rgb) -> 0..132 (the standard HSI outfit table);  outfit_rgb(i) -> rgb
               rgb_to_minimap_index(rgb) -> 1..215 (the 6x6x6 minimap cube; 0 is transparent);  minimap_rgb(i) -> rgb
Tables         digest(a) -> sha256 hex of pixels + shape;  csv_text(header, rows);  sums_text(items) with items
               [(path, array)] -> '<digest>  <path>' lines
               slugify(text), humanize(slug) -> 'Sootfang Wolf', key_of(pack, stem, cell=None) -> '<pack>__<stem>[__<cell>]'
               fps_to_ms(fps=None, default=110)
Overrides      load_overrides(path=OVERRIDES_CSV) -> {key: {action: value}} (values parsed: ints, 'e'|'w', (w, h) tiles,
               'rename'/'kind'/'flags' text, 'light' as (level, colour));  ov_get(ov, key, action, default=None)
-------------------------------------------------------------------------------------------------------------
"""
import csv
import hashlib
import io
import math
import os
import re
import sys
from collections import namedtuple

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
PACKS_CSV = os.path.join(ART, 'pack30_packs.csv')
PRIVATE_CSV = os.path.join(ART, 'pack30_packs.private.csv')
OVERRIDES_CSV = os.path.join(ART, 'pack30_overrides.csv')

TILE = 32
MAX_TILES = 4          # no item or outfit larger than 4x4 tiles (PLAN_PAIR30 section 2; T9 may lower it to 3)
ALPHA_MIN = 12
LABELS = ('set30 mutter', 'set30 pocket', 'set30 monsters', 'set30 potions')
CATEGORIES = ('looks', 'strips', 'grounds', 'decor', 'bldg', 'anim', 'fx', 'items')
STATUSES = ('ready', 'pending', 'excluded', 'dup')
PACK_FIELDS = ['slug', 'label', 'vendor_class', 'status', 'category', 'also', 'licence_class', 'fit', 'dup_of',
               'readme_md5', 'file_count', 'png_count', 'note']
PRIVATE_FIELDS = ['slug', 'folder', 'root', 'note']
FILES_FIELDS = ['slug', 'path', 'size', 'md5', 'w', 'h']
OVERRIDE_FIELDS = ['key', 'action', 'value']
OVERRIDE_ACTIONS = ('skip', 'rename', 'kind', 'flags', 'blocking', 'flip', 'ns', 'dx', 'dy', 'tiles', 'scale2x',
                    'light', 'hideout')
# colour mask markers of a sheet look: head, body, legs, feet
MASK_MARKERS = ((255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255))
SKIP_DIRS = ('preview', 'previews', 'godot', '__macosx')
KEEP_EXT = ('.png', '.json')

Pack = namedtuple('Pack', PACK_FIELDS)
FileRow = namedtuple('FileRow', FILES_FIELDS)
Piece = namedtuple('Piece', 'row col tx ty tw th')


class PackError(Exception):
    pass


def _cats(self):
    return [self.category] + [c for c in self.also.split('+') if c]


Pack.cats = _cats


def files_path(cat):
    return os.path.join(ART, 'pack30_%s.files' % cat)


# ------------------------------------------------------------------------------------------------ tables
def csv_text(header, rows):
    s = io.StringIO()
    w = csv.writer(s, lineterminator='\n')
    w.writerow(header)
    w.writerows(rows)
    return s.getvalue()


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def sums_text(items):
    return ''.join('%s  %s\n' % (digest(a), p) for p, a in items)


def slugify(text):
    return re.sub(r'[^a-z0-9]+', '_', text.lower()).strip('_')


def humanize(slug):
    return ' '.join(w.capitalize() for w in slug.split('_') if w)


def key_of(pack, stem, cell=None):
    k = '%s__%s' % (slugify(pack), slugify(stem))
    return k if cell is None else '%s__%s' % (k, slugify(str(cell)))


def fps_to_ms(fps=None, default=110):
    return default if not fps else max(1, int(round(1000.0 / float(fps))))


def _read_csv(path):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


# ------------------------------------------------------------------------------------------------ pack table
def load_packs(path=PACKS_CSV):
    rows = _read_csv(path)
    out = []
    for r in rows:
        if list(r) != PACK_FIELDS:
            raise PackError('%s: header must be %s' % (path, ','.join(PACK_FIELDS)))
        out.append(Pack(**r))
    return out


def pack_by_slug(packs):
    return {p.slug: p for p in packs}


def packs_for(packs, cat, status='ready'):
    return [p for p in packs if p.status == status and cat in p.cats()]


def check_packs(packs):
    bad = []
    seen = set()
    by = pack_by_slug(packs)
    for p in packs:
        if not re.fullmatch(r'[a-z0-9_]+', p.slug):
            bad.append('%s: slug must be a-z, 0-9, _' % p.slug)
        if p.slug in seen:
            bad.append('%s: duplicate slug' % p.slug)
        seen.add(p.slug)
        if p.status not in STATUSES:
            bad.append('%s: status %r' % (p.slug, p.status))
        if p.status in ('ready', 'dup') and p.label not in LABELS:
            bad.append('%s: label %r not one of %s' % (p.slug, p.label, ', '.join(LABELS)))
        for c in p.cats():
            if c not in CATEGORIES:
                bad.append('%s: category %r' % (p.slug, c))
        if p.status == 'dup' and (p.dup_of not in by or by[p.dup_of].status != 'ready'):
            bad.append('%s: dup_of %r is not a ready pack' % (p.slug, p.dup_of))
        if p.status != 'dup' and p.dup_of:
            bad.append('%s: dup_of set on a %s pack' % (p.slug, p.status))
        if p.status == 'ready' and not p.file_count.isdigit():
            bad.append('%s: file_count' % p.slug)
    return bad


def load_private(path=PRIVATE_CSV):
    if not os.path.isfile(path):
        return {}
    return {r['slug']: r for r in _read_csv(path)}


def pack_root(src, slug, private=None):
    priv = load_private() if private is None else private
    if slug in priv:
        root = os.path.join(src, priv[slug]['folder'], priv[slug].get('root') or '')
    else:
        root = os.path.join(src, slug)
    root = os.path.normpath(root)
    if not os.path.isdir(root):
        raise PackError('pack %s: folder %s not found (private map %s)' % (slug, root, PRIVATE_CSV))
    return root


def source_path(src, slug, rel, private=None):
    parts = rel.split('/')
    if rel.startswith('/') or '..' in parts or '\\' in rel:
        raise PackError('%s/%s: unsafe path' % (slug, rel))
    return os.path.join(pack_root(src, slug, private), *parts)


# ------------------------------------------------------------------------------------------------ file lists
def file_md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def png_size(path):
    with Image.open(path) as im:
        return im.size


def read_files(path):
    rows = []
    for r in _read_csv(path):
        if list(r) != FILES_FIELDS:
            raise PackError('%s: header must be %s' % (path, ','.join(FILES_FIELDS)))
        rows.append(FileRow(**r))
    return rows


def files_text(rows):
    return csv_text(FILES_FIELDS, [tuple(r) for r in sorted(rows, key=lambda r: (r.slug, r.path))])


def scan_pack(slug, root, looks=False):
    """The importable files of one pack (png and json; no previews, godot folders, gifs, archives or licence text).
    looks=True keeps only `<creature>/sheets/*.png` and `<creature>/animations.json` of a sheet-look pack."""
    out = []
    for dp, dn, fn in os.walk(root):
        dn[:] = sorted(d for d in dn if d.lower() not in SKIP_DIRS)
        for f in sorted(fn):
            if not f.lower().endswith(KEEP_EXT):
                continue
            full = os.path.join(dp, f)
            rel = os.path.relpath(full, root).replace(os.sep, '/')
            if looks:
                parts = rel.split('/')
                if not ((len(parts) == 3 and parts[1] == 'sheets' and f.lower().endswith('.png')) or
                        (len(parts) == 2 and f == 'animations.json')):
                    continue
            w = h = ''
            if f.lower().endswith('.png'):
                w, h = png_size(full)
            out.append(FileRow(slug, rel, str(os.path.getsize(full)), file_md5(full), str(w), str(h)))
    return sorted(out, key=lambda r: r.path)


def verify_files(src, rows, private=None, md5=True):
    bad = []
    for r in rows:
        try:
            p = source_path(src, r.slug, r.path, private)
        except PackError as e:
            bad.append(str(e))
            continue
        if not os.path.isfile(p):
            bad.append('%s/%s: missing' % (r.slug, r.path))
        elif str(os.path.getsize(p)) != r.size:
            bad.append('%s/%s: size %d, list has %s' % (r.slug, r.path, os.path.getsize(p), r.size))
        elif md5 and file_md5(p) != r.md5:
            bad.append('%s/%s: md5 differs from the list' % (r.slug, r.path))
    return bad


def load_verified(path, md5):
    """Decode a PNG only after its md5 matches the committed list (the files are untrusted)."""
    data = open(path, 'rb').read()
    got = hashlib.md5(data).hexdigest()
    if got != md5:
        raise PackError('%s: md5 %s, the list has %s (another file?)' % (path, got, md5))
    return np.asarray(Image.open(io.BytesIO(data)).convert('RGBA')).copy()


# ------------------------------------------------------------------------------------------------ pixels
def clean_alpha(a, amin=ALPHA_MIN):
    a = a.copy()
    a[a[..., 3] < amin] = 0
    return a


def strip_frames(a, cw, ch=None):
    ch = a.shape[0] if ch is None else ch
    if a.shape[0] != ch or a.shape[1] % cw:
        raise PackError('strip %dx%d is not whole frames of %dx%d' % (a.shape[1], a.shape[0], cw, ch))
    return [a[:, i * cw:(i + 1) * cw] for i in range(a.shape[1] // cw)]


def mirror(a):
    return np.ascontiguousarray(a[:, ::-1])


def alpha_bbox(a, thr=1):
    ys, xs = np.nonzero(a[..., 3] >= thr)
    if not len(xs):
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def union_bbox(frames, thr=1):
    box = None
    for f in frames:
        b = alpha_bbox(f, thr)
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return box


def tiles_of_px(px):
    return (int(px) + TILE - 1) // TILE


def fit_tiles(bw, bh, margin=1, lo=1, hi=3):
    """Smallest square edge in tiles (lo..hi) that holds a bw x bh box plus `margin` px right and below."""
    need = max(bw, bh) + margin
    s = max(lo, tiles_of_px(need))
    if s > min(hi, MAX_TILES):
        raise PackError('art %dx%d needs %d tiles, the limit is %d' % (bw, bh, s, min(hi, MAX_TILES)))
    return s


def place_bottom_right(a, box, tw, th, margin=1, dx=0, dy=0):
    W, H = tw * TILE, th * TILE
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0
    px, py = W - margin - bw + dx, H - margin - bh + dy
    if px < 0 or py < 0 or px + bw > W or py + bh > H:
        raise PackError('box %dx%d (shift %d,%d) does not fit %dx%d px' % (bw, bh, dx, dy, W, H))
    out = np.zeros((H, W, 4), a.dtype)
    out[py:py + bh, px:px + bw] = a[y0:y1, x0:x1]
    return out


def pad_to_tile(a, tile=TILE):
    h, w = a.shape[:2]
    H, W = tiles_of_px(h) * tile, tiles_of_px(w) * tile
    out = np.zeros((H, W, a.shape[2]), a.dtype)
    out[H - h:, W - w:] = a
    return out


def scale2x(a):
    h, w = a.shape[:2]
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode='edge')
    B, D, E, F, H = p[:-2, 1:-1], p[1:-1, :-2], p[1:-1, 1:-1], p[1:-1, 2:], p[2:, 1:-1]
    eq = lambda x, y: (x == y).all(axis=2)
    out = np.zeros((h * 2, w * 2, a.shape[2]), a.dtype)
    c = ~eq(B, H) & ~eq(D, F)
    for (dy, dx), (s1, s2) in {(0, 0): (D, B), (0, 1): (B, F), (1, 0): (D, H), (1, 1): (H, F)}.items():
        pick = c & eq(s1, s2)
        out[dy::2, dx::2] = np.where(pick[:, :, None], s1, E)
    return out


def snap_mask(m, tol=40, amin=128):
    """Colour mask of a sheet look: alpha >= amin becomes 255 and the pixel snaps to the one marker colour within `tol`
    per channel; every other pixel is cleared (so the mask never holds more than four colours)."""
    out = np.zeros_like(m)
    rgb = m[..., :3].astype(np.int16)
    on = m[..., 3] >= amin
    for mk in MASK_MARKERS:
        near = (np.abs(rgb - np.array(mk, np.int16)) <= tol).all(axis=2) & on
        out[near] = (mk[0], mk[1], mk[2], 255)
    return out


def mean_rgb(a, amin=1):
    on = a[..., 3] >= amin
    if not on.any():
        return (0, 0, 0)
    px = a[..., :3][on].astype(np.float64)
    return tuple(int(round(v)) for v in px.mean(axis=0))


# ------------------------------------------------------------------------------------------------ geometry
def components(mask):
    """8-connected components of a bool mask: [(x0, y0, x1, y1, area)] (x1, y1 exclusive), sorted by (y0, x0)."""
    h, w = mask.shape
    runs, rows = [], []          # run = [y, s, e); rows[y] = indices of its runs
    for y in range(h):
        idx = np.flatnonzero(mask[y])
        if not len(idx):
            rows.append([])
            continue
        cut = np.flatnonzero(np.diff(idx) > 1)
        starts = np.concatenate(([idx[0]], idx[cut + 1]))
        ends = np.concatenate((idx[cut] + 1, [idx[-1] + 1]))
        first = len(runs)
        runs.extend((y, int(s), int(e)) for s, e in zip(starts, ends))
        rows.append(list(range(first, len(runs))))
    parent = list(range(len(runs)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for y in range(1, h):
        a, b = rows[y - 1], rows[y]
        i = j = 0
        while i < len(a) and j < len(b):
            _, s1, e1 = runs[a[i]]
            _, s2, e2 = runs[b[j]]
            if s1 <= e2 and s2 <= e1:       # overlap or a corner touch
                ra, rb = find(a[i]), find(b[j])
                if ra != rb:
                    parent[rb] = ra
            if e1 < e2:
                i += 1
            else:
                j += 1
    box = {}
    for i, (y, s, e) in enumerate(runs):
        r = find(i)
        b = box.get(r)
        if b is None:
            box[r] = [s, y, e, y + 1, e - s]
        else:
            b[0], b[1], b[2], b[3], b[4] = min(b[0], s), min(b[1], y), max(b[2], e), max(b[3], y + 1), b[4] + e - s
    return sorted((tuple(v) for v in box.values()), key=lambda c: (c[1], c[0]))


def segment_sheet(a, grid=TILE, min_area=8, thr=1):
    """Cut a sheet without a known grid: the connected components of alpha, each box grown outwards to the grid;
    boxes that overlap after growing are merged (a component that crosses a cell edge stays whole). Components under
    `min_area` px are dropped and returned in `dropped`. -> (boxes, dropped), boxes sorted by (y0, x0)."""
    H, W = a.shape[:2]
    comps = components(a[..., 3] >= thr)
    dropped = [c for c in comps if c[4] < min_area]
    boxes = []
    for x0, y0, x1, y1, area in comps:
        if area < min_area:
            continue
        boxes.append([x0 // grid * grid, y0 // grid * grid, min(W, -(-x1 // grid) * grid), min(H, -(-y1 // grid) * grid)])
    merged = True
    while merged:
        merged = False
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                p, q = boxes[i], boxes[j]
                if p[0] < q[2] and q[0] < p[2] and p[1] < q[3] and q[1] < p[3]:
                    boxes[i] = [min(p[0], q[0]), min(p[1], q[1]), max(p[2], q[2]), max(p[3], q[3])]
                    del boxes[j]
                    merged = True
                    break
            if merged:
                break
    return sorted((tuple(b) for b in boxes), key=lambda b: (b[1], b[0])), dropped


def grid_detect(a, cells=(32, 16)):
    """Decide a sheet's grid by structure only. Gap grids (cells of 32 with 1 px gaps, width 33*n - 1) are recognised
    by the size; otherwise the largest cell in `cells` that divides the size and that no alpha component crosses.
    -> {'cell','gap','nx','ny','pitch','how'} or None (use segment_sheet)."""
    H, W = a.shape[:2]
    if (W + 1) % 33 == 0 and (H + 1) % 33 == 0 and (W % 32 or H % 32):
        return {'cell': 32, 'gap': 1, 'nx': (W + 1) // 33, 'ny': (H + 1) // 33, 'pitch': 33, 'how': 'gap33'}
    comps = None
    for c in cells:
        if W % c or H % c:
            continue
        if comps is None:
            comps = components(a[..., 3] >= 1)
        if all(x0 // c == (x1 - 1) // c and y0 // c == (y1 - 1) // c for x0, y0, x1, y1, _ in comps):
            return {'cell': c, 'gap': 0, 'nx': W // c, 'ny': H // c, 'pitch': c, 'how': 'cells%d' % c}
    return None


def _axis_sizes(n, m):
    k = -(-n // m)
    return [n - m * (k - 1)] + [m] * (k - 1)


def plan_split(gw, gh, max_tiles=MAX_TILES):
    """Pieces of at most max_tiles x max_tiles of a gw x gh tile picture, cut from the south-east corner (every piece
    is full size except the north-west row and column, which take the remainder). Row-major."""
    if gw < 1 or gh < 1:
        raise PackError('group %dx%d' % (gw, gh))
    xs, ys = _axis_sizes(gw, max_tiles), _axis_sizes(gh, max_tiles)
    out, ty = [], 0
    for r, ph in enumerate(ys):
        tx = 0
        for c, pw in enumerate(xs):
            out.append(Piece(r, c, tx, ty, pw, ph))
            tx += pw
        ty += ph
    return out


def cut_piece(a, piece):
    return a[piece.ty * TILE:(piece.ty + piece.th) * TILE, piece.tx * TILE:(piece.tx + piece.tw) * TILE]


def piece_key(key, piece):
    return '%s_r%dc%d' % (key, piece.row, piece.col)


def group_extra(key, gw, gh, piece):
    return 'group=%s|gw=%d|gh=%d|piece=%d,%d' % (key, gw, gh, piece.row, piece.col)


# ------------------------------------------------------------------------------------------------ palettes
def outfit_rgb(c):
    """The client's outfit colour 0..132 as RGB (same table as compose_outfit.outfit_colour)."""
    if c >= 19 * 7:
        c = 0
    if c % 19:
        h = c % 19 / 18.0
        s, v = {0: (0.25, 1.0), 1: (0.25, 0.75), 2: (0.5, 0.75), 3: (0.667, 0.75), 4: (1.0, 1.0), 5: (1.0, 0.75),
                6: (1.0, 0.5)}[c // 19]
    else:
        h, s, v = 0.0, 0.0, 1 - c / 19 / 7
    if v == 0:
        return (0, 0, 0)
    if s == 0:
        g = int(v * 255)
        return (g, g, g)
    if h < 1 / 6:
        r, b = v, v * (1 - s); g = b + (v - b) * 6 * h
    elif h < 2 / 6:
        g, b = v, v * (1 - s); r = g - (v - b) * (6 * h - 1)
    elif h < 3 / 6:
        g, r = v, v * (1 - s); b = r + (v - r) * (6 * h - 2)
    elif h < 4 / 6:
        b, r = v, v * (1 - s); g = b - (v - r) * (6 * h - 3)
    elif h < 5 / 6:
        b, g = v, v * (1 - s); r = g + (v - g) * (6 * h - 4)
    else:
        r, g = v, v * (1 - s); b = r - (v - g) * (6 * h - 5)
    return (int(r * 255), int(g * 255), int(b * 255))


OUTFIT_TABLE = tuple(outfit_rgb(i) for i in range(133))


def _nearest(table, rgb, first=0):
    best, bd = first, None
    for i in range(first, len(table)):
        d = sum((int(x) - int(y)) ** 2 for x, y in zip(table[i], rgb))
        if bd is None or d < bd:
            best, bd = i, d
    return best


def rgb_to_outfit_index(rgb):
    return _nearest(OUTFIT_TABLE, rgb)


def minimap_rgb(i):
    return ((i // 36) % 6 * 51, (i // 6) % 6 * 51, i % 6 * 51)


MINIMAP_TABLE = tuple(minimap_rgb(i) for i in range(216))


def rgb_to_minimap_index(rgb):
    return _nearest(MINIMAP_TABLE, rgb, first=1)


# ------------------------------------------------------------------------------------------------ overrides
_BOOL = ('skip', 'blocking', 'flip', 'scale2x', 'hideout')


def _parse_override(action, value, where):
    try:
        if action in _BOOL:
            if value not in ('0', '1'):
                raise ValueError('0 or 1')
            return int(value)
        if action in ('dx', 'dy'):
            return int(value)
        if action == 'ns':
            if value not in ('e', 'w'):
                raise ValueError('e or w')
            return value
        if action == 'tiles':
            m = re.fullmatch(r'(\d)(?:x(\d))?', value)
            if not m:
                raise ValueError('N or WxH')
            w, h = int(m.group(1)), int(m.group(2) or m.group(1))
            if not (1 <= w <= MAX_TILES and 1 <= h <= MAX_TILES):
                raise ValueError('1..%d tiles' % MAX_TILES)
            return (w, h)
        if action == 'light':
            m = re.fullmatch(r'(\d+):(\d+)', value)
            if not m or int(m.group(1)) > 255 or not 0 <= int(m.group(2)) <= 215:
                raise ValueError('level:colour (colour 0..215)')
            return (int(m.group(1)), int(m.group(2)))
        if not value:
            raise ValueError('a value')
        return value
    except ValueError as e:
        raise PackError('%s: %s %r should be %s' % (where, action, value, e))


def load_overrides(path=OVERRIDES_CSV):
    out = {}
    if not os.path.isfile(path):
        return out
    with open(path, newline='', encoding='utf-8') as f:
        rd = csv.reader(f)
        head = next(rd, None)
        if head != OVERRIDE_FIELDS:
            raise PackError('%s: header must be %s' % (path, ','.join(OVERRIDE_FIELDS)))
        for n, row in enumerate(rd, 2):
            if not row:
                continue
            if len(row) != 3:
                raise PackError('%s:%d: three columns expected' % (path, n))
            key, action, value = row
            if action not in OVERRIDE_ACTIONS:
                raise PackError('%s:%d: unknown action %r' % (path, n, action))
            d = out.setdefault(key, {})
            if action in d:
                raise PackError('%s:%d: %s %s twice' % (path, n, key, action))
            d[action] = _parse_override(action, value, '%s:%d' % (path, n))
    return out


def ov_get(ov, key, action, default=None):
    return ov.get(key, {}).get(action, default)


# ------------------------------------------------------------------------------------------------ check command
def check(src=None, md5=True):
    bad = []
    packs = load_packs()
    bad += check_packs(packs)
    try:
        load_overrides()
    except PackError as e:
        bad.append(str(e))
    by = pack_by_slug(packs)
    private = load_private()
    for cat in CATEGORIES:
        path = files_path(cat)
        if not os.path.isfile(path):
            bad.append('%s: missing' % path)
            continue
        rows = read_files(path)
        if files_text(rows) != open(path, encoding='utf-8').read():
            bad.append('%s: not in the canonical sorted form (files_text)' % path)
        for r in rows:
            p = by.get(r.slug)
            if p is None or p.status != 'ready' or cat not in p.cats():
                bad.append('%s: %s is not a ready pack of this category' % (path, r.slug))
        if src:
            bad += verify_files(src, rows, private, md5)
    return bad


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['check'])
    ap.add_argument('--src', help='the drivepacks folder (verifies every listed file)')
    ap.add_argument('--no-md5', action='store_true', help='with --src: sizes only')
    a = ap.parse_args(argv)
    bad = check(a.src, not a.no_md5)
    for b in bad:
        print(b)
    print('pack30lib check:', 'OK' if not bad else '%d problem(s)' % len(bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
