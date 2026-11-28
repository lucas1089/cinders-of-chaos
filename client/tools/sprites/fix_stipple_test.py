#!/usr/bin/env python3
"""Tests of fix_stipple.py and the unstipple op of anim_fixes.py on a small synthetic pair (no real pair needed), and of the
committed tables (O769, stage 2 of O777: the 1/16 stage and the glow lattice, stage 3 of O786: the Bayer glows requantised).

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


# ------------------------------------------------------------------------------------------------ stage 2 (O777)
def plus5(x, y):
    """the glow lattice of effect 708: a '+' of five pixels in every 4x4 cell (5/16, under half density)"""
    return (y % 4 == 0 and x % 4 in (0, 2, 3)) or (x % 4 == 3 and y % 4 in (1, 3))


def stage16(x, y):
    """the 1/16 Bayer stage: one hole in every 4x4 cell"""
    return (x % 4, y % 4) != (1, 1)


SQ = range(10, 22)


def glow_body(lo=SQ, lat=plus5, span=range(6, 26)):
    """a solid body (12x12) inside a glow lattice four to six pixels wide"""
    px = {y * 32 + x: DIM for y in span for x in span if lat(x, y)}
    px.update({y * 32 + x: BODY for y in lo for x in lo})
    return px


def test_stage2_rule():
    img = canvas(body(stage16))
    t.expect(FS.redraw(img)[1] == 0, 'stage 1 leaves the 1/16 stage (partners 4 px apart)')
    new, f, d = FS.redraw(img, 2)
    holes = sum(1 for y in range(5, 27) for x in range(5, 27) if not stage16(x, y))
    t.expect(f == holes and d == 0, 'stage 2 fills the 1/16 holes: %d of %d' % (f, holes))
    t.expect((new[4:28, 4:28, 3] == 255).all() and (new[4:28, 4:28, :3] == BODY[:3]).all(), 'the 1/16 body is one solid colour')
    one = canvas(body(lambda x, y: (x, y) not in ((13, 13), (17, 13))))
    t.expect(FS.redraw(one, 2)[1:] == (0, 0), 'two drawn holes 4 px apart (one partner) stay')
    lone = canvas(body(lambda x, y: (x, y) != (15, 15)))
    t.expect(FS.redraw(lone, 2)[1:] == (0, 0), 'a lone drawn hole stays in stage 2')
    g = canvas(glow_body())
    new, f, d = FS.redraw(g, 2)
    a = new[..., 3] > 0
    near = FS.dilate(np.pad(np.ones((12, 12), bool), ((10, 10), (10, 10))), 1)
    t.expect((new[10:22, 10:22] == g[10:22, 10:22]).all(), 'the body inside the glow keeps every pixel')
    t.expect(not (a & ~near).any() and d > 60, 'the glow lattice under half density goes (%d dropped, %d left out of the body '
             'and its edge)' % (d, int((a & ~near).sum())))
    t.expect(FS.redraw(new, 2)[1:] == (0, 0), 'stage 2 on its own result finds nothing')
    q = canvas(glow_body(lat=lambda x, y: x % 2 == 0 and y % 2 == 0))
    new, _f, d = FS.redraw(q, 2)
    t.expect(not ((new[..., 3] > 0) & ~near).any(), 'the 1/4 Bayer stage (dots two apart) round a body goes too (%d)' % d)
    mid = canvas(body(lambda x, y: not (y % 4 == 1 and x % 4 in (1, 2))))
    t.expect(FS.redraw(mid)[1] == 0, 'stage 1 leaves holes of two pixels (three art sides)')
    new, f, d = FS.redraw(mid, 2)
    t.expect((new[6:26, 6:26, 3] == 255).all() and f > 50, 'a lattice over half density fills solid in stage 2 (%d)' % f)
    t.expect(set(map(tuple, new[6:26, 6:26, :3].reshape(-1, 3).tolist())) == {BODY[:3]}, 'with the colour of the body')
    # what stage 2 must leave: lines, small rings, sparks, solid round shapes, drawn holes
    keep = {}
    hl = canvas({})
    hl[10, 3:29] = BODY
    keep['a one pixel straight line'] = hl
    dl = canvas({})
    for i in range(3, 29):
        dl[i, i] = BODY
    keep['a one pixel diagonal line'] = dl
    rg = canvas({})
    for y, x in ((14, 15), (14, 16), (14, 17), (15, 14), (16, 14), (17, 14),
                 (18, 15), (18, 16), (18, 17), (15, 18), (16, 18), (17, 18)):
        rg[y, x] = SPARK
    keep['a small ring'] = rg
    sp = canvas({})
    for x in range(2, 30, 2):
        sp[9, x] = SPARK
    keep['a row of sparks two apart'] = sp
    disc = canvas({y * 32 + x: BODY for y in range(32) for x in range(32) if (x - 15.5) ** 2 + (y - 15.5) ** 2 <= 120})
    keep['a solid disc'] = disc
    ol = canvas({y * 32 + x: EDGE for y in range(32) for x in range(32) if 9 <= ((x - 15.5) ** 2 + (y - 15.5) ** 2) ** 0.5 < 10})
    keep['a round outline'] = ol
    for name, img in keep.items():
        t.expect(FS.redraw(img, 2)[1:] == (0, 0), 'stage 2 leaves %s: %r' % (name, FS.redraw(img, 2)[1:]))


def parts2():
    """stage 2 pair (FS.STOCK and FS.BAYER_LAST patched to 1 and 6): effects 1 a stock look with a glow lattice (guard), 2 a
    body with the 1/16 stage (listed), 3 a body in a glow lattice (listed), 4 effect 1's art with other timing (a stock copy:
    guard), 5 a small body in a wide glow (mostly glow: guard), 6 a solid body with a drawn hole and a line (nothing), 7 a
    glow lattice after the Bayer cut era (guard)"""
    s7 = body(lambda x, y: (x, y) != (15, 15))
    for x in range(4, 28):
        s7[1 * 32 + x] = EDGE
    small = glow_body(lo=range(14, 18), span=range(2, 30))
    recs = [t.record(glow_body()), t.record(body(stage16)), t.record(small), t.record(s7)]
    ms = [80, 80] * 2
    ms2 = [120, 120] * 2
    effects = [t.entry(b'', [t.group([1, 1], phases=2, anim=(0, 0, 0, ms))]),
               t.entry(b'', [t.group([2, 2], phases=2, anim=(0, 0, 0, ms))]),
               t.entry(b'', [t.group([1], phases=1)]),
               t.entry(b'', [t.group([1, 1], phases=2, anim=(0, 0, 0, ms2))]),
               t.entry(b'', [t.group([3], phases=1)]),
               t.entry(b'', [t.group([4], phases=1)]),
               t.entry(b'', [t.group([1], phases=1)])]
    return recs, [t.entry(bytes([17]), [t.group([1])])], [t.entry(b'', [t.group([1], gtype=0)], outfit=True)], effects, []


def test_stage2_scan_build_check(c):
    keep = (FS.STOCK, FS.BAYER_LAST)
    FS.STOCK, FS.BAYER_LAST = {'effect': 1, 'missile': 0}, {'effect': 6, 'missile': 0}
    try:
        _test_stage2(c)
    finally:
        FS.STOCK, FS.BAYER_LAST = keep
        FX._FORMS.clear()


def _test_stage2(c):
    dat, spr = c.pair(*parts2())
    # effect 3 is one phase of effect 1's art: not a copy (other frames); effect 7 the same art after the era
    rows, text = quiet(FS.scan, dat, spr, stage=2)
    t.expect([r['id'] for r in rows] == [2, 3], 'stage 2 lists effects 2 and 3: %r %s' % ([r['id'] for r in rows], text))
    t.expect('2 stock or stock copies' in text and '1 after the Bayer cut' in text
             and '1 mostly glow' in text, 'the guards name the stock look, its copy, the late id and the glow: %s' % text)
    t.expect(all('stage=2' in r['args'] and r['reason'].startswith('O777') for r in rows), 'stage 2 rows: stage=2, O777')
    tab, sums = os.path.join(c.dir, 'stipple_p90.csv'), os.path.join(c.dir, 'stipple_p90.sums')
    FS.write_table(rows, tab)
    out = os.path.join(c.dir, 'out90')
    got, text = quiet(FS.build, dat, spr, out, write=True, table=tab, sums_path=sums, stage=2)
    t.expect(len(got) == 2 and 'verified' in text and '(O777)' in open(sums).read().splitlines()[0]
             and 'pair 89' in open(sums).read().splitlines()[0], 'stage 2 build writes its sums and verifies: %s' % text)
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:2,3'))
    t.expect(r.ok, 'check_pair append-only passes on the stage 2 pair: ' + r.text())
    t.expect(quiet(FS.scan, od, os_, stage=2)[0] == [], 'a stage 2 scan of the built pair lists nothing')
    t.expect(quiet(FS.check, od, os_, assets=89, sums_path=sums, stage=2)[0] == 0, 'stage 2 check: the built pair is redrawn')
    r89, text = quiet(FS.check, dat, spr, assets=89, sums_path=sums, stage=2)
    t.expect(r89 == 0 and 'pending' in text and 'O777' in text, 'stage 2 check: pending while windows-assets has pair 89')
    t.expect(quiet(FS.check, dat, spr, assets=90, sums_path=sums, stage=2)[0] == 1, 'stage 2 check: due from pair 90')
    # chained forms: an O769 thing redrawn again by stage 2 still counts as redrawn for O769 and fix_pack_fx
    b2, a2 = FX.read_sums(sums)[('effect', 3)]
    s1 = os.path.join(c.dir, 's1.sums')
    with open(s1, 'w') as f:
        f.write('# test\neffect 3 000000000000000000000000 %s\n' % b2)
    pk = os.path.join(c.dir, 'pk.sums')
    with open(pk, 'w') as f:
        f.write('# test\neffect 3 111111111111111111111111 000000000000000000000000\n')
    real = (FX.stipple_sums, FX.stipple2_sums, FX.stipple3_sums)
    try:
        FX.stipple2_sums = lambda: FX.read_sums(sums)
        FX.stipple_sums = lambda: FX.read_sums(s1)
        FX.stipple3_sums = lambda: {}
        FX._FORMS.clear()
        t.expect(FS.forms(od, os_, s1, stage=1)[('effect', 3)] == 'after',
                 'O769 forms: its redrawn form redrawn again is redrawn')
        t.expect(quiet(FS.check, od, os_, assets=90, sums_path=s1, stage=1)[0] == 0, 'O769 check passes on the stage 2 pair')
        t.expect(FX.forms(od, os_, FX.read_sums(pk))[('effect', 3)] == 'after', 'fix_pack_fx: fixed, O769, then O777 is fixed')
        t.expect(FX.forms(od, os_, FX.read_sums(pk), stipple='late')[('effect', 3)] is None, "fix_pack_fx 'late': stage 2 only")
    finally:
        FX.stipple_sums, FX.stipple2_sums, FX.stipple3_sums = real
        FX._FORMS.clear()
    _, text = quiet(FS.build, od, os_, os.path.join(c.dir, 'out91'), table=tab, sums_path=sums, stage=2)
    t.expect('nothing to do' in text, 'a second stage 2 run writes nothing')
    bad = os.path.join(c.dir, 'bad2.csv')
    for name, row in (('another count', ['effect', 2, 'unstipple', 'fill=1;drop=0;stage=2', 'test', '']),
                      ('no such stage', ['effect', 2, 'unstipple', 'fill=1;drop=0;stage=4', 'test', ''])):
        with open(bad, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f, lineterminator='\n')
            w.writerow(AF.SPEC_COLS)
            w.writerow(row)
        try:
            quiet(FS.build, dat, spr, None, dry_run=True, table=bad, sums_path=os.path.join(c.dir, 'bad2.sums'), stage=2)
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass
    with open(bad, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(AF.SPEC_COLS)
        w.writerow(rows[0][k] for k in AF.SPEC_COLS)
        w.writerow(['effect', 3, 'unstipple', 'fill=1;drop=0', 'test', ''])
    try:
        quiet(FS.build, dat, spr, None, dry_run=True, table=bad, sums_path=os.path.join(c.dir, 'bad3.sums'))
        t.expect(False, 'refused: rows of two stages')
    except SystemExit:
        pass


def test_committed_table2():
    rows = AF.read_spec(FS.TABLE2)
    sums = FX.read_sums(FS.SUMS2)
    keys = sorted({(r['kind'], r['id']) for r in rows})
    t.expect(len(rows) == len(keys) and len(rows) > 100, 'the stage 2 table: one row a thing (%d)' % len(rows))
    t.expect(all(r['op'] == 'unstipple' and AF.args_of(r['args']).get('stage') == '2' for r in rows), 'unstipple rows of stage 2')
    t.expect(sorted(sums) == keys and all(b != a for b, a in sums.values()), 'the stage 2 sums name every row, each changes')
    extra = FS.owned_extra()
    t.expect(not any(FS.owned(k, i) or (k, i) in extra for k, i in keys), 'no stage 2 row names a thing another tool holds')
    t.expect(all(FS.STOCK[k] < i <= FS.BAYER_LAST[k] for k, i in keys), 'stage 2 rows: after the stock ids, in the Bayer cut era')
    for want in (708, 3896, 719, 720, 721, 722, 723, 724, 725, 726):
        t.expect(('effect', want) in sums, 'effect %d (V45) is in the stage 2 table' % want)
    s1 = FX.read_sums(FS.SUMS)
    import fix_dissolve_tail as FD
    tail = FX.read_sums(FD.SUMS)
    pack = FX.read_sums()
    for k in keys:
        if k in s1:
            t.expect(sums[k][0] == s1[k][1], '%s %d: stage 2 starts from its O769 form' % k)
        elif k in tail:
            t.expect(sums[k][0] == tail[k][1], '%s %d: stage 2 starts from its tail cut form' % k)
        elif k in pack:
            t.expect(sums[k][0] == pack[k][1], '%s %d: stage 2 starts from its fixed form' % k)
    import re
    src = open(os.path.join(FS.HERE, 'gen_effects.py'), encoding='utf-8').read()
    m = re.search(r'^STOCK_EFFECTS, STOCK_MISSILES = (\d+), (\d+)', src, re.M)
    t.expect(m and (int(m.group(1)), int(m.group(2))) == (FS.STOCK['effect'], FS.STOCK['missile']),
             'FS.STOCK is gen_effects.STOCK_*')
    sys.path.insert(0, os.path.join(FS.HERE, '..', '..', '..', 'server', 'tools'))
    import client_pair
    t.expect(client_pair.PAIR_STIPPLE_LATTICE == FS.PAIR2 == 90, 'client_pair.PAIR_STIPPLE_LATTICE is the pair of stage 2')


# ------------------------------------------------------------------------------------------------ stage 3 (O786)
def bayer_glow(oy=1, ox=2, r0=4.0, r1=11.0, centre=(15.5, 15.5)):
    """a soft round glow cut by the 4x4 Bayer threshold (the imports up to pair 65): a solid core of radius r0, the alpha
    falling to 0 at r1, so the density changes within a few pixels; the core BODY, the glow EDGE"""
    rank = np.array(FS.BAYER4)
    px = {}
    for y in range(32):
        for x in range(32):
            r = ((x - centre[0]) ** 2 + (y - centre[1]) ** 2) ** 0.5
            a = 1.0 if r <= r0 else max(0.0, 1 - (r - r0) / (r1 - r0))
            if a > (rank[(y + oy) % 4, (x + ox) % 4] + 0.5) / 16:
                px[y * 32 + x] = BODY if r <= r0 else EDGE
    return px


def glow_line(oy=0, ox=3):
    """a glowing vertical line cut by the Bayer threshold: the centre column solid, alpha 0.6 one pixel out, 0.2 two out"""
    rank = np.array(FS.BAYER4)
    px = {}
    for y in range(2, 30):
        for x in range(10, 22):
            a = {0: 1.0, 1: 0.6, 2: 0.2}.get(abs(x - 15), 0.0)
            if a > (rank[(y + oy) % 4, (x + ox) % 4] + 0.5) / 16:
                px[y * 32 + x] = BODY if x == 15 else EDGE
    return px


def stage3_keep():
    """drawn art stage 3 must leave as it is"""
    keep = {}
    hl = canvas({})
    hl[10, 3:29] = BODY
    keep['a one pixel straight line'] = hl
    dl = canvas({})
    for i in range(3, 29):
        dl[i, i] = BODY
    keep['a one pixel diagonal line (it lies on the low ranks)'] = dl
    rg = canvas({})
    for y, x in ((14, 15), (14, 16), (14, 17), (15, 14), (16, 14), (17, 14),
                 (18, 15), (18, 16), (18, 17), (15, 18), (16, 18), (17, 18)):
        rg[y, x] = SPARK
    keep['a small ring'] = rg
    sp = canvas({})
    for x in range(2, 30, 2):
        sp[9, x] = SPARK
    keep['a row of sparks two apart'] = sp
    keep['a solid disc'] = canvas({y * 32 + x: BODY for y in range(32) for x in range(32)
                                   if (x - 15.5) ** 2 + (y - 15.5) ** 2 <= 120})
    keep['a round outline'] = canvas({y * 32 + x: EDGE for y in range(32) for x in range(32)
                                      if 9 <= ((x - 15.5) ** 2 + (y - 15.5) ** 2) ** 0.5 < 10})
    keep['a solid body with a drawn hole'] = canvas(body(lambda x, y: (x, y) != (15, 15)))
    return keep


def test_stage3_rule():
    for ph in ((1, 2), (0, 0), (3, 1)):
        img = canvas(bayer_glow(*ph))
        a = img[..., 3] > 0
        n, e = FS.best_phase(a)[:2]
        t.expect(e > 100 and n == e, 'phase %r: every art / clear edge of a Bayer glow follows the ranks (%d of %d)' % (ph, n, e))
        new, f, d, so = FS.glow_redraw(img)
        lv = set(new[..., 3].ravel().tolist())
        t.expect(lv == {0, FS.GLOW, 255} and f > 50 and so > 100,
                 'phase %r: the glow is requantised to 0 / %d / 255 (%d filled, %d dropped, %d at the glow level)' % (ph, FS.GLOW, f, d, so))
        core = np.zeros((32, 32), bool)
        for y in range(32):
            for x in range(32):
                core[y, x] = (x - 15.5) ** 2 + (y - 15.5) ** 2 <= 9
        t.expect((new[core] == img[core]).all(), 'phase %r: the solid core keeps every pixel' % (ph,))
        ys, xs = np.nonzero(new[..., 3] > 0)
        cols = {tuple(c) for c in img[img[..., 3] > 0][:, :3].tolist()}
        t.expect({tuple(c) for c in new[ys, xs, :3].tolist()} <= cols, 'phase %r: only colours the frame had' % (ph,))
        nb = new[..., 3] > 0
        k4 = sum(FS.shift(nb.astype(np.int16), dy, dx) for dy, dx in FS.SIDES)
        holes = int(((~nb) & (k4 >= 3)).sum())
        k4o = sum(FS.shift(a.astype(np.int16), dy, dx) for dy, dx in FS.SIDES)
        t.expect(holes * 5 < int(((~a) & (k4o >= 3)).sum()), 'phase %r: the dither holes are gone (%d left)' % (ph, holes))
        t.expect(FS.glow_redraw(new)[1:] == (0, 0, 0), 'phase %r: a second run finds nothing' % (ph,))
    ln = canvas(glow_line())
    new, f, d, so = FS.glow_redraw(ln)
    t.expect((new[2:30, 15] == ln[2:30, 15]).all(), 'a glowing line keeps its solid centre (runs of RUN_CORE or more)')
    t.expect((new[4:28, 14, 3] == FS.GLOW).all() and (new[4:28, 16, 3] == FS.GLOW).all(),
             'the dithered sides of the line become one glow level band')
    t.expect(not (new[4:28, 12, 3] > 0).any() and not (new[4:28, 18, 3] > 0).any(), 'the faint outer dots (density under LO) go')
    for name, img in stage3_keep().items():
        t.expect(FS.glow_redraw(img)[1:] == (0, 0, 0), 'stage 3 leaves %s: %r' % (name, FS.glow_redraw(img)[1:]))
    # the levels by density: a flat 6/16 Bayer stage becomes the glow level, a flat 3/16 one goes, 13/16 is solid
    for k, want in ((6, FS.GLOW), (3, 0), (13, 255)):
        rank = np.array(FS.BAYER4)
        img = canvas({y * 32 + x: EDGE for y in range(32) for x in range(32) if rank[y % 4, x % 4] < k})
        new = FS.glow_redraw(img)[0]
        t.expect(set(new[8:24, 8:24, 3].ravel().tolist()) == {want}, 'a flat %d/16 dither becomes alpha %d: %r'
                 % (k, want, sorted(set(new[8:24, 8:24, 3].ravel().tolist()))))


def parts3():
    """stage 3 pair (FS.STOCK and FS.BAYER_LAST patched to 1 and 6): effects 1 a stock look with a Bayer glow (guard), 2 a
    Bayer glow (listed), 3 a glowing line (listed), 4 effect 1's art with other timing (a stock copy: guard), 5 a solid body
    with a drawn hole, lines and sparks (not an ordered dither), 6 the glow with soft alpha (never touched), 7 a Bayer glow
    after the Bayer cut era (guard)"""
    s5 = body(lambda x, y: (x, y) != (15, 15))
    for x in range(4, 28):
        s5[1 * 32 + x] = EDGE
    for x in range(2, 30, 2):
        s5[30 * 32 + x] = SPARK
    soft = {k: (v[0], v[1], v[2], 200) for k, v in bayer_glow().items()}
    recs = [t.record(bayer_glow()), t.record(bayer_glow(0, 0, 3.0, 12.0)), t.record(glow_line()), t.record(s5), t.record(soft)]
    ms = [80, 80] * 2
    ms2 = [120, 120] * 2
    effects = [t.entry(b'', [t.group([1, 1], phases=2, anim=(0, 0, 0, ms))]),
               t.entry(b'', [t.group([2, 1], phases=2, anim=(0, 0, 0, ms))]),
               t.entry(b'', [t.group([3], phases=1)]),
               t.entry(b'', [t.group([1, 1], phases=2, anim=(0, 0, 0, ms2))]),
               t.entry(b'', [t.group([4], phases=1)]),
               t.entry(b'', [t.group([5], phases=1)]),
               t.entry(b'', [t.group([2], phases=1)])]
    return recs, [t.entry(bytes([17]), [t.group([1])])], [t.entry(b'', [t.group([1], gtype=0)], outfit=True)], effects, []


def test_stage3_scan_build_check(c):
    keep = (FS.STOCK, FS.BAYER_LAST)
    FS.STOCK, FS.BAYER_LAST = {'effect': 1, 'missile': 0}, {'effect': 6, 'missile': 0}
    try:
        _test_stage3(c)
    finally:
        FS.STOCK, FS.BAYER_LAST = keep
        FX._FORMS.clear()


def _test_stage3(c):
    dat, spr = c.pair(*parts3())
    rows, text = quiet(FS.scan, dat, spr, stage=3)
    t.expect([r['id'] for r in rows] == [2, 3], 'stage 3 lists effects 2 and 3: %r %s' % ([r['id'] for r in rows], text))
    t.expect('2 stock or stock copies' in text and '1 after the Bayer cut' in text and '1 soft alpha' in text
             and '1 not an ordered dither' in text, 'the guards: stock look and its copy, the late id, soft alpha, drawn art: %s' % text)
    t.expect(all('stage=3' in r['args'] and 'soft=' in r['args'] and r['reason'].startswith('O786') for r in rows),
             'stage 3 rows: stage=3, soft=, O786')
    tab, sums = os.path.join(c.dir, 'stipple_p91.csv'), os.path.join(c.dir, 'stipple_p91.sums')
    FS.write_table(rows, tab)
    out = os.path.join(c.dir, 'out_s3')
    got, text = quiet(FS.build, dat, spr, out, write=True, table=tab, sums_path=sums, stage=3)
    head = open(sums).read().splitlines()[0]
    t.expect(len(got) == 2 and 'verified' in text and '(O786)' in head and 'pair 90' in head and 'glow level' in text,
             'stage 3 build writes its sums and verifies: %s' % text)
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    r = cp.check(od, os_, auras=set(), old=(dat, spr), allow_changed=cp.parse_allow('effect:2,3'))
    t.expect(r.ok, 'check_pair append-only passes on the stage 3 pair: ' + r.text())
    new = idt.parse_dat(open(od, 'rb').read(), idt.OUR_KINDS)
    nstore = AF.Store(FX.Spr(os_))
    for i in (2, 3):
        g = new['effect'][i - 1].groups[0]
        lv = set()
        for k in AF.frames_of(g):
            lv |= set(AF.frame(nstore, g, *k)[..., 3].ravel().tolist())
        t.expect(lv == {0, FS.GLOW, 255}, 'effect %d of the built pair has alpha 0 / %d / 255 only: %r' % (i, FS.GLOW, sorted(lv)))
    t.expect(quiet(FS.scan, od, os_, stage=3)[0] == [], 'a stage 3 scan of the built pair lists nothing')
    t.expect(quiet(FS.check, od, os_, assets=90, sums_path=sums, stage=3)[0] == 0, 'stage 3 check: the built pair is redrawn')
    r90, text = quiet(FS.check, dat, spr, assets=90, sums_path=sums, stage=3)
    t.expect(r90 == 0 and 'pending' in text and 'O786' in text, 'stage 3 check: pending while windows-assets has pair 90')
    t.expect(quiet(FS.check, dat, spr, assets=91, sums_path=sums, stage=3)[0] == 1, 'stage 3 check: due from pair 91')
    # chained forms: a stage 2 thing redrawn again by stage 3 counts as redrawn for O777, O769 and fix_pack_fx
    b3, _a3 = FX.read_sums(sums)[('effect', 2)]
    s2 = os.path.join(c.dir, 's2.sums')
    with open(s2, 'w') as f:
        f.write('# test\neffect 2 000000000000000000000000 %s\n' % b3)
    s1 = os.path.join(c.dir, 's1b.sums')
    with open(s1, 'w') as f:
        f.write('# test\neffect 2 111111111111111111111111 000000000000000000000000\n')
    real = (FX.stipple_sums, FX.stipple2_sums, FX.stipple3_sums)
    try:
        FX.stipple_sums = lambda: FX.read_sums(s1)
        FX.stipple2_sums = lambda: FX.read_sums(s2)
        FX.stipple3_sums = lambda: FX.read_sums(sums)
        FX._FORMS.clear()
        t.expect(FS.forms(od, os_, s2, stage=2)[('effect', 2)] == 'after', 'O777 forms: its redrawn form requantised is redrawn')
        t.expect(quiet(FS.check, od, os_, assets=91, sums_path=s2, stage=2)[0] == 0, 'O777 check passes on the stage 3 pair')
        t.expect(FS.forms(od, os_, s1, stage=1)[('effect', 2)] == 'after', 'O769 forms: O769, O777, then O786 is redrawn')
        pk = os.path.join(c.dir, 'pk3.sums')
        with open(pk, 'w') as f:
            f.write('# test\neffect 2 222222222222222222222222 111111111111111111111111\n')
        t.expect(FX.forms(od, os_, FX.read_sums(pk))[('effect', 2)] == 'after', 'fix_pack_fx: fixed, O769, O777, O786 is fixed')
        t.expect(FX.forms(od, os_, FX.read_sums(pk), stipple='last')[('effect', 2)] is None, "fix_pack_fx 'last': stage 3 only")
    finally:
        FX.stipple_sums, FX.stipple2_sums, FX.stipple3_sums = real
        FX._FORMS.clear()
    _, text = quiet(FS.build, od, os_, os.path.join(c.dir, 'out_s3b'), table=tab, sums_path=sums, stage=3)
    t.expect('nothing to do' in text, 'a second stage 3 run writes nothing')
    bad = os.path.join(c.dir, 'bad3s.csv')
    a = AF.args_of(rows[0]['args'])
    for name, args in (('another count', 'fill=%d;drop=%s;soft=%s;stage=3' % (int(a['fill']) + 1, a['drop'], a['soft'])),
                       ('another soft count', 'fill=%s;drop=%s;soft=%d;stage=3' % (a['fill'], a['drop'], int(a['soft']) + 1)),
                       ('no soft count', 'fill=%s;drop=%s;stage=3' % (a['fill'], a['drop']))):
        with open(bad, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f, lineterminator='\n')
            w.writerow(AF.SPEC_COLS)
            w.writerow(['effect', 2, 'unstipple', args, 'test', ''])
        try:
            quiet(FS.build, dat, spr, None, dry_run=True, table=bad, sums_path=os.path.join(c.dir, 'bad3s.sums'), stage=3)
            t.expect(False, 'refused: ' + name)
        except SystemExit:
            pass


def test_committed_table3():
    rows = AF.read_spec(FS.TABLE3)
    sums = FX.read_sums(FS.SUMS3)
    keys = sorted({(r['kind'], r['id']) for r in rows})
    t.expect(len(rows) == len(keys) and len(rows) > 100, 'the stage 3 table: one row a thing (%d)' % len(rows))
    t.expect(all(r['op'] == 'unstipple' and AF.args_of(r['args']).get('stage') == '3' and 'soft' in AF.args_of(r['args'])
                 for r in rows), 'unstipple rows of stage 3 with a soft count')
    t.expect(sorted(sums) == keys and all(b != a for b, a in sums.values()), 'the stage 3 sums name every row, each changes')
    extra = FS.owned_extra()
    t.expect(not any(FS.owned(k, i) or (k, i) in extra for k, i in keys), 'no stage 3 row names a thing another tool holds')
    t.expect(all(FS.STOCK[k] < i <= FS.BAYER_LAST[k] for k, i in keys), 'stage 3 rows: after the stock ids, in the Bayer cut era')
    for want in (3902, 3892, 3945, 4062):
        t.expect(('effect', want) in sums, 'effect %d (O777 left it on purpose) is in the stage 3 table' % want)
    for plain in (500, 600, 719):
        t.expect(('effect', plain) not in sums, 'the plain effect %d is not in the stage 3 table' % plain)
    for r in rows:
        a = AF.args_of(r['args'])
        n = int(a['fill']) + int(a['drop']) + int(a['soft'])
        t.expect(n >= FS.MIN_FILL, '%s %d: at least MIN_FILL changed' % (r['kind'], r['id']))
    s2, s1 = FX.read_sums(FS.SUMS2), FX.read_sums(FS.SUMS)
    import fix_dissolve_tail as FD
    tail = FX.read_sums(FD.SUMS)
    pack = FX.read_sums()
    for k in keys:
        if k in s2:
            t.expect(sums[k][0] == s2[k][1], '%s %d: stage 3 starts from its O777 form' % k)
        elif k in s1:
            t.expect(sums[k][0] == s1[k][1], '%s %d: stage 3 starts from its O769 form' % k)
        elif k in tail:
            t.expect(sums[k][0] == tail[k][1], '%s %d: stage 3 starts from its tail cut form' % k)
        elif k in pack:
            t.expect(sums[k][0] == pack[k][1], '%s %d: stage 3 starts from its fixed form' % k)
    sys.path.insert(0, os.path.join(FS.HERE, '..', '..', '..', 'server', 'tools'))
    import client_pair
    t.expect(client_pair.PAIR_STIPPLE_GLOW == FS.PAIR3 == 91, 'client_pair.PAIR_STIPPLE_GLOW is the pair of stage 3')


def main():
    c = t.Case()
    test_rule()
    test_scan_build_check(c)
    test_committed_table()
    test_stage2_rule()
    test_stage2_scan_build_check(c)
    test_committed_table2()
    test_stage3_rule()
    test_stage3_scan_build_check(c)
    test_committed_table3()
    if t.FAILS:
        print('%d failed' % len(t.FAILS))
        return 1
    print('fix_stipple_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
