#!/usr/bin/env python3
"""Support rune looks: 100 PixelLab rune stones, 32 x 32, become client items 38658-38757 (pair 46, client/MANIFEST.md
"Support rune looks"). One look per support rune item of the server (20 supports x 5 levels, server ids 32101-32200);
flags are copied from the stock rune stone each item was made from (stackable, use-with: the support runes are stacks
that three combine into the next level).

    python3 -I gen_support_runes_art.py build [--src DIR] [--check] [--first-id N] [--preview OUT.png --dat P/Tibia.dat --spr P/Tibia.spr]
    python3 -I gen_support_runes_art.py icons [--check]      # the 32 x 32 icons of the support window and action bar

Owner, 2026-10-26: "Gere novas runas. Vamos usar as artes das runas como icones tambem" (make new rune art, and use it as
the icons too). The support runes (server/data/lib/chaos_supports_config.lua) wore the stock rune stones' looks and the
window drew procedural icons (gen_support_icons.py, retired by this). Each support gets one carved dark stone with its glowing
sigil in the colour of its theme (orange sunburst, ice crystal, gold cross, green skull, blue bolt, yellow spiral, teal drop,
silver sword, blue rings, yellow trident, orange waves, cyan starburst, red burst, yellow bolt, silver shield, red drop,
blue drop in a ring, orange hammer, purple eye, green leaf), the same stone for all 20 (PixelLab generate-image-v2 with the
first stone as style image and one seed, 64 candidates per call; the pick of each is level 1 = Common, its rim the grey
of the stone). The other four levels are the same picture with the stone's rim recoloured to the level's colour of the
game (server config levelColors: green Rare, red Epic, yellow Legendary, purple Mythic) by PixelLab edit-images-v2 (a text
edit of the pick; the calls are in pixellab-pip-generations/support-runes/calls.jsonl; credit: docs/CREDITS.md "Tools").
The pixels are PixelLab's, owner approved: nothing is repainted, snapped or recoloured here (only the colour under fully
transparent pixels is cleared).
`build --src DIR` takes the 100 files <key>_<level>.png (DIR = pixellab-pip-generations/support-runes/final, git-ignored),
checks them and copies them to art_import/support_runes/ (the committed sources, about 100 KB); without --src the
committed copies are used (CI), so later rebuilds need no PixelLab folder.

Outputs (committed): art_import/support_runes.png (the atlas: one row per support, one 32 px cell per level, 160 x 640),
art_import/support_runes.csv (the things file of import_art_things.py: 1 x 1, one phase, flags copy:<stock client id>, mode
new) and art_import/support_runes.sums (sha256 of the decoded pixels of every source and of the atlas). `--check` (CI)
rebuilds from the committed sources and compares, writes nothing. `--preview OUT.png` writes every look as the client draws
it from the pair (4x, names under each).
`icons` writes the window and action bar icons client/overlay/data/images/game/supports/<key>.png (32 x 32): the Common look
of each support, PixelLab's pixels copied unchanged (the window draws the level colour itself: spellsupports.lua). With
--check it compares the files on disk.

Style: docs/SPRITE_STYLE.md wants one theme palette. These stones carry twenty sigil colours and five rims, the owner approved
the pixels, so they are not snapped. `build` runs the style check on each canvas against its own colours: every rule but the
theme palette (outline, light, noise, colour count, alpha, scale) must pass or `build` refuses; the light rule is a warning.
Deterministic: numpy and Pillow only.
"""
import argparse, csv, hashlib, io, os, re, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
ART = os.path.join(HERE, 'art_import')
SRC_DIR = os.path.join(ART, 'support_runes')
ATLAS = os.path.join(ART, 'support_runes.png')
THINGS = os.path.join(ART, 'support_runes.csv')
SUMS = os.path.join(ART, 'support_runes.sums')
ICON_DIR = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'supports')
CONFIG = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_supports_config.lua')
FIRST_CLIENT_ID = 38658   # after the last item of pair 45 (38657, the Reward Chest look)
CELL = 32
LEVELS = 5
STOCK_CLIENT_OFFSET = 2656   # server id - client id of the stock rune stones (24685 -> 22029, ... 24698 -> 22042)
LEVEL_NAMES = ('common', 'rare', 'epic', 'legendary', 'mythic')

# the supports, in the order of chaos_supports_config.lua (checked against it): key, display name, stock rune stone
# index (`sprite` of the config entry) the flags are copied from
SUPPORTS = (
    ('emberbrand', 'Emberbrand'), ('rimebrand', 'Rimebrand'), ('dawnbrand', 'Dawnbrand'), ('gravebrand', 'Gravebrand'),
    ('stormbrand', 'Stormbrand'), ('quickening', 'Quickening'), ('thrift', 'Thrift'), ('keenedge', 'Keen Edge'),
    ('echo', 'Echo'), ('fork', 'Fork'), ('breadth', 'Breadth'), ('shatter', 'Shatter'), ('deathburst', 'Deathburst'),
    ('surge', 'Surge'), ('reprisal', 'Reprisal'), ('bloodthirst', 'Bloodthirst'), ('siphon', 'Siphon'),
    ('sunder', 'Sunder'), ('hex', 'Hex'), ('mercy', 'Mercy'),
)
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']


def read_config(path=CONFIG):
    """(firstId, [(key, name, stock server id)]) of chaos_supports_config.lua; the stock ids come from `sprites`"""
    text = re.sub(r'--[^\n]*', '', open(path, encoding='utf-8').read())
    first = int(re.search(r'firstId\s*=\s*(\d+)', text).group(1))
    sprites = [int(x) for x in re.findall(r'\d+', re.search(r'sprites\s*=\s*\{([^}]*)\}', text).group(1))]
    out = []
    for m in re.finditer(r'\{key\s*=\s*"(\w+)"(.*?)text\s*=\s*"', text, re.S):
        body = m.group(2)
        out.append((m.group(1), re.search(r'name\s*=\s*"([^"]+)"', body).group(1),
                    sprites[int(re.search(r'sprite\s*=\s*(\d+)', body).group(1)) - 1]))
    return first, out


def looks():
    """[(key, level 1..5, name, server id, stock client id)] in client id order (FIRST_CLIENT_ID + index)"""
    first, cfg = read_config()
    if [k for k, _n, _s in cfg] != [k for k, _n in SUPPORTS]:
        raise SystemExit('SUPPORTS does not match chaos_supports_config.lua')
    out = []
    for ti, (key, name, stock) in enumerate(cfg):
        for level in range(1, LEVELS + 1):
            out.append((key, level, '%s %s rune' % (LEVEL_NAMES[level - 1], name.lower()),
                        first + ti * LEVELS + level - 1, stock - STOCK_CLIENT_OFFSET))
    return out


def file_of(key, level):
    return '%s_%d.png' % (key, level)


def client_id(i, first=FIRST_CLIENT_ID):
    return first + i


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
        if ys.max() - ys.min() < 20 or xs.max() - xs.min() < 14:
            out.append('the art does not fill the canvas (a rune stone is about 26 x 20)')
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


def atlas_xy(i):
    return (i % LEVELS) * CELL, (i // LEVELS) * CELL


def build(src_dir):
    """(atlas RGBA, things text, sums text, [(name, errors, style bad, warnings, colours)])"""
    rows = looks()
    pics, report = [], []
    for key, level, name, _sid, _stock in rows:
        a = read_rgba(os.path.join(src_dir, file_of(key, level)))
        errs = problems_of(a)
        bad, warn, ncol = style_report(a) if not errs else ([], [], 0)
        report.append((name, errs, bad, warn, ncol))
        pics.append(a)
    atlas = None
    if all(not r[1] for r in report):
        atlas = np.zeros((CELL * len(SUPPORTS), CELL * LEVELS, 4), np.uint8)
        for i, a in enumerate(pics):
            x, y = atlas_xy(i)
            atlas[y:y + CELL, x:x + CELL] = a
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    for i, (key, level, name, sid, stock) in enumerate(rows):
        x, y = atlas_xy(i)
        w.writerow(['%s_%d' % (key, level), 'item', 'rune', name, 'support_runes', x, y, 1, 1, 1, 1,
                    'copy:%d' % stock, 'new', sid, ''])
    sums = ''.join('%s  support_runes/%s\n' % (digest(a), file_of(key, level)) for a, (key, level, *_r) in zip(pics, rows))
    if atlas is not None:
        sums += '%s  support_runes.png\n' % digest(atlas)
    return atlas, out.getvalue(), sums, report


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def icon_bytes(key):
    """the support icon: the Common look as it is (PixelLab's pixels), written with the same encoder everywhere"""
    return png_bytes(read_rgba(os.path.join(SRC_DIR, file_of(key, 1))))


def preview(out, dat, spr, first=FIRST_CLIENT_ID):
    """out.png: every look as the client draws it from the pair, 4x, five levels per support, names under each"""
    from PIL import ImageDraw
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    rows = looks()
    z, pad, lab = 4, 6, 22
    cw, ch = CELL * z + 2 * pad, CELL * z + lab + 2 * pad
    per_row = 2   # supports side by side
    nrows = (len(SUPPORTS) + per_row - 1) // per_row
    W, H = per_row * LEVELS * cw, nrows * ch
    im = Image.new('RGBA', (W, H), (40, 36, 34, 255))
    dr = ImageDraw.Draw(im)
    for i, (key, level, name, _sid, _stock) in enumerate(rows):
        ti = i // LEVELS
        col = (ti % per_row) * LEVELS + (level - 1)
        row = ti // per_row
        f = render_item(d, s, client_id(i, first)).convert('RGBA')
        assert f.size == (CELL, CELL), (client_id(i, first), f.size)
        x, y = col * cw + pad, row * ch + pad
        im.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (x, y))
        words = name.replace(' rune', '').split(' ', 1)
        dr.text((x, y + CELL * z + 2), words[0], fill=(230, 220, 200, 255))
        dr.text((x, y + CELL * z + 12), words[1] if len(words) > 1 else '', fill=(190, 180, 160, 255))
    im.convert('RGB').save(out)
    print('preview', out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'icons'])
    ap.add_argument('--src', default=None, help='the PixelLab folder with the 100 <key>_<level>.png '
                    '(pixellab-pip-generations/support-runes/final); copied to art_import/support_runes/')
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a PNG for the preview (needs --dat and --spr of the pair)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    ap.add_argument('--first-id', type=int, default=FIRST_CLIENT_ID, help='client id of the first look in the preview')
    a = ap.parse_args()
    if a.cmd == 'icons':
        ok = True
        os.makedirs(ICON_DIR, exist_ok=True)
        for key, _n in SUPPORTS:
            p = os.path.join(ICON_DIR, key + '.png')
            want = icon_bytes(key)
            if a.check:
                if not os.path.exists(p) or open(p, 'rb').read() != want:
                    print('stale:', os.path.relpath(p, ROOT)); ok = False
            else:
                with open(p, 'wb') as f:
                    f.write(want)
        print(('support icons up to date' if ok else 'run: python3 -I gen_support_runes_art.py icons') if a.check
              else '%d support icons written to %s' % (len(SUPPORTS), ICON_DIR))
        return 0 if ok else 1
    if a.src and a.check:
        sys.exit('--check reads the committed sources only; leave --src out')
    rows = looks()
    src = SRC_DIR
    tmp = None
    if a.src:
        import tempfile
        tmp = tempfile.mkdtemp()
        for key, level, *_r in rows:
            p = os.path.join(a.src, file_of(key, level))
            if not os.path.exists(p):
                sys.exit('missing %s in %s' % (file_of(key, level), a.src))
            Image.fromarray(read_rgba(p), 'RGBA').save(os.path.join(tmp, file_of(key, level)), format='PNG', optimize=False)
        src = tmp
    try:
        atlas, things, sums, report = build(src)
        failed = False
        for name, errs, bad, warn, ncol in report:
            reasons = errs + bad
            if reasons:
                print('%s: FAIL (%d colours)' % (name, ncol))
                failed = True
            for r in reasons:
                print('  ' + r)
            for w_ in warn:
                print('  warn %s: %s' % (name, w_))
        if failed:
            return 1
        print('%d looks pass the style check on their own colours' % len(report))
        if a.check:
            ok = True
            for key, level, *_r in rows:
                p = os.path.join(SRC_DIR, file_of(key, level))
                if not os.path.exists(p):
                    print('missing:', os.path.relpath(p, HERE)); ok = False
            if not os.path.exists(ATLAS) or not np.array_equal(read_rgba(ATLAS), atlas):
                print('stale:', os.path.relpath(ATLAS, HERE)); ok = False
            for path, want in ((THINGS, things), (SUMS, sums)):
                if not os.path.exists(path) or open(path, encoding='utf-8').read() != want:
                    print('stale:', os.path.relpath(path, HERE)); ok = False
            print('support rune art up to date' if ok else 'run: python3 -I gen_support_runes_art.py build')
            return 0 if ok else 1
        if a.src:
            os.makedirs(SRC_DIR, exist_ok=True)
            for key, level, *_r in rows:
                shutil.copyfile(os.path.join(tmp, file_of(key, level)), os.path.join(SRC_DIR, file_of(key, level)))
        with open(ATLAS, 'wb') as f:
            f.write(png_bytes(atlas))
        with open(THINGS, 'w', encoding='utf-8', newline='') as f:
            f.write(things)
        with open(SUMS, 'w', encoding='utf-8', newline='') as f:
            f.write(sums)
        print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client ids %d..%d'
              % (FIRST_CLIENT_ID, FIRST_CLIENT_ID + len(rows) - 1))
        if a.preview:
            if not (a.dat and a.spr):
                sys.exit('--preview needs --dat and --spr')
            preview(a.preview, a.dat, a.spr, a.first_id)
        return 0
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
