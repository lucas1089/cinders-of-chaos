#!/usr/bin/env python3
"""Pickup looks: three PixelLab pictures, 32 x 32, become client items 44396-44398 (pair 55, client/MANIFEST.md "Pair 55").
The ground pickups of server/data/scripts/chaos/pickups_config.lua wore stock sprites; they get looks of their own:
44396 the Ember Blessing pickup (server 32090; wore the Ember Orb sprite 25045), a violet arcane portal in a carved stone ring;
44397 the health globe (server 32088; wore the stock health potion 7618), a red glass globe on a dark base;
44398 the mana globe (server 32089; wore the stock mana potion 7620), the same globe in blue. The Ember Orb item
(server/data/lib/chaos_orbs_config.lua) keeps 25045. (The file keeps its first name, gen_portal_art.py.)

    python3 -I gen_portal_art.py build [--src KEY=FILE ...] [--check] [--preview DIR --dat P/Tibia.dat --spr P/Tibia.spr]

Owner approved PixelLab results (32 x 32 RGBA, alpha 0 / 255; docs/CREDITS.md "Tools"), 2026-10-28:
- ember_portal: create_image_pro job 66b816c8-5244-4cc7-b765-b7903d98ba81, index 11.
- health_globe: create_image_pro job 453273cc-5c1c-4f4e-862d-4a30a4e27ef1, index 0 (red glass globe on a dark base, style
  reference the portal art).
- mana_globe: the health globe with its red hues turned to blue, owner approved so both globes match: per pixel HLS, hue + 0.62
  where saturation > 0.25 and (hue < 0.08 or hue > 0.9), lightness and saturation kept (`recolour_blue`; the committed source
  differs from that function by at most 1 per channel, rounding; the test checks it).
The pixels are PixelLab's, owner approved: nothing is repainted, snapped or recoloured here (only the colour under fully
transparent pixels is cleared). `build --src KEY=FILE` (repeatable) takes a picture, checks it and copies it to
art_import/portal/KEY.png (the committed source); without --src the committed copies are used (CI).

Outputs (committed): art_import/portal.png (the atlas, three 32 px cells side by side, in LOOKS order),
art_import/portal.csv (the things file of import_art_things.py: 1 x 1, one phase, flags stackable, mode new) and
art_import/portal.sums (sha256 of the decoded pixels of each source and of the atlas). `--check` (CI) rebuilds from the
committed sources and compares, writes nothing. Flags are `stackable` only (not copied from the stock looks, which are
multi-use and pickupable: a ground pickup is neither; the server nodes are stackable, the 10.98 client reads a count for a
stackable look).

Style: docs/SPRITE_STYLE.md wants one theme palette. These looks use their own colours and the owner approved the pixels,
so they are not snapped. `build` runs the style check on each canvas against its own colours: every rule but the theme
palette must pass or `build` refuses; the light rule is a warning. Deterministic: numpy and Pillow only.
"""
import argparse, csv, hashlib, io, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SRC_DIR = os.path.join(ART, 'portal')
LOOKS = [   # (key, kind, item name, client id, server id); client ids follow the last item of pair 54 (44395)
    ('ember_portal', 'portal', 'ember pickup portal', 44396, 32090),   # the Ember Blessing ground pickup
    ('health_globe', 'globe', 'health globe pickup', 44397, 32088),
    ('mana_globe', 'globe', 'mana globe pickup', 44398, 32089),
]
KEYS = [l[0] for l in LOOKS]
FIRST_ID = LOOKS[0][3]
SRC_DIR = os.path.join(ART, 'portal')
ATLAS = os.path.join(ART, 'portal.png')
THINGS = os.path.join(ART, 'portal.csv')
SUMS = os.path.join(ART, 'portal.sums')
CELL = 32
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']


def src_path(key):
    return os.path.join(SRC_DIR, key + '.png')


def read_rgba(path):
    """the picture as RGBA; the colour under fully transparent pixels is cleared (PixelLab leaves noise there, nothing
    visible changes: the importer treats alpha 0 as empty)"""
    a = np.array(Image.open(path).convert('RGBA'))
    a[a[..., 3] == 0] = 0
    return a


def recolour_blue(a):
    """the mana globe from the health globe: per pixel HLS, hue + 0.62 where saturation > 0.25 and (hue < 0.08 or hue > 0.9),
    lightness and saturation kept. The committed mana_globe.png is the owner-approved result of this rule (within 1 per
    channel of this function); it is not rebuilt from it."""
    import colorsys
    o = a.copy()
    for y, x in zip(*np.nonzero(a[..., 3])):
        h, l, s = colorsys.rgb_to_hls(*(int(v) / 255.0 for v in a[y, x, :3]))
        if s > 0.25 and (h < 0.08 or h > 0.9):
            o[y, x, :3] = [int(v * 255) for v in colorsys.hls_to_rgb((h + 0.62) % 1.0, l, s)]
    return o


def problems_of(a):
    """why a picture cannot be a 32 x 32 item canvas ([] = fine)"""
    if a.shape[:2] != (CELL, CELL):
        return ['size %d x %d, not %d x %d' % (a.shape[1], a.shape[0], CELL, CELL)]
    out = []
    al = a[..., 3]
    if ((al != 0) & (al != 255)).any():
        out.append('semi-transparent pixels (alpha must be 0 or 255)')
    if not (al == 255).any():
        out.append('empty')
    else:
        ys, xs = np.nonzero(al)
        if ys.max() - ys.min() < 18 or xs.max() - xs.min() < 18:
            out.append('the art does not fill the canvas (a ring or globe is about 24 wide)')
    if (a[al == 0][:, :3] != 0).any():
        out.append('colour under transparent pixels')
    return out


def style_report(a):
    """(reasons that stop the build, warnings, colour count); the palette rule is judged against the canvas's own colours"""
    data = sc.load_palettes()
    own = np.unique(a[a[..., 3] > 0][:, :3], axis=0)
    bad, warn = sc.judge(sc.measure(a), own, data['light']['global'], data['thresholds'])
    return bad, warn, own.shape[0]


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def build(srcs):
    """srcs: {key: path}. (atlas RGBA or None, things text, sums text, {key: (errors, style bad, warnings, colours)})"""
    cells, reports = [], {}
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    sums = ''
    for i, (key, kind, name, _cid, sid) in enumerate(LOOKS):
        a = read_rgba(srcs[key])
        errs = problems_of(a)
        bad, warn, ncol = style_report(a) if not errs else ([], [], 0)
        reports[key] = (errs, bad, warn, ncol)
        cells.append(a)
        w.writerow([key, 'item', kind, name, 'portal', i * CELL, 0, 1, 1, 1, 1, 'stackable', 'new', sid, ''])
        sums += '%s  portal/%s.png\n' % (digest(a), key)
    ok = not any(r[0] for r in reports.values())
    atlas = np.concatenate(cells, axis=1) if ok else None
    if ok:
        sums += '%s  portal.png\n' % digest(atlas)
    return atlas, out.getvalue(), sums, reports


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(outdir, dat, spr):
    """pickup_looks.png: the items as the client draws them from the pair, 4x and 1x, on a dark and a light ground"""
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    pad, z = 8, 4
    W, H = len(LOOKS) * (CELL * z + pad) + pad, CELL * z + CELL + 3 * pad
    im = Image.new('RGBA', (2 * W, H))
    for side, bg in enumerate(((40, 36, 34, 255), (214, 200, 170, 255))):
        im.paste(Image.new('RGBA', (W, H), bg), (side * W, 0))
        for i, look in enumerate(LOOKS):
            f = render_item(d, s, look[3]).convert('RGBA')
            assert f.size == (CELL, CELL), (look[3], f.size)
            x = side * W + pad + i * (CELL * z + pad)
            im.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (x, pad))
            im.alpha_composite(f, (x + (CELL * z - CELL) // 2, CELL * z + 2 * pad))
    p = os.path.join(outdir, 'pickup_looks.png')
    im.convert('RGB').save(p)
    print('preview', p)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--src', action='append', default=[], metavar='KEY=FILE',
                    help='a PixelLab picture for one look (%s); copied to art_import/portal/KEY.png' % ', '.join(KEYS))
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for pickup_looks.png (needs --dat and --spr of pair 55)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    a = ap.parse_args()
    if a.src and a.check:
        sys.exit('--check reads the committed sources only; leave --src out')
    given = {}
    for s_ in a.src:
        k, _, f = s_.partition('=')
        if k not in KEYS or not f:
            sys.exit('--src KEY=FILE with KEY one of %s' % ', '.join(KEYS))
        given[k] = f
    srcs = {k: src_path(k) for k in KEYS}
    tmp = None
    if given:
        import tempfile
        tmp = tempfile.mkdtemp()
        for k, f in given.items():
            srcs[k] = os.path.join(tmp, k + '.png')
            Image.fromarray(read_rgba(f), 'RGBA').save(srcs[k], format='PNG', optimize=False)
    try:
        missing = [k for k in KEYS if not os.path.exists(srcs[k])]
        if missing:
            print('missing:', ', '.join(os.path.relpath(src_path(k), HERE) for k in missing))
            return 1
        atlas, things, sums, reports = build(srcs)
        failed = False
        for key in KEYS:
            errs, bad, warn, ncol = reports[key]
            reasons = errs + bad
            print('%s: %s (%d colours)' % (key, 'style PASS (own palette)' if not reasons else 'FAIL', ncol))
            for r in reasons:
                print('  ' + r)
            for w_ in warn:
                print('  warn ' + w_)
            failed = failed or bool(reasons)
        if failed:
            return 1
        if a.check:
            ok = True
            if not os.path.exists(ATLAS) or not np.array_equal(read_rgba(ATLAS), atlas):
                print('stale:', os.path.relpath(ATLAS, HERE)); ok = False
            for path, want in ((THINGS, things), (SUMS, sums)):
                if not os.path.exists(path) or open(path, encoding='utf-8').read() != want:
                    print('stale:', os.path.relpath(path, HERE)); ok = False
            print('pickup look art up to date' if ok else 'run: python3 -I gen_portal_art.py build')
            return 0 if ok else 1
        os.makedirs(SRC_DIR, exist_ok=True)
        for k in given:
            shutil.copyfile(srcs[k], src_path(k))
        with open(ATLAS, 'wb') as f:
            f.write(png_bytes(atlas))
        with open(THINGS, 'w', encoding='utf-8', newline='') as f:
            f.write(things)
        with open(SUMS, 'w', encoding='utf-8', newline='') as f:
            f.write(sums)
        print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client ids %s' % ', '.join(str(l[3]) for l in LOOKS))
        if a.preview:
            if not (a.dat and a.spr):
                sys.exit('--preview needs --dat and --spr (pair 55)')
            preview(a.preview, a.dat, a.spr)
        return 0
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
