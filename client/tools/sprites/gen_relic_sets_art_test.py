#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_relic_sets_art_test.py : the pure parts of gen_relic_sets_art.py (the canvas rules, the things
rows), the committed files against a rebuild, and the ids against the server manifest (server/data/items/relic_sets.csv: the client ids,
server ids, names and kinds of the 65 looks). No pair needed."""
import csv
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_relic_sets_art as G  # noqa: E402
from gen_relic_sets_art import LOOKS  # noqa: E402
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
amulet = np.zeros((32, 32, 4), np.uint8); amulet[0:28, 11:20] = (1, 2, 3, 255)
check(G.problems_of(amulet) == [], 'a tall narrow amulet passes')

cids = [l[5] for l in LOOKS]
check(len(LOOKS) == 65 and cids == list(range(44446, 44511)), 'client ids 44446-44510 in a row, right after the last item of pair 57 (44445)')
check([l[6] for l in LOOKS] == list(range(48446, 48511)), 'server ids 48446-48510')
check(all(l[6] == l[5] + 4000 for l in LOOKS), 'server id = client id + 4000 (the pair 50 rule)')
check(len(set(l[0] for l in LOOKS)) == 65 and len(set(l[4] for l in LOOKS)) == 65, 'unique keys and names')
check(len(G.SETS) == 5 and [l[1] for l in LOOKS] == [s[0] for s in G.SETS for _ in range(13)], 'five sets of 13, in order')
kinds = [l[2] for l in LOOKS[:13]]
check(kinds[:10] == ['helmet', 'armor', 'legs', 'boots', 'shield', 'spellbook', 'sword', 'axe', 'club', 'bow']
      and kinds[11:] == ['ring', 'amulet'] and kinds[10] in ('wand', 'rod'), 'the 13 slots of a set')
check(all([l[2] for l in LOOKS[i * 13:i * 13 + 13]][:10] == kinds[:10] for i in range(5)), 'every set has the same slots')
check(all(l[2] in G.COPY for l in LOOKS), 'every kind has a stock item to copy the dat flags from')
levels = [s[3] for s in G.SETS]
check(levels == sorted(levels) and all(l[7] == s[3] for s in G.SETS for l in LOOKS if l[1] == s[0]), 'one level per set, rising')
check(all('|' not in l[8] and '=' not in l[8] and ';' not in l[8] for l in LOOKS), 'descriptions are safe in the extra field')
check(len(set(G.WAIVED) - set(G.KEYS)) == 0, 'waivers name real looks')
check(all(k in G.KEYS for k in G.REPLACED), 'replaced pictures name real looks')

srcs = {k: G.src_path(k) for k in G.KEYS}
atlas, things, sums, reports = G.build(srcs)
check(all(not e and not b for e, b, _w, _n in reports.values()), 'every look passes the style check on its own colours or a printed waiver')
check(atlas is not None and atlas.shape == (32, 32 * 65, 4), 'atlas size')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
check(open(G.SOURCES_CSV, encoding='utf-8').read() == G.sources_text(), 'sources file is up to date')
rows = I.read_things(G.THINGS)
check(len(rows) == 65 and all((r['w'], r['h'], r['patterns'], r['phases'], r['mode'], r['cat']) == (1, 1, '1', '1', 'new', 'item')
                              for r in rows) and [r['key'] for r in rows] == G.KEYS, 'sixty-five 1 x 1 single-phase items, appended in order')
for i, r in enumerate(rows):
    check(r['flags'] == 'copy:%d' % G.COPY[LOOKS[i][2]], '%s: dat flags of a stock item of its kind' % r['key'])
    fr = I.item_frames(r)[0]
    check(len(fr) == 1 and fr[(0, 0, 0)].shape == (32, 32, 4) and np.array_equal(fr[(0, 0, 0)], atlas[:, i * 32:(i + 1) * 32]),
          'importer frame of %s is its atlas cell' % r['key'])
with open(os.path.join(HERE, 'art_import', 'relic_sets_sources.csv'), newline='', encoding='utf-8') as f:
    src = {r['name']: r for r in csv.DictReader(f)}
check(sorted(src) == sorted(G.KEYS) and all(r['pack'] == 'PixelLab' for r in src.values()), 'every look credited to PixelLab')

# the server manifest (import_art_things.py --manifest-out of the things file, --server-offset 4000) agrees
with open(os.path.join(ROOT, 'server', 'data', 'items', 'relic_sets.csv'), newline='', encoding='utf-8') as f:
    man = {r['key']: r for r in csv.DictReader(f)}
check(sorted(man) == sorted(G.KEYS), 'server manifest has the 65 keys')
for look in LOOKS:
    key, kind, name, cid, sid = look[0], look[2], look[4], look[5], look[6]
    r = man.get(key)
    check(r is not None and (int(r['client_id']), int(r['server_id']), r['name'], r['kind'], r['mode']) ==
          (cid, sid, name, kind, 'new') and r['extra'] == G.extra_of(look),
          '%s: server manifest has client id %d, server id %d, name %s, kind %s, the same extra' % (key, cid, sid, name, kind))

print('gen_relic_sets_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
