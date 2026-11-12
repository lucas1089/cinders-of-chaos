#!/usr/bin/env python3
"""Tests of clean_pack_dither.py, gen_pair66_fx.py and the hard cut of gen_pack27_fx.clean_alpha on a small synthetic pair the test
draws itself (no real pair needed; numpy).

python3 -I client/tools/sprites/clean_pack_dither_test.py
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import check_pair_test as t  # noqa: E402
import clean_pack_dither as cd  # noqa: E402
import gen_pack27_fx as G27  # noqa: E402
import gen_pair66_fx as g66  # noqa: E402
import import_art_things as iat  # noqa: E402
from datspr import Dat, Spr  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


HALO, HALO2 = (23, 100, 192, 255), (12, 46, 120, 255)
CORE = (208, 250, 255, 255)
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])


def dithered(size=64, cx=32, cy=32, r=22, level=8):
    """a disc of two halo colours cut with the 4x4 Bayer threshold, the old import rule (level / 16 of the cell kept)"""
    img = np.zeros((size, size, 4), np.uint8)
    yy, xx = np.mgrid[0:size, 0:size]
    inside = np.hypot(xx - cx, yy - cy) <= r
    thr = np.tile(BAYER, (size // 4, size // 4))
    keep = inside & (thr < level)
    img[keep] = HALO
    img[keep & (((xx // 4) + (yy // 4)) % 2 == 0)] = HALO2
    return img


def frame_with_art():
    img = dithered()
    img[28:36, 28:36] = CORE                       # a solid core: stays
    for i in range(10):                            # a 1 px diagonal line of the core colour: stays
        img[4 + i, 4 + i] = CORE
    img[60, 3] = CORE                              # a lone spark: stays
    return img


def synthetic_pair(case, frames):
    """one 2x2 effect (id 1) with one frame per image in `frames`, plus an item (id 100) that shares nothing"""
    recs, ids, sprites = [], {}, []
    for img in frames:
        for hh in range(2):
            for ww in range(2):
                tile = np.ascontiguousarray(img[(1 - hh) * 32:(2 - hh) * 32, (1 - ww) * 32:(2 - ww) * 32])
                rec = iat.encode_sprite(tile)
                if rec is None:
                    sprites.append(0)
                    continue
                if rec not in ids:
                    recs.append(rec)
                    ids[rec] = len(recs)
                sprites.append(ids[rec])
    n = len(frames)
    eff = t.entry(b'', [t.group(sprites, w=2, h=2, phases=n, anim=(0, 0, 0, [60] * (2 * n)))])
    recs.append(iat.encode_sprite(np.full((32, 32, 4), 200, np.uint8)))
    items = [t.entry(bytes([17]), [t.group([len(recs)])])]
    return case.pair(recs, items, [], [eff], [])


def main():
    # ---- the rule on one canvas
    img = frame_with_art()
    out, m = cd.clean_canvas(img)
    halo_before = int(((img[..., 3] > 0)).sum())
    check(m.sum() > 100, 'the mesh goes: %d pixels' % m.sum())
    check((out[28:36, 28:36] == np.array(CORE)).all(), 'the solid core stays')
    check(all(tuple(out[4 + i, 4 + i]) == CORE for i in range(10)), 'a one pixel diagonal line stays')
    check(tuple(out[60, 3]) == CORE, 'a lone spark stays')
    check(not (m & (img[..., 3] == 0)).any(), 'only kept pixels go')
    kept = img[..., 3] > 0
    check((out[kept & ~m] == img[kept & ~m]).all(), 'colours never change')
    check((out[m] == 0).all(), 'a removed pixel is 0, 0, 0, 0')
    check(halo_before - int(m.sum()) < 0.2 * halo_before, 'the halo is gone, what stays is the art: %d of %d' % (halo_before - int(m.sum()), halo_before))
    solid = np.zeros((64, 64, 4), np.uint8)
    solid[10:50, 10:50] = HALO
    check(not cd.mesh_mask(solid).any(), 'a solid block is not mesh')
    line = np.zeros((64, 64, 4), np.uint8)
    for i in range(40):
        line[10 + i, 10 + i] = HALO
        line[10 + i, 50 - i] = HALO
    check(not cd.mesh_mask(line).any(), 'two crossing one pixel diagonal lines are not mesh')
    check(not cd.mesh_mask(np.zeros((64, 64, 4), np.uint8)).any(), 'an empty canvas has no mesh')
    # a line of another colour inside the mesh stays
    mixed = dithered()
    for i in range(20):
        mixed[20 + i, 20 + i] = CORE
    o2, m2 = cd.clean_canvas(mixed)
    check(all(tuple(o2[20 + i, 20 + i]) == CORE for i in range(20)), 'a bright line inside the mesh stays')

    # ---- a pair
    case = t.Case()
    frames = [frame_with_art(), dithered(level=6), frame_with_art()]
    dat_p, spr_p = synthetic_pair(case, frames)
    dat, spr = Dat(dat_p), Spr(spr_p)
    changed, stats, left = cd.plan(dat, spr)
    check(('effect', 1) in stats and not left, 'the effect is cleaned: %s %s' % (stats, left))
    check(len(changed) > 0, 'sprites to rewrite')

    class A:
        pass
    a = A()
    a.dat, a.spr, a.out_dir, a.dry_run, a.stats_out = dat_p, spr_p, os.path.join(case.dir, 'out'), False, os.path.join(case.dir, 'stats.csv')
    log = io.StringIO()
    cd.build(a, log=lambda s: log.write(s + '\n'))
    nd, ns = Dat(os.path.join(a.out_dir, 'Tibia.dat')), Spr(os.path.join(a.out_dir, 'Tibia.spr'))
    check(nd.data == dat.data, 'the dat is byte identical')
    check(open(a.stats_out).read().splitlines()[0] == 'kind,id,removed,frames,opaque' and ('effect,1,' in open(a.stats_out).read()), 'the stats csv lists the effect')
    check(('e', 4090) in cd.SKIP and ('e', 4101) in cd.SKIP and ('e', 4089) not in cd.SKIP and ('e', 4102) not in cd.SKIP, 'the loot beams 4090-4101 are skipped')
    check(ns.count == spr.count, 'the spr keeps its count')
    new_frames = [f for _k, f, _tl in cd.canvases(nd.effects[0], ns)]
    for old, new in zip(frames, new_frames):
        o_, m_ = cd.clean_canvas(old)
        # tile borders make single pixels differ from the whole-canvas rule only by never removing more than it
        gone = (old[..., 3] > 0) & (new[..., 3] == 0)
        check((gone <= m_).all(), 'only mesh pixels went')
        check(gone.sum() >= 0.9 * m_.sum(), 'nearly all mesh pixels went: %d of %d' % (gone.sum(), m_.sum()))
    check(cd.check_clean(nd, ns) == [], 'check-clean passes on the output')
    check(cd.check_clean(dat, spr) != [], 'check-clean fails on the input')
    # a second run changes nothing
    changed2, stats2, left2 = cd.plan(nd, ns)
    check(not changed2 and not stats2, 'idempotent: a second run has nothing to do')
    # an item that shares a sprite blocks the effect: it stays whole
    shared = Dat(dat_p)
    sid = int(shared.effects[0].sprites[0]) or int(shared.effects[0].sprites[1])
    dat2, spr2 = synthetic_pair_shared(case, frames, sid)
    ch3, st3, left3 = cd.plan(Dat(dat2), Spr(spr2))
    check(('effect', 1) in left3 and not ch3, 'a sprite shared with an item leaves the effect whole: %s' % left3)

    # ---- the hard cut of the import
    fr = np.zeros((8, 8, 4), np.uint8)
    fr[0, 0] = (10, 20, 30, 255)
    fr[0, 1] = (10, 20, 30, 128)
    fr[0, 2] = (10, 20, 30, 127)
    fr[0, 3] = (10, 20, 30, 1)
    cut = G27.clean_alpha(fr)
    check(cut[0, 0, 3] == 255 and cut[0, 1, 3] == 255 and cut[0, 2, 3] == 0 and cut[0, 3, 3] == 0, 'clean_alpha: a hard cut at 0.5')
    check(tuple(cut[0, 1, :3]) == (10, 20, 30) and not cut[0, 2].any(), 'clean_alpha: colour kept, cut pixel is 0')
    soft = np.zeros((16, 16, 4), np.uint8)
    soft[...] = (50, 60, 70, 140)
    c2 = G27.clean_alpha(soft)
    check((c2[..., 3] == 255).all(), 'clean_alpha: a flat alpha 0.55 area is whole, not a mesh')
    soft[..., 3] = 100
    check(not G27.clean_alpha(soft).any(), 'clean_alpha: a flat alpha 0.39 area is gone, not a mesh')

    # ---- the recoloured nova
    r = np.zeros((4, 4, 4), np.uint8)
    r[0, 0] = (230, 190, 60, 255)               # gold
    r[0, 1] = (255, 255, 255, 255)              # white
    r[0, 2] = (230, 190, 60, 0)
    h = g66.hue_shift(r, 175.0)
    check(h[0, 0, 2] > h[0, 0, 0] and h[0, 0, 3] == 255, 'gold turns blue: %s' % (h[0, 0],))
    check(tuple(h[0, 1]) == (255, 255, 255, 255), 'white stays')
    check(not h[0, 2].any(), 'a transparent pixel stays 0')
    check(max(h[0, 0, :3]) == 230, 'the value (brightest channel) stays')

    print('clean_pack_dither_test: %s' % ('FAIL (%d)' % fails if fails else 'ok'))
    return 1 if fails else 0


def synthetic_pair_shared(case, frames, sid):
    """the same pair with an item that uses sprite `sid`"""
    recs, ids, sprites = [], {}, []
    for img in frames:
        for hh in range(2):
            for ww in range(2):
                tile = np.ascontiguousarray(img[(1 - hh) * 32:(2 - hh) * 32, (1 - ww) * 32:(2 - ww) * 32])
                rec = iat.encode_sprite(tile)
                if rec is None:
                    sprites.append(0)
                    continue
                if rec not in ids:
                    recs.append(rec)
                    ids[rec] = len(recs)
                sprites.append(ids[rec])
    n = len(frames)
    eff = t.entry(b'', [t.group(sprites, w=2, h=2, phases=n, anim=(0, 0, 0, [60] * (2 * n)))])
    items = [t.entry(bytes([17]), [t.group([sid])])]
    return case.pair(recs, items, [], [eff], [])


if __name__ == '__main__':
    sys.exit(main())
