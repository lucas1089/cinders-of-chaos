#!/usr/bin/env python3
"""Tests of check_hub_destinations.py: the real hub table is read, the landing rule is the engine's (rings outwards)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_hub_destinations as H  # noqa: E402

hub = H.read_hub(os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'guild_config.lua'))
assert len(hub) == 4 and all(d['level'] > 0 for d in hub), hub
d = hub[0]
assert H.landing(d, lambda x, y, z: False) is None
assert H.landing(d, lambda x, y, z: True) == (d['x'], d['y'])
assert H.landing(d, lambda x, y, z: (x, y) == (d['x'] + 3, d['y'] - 3)) == (d['x'] + 3, d['y'] - 3)
assert H.landing(d, lambda x, y, z: x == d['x'] + 4) is None, 'radius is 3'
assert H.landing(d, lambda x, y, z: z != d['z']) is None, 'same floor only'
only = hub[1]
assert H.dead_ends(hub, lambda x, y, z: (x, y, z) == (only['x'], only['y'], only['z'])) == [hub[0], hub[2], hub[3]]
print('check_hub_destinations_test: ok')
