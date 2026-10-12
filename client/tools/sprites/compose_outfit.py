#!/usr/bin/env python3
"""Compose a new outfit (a creature look, a wings or aura cosmetic, a mount) by stacking layers of existing things.

python3 -I compose_outfit.py SPEC.json --ours-dat Tibia.dat --ours-spr Tibia.spr [--lib-dir L] --out-dir OUT \
        [--preview] [--preview-only] [--csv-out THINGS.csv]
python3 -I compose_outfit.py SPEC.json --validate          # check the spec only (no pair needed)

Specs live in compose/ (JSON, one outfit each), so a result can be rebuilt. Sources of a layer: a thing of our pair
("live:outfit:2140", also item / effect / missile), of a donor library ("lib:I:outfit:286" = L/donorI/Tibia.dat), or a
PNG sheet in the import_art_things.py outfit layout ("png:sheets/foo.png", path relative to the spec, with png_size,
png_phases, png_layers, png_addons, png_mounts, png_gtypes, png_displacement, png_ms; a sheet this tool wrote can be a
layer of another spec). Inputs are only read.

Outputs in --out-dir: <key>.png, the sheet import_art_things.py reads (one row per frame group and phase, one column per
((z * addons + y) * layers + layer) * 4 + direction, cells of w x h tiles), and <key>.csv, a things.csv with the row
for it (--csv-out also adds or replaces the row in another things file). Append it to a pair with the normal importer:
    python3 -I import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \
        --things OUT/<key>.csv --first-outfit N --expect-items <item count of P>
--preview writes <key>_preview.png: every frame group, mount pattern and addon pattern as a block, each block a row of
all phases per direction (north, east, south, west), on a grey checker with the creature's tile outlined; when the
outfit has a colour mask a second row of the block shows it tinted with the spec's colours. --preview-only skips the
sheet and the row.

Spec (JSON object; unknown keys are refused):
  key       a-z, 0-9, _ (file names, the things.csv key)          name       text for the row
  size      "auto" (default: the base's size, grown up and left until every layer fits) or [w, h] tiles (1..7)
  displacement  "auto" (default: the base's, lowered when a layer reaches past the right / bottom edge of the tile),
            "base" (the base's, such content is an error) or [x, y]: pixels the client draws the outfit up / left
  flags     overrides of the flags copied from the base (displacement, light, animateAlways, bones): {"light": [3, 29]
            or null, "animateAlways": true / false, "bones": null or [nx, ny, sx, sy, ex, ey, wx, wy]}
  groups    the output's frame groups (default: the base's): [{"type": 0, "phases": 8, "ms": 120 or "durs": [[min, max],
            ...], "loop": 0, "async": 0, "start": 0}, ...]
  colours   {"head": 78, "body": 69, "legs": 58, "feet": 76}: outfit colour ids for the tinted preview and the row
  layers    list of layers; exactly one has "base": true (default: the first). The base gives the frame groups, the
            directions, addon and mount patterns, the displacement and the colour mask.
Layer keys:
  src       see above (required)
  role      "wings", "aura", "rider" or none: the client's placement rules for that kind (below)
  order     "front" (default) / "back" of the base, or per direction {"north": "front", "south": "back", ...}
  z         draw order among layers on the same side (default: list position)
  offset    [x, y] or per direction {"north": [x, y], ...} (pixels, + is right / down), added to the role's offset;
            "seat": the base's rider seat (Bones, byte 39) for that direction
  flip      {"west": "east"}: west draws the east frame mirrored about the creature's tile centre; ["west"] mirrors
            west's own frame
  opacity   0..1 (alpha multiplied)
  glow      {"palette": "ember", "step": 5, "radius": 2, "strength": 0.8}: a soft outer light around the layer: only on
            pixels the layer leaves transparent, at most radius (1..3) pixels from it, colours of one gen_effects.py
            palette ramp (step, then one darker per ring), alpha of the ramp's crisp "glow" levels, thinned by an
            ordered dither (no faint wash). It never changes the colour mask.
  frames    how the layer's phases follow the output's: "loop" (default: phase % n), "hold" (stops on its last),
            "repeat" (each phase stretched over the output's), "still" (phase 0), a list of phases, or per output group
            {"idle": mode or list or {"group": "walk", "phases": ...}, "walk": ...}; by default a layer uses its group of
            the same type, else its only / last group
  mask      "own" (base default: the layer's second layer is its colour mask), "none" (default: uncoloured; clears the
            mask under it where it covers, alpha >= 128), "keep" (leaves the mask under it)
  addons    "base-only" (default: drawn on addon pattern 0 only; front layers also cut their shape out of the addon
            patterns, which the client draws over pattern 0) or "own" (base default: the layer's addon pattern y)
  mount     "same" (default: the output's z pattern, or the layer's last) or a z pattern of the layer (1 = mounted pose)
Roles (as client base patches 0006 / 0034 draw them): "wings" go behind the body facing south and east and in front
facing north and west, 6 px right / down of it (GameWingOffset), with the client's mounted shifts on z pattern 1; an
"aura" draws its first layer behind everything and its second layer over everything, centred on the tile when bigger
than 1x1 (GameBigAurasCenter); a "rider" sits at the base's seat (offset "seat"), uses its mounted pattern (mount 1)
and keeps its own colour mask.

Placement: every frame is anchored at its bottom-right tile as the client draws it; a layer lands at
(output displacement - layer displacement + offset) relative to the output. Content may grow the size up and left;
content past the right or bottom edge lowers the displacement ("auto") or stops the run.
"""
import argparse
import csv
import json
import math
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

DIRS = ('north', 'east', 'south', 'west')
WORK = 256           # work canvas reaches this many pixels up / left of the anchor (8 tiles)
MARGIN = 64          # and this far right / down, to see overflow
MAX_TILES = 7        # exact size byte = 32 * max(w, h) < 256
COLS = ('key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
        'extra')


class SpecError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ palettes / colours
def palettes():
    from gen_effects import PALETTES, ALPHA
    return PALETTES, ALPHA


def outfit_colour(c):
    """the client's outfit colour (id 0..132) as RGB."""
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


# ------------------------------------------------------------------------------------------------ sources
class SGroup:
    """one frame group of a source (attributes as datspr / import_outfits groups)."""
    __slots__ = ('gtype', 'w', 'h', 'exact', 'layers', 'px', 'py', 'pz', 'phases', 'anim', 'sprites')


def signed(v):
    return v - 65536 if v >= 32768 else v


class PairSource:
    def __init__(self, dat, spr, cat, tid, label):
        from import_outfits import parse_body
        self.label = label
        lst = {'outfit': dat.outfits, 'item': dat.items, 'effect': dat.effects, 'missile': dat.missiles}[cat]
        idx = tid - (100 if cat == 'item' else 1)
        if not 0 <= idx < len(lst):
            raise SpecError(f'{label}: no such {cat}')
        t = lst[idx]
        if cat == 'outfit':
            self.groups = parse_body(dat, t)
        else:
            g = SGroup()
            g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim, g.sprites = (
                0, t.w, t.h, t.exact, t.layers, t.px, t.py, t.pz, t.phases, t.anim, t.sprites)
            self.groups = [g]
        disp = t.flags.get('displacement')
        self.disp = (signed(disp[0]), signed(disp[1])) if disp else (0, 0)
        self.light = t.flags.get('light')
        self.animate_always = bool(t.flags.get('animateAlways'))
        b = t.flags.get('x39')
        self.bones = struct.unpack('<8h', bytes(b)) if b else None
        self.spr = spr
        self._cache = {}

    def frame(self, gi, x, y, z, layer, phase):
        key = (gi, x, y, z, layer, phase)
        if key not in self._cache:
            g = self.groups[gi]
            from datspr import sprite_index
            out = np.zeros((g.h * 32, g.w * 32, 4), np.uint8)
            for hh in range(g.h):
                for ww in range(g.w):
                    a = self.spr.sprite(g.sprites[sprite_index(g, x, y, z, layer, phase, ww, hh)])
                    if a is not None:
                        y0, x0 = (g.h - 1 - hh) * 32, (g.w - 1 - ww) * 32
                        out[y0:y0 + 32, x0:x0 + 32] = a
            self._cache[key] = out
        return self._cache[key]


class PngSource:
    """a sheet in the import_art_things.py outfit layout."""

    def __init__(self, path, opts, label):
        self.label = label
        if not os.path.isfile(path):
            raise SpecError(f'{label}: no file {path}')
        self.img = np.asarray(Image.open(path).convert('RGBA'))
        w, h = opts.get('png_size', [1, 1])
        phases = [int(p) for p in str(opts.get('png_phases', '1')).split('+')]
        gtypes = [int(p) for p in str(opts.get('png_gtypes', '+'.join(str(i) for i in range(len(phases))))).split('+')]
        layers, py, pz = (int(opts.get(k, 1)) for k in ('png_layers', 'png_addons', 'png_mounts'))
        ms = int(opts.get('png_ms', 100))
        self.groups = []
        for gt, n in zip(gtypes, phases):
            g = SGroup()
            g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases = gt, w, h, 32 * max(w, h), layers, 4, py, pz, n
            g.anim = (0, 0, 0, (ms,) * (2 * n)) if n > 1 else None
            g.sprites = ()
            self.groups.append(g)
        self.disp = tuple(opts.get('png_displacement', (0, 0)))
        self.light, self.animate_always, self.bones = None, False, None
        rows = sum(phases)
        need = (rows * h * 32, layers * py * pz * 4 * w * 32)
        if self.img.shape[0] < need[0] or self.img.shape[1] < need[1]:
            raise SpecError(f'{label}: sheet {self.img.shape[1]}x{self.img.shape[0]} is smaller than the layout '
                            f'({need[1]}x{need[0]})')

    def frame(self, gi, x, y, z, layer, phase):
        g = self.groups[gi]
        row = sum(gg.phases for gg in self.groups[:gi]) + phase
        col = ((z * g.py + y) * g.layers + layer) * 4 + x
        W, H = g.w * 32, g.h * 32
        return self.img[row * H:(row + 1) * H, col * W:(col + 1) * W]


SRC_RE = re.compile(r'^(live:(outfit|item|effect|missile):(\d+)|lib:([A-Z]):(outfit|item|effect|missile):(\d+)|png:(.+))$')


class Pairs:
    def __init__(self, ours_dat=None, ours_spr=None, lib_dir=None):
        self.ours = (ours_dat, ours_spr)
        self.lib_dir = lib_dir
        self.open = {}

    def get(self, dat_path, spr_path):
        if dat_path not in self.open:
            from datspr import Dat, Spr
            d = Dat(dat_path)
            if d.variant[0] != 'new' or not all(d.variant[1:]):
                raise SpecError(f'{dat_path}: not a pair in our 10.98 format: {d.variant}')
            self.open[dat_path] = (d, Spr(spr_path))
        return self.open[dat_path]

    def source(self, src, opts, spec_dir, label):
        m = SRC_RE.match(src)
        if not m:
            raise SpecError(f'{label}: src {src!r} is not live:<cat>:<id>, lib:<L>:<cat>:<id> or png:<path>')
        if m.group(2):
            if not self.ours[0]:
                raise SpecError(f'{label}: {src} needs --ours-dat / --ours-spr')
            d, s = self.get(*self.ours)
            return PairSource(d, s, m.group(2), int(m.group(3)), f'{label} ({src})')
        if m.group(4):
            if not self.lib_dir:
                raise SpecError(f'{label}: {src} needs --lib-dir')
            base = os.path.join(self.lib_dir, f'donor{m.group(4)}')
            d, s = self.get(os.path.join(base, 'Tibia.dat'), os.path.join(base, 'Tibia.spr'))
            return PairSource(d, s, m.group(5), int(m.group(6)), f'{label} ({src})')
        return PngSource(os.path.join(spec_dir, m.group(7)), opts, f'{label} ({src})')


# ------------------------------------------------------------------------------------------------ spec
SPEC_KEYS = {'key', 'name', 'size', 'displacement', 'flags', 'groups', 'colours', 'layers', 'note'}
LAYER_KEYS = {'src', 'base', 'role', 'order', 'z', 'offset', 'flip', 'opacity', 'glow', 'frames', 'mask', 'addons',
              'mount', 'note', 'png_size', 'png_phases', 'png_layers', 'png_addons', 'png_mounts', 'png_gtypes',
              'png_displacement', 'png_ms'}
MODES = ('loop', 'hold', 'repeat', 'still')
GROUP_NAMES = {'idle': 0, 'walk': 1}


def _xy(v, where):
    if not (isinstance(v, list) and len(v) == 2 and all(isinstance(i, int) and -256 <= i <= 256 for i in v)):
        raise SpecError(f'{where}: expected [x, y] integers within -256..256, got {v!r}')
    return tuple(v)


def _per_dir(v, where, conv, default):
    if isinstance(v, dict):
        bad = set(v) - set(DIRS)
        if bad:
            raise SpecError(f'{where}: unknown direction(s) {sorted(bad)}')
        return [conv(v[d], f'{where}.{d}') if d in v else default for d in DIRS]
    return [conv(v, where)] * 4


def _frames_value(v, where):
    if isinstance(v, str):
        if v not in MODES:
            raise SpecError(f'{where}: mode {v!r} is not one of {MODES}')
        return {'group': None, 'phases': v}
    if isinstance(v, list):
        if not v or not all(isinstance(i, int) and i >= 0 for i in v):
            raise SpecError(f'{where}: a phase list needs phase numbers >= 0')
        return {'group': None, 'phases': list(v)}
    if isinstance(v, dict):
        bad = set(v) - {'group', 'phases'}
        if bad:
            raise SpecError(f'{where}: unknown keys {sorted(bad)}')
        g = v.get('group')
        if g is not None and not (g in GROUP_NAMES or (isinstance(g, int) and 0 <= g < 4)):
            raise SpecError(f'{where}.group: {g!r} is not idle, walk or a group number')
        inner = _frames_value(v.get('phases', 'loop'), f'{where}.phases')
        inner['group'] = GROUP_NAMES.get(g, g)
        return inner
    raise SpecError(f'{where}: expected a mode, a phase list or an object')


def validate(spec):
    """checks a spec object (no pair needed); returns it normalised. Raises SpecError."""
    if not isinstance(spec, dict):
        raise SpecError('spec: expected an object')
    bad = set(spec) - SPEC_KEYS
    if bad:
        raise SpecError(f'spec: unknown keys {sorted(bad)}')
    key = spec.get('key')
    if not isinstance(key, str) or not re.match(r'^[a-z0-9_]{1,48}$', key):
        raise SpecError(f'key: {key!r} must be 1..48 of a-z, 0-9, _')
    out = {'key': key, 'name': str(spec.get('name', key)), 'colours': None}
    size = spec.get('size', 'auto')
    if size != 'auto':
        if not (isinstance(size, list) and len(size) == 2 and all(isinstance(i, int) and 1 <= i <= MAX_TILES for i in size)):
            raise SpecError(f'size: "auto" or [w, h] with 1..{MAX_TILES} tiles, got {size!r}')
        size = tuple(size)
    out['size'] = size
    disp = spec.get('displacement', 'auto')
    out['displacement'] = disp if disp in ('base', 'auto') else _xy(disp, 'displacement')
    flags = spec.get('flags', {})
    if not isinstance(flags, dict) or set(flags) - {'light', 'animateAlways', 'bones'}:
        raise SpecError('flags: an object with light, animateAlways, bones')
    if 'light' in flags and flags['light'] is not None:
        lt = flags['light']
        if not (isinstance(lt, list) and len(lt) == 2 and 0 <= lt[0] <= 255 and 0 <= lt[1] <= 215):
            raise SpecError(f'flags.light: [level 0..255, colour 0..215] or null, got {lt!r}')
    if 'animateAlways' in flags and not isinstance(flags['animateAlways'], bool):
        raise SpecError('flags.animateAlways: true or false')
    if 'bones' in flags and flags['bones'] is not None:
        b = flags['bones']
        if not (isinstance(b, list) and len(b) == 8 and all(isinstance(i, int) and -128 <= i <= 128 for i in b)):
            raise SpecError('flags.bones: null or eight integers -128..128 (north, south, east, west x / y)')
    out['flags'] = flags
    groups = spec.get('groups')
    if groups is not None:
        if not (isinstance(groups, list) and 1 <= len(groups) <= 2):
            raise SpecError('groups: a list of 1 or 2 frame groups')
        norm = []
        for i, g in enumerate(groups):
            w = f'groups[{i}]'
            if not isinstance(g, dict) or set(g) - {'type', 'phases', 'ms', 'durs', 'loop', 'async', 'start'}:
                raise SpecError(f'{w}: keys type, phases, ms or durs, loop, async, start')
            n = g.get('phases')
            if not (isinstance(n, int) and 1 <= n <= 64):
                raise SpecError(f'{w}.phases: 1..64')
            gt = g.get('type', i)
            if gt not in (0, 1):
                raise SpecError(f'{w}.type: 0 (idle) or 1 (walking)')
            if 'durs' in g:
                d = g['durs']
                if not (isinstance(d, list) and len(d) == n and all(isinstance(p, list) and len(p) == 2 and 0 < p[0] <= p[1] <= 10000 for p in d)):
                    raise SpecError(f'{w}.durs: {n} pairs [min, max], 0 < min <= max <= 10000 ms')
                durs = tuple(x for p in d for x in p)
            else:
                ms = g.get('ms', 100)
                if not (isinstance(ms, int) and 0 < ms <= 10000):
                    raise SpecError(f'{w}.ms: 1..10000')
                durs = (ms,) * (2 * n)
            loop, asyn, start = g.get('loop', 0), g.get('async', 0), g.get('start', 0)
            if not (isinstance(loop, int) and loop >= -1 and asyn in (0, 1) and isinstance(start, int) and -1 <= start < n):
                raise SpecError(f'{w}: loop >= -1, async 0 / 1, start -1..phases-1')
            norm.append({'type': gt, 'phases': n, 'anim': (asyn, loop, start, durs) if n > 1 else None})
        if len({g['type'] for g in norm}) != len(norm):
            raise SpecError('groups: two groups of the same type')
        groups = norm
    out['groups'] = groups
    col = spec.get('colours')
    if col is not None:
        if not (isinstance(col, dict) and set(col) == {'head', 'body', 'legs', 'feet'}
                and all(isinstance(v, int) and 0 <= v < 133 for v in col.values())):
            raise SpecError('colours: {"head", "body", "legs", "feet"} outfit colour ids 0..132')
        out['colours'] = col
    layers = spec.get('layers')
    if not (isinstance(layers, list) and layers):
        raise SpecError('layers: a non-empty list')
    bases = [i for i, L in enumerate(layers) if isinstance(L, dict) and L.get('base')]
    if len(bases) > 1:
        raise SpecError(f'layers: {len(bases)} layers marked base (one allowed)')
    base_i = bases[0] if bases else 0
    out['layers'] = [validate_layer(L, i, i == base_i) for i, L in enumerate(layers)]
    return out


def validate_layer(L, i, is_base):
    w = f'layers[{i}]'
    if not isinstance(L, dict):
        raise SpecError(f'{w}: expected an object')
    bad = set(L) - LAYER_KEYS
    if bad:
        raise SpecError(f'{w}: unknown keys {sorted(bad)}')
    src = L.get('src')
    if not isinstance(src, str) or not SRC_RE.match(src):
        raise SpecError(f'{w}.src: live:<cat>:<id>, lib:<L>:<cat>:<id> or png:<path>, got {src!r}')
    role = L.get('role')
    if role not in (None, 'wings', 'aura', 'rider'):
        raise SpecError(f'{w}.role: wings, aura, rider or none')
    if is_base and role:
        raise SpecError(f'{w}: the base layer takes no role')
    o = {'src': src, 'base': is_base, 'role': role, 'index': i, 'opts': {k: v for k, v in L.items() if k.startswith('png_')}}
    if src.startswith('png:'):
        ps = L.get('png_size')
        if not (isinstance(ps, list) and len(ps) == 2 and all(isinstance(v, int) and 1 <= v <= MAX_TILES for v in ps)):
            raise SpecError(f'{w}.png_size: [w, h] tiles is required for a png source')
        for k in ('png_layers', 'png_addons', 'png_mounts'):
            if k in L and L[k] not in ((1, 2) if k != 'png_addons' else (1, 2, 3, 4)):
                raise SpecError(f'{w}.{k}: out of range')
        if 'png_phases' in L and not re.match(r'^\d+(\+\d+)?$', str(L['png_phases'])):
            raise SpecError(f'{w}.png_phases: like 8 or 2+4')
        if 'png_displacement' in L:
            _xy(L['png_displacement'], f'{w}.png_displacement')
    if is_base:
        default_order = 'base'
    elif role == 'wings':
        default_order = {'north': 'front', 'east': 'back', 'south': 'back', 'west': 'front'}
    else:
        default_order = 'front'

    def conv_order(v, where):
        if v not in ('front', 'back'):
            raise SpecError(f'{where}: front or back, got {v!r}')
        return v
    order = L.get('order', default_order)
    if is_base:
        if 'order' in L:
            raise SpecError(f'{w}.order: the base layer has no order')
        o['order'] = ['base'] * 4
    else:
        o['order'] = _per_dir(order, f'{w}.order', conv_order, 'front')
    z = L.get('z', i)
    if not isinstance(z, (int, float)):
        raise SpecError(f'{w}.z: a number')
    o['z'] = z
    off = L.get('offset', [0, 0])
    if off == 'seat':
        o['offset'] = 'seat'
    else:
        o['offset'] = _per_dir(off, f'{w}.offset', _xy, (0, 0))
    if role == 'rider' and 'offset' not in L:
        o['offset'] = 'seat'
    flip = L.get('flip', {})
    o['flip'] = [None] * 4
    if isinstance(flip, list):
        for d in flip:
            if d not in DIRS:
                raise SpecError(f'{w}.flip: unknown direction {d!r}')
            o['flip'][DIRS.index(d)] = d
    elif isinstance(flip, dict):
        for d, s in flip.items():
            if d not in DIRS or s not in DIRS:
                raise SpecError(f'{w}.flip: {{"west": "east"}} direction names, got {d!r}: {s!r}')
            o['flip'][DIRS.index(d)] = s
    else:
        raise SpecError(f'{w}.flip: a list or an object')
    op = L.get('opacity', 1.0)
    if not (isinstance(op, (int, float)) and 0 < op <= 1):
        raise SpecError(f'{w}.opacity: above 0, at most 1')
    o['opacity'] = float(op)
    glow = L.get('glow')
    if glow is not None:
        if not isinstance(glow, dict) or set(glow) - {'palette', 'step', 'radius', 'strength'}:
            raise SpecError(f'{w}.glow: keys palette, step, radius, strength')
        PAL, _ = palettes()
        if glow.get('palette') not in PAL:
            raise SpecError(f'{w}.glow.palette: one of the gen_effects.py palettes ({", ".join(sorted(PAL))})')
        step, radius, strength = glow.get('step', 5), glow.get('radius', 2), glow.get('strength', 0.8)
        if not (isinstance(step, int) and 2 <= step <= 7):
            raise SpecError(f'{w}.glow.step: 2..7 (a ramp step; outer rings use darker steps)')
        if not (isinstance(radius, int) and 1 <= radius <= 3):
            raise SpecError(f'{w}.glow.radius: 1..3 pixels')
        if not (isinstance(strength, (int, float)) and 0 < strength <= 1):
            raise SpecError(f'{w}.glow.strength: above 0, at most 1')
        o['glow'] = {'palette': glow['palette'], 'step': step, 'radius': radius, 'strength': float(strength)}
    else:
        o['glow'] = None
    fr = L.get('frames', 'loop')
    if isinstance(fr, dict) and not (set(fr) <= {'group', 'phases'}):
        per = {}
        for k, v in fr.items():
            gk = GROUP_NAMES.get(k, None)
            if gk is None:
                if not (isinstance(k, str) and k.isdigit()):
                    raise SpecError(f'{w}.frames: keys idle, walk or group numbers, got {k!r}')
                gk = int(k)
            per[gk] = _frames_value(v, f'{w}.frames.{k}')   # keyed by output group type
        o['frames'] = per
    else:
        o['frames'] = {'*': _frames_value(fr, f'{w}.frames')}
    mask = L.get('mask', 'own' if is_base or role == 'rider' else 'none')
    if mask not in ('own', 'none', 'keep'):
        raise SpecError(f'{w}.mask: own, none or keep')
    if role == 'aura' and mask == 'own':
        raise SpecError(f'{w}.mask: an aura\'s second layer is its front layer, not a mask')
    o['mask'] = mask
    addons = L.get('addons', 'own' if is_base else 'base-only')
    if addons not in ('own', 'base-only'):
        raise SpecError(f'{w}.addons: own or base-only')
    o['addons'] = addons
    mount = L.get('mount', 1 if role == 'rider' else 'same')
    if mount != 'same' and not (isinstance(mount, int) and 0 <= mount <= 1):
        raise SpecError(f'{w}.mount: same, 0 or 1')
    o['mount'] = mount
    return o


# ------------------------------------------------------------------------------------------------ drawing helpers
def over(dst, src):
    """straight-alpha 'over' of src onto dst (uint8 RGBA arrays of one size), in place on dst."""
    sa = src[..., 3]
    if not sa.any():
        return
    full = sa == 255
    dst[full] = src[full]
    part = (sa > 0) & ~full
    if part.any():
        s = src[part].astype(np.float64)
        d = dst[part].astype(np.float64)
        a_s, a_d = s[:, 3:4] / 255, d[:, 3:4] / 255
        a_o = a_s + a_d * (1 - a_s)
        rgb = (s[:, :3] * a_s + d[:, :3] * a_d * (1 - a_s)) / np.maximum(a_o, 1e-9)
        dst[part] = np.concatenate([np.rint(rgb), np.rint(a_o * 255)], axis=1).clip(0, 255).astype(np.uint8)


BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float64) + 0.5) / 16


def glow_layer(img, glow):
    """RGBA glow around img's visible pixels (same canvas): rings 1..radius outside it, ramp colours, crisp alpha
    levels, ordered dither. Never on a pixel img covers."""
    PAL, ALPHA = palettes()
    ramp = PAL[glow['palette']][0]
    levels = ALPHA['glow']
    solid = img[..., 3] > 0
    H, W = solid.shape
    out = np.zeros_like(img)
    taken = solid.copy()
    r = glow['radius']
    yy, xx = np.mgrid[0:H, 0:W]
    thr = BAYER4[yy % 4, xx % 4]
    for d in range(1, r + 1):
        ring = np.zeros_like(solid)
        for dy in range(-d, d + 1):
            for dx in range(-d, d + 1):
                if dx * dx + dy * dy > (d + 0.5) ** 2:
                    continue
                sh = np.zeros_like(solid)
                ys0, ys1 = max(0, dy), H + min(0, dy)
                xs0, xs1 = max(0, dx), W + min(0, dx)
                sh[ys0:ys1, xs0:xs1] = solid[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
                ring |= sh
        ring &= ~taken
        taken |= ring
        density = glow['strength'] * (1 - (d - 1) / r)
        ring &= thr < density
        colour = ramp[max(0, glow['step'] - (d - 1))]
        alpha = levels[max(0, 3 - d)]           # 235, 210, 180 for rings 1..3 (the ramp's crisp glow levels)
        out[ring] = (*colour, alpha)
    return out


# ------------------------------------------------------------------------------------------------ composition
class Composer:
    def __init__(self, spec, pairs, spec_dir):
        self.spec = spec
        self.sources = [pairs.source(L['src'], L['opts'], spec_dir, f'layers[{L["index"]}]') for L in spec['layers']]
        self.base_i = next(i for i, L in enumerate(spec['layers']) if L['base'])
        base = self.sources[self.base_i]
        self.base = base
        b0 = base.groups[0]
        self.px = 4
        self.py, self.pz = b0.py, b0.pz
        if spec['groups']:
            self.groups = [(g['type'], g['phases'], g['anim']) for g in spec['groups']]
        else:
            self.groups = [(g.gtype, g.phases, g.anim) for g in base.groups]
        self.disp = base.disp if spec['displacement'] in ('base', 'auto') else spec['displacement']
        self.base_size = (max(g.w for g in base.groups), max(g.h for g in base.groups))
        for L, s in zip(spec['layers'], self.sources):
            if L['role'] == 'aura' and s.groups[0].layers < 1:
                raise SpecError(f'{s.label}: no layers')
            if L['mask'] == 'own' and s.groups[0].layers < 2 and not L['base'] and L['role'] != 'rider':
                raise SpecError(f'{s.label}: mask "own" but the source has one layer')
        if spec['layers'][self.base_i]['addons'] == 'own' and any(
                L['addons'] == 'own' and s.groups[0].py < self.py and not L['base']
                for L, s in zip(spec['layers'], self.sources)):
            raise SpecError('a layer with addons "own" has fewer addon patterns than the base')
        self.has_wings = any(L['role'] == 'wings' for L in spec['layers'])
        self.notes = []

    # --- per layer choices
    def src_group(self, L, s, og):
        gtype = self.groups[og][0]
        fr = L['frames'].get(gtype, L['frames'].get('*', {'group': None, 'phases': 'loop'}))
        want = fr['group']
        if want is not None:
            cand = [i for i, g in enumerate(s.groups) if g.gtype == want]
            if not cand:
                if 0 <= want < len(s.groups):
                    cand = [want]
                else:
                    raise SpecError(f'{s.label}: has no frame group {want}')
            return cand[0], fr['phases']
        cand = [i for i, g in enumerate(s.groups) if g.gtype == gtype]
        return (cand[0] if cand else len(s.groups) - 1), fr['phases']

    def src_phase(self, s, sg, mode, p, n_out, label):
        n = s.groups[sg].phases
        if isinstance(mode, list):
            if len(mode) != n_out:
                raise SpecError(f'{label}: a phase list of {len(mode)} for an output group of {n_out} phases')
            if mode[p] >= n:
                raise SpecError(f'{label}: phase {mode[p]} but the source group has {n}')
            return mode[p]
        if mode == 'loop':
            return p % n
        if mode == 'hold':
            return min(p, n - 1)
        if mode == 'repeat':
            return p * n // n_out
        return 0

    def offset(self, L, s, d, z):
        dx, dy = 0, 0
        if L['offset'] == 'seat':
            b = self.base.bones
            if b is None:
                raise SpecError(f'{s.label}: offset "seat" but the base has no rider seat (byte 39)')
            fo = {'north': 0, 'south': 1, 'east': 2, 'west': 3}[DIRS[d]]
            dx, dy = b[2 * fo], b[2 * fo + 1]
        else:
            dx, dy = L['offset'][d]
        role = L['role']
        if role == 'wings':
            dx, dy = dx + 6, dy + 6
            if z > 0:
                ex = {'east': (-6, -2), 'south': (0, -6), 'north': (4, 6), 'west': (4, 6)}[DIRS[d]]
                dx, dy = dx + ex[0], dy + ex[1]
        elif role == 'aura':
            g = s.groups[0]
            if g.w > 1 or g.h > 1:
                dx += (g.w - 1) * 16 if g.w > 1 else 0
                dy += (g.h - 1) * 16 if g.h > 1 else 0
        return dx, dy

    # --- frames
    def parts(self, og, ph, d, y, z):
        """draw items of one output frame: (rank, z, index, part, color, mask or None, mask mode)."""
        items = []
        n_out = self.groups[og][1]
        for li, (L, s) in enumerate(zip(self.spec['layers'], self.sources)):
            own_addons = L['base'] or L['addons'] == 'own'
            if y > 0 and not own_addons:
                continue
            sg, mode = self.src_group(L, s, og)
            g = s.groups[sg]
            sy = y if own_addons else 0
            if sy >= g.py:
                continue
            sz = min(z if L['mount'] == 'same' else L['mount'], g.pz - 1)
            sp = self.src_phase(s, sg, mode, ph, n_out, s.label)
            flip = L['flip'][d]
            sd = DIRS.index(flip) if flip else d
            sx = sd if g.px >= 4 else 0
            off = self.offset(L, s, d, z)
            rank = {'base': 0, 'back': -1, 'front': 1}[L['order'][d]]
            if L['role'] == 'aura':
                pieces = [(-2, 0)]
                if g.layers > 1:
                    pieces.append((2, 1))
                for rk, layer in pieces:
                    o2 = off
                    if layer == 1 and z > 0:
                        ex = {'east': (-12, -6), 'south': (-1, -12)}.get(DIRS[d], (-4, -6))
                        o2 = (off[0] + ex[0], off[1] + ex[1])
                    items.append((rk, L['z'], li, layer, s, sg, sx, sy, sz, sp, flip is not None, o2, None, 'none', L))
                continue
            mask_layer = 1 if (L['mask'] == 'own' and g.layers >= 2) else None
            items.append((rank, L['z'], li, 0, s, sg, sx, sy, sz, sp, flip is not None, off, mask_layer, L['mask'], L))
        items.sort(key=lambda t: (t[0], t[1], t[2], t[3]))
        return items

    def place(self, s, sg, sx, sy, sz, layer, sp, mirror, off, L):
        """the layer frame on a work canvas (anchor = output's bottom-right corner at (WORK, WORK))."""
        g = s.groups[sg]
        img = s.frame(sg, sx, sy, sz, layer, sp)
        Wl, Hl = g.w * 32, g.h * 32
        X = -Wl + (self.disp[0] - s.disp[0])
        Y = -Hl + (self.disp[1] - s.disp[1])
        if mirror:
            axis = self.disp[0] - 16          # the creature tile's centre line (anchor coordinates)
            img = img[:, ::-1]
            X = 2 * axis - X - Wl
        X += off[0]; Y += off[1]
        canvas = np.zeros((WORK + MARGIN, WORK + MARGIN, 4), np.uint8)
        x0, y0 = X + WORK, Y + WORK
        if x0 < 0 or y0 < 0 or x0 + Wl > WORK + MARGIN or y0 + Hl > WORK + MARGIN:
            vis = img[..., 3] > 0
            if vis.any():
                ys, xs = np.nonzero(vis)
                if (x0 + xs.min() < 0 or y0 + ys.min() < 0 or x0 + xs.max() >= WORK + MARGIN
                        or y0 + ys.max() >= WORK + MARGIN):
                    raise SpecError(f'{s.label}: placed {X},{Y} reaches outside {WORK // 32} tiles up / left or '
                                    f'{MARGIN} px right / down of the output tile')
        cx0, cy0 = max(0, x0), max(0, y0)
        cx1, cy1 = min(WORK + MARGIN, x0 + Wl), min(WORK + MARGIN, y0 + Hl)
        if cx1 > cx0 and cy1 > cy0:
            canvas[cy0:cy1, cx0:cx1] = img[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
        if L['opacity'] < 1:
            canvas[..., 3] = np.rint(canvas[..., 3].astype(np.float64) * L['opacity']).astype(np.uint8)
            canvas[canvas[..., 3] == 0] = 0
        return canvas

    def render(self, og, ph, d, y, z, front_cover=None):
        color = np.zeros((WORK + MARGIN, WORK + MARGIN, 4), np.uint8)
        mask = np.zeros_like(color)
        cover_front = np.zeros(color.shape[:2], bool)
        any_mask = False
        for (rank, _z, li, layer, s, sg, sx, sy, sz, sp, mirror, off, mlayer, mmode, L) in self.parts(og, ph, d, y, z):
            img = self.place(s, sg, sx, sy, sz, layer, sp, mirror, off, L)
            cov = img[..., 3] >= 128
            if L['glow']:
                gl = glow_layer(img, L['glow'])
                if L['opacity'] < 1:
                    gl[..., 3] = np.rint(gl[..., 3] * L['opacity']).astype(np.uint8)
                over(color, gl)
            over(color, img)
            if mmode == 'own':
                if mlayer is not None:
                    k = self.place(s, sg, sx, sy, sz, mlayer, sp, mirror, off, dict(L, opacity=1.0))
                    k[k[..., 3] > 0, 3] = 255
                    mask[cov] = k[cov]
                    any_mask = any_mask or bool(k[..., 3].any())
                else:
                    mask[cov] = 0
            elif mmode == 'none':
                mask[cov] = 0
            if rank > 0:
                cover_front |= cov
        if front_cover is not None:             # addon patterns: the client draws them over pattern 0's front layers
            color[front_cover] = 0
            mask[front_cover] = 0
        mask[color[..., 3] == 0] = 0
        return color, mask, cover_front, any_mask

    def compose(self):
        """renders every frame; with displacement "auto" a frame reaching past the right / bottom edge lowers the
        output's displacement by that much (negative displacements need GameNegativeOffset, on for 10.98) and
        renders again."""
        for _ in range(3):
            over_x, over_y = self._render_all()
            if not (over_x or over_y) or self.spec['displacement'] != 'auto':
                break
            self.disp = (self.disp[0] - over_x, self.disp[1] - over_y)
            self.notes.append(f'displacement lowered by ({over_x}, {over_y}) to {self.disp}: content reached past '
                              'the right / bottom edge of the tile')
        return self._finish()

    def _render_all(self):
        frames = {}
        any_mask = False
        for og, (gt, n, anim) in enumerate(self.groups):
            for ph in range(n):
                for z in range(self.pz):
                    for d in range(4):
                        c0, m0, front, am = self.render(og, ph, d, 0, z)
                        frames[(og, ph, d, 0, z)] = (c0, m0)
                        any_mask |= am
                        for y in range(1, self.py):
                            c, m, _, am = self.render(og, ph, d, y, z, front_cover=front)
                            frames[(og, ph, d, y, z)] = (c, m)
                            any_mask |= am
        base_has_mask = self.base.groups[0].layers >= 2 and self.spec['layers'][self.base_i]['mask'] == 'own'
        self.layers_out = 2 if (any_mask or base_has_mask) else 1
        vis = np.zeros((WORK + MARGIN, WORK + MARGIN), bool)
        for c, m in frames.values():
            vis |= c[..., 3] > 0
        if not vis.any():
            raise SpecError('the composed outfit has no visible pixel')
        self._frames, self._vis = frames, vis
        ys, xs = np.nonzero(vis)
        return max(0, int(xs.max()) - WORK + 1), max(0, int(ys.max()) - WORK + 1)

    def _finish(self):
        frames, vis = self._frames, self._vis
        ys, xs = np.nonzero(vis)
        if xs.max() >= WORK or ys.max() >= WORK:
            raise SpecError(f'content reaches {xs.max() - WORK + 1} px right / {ys.max() - WORK + 1} px below the output '
                            'tile: move the layer up / left (offset) or give a smaller "displacement"')
        need_w = max(self.base_size[0], math.ceil((WORK - xs.min()) / 32))
        need_h = max(self.base_size[1], math.ceil((WORK - ys.min()) / 32))
        if self.spec['size'] == 'auto':
            w, h = need_w, need_h
        else:
            w, h = self.spec['size']
            if (WORK - xs.min()) > w * 32 or (WORK - ys.min()) > h * 32:
                raise SpecError(f'size {w}x{h}: the content needs {math.ceil((WORK - xs.min()) / 32)}x'
                                f'{math.ceil((WORK - ys.min()) / 32)} tiles')
        if w > MAX_TILES or h > MAX_TILES:
            raise SpecError(f'the content needs {w}x{h} tiles; at most {MAX_TILES}')
        self.w, self.h = w, h
        W, H = w * 32, h * 32
        self.frames = {k: (c[WORK - H:WORK, WORK - W:WORK].copy(), m[WORK - H:WORK, WORK - W:WORK].copy())
                       for k, (c, m) in frames.items()}
        # exact sizes: the base's when the size is kept, else 32 * max(w, h)
        same = (w, h) == self.base_size and len(self.groups) == len(self.base.groups) and not self.spec['groups']
        if same:
            self.exact = [g.exact if (g.w > 1 or g.h > 1) else 32 * max(w, h) for g in self.base.groups]
        else:
            self.exact = [32 * max(w, h)] * len(self.groups)
        return self

    # --- outputs
    def flags(self):
        f = self.spec['flags']
        toks = []
        disp = self.disp
        if disp != (0, 0):
            toks.append(f'displacement:{disp[0]}:{disp[1]}')
        light = f['light'] if 'light' in f else (list(self.base.light) if self.base.light else None)
        if light:
            toks.append(f'light:{light[0]}:{light[1]}')
        aa = f.get('animateAlways', self.base.animate_always)
        if aa:
            toks.append('animateAlways')
        bones = f['bones'] if 'bones' in f else (list(self.base.bones) if self.base.bones else None)
        if bones:
            toks.append('bones:' + ':'.join(str(v) for v in bones))
        return ' '.join(toks)

    def sheet(self):
        W, H = self.w * 32, self.h * 32
        rows = sum(n for _, n, _ in self.groups)
        cols = self.pz * self.py * self.layers_out * 4
        out = np.zeros((rows * H, cols * W, 4), np.uint8)
        row = 0
        for og, (gt, n, anim) in enumerate(self.groups):
            for ph in range(n):
                for z in range(self.pz):
                    for y in range(self.py):
                        for d in range(4):
                            c, m = self.frames[(og, ph, d, y, z)]
                            for layer, img in enumerate((c, m)[:self.layers_out]):
                                col = ((z * self.py + y) * self.layers_out + layer) * 4 + d
                                out[row * H:(row + 1) * H, col * W:(col + 1) * W] = img
                row += 1
        return out

    def row(self, atlas):
        ex = [f'gtypes={"+".join(str(g[0]) for g in self.groups)}', f'layers={self.layers_out}',
              f'addons={self.py}', f'mounts={self.pz}', f'exact={"+".join(str(e) for e in self.exact)}']
        for i, (gt, n, anim) in enumerate(self.groups):
            if n > 1:
                asyn, loop, start, durs = anim
                ex.append(f'durs{i}=' + '/'.join(f'{durs[2 * p]}:{durs[2 * p + 1]}' for p in range(n)))
                ex.append(f'anim{i}={asyn}:{loop}:{start}')
        if self.spec['colours']:
            ex += [f'{k}={self.spec["colours"][k]}' for k in ('head', 'body', 'legs', 'feet')]
        return {'key': self.spec['key'], 'cat': 'outfit', 'kind': 'composed', 'name': self.spec['name'], 'atlas': atlas,
                'x': 0, 'y': 0, 'w': self.w, 'h': self.h, 'patterns': 4,
                'phases': '+'.join(str(n) for _, n, _ in self.groups), 'flags': self.flags(), 'mode': 'new',
                'server_id': '', 'extra': '|'.join(ex)}

    def preview(self, path):
        W, H = self.w * 32, self.h * 32
        tinted = self.layers_out == 2
        cols = ['head', 'body', 'legs', 'feet']
        tint = {k: outfit_colour((self.spec['colours'] or {'head': 78, 'body': 69, 'legs': 58, 'feet': 76})[k]) for k in cols}
        blocks = [(og, z, y) for og in range(len(self.groups)) for z in range(self.pz) for y in range(self.py)]
        maxph = max(n for _, n, _ in self.groups)
        cw, ch = W + 6, H + 6
        label_w = 120
        per_block = 2 if tinted else 1
        sheet_w = label_w + 4 * maxph * cw + 3 * 8
        sheet_h = 18 + len(blocks) * per_block * ch
        scale = 2 if max(sheet_w, sheet_h) * 2 <= 6000 else 1
        im = Image.new('RGB', (sheet_w, sheet_h), (52, 52, 58))
        dr = ImageDraw.Draw(im)
        for d in range(4):
            dr.text((label_w + d * (maxph * cw + 8) + 2, 3), DIRS[d], fill=(220, 220, 220))
        checker = np.zeros((H, W, 3), np.uint8)
        yy, xx = np.mgrid[0:H, 0:W]
        checker[:] = 78
        checker[((yy // 8) + (xx // 8)) % 2 == 0] = 92
        tile = (W - 32 + self.disp[0], H - 32 + self.disp[1])
        for bi, (og, z, y) in enumerate(blocks):
            gt, n, _ = self.groups[og]
            for t in range(per_block):
                top = 18 + (bi * per_block + t) * ch
                name = {0: 'idle', 1: 'walk'}.get(gt, str(gt))
                dr.text((4, top + 4), f'group {og} ({name})', fill=(230, 230, 230))
                dr.text((4, top + 16), f'mount z{z} addon y{y}', fill=(200, 200, 200))
                if t:
                    dr.text((4, top + 28), 'tinted', fill=(240, 200, 120))
                for d in range(4):
                    for ph in range(n):
                        c, m = self.frames[(og, ph, d, y, z)]
                        img = c.copy()
                        if t:
                            rgb = img[..., :3].astype(np.float64)
                            for key, col in zip(cols, ((255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255))):
                                sel = (m[..., 3] > 0) & np.all(m[..., :3] == col, axis=2)
                                rgb[sel] = rgb[sel] * np.array(tint[key]) / 255
                            img[..., :3] = np.rint(rgb).astype(np.uint8)
                        bg = checker.copy()
                        a = img[..., 3:4].astype(np.float64) / 255
                        cell = np.rint(img[..., :3] * a + bg * (1 - a)).astype(np.uint8)
                        x0 = label_w + d * (maxph * cw + 8) + ph * cw + 3
                        im.paste(Image.fromarray(cell, 'RGB'), (x0, top + 3))
                        dr.rectangle((x0 + tile[0], top + 3 + tile[1], x0 + tile[0] + 31, top + 3 + tile[1] + 31),
                                     outline=(120, 160, 120))
        if scale > 1:
            im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        im.save(path)
        return path


def load_spec(path):
    with open(path, encoding='utf-8') as f:
        try:
            raw = json.load(f)
        except json.JSONDecodeError as e:
            raise SpecError(f'{path}: {e}')
    return validate(raw)


def write_csv(path, row, replace=True):
    rows = []
    if replace and os.path.isfile(path):
        with open(path, newline='', encoding='utf-8') as f:
            rows = [r for r in csv.DictReader(f) if r['key'] != row['key']]
    rows.append({k: row[k] for k in COLS})
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, COLS, lineterminator='\n')
        w.writeheader()
        w.writerows(rows)


def run(spec_path, pairs, out_dir, preview=False, preview_only=False, csv_out=None, log=print):
    spec = load_spec(spec_path)
    comp = Composer(spec, pairs, os.path.dirname(os.path.abspath(spec_path))).compose()
    os.makedirs(out_dir, exist_ok=True)
    key = spec['key']
    res = {'size': (comp.w, comp.h), 'layers': comp.layers_out, 'groups': comp.groups}
    if not preview_only:
        png = os.path.join(out_dir, key + '.png')
        Image.fromarray(comp.sheet(), 'RGBA').save(png)
        csv_path = os.path.join(out_dir, key + '.csv')
        row = comp.row(key)
        write_csv(csv_path, row, replace=False)
        res.update(png=png, csv=csv_path, row=row)
        if csv_out:
            rel = os.path.relpath(os.path.join(out_dir, key), os.path.dirname(os.path.abspath(csv_out)))
            write_csv(csv_out, dict(row, atlas=rel.replace(os.sep, '/')))
            res['csv_out'] = csv_out
        for n in comp.notes:
            log(f'{key}: {n}')
        log(f'{key}: {comp.w}x{comp.h} tiles, {comp.layers_out} layer(s), groups '
            + ', '.join(f'{gt}:{n}' for gt, n, _ in comp.groups) + f', addons {comp.py}, mounts {comp.pz}; '
            f'flags "{row["flags"]}" -> {png}, {csv_path}')
    if preview or preview_only:
        res['preview'] = comp.preview(os.path.join(out_dir, key + '_preview.png'))
        log(f'preview {res["preview"]}')
    res['composer'] = comp
    return res


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('spec', nargs='+')
    ap.add_argument('--ours-dat'); ap.add_argument('--ours-spr')
    ap.add_argument('--lib-dir', help='folder of the donor libraries (donorI/Tibia.dat, ...)')
    ap.add_argument('--out-dir')
    ap.add_argument('--preview', action='store_true', help='also write <key>_preview.png (every direction and frame)')
    ap.add_argument('--preview-only', action='store_true', help='only the contact sheet')
    ap.add_argument('--csv-out', help='also add / replace the row in this things file (atlas path made relative to it)')
    ap.add_argument('--validate', action='store_true', help='check the spec(s) only')
    a = ap.parse_args(argv)
    try:
        if a.validate:
            for p in a.spec:
                load_spec(p)
                print(f'{p}: ok')
            return 0
        if not a.out_dir:
            ap.error('--out-dir is required')
        pairs = Pairs(a.ours_dat, a.ours_spr, a.lib_dir)
        for p in a.spec:
            run(p, pairs, a.out_dir, a.preview, a.preview_only, a.csv_out)
    except SpecError as e:
        print(f'spec error: {e}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
