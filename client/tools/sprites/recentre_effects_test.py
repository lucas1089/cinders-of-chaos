#!/usr/bin/env python3
"""Tests of recentre_effects.py on a small synthetic pair (no real pair needed).

python3 -I client/tools/sprites/recentre_effects_test.py
"""
import contextlib
import csv
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402
import recentre_effects as RE  # noqa: E402
import import_donor_things as idt  # noqa: E402
from datspr import Spr  # noqa: E402

COL = (180, 90, 220, 255)


def block(x0, y0, x1, y1):
    """pixels {index: colour} of a rectangle of a 32 x 32 tile"""
    return {y * 32 + x: COL for y in range(y0, y1) for x in range(x0, x1)}


def parts(low=False, edge=False):
    """effects: 1 a 2x2 canvas of 2 phases whose art stands off centre (low: art at the canvas' bottom right, 8 px off),
    2 a one tile effect unrelated to the table. Tile order of a 2x2 canvas is (ww, hh): sprite i = ww + 2 * hh, ww 0 = right."""
    recs = [t.record(block(20, 20, 32, 32)),             # 1  the art of the bottom right tile, 12 px square
            t.record(block(0, 0, 4, 4)),                 # 2  a blob at the top left of another tile
            t.record(block(10, 10, 14, 14)),             # 3  a blob of the unrelated effect
            t.record(block(26, 26, 32, 32) if edge else block(0, 0, 4, 4))]    # 4  the art of phase 2
    # phase 0: tile (ww 0, hh 0) = the bottom right = record 1; the others empty. phase 1: same with record 4
    e1 = t.entry(b'', [t.group([1, 0, 0, 0, 4, 0, 0, 0], w=2, h=2, phases=2, anim=(0, 0, 0, [83] * 4))])
    e2 = t.entry(b'', [t.group([3])])
    return recs, [t.entry(bytes([17]), [t.group([3])])], [t.entry(b'', [t.group([3], gtype=0)], outfit=True)], [e1, e2], []


def centre_of(dat, spr, eid):
    d = open(dat, 'rb').read()
    things = idt.parse_dat(d, idt.OUR_KINDS)
    store = RE.AF.Store(Spr(spr))
    g = RE.AF.TS(things['effect'][eid - 1]).groups[0]
    return RE.centre(RE.canvases(store, g), g['w'], g['h'])


def spec(c, name, shift, of, to):
    p = os.path.join(c.dir, name + '.csv')
    with open(p, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['kind', 'id', 'shift', 'of', 'to', 'reason'])
        w.writerow(['effect', '1', shift, of, to, 'test'])
    return p


def build(c, dat, spr, sp, name):
    out = os.path.join(c.dir, name)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        RE.build(dat, spr, out, sp)
    return out, buf.getvalue()


def test_apply(c):
    dat, spr = c.pair(*parts())
    cx, cy = centre_of(dat, spr, 1)
    t.expect(cx > 10 and cy > 10, 'the synthetic art stands off centre (got %.2f, %.2f)' % (cx, cy))
    sp = spec(c, 'ok', '-8,-8', '%.2f,%.2f' % (cx, cy), '%.2f,%.2f' % (cx - 8, cy - 8))
    out, text = build(c, dat, spr, sp, 'out1')
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    nx, ny = centre_of(od, os_, 1)
    t.expect(abs(nx - (cx - 8)) < 0.01 and abs(ny - (cy - 8)) < 0.01, 'the centre moved by exactly the shift')
    t.expect('sprite records appended' in text and 'verified' in text, 'prints the counts and verifies')
    old = idt.parse_dat(open(dat, 'rb').read(), idt.OUR_KINDS)
    new = idt.parse_dat(open(od, 'rb').read(), idt.OUR_KINDS)
    t.expect(new['effect'][1].groups[0]['sprites'] == old['effect'][1].groups[0]['sprites'], 'the other effect keeps its sprites')
    og, ng = old['effect'][0].groups[0], new['effect'][0].groups[0]
    t.expect(ng['phases'] == 2 and ng['anim'] == og['anim'] and (ng['w'], ng['h']) == (2, 2), 'size, phases and durations stay')
    sp0, sp1 = Spr(spr), Spr(os_)
    t.expect(sp1.count > sp0.count and all(s > sp0.count for s in ng['sprites'] if s != 0 and s not in og['sprites']),
             'new pictures are records after the last id')
    t.expect(all(sp1.sprite(i) is None and sp0.sprite(i) is None or (sp1.sprite(i) == sp0.sprite(i)).all()
                 for i in range(1, sp0.count + 1)), 'old sprites unchanged')
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:1'))
    t.expect(r.ok, 'check_pair append-only passes: ' + r.text())
    t.expect(RE.check(od, os_, sp, log=lambda *_: None) == 0, 'check passes on the built pair')
    t.expect(RE.check(dat, spr, sp, log=lambda *_: None) == 1, 'check fails on the input pair')
    return out, sp


def test_idempotent(c):
    dat, spr = c.pair(*parts())
    cx, cy = centre_of(dat, spr, 1)
    sp = spec(c, 'idem', '-8,-8', '%.2f,%.2f' % (cx, cy), '%.2f,%.2f' % (cx - 8, cy - 8))
    out, _ = build(c, dat, spr, sp, 'idem1')
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    again, text = build(c, od, os_, sp, 'idem2')
    t.expect(not os.path.exists(again) and 'nothing to do' in text and 'done already' in text, 'a second run writes nothing')
    a, _ = build(c, dat, spr, sp, 'idem3')
    for f in ('Tibia.dat', 'Tibia.spr'):
        t.expect(open(os.path.join(out, f), 'rb').read() == open(os.path.join(a, f), 'rb').read(), 'same input, same ' + f)


def test_refusals(c):
    dat, spr = c.pair(*parts())
    cx, cy = centre_of(dat, spr, 1)
    of, to = '%.2f,%.2f' % (cx, cy), '%.2f,%.2f' % (cx - 8, cy - 8)
    bad = {
        'wrong premise': spec(c, 'b1', '-8,-8', '9.00,9.00', '1.00,1.00'),
        'to is not of + shift': spec(c, 'b2', '-8,-8', of, '0.00,0.00'),
        'cut at the edge': spec(c, 'b3', '9,0', of, '%.2f,%.2f' % (cx + 9, cy)),
    }
    for name, sp in bad.items():
        try:
            build(c, dat, spr, sp, 'refuse')
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass
    d2, s2 = c.pair(*parts(edge=True))
    try:
        cx2, cy2 = centre_of(d2, s2, 1)
        build(c, d2, s2, spec(c, 'b4', '3,3', '%.2f,%.2f' % (cx2, cy2), '%.2f,%.2f' % (cx2 + 3, cy2 + 3)), 'refuse2')
        t.expect(False, 'refused: art would be cut off')
    except SystemExit:
        pass
    try:
        build(c, dat, spr, spec(c, 'b5', '-8,-8', of, to), os.path.dirname(dat))
        t.expect(False, 'refused: out-dir is the input dir')
    except SystemExit:
        pass
    try:
        RE.read_spec(spec(c, 'b6', '-8,-8', of, to).replace('b6', 'missing'))
        t.expect(False, 'refused: no spec file')
    except (SystemExit, OSError):
        pass


def test_committed_table(c):
    rows = RE.read_spec(RE.SPEC)
    old = [r for r in rows if r['pair'] == 80]
    t.expect([r['id'] for r in old] == [3036], 'the pair 80 row is effect 3036')
    t.expect(all(r['dx'] == -6 and r['dy'] == -6 for r in old), 'the shift of 3036 is -6, -6')
    t.expect(all(max(abs(r['to'][0]), abs(r['to'][1])) <= 4 for r in old), 'the centre after is inside the 4 px of gen_area_fx.CENTRE_TOL')
    new = [r for r in rows if r['pair'] == 82]
    t.expect(len(new) == 25 and len({r['id'] for r in new}) == 25, 'O734: 25 rows of pair 82, one per effect')
    t.expect(all(r['pair'] in (80, 82) for r in rows), 'rows of pair 80 and 82 only')


def test_pending(c):
    """a row of a later pair is pending while windows-assets is older; a row due fails until done"""
    dat, spr = c.pair(*parts())
    cx, cy = centre_of(dat, spr, 1)
    p = os.path.join(c.dir, 'pend.csv')
    with open(p, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['kind', 'id', 'shift', 'of', 'to', 'pair', 'reason'])
        w.writerow(['effect', '1', '-8,-8', '%.2f,%.2f' % (cx, cy), '%.2f,%.2f' % (cx - 8, cy - 8), '82', 'test'])
    q = lambda *_: None  # noqa: E731
    t.expect(RE.check(dat, spr, p, log=q, assets=81, fixed=set()) == 0, 'pending while windows-assets has pair 81')
    t.expect(RE.check(dat, spr, p, log=q, assets=82, fixed=set()) == 1, 'due at pair 82')
    t.expect(RE.check(dat, spr, p, log=q, assets=82, fixed={('effect', 1)}) == 0, 'the fixed form of fix_pack_fx.py passes')
    out, text = build(c, dat, spr, p, 'pend_out')
    t.expect('built by fix_pack_fx.py' in text and not os.path.exists(out), 'build skips a row of a later pair')


def main():
    c = t.Case()
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            fn(c)
    if t.FAILS:
        print('%d failed' % len(t.FAILS))
        return 1
    print('recentre_effects_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
