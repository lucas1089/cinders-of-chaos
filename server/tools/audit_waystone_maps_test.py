"""Unit test of audit_waystone_maps.py on synthetic maps (run: python3 -I server/tools/audit_waystone_maps_test.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit_waystone_maps as a

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def grid(rows, origin=(0, 0), z=7):
    """'.' walks, '#' blocks; returns walk(p) for the rows placed at origin."""
    cells = set()
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            if ch != '#' and ch != ' ':
                cells.add((origin[0] + dx, origin[1] + dy, z))
    return lambda p: p in cells


# a 60 x 40 open map; the boss room is a closed box in the corner, reached only by the lever teleport
rows = []
for y in range(40):
    rows.append(''.join('.' for _ in range(60)))
rows = [list(r) for r in rows]
for y in range(30, 40):  # the room
    for x in range(40, 60):
        rows[y][x] = '#' if (y == 30 or x == 40) else '.'
walk = grid([''.join(r) for r in rows])
spec = {'name': 'test', 'dest': (5, 5, 7), 'box': (0, 0, 59, 29, 7), 'levers': [(50, 10, 7)], 'entrance': (45, 35, 7),
        'boss': (55, 38, 7), 'room': (40, 30, 59, 39, 7), 'spawns': {'A': 20, 'B': 20, 'C': 20, 'D': 20, 'E': 0},
        'points': [(10, 10, 7), (20, 20, 7)], 'monsters': ['A', 'B', 'C', 'D', 'E']}
import audit_waystone_maps as m
m.MIN_REGION = 100
check(a.audit_map(walk, spec) == [], 'a healthy map passes: %s' % a.audit_map(walk, spec))

# a lever behind a wall: closed pocket
for y in range(5, 12):
    rows[y][48] = '#'
    rows[y][52] = '#'
for x in range(48, 53):
    rows[5][x] = '#'
    rows[11][x] = '#'
walk2 = grid([''.join(r) for r in rows])
bad = a.audit_map(walk2, spec)
check(any('lever tile' in b for b in bad), 'a lever in a closed pocket is reported')
# the same pocket with one railing taken off (what clearPath does) passes again
rows[8][48] = '.'
check(a.audit_map(grid([''.join(r) for r in rows]), spec) == [], 'opening the pocket fixes it')

# the room open from the map
rows[30][45] = '.'
bad = a.audit_map(grid([''.join(r) for r in rows]), dict(spec, box=(0, 0, 59, 39, 7)))
check(any('open from the map' in b for b in bad), 'an open boss room is reported')

# a boss tile that does not walk
rows[30][45] = '#'
spec2 = dict(spec, boss=(41, 31, 7))
rows[31][41] = '#'
check(any('boss tile' in b for b in a.audit_map(grid([''.join(r) for r in rows]), spec2)), 'an unreachable boss is reported')

# spawns: too few, and cut-off points
bad = a.audit_map(walk, dict(spec, spawns={'A': 3}))
check(any('spawn points of the tier' in b for b in bad) and any('monster types' in b for b in bad), 'missing spawns are reported')
check(any('cut off' in b for b in a.audit_map(walk, dict(spec, points=[(45, 35, 7), (46, 35, 7)]))), 'cut-off spawn points are reported')

# the parsers
tm = '''  [29845] = {
    { ---- Underground: Map 3 Water
      area = {
        fromPos = Position(33314, 33066, 8),
        toPos   = Position(33606, 33178, 8),
        exitPos = Position(32369, 32241, 7)
      },
      destination = Position(33597, 33141, 8)
    },
  },
'''
maps = a.parse_tier_maps(tm)
check(maps == [(1, 'Underground: Map 3 Water', (33314, 33066, 8), (33606, 33178, 8), (33597, 33141, 8))], 'tier_maps parsed: %s' % maps)
boss = 'fromPos = Position(1, 2, 7), toPos = Position(3, 4, 7), entrancePos = Position(2, 3, 7), bossPosition = Position(3, 3, 7),\nparticipantsPos = {\nPosition(9, 9, 7),\nPosition(9, 10, 7),\n},\nattempts = {}'
b = a.parse_boss(boss)
check(b['levers'] == [(9, 9, 7), (9, 10, 7)] and b['boss'] == (3, 3, 7), 'boss file parsed')
cp = a.parse_clear_path('\tclearPath = {\n\t\t{x = 1, y = 2, z = 7, item = 2768},\n\t\t{x = 3, y = 4, z = 8, item = 3784}\n\t}\n')
check(cp == [(1, 2, 7, 2768), (3, 4, 8, 3784)], 'clearPath parsed: %s' % cp)
cfg = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'scripts', 'chaos', 'waystone_tiers_config.lua')).read()
check(len(a.parse_clear_path(cfg)) >= 2, 'the real config clearPath parses')
names = a.parse_config_monsters(cfg)
check(len(names) == 6 and all(len(n) == 5 for n in names), 'the real config monsters parse: %s' % names)
xml = '<spawn centerx="10" centery="10" centerz="7" radius="2"><monster name="A" x="1" y="1" z="7" spawntime="60" /></spawn>'
pts = {}
cnt = a.count_spawns(xml, [(1, 'x', (0, 0, 7), (20, 20, 7), (1, 1, 7))], pts)
check(cnt[0]['A'] == 1 and pts[0] == [(11, 11, 7)], 'spawn counting')

print('audit_waystone_maps_test: %s' % ('ok' if fails == 0 else '%d failure(s)' % fails))
sys.exit(1 if fails else 0)
