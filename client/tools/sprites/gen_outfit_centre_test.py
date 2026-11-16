#!/usr/bin/env python3
"""Tests of gen_outfit_centre.py on a small synthetic pair (no real pair needed).

python3 -I client/tools/sprites/gen_outfit_centre_test.py
"""
import contextlib
import io
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_pair_test as t  # noqa: E402
import gen_foot_marks as FM  # noqa: E402
import gen_outfit_centre as OC  # noqa: E402
from datspr import Dat, Spr  # noqa: E402
from gen_info_lift import displacement  # noqa: E402

SKIN = (200, 150, 110, 255)
KINDS = {1: 'outfit', 2: 'class', 3: 'outfit', 4: 'monster', 5: 'outfit', 6: 'mount'}


def box(x0, x1, y0, y1, extra=()):
    """a record: a filled box (inclusive bounds) plus more boxes"""
    px = {}
    for a, b, c, d in ((x0, x1, y0, y1),) + tuple(extra):
        for y in range(c, d + 1):
            for x in range(a, b + 1):
                px[y * 32 + x] = SKIN
    return t.record(px)


def disp(x, y):
    return bytes([25]) + struct.pack('<hh', x, y)


def parts():
    """outfits: 1 a stock-like look on the target; 2 a class look up and left of it (the displacement runs out at 0:
    1 px goes into the pixels); 3 a 2x2 look down and right at displacement 0; 4 a monster off the target; 5 a look whose
    art fills its canvas to the right edge (no room for the pixels); 6 a mount."""
    recs = [box(20, 28, 8, 29),                      # 1: feet at tile 17, 21 at displacement 8
            box(10, 18, 4, 25),                      # 2
            box(22, 30, 8, 31),                      # 3 (bottom right cell of a 2x2)
            box(2, 10, 8, 29),                       # 4
            box(2, 31, 6, 25, ((2, 8, 26, 31),)),    # 5: wide body, legs at its left
            box(12, 20, 10, 31)]                     # 6
    items = [t.entry(bytes([17]), [t.group([1])])]
    outfits = [t.entry(disp(8, 8), [t.group([1] * 4, px=4, gtype=0)], outfit=True),
               t.entry(disp(8, 8), [t.group([2] * 4, px=4, gtype=0), t.group([2] * 8, px=4, phases=2, gtype=1)],
                       outfit=True),
               t.entry(b'', [t.group([3, 0, 0, 0] * 4, w=2, h=2, px=4, gtype=0)], outfit=True),
               t.entry(b'', [t.group([4] * 4, px=4, gtype=0)], outfit=True),
               t.entry(b'', [t.group([5] * 4, px=4, gtype=0)], outfit=True),
               t.entry(b'', [t.group([6] * 4, px=4, gtype=0)], outfit=True)]
    return recs, items, outfits, [], []


def quiet(fn, *a, **kw):
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*a, **kw)


def test_plan(c):
    room = lambda: (5, 5)   # noqa: E731
    P = OC.plan
    t.expect(P(1, 'outfit', (1, 1), (8, 8), (16.5, 20))[0] == 'keep', 'on the target: kept')
    t.expect(P(1, 'outfit', (1, 1), (8, 8), (18, 21.5))[0] == 'keep', 'inside the dead band: kept')
    t.expect(P(1, 'outfit', (2, 2), (8, 8), (13, 18)) == ('move', (5, 6), (0, 0), ''), 'up and left: less displacement')
    t.expect(P(1, 'class', (2, 2), (0, 0), (26.5, 30)) == ('move', (10, 10), (0, 0), ''), 'down right: more displacement')
    t.expect(P(1, 'outfit', (1, 1), (8, 8), (18.5, 20)) == ('move', (10, 8), (0, 0), ''), 'one axis only')
    t.expect(P(1, 'outfit', (2, 2), (8, 8), (6.5, 20), room) == ('move', (0, 8), (2, 0), ''), 'the rest goes to the pixels')
    t.expect(P(1, 'outfit', (2, 2), (0, 0), (5.5, 20), room) == ('move', (0, 0), (5, 0), 'short 6,0: no room in the canvas'),
             'no room: short')
    t.expect(P(1, 'outfit', (2, 2), (0, 0), (5.5, 20), lambda: (0, 0))[0] == 'keep', 'nothing can move: kept, with the note')
    t.expect(P(1, 'monster', (1, 1), (0, 0), (5, 5))[0] == 'report', 'a monster is listed')
    t.expect(P(1, 'mount', (2, 2), (0, 0), (5, 5))[0] == 'report', 'a mount is listed')
    t.expect(P(1, 'outfit', (3, 3), (0, 0), (5, 5))[0] == 'report', 'a big look is listed')
    t.expect(P(1, 'outfit', (2, 2), (-4, 0), (5, 5))[0] == 'report', 'a negative displacement is listed')
    t.expect(P(sorted(OC.FLOATING)[0], 'class', (2, 2), (0, 0), (5, 5))[0] == 'report', 'a floating look is listed')
    t.expect(OC.after_point((6.5, 20), (8, 8), (0, 8), (2, 0)) == (16.5, 20), 'the point after the move')
    t.expect(OC.standing([(10, 20), (12, 20), (30, 22), None]) == ((12, 20), (20, 2)), 'median of the directions')
    t.expect(OC.standing([None] * 4) is None, 'nothing visible')


def test_measure(c):
    dat, spr = c.pair(*parts())
    rows = quiet(OC.measure_rows, dat, spr, KINDS)
    by = {int(r['look']): r for r in rows}
    t.expect(len(rows) == 6, 'six looks measured')
    t.expect(by[1]['action'] == 'keep' and (by[1]['before_x'], by[1]['before_y']) == ('17', '21'), 'look 1 stands on the target')
    r = by[2]
    t.expect((r['action'], r['new_dx'], r['new_dy'], r['shift_x'], r['shift_y']) == ('move', '0', '5', '1', '0'),
             'look 2: displacement to 0 and 1 px in the pixels: %r' % r)
    t.expect((r['after_x'], r['after_y']) == ('16', '20'), 'look 2 lands on the target')
    r = by[3]
    t.expect((r['size'], r['action'], r['new_dx'], r['new_dy'], r['shift_x']) == ('2x2', 'move', '11', '11', '0'),
             'look 3: displacement only: %r' % r)
    t.expect(by[4]['action'] == 'report' and by[4]['new_dx'] == by[4]['old_dx'], 'the monster is listed, not moved')
    t.expect(by[5]['action'] == 'move' and by[5]['note'].startswith('short') and by[5]['shift_x'] == '0',
             'look 5 has no room: %r' % by[5])
    t.expect(by[6]['action'] == 'report', 'the mount is listed')
    t.expect(OC.csv_text(rows) == OC.csv_text(quiet(OC.measure_rows, dat, spr, KINDS)), 'the same table twice')
    return dat, spr, rows


def test_apply(c):
    dat, spr, rows = test_measure(c)
    table = os.path.join(c.dir, 'outfit_centre.csv')
    open(table, 'w', newline='').write(OC.csv_text(rows))
    t.expect(len(OC.check(dat, spr, table)) == 3, 'the pair before the move fails the check')
    out = os.path.join(c.dir, 'out')
    n, skipped, wrote = quiet(OC.apply, dat, spr, out, table)
    odat, ospr = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    t.expect((n, skipped, wrote) == (3, 0, True), 'three rows applied, a spr written')
    t.expect(OC.check(odat, ospr, table) == [], 'the built pair matches the table: %r' % OC.check(odat, ospr, table))
    old, new = Dat(dat), Dat(odat)
    d = [displacement(x) for x in new.outfits]
    t.expect(d == [(8, 8), (0, 5), (11, 11), (0, 0), (0, 7), (0, 0)], 'displacements: %r' % d)
    for i in (0, 3, 5):
        a, b = old.outfits[i], new.outfits[i]
        t.expect(old.data[a.raw[0]:a.raw[1]] == new.data[b.raw[0]:b.raw[1]], 'look %d byte-identical' % (i + 1))
    t.expect(new.outfits[2].sprites == old.outfits[2].sprites, 'look 3 keeps its sprites (displacement only)')
    s0, s1 = Spr(spr), Spr(ospr)
    a, b = s0.sprite(old.outfits[1].sprites[0]), s1.sprite(new.outfits[1].sprites[0])
    t.expect((b[:, 1:] == a[:, :-1]).all() and not b[:, :1].any(), 'look 2: every pixel 1 px to the right')
    walk = [g for g in OC.idt.parse_dat(new.data, OC.idt.OUR_KINDS)['outfit'][1].groups][1]
    t.expect(len(set(walk['sprites'])) == 1 and walk['sprites'][0] == new.outfits[1].sprites[0],
             'look 2: the walk group moved with the idle one')
    # the tables that store tile pixels move by the table's move
    kn = OC.knockon(rows)
    t.expect(kn == {2: (9, 3), 3: (-11, -11), 5: (0, -7)}, 'knock-on: %r' % kn)
    for look, (dx, dy) in kn.items():
        f0, f1 = FM.thing_feet(old.outfits[look - 1], s0), FM.thing_feet(new.outfits[look - 1], s1)
        t.expect([q - p for p, q in zip(f0, f1)] == [dx, dy] * 4, 'foot marks of look %d move by %d,%d' % (look, dx, dy))
    # idempotent: the built pair takes no row again, and measuring it moves nothing
    out2 = os.path.join(c.dir, 'out2')
    n, skipped, wrote = quiet(OC.apply, odat, ospr, out2, table)
    t.expect((n, skipped, wrote) == (0, 3, False), 'a second apply changes nothing')
    t.expect(open(os.path.join(out2, 'Tibia.dat'), 'rb').read() == open(odat, 'rb').read(), 'the same dat again')
    again = quiet(OC.measure_rows, odat, ospr, KINDS)
    t.expect([r['action'] for r in again].count('move') == 0, 'measuring the built pair moves nothing')
    # a look that is neither before nor after its row is refused
    bad = [dict(r) for r in rows]
    bad[1]['old_dx'] = '3'
    open(table, 'w', newline='').write(OC.csv_text(bad))
    try:
        quiet(OC.apply, dat, spr, os.path.join(c.dir, 'out3'), table)
        t.expect(False, 'a stale row is refused')
    except SystemExit as e:
        t.expect('neither before nor after' in str(e), 'a stale row is refused')


def test_repo_table(c):
    """the committed table: columns, actions, the rule on every row"""
    rows = OC.read_csv(OC.CSV)
    t.expect(len(rows) > 2500, 'the table has the pair\'s looks')
    kinds = OC.repo_kinds()
    for r in rows:
        look, size = int(r['look']), tuple(int(v) for v in r['size'].split('x'))
        old, new, shift = OC.num(r, 'old_dx', 'old_dy'), OC.num(r, 'new_dx', 'new_dy'), OC.num(r, 'shift_x', 'shift_y')
        before, after = OC.num(r, 'before_x', 'before_y'), OC.num(r, 'after_x', 'after_y')
        t.expect(r['kind'] == kinds.get(look, 'other'), 'look %d: kind' % look)
        t.expect(after == OC.after_point(before, old, new, shift), 'look %d: after = before moved' % look)
        if r['action'] == 'move':
            t.expect(r['kind'] in OC.KINDS_MOVED and size in OC.SIZES and min(old + new + shift) >= 0
                     and look not in OC.FLOATING, 'look %d: only small player bodies move' % look)
            got = OC.plan(look, r['kind'], size, old, before, lambda: shift)
            t.expect(got[:3] == ('move', new, shift) or r['note'].startswith('short'), 'look %d: the rule' % look)
            if not r['note'].startswith('short'):
                t.expect(abs(after[0] - OC.TARGET[0]) <= 0.5 and abs(after[1] - OC.TARGET[1]) <= 0.5,
                         'look %d lands on the target' % look)
        else:
            t.expect(new == old and shift == (0, 0), 'look %d: not moved' % look)


def main():
    c = t.Case()
    for fn in (test_plan, test_apply, test_repo_table):
        fn(c)
    if t.FAILS:
        sys.exit(1)
    print('gen_outfit_centre_test: ok')


if __name__ == '__main__':
    main()
