#!/usr/bin/env python3
"""Bigger guardians: 4x4 looks of our own rift and Omen guardians with an 8-frame walk and a 4-frame idle, painted with
PixelLab over our own frames of the guardian's look, ready for import_art_things.py. No sprite pair is built here.

python3 -I big_bosses.py build --base BASE_DIR --raw RAW_DIR [--keys k1,k2] [--previews DIR]
python3 -I big_bosses.py check                      # the committed sheets and rows match the spec (no pair needed)
(BASE_DIR: rift_variants.py extract output of the base looks: <look>/g<g>_d<d>_p<p>.png and layout.json.)

Spec: monster_looks/big_bosses.json, one entry per look: key, planned look id, base look, name, the PixelLab jobs
with prompts and seeds, the post-processing numbers. Per guardian:
  * `up` (only for a 3x3 base): "Edit images (Pro)" over our four idle frames (one per direction) scaled to the 128 px
    canvas: the same creature repainted at 4x4 with finer detail;
  * per direction `walk` and `idle`: "Animate with text (v3)" from that direction's idle frame (the repainted one, or
    our own for a 4x4 base): 8 walk frames and 4 idle frames. The first image of each result is the input frame and is
    not used.
The raw results stay out of git (RAW_DIR/<tag>.json); the post-processed sheets are committed:
art_import/big_bosses/<key>.png, rows in art_import/big_bosses.csv (things.csv format, one outfit row per look) and
monster_looks/big_boss_picks.csv (picks.csv rows, family bigguardian; append them to picks.csv in the same step as the
pair). Server use: rift_config.lua looks.bigGuardians, switch looks.bigGuardiansOn (off).

build, deterministic (the same raw results and base frames give byte-identical sheets):
  1. every frame on the 128 px canvas, alpha cut to 0 / 255 and specks dropped (rift_variants.cut_alpha);
  2. one whole-pixel shift per direction, the same for all its walk and idle frames, so the frames stand where the
     direction's source frame stands (the animation results drift a little); then one vertical shift per look that
     puts the source frames' lowest row on the feet line: the base's lowest row, moved to the bottom-right 4x4 canvas;
  3. grade, one palette for all frames of the look (median cut, glow accents kept), a dark rim on bright edges
     (rift_variants.palette_of / snap / outline);
  4. the sheet: idle phases 0-3 then walk phases 0-7, one row each, one column per direction (north, east, south, west),
     128 px cells (import_art_things.py's outfit layout with layers=1); groups idle (type 0) and walk (type 1),
     exact 128, 300 ms per phase.
--previews DIR: <key>_walk.gif (the current look's walk next to the new walk, the four directions, 3x),
<key>_idle.gif and <key>_sheet.png (3x).
"""
import argparse, csv, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import rift_variants as RV

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HERE, 'monster_looks', 'big_bosses.json')
OUT_DIR = os.path.join(HERE, 'art_import', 'big_bosses')
OUT_CSV = os.path.join(HERE, 'art_import', 'big_bosses.csv')
PICKS_OUT = os.path.join(HERE, 'monster_looks', 'big_boss_picks.csv')
TILES = 4
W = 32 * TILES
IDLE, WALK = 4, 8
DUR = 300


def load_spec(path=SPEC):
    with open(path) as f:
        return json.load(f)


def layout():
    """the new look's frame groups: idle (4 phases) and walk (8 phases), 4x4"""
    anim = lambda n: [0, 0, 0, [DUR] * (2 * n)]
    return {'flags': {}, 'groups': [
        {'type': 0, 'w': TILES, 'h': TILES, 'exact': W, 'phases': IDLE, 'anim': anim(IDLE)},
        {'type': 1, 'w': TILES, 'h': TILES, 'exact': W, 'phases': WALK, 'anim': anim(WALK)}]}


def on_canvas(a):
    """a frame on the 128 px canvas, anchored bottom-right as the dat draws"""
    h, w = a.shape[:2]
    assert h <= W and w <= W, 'larger than the 4x4 canvas'
    cv = np.zeros((W, W, 4), np.uint8)
    cv[W - h:, W - w:] = a
    return cv


def images(raw_dir, tag):
    with open(os.path.join(raw_dir, tag + '.json')) as f:
        res = json.load(f)
    return [RV.decode_png(s) for s in res['last_response']['images']]


def base_frame(base_dir, look, g, d, p):
    return np.asarray(Image.open(os.path.join(base_dir, str(look), f'g{g}_d{d}_p{p}.png')).convert('RGBA'))


def feet_line(base_dir, look):
    """the base's lowest opaque row (idle, all directions), on the 4x4 canvas"""
    lay = json.load(open(os.path.join(base_dir, str(look), 'layout.json')))
    bw = lay['groups'][0]['w'] * 32
    return max(RV.feet(base_frame(base_dir, look, 0, d, 0), 250) for d in range(4)) + (W - bw)


def sources(v, base_dir, raw_dir):
    """the four source frames (north, east, south, west) the animations started from"""
    up = v.get('up')
    if up:
        return [on_canvas(RV.cut_alpha(a, v.get('speck', 4))) for a in images(raw_dir, up['tag'])[:4]]
    return [on_canvas(RV.cut_alpha(base_frame(base_dir, v['base'], 0, d, 0), v.get('speck', 4))) for d in range(4)]


def grow(mask, n):
    """the mask dilated by n pixels (8-connected)"""
    m = mask.copy()
    for _ in range(n):
        p = np.pad(m, 1)
        m = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:] | p[:-2, :-2] | p[:-2, 2:] \
            | p[2:, :-2] | p[2:, 2:]
    return m


def clip_to(a, ref, n):
    """drop the opaque pixels of `a` further than n px from `ref`'s silhouette, and then any island that is left
    under 12 pixels: the animations sometimes add loose sparks or props away from the body"""
    keep = grow(ref[..., 3] > 0, n)
    out = a.copy()
    out[~keep] = 0
    return RV.cut_alpha(out, 12)


def process(v, base_dir, raw_dir):
    """{(group, direction, phase): RGBA array} of spec entry `v`, plus a report"""
    src = sources(v, base_dir, raw_dir)
    frames, report = {}, {'shift': {}, 'iou': {}}
    for d in range(4):
        walk = images(raw_dir, v['walk'][d]['tag'])[1:1 + WALK]
        idle = images(raw_dir, v['idle'][d]['tag'])[1:1 + IDLE]
        assert len(walk) == WALK and len(idle) == IDLE, (v['key'], d, 'frame count', len(walk), len(idle))
        got = [(0, p, a) for p, a in enumerate(idle)] + [(1, p, a) for p, a in enumerate(walk)]
        got = [(g, p, RV.cut_alpha(on_canvas(a), v.get('speck', 4))) for g, p, a in got]
        ref = src[d].copy()
        ref[..., 3] = np.where(ref[..., 3] > 0, 255, 0)
        dx, dy = RV.best_shift([(a, ref) for _, _, a in got])
        report['shift'][d] = (dx, dy)
        for g, p, a in got:
            frames[(g, d, p)] = clip_to(RV.shift(a, dx, dy), ref, v.get('reach', 8))
            report['iou'][(g, d, p)] = round(RV.iou(frames[(g, d, p)], ref), 3)
    low = max(RV.feet(s) for s in src)
    fy = int(np.clip(feet_line(base_dir, v['base']) - low, -8, 8)) if v.get('feet', True) else 0
    report['feet_shift'] = fy
    for k in frames:
        frames[k] = RV.grade(RV.shift(frames[k], 0, fy), *v.get('grade', [1.0, 1.0]))
    pal = RV.palette_of(list(frames.values()), v.get('colours', 32), v.get('accents', 4))
    for k in frames:
        frames[k] = RV.outline(RV.snap(frames[k], pal), pal, v.get('outline', 80))
    report['colours'] = len({tuple(c) for f in frames.values() for c in f[f[..., 3] > 0][:, :3].tolist()})
    return frames, report


def things_row(v):
    r = RV.things_row(v, layout())
    r['atlas'] = 'big_bosses/' + v['key']
    return r


def write_rows(spec, path=OUT_CSV):
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, RV.FIELDS, lineterminator='\n')
        w.writeheader()
        for v in sorted(spec['looks'], key=lambda v: v['look']):
            w.writerow(things_row(v))


def pick_rows(spec):
    """picks.csv rows (family bigguardian: no monster file uses them, rift_config.lua looks.bigGuardians does; lib own:
    our art, painted over our look lib_id)"""
    return [{'key': v['key'], 'look': v['look'], 'lib': 'own', 'lib_id': v['base'], 'recolour': '',
             'family': 'bigguardian', 'rank': 'guardian', 'monsters': v['monsters'], 'description': v['description'],
             'edit': 'pixellab-animate'} for v in sorted(spec['looks'], key=lambda v: v['look'])]


def write_picks(spec, path=PICKS_OUT):
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, RV.PICK_FIELDS, lineterminator='\n')
        w.writeheader()
        for r in pick_rows(spec):
            w.writerow(r)


def previews(v, frames, base_dir, out, scale=3):
    os.makedirs(out, exist_ok=True)
    lay = json.load(open(os.path.join(base_dir, str(v['base']), 'layout.json')))
    bg = len(lay['groups']) - 1
    bn = lay['groups'][bg]['phases']
    gap = 16

    def strip(get_old, get_new):
        fr = RV.checker(8 * W + gap, W)
        for d in range(4):
            fr.alpha_composite(Image.fromarray(on_canvas(get_old(d))), (d * W, 0))
            fr.alpha_composite(Image.fromarray(get_new(d)), (gap + (4 + d) * W, 0))
        return fr.resize((fr.width * scale, fr.height * scale), Image.NEAREST).convert('RGB')

    walk = [strip(lambda d, p=p: base_frame(base_dir, v['base'], bg, d, p % bn), lambda d, p=p: frames[(1, d, p)])
            for p in range(WALK)]
    walk[0].save(os.path.join(out, v['key'] + '_walk.gif'), save_all=True, append_images=walk[1:], duration=DUR // 2,
                 loop=0)
    idle = [strip(lambda d: base_frame(base_dir, v['base'], 0, d, 0), lambda d, p=p: frames[(0, d, p)])
            for p in range(IDLE)]
    idle[0].save(os.path.join(out, v['key'] + '_idle.gif'), save_all=True, append_images=idle[1:], duration=DUR,
                 loop=0)
    sh = Image.fromarray(RV.sheet(layout(), frames), 'RGBA')
    bgim = RV.checker(sh.width, sh.height)
    bgim.alpha_composite(sh)
    bgim.resize((sh.width * 2, sh.height * 2), Image.NEAREST).convert('RGB').save(
        os.path.join(out, v['key'] + '_sheet.png'))


def cmd_build(a):
    spec = load_spec(a.spec)
    keys = set(a.keys.split(',')) if a.keys else None
    os.makedirs(OUT_DIR, exist_ok=True)
    for v in spec['looks']:
        if keys and v['key'] not in keys:
            continue
        frames, rep = process(v, a.base, a.raw)
        Image.fromarray(RV.sheet(layout(), frames), 'RGBA').save(os.path.join(OUT_DIR, v['key'] + '.png'))
        vals = list(rep['iou'].values())
        print(f"{v['key']}: look {v['look']} (base {v['base']}), {rep['colours']} colours, shifts {rep['shift']}, feet "
              f"{rep['feet_shift']:+d}, overlap with the source frame {min(vals):.2f}..{max(vals):.2f}")
        if a.previews:
            previews(v, frames, a.base, a.previews)
    write_rows(spec)
    write_picks(spec)


def cmd_check(a):
    spec = load_spec(a.spec)
    bad = []
    looks = [v['look'] for v in spec['looks']]
    if looks != sorted(looks) or len(set(looks)) != len(looks) or looks[0] != spec['first_outfit']:
        bad.append('looks must be unique, ascending, the first = first_outfit')
    with open(OUT_CSV, newline='') as f:
        rows = {r['key']: r for r in csv.DictReader(f)}
    for v in spec['looks']:
        r = rows.get(v['key'])
        p = os.path.join(OUT_DIR, v['key'] + '.png')
        if not r or not os.path.exists(p):
            bad.append(v['key'] + ': no row or sheet')
            continue
        if r != {k: str(x) for k, x in things_row(v).items()}:
            bad.append(v['key'] + ': things row is not the spec (run build)')
        im = np.asarray(Image.open(p).convert('RGBA'))
        if im.shape[:2] != ((IDLE + WALK) * W, 4 * W):
            bad.append(f"{v['key']}: sheet {im.shape[:2]} is not {IDLE + WALK} x 4 cells of {W}")
        if not set(np.unique(im[..., 3]).tolist()) <= {0, 255}:
            bad.append(v['key'] + ': alpha is not 0 / 255')
        n = len({tuple(c) for c in im[im[..., 3] > 0][:, :3].tolist()})
        if n > v.get('colours', 32) + v.get('accents', 4):
            bad.append(f"{v['key']}: {n} colours")
        for i in range(IDLE + WALK):
            for d in range(4):
                if not im[i * W:(i + 1) * W, d * W:(d + 1) * W, 3].any():
                    bad.append(f"{v['key']}: empty cell row {i} direction {d}")
    if len(rows) != len(spec['looks']):
        bad.append('art_import/big_bosses.csv has rows that are not in the spec')
    with open(PICKS_OUT, newline='') as f:
        got = list(csv.DictReader(f))
    if got != [{k: str(x) for k, x in r.items()} for r in pick_rows(spec)]:
        bad.append('monster_looks/big_boss_picks.csv is not the spec (run build)')
    for b in bad:
        print('PROBLEM', b)
    print('ok' if not bad else f'{len(bad)} problems')
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--base', required=True); b.add_argument('--raw', required=True)
    b.add_argument('--keys', default=None); b.add_argument('--previews', default=None)
    for p in (b, sub.add_parser('check')):
        p.add_argument('--spec', default=SPEC)
    a = ap.parse_args()
    if a.cmd == 'build':
        cmd_build(a)
    else:
        sys.exit(cmd_check(a))


if __name__ == '__main__':
    main()
