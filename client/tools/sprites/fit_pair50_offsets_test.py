#!/usr/bin/env python3
"""python3 -I client/tools/sprites/fit_pair50_offsets_test.py : the offset fit of fit_pair50_offsets.py on synthetic art
(no pair needed; numpy), and the committed csv against the Lua table it feeds (O520)."""
import csv
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fit_pair50_offsets as F  # noqa: E402

ROOT = F.ROOT
failed = 0


def check(cond, what):
    global failed
    if not cond:
        failed += 1
        print('FAIL', what)


# the error of an offset: a 2x2 sent at 0 has its bottom-right tile on the target (tile middle at px 48 of 64)
check(F.axis_error(48, 2, 0) == 0, 'art in the bottom-right tile, sent at 0, is on the target')
check(F.axis_error(48, 2, 1) == 32, 'the same art sent at +1 lands a whole tile away')
check(F.axis_error(16, 2, 1) == 0, 'art in the top-left tile, sent at +1, is on the target')
check(F.axis_error(80, 3, 0) == 0 and F.axis_error(48, 3, 1) == 0 and F.axis_error(16, 3, 2) == 0, '3 tiles')

# the fit: art in the middle of the canvas keeps the plain rule, art in the bottom-right tile moves to 0
check(F.fit((32, 32), 2, 2) == (1, 1), 'a centred 2x2 keeps (1, 1)')
check(F.fit((48, 48), 2, 2) == (0, 0), 'a 2x2 drawn in its bottom-right tile goes to (0, 0)')
check(F.fit((48, 16), 2, 2) == (0, 1), 'each axis on its own')
check(F.fit((38, 37), 2, 2) == (0, 0), 'a cloud 22 px off (Dreamrot 4579) moves')
check(F.fit((34, 34), 2, 2) == (1, 1), 'a little off the middle (18 px): the default stays')
check(F.fit((112, 112), 4, 4) == (0, 0), 'a 4x4 drawn in its bottom-right tile goes to (0, 0)')
check(F.fit((64, 64), 4, 4) == (2, 2), 'a centred 4x4 keeps (2, 2)')
check(F.fit((48, 48), 3, 3) == (1, 1), 'a centred 3x3 keeps (1, 1)')
check(F.fit(None, 2, 3) == (1, 1), 'no pixels: the plain rule')
check(F.fit((16, 16), 1, 1) == (0, 0), '1x1 is always 0')

# the centre of frames: alpha weighted over all phases
a = np.zeros((64, 64, 4), np.uint8)
a[32:64, 32:64, 3] = 255
b = np.zeros((64, 64, 4), np.uint8)
b[32:64, 32:64, 3] = 255
c = F.centre_of([a, b])
check(abs(c[0] - 47.5) < 1e-6 and abs(c[1] - 47.5) < 1e-6, 'centre of a block in the bottom-right tile: %s' % (c,))
check(F.centre_of([np.zeros((8, 8, 4), np.uint8)]) is None, 'nothing visible')

# the committed table: csv offsets are what the Lua table says, and the two effects of the report moved
with open(F.CSV, newline='', encoding='utf-8') as fh:
    rows = list(csv.DictReader(fh))
lua = open(os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_pair50_fx_ids.lua'), encoding='utf-8').read()
got = {m.group(1): (int(m.group(2)), int(m.group(3))) for m in
       re.finditer(r'ChaosVfx\.(\w+) = \{id = \d+, dx = (\d+), dy = (\d+)', lua)}
check(all(got.get(r['key']) == (int(r['dx']), int(r['dy'])) for r in rows), 'csv and Lua offsets agree')
by = {r['effect_id']: (int(r['dx']), int(r['dy'])) for r in rows}
check(by['4579'] == (0, 0) and by['4574'] == (0, 0) and by['4584'] == (0, 0), 'Dreamrot and Soulrend Beam hits sent at 0, 0')
check(all(0 <= dx <= int(r['size'].split('x')[0]) - 1 and 0 <= dy <= int(r['size'].split('x')[1]) - 1
          for r in rows for dx, dy in [(int(r['dx']), int(r['dy']))]), 'every offset lies inside the effect')

print('fit_pair50_offsets_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
