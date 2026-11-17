#!/usr/bin/env python3
"""Animated decor flames from pixelfx (O623; joins client pair 74). Five fire props: the temple torch gets its flame, four new items.

    python3 -I gen_decor_flames.py render --pixelfx DIR OUT      # ONCE: the pinned pixelfx render in a sandbox -> OUT/raw/fire/*
    python3 -I gen_decor_flames.py fit OUT/raw                   # fit the raw sheets to the game -> art_import/decor_flames/*.png,
                                                                 #   decor_flames.csv, decor_flames.sums, server/data/items/decor_flames.csv
    python3 -I gen_decor_flames.py sheets OUT_DIR                # renders nothing: PNG contact sheets of the committed strips (never committed)
    python3 -I gen_decor_flames.py preview OUT.mp4 [--dat D --spr S]   # the five flames at 1x and 3x on a stone floor (never committed)
    python3 -I gen_decor_flames.py build DAT SPR OUT_DIR         # pair 73 -> OUT_DIR/Tibia.dat, Tibia.spr (the pair 74 step)
    python3 -I gen_decor_flames.py live DAT SPR                  # the pair holds the five flames at their ids, pixel for pixel
    python3 -I gen_decor_flames.py check                         # CI, no pair: table, sums, strips, manifest and the bar of every strip

Source: https://github.com/patch-gg/pixelfx at commit 5294518 (MIT, Copyright (c) 2026 Patch, Hugo Duprez; parts adapt Sprite
Fusion's open-source fire, MIT, Hugo Duprez, and rehan-remade's hollow-crown, MIT; docs/CREDITS.md). Owner 2026-11-17: yes. Its code
is untrusted: `render` copies only the files the five effects need (SOURCE_FILES, held to one sha256) into a sandbox folder and runs
node there with the permission model on (read the sandbox, write OUT only, no child process, no network). Nothing is installed.
`decor_flames_render.mjs` is our driver: the same render as pixelfx's tools/render.mjs --sheet, but the sheet holds the colour layer
only (the big additive halo of the light layer is left out: the game lights by the light flag of the item). pixelfx's gallery fonts
are not MIT and are never copied.

The fit (everything integer or seeded: the same bytes on every run), per effect:
  frames   12 of the render's loop, evenly spaced (the render is periodic, so frame 12 is frame 0 again and the loop closes);
           ms a frame from the table (83 to 120), the loop is a little quicker than the original.
  scale    the stable body (pixels solid in a quarter of the frames) is scaled by an area average (premultiplied) down to the canvas,
           never up; the canvas is the item: torch, brazier and campfire 2 x 2 tiles, candle and spirit flame 1 x 1. The body stands
           on the bottom row, the pivot of the effect on the middle column; what flies out of the canvas (the top of the smoke,
           sparks) is cut.
  alpha    0, 144 (one glow level: smoke and the soft rim of a flame) and 255, from the cut 0.22 / 0.5 of the original alpha
           (docs/SPRITE_STYLE.md); a transparent pixel carries no colour.
  noise    pieces of fewer than 3 pixels (sparks) are removed: no lone pixel or speck (SPRITE_STYLE).
  colour   the spirit flame is recoloured to a cold blue-white ("chama fria": hue turned to blue, lighter); every colour goes to the
           nearest of a theme palette of style_palettes.json (Lab, theme per row: cinderwrought for the fire, rimewraith for the
           cold flame), then to the KEEP most used of them over the whole strip (one palette a look, no flicker between frames).
Strips are the frames left to right, each w * 32 x h * 32, committed under art_import/decor_flames/ (our derivative of MIT code).

Pair step: client pair 74 = pair 73 plus this step. The four new items are appended by import_art_things.py (44560-44563, after the
44,559 items of pair 73; server id = client id + 4000), then the temple torch 44544 (2 x 2, one frame) is rewritten IN PLACE with the
12 phases (flags, size and server id stay; the entry gets the animator and the duration table). No outfit, effect or missile moves.
Needs numpy and Pillow (the fx venv of CI), node 18+ for `render`, ffmpeg for `preview`.
"""
import argparse
import csv
import hashlib
import io
import os
import shutil
import struct
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import style_check as sc  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
STRIPS = os.path.join(ART, 'decor_flames')
SPEC = os.path.join(ART, 'decor_flames.csv')
SUMS = os.path.join(ART, 'decor_flames.sums')
MANIFEST = os.path.join(ROOT, 'server', 'data', 'items', 'decor_flames.csv')
DRIVER = os.path.join(HERE, 'decor_flames_render.mjs')

PAIR = 74
PIXELFX_URL = 'https://github.com/patch-gg/pixelfx'
PIXELFX_COMMIT = '5294518'
# what `render` copies into the sandbox and what it must hash to (sorted relative paths, each: path, NUL, bytes, NUL)
SOURCE_FILES = (['LICENSE', 'package.json', 'tools/lib/fxlib.mjs', 'tools/lib/png.mjs', 'src/fx/fire/_lib.js']
                + ['src/core/%s.js' % n for n in ('act', 'actor', 'chain', 'color', 'font', 'fx', 'index', 'math', 'painter',
                                                  'particles', 'poses', 'rig', 'scene', 'shapes', 'sim')]
                + ['src/fx/fire/%s.js' % n for n in ('torch', 'brazier', 'campfire', 'candle', 'spirit-flame')])
SOURCE_SHA256 = 'bc7bcabd94e12c3cd1c18d4023d442b5edc233a1593bac1244cb9570db7e23d0'

CELL = 32
FRAMES = 12
KEEP = 26                    # colours a strip keeps (style_check allows 68 a cell)
SOLID, GLOW = 255, 144       # the two alpha levels
CUT_SOLID, CUT_GLOW = 0.5, 0.22
MIN_PIECE = 3                # pixels: a smaller piece is a spark or a speck and goes
FIRST = 44560                # after the 44,559 items of pair 73
TORCH = 44544                # the temple torch of pair 60: replaced in place
SERVER_OFFSET = 4000
EXPECT_ITEMS = 44559
MS_MIN, MS_MAX = 83, 120

THEMES = {'fire': 'cinderwrought', 'cold': 'rimewraith'}
# key, pixelfx id, client id, name, kind, tiles, ms, theme, dat flags, note
ROWS = [
    ('torch', 'fire/torch', TORCH, 'temple torch', 'stump', 2, 100, 'fire', 'bottom notwalkable notmoveable light:6:206',
     'the temple torch of pair 60, animated in place (mode replace: the server item stays)'),
    ('brazier', 'fire/brazier', 44560, 'flame brazier', 'stump', 2, 100, 'fire', 'bottom notwalkable notmoveable light:7:206',
     'an iron brazier on a tripod, solid'),
    ('campfire', 'fire/campfire', 44561, 'flame campfire', 'decor', 2, 100, 'fire', 'notmoveable light:7:206',
     'logs and a fire, walkable'),
    ('candle', 'fire/candle', 44562, 'flame candle', 'decor', 1, 120, 'fire', 'notmoveable light:3:206',
     'a wax candle in a brass dish'),
    ('spirit', 'fire/spirit-flame', 44563, 'flame cold spirit', 'decor', 1, 100, 'cold', 'notmoveable light:5:101',
     'the spirit flame recoloured to a cold blue-white'),
]
KEYS = [r[0] for r in ROWS]
FIELDS = ['key', 'fx', 'client_id', 'server_id', 'name', 'kind', 'w', 'h', 'frames', 'ms', 'mode', 'theme', 'flags', 'note']
MANIFEST_HEADER = ['client_id', 'server_id', 'key', 'kind', 'mode', 'name', 'size', 'otb_group', 'otb_flags', 'top_order',
                   'speed', 'light_level', 'light_color', 'extra']


def pieces():
    out = []
    for key, fx, cid, name, kind, tiles, ms, theme, flags, note in ROWS:
        out.append(dict(key=key, fx=fx, client_id=cid, server_id=cid + SERVER_OFFSET, name=name, kind=kind, w=tiles, h=tiles,
                        frames=FRAMES, ms=ms, mode='replace' if cid == TORCH else 'new', theme=theme, flags=flags, note=note))
    return out


def table_errors(rows):
    errs = []
    new = [r for r in rows if r['mode'] == 'new']
    ids = [int(r['client_id']) for r in new]
    if ids != list(range(FIRST, FIRST + len(ids))):
        errs.append('new client ids are not %d.. in order' % FIRST)
    if [r['key'] for r in rows if r['mode'] == 'replace'] != ['torch'] or \
            [int(r['client_id']) for r in rows if r['mode'] == 'replace'] != [TORCH]:
        errs.append('exactly the torch %d is replaced in place' % TORCH)
    if len({r['key'] for r in rows}) != len(rows) or len({r['fx'] for r in rows}) != len(rows):
        errs.append('keys or effects repeat')
    for r in rows:
        if r['theme'] not in THEMES:
            errs.append('%s: theme' % r['key'])
        if int(r['server_id']) != int(r['client_id']) + SERVER_OFFSET:
            errs.append('%s: server id is client id + %d' % (r['key'], SERVER_OFFSET))
        if int(r['w']) != int(r['h']) or int(r['w']) not in (1, 2):
            errs.append('%s: 1 x 1 or 2 x 2 tiles' % r['key'])
        if int(r['frames']) > 12 or int(r['frames']) < 6:
            errs.append('%s: 6 to 12 frames' % r['key'])
        if not MS_MIN <= int(r['ms']) <= MS_MAX:
            errs.append('%s: %d to %d ms a frame' % (r['key'], MS_MIN, MS_MAX))
        if r['mode'] == 'new' and not r['name'].startswith('flame '):
            errs.append('%s: a new item name starts with "flame " (a stock item of the same name would break loot)' % r['key'])
        if r['kind'] not in ('stump', 'decor'):
            errs.append('%s: kind' % r['key'])
    return errs


# ------------------------------------------------------------------------------------------------------------------ render
def source_digest(base):
    h = hashlib.sha256()
    for rel in sorted(SOURCE_FILES):
        with open(os.path.join(base, rel), 'rb') as f:
            h.update(rel.encode() + b'\0' + f.read() + b'\0')
    return h.hexdigest()


def cmd_render(pixelfx, out):
    head = subprocess.run(['git', '-C', pixelfx, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
    if not head.startswith(PIXELFX_COMMIT):
        sys.exit('%s is at %s, not the pinned commit %s' % (pixelfx, head or 'no git checkout', PIXELFX_COMMIT))
    missing = [f for f in SOURCE_FILES if not os.path.isfile(os.path.join(pixelfx, f))]
    if missing:
        sys.exit('missing in the pixelfx checkout: %s' % ', '.join(missing))
    got = source_digest(pixelfx)
    if SOURCE_SHA256 != 'PENDING' and got != SOURCE_SHA256:
        sys.exit('the pixelfx files differ from the pinned ones (sha256 %s, want %s)' % (got, SOURCE_SHA256))
    if SOURCE_SHA256 == 'PENDING':
        print('sha256 of the sources: %s (write it into SOURCE_SHA256)' % got)
    sandbox = os.path.join(out, 'sandbox')
    raw = os.path.join(out, 'raw')
    shutil.rmtree(sandbox, ignore_errors=True)
    for rel in SOURCE_FILES:
        dst = os.path.join(sandbox, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(pixelfx, rel), dst)
    shutil.copyfile(DRIVER, os.path.join(sandbox, 'tools', 'decor_flames_render.mjs'))
    os.makedirs(raw, exist_ok=True)
    cmd = ['node', '--permission', '--allow-fs-read=' + os.path.abspath(sandbox), '--allow-fs-write=' + os.path.abspath(raw),
           os.path.join('tools', 'decor_flames_render.mjs'), os.path.abspath(raw)] + [r[1] for r in ROWS]
    env = {'PATH': os.environ.get('PATH', '/usr/bin:/bin')}
    res = subprocess.run(cmd, cwd=sandbox, env=env, capture_output=True, text=True)
    sys.stdout.write(res.stdout)
    if res.returncode:
        sys.exit('render failed:\n' + res.stderr)
    print('raw sheets in %s; next: gen_decor_flames.py fit %s' % (raw, raw))


# ---------------------------------------------------------------------------------------------------------------------- fit
def load_raw(raw, fx):
    """([RGBA frame, ...] straight alpha, info dict) of one raw sheet of `render`"""
    import json
    name = fx.split('/')[1]
    info = json.load(open(os.path.join(raw, fx, name + '.json')))
    im = np.array(Image.open(os.path.join(raw, fx, name + '.png')).convert('RGBA'))
    fw, fh = info['frameSize']
    cols = info['columns']
    frames = [im[(i // cols) * fh:(i // cols + 1) * fh, (i % cols) * fw:(i % cols + 1) * fw] for i in range(info['frames'])]
    return frames, info


def pick_frames(n, k=FRAMES):
    return [i * n // k for i in range(k)]


def area_scale(a, s):
    """RGBA straight alpha -> scaled by s (< 1) with an area average on premultiplied colour"""
    h, w = a.shape[:2]
    nw, nh = max(1, int(round(w * s))), max(1, int(round(h * s)))
    af = a.astype(np.float32)
    al = af[..., 3:4] / 255.0
    pm = np.concatenate([af[..., :3] * al, af[..., 3:4]], axis=2)
    ch = [np.array(Image.fromarray(np.ascontiguousarray(pm[..., c]), 'F').resize((nw, nh), Image.BOX)) for c in range(4)]
    o = np.stack(ch, axis=2)
    alpha = o[..., 3:4] / 255.0
    rgb = np.where(alpha > 0, o[..., :3] / np.maximum(alpha, 1e-6), 0)
    return np.concatenate([np.clip(np.rint(rgb), 0, 255), np.clip(np.rint(o[..., 3:4]), 0, 255)], axis=2).astype(np.uint8)


def stable_box(frames, share=0.25):
    solid = np.stack([f[..., 3] >= 128 for f in frames]).mean(0) >= share
    ys, xs = np.nonzero(solid)
    return xs.min(), xs.max(), ys.min(), ys.max()


def hard_alpha(a):
    """alpha 0 / GLOW / SOLID by the cuts; a transparent pixel carries no colour"""
    al = a[..., 3] / 255.0
    out = a.copy()
    out[..., 3] = np.where(al >= CUT_SOLID, SOLID, np.where(al >= CUT_GLOW, GLOW, 0)).astype(np.uint8)
    out[out[..., 3] == 0, :3] = 0
    return out


def drop_pieces(a, minpix=MIN_PIECE):
    """remove 8-connected pieces of fewer than minpix visible pixels"""
    vis = a[..., 3] > 0
    h, w = vis.shape
    seen = np.zeros_like(vis)
    out = a.copy()
    for y0 in range(h):
        for x0 in range(w):
            if not vis[y0, x0] or seen[y0, x0]:
                continue
            stack, comp = [(y0, x0)], []
            seen[y0, x0] = True
            while stack:
                y, x = stack.pop()
                comp.append((y, x))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < h and 0 <= xx < w and vis[yy, xx] and not seen[yy, xx]:
                            seen[yy, xx] = True
                            stack.append((yy, xx))
            if len(comp) < minpix:
                for y, x in comp:
                    out[y, x] = 0
    return out


def cold_colour(rgb):
    """the cold blue-white of the spirit flame: hue turned from teal to blue, a little lighter"""
    import colorsys
    out = rgb.copy()
    for i, (r, g, b) in enumerate(rgb.tolist()):
        h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
        if s > 0.05:
            h = (h + 0.115) % 1.0
        l = l + (1 - l) * 0.34
        s = s * 0.85
        out[i] = [int(round(v * 255)) for v in colorsys.hls_to_rgb(h, l, s)]
    return out


def theme_palette(theme):
    t = sc.load_palettes()['themes'][THEMES[theme]]
    return np.array([sc.unhex(x) for x in t['palette']])


def snap_strip(strip, theme, recolour):
    """every visible pixel of the strip to the theme palette, then to the KEEP most used colours of that"""
    out = strip.copy()
    vis = out[..., 3] > 0
    rgb = out[vis][:, :3]
    if recolour:
        rgb = cold_colour(rgb)
    pal = theme_palette(theme)
    _d, idx = sc.nearest(rgb, pal)
    use = np.bincount(idx, minlength=len(pal))
    keep = np.argsort(-use, kind='stable')[:KEEP]
    kp = pal[np.sort(keep)]
    _d, idx2 = sc.nearest(pal[idx], kp)
    out[vis, :3] = kp[idx2]
    return out


def fit_one(frames, info, tiles, theme, recolour):
    """the strip (tiles*32 high, FRAMES * tiles*32 wide) of one raw sheet"""
    S = tiles * CELL
    x0, x1, y0, y1 = stable_box(frames)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    head = 6 if tiles == 1 else 10
    s = min(1.0, (S - 2) / bw, (S - 1 - head) / bh)
    px = info['pivot'][0]
    idx = pick_frames(len(frames))
    cells = []
    for i in idx:
        f = frames[i]
        g = area_scale(f, s) if s < 1.0 else f
        cx = int(round(px * s)) if s < 1.0 else px
        by = int(round((y1 + 1) * s)) if s < 1.0 else y1 + 1
        cell = np.zeros((S, S, 4), np.uint8)
        # paste so that pivot column -> S // 2 and the bottom of the stable body -> row S - 1 (inclusive)
        ox, oy = S // 2 - cx, S - by
        sy0, sx0 = max(0, -oy), max(0, -ox)
        dy0, dx0 = max(0, oy), max(0, ox)
        hh = min(g.shape[0] - sy0, S - dy0)
        ww = min(g.shape[1] - sx0, S - dx0)
        if hh > 0 and ww > 0:
            cell[dy0:dy0 + hh, dx0:dx0 + ww] = g[sy0:sy0 + hh, sx0:sx0 + ww]
        cells.append(drop_pieces(hard_alpha(cell)))
    strip = np.concatenate(cells, axis=1)
    return snap_strip(strip, theme, recolour), s


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def spec_text(rows):
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(FIELDS)
    for r in rows:
        w.writerow([r[k] for k in FIELDS])
    return out.getvalue()


def sums_text(strips):
    s = ''.join('%s  decor_flames/%s.png\n' % (digest(strips[k]), k) for k in KEYS)
    return s + 'pixelfx %s %s sources %s\n' % (PIXELFX_COMMIT, PIXELFX_URL, SOURCE_SHA256)


def things_text(rows, atlas_dir='decor_flames'):
    """import_art_things.py's things file for the NEW items (the torch is rewritten in place by `build`)"""
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id', 'extra'])
    for r in rows:
        if r['mode'] != 'new':
            continue
        w.writerow([r['key'], 'item', r['kind'], r['name'], '%s/%s' % (atlas_dir, r['key']), 0, 0, r['w'], r['h'], 1, r['frames'],
                    r['flags'], 'new', '', 'family=flame|ms=%s' % r['ms']])
    return out.getvalue()


def manifest_text(rows):
    """what import_art_things.py --manifest-out writes for the new items (its OTB table and rules)"""
    import import_art_things as imp
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(MANIFEST_HEADER)
    for r in rows:
        if r['mode'] != 'new':
            continue
        toks = {t.split(':')[0]: t.split(':')[1:] for t in r['flags'].split()}
        g, fl, top = imp.OTB[r['kind']]
        if 'notwalkable' in toks:
            fl |= imp.SOLID
        if int(r['frames']) > 1:
            fl |= imp.ANIM
        light = tuple(int(v) for v in toks['light']) if 'light' in toks else (0, 0)
        w.writerow([r['client_id'], r['server_id'], r['key'], r['kind'], 'new', r['name'], '%sx%s' % (r['w'], r['h']), g, fl, top,
                    0, light[0], light[1], 'family=flame|ms=%s' % r['ms']])
    return out.getvalue()


def cmd_fit(raw):
    rows = pieces()
    strips = {}
    for r in rows:
        frames, info = load_raw(raw, r['fx'])
        strip, s = fit_one(frames, info, int(r['w']), r['theme'], r['theme'] == 'cold')
        strips[r['key']] = strip
        print('%s: %d raw frames -> %d, scale %.2f, %d colours' % (r['key'], len(frames), FRAMES, s,
                                                                 len(np.unique(strip[strip[..., 3] > 0][:, :3], axis=0))))
    os.makedirs(STRIPS, exist_ok=True)
    for k, a in strips.items():
        with open(os.path.join(STRIPS, k + '.png'), 'wb') as f:
            f.write(png_bytes(a))
    for path, text in ((SPEC, spec_text(rows)), (SUMS, sums_text(strips)), (MANIFEST, manifest_text(rows))):
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    print('strips in', STRIPS)


def read_strip(key):
    a = np.array(Image.open(os.path.join(STRIPS, key + '.png')).convert('RGBA'))
    return a


def cells_of(strip, tiles):
    S = tiles * CELL
    return [strip[:, i * S:(i + 1) * S] for i in range(strip.shape[1] // S)]


# --------------------------------------------------------------------------------------------------------------------- bar
def step_size(a, b):
    """mean absolute difference of two RGBA cells over the pixels either shows"""
    m = (a[..., 3] > 0) | (b[..., 3] > 0)
    if not m.any():
        return 0.0
    return float(np.abs(a.astype(int) - b.astype(int))[m].mean())


def strip_problems(strip, row):
    """why a strip does not hold the bar ([] = fine)"""
    out = []
    tiles, n = int(row['w']), int(row['frames'])
    S = tiles * CELL
    if strip.shape != (S, S * n, 4):
        return ['size %s, want %dx%d' % (strip.shape[:2][::-1], S * n, S)]
    al = strip[..., 3]
    if set(np.unique(al).tolist()) - {0, GLOW, SOLID}:
        out.append('alpha is not 0 / %d / %d' % (GLOW, SOLID))
    if (strip[al == 0][:, :3] != 0).any():
        out.append('colour under transparent pixels')
    pal = theme_palette(row['theme'])
    cols = np.unique(strip[al > 0][:, :3], axis=0)
    inpal = {tuple(c) for c in pal.tolist()}
    if any(tuple(c) not in inpal for c in cols.tolist()):
        out.append('a colour is not of the theme palette %s' % THEMES[row['theme']])
    if len(cols) > KEEP:
        out.append('%d colours, at most %d' % (len(cols), KEEP))
    cells = cells_of(strip, tiles)
    if len(cells) != n:
        out.append('%d frames, want %d' % (len(cells), n))
        return out
    if len({c.tobytes() for c in cells}) < n:
        out.append('two frames are the same picture')
    steps = [step_size(cells[i], cells[(i + 1) % n]) for i in range(n)]
    if steps[-1] > 1.5 * max(steps[:-1]):
        out.append('the loop does not close: last step %.1f, largest other %.1f' % (steps[-1], max(steps[:-1])))
    if min(steps) == 0:
        out.append('a frame equals the next')
    if (al[:, :S] > 0).sum() < 40:
        out.append('almost empty')
    return out


def style_problems(strip, row):
    """style_check of every cell (effects mode: no outline demanded for light, alpha soft), each cell's own palette is the theme"""
    data = sc.load_palettes()
    pal = theme_palette(row['theme'])
    ref = data['light']['global']
    bad_all = []
    for i, c in enumerate(cells_of(strip, int(row['w']))):
        for k in range(0, c.shape[0], CELL):
            for j in range(0, c.shape[1], CELL):
                cell = c[k:k + CELL, j:j + CELL]
                if not (cell[..., 3] > 0).any():
                    continue
                bad, _warn = sc.judge(sc.measure(cell), pal, ref, data['thresholds'], soft=True)
                bad = [b for b in bad if not b.startswith('colours:') or 'at most' in b]
                bad_all += ['frame %d tile %d,%d: %s' % (i, k // CELL, j // CELL, b) for b in bad]
    return bad_all


def check(quiet=False):
    say = (lambda *a: None) if quiet else print
    errs = table_errors(pieces())
    spec = list(csv.DictReader(open(SPEC, encoding='utf-8')))
    if [[str(r[k]) for k in FIELDS] for r in pieces()] != [[r[k] for k in FIELDS] for r in spec]:
        errs.append('decor_flames.csv is not the table of the script')
    strips = {}
    for r in pieces():
        p = os.path.join(STRIPS, r['key'] + '.png')
        if not os.path.exists(p):
            errs.append('missing ' + os.path.relpath(p, ROOT))
            continue
        strips[r['key']] = read_strip(r['key'])
        errs += ['%s: %s' % (r['key'], e) for e in strip_problems(strips[r['key']], r)]
        errs += ['%s: style: %s' % (r['key'], e) for e in style_problems(strips[r['key']], r)]
    if len(strips) == len(ROWS):
        if open(SUMS, encoding='utf-8').read() != sums_text(strips):
            errs.append('decor_flames.sums is stale')
        if open(MANIFEST, encoding='utf-8').read() != manifest_text(pieces()):
            errs.append('server/data/items/decor_flames.csv is stale')
    for e in errs:
        print('FAIL', e)
    say('decor flames: %s' % ('OK' if not errs else '%d problems' % len(errs)))
    return 1 if errs else 0


# ------------------------------------------------------------------------------------------------------------------- pair
def layout(torch=TORCH, first=FIRST, expect=EXPECT_ITEMS):
    """{key: client id} of the pair step; tests use other ids on a small pair"""
    ids = {'torch': torch}
    for i, k in enumerate(k for k in KEYS if k != 'torch'):
        ids[k] = first + i
    return ids, first, expect


def build(dat, spr, out_dir, torch=TORCH, first=FIRST, expect=EXPECT_ITEMS, torch_tiles=2):
    import import_art_things as iat
    import import_donor_things as idt
    from datspr import Dat, Spr
    if os.path.abspath(os.path.dirname(dat)) == os.path.abspath(out_dir):
        sys.exit('out-dir must differ from the input dir')
    rows = pieces()
    work = tempfile.mkdtemp(prefix='decor_flames_', dir=os.path.dirname(os.path.abspath(out_dir)) or '.')
    try:
        os.makedirs(os.path.join(work, 'decor_flames'))
        for r in rows:
            shutil.copyfile(os.path.join(STRIPS, r['key'] + '.png'), os.path.join(work, 'decor_flames', r['key'] + '.png'))
        new_rows = [dict(r) for r in rows]
        ids, _f, _e = layout(torch, first, expect)
        for r in new_rows:
            r['client_id'] = ids[r['key']]
        things = os.path.join(work, 'things.csv')
        open(things, 'w', newline='').write(things_text(new_rows))
        mid = os.path.join(work, 'mid')
        argv = ['import_art_things.py', '--ours-dat', dat, '--ours-spr', spr, '--out-dir', mid, '--things', things,
                '--first-item', str(first), '--expect-items', str(expect), '--server-offset', str(SERVER_OFFSET)]
        old_argv = sys.argv
        sys.argv = argv
        try:
            iat.main()
        finally:
            sys.argv = old_argv
        replace_item(os.path.join(mid, 'Tibia.dat'), os.path.join(mid, 'Tibia.spr'), out_dir, torch,
                     read_strip('torch'), torch_tiles, FRAMES, int([r for r in rows if r['key'] == 'torch'][0]['ms']))
    finally:
        shutil.rmtree(work, ignore_errors=True)


def replace_item(dat, spr, out_dir, cid, strip, tiles, n, ms):
    """item cid rewritten IN PLACE as a tiles x tiles item of n phases drawn by strip: flags kept, entry rebuilt (animator,
    durations), new sprites appended (an identical record of the input is reused); every other entry byte-identical"""
    import import_art_things as iat
    import import_donor_things as idt
    from datspr import Dat, Spr, sprite_index
    import hashlib as hl
    od, ospr = Dat(dat), Spr(spr)
    d = od.data
    ours = idt.parse_dat(d, idt.OUR_KINDS)
    items = {t.id: t for t in ours['item']}
    t = items.get(cid)
    if t is None:
        sys.exit('item %d is not in the input dat' % cid)
    if idt.entry_bytes('item', t.flags, t.groups) != d[t.raw[0]:t.raw[1]] or len(t.groups) != 1:
        sys.exit('item %d: one group that round-trips is expected; refusing' % cid)
    S = tiles * CELL
    cells = cells_of(strip, tiles)
    assert len(cells) == n and cells[0].shape == (S, S, 4)
    m = ospr.m
    have = {}
    for sid in range(ospr.count, 0, -1):
        o = int(ospr.offs[sid - 1])
        if o:
            have[hl.md5(m[o:o + 5 + struct.unpack_from('<H', m, o + 3)[0]]).digest()] = sid
    newrecs = []
    shp = iat.Shape(tiles, tiles, 1, 1, 1, n)
    sids = [0] * (tiles * tiles * n)
    for ph, cell in enumerate(cells):
        for (ww, hh), tile in iat.tiles_of(cell, tiles, tiles).items():
            rec = iat.encode_sprite(tile)
            if rec is None:
                continue
            h = hl.md5(rec).digest()
            if h not in have:
                newrecs.append(rec)
                have[h] = ospr.count + len(newrecs)
            sids[sprite_index(shp, 0, 0, 0, 0, ph, ww, hh)] = have[h]
    g = dict(gtype=0, w=tiles, h=tiles, exact=CELL * tiles, layers=1, px=1, py=1, pz=1, phases=n, anim=((1, 0, 0), (ms,) * (2 * n)),
             sprites=tuple(sids))
    entry = idt.entry_bytes('item', t.flags, [g])
    out = bytearray(d[:t.raw[0]]) + entry + d[t.raw[1]:]
    os.makedirs(out_dir, exist_ok=True)
    dat_path, spr_path = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
    open(dat_path, 'wb').write(out)
    idt.write_spr(spr_path, ospr.signature, m, ospr.count, newrecs)
    md, ms_ = Dat(dat_path), Spr(spr_path)
    assert md.counts == od.counts and ms_.count == ospr.count + len(newrecs)
    nt = idt.parse_dat(bytes(out), idt.OUR_KINDS)
    for cat in idt.CATS:
        assert len(nt[cat]) == len(ours[cat])
        for to, tn in zip(ours[cat], nt[cat]):
            if cat == 'item' and to.id == cid:
                assert tn.flags == to.flags, 'flags changed'
                continue
            assert bytes(out[tn.raw[0]:tn.raw[1]]) == d[to.raw[0]:to.raw[1]], (cat, to.id, 'entry changed')
    print('item %d rewritten in place: %dx%d, %d phases of %d ms, %d new sprite records; every other entry byte-identical'
          % (cid, tiles, tiles, n, ms, len(newrecs)))


def live(dat, spr, torch=TORCH, first=FIRST, torch_tiles=2):
    """the pair holds the five flames at their ids, every phase and tile pixel for pixel; [] problems = fine"""
    import import_art_things as iat
    import import_donor_things as idt
    from datspr import Dat, Spr, sprite_index
    d, s = Dat(dat), Spr(spr)
    ours = idt.parse_dat(d.data, idt.OUR_KINDS)
    items = {t.id: t for t in ours['item']}
    ids, _f, _e = layout(torch, first)
    bad = []
    for r in pieces():
        cid = ids[r['key']]
        t = items.get(cid)
        tiles = int(r['w']) if r['key'] != 'torch' else torch_tiles
        if t is None:
            bad.append('%s: item %d is not in the pair' % (r['key'], cid))
            continue
        g = t.groups[0]
        n = int(r['frames'])
        if (len(t.groups), g['w'], g['h'], g['layers'], g['px'], g['py'], g['phases']) != (1, tiles, tiles, 1, 1, 1, n):
            bad.append('%s: group %s' % (r['key'], {k: g[k] for k in ('w', 'h', 'layers', 'px', 'py', 'phases')}))
            continue
        if g['anim'] is None or set(g['anim'][1]) != {int(r['ms'])}:
            bad.append('%s: durations are not %s ms' % (r['key'], r['ms']))
        shp = iat.Shape(tiles, tiles, 1, 1, 1, n)
        cells = cells_of(read_strip(r['key']), tiles)
        for ph, cell in enumerate(cells):
            for (ww, hh), tile in iat.tiles_of(cell, tiles, tiles).items():
                sid = g['sprites'][sprite_index(shp, 0, 0, 0, 0, ph, ww, hh)]
                px = s.sprite(sid) if sid else None
                want = iat.decoded(tile)
                if px is None:
                    ok = not (want[..., 3] > 0).any()
                else:
                    ok = bool((px == want).all())
                if not ok:
                    bad.append('%s: phase %d tile %d,%d differs from the strip' % (r['key'], ph, ww, hh))
    return bad


# ----------------------------------------------------------------------------------------------------------- sheets, preview
def cmd_sheets(out):
    os.makedirs(out, exist_ok=True)
    for r in pieces():
        a = read_strip(r['key'])
        bg = np.zeros(a.shape, np.uint8)
        bg[...] = (30, 28, 34, 255)
        im = Image.fromarray(bg)
        im.alpha_composite(Image.fromarray(a))
        im.resize((a.shape[1] * 3, a.shape[0] * 3), Image.NEAREST).convert('RGB').save(os.path.join(out, r['key'] + '.png'))
    print('sheets in', out)


def stone_floor(w, h, seed=3):
    rng = np.random.RandomState(seed)
    base = np.zeros((h, w, 3), np.int32)
    for ty in range(0, h, CELL):
        for tx in range(0, w, CELL):
            v = 44 + rng.randint(-5, 6)
            base[ty:ty + CELL, tx:tx + CELL] = (v, v - 2, v + 4)
    base += rng.randint(-4, 5, (h, w, 1))
    base[::CELL, :] -= 14
    base[:, ::CELL] -= 14
    return np.clip(base, 0, 255).astype(np.uint8)


def cmd_preview(out, dat=None, spr=None):
    pad = 12
    shown = [(r['key'], read_strip(r['key']), int(r['w']), int(r['ms'])) for r in pieces()]
    old = None
    if dat and spr:
        from datspr import Dat, Spr
        from fxlib import render_item
        old = render_item(Dat(dat), Spr(spr), TORCH).convert('RGBA')
    W1 = sum(t * CELL + pad for _k, _a, t, _m in shown) + pad + (CELL * 2 + pad if old else 0)
    W3 = W1 * 3
    H = (CELL * 2 + pad) + (CELL * 2 * 3 + pad)
    Wc = max(W1, W3)
    floor = stone_floor(Wc, H)
    frames = []
    for f in range(FRAMES * 4):
        im = Image.fromarray(np.dstack([floor, np.full(floor.shape[:2], 255, np.uint8)]))
        x = pad
        for _k, a, t, ms in shown:
            c = Image.fromarray(a[:, (f % FRAMES) * t * CELL:((f % FRAMES) + 1) * t * CELL])
            im.alpha_composite(c, (x, pad + (2 - t) * CELL))
            im.alpha_composite(c.resize((c.width * 3, c.height * 3), Image.NEAREST), (x * 3 - pad * 2, CELL * 2 + 2 * pad + (2 - t) * CELL * 3))
            x += t * CELL + pad
        if old:
            im.alpha_composite(old, (x, pad + CELL))
        frames.append(np.array(im.convert('RGB')))
    h, w = frames[0].shape[:2]
    w2, h2 = w + w % 2, h + h % 2
    raw = b''.join(np.pad(f, ((0, h2 - h), (0, w2 - w), (0, 0))).tobytes() for f in frames)
    cmd = ['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (w2, h2), '-r', '9', '-i', '-',
           '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-crf', '18', '-movflags', '+faststart', out]
    subprocess.run(cmd, input=raw, check=True)
    print('preview', out, '%dx%d' % (w2, h2))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('render')
    p.add_argument('--pixelfx', required=True)
    p.add_argument('out')
    p = sub.add_parser('fit')
    p.add_argument('raw')
    p = sub.add_parser('sheets')
    p.add_argument('out')
    p = sub.add_parser('preview')
    p.add_argument('out')
    p.add_argument('--dat')
    p.add_argument('--spr')
    p = sub.add_parser('build')
    p.add_argument('dat')
    p.add_argument('spr')
    p.add_argument('out')
    p = sub.add_parser('live')
    p.add_argument('dat')
    p.add_argument('spr')
    sub.add_parser('check')
    a = ap.parse_args(argv)
    if a.cmd == 'render':
        cmd_render(a.pixelfx, a.out)
    elif a.cmd == 'fit':
        cmd_fit(a.raw)
    elif a.cmd == 'sheets':
        cmd_sheets(a.out)
    elif a.cmd == 'preview':
        cmd_preview(a.out, a.dat, a.spr)
    elif a.cmd == 'build':
        build(a.dat, a.spr, a.out)
    elif a.cmd == 'live':
        bad = live(a.dat, a.spr)
        for b in bad:
            print('FAIL', b)
        print('decor flames live: %s' % ('OK' if not bad else '%d problems' % len(bad)))
        return 1 if bad else 0
    elif a.cmd == 'check':
        return check()
    return 0


if __name__ == '__main__':
    sys.exit(main())
