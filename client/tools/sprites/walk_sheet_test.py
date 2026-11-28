#!/usr/bin/env python3
"""Test of walk_sheet.py (O781): python3 -I client/tools/sprites/walk_sheet_test.py

On synthetic figures drawn here (nothing is anyone's art): a sheet of direction rows in south, west, north, east order
and a 4 x 2 frame grid per direction brought to the engine columns north, east, south, west; the transpose of a figure
leaning up and left matches its east and keeps the lean, its mirror turns the lean round and fails; `derive` takes a
transpose that fits, refuses a mirror against a drawn target and a made direction that leans the wrong way, takes it
with --force; non-square frames and bad orders refused; the CLI. Needs numpy and Pillow (the fx venv of CI)."""
import contextlib
import io
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import walk_sheet as W  # noqa: E402

S = 64


def figure(step=0, col=(150, 90, 60)):
    """a body drawn along the view's diagonal: feet bottom right, head up and left, a pack on one side"""
    a = np.zeros((S, S, 4), np.uint8)
    for k in range(34):
        cy, cx = 54 - k, 50 - k + (step if k < 6 else 0)
        r = 5 if k > 26 else 4
        a[max(0, cy - r):cy + r, max(0, cx - 2):cx + 2] = (*col, 255)
    a[30:36, 26:32] = (60, 140, 200, 255)        # the pack: makes the figure handed
    return a


def dirs(step=0):
    s = figure(step)
    n = figure(step, (120, 70, 50))
    return {'south': s, 'north': n, 'east': W.transpose(s), 'west': W.transpose(n)}


def test_engine_rows_and_grid():
    frames = 8
    per = {d: [dirs(f)[d] for f in range(frames)] for d in W.ENGINE}
    rows = np.concatenate([np.concatenate(per[d], axis=1) for d in ('south', 'west', 'north', 'east')], axis=0)
    eng = W.to_engine(rows, W.parse_order('swne'), frames)
    back = W.engine_frames(eng)
    for d in W.ENGINE:
        for f in range(frames):
            assert np.array_equal(back[d][f], per[d][f]), (d, f)
    blocks = []
    for d in ('south', 'west', 'north', 'east'):
        top = np.concatenate(per[d][:4], axis=1)
        bot = np.concatenate(per[d][4:], axis=1)
        blocks.append(np.concatenate([top, bot], axis=0))
    eng2 = W.to_engine(np.concatenate(blocks, axis=0), W.parse_order('swne'), frames, (4, 2))
    assert np.array_equal(eng, eng2)


def test_fit_transpose_holds_mirror_does_not():
    per = {d: [v] for d, v in dirs().items()}
    got = {(m, op): (match, lm, ld) for m, op, _s, match, lm, ld in W.fit(per)}
    assert got[('east', 'transpose')][0] == 1.0
    assert got[('west', 'mirror')][0] < W.FIT_MIN
    assert got[('east', 'transpose')][1] > 9, 'the transpose keeps the lean'
    assert got[('west', 'mirror')][1] < 0, 'a mirror turns it round'


def test_derive_rules():
    d = dirs()
    per = {k: [v] for k, v in d.items()}
    out = W.derive(per, ['east=transpose:south'])
    assert np.array_equal(out['east'][0], d['east'])
    try:
        W.derive(per, ['west=mirror:east'])
    except W.SheetError as e:
        assert 'does not hold' in str(e)
    else:
        raise AssertionError('a mirror against a drawn west is refused')
    empty = dict(per)
    empty['east'] = [np.zeros_like(d['east'])]
    assert np.array_equal(W.derive(empty, ['east=transpose:south'])['east'][0], d['east'])
    try:
        W.derive(empty, ['east=mirror:west'])
    except W.SheetError as e:
        assert 'leans' in str(e)
    else:
        raise AssertionError('a made east that leans the wrong way is refused')
    W.derive(empty, ['east=mirror:west'], force=True)
    for bad in ('east', 'east=spin:south', 'east=mirror:east'):
        try:
            W.derive(per, [bad])
        except W.SheetError:
            continue
        raise AssertionError(bad)


def test_refusals():
    try:
        W.transpose(np.zeros((32, 64, 4), np.uint8))
    except W.SheetError:
        pass
    else:
        raise AssertionError('transpose needs square frames')
    for bad in ('nes', 'nnsw', 'abcd'):
        try:
            W.parse_order(bad)
        except W.SheetError:
            continue
        raise AssertionError(bad)
    try:
        W.to_engine(np.zeros((100, 100, 4), np.uint8), W.ENGINE, 8)
    except W.SheetError:
        pass
    else:
        raise AssertionError('not whole cells')


def test_cli():
    with tempfile.TemporaryDirectory() as tmp:
        d = dirs()
        for k, v in d.items():
            Image.fromarray(v, 'RGBA').save(os.path.join(tmp, k + '.png'))
        eng = np.concatenate([d[k] for k in W.ENGINE], axis=1)
        eng[:, S:2 * S] = 0
        Image.fromarray(eng, 'RGBA').save(os.path.join(tmp, 'eng.png'))
        with contextlib.redirect_stdout(io.StringIO()) as buf:
            assert W.main(['fit', tmp]) == 0
            assert W.main(['derive', os.path.join(tmp, 'eng.png'), os.path.join(tmp, 'out.png'),
                           '--make', 'east=transpose:south']) == 0
        assert 'holds' in buf.getvalue()
        out = np.array(Image.open(os.path.join(tmp, 'out.png')))
        assert np.array_equal(out[:, S:2 * S], d['east'])
        with contextlib.redirect_stderr(io.StringIO()):
            assert W.main(['engine', os.path.join(tmp, 'eng.png'), os.path.join(tmp, 'x.png'), '--order', 'nnnn']) == 1
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                W.main(['--help'])
            except SystemExit as e:
                assert e.code == 0


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t()
    print('walk_sheet_test: %d tests OK' % len(tests))


if __name__ == '__main__':
    main()
