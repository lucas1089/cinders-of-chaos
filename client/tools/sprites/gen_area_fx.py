#!/usr/bin/env python3
"""An area burst, beams, markers and a status effect of the purchased effect packs of pair 36 (O607, O609, O613; joins
client pair 73).

    python3 -I gen_area_fx.py build DAT SPR OUT_DIR --src DIR [--src DIR ...]   # DIR: the unzipped packs (any sub folders;
                                                         # only the picked sheets and the packs' json tables are needed)
    python3 -I gen_area_fx.py build DAT SPR OUT_DIR --src DIR --write   # also writes art_import/area_fx.csv and .sums
    python3 -I gen_area_fx.py check                      # CI, no art, no pair: table, sums, ids file, tags, pair 51 lists
    python3 -I gen_area_fx.py ids [--check]              # server/data/lib/chaos_area_fx_ids.lua, spells/area_fx_catalog.csv,
                                                         # the tags of spell_fx_elements.csv
    python3 -I gen_area_fx.py live DAT SPR [--long]      # the pair holds every row at its id, pixel for pixel
                                                         # (--long: only the long beams 5301..)

The owner approved the review O604: the beam spells draw balls on a line, and the pack has markers we lack. O607 also
swapped five area bursts of ours for pack ones; the owner saw them and kept ours (O613, 2026-11-17: "the new area bursts
are too weak"), so four of those bursts and the blood stream beam left the table, the clock face stays for two arcane
spells, and the pack's gravity press came in for a slowed creature. 51 effects in three kinds of rows:
  refill  30 effects that pair 36 imported at their ids and pair 51 blanked as unused (prune_pair.py): three beams of
          eight headings each, five markers, one status effect. Each is put back AT ITS PAIR 36 ID, in the size, the send
          offset and the phase count of its pair 36 spec (art_import/pack36_*.csv), so the names and offsets of
          server/data/lib/chaos_pack36_fx_ids.lua stay true. Their rows moved from pair51_removed.csv to pair51_keep.csv.
  new     1 area burst of a set pair 36 did not have, appended at 5300. The input pair may end anywhere from 4742
          to 5299: every id from its last effect + 1 up to 5299 is padded with a blank effect (one 1x1 frame, sprite 0,
          the bytes of a pair 51 blank), so this step runs LAST of the effect steps of pair 73, after the steps that own
          4743..5142 (O596, gen_spell_vfx.py) and 5190..5236 (O606, gen_gap_fx.py; then 5237..5299 are padded here).
          It never touches an id below 5300 that has art.
  long    20 beams at 5301..5320 (O609, the owner: "the larger beams are in segments"). The pack's beam art covers 3 tiles
          on a straight heading and less on a diagonal, and the beam spells hit a longer line, so O607 drew
          copies end to end: a start flare and a tip in the middle of every line. A long row is ONE effect for one beam,
          heading and line length (LONG): the one start, the body made longer by whole periods of itself, the one tip at
          the true end of the line. See "Long beams" below. The input pair is the one of the two kinds above (4742..5299
          effects: all three kinds are built) or a pair that ends at 5300 (only the long beams are appended; only the
          beam sheets are needed).

The cut is the one the pair 36 tools use now (gen_pack36_fx.load: the 32 px sheets 1:1, alpha cut hard at 0.5; the 64 px
set halved, the same cut; no dither mesh): O604's numbers show the hard cut keeps 84% to 106% of the alpha mass of every
pick, so none needs the game size cut of O596. A looping pack effect plays once and its last 3 frames dissolve, as in
pair 36. Placing is the pack's own anchor tile: an area burst is sent at the centre tile of the spell, a beam at the
caster's tile, a marker at the marked tile, a status effect at the creature's tile.

The art is purchased (docs/CREDITS.md: use and change allowed, no resale or redistribution, never machine-learning data),
so no picture is in the repository. Committed: this script, art_import/area_fx.csv (one row per effect: the name, a
neutral set key, src = the first 12 hex of the sha256 of the sheet file, the result) and art_import/area_fx.sums (the
digest of every strip). The sheets are read by this local script only: never sent to a web or AI service.

Needs numpy and Pillow (the fx venv of CI). Deterministic.
"""
import argparse
import csv
import hashlib
import io
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'area_fx.csv')
SUMS = os.path.join(ART, 'area_fx.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_area_fx_ids.lua')
CATALOG = os.path.join(ROOT, 'server', 'data', 'spells', 'area_fx_catalog.csv')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')
PACK36_LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_pack36_fx_ids.lua')
REMOVED = os.path.join(HERE, 'pair51_removed.csv')
KEEP = os.path.join(HERE, 'pair51_keep.csv')

PAIR = 73
FIRST = 5300                               # the new effects; ids below it are other steps' or padding
MIN_EFFECTS, NEED_MISSILES = 4742, 253     # pair 72 at least; a later step's effects may already be there
BLANK = bytes([0xFF, 1, 1, 1, 1, 1, 1, 1]) + struct.pack('<I', 0)     # a blank effect, as pair 51 writes one
DIRS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']
STEP = {'n': (0, -1), 'ne': (1, -1), 'e': (1, 0), 'se': (1, 1), 's': (0, 1), 'sw': (-1, 1), 'w': (-1, 0), 'nw': (-1, -1)}
ELEMENTS = ('physical', 'fire', 'ice', 'energy', 'earth', 'holy', 'death', 'arcane', 'any')
KEEP_REASON = 'kept since O607 (pair 73): refilled from the pack, sent by data/lib/chaos_area_fx.lua'
FIELDS = ['kind', 'id', 'name', 'role', 'set', 'src', 'dir', 'element', 'len', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'reach',
          'cut', 'note']

# (kind, first id, name, role, set key, src, element, directional, note)
#   set: a neutral key of the pack and its family (the names are in docs/CREDITS.md): a3 the area set pair 36 did not have,
#   v1 the 500 effect set, ui the 64 px interface set
PICKS = [
    ('new', 5300, 'ab_arcane_clock', 'area', 'a3', '8fb10e93aff5', 'arcane', False, 'a clock face of runes, a disc of 7 tiles'),
    ('refill', 3036, 'mega_gravity_press', 'status', 'v1', '11e5c615b9c3', 'any', False, 'a weight that presses down: a slowed creature'),
    ('refill', 3404, 'mega_glacier_breath', 'beam', 'v1', '7778956be1cd', 'ice', True, 'a breath of frost'),
    ('refill', 3492, 'mega_soul_chain', 'beam', 'v1', '406a12a645e7', 'death', True, 'a chain of souls'),
    ('refill', 3508, 'mega_sunbeam_lance', 'beam', 'v1', '3959fb2e44aa', 'holy', True, 'a lance of sunlight'),
    ('refill', 3685, 'mega_util_checkpoint_crystal', 'mark', 'v1', '56953a0c7351', 'any', False, 'a checkpoint crystal'),
    ('refill', 3688, 'mega_util_interact_hand', 'mark', 'v1', 'ceab1f723e41', 'any', False, 'a hand: something to use'),
    ('refill', 3690, 'mega_util_locked_marker', 'mark', 'v1', '1fdc423525e8', 'any', False, 'a lock: the way is shut'),
    ('refill', 4051, 'w_fx_quest_marker', 'mark', 'ui', '695411437e97', 'any', False, 'a gold quest marker'),
    ('refill', 4076, 'w_marker_skull', 'mark', 'ui', '6ec163293be4', 'any', False, 'a skull mark'),
]
PACK36_GROUP = {'v1': 'mega', 'ui': 'ui'}      # set key -> the pair 36 spec that holds a refill's row
# O613: the refills the owner dropped (the two area bursts that stood in for ours, the blood stream of Eclipse Edge): blank
# again as in pair 51, back on pair51_removed.csv, and their tags leave spell_fx_elements.csv (name prefixes)
RETIRED = ('area_whiteout', 'area_radiant_repulse', 'mega_blood_siphon')

# O609: a line spell whose line is not the length of the beam's own art gets ONE effect of that length per heading:
# (beam, line length in tiles). The lengths are the `length` of the spells of C.beams in server/data/lib/chaos_area_fx.lua
# (attack_kit_config.lua; server/tests/area_fx_test.lua holds the two together).
LONG = [('mega_soul_chain', 6), ('mega_sunbeam_lance', 3), ('mega_sunbeam_lance', 8)]
NATURAL = 3                  # tiles the pack's own art covers on a straight heading (held by the build, both beams)
STRAIGHT = ('n', 'e', 's', 'w')
# px along the axis that are not body: the start flare and the tip (measured, O609: the 1 px profile of the heading e)
CAPS = {'mega_soul_chain': (14, 14), 'mega_sunbeam_lance': (30, 14)}
WAVY = ('mega_soul_chain',)  # the body sways (its middle line jumps 2 to 6 px at a plain seam): bent
SLAB = 6                     # px each side of a seam that the seam error compares
SEAM_MAX = 0.75              # the worst seam error a long beam may have (0: the art continues exactly, 1: nothing matches)
VIEW = (8, 7)                # a player sees a tile up to 9 east and 7 south of its own (the engine's view): the far tile of
                             # a beam's canvas stays inside it, so the caster always gets its own beam; art past it is cut.
                             # East is held one tile short: the few px of a tip in a ninth tile would cost every viewer
                             # one tile behind the caster the whole beam
JUMP_MAX = 2.0               # px the middle line of a wavy beam may still step at a seam after the bend, any frame
LONG_TILES = 10              # the largest canvas side of a long beam (the caster's tile, 8 tiles, a tip that spills)


def digest(a):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def pieces():
    """the rows of PICKS, a directional one as its eight headings: dicts with the static fields"""
    out = []
    for kind, first, name, role, sk, src, element, directional, note in PICKS:
        for i, d in enumerate(DIRS if directional else ['']):
            out.append(dict(kind=kind, id=first + i, name=name + ('_' + d if d else ''), role=role, set=sk, src=src, dir=d,
                            element=element, len='', note=note + (', towards ' + d if d else '')))
    nid = FIRST + sum(p[0] == 'new' for p in PICKS)
    by_name = {p[2]: p for p in PICKS}
    for base, ln in LONG:
        _, _, name, role, sk, src, element, _, note = by_name[base]
        for d in DIRS:
            if ln == NATURAL and d in STRAIGHT:
                continue                              # the pack's own art is that long: the refilled id is the variant
            out.append(dict(kind='long', id=nid, name='%s_l%d_%s' % (base, ln, d), role=role, set=sk, src=src, dir=d,
                            element=element, len=ln, note='%s, %d tiles in one piece, towards %s' % (note, ln, d)))
            nid += 1
    return out


def long_name(base, ln, d):
    """the effect that draws `base` over a line of `ln` tiles towards `d`"""
    return base + '_' + d if ln == NATURAL and d in STRAIGHT else '%s_l%d_%s' % (base, ln, d)


def pack36_rows():
    """{name: row} of the pair 36 specs the refills come from (size, phases, ms, send offset)"""
    rows = {}
    for g in sorted(set(PACK36_GROUP.values())):
        with open(os.path.join(ART, 'pack36_%s.csv' % g), newline='') as fh:
            for r in csv.DictReader(fh):
                rows[r['name']] = r
    return rows


def pack36_ids():
    """{name: (id, dx, dy)} of server/data/lib/chaos_pack36_fx_ids.lua"""
    out = {}
    for line in open(PACK36_LUA, encoding='utf-8'):
        if line.startswith('ChaosVfx.') and '{id = ' in line:
            name = line[len('ChaosVfx.'):].split(' ')[0]
            out[name] = (int(line.split('{id = ')[1].split(',')[0]), int(line.split('dx = ')[1].split(',')[0]),
                         int(line.split('dy = ')[1].split(',')[0]))
    return out


def table_errors(rows):
    errs = []
    ids = [r['id'] for r in rows]
    names = [r['name'] for r in rows]
    if len(set(ids)) != len(ids) or len(set(names)) != len(names):
        errs.append('an id or a name twice')
    new = [r for r in rows if r['kind'] == 'new'] + [r for r in rows if r['kind'] == 'long']
    if [r['id'] for r in new] != list(range(FIRST, FIRST + len(new))):
        errs.append('the new effects are not the dense block %d..' % FIRST)
    for r in rows:
        if (r['kind'] == 'long') != bool(r['len']) or (r['kind'] == 'long' and r['role'] != 'beam'):
            errs.append('%s: a long beam has a length, nothing else has' % r['name'])
        if r['kind'] not in ('new', 'refill', 'long') or r['role'] not in ('area', 'beam', 'mark', 'status') or r['element'] not in ELEMENTS:
            errs.append('%s: kind, role or element' % r['name'])
        if len(r['src']) != 12 or any(c not in '0123456789abcdef' for c in r['src']):
            errs.append('%s: src is the first 12 hex of the sheet digest' % r['name'])
        if r['kind'] == 'refill' and r['id'] >= MIN_EFFECTS:
            errs.append('%s: a refill is an id of pair 36' % r['name'])
        if (r['role'] == 'beam') != bool(r['dir']):
            errs.append('%s: a beam has a heading, nothing else has' % r['name'])
    for sk in {r['set'] for r in rows}:
        if sk not in ('a3',) + tuple(PACK36_GROUP):
            errs.append('set %s' % sk)
    return errs


# ----------------------------------------------------------------------------------------------------------- the cut
def sheet_file(P, s):
    """the picture file whose digest names a pack effect: the combined sheet"""
    import json
    if s.fmt == 'meta':
        v = s.meta['variants']['oblique/32']
        p = os.path.join(s.root, v['files']['all'])
        return p if os.path.exists(p) else None
    if s.fmt == 'catalog':
        d = json.load(open(s.root))
        sheets = d['sheets']
        if isinstance(next(iter(sheets.values())), dict) or 'full' not in sheets:
            return None
        p = os.path.join(os.path.dirname(s.root), sheets['full'])
        return p if os.path.exists(p) else None
    return None


def find_sheets(P, srcs):
    """{12 hex: Src} of every pack effect under the folders whose sheet file is there"""
    out = {}
    for lst in P.discover(srcs).values():
        for s in lst:
            p = sheet_file(P, s)
            if p:
                out.setdefault(hashlib.sha256(open(p, 'rb').read()).hexdigest()[:12], s)
    return out


def prepared(P, frames, loop):
    """the frames as pair 36 plays them: empty ones dropped, a loop's last FADE frames dissolved"""
    frames = P.trim(frames)
    assert frames, 'no art'
    if loop and len(frames) > P.FADE + 2:
        for j in range(P.FADE):
            k = len(frames) - P.FADE + j
            frames[k] = P.G.dissolve(frames[k], (P.FADE - j) / (P.FADE + 1))
        frames = P.trim(frames)
    return frames


def fixed_strip(P, name, frames, anchor, point, loop, w, h, dx, dy, phases):
    """a refill: the frames in the canvas of the pair 36 spec (w x h tiles, the anchor tile dx from the right and dy from
    the bottom), `phases` phases with the empty ones at the end. Art that leaves the canvas stops the build."""
    import numpy as np
    frames = prepared(P, frames, loop)
    if len(frames) + 1 > phases:
        raise SystemExit('%s: %d frames do not fit the %d phases of pair 36' % (name, len(frames), phases))
    left, top = w - 1 - dx, h - 1 - dy
    strip = np.zeros((h * 32, w * 32 * phases, 4), np.uint8)
    for i, f in enumerate(frames):
        strip[:, i * w * 32:(i + 1) * w * 32] = P.G.place(f, anchor, point, left, top, w, h, name)
    return strip


# ------------------------------------------------------------------------------------------------- the long beams
# O609. The pack draws a beam about 3 tiles long: a start flare, a body, a tip. O607 drew a longer line as copies end to
# end, so every copy showed its own flare and tip (the owner: "os beams maiores estao segmentados"). A long beam is ONE
# effect: the art up to a cut in its body, the body between the cut and one period further repeated n times, then the rest
# of the art with its one tip, moved out by n periods. A copy plays `o` frames ahead of the one before it, so what flows
# along the body (the light pulses, the glint on the chain) runs on through the copies: the speed of that flow
# is measured (flow) and gives the frame step of a period (flow_step). The cut `c` and the period `q` are searched for
# the smallest sum of seam errors: the seam error compares, SLAB px each side
# of a cut, the art that would have come next with the art that does come next, over every frame (0: the same pixels).
# A beam whose body sways (WAVY: the chain) is also bent: at every seam and in every frame the two sides are
# moved sideways, half the gap each and falling to nothing over one period, so the middle line never jumps.
# The work is done in beam coordinates (v along the heading, c across it): whole pixels both ways, on a diagonal too (one
# step along a diagonal is one px in x and one in y), so nothing is resampled and no colour is made up.
PADC = 32                    # free room across the beam, for the bend


def to_strip(frames, anchor, d):
    """(S, v0, c0, n2): S[f, v - v0, c - c0] is the pixel of frame f that lies v along the heading and c across it from
    the centre of the caster's tile. A straight heading counts in px (n2 = 1); a diagonal in half steps (n2 = 2: the pixel
    one px east and one px south of another is 2 further along), so only every second cell of S holds a pixel."""
    import numpy as np
    sx, sy = STEP[d]
    h, w = frames[0].shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    rx, ry = xx - anchor[0] - 16, yy - anchor[1] - 16
    V, C = rx * sx + ry * sy, -rx * sy + ry * sx
    art = np.any([f[..., 3] > 0 for f in frames], axis=0)
    v0, c0 = int(V[art].min()), int(C[art].min()) - PADC
    S = np.zeros((len(frames), int(V[art].max()) - v0 + 1, int(C[art].max()) + PADC - c0 + 1, 4), np.uint8)
    for i, f in enumerate(frames):
        S[i, V[art] - v0, C[art] - c0] = f[art]
    return S, v0, c0, sx * sx + sy * sy


def from_strip(S, v0, c0, d):
    """(frames, anchor): the pictures of S, the anchor being the top left pixel of the caster's tile in them"""
    import numpy as np
    sx, sy = STEP[d]
    n2 = sx * sx + sy * sy
    vi, ci = np.nonzero(np.any(S[..., 3] > 0, axis=0))
    X, Y = (vi + v0) * sx - (ci + c0) * sy, (vi + v0) * sy + (ci + c0) * sx
    assert not (X % n2).any() and not (Y % n2).any(), 'a pixel between pixels'
    X, Y = X // n2, Y // n2
    x0, y0 = min(int(X.min()), -16), min(int(Y.min()), -16)
    w, h = max(int(X.max()), 15) - x0 + 1, max(int(Y.max()), 15) - y0 + 1
    out = []
    for s in S:
        f = np.zeros((h, w, 4), np.uint8)
        f[Y - y0, X - x0] = s[vi, ci]
        out.append(f)
    return out, (-16 - x0, -16 - y0)


def extent(frames, anchor, d):
    """(start, end) of the art along the heading, px per axis from the centre of the caster's tile: the median of the frames"""
    import numpy as np
    S, v0, _, n2 = to_strip(frames, anchor, d)
    lines = [np.nonzero(s[..., 3].any(axis=1))[0] for s in S]
    lo, hi = [l.min() for l in lines if len(l)], [l.max() for l in lines if len(l)]
    return (float(np.median(lo)) + v0) / n2, (float(np.median(hi)) + v0) / n2


def middle(s, a, b):
    """the middle line of one frame over the lines a..b-1 along the heading: the median place across of its pixels (None:
    no pixel there)"""
    import numpy as np
    a, b = max(0, a), min(len(s), b)
    c = np.nonzero(s[a:b, :, 3] > 0)[1] if a < b else []
    return float(np.median(c)) if len(c) else None


def gap(S, v0, n2, f, g, c, q):
    """how far across (in whole steps of the heading's grid) the body of frame g at the cut c lies from the body of
    frame f one period q further: the sideways jump of a seam"""
    lo = middle(S[f], (c + q - 3) * n2 - v0, (c + q) * n2 - v0)
    hi = middle(S[g], c * n2 - v0, (c + 3) * n2 - v0)
    if lo is None or hi is None:
        return 0
    return max(-12, min(12, int(round((hi - lo) / n2))))


def flow(S, v0, n2, lo, hi):
    """px along one axis that the pattern of the body moves from one frame to the next (+ away from the caster), or None
    when nothing moves in step: the light of every line across the body (its mean over the frames taken off, so what
    stands still does not count) of each frame against the next, moved by -14 .. 14 px; the best match, refined between
    its neighbours"""
    import numpy as np
    lum = (S[..., :3].astype(np.float64).sum(-1) * (S[..., 3] > 0)).sum(-1)
    a, b = max(0, int(np.ceil(lo)) * n2 - v0), min(lum.shape[1], int(np.floor(hi)) * n2 - v0)
    lum = lum[:, a:b]
    if n2 == 2:
        lum = lum[:, :lum.shape[1] // 2 * 2].reshape(len(lum), -1, 2).sum(-1)
    prof = lum - lum.mean(0)
    score = {}
    for s in range(-14, 15):
        cs = []
        for f in range(len(prof)):
            x, y = prof[f], prof[(f + 1) % len(prof)]
            xa, ya = (x[:len(x) - s], y[s:]) if s >= 0 else (x[-s:], y[:len(y) + s])
            den = np.sqrt((xa ** 2).sum() * (ya ** 2).sum())
            cs.append((xa * ya).sum() / den if den else 0.0)
        score[s] = float(np.mean(cs))
    s = max(score, key=lambda k: (score[k], -abs(k)))
    if score[s] < 0.4 or s == 0 or abs(s) == 14:
        return None
    lo_, mid, hi_ = score[s - 1], score[s], score[s + 1]
    return s + 0.5 * (lo_ - hi_) / (lo_ - 2 * mid + hi_) if lo_ - 2 * mid + hi_ else float(s)


def flow_step(q, speed, count):
    """the frame step that lets the flow run on over a period of q px: a copy q px further out shows what the flow
    brings there q / speed frames earlier. None when q is not a whole number of frames of flow (0.35 of a frame is let by)"""
    frames = -q / speed
    if abs(frames - round(frames)) > 0.35:
        return None
    return int(round(frames)) % count


def seam_errors(S, v0, n2, lo, hi, wavy, speed=None):
    """{(q, o): (error, c, bend)}: for a period of q px and a frame step o, the cut c (lo + SLAB <= c, c + q <= hi - SLAB)
    with the smallest seam error, and its mean sideways gap in px. The error: over every frame f and the pixels SLAB px
    each side of the cut, frame f one period further (moved sideways by the gap when the beam is wavy) against frame
    f + o; a pixel only one of them has counts 1, one both have counts its colour distance (0..1), and the sum is divided
    by the pixels either has. With a flow `speed` only the frame step that lets the flow run on is tried (flow_step)."""
    import numpy as np
    n = len(S)
    solid = S[..., 3] > 0
    rgb = S[..., :3].astype(np.int32)
    nc = S.shape[2]
    out = {}
    lo, hi = int(np.ceil(lo)), int(np.floor(hi))
    for q in range(8, hi - lo - 2 * SLAB + 1):
        steps = list(range(n)) if speed is None else [flow_step(q, speed, n)]
        if steps[0] is None:
            continue
        for c in range(lo + SLAB, hi - SLAB - q + 1):
            a0, b0 = (c - SLAB) * n2 - v0, (c + SLAB) * n2 - v0
            a1, b1 = a0 + q * n2, b0 + q * n2
            if a0 < 0 or b1 > S.shape[1]:
                continue
            gaps = {}
            for o in steps:
                D = M = B = 0.0
                for f in range(n):
                    g = (f + o) % n
                    m = (gaps.get((f, g)) if (f, g) in gaps else gaps.setdefault((f, g), gap(S, v0, n2, f, g, c, q))) if wavy else 0
                    m *= n2
                    sa, sb = (slice(0, nc - m), slice(m, nc)) if m >= 0 else (slice(-m, nc), slice(0, nc + m))
                    A, Bm = solid[f, a1:b1, sa], solid[g, a0:b0, sb]
                    both = A & Bm
                    D += (A ^ Bm).sum() + np.abs(rgb[f, a1:b1, sa][both] - rgb[g, a0:b0, sb][both]).sum() / 765.0
                    M += (A | Bm).sum()
                    B += abs(m) / n2
                if M > 0:
                    e = D / M
                    if (q, o) not in out or e < out[(q, o)][0] - 1e-12:
                        out[(q, o)] = (e, c, B / n)
    return out


def choose_seam(errors, extra, tol):
    """(c, q, n, o, error, bend) for `extra` px more beam: n whole periods of q px with |n q - extra| <= tol and the
    smallest sum of the n seam errors; of equal sums the longer period (fewer seams), then the smaller frame step"""
    best = None
    for (q, o), (e, c, bend) in sorted(errors.items()):
        n = int(round(extra / q))
        if n < 1 or abs(n * q - extra) > tol:
            continue
        key = (round(n * e, 9), -q, o)
        if best is None or key < best[0]:
            best = (key, (c, q, n, o, e, bend))
    return best[1] if best else None


def stretch(S, v0, n2, c, q, n, o, wavy):
    """S with n more periods: the lines [c + k q, c + (k + 1) q) along the heading show the art's [c, c + q) of the frame
    k o ahead (k = 1 .. n - 1); before them the art up to c + q as it is, after them the art from c on, n o frames ahead.
    wavy: at each seam the piece before it is moved sideways by half the gap, the piece after it by minus half the gap,
    each falling to nothing over the period next to the seam."""
    import numpy as np
    count = len(S)
    cut, per = c * n2 - v0, q * n2
    out = []
    for i in range(count):
        g = [(i + k * o) % count for k in range(n + 1)]
        jump = [0] * (n + 2)                                   # jump[j]: the gap of the seam before piece j
        if wavy:
            for j in range(1, n + 1):
                jump[j] = gap(S, v0, n2, g[j - 1], g[j], c, q)
        parts = []
        for k in range(n + 1):
            a, b = (0 if k == 0 else cut), (S.shape[1] if k == n else cut + per)
            part = S[g[k], a:b].copy()
            for v in range(cut, cut + per):
                t = (v - cut + 0.5) / per
                m = int(round(-jump[k] / 2.0 * (1 - t) + jump[k + 1] / 2.0 * t))
                if m:
                    part[v - a] = np.roll(part[v - a], m * n2, axis=0)
            parts.append(part)
        out.append(np.concatenate(parts, axis=0))
    return np.array(out)


def seam_check(S, T, v0, n2, c, q, n, lo, hi):
    """what the stretched beam T shows at its seams: ([px the middle line steps at each seam of each frame], (the most
    pixels a line across the new body has, the most a line of the art's body lo..hi has))"""
    jumps = []
    for t in T:
        for j in range(1, n + 1):
            v = (c + j * q) * n2 - v0
            a, b = middle(t, v - 2 * n2, v), middle(t, v, v + 2 * n2)
            jumps.append(abs(a - b) / n2 if a is not None and b is not None else 0.0)
    solid_t, solid_s = T[..., 3] > 0, S[..., 3] > 0
    new = solid_t[:, (c + q) * n2 - v0:(c + n * q) * n2 - v0].sum(-1)
    old = solid_s[:, int(lo) * n2 - v0:int(hi + 1) * n2 - v0].sum(-1)
    return jumps, (int(new.max()) if new.size else 0, int(old.max()))


def view_cut(frames, anchor):
    """the frames with the art past the caster's view (VIEW tiles east and south of the caster's tile) removed, and the
    share of the art pixels that went"""
    x1, y1 = anchor[0] + 32 * (VIEW[0] + 1), anchor[1] + 32 * (VIEW[1] + 1)
    before = sum(int((f[..., 3] > 0).sum()) for f in frames)
    out = []
    for f in frames:
        g = f.copy()
        g[:, max(0, x1):] = 0
        g[max(0, y1):] = 0
        out.append(g)
    after = sum(int((f[..., 3] > 0).sum()) for f in out)
    return out, 1 - after / max(1, before)


def beam_plan(P, base, rows, anchor):
    """what the headings of one beam sheet need: {d: (start, end)} of the art, and the px a diagonal's tip lies past the
    centre of its last tile (the straight headings' own, turned onto the diagonal). Stops when a straight heading's art
    is not NATURAL tiles long."""
    ext = {d: extent(P.trim(list(rows[P.DIRS8.index(d)])), anchor, d) for d in DIRS}
    for d in STRAIGHT:
        if int(ext[d][1] // 32) != NATURAL:
            sys.exit('%s %s: the art ends %.1f px out, not on tile %d' % (base, d, ext[d][1], NATURAL))
    over = sum(ext[d][1] - 32 * NATURAL for d in STRAIGHT) / len(STRAIGHT)
    return ext, int(round(over / 2 ** 0.5))


def long_frames(P, base, frames, anchor, d, ln, ext, over, cache=None):
    """(frames, anchor, cut text) of the beam `base` towards d over a line of ln tiles"""
    frames = P.trim(list(frames))
    start, end = ext[d]
    diag = d not in STRAIGHT
    k = 2 ** 0.5 if diag else 1.0
    extra = int(round(32 * ln + over - end if diag else 32 * (ln - NATURAL)))
    if extra <= 0:
        sys.exit('%s %s: a line of %d tiles is not longer than the art' % (base, d, ln))
    cap, tip = CAPS[base]
    wavy = base in WAVY
    S, v0, c0, n2 = to_strip(frames, anchor, d)
    key = (base, d)
    if cache is None or key not in cache:
        lo, hi = start + cap / k, end - tip / k
        speed = flow(S, v0, n2, lo, hi)
        errors = seam_errors(S, v0, n2, lo, hi, wavy, speed)
        print('%s %s: body %.0f..%.0f px, flow %s px a frame' % (base, d, lo, hi, 'none' if speed is None else '%+.1f' % speed))
        if cache is not None:
            cache[key] = errors
    else:
        errors = cache[key]
    pick = choose_seam(errors, extra, 2 if diag else 0)
    if not pick:
        sys.exit('%s %s: no period of the body gives %d px more' % (base, d, extra))
    c, q, n, o, e, bend = pick
    if e > SEAM_MAX:
        sys.exit('%s %s: the best seam has error %.3f (limit %.2f)' % (base, d, e, SEAM_MAX))
    T = stretch(S, v0, n2, c, q, n, o, wavy)
    jumps, wide = seam_check(S, T, v0, n2, c, q, n, start + cap / k, end - tip / k)
    print('%s %s %d tiles: %d seam(s), middle line steps at most %.1f px (mean %.2f), widest line of the new body %d px '
          '(the art\'s body %d px)' % (base, d, ln, n, max(jumps), sum(jumps) / len(jumps), wide[0], wide[1]))
    if wavy and max(jumps) > JUMP_MAX:
        sys.exit('%s %s: the middle line steps %.1f px at a seam (limit %.1f)' % (base, d, max(jumps), JUMP_MAX))
    if wide[0] > wide[1]:
        sys.exit('%s %s: the new body is wider than the art\'s body: a flare or a tip was copied' % (base, d))
    out, anchor = from_strip(T, v0, c0, d)
    return out, anchor, 'c%d q%d n%d o%d e%.3f b%.1f' % (c, q, n, o, e, bend)


def long_strip(P, r, rows, anchor, point, loop, ext, over, cache=None):
    """the strip of a long beam row and its measured fields"""
    assert tuple(point) == (0, 0), 'the beams are placed by their anchor tile'
    base = r['name'][:r['name'].rindex('_l')]
    frames, anchor, cut = long_frames(P, base, rows[P.DIRS8.index(r['dir'])], anchor, r['dir'], int(r['len']), ext, over, cache)
    frames, lost = view_cut(frames, anchor)
    reach = int(extent(frames, anchor, r['dir'])[1] // 32)
    done = P.effect_strip(r['name'], frames, anchor, point, loop, LONG_TILES)
    if done is None:
        sys.exit('%s: larger than %d tiles' % (r['name'], LONG_TILES))
    strip, w, h, n, dx, dy = done
    if lost:
        cut += ' view-%d%%' % max(1, int(round(lost * 100)))
    return strip, dict(w=w, h=h, phases=n, dx=dx, dy=dy, reach=reach, cut=cut)


def build_rows(srcs, kinds=('new', 'refill', 'long')):
    """[(row with every field, strip)] from the packs under srcs. A row whose kind is not in `kinds` is not cut: it is the
    committed row of art_import/area_fx.csv and its strip is None."""
    sys.path.insert(0, HERE)
    import gen_pack36_fx as P
    sheets = find_sheets(P, srcs)
    old = pack36_rows()
    have = {r['name']: r for r in read_spec()} if os.path.exists(SPEC) else {}
    out = []
    loaded = {}
    plans, seams = {}, {}
    for r in pieces():
        if r['kind'] not in kinds:
            if r['name'] not in have:
                sys.exit('%s: not cut in this run and not in art_import/area_fx.csv' % r['name'])
            r.update({k: have[r['name']].get(k, '') for k in ('w', 'h', 'phases', 'ms', 'dx', 'dy', 'reach', 'cut')})
            out.append((r, None))
            continue
        if r['src'] not in sheets:
            sys.exit('%s: no sheet with digest %s under %s' % (r['name'], r['src'], ', '.join(srcs)))
        if r['src'] not in loaded:
            loaded[r['src']] = P.load(sheets[r['src']])
        rows, anchor, point, ms, loop, directional = loaded[r['src']]
        if bool(r['dir']) != directional:
            sys.exit('%s: the sheet has %s headings' % (r['name'], 'eight' if directional else 'no'))
        frames = rows[P.DIRS8.index(r['dir'])] if r['dir'] else rows[0]
        if r['kind'] == 'long':
            if r['src'] not in plans:
                plans[r['src']] = beam_plan(P, r['name'][:r['name'].rindex('_l')], rows, anchor)
            strip, got = long_strip(P, r, rows, anchor, point, loop, *plans[r['src']], cache=seams)
            r.update(got, ms=ms)
            out.append((r, strip))
            continue
        if r['kind'] == 'refill':
            o = old[r['name']]
            w, h, n, dx, dy = (int(o[k]) for k in ('w', 'h', 'phases', 'dx', 'dy'))
            if int(o['ms']) != ms:
                sys.exit('%s: the pack plays at %d ms, pair 36 at %s' % (r['name'], ms, o['ms']))
            strip = fixed_strip(P, r['name'], frames, anchor, point, loop, w, h, dx, dy, n)
        else:
            cut = P.effect_strip(r['name'], frames, anchor, point, loop)
            if cut is None:
                sys.exit('%s: larger than %d tiles' % (r['name'], P.MAX_TILES))
            strip, w, h, n, dx, dy = cut
        r.update(w=w, h=h, phases=n, ms=ms, dx=dx, dy=dy, reach='', cut='')
        out.append((r, strip))
    return out


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def sums_text(pairs):
    """one digest per strip; a row that was not cut in this run keeps its committed digest"""
    old = read_sums() if os.path.exists(SUMS) else {}
    return ''.join('%s  %s\n' % (digest(s) if s is not None else old[r['name']], r['name']) for r, s in pairs)


def read_spec():
    with open(SPEC, newline='') as fh:
        return list(csv.DictReader(fh))


def read_sums():
    return dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))


# -------------------------------------------------------------------------------------------------------- the pair
def is_blank(t):
    return (t.w, t.h, t.phases) == (1, 1, 1) and tuple(t.sprites) == (0,)


def last_new():
    """the id of the last effect O607 appended: a pair that ends there has that step and takes only the long beams"""
    return FIRST + sum(p[0] == 'new' for p in PICKS) - 1


def pad_plan(effects):
    """(first pad id, pad count) for an input pair with `effects` effects, or None when the pair cannot take the step"""
    if not MIN_EFFECTS <= effects < FIRST:
        return None
    return effects + 1, FIRST - 1 - effects


def padded_dat(dat):
    """the dat bytes with blank effects after the last one, up to FIRST - 1 (items, outfits, missiles byte for byte)"""
    plan = pad_plan(len(dat.effects))
    assert plan, 'the pair cannot be padded'
    d = dat.data
    e_end = dat.effects[-1].raw[1]
    assert dat.missiles[0].raw[0] == e_end
    out = bytearray(d[:e_end]) + BLANK * plan[1] + d[e_end:]
    struct.pack_into('<HH', out, 8, len(dat.effects) + plan[1], len(dat.missiles))
    return bytes(out)


def build(dat_path, spr_path, out, srcs, write):
    import numpy as np
    from PIL import Image
    sys.path.insert(0, HERE)
    from datspr import Dat
    d = Dat(dat_path)
    only_long = len(d.effects) == last_new()        # the pair has the O607 step: the long beams are appended to it
    if (pad_plan(len(d.effects)) is None and not only_long) or len(d.missiles) != NEED_MISSILES:
        sys.exit('refused: the input pair has %d effects and %d missiles; this step needs %d to %d effects (pair 72 or later, '
                 'the ids from %d not taken) or %d (the O607 step is in, the long beams are not) and %d missiles' % (
                     len(d.effects), len(d.missiles), MIN_EFFECTS, FIRST - 1, FIRST, last_new(), NEED_MISSILES))
    errs = table_errors(pieces())
    if errs:
        sys.exit('\n'.join(errs))
    for r in pieces():
        if r['kind'] == 'refill' and not only_long and not is_blank(d.effects[r['id'] - 1]):
            sys.exit('refused: effect %d (%s) is not blank in the input pair' % (r['id'], r['name']))
    pairs = build_rows(srcs, ('long',) if only_long else ('new', 'refill', 'long'))
    rows = [r for r, _ in pairs]
    texts = {SPEC: spec_text(rows), SUMS: sums_text(pairs)}
    if write:
        for p, t in texts.items():
            open(p, 'w', newline='').write(t)
            print('wrote', os.path.relpath(p, ROOT))
    else:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        if bad:
            sys.exit('the sheets do not give the committed %s (run with --write after a wanted change)' % ', '.join(
                os.path.relpath(p, ROOT) for p in bad))
    out = os.path.abspath(out)
    strips = os.path.join(out, 'strips')
    padded = os.path.join(out, 'padded')
    os.makedirs(strips, exist_ok=True)
    os.makedirs(padded, exist_ok=True)
    if only_long:
        open(os.path.join(padded, 'Tibia.dat'), 'wb').write(d.data)
        print('the pair ends at %d: only the long beams %d.. are appended' % (last_new(), last_new() + 1))
    else:
        first_pad, pads = pad_plan(len(d.effects))
        open(os.path.join(padded, 'Tibia.dat'), 'wb').write(padded_dat(d))
        pd = Dat(os.path.join(padded, 'Tibia.dat'))
        assert len(pd.effects) == FIRST - 1 and all(is_blank(t) for t in pd.effects[first_pad - 1:]), 'padding'
        assert all(pd.data[a.raw[0]:a.raw[1]] == d.data[b.raw[0]:b.raw[1]] for a, b in zip(pd.effects, d.effects)), 'an effect moved'
        print('padded: %d blank effects %d..%d' % (pads, first_pad, FIRST - 1) if pads else 'padded: nothing to pad')
    spec = os.path.join(strips, 'import.csv')
    with open(spec, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note'])
        for r, s in sorted(pairs, key=lambda p: (p[0]['kind'] != 'refill', p[0]['id'])):
            if s is None:
                continue
            f = os.path.join(strips, r['name'] + '.png')
            Image.fromarray(np.ascontiguousarray(s)).save(f, optimize=False)
            w.writerow([r['id'] if r['kind'] == 'refill' else '', 'effect', r['name'], f, r['w'], r['h'], r['phases'], r['ms'],
                        r['dx'], r['dy'], r['note']])
    cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', os.path.join(padded, 'Tibia.dat'),
           '--ours-spr', spr_path, '--out-dir', out, '--spec', spec, '--expect-first-effect',
           str(last_new() + 1 if only_long else FIRST)]
    if subprocess.run(cmd).returncode:
        sys.exit('import_fx_art.py failed')
    for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv', os.path.join('padded', 'Tibia.dat')):   # the ids come from the table
        p = os.path.join(out, f)
        if os.path.exists(p):
            os.remove(p)
    os.rmdir(padded)
    return live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'), only_long)


def live(dat_path, spr_path, only_long=False):
    """the pair holds each row at its id: size, phases, durations and the pixels of the sums (only_long: the long beams
    alone, for a pair whose earlier rows this run did not write)"""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_vfx import render_back
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = [r for r in read_spec() if r['kind'] == 'long' or not only_long]
    sums = read_sums()
    errs = []
    last = max(int(r['id']) for r in rows)
    if len(dat.effects) < last or len(dat.missiles) != NEED_MISSILES:
        errs.append('the pair has %d effects and %d missiles' % (len(dat.effects), len(dat.missiles)))
    for r in rows if not errs else []:
        t = dat.effects[int(r['id']) - 1]
        ph, w, h = int(r['phases']), int(r['w']), int(r['h'])
        if (t.w, t.h, t.phases) != (w, h, ph):
            errs.append('%s: size or phases differ at %s' % (r['name'], r['id']))
            continue
        if t.anim and set(t.anim[3]) != {int(r['ms'])}:
            errs.append('%s: durations differ' % r['name'])
        back = render_back(t, spr, 1)
        strip = np.concatenate([back[(f, 0, 0, 0)] for f in range(ph)], axis=1).copy()
        strip[strip[..., 3] == 0] = 0
        if digest(strip) != sums.get(r['name']):
            errs.append('%s: pixels differ from the sum' % r['name'])
    for e in errs:
        print(e)
    print('area fx live: %d effects (%d refilled in place, %d new at %d.., %d long beams up to %d), %s' % (
        len(rows), sum(r['kind'] == 'refill' for r in rows), sum(r['kind'] == 'new' for r in rows), FIRST,
        sum(r['kind'] == 'long' for r in rows), last, 'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


# ------------------------------------------------------------------------------------------------- server files
def reach(r):
    """tiles a beam's canvas reaches from the caster's tile along its heading (a diagonal: the shorter side)"""
    w, h, dx, dy = (int(r[k]) for k in ('w', 'h', 'dx', 'dy'))
    sx, sy = STEP[r['dir']]
    side = []
    if sx:
        side.append(dx if sx > 0 else w - 1 - dx)
    if sy:
        side.append(dy if sy > 0 else h - 1 - dy)
    return max(1, min(side))


def lua_text(rows):
    new = [r for r in rows if r['kind'] != 'refill']
    L = ['-- GENERATED by client/tools/sprites/gen_area_fx.py from art_import/area_fx.csv (O607, O609, O613). Do not edit by hand.',
         '-- An area burst, beams, markers and a status effect of the purchased effect packs (docs/CREDITS.md), drawn by client pair %d:' % PAIR,
         '-- %d effects refilled at their pair 36 ids (pair 51 had blanked them; the names, sizes and send offsets are the ones' % (
             len(rows) - len(new)),
         '-- of chaos_pack36_fx_ids.lua) and %d new ones at %d..%d. A plain table: data/lib/chaos_area_fx.lua merges it into' % (
             len(new), FIRST, FIRST + len(new) - 1),
         '-- ChaosVfx when config.lua chaosClientPair is %d or more, so a server on an older pair never sends one.' % PAIR,
         '-- beams: the tiles a beam reaches from the caster along each heading (its canvas), for the chain of segments.',
         '-- lengths (O609): [beam][line length in tiles][heading] = the ONE effect that draws the beam over a line of that',
         '-- length (len: the line, reach: the tiles its art covers; one less where the view of the caster cuts it). The',
         '-- pack\'s own art covers %d tiles on a straight heading (natural), so there the refilled effect is the variant.' % NATURAL,
         'ChaosAreaFxIds = {',
         '\tpair = %d, first = %d, count = %d, natural = %d,' % (PAIR, FIRST, len(new), NATURAL),
         '\teffects = {']
    for r in rows:
        L.append('\t\t%s = {id = %s, dx = %s, dy = %s, ms = %d, w = %s, h = %s, element = "%s", role = "%s", refill = %s%s},  -- %s' % (
            r['name'], r['id'], r['dx'], r['dy'], int(r['ms']) * int(r['phases']), r['w'], r['h'], r['element'], r['role'],
            'true' if r['kind'] == 'refill' else 'false',
            ', len = %s, reach = %s' % (r['len'], r['reach']) if r['kind'] == 'long' else '', r['note']))
    L += ['\t},', '\tbeams = {']
    bases = []
    for r in rows:
        if r['role'] == 'beam' and r['kind'] != 'long' and r['name'][:-len(r['dir']) - 1] not in bases:
            bases.append(r['name'][:-len(r['dir']) - 1])
    for b in bases:
        rs = {r['dir']: reach(r) for r in rows if r['role'] == 'beam' and r['name'] == b + '_' + r['dir']}
        L.append('\t\t%s = {%s},' % (b, ', '.join('%s = %d' % (d, rs[d]) for d in DIRS)))
    L += ['\t},', '\tlengths = {']
    names = {r['name'] for r in rows}
    for b in bases:
        lens = [ln for base, ln in LONG if base == b]
        if lens:
            L.append('\t\t%s = {' % b)
            for ln in lens:
                assert all(long_name(b, ln, d) in names for d in DIRS), (b, ln)
                L.append('\t\t\t[%d] = {%s},' % (ln, ', '.join('%s = "%s"' % (d, long_name(b, ln, d)) for d in DIRS)))
            L.append('\t\t},')
    L += ['\t},', '}']
    return '\n'.join(L) + '\n'


def catalog_text(rows):
    """the area bursts as a catalogue of gen_ground_fx.py: they lie under the creatures like the bursts they stand in for"""
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(['kind', 'id', 'name', 'size', 'send_offset', 'patterns', 'frames', 'ms', 'note'])
    for r in rows:
        if r['role'] == 'area':
            w.writerow(['effect', r['id'], r['name'], '%sx%s' % (r['w'], r['h']), '%s,%s' % (r['dx'], r['dy']), '1x1', r['phases'],
                        r['ms'], r['note']])
    return buf.getvalue()


def tags_text(rows):
    """spell_fx_elements.csv with this step's rows (id, name, element) in id order, the other rows as they are. A row
    this step wrote once and no longer has goes: its names (`ab_`, `mega_`) from FIRST on, and the names of RETIRED.
    Rows of a later step (the lightning step, O614) stay."""
    mine = {r['id'] for r in rows}
    with open(TAGS, encoding='utf-8', newline='') as fh:
        lines = fh.read().splitlines()
    keep = [l for l in lines[1:] if l.split(',')[0] not in mine and not l.split(',')[1].startswith(RETIRED)
            and not (int(l.split(',')[0]) >= FIRST and l.split(',')[1].startswith(('ab_', 'mega_')))]
    new = ['%s,%s,%s' % (r['id'], r['name'], r['element']) for r in rows]
    return '\n'.join(lines[:1] + sorted(keep + new, key=lambda l: int(l.split(',')[0]))) + '\n'


def ids(check):
    rows = read_spec()
    want = {LUA: lua_text(rows), CATALOG: catalog_text(rows), TAGS: tags_text(rows)}
    if check:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_area_fx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


def pair51_errors(rows):
    """a refilled id is no longer on the removed list of pair 51 and is on its keep list"""
    errs = []
    with open(REMOVED, newline='') as fh:
        removed = {r['id'] for r in csv.DictReader(fh) if r['kind'] == 'effect'}
    with open(KEEP, newline='') as fh:
        keep = {r['id']: r['name'] for r in csv.DictReader(fh) if r['kind'] == 'effect'}
    for r in rows:
        if r['kind'] != 'refill':
            continue
        if r['id'] in removed:
            errs.append('%s: effect %s is still in pair51_removed.csv' % (r['name'], r['id']))
        if keep.get(r['id']) != r['name']:
            errs.append('%s: effect %s is not in pair51_keep.csv under that name' % (r['name'], r['id']))
    return errs


def long_row_errors(r):
    """a long beam row: it covers its line, the caster sees its far tile, its seam is below the limit"""
    errs = []
    ln, dx, dy = int(r['len']), int(r['dx']), int(r['dy'])
    part = r['cut'].split(' ')
    ok = len(part) in (6, 7) and [x[0] for x in part[:6]] == list('cqnoeb')
    if not ok or float(part[4][1:]) > SEAM_MAX or int(part[2][1:]) < 1:
        errs.append('%s: the cut is not "c q n o e b" with a seam error of at most %.2f' % (r['name'], SEAM_MAX))
    if dx > VIEW[0] or dy > VIEW[1]:
        errs.append('%s: the far tile of the canvas is outside the view of the caster' % r['name'])
    at_view = (STEP[r['dir']][0] > 0 and dx == VIEW[0]) or (STEP[r['dir']][1] > 0 and dy == VIEW[1])
    if not r['reach'] or not (int(r['reach']) == ln or (at_view and len(part) == 7 and int(r['reach']) == ln - 1)):
        errs.append('%s: the art covers %s tiles of a line of %d' % (r['name'], r['reach'], ln))
    return errs


def check():
    errs = table_errors(pieces())
    rows = read_spec() if os.path.exists(SPEC) else []
    static = [k for k in FIELDS if k not in ('w', 'h', 'phases', 'ms', 'dx', 'dy', 'reach', 'cut')]
    if [[str(r[k]) for k in static] for r in pieces()] != [[r[k] for k in static] for r in rows]:
        errs.append('art_import/area_fx.csv does not list the rows of the script in order')
    old, names = pack36_rows(), pack36_ids()
    for r in rows:
        w, h, dx, dy, ph, ms = (int(r[k]) for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'))
        side = LONG_TILES if r['kind'] == 'long' else 9
        if not (0 <= dx < w and 0 <= dy < h and 1 <= w <= side and 1 <= h <= side and ph >= 2 and ms > 0):
            errs.append('%s: size, offset or phases' % r['name'])
        if r['kind'] == 'long':
            errs += long_row_errors(r)
        elif r['reach'] or r['cut']:
            errs.append('%s: only a long beam has a reach and a cut' % r['name'])
        if r['kind'] == 'refill':
            o = old.get(r['name'])
            if not o or [r[k] for k in ('w', 'h', 'phases', 'ms', 'dx', 'dy')] != [o[k] for k in ('w', 'h', 'phases', 'ms', 'dx', 'dy')]:
                errs.append('%s: not the size, phases and send offset of its pair 36 spec' % r['name'])
            if names.get(r['name']) != (int(r['id']), dx, dy):
                errs.append('%s: not the id and send offset of chaos_pack36_fx_ids.lua' % r['name'])
        elif r['name'] in names:
            errs.append('%s: a new effect takes a pair 36 name' % r['name'])
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS)] if os.path.exists(SUMS) else []
    if sums != [r['name'] for r in rows]:
        errs.append('area_fx.sums does not list the table names in order')
    errs += pair51_errors(rows)
    for p in (SPEC, SUMS, LUA, CATALOG):                               # no pack name outside docs/CREDITS.md
        text = open(p, encoding='utf-8').read().lower() if os.path.exists(p) else ''
        for word in PACK_WORDS:
            if word in text:
                errs.append('%s names a pack' % os.path.relpath(p, ROOT))
    for e in errs:
        print(e)
    bad = ids(True) if rows else 1
    n, m = sum(r['kind'] == 'new' for r in rows), sum(r['kind'] == 'long' for r in rows)
    print('area fx: %d effects refilled at their pair 36 ids, %d new at %d..%d, %d long beams at %d..%d, %s' % (
        len(rows) - n - m, n, FIRST, FIRST + n - 1, m, FIRST + n, FIRST + n + m - 1, 'OK' if not errs and not bad else 'PROBLEMS'))
    return 1 if errs or bad else 0


# the pack names, split so this file does not name them either (docs/CREDITS.md does)
PACK_WORDS = ['mega ' + 'vfx', 'grid ' + 'magic', 'game ' + 'feel']


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'check', 'ids', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--src', action='append', default=[])
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--long', action='store_true', help='live: only the long beams (a pair whose earlier rows are not there)')
    a = ap.parse_args()
    if a.cmd == 'build':
        if not a.src or len(a.rest) != 3:
            sys.exit('build DAT SPR OUT_DIR --src DIR')
        return build(a.rest[0], a.rest[1], a.rest[2], a.src, a.write)
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'live':
        if len(a.rest) != 2:
            sys.exit('live DAT SPR')
        return live(a.rest[0], a.rest[1], a.long)
    return check()


if __name__ == '__main__':
    sys.exit(main())
