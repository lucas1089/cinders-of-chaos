#!/usr/bin/env python3
"""Pair 30: element bursts, summoning circles and thrown-flask bursts and projectiles as magic effects and missiles
(PLAN_PAIR30 3.6). Effects 830-854 (25), missiles 186-188 (3).

    python3 -I gen_pack30_fx.py build --src DRIVEPACKS            # cut the strips, write the tables
    python3 -I gen_pack30_fx.py build --src DRIVEPACKS --check    # rebuild in memory and compare with the repo and the disk
    python3 -I gen_pack30_fx.py build --check                     # CI, no sources: tables agree with the file list
    python3 -I gen_pack30_fx.py preview --out DIR                 # every strip 3x on a ground (for the owner; outside git)

Needs numpy and Pillow (CI: the fx venv). The packs ban machine-learning use and sharing: this script only reads file
names, md5s, sizes, alpha boxes (geometry) and copies pixels; nobody views, measures or samples a palette from a pack
image. The cut strips (art_import/pack30_fx/, ignored by git) never enter the repo; committed are
art_import/pack30_fx.csv (the spec of import_fx_art.py), pack30_fx.sums, pack30_fx_sources.csv, pack30_potions.json
and the existing pack30_fx.files. `DRIVEPACKS` is the folder of the extracted packs; the folder of each pack slug
comes from the ignored art_import/pack30_packs.private.csv. Every source is read only after its md5 matches the list.

What is imported (spec order = id order):
  effects 830-841  twelve element bursts (strips of 17 square frames, 64 px), 60 ms a frame
  effects 842-850  nine summoning circles (9 frames, 64 px), 110 ms a frame, played once from the first to the last
                   frame (the loop is cut open) and then one empty frame
  effects 851-854  the four thrown-flask bursts (12 or 14 frames; the cell size and the timing come from the pack's
                   own frame file, the whole strip is used)
  missile 186      the flask projectile sheet: 3 x 3 direction cells of 64 px, one phase (the centre cell is empty in
                   the sheet, so it repeats the south cell as the other generators do; the sheet is checked cell by
                   cell against the eight single-direction files, so its layout is the client's, see MISSILE_DIR)
  missiles 187-188 the lava and the poison flask (the medium size), 8 frames of 32 px in every direction cell
The twelve bursts and nine circles with the four bursts fill the 25 effect ids exactly; one more effect, or a fourth
missile, stops the build with an error (the integrator then moves the overflow, PLAN_PAIR30 section 2).

Placement (as every generator since pair 27: gen_pack27_fx.effect_strip / bbox_tiles / place). The frame centre is put
on a point of the target tile and the thing is as many tiles wide as the art needs, so the art is never cut and its
bottom-right tile is the target tile plus the send offset (dx, dy): bursts on the body of the creature hit
(BODY_POINT, as the pair 29 blasts), circles and flask bursts on the floor centre (TILE_CENTRE), missiles on
MISSILE_CENTRE. The plan's first idea (2 x 2 things, offset 0, 0, the target in the bottom-right tile) would draw a
64 px burst centred on the corner of the target tile, half a tile up-left of it. The pixels are not changed: alpha is
cut to 0 / 255 at 128 (the sources already are), nothing is scaled, mirrored or recoloured.

Flask table pack30_potions.json (data only, no throw system yet): which burst and projectile each of the six flasks
uses, and the area pattern of the pack's own table (0 outside, 1 inside, 3 the centre tile that is hit). Timings are
those of the spec. Credit: "a freely shared potion-throwing pack" (docs/CREDITS.md); its author, title and the game its
flasks were drawn on are named nowhere in the repo.

Import (client/MANIFEST.md "Pack effects (pair 30)"), after every pair 30 item and outfit step:
    python3 -I import_fx_art.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \\
        --spec art_import/pack30_fx.csv --expect-first-effect 830 --expect-first-missile 186 \\
        --lua-out ../../../server/data/lib/chaos_pack30_fx_ids.lua --catalog-out ../../../server/data/spells/pack30_fx_catalog.csv
"""
import argparse
import hashlib
import json
import os
import sys
from collections import namedtuple

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack27_fx as G  # noqa: E402
import pack30lib as P  # noqa: E402

ART = P.ART
CAT = 'fx'
OUT = os.path.join(ART, 'pack30_fx')
ATLAS_DIR = 'pack30_fx'
SPEC = os.path.join(ART, 'pack30_fx.csv')
SUMS = os.path.join(ART, 'pack30_fx.sums')
SOURCES = os.path.join(ART, 'pack30_fx_sources.csv')
POTIONS = os.path.join(ART, 'pack30_potions.json')
GITIGNORE_TEXT = ('# strips cut from the purchased and shared effect packs: not to be redistributed, never committed '
                  '(gen_pack30_fx.py)\n*\n!.gitignore\n')

FIRST_EFFECT, MAX_EFFECTS = 830, 25
FIRST_MISSILE, MAX_MISSILES = 186, 3
MAX_FX_TILES = 3            # an effect or missile is at most 3 x 3 tiles (MISSILE patterns are 3 x 3 of these)
BURST_MS = 60
CIRCLE_MS = 110
FLIGHT_MS = 125             # the flask frames' timing (animacao.json of the flasks); the sheet has one phase
BODY_POINT = (10, 8)        # gen_pack29_vfx.BLAST_POINT: the middle of the body box of a creature on the target tile
TILE_CENTRE = G.TILE_CENTRE
MISSILE_CENTRE = G.MISSILE_CENTRE
MISSILE_DIR = G.MISSILE_DIR
POINT = {'burst': BODY_POINT, 'circle': TILE_CENTRE, 'splash': TILE_CENTRE}

SOURCES_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']
LICENCE_MUTTER = ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
                  'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md')
LICENCE_POTIONS = ('shared freely by its maker, no licence text found; imported only, the raw files are not '
                   'redistributed; never AI training data or a style reference; docs/CREDITS.md')
LICENCE = {'set30 mutter': LICENCE_MUTTER, 'set30 potions': LICENCE_POTIONS}

Pick = namedtuple('Pick', 'kind name slug path ms note')

BURSTS = [('arcane', 'Arcane_Magic_Burst_strip17.png', 'an arcane burst'),
          ('blood', 'Blood_Magic_Burst_strip17.png', 'a blood burst'),
          ('dark', 'Dark_Magic_Burst_strip17.png', 'a dark burst'),
          ('energy', 'Energy_Explosion_strip17.png', 'an energy explosion'),
          ('fire', 'Fire_Explosion_strip17.png', 'a fire explosion'),
          ('holy', 'Holy_Light_Burst_strip17.png', 'a holy light burst'),
          ('ice', 'Ice_Explosion_strip17.png', 'an ice explosion'),
          ('lightning', 'Lightning_Burst_strip17.png', 'a lightning burst'),
          ('nature', 'Nature_Magic_Burst_strip17.png', 'a nature burst'),
          ('poison', 'Poison_Cloud_strip17.png', 'a poison cloud'),
          ('water', 'Water_Splash_strip17.png', 'a water splash'),
          ('wind', 'Wind_Slash_strip17.png', 'a wind slash')]
# the four bursts of the flask effects: our name, the pack's frame strip (its animacao.json sits beside it)
SPLASHES = [('fire_splash_a', 'efeitos/fogo_esparramado_v1', 'a small fire splash'),
            ('fire_splash_b', 'efeitos/fogo_esparramado_v4', 'a large fire splash'),
            ('poison_burst_a', 'efeitos/bomba_veneno_v1', 'a small poison burst'),
            ('poison_burst_b', 'efeitos/bomba_veneno_v4', 'a large poison burst')]
SHEET_DIR = 'projeteis/pocao_lava_v2'
SHEET_FILE = SHEET_DIR + '/folha_3x3.png'
# single-direction files of the sheet's projectile (compass letters of the pack: l = east, o = west) -> our direction
SHEET_DIRS = {'n': 'n', 'ne': 'ne', 'l': 'e', 'se': 'se', 's': 's', 'so': 'sw', 'o': 'w', 'no': 'nw'}
FLASKS = [('potion_flask_lava', 'pocoes/lava/strong', 'the lava flask (medium)'),
          ('potion_flask_poison', 'pocoes/veneno/strong', 'the poison flask (medium)')]
MONTAGEM = 'montagem.json'
SIZE_NAME = {'health': 'small', 'strong': 'medium', 'great': 'large'}
ELEMENT_NAME = {'lava': 'lava', 'veneno': 'venom'}
FLASK_OF = {'lava': 'potion_flask_lava', 'venom': 'potion_flask_poison'}


def picks():
    """[Pick] in id order: effects first, then missiles; the effect ids are FIRST_EFFECT.. and the missile ids
    FIRST_MISSILE.. in this order."""
    out = []
    for el, fname, what in BURSTS:
        out.append(Pick('burst', 'mfx_' + el, 'magic_fx', fname, BURST_MS, what))
    for i in range(1, 10):
        out.append(Pick('circle', 'summon_circle_%d' % i, 'summoning_circles', 'Summoning_Circle_%d_strip9.png' % i,
                        CIRCLE_MS, 'a ground circle'))
    for name, d, what in SPLASHES:
        out.append(Pick('splash', name, 'potions', d + '/tira.png', 0, what))      # ms from the pack's animacao.json
    out.append(Pick('sheet', 'potion_lava', 'potions', SHEET_FILE, FLIGHT_MS, 'the lava flask in flight'))
    for name, d, what in FLASKS:
        out.append(Pick('flask', name, 'potions', d + '/tira.png', 0, what + ' in flight'))
    return out


def kind_of(p):
    return 'missile' if p.kind in ('sheet', 'flask') else 'effect'


def check_blocks(pk):
    ne = sum(kind_of(p) == 'effect' for p in pk)
    nm = sum(kind_of(p) == 'missile' for p in pk)
    if ne > MAX_EFFECTS:
        raise P.PackError('%d effects need ids %d..%d but the block %d..%d holds %d: move the overflow to the '
                          'overflow range (PLAN_PAIR30 section 2) or drop some picks' %
                          (ne, FIRST_EFFECT, FIRST_EFFECT + ne - 1, FIRST_EFFECT, FIRST_EFFECT + MAX_EFFECTS - 1, MAX_EFFECTS))
    if nm > MAX_MISSILES:
        raise P.PackError('%d missiles need ids %d..%d but the block %d..%d holds %d: the client sends missile ids '
                          'in one byte; move the overflow below 255 by hand' %
                          (nm, FIRST_MISSILE, FIRST_MISSILE + nm - 1, FIRST_MISSILE, FIRST_MISSILE + MAX_MISSILES - 1, MAX_MISSILES))


def ids_of(pk):
    ids, cnt = {}, {'effect': FIRST_EFFECT - 1, 'missile': FIRST_MISSILE - 1}
    for p in pk:
        k = kind_of(p)
        cnt[k] += 1
        ids[p.name] = cnt[k]
    return ids


# ------------------------------------------------------------------------------------------------ pixels
def hard_alpha(a):
    """alpha 0 / 255 at 128 (as import_fx_art.build), colour of the transparent pixels cleared"""
    a = a.copy()
    on = a[..., 3] >= 128
    a[~on] = 0
    a[..., 3] = np.where(on, 255, 0)
    return a


def frames_of(a, name, n=None):
    """the strip's square frames (cell = strip height); n frames if given"""
    cell = a.shape[0]
    fr = P.strip_frames(a, cell)
    if n is not None and len(fr) != n:
        raise P.PackError('%s: %d frames, expected %d' % (name, len(fr), n))
    return [hard_alpha(f) for f in fr]


def effect_strip(name, frames, point):
    """frames (square cells) -> (strip, w, h, phases, dx, dy). Empty frames at either end are dropped, an empty frame
    inside is an error, one empty frame is appended (an effect plays once)."""
    while frames and not frames[-1][..., 3].any():
        frames = frames[:-1]
    while frames and not frames[0][..., 3].any():
        frames = frames[1:]
    if not frames:
        raise P.PackError('%s: no visible frame' % name)
    if not all(f[..., 3].any() for f in frames):
        raise P.PackError('%s: an empty frame inside the strip' % name)
    cell = frames[0].shape[0]
    anchor = (cell // 2, cell // 2)
    left, top, right, bottom = G.bbox_tiles(frames, anchor, point)
    w, h = left + 1 + right, top + 1 + bottom
    if w > MAX_FX_TILES or h > MAX_FX_TILES:
        raise P.PackError('%s: %dx%d tiles, the limit is %d' % (name, w, h, MAX_FX_TILES))
    n = len(frames) + 1
    strip = np.zeros((h * 32, w * 32 * n, 4), np.uint8)
    for i, f in enumerate(frames):
        strip[:, i * w * 32:(i + 1) * w * 32] = G.place(f, anchor, point, left, top, w, h, name)
    return strip, w, h, n, right, bottom


def sheet_cells(a, cell):
    """the sheet of 3 x 3 direction cells -> {(x, y): cell}; the centre cell, when empty, repeats the south cell"""
    if a.shape[0] != 3 * cell or a.shape[1] != 3 * cell:
        raise P.PackError('direction sheet %dx%d is not 3x3 cells of %d px' % (a.shape[1], a.shape[0], cell))
    cells = {(x, y): hard_alpha(a[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell]) for x in range(3) for y in range(3)}
    for k in cells:
        if k != (1, 1) and not cells[k][..., 3].any():
            raise P.PackError('direction sheet: cell %s is empty' % (k,))
    if cells[(1, 1)][..., 3].any():
        raise P.PackError('direction sheet: the centre cell holds art (expected an empty centre, PLAN_PAIR30 3.6)')
    cells[(1, 1)] = cells[(1, 2)].copy()
    return cells


def check_sheet_layout(a, cell, singles):
    """The sheet's cell at (x, y) must equal the single-direction file of MISSILE_DIR[(x, y)] (exact pixels).
    singles {direction: array}. Returns problems."""
    bad = []
    for (x, y), d in MISSILE_DIR.items():
        if (x, y) == (1, 1):
            continue
        if d not in singles:
            bad.append('no single-direction file for %s' % d)
            continue
        if not np.array_equal(a[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell], singles[d]):
            bad.append('sheet cell %s differs from the single file of direction %s: the sheet is not laid out as the '
                       'client reads it' % ((x, y), d))
    return bad


def missile_strip(name, pats, anchor):
    """pats {(x, y): [frames]} (3 x 3 patterns, equal frame counts) -> (strip, w, h, phases, dx, dy)"""
    n = len(pats[(0, 0)])
    if set(pats) != {(x, y) for x in range(3) for y in range(3)} or any(len(v) != n for v in pats.values()):
        raise P.PackError('%s: the patterns must be 3 x 3 with %d frames each' % (name, n))
    left, top, right, bottom = G.bbox_tiles([f for v in pats.values() for f in v], anchor, MISSILE_CENTRE)
    w, h = left + 1 + right, top + 1 + bottom
    if w > MAX_FX_TILES or h > MAX_FX_TILES:
        raise P.PackError('%s: %dx%d tiles, the limit is %d' % (name, w, h, MAX_FX_TILES))
    W, H = w * 32, h * 32
    strip = np.zeros((3 * H, 3 * W * n, 4), np.uint8)
    for (x, y), fr in pats.items():
        for i, img in enumerate(fr):
            x0 = (x * n + i) * W
            strip[y * H:(y + 1) * H, x0:x0 + W] = G.place(img, anchor, MISSILE_CENTRE, left, top, w, h, name)
    return strip, w, h, n, right, bottom


def flask_patterns(frames):
    """the same frames in every direction cell (the flask is not turned)"""
    return {(x, y): [f.copy() for f in frames] for x in range(3) for y in range(3)}


# ------------------------------------------------------------------------------------------------ sources
class Source:
    """reads the verified files of the packs; load(slug, path) -> RGBA array, meta(slug, path) -> parsed json"""

    def __init__(self, src, private, rows):
        self.src, self.private = src, private
        self.rows = {(r.slug, r.path): r for r in rows}

    def row(self, slug, path):
        r = self.rows.get((slug, path))
        if r is None:
            raise P.PackError('%s/%s is not in pack30_fx.files' % (slug, path))
        return r

    def load(self, slug, path):
        return P.load_verified(P.source_path(self.src, slug, path, self.private), self.row(slug, path).md5)

    def meta(self, slug, path):
        full = P.source_path(self.src, slug, path, self.private)
        data = open(full, 'rb').read()
        got = hashlib.md5(data).hexdigest()
        if got != self.row(slug, path).md5:
            raise P.PackError('%s: md5 %s, the list has %s (another file?)' % (full, got, self.row(slug, path).md5))
        return json.loads(data.decode('utf-8'))


def timing_of(meta, name, nframes, cell):
    """ms of an animacao.json: one value for every frame; the frame count and the cell must match the strip"""
    ms = meta.get('ms')
    if not ms or len(set(ms)) != 1:
        raise P.PackError('%s: the timing is not one value for all frames: %r' % (name, ms))
    if len(ms) != nframes:
        raise P.PackError('%s: the timing lists %d frames, the strip has %d' % (name, len(ms), nframes))
    if list(meta.get('quadro', [cell, cell])) != [cell, cell]:
        raise P.PackError('%s: the timing says frames of %r px, the strip has %d' % (name, meta.get('quadro'), cell))
    return int(ms[0])


def convert(p, source):
    """-> (spec row dict, strip array)"""
    n_name = p.name
    if p.kind in ('burst', 'circle'):
        a = source.load(p.slug, p.path)
        want = int(p.path.rsplit('strip', 1)[1].split('.')[0])
        fr = frames_of(a, n_name, want)
        strip, w, h, n, dx, dy = effect_strip(n_name, fr, POINT[p.kind])
        ms = p.ms
        src_note = '%d frames of %s' % (want, p.path)
    elif p.kind == 'splash':
        a = source.load(p.slug, p.path)
        meta = source.meta(p.slug, p.path.rsplit('/', 1)[0] + '/animacao.json')
        fr = frames_of(a, n_name)
        ms = timing_of(meta, n_name, len(fr), a.shape[0])
        strip, w, h, n, dx, dy = effect_strip(n_name, fr, POINT['splash'])
        src_note = '%d frames of %s' % (len(fr), p.path)
    elif p.kind == 'sheet':
        a = source.load(p.slug, p.path)
        cell = a.shape[0] // 3
        singles = {}
        for fn, d in SHEET_DIRS.items():
            s = source.load(p.slug, '%s/%s.png' % (SHEET_DIR, fn))
            if s.shape[:2] != (cell, cell):
                raise P.PackError('%s: single file %s is %s, the sheet cells are %d px' % (n_name, fn, s.shape, cell))
            singles[d] = s
        bad = check_sheet_layout(a, cell, singles)
        if bad:
            raise P.PackError('%s: %s' % (n_name, '; '.join(bad)))
        cells = sheet_cells(a, cell)
        strip, w, h, n, dx, dy = missile_strip(n_name, {k: [v] for k, v in cells.items()}, (cell // 2, cell // 2))
        ms = p.ms
        src_note = 'direction sheet %s' % p.path
    else:
        a = source.load(p.slug, p.path)
        meta = source.meta(p.slug, p.path.rsplit('/', 1)[0] + '/animacao.json')
        fr = frames_of(a, n_name)
        ms = timing_of(meta, n_name, len(fr), a.shape[0])
        strip, w, h, n, dx, dy = missile_strip(n_name, flask_patterns(fr), (a.shape[0] // 2, a.shape[0] // 2))
        src_note = '%d frames of %s' % (len(fr), p.path)
    row = dict(kind=kind_of(p), name=n_name, file='%s/%s.png' % (ATLAS_DIR, n_name), w=w, h=h, phases=n, ms=ms,
               dx=dx, dy=dy, note='%s (from %s)' % (p.note[0].upper() + p.note[1:], src_note))
    return row, strip


# ------------------------------------------------------------------------------------------------ tables
def spec_text(rows):
    return G.spec_text(rows)


def sums_text(rows, strips):
    return P.sums_text([(r['file'], s) for r, s in zip(rows, strips)])


def sources_text(pk, packs):
    label = {p.slug: p.label for p in packs}
    rows = []
    for p in pk:
        src = '%s/%s' % (p.slug, p.path)
        rows.append([p.name, kind_of(p), label[p.slug], src, LICENCE[label[p.slug]]])
    return P.csv_text(SOURCES_FIELDS, rows)


def area_ok(area):
    """the pack's area pattern: a rectangle of odd edges with 0 / 1 / 3 cells and exactly one 3 at the centre"""
    if not area or not all(isinstance(r, list) and len(r) == len(area[0]) for r in area):
        return False
    h, w = len(area), len(area[0])
    flat = [v for r in area for v in r]
    return (h % 2 == 1 and w % 2 == 1 and set(flat) <= {0, 1, 3} and flat.count(3) == 1
            and area[h // 2][w // 2] == 3)


def potions_data(rows, montagem):
    """pack30_potions.json: bursts, missiles and the six flasks with their area patterns (data for a later throw system)"""
    by = {r['name']: r for r in rows}
    ids = {r['name']: FIRST_EFFECT + i for i, r in enumerate(x for x in rows if x['kind'] == 'effect')}
    ids.update({r['name']: FIRST_MISSILE + i for i, r in enumerate(x for x in rows if x['kind'] == 'missile')})
    burst_of = {d: n for n, d, _ in SPLASHES}
    flight_of = {SHEET_DIR: 'potion_lava'}

    def entry(r):
        e = dict(id=ids[r['name']], size='%dx%d' % (r['w'], r['h']), send_offset='%d,%d' % (r['dx'], r['dy']),
                 phases=r['phases'], ms=r['ms'])
        if r['kind'] == 'effect':
            e['total_ms'] = r['phases'] * r['ms']
        return e

    flasks = []
    for key in sorted(montagem):
        el, _, sz = key.partition('_')
        m = montagem[key]
        if el not in ELEMENT_NAME or sz not in SIZE_NAME:
            raise P.PackError('%s: unknown flask key in the pack table' % key)
        if not area_ok(m.get('area')):
            raise P.PackError('%s: the area pattern is not an odd rectangle of 0 / 1 / 3 with one centre' % key)
        burst = burst_of.get(m.get('explosao'))
        if burst is None:
            raise P.PackError('%s: burst %r is not one of the imported splashes' % (key, m.get('explosao')))
        element = ELEMENT_NAME[el]
        flight = flight_of.get(m.get('projetil'), FLASK_OF[element])
        flasks.append(dict(key='%s_%s' % (element, SIZE_NAME[sz]), element=element, size=SIZE_NAME[sz], burst=burst,
                           missile=flight, flask_missile=FLASK_OF[element], area=m['area']))
    order = {'small': 0, 'medium': 1, 'large': 2}
    flasks.sort(key=lambda f: (f['element'], order[f['size']]))
    return dict(
        format=1,
        about='Thrown flasks: which burst effect and projectile each flask uses and the area it covers. Data only, no '
              'throw system uses it yet. Ids are those of the pair 30 build (art_import/pack30_fx.csv).',
        legend={'0': 'outside the area', '1': 'inside the area', '3': 'centre, the tile that is hit'},
        flights={'ms_per_frame': FLIGHT_MS},
        bursts={n: entry(by[n]) for n, _, _ in SPLASHES},
        missiles={n: entry(by[n]) for n in ('potion_lava', 'potion_flask_lava', 'potion_flask_poison')},
        flasks=flasks)


def potions_text(data):
    return json.dumps(data, indent=1, sort_keys=False, ensure_ascii=True) + '\n'


# ------------------------------------------------------------------------------------------------ build
def render(pk, source):
    rows, strips = [], []
    for p in pk:
        r, s = convert(p, source)
        rows.append(r)
        strips.append(s)
    return rows, strips


def write_strips(rows, strips, out=OUT):
    os.makedirs(out, exist_ok=True)
    gi = os.path.join(out, '.gitignore')
    if not os.path.isfile(gi) or open(gi, encoding='utf-8').read() != GITIGNORE_TEXT:
        with open(gi, 'w', encoding='utf-8', newline='') as f:
            f.write(GITIGNORE_TEXT)
    for r, s in zip(rows, strips):
        Image.fromarray(s, 'RGBA').save(os.path.join(ART, r['file']))


def disk_problems(rows, strips=None):
    """strips on disk that are not what they should be (a missing file is fine: CI has none): the shape from the
    spec, always; the pixels against `strips` when given"""
    bad = []
    for i, r in enumerate(rows):
        p = os.path.join(ART, r['file'])
        if not os.path.isfile(p):
            continue
        a = np.asarray(Image.open(p).convert('RGBA'))
        bad += G.check_strip(r, a)
        if strips is not None and not np.array_equal(a, strips[i]):
            bad.append('%s differs from the rebuilt strip' % p)
    return bad


def read_text(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()


def check_structure(pk, packs, files_rows):
    """Everything that needs no pixels: the committed tables against the pick list and the file list."""
    import csv
    import io
    bad = []
    try:
        check_blocks(pk)
    except P.PackError as e:
        return [str(e)]
    have = {(r.slug, r.path) for r in files_rows}
    need = [(p.slug, p.path) for p in pk]
    need += [('potions', MONTAGEM)] + [('potions', '%s/%s.png' % (SHEET_DIR, f)) for f in SHEET_DIRS]
    need += [('potions', p.path.rsplit('/', 1)[0] + '/animacao.json') for p in pk if p.kind in ('splash', 'flask')]
    for k in need:
        if k not in have:
            bad.append('%s/%s: not in pack30_fx.files' % k)
    for path in (SPEC, SUMS, SOURCES, POTIONS):
        if not os.path.isfile(path):
            bad.append('%s: missing (run build --src)' % path)
    if bad:
        return bad
    rd = list(csv.DictReader(io.StringIO(read_text(SPEC))))
    if read_text(SPEC).splitlines()[0] != ','.join(G.FIELDS):
        return ['%s: header must be %s' % (SPEC, ','.join(G.FIELDS))]
    ids = ids_of(pk)
    if [(r['kind'], r['name']) for r in rd] != [(kind_of(p), p.name) for p in pk]:
        return ['%s: kinds and names differ from the pick list (run build --src)' % SPEC]
    rows = []
    for r, p in zip(rd, pk):
        try:
            row = dict(r, **{k: int(r[k]) for k in ('w', 'h', 'phases', 'ms', 'dx', 'dy')})
        except ValueError:
            bad.append('%s: numbers of %s' % (SPEC, p.name))
            continue
        rows.append(row)
        if row['file'] != '%s/%s.png' % (ATLAS_DIR, p.name):
            bad.append('%s: file of %s' % (SPEC, p.name))
        if not (1 <= row['w'] <= MAX_FX_TILES and 1 <= row['h'] <= MAX_FX_TILES
                and 0 <= row['dx'] < row['w'] and 0 <= row['dy'] < row['h']):
            bad.append('%s: size or offset of %s' % (SPEC, p.name))
        if row['ms'] < 20 or not row['note']:
            bad.append('%s: timing or note of %s' % (SPEC, p.name))
        if p.kind in ('burst', 'circle', 'splash') and row['phases'] < 3:
            bad.append('%s: %s has %d phases' % (SPEC, p.name, row['phases']))
        if p.kind == 'sheet' and row['phases'] != 1:
            bad.append('%s: %s must have one phase' % (SPEC, p.name))
        if p.kind == 'burst' and row['ms'] != BURST_MS or p.kind == 'circle' and row['ms'] != CIRCLE_MS:
            bad.append('%s: timing of %s' % (SPEC, p.name))
    if bad:
        return bad
    if read_text(SOURCES) != sources_text(pk, packs):
        bad.append('%s differs from the pick list (run build --src)' % SOURCES)
    lines = read_text(SUMS).splitlines()
    paths = [ln.split('  ', 1)[1] for ln in lines if '  ' in ln]
    if paths != [r['file'] for r in rows]:
        bad.append('%s: paths differ from the spec' % SUMS)
    sums = {ln.split('  ', 1)[1]: ln.split('  ', 1)[0] for ln in lines if '  ' in ln}
    for r in rows:
        f = os.path.join(ART, r['file'])
        if os.path.isfile(f):
            a = np.asarray(Image.open(f).convert('RGBA'))
            if P.digest(a) != sums.get(r['file']):
                bad.append('%s differs from %s' % (f, SUMS))
    bad += disk_problems(rows)
    # the flask table against the spec
    try:
        data = json.loads(read_text(POTIONS))
    except ValueError as e:
        return bad + ['%s: %s' % (POTIONS, e)]
    by = {r['name']: r for r in rows}
    exp_ids = ids
    for sec in ('bursts', 'missiles'):
        for n, e in data.get(sec, {}).items():
            r = by.get(n)
            if r is None or e.get('id') != exp_ids[n] or e.get('ms') != r['ms'] or e.get('phases') != r['phases'] \
                    or e.get('size') != '%dx%d' % (r['w'], r['h']) or e.get('send_offset') != '%d,%d' % (r['dx'], r['dy']):
                bad.append('%s: %s %s differs from the spec' % (POTIONS, sec, n))
    if sorted(data.get('bursts', {})) != sorted(n for n, _, _ in SPLASHES):
        bad.append('%s: bursts differ from the splash list' % POTIONS)
    if sorted(data.get('missiles', {})) != sorted(['potion_lava'] + [n for n, _, _ in FLASKS]):
        bad.append('%s: missiles differ from the pick list' % POTIONS)
    if len(data.get('flasks', [])) != 6:
        bad.append('%s: expected six flasks' % POTIONS)
    for f in data.get('flasks', []):
        if not area_ok(f.get('area')) or f.get('burst') not in data.get('bursts', {}) \
                or f.get('missile') not in data.get('missiles', {}) or f.get('flask_missile') not in data.get('missiles', {}):
            bad.append('%s: flask %s is malformed' % (POTIONS, f.get('key')))
    if read_text(POTIONS) != potions_text(data):
        bad.append('%s is not in the canonical form' % POTIONS)
    gi = os.path.join(OUT, '.gitignore')
    if not os.path.isfile(gi) or open(gi, encoding='utf-8').read() != GITIGNORE_TEXT:
        bad.append('%s: missing or changed' % gi)
    return bad


def cmd_build(src, check):
    pk = picks()
    check_blocks(pk)
    packs = P.load_packs()
    by = P.pack_by_slug(packs)
    for slug in sorted({p.slug for p in pk}):
        if slug not in by or by[slug].status != 'ready' or CAT not in by[slug].cats():
            raise P.PackError('%s is not a ready pack of category %s' % (slug, CAT))
    files_rows = P.read_files(P.files_path(CAT))
    ids = ids_of(pk)
    ne = sum(kind_of(p) == 'effect' for p in pk)
    nm = len(pk) - ne
    print('effects: %d (ids %d..%d), missiles: %d (ids %d..%d)' % (ne, FIRST_EFFECT, FIRST_EFFECT + ne - 1, nm,
                                                                   FIRST_MISSILE, FIRST_MISSILE + nm - 1))
    bad = []
    if src is None:
        if not check:
            sys.exit('build needs --src DRIVEPACKS (or --check for the source-free check)')
        bad = check_structure(pk, packs, files_rows)
    else:
        private = P.load_private()
        source = Source(src, private, files_rows)
        rows, strips = render(pk, source)
        montagem = source.meta('potions', MONTAGEM)
        texts = {SPEC: spec_text(rows), SUMS: sums_text(rows, strips), SOURCES: sources_text(pk, packs),
                 POTIONS: potions_text(potions_data(rows, montagem))}
        if check:
            for path, text in texts.items():
                if not os.path.isfile(path) or read_text(path) != text:
                    bad.append('%s differs from the rebuild' % path)
            bad += disk_problems(rows, strips)
            if not bad:
                bad = check_structure(pk, packs, files_rows)
        else:
            write_strips(rows, strips)
            for path, text in texts.items():
                with open(path, 'w', encoding='utf-8', newline='') as f:
                    f.write(text)
            for r in rows:
                print('%s %d %s: %dx%d, offset %d,%d, %d x %d ms' % (r['kind'], ids[r['name']], r['name'], r['w'], r['h'],
                                                                   r['dx'], r['dy'], r['phases'], r['ms']))
            bad = check_structure(pk, packs, files_rows)
    for b in bad:
        print('FAIL', b)
    if bad:
        return 1
    print('ok')
    return 0


def cmd_preview(out):
    G.SPEC, G.ART = SPEC, ART
    G.preview(out)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src', default=None, help='the drivepacks folder')
    b.add_argument('--check', action='store_true')
    pv = sub.add_parser('preview')
    pv.add_argument('--out', required=True)
    a = ap.parse_args()
    try:
        if a.cmd == 'preview':
            return cmd_preview(a.out)
        return cmd_build(a.src, a.check)
    except P.PackError as e:
        print('STOP', e)
        return 2


if __name__ == '__main__':
    sys.exit(main())
