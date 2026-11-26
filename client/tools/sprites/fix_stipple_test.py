#!/usr/bin/env python3
"""Tests of fix_stipple.py and the unstipple op of anim_fixes.py on a small synthetic pair (no real pair needed), and of the
committed table (O769).

python3 -I client/tools/sprites/fix_stipple_test.py
"""
import contextlib
import csv
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
import anim_fixes as AF  # noqa: E402
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402
import fix_pack_fx as FX  # noqa: E402
import fix_stipple as FS  # noqa: E402
import import_donor_things as idt  # noqa: E402

BODY = (200, 90, 220, 255)
EDGE = (120, 40, 140, 255)
DIM = (40, 20, 50, 255)
SPARK = (255, 250, 230, 255)


def bayer34(x, y):
    """the 3/4 Bayer stage of a glow: holes every other pixel of every other row"""
    return (x % 2, y % 2) != (1, 1)


def body(cond, col=BODY):
    return {y * 32 + x: col for y in range(4, 28) for x in range(4, 28) if cond(x, y)}


def parts():
    """effects: 1 a body with the 3/4 Bayer stipple and a dim dotted fringe (listed); 2 a solid body with one drawn hole and bright
    sparks two apart (not listed); 3 a checker of two colours' art over a solid ring (listed); 4 the same body with soft alpha
    (never touched); 5 untouched solid"""
    s1 = body(bayer34)
    for x in range(0, 32, 2):                                   # a dim lattice fringe on rows 0 and 2, under the body
        s1[0 * 32 + x] = DIM
        s1[2 * 32 + x] = DIM
    s2 = body(lambda x, y: (x, y) != (15, 15))
    for x in range(0, 32, 4):
        s2[1 * 32 + x] = SPARK
        s2[1 * 32 + x + 2] = SPARK if x + 2 < 32 else SPARK
    s3 = body(lambda x, y: (x + y) % 2 == 0 or x in (4, 27) or y in (4, 27), BODY)
    for k, v in list(s3.items()):
        x, y = k % 32, k // 32
        if x in (4, 27) or y in (4, 27):
            s3[k] = EDGE
    s4 = {k: (v[0], v[1], v[2], 200) for k, v in body(bayer34).items()}
    s5 = body(lambda x, y: True)
    recs = [t.record(s1), t.record(s2), t.record(s3), t.record(s4), t.record(s5)]
    ms = [80, 80] * 2
    effects = [t.entry(b'', [t.group([1, 1], phases=2, anim=(0, 0, 0, ms))]),
               t.entry(b'', [t.group([2, 2], phases=2, anim=(0, 0, 0, ms))]),
               t.entry(b'', [t.group([3, 5], phases=2, anim=(0, 0, 0, ms))]),
               t.entry(b'', [t.group([4, 4], phases=2, anim=(0, 0, 0, ms))]),
               t.entry(b'', [t.group([5])])]
    return recs, [t.entry(bytes([17]), [t.group([1])])], [t.entry(b'', [t.group([1], gtype=0)], outfit=True)], effects, []


def quiet(fn, *a, **kw):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        r = fn(*a, log=print, **kw)
    return r, buf.getvalue()


def canvas(pixels):
    img = np.zeros((32, 32, 4), np.uint8)
    for k, v in pixels.items():
        img[k // 32, k % 32] = v
    return img


def test_rule():
    img = canvas(body(bayer34))
    new, f, d = FS.redraw(img)
    holes = sum(1 for y in range(5, 27) for x in range(5, 27) if not bayer34(x, y))
    t.expect(f == holes and d == 0, 'the 3/4 Bayer holes inside the body are filled: %d of %d' % (f, holes))
    t.expect((new[5:27, 5:27, 3] == 255).all() and (new[5:27, 5:27, :3] == BODY[:3]).all(), 'the body is one solid colour')
    t.expect(FS.masks(new)[0].sum() == 0, 'nothing left to fill')
    one = canvas(body(lambda x, y: (x, y) != (15, 15)))
    t.expect(FS.redraw(one)[1] == 0, 'a lone drawn hole (no partner on the grid) stays')
    chk = canvas(body(lambda x, y: (x + y) % 2 == 0))
    new, f, _d = FS.redraw(chk)
    t.expect(f > 200 and (new[6:26, 6:26, 3] == 255).all(), 'a 50%% checker becomes solid (%d filled)' % f)
    fr = canvas(body(lambda x, y: True))
    for x in range(0, 32, 2):
        fr[0, x] = DIM
        fr[2, x] = DIM
        fr[1, x] = SPARK if x % 4 == 0 else (0, 0, 0, 0)
    fr[1] = 0
    _n, _f, d = FS.redraw(fr)
    t.expect(d == 32, 'the dim lattice dots of a fringe go: %d' % d)
    sp = canvas(body(lambda x, y: True))
    for x in range(0, 32, 2):
        sp[1, x] = SPARK
    t.expect(FS.redraw(sp)[2] == 0, 'bright lattice dots are sparks and stay')
    line = canvas({})
    for i in range(4, 28):
        line[i, i] = BODY
    t.expect(FS.redraw(line)[1:] == (0, 0), 'a one pixel diagonal line stays')
    two = canvas(body(lambda x, y: True))
    two[10, 10] = two[10, 12] = 0
    two[9, 11] = two[11, 11] = (10, 200, 10, 255)
    two[10, 11] = (10, 200, 10, 255)
    _n, f, _d = FS.redraw(two)
    t.expect(f == 2, 'two holes two apart are a grid: filled')
    mix = canvas(body(lambda x, y: True))
    mix[10, 11] = 0
    mix[10, 13] = 0
    mix[9, 11] = (10, 200, 10, 255)
    out = FS.redraw(mix)[0]
    t.expect(tuple(out[10, 11, :3]) == BODY[:3], 'the fill takes the colour most sides share: %r' % (tuple(out[10, 11]),))


def test_scan_build_check(c):
    dat, spr = c.pair(*parts())
    rows, text = quiet(FS.scan, dat, spr)
    t.expect([r['id'] for r in rows] == [1, 3], 'scan lists effects 1 and 3: %r %s' % ([r['id'] for r in rows], text))
    t.expect('1 soft alpha' in text, 'the soft alpha effect is skipped: %s' % text)
    tab = os.path.join(c.dir, 'stipple.csv')
    FS.write_table(rows, tab)
    sums = os.path.join(c.dir, 'stipple.sums')
    got, text = quiet(FS.build, dat, spr, None, dry_run=True, write=True, table=tab, sums_path=sums)
    t.expect(len(got) == 2 and 'O769' in open(sums).read().splitlines()[0], 'the dry run writes the sums')
    out = os.path.join(c.dir, 'out')
    got2, text = quiet(FS.build, dat, spr, out, table=tab, sums_path=sums)
    t.expect(got2 == got and 'verified' in text and '2 things redrawn' in text, 'build verifies: %s' % text)
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    new = idt.parse_dat(open(od, 'rb').read(), idt.OUR_KINDS)
    old = idt.parse_dat(open(dat, 'rb').read(), idt.OUR_KINDS)
    for i in range(5):
        gn, go = new['effect'][i].groups[0], old['effect'][i].groups[0]
        t.expect(gn['phases'] == go['phases'] and gn['anim'] == go['anim'], 'effect %d keeps its frames and timing' % (i + 1))
    t.expect(new['effect'][1].raw and open(od, 'rb').read()[new['effect'][1].raw[0]:new['effect'][1].raw[1]]
             == open(dat, 'rb').read()[old['effect'][1].raw[0]:old['effect'][1].raw[1]], 'effect 2 is byte for byte the same')
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:1,3'))
    t.expect(r.ok, 'check_pair append-only passes: ' + r.text())
    rows2, _ = quiet(FS.scan, od, os_)
    t.expect(rows2 == [], 'a scan of the built pair lists nothing')
    t.expect(quiet(FS.check, od, os_, assets=87, sums_path=sums)[0] == 0, 'check: the built pair is redrawn')
    r87, text = quiet(FS.check, dat, spr, assets=87, sums_path=sums)
    t.expect(r87 == 0 and 'pending' in text, 'check: the input pair is pending while windows-assets has pair 87')
    t.expect(quiet(FS.check, dat, spr, assets=88, sums_path=sums)[0] == 1, 'check: the input pair fails once pair 88 is due')
    _, text = quiet(FS.build, od, os_, os.path.join(c.dir, 'out2'), table=tab, sums_path=sums)
    t.expect('nothing to do' in text and not os.path.exists(os.path.join(c.dir, 'out2')), 'a second run writes nothing')
    # fix_pack_fx: a thing in its fixed form whose stipple was redrawn later still counts as fixed
    b, a = FX.read_sums(sums)[('effect', 1)]
    pack = os.path.join(c.dir, 'pack.sums')
    with open(pack, 'w') as f:
        f.write('# test\neffect 1 000000000000000000000000 %s\n' % b)
    FX._FORMS.clear()
    real = FX.stipple_sums
    try:
        FX.stipple_sums = lambda: FX.read_sums(sums)
        t.expect(FX.forms(od, os_, FX.read_sums(pack))[('effect', 1)] == 'after', 'fix_pack_fx: the redrawn form of its fixed form is fixed')
        t.expect(FX.forms(od, os_, FX.read_sums(pack), stipple=False)[('effect', 1)] is None, 'fix_pack_fx without stipple: own forms only')
    finally:
        FX.stipple_sums = real
        FX._FORMS.clear()
    # refusals
    bad = os.path.join(c.dir, 'bad.csv')
    for name, row in (('another count', ['effect', 1, 'unstipple', 'fill=1;drop=0', 'test', '']),
                      ('nothing to fill', ['effect', 2, 'unstipple', 'fill=0;drop=0', 'test', '']),
                      ('another op', ['effect', 1, 'trim', 'of=2;keep=0-2', 'test', ''])):
        with open(bad, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f, lineterminator='\n')
            w.writerow(AF.SPEC_COLS)
            w.writerow(row)
        try:
            quiet(FS.build, dat, spr, None, dry_run=True, table=bad, sums_path=os.path.join(c.dir, 'bad.sums'))
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass
    try:
        quiet(FS.build, dat, spr, os.path.dirname(dat), table=tab, sums_path=sums)
        t.expect(False, 'refused: out-dir is the input dir')
    except SystemExit:
        pass


def test_committed_table():
    rows = AF.read_spec(FS.TABLE)
    sums = FX.read_sums(FS.SUMS)
    keys = sorted({(r['kind'], r['id']) for r in rows})
    t.expect(len(rows) == len(keys) and len(rows) > 100, 'the table: one row a thing (%d)' % len(rows))
    t.expect(all(r['op'] == 'unstipple' and r['kind'] in ('effect', 'missile') for r in rows), 'unstipple rows of effects and missiles')
    t.expect(sorted(sums) == keys and all(b != a for b, a in sums.values()), 'the sums name every row, each changes')
    extra = FS.owned_extra()
    t.expect(not any(FS.owned(k, i) or (k, i) in extra for k, i in keys), 'no row names a thing another tool holds')
    for r in rows:
        a = AF.args_of(r['args'])
        t.expect(int(a['fill']) >= FS.MIN_FILL, '%s %d: at least MIN_FILL filled' % (r['kind'], r['id']))
    pack = FX.read_sums()
    import fix_dissolve_tail as FD
    tail = FX.read_sums(FD.SUMS)
    for k in keys:
        if k in tail:
            t.expect(sums[k][0] == tail[k][1], '%s %d: redrawn from its tail cut form' % k)
        elif k in pack:
            t.expect(sums[k][0] == pack[k][1], '%s %d: redrawn from its fixed form' % k)
    sys.path.insert(0, os.path.join(FS.HERE, '..', '..', '..', 'server', 'tools'))
    import client_pair
    t.expect(client_pair.PAIR_STIPPLE == FS.PAIR == 88, 'client_pair.PAIR_STIPPLE is the pair of the redraw')


def main():
    c = t.Case()
    test_rule()
    test_scan_build_check(c)
    test_committed_table()
    if t.FAILS:
        print('%d failed' % len(t.FAILS))
        return 1
    print('fix_stipple_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
