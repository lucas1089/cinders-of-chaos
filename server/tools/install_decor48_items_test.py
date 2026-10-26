#!/usr/bin/env python3
"""python3 -I server/tools/install_decor48_items_test.py : install_decor48_items.py on a synthetic items.otb / items.xml
(the shipped manifest: 352 rows, ids, keys, biomes, flags; no server id shared with another manifest or with the
Waystone Tier items; the nodes added and verified, idempotent; the items.xml block added once, kept, rewritten on a
change, refused when an id is taken outside it; the kit lists). No base server needed."""
import csv
import glob
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_decor48_items as T  # noqa: E402
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
check(len(rows) == 352, 'manifest: 352 items')
check([r['client_id'] for r in rows] == list(range(38759, 39111)), 'manifest: client ids 38759..39110 in order')
check([r['server_id'] for r in rows] == list(range(42759, 43111)), 'manifest: server ids 42759..43110 in order')
per = {b: sum(1 for r in rows if T.biome_of(r) == b) for b in T.BIOMES}
check(per == {'ice': 58, 'swamp': 150, 'lava': 16, 'cave': 128}, 'manifest: items per biome %s' % per)
check(per['ice'] <= 120 and per['swamp'] <= 150 and per['lava'] <= 70 and per['cave'] <= 200, 'manifest: biome limits')
check(all(r['otb_flags'] & 32 == 0 for r in rows), 'no item is pickupable')
check(all(r['server_id'] <= 0xFFFF for r in rows), 'server ids fit 16 bits')
check(all(r['name'] == '%s prop %d' % (T.biome_of(r), 1 + [x for x in rows if T.biome_of(x) == T.biome_of(r)].index(r))
          for r in rows), 'names are "<biome> prop <n>" in order')
block = [r for r in rows if {'notwalkable', 'blockpath'} & set(r['dat_flags'].split())]
check(block and all(r['otb_flags'] & 1 for r in block), 'notwalkable / blockpath items are otb solid')
check(all(not (r['otb_flags'] & 1) for r in rows if r not in block), 'the others are not otb solid')

# no clash with the other manifests of server/data/items, nor with the Waystone Tier items (41951..41959)
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

# manifest rules refuse bad rows
with tempfile.TemporaryDirectory() as td:
    hdr = open(T.DEFAULT_MANIFEST).readline()
    first = open(T.DEFAULT_MANIFEST).readlines()[1]
    for label, line in (('server id off the +4000 rule', first.replace(',42759,', ',41759,', 1)),
                        ('key of another biome shape', first.replace('decor48_ice_', 'decor48_sea_', 1)),
                        ('pickupable', first.replace('8197', '8229', 1))):
        p = os.path.join(td, 'bad.csv')
        open(p, 'w').write(hdr + line)
        try:
            T.rows_of(p)
            check(False, 'manifest refused: ' + label)
        except AssertionError:
            pass

base = otb([item_node(2671, 3582)])
new, notes = patch_otb(base, rows)
check(verify_otb(new, rows) >= 352 and any('added' in n for n in notes), 'otb: 352 nodes added and verified')
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
check('added' in note and x1.count('<item id="4') == 352 and x1.count(T.XML_BEGIN) == 1, 'xml: block added with 352 items')
x2, note2 = T.patch_xml(x1, rows)
check(x2 == x1 and 'up to date' in note2, 'xml: a second run keeps the block')
renamed = [dict(r, name='renamed prop') if r['key'] == rows[0]['key'] else r for r in rows]
x3, note3 = T.patch_xml(x1, renamed)
check('rewritten' in note3 and x3.count('renamed prop') == 1 and x3.count(T.XML_BEGIN) == 1, 'xml: block rewritten')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="42800" name="taken" />\n</items>'), rows)
    check(False, 'xml: a taken id stops the script')
except SystemExit:
    pass

kits = T.kit_json(rows)
check({b: len(v) for b, v in kits.items()} == per, 'kit lists: counts per biome')
check(all(set(e) == {'server_id', 'size', 'kind', 'blocks'} and e['kind'] in ('static', 'animated', 'light')
          for v in kits.values() for e in v), 'kit lists: fields and kinds')
check(any(e['kind'] == 'animated' for e in kits['ice']) and any(e['kind'] == 'animated' for e in kits['lava']),
      'kit lists: animated props found')

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

print('install_decor48_items_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
