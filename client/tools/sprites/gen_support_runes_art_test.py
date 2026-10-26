#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_support_runes_art_test.py : the pure parts of gen_support_runes_art.py (the canvas
rules, the things rows), the committed files against a rebuild, the icons of the support window against the Common looks,
and the ids against server/data/lib/chaos_supports_config.lua (every support rune points at its own client id and
copies the flags of its stock rune stone). No pair needed."""
import csv
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_support_runes_art as G  # noqa: E402
import import_art_things as I  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# canvas rules
good = np.zeros((32, 32, 4), np.uint8)
good[3:29, 8:24] = (90, 70, 60, 255)
check(G.problems_of(good) == [], 'a filled canvas passes')
check(G.problems_of(np.zeros((64, 64, 4), np.uint8)) != [], 'a 64 px picture is refused')
soft = good.copy(); soft[10, 10, 3] = 128
check(any('semi' in p for p in G.problems_of(soft)), 'semi-transparent pixels are refused')
ghost = good.copy(); ghost[0, 0] = (9, 9, 9, 0)
check(any('transparent' in p for p in G.problems_of(ghost)), 'colour under alpha 0 is refused')
tiny = np.zeros((32, 32, 4), np.uint8); tiny[14:18, 14:18] = (1, 2, 3, 255)
check(any('fill' in p for p in G.problems_of(tiny)), 'a small speck is refused')
check(any('empty' in p for p in G.problems_of(np.zeros((32, 32, 4), np.uint8))), 'an empty canvas is refused')

# the looks: 20 supports x 5 levels, ids in server order
rows = G.looks()
check(len(rows) == 100, 'a hundred looks')
check([(k, lv) for k, lv, *_r in rows] == [(k, lv) for k, _n in G.SUPPORTS for lv in range(1, 6)], 'support by support, levels 1 to 5')
check([r[3] for r in rows] == list(range(32101, 32201)), 'server ids 32101-32200')
check(G.client_id(0) == 38658 and G.client_id(99) == 38757, 'client ids 38658-38757')
check(rows[0][2] == 'common emberbrand rune' and rows[9][2] == 'mythic rimebrand rune', 'names agree with install_supports.py')

# the committed sources, atlas, things and sums are what a build gives
atlas, things, sums, report = G.build(G.SRC_DIR)
check(all(not e and not b for _k, e, b, _w, _n in report), 'every look passes the style check on its own colours')
check(atlas is not None and atlas.shape == (32 * 20, 32 * 5, 4), 'atlas size')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
trows = I.read_things(G.THINGS)
check(len(trows) == 100 and all((r['w'], r['h'], r['patterns'], r['phases'], r['mode'], r['cat']) == (1, 1, '1', '1', 'new', 'item')
                                for r in trows), 'a hundred 1 x 1 single-phase items, appended')
for i, r in enumerate(trows):
    fr = I.item_frames(r)[0]
    check(len(fr) == 1 and fr[(0, 0, 0)].shape == (32, 32, 4), 'importer frame of ' + r['key'])
    cell = atlas[(i // 5) * 32:(i // 5) * 32 + 32, (i % 5) * 32:(i % 5) * 32 + 32]
    check(np.array_equal(fr[(0, 0, 0)], cell), 'importer frame of %s is its atlas cell' % r['key'])
check(all(r['flags'].startswith('copy:') for r in trows), 'flags copied from a stock rune stone')
check(len({G.digest(atlas[(i // 5) * 32:(i // 5) * 32 + 32, (i % 5) * 32:(i % 5) * 32 + 32]) for i in range(100)}) == 100,
      'a hundred different pictures')

# one stone shape for all 100, and the five levels of a support differ only in the rim colour: the silhouettes agree
def sil(i):
    return atlas[(i // 5) * 32:(i // 5) * 32 + 32, (i % 5) * 32:(i % 5) * 32 + 32, 3] > 0
ref = sil(0)
for i in range(100):
    share = (ref & sil(i)).sum() / max(1, (ref | sil(i)).sum())
    check(share > 0.85, '%s: the stone silhouette matches the first one (%.2f)' % (rows[i][2], share))
for t in range(20):
    for lv in range(1, 5):
        a, b = sil(t * 5), sil(t * 5 + lv)
        check((a & b).sum() / max(1, (a | b).sum()) > 0.85, '%s: the level keeps the stone' % rows[t * 5 + lv][2])

# the icons of the window and action bar are the Common looks, byte for byte
for key, _n in G.SUPPORTS:
    p = os.path.join(G.ICON_DIR, key + '.png')
    check(os.path.exists(p) and open(p, 'rb').read() == G.icon_bytes(key), 'icon %s.png is the Common look' % key)

# the ids agree with the server config
cfg = open(G.CONFIG, encoding='utf-8').read()
check(re.search(r'\n\tfirstId = 32101,', cfg) is not None, 'config firstId 32101')
check(re.search(r'\n\tclientFirstId = %d,' % G.FIRST_CLIENT_ID, cfg) is not None, 'config clientFirstId is the first look')
first, conf = G.read_config()
sprites = [int(x) for x in re.findall(r'\d+', re.search(r'sprites\s*=\s*\{([^}]*)\}', cfg).group(1))]
check(all(s - G.STOCK_CLIENT_OFFSET > 20000 for s in sprites), 'stock rune stones are client items 22029..22042')
for i, ((key, _lv, _nm, sid, stock), r) in enumerate(zip(rows, trows)):
    check(int(r['server_id']) == sid, '%s: server id %d' % (r['key'], sid))
    check(r['flags'] == 'copy:%d' % stock, '%s copies the stock client id %d' % (r['key'], stock))
check([n for _k, n, _s in conf] == [n for _k, n in G.SUPPORTS], 'display names agree with the config')

print('gen_support_runes_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
