#!/usr/bin/env python3
"""HD minimap swatch atlas: one 8 px per tile picture per item type of the map (O543, base patch 0197).

The minimap of the client draws one flat colour per tile. With the patch the client also keeps, per tile, the client ids of
its ground, ground border, decoration and top solid item, and draws the explored area from small pictures of those items
(the swatches of this atlas) when the map is zoomed to 2 px per tile or more. A swatch is the item's first sprite phase
(pattern 0) averaged 4x4 down from 32 px to 8 px per tile cell (a 2x2 item is 16 x 16), alpha weighted so the colour of a thin
wall is not dimmed by the empty pixels round it, and lightly sharpened. The pair itself is read by this tool only; the atlas
is made of our own art, derived pixels, like the other generated art of the overlay.

  python3 -I client/tools/gen_minimap_swatches.py build DAT SPR             # write swatches.png and index.txt (needs the pair)
  python3 -I client/tools/gen_minimap_swatches.py build --check             # committed files agree with each other (CI, no pair)
  python3 -I client/tools/gen_minimap_swatches.py build --check DAT SPR     # and are what the pair gives (live pair job)
  python3 -I client/tools/gen_minimap_swatches.py ids MAP.otbm|MAP.npz ITEMS_DIR [DAT]   # rewrite ids.txt from a world map

Inputs (client/tools/minimap_hd/ids.txt): the client item ids the world map uses, one line `first[-last]` (decimal). A new item
type in the map that is not listed draws as the flat colour square of before (the client falls back), so rerun `ids` and
`build` when a map change brings a new type; map edits that only move known types need nothing.
Outputs (client/overlay/data/minimap_hd/): swatches.png (RGBA atlas, 2048 px wide) and index.txt:
  chaos-minimap-hd 1
  atlas swatches.png <width> <height> <cell px> <sha256 of the png file>
  <client id> <x> <y> <w h cells, two digits> <flags hex>      one line per item type, x y = atlas pixel of its top left
flags: 1 solid (blocks walking, not ground or border: walls, rock, trees; drawn with the alpha boost), 2 tall (solid and blocks
missiles: casts a shadow), 4 water ground (minimap colour 51), 8 lava ground (minimap colour 192).
Limits (checked): the png stays under 4 MB, the index lists exactly the ids of ids.txt.
"""
import argparse
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
IDS_FILE = os.path.join(HERE, 'minimap_hd', 'ids.txt')
OUT_DIR = os.path.join(ROOT, 'client', 'overlay', 'data', 'minimap_hd')
PNG_NAME = 'swatches.png'
INDEX_NAME = 'index.txt'
INDEX_HEAD = 'chaos-minimap-hd 1'
CELL = 8                 # atlas px per tile cell
SRC = 32                 # sprite px
ATLAS_W = 2048
MAX_PNG_BYTES = 4 * 1000 * 1000
WATER_COLOUR = 51        # dat minimap colour of water ground
LAVA_COLOUR = 192
F_SOLID, F_TALL, F_WATER, F_LAVA = 1, 2, 4, 8


class SwatchError(Exception):
    pass


# ---------------------------------------------------------------- ids file
def read_ids(path=IDS_FILE):
    out = []
    with open(path, encoding='utf-8') as f:
        for ln in f:
            ln = ln.split('#')[0].strip()
            if not ln:
                continue
            a, _, b = ln.partition('-')
            lo, hi = int(a), int(b or a)
            if hi < lo:
                raise SwatchError('bad range %s' % ln)
            out.extend(range(lo, hi + 1))
    if out != sorted(set(out)):
        raise SwatchError('ids.txt must be ascending without repeats')
    return out


def format_ids(ids):
    lines = ['# client item ids the world map uses (O543; client/tools/gen_minimap_swatches.py ids), ascending ranges']
    ids = sorted(set(ids))
    i = 0
    while i < len(ids):
        j = i
        while j + 1 < len(ids) and ids[j + 1] == ids[j] + 1:
            j += 1
        lines.append(str(ids[i]) if i == j else '%d-%d' % (ids[i], ids[j]))
        i = j + 1
    return '\n'.join(lines) + '\n'


# ---------------------------------------------------------------- pair side
def item_flags(t):
    f = t.flags
    ground = 'ground' in f
    border = 'clip' in f
    solid = 'notwalkable' in f and not ground and not border
    flags = 0
    if solid:
        flags |= F_SOLID
        if 'blockmissile' in f:
            flags |= F_TALL
    if ground:
        mm = f.get('minimap')
        if mm == WATER_COLOUR:
            flags |= F_WATER
        elif mm == LAVA_COLOUR:
            flags |= F_LAVA
    return flags


def sprite_at(t, ww, hh):
    """sprite id of cell (ww, hh) of an item's first phase and pattern (x y z 0, layer 0)"""
    idx = (((0 * t.py + 0) * t.px + 0) * t.layers + 0) * t.h + hh
    idx = idx * t.w + ww
    return t.sprites[idx] if idx < len(t.sprites) else 0


def render_swatch(t, spr):
    """straight RGBA uint8 array (h * CELL, w * CELL, 4), or None for an item without a pixel"""
    w, h = t.w, t.h
    big = Image.new('RGBA', (w * SRC, h * SRC), (0, 0, 0, 0))
    for hh in range(h):
        for ww in range(w):
            sid = sprite_at(t, ww, hh)
            if not sid:
                continue
            a = spr.sprite(sid)
            if a is None:
                continue
            big.alpha_composite(Image.fromarray(np.asarray(a, np.uint8), 'RGBA'), ((w - 1 - ww) * SRC, (h - 1 - hh) * SRC))
    px = np.asarray(big, np.float32)
    al = px[..., 3:] / 255.0
    pm = px[..., :3] * al
    k = SRC // CELL
    pm = pm.reshape(h * CELL, k, w * CELL, k, 3).mean((1, 3))
    al = al.reshape(h * CELL, k, w * CELL, k, 1).mean((1, 3))
    if float(al.max()) <= 0.0:
        return None
    col = np.where(al > 0.004, pm / np.maximum(al, 0.004), 0.0)
    rgb = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), 'RGB')
    # a light sharpen on the colour, only where the swatch has body
    sharp = np.asarray(rgb.filter(ImageFilter.UnsharpMask(0.8, 45, 0)), np.float32)
    col = np.where(al > 0.5, sharp, col)
    out = np.zeros((h * CELL, w * CELL, 4), np.uint8)
    out[..., :3] = np.clip(np.rint(col), 0, 255).astype(np.uint8)
    out[..., 3:] = np.clip(np.rint(al * 255), 0, 255).astype(np.uint8)
    out[out[..., 3] == 0] = 0
    return out


def pack(items):
    """shelf packing, tallest first, ids ascending inside a shelf; returns ([(cid, x, y, w, h, flags, arr)], atlas height)"""
    order = sorted(items, key=lambda r: (-r[2].shape[0], -r[2].shape[1], r[0]))
    placed = []
    x = y = shelf = 0
    for cid, flags, arr in order:
        h, w = arr.shape[:2]
        if x + w > ATLAS_W:
            x, y, shelf = 0, y + shelf, 0
        placed.append((cid, x, y, w // CELL, h // CELL, flags, arr))
        x += w
        shelf = max(shelf, h)
    return placed, y + shelf


def build(dat, spr, ids):
    items = []
    for cid in ids:
        i = cid - 100
        if i < 0 or i >= len(dat.items):
            continue
        t = dat.items[i]
        arr = render_swatch(t, spr)
        if arr is not None:
            items.append((cid, item_flags(t), arr))
    placed, height = pack(items)
    atlas = np.zeros((max(height, 1), ATLAS_W, 4), np.uint8)
    for cid, x, y, w, h, flags, arr in placed:
        atlas[y:y + arr.shape[0], x:x + arr.shape[1]] = arr
    buf = io.BytesIO()
    Image.fromarray(atlas, 'RGBA').save(buf, 'PNG', optimize=True)
    png = buf.getvalue()
    lines = [INDEX_HEAD, 'atlas %s %d %d %d %s' % (PNG_NAME, ATLAS_W, atlas.shape[0], CELL, hashlib.sha256(png).hexdigest())]
    for cid, x, y, w, h, flags, _a in sorted(placed, key=lambda r: r[0]):
        lines.append('%d %d %d %d%d %x' % (cid, x, y, w, h, flags))
    return png, '\n'.join(lines) + '\n'


# ---------------------------------------------------------------- reading the index back (the client does the same)
def parse_index(text):
    lines = text.splitlines()
    if not lines or lines[0] != INDEX_HEAD:
        raise SwatchError('bad index header')
    p = lines[1].split()
    if len(p) != 6 or p[0] != 'atlas':
        raise SwatchError('bad atlas line')
    atlas = {'file': p[1], 'w': int(p[2]), 'h': int(p[3]), 'cell': int(p[4]), 'sha256': p[5]}
    recs = []
    for ln in lines[2:]:
        q = ln.split()
        if len(q) != 5 or len(q[3]) != 2:
            raise SwatchError('bad item line: %r' % ln)
        recs.append((int(q[0]), int(q[1]), int(q[2]), int(q[3][0]), int(q[3][1]), int(q[4], 16)))
    return atlas, recs


def check_files(png, text, ids):
    """the committed png and index agree: hash, geometry inside the atlas, no overlap, ids a subset of ids.txt, size"""
    atlas, recs = parse_index(text)
    errs = []
    if hashlib.sha256(png).hexdigest() != atlas['sha256']:
        errs.append('swatches.png does not match the sha256 of index.txt')
    if len(png) > MAX_PNG_BYTES:
        errs.append('swatches.png is %d bytes, over the %d byte budget' % (len(png), MAX_PNG_BYTES))
    im = Image.open(io.BytesIO(png))
    if im.size != (atlas['w'], atlas['h']) or im.mode != 'RGBA':
        errs.append('swatches.png is %s %s, the index says %dx%d RGBA' % (im.size, im.mode, atlas['w'], atlas['h']))
    cell = atlas['cell']
    grid = np.zeros((atlas['h'], atlas['w']), np.uint8)
    seen = set()
    idset = set(ids)
    for cid, x, y, w, h, fl in recs:
        if cid in seen:
            errs.append('item %d twice' % cid)
        seen.add(cid)
        if cid not in idset:
            errs.append('item %d is not in ids.txt' % cid)
        pw, ph = w * cell, h * cell
        if w < 1 or h < 1 or x < 0 or y < 0 or x + pw > atlas['w'] or y + ph > atlas['h']:
            errs.append('item %d outside the atlas' % cid)
            continue
        if fl & ~0xF or (fl & F_TALL and not fl & F_SOLID) or (fl & F_WATER and fl & F_LAVA):
            errs.append('item %d has bad flags %x' % (cid, fl))
        if grid[y:y + ph, x:x + pw].any():
            errs.append('item %d overlaps another' % cid)
        grid[y:y + ph, x:x + pw] = 1
    if len(seen) < 0.9 * len(idset):
        errs.append('only %d of %d ids have a swatch' % (len(seen), len(idset)))
    return errs


# ---------------------------------------------------------------- ids from a map
def cmd_ids(args):
    sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))
    import otbm
    from itemdb import ItemDB
    m = otbm.load_cache(args.map) if args.map.endswith('.npz') else otbm.load_otbm(args.map)
    db = ItemDB(os.path.join(args.items, 'items.otb'), os.path.join(args.items, 'items.xml'), args.dat)
    used = np.unique(m.items)
    cids = sorted({int(db.cid[s]) for s in used if s < len(db.cid) and db.cid[s]})
    with open(IDS_FILE, 'w', encoding='utf-8') as f:
        f.write(format_ids(cids))
    print('ids.txt: %d client ids' % len(cids))
    return 0


def cmd_build(args):
    ids = read_ids()
    png_path = os.path.join(OUT_DIR, PNG_NAME)
    idx_path = os.path.join(OUT_DIR, INDEX_NAME)
    if args.check:
        png = open(png_path, 'rb').read()
        text = open(idx_path, encoding='utf-8').read()
        errs = check_files(png, text, ids)
        if args.dat:
            sys.path.insert(0, os.path.join(ROOT, 'client', 'tools', 'sprites'))
            from datspr import Dat, Spr
            dat, spr = Dat(args.dat), Spr(args.spr)
            npng, ntext = build(dat, spr, ids)
            if npng != png or ntext != text:
                errs.append('the committed atlas is not what this pair gives (run build DAT SPR)')
        for e in errs:
            print('FAIL', e)
        if not errs:
            print('minimap swatches ok: %d items, %d bytes png' % (len(parse_index(text)[1]), len(png)))
        return 1 if errs else 0
    if not args.dat:
        print('build needs DAT SPR (or --check)')
        return 2
    sys.path.insert(0, os.path.join(ROOT, 'client', 'tools', 'sprites'))
    from datspr import Dat, Spr
    dat, spr = Dat(args.dat), Spr(args.spr)
    png, text = build(dat, spr, ids)
    errs = check_files(png, text, ids)
    if errs:
        for e in errs:
            print('FAIL', e)
        return 1
    os.makedirs(OUT_DIR, exist_ok=True)
    open(png_path, 'wb').write(png)
    open(idx_path, 'w', encoding='utf-8').write(text)
    print('wrote %s (%d bytes) and %s (%d bytes)' % (PNG_NAME, len(png), INDEX_NAME, len(text)))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--check', action='store_true')
    b.add_argument('dat', nargs='?')
    b.add_argument('spr', nargs='?')
    i = sub.add_parser('ids')
    i.add_argument('map')
    i.add_argument('items')
    i.add_argument('dat', nargs='?')
    args = ap.parse_args(argv)
    if args.cmd == 'build':
        return cmd_build(args)
    return cmd_ids(args)


if __name__ == '__main__':
    sys.exit(main())
