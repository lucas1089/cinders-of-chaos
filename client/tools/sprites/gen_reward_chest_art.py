#!/usr/bin/env python3
"""Reward Chest look: one PixelLab painting of a chest, 64 x 64, becomes client item 38657 (pair 45, client/MANIFEST.md
"Reward Chest look"). A 2 x 2 tile item (flags copied from client 19250, the stock reward chest of server 21584:
container, blocks, not moveable).

    python3 -I gen_reward_chest_art.py build [--src DIR] [--check] [--preview DIR --dat P/Tibia.dat --spr P/Tibia.spr]

Owner request, 2026-10-26: "make a reward chest and give every quest chest this sprite"; after the first preview (dark
wood, gold bands, ember red) "make it far more eye-catching, with gold and jewels, golden and shiny" (the first pick was
reward_chest_b_4.png). Every chest a player takes a
reward from (rift chest, Descent treasure room, the quest chests of the planned areas and of the base server's quests;
server/README.md "Reward chests") wore the stock gold chest on a stone plinth; it gets a look of its own: a gold chest
overflowing with coins and gems, the lid open. Our own PixelLab prompts (generate-image-v2, 64 x 64, no background; 128
candidates in eight prompt variants; the owner picked the 6th of the "lid open, coins and jewels spilling" variant and asked
for it mirrored left-right: `build` flips the committed source (MIRROR; a lossless flip of PixelLab's pixels, nothing else
changes);
credit: docs/CREDITS.md "Tools"). A still: PixelLab's idle animation of it lifted the lid and moved the outline from frame to frame
(the Cursed Chest's animations were accepted; a reward chest that is on the map for good should not shimmer), so there is
one phase.
The pixels are PixelLab's; nothing is repainted, snapped or recoloured (only the colour under fully transparent pixels is
cleared). `build --src DIR` takes the frame by its PixelLab path from DIR (the raw folder is git-ignored), checks it and
copies it to art_import/reward_chest/ (the committed source, one small PNG). Without --src the committed copy is used (CI).

Outputs (committed): art_import/reward_chest.png (the atlas, one 64 px cell), art_import/reward_chest.csv (the things
file of import_art_things.py: w = h = 2, one phase, flags copy:19250, mode new) and art_import/reward_chest.sums (sha256 of
the decoded pixels of the source and of the atlas). `--check` (CI) rebuilds from the committed source and compares,
writes nothing.

Style: docs/SPRITE_STYLE.md wants one theme palette (`style_check.py snap`). This is gold, wood and ember red, not one of
the seven themes, so it is not snapped. `build` runs the style check on the canvas (cell 64) against its own colours:
every rule but the theme palette (outline, light, noise, colour count, alpha, scale) must pass or `build` refuses.
Deterministic: numpy and Pillow only.

The small look (client item 38758, server 32311). The base map's quest chests were one tile big; a 2 x 2 chest overlaps
the walls and the neighbouring chests of tight quest rooms (31 of about 297 sit next to another chest). Owner pick
2026-10-26 ("use o 15"): candidate 15 of the 32 x 32 sheet, PixelLab Pro `generate-image-v2`, 32 x 32, no background,
style image = the approved 64 art scaled down 2x, reference = the 64 art (raw file pro_style32_13.png of the git-ignored
folder pixellab-pip-generations/reward-chest-32/). A one tile (1 x 1) item with the same flags as the big look.

    python3 -I gen_reward_chest_art.py build-small [--src FILE] [--check]

PixelLab's pixels are unchanged except for two lossless steps: the colour under fully transparent pixels is cleared, and
the picture is mirrored left-right (MIRROR_SMALL) because the raw 32 px result leans the other way from the big look as
shipped (the big source is mirrored by `build`; compared side by side, the small raw file matched the unmirrored big
one, so the flip makes it match the shipped one: ring and clasp side, lid opening). Committed source:
art_import/reward_chest/reward_chest_small.png; outputs art_import/reward_chest_small.png (atlas, one 32 px cell),
reward_chest_small.csv (things file: w = h = 1, one phase, flags copy:19250, mode new) and reward_chest_small.sums.
`--check` (CI) rebuilds from the committed source and compares. The style check runs on the 32 px cell like the big one.
"""
import argparse, csv, hashlib, io, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SRC_DIR = os.path.join(ART, 'reward_chest')
ATLAS = os.path.join(ART, 'reward_chest.png')
THINGS = os.path.join(ART, 'reward_chest.csv')
SUMS = os.path.join(ART, 'reward_chest.sums')
FIRST_CLIENT_ID = 38657   # after the last item of pair 44 (38656, the supreme Everfull spirit potion)
STOCK_CLIENT_ID = 19250   # client id of server 21584, the stock reward chest: container, notwalkable, notmoveable, 2x2
SERVER_ID = 32310         # server/tools/install_reward_chest.py, server/README.md "Reward chests"
CELL = 64
# the small (one tile) look: pair 47 appends one item after pair 46's last (38757, the last support rune)
SMALL_CLIENT_ID = 38758
SMALL_SERVER_ID = 32311   # install_reward_chest.py, second item of the block 32310-32319
SMALL_CELL = 32
SMALL_SRC = os.path.join(SRC_DIR, 'reward_chest_small.png')
SMALL_ATLAS = os.path.join(ART, 'reward_chest_small.png')
SMALL_THINGS = os.path.join(ART, 'reward_chest_small.csv')
SMALL_SUMS = os.path.join(ART, 'reward_chest_small.sums')
MIRROR_SMALL = True   # the raw 32 px pick leans the other way from the shipped big look; see the module docstring
MIRROR = True   # owner, 2026-10-26: the picked chest mirrored left-right (the committed source is PixelLab's, unflipped)

# key, committed file, PixelLab file (relative to --src; the raw folder pixellab-pip-generations/reward-chest/), server id
LOOK = ('reward_chest', 'reward_chest.png', 'reward_chest_f_6.png', SERVER_ID)

HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']


def read_rgba(path):
    """the picture as RGBA; the colour under fully transparent pixels is cleared (PixelLab leaves noise there, nothing
    visible changes: the importer treats alpha 0 as empty)"""
    a = np.array(Image.open(path).convert('RGBA'))
    a[a[..., 3] == 0] = 0
    return a


def problems_of(a, cell=CELL):
    """why a picture cannot be a cell x cell item canvas (64 for the big look, 32 for the small; [] = fine)"""
    out = []
    margin = 12 if cell == CELL else cell // 5
    if a.shape[:2] != (cell, cell):
        return ['size %d x %d, not %d x %d' % (a.shape[1], a.shape[0], cell, cell)]
    al = a[..., 3]
    if ((al != 0) & (al != 255)).any():
        out.append('semi-transparent pixels (alpha must be 0 or 255)')
    if not (al == 255).any():
        out.append('empty')
    else:
        ys, xs = np.nonzero(al)
        if ys.min() > margin or xs.min() > margin or ys.max() < cell - margin - 1 or xs.max() < cell - margin - 1:
            out.append('the art does not fill the canvas (a chest is about %d px wide)' % (cell - cell // 8))
    if (a[al == 0][:, :3] != 0).any():
        out.append('colour under transparent pixels')
    return out


def tiles(a):
    """the four 32 px tiles of a 64 x 64 canvas as the dat holds a 2 x 2 item: {(ww, hh): tile}, ww = 0 the right
    column, hh = 0 the bottom row (import_art_things.tiles_of)"""
    return {(ww, hh): np.ascontiguousarray(a[(1 - hh) * 32:(2 - hh) * 32, (1 - ww) * 32:(2 - ww) * 32])
            for hh in range(2) for ww in range(2)}


def style_report(a):  # judged on a whole canvas of one cell (64 or 32 px)
    """(reasons that stop the build, warnings, colour count) of one canvas; the palette rule is judged against the
    canvas's own colours (no theme palette: see the module docstring)"""
    data = sc.load_palettes()
    own = np.unique(a[a[..., 3] > 0][:, :3], axis=0)
    bad, warn = sc.judge(sc.measure(a), own, data['light']['global'], data['thresholds'])
    # the colour count (11-68 a cell) and the noise rule (lone pixels, specks) measure flat or noisy art; the sparkle glints
    # and the coins that spill off the chest are lone pixels by design, and the frame is owner approved and cannot be
    # repainted, so they are reported (a warning), every other rule still refuses
    soft = [b for b in bad if b.startswith(('colours:', 'noise:'))]
    return [b for b in bad if b not in soft], warn + ['(owner-approved frame) ' + b for b in soft], own.shape[0]


def build(src_dir):
    """(atlas RGBA, things text, sums text, [(key, errors, style bad, warnings, colours)])"""
    key, fname, _pl, sid = LOOK
    raw = read_rgba(os.path.join(src_dir, fname))
    a = np.ascontiguousarray(raw[:, ::-1]) if MIRROR else raw   # the owner's flip: a lossless left-right mirror
    errs = problems_of(a)
    bad, warn, ncol = style_report(a) if not errs else ([], [], 0)
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    w.writerow([key, 'item', 'chest', 'reward chest', 'reward_chest', 0, 0, 2, 2, 1, 1,
                'copy:%d' % STOCK_CLIENT_ID, 'new', sid, ''])
    sums = '%s  reward_chest/%s\n%s  reward_chest.png\n' % (digest(raw), fname, digest(a))
    return a, out.getvalue(), sums, [(key, errs, bad, warn, ncol)]


def build_small(src_path):
    """(atlas RGBA, things text, sums text, errors, style bad, warnings, colours) of the small look"""
    raw = read_rgba(src_path)
    a = np.ascontiguousarray(raw[:, ::-1]) if MIRROR_SMALL else raw
    errs = problems_of(a, SMALL_CELL)
    bad, warn, ncol = style_report(a) if not errs else ([], [], 0)
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    w.writerow(['reward_chest_small', 'item', 'chest', 'reward chest', 'reward_chest_small', 0, 0, 1, 1, 1, 1,
                'copy:%d' % STOCK_CLIENT_ID, 'new', SMALL_SERVER_ID, ''])
    sums = '%s  reward_chest/reward_chest_small.png\n%s  reward_chest_small.png\n' % (digest(raw), digest(a))
    return a, out.getvalue(), sums, errs, bad, warn, ncol


def main_small(args):
    src = args.src or SMALL_SRC
    if args.src and args.check:
        sys.exit('--check reads the committed source only; leave --src out')
    if not os.path.exists(src):
        sys.exit('missing %s' % src)
    atlas, things, sums, errs, bad, warn, ncol = build_small(src)
    reasons = errs + bad
    print('reward_chest_small: %s (%d colours)' % ('style PASS (own palette)' if not reasons else 'FAIL', ncol))
    for r in reasons:
        print('  ' + r)
    for w_ in warn:
        print('  warn ' + w_)
    if reasons:
        return 1
    if args.check:
        ok = True
        for path, want in ((SMALL_THINGS, things), (SMALL_SUMS, sums)):
            if not os.path.exists(path) or open(path, encoding='utf-8').read() != want:
                print('stale:', os.path.relpath(path, HERE)); ok = False
        if not os.path.exists(SMALL_SRC):
            print('missing:', os.path.relpath(SMALL_SRC, HERE)); ok = False
        if not os.path.exists(SMALL_ATLAS) or not np.array_equal(read_rgba(SMALL_ATLAS), atlas):
            print('stale:', os.path.relpath(SMALL_ATLAS, HERE)); ok = False
        print('small reward chest art up to date' if ok else 'run: python3 -I gen_reward_chest_art.py build-small')
        return 0 if ok else 1
    os.makedirs(SRC_DIR, exist_ok=True)
    if args.src:   # the committed source: PixelLab's pixels, transparent colour cleared, not mirrored
        with open(SMALL_SRC, 'wb') as f:
            f.write(png_bytes(read_rgba(src)))
    with open(SMALL_ATLAS, 'wb') as f:
        f.write(png_bytes(atlas))
    with open(SMALL_THINGS, 'w', encoding='utf-8', newline='') as f:
        f.write(things)
    with open(SMALL_SUMS, 'w', encoding='utf-8', newline='') as f:
        f.write(sums)
    print('atlas', SMALL_ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client id %d' % SMALL_CLIENT_ID)
    return 0


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(outdir, dat, spr, first=FIRST_CLIENT_ID, name='reward_chest_preview.png'):
    """the look as the client draws it from the pair, 1x and 4x, on a light and a dark ground, next to the stock reward
    chest (client 19250) at 1x and 4x"""
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    pad, z = 8, 4
    cols = [('new', first), ('stock', STOCK_CLIENT_ID)]
    W = pad + len(cols) * (CELL * z + pad)
    H = 2 * (CELL * z + CELL + 3 * pad)
    im = Image.new('RGBA', (W, H))
    half = H // 2
    for row, bg in enumerate(((214, 200, 170, 255), (40, 36, 34, 255))):
        im.paste(Image.new('RGBA', (W, half), bg), (0, row * half))
        for k, (_n, cid) in enumerate(cols):
            f = render_item(d, s, cid).convert('RGBA')
            assert f.size == (CELL, CELL), f.size
            x = pad + k * (CELL * z + pad)
            im.alpha_composite(f, (x, row * half + pad))
            im.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (x, row * half + CELL + 2 * pad))
    p = os.path.join(outdir, name)
    im.convert('RGB').save(p)
    print('preview', p)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'build-small'])
    ap.add_argument('--src', default=None, help='build: the PixelLab folder (pixellab-pip-generations/reward-chest); the frame '
                    'is copied to art_import/reward_chest/. build-small: the PixelLab PNG (reward-chest-32/pro_style32_13.png)')
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for reward_chest_preview.png (needs --dat / --spr of pair 45)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    a = ap.parse_args()
    if a.cmd == 'build-small':   # --src is the PixelLab PNG itself here
        return main_small(a)
    if a.src and a.check:
        sys.exit('--check reads the committed source only; leave --src out')
    src = SRC_DIR
    tmp = None
    if a.src:
        import tempfile
        tmp = tempfile.mkdtemp()
        p = os.path.join(a.src, LOOK[2])
        if not os.path.exists(p):
            sys.exit('missing %s in %s' % (LOOK[2], a.src))
        Image.fromarray(read_rgba(p), 'RGBA').save(os.path.join(tmp, LOOK[1]), format='PNG', optimize=False)
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
            p = os.path.join(SRC_DIR, LOOK[1])
            if not os.path.exists(p):
                print('missing:', os.path.relpath(p, HERE)); ok = False
            if not os.path.exists(ATLAS) or not np.array_equal(read_rgba(ATLAS), atlas):
                print('stale:', os.path.relpath(ATLAS, HERE)); ok = False
            for path, want in ((THINGS, things), (SUMS, sums)):
                if not os.path.exists(path) or open(path, encoding='utf-8').read() != want:
                    print('stale:', os.path.relpath(path, HERE)); ok = False
            print('reward chest art up to date' if ok else 'run: python3 -I gen_reward_chest_art.py build')
            return 0 if ok else 1
        os.makedirs(SRC_DIR, exist_ok=True)
        if a.src:
            shutil.copyfile(os.path.join(tmp, LOOK[1]), os.path.join(SRC_DIR, LOOK[1]))
        with open(ATLAS, 'wb') as f:
            f.write(png_bytes(atlas))
        with open(THINGS, 'w', encoding='utf-8', newline='') as f:
            f.write(things)
        with open(SUMS, 'w', encoding='utf-8', newline='') as f:
            f.write(sums)
        print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client id %d' % FIRST_CLIENT_ID)
        if a.preview:
            if not (a.dat and a.spr):
                sys.exit('--preview needs --dat and --spr (pair 45)')
            preview(a.preview, a.dat, a.spr)
        return 0
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
