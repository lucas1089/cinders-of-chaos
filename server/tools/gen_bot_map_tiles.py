#!/usr/bin/env python3
"""Map tiles for the staff's live bot map (O727, server/README.md "Bot live map (O727)"): the installed world map drawn floor by floor from the
HD minimap swatches, as a standard z/x/y tile pyramid of PNG files. Never committed (the world map is not in git, and the tiles show all of it).

  python3 -I server/tools/gen_bot_map_tiles.py SERVER_DIR --out DIR [--pointer FILE --url NAME] [--levels 5] [--floors 7,8] [--swatches DIR]
                                                              [--full-colour] [--dry-run]
  python3 -I server/tools/gen_bot_map_tiles.py --map FILE.otbm --items DIR --out DIR ...      (a map and an items folder given by hand)

SERVER_DIR has data/world/<mapName>.otbm (the mapName of config.lua, else the only .otbm) and data/items/items.otb + items.xml. The art is the
committed swatch atlas of the client's HD minimap (client/overlay/data/minimap_hd, client/tools/gen_minimap_swatches.py): the sprite pair is not
needed. A tile of the map is drawn the way the client's HD minimap composes it (base patch 0197): a flat square, the ground, the ground border,
the top decoration, then the top solid (a wall, a tree) with its alpha boosted; a swatch of 2 x 2 tiles or more sits on its bottom right tile.
Which item is which comes from items.otb and items.xml (tools/map/itemdb.py: ground, border, solid, decoration); a tile whose ground has no
swatch stays the dark flat square.

Output, in --out (an empty or new folder): <floor z>/<zoom>/<x>/<y>.png and meta.json. Tile geometry (all floors share it):
  * a tile is 256 px; the top zoom (levels - 1) draws 8 px a game tile, so a tile covers 32 x 32 game tiles; every zoom below halves that
    (the default 5 levels: 8, 4, 2, 1 and 0.5 px a game tile);
  * the origin (X0, Y0) is the smallest used x and y over all floors, rounded down to 32; tile (tx, ty) at zoom z covers the game tiles
    X0 + tx * span .. + span - 1 (and the same for y, south is up in ty), with span = 32 * 2^(top - z);
  * for Leaflet's simple CRS (the staff page): lng = (x - X0) / span0, lat = -(y - Y0) / span0, span0 = the span at zoom 0 (meta.json "span0").
meta.json: {"v": 1, "tile": 256, "minZoom": 0, "maxZoom": top, "cell": 8, "origin": [X0, Y0], "span0": N, "bbox": [x0, y0, x1, y1],
"floors": [{"z", "tiles", "bbox"}], "towns": [{"id", "name", "x", "y", "z"}] (the towns of the map: their temples), "built": epoch}.
--pointer FILE (with --url NAME, the folder's address under the site) writes the same meta plus "url" there: the staff page reads it from the server's
data folder, so the address of the tiles (a folder named with a secret token, like areas-publish) is never in a public file.
PNG files are quantised to 256 colours (a quarter of the size); --full-colour keeps 32 bit. --dry-run counts the tiles and the megabytes only.
"""
import argparse
import json
import os
import re
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))
sys.path.insert(0, os.path.join(ROOT, 'client', 'tools'))
DEFAULT_SWATCHES = os.path.join(ROOT, 'client', 'overlay', 'data', 'minimap_hd')

TILE = 256
CELL = 8
SPAN = TILE // CELL          # game tiles a side of a tile at the top zoom
VERSION = 1
FLAT = (24, 24, 24)          # the flat square of a seen tile (the client's fallback colour)
BOOST = 1.55                 # the alpha boost of a solid (chaosminimaphd.h kSolidBoost)
R_GROUND, R_BORDER, R_SOLID, R_DECOR = 1, 2, 3, 4
EST_BYTES = {True: 9000, False: 30000}   # a rough PNG size by mode (quantised or not), for --dry-run


class TileError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ the swatches
class Atlas:
    """the swatch atlas of the client's HD minimap: 1 x 1 swatches in one table (row 0 is empty), larger ones apart"""

    def __init__(self, folder):
        import gen_minimap_swatches as GS
        try:
            with open(os.path.join(folder, GS.INDEX_NAME), encoding='utf-8') as f:
                meta, recs = GS.parse_index(f.read())
            pic = np.asarray(Image.open(os.path.join(folder, meta['file'])).convert('RGBA'))
        except (OSError, GS.SwatchError, ValueError) as e:
            raise TileError('no swatch atlas in %s: %s' % (folder, e))
        if pic.shape[1] != meta['w'] or pic.shape[0] != meta['h'] or meta['cell'] != CELL:
            raise TileError('the swatch picture does not match its index')
        self.index = np.zeros(65536, np.int32)       # client id -> row of `small` (0: none)
        self.bigmask = np.zeros(65536, bool)
        self.flags = np.zeros(65536, np.uint8)
        self.big = {}
        small = [np.zeros((CELL, CELL, 4), np.uint8)]
        for cid, x, y, w, h, flags in recs:
            cell = pic[y:y + h * CELL, x:x + w * CELL]
            self.flags[cid] = flags
            if w == 1 and h == 1:
                self.index[cid] = len(small)
                small.append(cell.copy())
            else:
                self.bigmask[cid] = True
                self.big[cid] = (w, h, cell.copy())
        self.small = np.stack(small)
        self.margin = max([max(w, h) - 1 for w, h, _ in self.big.values()] + [0])

    def has(self, cid):
        return bool(self.index[cid] or self.bigmask[cid])


# ------------------------------------------------------------------------------------------------ the map
def find_map(server):
    world = os.path.join(server, 'data', 'world')
    cfg = os.path.join(server, 'config.lua')
    if os.path.isfile(cfg):
        with open(cfg, encoding='utf-8', errors='replace') as f:
            m = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', f.read(), re.M)
        if m and os.path.isfile(os.path.join(world, m.group(1) + '.otbm')):
            return os.path.join(world, m.group(1) + '.otbm')
    maps = sorted(n for n in os.listdir(world) if n.endswith('.otbm')) if os.path.isdir(world) else []
    if len(maps) != 1:
        raise TileError('no world map: give SERVER_DIR with data/world/<mapName>.otbm, or --map')
    return os.path.join(world, maps[0])


def roles_of(db):
    """(role, cid) per server id: what an item is for the picture, by the rules of the client's chaosRecipe on what items.otb and items.xml
    tell (the flags of the .dat are not read): ground, ground border, solid (blocks walking, cannot be picked up), decoration (static or
    not movable). Splashes, fluids and unknown ids draw nothing"""
    from itemdb import C
    n = len(db.cid)
    role = np.zeros(n, np.uint8)
    cls, fl = db.cls, db.flags
    live = db.known & (db.cid > 0)
    ground = live & (cls == C['ground'])
    border = live & ~ground & (cls == C['border'])
    solid = live & ~ground & ~border & ((fl & 1) > 0) & ((fl & 32) == 0)
    decor = live & ~ground & ~border & ~solid & (cls != C['splash']) & (cls != C['none']) & (((fl & 64) == 0) | (db.order > 0))
    role[decor] = R_DECOR
    role[solid] = R_SOLID
    role[border] = R_BORDER
    role[ground] = R_GROUND
    return role, db.cid.astype(np.uint16)


def recipes(m, role, cid):
    """per tile of the map: the client ids of its ground, border, decoration and solid (the last item of a kind in the stack wins, as in the
    client) -> four uint16 arrays"""
    n = len(m.tiles['x'])
    tile_of = np.repeat(np.arange(n, dtype=np.int64), m.tiles['cnt'].astype(np.int64))
    rl = role[m.items]
    cd = cid[m.items]
    out = {}
    for name, r in (('ground', R_GROUND), ('border', R_BORDER), ('decor', R_DECOR), ('solid', R_SOLID)):
        arr = np.zeros(n, np.uint16)
        sel = rl == r
        idx, val = tile_of[sel][::-1], cd[sel][::-1]
        u, first = np.unique(idx, return_index=True)    # the first of the reversed list is the last of the stack
        arr[u] = val[first]
        out[name] = arr
    return out


class Floor:
    """the recipe of one floor as dense rasters over the map's box (a margin on the right and bottom for the big swatches)"""

    def __init__(self, m, rec, z, origin, atlas):
        t = m.tiles
        sel = np.flatnonzero(t['z'] == z)
        self.z = z
        self.count = len(sel)
        x = t['x'][sel].astype(np.int64)
        y = t['y'][sel].astype(np.int64)
        self.bbox = (int(x.min()), int(y.min()), int(x.max()), int(y.max())) if len(sel) else None
        self.origin = origin
        if not len(sel):
            return
        self.w = (self.bbox[2] - origin[0]) // SPAN * SPAN + SPAN + atlas.margin + 1
        self.h = (self.bbox[3] - origin[1]) // SPAN * SPAN + SPAN + atlas.margin + 1
        if self.w * self.h > MAX_RASTER:
            raise TileError('floor %d spans %d x %d game tiles: a stray tile far from the rest? (--floors leaves a floor out)' % (z, self.w, self.h))
        self.have = np.zeros((self.h, self.w), bool)
        self.layers = {k: np.zeros((self.h, self.w), np.uint16) for k in ('ground', 'border', 'decor', 'solid')}
        xi, yi = x - origin[0], y - origin[1]
        self.have[yi, xi] = True
        for k, arr in self.layers.items():
            arr[yi, xi] = rec[k][sel]
        self.tiles = sorted({(int(a) // SPAN, int(b) // SPAN) for a, b in zip(xi, yi)})


# ------------------------------------------------------------------------------------------------ drawing
def over(dst, src, region, boost=False):
    """src RGBA pixels laid over dst (RGBA, the tile) in `region` (y0, x0 of dst), on the pixels that are seen (alpha > 0) only"""
    y0, x0 = region
    h, w = src.shape[:2]
    ya, xa = max(0, y0), max(0, x0)
    yb, xb = min(dst.shape[0], y0 + h), min(dst.shape[1], x0 + w)
    if ya >= yb or xa >= xb:
        return
    s = src[ya - y0:yb - y0, xa - x0:xb - x0].astype(np.int32)
    d = dst[ya:yb, xa:xb]
    a = s[..., 3]
    if boost:
        a = np.where(a == 255, 255, np.minimum(255, (a * int(BOOST * 256)) >> 8))
    a = np.where(d[..., 3] > 0, a, 0)[..., None]
    d[..., :3] = ((d[..., :3].astype(np.int32) * (255 - a) + s[..., :3] * a + 127) // 255).astype(np.uint8)


def draw_tile(floor, atlas, tx, ty):
    """the 256 x 256 RGBA picture of tile (tx, ty) of the top zoom, or None when no game tile of it exists"""
    x0, y0 = tx * SPAN, ty * SPAN
    m = atlas.margin
    have = floor.have[y0:y0 + SPAN, x0:x0 + SPAN]
    if not have.any():
        return None
    img = np.zeros((TILE, TILE, 4), np.uint8)
    seen = np.repeat(np.repeat(have, CELL, 0), CELL, 1)
    img[seen] = (FLAT[0], FLAT[1], FLAT[2], 255)
    for name in ('ground', 'border', 'decor', 'solid'):
        boost = name == 'solid'
        region = floor.layers[name][y0:y0 + SPAN + m, x0:x0 + SPAN + m]
        ids = region[:SPAN, :SPAN]
        if ids.any():
            rows = atlas.index[ids]
            layer = atlas.small[rows].transpose(0, 2, 1, 3, 4).reshape(TILE, TILE, 4)
            over(img, layer, (0, 0), boost)
        if atlas.big:
            bm = atlas.bigmask[region]
            for ry, rx in np.argwhere(bm):
                w, h, pix = atlas.big[int(region[ry, rx])]
                over(img, pix, ((ry + 1) * CELL - h * CELL, (rx + 1) * CELL - w * CELL), boost)
    return img


def reduce2(img):
    """a picture of 2 x 2 tiles (512 x 512) halved to one tile, the colours weighted by alpha (no dark fringe at the edge of the explored area)"""
    f = img.astype(np.float32)
    a = f[..., 3:4] / 255.0
    pm = f[..., :3] * a

    def pool(v):
        return v.reshape(TILE, 2, TILE, 2, v.shape[-1]).sum(axis=(1, 3))
    sa, spm = pool(a), pool(pm)
    rgb = np.where(sa > 0, spm / np.maximum(sa, 1e-6), 0)
    out = np.zeros((TILE, TILE, 4), np.uint8)
    out[..., :3] = np.clip(rgb + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(sa[..., 0] / 4.0 * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return out


def save_png(path, arr, colours):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = Image.fromarray(arr, 'RGBA')
    if colours:
        im = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE)
    im.save(path, optimize=True)


def load_png(path):
    with Image.open(path) as im:
        return np.asarray(im.convert('RGBA')).copy()


# ------------------------------------------------------------------------------------------------ tile maths (the contract of the staff page's script)
def to_latlng(meta, x, y):
    """the Leaflet simple-CRS point of the centre of game tile (x, y): lng east, lat negative towards the south"""
    ox, oy = meta['origin']
    return (-(y + 0.5 - oy) / meta['span0'], (x + 0.5 - ox) / meta['span0'])


def tile_of(meta, x, y, zoom):
    """(tx, ty, px, py): the tile at `zoom` that holds game tile (x, y) and the pixel in it where the tile's top left corner is"""
    ox, oy = meta['origin']
    span = meta['span0'] // 2 ** zoom
    per = TILE / span
    return ((x - ox) // span, (y - oy) // span, int(((x - ox) % span) * per), int(((y - oy) % span) * per))


# ------------------------------------------------------------------------------------------------ the build
MAX_RASTER = 160_000_000     # cells (w * h) of one floor's raster: a box this big is a map with a stray tile far away


def build(m, db, atlas, out, levels=5, floors=None, quantise=True, dry=False, log=print, towns=None):
    """draw the pyramid into `out`; -> the meta dict of meta.json"""
    if levels < 1 or levels > 8:
        raise TileError('--levels 1 to 8')
    top = levels - 1
    t = m.tiles
    if not len(t['x']):
        raise TileError('the map has no tiles')
    zs = sorted({int(v) for v in np.unique(t['z'])})
    if floors is not None:
        zs = [z for z in zs if z in floors]
    if not zs:
        raise TileError('no tiles on the floors asked for')
    keep = np.isin(t['z'], zs)
    origin = (int(t['x'][keep].min()) // SPAN * SPAN, int(t['y'][keep].min()) // SPAN * SPAN)
    bbox = (int(t['x'][keep].min()), int(t['y'][keep].min()), int(t['x'][keep].max()), int(t['y'][keep].max()))
    if not dry and os.path.isdir(out) and os.listdir(out):
        raise TileError('%s is not empty: give a new folder' % out)
    role, cid = roles_of(db)
    rec = recipes(m, role, cid)
    meta = {'v': VERSION, 'tile': TILE, 'minZoom': 0, 'maxZoom': top, 'cell': CELL, 'origin': list(origin), 'span0': SPAN * 2 ** top,
            'bbox': list(bbox), 'floors': [], 'towns': towns if towns is not None else [], 'built': int(time.time())}
    total = 0
    for z in zs:
        fl = Floor(m, rec, z, origin, atlas)
        tops = fl.tiles
        n_all = sum(len({(a >> k, b >> k) for a, b in tops}) for k in range(levels))
        total += n_all
        meta['floors'].append({'z': z, 'tiles': n_all, 'bbox': list(fl.bbox)})
        log('floor %d: %d game tiles, %d map tiles in %d zooms' % (z, fl.count, n_all, levels))
        if dry:
            continue
        cur = []
        for tx, ty in tops:
            img = draw_tile(fl, atlas, tx, ty)
            if img is not None:
                save_png(os.path.join(out, str(z), str(top), str(tx), '%d.png' % ty), img, quantise)
                cur.append((tx, ty))
        for zoom in range(top - 1, -1, -1):
            parents = sorted({(a >> 1, b >> 1) for a, b in cur})
            for px, py in parents:
                canvas = np.zeros((TILE * 2, TILE * 2, 4), np.uint8)
                for dx in (0, 1):
                    for dy in (0, 1):
                        path = os.path.join(out, str(z), str(zoom + 1), str(px * 2 + dx), '%d.png' % (py * 2 + dy))
                        if os.path.exists(path):
                            canvas[dy * TILE:(dy + 1) * TILE, dx * TILE:(dx + 1) * TILE] = load_png(path)
                save_png(os.path.join(out, str(z), str(zoom), str(px), '%d.png' % py), reduce2(canvas), quantise)
            cur = parents
    meta['estimate_mb'] = round(total * EST_BYTES[quantise] / 1e6, 3)
    if not dry:
        os.makedirs(out, exist_ok=True)
        write_json(os.path.join(out, 'meta.json'), meta)
    return meta


def write_json(path, doc):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(doc, f, separators=(',', ':'), ensure_ascii=True)
        f.write('\n')
    os.replace(tmp, path)
    os.chmod(path, 0o644)


def towns_of(m):
    return [{'id': int(i), 'name': str(name), 'x': int(p[0]), 'y': int(p[1]), 'z': int(p[2])} for i, name, p in m.towns]


def parse(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('server', nargs='?', help='the installed server folder (data/world, data/items)')
    ap.add_argument('--map', help='a world map (.otbm or a cached .npz) instead of the server\'s')
    ap.add_argument('--items', help='a folder with items.otb and items.xml instead of the server\'s')
    ap.add_argument('--swatches', default=DEFAULT_SWATCHES)
    ap.add_argument('--out', required=True)
    ap.add_argument('--levels', type=int, default=5)
    ap.add_argument('--floors', help='comma separated floors (default: every floor the map uses)')
    ap.add_argument('--pointer', help='write meta + url here (the staff page reads it)')
    ap.add_argument('--url', default='', help='the folder\'s address under the site, for --pointer')
    ap.add_argument('--full-colour', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args(argv)
    if not a.server and not (a.map and a.items):
        ap.error('give SERVER_DIR, or --map and --items')
    if a.pointer and not re.match(r'^[A-Za-z0-9._/-]{1,200}$', a.url or ''):
        ap.error('--pointer needs --url NAME (letters, digits, . _ - /)')
    return a


def main(argv):
    a = parse(argv)
    try:
        import otbm
        from itemdb import ItemDB
        mp = a.map or find_map(a.server)
        items = a.items or os.path.join(a.server, 'data', 'items')
        floors = {int(v) for v in a.floors.split(',')} if a.floors else None
        atlas = Atlas(a.swatches)
        print('map %s' % mp, flush=True)
        m = otbm.load_cache(mp) if mp.endswith('.npz') else otbm.load_otbm(mp)
        db = ItemDB(os.path.join(items, 'items.otb'), os.path.join(items, 'items.xml'))
        meta = build(m, db, atlas, a.out, a.levels, floors, not a.full_colour, a.dry_run, lambda s: print(s, flush=True), towns_of(m))
    except (TileError, OSError) as e:
        print('gen_bot_map_tiles: %s' % e, file=sys.stderr)
        return 1
    print('%s: %d floors, about %.0f MB' % ('dry run' if a.dry_run else 'tiles written', len(meta['floors']), meta['estimate_mb']))
    if a.pointer and not a.dry_run:
        doc = dict(meta)
        doc['url'] = a.url
        write_json(a.pointer, doc)
        print('pointer %s' % a.pointer)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
