#!/usr/bin/env python3
"""Tests of check_hunt_returns.py: the CSV and the shipped config (every hunt without a base teleport has a way back),
the tile rule (the same answers as tests/hunt_teleports_test.lua for ChaosHuntTeleportsCore.pickReturnTile), the map
ways back (into the hall, in front of the hunt's own teleport when the places file says where it stands) and the
planned hunts' camp portals."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_hunt_returns as R  # noqa: E402
import install_content_areas as I  # noqa: E402

# the CSV and the shipped config
hunts = R.read_hunts()
added = [h for h in hunts if not h['placed']]
assert len(hunts) >= 45 and len(added) >= 10, (len(hunts), len(added))
cfg = I.load_config()
listed = {r['id']: r for r in cfg['returns']['list']}
for h in added:
    assert h['id'] in listed, '%s: a hunt of the hall without a way back' % h['id']
    at = listed[h['id']]['at']
    d = max(abs(at['x'] - h['arrival'][0]), abs(at['y'] - h['arrival'][1]))
    assert at['z'] == h['arrival'][2] and 1 <= d <= cfg['returns']['radius'], h['id']
assert set(listed) <= {h['id'] for h in hunts}, 'a way back for a hunt the CSV does not have'


def grid(rows, z=7):
    cells = {}
    for y, row in enumerate(rows, 1):
        for x, c in enumerate(row, 1):
            if c != '#':
                cells[(x, y, z)] = dict(walk=c != 'S', spot=c in '.A')
    return lambda p: cells.get(tuple(p))


# the tile rule, the same cases as the Lua core's tests
room = grid(['#####', '#...#', '#.A.#', '#...#', '#####'])
assert R.pick_return_tile((3, 3, 7), 4, room) == (2, 2, 7)
assert R.pick_return_tile((3, 3, 7), 4, room, (4, 4, 7)) == (4, 4, 7)
assert R.pick_return_tile((3, 3, 7), 4, room, (3, 3, 7)) == (2, 2, 7), 'never the arrival'
corridor = grid(['#######', '#A....#', '####.##', '#######'])
assert R.pick_return_tile((2, 2, 7), 4, corridor) == (5, 3, 7), 'the nook, not the corridor'
assert R.cuts_way((3, 2, 7), corridor) and R.cuts_way((5, 2, 7), corridor)
assert not R.cuts_way((6, 2, 7), corridor) and not R.cuts_way((5, 3, 7), corridor)
busy = grid(['#########', '#S,P#...#', '#,A,#...#', '#.,.....#', '#########'])
assert R.pick_return_tile((3, 3, 7), 4, busy) == (2, 4, 7)
assert R.pick_return_tile((3, 3, 7), 4, busy, (2, 2, 7)) == (2, 4, 7), 'stairs: picked'
assert R.pick_return_tile((2, 2, 7), 1, grid(['###', '#A#', '###'])) is None
behind = grid(['#######', '#,A,#.#', '#,,,#.#', '#######'])
assert R.pick_return_tile((3, 2, 7), 4, behind) is None, 'behind a wall'

# the check: a hunt with a way back on the map, one listed in returns, one with nothing, a planned hunt
scfg = dict(hall=dict(floors=[7, 6, 5], x=[100, 200]), room=dict(rows=[50, 62], teleportRows=[54, 58], back=dict(x=150)),
            returns=dict(radius=4, list=[dict(id='low_a', at=dict(x=3, y=3, z=9))]))
open_cave = grid(['#######', '#.....#', '#.....#', '#.....#', '#######'], z=9)
shunts = [dict(id='base_a', arrival=(500, 500, 8), placed=True), dict(id='low_a', arrival=(4, 4, 9), placed=False),
          dict(id='low_b', arrival=(900, 900, 9), placed=False), dict(id='base_far', arrival=(600, 600, 8), placed=True)]
tele = {(501, 500, 8): (120, 55, 7),  # base_a's way back, into the hall
        (610, 600, 8): (120, 55, 7)}  # 10 tiles from base_far's arrival: too far
lines, missing = R.check(scfg, shunts, tele, open_cave)
assert missing == ['low_b', 'base_far'], (missing, lines)
assert any('low_a: way back at startup (3, 3, 9)' in line for line in lines), lines
assert R.map_way_back(scfg, {(501, 500, 8): (5, 5, 7)}, (500, 500, 8), 4) is None, 'a teleport leading elsewhere'
# with the places file: the way back must lead in front of the hunt's teleport now; a planned hunt needs its exit
places = ('\t\t{id = "plan_x", name = "X", level = {1, 2}, teleport = {x = 130, y = 58, z = 6}, sign = nil, '
          'arrival = {x = 1, y = 1, z = 8}, exit = {x = 2, y = 1, z = 8}, monster = nil},\n'
          '\t\t{id = "plan_y", name = "Y", level = {1, 2}, teleport = {x = 134, y = 58, z = 6}, sign = nil, '
          'arrival = {x = 1, y = 1, z = 8}, exit = nil, monster = nil},\n'
          '\t\t{id = "base_a", name = "A", level = {1, 2}, teleport = {x = 120, y = 54, z = 7}, sign = nil, dest = nil},\n'
          '\t\t{id = "base_far", name = "F", level = {1, 2}, teleport = {x = 124, y = 54, z = 6}, sign = nil, dest = nil},\n')
lines, missing = R.check(scfg, shunts[:2], tele, open_cave, places)
assert missing == ['plan_y'], (missing, lines)
moved = places.replace('teleport = {x = 120, y = 54, z = 7}', 'teleport = {x = 124, y = 58, z = 7}')
lines, missing = R.check(scfg, shunts[:2], tele, open_cave, moved)
assert missing == ['base_a', 'plan_y'], (missing, lines)
assert any('leads in front of another teleport' in line for line in lines), lines
print('check_hunt_returns_test: ok')
