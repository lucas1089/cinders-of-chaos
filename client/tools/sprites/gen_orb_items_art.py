#!/usr/bin/env python3
"""Orb item looks: the 18 crafting bench orbs in one drawing line, 32 x 32 pixel art (pair 63, O482; client/MANIFEST.md
"Orb looks").

    python3 -I gen_orb_items_art.py build [--check]           # write the outputs from art_import/orbs_src.png
    python3 -I gen_orb_items_art.py pack DIR                  # (re)make art_import/orbs_src.png from DIR/<slug>.png
    python3 -I gen_orb_items_art.py strips                    # the redraw_items.py arguments of the eight in-place looks
    python3 -I gen_orb_items_art.py style                     # style_check of every cell against every theme (a report)
    python3 -I gen_orb_items_art.py build --preview DIR --dat P/Tibia.dat --spr P/Tibia.spr   # old looks beside the new

History: the first look drawn here (pair 38, Orb of Sockets, client 38641) was a sphere drawn per pixel in code, snapped to a
theme palette. Owner, 2026-11-11 (translated), on the Ember Orb and the Orb of Binding: "Redo these 2 first orbs"; on the
Void Orb: "This last orb too. It looks like a small stone."; then: "Generate all the other orbs too. Let us keep them all in the
same line." After the options: "A, b, c" (Ember, Binding, Void), and on the full sheet with a suggestion per orb: "You can go
ahead with your recommendations." The code-drawn Orb of Sockets and the per-pixel drawing code are gone; the other 17 orbs wore
looks of base things (inlay stones, essence crystals, a gem), of the owner's art sets and of rune stones.

New art: 18 pixel art cells of 32 px made with the tool named in docs/CREDITS.md "Tools" (PixelLab; one prompt an orb, candidates
picked by the owner's sheet). Nothing is repainted: no recolour, no resize, no outline pass. They are committed as one sheet,
the only input of this generator:

  art_import/orbs_src.png    192 x 96 RGBA, alpha 0 / 255 only: 6 columns x 3 rows, the orbs in bench order (LOOKS), reading
                             order (Ember, Binding, Whetstone, Unveiling, Awakening, Gilding / Grafting, Reforging, Tempering,
                             Crown, Sockets, Ruin / Unmaking, Erasure, Upheaval, Fate, Excision, Void)

One look, one item. Ten orbs are copies of stock nodes (inlay stones, essence crystals, moonlight crystals, crowned gems, a
small enchanted amethyst) whose client sprite other stock items wear too (essences and stones drop; the Void Orb's stack has
eight count patterns): those ten get a NEW client item each, appended to the pair (ids from FIRST_CLIENT_ID, flags copied from
the stock thing, one phase, one pattern), and the server points the orb's node at it once the client pair has it
(`look` in data/lib/chaos_orbs_config.lua, server/tools/install_orbs.py). The other eight client ids belong to their orb alone:
they are redrawn in place (redraw_items.py --strip), nothing moves on the server.

Outputs (committed): art_import/orb_items.png (the 18 cells stacked, 32 x 576, LOOKS order: the atlas of redraw_items.py
--strip and of the importer) and art_import/orb_items.csv (the things file of import_art_things.py for the ten new ids: mode
replace with the orb's server id). `build --check` (CI) rebuilds and compares, writes nothing. Deterministic: numpy and Pillow
only, no randomness.
"""
import argparse, csv, io, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
SOURCE = os.path.join(ART, 'orbs_src.png')
ATLAS = os.path.join(ART, 'orb_items.png')
THINGS = os.path.join(ART, 'orb_items.csv')
FIRST_CLIENT_ID = 44550   # after the last item of pair 62 (44549); the ten new looks follow in LOOKS order
COLS, ROWS = 6, 3
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']

# slug, item name, server id, client id before, 'new' (own client item, flags copied from the stock thing = client id before) or
# 'redraw' (the client id before is the orb's alone: drawn in place). Bench order = the order of the owner's sheet.
LOOKS = (
    ('ember', 'ember orb', 32258, 25045, 'new'),
    ('binding', 'orb of binding', 32252, 25047, 'new'),
    ('whetstone', 'whetstone', 32256, 22083, 'new'),
    ('unveiling', 'orb of unveiling', 32257, 25046, 'new'),
    ('awakening', 'orb of awakening', 29851, 27195, 'redraw'),
    ('gilding', 'orb of gilding', 24691, 33000, 'redraw'),
    ('grafting', 'orb of grafting', 29855, 27199, 'redraw'),
    ('reforging', 'orb of reforging', 32254, 25048, 'new'),
    ('tempering', 'orb of tempering', 32251, 24483, 'new'),
    ('crown', 'crown orb', 32259, 25044, 'new'),
    ('sockets', 'orb of sockets', 24692, 38641, 'redraw'),
    ('ruin', 'orb of ruin', 32255, 24477, 'new'),
    ('unmaking', 'orb of unmaking', 24697, 33001, 'redraw'),
    ('erasure', 'orb of erasure', 24688, 33002, 'redraw'),
    ('upheaval', 'orb of upheaval', 29856, 27200, 'redraw'),
    ('fate', 'orb of fate', 29857, 27201, 'redraw'),
    ('excision', 'orb of excision', 32253, 25049, 'new'),
    ('void', 'void orb', 32260, 678, 'new'),
)


def new_ids():
    """slug -> the new client id of the ten appended looks (LOOKS order from FIRST_CLIENT_ID)"""
    out, n = {}, FIRST_CLIENT_ID
    for slug, _name, _sid, _old, how in LOOKS:
        if how == 'new':
            out[slug] = n
            n += 1
    return out


def check_source(sheet):
    """the committed sheet: 192 x 96 RGBA, alpha 0 / 255, no colour under alpha 0, every cell drawn"""
    assert sheet.shape == (32 * ROWS, 32 * COLS, 4), 'orbs_src.png is %d x %d, not %d x %d' % (
        sheet.shape[1], sheet.shape[0], 32 * COLS, 32 * ROWS)
    assert set(np.unique(sheet[..., 3]).tolist()) <= {0, 255}, 'alpha must be 0 / 255'
    assert not sheet[sheet[..., 3] == 0].any(), 'colour under alpha 0 must be 0'
    assert len(LOOKS) == COLS * ROWS
    for k in range(len(LOOKS)):
        assert cell(sheet, k)[..., 3].any(), 'empty cell %s' % LOOKS[k][0]


def cell(sheet, k):
    """the 32 x 32 cell of look k (reading order of the grid)"""
    r, c = divmod(k, COLS)
    return sheet[r * 32:(r + 1) * 32, c * 32:(c + 1) * 32]


def pack(src_dir):
    """the sheet of DIR/<slug>.png files (32 x 32 RGBA, no partial alpha), the colour under alpha 0 cleared"""
    sheet = np.zeros((32 * ROWS, 32 * COLS, 4), np.uint8)
    for k, (slug, *_r) in enumerate(LOOKS):
        a = np.array(Image.open(os.path.join(src_dir, slug + '.png')).convert('RGBA'))
        assert a.shape == (32, 32, 4), '%s.png is not 32 x 32' % slug
        assert set(np.unique(a[..., 3]).tolist()) <= {0, 255}, '%s.png has partial alpha' % slug
        a[a[..., 3] == 0] = 0
        r, c = divmod(k, COLS)
        sheet[r * 32:(r + 1) * 32, c * 32:(c + 1) * 32] = a
    return sheet


def build(sheet):
    """(atlas RGBA 32 x 576, things csv text)"""
    check_source(sheet)
    atlas = np.concatenate([cell(sheet, k) for k in range(len(LOOKS))], axis=0)
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    for k, (slug, name, sid, old, how) in enumerate(LOOKS):
        if how == 'new':
            w.writerow(['orb_' + slug, 'item', 'look', name, 'orb_items', 0, k * 32, 1, 1, 1, 1, 'copy:%d' % old, 'replace',
                        sid, ''])
    return atlas, out.getvalue()


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False, compress_level=9)
    return buf.getvalue()


def strips():
    """the --strip arguments of redraw_items.py for the in-place looks"""
    return ['%d=client/tools/sprites/art_import/orb_items.png@%d' % (old, k)
            for k, (_s, _n, _sid, old, how) in enumerate(LOOKS) if how == 'redraw']


def style_report(sheet):
    """per cell: the themes it passes and the reasons of the best fit; a report, never a failure"""
    data = sc.load_palettes()
    lines = []
    for k, (slug, *_r) in enumerate(LOOKS):
        tile = np.ascontiguousarray(cell(sheet, k))
        results = []
        for theme, t in data['themes'].items():
            pal = np.array([sc.unhex(x) for x in t['palette']], np.uint8)
            bad, _warn = sc.judge(sc.measure(tile), pal, t['light'], data['thresholds'])
            results.append((len(bad), theme, bad))
        results.sort()
        ok = [th for n, th, _b in results if n == 0]
        lines.append('%-10s passes %s' % (slug, ', '.join(ok) if ok else 'no theme; best %s: %s' % (
            results[0][1], '; '.join(results[0][2]))))
    return lines


def preview(atlas, outdir, dat, spr):
    """orb_items_before_after.png: per look the old client thing (from the pair) and the new tile, 4x, light / dark"""
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    z, pad = 4, 8
    n = len(LOOKS)
    W, H = pad + n * 2 * (32 * z + pad), 2 * (32 * z + 2 * pad)
    im = Image.new('RGBA', (W, H))
    for row, bg in enumerate(((214, 200, 170, 255), (40, 36, 34, 255))):
        im.paste(Image.new('RGBA', (W, H // 2), bg), (0, row * H // 2))
        for k, (_slug, _n, _sid, old, _how) in enumerate(LOOKS):
            before = render_item(d, s, old, box=32).convert('RGBA').resize((32 * z, 32 * z), Image.NEAREST)
            after = Image.fromarray(atlas[k * 32:(k + 1) * 32]).resize((32 * z, 32 * z), Image.NEAREST)
            for j, tile in enumerate((before, after)):
                im.alpha_composite(tile, (pad + (2 * k + j) * (32 * z + pad), row * H // 2 + pad))
    p = os.path.join(outdir, 'orb_items_before_after.png')
    im.convert('RGB').save(p)
    print('preview', p)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'pack', 'strips', 'style'])
    ap.add_argument('dir', nargs='?', help='pack: the folder with <slug>.png files')
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for orb_items_before_after.png (needs --dat / --spr)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    a = ap.parse_args()
    if a.cmd == 'pack':
        if not a.dir:
            sys.exit('pack needs the folder with the <slug>.png files')
        with open(SOURCE, 'wb') as f:
            f.write(png_bytes(pack(a.dir)))
        print('wrote', os.path.relpath(SOURCE, HERE))
        return 0
    sheet = np.asarray(Image.open(SOURCE).convert('RGBA'))
    if a.cmd == 'strips':
        print(' '.join('--strip ' + s for s in strips()))
        return 0
    if a.cmd == 'style':
        print('\n'.join(style_report(sheet)))
        return 0
    atlas, things = build(sheet)
    if a.check:
        ok = True
        if not os.path.exists(ATLAS) or not np.array_equal(np.array(Image.open(ATLAS).convert('RGBA')), atlas):
            print('stale:', os.path.relpath(ATLAS, HERE))
            ok = False
        if not os.path.exists(THINGS) or open(THINGS, encoding='utf-8').read() != things:
            print('stale:', os.path.relpath(THINGS, HERE))
            ok = False
        print('orb item looks up to date (%d orbs, %d new client ids)' % (len(LOOKS), len(new_ids())) if ok
              else 'run: python3 -I gen_orb_items_art.py build')
        return 0 if ok else 1
    with open(ATLAS, 'wb') as f:
        f.write(png_bytes(atlas))
    with open(THINGS, 'w', encoding='utf-8', newline='') as f:
        f.write(things)
    ids = new_ids()
    print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; new client ids %d..%d' % (min(ids.values()), max(ids.values())))
    print('things', THINGS)
    if a.preview:
        if not (a.dat and a.spr):
            sys.exit('--preview needs --dat and --spr (the pair with the old looks)')
        preview(atlas, a.preview, a.dat, a.spr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
