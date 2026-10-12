#!/usr/bin/env python3
"""Tests of fix_pair_warnings.py on a small synthetic pair (no real pair needed, no numpy / Pillow).

python3 -I client/tools/sprites/fix_pair_warnings_test.py
"""
import csv
import hashlib
import io
import os
import struct
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_pair as cp  # noqa: E402
import fix_pair_warnings as fx  # noqa: E402
from check_pair_test import record, spr_bytes, group, entry, dat_bytes, RED, YELLOW  # noqa: E402

ART = {0: (10, 20, 30, 255), 1: (200, 240, 250, 255), 33: RED}
ART2 = {5: (90, 60, 30, 255), 6: (240, 235, 220, 255)}


def build(d):
    """sprites: 1 art, 2 mask, 3 copy of 1 (art in a mask slot), 4 art2, 5 mask of art2, 6 empty slot, 7 art,
    8 a mask that is neither art copy nor template colours."""
    recs = [record(ART), record({0: YELLOW, 1: YELLOW}), record(ART), record(ART2), record({5: RED}), None,
            record(ART), record({0: (1, 2, 3, 255)})]
    items = [entry(groups=[group([1, 7, 1], phases=3, anim=(0, 0, 0, [0, 0, 100, 100, 0, 0]))])]
    # outfit 1: 2 layers, 4 dirs, 3 addon rows; base masks real; addon 1 masks are art copies, addon 2 real masks
    s = []
    for y in range(3):
        for x in range(4):
            if y == 0:
                s += [1, 2]
            elif y == 1:
                s += [1, 3]
            else:
                s += [4, 5]
    o1 = entry(groups=[group(s, layers=2, px=4, py=3, gtype=0), group(s, layers=2, px=4, py=3, gtype=1)], outfit=True)
    # outfit 2: idle group with 2 addon rows, walk group with 1
    o2 = entry(groups=[group([1, 1, 1, 1, 7, 7, 7, 7], px=4, py=2, gtype=0), group([1, 1, 1, 1], px=4, gtype=1)],
               outfit=True)
    # outfit 3: one slot points at the empty slot 6
    o3 = entry(groups=[group([1, 6, 1, 1], px=4, gtype=0)], outfit=True)
    missiles = [entry(groups=[group([1] * 18, px=3, py=3, phases=2, anim=(0, 0, 0, [0] * 4))])]
    dp, sp = os.path.join(d, 'Tibia.dat'), os.path.join(d, 'Tibia.spr')
    with open(dp, 'wb') as f:
        f.write(dat_bytes(items, [o1, o2, o3], [], missiles))
    with open(sp, 'wb') as f:
        f.write(spr_bytes(recs))
    return dp, sp


SPEC = [
    ('durations', 'item', 100, '0', '0:100', 'test'),
    ('durations', 'item', 100, '0', '2:100', 'test'),
    ('durations', 'missile', 1, '0', '0-1:100', 'test'),
    ('clear_addon_masks', 'outfit', 1, '*', '1-2', 'test'),
    ('drop_addon_rows', 'outfit', 2, '0', '1', 'test'),
    ('zero_empty', 'outfit', 3, '*', '6', 'test'),
]


def write_spec(path, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['kind', 'cat', 'id', 'group', 'arg', 'reason'])
        w.writerows(rows)


def run(args):
    buf = io.StringIO()
    with redirect_stdout(buf):
        fx.main(args)
    return buf.getvalue()


def md5(p):
    return hashlib.md5(open(p, 'rb').read()).hexdigest()


def expect_exit(args, needle):
    try:
        run(args)
    except SystemExit as e:
        assert needle in str(e), (needle, str(e))
        return
    raise AssertionError(f'no exit, wanted {needle!r}')


def disp_flag(x, y):
    return b'\x19' + struct.pack('<hh', x, y)


def build_disp(d):
    """outfits for the displacement kind (2x2, 4 directions, art in the bottom-right tile of each direction):
    1 no flags but animateAlways, art on the frame's bottom rows (stands low) -> 8,8 inserted before byte 28
    2 displacement 0,0, the same art -> replaced by 8,8          3 art 8 px clear of the frame edges (drawn for 0)
    4 1x1                                                      5 already 8,8 (the reference look of the scan)
    6 displacement 4,4                                         7 art at the edges but its feet line high (a thin
                                                                 line down the right edge, a 3 px row at row 20)"""
    low = {y * 32 + x: (90, 60, 30, 255) for y in range(26, 32) for x in range(8, 32)}
    clear = {y * 32 + x: (90, 60, 30, 255) for y in range(18, 24) for x in range(0, 24)}
    thin = {y * 32 + 31: (90, 60, 30, 255) for y in range(32)}
    thin.update({20 * 32 + x: (90, 60, 30, 255) for x in (28, 29, 30)})
    recs = [record(low), record(clear), record(thin)]

    def big(sid):
        sl = []
        for x in range(4):
            sl += [sid, 0, 0, 0]
        return group(sl, w=2, h=2, px=4, gtype=0)
    outs = [entry(b'\x1c', [big(1)], outfit=True), entry(disp_flag(0, 0), [big(1)], outfit=True),
            entry(b'', [big(2)], outfit=True), entry(b'', [group([1, 1, 1, 1], px=4, gtype=0)], outfit=True),
            entry(disp_flag(8, 8), [big(1)], outfit=True), entry(disp_flag(4, 4), [big(1)], outfit=True),
            entry(b'', [big(3)], outfit=True)]
    dp, sp = os.path.join(d, 'Tibia.dat'), os.path.join(d, 'Tibia.spr')
    with open(dp, 'wb') as f:
        f.write(dat_bytes([], outs, [], []))
    with open(sp, 'wb') as f:
        f.write(spr_bytes(recs))
    return dp, sp


def test_displacement(d):
    src = os.path.join(d, 'dsrc'); os.makedirs(src)
    dp, sp = build_disp(src)
    spec = os.path.join(d, 'disp.csv')
    write_spec(spec, [('displacement', 'outfit', 1, '*', '8,8', 't'), ('displacement', 'outfit', 2, '*', '8,8', 't'),
                      ('displacement', 'outfit', 5, '*', '8,8', 't')])
    out, out2 = os.path.join(d, 'dout'), os.path.join(d, 'dout2')
    ch = os.path.join(d, 'dchanges.csv')
    txt = run(['--ours-dat', dp, '--ours-spr', sp, '--out-dir', out, '--spec', spec, '--changes-out', ch])
    assert "'outfit:1,2'" in txt and txt.startswith('2 field changes in 2 things'), txt
    od = os.path.join(out, 'Tibia.dat')
    data, old = open(od, 'rb').read(), open(dp, 'rb').read()
    assert len(data) == len(old) + 5                     # one flag inserted, one replaced
    _, _, th, _ = cp.parse_dat(data, None)
    o = th['outfit']
    assert [b for b, _, _ in o[0].flags] == [25, 28] and o[0].flag('displacement') == (8, 8), o[0].flags
    assert [(b, v) for b, _, v in o[1].flags] == [(25, (8, 8))]
    _, _, th0, _ = cp.parse_dat(old, None)
    for a, b in zip(th0['outfit'], o):
        assert [fx.groups_sig(g) for g in a.groups] == [fx.groups_sig(g) for g in b.groups]   # sprites untouched
    for k in range(2, 7):
        assert old[th0['outfit'][k].start:th0['outfit'][k].end] == data[o[k].start:o[k].end]
    rows = list(csv.DictReader(open(ch, encoding='utf-8')))
    assert [(r['id'], r['field'], r['old'], r['new']) for r in rows] == [
        ('1', 'displacement', 'none', '8,8'), ('2', 'displacement', '0,0', '8,8')], rows
    rep = cp.check(od, os.path.join(out, 'Tibia.spr'), old=(dp, sp), new_only=True, allow_changed=cp.parse_allow('outfit:1,2'))
    assert rep.ok, rep.text()
    # idempotent
    txt = run(['--ours-dat', od, '--ours-spr', os.path.join(out, 'Tibia.spr'), '--out-dir', out2, '--spec', spec,
               '--link-spr'])
    assert txt.startswith('0 field changes'), txt
    assert md5(od) == md5(os.path.join(out2, 'Tibia.dat'))
    # premise refusals
    bad = os.path.join(d, 'dbad.csv')
    a = ['--ours-dat', dp, '--ours-spr', sp, '--out-dir', os.path.join(d, 'dx'), '--spec', bad]
    for row, needle in ((('displacement', 'outfit', 3, '*', '8,8', 't'), 'drawn for no displacement'),
                        (('displacement', 'outfit', 4, '*', '8,8', 't'), 'not 2x2 or larger'),
                        (('displacement', 'outfit', 6, '*', '8,8', 't'), 'already has displacement 4,4'),
                        (('displacement', 'outfit', 7, '*', '8,8', 't'), 'does not stand low'),
                        (('displacement', 'outfit', 1, '0', '8,8', 't'), 'group must be "*"'),
                        (('displacement', 'outfit', 1, '*', '8', 't'), 'is not "X,Y"'),
                        (('displacement', 'outfit', 1, '*', '0,0', 't'), 'out of range')):
        write_spec(bad, [row])
        expect_exit(a, needle)
    # the scan lists the low looks (1 no flag, 2 0,0) and outfit 7 (premise fails), not 3 / 4 / 5 / 6
    txt = run(['--ours-dat', dp, '--ours-spr', sp, '--scan-displacement', '--looks', '1-7'])
    assert '1 looks with displacement 8,8: feet line median 24' in txt, txt
    listed = [line.split(':')[0].strip() for line in txt.splitlines() if line.startswith('  outfit')]
    assert listed == ['outfit 1', 'outfit 2', 'outfit 7'], txt
    assert txt.count('premise ok') == 2 and 'premise fails' in txt, txt


def main():
    with tempfile.TemporaryDirectory() as d:
        test_displacement(d)
        src = os.path.join(d, 'src'); os.makedirs(src)
        dp, sp = build(src)
        before = cp.check(dp, sp, auras=set())
        codes = before.codes('warning')
        assert {'anim-zero', 'group-mismatch', 'sprite-empty-slot'} <= codes, codes
        spec = os.path.join(d, 'fixes.csv'); write_spec(spec, SPEC)
        out, out2, out3 = (os.path.join(d, n) for n in ('out', 'out2', 'out3'))
        ch = os.path.join(d, 'changes.csv')
        txt = run(['--ours-dat', dp, '--ours-spr', sp, '--out-dir', out, '--spec', spec, '--changes-out', ch])
        assert "outfit:1,2,3" in txt and 'item:100' in txt and 'missile:1' in txt, txt
        after = cp.check(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'), auras=set())
        assert after.ok and after.count('warning') == 0, after.text()
        # exactly the expected edits
        _, _, th, _ = cp.parse_dat(open(os.path.join(out, 'Tibia.dat'), 'rb').read(), None)
        assert list(th['item'][0].groups[0].anim[3]) == [100] * 6
        assert list(th['missile'][0].groups[0].anim[3]) == [100] * 4
        o1 = th['outfit'][0].groups[0].sprites
        assert list(o1[:8]) == [1, 2] * 4 and list(o1[8:16]) == [1, 0] * 4 and list(o1[16:24]) == [4, 5] * 4, o1
        g0, g1 = th['outfit'][1].groups
        assert (g0.py, list(g0.sprites)) == (1, [1, 1, 1, 1]) and g1.py == 1
        assert list(th['outfit'][2].groups[0].sprites) == [1, 0, 1, 1]
        rows = list(csv.DictReader(open(ch, encoding='utf-8')))
        assert len(rows) == 2 + 2 + 8 + 2 + 1, len(rows)       # durations 2+2, masks 2 groups x 4, drop 2, zero 1
        assert md5(os.path.join(out, 'Tibia.spr')) == md5(sp)
        # deterministic and idempotent
        run(['--ours-dat', dp, '--ours-spr', sp, '--out-dir', out2, '--spec', spec])
        assert md5(os.path.join(out, 'Tibia.dat')) == md5(os.path.join(out2, 'Tibia.dat'))
        txt = run(['--ours-dat', os.path.join(out, 'Tibia.dat'), '--ours-spr', os.path.join(out, 'Tibia.spr'),
                   '--out-dir', out3, '--spec', spec, '--link-spr'])
        assert txt.startswith('0 field changes'), txt
        assert md5(os.path.join(out, 'Tibia.dat')) == md5(os.path.join(out3, 'Tibia.dat'))
        # append-only with exactly the changed things passes, one fewer fails
        rep = cp.check(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'), old=(dp, sp), new_only=True,
                       allow_changed=cp.parse_allow('item:100;outfit:1,2,3;missile:1'))
        assert rep.ok, rep.text()
        rep = cp.check(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'), old=(dp, sp), new_only=True,
                       allow_changed=cp.parse_allow('item:100;outfit:1,2'))
        assert not rep.ok
        # refusals
        bad = os.path.join(d, 'bad.csv')
        a = ['--ours-dat', dp, '--ours-spr', sp, '--out-dir', os.path.join(d, 'x'), '--spec', bad]
        write_spec(bad, [('durations', 'item', 100, '0', '1:50', 't')])
        expect_exit(a, 'not 0 ms')
        write_spec(bad, [('zero_empty', 'outfit', 3, '*', '1', 't')])
        expect_exit(a, 'not an empty spr slot')
        write_spec(bad, [('drop_addon_rows', 'outfit', 1, '0', '1', 't')])
        expect_exit(a, 'still differ')
        write_spec(bad, [('durations', 'item', 100, '0', '0:100', 't'), ('durations', 'item', 100, '0', '0:100', 't')])
        expect_exit(a, 'twice')
        write_spec(bad, [('clear_addon_masks', 'outfit', 1, '*', '1-2', 't')])
        expect_exit(a + ['--expect-dat-md5', '0' * 32], 'md5 is not')
        # a mask slot holding neither an art copy nor template colours stops the run
        with open(sp, 'r+b') as f:
            data = f.read()
        recs = [record(ART), record({0: YELLOW, 1: YELLOW}), record(ART), record(ART2), record({5: (1, 2, 3, 255)})]
        with open(sp, 'wb') as f:
            f.write(spr_bytes(recs + [None, record(ART), record({0: (1, 2, 3, 255)})]))
        write_spec(bad, [('clear_addon_masks', 'outfit', 1, '*', '1-2', 't')])
        expect_exit(a, 'neither a copy of the art nor a colour mask')
        with open(sp, 'wb') as f:
            f.write(data)
    print('fix_pair_warnings_test: ok')


if __name__ == '__main__':
    main()
