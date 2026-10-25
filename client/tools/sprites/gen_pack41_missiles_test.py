#!/usr/bin/env python3
"""Tests of gen_pack41_missiles.py on synthetic images (no pixel of the purchased pack): the sheet rows E SE S SW W NW N
NE land in the client's 3 x 3 missile cells (the engine's Missile::draw: NW 0,0; N 1,0; NE 2,0; W 0,1; E 2,1; SW 0,2;
S 1,2; SE 2,2; the centre cell is the fallback), the pivot lands on (13, 13) of the tile, art past the bottom-right tile
is moved as a whole, the appended ones keep a fixed send offset, and the committed tables agree.

    python3 -I gen_pack41_missiles_test.py
"""
import json
import os
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack27_fx as G  # noqa: E402
import gen_pack41_missiles as M  # noqa: E402

VEC = {'e': (1, 0), 'se': (1, 1), 's': (0, 1), 'sw': (-1, 1), 'w': (-1, 0), 'nw': (-1, -1), 'n': (0, -1), 'ne': (1, -1)}
# the client's cell of each direction (Missile::draw in the OTClient family): (x pattern, y pattern)
ENGINE_CELL = {'nw': (0, 0), 'n': (1, 0), 'ne': (2, 0), 'w': (0, 1), 'e': (2, 1), 'sw': (0, 2), 's': (1, 2), 'se': (2, 2)}
fails = 0


def ok(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL', msg)


def make_pack(root, eid, var, reach, frames=8):
    """a pack folder with one synthetic projectile: in row r a 4 x 4 block `reach` pixels from the pivot (32, 32) in
    direction r, drawn in all frames; the first frame also holds a 1-pixel mark at the pivot's row end so frames differ"""
    d = os.path.join(root, 'sheets', '32px', 'projectiles', eid, var)
    os.makedirs(d)
    img = np.zeros((64 * 8, 64 * frames, 4), np.uint8)
    for r, name in enumerate(G.DIRS8):
        vx, vy = VEC[name]
        norm = (vx * vx + vy * vy) ** 0.5
        cx, cy = int(round(32 + reach * vx / norm)), int(round(32 + reach * vy / norm))
        for f in range(frames):
            img[r * 64 + cy - 2:r * 64 + cy + 2, f * 64 + cx - 2:f * 64 + cx + 2] = (200, 40 + 10 * f, 90, 255)
    Image.fromarray(img).save(os.path.join(d, f'{eid}_{var}_main.png'))
    meta = dict(id=eid, title=eid, category='projectiles', variant=var, loop=True, frames=frames,
                stages={'loop': {'frames': frames, 'loop': True}},
                directions=['E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE'], fps=12, tile_size=32, frame_width=64,
                frame_height=64, tiles=[2, 2], pivot=[32.0, 32.0], pivot_tiles=[1.0, 1.0], anchor_tile=[1, 1],
                projection='oblique', layers=['main'], sheets={'main': f'{eid}_{var}_main.png'},
                sheet_layout='rows_are_directions')
    json.dump(meta, open(os.path.join(d, f'{eid}_{var}.json'), 'w'))


def cell_centre(strip, w, h, n, x, y, f=0):
    """-> centroid (px) of the art of cell (x, y), frame f, inside its w x h tile canvas"""
    W, H = w * 32, h * 32
    c = strip[y * H:(y + 1) * H, (x * n + f) * W:(x * n + f + 1) * W, 3] > 0
    ys, xs = np.nonzero(c)
    return xs.mean() + 0.5, ys.mean() + 0.5


def test_cells():
    with tempfile.TemporaryDirectory() as root:
        make_pack(root, 'proj_t', 'steel', 9)
        for label, pick in (('stock id', ('replace', 4, 'rep41_m4', 'proj_t', 'steel', (2, 2, 0, 0))),
                            ('appended id', ('replace', 190, 'rep41_m190', 'proj_t', 'steel', (3, 3, 1, 1))),
                            ('new', ('new', None, 'proj_t_steel', 'proj_t', 'steel', None))):
            row, strip, src, notes = M.convert([root], pick)
            w, h, n, dx, dy = row['w'], row['h'], row['phases'], row['dx'], row['dy']
            ok(strip.shape == (3 * h * 32, 3 * w * 32 * n, 4), f'{label}: strip shape {strip.shape}')
            ok(n == 8 and row['ms'] == 83, f'{label}: 8 frames at 83 ms')
            if label == 'stock id':
                ok((dx, dy) == (0, 0), f'{label}: send offset 0, 0')
            if label == 'appended id':
                ok((dx, dy) == (1, 1), f'{label}: send offset kept')
            # the pivot of the cell: (left * 32 + 13, top * 32 + 13), left = w - 1 - dx
            px, py = (w - 1 - dx) * 32 + G.MISSILE_CENTRE[0], (h - 1 - dy) * 32 + G.MISSILE_CENTRE[1]
            for d, (x, y) in ENGINE_CELL.items():
                cx, cy = cell_centre(strip, w, h, n, x, y)
                vx, vy = VEC[d]
                nn = (vx * vx + vy * vy) ** 0.5
                ex, ey = 9 * vx / nn, 9 * vy / nn
                ok(abs(cx - px - ex) <= 1.0 and abs(cy - py - ey) <= 1.0,
                   f'{label}: {d} in cell {x},{y}: at {cx - px:+.1f},{cy - py:+.1f}, want {ex:+.1f},{ey:+.1f}')
            # the centre cell repeats the south row (the engine's fallback pattern)
            cx, cy = cell_centre(strip, w, h, n, 1, 1)
            ok(abs(cx - px) <= 1.0 and abs(cy - py - 9) <= 1.0, f'{label}: centre cell shows the south row')
            # a pixel-exact copy of the south cell
            W, H = w * 32, h * 32
            a = strip[1 * H:2 * H, 1 * n * W:2 * n * W]
            b = strip[2 * H:3 * H, 1 * n * W:2 * n * W]
            ok(np.array_equal(a, b), f'{label}: centre cell equals the south cell')
            ok(not any('moved' in x or 'cut' in x for x in notes), f'{label}: no shift or cut for small art: {notes}')
            # every frame holds art and frames differ (colour per frame)
            cols = {tuple(strip[:, (1 * n + f) * W:(1 * n + f + 1) * W][..., :3][strip[:, (1 * n + f) * W:(1 * n + f + 1) * W, 3] > 0][0]) for f in range(n)}
            ok(len(cols) == n, f'{label}: frames keep their own pixels')


def test_shift():
    """art that reaches past the bottom-right tile moves up and left as a whole; the stock id stays at 2 x 2"""
    with tempfile.TemporaryDirectory() as root:
        make_pack(root, 'proj_far', 'steel', 24)                  # blocks up to 24 + 2 px from the pivot
        row, strip, src, notes = M.convert([root], ('replace', 5, 'rep41_m5', 'proj_far', 'steel', (2, 2, 0, 0)))
        ok((row['w'], row['h']) == (2, 2) and (row['dx'], row['dy']) == (0, 0), f"far art: 2x2, offset 0,0: {row}")
        ok(any('moved' in x for x in notes), f'far art: the move is reported: {notes}')
        al = strip[:, :, 3] > 0
        W, H = row['w'] * 32, row['h'] * 32
        ok(all(al[y * H:(y + 1) * H, x * W:(x + 1) * W].any() for x in range(3 * row['phases']) for y in range(3)),
           'far art: every cell and frame has art')
        ok('cut' not in ' '.join(notes), f'far art: nothing cut: {notes}')


def test_clean_alpha():
    """alpha is 0 / 255 after the cut (no halving, no soft pixels)"""
    with tempfile.TemporaryDirectory() as root:
        make_pack(root, 'proj_a', 'steel', 6)
        sheet = os.path.join(root, 'sheets', '32px', 'projectiles', 'proj_a', 'steel', 'proj_a_steel_main.png')
        im = np.asarray(Image.open(sheet).convert('RGBA')).copy()
        im[10:14, 10:14] = (255, 255, 255, 90)                    # a soft pixel block: the dither keeps some, as 255
        Image.fromarray(im).save(sheet)
        row, strip, _, _ = M.convert([root], ('replace', 4, 'rep41_m4', 'proj_a', 'steel', (2, 2, 0, 0)))
        ok(set(np.unique(strip[:, :, 3])) <= {0, 255}, 'alpha is 0 / 255')


def test_tables():
    ok(M.check_without_art() == 0, 'the committed spec, sources and sums agree')
    t = M.targets()
    ids = [i for i, *_ in t]
    ok(ids == sorted(set(ids)), 'targets: ids sorted and unique')
    ok(all(1 <= i <= 250 for i in ids), 'targets: ids within pair 36')
    ok(M.FIRST_NEW + len(M.NEW) - 1 <= M.LAST_NEW < 254, 'new ids stay below 254 (255 free)')
    rows = M.read_csv(M.SPEC)
    ok([r['name'] for r in rows][-len(M.NEW):] == [n for _, _, n, _ in M.NEW], 'new picks last, in order')
    ok(all(r['replace'] == '' for r in rows[-len(M.NEW):]), 'new picks have no replace id')
    taken = M.existing_names()
    ok(all(n not in taken for _, _, n, _ in M.NEW), 'new names are free')


if __name__ == '__main__':
    test_cells()
    test_shift()
    test_clean_alpha()
    test_tables()
    if fails:
        print(f'{fails} failure(s)')
        sys.exit(1)
    print('gen_pack41_missiles_test: OK')
