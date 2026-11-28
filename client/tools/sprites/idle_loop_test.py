#!/usr/bin/env python3
"""Test of idle_loop.py (O781): python3 -I client/tools/sprites/idle_loop_test.py

On synthetic sprites drawn here (nothing is anyone's art): every effect and every element closes its loop (frame n is
frame 0), keeps the body whole, alpha 0 / 255 (and the one glow level 144 only with --soft), no lone pixel or speck
outside the body, no colour outside the sprite's colours and the layer ramps (or the theme with --theme), moves; repeats
run an effect more often, strength 0 leaves the sprite still, flames rise above the top edge and drops fall under the
bottom edge, the same settings give the same bytes and the json written by `make` makes the same strip again, `check`
refuses a soft pixel and a hole. Needs numpy and Pillow (the fx venv of CI)."""
import contextlib
import io
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import idle_loop as I  # noqa: E402


def brazier(w=32, h=32):
    """a bowl on a foot with a bright green gem, dark rim, in the lower half of its canvas"""
    a = np.zeros((h, w, 4), np.uint8)
    a[h - 14:h - 2, 6:w - 6] = (110, 80, 60, 255)
    a[h - 6:h - 2, 12:w - 12] = (80, 60, 50, 255)
    a[h - 14, 6:w - 6] = (30, 20, 20, 255)
    a[h - 14:h - 2, 6] = (30, 20, 20, 255)
    a[h - 14:h - 2, w - 7] = (30, 20, 20, 255)
    a[h - 10:h - 8, w // 2 - 1:w // 2 + 1] = (60, 240, 80, 255)
    return a


def colours(a):
    return {tuple(int(v) for v in c) for c in a[a[..., 3] > 0][:, :3]}


def allowed(a, specs):
    sp = I.Sprite(a)
    cols = colours(a)
    for s in specs:
        cols |= set(I.Layer(sp, s, I.FRAMES, 0).r.values())
    return cols


def each_spec():
    for e in I.EFFECTS:
        yield e, [I.layer(e)]
    for k in sorted(I.ELEMENTS):
        yield k, I.element_layers(k)


def test_every_effect_holds_the_rules():
    a = brazier()
    body = a[..., 3] > 0
    for name, specs in each_spec():
        frames = I.animate(a, specs)
        assert len(frames) == I.FRAMES
        errs = I.check(frames, body)
        assert not errs, (name, errs)
        again = I.animate(a, specs, times=[0, I.FRAMES, 2 * I.FRAMES + 3])
        assert np.array_equal(again[0], again[1]), (name, 'frame n is frame 0: the loop closes')
        assert np.array_equal(again[2], frames[3]), name
        ok = allowed(a, specs)
        for f in frames:
            assert colours(f) <= ok, (name, 'a colour outside the sprite and the ramps')
            assert set(np.unique(f[..., 3]).tolist()) <= {0, 255}, name


def test_soft_glow_level():
    a = brazier()
    frames = I.animate(a, I.element_layers('fire'), soft=True)
    levels = set()
    for f in frames:
        levels |= set(np.unique(f[..., 3]).tolist())
    assert levels <= {0, 144, 255} and 144 in levels, levels
    assert not I.check(frames, a[..., 3] > 0, soft=True)
    assert I.check(frames, a[..., 3] > 0, soft=False), 'a soft pixel fails the hard rule'


def test_repeats_and_strength():
    a = brazier()
    f = I.animate(a, [I.layer('pulse', repeats=2)])
    for t in range(I.FRAMES // 2):
        assert np.array_equal(f[t], f[t + I.FRAMES // 2]), 'twice a loop'
    still = I.animate(a, [I.layer('pulse', strength=0.0)])
    assert all(np.array_equal(x, a) for x in still)
    assert 'nothing moves' in I.check(still, a[..., 3] > 0)


def test_flames_rise_and_drops_fall():
    a = brazier()
    body = a[..., 3] > 0
    top = np.nonzero(body.any(1))[0].min()
    bottom = np.nonzero(body.any(1))[0].max()
    seen_above = False
    for f in I.animate(a, [I.layer('flames', (240, 110, 20))]):
        added = (f[..., 3] > 0) & ~body
        ys = np.nonzero(added)[0]
        assert (ys < top).all(), 'flames only above the top edge'
        seen_above |= len(ys) > 0
    assert seen_above
    a2 = np.zeros((32, 32, 4), np.uint8)
    a2[2:10, 10:22] = (60, 120, 60, 255)
    body2 = a2[..., 3] > 0
    fell = False
    for f in I.animate(a2, [I.layer('drip', (110, 190, 60))]):
        ys = np.nonzero((f[..., 3] > 0) & ~body2)[0]
        assert (ys > 9).all()
        fell |= len(ys) > 0
    assert fell and bottom > 0


def test_seed_and_bytes():
    a = brazier()
    specs = [I.layer('flames', (240, 110, 20))]
    one = I.animate(a, specs, seed=1)
    two = I.animate(a, specs, seed=1)
    other = I.animate(a, specs, seed=2)
    assert all(np.array_equal(x, y) for x, y in zip(one, two))
    assert any(not np.array_equal(x, y) for x, y in zip(one, other))


def test_theme_snap():
    import style_check
    a = brazier()
    pal = {tuple(int(v) for v in style_check.unhex(c))
           for c in style_check.load_palettes()['themes']['cinderwrought']['palette']}
    for f in I.animate(a, I.element_layers('fire'), theme='cinderwrought'):
        changed = (np.abs(f[..., :3].astype(int) - a[..., :3].astype(int)).sum(-1) > 0) & (f[..., 3] > 0)
        got = {tuple(int(v) for v in c) for c in f[changed][:, :3]}
        assert got <= pal


def test_check_refuses_a_hole():
    a = brazier()
    frames = I.animate(a, [I.layer('glint')])
    frames[2] = frames[2].copy()
    ys, xs = np.nonzero(a[..., 3] > 0)
    frames[2][ys[5], xs[5]] = 0
    assert any('hole' in e for e in I.check(frames, a[..., 3] > 0))


def test_empty_sprite_refused():
    try:
        I.animate(np.zeros((32, 32, 4), np.uint8), [I.layer('pulse')])
    except ValueError:
        return
    raise AssertionError('an empty sprite has no loop')


def test_cli_and_json_round_trip():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, 'brazier.png')
        out = os.path.join(d, 'loop.png')
        Image.fromarray(brazier(), 'RGBA').save(src)
        with contextlib.redirect_stdout(io.StringIO()) as buf:
            assert I.main(['make', src, out, '--element', 'fire', '--layer', 'glint:ffe080::2:3', '--frames', '8',
                           '--ms', '110', '--seed', '4']) == 0
            assert I.main(['check', out, '--frames', '8']) == 0
            assert I.main(['effects']) == 0
        assert 'PASS' in buf.getvalue()
        meta = json.load(open(os.path.join(d, 'loop.json')))
        assert meta['frames'] == 8 and meta['ms'] == 110 and len(meta['layers']) == 4
        assert meta['layers'][3]['repeats'] == 2 and meta['layers'][3]['amount'] == 3
        again = I.animate(np.array(Image.open(src).convert('RGBA')), meta['layers'], meta['frames'], meta['seed'],
                          meta['soft'], meta['theme'])
        assert np.array_equal(I.strip(again), np.array(Image.open(out).convert('RGBA'))), 'the json makes it again'
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                I.main(['--help'])
            except SystemExit as e:
                assert e.code == 0
        try:
            I.parse_layer('wobble')
        except ValueError:
            pass
        else:
            raise AssertionError('an unknown effect is refused')


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t()
    print('idle_loop_test: %d tests OK' % len(tests))


if __name__ == '__main__':
    main()
