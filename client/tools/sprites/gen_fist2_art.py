#!/usr/bin/env python3
"""Monk fist weapon looks: thirteen PixelLab pictures, 32 x 32, become client items 44399-44411 (pair 56, client/MANIFEST.md "Pair 56").
Owner approved 2026-10-28 ("aprovo todas"), the top picks of the phase 1 sheets:
44399-44404 the redraws of the six claws fist_c4..fist_c9 (server 40003-40008; they wore the donor claws 28003-28008),
44405-44408 the four uniques fist_u1..fist_u4 (server 40009-40012; donor 28009-28012), and
44409-44411 three new fist weapons (server 48409-48411 = client id + 4000, the pair 50 rule): gravetooth cestus (750),
pair of hollowfang katars (950), wardenplate gauntlet (1150). The donor sprite slots are not touched: the server items are
repointed to the new client ids (server/data/items/fist_claws.csv, mode repoint).

    python3 -I gen_fist2_art.py build [--src KEY=FILE ...] [--check] [--preview DIR --dat P/Tibia.dat --spr P/Tibia.spr]

PixelLab results (create_image_pro, 8 x 8 sheets of 32 px tiles, the tile is re-cut over the cell seam; 32 x 32 RGBA, alpha 0 / 255;
docs/CREDITS.md "Tools"). The pixels are PixelLab's, owner approved: nothing is repainted, snapped or recoloured here (only the
colour under fully transparent pixels is cleared). Candidate set and tile number of each look: art_import/fist2_sources.csv.
`build --src KEY=FILE` (repeatable) takes a picture, checks it and copies it to art_import/fist2/KEY.png (the committed source);
without --src the committed copies are used (CI).

Outputs (committed): art_import/fist2.png (the atlas, 32 px cells side by side in LOOKS order), art_import/fist2.csv (the
things file of import_art_things.py: 1 x 1, one phase, flags copied from the stock fist wrap 3412 like fist_weapons.csv,
mode new) and art_import/fist2.sums (sha256 of the decoded pixels of each source and of the atlas). `--check` (CI) rebuilds
from the committed sources and compares, writes nothing.

Style: docs/SPRITE_STYLE.md wants one theme palette. These looks use their own colours and the owner approved the pixels, so
they are not snapped. `build` runs the style check on each canvas against its own colours: every rule but the theme palette
must pass or `build` refuses; the light rule is a warning. Deterministic: numpy and Pillow only.

A second look set of the same kind (the next pair): copy this file and its test, change NAME, LOOKS (key, kind, name,
client id, server id), the doc text and the sources file; client ids continue after the last item of the pair before.
"""
import argparse, csv, hashlib, io, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
NAME = 'fist2'
LOOKS = [   # (key, kind, item name, client id, server id); client ids follow the last item of pair 55 (44398)
    ('fist_c4', 'weapon', 'pair of emberhide claws', 44399, 40003),
    ('fist_c5', 'weapon', 'pair of voidglass claws', 44400, 40004),
    ('fist_c6', 'weapon', 'pair of stormforged claws', 44401, 40005),
    ('fist_c7', 'weapon', 'pair of wyrmbone claws', 44402, 40006),
    ('fist_c8', 'weapon', 'pair of gravewrought claws', 44403, 40007),
    ('fist_c9', 'weapon', 'pair of last-dawn claws', 44404, 40008),
    ('fist_u1', 'weapon', 'vigil-knot wraps', 44405, 40009),
    ('fist_u2', 'weapon', 'chapel-iron knuckles', 44406, 40010),
    ('fist_u3', 'weapon', 'gravewind talons', 44407, 40011),
    ('fist_u4', 'weapon', 'dawnless gauntlets', 44408, 40012),
    ('fist_t6', 'weapon', 'gravetooth cestus', 44409, 48409),
    ('fist_t7', 'weapon', 'pair of hollowfang katars', 44410, 48410),
    ('fist_t8', 'weapon', 'wardenplate gauntlet', 44411, 48411),
]
KEYS = [l[0] for l in LOOKS]
FIRST_ID = LOOKS[0][3]
FLAGS = 'copy:3412'
# style rules a look misses by a little but the owner approved as drawn (rule word -> why); printed, never silent
WAIVED = {'fist_c6': {'noise': '8 one-pixel holes (max 6): the rivets of the steel glove'},
          'fist_u3': {'outline': '27% near-black rim (min 30%): the spectral wind claws have a teal edge'}}
SRC_DIR = os.path.join(ART, NAME)
ATLAS = os.path.join(ART, NAME + '.png')
THINGS = os.path.join(ART, NAME + '.csv')
SUMS = os.path.join(ART, NAME + '.sums')
SOURCES = os.path.join(ART, NAME + '_sources.csv')
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
        if ys.max() - ys.min() < 12 or xs.max() - xs.min() < 12:
            out.append('the art does not fill the canvas (a fist weapon is at least 13 px wide and high)')
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
        waived = WAIVED.get(key, {})
        warn = warn + ['waived (owner approved): ' + b for b in bad if b.split(':')[0] in waived]
        bad = [b for b in bad if b.split(':')[0] not in waived]
        reports[key] = (errs, bad, warn, ncol)
        cells.append(a)
        w.writerow([key, 'item', kind, name, NAME, i * CELL, 0, 1, 1, 1, 1, FLAGS, 'new', sid, ''])
        sums += '%s  %s/%s.png\n' % (digest(a), NAME, key)
    ok = not any(r[0] for r in reports.values())
    atlas = np.concatenate(cells, axis=1) if ok else None
    if ok:
        sums += '%s  %s.png\n' % (digest(atlas), NAME)
    return atlas, out.getvalue(), sums, reports


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(outdir, dat, spr):
    """fist_looks.png: the items as the client draws them from the pair, 4x and 1x, on a dark and a light ground"""
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    pad, z = 8, 4
    W, H = len(LOOKS) * (CELL * z + pad) + pad, CELL * z + CELL + 3 * pad
    im = Image.new('RGBA', (W, 2 * H))
    for side, bg in enumerate(((40, 36, 34, 255), (214, 200, 170, 255))):
        im.paste(Image.new('RGBA', (W, H), bg), (0, side * H))
        for i, look in enumerate(LOOKS):
            f = render_item(d, s, look[3]).convert('RGBA')
            assert f.size == (CELL, CELL), (look[3], f.size)
            x = pad + i * (CELL * z + pad)
            im.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (x, side * H + pad))
            im.alpha_composite(f, (x + (CELL * z - CELL) // 2, side * H + CELL * z + 2 * pad))
    p = os.path.join(outdir, 'fist_looks.png')
    im.convert('RGB').save(p)
    print('preview', p)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--src', action='append', default=[], metavar='KEY=FILE',
                    help='a PixelLab picture for one look (%s); copied to art_import/%s/KEY.png' % (', '.join(KEYS), NAME))
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for fist_looks.png (needs --dat and --spr of the new pair)')
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
            print('fist look art up to date' if ok else 'run: python3 -I gen_fist2_art.py build')
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
        print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client ids %d-%d' % (LOOKS[0][3], LOOKS[-1][3]))
        if a.preview:
            if not (a.dat and a.spr):
                sys.exit('--preview needs --dat and --spr (the new pair)')
            preview(a.preview, a.dat, a.spr)
        return 0
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
