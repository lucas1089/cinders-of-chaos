#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_inbox_icons_art_test.py : the committed inbox icon files against a rebuild, the
ids against the store item tables. No pair needed."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_inbox_icons_art as G  # noqa: E402
import gen_store_items_art as S  # noqa: E402
import import_art_things as I  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


atlas, things, sums, report = G.build(G.SRC_DIR)
check(all(not e and not b for _k, _t, e, b in report), 'every look passes its theme check')
check(atlas.shape == (32, 128, 4), 'atlas size')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
rows = I.read_things(G.THINGS)
check([r['mode'] for r in rows] == ['redraw'] * 4, 'redraw rows')
# the redrawn client and server ids are the ones of the store items (gen_store_items_art.LOOKS: ids 38608 + k)
store = {sid: 38608 + k for k, (_k, _n, _s, _t, _th, _c, sid) in enumerate(S.LOOKS)}
check(all(store[l[4]] == l[5] for l in G.LOOKS), 'client ids match the store items of pair 34')
check([l[0] for l in G.LOOKS] == ['inbox_loot', 'inbox_orbs', 'inbox_keys', 'inbox_ration'], 'four looks in store order')
check([r['key'] for r in rows] == [l[0] for l in G.LOOKS], 'things rows follow LOOKS')
check([r['extra'] for r in rows] == ['item=%d' % l[5] for l in G.LOOKS], 'redrawn client ids in the things file')
check(dict(p.split('=') for p in G.PICKS.split(',')) == {'loot': 'a', 'orbs': 'b', 'keys': 'a', 'ration': 'b'}, "owner's picks")
check(all(G.read_rgba(os.path.join(G.SRC_DIR, s + '.png')).shape == (32, 32, 4) for s in G.SHORT.values()), '32 px sources')
print('inbox icons test: %s' % ('OK' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
