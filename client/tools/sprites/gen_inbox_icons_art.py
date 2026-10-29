#!/usr/bin/env python3
"""Store inbox icons: three PixelLab redraws, 32 x 32, drawn IN PLACE over client items 38608 (Loot Bag), 38609 (Orbs
Pouch) and 38611 (Everfull Ration) of pair 34 (client/MANIFEST.md "Store inbox icons"). Server ids 32081, 32082, 32084
and their client ids stay, so items already owned and the store icons show the new art after the pair is rebuilt.

    python3 -I gen_inbox_icons_art.py build [--src DIR] [--pick loot=a,orbs=a,ration=a] [--check]

Owner request (pt-BR, 2026-10-29): "refaca esses icones no pixellab" about the Store Inbox window, which shows the Everfull
Ration (a roast on a plate), the Orbs Pouch (a violet pouch) and the Loot Bag (a brown coin sack). Our own PixelLab prompts
(Pro, 32 x 32, no background, 64 candidates a call; the palette parameter was the theme palette of the old look, the style
image the old tile where the upload took it). Three candidates a look were kept (a, b, c); the first is committed, the owner
may pick another with --pick. The pixels are PixelLab's: nothing is repainted or recoloured, only alpha is made 0 / 255 and
the colour under alpha 0 is cleared. Every look is judged by style_check against the SAME theme palette as before (Loot Bag
gildcrown, Orbs Pouch rimewraith, Everfull Ration cinderwrought) and `build` refuses a failing one.
`build --src DIR` copies <key>_<letter>.png from DIR to art_import/inbox_icons/<key>.png (the committed sources, about 1 KB
each). Without --src the committed copies are used (CI). `--check` compares and writes nothing.

Outputs (committed): art_import/inbox_icons.png (atlas, 3 x 1 cells in LOOKS order), art_import/inbox_icons.csv (things file
of import_art_things.py, mode redraw, flags as the old things file) and art_import/inbox_icons.sums. Credit: docs/CREDITS.md
"Tools" (PixelLab; art_import/inbox_icons_sources.csv). Deterministic: numpy and Pillow only.
"""
import argparse, csv, hashlib, io, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SRC_DIR = os.path.join(ART, 'inbox_icons')
ATLAS = os.path.join(ART, 'inbox_icons.png')
THINGS = os.path.join(ART, 'inbox_icons.csv')
SUMS = os.path.join(ART, 'inbox_icons.sums')

# key, things name, theme, flags copied from (as store_items.csv), server id, client id redrawn
LOOKS = (
    ('inbox_loot', 'loot bag', 'gildcrown', 10325, 32081, 38608),
    ('inbox_orbs', 'orbs pouch', 'rimewraith', 8861, 32082, 38609),
    ('inbox_ration', 'everfull ration', 'cinderwrought', 3583, 32084, 38611),
)
SHORT = {'inbox_loot': 'loot', 'inbox_orbs': 'orbs', 'inbox_ration': 'ration'}
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']


def read_rgba(path):
    a = np.array(Image.open(path).convert('RGBA'))
    a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
    a[a[..., 3] == 0] = 0
    return a


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def problems_of(a):
    """why a picture cannot be a 32 x 32 item canvas ([] = fine)"""
    if a.shape[:2] != (32, 32):
        return ['size %d x %d, not 32 x 32' % (a.shape[1], a.shape[0])]
    out = []
    al = a[..., 3]
    if not (al == 255).any():
        return ['empty']
    ys, xs = np.nonzero(al)
    if ys.min() > 6 or xs.min() > 6 or ys.max() < 25 or xs.max() < 25:
        out.append('the art does not fill the tile')
    return out


def build(src_dir):
    """(atlas RGBA, things text, sums text, [(key, theme, errors, style bad)])"""
    data = sc.load_palettes()
    tiles, report, sums = [], [], ''
    for key, _n, theme, _c, _s, _i in LOOKS:
        t = data['themes'][theme]
        pal = np.array([sc.unhex(x) for x in t['palette']], np.uint8)
        a = read_rgba(os.path.join(src_dir, SHORT[key] + '.png'))
        errs = problems_of(a)
        bad = [] if errs else sc.judge(sc.measure(a), pal, t['light'], data['thresholds'])[0]
        report.append((key, theme, errs, bad))
        tiles.append(a)
        sums += '%s  inbox_icons/%s.png\n' % (digest(a), SHORT[key])
    atlas = np.concatenate(tiles, axis=1)
    sums += '%s  inbox_icons.png\n' % digest(atlas)
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    for k, (key, name, _th, copy, sid, cid) in enumerate(LOOKS):
        w.writerow([key, 'item', 'look', name, 'inbox_icons', k * 32, 0, 1, 1, 1, 1, 'copy:%d' % copy, 'redraw', sid,
                    'item=%d' % cid])
    return atlas, out.getvalue(), sums, report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--src', default=None, help='the folder of the candidates: <loot|orbs|ration>_<a|b|c>.png')
    ap.add_argument('--pick', default='loot=a,orbs=a,ration=a', help='the candidate letter of each look (with --src)')
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    a = ap.parse_args()
    if a.src and a.check:
        sys.exit('--check reads the committed sources only; leave --src out')
    src = SRC_DIR
    tmp = None
    if a.src:
        import tempfile
        tmp = tempfile.mkdtemp()
        picks = dict(p.split('=') for p in a.pick.split(','))
        for short in SHORT.values():
            p = os.path.join(a.src, '%s_%s.png' % (short, picks.get(short, 'a')))
            if not os.path.exists(p):
                sys.exit('missing %s' % p)
            with open(os.path.join(tmp, short + '.png'), 'wb') as f:
                f.write(png_bytes(read_rgba(p)))
        src = tmp
    atlas, things, sums, report = build(src)
    bad_any = False
    for key, theme, errs, bad in report:
        print('%s: %s against %s' % (key, 'FAIL' if errs + bad else 'style PASS', theme))
        for r in errs + bad:
            print('  ' + r); bad_any = True
    if bad_any:
        return 1
    if a.check:
        ok = True
        for path, want in ((THINGS, things), (SUMS, sums)):
            if not os.path.exists(path) or open(path, encoding='utf-8').read() != want:
                print('stale:', os.path.relpath(path, HERE)); ok = False
        if not os.path.exists(ATLAS) or not np.array_equal(read_rgba(ATLAS), atlas):
            print('stale:', os.path.relpath(ATLAS, HERE)); ok = False
        print('inbox icon art up to date' if ok else 'run: python3 -I gen_inbox_icons_art.py build')
        return 0 if ok else 1
    if a.src:
        for short in SHORT.values():
            shutil.copyfile(os.path.join(src, short + '.png'), os.path.join(SRC_DIR, short + '.png'))
        shutil.rmtree(tmp)
    with open(ATLAS, 'wb') as f:
        f.write(png_bytes(atlas))
    for path, text in ((THINGS, things), (SUMS, sums)):
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    print('atlas', ATLAS, '; client ids %s redrawn' % ', '.join(str(l[5]) for l in LOOKS))
    return 0


if __name__ == '__main__':
    sys.exit(main())
