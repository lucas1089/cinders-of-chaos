#!/usr/bin/env python3
"""Families of code-drawn wings (O583): one generator per shape class, each read from a row of drawn_wings/designs.csv.

A row names a family and a variant, three colours (main, accent, glow), a spark kind and a count. The kit and the
frame rules are gen_drawn_wings.py's; this file only places pieces. Every motion reads the frame phase, so every
design loops in 16 frames. No art file is read.

Likeness to the old art (O587, second pass O590). A row also holds numbers measured once on the old wing of the pair
(`measure DAT SPR --write`, by hand, never at build): `sl`, `sr`, `nl`, `nr`, the strip of the left and the right
wing in the south and the north view (gen_drawn_wings_strip.py: the root, five places along the spine each with the
reach to both sides, the tip; 24 whole numbers, empty when the old art has no wing on that side); `zones`, six
colours of the larger wing (inner, middle and outer third, upper and lower half); `beat`, the share of the silhouette
that moved over the loop; `mould` (free: as the style draws; clip: cut to the strip; fill: cut, and what the style
leaves open is closed in the dark shade of the zone). A style (STYLES, one a family) fills a strip with the material
of its family at strip places (s along, t across), so one style draws a long flat wing and a short upright one. East
and west are the face-on pictures with x and y changed over, as in the old art (render_frame). The repository holds
these numbers only, no picture data. `score DAT SPR [OUT]` prints how far each row is from the old art.

Families: feather, bone, bat, insect, crystal, fan, leaf, energy, orbit (variants: VARIANTS below).
"""
import colorsys
import csv
import math
import os

import numpy as np

import gen_drawn_wings as k
import gen_drawn_wings_strip as st

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, 'drawn_wings', 'designs.csv')
S = k.SIZE
TAU = k.TAU
rad = k.rad
sin, cos = math.sin, math.cos

VARIANTS = {
    'feather': ('pinion', 'angel', 'owl', 'swift', 'plume', 'peacock', 'seraph', 'scaled'),
    'bone': ('rib', 'finger', 'wire'),
    'bat': ('bat', 'dragon', 'torn', 'demon', 'gargoyle'),
    'insect': ('butterfly', 'moth', 'dragonfly', 'fairy', 'beetle', 'ray'),
    'crystal': ('shard', 'cluster', 'needle', 'flake', 'prism', 'pane', 'drop'),
    'fan': ('blade', 'slat', 'web', 'tile', 'ribbon', 'pipe', 'kite', 'fold', 'shell'),
    'leaf': ('oval', 'needle', 'petal', 'maple', 'fern', 'flower'),
    'energy': ('flame', 'cloud', 'bolt', 'water', 'ray', 'veil', 'funnel', 'whirl', 'smoke', 'rain', 'nebula'),
    'orbit': ('firefly', 'circle'),
}
SPARKS = ('none', 'rise', 'fall', 'twinkle')
AMP_PER_BEAT = 0.45          # radians of beat per share of the old wing that moved


# ------------------------------------------------------------------------------------------------ colour
def rgb(text):
    text = text.strip().lstrip('#')
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


def ramp5(colour):
    """five shades round a colour, dark to light: shadows more saturated and cooler, lights paler and warmer"""
    h, s, v = colorsys.rgb_to_hsv(colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0)
    step = max(0.055, min(0.15, v * 0.25))                  # a dark colour keeps dark shades (O587)
    v = k.clamp(v, 0.1 + 2 * step, 1.0 - step)             # a pale colour sits one shade under the light end
    out = []
    for i in (-2, -1, 0, 1, 2):
        vv = k.clamp(v + i * step, 0.0, 1.0)
        ss = k.clamp(s * (1.0 - 0.16 * i), 0.0, 1.0)
        hh = h
        if s > 0.08:
            hh = (h - 0.018 * i * (1 if ((h - 0.11) % 1.0) < 0.5 else -1)) % 1.0
        elif i < 0:
            hh, ss = 0.66, 0.1 * -i                         # a grey or white gets a cool shadow
        r, g, b = colorsys.hsv_to_rgb(hh, ss, vv)
        out.append((int(round(r * 255)), int(round(g * 255)), int(round(b * 255))))
    return tuple(out)


def outline_of(colour):
    h, s, v = colorsys.rgb_to_hsv(colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0)
    r, g, b = colorsys.hsv_to_rgb((h + 0.03) % 1.0 if s > 0.08 else 0.72, max(s, 0.35) * 0.9, 0.13)
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


def hue_turn(colour, turn):
    h, s, v = colorsys.rgb_to_hsv(colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0)
    r, g, b = colorsys.hsv_to_rgb((h + turn) % 1.0, max(s, 0.5), max(v, 0.6))
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


class Spec:
    """one row of designs.csv"""

    def __init__(self, row):
        self.wings = int(row['wings'])
        self.look = int(row['look'])
        self.key = row['key']
        self.name = row['name']
        self.family = row['family']
        self.var = row['variant']
        self.main = rgb(row['main'])
        self.accent = rgb(row['accent'])
        self.glow = rgb(row['glow'])
        self.spark = row['spark']
        self.n = int(row['n'])
        self.old = row.get('old', '')
        self.mould = row.get('mould') or 'free'            # free: as the style draws; clip, fill: held to the old outline
        self.beat = float(row['beat']) if row.get('beat') else None   # the share of the old wing that moved over its loop
        self.amp = 0.07 if self.beat is None else k.clamp(self.beat * AMP_PER_BEAT, 0.03, 0.3)   # the beat, radians
        # the strips of the old wing: {view: (left, right)}, a missing wing is None (gen_drawn_wings_strip.py)
        self.strips = {'south': (st.parse(row.get('sl', '')), st.parse(row.get('sr', ''))),
                       'north': (st.parse(row.get('nl', '')), st.parse(row.get('nr', '')))}
        zones = [rgb(v) for v in row.get('zones', '').split()]
        if len(zones) != 6:
            raise ValueError('%s: zones needs 6 colours' % self.key)
        self.zones = zones                                 # the colour of the inner, middle and outer third, upper and lower half
        self.Z = [ramp5(c) for c in zones]
        self.R = ramp5(self.main)
        self.A = ramp5(self.accent)
        self.outline = outline_of(self.main)
        self.jit = (self.wings * 0.6180339887) % 1.0       # a fixed offset a row, so two rows never move in step
        self.PAL = self.R + self.A + (self.glow,)          # one table for two-colour pieces: 0-4 main, 5-9 accent, 10 glow
        self.ZT = sum(self.Z, ()) + self.R + self.A + (self.glow,)   # zone i shade j: 5 i + j; 30-34 main, 35-39 accent, 40 glow
        if self.family not in VARIANTS or self.var not in VARIANTS[self.family]:
            raise ValueError('%s: no variant %s/%s' % (self.key, self.family, self.var))
        if self.spark not in SPARKS:
            raise ValueError('%s: no spark kind %s' % (self.key, self.spark))


def load(path=CSV):
    with open(path, newline='', encoding='utf-8') as f:
        return [Spec(row) for row in csv.DictReader(f)]


PIVOT = 9.0


# ------------------------------------------------------------------------------------------------ the strip engine
# O590. A wing is a strip (gen_drawn_wings_strip.py): the spine and the reach of the old wing, measured for the south
# and the north view, the left and the right wing. A style fills the strip with the material of its family: it puts
# pieces at strip places (s along, t across), so the same style draws a long flat wing and a short upright one.
# The colours of a wing come from six measured zones (three along, two across): `zones` of the table.
INNER = np.zeros((S, S), bool)
INNER[2:S - 2, 2:S - 2] = True


def _hash(i, j=0):
    """a fixed number in 0..1 for a pair of whole numbers"""
    v = (i * 374761393 + j * 668265263 + 1013904223) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0


NOISE = ((k.XX * 7 + k.YY * 13 + (k.XX * k.YY) % 3) % 5 - 2) * 0.03      # a fixed grain, so zone borders are ragged


class Clip(k.Canvas):
    """a layer that keeps its art off the cell border"""

    def piece(self, mask, idx, ramp, line=None, ring=True):
        k.Canvas.piece(self, mask & INNER, idx, ramp, line=line, ring=ring)


def lum(c):
    return c[0] * 0.3 + c[1] * 0.59 + c[2] * 0.11


_PLACED = {}


def placed(sp, d):
    """(origin, scale) of a row's pair in one face-on view: the model wing and its mirror picture, so the box of the
    pair is centred on the anchor column and so is the meeting point (O714)"""
    key = (sp.key, d)
    if key not in _PLACED:
        v = model_strip(sp, d)
        _PLACED[key] = st.place((v, mirror_strip(v)), amp=sp.amp, tries=40)
    return _PLACED[key]


class G:
    """what a style draws with: one wing (w, bent by the beat; rest, the same wing at rest), its layer, the row"""

    def __init__(self, canvas, w, rest, sp, sc, sgn):
        self.c, self.w, self.rest, self.sp, self.sgn = canvas, w, rest, sp, sgn
        self.ph, self.f, self.d = sc.ph, sc.f, sc.d
        self.full = w

    # -- colours
    def zi(self, s, t):
        return min(2, int(k.clamp(s, 0.0, 0.999) * 3)) * 2 + (0 if t < 0 else 1)

    def ramp(self, s, t):
        """the ramp of the measured zone at a place of the whole wing"""
        return self.sp.Z[self.zi(s, t)]

    def pal2(self, a, b):
        """a table for a piece of two colours: 0-4 the zone at a, 5-9 the zone at b, 10 the glow"""
        return self.ramp(*a) + self.ramp(*b) + (self.sp.glow,)

    # -- pieces
    def piece(self, mask, idx, ramp, line=None, ring=True):
        if not isinstance(idx, np.ndarray):
            idx = np.full((S, S), idx, np.int8)
        self.c.piece(mask, idx.astype(np.int8), ramp, line=line, ring=ring)

    def zonefill(self, mask=None, shade=None, w=None):
        """the wing's body in its zone colours, lit along the upper edge; returns the field (ss, tt) of the whole wing"""
        ss, tt = self.full.field()
        mask = (w or self.full).body() if mask is None else mask
        zi = np.clip(((ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + ((tt + 2 * NOISE) >= 0)
        sh = (2 + (tt < -0.4).astype(np.int8) - (tt > 0.5).astype(np.int8)) if shade is None else shade(ss, tt)
        self.piece(mask, zi * 5 + np.clip(sh, 0, 4), self.sp.ZT)
        return ss, tt

    def rimf(self, q0, q1):
        return lambda u: self.w.rim(q0 + (q1 - q0) * u)

    def linef(self, s0, s1, t0, t1=None):
        t1 = t0 if t1 is None else t1
        return lambda u: self.w.pt(s0 + (s1 - s0) * u, t0 + (t1 - t0) * u)

    def fan(self, n, bases, tips, knots, shader, pal, hwk=0.75, hw=None, bend=0.0, order=-1, minw=1.2, maxw=5.0,
            line=None, sway=0.0, lag=0.6, reach=None):
        """n long pieces from bases(u) to tips(u), u from 0 to 1; the width follows the gap between neighbours;
        `sway` turns each piece a little with the frame, one after the other; returns [(base, tip)]"""
        got = []
        for i in range(n):
            u = i / float(max(1, n - 1))
            b, t = bases(u), tips(u)
            dx, dy = t[0] - b[0], t[1] - b[1]
            if reach is not None:
                r = reach(i)
                dx, dy = dx * r, dy * r
            if sway:
                a = sway * sin(self.ph - lag * i + TAU * self.sp.jit)
                dx, dy = dx * cos(a) - dy * sin(a), dx * sin(a) + dy * cos(a)
            got.append((b, (b[0] + dx, b[1] + dy)))
        if hw is None:
            mids = [(b[0] + (t[0] - b[0]) * 0.7, b[1] + (t[1] - b[1]) * 0.7) for b, t in got]
            gaps = [math.hypot(mids[i + 1][0] - mids[i][0], mids[i + 1][1] - mids[i][1]) for i in range(n - 1)] or [3.0]
            hw = k.clamp(hwk * sum(gaps) / len(gaps), minw, maxw)
        for i in (range(n - 1, -1, -1) if order < 0 else range(n)):
            b, t = got[i]
            if math.hypot(t[0] - b[0], t[1] - b[1]) < 2.5:
                continue
            mask, tt, ss, lit = k.leaf(b, t, hw, knots, bend * self.sgn)
            ramp = pal(i, i / float(max(1, n - 1))) if callable(pal) else pal
            self.c.piece(mask, shader(tt, ss, lit, hw).astype(np.int8), ramp, line=line)
        return got

    def stem(self, places, hw0, hw1, ramp, knob0=0.0, knob1=0.0, shade=(3, 2, 1), w=None):
        m = (w or self.w).line(places, hw0, hw1, knob0, knob1)
        self.piece(m, k.edge_shade(m, *shade), ramp)

    def seg(self, a, b, hw0, hw1, ramp, shade=(3, 2, 1), knob1=0.0):
        """a thick line between two canvas points"""
        m = k.capsule_mask(a, b, hw0, hw1)
        if knob1:
            m |= k.disc_mask(b[0], b[1], knob1)
        self.piece(m, k.edge_shade(m, *shade), ramp)

    def ball(self, x, y, r, ramp, line=None):
        self.piece(k.disc_mask(x, y, r), k.sphere_shade(x, y, r + 0.5), ramp, line=line)

    def motes(self, pts, count=2, reach=12.0):
        """sparks from canvas points: they rise, fall or twinkle (the row's `spark`)"""
        sp = self.sp
        if sp.spark == 'none' or not pts:
            return
        for i in range(count):
            x, y = pts[(i * 2 + (1 if self.sgn > 0 else 0)) % len(pts)]
            q = (self.f / float(k.FRAMES) + i / float(count) + sp.jit + (0.29 if self.sgn > 0 else 0.0)) % 1.0
            if sp.spark == 'twinkle':
                gl = cos(TAU * q)
                if gl > 0.55:
                    self.c.spark(x, y, sp.glow, 2 if gl > 0.93 else 1)
                continue
            x += 2.0 * sin(TAU * (q * 1.2 + i * 0.37))
            y += -reach * q if sp.spark == 'rise' else 3 + reach * q
            if q < 0.4:
                self.c.spark(x, y, sp.glow, 1)
            elif q < 0.8:
                self.c.spark(x, y, sp.glow, 0)

    def glint(self):
        """a light that walks out along the wing once a loop, so every frame is a new picture"""
        q = (self.f / float(k.FRAMES) + self.sp.jit + (0.5 if self.sgn > 0 else 0.0)) % 1.0
        x, y = self.rest.pt(0.12 + 0.8 * q, -0.25)
        xi, yi = int(math.floor(x)), int(math.floor(y))
        if 2 <= xi < S - 2 and 2 <= yi < S - 2 and self.c.op[yi, xi]:
            self.c.spark(x, y, self.sp.glow, 1)
        else:
            x, y = self.rest.pt(0.2 + 0.7 * q, -1.0)
            self.c.spark(x, y - 2, self.sp.glow, 0)

    def stalk(self, hw=1.3, ramp=None, knob=0.0):
        """a wing that begins as a thin stalk: draw the stalk and go on with the head only; returns the share of
        the length that is stalk"""
        s0 = self.full.stalk()
        if s0 < 0.14:
            return 0.0
        s0 = min(s0, 0.7)
        self.stem([(s0 * i / 4.0, 0.0) for i in range(5)] + [(s0 + 0.05, 0.0)], hw, hw * 0.8, ramp or self.ramp(s0 * 0.4, 0.0),
                  knob0=knob, w=self.full)
        self.w = st.Sub(self.full, s0 * 0.92)
        self.rest = st.Sub(self.rest, s0 * 0.92)
        return s0


# ------------------------------------------------------------------------------------------------ shaders, outlines
ROUND = ((0.0, 0.42), (0.12, 0.8), (0.35, 1.0), (0.7, 1.0), (0.87, 0.84), (0.95, 0.6), (1.0, 0.3))
SOFT = ((0.0, 0.38), (0.12, 0.78), (0.36, 1.0), (0.68, 0.96), (0.86, 0.74), (0.95, 0.48), (1.0, 0.2))
PLUME = ((0.0, 0.34), (0.1, 0.74), (0.3, 1.0), (0.58, 0.94), (0.8, 0.68), (0.93, 0.4), (1.0, 0.14))
THORN = ((0.0, 1.0), (1.0, 0.0))
PANE = ((0.0, 0.5), (0.1, 1.0), (0.84, 1.0), (1.0, 0.3))
DROP = ((0.0, 0.2), (0.3, 0.5), (0.62, 1.0), (0.86, 0.9), (1.0, 0.0))
SLAT = ((0.0, 0.6), (0.06, 0.85), (0.9, 1.0), (0.97, 0.8), (1.0, 0.45))
KITE = ((0.0, 0.0), (0.38, 1.0), (1.0, 0.0))
RIBBON = ((0.0, 0.5), (0.2, 1.0), (0.8, 0.8), (1.0, 0.0))
LEAF = ((0.0, 0.12), (0.22, 0.8), (0.5, 1.0), (0.8, 0.66), (1.0, 0.0))
PETAL = ((0.0, 0.2), (0.3, 0.86), (0.64, 1.0), (0.9, 0.72), (1.0, 0.12))
TONGUE = ((0.0, 0.7), (0.16, 1.0), (0.45, 0.8), (0.75, 0.42), (1.0, 0.0))
RAY = ((0.0, 0.25), (0.45, 1.0), (1.0, 0.0))
BAR = ((0.0, 0.9), (0.05, 1.0), (0.95, 1.0), (1.0, 0.9))
POINT = ((0.0, 0.3), (0.12, 0.8), (0.4, 1.0), (0.7, 0.8), (0.9, 0.42), (1.0, 0.0))
BLADE = ((0.0, 0.34), (0.12, 0.8), (0.4, 1.0), (0.72, 0.9), (0.9, 0.62), (1.0, 0.22))



def feather_shader(row, tip_from, bars=False, shaft_idx=7):
    """ramp index in a two-colour table: 0-4 the body colour, 5-9 the tip colour, 10 the glow. The vane is one shade
    lighter on the lit side, the shaft is a line, the root lies in the shadow of the row above"""
    def shader(tt, ss, lit, hw):
        base = (2, 3, 2, 3, 2)[row]                       # the rows differ by a shade, so the layers read
        idx = np.full(tt.shape, base, np.int8) + lit.astype(np.int8)
        idx = idx - (tt < 0.2).astype(np.int8) + ((tt > 0.8) & lit).astype(np.int8)
        if bars:
            idx = idx - (((tt * 5.0 + 0.3).astype(np.int32) % 2) == 1).astype(np.int8)
        idx = np.clip(idx, 0, 4)
        shaft = (np.abs(ss) * hw < 0.6) & (tt > 0.08) & (tt < 0.9) & (hw > 1.9)
        idx[shaft] = shaft_idx
        return np.where(tt > tip_from, idx + 5, idx).astype(np.int8)
    return shader


def flat_shader(base=2, tip_from=2.0, mid=None):
    """a plain piece: lit side a shade up, the root a shade down; past tip_from the second colour of the table;
    `mid`: the index of a line down the middle"""
    def shader(tt, ss, lit, hw):
        idx = np.clip(base + lit.astype(np.int8) - (tt < 0.18).astype(np.int8), 0, 4)
        if mid is not None:
            idx[(np.abs(ss) * hw < 0.55) & (tt > 0.06) & (tt < 0.92) & (hw > 1.7)] = mid
        return np.where(tt > tip_from, idx + 5, idx).astype(np.int8)
    return shader


def glass_shader(tt, ss, lit, hw):
    idx = np.where(lit, 3, 1).astype(np.int8)
    idx = idx + (tt > 0.7) - ((tt < 0.2) & ~lit)
    idx[(np.abs(ss) * hw < 0.55) & lit & (tt > 0.12) & (hw > 1.6)] = 4
    return idx


def leaf_shader(tt, ss, lit, hw):
    idx = (2 + lit - (tt < 0.22) + ((tt > 0.75) & lit)).astype(np.int8)
    idx[(np.abs(ss) * hw < 0.5) & (tt < 0.8) & (hw > 2.4)] = 1
    return idx


def flame_shader(tt, ss, lit, hw):
    """hot in the middle and at the root, the second colour at the tip"""
    idx = (3 - (np.abs(ss) > 0.55) + (tt < 0.3)).astype(np.int8)
    idx = np.clip(idx, 1, 4)
    return np.where(tt > 0.62, idx + 5 - 1, idx).astype(np.int8)


# ------------------------------------------------------------------------------------------------ feather
def st_feather(g):
    """an arm with rows of feathers: the flight row hangs from the arm to the lower edge and fans round the tip,
    rows of coverts lie over its roots, each shorter and a shade apart. Rounded tips, a shaft line, a two-tone vane"""
    sp, var = g.sp, g.sp.var
    g.stalk(1.5)
    w = g.w
    knots = POINT if var in ('swift', 'pinion', 'plume', 'seraph') else BLADE
    n = int(k.clamp(round(w.length / (4.6 if var == 'swift' else 3.8)) + sp.n, 4, 14))
    wide = (w.half(0.5, -1) + w.half(0.5, 1))
    thin = wide < 7.0
    g.zonefill(shade=lambda ss, tt: np.where(tt < -0.55, 1, 2))
    slant = 0.34 if var in ('swift', 'pinion', 'seraph') else 0.26
    spiky = var == 'plume'
    reach = (lambda i: 1.0 + 0.12 * _hash(i, sp.wings)) if spiky else (lambda i: 1.0 - 0.06 * _hash(i, sp.wings))

    def tip_of(u):                                        # the lower edge, then round the tip of the wing
        s = 0.06 + 0.9 * u + slant
        return w.pt(s, 1.05) if s <= 1.0 else w.pt(1.0 + 0.04 * (s - 1.0), 1.05 - 2.6 * (s - 1.0))
    got = g.fan(n, g.linef(0.02, 0.86, -0.35 if not thin else -0.7), tip_of, knots,
                feather_shader(0, 0.7, var == 'owl'), lambda i, u: g.ramp(0.9 * u, 0.5) + sp.A + (sp.glow,),
                hwk=0.62, bend=0.6, sway=0.035, reach=reach, maxw=3.4, minw=1.3, order=1)
    tips = [t for b, t in got]
    dark = g.ramp(0.4, -0.5)[0]
    if not thin:
        g.fan(max(3, n - 2), g.linef(0.0, 0.8, -0.95), lambda u: w.pt(0.1 + 0.8 * u + slant * 0.7, 0.05), knots,
              feather_shader(1, 2.0), lambda i, u: g.pal2((0.8 * u, -0.5), (0.8 * u, -0.5)), hwk=0.6, sway=0.025,
              line=dark, maxw=3.0, order=1)
        if var in ('angel', 'scaled', 'owl', 'plume', 'peacock') and wide > 12.0:
            g.fan(max(3, n - 3), g.linef(0.0, 0.62, -1.0), lambda u: w.pt(0.08 + 0.62 * u + slant * 0.5, -0.45), knots,
                  feather_shader(2, 2.0), lambda i, u: g.pal2((0.7 * u, -0.5), (0.7 * u, -0.5)), hwk=0.6, line=dark,
                  maxw=2.6, order=1)
    g.stem([(0.0, -0.75), (0.35, -0.95), (0.8, -0.95), (0.97, -0.5)], 1.1, 0.7, g.ramp(0.5, -0.5), shade=(2, 1, 0))
    if var in ('angel', 'scaled', 'seraph'):              # a bright arm lies on the wing
        g.stem([(0.0, -0.5), (0.3, -0.88), (0.72, -0.94)], 1.4, 0.8, sp.A, shade=(4, 3, 1))
    if var == 'peacock':
        for i, (b, t) in enumerate(got):
            if i % 2 == 0:
                x, y = b[0] + (t[0] - b[0]) * 0.82, b[1] + (t[1] - b[1]) * 0.82
                m = k.disc_mask(x, y, 2.4)
                idx = np.full((S, S), 6, np.int8)
                idx[k.disc_mask(x, y, 1.5)] = 1
                idx[k.disc_mask(x, y, 0.8)] = 10
                g.piece(m, idx, sp.PAL, ring=False)
    if var == 'scaled':
        x, y = w.pt(0.06, -0.2)
        g.ball(x, y, 2.3, ramp5(sp.glow))
    if var == 'seraph':                                   # gold on the tips
        for i, (b, t) in enumerate(got):
            if i % 3 == 1:
                g.c.spark(t[0], t[1], sp.glow, 1 if (i + g.f // 4) % 2 else 0)
    g.motes(tips, 3)


# ------------------------------------------------------------------------------------------------ bat
def st_bat(g):
    """an arm to a wrist, fingers from the wrist to the lower edge, a membrane between them with a scalloped edge"""
    sp, var = g.sp, g.sp.var
    g.stalk(1.6, sp.A)
    w = g.w
    nf = {'bat': 4, 'dragon': 5, 'torn': 4, 'demon': 4, 'gargoyle': 3}[var] + sp.n
    nf = max(3, min(6, nf if w.length > 26 else nf - 1))
    wrist = w.pt(0.4, -0.72)
    elbow = w.pt(0.18, -0.2)
    root = w.pt(0.0, 0.0)
    tips = []
    for i in range(nf):
        q = 0.05 + 0.47 * i / float(nf - 1)
        x, y = w.rim(q + 0.012 * sin(g.ph - 0.7 * i))
        tips.append((x, y))
    mask = w.body()
    for i in range(nf - 1):                               # the scallops between the finger tips
        mx, my = (tips[i][0] + tips[i + 1][0]) / 2.0, (tips[i][1] + tips[i + 1][1]) / 2.0
        gap = math.hypot(tips[i + 1][0] - tips[i][0], tips[i + 1][1] - tips[i][1])
        dx, dy = mx - wrist[0], my - wrist[1]
        ln = math.hypot(dx, dy) or 1.0
        mask &= ~k.disc_mask(mx + dx / ln * gap * 0.33, my + dy / ln * gap * 0.33, gap * 0.52)
    ang = np.arctan2(k.PY - wrist[1], k.PX - wrist[0])
    a0 = math.atan2(tips[0][1] - wrist[1], tips[0][0] - wrist[0])
    rel = (ang - a0 + math.pi) % TAU - math.pi
    fa = sorted(((math.atan2(t[1] - wrist[1], t[0] - wrist[0]) - a0 + math.pi) % TAU - math.pi) for t in tips)
    panel = np.zeros((S, S), np.int32)
    for a in fa:
        panel += rel > a
    ss, tt = g.full.field()
    idx = 2 - (panel % 2) + (tt < -0.45)
    if var == 'gargoyle':                                 # stone: flat, a crack
        idx = np.where(np.abs(((ss * 7.0 + tt * 1.5) % 1.0) - 0.5) < 0.07, 0, idx)
    if var == 'torn':
        for i in range(nf - 1):
            mx, my = (tips[i][0] + tips[i + 1][0] + wrist[0]) / 3.0, (tips[i][1] + tips[i + 1][1] + wrist[1]) / 3.0
            if i % 2 == 0:
                mask &= ~k.disc_mask(mx, my, 1.9)
    zi = np.clip(((ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + 1
    g.piece(mask, zi * 5 + np.clip(idx, 0, 4), sp.ZT, line=g.ramp(0.5, 0.5)[0])
    bone = sp.A if lum(sp.accent) > lum(g.ramp(0.5, 0.5)[2]) + 12 else g.ramp(0.2, -0.5)
    bhw = {'bat': 0.6, 'dragon': 0.75, 'torn': 0.6, 'demon': 0.8, 'gargoyle': 1.1}[var]
    for i in range(nf - 1, -1, -1):
        g.seg(wrist, tips[i], bhw, bhw * 0.55, bone)
        if var in ('dragon', 'demon', 'gargoyle'):
            dx, dy = tips[i][0] - wrist[0], tips[i][1] - wrist[1]
            ln = math.hypot(dx, dy) or 1.0
            g.seg(tips[i], (tips[i][0] + dx / ln * 2.4, tips[i][1] + dy / ln * 2.4), 0.8, 0.4, bone, shade=(4, 3, 2))
    if var == 'demon':
        for s in (0.12, 0.26, 0.4):
            b = w.pt(s, -0.8)
            e = w.pt(s + 0.03, -1.0)
            dx, dy = e[0] - b[0], e[1] - b[1]
            ln = math.hypot(dx, dy) or 1.0
            g.seg(b, (b[0] + dx / ln * 4.5, b[1] + dy / ln * 4.5), 1.1, 0.4, ramp5(sp.glow), shade=(3, 2, 2))
    g.seg(elbow, wrist, bhw + 0.6, bhw + 0.4, bone, knob1=bhw + 1.0)
    g.seg(root, elbow, bhw + 0.8, bhw + 0.6, bone, knob1=bhw + 1.1)
    up = w.pt(0.44, -1.0)
    g.seg(wrist, (up[0] + (up[0] - wrist[0]) * 0.8, up[1] + (up[1] - wrist[1]) * 0.8), 1.0, 0.5, bone, shade=(4, 3, 2))
    g.motes(tips, 2)


# ------------------------------------------------------------------------------------------------ insect
def st_insect(g):
    """a wing of one sheet: veins that fan from the root, a border, the pattern of its kind"""
    sp, var = g.sp, g.sp.var
    g.stalk(1.2)
    w = g.w
    ss, tt = w.field()
    mask = w.body()
    at = np.abs(tt)
    full_ss, _ = g.full.field()
    zi = np.clip(((full_ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + ((tt + 2 * NOISE) >= 0)
    base = zi * 5
    A = 35
    if var in ('dragonfly', 'fairy'):                     # clear wings: pale, a net of veins
        sh = 3 + (tt < -0.25).astype(np.int8) - (tt > 0.6).astype(np.int8)
        idx = base + np.clip(sh, 0, 4)
        vein = (at < 0.13) | ((((ss * (9 if var == 'dragonfly' else 6)) % 1.0) < 0.2) & (at > 0.2))
        idx = np.where(vein & (ss < 0.93), base + 1, idx)
        if var == 'fairy':
            idx = np.where((tt < -0.45) & (tt > -0.8) & (ss > 0.2) & (ss < 0.8), base + 4, idx)
        else:
            idx = np.where((ss > 0.8) & (ss < 0.92) & (tt < -0.3), A + 1, idx)      # the dark mark near the tip
    elif var == 'beetle':                                 # a hard shell over a soft wing
        sh = 2 + (tt < -0.2).astype(np.int8) + ((tt < -0.45) & (tt > -0.75)).astype(np.int8) - (tt > 0.25).astype(np.int8)
        idx = base + np.clip(sh, 0, 4)
        idx = np.where(np.abs(tt - 0.05) < 0.1, base + 0, idx)
        idx = np.where((tt > 0.5), A + 3 - ((ss * 8).astype(np.int32) % 2), idx)
    elif var == 'ray':                                    # a fin: dark above, pale below, spots
        sh = 2 + (tt < -0.5).astype(np.int8) - (tt > 0.2).astype(np.int8)
        idx = base + np.clip(sh, 0, 4)
        idx = np.where((tt > 0.62), A + 3, idx)
        spot = (((ss * 6.0) % 1.0 - 0.5) ** 2 + ((tt * 1.5 + 0.2) % 1.0 - 0.5) ** 2) < 0.03
        idx = np.where(spot & (tt < 0.5), base + 4, idx)
    else:                                                 # butterfly, moth: veins, a dark border, dots on it
        sh = 2 + (tt < -0.3).astype(np.int8) - (tt > 0.55).astype(np.int8)
        idx = base + np.clip(sh, 0, 4)
        fanv = np.abs(((tt * 2.6 + ss * 0.4) % 1.0) - 0.5) < 0.09
        border = (at > 0.7) | (ss > 0.9)
        dark = A if lum(sp.accent) < lum(sp.main) else base
        idx = np.where(fanv & ~border & (ss > 0.08), dark + 1, idx)
        idx = np.where(border, dark + (1 if var == 'butterfly' else 2) - (tt > 0).astype(np.int8) * 0, idx)
        dots = border & (((ss * 11).astype(np.int32) % 2) == 0) & (at > 0.8) & (at < 1.0) & (ss > 0.2)
        idx = np.where(dots, 40, idx)
    g.piece(mask, idx, sp.ZT)
    if var == 'moth':                                     # the eye
        x, y = w.pt(0.62, 0.1)
        r = k.clamp(w.half(0.62, 1) * 0.55, 1.6, 3.2)
        m = k.disc_mask(x, y, r) & mask & ~k.dilate4(~mask)
        idx2 = np.full((S, S), A + 0, np.int32)
        idx2[k.disc_mask(x, y, r * 0.55)] = 40
        g.piece(m, idx2, sp.ZT, ring=False)
    if var == 'fairy':
        for i in range(3):
            x, y = w.pt(0.3 + 0.25 * i, -0.2 + 0.5 * _hash(i, sp.wings))
            if mask[int(k.clamp(y, 0, S - 1)), int(k.clamp(x, 0, S - 1))]:
                g.c.spark(x, y, sp.glow, 1 if (i + g.f // 3) % 3 == 0 else 0)
    g.motes([w.rim(0.2), w.rim(0.4), w.rim(0.5), w.rim(0.7)], 2)


# ------------------------------------------------------------------------------------------------ crystal
def st_crystal(g):
    sp, var = g.sp, g.sp.var
    s0 = g.stalk(1.3)
    w = g.w
    if var == 'drop':                                     # a drop of sap: one smooth body, a shine, a drip
        ss, tt = g.zonefill(shade=lambda ss, tt: 2 + (tt < -0.2).astype(np.int8) + ((tt < -0.35) & (tt > -0.7) & (ss > 0.3) & (ss < 0.8)).astype(np.int8) - (tt > 0.5).astype(np.int8))
        x, y = w.pt(0.55, 0.9)
        q = (g.f / float(k.FRAMES) + sp.jit) % 1.0
        g.ball(x, y + 2 + 9 * q, 1.3 if q < 0.7 else 0.9, sp.Z[3])
        g.motes([w.rim(0.3), w.rim(0.5)], 2)
        return
    if var == 'needle':                                   # icicles hang from an arm
        n = int(k.clamp(round(w.length / 4.2) + sp.n, 5, 12))
        got = g.fan(n, g.linef(0.04, 0.96, -0.55), g.linef(0.04, 0.99, 1.0), k.SHARD, glass_shader,
                    lambda i, u: g.ramp(u, 0.5), hwk=0.6, maxw=2.4, sway=0.03,
                    reach=lambda i: 1.0 + 0.12 * sin(g.ph - 0.8 * i))
        g.stem([(i / 8.0, -0.55) for i in range(9)], 1.6, 1.0, g.ramp(0.3, -0.5), shade=(4, 3, 1))
        tips = [t for b, t in got]
    elif var == 'flake':                                  # a six-armed flake on the head
        x, y, r = w.mid()
        r = max(r, w.length * 0.4, 5.0)
        tips = []
        turn = 0.12 * sin(g.ph)
        for j in range(6):
            a = turn + TAU * j / 6.0
            ex, ey = x + r * cos(a), y + r * sin(a)
            g.seg((x, y), (ex, ey), 1.1, 0.8, g.ramp(0.6, 0.0), shade=(4, 3, 2))
            for u in (0.5, 0.78):
                for side in (-1, 1):
                    bx, by = x + r * u * cos(a), y + r * u * sin(a)
                    g.seg((bx, by), (bx + r * 0.3 * cos(a + side * 0.9), by + r * 0.3 * sin(a + side * 0.9)), 0.8, 0.5,
                          g.ramp(0.9, 0.0), shade=(4, 3, 2))
            tips.append((ex, ey))
        g.ball(x, y, 1.8, g.ramp(0.5, 0.0))
    else:                                                 # shards that burst from the spine to both edges
        knots = PANE if var == 'pane' else k.SHARD
        n = int(k.clamp(round(w.length / (5.5 if var == 'pane' else 4.6)) + sp.n, 4, 11))
        if var in ('pane', 'prism'):                      # a fan of panes from the arm to the lower edge
            def pal(i, u):
                if var == 'prism' or sp.key == 'rose_window':
                    return ramp5(hue_turn(sp.main, i / float(n)))
                return g.ramp(0.2 + 0.8 * u, 0.5)
            g.piece(w.region(0.0, 0.94, -0.8, 0.5), 1, g.ramp(0.4, 0.0))
            got = g.fan(n, g.linef(0.0, 0.7, -0.7), g.rimf(0.04, 0.6), knots, glass_shader, pal, hwk=0.72, sway=0.03,
                        reach=lambda i: 1.0 + 0.06 * sin(g.ph - 0.7 * i))
            g.stem([(0.0, -0.6), (0.35, -0.85), (0.72, -0.9)], 1.2, 0.7, g.ramp(0.2, -0.5), shade=(4, 3, 1))
        else:
            order = sorted(range(n), key=lambda i: _hash(i, sp.wings))
            got = []
            for i in order:
                u = i / float(n - 1)
                b = w.pt(0.05 + 0.6 * u, 0.0)
                t = w.rim(0.08 + 0.84 * ((i * 0.618 + 0.3 * u) % 1.0)) if var == 'cluster' else w.rim(0.06 + 0.56 * u)
                pulse = 1.0 + 0.1 * sin(g.ph - 0.75 * i + TAU * sp.jit)
                t = (b[0] + (t[0] - b[0]) * pulse, b[1] + (t[1] - b[1]) * pulse)
                if math.hypot(t[0] - b[0], t[1] - b[1]) < 3:
                    continue
                m, tt_, ss_, lit = k.leaf(b, t, k.clamp(w.length / n * 0.62, 1.8, 3.6), knots)
                g.c.piece(m, glass_shader(tt_, ss_, lit, 2.5), g.ramp(0.1 + 0.85 * u, 0.5 if i % 2 else -0.5))
                got.append((b, t))
        tips = [t for b, t in got]
        for i, (b, t) in enumerate(got):
            gl = cos(g.ph - TAU * i / float(max(1, len(got))) + TAU * sp.jit)
            if gl > 0.75:
                g.c.spark(b[0] + (t[0] - b[0]) * 0.8, b[1] + (t[1] - b[1]) * 0.8, sp.glow, 2 if gl > 0.94 else 1)
    g.motes(tips, 2)


# ------------------------------------------------------------------------------------------------ leaf
def _head_petals(g, x, y, r, n, ramp, heart, heart_r, turn=0.0, knots=PETAL):
    for j in range(n):
        a = turn + TAU * j / float(n)
        m, tt, ss, lit = k.leaf((x + heart_r * 0.5 * cos(a), y + heart_r * 0.5 * sin(a)), (x + r * cos(a), y + r * sin(a)),
                                max(1.3, r * math.pi / n * 0.8), knots)
        g.c.piece(m, leaf_shader(tt, ss, lit, 2.0), ramp)
    if heart_r:
        g.ball(x, y, heart_r, heart)


def st_leaf(g):
    sp, var = g.sp, g.sp.var
    green = g.ramp(0.15, 0.0)
    s0 = g.stalk(1.3, green)
    w = g.w
    tips = []
    if var in ('petal', 'flower'):                        # a flower head on its stalk
        x, y, r = w.mid()
        r = max(r, w.length * 0.42, 5.5)
        turn = 0.1 * sin(g.ph) + TAU * sp.jit
        if var == 'flower':
            _head_petals(g, x, y, r, 12, g.ramp(0.95, -0.5), sp.A if lum(sp.accent) < 120 else g.ramp(0.7, 0.5), r * 0.45, turn, LEAF)
            lx, ly = g.full.pt(max(0.1, s0 * 0.5), 0.0)
            m, tt, ss, lit = k.leaf((lx, ly), (lx + 6 * g.sgn, ly + 3 + sin(g.ph)), 2.4, LEAF)
            g.c.piece(m, leaf_shader(tt, ss, lit, 2.4), green)
        else:
            _head_petals(g, x, y, r, 6, g.ramp(0.8, 0.5), ramp5(sp.glow), 1.8, turn + 0.3)
            _head_petals(g, x, y, r * 0.62, 5, g.ramp(0.6, -0.5), ramp5(sp.glow), 1.8, -turn)
        tips = [(x + r * cos(TAU * j / 5.0), y + r * sin(TAU * j / 5.0)) for j in range(5)]
        g.motes(tips, 2)
        return
    if var == 'needle':                                   # stems with thorns, a bloom at each end
        for j, t in enumerate((-0.6, 0.0, 0.6)):
            pl = [(i / 6.0 * (0.8 + 0.1 * j), t * (0.3 + 0.7 * i / 6.0)) for i in range(7)]
            g.stem(pl, 1.0, 0.7, green)
            x, y = w.pt(*pl[-1])
            g.ball(x, y, 2.6 + 0.3 * sin(g.ph - j), g.ramp(0.95, t))
            tips.append((x, y))
            for i in (2, 4):
                b = w.pt(*pl[i])
                g.seg(b, (b[0] + 2.2 * g.sgn, b[1] - 2.0), 0.7, 0.3, green, shade=(4, 3, 2))
        g.motes(tips, 2)
        return
    n = int(k.clamp(round(w.length / (3.4 if var == 'fern' else 5.0)) + sp.n, 4, 14))
    if var == 'fern' and sp.key == 'dandelion_seed':      # seed heads on a bent stalk
        g.stem([(i / 8.0, 0.0) for i in range(9)], 1.0, 0.7, green)
        for i in range(n):
            u = i / float(n - 1)
            x, y = w.pt(0.15 + 0.85 * u, (-0.75 if i % 2 else 0.75))
            x += 0.8 * sin(g.ph - 0.6 * i)
            g.ball(x, y, 2.0, g.ramp(0.3 + 0.7 * u, -0.5 if i % 2 else 0.5))
            tips.append((x, y))
        g.motes(tips, 3)
        return
    knots = LEAF
    hw = None
    for side in (-1, 1):                                  # leaves to both sides of a twig
        def bases(u):
            return w.pt(0.06 + 0.8 * u, 0.0)

        def ends(u, side=side):
            return w.pt(min(1.0, 0.16 + 0.86 * u), side * 1.0)
        if var == 'maple':
            for i in range(n // 2, -1, -1):
                u = i / float(max(1, n // 2))
                b, t = bases(u), ends(u)
                a0 = math.atan2(t[1] - b[1], t[0] - b[0]) + 0.1 * sin(g.ph - 0.7 * i)
                ln = math.hypot(t[0] - b[0], t[1] - b[1]) * 1.05
                for da, share in ((-0.75, 0.62), (0.75, 0.62), (-0.36, 0.86), (0.36, 0.86), (0.0, 1.0)):
                    m, tt, ss, lit = k.leaf(b, (b[0] + ln * share * cos(a0 + da), b[1] + ln * share * sin(a0 + da)), max(1.4, ln * 0.2), LEAF)
                    g.c.piece(m, leaf_shader(tt, ss, lit, 2.0), g.ramp(0.1 + 0.85 * u, side * 0.5), line=g.ramp(0.5, side * 0.5)[1])
                tips.append(t)
            continue
        got = g.fan(n if var == 'fern' else max(3, n // 2 + 1), bases, ends, knots, leaf_shader,
                    lambda i, u, side=side: g.ramp(0.1 + 0.85 * u, side * 0.5), hwk=0.62 if var == 'fern' else 0.78,
                    sway=0.07, maxw=4.0 if var != 'fern' else 2.2, bend=0.8 * side)
        tips += [t for b, t in got]
    g.stem([(i / 8.0, 0.0) for i in range(9)], 1.3, 0.7, sp.A if var != 'fern' else green, shade=(3, 2, 1))
    g.motes(tips, 3)


# ------------------------------------------------------------------------------------------------ bone
def st_bone(g):
    sp, var = g.sp, g.sp.var
    w = g.w
    bone = g.ramp(0.5, 0.0)
    tips = []
    if var == 'rib':                                      # an arm, curled ribs hang from it
        n = int(k.clamp(round(w.length / 5.0) + sp.n, 4, 9))
        for i in range(n - 1, -1, -1):
            u = i / float(n - 1)
            s = 0.08 + 0.84 * u
            curl = 0.1 + 0.03 * sin(g.ph - 0.7 * i)
            pl = [(s, -0.6), (s + curl * 0.4, 0.0), (s + curl * 0.8, 0.6), (s + curl * 0.6, 1.0)]
            g.stem(pl, 1.1, 0.6, g.ramp(s, 0.5), knob1=1.1, shade=(4, 3, 1))
            tips.append(w.pt(*pl[-1]))
        g.stem([(i / 8.0, -0.62) for i in range(9)], 1.9, 1.1, g.ramp(0.3, -0.5), knob0=2.2, knob1=1.5, shade=(4, 3, 1))
    else:                                                 # finger: bones that fan from the root; wire: thin, beads
        n = int(k.clamp(round((w.half(0.6, -1) + w.half(0.6, 1)) / (3.6 if var == 'wire' else 4.2)) + sp.n, 3, 8))
        for i in range(n):
            u = i / float(max(1, n - 1))
            q = 0.1 + 0.8 * u + 0.02 * sin(g.ph - 0.8 * i)
            tx, ty = w.rim(q)
            b = w.pt(0.02, 0.0)
            mid = w.pt(0.45, (0.5 - u) * 1.3)
            ramp = g.ramp(0.6, 0.5 if u < 0.5 else -0.5)
            hw = 0.75 if var == 'wire' else 1.15
            g.seg(b, mid, hw + 0.3, hw, ramp, shade=(4, 3, 1))
            g.seg(mid, (tx, ty), hw, hw * 0.7, ramp, shade=(4, 3, 1), knob1=1.5 if var != 'wire' else 0.0)
            if var == 'wire':
                for j in range(1, 4):
                    x, y = mid[0] + (tx - mid[0]) * j / 3.0, mid[1] + (ty - mid[1]) * j / 3.0
                    g.ball(x, y, 1.5, g.ramp(0.9, 0.0) if j == 3 else ramp)
            tips.append((tx, ty))
        g.ball(*(w.pt(0.03, 0.0) + (2.0, g.ramp(0.1, 0.0))))
    g.motes(tips, 2)


# ------------------------------------------------------------------------------------------------ fan
def st_fan(g):
    sp, var = g.sp, g.sp.var
    wood = g.ramp(0.12, 0.0)
    s0 = g.stalk(1.4, wood)
    w = g.w
    tips = []
    if var in ('web', 'shell'):                           # sticks that fan from the root, a web between them
        ss, tt = w.field()
        mask = w.body()
        if var == 'shell':                                # a scalloped edge
            n = int(k.clamp(round((w.half(0.8, -1) + w.half(0.8, 1)) / 3.4), 4, 8))
            for i in range(n):
                x, y = w.rim(0.12 + 0.76 * (i + 0.5) / n)
                c = w.pt(0.5, 0.0)
                d = math.hypot(x - c[0], y - c[1]) or 1.0
                mask &= ~k.disc_mask(x + (x - c[0]) / d * 1.2, y + (y - c[1]) / d * 1.2, 1.5)
        ridge = np.abs(((tt * (3.2 if var == 'shell' else 4.2)) % 1.0) - 0.5)
        full_ss, _ = g.full.field()
        zi = np.clip(((full_ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + (tt >= 0)
        sh = 2 + (ridge > 0.3).astype(np.int8) - (ridge < 0.12).astype(np.int8) + (tt < -0.6).astype(np.int8)
        if var == 'shell':
            sh = sh - (np.abs(((ss * 3.3) % 1.0) - 0.5) < 0.08).astype(np.int8)      # growth lines
        idx = zi * 5 + np.clip(sh, 0, 4)
        if var == 'web':
            idx = np.where((ss > 0.86) & (np.abs(tt) < 1.0), 35 + 2 + (ridge > 0.3), idx)   # the trim of the edge
            if sp.key in ('salamander_fan', 'koi_fin'):
                spot = (((ss * 5.0) % 1.0 - 0.5) ** 2 + ((tt * 2.0) % 1.0 - 0.5) ** 2) < 0.04
                idx = np.where(spot & (ss < 0.84), 35 + 1, idx)
        g.piece(mask, idx, sp.ZT)
        n = int(k.clamp(round((w.half(0.8, -1) + w.half(0.8, 1)) / 4.0) + sp.n, 3, 8))
        if var == 'web':
            for i in range(n):
                x, y = w.rim(0.1 + 0.8 * i / float(n - 1))
                g.seg(w.pt(0.02, 0.0), (x, y), 0.8, 0.5, wood, shade=(4, 3, 1))
                tips.append((x, y))
        g.ball(*(w.pt(0.03, 0.0) + (1.9, ramp5(sp.glow) if var == 'web' else g.ramp(0.1, 0.0))))
        tips = tips or [w.rim(0.2), w.rim(0.5), w.rim(0.8)]
    elif var == 'tile':                                   # plates in rows, each over the next
        ss, tt = w.field()
        mask = w.body()
        rows = 3 if w.width > 12 else 2
        cols = int(k.clamp(round(w.length / 7.0), 3, 8))
        r = np.floor((tt + 1.0) / 2.0 * rows).astype(np.int32)
        cu = ss * cols + (r % 2) * 0.5
        c = np.floor(cu).astype(np.int32)
        fu, fv = cu - c, ((tt + 1.0) / 2.0 * rows) % 1.0
        full_ss, _ = g.full.field()
        zi = np.clip(((full_ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + (tt >= 0)
        sh = 2 + ((fu < 0.3) | (fv < 0.25)).astype(np.int8) - ((fu > 0.82) | (fv > 0.85)).astype(np.int8) * 2 - ((c + r) % 3 == 0).astype(np.int8)
        g.piece(mask, zi * 5 + np.clip(sh, 0, 4), sp.ZT)
        g.stem([(i / 6.0 * 0.9, -0.1) for i in range(7)], 1.0, 0.6, wood)
        tips = [w.rim(0.2), w.rim(0.4), w.rim(0.6)]
    elif var == 'ribbon':                                 # bands that stream from the root
        n = max(3, min(6, 4 + sp.n))
        for i in range(n):
            u = i / float(n - 1)
            t1 = -1.0 + 2.0 * u
            wave = 0.35 * sin(g.ph - 1.3 * i)
            pl = [(j / 8.0, t1 * (j / 8.0) ** 0.8 + wave * sin(math.pi * j / 8.0) * 0.6) for j in range(9)]
            g.stem(pl, 1.5, 0.6, g.ramp(0.7, t1), shade=(4, 3, 1))
            tips.append(w.pt(*pl[-1]))
    elif var == 'pipe':                                   # pipes side by side across the blade
        n = int(k.clamp(round(w.length / 3.6) + sp.n, 5, 16))
        got = g.fan(n, g.linef(0.03, 0.97, -1.0), g.linef(0.03, 0.97, 1.0), BAR, flat_shader(2, mid=4), lambda i, u: g.ramp(u, 0.0),
                    hwk=0.46, maxw=2.0, sway=0.02, reach=lambda i: 0.82 + 0.18 * abs(sin(1.7 * i + 0.4)) + 0.04 * sin(g.ph - 0.5 * i))
        for b, t in got:
            g.ball(t[0], t[1], 1.0, (g.ramp(0.5, 0.0)[0],) * 5)
        g.stem([(i / 6.0, -0.2) for i in range(7)], 1.0, 0.8, sp.A, shade=(4, 3, 1))
        tips = [t for b, t in got]
    elif var == 'kite':                                   # a head on a stick: a kite, a pinwheel
        x, y, r = w.mid()
        r = max(r, w.length * 0.42, 6.0)
        if sp.key == 'pinwheel':
            turn = g.ph
            for j in range(4):
                a = turn + TAU * j / 4.0
                tip = (x + r * cos(a), y + r * sin(a))
                side = (x + r * 0.7 * cos(a + 0.9), y + r * 0.7 * sin(a + 0.9))
                m = k.poly_mask([(x, y), tip, side])
                g.piece(m, k.edge_shade(m, 4, 3, 2), ramp5(hue_turn(sp.main, j / 4.0)) if j % 2 else g.ramp(0.8, 0.0))
                tips.append(tip)
            g.ball(x, y, 1.6, ramp5(sp.glow))
        else:
            a = math.atan2(w.pt(1.0, 0)[1] - w.pt(0.0, 0)[1], w.pt(1.0, 0)[0] - w.pt(0.0, 0)[0]) + 0.05 * sin(g.ph)
            p = [(x + r * 1.25 * cos(a), y + r * 1.25 * sin(a)), (x + r * 0.75 * cos(a + 1.57), y + r * 0.75 * sin(a + 1.57)),
                 (x - r * 1.25 * cos(a), y - r * 1.25 * sin(a)), (x + r * 0.75 * cos(a - 1.57), y + r * 0.75 * sin(a - 1.57))]
            for j in range(4):
                m = k.poly_mask([(x, y), p[j], p[(j + 1) % 4]])
                g.piece(m, k.edge_shade(m, 4, 3, 2) - (j % 2), g.ramp(0.8, 0.5 if j < 2 else -0.5), line=g.ramp(0.8, 0.0)[0])
            g.seg(p[0], p[2], 0.7, 0.7, sp.A, shade=(4, 3, 2))
            g.seg(p[1], p[3], 0.7, 0.7, sp.A, shade=(4, 3, 2))
            tx, ty = p[2]
            for j in range(4):                            # the tail streams
                nx_, ny_ = tx + 3 * g.sgn * 0 + 2.0 * sin(g.ph - j), ty + 3.0
                g.seg((tx, ty), (nx_, ny_), 0.7, 0.5, ramp5(sp.glow), shade=(3, 2, 2))
                tx, ty = nx_, ny_
            tips = p
    elif var == 'fold':                                   # folded paper: flat faces, light and dark, sharp creases
        n = int(k.clamp(round(w.length / 8.0) + 1, 3, 6))
        cuts = [(i / float(n)) for i in range(n + 1)]
        for i in range(n):
            a, b = cuts[i], cuts[i + 1]
            mid = (a + b) / 2.0
            peak = 1.0 + 0.12 * sin(g.ph - 0.9 * i)
            up = [w.pt(a, -0.15), w.pt(mid, -1.0 * peak), w.pt(b, -0.15)]
            dn = [w.pt(a, -0.15), w.pt(mid + 0.06, 1.0 * peak), w.pt(b, -0.15)]
            m = k.poly_mask(dn)
            g.piece(m, 1 + (i % 2), g.ramp(mid, 0.5))
            m = k.poly_mask(up)
            g.piece(m, 3 + (i % 2), g.ramp(mid, -0.5))
            tips.append(up[1])
        g.stem([(0.0, -0.15), (1.0, -0.15)], 0.7, 0.5, g.ramp(0.5, 0.0), shade=(1, 1, 0))
    else:                                                 # blade, slat: long pieces from an arm
        knots = k.BLADE if var == 'blade' else SLAT
        n = int(k.clamp(round(w.length / (6.0 if var == 'slat' else 4.6)) + sp.n, 3, 10))
        if sp.key == 'clockwork':                         # gears along a rod
            g.stem([(i / 6.0, 0.0) for i in range(7)], 1.2, 0.9, wood)
            for i in range(n):
                u = i / float(n - 1)
                x, y = w.pt(0.2 + 0.75 * u, 0.5 * (1 if i % 2 else -1))
                r = 2.2 + 1.4 * _hash(i, sp.wings)
                turn = g.ph * (1 if i % 2 else -1)
                for j in range(6):
                    a = turn + TAU * j / 6.0
                    g.seg((x, y), (x + (r + 1.3) * cos(a), y + (r + 1.3) * sin(a)), 0.8, 0.8, g.ramp(u, 0.0), shade=(3, 2, 1))
                g.ball(x, y, r, g.ramp(u, 0.5))
                g.ball(x, y, 0.9, (g.ramp(u, 0.0)[0],) * 5)
                tips.append((x, y))
        elif var == 'slat':                               # poles, a flag on each
            for i in range(n - 1, -1, -1):
                u = i / float(max(1, n - 1))
                q = 0.5 - 0.42 * u
                b, t = w.pt(0.0 + 0.3 * u, -0.2), w.rim(q)
                g.seg(b, t, 0.9, 0.7, wood, shade=(4, 3, 1))
                fl = [(b[0] + (t[0] - b[0]) * 0.45, b[1] + (t[1] - b[1]) * 0.45), t]
                dx, dy = w.rim(max(0.02, q - 0.12))
                wave = 1.2 * sin(g.ph - 0.8 * i)
                m = k.poly_mask([fl[0], fl[1], (dx + wave, dy + 1.0), ((fl[0][0] + dx) / 2.0, (fl[0][1] + dy) / 2.0 + 1.5 + wave)])
                idx = k.edge_shade(m, 3, 2, 1)
                g.piece(m, idx, g.ramp(0.8, 0.5))
                edge = m & ~k.nb(m, 0, 1)
                g.piece(edge, 3, ramp5(sp.glow), ring=False)
                tips.append(t)
        else:
            got = g.fan(n, g.linef(0.0, 0.55, -0.4), g.rimf(0.06, 0.62), knots,
                        lambda tt, ss, lit, hw: np.clip(np.where(lit, 3, 1) + (tt > 0.75) + ((np.abs(ss) < 0.2) & lit), 0, 4),
                        lambda i, u: g.ramp(0.2 + 0.8 * u, 0.5), hwk=0.7, sway=0.05, maxw=3.4)
            g.ball(*(w.pt(0.04, -0.2) + (2.2, ramp5(sp.glow))))
            tips = [t for b, t in got]
    g.motes(tips, 2)


# ------------------------------------------------------------------------------------------------ energy
def st_energy(g):
    sp, var = g.sp, g.sp.var
    fn = ENERGY.get(sp.key) or ENERGY.get(var)
    return fn(g)


def en_flame(g):
    """tongues of fire: hot at the root, they lick out to the edge and past it"""
    sp = g.sp
    g.stalk(1.4)
    w = g.w
    n = int(k.clamp(round(w.length / 4.4) + sp.n, 4, 11))
    g.piece(w.region(0.0, 0.9, -0.7, 0.6), 3, g.ramp(0.3, 0.0))
    got = g.fan(n, g.linef(0.0, 0.7, -0.2), g.rimf(0.05, 0.66), TONGUE, flame_shader,
                lambda i, u: g.pal2((0.6 * u, 0.2), (0.3 + 0.69 * u, 0.9)), hwk=0.95, sway=0.13, lag=1.7,
                reach=lambda i: 1.05 + 0.17 * sin(2 * g.ph + 1.7 * i + TAU * sp.jit), bend=1.6, maxw=4.6)
    g.motes([t for b, t in got], 3)


def en_cloud(g):
    """puffs along the spine, lit from above, they swell one after the other"""
    sp = g.sp
    w = g.w
    n = int(k.clamp(round(w.length / 4.2), 5, 13))
    pts = []
    for i in range(n):
        u = i / float(n - 1)
        for side in ((-0.45, 0.45) if w.half(u, 1) + w.half(u, -1) > 9 else (0.0,)):
            x, y = w.pt(0.04 + 0.92 * u, side)
            r = max(1.8, (w.half(u, -1) + w.half(u, 1)) * (0.36 if side else 0.55)) * (1.0 + 0.1 * sin(g.ph - 0.8 * i))
            pts.append((x, y, r, u, side))
    mask = np.zeros((S, S), bool)
    for x, y, r, u, side in pts:
        mask |= k.disc_mask(x, y, r)
    idx = np.full((S, S), 1, np.int32)
    for x, y, r, u, side in pts:                          # each puff is a ball of light
        sh = k.sphere_shade(x, y, r + 0.5)
        idx = np.where(k.disc_mask(x, y, r), np.maximum(idx, sh), idx)
    ss, tt = g.full.field()
    zi = np.clip(((ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + (tt >= 0.3)
    g.piece(mask, zi * 5 + np.clip(idx, 1, 4), sp.ZT)
    g.motes([(x, y) for x, y, r, u, side in pts], 2)


def en_bolt(g):
    """a dark arm, a bolt runs along it and forks"""
    sp = g.sp
    w = g.w
    g.stem([(i / 8.0, 0.25) for i in range(9)], max(1.4, w.half(0.3, 1) * 0.45), 0.9, g.ramp(0.4, 0.5))
    tips = []
    for b in range(2):
        pl = []
        n = 7
        for i in range(n + 1):
            u = i / float(n)
            jit = (_hash(i + 7 * b, sp.wings + g.f // 2) - 0.5) * 1.1 if 0 < i < n else 0.0
            pl.append((u if b == 0 else 0.25 + 0.5 * u, (-0.55 if b == 0 else 0.1 - 1.0 * u) + jit))
        m = w.line(pl, 0.9 if b == 0 else 0.7, 0.6)
        g.piece(m, 3 + (k.edge_shade(m, 1, 1, 0)), ramp5(sp.main), line=sp.A[1])
        tips.append(w.pt(*pl[-1]))
        for i in (2, 4):
            a = w.pt(*pl[i])
            g.seg(a, (a[0] + 2.5 * (_hash(i, g.f // 2) - 0.5) * 2, a[1] - 3.0), 0.6, 0.4, ramp5(sp.main), shade=(4, 4, 3))
    g.c.haze(k.disc_mask(*(w.pt(0.05, 0.3) + (4.0,))), sp.A[1])
    for i, (x, y) in enumerate(tips):
        g.c.spark(x, y, sp.glow, 1 + (g.f + i) % 2)


def en_water(g):
    """water: a body of curled lobes, foam on the upper edge, drops fly off"""
    sp = g.sp
    g.stalk(1.3)
    w = g.w
    n = int(k.clamp(round(w.length / 6.0) + sp.n, 3, 8))
    ss, tt = g.zonefill(shade=lambda ss, tt: 2 + (tt < -0.3).astype(np.int8) - (tt > 0.45).astype(np.int8) + (np.abs(((ss * n + tt * 0.6) % 1.0) - 0.5) < 0.1).astype(np.int8) * -1)
    tips = []
    foam = ramp5(sp.glow) if lum(sp.glow) > 150 else g.ramp(0.9, -0.5)
    for i in range(n):
        u = (i + 0.5) / n
        x, y = w.pt(u, -0.75 + 0.1 * sin(g.ph - i))
        r = k.clamp(w.half(u, -1) * 0.5, 1.5, 3.4) * (1.0 + 0.12 * sin(g.ph - 0.9 * i))
        if sp.key != 'ink_splash' and sp.key != 'solar_flare':
            g.ball(x, y, r, foam, line=foam[1])
        tx, ty = w.rim(0.08 + 0.5 * u)
        q = (g.f / float(k.FRAMES) + _hash(i, sp.wings)) % 1.0
        g.ball(tx + (tx - x) * 0.25 * q, ty + 1 + 5 * q, 1.4 - 0.5 * q, g.ramp(u, 0.5))
        tips.append((tx, ty))
    g.motes(tips, 2)


def en_arcs(g):
    """loops of fire that leave the body and come back"""
    sp = g.sp
    w = g.w
    n = max(3, min(6, 4 + sp.n))
    tips = []
    for i in range(n):
        u = i / float(n - 1)
        t1 = 1.0 - 2.0 * u
        swell = 1.0 + 0.1 * sin(g.ph - 1.1 * i)
        pl = [(j / 8.0, t1 * sin(math.pi * (j / 8.0) ** 0.8) * swell) for j in range(9)]
        g.stem(pl, 1.7, 0.9, g.pal2((0.5, t1), (0.5, t1))[:5], shade=(4, 3, 2))
        tips.append(w.pt(0.6, t1 * swell))
    g.ball(*(w.pt(0.04, 0.0) + (2.6, g.ramp(0.1, 0.0))))
    g.motes(tips, 3)


def en_ray(g):
    """rays that burst from one point: the root, or the head of a stalk"""
    sp = g.sp
    s0 = g.stalk(1.2)
    w = g.w
    burst = sp.key in ('firework_burst',)
    wide = (w.half(0.6, -1) + w.half(0.6, 1))
    n = int(k.clamp(round(wide / 2.6) + sp.n, 4, 12))
    c = w.pt(0.5, 0.0) if burst else w.pt(0.02, 0.0)
    tips = []
    for i in range(n):
        u = i / float(n - 1)
        if burst:
            a = TAU * i / n + 0.1 * sin(g.ph)
            r = max(w.length * 0.5, wide * 0.5) * (0.75 + 0.25 * sin(g.ph - 1.3 * i) ** 2)
            t = (c[0] + r * cos(a), c[1] + r * sin(a))
        else:
            t = w.rim(0.1 + 0.8 * u)
            r = 0.86 + 0.14 * sin(g.ph - 1.1 * i + TAU * sp.jit)
            t = (c[0] + (t[0] - c[0]) * r, c[1] + (t[1] - c[1]) * r)
        m, tt, ss, lit = k.leaf(c, t, 1.5 if sp.key == 'gale_streak' else 2.1, RAY)
        idx = np.where(np.abs(ss) < 0.45, 4, 3) - (tt > 0.7)
        g.c.piece(m, np.where(tt > 0.6, idx + 5, idx).astype(np.int8), g.pal2((0.4, 1 - 2 * u), (0.95, 1 - 2 * u)))
        tips.append(t)
        if burst:
            g.c.spark(t[0], t[1], sp.glow, 1 + (i + g.f // 2) % 2)
    g.ball(c[0], c[1], 2.0 if not burst else 2.6, ramp5(sp.glow))
    g.motes(tips, 2)


def en_disc(g):
    """a bar of feathers of light with a disc on it (the sun disc)"""
    sp = g.sp
    w = g.w
    n = int(k.clamp(round(w.length / 3.6), 5, 14))
    got = g.fan(n, g.linef(0.05, 0.95, -0.9), g.linef(0.08, 1.0, 1.0), SLAT, flat_shader(2, 0.7, mid=4),
                lambda i, u: g.pal2((u, -0.5), (u, 0.9)), hwk=0.5, maxw=2.2, sway=0.02,
                reach=lambda i: 0.9 + 0.1 * sin(g.ph - 0.6 * i))
    g.stem([(i / 6.0, -0.85) for i in range(7)], 1.4, 1.0, sp.A, shade=(4, 3, 1))
    x, y = w.pt(0.06, -0.3)
    g.ball(x, y, 2.6 + 0.3 * sin(g.ph), ramp5(sp.glow))
    g.motes([t for b, t in got], 2)


def en_veil(g):
    """an arm of light, bands hang from it and sway"""
    sp = g.sp
    w = g.w
    n = int(k.clamp(round(w.length / 5.0) + sp.n, 4, 10))
    got = g.fan(n, g.linef(0.08, 0.96, -0.7), g.linef(0.02, 0.9, 1.0), RIBBON, flat_shader(3, 0.55),
                lambda i, u: g.pal2((u, 0.2), (u, 0.9)), hwk=0.5, maxw=2.3, sway=0.12, lag=0.9,
                reach=lambda i: 0.9 + 0.12 * sin(g.ph - 0.9 * i))
    g.stem([(i / 8.0, -0.75) for i in range(9)], 1.6, 0.9, g.ramp(0.5, -0.5), shade=(4, 3, 2))
    for i, (b, t) in enumerate(got):
        if i % 2 == 0:
            q = (g.f / float(k.FRAMES) + i * 0.17) % 1.0
            g.c.spark(b[0] + (t[0] - b[0]) * q, b[1] + (t[1] - b[1]) * q - 5, sp.glow, 0 if q > 0.5 else 1)
    g.motes([b for b, t in got], 2)


def en_jelly(g):
    """a bell on a stalk, tentacles under it"""
    sp = g.sp
    s0 = g.stalk(1.3)
    w = g.w
    x, y, r = w.mid()
    r = max(r * 0.9, 4.5) * (1.0 + 0.08 * sin(g.ph))
    tips = []
    for i in range(5):
        bx = x - r * 0.7 + r * 1.4 * i / 4.0
        px, py = bx, y + 1
        for j in range(3):
            nx_, ny_ = bx + 1.3 * sin(g.ph - 0.9 * j - i), py + (r * 0.5 + 1.5)
            g.seg((px, py), (nx_, ny_), 0.8, 0.5, g.ramp(0.8, 0.9), shade=(4, 3, 2))
            px, py = nx_, ny_
        tips.append((px, py))
    bell = k.disc_mask(x, y, r) & (k.PY < y + r * 0.35)
    g.piece(bell, np.clip(k.sphere_shade(x, y, r + 0.5), 1, 4), g.ramp(0.7, -0.5))
    g.c.spark(x - r * 0.3, y - r * 0.4, sp.glow, 1)
    g.motes(tips, 2)


def en_funnel(g):
    """a tornado: a cone that widens from the root to a dark mouth, bands of cloud turn round it, dust flies"""
    sp = g.sp
    w = g.w
    ss, tt = w.field()
    mask = w.body()
    turn = g.f / float(k.FRAMES)
    band = ((ss * 5.5 - tt * 0.45 - turn) % 1.0)
    sh = np.where(band < 0.4, 4, np.where(band < 0.55, 2, 1)) + (tt < -0.35).astype(np.int8) - (tt > 0.45).astype(np.int8)
    zi = np.clip(((ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + (tt >= 0.2)
    idx = zi * 5 + np.clip(sh, 0, 4)
    mouth = (ss > 0.86) & (np.abs(tt) < 0.72)
    idx = np.where(mouth, zi * 5 + 0, idx)
    g.piece(mask, idx, sp.ZT)
    for i in range(4):                                    # dust that is thrown out
        q = (turn + i / 4.0) % 1.0
        x, y = w.pt(0.3 + 0.6 * _hash(i, sp.wings), (1.15 + 0.6 * q) * (1 if i % 2 else -1))
        g.c.spark(x, y, sp.glow, 1 if q < 0.5 else 0)
    x, y = w.pt(0.95, 0.0)
    g.c.haze(k.disc_mask(x, y, 3.5) & ~mask, g.ramp(0.9, 0.0)[1])


def en_whirl(g):
    """a whirlpool: a disc of water on a stalk, a spiral of foam that turns"""
    sp = g.sp
    s0 = g.stalk(1.6)
    w = g.w
    x, y, r = w.mid()
    r = max(r, w.length * 0.46, 5.5)
    mask = w.body() | k.disc_mask(x, y, r * 0.8)
    dx, dy = k.PX - x, k.PY - y
    rr = np.sqrt(dx * dx + dy * dy) / r
    th = np.arctan2(dy, dx)
    turn = TAU * g.f / float(k.FRAMES)
    arm = ((th * g.sgn + rr * 7.5 - turn) / TAU * 2.0) % 1.0
    sh = np.where(arm < 0.3, 4, np.where(arm < 0.5, 3, np.where(rr > 0.8, 1, 2)))
    sh = np.where(rr < 0.16, 0, sh)
    g.piece(mask, sh, g.ramp(0.7, 0.0))
    for i in range(3):
        a = turn + TAU * i / 3.0
        g.c.spark(x + (r + 1.5) * cos(a), y + (r + 1.5) * sin(a), sp.glow, 1 if i == 0 else 0)


def en_smoke(g):
    """dark smoke: thick wisps that curl from the root, a haze round them, pieces that drift off"""
    sp = g.sp
    w = g.w
    body = np.zeros((S, S), bool)
    n = max(4, min(6, 5 + sp.n))
    turn = g.f / float(k.FRAMES)
    for i in range(n):
        u = i / float(n - 1)
        t1 = -0.9 + 1.8 * u
        pl = [(j / 8.0, t1 * (j / 8.0) ** 0.7 + 0.28 * sin(g.ph - 1.2 * i + 5.0 * j / 8.0)) for j in range(9)]
        m = w.line(pl, 2.6, 1.0, knob1=1.8 + 0.5 * sin(g.ph - i))
        body |= m
    ss, tt = g.full.field()
    zi = np.clip(((ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + (tt >= 0)
    curl = ((ss * 4.0 + tt * 0.8 - turn) % 1.0) < 0.35
    g.c.haze(k.dilate4(k.dilate4(body)) & ~body, g.ramp(0.5, 0.0)[1])
    g.piece(body, zi * 5 + 1 + curl + (tt < -0.5), sp.ZT)
    for i in range(3):
        q = (turn + i / 3.0) % 1.0
        x, y = w.pt(0.75 + 0.3 * q, -1.0 + 0.8 * i - 0.4 * q)
        g.c.haze(k.disc_mask(x, y - 4 * q, 2.6 * (1.0 - 0.6 * q)), g.ramp(0.9, 0.0)[2])


def en_rain(g):
    """a rain cloud arm: strands of rain hang from it, bright drops run down them, rings where they land"""
    sp = g.sp
    w = g.w
    n = int(k.clamp(round(w.length / 3.0) + sp.n, 6, 16))
    turn = g.f / float(k.FRAMES)
    tips = []
    for i in range(n):
        u = i / float(n - 1)
        b = w.pt(0.05 + 0.93 * u, -0.6)
        t = w.pt(0.03 + 0.9 * u, 1.0)
        g.seg(b, t, 0.75, 0.5, g.ramp(u, 0.5), shade=(3, 2, 2))
        q = (turn * 2.0 + _hash(i, sp.wings)) % 1.0
        g.c.spark(b[0] + (t[0] - b[0]) * q, b[1] + (t[1] - b[1]) * q, sp.glow, 0)
        tips.append(t)
    g.stem([(i / 8.0, -0.7) for i in range(9)], 2.0, 1.2, g.ramp(0.4, -0.5), shade=(4, 3, 2))
    x, y = w.pt(0.45, 1.0)
    q = turn
    ring = k.disc_mask(x, y + 7, 1.5 + 3.5 * q) & ~k.disc_mask(x, y + 7, 0.6 + 3.5 * q)
    ring &= (k.PY > y + 5.5)
    g.c.haze(ring, sp.glow)


def en_nebula(g):
    """a cloud of two colours with a field of stars"""
    sp = g.sp
    w = g.w
    ss, tt = w.field()
    mask = w.body()
    n = 5
    for i in range(n):                                    # a knobbly edge
        x, y = w.rim(0.1 + 0.8 * i / float(n - 1))
        mask |= k.disc_mask(x, y, 2.4 + 0.5 * sin(g.ph - i))
    drift = 0.15 * sin(g.ph)
    lobes = np.sin(ss * 9.0 + drift) + np.sin(tt * 3.0 + ss * 4.0 - drift)
    zi = np.clip(((ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + (tt >= 0)
    idx = zi * 5 + np.clip(2 + (lobes > 0.6).astype(np.int8) - (lobes < -0.7).astype(np.int8) + (tt < -0.5), 0, 4)
    idx = np.where((lobes > 1.2), 35 + 3, idx)
    g.piece(mask, idx, sp.ZT)
    turn = g.f / float(k.FRAMES)
    for j in range(7):
        x, y = w.pt(0.1 + 0.85 * _hash(j, sp.wings), -0.7 + 1.4 * _hash(j, 77))
        gl = cos(TAU * (turn + _hash(j, 5)))
        if gl > -0.2:
            g.c.spark(x, y, (255, 255, 255) if j % 2 else sp.glow, 1 if gl > 0.7 else 0)


ENERGY = {'flame': en_flame, 'cloud': en_cloud, 'bolt': en_bolt, 'water': en_water, 'ray': en_ray, 'veil': en_veil,
          'funnel': en_funnel, 'whirl': en_whirl, 'smoke': en_smoke, 'rain': en_rain, 'nebula': en_nebula,
          'jellyfish': en_jelly, 'solar_flare': en_arcs, 'sun_disc': en_disc}


# ------------------------------------------------------------------------------------------------ orbit
def st_orbit(g):
    sp = g.sp
    stem = g.ramp(0.15, 0.0)
    if sp.var == 'firefly':                               # stalks that end in lights; the lights breathe
        w = g.w
        n = max(8, min(14, int(w.length / 3.0) + sp.n))
        for i in range(n):                                # a swarm: lights in two loose rows along the wing
            u = i / float(n - 1)
            x, y = w.pt(0.08 + 0.88 * u, (-0.55 if i % 2 else 0.55) + 0.35 * (_hash(i, sp.wings) - 0.5))
            x += 0.9 * sin(g.ph - 0.9 * i)
            y += 0.9 * cos(g.ph - 0.9 * i)
            if i % 3 == 0:
                g.seg(w.pt(max(0.0, u - 0.25), 0.0), (x, y), 0.6, 0.5, stem)
            gl = 0.5 + 0.5 * sin(g.ph - 1.4 * i)
            g.ball(x, y, 1.9 + 0.5 * gl, g.ramp(0.1 + 0.8 * u, 0.0))
            if gl > 0.75:
                g.c.spark(x, y, sp.glow, 1)
        return
    s0 = g.stalk(1.5, stem)                               # a disc of signs that turns on a stalk
    w = g.w
    x, y, r = w.mid()
    r = max(r, w.length * 0.45, 6.0)
    turn = g.ph * 0.5
    mask = k.disc_mask(x, y, r)
    dx, dy = k.PX - x, k.PY - y
    rr = np.sqrt(dx * dx + dy * dy) / r
    idx = np.where(rr > 0.8, 3, 2) + (dy < -r * 0.3)
    for j in range(6):
        a = turn + TAU * j / 6.0
        mask &= ~k.disc_mask(x + r * 0.52 * cos(a), y + r * 0.52 * sin(a), r * 0.17)
    mask &= ~k.disc_mask(x, y, r * 0.16)
    g.piece(mask, idx, g.ramp(0.8, 0.0))
    for j in range(3):
        a = -turn + TAU * j / 3.0
        g.c.spark(x + (r + 2) * cos(a), y + (r + 2) * sin(a), sp.glow, 1)


STYLES = {'feather': st_feather, 'bat': st_bat, 'insect': st_insect, 'crystal': st_crystal, 'leaf': st_leaf, 'bone': st_bone,
          'fan': st_fan, 'energy': st_energy, 'orbit': st_orbit}


# O714. The layout of a pair, the same for every row (the layout of the painted rows, O620, for the code rows):
#   south, north   ONE wing is drawn, the left one, with its root on the anchor column; the right wing is its mirror
#                  picture about that column (Canvas.mirror_in). The wing is the longer of the two measured wings of
#                  the view (a right wing is mirrored first). Before O714 each of the two measured wings was drawn
#                  as measured, so a pair had a long wing and a short one and its box, not its meeting point, stood on
#                  the anchor column: mirror partner share 0.56 (median), mass 2.5 px right of the column facing south.
#   east, west     the same wing seen from the side (O714c, the kit's SIDE_* numbers): the near wing at k.SIDE_NEAR of
#                  its size, rooted on the shoulder blade (k.SIDE_ROOT) and swept back at one of k.SIDE_AIMS degrees
#                  (side_geo fits the turn), the far wing k.SIDE_FAR, a step darker, up and back (k.SIDE_FARS) and
#                  steeper until k.SIDE_FAR_FREE of it shows; nothing in front of the back line; west is
#                  the east frame mirrored about the anchor column, so it trails right. O714 had both wings on the
#                  torso column at 70% and 55%, as steep as 58 degrees: a narrow clump over the shoulder. Before O714 east was the
#                  south picture and west the north picture with x and y changed over: a transposed picture trails
#                  left in both, and the second wing hung under the body (46% of the pixels under the torso row).
JOIN = (k.ANCHOR[0], st.MEET[1])        # the point where the wings meet, over the anchor
SIDE_LAG = 0.5                          # the far wing follows the near one (radians of the beat)
X_INDEX = tuple([0] + [2 + 4 * i for i in range(st.STATIONS)] + [4 * st.STATIONS + 2])      # the x of root, stations, tip


def mirror_strip(v):
    """the strip of the mirror picture: x changes sign"""
    out = list(v)
    for i in X_INDEX:
        out[i] = -out[i]
    return out


def model_strip(sp, d):
    """the one wing of a face-on view as a left wing with its root on the column x = 0: the longer of the measured
    left wing and the measured right wing mirrored (the left one when they are as long)"""
    l, r = sp.strips[d]
    cands = []
    if l is not None:
        cands.append((st.Strip(l, -1, (0.0, 0.0)).length, 1, list(l)))
    if r is not None:
        cands.append((st.Strip(r, 1, (0.0, 0.0)).length, 0, mirror_strip(r)))
    v = max(cands, key=lambda c: (round(c[0], 1), c[1]))[2]
    root = v[0]
    for i in X_INDEX:
        v[i] -= root
    return v


def side_strip(v, rise):
    """a left wing turned about its root so that the line to its tip rises `rise` degrees over the horizontal
    (the numbers become floats; the widths do not turn)"""
    out = [float(x) for x in v]
    rx, ry = out[0], out[1]
    cx, cy = out[-2] - rx, out[-1] - ry
    if math.hypot(cx, cy) >= 4.0:
        turn = math.atan2(-math.sin(math.radians(rise)), -math.cos(math.radians(rise))) - math.atan2(cy, cx)
        c, s = math.cos(turn), math.sin(turn)
        pts = [(0, 1)] + [(2 + 4 * i, 3 + 4 * i) for i in range(st.STATIONS)] + [(len(v) - 2, len(v) - 1)]
        for xi, yi in pts:
            x, y = out[xi] - rx, out[yi] - ry
            out[xi], out[yi] = rx + x * c - y * s, ry + x * s + y * c
    return out


def _draw_wing(sc, canvas, sp, v, origin, scale, lag=0.0, amp=None):
    """one left wing (strip numbers v, root at `origin` plus the root's own numbers) into a canvas with its style;
    amp: the beat (the row's own when None)"""
    sgn = -1
    amp = sp.amp if amp is None else amp

    def bend(u):
        return -sgn * amp * (0.25 + 0.75 * u) * sin(sc.ph - 1.0 * u - lag)
    w = st.Strip(v, sgn, origin, scale, bend, 1.0 + 0.015 * sin(sc.ph + 1.0))
    rest = st.Strip(v, sgn, origin, scale)
    mould = MOULD_ENV or sp.mould
    layer = Clip(sp.outline) if mould != 'free' else canvas
    g = G(layer, w, rest, sp, sc, sgn)
    STYLES[sp.family](g)
    g.glint()
    if layer is not canvas:
        _mould(layer, canvas, w, sp, mould == 'fill')


def fam_strip(sc, sp):
    """one face-on frame of a row: the left wing and its mirror picture; south behind the body, north in front of it"""
    d = sc.d
    sc.back, sc.front = Clip(sp.outline), Clip(sp.outline)
    canvas = sc.front if d == 'north' else sc.back
    origin, scale = placed(sp, d)
    _draw_wing(sc, canvas, sp, model_strip(sp, d), (origin[0] + 0.5, origin[1]), scale)
    canvas.mirror_in()
    if d == 'north':                                      # from behind, the knot that ties the pair is in sight
        x, y = origin
        m = k.disc_mask(x + 0.5, y + 0.5, 1.9) & INNER
        canvas.piece(m, k.sphere_shade(x + 0.5, y + 0.5, 2.4).astype(np.int8), sp.A)


def _side_fit(v, at, scale, amp):
    """(origin, scale) that puts the root of the side wing v on `at`, shrunk until the wing stays inside ROOM through the beat"""
    room = st.ROOM
    for _ in range(12):
        origin = (at[0] - v[0] * scale, at[1] - v[1] * scale)
        boxes = [st.Strip(v, -1, origin, scale, (lambda u, a=a: a * (0.25 + 0.75 * u)) if a else None).box()
                 for a in ((-amp, 0.0, amp) if amp else (0.0,))]
        if (min(b[0] for b in boxes) >= room[0] + 2 and min(b[1] for b in boxes) >= room[1] + 2
                and max(b[2] for b in boxes) <= room[2] - 2 and max(b[3] for b in boxes) <= room[3] - 2):
            break
        scale *= 0.96
    return origin, scale


SIDE_AMP = 0.16             # radians: the most a side wing beats, so every frame keeps the band of k.SIDE_ANGLE


def side_amp(sp):
    return min(sp.amp, SIDE_AMP)


def _side_draw(sc, sp, rise, spread, parts=('far', 'near'), back=0, lag=SIDE_LAG):
    """the side wings of one east frame at a turn: {part: Clip canvas}, the far one already darker"""
    v = model_strip(sp, 'south')
    scale = placed(sp, 'south')[1]
    out = {}
    for part in parts:
        c = Clip(sp.outline)
        if part == 'far':
            more, at = k.SIDE_FARS[spread]
            w = side_strip(v, rise + more)
            at = (k.SIDE_ROOT[0] - back + at[0] + 0.5, k.SIDE_ROOT[1] + at[1])
            origin, s = _side_fit(w, at, scale * k.SIDE_FAR, side_amp(sp))
            _draw_wing(sc, c, sp, w, origin, s, lag, side_amp(sp))
            k.side_clip(c)
            k.side_far_shade(c)
        else:
            w = side_strip(v, rise)
            origin, s = _side_fit(w, (k.SIDE_ROOT[0] - back + 0.5, k.SIDE_ROOT[1]), scale * k.SIDE_NEAR, side_amp(sp))
            _draw_wing(sc, c, sp, w, origin, s, 0.0, side_amp(sp))
            k.side_clip(c)
        out[part] = c
    return out


_SIDE = {}


def side_geo(sp):
    """(rise, spread, back) of a row: the turn of the strip, the far wing's place and the step back (k.side_fit)"""
    if sp.key not in _SIDE:
        def draw(f, rise, spread, parts, back):
            return _side_draw(k.Scene(sp.outline, 'east', f, PIVOT), sp, rise, spread, parts, back)
        reach = {f: k.face_reach(k.merge(*render_frame(sp, 'south', f))[..., 3] == 255, JOIN) for f in k.SIDE_PROBE}
        _SIDE[sp.key] = k.side_fit(draw, reach)
    return _SIDE[sp.key]


def fam_side(sc, sp, geo=None):
    """one east frame of a row (west is it mirrored): the far wing, a step darker, then the near wing over it, both
    rooted on the shoulder blade and swept back, behind the body (O714c)"""
    rise, spread, back = side_geo(sp) if geo is None else geo
    got = _side_draw(sc, sp, rise, spread, back=back)
    sc.side = (got['near'].op.copy(), got['far'].op.copy())
    sc.back, sc.front = got['far'], Clip(sp.outline)
    k.side_put(sc.back, got['near'])


def fam_side_o714(sc, sp):
    """the side view of O714, kept for the test that shows it refused: both wings on the torso column, 70% and 55% of
    the size, as steep as 58 degrees"""
    sc.back, sc.front = Clip(sp.outline), Clip(sp.outline)
    canvas = sc.back
    v = model_strip(sp, 'south')
    scale = placed(sp, 'south')[1]
    rise = 58
    far = side_strip(v, rise + 14)
    origin, s = _side_fit(far, (JOIN[0] + 2.5, JOIN[1] - 3), scale * 0.55, sp.amp)
    _draw_wing(sc, canvas, sp, far, origin, s, SIDE_LAG)
    k.side_far_shade(canvas)
    farm = canvas.op.copy()
    nc = Clip(sp.outline)
    near = side_strip(v, rise)
    origin, s = _side_fit(near, (JOIN[0] + 0.5, JOIN[1]), scale * 0.7, sp.amp)
    _draw_wing(sc, nc, sp, near, origin, s)
    k.side_put(canvas, nc)
    sc.side = (nc.op.copy(), farm)


def _grow(mask, n):
    for _ in range(n):
        mask = k.dilate4(mask)
    return mask


def _mould(layer, canvas, w, sp, fill):
    """hold one wing to the measured outline of the old wing: what a style draws outside the strip is cut away
    and, with `fill`, what it leaves open inside is closed in the dark shade of the zone; then the wing goes on
    the frame's layer"""
    body = w.body() & INNER
    layer.op &= _grow(body, 1)
    if fill:
        under = body & ~layer.op
        if under.any():
            ss, tt = w.field()
            zi = np.clip(((ss + NOISE) * 3).astype(np.int32), 0, 2) * 2 + ((tt + 2 * NOISE) >= 0)
            layer.rgb[under] = np.asarray(sp.ZT, np.uint8)[(zi * 5 + 1)[under]]
            layer.op |= under
    op = layer.op
    edge = op & ~(k.nb(op, 1, 0) & k.nb(op, -1, 0) & k.nb(op, 0, 1) & k.nb(op, 0, -1))
    layer.rgb[edge] = sp.outline
    canvas.rgb[op] = layer.rgb[op]
    canvas.op |= op
    near = _grow(body, 3)
    canvas.sparks.extend(layer.sparks)
    canvas.hazes.extend((m & near, c) for m, c in layer.hazes)


MOULD_ENV = os.environ.get('CHAOS_WINGS_MOULD', '')      # a trial switch for `score`: free, clip or fill for every row
MOULDS = ('free', 'clip', 'fill')


FAMILIES = {name: (fam_strip, PIVOT) for name in STYLES}


# ------------------------------------------------------------------------------------------------ sheets (O594)
# Ten rows are painted with PixelLab (gen_pixellab_wings.py). Their sheets are picture data and live outside the
# repository: `<wings id>.png` in a private folder, 16 columns x 4 rows of 96 px (south, north, east, west), cleaned. With
# `--src DIR` (or CHAOS_WINGS_SRC) a row of drawn_wings/pixellab_rows.csv is taken from that folder; without it
# every row is drawn by code. A sheet that is not the one of the table (sha256) is refused.
SHEET_CSV = os.path.join(HERE, 'drawn_wings', 'pixellab_rows.csv')
SHEET_SUMS = os.path.join(HERE, 'drawn_wings', 'pixellab_rows.sums')
SRC_DIR = os.environ.get('CHAOS_WINGS_SRC', '')
SRC_CHECK = True
SHEET_VIEWS = ('south', 'north', 'east', 'west')         # the rows of a sheet, top to bottom
_SHEETS = {}
_SHEET_ROWS = {}


def sheet_rows(path=None):
    """{wings id: row} of pixellab_rows.csv"""
    path = path or SHEET_CSV
    if path not in _SHEET_ROWS:
        with open(path, newline='', encoding='utf-8') as f:
            _SHEET_ROWS[path] = {int(row['wings']): row for row in csv.DictReader(f)}
    return _SHEET_ROWS[path]


def use_src(path, check=True):
    """name the sheets folder ('' for none); check=False takes a sheet whatever its sha256 (the cleaning step)"""
    global SRC_DIR, SRC_CHECK
    SRC_DIR, SRC_CHECK = path or '', check
    _SHEETS.clear()
    _FACE.clear()


def sheet_faces(sp):
    """{view: [16 RGBA]} (south, north, east, west) of a row that comes from a sheet, or None: no folder named, or
    the row is drawn by code"""
    if not SRC_DIR:
        return None
    row = sheet_rows().get(sp.wings)
    if row is None:
        return None
    if sp.wings not in _SHEETS:
        import hashlib
        from PIL import Image
        path = os.path.join(SRC_DIR, '%d.png' % sp.wings)
        if not os.path.isfile(path):
            raise SystemExit('%s: no sheet for row %d (%s); leave --src out to draw it by code' % (path, sp.wings, sp.key))
        with open(path, 'rb') as f:
            data = f.read()
        if SRC_CHECK and hashlib.sha256(data).hexdigest() != row['sha256']:
            raise SystemExit('%s: not the sheet of drawn_wings/pixellab_rows.csv (sha256)' % path)
        sheet = np.asarray(Image.open(path).convert('RGBA'))
        if sheet.shape != (len(SHEET_VIEWS) * S, k.FRAMES * S, 4):
            raise SystemExit('%s: a sheet is %d x %d' % (path, k.FRAMES * S, len(SHEET_VIEWS) * S))
        _SHEETS[sp.wings] = {v: [np.ascontiguousarray(sheet[r * S:(r + 1) * S, f * S:(f + 1) * S]) for f in range(k.FRAMES)]
                             for r, v in enumerate(SHEET_VIEWS)}
    return _SHEETS[sp.wings]


_FACE = {}


def _view(sp, d, f):
    """(back, front) of a frame the family draws itself, north, south or east; one row is kept, so west (east mirrored)
    costs nothing more"""
    if _FACE.get('key') != sp.key:
        _FACE.clear()
        _FACE['key'] = sp.key
    if (d, f) not in _FACE:
        fn, pivot = FAMILIES[sp.family]
        sc = k.Scene(sp.outline, d, f, pivot)
        (fam_side if d == 'east' else fn)(sc, sp)
        _FACE[(d, f)] = sc.result()
        if d == 'east':
            _FACE[('side', f)] = sc.side
    return _FACE[(d, f)]


def side_masks(sp, f):
    """(near, far) masks of the east frame f of a row drawn by code"""
    _view(sp, 'east', f)
    return _FACE[('side', f)]


def render_frame(sp, d, f):
    """(back, front) of one frame. North and south are drawn face on, the left wing and its mirror picture; east is the
    side view, west is east mirrored about the anchor column (O714, the layout above `JOIN`)."""
    faces = sheet_faces(sp)
    if faces is not None:                                 # a painted row (O594, own side views O620): north in front of the body, the rest behind
        img, none = faces[d][f], np.zeros((S, S, 4), np.uint8)
        return (none, img) if d == 'north' else (img, none)
    if d == 'west':
        back, front = _view(sp, 'east', f)
        return k.mirrored(back), k.mirrored(front)
    return _view(sp, d, f)


def render(sp, dirs=k.DIRS, frames=None):
    frames = range(k.FRAMES) if frames is None else frames
    return {d: [render_frame(sp, d, f) for f in frames] for d in dirs}


# ------------------------------------------------------------------------------------------------ frames of a row
TILES = S // 32
PATTERN_Y = 2               # y0: the whole wing (old clients), y1: the part in front of the body (base patch 0203)
FRAME_MS = 83               # 16 frames in 1.33 s, the speed of the previews
SUMS = os.path.join(HERE, 'drawn_wings', 'designs.sums')
ANCHORS = os.path.normpath(os.path.join(HERE, '..', '..', 'overlay', 'modules', 'client_chaos_wingfit', 'wing_anchors.lua'))


def whole(back, front):
    """pattern y0: the back layer with the opaque pixels of the front on it (a client without base patch 0203 draws
    only this one; the glow of the front stays out, the patched client draws it once, with y1)"""
    out = back.copy()
    solid = front[..., 3] == 255
    out[solid] = front[solid]
    return out


def patterns(sp):
    """{(y, direction index, frame): RGBA 96 x 96} of a row, directions in the dat order (north, east, south, west)"""
    out = {}
    for x, d in enumerate(k.DIRS):
        for f in range(k.FRAMES):
            back, front = render_frame(sp, d, f)
            out[(0, x, f)] = whole(back, front)
            out[(1, x, f)] = front
    return out


def digest(pats):
    import hashlib
    h = hashlib.sha256()
    for key in sorted(pats):
        h.update(bytes(key))
        h.update(np.ascontiguousarray(pats[key]).tobytes())
    return h.hexdigest()


def _digest_row(sp):
    return sp.wings, digest(patterns(sp))


def all_digests(specs=None, jobs=None):
    """{wings id: sha256 of its 128 pictures}; the rows are drawn in parallel"""
    import multiprocessing
    specs = load() if specs is None else specs
    jobs = jobs or min(4, os.cpu_count() or 1)
    if jobs <= 1 or len(specs) < 4:
        return dict(_digest_row(sp) for sp in specs)
    with multiprocessing.Pool(jobs) as pool:
        return dict(pool.map(_digest_row, specs, chunksize=4))


def sums_text(sums):
    return ''.join('%d %s\n' % (w, sums[w]) for w in sorted(sums))


def read_sums(path=SUMS):
    out = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            w, h = line.split()
            out[int(w)] = h
    return out


def problems(specs=None):
    """the rules of the table that need no drawing"""
    specs = load() if specs is None else specs
    bad = []
    seen, keys, looks = set(), set(), set()
    for sp in specs:
        if sp.wings in seen or sp.key in keys or sp.look in looks:
            bad.append('%s: wings id, key or look twice' % sp.key)
        seen.add(sp.wings)
        keys.add(sp.key)
        looks.add(sp.look)
        if not -2 <= sp.n <= 2:
            bad.append('%s: size or n out of range' % sp.key)
    recipe = {}
    for sp in specs:
        key = (sp.family, sp.var, sp.main, sp.accent, sp.glow, sp.spark, sp.n, str(sp.strips), tuple(sp.zones))
        if key in recipe:
            bad.append('%s and %s: the same recipe' % (recipe[key], sp.key))
        recipe[key] = sp.key
    return bad


# ------------------------------------------------------------------------------------------------ the engine's anchor
def anchor_rel():
    """the wings' own anchor, sprite px at 1x from the creature's place (the top left of its tile), displacement 0:
    the point of the 96 x 96 picture that goes on the body's torso (base patch 0204)"""
    return (k.ANCHOR[0] - (S - 32), k.ANCHOR[1] - (S - 32))


NEW_LOOKS = os.path.join(HERE, 'drawn_wings', 'new_looks.csv')


def new_looks(path=NEW_LOOKS):
    """the looks of the six wings of O581 phase 2 (gen_drawn_wings_new.py, pair 78): drawn the same way, anchored the same way"""
    if not os.path.isfile(path):
        return []
    with open(path, newline='', encoding='utf-8') as f:
        return [int(r['look']) for r in csv.DictReader(f)]


def anchors_text(specs=None):
    specs = load() if specs is None else specs
    ax, ay = anchor_rel()
    lines = ['-- Generated by client/tools/sprites/gen_drawn_wings.py table from drawn_wings/designs.csv and new_looks.csv. Do not edit.',
             '-- Code-drawn wings (O583, O581 phase 2): the point of every drawn wings look that sits on the body torso, sprite px at 1x',
             "-- from the creature's place, the same for the four directions (base patch 0204 measures the body and puts",
             '-- this point on its torso). bodies: a look whose measured torso is wrong gets a row',
             '-- {look, direction 0-3, x, y} here, by hand, in gen_drawn_wings_families.py BODY_OVERRIDES.',
             'ChaosWingAnchors = {',
             '  anchor = {%d, %d},' % (ax, ay),
             '  wings = {']
    looks = sorted([sp.look for sp in specs] + new_looks())
    for i in range(0, len(looks), 16):
        lines.append('    ' + ','.join(str(v) for v in looks[i:i + 16]) + ',')
    lines += ['  },', '  bodies = {']
    for row in BODY_OVERRIDES:
        lines.append('    {%d,%d,%d,%d},' % row)
    lines += ['  },', '}', 'return ChaosWingAnchors', '']
    return '\n'.join(lines)


BODY_OVERRIDES = ()         # (look, direction, x, y): the short list of bodies the rule gets wrong; none so far

# the rule of base patch 0204 (chaoswinganchor.h), the same as gen_wing_centres.torso_x plus a y: kept in integers so
# the C++ and this twin agree on every mask
TORSO_ALPHA = 64
TORSO_OPEN = 2
TORSO_LO_PCT, TORSO_HI_PCT = 30, 70


def _erode(m):
    p = np.zeros((m.shape[0] + 2, m.shape[1] + 2), bool)
    p[1:-1, 1:-1] = m
    out = np.ones_like(m)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            out &= p[dy:dy + m.shape[0], dx:dx + m.shape[1]]
    return out


def torso_anchor(alpha):
    """(x2, y2): twice the torso point of a body picture, canvas px (x: the median column of the torso band, y: the
    middle of the band), or None when the picture is empty. alpha: 2-D uint8."""
    a = np.asarray(alpha)
    m = a >= TORSO_ALPHA
    if not m.any():
        m = a > 0
    if not m.any():
        return None
    core = m
    for _ in range(TORSO_OPEN):
        core = _erode(core)
    for _ in range(TORSO_OPEN):
        core = ~_erode(~core)
    core &= m
    if not core.any():
        core = m
    # the biggest 8-connected part; ties go to the part met first in row order
    H, W = core.shape
    label = np.zeros((H, W), np.int32)
    best, best_n, n = 0, 0, 0
    for y0 in range(H):
        for x0 in range(W):
            if not core[y0, x0] or label[y0, x0]:
                continue
            n += 1
            label[y0, x0] = n
            stack, cnt = [(y0, x0)], 0
            while stack:
                y, x = stack.pop()
                cnt += 1
                for yy in range(max(0, y - 1), min(H, y + 2)):
                    for xx in range(max(0, x - 1), min(W, x + 2)):
                        if core[yy, xx] and not label[yy, xx]:
                            label[yy, xx] = n
                            stack.append((yy, xx))
            if cnt > best_n:
                best, best_n = n, cnt
    ys, xs = np.nonzero(label == best)
    top, bot = int(ys.min()), int(ys.max()) + 1
    r0 = top * 100 + TORSO_LO_PCT * (bot - top)          # in hundredths of a row
    r1 = top * 100 + TORSO_HI_PCT * (bot - top)
    sel = (ys * 100 >= r0) & (ys * 100 < r1)
    if not sel.any():
        sel = np.ones(len(ys), bool)
    cols = np.sort(xs[sel])
    c = len(cols)
    x2 = int(cols[(c - 1) // 2]) + int(cols[c // 2])
    y2 = int(ys[sel].min()) + int(ys[sel].max())
    return x2, y2


def body_rel(alpha, disp=(0, 0)):
    """the torso of a body as drawn, sprite px at 1x from the creature's place (halves round up), or None"""
    got = torso_anchor(alpha)
    if got is None:
        return None
    h, w = np.asarray(alpha).shape
    return ((got[0] + 1) // 2 - (w - 32) - disp[0], (got[1] + 1) // 2 - (h - 32) - disp[1])


def wing_shift(body, lift=6, limit=64):
    """the shift of the wings' place for a body torso (body_rel): body - lift - anchor; (0, 0) when out of range"""
    ax, ay = anchor_rel()
    sx, sy = body[0] - lift - ax, body[1] - lift - ay
    if abs(sx) > limit or abs(sy) > limit:
        return (0, 0)
    return (sx, sy)


# ------------------------------------------------------------------------------------------------ the pair
class _G:
    pass


def new_group(old, pats, index):
    """the frame group of a drawn wing: 3 x 3 tiles, one layer, 4 directions, 2 y patterns, the old group's z
    patterns and type, 16 phases of FRAME_MS; index(tile RGBA) -> sprite id"""
    from datspr import sprite_index
    g = _G()
    g.gtype = old.gtype
    g.w = g.h = TILES
    g.exact = S
    g.layers, g.px, g.py, g.pz, g.phases = 1, 4, PATTERN_Y, old.pz, k.FRAMES
    g.anim = (0, 0, 0, (FRAME_MS, FRAME_MS) * k.FRAMES)
    sprites = [0] * (g.w * g.h * g.px * g.py * g.pz * g.phases)
    for (y, x, f), img in pats.items():
        for hh in range(g.h):
            for ww in range(g.w):
                tile = img[(g.h - 1 - hh) * 32:(g.h - hh) * 32, (g.w - 1 - ww) * 32:(g.w - ww) * 32]
                sid = index(tile)
                for z in range(g.pz):
                    sprites[sprite_index(g, x, y, z, 0, f, ww, hh)] = sid
    g.sprites = tuple(sprites)
    return g


def group_frame(g, spr, x, y, z, f):
    from datspr import sprite_index
    img = np.zeros((g.h * 32, g.w * 32, 4), np.uint8)
    for hh in range(g.h):
        for ww in range(g.w):
            a = spr.sprite(g.sprites[sprite_index(g, x, y, z, 0, f, ww, hh)])
            if a is not None:
                img[(g.h - 1 - hh) * 32:(g.h - hh) * 32, (g.w - 1 - ww) * 32:(g.w - ww) * 32] = a
    return img


def pair_patterns(dat, spr, look):
    """the pictures of a wings look of a pair in the shape `patterns` gives, or a text saying why not"""
    from import_outfits import parse_body
    t = dat.outfit(look)
    if t is None:
        return 'look %d is not in the pair' % look
    if 'displacement' in t.flags or 'animateAlways' not in t.flags:
        return 'look %d: displacement set or animateAlways missing' % look
    out = None
    for g in parse_body(dat, t):
        if (g.w, g.h, g.layers, g.px, g.py, g.phases) != (TILES, TILES, 1, 4, PATTERN_Y, k.FRAMES):
            return 'look %d: not a drawn wing (%dx%d tiles, %d y patterns, %d phases)' % (look, g.w, g.h, g.py, g.phases)
        if g.anim is None or tuple(g.anim[3]) != (FRAME_MS, FRAME_MS) * k.FRAMES:
            return 'look %d: frame times' % look
        for z in range(g.pz):
            got = {(y, x, f): group_frame(g, spr, x, y, z, f) for y in range(PATTERN_Y) for x in range(4) for f in range(k.FRAMES)}
            if out is None:
                out = got
            elif any(not np.array_equal(out[key], got[key]) for key in out):
                return 'look %d: its groups or z patterns differ' % look
    return out


def new_rows():
    """the six wings of O581 phase 2 (gen_drawn_wings_new.py) as (look, wings id, key, pictures) for `apply` and `check_pair`"""
    import gen_drawn_wings_new as new
    return [(int(r['look']), int(r['wings']), r['key'], new.patterns(r['key'])) for r in new.load()]


def apply(dat_path, spr_path, out_dir, specs=None, log=print, extra=(), keep=(), sides=()):
    """pair in -> pair out in OUT_DIR (not there yet): every row's wings look keeps its id, its flags without the
    displacement, its frame groups and z patterns, and gets the drawn pictures. Outfits, items, effects and missiles
    that are not wings stay byte for byte, sprites are only appended. Verified before the rename. `extra`: more wings
    looks of the same shape as (look, wings id, key, pictures), for the six of O581 phase 2 that pair 78 already holds
    (`apply --new`, O714: they are drawn again in place, pair 77 -> 78 is gen_drawn_wings_new.py build-new).
    `keep`: wings ids whose looks stay exactly as the input pair has them, frame groups and sprite ids (`--keep-painted`,
    O714b: the ten painted rows when the sheets are not at hand).
    `sides`: kept wings ids whose east and west views become the PixelLab side strips of gen_painted_sides.py
    (`--painted-sides`, O724); north and south stay the pictures of the input pair."""
    import hashlib
    import shutil
    import struct
    from datspr import Dat, Spr
    from import_outfits import parse_body, build_entry, encode_flags
    from gen_effects import encode_sprite
    specs = load() if specs is None else specs
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    od, ospr = Dat(dat_path), Spr(spr_path)
    assert od.variant[0] == 'new' and all(od.variant[1:]), 'expected our 10.98 dat: %s' % (od.variant,)
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    cnt = ospr.count
    newrecs, recs = [], {}

    def index(tile):
        rec = encode_sprite(np.ascontiguousarray(tile))
        if rec is None:
            return 0
        rec = bytes(rec)
        if rec not in recs:
            newrecs.append(rec)
            recs[rec] = cnt + len(newrecs)
        return recs[rec]

    entries, expect = {}, {}
    keep = set(keep)
    jobs = [(sp.look, sp.wings, sp.key, None, sp) for sp in specs if sp.wings not in keep] + [(look, wings, key, pats, None) for look, wings, key, pats in extra]
    sides = set(sides)
    if sides - keep:
        raise SystemExit('--painted-sides goes with --keep-painted: rows %s are not kept' % sorted(sides - keep))
    if sides:
        import gen_painted_sides as gps
        for sp in specs:
            if sp.wings in sides:
                base = pair_patterns(od, ospr, sp.look)
                if isinstance(base, str):
                    raise SystemExit(base)
                jobs.append((sp.look, sp.wings, sp.key, gps.side_patterns(base, sp.wings), None))
    for look, wings, key, pats, sp in jobs:
        t = od.outfit(look)
        if t is None:
            raise SystemExit('the pair has no outfit %d (%s)' % (look, key))
        if 'animateAlways' not in t.flags:
            raise SystemExit('outfit %d (%s) is not a wings look of the pair: no animateAlways' % (look, key))
        keep = _G()
        keep.flags = {name: v for name, v in t.flags.items() if name != 'displacement'}
        flags, stripped = encode_flags(keep, od.extra)
        if stripped:
            raise SystemExit('outfit %d: flags %s cannot be kept' % (look, stripped))
        pats = patterns(sp) if pats is None else pats
        expect[look] = pats
        groups = [new_group(g, pats, index) for g in parse_body(od, t)]
        entries[look] = build_entry(flags, groups, {s: s for g in groups for s in g.sprites})
        log('%3d %-22s look %d drawn' % (wings, key, look))
    d = od.data
    parts = [bytes(d[:od.outfits[0].raw[0]])]
    for i, t in enumerate(od.outfits):
        parts.append(entries.get(i + 1) or bytes(d[t.raw[0]:t.raw[1]]))
    parts.append(bytes(d[od.outfits[-1].raw[1]:]))
    tmp = out_dir.rstrip('/') + '.tmp'
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    with open(os.path.join(tmp, 'Tibia.dat'), 'wb') as f:
        f.write(b''.join(parts))
    m, nn = ospr.m, len(newrecs)
    toffs = ospr.offs.astype('<u8').copy()
    toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur)
        cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(tmp, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn))
        f.write(table.tobytes())
        pos = 8 + 4 * cnt
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)])
            pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    md, ms = Dat(os.path.join(tmp, 'Tibia.dat')), Spr(os.path.join(tmp, 'Tibia.spr'))
    assert md.variant == od.variant and md.counts == od.counts and ms.count == cnt + nn and md.max_sprite <= ms.count
    looks = set(entries)
    for i, (a, b) in enumerate(zip(od.outfits, md.outfits)):   # a kept look is not in entries: its bytes are checked here too
        if i + 1 not in looks:
            assert d[a.raw[0]:a.raw[1]] == md.data[b.raw[0]:b.raw[1]], 'outfit %d changed' % (i + 1)
    assert d[:od.outfits[0].raw[0]] == md.data[:md.outfits[0].raw[0]], 'items changed'
    assert d[od.outfits[-1].raw[1]:] == md.data[md.outfits[-1].raw[1]:], 'effects or missiles changed'
    for look, pats in expect.items():
        got = pair_patterns(md, ms, look)
        assert not isinstance(got, str), got
        assert all(np.array_equal(pats[key], got[key]) for key in pats), 'look %d: pictures differ' % look
    step = max(1, cnt // 3000)
    sample = list(range(1, cnt + 1, step)) + [cnt]
    for sid in sample:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), sid
    log('verified: %d wings looks redrawn in place, %d sprite records appended (%d -> %d), every other outfit, item, effect, '
        'missile and %d sampled old sprites unchanged' % (len(entries), nn, cnt, cnt + nn, len(sample)))
    with open(os.path.join(tmp, 'Tibia.dat'), 'rb') as f:
        log('dat md5 %s' % hashlib.md5(f.read()).hexdigest())
    os.rename(tmp, out_dir)
    return sorted(entries)


ART_BY_ROW = os.path.join(HERE, 'drawn_wings', 'art_by_row.csv')


def pack_art_looks(path=ART_BY_ROW):
    """looks of the rows whose art is purchased pack art since pair 83 (O747: `art` pack in drawn_wings/art_by_row.csv,
    written by gen_wst_wear.py, whose live holds them); live here skips them"""
    if not os.path.exists(path):
        return set()
    with open(path, newline='', encoding='utf-8') as f:
        return {int(r['look']) for r in csv.DictReader(f) if r.get('art') == 'pack'}


def check_pair(dat_path, spr_path, specs=None, sums=None, log=print, keep=(), base=None, sides=(), pack=()):
    """a built pair holds the drawn wings: every row's look has the shape and the pictures of designs.sums.
    `pack`: looks redrawn with purchased pack art (O747, pair 83 on): skipped and counted, never held here.
    `keep`: wings ids of the rows kept as they were (`--keep-painted`): not held to designs.sums; with `base` = (dat, spr)
    of the input pair their entry bytes and sprites must equal the base's, else they are only named as skipped.
    `sides` (`--painted-sides`, O724): kept rows whose east and west are the side strips of gen_painted_sides.py and
    whose north and south equal the base pair's pictures (with no base only the side views are held)."""
    from datspr import Dat, Spr
    specs = load() if specs is None else specs
    if sums is None:
        sums = read_sums()
        if SRC_DIR:                                       # a pair built with --src holds the painted rows (O594)
            sums.update(read_sums(SHEET_SUMS))
    pack = set(pack)
    skipped = [sp for sp in specs if sp.look in pack]
    specs = [sp for sp in specs if sp.look not in pack]
    dat, spr = Dat(dat_path), Spr(spr_path)
    bad = []
    keep = set(keep) & {sp.wings for sp in specs}
    bdat, bspr = (Dat(base[0]), Spr(base[1])) if base and keep else (None, None)
    sides = set(sides) & keep
    for sp in specs:
        if sp.wings in sides:
            import gen_painted_sides as gps
            got = pair_patterns(dat, spr, sp.look)
            if isinstance(got, str):
                bad.append(got)
                continue
            want = gps.side_patterns(got if bdat is None else pair_patterns(bdat, bspr, sp.look), sp.wings)
            if isinstance(want, str) or any(not np.array_equal(want[key], got[key]) for key in want):
                bad.append('look %d (%s): painted side views or kept north / south differ' % (sp.look, sp.key))
            continue
        if sp.wings in keep:
            if bdat is None:
                log('look %d (%s): kept painted row, skipped (no --base)' % (sp.look, sp.key))
                continue
            a, b = bdat.outfit(sp.look), dat.outfit(sp.look)
            if a is None or b is None or bdat.data[a.raw[0]:a.raw[1]] != dat.data[b.raw[0]:b.raw[1]]:   # same flags, groups, sprite ids
                bad.append('look %d (%s): kept painted row differs from the base pair' % (sp.look, sp.key))
            else:
                for sid in {s for g in __import__('import_outfits').parse_body(dat, b) for s in g.sprites if s}:
                    x, y = bspr.sprite(sid), spr.sprite(sid)
                    if (x is None) != (y is None) or (x is not None and not np.array_equal(x, y)):
                        bad.append('look %d (%s): kept sprite %d differs' % (sp.look, sp.key, sid))
                        break
            continue
        got = pair_patterns(dat, spr, sp.look)
        if isinstance(got, str):
            bad.append(got)
        elif digest(got) != sums.get(sp.wings):
            bad.append('look %d (%s): pictures are not those of designs.sums' % (sp.look, sp.key))
    for line in bad:
        log(line)
    n = len(specs) - len(keep & {sp.wings for sp in specs})
    log('%d of %d wings looks hold the drawn pictures%s' % (n - len([b for b in bad if 'kept' not in b]), n,
        '' if not keep else '; %d kept painted rows %s%s' % (len(keep), 'equal to the base pair' if bdat else 'skipped',
                                                             '' if not sides else ', %d with the PixelLab side views' % len(sides))))
    if skipped:
        log('%d rows skipped: purchased pack art since pair 83 (O747, drawn_wings/art_by_row.csv; gen_wst_wear.py live holds them)'
            % len(skipped))
    return bad


# ------------------------------------------------------------------------------------------------ pictures
def old_frames(dat, spr, look):
    """({direction: [RGBA of every phase]}, side): a wings look of the pair on a square canvas, bottom right aligned"""
    from datspr import sprite_index
    t = dat.outfit(look)
    disp = (0, 0)
    d = t.flags.get('displacement')
    if isinstance(d, tuple):
        disp = tuple(v - 65536 if v >= 32768 else v for v in d)
    side = max(S, t.w * 32 + 16, t.h * 32 + 16)
    out = {}
    for x, name in enumerate(k.DIRS):
        seq = []
        for p in range(t.phases):
            img = np.zeros((side, side, 4), np.uint8)
            for hh in range(t.h):
                for ww in range(t.w):
                    a = spr.sprite(t.sprites[sprite_index(t, x if t.px >= 4 else 0, 0, 0, 0, p, ww, hh)])
                    if a is None:
                        continue
                    y0, x0 = side - (hh + 1) * 32 - disp[1], side - (ww + 1) * 32 - disp[0]
                    y1, x1 = max(0, y0), max(0, x0)
                    y2, x2 = min(side, y0 + 32), min(side, x0 + 32)
                    if y2 > y1 and x2 > x1:
                        img[y1:y2, x1:x2] = a[y1 - y0:y2 - y0, x1 - x0:x2 - x0]
            seq.append(img)
        out[name] = seq
    return out, side


def on_bg(img):
    out = np.empty(img.shape[:2] + (3,), np.float64)
    out[:] = k.BG
    return k.over(out, img).astype(np.uint8)


def label_strip(width, text, height=12):
    from PIL import Image, ImageDraw
    im = Image.new('RGB', (width, height), (30, 32, 38))
    ImageDraw.Draw(im).text((2, 0), text, fill=(236, 236, 236))
    return np.asarray(im)


def family_sheet(specs, scale):
    """one row a wing: the four directions at frame 0 and the south view six frames on, on the plain figure"""
    bodies = {d: k.silhouette(d) for d in k.DIRS}
    rows = []
    for sp in specs:
        cells = [k.compose({d: {0: render_frame(sp, d, 0)}}, bodies, d, 0) for d in ('south', 'east', 'north', 'west')]
        cells.append(k.compose({'south': {0: render_frame(sp, 'south', 6)}}, bodies, 'south', 0))
        row = k.upscale(np.concatenate(cells, axis=1), scale)
        rows.append(np.concatenate([label_strip(row.shape[1], '%d  %s  %s / %s' % (sp.wings, sp.name, sp.family, sp.var)), row], axis=0))
    return np.concatenate(rows, axis=0)


def by_family(specs):
    out = {}
    for sp in specs:
        out.setdefault(sp.family, []).append(sp)
    return out


def sheets(out_dir, specs=None, log=print):
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for name, rows in sorted(by_family(load() if specs is None else specs).items()):
        for scale in (1, 3):
            path = os.path.join(out_dir, 'sheet_%s_%dx.png' % (name, scale))
            Image.fromarray(family_sheet(rows, scale), 'RGB').save(path)
            written.append(path)
            log(path)
    return written


def compare(out_dir, dat_path, spr_path, specs=None, loops=3, scale=2, per_file=8, log=print):
    """MP4s a family, at most per_file wings a file: every wing a row, the old art of the pair on the left and the drawn wing on the right, four
    directions each"""
    from PIL import Image
    from datspr import Dat, Spr
    os.makedirs(out_dir, exist_ok=True)
    dat, spr = Dat(dat_path), Spr(spr_path)
    bodies = {d: k.silhouette(d) for d in k.DIRS}
    written = []
    jobs = []
    for name, rows in sorted(by_family(load() if specs is None else specs).items()):
        chunks = [rows[i:i + per_file] for i in range(0, len(rows), per_file)]
        for i, chunk in enumerate(chunks):
            jobs.append((name if len(chunks) == 1 else '%s_%d' % (name, i + 1), chunk))
    for name, rows in jobs:
        parts = []
        for sp in rows:
            old, side = old_frames(dat, spr, sp.look)
            for d in k.DIRS:
                seq = [on_bg(img) for img in old[d]]
                if side > S:
                    seq = [np.asarray(Image.fromarray(img).resize((S, S), Image.NEAREST)) for img in seq]
                old[d] = seq
            new = {d: [render_frame(sp, d, f) for f in range(k.FRAMES)] for d in k.DIRS}
            parts.append((sp, old, new))
        frames = []
        for f in range(k.FRAMES * loops):
            lines = []
            for sp, old, new in parts:
                left = [old[d][(f % k.FRAMES) * len(old[d]) // k.FRAMES] for d in k.DIRS]
                right = [k.compose(new, bodies, d, f % k.FRAMES) for d in k.DIRS]
                gap = np.full((S, 8, 3), 20, np.uint8)
                row = np.concatenate(left + [gap] + right, axis=1)
                row = np.concatenate([label_strip(row.shape[1], '%d  %s    old: %s    new: %s / %s'
                                                  % (sp.wings, sp.name, sp.old, sp.family, sp.var)), row], axis=0)
                lines.append(row)
            sheet = k.upscale(np.concatenate(lines, axis=0), scale)
            frames.append(sheet[:sheet.shape[0] // 2 * 2, :sheet.shape[1] // 2 * 2])
        path = os.path.join(out_dir, 'compare_%s.mp4' % name)
        k.write_mp4(path, frames)
        written.append(path)
        log(path)
    return written


PLAYER_LOOKS = os.path.join(HERE, '..', '..', '..', 'server', 'data', 'monster', 'player_looks.csv')


def player_looks(path=PLAYER_LOOKS):
    """{look: source} of the looks a player can wear or ride (outfits.xml, mounts.xml, ...)"""
    with open(path, newline='', encoding='utf-8') as f:
        return {int(r['look']): r['source'] for r in csv.DictReader(f)}


def parse_fit_look(item, players):
    """'LOOK[+ADDONS][:MOUNT]' -> (look, mount, addons); only a player outfit on a player mount passes (O587)"""
    body, _, mount = str(item).partition(':')
    look, _, addons = body.partition('+')
    look, mount, addons = int(look), int(mount or 0), int(addons or 0)
    if players.get(look) != 'outfits.xml':
        raise SystemExit('fit: look %d is no player outfit (player_looks.csv, outfits.xml)' % look)
    if mount and players.get(mount) != 'mounts.xml':
        raise SystemExit('fit: look %d is no mount (player_looks.csv, mounts.xml)' % mount)
    if not 0 <= addons <= 3:
        raise SystemExit('fit: addons are 0 to 3')
    return look, mount, addons


def fit_preview(out_dir, dat_path, spr_path, looks, wings=1, loops=4, scale=3, log=print):
    """one new wing on several looks, four directions: left the engine rule of base patch 0204 (the body measured from
    its picture, emulated here), right the old table rule of base patch 0193 (x only, the torso of gen_wing_centres on
    the wings' own centre). A look is LOOK, LOOK+ADDONS (1, 2 or 3) or either with :MOUNT (drawn riding, its z
    pattern 1, over the mount). Player bodies only (O587): a look must be a row `outfits.xml` of
    server/data/monster/player_looks.csv (the class looks and the other outfits a player can wear) of at most 2 x 2
    tiles, a mount a row `mounts.xml`; a monster or a 3 x 3 store look is refused."""
    from datspr import Dat, Spr, sprite_index
    import gen_wing_centres as gw
    os.makedirs(out_dir, exist_ok=True)
    dat, spr = Dat(dat_path), Spr(spr_path)
    sp = [s for s in load() if s.wings == wings][0]
    new = {d: [render_frame(sp, d, f) for f in range(k.FRAMES)] for d in k.DIRS}
    ax, ay = anchor_rel()
    cell = 128                                              # the creature's tile is at (64..96, 64..96) of a cell

    def picture(t, x, z, addons=0):
        out = None
        for y in range(min(t.py, 3)):                       # the body, then each addon worn (y patterns 1 and 2)
            if y and not addons & (1 << (y - 1)):
                continue
            layers = []
            for layer in range(min(t.layers, 2)):
                img = np.zeros((t.h * 32, t.w * 32, 4), np.uint8)
                for hh in range(t.h):
                    for ww in range(t.w):
                        a = spr.sprite(t.sprites[sprite_index(t, x if t.px >= 4 else 0, y, min(z, t.pz - 1), layer, 0, ww, hh)])
                        if a is not None:
                            img[(t.h - 1 - hh) * 32:(t.h - hh) * 32, (t.w - 1 - ww) * 32:(t.w - ww) * 32] = a
                layers.append(img)
            body = layers[0].astype(np.float64)
            if len(layers) > 1:
                for key, colour in k.TINT.items():
                    sel = (layers[1][..., :3] == key).all(axis=2) & (layers[1][..., 3] > 0)
                    body[sel, :3] = body[sel, :3] * np.asarray(colour) / 170.0
            body = np.clip(body, 0, 255).astype(np.uint8)
            if out is None:
                out = body
            else:
                on = body[..., 3] > 0
                out[on] = body[on]
        return out

    players = player_looks()

    rows = []
    for item in looks:
        look, mount, addons = parse_fit_look(item, players)
        t = dat.outfit(look)
        if t.w > 2 or t.h > 2:
            raise SystemExit('fit: look %d is %d x %d tiles, no player body (O587)' % (look, t.w, t.h))
        disp = gw.displacement(t)
        mt = dat.outfit(mount) if mount else None
        mdisp = gw.displacement(mt) if mt else (0, 0)
        per = []
        for x, d in enumerate(k.DIRS):
            body = picture(t, x, 1 if mount else 0, addons)
            # a rider is drawn at the mount's displacement, its own left out (Outfit::draw, positive mounts)
            off = mdisp if mt else disp
            rel = body_rel(body[..., 3], off)
            new_shift = wing_shift(rel) if rel else (0, 0)
            tx = gw.torso_x(picture(t, x, 0, addons)[..., 3])
            old_shift = (0, 0)
            if tx is not None:
                old_shift = (int(round(tx - (t.w * 32 - 32) - disp[0])) - 6 - ax, 0)
            per.append((d, body, off, picture(mt, x, 0) if mt else None, new_shift, old_shift))
        rows.append((item, t, mt, mdisp, per))

    def put(dst, src, x0, y0):
        h, w = src.shape[:2]
        x1, y1 = max(0, x0), max(0, y0)
        x2, y2 = min(cell, x0 + w), min(cell, y0 + h)
        if x2 > x1 and y2 > y1:
            dst[y1:y2, x1:x2] = k.over(dst[y1:y2, x1:x2], src[y1 - y0:y2 - y0, x1 - x0:x2 - x0])

    frames = []
    for f in range(k.FRAMES * loops):
        lines = []
        for item, t, mt, mdisp, per in rows:
            cells = []
            for which in (0, 1):
                for d, body, off, mount_img, new_shift, old_shift in per:
                    shift = (new_shift, old_shift)[which]
                    img = np.empty((cell, cell, 3), np.float64)
                    img[:] = k.BG
                    back, front = new[d][f % k.FRAMES]
                    wx, wy = 96 - S + shift[0], 96 - S + shift[1]
                    if mount_img is not None:
                        put(img, mount_img, 96 - mt.w * 32 - mdisp[0] - 6, 96 - mt.h * 32 - mdisp[1] - 6)
                    put(img, back, wx, wy)
                    put(img, body, 96 - t.w * 32 - off[0] - 6, 96 - t.h * 32 - off[1] - 6)
                    put(img, front, wx, wy)
                    cells.append(img.astype(np.uint8)[16:, 16:])
                cells.append(np.full((cell - 16, 8, 3), 20, np.uint8))
            row = np.concatenate(cells[:-1], axis=1)
            row = np.concatenate([label_strip(row.shape[1], 'look %s    left: the body measured by the engine (0204)    '
                                              'right: the old table (0193, x only)' % item), row], axis=0)
            lines.append(row)
        sheet = k.upscale(np.concatenate(lines, axis=0), scale)
        frames.append(sheet[:sheet.shape[0] // 2 * 2, :sheet.shape[1] // 2 * 2])
    path = os.path.join(out_dir, 'fit_%s.mp4' % sp.key)
    k.write_mp4(path, frames)
    log(path)
    return path


# ------------------------------------------------------------------------------------------------ likeness (O587)
NORM = 64                   # a wing is compared on a square of this side, its own box centred on it
SCORE_W = (('shape', 0.4), ('colour', 0.25), ('layout', 0.2), ('motion', 0.15))


def _alpha_box(masks):
    """the box round every mask of a list (x0, y0, x1, y1), or None"""
    any_ = np.zeros(masks[0].shape, bool)
    for m in masks:
        any_ |= m
    ys, xs = np.nonzero(any_)
    if not len(xs):
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def _norm_mask(mask, box):
    """the mask in its box, on NORM x NORM, the longer side of the box filling it (nearest pixel)"""
    x0, y0, x1, y1 = box
    side = float(max(x1 - x0, y1 - y0))
    ys = ((np.arange(NORM) + 0.5) / NORM - 0.5) * side + (y0 + y1) / 2.0
    xs = ((np.arange(NORM) + 0.5) / NORM - 0.5) * side + (x0 + x1) / 2.0
    yi, xi = np.floor(ys).astype(int), np.floor(xs).astype(int)
    ok_y = (yi >= 0) & (yi < mask.shape[0])
    ok_x = (xi >= 0) & (xi < mask.shape[1])
    sub = mask[np.clip(yi, 0, mask.shape[0] - 1)][:, np.clip(xi, 0, mask.shape[1] - 1)]
    return sub & ok_y[:, None] & ok_x[None, :]


def colour_hist(frames):
    """the colour areas of a list of RGBA pictures: 12 hue bins of the coloured pixels, 4 grey bins by lightness,
    as shares of the solid pixels"""
    hist = np.zeros(16)
    for img in frames:
        sel = img[..., 3] >= 128
        if not sel.any():
            continue
        c = img[sel][:, :3].astype(np.float64) / 255.0
        mx, mn = c.max(axis=1), c.min(axis=1)
        dlt = mx - mn
        s = np.where(mx > 0, dlt / np.maximum(mx, 1e-9), 0.0)
        r, g, b = c[:, 0], c[:, 1], c[:, 2]
        d = np.maximum(dlt, 1e-9)
        h = np.where(mx == r, ((g - b) / d) % 6.0, np.where(mx == g, (b - r) / d + 2.0, (r - g) / d + 4.0)) / 6.0
        grey = (s < 0.22) | (mx < 0.2)
        hist[:12] += np.bincount((h[~grey] * 12).astype(int) % 12, minlength=12)
        hist[12:] += np.bincount(np.minimum((mx[grey] * 4).astype(int), 3), minlength=4)
    total = hist.sum()
    return hist / total if total else hist


def likeness(old, new):
    """how far a drawn wing is from the old art: {'shape', 'colour', 'layout', 'motion', 'score'}; 0 the same, 100
    nothing alike. old, new: {direction: [RGBA pictures]} (any size, any count of frames).
    shape: 1 - IoU of the silhouettes, each in its own box on a NORM square, per direction and frame;
    colour: half the L1 distance of the colour histograms (hue areas, greys by lightness);
    layout: the box (width : height), how much of it the art fills, and where the mass lies from top to bottom;
    motion: the share of the silhouette that changes over the loop (left out when the old art has one frame)."""
    shape, layout, mot = [], [], []
    for d in k.DIRS:
        om = [f[..., 3] >= 128 for f in old[d]]
        nm = [f[..., 3] >= 128 for f in new[d]]
        ob, nb_ = _alpha_box(om), _alpha_box(nm)
        if ob is None or nb_ is None:
            shape.append(1.0)
            layout.append(1.0)
            continue
        on = [_norm_mask(m, ob) for m in om]
        nn = [_norm_mask(m, nb_) for m in nm]
        ious = []
        for f in range(len(nn)):
            a, b = on[f * len(on) // len(nn)], nn[f]
            u = (a | b).sum()
            ious.append((a & b).sum() / float(u) if u else 0.0)
        shape.append(1.0 - float(np.mean(ious)))
        ow, oh = ob[2] - ob[0], ob[3] - ob[1]
        nw, nh = nb_[2] - nb_[0], nb_[3] - nb_[1]
        asp = abs(math.log((ow / float(oh)) / (nw / float(nh))))
        of = np.mean([m.sum() for m in om]) / float(ow * oh)
        nf = np.mean([m.sum() for m in nm]) / float(nw * nh)
        orow = np.mean([m.mean(axis=1) for m in on], axis=0)
        nrow = np.mean([m.mean(axis=1) for m in nn], axis=0)
        prof = float(np.abs(orow / max(orow.sum(), 1e-9) - nrow / max(nrow.sum(), 1e-9)).sum()) / 2.0
        layout.append(min(1.0, 0.8 * min(asp, 1.0) + 1.2 * abs(of - nf) + prof))
        if len(on) > 1:
            mot.append(min(1.0, abs(moved(on) - moved(nn)) * 2.0))
    ho = colour_hist([f for d in k.DIRS for f in old[d]])
    hn = colour_hist([f for d in k.DIRS for f in new[d]])
    out = {'shape': float(np.mean(shape)), 'colour': float(np.abs(ho - hn).sum() / 2.0), 'layout': float(np.mean(layout)),
           'motion': float(np.mean(mot)) if mot else None}
    wsum = sum(w for name, w in SCORE_W if out[name] is not None)
    out['score'] = 100.0 * sum(w * out[name] for name, w in SCORE_W if out[name] is not None) / wsum
    return out


def score_rows(dat_path, spr_path, specs=None, draw=None):
    """{wings id: likeness} of every row against the old art of a pair (O587); draw(sp) -> frames, default `render`"""
    from datspr import Dat, Spr
    specs = load() if specs is None else specs
    dat, spr = Dat(dat_path), Spr(spr_path)
    out = {}
    for sp in specs:
        old, _ = old_frames(dat, spr, sp.look)
        frames = (draw or render)(sp)
        out[sp.wings] = likeness(old, {d: [k.merge(b, f) for b, f in frames[d]] for d in k.DIRS})
    return out


def score_text(specs, scores):
    lines = ['wings\tkey\tfamily\tvariant\tshape\tcolour\tlayout\tmotion\tscore']
    for sp in specs:
        r = scores[sp.wings]
        lines.append('%d\t%s\t%s\t%s\t%.3f\t%.3f\t%.3f\t%s\t%.1f' % (
            sp.wings, sp.key, sp.family, sp.var, r['shape'], r['colour'], r['layout'],
            '-' if r['motion'] is None else '%.3f' % r['motion'], r['score']))
    vals = [scores[sp.wings]['score'] for sp in specs]
    lines.append('# mean %.1f  median %.1f  worst %.1f' % (float(np.mean(vals)), float(np.median(vals)), max(vals)))
    return '\n'.join(lines) + '\n'


# ------------------------------------------------------------------------------------------------ measuring (O590)
def moved(masks):
    """the share of a silhouette that changes over its loop"""
    base = np.mean(masks, axis=0)
    return float(np.mean([np.abs(m - base).sum() for m in masks]) / max(base.sum(), 1.0))


def measure_beat(frames):
    """how much a wing moves: `moved` of its pictures, each direction in its own box, the mean of the four"""
    out = []
    for d in k.DIRS:
        masks = [f[..., 3] >= 128 for f in frames[d]]
        box = _alpha_box(masks)
        if box is not None:
            out.append(moved([_norm_mask(m, box) for m in masks]))
    return float(np.mean(out)) if out else 0.0


def _lead(px):
    """the commonest of three groups of colours; of two the same size the lighter"""
    lumv = px @ np.array([0.3, 0.59, 0.11])
    centres = np.array([np.median(px[(lumv >= np.percentile(lumv, q0)) & (lumv <= np.percentile(lumv, q1))], axis=0)
                        for q0, q1 in ((0, 33), (33, 67), (67, 100))])
    lab = np.zeros(len(px), int)
    for _ in range(8):
        lab = np.argmin(((px[:, None, :] - centres[None]) ** 2).sum(axis=2), axis=1)
        for j in range(3):
            if (lab == j).any():
                centres[j] = px[lab == j].mean(axis=0)
    counts = np.bincount(lab, minlength=3)
    w = [counts[j] * (0.85 + 0.3 * float(centres[j] @ np.array([0.3, 0.59, 0.11])) / 255.0) for j in range(3)]
    return centres[int(np.argmax(w))]


def measure_zones(frames, strip, sgn, meet):
    """six colours of an old wing: the inner, middle and outer third of its strip, each the upper and the lower
    half (the leading colour of the zone, its dark outline pixels left out). frames: RGBA pictures of one view;
    strip: the wing's numbers; meet: the px where the wings meet"""
    img = frames[0]
    h, w_ = img.shape[:2]
    vals = strip
    xs = [vals[0]] + [vals[2 + 4 * i] for i in range(st.STATIONS)] + [vals[-2]]
    ys = [vals[1]] + [vals[3 + 4 * i] for i in range(st.STATIONS)] + [vals[-1]]
    ox = int(k.clamp(S // 2 - (min(xs) + max(xs)) // 2, -meet[0], S - meet[0] + 200))
    oy = int(k.clamp(S // 2 - (min(ys) + max(ys)) // 2, -meet[1], S - meet[1] + 200))
    win = np.zeros((S, S, 4), np.uint8)                   # the wing in a cell of its own
    x0, y0 = meet[0] - ox, meet[1] - oy                   # picture px of the cell's corner
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(w_, x0 + S), min(h, y0 + S)
    if sx1 > sx0 and sy1 > sy0:
        win[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = img[sy0:sy1, sx0:sx1]
    strip_ = st.Strip(vals, sgn, (ox, oy))
    ss, tt = strip_.field()
    solid = (win[..., 3] >= 128) & (np.abs(tt) <= 1.3)
    rgbs = win[..., :3].astype(np.float64)
    lumv = rgbs @ np.array([0.3, 0.59, 0.11])
    out = []
    whole_ = rgbs[solid] if solid.sum() >= 3 else np.array([[128.0, 128.0, 128.0]] * 3)
    for i in range(3):
        for j in range(2):
            sel = solid & (np.clip((ss * 3).astype(int), 0, 2) == i) & ((tt >= 0) == bool(j))
            px = rgbs[sel]
            if len(px) >= 12:                             # without the dark outline pixels
                lv = lumv[sel]
                keep = lv > np.percentile(lv, 25) if (lv > 40).mean() > 0.5 else np.ones(len(lv), bool)
                px = px[keep] if keep.sum() >= 8 else px
            out.append(_lead(px) if len(px) >= 8 else None)
    fill = _lead(whole_)
    for i in range(6):                                    # a zone that is nearly all outline says nothing
        if out[i] is not None and lum(out[i]) < 30 and lum(fill) > 70:
            out[i] = None
    for i in range(6):                                    # an empty zone takes its neighbour's colour
        if out[i] is None:
            near = [out[j] for j in (i ^ 1, i - 2, i + 2, i - 1, i + 1) if 0 <= j < 6 and out[j] is not None]
            out[i] = near[0] if near else fill
    return ' '.join('%02x%02x%02x' % tuple(int(round(v)) for v in c) for c in out)


def measure(dat_path, spr_path, write=False, log=print):
    """read the strips (`sl`, `sr`, `nl`, `nr`), the zone colours (`zones`) and the beat of every row from the old
    art of a pair and, with `write`, put the numbers in designs.csv. The pair is only read here, by hand, never at
    build; the table holds numbers, no picture."""
    from datspr import Dat, Spr
    dat, spr = Dat(dat_path), Spr(spr_path)
    with open(CSV, newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    fields = [name for name in rows[0].keys() if name not in ('env', 'tips', 'core', 'fit', 'size')]
    for name in ('sl', 'sr', 'nl', 'nr', 'zones', 'beat'):
        if name not in fields:
            fields.insert(fields.index('old'), name)
    for row in rows:
        for name in ('env', 'tips', 'core', 'fit', 'size'):
            row.pop(name, None)
        old, _ = old_frames(dat, spr, int(row['look']))
        for d, (a, b) in (('south', ('sl', 'sr')), ('north', ('nl', 'nr'))):
            left, right = st.measure_view(old[d])
            row[a], row[b] = st.text_of(left), st.text_of(right)
        left, right = st.parse(row['sl']), st.parse(row['sr'])
        meet = st.view_meet(old['south'])
        big, sgn = (left, -1) if right is None or (left is not None and st.Strip(left, -1, (0, 0)).length >= st.Strip(right, 1, (0, 0)).length) else (right, 1)
        row['zones'] = measure_zones(old['south'], big, sgn, meet)
        row['beat'] = '%.2f' % measure_beat(old) if len(old['south']) > 1 else ''
        log('%3s %-20s %s | %s | %s' % (row['wings'], row['key'], row['sl'], row['sr'], row['zones']))
    if write:
        with open(CSV, 'w', newline='', encoding='utf-8') as f:
            wr = csv.DictWriter(f, fieldnames=fields, lineterminator='\n')
            wr.writeheader()
            wr.writerows(rows)
    return rows


def write_or_check(path, text, check):
    old = None
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            old = f.read()
    if check:
        return [] if old == text else ['%s is stale: run `gen_drawn_wings.py table`' % os.path.basename(path)]
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    return []


def main(argv):
    """the commands of the table (gen_drawn_wings.py hands them over)"""
    import sys
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    cmd, args = argv[0], argv[1:]
    check = '--check' in args
    with_new = '--new' in args                            # apply and live also take the six wings looks of O581 phase 2
    if with_new and cmd not in ('apply', 'live'):
        raise SystemExit('--new goes with apply and live')
    keep_painted = '--keep-painted' in args               # apply and live: the ten painted rows stay as the input pair has them (O714b)
    painted_sides = '--painted-sides' in args             # with --keep-painted: their east and west from gen_painted_sides.py (O724)
    sides_only = '--sides-only' in args                   # apply --keep-painted --painted-sides: only the ten painted looks change (O724)
    if sides_only and not (painted_sides and cmd == 'apply'):
        raise SystemExit('--sides-only goes with apply --keep-painted --painted-sides')
    if painted_sides and not keep_painted:
        raise SystemExit('--painted-sides goes with --keep-painted (apply and live)')
    if keep_painted and cmd not in ('apply', 'live'):
        raise SystemExit('--keep-painted goes with apply and live')
    base = None
    if '--base' in args:                                  # live --keep-painted: the input pair, the kept rows are held equal to it
        i = args.index('--base')
        if cmd != 'live' or i + 2 >= len(args):
            raise SystemExit('--base DAT SPR goes with live --keep-painted')
        base = (args[i + 1], args[i + 2])
        del args[i:i + 3]
    args = [a for a in args if a not in ('--check', '--new', '--keep-painted', '--painted-sides', '--sides-only')]
    if keep_painted and '--src' in args:
        raise SystemExit('--keep-painted and --src exclude each other')
    keep = set(sheet_rows()) if keep_painted else set()
    sides = set(keep) if painted_sides else set()
    if '--src' in args:                                   # the folder of the painted sheets (O594)
        i = args.index('--src')
        if cmd == 'table' or i + 1 >= len(args):
            raise SystemExit('--src DIR goes with sheets, compare, fit, score, apply and live; '
                             'the table of the sheets is gen_pixellab_wings.py table DIR')
        if not os.path.isdir(args[i + 1]):
            raise SystemExit('%s: no such folder' % args[i + 1])
        use_src(args[i + 1])
        del args[i:i + 2]
    elif cmd == 'table':
        use_src('')                                       # designs.sums is the code drawing of every row
    if cmd == 'table':
        bad = problems()
        if not bad:
            sums = all_digests()
            if len(set(sums.values())) != len(sums):
                bad.append('two rows draw the same pictures')
            bad += write_or_check(SUMS, sums_text(sums), check)
            bad += write_or_check(ANCHORS, anchors_text(), check)
            bad += write_or_check(FIXTURES, fixtures_text(), check)
        for line in bad:
            print(line)
        print('%d rows, %d families%s' % (len(load()), len(by_family(load())), '' if bad else ': ok'))
        return 1 if bad else 0
    if cmd == 'sheets':
        sheets(args[0])
        return 0
    if cmd == 'compare':
        compare(args[0], args[1], args[2])
        return 0
    if cmd == 'fit':
        fit_preview(args[0], args[1], args[2], args[3].split(','), wings=int(args[4]) if len(args) > 4 else 1)
        return 0
    if cmd == 'measure':
        measure(args[0], args[1], write='--write' in args)
        return 0
    if cmd == 'score':
        specs = load()
        text = score_text(specs, score_rows(args[0], args[1], specs))
        if len(args) > 2:
            with open(args[2], 'w', encoding='utf-8') as f:
                f.write(text)
        print(text, end='')
        return 0
    if cmd == 'apply':
        apply(args[0], args[1], args[2], specs=[sp for sp in load() if sp.wings in sides] if sides_only else None,
              extra=new_rows() if with_new else (), keep=keep, sides=sides)
        return 0
    if cmd == 'live':
        bad = check_pair(args[0], args[1], keep=keep, base=base, sides=sides, pack=pack_art_looks())
        if with_new:
            import gen_drawn_wings_new as new
            bad += new.live(args[0], args[1])
        return 1 if bad else 0
    raise SystemExit('unknown command %s' % cmd)


COMMANDS = ('table', 'sheets', 'compare', 'fit', 'apply', 'live', 'measure', 'score')


# ------------------------------------------------------------------------------------------------ shared fixtures
FIXTURES = os.path.join(HERE, 'drawn_wings', 'anchor_fixtures.txt')
FIX_CHARS = {'.': 0, '-': 30, '+': 100, '#': 255}


def _blank(w, h):
    return np.zeros((h, w), np.uint8)


def _figure(a, cx, top, bot, half=7, value=255):
    """a plain standing figure: a head, a trunk and two legs"""
    hh = bot - top
    a[top:top + hh // 4, cx - 4:cx + 4] = value
    a[top + hh // 4:top + 3 * hh // 4, cx - half:cx + half] = value
    a[top + 3 * hh // 4:bot, cx - half:cx - 1] = value
    a[top + 3 * hh // 4:bot, cx + 1:cx + half] = value
    return a


def anchor_fixtures():
    """[(name, alpha)]: masks the C++ header and the Python twin must measure alike"""
    out = []
    out.append(('plain', _figure(_blank(64, 64), 34, 18, 58)))
    a = _figure(_blank(64, 64), 34, 18, 58)
    a[4:60, 50:52] = 255                                   # a staff two wide, held apart
    a[30:32, 41:50] = 255                                  # the arm that holds it
    out.append(('thin_staff', a))
    a = _figure(_blank(64, 64), 30, 18, 58)
    a[26:54, 37:58] = 255                                  # a cape that hangs wide on one side
    out.append(('wide_cape', a))
    a = _figure(_blank(96, 96), 52, 20, 52, half=6)        # a rider drawn high in a big canvas
    out.append(('mounted', a))
    a = _figure(_blank(64, 64), 30, 14, 52)
    a[52:60, 34:60] = 40                                   # a faint ground shadow under the kAlpha cut
    a[54:59, 44:56] = 120                                  # its darker heart: visible, but a small part of its own
    out.append(('shadow_blob', a))
    out.append(('empty', _blank(64, 64)))
    a = _blank(32, 32)
    a[10:24, 12:20] = 30                                   # only faint pixels: they are the figure
    out.append(('faint_only', a))
    a = _blank(32, 32)
    a[15:17, 3:29] = 255                                   # nothing survives the opening: the mask itself
    out.append(('thin_only', a))
    a = _figure(_blank(64, 64), 8, 20, 60, half=7)         # a figure against the left edge of the picture
    out.append(('at_the_edge', a))
    a = _blank(64, 64)
    a[20:40, 10:22] = 255                                  # two parts of one size: the first in row order wins
    a[20:40, 40:52] = 255
    out.append(('two_equal', a))
    return out


def fixtures_text():
    back = {v: c for c, v in FIX_CHARS.items()}
    lines = ['# Generated by client/tools/sprites/gen_drawn_wings.py table. Masks for the torso rule of base patch 0204:',
             '# name width height x2 y2 (twice the canvas point; - - when there is nothing to measure), then the rows.',
             '# . 0   - 30   + 100   # 255. client/tools/chaoswinganchor_test.cpp and gen_drawn_wings_test.py read it.']
    for name, a in anchor_fixtures():
        got = torso_anchor(a)
        lines.append('%s %d %d %s' % (name, a.shape[1], a.shape[0], '%d %d' % got if got else '- -'))
        for row in a:
            lines.append(''.join(back[min(back, key=lambda v: abs(v - int(p)))] for p in row))
    return '\n'.join(lines) + '\n'


def read_fixtures(path=FIXTURES):
    out = []
    with open(path, encoding='utf-8') as f:
        lines = [ln.rstrip('\n') for ln in f if not ln.startswith('#')]
    i = 0
    while i < len(lines):
        name, w, h, x2, y2 = lines[i].split()
        w, h = int(w), int(h)
        a = np.array([[FIX_CHARS[c] for c in lines[i + 1 + r]] for r in range(h)], np.uint8)
        assert a.shape == (h, w), name
        out.append((name, a, None if x2 == '-' else (int(x2), int(y2))))
        i += 1 + h
    return out


# ------------------------------------------------------------------------------------------------ the bar (O581)
def _touches_open(alpha):
    """opaque pixels with a transparent 4-neighbour"""
    op = alpha == 255
    clear = alpha == 0
    near = np.zeros_like(op)
    near[1:, :] |= clear[:-1, :]
    near[:-1, :] |= clear[1:, :]
    near[:, 1:] |= clear[:, :-1]
    near[:, :-1] |= clear[:, 1:]
    return op & near


def _frame_bar(img, outline):
    a = img[..., 3]
    bad = []
    if not set(np.unique(a).tolist()) <= {0, 255, k.GLOW_ALPHA}:
        bad.append('alpha is not 0, 255 or the glow level')
    edge = _touches_open(a)
    if (edge & ~(img[..., :3] == np.asarray(outline, np.uint8)).all(axis=2)).any():
        bad.append('an open edge is not the outline colour')
    if a[0, :].any() or a[-1, :].any() or a[:, 0].any() or a[:, -1].any():
        bad.append('art touches the cell border')
    if img[a == 0][:, :3].any():
        bad.append('a transparent pixel carries colour')
    return bad


def bar_problems(sp, frames=None):
    """the bar of docs/SPRITE_STYLE.md "Wings" on one row: what the six wings of O581 hold, every redone wing holds.
    16 frames a direction, alpha 0 / 255 / one glow level, the outline on every open edge of the back, the front and
    the two together, nothing on the cell border, a loop that moves at every step and closes without a jump, four
    directions that differ, both layers used, the art round the anchor."""
    frames = render(sp) if frames is None else frames
    bad = set()
    used = {'back': 0, 'front': 0}
    merged = {}
    for d in k.DIRS:
        if len(frames[d]) != k.FRAMES:
            bad.add('%s: not 16 frames' % d)
        merged[d] = []
        for back, front in frames[d]:
            both = k.merge(back, front)
            for name, img in (('back', back), ('front', front), ('merged', both)):
                for what in _frame_bar(img, sp.outline):
                    bad.add('%s: %s' % (name, what))
            used['back'] += int((back[..., 3] == 255).sum())
            used['front'] += int((front[..., 3] == 255).sum())
            if (both[..., 3] == 255).sum() < 120:
                bad.add('%s: a frame with under 120 solid pixels' % d)
            merged[d].append(both)
        n = len(merged[d])
        steps = [int((merged[d][i] != merged[d][(i + 1) % n]).any(axis=2).sum()) for i in range(n)]
        if min(steps) == 0:
            bad.add('%s: a frame equals the next' % d)
        if steps[n - 1] > 1.5 * max(steps[:n - 1]):
            bad.add('%s: a jump from the last frame to the first' % d)
        if np.array_equal(merged[d][0], merged[d][n // 2]):
            bad.add('%s: half a cycle later it looks the same' % d)
    if not used['back'] or not used['front']:
        bad.add('a layer is empty (%s)' % used)
    for i, a in enumerate(k.DIRS):
        for b in k.DIRS[i + 1:]:
            if np.array_equal(merged[a][0], merged[b][0]):
                bad.add('%s and %s look the same' % (a, b))
    ys, xs = np.nonzero(np.max([m[..., 3] for d in k.DIRS for m in merged[d]], axis=0))
    if abs(xs.mean() - k.ANCHOR[0]) >= 16 or abs(ys.mean() - k.ANCHOR[1]) >= 32:      # y: a tile (24 before O714, when the side wings hung)
        bad.add('the art is far from the anchor (%.1f, %.1f)' % (xs.mean(), ys.mean()))
    bad.update(layout_problems(sp, frames, merged))
    return sorted(bad)


SIDE_EXCEPT = {                 # named exceptions of the side view rules (O714c), with the reason
    'gale_streak': ('is short', 'does not stand over'),       # a burst of rays round the root: the rays that stand up face on
}                                                              # would point at the face from the side, so they are cut at the back line
LOPSIDED = 0.02             # the share of a face-on pair without a mirror partner
SIDE_RISE_MIN = 8           # px a side wing rises over the join at least
SIDE_HANG_MAX = 0.25        # the most of a side wing that may lie under the anchor row (a tail or a stalk of a few
                            # designs does: kite, maple leaf, torn bat; the painted rows hold 0.12, gen_pixellab_wings.py)


def layout_problems(sp, frames, merged=None, sides=None):
    """the layout of O714 on one row: a face-on pair is the same left and right about the anchor column, west is east
    mirrored (exactly, for a row drawn by code), a side wing rises from the join and trails behind the body (east to the
    left, west to the right) and does not hang under the anchor row. The painted rows (O620) hold their own checks
    of the same facts (gen_pixellab_wings.py)."""
    merged = merged or {d: [k.merge(b, f) for b, f in frames[d]] for d in k.DIRS}
    bad = set()
    if sheet_faces(sp) is None:                           # a painted row holds its own (O620, gen_pixellab_wings.py)
        for d in ('south', 'north'):
            for img in merged[d]:
                m = img[..., 3] > 0
                if (m ^ k.mirrored(m))[:, 1:].sum() > LOPSIDED * max(1, int(m.sum())):
                    bad.add('%s: the pair is not the same left and right' % d)
                    break
        for (be, fe), (bw, fw) in zip(frames['east'], frames['west']):
            if not (np.array_equal(k.mirrored(be), bw) and np.array_equal(k.mirrored(fe), fw)):
                bad.add('west is not east mirrored')
                break
        for f, img in enumerate(merged['east']):         # the side view of O714c, every frame
            near, far = sides[f] if sides is not None else side_masks(sp, f)
            bad.update('east: ' + b for b in k.side_problems(near, far, img, merged['south'][f], JOIN, sp.outline)
                       if not any(w in b for w in SIDE_EXCEPT.get(sp.key, ())))
    for d, sign in (('east', -1), ('west', 1)):
        for img in merged[d]:
            ys, xs = np.nonzero(img[..., 3] == 255)
            if not len(ys):
                continue
            if JOIN[1] - int(ys.min()) < SIDE_RISE_MIN:
                bad.add('%s: the side wing does not rise over the join' % d)
            if float((ys >= k.ANCHOR[1]).mean()) > SIDE_HANG_MAX:
                bad.add('%s: the side wing hangs under the anchor row' % d)
            reach = ((JOIN[0] - int(xs.min())) - (int(xs.max()) - JOIN[0])) * -sign     # the reach behind the join minus the reach in front
            if reach <= 0:
                bad.add('%s: the side wing trails the wrong way' % d)
    return sorted(bad)


def _report_row(sp):
    frames = render(sp)
    pats = {}
    for x, d in enumerate(k.DIRS):
        for f, (back, front) in enumerate(frames[d]):
            pats[(0, x, f)] = whole(back, front)
            pats[(1, x, f)] = front
    return sp.wings, digest(pats), bar_problems(sp, frames)


def all_reports(specs=None, jobs=None):
    """{wings id: (sha256 of its pictures, the bar's problems)}; one drawing a row, in parallel"""
    import multiprocessing
    specs = load() if specs is None else specs
    jobs = jobs or min(4, os.cpu_count() or 1)
    if jobs <= 1 or len(specs) < 4:
        rows = [_report_row(sp) for sp in specs]
    else:
        with multiprocessing.Pool(jobs) as pool:
            rows = pool.map(_report_row, specs, chunksize=4)
    return {w: (h, bad) for w, h, bad in rows}
