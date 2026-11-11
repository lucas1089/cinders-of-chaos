#!/usr/bin/env python3
"""Take the vendor's baked ground shadow out of the wings' sprites, in place (pair 64 candidate, ROADMAP O508).

python3 -I clean_wing_shadows.py fit     DAT SPR [--out pair_fixes/wing_shadows.csv] [--check]
python3 -I clean_wing_shadows.py measure DAT SPR [--out measure.csv]
python3 -I clean_wing_shadows.py build   DAT SPR --out-dir OUT [--table T] [--overrides O] [--dry-run]
python3 -I clean_wing_shadows.py check-clean DAT SPR [--table T] [--overrides O]

Why. Most pack wings carry a soft round shadow INSIDE their sprites: a core of one or two dark levels and one or two
rings, about 24 px right of and 30 px below the wings' centre. The character already has its own shadow (base patch
0155), so a second dark blob sat to the lower right of every winged character and moved with the wing shift (base patch
0193, O495). A plain per-pixel mask (alpha under 200 and luminance under 150, gen_wing_centres.py shadow_mask) is not
enough: it eats the dark soft edges of wings that have no shadow at all (940, 2227: the whole outline), the dark
translucent parts of wings that have one, and it misses a pale ring (2406: ring luminance 188) and a near opaque core
(alpha 204 to 242 on 2427, 2445, 2451, 2457). So the rule below looks for the blob itself.

What the blob is, measured on pair 63 (client/MANIFEST.md "Pair 64"). It is ONE ground shadow per frame group: the same
exact RGBA at the same place in the north, east, south and west frames of a phase (the wing is what changes with the
direction). It is drawn in a few exact RGBA levels (2 to 20 per wing, alpha 26 to 242) inside a filled ellipse. Its core
does not move between phases; on some wings the rings pulse, and on the vortex and orbit wings (2430, 2475) arms or
dots turn around the core. A wing frame is the shadow with the wing drawn over it, so a shadow pixel is found by
comparing directions, not by a colour test. Nine wings of the old sets (937, 1486, 2141, 2142, 2227 to 2230 ...) have no
shadow at all: the plain mask hits their soft edges.

fit (deterministic, per wing and frame group; pair_fixes/wing_shadows.csv is its output, --check compares):
  1. CONSENSUS, per phase: a pixel where 3 or 4 of the 4 direction frames hold the same RGBA with 0 < alpha < 255.
  2. CORE: the pixels that are consensus in half or more of the phases, in 8-connected components. The largest
     component and the ones nested in it (bounding box centre within 3 px of its centre: the rings and the core of
     one shadow) are the core; the other ones are STATIC wing art (a halo or smoke that looks the same in every
     direction) and are left out of everything below. No component of 64 pixels or more: no shadow, no row.
  3. PALETTE: the RGBA levels that are consensus at 8 or more pixel-phases inside the ZONE, the core's ellipse (its
     bounding box grown by 1 px) grown by 12 px, static art taken out.
  4. ELLIPSE: the bounding box of the palette's consensus pixels in the zone, grown by 1 px, centre (cx, cy), radii
     (rx, ry), canvas px of the group's frame (w x h tiles of 32 px, tile (0, 0) at the bottom right). The zone then grows
     by 12 px around the new ellipse, up to 4 times and never beyond 30 px past the core's ellipse, so that rings and
     arms that move with the phase are inside. The radii are scaled until every pixel centre of the support is inside.
  The row: wing, group, cx, cy, rx, ry, palette (r.g.b.a levels joined by /), phases, support (palette consensus pixels
  of the union over the phases), static (pixels of static wing art kept out), mask_kept (pixels the plain mask takes
  over all frames of the group that this rule keeps: what the plain mask would eat of the wing).
rule (build): in every frame of the group a pixel is SHADOW when (a) its alpha is under 255, (b) its RGBA is a palette
  level, (c) its centre is inside the ellipse, (d) the same level is a consensus level at that place in at least one
  phase of the group and is not static art (the same pixel in other directions: a wing pixel is not). Shadow pixels
  become transparent (0, 0, 0, 0). Nothing else changes. A pixel of alpha 255 cannot change, a pixel that is not exactly
  a palette level cannot change, a pixel outside the ellipse cannot change, a pixel no other direction shows cannot
  change. Where the wing lies over the blob its own pixels are not the blob's level and stay; the low-alpha pixels of the
  blob around them go.
Limits (the run prints the numbers; client/MANIFEST.md "Pair 64" has them for pair 63):
  (a) a wing edge blended over the blob has a value that is neither the wing's nor the blob's: it stays, the blob level
      under it stays with it; (b) a shadow pixel that two or more other directions cover with wing in every phase has no
      consensus: it stays (a few specks beside the wing's root); (c) wing art that uses the same levels as the shadow
      and looks the same in every direction and is not static in all phases (2457's smoke) is not told apart: the
      override file gives such a wing a tighter ellipse, or skips it, with a reason; (d) a wing with no consensus has no
      row and stays as it is (`measure` lists them and the plain mask's hits on them); (e) the fit reads pair 63's
      frames, a new pair needs `fit` again, `fit --check` says so.
build: the candidate pair. The dat is copied byte for byte (no sprite id and no thing changes). The spr keeps its count,
  its ids and the order of its records: a changed record is rewritten where it is (a tile that is empty after the
  cleaning loses its record: offset 0, the client draws nothing there), the offset table is recomputed, nothing else
  moves. A sprite is rewritten only when every thing that uses it is a wing, every use of it gives the same cleaned tile,
  and no other sprite id shares its record. A wing with a sprite that fails these is left whole as it was (listed): a
  half cleaned blob would look worse than a whole one. Deterministic: the same pair and table give the same bytes.
  Verification (always): the output parses, the dat is identical, every unchanged record is byte identical (all of
  them), every rewritten sprite decodes to the cleaned tile, every changed pixel of every wing frame is a shadow pixel
  of the rule, no changed pixel has alpha 255, no frame of a wing left whole changed.
check-clean (the CI check on the live pair once it is the cleaned one 64; `fit --check` only holds on pair 63, the pair the table was
  fitted on): every cleaned wing group has no core any more (no pixel that 3 of 4 directions agree on in half of the phases) and at most
  CLEAN_LEFT_MAX consensus pixels of its palette inside its ellipse over all frames (what stays, limit (b) and glow of the same level);
  every group the override file skips has exactly the blob the table holds (it is untouched); no other wing group has a blob.
Sprite art is only read; nothing is drawn, nothing is fetched, no pixel is invented.
"""
import argparse
import csv
import os
import struct
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_wing_centres as gwc  # noqa: E402
import import_art_things as iat  # noqa: E402
from datspr import Dat, Spr  # noqa: E402

TABLE = os.path.join(HERE, 'pair_fixes', 'wing_shadows.csv')
OVERRIDES = os.path.join(HERE, 'pair_fixes', 'wing_shadow_overrides.csv')
TABLE_COLS = ['wing', 'group', 'cx', 'cy', 'rx', 'ry', 'palette', 'phases', 'support', 'static', 'mask_kept']
ALPHA_MAX = 255         # a shadow level has an alpha under this: a pixel of alpha 255 is a wing pixel, never shadow
CONSENSUS = 3           # of the 4 directions hold the same RGBA
PERSIST = 0.5           # a core pixel is a consensus pixel in this share of the phases
LEVEL_MIN = 8           # a level seen at this many pixel-phases in the zone joins the palette
MIN_CORE = 64           # pixels of the core component, else no shadow
GROW = 1.0              # the ellipse is the bounding box grown by this
ZONE_GROW = 12.0        # moving rings and arms of the shadow reach this far past what was found so far,
ZONE_STEPS = 4          # in this many steps,
ZONE_MAX = 30.0         # and never more than this past the core's ellipse
CLEAN_LEFT_MAX = 1000   # check-clean: consensus palette pixels that may stay inside the ellipse of a cleaned group
DIRS = 4


# ------------------------------------------------------------------------------------------------ frames
def usable(g):
    """a wing frame group the rule reads: 4 directions, one layer, one addon pattern, one mount pattern"""
    w, h, exact, layers, px, py, pz, ph, sprites = g[:9]
    return px == DIRS and layers == 1 and py == 1 and pz == 1 and ph >= 1


def sidx(g, d, p, ww, hh):
    w, h, _e, layers, px, py, pz, ph = g[:8]
    return ((((p * pz) * py * px + d) * layers) * h + hh) * w + ww


def frames_of(g, spr):
    """{(direction, phase): RGBA canvas (h * 32, w * 32, 4)}; tile (ww, hh) sits at the canvas' bottom right"""
    w, h, ph = g[0], g[1], g[7]
    out = {}
    for d in range(DIRS):
        for p in range(ph):
            img = np.zeros((h * 32, w * 32, 4), np.uint8)
            for hh in range(h):
                for ww in range(w):
                    a = spr.sprite(g[8][sidx(g, d, p, ww, hh)])
                    if a is not None:
                        img[(h - 1 - hh) * 32:(h - hh) * 32, (w - 1 - ww) * 32:(w - ww) * 32] = a
            out[(d, p)] = img
    return out


def packed(img):
    """RGBA canvas -> uint32 per pixel (r | g << 8 | b << 16 | a << 24)"""
    return np.ascontiguousarray(img).view('<u4')[..., 0]


def pack_level(r, g, b, a):
    return int(r) | int(g) << 8 | int(b) << 16 | int(a) << 24


def level_str(u):
    return '%d.%d.%d.%d' % (u & 255, u >> 8 & 255, u >> 16 & 255, u >> 24)


def level_of(s):
    r, g, b, a = (int(v) for v in s.split('.'))
    return pack_level(r, g, b, a)


# ------------------------------------------------------------------------------------------------ the blob
def consensus(frames, ph):
    """per phase the pixels where 3 or 4 of the 4 directions hold the same RGBA with 0 < alpha < 255:
    [(bool mask, uint32 value per pixel)]"""
    out = []
    for p in range(ph):
        u = np.stack([packed(frames[(d, p)]) for d in range(DIRS)])
        a = u >> 24
        ok = (a > 0) & (a < ALPHA_MAX)
        votes = np.zeros(u.shape, np.int32)
        for k in range(DIRS):
            votes[k] = (u == u[k]).sum(axis=0) * ok[k]
        best = votes.argmax(axis=0)
        top = np.take_along_axis(votes, best[None], 0)[0]
        val = np.take_along_axis(u, best[None], 0)[0]
        out.append((top >= CONSENSUS, val))
    return out


def components(mask):
    """8-connected components of a bool mask: [list of (y, x)], largest first (ties: top left first)"""
    h, w = mask.shape
    seen = np.zeros(mask.shape, bool)
    comps = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        stack, pix = [(int(y0), int(x0))], []
        while stack:
            y, x = stack.pop()
            pix.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
        comps.append(sorted(pix))
    comps.sort(key=lambda c: (-len(c), c[0]))
    return comps


def ellipse_mask(shape, cx, cy, rx, ry):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    return ((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1.0


class Analysis:
    """what the directions agree on in one frame group: cons (per phase mask, value), core and static masks"""

    def __init__(self, frames, ph):
        self.cons = consensus(frames, ph)
        self.shape = self.cons[0][0].shape
        persist = np.zeros(self.shape, np.int32)
        for hit, _val in self.cons:
            persist += hit
        stable = persist >= max(1, int(np.ceil(PERSIST * ph)))
        comps = components(stable)
        self.core = np.zeros(self.shape, bool)
        self.static = np.zeros(self.shape, bool)
        self.ok = bool(comps) and len(comps[0]) >= MIN_CORE
        if self.ok:
            ys, xs = zip(*comps[0])
            c0 = ((min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0)
            for comp in comps:      # rings and cores of the same shadow are nested: the same centre within 3 px
                ys, xs = zip(*comp)
                if len(comp) >= 4 and abs((min(xs) + max(xs)) / 2.0 - c0[0]) <= 3 and abs((min(ys) + max(ys)) / 2.0 - c0[1]) <= 3:
                    self.core[list(ys), list(xs)] = True
            self.static = stable & ~self.core       # wing art that looks the same in every direction and phase


def box_ellipse(xs, ys):
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    return (x0 + x1 + 1) / 2.0, (y0 + y1 + 1) / 2.0, (x1 - x0 + 1) / 2.0 + GROW, (y1 - y0 + 1) / 2.0 + GROW


def fit_group(an):
    """the blob of one frame group from its Analysis: dict(cx, cy, rx, ry, palette, support, static) or None"""
    if not an.ok:
        return None
    shape, cons, static = an.shape, an.cons, an.static
    ys, xs = np.nonzero(an.core)
    cx0, cy0, rx0, ry0 = box_ellipse(xs, ys)
    limit = ellipse_mask(shape, cx0, cy0, rx0 + ZONE_MAX, ry0 + ZONE_MAX) & ~static
    zone = ellipse_mask(shape, cx0, cy0, rx0 + ZONE_GROW, ry0 + ZONE_GROW) & ~static
    count = Counter()
    for hit, val in cons:
        v, c = np.unique(val[hit & zone], return_counts=True)
        count.update(dict(zip(v.tolist(), c.tolist())))
    palette = sorted(v for v, c in count.items() if c >= LEVEL_MIN)
    if not palette:
        return None
    pal = np.array(palette, np.uint32)

    def support(z):
        sup = np.zeros(shape, bool)
        for hit, val in cons:
            sup |= hit & z & np.isin(val, pal)
        ys, xs = np.nonzero(sup)
        return (sup, xs, ys) + box_ellipse(xs, ys)

    for _ in range(ZONE_STEPS):
        sup, xs, ys, cx, cy, rx, ry = support(zone)
        grown = ellipse_mask(shape, cx, cy, rx + ZONE_GROW, ry + ZONE_GROW) & limit
        if not (grown & ~zone).any():
            break
        zone = zone | grown
    sup, xs, ys, cx, cy, rx, ry = support(zone)
    # a support that is not a clean ellipse (a vortex arm, a corner): scale the radii until every pixel centre is inside
    k = np.sqrt((((xs + 0.5 - cx) / rx) ** 2 + ((ys + 0.5 - cy) / ry) ** 2).max())
    if k > 1.0:
        rx, ry = rx * k + 0.05, ry * k + 0.05
    rx, ry = round(rx * 2) / 2.0, round(ry * 2) / 2.0
    while (sup & ~ellipse_mask(shape, cx, cy, rx, ry)).any():
        rx, ry = rx + 0.5, ry + 0.5
    return dict(cx=cx, cy=cy, rx=rx, ry=ry, palette=palette, support=int(sup.sum()), static=int(static.sum()))


def with_template(spec, an):
    """spec plus `tmpl`: {level: bool mask of the places where that level is a consensus level in some phase, static art out}"""
    tm = {v: np.zeros(an.shape, bool) for v in spec['palette']}
    for hit, val in an.cons:
        for v in tm:
            tm[v] |= hit & (val == v)
    for v in tm:
        tm[v] &= ~an.static
    return dict(spec, tmpl=tm)


def shadow_pixels(img, spec):
    """bool mask of the shadow pixels of one frame under a spec (cx, cy, rx, ry, palette, tmpl)"""
    u = packed(img)
    a = u >> 24
    inside = ellipse_mask(u.shape, spec['cx'], spec['cy'], spec['rx'], spec['ry'])
    m = np.zeros(u.shape, bool)
    for v, t in spec['tmpl'].items():
        m |= (u == v) & t
    return m & (a > 0) & (a < ALPHA_MAX) & inside


def clean_frame(img, spec):
    """(cleaned frame, removed mask)"""
    m = shadow_pixels(img, spec)
    out = img.copy()
    out[m] = 0
    return out, m


# ------------------------------------------------------------------------------------------------ the table
def wing_groups(dat):
    """[(wing id, group index, group tuple)] of the wings of the O495 list, in id order"""
    out = []
    for i in gwc.wing_ids():
        if 1 <= i <= len(dat.outfits):
            for gi, g in enumerate(dat.outfits[i - 1].groups):
                out.append((i, gi, g))
    return out


def num(v):
    return str(int(v)) if v == int(v) else '%.1f' % v


def mask_kept(frames, spec):
    """pixels the O495 shadow mask takes that the rule keeps: what the plain mask would eat of the wing"""
    return sum(int((gwc.shadow_mask(f) & ~shadow_pixels(f, spec)).sum()) for f in frames.values())


def spec_of_row(r):
    return dict(cx=float(r['cx']), cy=float(r['cy']), rx=float(r['rx']), ry=float(r['ry']),
                palette=[level_of(s) for s in r['palette'].split('/')])


def fit_table(dat, spr):
    """([table rows], [(wing, group, why no row)])"""
    rows, none = [], []
    for i, gi, g in wing_groups(dat):
        if not usable(g):
            none.append((i, gi, 'not 4 directions x 1 layer'))
            continue
        frames = frames_of(g, spr)
        an = Analysis(frames, g[7])
        fit = fit_group(an)
        if fit is None:
            none.append((i, gi, 'no shadow found'))
            continue
        kept = mask_kept(frames, with_template(fit, an))
        rows.append({'wing': i, 'group': gi, 'cx': num(fit['cx']), 'cy': num(fit['cy']), 'rx': num(fit['rx']),
                     'ry': num(fit['ry']), 'palette': '/'.join(level_str(v) for v in fit['palette']),
                     'phases': g[7], 'support': fit['support'], 'static': fit['static'], 'mask_kept': kept})
    return rows, none


def write_table(path, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, TABLE_COLS, lineterminator='\n')
        w.writeheader()
        w.writerows(rows)


def read_table(path):
    with open(path, newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        r['wing'], r['group'] = int(r['wing']), int(r['group'])
    return rows


def read_overrides(path):
    """{(wing, group): row}: action skip, or region with args cx=..;cy=..;rx=..;ry=.. ; a reason is required"""
    if not path or not os.path.exists(path):
        return {}
    out = {}
    with open(path, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if r['action'] not in ('skip', 'region') or not r['reason'].strip():
                raise SystemExit('%s: action skip or region, and a reason, for every row: %r' % (path, r))
            out[(int(r['wing']), int(r['group']))] = r
    return out


def apply_override(spec, o):
    """the spec under an override row; None for a skip"""
    if o['action'] == 'skip':
        return None
    kv = dict(p.split('=') for p in o['args'].split(';'))
    s = dict(spec)
    for k in ('cx', 'cy', 'rx', 'ry'):
        if k in kv:
            s[k] = float(kv[k])
    return s


def specs_of(rows, overrides):
    """{(wing, group): spec} of the groups that get cleaned (skips left out)"""
    out = {}
    for r in rows:
        s = spec_of_row(r)
        o = overrides.get((r['wing'], r['group']))
        if o is not None:
            s = apply_override(s, o)
        if s is not None:
            out[(r['wing'], r['group'])] = s
    return out


# ------------------------------------------------------------------------------------------------ plan and build
def plan(dat, spr, rows, overrides):
    """what changes, sprite by sprite.
    Returns (changed {sid: new tile}, left {(wing, group): why it stays whole}, stats {(wing, group): dict}, specs, why)"""
    specs = specs_of(rows, overrides)
    wing_things = {('outfit', i) for i in gwc.wing_ids()}
    users = defaultdict(set)
    for cat, lst in (('item', dat.items), ('outfit', dat.outfits), ('effect', dat.effects), ('missile', dat.missiles)):
        for t in lst:
            for g in t.groups:
                for s in set(g[8]):
                    if s:
                        users[int(s)].add((cat, t.id))
    offs = np.asarray(spr.offs)
    by_off = defaultdict(list)
    for sid in np.nonzero(offs)[0]:
        by_off[int(offs[sid])].append(int(sid) + 1)

    results = defaultdict(lambda: defaultdict(set))    # sid -> (wing, group) -> {resulting tile bytes}
    stats = {}
    for i, gi, g in wing_groups(dat):
        if not usable(g):
            continue
        spec = specs.get((i, gi))
        frames = frames_of(g, spr)
        if spec is not None:
            spec = with_template(spec, Analysis(frames, g[7]))
        removed = changed_frames = 0
        h, w = g[1], g[0]
        for (d, p), img in frames.items():
            if spec is not None:
                out, m = clean_frame(img, spec)
                removed += int(m.sum())
                changed_frames += int(m.any())
            else:
                out = img
            for hh in range(h):
                for ww in range(w):
                    sid = int(g[8][sidx(g, d, p, ww, hh)])
                    if sid:
                        sl = (slice((h - 1 - hh) * 32, (h - hh) * 32), slice((w - 1 - ww) * 32, (w - ww) * 32))
                        results[sid][(i, gi)].add(iat.decoded(np.ascontiguousarray(out[sl])).tobytes())
        stats[(i, gi)] = {'removed': removed, 'frames_changed': changed_frames, 'frames': len(frames)}
    # a sprite is cleanable when all its uses give one tile, only wings use it, and no other id shares its record
    why, changed = {}, {}
    for sid, byw in results.items():
        allt = set().union(*byw.values())
        if len(allt) != 1:
            why[sid] = 'its uses give different tiles'
            continue
        old = spr.sprite(sid)
        old = np.zeros((32, 32, 4), np.uint8) if old is None else iat.decoded(old)
        (tb,) = allt
        if tb == old.tobytes():
            continue
        bad = users[sid] - wing_things
        if bad:
            why[sid] = 'shared with ' + ', '.join('%s %d' % u for u in sorted(bad))
        elif len(by_off.get(int(offs[sid - 1]), [])) > 1:
            why[sid] = 'its record is shared by sprite ids %s' % by_off[int(offs[sid - 1])]
        else:
            changed[sid] = np.frombuffer(tb, np.uint8).reshape(32, 32, 4)
    # a wing group with a blocked sprite stays whole; a sprite it shared with another cleaned wing blocks that one too
    left = {}
    wing_sids = {k: {int(s) for s in dat.outfits[k[0] - 1].groups[k[1]][8] if s} for k in stats}
    blocked = set(why)
    while True:
        moved = False
        for k, sids in wing_sids.items():
            if k in left or k not in specs:
                continue
            hit = sids & blocked
            if hit:
                sid = min(hit)
                left[k] = 'sprite %d: %s' % (sid, why[sid])
                for s in sids & set(changed):
                    changed.pop(s)
                    why.setdefault(s, 'wing %d is left whole' % k[0])
                    blocked.add(s)
                moved = True
        if not moved:
            break
    return changed, left, stats, specs, why


def write_spr_in_place(path, spr, changed):
    """the spr with the records of `changed` {sid: tile} rewritten where they are; a tile with no pixel loses its record.
    Returns (bytes written, records dropped)."""
    m = spr.m
    count = spr.count
    offs = np.asarray(spr.offs).astype(np.int64)
    new = {sid: iat.encode_sprite(tile) for sid, tile in changed.items()}
    order = sorted(changed, key=lambda s: int(offs[s - 1]))
    old_len = {sid: 5 + struct.unpack_from('<H', m, int(offs[sid - 1]) + 3)[0] for sid in order}
    pos_old = np.array([int(offs[s - 1]) for s in order], np.int64)
    deltas = np.array([(len(new[s]) if new[s] is not None else 0) - old_len[s] for s in order], np.int64)
    cum = np.concatenate([[0], np.cumsum(deltas)])
    table = offs.copy()
    nz = table > 0
    table[nz] += cum[np.searchsorted(pos_old, table[nz], side='left')]     # changed records before this one
    for sid in order:
        if new[sid] is None:
            table[sid - 1] = 0
    dropped = sum(1 for s in order if new[s] is None)
    with open(path, 'wb') as f:
        f.write(struct.pack('<II', spr.signature, count))
        f.write(table.astype('<u4').tobytes())
        pos = 8 + 4 * count
        for sid in order:
            o = int(offs[sid - 1])
            while pos < o:
                n = min(1 << 24, o - pos)
                f.write(m[pos:pos + n])
                pos += n
            if new[sid] is not None:
                f.write(new[sid])
            pos = o + old_len[sid]
        while pos < len(m):
            n = min(1 << 24, len(m) - pos)
            f.write(m[pos:pos + n])
            pos += n
    return os.path.getsize(path), dropped


def build(a, log=print):
    dat, spr = Dat(a.dat), Spr(a.spr)
    if not (spr.u32count and spr.alpha):
        raise SystemExit('not an alpha u32 spr')
    rows = read_table(a.table)
    overrides = read_overrides(a.overrides)
    changed, left, stats, specs, why = plan(dat, spr, rows, overrides)
    removed = sum(stats[k]['removed'] for k in specs if k not in left)
    log('wing groups in the table: %d, overrides: %d, left whole: %d' % (len(rows), len(overrides), len(left)))
    for k, w in sorted(left.items()):
        log('  left whole: wing %d group %d: %s' % (k[0], k[1], w))
    empty = sum(1 for t in changed.values() if not (t[..., 3] > 0).any())
    log('sprites to rewrite: %d (%d empty afterwards), pixels removed over all wing frames: %d' % (len(changed), empty, removed))
    if a.dry_run:
        log('dry run: nothing written')
        return changed, left, stats, specs, why
    if os.path.abspath(os.path.dirname(a.dat)) == os.path.abspath(a.out_dir):
        raise SystemExit('out-dir must differ from the input dir')
    st = os.statvfs(os.path.dirname(os.path.abspath(a.out_dir)) or '.')
    if st.f_bavail * st.f_frsize < len(spr.m) + (1 << 30):
        raise SystemExit('not enough disk space for the output spr (%s bytes, 1 GB left over)' % f'{len(spr.m):,}')
    os.makedirs(a.out_dir, exist_ok=True)
    dat_path, spr_path = os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr')
    with open(a.dat, 'rb') as s, open(dat_path, 'wb') as d:
        d.write(s.read())
    size, dropped = write_spr_in_place(spr_path, spr, changed)
    log('wrote %s, %s (%s bytes, %d records dropped)' % (dat_path, spr_path, f'{size:,}', dropped))
    verify(a, dat, spr, changed, specs, left, spr_path, log)
    return changed, left, stats, specs, why


def verify(a, dat, spr, changed, specs, left, spr_path, log):
    ns = Spr(spr_path)
    nd = Dat(os.path.join(os.path.dirname(spr_path), 'Tibia.dat'))
    assert ns.count == spr.count and ns.signature == spr.signature
    assert nd.data == dat.data, 'dat differs'
    for sid in range(1, spr.count + 1):
        if sid in changed:
            continue
        x, y = int(spr.offs[sid - 1]), int(ns.offs[sid - 1])
        assert (x == 0) == (y == 0), ('slot emptiness changed', sid)
        if x:
            n = 5 + struct.unpack_from('<H', spr.m, x + 3)[0]
            assert spr.m[x:x + n] == ns.m[y:y + n], ('record bytes changed', sid)
    for sid, tile in changed.items():
        got, want = ns.sprite(sid), iat.decoded(tile)
        if not (want[..., 3] > 0).any():
            assert got is None, ('an empty tile must have no record', sid)
        else:
            assert got is not None and (got == want).all(), ('rewritten sprite differs from the cleaned tile', sid)
    n_px = 0
    for i, gi, g in wing_groups(dat):
        if not usable(g):
            continue
        fo, fn = frames_of(g, spr), frames_of(nd.outfits[i - 1].groups[gi], ns)
        spec = specs.get((i, gi))
        if spec is not None:
            spec = with_template(spec, Analysis(fo, g[7]))
        for k, img in fo.items():
            diff = (img != fn[k]).any(axis=2)
            if not diff.any():
                continue
            assert spec is not None and (i, gi) not in left, ('a wing left whole changed', i, gi)
            assert (diff <= shadow_pixels(img, spec)).all(), ('a changed pixel is not a shadow pixel', i, gi, k)
            assert (img[diff][:, 3] < ALPHA_MAX).all(), ('a pixel of alpha 255 changed', i, gi, k)
            n_px += int(diff.sum())
    log('verified: dat identical, %d sprite records rewritten, every other record byte identical, every changed wing '
        'pixel (%d) is a shadow pixel of the rule, none with alpha 255' % (len(changed), n_px))


def check_clean(dat, spr, rows, overrides, log=print):
    """the cleaned pair holds no more blob for the cleaned groups, the skipped ones are untouched. Returns the problems"""
    table = {(r['wing'], r['group']): r for r in rows}
    bad = []
    for i, gi, g in wing_groups(dat):
        if not usable(g):
            continue
        frames = frames_of(g, spr)
        an = Analysis(frames, g[7])
        row = table.get((i, gi))
        if row is None:
            if fit_group(an) is not None:
                bad.append('wing %d group %d has a blob but no table row' % (i, gi))
            continue
        if (i, gi) in overrides and overrides[(i, gi)]['action'] == 'skip':
            fit = fit_group(an)
            same = fit is not None and all(row[k] == num(fit[k]) for k in ('cx', 'cy', 'rx', 'ry')) and \
                row['palette'] == '/'.join(level_str(v) for v in fit['palette'])
            if not same:
                bad.append('wing %d group %d is skipped but its blob is not the table\'s' % (i, gi))
            continue
        sp = spec_of_row(row)
        ell = ellipse_mask(an.shape, sp['cx'], sp['cy'], sp['rx'], sp['ry'])
        pal = np.array(sp['palette'], np.uint32)
        left = sum(int((hit & ell & np.isin(val, pal)).sum()) for hit, val in an.cons)
        if an.ok:
            bad.append('wing %d group %d still has a core' % (i, gi))
        if left > CLEAN_LEFT_MAX:
            bad.append('wing %d group %d: %d consensus palette pixels in the ellipse (limit %d)' % (i, gi, left, CLEAN_LEFT_MAX))
    return bad


# ------------------------------------------------------------------------------------------------ measure
def measure(dat, spr, rows=None, overrides=None):
    """per wing group: frames, sprites, the plain mask's hits, the fitted blob, how much of the wing the plain mask
    would eat, how far the blob and the wing overlap. Returns [dict]"""
    table = {(r['wing'], r['group']): r for r in (rows or [])}
    out = []
    for i, gi, g in wing_groups(dat):
        w, h = g[0], g[1]
        r = {'wing': i, 'group': gi, 'tiles': '%dx%d' % (w, h), 'phases': g[7]}
        if not usable(g):
            r['class'] = 'unreadable'
            out.append(r)
            continue
        frames = frames_of(g, spr)
        n = len(frames)
        masked = sum(int(gwc.shadow_mask(f).sum()) for f in frames.values())
        r.update({'frames': n, 'sprites': len({int(s) for s in g[8] if s}),
                  'mask_px': masked, 'mask_frames': sum(1 for f in frames.values() if gwc.shadow_mask(f).any())})
        an = Analysis(frames, g[7])
        fit = fit_group(an)
        if fit is None:
            r.update({'class': 'no shadow', 'removed_px': 0, 'mask_kept_px': masked, 'mask_kept_per_frame': round(masked / n, 1)})
        else:
            spec = with_template(fit, an)
            rem = kept = overlap = 0
            for f in frames.values():
                m = shadow_pixels(f, spec)
                rem += int(m.sum())
                kept += int((gwc.shadow_mask(f) & ~m).sum())
                overlap += int(((f[..., 3] == 255) & ellipse_mask(m.shape, fit['cx'], fit['cy'], fit['rx'], fit['ry'])).sum())
            area = np.pi * fit['rx'] * fit['ry']
            r.update({'cx': num(fit['cx']), 'cy': num(fit['cy']), 'rx': num(fit['rx']), 'ry': num(fit['ry']),
                      'levels': len(fit['palette']), 'removed_px': rem, 'mask_kept_px': kept,
                      'mask_kept_per_frame': round(kept / n, 1), 'wing_in_blob_share': round(overlap / n / area, 3)})
        out.append(r)
    return out


# ------------------------------------------------------------------------------------------------ main
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    f = sub.add_parser('fit')
    f.add_argument('dat')
    f.add_argument('spr')
    f.add_argument('--out', default=TABLE)
    f.add_argument('--check', action='store_true')
    m = sub.add_parser('measure')
    m.add_argument('dat')
    m.add_argument('spr')
    m.add_argument('--out')
    b = sub.add_parser('build')
    b.add_argument('dat')
    b.add_argument('spr')
    b.add_argument('--out-dir', required=True)
    b.add_argument('--table', default=TABLE)
    b.add_argument('--overrides', default=OVERRIDES)
    b.add_argument('--dry-run', action='store_true')
    c = sub.add_parser('check-clean')
    c.add_argument('dat')
    c.add_argument('spr')
    c.add_argument('--table', default=TABLE)
    c.add_argument('--overrides', default=OVERRIDES)
    a = ap.parse_args(argv)
    if a.cmd == 'fit':
        rows, none = fit_table(Dat(a.dat), Spr(a.spr))
        if a.check:
            have = read_table(a.out) if os.path.exists(a.out) else []
            norm = lambda rs: [{k: str(v) for k, v in r.items()} for r in rs]  # noqa: E731
            if norm(have) != norm(rows):
                print('%s is not what the pair gives: run %s fit' % (a.out, os.path.basename(__file__)))
                return 1
            print('wing shadow table up to date (%d wing groups with a blob, %d without)' % (len(rows), len(none)))
            return 0
        write_table(a.out, rows)
        print('wrote %s (%d wing groups with a blob, %d without)' % (a.out, len(rows), len(none)))
        return 0
    if a.cmd == 'measure':
        rows = measure(Dat(a.dat), Spr(a.spr))
        if a.out:
            cols = []
            for r in rows:
                cols += [k for k in r if k not in cols]
            with open(a.out, 'w', newline='', encoding='utf-8') as fh:
                w = csv.DictWriter(fh, cols, lineterminator='\n')
                w.writeheader()
                w.writerows(rows)
        print('measured %d wing groups' % len(rows))
        return 0
    if a.cmd == 'check-clean':
        rows, ov = read_table(a.table), read_overrides(a.overrides)
        bad = check_clean(Dat(a.dat), Spr(a.spr), rows, ov)
        for b in bad:
            print(b)
        if bad:
            return 1
        print('wing shadows are cleaned (%d wing groups, %d skipped, none with a blob left)' % (len(rows), sum(1 for o in ov.values() if o['action'] == 'skip')))
        return 0
    build(a)
    return 0


if __name__ == '__main__':
    sys.exit(main())
