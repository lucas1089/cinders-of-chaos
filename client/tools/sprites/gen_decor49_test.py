#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_decor49_test.py : gen_decor49.py without sources. The list and the committed tables
agree (ids, keys, blocking, light, phases), the own art is deterministic and fits its tiles, the recolour keeps the
alpha and turns grey, blocking and light rules hold for every item."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_decor49 as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


errs = G.check_tables()
check(not errs, 'tables agree: %s' % errs[:3])
check(len(G.S) == 87, '87 items')
per = {b: sum(1 for s in G.S if s['biome'] == b) for b in ('celestial', 'cursed')}
check(per['celestial'] >= 30 and per['cursed'] >= 40, 'items per biome %s' % per)
check(len({s['name'] for s in G.S}) == len(G.S), 'names are unique')
for s in G.S:
    n = s['name']
    check(s['kind'] in ('static', 'animated', 'light'), n + ': kind')
    check((s['kind'] == 'animated') == (s['phases'] > 1), n + ': animated has phases')
    check(bool(s['light']) == (s['kind'] in ('light', 'animated')) or s['kind'] == 'animated', n + ': light kind has light')
    if s['light']:
        check(1 <= s['light'][0] <= 9 and 0 <= s['light'][1] <= 215, n + ': light level and colour')
    if 'tree' in n.lower() and 'fallen' not in n.lower() and 'stump' not in n.lower() or 'statue' in n or 'pillar' in n:
        check(s['blocks'], n + ': blocks')
    if any(w in n.lower() for w in ('cloud', 'doves', 'bats', 'crows', 'sparkle', 'rune circle', 'taint', 'pumpkin', 'jack')) and 'scarecrow' not in n.lower():
        check(not s['blocks'], n + ': does not block')

# own art: deterministic, fits whole tiles, never empty
for s in G.S:
    if not s['src'].startswith('own:'):
        continue
    for ph in range(s['phases']):
        a, _ = G.source_art(s, '/nonexistent', ph)
        b, _ = G.source_art(s, '/nonexistent', ph)
        check(np.array_equal(a, b), s['name'] + ': deterministic')
        check((a[..., 3] > 0).any(), s['name'] + ': not empty')
        check(set(np.unique(a[..., 3])) <= {0, 255}, s['name'] + ': no half-transparent pixels')
        cv, tw, th = G.to_canvas(a, own=True)
        check(cv.shape == (th * 32, tw * 32, 4), s['name'] + ': whole tiles')
    if s['phases'] > 1:
        f = [G.source_art(s, '/nonexistent', ph)[0] for ph in range(s['phases'])]
        check(any(not np.array_equal(f[0], x) for x in f[1:]), s['name'] + ': the phases differ')

# recolour keeps the shape and turns the colours into the ramp
rng = np.random.RandomState(1)
a = np.zeros((20, 20, 4), np.uint8)
a[4:16, 4:16, :3] = rng.randint(0, 255, (12, 12, 3)); a[4:16, 4:16, 3] = 255
for name in G.RAMPS:
    r = G.recolour(a, name)
    check(np.array_equal(r[..., 3], a[..., 3]), name + ': alpha kept')
    check((r[..., :3].astype(int).max(axis=2)[a[..., 3] > 0] >= 70).all(), name + ': nothing darker than the outline')
check(G.ot(5, 5, 5) == 215 and G.ot(0, 0, 0) == 0, 'palette index of the colour cube')

print('gen_decor49_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
