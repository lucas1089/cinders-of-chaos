#!/usr/bin/env python3
"""Pair 33 (planned, not built): four purchased packs of one vendor cut into importer sheets. Internal labels
`set33 heads` (100 head accessories), `set33 capes` (100 capes), `set33 wings` (100 wings) and `set33 kit` (a harvest
farmland and catacomb tile kit: 514 items, 10 creature looks, a boss corpse). Pack names, vendor and licence:
docs/CREDITS.md (internal part). The owner's Drive folder "ots", uploaded 2026-10-21 (`PACKS`: Drive id, zip size,
zip sha256).

    python3 -I gen_pack33.py scan  --src SRC              # write art_import/pack33_<slug>.files (used files, md5)
    python3 -I gen_pack33.py build --src SRC              # cut -> art_import/pack33_<slug>/ (ignored by git) and
                                                          #   pack33_<slug>.csv, .sums, pack33_<slug>_sources.csv
    python3 -I gen_pack33.py build --src SRC --check      # rebuild in memory, compare every committed file
    python3 -I gen_pack33.py build --check                # CI, no sources: the committed tables agree with each other
    python3 -I gen_pack33.py stats --src SRC              # sprite counts (unique 32 px tiles) and geometry facts
    python3 -I gen_pack33.py contact --src SRC --out DIR  # owner review sheets of the cut art (PNG, never committed)
    python3 -I gen_pack33.py preview --dat T/Tibia.dat --spr T/Tibia.spr --out DIR
                                                          # owner review from a TEST pair: wings, heads and capes on
                                                          #   look 128 as the client draws them, kit looks and items

SRC holds one folder per pack slug (heads, capes, wings, kit), each the unpacked zip (untrusted: unpack with a
path-checking extractor into empty folders; every file is md5-checked against pack33_<slug>.files before decoding).
Python: numpy and Pillow (CI uses the fx venv). Run with -I.

Import-only (like the set30 packs, docs/SPRITE_STYLE.md "Reference art"): the four licences forbid machine-learning
use and sharing the assets, even modified. Nothing here views, style-measures or samples a palette from a pack image,
and `style_check.py` is not run on them. Allowed: names, sizes, md5, the packs' metadata / catalogue (geometry facts:
frame size, anchor tile, frame count, fps, footprint), alpha boxes and the mean colour for the minimap. The contact
sheets are for the owner's eyes only (scratchpad, never committed, never given to an AI tool).

Ids (pair 32: 38,092 items, 2,384 outfits): outfits from FIRST_OUTFIT in the order wings, heads, capes, kit looks
(each sorted by the pack's id); items from FIRST_ITEM (kit items in catalogue order, then the boss corpse). Server id
= client id + 3000. Adding or removing a thing moves every later id; COUNTS stops the build.

Wings, heads and capes (pack sheets: one row per direction E, SE, S, SW, W, NW, N, NE; one column per frame; frame
`frame_w` x `frame_h`; `anchor_tile` = the wearer's tile inside the frame):
- the dat's four directions are the rows N, E, S, W (6, 0, 2, 4); the diagonal rows are not used;
- wings: one layer, the combined sheet (`all`); the client draws wings behind the body facing south / east and in
  front facing north / west, and lifts the body 6 px itself (GameWingOffset), so the pack's per-frame lift is not used;
- heads and capes: aura things with two layers, the pack's `back` sheet (layer 0, drawn behind the body) and its
  `front` sheet (layer 1, drawn over it) (client base patch 0006 GameAuraFrontAndBack, compose_outfit.py role aura);
- one frame group of `frames` phases at 1000 / fps ms (12 fps: 83 ms), animateAlways;
- the frame is trimmed to the union alpha box of every used frame, direction and layer (alpha < 12 cleared): the
  canvas is the fewest whole tiles from the box's left / top to its right / bottom edge, and the anchor tile's
  bottom-right corner keeps its place against the box (no pixel moves relative to another);
- displacement: the wearer's tile is where the pack's anchor tile is, with the body as our player looks draw it
  (BODY_REF = 8, 8 like the stock player look); content right of / below the anchor tile (r, b px) is reached with a
  negative share: D = BODY_REF - (r, b); an aura is also moved back by the client's centring of big auras,
  (w - 1) * 16, (h - 1) * 16 (GameBigAurasCenter). To check on a test pair with `fix_pair_warnings.py
  --scan-wings-displacement` / `--scan-aura-displacement` and the owner's preview on look 128 (not verified yet).

Kit (catalog.json: one PNG per sprite, `footprint_bottom_right` anchor = the dat's bottom-right anchor):
- items: every sprite but the figures, the per-floor parts (`part_of`: the dat draws a tall thing whole, up and left)
  and a static first frame whose `<id>_strip` exists; animated sprites (`strip`) get their frames as phases,
  `frame_ms` (default 125) and animateAlways; kind and flags from KIT_KINDS (a draft for the owner: walls and big props
  block, decals / open doors / floor changes do not; floor changes, doors and the event mechanics' state changes are
  server work); `light:3:206` on glowing sprites (`emissive`, candles, lanterns);
- looks: each figure set is one outfit, idle (4 phases) and walk (4 phases; the raven's hop) in the four directions,
  one layer, no colour mask; attack, cast and death strips are not used (a 10.98 outfit has idle and walking only);
- the boss's last death frame facing south is a corpse item.
"""
import argparse
import csv
import hashlib
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack30lib as L  # noqa: E402  (shared helpers: tables, md5 checks, alpha boxes; read only)

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')

FIRST_OUTFIT = 2385
FIRST_ITEM = 38093
SERVER_OFFSET = 3000
BODY_REF = 8
ALPHA_MIN = 12
DIRS = ('N', 'E', 'S', 'W')                       # dat order
ROW_OF = {'E': 0, 'SE': 1, 'S': 2, 'SW': 3, 'W': 4, 'NW': 5, 'N': 6, 'NE': 7}
KIT_DIRS = ('n', 'e', 's', 'w')
LICENCE = ('purchased; use in games incl. commercial, modified or not; no attribution needed (credit appreciated); '
           'no resale, redistribution or sharing of the assets, even modified (they ship only inside the compiled '
           'game); never machine-learning training data or a style reference; vendor: docs/CREDITS.md')

# slug -> label, kind, Drive file id, zip bytes, zip sha256 (the owner's upload of 2026-10-21)
PACKS = {
    'wings': dict(label='set33 wings', kind='wings', drive='1t0a4zq6UKEFcK1cY789jXrmianKjdT81', size=33336823,
                  sha256='8e42513e7807e47f84bc18a443d8eb2060675a6c40cd4ee674ca5d42e75e3eed'),
    'heads': dict(label='set33 heads', kind='aura', drive='11ooHL-N2XGkj1jWjSim7GTTLzB32rG2m', size=6511764,
                  sha256='7f3cad05388b5b732fef71c4f0b9744eb9d004f81b3f91f23c7ddf4e4c039f06'),
    'capes': dict(label='set33 capes', kind='aura', drive='1ONelgJiBanh2ZO7wXjpd3c84TfxVXuNi', size=13766017,
                  sha256='76caa2c85191e033d71b65a807dc882d0371af231677a8faf91f57ff55e66ac8'),
    'kit': dict(label='set33 kit', kind='kit', drive='1nMX1FUOxMDBBTKIAUhIVvx1hV0srnhs_', size=26222103,
                sha256='9349aace80929786ac31d10d7ea69c449c41187f62d1b9a7c3f3fe708405eae3'),
}
ORDER = ('wings', 'heads', 'capes', 'kit')
# things per pack: (outfits, items); the build stops when a pack has another count (every later id would move)
COUNTS = {'wings': (100, 0), 'heads': (100, 0), 'capes': (100, 0), 'kit': (10, 515)}

HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']
SOURCES_HEADER = ['name', 'kind', 'pack', 'source', 'licence']

BLOCK = 'bottom notwalkable notmoveable'
OPEN = 'notmoveable'
# kit (category, kind) -> (importer kind, flags); ids matched by OPEN_IDS / WALK_IDS override to walkable decor
KIT_KINDS = {
    ('tiles', 'ground'): ('ground', 'ground:100 notmoveable fullground'),
    ('borders', 'border'): ('border', 'clip notmoveable'),
    ('decals', 'decal'): ('border', 'clip notmoveable'),
    ('roofs', 'roof'): ('decor', OPEN), ('roofs', 'tower_roof'): ('decor', OPEN),
    ('floorchanges', 'floor_change'): ('decor', OPEN),
    ('decor', 'decor'): ('wall', 'hangable notmoveable'), ('decor', 'decor_anim'): ('wall', 'hangable notmoveable'),
    ('decor', 'wall'): ('wall', 'hangable notmoveable'), ('decor', 'prop'): ('stump', BLOCK),
    ('mechanics', 'prop'): ('stump', BLOCK), ('mechanics', 'stairs_down'): ('decor', OPEN),
    ('nature', 'corn'): ('stump', BLOCK), ('nature', 'corn_tall'): ('stump', BLOCK),
    ('nature', 'pumpkin'): ('stump', BLOCK), ('nature', 'jack_lantern'): ('stump', BLOCK),
    ('nature', 'tree'): ('stump', BLOCK),
}
WALK_IDS = re.compile(r'(^|_)(open|gap)(_|$)|^circle_|^portal_|^pumpkin_stage_[123]_|^grave_(mound|dug)$|'
                      r'^(candle_wax|bones_small|straw_scatter|leaves_|fog_patch|puddle)|^witch_hat$|^bats_flock$|'
                      r'^crows_ground$|^cobweb_sheet$|^candles_cluster$|^candle_skull$|^pumpkin_small$')
LIGHT = 'light:3:206'
LIGHT_KINDS = ('light', 'jack_lantern')


class BuildError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ files
def files_path(slug):
    return os.path.join(ART, 'pack33_%s.files' % slug)


def src_path(src, slug, rel):
    parts = rel.split('/')
    if rel.startswith('/') or '..' in parts or '\\' in rel or not rel:
        raise BuildError('%s/%s: unsafe path' % (slug, rel))
    return os.path.join(src, slug, *parts)


class Source:
    """md5-checked reads of one pack (the committed .files list), or a fresh scan (`scan`)."""

    def __init__(self, src, slug, scanning=False):
        self.src, self.slug, self.scanning = src, slug, scanning
        self.used = {}
        self.listed = {} if scanning else {r.path: r for r in L.read_files(files_path(slug))}

    def _row(self, rel):
        p = src_path(self.src, self.slug, rel)
        if not os.path.isfile(p):
            raise BuildError('%s/%s: missing' % (self.slug, rel))
        if self.scanning:
            w = h = ''
            if rel.endswith('.png'):
                w, h = L.png_size(p)
            r = L.FileRow(self.slug, rel, str(os.path.getsize(p)), L.file_md5(p), str(w), str(h))
        else:
            r = self.listed.get(rel)
            if r is None:
                raise BuildError('%s/%s: not in %s (run scan after checking the new file)' %
                                 (self.slug, rel, os.path.basename(files_path(self.slug))))
        self.used[rel] = r
        return p, r

    def json(self, rel):
        p, r = self._row(rel)
        data = open(p, 'rb').read()
        if not self.scanning and hashlib.md5(data).hexdigest() != r.md5:
            raise BuildError('%s/%s: md5 differs from the list' % (self.slug, rel))
        return json.loads(data.decode('utf-8'))

    def text(self, rel):
        p, r = self._row(rel)
        data = open(p, 'rb').read()
        if not self.scanning and hashlib.md5(data).hexdigest() != r.md5:
            raise BuildError('%s/%s: md5 differs from the list' % (self.slug, rel))
        return data.decode('utf-8')

    def png(self, rel):
        p, r = self._row(rel)
        return L.clean_alpha(L.load_verified(p, r.md5), ALPHA_MIN)

    def files_text(self):
        return L.files_text(list(self.used.values()))


# ------------------------------------------------------------------------------------------------ geometry
def trim_plan(box, ax, ay):
    """box (x0, y0, x1, y1) in frame px, anchor tile (ax, ay) -> (tw, th, R, B, r, b): the canvas in tiles, the frame
    point that lands on the canvas's bottom-right corner, and the px reached right of / below the anchor tile."""
    px, py = (ax + 1) * 32, (ay + 1) * 32
    r, b = max(0, box[2] - px), max(0, box[3] - py)
    R, B = px + r, py + b
    tw = max(1, int(math.ceil((R - min(box[0], px - 32)) / 32.0)))
    th = max(1, int(math.ceil((B - min(box[1], py - 32)) / 32.0)))
    return tw, th, R, B, r, b


def place(cell, tw, th, R, B):
    """the part of `cell` left of R and above B, on a tw x th tile canvas with (R, B) at its bottom-right corner."""
    W, H = tw * 32, th * 32
    out = np.zeros((H, W, 4), np.uint8)
    x0, y0 = R - W, B - H
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(cell.shape[1], R), min(cell.shape[0], B)
    if sx1 > sx0 and sy1 > sy0:
        out[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = cell[sy0:sy1, sx0:sx1]
    return out


def displacement(kind, tw, th, r, b):
    dx, dy = BODY_REF - r, BODY_REF - b
    if kind == 'aura':
        dx += (tw - 1) * 16 if tw > 1 else 0
        dy += (th - 1) * 16 if th > 1 else 0
    return dx, dy


def frames_of_strip(a, fw, fh, n):
    if a.shape[0] != fh or a.shape[1] != fw * n:
        raise BuildError('strip %dx%d is not %d frames of %dx%d' % (a.shape[1], a.shape[0], n, fw, fh))
    return [a[:, i * fw:(i + 1) * fw] for i in range(n)]


def tiles_px(v, what):
    if v % 32:
        raise BuildError('%s: %d px is not whole tiles' % (what, v))
    return v // 32


# ------------------------------------------------------------------------------------------------ vfx packs
def elements(readme):
    """file id -> element (the `## Fire (12)` tables of the pack readme; classification only, no text copied)."""
    out, cur = {}, None
    for line in readme.split('\n'):
        m = re.match(r'^## ([A-Za-z]+) \(\d+\)\s*$', line)
        if m:
            cur = m.group(1).lower()
            continue
        m = re.match(r'^\| [^|]+ \| `([a-z0-9_]+)` \|', line)
        if m and cur:
            out[m.group(1)] = cur
    return out


def build_vfx(slug, S):
    kind = PACKS[slug]['kind']
    meta = S.json('metadata.json')
    elem = elements(S.text('README.md'))
    rows, sheets, sources = [], [], []
    for e in sorted(meta['effects'], key=lambda e: e['id']):
        eid = e['id']
        if not re.match(r'^[a-z0-9_]+$', eid):
            raise BuildError('%s: odd id %r' % (slug, eid))
        v = e['variants']['oblique/32']
        fw, fh, n = int(v['frame_w']), int(v['frame_h']), int(v['columns'])
        ax, ay = (int(t) for t in v['anchor_tile'])
        if int(v['rows']) != 8 or [d for d in e['directions']] != list(ROW_OF):
            raise BuildError('%s/%s: expected 8 rows E..NE' % (slug, eid))
        if n != int(e['frames']) or not 1 < n <= 255:
            raise BuildError('%s/%s: frames' % (slug, eid))
        layers = ('all',) if kind == 'wings' else ('back', 'front')
        cells = {}
        for li, lname in enumerate(layers):
            rel = v['files'][lname]
            a = S.png(rel)
            if a.shape[:2] != (8 * fh, n * fw):
                raise BuildError('%s: %dx%d, expected %dx%d' % (rel, a.shape[1], a.shape[0], n * fw, 8 * fh))
            for d, dn in enumerate(DIRS):
                row = ROW_OF[dn]
                for f in range(n):
                    cells[(li, d, f)] = a[row * fh:(row + 1) * fh, f * fw:(f + 1) * fw]
        box = L.union_bbox(cells.values())
        if box is None:
            raise BuildError('%s/%s: empty' % (slug, eid))
        tw, th, R, B, r, b = trim_plan(box, ax, ay)
        if max(tw, th) > 7:
            raise BuildError('%s/%s: %dx%d tiles' % (slug, eid, tw, th))
        W, H = tw * 32, th * 32
        sheet = np.zeros((n * H, len(layers) * 4 * W, 4), np.uint8)
        for (li, d, f), c in cells.items():
            col = li * 4 + d
            sheet[f * H:(f + 1) * H, col * W:(col + 1) * W] = place(c, tw, th, R, B)
        dx, dy = displacement(kind, tw, th, r, b)
        ms = L.fps_to_ms(e.get('fps') or 12)
        key = '%s__%s' % (slug, eid)
        atlas = 'pack33_%s/%s' % (slug, eid)
        extra = '|'.join(['gtypes=1', 'layers=%d' % len(layers), 'exact=%d' % (32 * max(tw, th)),
                          'durs0=' + '/'.join([str(ms)] * n), 'anim0=0:0:0', 'family=%s' % slug,
                          'element=%s' % elem.get(eid, 'none'), 'anchor=%d,%d' % (ax, ay),
                          'frame=%dx%d' % (fw, fh)])
        rows.append([key, 'outfit', kind, L.humanize(eid), atlas, 0, 0, tw, th, 4, n,
                     'animateAlways displacement:%d:%d' % (dx, dy), 'new', '', extra])
        sheets.append((atlas + '.png', sheet))
        sources.append([key, 'outfit', PACKS[slug]['label'], ' '.join(v['files'][x] for x in layers), LICENCE])
    return rows, sheets, sources


# ------------------------------------------------------------------------------------------------ kit
def kit_item_kind(s):
    cat, k = s['category'], s['kind']
    if (cat, k) in KIT_KINDS:
        kind, flags = KIT_KINDS[(cat, k)]
    elif cat == 'walls':
        kind, flags = 'stump', BLOCK
    elif cat == 'props':
        kind, flags = 'stump', BLOCK
    else:
        raise BuildError('kit/%s: no rule for %s / %s' % (s['id'], cat, k))
    if kind in ('stump',) and WALK_IDS.search(s['id']):
        kind, flags = 'decor', OPEN
    return kind, flags


def kit_frames(S, s):
    if s.get('strip') or (int(s.get('frames') or 1) > 1 and s.get('frame_w')):
        rel = s.get('strip') or s['file']            # a `*_strip` sprite is its own strip
        fw = int(s.get('frame_w') or s['w'])
        fh = int(s.get('frame_h') or s['h'])
        n = int(s['frames'])
        return frames_of_strip(S.png(rel), fw, fh, n), rel
    a = S.png(s['file'])
    if a.shape[:2] != (int(s['h']), int(s['w'])):
        raise BuildError('%s: %dx%d, catalogue says %sx%s' % (s['file'], a.shape[1], a.shape[0], s['w'], s['h']))
    return [a], s['file']


def build_kit(S):
    cat = S.json('catalog.json')
    sprites = cat['sprites']
    ids = {s['id'] for s in sprites}
    label = PACKS['kit']['label']
    items, item_sheets, outfits, outfit_sheets, sources = [], [], [], [], []
    figures = {}
    for s in sprites:
        if s['category'] == 'figures':
            figures.setdefault(s['set'], {})[(s['anim'], s['dir'])] = s
            continue
        if s.get('part_of') or (s['id'] + '_strip') in ids:
            continue
        frames, rel = kit_frames(S, s)
        fh, fw = frames[0].shape[:2]
        tw, th = tiles_px(fw, s['id']), tiles_px(fh, s['id'])
        if max(tw, th) > 7:
            raise BuildError('kit/%s: %dx%d tiles' % (s['id'], tw, th))
        kind, flags = kit_item_kind(s)
        extra = ['family=%s' % s['group'], 'footprint=%s' % 'x'.join(str(x) for x in s.get('footprint', [1, 1]))]
        if kind == 'ground':
            flags += ' minimap:%d' % L.rgb_to_minimap_index(L.mean_rgb(frames[0]))
        if s.get('emissive') or s['kind'] in LIGHT_KINDS:
            flags += ' ' + LIGHT
        if len(frames) > 1:
            flags += ' animateAlways'
            extra.append('ms=%d' % int(s.get('frame_ms') or 125))
            if s.get('loop') is False:
                extra.append('once=1')
        for t in ('mechanic', 'state', 'stage', 'floor_change'):
            if s.get(t) not in (None, ''):
                extra.append('%s=%s' % (t, s[t]))
        key = 'kit__%s' % s['id']
        atlas = 'pack33_kit/%s' % s['id']
        items.append([key, 'item', kind, L.humanize(s['id']), atlas, 0, 0, tw, th, 1, len(frames), flags, 'new', '',
                      '|'.join(extra)])
        item_sheets.append((atlas + '.png', np.concatenate(frames, axis=1)))
        sources.append([key, 'item', label, rel, LICENCE])
    corpse = None
    for fset in sorted(figures):
        anims = figures[fset]
        walk = 'walk' if ('walk', 's') in anims else 'hop'
        groups = []
        for anim in ('idle', walk):
            per_dir = []
            for d in KIT_DIRS:
                s = anims.get((anim, d))
                if s is None:
                    raise BuildError('kit/%s: no %s %s' % (fset, anim, d))
                fw, fh = int(s.get('frame_w') or s['w']), int(s.get('frame_h') or s['h'])
                per_dir.append((frames_of_strip(S.png(s['strip']), fw, fh, int(s['frames'])),
                                int(s.get('frame_ms') or 125), s['strip']))
            groups.append(per_dir)
        fh, fw = groups[0][0][0][0].shape[:2]
        tw, th = tiles_px(fw, fset), tiles_px(fh, fset)
        if any(f.shape[:2] != (fh, fw) for g in groups for fr, _, _ in g for f in fr):
            raise BuildError('kit/%s: frame sizes differ' % fset)
        n0, n1 = len(groups[0][0][0]), len(groups[1][0][0])
        if any(len(fr) != n for g, n in zip(groups, (n0, n1)) for fr, _, _ in g):
            raise BuildError('kit/%s: frame counts differ per direction' % fset)
        W, H = tw * 32, th * 32
        sheet = np.zeros(((n0 + n1) * H, 4 * W, 4), np.uint8)
        row = 0
        for g in groups:
            for f in range(len(g[0][0])):
                for d in range(4):
                    sheet[row * H:(row + 1) * H, d * W:(d + 1) * W] = g[d][0][f]
                row += 1
        ms0, ms1 = groups[0][2][1], groups[1][2][1]
        key = 'kit__%s' % fset
        atlas = 'pack33_kit/look_%s' % fset
        extra = '|'.join(['layers=1', 'gtypes=0+1', 'exact=%d+%d' % (32 * max(tw, th), 32 * max(tw, th)),
                          'durs0=' + '/'.join([str(ms0)] * n0), 'durs1=' + '/'.join([str(ms1)] * n1),
                          'anim0=0:0:0', 'anim1=0:0:0', 'family=%s' % anims[('idle', 's')]['group']])
        outfits.append([key, 'outfit', 'creature', L.humanize(fset), atlas, 0, 0, tw, th, 4, '%d+%d' % (n0, n1), '',
                        'new', '', extra])
        outfit_sheets.append((atlas + '.png', sheet))
        sources.append([key, 'outfit', label, ' '.join(sorted({x[2] for g in groups for x in g})), LICENCE])
        if ('death', 's') in anims:
            s = anims[('death', 's')]
            fw2, fh2 = int(s.get('frame_w') or s['w']), int(s.get('frame_h') or s['h'])
            last = frames_of_strip(S.png(s['strip']), fw2, fh2, int(s['frames']))[-1]
            if corpse is not None:
                raise BuildError('kit: two corpses')
            ck = 'kit__corpse_%s' % fset
            catlas = 'pack33_kit/corpse_%s' % fset
            corpse = ([ck, 'item', 'corpse', 'dead %s' % L.humanize(fset).lower(), catlas, 0, 0, tiles_px(fw2, fset),
                       tiles_px(fh2, fset), 1, 1, 'container forceuse notmoveable usable', 'new', '', 'race=blood'],
                      (catlas + '.png', last), [ck, 'item', label, s['strip'] + ' (last frame)', LICENCE])
    if corpse:
        items.append(corpse[0])
        item_sheets.append(corpse[1])
        sources.append(corpse[2])
    by_key = {s[0]: s for s in sources}
    return outfits + items, outfit_sheets + item_sheets, [by_key[r[0]] for r in outfits + items]


# ------------------------------------------------------------------------------------------------ build
def build_pack(slug, src, scanning=False):
    S = Source(src, slug, scanning)
    if PACKS[slug]['kind'] == 'kit':
        rows, sheets, sources = build_kit(S)
    else:
        rows, sheets, sources = build_vfx(slug, S)
    return rows, sheets, sources, S


def assign_ids(per_pack):
    """client ids, in place: the extra gets id=<client id> (outfit look or item client id); returns the totals."""
    nxt_o, nxt_i = FIRST_OUTFIT, FIRST_ITEM
    for slug in ORDER:
        rows = per_pack[slug]
        no = sum(1 for r in rows if r[1] == 'outfit')
        ni = sum(1 for r in rows if r[1] == 'item')
        if (no, ni) != COUNTS[slug]:
            raise BuildError('%s: %d outfits and %d items, COUNTS says %s (ids would move)' %
                             (slug, no, ni, COUNTS[slug]))
        for r in rows:
            if r[1] == 'outfit':
                r[14] = 'id=%d|' % nxt_o + r[14]
                nxt_o += 1
            else:
                r[14] = 'id=%d|' % nxt_i + r[14]
                nxt_i += 1
    return nxt_o - FIRST_OUTFIT, nxt_i - FIRST_ITEM


def outputs(src):
    per_pack, sheets, sources, files = {}, {}, {}, {}
    for slug in ORDER:
        rows, sh, so, S = build_pack(slug, src)
        per_pack[slug], sheets[slug], sources[slug] = rows, sh, so
        files[slug] = S.files_text()
    assign_ids(per_pack)
    return per_pack, sheets, sources, files


def committed_texts(per_pack, sheets, sources):
    out = {}
    for slug in ORDER:
        out['pack33_%s.csv' % slug] = L.csv_text(HEADER, per_pack[slug])
        out['pack33_%s_sources.csv' % slug] = L.csv_text(SOURCES_HEADER, sources[slug])
        out['pack33_%s.sums' % slug] = L.sums_text(sheets[slug])
    return out


def cmd_scan(a):
    for slug in ORDER:
        rows, sh, so, S = build_pack(slug, a.src, scanning=True)
        open(files_path(slug), 'w').write(S.files_text())
        print('%s: %d files listed' % (slug, len(S.used)))


def check_tables():
    """CI without sources: things, sources, sums and files lists agree; ids contiguous; counts."""
    bad = []
    nxt_o, nxt_i = FIRST_OUTFIT, FIRST_ITEM
    for slug in ORDER:
        try:
            rows = list(csv.DictReader(open(os.path.join(ART, 'pack33_%s.csv' % slug), newline='')))
            src = list(csv.DictReader(open(os.path.join(ART, 'pack33_%s_sources.csv' % slug), newline='')))
            sums = [ln.split('  ', 1)[1] for ln in open(os.path.join(ART, 'pack33_%s.sums' % slug)).read().split('\n')
                    if ln]
            files = L.read_files(files_path(slug))
        except (OSError, L.PackError) as e:
            bad.append('%s: %s' % (slug, e))
            continue
        if [r['key'] for r in rows] != [r['name'] for r in src]:
            bad.append('%s: things and sources rows differ' % slug)
        if sorted(r['atlas'] + '.png' for r in rows) != sorted(sums):
            bad.append('%s: things and sums differ' % slug)
        if any(r['pack'] != PACKS[slug]['label'] or r['licence'] != LICENCE for r in src):
            bad.append('%s: sources rows need pack %r and the licence text' % (slug, PACKS[slug]['label']))
        listed = {f.path for f in files}
        for r in src:
            for p in re.findall(r'[^ ]+\.png', r['source']):
                if p not in listed:
                    bad.append('%s: %s not in the files list' % (slug, p))
        no = sum(1 for r in rows if r['cat'] == 'outfit')
        ni = sum(1 for r in rows if r['cat'] == 'item')
        if (no, ni) != COUNTS[slug]:
            bad.append('%s: %d outfits, %d items; COUNTS %s' % (slug, no, ni, COUNTS[slug]))
        for r in rows:
            want = nxt_o if r['cat'] == 'outfit' else nxt_i
            if not r['extra'].startswith('id=%d|' % want):
                bad.append('%s: %s should have id %d' % (slug, r['key'], want))
            if r['cat'] == 'outfit':
                nxt_o += 1
            else:
                nxt_i += 1
    return bad


def cmd_build(a):
    if not a.src:
        if not a.check:
            sys.exit('build without --src needs --check')
        bad = check_tables()
        for b in bad:
            print('FAIL', b)
        print('pack33 tables: %s' % ('OK' if not bad else '%d problems' % len(bad)))
        return 1 if bad else 0
    per_pack, sheets, sources, files = outputs(a.src)
    texts = committed_texts(per_pack, sheets, sources)
    for slug in ORDER:
        texts[os.path.basename(files_path(slug))] = files[slug]
    if a.check:
        bad = 0
        for name, t in sorted(texts.items()):
            p = os.path.join(ART, name)
            if not os.path.isfile(p) or open(p).read() != t:
                print('DIFF', name)
                bad += 1
        print('pack33 build --check: %s' % ('OK' if not bad else '%d files differ' % bad))
        return 1 if bad else 0
    for slug in ORDER:
        d = os.path.join(ART, 'pack33_%s' % slug)
        os.makedirs(d, exist_ok=True)
        gi = os.path.join(d, '.gitignore')
        open(gi, 'w').write('# sheets cut from purchased packs: never committed, never shared (gen_pack33.py)\n*\n'
                            '!.gitignore\n')
        for rel, arr in sheets[slug]:
            Image.fromarray(arr, 'RGBA').save(os.path.join(ART, rel), optimize=False, compress_level=6)
    for name, t in texts.items():
        open(os.path.join(ART, name), 'w').write(t)
    print('pack33: %s' % ', '.join('%s %d things' % (s, len(per_pack[s])) for s in ORDER))
    return 0


# ------------------------------------------------------------------------------------------------ stats, contact
def tiles_of(sheet):
    h, w = sheet.shape[:2]
    for y in range(0, h, 32):
        for x in range(0, w, 32):
            t = sheet[y:y + 32, x:x + 32]
            if t[..., 3].any():
                yield t


def cmd_stats(a):
    per_pack, sheets, sources, files = outputs(a.src)
    total = set()
    for slug in ORDER:
        seen = set()
        soft = opaque = 0
        for _, arr in sheets[slug]:
            al = arr[..., 3]
            soft += int(((al > 0) & (al < 255)).sum())
            opaque += int((al > 0).sum())
            for t in tiles_of(arr):
                seen.add(L.digest(t))
        total |= seen
        sizes = {}
        for r in per_pack[slug]:
            k = '%sx%s %s' % (r[7], r[8], r[1])
            sizes[k] = sizes.get(k, 0) + 1
        disp = sorted({r[11].split('displacement:')[1] for r in per_pack[slug] if 'displacement:' in r[11]})
        print('%s: %d things, %d unique non-empty sprites, soft alpha %.1f%% of drawn pixels' %
              (slug, len(per_pack[slug]), len(seen), 100.0 * soft / max(1, opaque)))
        print('   sizes: %s' % ', '.join('%s: %d' % kv for kv in sorted(sizes.items())))
        if disp:
            print('   displacements: %s' % ' '.join(disp))
    print('all: %d unique sprites' % len(total))
    return 0


def _label(draw, xy, text):
    draw.text(xy, text, fill=(235, 225, 200, 255))


def compose_cell(sheet, r, f, d):
    """frame f facing d of a things row; aura layers back then front (no body: the owner sees the art itself)."""
    w, h = int(r[7]) * 32, int(r[8]) * 32
    layers = int(re.search(r'layers=(\d)', r[14]).group(1)) if r[1] == 'outfit' else 1
    if r[1] == 'item':
        return sheet[0:h, f * w:(f + 1) * w]
    out = np.zeros((h, w, 4), np.uint8)
    for li in range(layers):
        c = sheet[f * h:(f + 1) * h, (li * 4 + d) * w:(li * 4 + d + 1) * w]
        on = c[..., 3:4].astype(np.float32) / 255.0
        out[..., :3] = (c[..., :3] * on + out[..., :3] * (1 - on)).astype(np.uint8)
        out[..., 3] = np.maximum(out[..., 3], c[..., 3])
    return out


def cmd_contact(a):
    per_pack, sheets, sources, files = outputs(a.src)
    os.makedirs(a.out, exist_ok=True)
    bg = (38, 34, 40, 255)
    for slug in ORDER:
        rows = per_pack[slug]
        arr = dict(sheets[slug])
        outfits = [r for r in rows if r[1] == 'outfit']
        items = [r for r in rows if r[1] == 'item']
        for part, sel in (('looks', outfits), ('items', items)):
            if not sel:
                continue
            ndir = 4 if part == 'looks' else 1
            cw = max(int(r[7]) for r in sel) * 32
            ch = max(int(r[8]) for r in sel) * 32
            per_row = max(1, 2400 // (cw * ndir + 8))
            nrows = int(math.ceil(len(sel) / float(per_row)))
            W = per_row * (cw * ndir + 8) + 8
            H = nrows * (ch + 26) + 8
            img = Image.new('RGBA', (W, H), bg)
            dr = ImageDraw.Draw(img)
            for i, r in enumerate(sel):
                gx, gy = 8 + (i % per_row) * (cw * ndir + 8), 8 + (i // per_row) * (ch + 26)
                sh = arr[r[4] + '.png']
                for d in range(ndir):
                    dirs = (2, 1, 0, 3)          # S, E, N, W
                    c = compose_cell(sh, r, 0, dirs[d])
                    tile = Image.new('RGBA', (cw, ch), (58, 54, 60, 255))
                    # the wearer's / item's own tile (bottom-right of the canvas) marked by a lighter square
                    ImageDraw.Draw(tile).rectangle([cw - 32, ch - 32, cw - 1, ch - 1], fill=(72, 68, 76, 255))
                    tile.alpha_composite(Image.fromarray(c, 'RGBA'), (cw - c.shape[1], ch - c.shape[0]))
                    img.alpha_composite(tile, (gx + d * cw, gy))
                ident = re.search(r'id=(\d+)', r[14]).group(1)
                _label(dr, (gx, gy + ch + 4), '%s %s' % (ident, r[0].split('__', 1)[1][:34]))
            out = os.path.join(a.out, 'pack33_%s_%s.png' % (slug, part))
            img.convert('RGB').save(out)
            print(out, '%dx%d, %d things' % (W, H, len(sel)))
    return 0


def cmd_preview(a):
    """owner review from a TEST pair (import_art_things.py output): wings and auras on the stock player look 128 as
    the client draws them (wings: at the tile, the body 6, 6 up-left, GameWingOffset, behind it facing south / east;
    aura: layer 0 behind and layer 1 over the body, moved by (w - 1) * 16, GameBigAurasCenter), every thing at its own
    displacement; kit looks in four directions; kit items on a floor. 2x, pages of PAGE things."""
    from datspr import Dat, Spr
    from gen_owner_art import checker_ground, draw_thing, groups_of
    dat, spr = Dat(a.dat), Spr(a.spr)
    os.makedirs(a.out, exist_ok=True)
    rows = []
    for slug in ORDER:
        rows += [(slug, r) for r in csv.DictReader(open(os.path.join(ART, 'pack33_%s.csv' % slug), newline=''))]
    body = dat.outfit(128)
    bg = groups_of(dat, body)[0]
    bdisp = (8, 8)                                     # look 128's displacement (fix_pair_warnings.py scans)
    sc, page = 2, 20

    def disp(r):
        m = re.search(r'displacement:(-?\d+):(-?\d+)', r['flags'])
        return (int(m.group(1)), int(m.group(2))) if m else (0, 0)

    def save(img, name):
        img.resize((img.width * sc, img.height * sc), Image.NEAREST).convert('RGB').save(os.path.join(a.out, name))
        print(os.path.join(a.out, name))

    for slug in ('wings', 'heads', 'capes'):
        sel = [r for s, r in rows if s == slug]
        for p0 in range(0, len(sel), page):
            part = sel[p0:p0 + page]
            cw, ch = 5 * 32, 5 * 32                    # one direction: the wearer on tile (3, 3) of a 5 x 5 patch
            img = Image.new('RGBA', (2 * (4 * cw + 16), (len(part) + 1) // 2 * (ch + 14)), (30, 28, 32, 255))
            dr = ImageDraw.Draw(img)
            for i, r in enumerate(part):
                look = int(re.search(r'id=(\d+)', r['extra']).group(1))
                t = dat.outfit(look)
                g = groups_of(dat, t)[0]
                dx, dy = disp(r)
                for d in range(4):
                    cv = checker_ground(cw, ch)
                    tile = (3, 3)
                    bx, by = -bdisp[0], -bdisp[1]
                    if slug == 'wings':
                        bx, by = bx - 6, by - 6
                        if d in (1, 2):
                            draw_thing(cv, t, spr, tile, d, 0, group=g, dx=-dx, dy=-dy)
                        draw_thing(cv, body, spr, tile, d, 0, group=bg, dx=bx, dy=by)
                        if d in (0, 3):
                            draw_thing(cv, t, spr, tile, d, 0, group=g, dx=-dx, dy=-dy)
                    else:
                        cx = (g.w - 1) * 16 if g.w > 1 else 0
                        cy = (g.h - 1) * 16 if g.h > 1 else 0
                        draw_thing(cv, t, spr, tile, d, 0, layer=0, group=g, dx=cx - dx, dy=cy - dy)
                        draw_thing(cv, body, spr, tile, d, 0, group=bg, dx=bx, dy=by)
                        if g.layers > 1:
                            draw_thing(cv, t, spr, tile, d, 0, layer=1, group=g, dx=cx - dx, dy=cy - dy)
                    img.alpha_composite(cv, ((i % 2) * (4 * cw + 16) + d * cw, (i // 2) * (ch + 14)))
                dr.text(((i % 2) * (4 * cw + 16) + 2, (i // 2) * (ch + 14) + ch + 1),
                        '%d %s  disp %d,%d  (N E S W)' % (look, r['key'].split('__', 1)[1], dx, dy),
                        fill=(235, 225, 200, 255))
            save(img, 'preview_%s_%02d.png' % (slug, p0 // page + 1))
    kit = [r for s, r in rows if s == 'kit']
    looks = [r for r in kit if r['cat'] == 'outfit']
    img = Image.new('RGBA', (4 * 6 * 32, len(looks) * (6 * 32 + 14)), (30, 28, 32, 255))
    dr = ImageDraw.Draw(img)
    for i, r in enumerate(looks):
        look = int(re.search(r'id=(\d+)', r['extra']).group(1))
        t = dat.outfit(look)
        g = groups_of(dat, t)[0]
        for d in range(4):
            cv = checker_ground(6 * 32, 6 * 32)
            draw_thing(cv, t, spr, (4, 4), d, 0, group=g)
            img.alpha_composite(cv, (d * 6 * 32, i * (6 * 32 + 14)))
        dr.text((2, i * (6 * 32 + 14) + 6 * 32 + 1), '%d %s (N E S W, idle)' % (look, r['key'].split('__', 1)[1]),
                fill=(235, 225, 200, 255))
    save(img, 'preview_kit_looks.png')
    items = [r for r in kit if r['cat'] == 'item']
    cols, cell = 10, 7
    for p0 in range(0, len(items), 100):
        part = items[p0:p0 + 100]
        nrow = (len(part) + cols - 1) // cols
        img = Image.new('RGBA', (cols * cell * 32, nrow * (cell * 32 + 14)), (30, 28, 32, 255))
        dr = ImageDraw.Draw(img)
        for k, r in enumerate(part):
            cid = int(re.search(r'id=(\d+)', r['extra']).group(1))
            cv = checker_ground(cell * 32, cell * 32)
            draw_thing(cv, dat.items[cid - 100], spr, (cell - 1, cell - 1), 0, 0)
            img.alpha_composite(cv, ((k % cols) * cell * 32, (k // cols) * (cell * 32 + 14)))
            dr.text(((k % cols) * cell * 32 + 2, (k // cols) * (cell * 32 + 14) + cell * 32 + 1),
                    '%d %s' % (cid, r['key'].split('__', 1)[1][:30]), fill=(235, 225, 200, 255))
        save(img, 'preview_kit_items_%d.png' % (p0 // 100 + 1))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('scan'); p.add_argument('--src', required=True)
    p = sub.add_parser('build'); p.add_argument('--src'); p.add_argument('--check', action='store_true')
    p = sub.add_parser('stats'); p.add_argument('--src', required=True)
    p = sub.add_parser('contact'); p.add_argument('--src', required=True); p.add_argument('--out', required=True)
    p = sub.add_parser('preview'); p.add_argument('--dat', required=True); p.add_argument('--spr', required=True)
    p.add_argument('--out', required=True)
    a = ap.parse_args(argv)
    try:
        return {'scan': cmd_scan, 'build': cmd_build, 'stats': cmd_stats, 'contact': cmd_contact,
                'preview': cmd_preview}[a.cmd](a) or 0
    except (BuildError, L.PackError) as e:
        print('gen_pack33: %s' % e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
