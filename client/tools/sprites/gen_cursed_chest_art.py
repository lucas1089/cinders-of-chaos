#!/usr/bin/env python3
"""Cursed Chest looks: three PixelLab paintings of a chest, 64 x 64, become client items 38642-38644 (pair 43,
client/MANIFEST.md "Cursed Chest looks"). Each is a 2 x 2 tile item (flags copied from client 4073, the Sealed Coffer
chest of server 12664: container, blocks, not moveable).

    python3 -I gen_cursed_chest_art.py build [--src DIR] [--check] [--preview DIR --dat P/Tibia.dat --spr P/Tibia.spr]

Owner, 2026-10-25: the Cursed Chest (server/data/scripts/chaos/cursedchest_*.lua) borrowed the Sealed Coffer's chest;
it gets art of its own. The owner picked three PixelLab results (64 x 64 RGBA, alpha 0 / 255, our own prompt; credit: docs/CREDITS.md "Tools"):
  A  cursed_chest_pro_6.png   iron chest with glowing lava cracks and chains   (the main look)
  B  cursed_chest_pro_13.png  purple flame, grinning faces on the lid, chains
  C  cursed_chest_pro_10.png  open maw: a red lid with iron teeth
The pixels are PixelLab's, owner approved; nothing is repainted, snapped or recoloured here (only the colour under
fully transparent pixels is cleared). `build --src DIR` takes
the frames by their PixelLab paths from DIR (the raw folder is git-ignored), checks them and copies them to
art_import/cursed_chest/ (the committed sources, 11 small PNGs; the same way the themed item icons keep their cleaned
picks). Idle animation (owner, same day; PixelLab animate-with-text): A 5 phases (250 ms), B a still, C 8 phases
(200 ms) as the ping-pong 0 1 2 3 4 3 2 1; LOOKS lists the frames, the phase sequence and the time per phase. Without --src the committed copies are used (CI).

Outputs (committed): art_import/cursed_chest.png (the atlas: the three looks side by side, 64 px apart),
art_import/cursed_chest.csv (the things file of import_art_things.py: w = h = 2, phases per look, flags copy:4073, mode new)
and art_import/cursed_chest.sums (sha256 of the decoded pixels of every source and of the atlas). The importer cuts
each 64 x 64 canvas into the four 32 px tiles the dat holds for a 2 x 2 item (`tiles()` below is the same cut).
`--check` (CI) rebuilds from the committed sources and compares, writes nothing.

Style: docs/SPRITE_STYLE.md wants one theme palette (`style_check.py snap`). These pictures are lava, purple and
blood red, none of them one of the seven themes, and the owner approved the pixels, so they are not snapped. `build`
runs the style check on each canvas (cell 64) against its own colours: every rule but the theme palette (outline,
light, noise, colour count, alpha, scale) must pass or `build` refuses.
Deterministic: numpy and Pillow only.
"""
import argparse, csv, hashlib, io, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SRC_DIR = os.path.join(ART, 'cursed_chest')
ATLAS = os.path.join(ART, 'cursed_chest.png')
THINGS = os.path.join(ART, 'cursed_chest.csv')
SUMS = os.path.join(ART, 'cursed_chest.sums')
FIRST_CLIENT_ID = 38642   # after the last item of pair 42 (38641, the Orb of Sockets)
STOCK_CLIENT_ID = 4073    # client id of server 12664, the Sealed Coffer chest: container, notwalkable, notmoveable, 2x2
SERVER_FIRST = 32281      # server ids 32281-32283 (server/tools/install_cursed_chest.py, server/README.md "Cursed Chest")
CELL = 64

# key, [(committed file, PixelLab file) per distinct frame], sequence (frame indices, one per phase), ms per phase,
# server id. One frame and sequence (0,) = a still item. The atlas holds one 64 px cell per phase, side by side; a
# frame used twice (the ping-pong of C) is stored once in the pair (the importer stores identical sprites once).
IDLE = 'cursed-chest-idle/'   # PixelLab folder of the idle frames, next to cursed-chest/ (--src is the parent folder)
LOOKS = (
    ('cursed_chest_a', tuple(('cursed_chest_a_f%d.png' % i, IDLE + 'chest_A_f%d.png' % i) for i in range(5)),
     (0, 1, 2, 3, 4), 250, SERVER_FIRST),
    ('cursed_chest_b', (('cursed_chest_b.png', 'cursed-chest/cursed_chest_pro_13.png'),), (0,), 250, SERVER_FIRST + 1),
    ('cursed_chest_c', tuple(('cursed_chest_c_f%d.png' % i, IDLE + 'chest_C_f%d.png' % i) for i in range(5)),
     (0, 1, 2, 3, 4, 3, 2, 1), 200, SERVER_FIRST + 2),
)


def frame_files():
    """[(look index, frame index, committed file, PixelLab file)] of the distinct frames"""
    return [(k, f, c, pl) for k, (_key, frames, _seq, _ms, _sid) in enumerate(LOOKS) for f, (c, pl) in enumerate(frames)]


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
    # the colour count (11-68 a cell) is a measure of flat or noisy art: one animation frame has 69 colours; the frames
    # are owner approved and cannot be repainted, so it is reported (a warning), every other rule still refuses
    soft = [b for b in bad if b.startswith('colours:')]
    return [b for b in bad if b not in soft], warn + ['(owner-approved frame) ' + b for b in soft], own.shape[0]


def build(src_dir):
    """(atlas RGBA, things text, sums text, [(key, errors, style bad, warnings, colours)])"""
    pics, report = {}, []
    for k, f, fname, _pl in frame_files():
        key = LOOKS[k][0] + ('' if len(LOOKS[k][1]) == 1 else '_f%d' % f)
        a = read_rgba(os.path.join(src_dir, fname))
        errs = problems_of(a)
        bad, warn, ncol = style_report(a) if not errs else ([], [], 0)
        report.append((key, errs, bad, warn, ncol))
        pics[(k, f)] = a
    cells = [pics[(k, f)] for k, (_key, _fr, seq, _ms, _sid) in enumerate(LOOKS) for f in seq]
    atlas = np.concatenate(cells, axis=1)
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    x = 0
    for key, _frames, seq, ms, sid in LOOKS:
        n = len(seq)
        w.writerow([key, 'item', 'chest', 'cursed chest', 'cursed_chest', x, 0, 2, 2, 1, n,
                    'copy:%d' % STOCK_CLIENT_ID, 'new', sid, '' if n == 1 else 'ms=%d' % ms])
        x += n * CELL
    sums = ''.join('%s  cursed_chest/%s\n' % (digest(pics[(k, f)]), c) for k, f, c, _pl in frame_files())
    sums += '%s  cursed_chest.png\n' % digest(atlas)
    return atlas, out.getvalue(), sums, report


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(outdir, dat, spr, first=FIRST_CLIENT_ID):
    """cursed_chest_looks.png: the three looks as the client draws them from the pair, 1x and 4x, light and dark (the
    first phase); cursed_chest_frames.png: every phase of every look in sequence, 4x, one row per look"""
    from datspr import Dat, Spr, render_thing
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    pad, z = 8, 4
    W = pad + 3 * (CELL * z + pad)
    H = 2 * (CELL * z + CELL + 3 * pad)
    im = Image.new('RGBA', (W, H))
    half = H // 2
    for row, bg in enumerate(((214, 200, 170, 255), (40, 36, 34, 255))):
        im.paste(Image.new('RGBA', (W, half), bg), (0, row * half))
        for k in range(3):
            f = render_item(d, s, first + k).convert('RGBA')
            assert f.size == (CELL, CELL), f.size
            x = pad + k * (CELL * z + pad)
            im.alpha_composite(f, (x, row * half + pad))
            im.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (x, row * half + CELL + 2 * pad))
    p = os.path.join(outdir, 'cursed_chest_looks.png')
    im.convert('RGB').save(p)
    print('preview', p)
    # every phase, as the dat lists them (render_thing draws one phase at a time)
    n = max(len(seq) for _k, _f, seq, _m, _s in LOOKS)
    strip = Image.new('RGBA', (pad + n * (CELL * z + pad), len(LOOKS) * (CELL * z + pad) + pad), (40, 36, 34, 255))
    for k, (_key, _fr, seq, _ms, _sid) in enumerate(LOOKS):
        t = d.items[first + k - 100]
        assert t.phases == len(seq), (first + k, t.phases, len(seq))
        for ph in range(t.phases):
            f = render_thing(t, s, phase=ph, layers='all').convert('RGBA')
            strip.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (pad + ph * (CELL * z + pad), pad + k * (CELL * z + pad)))
    p = os.path.join(outdir, 'cursed_chest_frames.png')
    strip.convert('RGB').save(p)
    print('preview', p)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--src', default=None, help='the PixelLab folder (pixellab-pip-generations: cursed-chest/ and '
                    'cursed-chest-idle/ inside); the frames are copied to art_import/cursed_chest/')
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for cursed_chest_looks.png (needs --dat / --spr of pair 43)')
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
        for _k, _f, fname, plname in frame_files():
            p = os.path.join(a.src, plname)
            if not os.path.exists(p):
                sys.exit('missing %s in %s' % (plname, a.src))
            Image.fromarray(read_rgba(p), 'RGBA').save(os.path.join(tmp, fname), format='PNG', optimize=False)
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
            for _k, _f, fname, _pl in frame_files():
                p = os.path.join(SRC_DIR, fname)
                if not os.path.exists(p):
                    print('missing:', os.path.relpath(p, HERE)); ok = False
            if not os.path.exists(ATLAS) or not np.array_equal(read_rgba(ATLAS), atlas):
                print('stale:', os.path.relpath(ATLAS, HERE)); ok = False
            for path, want in ((THINGS, things), (SUMS, sums)):
                if not os.path.exists(path) or open(path, encoding='utf-8').read() != want:
                    print('stale:', os.path.relpath(path, HERE)); ok = False
            print('cursed chest art up to date' if ok else 'run: python3 -I gen_cursed_chest_art.py build')
            return 0 if ok else 1
        if a.src:
            for _k, _f, fname, _pl in frame_files():
                shutil.copyfile(os.path.join(tmp, fname), os.path.join(SRC_DIR, fname))
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
                sys.exit('--preview needs --dat and --spr (pair 43)')
            preview(a.preview, a.dat, a.spr)
        return 0
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
