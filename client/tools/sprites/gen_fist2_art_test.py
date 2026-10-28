#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_fist2_art_test.py : the pure parts of gen_fist2_art.py (the canvas rules, the things
rows), the committed files against a rebuild, and the ids against the server manifests (server/data/items/fist_claws.csv,
fist_items.csv: the client ids and server ids of the thirteen looks). No pair needed."""
import csv
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_fist2_art as G  # noqa: E402
from gen_fist2_art import LOOKS  # noqa: E402
import import_art_things as I  # noqa: E402

failed = 0
ROOT = os.path.join(HERE, '..', '..', '..')


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


good = np.zeros((32, 32, 4), np.uint8)
good[4:28, 4:28] = (90, 40, 140, 255)
check(G.problems_of(good) == [], 'a filled canvas passes')
check(G.problems_of(np.zeros((64, 64, 4), np.uint8)) != [], 'a 64 px picture is refused')
soft = good.copy(); soft[10, 10, 3] = 128
check(any('semi' in p for p in G.problems_of(soft)), 'semi-transparent pixels are refused')
ghost = good.copy(); ghost[0, 0] = (9, 9, 9, 0)
check(any('transparent' in p for p in G.problems_of(ghost)), 'colour under alpha 0 is refused')
tiny = np.zeros((32, 32, 4), np.uint8); tiny[14:18, 14:18] = (1, 2, 3, 255)
check(any('fill' in p for p in G.problems_of(tiny)), 'a small speck is refused')
check(any('empty' in p for p in G.problems_of(np.zeros((32, 32, 4), np.uint8))), 'an empty canvas is refused')

cids = [l[3] for l in LOOKS]
check(cids == list(range(44399, 44412)), 'client ids 44399-44411 in a row, right after pair 55')
check([l[4] for l in LOOKS] == list(range(40003, 40013)) + [48409, 48410, 48411], 'server ids')
check(all(l[4] == l[3] + 4000 for l in LOOKS[10:]), 'new items: server id = client id + 4000 (the pair 50 rule)')
check(len(set(G.WAIVED) - set(G.KEYS)) == 0, 'waivers name real looks')

srcs = {k: G.src_path(k) for k in G.KEYS}
atlas, things, sums, reports = G.build(srcs)
check(all(not e and not b for e, b, _w, _n in reports.values()), 'every look passes the style check on its own colours')
check(atlas is not None and atlas.shape == (32, 32 * 13, 4), 'atlas size')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
rows = I.read_things(G.THINGS)
check(len(rows) == 13 and all((r['w'], r['h'], r['patterns'], r['phases'], r['mode'], r['cat'], r['flags']) ==
                              (1, 1, '1', '1', 'new', 'item', 'copy:3412') for r in rows)
      and [r['key'] for r in rows] == G.KEYS, 'thirteen 1 x 1 single-phase items, appended in order')
for i, r in enumerate(rows):
    fr = I.item_frames(r)[0]
    check(len(fr) == 1 and fr[(0, 0, 0)].shape == (32, 32, 4) and np.array_equal(fr[(0, 0, 0)], atlas[:, i * 32:(i + 1) * 32]),
          'importer frame of %s is its atlas cell' % r['key'])
with open(os.path.join(HERE, 'art_import', 'fist2_sources.csv'), newline='', encoding='utf-8') as f:
    src = {r['name']: r for r in csv.DictReader(f)}
check(sorted(src) == sorted(G.KEYS) and all(r['pack'] == 'PixelLab' for r in src.values()), 'every look credited to PixelLab')

# the server manifests agree: each look is the client id of its fist weapon
man = {}
for fn in ('fist_claws.csv', 'fist_items.csv'):
    with open(os.path.join(ROOT, 'server', 'data', 'items', fn), newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            man[r['key']] = r
for key, _kind, name, cid, sid in LOOKS:
    r = man.get(key)
    check(r is not None and (int(r['client_id']), int(r['server_id']), r['name']) == (cid, sid, name),
          '%s: server manifest has client id %d, server id %d, name %s' % (key, cid, sid, name))

print('gen_fist2_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
