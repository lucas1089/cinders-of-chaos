#!/usr/bin/env python3
"""Test of idle_loop.py (O781): python3 -I client/tools/sprites/idle_loop_test.py

On synthetic sprites drawn here (nothing is anyone's art): every effect and every element closes its loop (frame n is
frame 0), keeps the body whole, alpha 0 / 255 (and the one glow level 144 only with --soft), no lone pixel or speck
outside the body, no colour outside the sprite's colours and the layer ramps (or the theme with --theme), moves; repeats
run an effect more often, strength 0 leaves the sprite still, flames rise above the top edge and drops fall under the
bottom edge, the same settings give the same bytes and the json written by `make` makes the same strip again, `check`
refuses a soft pixel and a hole.
O783 (the X1 run on 24 still items): --clamp cuts a still with too many colours and is kept in the json, --pad grows a
1 x 1 still to 64 x 64 at the bottom right and the flames use the room, drip runs down the face of a body on the bottom
row or is refused, a pulse on a small palette gets ramp steps (as many distinct frames as the loop allows, the palette
under the cap), shine and rim grow with the body, a glint is lit in every frame and refused when it cannot show, a pair
thing is a source (first phase, its client id and dat md5 in the json) and `remake` rebuilds from the json.
Needs numpy and Pillow (the fx venv of CI)."""
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


def allowed(a, specs, frames=I.FRAMES):
    sp = I.Sprite(a)
    layers = [I.Layer(sp, s, frames, 0) for s in specs]
    return {tuple(int(v) for v in c) for c in I.palette_of(sp, layers)}


def changed_share(frames, a):
    """the largest share of the body any frame changes"""
    body = a[..., 3] > 0
    return max(float(((np.abs(f.astype(int) - a.astype(int)).sum(-1) > 0) & body).sum()) / body.sum() for f in frames)


def gradient(w=32, h=32, y0=4):
    """a body of hundreds of colours: a smooth two-way gradient (like a rendered stock item)"""
    a = np.zeros((h, w, 4), np.uint8)
    for y in range(y0, h - 2):
        for x in range(4, w - 4):
            a[y, x] = (40 + (x * 197) // w, 30 + (y * 181) // h, 90 + ((x + y) * 61) // (w + h), 255)
    return a


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


def test_clamp_kept_in_the_json():
    a = gradient()
    assert len(colours(a)) > I.COLOURS_CELL
    errs = I.build(a, [I.layer('glint', (255, 230, 120))])[1]
    assert any('colours' in e for e in errs) and any('--clamp' in e for e in errs), errs
    frames, errs, meta = I.build(a, [I.layer('glint', (255, 230, 120))], clamp=56)
    assert not errs, errs
    assert meta['clamp'] == 56 and meta['pad'] is False
    assert len(colours(I.prepare(a, 56))) <= 56
    for bad in (I.CLAMP_MIN - 1, I.COLOURS_CELL + 1):
        try:
            I.prepare(a, bad)
        except ValueError:
            continue
        raise AssertionError('--clamp %d is refused' % bad)
    with tempfile.TemporaryDirectory() as d:
        src, out, again = (os.path.join(d, n) for n in ('g.png', 'loop.png', 'again.png'))
        Image.fromarray(a, 'RGBA').save(src)
        with contextlib.redirect_stdout(io.StringIO()):
            assert I.main(['make', src, out, '--clamp', '56', '--element', 'holy']) == 0
            assert I.main(['remake', os.path.join(d, 'loop.json'), again, '--png', src]) == 0
        assert np.array_equal(np.array(Image.open(out)), np.array(Image.open(again))), 'the json rebuilds the strip'
        assert json.load(open(os.path.join(d, 'loop.json')))['clamp'] == 56
        Image.fromarray(brazier(), 'RGBA').save(src)
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                I.main(['remake', os.path.join(d, 'loop.json'), again, '--png', src])
            except SystemExit as e:
                assert 'sha256' in str(e)
            else:
                raise AssertionError('another PNG is refused')


def test_pad_gives_headroom():
    a = np.zeros((32, 32, 4), np.uint8)
    a[4:30, 8:24] = (110, 80, 60, 255)                    # a 1 x 1 brazier filling its tile: no room above
    a[4, 8:24] = (30, 20, 20, 255)
    p = I.prepare(a, pad=True)
    assert p.shape == (64, 64, 4) and np.array_equal(p[32:, 32:], a) and not p[:32].any() and not p[:, :32].any()
    frames, errs, meta = I.build(a, I.element_layers('fire'), soft=True, pad=True)
    assert not errs, errs
    assert meta['pad'] is True and meta['size'] == [64, 64] and meta['source_size'] == [32, 32]
    above = max(int(((f[..., 3] > 0) & (np.arange(64)[:, None] < 32 + 4)).sum()) for f in frames)
    assert above >= 20, 'flames rise into the room the pad gave (%d px)' % above
    try:
        I.prepare(np.zeros((96, 32, 4), np.uint8), pad=True)
    except ValueError:
        pass
    else:
        raise AssertionError('a sprite over 64 px is not padded')


def test_drip_down_the_face_or_refused():
    a = np.zeros((32, 32, 4), np.uint8)
    a[12:32, 8:24] = (60, 120, 60, 255)                   # standing on the bottom row: no room under it
    body = a[..., 3] > 0
    frames = I.animate(a, [I.layer('drip', (110, 190, 60))])
    assert not I.check(frames, body)
    for f in frames:
        assert np.array_equal(f[..., 3], a[..., 3]), 'down the face: nothing added outside the body'
    rows = set()
    for f in frames:
        ys = np.nonzero((np.abs(f[..., :3].astype(int) - a[..., :3].astype(int)).sum(-1) > 0) & body)[0]
        rows |= set(ys.tolist())
    assert max(rows) - min(rows) >= I.DRIP_ROOM, 'the drop runs down the face'
    flat = np.zeros((32, 32, 4), np.uint8)
    flat[29:32, 4:28] = (60, 120, 60, 255)                # a flat slab on the bottom row: nowhere to run
    try:
        I.animate(flat, [I.layer('drip')])
    except ValueError as e:
        assert 'drip' in str(e) and 'room' in str(e)
    else:
        raise AssertionError('drip with no room is refused')


def test_pulse_ramp_steps():
    a = np.zeros((32, 32, 4), np.uint8)
    a[8:28, 8:24] = (70, 60, 80, 255)
    a[8, 8:24] = (30, 25, 35, 255)
    a[16:19, 14:18] = (150, 40, 50, 255)                 # a small dull red gem: 3 colours in all
    for n in (12, 16):
        frames = I.animate(a, [I.layer('pulse', (255, 60, 60))], frames=n)
        assert len({f.tobytes() for f in frames}) == n // 2 + 1, 'every pulse level is its own frame'
        assert not I.check(frames, a[..., 3] > 0)
        for f in frames:
            assert colours(f) <= allowed(a, [I.layer('pulse', (255, 60, 60))], n)
    full = gradient(y0=6)
    full = I.prepare(full, 60)
    sp = I.Sprite(full)
    layers = [I.Layer(sp, I.layer('pulse', (255, 60, 60)), 16, 0)]
    assert len(I.palette_of(sp, layers)) <= I.COLOURS_CELL, 'the steps stop at the cap'
    assert not I.check(I.animate(full, [I.layer('pulse', (255, 60, 60))], frames=16), full[..., 3] > 0)


def test_shine_and_rim_scale_with_the_body():
    big = np.zeros((64, 64, 4), np.uint8)
    big[4:62, 6:58] = (90, 90, 100, 255)
    big[4, 6:58] = (20, 20, 30, 255)
    small = np.zeros((32, 32, 4), np.uint8)
    small[14:26, 10:22] = (90, 90, 100, 255)
    for eff, least in (('shine', 0.12), ('rim', 0.08)):
        sb = changed_share(I.animate(big, [I.layer(eff, (255, 215, 110))]), big)
        assert sb >= least, (eff, sb)
        assert not I.check(I.animate(big, [I.layer(eff, (255, 215, 110))]), big[..., 3] > 0)
    sp_b, sp_s = I.Sprite(big), I.Sprite(small)
    lb, ls = I.Layer(sp_b, I.layer('shine'), 12, 0), I.Layer(sp_s, I.layer('shine'), 12, 0)
    assert lb.shine_half() > ls.shine_half() >= 1 and lb.rim_thick() > ls.rim_thick() == 1


def test_glint_always_visible_or_refused():
    a = brazier()
    hot = I.ramp((255, 215, 110))['hot']
    a[a[..., 1] == 240] = (*hot, 255)                     # the accent already wears the glint's hot colour
    body = a[..., 3] > 0
    for amount in (1, 2, 4):
        for n in (8, 12, 16):
            frames = I.animate(a, [I.layer('glint', (255, 215, 110), amount=amount)], frames=n)
            assert not I.check(frames, body)
            for t, f in enumerate(frames):
                assert not np.array_equal(f, a), 'frame %d equal to the still (amount %d, %d frames)' % (t, amount, n)
    white = np.zeros((32, 32, 4), np.uint8)
    white[8:24, 8:24] = (*hot, 255)
    try:
        I.animate(white, [I.layer('glint', (255, 215, 110))])
    except ValueError as e:
        assert 'glint' in str(e)
    else:
        raise AssertionError('a glint that cannot show is refused')


def test_pair_source_and_remake():
    import check_pair_test as cpt
    a = brazier()
    other = a.copy()
    other[..., :3] = 255 - other[..., :3]
    other[other[..., 3] == 0] = 0

    def rec(img):
        return cpt.record({y * 32 + x: tuple(int(v) for v in img[y, x])
                           for y in range(32) for x in range(32) if img[y, x, 3]})
    items = [cpt.entry(b'', [cpt.group([1])]), cpt.entry(b'', [cpt.group([1, 2], phases=2)])]
    c = cpt.Case()
    dat, spr = c.pair([rec(a), rec(other)], items, [], [], [])
    still, md5 = I.pair_still(dat, spr, 101)
    assert np.array_equal(still, a), 'the first phase of item 101'
    with tempfile.TemporaryDirectory() as d:
        out, again = os.path.join(d, 'loop.png'), os.path.join(d, 'again.png')
        with contextlib.redirect_stdout(io.StringIO()):
            assert I.main(['make', '--pair', dat, spr, '--item', '101', out, '--element', 'holy', '--pad']) == 0
            meta = json.load(open(os.path.join(d, 'loop.json')))
            assert meta['pair'] == {'item': 101, 'dat_md5': I.file_md5(dat)} and meta['pad'] is True
            assert I.main(['remake', os.path.join(d, 'loop.json'), again, '--pair', dat, spr]) == 0
        assert np.array_equal(np.array(Image.open(out)), np.array(Image.open(again))), 'the pair rebuilds the strip'
        dat2, spr2 = c.pair([rec(other), rec(a)], items + [cpt.entry(b'', [cpt.group([2])])], [], [], [])
        I._PAIRS.clear()
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                I.main(['remake', os.path.join(d, 'loop.json'), again, '--pair', dat2, spr2])
            except SystemExit as e:
                assert 'md5' in str(e)
            else:
                raise AssertionError('another dat is refused')
        try:
            I.pair_still(dat, spr, 300)
        except ValueError:
            pass
        else:
            raise AssertionError('an item outside the dat is refused')


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t()
    print('idle_loop_test: %d tests OK' % len(tests))


if __name__ == '__main__':
    main()
