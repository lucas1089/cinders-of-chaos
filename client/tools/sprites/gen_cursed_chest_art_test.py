#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_cursed_chest_art_test.py : the pure parts of gen_cursed_chest_art.py (the cut of a
64 x 64 canvas into the four tiles of a 2 x 2 item, the canvas rules, the things rows) and the committed files against
a rebuild. No pair needed."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_cursed_chest_art as G  # noqa: E402
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
back = np.zeros_like(a)
for (ww, hh), t in mine.items():
    back[(1 - hh) * 32:(2 - hh) * 32, (1 - ww) * 32:(2 - ww) * 32] = t
check(np.array_equal(back, a), 'the four tiles put back give the canvas')

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

# the committed sources, atlas, things and sums are what a build gives
atlas, things, sums, report = G.build(G.SRC_DIR)
check(all(not e and not b for _k, e, b, _w, _n in report), 'every look passes the style check on its own colours')
check(atlas.shape == (64, 64 * 14, 4), 'atlas size')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
rows = I.read_things(G.THINGS)
check([r['key'] for r in rows] == ['cursed_chest_a', 'cursed_chest_b', 'cursed_chest_c'], 'three rows in look order')
check(all((r['w'], r['h'], r['patterns'], r['flags'], r['mode']) == (2, 2, '1', 'copy:4073', 'new') for r in rows),
      'every row is a 2 x 2 of the flags of 4073, appended')
check([r['phases'] for r in rows] == ['5', '1', '8'], 'phases 5 / 1 / 8')
check([r['ex'].get('ms') for r in rows] == ['250', None, '200'], 'phase times 250 / - / 200 ms')
check([int(r['server_id']) for r in rows] == [32281, 32282, 32283], 'server ids 32281-32283')
check([r['x'] for r in rows] == [0, 320, 384], 'atlas columns follow the phases')
check(atlas.shape == (64, 64 * 14, 4), 'atlas: 14 cells')
# the ping-pong of C: cells 1..4 of the sequence 0 1 2 3 4 3 2 1 repeat frames 3 2 1
cells = [atlas[:, 384 + 64 * i:384 + 64 * (i + 1)] for i in range(8)]
check(np.array_equal(cells[5], cells[3]) and np.array_equal(cells[6], cells[2]) and np.array_equal(cells[7], cells[1]),
      'C ping-pong: phases 5-7 are frames 3, 2, 1')
check(not any(np.array_equal(cells[i], cells[j]) for i in range(5) for j in range(i)), 'C: five distinct frames')
for r in rows:
    fr = I.item_frames(r)[0]
    check(len(fr) == int(r['phases']) and all(f.shape == (64, 64, 4) for f in fr.values()), 'importer frames of ' + r['key'])
check(np.array_equal(I.item_frames(rows[0])[0][(0, 0, 0)], G.read_rgba(os.path.join(G.SRC_DIR, 'cursed_chest_a_f0.png'))),
      'the importer reads A frame 0 unchanged')

# a still look given as several frames: phases = frames, ms in extra (restore afterwards)
saved = G.LOOKS
G.LOOKS = (('x_a', (('cursed_chest_a_f0.png', 'p'), ('cursed_chest_a_f1.png', 'p')), (0, 1), 300, 1),
           ('x_b', (('cursed_chest_b.png', 'p'),), (0,), 250, 2))
_a, th, _s, rep = G.build(G.SRC_DIR)
G.LOOKS = saved
r2 = list(__import__('csv').DictReader(th.splitlines()))
check(_a.shape == (64, 192, 4) and len(rep) == 3, 'two frames and a still: three cells')
check((r2[0]['phases'], r2[0]['extra'], r2[1]['x'], r2[1]['phases'], r2[1]['extra']) == ('2', 'ms=300', '128', '1', ''),
      'phases, columns, ms')

print('gen_cursed_chest_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
