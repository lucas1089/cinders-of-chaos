#!/usr/bin/env python3
"""Style checker for new sprites: do they match the owner's art? (docs/SPRITE_STYLE.md is the guide.)

    python3 -I style_check.py check FILE.png [...] --theme NAME [--cell 32] [--soft] [--key RRGGBB] [--verbose]
    python3 -I style_check.py check FILE.png [...] --palette PAL.png|PAL.txt [...]
    python3 -I style_check.py snap IN.png OUT.png --theme NAME     # move every opaque pixel to the nearest theme colour
    python3 -I style_check.py build-palettes [--check]             # -> style_palettes.json from the owner sheets
    python3 -I style_check.py report                               # the measured facts of docs/SPRITE_STYLE.md

Run it with numpy and Pillow (CI: the pinned /tmp/fxenv, the same pins as the art generators).

Reference art: only the owner's own art. The themes are the seven gear set sheets of art_import/gear_sets/ (the owner's
sheets, "made for us", gen_gear_sets_art.py); `report` also measures the owner art of pair 26 (art_import/owner_art/)
and the frame counts of our generated effects. No purchased pack and nothing else from the Drive is read: allowed packs
are added after the licence audit.

`check` cuts every PNG into cells of --cell px (default 32; a sheet is a grid of sprites) and checks each cell that
holds art. A failed check is a reason; a cell with a reason fails, and the run exits 1 when any cell fails.
  size        the image is a whole number of cells (grid alignment)
  background  fully transparent, or one key colour (an RGB image, or --key) with no near-key fringe pixels
  scale       the art is not upscaled (every 2x2 block one colour): draw at 1:1, one art pixel = one screen pixel
  alpha       no semi-transparent pixels (--soft, for effects and glows: allowed, but none below alpha 12)
  colours     the number of colours of a cell lies in the owners' range (flat or noisy art fails)
  palette     the mean CIE76 distance of the non-outline pixels to the palette, and the share of far pixels
  outline     the rim (opaque pixels next to transparency) is mostly near-black, and the outline is one pixel thick
  light       the rim light does not come from the side opposite the reference (top, a little left); a weak
              disagreement is a warning
  noise       no lone pixels, two-pixel specks or one-pixel holes; inside the body not too many single-pixel luma
              spikes and not too many pixels whose colour no neighbour shares (speckle)
Thresholds and palettes come from style_palettes.json; build-palettes measures them on the owner sheets (every owner
cell passes its own theme by construction, with a margin) and --check (CI) rebuilds and compares the file.
Deterministic: numpy and Pillow only.
"""
import argparse
import collections
import csv
import json
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
GEAR = os.path.join(ART, 'gear_sets')
OWNER = os.path.join(ART, 'owner_art')
PALETTES = os.path.join(HERE, 'style_palettes.json')

CELL = 32
DARK = 24.0          # luma below this is an outline colour
SPIKE = 12.0         # a body pixel brighter or darker than all four neighbours by this much is a spike
FAR_DE = 12.0        # CIE76 distance of a "far" pixel (clearly another colour)
SOFT_MIN = 12        # soft alpha: nothing fainter (gen_owner_art.ALPHA_MIN)
FRINGE = 60.0        # RGB distance of a near-key fringe pixel
# the themes: sheet key -> the owner's words (gen_gear_sets_art.SETS)
THEMES = collections.OrderedDict([
    ('cinderwrought', 'fire and ember'),
    ('wyrmscale', 'green dragon'),
    ('rimewraith', 'teal frost, spectral'),
    ('azurevigil', 'blue and gold paladin'),
    ('bloodmoon', 'crimson, blood'),
    ('gildcrown', 'gold'),
    ('blightfang', 'dark green, venom'),
])


# ---------------------------------------------------------------------------------------------------- pixels and colour
def luma(rgb):
    rgb = np.asarray(rgb, dtype=np.float64)
    return 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]


def to_lab(rgb):
    """sRGB (0..255, any shape ..., 3) -> CIELAB (D65)."""
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = (c @ m.T) / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0, 500.0 * (f[..., 0] - f[..., 1]), 200.0 * (f[..., 1] - f[..., 2])], -1)


def hexc(rgb):
    return '#%02x%02x%02x' % tuple(int(v) for v in rgb[:3])


def unhex(s):
    s = s.strip().lstrip('#')
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def nearest(rgb, pal_rgb):
    """(distance, index) of the nearest palette colour (CIE76) for every row of rgb (N, 3)."""
    lab, plab = to_lab(rgb), to_lab(pal_rgb)
    d = np.sqrt(((lab[:, None, :] - plab[None, :, :]) ** 2).sum(-1))
    return d.min(1), d.argmin(1)


def erode(m):
    """4-neighbour erosion; outside the array counts as empty."""
    p = np.pad(m, 1)
    return m & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]


def components(m):
    """sizes of the 8-connected parts of a boolean mask."""
    seen = np.zeros_like(m)
    h, w = m.shape
    out = []
    for y0, x0 in zip(*np.nonzero(m)):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        stack, n = [(y0, x0)], 0
        while stack:
            y, x = stack.pop()
            n += 1
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and m[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
        out.append(n)
    return out


def load(path, key=None):
    """RGBA uint8 array of a PNG and a background note. A key colour (RGB image, or --key) becomes transparent.
    Returns (rgba, problems)."""
    im = Image.open(path)
    problems = []
    has_alpha = im.mode in ('RGBA', 'LA', 'PA') or (im.mode == 'P' and 'transparency' in im.info)
    a = np.array(im.convert('RGBA'))
    if key is None and has_alpha and (a[..., 3] == 0).any():
        return a, problems
    if key is None:   # no transparency: the key is the top-left pixel
        key = tuple(int(v) for v in a[0, 0, :3])
    key = np.array(key, dtype=np.int64)
    rgb = a[..., :3].astype(np.int64)
    exact = (rgb == key).all(-1)
    dist = np.sqrt(((rgb - key) ** 2).sum(-1))
    fringe = (~exact) & (dist <= FRINGE) & (a[..., 3] > 0)
    if not exact.any():
        problems.append('background: no transparent pixel and no key colour %s' % hexc(key))
    if fringe.any():
        problems.append('background: %d pixels close to the key colour %s but not it (a soft or dirty key edge)'
                        % (int(fringe.sum()), hexc(key)))
    a = a.copy()
    a[exact, 3] = 0
    return a, problems


def upscaled(a):
    """True when the art is drawn in 2x2 blocks (an upscaled sprite)."""
    h, w = a.shape[:2]
    if h % 2 or w % 2 or not (a[..., 3] > 0).any():
        return False
    b = a.astype(np.int64)
    return bool((b[0::2, 0::2] == b[1::2, 0::2]).all() and (b[0::2, 0::2] == b[0::2, 1::2]).all()
                and (b[0::2, 0::2] == b[1::2, 1::2]).all())


def cells(a, size):
    """(row, col, cell) of every cell that holds art."""
    h, w = a.shape[:2]
    for r in range(h // size):
        for c in range(w // size):
            cell = a[r * size:(r + 1) * size, c * size:(c + 1) * size]
            if (cell[..., 3] > 0).any():
                yield r, c, cell


# ------------------------------------------------------------------------------------------------------------ measures
def rim_light(L, body):
    """(x, y) of the rim light: mean luma of the body pixels within 2 px of its left edge minus its right edge, and of
    its top edge minus its bottom edge (body = the pixels inside the outline). (+, +) = lit from the top left."""
    h, w = body.shape
    p = np.pad(body, 2)

    def side(dy, dx):
        near = np.zeros_like(body)
        for k in (1, 2):
            near |= ~p[2 + dy * k:2 + dy * k + h, 2 + dx * k:2 + dx * k + w]
        s = body & near
        return float(L[s].mean()) if s.sum() >= 3 else None

    t, b, lf, rt = side(-1, 0), side(1, 0), side(0, -1), side(0, 1)
    x = (lf - rt) if lf is not None and rt is not None else 0.0
    y = (t - b) if t is not None and b is not None else 0.0
    return x, y


def measure(cell):
    """The style measures of one cell (RGBA uint8)."""
    al = cell[..., 3]
    vis = al > 0
    solid = al >= 128
    L = luma(cell[..., :3])
    body = erode(solid)
    rim = solid & ~body
    ring2 = body & ~erode(body)
    inner = erode(body)
    dark = L < DARK
    nb = np.zeros(vis.shape, dtype=np.int64)
    p = np.pad(vis, 1)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            if dy != 1 or dx != 1:
                nb += p[dy:dy + vis.shape[0], dx:dx + vis.shape[1]]
    Lp = np.pad(L, 1, mode='edge')
    d = [L - Lp[:-2, 1:-1], L - Lp[2:, 1:-1], L - Lp[1:-1, :-2], L - Lp[1:-1, 2:]]
    spike = inner & (np.all([x > SPIKE for x in d], 0) | np.all([x < -SPIKE for x in d], 0))
    lx, ly = rim_light(L, body)
    rgb = cell[..., :3].astype(np.int64)
    code = rgb[..., 0] * 65536 + rgb[..., 1] * 256 + rgb[..., 2]
    cp = np.pad(code, 1, constant_values=-1)
    alike = (code == cp[:-2, 1:-1]) | (code == cp[2:, 1:-1]) | (code == cp[1:-1, :-2]) | (code == cp[1:-1, 2:])
    vp = np.pad(vis, 1)
    hole = ~vis & vp[:-2, 1:-1] & vp[2:, 1:-1] & vp[1:-1, :-2] & vp[1:-1, 2:]
    return {
        'pixels': int(vis.sum()),
        'semi': int(((al > 0) & (al < 255)).sum()),
        'faint': int(((al > 0) & (al < SOFT_MIN)).sum()),
        'colours': int(len(np.unique(cell[vis][:, :3], axis=0))),
        'outline_dark': float((dark & rim).sum() / max(rim.sum(), 1)),
        'ring2_dark': float((dark & ring2).sum() / max(ring2.sum(), 1)),
        'inner_dark': float((dark & inner).sum() / max(inner.sum(), 1)),
        'outline_luma': float(L[rim].mean()) if rim.any() else 0.0,
        'light': (lx, ly),
        'isolated': int((vis & (nb == 0)).sum()),
        'specks': int(sum(1 for n in components(vis) if n <= 2)),
        'spike': float(spike.sum() / inner.sum()) if inner.sum() >= 16 else 0.0,
        'single': float((inner & ~alike).sum() / inner.sum()) if inner.sum() >= 16 else 0.0,
        'holes': int(hole.sum()),
        # the pixels the palette check reads: every visible pixel but the dark outline
        'paint': cell[vis & ~(rim & dark)][:, :3],
    }


def palette_fit(paint, pal_rgb):
    """(mean distance, share of far pixels) of the painted pixels to a palette."""
    if not len(paint):
        return 0.0, 0.0
    d, _i = nearest(paint, pal_rgb)
    return float(d.mean()), float((d > FAR_DE).mean())


def light_of(ms, ref):
    """(projection on the reference direction, angle away from it in degrees, strength) of a cell's rim light."""
    v = np.array(ms['light'], dtype=np.float64)
    r = np.array(ref, dtype=np.float64)
    r = r / max(np.hypot(*r), 1e-9)
    mag = float(np.hypot(*v))
    proj = float(v @ r)
    ang = float(np.degrees(np.arccos(np.clip(proj / mag, -1, 1)))) if mag > 1e-9 else 0.0
    return proj, ang, mag


def judge(ms, pal_rgb, ref, thr, soft=False):
    """(reasons, warnings) of one cell's measures against a palette, a light reference and the thresholds."""
    bad, warn = [], []
    if not soft and ms['semi']:
        bad.append('alpha: %d semi-transparent pixels (only 0 or 255; --soft for effects)' % ms['semi'])
    if soft and ms['faint']:
        bad.append('alpha: %d stray pixels fainter than alpha %d' % (ms['faint'], SOFT_MIN))
    if ms['colours'] < thr['colours_min']:
        bad.append('colours: %d, at least %d (flat, no shading steps)' % (ms['colours'], thr['colours_min']))
    if ms['colours'] > thr['colours_max']:
        bad.append('colours: %d, at most %d (gradient or noise; snap to the theme)'
                   % (ms['colours'], thr['colours_max']))
    de, far = palette_fit(ms['paint'], pal_rgb)
    if de > thr['palette_mean_de_max'] or far > thr['palette_far_max']:
        bad.append('palette: mean distance %.1f (max %.1f), %.0f%% far pixels (max %.0f%%); snap to the theme'
                   % (de, thr['palette_mean_de_max'], far * 100, thr['palette_far_max'] * 100))
    if not soft:
        if ms['outline_dark'] < thr['outline_dark_min']:
            bad.append('outline: %.0f%% of the rim is near-black (luma < %d), at least %.0f%%'
                       % (ms['outline_dark'] * 100, DARK, thr['outline_dark_min'] * 100))
        if ms['ring2_dark'] > thr['ring2_dark_max']:
            bad.append('outline: %.0f%% of the second ring is near-black too (max %.0f%%): one pixel thick'
                       % (ms['ring2_dark'] * 100, thr['ring2_dark_max'] * 100))
    proj, ang, mag = light_of(ms, ref)
    if proj < thr['light_proj_min']:
        bad.append('light: the rim is lit from the opposite side (%.0f along the reference, min %.0f)'
                   % (proj, thr['light_proj_min']))
    elif ang > 90 and mag >= thr['light_warn_mag']:
        warn.append('light: %.0f degrees away from the reference (top, a little left)' % ang)
    if ms['isolated'] > thr['isolated_max'] or ms['specks'] > thr['specks_max']:
        bad.append('noise: %d lone pixels (max %d), %d specks of 1-2 pixels (max %d)'
                   % (ms['isolated'], thr['isolated_max'], ms['specks'], thr['specks_max']))
    if ms['holes'] > thr['holes_max']:
        bad.append('noise: %d one-pixel holes in the body (max %d)' % (ms['holes'], thr['holes_max']))
    if ms['spike'] > thr['spike_max']:
        bad.append('noise: %.0f%% of the body are single-pixel spikes (max %.0f%%): unreadable at 32 px'
                   % (ms['spike'] * 100, thr['spike_max'] * 100))
    if ms['single'] > thr['single_max']:
        bad.append('noise: %.0f%% of the body pixels share their colour with no neighbour (max %.0f%%): '
                   'speckle, not shading' % (ms['single'] * 100, thr['single_max'] * 100))
    return bad, warn


# ----------------------------------------------------------------------------------------------------- build-palettes
FAMILIES = (('red', 345, 15), ('orange', 15, 40), ('yellow', 40, 70), ('green', 70, 165), ('teal', 165, 195),
            ('blue', 195, 255), ('violet', 255, 345))


def family(rgb):
    """hue family of a colour: outline (near-black), grey (low saturation) or a hue name."""
    r, g, b = (v / 255.0 for v in rgb)
    mx, mn = max(r, g, b), min(r, g, b)
    if luma(rgb) < DARK:
        return 'dark'
    if mx - mn < 0.12 or (mx - mn) / mx < 0.2:
        return 'grey'
    if mx == r:
        h = (60 * (g - b) / (mx - mn)) % 360
    elif mx == g:
        h = 60 * (b - r) / (mx - mn) + 120
    else:
        h = 60 * (r - g) / (mx - mn) + 240
    for name, lo, hi in FAMILIES:
        if (lo <= h < hi) if lo < hi else (h >= lo or h < hi):
            return name
    return 'red'


def sheet(key):
    return np.array(Image.open(os.path.join(GEAR, key + '.png')).convert('RGBA'))


def r2(v):
    return round(float(v), 2)


def build():
    """style_palettes.json as a dict, measured on the owner sheets."""
    themes, per = collections.OrderedDict(), {}
    for key, words in THEMES.items():
        a = sheet(key)
        vis = a[..., 3] > 0
        cols, counts = np.unique(a[vis][:, :3], axis=0, return_counts=True)
        order = sorted(range(len(cols)), key=lambda i: (float(luma(cols[i])), hexc(cols[i])))
        ms = [measure(c) for _r, _c, c in cells(a, CELL)]
        light = np.mean([m['light'] for m in ms], axis=0)
        rim = collections.Counter()
        L = luma(a[..., :3])
        solid = a[..., 3] >= 128
        for r, c, _cell in cells(a, CELL):   # outline colours: the dark rim of every cell
            s = solid[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL]
            e = s & ~erode(s) & (L[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] < DARK)
            for px in a[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL][e][:, :3]:
                rim[hexc(px)] += 1
        ramps = collections.OrderedDict()
        for i in order:
            ramps.setdefault(family(cols[i]), []).append(hexc(cols[i]))
        per[key] = ms
        themes[key] = collections.OrderedDict([
            ('words', words), ('sheet', 'art_import/gear_sets/%s.png' % key), ('cells', len(ms)),
            ('palette', [hexc(cols[i]) for i in order]), ('counts', [int(counts[i]) for i in order]),
            ('light', [r2(light[0]), r2(light[1])]),
            ('light_deg', r2(np.degrees(np.arctan2(light[1], -light[0])))),
            ('outline', [k for k, _n in sorted(rim.items(), key=lambda kv: (-kv[1], kv[0]))[:6]]),
            ('ramps', ramps),
        ])
    gl = np.mean([themes[k]['light'] for k in themes], axis=0)
    # the owners' ranges (every cell against its own theme)
    allm = [(k, m) for k in per for m in per[k]]
    proj = [light_of(m, themes[k]['light'])[0] for k, m in allm]
    rng = collections.OrderedDict([
        ('colours', [min(m['colours'] for _k, m in allm), max(m['colours'] for _k, m in allm)]),
        ('outline_dark_min', r2(min(m['outline_dark'] for _k, m in allm))),
        ('outline_dark_mean', r2(np.mean([m['outline_dark'] for _k, m in allm]))),
        ('ring2_dark_max', r2(max(m['ring2_dark'] for _k, m in allm))),
        ('ring2_dark_mean', r2(np.mean([m['ring2_dark'] for _k, m in allm]))),
        ('outline_luma_mean', r2(np.mean([m['outline_luma'] for _k, m in allm]))),
        ('inner_dark_mean', collections.OrderedDict((k, r2(np.mean([m['inner_dark'] for m in per[k]])))
                                                    for k in per)),
        ('light_proj_min', r2(min(proj))),
        ('light_proj_median', r2(np.median(proj))),
        ('isolated_max', max(m['isolated'] for _k, m in allm)),
        ('specks_max', max(m['specks'] for _k, m in allm)),
        ('spike_max', r2(max(m['spike'] for _k, m in allm))),
        ('spike_mean', r2(np.mean([m['spike'] for _k, m in allm]))),
        ('single_max', r2(max(m['single'] for _k, m in allm))),
        ('single_mean', r2(np.mean([m['single'] for _k, m in allm]))),
        ('holes_max', max(m['holes'] for _k, m in allm)),
        ('semi', sum(m['semi'] for _k, m in allm)),
    ])
    # other themes' cells against each palette: how far a wrong theme lands
    cross = collections.OrderedDict()
    for key in themes:
        pal = np.array([unhex(h) for h in themes[key]['palette']])
        des = [palette_fit(m['paint'], pal)[0] for k, m in allm if k != key]
        cross[key] = [r2(np.percentile(des, 5)), r2(np.median(des))]
    de_max = np.floor(min(v[0] for v in cross.values()) * 2) / 2
    thr = collections.OrderedDict([
        ('colours_min', max(4, int(rng['colours'][0] * 0.6))),
        ('colours_max', int(np.ceil(rng['colours'][1] * 1.1))),
        ('palette_mean_de_max', float(de_max)),
        ('palette_far_max', 0.1),
        ('outline_dark_min', float(np.floor((rng['outline_dark_min'] - 0.05) * 20) / 20)),
        ('ring2_dark_max', float(min(0.95, np.ceil((rng['ring2_dark_max'] + 0.15) * 20) / 20))),
        ('light_proj_min', float(np.floor(rng['light_proj_min'] - 15))),
        ('light_warn_mag', 15.0),
        ('isolated_max', int(rng['isolated_max'])),
        ('specks_max', int(rng['specks_max']) + 1),
        ('spike_max', float(np.ceil((rng['spike_max'] + 0.05) * 100) / 100)),
        ('single_max', float(min(0.95, np.ceil((rng['single_max'] + 0.05) * 100) / 100))),
        ('holes_max', int(rng['holes_max'])),
    ])
    for key in themes:   # how many wrong-theme cells would still pass the palette check
        pal = np.array([unhex(h) for h in themes[key]['palette']])
        fits = [palette_fit(m['paint'], pal) for k, m in allm if k != key]
        ok = sum(1 for de, far in fits if de <= thr['palette_mean_de_max'] and far <= thr['palette_far_max'])
        cross[key].append(r2(ok / len(fits)))
    return collections.OrderedDict([
        ('about', 'Generated by style_check.py build-palettes from the owner gear sheets; do not edit.'),
        ('constants', collections.OrderedDict([('cell', CELL), ('dark_luma', DARK), ('spike_luma', SPIKE),
                                                ('far_de', FAR_DE), ('soft_alpha_min', SOFT_MIN)])),
        ('thresholds', thr),
        ('owner_ranges', rng),
        ('cross_theme', collections.OrderedDict([('fields', ['mean_de_p5', 'mean_de_median', 'pass_share'])] +
                                                list(cross.items()))),
        ('light', collections.OrderedDict([('global', [r2(gl[0]), r2(gl[1])]),
                                           ('global_deg', r2(np.degrees(np.arctan2(gl[1], -gl[0])))),
                                           ('note', 'x: left minus right rim luma, y: top minus bottom; '
                                                    'deg: 90 = from the top, 180 = from the left')])),
        ('themes', themes),
    ])


def dumps(obj):
    """JSON text: one key a line, lists of plain values on one line."""
    text = json.dumps(obj, indent=1)
    return re.sub(r'\[([^\[\]{}]*)\]', lambda m: '[' + ', '.join(x.strip() for x in m.group(1).split(',')
                                                                 if x.strip()) + ']', text) + '\n'


def load_palettes(path=PALETTES):
    with open(path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------------------------------------- commands
def read_palette(path):
    """palette colours (N, 3) of a PNG (its visible colours) or a text file of #rrggbb values."""
    if path.lower().endswith('.png'):
        a = np.array(Image.open(path).convert('RGBA'))
        return np.unique(a[a[..., 3] > 0][:, :3], axis=0)
    with open(path) as f:
        toks = f.read().replace(',', ' ').split()
    return np.array([unhex(t) for t in toks if t.lstrip('#') and not t.startswith('//')])


def check_image(path, pal_rgb, ref, thr, size=CELL, soft=False, key=None):
    """[(where, reasons, warnings)] of one PNG: the whole-image problems first (where = 'image'), then each cell."""
    out = []
    a, problems = load(path, key)
    h, w = a.shape[:2]
    if h % size or w % size:
        problems.append('size: %d x %d is not a whole number of %d px cells' % (w, h, size))
    if upscaled(a):
        problems.append('scale: the art is drawn in 2x2 blocks (upscaled); draw at 1:1')
    if not (a[..., 3] > 0).any():
        problems.append('empty: no visible pixel')
    if problems:
        out.append(('image', problems, []))
    for r, c, cell in cells(a, size):
        bad, warn = judge(measure(cell), pal_rgb, ref, thr, soft)
        out.append(('cell r%d c%d' % (r, c), bad, warn))
    return out


def cmd_check(args):
    data = load_palettes(args.palettes)
    thr = data['thresholds']
    if args.theme:
        if args.theme not in data['themes']:
            sys.exit('unknown theme %s (themes: %s)' % (args.theme, ', '.join(data['themes'])))
        t = data['themes'][args.theme]
        pal, ref = np.array([unhex(x) for x in t['palette']]), t['light']
    else:
        pal = np.concatenate([read_palette(p) for p in args.palette])
        ref = data['light']['global']
    key = unhex(args.key) if args.key else None
    failed = cells_n = 0
    for path in args.files:
        res = check_image(path, pal, ref, thr, args.cell, args.soft, key)
        bad_cells = [x for x in res if x[1]]
        cells_n += sum(1 for x in res if x[0] != 'image')
        failed += len(bad_cells)
        print('%s %s: %d cells, %d failed' % ('FAIL' if bad_cells else 'PASS', path,
                                               sum(1 for x in res if x[0] != 'image'), len(bad_cells)))
        for where, bad, warn in res:
            for b in bad:
                print('  %s FAIL %s' % (where, b))
            if args.verbose or bad:
                for x in warn:
                    print('  %s warn %s' % (where, x))
    print('%d cells checked, %d failed' % (cells_n, failed))
    return 1 if failed else 0


def snap(a, pal_rgb):
    """a copy of a with every visible pixel moved to the nearest palette colour (alpha kept)."""
    out = a.copy()
    vis = a[..., 3] > 0
    if vis.any():
        _d, idx = nearest(a[vis][:, :3], pal_rgb)
        out[vis, :3] = pal_rgb[idx]
    return out


def cmd_snap(args):
    data = load_palettes(args.palettes)
    if args.theme not in data['themes']:
        sys.exit('unknown theme %s' % args.theme)
    pal = np.array([unhex(x) for x in data['themes'][args.theme]['palette']], dtype=np.uint8)
    a, problems = load(args.inp, unhex(args.key) if args.key else None)
    for p in problems:
        print('warning:', p)
    Image.fromarray(snap(a, pal), 'RGBA').save(args.out)
    print('wrote', args.out)
    return 0


def cmd_build(args):
    text = dumps(build())
    if args.check:
        old = open(args.palettes).read() if os.path.exists(args.palettes) else ''
        if old != text:
            print('FAIL: %s is not what build-palettes makes from the owner sheets; run style_check.py build-palettes'
                  % args.palettes)
            return 1
        print('OK: %s matches the owner sheets' % args.palettes)
        return 0
    with open(args.palettes, 'w') as f:
        f.write(text)
    print('wrote', args.palettes)
    return 0


def owner_outfits():
    """measures of the owner art of pair 26 (art_import/owner_art.csv outfits): one dict per look."""
    out = []
    with open(os.path.join(ART, 'owner_art.csv'), newline='') as f:
        rows = [r for r in csv.DictReader(f) if r['cat'] == 'outfit']
    for r in rows:
        a = np.array(Image.open(os.path.join(ART, r['atlas'] + '.png')).convert('RGBA'))
        size = int(r['w']) * CELL
        ms, gaps = [], []
        for _r, _c, cell in cells(a, size):
            if (cell[..., 3] >= 128).sum() < 20:
                continue
            ms.append(measure(cell))
            ys, xs = np.nonzero(cell[..., 3] >= 128)
            gaps.append((size - 1 - xs.max(), size - 1 - ys.max()))
        vis = a[..., 3] > 0
        ex = dict(p.split('=', 1) for p in r['extra'].split('|') if '=' in p)
        out.append({'key': r['key'], 'kind': r['kind'], 'tiles': '%sx%s' % (r['w'], r['h']), 'phases': r['phases'],
                    'gtypes': ex.get('gtypes', ''), 'flags': r['flags'] or '-',
                    'semi': r2(((a[..., 3] > 0) & (a[..., 3] < 255)).sum() / max(vis.sum(), 1)),
                    'outline_dark': r2(np.mean([m['outline_dark'] for m in ms])),
                    'colours': int(np.median([m['colours'] for m in ms])),
                    'light_deg': r2(np.degrees(np.arctan2(np.mean([m['light'][1] for m in ms]),
                                                          -np.mean([m['light'][0] for m in ms])))),
                    'gap_right': int(np.median([g[0] for g in gaps])),
                    'gap_bottom': int(np.median([g[1] for g in gaps]))})
    return out


def effect_frames():
    """(source, kind, tiles, frames, ms) counts of our generated effects."""
    cnt = collections.Counter()
    with open(os.path.join(HERE, 'fx_custom.csv'), newline='') as f:
        for r in csv.DictReader(f):
            cnt[('fx_custom.csv', r['category'], r['size'], r['frames'], r['ms'])] += 1
    for name in ('class_fx.csv', 'big_fx.csv', 'necro_fx.csv'):
        with open(os.path.join(ART, name), newline='') as f:
            for r in csv.DictReader(f):
                cnt[(name, r['kind'], '%sx%s' % (r['w'], r['h']), r['phases'], r['ms'])] += 1
    return cnt


def item_kinds():
    """kind -> [(content w, content h, fill of the content box, diagonal, rising, checker share)] of every gear piece.
    diagonal share: how much of the box's long axis runs corner to corner (weapons lie diagonally); checker share:
    2x2 blocks in an a-b / b-a dither pattern."""
    out = collections.defaultdict(list)
    sheets = {}
    with open(os.path.join(ART, 'gear_sets.csv'), newline='') as f:
        for r in csv.DictReader(f):
            key = r['atlas'].split('/')[-1]
            a = sheets.setdefault(key, sheet(key))
            c = a[int(r['y']):int(r['y']) + CELL, int(r['x']):int(r['x']) + CELL]
            vis = c[..., 3] > 0
            ys, xs = np.nonzero(vis)
            w, h = np.ptp(xs) + 1, np.ptp(ys) + 1
            fill = vis.sum() / float(w * h)
            cov = np.cov(xs, ys)
            ev, evec = np.linalg.eigh(cov)
            ang = abs(np.degrees(np.arctan2(evec[1, 1], evec[0, 1]))) % 180
            diag = 1.0 - min(abs(ang - 45), abs(ang - 135)) / 45.0 if ev[1] > 2 * ev[0] else 0.0
            code = c[..., :3].astype(np.int64) @ np.array([65536, 256, 1])
            chk = ((code[:-1, :-1] == code[1:, 1:]) & (code[:-1, 1:] == code[1:, :-1]) &
                   (code[:-1, :-1] != code[:-1, 1:]) & vis[:-1, :-1] & vis[1:, 1:] & vis[:-1, 1:] & vis[1:, :-1])
            rising = 1.0 if diag > 0.5 and cov[0, 1] < 0 else 0.0   # '/': up to the right (y grows down)
            out[r['kind']].append((w, h, fill, max(diag, 0.0), rising, chk.sum() / max(vis.sum(), 1)))
    return out


def cmd_report(args):
    data = load_palettes(args.palettes)
    p = print
    p('## Themes (owner gear sheets)\n')
    p('| theme | words | colours | main outline colours | light (deg) | ramps (family: steps, dark .. light) |')
    p('|---|---|---|---|---|---|')
    for k, t in data['themes'].items():
        ramps = '; '.join('%s: %d, %s .. %s' % (f, len(v), v[0], v[-1]) for f, v in t['ramps'].items())
        p('| %s | %s | %d | %s | %.0f | %s |' % (k, t['words'], len(t['palette']), ' '.join(t['outline'][:3]),
                                                 t['light_deg'], ramps))
    p('\nglobal light: %s, %.0f deg' % (data['light']['global'], data['light']['global_deg']))
    p('\n## Main ramps (per family with 3+ colours: its 6 most used colours, dark to light)\n')
    for k, t in data['themes'].items():
        use = dict(zip(t['palette'], t['counts']))
        parts = []
        for f, v in t['ramps'].items():
            if len(v) >= 3:
                top = sorted(sorted(v, key=lambda h: -use[h])[:6], key=lambda h: (float(luma(unhex(h))), h))
                parts.append('%s %s' % (f, ' '.join(top)))
        p('- %s: %s' % (k, '; '.join(parts)))
    p('\n## Owner ranges (448 cells)\n')
    for k, v in data['owner_ranges'].items():
        p('- %s: %s' % (k, v))
    p('\n## Thresholds\n')
    for k, v in data['thresholds'].items():
        p('- %s: %s' % (k, v))
    p('\n## Cross-theme palette fit (%s)\n' % ', '.join(data['cross_theme']['fields']))
    for k, v in data['cross_theme'].items():
        if k != 'fields':
            p('- %s: %s' % (k, v))
    p('\n## Item cells: content box per sheet\n')
    p('| theme | content w x h (median) | margin min (l t r b) | margin median | fill (median) |')
    p('|---|---|---|---|---|')
    for k in data['themes']:
        bb, fill = [], []
        for _r, _c, c in cells(sheet(k), CELL):
            ys, xs = np.nonzero(c[..., 3] > 0)
            bb.append((xs.min(), ys.min(), CELL - 1 - xs.max(), CELL - 1 - ys.max(), np.ptp(xs) + 1, np.ptp(ys) + 1))
            fill.append((c[..., 3] > 0).mean())
        bb = np.array(bb)
        p('| %s | %d x %d | %s | %s | %.2f |' % (k, np.median(bb[:, 4]), np.median(bb[:, 5]),
                                                 ' '.join(str(int(v)) for v in bb[:, :4].min(0)),
                                                 ' '.join('%g' % v for v in np.median(bb[:, :4], 0)), np.median(fill)))
    p('\n## Item silhouettes per kind (art_import/gear_sets.csv, 7 sheets)\n')
    p('| kind | pieces | content w x h (median) | fill of the box | diagonal (median) | rising / (share) | '
      'checker 2x2 share |')
    p('|---|---|---|---|---|---|---|')
    for kind, v in sorted(item_kinds().items(), key=lambda kv: -len(kv[1])):
        v = np.array(v)
        med = np.median(v, 0)
        p('| %s | %d | %d x %d | %.2f | %.2f | %.2f | %.3f |' % (kind, len(v), med[0], med[1], med[2], med[3],
                                                                 v[:, 4].mean(), med[5]))
    p('\n## Owner art of pair 26 (outfits)\n')
    p('| look | kind | tiles | phases | gtypes | flags | semi alpha | dark rim | colours/frame | light (deg) | '
      'gap right / bottom |')
    p('|---|---|---|---|---|---|---|---|---|---|---|')
    for o in owner_outfits():
        p('| %(key)s | %(kind)s | %(tiles)s | %(phases)s | %(gtypes)s | %(flags)s | %(semi).2f | %(outline_dark).2f | '
          '%(colours)d | %(light_deg).0f | %(gap_right)d / %(gap_bottom)d |' % o)
    p('\n## Our generated effects (per source and kind: things, sizes, frames min / median / max, ms median)\n')
    by = collections.defaultdict(list)
    for (src, kind, size, frames, ms), n in effect_frames().items():
        by[(src, kind)] += [(size, int(frames), int(ms))] * n
    for (src, kind), v in sorted(by.items()):
        sizes = collections.Counter(x[0] for x in v)
        fr = sorted(x[1] for x in v)
        p('- %s %s: %d, sizes %s, frames %d / %g / %d, %g ms' % (
            src, kind, len(v), ' '.join('%s (%d)' % kv for kv in sorted(sizes.items())), fr[0], np.median(fr), fr[-1],
            np.median([x[2] for x in v])))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--palettes', default=PALETTES, help='style_palettes.json (default: next to this file)')
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('check', help='check PNG sprites or sheets')
    c.add_argument('files', nargs='+')
    g = c.add_mutually_exclusive_group(required=True)
    g.add_argument('--theme', help='a theme of style_palettes.json')
    g.add_argument('--palette', action='append', help='a PNG (its colours) or a text file of #rrggbb (repeatable)')
    c.add_argument('--cell', type=int, default=CELL, help='cell size in px (32; 64 for 2x2 things)')
    c.add_argument('--soft', action='store_true', help='effects and glows: soft alpha allowed, no outline rule')
    c.add_argument('--key', help='key colour RRGGBB of an opaque background (default: transparency, else top-left)')
    c.add_argument('--verbose', action='store_true', help='also print warnings of passing cells')
    s = sub.add_parser('snap', help='move every visible pixel to the nearest theme colour')
    s.add_argument('inp')
    s.add_argument('out')
    s.add_argument('--theme', required=True)
    s.add_argument('--key')
    b = sub.add_parser('build-palettes', help='measure the owner sheets -> style_palettes.json')
    b.add_argument('--check', action='store_true')
    sub.add_parser('report', help='print the measured facts of docs/SPRITE_STYLE.md')
    args = ap.parse_args(argv)
    return {'check': cmd_check, 'snap': cmd_snap, 'build-palettes': cmd_build, 'report': cmd_report}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
