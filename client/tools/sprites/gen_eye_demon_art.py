#!/usr/bin/env python3
"""The Verdant Eye Demon boss look (owner request 2026-10-28): one 4x4 creature look from our own AutoSprite render.

Source and licence: the owner's AutoSprite character "Verdant Eye Demon" (made with the owner's paid AutoSprite account,
docs/CREDITS.md "Tools"), animated with AutoSprite's eight-direction walk (one render, 25 frames of 256 px per
direction, 5 x 5 cells per PNG). SOURCES pins the four PNGs we use (up, right, down, left) by md5; the diagonal ones
are not used (our looks have four directions). The raw zip is not in git.

    python3 -I gen_eye_demon_art.py build --src DIR     # DIR holds up.png, right.png, down.png, left.png of the zip
    python3 -I gen_eye_demon_art.py build --check       # CI: the committed sheet, things file, picks and sources match
    python3 -I gen_eye_demon_art.py build --src DIR --check   # rebuild from the render, compare pixel for pixel

How a frame is made: the 256 px cell is halved to 128 px (4x4 tiles) by the mean of each 2 x 2 block in premultiplied
alpha (numpy only, so every Pillow version gives the same pixels); alpha under ALPHA_MIN is cleared and colour under
alpha 0 zeroed. Each direction is then moved as a whole (one shift for all its frames, so the walk does not jitter):
its lowest row over all frames on FOOT_Y and the centre of its feet in frame 0 on FOOT_X (the four 4x4 lion looks of
pair 26 stand there: feet about x 96, lowest row 125-127), kept inside the cell.
Phases: idle = walk frame 0, then WALK frames picked evenly from the 25 (the render's loop), 100 ms each.

Outputs (committed):
  art_import/eye_demon/eye_demon.png   the look sheet in import_art_things.py's outfit layout (layers=1: one row per
                                       phase, idle first; one column per direction north, east, south, west)
  art_import/eye_demon.csv             the things file: outfit 3361 (after pair 53's 3360)
  art_import/eye_demon_sources.csv     where the art comes from (check_credits.py)
  monster_looks/eye_demon_picks.csv    the picks.csv row of the look (appended to picks.csv with pair 54)
Append to pair 53 (output pair 54):
    python3 -I import_art_things.py --ours-dat P53/Tibia.dat --ours-spr P53/Tibia.spr --out-dir P54 \
        --things art_import/eye_demon.csv --first-item 44396 --first-outfit 3361 --expect-items 44395
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
KEY = 'eye_demon'
SHEET = os.path.join(ART, KEY, KEY + '.png')
THINGS = os.path.join(ART, KEY + '.csv')
SOURCES_CSV = os.path.join(ART, KEY + '_sources.csv')
PICKS = os.path.join(HERE, 'monster_looks', KEY + '_picks.csv')

FIRST_OUTFIT = 3361         # after pair 53's 3360 outfits
NAME = 'Verdant Eye Demon'
MONSTER = 'Vharzul the Verdant Eye'
CELL_IN, CELL = 256, 128
GRID = 5                    # 5 x 5 cells per source PNG
FRAMES = 25
WALK = 8
MS = 100
ALPHA_MIN = 12
FOOT_X, FOOT_Y = 96, 125
DIRS = ('north', 'east', 'south', 'west')
FILES = ('up.png', 'right.png', 'down.png', 'left.png')   # the render's names, in DIRS order
SOURCES = {
    'up.png': '8e9ae2853610c7ee4741910e3652f76e',
    'right.png': 'afd3ec641ee7dfeab404a53e8290f492',
    'down.png': 'aa39ff22aa86fa4793fa716bff2626df',
    'left.png': '0c82bf8a09d725baea2e990f8ddaf005',
}
CHARACTER_ID = 'cmvrcd1w20014jc1opt6ib6ox'
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
PICK_FIELDS = ['key', 'look', 'lib', 'lib_id', 'recolour', 'family', 'rank', 'monsters', 'description', 'edit']
SOURCE_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']


def walk_frames():
    """the WALK frame indices picked evenly from the FRAMES of the loop"""
    return [i * FRAMES // WALK for i in range(WALK)]


def load(src, name):
    p = os.path.join(src, name)
    data = open(p, 'rb').read()
    want = SOURCES[name]
    got = hashlib.md5(data).hexdigest()
    if want and got != want:
        sys.exit('%s: md5 %s, SOURCES pins %s' % (p, got, want))
    a = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))
    assert a.shape == (CELL_IN * GRID, CELL_IN * GRID, 4), (name, a.shape)
    return a


def halve(cell):
    """2 x 2 block mean in premultiplied alpha, rounded; alpha under ALPHA_MIN cleared, colour under alpha 0 zeroed"""
    f = cell.astype(np.float64)
    a = f[..., 3:4] / 255.0
    pm = np.concatenate([f[..., :3] * a, a], axis=2)
    h, w = cell.shape[:2]
    m = pm.reshape(h // 2, 2, w // 2, 2, 4).mean(axis=(1, 3))
    al = m[..., 3]
    out = np.zeros((h // 2, w // 2, 4), np.uint8)
    nz = al > 0
    rgb = np.zeros((h // 2, w // 2, 3))
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


def feet_x(cell, rows=8):
    ys, xs = np.nonzero(cell[..., 3] > 0)
    low = ys >= ys.max() - rows + 1
    return float(xs[low].mean())


def place(frames):
    """one shift for all frames of a direction: lowest row on FOOT_Y, frame 0's feet on FOOT_X, kept inside"""
    on = [np.nonzero(f[..., 3] > 0) for f in frames]
    x0 = min(int(x.min()) for _y, x in on)
    x1 = max(int(x.max()) for _y, x in on)
    y0 = min(int(y.min()) for y, _x in on)
    y1 = max(int(y.max()) for y, _x in on)
    dy = FOOT_Y - y1
    dx = int(round(FOOT_X - feet_x(frames[0])))
    dx = max(-x0, min(dx, CELL - 1 - x1))
    dy = max(-y0, min(dy, CELL - 1 - y1))
    return [shift(f, dx, dy) for f in frames], (dx, dy)


def build_sheet(src):
    """-> (sheet, shifts): rows idle + WALK phases, columns DIRS"""
    cols, shifts = [], []
    for name in FILES:
        a = load(src, name)
        cells = [halve(a[(i // GRID) * CELL_IN:(i // GRID + 1) * CELL_IN, (i % GRID) * CELL_IN:(i % GRID + 1) * CELL_IN])
                 for i in range(FRAMES)]
        placed, sh = place(cells)
        cols.append([placed[0]] + [placed[i] for i in walk_frames()])
        shifts.append(sh)
    rows = [np.concatenate([cols[d][r] for d in range(4)], axis=1) for r in range(1 + WALK)]
    return np.concatenate(rows, axis=0), shifts


def things_rows():
    t = CELL // 32
    durs = '/'.join(['%d' % MS] * WALK)
    return [[KEY, 'outfit', 'creature', NAME, KEY + '/' + KEY, 0, 0, t, t, 4, '1+%d' % WALK, '', 'new', '',
             'layers=1|gtypes=0+1|exact=%d+%d|durs1=%s|anim1=0:0:0' % (CELL, CELL, durs)]]


def picks_rows():
    return [[KEY, FIRST_OUTFIT, 'autosprite', CHARACTER_ID, '', 'lairboss', 'boss', MONSTER,
             '%s: horned red and black demon with pale green eyes, claws and spiked shoulders, 4x4' % NAME,
             'autosprite walk, 256 px halved']]


def sources_rows():
    return [[KEY, 'outfit', 'AutoSprite',
             'character %s, eight-direction walk (one render, 25 frames of 256 px); up/right/down/left halved to 128 px'
             % CHARACTER_ID, 'made with the owner\'s AutoSprite account; docs/CREDITS.md']]


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


def check_rules(sheet):
    bad = []
    want = (CELL * (1 + WALK), CELL * 4)
    if sheet.shape[:2] != want:
        return ['%s: %s, the spec gives %s' % (KEY, sheet.shape[:2], want)]
    al = sheet[..., 3]
    if ((al > 0) & (al < ALPHA_MIN)).any():
        bad.append(KEY + ': alpha under %d left' % ALPHA_MIN)
    if (sheet[al == 0][:, :3] != 0).any():
        bad.append(KEY + ': colour under alpha 0')
    for r in range(1 + WALK):
        for d in range(4):
            c = sheet[r * CELL:(r + 1) * CELL, d * CELL:(d + 1) * CELL]
            if not c[..., 3].any():
                bad.append('%s: empty frame (row %d, %s)' % (KEY, r, DIRS[d]))
                continue
            # the creature's own tile (bottom right 32 x 32) must hold some of the body
            if not c[CELL - 32:, CELL - 32:, 3].any():
                bad.append('%s: nothing on the creature tile (row %d, %s)' % (KEY, r, DIRS[d]))
    return bad


def outputs(sheet):
    return {
        SHEET: png_bytes(sheet),
        THINGS: csv_bytes(FIELDS, things_rows()),
        SOURCES_CSV: csv_bytes(SOURCE_FIELDS, sources_rows()),
        PICKS: csv_bytes(PICK_FIELDS, picks_rows()),
    }


def cmd_build(a):
    if a.src:
        sheet, shifts = build_sheet(a.src)
        for d, s in zip(DIRS, shifts):
            print('%s: shift %+d, %+d' % (d, s[0], s[1]))
    elif a.check:
        if not os.path.exists(SHEET):
            sys.exit(os.path.relpath(SHEET, REPO) + ' missing')
        sheet = np.asarray(Image.open(SHEET).convert('RGBA'))
    else:
        sys.exit('build needs --src (the render PNGs); without it only --check runs')
    bad = check_rules(sheet)
    if bad:
        sys.exit('\n'.join(bad))
    for path, data in sorted(outputs(sheet).items()):
        rel = os.path.relpath(path, REPO)
        if a.check:
            if not os.path.exists(path):
                bad.append(rel + ' missing')
            elif path.endswith('.png'):
                have = np.asarray(Image.open(path).convert('RGBA'))
                if have.shape != sheet.shape or not (have == sheet).all():
                    bad.append(rel + ' differs')
            elif open(path, 'rb').read() != data:
                bad.append(rel + ' differs')
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'wb').write(data)
            print('wrote', rel)
    if bad:
        sys.exit('\n'.join(bad) + '\nrun gen_eye_demon_art.py build --src DIR')
    if a.check:
        print('eye demon art: 1 look, %d phases, matches the spec' % (1 + WALK))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    a = p.parse_args(argv)
    cmd_build(a)


if __name__ == '__main__':
    main()
