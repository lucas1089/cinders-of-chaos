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
SHEETS = os.environ.get('CHAOS_WINGS_SRC', '')   # the private folder of the painted sheets (O594), or nothing
fm.use_src('')                                   # everything below is the code drawing until the O594 part names it


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
    # O714: a pair is the same on both sides, west is the east frame mirrored about the anchor column
    for d in ('south', 'north'):
        for f in range(F):
            a = merged[d][f][..., 3] > 0
            check(int((a ^ gd.mirrored(a))[:, 1:].sum()) <= 0.02 * int(a.sum()), '%s %s %d: the pair is not the same left and right' % (key, d, f))
    for f in range(F):
        check(np.array_equal(gd.mirrored(merged['east'][f]), merged['west'][f]), '%s %d: west is east mirrored' % (key, f))
        ex = np.nonzero(merged['east'][f][..., 3] == 255)[1]
        check(ex.mean() < gd.ANCHOR[0], '%s %d: east is on the left of the anchor column' % (key, f))
    # O714c: a wing of the six seen from the side is a pair of wings in profile (the orbit and the lanterns are no wings)
    if key in gd.SIDE_WINGS:
        _sb = gd.side_problems_of(key)
        check(not _sb, '%s: the side view (O714c): %s' % (key, _sb[:3]))
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
    # O714: `apply --new` redraws the six looks of O581 phase 2 in place on a pair that holds them (look 3 stands for one here)
    import gen_drawn_wings_new as new_wings
    new_pats = new_wings.patterns('void_orbit')
    out_x = os.path.join(case.dir, 'outx')
    done = fm.apply(dat_p, spr_p, out_x, [rows[0]], log=quiet, extra=[(3, 127, 'void_orbit', new_pats)])
    check(done == [2, 3], 'apply with extra looks redraws them too: %s' % done)
    xd, xs = Dat(os.path.join(out_x, 'Tibia.dat')), Spr(os.path.join(out_x, 'Tibia.spr'))
    got = fm.pair_patterns(xd, xs, 3)
    check(not isinstance(got, str) and all(np.array_equal(new_pats[key], got[key]) for key in new_pats), 'an extra look reads back its pictures')
    check([r[2] for r in fm.new_rows()] == list(gd.KEYS), 'new_rows names the six designs in order')
    # O714b: `--keep-painted`: a row of pixellab_rows.csv keeps its look as the input pair has it, the others are redrawn
    painted = copy.copy(rows[1])
    painted.wings = sorted(fm.sheet_rows())[0]
    out_k = os.path.join(case.dir, 'outk')
    done = fm.apply(dat_p, spr_p, out_k, [rows[0], painted], log=quiet, keep=set(fm.sheet_rows()))
    check(done == [2], 'apply keep redraws the unpainted look only: %s' % done)
    kd, ks = Dat(os.path.join(out_k, 'Tibia.dat')), Spr(os.path.join(out_k, 'Tibia.spr'))
    ta, tb = od.outfit(3), kd.outfit(3)
    check(od.data[ta.raw[0]:ta.raw[1]] == kd.data[tb.raw[0]:tb.raw[1]], 'a kept look is byte for byte the input look')
    kdat, kspr = os.path.join(out_k, 'Tibia.dat'), os.path.join(out_k, 'Tibia.spr')
    ksums = {rows[0].wings: row_sums[rows[0].wings]}
    keep_ids = set(fm.sheet_rows())
    check(fm.check_pair(kdat, kspr, [rows[0], painted], ksums, log=quiet, keep=keep_ids, base=(dat_p, spr_p)) == [],
          'live keep: kept row equal to the base pair, the other held to the sums')
    check(fm.check_pair(kdat, kspr, [rows[0], painted], ksums, log=quiet, keep=keep_ids) == [], 'live keep without a base skips the kept row')
    check(len(fm.check_pair(ndat_p, nspr_p, [rows[0], painted], ksums, log=quiet, keep=keep_ids, base=(dat_p, spr_p))) == 1,
          'live keep names a painted row that was redrawn instead of kept')
    # O724: `--keep-painted --painted-sides`: a painted look keeps its north and south as the input pair has them and
    # takes the PixelLab side strips in east and west (west the strip mirrored); every other look stays as it was
    import gen_painted_sides as gps
    out_s = os.path.join(case.dir, 'outs')
    done = fm.apply(ndat_p, nspr_p, out_s, [painted], log=quiet, keep=keep_ids, sides=keep_ids)
    check(done == [3], 'apply painted sides rewrites the painted look only: %s' % done)
    sdat, sspr = os.path.join(out_s, 'Tibia.dat'), os.path.join(out_s, 'Tibia.spr')
    sd, ss = Dat(sdat), Spr(sspr)
    base3, got3 = fm.pair_patterns(nd, nspr, 3), fm.pair_patterns(sd, ss, 3)
    east = gps.read_strip(painted.wings)
    check(not isinstance(got3, str) and all(np.array_equal(base3[(y, x, f)], got3[(y, x, f)])
                                             for y in range(2) for x in (0, 2) for f in range(gd.FRAMES)),
          'painted sides keep north and south of the input pair')
    check(all(np.array_equal(got3[(0, 1, f)], east[f]) and np.array_equal(got3[(0, 3, f)], gd.mirrored(east[f]))
              and not got3[(1, 1, f)].any() and not got3[(1, 3, f)].any() for f in range(gd.FRAMES)),
          'painted sides put the strip in east and its mirror in west, behind the body')
    ta, tb = nd.outfit(2), sd.outfit(2)
    check(nd.data[ta.raw[0]:ta.raw[1]] == sd.data[tb.raw[0]:tb.raw[1]], 'painted sides leave the other looks byte for byte')
    check(fm.check_pair(sdat, sspr, [painted], {}, log=quiet, keep=keep_ids, base=(ndat_p, nspr_p), sides=keep_ids) == [],
          'live painted sides: north / south equal the base, east / west the strips')
    check(len(fm.check_pair(ndat_p, nspr_p, [painted], {}, log=quiet, keep=keep_ids, base=(ndat_p, nspr_p), sides=keep_ids)) == 1,
          'live painted sides names a look without the side strips')
    try:
        fm.apply(ndat_p, nspr_p, out_s + '2', [painted], log=quiet, keep=set(), sides=keep_ids)
        check(False, 'painted sides refuse a row that is not kept')
    except SystemExit:
        pass
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

# ---- O714: a pair is one wing and its mirror picture, west is east mirrored, a side wing rises and trails behind the body.
# The owner saw a wing mirrored or on the wrong side in nearly every wing of the store preview. The cause, held here by numbers:
# (1) the table measured the left and the right wing of the old art apart and the strip engine drew each as measured
_lopsided = sum(1 for _s in _specs for _v in ('south', 'north')
                if min(_st.Strip(_s.strips[_v][0], -1, (0, 0)).length, _st.Strip(_s.strips[_v][1], 1, (0, 0)).length)
                < 0.8 * max(_st.Strip(_s.strips[_v][0], -1, (0, 0)).length, _st.Strip(_s.strips[_v][1], 1, (0, 0)).length))
check(_lopsided >= 60, 'O714: the measured pair is lopsided in many views (%d of 242)' % _lopsided)
# (2) and the side views were the face-on pictures with x and y changed over: east and west alike, so west trailed left too
_sp = [sp for sp in _specs if sp.key == 'fiery'][0]
_old_side = {}
for _d, _src in (('east', 'south'), ('west', 'north')):
    _fb, _ff = fm587.render_frame(_sp, _src, 3)
    _old_side[_d] = np.ascontiguousarray(gd.merge(_fb, _ff).transpose(1, 0, 2))
_mx = lambda im: np.nonzero(im[..., 3] > 0)[1].mean()
check(_mx(_old_side['east']) - _mx(_old_side['west']) < 8 and (_old_side['east'][..., 3] > 0).sum() > 0,
      'O714: a transposed picture has the same x for east and west (it cannot trail both ways)')

# the layout
check(gd.mirrored(np.arange(96)[None, :, None] * np.ones((2, 1, 1), np.int32))[0, 5, 0] == 91 and gd.mirrored(np.ones((2, 96)))[0, 0] == 0,
      'O714: mirrored() sends column c to 96 - c and leaves column 0 empty')
for _sp in _specs:
    _bad = []
    for _v in ('south', 'north'):
        _m = fm587.model_strip(_sp, _v)
        _n = fm587.mirror_strip(_m)
        _bad += [] if (_m[0] == 0 and _n[0] == 0 and fm587.mirror_strip(_n) == _m) else ['root or mirror']
        _a = _st.Strip(_m, -1, (48.0, 58.0))
        _b = _st.Strip(_n, 1, (48.0, 58.0))
        _lens = [_st.Strip(v, sg, (0, 0)).length for v, sg in zip(_sp.strips[_v], (-1, 1)) if v is not None]
        _bad += [] if abs(_a.length - max(_lens)) < 1.0 else ['not the longer wing']
        _pa, _pb = np.array([_a.pt(s_, 0.0) for s_ in (0.2, 0.5, 1.0)]), np.array([_b.pt(s_, 0.0) for s_ in (0.2, 0.5, 1.0)])
        _bad += [] if np.allclose(_pa[:, 0] - 48.0, -(_pb[:, 0] - 48.0), atol=1e-6) and np.allclose(_pa[:, 1], _pb[:, 1], atol=1e-6) else ['strip and mirror']
        _o, _sc = fm587.placed(_sp, _v)
        _bad += [] if _o[0] == 48 else ['origin x %s' % (_o,)]
    check(not _bad, 'O714: %s: model strip %s' % (_sp.key, _bad))
_sp = [sp for sp in _specs if sp.key == 'fiery'][0]
_fr = fm587.render(_sp)
check(fm587.layout_problems(_sp, _fr) == [], 'O714: fiery holds the layout: %s' % fm587.layout_problems(_sp, _fr))
for _d in ('south', 'north'):
    for _f in (0, 7, 15):
        _mg = gd.merge(*_fr[_d][_f])[..., 3] > 0
        check(int((_mg ^ gd.mirrored(_mg))[:, 1:].sum()) <= 0.02 * int(_mg.sum()), 'O714: fiery %s %d is its own mirror picture' % (_d, _f))
check(all(np.array_equal(gd.mirrored(_fr['east'][_f][_i]), _fr['west'][_f][_i]) for _f in range(F) for _i in (0, 1)), 'O714: west is east mirrored, both layers')
check(all(not _fr[_d][_f][1][..., 3].any() for _d in ('east', 'west') for _f in range(F)), 'O590: from the side the pair lies behind the body')
check(any(_fr['north'][_f][1][..., 3].any() for _f in range(F)) and not any(_fr['south'][_f][1][..., 3].any() for _f in range(F)),
      'O583: south behind the body, north in front of it')
_ys, _xs = np.nonzero(gd.merge(*_fr['east'][3])[..., 3] == 255)
check(fm587.JOIN[1] - _ys.min() >= fm587.SIDE_RISE_MIN and (_ys >= gd.ANCHOR[1]).mean() <= 0.25, 'O714: the east wing rises over the join and does not hang')
check(_xs.min() < fm587.JOIN[0] - 8, 'O714: the east wing trails behind the join')
# the strip turned to rise: the line to the tip is at the angle asked, the widths do not change
_v = fm587.model_strip(_sp, 'south')
for _rise in (58, 30):
    _t = fm587.side_strip(_v, _rise)
    _ang = math.degrees(math.atan2(-(_t[-1] - _t[1]), -(_t[-2] - _t[0])))
    check(abs(_ang - _rise) < 0.5 and [_t[4 + 4 * _i] for _i in range(5)] == [float(_v[4 + 4 * _i]) for _i in range(5)],
          'O714: a side wing is turned to rise %d degrees (got %.1f)' % (_rise, _ang))

# ---- O714c: from the side a wing is a pair of wings in profile. The owner, on the pair 79 preview: most wings look bad
# from the side. Before: both wings on the torso column at 70% and 55% of the size, as steep as 58 degrees, a clump.
_rise, _far, _back = fm587.side_geo(_sp)
check(0 <= _far < len(gd.SIDE_FARS) and _back in gd.SIDE_BACKS, 'O714c: the far wing takes one of the places of SIDE_FARS')
_near, _farm = fm587.side_masks(_sp, 0)
_e0 = gd.merge(*_fr['east'][0])
_reach, _sweep, _behind = gd.side_tip(_near)
check(_behind > 0 and gd.SIDE_ANGLE[0] <= _sweep <= gd.SIDE_ANGLE[1], 'O714c: fiery is swept back at %.0f degrees' % _sweep)
check(_reach >= gd.SIDE_LEN * gd.face_reach(gd.merge(*_fr['south'][0])[..., 3] == 255, fm587.JOIN), 'O714c: the near wing keeps its length')
check(int(np.nonzero(_e0[..., 3].any(axis=0))[0].max()) <= gd.SIDE_ROOT[0] + gd.SIDE_FRONT, 'O714c: nothing in front of the back line')
check((_farm & ~_near).sum() >= gd.SIDE_FAR_FREE * _farm.sum(), 'O714c: the far wing shows beside the near one')
check(not gd.side_problems(_near, _farm, _e0, gd.merge(*_fr['south'][0]), fm587.JOIN, _sp.outline), 'O714c: fiery holds the side rules')
# the dummy of the sheets: east looks right, west left, and the side wing lies behind its back
_be, _bw = gd.silhouette('east'), gd.silhouette('west')
check(np.array_equal(gd.mirrored(_be), _bw), 'O714c: the west dummy is the east one mirrored')
_hx = np.nonzero(_be[: gd.ANCHOR[1] - 8, :, 3].any(axis=0))[0]
check(_hx.mean() > gd.ANCHOR[0], 'O714c: the east dummy faces right (its head is ahead of the torso column)')
# refused: the side view of O714, the clump, and faults one at a time
_o714 = {d: list(_fr[d]) for d in gd.DIRS}
_o714s = {}
for _f in range(F):
    _sc = gd.Scene(_sp.outline, 'east', _f, fm587.PIVOT)
    fm587.fam_side_o714(_sc, _sp)
    _o714['east'][_f] = _sc.result()
    _o714['west'][_f] = tuple(gd.mirrored(_x) for _x in _o714['east'][_f])
    _o714s[_f] = _sc.side
_p = fm587.layout_problems(_sp, _o714, sides=_o714s)
check(any('front of the back line' in p for p in _p) and any('is short' in p for p in _p),
      'O714c: the side view of O714 (on the torso column, 70%%) is refused: %s' % _p[:3])
_p = gd.side_problems(_near, _near.copy(), _e0, gd.merge(*_fr['south'][0]), fm587.JOIN, _sp.outline)
check(any('hidden' in p for p in _p), 'O714c: a far wing under the near one is refused')
_up = np.zeros_like(_near)
_up[10:40, 30:32] = True
_p = gd.side_problems(_up, _farm, _e0, gd.merge(*_fr['south'][0]), fm587.JOIN, _sp.outline)
check(any('swept back' in p for p in _p) and any('no root' in p for p in _p), 'O714c: a wing that stands straight up off the shoulder is refused')
_p = gd.side_problems(_near, _farm, np.roll(_e0, 6, axis=1), gd.merge(*_fr['south'][0]), fm587.JOIN, _sp.outline)
check(any('front of the back line' in p for p in _p), 'O714c: art over the chest is refused')
_lit = _e0.copy()
_fc = gd.merge(*_fr['south'][0])
_fc = _fc[(_fc[..., 3] == 255) & ~(_fc[..., :3] == np.asarray(_sp.outline, np.uint8)).all(axis=2)][0]
_lit[_farm & ~_near] = _fc
_p = gd.side_problems(_near, _farm, _lit, gd.merge(*_fr['south'][0]), fm587.JOIN, _sp.outline)
check(any('darker' in p for p in _p), 'O714c: a far wing in the colours of the wing face on is refused')

# a pair is mirrored in place by the canvas: the first drawing keeps a pixel both own, sparks and hazes follow
_c = gd.Canvas((20, 20, 30))
_pc = np.zeros((gd.SIZE, gd.SIZE), bool)
_pc[30:40, 20:44] = True
_c.piece(_pc, np.full((gd.SIZE, gd.SIZE), 2, np.int8), fm587.ramp5((200, 60, 60)))
_c.spark(30.4, 20.2, (255, 255, 200), 1)
_c.mirror_in()
_ci = _c.finish()
check(((_ci[..., 3] > 0) == gd.mirrored(_ci[..., 3] > 0)).all(), 'O714: Canvas.mirror_in gives a picture that is its own mirror picture')
check(_ci[20, 30, 3] == 255 and _ci[20, 66, 3] == 255, 'O714: a spark comes with its mirror partner (column 30 and 66)')
_c = gd.Canvas((20, 20, 30))
_pc[:] = False
_pc[30:40, 0:6] = True
_c.piece(_pc, np.full((gd.SIZE, gd.SIZE), 2, np.int8), fm587.ramp5((200, 60, 60)))
_c.mirror_in()
check(not (_c.op[:, :2].any() or _c.op[:, -1:].any()), 'O714: a ring on column 1 and its partner on column 95 are dropped together: nothing on the cell border')
# refused: the layout of before O714
_old = {d: list(_fr[d]) for d in gd.DIRS}
_old['west'] = [(_t, np.zeros_like(_t)) for _t in (np.roll(_old_side['west'], 0, axis=1),) for _f in range(F)]
check(any('west is not east mirrored' in p for p in fm587.layout_problems(_sp, _old)), 'O714: a west view that is not east mirrored is refused')
_old = {d: list(_fr[d]) for d in gd.DIRS}
_old['south'] = [(np.roll(_b, 3, axis=1), np.roll(_f2, 3, axis=1)) for _b, _f2 in _fr['south']]
check(any('not the same left and right' in p for p in fm587.layout_problems(_sp, _old)), 'O714: a pair 3 px off the anchor column is refused')
_old = {d: list(_fr[d]) for d in gd.DIRS}
_old['east'] = [(np.roll(np.ascontiguousarray(gd.merge(*_fr['south'][_f]).transpose(1, 0, 2)), 6, axis=0), np.zeros((gd.SIZE, gd.SIZE, 4), np.uint8)) for _f in range(F)]
_old['west'] = [(gd.mirrored(_b), gd.mirrored(_f2)) for _b, _f2 in _old['east']]
check(any('hangs' in p or 'does not rise' in p or 'trails the wrong way' in p for p in fm587.layout_problems(_sp, _old)),
      'O714: the south picture turned on its side (the side view of before) is refused')

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

# ---- O594: ten rows painted with PixelLab; no picture in the repository, the sheets come from a private folder
import hashlib as _hl  # noqa: E402
import gen_pixellab_wings as pw  # noqa: E402
_prow = fm587.sheet_rows()
_TEN = {58, 93, 96, 104, 109, 110, 111, 116, 117, 118}
check(set(_prow) == _TEN, 'O594: the ten rows of pixellab_rows.csv')
_by = {sp.wings: sp for sp in _specs}
for _w, _r in sorted(_prow.items()):
    check(_w in _by and _by[_w].key == _r['key'], 'O594: row %d is a row of designs.csv with its key' % _w)
    check(_r['source'] == 'pixellab' and _r['frames'] == '16' and _r['notes'], 'O594: row %d names its source' % _w)
    pw.parse_motion(_r['ms']), pw.parse_motion(_r['mn']), pw.parse_fit(_r['fs']), pw.parse_fit(_r['fn']), pw.parse_tint(_r['tint'])
    check(len(_r['sha256']) == 64 and set(_r['sha256']) <= set('0123456789abcdef'), 'O594: row %d has the sha256 of its sheet' % _w)
check(len({_r['sha256'] for _r in _prow.values()}) == len(_prow), 'O594: no two rows share a sheet')
_psums = fm587.read_sums(fm587.SHEET_SUMS)
_dsums = fm587.read_sums()
check(set(_psums) == _TEN, 'O594: pixellab_rows.sums has the ten rows')
check(all(_psums[_w] != _dsums[_w] for _w in _psums), 'O594: a painted row is not the code drawing')
check(set(pw.EXTRAS) == _TEN, 'O594: every painted row names its lights')
_here = os.path.dirname(os.path.abspath(__file__))
_pics = [n for n in os.listdir(os.path.join(_here, 'drawn_wings')) if n.lower().endswith(('.png', '.gif', '.bmp', '.webp'))]
check(not _pics, 'O594: no picture in drawn_wings: %s' % _pics)

# the folder path on a made-up sheet: the loader, the sha256 guard, the fall back to code
_sp = _by[111]
_code = {d: [fm587.render_frame(_sp, d, f) for f in (0, 5)] for d in gd.DIRS}
check(fm587.sheet_faces(_sp) is None, 'O594: no folder named, a row is drawn by code')
with tempfile.TemporaryDirectory() as _tmp:
    _raw = os.path.join(_tmp, 'raw')
    os.makedirs(_raw)
    for _v in pw.VIEWS:                                    # a made-up raw loop: a bar that swings, soft edged, with a crumb
        for _f in range(gd.FRAMES + 1):
            _a = np.zeros((gd.SIZE, gd.SIZE, 4), np.uint8)
            _t = abs(_f % gd.FRAMES - 8)                    # up and down, every step a pixel
            _y = 30 if _v == 'south' else 44
            _a[_y + _t:_y + 14 + _t, 20:70] = (90 + 4 * _f, 120, 200, 255)
            _a[_y + 3 + _t:_y + 9 + _t, 26:60] = (200, 210, 240 - 3 * _f, 255)
            _a[_y + 14 + _t, 20:70] = (90, 120, 200, 90)   # under the alpha cut
            _a[5, 5] = (250, 0, 0, 255)                    # a crumb
            Image.fromarray(_a, 'RGBA').save(os.path.join(_raw, '111_%s_%02d.png' % (_v[0], _f)))
    _dir = os.path.join(_tmp, 'sheets')
    _done = pw.clean(_raw, _dir, only={111}, log=lambda *a: None, rows={111: {}})
    check(_done == [(111, [])], 'O594: a cleaned loop holds the bar: %s' % (_done,))
    check(fm587.SRC_DIR == '', 'O594: the cleaning step leaves no folder named')
    _sheet = np.asarray(Image.open(os.path.join(_dir, '111.png')))
    check(_sheet.shape == (4 * gd.SIZE, gd.FRAMES * gd.SIZE, 4), 'O594: a sheet is 16 x 4 cells of 96 px')
    check(set(np.unique(_sheet[..., 3]).tolist()) <= {0, 255, gd.GLOW_ALPHA}, 'O594: a sheet has alpha 0, 255 or the glow level')
    check(not _sheet[5, 5::gd.SIZE, 3].any(), 'O594: crumbs are dropped')
    _solid = _sheet[..., 3] == 255
    check(len(np.unique(_sheet[_solid][:, :3], axis=0)) <= pw.PALETTE + 2, 'O594: one palette a row')
    check(np.array_equal(_sheet[:, :gd.SIZE], np.asarray(Image.open(os.path.join(_dir, '111.png')))[:, :gd.SIZE]), 'O594: a sheet reads back')
    _b0 = pw.box_of([_sheet[:gd.SIZE, _f * gd.SIZE:(_f + 1) * gd.SIZE, 3] == 255 for _f in range(gd.FRAMES)])
    check(_b0[0] + _b0[2] == 2 * gd.ANCHOR[0], 'O620: the pair stands with its middle on the anchor column: %s' % (_b0,))
    fm587.use_src(_dir)
    try:
        fm587.render_frame(_sp, 'south', 0)
        check(False, 'O594: a sheet that is not the one of the table is refused')
    except SystemExit:
        pass
    fm587.use_src(_dir, check=False)
    _bk, _fr = fm587.render_frame(_sp, 'south', 5)
    check(np.array_equal(_bk, _sheet[:gd.SIZE, 5 * gd.SIZE:6 * gd.SIZE]) and not _fr.any(), 'O594: south is the sheet, behind the body')
    _bk, _fr = fm587.render_frame(_sp, 'north', 5)
    check(np.array_equal(_fr, _sheet[gd.SIZE:2 * gd.SIZE, 5 * gd.SIZE:6 * gd.SIZE]) and not _bk.any(), 'O594: north is the sheet, in front of the body')
    _eb, _ef = fm587.render_frame(_sp, 'east', 5)
    check(np.array_equal(_eb, _sheet[2 * gd.SIZE:3 * gd.SIZE, 5 * gd.SIZE:6 * gd.SIZE]) and not _ef.any(),
          'O594: east is the third row of the sheet, behind the body')
    _wb, _wf = fm587.render_frame(_sp, 'west', 5)
    check(np.array_equal(_wb, _sheet[3 * gd.SIZE:, 5 * gd.SIZE:6 * gd.SIZE]) and not _wf.any(),
          'O594: west is the fourth row of the sheet, behind the body')

    # ---- O620: the layout of a painted row. One wing is painted; the pair, the side views and the join are made by rule
    _fr = pw.row_frames(_sp)
    _n = pw.measure(_fr)
    check(pw.fit_problems(_fr) == [], 'O620: a cleaned loop holds the layout: %s' % pw.fit_problems(_fr))
    for _d in gd.DIRS:
        check(abs(_n['centre'][_d]) <= 1.0, 'O620: %s, the wings stand on the torso column (%.1f px off)' % (_d, _n['centre'][_d]))
        check(_n['join'][_d] <= 1.0, 'O620: %s, no gap between the wings and the join (%.1f px)' % (_d, _n['join'][_d]))
        check(_n['one'][_d] >= 0.9, 'O620: %s, the pair hangs together (%.2f)' % (_d, _n['one'][_d]))
        check((_fr[_d][3][pw.JOIN[1], pw.JOIN[0], 3] == 255), 'O620: %s, the join is the same point in every view' % _d)
    for _d in pw.VIEWS:
        check(_n['lopsided'][_d] <= pw.LOPSIDED, 'O620: %s, the pair is the same left and right' % _d)
        check(all(np.array_equal(pw.wing_of(_i), pw.mirrored(pw.wing_of(_i))) for _i in _fr[_d]), 'O620: %s, every frame is its own mirror picture' % _d)
    for _d in ('east', 'west'):
        check(_n['top'][_d] >= pw.SIDE_RISE and _n['hang'][_d] <= pw.SIDE_HANG,
              'O620: %s, the side wing rises over the shoulder line and does not hang (%d px, %.2f)' % (_d, _n['top'][_d], _n['hang'][_d]))
        _ys, _xs = np.nonzero(pw.wing_of(_fr[_d][0]))
        check(_ys.mean() < pw.JOIN[1], 'O620: %s, the middle of the side wing lies over the join' % _d)
    _ex = np.nonzero(pw.wing_of(_fr['east'][0]))[1]
    _wx = np.nonzero(pw.wing_of(_fr['west'][0]))[1]
    check(_ex.mean() < pw.JOIN[0] < _wx.mean(), 'O620: the east wing trails left of the join, the west wing right')
    check(_n['pair'] <= pw.PAIR_GAP, 'O620: north and south share their colours (%.2f)' % _n['pair'])
    check(_n['edge_dark']['north'] >= pw.CONTRAST and _n['line_light']['north'] >= pw.CONTRAST,
          'O620: the north view reads on dark and on light ground (%.1f, %.1f)' % (_n['edge_dark']['north'], _n['line_light']['north']))

    # the same wings on a body: the engine puts the anchor on the torso (base patch 0204), so the middle of the pair
    # is the middle of the torso, on every figure of the fixtures
    for _name, _alpha, _want in fm587.read_fixtures():
        _rel = fm587.body_rel(_alpha)
        if _rel is None or fm587.wing_shift(_rel) == (0, 0):
            continue
        for _d in gd.DIRS:
            _off = pw.on_body(_n['centre'][_d], _rel)
            check(abs(_off) <= 1.0, 'O620: %s on body %s, the wings are %.1f px beside the torso' % (_d, _name, _off))

    # what the measure refuses
    def _moved(_frames, _dx, _dy):
        return {_d: [pw.moved(_i, _dx, _dy) for _i in _seq] for _d, _seq in _frames.items()}

    def _has(_frames, _word):
        return any(_word in _t for _t in pw.fit_problems(_frames))

    check(_has(_moved(_fr, 3, 0), 'beside the torso'), 'O620: a pair 3 px beside the torso is refused')
    check(_has(_moved(_fr, 0, -5), 'a gap'), 'O620: a pair 5 px over the join is refused')
    _cut = {_d: [_i.copy() for _i in _seq] for _d, _seq in _fr.items()}
    for _i in _cut['south']:
        _i[:, pw.JOIN[0] - 6:pw.JOIN[0] - 3] = 0
    check(_has(_cut, 'comes apart') or _has(_cut, 'not the same left and right'), 'O620: a pair that comes apart is refused')
    _red = {_d: [_i.copy() for _i in _seq] for _d, _seq in _fr.items()}
    for _i in _red['north']:
        _in = pw.wing_of(_i) & ~pw.open_edge(pw.wing_of(_i))
        _i[..., :3][_in] = (230, 40, 30)
    check(_has(_red, 'do not share their colours'), 'O620: a north view in colours the south view lacks is refused')
    _dim = {_d: [_i.copy() for _i in _seq] for _d, _seq in _fr.items()}
    for _i in _dim['north']:
        _i[..., :3][pw.wing_of(_i)] = pw.GROUND_DARK
    check(_has(_dim, 'lost on dark ground'), 'O620: a north view as dark as the ground is refused')
    _old = dict(_fr)
    _old['east'] = [np.ascontiguousarray(_i.transpose(1, 0, 2)) for _i in _fr['south']]      # the O594 side view
    check(_has(_old, 'hangs') or _has(_old, 'beside the torso'), 'O620: the south picture turned on its side is refused')
    check(abs(pw.contrast((255, 255, 255), (0, 0, 0)) - 21.0) < 1e-6 and pw.contrast((9, 9, 9), (9, 9, 9)) == 1.0, 'O620: the contrast ratio')

    _row = dict(ms='still 6', mn='loop 3', fs='45 -1 -1 5 90 100', fn='', tint='20 110 95', rim='c0b0ff')
    _done = pw.clean(_raw, os.path.join(_tmp, 'fit'), only={111}, log=lambda *a: None, rows={111: _row})
    check(_done == [(111, [])], 'O594: a loop with a beat, a fit and a tint holds the bar: %s' % (_done,))
    check(not np.array_equal(np.asarray(Image.open(os.path.join(_tmp, 'fit', '111.png'))), _sheet), 'O594: the numbers of a row change its sheet')
    check(pw.parse_motion('') == ('loop', 0) and pw.parse_fit('') == pw.FIT_NONE and pw.parse_tint('') == pw.TINT_NONE
          and pw.rim_of({}) is None, 'O594: an empty column changes nothing')
    for _bad_text, _fn in (('sway 3', pw.parse_motion), ('1 2 3', pw.parse_fit), ('-1 -1 -1 0 20 100', pw.parse_fit), ('1 2', pw.parse_tint),
                           ('fff', lambda _t: pw.rim_of({'rim': _t}))):
        try:
            _fn(_bad_text)
            check(False, 'O594: a wrong column is refused: %s' % _bad_text)
        except ValueError:
            pass
    _other = _by[1]
    check(fm587.digest(fm587.patterns(_other)) == _dsums[1], 'O594: with a folder named a row that is not painted is still drawn by code')
    try:
        fm587.render_frame(_by[58], 'south', 0)
        check(False, 'O594: a folder without the sheet of a painted row is refused')
    except SystemExit:
        pass
    try:
        fm587.main(['table', '--src', _dir])
        check(False, 'O594: the table of the code drawing takes no folder')
    except SystemExit:
        pass
    fm587.use_src('')
    check(all(np.array_equal(_code[d][i][0], fm587.render_frame(_sp, d, f)[0]) for d in gd.DIRS for i, f in enumerate((0, 5))),
          'O594: without the folder the row is the code drawing again')

# the real sheets, when their folder is named: the files of the table, the bar, the sums
if SHEETS:
    for _w, _r in sorted(_prow.items()):
        _path = os.path.join(SHEETS, '%d.png' % _w)
        check(os.path.isfile(_path), 'O594: %s is there' % _path)
        if os.path.isfile(_path):
            with open(_path, 'rb') as _f:
                check(_hl.sha256(_f.read()).hexdigest() == _r['sha256'], 'O594: %d.png is the sheet of the table' % _w)
    fm587.use_src(SHEETS)
    for _w in sorted(_prow):
        _frames = fm587.render(_by[_w])
        _bad = fm587.bar_problems(_by[_w], _frames)
        check(not _bad, 'O594: the bar, painted row %d %s: %s' % (_w, _by[_w].key, _bad[:4]))
        check(fm587.digest(fm587.patterns(_by[_w])) == _psums[_w], 'O594: pixellab_rows.sums is stale for %d' % _w)
        _fit = pw.fit_problems({_d: [gd.merge(*_p) for _p in _frames[_d]] for _d in gd.DIRS})
        check(not _fit, 'O620: the layout, painted row %d %s: %s' % (_w, _by[_w].key, _fit[:4]))
    fm587.use_src('')
    print('O594, O620: the ten sheets of %s hold the table, the bar, the layout and the sums' % SHEETS)
else:
    print('O594: no sheets folder named (CHAOS_WINGS_SRC), the ten painted sheets are not checked')

# ---- O724: the side views of the ten painted rows, from PixelLab, held to the O714c side rules
import gen_painted_sides as _gps  # noqa: E402
check(set(_gps.rows()) == set(fm.sheet_rows()), 'O724: a side strip for every painted row of pixellab_rows.csv')
check(all(_gps.rows()[_w]['key'] == fm.sheet_rows()[_w]['key'] for _w in _gps.rows()), 'O724: side rows name the keys of the table')
_gbad = _gps.build(check=True, log=lambda *_a: None)
check(not _gbad, 'O724: the strips are what build draws, sides.sums is current, every frame holds the side rules: %s' % _gbad[:4])
_gs = _gps.read_strip(58)
_gw = [_f.copy() for _f in _gs]
_gw[3][40, 47:60] = 255                                  # art over the chest
check(_gps.problems(58, _gw), 'O724: the side rules refuse art in front of the back line')
_gw = [_f.copy() for _f in _gs]
_gw[0][_gw[0][..., 3] == 255] = (255, 0, 0, 255)          # no outline
check(_gps.problems(58, _gw), 'O724: the side rules refuse an open edge that is not the outline colour')
check(_gps.problems(58, [_gs[0]] * gd.FRAMES), 'O724: the side rules refuse a strip that does not flap')
_gr = dict(_gps.rows()[58])
_gr['aim'] = '60'
_gi, _gm = _gps.frames(58, _gr)
check(_gps.problems(58, _gi, _gm, _gr), 'O724: the side rules refuse a near wing that stands too steep')
print('O724: the ten painted side strips hold the side rules and the sums')

if fails:
    print('%d FAILED' % fails)
    sys.exit(1)
print('gen_drawn_wings_test: OK')
