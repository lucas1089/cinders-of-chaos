#!/usr/bin/env python3
"""Tests of fix_dissolve_tail.py and the undissolve op of anim_fixes.py on a small synthetic pair (no real pair needed), and
of the committed table (O766).

python3 -I client/tools/sprites/fix_dissolve_tail_test.py
"""
import contextlib
import csv
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anim_fixes as AF  # noqa: E402
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402
import fix_dissolve_tail as FD  # noqa: E402
import fix_pack_fx as FX  # noqa: E402
import import_donor_things as idt  # noqa: E402
import recentre_effects as RC  # noqa: E402

COL = (200, 90, 220, 255)


def px(cond):
    return {y * 32 + x: COL for y in range(4, 28) for x in range(4, 28) if cond(x, y)}


def parts():
    """effects: 1 solid x3, the Bayer tail (holes, dots, dots), a blank end; 2 the same with a solid last phase (no tail);
    3 sparks: lone dots in every phase (no tail); 4 untouched"""
    recs = [t.record(px(lambda x, y: True)),                                  # 1 solid
            t.record(px(lambda x, y: (x % 2, y % 2) != (1, 1))),               # 2 stage A: holes, 3/4 of the art
            t.record(px(lambda x, y: x % 4 == 0 and y % 4 == 0)),              # 3 stage B: lone dots
            t.record(px(lambda x, y: x % 4 == 2 and y % 4 == 2)),              # 4 stage C: lone dots
            t.record(px(lambda x, y: (x + 2 * y) % 5 == 0 and x % 3 == 0))]    # 5 sparks
    ms = [70, 70] * 7
    e1 = t.entry(b'', [t.group([1, 1, 1, 2, 3, 4, 0], phases=7, anim=(0, 0, 0, ms))])
    e2 = t.entry(b'', [t.group([1, 1, 1, 2, 3, 1, 0], phases=7, anim=(0, 0, 0, ms))])
    e3 = t.entry(b'', [t.group([5, 3, 5, 3, 4, 3, 0], phases=7, anim=(0, 0, 0, ms))])
    e4 = t.entry(b'', [t.group([1])])
    return recs, [t.entry(bytes([17]), [t.group([1])])], [t.entry(b'', [t.group([1], gtype=0)], outfit=True)], [e1, e2, e3, e4], []


def quiet(fn, *a, **kw):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        r = fn(*a, log=print, **kw)
    return r, buf.getvalue()


def write_rows(path, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(AF.SPEC_COLS)
        w.writerows(rows)
    return path


def centre_table(path, rows=()):
    """an effect_centre.csv of the given rows (the committed one names effects the synthetic pair lacks)"""
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['kind', 'id', 'shift', 'of', 'to', 'pair', 'reason'])
        w.writerows(rows)
    return path


def test_rule():
    m = [(576, 0, 0)] * 3 + [(432, 144, 0), (36, 0, 36), (36, 0, 36), (0, 0, 0)]
    t.expect(AF.dissolve_tail(m) == (3, 6), 'tail: phases 3-5, the blank end stays')
    t.expect(AF.dissolve_tail(m[:-1]) == (3, 6), 'tail without a blank end')
    t.expect(AF.dissolve_tail(m[:5] + [(576, 0, 0), (0, 0, 0)]) is None, 'a solid last phase: no tail')
    t.expect(AF.dissolve_tail([(432, 144, 0), (36, 0, 36), (36, 0, 36)]) is None, 'no solid phase before: no tail')
    t.expect(AF.dissolve_tail(m[:3] + [(560, 144, 0)] + m[4:]) is None, 'stage A must hold about 3/4 of the art before it')
    t.expect(AF.dissolve_tail(m[:3] + [(432, 10, 0)] + m[4:]) is None, 'stage A needs holes')
    t.expect(AF.dissolve_tail(m[:3] + [(432, 144, 200)] + m[4:]) is None, 'stage A of sparks is no tail')
    t.expect(AF.dissolve_tail(m[:4] + [(36, 0, 20)] + m[5:]) is None, 'stage B must be lone dots')
    t.expect(AF.keep_text([0, 1, 2, 6]) == '0-2,6' and AF.keep_text([0, 2, 3]) == '0,2-3', 'keep text')


def test_scan_build_check(c):
    dat, spr = c.pair(*parts())
    rows, text = quiet(FD.scan, dat, spr)
    t.expect([r['id'] for r in rows] == [1] and rows[0]['args'] == 'of=7;keep=0-2,6', 'scan finds effect 1 only, keep 0-2,6')
    tab = os.path.join(c.dir, 'tail.csv')
    FD.write_table(rows, tab)
    sums = os.path.join(c.dir, 'tail.sums')
    none = centre_table(os.path.join(c.dir, 'centre_none.csv'))
    got, text = quiet(FD.build, dat, spr, None, dry_run=True, write=True, table=tab, sums_path=sums, centre=none)
    t.expect(len(got) == 1 and 'O766' in open(sums).read().splitlines()[0], 'the dry run writes the sums')
    out = os.path.join(c.dir, 'out')
    got2, text = quiet(FD.build, dat, spr, out, table=tab, sums_path=sums, centre=none)
    t.expect(got2 == got and 'verified' in text and '1 things cut, 3 phases removed' in text, 'build verifies: %s' % text)
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    new = idt.parse_dat(open(od, 'rb').read(), idt.OUR_KINDS)
    g = new['effect'][0].groups[0]
    t.expect(g['phases'] == 4 and list(g['sprites']) == [1, 1, 1, 0] and tuple(g['anim'][1]) == (70,) * 8, 'the tail is cut with its time: %r' % (g,))
    t.expect(new['effect'][1].groups[0]['phases'] == 7 and new['effect'][2].groups[0]['phases'] == 7, 'the others stay')
    t.expect(open(os_, 'rb').read() == open(spr, 'rb').read(), 'the spr is the input spr')
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:1'))
    t.expect(r.ok, 'check_pair append-only passes: ' + r.text())
    t.expect(quiet(FD.check, od, os_, assets=84, sums_path=sums)[0] == 0, 'check: the built pair is cut')
    r84, text = quiet(FD.check, dat, spr, assets=84, sums_path=sums)
    t.expect(r84 == 0 and 'pending' in text, 'check: the input pair is pending while windows-assets has pair 84')
    t.expect(quiet(FD.check, dat, spr, assets=85, sums_path=sums)[0] == 1, 'check: the input pair fails once pair 85 is due')
    _, text = quiet(FD.build, od, os_, os.path.join(c.dir, 'out2'), table=tab, sums_path=sums, centre=none)
    t.expect('nothing to do' in text and not os.path.exists(os.path.join(c.dir, 'out2')), 'a second run writes nothing')
    # fix_pack_fx: a thing in its fixed form whose tail was cut later still counts as fixed
    b, a = FX.read_sums(sums)[('effect', 1)]
    pack = os.path.join(c.dir, 'pack.sums')
    open(pack, 'w').write('# test\neffect 1 000000000000000000000000 %s\n' % b)
    FX._FORMS.clear()
    real = FX.tail_sums
    try:
        FX.tail_sums = lambda: FX.read_sums(sums)
        t.expect(FX.forms(od, os_, FX.read_sums(pack))[('effect', 1)] == 'after', 'fix_pack_fx: the cut form of its fixed form is fixed')
        t.expect(FX.forms(od, os_, FX.read_sums(pack), raw=True)[('effect', 1)] is None, 'fix_pack_fx raw: only its own forms')
    finally:
        FX.tail_sums = real
        FX._FORMS.clear()
    # refusals
    for name, args in (('another phase count', 'of=8;keep=0-2,6'), ('another keep', 'of=7;keep=0-3,6')):
        bad = write_rows(os.path.join(c.dir, 'bad.csv'), [['effect', 1, 'undissolve', args, 'test', '']])
        try:
            quiet(FD.build, dat, spr, None, dry_run=True, table=bad, sums_path=sums, centre=none)
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass
    bad = write_rows(os.path.join(c.dir, 'bad.csv'), [['effect', 2, 'undissolve', 'of=7;keep=0-2,6', 'test', '']])
    try:
        quiet(FD.build, dat, spr, None, dry_run=True, table=bad, sums_path=sums, centre=none)
        t.expect(False, 'refused: no tail')
    except SystemExit:
        pass
    try:
        quiet(FD.build, dat, spr, os.path.dirname(dat), table=tab, sums_path=sums, centre=none)
        t.expect(False, 'refused: out-dir is the input dir')
    except SystemExit:
        pass


def test_centre_row(c):
    """a row of effect_centre.csv of pair 85 moves the art after the cut (758 stun_stars over the head): new sprite records,
    the cut and moved form in the sums, every check passes on it"""
    dat, spr = c.pair(*parts())
    rows, _ = quiet(FD.scan, dat, spr)
    tab = FD.write_table(rows, os.path.join(c.dir, 'ctail.csv')) or os.path.join(c.dir, 'ctail.csv')
    sums = os.path.join(c.dir, 'ctail.sums')
    row = ['effect', '1', '-2,-3', '0.00,0.00', '-2.00,-3.00', str(FD.PAIR), 'test']
    cen = centre_table(os.path.join(c.dir, 'centre85.csv'), [row])
    other = centre_table(os.path.join(c.dir, 'centre82.csv'), [row[:5] + ['82', 'test']])
    t.expect(FD.centre_rows(other) == [] and [r['id'] for r in FD.centre_rows(cen)] == [1], 'only the rows of pair 85 are built here')
    got, text = quiet(FD.build, dat, spr, None, dry_run=True, write=True, table=tab, sums_path=sums, centre=cen)
    t.expect('shift -2,-3' in text and '1 rows of pair 85' in text, 'the dry run moves effect 1: %s' % text)
    out = os.path.join(c.dir, 'cout')
    got2, text = quiet(FD.build, dat, spr, out, table=tab, sums_path=sums, centre=cen)
    t.expect(got2 == got and 'verified' in text and 'sprite records appended' in text, 'build verifies: %s' % text)
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    d, sp, things = RC.load(od, os_)
    g = things['effect'][0].groups[0]
    t.expect(g['phases'] == 4 and set(g['sprites']) - {0} == {sp.count}, 'cut by three phases, on one new record: %r' % (g['sprites'],))
    cx, cy = RC.centre(RC.canvases(AF.Store(sp), AF.TS(things['effect'][0]).groups[0]), 1, 1)
    t.expect(abs(cx + 2) < 0.05 and abs(cy + 3) < 0.05, 'the centre is the row\'s `to`: %.2f, %.2f' % (cx, cy))
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:1'))
    t.expect(r.ok, 'check_pair append-only passes: ' + r.text())
    t.expect(quiet(FD.check, od, os_, assets=85, sums_path=sums)[0] == 0, 'check: the cut and moved form passes')
    t.expect(RC.check(od, os_, cen, log=lambda *_: None, assets=85, fixed=set()) == 0, 'recentre_effects check: the row is done')
    _, text = quiet(FD.build, od, os_, os.path.join(c.dir, 'cout2'), table=tab, sums_path=sums, centre=cen)
    t.expect('nothing to do' in text, 'a second run writes nothing')
    _, text = quiet(RC.build, dat, spr, os.path.join(c.dir, 'cout3'), cen)
    t.expect('built by fix_dissolve_tail.py' in text and not os.path.exists(os.path.join(c.dir, 'cout3')), 'recentre_effects build skips it')
    edge = centre_table(os.path.join(c.dir, 'centre_edge.csv'), [['effect', '1', '-5,0', '0.00,0.00', '-5.00,0.00', '85', 'test']])
    try:
        quiet(FD.build, dat, spr, None, dry_run=True, table=tab, sums_path=sums, centre=edge)
        t.expect(False, 'refused: a shift that cuts art off')
    except SystemExit:
        pass


def test_committed_table():
    rows = AF.read_spec(FD.TABLE)
    sums = FX.read_sums(FD.SUMS)
    keys = sorted({(r['kind'], r['id']) for r in rows})
    t.expect(len(rows) == 141 and len(keys) == 141, 'the table: 141 effects')
    t.expect(all(r['op'] == 'undissolve' and r['kind'] == 'effect' for r in rows), 'undissolve rows of effects only')
    t.expect(sorted(sums) == keys and all(b != a for b, a in sums.values()), 'the sums name every row, each changes')
    import clean_pack_dither as cpd
    only = {i for (_c, i) in cpd.read_only(cpd.ONLY)}
    t.expect(only <= {i for _k, i in keys}, 'every effect of the O733 dissolve table is cut')
    pack = FX.read_sums()
    t.expect(all(sums[k][0] == pack[k][1] for k in keys if k in pack), 'a thing of fix_pack_fx.py is cut from its fixed form')
    for r in rows:
        a = AF.args_of(r['args'])
        n = int(a['of'])
        t.expect(a['keep'] in ('0-%d,%d' % (n - 5, n - 1), '0-%d' % (n - 4)), 'effect %d: three phases cut before the end' % r['id'])
    sys.path.insert(0, os.path.join(FD.HERE, '..', '..', '..', 'server', 'tools'))
    import client_pair
    t.expect(client_pair.PAIR_DISSOLVE_TAIL == FD.PAIR == 85, 'client_pair.PAIR_DISSOLVE_TAIL is the pair of the cut')
    crow = FD.centre_rows()
    t.expect([(r['id'], r['dx'], r['dy']) for r in crow] == [(758, -8, -24)], 'the pair 85 centre row: 758 stun_stars by -8, -24')
    if crow:
        r = crow[0]
        tx, ty = r['to'][0] - 16, r['to'][1] - 16       # 2x2 canvas: the target tile's middle is 16 px right and down
        t.expect(-12 <= tx <= -5 and -28 <= ty <= -20, 'stun_stars over the head of a 1x1 creature (x -8.5, head top -22..-24): %.1f, %.1f' % (tx, ty))
        t.expect(('effect', 758) in sums, 'the sums hold the cut and moved form of 758')


def main():
    c = t.Case()
    test_rule()
    test_scan_build_check(c)
    test_centre_row(c)
    test_committed_table()
    if t.FAILS:
        print('%d failed' % len(t.FAILS))
        return 1
    print('fix_dissolve_tail_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
