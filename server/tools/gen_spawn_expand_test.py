#!/usr/bin/env python3
"""python3 -I server/tools/gen_spawn_expand_test.py : the pure parts of gen_spawn_expand.py on synthetic data, and the committed
tools/spawn_expand.json / tools/waystone_trim.json.

Farthest-point blocks keep their spacing and are deterministic; a fill area copies the nearest monster and its blocks stay on the
region; a dead-end lobe behind a narrow neck is found, one with the boss lever in it is not, the largest lobes are taken without
nesting; the thinning takes out the entries whose ground others cover and never a protected one; the spawn reader ignores the
tool's own blocks and counts the entries it took out. The committed files are well formed: fill areas XW.., likes that exist,
blocks inside the area's box, no entry taken out twice. Needs numpy (system python3-numpy)."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import gen_spawn_expand as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# ---- far_blocks / fill_area
region = {(x, y) for x in range(0, 40) for y in range(0, 20)}
taken = [(0, 0), (39, 19)]
a = G.far_blocks(sorted(region), set(taken), 6)
b = G.far_blocks(sorted(region), set(taken), 6)
check(a == b and len(a) == 6, 'far_blocks: six blocks, the same twice: %s' % a)
for i, p in enumerate(a):
    for q in a[:i] + taken:
        check(max(abs(p[0] - q[0]), abs(p[1] - q[1])) >= G.SPACING, 'far_blocks: %s is %d+ from %s' % (p, G.SPACING, q))
check(G.far_blocks(sorted({(1, 1), (2, 1)}), {(1, 1)}, 3) == [], 'far_blocks: nothing farther than the spacing, no block')
area, got = G.fill_area('XW99', 7, (0, 0, 40, 20, 7, 7), region, taken, [(0, 0), (39, 19)], 10)
check(got == 10, 'fill_area: ten monsters placed: %d' % got)
check(sum(1 + (len(r) - 3) // 2 for r in area['add']) == 10, 'fill_area: the blocks hold ten monsters')
check(all(0 <= r[2] < len(area['likes']) for r in area['add']), 'fill_area: every block names a like')
check(all((r[0], r[1]) in region for r in area['add']), 'fill_area: the centres are on the region')
check(area['likes'][area['add'][0][2]] == [0, 0] or area['likes'][area['add'][0][2]] == [39, 19], 'fill_area: the like is the nearest monster')

# ---- lobes: a corridor tree with a side pocket behind a 1-wide neck and the boss lever at the end of the main branch
graph = set()
for x in range(0, 30):
    graph.add((x, 5, 7))                    # the main corridor
graph |= {(12, 6, 7), (12, 7, 7)}           # a one-tile neck south of it ...
for y in range(8, 14):
    for x in range(10, 16):
        graph.add((x, y, 7))                # ... into a 6 x 6 pocket
for x in range(20, 30):
    for y in range(0, 4):
        graph.add((x, y, 7))                # a pocket north at the end (the lever)
graph.add((25, 4, 7))
found = G.lobes(graph, (0, 5, 7), {(29, 0, 7)}, {}, neck=8)
sizes = sorted(o['size'] for o in found)
pocket = {(x, y, 7) for y in range(8, 14) for x in range(10, 16)}
check(any(pocket <= o['tiles'] and o['size'] <= 38 for o in found), 'lobes: the pocket of 36 tiles behind the neck is a lobe: %s' % sizes)
check(all((29, 0, 7) not in o['tiles'] for o in found), 'lobes: none holds the lever')
check(all(not any(abs(t[0] - 29) <= 1 and abs(t[1] - 0) <= 1 for t in o['tiles']) for o in found), 'lobes: none is next to the lever')
took = G.choose_lobes(found, 40)
check(took and took[0]['size'] >= 36 and pocket <= took[0]['tiles'], 'choose_lobes: the largest first')
cov = set()
for o in took:
    check(not (cov & o['tiles']), 'choose_lobes: no lobe inside another')
    cov |= o['tiles']
few = G.lobes(graph, (0, 5, 7), set(), {(12, 8): 50}, neck=8, max_spawns=40)
check(not any(pocket <= o['tiles'] for o in few), 'lobes: a lobe with too many monsters is left')
# blocking the neck cuts the lobe off
blocked = set(took[0]['neck'])
reach = G.bfs({t for t in graph if t not in blocked}, (0, 5, 7))
check(not (took[0]['tiles'] & set(reach)), 'the blocked neck cuts the lobe off')

# ---- thin
ents = [(x, 0, 7) for x in range(0, 10)] + [(x, 0, 7) for x in range(0, 10, 2)]   # dense row: the same tile twice is not possible, use offsets
ents = [(x, 0, 7) for x in range(0, 20)]
tiles = {(x, y, 7) for x in range(-3, 24) for y in range(-3, 4)}
r = 3
tiles_of = lambda e: [(e[0] + dx, e[1] + dy, e[2]) for dx in range(-r, r + 1) for dy in range(-r, r + 1) if (e[0] + dx, e[1] + dy, e[2]) in tiles]
keep = {(0, 0, 7)}
gone = G.thin(ents, tiles_of, 8.0, keep)
left = [e for e in ents if e not in gone]
cover = {t for e in left for t in tiles_of(e)}
check(len(left) * 100.0 / len(cover) <= 8.0 and gone, 'thin: the density is under the cap: %.1f' % (len(left) * 100.0 / len(cover)))
check((0, 0, 7) in left, 'thin: a protected entry stays')
check(G.thin(ents, tiles_of, 8.0, keep) == gone, 'thin: deterministic')

# ---- the spawn reader
xml = '''<spawns>
	<spawn centerx="100" centery="100" centerz="7" radius="2">
		<monster name="A" x="0" y="0" z="7" spawntime="60" />
		<!-- chaosremoved: <monster name="B" x="1" y="1" z="7" spawntime="45" /> -->
		<monster name="C" x="2" y="0" z="7" spawntime="60" lategame="D" />
	</spawn>
	<spawn centerx="110" centery="100" centerz="7" radius="2" chaosadd="XW03">
		<monster name="A" x="0" y="0" z="7" spawntime="60" />
	</spawn>
	<spawn centerx="120" centery="100" centerz="7" radius="2" chaosadd="H4-01">
		<monster name="A" x="0" y="0" z="7" spawntime="60" />
	</spawn>
</spawns>
'''
got = G.read_entries(xml, [[101, 101, 7]])
names = sorted((e['name'], e['x'], e['y']) for e in got)
check(names == [('A', 100, 100), ('A', 120, 100), ('B', 101, 101), ('C', 102, 100)], 'read_entries: own blocks skipped, the entry taken out counted: %s' % names)
check([e['late'] for e in got if e['name'] == 'C'] == [True], 'read_entries: the late game mark')
check([e['name'] for e in G.read_entries(xml, [])] == ['A', 'C', 'A'], 'read_entries: without the list the removed entry is gone')

# ---- the committed files
doc = json.load(open(G.OUT, encoding='utf-8'))
check(G.render(doc) == open(G.OUT, encoding='utf-8').read(), 'spawn_expand.json is in the tool\'s own format')
ids = [a['id'] for a in doc['areas']]
check(len(ids) == len(set(ids)) and all(i.startswith('XW') for i in ids), 'fill areas XW.., none twice: %s' % ids)
for a in doc['areas']:
    x0, y0, x1, y1, z0, z1 = a['box']
    check(all(0 <= r[2] < len(a['likes']) for r in a['add']), '%s: every block names a like' % a['id'])
    check(all(x0 <= r[0] <= x1 and y0 <= r[1] <= y1 for r in a['add']), '%s: every block is inside the box' % a['id'])
    check(all((len(r) - 3) % 2 == 0 and len(r) <= 3 + 2 * (G.BLOCK - 1) for r in a['add']), '%s: blocks of up to %d' % (a['id'], G.BLOCK))
    check(a['z'] == z0 == z1, '%s: one floor' % a['id'])
check(len({tuple(r) for r in doc['remove']}) == len(doc['remove']) and doc['remove'] == sorted(doc['remove']), 'remove: sorted, no entry twice')
tdoc = json.load(open(G.TRIM_OUT, encoding='utf-8'))
check(G.render_trim(tdoc) == open(G.TRIM_OUT, encoding='utf-8').read(), 'waystone_trim.json is in the tool\'s own format')

if failed:
    print('%d failure(s)' % failed)
    sys.exit(1)
print('gen_spawn_expand_test: ok')
