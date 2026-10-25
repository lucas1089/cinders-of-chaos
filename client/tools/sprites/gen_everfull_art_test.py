#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_everfull_art_test.py : the pure parts of gen_everfull_art.py (the canvas rules, the
things rows) and the committed files against a rebuild, and the ids against server/data/scripts/chaos/potions_config.lua
(every Everfull server item points at its own client id). No pair needed."""
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_everfull_art as G  # noqa: E402
import import_art_things as I  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# canvas rules
good = np.zeros((32, 32, 4), np.uint8)
good[3:30, 8:24] = (90, 40, 40, 255)
check(G.problems_of(good) == [], 'a filled canvas passes')
check(G.problems_of(np.zeros((64, 64, 4), np.uint8)) != [], 'a 64 px picture is refused')
soft = good.copy(); soft[10, 10, 3] = 128
check(any('semi' in p for p in G.problems_of(soft)), 'semi-transparent pixels are refused')
ghost = good.copy(); ghost[0, 0] = (9, 9, 9, 0)
check(any('transparent' in p for p in G.problems_of(ghost)), 'colour under alpha 0 is refused')
tiny = np.zeros((32, 32, 4), np.uint8); tiny[14:18, 14:18] = (1, 2, 3, 255)
check(any('fill' in p for p in G.problems_of(tiny)), 'a small speck is refused')
check(any('empty' in p for p in G.problems_of(np.zeros((32, 32, 4), np.uint8))), 'an empty canvas is refused')

# the looks: twelve, three lines of four tiers, unique ids
check(len(G.LOOKS) == 12, 'twelve looks')
check([(l, t) for l, t, *_r in G.LOOKS] == [(l, t) for l in ('health', 'mana', 'spirit') for t in (1, 2, 3, 4)],
      'health, mana, spirit, tiers 1 to 4')
check(len({s for *_r, s, _n in G.LOOKS}) == 12, 'twelve server ids')
check(G.client_id(0) == 38645 and G.client_id(11) == 38656, 'client ids 38645-38656')

# the committed sources, atlas, things and sums are what a build gives
atlas, things, sums, report = G.build(G.SRC_DIR)
check(all(not e and not b for _k, e, b, _w, _n in report), 'every look passes the style check on its own colours')
check(atlas is not None and atlas.shape == (32, 32 * 12, 4), 'atlas size')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
rows = I.read_things(G.THINGS)
check(len(rows) == 12 and all((r['w'], r['h'], r['patterns'], r['phases'], r['mode'], r['cat']) == (1, 1, '1', '1', 'new', 'item')
                              for r in rows), 'twelve 1 x 1 single-phase items, appended')
check([r['x'] for r in rows] == [32 * i for i in range(12)], 'atlas columns')
for r in rows:
    fr = I.item_frames(r)[0]
    check(len(fr) == 1 and fr[(0, 0, 0)].shape == (32, 32, 4), 'importer frame of ' + r['key'])
check(all(r['flags'].startswith('copy:') for r in rows), 'flags copied from a stock potion')
check(all(not np.array_equal(atlas[:, 32 * i:32 * i + 32], atlas[:, 32 * j:32 * j + 32]) for i in range(12) for j in range(i)),
      'twelve different pictures')

# the same flask shape per tier in the three colours: the silhouettes of a tier agree closely (PixelLab edits, owner approved)
def sil(i):
    return atlas[:, 32 * i:32 * i + 32, 3] > 0
for t in range(4):
    base = sil(t)
    for line in (1, 2):
        other = sil(line * 4 + t)
        share = (base & other).sum() / max(1, (base | other).sum())
        check(share > 0.8, 'tier %d: the %s silhouette matches health (%.2f)' % (t + 1, ('mana', 'spirit')[line - 1], share))

# the ids agree with the server config: server id -> client id, name
cfg = open(os.path.join(HERE, '..', '..', '..', 'server', 'data', 'scripts', 'chaos', 'potions_config.lua'), encoding='utf-8').read()
body = re.search(r'\n\teverfull = \{(.*?)\n\t\},?\n', cfg, re.S).group(1)
conf = {}
for chunk in re.findall(r'\n\t\t\{(.*?)\}(?=,?\n\t\t\{|\s*$)', body + '\n', re.S):
    sid = int(re.search(r'\bid\s*=\s*(\d+)', chunk).group(1))
    cid = re.search(r'\bclientId\s*=\s*(\d+)', chunk)
    conf[sid] = (int(cid.group(1)) if cid else None, re.search(r'\bname\s*=\s*"([^"]*)"', chunk).group(1))
check(sorted(conf) == sorted(s for *_r, s, _n in G.LOOKS), 'potions_config.lua everfull has the twelve server ids')
for i, (line, tier, _stock, sid, name) in enumerate(G.LOOKS):
    check(conf.get(sid, (None, None))[0] == G.client_id(i), 'server %d (%s) has clientId %d' % (sid, name, G.client_id(i)))
    check(conf.get(sid, (None, None))[1] == name, 'server %d is named "%s"' % (sid, name))

print('gen_everfull_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
