#!/usr/bin/env python3
"""python3 -I server/tools/patch_temple_tidy_test.py : patch_temple_tidy.py (O386) on a synthetic map and script.

Map: the listed items go (a teleport with a destination too, every item of a listed id on its tile), the rest of
each tile stays, an item with an action id stays, a missing item or tile is skipped, the ground is never taken; a dry
run writes nothing, --out writes there, a second run changes nothing, <map>.otbm.bak is written once. Texts: the floating text
line at a listed spot with its text goes (CRLF kept), another text at that spot and the other lines stay, no script is
fine. A bad config refuses. The real config: the tidy list names the east purple teleport (all five pieces, two with a
destination in the base map) and not the west one, every spot is in Cinderhold's temple, nothing on the gallery or a
portal alcove, and the Great Brazier's first spot is the freed teleport tile. install_all.py has the step after
startchest. No base server needed (numpy for tools/map/otbm.py)."""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(SERVER), 'tools', 'map'))
import patch_temple_tidy as T  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


MARBLE, PILLAR, LEAVES, BROOM, BASIN = 406, 1515, 12768, 2551, 1481
Z = 7


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


def t(ground, *items, flags=1):
    return dict(flags=flags, ground=ground, items=[i if isinstance(i, tuple) else (i, {}) for i in items])


def base_tiles():
    tiles = {}
    for y in range(10, 20):
        for x in range(10, 20):
            tiles[(x, y, Z)] = t(MARBLE)
    # a five piece teleport: the top row decoration, the bottom row with two destinations
    tiles[(12, 12, Z)] = t(MARBLE, 28016)
    tiles[(13, 12, Z)] = t(MARBLE, PILLAR, 28017)
    tiles[(12, 13, Z)] = t(MARBLE, 28013)
    tiles[(13, 13, Z)] = t(MARBLE, (28014, {'tele': (30, 30, 7)}))
    tiles[(14, 13, Z)] = t(MARBLE, (28015, {'tele': (30, 30, 7)}))
    tiles[(16, 16, Z)] = t(MARBLE, LEAVES, LEAVES, BROOM)                # two leaves: both go
    tiles[(17, 16, Z)] = t(MARBLE, (BASIN, {'aid': 47901}))              # scripted: stays
    tiles[(30, 30, Z)] = t(MARBLE)
    return tiles


TIDY = """return {tidy = {{town = 2, name = "Town", z = 7,
	remove = {{x = 12, y = 12, item = 28016}, {x = 13, y = 12, item = 28017}, {x = 13, y = 12, item = 1515},
		{x = 12, y = 13, item = 28013}, {x = 13, y = 13, item = 28014}, {x = 14, y = 13, item = 28015},
		{x = 16, y = 16, item = 12768}, {x = 16, y = 16, item = 2551}, {x = 17, y = 16, item = 1481},
		{x = 18, y = 18, item = 999}, {x = 50, y = 50, item = 999}, {x = 11, y = 11, item = 406}},
	texts = {{x = 13, y = 13, text = "Teleports"}, {x = 16, y = 16, text = "Collect First Items!"}}}}}
"""

MESSAGES = """local textFloat = GlobalEvent("textFloat")

local effects = {
    {position = Position(1, 1, 7), text = 'Welcome!', effect = 317},
    {position = Position(16, 16, 7), text = 'Collect First Items!', effect = 257},
    {position = Position(13, 13, 7), text = 'Teleports', effect = 316},
    {position = Position(13, 13, 7), text = 'Something else', effect = 316},
    {position = Position(11, 13, 7), text = 'Teleports', effect = 316},
}
"""


def setup(root, tiles=None, tidy=TIDY, messages=MESSAGES):
    data = os.path.join(root, 'data')
    os.makedirs(os.path.join(data, 'world'))
    mp = os.path.join(data, 'world', 'w.otbm')
    open(mp, 'wb').write(otbm_file(tiles or base_tiles()))
    cfg = os.path.join(root, 'tidy.lua')
    open(cfg, 'w').write(tidy)
    if messages is not None:
        p = os.path.join(data, T.MESSAGES)
        os.makedirs(os.path.dirname(p))
        open(p, 'w', newline='').write(messages)
    return data, mp, cfg


def run(data, mp, cfg, **kw):
    log = []
    res = T.run(data, map_path=mp, config=cfg, log=log.append, **kw)
    return res, log


def ids(mp, x, y):
    m = otbm.load_otbm(mp)
    i = m.find(x, y, Z)
    return [int(v) for v in m.stack(i)]


with tempfile.TemporaryDirectory() as d:
    data, mp, cfg = setup(d)
    raw = open(mp, 'rb').read()
    res, log = run(data, mp, cfg, dry=True)
    check(res['items'] == 9 and res['texts'] == 2, 'dry run counts: %s' % res)
    check(open(mp, 'rb').read() == raw and not os.path.exists(mp + '.bak'), 'dry run writes no map')
    check(open(os.path.join(data, T.MESSAGES)).read() == MESSAGES, 'dry run writes no script')
    out = os.path.join(d, 'out.otbm')
    res, log = run(data, mp, cfg, dry=True, out=out)
    check(os.path.isfile(out) and open(mp, 'rb').read() == raw and not os.path.exists(mp + '.bak'), '--out writes there only')
    res, log = run(data, mp, cfg)
    check(res['items'] == 9, 'nine items taken: %s' % res)
    check(ids(mp, 12, 12) == [MARBLE] and ids(mp, 13, 12) == [MARBLE] and ids(mp, 12, 13) == [MARBLE], 'teleport pieces and pillar gone')
    check(ids(mp, 13, 13) == [MARBLE] and ids(mp, 14, 13) == [MARBLE], 'the pieces with a destination gone too')
    check(ids(mp, 16, 16) == [MARBLE], 'both leaves and the broom gone')
    check(ids(mp, 17, 16) == [MARBLE, BASIN], 'an item with an action id stays')
    check(any('action id' in line for line in log), 'the scripted item is listed')
    check(ids(mp, 11, 11) == [MARBLE], 'the ground is never taken')
    check(any('is the ground' in line for line in log), 'a ground in the list is listed')
    check(os.path.isfile(mp + '.bak') and open(mp + '.bak', 'rb').read() == raw, 'backup of the first map')
    check(len(otbm.load_otbm(mp).tiles['x']) == len(base_tiles()), 'tile count kept')
    text = open(os.path.join(data, T.MESSAGES)).read()
    check("text = 'Collect First Items!'" not in text and "Position(13, 13, 7), text = 'Teleports'" not in text,
          'the two listed floating texts gone')
    check("'Something else'" in text and "Position(11, 13, 7), text = 'Teleports'" in text and "'Welcome!'" in text,
          'another text on the spot and the same text elsewhere stay')
    check(text.count('\n') == MESSAGES.count('\n') - 2, 'whole lines cut')
    after = open(mp, 'rb').read()
    res, log = run(data, mp, cfg)
    check(res == dict(items=0, texts=0) and open(mp, 'rb').read() == after, 'a second run changes nothing: %s' % res)
    import map_guard_testkit as K
    K.fault_check(check, IC, lambda p: open(p, 'wb').write(otbm_file(base_tiles())),
                  lambda dd, p: T.run(dd, map_path=p, config=cfg, log=lambda s: None), d, 'temple tidy')
    check(open(os.path.join(data, T.MESSAGES)).read() == text, 'a second run leaves the script')
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_temple_tidy.py'), data, '--map', mp,
                        '--config', cfg], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    check(p.returncode == 0 and b'nothing to take off' in p.stdout, 'the command line: %s' % p.stdout[-200:])

with tempfile.TemporaryDirectory() as d:
    data, mp, cfg = setup(d, messages=MESSAGES.replace('\n', '\r\n'))
    res, log = run(data, mp, cfg)
    text = open(os.path.join(data, T.MESSAGES), newline='').read()
    check(res['texts'] == 2 and text.count('\r\n') == text.count('\n'), 'CRLF kept')

with tempfile.TemporaryDirectory() as d:
    data, mp, cfg = setup(d, messages=None)
    res, log = run(data, mp, cfg)
    check(res['items'] == 9 and res['texts'] == 0 and any('not there' in x for x in log), 'no script: the map alone')

with tempfile.TemporaryDirectory() as d:
    data, mp, cfg = setup(d, tidy='return {tidy = {{z = 7, remove = {{x = 1, item = 2}}}}}')
    try:
        run(data, mp, cfg)
        check(False, 'a bad entry refuses')
    except T.TidyError:
        pass

with tempfile.TemporaryDirectory() as d:
    data, mp, cfg = setup(d, tidy='return {}')
    os.remove(mp)
    res, log = run(data, mp, cfg)
    check(res == dict(items=0, texts=0), 'no tidy list: nothing to do, the map not read')

# ------------------------------------------------------------------------------------------------ the real config
real = IC.load_config(T.CONFIG)
entries = T.entries(real)
check(len(entries) == 1 and entries[0][0] == 'Cinderhold', 'one town: Cinderhold')
name, rem, txt = entries[0]
town = next(tw for tw in real['towns'] if tw['town'] == 2)
tx, ty, tz = town['temple']['x'], town['temple']['y'], town['temple']['z']
east = {((32372, 32235, 7), 28016), ((32373, 32235, 7), 28017), ((32372, 32236, 7), 28013), ((32373, 32236, 7), 28014),
        ((32374, 32236, 7), 28015)}
check(east <= set(rem), 'the east purple teleport: all five pieces')
check(not any(p[0] < tx for p, i in rem if i in (28013, 28014, 28015, 28016, 28017)), 'the west purple teleport stays')
check(((32373, 32235, 7), 1515) in rem, 'the pillar on its top piece goes with it')
gallery = {(x, y) for w in town['wings'] for x in range(w['from'], w['to'] + 1) for y in [town['portalRow']] + town['aisle']}
for p, i in rem + [(q, s) for q, s in txt]:
    check(abs(p[0] - tx) <= 12 and abs(p[1] - ty) <= 8 and p[2] == tz, 'in the temple: %s' % (p,))
    check((p[0], p[1]) not in gallery, 'not on the portal gallery: %s' % (p,))
check(((32373, 32236, 7), 'Teleports') in txt, "the east teleport's floating text goes")
check(((32373, 32240, 7), 'Collect First Items!') in txt, "the removed starter chest's floating text goes")
lua = 'local c = dofile("data/scripts/chaos/community_config.lua") local o = c.brazier.offsets[1] print(c.brazier.townId, o[1], o[2])'
p = subprocess.run(['luajit', '-e', lua], cwd=SERVER, stdout=subprocess.PIPE)
bt, bx, by = (int(v) for v in p.stdout.split())
check(bt == 2 and (tx + bx, ty + by) == (32373, 32236), 'the Great Brazier first takes the freed teleport tile')

text = open(os.path.join(HERE, 'install_all.py'), encoding='utf-8').read()
check("def step_templetidy(" in text and "'patch_temple_tidy.py'" in text, 'install_all.py has the step')
check("STEPS.insert(STEPS.index('startchest') + 1, 'templetidy')" in text and
      'templetidy   tools/patch_temple_tidy.py' in text, 'the step after startchest, in the docstring')

print('patch_temple_tidy_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
sys.exit(1 if failed else 0)
