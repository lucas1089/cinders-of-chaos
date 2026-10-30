#!/usr/bin/env python3
"""Seven creature looks from the free AI Sprite Studio sample pack (owner request 2026-10-30), ready for import_art_things.py.

Source and licence: docs/CREDITS.md "AI Sprite Studio" (AI-generated free sample pack, https://aispritestudio.com/terms/;
personal and commercial use allowed, the art must not be claimed as hand-drawn). The pack has eight full sheets; the hammer
warrior is left out on purpose (the owner: it looks like a famous comic character). LOOKS pins the seven PNGs by SHA-256
(the pack's manifest.json). The sheets are not in git.

Sheet layout of the pack: 4 direction columns, 3 pose rows (idle, walk 1, walk 2). The column order was checked by eye on
the crystal tortoise (head up, right, down, left): north, east, south, west, the order of our outfits, so the columns are
taken as they are. Six sheets are 256 x 192 (64 px cells = 2 x 2 tiles); the sea naga is a legacy 512 x 384 sheet with
128 px cells whose every 2 x 2 block is one colour (it was drawn at 64 px and doubled), so taking every second pixel gives
the 64 px art back with no loss (nearest neighbour; the check below refuses a sheet that is not an exact doubling).

    python3 -I gen_aiss_art.py build --src DIR           # DIR/<file> holds the seven PNGs of LOOKS
    python3 -I gen_aiss_art.py build --check             # CI: the committed sheets, things file, picks and sources match
    python3 -I gen_aiss_art.py build --src DIR --check   # rebuild from the pack, compare pixel for pixel

How a look is made: the cells are used as drawn (every frame already stands in its cell: no shifting, no scaling). Two
clean-ups bring the AI art to docs/SPRITE_STYLE.md (the pack's sheets hold 5,000-8,500 colours each, the style wants at most
68 per 64 px cell, `style_check.py check FILE --palette FILE --cell 64`): the colours of a sheet are reduced to COLOURS by a
k-means in CIE Lab (weighted by pixel count, farthest-point start, no dithering, so no new noise; the picture is the same to
the eye), and a one-pixel hole inside the body (a transparent pixel with four opaque neighbours) takes the colour most of
its neighbours share. Alpha stays 0 / 255. Rows of the outfit sheet: phase 0 = the idle pose (frame group 0, one phase); the walk (frame group 1) has four
phases, idle, walk 1, idle, walk 2 (the order the engine loops), 150 ms each. patterns = 4 (north, east, south, west).

Outputs (committed):
  art_import/aiss/<key>.png          one sheet per look in import_art_things.py's outfit layout (layers=1: one row per
                                     phase, idle first; one column per direction)
  art_import/aiss.csv                the things file: outfits 3364.. (after pair 56's 3363), in LOOKS order
  art_import/aiss_sources.csv        where the art comes from (check_credits.py)
  monster_looks/aiss_picks.csv       the picks.csv rows of the looks (appended to picks.csv when the pair is on windows-assets)
Append to pair 56 (output pair 57):
    python3 -I import_art_things.py --ours-dat P56/Tibia.dat --ours-spr P56/Tibia.spr --out-dir P57 \
        --things art_import/aiss.csv --first-item 44446 --first-outfit 3364 --expect-items 44445
Deterministic: numpy and Pillow only.
"""
import argparse
import csv
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
OUT_DIR = os.path.join(ART, 'aiss')
THINGS = os.path.join(ART, 'aiss.csv')
SOURCES_CSV = os.path.join(ART, 'aiss_sources.csv')
PICKS = os.path.join(HERE, 'monster_looks', 'aiss_picks.csv')

FIRST_OUTFIT = 3364         # after pair 56's 3363 outfits
CELL = 64                   # 2 x 2 tiles
COLS = 4                    # north, east, south, west
POSES = 3                   # idle, walk 1, walk 2
WALK = ('idle', 'walk1', 'idle', 'walk2')   # walk phases, as indexes into POSE_ROW
COLOURS = 48                # colours of a sheet after the reduction (the style's limit is 68 a cell)
KMEANS_ITERS = 40
POSE_ROW = {'idle': 0, 'walk1': 1, 'walk2': 2}
MS = 150
DIRS = ('north', 'east', 'south', 'west')

# the looks in look-id order (FIRST_OUTFIT + index):
# key, the pack's file, SHA-256 of the file, its cell px, look name, family, monster (exact <monster name>), description
LOOKS = [
    ('gloamgeode_shellback', 'crystal-tortoise-sheet.png',
     '33107a71618551c048d77a3c2ff49dc5304c903db7660a6a8508d4643aa5148e', 64, 'Crystal tortoise', 'hunt',
     'Gloamgeode Shellback', 'huge blue-shelled tortoise with a violet crystal cluster on its back'),
    ('wickstaff_hexmage', 'purple-mage-sheet.png',
     'a424adfdf9d7f08fc4cb33b3ded6d516f0764ec06c95ed876e2bf5ddae38a7a5', 64, 'Purple mage', 'hunt',
     'Wickstaff Hexmage', 'old wizard in a wine-red pointed hat and robe with a flame-tipped wooden staff'),
    ('bogtusk_cleaver', 'orc-warrior-sheet.png',
     'bb2469d19fefe67c1f7f735a6fc410cc4e33ec9b1d8f5991b976271103e58302', 64, 'Orc warrior', 'hunt',
     'Bogtusk Cleaver', 'green-skinned brute in a brown leather vest with a double-bladed axe'),
    ('redmane_anvilbreaker', 'armored-berserker-sheet.png',
     'f5ae89e99eed8de802594b8a0cbc07fbc9ec9f413f96686a8f2aaae56efea413', 64, 'Armored berserker', 'hunt',
     'Redmane Anvilbreaker', 'red-haired bearded berserker in black plate with two glowing forge hammers'),
    ('marshlight_hollowseer', 'teal-mage-sheet.png',
     '20cdcc2ce259277d01c863164d9b86ce4a690178440f45517b2ceb119d610d5f', 64, 'Teal mage', 'hunt',
     'Marshlight Hollowseer', 'hooded teal-cloaked seer with empty shadow for a face, holding two glowing lanterns'),
    ('gravecrown_oathbreaker', 'crowned-knight-sheet.png',
     '5f10b462885a7fddc307bc1db0fe5313e580bd8e8abc2abdbdf12b99b9ab72f4', 64, 'Crowned knight', 'hunt',
     'Gravecrown Oathbreaker', 'skull-pauldroned knight in a small gold crown, torn red cape, blue soul glow, great sword'),
    ('coralcrown_brinecaller', 'sea-naga-sheet.png',
     '760c9f8edfea3d00614008a37e714e630f37645ec642e7825d20f1321ba4bb63', 128, 'Sea naga', 'hunt',
     'Coralcrown Brinecaller', 'teal serpent-tailed sea siren with a pink coral crown and a coral trident'),
]
PACK = 'AI Sprite Studio'
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
PICK_FIELDS = ['key', 'look', 'lib', 'lib_id', 'recolour', 'family', 'rank', 'monsters', 'description', 'edit']
SOURCE_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']


def load(src, fname, sha, cell):
    """the pack's sheet as a 192 x 256 RGBA array of 64 px cells"""
    p = os.path.join(src, fname)
    data = open(p, 'rb').read()
    got = hashlib.sha256(data).hexdigest()
    if got != sha:
        sys.exit('%s: sha256 %s, LOOKS pins %s' % (p, got, sha))
    a = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))
    want = (POSES * cell, COLS * cell, 4)
    if a.shape != want:
        sys.exit('%s: shape %s, the pack says %s' % (p, a.shape, want))
    if cell != CELL:
        k = cell // CELL
        blocks = a.reshape(a.shape[0] // k, k, a.shape[1] // k, k, 4)
        if not (blocks == blocks[:, :1, :, :1, :]).all():
            sys.exit('%s: not an exact %dx doubling, a nearest-neighbour shrink would lose pixels' % (p, k))
        a = np.ascontiguousarray(a[::k, ::k])
    a = a.copy()
    a[a[..., 3] == 0] = 0      # colour under alpha 0 zeroed
    return reduce_colours(fill_holes(a))


def kmeans_palette(rgb, k):
    """-> (palette k x 3 uint8, index of every row of the unique colours `rgb` count-weighted): k-means in CIE Lab"""
    import style_check as sc
    u, inv, cnt = np.unique(rgb, axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(-1)
    if len(u) <= k:
        return u, np.arange(len(u)), inv
    lab = sc.to_lab(u)
    w = cnt.astype(np.float64)
    idx = [int(np.argmax(w))]
    d = ((lab - lab[idx[0]]) ** 2).sum(1)
    for _ in range(k - 1):
        i = int(np.argmax(d * np.sqrt(w)))
        idx.append(i)
        d = np.minimum(d, ((lab - lab[i]) ** 2).sum(1))
    c = lab[idx].copy()
    for _ in range(KMEANS_ITERS):
        asg = ((lab[:, None, :] - c[None]) ** 2).sum(2).argmin(1)
        for j in range(k):
            m = asg == j
            if m.any():
                c[j] = (lab[m] * w[m, None]).sum(0) / w[m].sum()
    asg = ((lab[:, None, :] - c[None]) ** 2).sum(2).argmin(1)
    pal = np.zeros((k, 3))
    for j in range(k):
        m = asg == j
        if m.any():
            pal[j] = np.rint((u[m] * cnt[m, None]).sum(0) / cnt[m].sum())
    return np.clip(pal, 0, 255).astype(np.uint8), asg, inv


def reduce_colours(a):
    out = a.copy()
    vis = out[..., 3] > 0
    pal, asg, inv = kmeans_palette(out[vis][:, :3], COLOURS)
    out[vis, :3] = pal[asg[inv]]
    return out


def fill_holes(a):
    """a transparent pixel whose four neighbours are all opaque takes the colour most of them share (ties: up, left, right,
    down)"""
    out = a.copy()
    al = a[..., 3] > 0
    h, w = al.shape
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if al[y, x] or not (al[y - 1, x] and al[y + 1, x] and al[y, x - 1] and al[y, x + 1]):
                continue
            nb = [tuple(a[y - 1, x, :3]), tuple(a[y, x - 1, :3]), tuple(a[y, x + 1, :3]), tuple(a[y + 1, x, :3])]
            best = max(nb, key=lambda c: (nb.count(c), -nb.index(c)))
            out[y, x] = list(best) + [255]
    return out


def build_sheet(a):
    """rows idle + the four walk phases; columns north, east, south, west"""
    rows = [POSE_ROW['idle']] + [POSE_ROW[p] for p in WALK]
    return np.concatenate([a[r * CELL:(r + 1) * CELL] for r in rows], axis=0)


def build_sheets(src):
    return {key: build_sheet(load(src, fname, sha, cell)) for key, fname, sha, cell, *_r in LOOKS}


def things_rows():
    durs = '/'.join(['%d' % MS] * len(WALK))
    return [[key, 'outfit', 'creature', monster, 'aiss/' + key, 0, 0, 2, 2, COLS, '1+%d' % len(WALK), '', 'new', '',
             'layers=1|gtypes=0+1|exact=%d+%d|durs1=%s|anim1=0:0:0' % (CELL, CELL, durs)]
            for key, _f, _s, _c, _label, _fam, monster, _d in LOOKS]


def picks_rows():
    out = []
    for i, (key, fname, _sha, _c, label, family, monster, desc) in enumerate(LOOKS):
        out.append([key, FIRST_OUTFIT + i, 'aiss', fname, '', family, 'hunt', monster, '%s: %s' % (monster, desc),
                    'pack sheet, 64 px cells' + (', every second pixel of 128 px cells' if _c == 128 else '')])
    return out


def sources_rows():
    out = []
    for key, fname, sha, c, label, *_r in LOOKS:
        out.append([key, 'outfit', PACK,
                    '%s (%s, sha256 %s): 4 directions x 3 poses of %d px cells%s; colours reduced to %d, holes filled' % (
                        fname, label, sha[:12], c, ', nearest neighbour to 64 px' if c == 128 else '', COLOURS),
                    'free sample pack, personal and commercial use; AI-generated; docs/CREDITS.md'])
    return out


def csv_bytes(header, rows):
    s = io.StringIO()
    w = csv.writer(s, lineterminator='\n')
    w.writerow(header)
    w.writerows(rows)
    return s.getvalue().encode()


def png_bytes(a):
    b = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(b, format='PNG', optimize=False, compress_level=9)
    return b.getvalue()


def check_rules(sheets):
    bad = []
    for key, *_r in LOOKS:
        sheet = sheets.get(key)
        if sheet is None:
            bad.append(key + ' missing')
            continue
        want = (CELL * (1 + len(WALK)), CELL * COLS)
        if sheet.shape[:2] != want:
            bad.append('%s: %s, the spec gives %s' % (key, sheet.shape[:2], want))
            continue
        al = sheet[..., 3]
        if ((al > 0) & (al < 255)).any():
            bad.append(key + ': semi-transparent pixels (the pack has alpha 0 / 255)')
        if len(np.unique(sheet[al > 0][:, :3], axis=0)) > COLOURS:
            bad.append(key + ': more than %d colours' % COLOURS)
        if (sheet[al == 0][:, :3] != 0).any():
            bad.append(key + ': colour under alpha 0')
        for r in range(1 + len(WALK)):
            for d in range(COLS):
                cell = sheet[r * CELL:(r + 1) * CELL, d * CELL:(d + 1) * CELL]
                if not cell[..., 3].any():
                    bad.append('%s: empty frame (row %d, %s)' % (key, r, DIRS[d]))
                elif not cell[CELL - 32:, :, 3].any():
                    bad.append('%s: nothing on the bottom tile row (row %d, %s)' % (key, r, DIRS[d]))
                elif r == 0 and not cell[CELL - 32:, CELL - 32:, 3].any():
                    bad.append('%s: nothing on the creature tile (idle, %s)' % (key, DIRS[d]))
    return bad


def outputs(sheets):
    out = {os.path.join(OUT_DIR, k + '.png'): png_bytes(v) for k, v in sheets.items()}
    out[THINGS] = csv_bytes(FIELDS, things_rows())
    out[SOURCES_CSV] = csv_bytes(SOURCE_FIELDS, sources_rows())
    out[PICKS] = csv_bytes(PICK_FIELDS, picks_rows())
    return out


def read_sheets():
    out = {}
    for key, *_r in LOOKS:
        p = os.path.join(OUT_DIR, key + '.png')
        if os.path.exists(p):
            out[key] = np.asarray(Image.open(p).convert('RGBA'))
    return out


def cmd_build(a):
    if a.src:
        sheets = build_sheets(a.src)
    elif a.check:
        sheets = read_sheets()
    else:
        sys.exit('build needs --src (the pack folder); without it only --check runs')
    bad = check_rules(sheets)
    if bad:
        sys.exit('\n'.join(bad))
    for path, data in sorted(outputs(sheets).items()):
        rel = os.path.relpath(path, REPO)
        if a.check:
            if not os.path.exists(path):
                bad.append(rel + ' missing')
            elif path.endswith('.png'):
                have = np.asarray(Image.open(path).convert('RGBA'))
                want = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))
                if have.shape != want.shape or not (have == want).all():
                    bad.append(rel + ' differs')
            elif open(path, 'rb').read() != data:
                bad.append(rel + ' differs')
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'wb').write(data)
            print('wrote', rel)
    if bad:
        sys.exit('\n'.join(bad) + '\nrun gen_aiss_art.py build --src DIR')
    if a.check:
        print('AI Sprite Studio art: %d looks, %d phases each, match the spec' % (len(LOOKS), 1 + len(WALK)))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    cmd_build(p.parse_args(argv))


if __name__ == '__main__':
    main()
