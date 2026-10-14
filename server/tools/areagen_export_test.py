#!/usr/bin/env python3
"""Tests of server/tools/areagen_export.py without the live data (CI): the dump of the Lua generator parses, the
OTBM writer gives a file the reader takes back tile by tile (escaped bytes included), the spawn file names every
spawn point, and the same config gives the same bytes. Needs LuaJIT (LUAJIT=... to point elsewhere).

    python3 -I server/tools/areagen_export_test.py
"""
import os, sys, re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import areagen_export as ax

checks = fails = 0


def ok(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


# the escape of the node bytes
ok(ax._esc(b'\x01\xfd\xfe\xff') == b'\x01\xfd\xfd\xfd\xfe\xfd\xff', 'escape of FD FE FF')

areas = ax.run_dump('all')
ids = [a['id'] for a in areas]
ok(ids == ['emberdeep', 'ossuary', 'cinderfall', 'vault'], 'four areas in config order: %s' % ids)
for a in areas:
    ok(not a['problems'], a['id'] + ': no validator problem: %s' % a['problems'])
    ok(a['arrival'] and a['exit'], a['id'] + ': arrival and exit')
    ok(len(a['tiles']) > 500, a['id'] + ': tiles')
    walk = sum(1 for t in a['tiles'] if t['walk'])
    ok(walk == sum(f['walkable'] for f in a['floor_stats']), a['id'] + ': walkable tiles match the floor stats')
    data = ax.otbm_bytes(a)
    ok(data[:4] == b'\x00\x00\x00\x00', a['id'] + ': OTBM identifier')
    tiles, header = ax.read_otbm(data)
    ok(header == (2, ax.MAP_W, ax.MAP_H, ax.ITEMS_MAJOR, ax.ITEMS_MINOR), a['id'] + ': header %s' % (header,))
    ok(len(tiles) == len(a['tiles']), a['id'] + ': every tile written once')
    same = all(tiles.get((t['x'], t['y'], t['z'])) == [t['ground']] + t['items'] for t in a['tiles'])
    ok(same, a['id'] + ': every tile reads back with its ground and items in order')
    ok(ax.otbm_bytes(a) == data, a['id'] + ': the same model gives the same bytes')
    xml = ax.spawn_xml(a)
    blocks = re.findall(r'<spawn centerx="(\d+)" centery="(\d+)" centerz="(\d+)"', xml)
    ok(len(blocks) == len(a['spawns']) + (1 if a['boss'] else 0), a['id'] + ': one spawn block per point and the boss')
    mons = len(re.findall(r'<monster name=', xml))
    want = sum(s['count'] for s in a['spawns']) + (1 if a['boss'] else 0)
    ok(mons <= want and mons >= len(blocks), a['id'] + ': pack members on free tiles (%d of %d)' % (mons, want))

# a byte that needs escaping inside a tile (x & 0xFF = 0xFE) survives the round trip
probe = dict(id='probe', kind='cave', origin=(14590, 14590, 7), w=2, h=1, floors=1, name='probe', floor_stats=[],
             tiles=[dict(x=14590, y=14590, z=7, walk=True, ground=351, items=[]),
                    dict(x=14591, y=14590, z=7, walk=True, ground=0xFEFD, items=[0xFFFE, 1387])],
             spawns=[], boss=None, links=[], problems=[], exit=(14591, 14590, 7))
tiles, _ = ax.read_otbm(ax.otbm_bytes(probe))
ok(tiles.get((14590, 14590, 7)) == [351], 'probe tile 1 (x low byte 0xFE)')
ok(tiles.get((14591, 14590, 7)) == [0xFEFD, 0xFFFE, 1387], 'probe tile 2 with escaped ids')

print('areagen export: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
