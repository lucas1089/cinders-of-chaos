#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_portal_art_test.py : the pure parts of gen_portal_art.py (the canvas rules, the
things rows), the committed files against a rebuild, the mana globe against the blue recolour of the health globe, and the
ids against server/data/scripts/chaos/pickups_config.lua (each pickup points at its new client id and the stock client id it
is copied from; the Ember Orb keeps 25045). No pair needed."""
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_portal_art as G  # noqa: E402
from gen_portal_art import LOOKS  # noqa: E402
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

check([(l[0], l[3], l[4]) for l in LOOKS] == [('ember_portal', 44396, 32090), ('health_globe', 44397, 32088),
                                              ('mana_globe', 44398, 32089)], 'ids')
srcs = {k: G.src_path(k) for k in G.KEYS}
atlas, things, sums, reports = G.build(srcs)
check(all(not e and not b for e, b, _w, _n in reports.values()), 'every look passes the style check on its own colours')
check(atlas is not None and atlas.shape == (32, 96, 4), 'atlas size')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
rows = I.read_things(G.THINGS)
check(len(rows) == 3 and all((r['w'], r['h'], r['patterns'], r['phases'], r['mode'], r['cat'], r['flags']) ==
                             (1, 1, '1', '1', 'new', 'item', 'stackable') for r in rows)
      and [r['key'] for r in rows] == G.KEYS, 'three 1 x 1 single-phase stackable items, appended in order')
for i, r in enumerate(rows):
    fr = I.item_frames(r)[0]
    check(len(fr) == 1 and fr[(0, 0, 0)].shape == (32, 32, 4) and np.array_equal(fr[(0, 0, 0)], atlas[:, i * 32:(i + 1) * 32]),
          'importer frame of %s is its atlas cell' % r['key'])
src = open(os.path.join(HERE, 'art_import', 'portal_sources.csv'), encoding='utf-8').read()
for k in G.KEYS:
    check(('\n' + k + ',') in ('\n' + src), '%s credited in portal_sources.csv' % k)
check('453273cc-5c1c-4f4e-862d-4a30a4e27ef1' in src, 'health globe job id in the sources')

# the mana globe is the owner-approved blue recolour of the health globe (within 1 per channel: rounding)
hp, mp = G.read_rgba(G.src_path('health_globe')), G.read_rgba(G.src_path('mana_globe'))
check(np.array_equal(hp[..., 3], mp[..., 3]), 'mana globe: same shape as the health globe')
check(int(np.abs(G.recolour_blue(hp).astype(int) - mp.astype(int)).max()) <= 1, 'mana globe: the blue recolour of the health globe')
check(not np.array_equal(hp, mp), 'mana globe differs from the health globe')
dark = (mp[..., 3] > 0) & (hp[..., :3] == mp[..., :3]).all(axis=2)
check(dark.sum() > 20, 'the dark base and the glints keep their colours')

cfg = open(os.path.join(ROOT, 'server', 'data', 'scripts', 'chaos', 'pickups_config.lua'), encoding='utf-8').read()
for key, sid, cid, stock in (('ember', 32090, 44396, 25045), ('health_globe', 32088, 44397, 7618), ('mana_globe', 32089, 44398, 7620)):
    m = re.search(r'key = "%s", id = (\d+), clientId = (\d+), stockClientId = (\d+)' % key, cfg)
    check(m and (int(m.group(1)), int(m.group(2)), int(m.group(3))) == (sid, cid, stock),
          'pickups_config.lua: %s has clientId %d copied from stock client id %d' % (key, cid, stock))
orbs = open(os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_orbs_config.lua'), encoding='utf-8').read()
check(re.search(r'id = 32258, key = "ember", clientId = 25045', orbs) is not None, 'the Ember Orb keeps client id 25045')

print('gen_portal_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
