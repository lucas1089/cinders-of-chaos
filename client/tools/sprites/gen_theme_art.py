#!/usr/bin/env python3
"""Themed art of things_custom24: ten equipment sets, two auras and a pair of wings, four grounds with borders.

    python3 -I gen_theme_art.py build              # -> art_import/theme/*.png + art_import/theme_things.csv
    python3 -I gen_theme_art.py build --check      # rebuild in memory, compare with the checked-in atlases and spec
    python3 -I gen_theme_art.py recolour --dat D --spr S [--check]
                                                   # elemental variants of monster looks of our pair D / S
                                                   # -> art_import/theme_recolour/*.png + art_import/theme_recolour.csv
    python3 -I gen_theme_art.py preview --out DIR [--dat D --spr S]
                                                   # contact sheets 1x / 4x, items on an inventory background,
                                                   # auras and wings on a player look in four directions (from the
                                                   # pair D / S when given), ground patches with their borders

Our own procedural art (theme_items.py, theme_cosmetics.py, theme_grounds.py): shapes, noise and ramps in Python,
fixed seeds, no painting service, and no pixel of any other game, client or reference sheet is read. The reference
sheets the owner showed were looked at for themes only. Deterministic for one Pillow and numpy version: the
checked-in atlases were made with Pillow 12.3.0 and numpy 2.5.3 (CI checks with those, as for gen_class_fx.py).

Output, imported by import_art_things.py (client/MANIFEST.md "Themed sets, auras and grounds"):
  items     theme/items_<set>.png: one column per piece, 8 rows (the stack patterns of arrows and bolts; other
            pieces use row 0). Dat flags copied from a stock item of the same kind (copy:<client id>), so slots,
            pickupable, stackable and container stay the stock ones.
  grounds   theme/grounds_<family>.png: the ground and its 12 border pieces side by side, each 16 patterns (4 x 4,
            stacked down) by its phases (across).
  outfits   theme/<key>.png in the import outfit layout: rows = phases, columns = layer * 4 + direction.
Checks (build stops otherwise): alpha 0 / 255 everywhere; every item, ground pattern and outfit frame has art; grounds
opaque; border pieces continuous along the edges they continue; auras and wings never touch the frame edge.
"""
import argparse
import csv
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np
from PIL import Image

ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'theme')
SPEC = os.path.join(ART, 'theme_things.csv')
RC_OUT = os.path.join(ART, 'theme_recolour')
RC_SPEC = os.path.join(ART, 'theme_recolour.csv')

COPY = {   # dat flags of a stock item per kind (client ids of the 10.98 pair)
    'sword': 3264, 'axe': 3274, 'club': 3270, 'bow': 3350, 'crossbow': 3349, 'wand': 3066, 'rod': 3066,
    'shield': 3409, 'spellbook': 3059, 'helmet': 3351, 'armor': 3357, 'legs': 3557, 'boots': 3552, 'amulet': 3572,
    'ring': 3063, 'backpack': 2854, 'arrow': 3447, 'bolt': 3446,
}
AURA_MS = {'blood_vortex': 110, 'rune_seal': 140, 'runic_wings': 150}
NAMES = {'blood_vortex': 'Blood Vortex', 'rune_seal': 'Rune Seal', 'runic_wings': 'Runic Wings'}
PIECE_NAME = {'n': 'north edge', 'e': 'east edge', 's': 'south edge', 'w': 'west edge', 'outer_ne': 'outer corner ne',
              'outer_nw': 'outer corner nw', 'outer_se': 'outer corner se', 'outer_sw': 'outer corner sw',
              'inner_ne': 'inner corner ne', 'inner_nw': 'inner corner nw', 'inner_se': 'inner corner se',
              'inner_sw': 'inner corner sw'}


def png_bytes(arr):
    b = io.BytesIO()
    Image.fromarray(arr, 'RGBA').save(b, format='PNG', optimize=False)
    return b.getvalue()


def binary_alpha(arr, what, bad):
    a = arr[..., 3]
    if ((a != 0) & (a != 255)).any():
        bad.append('%s: alpha not 0 / 255' % what)


def build(log=print):
    """-> ({atlas name: RGBA array}, spec rows, problems)"""
    import theme_items as TI
    import theme_sets as TS
    import theme_cosmetics as TC
    import theme_grounds as TG
    atlases, rows, bad = {}, [], []
    # ---- items
    for s in TS.SETS:
        ps = TS.pieces(s)
        sheet = np.zeros((8 * 32, len(ps) * 32, 4), np.uint8)
        for i, (key, kind, style, name, kit) in enumerate(ps):
            tiles = TI.render(kind, s['th'], style)
            for p, t in enumerate(tiles):
                if not t[..., 3].any():
                    bad.append('%s pattern %d: empty' % (key, p))
                binary_alpha(t, key, bad)
                sheet[p * 32:(p + 1) * 32, i * 32:(i + 1) * 32] = t
            n = len(tiles)
            extra = 'set=%s|kind=%s|kit=%s' % (s['key'], kind, kit or '')
            if n > 1:
                extra = 'px=4|py=2|' + extra
            rows.append(dict(key=key, cat='item', kind=kind, name=name, atlas='theme/items_%s' % s['key'], x=i * 32, y=0,
                             w=1, h=1, patterns=n, phases=1, flags='copy:%d' % COPY[kind], mode='new', server_id='',
                             extra=extra))
        atlases['items_%s' % s['key']] = sheet
        log('items %s: %d pieces' % (s['key'], len(ps)))
    # ---- grounds
    for fam in TG.FAMILIES:
        art = TG.build_family(fam)
        bad += TG.check(fam, art)
        n = fam['phases']
        things = ['ground'] + list(TG.PIECES)
        sheet = np.zeros((16 * 32, len(things) * n * 32, 4), np.uint8)
        for i, th in enumerate(things):
            for ph in range(n):
                for (px, py), t in art[th][ph].items():
                    binary_alpha(t, '%s %s' % (fam['key'], th), bad)
                    p = py * 4 + px
                    x0 = (i * n + ph) * 32
                    sheet[p * 32:(p + 1) * 32, x0:x0 + 32] = t
            if th == 'ground':
                fl = ['ground:%d' % fam['speed'], 'notmoveable', 'minimap:%d' % fam['minimap'], 'fullground']
                if not fam['walk']:
                    fl.append('notwalkable')
                if fam['light']:
                    fl.append('light:%d:%d' % fam['light'])
                key, kind, name = 'ground_%s' % fam['key'], 'ground', fam['name']
            else:
                fl = ['clip', 'notmoveable']
                key, kind, name = 'border_%s_%s' % (fam['key'], th), 'border', '%s (%s)' % (fam['name'], PIECE_NAME[th])
            extra = 'px=4|py=4|family=%s' % fam['key'] + ('|piece=%s' % th if th != 'ground' else '')
            if n > 1:
                extra += '|ms=%d' % fam['ms']
            rows.append(dict(key=key, cat='item', kind=kind, name=name, atlas='theme/grounds_%s' % fam['key'],
                             x=i * n * 32, y=0, w=1, h=1, patterns=16, phases=n, flags=' '.join(fl), mode='new',
                             server_id='', extra=extra))
        atlases['grounds_%s' % fam['key']] = sheet
        log('grounds %s: 1 ground + %d border pieces, %d phases' % (fam['key'], len(TG.PIECES), n))
    # ---- auras and wings
    for key, (role, fn) in TC.KINDS.items():
        fr = TC.frames(key)
        bad += TC.check(key, fr)
        layers = 2 if role == 'aura' else 1
        sheet = np.zeros((TC.PHASES * 96, layers * 4 * 96, 4), np.uint8)
        for t, row in enumerate(fr):
            for d, ls in enumerate(row):
                for layer, img in enumerate(ls):
                    c = layer * 4 + d
                    sheet[t * 96:(t + 1) * 96, c * 96:(c + 1) * 96] = img
        atlases[key] = sheet
        ms = AURA_MS[key]
        flags = 'animateAlways' + (' displacement:%d:%d' % TC.AURA_DISP if role == 'aura' else '')
        rows.append(dict(key=key, cat='outfit', kind=role, name=NAMES[key], atlas='theme/%s' % key, x=0, y=0, w=3, h=3,
                         patterns=4, phases=TC.PHASES, flags=flags, mode='new', server_id='',
                         extra='gtypes=1|layers=%d|exact=96|durs0=%s|anim0=0:0:0' % (layers, '/'.join([str(ms)] * TC.PHASES))))
        log('%s: %s, 3x3, %d layer(s), %d phases' % (key, role, layers, TC.PHASES))
    return atlases, rows, bad


FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']


def spec_text(rows):
    b = io.StringIO()
    w = csv.DictWriter(b, FIELDS, lineterminator='\n')
    w.writeheader()
    for r in rows:
        w.writerow(r)
    return b.getvalue()


def cmd_build(check):
    atlases, rows, bad = build()
    if bad:
        for b in bad[:40]:
            print('problem:', b)
        sys.exit('%d problems: nothing written' % len(bad))
    text = spec_text(rows)
    if check:
        diff = []
        for name, arr in atlases.items():
            path = os.path.join(OUT, name + '.png')
            if not os.path.isfile(path):
                diff.append('missing ' + path)
                continue
            old = np.asarray(Image.open(path).convert('RGBA'))
            if old.shape != arr.shape or not np.array_equal(old, arr):
                diff.append('differs: ' + path)
        extra = sorted(set(f[:-4] for f in os.listdir(OUT) if f.endswith('.png')) - set(atlases)) if os.path.isdir(OUT) else []
        diff += ['not made by the generator: %s.png' % e for e in extra]
        if not os.path.isfile(SPEC) or open(SPEC, newline='').read() != text:
            diff.append('differs: ' + SPEC)
        if diff:
            print('\n'.join(diff))
            sys.exit('gen_theme_art.py build --check: %d differences (run build and commit)' % len(diff))
        print('check: %d atlases and %s match the generator' % (len(atlases), os.path.relpath(SPEC, HERE)))
        return
    os.makedirs(OUT, exist_ok=True)
    for name, arr in atlases.items():
        open(os.path.join(OUT, name + '.png'), 'wb').write(png_bytes(arr))
    open(SPEC, 'w', newline='').write(text)
    n_items = sum(1 for r in rows if r['cat'] == 'item')
    print('wrote %d atlases to %s and %s (%d items, %d outfits)' % (len(atlases), os.path.relpath(OUT, HERE),
                                                                   os.path.relpath(SPEC, HERE), n_items,
                                                                   len(rows) - n_items))


def cmd_recolour(dat, spr, check):
    """recolour variants of shipped monster looks (theme_recolour.py): needs the pair, so a separate spec and step"""
    from datspr import Dat, Spr
    import theme_recolour as TR
    D, S = Dat(dat), Spr(spr)
    out = TR.variant_sheets(D, S)
    rows = [o[3] for o in out]
    text = spec_text(rows)
    if check:
        diff = []
        for key, name, sheet, spec in out:
            path = os.path.join(RC_OUT, key + '.png')
            if not os.path.isfile(path) or not np.array_equal(np.asarray(Image.open(path).convert('RGBA')), sheet):
                diff.append('differs: ' + path)
        if not os.path.isfile(RC_SPEC) or open(RC_SPEC, newline='').read() != text:
            diff.append('differs: ' + RC_SPEC)
        if diff:
            print('\n'.join(diff))
            sys.exit('gen_theme_art.py recolour --check: %d differences' % len(diff))
        print('check: %d recolour sheets and %s match' % (len(out), os.path.relpath(RC_SPEC, HERE)))
        return
    os.makedirs(RC_OUT, exist_ok=True)
    for key, name, sheet, spec in out:
        open(os.path.join(RC_OUT, key + '.png'), 'wb').write(png_bytes(sheet))
    open(RC_SPEC, 'w', newline='').write(text)
    print('wrote %d recolour sheets to %s and %s' % (len(out), os.path.relpath(RC_OUT, HERE), os.path.relpath(RC_SPEC, HERE)))


# ------------------------------------------------------------------------------------------------ previews
def inv_bg(w, h):
    """an inventory panel of our own: dark slots with a bevel"""
    bg = np.zeros((h, w, 4), np.uint8)
    bg[...] = (36, 32, 30, 255)
    return bg


def slot_img():
    s = np.zeros((36, 36, 4), np.uint8)
    s[...] = (20, 18, 18, 255)
    s[0, :, :3] = s[:, 0, :3] = (10, 9, 9)
    s[-1, :, :3] = s[:, -1, :3] = (70, 62, 54)
    s[1:-1, 1:-1, :3] = (44, 40, 38)
    return s


def paste(dst, src, x, y):
    h, w = src.shape[:2]
    a = src[..., 3:4].astype(np.float32) / 255
    blk = dst[y:y + h, x:x + w]
    blk[..., :3] = (src[..., :3] * a + blk[..., :3] * (1 - a)).astype(np.uint8)
    blk[..., 3] = np.maximum(blk[..., 3], src[..., 3])


def cmd_preview(out, dat, spr):
    import theme_sets as TS
    import theme_grounds as TG
    import theme_cosmetics as TC
    import darklib as L
    os.makedirs(out, exist_ok=True)
    atlases = {}
    for f in os.listdir(OUT):
        atlases[f[:-4]] = np.asarray(Image.open(os.path.join(OUT, f)).convert('RGBA'))
    rows = list(csv.DictReader(open(SPEC, newline='')))
    # items: contact sheet 1x and 4x, and on inventory slots
    sets = TS.SETS
    ncol = max(len(TS.pieces(s)) for s in sets)
    for z in (1, 4):
        cw = 32 * z + 4 * z
        im = np.zeros((len(sets) * cw + 4, ncol * cw + 4, 4), np.uint8)
        im[...] = (58, 52, 46, 255)
        for j, s in enumerate(sets):
            a = atlases['items_%s' % s['key']]
            for i in range(len(TS.pieces(s))):
                t = a[0:32, i * 32:(i + 1) * 32]
                t = np.asarray(Image.fromarray(t).resize((32 * z, 32 * z), Image.NEAREST))
                paste(im, t, 4 + i * cw, 4 + j * cw)
        Image.fromarray(im).convert('RGB').save(os.path.join(out, 'items_%dx.png' % z))
    # inventory: one panel per set, slots 36 px at 2x
    z = 2
    panels = []
    for s in sets:
        ps = TS.pieces(s)
        a = atlases['items_%s' % s['key']]
        cols = 7
        nr = (len(ps) + cols - 1) // cols
        pan = inv_bg(cols * 38 + 6, nr * 38 + 6)
        for i in range(len(ps)):
            x, y = 3 + (i % cols) * 38, 3 + (i // cols) * 38
            paste(pan, slot_img(), x, y)
            paste(pan, a[0:32, i * 32:(i + 1) * 32], x + 2, y + 2)
        panels.append(np.asarray(Image.fromarray(pan).resize((pan.shape[1] * z, pan.shape[0] * z), Image.NEAREST)))
    W = max(p.shape[1] for p in panels)
    H = sum(p.shape[0] + 8 for p in panels)
    im = np.zeros((H, W, 4), np.uint8); im[...] = (14, 12, 12, 255)
    y = 0
    for p in panels:
        paste(im, p, 0, y); y += p.shape[0] + 8
    Image.fromarray(im).convert('RGB').save(os.path.join(out, 'items_inventory.png'))
    # arrows and bolts: the 8 stack patterns
    stk = np.zeros((len(sets) * 2 * 36 + 4, 8 * 36 + 4, 4), np.uint8); stk[...] = (58, 52, 46, 255)
    k = 0
    for s in sets:
        ps = TS.pieces(s)
        a = atlases['items_%s' % s['key']]
        for i, (key, kind, *_r) in enumerate(ps):
            if kind in ('arrow', 'bolt'):
                for p in range(8):
                    paste(stk, a[p * 32:(p + 1) * 32, i * 32:(i + 1) * 32], 4 + p * 36, 4 + k * 36)
                k += 1
    stk = stk[:4 + k * 36]
    Image.fromarray(stk).resize((stk.shape[1] * 4, stk.shape[0] * 4), Image.NEAREST).convert('RGB').save(
        os.path.join(out, 'items_ammo_stacks_4x.png'))
    # grounds: a patch of each family on plain earth, phase 0 and a later phase, 1x and 4x
    Yp, Xp = L.grid(32, 32)
    plain = np.zeros((32, 32, 4), np.uint8)
    plain[..., :3] = (L.ramp(L.FBM(5, 4, 32, 3)(Xp, Yp), ['#4a4026', '#5a4e30', '#665a38']) * 255).astype(np.uint8)
    plain[..., 3] = 255
    scenes = []
    for fam in TG.FAMILIES:
        a = atlases['grounds_%s' % fam['key']]
        n = fam['phases']
        art = {}
        for i, th in enumerate(['ground'] + list(TG.PIECES)):
            art[th] = [{(p % 4, p // 4): a[p * 32:(p + 1) * 32, (i * n + ph) * 32:(i * n + ph + 1) * 32]
                        for p in range(16)} for ph in range(n)]
        m = TG.blob(12, 10, 3 + fam['seed'], 0.55)
        scenes.append(np.concatenate([TG.scene(art, plain, m, 0), TG.scene(art, plain, m, n // 2)], 1))
    sc = np.concatenate(scenes, 0)
    Image.fromarray(sc).convert('RGB').save(os.path.join(out, 'grounds_1x.png'))
    Image.fromarray(sc).resize((sc.shape[1] * 4, sc.shape[0] * 4), Image.NEAREST).convert('RGB').save(
        os.path.join(out, 'grounds_4x.png'))
    # every ground thing, all patterns, phase 0 (the atlas itself is the contact sheet)
    for fam in TG.FAMILIES:
        a = atlases['grounds_%s' % fam['key']]
        Image.fromarray(a).convert('RGB').save(os.path.join(out, 'grounds_atlas_%s.png' % fam['key']))
    # auras and wings on a player look, four directions, three phases, 4x
    look = None
    if dat and spr:
        from datspr import Dat, Spr, render_thing
        from import_outfits import parse_body
        D, S = Dat(dat), Spr(spr)
        looks = []
        for lid in (128, 2073):
            t = D.outfit(lid)
            g = parse_body(D, t)[0]
            disp = t.flags.get('displacement', (0, 0))
            looks.append((lid, g, disp))
    cells = []
    for key, (role, fn) in TC.KINDS.items():
        a = atlases[key]
        for lk in (looks if dat and spr else [None]):
            for t in (0, 3, 6):
                row = []
                for di, dn in enumerate(TC.DIRS):
                    can = np.zeros((160, 160, 4), np.uint8)
                    can[..., :3] = (62, 78, 46); can[..., 3] = 255
                    for yy in range(5):
                        for xx in range(5):
                            if (xx + yy) % 2:
                                can[yy * 32:(yy + 1) * 32, xx * 32:(xx + 1) * 32, :3] = (56, 72, 42)
                    can[64:96, 64, :3] = can[64:96, 95, :3] = can[64, 64:96, :3] = can[95, 64:96, :3] = (150, 70, 60)
                    ox, oy = 64, 64
                    body = None
                    if lk is not None:
                        lid, g, disp = lk
                        body = np.asarray(render_thing(g, S, direction=dn))
                        bx, by = ox - disp[0] - (g.w - 1) * 32, oy - disp[1] - (g.h - 1) * 32
                    if role == 'aura':
                        back = a[t * 96:(t + 1) * 96, di * 96:(di + 1) * 96]
                        front = a[t * 96:(t + 1) * 96, (4 + di) * 96:(5 + di) * 96]
                        ax, ay = ox - TC.AURA_DISP[0] - 32, oy - TC.AURA_DISP[1] - 32
                        paste(can, back, ax, ay)
                        if body is not None:
                            paste(can, body, bx, by)
                        paste(can, front, ax, ay)
                    else:
                        w = a[t * 96:(t + 1) * 96, di * 96:(di + 1) * 96]
                        wx, wy = ox - 64 + 6, oy - 64 + 6
                        if dn in ('south', 'east'):
                            paste(can, w, wx, wy)
                            if body is not None:
                                paste(can, body, bx, by)
                        else:
                            if body is not None:
                                paste(can, body, bx, by)
                            paste(can, w, wx, wy)
                    row.append(can)
                cells.append(np.concatenate(row, 1))
    im = np.concatenate(cells, 0)
    Image.fromarray(im).convert('RGB').save(os.path.join(out, 'auras_wings_1x.png'))
    Image.fromarray(im).resize((im.shape[1] * 4, im.shape[0] * 4), Image.NEAREST).convert('RGB').save(
        os.path.join(out, 'auras_wings_4x.png'))
    if dat and spr:
        # read back from the pair: every new item (pattern 0, phase 0) and every new outfit (idle, four directions)
        first = D.counts[0] - sum(1 for r in rows if r['cat'] == 'item') + 1
        items = [D.items[i - 100] for i in range(first, D.counts[0] + 1)]
        cols = 24
        sh = np.zeros((((len(items) + cols - 1) // cols) * 34 + 2, cols * 34 + 2, 4), np.uint8); sh[...] = (58, 52, 46, 255)
        for k, t in enumerate(items):
            paste(sh, np.asarray(render_thing(t, S)), 2 + (k % cols) * 34, 2 + (k // cols) * 34)
        Image.fromarray(sh).resize((sh.shape[1] * 2, sh.shape[0] * 2), Image.NEAREST).convert('RGB').save(
            os.path.join(out, 'pair_items_2x.png'))
        new_o = [o for o in range(D.counts[1], 0, -1) if o >= 2185]
        new_o.sort()
        sh = np.zeros((len(new_o) * 98 + 2, 4 * 98 + 2, 4), np.uint8); sh[...] = (62, 78, 46, 255)
        for j, lid in enumerate(new_o):
            g = parse_body(D, D.outfit(lid))[0]
            for di, dn in enumerate(TC.DIRS):
                for layer in range(g.layers):
                    im2 = np.asarray(render_thing(g, S, direction=dn, layers='all' if g.layers > 1 else 'base'))
                paste(sh, im2, 2 + di * 98 + 96 - im2.shape[1], 2 + j * 98 + 96 - im2.shape[0])
        Image.fromarray(sh).resize((sh.shape[1] * 3, sh.shape[0] * 3), Image.NEAREST).convert('RGB').save(
            os.path.join(out, 'pair_outfits_3x.png'))
        print('pair read back: %d items from %d, outfits %s' % (len(items), first, new_o))
    print('previews in', out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build'); b.add_argument('--check', action='store_true')
    r = sub.add_parser('recolour'); r.add_argument('--dat', required=True); r.add_argument('--spr', required=True)
    r.add_argument('--check', action='store_true')
    p = sub.add_parser('preview'); p.add_argument('--out', required=True); p.add_argument('--dat'); p.add_argument('--spr')
    a = ap.parse_args()
    if a.cmd == 'build':
        cmd_build(a.check)
    elif a.cmd == 'recolour':
        cmd_recolour(a.dat, a.spr, a.check)
    else:
        cmd_preview(a.out, a.dat, a.spr)


if __name__ == '__main__':
    main()
