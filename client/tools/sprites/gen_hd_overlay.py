#!/usr/bin/env python3
"""HD sprite overlay: high resolution frames of a creature look -> per-sprite tiles, atlas and index (O539, base patch 0196).

The 32 px sprites of the pair and its .dat / .spr stay as they are. A look's HD frames (one picture per direction and
walk or idle frame, 2x or 4x of the look's own size: a 2x2 look at 2x is 128 x 128 px) are cut into square tiles, one per
sprite id of that look, packed into atlas PNGs, and listed in an index that the client reads (g_sprites.loadHdOverlay,
client/overlay/modules/game_hdsprites, src/client/chaoshdoverlay.h). The client draws a tile in place of its sprite,
resampled to the rectangle one sprite has, so the creature keeps its size and shows finer detail.

  python3 -I client/tools/sprites/gen_hd_overlay.py build DAT SPR        # find the sprite ids in the pair, write tiles.csv, atlas, index
  python3 -I client/tools/sprites/gen_hd_overlay.py build --check        # rebuild from the frames and tiles.csv, compare (CI, no pair)
  python3 -I client/tools/sprites/gen_hd_overlay.py build --check DAT SPR  # and the tile rows against that pair (live pair)
  python3 -I client/tools/sprites/gen_hd_overlay.py preview DAT SPR OUT_DIR [--zoom 2]   # 1x sprite beside the HD overlay, as the client draws it

Inputs (client/tools/sprites/hd_overlay/):
  hd_looks.json          {"version": 1, "looks": [{"look": 3019, "name": "ghoul", "scale": 2, "groups": [0, 1],
                          "allow_foreign": []}]}   look = the dat outfit id, groups = the dat frame groups drawn
  art/<name>/g<G>_<direction>_<NN>.png   direction north | east | south | west (the dat's pattern x 0..3), NN = 00.. frames
                          of that group; the picture is (w * 32 * scale) x (h * 32 * scale), RGBA, anchored like the look.
                          Fewer frames than the group has phases: phase p shows frame (p * k) // n (n phases, k frames).
                          One direction only (a look with pattern x 1): the files are named south.
Outputs: hd_tiles.csv (next to hd_looks.json), client/overlay/data/hd/index.txt and hd_<scale>x_<n>.png.

A sprite id has one tile, and a pair shares identical sprites between phases and between things and leaves tiles of a look
empty (sprite 0), so every place of a look (group, phase, direction, tile) gets a status:
  * used      the first place of a sprite no other thing draws: a `sprite` record of the index (id -> tile);
  * same      another place of that sprite that cuts the very same tile: covered by the `sprite` record;
  * conflict  another place of that sprite that cuts a different tile (the pair drew two phases alike, the HD art does not);
  * foreign   a sprite another thing of the dat draws too (another look, an item, an effect): a `sprite` record would change
              that thing too (the look's "allow_foreign" list makes it a `sprite` record anyway);
  * zero      a place with no sprite: the pair's art leaves that tile empty, so no sprite id can carry the HD picture;
  * empty     a place whose sprite record holds no pixel.
conflict, foreign, zero and empty places whose HD tile has a pixel become `slot` records, which name the place itself (thing,
index into its sprite list, the sprite id the pair has there). The client draws a slot before the sprite id of that place.
The index keeps the crc32 of the pair's 32x32 RGBA bytes of each `sprite` (transparent pixels as 0) and the pair's sprite id
of each `slot`, so a later pair that moves things around hides the tile on its own.
"""
import argparse
import csv
import hashlib
import json
import os
import sys
import zlib

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SPEC_DIR = os.path.join(HERE, 'hd_overlay')
SPEC = os.path.join(SPEC_DIR, 'hd_looks.json')
TILES_CSV = os.path.join(SPEC_DIR, 'hd_tiles.csv')
ART_DIR = os.path.join(SPEC_DIR, 'art')
OUT_DIR = os.path.join(ROOT, 'client', 'overlay', 'data', 'hd')

DIRS = ('north', 'east', 'south', 'west')
BASE = 32
ATLAS_SIZE = 2048
MAX_SCALE = 8
CSV_HEAD = ['look', 'group', 'direction', 'phase', 'ww', 'hh', 'index', 'sid', 'crc', 'status']
SLOT_STATUSES = ('conflict', 'foreign', 'zero', 'empty')
CATEGORY_CREATURE = 1
INDEX_HEAD = 'chaos-hd-overlay 1'


class HdError(Exception):
    pass


# ---------------------------------------------------------------- pair side
def sprite_crc(arr):
    """crc32 of a 32x32x4 RGBA sprite, the colour of a transparent pixel taken as 0 (the engine does the same)"""
    a = np.array(arr, dtype=np.uint8).reshape(-1, 4)
    a[a[:, 3] == 0] = 0
    return zlib.crc32(a.tobytes()) & 0xFFFFFFFF


def group_index(g, x, y, z, layer, phase, ww, hh):
    w, h, _ex, layers, px, py, pz = g[0], g[1], g[2], g[3], g[4], g[5], g[6]
    return ((((((phase * pz + z) * py + y) * px + x) * layers + layer) * h + hh) * w + ww)


def things_of(dat):
    for name in ('items', 'outfits', 'effects', 'missiles'):
        for t in getattr(dat, name, []):
            yield name[0] + str(t.id), t


def sprite_owners(dat):
    """sprite id -> set of 'o3019'-style keys of the things that draw it (every frame group)"""
    owners = {}
    for key, t in things_of(dat):
        for g in t.groups:
            for sid in set(g[8]):
                if sid:
                    owners.setdefault(sid, set()).add(key)
    return owners


def direction_names(px):
    if px == 1:
        return {0: 'south'}
    if px == 4:
        return {i: d for i, d in enumerate(DIRS)}
    raise HdError('a look with %d directions is not supported' % px)


def load_spec(path=SPEC):
    with open(path, encoding='utf-8') as f:
        spec = json.load(f)
    if spec.get('version') != 1:
        raise HdError('hd_looks.json: version must be 1')
    names = set()
    for lk in spec['looks']:
        for key in ('look', 'name', 'scale', 'groups'):
            if key not in lk:
                raise HdError('hd_looks.json: a look has no "%s"' % key)
        if not 1 <= lk['scale'] <= MAX_SCALE:
            raise HdError('%s: scale %s out of range' % (lk['name'], lk['scale']))
        if lk['name'] in names:
            raise HdError('%s: named twice' % lk['name'])
        names.add(lk['name'])
    return spec


def frame_dir(spec_look, art_dir=ART_DIR):
    return os.path.join(art_dir, spec_look['name'])


def frame_files(spec_look, group, direction, art_dir=ART_DIR):
    d = frame_dir(spec_look, art_dir)
    prefix = 'g%d_%s_' % (group, direction)
    if not os.path.isdir(d):
        return []
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.startswith(prefix) and f.endswith('.png'))


_frame_cache = {}


def load_frame(path):
    if path not in _frame_cache:
        with Image.open(path) as im:
            _frame_cache[path] = np.array(im.convert('RGBA'), dtype=np.uint8)
    return _frame_cache[path]


def pick_frame(files, phase, phases):
    return files[(phase * len(files)) // phases]


def frame_for(spec_look, group, direction, phase, phases, art_dir=ART_DIR):
    files = frame_files(spec_look, group, direction, art_dir)
    if not files:
        raise HdError('%s: no frames g%d_%s_NN.png' % (spec_look['name'], group, direction))
    return load_frame(pick_frame(files, phase, phases))


def cut_tile(frame, spec_look, thing, ww, hh):
    """the tile of a look frame at tile (ww, hh): the look is drawn with tile (0, 0) at the bottom right"""
    s = BASE * spec_look['scale']
    w, h = thing.groups[0][0], thing.groups[0][1]
    x0, y0 = (w - 1 - ww) * s, (h - 1 - hh) * s
    return np.ascontiguousarray(frame[y0:y0 + s, x0:x0 + s])


def plan_rows(spec, dat, spr, art_dir=ART_DIR):
    """The pair step: every (look, group, direction, phase, tile) with its place in the thing's sprite list, its sprite id,
    the crc and the status (see the module docstring)"""
    owners = sprite_owners(dat)
    rows = []
    taken = {}      # sid -> tile bytes of its first place
    for lk in spec['looks']:
        t = dat.outfit(lk['look'])
        if t is None:
            raise HdError('%s: the dat has no outfit %d' % (lk['name'], lk['look']))
        key = 'o%d' % t.id
        allow = set(lk.get('allow_foreign', []))
        s = BASE * lk['scale']
        offsets, total = [], 0
        for grp in t.groups:
            offsets.append(total)
            total += len(grp[8])
        for gi in lk['groups']:
            if gi >= len(t.groups):
                raise HdError('%s: look %d has no frame group %d' % (lk['name'], lk['look'], gi))
            grp = t.groups[gi]
            w, h, _ex, layers, px, py, pz, phases = grp[:8]
            if layers != 1:
                raise HdError('%s: look %d has %d layers (a colour mask look); only one layer looks are supported' % (lk['name'], lk['look'], layers))
            if (w, h) != (t.groups[0][0], t.groups[0][1]):
                raise HdError('%s: the frame groups differ in size' % lk['name'])
            for x, dname in direction_names(px).items():
                for phase in range(phases):
                    frame = frame_for(lk, gi, dname, phase, phases, art_dir)
                    if frame.shape[0] != h * s or frame.shape[1] != w * s:
                        raise HdError('%s g%d %s: frame is %dx%d, a %dx%d look at %dx is %dx%d' % (
                            lk['name'], gi, dname, frame.shape[1], frame.shape[0], w, h, lk['scale'], w * s, h * s))
                    for hh in range(h):
                        for ww in range(w):
                            gidx = group_index(grp, x, 0, 0, 0, phase, ww, hh)
                            idx = offsets[gi] + gidx
                            sid = grp[8][gidx]
                            tile = cut_tile(frame, lk, t, ww, hh)
                            if not sid:
                                status, crc = 'zero', 0
                            else:
                                pix = spr.sprite(sid)
                                if pix is None:
                                    status, crc = 'empty', 0
                                else:
                                    crc = sprite_crc(pix)
                                    if owners.get(sid, set()) - {key} and sid not in allow:
                                        status = 'foreign'
                                    elif sid in taken:
                                        status = 'same' if taken[sid] == tile.tobytes() else 'conflict'
                                    else:
                                        status = 'used'
                                        taken[sid] = tile.tobytes()
                            rows.append((lk['look'], gi, dname, phase, ww, hh, idx, sid, crc, status))
    return rows


def write_rows(rows, path=TILES_CSV):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(CSV_HEAD)
        for r in rows:
            w.writerow(list(r[:8]) + ['%08x' % r[8], r[9]])


def read_rows(path=TILES_CSV):
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        rd = csv.DictReader(f)
        if rd.fieldnames != CSV_HEAD:
            raise HdError('%s: header is not %s' % (path, ','.join(CSV_HEAD)))
        for r in rd:
            rows.append((int(r['look']), int(r['group']), r['direction'], int(r['phase']), int(r['ww']), int(r['hh']),
                         int(r['index']), int(r['sid']), int(r['crc'], 16), r['status']))
    return rows


# ---------------------------------------------------------------- atlas and index (no pair)
class FakeThing:
    """what cut_tile needs of a thing when no dat is read: the look's size in tiles"""
    def __init__(self, w, h):
        self.groups = [(w, h)]


def look_sizes_from_rows(rows):
    sizes = {}
    for r in rows:
        look, ww, hh = r[0], r[4], r[5]
        w, h = sizes.get(look, (1, 1))
        sizes[look] = (max(w, ww + 1), max(h, hh + 1))
    return sizes


def build_outputs(spec, rows, art_dir=ART_DIR, sizes=None, thing_of_look=None):
    """atlas pictures and index text from the rows and the frames. Returns (index_text, {atlas name: RGBA array}).
    The look's size in tiles comes from thing_of_look(look) (a pair is read) or else from the rows (the largest tile
    index seen: the rows hold every place, empty ones included, so it is the look's size)."""
    by_look = {lk['look']: lk for lk in spec['looks']}
    sizes = sizes or look_sizes_from_rows(rows)
    items = []            # ('sprite', sid, crc, scale, tile) | ('slot', look, index, sid, scale, tile)
    phase_count = {}
    for r in rows:
        phase_count[(r[0], r[1])] = max(phase_count.get((r[0], r[1]), 0), r[3] + 1)
    for r in rows:
        look, gi, dname, phase, ww, hh, idx, sid, crc, status = r
        if status not in ('used',) + SLOT_STATUSES:
            continue
        lk = by_look[look]
        t = thing_of_look(look) if thing_of_look else FakeThing(*sizes[look])
        frame = frame_for(lk, gi, dname, phase, phase_count[(look, gi)], art_dir)
        tile = cut_tile(frame, lk, t, ww, hh)
        if status == 'used':
            items.append(('sprite', sid, crc, lk['scale'], tile))
        elif tile[:, :, 3].any():
            items.append(('slot', look, idx, sid, lk['scale'], tile))
    # pack: one atlas series per scale, identical tiles once
    atlases = {}
    atlas_names = []
    placed = {}           # (scale, sha1) -> (atlas index, x, y)
    cursor = {}           # scale -> [atlas name, x, y, count]
    sprite_lines, slot_lines = [], []

    def place_tile(scale, tile):
        cell = BASE * scale
        key = (scale, hashlib.sha1(tile.tobytes()).hexdigest())
        if key not in placed:
            cols = ATLAS_SIZE // cell
            cur = cursor.get(scale)
            if cur is None or cur[2] >= cols * cols:
                name = 'hd_%dx_%d.png' % (scale, sum(1 for n in atlas_names if n.startswith('hd_%dx_' % scale)))
                atlas_names.append(name)
                atlases[name] = [np.zeros((ATLAS_SIZE, ATLAS_SIZE, 4), np.uint8), 0]
                cur = cursor[scale] = [name, 0, 0]
            name, n = cur[0], cur[2]
            x, y = (n % cols) * cell, (n // cols) * cell
            atlases[name][0][y:y + cell, x:x + cell] = tile
            atlases[name][1] = max(atlases[name][1], y + cell)
            cur[2] += 1
            placed[key] = (atlas_names.index(name), x, y)
        return placed[key]

    for it in sorted(items, key=lambda i: (0, i[1]) if i[0] == 'sprite' else (1, i[1], i[2])):
        if it[0] == 'sprite':
            _k, sid, crc, scale, tile = it
            a, x, y = place_tile(scale, tile)
            sprite_lines.append('sprite %d %d %d %d %d %08x' % (sid, a, x, y, scale, crc))
        else:
            _k, look, idx, sid, scale, tile = it
            a, x, y = place_tile(scale, tile)
            slot_lines.append('slot %d %d %d %d %d %d %d %d' % (CATEGORY_CREATURE, look, idx, sid, a, x, y, scale))
    lines = [INDEX_HEAD, '# made by client/tools/sprites/gen_hd_overlay.py; do not edit']
    lines += ['atlas %d %s' % (i, n) for i, n in enumerate(atlas_names)]
    lines += sprite_lines + slot_lines
    # an atlas is cut to the rows it uses
    pics = {n: v[0][:max(v[1], BASE)] for n, v in atlases.items()}
    return '\n'.join(lines) + '\n', pics


def write_outputs(index_text, pics, out_dir=OUT_DIR):
    os.makedirs(out_dir, exist_ok=True)
    keep = {'index.txt'} | set(pics)
    for f in os.listdir(out_dir):
        if f.startswith('hd_') and f.endswith('.png') and f not in keep:
            os.remove(os.path.join(out_dir, f))
    for n, arr in pics.items():
        Image.fromarray(arr, 'RGBA').save(os.path.join(out_dir, n), optimize=True)
    with open(os.path.join(out_dir, 'index.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(index_text)


def compare_outputs(index_text, pics, out_dir=OUT_DIR):
    """list of differences between what the frames and rows build and what is committed"""
    bad = []
    p = os.path.join(out_dir, 'index.txt')
    if not os.path.isfile(p):
        return ['%s is missing' % p]
    with open(p, encoding='utf-8', newline='') as f:
        if f.read() != index_text:
            bad.append('index.txt differs from a rebuild')
    have = sorted(f for f in os.listdir(out_dir) if f.startswith('hd_') and f.endswith('.png'))
    if have != sorted(pics):
        bad.append('atlas files %s, a rebuild makes %s' % (have, sorted(pics)))
    for n, arr in pics.items():
        q = os.path.join(out_dir, n)
        if not os.path.isfile(q):
            continue
        with Image.open(q) as im:
            got = np.array(im.convert('RGBA'), dtype=np.uint8)
        if got.shape != arr.shape or not np.array_equal(got, arr):
            bad.append('%s differs from a rebuild' % n)
    return bad


def check_rows_against_pair(spec, rows, dat, spr, art_dir=ART_DIR):
    """the live pair check: every row names the sprite the pair has there, with the crc it had"""
    fresh = plan_rows(spec, dat, spr, art_dir)
    if fresh == rows:
        return []
    bad = []
    if len(fresh) != len(rows):
        bad.append('the pair gives %d tile rows, hd_tiles.csv has %d' % (len(fresh), len(rows)))
    for a, b in zip(fresh, rows):
        if a != b:
            bad.append('row %s: the pair has %s' % (b, a))
            if len(bad) > 8:
                break
    return bad


# ---------------------------------------------------------------- the client's resample, for the preview
def resample(tile, dst):
    """RGBA square tile -> dst x dst the way chaoshdoverlay.h does: same size copy, smaller area mean with colour weighted by
    alpha, larger nearest"""
    src = tile.shape[0]
    if src == dst:
        return tile.copy()
    if dst > src:
        idx = (np.arange(dst) * src) // dst
        return tile[idx][:, idx].copy()
    ratio = src / dst
    out = np.zeros((dst, dst, 4), np.uint8)
    f = tile.astype(np.float64)
    a = f[:, :, 3]
    pm = f[:, :, :3] * a[:, :, None]
    # exact fractional weights along each axis
    def weights(n_dst):
        m = np.zeros((n_dst, src))
        for i in range(n_dst):
            lo, hi = i * ratio, (i + 1) * ratio
            for s in range(int(lo), min(src, int(np.ceil(hi)))):
                m[i, s] = min(s + 1, hi) - max(s, lo)
        return m
    wm = weights(dst)
    sum_a = wm @ a @ wm.T
    sum_c = [wm @ pm[:, :, c] @ wm.T for c in range(3)]
    area = ratio * ratio
    for c in range(3):
        with np.errstate(invalid='ignore', divide='ignore'):
            v = np.where(sum_a > 0, sum_c[c] / sum_a, 0)
        out[:, :, c] = np.clip(v + 0.5, 0, 255).astype(np.uint8)
    out[:, :, 3] = np.clip(sum_a / area + 0.5, 0, 255).astype(np.uint8)
    out[out[:, :, 3] == 0] = 0
    return out


def parse_index(text):
    """(atlas names, {sprite id: (atlas, x, y, scale, crc)}, {(category, thing, index): (sprite id, atlas, x, y, scale)})"""
    atlases, sprites, slots = [], {}, {}
    for n, line in enumerate(text.splitlines(), 1):
        if not line or line.startswith('#'):
            continue
        w = line.split()
        if not atlases and not sprites and not slots and w[0] == 'chaos-hd-overlay':
            if w != ['chaos-hd-overlay', '1']:
                raise HdError('index.txt line %d: not a chaos-hd-overlay 1 file' % n)
        elif w[0] == 'atlas':
            atlases.append(w[2])
        elif w[0] == 'sprite':
            sprites[int(w[1])] = (int(w[2]), int(w[3]), int(w[4]), int(w[5]), int(w[6], 16))
        elif w[0] == 'slot':
            slots[(int(w[1]), int(w[2]), int(w[3]))] = (int(w[4]), int(w[5]), int(w[6]), int(w[7]), int(w[8]))
        else:
            raise HdError('index.txt line %d: unknown record' % n)
    return atlases, sprites, slots


def load_overlay(out_dir=OUT_DIR):
    """(atlas names, sprites, slots, {atlas name: RGBA array})"""
    with open(os.path.join(out_dir, 'index.txt'), encoding='utf-8') as f:
        atlases, sprites, slots = parse_index(f.read())
    pics = {}
    for n in atlases:
        with Image.open(os.path.join(out_dir, n)) as im:
            pics[n] = np.array(im.convert('RGBA'), dtype=np.uint8)
    return atlases, sprites, slots, pics


def overlay_tile(overlay, sid, pix, size, thing_id=None, index=None):
    """the picture the client draws for a place at size px, or None (plain sprite). A slot of the place wins; else the
    tile of the sprite id, unless its crc says the pair's sprite is another picture."""
    atlases, sprites, slots, pics = overlay
    slot = slots.get((CATEGORY_CREATURE, thing_id, index)) if thing_id is not None else None
    if slot is not None and slot[0] == sid:
        _s, a, x, y, scale = slot
        cell = BASE * scale
        return resample(pics[atlases[a]][y:y + cell, x:x + cell], size)
    e = sprites.get(sid)
    if e is None:
        return None
    a, x, y, scale, crc = e
    if crc and pix is not None and sprite_crc(pix) != crc:
        return None
    cell = BASE * scale
    return resample(pics[atlases[a]][y:y + cell, x:x + cell], size)


def compose(thing, spr, group, direction, phase, size, overlay=None):
    """one frame of a look: with the overlay, the tiles the client would draw at `size` px a tile; without, the plain
    sprites repeated to that size (nearest). Returns RGBA array (h * size, w * size, 4)."""
    g_ = thing.groups[group]
    w, h, px = g_[0], g_[1], g_[4]
    x = {v: k for k, v in direction_names(px).items()}[direction]
    offset = sum(len(grp[8]) for grp in thing.groups[:group])
    out = np.zeros((h * size, w * size, 4), np.uint8)
    for hh in range(h):
        for ww in range(w):
            gidx = group_index(g_, x, 0, 0, 0, phase, ww, hh)
            sid = g_[8][gidx]
            pix = spr.sprite(sid) if sid else None
            tile = overlay_tile(overlay, sid, pix, size, thing.id, offset + gidx) if overlay else None
            if tile is None:
                if pix is None:
                    continue
                k = size // BASE
                tile = np.repeat(np.repeat(np.array(pix, dtype=np.uint8), k, axis=0), k, axis=1) if size % BASE == 0 else resample(np.array(pix, dtype=np.uint8), size)
            y0, x0 = (h - 1 - hh) * size, (w - 1 - ww) * size
            out[y0:y0 + size, x0:x0 + size] = tile
    return out


def side_by_side(left, right, bg=(46, 42, 52, 255), gap=8):
    h = max(left.shape[0], right.shape[0])
    panel = np.zeros((h, left.shape[1] + gap + right.shape[1], 4), np.uint8)
    panel[:] = bg
    for arr, x0 in ((left, 0), (right, left.shape[1] + gap)):
        a = arr[:, :, 3:4].astype(np.float64) / 255
        region = panel[:arr.shape[0], x0:x0 + arr.shape[1]]
        region[:, :, :3] = (arr[:, :, :3] * a + region[:, :, :3] * (1 - a)).astype(np.uint8)
    return panel


def preview(spec, dat, spr, out_dir, zoom=2, overlay=None):
    overlay = overlay or load_overlay()
    os.makedirs(out_dir, exist_ok=True)
    size = BASE * zoom
    made = []
    for lk in spec['looks']:
        t = dat.outfit(lk['look'])
        for gi in lk['groups']:
            g = t.groups[gi]
            for dname in direction_names(g[4]).values():
                for phase in range(g[7]):
                    left = compose(t, spr, gi, dname, phase, size, None)
                    right = compose(t, spr, gi, dname, phase, size, overlay)
                    p = os.path.join(out_dir, '%s_g%d_%s_%02d_%dx.png' % (lk['name'], gi, dname, phase, zoom))
                    Image.fromarray(side_by_side(left, right), 'RGBA').save(p)
                    made.append(p)
    return made


# ---------------------------------------------------------------- command line
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--check', action='store_true')
    b.add_argument('pair', nargs='*', help='DAT SPR')
    p = sub.add_parser('preview')
    p.add_argument('pair', nargs=3, help='DAT SPR OUT_DIR')
    p.add_argument('--zoom', type=int, default=2)
    a = ap.parse_args(argv)
    spec = load_spec()
    if a.cmd == 'build':
        if len(a.pair) not in (0, 2):
            ap.error('give DAT and SPR, or neither')
        dat = spr = None
        if a.pair:
            sys.path.insert(0, HERE)
            from datspr import Dat, Spr
            dat, spr = Dat(a.pair[0]), Spr(a.pair[1])
        if not a.check:
            if not dat:
                ap.error('build needs DAT SPR (build --check does not)')
            rows = plan_rows(spec, dat, spr)
            write_rows(rows)
            text, pics = build_outputs(spec, rows, thing_of_look=dat.outfit)
            write_outputs(text, pics)
            counts = {}
            for r in rows:
                counts[r[9]] = counts.get(r[9], 0) + 1
            print('hd overlay: %d tile rows %s, %d sprites, %d slots, %d atlas files' % (
                len(rows), counts, text.count('\nsprite '), text.count('\nslot '), len(pics)))
            return 0
        rows = read_rows()
        thing_of = dat.outfit if dat else None
        text, pics = build_outputs(spec, rows, thing_of_look=thing_of)
        bad = compare_outputs(text, pics)
        if dat:
            bad += check_rows_against_pair(spec, rows, dat, spr)
        for m in bad:
            print('FAIL', m)
        if bad:
            print('run: python3 -I client/tools/sprites/gen_hd_overlay.py build DAT SPR')
            return 1
        print('gen_hd_overlay --check: %d rows, %d sprites, %d slots, %d atlas files up to date%s' % (
            len(rows), text.count('\nsprite '), text.count('\nslot '), len(pics), ', matches the pair' if dat else ''))
        return 0
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    made = preview(spec, Dat(a.pair[0]), Spr(a.pair[1]), a.pair[2], a.zoom)
    print('preview: %d pictures in %s' % (len(made), a.pair[2]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
