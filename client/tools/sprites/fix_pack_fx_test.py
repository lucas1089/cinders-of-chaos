#!/usr/bin/env python3
"""Tests of fix_pack_fx.py on a small synthetic pair (no real pair needed), and of its committed tables.

python3 -I client/tools/sprites/fix_pack_fx_test.py
"""
import contextlib
import csv
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402
import fix_pack_fx as FX  # noqa: E402
import import_donor_things as idt  # noqa: E402
from datspr import Spr  # noqa: E402

COL = (90, 160, 230, 255)


def rect(x0, y0, x1, y1, col=COL):
    return {y * 32 + x: col for y in range(y0, y1) for x in range(x0, x1)}


def checker(x0, y0, x1, y1, col=COL):
    return {y * 32 + x: col for y in range(y0, y1) for x in range(x0, x1) if (x + y) % 2 == 0}


def parts():
    """effects: 1 a solid frame then a frame with a checker dissolve (dissolve table), 2 a 2x2 canvas whose art stands
    up and left (centre table), 3 phases A A B (merge), 4 a block with pixels at alpha 20 (drop_faint), 5 untouched"""
    recs = [t.record(rect(4, 4, 28, 28)),                                   # 1 solid
            t.record({**rect(4, 4, 12, 12), **checker(14, 14, 30, 30)}),    # 2 solid corner and a checker mesh
            t.record(rect(0, 0, 10, 10)),                                   # 3 art at a tile's top left
            t.record(rect(8, 8, 16, 16)),                                   # 4 A
            t.record(rect(10, 10, 20, 20)),                                 # 5 B
            t.record({**rect(8, 8, 16, 16), **rect(20, 20, 24, 24, (200, 100, 50, 20))}),   # 6 faint
            t.record(rect(1, 1, 3, 3))]                                     # 7 other
    e1 = t.entry(b'', [t.group([1, 2], phases=2, anim=(0, 0, 0, [83] * 4))])
    e2 = t.entry(b'', [t.group([0, 0, 0, 3, 0, 0, 0, 3], w=2, h=2, phases=2, anim=(0, 0, 0, [83] * 4))])
    e3 = t.entry(b'', [t.group([4, 4, 5], phases=3, anim=(0, 0, 0, [100, 100, 60, 60, 80, 80]))])
    e4 = t.entry(b'', [t.group([6, 6], phases=2, anim=(0, 0, 0, [90] * 4))])
    e5 = t.entry(b'', [t.group([7])])
    return recs, [t.entry(bytes([17]), [t.group([7])])], [t.entry(b'', [t.group([7], gtype=0)], outfit=True)], [e1, e2, e3, e4, e5], []


def write(path, head, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(head)
        w.writerows(rows)
    return path


def tables(c, name, centre_of=None, mesh=None, merge='0,2'):
    d = c.dir
    dis = write(os.path.join(d, name + '_dis.csv'), ['kind', 'id', 'mesh', 'reason'], [['effect', 1, mesh, 'test']])
    of = centre_of or (0, 0)
    cen = write(os.path.join(d, name + '_cen.csv'), ['kind', 'id', 'shift', 'of', 'to', 'pair', 'reason'],
                [['effect', 2, '16,16', '%.2f,%.2f' % of, '%.2f,%.2f' % (of[0] + 16, of[1] + 16), FX.PAIR, 'test'],
                 ['effect', 2, '0,0', '9.00,9.00', '9.00,9.00', 80, 'a row of an older pair: not run here']])
    fix = write(os.path.join(d, name + '_fix.csv'), ['kind', 'id', 'op', 'args', 'reason', 'review'],
                [['effect', 3, 'merge', 'of=3;keep=' + merge, 'test', 'n/a'],
                 ['effect', 4, 'drop_faint', 'below=40;expect=32', 'test', 'n/a']])
    return dict(fixes=fix, dissolve=dis, centre=cen, sums_path=os.path.join(d, name + '.sums'))


def quiet(fn, *a, **kw):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        r = fn(*a, log=print, **kw)
    return r, buf.getvalue()


def setup(c):
    dat, spr = c.pair(*parts())
    import clean_pack_dither as cpd
    import recentre_effects as RC
    from datspr import Dat
    mesh = cpd.count_mesh(Dat(dat).effects[0], Spr(spr))
    things = idt.parse_dat(open(dat, 'rb').read(), idt.OUR_KINDS)
    store = FX.AF.Store(Spr(spr))
    g = FX.AF.TS(things['effect'][1]).groups[0]
    centre = RC.centre(RC.canvases(store, g), g['w'], g['h'])
    return dat, spr, mesh, centre


def test_build_and_check(c):
    dat, spr, mesh, centre = setup(c)
    t.expect(mesh >= 12, 'the synthetic checker is a mesh (%d pixels)' % mesh)
    tb = tables(c, 'a', centre, mesh)
    got, text = quiet(FX.build, dat, spr, None, dry_run=True, write=True, **tb)
    t.expect(len(got) == 4 and os.path.exists(tb['sums_path']), 'the dry run writes the sums of the 4 things')
    t.expect('1 dissolve: 1 things' in text and '2 centre: 1 rows' in text and '3 frames: 2 rows' in text, 'three steps in order')
    out = os.path.join(c.dir, 'out_a')
    got2, text = quiet(FX.build, dat, spr, out, **tb)
    t.expect(got2 == got and 'verified' in text, 'the build matches the sums and verifies')
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    old = idt.parse_dat(open(dat, 'rb').read(), idt.OUR_KINDS)
    new = idt.parse_dat(open(od, 'rb').read(), idt.OUR_KINDS)
    g3 = new['effect'][2].groups[0]
    t.expect(g3['phases'] == 2 and g3['anim'][1] == (160, 160, 80, 80), 'merge: A A B -> A B, 160 ms then 80 ms')
    t.expect(new['effect'][4].raw[1] - new['effect'][4].raw[0] == old['effect'][4].raw[1] - old['effect'][4].raw[0]
             and new['effect'][4].groups[0]['sprites'] == old['effect'][4].groups[0]['sprites'], 'an effect outside the tables stays')
    sp = Spr(os_)
    g1 = new['effect'][0].groups[0]
    t.expect(g1['sprites'][0] == 1 and g1['sprites'][1] > Spr(spr).count, 'dissolve: the meshed frame is a new record, the solid one stays')
    t.expect(int((sp.sprite(g1['sprites'][1])[..., 3] > 0).sum()) < int((Spr(spr).sprite(2)[..., 3] > 0).sum()), 'dissolve removed pixels')
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:1,2,3,4'))
    t.expect(r.ok, 'check_pair append-only passes: ' + r.text())
    sums = tb['sums_path']
    t.expect(quiet(FX.check, od, os_, assets=81, sums_path=sums)[0] == 0, 'check: the built pair is fixed')
    t.expect(quiet(FX.check, od, os_, assets=82, sums_path=sums)[0] == 0, 'check: fixed at pair 82 too')
    r81, text = quiet(FX.check, dat, spr, assets=81, sums_path=sums)
    t.expect(r81 == 0 and 'pending' in text, 'check: the input pair is pending while windows-assets has pair 81')
    t.expect(quiet(FX.check, dat, spr, assets=82, sums_path=sums)[0] == 1, 'check: the input pair fails once pair 82 is due')
    FX._FORMS.clear()
    import fix_pack_fx as again
    t.expect(len({k for k, v in again.forms(od, os_, again.read_sums(sums)).items() if v == 'after'}) == 4, 'forms: 4 things fixed')
    _, text = quiet(FX.build, od, os_, os.path.join(c.dir, 'out_a2'), **tb)
    t.expect('nothing to do' in text and not os.path.exists(os.path.join(c.dir, 'out_a2')), 'a second run writes nothing')
    out3 = os.path.join(c.dir, 'out_a3')
    quiet(FX.build, dat, spr, out3, **tb)
    for f in ('Tibia.dat', 'Tibia.spr'):
        t.expect(open(os.path.join(out, f), 'rb').read() == open(os.path.join(out3, f), 'rb').read(), 'same input, same ' + f)


def test_refusals(c):
    dat, spr, mesh, centre = setup(c)
    good = tables(c, 'g', centre, mesh)
    quiet(FX.build, dat, spr, None, dry_run=True, write=True, **good)
    cases = {
        'dissolve count of another pair': tables(c, 'b1', centre, mesh + 5),
        'centre premise': tables(c, 'b2', (centre[0] + 3, centre[1]), mesh),
        'merge keep': tables(c, 'b3', centre, mesh, merge='0,1,2'),
    }
    for name, tb in cases.items():
        tb['sums_path'] = good['sums_path']
        try:
            quiet(FX.build, dat, spr, None, dry_run=True, **tb)
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass
    lines = open(good['sums_path']).read().splitlines()
    bad = os.path.join(c.dir, 'bad.sums')
    open(bad, 'w').write('\n'.join(lines[:-1] + [lines[-1][:-3] + '000']) + '\n')
    tb = dict(good, sums_path=bad)
    try:
        quiet(FX.build, dat, spr, None, dry_run=True, **tb)
        t.expect(False, 'refused: an output that differs from the sums')
    except SystemExit:
        pass
    try:
        quiet(FX.build, dat, spr, os.path.dirname(dat), **good)
        t.expect(False, 'refused: out-dir is the input dir')
    except SystemExit:
        pass


def test_committed_tables(c):
    only, crow, frows = FX.tables()
    keys = FX.touched(only, crow, frows)
    sums = FX.read_sums()
    t.expect(len(only) == 47 and len(crow) == 25 and len(frows) == 65, 'the tables: 47 dissolve, 25 centre, 65 frame rows')
    t.expect(sorted(sums) == keys and len(keys) == 130, 'the sums name every thing of the tables (130)')
    t.expect(all(b != a for b, a in sums.values()), 'every thing of the sums changes')
    ops = {r['op'] for r in frows}
    t.expect(ops == {'merge', 'clear_strays', 'drop_faint', 'demesh'}, 'frame ops: merge, clear_strays, drop_faint, demesh')
    t.expect(all(r['pair'] == FX.PAIR and abs(r['dx']) <= 32 and abs(r['dy']) <= 32 for r in crow), 'centre rows: pair 82, under a tile')
    t.expect(all(int(dict(p.split('=') for p in r['args'].split(';'))['below']) == 40 for r in frows if r['op'] == 'drop_faint'),
             'drop_faint at alpha 40 only')


def main():
    c = t.Case()
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            fn(c)
    if t.FAILS:
        print('%d failed' % len(t.FAILS))
        return 1
    print('fix_pack_fx_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
