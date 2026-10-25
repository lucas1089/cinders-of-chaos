#!/usr/bin/env python3
"""python3 -I server/tools/install_pickups_test.py : install_pickups.py on a synthetic items.otb / items.xml (the config
read from pickups_config.lua, nodes copied from the stock nodes of a server id and of a client id, never pickupable or
moveable, stackable as the row says, idempotent, an id taken by another item stops it, the items.xml block added once
and rewritten on a change). No base server needed."""
import os, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_pickups as T  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=FLAG_PICKUPABLE | FLAG_MOVEABLE, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


cfg = T.read_config()
rows = {r['key']: r for r in cfg['items']}
check(set(rows) == {'health_globe', 'mana_globe', 'ember'}, 'config: three items')
check(rows['health_globe']['id'] == 32088 and rows['mana_globe']['id'] == 32089 and rows['ember']['id'] == 32090, 'config: ids')
check(rows['health_globe']['sourceId'] == 7618 and rows['mana_globe']['sourceId'] == 7620, 'config: potion looks')
check(rows['ember']['clientId'] == 25045 and rows['ember']['stackable'] is True, 'config: the ember look, stackable')
check('Step on it' in rows['health_globe']['description'], 'config: description read')
check(cfg['failsafe'] > 0, 'config: failsafe seconds')

base = otb([item_node(7618, 7618, FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE), item_node(7620, 7620),
            item_node(30000, 25045, FLAG_PICKUPABLE | FLAG_MOVEABLE), item_node(30001, 25045)])
new, notes, wanted = T.patch_otb(base, cfg)
check(all('added' in n for n in notes) and len(notes) == 3, 'three nodes added')
kids, _ = scan(new)
by = {k[2]: k for k in kids}
for sid in (32088, 32089, 32090):
    check(sid in by and not (by[sid][5] & (FLAG_PICKUPABLE | FLAG_MOVEABLE)), '%d: neither pickupable nor moveable' % sid)
check(by[32088][3] == 7618 and by[32089][3] == 7620 and by[32090][3] == 25045, 'looks of the sources')
check(by[32088][5] & FLAG_STACKABLE, 'stackable like the stock potion')
check(not (by[32089][5] & FLAG_STACKABLE), 'not stackable like its source')
check(by[32090][5] & FLAG_STACKABLE, 'the ember is stackable (forced)')
check(by[7618][5] & FLAG_PICKUPABLE, 'the stock node stays pickupable')
check(T.verify_otb(new, wanted) == 7, 'verified, seven nodes')
again, notes2, _ = T.patch_otb(new, cfg)
check(again == new and all('present' in n for n in notes2), 'idempotent')
# an older node with other flags is replaced in place
older = otb([item_node(7618, 7618, FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE), item_node(7620, 7620),
             item_node(30000, 25045), item_node(32088, 7618, FLAG_PICKUPABLE | FLAG_MOVEABLE)])
fixed, notes3, w3 = T.patch_otb(older, cfg)
check(any('updated' in n for n in notes3) and T.verify_otb(fixed, w3) == 6, 'a pickupable older node is fixed')
taken = otb([item_node(7618, 7618), item_node(7620, 7620), item_node(30000, 25045), item_node(32089, 9999)])
try:
    T.patch_otb(taken, cfg)
    check(False, 'a foreign item on 32089 must stop the install')
except SystemExit as e:
    check('already belongs' in str(e), 'a foreign item on 32089 stops the install')
try:
    T.patch_otb(otb([item_node(7618, 7618), item_node(7620, 7620)]), cfg)
    check(False, 'no stock node for the ember must stop')
except SystemExit as e:
    check('no stock node' in str(e), 'no stock node with client id 25045: stop')

xml = '<?xml version="1.0"?>\n<items>\n\t<item id="7618" name="health potion" />\n</items>\n'
x1, n1 = T.patch_xml(xml, cfg)
check('added' in n1 and all(x1.count('id="%d"' % i) == 1 for i in (32088, 32089, 32090)), 'items.xml: block added')
check('key="decayTo" value="0"' in x1 and ('value="%d"' % cfg['failsafe']) in x1, 'items.xml: failsafe decay')
x2, n2 = T.patch_xml(x1, cfg)
check(x2 == x1 and 'up to date' in n2, 'items.xml: idempotent')
x3, n3 = T.patch_xml(x1, dict(cfg, failsafe=30))
check('rewritten' in n3 and x3.count('id="32088"') == 1, 'items.xml: rewritten on a change')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="32090" name="other" />\n</items>'), cfg)
    check(False, 'an entry outside the block must stop')
except SystemExit:
    check(True, '')

with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, 'items'))
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(base)
    open(os.path.join(d, 'items', 'items.xml'), 'w').write(xml)
    check(T.main([d, '--dry-run']) == 0 and open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == base, 'dry run writes nothing')
    check(T.main([d]) == 0, 'install')
    check(os.path.exists(os.path.join(d, 'items', 'items.otb.bak')), 'items.otb.bak kept')
    first = open(os.path.join(d, 'items', 'items.otb'), 'rb').read()
    check(T.main([d]) == 0 and open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == first, 'second run: no change')

print('install_pickups_test: OK' if failed == 0 else 'install_pickups_test: %d failed' % failed)
sys.exit(1 if failed else 0)
