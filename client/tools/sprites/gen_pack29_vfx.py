#!/usr/bin/env python3
"""Pair 29, second part: condition auras, element blasts, missiles, fireworks and hit splashes cut from the five
effect packs (animated, one studio) the owner bought on 2026-10-16: status effects, projectiles, fireworks, blood and
explosions.

    python3 -I gen_pack29_vfx.py build --src DIR [--src DIR ...]   # -> art_import/pack29_vfx/<name>.png
                                                                   #    + art_import/pack29_vfx.csv + pack29_vfx.sums
                                                                   #    + art_import/pack29_vfx_sources.csv
    python3 -I gen_pack29_vfx.py build --src DIR ... --check       # rebuild in memory, compare with spec, sums, strips
    python3 -I gen_pack29_vfx.py build --check                     # without the packs (CI): spec and sums match PICKS;
                                                                   #    strips on disk match the sums
    python3 -I gen_pack29_vfx.py preview --out DIR                 # every strip 3x on a ground with the tile grid

Sources: each --src is a folder that holds the unzipped packs. A pick names a strip file (`<Name>_strip<N>.png`, the
frames left to right, square or 2:1 frames, alpha already 0 / 255); it is found by its file name anywhere under a
--src. The files are untrusted: only read as PNG pixels, nothing in them runs. Pack names, the studio and the licence:
docs/CREDITS.md (the packs are listed here and in art_import/pack29_vfx_sources.csv only by their internal labels
`set29 ...`, tools/ci/check_names.py).

Licence (README of every pack, identical): use in games, commercial too, modified or recoloured; no resale and no
sharing of the raw files outside a game; never used as training data for generative AI; credit appreciated. So the
packs are imported only: never a style reference, never measured for a palette, never given to an AI tool
(docs/SPRITE_STYLE.md); `style_check.py` is not run on them. Neither the packs nor these strips are committed:
art_import/pack29_vfx/ is ignored by git; art_import/pack29_vfx.sums holds the sha256 of every strip's pixels.

Conversion (numpy only, deterministic; no recolour):
  * `aura`  condition auras: frames scaled to half size (a 2 x 2 box mean of the premultiplied colour, then the alpha
            cut to 0 / 255 with the 4x4 ordered dither of gen_pack27_fx.py), the frame centre put over the head of a
            creature on the target tile (AURA_POINT). Small and above the body, so they never hide the creature. Their
            send offset is 0, 0: the engine may send them by id (a condition tick, src-patch 0045).
  * `hit`   hit splashes: 1:1, the frame centre on the body (HIT_POINT), kept inside the target tile's column and row
            (offset 0, 0: the engine sends them on a physical hit, src-patch 0045).
  * `blast` explosions: 1:1, the frame centre on the body (BLAST_POINT); the ground blast from the feet
            (GROUND_POINT).
  * `sky`   fireworks: 1:1, the frame centre above the head (SKY_POINT).
  * `bolt`  missiles: the strip points east; the head and the nearest BOLT_LEN px of the trail are kept, centred and
            turned to the eight directions by an exact nearest-pixel rotation, then laid out in the client's 3 x 3
            direction patterns (gen_pack27_fx.MISSILE_DIR), centre on the missile point (13, 13).
Frames a..b every `step`-th; effects get one empty last frame (they play once; auras are sent again while the
condition lasts: server/data/lib/chaos_pack29_vfx.lua).

Pair 29 (client/MANIFEST.md "Condition auras, blasts and fireworks (pair 29)"); server side
server/data/lib/chaos_pack29_vfx.lua behind the pair 29 switch ChaosPack29Fx.PAIR29 (off until the pair is live).
"""
import argparse
import csv
import glob
import io
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack27_fx as G  # noqa: E402

ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'pack29_vfx')
SPEC = os.path.join(ART, 'pack29_vfx.csv')
SUMS = os.path.join(ART, 'pack29_vfx.sums')
SOURCES = os.path.join(ART, 'pack29_vfx_sources.csv')
LICENCE = ('purchased; use in games incl. commercial, modified or recoloured; credit appreciated; no resale or '
           'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md')
# the internal label of each pack (docs/CREDITS.md "Internal: licence tracing" names the pack behind each label)
PACK = {'aura': 'set29 status', 'blast': 'set29 explosion', 'bolt': 'set29 projectile', 'sky': 'set29 firework',
        'hit': 'set29 blood'}

AURA_POINT = (6, -20)      # the aura's centre: over the head of a creature standing on the target tile
HIT_POINT = (10, 8)        # a hit splash: the middle of the body box (8 px up-left of the tile, 32 x 32)
SKY_POINT = (8, -28)       # a firework bursts above the head
BLAST_POINT = (10, 8)      # a blast: on the body of the creature hit (the hit splash's point)
GROUND_POINT = (12, 18)    # a ground blast: from the floor at the feet
BOLT_LEN = 48              # px of a missile kept from its head backwards
BOLT_ANGLE = {'e': 0, 'se': 45, 's': 90, 'sw': 135, 'w': 180, 'nw': 225, 'n': 270, 'ne': 315}   # clockwise, y down

# kind, name, strip file, first and last frame, step, ms per frame, note (spec order = id order).
# What sends each one: server/data/lib/chaos_pack29_vfx.lua.
PICKS = [
    # condition auras (status pack): all sixteen
    ('aura', 'cond_burning', 'Burning_Status_Effect_strip24.png', 0, 23, 2, 83, 'Burning: a small flame over the head'),
    ('aura', 'cond_poison', 'Poison_Status_Effect_strip24.png', 0, 23, 2, 83, 'Poisoned: green venom swirls'),
    ('aura', 'cond_frozen', 'Frozen_Status_Effect_strip24.png', 0, 23, 2, 83, 'Frozen: an ice star'),
    ('aura', 'cond_slowed', 'Slowed_Status_Effect_strip24.png', 0, 23, 2, 83, 'Slowed: a blue snail shell swirl'),
    ('aura', 'cond_shocked', 'Shocked_Status_Effect_strip24.png', 0, 23, 2, 83, 'Shocked: crackling sparks'),
    ('aura', 'cond_bleeding', 'Bleeding_Status_Effect_strip24.png', 0, 23, 2, 83, 'Bleeding: dripping red drops'),
    ('aura', 'cond_cursed', 'Cursed_Status_Effect_strip24.png', 0, 23, 2, 83, 'Cursed: a violet curse vortex'),
    ('aura', 'cond_stunned', 'Stunned_Status_Effect_strip24.png', 0, 23, 2, 83, 'Stunned: stars circle the head'),
    ('aura', 'cond_fear', 'Fear_Status_Effect_strip8.png', 0, 7, 1, 125, 'Feared: a dark dread cloud'),
    ('aura', 'cond_silenced', 'Silenced_Status_Effect_strip24.png', 0, 23, 2, 83, 'Silenced: muted violet rings'),
    ('aura', 'cond_confused', 'Confused_Status_Effect_strip12.png', 0, 11, 1, 83, 'Confused: spinning sparkles'),
    ('aura', 'cond_regeneration', 'Regeneration_Status_Effect_strip24.png', 0, 23, 2, 83,
     'Regenerating: a green healing helix'),
    ('aura', 'cond_blessed', 'Blessed_Status_Effect_strip24.png', 0, 23, 2, 83, 'Blessed: a small golden sun'),
    ('aura', 'cond_enraged', 'Enraged_Status_Effect_strip24.png', 0, 23, 2, 83, 'Enraged: a red fury flame'),
    ('aura', 'cond_invulnerable', 'Invulnerable_Status_Effect_strip24.png', 0, 23, 2, 83,
     'Invulnerable: a turning cyan and white ring'),
    ('aura', 'cond_petrified', 'Petrified_Status_Effect_strip24.png', 0, 23, 2, 83, 'Petrified: grey stone shards'),
    # element blasts (explosions pack): all sixteen
    ('blast', 'blast_dark', 'Dark_Explosion_strip9.png', 0, 8, 1, 70, 'Dark blast: a black burst and a red ring'),
    ('blast', 'blast_energy', 'Energy_Explosion_strip9.png', 0, 8, 1, 70, 'Energy blast: a blue star flash'),
    ('blast', 'blast_lightning', 'Lightning_Explosion_strip9.png', 0, 8, 1, 70, 'Lightning blast: white bolts'),
    ('blast', 'blast_arcane', 'Arcane_Explosion_strip9.png', 0, 8, 1, 70, 'Arcane blast: a violet star'),
    ('blast', 'blast_ice', 'Ice_Explosion_strip9.png', 0, 8, 1, 70, 'Ice blast: cyan shards burst out'),
    ('blast', 'blast_fire1', 'Explosion_1_strip9.png', 0, 8, 1, 70, 'Fire blast: a bright fire star'),
    ('blast', 'blast_fire2', 'Explosion_2_strip9.png', 0, 8, 1, 70, 'Fire blast: a flower of flame drops'),
    ('blast', 'blast_fire3', 'Explosion_3_strip9.png', 0, 8, 1, 70, 'Fire blast: a burst into a fire ring'),
    ('blast', 'blast_fire4', 'Explosion_4_strip9.png', 0, 8, 1, 70, 'Fire blast: a flash and a jagged ring'),
    ('blast', 'blast_fire5', 'Explosion_5_strip9.png', 0, 8, 1, 70, 'Fire blast: smoke, then a fire flower'),
    ('blast', 'blast_fire6', 'Explosion_6_strip9.png', 0, 8, 1, 70, 'Fire blast: a fireball into a fire ring'),
    ('blast', 'blast_boss', 'Boss_Explosion_strip9.png', 0, 8, 1, 80, 'Boss blast: a big fire burst with debris'),
    ('blast', 'blast_massive', 'Massive_explosion_strip9.png', 0, 8, 1, 80,
     'Massive blast: the largest fire burst with debris'),
    ('blast', 'blast_ground', 'Ground_Explosion_strip9.png', 0, 8, 1, 70, 'Ground blast: earth and rocks burst up'),
    ('blast', 'blast_magical', 'Magical_Explosion_strip9.png', 0, 8, 1, 70, 'Magic blast: a blue and violet star'),
    ('blast', 'blast_poison', 'Poison_Explosion_strip9.png', 0, 8, 1, 70, 'Poison blast: a green venom burst'),
    # fireworks (fireworks pack): all sixteen
    ('sky', 'fw_gold_ring', 'firework_1_strip16.png', 0, 15, 1, 70, 'Firework: a golden ring'),
    ('sky', 'fw_blue_star', 'firework_2_strip16.png', 0, 15, 1, 70, 'Firework: a blue star burst'),
    ('sky', 'fw_orange', 'firework_3_strip16.png', 0, 15, 1, 70, 'Firework: an orange shell'),
    ('sky', 'fw_green', 'firework_4_strip16.png', 0, 15, 1, 70, 'Firework: a green shell'),
    ('sky', 'fw_violet', 'firework_5_strip16.png', 0, 15, 1, 70, 'Firework: a violet shell'),
    ('sky', 'fw_rainbow', 'firework_6_strip16.png', 0, 15, 1, 70, 'Firework: a rainbow burst'),
    ('sky', 'fw_heart', 'firework_7_strip16.png', 0, 15, 1, 70, 'Firework: a pink heart'),
    ('sky', 'fw_star', 'firework_8_strip16.png', 0, 15, 1, 70, 'Firework: a golden star'),
    ('sky', 'fw_white_ring', 'firework_9_strip16.png', 0, 15, 1, 70, 'Firework: a widening white ring'),
    ('sky', 'fw_spiral', 'firework_10_strip16.png', 0, 15, 1, 70, 'Firework: a white spiral'),
    ('sky', 'fw_twin', 'firework_11_strip16.png', 0, 15, 1, 70, 'Firework: two small shells'),
    ('sky', 'fw_rocket', 'firework_12_strip16.png', 0, 15, 1, 70, 'Firework: a rocket climbs and pops'),
    ('sky', 'fw_sparks', 'firework_13_strip16.png', 0, 15, 1, 70, 'Firework: golden sparks drift'),
    ('sky', 'fw_ice', 'firework_14_strip16.png', 0, 15, 1, 70, 'Firework: a pale blue shell'),
    ('sky', 'fw_willow', 'firework_15_strip16.png', 0, 15, 1, 70, 'Firework: a golden willow'),
    ('sky', 'fw_grand', 'firework_16_strip16.png', 0, 15, 1, 80, 'Firework: the grand red, white and blue burst'),
    # hit splashes (blood pack: red only)
    ('hit', 'hit_blood', 'Blood_Splatter_2_strip24.png', 0, 23, 2, 45, 'Hit on a blood creature: a small red splash'),
    ('hit', 'hit_blood_spray', 'Blood_Splatter_6_strip24.png', 0, 23, 2, 45,
     'Hit on a fire creature: a small spiky red spray'),
    # missiles (projectiles pack): all sixteen
    ('bolt', 'bolt_arcane', 'Arcane_Energy_Bolt_strip24.png', 0, 23, 3, 50, 'Arcane bolt: a violet energy bolt'),
    ('bolt', 'bolt_crystal', 'Crystal_Projectile_strip24.png', 0, 23, 3, 50, 'Crystal bolt: a cyan crystal dart'),
    ('bolt', 'bolt_dark', 'Dark_Energy_Bolt_strip24.png', 0, 23, 3, 50, 'Dark bolt: a magenta dark energy bolt'),
    ('bolt', 'bolt_fire', 'Fireball_Projectile_strip24.png', 0, 23, 3, 50, 'Fire bolt: a fireball with a flame trail'),
    ('bolt', 'bolt_holy', 'Holy_Light_Projectile_strip24.png', 0, 23, 3, 50, 'Holy bolt: a lance of white light'),
    ('bolt', 'bolt_ice', 'Ice_Shard_Projectile_strip24.png', 0, 23, 3, 50, 'Ice bolt: an ice shard'),
    ('bolt', 'bolt_lightning', 'Lightning_Bolt_Projectile_strip24.png', 0, 23, 3, 50, 'Lightning bolt: forked arcs'),
    ('bolt', 'bolt_meteor', 'Meteor_Projectile_strip24.png', 0, 23, 3, 50, 'Meteor: a burning rock'),
    ('bolt', 'bolt_thorn', 'Nature_Thorn_Projectile_strip24.png', 0, 23, 3, 50, 'Thorn: a green thorn dart'),
    ('bolt', 'bolt_plasma', 'Plasma_Projectile_strip24.png', 0, 23, 3, 50, 'Plasma bolt: a cyan and violet plasma'),
    ('bolt', 'bolt_poison', 'Poison_Orb_Projectile_strip23.png', 0, 22, 3, 50, 'Poison orb: a green venom orb'),
    ('bolt', 'bolt_shadow', 'Shadow_Orb_Projectile_strip24.png', 0, 23, 3, 50, 'Shadow orb: a dark violet orb'),
    ('bolt', 'bolt_soul', 'Soul_Projectile_strip24.png', 0, 23, 3, 50, 'Soul bolt: a pale blue spirit'),
    ('bolt', 'bolt_ultimate', 'Ultimate_Magic_Projectile_strip24.png', 0, 23, 3, 50,
     'Ultimate bolt: blue, violet and gold arcs'),
    ('bolt', 'bolt_water', 'Water_Orb_Projectile_strip24.png', 0, 23, 3, 50, 'Water orb: a blue water orb'),
    ('bolt', 'bolt_wind', 'Wind_Blade_Projectile_strip24.png', 0, 23, 3, 50, 'Wind blade: a white crescent'),
]
# effects sent by the engine with offset 0, 0 (src-patch 0045 sends them by id on the creature's tile)
ZERO_OFFSET = ('aura', 'hit')


def find(srcs, fname):
    hits = []
    for s in srcs:
        hits += glob.glob(os.path.join(glob.escape(s), '**', glob.escape(fname)), recursive=True)
    if not hits:
        sys.exit(f'{fname}: not found under {srcs}')
    return sorted(hits)[0]


def frames_of(srcs, fname):
    """the strip's frames; the count is the file name's `strip<N>`"""
    n = int(fname.rsplit('strip', 1)[1].split('.')[0])
    with Image.open(find(srcs, fname)) as im:
        a = np.asarray(im.convert('RGBA')).copy()
    assert a.shape[1] % n == 0, (fname, a.shape)
    fw = a.shape[1] // n
    return [a[:, i * fw:(i + 1) * fw].copy() for i in range(n)]


def half(fr):
    """2 x 2 box mean of the premultiplied colour (odd sizes padded), alpha cut with the ordered dither"""
    h, w = fr.shape[:2]
    p = np.zeros((h + h % 2, w + w % 2, 4), np.float64)
    p[:h, :w] = fr
    a = p[:, :, 3:4] / 255.0
    pre = np.concatenate([p[:, :, :3] * a, a], 2)
    s = (pre[0::2, 0::2] + pre[1::2, 0::2] + pre[0::2, 1::2] + pre[1::2, 1::2]) / 4.0
    al = s[:, :, 3:4]
    rgb = np.where(al > 0, s[:, :, :3] / np.maximum(al, 1e-9), 0)
    out = np.clip(np.round(np.concatenate([rgb, al * 255.0], 2)), 0, 255).astype(np.uint8)
    return G.clean_alpha(out)


def rotate(fr, deg):
    """exact nearest-pixel turn by `deg` clockwise (y down) about the frame centre, on a square canvas of the
    diagonal"""
    h, w = fr.shape[:2]
    n = int(math.ceil(math.hypot(w, h))) + 2
    c = {0: (1, 0), 90: (0, 1), 180: (-1, 0), 270: (0, -1)}.get(deg)
    if c is None:
        r = math.sqrt(0.5)
        c = {45: (r, r), 135: (-r, r), 225: (-r, -r), 315: (r, -r)}[deg]
    cos, sin = c
    ys, xs = np.mgrid[0:n, 0:n]
    ox, oy = xs + 0.5 - n / 2.0, ys + 0.5 - n / 2.0
    sx = ox * cos + oy * sin + w / 2.0      # inverse turn: back to the source frame
    sy = -ox * sin + oy * cos + h / 2.0
    ix, iy = np.floor(sx).astype(int), np.floor(sy).astype(int)
    ok = (ix >= 0) & (ix < w) & (iy >= 0) & (iy < h)
    out = np.zeros((n, n, 4), np.uint8)
    out[ok] = fr[iy[ok], ix[ok]]
    return out


def bolt_cut(frames):
    """the head and BOLT_LEN px of trail of every frame (same window for all), centred on a square frame"""
    x1 = max(int(np.nonzero(f[:, :, 3].any(axis=0))[0].max()) for f in frames) + 1
    x0 = max(0, x1 - BOLT_LEN)
    rows = [np.nonzero(f[:, x0:x1, 3].any(axis=1))[0] for f in frames]
    y0 = min(int(r.min()) for r in rows if len(r))
    y1 = max(int(r.max()) for r in rows if len(r)) + 1
    side = max(x1 - x0, y1 - y0)
    out = []
    for f in frames:
        sq = np.zeros((side, side, 4), np.uint8)
        cut = f[y0:y1, x0:x1]
        oy, ox = (side - (y1 - y0)) // 2, (side - (x1 - x0)) // 2
        sq[oy:oy + cut.shape[0], ox:ox + cut.shape[1]] = cut
        out.append(sq)
    return out


def keep_in_tile(frames, anchor, point):
    """move the point up / left until no art reaches past the target tile's right or bottom edge"""
    px, py = point
    for f in frames:
        ys, xs = np.nonzero(f[:, :, 3])
        if len(xs):
            px = min(px, 31 - (int(xs.max()) - anchor[0]))
            py = min(py, 31 - (int(ys.max()) - anchor[1]))
    return px, py


def convert(srcs, pick):
    kind, name, fname, a, b, step, ms, note = pick
    src = f'{fname} {a}-{b}' + (f' step {step}' if step > 1 else '')
    frames = frames_of(srcs, fname)
    fr = [f.copy() for f in frames[a:b + 1:step]]
    if kind == 'bolt':
        fr = bolt_cut([G.clean_alpha(f) for f in fr])
        side = fr[0].shape[0]
        pats = {}
        for pat, d in G.MISSILE_DIR.items():
            pats[pat] = [rotate(f, BOLT_ANGLE[d]) for f in fr]
        piv = (pats[(0, 0)][0].shape[1] // 2, pats[(0, 0)][0].shape[0] // 2)
        point = G.MISSILE_CENTRE
        n = len(fr)
        left, top, right, bottom = G.bbox_tiles([f for v in pats.values() for f in v], piv, point)
        w, h = left + 1 + right, top + 1 + bottom
        assert w <= 3 and h <= 3, (name, w, h, side)
        W, H = w * 32, h * 32
        strip = np.zeros((3 * H, 3 * W * n, 4), np.uint8)
        for (x, y), pf in pats.items():
            for i, img in enumerate(pf):
                assert img[:, :, 3].any(), (name, 'empty missile frame')
                x0 = (x * n + i) * W
                strip[y * H:(y + 1) * H, x0:x0 + W] = G.place(img, piv, point, left, top, w, h, name)
        return dict(kind='missile', name=name, file=f'pack29_vfx/{name}.png', w=w, h=h, phases=n, ms=ms,
                    dx=right, dy=bottom, note=f'{note} (from {src})'), strip
    if kind == 'aura':
        fr = [half(f) for f in fr]
        point = AURA_POINT
    else:
        fr = [G.clean_alpha(f) for f in fr]
        point = {'hit': HIT_POINT, 'blast': BLAST_POINT, 'sky': SKY_POINT}[kind]
        if name == 'blast_ground':
            point = GROUND_POINT
    piv = (fr[0].shape[1] // 2, fr[0].shape[0] // 2)
    if kind in ZERO_OFFSET:
        point = keep_in_tile(fr, piv, point)
    strip, w, h, n, dx, dy = G.effect_strip(name, fr, piv, point)
    if kind in ZERO_OFFSET:
        assert (dx, dy) == (0, 0), (name, dx, dy)
    return dict(kind='effect', name=name, file=f'pack29_vfx/{name}.png', w=w, h=h, phases=n, ms=ms,
                dx=dx, dy=dy, note=f'{note} (from {src})'), strip


def sources_text():
    """one row per pick: our name, its kind, the pack's internal label (docs/CREDITS.md), the strip and the licence"""
    buf = io.StringIO()
    wr = csv.writer(buf, lineterminator='\n')
    wr.writerow(['name', 'kind', 'pack', 'source', 'licence'])
    for kind, name, fname, a, b, step, ms, note in PICKS:
        wr.writerow([name, 'missile' if kind == 'bolt' else 'effect', PACK[kind], fname, LICENCE])
    return buf.getvalue()


def expected_names():
    out = []
    for kind, name, fname, a, b, step, ms, note in PICKS:
        src = f'{fname} {a}-{b}' + (f' step {step}' if step > 1 else '')
        out.append(('missile' if kind == 'bolt' else 'effect', name, ms, f'{note} (from {src})', kind))
    return out


def read(path):
    return open(path, newline='').read() if os.path.exists(path) else None


def check_without_art():
    ok = True
    spec, sums = read(SPEC), read(SUMS)
    if spec is None or sums is None:
        print('missing', SPEC if spec is None else SUMS)
        return False
    rows = list(csv.DictReader(io.StringIO(spec)))
    if read(SOURCES) != sources_text():
        print(SOURCES, 'differs from PICKS (run build)')
        ok = False
    want = expected_names()
    if [(r['kind'], r['name']) for r in rows] != [(k, n) for k, n, _, _, _ in want]:
        print('spec names differ from PICKS')
        ok = False
    for r, (kind, name, ms, note, pk) in zip(rows, want):
        exp = dict(file=f'pack29_vfx/{name}.png', ms=str(ms), note=note)
        for k, v in exp.items():
            if r[k] != v:
                print(f'{name}: {k} = {r[k]!r}, PICKS says {v!r}')
                ok = False
        for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'):
            r[k] = int(r[k])
        lim = 3 if kind == 'missile' else G.MAX_TILES
        if not (1 <= r['w'] <= lim and 1 <= r['h'] <= lim and 0 <= r['dx'] < r['w'] and 0 <= r['dy'] < r['h']):
            print(f'{name}: bad size or offset')
            ok = False
        if pk in ZERO_OFFSET and (r['dx'], r['dy']) != (0, 0):
            print(f'{name}: the engine sends it by id, its offset must be 0, 0')
            ok = False
    sum_of = dict(reversed(line.split('  ', 1)) for line in sums.splitlines())
    if sorted(sum_of) != sorted(r['file'] for r in rows):
        print('sums do not list exactly the spec files')
        ok = False
    found = 0
    for r in rows:
        p = os.path.join(ART, r['file'])
        if os.path.exists(p):
            found += 1
            s = np.asarray(Image.open(p).convert('RGBA'))
            errs = G.check_strip(r, s)
            if G.digest(s) != sum_of.get(r['file']):
                errs.append(f"{r['name']}: strip differs from pack29_vfx.sums")
            for e in errs:
                print(e)
            ok = ok and not errs
    print(f'pack29 vfx check (no packs): {len(rows)} specs, {found} strips on disk checked:', 'OK' if ok else 'FAILED')
    return ok


def build(srcs, check):
    if not srcs:
        if not check:
            sys.exit('build needs --src (the packs); without it only --check runs')
        return check_without_art()
    rows, strips, errs = [], [], []
    for p in PICKS:
        r, s = convert(srcs, p)
        errs += G.check_strip(r, s)
        rows.append(r)
        strips.append(s)
    for e in errs:
        print(e)
    if errs:
        return False
    spec = G.spec_text(rows)
    sums = ''.join(f"{G.digest(s)}  {r['file']}\n" for r, s in zip(rows, strips))
    if check:
        ok = read(SPEC) == spec and read(SUMS) == sums and read(SOURCES) == sources_text()
        if not ok:
            print('spec, sums or sources differ from a rebuild')
        for r, s in zip(rows, strips):
            p = os.path.join(ART, r['file'])
            if os.path.exists(p) and not np.array_equal(np.asarray(Image.open(p).convert('RGBA')), s):
                print(r['name'], 'strip differs from a rebuild')
                ok = False
        print('pack29 vfx check:', 'OK' if ok else 'FAILED')
        return ok
    os.makedirs(OUT, exist_ok=True)
    for r, s in zip(rows, strips):
        Image.fromarray(s).save(os.path.join(ART, r['file']), optimize=True)
    open(SPEC, 'w', newline='').write(spec)
    open(SUMS, 'w', newline='').write(sums)
    open(SOURCES, 'w', newline='').write(sources_text())
    for r in rows:
        print(f"{r['kind']} {r['name']}: {r['w']}x{r['h']}, offset {r['dx']},{r['dy']}, {r['phases']} x {r['ms']} ms")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src', action='append', default=[])
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    a = ap.parse_args()
    if a.cmd == 'build':
        sys.exit(0 if build(a.src, a.check) else 1)
    G.SPEC, G.ART = SPEC, ART
    G.preview(a.out)


if __name__ == '__main__':
    main()
