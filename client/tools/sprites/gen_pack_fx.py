#!/usr/bin/env python3
"""Short one-shot cuts of the oblique spell effect set for procs, ticks and the reflect (ChaosPackFx uses).

    python3 -I gen_pack_fx.py build --src DIR            # -> art_import/pack_fx/<name>.png + art_import/pack_fx.csv
                                                         #    + art_import/pack_fx.sums
    python3 -I gen_pack_fx.py build --src DIR --check    # rebuild in memory, compare with the spec, the sums and the
                                                         #    strips on disk (when they are there)
    python3 -I gen_pack_fx.py build --check              # without the art set (CI): the spec and the sums match the
                                                         #    PICKS table below; strips on disk match the sums
    python3 -I gen_pack_fx.py preview --out DIR          # every strip 3x on a ground with the tile grid + GIFs

The source is the oblique spell effect set that import_vfx.py reads (--src-spells there: metadata.json +
oblique/32px/<category>/<id>.png). All 68 of its effects are already in the pair as full loops (effects 429-558,
missiles 126-133, auras; data/spells/README_FX.md "Animated pack effects"). Its status loops run 1.3-2 s, too long for
something sent on every proc or damage tick, and its shield bubble is a 2 s loop. This script cuts them into short
one-shots: frames a..b of the combined layer (the set's own `all` sheet), alpha made clean (0 / 255; the set's soft
glows, alpha 1..254, become an ordered 4x4 dither of the same colour), the last three frames dissolve in the same
dither (3/4, 1/2, 1/4 of the pixels kept), placed like import_vfx.py places the set (the
set's feet point on our feet point (14, 20) of the target tile), cut to whole tiles, and an empty last frame added.

The art set's licence allows use in a game, modified or not, and forbids redistributing the assets themselves, also
modified. So neither the set nor these strips are committed: art_import/pack_fx/ is ignored by git, and the committed
art_import/pack_fx.sums holds the sha256 of every strip's decoded RGBA pixels (PNG bytes depend on the zlib build), so
a rebuild can be checked without the art. Deterministic: no randomness; made with Pillow 12.3.0 and numpy 2.5.3.

Rules every strip is checked against (build stops otherwise): alpha 0 / 255; every frame but the last has art; the
last frame is empty; at most 4x4 tiles; the send offset (dx, dy) lies inside the thing.
Append to the next pair with import_fx_art.py (client/MANIFEST.md "Pack effect cuts"); server side
server/data/lib/chaos_pack_fx.lua (which use sends which effect, behind the switch ChaosPackFx.PACK_FX).
"""
import argparse
import csv
import hashlib
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'pack_fx')
SPEC = os.path.join(ART, 'pack_fx.csv')
SUMS = os.path.join(ART, 'pack_fx.sums')
FADE = 3                      # last frames of a cut that dissolve (ordered dither) before the empty frame
FEET = (14, 20)               # import_vfx.PLACE['feet']: where the set's feet point goes on the target tile

# name, source effect, first and last source frame, ms per frame, note (spec order = id order)
PICKS = [
    ('reflect_bubble', 'shield_bubble', 0, 7, 70, 'reflect: a hex shield bubble flashes round the creature and is gone'),
    ('tick_bleed', 'bleeding', 0, 11, 70, 'tick: blood bursts from the wound (bleed proc, crit wounds)'),
    ('tick_burn', 'burning', 0, 11, 70, 'tick: flames lick up the body, a puff of smoke (ignite proc, cinder mark)'),
    ('tick_poison', 'poisoned', 0, 11, 70, 'tick: green venom drips, a small skull (poison proc, festering wounds)'),
    ('tick_chill', 'frozen', 0, 9, 70, 'tick: ice crystals grow over the body and break (chill proc)'),
    ('tick_curse', 'cursed', 0, 11, 70, 'tick: a violet eye sigil and curse runes circle the body'),
    ('tick_regen', 'regenerating', 0, 11, 70, 'tick: green crosses and a leaf vine rise round the body (heal pulse)'),
]

BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0


def dissolve(fr, keep):
    """keep a Bayer-ordered share `keep` (0..1) of the art: a pixel-art fade out"""
    h, w = fr.shape[:2]
    thr = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    out = fr.copy()
    out[thr >= keep] = 0
    return out


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


def load_set(src):
    import json
    meta = {e['id']: e for e in json.load(open(os.path.join(src, 'metadata.json')))['effects']}

    def frames(sid):
        e = meta[sid]
        v = e['variants']['oblique/32']
        assert v['tile'] == 32 and v['rows'] == 1, sid
        fw, fh = v['frame_w'], v['frame_h']
        sheet = np.asarray(Image.open(os.path.join(src, v['files']['all'])).convert('RGBA'))
        fr = [sheet[0:fh, i * fw:(i + 1) * fw].copy() for i in range(e['frames'])]
        ax, ay = v['anchor_tile']
        return fr, (ax * 32 + 24, ay * 32 + 24)          # the set's oblique feet point
    return frames


def bbox_tiles(frames, anchor):
    x0 = y0 = 10 ** 6
    x1 = y1 = -10 ** 6
    for fr in frames:
        al = fr[:, :, 3] > 0
        if not al.any():
            continue
        ys, xs = np.nonzero(al)
        ox, oy = FEET[0] - anchor[0], FEET[1] - anchor[1]
        x0, x1 = min(x0, xs.min() + ox), max(x1, xs.max() + 1 + ox)
        y0, y1 = min(y0, ys.min() + oy), max(y1, ys.max() + 1 + oy)
    t = lambda v: int(-(-max(0, v) // 32))
    return t(-x0), t(-y0), t(x1 - 32), t(y1 - 32)


def convert(frames_of, pick):
    name, sid, a, b, ms, note = pick
    src, anchor = frames_of(sid)
    assert 0 <= a <= b < len(src), (name, len(src))
    fr = [clean_alpha(f) for f in src[a:b + 1]]
    for j in range(FADE):                                   # the last FADE frames dissolve: 3/4, 1/2, 1/4 kept
        fr[len(fr) - FADE + j] = dissolve(fr[len(fr) - FADE + j], (FADE - j) / (FADE + 1))
    left, top, right, bottom = bbox_tiles(fr, anchor)
    w, h = left + 1 + right, top + 1 + bottom
    assert w <= 4 and h <= 4, (name, w, h)
    px, py = left * 32 + FEET[0] - anchor[0], top * 32 + FEET[1] - anchor[1]
    strip = np.zeros((h * 32, w * 32 * (len(fr) + 1), 4), np.uint8)
    for i, f in enumerate(fr):
        fh, fw = f.shape[:2]
        cv = np.zeros((h * 32 + 2 * fh, w * 32 + 2 * fw, 4), np.uint8)       # padded: art outside is cut, checked
        cv[fh + py:fh + py + fh, fw + px:fw + px + fw] = f
        tile = cv[fh:fh + h * 32, fw:fw + w * 32]
        assert (tile[:, :, 3] > 0).sum() == (f[:, :, 3] > 0).sum(), (name, 'art clipped')
        strip[:, i * w * 32:(i + 1) * w * 32] = tile
    row = dict(kind='effect', name=name, file=f'pack_fx/{name}.png', w=w, h=h, phases=len(fr) + 1, ms=ms,
               dx=right, dy=bottom, note=f'{note} (cut of {sid} {a}-{b})')
    return row, strip


def check_strip(row, strip):
    W, H, n = row['w'] * 32, row['h'] * 32, row['phases']
    errs = []
    if strip.shape[:2] != (H, W * n):
        return [f"{row['name']}: size {strip.shape[:2]} != {(H, W * n)}"]
    al = strip[:, :, 3]
    if not np.isin(al, (0, 255)).all():
        errs.append(f"{row['name']}: alpha not 0 / 255")
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


def check_without_art():
    """the committed spec and sums against PICKS; strips on disk (if any) against the sums"""
    ok = True
    spec = read(SPEC)
    sums = read(SUMS)
    if spec is None or sums is None:
        print('missing', SPEC if spec is None else SUMS)
        return False
    rows = list(csv.DictReader(io.StringIO(spec)))
    names = [p[0] for p in PICKS]
    if [r['name'] for r in rows] != names:
        print('spec names differ from PICKS:', [r['name'] for r in rows], names)
        ok = False
    for r, p in zip(rows, PICKS):
        name, sid, a, b, ms, note = p
        want = dict(kind='effect', file=f'pack_fx/{name}.png', phases=str(b - a + 2), ms=str(ms),
                    note=f'{note} (cut of {sid} {a}-{b})')
        for k, v in want.items():
            if r[k] != v:
                print(f'{name}: {k} = {r[k]!r}, PICKS says {v!r}')
                ok = False
        for k in ('w', 'h', 'dx', 'dy'):
            r[k] = int(r[k])
        r['phases'] = int(r['phases'])
        r['ms'] = int(r['ms'])
        if not (1 <= r['w'] <= 4 and 1 <= r['h'] <= 4 and 0 <= r['dx'] < r['w'] and 0 <= r['dy'] < r['h']):
            print(f'{name}: bad size or offset')
            ok = False
    sum_of = {}
    for line in sums.splitlines():
        h, f = line.split('  ', 1)
        sum_of[f] = h
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
                errs.append(f"{r['name']}: strip differs from pack_fx.sums")
            for e in errs:
                print(e)
            ok = ok and not errs
    print(f'pack fx check (no art set): {len(rows)} specs, {found} strips on disk checked:', 'OK' if ok else 'FAILED')
    return ok


def build(src, check):
    if not src:
        if not check:
            sys.exit('build needs --src (the art set); without it only --check runs')
        return check_without_art()
    frames_of = load_set(src)
    rows, strips, errs = [], [], []
    for p in PICKS:
        r, s = convert(frames_of, p)
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
        print('pack fx check:', 'OK' if ok else 'FAILED')
        return ok
    os.makedirs(OUT, exist_ok=True)
    for r, s in zip(rows, strips):
        Image.fromarray(s).save(os.path.join(ART, r['file']), optimize=True)
    open(SPEC, 'w', newline='').write(spec)
    open(SUMS, 'w', newline='').write(sums)
    for r in rows:
        print(f"{r['name']}: {r['w']}x{r['h']}, offset {r['dx']},{r['dy']}, {r['phases']} x {r['ms']} ms")
    return True


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
            bg = Image.new('RGBA', (W, H), (52, 46, 40, 255))
            d = ImageDraw.Draw(bg)
            for x in range(0, W, 32):
                d.line([(x, 0), (x, H)], fill=(66, 60, 52, 255))
            for y in range(0, H, 32):
                d.line([(0, y), (W, y)], fill=(66, 60, 52, 255))
            tx, ty = (w - 1 - int(r['dx'])) * 32, (h - 1 - int(r['dy'])) * 32
            d.rectangle([tx, ty, tx + 31, ty + 31], outline=(150, 120, 60, 255))     # the target tile
            bg.alpha_composite(s.crop((f * W, 0, (f + 1) * W, H)))
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
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    a = ap.parse_args()
    if a.cmd == 'build':
        sys.exit(0 if build(a.src, a.check) else 1)
    preview(a.out)


if __name__ == '__main__':
    main()
