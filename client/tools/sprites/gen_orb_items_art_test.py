#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_orb_items_art_test.py : the pure parts of gen_orb_items_art.py (cell cut, pack, source
checks, the atlas and things file, new ids) on synthetic cells, then the committed sheet, atlas, things file and the server
config (look ids). No pair needed."""
import csv
import os
import re
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_orb_items_art as G  # noqa: E402
from PIL import Image  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def raises(fn, *a):
    try:
        fn(*a)
    except (AssertionError, SystemExit):
        return True
    return False


def orb(k):
    c = np.zeros((32, 32, 4), np.uint8)
    c[6:26, 6:26] = (10 + k, 20 + k, 30 + k, 255)
    return c


# ---- cell cut and pack
check(len(G.LOOKS) == 18 and G.COLS * G.ROWS == 18, 'eighteen orbs in a 6 x 3 grid')
check(len({l[0] for l in G.LOOKS}) == 18 and len({l[2] for l in G.LOOKS}) == 18, 'slugs and server ids are unique')
with tempfile.TemporaryDirectory() as d:
    for k, (slug, *_r) in enumerate(G.LOOKS):
        Image.fromarray(orb(k), 'RGBA').save(os.path.join(d, slug + '.png'))
    sheet = G.pack(d)
    check(sheet.shape == (96, 192, 4), 'pack: 192 x 96')
    check(all(np.array_equal(G.cell(sheet, k), orb(k)) for k in range(18)), 'pack and cell: reading order of the grid')
    G.check_source(sheet)
    bad = orb(0)
    bad[10, 10, 3] = 100
    Image.fromarray(bad, 'RGBA').save(os.path.join(d, G.LOOKS[0][0] + '.png'))
    check(raises(G.pack, d), 'pack refuses partial alpha')
    Image.fromarray(np.zeros((16, 16, 4), np.uint8), 'RGBA').save(os.path.join(d, G.LOOKS[0][0] + '.png'))
    check(raises(G.pack, d), 'pack refuses a file that is not 32 x 32')
check(raises(G.check_source, sheet[:-32]), 'check_source refuses the wrong size')
dirty = sheet.copy()
dirty[0, 0, :3] = 5
check(raises(G.check_source, dirty), 'check_source refuses colour under alpha 0')
empty = sheet.copy()
empty[32:64, 0:32] = 0
check(raises(G.check_source, empty), 'check_source refuses an empty cell')

# ---- atlas and things file
atlas, things = G.build(sheet)
check(atlas.shape == (576, 32, 4), 'atlas is 32 x 576, the cells stacked')
check(all(np.array_equal(atlas[k * 32:(k + 1) * 32], G.cell(sheet, k)) for k in range(18)), 'atlas rows follow LOOKS')
rows = list(csv.DictReader(things.splitlines()))
new = [l for l in G.LOOKS if l[4] == 'new']
check(len(rows) == 10 == len(new) and len(G.strips()) == 8, 'ten new looks, eight redraws')
check([int(r['server_id']) for r in rows] == [l[2] for l in new], 'things rows: the new looks in LOOKS order, server ids')
check([r['flags'] for r in rows] == ['copy:%d' % l[3] for l in new], 'things rows copy the flags of the stock thing')
check(all(r['mode'] == 'replace' and r['phases'] == '1' and r['patterns'] == '1' and r['x'] == '0' for r in rows), 'one phase, one pattern, mode replace')
check([int(r['y']) // 32 for r in rows] == [k for k, l in enumerate(G.LOOKS) if l[4] == 'new'], 'things rows point at their atlas row')
ids = G.new_ids()
check(sorted(ids.values()) == list(range(G.FIRST_CLIENT_ID, G.FIRST_CLIENT_ID + 10)), 'new client ids are consecutive from FIRST_CLIENT_ID')
check(all(s.split('=')[0].isdigit() and s.split('@')[1].isdigit() for s in G.strips()), 'strip arguments are ID=FILE@ROW')
check(G.png_bytes(atlas) == G.png_bytes(atlas), 'png bytes are deterministic')

# ---- the committed files
src = np.asarray(Image.open(G.SOURCE).convert('RGBA'))
G.check_source(src)
atlas, things = G.build(src)
check(np.array_equal(np.asarray(Image.open(G.ATLAS).convert('RGBA')), atlas), 'committed orb_items.png is the build of orbs_src.png')
check(open(G.THINGS, encoding='utf-8').read() == things, 'committed orb_items.csv is the build of orbs_src.png')
check(len(G.style_report(src)) == 18, 'style report: a line per orb')

# ---- the server config knows the same ids: clientId (stock) and look (new) of each orb that gets its own client item
cfg = open(os.path.join(G.HERE, '..', '..', '..', 'server', 'data', 'lib', 'chaos_orbs_config.lua'), encoding='utf-8').read()
cfg = re.sub(r'--[^\n]*', '', cfg)
for slug, _n, sid, old, how in G.LOOKS:
    m = re.search(r'\{id = %d, key = "%s", clientId = (\d+)(?:, look = (\d+))?' % (sid, slug), cfg)
    if how == 'new':
        check(m is not None and int(m.group(1)) == old and m.group(2) and int(m.group(2)) == ids[slug],
              '%s: config has clientId %d and look %d' % (slug, old, ids[slug]))
    elif m:
        check(m.group(2) is None, '%s: an in-place look has no look id in the orb config' % slug)
gems = open(os.path.join(G.HERE, '..', '..', '..', 'server', 'data', 'lib', 'chaos_gems_config.lua'), encoding='utf-8').read()
check(re.search(r'look = 38641', gems) is not None and G.LOOKS[10][3] == 38641, 'Orb of Sockets keeps client 38641, redrawn in place')

print('orb items art test: %s' % ('OK' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
