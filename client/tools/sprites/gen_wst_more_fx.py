#!/usr/bin/env python3
"""The effects of the purchased 32 px effect sets that no pair held yet, appended after effect 5441 (O735; client pair 82).

    python3 -I gen_wst_more_fx.py build DAT SPR OUT_DIR --src DIR [--src DIR ...]   # OUT_DIR gets Tibia.dat, Tibia.spr, strips/
    python3 -I gen_wst_more_fx.py build DAT SPR OUT_DIR --src DIR --write           # also writes the table and the sums
    python3 -I gen_wst_more_fx.py check          # CI, no art, no pair: table rules, sums, ids file, tags, catalog agree
    python3 -I gen_wst_more_fx.py ids [--check]  # server/data/lib/chaos_wst_more_fx_ids.lua, the tags of
                                                 # server/data/spells/spell_fx_elements.csv, server/data/spells/more_pack_fx_catalog.csv
    python3 -I gen_wst_more_fx.py live DAT SPR   # the pair holds every effect at its id, pixel for pixel

Owner 2026-11-23 (O735): "pode importar todos os pacotes" of the effect seller. Three sources of new art (docs/CREDITS.md
names them; this file does not):
  m3  the third volume of the 500 effect set: cones and waves (8 headings each), area spells, tile spells
  m4  the fourth volume: blasts, sigils, feedback, rewards, portals, pings, status, emotes and the rest
  mv  the 64 px catalog sets (impacts, circles, auras, status, fields, markers, game feel): the colour variants that pair 36
      did not take (it took one variant of each effect), halved to 32 px like pair 36
Not taken: every effect a pair already holds (the src digests of the other art_import tables, the sources of pair 36 / 27
/ 29), the projectiles (pair 81 has 253 missiles and the id is one byte: no free id), text pictures (English words), the
camera copies of the first 500 set (same effects, wrong projection), and the body layers (wings, heads, capes: cosmetics).

The art may not be passed on or train a model, and the first set is never a style reference. So no picture is in the
repository: committed are this script, the table art_import/more_pack_fx.csv (one row per effect: our name, the set, the
pack effect id and variant, src = 12 hex of the sha256 of the sheet file or of the variant's json, the cut) and
art_import/more_pack_fx.sums (the digest of every built strip). The sheets are read by this local script only; nothing is
sent to a web or AI service and no picture is looked at: the choice is by file names, metadata and numbers.

The cut (O733 house rules, every effect):
  alpha     a hard cut at 0.5 (gen_pack27_fx.clean_alpha): alpha 0 / 255, no halo, no dither; the 64 px sets are halved first
            (gen_pack36_fx.halve, premultiplied 2 x 2 mean, then the same cut)
  frames    empty frames at the ends and inside dropped, a frame equal to the one before merged into it (its time added:
            column durs), at most MAX_PHASES
  one-shot  ends empty: a blank last phase when the last frame still holds more than END_SHARE of the peak art
  loop      closes: cut to the longest run 0..k whose jump back to frame 0 is at most LOOP_RATIO x the mean step, else out
  place     the pack anchor tile on the target tile (pair 36); a non-directional effect whose art centre is more than
            CENTRE_PX from the tile middle is moved by whole pixels onto it; the canvas follows the art (dx, dy: send offset)
  out       a dither or dissolve mesh (clean_pack_dither.mesh_mask, MESH_PX), stray pixels (anim_fixes.isolated_px, over
            STRAY_SHARE and STRAY_PX), art cut by the pack's own frame (EDGE_RUN px on its border), a loop that does not
            close, more than MAX_TILES tiles a side, almost no art left after the cut
  headings  a cone or a wave is 8 effects, n ne e se s sw w nw: all 8 pass or the set is out
Element tag (spell_fx_elements.csv): the element the pack's name, element field or variant says, kept only when the
measured hue of the art agrees (HUE_OK); else `any`.

Input pair: pair 81 (dat md5 d5212ccc...) or the pair the O734 fixes make of it: 5,441 effects, 253 missiles, the fixed
effects 5354..5441 drawn. Order: the O734 fixes first, then this step. New ids 5442.. dense, in table order; no missile.
Needs numpy and Pillow (the fx venv of CI). Deterministic: the same sheets give the same strips.
"""
import argparse
import csv
import colorsys
import glob
import hashlib
import io
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'more_pack_fx.csv')
SUMS = os.path.join(ART, 'more_pack_fx.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_wst_more_fx_ids.lua')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')
CATALOG = os.path.join(ROOT, 'server', 'data', 'spells', 'more_pack_fx_catalog.csv')
sys.path.insert(0, HERE)

NEED_EFFECTS, NEED_MISSILES = 5441, 253     # pair 81, or the O734 fixes on it
FIXED = (5354, 5441)                        # the awakened kit and its headings (pair 76 / 77): drawn in the input pair
FIRST = NEED_EFFECTS + 1
PAIR = 82
MAX_PHASES = 48
MAX_TILES = 9
END_SHARE = 0.3
LOOP_RATIO = 2.5
CENTRE_PX = 12
MESH_PX = 100
STRAY_SHARE, STRAY_PX = 0.08, 80
EDGE_RUN = 8
MIN_PX = 24                                 # the peak frame keeps at least this many pixels after the cut
DIRS8 = ['e', 'se', 's', 'sw', 'w', 'nw', 'n', 'ne']       # the row order of a directional sheet
OUR_DIRS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']    # our suffix order
# the sets, known by the sha256 of the metadata's own set field (12 hex), so the pack is not named here
META_SETS = {'93ef3b267141': 'm3', '490093662ae2': 'm4'}
PREFIX = {'m3': 'm3_', 'm4': 'm4_', 'mv': 'mv_'}
CATALOG_CATS = {'impacts': 'impact', 'circles': 'circle', 'auras': 'aura', 'status': 'status', 'fields': 'field',
                'environment': 'field', 'fx': 'fx', 'markers': 'marker'}      # not 'text' (English words), not projectiles
SHAPE_M3 = {'cones': 'cone', 'waves': 'wave', 'area_spells': 'area', 'tile_spells': 'tile'}
# fourth volume pieces that write words or a game's own UI prompt (by the pack's file name; never looked at)
WORDS = ('your_turn', 'turn_start', 'turn_end', 'well_played', 'press_here', 'out_of_mana', 'out_of_range', 'qte_',
         'stamina_empty', 'invalid_target', 'tutorial_hand', 'level_up_text', '_text', 'text_')
ELEMENT_WORDS = [
    ('fire', 'fire flame flames hellfire magma lava inferno ember embers burn burning blaze ash pyre phoenix'),
    ('ice', 'ice frost freeze frozen crystal water snow glacier tide aqua ocean hail frostbite'),
    ('energy', 'lightning storm thunder shock electric spark sparks volt energy plasma static tesla'),
    ('earth', 'earth nature poison toxic acid venom stone rock leaf leaves vine vines thorn thorns root roots sand mud '
              'plague sakura petal petals moss spore spores'),
    ('holy', 'holy light radiant celestial divine sacred gold golden angel angelic heal healing sun solar dawn'),
    ('death', 'shadow void dark necro necrotic blood bone bones abyss death curse cursed soul ghost doom skull '
              'umbral'),
    ('arcane', 'arcane lavender spirit mana magic astral cosmic rune runes mystic ethereal psychic'),
    ('physical', 'steel wind physical slash pierce blunt dust iron blade sword cleave'),
]
WORD_EL = {w: el for el, ws in ELEMENT_WORDS for w in ws.split()}
FIELDS = ['kind', 'id', 'name', 'set', 'eid', 'var', 'dir', 'src', 'shape', 'loop', 'frames', 'w', 'h', 'phases', 'ms',
          'durs', 'dx', 'dy', 'mx', 'my', 'element', 'hue', 'tag']
CAT_FIELDS = ['id', 'name', 'family', 'element', 'shape', 'size', 'frames', 'play']


# ----------------------------------------------------------------------------------------------------- choice
def name_element(*words):
    """the first element word of the pack's element field, the variant, then the effect id"""
    for w in words:
        for t in str(w or '').lower().replace('-', '_').split('_'):
            if t in WORD_EL:
                return WORD_EL[t]
    return ''


def hue_ok(el, h, s, lum):
    """does the measured colour (hue degrees, saturation 0..1, luma 0..255) fit the element of the name"""
    pale = s < 0.25
    return {
        'fire': (h <= 55 or h >= 330) and not pale,
        'ice': 160 <= h <= 255 or (pale and lum > 140),
        'energy': 35 <= h <= 80 or 160 <= h <= 300 or (pale and lum > 140),
        'earth': 45 <= h <= 175 or (15 <= h <= 50 and lum < 160),
        'holy': 30 <= h <= 80 or (pale and lum > 130),
        'death': h >= 230 or h <= 25 or lum < 90 or pale,
        'arcane': 215 <= h <= 345,
        'physical': pale or 15 <= h <= 60,
    }.get(el, False)


def tag_of(el, hue):
    if not el or not hue:
        return 'any'
    h, s, lum = hue
    return el if hue_ok(el, h, s, lum) else 'any'


def colour(frames):
    """(hue degrees, mean saturation, mean luma) of the kept pixels; the hue is the saturation-weighted circular mean"""
    import numpy as np
    px = np.concatenate([f[f[..., 3] > 0][:, :3] for f in frames if (f[..., 3] > 0).any()]).astype(np.float64) / 255.0
    if len(px) > 20000:
        px = px[:: len(px) // 20000 + 1]
    mx, mn = px.max(1), px.min(1)
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-9), 0)
    hs = np.array([colorsys.rgb_to_hsv(*p)[0] for p in px]) * 2 * math.pi
    x, y = float((np.cos(hs) * s).sum()), float((np.sin(hs) * s).sum())
    h = (math.degrees(math.atan2(y, x)) + 360) % 360
    lum = float((px @ np.array([0.299, 0.587, 0.114])).mean() * 255)
    return round(h), round(float(s.mean()), 2), round(lum)


def worded(eid):
    return any(w in eid for w in WORDS)


# ----------------------------------------------------------------------------------------------------- sources
class Src:
    def __init__(self, sset, eid, var, meta, path, fmt, shape):
        self.set, self.eid, self.var, self.meta, self.path, self.fmt, self.shape = sset, eid, var, meta, path, fmt, shape


def sha12(path):
    with open(path, 'rb') as fh:
        return hashlib.sha256(fh.read()).hexdigest()[:12]


def taken():
    """(digests, sources) the pair already holds: src columns of the other art_import tables, pair 36 / 27 / 29 sources"""
    digests, sources = set(), set()
    for p in sorted(glob.glob(os.path.join(ART, '*.csv'))):
        if os.path.abspath(p) == SPEC:
            continue
        with open(p, newline='', encoding='utf-8') as fh:
            rd = csv.DictReader(fh)
            for r in rd:
                v = (r.get('src') or '').strip()
                if len(v) == 12:
                    digests.add(v)
                if os.path.basename(p) in ('pack36_fx_sources.csv', 'pack27_sources.csv', 'pack29_sources.csv'):
                    sources.add((r.get('source') or '').strip())
    return digests, sources


MISSING = []
PNGS = {}                                   # tail of a path -> file, of every PNG under --src (discover fills it)


def sheet(base, f):
    p = os.path.join(base, f)
    return p if os.path.exists(p) else PNGS.get(f)


def png_index(srcs):
    """{relative tail 'oblique/32px/.../x.png': path} of every PNG under the --src folders"""
    out = {}
    for s in srcs:
        for base, _d, files in os.walk(s):
            for f in files:
                if f.lower().endswith('.png'):
                    p = os.path.join(base, f)
                    parts = p.replace(os.sep, '/').split('/')
                    for k in range(1, len(parts)):
                        out.setdefault('/'.join(parts[-k:]), p)
    return out


def discover(srcs):
    """-> [Src] of every candidate effect under the --src folders, in table order"""
    pngs = png_index(srcs)
    PNGS.clear()
    PNGS.update(pngs)
    found, seen = [], set()
    for s in srcs:
        for p in sorted(glob.glob(os.path.join(s, '**', 'metadata.json'), recursive=True)):
            d = json.load(open(p))
            sset = META_SETS.get(hashlib.sha256(str(d.get('pack', '')).encode()).hexdigest()[:12])
            if not sset:
                continue
            ef = d['effects']
            for e in (ef.values() if isinstance(ef, dict) else ef):
                v = (e.get('variants') or {}).get('oblique/32')
                if not v or (sset, e['id']) in seen:
                    continue
                seen.add((sset, e['id']))
                rel = v['files']['all']
                path = pngs.get(rel) or pngs.get(rel.split('/', 1)[-1])
                if not path:
                    MISSING.append('%s/%s' % (sset, e['id']))       # a sheet not fetched: reported, not taken
                    continue
                cat = str(e.get('category', '')) or 'fx'
                shape = SHAPE_M3.get(d.get('family') or e.get('family'), '') if sset == 'm3' else \
                    (cat[:-1] if cat.endswith('s') and cat != 'status' else cat)
                found.append(Src(sset, e['id'], '', e, path, 'meta', shape))
        for p in sorted(glob.glob(os.path.join(s, '**', 'catalog.json'), recursive=True)):
            root = os.path.dirname(p)
            for e in json.load(open(p)):
                if e['category'] not in CATALOG_CATS:
                    continue
                for var in e['variants']:
                    j = os.path.join(root, 'sheets', '64px', e['category'], e['id'], var, '%s_%s.json' % (e['id'], var))
                    if not os.path.exists(j) or ('mv', e['id'], var) in seen:
                        continue
                    seen.add(('mv', e['id'], var))
                    found.append(Src('mv', e['id'], var, e, j, 'catalog', CATALOG_CATS[e['category']]))
    order = {'m3': 0, 'm4': 1, 'mv': 2}
    found.sort(key=lambda x: (order[x.set], x.shape, x.eid, x.var))
    return found


def load(src):
    """-> (rows {row: [frames]}, anchor px, point px, ms, loop, directional, edge run of the pack frames)"""
    import numpy as np
    from PIL import Image
    import gen_pack27_fx as G
    from gen_pack36_fx import halve
    if src.fmt == 'meta':
        e = src.meta
        v = e['variants']['oblique/32']
        img = np.asarray(Image.open(src.path).convert('RGBA'))
        fw, fh, nrow = v['frame_w'], v['frame_h'], v['rows']
        assert img.shape[0] == fh * nrow and img.shape[1] % fw == 0, (src.eid, img.shape)
        raw = {r: [img[r * fh:(r + 1) * fh, i * fw:(i + 1) * fw] for i in range(img.shape[1] // fw)] for r in range(nrow)}
        ax, ay = v['anchor_tile']
        rows = {r: [G.clean_alpha(f) for f in fs] for r, fs in raw.items()}
        directional = bool(e.get('directions')) and nrow == 8
        return rows, (ax * 32, ay * 32), (0, 0), int(round(1000 / e['fps'])), bool(e.get('loop')), directional, \
            max(edge_run(f) for fs in rows.values() for f in fs)
    d = json.load(open(src.path))
    base = os.path.dirname(src.path)
    assert d['tile_size'] == 64, src.path
    fw, fh = d['frame_width'], d['frame_height']
    sheets = d['sheets']
    staged = isinstance(next(iter(sheets.values())), dict)
    parts = [sheets[k] for k in ('start', 'loop', 'end') if k in sheets] if staged else [sheets]
    nrow = len(d.get('directions') or []) or 1
    rows = {r: [] for r in range(nrow)}
    edge = 0
    for p in parts:
        if 'full' in p and sheet(base, p['full']):
            layers = ['full']
        else:
            layers = [ln for ln in d['layers'] if ln in p]
        merged = None
        for ln in layers:
            f = sheet(base, p[ln])
            assert f, (src.eid, src.var, 'sheet not found')
            a = np.asarray(Image.open(f).convert('RGBA'))
            if merged is None:
                merged = np.zeros_like(a)
            merged = G.over(merged, a, G.BACK_ALPHA if (ln == 'back' and 'front' in layers) else 1.0)
        assert merged.shape[0] == fh * nrow and merged.shape[1] % fw == 0, (src.path, merged.shape)
        for r in range(nrow):
            for i in range(merged.shape[1] // fw):
                f = halve(merged[r * fh:(r + 1) * fh, i * fw:(i + 1) * fw])
                edge = max(edge, edge_run(f))
                rows[r].append(f)
    piv = (int(round(d['pivot'][0] / 2)), int(round(d['pivot'][1] / 2)))
    ax, ay = d['anchor_tile']
    point = G.TILE_CENTRE if piv == (ax * 32 + 16, ay * 32 + 16) else G.FEET
    # a staged effect plays start, one loop and end: a one-shot here (the server resends nothing of it)
    loop = bool(d.get('loop')) and not (staged and 'end' in sheets)
    return rows, piv, point, int(round(1000 / d['fps'])), loop, nrow == 8, edge


# ----------------------------------------------------------------------------------------------------- cutting
def edge_run(f):
    """the longest run of art on the four borders of a frame"""
    import numpy as np
    a = f[..., 3] > 0
    best = 0
    for line in (a[0, :], a[-1, :], a[:, 0], a[:, -1]):
        if not line.any():
            continue
        d = np.diff(np.concatenate([[0], line.astype(np.int8), [0]]))
        best = max(best, int((np.nonzero(d == -1)[0] - np.nonzero(d == 1)[0]).max()))
    return best


def step(a, b):
    import numpy as np
    u = (a[..., 3] > 0) | (b[..., 3] > 0)
    if not u.any():
        return 0.0
    d = np.abs(a.astype(np.int16) - b.astype(np.int16)).max(axis=2) > 12
    return float((d & u).sum() / u.sum())


def loop_ratio(frames):
    steps = [step(frames[i - 1], frames[i]) for i in range(1, len(frames))]
    m = sum(steps) / len(steps) if steps else 0
    return step(frames[-1], frames[0]) / max(1e-6, m)


def cut(frames, ms, loop):
    """-> (frames, durations ms, why-out or ''): the frame rules of the docstring"""
    import numpy as np
    fr = [f for f in frames if f[..., 3].any()]
    if not fr:
        return [], [], 'no_art'
    keep, durs = [fr[0]], [ms]
    for f in fr[1:]:
        if np.array_equal(f, keep[-1]):
            durs[-1] += ms
        else:
            keep.append(f)
            durs.append(ms)
    if loop and len(keep) >= 4 and loop_ratio(keep) > LOOP_RATIO:
        best = None
        for k in range(len(keep), max(4, (len(keep) + 1) // 2) - 1, -1):
            if loop_ratio(keep[:k]) <= LOOP_RATIO:
                best = k
                break
        if best is None:
            return [], [], 'loop_jump'
        keep, durs = keep[:best], durs[:best]
    if len(keep) > MAX_PHASES:
        return [], [], 'too_long'
    return keep, durs, ''


def quality(frames, edge):
    """the art rules on the cut frames: '' or the reason it is out"""
    import clean_pack_dither as cpd
    import anim_fixes as AF
    px = [int((f[..., 3] > 0).sum()) for f in frames]
    if max(px) < MIN_PX:
        return 'no_art'
    if edge >= EDGE_RUN:
        return 'clipped'
    if sum(int(cpd.mesh_mask(f).sum()) for f in frames) >= MESH_PX:
        return 'mesh'
    stray = sum(int(AF.isolated_px(f).sum()) for f in frames)
    if stray >= STRAY_PX and stray / max(1, sum(px)) > STRAY_SHARE:
        return 'stray'
    return ''


def centroid(frames, anchor, point):
    """art centre relative to the target tile middle, px (the frames placed by anchor -> point)"""
    import numpy as np
    sx = sy = tot = 0.0
    for f in frames:
        ys, xs = np.nonzero(f[..., 3])
        sx += float((xs + 0.5).sum())
        sy += float((ys + 0.5).sum())
        tot += len(xs)
    return sx / tot - anchor[0] + point[0] - 16, sy / tot - anchor[1] + point[1] - 16


def border_runs(a):
    """the longest art run (alpha > 0) on the left, top, right and bottom border of one frame"""
    import numpy as np
    out = []
    for line in (a[:, 0], a[0, :], a[:, -1], a[-1, :]):
        d = np.diff(np.concatenate([[0], (line > 0).astype(np.int8), [0]]))
        out.append(int((np.nonzero(d == -1)[0] - np.nonzero(d == 1)[0]).max()) if line.any() else 0)
    return out


def strip_of(frames, anchor, point, ending, name):
    """-> (strip, w, h, dx, dy) or None when bigger than MAX_TILES. The canvas follows the art; a side where the art runs
    EDGE_RUN px or more along the border gets one more tile, so no art seems cut by the canvas (O733 rule `clipped`)"""
    import numpy as np
    import gen_pack27_fx as G
    left, top, right, bottom = G.bbox_tiles(frames, anchor, point)
    for _ in range(2):
        w, h = left + 1 + right, top + 1 + bottom
        if w > MAX_TILES or h > MAX_TILES:
            return None
        placed = [G.place(f, anchor, point, left, top, w, h, name) for f in frames]
        runs = [max(r) for r in zip(*[border_runs(c[..., 3]) for c in placed])]
        grow = [r >= EDGE_RUN for r in runs]
        if not any(grow):
            break
        left, top, right, bottom = left + grow[0], top + grow[1], right + grow[2], bottom + grow[3]
    else:
        w, h = left + 1 + right, top + 1 + bottom
        if w > MAX_TILES or h > MAX_TILES:
            return None
        placed = [G.place(f, anchor, point, left, top, w, h, name) for f in frames]
    n = len(frames) + (1 if ending else 0)
    strip = np.zeros((h * 32, w * 32 * n, 4), np.uint8)
    for i, c in enumerate(placed):
        strip[:, i * w * 32:(i + 1) * w * 32] = c
    return strip, w, h, right, bottom


def convert(src):
    """-> [(row, strip)] of one pack effect (8 for a heading set), or ([], reason)"""
    rows, anchor, point, ms, loop, directional, edge = load(src)
    heads = [(OUR_DIRS[i], rows[DIRS8.index(OUR_DIRS[i])]) for i in range(8)] if directional else [('', rows[0])]
    out = []
    for hd, fr in heads:
        frames, durs, why = cut(fr, ms, loop)
        why = why or quality(frames, edge)
        if why:
            return [], why
        mx = my = 0
        if not directional:
            cx, cy = centroid(frames, anchor, point)
            if math.hypot(cx, cy) > CENTRE_PX:
                mx, my = -int(round(cx)), -int(round(cy))
        pt = (point[0] + mx, point[1] + my)
        peak = max(int((f[..., 3] > 0).sum()) for f in frames)
        ending = not loop and (frames[-1][..., 3] > 0).sum() > END_SHARE * peak
        name = PREFIX[src.set] + src.eid + ('_' + src.var if src.var else '') + ('_' + hd if hd else '')
        got = strip_of(frames, anchor, pt, ending, name)
        if got is None:
            return [], 'too_big'
        strip, w, h, dx, dy = got
        if ending:
            durs = durs + [ms]
        el = name_element(src.meta.get('element'), src.var, src.eid)
        hue = colour(frames)
        r = dict(kind='effect', name=name, set=src.set, eid=src.eid, var=src.var, dir=hd,
                 src=sha12(src.path), shape=src.shape, loop=int(loop), frames=len(fr), w=w, h=h, phases=len(durs),
                 ms=ms, durs=';'.join(str(x) for x in durs) if any(x != ms for x in durs) else '', dx=dx, dy=dy,
                 mx=mx, my=my, element=el, hue='%d:%.2f:%d' % hue, tag=tag_of(el, hue))
        out.append((r, strip))
    return out, ''


STRIPS = None


def work(src):
    """one pack effect -> ([rows with the strip digest], why-out); the strips go to STRIPS as PNG (memory stays flat)"""
    from PIL import Image
    import numpy as np
    try:
        got, why = convert(src)
    except AssertionError as e:
        got, why = [], ('no_sheet' if 'sheet not found' in str(e) else 'error %s' % (e,))
    out = []
    for r, s in got:
        r['sum'] = digest(s)
        if STRIPS:
            Image.fromarray(np.ascontiguousarray(s)).save(os.path.join(STRIPS, r['name'] + '.png'), optimize=False)
        out.append(r)
    return out, why


def set_strips(path):
    global STRIPS
    STRIPS = path


# ----------------------------------------------------------------------------------------------------- table
def digest(strip):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    n = len(rows)
    w.writerow(dict(kind='total', id=n, name='effects_%d_%d' % (FIRST, FIRST + n - 1)))
    return buf.getvalue()


def sums_text(rows):
    return ''.join('%s  %s\n' % (r['sum'], r['name']) for r in rows)


def read_spec(path=None):
    with open(path or SPEC, newline='') as fh:
        return [r for r in csv.DictReader(fh) if r['kind'] != 'total']


def read_total(path=None):
    with open(path or SPEC, newline='') as fh:
        return [int(r['id']) for r in csv.DictReader(fh) if r['kind'] == 'total']


def read_sums(path=None):
    return dict(l.strip().split('  ', 1)[::-1] for l in open(path or SUMS))


def table_errors(rows):
    """rules of the table that hold without art"""
    errs = []
    ids = [int(r['id']) for r in rows]
    if ids != list(range(FIRST, FIRST + len(ids))):
        errs.append('effect ids are not %d.. in order' % FIRST)
    if ids and ids[-1] > 65535:
        errs.append('an effect id past 65535')
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names):
        errs.append('names are not unique')
    sets = {}
    for r in rows:
        if r['set'] not in PREFIX or not r['name'].startswith(PREFIX[r['set']]):
            errs.append('%s: set or prefix' % r['name'])
        if len(r['src']) != 12 or any(c not in '0123456789abcdef' for c in r['src']):
            errs.append('%s: src is not 12 hex' % r['name'])
        w, h, dx, dy, ph, ms = (int(r[k]) for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'))
        if not (1 <= w <= MAX_TILES and 1 <= h <= MAX_TILES and 0 <= dx < w and 0 <= dy < h):
            errs.append('%s: size or offset' % r['name'])
        durs = [int(x) for x in r['durs'].split(';')] if r['durs'] else [ms] * ph
        if not (1 <= ph <= MAX_PHASES + 1 and len(durs) == ph and all(d % ms == 0 for d in durs)):
            errs.append('%s: phases or durations' % r['name'])
        if r['tag'] not in ('any', r['element']) or (r['element'] and r['element'] not in WORD_EL.values()):
            errs.append('%s: tag' % r['name'])
        if r['dir']:
            if (int(r['mx']), int(r['my'])) != (0, 0):
                errs.append('%s: a heading is never moved' % r['name'])
            sets.setdefault(r['name'][:-len(r['dir']) - 1], []).append(r['dir'])
        elif math.hypot(int(r['mx']), int(r['my'])) and math.hypot(int(r['mx']), int(r['my'])) < CENTRE_PX - 2:
            errs.append('%s: moved although it stood within %d px' % (r['name'], CENTRE_PX))
        if worded(r['eid']) or r['shape'] == 'text':
            errs.append('%s: a picture of words' % r['name'])
    for base, ds in sets.items():
        if ds != OUR_DIRS:
            errs.append('%s: the headings are not %s in order' % (base, ' '.join(OUR_DIRS)))
    return errs


def pair_ok(dat):
    t = dat.effects
    return len(t) == NEED_EFFECTS and len(dat.missiles) == NEED_MISSILES and \
        all(any(s for s in t[i - 1].sprites) for i in range(FIXED[0], FIXED[1] + 1))


def import_spec(path, strips, rows):
    with open(path, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs', 'lua', 'blank'])
        for r in rows:
            w.writerow(['', 'effect', r['name'], os.path.join(strips, r['name'] + '.png'), r['w'], r['h'], r['phases'], r['ms'],
                        r['dx'], r['dy'], r['shape'], 'hard', r['durs'], '', ''])


CHUNK = 700                                 # effects per import_fx_art.py run (it holds every frame of a run in memory)


def build(dat, spr, out, srcs, write, jobs):
    import shutil
    from multiprocessing import Pool
    from datspr import Dat
    d = Dat(dat)
    if not pair_ok(d):
        sys.exit('refused: the input pair has %d effects and %d missiles; this step needs %d effects with %d..%d drawn and '
                 '%d missiles (pair 81 or the O734 fixes on it)' % (len(d.effects), len(d.missiles), NEED_EFFECTS,
                                                                   FIXED[0], FIXED[1], NEED_MISSILES))
    del d
    out = os.path.abspath(out)
    strips = os.path.join(out, 'strips')
    os.makedirs(strips, exist_ok=True)
    digests, sources = taken()
    cands, skipped = [], {}
    for s in discover(srcs):
        if s.set == 'mv' and ('%s/%s' % (s.eid, s.var) in sources):
            continue                                                  # pair 36 took this variant
        if worded(s.eid):
            skipped.setdefault('words', []).append(s.eid)
            continue
        if sha12(s.path) in digests:
            skipped.setdefault('in_pair', []).append(s.eid)
            continue
        cands.append(s)
    with Pool(max(1, jobs), initializer=set_strips, initargs=(strips,)) as p:
        res = p.map(work, cands, chunksize=2)
    rows = []
    for s, (got, why) in zip(cands, res):
        if why:
            skipped.setdefault(why.split(' ')[0], []).append('%s/%s%s' % (s.set, s.eid, '/' + s.var if s.var else ''))
            continue
        rows += got
    for i, r in enumerate(rows):
        r['id'] = FIRST + i
    errs = table_errors(rows)
    if errs:
        sys.exit('\n'.join(errs[:40]))
    print('candidates %d, effects %d (%d..%d)' % (len(cands), len(rows), FIRST, FIRST + len(rows) - 1))
    if MISSING:
        skipped.setdefault('no_sheet', []).extend(MISSING)
    for k, v in sorted(skipped.items()):
        print('  out %-10s %4d  %s' % (k, len(v), ' '.join(v[:6])))
    texts = {SPEC: spec_text([{k: r[k] for k in FIELDS} for r in rows]), SUMS: sums_text(rows)}
    if write:
        for p, t in texts.items():
            open(p, 'w', newline='').write(t)
            print('wrote', os.path.relpath(p, ROOT))
    else:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        if bad:
            sys.exit('the sheets do not give the committed %s (run with --write after a wanted change)' % ', '.join(
                os.path.relpath(p, ROOT) for p in bad))
    cur_dat, cur_spr, prev = dat, spr, None
    for k in range(0, len(rows), CHUNK):
        part = rows[k:k + CHUNK]
        spec = os.path.join(strips, 'import_%03d.csv' % (k // CHUNK))
        import_spec(spec, strips, part)
        last = k + CHUNK >= len(rows)
        step_out = out if last else os.path.join(out, 'part_%03d' % (k // CHUNK))
        cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', cur_dat, '--ours-spr', cur_spr,
               '--out-dir', step_out, '--spec', spec, '--expect-first-effect', str(FIRST + k), '--keep-donor-names']
        if subprocess.run(cmd).returncode:
            sys.exit('import_fx_art.py failed')
        if prev:
            shutil.rmtree(prev)
        prev = None if last else step_out
        cur_dat, cur_spr = os.path.join(step_out, 'Tibia.dat'), os.path.join(step_out, 'Tibia.spr')
        for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv'):             # this step's ids come from the table
            p = os.path.join(step_out, f)
            if os.path.exists(p):
                os.remove(p)
    return live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))


# ----------------------------------------------------------------------------------------------------- server files
def total_ms(r):
    return sum(int(x) for x in r['durs'].split(';')) if r['durs'] else int(r['ms']) * int(r['phases'])


def lua_text(rows):
    n = len(rows)
    L = ['-- GENERATED by client/tools/sprites/gen_wst_more_fx.py from art_import/more_pack_fx.csv (O735). Do not edit by hand.',
         '-- Effects of the purchased 32 px effect sets that no pair held before (docs/CREDITS.md), drawn by client pair %d:' % PAIR,
         '-- %d effects at the ids %d..%d. No projectile. A cone or a wave has 8 entries, <name>_n .. <name>_nw.' % (
             n, FIRST, FIRST + n - 1),
         '-- dx, dy: the send offset (the bottom-right tile of the art is the target tile + dx, dy); ms: the whole play;',
         '-- el: the element tag of server/data/spells/spell_fx_elements.csv. Sent only through data/lib/chaos_wst_more_fx.lua,',
         '-- which sends nothing while config.lua chaosClientPair is below %d.' % PAIR,
         'ChaosWstMoreFxIds = {',
         '\tpair = %d, first = %d, count = %d,' % (PAIR, FIRST, n),
         '\teffects = {']
    for r in rows:
        L.append('\t\t%s = {id = %s, dx = %s, dy = %s, ms = %d, el = "%s"},' % (
            r['name'], r['id'], r['dx'], r['dy'], total_ms(r), r['tag']))
    L += ['\t},', '}']
    return '\n'.join(L) + '\n'


def tags_text(rows):
    """spell_fx_elements.csv with this step's rows (id, name, element) in id order, the other rows as they are"""
    pre = tuple(PREFIX.values())
    with open(TAGS, encoding='utf-8', newline='') as fh:
        keep = [l for l in fh.read().splitlines() if not (l.split(',')[1:2] and l.split(',')[1].startswith(pre))]
    mine = ['%s,%s,%s' % (r['id'], r['name'], r['tag']) for r in rows]
    return '\n'.join(keep[:1] + sorted(keep[1:] + mine, key=lambda l: int(l.split(',')[0]))) + '\n'


def catalog_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=CAT_FIELDS, lineterminator='\n')
    w.writeheader()
    for r in rows:
        w.writerow(dict(id=r['id'], name=r['name'], family=r['set'] + ':' + r['shape'], element=r['tag'], shape=r['shape'] + (
            ':' + r['dir'] if r['dir'] else ''), size='%sx%s' % (r['w'], r['h']), frames=r['phases'],
            play='loop' if r['loop'] == '1' else 'once'))
    return buf.getvalue()


def ids(check, rows=None):
    rows = read_spec() if rows is None else rows
    want = {LUA: lua_text(rows), TAGS: tags_text(rows), CATALOG: catalog_text(rows)}
    if check:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_wst_more_fx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


# the seller's set name and file prefix, split so this file does not name them either (docs/CREDITS.md does)
PACK_WORDS = ['mega' + ' vfx', 'mega' + '_vfx', 'vol' + '. 3', 'vol' + '. 4']
PACK_RE = __import__('re').compile(r'\b' + 'w' + r'st(_|\b)')            # the author's prefix as tools/ci/check_names.py finds it


def names_pack(text):
    return any(w in text for w in PACK_WORDS) or bool(PACK_RE.search(text))


def check():
    rows = read_spec() if os.path.exists(SPEC) else []
    errs = table_errors(rows)
    n = len(rows)
    if not rows or read_total() != [n]:
        errs.append('more_pack_fx.csv: no rows, or the total row does not record the %d effects' % n)
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS)] if os.path.exists(SUMS) else []
    if sums != [r['name'] for r in rows]:
        errs.append('more_pack_fx.sums does not list the table names in order')
    for p in (SPEC, SUMS, LUA, CATALOG, os.path.abspath(__file__)):         # no pack name outside docs/CREDITS.md
        text = open(p, encoding='utf-8').read().lower() if os.path.exists(p) else ''
        if names_pack(text):
            errs.append('%s names the pack' % os.path.relpath(p, ROOT))
    for e in errs[:40]:
        print(e)
    bad = ids(True) if rows else 1
    print('more pack fx: %d effects %d..%d, %s' % (n, FIRST, FIRST + n - 1, 'OK' if not errs and not bad else 'PROBLEMS'))
    return 1 if errs or bad else 0


def live(dat_path, spr_path):
    """the pair holds each effect at its id: size, phases, durations and the pixels of the sums"""
    import numpy as np
    from datspr import Dat, Spr
    from import_vfx import render_back
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_spec()
    sums = read_sums()
    errs = []
    n = len(rows)
    if len(dat.effects) < FIRST + n - 1 or len(dat.missiles) != NEED_MISSILES:
        errs.append('the pair has %d effects and %d missiles' % (len(dat.effects), len(dat.missiles)))
    for r in rows if not errs else []:
        t = dat.effects[int(r['id']) - 1]
        ph, w, h = int(r['phases']), int(r['w']), int(r['h'])
        if (t.w, t.h, t.phases) != (w, h, ph):
            errs.append('%s: size or phases differ at %s' % (r['name'], r['id']))
            continue
        want = [int(x) for x in r['durs'].split(';')] if r['durs'] else [int(r['ms'])] * ph
        if t.anim and list(t.anim[3][0::2]) != want:
            errs.append('%s: durations differ' % r['name'])
        back = render_back(t, spr, 1)
        strip = np.concatenate([back[(f, 0, 0, 0)] for f in range(ph)], axis=1).copy()
        strip[strip[..., 3] == 0] = 0
        if digest(strip) != sums.get(r['name']):
            errs.append('%s: pixels differ from the sum' % r['name'])
    for e in errs[:40]:
        print(e)
    print('more pack fx live: %d effects at %d..%d, %s' % (n, FIRST, FIRST + n - 1, 'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'check', 'ids', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--src', action='append', default=[])
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--jobs', type=int, default=max(1, min(4, os.cpu_count() or 1)))
    a = ap.parse_args()
    if a.cmd == 'build':
        if not a.src or len(a.rest) != 3:
            sys.exit('build DAT SPR OUT_DIR --src DIR [--src DIR ...]')
        return build(a.rest[0], a.rest[1], a.rest[2], a.src, a.write, a.jobs)
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'live':
        if len(a.rest) != 2:
            sys.exit('live DAT SPR')
        return live(*a.rest)
    return check()


if __name__ == '__main__':
    sys.exit(main())
