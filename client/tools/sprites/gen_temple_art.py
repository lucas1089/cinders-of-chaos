#!/usr/bin/env python3
"""Pair 60: the temple tileset from the owner's sheet (O431), ready for import_art_things.py.

    python3 -I gen_temple_art.py extract --src DIR           # DIR holds temple_sheet.png (SOURCE, md5 checked)
                                                             #   -> art_import/temple/temple_src.png, temple_src.csv
    python3 -I gen_temple_art.py build                       # the committed pieces -> art_import/temple.png (atlas), temple.csv
                                                             #   (things file), temple.sums, temple_sources.csv and
                                                             #   server/data/items/temple_art.csv (items.otb / items.xml manifest)
    python3 -I gen_temple_art.py build --check               # CI: the committed outputs match, every piece passes style_check
    python3 -I gen_temple_art.py build --src DIR --check     # rebuild from the owner's sheet, compare pixel for pixel
    python3 -I gen_temple_art.py themes                      # why THEME: the pieces' distance to each theme palette
    python3 -I gen_temple_art.py preview --out DIR           # contact sheet of every piece at 2x and a 13 x 13 room built from them

Source and licence: one 1584 x 1056 RGBA PNG the owner put on Google Drive (file id SOURCE_ID) on 2026-11-06 with "pode usar,
sao todas livres, comece pelo templo": free to use, per the owner. The file names no author and carries no licence text
(docs/CREDITS.md "Temple tileset"). The Drive title is not copied here. On the left a composed temple room, 13 x 13 tiles of
64 px (832 px: the true pitch, measured on the tile seams): a gold meander border one tile wide, marble floor, four 3 x 3 corner
mosaics, a red carpet, a black and white checker cross with a blue pad, blood and soot decals painted over it. On the right and
along the bottom loose oblique pieces on a transparent ground: brick walls, corners, pillars, torches, statue pedestals. Same
view as ours: the height of a thing goes up and left from its base, the light comes from the top left.

The raw sheet is not committed (1.4 MB). art_import/temple/temple_src.png holds only the pieces, packed, at the source's 64 px
scale, and temple_src.csv where each came from; `extract` makes both and `build --src` checks them against the sheet. Pieces:
  comp    a loose piece, cut at its bounding box (alpha >= 128) with 2 px of soft edge; torches, pillars and walls repeat in the
          sheet, only the pieces that differ are kept (the test checks no two are equal);
  tile    one 64 px tile of the room (a clean one: few decal pixels), block = a w x h tiles area;
  mosaic  the 3 x 3 corner mosaic: the four corners are one drawing with different decals, so each pixel is the mean of the two brightest
          of the four (decals only darken), which leaves the mosaic clean;
  blood   a blood pool of the room, keyed by colour (dark red: red 24 over green and blue, at most 140; the bright orange mosaic pegs stay out), droplets under
          80 px dropped, alpha 0 / 255: the floor under it is left out. The soot clouds are soft grey and stay baked into the
          floor, so there is no soot decal.

Build: each piece goes to 32 px by an exact 2 x 2 box average (integers: alpha-weighted colour, the piece opaque where the mean
alpha is 128 or more), the loose pieces anchored at the bottom right of a canvas of whole 32 px cells (the dat draws a thing's
bottom right cell on its tile, the rest up and left: a wall's base is its bottom right edge). Then every pixel moves to the
nearest colour of THEME's palette (style_palettes.json) and, for a prop (wall, pillar, torch, statue), the silhouette gets the
one pixel near-black outline of the theme. Floors (ground, border, mosaic, carpet, blood) are full-bleed or flat: no outline,
and the style check does not judge their outline (printed). The pieces keep the source's light: top left.

Outputs (committed): temple.csv (things: floors are `ground` items, `ground:100 notmoveable minimap fullground`; mosaic, carpet
and blood `decor`, walkable; walls, pillars, torches and statues `stump`, `bottom notwalkable notmoveable`; the torch carries
light 6 colour 206), items from FIRST_ITEM 44511 (after pair 58's 44510; pair 59 redraws in place) in table order, server id =
client id + 4000. Append to pair 59 (the output is pair 60):
    python3 -I import_art_things.py --ours-dat P59/Tibia.dat --ours-spr P59/Tibia.spr --out-dir P60 \\
        --things art_import/temple.csv --first-item 44511 --expect-items 44510 --server-offset 4000 \\
        --manifest-out ../../../server/data/items/temple_art.csv
The committed manifest is what that call writes (the test imports the importer's OTB table; `build --check` compares).
Deterministic: numpy and Pillow only (CI pins Pillow 12.3.0 / numpy 2.5.3).
"""
import argparse
import csv
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import style_check as sc  # noqa: E402

ART = os.path.join(HERE, 'art_import')
SRC_DIR = os.path.join(ART, 'temple')
SRC_SHEET = os.path.join(SRC_DIR, 'temple_src.png')
SRC_CSV = os.path.join(SRC_DIR, 'temple_src.csv')
ATLAS = os.path.join(ART, 'temple.png')
THINGS = os.path.join(ART, 'temple.csv')
SUMS = os.path.join(ART, 'temple.sums')
SOURCES = os.path.join(ART, 'temple_sources.csv')
MANIFEST = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'server', 'data', 'items', 'temple_art.csv'))

SOURCE_NAME = 'temple_sheet.png'
SOURCE_ID = '1NPYEWmgq6mQoQ-Ug_P-XW73NP9iT5qqu'     # the owner's Google Drive file (the Drive title is not copied)
SOURCE_MD5 = '481a2fc0d3cc4a96fff602d140c191a6'
SOURCE_SIZE = (1584, 1056)
T64 = 64                  # the true tile pitch of the source
CELL = 32
FIRST_ITEM = 44511        # after pair 58's last item (44510); pair 59 redraws items in place
SERVER_OFFSET = 4000
THEME = 'gildcrown'       # `themes` prints the distances behind this choice
ATLAS_W = 512             # the atlas is packed in rows this wide
SHEET_W = 1024            # the source sheet is packed in rows this wide
# pieces whose drawing is a pale pattern on a pale ground: the lightness contrast about the ground (80th percentile of the luma) is
# multiplied before the snap, or the palette's coarse steps in that range merge the pattern into the ground
STRETCH = {'mosaic': 1.8}
MIN_COLOURS = 2           # the flat-colour rule of style_check is waived down to this many colours (style_report)
WC = 0.25                 # chroma weight of the snap (snap_index)
MARGIN = 2                # soft edge pixels kept around a loose piece
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
MANIFEST_HEADER = ['client_id', 'server_id', 'key', 'kind', 'mode', 'name', 'size', 'otb_group', 'otb_flags', 'top_order',
                   'speed', 'light_level', 'light_color', 'extra']

# the four 3 x 3 mosaics of the room, top-left pixel of each (tile 1,1 / 9,1 / 1,9 / 9,9)
MOSAICS = [(64, 64), (576, 64), (64, 576), (576, 576)]

# class -> (items.otb kind, dat flags; %d = minimap colour)
CLASSES = {
    'ground': ('ground', 'ground:100 notmoveable minimap:%d fullground'),
    'decor': ('decor', 'notmoveable'),
    'block': ('stump', 'bottom notwalkable notmoveable minimap:%d'),
    'torch': ('stump', 'bottom notwalkable notmoveable light:6:206'),
}
FLOOR = ('ground', 'decor')    # no silhouette: no outline

# key, class, name, how, args. Table order = item id order. Rects are source pixels (x, y, w, h).
PIECES = [
    ('marble_floor', 'ground', 'temple marble floor', 'tile', (4, 1)),
    ('checker_black', 'ground', 'temple black marble floor', 'tile', (6, 4)),
    ('rune_pad', 'ground', 'temple blue rune pad', 'tile', (6, 6)),
    ('border_n', 'ground', 'temple gilded border north', 'tile', (3, 0)),
    ('border_e', 'ground', 'temple gilded border east', 'tile', (12, 4)),
    ('border_s', 'ground', 'temple gilded border south', 'tile', (3, 12)),
    ('border_w', 'ground', 'temple gilded border west', 'tile', (0, 3)),
    ('corner_nw', 'ground', 'temple gilded corner north west', 'tile', (0, 0)),
    ('corner_ne', 'ground', 'temple gilded corner north east', 'tile', (12, 0)),
    ('corner_sw', 'ground', 'temple gilded corner south west', 'tile', (0, 12)),
    ('corner_se', 'ground', 'temple gilded corner south east', 'tile', (12, 12)),
    ('mosaic', 'decor', 'temple mosaic floor', 'mosaic', ()),
    ('carpet', 'decor', 'temple red carpet', 'block', (5, 9, 3, 4)),
    ('blood_1', 'decor', 'temple blood stain', 'blood', (545, 305, 140, 100)),
    ('blood_2', 'decor', 'temple blood stain', 'blood', (615, 455, 110, 65)),
    ('blood_3', 'decor', 'temple blood stain', 'blood', (180, 490, 125, 70)),
    ('blood_4', 'decor', 'temple blood stain', 'blood', (270, 130, 125, 55)),
    ('wall_a', 'block', 'temple wall', 'comp', (1190, 180, 126, 82)),
    ('wall_b', 'block', 'temple wall', 'comp', (1058, 48, 123, 82)),
    ('wall_c', 'block', 'temple wall', 'comp', (1322, 180, 110, 82)),
    ('wall_thick', 'block', 'temple thick wall', 'comp', (266, 972, 128, 82)),
    ('wall_ns_a', 'block', 'temple wall', 'comp', (972, 266, 82, 126)),
    ('wall_ns_b', 'block', 'temple wall', 'comp', (1104, 266, 82, 117)),
    ('wall_ns_c', 'block', 'temple wall', 'comp', (1104, 662, 82, 112)),
    ('wall_ns_thick', 'block', 'temple thick wall end', 'comp', (1368, 398, 82, 128)),
    ('wall_corner', 'block', 'temple wall corner', 'comp', (1454, 180, 128, 80)),
    ('wall_corner_thick', 'block', 'temple thick wall corner', 'comp', (1058, 926, 128, 128)),
    ('wall_end_ew', 'block', 'temple wall end', 'comp', (1104, 180, 80, 82)),
    ('wall_end_ns', 'block', 'temple wall end', 'comp', (972, 708, 82, 80)),
    ('pillar_a', 'block', 'temple pillar', 'comp', (1464, 22, 112, 102)),
    ('pillar_b', 'block', 'temple pillar', 'comp', (542, 946, 113, 102)),
    ('pillar_c', 'block', 'temple pillar', 'comp', (946, 535, 102, 113)),
    ('pillar_d', 'block', 'temple pillar', 'comp', (1342, 538, 102, 113)),
    ('torch', 'torch', 'temple torch', 'comp', (1496, 280, 66, 92)),
    ('pedestal_a', 'block', 'temple statue pedestal', 'comp', (1342, 302, 108, 92)),
    ('pedestal_b', 'block', 'temple statue pedestal', 'comp', (1077, 427, 109, 99)),
    ('pedestal_c', 'block', 'temple statue pedestal', 'comp', (1201, 686, 117, 104)),
    ('pedestal_d', 'block', 'temple statue pedestal', 'comp', (961, 828, 93, 94)),
    ('gargoyle', 'block', 'temple gargoyle', 'comp', (940, 160, 106, 94)),
]
KEYS = [p[0] for p in PIECES]
SPEC = {p[0]: p for p in PIECES}


# ------------------------------------------------------------------------------------------------ the source
def md5_of(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        h.update(f.read())
    return h.hexdigest()


def read_rgba(path):
    a = np.array(Image.open(path).convert('RGBA'))
    a[a[..., 3] == 0] = 0
    return a


def drop_small(mask, n):
    """mask without its 8-connected parts of fewer than n pixels"""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    out = np.zeros_like(mask)
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        stack, part = [(y0, x0)], []
        while stack:
            y, x = stack.pop()
            part.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
        if len(part) >= n:
            for y, x in part:
                out[y, x] = True
    return out


def blood_mask(rgb):
    r, g, b = (rgb[..., i].astype(np.int64) for i in range(3))
    return ((r - g) >= 24) & ((r - b) >= 24) & (r <= 140)


def cut(sheet, key):
    """the piece `key` of the owner's sheet as an RGBA array at the 64 px scale"""
    _k, _cls, _name, how, args = SPEC[key]
    if how == 'tile':
        c, r = args
        return np.dstack([sheet[r * T64:(r + 1) * T64, c * T64:(c + 1) * T64, :3], np.full((T64, T64), 255, np.uint8)])
    if how == 'block':
        c, r, cs, rs = args
        return np.dstack([sheet[r * T64:(r + rs) * T64, c * T64:(c + cs) * T64, :3],
                          np.full((rs * T64, cs * T64), 255, np.uint8)])
    if how == 'mosaic':
        st = np.stack([sheet[y:y + 3 * T64, x:x + 3 * T64, :3].astype(np.int64) for x, y in MOSAICS])
        order = np.argsort(st.sum(axis=3), axis=0, kind='stable')     # decals only darken: take the two brightest pixels of the
        top = np.take_along_axis(st, order[-2:, :, :, None], axis=0)      # four (the brightest alone is biased to noise highs)
        rgb = ((top[0] + top[1] + 1) // 2).astype(np.uint8)
        return np.dstack([rgb, np.full(rgb.shape[:2], 255, np.uint8)])
    if how == 'blood':
        x, y, w, h = args
        rgb = sheet[y:y + h, x:x + w, :3]
        m = drop_small(blood_mask(rgb), 80)
        ys, xs = np.nonzero(m)
        out = np.zeros((ys.max() - ys.min() + 1, xs.max() - xs.min() + 1, 4), np.uint8)
        sub = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        out[..., :3] = np.where(sub[..., None], rgb[ys.min():ys.max() + 1, xs.min():xs.max() + 1], 0)
        out[..., 3] = np.where(sub, 255, 0)
        return out
    x, y, w, h = args
    x0, y0 = max(x - MARGIN, 0), max(y - MARGIN, 0)
    out = sheet[y0:min(y + h + MARGIN, sheet.shape[0]), x0:min(x + w + MARGIN, sheet.shape[1])].copy()
    out[out[..., 3] == 0] = 0
    return out


def pack(pieces, width, gap):
    """shelf packing of {key: array} in table order -> ({key: (x, y)}, (w, h))"""
    pos, x, y, rowh, wmax = {}, 0, 0, 0, 0
    for key in KEYS:
        h, w = pieces[key].shape[:2]
        if x and x + w > width:
            x, y, rowh = 0, y + rowh + gap, 0
        pos[key] = (x, y)
        x += w + gap
        rowh = max(rowh, h)
        wmax = max(wmax, x - gap)
    return pos, (wmax, y + rowh)


def sheet_of(pieces):
    pos, (w, h) = pack(pieces, SHEET_W, 2)
    sheet = np.zeros((h, w, 4), np.uint8)
    rows = []
    for key in KEYS:
        a = pieces[key]
        x, y = pos[key]
        sheet[y:y + a.shape[0], x:x + a.shape[1]] = a
        rows.append([key, x, y, a.shape[1], a.shape[0]])
    return sheet, rows


def src_csv_text(rows):
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(['key', 'x', 'y', 'w', 'h', 'how', 'from'])
    for key, x, y, cw, ch in rows:
        _k, _cls, _name, how, args = SPEC[key]
        w.writerow([key, x, y, cw, ch, how, ' '.join(str(v) for v in args)])
    return out.getvalue()


def load_pieces():
    """{key: RGBA at 64 px} from the committed source sheet"""
    sheet = read_rgba(SRC_SHEET)
    rows = list(csv.DictReader(open(SRC_CSV, newline='', encoding='utf-8')))
    got = {}
    for r in rows:
        x, y, w, h = (int(r[k]) for k in ('x', 'y', 'w', 'h'))
        got[r['key']] = sheet[y:y + h, x:x + w].copy()
    missing = [k for k in KEYS if k not in got]
    if missing:
        raise SystemExit('temple_src.csv misses: %s' % ', '.join(missing))
    return got


# ------------------------------------------------------------------------------------------------ the build
def down2(a):
    """64 px scale -> 32: exact 2 x 2 box average, integers; the colour weighted by alpha, opaque where the mean alpha >= 128"""
    h, w = a.shape[:2]
    assert h % 2 == 0 and w % 2 == 0
    v = a.astype(np.int64).reshape(h // 2, 2, w // 2, 2, 4)
    al = v[..., 3]
    s = al.sum(axis=(1, 3))
    num = (v[..., :3] * al[..., None]).sum(axis=(1, 3))
    rgb = np.where(s[..., None] > 0, (num + s[..., None] // 2) // np.maximum(s[..., None], 1), 0)
    opaque = s >= 512
    out = np.zeros((h // 2, w // 2, 4), np.uint8)
    out[..., :3] = np.where(opaque[..., None], rgb, 0)
    out[..., 3] = np.where(opaque, 255, 0)
    return out


def canvas64(a):
    """the art's bounding box (alpha >= 128) on a canvas of whole 64 px cells, anchored at the bottom right"""
    ys, xs = np.nonzero(a[..., 3] >= 128)
    c = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = c.shape[:2]
    H, W = -(-h // T64) * T64, -(-w // T64) * T64
    out = np.zeros((H, W, 4), np.uint8)
    out[H - h:, W - w:] = np.where((c[..., 3:4] >= 128), c, 0)
    return out


def theme_data(theme=THEME):
    data = sc.load_palettes()
    t = data['themes'][theme]
    return data, np.array([sc.unhex(x) for x in t['palette']], dtype=np.uint8), t


def snap_index(rgb, pal):
    """the palette colour of every row of rgb (N, 3): nearest in CIELAB with the chroma weighted WC. Marble is pale and nearly
    one hue, so plain nearest-colour snapping (style_check.py snap) leaves a tile two colours; weighting lightness keeps the
    shading steps and lets the hue slide along the theme's ramps. Every output colour is a palette colour."""
    lab, plab = sc.to_lab(rgb), sc.to_lab(pal)
    d = (lab[:, None, 0] - plab[None, :, 0]) ** 2 + WC * ((lab[:, None, 1:] - plab[None, :, 1:]) ** 2).sum(-1)
    return d.argmin(1)


def outline(a, colour):
    """the silhouette's one pixel rim (as style_check measures it: outside the canvas counts as empty) in the outline colour"""
    solid = a[..., 3] == 255
    rim = solid & ~sc.erode(solid)
    out = a.copy()
    out[rim, :3] = colour
    return out


def render(key, src, pal, edge, snap=True):
    """the 32 px RGBA of one piece"""
    cls, how = SPEC[key][1], SPEC[key][3]
    a = down2(canvas64(src) if how in ('comp', 'blood') else src)
    if how == 'blood':   # droplets of a pixel or two do not survive 32 px: drop them, then trim to whole cells again
        m = drop_small(a[..., 3] == 255, 4)
        a[~m] = 0
        ys, xs = np.nonzero(m)
        c = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        h, w = c.shape[:2]
        H, W = -(-h // CELL) * CELL, -(-w // CELL) * CELL
        a = np.zeros((H, W, 4), np.uint8)
        a[H - h:, W - w:] = c
    if snap and key in STRETCH:
        vis = a[..., 3] > 0
        v = a[vis][:, :3].astype(np.float64)
        y = sc.luma(v)
        d = (STRETCH[key] - 1.0) * (y - np.percentile(y, 80))      # lightness only: the hue stays
        a[vis, :3] = np.clip(np.rint(v + d[:, None]), 0, 255).astype(np.uint8)
    if snap:
        vis = a[..., 3] > 0
        a[vis, :3] = pal[snap_index(a[vis][:, :3], pal)]
    if cls not in FLOOR:
        a = outline(a, edge)
    return a


def minimap_index(a):
    """the 6 x 6 x 6 minimap cube colour (1..215) nearest to the mean colour of the opaque pixels"""
    mean = a[a[..., 3] == 255][:, :3].mean(axis=0)
    best, bd = 1, None
    for i in range(1, 216):
        c = ((i // 36) % 6 * 51, (i // 6) % 6 * 51, i % 6 * 51)
        d = sum((float(x) - y) ** 2 for x, y in zip(c, mean))
        if bd is None or d < bd:
            best, bd = i, d
    return best


def build_all(pieces):
    """({key: RGBA 32 px}, theme data, palette)"""
    data, pal, t = theme_data()
    edge = np.array(sc.unhex(t['outline'][0]), dtype=np.uint8)
    return {k: render(k, pieces[k], pal, edge) for k in KEYS}, data, pal, t


def atlas_of(arts):
    pos, (w, h) = pack(arts, ATLAS_W, 0)
    atlas = np.zeros((h, w, 4), np.uint8)
    for k in KEYS:
        x, y = pos[k]
        atlas[y:y + arts[k].shape[0], x:x + arts[k].shape[1]] = arts[k]
    return atlas, pos


def things_text(arts, pos):
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    for k in KEYS:
        _k, cls, name, how, _args = SPEC[k]
        kind, flags = CLASSES[cls]
        if '%d' in flags:
            flags = flags % minimap_index(arts[k])
        h, wd = arts[k].shape[0] // CELL, arts[k].shape[1] // CELL
        x, y = pos[k]
        part = k.rsplit('_', 1)[0] if '_' in k and len(k.rsplit('_', 1)[1]) == 1 else k
        extra = 'family=temple|part=%s|block=%d' % (part, 1 if kind == 'stump' else 0)
        w.writerow([k, 'item', kind, name, 'temple', x, y, wd, h, 1, 1, flags, 'new', '', extra])
    return out.getvalue()


def manifest_text(things):
    """what import_art_things.py --manifest-out writes for the things file (its OTB table and rules)"""
    import import_art_things as imp
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(MANIFEST_HEADER)
    for k, r in enumerate(csv.DictReader(io.StringIO(things))):
        toks = {t.split(':')[0]: t.split(':')[1:] for t in r['flags'].split()}
        g, fl, top = imp.OTB[r['kind']]
        if 'notwalkable' in toks:
            fl |= imp.SOLID
        speed = int(toks['ground'][0]) if 'ground' in toks else 0
        light = tuple(int(v) for v in toks['light']) if 'light' in toks else (0, 0)
        cid = FIRST_ITEM + k
        w.writerow([cid, cid + SERVER_OFFSET, r['key'], r['kind'], r['mode'], r['name'], '%sx%s' % (r['w'], r['h']), g, fl,
                    top, speed, light[0], light[1], r['extra']])
    return out.getvalue()


def sources_text():
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(['name', 'kind', 'pack', 'source', 'licence'])
    w.writerow(['temple tileset', 'item', 'Temple tileset',
                'owner-supplied sheet (Google Drive file %s, md5 %s, 1584 x 1056); pieces cut by gen_temple_art.py, '
                'committed as art_import/temple/temple_src.png' % (SOURCE_ID, SOURCE_MD5),
                'supplied by the owner, free to use per the owner (2026-11-06); no licence text came with it; docs/CREDITS.md'])
    return out.getvalue()


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def sums_text(pieces, arts, atlas):
    out = ''.join('%s  temple_src/%s\n' % (digest(pieces[k]), k) for k in KEYS)
    out += ''.join('%s  temple/%s\n' % (digest(arts[k]), k) for k in KEYS)
    return out + '%s  temple.png\n' % digest(atlas)


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def style_report(key, a, data, pal, t):
    """(reasons, warnings, colours) of one piece against THEME; a floor's outline rule is not judged (it has no silhouette)"""
    bad, warn = sc.judge(sc.measure(a), pal, t['light'], data['thresholds'])
    ncol = len(np.unique(a[a[..., 3] > 0][:, :3], axis=0))
    if SPEC[key][1] in FLOOR:
        bad = [b for b in bad if not b.startswith('outline:')]
    # the source is painted flat: marble, brick and blood are two to ten shades (the owners' items carry 19 to 61). The palette
    # snap keeps that. The rule against flat art is waived down to MIN_COLOURS, printed; every other rule is judged.
    if ncol >= MIN_COLOURS:
        bad = [b for b in bad if not b.startswith('colours: %d, at least' % ncol)]
    return bad, warn, ncol


def problems_of(arts):
    out = []
    for k in KEYS:
        a = arts[k]
        if a.shape[0] % CELL or a.shape[1] % CELL:
            out.append('%s: %d x %d is not whole cells' % (k, a.shape[1], a.shape[0]))
        if (~np.isin(a[..., 3], (0, 255))).any():
            out.append('%s: semi-transparent pixels' % k)
        if (a[a[..., 3] == 0][:, :3] != 0).any():
            out.append('%s: colour under transparent pixels' % k)
    for i, a in enumerate(KEYS):
        for b in KEYS[i + 1:]:
            if arts[a].shape == arts[b].shape and np.array_equal(arts[a], arts[b]):
                out.append('%s and %s are the same picture' % (a, b))
    return out


# ------------------------------------------------------------------------------------------------ commands
def cmd_extract(src_dir):
    path = os.path.join(src_dir, SOURCE_NAME)
    if not os.path.isfile(path):
        sys.exit('%s not found' % path)
    if md5_of(path) != SOURCE_MD5:
        sys.exit('%s: md5 %s, expected %s' % (SOURCE_NAME, md5_of(path), SOURCE_MD5))
    sheet = read_rgba(path)
    if sheet.shape[:2] != (SOURCE_SIZE[1], SOURCE_SIZE[0]):
        sys.exit('unexpected size %s' % (sheet.shape,))
    return {k: cut(sheet, k) for k in KEYS}


def run_build(a):
    if a.src:
        pieces = cmd_extract(a.src)
        sheet, rows = sheet_of(pieces)
        if a.check:
            ok = os.path.isfile(SRC_SHEET) and np.array_equal(read_rgba(SRC_SHEET), sheet) and \
                open(SRC_CSV, encoding='utf-8').read() == src_csv_text(rows)
            print('committed source sheet matches the owner sheet' if ok else 'stale: art_import/temple (run extract)')
            if not ok:
                return 1
        else:
            os.makedirs(SRC_DIR, exist_ok=True)
            with open(SRC_SHEET, 'wb') as f:
                f.write(png_bytes(sheet))
            with open(SRC_CSV, 'w', encoding='utf-8', newline='') as f:
                f.write(src_csv_text(rows))
            print('wrote', SRC_SHEET, sheet.shape[1], 'x', sheet.shape[0], '(%d pieces)' % len(KEYS))
    pieces = load_pieces()
    arts, data, pal, t = build_all(pieces)
    errs = problems_of(arts)
    failed = bool(errs)
    for e in errs:
        print('FAIL', e)
    for k in KEYS:
        bad, warn, ncol = style_report(k, arts[k], data, pal, t)
        note = 'style PASS (%s%s)' % (THEME, '; flat-colour rule waived' if ncol < data['thresholds']['colours_min'] else '')
        print('%-18s %dx%d tiles %2d colours %s' % (k, arts[k].shape[1] // CELL, arts[k].shape[0] // CELL, ncol,
                                                    note if not bad else 'FAIL'))
        for b in bad:
            print('  ' + b)
        for w_ in warn:
            print('  warn ' + w_)
        failed = failed or bool(bad)
    if failed:
        return 1
    atlas, pos = atlas_of(arts)
    things = things_text(arts, pos)
    want = {ATLAS: None, THINGS: things, MANIFEST: manifest_text(things), SOURCES: sources_text(),
            SUMS: sums_text(pieces, arts, atlas)}
    if a.check:
        ok = os.path.exists(ATLAS) and np.array_equal(read_rgba(ATLAS), atlas)
        if not ok:
            print('stale:', os.path.relpath(ATLAS, HERE))
        for path, text in want.items():
            if text is not None and (not os.path.exists(path) or open(path, encoding='utf-8').read() != text):
                print('stale:', os.path.relpath(path, HERE))
                ok = False
        print('temple art up to date' if ok else 'run: python3 -I gen_temple_art.py build')
        return 0 if ok else 1
    with open(ATLAS, 'wb') as f:
        f.write(png_bytes(atlas))
    for path, text in want.items():
        if text is not None:
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(text)
    print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client ids %d-%d' % (FIRST_ITEM, FIRST_ITEM + len(KEYS) - 1))
    return 0


def cmd_themes():
    pieces = load_pieces()
    data = sc.load_palettes()
    raw = {k: down2(canvas64(pieces[k]) if SPEC[k][3] in ('comp', 'blood') else pieces[k]) for k in KEYS}
    print('%-14s %s' % ('theme', 'mean CIE76 distance of the pieces to the palette: floors / props (share of far pixels)'))
    for name in data['themes']:
        pal = np.array([sc.unhex(x) for x in data['themes'][name]['palette']], dtype=np.uint8)
        res = []
        for floor in (True, False):
            paint = np.concatenate([raw[k][raw[k][..., 3] == 255][:, :3] for k in KEYS if (SPEC[k][1] in FLOOR) == floor])
            d, far = sc.palette_fit(paint, pal)
            res.append('%5.1f (%2.0f%%)' % (d, far * 100))
        print('%-14s %s%s' % (name, ' / '.join(res), '   <- THEME' if name == THEME else ''))
    return 0


def preview(outdir):
    pieces = load_pieces()
    arts, _data, _pal, _t = build_all(pieces)
    os.makedirs(outdir, exist_ok=True)
    z, pad = 2, 8
    W = 1100
    x = y = pad
    rowh = 0
    cells = []
    for k in KEYS:
        h, w = arts[k].shape[:2]
        if x + w * z + pad > W:
            x, y, rowh = pad, y + rowh + pad, 0
        cells.append((k, x, y))
        x += w * z + pad
        rowh = max(rowh, h * z)
    H = y + rowh + pad
    for side, bg in (('dark', (44, 38, 40, 255)), ('light', (150, 140, 120, 255))):
        im = Image.new('RGBA', (W, H), bg)
        for k, cx, cy in cells:
            a = Image.fromarray(arts[k], 'RGBA')
            im.alpha_composite(a.resize((a.width * z, a.height * z), Image.NEAREST), (cx, cy))
        p = os.path.join(outdir, 'temple_pieces_%s.png' % side)
        im.convert('RGB').save(p)
        print('preview', p)
    # a 13 x 13 room: the layout of the owner's mockup, built from the 32 px pieces
    S = 13
    room = Image.new('RGBA', (S * CELL, S * CELL), (0, 0, 0, 255))

    def put(key, tx, ty):
        a = Image.fromarray(arts[key], 'RGBA')
        room.alpha_composite(a, ((tx + 1) * CELL - a.width, (ty + 1) * CELL - a.height))   # a thing's bottom right cell is its tile
    for ty in range(S):
        for tx in range(S):
            edge_x, edge_y = tx in (0, S - 1), ty in (0, S - 1)
            if edge_x and edge_y:
                put('corner_%s%s' % ('n' if ty == 0 else 's', 'w' if tx == 0 else 'e'), tx, ty)
            elif edge_y:
                put('border_n' if ty == 0 else 'border_s', tx, ty)
            elif edge_x:
                put('border_w' if tx == 0 else 'border_e', tx, ty)
            else:
                put('marble_floor', tx, ty)
    for tx, ty in ((6, 4), (5, 5), (7, 5), (4, 6), (8, 6), (5, 7), (7, 7), (6, 8)):
        put('checker_black', tx, ty)
    put('rune_pad', 6, 6)
    for tx, ty in ((3, 3), (11, 3), (3, 11), (11, 11)):
        put('mosaic', tx, ty)
    put('carpet', 7, 12)
    put('blood_1', 9, 5)
    put('blood_3', 4, 8)
    for tx, ty in ((4, 2), (8, 2)):
        put('pillar_a', tx, ty)
        put('torch', tx + 1, ty + 1)
    big = room.resize((S * CELL * 3, S * CELL * 3), Image.NEAREST)
    p = os.path.join(outdir, 'temple_room.png')
    big.convert('RGB').save(p)
    print('preview', p)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['extract', 'build', 'themes', 'preview'])
    ap.add_argument('--src', default=None, help='folder with %s (extract; build --src --check rebuilds from it)' % SOURCE_NAME)
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--out', default=None, help='preview folder')
    a = ap.parse_args()
    if a.cmd == 'extract':
        if not a.src:
            sys.exit('extract needs --src DIR')
        a.cmd = 'build'
        a.check = False
        return run_build(a)
    if a.cmd == 'build':
        return run_build(a)
    if a.cmd == 'themes':
        return cmd_themes()
    if not a.out:
        sys.exit('preview needs --out DIR')
    return preview(a.out)


if __name__ == '__main__':
    sys.exit(main())
