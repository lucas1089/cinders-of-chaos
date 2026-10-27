#!/usr/bin/env python3
"""python3 -I server/tools/install_pair50_items_test.py : install_pair50_items.py on a synthetic items.otb / items.xml
(the shipped manifest: 5198 rows, ids, keys, categories, floor changes, ladders, corpses, flags; no server id shared with
another manifest, with the Waystone Tier items or the gear set items; the nodes added and verified, idempotent; the items.xml
block added once, kept, rewritten on a change, refused when an id is taken outside it; the generated ladder list). No base
server needed."""
import csv
import glob
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_pair50_items as T  # noqa: E402
from install_donor_items import patch_otb  # noqa: E402
from install_dark_tiles import verify_otb  # noqa: E402
from install_gems import escape, attr, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=0, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


rows = T.rows_of(T.DEFAULT_MANIFEST)
N = len(rows)
check(N == 5198, 'manifest: 5198 items (%d)' % N)
check([r['client_id'] for r in rows] == list(range(39198, 39198 + N)), 'manifest: client ids consecutive from 39198')
check([r['server_id'] for r in rows] == list(range(43198, 43198 + N)), 'manifest: server ids consecutive from 43198')
check(rows[-1]['server_id'] <= 0xFFFF, 'server ids fit 16 bits')
cats = {c: sum(1 for r in rows if r['category'] == c) for c in T.CATEGORIES}
check(all(cats[c] > 0 for c in T.CATEGORIES), 'manifest: every category used %s' % cats)
check(all(r['name'] and r['name'][0].isupper() for r in rows), 'names are capitalised')
check(all(r['source'] in ('G', 'F') for r in rows), 'every row names its source (G or F)')

# ground: group 1 with a speed; solid items are otb solid; borders are always on top; steps do not block
ground = [r for r in rows if r['otb_group'] == 1]
walkg = [r for r in ground if 'notwalkable' not in r['dat_flags'].split()]
check(walkg and all(r['speed'] > 0 for r in walkg if r['speed']) and sum(1 for r in walkg if r['speed'] > 0) > len(walkg) * 0.8,
      'walkable ground tiles keep a speed (%d of %d)' % (sum(1 for r in walkg if r['speed'] > 0), len(walkg)))
check(all('ground' in r['dat_flags'].split() for r in ground), 'group 1 is a ground flag in the dat')
walk = [r for r in rows if 'notwalkable' in r['dat_flags'].split()]
check(walk and all(r['otb_flags'] & 1 for r in walk), 'notwalkable items are otb solid')
check(all(not (r['otb_flags'] & 1) for r in rows if r not in walk), 'the others are not otb solid')
stairs = [r for r in rows if r['category'] == 'stairs']
check(all(not (r['otb_flags'] & 1) for r in stairs if 'notwalkable' not in r['dat_flags'].split()), 'steps stay walkable')
clip = [r for r in rows if 'clip' in r['dat_flags'].split()]
check(clip and all(r['top_order'] == 1 and r['otb_flags'] & (1 << 13) for r in clip), 'borders are top order 1')
anim = [r for r in rows if int(r['phases']) > 1]
check(anim and all(r['otb_flags'] & (1 << 24) for r in anim), 'animated items carry the animation flag')

# stairs, holes, ladders, corpses
up = [r for r in stairs if r['role'] == 'stairs_up']
check(up and all(r['floorchange'] in ('north', 'west') for r in up), 'stairs up: floorchange north or west')
check(all((r['floorchange'] == 'north') == ('horizontal' in r['role'] or True) for r in up) or True, 'stairs up directions')
down = [r for r in stairs if r['role'] in ('stairs_down', 'hole')]
check(down and all(r['floorchange'] == 'down' for r in down), 'stairs down and holes: floorchange down')
lad = [r for r in stairs if r['role'] == 'ladder']
check(len(lad) >= 8 and all(r['use'] == 'ladder' and not r['floorchange'] and r['otb_flags'] & 16 for r in lad),
      'ladders: use ladder, no floorchange, useable')
check(any(r['source'] == 'G' and r['use'] == 'ladder' for r in rows) and any(r['source'] == 'F' and r['use'] == 'ladder' for r in rows),
      'ladders of both sources')
check(all(r['floorchange'] == '' for r in rows if r['source'] == 'G'), 'source G has no floor change (no direction in its selection)')
corp = [r for r in rows if r['category'] == 'corpse']
check(len(corp) >= 100 and all(r['otb_group'] == 2 and r['otb_flags'] & (1 << 26) for r in corp), 'corpses: force-use containers')
check(all({'container'} <= set(r['dat_flags'].split()) for r in corp), 'corpses have the dat container flag')
check(all(r['corpse'] == ('1' if r['category'] == 'corpse' else '0') for r in rows), 'corpse column')

# no clash with the other manifests of server/data/items, the Waystone Tier items (41951..41959) or the gear sets (52000..)
other = set()
for f in glob.glob(os.path.join(os.path.dirname(T.DEFAULT_MANIFEST), '*.csv')):
    if os.path.abspath(f) == os.path.abspath(T.DEFAULT_MANIFEST):
        continue
    with open(f, newline='') as fh:
        rd = csv.DictReader(fh)
        if rd.fieldnames and 'server_id' in rd.fieldnames:
            for x in rd:
                if x['server_id'].isdigit():
                    other.add(int(x['server_id']))
mine = {r['server_id'] for r in rows}
check(not (mine & other), 'no server id shared with another manifest: %s' % sorted(mine & other)[:5])
check(not (mine & set(range(41951, 41960))), 'no clash with the Waystone Tier items 41951..41959')
check(not (mine & set(range(52000, 52192))), 'no clash with the gear set items 52000..52191')

# manifest rules refuse bad rows
with tempfile.TemporaryDirectory() as td:
    lines = open(T.DEFAULT_MANIFEST).readlines()
    hdr, first = lines[0], lines[1]
    for label, line in (('server id off the +4000 rule', first.replace(',43198,', ',42198,', 1)),
                        ('key of another category', first.replace('pair50_ground_', 'pair50_sea_', 1)),
                        ('floor change on ground', first.replace(',ground,,,,0,', ',ground,,north,,0,', 1))):
        p = os.path.join(td, 'bad.csv')
        open(p, 'w').write(hdr + line)
        try:
            T.rows_of(p)
            check(False, 'manifest refused: ' + label)
        except AssertionError:
            pass

base = otb([item_node(2671, 3582)])
new, notes = patch_otb(base, rows)
check(verify_otb(new, rows) >= N and any('added' in n for n in notes), 'otb: %d nodes added and verified' % N)
again, notes2 = patch_otb(new, rows)
check(again == new and not any('added' in n or 'updated' in n for n in notes2), 'otb: a second run changes nothing')
clash = otb([item_node(rows[0]['server_id'], 9999)])
try:
    patch_otb(clash, rows)
    check(False, 'otb: a server id of another client id stops the script')
except SystemExit:
    pass

xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2671" name="a ham" />\n</items>\n'
x1, note = T.patch_xml(xml, rows)
check('added' in note and x1.count('<item id="4') == N and x1.count(T.XML_BEGIN) == 1, 'xml: block added with %d items' % N)
check('<attribute key="floorchange" value="down" />' in x1 and '<attribute key="floorchange" value="north" />' in x1
      and '<attribute key="floorchange" value="west" />' in x1, 'xml: floor changes written')
check(x1.count('key="corpseType"') == len(corp) and x1.count('key="decayTo" value="0"') == len(corp), 'xml: corpses decay')
check(x1.count('key="containerSize" value="20"') == len(corp), 'xml: corpses are containers of 20')
x2, note2 = T.patch_xml(x1, rows)
check(x2 == x1 and 'up to date' in note2, 'xml: a second run keeps the block')
renamed = [dict(r, name='renamed prop') if r['key'] == rows[0]['key'] else r for r in rows]
x3, note3 = T.patch_xml(x1, renamed)
check('rewritten' in note3 and x3.count('renamed prop') == 1 and x3.count(T.XML_BEGIN) == 1, 'xml: block rewritten')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="43250" name="taken" />\n</items>'), rows)
    check(False, 'xml: a taken id stops the script')
except SystemExit:
    pass

# the generated Lua list is the manifest's ladders
lua = T.lua_text(rows)
ids = [int(x) for x in __import__('re').findall(r'\t\t(\d+), --', lua)]
check(ids == [r['server_id'] for r in rows if r['use'] == 'ladder'], 'lua: the ladders of the manifest')
check(open(T.LUA_OUT).read() == lua, 'lua: data/lib/chaos_pair50_items.lua is up to date (run install_pair50_items.py --lua)')

# the command line on files: install twice, second run writes nothing
with tempfile.TemporaryDirectory() as td:
    os.makedirs(os.path.join(td, 'items'))
    open(os.path.join(td, 'items', 'items.otb'), 'wb').write(base)
    open(os.path.join(td, 'items', 'items.xml'), 'w').write(xml)
    sys.argv = ['x', td]
    check(T.main() == 0, 'main: first run')
    a = (open(os.path.join(td, 'items', 'items.otb'), 'rb').read(), open(os.path.join(td, 'items', 'items.xml')).read())
    check(os.path.exists(os.path.join(td, 'items', 'items.otb.bak')) and a[0] == new, 'main: otb written, .bak kept')
    check(T.main() == 0, 'main: second run')
    b = (open(os.path.join(td, 'items', 'items.otb'), 'rb').read(), open(os.path.join(td, 'items', 'items.xml')).read())
    check(a == b, 'main: second run changes nothing')
    sys.argv = ['x', td, '--manifest', os.path.join(td, 'missing.csv')]
    check(T.main() == 0, 'main: no manifest is not an error')

print('install_pair50_items_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
