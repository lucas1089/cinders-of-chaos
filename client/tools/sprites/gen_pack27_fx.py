#!/usr/bin/env python3
"""Pair 27 trial: own effects and missiles for the nine pack farming spells, cut from three oblique effect sets.

    python3 -I gen_pack27_fx.py build --src DIR [--src DIR ...]   # -> art_import/pack27_fx/<name>.png
                                                                  #    + art_import/pack27_fx.csv + pack27_fx.sums
    python3 -I gen_pack27_fx.py build --src DIR ... --check       # rebuild in memory, compare with spec, sums, strips
    python3 -I gen_pack27_fx.py build --check                     # without the sets (CI): spec and sums match PICKS;
                                                                  #    strips on disk match the sums
    python3 -I gen_pack27_fx.py preview --out DIR                 # every strip 3x on a ground with the tile grid + GIFs

The sources: the owner's oblique effect sets of 2026-10-15 (Google Drive "ots"): projectiles, fields and traps, and
game feel effects, 32 px tiles. Each --src is a folder that holds unzipped sets; an effect variant is found at
`sheets/32px/<category>/<effect>/<variant>/<effect>_<variant>.json` in any of them (frame size, pivot, anchor tile,
layers, stages, sheets; 8-way sheets have one row per direction, E SE S SW W NW N NE).

Conversion (like gen_pack_fx.py):
  * layers merged: `back` at 60 % opacity under `front` (import_vfx.py BACK_ALPHA), `ground` under `air`;
    staged effects (start / loop / end) are their stages in order;
  * frames a..b of that, every `step`-th; alpha made clean (0 / 255; soft pixels become an ordered 4x4 dither);
    effects: empty frames at the end are dropped and one empty last frame is added (they play once);
  * placed like import_vfx.py: a unit-centred effect's pivot (the set's feet point, a quarter tile right/down of the
    tile centre) goes on our feet point (14, 20); a tile-centred one's pivot (the tile centre) on (16, 16);
    a missile's pivot (its frame centre) on (13, 13); cut to whole tiles, sent at target + (dx, dy);
  * missiles: the 3 x 3 direction patterns of the client (import_vfx.MISSILE_DIR), each a block of the frames;
    directional effects (`dirs`): one effect per direction, named <name>_<dir> (VfxDir).

The sets' licence allows use in unlimited commercial projects (games included), modified or not, without
attribution; it forbids reselling, redistributing, sublicensing or sharing the assets themselves (alone or in
another pack, template or generator, even modified) and machine-learning training. Shipping the converted frames
inside the game client is use in a game. So neither the sets nor these strips are committed: art_import/pack27_fx/
is ignored by git; art_import/pack27_fx.sums holds the sha256 of every strip's decoded RGBA pixels.
Deterministic: no randomness; Pillow 12.3.0 and numpy 2.5.3 (the CI pins).

Not in any published pair. Trial: appended to things_custom26 with import_fx_art.py (client/MANIFEST.md
"Pack farming spell effects (pair 27 trial)"); server side server/data/lib/chaos_pack27_fx.lua behind the switch
ChaosPack27Fx.PAIR27_FX (off).
"""
import argparse
import csv
import glob
import hashlib
import io
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'pack27_fx')
SPEC = os.path.join(ART, 'pack27_fx.csv')
SUMS = os.path.join(ART, 'pack27_fx.sums')
FEET = (14, 20)               # import_vfx.PLACE['feet']
TILE_CENTRE = (16, 16)
MISSILE_CENTRE = (13, 13)     # import_vfx.PLACE['centre']
BACK_ALPHA = 0.6
MAX_TILES = 5
DIRS8 = ['e', 'se', 's', 'sw', 'w', 'nw', 'n', 'ne']
MISSILE_DIR = {(0, 0): 'nw', (1, 0): 'n', (2, 0): 'ne', (0, 1): 'w', (1, 1): 's', (2, 1): 'e',
               (0, 2): 'sw', (1, 2): 's', (2, 2): 'se'}
OUR_DIRS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']       # suffix order of the directional effects

# kind, name, source effect, variant, first and last frame of the merged stages, step, ms per frame, note
# (spec order = id order; a 'dirs' row writes 8 effects <name>_<dir>)
PICKS = [
    ('effect', 'palm_quake', 'fx_dust_cloud', 'earth', 0, 13, 1, 70,
     'Palm Shockwave: a ring of rubble and dust bursts from the struck target'),
    ('effect', 'flurry_petals', 'fx_dance_spin', 'sakura', 0, 15, 1, 70,
     'Blade Flurry: a sakura blade spiral round the caster, petals scatter'),
    ('dirs', 'iaido_dash', 'fx_charge_dash', 'steel', 0, 11, 1, 70,
     'Iaido Sweep: steel crescents and speed lines rush towards the cut'),
    ('effect', 'ricochet_burst', 'fx_shadow_step', 'void', 0, 15, 1, 70,
     'Shadow Ricochet: violet shards burst on each struck target, a fading ring'),
    ('effect', 'chain_sparks', 'fx_spark_shower', 'steel', 0, 11, 1, 70,
     'Iron Chain: a shower of steel sparks on each link'),
    ('effect', 'sanctified_seal', 'fx_resurrection', 'holy', 0, 23, 2, 110,
     'Sanctified Ground: a golden rune circle on the ground, a winged light rises'),
    ('effect', 'shieldwave_wall', 'field_magic_wall', 'holy', 0, 31, 2, 90,
     'Shield Wave: a pane of golden light rises in front and fades'),
    ('missile', 'fan_knife', 'proj_throwing_knife', 'steel', 0, 7, 1, 83, 'Fan of Knives: a steel throwing knife'),
    ('missile', 'ricochet_bolt', 'proj_shadow_bolt', 'void', 0, 7, 1, 83, 'Shadow Ricochet: a violet shadow bolt'),
    ('missile', 'chain_disc', 'proj_energy_disc', 'gold', 0, 7, 1, 83, 'Iron Chain: a ring of golden chi'),
    ('missile', 'shrapnel_shards', 'proj_bone_shards', 'bone', 0, 7, 1, 83, 'Bone Shrapnel: three bone shards'),
]

BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0


def clean_alpha(fr):
    """RGBA -> RGBA with alpha 0 / 255: opaque stays, soft pixels kept where alpha beats a 4x4 Bayer threshold"""
    a = fr[:, :, 3].astype(np.float64) / 255.0
    h, w = a.shape
    thr = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    keep = (a >= 1.0) | ((a > 0) & (a > thr))
    out = fr.copy()
    out[:, :, 3] = np.where(keep, 255, 0).astype(np.uint8)
    out[~keep] = 0
    return out


def over(dst, src, alpha=1.0):
    """straight-alpha 'over' in float, -> uint8 RGBA"""
    d = dst.astype(np.float64) / 255.0
    s = src.astype(np.float64) / 255.0
    sa = s[:, :, 3:4] * alpha
    da = d[:, :, 3:4]
    oa = sa + da * (1 - sa)
    rgb = np.where(oa > 0, (s[:, :, :3] * sa + d[:, :, :3] * da * (1 - sa)) / np.maximum(oa, 1e-9), 0)
    return np.clip(np.round(np.concatenate([rgb, oa], 2) * 255), 0, 255).astype(np.uint8)


def find(srcs, eid, var):
    hits = []
    for s in srcs:
        hits += glob.glob(os.path.join(s, '**', 'sheets', '32px', '*', eid, var, f'{eid}_{var}.json'), recursive=True)
    if not hits:
        sys.exit(f'{eid}/{var}: not found under {srcs}')
    return sorted(hits)[0]


def load(srcs, eid, var):
    """-> (meta, {row: [frames]}) of the merged layers, stages in order"""
    path = find(srcs, eid, var)
    d = json.load(open(path))
    base = os.path.dirname(path)
    fw, fh = d['frame_width'], d['frame_height']
    assert d['tile_size'] == 32, path
    sheets = d['sheets']
    parts = [sheets[k] for k in ('start', 'loop', 'end') if k in sheets] \
        if isinstance(sheets.get('loop'), dict) else [sheets]
    layers = d['layers']
    rows = len(d.get('directions') or []) or 1
    out = {r: [] for r in range(rows)}
    for p in parts:
        merged = None
        for ln in layers:
            a = np.asarray(Image.open(os.path.join(base, p[ln])).convert('RGBA'))
            if merged is None:
                merged = np.zeros_like(a)
            merged = over(merged, a, BACK_ALPHA if (ln == 'back' and 'front' in layers) else 1.0)
        assert merged.shape[0] == fh * rows and merged.shape[1] % fw == 0, (path, merged.shape)
        for r in range(rows):
            for i in range(merged.shape[1] // fw):
                out[r].append(merged[r * fh:(r + 1) * fh, i * fw:(i + 1) * fw].copy())
    return d, out


def bbox_tiles(frames, anchor, point):
    x0 = y0 = 10 ** 6
    x1 = y1 = -10 ** 6
    for fr in frames:
        al = fr[:, :, 3] > 0
        if not al.any():
            continue
        ys, xs = np.nonzero(al)
        ox, oy = point[0] - anchor[0], point[1] - anchor[1]
        x0, x1 = min(x0, xs.min() + ox), max(x1, xs.max() + 1 + ox)
        y0, y1 = min(y0, ys.min() + oy), max(y1, ys.max() + 1 + oy)
    t = lambda v: int(-(-max(0, v) // 32))
    return t(-x0), t(-y0), t(x1 - 32), t(y1 - 32)


def place(f, anchor, point, left, top, w, h, name):
    fh, fw = f.shape[:2]
    px, py = left * 32 + point[0] - anchor[0], top * 32 + point[1] - anchor[1]
    cv = np.zeros((h * 32 + 2 * fh, w * 32 + 2 * fw, 4), np.uint8)       # padded: art outside is cut, checked
    cv[fh + py:fh + py + fh, fw + px:fw + px + fw] = f
    tile = cv[fh:fh + h * 32, fw:fw + w * 32]
    assert (tile[:, :, 3] > 0).sum() == (f[:, :, 3] > 0).sum(), (name, 'art clipped')
    return tile


def pivot_point(meta, kind):
    """(the set's pivot in frame pixels, our point on the target tile)"""
    piv = (int(round(meta['pivot'][0])), int(round(meta['pivot'][1])))
    if kind == 'missile':
        return piv, MISSILE_CENTRE
    ax, ay = meta['anchor_tile']
    if piv == (ax * 32 + 16, ay * 32 + 16):
        return piv, TILE_CENTRE                                         # tile-centred (fields, circles)
    assert piv == (ax * 32 + 24, ay * 32 + 24), (meta['id'], piv)       # unit-centred: the feet point
    return piv, FEET


def select(frames, a, b, step):
    assert 0 <= a <= b < len(frames), (a, b, len(frames))
    return [clean_alpha(f) for f in frames[a:b + 1:step]]


def effect_strip(name, frames, anchor, point):
    while frames and not frames[-1][:, :, 3].any():
        frames = frames[:-1]
    while frames and not frames[0][:, :, 3].any():
        frames = frames[1:]
    assert frames and all(f[:, :, 3].any() for f in frames), (name, 'empty frame inside')
    left, top, right, bottom = bbox_tiles(frames, anchor, point)
    w, h = left + 1 + right, top + 1 + bottom
    assert w <= MAX_TILES and h <= MAX_TILES, (name, w, h)
    n = len(frames) + 1
    strip = np.zeros((h * 32, w * 32 * n, 4), np.uint8)
    for i, f in enumerate(frames):
        strip[:, i * w * 32:(i + 1) * w * 32] = place(f, anchor, point, left, top, w, h, name)
    return strip, w, h, n, right, bottom


def convert(srcs, pick):
    kind, name, sid, var, a, b, step, ms, note = pick
    meta, rows = load(srcs, sid, var)
    src = f'{sid}/{var} {a}-{b}' + (f' step {step}' if step > 1 else '')
    out = []
    if kind == 'effect':
        anchor, point = pivot_point(meta, kind)
        strip, w, h, n, dx, dy = effect_strip(name, select(rows[0], a, b, step), anchor, point)
        out.append((dict(kind='effect', name=name, file=f'pack27_fx/{name}.png', w=w, h=h, phases=n, ms=ms,
                         dx=dx, dy=dy, note=f'{note} (from {src})'), strip))
    elif kind == 'dirs':
        assert len(rows) == 8, name
        anchor, point = pivot_point(meta, 'effect')
        for d in OUR_DIRS:
            fr = select(rows[DIRS8.index(d)], a, b, step)
            strip, w, h, n, dx, dy = effect_strip(f'{name}_{d}', fr, anchor, point)
            out.append((dict(kind='effect', name=f'{name}_{d}', file=f'pack27_fx/{name}_{d}.png', w=w, h=h,
                             phases=n, ms=ms, dx=dx, dy=dy, note=f'{note}, towards {d} (from {src})'), strip))
    else:
        assert len(rows) == 8, name
        anchor, point = pivot_point(meta, 'missile')
        pats = {pat: select(rows[DIRS8.index(d)], a, b, step) for pat, d in MISSILE_DIR.items()}
        n = len(pats[(0, 0)])
        left, top, right, bottom = bbox_tiles([f for v in pats.values() for f in v], anchor, point)
        w, h = left + 1 + right, top + 1 + bottom
        assert w <= 3 and h <= 3, (name, w, h)
        W, H = w * 32, h * 32
        strip = np.zeros((3 * H, 3 * W * n, 4), np.uint8)
        for (x, y), fr in pats.items():
            for f, img in enumerate(fr):
                assert img[:, :, 3].any(), (name, 'empty missile frame')
                x0 = (x * n + f) * W
                strip[y * H:(y + 1) * H, x0:x0 + W] = place(img, anchor, point, left, top, w, h, name)
        out.append((dict(kind='missile', name=name, file=f'pack27_fx/{name}.png', w=w, h=h, phases=n, ms=ms,
                         dx=right, dy=bottom, note=f'{note} (from {src})'), strip))
    return out


def check_strip(row, strip):
    W, H, n = row['w'] * 32, row['h'] * 32, row['phases']
    if row['kind'] == 'missile':
        want = (3 * H, 3 * W * n)
    else:
        want = (H, W * n)
    if strip.shape[:2] != want:
        return [f"{row['name']}: size {strip.shape[:2]} != {want}"]
    errs = []
    al = strip[:, :, 3]
    if not np.isin(al, (0, 255)).all():
        errs.append(f"{row['name']}: alpha not 0 / 255")
    if row['kind'] == 'effect':
        for f in range(n):
            has = al[:, f * W:(f + 1) * W].any()
            if f < n - 1 and not has:
                errs.append(f"{row['name']}: frame {f} empty")
            if f == n - 1 and has:
                errs.append(f"{row['name']}: last frame not empty")
    if not (0 <= row['dx'] < row['w'] and 0 <= row['dy'] < row['h']):
        errs.append(f"{row['name']}: offset outside")
    return errs


def digest(strip):
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


FIELDS = ['kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note']


def spec_text(rows):
    buf = io.StringIO()
    wr = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    wr.writeheader()
    wr.writerows(rows)
    return buf.getvalue()


def sums_text(rows, strips):
    return ''.join(f"{digest(s)}  {r['file']}\n" for r, s in zip(rows, strips))


def read(path):
    return open(path, newline='').read() if os.path.exists(path) else None


def expected_names():
    """[(kind, name, source text, ms, note)] the spec must list, in order, from PICKS"""
    out = []
    for kind, name, sid, var, a, b, step, ms, note in PICKS:
        src = f'{sid}/{var} {a}-{b}' + (f' step {step}' if step > 1 else '')
        if kind == 'dirs':
            out += [('effect', f'{name}_{d}', ms, f'{note}, towards {d} (from {src})') for d in OUR_DIRS]
        else:
            out.append((kind, name, ms, f'{note} (from {src})'))
    return out


def check_without_art():
    ok = True
    spec, sums = read(SPEC), read(SUMS)
    if spec is None or sums is None:
        print('missing', SPEC if spec is None else SUMS)
        return False
    rows = list(csv.DictReader(io.StringIO(spec)))
    want = expected_names()
    if [(r['kind'], r['name']) for r in rows] != [(k, n) for k, n, _, _ in want]:
        print('spec names differ from PICKS')
        ok = False
    for r, (kind, name, ms, note) in zip(rows, want):
        exp = dict(file=f'pack27_fx/{name}.png', ms=str(ms), note=note)
        for k, v in exp.items():
            if r[k] != v:
                print(f'{name}: {k} = {r[k]!r}, PICKS says {v!r}')
                ok = False
        for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'):
            r[k] = int(r[k])
        lim = 3 if kind == 'missile' else MAX_TILES
        if not (1 <= r['w'] <= lim and 1 <= r['h'] <= lim and 0 <= r['dx'] < r['w'] and 0 <= r['dy'] < r['h']):
            print(f'{name}: bad size or offset')
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
            errs = check_strip(r, s)
            if digest(s) != sum_of.get(r['file']):
                errs.append(f"{r['name']}: strip differs from pack27_fx.sums")
            for e in errs:
                print(e)
            ok = ok and not errs
    print(f'pack27 fx check (no art sets): {len(rows)} specs, {found} strips on disk checked:',
          'OK' if ok else 'FAILED')
    return ok


def build(srcs, check):
    if not srcs:
        if not check:
            sys.exit('build needs --src (the art sets); without it only --check runs')
        return check_without_art()
    rows, strips, errs = [], [], []
    for p in PICKS:
        for r, s in convert(srcs, p):
            errs += check_strip(r, s)
            rows.append(r)
            strips.append(s)
    for e in errs:
        print(e)
    if errs:
        return False
    spec, sums = spec_text(rows), sums_text(rows, strips)
    if check:
        ok = read(SPEC) == spec and read(SUMS) == sums
        if not ok:
            print('spec or sums differ from a rebuild')
        for r, s in zip(rows, strips):
            p = os.path.join(ART, r['file'])
            if os.path.exists(p) and not np.array_equal(np.asarray(Image.open(p).convert('RGBA')), s):
                print(r['name'], 'strip differs from a rebuild')
                ok = False
        print('pack27 fx check:', 'OK' if ok else 'FAILED')
        return ok
    os.makedirs(OUT, exist_ok=True)
    for r, s in zip(rows, strips):
        Image.fromarray(s).save(os.path.join(ART, r['file']), optimize=True)
    open(SPEC, 'w', newline='').write(spec)
    open(SUMS, 'w', newline='').write(sums)
    for r in rows:
        print(f"{r['kind']} {r['name']}: {r['w']}x{r['h']}, offset {r['dx']},{r['dy']}, {r['phases']} x {r['ms']} ms")
    return True


def ground(W, H):
    bg = Image.new('RGBA', (W, H), (52, 46, 40, 255))
    d = ImageDraw.Draw(bg)
    for x in range(0, W, 32):
        d.line([(x, 0), (x, H)], fill=(66, 60, 52, 255))
    for y in range(0, H, 32):
        d.line([(0, y), (W, y)], fill=(66, 60, 52, 255))
    return bg, d


def preview(out):
    os.makedirs(out, exist_ok=True)
    rows = list(csv.DictReader(open(SPEC, newline='')))
    S = 3
    for r in rows:
        w, h, n = int(r['w']), int(r['h']), int(r['phases'])
        s = Image.open(os.path.join(ART, r['file'])).convert('RGBA')
        W, H = w * 32, h * 32
        frames = []
        for f in range(n):
            if r['kind'] == 'missile':                  # the east pattern (2, 1)
                art = s.crop(((2 * n + f) * W, H, (2 * n + f + 1) * W, 2 * H))
            else:
                art = s.crop((f * W, 0, (f + 1) * W, H))
            bg, d = ground(W, H)
            tx, ty = (w - 1 - int(r['dx'])) * 32, (h - 1 - int(r['dy'])) * 32
            d.rectangle([tx, ty, tx + 31, ty + 31], outline=(150, 120, 60, 255))     # the target tile
            bg.alpha_composite(art)
            frames.append(bg.resize((W * S, H * S), Image.NEAREST))
        sheet = Image.new('RGBA', (len(frames) * (W * S + 4), H * S), (20, 18, 22, 255))
        for i, f in enumerate(frames):
            sheet.paste(f, (i * (W * S + 4), 0))
        sheet.convert('RGB').save(os.path.join(out, r['name'] + '_frames.png'))
        g = [f.convert('RGB') for f in frames]
        g[0].save(os.path.join(out, r['name'] + '.gif'), save_all=True, append_images=g[1:],
                  duration=int(r['ms']), loop=0)
    print('preview:', out)


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
    preview(a.out)


if __name__ == '__main__':
    main()
