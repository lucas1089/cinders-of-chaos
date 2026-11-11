#!/usr/bin/env python3
"""Tests of clean_wing_shadows.py on a small synthetic pair the test draws itself (no real pair needed; numpy).

python3 -I client/tools/sprites/clean_wing_shadows_test.py
"""
import contextlib
import io
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import check_pair_test as t  # noqa: E402
import clean_wing_shadows as cw  # noqa: E402
import gen_wing_centres as gwc  # noqa: E402
import import_art_things as iat  # noqa: E402
from datspr import Dat, Spr  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


CORE, RING = (10, 10, 20, 170), (30, 30, 40, 90)
WING = (230, 200, 120, 255)
DARK = (10, 10, 20, 170)        # a dark translucent wing pixel with exactly the core's level
PH, W, H = 3, 2, 2


def disc(img, cx, cy):
    yy, xx = np.mgrid[0:img.shape[0], 0:img.shape[1]]
    r = np.hypot(xx + 0.5 - cx, yy + 0.5 - cy)
    img[r <= 11] = RING
    img[r <= 5.5] = CORE


def wing_frame(kind, d, p):
    """a 64 x 64 frame: the wing moves with the direction and the phase, the shadow does not move with the direction"""
    img = np.zeros((64, 64, 4), np.uint8)
    if kind in ('sep', 'over', 'copy', 'shared'):
        disc(img, 44, 44)
    x = 4 + 5 * d + p
    if kind == 'sep':
        img[6:20, x:x + 8] = WING
    elif kind == 'over':
        img[26:41, 30 + 3 * d:44 + 3 * d] = WING        # lies over the top of the blob
    elif kind in ('copy', 'shared'):
        img[6:20, x:x + 8] = WING
    elif kind == 'dark':                                # no shadow: dark translucent wing, uses the core's level
        x = 2 + 15 * d + p
        img[10:30, x:x + 8] = DARK
        img[10:30, x + 8:x + 11] = (40, 40, 60, 120)
    return img


def cut(img, ids, recs):
    """cut a frame into its tiles (tile (ww, hh) at the bottom right); ids: bytes -> sprite id"""
    out = []
    for hh in range(H):
        for ww in range(W):
            tile = np.ascontiguousarray(img[(H - 1 - hh) * 32:(H - hh) * 32, (W - 1 - ww) * 32:(W - ww) * 32])
            rec = iat.encode_sprite(tile)
            if rec is None:
                out.append(0)
                continue
            if rec not in ids:
                recs.append(rec)
                ids[rec] = len(recs)
            out.append(ids[rec])
    return out


def pair(case, kinds, non_wing_uses=()):
    """a pair with one wing outfit per kind (outfit ids 1..n); outfit n + 1 is a non-wing thing using the sprite ids
    non_wing_uses. Returns (dat path, spr path)"""
    ids, recs = {}, []
    outfits = []
    for kind in kinds:
        sprites = []
        for p in range(PH):
            for d in range(4):
                sprites += cut(wing_frame(kind, d, p), ids, recs)
        outfits.append(t.entry(b'', [t.group(sprites, w=W, h=H, px=4, phases=PH, gtype=0)], outfit=True))
    if non_wing_uses:
        outfits.append(t.entry(b'', [t.group(list(non_wing_uses), w=1, h=1, px=1, phases=1, gtype=0)], outfit=True))
    return case.pair(recs, [], outfits, [], [])


def run_build(dat, spr, table_rows, outdir, overrides=None):
    tbl = os.path.join(outdir, 'table.csv')
    cw.write_table(tbl, table_rows)

    class A:
        pass
    a = A()
    a.dat, a.spr, a.out_dir, a.table, a.overrides, a.dry_run = dat, spr, os.path.join(outdir, 'out'), tbl, overrides, False
    buf = io.StringIO()
    res = cw.build(a, log=lambda s: buf.write(s + '\n'))
    return res, buf.getvalue(), a


def px_of(dat_path, spr_path, outfit, d, p):
    dat, spr = Dat(dat_path), Spr(spr_path)
    return cw.frames_of(dat.outfits[outfit - 1].groups[0], spr)[(d, p)]


def main():
    case = t.Case()
    kinds = ['sep', 'over', 'dark', 'copy']
    gwc.wing_ids = lambda: list(range(1, len(kinds) + 1))
    dat_p, spr_p = pair(case, kinds)
    dat, spr = Dat(dat_p), Spr(spr_p)

    # ---- fit: a blob for the wings that have one, none for the dark translucent wing
    rows, none = cw.fit_table(dat, spr)
    by = {r['wing']: r for r in rows}
    check(sorted(by) == [1, 2, 4], 'blob found on 1, 2, 4, none on 3: %s' % sorted(by))
    check(any(n[0] == 3 for n in none), 'the dark translucent wing has no row')
    for w in (1, 2, 4):
        r = by[w]
        check(abs(float(r['cx']) - 44) <= 2 and abs(float(r['cy']) - 44) <= 2, 'blob centre of %d: %s,%s' % (w, r['cx'], r['cy']))
        check(10 <= float(r['rx']) <= 14, 'blob radius of %d: %s' % (w, r['rx']))
        check(set(r['palette'].split('/')) >= {'10.10.20.170', '30.30.40.90'}, 'palette of %d: %s' % (w, r['palette']))
    check(cw.fit_table(dat, spr)[0] == rows, 'fit is deterministic')

    # ---- build: shadow gone, the wing proper not touched, the dark wing not touched
    out = tempfile.mkdtemp(prefix='cws_')
    (changed, left, stats, specs, why), log, a = run_build(dat_p, spr_p, rows, out)
    check(not left, 'no wing is left whole: %s' % left)
    ndat, nspr = os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr')
    check(open(dat_p, 'rb').read() == open(ndat, 'rb').read(), 'dat byte identical')
    for w in (1, 2, 4):
        for d in range(4):
            for p in range(PH):
                old, new = px_of(dat_p, spr_p, w, d, p), px_of(ndat, nspr, w, d, p)
                ref = wing_frame(kinds[w - 1], d, p)
                wing_px = ref[..., 3] == 255
                check((new[wing_px] == old[wing_px]).all(), 'wing %d d%d p%d: opaque wing pixels unchanged' % (w, d, p))
                disc_only = (old[..., 3] > 0) & ~wing_px
                any_dir = np.zeros(wing_px.shape, bool)    # the wing of any direction in this phase (limit b: covered elsewhere)
                for d2 in range(4):
                    any_dir |= wing_frame(kinds[w - 1], d2, p)[..., 3] == 255
                near = np.zeros(wing_px.shape, bool)       # within 4 px of it
                for dy in range(-4, 5):
                    for dx in range(-4, 5):
                        near |= np.roll(np.roll(any_dir, dy, 0), dx, 1)
                left = disc_only & (new[..., 3] > 0)
                check((left <= near).all(), 'wing %d d%d p%d: only blob pixels beside the wing stay' % (w, d, p))
                check(left.sum() <= 0.15 * disc_only.sum(), 'wing %d d%d p%d: most of the blob is gone' % (w, d, p))
                check(((new != old).any(axis=2) <= disc_only).all(), 'wing %d d%d p%d: only blob pixels changed' % (w, d, p))
    for d in range(4):
        for p in range(PH):
            check((px_of(dat_p, spr_p, 3, d, p) == px_of(ndat, nspr, 3, d, p)).all(), 'dark translucent wing %d.%d unchanged' % (d, p))
    check('verified' in log, 'build verified itself')

    # ---- check-clean: the cleaned pair passes, the original fails, a skipped wing must be untouched
    check(cw.check_clean(Dat(ndat), Spr(nspr), rows, {}) == [], 'check-clean passes on the cleaned pair: %s' % cw.check_clean(Dat(ndat), Spr(nspr), rows, {}))
    check(len(cw.check_clean(dat, spr, rows, {})) >= 3, 'check-clean fails on the pair with the shadows')

    # ---- idempotence: the same table on the cleaned pair changes nothing; fit finds no blob any more
    out2 = tempfile.mkdtemp(prefix='cws_')
    (changed2, left2, _s, _sp, _w), _log, _a = run_build(ndat, nspr, rows, out2)
    check(not changed2, 'second run changes nothing: %d sprites' % len(changed2))
    check(not cw.fit_table(Dat(ndat), Spr(nspr))[0], 'no blob left to fit on the cleaned pair')

    # ---- a shared sprite: cleaned once for the wings that share it (1 and 4 use the same ids), and a sprite shared
    # with a thing that is not a wing blocks its wing, which stays whole
    dat_q, spr_q = pair(case, kinds)
    ids_q = Dat(dat_q).outfits[0].groups[0][8]
    shared_blob = next(s for s in ids_q if s and (Spr(spr_q).sprite(s)[..., 3] > 0).any() and (Spr(spr_q).sprite(s)[..., 3] == 255).sum() == 0)
    dat_r, spr_r = pair(case, kinds, non_wing_uses=(shared_blob,))
    rows_r, _ = cw.fit_table(Dat(dat_r), Spr(spr_r))
    check(len(rows_r) == 3, 'the extra non-wing outfit does not change the fit')
    out3 = tempfile.mkdtemp(prefix='cws_')
    (changed3, left3, _s, _sp, why3), log3, a3 = run_build(dat_r, spr_r, rows_r, out3)
    check(1 in {k[0] for k in left3} and 4 in {k[0] for k in left3}, 'wings 1 and 4 (sharing the blocked sprite) stay whole: %s' % left3)
    check(2 not in {k[0] for k in left3}, 'wing 2 is cleaned')
    check(shared_blob in why3 and 'shared with outfit' in why3[shared_blob], 'the reason names the non-wing user: %s' % why3.get(shared_blob))
    n3 = os.path.join(a3.out_dir, 'Tibia.spr')
    check((px_of(dat_r, spr_r, 1, 0, 0) == px_of(os.path.join(a3.out_dir, 'Tibia.dat'), n3, 1, 0, 0)).all(), 'a wing left whole is byte for byte the same')

    # ---- an override: skip leaves the wing, a tighter region is used
    ov = os.path.join(out, 'ov.csv')
    open(ov, 'w').write('wing,group,action,args,reason\n2,0,skip,,test\n')
    out4 = tempfile.mkdtemp(prefix='cws_')
    (changed4, left4, st4, specs4, _w), _l, a4 = run_build(dat_p, spr_p, rows, out4, overrides=ov)
    check((2, 0) not in specs4 and (1, 0) in specs4, 'skip override: wing 2 not cleaned')
    check((px_of(dat_p, spr_p, 2, 1, 1) == px_of(os.path.join(a4.out_dir, 'Tibia.dat'), os.path.join(a4.out_dir, 'Tibia.spr'), 2, 1, 1)).all(),
          'skipped wing unchanged')
    skip2 = cw.read_overrides(ov)
    check(cw.check_clean(Dat(os.path.join(a4.out_dir, 'Tibia.dat')), Spr(os.path.join(a4.out_dir, 'Tibia.spr')),
                         [r for r in rows if r['wing'] != 3], {k: v for k, v in skip2.items()}) == [], 'a skipped wing is untouched in the build')
    check(any('wing 1 ' in b for b in cw.check_clean(Dat(ndat), Spr(nspr), rows, {(1, 0): {'action': 'skip'}})), 'a skipped wing that was cleaned is reported')
    open(ov, 'w').write('wing,group,action,args,reason\n1,0,skip,,\n')
    try:
        cw.read_overrides(ov)
        check(False, 'an override without a reason is refused')
    except SystemExit:
        pass
    s2 = cw.apply_override({'cx': 1.0, 'cy': 2.0, 'rx': 3.0, 'ry': 4.0, 'palette': []},
                           {'action': 'region', 'args': 'cx=5;ry=9', 'reason': 'x'})
    check((s2['cx'], s2['cy'], s2['rx'], s2['ry']) == (5.0, 2.0, 3.0, 9.0), 'region override changes the named numbers only')

    # ---- builds are byte identical
    out5 = tempfile.mkdtemp(prefix='cws_')
    _r, _l, a5 = run_build(dat_p, spr_p, rows, out5)
    check(open(nspr, 'rb').read() == open(os.path.join(a5.out_dir, 'Tibia.spr'), 'rb').read(), 'two builds are byte identical')

    if fails:
        print('%d failure(s)' % fails)
        return 1
    print('clean_wing_shadows_test: ok')
    return 0


if __name__ == '__main__':
    with contextlib.redirect_stderr(sys.stderr):
        sys.exit(main())
