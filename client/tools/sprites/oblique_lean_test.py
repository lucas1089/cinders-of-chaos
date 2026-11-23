#!/usr/bin/env python3
"""Test of oblique_lean.py (O728): python3 -I client/tools/sprites/oblique_lean_test.py

The shear on synthetic pictures drawn here: the shift of every row (floor(k * (feet - y) + 0.5) px left, a row under the feet right), the
feet row fixed, hard alpha and colours kept, no pixel dropped, the feet line of the standing picture used for every frame of its direction
(a lifted foot does not move it), a pixel that would leave the canvas refused, `lean_frames` lowering k a hundredth at a time down to
K_MIN and refusing below it, the guard (a figure leaning 9 px or more in south or east is refused unless forced), the lean rule and its
band, `align_to_standing` (one whole pixel shift a group onto the standing feet), and `read_drop` on a synthetic PixelLab download.
Needs numpy and Pillow (the fx venv of CI). Nothing drawn here is art of anyone."""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import oblique_lean as L  # noqa: E402


def body(w=64, h=64, x=20, y=8, bw=16, bh=48, seed=1):
    """a standing block of random colours with two legs, hard alpha"""
    rng = np.random.default_rng(seed)
    a = np.zeros((h, w, 4), np.uint8)
    a[y:y + bh, x:x + bw, :3] = rng.integers(30, 250, (bh, bw, 3))
    a[y:y + bh, x:x + bw, 3] = 255
    a[y + bh:y + bh + 6, x + 2:x + 5, :3] = 60
    a[y + bh:y + bh + 6, x + bw - 5:x + bw - 2, :3] = 60
    a[y + bh:y + bh + 6, x + 2:x + 5, 3] = 255
    a[y + bh:y + bh + 6, x + bw - 5:x + bw - 2, 3] = 255
    return a


def frames_of(pics):
    """{(group, direction): [pictures]}: the same pictures in the four directions, idle and walk"""
    return {(g, d): [p.copy() for p in pics] for g in ('idle', 'walk') for d in range(4)}


def main():
    a = body()
    fy = L.feet_row(a)
    assert fy == 8 + 48 + 5
    s = L.shear(a, 0.25)
    for y in range(a.shape[0]):
        xs, xt = np.nonzero(a[y, :, 3])[0], np.nonzero(s[y, :, 3])[0]
        if len(xs):
            k = int(np.floor(0.25 * (fy - y) + 0.5))
            assert (xt == xs - k).all(), (y, k)
            assert (s[y, xt] == a[y, xs]).all(), 'colours move with their pixel'
    assert (s[fy] == a[fy]).all(), 'the feet row stays'
    assert int((s[..., 3] > 0).sum()) == int((a[..., 3] > 0).sum()), 'no pixel dropped'
    assert set(np.unique(s[..., 3]).tolist()) <= {0, 255} and not s[s[..., 3] == 0].any(), 'hard alpha, no colour under clear'
    assert L.shift_of(fy, fy) == 0 and L.shift_of(fy - 4, fy) == 1 and L.shift_of(fy - 2, fy) == 1 and L.shift_of(fy + 4, fy) == -1
    ln0, ln1 = L.lean(a), L.lean(s)
    assert abs(ln0) < 1 and ln1 > 9, (ln0, ln1)

    # the feet line of the standing picture holds for every frame of the direction: a frame with a foot lifted is not re-anchored
    lifted = a.copy()
    lifted[fy - 1:fy + 1] = 0                   # both feet off the ground: its own lowest row is 2 higher
    assert L.feet_row(lifted) == fy - 2
    fr = {('idle', d): [a, lifted] for d in range(4)}
    fr.update({('walk', d): [lifted] for d in range(4)})
    sh = L.shear_frames(fr, 0.25)
    assert (sh[('idle', 0)][1] == L.shear(lifted, 0.25, fy)).all() and not (sh[('idle', 0)][1] == L.shear(lifted, 0.25)).all()

    # a pixel that would leave the canvas is refused; lean_frames lowers k for that look, never under K_MIN
    edge = body(x=2)
    try:
        L.shear(edge, 0.25)
    except L.LostPixel:
        pass
    else:
        raise AssertionError('a pixel left the canvas')
    near = body(x=12)                           # room for 12 px: the top row is 53 over the feet, k 0.25 moves it 13, 0.23 moves it 12
    out, k = L.lean_frames(frames_of([near]))
    assert round(k, 2) == 0.23, k
    assert int((out[('idle', 2)][0][..., 3] > 0).sum()) == int((near[..., 3] > 0).sum())
    try:
        L.lean_frames(frames_of([body(x=5)]))
    except L.LostPixel as e:
        assert '0.15' in str(e)
    else:
        raise AssertionError('k fell under K_MIN')
    out, k = L.lean_frames(frames_of([a]), fits=lambda fr: L.lean(fr[("idle", 2)][0]) < 9)
    assert k < 0.25 and L.lean(out[("idle", 2)][0]) < 9, "fits() lowers k too"

    # the guard: art that leans already is left as drawn, unless forced
    leaning = frames_of([s])
    assert L.leaning(leaning) and not L.leaning(frames_of([a]))
    try:
        L.lean_frames(leaning)
    except ValueError as e:
        assert 'already' in str(e)
    else:
        raise AssertionError('a leaning look was sheared twice')
    wide = {kk: [L.pad(x, 20) for x in v] for kk, v in leaning.items()}
    assert L.lean_frames(wide, force=True)[1] == 0.25

    # the rule: south or east in the band
    assert L.lean_ok(leaning) and not L.lean_ok(frames_of([a]))
    assert L.lean_problem('x', leaning) is None and 'game\'s angle' in L.lean_problem('x', frames_of([a]))
    far = L.shear(L.pad(a, 50), 0.8)
    assert L.lean(far) > L.LEAN[1] and not L.lean_ok(frames_of([far])), 'over the band'
    only_east = {**frames_of([a]), ('idle', 1): [s]}
    assert L.lean_ok(only_east), 'east alone is enough'
    assert L.LEAN == (9.0, 26.0) and L.K == 0.25 and L.K_MIN == 0.15

    # align_to_standing: one shift a group, the median feet onto the standing feet
    moved = [np.roll(a, (2, -3), axis=(0, 1)), np.roll(a, (2, -3), axis=(0, 1))]
    back, mv = L.align_to_standing(a, moved)
    assert mv == (3, -2) and all((b == a).all() for b in back), mv

    # read_drop: a synthetic PixelLab download (rotations, walkv3 per direction with the standing frame_000)
    with tempfile.TemporaryDirectory() as tmp:
        st = os.path.join(tmp, 'k', 'Idle')
        for i, d in enumerate(L.DROP_DIRS):
            os.makedirs(os.path.join(st, 'rotations'), exist_ok=True)
            Image.fromarray(L.shear(body(80, 80, 40, 10, seed=i), 0.3), 'RGBA').save(os.path.join(st, 'rotations', d + '.png'))
            wd = os.path.join(st, 'animations', 'walkv3-%d' % i, d)
            os.makedirs(wd)
            for f in range(9):
                p = L.shear(body(80, 80, 40, 10 + f % 2, seed=10 + f), 0.3)
                Image.fromarray(np.roll(p, 1, axis=1), 'RGBA').save(os.path.join(wd, 'frame_%03d.png' % f))
        dr = L.read_drop(os.path.join(tmp, 'k'))
        assert [len(dr['walk'][d]) for d in L.DROP_DIRS] == [8] * 4 and [len(dr['idle'][d]) for d in L.DROP_DIRS] == [4] * 4
        assert all(set(np.unique(x[..., 3]).tolist()) <= {0, 255} for v in dr['walk'].values() for x in v)
        assert len({x.tobytes() for x in dr['idle']['south']}) >= 2, 'the breath moves'
        assert L.lean_ok(L.drop_frames(dr))
        os.remove(os.path.join(st, 'animations', 'walkv3-0', 'north', 'frame_008.png'))
        os.remove(os.path.join(st, 'animations', 'walkv3-0', 'north', 'frame_007.png'))
        try:
            L.read_drop(os.path.join(tmp, 'k'))
        except ValueError as e:
            assert 'walk pictures' in str(e)
        else:
            raise AssertionError('a short walk was taken')
    print('oblique_lean_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
