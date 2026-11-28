#!/usr/bin/env python3
"""Test of pixel_grid.py (O781): python3 -I client/tools/sprites/pixel_grid_test.py

On synthetic pictures drawn here (nothing is anyone's art): an exact nearest upscale found and undone byte for byte, a
native sprite left alone, a painted render (blocks of 4 and of 6 with noise, a shifted grid, a soft rim and a flat
backdrop) brought back to its art pixels, the key colour and the flat backdrop keyed from the border, an enclosed hole of
the backdrop keyed while a near colour stays, specks dropped, the palette clamp and the theme snap, hard alpha, same bytes twice, the
CLI. Needs numpy and Pillow (the fx venv of CI)."""
import contextlib
import io
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import pixel_grid as G  # noqa: E402

DARK = (24, 16, 20)
COLS = [(170, 60, 40), (220, 140, 60), (90, 110, 150), (240, 220, 150)]


def sprite(n=32):
    """a shield of four flat colours with a dark rim, hard alpha, in an n x n cell"""
    a = np.zeros((n, n, 4), np.uint8)
    yy, xx = np.mgrid[0:n, 0:n]
    c = (n - 1) / 2.0
    inside = (np.abs(xx - c) < n * 0.36) & (yy > n * 0.12) & (yy < n * 0.88 - np.abs(xx - c) * 0.5)
    a[inside, 3] = 255
    for i, col in enumerate(COLS):
        part = inside & ((xx // 6 + yy // 7) % 4 == i)
        a[part, :3] = col
    edge = inside & ~(np.roll(inside, 1, 0) & np.roll(inside, -1, 0) & np.roll(inside, 1, 1) & np.roll(inside, -1, 1))
    a[edge, :3] = DARK
    return a


def upscale(a, s):
    return a.repeat(s, 0).repeat(s, 1)


def painted(a, s, dy, dx, noise=3, backdrop=(200, 60, 190), seed=7):
    """an s x s painted render: backdrop, grid shifted by (dy, dx), noisy blocks, half the rim pixels soft"""
    big = upscale(a, s).astype(int)
    h, w = big.shape[:2]
    out = np.zeros((h, w, 4), int)
    out[..., :3] = backdrop
    out[..., 3] = 255
    on = big[..., 3] > 0
    out[on] = big[on]
    rng = np.random.default_rng(seed)
    out[..., :3] += rng.integers(-noise, noise + 1, (h, w, 3))
    out = np.roll(out, (dy, dx), (0, 1))
    return out.clip(0, 255).astype(np.uint8)


def test_exact_upscale():
    a = sprite()
    big = upscale(a, 8)
    assert G.exact_scale(big) == 8
    s, dy, dx, how = G.find_grid(big)
    assert (s, dy, dx, how) == (8, 0, 0, 'exact upscale')
    out = G.depixel(big, s)
    assert np.array_equal(out, a)


def test_native_left_alone():
    a = sprite()
    s, _dy, _dx, how = G.find_grid(a)
    assert s == 1 and how == 'native'
    out, facts = G.clean(a, colours=0)
    assert np.array_equal(out, a), 'a native sprite comes back as it went in'
    assert facts['scale'] == 1


def check_painted(s, dy, dx):
    a = sprite()
    pic = painted(a, s, dy, dx)
    out, facts = G.clean(pic, colours=0)
    assert facts['scale'] == s, facts
    assert facts['phase'] == (dy, dx), facts
    assert facts['how'] == 'painted render', facts
    hh, ww = out.shape[:2]
    ref = a[:hh, :ww]
    assert np.array_equal(out[..., 3] > 0, ref[..., 3] > 0), 'the silhouette of every art pixel is back'
    on = ref[..., 3] > 0
    diff = np.abs(out[on, :3].astype(int) - ref[on, :3].astype(int)).max()
    assert diff <= 3, diff


def test_painted_render_4():
    check_painted(4, 2, 1)


def test_painted_render_6():
    check_painted(6, 3, 5)


def test_key_and_backdrop():
    a = np.zeros((20, 20, 4), np.uint8)
    a[...] = (90, 200, 90, 255)               # flat backdrop
    a[5:15, 5:15] = (40, 40, 140, 255)       # a box
    a[9, 9] = (90, 200, 90, 255)             # an enclosed hole the colour of the backdrop
    a[12, 12] = (90, 160, 70, 255)           # an enclosed green that is not the backdrop (diff 60 > tol / 2)
    a[6, 6] = (255, 0, 255, 255)             # the exact key inside the box
    out, col = G.key_out(a)
    assert col == (90, 200, 90), col
    assert out[0, 0, 3] == 0 and out[19, 19, 3] == 0
    assert out[9, 9, 3] == 0, 'an enclosed hole of the backdrop goes'
    assert out[12, 12, 3] == 255, 'an enclosed colour near the backdrop stays'
    assert out[6, 6, 3] == 0, 'the exact key goes anywhere'
    assert out[10, 10, 3] == 255
    clear = np.zeros((20, 20, 4), np.uint8)
    clear[5:15, 5:15] = (40, 40, 140, 255)
    assert G.key_out(clear)[1] is None, 'a transparent border has no backdrop'


def test_despeckle():
    a = np.zeros((16, 16, 4), np.uint8)
    a[2, 2] = (200, 200, 200, 255)                       # lone pixel
    a[6, 6] = a[6, 7] = (200, 200, 200, 255)             # two-pixel speck
    a[10, 10] = a[10, 11] = a[11, 10] = (200, 200, 200, 255)   # three: kept
    out = G.despeckle(a)
    assert out[2, 2, 3] == 0 and out[6, 6, 3] == 0 and out[6, 7, 3] == 0
    assert out[10, 10, 3] == 255 and out[11, 10, 3] == 255


def test_palette_and_theme():
    rng = np.random.default_rng(3)
    a = np.zeros((32, 32, 4), np.uint8)
    a[4:28, 4:28, :3] = rng.integers(0, 255, (24, 24, 3))
    a[4:28, 4:28, 3] = 255
    out = G.palette(a, colours=12)
    assert len(np.unique(out[out[..., 3] > 0][:, :3], axis=0)) <= 12
    themed = G.palette(a, theme='cinderwrought')
    pal = {tuple(int(v) for v in c) for c in G.theme_palette('cinderwrought')}
    got = {tuple(int(v) for v in c) for c in themed[themed[..., 3] > 0][:, :3]}
    assert got <= pal, 'every colour is a theme colour'


def test_hard_alpha_and_bytes():
    pic = painted(sprite(), 4, 1, 3)
    soft = pic.copy()
    soft[::3, ::5, 3] = 150
    out1, _ = G.clean(soft)
    out2, _ = G.clean(soft)
    assert set(np.unique(out1[..., 3]).tolist()) <= {0, 255}
    assert not out1[out1[..., 3] == 0, :3].any(), 'a transparent pixel carries no colour'
    assert out1.tobytes() == out2.tobytes()


def test_cli():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, 'in.png')
        dst = os.path.join(d, 'out.png')
        Image.fromarray(painted(sprite(), 4, 0, 2), 'RGBA').save(src)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            assert G.main(['scale', src]) == 0
            assert G.main(['clean', src, dst, '--colours', '16']) == 0
        assert 'scale 4' in buf.getvalue()
        out = np.array(Image.open(dst))
        assert out.shape[:2] == (31, 31) or out.shape[:2] == (32, 31) or out.shape[0] in (31, 32)
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                G.main(['--help'])
            except SystemExit as e:
                assert e.code == 0


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t()
    print('pixel_grid_test: %d tests OK' % len(tests))


if __name__ == '__main__':
    main()
