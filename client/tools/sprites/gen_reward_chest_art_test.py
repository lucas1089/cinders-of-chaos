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

print('gen_reward_chest_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
