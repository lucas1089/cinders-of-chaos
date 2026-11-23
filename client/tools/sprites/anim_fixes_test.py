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


def o734_parts():
    """effects: 1 four phases A A B A (100, 50, 80, 30 ms), 2 one tile with a solid block, 3 dim isolated dots and one bright
    isolated dot (two phases), 3 one tile with 10 pixels at alpha 20 and 20 at alpha 255 (two phases)"""
    solid = {y * 32 + x: BRIGHT for y in range(10, 20) for x in range(10, 20)}
    dots = {2 * 32 + 2: (40, 40, 40, 255), 2 * 32 + 6: (30, 30, 30, 255), 28 * 32 + 28: (50, 50, 50, 255),
            28 * 32 + 2: (250, 250, 250, 255)}
    faint = {**{i: (200, 100, 50, 20) for i in range(300, 310)}, **{i: (200, 100, 50, 255) for i in range(400, 420)}}
    mesh = {**solid, **{y * 32 + x: (90, 160, 230, 255) for y in range(22, 32) for x in range(0, 16) if (x + y) % 2 == 0}}
    recs = [t.record(solid), t.record({**solid, 0: BRIGHT}), t.record({**solid, **dots}), t.record(faint), t.record(px_block()),
            t.record(mesh)]
    e1 = t.entry(b'', [t.group([1, 1, 2, 1], phases=4, anim=(0, 0, 0, [100, 100, 50, 50, 80, 80, 30, 30]))])
    e2 = t.entry(b'', [t.group([3, 3], phases=2, anim=(0, 0, 0, [100] * 4))])
    e3 = t.entry(b'', [t.group([4, 4], phases=2, anim=(0, 0, 0, [100] * 4))])
    e4 = t.entry(b'', [t.group([6])])
    return recs, [t.entry(bytes([17]), [t.group([5])])], [], [e1, e2, e3, e4], []


def px_block():
    return {i: DARK for i in range(10)}


O734_ROWS = [
    ['effect', '1', 'merge', 'of=4;keep=0,2,3', 'test', 'n/a'],
    ['effect', '2', 'clear_strays', 'luma_max=100;expect=6', 'test', 'n/a'],
    ['effect', '3', 'drop_faint', 'below=40;expect=20', 'test', 'n/a'],
    ['effect', '4', 'demesh', 'expect=%d', 'test', 'n/a'],
]


def test_o734_ops(c):
    dat, spr = c.pair(*o734_parts())
    import clean_pack_dither as cpd
    mesh = int(cpd.mesh_mask(Spr(spr).sprite(6)).sum())
    t.expect(mesh >= 40, 'the synthetic checker is a mesh (%d pixels)' % mesh)
    rows = [r[:3] + [r[3] % mesh if '%d' in r[3] else r[3]] + r[4:] for r in O734_ROWS]
    out, text = run(c, rows, dat, spr, 'o734')
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    old = idt.parse_dat(open(dat, 'rb').read(), idt.OUR_KINDS)
    new = idt.parse_dat(open(od, 'rb').read(), idt.OUR_KINDS)
    g = new['effect'][0].groups[0]
    t.expect(g['phases'] == 3 and list(g['sprites']) == [1, 2, 1], 'merge: A A B A -> A B A, the same sprite ids')
    t.expect(g['anim'][1] == (150, 150, 80, 80, 30, 30), 'merge: the run lasts its total time (150 ms)')
    t.expect(sum(d[1] for d in AF.durations(g)) == sum(d[1] for d in AF.durations(old['effect'][0].groups[0])), 'merge keeps the total time')
    sp = Spr(os_)
    e2 = new['effect'][1].groups[0]
    a = sp.sprite(e2['sprites'][0])
    t.expect(int((a[..., 3] > 0).sum()) == 101 and a[28, 2, 3] > 0 and a[2, 2, 3] == 0, 'clear_strays: dim dots go, the bright one stays')
    t.expect(e2['sprites'][0] == e2['sprites'][1], 'clear_strays: both phases share the cleaned picture')
    b = sp.sprite(new['effect'][2].groups[0]['sprites'][0])
    t.expect(int((b[..., 3] > 0).sum()) == 20 and int(b[..., 3].min()) == 0 and int(b[b[..., 3] > 0][:, 3].min()) == 255,
             'drop_faint: the 10 pixels at alpha 20 go, alpha 255 stays')
    t.expect(new['effect'][2].groups[0]['phases'] == 2 and new['effect'][1].groups[0]['anim'] == old['effect'][1].groups[0]['anim'],
             'clear_strays and drop_faint keep phases and durations')
    m = sp.sprite(new['effect'][3].groups[0]['sprites'][0])
    t.expect(int((m[..., 3] > 0).sum()) == 100 + 80 - mesh and m[15, 15, 3] > 0, 'demesh: the checker goes, the solid block stays')
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:1,2,3,4'))
    t.expect(r.ok, 'check_pair append-only passes: ' + r.text())
    bad = {
        'demesh count': [['effect', '4', 'demesh', 'expect=%d' % (mesh + 1), 'x', 'x']],
        'merge keep': [['effect', '1', 'merge', 'of=4;keep=0,1,2,3', 'x', 'x']],
        'merge of': [['effect', '1', 'merge', 'of=5;keep=0,2,3', 'x', 'x']],
        'strays count': [['effect', '2', 'clear_strays', 'luma_max=100;expect=5', 'x', 'x']],
        'faint count': [['effect', '3', 'drop_faint', 'below=40;expect=21', 'x', 'x']],
        'faint bound': [['effect', '3', 'drop_faint', 'below=200;expect=20', 'x', 'x']],
    }
    for name, rows in bad.items():
        try:
            run(c, rows, dat, spr, 'refuse734')
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass
    try:
        run(c, rows[:1], od, os_, 'again734')
        t.expect(False, 'refused: a merge row cannot apply twice')
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
    print('anim_fixes_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
