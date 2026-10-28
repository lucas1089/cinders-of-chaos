#!/usr/bin/env python3
"""Creature looks from our own AutoSprite renders (owner requests 2026-10-28), ready for import_art_things.py.

Source and licence: characters made with the owner's paid AutoSprite account (docs/CREDITS.md "Tools"), each animated
with AutoSprite's eight-direction walk (one render, 25 frames of 256 px per direction, 5 x 5 cells per PNG). SOURCES
pins the four PNGs of each look we use (up, right, down, left) by md5; the diagonal ones are not used (our looks have
four directions). The renders are not in git.

    python3 -I gen_autosprite_art.py build --src DIR     # DIR/<key>/ holds up.png, right.png, down.png, left.png
    python3 -I gen_autosprite_art.py build --check       # CI: the committed sheets, things file, picks and sources match
    python3 -I gen_autosprite_art.py build --src DIR --check   # rebuild from the renders, compare pixel for pixel

How a frame is made: the 256 px cell is shrunk to the look's cell (128 px = 4x4 tiles, 64 px = 2x2) by the mean of
each square block in premultiplied alpha (numpy only, so every Pillow version gives the same pixels); alpha under
ALPHA_MIN is cleared and colour under alpha 0 zeroed. Each direction is then moved as a whole (one shift for all its
frames, so the walk does not jitter): its lowest row over all frames on the look's foot row and the centre of its feet
in frame 0 on its foot column, kept inside the cell. 4x4: feet x 96, lowest row 125 (where the 4x4 lions of pair 26
stand); 2x2: feet x 44, lowest row 62 (the creature's own tile is the bottom right 32 x 32; the 2x2 looks of pair 26
stand there, feet x 40-53).
Phases: idle = walk frame 0, then WALK frames picked evenly from the 25 (the render's loop), 100 ms each.

Outputs (committed):
  art_import/autosprite/<key>.png      one sheet per look in import_art_things.py's outfit layout (layers=1: one row
                                       per phase, idle first; one column per direction north, east, south, west)
  art_import/autosprite.csv            the things file: outfits 3361.. (after pair 53's 3360), in LOOKS order
  art_import/autosprite_sources.csv    where the art comes from (check_credits.py)
  monster_looks/autosprite_picks.csv   the picks.csv rows of the looks (appended to picks.csv with pair 54)
Append to pair 53 (output pair 54):
    python3 -I import_art_things.py --ours-dat P53/Tibia.dat --ours-spr P53/Tibia.spr --out-dir P54 \
        --things art_import/autosprite.csv --first-item 44396 --first-outfit 3361 --expect-items 44395
Deterministic: numpy and Pillow only (CI pins Pillow 12.3.0 / numpy 2.5.3).
"""
import argparse
import csv
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
OUT_DIR = os.path.join(ART, 'autosprite')
THINGS = os.path.join(ART, 'autosprite.csv')
SOURCES_CSV = os.path.join(ART, 'autosprite_sources.csv')
PICKS = os.path.join(HERE, 'monster_looks', 'autosprite_picks.csv')

FIRST_OUTFIT = 3361         # after pair 53's 3360 outfits
CELL_IN = 256
GRID = 5                    # 5 x 5 cells per source PNG
FRAMES = 25
WALK = 8
MS = 100
ALPHA_MIN = 12
FOOT = {128: (96, 125), 64: (44, 62)}   # cell px -> (feet x, lowest row)
DIRS = ('north', 'east', 'south', 'west')
FILES = ('up.png', 'right.png', 'down.png', 'left.png')   # the render's names, in DIRS order

# the looks in look-id order (FIRST_OUTFIT + index):
# key, AutoSprite character id, cell px, look name, family, monster (exact <monster name>), description,
# md5 of up / right / down / left
LOOKS = [
    ('eye_demon', 'cmvrcd1w20014jc1opt6ib6ox', 128, 'Verdant Eye Demon', 'lairboss', 'Vharzul the Verdant Eye',
     'horned red and black demon with pale green eyes, claws and spiked shoulders, 4x4',
     ('8e9ae2853610c7ee4741910e3652f76e', 'afd3ec641ee7dfeab404a53e8290f492', 'aa39ff22aa86fa4793fa716bff2626df',
      '0c82bf8a09d725baea2e990f8ddaf005')),
    ('ashbound_thrall', 'cmvre826d00ezz6z1fg72bkp8', 64, 'Ashbound Thrall', 'hunt', 'Ashbound Thrall',
     'hunched chained demonic thrall, charred hide cracked with ember veins, small horns',
     ('4e105e83487eb1318fae139b5b8764b3', '4d46fb98b76d591e99bee068df7f1c0f', '99c71f7af5d29d30c7d8dcffcc13b92a',
      '8789f0464ae9085087e0f3b66bdb84ad')),
    ('slagback_hound', 'cmvre8d91006k4v8d5v9j0xc9', 64, 'Slagback Hound', 'hunt', 'Slagback Hound',
     'black hellhound with glowing slag plates on its back and a smoking mane',
     ('2bf262f1b48e0021476d56eda14d20e1', '50b63c78cb9691733941e5fc1f40041f', 'fd56cf8779cbd0e65314730aa1406dc0',
      'bd7ee0920b392a259fb04c899bb8fd9d')),
]
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
PICK_FIELDS = ['key', 'look', 'lib', 'lib_id', 'recolour', 'family', 'rank', 'monsters', 'description', 'edit']
SOURCE_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']


def walk_frames():
    """the WALK frame indices picked evenly from the FRAMES of the loop"""
    return [i * FRAMES // WALK for i in range(WALK)]


def load(src, key, name, md5):
    p = os.path.join(src, key, name)
    data = open(p, 'rb').read()
    got = hashlib.md5(data).hexdigest()
    if got != md5:
        sys.exit('%s: md5 %s, LOOKS pins %s' % (p, got, md5))
    a = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))
    assert a.shape == (CELL_IN * GRID, CELL_IN * GRID, 4), (p, a.shape)
    return a


def shrink(cell, k):
    """k x k block mean in premultiplied alpha, rounded; alpha under ALPHA_MIN cleared, colour under alpha 0 zeroed"""
    f = cell.astype(np.float64)
    a = f[..., 3:4] / 255.0
    pm = np.concatenate([f[..., :3] * a, a], axis=2)
    h, w = cell.shape[:2]
    m = pm.reshape(h // k, k, w // k, k, 4).mean(axis=(1, 3))
    al = m[..., 3]
    out = np.zeros((h // k, w // k, 4), np.uint8)
    nz = al > 0
    rgb = np.zeros((h // k, w // k, 3))
    rgb[nz] = m[nz][:, :3] / al[nz][:, None]
    out[..., :3] = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(np.rint(al * 255), 0, 255).astype(np.uint8)
    out[out[..., 3] < ALPHA_MIN] = 0
    return out


def shift(cell, dx, dy):
    h, w = cell.shape[:2]
    out = np.zeros_like(cell)
    out[max(0, dy):h + min(0, dy), max(0, dx):w + min(0, dx)] = cell[max(0, -dy):h - max(0, dy),
                                                                     max(0, -dx):w - max(0, dx)]
    return out


def feet_x(cell, rows):
    ys, xs = np.nonzero(cell[..., 3] > 0)
    low = ys >= ys.max() - rows + 1
    return float(xs[low].mean())


def place(frames, c):
    """one shift for all frames of a direction: lowest row on the foot row, frame 0's feet on the foot column, kept
    inside the cell"""
    fx, fy = FOOT[c]
    on = [np.nonzero(f[..., 3] > 0) for f in frames]
    x0 = min(int(x.min()) for _y, x in on)
    x1 = max(int(x.max()) for _y, x in on)
    y0 = min(int(y.min()) for y, _x in on)
    y1 = max(int(y.max()) for y, _x in on)
    dy = fy - y1
    dx = int(round(fx - feet_x(frames[0], max(2, c // 16))))
    dx = max(-x0, min(dx, c - 1 - x1))
    dy = max(-y0, min(dy, c - 1 - y1))
    return [shift(f, dx, dy) for f in frames], (dx, dy)


def build_look(src, key, c, md5s):
    """-> (sheet, shifts): rows idle + WALK phases, columns DIRS"""
    k = CELL_IN // c
    cols, shifts = [], []
    for name, md5 in zip(FILES, md5s):
        a = load(src, key, name, md5)
        cells = [shrink(a[(i // GRID) * CELL_IN:(i // GRID + 1) * CELL_IN,
                          (i % GRID) * CELL_IN:(i % GRID + 1) * CELL_IN], k) for i in range(FRAMES)]
        placed, sh = place(cells, c)
        cols.append([placed[0]] + [placed[i] for i in walk_frames()])
        shifts.append(sh)
    rows = [np.concatenate([cols[d][r] for d in range(4)], axis=1) for r in range(1 + WALK)]
    return np.concatenate(rows, axis=0), shifts


def build_sheets(src):
    out = {}
    for key, _cid, c, *_r, md5s in LOOKS:
        out[key], shifts = build_look(src, key, c, md5s)
        print('%s: %s' % (key, ', '.join('%s %+d,%+d' % (d, s[0], s[1]) for d, s in zip(DIRS, shifts))))
    return out


def things_rows():
    rows = []
    durs = '/'.join(['%d' % MS] * WALK)
    for key, _cid, c, name, *_r in LOOKS:
        t = c // 32
        rows.append([key, 'outfit', 'creature', name, 'autosprite/' + key, 0, 0, t, t, 4, '1+%d' % WALK, '', 'new', '',
                     'layers=1|gtypes=0+1|exact=%d+%d|durs1=%s|anim1=0:0:0' % (c, c, durs)])
    return rows


def picks_rows():
    out = []
    for i, (key, cid, c, name, family, monster, desc, _m) in enumerate(LOOKS):
        out.append([key, FIRST_OUTFIT + i, 'autosprite', cid, '', family, 'boss' if family.endswith('boss') else 'hunt',
                    monster, '%s: %s' % (name, desc), 'autosprite walk, 256 px shrunk to %d' % c])
    return out


def sources_rows():
    out = []
    for key, cid, c, *_r in LOOKS:
        out.append([key, 'outfit', 'AutoSprite',
                    'character %s, eight-direction walk (one render, 25 frames of 256 px); up/right/down/left shrunk '
                    'to %d px' % (cid, c), 'made with the owner\'s AutoSprite account; docs/CREDITS.md'])
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
    for key, _cid, c, *_r in LOOKS:
        sheet = sheets.get(key)
        if sheet is None:
            bad.append(key + ' missing')
            continue
        want = (c * (1 + WALK), c * 4)
        if sheet.shape[:2] != want:
            bad.append('%s: %s, the spec gives %s' % (key, sheet.shape[:2], want))
            continue
        al = sheet[..., 3]
        if ((al > 0) & (al < ALPHA_MIN)).any():
            bad.append(key + ': alpha under %d left' % ALPHA_MIN)
        if (sheet[al == 0][:, :3] != 0).any():
            bad.append(key + ': colour under alpha 0')
        for r in range(1 + WALK):
            for d in range(4):
                cell = sheet[r * c:(r + 1) * c, d * c:(d + 1) * c]
                if not cell[..., 3].any():
                    bad.append('%s: empty frame (row %d, %s)' % (key, r, DIRS[d]))
                elif not cell[c - 32:, c - 32:, 3].any():
                    # the creature's own tile (bottom right 32 x 32) must hold some of the body
                    bad.append('%s: nothing on the creature tile (row %d, %s)' % (key, r, DIRS[d]))
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
        sys.exit('build needs --src (the render PNGs); without it only --check runs')
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
        sys.exit('\n'.join(bad) + '\nrun gen_autosprite_art.py build --src DIR')
    if a.check:
        print('autosprite art: %d looks, %d phases each, match the spec' % (len(LOOKS), 1 + WALK))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    cmd_build(p.parse_args(argv))


if __name__ == '__main__':
    main()
