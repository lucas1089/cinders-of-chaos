#!/usr/bin/env python3
"""The item looks of the four store items (Loot Bag, Orbs Pouch, Rift Key Pouch, Everfull Ration), each snapped to one
theme palette of docs/SPRITE_STYLE.md, written as the 32 px atlas art_import/store_items.png (4 x 1 tiles, in server
id order 32081..32084) and the things file art_import/store_items.csv that import_art_things.py appends (pair 34,
client ids 38608..38611; client/MANIFEST.md "Store item looks, theme palettes").

python3 -I gen_store_items_art.py build [--check] [--preview DIR]

Our own art only: the source tiles are our earlier store looks in git, art_import/pouches.png (gen_pouch_art.py:
orbs, keys, loot) and art_import/store_food.png (gen_store_food_art.py: the ration). Those were downsampled from
128 px shape fields and kept every in-between colour (362 to 425 colours a tile, `style_check.py check` refused them).
Here every pixel moves to the nearest colour of the theme that matches its store icon best (CIE76, the checker's
`snap`), so each look keeps its silhouette and colours and passes the checker:
  Loot Bag        gildcrown       brown leather sack, gold trim, gold coins
  Orbs Pouch      rimewraith      violet velvet pouch, a cyan orb in a gold bezel
  Rift Key Pouch  azurevigil      steel strongbox with riveted bands, a gold key
  Everfull Ration cinderwrought   roast haunch with its bone on a glazed bowl, gold sparks
`build` refuses to write a tile that fails `style_check.py` against its theme. `--check` (CI) compares the atlas and
the things file with the committed ones and writes nothing. `--preview DIR` writes before / after at 4x (nearest) on
a light and a dark ground. Deterministic: integer RGB in, the same palette and nearest colour out.
"""
import argparse, csv, io, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
ATLAS = os.path.join(ART, 'store_items.png')
THINGS = os.path.join(ART, 'store_items.csv')
FIRST_CLIENT_ID = 38608   # after the last item of pair 33 (38607)

# key, things name, source atlas, source tile, theme, flags copied from (client id), server id
LOOKS = (
    ('store_loot', 'loot bag', 'pouches.png', 2, 'gildcrown', 10325, 32081),
    ('store_orbs', 'orbs pouch', 'pouches.png', 0, 'rimewraith', 8861, 32082),
    ('store_keys', 'rift key pouch', 'pouches.png', 1, 'azurevigil', 7343, 32083),
    ('store_ration', 'everfull ration', 'store_food.png', 0, 'cinderwrought', 3583, 32084),
)
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']


def source(name, tile):
    a = np.array(Image.open(os.path.join(ART, name)).convert('RGBA'))
    return a[:32, tile * 32:(tile + 1) * 32].copy()


def build():
    """(atlas RGBA, things csv text, [(key, theme, reasons)])"""
    data = sc.load_palettes()
    tiles, report = [], []
    for key, _n, src, tile, theme, _c, _s in LOOKS:
        t = data['themes'][theme]
        pal = np.array([sc.unhex(x) for x in t['palette']], np.uint8)
        a = source(src, tile)
        a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)   # hard alpha (the sources have it already)
        a[a[..., 3] == 0] = 0
        s = sc.snap(a, pal)
        bad, _warn = sc.judge(sc.measure(s), pal, t['light'], data['thresholds'])
        report.append((key, theme, bad))
        tiles.append(s)
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    for k, (key, name, _src, _t, _th, copy, sid) in enumerate(LOOKS):
        w.writerow([key, 'item', 'look', name, 'store_items', k * 32, 0, 1, 1, 1, 1, 'copy:%d' % copy, 'replace',
                    sid, ''])
    return np.concatenate(tiles, axis=1), out.getvalue(), report


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(atlas, outdir):
    """before.png / after.png: each look at 4x on a light and a dark ground, the four side by side"""
    os.makedirs(outdir, exist_ok=True)
    before = np.concatenate([source(src, tile) for _k, _n, src, tile, _t, _c, _s in LOOKS], axis=1)
    for name, a in (('before', before), ('after', atlas)):
        z, pad = 4, 8
        n = a.shape[1] // 32
        W, H = pad + n * (32 * z + pad), 2 * (32 * z + 2 * pad)
        im = Image.new('RGBA', (W, H))
        for row, bg in enumerate(((214, 200, 170, 255), (40, 36, 34, 255))):
            im.paste(Image.new('RGBA', (W, H // 2), bg), (0, row * H // 2))
            for k in range(n):
                tile = Image.fromarray(a[:, k * 32:(k + 1) * 32]).resize((32 * z, 32 * z), Image.NEAREST)
                im.alpha_composite(tile, (pad + k * (32 * z + pad), row * H // 2 + pad))
        p = os.path.join(outdir, name + '.png')
        im.convert('RGB').save(p)
        print('preview', p)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for before.png / after.png')
    a = ap.parse_args()
    atlas, things, report = build()
    failed = False
    for key, theme, bad in report:
        print('%s %s: %s' % (key, theme, 'style PASS' if not bad else 'style FAIL'))
        for b in bad:
            print('  ' + b)
            failed = True
    if failed:
        return 1
    if a.check:
        ok = True
        if not os.path.exists(ATLAS) or not np.array_equal(np.array(Image.open(ATLAS).convert('RGBA')), atlas):
            print('stale:', os.path.relpath(ATLAS, HERE))
            ok = False
        if not os.path.exists(THINGS) or open(THINGS, encoding='utf-8').read() != things:
            print('stale:', os.path.relpath(THINGS, HERE))
            ok = False
        print('store item looks up to date' if ok else 'run: python3 -I gen_store_items_art.py build')
        return 0 if ok else 1
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
