#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_reward_chest_art_test.py : the pure parts of gen_reward_chest_art.py (the cut of a
64 x 64 canvas into the four tiles of a 2 x 2 item, the canvas rules, the things row) and the committed files against
a rebuild. No pair needed."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_reward_chest_art as G  # noqa: E402
import import_art_things as I  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# the cut is the importer's: tile (ww, hh) with ww = 0 the right column, hh = 0 the bottom row
a = np.zeros((64, 64, 4), np.uint8)
rng = np.random.RandomState(7)
a[..., :3] = rng.randint(0, 256, (64, 64, 3))
a[..., 3] = 255
mine, theirs = G.tiles(a), I.tiles_of(a, 2, 2)
check(sorted(mine) == sorted(theirs) == [(0, 0), (0, 1), (1, 0), (1, 1)], 'four tiles')
check(all(np.array_equal(mine[k], theirs[k]) for k in mine), 'the cut equals import_art_things.tiles_of')
check(np.array_equal(mine[(0, 0)], a[32:, 32:]) and np.array_equal(mine[(1, 1)], a[:32, :32]), 'bottom right is tile (0, 0)')

# canvas rules
good = np.zeros((64, 64, 4), np.uint8)
good[4:60, 2:62] = (90, 40, 40, 255)
check(G.problems_of(good) == [], 'a filled canvas passes')
check(G.problems_of(np.zeros((32, 32, 4), np.uint8)) != [], 'a 32 px picture is refused')
soft = good.copy(); soft[10, 10, 3] = 128
check(any('semi' in p for p in G.problems_of(soft)), 'semi-transparent pixels are refused')
ghost = good.copy(); ghost[0, 0] = (9, 9, 9, 0)
check(any('transparent' in p for p in G.problems_of(ghost)), 'colour under alpha 0 is refused')
tiny = np.zeros((64, 64, 4), np.uint8); tiny[28:36, 28:36] = (1, 2, 3, 255)
check(any('fill' in p for p in G.problems_of(tiny)), 'a small speck is refused')
check(any('empty' in p for p in G.problems_of(np.zeros((64, 64, 4), np.uint8))), 'an empty canvas is refused')

# the committed source, atlas, things and sums are what a build gives
atlas, things, sums, report = G.build(G.SRC_DIR)
check(all(not e and not b for _k, e, b, _w, _n in report), 'the look passes the style check on its own colours')
check(atlas.shape == (64, 64, 4), 'atlas size: one cell')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
rows = I.read_things(G.THINGS)
check([r['key'] for r in rows] == ['reward_chest'], 'one row')
r = rows[0]
check((r['w'], r['h'], r['patterns'], r['phases'], r['flags'], r['mode']) == (2, 2, '1', '1', 'copy:19250', 'new'),
      'a 2 x 2 still of the flags of 19250, appended')
check(int(r['server_id']) == 32310, 'server id 32310')
fr = I.item_frames(r)[0]
check(len(fr) == 1 and all(f.shape == (64, 64, 4) for f in fr.values()), 'importer frame')
src = G.read_rgba(os.path.join(G.SRC_DIR, 'reward_chest.png'))
check(G.MIRROR and np.array_equal(fr[(0, 0, 0)], src[:, ::-1]) and not np.array_equal(src, src[:, ::-1]), 'the importer reads the mirrored source')
check(np.array_equal(atlas, src[:, ::-1]), 'the atlas is the source mirrored')

# the small (one tile) look
check(G.problems_of(np.zeros((32, 32, 4), np.uint8), 32) != [], 'an empty 32 px canvas is refused')
ok32 = np.zeros((32, 32, 4), np.uint8); ok32[2:30, 1:31] = (90, 40, 40, 255)
check(G.problems_of(ok32, 32) == [], 'a filled 32 px canvas passes')
check(G.problems_of(ok32) != [], 'a 32 px canvas is not a 64 px one')
tiny32 = np.zeros((32, 32, 4), np.uint8); tiny32[14:18, 14:18] = (1, 2, 3, 255)
check(any('fill' in p for p in G.problems_of(tiny32, 32)), 'a small speck on a 32 px canvas is refused')
satlas, sthings, ssums, serrs, sbad, _swarn, _sn = G.build_small(G.SMALL_SRC)
check(not serrs and not sbad, 'the small look passes the style check on its own colours')
check(satlas.shape == (32, 32, 4), 'small atlas size: one 32 px cell')
check(np.array_equal(G.read_rgba(G.SMALL_ATLAS), satlas), 'small atlas on disk is up to date')
check(open(G.SMALL_THINGS, encoding='utf-8').read() == sthings, 'small things file is up to date')
check(open(G.SMALL_SUMS, encoding='utf-8').read() == ssums, 'small sums file is up to date')
srows = I.read_things(G.SMALL_THINGS)
check([r['key'] for r in srows] == ['reward_chest_small'], 'one small row')
sr = srows[0]
check((sr['w'], sr['h'], sr['patterns'], sr['phases'], sr['flags'], sr['mode']) == (1, 1, '1', '1', 'copy:19250', 'new'),
      'a 1 x 1 still of the flags of 19250, appended')
check(int(sr['server_id']) == G.SMALL_SERVER_ID == 32311 and G.SMALL_CLIENT_ID == 38758, 'ids 32311 / 38758')
sfr = I.item_frames(sr)[0]
check(len(sfr) == 1 and all(f.shape == (32, 32, 4) for f in sfr.values()), 'small importer frame')
ssrc = G.read_rgba(G.SMALL_SRC)
check(G.MIRROR_SMALL and np.array_equal(satlas, ssrc[:, ::-1]) and not np.array_equal(ssrc, ssrc[:, ::-1]),
      'the small atlas is the source mirrored')
check(np.array_equal(sfr[(0, 0, 0)], satlas), 'the importer reads the small atlas')

# the front look (pair 53): squeeze fit, recipe files without pixels
sq = np.zeros((6, 8, 4), np.uint8); sq[..., 3] = 255
sq[..., 0] = np.arange(8)[None, :] * 10; sq[..., 1] = np.arange(6)[:, None] * 10
sq[2, :, 1] = sq[1, :, 1]; sq[:, 3, 0] = sq[:, 2, 0]   # row 2 repeats row 1, column 3 repeats column 2
sqz, kr, kc = G.squeeze(sq, 1, 1)
check(sqz.shape == (5, 7, 4) and kr == [0, 2, 3, 4, 5] and kc == [0, 1, 3, 4, 5, 6, 7] and kc[-1] == 7, 'squeeze drops the duplicate lines')
check(all(any((sqz[i, j] == sq[a_, b_]).all() for a_ in kr for b_ in kc) for i in range(5) for j in range(7)), 'squeeze keeps source pixels')
check(np.array_equal(G.squeeze(sq, 0, 0)[0], sq), 'squeeze 0 changes nothing')
big = np.zeros((38, 35, 4), np.uint8); big[..., 3] = 255
big[..., 0] = rng.randint(0, 256, (38, 35)); big[..., 1] = rng.randint(0, 256, (38, 35))
cv, rr, cc = G.fit_front(np.pad(big, ((5, 5), (6, 6), (0, 0))))[:3]
check(cv.shape == (32, 32, 4) and len(rr) == 6 and len(cc) == 3, 'fit_front: 35 x 38 -> 32 x 32 (3 columns, 6 rows out)')
check((cv[-1, :, 3] > 0).any(), 'fit_front is bottom aligned')
try:
    G.fit_front(np.zeros((40, 40, 4), np.uint8)); check(False, 'an empty picture is refused')
except ValueError:
    pass
th, sm = G.front_texts(big, cv, rr, cc)
check('redraw' in th and 'item=38758' in th and '32311' in th and 'squeeze_rows=' in th, 'front things row: redraw, ids, recipe')
check(sm.count('\n') == 2, 'front sums: two digests')
check(os.path.exists(G.FRONT_THINGS) and os.path.exists(G.FRONT_SUMS), 'front recipe files are committed')

print('gen_reward_chest_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
