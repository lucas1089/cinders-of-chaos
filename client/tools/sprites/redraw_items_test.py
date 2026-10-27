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
