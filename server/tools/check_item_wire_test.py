#!/usr/bin/env python3
"""python3 -I server/tools/check_item_wire_test.py : the per-item byte rules of check_item_wire.py (server addItem vs
client getItem) on synthetic nodes, including the 2026-10-16 case: an animated own gem look on a node without
FLAG_ANIMATION (the client reads a phase byte the server never sends). No pair or server needed."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_item_wire as W  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


S, A = W.FLAG_STACKABLE, W.FLAG_ANIMATION
# client things: cid -> (stackable, fluid, splash, market category, phases)
things = {
    100: (False, False, False, None, 1),    # a bag
    200: (True, False, False, None, 1),     # gold
    300: (True, False, False, None, 9),     # an animated gem look
    400: (False, True, False, None, 1),     # a vial
    500: (False, False, False, 25, 1),      # a quiver (market category)
    35562: (False, False, False, None, 1),  # the id of a quiver the client once hard-coded (base patch 0174 removed it)
}
ok_nodes = [(1, 100, 2, 0), (2, 200, 0, S), (3, 300, 0, S | A), (4, 400, W.GROUP_FLUID, 0)]
check(W.compare(ok_nodes, things) == [], 'matching nodes pass')

bad = W.compare([(32001, 300, 0, S)], things)
check(len(bad) == 1 and 'phase byte: server 0, client 1' in bad[0][2], 'animated look without FLAG_ANIMATION found')
bad = W.compare([(5, 100, 2, A)], things)
check(len(bad) == 1 and 'phase byte: server 1, client 0' in bad[0][2], 'FLAG_ANIMATION on a still look found')
bad = W.compare([(6, 200, 0, 0)], things)
check(len(bad) == 1 and 'count/fluid byte' in bad[0][2], 'stackable look on a node that is not')
bad = W.compare([(7, 500, 2, 0)], things)
check(len(bad) == 1, 'the client reads a count for quivers (market category 25); a container node sends none')
check(W.compare([(8, 35562, 0, 0)], things) == [], 'no client id is a quiver by itself any more (base patch 0174)')
check(not hasattr(W, 'QUIVER_IDS'), 'no hard-coded quiver id list')
bad = W.compare([(9, 999, 0, 0)], things)
check(bad == [(9, 999, 'no client thing')], 'a look the pair lacks')
check(W.compare([(None, 100, 0, 0), (10, None, 0, 0)], things) == [], 'nodes without ids are skipped')

# --table-check also checks our item manifests (V43, 2026-11-27): the temple torch 44544 / 48544 of temple_art.csv got 12 phases
# in pair 74 while its node kept no FLAG_ANIMATION and item_wire.csv had no row for it, so the table check passed and one torch
# on screen cut the map packet short. A missing table row is found from the manifest row.
import tempfile  # noqa: E402

things[44544] = (False, False, False, None, 12)   # the torch, animated in place
things[44560] = (False, False, False, None, 12)   # a flame whose manifest has the ANIM bit
HEAD = 'client_id,server_id,key,kind,mode,name,size,otb_group,otb_flags,top_order,speed,light_level,light_color,extra\n'
with tempfile.TemporaryDirectory() as d:
    with open(os.path.join(d, 'temple_art.csv'), 'w') as fh:
        fh.write(HEAD + '44544,48544,torch,stump,new,temple torch,2x2,0,8193,2,0,6,206,family=temple\n'
                 '44511,48511,floor,ground,new,temple floor,1x1,1,0,0,100,0,0,family=temple\n'
                 '44999,48999,later,decor,new,temple later,1x1,0,0,0,0,0,0,family=temple\n'
                 '100,4100,swap,decor,replace,temple swap,1x1,0,0,0,0,0,0,family=temple\n')
    with open(os.path.join(d, 'decor_flames.csv'), 'w') as fh:
        fh.write(HEAD + '44560,48560,brazier,stump,new,flame brazier,2x2,0,16785409,2,0,7,206,family=flame\n')
    with open(os.path.join(d, 'item_wire.csv'), 'w') as fh:
        fh.write('server,client,animation,group\n6651,6651,0,\n')   # not a manifest (no client_id column)
    paths = W.manifest_paths(d)
    check([os.path.basename(p) for p in paths] == ['decor_flames.csv', 'temple_art.csv'], 'manifests found by their header only')
    things[44511] = (False, False, False, None, 1)
    bad, n, missing = W.manifest_check(paths, things, {})
    check(len(bad) == 1 and '48544' in bad[0] and 'temple_art.csv' in bad[0], 'torch without FLAG_ANIMATION found: %r' % (bad,))
    check(n == 3 and missing == 1, 'three rows checked, the client id the pair lacks counted, the replace row skipped: %d %d' % (n, missing))
    bad, n, missing = W.manifest_check(paths, things, {48544: (44544, 1, None)})
    check(bad == [], 'the table row fixes the torch, as the installer applies it: %r' % (bad,))
    bad, _n, _m = W.manifest_check(paths, things, {48544: (49999, 1, None)})
    check(len(bad) == 1, 'a table row for another client id does not apply')

# O787: the idle loops' own gated table. A row says animation 1; on a pair of one phase it is pending (not stale) only
# while the gate is not reached, and stale once it is.
things[2917] = (False, False, False, None, 1)
check(W.table_check([(2047, 2917, 1, None)], things, pending=True) == [], 'idle row on the still pair: pending')
check(len(W.table_check([(2047, 2917, 1, None)], things)) == 1, 'idle row on the still pair after the gate: stale')
things[2917] = (False, False, False, None, 12)
check(W.table_check([(2047, 2917, 1, None)], things) == [], 'idle row on the loop pair: current')
check(len(W.table_check([(2047, 2917, 0, None)], things, pending=True)) == 1, 'an idle row without the flag is stale')
check(os.path.basename(W.IDLE_TABLE) == 'item_wire_idle.csv', 'the idle table is data/items/item_wire_idle.csv')

print('check_item_wire_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
sys.exit(1 if failed else 0)
