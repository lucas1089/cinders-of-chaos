#!/usr/bin/env python3
"""Tests of anim_fixes.py on a small synthetic pair (no real pair needed).

python3 -I client/tools/sprites/anim_fixes_test.py
"""
import contextlib
import csv
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402
import anim_fixes as AF  # noqa: E402
import import_donor_things as idt  # noqa: E402
from datspr import Spr  # noqa: E402

BRIGHT = (230, 200, 120, 255)
DARK = (20, 16, 40, 255)


def parts():
    """items: 100 a still. effects: 1 six phases (2, 40, 100, 100, 50, 0 pixels), 2 two grey pixel fields.
    outfits: 1 a one-frame look of dark pixels with bright ones, 2 a look unrelated to the table."""
    def px(n, col, off=0):
        return {off + i: col for i in range(n)}
    recs = [t.record(px(2, BRIGHT)), t.record(px(40, BRIGHT)), t.record(px(100, BRIGHT)), t.record(px(100, BRIGHT, 200)),
            t.record(px(50, BRIGHT)), None,
            t.record({**px(60, DARK), **px(20, BRIGHT, 100)}),
            t.record({**px(90, (129, 129, 129, 255)), 500: BRIGHT, 700: BRIGHT}),
            t.record(px(5, BRIGHT))]
    items = [t.entry(bytes([17]), [t.group([9])])]
    e1 = t.entry(b'', [t.group([1, 2, 3, 4, 5, 6], phases=6, anim=(0, 0, 0, [83, 83, 70, 70, 60, 60, 60, 60, 90, 90, 50, 50]))])
    e2 = t.entry(b'', [t.group([8, 8, 8, 8], phases=4, anim=(0, 0, 0, [100] * 8))])
    o1 = t.entry(b'', [t.group([7], px=1, gtype=0)], outfit=True)
    o2 = t.entry(bytes([25]) + b'\x08\x00\x08\x00', [t.group([9, 9, 9, 9], px=4, gtype=0)], outfit=True)
    return recs, items, [o1, o2], [e1, e2], []


def spec(path, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(AF.SPEC_COLS)
        w.writerows(rows)


ROWS = [
    ['effect', '1', 'trim', 'share=0.1;floor=4;of=6;keep=1-5', 'test', 'n/a'],
    ['effect', '2', 'clear_color', 'frame=1;rgb=129,129,129;expect=90', 'test', 'n/a'],
    ['outfit', '1', 'lift', 'k=0.5;vmid_min=60', 'test', 'n/a'],
    ['outfit', '1', 'pulse', 'n=4;amp=0.5;ms=200', 'test', 'n/a'],
    ['outfit', '2', 'displacement', '3,-4', 'test', 'n/a'],
]


def run(c, rows, dat, spr, name, extra=()):
    sp = os.path.join(c.dir, name + '.csv')
    spec(sp, rows)
    out = os.path.join(c.dir, name)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        AF.main(['--ours-dat', dat, '--ours-spr', spr, '--out-dir', out, '--spec', sp,
                 '--changes-out', os.path.join(c.dir, name + '_changes.csv')] + list(extra))
    return out, buf.getvalue()


def test_apply(c):
    dat, spr = c.pair(*parts())
    out, text = run(c, ROWS, dat, spr, 'out1')
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    old = idt.parse_dat(open(dat, 'rb').read(), idt.OUR_KINDS)
    new = idt.parse_dat(open(od, 'rb').read(), idt.OUR_KINDS)
    e1 = new['effect'][0].groups[0]
    t.expect(e1['phases'] == 4 and len(e1['sprites']) == 4, 'trim leaves phases 1-4')
    t.expect(list(e1['sprites']) == list(old['effect'][0].groups[0]['sprites'][1:5]), 'trim keeps the sprite ids')
    t.expect(e1['anim'][1] == (70, 70, 60, 60, 60, 60, 90, 90), 'kept phases keep their durations')
    sp = Spr(os_)
    e2 = new['effect'][1].groups[0]
    gone = sp.sprite(e2['sprites'][1])
    t.expect((gone[..., 3] > 0).sum() == 2 and not ((gone[..., :3] == 129).all(axis=-1) & (gone[..., 3] > 0)).any(),
             'clear_color removes the grey pixels of frame 1 only')
    t.expect(sp.sprite(e2['sprites'][0])[..., 3].sum() > 0 and e2['sprites'][0] == old['effect'][1].groups[0]['sprites'][0],
             'other frames of the effect keep their sprite')
    o1 = new['outfit'][0]
    g = o1.groups[0]
    t.expect(g['phases'] == 4 and len(g['sprites']) == 4, 'pulse makes 4 phases')
    t.expect(any(b == AF.ANIMATE_ALWAYS_BYTE for b, _ in o1.flags), 'pulse sets animateAlways')
    first, peak = sp.sprite(g['sprites'][0]), sp.sprite(g['sprites'][2])
    t.expect(g['sprites'][0] != g['sprites'][2] and g['anim'][1] == (200,) * 8, 'pulse phases differ, 200 ms each')
    t.expect(int(peak[..., :3].max()) >= int(first[..., :3].max()), 'pulse peak is not darker than the still')
    lifted = (first[..., 3] > 0) & (first[..., :3].max(axis=-1) > 40)
    t.expect(lifted.any(), 'lift raised dark pixels')
    t.expect(new['outfit'][1].flags == [(25, b'\x03\x00\xfc\xff')], 'displacement sets the attribute')
    t.expect(out and 'things not in the table, byte-identical' in text and 'verified' in text, 'prints the counts and verifies')
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:1,2;outfit:1,2'))
    t.expect(r.ok, 'check_pair append-only passes: ' + r.text())
    t.expect(os.path.getsize(os.path.join(c.dir, 'out1_changes.csv')) > 0, 'changes csv written')
    # every other thing is byte-identical: item 100
    t.expect(new['item'][0].raw[1] - new['item'][0].raw[0] == old['item'][0].raw[1] - old['item'][0].raw[0], 'item untouched')


def test_deterministic(c):
    dat, spr = c.pair(*parts())
    a, _ = run(c, ROWS, dat, spr, 'det1')
    b, _ = run(c, ROWS, dat, spr, 'det2')
    for f in ('Tibia.dat', 'Tibia.spr'):
        t.expect(open(os.path.join(a, f), 'rb').read() == open(os.path.join(b, f), 'rb').read(), 'same input, same ' + f)


def test_refusals(c):
    dat, spr = c.pair(*parts())
    bad = {
        'wrong keep': [['effect', '1', 'trim', 'share=0.1;floor=4;of=6;keep=0-6', 'x', 'x']],
        'wrong of': [['effect', '1', 'trim', 'share=0.1;floor=4;of=7;keep=1-5', 'x', 'x']],
        'wrong count': [['effect', '2', 'clear_color', 'frame=1;rgb=129,129,129;expect=89', 'x', 'x']],
        'missing thing': [['effect', '99', 'trim', 'share=0.1;floor=4;of=6;keep=1-5', 'x', 'x']],
        'unknown op': [['effect', '1', 'wobble', '', 'x', 'x']],
        'pulse on animated': [['effect', '1', 'pulse', 'n=4;amp=0.5;ms=100', 'x', 'x']],
    }
    for name, rows in bad.items():
        try:
            run(c, rows, dat, spr, 'refuse')
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass
    try:
        AF.main(['--ours-dat', dat, '--ours-spr', spr, '--out-dir', os.path.dirname(dat)])
        t.expect(False, 'refused: out-dir is the input dir')
    except SystemExit:
        pass
    try:
        run(c, ROWS[:1], dat, spr, 'refuse', ['--expect-dat-md5', '0' * 32])
        t.expect(False, 'refused: wrong input md5')
    except SystemExit:
        pass


def test_floor_and_rule(c):
    t.expect(AF.trim_range([2, 40, 100, 100, 50, 0], 0.1, 4) == (1, 5), 'trim rule: both ends')
    t.expect(AF.trim_range([0, 0, 0, 0, 0, 5], 0.1, 4) == (2, 6), 'trim rule: floor of 4 frames')
    t.expect(AF.trim_range([5, 5, 5, 5], 0.5, 4) == (0, 4), 'trim rule: never below the floor')


def main():
    c = t.Case()
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            fn(c)
    if t.FAILS:
        print('%d failed' % len(t.FAILS))
        return 1
    print('anim_fixes_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
