#!/usr/bin/env python3
"""python3 -I server/tools/install_store_food_test.py : install_store_food.py on a synthetic items.otb / items.xml
(the config read from store_food_config.lua, the node copied from the stock food node, stackable as that node is, the
stock look while ownLook is false and our look when it is true, idempotent, an id taken by another item stops it,
the items.xml block added once and rewritten on a change). No base server needed."""
import os, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_store_food as T  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=FLAG_STACKABLE, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


shipped = T.read_config()
check(shipped['ownLook'] is True, 'config: our look, on since 2026-10-14 (things_custom25 on windows-assets)')
cfg = dict(shipped, ownLook=False)   # the stock look first, then ownLook
check(cfg['id'] == 32084 and cfg['sourceId'] == 2672, 'config: ids')
check(cfg['clientId'] == 38611, 'config: our look of pair 34 (after the pair 33 items, 38607)')
check(cfg['oldClientId'] == 33904, 'config: the earlier look of things_custom25')
check('never runs out' in cfg['description'], 'config: description read (joined strings)')

base = otb([item_node(2671, 3582), item_node(2672, 3583), item_node(2673, 3584, 0)])
new, note, want, cid = T.patch_otb(base, cfg)
check('added' in note and cid == 3583, 'node added with the dragon ham look')
kids, _ = scan(new)
by = {k[2]: k for k in kids}
check(32084 in by and by[32084][3] == 3583, 'server id 32084 -> client 3583')
check(by[32084][5] & FLAG_STACKABLE, 'stackable like its look (the dragon ham): the client reads a count for a stackable '
      'thing, a non-stackable server item broke the container packet (live test 2026-10-14)')
check(by[2672][5] & FLAG_STACKABLE, 'the dragon ham stays stackable')
check(T.verify_otb(new, cfg, want, cid) == 4, 'verified, four nodes')
# an older install (the ration made not stackable) is updated in place
old_node = item_node(32084, 3583, 0)
older = otb([item_node(2671, 3582), item_node(2672, 3583), item_node(2673, 3584, 0), old_node])
fixed, note_f, want_f, cid_f = T.patch_otb(older, cfg)
by_f = {k[2]: k for k in scan(fixed)[0]}
check('updated' in note_f and by_f[32084][5] & FLAG_STACKABLE, 'a non-stackable ration from an older install is fixed')
check(T.verify_otb(fixed, cfg, want_f, cid_f) == 4, 'fixed node verified')
again, note2, _, _ = T.patch_otb(new, cfg)
check(again == new and 'present' in note2, 'idempotent')
own = dict(cfg, ownLook=True)
mine, note3, want3, cid3 = T.patch_otb(new, own)
check(cid3 == 38611 and 'updated' in note3, 'ownLook: the node gets our look')
check(T.verify_otb(mine, own, want3, cid3) == 4, 'own look verified')
# an install with the earlier look (33904, things_custom25) gets the new one in place
earlier = otb([item_node(2671, 3582), item_node(2672, 3583), item_node(2673, 3584, 0), item_node(32084, 33904)])
up, note5, want5, cid5 = T.patch_otb(earlier, own)
check(cid5 == 38611 and 'updated' in note5 and T.verify_otb(up, own, want5, cid5) == 4, 'the earlier look is replaced')
again5, note6, _, _ = T.patch_otb(up, own)
check(again5 == up and 'present' in note6, 'idempotent after the look change')
back, note4, _, _ = T.patch_otb(mine, cfg)
check(back == new and 'updated' in note4, 'back to the stock look')
taken = otb([item_node(2672, 3583), item_node(32084, 9999, 0)])
try:
    T.patch_otb(taken, cfg)
    check(False, 'a foreign item on 32084 must stop the install')
except SystemExit as e:
    check('already belongs' in str(e), 'a foreign item on 32084 stops the install')
try:
    T.patch_otb(otb([item_node(2671, 3582)]), cfg)
    check(False, 'no source node must stop the install')
except SystemExit as e:
    check('no stock node' in str(e), 'no dragon ham: stop')
clash = otb([item_node(2672, 3583), item_node(40000, 38611, 0)])
try:
    T.patch_otb(clash, own)
    check(False, 'our client id on another node must stop')
except SystemExit as e:
    check('already used' in str(e), 'our client id on another node: stop')

xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2672" name="dragon ham" />\n</items>\n'
x1, n1 = T.patch_xml(xml, cfg)
check('added' in n1 and x1.count('id="32084"') == 1, 'items.xml: block added')
x2, n2 = T.patch_xml(x1, cfg)
check(x2 == x1 and 'up to date' in n2, 'items.xml: idempotent')
x3, n3 = T.patch_xml(x1, dict(cfg, weight=400))
check('rewritten' in n3 and x3.count('id="32084"') == 1 and 'value="400"' in x3, 'items.xml: rewritten on a change')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="32084" name="other" />\n</items>'), cfg)
    check(False, 'an entry outside the block must stop')
except SystemExit:
    check(True, '')

with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, 'items'))
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(base)
    open(os.path.join(d, 'items', 'items.xml'), 'w').write(xml)
    check(T.main([d, '--dry-run']) == 0, 'dry run')
    check(open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == base, 'dry run writes nothing')
    check(T.main([d]) == 0, 'install')
    check(os.path.exists(os.path.join(d, 'items', 'items.otb.bak')), 'items.otb.bak kept')
    first = open(os.path.join(d, 'items', 'items.otb'), 'rb').read()
    check(T.main([d]) == 0 and open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == first, 'second run: no change')

print('install_store_food_test: OK' if failed == 0 else 'install_store_food_test: %d failed' % failed)
sys.exit(1 if failed else 0)
