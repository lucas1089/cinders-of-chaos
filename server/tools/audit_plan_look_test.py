#!/usr/bin/env python3
"""Test of audit_plan_look.py on synthetic compiled plans (one case per code), then the real hollow_crypt plan (O574).
Run: python3 -I server/tools/audit_plan_look_test.py (needs luajit for the real plan)"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import audit_plan_look as L  # noqa: E402

FAILS = []


def ok(cond, msg):
    print(('ok   ' if cond else 'FAIL ') + msg)
    if not cond:
        FAILS.append(msg)


SLATE, FLAG, MARBLE = 10766, 3152, 407
TABLES = {'walls': {}, 'grounds': {'slate': {SLATE}, 'flagstone': {FLAG}, 'marble': {MARBLE}}}
GROUPS = {'coffin': {'block': True, 'ids': [9001], 'light': 0, 'size': 1},
          'brazier': {'block': True, 'ids': [9002], 'light': 2, 'size': 1},
          'tapestry_h': {'block': False, 'ids': [9010], 'light': 0, 'size': 2},
          'tapestry_v': {'block': False, 'ids': [9011], 'light': 0, 'size': 2}}


def room(ground, x1, y1, x2, y2, extra=None):
    t = {}
    for y in range(y1 - 1, y2 + 2):
        for x in range(x1 - 1, x2 + 2):
            edge = x in (x1 - 1, x2 + 1) or y in (y1 - 1, y2 + 1)
            t[(x, y, 7)] = dict(ground=0 if edge else ground, items=[(3362, {})] if edge else [], flags=0)
    for k, items in (extra or {}).items():
        t[k]['items'] += [(i, {}) for i in items]
    return t


def run(plan, tiles, rects, walk=()):
    res = dict(tiles=tiles, zrect=rects, walk=set(walk))
    return L.look_findings(plan, res, tables=TABLES, groups=GROUPS, wall_ids={3362})


def codes(found):
    return sorted(c for c, *_ in found)


PLAN = {'id': 'hollow_crypt', 'zones': [{'id': 'a', 'role': None}, {'id': 'b', 'role': None}, {'id': 'boss', 'role': 'boss'}]}
OTHER = {'id': 'some_cave', 'zones': PLAN['zones']}

# clean: two slate rooms, a marble boss room, a coffin with a skull next to it
t = room(SLATE, 10, 10, 18, 18, {(11, 11, 7): [9001], (12, 11, 7): [2229]})
t.update(room(SLATE, 30, 10, 38, 18))
t.update(room(MARBLE, 50, 10, 58, 18))
rects = {'a': (10, 10, 18, 18, 7), 'b': (30, 10, 38, 18, 7), 'boss': (50, 10, 58, 18, 7)}
ok(codes(run(PLAN, t, rects)) == [], 'clean plan: no finding (boss marble is allowed)')

# a light room among dark ones
t2 = dict(t)
t2.update(room(FLAG, 30, 10, 38, 18))
ok(codes(run(PLAN, t2, rects)) == ['PLAN_FLOOR_SPLIT'], 'flagstone room among slate rooms: PLAN_FLOOR_SPLIT')
ok(codes(run(OTHER, t2, rects)) == [], 'a plan that is not held is not looked at for floors')

# two families in one room
t3 = dict(t)
t3[(12, 12, 7)] = dict(ground=FLAG, items=[], flags=0)
ok(codes(run(PLAN, t3, rects)) == ['PLAN_FLOOR_SPLIT', 'ROOM_FLOOR_MIX'],'one flagstone tile in a slate room: ROOM_FLOOR_MIX')

# a lone block in the middle of a room, a lit one is fine, one with a bone beside it is fine
t4 = room(SLATE, 10, 10, 20, 20, {(15, 15, 7): [9001], (12, 12, 7): [9002]})
rects4 = {'a': (10, 10, 20, 20, 7)}
f4 = run(PLAN, t4, rects4)
ok(codes(f4) == ['LONE_PROP'] and f4[0][1:4] == (15, 15, 7), 'lone block mid room: LONE_PROP (a brazier is not)')
t4[(16, 15, 7)]['items'].append((2229, {}))
ok(codes(run(PLAN, t4, rects4)) == [], 'a bone within 2 tiles: no LONE_PROP')

# stock wooden pieces
t5 = room(SLATE, 10, 10, 20, 20, {(11, 11, 7): [7362, 2229]})
ok(codes(run(PLAN, t5, rects4)) == ['WOOD_PROP'], 'stock sarcophagus 7362 in a held plan: WOOD_PROP')
ok(codes(run(OTHER, t5, rects4)) == [], 'not in a plan that is not held')

# hangings: on a straight wall run, and cut at a corner
t6 = room(SLATE, 10, 10, 20, 20)
for x in range(9, 22):
    t6[(x, 9, 7)]['items'] = [(3362, {})]
t6[(14, 9, 7)]['items'].append((9010, {}))
ok(codes(run(PLAN, t6, rects4)) == [], 'tapestry on a straight wall: no finding')
t6[(9, 9, 7)]['items'].append((9010, {}))
ok(codes(run(PLAN, t6, rects4)) == ['HANGING_CUT'], 'tapestry at the corner (no wall to its west): HANGING_CUT')

# the real plan
try:
    got = L.audit_plan(os.path.join(L.PLANS, 'hollow_crypt.json'))
    ok(got is not None and got[1] == [], 'hollow_crypt.json compiles with no look finding: %s' % (got[1][:3] if got else None))
    plan = json.load(open(os.path.join(L.PLANS, 'hollow_crypt.json')))
    ok(plan['biome'] == 'catacomb_earth', 'hollow_crypt uses the biome catacomb_earth (one dirt floor)')
except FileNotFoundError:
    ok(False, 'luajit missing')

print('FAILED: %d' % len(FAILS) if FAILS else 'all passed')
sys.exit(1 if FAILS else 0)
