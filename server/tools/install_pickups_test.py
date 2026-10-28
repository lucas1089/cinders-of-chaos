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
check(rows['health_globe']['clientId'] == 44397 and rows['health_globe']['stockClientId'] == 7618 and rows['health_globe']['stackable'] is True
      and rows['mana_globe']['clientId'] == 44398 and rows['mana_globe']['stockClientId'] == 7620 and rows['mana_globe']['stackable'] is True,
      'config: the globe looks (44397 / 44398, nodes copied from the potion client ids 7618 / 7620), stackable')
check(rows['ember']['clientId'] == 44396 and rows['ember']['stockClientId'] == 25045 and rows['ember']['stackable'] is True,
      'config: the ember look (portal 44396, node copied from 25045), stackable')
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
check(by[32088][3] == 44397 and by[32089][3] == 44398 and by[32090][3] == 44396, 'own looks: globes 44397 / 44398, ember 44396')
check(all(by[s][5] & FLAG_STACKABLE for s in (32088, 32089, 32090)), 'all three are stackable (forced, also the mana globe)')
check(by[7618][3] == 7618 and by[7620][3] == 7620 and not (by[7620][5] & FLAG_STACKABLE), 'the stock potion nodes stay as they are')
check(by[7618][5] & FLAG_PICKUPABLE, 'the stock node stays pickupable')
check(T.verify_otb(new, wanted) == 7, 'verified, seven nodes')
again, notes2, _ = T.patch_otb(new, cfg)
check(again == new and all('present' in n for n in notes2), 'idempotent')
# an older node with other flags is replaced in place
older = otb([item_node(7618, 7618, FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE), item_node(7620, 7620),
             item_node(30000, 25045), item_node(32088, 7618, FLAG_PICKUPABLE | FLAG_MOVEABLE)])
fixed, notes3, w3 = T.patch_otb(older, cfg)
check(any('updated' in n for n in notes3) and T.verify_otb(fixed, w3) == 6, 'a pickupable older node is fixed')
# a node of an older install (the ember on the orb look 25045) is moved to the portal look; the orb's stock node stays
old_ember = otb([item_node(7618, 7618, FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE), item_node(7620, 7620),
                 item_node(30000, 25045), item_node(32090, 25045, FLAG_STACKABLE)])
moved, notes4, w4 = T.patch_otb(old_ember, cfg)
mk = {k[2]: k for k in scan(moved)[0]}
check(any('ember' in n and 'updated' in n for n in notes4) and mk[32090][3] == 44396 and mk[30000][3] == 25045 and T.verify_otb(moved, w4),
      'an older ember node on 25045 is rewritten to 44396')
# nodes of an older install (the globes on the potion looks 7618 / 7620) are moved to the globe looks; the stock nodes stay
old_globes = otb([item_node(7618, 7618, FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE), item_node(7620, 7620),
                  item_node(30000, 25045), item_node(32088, 7618, FLAG_STACKABLE), item_node(32089, 7620)])
mg, notes5, w5 = T.patch_otb(old_globes, cfg)
mg_by = {k[2]: k for k in scan(mg)[0]}
check(sum('updated' in n for n in notes5) == 2 and mg_by[32088][3] == 44397 and mg_by[32089][3] == 44398
      and mg_by[7618][3] == 7618 and mg_by[7620][3] == 7620 and T.verify_otb(mg, w5), 'older globe nodes on 7618 / 7620 are rewritten to 44397 / 44398')
# the new client id belongs to another server id: stop
try:
    T.patch_otb(otb([item_node(7618, 7618), item_node(7620, 7620), item_node(30000, 25045), item_node(31999, 44396)]), cfg)
    check(False, 'a foreign item on client id 44396 must stop the install')
except SystemExit as e:
    check('44396' in str(e) and 'belongs to server id' in str(e), 'a foreign item on client id 44396 stops the install')
try:
    T.patch_otb(otb([item_node(7618, 7618), item_node(7620, 7620), item_node(30000, 25045), item_node(31998, 44398)]), cfg)
    check(False, 'a foreign item on client id 44398 must stop the install')
except SystemExit as e:
    check('44398' in str(e) and 'belongs to server id' in str(e), 'a foreign item on client id 44398 stops the install')
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
    check('no stock node' in str(e), 'no stock node with client id 25045 (the ember source): stop')

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

with tempfile.TemporaryDirectory() as srv:
    d = os.path.join(srv, 'data')  # the step reads the recorded client pair from SERVER/config.lua (client_pair.py)
    os.makedirs(os.path.join(d, 'items'))
    open(os.path.join(srv, 'config.lua'), 'w').write('chaosClientPair = 55\n')
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(base)
    open(os.path.join(d, 'items', 'items.xml'), 'w').write(xml)
    check(T.main([d, '--dry-run']) == 0 and open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == base, 'dry run writes nothing')
    check(T.main([d]) == 0, 'install')
    check(os.path.exists(os.path.join(d, 'items', 'items.otb.bak')), 'items.otb.bak kept')
    first = open(os.path.join(d, 'items', 'items.otb'), 'rb').read()
    check(T.main([d]) == 0 and open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == first, 'second run: no change')

print('install_pickups_test: OK' if failed == 0 else 'install_pickups_test: %d failed' % failed)
sys.exit(1 if failed else 0)
