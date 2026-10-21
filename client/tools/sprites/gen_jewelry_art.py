#!/usr/bin/env python3
"""The looks of the 29 jewelry loot bases (10 rings, 19 necklaces; server/data/lib/chaos_jewelry.lua `J.bases`), cut
from a free icon set and written as the 32 px atlas art_import/jewelry.png (29 x 1 tiles, in `look` order) and the
things file art_import/jewelry.csv that import_art_things.py appends (pair 35, client ids 38612..38640; client/MANIFEST.md
"Jewelry looks (pair 35)").

python3 -I gen_jewelry_art.py build [--src SHEET] [--check] [--preview DIR]

Owner request 2026-10-22: "use sprites de rings e necklaces dos nossos assets". The source is the free fantasy icon set
of docs/CREDITS.md (internal label `set35 icons`, the 32 x 32 full sheet: 16 x 137 cells of 32 px; Drive file id and
md5 in SOURCE). That sheet is its 16 px art doubled pixel for pixel (checked: every 2 x 2 block is one colour), so each
pick takes the 16 px cell (every other pixel) and doubles it with Scale2x (pack30lib.scale2x, as the importer does for
16 px art): no colour is changed, nothing is traced or redrawn. Imported art stays as it is (docs/SPRITE_STYLE.md),
so `style_check.py` is not run on it.

`build --src SHEET` cuts the picks of PICKS and writes the atlas and the things file. `build --check` (CI) compares the
things file with PICKS and chaos_jewelry.lua (server id, client id, name, order) and the atlas's size; with --src it
also rebuilds the atlas and compares it pixel for pixel. Writes nothing then. `--preview DIR` writes the looks at 4x
on a light and a dark ground. Deterministic.

Flags: `copy:<stock client id>` (the base item's own look of pair 34: pickupable, moveable and the rest as before);
mode replace with the server id, so the importer's manifest maps the stock item to its new look. The server points
the items.otb nodes at them (server/tools/patch_base_jewelry.py, install step `jewelry`).
"""
import argparse, csv, hashlib, io, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import pack30lib as P

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
ART = os.path.join(HERE, 'art_import')
ATLAS = os.path.join(ART, 'jewelry.png')
THINGS = os.path.join(ART, 'jewelry.csv')
LIB = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_jewelry.lua')
FIRST_CLIENT_ID = 38612   # after the last item of pair 34 (38611)
CELL = 32                 # the sheet's grid; the art is 16 px doubled
SOURCE = {'drive_id': '1ngMAdCvwGdehhd5RrR1BloVNY6ZhoeZt', 'md5': 'bd6c96e2e925372fe655d16b4d69d91f',
          'size': (512, 4384)}

# server id, things name, sheet row, sheet column, stock client id (flags copied from it)
PICKS = (
    (2168, 'life ring', 115, 2, 3052),             # plain silver band
    (2166, 'power ring', 115, 4, 3050),            # gold band, ruby
    (2207, 'sword ring', 128, 12, 3091),           # iron band
    (2208, 'axe ring', 128, 14, 3092),             # iron band, open
    (2209, 'club ring', 128, 15, 3093),            # two iron bands
    (2214, 'ring of healing', 128, 13, 3098),      # iron band, green stone
    (6300, 'death ring', 115, 5, 6299),            # violet band, green gem
    (18408, 'prismatic ring', 136, 10, 16114),     # gold band, blue gem
    (28691, 'ring of temptation', 136, 9, 26035),  # gold signet, red stone
    (26808, 'butterfly ring', 136, 12, 24152),     # gold band, blue gem cluster
    (2172, 'bronze amulet', 115, 7, 3056),         # copper chain, green drop
    (2200, 'protection amulet', 129, 0, 3084),     # leather cord, green stone
    (2161, 'strange talisman', 129, 1, 3045),      # cord, bone charm
    (2170, 'silver amulet', 115, 10, 3054),        # silver chain, amber drop
    (2201, 'dragon necklace', 115, 8, 3085),       # copper chain, red drop
    (2198, 'elven amulet', 136, 7, 3082),          # gold chain, blue drop
    (2199, 'garlic necklace', 129, 2, 3083),       # bead string
    (7887, 'terra amulet', 113, 3, 814),           # green gem pendant
    (7888, 'glacier amulet', 113, 2, 815),         # ice gem pendant
    (7889, 'lightning pendant', 113, 1, 816),      # blue eye medallion
    (7890, 'magma amulet', 113, 4, 817),           # red gem pendant
    (24851, 'onyx pendant', 136, 6, 22195),        # gold loop, dark beads
    (15403, 'necklace of the deep', 136, 0, 13990),  # blue chain, gold drop
    (18402, 'gill necklace', 136, 2, 16108),       # blue chain, gold clasp
    (18407, 'prismatic necklace', 115, 9, 16113),  # copper chain, blue drop
    (27652, 'exotic amulet', 136, 4, 24996),       # gold chain, amber stone
    (26807, 'foxtail amulet', 136, 3, 24151),      # blue chain, gold claws
    (27251, 'rainbow necklace', 136, 1, 24595),    # blue chain, gold claws and gem
    (27215, 'cobra amulet', 136, 5, 24559),        # gold chain, blue gem
)
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']


class ArtError(Exception):
    pass


def lib_bases(path=LIB):
    """[(server id, look, stock client id)] of chaos_jewelry.lua J.bases, rings then necklaces"""
    text = open(path, encoding='utf-8').read()
    block = text.partition('J.bases = {')[2].partition('\n}\n')[0]
    return [(int(a), int(b), int(c)) for a, b, c in
            re.findall(r'\{id = (\d+), level = \d+, name = "[^"]+", look = (\d+), stock = (\d+)\}', block)]


def things_text():
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    for k, (sid, name, _r, _c, stock) in enumerate(PICKS):
        w.writerow(['jewelry_%d' % sid, 'item', 'look', name, 'jewelry', k * 32, 0, 1, 1, 1, 1, 'copy:%d' % stock,
                    'replace', sid, ''])
    return out.getvalue()


def cut(sheet):
    """the atlas (32 x 29*32 RGBA) from the full 32 px sheet"""
    if sheet.shape[1] != SOURCE['size'][0] or sheet.shape[0] != SOURCE['size'][1]:
        raise ArtError('sheet %dx%d, expected %dx%d' % ((sheet.shape[1], sheet.shape[0]) + SOURCE['size']))
    tiles = []
    for sid, _n, r, c, _s in PICKS:
        cell = sheet[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL]
        half = cell[0::2, 0::2]
        if not (half.repeat(2, 0).repeat(2, 1) == cell).all():
            raise ArtError('cell %d,%d (%d) is not 16 px art doubled' % (r, c, sid))
        if set(np.unique(half[..., 3])) - {0, 255}:
            raise ArtError('cell %d,%d (%d) has soft alpha' % (r, c, sid))
        half = half.copy()
        half[half[..., 3] == 0] = 0
        t = P.scale2x(half)
        if not t[..., 3].any():
            raise ArtError('cell %d,%d (%d) is empty' % (r, c, sid))
        tiles.append(t)
    return np.concatenate(tiles, axis=1)


def check_spec():
    """problems of PICKS against chaos_jewelry.lua"""
    out = []
    lib = lib_bases()
    if [s for s, _l, _k in lib] != [p[0] for p in PICKS]:
        out.append('PICKS and chaos_jewelry.lua J.bases name other server ids or another order')
    if [k for _s, _l, k in lib] != [p[4] for p in PICKS]:
        out.append('PICKS and chaos_jewelry.lua J.bases name other stock client ids')
    want = list(range(FIRST_CLIENT_ID, FIRST_CLIENT_ID + len(PICKS)))
    if [l for _s, l, _k in lib] != want:
        out.append('chaos_jewelry.lua looks are not %d..%d in order' % (want[0], want[-1]))
    cells = [(p[2], p[3]) for p in PICKS]
    if len(set(cells)) != len(cells):
        out.append('two picks share a cell')
    return out


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(atlas, outdir):
    os.makedirs(outdir, exist_ok=True)
    z, pad, n = 4, 8, atlas.shape[1] // 32
    cols = 10
    rows = (n + cols - 1) // cols
    W, H = pad + cols * (32 * z + pad), 2 * rows * (32 * z + pad) + pad
    im = Image.new('RGBA', (W, H), (214, 200, 170, 255))
    im.paste(Image.new('RGBA', (W, H // 2), (40, 36, 34, 255)), (0, H // 2))
    for k in range(n):
        tile = Image.fromarray(atlas[:, k * 32:(k + 1) * 32]).resize((32 * z, 32 * z), Image.NEAREST)
        for half in (0, 1):
            x = pad + (k % cols) * (32 * z + pad)
            y = half * (H // 2) + pad + (k // cols) * (32 * z + pad)
            im.alpha_composite(tile, (x, y))
    p = os.path.join(outdir, 'jewelry.png')
    im.convert('RGB').save(p)
    print('preview', p)


def load_sheet(path):
    data = open(path, 'rb').read()
    md5 = hashlib.md5(data).hexdigest()
    if md5 != SOURCE['md5']:
        raise ArtError('%s: md5 %s, expected %s' % (path, md5, SOURCE['md5']))
    return np.array(Image.open(io.BytesIO(data)).convert('RGBA'))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--src', default=None, help='the 32 px full sheet of the icon set')
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for jewelry.png at 4x')
    a = ap.parse_args()
    bad = check_spec()
    for b in bad:
        print('spec:', b)
    if bad:
        return 1
    things = things_text()
    try:
        atlas = cut(load_sheet(a.src)) if a.src else None
    except ArtError as e:
        print('error:', e)
        return 1
    if a.check:
        ok = True
        if not os.path.exists(THINGS) or open(THINGS, encoding='utf-8').read() != things:
            print('stale:', os.path.relpath(THINGS, HERE))
            ok = False
        if not os.path.exists(ATLAS):
            print('missing:', os.path.relpath(ATLAS, HERE))
            ok = False
        else:
            have = np.array(Image.open(ATLAS).convert('RGBA'))
            if have.shape != (32, 32 * len(PICKS), 4):
                print('atlas size %s, expected 32 x %d' % (have.shape[:2], 32 * len(PICKS)))
                ok = False
            elif atlas is not None and not np.array_equal(have, atlas):
                print('stale:', os.path.relpath(ATLAS, HERE))
                ok = False
        print('jewelry looks up to date' if ok else 'run: python3 -I gen_jewelry_art.py build --src SHEET')
        return 0 if ok else 1
    if atlas is None:
        print('build needs --src SHEET (the 32 px full sheet, md5 %s)' % SOURCE['md5'])
        return 2
    with open(ATLAS, 'wb') as f:
        f.write(png_bytes(atlas))
    with open(THINGS, 'w', encoding='utf-8', newline='') as f:
        f.write(things)
    print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0])
    print('things', THINGS)
    if a.preview:
        preview(atlas, a.preview)
    return 0


if __name__ == '__main__':
    sys.exit(main())
