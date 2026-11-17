#!/usr/bin/env python3
"""Tests of gen_class_redraw.py (O618): the table, the placing, the outline, the colour template, the stock bar rules.

    python3 -I client/tools/sprites/gen_class_redraw_test.py
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_class_redraw as G  # noqa: E402

FAILS = []


def ok(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def figure(lean=16, shade=0, step=0, mirror=False, lift=0):
    """a leaning figure on a 56 px canvas: a grey body with a red band, head up and left, two feet"""
    a = np.zeros((56, 56, 4), np.uint8)
    for i in range(30):
        y = 10 + i
        x0 = 14 + int(round(lean * i / 29.0))
        for x in range(x0, x0 + 12):
            red = 8 <= i < 20
            a[y, x] = (200 - shade, 30, 30, 255) if red else (120 + shade + (x % 3) * 20, 120 + shade, 130, 255)
    y = 40
    b = lean - 16
    a[y - lift:y + 2, 30 + b + step:33 + b + step] = (90, 80, 70, 255)
    a[y:y + 2, 36 + b - step:39 + b - step] = (90, 80, 70, 255)
    return a[:, ::-1].copy() if mirror else a


def write_src(root, key, anim='walkv3', mirror_west=False):
    st = os.path.join(root, key, 'Idle')
    for i, d in enumerate(G.DIR_NAMES):
        os.makedirs(os.path.join(st, 'rotations'), exist_ok=True)
        ref = figure(shade=i * 6)
        if d == 'west' and mirror_west:
            ref = figure(shade=6, mirror=True)
        Image.fromarray(ref).save(os.path.join(st, 'rotations', d + '.png'))
        ad = os.path.join(st, 'animations', anim, d)
        os.makedirs(ad)
        for p in range(G.WALK):
            Image.fromarray(figure(shade=i * 6, step=p % 4, lift=p // 4)).save(os.path.join(ad, 'frame_%03d.png' % p))


def main():
    row = {'key': 'test', 'name': 'Test', 'looks': '1508+2071', 'walk': '8', 'ms': '300', 'disp': '8', 'accent': '335-20',
           'anim': 'walkv3', 'idle': '1', 'addons': '0', 'prompt': 'a figure'}
    # ---- the table
    ok(G.problems([row], {'test': 'x'}) == [], 'a good row has no problem')
    ok(any('two rows' in p for p in G.problems([row, dict(row, key='b')], {'test': 'x', 'b': 'x'})), 'a look on two rows is refused')
    ok(any('walk' in p for p in G.problems([dict(row, walk='2')], {'test': 'x'})), 'a walk of 2 pictures is refused')
    ok(any('sums' in p for p in G.problems([row], {})), 'a row with no sums row is refused')
    ok(any('accent' in p for p in G.problems([dict(row, accent='red')], {'test': 'x'})), 'an accent that is no hue range is refused')
    ok(G.looks_of(row) == [1508, 2071], 'looks joined by +')
    # ---- the outline
    a = G.outline(figure())
    ok(G.rim_dark(a) == 1.0, 'every rim pixel is dark after the outline step')
    m = a[..., 3] > 0
    inner = m & ~G.rim_of(m)
    ok((a[inner] == figure()[inner]).all(), 'the outline step leaves the inner pixels alone')
    # ---- a sheet from a download
    with tempfile.TemporaryDirectory() as tmp:
        write_src(tmp, 'test')
        s = G.make_sheet(row, tmp)
        ok(s.shape == (9 * 64, 8 * 64, 4), 'the sheet is 9 rows of 8 cells')
        n = G.numbers(row, s)
        ok(G.sheet_problems(row, s) == [], 'the sheet of a leaning figure passes: %s' % G.sheet_problems(row, s))
        ok(abs(n['stand'][0] - 16.5) <= 1 and abs(n['stand'][1] - 20) <= 1, 'the look stands on the O585 point: %s' % (n['stand'],))
        ok(n['walk'] == 8 and n['dirs'] == 4 and n['soft'] == 0, 'walk of 8, four directions, hard alpha')
        ok(n['zones'] >= 2 and n['mask'] > 0.1 and n['mask_outside'] == 0, 'the template marks the red band in zones: %s' % n)
        art, tpl = G.cell(s, 0, 2, 0), G.cell(s, 1, 2, 0)
        tm = tpl[..., 3] > 0
        ok((art[tm][:, 0] == art[tm][:, 1]).all() and (art[tm][:, 1] == art[tm][:, 2]).all(), 'the art is grey under the template')
        t = G.tinted(s, 2, 0, [(0, 0, 255)] * 4)
        ok((t[tm][:, 0] == 0).all() and t[tm][:, 2].max() > 150, 'a blue player colour makes the band blue')
        ok((t[~tm] == art[~tm]).all(), 'the tint leaves the rest alone')
        ok(G.numbers(row, G.make_sheet(row, tmp)) == n, 'the same download gives the same sheet')
        # the walk needs room: a wrong disp is refused
        try:
            G.make_sheet(dict(row, disp='5'), tmp)
            ok(False, 'a disp lower than needed is refused')
        except SystemExit as e:
            ok('highest displacement' in str(e), 'a disp lower than needed is refused: %s' % e)
        # an upright figure with a mirrored west fails the bar
        up = os.path.join(tmp, 'up')
        st = os.path.join(up, 'test', 'Idle')
        for d in G.DIR_NAMES:
            os.makedirs(os.path.join(st, 'rotations'), exist_ok=True)
            Image.fromarray(figure(lean=0)).save(os.path.join(st, 'rotations', d + '.png'))
            ad = os.path.join(st, 'animations', 'walkv3', d)
            os.makedirs(ad)
            for p in range(G.WALK):
                Image.fromarray(figure(lean=0, step=p % 4, lift=p // 4)).save(os.path.join(ad, 'frame_%03d.png' % p))
        bad = G.sheet_problems(row, G.make_sheet(row, up))
        ok(any('lean' in b for b in bad), 'an upright figure is refused: %s' % bad)
        ok(any('different standing' in b or 'mirrored' in b for b in bad), 'east = mirrored west or equal directions are refused: %s' % bad)
    # ---- the importer rows
    old = G.rows
    G.rows = lambda path=None: [row]
    try:
        tr = G.things_rows()
    finally:
        G.rows = old
    ok([r['extra'].split('look=')[1] for r in tr] == ['1508', '2071'], 'one replace row per look')
    ok(all(r['mode'] == 'replace' and r['phases'] == '1+8' and r['flags'] == 'displacement:8:8' and 'layers=2' in r['extra'] for r in tr),
       'the rows rewrite the look in place: idle 1, walk 8, two layers, the row displacement')
    # ---- accents: several ranges, a minimum saturation, white cloth
    ok(G.accents_of(dict(row, accent='335-20')) == [(335.0, 20.0, G.SAT_MIN)], 'one range, the default saturation')
    ok(G.accents_of(dict(row, accent='15-35@0.62+white+205-240')) == [(15.0, 35.0, 0.62), ('white',), (205.0, 240.0, G.SAT_MIN)],
       'ranges joined by +, @ a saturation, white')
    ok(any('accent' in p for p in G.problems([dict(row, accent='10-30@2')], {'test': 'x'})), 'a saturation over 1 is refused')
    ok(G.problems([dict(row, accent='15-35@0.6+white')], {'test': 'x'}) == [], 'a good several range accent')
    ok(any('idle' in p for p in G.problems([dict(row, idle='2')], {'test': 'x'})), 'an idle of 2 pictures is refused')
    ok(any('addons' in p for p in G.problems([dict(row, addons='cape')], {'test': 'x'})), 'an unknown addon kind is refused')
    pale = np.zeros((20, 20, 4), np.uint8)
    pale[3:17, 3:17] = (235, 235, 240, 255)
    pale[8, 8] = (20, 60, 200, 255)
    ok(G.accent_mask(pale, [('white',)])[10, 10] and not G.accent_mask(pale, [('white',)])[8, 8], 'white is the pale unsaturated cloth')
    ok(G.accent_mask(pale, [(200.0, 240.0, 0.32)])[8, 8] and not G.accent_mask(pale, [(200.0, 240.0, 0.32)])[10, 10], 'a hue range is the saturated cloth')
    # ---- an idle of 4 pictures (a breath) and the two addon overlays of a kind
    with tempfile.TemporaryDirectory() as tmp:
        write_src(tmp, 'test')
        r4 = dict(row, idle='4', addons='templar')
        s4 = G.make_sheet(r4, tmp)
        ok(s4.shape == (12 * 64, 24 * 64, 4), 'idle 4 + walk 8 rows, three addon columns of 8 cells: %s' % (s4.shape,))
        n4 = G.numbers(r4, s4)
        ok(n4['walk'] == 8 and n4['dirs'] == 4 and n4['mask_outside'] == 0 and n4['soft'] == 0, 'the numbers of a sheet with idle and addons: %s' % n4)
        ok(len({G.cell(s4, 0, 2, p).tobytes() for p in range(4)}) >= 2, 'the breath: the idle pictures differ')
        for kind in G.ADDON_KINDS:
            r5 = dict(row, addons=kind)
            s5 = G.make_sheet(r5, tmp)
            for y in (1, 2):
                for x in range(4):
                    for p in (0, 3, 8):
                        o = G.cell(s5, 0, x, p, y)
                        ok((o[..., 3] > 0).sum() > 6 and ((o[..., 3] == 0) | (o[..., 3] == 255)).all(), '%s addon %d, direction %d, picture %d is drawn, hard alpha' % (kind, y, x, p))
                        ok((G.cell(s5, 1, x, p, y)[..., 3] == 0).all(), '%s addon %d has no template layer' % (kind, y))
        r_idle = dict(row, idle='4', addons='monk')
        old = G.rows
        G.rows = lambda path=None: [r_idle]
        try:
            tr = G.things_rows()
        finally:
            G.rows = old
        ok(tr[0]['phases'] == '4+8' and 'addons=3' in tr[0]['extra'] and 'durs0=' in tr[0]['extra'], 'the importer row of idle 4 and addons: %s' % tr[0]['extra'])
    # ---- a few pixels over the edge of the cell are cut, a figure that does not fit is refused
    def wide_src(root, tips):
        st = os.path.join(root, 'wide', 'Idle')
        for i, d in enumerate(G.DIR_NAMES):
            os.makedirs(os.path.join(st, 'rotations'), exist_ok=True)
            big = np.zeros((100, 100, 4), np.uint8)
            big[30:86, 30:86] = figure(shade=i * 6)
            Image.fromarray(big).save(os.path.join(st, 'rotations', d + '.png'))
            ad = os.path.join(st, 'animations', 'walkv3', d)
            os.makedirs(ad)
            for pidx in range(G.WALK):
                b = np.zeros((100, 100, 4), np.uint8)
                b[30:86, 30:86] = figure(shade=i * 6, step=pidx % 4, lift=pidx // 4)
                if tips == 'all' or (tips == 'one' and d == 'west' and pidx == 3):
                    b[50, 1] = (200, 200, 200, 255)             # a long weapon tip, far left of the figure
                Image.fromarray(b).save(os.path.join(ad, 'frame_%03d.png' % pidx))
    with tempfile.TemporaryDirectory() as tmp:
        wide_src(tmp, 'one')
        sw = G.make_sheet(dict(row, key='wide', disp='auto'), tmp)
        ok(sw.shape == (9 * 64, 8 * 64, 4), 'a tip over the edge in one picture is cut, the sheet is made')
    with tempfile.TemporaryDirectory() as tmp:
        wide_src(tmp, 'all')
        try:
            G.make_sheet(dict(row, key='wide', disp='auto'), tmp)
            ok(False, 'a figure that does not fit is refused')
        except SystemExit as e:
            ok('fall over the edge' in str(e), 'a figure that does not fit is refused: %s' % e)
    # ---- the committed table and sheets
    ok(G.problems() == [], 'the committed table: %s' % G.problems())
    for r in G.rows():
        ok(G.sheet_problems(r) == [], 'the committed sheet %s: %s' % (r['key'], G.sheet_problems(r)))
    print('gen_class_redraw_test: %s' % ('%d FAILED' % len(FAILS) if FAILS else 'ok'))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())
