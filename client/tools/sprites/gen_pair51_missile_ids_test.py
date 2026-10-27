#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_pair51_missile_ids_test.py : gen_pair51_missile_ids.py on a synthetic table and on the
committed one (62 missiles on exactly the freed ids of pair51_removed.csv, unique names, valid ids and elements, generated
Lua up to date)."""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pair51_missile_ids as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


rows = [{'missile_id': '147', 'source': 'G', 'src_id': '2', 'name': 'wood_dart', 'element': 'physical', 'size': '1x1', 'phases': '1'},
        {'missile_id': '148', 'source': 'F', 'src_id': '25', 'name': 'big_claw', 'element': 'death', 'size': '2x2', 'phases': '4'}]
t = G.lua_text(rows)
check('ChaosPair51Missile.wood_dart = 147' in t, 'name -> id line')
check('ChaosVfxMissile.p51_wood_dart = {id = 147, dx = 0, dy = 0}' in t, 'small missile has no offset')
check('ChaosVfxMissile.p51_big_claw = {id = 148, dx = 1, dy = 1}' in t, '2x2 missile offset 1')
check('ids 147..148' in t, 'header names the id range')
check(G.lua_text(rows) == t, 'deterministic')

real = G.read_rows()
check(len(real) == 62, "62 missiles")
with open(os.path.join(HERE, 'pair51_removed.csv'), newline='', encoding='utf-8') as fh:
    free = sorted(int(r['id']) for r in csv.DictReader(fh) if r['kind'] == 'missile')
check(sorted(int(r['missile_id']) for r in real) == free, 'ids are the freed missile ids of pair51_removed.csv')
check(all(r['source'] in ('G', 'F') for r in real), 'source is G or F')
check({r['element'] for r in real} <= {'physical', 'fire', 'ice', 'energy', 'earth', 'death', 'holy', 'water'}, 'known elements')
check(all(r['size'] in ('1x1', '2x2', '3x3') for r in real), 'sizes')
check(os.path.exists(G.OUT) and open(G.OUT, encoding='utf-8').read() == G.lua_text(real), 'generated Lua is up to date')
sys.exit(1 if failed else 0)
