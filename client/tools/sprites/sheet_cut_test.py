#!/usr/bin/env python3
"""Test of sheet_cut.py (O781): python3 -I client/tools/sprites/sheet_cut_test.py

On synthetic sheets drawn here (nothing is anyone's art): a 3 x 3 pack with gutters found by its gutters, a 2 x 2 pack
with touching cells by --grid and by the json next to it, an upscaled sheet on a flat backdrop brought back first, a
stray pixel that stops the gutter cut, the three anchors (item centred with its margin, bottom row, bottom right), a
piece too big for its cell refused, empty cells skipped, the wall set cut and anchored bottom right, a thin wall piece
refused, the room ring (post, runs and corner where they belong), the CLI and pieces.csv. Needs numpy and Pillow."""
import contextlib
import csv
import io
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import sheet_cut as C  # noqa: E402


def blob(h, w, col):
    a = np.zeros((h, w, 4), np.uint8)
    a[...] = (*col, 255)
    a[0, :] = a[-1, :] = a[:, 0] = a[:, -1] = (20, 16, 18, 255)
    return a


def pack(k=3, cell=32, gap=3):
    a = np.zeros((k * cell, k * cell, 4), np.uint8)
    for r in range(k):
        for c in range(k):
            col = (60 + 50 * c, 60 + 50 * r, 120)
            a[r * cell + gap:(r + 1) * cell - gap, c * cell + gap:(c + 1) * cell - gap] = blob(cell - 2 * gap, cell - 2 * gap, col)
    return a


def test_gutters_3x3():
    a = pack()
    pieces, how = C.cut_pack(a)
    assert how == 'gutters between items', how
    assert len(pieces) == 9
    assert (pieces[8][0], pieces[8][1]) == (2, 2)
    for _r, _c, p in pieces:
        assert p.shape[:2] == (32, 32)
        b = C.bbox(p)
        assert b[0] >= 1 and b[1] >= 1 and b[2] <= 31 and b[3] <= 31, 'a 1 px margin'


def test_grid_and_json():
    a = pack(2, 32, 0)                   # cells touch: no gutters
    assert C.gutter_cells(a) is None or len(C.gutter_cells(a)) < 4
    pieces, how = C.cut_pack(a, grid=2, anchor='bottom-right')
    assert how == 'grid 2x2' and len(pieces) == 4
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'sheet.png')
        json.dump({'grid': 2, 'cell': 32}, open(os.path.join(d, 'sheet.json'), 'w'))
        pieces, how = C.cut_pack(a, path=path, anchor='bottom-right')
        assert how == 'json next to the sheet' and len(pieces) == 4


def test_upscale_and_backdrop_first():
    a = pack()
    big = a.repeat(4, 0).repeat(4, 1)
    big[big[..., 3] == 0] = (40, 200, 60, 255)    # flat backdrop
    small, s = C.prepare(big)
    assert s == 4
    assert np.array_equal(small[..., 3] > 0, a[..., 3] > 0)
    pieces, how = C.cut_pack(small)
    assert len(pieces) == 9 and how == 'gutters between items'


def test_stray_pixel_stops_gutters():
    a = pack()
    a[1, 1] = (200, 200, 200, 255)       # a stray pixel in a gutter corner
    assert C.gutter_cells(a) is None
    pieces, how = C.cut_pack(a)
    assert how == '32 px cells'


def test_anchors():
    a = np.zeros((64, 64, 4), np.uint8)
    a[10:20, 30:40] = blob(10, 10, (200, 100, 50))
    one = a[:32, 32:]
    item = C.place_item(one)
    b = C.bbox(item)
    assert (b[0] + b[2]) // 2 in (15, 16) and (b[1] + b[3]) // 2 in (15, 16)
    bot = C.place_bottom(one, 32, 32)
    assert C.bbox(bot)[2] == 32
    br = C.anchor_bottom_right(a)
    assert C.bbox(br)[2:] == (64, 64)
    assert (br[..., 3] > 0).sum() == (a[..., 3] > 0).sum(), 'nothing lost'
    try:
        C.place_item(blob(31, 31, (1, 2, 3)))
    except C.CutError:
        pass
    else:
        raise AssertionError('a piece wider than the cell minus its margin is refused')


def test_empty_cells_skipped():
    a = pack(2, 32, 2)
    a[32:, 32:] = 0
    pieces, _how = C.cut_pack(a, grid=2)
    assert len(pieces) == 3


def wall_sheet(cell=64):
    a = np.zeros((2 * cell, 2 * cell, 4), np.uint8)
    a[10:40, 10:16] = blob(30, 6, (120, 110, 100))           # post, not anchored
    a[20:50, 64 + 4:64 + 50] = blob(30, 46, (130, 120, 105))  # north run
    a[64 + 2:64 + 52, 20:30] = blob(50, 10, (125, 115, 100))  # east run
    a[64 + 10:64 + 40, 64 + 10:64 + 40] = blob(30, 30, (135, 125, 110))   # corner
    return a


def test_walls_and_room():
    pieces = C.cut_walls(wall_sheet())
    assert list(pieces) == list(C.WALL_PIECES)
    for k, p in pieces.items():
        assert C.bbox(p)[2:] == (64, 64), k
    r = C.room(pieces, 3)
    assert r.shape[:2] == (4 * 32 + 32, 4 * 32 + 32)
    # the post's colour sits at the north-west, the corner's at the south-east
    assert (r[:64, :64][..., 3] > 0).any()
    se = r[-32:, -32:]
    assert (se[..., :3] == (135, 125, 110)).all(-1).any()
    middle = r[64 + 16:64 + 48, 64 + 16:64 + 48]
    assert not (middle[..., 3] > 0).all(), 'the inside of the room is open'
    thin = wall_sheet()
    thin[64:, :64] = 0
    thin[100, 30] = (1, 1, 1, 255)
    try:
        C.cut_walls(thin)
    except C.CutError as e:
        assert 'east' in str(e)
    else:
        raise AssertionError('a wall piece of 1 px is refused')
    try:
        C.cut_walls(np.zeros((96, 128, 4), np.uint8))
    except C.CutError:
        pass
    else:
        raise AssertionError('a sheet that is not 2 x 2 cells is refused')


def test_cli():
    with tempfile.TemporaryDirectory() as d:
        sheet = os.path.join(d, 'pack.png')
        Image.fromarray(pack(), 'RGBA').save(sheet)
        walls = os.path.join(d, 'walls.png')
        Image.fromarray(wall_sheet(), 'RGBA').save(walls)
        out = os.path.join(d, 'out')
        with contextlib.redirect_stdout(io.StringIO()):
            assert C.main(['pack', sheet, out]) == 0
            assert C.main(['walls', walls, os.path.join(d, 'w')]) == 0
            assert C.main(['room', os.path.join(d, 'w'), os.path.join(d, 'room.png'), '--tiles', '2']) == 0
        rows = list(csv.DictReader(open(os.path.join(out, 'pieces.csv'))))
        assert len(rows) == 9 and rows[0]['file'] == 'pack_r1c1.png'
        assert os.path.exists(os.path.join(d, 'w', 'corner.png'))
        assert np.array(Image.open(os.path.join(d, 'room.png'))).shape[:2] == (128, 128)
        with contextlib.redirect_stderr(io.StringIO()):
            assert C.main(['walls', sheet, os.path.join(d, 'x')]) == 1
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                C.main(['--help'])
            except SystemExit as e:
                assert e.code == 0


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t()
    print('sheet_cut_test: %d tests OK' % len(tests))


if __name__ == '__main__':
    main()
