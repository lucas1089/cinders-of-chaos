#!/usr/bin/env python3
"""Tests of gen_poi.py (the points of interest of the map markers). Run: python3 -I server/tools/gen_poi_test.py

A small installed server is built in a temporary folder: an OTBM map with two towns, depot lockers (a depot of four and
a lone locker), crafting tables by action id (escaped bytes included), an NPC spawn file with a shop, a travel NPC in
town, a banker far away, an unrenamed name; items.xml; the bounty pool, bestiary spawn data and boss spawns. Checked:
the marks and their reveal flags, the clustering, the level band, the old-name filter, determinism, --check, --map."""
import os
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_poi as G  # noqa: E402
from base_rename_lib import digest  # noqa: E402

fails = checks = 0


def ok(cond, what):
    global fails, checks
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


def eq(a, b, what):
    ok(a == b, '%s: %r != %r' % (what, a, b))


def node(t, body=b'', children=b''):
    return bytes([0xFE, t]) + G.esc(body) + children + bytes([0xFF])


def item(iid, aid=None):
    body = struct.pack('<H', iid)
    if aid is not None:
        body += bytes([4]) + struct.pack('<H', aid)
    return node(6, body)


def tile(x, y, items):
    return node(5, bytes([x, y]), b''.join(items))


def area(bx, by, z, tiles):
    return node(4, struct.pack('<HHB', bx, by, z), b''.join(tiles))


def town(tid, name, x, y, z):
    nm = name.encode('latin-1')
    return node(13, struct.pack('<IH', tid, len(nm)) + nm + struct.pack('<HHB', x, y, z))


def build_map():
    tiles_a = [tile(0, 0, [item(100)])]
    # a depot of four lockers on floor 7 near town 1, a lone locker far away
    tiles_a += [tile(10 + i, 10, [item(2589 + (i % 4))]) for i in range(4)]
    area_a = area(1000, 1000, 7, tiles_a)
    # crafting tables: three in a hall (one with an action id whose low byte must be escaped? 38909 = 0x97FD), one alone
    tiles_b = [tile(1, 1, [item(1650, 38820)]), tile(3, 1, [item(1650, 38822)]), tile(5, 1, [item(1650, 38826)])]
    area_b = area(1100, 1000, 6, tiles_b)
    area_c = area(2000, 2000, 7, [tile(7, 7, [item(1650, 38824)]), tile(30, 30, [item(2590)])])
    towns = node(12, b'', town(1, 'Oldname', 1005, 1005, 7) + town(2, 'Kindle Isle', 3000, 3000, 7))
    data = node(2, b'', area_a + area_b + area_c + towns)
    root = node(0, struct.pack('<IHHII', 2, 100, 100, 3, 57), data)
    return b'\0\0\0\0' + root


ITEMS = """<?xml version="1.0"?>
<items>
\t<item id="100" name="grass" />
\t<item fromid="2589" toid="2592" article="a" name="locker">
\t\t<attribute key="type" value="depot" />
\t</item>
\t<item id="2593" name="mailbox" />
</items>
"""

SPAWN = """<?xml version="1.0"?>
<spawns>
\t<spawn centerx="1010" centery="1010" centerz="7" radius="2">
\t\t<npc name="Quillon" x="1" y="-1" z="7" spawntime="60" />
\t\t<monster name="Ashrat" x="0" y="0" z="7" spawntime="60" />
\t</spawn>
\t<spawn centerx="1020" centery="1000" centerz="7" radius="1">
\t\t<npc name="Captain Brine" x="0" y="0" z="7" spawntime="60" />
\t</spawn>
\t<spawn centerx="5000" centery="5000" centerz="8" radius="1">
\t\t<npc name="Hoarder" x="0" y="0" z="8" spawntime="60" />
\t</spawn>
\t<spawn centerx="1030" centery="1030" centerz="7" radius="1">
\t\t<npc name="Guard" x="0" y="0" z="7" spawntime="60" />
\t</spawn>
</spawns>
"""

NPCS = {
    'Quillon.xml': ('<npc name="Quillon" script="q.lua"><parameters><parameter key="module_shop" value="1" />'
                    '<parameter key="shop_buyable" value="x" /></parameters></npc>', 'q.lua', '-- shop'),
    'Captain Brine.xml': ('<npc name="Captain Brine" script="c.lua"></npc>', 'c.lua',
                          'local travelNode = keywordHandler:addKeyword({"x"}, StdModule.travel, {})'),
    'Hoarder.xml': ('<npc name="Hoarder" script="h.lua"></npc>', 'h.lua',
                    "if msgcontains(msg, 'deposit') then end\nif msgcontains(msg, 'withdraw') then end"),
    'Guard.xml': ('<npc name="Guard" script="g.lua"></npc>', 'g.lua', '-- says hello'),
}

POOL = """return {
\thunt = {
\t\t{name = "Ashrat", level = 4, exp = 5, health = 20, spawns = 508, look = 21},
\t\t{name = "Cinder Rat", level = 6, exp = 10, health = 30, spawns = 402, look = 56},
\t\t{name = "Wyrm", level = 90, exp = 700, health = 1000, spawns = 50, look = 34},
\t\t{name = "Wyrm Lord", level = 140, exp = 2100, health = 1900, spawns = 20, look = 39},
\t},
\tbosses = {
\t\t{name = "Big Boss", level = 500},
\t}
}
"""

BESTIARY = """return {
\t["ashrat"] = {spawns = 508, areas = {{1100, 1100, 8, 20}, {4000, 4000, 9, 3}}},
\t["cinder rat"] = {spawns = 402, areas = {{1110, 1105, 8, 10}}},
\t["wyrm"] = {spawns = 50, areas = {{1500, 1500, 9, 30}}},
\t["wyrm lord"] = {spawns = 20, areas = {{1520, 1490, 9, 12}}},
\t["big boss"] = {spawns = 1, areas = {{1500, 1500, 9, 1}}},
}
"""

BOSSES = """return {
\tbosses = {
\t\t{key = "dreadscale", category = "island", name = "Dreadscale the Ancient", monster = "X",
\t\t\tloc = "Dreadscale Island", pos = {x = 1314, y = 1524, z = 9}, rule = {type = "weekly"}},
\t\t{key = "wb", category = "world", name = "Kaelgor", monster = "Kaelgor", rule = {type = "slot"}},
\t\t{key = "lair_x", category = "lair", name = "Apocalypse", monster = "Apocalypse",
\t\t\tpos = {x = 1600, y = 1600, z = 6}, radius = 12, rule = {type = "timer", seconds = 60}},
\t}
}
"""


def write(path, text, mode='w'):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, mode) as f:
        f.write(text)


def make_server(root):
    data = os.path.join(root, 'data')
    write(os.path.join(root, 'config.lua'), 'mapName = "testmap"\n')
    write(os.path.join(data, 'world', 'testmap.otbm'), build_map(), 'wb')
    write(os.path.join(data, 'world', 'testmap-spawn.xml'), SPAWN)
    write(os.path.join(data, 'items', 'items.xml'), ITEMS)
    for fname, (xml, script, body) in NPCS.items():
        write(os.path.join(data, 'npc', fname), xml)
        write(os.path.join(data, 'npc', 'scripts', script), body)
    chaos = os.path.join(data, 'scripts', 'chaos')
    write(os.path.join(chaos, 'bounty_pool.lua'), POOL)
    write(os.path.join(chaos, 'bestiary_spawns.lua'), BESTIARY)
    write(os.path.join(chaos, 'bossspawns_config.lua'), BOSSES)
    return data


# ------------------------------------------------------------------------------------------------ pure parts
eq(G.level_band([(4, 20), (6, 10)]), (1, 10), 'band of small ones')
eq(G.level_band([(90, 30), (140, 12)]), (90, 140), 'band of big ones')
eq(G.level_band([(95, 1), (100, 98), (300, 1)]), (100, 110), 'the middle, not the outliers')
eq(G.level_band([]), None, 'no weight')
groups = G.cluster([(0, 0, 7, 1, 'a'), (5, 5, 7, 1, 'b'), (100, 0, 7, 1, 'c'), (0, 0, 8, 1, 'd')], 10)
eq(len(groups), 3, 'clusters: near ones joined, far one and other floor apart')
eq(sorted(len(g['items']) for g in groups), [1, 1, 2], 'cluster sizes')
eq(G.title('dragon lord'), 'Dragon Lord', 'title case')
eq(G.esc(b'\xfd\x01\xfe'), b'\xfd\xfd\x01\xfd\xfe', 'escape')
eq(G.payload(b'\x01\xfd\xfe\x02\xff', 0), b'\x01\xfe\x02', 'unescaped payload')
eq(G.lua_string('a "b" \\c'), '"a \\"b\\" \\\\c"', 'Lua string escaping')
kept, dropped = G.drop_old_names([{'n': 'Temple of Oldname'}, {'n': 'Temple of Cinderhold'}], {digest('oldname')})
eq(dropped, 1, 'an old name is dropped'); eq([m['n'] for m in kept], ['Temple of Cinderhold'], 'the new one kept')

# ------------------------------------------------------------------------------------------------ a whole server
tmp = tempfile.mkdtemp(prefix='gen_poi_test_')
try:
    data_dir = make_server(tmp)
    marks, stats = G.generate(tmp)
    eq(stats['towns'], 2, 'towns read'); eq(stats['lockers'], 5, 'lockers found'); eq(stats['tables'], 4, 'tables found')
    eq(stats['npcs'], 4, 'NPC entries read')
    by = {}
    for m in marks:
        by.setdefault(m['k'], []).append(m)
    temples = sorted(m['n'] for m in by['temple'])
    # town 1's map name is unknown to the CSV, so it is "Temple of Oldname" unless base_towns.csv knows id 1
    names = G.read_town_names(os.path.join(HERE, 'base_towns.csv'))
    want1 = 'Temple of ' + names[1] if 1 in names else 'Temple of Oldname'
    want2 = 'Temple of ' + names[2] if 2 in names else 'Temple of Kindle Isle'
    eq(temples, sorted([want1, want2]), 'temples named by town id')
    eq(len(by['depot']), 1, 'one depot (the lone locker is left out)')
    d = by['depot'][0]
    eq((d['x'], d['y'], d['z']), (1012, 1010, 7), 'depot at the lockers\' centre')
    ok(d['n'].startswith('Depot, '), 'depot named after the town')
    crafts = sorted((m['x'], m['y'], m['z'], m['n']) for m in by['craft'])
    eq(crafts, [(1103, 1001, 6, 'Crafting hall'), (2007, 2007, 7, 'Jewelsmith table')], 'crafting hall and a lone table')
    eq([(m['n'], m['r']) for m in by['shop']], [('Quillon (shop)', 0)], 'shop in town: always')
    eq([(m['n'], m['r']) for m in by['travel']], [('Captain Brine (travel)', 0)], 'travel in town: always')
    eq([(m['n'], m['r']) for m in by['bank']], [('Hoarder (bank)', 1)], 'a banker far from town: discovered')
    ok('Guard' not in ' '.join(m['n'] for m in marks), 'an NPC without a service is no mark')
    hunts = sorted(m['n'] for m in by['hunt'])
    eq(hunts, ['Hunting: Ashrat, Cinder Rat (level 1-20)', 'Hunting: Wyrm, Wyrm Lord (level 180-280)'], 'hunting areas print the hunting level (pool x baseLevelMult 2)')
    eq(G.base_level_mult(os.path.join(tmp, 'nowhere')), 2, 'baseLevelMult read from the repo pace_config.lua')
    h3 = G.hunting_areas({'Ashrat': 4, 'Wyrm': 90}, {'ashrat': [(1, 1, 7, 20)], 'wyrm': [(500, 500, 7, 20)]}, 3)
    eq(sorted(m['n'] for m in h3), ['Hunting: Ashrat (level 1-30)', 'Hunting: Wyrm (level 270-300)'], 'mult 3: lo = max(1, lo10*3), hi = hi10*3')
    ok(all(m['r'] == 1 for m in by['hunt']), 'hunting areas are discovered')
    ok(not any('Big Boss' in m['n'] for m in marks), 'the bounty pool\'s bosses are no hunting area')
    eq(sorted(m['n'] for m in by['boss']), ['Apocalypse (boss lair)', 'Dreadscale the Ancient (island boss)'], 'bosses')
    ok(all(m['r'] == 1 for m in by['boss']), 'bosses are discovered')
    text = G.render(marks)
    eq(G.render(G.generate(tmp)[0]), text, 'deterministic')
    ok(text.startswith('-- Points of interest'), 'header')
    ok('testmap' not in text, 'the map name is not written')
    # the command line: write, unchanged, --check, --map
    tool = os.path.join(HERE, 'gen_poi.py')
    run = lambda *a: subprocess.run([sys.executable, '-I', tool] + list(a), stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, universal_newlines=True)
    r = run(tmp)
    eq(r.returncode, 0, 'tool runs: ' + r.stdout)
    out = os.path.join(data_dir, 'chaos_poi.lua')
    ok(os.path.isfile(out), 'data/chaos_poi.lua written')
    eq(open(out).read(), text, 'the file is the rendered text')
    ok('unchanged' in run(tmp).stdout, 'second run: unchanged')
    eq(run(tmp, '--check').returncode, 0, '--check: up to date')
    with open(out, 'a') as f:
        f.write('-- edited\n')
    eq(run(tmp, '--check').returncode, 1, '--check: differs')
    copy = os.path.join(tmp, 'copy')
    shutil.copytree(data_dir, os.path.join(copy, 'data'), ignore=shutil.ignore_patterns('*.otbm'))
    shutil.copy(os.path.join(tmp, 'config.lua'), copy)
    eq(run(copy).returncode, 1, 'no map: fails')
    r = run(copy, '--map', os.path.join(data_dir, 'world', 'testmap.otbm'))
    eq(r.returncode, 0, '--map reads another map: ' + r.stdout)
    eq(open(os.path.join(copy, 'data', 'chaos_poi.lua')).read(), text, '--map gives the same marks')
    # the output loads as Lua (when an interpreter is there)
    lua = shutil.which('luajit') or shutil.which('lua5.3')
    if lua:
        p = subprocess.run([lua, '-e', 'local t = dofile(%r); print(#t.marks, t.version)' % out],
                           stdout=subprocess.PIPE, universal_newlines=True)
        ok(p.stdout.split()[0] == str(len(marks)), 'loads as Lua: ' + p.stdout)
finally:
    shutil.rmtree(tmp)

print('gen_poi_test: %d checks, %d failed' % (checks, fails))
sys.exit(1 if fails else 0)
