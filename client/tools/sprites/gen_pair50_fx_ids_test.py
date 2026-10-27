#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_pair50_fx_ids_test.py : gen_pair50_fx_ids.py on a synthetic table and on the
committed one (consecutive ids, unique keys, offsets from the size, generated file up to date)."""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pair50_fx_ids as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


rows = [{'effect_id': '10', 'key': 'p50_a_10', 'name': 'A', 'size': '1x1', 'phases': '4', 'ms': '400', 'dx': '0', 'dy': '0'},
        {'effect_id': '11', 'key': 'p50_b_11', 'name': 'B', 'size': '2x2', 'phases': '8', 'ms': '900', 'dx': '1', 'dy': '1'}]
t = G.lua_text(rows)
check('ChaosVfx.p50_a_10 = {id = 10, dx = 0, dy = 0, ms = 400}' in t, 'line of an effect')
check('ChaosVfx.p50_b_11 = {id = 11, dx = 1, dy = 1, ms = 900}' in t, 'line with an offset')
check('ids 10..11' in t, 'header names the id range')
check(G.lua_text(rows) == t, 'deterministic')

with open(G.SRC, newline='', encoding='utf-8') as fh:
    real = list(csv.DictReader(fh))
ids = [int(r['effect_id']) for r in real]
check(len(real) == 600 and ids == list(range(4102, 4702)), 'committed table: 600 effects, ids 4102..4701')
check(len({r['key'] for r in real}) == len(real), 'keys are unique')
ok = True
for r in real:
    w, h = (int(x) for x in r['size'].split('x'))
    ok = ok and (int(r['dx']), int(r['dy'])) == (w // 2, h // 2)
check(ok, 'offsets are half the size')
check(os.path.exists(G.OUT) and open(G.OUT, encoding='utf-8').read() == G.lua_text(real), 'generated Lua is up to date')

print('gen_pair50_fx_ids_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
