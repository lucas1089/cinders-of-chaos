#!/usr/bin/env python3
"""Projectiles with a particle trail and a life of their own (O526 step 2, pair 67; client/MANIFEST.md "Pair 67").

    python3 -I gen_missile_fx.py build --dat P66/Tibia.dat --spr P66/Tibia.spr   # cut the 6 strips, write the spec, sums, ids
    python3 -I gen_missile_fx.py build --dat P66/Tibia.dat --spr P66/Tibia.spr --check   # rebuild in memory, compare with the repo and the disk
    python3 -I gen_missile_fx.py build --dat P67/Tibia.dat --spr P67/Tibia.spr --check   # the result pair: its 6 missiles are the committed strips (CI live pair)
    python3 -I gen_missile_fx.py build --check                                    # CI, no pair: the committed tables agree
    python3 -I gen_missile_fx.py preview --dat D --spr S --out DIR [--style A|B|C]   # contact sheets (never committed)

Why: the client drew every missile at animation phase 0 (base patch 0147), so no missile moved in flight, and the 6 projectiles below were
1 phase (or a flat 8-phase loop) shot out as a stiff sprite. The engine animates missiles now (base patch 0194: the phase cycles by the dat's
frame durations); this tool gives six of them something to animate. Owner 2026-11-12 (translated): after three videos, "B" (alive + particle
trail) and "Fix the engine too."

What it does, per missile id and per direction (8 travel directions; the centre pattern repeats south, as every pack missile does):
  * reads the missile's own art from the INPUT pair (the pair is the source; no picture is committed or sampled for style);
  * finds the head (the mean of the 35% most forward pixels), puts it at the centre of a 96 x 96 px canvas (3 x 3 tiles) so the missile is
    sent at the send offset (1, 1) like every other 3 x 3 pack missile (VfxShoot, chaos_pair67_missile_ids.lua);
  * style B (the shipped one), 8 phases of 50 ms: the core pulses one palette step up and down, the tail behind the head sways (or re-zigs
    each phase for lightning), an orbiting highlight on the orb, and 3 to 6 small particles fall back behind the head, shrinking by age, in
    the element's own colours (death motes, energy arcs, ice flakes, fire embers, poison drops). Hard alpha, only the projectile's own
    colours (its 8 most used, dark to bright), no blur, no dither, never over the head;
  * style A (alive only) and C (a hard head ring and a long outlined tail) exist for previews (`preview --style`); they are not shipped.
The six: 222 (a magenta orb with tendrils), 221 (a pink lightning line), 5 (the energy shot: forked blue-white lightning), 37 (the small ice
shot), 161 (witchfire_lance: a flame lance) and 144 (venom_glob_necrotic: a green glob). Ids 5 and 37 are the stock ids of
CONST_ANI_ENERGY and CONST_ANI_SMALLICE. Ids 161 and 144 are sent at offset (1, 1) already; 221 and 222 were 1 x 1 sent at (0, 0): the
generated Lua file registers the new offsets.

Licence (docs/CREDITS.md "Projectiles", "Mega VFX 500" and the pair 29 / 36 / 51 sources): the art is purchased, "no resale, redistribution or
sharing of the assets, even modified", never machine-learning training data, never a style reference. So the six strips cut here
(art_import/missile_fx/*.png) are ignored by version control; committed are this script, the spec (art_import/missile_fx_p67.csv), the digests of
the decoded strips (art_import/missile_fx.sums) and the ids file. Everything is procedural (numpy and Pillow, seeded by the missile id): the same
pair gives the same strips byte for byte. No ML, nothing leaves this machine.

Import: python3 -I import_fx_art.py --ours-dat P66/Tibia.dat --ours-spr P66/Tibia.spr --out-dir P67 --spec art_import/missile_fx_p67.csv
(rows with `replace` rebuild the existing missile in place; the old sprites stay in the spr, unused).
"""
import math
import numpy as np
from PIL import Image

NPHASES = 8
CANVAS = 96
C0 = CANVAS // 2
DIRS = {'east': (1, 0), 'west': (-1, 0), 'north': (0, -1), 'south': (0, 1),
        'northeast': (1, -1), 'southeast': (1, 1), 'southwest': (-1, 1), 'northwest': (-1, -1)}
# OTClient missile pattern (x, y): 0 / 1 / 2 = dx<0 / dx=0 / dx>0 (and dy)
PATTERN = {'east': (2, 1), 'west': (0, 1), 'north': (1, 0), 'south': (1, 2),
           'northeast': (2, 0), 'southeast': (2, 2), 'southwest': (0, 2), 'northwest': (0, 0)}

# per-kind behaviour (element feel)
KINDS = {
    'death':   dict(particle='mote'),
    'energy':  dict(particle='arc'),
    'ice':     dict(particle='flake'),
    'fire':    dict(particle='ember'),
    'poison':  dict(particle='drop'),
}


def unit(direction):
    dx, dy = DIRS[direction]
    n = math.hypot(dx, dy)
    return dx / n, dy / n


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def palette_of(frames, k=8):
    """the projectile's own colours: the k most used opaque colours, dark to bright"""
    cnt = {}
    for im in frames:
        a = np.asarray(im.convert('RGBA'))
        m = a[..., 3] > 0
        for c in map(tuple, a[m][:, :3]):
            cnt[c] = cnt.get(c, 0) + 1
    top = sorted(cnt, key=lambda c: -cnt[c])[:k]
    return sorted(top, key=lum)


# ------------------------------------------------------------------ small drawing helpers
def put(arr, x, y, col):
    if 0 <= x < arr.shape[1] and 0 <= y < arr.shape[0]:
        arr[y, x, :3] = col
        arr[y, x, 3] = 255


def rect(arr, x, y, w, h, col):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            put(arr, xx, yy, col)


def over(dst, src):
    m = src[..., 3] > 0
    dst[m] = src[m]


def _rank(pal, rgb):
    d = [sum((int(a) - int(b)) ** 2 for a, b in zip(rgb, p)) for p in pal]
    return int(np.argmin(d))


# ------------------------------------------------------------------ anchor, head size
def analyse(arr, t):
    ys, xs = np.nonzero(arr[..., 3] > 0)
    proj = xs * t[0] + ys * t[1]
    thr = np.percentile(proj, 65)
    sel = proj >= thr
    ax, ay = xs[sel].mean(), ys[sel].mean()
    au = ax * t[0] + ay * t[1]
    n = (-t[1], t[0])
    lat = xs * n[0] + ys * n[1]
    near = np.abs(proj - au) <= 5
    rim = (lat[near].max() - lat[near].min()) / 2 + 0.5 if near.any() else 3
    return int(round(ax)), int(round(ay)), float(min(14, max(2.5, rim)))


def place(im, ax, ay):
    """paste a source frame onto the CANVAS so that (ax, ay) lands on the centre"""
    out = np.zeros((CANVAS, CANVAS, 4), np.uint8)
    a = np.asarray(im.convert('RGBA'))
    ox, oy = C0 - ax, C0 - ay
    h, w = a.shape[:2]
    lost = 0
    for y in range(h):
        for x in range(w):
            if a[y, x, 3]:
                X, Y = x + ox, y + oy
                if 0 <= X < CANVAS and 0 <= Y < CANVAS:
                    out[Y, X] = a[y, x]
                    out[Y, X, 3] = 255
                else:
                    lost += 1
    return out, lost


# ------------------------------------------------------------------ style A operations
def op_pulse(arr, anchor, radius, pal, k):
    """flicker of the bright core: bright-class pixels near the head step one palette colour up / down"""
    K = len(pal)
    lvl = int(round(1.3 * math.sin(2 * math.pi * k / NPHASES)))
    if lvl == 0 or K < 3:
        return arr
    out = arr.copy()
    ys, xs = np.nonzero(arr[..., 3] > 0)
    lo = max(1, K - 3)
    for x, y in zip(xs, ys):
        if (x - anchor[0]) ** 2 + (y - anchor[1]) ** 2 > radius * radius:
            continue
        r = _rank(pal, arr[y, x, :3])
        if r >= lo:
            out[y, x, :3] = pal[min(K - 1, max(lo, r + lvl))]
    return out


def op_wave(arr, anchor, t, mode, amp, k, seed):
    """shift whole columns (or rows) behind the head: 'sway' (a wave running back) or 'zig' (re-zigs every phase)"""
    if amp <= 0:
        return arr
    vertical_shift = abs(t[0]) >= abs(t[1])
    sgn = (1 if t[0] >= 0 else -1) if vertical_shift else (1 if t[1] >= 0 else -1)
    out = np.zeros_like(arr)
    n = CANVAS
    rng = np.random.RandomState(seed * 977 + k * 31 + 5)
    walk = [0]
    for _ in range(40):
        walk.append(int(np.clip(walk[-1] + rng.choice([-1, 0, 1]), -amp, amp)))
    for i in range(n):  # i = column (or row) index
        u = ((i - anchor[0]) if vertical_shift else (i - anchor[1])) * sgn
        behind = max(0, -u)
        env = min(1.0, max(0.0, (behind - 1) / 9.0))
        m = behind // 3
        if mode == 'zig':
            d = int(round(env * walk[min(m, 40)]))
        else:
            d = int(round(env * amp * math.sin(2 * math.pi * (behind / 16.0 - k / NPHASES))))
        if vertical_shift:
            col = arr[:, i]
            if d == 0:
                out[:, i] = col
            elif d > 0:
                out[d:, i] = col[:n - d]
            else:
                out[:n + d, i] = col[-d:]
        else:
            row = arr[i]
            if d == 0:
                out[i] = row
            elif d > 0:
                out[i, d:] = row[:n - d]
            else:
                out[i, :n + d] = row[-d:]
    return out


def op_erode(arr, anchor, t, k, seed, p=0.16):
    """flicker of a flame tail: tail pixels drop out at random, different each phase"""
    rng = np.random.RandomState(seed * 131 + k * 17 + 3)
    out = arr.copy()
    ys, xs = np.nonzero(arr[..., 3] > 0)
    for x, y in zip(xs, ys):
        u = (x - anchor[0]) * t[0] + (y - anchor[1]) * t[1]
        if u < -6 and rng.rand() < p:
            out[y, x] = 0
    return out


def op_orbit(arr, anchor, rim, pal, k):
    """spin of an orb: a bright arc and a dark arc run around the disc (inside its silhouette only)"""
    out = arr.copy()
    r = max(2.0, rim - 2.5)
    for j, (col, off) in enumerate(((pal[-1], 0.0), (pal[1] if len(pal) > 1 else pal[0], math.pi))):
        for s in (-1, 0, 1):
            th = 2 * math.pi * k / NPHASES + off + s * 0.42
            x = int(round(anchor[0] + r * math.cos(th)))
            y = int(round(anchor[1] + r * math.sin(th)))
            if 0 <= x < CANVAS and 0 <= y < CANVAS and arr[y, x, 3]:
                out[y, x, :3] = col
    return out


def alive(arr, anchor, t, rim, pal, k, spec, seed):
    a = op_pulse(arr, anchor, rim * 0.75, pal, k)
    a = op_wave(a, anchor, t, spec.get('wave', 'sway'), spec.get('amp', 1), k, seed)
    if spec.get('erode'):
        a = op_erode(a, anchor, t, k, seed, spec['erode'])
    if spec.get('orbit'):
        a = op_orbit(a, anchor, rim, pal, k)
    return a


# ------------------------------------------------------------------ style B / C: particles, ring, tail
def ramp_color(pal, frac):
    """bright -> dark by frac in 0..1, never the darkest (outline) colour"""
    K = len(pal)
    top = max(1, K - 3)
    i = int(round(frac * (top - 1)))
    return pal[K - 2 - min(top - 1, max(0, i))]


def particles(arr, anchor, t, rim, pal, k, kind, seed, style):
    n = (-t[1], t[0])
    M, life, sp = (12, 6, 3.6) if style == 'B' else (13, 7, 3.6)
    rng = np.random.RandomState(seed * 7919 + 11)
    part = kind
    for j in range(M):
        b = (j * NPHASES) // M
        age = (k - b) % NPHASES
        lat0 = rng.uniform(-1, 1)
        jit = rng.uniform(-1, 1)
        jit2 = rng.uniform(-1, 1)
        if age >= life:
            continue
        frac = age / float(life)
        along = rim * 0.85 + 3 + age * sp + jit * 1.5
        lat = lat0 * (rim * 0.9 + 4.0) * (0.55 + 0.2 * age)
        dx = dy = 0.0
        if part == 'ember':
            dy -= 1.25 * age
        elif part == 'drop':
            dy += 0.28 * age * age
        elif part == 'flake':
            dx += 1.6 * math.sin(age * 1.3 + j)
        elif part == 'mote':
            lat += 1.5 * math.sin(age * 1.1 + j * 2)
        px = anchor[0] - t[0] * along + n[0] * lat + dx
        py = anchor[1] - t[1] * along + n[1] * lat + dy
        X, Y = int(round(px)), int(round(py))
        col = ramp_color(pal, frac)
        bright = pal[-1]
        if part in ('mote', 'ember'):
            if age <= 3:
                rect(arr, X, Y, 2, 2, col)
                put(arr, X, Y, bright if age <= 1 else col)
                if age <= 1 and j % 2 == 0:
                    for ox, oy in ((-1, 0), (2, 0), (0, -1), (1, 2), (-1, 1), (2, 1), (1, -1), (0, 2)):
                        put(arr, X + ox, Y + oy, col)
            else:
                put(arr, X, Y, col)
        elif part == 'flake':
            if age <= 2:
                for ox, oy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                    put(arr, X + ox, Y + oy, bright if (ox, oy) == (0, 0) else col)
            elif age == 3:
                for ox, oy in ((0, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    put(arr, X + ox, Y + oy, col)
            else:
                put(arr, X, Y, col)
        elif part == 'drop':
            if age <= 3:
                rect(arr, X, Y, 2, 2 if age < 2 else 1, col)
                put(arr, X, Y, bright if age == 0 else col)
                put(arr, X, Y + 2, col)
            else:
                put(arr, X, Y, col)
        elif part == 'arc':
            r2 = np.random.RandomState(seed * 31 + j * 101 + k * 7)
            length = max(3, 8 - age)
            cx, cy = px, py
            for s in range(length):
                put(arr, int(round(cx)), int(round(cy)), bright if (s == 0 and age < 2) else col)
                cx -= t[0] * 1.0
                cy -= t[1] * 1.0
                jj = r2.choice([-1, 0, 1])
                cx += n[0] * jj
                cy += n[1] * jj
    return arr


def head_ring(arr, anchor, rim, pal, k):
    rr = rim + 2.2
    ys, xs = np.mgrid[0:CANVAS, 0:CANVAS]
    d = np.hypot(xs - anchor[0], ys - anchor[1])
    th = np.arctan2(ys - anchor[1], xs - anchor[0])
    seg = ((th / (2 * math.pi)) * 12 + k * 1.5) % 3.0
    ring1 = (d >= rr - 0.5) & (d < rr + 0.5) & (seg < 2.0)
    ring2 = (d >= rr + 0.5) & (d < rr + 1.5) & (seg < 1.0)
    arr[ring1, :3] = pal[-1]
    arr[ring1, 3] = 255
    mid = pal[len(pal) // 2 + 1] if len(pal) > 2 else pal[-1]
    arr[ring2, :3] = mid
    arr[ring2, 3] = 255
    return arr


def comet_tail(arr, anchor, t, rim, pal, k, L=38):
    n = (-t[1], t[0])
    mask = np.zeros((CANVAS, CANVAS), bool)
    colr = np.zeros((CANVAS, CANVAS, 3), np.uint8)
    w0 = max(1.5, rim * 0.8)
    K = len(pal)
    for s in range(L + 1):
        f = s / float(L)
        sway = 2.0 * f * math.sin(2 * math.pi * (s / 15.0 - k / NPHASES))
        cx = anchor[0] - t[0] * (rim * 0.4 + s) + n[0] * sway
        cy = anchor[1] - t[1] * (rim * 0.4 + s) + n[1] * sway
        hw = int(round(w0 * (1 - f) ** 0.7))
        band = min(3, int(f * 4))
        col = pal[max(1, K - 3 - band)] if K > 3 else pal[-1]
        for oy in range(-hw, hw + 1):
            for ox in range(-hw, hw + 1):
                if ox * ox + oy * oy <= hw * hw + (0 if hw else 0):
                    X, Y = int(round(cx)) + ox, int(round(cy)) + oy
                    if 0 <= X < CANVAS and 0 <= Y < CANVAS:
                        mask[Y, X] = True
                        colr[Y, X] = col
    # 1 px outline in the darkest colour of the projectile
    dil = mask.copy()
    dil[1:, :] |= mask[:-1, :]
    dil[:-1, :] |= mask[1:, :]
    dil[:, 1:] |= mask[:, :-1]
    dil[:, :-1] |= mask[:, 1:]
    out = arr.copy()
    edge = dil & ~mask
    out[edge, :3] = pal[0]
    out[edge, 3] = 255
    out[mask, :3] = colr[mask]
    out[mask, 3] = 255
    return out


# ------------------------------------------------------------------ the entry point
def enhance(frames, palette, style, direction, kind='death', wave='sway', amp=1, orbit=False, erode=0.0, seed=1):
    """see module docstring.  kind picks the particle (death mote, energy arc, ice flake, fire ember, poison drop)."""
    t = unit(direction)
    spec = dict(wave=wave, amp=amp, orbit=orbit, erode=erode)
    base0 = np.asarray(frames[0].convert('RGBA'))
    ax, ay, rim = analyse(base0, t)
    pal = list(palette)
    out = []
    for k in range(NPHASES):
        src = frames[k % len(frames)]
        arr, lost = place(src, ax, ay)
        if lost:
            raise ValueError('source frame does not fit the 3x3 canvas (%d px lost)' % lost)
        a = alive(arr, (C0, C0), t, rim, pal, k, spec, seed)
        if style == 'A':
            res = a
        else:
            under = np.zeros_like(a)
            if style == 'C':
                under = comet_tail(under, (C0, C0), t, rim, pal, k)
                under = head_ring(under, (C0, C0), rim, pal, k)
            res = under
            over(res, a)
            parts = np.zeros_like(a)
            parts = particles(parts, (C0, C0), t, rim, pal, k, KINDS[kind]['particle'], seed, style)
            # particles never cover the head sprite itself
            m = (a[..., 3] > 0) & (parts[..., 3] > 0)
            parts[m] = 0
            over(res, parts)
        res[..., 3] = np.where(res[..., 3] > 0, 255, 0)
        out.append(Image.fromarray(res, 'RGBA'))
    return out


def today_frames(thing, spr, direction, render_frame):
    px, py = PATTERN[direction]
    return [render_frame(thing, spr, p, px, py) for p in range(thing.phases)]


# ------------------------------------------------------------------------------------------------ the six, the strips, the checks
import argparse  # noqa: E402
import csv  # noqa: E402
import hashlib  # noqa: E402
import io  # noqa: E402
import os  # noqa: E402
import sys  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'missile_fx')
SPEC = os.path.join(ART, 'missile_fx_p67.csv')
SUMS = os.path.join(ART, 'missile_fx.sums')
LUA = os.path.join(HERE, '..', '..', '..', 'server', 'data', 'lib', 'chaos_pair67_missile_ids.lua')
IGNORE_TEXT = ('# strips cut from purchased projectile art: not to be redistributed, never committed (gen_missile_fx.py)\n'
               '*\n!.gitignore\n')
STYLE = 'B'
MS = 50                      # per phase, the engine's fixed step too (base patch 0194 kFixedMs)
SEND = (1, 1)                # the send offset of a 3 x 3 group whose head is at the canvas centre
PHASES = NPHASES
SPEC_FIELDS = ['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note']

# key, missile id, label, kind (the particle), tail motion, amplitude, orbit highlight, flame erosion, Lua names
SPECS = [
    dict(key='dreamrot', id=222, label='Dreamrot', kind='death', wave='sway', amp=1, orbit=True, names=['p51_magenta_orb_tendrils']),
    dict(key='soulrend', id=221, label='Soulrend Beam', kind='death', wave='zig', amp=2, names=['p51_pink_lightning']),
    dict(key='energy', id=5, label='Energy shot', kind='energy', wave='zig', amp=1, names=['p67_energy_shot']),
    dict(key='ice', id=37, label='Ice shot', kind='ice', wave='sway', amp=1, names=['p67_ice_shot']),
    dict(key='fire', id=161, label='Witchfire Bolt', kind='fire', wave='sway', amp=1, erode=0.18, names=[]),
    dict(key='earth', id=144, label='Blightbrand', kind='poison', wave='sway', amp=1, names=[]),
]
IDS = [s['id'] for s in SPECS]


def spec_rows():
    rows = []
    for s in SPECS:
        rows.append(dict(replace=s['id'], kind='missile', name='mfx_' + s['key'], file='missile_fx/mfx_%s.png' % s['key'],
                         w=CANVAS // 32, h=CANVAS // 32, phases=PHASES, ms=MS, dx=SEND[0], dy=SEND[1],
                         note='%s: style %s, particle trail, 8 phases (pair 67: redrawn in place at missile %d)' % (s['label'], STYLE, s['id'])))
    return rows


def spec_text():
    out = io.StringIO()
    w = csv.DictWriter(out, SPEC_FIELDS, lineterminator='\n')
    w.writeheader()
    for r in spec_rows():
        w.writerow(r)
    return out.getvalue()


def lua_text():
    L = ['-- GENERATED by client/tools/sprites/gen_missile_fx.py (O526, client pair 67). Do not edit by hand.',
         '-- The 6 projectiles redrawn with a particle trail: 3 x 3 tiles, 8 phases of 50 ms, the head at the centre of the group, so they are',
         '-- sent at the send offset (1, 1) (VfxShoot adds it to both ends). Ids 221 and 222 were 1 x 1 at (0, 0) before pair 67: the p51_ names',
         '-- below replace the offsets of chaos_pair51_missile_ids.lua. Ids 5 and 37 are the stock CONST_ANI_ENERGY and CONST_ANI_SMALLICE:',
         '-- the engine override of pair 29 (chaos_pack29_vfx.lua C.missiles) sends those as the pack bolts; p67_energy_shot / p67_ice_shot name',
         '-- the new art for a spell that wants it (server/README.md "Projectiles with a trail (O526)"). 161 and 144 keep their pack names',
         '-- (witchfire_lance, proj_venom_glob_necrotic: offset 1, 1 already).',
         'if not ChaosVfxMissile then',
         '\tpcall(dofile, "data/lib/chaos_vfx.lua")',
         'end',
         'ChaosVfxMissile = ChaosVfxMissile or {}']
    for s in SPECS:
        for n in s['names']:
            L.append('ChaosVfxMissile.%s = {id = %d, dx = %d, dy = %d}  -- %s, 3x3, %d phases of %d ms' % (n, s['id'], SEND[0], SEND[1], s['label'], PHASES, MS))
    return '\n'.join(L) + '\n'


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def strip_path(s):
    return os.path.join(OUT, 'mfx_%s.png' % s['key'])


def sums_text(strips):
    return ''.join('%s  missile_fx/mfx_%s.png\n' % (digest(strips[s['key']]), s['key']) for s in SPECS)


def build_strip(frames_by_dir, spec):
    """frames_by_dir: {direction: [RGBA PIL images]} (the missile's art in the input pair, one list per direction)
    -> the strip array (3 * 96, 3 * 96 * PHASES, 4): the 3 x 3 direction patterns, each PHASES frames left to right"""
    pal = palette_of([f for d in DIRS for f in frames_by_dir[d]])
    out = np.zeros((3 * CANVAS, 3 * CANVAS * PHASES, 4), np.uint8)
    cells = {}
    for d in DIRS:
        fr = enhance(frames_by_dir[d], pal, STYLE, d, kind=spec['kind'], wave=spec.get('wave', 'sway'), amp=spec.get('amp', 1),
                     orbit=spec.get('orbit', False), erode=spec.get('erode', 0.0), seed=spec['id'])
        cells[PATTERN[d]] = fr
    cells[(1, 1)] = cells[PATTERN['south']]           # the centre cell repeats the south row (every pack missile does)
    for (px, py), fr in cells.items():
        for f, im in enumerate(fr):
            x0 = (px * PHASES + f) * CANVAS
            out[py * CANVAS:(py + 1) * CANVAS, x0:x0 + CANVAS] = np.asarray(im)
    return out


def source_frames(dat, spr, mid):
    from fxlib import render_frame
    t = dat.missiles[mid - 1]
    return {d: today_frames(t, spr, d, render_frame) for d in DIRS}


def is_built(dat, mid):
    """True when the pair already holds the new art at this id (3 x 3, 8 phases of 50 ms): the result pair 67 and later"""
    t = dat.missiles[mid - 1]
    raw = list(t.anim[3]) if t.anim else []
    return (t.w, t.h, t.phases) == (3, 3, PHASES) and len(raw) == 2 * PHASES and set(raw) == {MS}


def strip_of_pair(dat, spr, mid):
    """the missile as the pair draws it, in the strip layout (3 x 3 patterns, each PHASES frames left to right)"""
    from fxlib import render_frame
    t = dat.missiles[mid - 1]
    out = np.zeros((3 * CANVAS, 3 * CANVAS * PHASES, 4), np.uint8)
    for py in range(3):
        for px in range(3):
            for f in range(PHASES):
                a = np.array(render_frame(t, spr, f, px, py))
                a[a[..., 3] == 0] = 0
                out[py * CANVAS:(py + 1) * CANVAS, (px * PHASES + f) * CANVAS:(px * PHASES + f + 1) * CANVAS] = a
    return out


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def read_png(path):
    a = np.array(Image.open(path).convert('RGBA'))
    a[a[..., 3] == 0] = 0
    return a


def committed_problems(strips=None):
    """what is out of step between the generator and the committed spec, ids file and sums (strips: rebuilt arrays or None)"""
    bad = []
    for path, want in ((SPEC, spec_text()), (LUA, lua_text())):
        if not os.path.exists(path) or open(path, encoding='utf-8', newline='').read() != want:
            bad.append('stale: ' + os.path.relpath(path, HERE))
    if not os.path.exists(SUMS):
        bad.append('missing: ' + os.path.relpath(SUMS, HERE))
        return bad
    text = open(SUMS, encoding='utf-8').read()
    lines = [l.split() for l in text.splitlines() if l.strip()]
    names = [l[1] for l in lines if len(l) == 2]
    want_names = ['missile_fx/mfx_%s.png' % s['key'] for s in SPECS]
    if names != want_names or any(len(l[0]) != 64 for l in lines):
        bad.append('sums: the lines are not the 6 strips in order')
    if strips is not None and text != sums_text(strips):
        bad.append('stale digests: ' + os.path.relpath(SUMS, HERE))
    if strips is None:
        for s, l in zip(SPECS, lines):
            if os.path.exists(strip_path(s)) and digest(read_png(strip_path(s))) != l[0]:
                bad.append('the strip on disk differs from its digest: mfx_%s.png' % s['key'])
    return bad


def preview(dat, spr, outdir, style):
    """one contact sheet per missile: 8 directions (rows), the 8 phases (columns), 2x"""
    os.makedirs(outdir, exist_ok=True)
    for s in SPECS:
        fr = source_frames(dat, spr, s['id'])
        pal = palette_of([f for d in DIRS for f in fr[d]])
        z = 2
        sheet = Image.new('RGBA', (PHASES * CANVAS * z, len(DIRS) * CANVAS * z), (22, 24, 30, 255))
        for r, d in enumerate(DIRS):
            en = enhance(fr[d], pal, style, d, kind=s['kind'], wave=s.get('wave', 'sway'), amp=s.get('amp', 1), orbit=s.get('orbit', False),
                         erode=s.get('erode', 0.0), seed=s['id'])
            for k, im in enumerate(en):
                sheet.alpha_composite(im.resize((CANVAS * z, CANVAS * z), Image.NEAREST), (k * CANVAS * z, r * CANVAS * z))
        p = os.path.join(outdir, 'missile_%s_%s.png' % (style, s['key']))
        sheet.convert('RGB').save(p)
        print('preview', p)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'preview'])
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    ap.add_argument('--check', action='store_true', help='compare with the repository and the disk, write nothing')
    ap.add_argument('--out', default=None, help='preview: the folder for the sheets')
    ap.add_argument('--style', default='B', choices=['A', 'B', 'C'], help='preview: the style (only B is shipped)')
    a = ap.parse_args(argv)
    if a.cmd == 'preview':
        if not (a.dat and a.spr and a.out):
            sys.exit('preview needs --dat, --spr and --out')
        from datspr import Dat, Spr
        preview(Dat(a.dat), Spr(a.spr), a.out, a.style)
        return 0
    strips = None
    if a.dat or a.spr:
        if not (a.dat and a.spr):
            sys.exit('--dat and --spr go together')
        from datspr import Dat, Spr
        dat, spr = Dat(a.dat), Spr(a.spr)
        built = [is_built(dat, s['id']) for s in SPECS]
        if any(built) and not all(built):
            sys.exit('the pair holds the new art for some of the six missiles but not all: not an input and not a result pair')
        if all(built):      # a result pair (67 or later): its six missiles must be the committed strips
            if not a.check:
                sys.exit('this pair already holds the new art; build from the input pair (66), or use --check on this one')
            strips = {s['key']: strip_of_pair(dat, spr, s['id']) for s in SPECS}
        else:
            strips = {s['key']: build_strip(source_frames(dat, spr, s['id']), s) for s in SPECS}
    elif not a.check:
        sys.exit('build needs --dat and --spr (the input pair), or --check alone for the committed tables')
    if a.check:
        bad = committed_problems(strips)
        for b in bad:
            print(b)
        print('missile fx up to date' if not bad else 'run: python3 -I gen_missile_fx.py build --dat P/Tibia.dat --spr P/Tibia.spr')
        return 1 if bad else 0
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, '.gitignore'), 'w', encoding='utf-8', newline='') as f:
        f.write(IGNORE_TEXT)
    for s in SPECS:
        with open(strip_path(s), 'wb') as f:
            f.write(png_bytes(strips[s['key']]))
    for path, text in ((SPEC, spec_text()), (SUMS, sums_text(strips)), (LUA, lua_text())):
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    print('strips', OUT, '; missile ids', ', '.join(str(i) for i in IDS))
    return 0


if __name__ == '__main__':
    sys.exit(main())
