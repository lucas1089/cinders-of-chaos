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


def problems_of(a):
    """why a picture cannot be a 64 x 64 item canvas ([] = fine)"""
    out = []
    if a.shape[:2] != (CELL, CELL):
        return ['size %d x %d, not %d x %d' % (a.shape[1], a.shape[0], CELL, CELL)]
    al = a[..., 3]
    if ((al != 0) & (al != 255)).any():
        out.append('semi-transparent pixels (alpha must be 0 or 255)')
    if not (al == 255).any():
        out.append('empty')
    else:
        ys, xs = np.nonzero(al)
        if ys.min() > 12 or xs.min() > 12 or ys.max() < CELL - 13 or xs.max() < CELL - 13:
            out.append('the art does not fill the canvas (a chest is about 56 x 56)')
    if (a[al == 0][:, :3] != 0).any():
        out.append('colour under transparent pixels')
    return out


def tiles(a):
    """the four 32 px tiles of a 64 x 64 canvas as the dat holds a 2 x 2 item: {(ww, hh): tile}, ww = 0 the right
    column, hh = 0 the bottom row (import_art_things.tiles_of)"""
    return {(ww, hh): np.ascontiguousarray(a[(1 - hh) * 32:(2 - hh) * 32, (1 - ww) * 32:(2 - ww) * 32])
            for hh in range(2) for ww in range(2)}


def style_report(a):
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
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--src', default=None, help='the PixelLab folder (pixellab-pip-generations/reward-chest); the frame '
                    'is copied to art_import/reward_chest/')
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for reward_chest_preview.png (needs --dat / --spr of pair 45)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    a = ap.parse_args()
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
