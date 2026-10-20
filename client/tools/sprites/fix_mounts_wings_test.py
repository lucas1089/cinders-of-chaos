#!/usr/bin/env python3
"""Tests of fix_mounts_wings.py on a small synthetic pair (needs numpy and Pillow, as the tool).

python3 -I client/tools/sprites/fix_mounts_wings_test.py
"""
import csv
import hashlib
import io
import os
import struct
import sys
import tempfile
from contextlib import redirect_stdout

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_pair as cp  # noqa: E402
import fix_mounts_wings as fm  # noqa: E402
from check_pair_test import record, spr_bytes, group, entry, dat_bytes, YELLOW  # noqa: E402

BODY = (120, 90, 60, 255)
STOCK = list(range(1, 11))      # synthetic stock riders
TARGET = 11                     # a player look without a mounted pattern, displacement 8,8
NEG = 12                        # one with a negative displacement and only a walk group
WINGS_OK = (13, 14)             # synthetic stock wings
WING_LEFT = 15                  # wings 6 px left and up in every direction
WING_EAST = 16                  # wings whose east frames sit 14 px up
MOUNT = 17                      # a mount with no displacement
MOVE = (-6, -10)                # stock: the mounted frame is the standing one moved this much, 3 rows shorter
TRIM = 3


class Pair:
    """frames (64 x 64 RGBA arrays, 2x2 things) -> records and sprite ids, deduplicated."""

    def __init__(self):
        self.recs, self.index = [], {}

    def sid(self, tile):
        on = tile[:, :, 3] > 0
        if not on.any():
            return 0
        rec = record({int(i): tuple(int(v) for v in tile.reshape(1024, 4)[i]) for i in np.nonzero(on.reshape(1024))[0]})
        if rec not in self.index:
            self.recs.append(rec)
            self.index[rec] = len(self.recs)
        return self.index[rec]

    def tiles(self, a):
        """sprite ids of a 64x64 frame in the dat's order (ww, hh from the bottom right)."""
        return [self.sid(a[(1 - hh) * 32:(2 - hh) * 32, (1 - ww) * 32:(2 - ww) * 32]) for hh in range(2) for ww in range(2)]


def rect(x0, y0, w, h, colour=BODY, size=64):
    a = np.zeros((size, size, 4), np.uint8)
    a[y0:y0 + h, x0:x0 + w] = colour
    return a


def mask_of(a):
    m = np.zeros_like(a)
    on = a[:, :, 3] > 0
    m[on] = YELLOW
    return m


def moved(a, dx, dy, trim=0):
    b, _ = fm.shift(a, dx, dy)
    if trim:
        rows = np.nonzero((b[:, :, 3] > 0).sum(1) >= 3)[0]
        b[rows[-1] - trim + 1:] = 0
    return b


def outfit_groups(p, frames, layers, gtypes_phases, pz):
    """frames(group, x, z, phase) -> layer-0 array; the mask layer is made from it. -> list of group bytes."""
    out = []
    for gi, (gtype, phases) in enumerate(gtypes_phases):
        sl = []
        for ph in range(phases):
            for z in range(pz):
                for x in range(4):
                    a = frames(gi, x, z, ph)
                    lay = [a, mask_of(a)][:layers]
                    for la in lay:
                        sl += p.tiles(la)
        # the dat order is phase, z, y, x, layer, hh, ww: the loops above follow it (y = 0 only)
        anim = None
        if phases > 1:
            anim = (0, 0, 0, [100] * (2 * phases))
        out.append(group(sl, w=2, h=2, layers=layers, px=4, pz=pz, phases=phases, gtype=gtype, anim=anim))
    return out


def standing(x):
    return rect(40 + x, 30, 6, 32)                          # a figure of 31 rows above the feet, one per direction


def build(d):
    p = Pair()
    outs = []
    disp88 = b'\x19' + struct.pack('<hh', 8, 8)
    for _ in STOCK:
        def fr(gi, x, z, ph):
            s = standing(x)
            if z == 0:
                return s
            bob = (ph % 2, 0) if gi == 1 else (0, 0)
            return moved(s, MOVE[0] + bob[0], MOVE[1] + bob[1], TRIM)
        outs.append(entry(disp88, outfit_groups(p, fr, 2, [(0, 1), (1, 8)], 2), outfit=True))
    # the target: a different figure, 2 walk phases, no mounted pattern
    outs.append(entry(disp88, outfit_groups(p, lambda gi, x, z, ph: rect(36, 34 - ph, 8, 28), 2, [(0, 1), (1, 2)], 1),
                      outfit=True))
    # negative displacement, walk group only (phase 0 is its idle pose)
    outs.append(entry(b'\x19' + struct.pack('<hh', -32, 0),
                      outfit_groups(p, lambda gi, x, z, ph: rect(30, 30, 8, 30), 1, [(1, 3)], 1), outfit=True))

    def wing(dx=0, dy=0, east=0):
        def fr(gi, x, z, ph):
            a = rect(20, 30, 40, 6, (200, 200, 255, 255)) if x in (0, 2) else rect(44, 20, 6, 40, (200, 200, 255, 255))
            return moved(a, dx, dy - (east if x == 1 else 0))
        return entry(b'', outfit_groups(p, fr, 1, [(0, 1)], 1), outfit=True)
    outs += [wing(), wing(), wing(-6, -6), wing(east=14)]
    outs.append(entry(b'', outfit_groups(p, lambda gi, x, z, ph: rect(20, 40, 44, 20, (60, 40, 20, 255)), 1, [(0, 1)], 1),
                      outfit=True))
    dp, sp = os.path.join(d, 'Tibia.dat'), os.path.join(d, 'Tibia.spr')
    with open(dp, 'wb') as f:
        f.write(dat_bytes([entry(b'', [group([1])])], outs, [], []))
    with open(sp, 'wb') as f:
        f.write(spr_bytes(p.recs))
    return dp, sp


def write_spec(path, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['kind', 'id', 'disp_old', 'disp', 'shift', 'reason'])
        w.writerows(rows)


def run(args):
    buf = io.StringIO()
    with redirect_stdout(buf):
        fm.main(args)
    return buf.getvalue()


def expect_exit(args, needle):
    try:
        run(args)
    except SystemExit as e:
        assert needle in str(e), (needle, str(e))
        return
    raise AssertionError(f'no exit, wanted {needle!r}')


def md5(p):
    return hashlib.md5(open(p, 'rb').read()).hexdigest()


def load(dp, sp):
    return cp.parse_dat(open(dp, 'rb').read())[2]['outfit'], fm.Sprites(sp)


def setup():
    fm.STOCK_RANGE = (STOCK[0], STOCK[-1])
    fm.STOCK_MIN = len(STOCK)
    fm.STOCK_WINGS = WINGS_OK
    fm.BODY_LOOKS = tuple(STOCK[:2])


def test_measure(d):
    dp, sp = build(d)
    outs, spr = load(dp, sp)
    n, stock = fm.measure_stock(outs, spr)
    assert n == len(STOCK), n
    for x, s in enumerate(stock):
        # standing drawn with 8,8, mounted with none: the screen delta is the frame move + 8
        assert s['delta'] == (MOVE[0] + 8, MOVE[1] + 8), (x, s['delta'])
        assert s['trim'] == TRIM and s['h'] == 31, s
        assert s['bob'] == [(p % 2, 0) for p in range(8)], s['bob']
    spr.close()


def test_mounted(d):
    dp, sp = build(d)
    spec = os.path.join(d, 'spec.csv')
    write_spec(spec, [('mounted', TARGET, '', '', '', 't'), ('mounted', NEG, '', '', '', 't')])
    out = os.path.join(d, 'out')
    log = run(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', out, '--spec', spec,
               '--changes-out', os.path.join(d, 'ch.csv')])
    assert 'append-only guard passed' in log, log
    outs, spr = load(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
    old, ospr = load(dp, sp)
    t, o = outs[TARGET - 1], old[TARGET - 1]
    assert [g.pz for g in t.groups] == [2, 2]
    for x in range(4):
        for layer in range(2):
            s = fm.frame(o.groups[0], ospr, x, 0, 0, 0, layer)
            # standing frames unchanged
            assert np.array_equal(fm.frame(t.groups[0], spr, x, 0, 0, 0, layer), s)
            # idle mounted, base and mask layer alike: the stock move, the lowest rows cut (trim 3 * 27 / 31 -> 3)
            assert np.array_equal(fm.frame(t.groups[0], spr, x, 0, 1, 0, layer), moved(s, *MOVE, trim=3)), (x, layer)
            # walk mounted: idle phase 0 moved, + the bob of phases 0 and 4 of the stock cycle (both 0)
            for ph in range(2):
                assert np.array_equal(fm.frame(t.groups[1], spr, x, 0, 1, ph, 0) > 0,
                                      moved(fm.frame(o.groups[0], ospr, x, 0, 0, 0, 0), *MOVE, trim=3) > 0)
    # the negative look: drawn by its own displacement mounted too, so the frame moves by the screen delta only
    t, o = outs[NEG - 1], old[NEG - 1]
    g = o.groups[0]
    for x in range(4):
        s = fm.frame(g, ospr, x, 0, 0, 0)
        got = fm.frame(t.groups[0], spr, x, 0, 1, 0)
        # its figure is 29 rows: trim round(3 * 29 / 31) = 3
        assert np.array_equal(got, moved(s, MOVE[0] + 8, MOVE[1] + 8, trim=3)), x
        # phase 1 and 2 of the walk-only group: stock cycle phases 0 and 4 (bob 0); phase 0 (idle) no bob
        assert np.array_equal(fm.frame(t.groups[0], spr, x, 0, 1, 2), got)
    with open(os.path.join(d, 'ch.csv'), encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    assert [(r['id'], r['field']) for r in rows] == [(str(TARGET), 'pattern z'), (str(NEG), 'pattern z')], rows
    spr.close()
    ospr.close()
    # idempotent: a run on its own output gives the same files
    again = os.path.join(d, 'again')
    run(['build', '--ours-dat', os.path.join(out, 'Tibia.dat'), '--ours-spr', os.path.join(out, 'Tibia.spr'),
         '--out-dir', again, '--spec', spec])
    for f in ('Tibia.dat', 'Tibia.spr'):
        assert md5(os.path.join(out, f)) == md5(os.path.join(again, f)), f
    # deterministic
    out2 = os.path.join(d, 'out2')
    run(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', out2, '--spec', spec])
    for f in ('Tibia.dat', 'Tibia.spr'):
        assert md5(os.path.join(out, f)) == md5(os.path.join(out2, f)), f
    # refusals: a look that is not pattern Z 1 or 2; a wrong input md5
    write_spec(spec, [('mounted', STOCK[0], '', '', '', 't')])
    run(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', os.path.join(d, 'noop'), '--spec', spec])
    assert md5(os.path.join(d, 'noop', 'Tibia.dat')) == md5(dp)        # a stock look: pattern Z 2, a no-op
    expect_exit(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', os.path.join(d, 'x'), '--spec', spec,
                 '--expect-dat-md5', '0' * 32], 'is not')


def test_wings(d):
    dp, sp = build(d)
    outs, spr = load(dp, sp)
    body = fm.body_centre(outs, spr)
    target = fm.stock_wings(outs, spr, body)
    assert not fm.wing_off(fm.wing_errors(outs[WINGS_OK[0] - 1], spr, body, target))
    err = fm.wing_errors(outs[WING_LEFT - 1], spr, body, target)
    assert fm.wing_off(err) and all(abs(e[0] + 6) < 0.01 for e in err), err
    assert fm.wing_fit(outs[WING_LEFT - 1], spr, body, target) == (-6, -6)
    ee = fm.wing_errors(outs[WING_EAST - 1], spr, body, target)
    assert abs(ee[1][0] + 14) < 0.01 and fm.wing_axis_error(ee)[1] == -7, ee
    assert fm.wing_fit(outs[WING_EAST - 1], spr, body, target) == (0, -7)
    assert fm.wing_bad(fm.wing_errors(outs[WING_EAST - 1], spr, body, target, (0, -7))) == [1, 3]   # 7 off each
    spr.close()
    spec = os.path.join(d, 'spec.csv')
    write_spec(spec, [('wings', WING_LEFT, '0,0', '-6,-6', '', 't'),
                      ('wings', WING_EAST, '0,0', '0,-7', 'east=0 7;west=0 -7', 't')])
    out = os.path.join(d, 'out')
    run(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', out, '--spec', spec,
         '--changes-out', os.path.join(d, 'ch.csv')])
    new, nspr = load(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
    old, ospr = load(dp, sp)
    assert fm.disp(new[WING_LEFT - 1]) == (-6, -6)
    assert fm.groups_bytes(new[WING_LEFT - 1]) == fm.groups_bytes(old[WING_LEFT - 1])
    t, o = new[WING_EAST - 1], old[WING_EAST - 1]
    assert fm.disp(t) == (0, -7)
    for x in range(4):
        a, b = fm.frame(o.groups[0], ospr, x), fm.frame(t.groups[0], nspr, x)
        b = b[b.shape[0] - 64:, b.shape[1] - 64:]
        want = {1: moved(a, 0, 7), 3: moved(a, 0, -7)}.get(x, a)
        assert np.array_equal(b, want), x
    err = fm.wing_errors(t, nspr, body, target)
    assert all(abs(e[0]) < 0.01 for e in err), err
    with open(os.path.join(d, 'ch.csv'), encoding='utf-8') as f:
        fields = [(r['id'], r['field']) for r in csv.DictReader(f)]
    assert fields == [(str(WING_LEFT), 'displacement'), (str(WING_EAST), 'frames'), (str(WING_EAST), 'displacement')], fields
    nspr.close()
    ospr.close()
    # idempotent: the new displacement marks a row applied
    again = os.path.join(d, 'again')
    run(['build', '--ours-dat', os.path.join(out, 'Tibia.dat'), '--ours-spr', os.path.join(out, 'Tibia.spr'),
         '--out-dir', again, '--spec', spec])
    for f in ('Tibia.dat', 'Tibia.spr'):
        assert md5(os.path.join(out, f)) == md5(os.path.join(again, f)), f
    # refusals
    x = os.path.join(d, 'x')
    write_spec(spec, [('wings', WING_LEFT, '0,0', '0,-6', '', 't')])
    expect_exit(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', x, '--spec', spec], 'an axis still off')
    write_spec(spec, [('wings', WING_EAST, '0,0', '0,-7', '', 't')])
    expect_exit(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', x, '--spec', spec], 'west across')
    write_spec(spec, [('wings', WING_LEFT, '1,1', '-6,-6', '', 't')])
    expect_exit(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', x, '--spec', spec], 'measured on')
    write_spec(spec, [('wings', WING_LEFT, '0,0', '0,0', '', 't')])
    expect_exit(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', x, '--spec', spec], 'are the same')
    write_spec(spec, [('wings', WING_EAST, '0,0', '0,-7', 'east=20 7;west=0 -7', 't')])
    expect_exit(['build', '--ours-dat', dp, '--ours-spr', sp, '--out-dir', x, '--spec', spec], 'right / bottom edge')


def test_sheet(d):
    dp, sp = build(d)
    png = os.path.join(d, 's.png')
    run(['sheet', '--dat', dp, '--spr', sp, '--out', png, '--riders', f'{STOCK[0]},{TARGET}', '--mounts', str(MOUNT),
         '--wings', str(WING_LEFT)])
    from PIL import Image
    im = Image.open(png)
    assert im.size == (2 * 4 * 128 * 3 // 2, 3 * 128 * 3 // 2), im.size
    # the scan prints the stock measurements and the plan
    log = run(['scan', '--ours-dat', dp, '--ours-spr', sp, '--looks', str(TARGET), '--wings', f'{WING_LEFT}'])
    assert 'stock riders: 10' in log and f'{TARGET}: pattern z [1]' in log and 'fix: disp -6,-6' in log, log


def main():
    setup()
    for test in (test_measure, test_mounted, test_wings, test_sheet):
        with tempfile.TemporaryDirectory() as d:
            test(d)
        print(f'ok {test.__name__}')
    print('fix_mounts_wings_test: all passed')


if __name__ == '__main__':
    main()
