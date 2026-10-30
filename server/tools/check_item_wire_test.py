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

print('check_item_wire_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
sys.exit(1 if failed else 0)
