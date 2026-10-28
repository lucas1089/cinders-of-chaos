#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_weapons800_art_test.py : the pure parts of gen_weapons800_art.py (the canvas rules, the things
rows), the committed files against a rebuild, and the ids against the server manifest (server/data/items/weapons800.csv: the client ids,
server ids, names and kinds of the 34 looks). No pair needed."""
import csv
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_weapons800_art as G  # noqa: E402
from gen_weapons800_art import LOOKS  # noqa: E402
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
check(len(LOOKS) == 34 and cids == list(range(44412, 44446)), 'client ids 44412-44445 in a row, right after the fist looks (44411)')
check([l[4] for l in LOOKS] == list(range(48412, 48446)), 'server ids 48412-48445')
check(all(l[4] == l[3] + 4000 for l in LOOKS), 'server id = client id + 4000 (the pair 50 rule)')
check(len(set(l[0] for l in LOOKS)) == 34 and len(set(l[2] for l in LOOKS)) == 34, 'unique keys and names')
types = [l[1] for l in LOOKS]
check([types.count(t) for t in ('bow', 'crossbow', 'wand', 'rod', 'sword2', 'axe2', 'club2')] == [9, 4, 9, 9, 1, 1, 1], 'nine bows, four crossbows, nine wands, nine rods, three two-handed melee weapons')
check(all(t in G.KIND for t in types), 'every type has a things kind')
check(all(820 <= l[5] <= 2150 for l in LOOKS), 'levels 820-2150 (all above 800)')
check(all('|' not in l[8] and '=' not in l[8] and ';' not in l[8] for l in LOOKS), 'descriptions are safe in the extra field')
check(len(set(G.WAIVED) - set(G.KEYS)) == 0, 'waivers name real looks')
check(sorted(G.SOURCES) == sorted(G.KEYS), 'a candidate set and tile for every look')

srcs = {k: G.src_path(k) for k in G.KEYS}
atlas, things, sums, reports = G.build(srcs)
check(all(not e and not b for e, b, _w, _n in reports.values()), 'every look passes the style check on its own colours')
check(atlas is not None and atlas.shape == (32, 32 * 34, 4), 'atlas size')
check(np.array_equal(G.read_rgba(G.ATLAS), atlas), 'atlas on disk is up to date')
check(open(G.THINGS, encoding='utf-8').read() == things, 'things file is up to date')
check(open(G.SUMS, encoding='utf-8').read() == sums, 'sums file is up to date')
check(open(G.SOURCES_CSV, encoding='utf-8').read() == G.sources_text(), 'sources file is up to date')
rows = I.read_things(G.THINGS)
check(len(rows) == 34 and all((r['w'], r['h'], r['patterns'], r['phases'], r['mode'], r['cat']) == (1, 1, '1', '1', 'new', 'item')
                              for r in rows) and [r['key'] for r in rows] == G.KEYS, 'thirty-four 1 x 1 single-phase items, appended in order')
for i, r in enumerate(rows):
    check(r['flags'] == 'copy:%d' % G.COPY[G.KIND[LOOKS[i][1]]], '%s: dat flags of a stock item of its kind' % r['key'])
    fr = I.item_frames(r)[0]
    check(len(fr) == 1 and fr[(0, 0, 0)].shape == (32, 32, 4) and np.array_equal(fr[(0, 0, 0)], atlas[:, i * 32:(i + 1) * 32]),
          'importer frame of %s is its atlas cell' % r['key'])
with open(os.path.join(HERE, 'art_import', 'weapons800_sources.csv'), newline='', encoding='utf-8') as f:
    src = {r['name']: r for r in csv.DictReader(f)}
check(sorted(src) == sorted(G.KEYS) and all(r['pack'] == 'PixelLab' for r in src.values()), 'every look credited to PixelLab')

# the server manifest (import_art_things.py --manifest-out of the things file, --server-offset 4000) agrees
with open(os.path.join(ROOT, 'server', 'data', 'items', 'weapons800.csv'), newline='', encoding='utf-8') as f:
    man = {r['key']: r for r in csv.DictReader(f)}
check(sorted(man) == sorted(G.KEYS), 'server manifest has the 34 keys')
for look in LOOKS:
    key, typ, name, cid, sid = look[:5]
    r = man.get(key)
    check(r is not None and (int(r['client_id']), int(r['server_id']), r['name'], r['kind'], r['mode']) ==
          (cid, sid, name, G.KIND[typ], 'new') and r['extra'] == G.extra_of(look),
          '%s: server manifest has client id %d, server id %d, name %s, kind %s, the same extra' % (key, cid, sid, name, G.KIND[typ]))
    check(r is not None and int(r['otb_flags']) == (112 if G.KIND[typ] in ('sword', 'axe', 'club') else 96),
          '%s: items.otb flags of its kind' % key)

print('gen_weapons800_art_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
