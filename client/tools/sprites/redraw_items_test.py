#!/usr/bin/env python3
"""Tests of redraw_items.py on a small synthetic pair (no real pair needed).

python3 -I client/tools/sprites/redraw_items_test.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402
import redraw_items as R  # noqa: E402


def art(path, seed, alpha=255):
    rng = np.random.RandomState(seed)
    a = np.zeros((32, 32, 4), np.uint8)
    a[4:30, 3:29, :3] = rng.randint(1, 256, (26, 26, 3))
    a[4:30, 3:29, 3] = alpha
    Image.fromarray(a).save(path)
    return a


def test_redraw(c):
    dat, spr = c.pair(*t.good_parts())
    pa, pb = os.path.join(c.dir, 'a.png'), os.path.join(c.dir, 'b.png')
    art(pa, 1)
    art(pb, 2)
    out = os.path.join(c.dir, 'redrawn')
    # item 101 is animated (2 phases, light flag); item 100 is a still
    rc = R.main(['--dat', dat, '--spr', spr, '--out-dir', out, '--item', '101=' + pa, '--item', '100=' + pb])
    t.expect(rc == 0, 'redraw runs')
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    old = cp.parse_dat(open(dat, 'rb').read())[2]
    new = cp.parse_dat(open(od, 'rb').read())[2]
    t.expect(len(new['outfit']) == len(old['outfit']), 'outfits are still there')
    i101 = [x for x in new['item'] if x.id == 101][0]
    o101 = [x for x in old['item'] if x.id == 101][0]
    g = i101.groups[0]
    t.expect((g.w, g.h, g.phases, len(g.sprites)) == (1, 1, 1, 1), 'item 101 is a 1x1 still')
    t.expect(i101.flags == o101.flags, 'item 101 keeps its flag bytes (light)')
    t.expect(len(new['item']) == len(old['item']) and len(new['effect']) == len(old['effect']), 'same counts')
    t.expect(os.path.getsize(os_) > os.path.getsize(spr), 'two sprite records appended')
    r = cp.check(od, os_, auras={2}, old=(dat, spr), allow_changed=cp.parse_allow('item:100,101'))
    t.expect(r.ok, 'redrawn pair has no errors: ' + r.text())
    # again from the output: identical art is reused, nothing new is appended
    out2 = os.path.join(c.dir, 'redrawn2')
    R.main(['--dat', od, '--spr', os_, '--out-dir', out2, '--item', '101=' + pa, '--item', '100=' + pb])
    t.expect(os.path.getsize(os.path.join(out2, 'Tibia.spr')) == os.path.getsize(os_), 'same art is reused, spr does not grow')
    t.expect(open(os.path.join(out2, 'Tibia.dat'), 'rb').read() == open(od, 'rb').read(), 'second run: same dat')
    # deterministic
    out3 = os.path.join(c.dir, 'redrawn3')
    R.main(['--dat', dat, '--spr', spr, '--out-dir', out3, '--item', '101=' + pa, '--item', '100=' + pb])
    t.expect(open(os.path.join(out3, 'Tibia.spr'), 'rb').read() == open(os_, 'rb').read(), 'same inputs, same spr')


def atlas(path, rows):
    """an atlas of 32 px cells: rows = [[seed or None, ...]]; the same seed twice is the same cell"""
    a = np.zeros((32 * len(rows), 32 * len(rows[0]), 4), np.uint8)
    for r, row in enumerate(rows):
        for k, seed in enumerate(row):
            rng = np.random.RandomState(seed)
            a[r * 32 + 4:r * 32 + 30, k * 32 + 3:k * 32 + 29, :3] = rng.randint(1, 256, (26, 26, 3))
            a[r * 32 + 4:r * 32 + 30, k * 32 + 3:k * 32 + 29, 3] = 255
    Image.fromarray(a).save(path)
    return a


def test_strip(c):
    dat, spr = c.pair(*t.good_parts())
    at = os.path.join(c.dir, 'strip.png')
    atlas(at, [[11, 12], [13, 13]])
    out = os.path.join(c.dir, 'strip_out')
    # item 101 is animated (2 phases, light flag, the animator head and a duration table)
    rc = R.main(['--dat', dat, '--spr', spr, '--out-dir', out, '--strip', '101=%s@0' % at])
    t.expect(rc == 0, 'strip runs')
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    old = cp.parse_dat(open(dat, 'rb').read())[2]
    new = cp.parse_dat(open(od, 'rb').read())[2]
    o101 = [x for x in old['item'] if x.id == 101][0]
    n101 = [x for x in new['item'] if x.id == 101][0]
    go, gn = o101.groups[0], n101.groups[0]
    t.expect(n101.flags == o101.flags, 'strip keeps the flag bytes')
    t.expect((gn.w, gn.h, gn.layers, gn.px, gn.py, gn.pz, gn.phases, gn.anim, gn.exact) ==
             (go.w, go.h, go.layers, go.px, go.py, go.pz, go.phases, go.anim, go.exact), 'strip keeps the group and its durations')
    t.expect(len(gn.sprites) == 2 and gn.sprites != go.sprites and gn.sprites[0] != gn.sprites[1], 'two new sprites, one per phase')
    t.expect([x for x in new['item'] if x.id == 100][0].groups[0].sprites == [x for x in old['item'] if x.id == 100][0].groups[0].sprites,
             'the other item is untouched')
    r = cp.check(od, os_, auras={2}, old=(dat, spr), allow_changed=cp.parse_allow('item:101'))
    t.expect(r.ok, 'strip pair has no errors: ' + r.text())
    # identical cells share one sprite: one record for the two phases
    out2 = os.path.join(c.dir, 'strip_out2')
    R.main(['--dat', dat, '--spr', spr, '--out-dir', out2, '--strip', '101=%s@1' % at])
    n2 = [x for x in cp.parse_dat(open(os.path.join(out2, 'Tibia.dat'), 'rb').read())[2]['item'] if x.id == 101][0].groups[0]
    t.expect(n2.sprites[0] == n2.sprites[1], 'identical phases share a sprite')
    t.expect(os.path.getsize(os.path.join(out2, 'Tibia.spr')) < os.path.getsize(os_), 'one record appended for identical phases')
    # again from the output: nothing is appended, same dat
    out3 = os.path.join(c.dir, 'strip_out3')
    R.main(['--dat', od, '--spr', os_, '--out-dir', out3, '--strip', '101=%s@0' % at])
    t.expect(os.path.getsize(os.path.join(out3, 'Tibia.spr')) == os.path.getsize(os_), 'same strip is reused, spr does not grow')
    t.expect(open(os.path.join(out3, 'Tibia.dat'), 'rb').read() == open(od, 'rb').read(), 'second strip run: same dat')
    # a still and a strip in one run; deterministic
    pa = os.path.join(c.dir, 's.png')
    art(pa, 5)
    out4 = os.path.join(c.dir, 'strip_out4')
    R.main(['--dat', dat, '--spr', spr, '--out-dir', out4, '--strip', '101=%s@0' % at, '--item', '100=' + pa])
    out5 = os.path.join(c.dir, 'strip_out5')
    R.main(['--dat', dat, '--spr', spr, '--out-dir', out5, '--item', '100=' + pa, '--strip', '101=%s@0' % at])
    t.expect(open(os.path.join(out4, 'Tibia.spr'), 'rb').read() == open(os.path.join(out5, 'Tibia.spr'), 'rb').read(),
             'same inputs in any order, same spr')


def test_strip_refusals(c):
    dat, spr = c.pair(*t.good_parts())
    out = os.path.join(c.dir, 'strip_refuse')
    at = os.path.join(c.dir, 'r.png')
    atlas(at, [[21, 22], [23, 24], [25, 26]])
    semi = os.path.join(c.dir, 'rs.png')
    a = atlas(semi, [[31, 32]])
    a[:32, :32, 3] = 100
    Image.fromarray(a).save(semi)
    odd = os.path.join(c.dir, 'odd.png')
    Image.fromarray(np.zeros((40, 64, 4), np.uint8)).save(odd)
    blank = os.path.join(c.dir, 'blank.png')
    Image.fromarray(np.zeros((32, 64, 4), np.uint8)).save(blank)
    one = os.path.join(c.dir, 'one.png')
    atlas(one, [[41]])
    pa = os.path.join(c.dir, 'ra.png')
    art(pa, 4)
    cases = (('row out of the atlas', ['--strip', '101=%s@3' % at]),
             ('semi-transparent cell', ['--strip', '101=%s@0' % semi]),
             ('not a multiple of 32', ['--strip', '101=%s@0' % odd]),
             ('empty cell', ['--strip', '101=%s@0' % blank]),
             ('cells do not match the phases', ['--strip', '101=%s@0' % one]),
             ('a still item given a strip of 2', ['--strip', '100=%s@0' % at]),
             ('an outfit-less id', ['--strip', '9999=%s@0' % at]),
             ('item and strip both', ['--strip', '101=%s@0' % at, '--item', '101=' + pa]),
             ('bad spec', ['--strip', '101']),
             ('twice', ['--strip', '101=%s@0' % at, '--strip', '101=%s@1' % at]),
             ('nothing to do', []))
    for name, extra in cases:
        try:
            R.main(['--dat', dat, '--spr', spr, '--out-dir', out] + extra)
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass


def test_refusals(c):
    dat, spr = c.pair(*t.good_parts())
    out = os.path.join(c.dir, 'refuse')
    big = os.path.join(c.dir, 'big.png')
    Image.fromarray(np.zeros((64, 64, 4), np.uint8)).save(big)
    for name, spec in (('size', '100=' + big), ('missing item', '9999=' + os.path.join(c.dir, 'a.png'))):
        try:
            R.main(['--dat', dat, '--spr', spr, '--out-dir', out, '--item', spec])
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass
    semi = os.path.join(c.dir, 'semi.png')
    art(semi, 3, alpha=100)
    try:
        R.main(['--dat', dat, '--spr', spr, '--out-dir', out, '--item', '100=' + semi])
        t.expect(False, 'refused: semi-transparent')
    except SystemExit:
        pass
    try:
        R.parse_items(['100=a.png', '100=b.png'])
        t.expect(False, 'refused: item twice')
    except SystemExit:
        pass
    try:
        R.main(['--dat', dat, '--spr', spr, '--out-dir', os.path.dirname(dat), '--item', '100=' + semi])
        t.expect(False, 'refused: out-dir is the input dir')
    except SystemExit:
        pass


def main():
    c = t.Case()
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            fn(c)
    if t.FAILS:
        print('%d failed' % len(t.FAILS))
        return 1
    print('redraw_items_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
