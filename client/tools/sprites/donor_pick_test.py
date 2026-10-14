#!/usr/bin/env python3
"""Tests of donor_pick.py's rules that need no library: catalogue tags, the stock pixel compare, the edits.

python3 -I client/tools/sprites/donor_pick_test.py      (numpy: python3-numpy)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
import donor_pick as dp  # noqa: E402

FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def figure(seed, shift=(0, 0), across=False):
    """a 64x64 RGBA 'body': a shaded blob with random texture at the bottom-right of the frame"""
    rng = np.random.RandomState(seed)
    a = np.zeros((64, 64, 4), np.uint8)
    y0, x0 = 20 + shift[1], 30 + shift[0]
    for y in range(y0, 62):
        for x in range(x0, 60):
            if (x - 45) ** 2 / 200 + (y - 42) ** 2 / 500 <= 1:
                v = (200 - (x - x0) * 5 if across else 60 + (y - y0) * 3) + rng.randint(0, 60)
                a[y, x] = (v, max(0, v - 30), min(255, v + 20), 255)
    return a


def test_pixel_match():
    a = figure(1)
    same, lum = dp.pixel_match(a, a)
    expect(same == 1.0 and lum > 0.99, f'a copy: {same:.2f} / {lum:.2f}')
    moved = np.zeros_like(a)
    moved[:-2, :-1] = a[2:, 1:]                                   # the same art 2 px up, 1 px left in its frame
    expect(dp.pixel_match(a, moved)[0] == 1.0, 'a shifted copy is still a copy')
    rec = a.copy()
    rec[..., :3] = a[..., [2, 0, 1]]                              # channels swapped: a recolour
    same, lum = dp.pixel_match(a, rec)
    expect(same < 0.6 and lum >= 0.6, f'a recolour: rgb differs ({same:.2f}), luminance follows ({lum:.2f})')
    other = figure(7, across=True)                                # same shape, other shading and texture
    same, lum = dp.pixel_match(a, other)
    expect(max(same, lum) < 0.6, f'same body shape, other pixels: {same:.2f} / {lum:.2f}')
    empty = np.zeros_like(a)
    expect(dp.pixel_match(a, empty) == (0.0, 0.0), 'nothing to compare')


def test_tags():
    expect(dp.tag_refusal('creature walk, grey') is None, 'untagged row passes')
    expect(dp.tag_refusal('named character (do not use live), creature walk', True), 'named never')
    expect(dp.tag_refusal('do not use live: branded, item', True), 'branded never')
    expect(dp.tag_refusal('library only: retail-style art, creature walk'), 'library only refused by default')
    expect(dp.tag_refusal('library only: retail-style art, creature walk', True) is None, 'library only when allowed')


def test_edits():
    class T:
        flags = {'light': (2, 3)}
    f = dp.edit_flags(T(), [], 'player-disp')
    expect(f == {'light': (2, 3), 'displacement': (8, 8)}, f'player-disp: {f}')
    expect(T.flags == {'light': (2, 3)}, 'the donor flags are not changed')
    expect(dp.edit_flags(T(), [], '') == {'light': (2, 3)}, 'no edit')


def main():
    test_pixel_match()
    test_tags()
    test_edits()
    if FAILS:
        print(f'{len(FAILS)} failures')
        return 1
    print('donor_pick_test: all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
