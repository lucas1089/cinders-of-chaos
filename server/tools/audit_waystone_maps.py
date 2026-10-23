"""Waystone map audit: can a group walk from the arrival to the boss lever and the boss, and do the maps hold monsters?

    python3 -I server/tools/audit_waystone_maps.py BASE_SERVER_DIR [--check] [--no-clear] [N ...]

BASE_SERVER_DIR is an unpacked base server (data/world/*.otbm, *-spawn.xml, data/items/items.otb + items.xml,
data/scripts/customs/waystone_system/tier_maps.lua + waystone_bosses/). The base map is not in the repo, so CI runs only
the unit test (audit_waystone_maps_test.py, a synthetic map) and the config checks of tests/waystone_layouts_test.lua;
run this on an installed server after a map or a clearPath change (server/README.md "Waystone layouts").

Per map (the 12 of tier_maps.lua, each with its boss file) it checks, on the map as the server runs it (the
`clearPath` items of data/scripts/chaos/waystone_tiers_config.lua taken off, the Frostreaver entrance moved by
tools/patch_waystone_bosses.py):
  arrival     the arrival tile walks and its region is large (>= MIN_REGION tiles)
  levers      every participant tile of the boss lever is reachable on foot from the arrival (the report of 2026-10-22:
              "one layout has no boss lever"; both tier IV maps were closed off: a fir tree, rope railings)
  room        the boss entrance tile walks and the boss tile is reachable from it, inside the room box
  closed      the room is not open from the map (the group enters by the lever's teleport only)
  reach       at least 85% of the spawn points are within a step of the region walked from the arrival
  spawns      the map holds at least MIN_SPAWNS of the tier's monsters in the spawn file, at least four of its five names
--no-clear audits the raw base map (without the clearPath items taken off). Exit code 1 on any failure with --check. Diagnostic text goes to stdout.
"""
import collections
import os
import re
import sys

MIN_REGION = 1000
MIN_SPAWNS = 40
MIN_REACH = 0.85  # share of the spawn points that must be within a step of the arrival's region
POS = r'Position\((\d+),\s*(\d+),\s*(\d+)\)'

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))


# ---------------------------------------------------------------------------------------------------- pure logic
def flood(walk, start, box, diagonal=True):
    """tiles reachable from start on foot inside box = (x1, y1, x2, y2, z) (inclusive)."""
    x1, y1, x2, y2, z = box
    if not walk(start):
        return set()
    seen = {start}
    queue = collections.deque([start])
    steps = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy) and (diagonal or not (dx and dy))]
    while queue:
        x, y, zz = queue.popleft()
        for dx, dy in steps:
            n = (x + dx, y + dy, zz)
            if n in seen or not (x1 <= n[0] <= x2 and y1 <= n[1] <= y2):
                continue
            if walk(n):
                seen.add(n)
                queue.append(n)
    return seen


def audit_map(walk, spec):
    """spec: name, dest, box (x1, y1, x2, y2, z), levers [pos], entrance, boss, room (x1, y1, x2, y2, z), spawns {name: n},
    monsters [names]. Returns the list of problems (empty: fine)."""
    bad = []
    name = spec['name']
    region = flood(walk, spec['dest'], spec['box'])
    if not walk(spec['dest']):
        bad.append('%s: the arrival %s does not walk' % (name, spec['dest']))
    elif len(region) < MIN_REGION:
        bad.append('%s: the arrival region holds only %d tiles' % (name, len(region)))
    for p in spec['levers']:
        if p not in region:
            bad.append('%s: lever tile %s is not reachable from the arrival' % (name, p))
    if not walk(spec['entrance']):
        bad.append('%s: the boss entrance %s does not walk' % (name, spec['entrance']))
    room = flood(walk, spec['entrance'], spec['room'])
    if spec['boss'] not in room:
        bad.append('%s: the boss tile %s is not reachable from the entrance' % (name, spec['boss']))
    if spec['entrance'] in region:
        bad.append('%s: the boss room is open from the map (the entrance is reachable on foot)' % name)
    # spawn points the group cannot walk to are monsters nobody can kill (and the pack count the tier counts on)
    points = spec.get('points') or []
    if points:
        cut = [p for p in points if not any((p[0] + dx, p[1] + dy, p[2]) in region for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
        if len(cut) > len(points) * (1 - MIN_REACH):
            bad.append('%s: %d of %d spawn points are cut off from the arrival (first %s)' % (name, len(cut), len(points), cut[0]))
    total = sum(spec['spawns'].values())
    if total < MIN_SPAWNS:
        bad.append('%s: only %d spawn points of the tier in the map' % (name, total))
    # one of a tier's five types may live only in the tier's other map (map 1 has no Nexlurith), no more
    present = sum(1 for m in spec['monsters'] if spec['spawns'].get(m, 0) > 0)
    if present < len(spec['monsters']) - 1:
        bad.append('%s: only %d of the tier\'s %d monster types have a spawn' % (name, present, len(spec['monsters'])))
    return bad


# ---------------------------------------------------------------------------------------------------- readers
def parse_tier_maps(text):
    """[(tier, name, from, to, dest)] of tier_maps.lua (tier 1-6 by the base item id 29845+)."""
    out = []
    for tier, body in re.findall(r'\[(298\d\d)\] = \{(.*?)\n  \},', text, re.S):
        for m in re.finditer(r'---- ([^\n]*)\n(.*?)destination = Position\((\d+), (\d+), (\d+)\)', body, re.S):
            ps = [tuple(map(int, x)) for x in re.findall(POS, m.group(2))]
            out.append((int(tier) - 29844, m.group(1).strip(), ps[0], ps[1], tuple(map(int, m.group(3, 4, 5)))))
    return out


def parse_boss(text):
    def one(key):
        return tuple(map(int, re.search(key + r'\s*=\s*' + POS, text).groups()))
    lever = text[text.find('participantsPos'):text.find('attempts')]
    return {'from': one('fromPos'), 'to': one('toPos'), 'entrance': one('entrancePos'), 'boss': one('bossPosition'),
            'levers': [tuple(map(int, x)) for x in re.findall(POS, lever)]}


def parse_clear_path(text):
    """[(x, y, z, item)] of waystone_tiers_config.lua clearPath."""
    block = re.search(r'clearPath\s*=\s*\{(.*?)\n\t\}', text, re.S)
    return [tuple(map(int, m)) for m in re.findall(r'x = (\d+), y = (\d+), z = (\d+), item = (\d+)', block.group(1))] if block else []


def parse_config_monsters(text):
    block = re.search(r'\n\tmonsters = \{(.*?)\n\t\},', text, re.S).group(1)
    return [re.findall(r'"([^"]+)"', row) for row in re.findall(r'\{([^{}]*)\}', block)]


def count_spawns(xml_text, maps, points=None):
    cnt = {i: collections.Counter() for i in range(len(maps))}
    for sp in re.finditer(r'<spawn centerx="(\d+)" centery="(\d+)" centerz="(\d+)"[^>]*>(.*?)</spawn>', xml_text, re.S):
        cx, cy = int(sp.group(1)), int(sp.group(2))
        for mo in re.finditer(r'<monster name="([^"]+)" x="(-?\d+)" y="(-?\d+)" z="(\d+)"', sp.group(4)):
            px, py, pz = cx + int(mo.group(2)), cy + int(mo.group(3)), int(mo.group(4))
            for i, m in enumerate(maps):
                a, b = m[2], m[3]
                if a[0] <= px <= b[0] and a[1] <= py <= b[1] and pz == a[2]:
                    cnt[i][mo.group(1)] += 1
                    if points is not None:
                        points.setdefault(i, []).append((px, py, pz))
    return cnt


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if not args:
        print(__doc__)
        return 2
    base = args[0]
    check = '--check' in argv
    sys.path.insert(0, os.path.join(REPO, 'tools', 'map'))
    import otbm
    from itemdb import ItemDB
    data = os.path.join(base, 'data')
    world = [f for f in os.listdir(os.path.join(data, 'world')) if f.endswith('.otbm')][0]
    m = otbm.load_map(os.path.join(data, 'world', world))
    db = ItemDB(os.path.join(data, 'items', 'items.otb'), os.path.join(data, 'items', 'items.xml'))
    db.classify()
    ws = os.path.join(data, 'scripts', 'customs', 'waystone_system')
    maps = parse_tier_maps(open(os.path.join(ws, 'tier_maps.lua'), encoding='utf-8', errors='replace').read())
    cfg_text = open(os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'waystone_tiers_config.lua'), encoding='utf-8').read()
    removed = collections.defaultdict(list)
    for x, y, z, item in ([] if '--no-clear' in argv else parse_clear_path(cfg_text)):
        removed[(x, y, z)].append(item)
    names = parse_config_monsters(cfg_text)
    spawn_name = [f for f in os.listdir(os.path.join(data, 'world')) if f.endswith('-spawn.xml')][0]
    points = {}
    spawns = count_spawns(open(os.path.join(data, 'world', spawn_name), encoding='latin-1').read(), maps, points)
    bosses = {}
    for f in sorted(os.listdir(os.path.join(ws, 'waystone_bosses'))):
        if f.startswith('boss_'):
            b = parse_boss(open(os.path.join(ws, 'waystone_bosses', f), encoding='utf-8', errors='replace').read())
            bosses[f] = b
    # tools/patch_waystone_bosses.py: the Frostreaver entrance moves off a tar tile
    for b in bosses.values():
        if b['entrance'] == (32965, 33236, 7):
            b['entrance'] = (32964, 33236, 7)

    def make_walk():
        def stack(p):
            i = m.find(*p)
            if i < 0:
                return None
            st = [int(a) for a in m.stack(i)]
            for item in removed.get(p, []):
                if item in st:
                    st.remove(item)
            return st

        def walk(p):
            st = stack(p)
            if not st or db.group[st[0]] != 1:
                return False
            # a player walks onto a field (block path); only a solid item (flag 1) stops him
            return not any(int(db.flags[s]) & 1 for s in st)
        return walk
    walk = make_walk()
    only = [int(a) for a in argv if a.isdigit()]
    failures = 0
    for i, (tier, name, a, b, dest) in enumerate(maps):
        if only and (i + 1) not in only:
            continue
        match = [(fn, bs) for fn, bs in bosses.items() if a[0] <= bs['from'][0] <= b[0] and a[1] <= bs['from'][1] <= b[1]
                 and bs['from'][2] == a[2]]
        if not match:
            print('map %d (tier %d %s): no boss file in its rectangle' % (i + 1, tier, name))
            failures += 1
            continue
        fn, bs = match[0]
        spec = {'name': 'map %d (tier %d %s, %s)' % (i + 1, tier, name, fn), 'dest': dest, 'box': (a[0], a[1], b[0], b[1], a[2]),
                'levers': bs['levers'], 'entrance': bs['entrance'], 'boss': bs['boss'],
                'room': (bs['from'][0] - 3, bs['from'][1] - 3, bs['to'][0] + 3, bs['to'][1] + 3, bs['from'][2]),
                'spawns': dict(spawns[i]), 'points': points.get(i, []), 'monsters': names[tier - 1]}
        bad = audit_map(walk, spec)
        print('%s: %s (%d spawn points)' % (spec['name'], 'ok' if not bad else 'FAILS', sum(spec['spawns'].values())))
        for line in bad:
            print('  ' + line)
        failures += len(bad)
    print('waystone maps: %s' % ('every map passes' if failures == 0 else '%d problem(s)' % failures))
    return 1 if (check and failures) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
