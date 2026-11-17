#!/usr/bin/env python3
"""Tests of gen_drawn_wings.py (O581): the drawing rules hold on every frame of every design (numpy, Pillow; no pair).
And of the table of the existing wings (O583, gen_drawn_wings_families.py): every row of drawn_wings/designs.csv is
drawn and holds the same bar (docs/SPRITE_STYLE.md "Wings"), no two rows give the same pictures, the generated files
are current, the pair step on a synthetic pair, the torso rule against the fixtures the C++ header reads.
And of the likeness rounds (O587, O590): every row has its measured numbers and no picture data (the strips of
gen_drawn_wings_strip.py, six zone colours, the beat), a strip gives the measured shape again, east and west are the
face-on views turned, the mould, a haze is one glow level, the score, the fit preview takes player looks only.

python3 -I client/tools/sprites/gen_drawn_wings_test.py
"""
import os
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_drawn_wings as gd  # noqa: E402
import gen_drawn_wings_families as fm  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


S, F = gd.SIZE, gd.FRAMES

# ---- the kit
sq = gd.poly_mask([(10, 10), (20, 10), (20, 16), (10, 16)])
check(sq.sum() == 60 and sq[10, 10] and sq[15, 19] and not sq[16, 10] and not sq[10, 20], 'poly_mask fills pixel centres')
check(gd.disc_mask(30.5, 30.5, 0.6).sum() == 1, 'a disc under one pixel wide is one pixel')
idx = gd.edge_shade(sq, 3, 2, 1)
check(idx[10, 12] == 3 and idx[12, 10] == 3 and idx[15, 15] == 1 and idx[13, 19] == 1 and idx[12, 14] == 2,
      'edge_shade: lit top and left, dark bottom and right')
c = gd.Canvas((1, 2, 3))
c.piece(sq, idx, ((0, 0, 0), (50, 50, 50), (100, 100, 100), (200, 200, 200)))
c.spark(40, 40, (250, 250, 0), 1)
c.spark(12, 9, (250, 250, 0), 1)             # on the outline ring: not painted
c.spark(60, 60, (9, 9, 9), 0)
img = c.finish()
check(tuple(img[9, 12]) == (1, 2, 3, 255), 'the ring is the outline colour and a spark does not repaint it')
check(tuple(img[40, 40]) == (250, 250, 0, 255) and img[40, 41, 3] == gd.GLOW_ALPHA and img[39, 40, 3] == gd.GLOW_ALPHA,
      'a spark is a core with glow arms')
check(img[60, 60, 3] == gd.GLOW_ALPHA and img[41, 41, 3] == 0, 'a glow dot; no glow on the diagonal')
back = np.zeros((S, S, 4), np.uint8)
front = np.zeros((S, S, 4), np.uint8)
back[5, 5] = (10, 10, 10, 255)
front[5, 5] = (99, 99, 99, gd.GLOW_ALPHA)
front[6, 6] = (99, 99, 99, gd.GLOW_ALPHA)
front[7, 7] = (7, 7, 7, 255)
m = gd.merge(back, front)
check(tuple(m[5, 5]) == (10, 10, 10, 255) and m[6, 6, 3] == gd.GLOW_ALPHA and tuple(m[7, 7]) == (7, 7, 7, 255),
      'merge: front over back, a glow pixel never repaints an opaque one')
check(len(gd.KEYS) == 6 and len(set(gd.KEYS)) == 6, 'six designs')
check(gd.anchor_row() == {d: gd.ANCHOR[0] - 64 for d in gd.DIRS}, 'the wings centre row is the anchor')
p0 = gd.project((0, 0, 0), 'south')
check(abs(p0[0] - gd.ANCHOR[0]) < 1e-9 and abs(p0[1] - gd.ANCHOR[1]) < 1e-9, 'the model origin is the anchor')
check(gd.project((0, 0, -5), 'south')[2] < 0 < gd.project((0, 0, -5), 'north')[2], 'the back is behind when facing south')
check(gd.project((0, 0, -5), 'east')[0] < gd.ANCHOR[0] < gd.project((0, 0, -5), 'west')[0], 'the back is left when facing east')


def touches_open(alpha):
    """opaque pixels with a transparent 4-neighbour"""
    op = alpha == 255
    clear = alpha == 0
    near = np.zeros_like(op)
    near[1:, :] |= clear[:-1, :]
    near[:-1, :] |= clear[1:, :]
    near[:, 1:] |= clear[:, :-1]
    near[:, :-1] |= clear[:, 1:]
    return op & near


def frame_rules(img, outline, what):
    a = img[..., 3]
    check(set(np.unique(a).tolist()) <= {0, 255, gd.GLOW_ALPHA}, what + ': alpha is 0, 255 or the glow level')
    edge = touches_open(a)
    bad = edge & ~(img[..., :3] == np.asarray(outline, np.uint8)).all(axis=2)
    check(not bad.any(), what + ': %d edge pixels are not the outline colour' % int(bad.sum()))
    check(not (a[0, :].any() or a[-1, :].any() or a[:, 0].any() or a[:, -1].any()), what + ': art touches the cell border')
    check(not img[a == 0][:, :3].any(), what + ': a transparent pixel carries colour')


# ---- every design, every frame
for key, title, outline, fn, pivot in gd.DESIGNS:
    frames = gd.render(key)
    again = gd.render(key)
    glow = 0
    used = {'back': 0, 'front': 0}
    merged = {}
    for d in gd.DIRS:
        check(len(frames[d]) == F, '%s %s: 16 frames' % (key, d))
        merged[d] = []
        for f in range(F):
            back, front = frames[d][f]
            check(back.shape == (S, S, 4) and front.shape == (S, S, 4) and back.dtype == np.uint8, '%s: frame size' % key)
            check(np.array_equal(back, again[d][f][0]) and np.array_equal(front, again[d][f][1]),
                  '%s %s %d: the same pixels twice' % (key, d, f))
            both = gd.merge(back, front)
            for name, img in (('back', back), ('front', front), ('merged', both)):
                frame_rules(img, outline, '%s %s %d %s' % (key, d, f, name))
            used['back'] += int((back[..., 3] == 255).sum())
            used['front'] += int((front[..., 3] == 255).sum())
            glow += int((both[..., 3] == gd.GLOW_ALPHA).sum())
            check((both[..., 3] == 255).sum() >= 120, '%s %s %d: the art is there' % (key, d, f))
            merged[d].append(both)
        # the loop closes: every step moves, and the step from frame 15 to frame 0 is no bigger than the others
        steps = [int((merged[d][i] != merged[d][(i + 1) % F]).any(axis=2).sum()) for i in range(F)]
        check(min(steps) > 0, '%s %s: a frame equals the next (%s)' % (key, d, steps))
        check(steps[F - 1] <= 1.5 * max(steps[:F - 1]), '%s %s: a jump from frame 15 to frame 0 (%s)' % (key, d, steps))
        check(not np.array_equal(merged[d][0], merged[d][F // 2]), '%s %s: half a cycle later it looks the same' % (key, d))
    check(used['back'] > 0 and used['front'] > 0, '%s: both layers are used (%s)' % (key, used))
    check(glow > 0, '%s: sparks' % key)
    for i, a in enumerate(gd.DIRS):
        for b in gd.DIRS[i + 1:]:
            check(not np.array_equal(merged[a][0], merged[b][0]), '%s: %s and %s look the same' % (key, a, b))
    check(not np.array_equal(merged['east'][0], merged['west'][0][:, ::-1]), '%s: west is not east mirrored' % key)
    # the art stands round the anchor: its mass is within a tile of it
    ys, xs = np.nonzero(np.max([m[..., 3] for d in gd.DIRS for m in merged[d]], axis=0))
    check(abs(xs.mean() - gd.ANCHOR[0]) < 16 and abs(ys.mean() - gd.ANCHOR[1]) < 24,
          '%s: the art is far from the anchor (%.1f, %.1f)' % (key, xs.mean(), ys.mean()))

# ---- the files: sizes, the same bytes twice
with tempfile.TemporaryDirectory() as tmp:
    a_dir, b_dir = os.path.join(tmp, 'a'), os.path.join(tmp, 'b')
    one = gd.build(a_dir, ('void_orbit', 'grave_lanterns'))
    two = gd.build(b_dir, ('void_orbit', 'grave_lanterns'))
    check(sorted(os.path.basename(p) for p in one) == sorted('%s_%s.png' % (k, n) for k in ('void_orbit', 'grave_lanterns')
                                                             for n in ('sheet', 'back', 'front')), 'three files a design')
    for pa, pb in zip(one, two):
        check(open(pa, 'rb').read() == open(pb, 'rb').read(), 'the same bytes twice: ' + os.path.basename(pa))
        im = Image.open(pa)
        check(im.size == (S * F, S * len(gd.DIRS)) and im.mode == 'RGBA', 'sheet size and mode: ' + os.path.basename(pa))
    sheet = np.asarray(Image.open(os.path.join(a_dir, 'void_orbit_sheet.png')))
    back, front = gd.render_frame('void_orbit', 'south', 3)
    r = gd.DIRS.index('south')
    check(np.array_equal(sheet[r * S:(r + 1) * S, 3 * S:4 * S], gd.merge(back, front)), 'rows north east south west, 16 columns')
    check(gd.main(['build', os.path.join(tmp, 'c'), '--only', 'bladefan']) == 0 and
          sorted(os.listdir(os.path.join(tmp, 'c'))) == ['bladefan_back.png', 'bladefan_front.png', 'bladefan_sheet.png'],
          'build --only')

# ---- the preview body without a pair
for d in gd.DIRS:
    body = gd.silhouette(d)
    ys, xs = np.nonzero(body[..., 3])
    check(len(xs) > 150 and abs(xs.mean() - gd.ANCHOR[0]) < 6 and abs(ys.mean() - gd.ANCHOR[1]) < 6, 'silhouette on the anchor ' + d)
frames = {d: [gd.render_frame('void_orbit', d, 0)] for d in gd.DIRS}
strip = gd.strip(frames, {d: gd.silhouette(d) for d in gd.DIRS}, 0)
check(strip.shape == (S, S * 4, 3), 'preview strip: four directions side by side')

# ---- O583: the table of the existing wings
if __name__ == '__main__':
    import copy
    import struct
    import check_pair_test as t
    from datspr import Dat, Spr
    from gen_effects import encode_sprite
    from import_outfits import parse_body

    specs = fm.load()
    check(len(specs) == 121 and len({sp.wings for sp in specs}) == 121 and len({sp.look for sp in specs}) == 121,
          'one row a wings look: %d' % len(specs))
    check(fm.problems(specs) == [], 'the table rules: %s' % fm.problems(specs)[:3])
    fams = fm.by_family(specs)
    check(sorted(fams) == sorted(fm.FAMILIES) and len(fams) == 9, 'nine families, every one used')
    check(all(len(v) >= 2 for v in fams.values()), 'no family of one')
    check(all(sp.name and sp.old and sp.key == sp.key.lower() for sp in specs), 'every row names its wing and what it was')

    # every row is drawn once: its pictures are those of designs.sums, and it holds the bar of the six wings of O581
    reports = fm.all_reports(specs)
    sums = fm.read_sums()
    check(sorted(reports) == sorted(sums) == sorted(sp.wings for sp in specs), 'a digest for every row')
    stale = [w for w in sorted(reports) if reports[w][0] != sums.get(w)]
    check(not stale, 'designs.sums is stale for %s: run gen_drawn_wings.py table' % stale[:8])
    check(len({h for h, _ in reports.values()}) == len(reports), 'no two rows draw the same pictures')
    for sp in specs:
        bad = reports[sp.wings][1]
        check(not bad, 'the bar, %d %s (%s/%s): %s' % (sp.wings, sp.key, sp.family, sp.var, bad[:4]))
    # the bar itself catches a broken wing: a frozen loop, a missing outline, a half-clear pixel
    sp = specs[0]
    one = fm.render(sp)
    frozen = {d: [one[d][0]] * gd.FRAMES for d in gd.DIRS}
    check(any('equals the next' in b for b in fm.bar_problems(sp, frozen)), 'the bar sees a frozen loop')
    short = {d: one[d][:8] for d in gd.DIRS}
    check(any('16 frames' in b for b in fm.bar_problems(sp, short)), 'the bar sees a short loop')
    hurt = {d: [(bk.copy(), fr.copy()) for bk, fr in one[d]] for d in gd.DIRS}
    bk = hurt['south'][3][0]
    ys, xs = np.nonzero(bk[..., 3] == 255)
    bk[ys[0], xs[0]] = (250, 250, 250, 255)
    check(any('outline' in b for b in fm.bar_problems(sp, hurt)), 'the bar sees an edge without the outline')
    bk[ys[0], xs[0]] = (250, 250, 250, 77)
    check(any('alpha' in b for b in fm.bar_problems(sp, hurt)), 'the bar sees a half-clear pixel')

    # the generated files are current
    for path, text in ((fm.ANCHORS, fm.anchors_text(specs)), (fm.FIXTURES, fm.fixtures_text()), (fm.SUMS, fm.sums_text(sums))):
        with open(path, encoding='utf-8') as fh:
            check(fh.read() == text, '%s is stale: run gen_drawn_wings.py table' % os.path.basename(path))
    check(fm.anchor_rel() == (gd.ANCHOR[0] - 64, gd.ANCHOR[1] - 64) == (-16, 0), 'the wings anchor from the creature place')

    # the patterns of the pair: y0 the whole wing without the front glow, y1 the front
    pats = fm.patterns(sp)
    check(len(pats) == 2 * 4 * gd.FRAMES, 'two y patterns, four directions, 16 frames')
    bk, fr = fm.render_frame(sp, 'south', 5)
    y0, y1 = pats[(0, 2, 5)], pats[(1, 2, 5)]
    solid = fr[..., 3] == 255
    check(np.array_equal(y1, fr) and np.array_equal(y0[solid], fr[solid]) and np.array_equal(y0[~solid], bk[~solid]),
          'y0 is the back with the solid front on it, y1 the front')

    # ---- the torso rule: the Python twin gives the numbers of the fixtures file (the C++ test reads the same file)
    fixtures = fm.read_fixtures()
    check(len(fixtures) >= 10, 'fixtures: %d' % len(fixtures))
    for name, alpha, want in fixtures:
        check(fm.torso_anchor(alpha) == want, 'fixture %s: %s, the file says %s' % (name, fm.torso_anchor(alpha), want))
    by_name = {name: (alpha, want) for name, alpha, want in fixtures}
    check(by_name['thin_staff'][1] == by_name['plain'][1], 'a thin staff does not move the torso')
    check(by_name['empty'][1] is None, 'an empty picture has no torso')
    check(0 < by_name['wide_cape'][1][0] - 59 <= 21, 'a wide cape moves it by less than half its width')
    check(abs(by_name['shadow_blob'][1][0] - 59) <= 1, 'a ground shadow does not pull the torso: %s' % (by_name['shadow_blob'][1],))
    plain = by_name['plain'][0]
    rel = fm.body_rel(plain)
    check(rel == (34 - 32, (by_name['plain'][1][1] + 1) // 2 - 32), 'the torso from the creature place: %s' % (rel,))
    check(fm.body_rel(plain, (8, 8)) == (rel[0] - 8, rel[1] - 8), 'the displacement moves the torso as drawn')
    check(fm.body_rel(by_name['empty'][0]) is None, 'nothing to measure')
    ax, ay = fm.anchor_rel()
    sh = fm.wing_shift(rel, lift=6)
    check(sh == (rel[0] - 6 - ax, rel[1] - 6 - ay), 'the anchor lands on the torso of the lifted body')
    check(fm.wing_shift((400, 0)) == (0, 0), 'a shift out of range is refused')
    # walking does not move the wings: the rule reads the standing picture only (one measure a look, column, z)
    moved = plain.copy()
    moved[50:58, 20:26] = 255                                  # a leg swung out, as a walking frame has
    check(fm.torso_anchor(moved) is not None, 'a walking frame can be measured, the engine does not')

    # ---- the pair step on a synthetic pair: two old wings looks redrawn in place, the rest byte for byte
    def cut(img, ids, recs, w, h):
        out = []
        for hh in range(h):
            for ww in range(w):
                tile = np.ascontiguousarray(img[(h - 1 - hh) * 32:(h - hh) * 32, (w - 1 - ww) * 32:(w - ww) * 32])
                rec = encode_sprite(tile)
                if rec is None:
                    out.append(0)
                    continue
                rec = bytes(rec)
                if rec not in ids:
                    recs.append(rec)
                    ids[rec] = len(recs)
                out.append(ids[rec])
        return out

    def old_wing(seed, d, p, z=0):
        img = np.zeros((64, 64, 4), np.uint8)
        x = 4 + 5 * d + p + 3 * z
        img[6 + seed:22 + seed, x:x + 9] = (200, 180 - 20 * seed, 90, 255)
        return img

    ids, recs = {}, []
    body = np.zeros((32, 32, 4), np.uint8)
    body[4:30, 10:22] = (90, 60, 40, 255)
    b = cut(body, ids, recs, 1, 1)
    wing_a = []                                               # look 2: 2 x 2 tiles, 3 phases, two groups (idle, walk)
    for p in range(3):
        for d in range(4):
            wing_a += cut(old_wing(0, d, p), ids, recs, 2, 2)
    wing_b = []                                               # look 3: one group, two z patterns
    for p in range(2):
        for z in range(2):
            for d in range(4):
                wing_b += cut(old_wing(2, d, p, z), ids, recs, 2, 2)
    always, disp = bytes([28]), bytes([25]) + struct.pack('<hh', 8, 8)
    outfits = [t.entry(disp, [t.group(b * 4, px=4, gtype=0)], outfit=True),
               t.entry(disp + always, [t.group(wing_a, w=2, h=2, px=4, phases=3, gtype=0),
                                       t.group(wing_a, w=2, h=2, px=4, phases=3, gtype=1)], outfit=True),
               t.entry(always, [t.group(wing_b, w=2, h=2, px=4, pz=2, phases=2, gtype=0)], outfit=True),
               t.entry(disp, [t.group(b * 4, px=4, gtype=0)], outfit=True)]
    items = [t.entry(bytes([17]), [t.group(b)])]
    effects = [t.entry(b'', [t.group(b)])]
    missiles = [t.entry(b'', [t.group(b * 9, px=3, py=3)])]
    case = t.Case()
    dat_p, spr_p = case.pair(recs, items, outfits, effects, missiles)
    rows = [copy.copy(specs[0]), copy.copy(specs[40])]
    rows[0].look, rows[1].look = 2, 3
    row_sums = {r.wings: reports[r.wings][0] for r in rows}
    quiet = lambda *a: None  # noqa: E731
    check(len(fm.check_pair(dat_p, spr_p, rows, row_sums, log=quiet)) == 2, 'the old pair does not hold the drawn wings')
    out_dir = os.path.join(case.dir, 'out')
    done = fm.apply(dat_p, spr_p, out_dir, rows, log=quiet)
    check(done == [2, 3], 'apply redraws the looks of the rows: %s' % done)
    ndat_p, nspr_p = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
    check(fm.check_pair(ndat_p, nspr_p, rows, row_sums, log=quiet) == [], 'the built pair holds the drawn wings')
    od, nd, ospr, nspr = Dat(dat_p), Dat(ndat_p), Spr(spr_p), Spr(nspr_p)
    check(nd.counts == od.counts and nspr.count > ospr.count, 'no id added to the dat, sprites appended')
    for sid in range(1, ospr.count + 1):
        x, y = ospr.sprite(sid), nspr.sprite(sid)
        check((x is None) == (y is None) and (x is None or np.array_equal(x, y)), 'old sprite %d unchanged' % sid)
    for look in (1, 4):
        ta, tb = od.outfit(look), nd.outfit(look)
        check(od.data[ta.raw[0]:ta.raw[1]] == nd.data[tb.raw[0]:tb.raw[1]], 'outfit %d byte for byte' % look)
    for look, groups, pz in ((2, 2, 1), (3, 1, 2)):
        tt = nd.outfit(look)
        check('displacement' not in tt.flags and 'animateAlways' in tt.flags, 'look %d: flags' % look)
        got_groups = list(parse_body(nd, tt))
        check(len(got_groups) == groups, 'look %d keeps its frame groups: %d' % (look, len(got_groups)))
        for g in got_groups:
            check((g.w, g.h, g.layers, g.px, g.py, g.pz, g.phases) == (3, 3, 1, 4, 2, pz, gd.FRAMES), 'look %d: shape' % look)
    check([g.gtype for g in parse_body(nd, nd.outfit(2))] == [0, 1], 'idle and walk group types kept')
    got = fm.pair_patterns(nd, nspr, 2)
    want = fm.patterns(rows[0])
    check(not isinstance(got, str) and all(np.array_equal(want[key], got[key]) for key in want), 'the pictures read back')
    for bad_call, what in ((lambda: fm.apply(dat_p, spr_p, out_dir, rows, log=quiet), 'an existing folder'),
                           (lambda: fm.apply(dat_p, spr_p, out_dir + '2', [rows[0], copy.copy(specs[1])], log=quiet), 'a missing look')):
        try:
            bad_call()
            check(False, 'apply refuses ' + what)
        except SystemExit:
            pass
    not_wing = copy.copy(specs[2])
    not_wing.look = 1
    try:
        fm.apply(dat_p, spr_p, out_dir + '3', [not_wing], log=quiet)
        check(False, 'apply refuses a look that is not a wings look')
    except SystemExit:
        pass
    check(not os.path.exists(out_dir + '2') and not os.path.exists(out_dir + '3'), 'a refused run leaves no folder')
    again = os.path.join(case.dir, 'again')
    fm.apply(dat_p, spr_p, again, rows, log=quiet)
    for name in ('Tibia.dat', 'Tibia.spr'):
        with open(os.path.join(out_dir, name), 'rb') as fa, open(os.path.join(again, name), 'rb') as fb:
            check(fa.read() == fb.read(), 'the same pair twice: ' + name)
    import shutil
    shutil.rmtree(case.dir)

# ---- O587, O590: the redone wings follow the old art by numbers (strips, zone colours, beat), no picture data
import csv as _csv  # noqa: E402
import math  # noqa: E402
import gen_drawn_wings_families as fm587  # noqa: E402
import gen_drawn_wings_strip as _st  # noqa: E402
with open(fm587.CSV, newline='', encoding='utf-8') as _f:
    _rows = list(_csv.DictReader(_f))
_specs = fm587.load()
check(len(_rows) == 121, 'O587: 121 rows')
_LEN = 4 + 4 * _st.STATIONS
for _r, _sp in zip(_rows, _specs):
    for _name in ('sl', 'sr', 'nl', 'nr'):
        _v = _r[_name].split()
        check(len(_v) in (0, _LEN), 'O590: %s %s is a strip of %d whole numbers or empty' % (_r['key'], _name, _LEN))
        check(all(-96 <= int(x) <= 96 for x in _v), 'O590: %s %s lies in the cell' % (_r['key'], _name))
    check(_r['sl'] or _r['sr'], 'O590: %s has a wing in the south view' % _r['key'])
    check(_r['nl'] or _r['nr'], 'O590: %s has a wing in the north view' % _r['key'])
    check(len(_r['zones'].split()) == 6 and len(_sp.zones) == 6, 'O590: %s has six zone colours' % _r['key'])
    check(_r['mould'] in fm587.MOULDS, 'O590: %s mould %s' % (_r['key'], _r['mould']))
    check(0.03 <= _sp.amp <= 0.3, 'O590: %s beat %s' % (_r['key'], _sp.amp))
    check(max(len(v) for v in _r.values()) < 80, 'O587: %s holds numbers and words, no picture data' % _r['key'])
check(not any(name in _rows[0] for name in ('env', 'core', 'tips', 'fit', 'size')), 'O590: the O587 columns are gone')
_var = {sp.key: (sp.family, sp.var) for sp in _specs}
for _key, _want in (('tornado_funnel', ('energy', 'funnel')), ('whirlpool', ('energy', 'whirl')),
                    ('shadow_smoke', ('energy', 'smoke')), ('rain_veil', ('energy', 'rain')), ('nebula', ('energy', 'nebula')),
                    ('origami_crane', ('fan', 'fold')), ('pearl_scallop', ('fan', 'shell'))):
    check(_var.get(_key) == _want, 'O587: %s is drawn as %s/%s' % ((_key,) + _want))
check(sum(1 for sp in _specs if sp.family == 'feather') == 35, 'O587: 35 feather rows')
check(set(fm587.STYLES) == set(fm587.VARIANTS), 'O590: every family has a strip style')

# a strip measured from a picture gives that picture's shape again (no pair: a drawn bar pair)
_bar = np.zeros((64, 96, 4), np.uint8)
for _i in range(34):                                      # the left wing rises to the left, the right one is short
    _bar[40 - _i // 2 - 4:40 - _i // 2 + 5, 46 - _i, 3] = 255
for _i in range(16):
    _bar[40 - _i - 3:40 - _i + 4, 50 + _i, 3] = 255
_bar[36:45, 46:50, 3] = 255
_l, _r2 = _st.measure_view([_bar])
check(_l is not None and _r2 is not None and len(_l) == _LEN and len(_r2) == _LEN, 'O590: two strips from a picture')
check(_st.parse(_st.text_of(_l)) == list(_l), 'O590: a strip goes through the table text unchanged')
check(_st.parse('') is None, 'O590: an empty field is no wing')
_origin, _scale = _st.place((_l, _r2))
_m = np.zeros((gd.SIZE, gd.SIZE), bool)
for _v, _sgn in ((_l, -1), (_r2, 1)):
    _m |= _st.Strip(_v, _sgn, _origin, _scale).body()
_ob, _nb = fm587._alpha_box([_bar[..., 3] > 0]), fm587._alpha_box([_m])
_x, _y = fm587._norm_mask(_bar[..., 3] > 0, _ob), fm587._norm_mask(_m, _nb)
check((_x & _y).sum() / float((_x | _y).sum()) > 0.7, 'O590: the strips cover the measured picture')
_sl = _st.Strip(_l, -1, _origin, _scale)
check(_sl.length > _st.Strip(_r2, 1, _origin, _scale).length, 'O590: the long wing stays the long one')
check(abs((_nb[0] + _nb[2]) / 2.0 - gd.ANCHOR[0]) <= 3, 'O590: the pair is centred on the anchor')
_ss, _tt = _sl.field()
check(_ss.shape == (gd.SIZE, gd.SIZE) and 0.0 <= float(_ss[_sl.body()].min()) and float(_ss[_sl.body()].max()) <= 1.0,
      'O590: the field of a strip runs from root to tip')

# east and west are the face-on pictures with x and y changed over (the old art's side views)
_sp = [sp for sp in _specs if sp.key == 'fiery'][0]
for _d, _src in (('east', 'south'), ('west', 'north')):
    _fb, _ff = fm587.render_frame(_sp, _src, 3)
    _eb, _ef = fm587.render_frame(_sp, _d, 3)
    _dx, _dy = fm587._side_shift(_sp, _d)
    check(np.array_equal(_eb, fm587._turned(gd.merge(_fb, _ff), _dx, _dy)), 'O590: %s is the %s view turned' % (_d, _src))
    check(not _ef[..., 3].any(), 'O590: from the side the pair lies behind the body (%s)' % _d)
    check((gd.merge(_eb, _ef)[..., 3] > 0).sum() == (gd.merge(_fb, _ff)[..., 3] > 0).sum(), 'O590: %s loses no pixel' % _d)

# a mould holds a wing to its strip: nothing further than a pixel outside, `fill` leaves no hole
for _mould in ('clip', 'fill'):
    _lay, _can = fm587.Clip((10, 10, 10)), fm587.Clip((10, 10, 10))
    _box = np.zeros((gd.SIZE, gd.SIZE), bool)
    _box[20:60, 30:60] = True
    _lay.piece(_box & (gd.XX % 2 == 0), np.full((gd.SIZE, gd.SIZE), 2, np.int8), _sp.R, ring=False)
    fm587._mould(_lay, _can, _sl, _sp, _mould == 'fill')
    check(not (_can.op & ~fm587._grow(_sl.body(), 1)).any(), 'O590: %s cuts what lies outside the strip' % _mould)
    if _mould == 'fill':
        check(not (_sl.body() & fm587.INNER & ~_can.op).any(), 'O590: fill closes the strip')

# a haze is one glow level, only on clear pixels
_c = gd.Canvas((20, 20, 30))
_m = np.zeros((gd.SIZE, gd.SIZE), bool)
_m[40:50, 40:50] = True
_c.piece(_m, np.full((gd.SIZE, gd.SIZE), 2, np.int8), fm587.ramp5((200, 60, 60)))
_h = np.zeros((gd.SIZE, gd.SIZE), bool)
_h[36:60, 36:60] = True
_c.haze(_h, (90, 80, 120))
_img = _c.finish()
check(set(np.unique(_img[..., 3]).tolist()) == {0, 255, gd.GLOW_ALPHA}, 'O587: a haze is the glow level')
check((_img[40:50, 40:50, 3] == 255).all(), 'O587: a haze does not cover art')

# the likeness score: 0 for the same pictures, larger the further away
def _pic(x0, y0, x1, y1, colour):
    a = np.zeros((64, 64, 4), np.uint8)
    a[y0:y1, x0:x1, :3] = colour
    a[y0:y1, x0:x1, 3] = 255
    return a


_a = {d: [_pic(10, 20, 50, 40, (200, 40, 40)), _pic(10, 18, 50, 40, (200, 40, 40))] for d in gd.DIRS}
_b = {d: [_pic(10, 20, 50, 40, (40, 40, 200)), _pic(10, 18, 50, 40, (40, 40, 200))] for d in gd.DIRS}
_c2 = {d: [_pic(28, 4, 36, 60, (40, 40, 200)), _pic(28, 4, 36, 60, (40, 40, 200))] for d in gd.DIRS}
_same, _col, _far = fm587.likeness(_a, _a), fm587.likeness(_a, _b), fm587.likeness(_a, _c2)
check(_same['score'] == 0.0, 'O587: the same pictures score 0')
check(_col['shape'] == 0.0 and _col['colour'] > 0.9, 'O587: another colour is a colour distance only')
check(_far['score'] > _col['score'] > 0, 'O587: another shape and colour is further away')

# the fit preview takes player bodies only
_players = fm587.player_looks()
check(fm587.parse_fit_look('2073+3:370', _players) == (2073, 370, 3), 'O587: a class look with addons on a mount')
for _bad in ('35', '370', '2073:35', '2073+4'):
    try:
        fm587.parse_fit_look(_bad, _players)
        check(False, 'O587: the fit preview refuses %s' % _bad)
    except SystemExit:
        pass

if fails:
    print('%d FAILED' % fails)
    sys.exit(1)
print('gen_drawn_wings_test: OK')
