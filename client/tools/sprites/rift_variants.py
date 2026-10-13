#!/usr/bin/env python3
"""Rift monster variants: new looks painted over the frames of a rift look we already ship (same size, frame groups,
phases and timing as the base), ready for import_art_things.py.

python3 -I rift_variants.py extract --dat P/Tibia.dat --spr P/Tibia.spr --out BASE_DIR [--looks 2100,2101,...]
python3 -I rift_variants.py build --base BASE_DIR --raw RAW_DIR [--keys k1,k2] [--previews DIR]
python3 -I rift_variants.py check                   # the committed sheets and rows match the spec (no pair needed)

Spec: monster_looks/rift_variants.json (one entry per variant: key, planned look id, base look, theme, rank, name,
the PixelLab jobs that painted it with their prompts and seeds, and the post-processing numbers). The raw PixelLab
results stay out of git (RAW_DIR/<job tag>.json, the background job's response); the post-processed sheets are
committed: art_import/rift_variants/<key>.png, rows in art_import/rift_variants.csv (things.csv format, one outfit
row per variant) and monster_looks/rift_variant_picks.csv (the picks.csv rows of the looks, family riftvariant: append
them to picks.csv in the same step as the pair, as classlook_picks20.csv was; until then check_content.py's outfit
limit must not count them). Append them to a pair with the normal importer:
    python3 -I import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \
        --things art_import/rift_variants.csv --first-outfit <first look of the spec> --expect-items <items of P>
(the outfit rows are in look order; --first-outfit pads blank outfits up to the first id).

extract: every frame of the base looks as PNGs (BASE_DIR/<look>/g<group>_d<direction>_p<phase>.png, the client's
canvas of w x h tiles, the creature anchored bottom-right as the dat draws) and BASE_DIR/<look>/layout.json (frame
groups, sizes, exact sizes, phases, animator and flags).

build, deterministic (the same raw results and base frames give byte-identical sheets):
  1. the job's frames are put back on the base's canvas (a job may send a bottom-right crop of the canvas);
  2. alpha is cut to 0 / 255 (at 128) and specks under `speck` pixels (8-connected) are dropped;
  3. all frames are moved by one whole-pixel shift (up to 3 px each way): the one whose summed silhouette overlap with
     the base frames' opaque core is best, so the variant stands on the base's feet line and tile without jitter
     between frames (ties: the smallest shift, then x, then y; no shift unless it gains over 0.02 overlap per frame:
     the edits come back registered); the lowest opaque row of every frame is reported against the base's;
  4. grade: value x grade[0], saturation x grade[1] (the dark fantasy look of our pair);
  5. one palette for all frames of the variant: median cut to `colours` colours, every pixel snapped to it (no dither);
  6. outline: a silhouette edge pixel brighter than `outline` (luma) is darkened (x 0.45) and snapped again, so every
     creature keeps a dark rim on any floor;
  7. the sheet: one row per frame group and phase, one column per direction (north, east, south, west), cells of the
     base's canvas (import_art_things.py's outfit layout with layers=1).
--previews DIR: <key>_sheet.png (each direction a row: the base's idle and walk frames, then the variant's, 4x
nearest-neighbour on a dark checker) and <key>_walk.gif (the walk cycle in the four directions, 4x).
"""
import argparse, csv, io, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HERE, 'monster_looks', 'rift_variants.json')
OUT_DIR = os.path.join(HERE, 'art_import', 'rift_variants')
OUT_CSV = os.path.join(HERE, 'art_import', 'rift_variants.csv')
PICKS_OUT = os.path.join(HERE, 'monster_looks', 'rift_variant_picks.csv')
PICK_FIELDS = ['key', 'look', 'lib', 'lib_id', 'recolour', 'family', 'rank', 'monsters', 'description', 'edit']
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
DIRS = ('north', 'east', 'south', 'west')


# ------------------------------------------------------------------------------------------------------- extract
def cmd_extract(a):
    from datspr import Dat, Spr
    from import_outfits import parse_body, frame
    dat, spr = Dat(a.dat), Spr(a.spr)
    looks = [int(x) for x in a.looks.split(',')] if a.looks else sorted({v['base'] for v in load_spec()['variants']})
    for lk in looks:
        t = dat.outfit(lk)
        groups = parse_body(dat, t)
        o = os.path.join(a.out, str(lk))
        os.makedirs(o, exist_ok=True)
        lay = {'look': lk, 'flags': {k: v for k, v in t.flags.items() if not (k.startswith('x') and k[1:].isdigit())},
               'groups': []}
        for gi, g in enumerate(groups):
            assert g.layers == 1 and g.py == 1 and g.pz == 1 and g.px == 4, (lk, 'a plain creature look')
            lay['groups'].append({'type': g.gtype, 'w': g.w, 'h': g.h, 'exact': g.exact, 'phases': g.phases,
                                  'anim': list(g.anim[:3]) + [list(g.anim[3])] if g.anim else None})
            for d in range(4):
                for ph in range(g.phases):
                    Image.fromarray(frame(g, spr, d, 0, 0, ph)).save(os.path.join(o, f'g{gi}_d{d}_p{ph}.png'))
        with open(os.path.join(o, 'layout.json'), 'w') as f:
            json.dump(lay, f, indent=1, sort_keys=True)
        print(lk, [(g['w'], g['h'], g['phases']) for g in lay['groups']])


# ------------------------------------------------------------------------------------------------- post-process
def load_spec(path=SPEC):
    with open(path) as f:
        return json.load(f)


def decode_png(s):
    import base64
    if isinstance(s, dict):
        s = s['base64']
    if s.startswith('data:'):
        s = s.split(',', 1)[1]
    return np.asarray(Image.open(io.BytesIO(base64.b64decode(s))).convert('RGBA')).copy()


def cut_alpha(a, speck=4):
    """alpha to 0 / 255 at 128; 8-connected opaque islands under `speck` pixels dropped."""
    a = a.copy()
    on = a[..., 3] >= 128
    a[..., 3] = np.where(on, 255, 0)
    if speck > 1:
        H, W = on.shape
        seen = np.zeros_like(on)
        for y in range(H):
            for x in range(W):
                if on[y, x] and not seen[y, x]:
                    stack, comp = [(y, x)], []
                    seen[y, x] = True
                    while stack:
                        cy, cx = stack.pop()
                        comp.append((cy, cx))
                        for dy in (-1, 0, 1):
                            for dx in (-1, 0, 1):
                                ny, nx = cy + dy, cx + dx
                                if 0 <= ny < H and 0 <= nx < W and on[ny, nx] and not seen[ny, nx]:
                                    seen[ny, nx] = True
                                    stack.append((ny, nx))
                    if len(comp) < speck:
                        for cy, cx in comp:
                            a[cy, cx, 3] = 0
    a[a[..., 3] == 0] = 0
    return a


def shift(a, dx, dy):
    out = np.zeros_like(a)
    H, W = a.shape[:2]
    ys, yd = (slice(0, H - dy), slice(dy, H)) if dy >= 0 else (slice(-dy, H), slice(0, H + dy))
    xs, xd = (slice(0, W - dx), slice(dx, W)) if dx >= 0 else (slice(-dx, W), slice(0, W + dx))
    out[yd, xd] = a[ys, xs]
    return out


def iou(a, b):
    """silhouette overlap of a variant frame `a` and a base frame `b`; only the base's opaque core counts (several
    base looks have a soft glow halo that the variants do not keep)."""
    m, n = a[..., 3] > 0, b[..., 3] >= 250
    uni = np.logical_or(m, n).sum()
    return float(np.logical_and(m, n).sum() / uni) if uni else 0.0


def best_shift(pairs, reach=3, gain=0.02):
    """one whole-pixel shift for all (variant, base) frame pairs: the best summed silhouette overlap (IoU); ties: the
    smallest shift, then x, then y.
    PixelLab's edits keep the frames registered, so a shift is taken only when it gains more than `gain` overlap per
    frame on average over no shift."""
    best, zero = None, sum(iou(a, b) for a, b in pairs)
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            tot = sum(iou(shift(a, dx, dy), b) for a, b in pairs)
            k = (-round(tot, 6), abs(dx) + abs(dy), dx, dy)
            if best is None or k < best[0]:
                best = (k, dx, dy, tot)
    if best[3] - zero <= gain * len(pairs):
        return 0, 0
    return best[1], best[2]


def feet(a, core=1):
    rows = np.nonzero((a[..., 3] >= core).any(1))[0]
    return int(rows[-1]) if len(rows) else -1


def grade(a, value=1.0, sat=1.0):
    if value == 1.0 and sat == 1.0:
        return a
    rgb = a[..., :3].astype(np.float32)
    lum = (rgb * np.array([0.299, 0.587, 0.114], np.float32)).sum(-1, keepdims=True)
    rgb = (lum + (rgb - lum) * sat) * value
    out = a.copy()
    out[..., :3] = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    return out


def _median_cut(px, n):
    strip = Image.fromarray(px.reshape(1, -1, 3), 'RGB')
    q = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    used = sorted(set(np.asarray(q).ravel().tolist()))
    return np.array(q.getpalette()[:3 * 256], np.uint8).reshape(-1, 3)[used]


def palette_of(frames, n, accents=0):
    """median-cut palette of the opaque pixels of all frames, sorted dark to light: n - accents colours for the body,
    then up to `accents` colours cut from the saturated, bright pixels the body colours miss (glowing eyes, embers:
    few pixels, so a plain median cut merges them away)."""
    px = np.concatenate([f[f[..., 3] > 0][:, :3] for f in frames], 0)
    if len(px) == 0:
        return np.zeros((1, 3), np.uint8)
    pal = _median_cut(px, n - accents)
    if accents:
        f = px.astype(np.float32) / 255.0
        mx, mn = f.max(1), f.min(1)
        sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
        d = ((px[:, None, :].astype(np.int32) - pal[None].astype(np.int32)) ** 2).sum(-1).min(1)
        hot = px[(sat > 0.35) & (mx > 0.45) & (d > 24 ** 2)]
        if len(hot) >= 2:
            pal = np.concatenate([pal, _median_cut(hot, accents)], 0)
    pal = np.unique(pal, axis=0)
    order = np.argsort((pal.astype(np.int32) * np.array([299, 587, 114])).sum(1), kind='stable')
    return pal[order]


def snap(a, pal):
    out = a.copy()
    on = a[..., 3] > 0
    rgb = a[on][:, :3].astype(np.int32)
    d = ((rgb[:, None, :] - pal[None, :, :].astype(np.int32)) ** 2).sum(-1)
    out[on, :3] = pal[np.argmin(d, 1)]
    return out


def outline(a, pal, limit):
    if limit is None:
        return a
    on = a[..., 3] > 0
    pad = np.pad(on, 1)
    edge = on & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    luma = (a[..., :3].astype(np.float32) * np.array([0.299, 0.587, 0.114], np.float32)).sum(-1)
    hit = edge & (luma > limit)
    out = a.copy()
    out[hit, :3] = np.rint(a[hit, :3] * 0.45).astype(np.uint8)
    return snap(out, pal) if hit.any() else out


def process(v, base_dir, raw_dir):
    """{(group, direction, phase): RGBA array} of variant spec `v`, plus a report."""
    lk = v['base']
    lay = json.load(open(os.path.join(base_dir, str(lk), 'layout.json')))
    W = lay['groups'][0]['w'] * 32
    raw, base = {}, {}
    for job in v['jobs']:
        res = json.load(open(os.path.join(raw_dir, job['tag'] + '.json')))
        imgs = res['last_response']['images']
        assert len(imgs) == len(job['frames']), (v['key'], job['tag'], 'frame count')
        for name, s in zip(job['frames'], imgs):
            g, d, p = (int(x[1:]) for x in name.split('_'))
            im = decode_png(s)
            cv = np.zeros((W, W, 4), np.uint8)
            h, w = im.shape[:2]
            assert h <= W and w <= W, (v['key'], name, 'larger than the canvas')
            cv[W - h:, W - w:] = im                      # crops are bottom-right boxes of the canvas
            raw[(g, d, p)] = cv
    report = {'iou': {}, 'feet': {}}
    frames = {}
    for gi, g in enumerate(lay['groups']):
        for d in range(4):
            for p in range(g['phases']):
                k = (gi, d, p)
                assert k in raw, (v['key'], 'missing frame', k)
                b = np.asarray(Image.open(os.path.join(base_dir, str(lk), f'g{gi}_d{d}_p{p}.png')).convert('RGBA'))
                base[k] = b
                frames[k] = cut_alpha(raw[k], v.get('speck', 4))
    dx, dy = best_shift([(frames[k], base[k]) for k in frames])
    report['shift'] = (dx, dy)
    for k in frames:
        frames[k] = grade(shift(frames[k], dx, dy), *v.get('grade', [1.0, 1.0]))
        report['iou'][k] = round(iou(frames[k], base[k]), 3)
        report['feet'][k] = feet(frames[k]) - feet(base[k], 250)
    pal = palette_of(list(frames.values()), v.get('colours', 24), v.get('accents', 4))
    lim = v.get('outline', 80)
    for k in frames:
        frames[k] = outline(snap(frames[k], pal), pal, lim)
    report['colours'] = len({tuple(c) for f in frames.values() for c in f[f[..., 3] > 0][:, :3].tolist()})
    return lay, frames, base, report


def sheet(lay, frames):
    W = lay['groups'][0]['w'] * 32
    rows = sum(g['phases'] for g in lay['groups'])
    out = np.zeros((rows * W, 4 * W, 4), np.uint8)
    r = 0
    for gi, g in enumerate(lay['groups']):
        for p in range(g['phases']):
            for d in range(4):
                out[r * W:(r + 1) * W, d * W:(d + 1) * W] = frames[(gi, d, p)]
            r += 1
    return out


def things_row(v, lay):
    gs = lay['groups']
    W = gs[0]['w']
    ex = ['layers=1', 'gtypes=' + '+'.join(str(g['type']) for g in gs)]
    if W > 1 or gs[0]['h'] > 1:
        ex.append('exact=' + '+'.join(str(g['exact'] or 32 * max(g['w'], g['h'])) for g in gs))
    for gi, g in enumerate(gs):
        if g['anim']:
            asyn, loop, start, durs = g['anim']
            ex.append(f'durs{gi}=' + '/'.join(f'{durs[2 * i]}:{durs[2 * i + 1]}' for i in range(g['phases'])))
            ex.append(f'anim{gi}={asyn}:{loop}:{start}')
    flags = ' '.join(k for k, val in sorted(lay['flags'].items()) if val is True)
    return {'key': v['key'], 'cat': 'outfit', 'kind': 'creature', 'name': v['name'],
            'atlas': 'rift_variants/' + v['key'], 'x': 0, 'y': 0, 'w': W, 'h': gs[0]['h'], 'patterns': 4,
            'phases': '+'.join(str(g['phases']) for g in gs), 'flags': flags, 'mode': 'new', 'server_id': '',
            'extra': '|'.join(ex)}


def write_rows(spec, layouts, path=OUT_CSV):
    rows = [things_row(v, layouts[v['key']]) for v in sorted(spec['variants'], key=lambda v: v['look'])]
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, FIELDS, lineterminator='\n')
        w.writeheader()
        for r in rows:
            w.writerow(r)


def pick_rows(spec):
    """the picks.csv rows of the variants (family riftvariant: no monster file uses them, rift_config.lua
    looks.variants does; lib own: our art, painted over our look lib_id)."""
    return [{'key': v['key'], 'look': v['look'], 'lib': 'own', 'lib_id': v['base'], 'recolour': '', 'family': 'riftvariant',
             'rank': v['rank'], 'monsters': f"rift packs ({v['theme']}), {v['name']}",
             'description': v['description'], 'edit': 'pixellab-edit'}
            for v in sorted(spec['variants'], key=lambda v: v['look'])]


def write_picks(spec, path=PICKS_OUT):
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, PICK_FIELDS, lineterminator='\n')
        w.writeheader()
        for r in pick_rows(spec):
            w.writerow(r)


def checker(w, h, s=8):
    yy, xx = np.mgrid[0:h, 0:w]
    c = np.where(((yy // s) + (xx // s)) % 2 == 0, 34, 42).astype(np.uint8)
    return Image.fromarray(np.stack([c, c, c + 4, np.full_like(c, 255)], -1), 'RGBA')


def previews(v, lay, frames, base, out):
    os.makedirs(out, exist_ok=True)
    W = lay['groups'][0]['w'] * 32
    seq = [(gi, p) for gi, g in enumerate(lay['groups']) for p in range(g['phases'])]
    gap = 8
    cols = 2 * len(seq)
    im = checker(cols * W + gap, 4 * W)
    for d in range(4):
        for i, (gi, p) in enumerate(seq):
            im.alpha_composite(Image.fromarray(base[(gi, d, p)]), (i * W, d * W))
            im.alpha_composite(Image.fromarray(frames[(gi, d, p)]), (gap + (len(seq) + i) * W, d * W))
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).convert('RGB').save(
        os.path.join(out, v['key'] + '_sheet.png'))
    walk = len(lay['groups']) - 1
    n = lay['groups'][walk]['phases']
    gif = []
    for p in range(max(n, 2)):
        fr = checker(8 * W + gap, W)
        for d in range(4):
            fr.alpha_composite(Image.fromarray(base[(walk, d, p % n)]), (d * W, 0))
            fr.alpha_composite(Image.fromarray(frames[(walk, d, p % n)]), (gap + (4 + d) * W, 0))
        gif.append(fr.resize((fr.width * 4, fr.height * 4), Image.NEAREST).convert('RGB'))
    gif[0].save(os.path.join(out, v['key'] + '_walk.gif'), save_all=True, append_images=gif[1:], duration=160, loop=0)


def cmd_build(a):
    spec = load_spec(a.spec)
    keys = set(a.keys.split(',')) if a.keys else None
    os.makedirs(OUT_DIR, exist_ok=True)
    layouts = {}
    for v in spec['variants']:
        if keys and v['key'] not in keys:
            layouts[v['key']] = json.load(open(os.path.join(a.base, str(v['base']), 'layout.json')))
            continue
        lay, frames, base, rep = process(v, a.base, a.raw)
        layouts[v['key']] = lay
        Image.fromarray(sheet(lay, frames), 'RGBA').save(os.path.join(OUT_DIR, v['key'] + '.png'), optimize=False)
        low = min(rep['iou'].values())
        print(f"{v['key']}: look {v['look']} (base {v['base']}), {rep['colours']} colours, silhouette overlap with the "
              f"base {low:.2f}..{max(rep['iou'].values()):.2f}, shift {rep['shift']}, lowest row against the base "
              f"{min(rep['feet'].values())}..{max(rep['feet'].values())}")
        if a.previews:
            previews(v, lay, frames, base, a.previews)
    write_rows(spec, layouts)
    write_picks(spec)


def cmd_check(a):
    spec = load_spec(a.spec)
    bad = []
    looks = [v['look'] for v in spec['variants']]
    if looks != sorted(looks) or len(set(looks)) != len(looks) or looks[0] != spec['first_outfit']:
        bad.append('looks must be unique, ascending, the first = first_outfit')
    with open(OUT_CSV, newline='') as f:
        rows = {r['key']: r for r in csv.DictReader(f)}
    for v in spec['variants']:
        r = rows.get(v['key'])
        p = os.path.join(OUT_DIR, v['key'] + '.png')
        if not r or not os.path.exists(p):
            bad.append(v['key'] + ': no row or sheet')
            continue
        im = np.asarray(Image.open(p).convert('RGBA'))
        W = int(r['w']) * 32
        rows_n = sum(int(x) for x in r['phases'].split('+'))
        if im.shape[:2] != (rows_n * W, 4 * W):
            bad.append(f"{v['key']}: sheet {im.shape[:2]} is not {rows_n} x 4 cells of {W}")
        if not set(np.unique(im[..., 3]).tolist()) <= {0, 255}:
            bad.append(v['key'] + ': alpha is not 0 / 255')
        n = len({tuple(c) for c in im[im[..., 3] > 0][:, :3].tolist()})
        if n > v.get('colours', 24):
            bad.append(f"{v['key']}: {n} colours")
    with open(PICKS_OUT, newline='') as f:
        got = list(csv.DictReader(f))
    if got != [{k: str(v) for k, v in r.items()} for r in pick_rows(spec)]:
        bad.append('monster_looks/rift_variant_picks.csv is not the spec (run build)')
    for b in bad:
        print('PROBLEM', b)
    print('ok' if not bad else f'{len(bad)} problems')
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    e = sub.add_parser('extract')
    e.add_argument('--dat', required=True); e.add_argument('--spr', required=True); e.add_argument('--out', required=True)
    e.add_argument('--looks', default=None)
    b = sub.add_parser('build')
    b.add_argument('--base', required=True); b.add_argument('--raw', required=True)
    b.add_argument('--keys', default=None); b.add_argument('--previews', default=None)
    for p in (e, b, sub.add_parser('check')):
        p.add_argument('--spec', default=SPEC)
    a = ap.parse_args()
    if a.cmd == 'extract':
        cmd_extract(a)
    elif a.cmd == 'build':
        cmd_build(a)
    else:
        sys.exit(cmd_check(a))


if __name__ == '__main__':
    main()
