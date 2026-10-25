#!/usr/bin/env python3
"""Everfull potion looks: twelve PixelLab flasks, 32 x 32, become client items 38645-38656 (pair 44, client/MANIFEST.md
"Everfull potion looks"). Flags are copied from the stock potion each server item was made from (stackable, multi-use,
as the potion was: the server's engine patch 0043 relies on a stackable item that is never used up).

    python3 -I gen_everfull_art.py build [--src DIR] [--check] [--preview DIR --dat P/Tibia.dat --spr P/Tibia.spr]

Owner, 2026-10-25: the Everfull potions (server/data/scripts/chaos/potions_config.lua `everfull`) wore the stock
potions' looks; they get art of their own, one flask shape per tier, the same in the three colours, growing from tier 1
to tier 4 (a small flask, a round one with a neck ring, a round one in a gold cradle, a gold-winged one). The owner
approved twelve PixelLab results (32 x 32 RGBA, alpha 0 / 255; generate-image-v2, then edit-image-pixen; the calls are in
pixellab-pip-generations/everfull/manifest.json and everfull.blueprint.json; credit: docs/CREDITS.md "Tools"):
health / mana / spirit, tiers 1 to 4. The pixels are PixelLab's, owner approved: nothing is repainted, snapped or
recoloured here (only the colour under fully transparent pixels is cleared).
`build --src DIR` takes the twelve files (DIR = pixellab-pip-generations/everfull/final, git-ignored), checks them and
copies them to art_import/everfull/ (the committed sources, about 25 KB); without --src the committed copies are used
(CI), so later rebuilds need no PixelLab folder.

Outputs (committed): art_import/everfull.png (the atlas: the twelve looks side by side, 32 px apart),
art_import/everfull.csv (the things file of import_art_things.py: 1 x 1, one phase, flags copy:<stock client id>, mode
new) and art_import/everfull.sums (sha256 of the decoded pixels of every source and of the atlas). `--check` (CI)
rebuilds from the committed sources and compares, writes nothing. `--preview DIR` writes everfull_looks.png (the twelve
looks as the client draws them from the pair, 1x and 4x).

Style: docs/SPRITE_STYLE.md wants one theme palette. These flasks are red, blue, purple and gold, the owner approved the
pixels, so they are not snapped. `build` runs the style check on each canvas against its own colours: every rule but the
theme palette (outline, light, noise, colour count, alpha, scale) must pass or `build` refuses; the light rule is a
warning (the gold cradles of tier 3 catch the light from below). Deterministic: numpy and Pillow only.
"""
import argparse, csv, hashlib, io, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SRC_DIR = os.path.join(ART, 'everfull')
ATLAS = os.path.join(ART, 'everfull.png')
THINGS = os.path.join(ART, 'everfull.csv')
SUMS = os.path.join(ART, 'everfull.sums')
FIRST_CLIENT_ID = 38645   # after the last item of pair 43 (38644, the Cursed Chest's third look)
CELL = 32

# line, tier, stock client id the flags are copied from (the client id of the stock potion the server node copies:
# 7618 -> 266, 7620 -> 268, 7591 -> 239, 7590 -> 238, 8472 -> 7642, 8473 -> 7643, 26029 -> 23373, 26030 -> 23374,
# 26031 -> 23375; the two supreme potions that have no stock potion copy the ultimate one), server id, things name.
# One look per Everfull server item, in this order = the client ids FIRST_CLIENT_ID.. (potions_config.lua clientId).
LOOKS = (
    ('health', 1, 266, 32085, 'everfull health potion'),
    ('health', 2, 239, 32261, 'everfull great health potion'),
    ('health', 3, 7643, 32264, 'everfull ultimate health potion'),
    ('health', 4, 23375, 32267, 'everfull supreme health potion'),
    ('mana', 1, 268, 32086, 'everfull mana potion'),
    ('mana', 2, 238, 32262, 'everfull great mana potion'),
    ('mana', 3, 23373, 32265, 'everfull ultimate mana potion'),
    ('mana', 4, 23373, 32269, 'everfull supreme mana potion'),
    ('spirit', 1, 7642, 32268, 'everfull spirit potion'),
    ('spirit', 2, 7642, 32263, 'everfull great spirit potion'),
    ('spirit', 3, 23374, 32266, 'everfull ultimate spirit potion'),
    ('spirit', 4, 23374, 32270, 'everfull supreme spirit potion'),
)
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']


def key_of(line, tier):
    return 'everfull_%s_t%d' % (line, tier)


def file_of(line, tier):
    return key_of(line, tier) + '.png'


def client_id(i):
    return FIRST_CLIENT_ID + i


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
        if ys.max() - ys.min() < 22 or xs.max() - xs.min() < 10:
            out.append('the art does not fill the canvas (a flask is about 28 high)')
        if ys.min() < 0 or xs.min() < 0:
            out.append('outside the canvas')
    if (a[al == 0][:, :3] != 0).any():
        out.append('colour under transparent pixels')
    return out


def style_report(a):
    """(reasons that stop the build, warnings, colour count) of one canvas; the palette rule is judged against the
    canvas's own colours (no theme palette: see the module docstring)"""
    data = sc.load_palettes()
    own = np.unique(a[a[..., 3] > 0][:, :3], axis=0)
    bad, warn = sc.judge(sc.measure(a), own, data['light']['global'], data['thresholds'])
    return bad, warn, own.shape[0]


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def build(src_dir):
    """(atlas RGBA, things text, sums text, [(key, errors, style bad, warnings, colours)])"""
    pics, report = [], []
    for line, tier, _stock, _sid, _name in LOOKS:
        a = read_rgba(os.path.join(src_dir, file_of(line, tier)))
        errs = problems_of(a)
        bad, warn, ncol = style_report(a) if not errs else ([], [], 0)
        report.append((key_of(line, tier), errs, bad, warn, ncol))
        pics.append(a)
    atlas = np.concatenate(pics, axis=1) if all(not r[1] for r in report) else None
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    for i, (line, tier, stock, sid, name) in enumerate(LOOKS):
        w.writerow([key_of(line, tier), 'item', 'flask', name, 'everfull', i * CELL, 0, 1, 1, 1, 1,
                    'copy:%d' % stock, 'new', sid, ''])
    sums = ''.join('%s  everfull/%s\n' % (digest(a), file_of(line, tier)) for a, (line, tier, *_r) in zip(pics, LOOKS))
    if atlas is not None:
        sums += '%s  everfull.png\n' % digest(atlas)
    return atlas, out.getvalue(), sums, report


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(outdir, dat, spr, first=FIRST_CLIENT_ID):
    """everfull_looks.png: the twelve looks as the client draws them from the pair, 1x and 4x, three rows (health, mana,
    spirit) of four tiers, on a dark and a light ground"""
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    pad, z = 8, 4
    colw = CELL * z + 2 * pad
    rowh = CELL * z + CELL + 3 * pad
    W, H = 4 * colw + pad, 3 * rowh + pad
    im = Image.new('RGBA', (2 * W, H))
    for side, bg in enumerate(((40, 36, 34, 255), (214, 200, 170, 255))):
        im.paste(Image.new('RGBA', (W, H), bg), (side * W, 0))
        for i in range(len(LOOKS)):
            row, col = divmod(i, 4)
            f = render_item(d, s, first + i).convert('RGBA')
            assert f.size == (CELL, CELL), (first + i, f.size)
            x = side * W + pad + col * colw + pad
            y = pad + row * rowh
            im.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (x, y))
            im.alpha_composite(f, (x + (CELL * z - CELL) // 2, y + CELL * z + pad))
    p = os.path.join(outdir, 'everfull_looks.png')
    im.convert('RGB').save(p)
    print('preview', p)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--src', default=None, help='the PixelLab folder with the twelve everfull_<line>_t<tier>.png '
                    '(pixellab-pip-generations/everfull/final); copied to art_import/everfull/')
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for everfull_looks.png (needs --dat and --spr of pair 44)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    a = ap.parse_args()
    if a.src and a.check:
        sys.exit('--check reads the committed sources only; leave --src out')
    src = SRC_DIR
    tmp = None
    if a.src:
        import tempfile
        tmp = tempfile.mkdtemp()
        for line, tier, *_r in LOOKS:
            p = os.path.join(a.src, file_of(line, tier))
            if not os.path.exists(p):
                sys.exit('missing %s in %s' % (file_of(line, tier), a.src))
            Image.fromarray(read_rgba(p), 'RGBA').save(os.path.join(tmp, file_of(line, tier)), format='PNG', optimize=False)
        src = tmp
    try:
        atlas, things, sums, report = build(src)
        failed = False
        for key, errs, bad, warn, ncol in report:
            reasons = errs + bad
            print('%s: %s (%d colours)' % (key, 'style PASS (own palette)' if not reasons else 'FAIL', ncol))
            for r in reasons:
                print('  ' + r)
                failed = True
            for w_ in warn:
                print('  warn ' + w_)
        if failed:
            return 1
        if a.check:
            ok = True
            for line, tier, *_r in LOOKS:
                p = os.path.join(SRC_DIR, file_of(line, tier))
                if not os.path.exists(p):
                    print('missing:', os.path.relpath(p, HERE)); ok = False
            if not os.path.exists(ATLAS) or not np.array_equal(read_rgba(ATLAS), atlas):
                print('stale:', os.path.relpath(ATLAS, HERE)); ok = False
            for path, want in ((THINGS, things), (SUMS, sums)):
                if not os.path.exists(path) or open(path, encoding='utf-8').read() != want:
                    print('stale:', os.path.relpath(path, HERE)); ok = False
            print('everfull art up to date' if ok else 'run: python3 -I gen_everfull_art.py build')
            return 0 if ok else 1
        if a.src:
            os.makedirs(SRC_DIR, exist_ok=True)
            for line, tier, *_r in LOOKS:
                shutil.copyfile(os.path.join(tmp, file_of(line, tier)), os.path.join(SRC_DIR, file_of(line, tier)))
        with open(ATLAS, 'wb') as f:
            f.write(png_bytes(atlas))
        with open(THINGS, 'w', encoding='utf-8', newline='') as f:
            f.write(things)
        with open(SUMS, 'w', encoding='utf-8', newline='') as f:
            f.write(sums)
        print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client ids %d..%d'
              % (FIRST_CLIENT_ID, FIRST_CLIENT_ID + len(LOOKS) - 1))
        if a.preview:
            if not (a.dat and a.spr):
                sys.exit('--preview needs --dat and --spr (pair 44)')
            preview(a.preview, a.dat, a.spr)
        return 0
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
